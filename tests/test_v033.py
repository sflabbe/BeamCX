"""v0.3.3 signed loads, drawing boxes, reference length and unchanged CAS results."""
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
local width,height=318,212
platform={window={width=function() return width end,height=function() return height end,
    invalidate=function() end}}
dofile(bundle)
local function eq(a,b)
    assert(type(a)=='number' and math.abs(a-b)<1e-9*math.max(1,math.abs(b)),
        tostring(a)..' != '..tostring(b))
end
local function contains(text,fragment) return string.find(text,fragment,1,true)~=nil end
local function model(support,material,q,P,page,mode)
    return {params={L=6,q=q or 10,P=P or 0,a=3,EI=10000,support=support},
        section={material=material or 1,profile=10,b=250,h=450,manualEI=10000},
        settings={self_weight=false,limit=250},page=page or 2,mode=mode or 1,cursor=0.5}
end
-- The simulated metrics exercise the same measurement API used on the device.
-- These are not a claim about physical LCD pixels or exact handheld font sizes.
local text_height=nil
local gc={font=10,rgb={},pen='',lines={},heads={},texts={},beam=nil}
function gc:setColorRGB(r,g,b) self.rgb={r,g,b} end
function gc:setFont(face,style,size) self.font=size end
function gc:getStringWidth(t)
    local n=0
    for ch in string.gmatch(t,'.') do
        n=n+((ch==' ' or ch=='i' or ch=='l') and 0.3 or 0.65)*self.font
    end
    return n
end
local function measured_height(self,t) return text_height or self.font+4 end
function gc:setPen(pen,style) self.pen=pen end
function gc:fillRect() end
local function kind(rgb)
    if rgb[1]==230 and rgb[2]==179 and rgb[3]==83 then return 'q' end
    if rgb[1]==235 and rgb[2]==100 and rgb[3]==105 then return 'P' end
end
function gc:drawLine(x1,y1,x2,y2)
    local line={x1=x1,y1=y1,x2=x2,y2=y2,kind=kind(self.rgb),pen=self.pen}
    self.lines[#self.lines+1]=line
    if self.rgb[1]==216 and self.rgb[2]==228 and self.rgb[3]==237 and self.pen=='medium' then
        self.beam=line
    end
end
function gc:fillPolygon(points)
    self.heads[#self.heads+1]={p=points,kind=kind(self.rgb)}
end
function gc:drawString(t,x,y)
    self.texts[#self.texts+1]={text=t,x=x,y=y,w=self:getStringWidth(t),
        h=measured_height(self,t),font=self.font}
end
local function paint()
    gc.lines={};gc.heads={};gc.texts={};gc.beam=nil
    on.paint(gc)
    local text={}
    for _,item in ipairs(gc.texts) do text[#text+1]=item.text end
    return table.concat(text,'\n')
end
local function title_box()
    for _,item in ipairs(gc.texts) do if item.y==29 then return item end end
    error('diagram title missing')
end
local function overlap(a,b)
    return a.x<b.x+b.w and b.x<a.x+a.w and a.y<b.y+b.h and b.y<a.y+a.h
end
local function verify_loads(q,P)
    local title=title_box()
    local beam=assert(gc.beam,'beam missing')
    local ymin=math.huge
    local function point(x,y)
        assert(x>=0 and x<=width and y>=0 and y<=height,'load point outside canvas')
        assert(y>=title.y+title.h+4,'load stroke enters title text box / clearance')
        ymin=math.min(ymin,y)
    end
    local n={q=0,P=0}
    local extents={}
    for _,arrow in ipairs(gc.heads) do
        assert(arrow.kind=='q' or arrow.kind=='P')
        local p=arrow.p
        assert(#p==6 and p[2]==p[4],'one filled triangular head per arrow')
        assert(p[3]-p[1]==2*(p[5]-p[1]),'symmetric head')
        local load=arrow.kind=='q' and q or P
        assert(load~=0)
        if load>0 then
            assert(p[6]>p[2],'positive load points down')
            eq(p[6],beam.y1)
        else
            assert(p[6]<p[2] and p[6]<beam.y1,'negative load points up away from beam')
        end
        local shaft=nil
        for _,line in ipairs(gc.lines) do
            if line.kind==arrow.kind and line.x1==p[5] and line.x2==p[5] and line.y2==p[2] then
                assert(shaft==nil,'one shaft per head')
                shaft=line
            end
        end
        assert(shaft,'shaft must stop at head base')
        assert(shaft.pen=='thin')
        if load<0 then eq(shaft.y1,beam.y1) end
        n[arrow.kind]=n[arrow.kind]+1
        local span=math.abs(shaft.y1-p[6])
        extents[arrow.kind]=span
        for j=1,6,2 do
            point(p[j],p[j+1])
            if arrow.kind=='q' then
                assert(p[j]>=beam.x1+4 and p[j]<=beam.x2-4,'UDL head touches support axis')
            end
        end
    end
    eq(n.q,q==0 and 0 or 9);eq(n.P,P==0 and 0 or 1)
    for _,line in ipairs(gc.lines) do
        if line.kind then
            point(line.x1,line.y1);point(line.x2,line.y2)
            if line.kind=='q' then
                assert(line.x1>=beam.x1+4 and line.x2<=beam.x2-4,'UDL stroke touches support axis')
            end
        end
    end
    if q~=0 and P~=0 then
        assert(extents.P>extents.q,'P must be longer and keep its own color')
    end
    return title.y+title.h,ymin,beam.y1
end
-- 1-2. Both signs, both loads, all four supports and both target windows.
for _,size in ipairs{{318,212},{320,240}} do
    width,height=size[1],size[2]
    for _,native_height in ipairs{14,18} do
        text_height=native_height;gc.getStringHeight=measured_height
        for support=1,4 do
            for _,q in ipairs{-10,10} do
                for _,P in ipairs{-12,12} do
                    on.restore(model(support,1,q,P));paint();verify_loads(q,P)
                end
            end
        end
    end
    text_height=nil;gc.getStringHeight=nil -- documented font+4 fallback
    for _,loads in ipairs{{10,0},{-10,0},{0,12},{0,-12},{0,0}} do
        on.restore(model(1,1,loads[1],loads[2]));paint()
        verify_loads(loads[1],loads[2])
    end
end
-- q sign must follow the productive load, including self-weight.
local weighted=model(1,5,-0.1,0)
weighted.settings.self_weight=true
on.restore(weighted);paint()
assert(on.save().params.q<0 and _BX_TEST_STATE().result.p.q>0)
verify_loads(_BX_TEST_STATE().result.p.q,0)
width,height=318,212;on.restore(model(4,1,10,12));paint()
local bottom,highest,beam_y=verify_loads(10,12)
eq(bottom,43);eq(highest,47);eq(beam_y,73)
print('PASS: signed P / total-q heads, counts, zero loads, self-weight sign, title metrics and support clearance')

-- 3. EI value (auto), caption and units have disjoint measured text boxes.
for _,size in ipairs{{318,212},{320,240}} do
    width,height=size[1],size[2]
    for _,material in ipairs{1,3,5} do
        on.restore(model(1,material,10,0,1));paint()
        local row={}
        for _,text in ipairs(gc.texts) do if text.y==153 then row[#row+1]=text end end
        assert(#row==3,'EI row must contain caption, one value and one unit')
        for i=1,3 do
            assert(row[i].x>=0 and row[i].x+row[i].w<=width)
            for j=i+1,3 do assert(not overlap(row[i],row[j]),'EI text boxes overlap') end
        end
        assert(row[1].text=='EI' and row[3].text=='kN*m2')
        assert(contains(row[2].text,'(auto)')==(material~=1))
        for _,text in ipairs(gc.texts) do assert(text.text~='AUTO') end
    end
end
print('PASS: EI auto suffix stays in the value column, separated from caption and units')

-- 4. The core defaults to the old factor 1 and keeps physical extrema unchanged.
local cantilever=assert(Beam.solve{L=6,q=10,P=0,a=3,EI=10000,support=2})
for _,factor in ipairs{1,2.5} do
    local s=Beam.deflection_check(cantilever,250,factor)
    eq(s.w_abs_max,162);eq(s.x_wmax,6)
    eq(s.lref_factor,factor);eq(s.lref,6*factor)
    eq(s.ratio,(6*factor)*1000/162)
    eq(s.u250,factor==1 and 6.75 or 2.70)
    eq(s.u300,factor==1 and 8.10 or 3.24)
    assert(s.status=='EXCEEDED')
    local summary=Beam.summary(cantilever,250,factor)
    for key,value in pairs(s) do assert(summary[key]==value,key..' lost by summary') end
end
local default=Beam.deflection_check(cantilever,250)
local explicit=Beam.deflection_check(cantilever,250,1)
for key,value in pairs(default) do assert(explicit[key]==value,'default factor must preserve v0.3.2') end
-- UI decides from material and support, including after changing the limit.
for _,size in ipairs{{318,212},{320,240}} do
    width,height=size[1],size[2]
    for material=1,6 do
        for support=1,4 do
            on.restore(model(support,material,10,0,2,4))
            local text=paint()
            local summary=_BX_TEST_STATE().summary
            local concrete=DB.materials[material].kind=='concrete'
            local factor=(support==2 and concrete) and 2.5 or 1
            eq(summary.lref_factor,factor);eq(summary.lref,6*factor)
            assert(contains(text,'Lref=2.5L (EC2/NA)')==(support==2 and concrete))
            assert(contains(text,'CANTILEVER: AGREE LIMIT')==(support==2 and not concrete))
            assert(contains(text,'Lref/|w|=')==(support==2 and concrete))
            for _,mark in ipairs(gc.texts) do
                if contains(mark.text,'Lref=') or contains(mark.text,'AGREE LIMIT') or
                   (support==2 and mark.text=='RC: GROSS EI ONLY') then
                    assert(mark.x>=0 and mark.x+mark.w<=width and mark.y+mark.h<=height)
                    for _,other in ipairs(gc.texts) do
                        if other~=mark then assert(not overlap(mark,other),'cantilever note overlaps results') end
                    end
                end
            end
            on.arrowUp();eq(_BX_TEST_STATE().summary.lref_factor,factor)
            on.arrowDown();eq(_BX_TEST_STATE().summary.lref_factor,factor)
        end
    end
end
print('PASS: factor 1 / 2.5 cantilever witnesses, all UI material/support combinations, limit keys and note bounds')

-- 5. All eight CAS values, recorded from v0.3.2 before modification.
local witnesses={
    {45,0,30,16.874999999999996,3,30,30,10000},
    {-2.8421709430404007e-14,-180.00000000000003,60,161.99999999999997,6,60,0,10000},
    {15,-30,30,3.3750000000000004,2.9999999999999991,30,30,10000},
    {25.3125,-45,37.5,7.0192936011540326,3.4707890075482379,37.5,22.5,10000}
}
local names={'bx_mmax','bx_mmin','bx_vabs','bx_wmax','bx_xwmax','bx_ra','bx_rb','bx_ei'}
for support=1,4 do
    on.restore(model(support,1,10,0,2,4))
    local exported={}
    var={store=function(name,value)
        assert(exported[name]==nil,'duplicate store');exported[name]=value
    end}
    on.enterKey()
    assert(_BX_TEST_STATE().export_message=='CAS: 8 variables stored')
    local n=0;for _ in pairs(exported) do n=n+1 end;assert(n==8)
    for i,name in ipairs(names) do eq(exported[name],witnesses[support][i]) end
end
-- Changing only the reference factor changes no physical or export quantities.
for _,material in ipairs{1,3,5} do
    on.restore(model(2,material,10,0,2,4))
    local sol=_BX_TEST_STATE().result
    local old_units=Beam.summary(sol,250) -- v0.3.2 factor default
    local expected={old_units.mmax,old_units.mmin,old_units.vabs,old_units.w_abs_max,
        old_units.x_wmax,old_units.ra,old_units.rb,old_units.ei}
    local values={};var={store=function(name,value) values[name]=value end}
    on.enterKey()
    for i,name in ipairs(names) do eq(values[name],expected[i]) end
end
print('PASS: P0 witnesses and all eight bx_ values unchanged, including concrete cantilever export')
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
