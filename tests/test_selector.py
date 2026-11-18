"""Visual system selector: actual bundled TI-Lua, rollback and simulated canvas."""
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
script = f"local bundle={str(root / 'BeamCX.lua')!r}\nlocal load_test_bundle=dofile({str(root / 'tests/load_ui.lua')!r})\n" + r'''
local width,height=320,212
platform={window={width=function() return width end,height=function() return height end,
    invalidate=function() end}}
local function fresh()
    on=nil
    load_test_bundle(bundle)
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
    on.arrowUp();on.arrowLeft();on.arrowLeft()
    for i=2,math.min(c,3) do on.arrowRight() end
    if c>=4 then
        on.arrowLeft();on.arrowLeft();on.arrowDown()
        if c==5 then on.arrowRight() end
    end
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

-- 2. All twenty grid transitions, with clamping and no solves / editor changes.
local arrows={on.arrowUp,on.arrowDown,on.arrowLeft,on.arrowRight}
local expected={{1,4,1,2},{2,5,1,3},{3,5,2,3},{1,4,4,5},{2,5,4,5}}
local original=Frame.solve
local calls=0
Frame.solve=function(p) calls=calls+1;return original(p) end
for c=1,5 do
    for i,arrow in ipairs(arrows) do
        focus(c)
        local before,saved=state(),on.save()
        arrow()
        assert(state().sel_index==expected[c][i],'incorrect grid transition')
        assert(state().sel_index>=1 and state().sel_index<=5)
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
Frame.solve=original
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
    local solve=Frame.solve
    local count=0
    Frame.solve=function(p) count=count+1;return solve(p) end
    on.enterKey()
    Frame.solve=solve
    local s=state()
    assert(count==1,'Enter must solve once')
    assert(s.page==1 and s.support==c and s.result~=nil and s.selector_error==nil)
    assert(not rawequal(before.result,s.result),'Enter must install the successful result')
    eq(on.save().params.L,6);eq(on.save().params.q,10);eq(on.save().params.P,0);eq(s.EI,10000)
    eq(s.summary.bx_ra,witnesses[c].ra);eq(s.summary.bx_rb,witnesses[c].rb)
    eq(s.summary.bx_mmin,witnesses[c].mmin);eq(s.summary.bx_mmax,witnesses[c].mmax)
    eq(s.summary.bx_wmax,witnesses[c].w)
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
original=Frame.solve
local failure_calls=0
Frame.solve=function(p)
    if p.supports[2].rz==true then failure_calls=failure_calls+1;return nil,'selector candidate failed' end
    return original(p)
end
-- Temporary data doubles ensure recalc really changes EI, q_sw and ON/OFF
-- before failing. Catalogue files are untouched and values are restored below.
local oldE,oldMass=DB.materials[5].E,DB.profiles[6][3]
DB.materials[5].E=oldE+1000;DB.profiles[6][3]=nil
on.enterKey()
Frame.solve=original
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
on.restore(bad);assert(on.save().params.L==6 and state().err==nil)
on.escapeKey();focus(2)
before=state()
original=BeamPreset.solve
BeamPreset.solve=function(p)
    if p.support==2 then return nil,'different candidate error' end
    return original(p)
end
on.enterKey()
BeamPreset.solve=original
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
    assert(on.save().page==0 and state().result~=nil)
    on.enterKey();assert(on.save().page==1)
    on.escapeKey();assert(on.save().page==0)
    on.enterKey();assert(on.save().page==1)
    on.tabKey();on.tabKey();assert(on.save().page==3)
end
print('PASS: selector restore, legacy pages and invalid page recovery')

-- P3. Invalid text leaves the confirmed model valid. Idle Esc clears its error,
-- then the same confirmed system can be reopened and exported normally.
fresh();on.enterKey();on.arrowDown() -- L field
local valid=state()
on.charIn('.');on.charIn('.');on.enterKey()
assert(state().page==1 and state().err=='invalid number')
assert(rawequal(state().result,valid.result) and rawequal(state().summary,valid.summary))
on.escapeKey()
assert(state().page==0 and state().err==nil and state().support==valid.support)
on.enterKey();assert(state().page==1 and state().result~=nil)
on.tabKey();on.enterKey() -- results
local exported={}
var={store=function(name,value) exported[name]=value end}
on.enterKey()
assert(state().export_message=='CAS: 8 variables stored')
local exported_count=0
for _ in pairs(exported) do exported_count=exported_count+1 end
assert(exported_count==8);eq(exported.bx_mmax,45)
for target_page=2,3 do
    fresh();on.enterKey();on.arrowDown()
    on.charIn('.');on.charIn('.');on.enterKey()
    for i=2,target_page do on.tabKey() end
    assert(state().page==target_page and state().result~=nil and state().err=='invalid number')
    on.escapeKey();assert(state().page==0 and state().err==nil)
end
-- A failed calculation remains invalid after Esc, with its diagnostic intact.
fresh();on.enterKey();on.arrowDown();on.charIn('0');on.enterKey()
local failed=state()
assert(failed.result==nil and failed.err~=nil)
on.escapeKey();assert(state().page==0 and state().err==failed.err)
print('PASS: Esc clears errors only for a valid result; invalid text recovery exports all CAS variables')

-- P5B: old formats are intentionally rejected and use current defaults.
fresh()
on.restore{params={L=8,q=7,P=12,a=3,EI=10000,support=4},page=2,mode=2,cursor=.25}
local restored=on.save()
assert(restored.format=='0.5.0' and restored.page==0 and restored.params.support==1)
eq(restored.params.L,6);eq(restored.params.q,10)
fresh();focus(3);on.enterKey();on.escapeKey()
local selector_saved=on.save()
assert(selector_saved.page==0 and selector_saved.params.support==3)
focus(1);fresh();on.restore(selector_saved)
assert(state().page==0 and state().support==3 and state().sel_index==3)
same(selector_saved,on.save())
print('PASS: old formats rejected; current selector restores confirmed support')

-- P2. Exercise the actual private formula used by painting, without exporting
-- another app API. This is the only solver-based reference-silhouette test.
local function upvalue(fn,wanted)
    local i=1
    while true do
        local name,value=debug.getupvalue(fn,i)
        assert(name,'missing test upvalue '..wanted)
        if name==wanted then return value end
        i=i+1
    end
end
fresh()
local reference_moment=upvalue(upvalue(on.paint,'draw_selector'),'selector_moment')
for c=1,4 do
    local sol,message=BeamPreset.solve{L=1,q=1,P=0,a=0,EI=1,support=c}
    assert(sol,message)
    for j=0,10 do
        local xi=j/10
        assert(math.abs(reference_moment(c,xi)-BeamPreset.at(sol,xi).M)<1e-9,
            'reference coefficients disagree with solver for support '..c)
    end
end
print('PASS: all four closed reference-moment formulas match the solver at eleven positions')

-- 9. All selector coordinates and approximate text extents stay on the canvas.
-- No physical LCD / font validation is claimed by this simulated canvas.
local gc={font=10,fill={},texts={},lines=0,pen=nil,rgb={},curves={},axes={},schematics={}}
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
function gc:setPen(pen,style) self.pen=pen;self.style=style end
function gc:drawLine(x1,y1,x2,y2)
    point(x1,y1);point(x2,y2)
    assert(self.pen=='thin','selector strokes must be thin')
    assert(self.style=='smooth','selector strokes must match the smooth M diagram pen')
    self.lines=self.lines+1
    local segment={x1=x1,y1=y1,x2=x2,y2=y2,card=#self.fill-2}
    if self.rgb[1]==242 and self.rgb[2]==177 and self.rgb[3]==103 then
        self.curves[#self.curves+1]=segment
    elseif self.rgb[1]==115 and self.rgb[2]==132 and self.rgb[3]==148 then
        self.axes[#self.axes+1]=segment
    else self.schematics[#self.schematics+1]=segment end
end
function gc:drawString(t,x,y,anchor)
    assert(anchor=='top')
    point(x,y);point(x+self:getStringWidth(t),y+self.font+3)
    self.texts[#self.texts+1]={text=t,x=x,y=y,h=self.font+3,w=self:getStringWidth(t),font=self.font}
end
function gc:fillPolygon() error('selector schematics and silhouettes must use lines') end
local function paint(c,has_error)
    focus(c)
    gc.fill={};gc.texts={};gc.lines=0
    gc.curves={};gc.axes={};gc.schematics={}
    local before=state()
    local solve=Frame.solve
    local paint_solves=0
    Frame.solve=function(p) paint_solves=paint_solves+1;return solve(p) end
    on.paint(gc)
    Frame.solve=solve
    assert(paint_solves==0,'selector painting must never solve')
    unchanged(before,state(),true)
    assert(#gc.fill==7,'expected background, header and five cards')
    assert(#gc.curves==5*32,'expected five 32-segment moment silhouettes')
    assert(#gc.schematics==55,'expected four compact beam/support schematics')
    assert(#gc.axes==5,'expected one reference axis per card')
    assert(gc.lines==#gc.curves+#gc.axes+#gc.schematics)
    local highlighted=0
    for i=3,7 do
        if gc.fill[i].color[1]==213 then
            highlighted=highlighted+1
            assert(i-2==c,'incorrect card highlight')
        end
    end
    assert(highlighted==1)
    -- Cards have three disjoint zones at every supported window size.
    -- Name: 12 px; compact supports: 18 px; M: remaining height minus gaps.
    local preset_names={'PIN-PIN','FIX-FREE','FIX-FIX','FIX-PIN','CONTINUA'}
    local absolute_m={1/8,1/2,1/12,1/8,0}
    for j=0,32 do absolute_m[5]=math.max(absolute_m[5],math.abs(reference_moment(5,j/32))) end
    for card=1,5 do
        local box=gc.fill[card+2]
        local name_top,name_bottom=box.y+2,box.y+14
        local scheme_top,scheme_bottom=box.y+15,box.y+33
        local moment_top,moment_bottom=box.y+35,box.y+box.h-2
        assert(name_bottom<scheme_top and scheme_bottom<moment_top)
        assert(moment_bottom-moment_top>=20,'tested windows need at least 20 px for M')
        assert(box.y>=46 and box.y+box.h<=height-43,'card invades title or error / footer')
        local mid=(moment_top+moment_bottom)/2
        local left,right=box.x+12,box.x+box.w-12
        local curves,axes,schematics=0,0,0
        local amplitude=0
        local found_name=false
        for _,text in ipairs(gc.texts) do
            if text.text==preset_names[card] then
                found_name=true
                assert((text.font==9 or text.font==8) and text.y>=name_top and text.y+text.h<=name_bottom)
                assert(text.x>=box.x and text.x+text.w<=box.x+box.w)
            end
        end
        assert(found_name,'missing card name')
        for _,line in ipairs(gc.schematics) do
            if line.card==card then
                schematics=schematics+1
                for _,p in ipairs{{line.x1,line.y1},{line.x2,line.y2}} do
                    assert(p[1]>=box.x and p[1]<=box.x+box.w)
                    assert(p[2]>=scheme_top and p[2]<=scheme_bottom,'schematic leaves its zone')
                end
            end
        end
        assert(schematics>0)
        for _,line in ipairs(gc.axes) do
            if line.card==card then
                axes=axes+1
                eq(line.x1,left);eq(line.x2,right);eq(line.y1,mid);eq(line.y2,mid)
            end
        end
        assert(axes==1)
        for _,line in ipairs(gc.curves) do
            if line.card==card then
                curves=curves+1
                for _,p in ipairs{{line.x1,line.y1},{line.x2,line.y2}} do
                    assert(p[1]>=left and p[1]<=right)
                    assert(p[2]>=moment_top and p[2]<=moment_bottom,'silhouette leaves its zone')
                    local xi=(p[1]-left)/(right-left)
                    local m=reference_moment(card,xi)
                    eq(p[2],mid+m*(moment_bottom-moment_top)/(2*absolute_m[card]))
                    if m>1e-12 then assert(p[2]>mid,'positive M must be below axis')
                    elseif m< -1e-12 then assert(p[2]<mid,'negative M must be above axis')
                    else eq(p[2],mid) end
                    if card==1 and xi>0 and xi<1 then assert(p[2]>mid,'PIN-PIN interior must be below') end
                    if card==2 and xi<1 then assert(p[2]<mid,'FIX-FREE interior must be above') end
                    amplitude=math.max(amplitude,math.abs(p[2]-mid))
                end
            end
        end
        assert(curves==32)
        eq(amplitude,(moment_bottom-moment_top)/2)
    end
    local names={}
    local legend_count=0
    local error_visible=false
    local cards_bottom=gc.fill[7].y+gc.fill[7].h
    for _,t in ipairs(gc.texts) do
        names[t.text]=true
        if t.text=='M (q>0)' then legend_count=legend_count+1 end
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
    assert(legend_count==1,'reference M legend must appear exactly once')
end
for _,size in ipairs{{318,212},{320,212},{320,240}} do
    width,height=size[1],size[2]
    fresh()
    for c=1,5 do paint(c,false) end
    focus(4)
    original=Frame.solve
    Frame.solve=function() return nil,string.rep('candidate failed ',10) end
    on.enterKey()
    Frame.solve=original
    assert(state().page==0 and state().selector_error~=nil)
    paint(4,true)
end
print('PASS: signed moment silhouettes, disjoint zones, one legend and zero solves per paint at 318x212, 320x212 and 320x240')
-- Below the 14 px silhouette minimum, names / supports remain and M is omitted.
width,height=318,180
fresh()
gc.fill={};gc.texts={};gc.lines=0;gc.curves={};gc.axes={};gc.schematics={}
local solves_small=0
original=Frame.solve
Frame.solve=function(p) solves_small=solves_small+1;return original(p) end
on.paint(gc)
Frame.solve=original
assert(#gc.curves==0 and #gc.axes==0 and #gc.schematics==55 and solves_small==0)
print('PASS: short silhouette zones omit M while retaining the compact support schematics')
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
