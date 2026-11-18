"""P1 system selector: actual bundled TI-Lua, rollback and simulated canvas."""
import ctypes
from pathlib import Path

root = Path(__file__).resolve().parent.parent
lib = ctypes.CDLL('liblua5.4.so.0')
lib.luaL_newstate.restype = ctypes.c_void_p
lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
lib.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lib.luaL_loadstring.restype = ctypes.c_int
lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                           ctypes.c_longlong, ctypes.c_void_p]
lib.lua_pcallk.restype = ctypes.c_int
lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
lib.lua_tolstring.restype = ctypes.c_char_p
lib.lua_close.argtypes = [ctypes.c_void_p]
script = f"local bundle={str(root / 'BeamCX.lua')!r}\n" + r'''
local width,height=320,212
platform={window={width=function() return width end,height=function() return height end,
    invalidate=function() end}}
local function fresh()
    on=nil
    dofile(bundle)
end
local function state() return _BX_TEST_STATE() end
local function eq(a,b)
    assert(type(a)=='number' and math.abs(a-b)<1e-9*math.max(1,math.abs(b)),
        tostring(a)..' != '..tostring(b))
end
local function same(a,b)
    assert(type(a)==type(b),'type changed')
    if type(a)~='table' then assert(a==b,'value changed');return end
    for k,v in pairs(a) do same(v,b[k]) end
    for k in pairs(b) do assert(a[k]~=nil,'unexpected key: '..tostring(k)) end
end
local function unchanged(before,after,include_focus)
    assert(rawequal(before.result,after.result),'result identity changed')
    assert(rawequal(before.summary,after.summary),'summary identity changed')
    for _,k in ipairs{'support','EI','err','export_message','q_sw','self_weight','page','typing'} do
        assert(before[k]==after[k],k..' changed')
    end
    if include_focus then
        assert(before.sel_index==after.sel_index,'focus changed')
        assert(before.selector_error==after.selector_error,'selector error changed')
    end
end
local function focus(c)
    assert(on.save().page==0)
    on.arrowUp();on.arrowLeft()
    if c==2 or c==4 then on.arrowRight() end
    if c>=3 then on.arrowDown() end
    assert(state().sel_index==c)
end

-- 1. New documents start at the selector with the confirmed preset focused.
fresh()
local first=on.save()
assert(first.page==0 and first.params.support==1)
assert(state().sel_index==1 and state().result~=nil)
assert(state().selector_error==nil)
assert(first.sel_index==nil and first.selector_error==nil,'temporary selector state must not be saved')
print('PASS: selector initial page and temporary focus')

-- 2. All sixteen grid transitions, with clamping and no solves / editor changes.
local arrows={on.arrowUp,on.arrowDown,on.arrowLeft,on.arrowRight}
local expected={{1,3,1,2},{2,4,1,2},{1,3,3,4},{2,4,3,4}}
local original=Beam.solve
local calls=0
Beam.solve=function(p) calls=calls+1;return original(p) end
for c=1,4 do
    for i,arrow in ipairs(arrows) do
        focus(c)
        local before,saved=state(),on.save()
        arrow()
        assert(state().sel_index==expected[c][i],'incorrect grid transition')
        assert(state().sel_index>=1 and state().sel_index<=4)
        unchanged(before,state(),false)
        same(saved,on.save())
    end
end
assert(calls==0,'arrows must not recalculate')
-- 3. Inert selector keys must not enter the editor or mutate its model.
focus(4)
for _,key in ipairs{on.tabKey,function() on.charIn('5') end,on.backspaceKey,on.escapeKey} do
    local before,saved=state(),on.save()
    key()
    unchanged(before,state(),true)
    same(saved,on.save())
end
assert(calls==0,'inert keys must not recalculate')
Beam.solve=original
print('PASS: all grid transitions and inert keys preserve the confirmed model and result references')

-- 4. P0 witnesses, recorded before any source modification (EI=10000).
local witnesses={
    {ra=30,rb=30,mmin=0,mmax=45,w=16.874999999999996},
    {ra=60,rb=0,mmin=-180.00000000000003,mmax=-2.8421709430404007e-14,w=161.99999999999997},
    {ra=30,rb=30,mmin=-30,mmax=15,w=3.3750000000000004},
    {ra=37.5,rb=22.5,mmin=-45,mmax=25.3125,w=7.0192936011540326}
}
for c=1,4 do
    fresh();focus(c)
    local before=state()
    local solve=Beam.solve
    local count=0
    Beam.solve=function(p) count=count+1;return solve(p) end
    on.enterKey()
    Beam.solve=solve
    local s=state()
    assert(count==1,'Enter must solve once')
    assert(s.page==1 and s.support==c and s.result~=nil and s.selector_error==nil)
    assert(not rawequal(before.result,s.result),'Enter must install the successful result')
    eq(on.save().params.L,6);eq(on.save().params.q,10);eq(on.save().params.P,0);eq(s.EI,10000)
    eq(s.summary.ra,witnesses[c].ra);eq(s.summary.rb,witnesses[c].rb)
    eq(s.summary.mmin,witnesses[c].mmin);eq(s.summary.mmax,witnesses[c].mmax)
    eq(s.summary.w_abs_max,witnesses[c].w)
end
print('PASS: Enter confirms all four presets with unchanged P0 reaction, moment and deflection witnesses')

-- 5. Idle Esc returns from each old page. Editing Esc only cancels the edit.
for page=1,3 do
    fresh();focus(4);on.enterKey()
    for i=2,page do on.tabKey() end
    assert(on.save().page==page)
    local result=state().result
    on.escapeKey()
    assert(state().page==0 and state().sel_index==4 and state().support==4)
    assert(state().selector_error==nil and rawequal(result,state().result))
end
fresh();on.enterKey();on.arrowDown() -- L field
local saved=on.save()
on.charIn('7');assert(state().typing=='7')
on.escapeKey()
assert(state().typing==nil and state().page==1)
same(saved,on.save())
on.escapeKey();assert(state().page==0 and state().sel_index==state().support)
-- Existing Supports row still changes the confirmed support from the editor.
fresh();on.enterKey();on.arrowRight()
assert(state().page==1 and state().support==2 and state().result~=nil)
on.escapeKey();assert(state().sel_index==2)
-- 6. Tab retains the exact old three-page cycle.
fresh();on.enterKey()
for _,page in ipairs{2,3,1} do on.tabKey();assert(on.save().page==page) end
print('PASS: Esc cancels edits or opens selector, Supports row retained, Tab cycle 1-2-3-1')

-- 7. Real rollback: use a solved steel model, self-weight ON and a prior CAS
-- message. Failure must restore every recalc side effect, including references.
fresh()
local model=on.save()
model.page=2;model.mode=4;model.section.material=5;model.settings.self_weight=true
on.restore(model)
var={store=function() return nil end}
on.enterKey()
assert(state().export_message=='CAS: 8 variables stored')
on.escapeKey();focus(3)
local before,saved=state(),on.save()
assert(before.result~=nil and before.summary~=nil and before.q_sw>0 and before.self_weight)
original=Beam.solve
local failure_calls=0
Beam.solve=function(p)
    if p.support==3 then failure_calls=failure_calls+1;return nil,'selector candidate failed' end
    return original(p)
end
-- Temporary data doubles ensure recalc really changes EI, q_sw and ON/OFF
-- before failing. Catalogue files are untouched and values are restored below.
local oldE,oldMass=DB.materials[5].E,DB.profiles[6][3]
DB.materials[5].E=oldE+1000;DB.profiles[6][3]=nil
on.enterKey()
Beam.solve=original
DB.materials[5].E=oldE;DB.profiles[6][3]=oldMass
assert(failure_calls==1)
local after=state()
assert(after.page==0 and after.sel_index==3)
assert(type(after.selector_error)=='string' and #after.selector_error>0)
assert(after.selector_error=='selector candidate failed')
assert(rawequal(after.result,before.result),'rollback must restore original result reference')
assert(rawequal(after.summary,before.summary),'rollback must restore original summary reference')
unchanged(before,after,false)
same(saved,on.save())
-- Inert keys must also preserve a visible selector error.
for _,key in ipairs{on.tabKey,function() on.charIn('5') end,on.backspaceKey,on.escapeKey} do
    local prior=state();key();unchanged(prior,state(),true)
end
-- A retry with the original solver succeeds and clears only selector error.
on.enterKey()
assert(state().page==1 and state().support==3 and state().selector_error==nil)
-- Preserve a prior model error too, when opening from an already failed model.
local bad=on.save();bad.params.L=0;bad.page=1
on.restore(bad);assert(state().err~=nil)
on.escapeKey();focus(2)
before=state()
original=Beam.solve
Beam.solve=function(p)
    if p.support==2 then return nil,'different candidate error' end
    return original(p)
end
on.enterKey()
Beam.solve=original
unchanged(before,state(),false)
assert(state().selector_error=='different candidate error' and state().err==before.err)
print('PASS: failed Enter restores exact result/summary identity, EI, old error, CAS message, weight and page; retry succeeds')

-- 8. Restore page 0 focuses the confirmed support; legacy pages remain intact.
fresh()
local zero=on.save();zero.params.support=4;zero.page=0
on.restore(zero)
assert(state().page==0 and state().sel_index==4 and state().support==4)
for _,page in ipairs{1,2,3} do
    local legacy=on.save();legacy.page=page;legacy.settings=nil
    on.restore(legacy)
    assert(on.save().page==page,'legacy page must not be forced to selector')
end
for _,invalid in ipairs{7,'x'} do
    local restored=on.save();restored.page=invalid
    on.restore(restored)
    assert(on.save().page==3 and state().result~=nil)
    on.tabKey();assert(on.save().page==1)
    on.escapeKey();assert(on.save().page==0)
    on.enterKey();assert(on.save().page==1)
    on.tabKey();on.tabKey();assert(on.save().page==3)
end
print('PASS: selector restore, legacy pages and invalid page recovery')

-- 9. All selector coordinates and approximate text extents stay on the canvas.
-- No physical LCD / font validation is claimed by this simulated canvas.
local gc={font=10,fill={},texts={},lines=0,pen=nil,rgb={}}
local function point(x,y)
    assert(type(x)=='number' and x>=0 and x<=width,'x outside window: '..tostring(x))
    assert(type(y)=='number' and y>=0 and y<=height,'y outside window: '..tostring(y))
end
function gc:setColorRGB(r,g,b) self.rgb={r,g,b} end
function gc:setFont(face,style,size) self.font=size end
function gc:getStringWidth(t) return #t*self.font*0.7 end
function gc:fillRect(x,y,w,h)
    point(x,y);point(x+w,y+h)
    self.fill[#self.fill+1]={x=x,y=y,w=w,h=h,color=self.rgb}
end
function gc:setPen(pen,style) self.pen=pen end
function gc:drawLine(x1,y1,x2,y2)
    point(x1,y1);point(x2,y2)
    assert(self.pen=='thin','selector strokes must be thin')
    self.lines=self.lines+1
end
function gc:drawString(t,x,y,anchor)
    assert(anchor=='top')
    point(x,y);point(x+self:getStringWidth(t),y+self.font+3)
    self.texts[#self.texts+1]={text=t,x=x,y=y,h=self.font+3}
end
function gc:fillPolygon() error('P1 selector must not draw loads or a moment silhouette') end
local function paint(c,has_error)
    focus(c)
    gc.fill={};gc.texts={};gc.lines=0
    local before=state()
    on.paint(gc)
    unchanged(before,state(),true)
    assert(#gc.fill==6,'expected background, header and four cards')
    assert(gc.lines==39,'expected only four beam/support schematics')
    local highlighted=0
    for i=3,6 do
        if gc.fill[i].color[1]==213 then
            highlighted=highlighted+1
            assert(i-2==c,'incorrect card highlight')
        end
    end
    assert(highlighted==1)
    local names={}
    local error_visible=false
    local cards_bottom=gc.fill[6].y+gc.fill[6].h
    for _,t in ipairs(gc.texts) do
        names[t.text]=true
        if has_error and t.y==height-33 then
            error_visible=true
            assert(#t.text>0 and #t.text<#state().selector_error,'long error must be fitted')
            assert(t.y>=cards_bottom and t.y+t.h<=height-15,'error overlaps cards or footer')
        end
    end
    for _,t in ipairs{'SELECT SYSTEM','PIN-PIN','FIX-FREE','FIX-FIX','FIX-PIN','ARROWS select | ENTER open'} do
        assert(names[t],'missing selector label '..t)
    end
    assert(error_visible==has_error)
end
for _,size in ipairs{{318,212},{320,212},{320,240}} do
    width,height=size[1],size[2]
    fresh()
    for c=1,4 do paint(c,false) end
    original=Beam.solve
    Beam.solve=function() return nil,string.rep('candidate failed ',10) end
    on.enterKey()
    Beam.solve=original
    assert(state().page==0 and state().selector_error~=nil)
    paint(4,true)
end
print('PASS: selector paint and visible errors at 318x212, 320x212 and 320x240, with thin schematics and no moment silhouettes')
'''
vm = lib.luaL_newstate()
try:
    lib.luaL_openlibs(vm)
    code = lib.luaL_loadstring(vm, script.encode())
    if code == 0:
        code = lib.lua_pcallk(vm, 0, 0, 0, 0, None)
    if code:
        raise RuntimeError(lib.lua_tolstring(vm, -1, None).decode())
finally:
    lib.lua_close(vm)
