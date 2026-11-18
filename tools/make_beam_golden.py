"""Generate the v0.3.3 numerical oracle. Run: python3 tools/make_beam_golden.py.

Standard library + real liblua5.4; --lua lua5.1 can reproduce the same sweep.
The fixture remains usable after deleting beam_core.lua. @nan/@inf/@-inf are
explicit input sentinels, keeping invalid cases valid JSON.
"""
import argparse
import ctypes
from datetime import datetime
import hashlib
import json
from pathlib import Path
import random
import subprocess
import tempfile
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parent.parent
SEED = 20261118


def literal(value):
    if value is None:
        return 'nil'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, (float, int)):
        return repr(value)
    if isinstance(value, list):
        return '{' + ','.join(literal(v) for v in value) + '}'
    return '{' + ','.join('[' + literal(k) + ']=' + literal(v) for k, v in value.items()) + '}'


def cases():
    rng = random.Random(SEED)
    out = []
    for i in range(2000):
        L = 1 + 11*rng.random()
        p = dict(L=L, q=-30+60*rng.random(), P=-50+100*rng.random(),
                 a=L*rng.random(), EI=1000+99000*rng.random(), support=1+int(4*rng.random()))
        if i % 20 < 3:
            p['q'] = 0
        if 7 <= i % 20 <= 9:
            p['P'] = 0
        if i % 40 == 0:
            p['a'] = 0
        elif i % 40 == 20:
            p['a'] = L
        out.append(dict(name=f'random_{i:04d}', p=p, limit=250 if rng.random()<.5 else 300,
                        lref_factor=1 if rng.random()<.5 else 2.5, valid=True))
    for support in range(1,5):
        p=dict(L=6,q=10,P=0,a=3,EI=10000,support=support)
        out.append(dict(name=f'P0_{support}',p=p,limit=250,lref_factor=1,valid=True))
        out.append(dict(name=f'zero_{support}',p=dict(p,q=0),limit=300,lref_factor=2.5,valid=True))
        for a in (1e-7,6-1e-7):
            out.append(dict(name=f'near_{support}_{a}',p=dict(p,q=0,P=12,a=a),
                            limit=250,lref_factor=1,valid=True))
    base=dict(L=6,q=10,P=12,a=2,EI=10000,support=1)
    bad=[('L',0),('L',-1),('a',-1),('a',7),('EI',0),('EI',-1),('support',0),('support',5)]
    bad += [(key,value) for key in base for value in ('@nan','@inf','@-inf')]
    for i,(key,value) in enumerate(bad):
        out.append(dict(name=f'invalid_{i:02d}_{key}',p=dict(base,**{key:value}),
                        limit=250,lref_factor=1,valid=False))
    return out


def run_beam(inputs, source=ROOT/'src/beam_core.lua', lua=None):
    with tempfile.TemporaryDirectory(prefix='beam-golden-') as tmp:
        output=Path(tmp)/'results.json'
        code='local Beam=dofile('+literal(str(source))+')\nlocal cases='+literal(inputs)+'\n'
        code += r'''
local function number(v)
    if v=='@nan' then return 0/0 elseif v=='@inf' then return math.huge
    elseif v=='@-inf' then return -math.huge end
    return v
end
local results={}
for i,case in ipairs(cases) do
    local p={};for k,v in pairs(case.p) do p[k]=number(v) end
    local sol,err=Beam.solve(p)
    if not sol then results[i]={error=err} else
        local lo,xlo,hi,xhi=Beam.moment_extrema(sol)
        local w,xw=Beam.deflection_extrema(sol)
        local samples={}
        for k=0,100 do
            local v=Beam.at(sol,p.L*k/100)
            samples[#samples+1]={v.M,v.V,v.w}
        end
        results[i]={reactions={left={Rx=sol.r[1],Ry=sol.r[2],Mz=sol.r[3]},
            right={Rx=sol.r[#sol.r-2],Ry=sol.r[#sol.r-1],Mz=sol.r[#sol.r]}},
            samples=samples,moments={lo=lo,xlo=xlo,hi=hi,xhi=xhi},
            deflection={mm=w,position=xw},summary=Beam.summary(sol,case.limit,case.lref_factor)}
    end
end
'''
        code+='local file=assert(io.open('+literal(str(output))+',"w"))\n'
        code+=r'''
local function encode(v)
    if type(v)=='number' then file:write(string.format('%.17g',v))
    elseif type(v)=='string' then
        local escaped=v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r')
        file:write('"',escaped,'"')
    elseif type(v)=='boolean' then file:write(v and 'true' or 'false')
    elseif type(v)=='table' then
        if #v>0 then
            file:write('[');for i,item in ipairs(v) do if i>1 then file:write(',') end;encode(item) end;file:write(']')
        else
            local keys={};for k in pairs(v) do keys[#keys+1]=k end;table.sort(keys)
            file:write('{');for i,k in ipairs(keys) do if i>1 then file:write(',') end;encode(k);file:write(':');encode(v[k]) end;file:write('}')
        end
    else file:write('null') end
end
encode(results);file:close()
'''
        if lua:
            subprocess.run([lua,'-'],input=code,text=True,check=True)
        else:
            lib=ctypes.CDLL('liblua5.4.so.0')
            lib.luaL_newstate.restype=ctypes.c_void_p
            lib.luaL_openlibs.argtypes=[ctypes.c_void_p]
            lib.luaL_loadstring.argtypes=[ctypes.c_void_p,ctypes.c_char_p]
            lib.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_longlong,ctypes.c_void_p]
            lib.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p]
            lib.lua_tolstring.restype=ctypes.c_char_p
            lib.lua_close.argtypes=[ctypes.c_void_p]
            vm=lib.luaL_newstate()
            try:
                lib.luaL_openlibs(vm)
                status=lib.luaL_loadstring(vm,code.encode())
                if status==0: status=lib.lua_pcallk(vm,0,0,0,0,None)
                if status: raise RuntimeError(lib.lua_tolstring(vm,-1,None).decode())
            finally: lib.lua_close(vm)
        return json.loads(output.read_text())


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lua')
    parser.add_argument('--output',type=Path,default=ROOT/'tests/fixtures/beam_v033_golden.json')
    args=parser.parse_args()
    inputs=cases()
    results=run_beam(inputs,lua=args.lua)
    for case,result in zip(inputs,results): case['beam']=result
    fixture=dict(seed=SEED,random_cases=2000,date=datetime.now(ZoneInfo('Europe/Berlin')).date().isoformat(),
                 source_sha256=hashlib.sha256((ROOT/'src/beam_core.lua').read_bytes()).hexdigest(),
                 units='m, kN, kNm; sample w in m, deflection.mm and summary.w_abs_max in mm',cases=inputs)
    args.output.write_text(json.dumps(fixture,separators=(',',':'),allow_nan=False)+'\n')
    failures=[c for c in inputs if c['valid'] and 'error' in c['beam']]
    print(f'Golden: {len(inputs)} cases, {len(failures)} valid Beam failures; {args.output.stat().st_size} bytes')
    for case in failures: print('BEAM_FAILURE',json.dumps(case['p']),case['beam']['error'])


if __name__=='__main__': main()
