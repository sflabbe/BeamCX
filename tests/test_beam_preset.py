"""Physical equivalence to the frozen v0.3.3 golden and adjudication fixtures.

Tests load the generated application bundle with stdlib + liblua5.4. --lua lua5.1
runs the identical assertions with the target runtime.
"""
import argparse
import ctypes
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

root=Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('golden_builder',root/'tools/make_beam_golden.py')
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
fixture=json.loads((root/'tests/fixtures/beam_v033_golden.json').read_text())


adjudication=json.loads((root/'tests/fixtures/beam_v033_adjudicated.json').read_text())
assert adjudication['golden_sha256']==hashlib.sha256((root/'tests/fixtures/beam_v033_golden.json').read_bytes()).hexdigest()
for case in fixture['cases']:
    if case['name'] in adjudication['references']:
        case['reference']=adjudication['references'][case['name']]
        case['adjudicated']=case['name'] in adjudication['adjudicated']

script='platform={window={invalidate=function() end}}\n'
script+='dofile('+builder.literal(str(root/'BeamCX.lua'))+')\nlocal Preset=BeamPreset\n'
script+='local cases={}\n'
# Lua 5.1 limits constants per function; batch fixture literals into functions.
for offset in range(0,len(fixture['cases']),100):
    script+='do local part=(function() return '+builder.literal(fixture['cases'][offset:offset+100])+' end)()\n'
    script+='for _,case in ipairs(part) do cases[#cases+1]=case end end\n'
script+=r'''
local maxima={};local ties=0;local successes,adjudicated,resolved,invalid=0,0,0,0
local xw_coordinate_max=0
local function compare(name,got,want,scale,context)
    local error=math.abs(got-want)/math.max(scale,1e-300)
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
        local ref=case.reference or case.beam
        local F=math.abs(p.q)*p.L+math.abs(p.P)
        -- Global equivalence scales, NOT accuracy oracles for tiny responses.
        local Mscale,Vscale,Wscale=1e-6*F*p.L,1e-6*F,1e-6*F*p.L^3/p.EI
        local samples={}
        for i=0,100 do
            local got=Preset.at(sol,p.L*i/100);samples[i+1]=got
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
        compare('Mmin',sol.moments.minimum.value,ref.moments.lo,Mscale,case.name)
        compare('Mmax',sol.moments.maximum.value,ref.moments.hi,Mscale,case.name)
        for _,pair in ipairs{{sol.moments.minimum,ref.moments.xlo},{sol.moments.maximum,ref.moments.xhi}} do
            assert(pair[1].position>=-1e-12*p.L and pair[1].position<=p.L*(1+1e-12),case.name..' moment position')
            if math.abs(pair[1].position-pair[2])>1e-9*p.L then
                compare('M at tied position',Preset.at(sol,pair[2]).M,pair[1].value,Mscale,case.name)
                ties=ties+1
            else compare('xM',pair[1].position,pair[2],p.L,case.name) end
        end
        compare('wmax_mm',sol.summary.bx_wmax,ref.deflection.mm,Wscale*1000,case.name)
        local xw=sol.deflection.position
        assert(xw>=0 and xw<=p.L,case.name..' xw range')
        compare('w at xw',math.abs(Preset.at(sol,xw).w),ref.deflection.mm/1000,Wscale,case.name)
        xw_coordinate_max=math.max(xw_coordinate_max,math.abs(xw-ref.deflection.position)/p.L)
        local legacy=ref.summary
        local fields={mmin='bx_mmin',mmax='bx_mmax',vabs='bx_vabs',w_abs_max='bx_wmax',ra='bx_ra',rb='bx_rb',ei='bx_ei'}
        for old,new in pairs(fields) do
            local scale=(old=='mmin' or old=='mmax') and Mscale or
                ((old=='ra' or old=='rb' or old=='vabs') and Vscale or
                (old=='w_abs_max' and Wscale*1000 or p.EI))
            compare('summary.'..old,sol.summary[new],legacy[old],scale,case.name)
        end
        assert(sol.summary.bx_xwmax==xw)
        local check=sol.deflection_check
        compare('summary.lref',check.reference_length,legacy.lref,p.L*case.lref_factor,case.name)
        compare('summary.lref_factor',check.lref_factor,legacy.lref_factor,case.lref_factor,case.name)
        compare('summary.u250',check.utilization.L250,legacy.u250,Wscale*250/check.reference_length,case.name)
        compare('summary.u300',check.utilization.L300,legacy.u300,Wscale*300/check.reference_length,case.name)
        -- Compare inverse ratios as their implied physical deflection. Never
        -- invert nil or a zero-deflection state; require both states to agree.
        local no_deflection=sol.summary.bx_wmax==0
        assert(no_deflection==(legacy.w_abs_max==0),case.name..' zero deflection state')
        if no_deflection then
            assert(check.span_deflection_ratio==nil and legacy.ratio==nil)
            assert(check.status=='N/A' and legacy.status=='N/A')
        else
            assert(check.span_deflection_ratio and legacy.ratio)
            compare('ratio as w',check.reference_length/check.span_deflection_ratio,
                    legacy.lref/legacy.ratio,Wscale,case.name)
        end
        assert(check.status==legacy.status,case.name..' status')
        -- Zero displacement at a support is a prescribed nodal DOF oracle,
        -- not an assertion about the integrated recovery at that endpoint.
        for d in pairs(sol.frame.fixed) do assert(sol.frame.u[d]==0,case.name..' prescribed DOF') end
        assert(sol.frame.ndof==6 and sol.r==nil and sol.force_residual==nil)
        if case.adjudicated then adjudicated=adjudicated+1
        elseif case.reference then
            resolved=resolved+1
            print(string.format('RESOLVED %s L=%.17g q=%.17g P=%.17g a=%.17g EI=%.17g support=%d error=%s',
                case.name,p.L,p.q,p.P,p.a,p.EI,p.support,case.beam.error))
        else successes=successes+1 end
    end
end
assert(successes==2009 and adjudicated==2 and resolved==5 and invalid==26)
local keys={};for k in pairs(maxima) do keys[#keys+1]=k end;table.sort(keys)
for _,key in ipairs(keys) do print(string.format('MAX %s %.17g',key,maxima[key])) end
print(string.format('XW coordinate_difference_over_L %.17g',xw_coordinate_max))
print(string.format('PASS PRESET random=2000 successes=%d adjudicated=%d RESOLVED=%d invalid=%d total=2042 tied_moment_positions=%d',successes,adjudicated,resolved,invalid,ties))
-- A dedicated tiny-response oracle, separate from the global scale floor.
-- Fixes current behavior (~5.4e-9 relative observed), NOT a guaranteed bound.
local tiny=assert(Preset.solve{L=6,q=0,P=12,a=1e-7,EI=10000,support=4})
local expected=-6.7499998625e-18
local actual=Preset.at(tiny,3).w
assert(actual~=0 and math.abs(actual/expected-1)<1e-7)
assert(tiny.frame.u[2]==0 and tiny.frame.u[5]==0)
print(string.format('TINY w(3)=%.17g expected=%.17g relative=%.17g recovered_w(L)=%.17g',actual,expected,math.abs(actual/expected-1),Preset.at(tiny,6).w))
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
    local zero=assert(Preset.solve{L=6,q=0,P=0,a=3,EI=10000,support=support})
    assert(zero.deflection.absolute==0 and zero.summary.bx_wmax==0 and zero.deflection_check.span_deflection_ratio==nil)
    local template=assert(Preset.model{L=6,q=0,P=0,a=3,EI=10000,support=support})
    assert(template.supports[2].ux==(support==3))
end
print('PASS P0: four presets and all eight bx_* witnesses; unloaded zero response')

'''


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lua')
    args=parser.parse_args()
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
