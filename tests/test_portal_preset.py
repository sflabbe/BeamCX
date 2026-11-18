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

assert len(inputs) == 136
for case in inputs:
    reference = Reference(case['p'])
    case['ref'] = reference.export()
    case['diagnostics'] = reference.conditioning()
    case['displacement_tol'] = 1e-9
    if case['name'].startswith('random '):
        case['displacement_tol'] = max(1e-9, 10*float(case['diagnostics']['kappa'])*2.220446049250313e-16)
        assert case['displacement_tol'] <= 1e-6, f"STOP: outside qualified domain: {case['name']}"
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
local worst={}
local current_case=''
local model_errors={}
local function category(group)
    if group=='drift' or group=='nodal translation' or group=='sample w' or group=='sample u'
        or group=='relative deflection' or group=='relative signed' or group=='relative position value' then return 'D' end
    if group=='nodal rotation' then return 'rotation' end
    if group:find('axial',1,true) or group=='sample N' then return 'N' end
    if group=='reaction H' or group=='reaction V' then return 'R' end
    if group=='sample V' then return 'V' end
    if group=='sample M' or group=='reaction M' or group:find('moment',1,true) then return 'M' end
    return 'other'
end
local function eq(group,got,want,scale,tol)
    assert(type(got)=='number' and got==got,group..' not finite')
    local err=math.abs(got-want)/math.max(scale or math.abs(want),1e-300)
    errors[group]=math.max(errors[group] or 0,err)
    local key=category(group)
    local entry=model_errors[key] or {absolute=0,relative=0}
    entry.absolute=math.max(entry.absolute,math.abs(got-want))
    entry.relative=math.max(entry.relative,err)
    model_errors[key]=entry
    local overall=worst[group] or {relative=0,absolute=0,relative_case=current_case,absolute_case=current_case}
    if err>overall.relative then overall.relative=err;overall.relative_case=current_case end
    if math.abs(got-want)>overall.absolute then overall.absolute=math.abs(got-want);overall.absolute_case=current_case end
    worst[group]=overall
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
local solutions={}
for _,case in ipairs(cases) do
    current_case=case.name
    model_errors={}
    local p,ref=case.p,case.ref
    local dtol=case.displacement_tol
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
    solutions[case.name]=sol
    equilibrium(p,sol.reactions)
    for i,side in ipairs{'left','right'} do
        for _,key in ipairs{'H','V','M'} do
            if key=='M' and p.base=='PIN' then assert(sol.reactions[side].M==nil)
            else eq('reaction '..key,sol.reactions[side][key],ref.reactions[i][key],key=='M' and mscale or scale) end
        end
        eq('drift',sol.drift[side],ref.drift[side],dscale,dtol)
    end
    for d=1,12 do
        local rotation=d%3==0
        eq(rotation and 'nodal rotation' or 'nodal translation',sol.frame.u[d],ref.nodal_displacements[d],
            rotation and dscale/length or dscale,dtol)
    end
    for _,point in ipairs(case.points) do
        local got=sol.at(point.member,point.s,point.side)
        local delegated=Frame.at(sol.frame,point.member,point.s,point.side)
        for _,key in ipairs{'N','V','M','w','u'} do
            assert(got[key]==delegated[key])
            local displacement=key=='w' or key=='u'
            eq('sample '..key,got[key],point.value[key],key=='M' and mscale or
                (displacement and math.max(dscale,wscale) or scale),displacement and dtol or 1e-9)
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
    eq('relative deflection',sol.deflection.absolute,ref.deflection.absolute,wscale,dtol)
    eq('relative signed',sol.deflection.value,ref.deflection.value,wscale,dtol)
    eq('relative position value',relative,ref.deflection.value,wscale,dtol)
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
    -- Relative backward residual from the INDEPENDENT reference assembly.
    -- All norms are infinity norms; evaluation here is binary64 in both Lua.
    local diag=case.diagnostics
    local residual,unorm=0,0
    for _,d in ipairs(diag.free) do unorm=math.max(unorm,math.abs(sol.frame.u[d])) end
    for i,row in ipairs(diag.matrix) do
        local r=-diag.load[i]
        for j,d in ipairs(diag.free) do r=r+row[j]*sol.frame.u[d] end
        residual=math.max(residual,math.abs(r))
    end
    local denominator=diag.matrix_norm*unorm+diag.load_norm
    local backward=denominator>0 and residual/denominator or residual
    local function maximum(key,field) return model_errors[key] and model_errors[key][field] or 0 end
    print(string.format('PORTAL MODEL | %s | %.12g | %.12g | %.12g | %.12g | %.12g | %.12g | %.12g | %.12g | %.12g | %.12g | PASS',
        case.name,diag.kappa,diag.kappa_scaled,dtol,maximum('D','absolute'),maximum('D','relative'),
        maximum('N','relative'),maximum('V','relative'),maximum('M','relative'),maximum('R','relative'),backward))
end
-- Reversal uses the original +/- individual cases, without new models.
for _,support in ipairs{'PIN','FIX'} do
    current_case='reversal '..support
    for _,load in ipairs{'q','P','H','w'} do
        local positive=solutions['sign '..support..' '..load..' 1']
        local negative=solutions['sign '..support..' '..load..' -1']
        for d=1,12 do assert(positive.frame.u[d]==-negative.frame.u[d]) end
        for i=1,3 do
            local L=i==2 and 6 or 4
            for sample=0,20 do
                local s=L*sample/20
                local a,b=positive.at(i,s),negative.at(i,s)
                for _,key in ipairs{'N','V','M','w','u'} do assert(a[key]==-b[key]) end
            end
        end
    end
end
-- Decompose the two EXISTING combined geometries into four load components.
-- Eight supplementary component solves, each still one Frame.solve; no
-- change to the original 136-model campaign or its Python reference inputs.
local components=0
for _,support in ipairs{'PIN','FIX'} do
    current_case='superposition '..support
    local combined=solutions['combined '..support]
    local p=combined.parameters
    local parts={}
    for _,load in ipairs{'q','P','H','w'} do
        local part={};for k,v in pairs(p) do part[k]=v end
        part.q,part.P,part.H,part.w=0,0,0,0;part[load]=p[load]
        local count,solve=0,Frame.solve
        Frame.solve=function(m) count=count+1;return solve(m) end
        parts[#parts+1]=assert(Portal.solve(part));Frame.solve=solve
        assert(count==1);components=components+1
        equilibrium(part,parts[#parts].reactions)
    end
    local F=math.abs(p.q*p.l)+math.abs(p.P)+math.abs(p.H)+math.abs(p.w*p.h)
    local ds=math.max(math.abs(combined.drift.left),math.abs(combined.drift.right),
        1e-6*F*6^3/math.min(p.EIc,p.EIb))
    for d=1,12 do
        local sum=0;for _,part in ipairs(parts) do sum=sum+part.frame.u[d] end
        eq('superposition nodal',sum,combined.frame.u[d],d%3==0 and ds/6 or ds)
    end
    for _,side in ipairs{'left','right'} do
        for _,key in ipairs{'H','V','M'} do
            local sum=0;for _,part in ipairs(parts) do sum=sum+(part.reactions[side][key] or 0) end
            eq('superposition reaction '..key,sum,combined.reactions[side][key] or 0,key=='M' and 6*F or F)
        end
    end
    for member=1,3 do
        local L=member==2 and p.l or p.h
        for sample=0,20 do
            local s=L*sample/20
            local sum={N=0,V=0,M=0,w=0,u=0}
            for _,part in ipairs(parts) do
                local v=part.at(member,s)
                for key in pairs(sum) do sum[key]=sum[key]+v[key] end
            end
            local v=combined.at(member,s)
            for key,value in pairs(sum) do
                eq('superposition '..key,value,v[key],key=='M' and 6*F or ((key=='w' or key=='u') and ds or F))
            end
            if member==2 then
                local relative=0
                for _,part in ipairs(parts) do relative=relative+part.at(2,s).w-(1-s/L)*part.at(2,0).w-s/L*part.at(2,L).w end
                eq('superposition relative',relative,combined.at(2,s).w-(1-s/L)*combined.at(2,0).w-s/L*combined.at(2,L).w,
                    math.max(combined.deflection.absolute,1e-6*F*L^3/p.EIb))
            end
        end
    end
end
assert(components==8)
print('PASS P6A reversal: 8 original +/- pairs; superposition: 2 combined cases / 8 component solves')
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
for key,v in pairs(worst) do print(string.format('PORTAL WORST | %s | %s | %.12g | %s | %.12g',key,v.relative_case,v.relative,v.absolute_case,v.absolute)) end
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
