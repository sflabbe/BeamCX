-- Also runnable directly: lua5.1 tests/quick_check.lua /path/to/BeamCX
local root=(...) or '.'
Frame=dofile(root..'/src/frame_core.lua')
local BeamPreset=dofile(root..'/src/beam_preset.lua')
local DB=dofile(root..'/src/section_db.lua')
local function eq(a,b)
    assert(type(a)=='number' and math.abs(a-b)<=1e-8*math.max(1e-5,math.abs(b)),
        tostring(a)..' != '..tostring(b))
end
local function solve(L,q,P,a,EI,support)
    local sol,msg=BeamPreset.solve{L=L,q=q,P=P,a=a,EI=EI,support=support}
    assert(sol,msg)
    return sol
end
local function extrema(sol,w,x)
    local maximum=BeamPreset.deflection_extrema(sol)
    local actual,pos=maximum.absolute*1000,maximum.position
    eq(actual,w);eq(pos,x)
    eq(actual,math.abs(BeamPreset.at(sol,pos).w)*1000)
end
local L,q,EI=6,10,10000
local simple=solve(L,q,0,3,EI,1)
extrema(simple,5*q*L^4/(384*EI)*1000,L/2)
assert(BeamPreset.at(simple,L/2).w<0,'downward displacement must stay negative')
extrema(solve(L,q,0,3,EI,2),q*L^4/(8*EI)*1000,L)
extrema(solve(L,-q,0,3,EI,1),5*q*L^4/(384*EI)*1000,L/2)
extrema(solve(L,q,0,3,EI,3),q*L^4/(384*EI)*1000,L/2)
-- Asymmetric point load: maximum is between load position and midspan.
-- For a<L/2, x=L-sqrt((L^2-a^2)/3), with exact right-branch deflection.
local P,a=12,2
local x=L-math.sqrt((L^2-a^2)/3)
local w=P*a*(L-x)*(L^2-a^2-(L-x)^2)/(6*L*EI)
extrema(solve(L,0,P,a,EI,1),w*1000,x)
extrema(solve(L,0,P,L-a,EI,1),w*1000,L-x)
extrema(solve(L,0,P,L,EI,2),P*L^3/(3*EI)*1000,L)
-- Symmetric point load: stationary maximum lies on the segment boundary.
extrema(solve(L,0,P,L/2,EI,1),P*L^3/(48*EI)*1000,L/2)
-- Opposing UDL/point loads yield three stationary points, two equal absolute
-- maxima. On the left branch slope is proportional to
-- -1 + 3r/2 + (6-6r)z^2 - 4z^3, r=|P|/(qL)=3/5, z=x/L.
local mixed=solve(L,q,-0.6*q*L,L/2,EI,1)
local z=(1+math.sqrt(21))/20
local expected_x=L*z
local expected_w=math.abs(-q*expected_x*(L^3-2*L*expected_x^2+expected_x^3)/(24*EI)
    +(0.6*q*L)*expected_x*(3*L^2-4*expected_x^2)/(48*EI))*1000
local maximum=BeamPreset.deflection_extrema(mixed)
local actual_w,actual_x=maximum.absolute*1000,maximum.position
eq(actual_w,expected_w)
assert(math.min(math.abs(actual_x-expected_x),math.abs(actual_x-(L-expected_x)))<1e-8)
-- Tiny loads must not disappear behind an absolute slope-root tolerance.
extrema(solve(L,1e-12,0,3,EI,1),5*1e-12*L^4/(384*EI)*1000,L/2)
local zero=solve(L,0,0,3,EI,1)
local check=BeamPreset.deflection_check(zero,250)
eq(zero.summary.bx_wmax,0);assert(check.span_deflection_ratio==nil and check.status=='N/A')
check=BeamPreset.deflection_check(simple,250)
eq(check.span_deflection_ratio,L*1000/simple.summary.bx_wmax)
eq(check.utilization.L250,simple.summary.bx_wmax/(L*1000/250))
eq(check.utilization.L300,simple.summary.bx_wmax/(L*1000/300))
assert(check.status=='OK')
-- A deflection of L/275 passes L/250 and fails L/300.
local target=L/275
local middle=solve(L,q,0,3,5*q*L^4/(384*target),1)
assert(BeamPreset.deflection_check(middle,250).status=='OK')
assert(BeamPreset.deflection_check(middle,300).status=='EXCEEDED')
for _,limit in ipairs{250,300} do
    local at_limit=solve(L,q,0,3,5*q*L^4/(384*(L/limit)),1)
    assert(BeamPreset.deflection_check(at_limit,limit).status=='OK')
end
print('PASS: analytical deflection extrema, signed loads, segment boundaries, multiple roots, L/250 and L/300')

-- Catalogue weights are independent of EI. No weights for manual mode or
-- missing mass data; concrete uses b*h (m2) times nominal 25 kN/m3.
local sec={material=5,profile=6,b=250,h=450,manualEI=EI}
eq(DB.compute(sec).q_sw,22.4*9.81/1000)
sec.profile=16;eq(DB.compute(sec).q_sw,42.3*9.81/1000)
sec.material=2;eq(DB.compute(sec).q_sw,25*0.25*0.45)
sec.material=1;assert(DB.compute(sec).q_sw==nil)
sec.material=5
local mass=DB.profiles[16][3];DB.profiles[16][3]=nil
assert(DB.compute(sec).q_sw==nil)
DB.profiles[16][3]=mass
for _,profile in ipairs(DB.profiles) do assert(profile[3]>0) end
print('PASS: steel kg/m, concrete 25 kN/m3, unavailable weights')

-- Exercise production UI, not a second calculation path.
local height=212
platform={window={width=function() return 320 end,height=function() return height end,
    invalidate=function() end}}
dofile(root..'/BeamCX.lua')
local texts,stores={},{}
local gc={font=10}
function gc:setColorRGB() end
function gc:setPen() end
function gc:drawLine() end
function gc:fillRect() end
function gc:fillPolygon() end
function gc:setFont(face,style,size) self.font=size end
function gc:drawString(t,x,y)
    assert(x>=0 and y>=0 and y+self.font+3<=height,'text exceeds canvas: '..t)
    -- Conservative approximate glyph widths; hardware metrics still need a device.
    assert(x+#t*(self.font==9 and 6 or 7)<=320,'text exceeds width: '..t)
    texts[#texts+1]=t
end
local function paint()
    texts={};on.paint(gc);return table.concat(texts,'\n')
end
local function contains(fragment)
    local text=paint()
    assert(string.find(text,fragment,1,true),fragment..' missing from:\n'..text)
end
var={store=function(name,value)
    assert(type(value)=='number','CAS export must contain numeric values')
    assert(stores[name]==nil,'duplicate variable store')
    stores[name]=value
end}
local function export()
    stores={};on.enterKey();return stores
end
local function count(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
local function go(page)
    for i=1,3 do
        if on.save().page==page then return end
        on.tabKey()
    end
    error('could not reach page '..page)
end
local function edit(value)
    for ch in string.gmatch(value,'.') do on.charIn(ch) end
    on.enterKey()
end
on.enterKey()
local initial=on.save()
assert(initial.settings.self_weight==false and initial.settings.limit==250)
on.tabKey();eq(on.save().page,2)
-- Original M -> V -> w navigation, cursor behavior and TAB route retained.
on.arrowRight();eq(on.save().mode,2)
on.arrowRight();eq(on.save().mode,3)
on.arrowUp();eq(on.save().cursor,0.525)
on.arrowDown();eq(on.save().cursor,0.5)
on.arrowRight();eq(on.save().mode,4)
contains('|w|max=16.875 mm');contains('L/250: OK')
local values=export()
eq(count(values),8);eq(values.bx_mmax,45);eq(values.bx_mmin,0)
eq(values.bx_vabs,30);eq(values.bx_wmax,16.875);eq(values.bx_xwmax,3)
eq(values.bx_ra,30);eq(values.bx_rb,30);eq(values.bx_ei,10000)
contains('CAS: 8 variables stored')
on.arrowUp();eq(on.save().settings.limit,300)
local persisted=on.save()
on.restore(initial);on.restore(persisted)
eq(on.save().mode,4);eq(on.save().settings.limit,300)
contains('L/300: OK')
on.arrowRight();eq(on.save().mode,1)
on.arrowLeft();eq(on.save().mode,4)
-- Older saves have no settings and must reset both new settings to defaults.
local legacy=on.save();legacy.settings=nil
on.restore(legacy)
assert(not on.save().settings.self_weight);eq(on.save().settings.limit,250)

-- Turn self-weight on using the actual section-page selector.
on.restore(initial);go(3)
for i=1,4 do on.arrowRight() end -- MANUAL -> S235
on.arrowDown() -- profile
on.arrowDown() -- skip E / I / EI -> Self-weight
contains('Self-weight');contains('OFF')
on.enterKey();assert(on.save().settings.self_weight)
go(2);on.enterKey() -- compact results
local sw=22.4*9.81/1000
contains('q sw=0.21974 kN/m');contains('q total=10.22 kN/m')
values=export();eq(values.bx_ra,(10+sw)*L/2)
eq(on.save().params.q,10) -- still user load
local frozen=on.save()
for i=1,3 do
    on.restore(frozen);values=export();eq(values.bx_ra,(10+sw)*L/2)
    eq(on.save().params.q,10)
end
-- Change profile while ON, then recalculate q_user through the keyboard.
go(3);on.arrowUp();on.arrowRight() -- IPE 220
local sw220=26.2*9.81/1000
go(1);on.arrowDown();on.arrowDown();edit('-1') -- q user
assert(on.save().settings.self_weight);eq(on.save().params.q,-1)
go(2);values=export();eq(values.bx_ra,(-1+sw220)*L/2)
-- OFF returns to the original user-only solve with the same section.
go(3);on.arrowDown();on.enterKey()
assert(not on.save().settings.self_weight)
go(2);values=export();eq(values.bx_ra,-L/2)
contains('SW OFF | q sw=0.25702 kN/m');contains('q total=-1 kN/m')

-- Concrete weight, RC warning and compact eight-row section layout.
local concrete=on.save()
concrete.section.material=2;concrete.section.b=250;concrete.section.h=450
concrete.params.q=0;concrete.settings.self_weight=true;concrete.page=2;concrete.mode=4
on.restore(concrete)
values=export();eq(values.bx_ra,25*0.25*0.45*L/2)
contains('RC: GROSS EI ONLY');contains('q sw=2.8125 kN/m')
for _,h in ipairs{212,240} do
    height=h
    for _,p in ipairs{1,2,3} do
        local model=on.save();model.page=p;on.restore(model);paint()
    end
end
height=212
-- Manual mode never silently substitutes weight and forces unavailable to OFF.
local manual=on.save();manual.section.material=1;manual.settings.self_weight=true
manual.page=2;manual.mode=4
on.restore(manual)
assert(not on.save().settings.self_weight)
contains('SW N/A | q sw=N/A kN/m')
values=export();eq(values.bx_ra,0)
contains('L/250: N/A')
-- Missing steel weight is also unavailable through the productive route.
local missing=on.save();missing.section.material=5;missing.section.profile=6
missing.settings.self_weight=true
-- UI has its own generated DB.
local ui_mass=_G.DB.profiles[6][3];_G.DB.profiles[6][3]=nil
on.restore(missing);assert(not on.save().settings.self_weight)
contains('SW N/A | q sw=N/A kN/m')
_G.DB.profiles[6][3]=ui_mass
print('PASS: actual UI self-weight ON/OFF, sign, section change, no accumulation, legacy and new persistence, canvas bounds')

-- Export uses signed solver extrema and actual reactions for all presets.
for support=1,4 do
    local model=initial
    model.params.support=support;model.params.q=-10;model.params.P=12
    model.params.a=2;model.page=2;model.mode=4
    on.restore(model)
    values=export()
    local sol=solve(L,-10,12,2,EI,support)
    local lo,hi=sol.moments.minimum.value,sol.moments.maximum.value
    eq(values.bx_mmin,lo);eq(values.bx_mmax,hi)
    eq(values.bx_ra,sol.reactions.left.Ry);eq(values.bx_rb,sol.reactions.right.Ry)
end
-- Native returned errors, exceptions and unavailable API must never claim success.
var.store=function(name,value)
    stores[name]=value
    if name=='bx_wmax' then return 'cannot store' end
end
stores={};on.enterKey();contains('CAS ERROR bx_wmax: cannot store')
assert(not string.find(paint(),'variables stored',1,true))
eq(count(stores),4)
var.store=function() error('store exception',0) end
on.enterKey();contains('CAS ERROR bx_mmax: store exception')
var=nil;on.enterKey();contains('CAS ERROR: API unavailable')
-- Failed restore and rejected numerical calculation both invalidate old results.
local called=0
var={store=function() called=called+1 end}
local bad=on.save();bad.params.L=0;bad.page=2;bad.mode=4
on.restore(bad);on.enterKey();eq(called,0)
contains('invalid beam dimensions, rigidity or loads')
-- Valid recovery, then invalid edit: no stale result exports.
local recovered=on.save();recovered.params.L=6;recovered.page=1
on.restore(recovered)
-- edit_index was q above; move up once to L, reject zero.
on.arrowUp();edit('0');on.tabKey();eq(on.save().page,1);eq(called,0)
contains('invalid beam dimensions, rigidity or loads')
print('PASS: CAS names/units/solver values, all supports, returned errors, exceptions, missing API, failed-solve blocking')
