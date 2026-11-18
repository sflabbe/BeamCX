"""Physical equivalence to the frozen v0.3.3 golden; optional --live-beam check.

Default tests need only stdlib + liblua5.4, never the legacy solver. --lua lua5.1
runs the identical assertions with the target runtime.
"""
import argparse
import ctypes
from decimal import Decimal, localcontext
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

root=Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('golden_builder',root/'tools/make_beam_golden.py')
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
fixture=json.loads((root/'tests/fixtures/beam_v033_golden.json').read_text())


def closed(p):
    """Independent classical formulas; decimal arithmetic protects tiny responses."""
    with localcontext() as ctx:
        ctx.prec=60
        d=lambda v:Decimal.from_float(v) if isinstance(v,float) else Decimal(v)
        L,q,P,a,EI=(d(p[k]) for k in ('L','q','P','a','EI'));b=L-a
        support=p['support']
        if support==1:
            rb=q*L/2+P*a/L;ra=q*L+P-rb;m0=d(0)
        elif support==2:
            rb=d(0);ra=q*L+P;m0=-q*L**2/2-P*a
        elif support==3:
            rb=q*L/2+P*a*a*(a+3*b)/L**3;ra=q*L+P-rb
            m0=-q*L**2/12-P*a*b*b/L**2
        else:
            rb=3*q*L/8+P*a*a*(3*L-a)/(2*L**3);ra=q*L+P-rb
            m0=-q*L**2/2-P*a+rb*L
        samples=[]
        for i in range(101):
            # Match the actual binary x passed to Frame, including grid rounding.
            x=d(float(p['L']*i/100));x=min(L,max(d(0),x))
            beyond=max(d(0),x-a)
            V=ra-q*x-(P if x>a or a==0 else d(0))
            M=m0+ra*x-q*x*x/2-P*beyond
            if support==1:
                w=-q*x*(L**3-2*L*x*x+x**3)/(24*EI)
                if x<=a: w-=P*b*x*(L*L-b*b-x*x)/(6*L*EI)
                else: w-=P*a*(L-x)*(L*L-a*a-(L-x)**2)/(6*L*EI)
            else:
                w=(m0*x*x/2+ra*x**3/6-q*x**4/24-P*beyond**3/6)/EI
            samples.append([float(M),float(V),float(w)])
        mj=m0+ra*L-q*L*L/2-P*b
        return dict(reactions=dict(left=dict(Rx=0,Ry=float(ra),Mz=float(-m0)),
                                   right=dict(Rx=0,Ry=float(rb),Mz=float(mj))),samples=samples)


for case in fixture['cases']:
    if case['valid'] and 'error' in case['beam']:
        case['closed']=closed(case['p'])

script='Frame=dofile('+builder.literal(str(root/'src/frame_core.lua'))+')\n'
script+='local Preset=dofile('+builder.literal(str(root/'src/beam_preset.lua'))+')\n'
script+='local cases={}\n'
# Lua 5.1 limits constants per function; batch fixture literals into functions.
for offset in range(0,len(fixture['cases']),100):
    script+='do local part=(function() return '+builder.literal(fixture['cases'][offset:offset+100])+' end)()\n'
    script+='for _,case in ipairs(part) do cases[#cases+1]=case end end\n'
script+=r'''
local maxima={};local ties=0;local successes,failures,invalid=0,0,0
local function compare(name,got,want,scale,context)
    scale=math.max(scale,1e-300)
    local error=math.abs(got-want)/scale
    maxima[name]=math.max(maxima[name] or 0,error)
    assert(got==got and error<=1e-9,context..' '..name..': '..string.format('%.17g vs %.17g err %.6g',got,want,error))
end
local function number(v)
    if v=='@nan' then return 0/0 elseif v=='@inf' then return math.huge elseif v=='@-inf' then return -math.huge end
    return v
end
for _,case in ipairs(cases) do
    local p={};for k,v in pairs(case.p) do p[k]=number(v) end
    local sol,err=Preset.solve(p,case.limit,case.lref_factor)
    if not case.valid then
        assert(sol==nil and type(err)=='string' and #err>0,case.name);invalid=invalid+1
    else
        assert(sol,case.name..' CORE_FAILURE: '..tostring(err))
        local ref=case.closed or case.beam
        local Mscale,Vscale,Wscale=0,0,0
        local samples={}
        for i=0,100 do
            local got=Preset.at(sol,p.L*i/100)
            samples[i+1]=got
            local want=ref.samples[i+1]
            Mscale=math.max(Mscale,math.abs(got.M),math.abs(want[1]))
            Vscale=math.max(Vscale,math.abs(got.V),math.abs(want[2]))
            Wscale=math.max(Wscale,math.abs(got.w),math.abs(want[3]))
        end
        for _,side in ipairs{'left','right'} do
            Mscale=math.max(Mscale,math.abs(ref.reactions[side].Mz),math.abs(sol.reactions[side].Mz))
            Vscale=math.max(Vscale,math.abs(ref.reactions[side].Ry),math.abs(sol.reactions[side].Ry))
        end
        for _,side in ipairs{'left','right'} do
            compare('Ry',sol.reactions[side].Ry,ref.reactions[side].Ry,Vscale,case.name)
            compare('Mz',sol.reactions[side].Mz,ref.reactions[side].Mz,Mscale,case.name)
        end
        for i,got in ipairs(samples) do
            compare('M',got.M,ref.samples[i][1],Mscale,case.name..' grid '..i)
            compare('V',got.V,ref.samples[i][2],Vscale,case.name..' grid '..i)
            compare('w',got.w,ref.samples[i][3],Wscale,case.name..' grid '..i)
        end
        if case.closed then
            failures=failures+1
            print(string.format('RESOLVED %s L=%.17g q=%.17g P=%.17g a=%.17g EI=%.17g support=%d error=%s',
                case.name,p.L,p.q,p.P,p.a,p.EI,p.support,case.beam.error))
        else
            successes=successes+1
            compare('Mmin',sol.moments.minimum.value,ref.moments.lo,Mscale,case.name)
            compare('Mmax',sol.moments.maximum.value,ref.moments.hi,Mscale,case.name)
            for _,pair in ipairs{{sol.moments.minimum,ref.moments.xlo},{sol.moments.maximum,ref.moments.xhi}} do
                if math.abs(pair[1].position-pair[2])>1e-9*p.L then
                    -- A support minimum (or other tied extremum) has no unique
                    -- coordinate. Verify BOTH positions attain the same value.
                    compare('M at tied position',Preset.at(sol,pair[2]).M,pair[1].value,Mscale,case.name)
                    ties=ties+1
                else compare('xM',pair[1].position,pair[2],p.L,case.name) end
            end
            compare('wmax_mm',sol.summary.bx_wmax,ref.deflection.mm,Wscale*1000,case.name)
            compare('xw',sol.deflection.position,ref.deflection.position,p.L,case.name)
            local legacy=ref.summary
            local fields={mmin='bx_mmin',mmax='bx_mmax',vabs='bx_vabs',w_abs_max='bx_wmax',x_wmax='bx_xwmax',ra='bx_ra',rb='bx_rb',ei='bx_ei'}
            for old,new in pairs(fields) do
                local scale=(old=='mmin' or old=='mmax') and Mscale or
                    ((old=='ra' or old=='rb' or old=='vabs') and Vscale or
                    (old=='w_abs_max' and Wscale*1000 or (old=='x_wmax' and p.L or p.EI)))
                compare('summary.'..old,sol.summary[new],legacy[old],scale,case.name)
            end
            local check=sol.deflection_check
            local mapped={lref=check.reference_length,lref_factor=check.lref_factor,
                ratio=check.span_deflection_ratio,u250=check.utilization.L250,u300=check.utilization.L300}
            for key,value in pairs(mapped) do
                compare('summary.'..key,value,legacy[key],math.max(math.abs(value),math.abs(legacy[key])),case.name)
            end
            assert((mapped.ratio==nil)==(legacy.ratio==nil) and check.status==legacy.status,case.name..' status/ratio')
        end
        assert(sol.frame.ndof==6 and sol.r==nil and sol.force_residual==nil)
    end
end
local keys={};for k in pairs(maxima) do keys[#keys+1]=k end;table.sort(keys)
for _,key in ipairs(keys) do print(string.format('MAX %s %.17g',key,maxima[key])) end
print(string.format('PASS PRESET random=2000 successes=%d legacy_failures_resolved=%d invalid=%d tied_moment_positions=%d',successes,failures,invalid,ties))
-- Pure template, input copy, point-load limits and out-of-range clipping.
local p={L=6,q=10,P=12,a=2,EI=10000,support=1}
local model=assert(Preset.model(p));assert(model.members[1].EA==1000*p.EI/p.L^2)
assert(model.member_loads[1].q==-10 and model.member_loads[2].P==-12 and #model.nodes==2)
local sol=assert(Preset.solve(p));p.L=99;assert(sol.parameters.L==6)
compare('point left limit',Preset.at(sol,2).V,Frame.at(sol.frame,1,2,'left').V,40,'point')
assert(Preset.at(sol,-1).w==Preset.at(sol,0).w and Preset.at(sol,7).w==Preset.at(sol,6).w)
local witnesses={{45,0,30,16.875,3,30,30,10000},
 {0,-180,60,162,6,60,0,10000},{15,-30,30,3.375,3,30,30,10000},
 {25.3125,-45,37.5,7.0192936011540326,3.4707890075482379,37.5,22.5,10000}}
local names={'bx_mmax','bx_mmin','bx_vabs','bx_wmax','bx_xwmax','bx_ra','bx_rb','bx_ei'}
for support=1,4 do
    local s=assert(Preset.solve{L=6,q=10,P=0,a=3,EI=10000,support=support})
    for i,name in ipairs(names) do compare('P0 '..name,s.summary[name],witnesses[support][i],math.max(1,math.abs(witnesses[support][i])),'P0') end
end
print('PASS P0: four presets and all eight bx_* witnesses')
'''


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lua')
    parser.add_argument('--live-beam',action='store_true')
    args=parser.parse_args()
    if args.live_beam:
        source=root/'src/beam_core.lua'
        assert hashlib.sha256(source.read_bytes()).hexdigest()==fixture['source_sha256']
        results=builder.run_beam(fixture['cases'],source,lua=args.lua)
        for case,result in zip(fixture['cases'],results):
            assert result==case['beam'],case['name']+' differs from live Beam'
        print('PASS live Beam: SHA-256 and all golden outputs identical',flush=True)
    if args.lua:
        subprocess.run([args.lua,'-'],input=script,text=True,check=True);return
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
        status=lib.luaL_loadstring(vm,script.encode())
        if status==0: status=lib.lua_pcallk(vm,0,0,0,0,None)
        if status: raise RuntimeError(lib.lua_tolstring(vm,-1,None).decode())
    finally: lib.lua_close(vm)


if __name__=='__main__': main()
