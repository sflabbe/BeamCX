"""P6A: finite-EA Python reference, analytical witnesses and sign regressions."""
import ctypes
from decimal import Decimal
import importlib.util
from pathlib import Path
import random

from portal_reference import Reference

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('portal_literals', root/'tools/make_beam_golden.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def floats(value):
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, list):
        return [floats(v) for v in value]
    if isinstance(value, dict):
        return {k: floats(v) for k, v in value.items()}
    return value


base = dict(h=4, l=6, EIc=10000, EIb=15000, base='FIX', q=0, P=0, a=3, H=0, w=0)
inputs = []


def add(name, oracle=None, **changes):
    inputs.append(dict(name=name, p=dict(base, **changes), oracle=oracle))


# Supplied analytical magnitudes, independently derived finite-EA responses.
add('PIN q', base='PIN', q=10, oracle=dict(field='H', side='left', value=4.5))
add('FIX q', q=10, oracle=dict(field='M', side='both', value=10, corner=20))
add('FIX P', P=20, oracle=dict(field='M', side='both', value=5))
add('FIX H', H=10, oracle=dict(field='M', side='both', value=80/7))
add('PIN w', base='PIN', w=10, oracle=dict(field='H', side='right', value=11, windward=29))
add('PIN H', base='PIN', H=10, oracle=dict(field='drift', value=.016))
for support in ('PIN', 'FIX'):
    add('combined '+support, base=support, q=10, P=20, a=1.7, H=10, w=7)
    add('zero '+support, base=support)
    for load in ('q', 'P', 'H', 'w'):
        for sign in (-1, 1):
            add(f'sign {support} {load} {sign}', **dict(base=support, **{load: sign*13}))
    for a in (0, 6, 1e-7, 6-1e-7):
        add(f'endpoint {support} {a}', base=support, q=-3, P=20, a=a, H=-10, w=7)
    # Large chord slope relative to bending: using absolute-w extrema fails.
    add('asymmetric chord '+support, base=support, h=8, l=3, EIc=10000, EIb=100000,
        q=2, P=30, a=.4, H=12, w=-4)

rng = random.Random(20261118)
for index in range(50):
    p = dict(h=rng.uniform(2, 8), l=rng.uniform(3, 15), EIc=10**rng.uniform(3, 5),
             EIb=10**rng.uniform(3, 5), q=rng.uniform(-25, 25), P=rng.uniform(-50, 50),
             H=rng.uniform(-40, 40), w=rng.uniform(-20, 20))
    p['a'] = rng.random()*p['l']
    for support in ('PIN', 'FIX'):
        add(f'random {index:02d} {support}', base=support, **p)

for case in inputs:
    reference = Reference(case['p'])
    case['ref'] = reference.export()
    p = case['p']
    # Independent equilibrium, using physical loads and support positions.
    rx = reference.reactions
    F = abs(p['q']*p['l'])+abs(p['P'])+abs(p['H'])+abs(p['w']*p['h'])
    terms = [rx[0]+rx[9]+Decimal(str(p['H']))+Decimal(str(p['w']))*Decimal(str(p['h'])),
             rx[1]+rx[10]-Decimal(str(p['q']))*Decimal(str(p['l']))-Decimal(str(p['P'])),
             rx[2]+rx[11]+Decimal(str(p['l']))*rx[10]
             -Decimal(str(p['q']))*Decimal(str(p['l']))**2/2
             -Decimal(str(p['P']))*Decimal(str(p['a']))-Decimal(str(p['H']))*Decimal(str(p['h']))
             -Decimal(str(p['w']))*Decimal(str(p['h']))**2/2]
    assert max(abs(t) for t in terms) <= Decimal('1e-24')*Decimal(str(max(1, F*max(p['l'], p['h']))))
    case['points'] = []
    for member in (1, 2, 3):
        L = p['l'] if member == 2 else p['h']
        positions = [0]+[L*i/20 for i in range(1, 20)]+[L]
        if member == 2:
            positions.append(p['a'])
        for s in positions:
            for side in ('left', 'right'):
                if (s == 0 and side == 'left') or (s == L and side == 'right'):
                    continue
                case['points'].append(dict(member=member, s=s, side=side, value=reference.at(member, s, side)))
    case.update(floats(case))

script = 'Frame=dofile('+builder.literal(str(root/'src/frame_core.lua'))+')\n'
script += 'local Portal=dofile('+builder.literal(str(root/'src/portal_preset.lua'))+')\n'
script += 'local cases='+builder.literal(inputs)+'\n'
script += r'''
local errors={}
local current_case=''
local function eq(group,got,want,scale,tol)
    assert(type(got)=='number' and got==got,group..' not finite')
    local err=math.abs(got-want)/math.max(scale or math.abs(want),1e-300)
    errors[group]=math.max(errors[group] or 0,err)
    assert(err<=(tol or 1e-9),current_case..' '..group..string.format(': %.17g != %.17g relative=%.6g',got,want,err))
end
local function semantic(t)
    for key,value in pairs(t) do
        assert(type(key)~='string' or not key:find('bx_',1,true))
        if type(value)=='table' then semantic(value) end
    end
end
local function equilibrium(p,r)
    local F=math.abs(p.q*p.l)+math.abs(p.P)+math.abs(p.H)+math.abs(p.w*p.h)
    F=F>0 and F or 1
    eq('equilibrium Fx',r.left.H+r.right.H+p.H+p.w*p.h,0,F)
    eq('equilibrium Fy',r.left.V+r.right.V-p.q*p.l-p.P,0,F)
    eq('equilibrium Mz',(r.left.M or 0)+(r.right.M or 0)+p.l*r.right.V
        -p.q*p.l^2/2-p.P*p.a-p.H*p.h-p.w*p.h^2/2,0,F*math.max(p.h,p.l))
end
local points,oracles,chord_witnesses=0,0,0
for _,case in ipairs(cases) do
    current_case=case.name
    local p,ref=case.p,case.ref
    local F=math.abs(p.q*p.l)+math.abs(p.P)+math.abs(p.H)+math.abs(p.w*p.h)
    local scale=F>0 and F or 1
    local length=math.max(p.h,p.l)
    local mscale=scale*length
    local dscale=math.max(math.abs(ref.drift.left),math.abs(ref.drift.right),
        1e-6*scale*length^3/math.min(p.EIc,p.EIb))
    local wscale=math.max(ref.deflection.absolute,1e-6*scale*p.l^3/p.EIb)
    local solve=Frame.solve
    local count=0
    Frame.solve=function(model) count=count+1;return solve(model) end
    local sol,err=Portal.solve(p)
    Frame.solve=solve
    assert(sol,case.name..': '..tostring(err));assert(count==1)
    equilibrium(p,sol.reactions)
    for i,side in ipairs{'left','right'} do
        for _,key in ipairs{'H','V','M'} do
            if key=='M' and p.base=='PIN' then assert(sol.reactions[side].M==nil)
            else eq('reaction '..key,sol.reactions[side][key],ref.reactions[i][key],key=='M' and mscale or scale) end
        end
        eq('drift',sol.drift[side],ref.drift[side],dscale)
    end
    for _,point in ipairs(case.points) do
        local got=sol.at(point.member,point.s,point.side)
        local delegated=Frame.at(sol.frame,point.member,point.s,point.side)
        for _,key in ipairs{'N','V','M','w'} do
            assert(got[key]==delegated[key])
            eq('sample '..key,got[key],point.value[key],key=='M' and mscale or
                (key=='w' and math.max(dscale,wscale) or scale))
        end
        points=points+1
    end
    for i,member in ipairs(sol.members) do
        for _,kind in ipairs{'minimum','maximum'} do
            local extremum=member.moments[kind]
            eq('moment extrema',extremum.value,ref.members[i].moments[kind].value,mscale)
            eq('moment position value',sol.at(i,extremum.position).M,ref.members[i].moments[kind].value,mscale)
        end
        eq('axial',member.axial.value,ref.members[i].N,scale)
        eq('axial absolute',member.axial.absolute,math.abs(ref.members[i].N),scale)
        eq('axial position value',sol.at(i,member.axial.position).N,member.axial.value,scale)
    end
    local w0,wL=sol.at(2,0).w,sol.at(2,p.l).w
    local s=sol.deflection.position
    local relative=sol.at(2,s).w-(1-s/p.l)*w0-s/p.l*wL
    eq('relative deflection',sol.deflection.absolute,ref.deflection.absolute,wscale)
    eq('relative signed',sol.deflection.value,ref.deflection.value,wscale)
    eq('relative position value',relative,ref.deflection.value,wscale)
    -- Position is unique in this asymmetric witness; also detects a search
    -- that corrects w at the old absolute-w stationary points only.
    if case.name:find('asymmetric chord',1,true) then
        eq('relative position',s,ref.deflection.position,p.l)
        local lo,xlo,hi,xhi=Frame.deflection_extrema(sol.frame,2)
        local old=math.abs(hi)>math.abs(lo) and xhi or xlo
        assert(math.abs(old-s)>1e-7*p.l)
        chord_witnesses=chord_witnesses+1
    end
    eq('corner left',sol.corners.left.column,sol.corners.left.beam,mscale)
    eq('corner right',sol.corners.right.column,-sol.corners.right.beam,mscale)
    assert(sol.corners.left.column==sol.at(1,p.h).M and sol.corners.left.beam==sol.at(2,0).M)
    assert(sol.corners.right.column==sol.at(3,p.h).M and sol.corners.right.beam==sol.at(2,p.l).M)
    semantic(sol.summary)
    assert(sol.summary.reactions==sol.reactions and sol.summary.member_extrema==sol.members
        and sol.summary.drift==sol.drift and sol.summary.beam_deflection==sol.deflection
        and sol.summary.corner_moments==sol.corners)
    -- Direction/resultant regressions independent of Frame's applied totals.
    local model=assert(Portal.model(p))
    assert(model.member_loads[1].member==1 and model.member_loads[1].q==-p.w)
    assert(model.member_loads[2].member==2 and model.member_loads[2].q==-p.q)
    assert(model.nodal_loads[1].node==2 and model.nodal_loads[1].Fx==p.H)
    if p.P~=0 then assert(model.member_loads[3].P==-p.P and model.member_loads[3].a==p.a) end
    assert(#model.member_loads==(p.P==0 and 2 or 3))
    eq('column resultant',sol.at(1,p.h).V-sol.at(1,0).V,-p.w*p.h,scale)
    local internalP=p.a>0 and p.a<p.l and p.P or 0
    eq('beam resultant',sol.at(2,p.l).V-sol.at(2,0).V,-p.q*p.l-internalP,scale)
    if internalP~=0 then eq('point jump',sol.at(2,p.a,'right').V-sol.at(2,p.a,'left').V,-p.P,scale) end
    if case.name=='FIX q' then
        eq('symmetry H',sol.reactions.left.H,-sol.reactions.right.H,scale)
        eq('symmetry V',sol.reactions.left.V,sol.reactions.right.V,scale)
        eq('symmetry base M',sol.reactions.left.M,-sol.reactions.right.M,mscale)
        eq('symmetry corner M',sol.corners.left.column,-sol.corners.right.column,mscale)
        eq('symmetry beam M',sol.corners.left.beam,sol.corners.right.beam,mscale)
    end
    if case.oracle then
        local o=case.oracle
        local analytical,finite_error=0,0
        local function witness(got,finite,want)
            analytical=math.max(analytical,math.abs(math.abs(got)/want-1))
            finite_error=math.max(finite_error,math.abs(math.abs(got)-math.abs(finite))/want)
        end
        if o.field=='drift' then
            witness(sol.drift.left,ref.drift.left,o.value)
            witness(sol.drift.right,ref.drift.right,o.value)
        else
            for i,side in ipairs{'left','right'} do
                if o.side=='both' or o.side==side then witness(sol.reactions[side][o.field],ref.reactions[i][o.field],o.value) end
            end
        end
        if o.corner then
            witness(sol.corners.left.beam,ref.members[2].moments.minimum.value,o.corner)
            witness(sol.corners.right.beam,ref.members[2].moments.minimum.value,o.corner)
        end
        if o.windward then witness(sol.reactions.left.H,ref.reactions[1].H,o.windward) end
        assert(analytical<=5e-5 and finite_error<=1e-9,case.name..' analytical witness')
        print(string.format('ORACLE | %s | analytical=%.12g | finite_EA=%.12g',case.name,analytical,finite_error))
        oracles=oracles+1
    end
end
-- Validation is fail-closed at the public model AND solve boundaries.
local valid=cases[1].p
for _,key in ipairs{'h','l','EIc','EIb','q','P','a','H','w'} do
    for _,value in ipairs{math.huge,-math.huge,0/0,'bad',false} do
        local p={};for k,v in pairs(valid) do p[k]=v end;p[key]=value
        local model,message=Portal.model(p);assert(model==nil and type(message)=='string')
        local sol,err=Portal.solve(p);assert(sol==nil and type(err)=='string')
    end
    local p={};for k,v in pairs(valid) do p[k]=v end;p[key]=nil
    local model,message=Portal.model(p);assert(model==nil and type(message)=='string')
end
for _,change in ipairs{{h=0},{l=-1},{EIc=0},{EIb=0},{a=-1},{a=7},{base='ROLLER'}} do
    local p={};for k,v in pairs(valid) do p[k]=v end;for k,v in pairs(change) do p[k]=v end
    local model,message=Portal.model(p);assert(model==nil and type(message)=='string')
    local sol,err=Portal.solve(p);assert(sol==nil and type(err)=='string')
end
for _,invalid in ipairs{false,42,'invalid'} do assert(Portal.model(invalid)==nil and Portal.solve(invalid)==nil) end
assert(Portal.model(nil)==nil and Portal.solve(nil)==nil)
assert(oracles==6 and chord_witnesses==2)
for key,value in pairs(errors) do print(string.format('PORTAL ERROR | %s | %.12g',key,value)) end
print(string.format('PASS P6A: %d models, 50 random geometries x PIN/FIX, %d cuts, six oracles, one solve/model, Fx/Fy/Mz, signs, chord extrema, invalid inputs (%s)',#cases,points,_VERSION))
'''

lib = ctypes.CDLL('liblua5.4.so.0')
lib.luaL_newstate.restype = ctypes.c_void_p
lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
lib.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lib.luaL_loadstring.restype = ctypes.c_int
lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_longlong, ctypes.c_void_p]
lib.lua_pcallk.restype = ctypes.c_int
lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
lib.lua_tolstring.restype = ctypes.c_char_p
lib.lua_close.argtypes = [ctypes.c_void_p]
vm = lib.luaL_newstate()
try:
    lib.luaL_openlibs(vm)
    status = lib.luaL_loadstring(vm, script.encode())
    if status == 0:
        status = lib.lua_pcallk(vm, 0, 0, 0, 0, None)
    if status:
        raise RuntimeError(lib.lua_tolstring(vm, -1, None).decode())
finally:
    lib.lua_close(vm)
