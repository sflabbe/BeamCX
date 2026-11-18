local load_ui=dofile(root..'/tests/load_ui.lua')
local width,height=318,212
local running=false
platform={window={width=function() return width end,height=function() return height end,
    invalidate=function() end}}
timer={start=function() running=true end,stop=function() running=false end}
local function fresh() on=nil;load_ui(root..'/BeamCX.lua') end
local function state() return _BX_TEST_STATE() end
local function same(a,b)
    assert(type(a)==type(b))
    if type(a)~='table' then assert(a==b,tostring(a)..' != '..tostring(b));return end
    for k,v in pairs(a) do same(v,b[k]) end
    for k in pairs(b) do assert(a[k]~=nil) end
end
local gc={size=10,texts={}}
function gc:setFont(_,__,size) self.size=size end
function gc:getStringWidth(t) return #t:gsub('[\128-\191]','')*self.size*.7 end
function gc:getStringHeight() return self.size+3 end
function gc:setColorRGB() end
function gc:setPen() end
function gc:fillRect() end
function gc:drawLine() end
function gc:fillPolygon() end
function gc:drawString(t,x,y)
    local w,h=self:getStringWidth(t),self:getStringHeight(t)
    assert(x>=0 and y>=0 and x+w<=width+.001 and y+h<=height+.001,
        'outside screen: '..t..' at '..x..','..y..' size '..w..','..h)
    for _,b in ipairs(self.texts) do
        assert(x+w<=b.x or b.x+b.w<=x or y+h<=b.y or b.y+b.h<=y,
            'overlap: '..t..' and '..b.t..' at '..x..','..y)
    end
    self.texts[#self.texts+1]={t=t,x=x,y=y,w=w,h=h}
end
local function paint()
    gc.texts={};on.paint(gc)
    local texts={};for _,v in ipairs(gc.texts) do texts[#texts+1]=v.t end
    return table.concat(texts,'\n')
end
local function includes(text,wanted) assert(text:find(wanted,1,true),wanted..' missing from '..text) end
local function results()
    on.tabKey()
    if running then on.timer() end
    assert(state().result)
end
local function export()
    local values={}
    var={store=function(k,v) values[k]=v end}
    on.enterKey()
    return values
end
fresh()
local defaults=on.save()
local legacy=dofile(root..'/tests/fixtures/beam_v050_saved.lua')
for _,doc in ipairs(legacy) do
    on.restore(doc);same(on.save(),defaults)
    assert(state().restore_notice=='Invalid document or version: defaults restored')
end
local docs=dofile(root..'/tests/current_documents.lua')(defaults)
for _,doc in ipairs(docs) do
    on.restore(doc);assert(state().restore_notice==nil)
    same(on.save(),doc)
end
-- Actual user pages: all presets, material families, result modes and table pages.
for _,size in ipairs{{318,212},{320,212},{320,240}} do
    width,height=size[1],size[2]
    fresh();paint()
    local invalid=on.save();invalid.params.L=0;on.restore(invalid);paint()
    for support=1,5 do
        for _,material in ipairs{1,2,5} do
            local doc=on.save()
            doc.params.support=support;doc.section.material=material
            doc.page=1;doc.mode=1
            on.restore(doc);paint()
            if support==5 then
                for i=2,11 do on.arrowDown();paint() end
            end
            results()
            for mode=1,3 do paint();on.arrowRight() end
            paint();export();paint()
            if support==5 then on.arrowDown();paint();on.arrowUp();paint() end
            on.tabKey();paint()
            for i=1,9 do on.arrowDown();paint() end
            for i=1,9 do on.arrowUp();paint() end
        end
    end
end
print('PASS English layouts: selector, all inputs/sections, all M/V/w and both tables in all target windows')

-- Common formatting is presentation-only; tiny values keep sign and magnitude.
fresh()
local fmt=state().format_number
for _,case in ipairs{{27.58,'27.58'},{8.43,'8.43'},{15,'15.00'},
    {3.96,'3.96'},{5.1,'5.10'},{4,'4.00'},{1263.4,'1263.40'},{1.35,'1.35'},
    {0,'0.00'},{-1/math.huge,'0.00'},{1e-8,'1.00e-08'},{-1e-8,'-1.00e-08'},
    {.0049,'4.90e-03'},{-.0049,'-4.90e-03'},{1e12,'1.00e+12'}} do
    assert(fmt(case[1])==case[2],fmt(case[1])..' != '..case[2])
end
local old_docs=dofile(root..'/tests/current_documents.lua')(on.save())
for _,doc in ipairs(old_docs) do
    doc.page=1;doc.mode=1
    on.restore(doc);same(on.save(),doc)
    if doc.params.support==5 then on.arrowDown() else on.arrowDown() end
    local text='6.123456789012345'
    for ch in text:gmatch('.') do on.charIn(ch) end
    assert(state().typing==text);includes(paint(),text..'_')
    on.enterKey()
    local saved=on.save()
    local actual=saved.params.support==5 and saved.continuous.spans[1] or saved.params.L
    assert(actual==tonumber(text),'editing rounded the stored input')
    -- Backspace and cancel must not round the previously committed value.
    on.charIn('9');on.backspaceKey();on.escapeKey();same(on.save(),saved)
    results()
    for i=1,3 do on.arrowRight() end
    local values=export()
    local sum=state().summary
    local expected
    if saved.params.support==5 then
        expected={bc_mmax=sum.moment_max,bc_mmin=sum.moment_min,bc_vabs=sum.shear_absolute_max,
            bc_rmax=sum.reaction_max,bc_wmax=sum.deflection_absolute_max*1000,
            bc_xwmax=sum.deflection_position,bc_ei=sum.rigidity,bc_n=sum.span_count}
    else expected=sum end
    same(values,expected)
    assert(values[saved.params.support==5 and 'bc_ei' or 'bx_ei']==10000.123456789)
    local before=on.save();paint();paint();same(on.save(),before)
end
print('PASS display formatting, full keyboard precision, original saves and full-precision bx_*/bc_* exports')

-- Check signed/tiny values, high ratios, concrete and large catalogue EI too.
width,height=318,212
for _,support in ipairs{1,2,3,4,5} do
    for _,load in ipairs{-10,1e-8,0} do
        local doc=defaults
        doc.params.support=support;doc.params.q=load;doc.page=1;doc.mode=1
        doc.continuous.g=load;doc.continuous.q=load/2
        on.restore(doc);paint();results()
        for mode=1,3 do paint();on.arrowRight() end
        paint()
        if support==5 then on.arrowDown();paint() end
    end
end
print('PASS small-screen negative/zero/tiny load results, scientific values and large ratios')

-- Typed tiny values remain entirely visible; formatting never edits the buffer.
fresh();on.arrowRight();on.arrowDown();on.enterKey();on.arrowDown()
local tiny='0.000000000000000001'
for ch in tiny:gmatch('.') do on.charIn(ch) end
includes(paint(),tiny..'_');assert(state().typing==tiny)
on.escapeKey()
fresh();on.enterKey();on.arrowDown()
for ch in tiny:gmatch('.') do on.charIn(ch) end
includes(paint(),tiny..'_');assert(state().typing==tiny)
on.escapeKey()
on.tabKey();on.tabKey();on.arrowDown()
for ch in tiny:gmatch('.') do on.charIn(ch) end
includes(paint(),tiny..'_');assert(state().typing==tiny)
on.escapeKey()
-- Validation and CAS feedback are English, visible, and preserve export precision.
fresh();on.enterKey();on.arrowDown()
on.charIn('0');on.enterKey();includes(paint(),'invalid beam dimensions, rigidity or loads')
fresh();on.enterKey();results();on.enterKey()
var={store=function() return 'cannot store' end}
on.enterKey();includes(paint(),'CAS ERROR bx_mmax: cannot store')
-- A genuine long engine diagnostic must wrap entirely in the selector footer.
on.escapeKey()
local original=Frame.solve
local diagnostic='member compatibility failed: member 1 (relative 1.23e-06, dw 1.23e-09, drz 2.34e-09, w scale 3.45e-05, rz scale 4.56e-05)'
Frame.solve=function() return nil,diagnostic end
on.enterKey();Frame.solve=original
local text=paint()
local parts={}
for _,v in ipairs(gc.texts) do if v.y>=height-42 and v.y<height-15 then parts[#parts+1]=v.t end end
assert(table.concat(parts,' ')==diagnostic,'engine diagnostic was truncated')
print('PASS English errors, wrapped diagnostics, CAS feedback and visible unrounded editing')
