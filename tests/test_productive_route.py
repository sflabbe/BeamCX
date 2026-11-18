"""P2B: real UI events reach Frame; cursor, sections, settings and RESOLVED cases."""
import ctypes
import importlib.util
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('golden_builder', root/'tools/make_beam_golden.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
fixture = json.loads((root/'tests/fixtures/beam_v033_golden.json').read_text())
adjudication = json.loads((root/'tests/fixtures/beam_v033_adjudicated.json').read_text())
resolved = [c for c in fixture['cases'] if c['name'] in adjudication['references']
            and c['name'] not in adjudication['adjudicated']]
assert len(resolved) == 5
source = (root/'BeamCX.lua').read_text()
for declaration in ('Frame = {}', 'BeamPreset = {}', 'local SectionDB=DB', 'function on.paint',
                    'function on.save', 'function on.restore'):
    assert declaration in source, declaration
assert 'Beam.' not in source and 'require(' not in source
assert '_BX_TEST_STATE' not in source and 'load_particular' not in source
assert not (root/'src/beam_core.lua').exists()
script = 'local bundle=' + builder.literal(str(root/'BeamCX.lua')) + '\n'
script += 'local resolved=' + builder.literal(resolved) + '\n'
script += 'local load_test_bundle=dofile(' + builder.literal(str(root/'tests/load_ui.lua')) + ')\n'
script += r'''
local width,height=318,212
platform={window={width=function() return width end,height=function() return height end,
    invalidate=function() end}}
load_test_bundle(bundle)
local function eq(a,b)
    assert(type(a)=='number' and math.abs(a-b)<=1e-9*math.max(1e-10,math.abs(b)),
        tostring(a)..' != '..tostring(b))
end
local function same(a,b)
    if type(a)~='table' then assert(a==b);return end
    assert(type(b)=='table')
    for k,v in pairs(a) do same(v,b[k]) end
    for k in pairs(b) do assert(a[k]~=nil) end
end
local function state() return _BX_TEST_STATE() end
local calls=0
local original=Frame.solve
Frame.solve=function(model)
    calls=calls+1
    local p=on.save().params
    local info=assert(DB.compute(on.save().section))
    local weight=on.save().settings.self_weight and info.q_sw or 0
    eq(model.members[1].EI,info.EI)
    eq(model.nodes[2].x,p.L)
    eq(model.member_loads[1].q,-(p.q+weight))
    if p.P~=0 then
        assert(#model.member_loads==2)
        eq(model.member_loads[2].P,-p.P);eq(model.member_loads[2].a,p.a)
    else assert(#model.member_loads==1) end
    return original(model)
end
local gc={texts={}}
function gc:setColorRGB() end
function gc:setPen() end
function gc:drawLine() end
function gc:fillRect() end
function gc:fillPolygon() end
function gc:setFont() end
function gc:getStringWidth(t) return #t*6 end
function gc:drawString(t) self.texts[#self.texts+1]=t end
local function paint()
    gc.texts={};local before=calls;on.paint(gc)
    assert(calls==before,'paint must not solve')
    return table.concat(gc.texts,'\n')
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
local function cursor_text()
    local s=state().result
    local saved=on.save()
    local v=BeamPreset.at(s,s.parameters.L*saved.cursor)
    local values={v.M,v.V,v.w*1000}
    local names={'M [kNm]','V [kN]','w [mm]'}
    local function fmt(x) return math.abs(x)<1e-10 and '0' or string.format('%.5g',x) end
    local text='x='..fmt(saved.cursor*s.parameters.L)..' m  '..names[saved.mode]..'='..fmt(values[saved.mode])
    assert(string.find(paint(),text,1,true),'cursor value differs from BeamPreset.at')
    eq(v.N,0)
    for d in pairs(s.frame.fixed) do eq(s.frame.u[d],0) end
end
local names={'bx_mmax','bx_mmin','bx_vabs','bx_wmax','bx_xwmax','bx_ra','bx_rb','bx_ei'}
local function export()
    local values={};var={store=function(k,v) assert(values[k]==nil);values[k]=v end}
    on.enterKey()
    assert(state().export_message=='CAS: 8 variables stored')
    local n=0;for _ in pairs(values) do n=n+1 end;assert(n==8)
    for _,name in ipairs(names) do eq(values[name],state().result.summary[name]) end
end
for _,size in ipairs{{318,212},{320,240}} do
    width,height=size[1],size[2]
    for support=1,4 do
        if on.save().page~=0 then on.escapeKey() end
        focus(support);paint()
        local before=calls;on.enterKey()
        assert(calls==before+1 and state().result and state().support==support)
        on.tabKey()
        assert(on.save().mode==1)
        for mode=1,3 do
            assert(on.save().mode==mode)
            cursor_text();on.arrowUp();cursor_text();on.arrowDown();cursor_text()
            on.arrowRight()
        end
        local result,summary=state().result,state().summary
        before=calls
        on.arrowUp();assert(on.save().settings.limit==300)
        assert(result.deflection_check.selected_limit==300)
        on.arrowDown();assert(on.save().settings.limit==250)
        assert(result.deflection_check.selected_limit==250)
        assert(calls==before and rawequal(result,state().result) and rawequal(summary,state().summary))
        export()
        -- An explicit v0.3.3 document retains its complete input/settings contract.
        local saved=on.save()
        saved.section.material=5;saved.section.profile=16
        saved.settings.self_weight=true;saved.settings.limit=300
        saved.params.EI=DB.compute(saved.section).EI
        on.restore(saved);same(saved,on.save())
        local persisted=on.save();on.restore(persisted);same(persisted,on.save())
        -- Reset to manual on the existing page before the next selector case.
        saved.section.material=1;saved.settings.self_weight=false;saved.settings.limit=250
        saved.mode=1;on.restore(saved)
    end
end
-- Material change through section keys changes rigidity and physical deflection.
local manual=on.save();manual.params.support=1;manual.page=3;manual.mode=1
on.restore(manual)
local ei,w=state().EI,state().result.deflection.absolute
local before=calls;on.arrowRight() -- MANUAL -> concrete
assert(calls==before+1 and state().EI~=ei)
eq(state().result.deflection.absolute*state().EI,w*ei)
-- Repeated ON/OFF via real section events never changes q user or accumulates weight.
on.arrowDown();on.arrowDown();on.arrowDown() -- width, height, self-weight
local q=on.save().params.q
for i=1,3 do
    on.enterKey();assert(on.save().settings.self_weight)
    eq(state().result.parameters.q,q+state().q_sw)
    on.enterKey();assert(not on.save().settings.self_weight)
    eq(state().result.parameters.q,q)
end
-- Actual L/P edits, including the unloaded model.
local zero=on.save();zero.params.q=0;zero.params.P=0;zero.page=1;zero.section.material=1
on.restore(zero)
local function edit(text) for ch in text:gmatch('.') do on.charIn(ch) end;on.enterKey() end
on.arrowDown();edit('8');eq(state().result.parameters.L,8)
assert(state().result.deflection.absolute==0)
on.arrowDown();on.arrowDown();edit('12');eq(state().result.parameters.P,12)
assert(state().result.deflection.absolute>0)
edit('0');assert(state().result.deflection.absolute==0)
print('PASS productive Frame invocation: selector, real input, sections and restore; all four M/V/w cursors; limit changes/paint solve zero times')
for _,case in ipairs(resolved) do
    local saved=on.save()
    saved.params=case.p;saved.section.material=1;saved.section.manualEI=case.p.EI
    saved.settings.self_weight=false;saved.page=2;saved.mode=4
    local before=calls;on.restore(saved)
    assert(calls==before+1 and state().result~=nil and state().err==nil,case.name)
    export();paint()
    print('PASS productive RESOLVED '..case.name)
end
Frame.solve=original
'''
lib = ctypes.CDLL('liblua5.4.so.0')
lib.luaL_newstate.restype = ctypes.c_void_p
lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
lib.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                           ctypes.c_longlong, ctypes.c_void_p]
lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
lib.lua_tolstring.restype = ctypes.c_char_p
lib.lua_close.argtypes = [ctypes.c_void_p]
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
