local load_ui=dofile(root..'/tests/load_ui.lua')
local width,height=318,212
local invalidates,starts,stops=0,0,0
local running=false
platform={window={width=function() return width end,height=function() return height end,
    invalidate=function() invalidates=invalidates+1 end}}
timer={start=function(t) assert(t>0 and t<=.1);starts=starts+1;running=true end,
    stop=function() stops=stops+1;running=false end}
local function fresh() on=nil;running=false;load_ui(root..'/BeamCX.lua') end
local function state() return _BX_TEST_STATE() end
local function eq(a,b,tol)
    assert(type(a)=='number' and math.abs(a-b)<=(tol or 1e-10)*math.max(1,math.abs(b)),
        tostring(a)..' != '..tostring(b))
end
local function same(a,b)
    assert(type(a)==type(b),'different types')
    if type(a)~='table' then assert(a==b);return end
    for k,v in pairs(a) do same(v,b[k]) end
    for k in pairs(b) do assert(a[k]~=nil,'extra key '..tostring(k)) end
end
local gc={font=10,texts={},lines={},rgb={}}
function gc:setColorRGB(r,g,b) self.rgb={r,g,b} end
function gc:setFont(_,__,size) self.font=size end
function gc:getStringWidth(t) return #string.gsub(t,'[\128-\191]','')*self.font*.7 end
function gc:setPen() end
local function point(x,y)
    assert(x>=0 and x<=width and y>=0 and y<=height,'outside canvas: '..x..', '..y)
end
function gc:fillRect(x,y,w,h) point(x,y);point(x+w,y+h) end
function gc:fillPolygon() end
function gc:drawLine(x,y,xx,yy)
    point(x,y);point(xx,yy)
    self.lines[#self.lines+1]={x,y,xx,yy,color=self.rgb}
end
function gc:drawString(t,x,y)
    point(x,y);point(x+self:getStringWidth(t),y+self.font+3)
    self.texts[#self.texts+1]={t=t,x=x,y=y}
end
local function paint()
    gc.texts={};gc.lines={}
    local sol=state().result
    local saved=Frame.solve
    Frame.solve=function() error('paint solved') end
    local at=Frame.at
    Frame.at=function() error('continuous paint recovered') end
    local env=sol and sol.envelope_at
    if env then sol.envelope_at=function() error('paint queried envelope') end end
    on.paint(gc)
    Frame.solve=saved;Frame.at=at
    if env then sol.envelope_at=env end
    local texts={}
    for _,t in ipairs(gc.texts) do texts[#texts+1]=t.t end
    return table.concat(texts,'\n')
end
local function contains(text,needle) assert(string.find(text,needle,1,true),needle..' missing from '..text) end
local function open_continuous()
    on.arrowRight();on.arrowDown();assert(state().sel_index==5)
    on.enterKey();assert(state().page==1 and state().support==5)
end
local function edit(text)
    for ch in text:gmatch('.') do on.charIn(ch) end
    on.enterKey()
end
local function field(index)
    while state().edit_index<index do on.arrowDown() end
    while state().edit_index>index do on.arrowUp() end
end
local function calculate(n)
    local queries=0
    local continuous_solve=ContinuousPreset.solve
    ContinuousPreset.solve=function(p)
        local result,message=continuous_solve(p)
        if result then
            local envelope=result.envelope_at
            result.envelope_at=function(...) queries=queries+1;return envelope(...) end
        end
        return result,message
    end
    local solve=Frame.solve
    local calls=0
    Frame.solve=function(p) calls=calls+1;return solve(p) end
    local before=invalidates
    on.tabKey()
    assert(state().page==2 and state().calculating and running and calls==0)
    assert(invalidates>before)
    contains(paint(),'Calculando…')
    on.timer()
    ContinuousPreset.solve=continuous_solve
    Frame.solve=solve
    assert(queries==21*n+1,'samples and initial cursor must be queried exactly once')
    assert(not running and not state().calculating and not state().stale)
    assert(state().result and calls==n+1,'expected n+1 solves, got '..calls)
    local result=state().result
    local samples=state().samples
    assert(#samples==21*n)
    for i=2,n do
        local s=samples.supports[i]
        assert(s.left and s.right)
        eq(s.left.x,result.supports[i].position);eq(s.right.x,s.left.x)
        eq(s.left.Vmax,result.envelope_at(s.left.x,'left').Vmax)
        eq(s.right.Vmin,result.envelope_at(s.right.x,'right').Vmin)
    end
    return result
end

-- E is entered via the selector, input fields and the shared section page.
fresh();open_continuous()
local solve=Frame.solve
local calls=0
Frame.solve=function(p) calls=calls+1;return solve(p) end
for i=2,4 do field(i);edit('6') end
field(7);edit('10');field(8);edit('5')
field(9);edit('1.35');field(10);edit('1');field(11);edit('1.5')
assert(calls==0 and state().stale and state().samples==nil)
Frame.solve=solve
local e=calculate(3)
local reference=assert(ContinuousPreset.solve{spans={6,6,6},left='PIN',right='PIN',g=10,q=5,
    EI=10000,gG_sup=1.35,gG_inf=1,gQ=1.5,limit=250})
same(e.spans,reference.spans);same(e.supports,reference.supports);same(e.summary,reference.summary)
for i=1,3 do paint();on.arrowRight() end
assert(on.save().mode==4)
local text=paint();contains(text,'Vanos');contains(text,'↓15.326')
contains(text,'γ: OPEN (EN 1990 A1 + NA)')
on.arrowDown();contains(paint(),'Apoyos');assert(state().table_page==2)
on.arrowUp();assert(state().table_page==1)
local exported={}
var={store=function(k,v) assert(string.sub(k,1,3)=='bc_');exported[k]=v end}
on.enterKey()
local expected={bc_mmax=66.0005357143,bc_mmin=-80.1,bc_vabs=76.35,bc_rmax=143.1,
    bc_wmax=15.3264571214,bc_ei=10000,bc_n=3}
for k,v in pairs(expected) do eq(exported[k],v) end
assert(math.min(math.abs(exported.bc_xwmax-2.75420947417),math.abs(exported.bc_xwmax-15.24579052583))<1e-9)
assert(exported.bc_xwmax==e.summary.deflection_position)
local span=exported.bc_xwmax<6 and 1 or 3
local wx=exported.bc_xwmax-e.spans[span].offset
local reached=math.max(math.abs(Frame.at(state().characteristic[1],span,wx).w),
    math.abs(Frame.at(state().characteristic[2],span,wx).w))
eq(reached,reference.summary.deflection_absolute_max,1e-9)
eq(reached*1000,exported.bc_wmax,1e-9)
local count=0;for _ in pairs(exported) do count=count+1 end;assert(count==8)
contains(paint(),'CAS: 8 variables stored')
print('PASS E: real UI -> deferred Frame -> identical span/support tables -> eight bc_* values')

-- Cached plots: zero recovery on paint; one exact envelope query per movement.
on.arrowRight();assert(on.save().mode==1)
local samples=state().samples
local function verify_curves(mode)
    local counts={0,0}
    local top,bottom=85,height-82
    local mid=(top+bottom)/2
    local keys=mode==1 and {'Mmax','Mmin'} or (mode==2 and {'Vmax','Vmin'} or {'wodd','weven'})
    local scale=1e-10
    for _,v in ipairs(samples) do for _,key in ipairs(keys) do scale=math.max(scale,math.abs(v[key])) end end
    local jumps=0
    for _,line in ipairs(gc.lines) do
        local color=line.color
        local k=color[1]==242 and 1 or (color[1]==80 and 2 or nil)
        if k then
            counts[k]=counts[k]+1
            local a,b=samples[counts[k]],samples[counts[k]+1]
            local sign=mode==2 and -1 or 1
            eq(line[2],mid+sign*(bottom-top)*.45*a[keys[k]]/scale)
            eq(line[4],mid+sign*(bottom-top)*.45*b[keys[k]]/scale)
            if mode==1 and a[keys[k]]>1e-9 then assert(line[2]>mid) end
            if mode==2 and a.x==b.x and math.abs(line[2]-line[4])>1e-8 then jumps=jumps+1 end
        end
    end
    assert(counts[1]==#samples-1 and counts[2]==#samples-1)
    if mode==2 then assert(jumps==4,'both shear envelopes must jump at both internal supports') end
end
local queries=0
local env=e.envelope_at
e.envelope_at=function(...) queries=queries+1;return env(...) end
for mode=1,3 do
    local before=queries
    on.arrowUp();assert(queries==before+1)
    local c=state().cursor_value
    local exact=env(c.x)
    for _,k in ipairs{'Mmax','Mmin','Vmax','Vmin'} do eq(c[k],exact[k]) end
    if mode==3 then
        local i=c.x<=6 and 1 or (c.x<=12 and 2 or 3)
        eq(c.wodd,-Frame.at(state().characteristic[1],i,c.x-e.spans[i].offset).w*1000)
        eq(c.weven,-Frame.at(state().characteristic[2],i,c.x-e.spans[i].offset).w*1000)
    end
    paint();verify_curves(mode);paint();assert(queries==before+1 and rawequal(samples,state().samples))
    on.arrowRight()
end
-- Revisit input and results without editing: no timer or new solve/cache.
on.tabKey();assert(state().page==3);paint()
on.tabKey();local before=starts;on.tabKey()
assert(starts==before and rawequal(e,state().result) and rawequal(samples,state().samples))
on.arrowRight() -- mode 4 -> M
-- Find support with the actual cursor keys (support is included even off the grid).
for i=1,40 do
    on.arrowDown()
    local c=state().cursor_value
    if c.left then
        eq(c.left.Vmax,env(c.x,'left').Vmax);eq(c.right.Vmin,env(c.x,'right').Vmin)
        contains(paint(),'V izq');contains(paint(),'V der');break
    end
    assert(i<40,'cursor missed every support')
end
print('PASS cached paint and exact cursor, including both support shear sides')

-- Transactional validation, n resizing, scroll and final MAX_SPANS=5.
on.tabKey();on.tabKey();field(2)
local valid=on.save();local old_result=state().result
edit('0');same(on.save(),valid);assert(rawequal(old_result,state().result))
edit('7');assert(state().stale and state().result==nil and state().samples==nil)
field(1);on.arrowRight();on.arrowRight();on.arrowRight()
assert(#on.save().continuous.spans==5)
local lengths=on.save().continuous.spans
assert(lengths[1]==7 and lengths[4]==6 and lengths[5]==6)
field(6);edit('8');field(1);on.arrowLeft();on.arrowRight()
assert(on.save().continuous.spans[5]==6,'new span must copy the last retained length')
field(2);edit('4.3');field(3);edit('5.7')
field(7);on.arrowRight();assert(on.save().continuous.left=='FIX')
field(8);on.arrowRight();assert(on.save().continuous.right=='FIX')
field(13);paint();assert(state().edit_top>1)
edit('0');assert(on.save().continuous.gQ==1.5)
local five=calculate(5)
for i=1,4 do paint();on.arrowRight() end
on.arrowDown();paint();on.arrowUp();paint()
-- All exact support coordinates and shear jumps occur in the drawing cache.
local cache=state().samples
for i=2,5 do assert(cache.supports[i].left.x==cache.supports[i].right.x) end
print('PASS 2..5 spans, retained lengths, PIN/FIX, invalid edit rollback and scrolling')

-- Shared sections: self-weight goes to g once; changing L/limit never solves immediately.
on.tabKey();assert(state().page==3)
solve=Frame.solve;calls=0;Frame.solve=function(p) calls=calls+1;return solve(p) end
on.arrowRight();assert(on.save().section.material==2)
on.arrowDown();on.arrowDown();on.arrowDown();on.enterKey()
assert(on.save().settings.self_weight)
on.arrowDown();on.enterKey();assert(on.save().settings.limit==300)
paint();assert(calls==0)
on.tabKey();Frame.solve=solve
local weighted=calculate(5)
eq(weighted.parameters.g,on.save().continuous.g+DB.compute(on.save().section).q_sw)
eq(weighted.parameters.q,on.save().continuous.q)
for _,s in ipairs(weighted.spans) do assert(s.deflection.selected_limit==300);eq(s.deflection.ratio,s.length/s.deflection.governing.absolute) end
print('PASS shared sections, EI, self-weight only in g and per-span L/300')

-- Restore is field-wise and never solves continuous, even a saved results page.
local saved=on.save()
solve=Frame.solve;calls=0;Frame.solve=function(p) calls=calls+1;return solve(p) end
on.restore(saved)
assert(calls==0 and state().page==1 and state().stale and state().result==nil and not running)
local restored=on.save();restored.page=saved.page;same(restored,saved)
Frame.solve=solve
calculate(5)
-- Every saved field is mandatory and validated before accepting any of them.
local valid_saved=on.save()
fresh()
local defaults=on.save()
local function copy(t)
    if type(t)~='table' then return t end
    local out={};for k,v in pairs(t) do out[k]=copy(v) end;return out
end
local notice='Documento no válido o de otra versión: valores por defecto'
local function rejected(doc)
    on.restore(valid_saved)
    on.restore(doc)
    same(on.save(),defaults)
    assert(state().page==0 and state().restore_notice==notice and state().result and not running)
    contains(paint(),'Documento no válido o de otra versión:')
    contains(paint(),'valores por defecto')
    assert(state().restore_notice==notice,'painting and saving must retain notice')
end
local bad=copy(valid_saved);bad.params.L=0;rejected(bad)
-- Real v0.4 on.save shape: no format or continuous parameters, no migration.
local v04={params={L=9,q=-8,P=13,a=2,EI=27000,support=4},
    section={material=5,profile=10,b=300,h=600,manualEI=27000},
    settings={self_weight=true,limit=300},page=2,mode=4,cursor=.7}
rejected(v04)
for _,change in ipairs{
    {'format','0.4.0'},{'page',2.5},{'page',7},{'mode',0},{'cursor',math.huge},
    {'params','support',2.5},{'params','L',0},{'params','q',0/0},{'params','P','bad'},
    {'params','a',7},{'params','EI',-1},{'section','material','bad'},
    {'section','profile',999},{'section','b',-3},{'section','h',0},{'section','manualEI',0},
    {'settings','self_weight',1},{'settings','limit',275},
    {'continuous','spans',{6}},{'continuous','spans',{2,-3,6}},
    {'continuous','spans',{6,6,math.huge}},{'continuous','left','FREE'},
    {'continuous','right',false},{'continuous','g','bad'},{'continuous','q',0/0},
    {'continuous','gG_sup',0},{'continuous','gG_inf',0/0},{'continuous','gQ',-1}
} do
    bad=copy(valid_saved)
    if #change==2 then bad[change[1]]=change[2] else bad[change[1]][change[2]]=change[3] end
    rejected(bad)
end
for _,key in ipairs{'params','section','settings','continuous','format','page','mode','cursor'} do
    bad=copy(valid_saved);bad[key]=nil;rejected(bad)
end
for _,key in ipairs{on.tabKey,on.escapeKey,on.backspaceKey,function() on.charIn('5') end,
    on.arrowUp,on.arrowDown,on.arrowLeft,on.arrowRight,on.enterKey} do
    rejected(v04);key();assert(state().restore_notice==nil,'first action must clear notice')
end
on.restore(defaults)
local simple=on.save();simple.params.support=4;simple.params.q=-3;simple.page=2;simple.mode=4
on.restore(simple);same(on.save(),simple)
var={store=function(k) assert(string.sub(k,1,3)=='bx_') end};on.enterKey()
assert(state().export_message=='CAS: 8 variables stored')
print('PASS current save/restore both modes; invalid documents reset completely with notice; namespace separation')

-- A failed deferred candidate restores the previous solved model and references.
on.escapeKey()
local previous=state();local previous_save=on.save()
on.arrowUp();on.arrowLeft();on.arrowLeft();open_continuous()
local broken=ContinuousPreset.solve
ContinuousPreset.solve=function() return nil,'deferred failure' end
on.tabKey();contains(paint(),'Calculando…');on.timer()
ContinuousPreset.solve=broken
local rolled=state()
assert(rolled.page==0 and rolled.support==4 and rolled.selector_error=='deferred failure')
assert(rawequal(rolled.result,previous.result) and rawequal(rolled.summary,previous.summary))
same(on.save(),previous_save)
-- Retry succeeds; abandoning a queued solve cancels it.
on.enterKey();on.tabKey();on.escapeKey();assert(not running and state().page==0)
on.timer();assert(state().page==0 and state().support==5)
print('PASS deferred selector rollback, retry and timer cancellation')

-- Target canvas: scroll every input row and render all result modes and table pages.
for _,size in ipairs{{318,212},{320,212},{320,240}} do
    width,height=size[1],size[2]
    for n=2,5 do
        fresh();open_continuous()
        if n==2 then on.arrowLeft() end
        for i=4,n do on.arrowRight() end
        assert(#on.save().continuous.spans==n)
        for i=1,n+8 do field(i);paint() end
        calculate(n)
        for i=1,3 do paint();on.arrowRight() end
        paint();on.arrowDown();paint()
    end
end
print('PASS all continuous screens at 318x212, 320x212 and 320x240')
