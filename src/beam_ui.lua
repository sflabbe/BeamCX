-- BeamCX v0.2.3, UI (TI-Lua 5.1). Single filled heads for load arrows.
local SectionDB=DB -- the offline DB from the generated single-file script
local presets={'PIN-PIN','FIX-FREE','FIX-FIX','FIX-PIN'}
local params={L=6,q=10,P=0,a=3,EI=10000,support=1}
local section={material=1,profile=6,b=250,h=450,manualEI=10000}
local names={'support','L','q','P','a','EI'}
local units={'','m','kN/m','kN','m','kN*m2'}
local page=1 -- 1 beam input, 2 diagram, 3 sections
local mode=1 -- 1 M, 2 V, 3 w
local edit_index,sec_index=1,1
local typing=nil
local cursor=0.5
local result,err=nil,nil

local function fmt(x)
    if x==nil then return '--' end
    if math.abs(x)<1e-10 then return '0' end
    return string.format('%.5g',x)
end
local function sec_info() return SectionDB.compute(section) end
local function recalc()
    local info,message=sec_info()
    if not info then result=nil;err=message;page=3;return end
    params.EI=info.EI
    result,err=Beam.solve(params)
    if not result then page=1 end
end
recalc()

local function color(gc,r,g,b) gc:setColorRGB(r,g,b) end
local function label(gc,t,x,y) gc:drawString(t,x,y,'top') end
local function header(gc,w)
    color(gc,18,44,66);gc:fillRect(0,0,w,22)
    color(gc,255,255,255);gc:setFont('sansserif','b',11)
    label(gc,'BeamCX | EB 2D | v0.2.3',6,4)
end
local function name_value(index)
    local key=names[index]
    if key=='support' then return presets[params.support] end
    return fmt(params[key])
end
local function draw_edit(gc,w,h)
    color(gc,215,225,236);gc:setFont('sansserif','r',10)
    label(gc,'BEAM INPUT  (downward loads +)',8,29)
    for i=1,#names do
        local y=46+(i-1)*21
        if i==edit_index then
            color(gc,213,232,245);gc:fillRect(6,y-1,w-12,21)
            color(gc,18,44,66)
        else color(gc,215,225,236) end
        local key=names[i]
        label(gc,key=='support' and 'Supports' or key,14,y+2)
        local text=(i==edit_index and typing~=nil) and (typing..'_') or name_value(i)
        label(gc,text,100,y+2)
        if units[i]~='' then label(gc,units[i],w-78,y+2) end
        if i==6 and section.material~=1 then label(gc,'AUTO',w-114,y+2) end
    end
    if err then
        color(gc,255,140,120);label(gc,err,7,h-46)
    elseif result then
        color(gc,128,222,181)
        local lo,_,hi=Beam.moment_extrema(result)
        label(gc,'Mmin='..fmt(lo)..'  Mmax='..fmt(hi)..' kNm',7,h-46)
    end
    color(gc,171,193,207);gc:setFont('sansserif','r',9)
    label(gc,'UP/DOWN field  |  ENTER apply',7,h-31)
    label(gc,'TAB plot; TAB again = sections',7,h-19)
end

local function section_rows()
    local m=SectionDB.materials[section.material]
    local info=sec_info()
    local rows={{key='material',caption='Material',value=m.name,editable=true}}
    if m.kind=='manual' then
        rows[#rows+1]={key='manualEI',caption='EI [kNm2]',value=fmt(section.manualEI),editable=true}
    elseif m.kind=='concrete' then
        rows[#rows+1]={key='shape',caption='Section',value='RECT',editable=false}
        rows[#rows+1]={key='b',caption='b [mm]',value=fmt(section.b),editable=true}
        rows[#rows+1]={key='h',caption='h [mm]',value=fmt(section.h),editable=true}
        rows[#rows+1]={key='E',caption='E [GPa]',value=fmt(m.E/1000),editable=false}
        rows[#rows+1]={key='I',caption='I [cm4]',value=info and fmt(info.I*1e8) or '--',editable=false}
        rows[#rows+1]={key='EI',caption='EI [kNm2]',value=info and fmt(info.EI) or '--',editable=false}
    else
        rows[#rows+1]={key='profile',caption='Profile',value=SectionDB.profiles[section.profile][1],editable=true}
        rows[#rows+1]={key='E',caption='E [GPa]',value=fmt(m.E/1000),editable=false}
        rows[#rows+1]={key='I',caption='Iy [cm4]',value=info and fmt(info.I*1e8) or '--',editable=false}
        rows[#rows+1]={key='EI',caption='EI [kNm2]',value=info and fmt(info.EI) or '--',editable=false}
    end
    return rows
end
local function active_section_index()
    local rows=section_rows()
    if not rows[sec_index] or not rows[sec_index].editable then sec_index=1 end
    return rows
end
local function draw_section(gc,w,h)
    color(gc,215,225,236);gc:setFont('sansserif','r',10)
    label(gc,'OFFLINE MATERIAL / SECTION',8,29)
    local rows=active_section_index()
    for i,row in ipairs(rows) do
        local y=45+(i-1)*20
        if i==sec_index then
            color(gc,213,232,245);gc:fillRect(6,y-1,w-12,20)
            color(gc,18,44,66)
        elseif row.editable then color(gc,215,225,236)
        else color(gc,129,164,181) end
        label(gc,row.caption,14,y+2)
        label(gc,(i==sec_index and typing~=nil) and (typing..'_') or row.value,122,y+2)
    end
    if err then color(gc,255,140,120);label(gc,err,7,h-31) end
    color(gc,171,193,207);gc:setFont('sansserif','r',9)
    if not err then label(gc,'UP/DOWN field  |  LEFT/RIGHT select',7,h-31) end
    label(gc,'Type dimensions  |  TAB input',7,h-19)
end

local function support(gc,x,y,isleft,clamp)
    color(gc,91,195,203)
    if clamp then
        gc:drawLine(x,y-13,x,y+13)
        for j=0,4 do gc:drawLine(x-5,y-11+j*5,x,y-15+j*5) end
    else
        gc:drawLine(x,y,x-9,y+12);gc:drawLine(x,y,x+9,y+12)
        gc:drawLine(x-10,y+12,x+10,y+12)
        if not isleft then gc:drawLine(x-10,y+16,x+10,y+16) end
    end
end
-- Draw one downward load arrow: shaft stops at the solid triangular head.
-- Pixel-aligned geometry prevents two open V strokes from resembling stacked heads.
local function load_arrow(gc,xc,top,tip,halfwidth)
    local x=math.floor(xc+0.5)
    local base=tip-7
    gc:drawLine(x,top,x,base)
    gc:fillPolygon({x-halfwidth,base,x+halfwidth,base,x,tip})
end
local function diagram(gc,w,h)
    local p=result.p
    local left,right=23,w-23
    local ybeam=66
    local info=sec_info()
    color(gc,215,225,236);gc:setFont('sansserif','r',10)
    label(gc,presets[p.support]..'  L='..fmt(p.L)..'m  '..info.label,7,29)
    color(gc,216,228,237);gc:setPen('medium','smooth')
    gc:drawLine(left,ybeam,right,ybeam)
    support(gc,left,ybeam,true,p.support~=1)
    if p.support~=2 then support(gc,right,ybeam,false,p.support==3) end
    gc:setPen('thin','smooth')
    if p.q~=0 then
        color(gc,230,179,83)
        gc:drawLine(left,ybeam-23,right,ybeam-23)
        for i=0,8 do
            local xx=left+(right-left)*i/8
            load_arrow(gc,xx,ybeam-23,ybeam-6,3)
        end
    end
    if p.P~=0 then
        local xp=left+(right-left)*p.a/p.L
        color(gc,235,100,105)
        load_arrow(gc,xp,ybeam-34,ybeam-6,4)
    end
    local namesplot={'M [kNm]','V [kN]','w [mm]'}
    color(gc,225,235,246);gc:setPen('thin','smooth')
    label(gc,namesplot[mode]..'   LEFT/RIGHT: change',8,91)
    local top,bottom=111,h-50
    local mid=(top+bottom)/2
    color(gc,115,132,148);gc:drawLine(left,mid,right,mid)
    local data={}
    local min,max=math.huge,-math.huge
    for i=0,100 do
        local x=p.L*i/100
        local v=Beam.at(result,x)
        local ordinate=(mode==1 and v.M) or (mode==2 and v.V) or (v.w*1000)
        data[i+1]=ordinate
        if ordinate<min then min=ordinate end
        if ordinate>max then max=ordinate end
    end
    local scale=math.max(math.abs(min),math.abs(max),1e-10)
    local amp=(bottom-top)*0.42
    color(gc,mode==1 and 242 or 80,mode==2 and 213 or 177,mode==3 and 235 or 103)
    gc:setPen('thin','smooth')
    -- Bending moment: sagging (+) below reference axis, hogging (-) above.
    -- Keep shear and deflection display conventions unchanged.
    local ordinate_sign=(mode==1) and 1 or -1
    for i=1,100 do
        local x0=left+(right-left)*(i-1)/100
        local x1=left+(right-left)*i/100
        gc:drawLine(x0,mid+ordinate_sign*amp*data[i]/scale,x1,mid+ordinate_sign*amp*data[i+1]/scale)
    end
    local xx=left+(right-left)*cursor
    local v=Beam.at(result,p.L*cursor)
    local ordinate=(mode==1 and v.M) or (mode==2 and v.V) or (v.w*1000)
    color(gc,173,198,210);gc:setPen('thin','dotted')
    gc:drawLine(xx,top,xx,bottom)
    color(gc,244,244,244);gc:setFont('sansserif','r',10)
    label(gc,'x='..fmt(cursor*p.L)..' m  '..namesplot[mode]..'='..fmt(ordinate),8,h-42)
    local r=result.r
    label(gc,'RA='..fmt(r[2])..' RB='..fmt(p.support==2 and 0 or r[#r-1])..' kN',8,h-29)
    color(gc,171,193,207);gc:setFont('sansserif','r',9)
    label(gc,'UP/DOWN cursor | TAB sections',8,h-17)
end

on=on or {}
function on.paint(gc)
    local w=platform.window:width()
    local h=platform.window:height()
    color(gc,12,25,36);gc:fillRect(0,0,w,h)
    header(gc,w)
    if page==3 then draw_section(gc,w,h)
    elseif page==2 and result then diagram(gc,w,h)
    else draw_edit(gc,w,h) end
end
local function redraw() platform.window:invalidate() end
local function apply_edit(key,v)
    if key=='manualEI' or key=='b' or key=='h' then
        local old=section[key]
        section[key]=v
        local info,msg=sec_info()
        if not info then section[key]=old;err=msg;return end
        recalc()
        return
    end
    if key=='EI' and section.material~=1 then
        err='EI from section; use TAB';return
    end
    local old=params[key]
    local olda=params.a
    if key=='EI' then apply_edit('manualEI',v)
    else
        params[key]=v
        -- If there is no point load, its inactive position does not prevent reducing L.
        if key=='L' and params.P==0 and v>0 and params.a>v then params.a=v/2 end
        local sol,msg=Beam.solve(params)
        if sol then result=sol;err=nil
        else params[key]=old;params.a=olda;err=msg end
    end
end
local function commit()
    if typing==nil then return end
    local v=tonumber(typing)
    if v==nil then err='invalid number'
    elseif page==1 then apply_edit(names[edit_index],v)
    elseif page==3 then
        local row=active_section_index()[sec_index]
        if row and row.editable and row.key~='material' and row.key~='profile' then
            apply_edit(row.key,v)
        end
    end
    typing=nil
end
local function step_selection(d)
    if page==1 and edit_index==1 then
        params.support=(params.support-1+d+4)%4+1
        recalc()
    elseif page==3 then
        local row=active_section_index()[sec_index]
        if row.key=='material' then
            section.material=(section.material-1+d+#SectionDB.materials)%#SectionDB.materials+1
            sec_index=1;recalc()
        elseif row.key=='profile' then
            section.profile=(section.profile-1+d+#SectionDB.profiles)%#SectionDB.profiles+1
            recalc()
        end
    end
end
function on.tabKey()
    commit()
    if result then page=page%3+1 end
    redraw()
end
function on.enterKey()
    if page==1 then
        if edit_index==1 then step_selection(1) else commit() end
    elseif page==3 then
        local row=active_section_index()[sec_index]
        if row.key=='material' or row.key=='profile' then step_selection(1)
        else commit() end
    end
    redraw()
end
function on.charIn(ch)
    local can=false
    if page==1 then can=edit_index~=1 and (names[edit_index]~='EI' or section.material==1)
    elseif page==3 then
        local row=active_section_index()[sec_index]
        can=row.editable and row.key~='material' and row.key~='profile'
    end
    if not can then return end
    if ch=='−' then ch='-' end -- TI handheld minus key can send U+2212
    if string.match(ch,'^[0-9%.%-]$') then
        typing=(typing or '')..ch
        redraw()
    end
end
function on.backspaceKey()
    if typing and #typing>0 then typing=string.sub(typing,1,-2) end
    redraw()
end
function on.escapeKey() typing=nil;err=nil;redraw() end
local function move_field(d)
    if page==1 then
        edit_index=math.max(1,math.min(#names,edit_index+d))
    elseif page==3 then
        local rows=section_rows()
        local i=sec_index+d
        while i>=1 and i<=#rows do
            if rows[i].editable then sec_index=i;break end
            i=i+d
        end
    end
end
function on.arrowUp()
    if page==2 then cursor=math.min(1,cursor+0.025)
    else commit();move_field(-1) end
    redraw()
end
function on.arrowDown()
    if page==2 then cursor=math.max(0,cursor-0.025)
    else commit();move_field(1) end
    redraw()
end
function on.arrowLeft()
    if page==2 then mode=(mode+1)%3+1
    else commit();step_selection(-1) end
    redraw()
end
function on.arrowRight()
    if page==2 then mode=mode%3+1
    else commit();step_selection(1) end
    redraw()
end
-- Saved inside the .tns document when the user saves it (TI Lua API on.save/restore).
function on.save()
    local p,s={},{}
    for k,v in pairs(params) do p[k]=v end
    for k,v in pairs(section) do s[k]=v end
    return {params=p,section=s,page=page,mode=mode,cursor=cursor}
end
function on.restore(data)
    if type(data)~='table' then return end
    if type(data.section)=='table' then
        local s=data.section
        local n={material=s.material,profile=s.profile,b=s.b,h=s.h,manualEI=s.manualEI}
        if type(n.profile)=='number' and n.profile==math.floor(n.profile)
           and n.profile>=1 and n.profile<=#SectionDB.profiles
           and SectionDB.compute(n) then section=n end
    end
    if type(data.params)=='table' then
        local p=data.params
        if type(p.L)=='number' and type(p.q)=='number' and type(p.P)=='number'
           and type(p.a)=='number' and type(p.support)=='number' then
            params.L=p.L;params.q=p.q;params.P=p.P;params.a=p.a;params.support=p.support
        end
    end
    recalc()
    if type(data.page)=='number' and data.page>=1 and data.page<=3 then page=data.page end
    if type(data.mode)=='number' and data.mode>=1 and data.mode<=3 then mode=data.mode end
    if type(data.cursor)=='number' and data.cursor>=0 and data.cursor<=1 then cursor=data.cursor end
end
