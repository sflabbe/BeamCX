"""P5A rational reference, brute-force envelopes, combination and uplift oracles."""
import argparse
import ctypes
import importlib.util
from pathlib import Path
import sys
import random
import subprocess

root=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(root/'tests'))
from continuous_reference import Reference
spec=importlib.util.spec_from_file_location('golden_builder',root/'tools/make_beam_golden.py')
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
models=[dict(name='D',spans=[4,6,5],left='FIX',right='PIN',g=8,q=5,EI=20000,gG_sup=1.35,gG_inf=1,gQ=1.5),
        dict(name='E',spans=[6,6,6],left='PIN',right='PIN',g=10,q=5,EI=10000,gG_sup=1.35,gG_inf=1,gQ=1.5),
        dict(name='F5',spans=[3,5,4,6,2],left='FIX',right='FIX',g=7,q=4,EI=23000,gG_sup=1.35,gG_inf=1,gQ=1.5)]
cases=[]
for p in models:
    print('REFERENCE exact rational stiffness + brute-force: '+p['name'],flush=True)
    cases.append(dict(p=p,reference=Reference(p).envelope()))
# The reference itself also reproduces the supplied A/B/C closed witnesses.
for spans,expected in (([6,6],[22.5,75,22.5]),([6,6,6],[24,66,66,24])):
    r=Reference(dict(spans=spans,left='PIN',right='PIN',EI=10000)).solve([10]*len(spans))
    assert list(map(float,r['reactions']))==expected
# Reuse the unchanged P2A assertions against the updated standalone modules,
# in addition to the existing suite that checks the frozen productive bundle.
golden_spec=importlib.util.spec_from_file_location('p2a_golden',root/'tests/test_beam_preset.py')
golden=importlib.util.module_from_spec(golden_spec);golden_spec.loader.exec_module(golden)
new_modules='Frame=dofile('+builder.literal(str(root/'src/frame_core.lua'))+')\nlocal Preset=dofile('+builder.literal(str(root/'src/beam_preset.lua'))+')'
script='do\n'+golden.script.replace('local Preset=BeamPreset',new_modules)+'\nend\n'
script+='Frame=dofile('+builder.literal(str(root/'src/frame_core.lua'))+')\n'
script+='local C=dofile('+builder.literal(str(root/'src/continuous_preset.lua'))+')\n'
script+='local cases='+builder.literal(cases)+'\n'
script+=r'''
local unpack=table.unpack or unpack
local errors={}
local function eq(group,got,want,scale,tol)
    scale=math.max(scale or math.abs(want),1e-300)
    local error=math.abs(got-want)/scale
    errors[group]=math.max(errors[group] or 0,error)
    assert(type(got)=='number' and got==got and error<=(tol or 1e-9),group..': '..string.format('%.17g != %.17g err %.6g',got,want,error))
end
local function copy(t)
    if type(t)~='table' then return t end
    local out={};for k,v in pairs(t) do out[k]=copy(v) end;return out
end
local function same(a,b)
    assert(type(a)==type(b))
    if type(a)~='table' then assert(a==b);return end
    for k,v in pairs(a) do same(v,b[k]) end
    for k in pairs(b) do assert(a[k]~=nil) end
end
local function number_pattern(text,n)
    local active={}
    for i=1,n do active[i]=false end
    for v in text:gmatch('%d+') do active[tonumber(v)]=true end
    return active
end
local function direct(p,name,gamma,characteristic)
    local m=assert(C.model(p,'G'))
    local active=number_pattern(name,#p.spans)
    for i,load in ipairs(m.member_loads) do
        load.q=-((gamma or 1)*p.g+(active[i] and (characteristic and 1 or p.gQ or 1.5)*p.q or 0))
    end
    return assert(Frame.solve(m))
end
-- Exact count evidence: every preset solve uses n+1 real Frame solves only.
for _,case in ipairs(cases) do
    local p,ref=case.p,case.reference
    local solve,combine=Frame.solve,Frame.combine
    local solves,combines=0,0
    Frame.solve=function(m) solves=solves+1;return solve(m) end
    Frame.combine=function(s,f) combines=combines+1;return combine(s,f) end
    local result=assert(C.solve(p))
    Frame.solve,Frame.combine=solve,combine
    assert(solves==#p.spans+1 and combines==2)
    assert(result.factor_convention.status=='OPEN' and result.deflection_label=='w car.')
    for k in pairs(result.summary) do assert(not k:find('bx_',1,true)) end
    local F=(math.abs(p.g)+math.abs(p.q))*result.supports[#result.supports].position
    local L=result.supports[#result.supports].position
    local Mfloor,Vfloor,Wfloor=1e-6*F*L,1e-6*F,1e-6*F*L^3/p.EI
    local ms,vs,ws=Mfloor,Vfloor,Wfloor
    for _,s in ipairs(ref.spans) do
        ms=math.max(ms,math.abs(s.Mmax.value));ws=math.max(ws,math.abs(s.down.value),math.abs(s.up.value))
    end
    for _,s in ipairs(ref.supports) do ms=math.max(ms,math.abs(s.Mmin.value));vs=math.max(vs,math.abs(s.Rmax.value),math.abs(s.Rmin.value)) end
    local offset=0
    for i,span in ipairs(result.spans) do
        local expected=ref.spans[i]
        eq(p.name..'.Mmax',span.Mmax.value,expected.Mmax.value,ms)
        assert(span.Mplus and span.Mplus.value==span.Mmax.value)
        local governing=direct(p,span.Mmax.pattern,span.Mmax.gammaG)
        eq(p.name..'.xM as M',Frame.at(governing,i,span.Mmax.x).M,expected.Mmax.value,ms)
        for _,direction in ipairs{'down','up'} do
            local got,want=span.deflection[direction],expected[direction]
            eq(p.name..'.w '..direction,got.value,want.value,ws)
            assert(got.x>=0 and got.x<=span.length)
            local car=direct(p,got.pattern,1,true)
            eq(p.name..'.xw as w '..direction,-Frame.at(car,i,got.x).w,want.value,ws)
        end
        local d=span.deflection
        eq(p.name..'.governing w',d.governing.absolute,math.max(math.abs(expected.down.value),math.abs(expected.up.value)),ws)
        eq(p.name..'.ratio as w',span.length/d.ratio,d.governing.absolute,ws)
        eq(p.name..'.L250',d.utilization.L250,d.governing.absolute/(span.length/250),ws*250/span.length)
        eq(p.name..'.L300',d.utilization.L300,d.governing.absolute/(span.length/300),ws*300/span.length)
        assert(d.selected_limit==250 and d.status==(d.governing.absolute<=span.length/250 and 'OK' or 'EXCEEDED'))
        for j=0,100 do
            local side=j==0 and 'right' or 'left'
            local envelope=result.envelope_at(offset+p.spans[i]*j/100,side)
            local want=ref.grid[(i-1)*101+j+1]
            for _,key in ipairs{'Mmax','Mmin','Vmax','Vmin'} do
                eq(p.name..'.envelope '..key,envelope[key],want[key],key:sub(1,1)=='M' and ms or vs)
            end
        end
        offset=offset+p.spans[i]
    end
    for i,s in ipairs(result.supports) do
        for _,key in ipairs{'Mmin','Rmax','Rmin'} do
            eq(p.name..'.support '..key,s[key].value,ref.supports[i][key].value,key=='Mmin' and ms or vs)
            local actual=direct(p,s[key].pattern,s[key].gammaG)
            local value=key=='Mmin' and Frame.at(actual,i==1 and 1 or i-1,i==1 and 0 or p.spans[i-1]).M or actual.reactions[i].Ry
            eq(p.name..'.support pattern '..key,value,ref.supports[i][key].value,key=='Mmin' and ms or vs)
        end
    end
    if p.name=='D' or p.name=='E' then
        for i,expected in ipairs{'1-3','2','1-3'} do
            assert(result.spans[i].Mplus.pattern==expected and result.spans[i].Mplus.gammaG==1.35)
            assert(result.spans[i].deflection.down.pattern==expected)
        end
        for i,expected in ipairs{'1-3','1-2','2-3','1-3'} do
            assert(result.supports[i].Rmax.pattern==expected and result.supports[i].Rmax.gammaG==1.35)
        end
        for i,expected in ipairs{'2','3','1','2'} do
            assert(result.supports[i].Rmin.pattern==expected and result.supports[i].Rmin.gammaG==1)
        end
        assert(result.supports[2].Mmin.pattern=='1-2' and result.supports[3].Mmin.pattern=='2-3')
        if p.name=='D' then assert(result.supports[1].Mmin.pattern=='1-3') end
    end
    eq(p.name..'.Vabs',result.shear.value,ref.vabs,vs)
    local summary=result.summary
    eq(p.name..'.summary M',summary.moment_max,math.max(unpack((function() local a={} for _,s in ipairs(ref.spans) do a[#a+1]=s.Mmax.value end return a end)())),ms)
    eq(p.name..'.summary w',summary.deflection_absolute_max,math.max(unpack((function() local a={} for _,s in ipairs(ref.spans) do a[#a+1]=math.max(math.abs(s.down.value),math.abs(s.up.value)) end return a end)())),ws)
    local minM,maxR=math.huge,-math.huge
    for _,support in ipairs(ref.supports) do minM=math.min(minM,support.Mmin.value);maxR=math.max(maxR,support.Rmax.value) end
    eq(p.name..'.summary Mmin',summary.moment_min,minM,ms)
    eq(p.name..'.summary Rmax',summary.reaction_max,maxR,vs)
    eq(p.name..'.summary Vabs',summary.shear_absolute_max,ref.vabs,vs)
    local position_found=false
    for _,span in ipairs(result.spans) do
        if span.deflection.governing.position==summary.deflection_position and span.deflection.governing.absolute==summary.deflection_absolute_max then position_found=true end
    end
    assert(position_found,'summary deflection position must achieve its maximum')
    eq(p.name..'.summary EI',summary.rigidity,p.EI,p.EI)
    assert(summary.span_count==#p.spans)
    if p.name=='D' then
        assert(result.spans[1].deflection.governing==result.spans[1].deflection.up,'D span 1 must govern in uplift')
        eq('D uplift regression',result.spans[1].deflection.governing.absolute,4.20398173154e-4,ws)
        assert(result.spans[1].deflection.governing.pattern=='2')
    elseif p.name=='E' then
        eq('E symmetry M',result.spans[1].Mplus.value,result.spans[3].Mplus.value,ms)
        eq('E symmetry w',result.spans[1].deflection.down.value,result.spans[3].deflection.down.value,ws)
        eq('E symmetry supports',result.supports[2].Mmin.value,result.supports[3].Mmin.value,ms)
        eq('E middle uplift',result.spans[2].deflection.up.value,-.003375,ws)
        assert(result.spans[1].deflection.up.value==0 and result.spans[3].deflection.up.value==0)
    end
    print(string.format('PASS %s: all %d patterns, two global gammaG; 101 points/span; signed w and governing pattern; solves=%d combines=%d',p.name,2^#p.spans,solves,combines))
end
-- PIN-FIX is the mirrored FIX-PIN witness; the application still has no UI path.
local mirror=copy(cases[1].p);mirror.spans={5,6,4};mirror.left='PIN';mirror.right='FIX'
local mirrored=assert(C.solve(mirror))
for i=1,3 do
    eq('PIN-FIX mirror M',mirrored.spans[i].Mmax.value,cases[1].reference.spans[4-i].Mmax.value,100)
    eq('PIN-FIX mirror w',mirrored.spans[i].deflection.down.value,cases[1].reference.spans[4-i].down.value,.01)
end
-- Supplied A/B analytical witnesses and C isolated load patterns.
for _,test in ipairs{
    {lengths={6,6},moments={0,-45,0},reactions={22.5,75,22.5},maxima={25.3125,25.3125},positions={2.25,3.75}},
    {lengths={6,6,6},moments={0,-36,-36,0},reactions={24,66,66,24},maxima={28.8,9,28.8},positions={2.4,3,3.6}}
} do
    local p={spans=test.lengths,left='PIN',right='PIN',g=10,q=0,EI=10000,gG_sup=1,gG_inf=1,gQ=1}
    local s=assert(C.solve(p))
    for i,r in ipairs(test.reactions) do eq('AB reaction',s.supports[i].Rmax.value,r,100) end
    for i,m in ipairs(test.moments) do eq('AB support moment',s.supports[i].Mmin.value,m,100) end
    for i,m in ipairs(test.maxima) do eq('AB span moment',s.spans[i].Mmax.value,m,100);eq('AB xM',s.spans[i].Mmax.x,test.positions[i],6) end
end
local cp={spans={6,6,6},left='PIN',right='PIN',g=0,q=10,EI=10000,gG_sup=1,gG_inf=1,gQ=1}
local cb=assert(C.solve(cp)).bases
for _,test in ipairs{
    {name='1-3',moments={-18,-18},R={27,33,33,27},hi={36.45,-18,36.45},x={2.7,0,3.3}},
    {name='2',moments={-18,-18},R={-3,33,33,-3},hi={0,27,0},x={0,3,6}},
    {name='1-2',moments={-42,-12},R={23,72,27,-2},hi={26.45,19.25,0},x={2.3,3.5,6}}
} do
    local active=number_pattern(test.name,3)
    local s=assert(Frame.combine(cb,{0,active[1] and 1 or 0,active[2] and 1 or 0,active[3] and 1 or 0}))
    for i=1,2 do eq('C moment '..test.name,Frame.at(s,i,6).M,test.moments[i],100) end
    for i=1,4 do eq('C reaction '..test.name,s.reactions[i].Ry,test.R[i],100) end
    for i=1,3 do
        local lo,xlo,hi,xhi=Frame.moment_extrema(s,i)
        eq('C Mmax '..test.name,hi,test.hi[i],100)
        eq('C position as M '..test.name,Frame.at(s,i,test.x[i]).M,test.hi[i],100)
        if test.name=='1-3' and i==2 then assert(hi<0,'algebraic Mmax must remain negative; Mplus absent') end
    end
end
print('PASS A/B/C: analytical values, isolated patterns and negative algebraic central Mmax')
-- combine: three independent direct-load comparisons for D and E at 1e-12.
for index=1,2 do
    local p=cases[index].p
    local a=direct(p,'-',1)
    local qmodel=assert(C.model(p,'G'))
    for i,load in ipairs(qmodel.member_loads) do load.q=(i==2) and 0 or -p.q end
    local b=assert(Frame.solve(qmodel))
    local before_a,before_b=copy(a),copy(b)
    local identity=assert(Frame.combine({a},{1}));same(identity,a)
    for _,factors in ipairs{{1.35,1.5},{1,-.75},{.7,0}} do
        local m=assert(C.model(p,'G'))
        for i,load in ipairs(m.member_loads) do load.q=-(factors[1]*p.g+(i~=2 and factors[2]*p.q or 0)) end
        local wanted=assert(Frame.solve(m))
        local old_solve=Frame.solve;Frame.solve=function() error('combine must not solve') end
        local got=assert(Frame.combine({a,b},factors));Frame.solve=old_solve
        local scales={M=1e-6,V=1e-6,w=1e-12}
        for i,L in ipairs(p.spans) do for k=0,100 do
            local value=Frame.at(wanted,i,L*k/100)
            for key in pairs(scales) do scales[key]=math.max(scales[key],math.abs(value[key])) end
        end end
        for i,L in ipairs(p.spans) do
            for k=0,100 do
                local g,w=Frame.at(got,i,L*k/100),Frame.at(wanted,i,L*k/100)
                for key,scale in pairs(scales) do eq('combine '..key,g[key],w[key],scale,1e-12) end
            end
            for _,extrema in ipairs{Frame.moment_extrema,Frame.deflection_extrema} do
                local lo,xlo,hi,xhi=extrema(got,i)
                local wlo,wxlo,whi,wxhi=extrema(wanted,i)
                local scale=extrema==Frame.moment_extrema and scales.M or scales.w
                eq('combine extrema',lo,wlo,scale,1e-12);eq('combine extrema',hi,whi,scale,1e-12)
            end
        end
        for i,r in ipairs(got.reactions) do
            eq('combine reaction Ry',r.Ry,wanted.reactions[i].Ry,scales.V,1e-12)
            eq('combine reaction Mz',r.Mz,wanted.reactions[i].Mz,scales.M,1e-12)
            eq('combine reaction Rx',r.Rx,wanted.reactions[i].Rx,scales.V,1e-12)
        end
        same(a,before_a);same(b,before_b)
    end
end
-- Nonzero axial force, a release, spring, thermal curvature and recovery cuts.
-- These exercise every superposed recovery coefficient, not only UDL beams.
local function general(v)
    return {nodes={{x=0,y=0},{x=6,y=0}},members={{i=1,j=2,EI=10000,EA=1e8,hinge_i=true,alphaT=1e-5,h=.5}},
        supports={{node=1,ux=true,uy=true},{node=2,uy=true,kr=5000}},
        nodal_loads={{node=2,Fx=v[5]}},member_loads={{member=1,type='dist',a=1,b=5,q1=v[1],q2=v[2]},
            {member=1,type='point',a=3,P=v[3]},{member=1,type='dT',dT=v[4]}}}
end
local va,vb={-3,-7,-2,10,3},{5,-1,4,-7,-2}
local vc={};for i=1,5 do vc[i]=.8*va[i]+1.2*vb[i] end
local sa,sb=assert(Frame.solve(general(va))),assert(Frame.solve(general(vb)))
local sc=assert(Frame.combine({sa,sb},{.8,1.2}))
local sd=assert(Frame.solve(general(vc)))
for i=1,#sc.u do eq('combine general u',sc.u[i],sd.u[i],.01,1e-12) end
for i=1,2 do for _,key in ipairs{'Rx','Ry','Mz'} do eq('combine general R',sc.reactions[i][key],sd.reactions[i][key],100,1e-12) end end
for j=0,100 do
    local x=6*j/100
    local got,want=Frame.at(sc,1,x,x==6 and 'left' or 'right'),Frame.at(sd,1,x,x==6 and 'left' or 'right')
    for _,key in ipairs{'N','V','M','w','u'} do eq('combine general '..key,got[key],want[key],key=='w' and .01 or 100,1e-12) end
end
for i,span in ipairs(sc.members[1].elements[1].spans) do
    for _,key in ipairs{'V','M','w','theta','qa','g','kappa'} do
        eq('combine coefficient '..key,span[key],sd.members[1].elements[1].spans[i][key],math.max(1e-6,math.abs(sd.members[1].elements[1].spans[i][key])),1e-12)
    end
end
local p=cases[1].p
local base=assert(Frame.solve(assert(C.model(p,'G'))))
local function rejected(other,reason)
    local s,e=Frame.combine({base,other},{1,1})
    assert(s==nil and e:find('incompatible solutions: ',1,true)==1 and e:find(reason,1,true),tostring(e))
end
local m=assert(C.model(p,'G'));m.member_loads[#m.member_loads+1]={member=1,type='point',P=-2,a=2}
rejected(assert(Frame.solve(m)),'cuts')
local changed=copy(p);changed.spans={4,6};rejected(assert(Frame.solve(assert(C.model(changed,'G')))),'nodes')
for _,key in ipairs{'EI','EA'} do m=assert(C.model(p,'G'));m.members[1][key]=m.members[1][key]*2;rejected(assert(Frame.solve(m)),key) end
m=assert(C.model(p,'G'));m.supports[2].kr=1000;rejected(assert(Frame.solve(m)),'springs')
m=assert(C.model(p,'G'));m.members[1].hinge_j=true;rejected(assert(Frame.solve(m)),'hinge_j')
for _,f in ipairs{{},{1,2},{0/0},{math.huge}} do local s,e=Frame.combine({base},f);assert(s==nil and e:find('incompatible solutions: ',1,true)==1) end
for _,change in ipairs{{'spans',{6}},{'spans',{1,1,1,1,1,1}},{'spans',{0,6}},{'EI',0},{'gG_sup',0},{'gG_inf',0},{'gQ',0},{'gQ',false},{'q',math.huge},{'left','FREE'}} do
    local bad=copy(p);bad[change[1]]=change[2]
    local s,e=C.model(bad,'G');assert(s==nil and type(e)=='string')
    s,e=C.solve(bad);assert(s==nil and type(e)=='string')
end
local negative=assert(C.solve{spans={8,1,8},left='PIN',right='PIN',g=10,q=0,EI=10000})
assert(negative.spans[2].Mmax.value<0 and negative.spans[2].Mplus==nil)
local limits={spans={6,6},left='PIN',right='PIN',g=10,q=0,EI=10000}
local initial=assert(C.solve(limits))
limits.EI=limits.EI*initial.spans[1].deflection.governing.absolute/(6/275)
assert(assert(C.solve(limits)).spans[1].deflection.status=='OK')
limits.limit=300
assert(assert(C.solve(limits)).spans[1].deflection.status=='EXCEEDED')
local zero=copy(p);zero.g=0;zero.q=0;zero.limit=300
local z=assert(C.solve(zero))
for _,s in ipairs(z.spans) do assert(s.Mplus==nil and s.deflection.ratio==nil and s.deflection.status=='N/A' and s.deflection.selected_limit==300) end
print('PASS combine: identity, unchanged operands, six direct-load comparisons, incompatibilities and invalid inputs')
local keys={};for key in pairs(errors) do keys[#keys+1]=key end;table.sort(keys)
for _,key in ipairs(keys) do print(string.format('P5A MAX | %s | %.17g',key,errors[key])) end
print('PASS P5A')
'''
# Deterministic identical random inputs for both real Lua runtimes.
rng=random.Random(20261118)
random_cases=[]
for i in range(300):
    n=2+i%4
    random_cases.append(dict(spans=[2+8*rng.random() for _ in range(n)],
        left=rng.choice(['PIN','FIX']),right=rng.choice(['PIN','FIX']),
        g=0 if i%23==0 else 30*rng.random(),q=0 if i%17==0 else 30*rng.random(),
        EI=5000+30000*rng.random(),gG_sup=1.35,gG_inf=1,gQ=1.5,limit=300 if i%3==0 else 250))
script+='\ndo local random_cases='+builder.literal(random_cases)+'\n'
script+=(root/'tests/continuous_bruteforce.lua').read_text()+'\nend\n'
# Lua 5.4 and target Lua 5.1 execute this identical test chunk.
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--lua')
args=parser.parse_args()
if args.lua:
    subprocess.run([args.lua,'-'],input=script,text=True,check=True)
else:
    lib=ctypes.CDLL('liblua5.4.so.0')
    lib.luaL_newstate.restype=ctypes.c_void_p
    lib.luaL_openlibs.argtypes=[ctypes.c_void_p]
    lib.luaL_loadstring.argtypes=[ctypes.c_void_p,ctypes.c_char_p]
    lib.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_longlong,ctypes.c_void_p]
    lib.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];lib.lua_tolstring.restype=ctypes.c_char_p
    lib.lua_close.argtypes=[ctypes.c_void_p]
    vm=lib.luaL_newstate()
    try:
        lib.luaL_openlibs(vm);status=lib.luaL_loadstring(vm,script.encode())
        if status==0: status=lib.lua_pcallk(vm,0,0,0,0,None)
        if status: raise RuntimeError(lib.lua_tolstring(vm,-1,None).decode())
    finally: lib.lua_close(vm)
