-- BeamCX v0.4.0, UI (TI-Lua 5.1). Single productive Frame engine.
local SectionDB=DB -- the offline DB from the generated single-file script
local presets={'PIN-PIN','FIX-FREE','FIX-FIX','FIX-PIN'}
local params={L=6,q=10,P=0,a=3,EI=10000,support=1}
local section={material=1,profile=6,b=250,h=450,manualEI=10000}
local settings={self_weight=false,limit=250}
local names={'support','L','q','P','a','EI'}
local units={'','m','kN/m','kN','m','kN*m2'}
local page=0 -- 0 system selector, 1 beam input, 2 diagram, 3 sections
local sel_index=params.support -- temporary focus; params.support is authoritative
local selector_error=nil
local mode=1 -- 1 M, 2 V, 3 w, 4 compact results (inside page 2)
local edit_index,sec_index=1,1
local typing=nil
local cursor=0.5
local result,err=nil,nil
local summary,export_message=nil,nil
local q_sw=nil -- available section self-weight; params.q always remains q_user

local function fmt(x)
    if x==nil then return '--' end
    if math.abs(x)<1e-10 then return '0' end
    return string.format('%.5g',x)
end
local function sec_info() return SectionDB.compute(section) end
local function lref_factor()
    local material=SectionDB.materials[section.material]
    if params.support==2 and material and material.kind=='concrete' then
        -- DIN EN 1992-1-1/NA 7.4.1: cantilever span = 2.5 x cantilever length
        return 2.5
    end
    return 1
end
local function recalc()
    result=nil;summary=nil;export_message=nil
    local info,message=sec_info()
    if not info then result=nil;err=message;page=3;return end
    params.EI=info.EI
    q_sw=info.q_sw
    -- Manual EI / missing catalogue weight never substitutes an invented load.
    if q_sw==nil then settings.self_weight=false end
    local p={}
    for k,v in pairs(params) do p[k]=v end
    p.q=params.q+(settings.self_weight and q_sw or 0)
    result,err=BeamPreset.solve(p,settings.limit,lref_factor())
    if result then summary=result.summary end
    if not result then page=1 end
    return result~=nil
end
recalc()

local function open_selected_system()
    local before={support=params.support,EI=params.EI,result=result,summary=summary,
        err=err,export_message=export_message,q_sw=q_sw,
        self_weight=settings.self_weight,page=page}
    params.support=sel_index
    recalc()
    if result~=nil then
        selector_error=nil;page=1
    else
        local message=err or 'calculation failed'
        params.support=before.support;params.EI=before.EI
        result=before.result;summary=before.summary;err=before.err
        export_message=before.export_message;q_sw=before.q_sw
        settings.self_weight=before.self_weight;page=before.page
        selector_error=message
    end
end

local function export_cas()
    export_message=nil
    if not result or not summary or err then
        export_message='CAS BLOCKED: solve first';return
    end
    if not var or type(var.store)~='function' then
        export_message='CAS ERROR: API unavailable';return
    end
    local values={
        {'bx_mmax',summary.bx_mmax},{'bx_mmin',summary.bx_mmin},
        {'bx_vabs',summary.bx_vabs},{'bx_wmax',summary.bx_wmax},
        {'bx_xwmax',summary.bx_xwmax},{'bx_ra',summary.bx_ra},
        {'bx_rb',summary.bx_rb},{'bx_ei',summary.bx_ei}
    }
    for _,v in ipairs(values) do
        if type(v[2])~='number' or v[2]~=v[2] or math.abs(v[2])==math.huge then
            export_message='CAS ERROR: invalid '..v[1];return
        end
    end
    for _,v in ipairs(values) do
        -- Native var.store returns nil on success, an error message on failure.
        local ok,message=pcall(var.store,v[1],v[2])
        if not ok or message~=nil then
            export_message='CAS ERROR '..v[1]..': '..string.sub(tostring(message),1,18)
            return -- Earlier stores may have succeeded; never report full success.
        end
    end
    export_message='CAS: 8 variables stored'
end

local function color(gc,r,g,b) gc:setColorRGB(r,g,b) end
local function label(gc,t,x,y) gc:drawString(t,x,y,'top') end
local function header(gc,w)
    color(gc,18,44,66);gc:fillRect(0,0,w,22)
    color(gc,255,255,255);gc:setFont('sansserif','b',11)
    label(gc,'BeamCX | EB 2D | v0.4.0',6,4)
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
        label(gc,key=='support' and 'Supports' or (key=='q' and 'q user' or key),14,y+2)
        local text=(i==edit_index and typing~=nil) and (typing..'_') or name_value(i)
        if i==6 and section.material~=1 then
            text=text..' (auto)'
            local text_w=gc.getStringWidth and gc:getStringWidth(text)
            if type(text_w)=='number' and 100+text_w>w-84 then
                gc:setFont('sansserif','r',9)
            end
        end
        label(gc,text,100,y+2)
        gc:setFont('sansserif','r',10)
        if units[i]~='' then label(gc,units[i],w-78,y+2) end
    end
    if err then
        color(gc,255,140,120);label(gc,err,7,h-46)
    elseif result then
        color(gc,128,222,181)
        local lo,hi=result.moments.minimum.value,result.moments.maximum.value
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
    rows[#rows+1]={key='self_weight',caption='Self-weight',
        value=info and info.q_sw and (settings.self_weight and 'ON' or 'OFF') or 'N/A',editable=true}
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
        local y=45+(i-1)*17
        if i==sec_index then
            color(gc,213,232,245);gc:fillRect(6,y-1,w-12,17)
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

local function draw_results(gc,w,h)
    color(gc,215,225,236);gc:setFont('sansserif','r',10)
    local s=result.deflection_check
    local cas=result.summary
    label(gc,'QUICK CHECK | deflection comparison',7,27)
    label(gc,'|w|max='..fmt(cas.bx_wmax)..' mm',7,46)
    label(gc,'x='..fmt(cas.bx_xwmax)..' m',193,46)
    local ratio_label=s.lref_factor==2.5 and 'Lref/|w|=' or 'L/|w|='
    label(gc,ratio_label..(s.span_deflection_ratio and fmt(s.span_deflection_ratio) or 'N/A'),7,64)
    label(gc,'L/'..settings.limit..': '..s.status,163,64)
    label(gc,'L/250: '..fmt(s.utilization.L250*100)..'%',7,82)
    label(gc,'L/300: '..fmt(s.utilization.L300*100)..'%',163,82)
    label(gc,'SW '..(q_sw and (settings.self_weight and 'ON' or 'OFF') or 'N/A')..
        ' | q sw='..(q_sw and fmt(q_sw) or 'N/A')..' kN/m',7,100)
    label(gc,'q total='..fmt(result.parameters.q)..' kN/m',7,118)
    if result.parameters.support==2 then
        gc:setFont('sansserif','r',9);color(gc,255,200,112)
        if s.lref_factor==2.5 then
            label(gc,'Lref=2.5L (EC2/NA)',7,136)
            label(gc,'RC: GROSS EI ONLY',168,136)
        else label(gc,'CANTILEVER: AGREE LIMIT',7,136) end
        gc:setFont('sansserif','r',10)
    elseif sec_info().kind=='concrete' then
        color(gc,255,200,112);label(gc,'RC: GROSS EI ONLY',7,136)
    end
    color(gc,128,222,181);label(gc,'ENTER: EXPORT CAS',7,h-58)
    gc:setFont('sansserif','r',9)
    if export_message then
        color(gc,255,200,112);label(gc,export_message,7,h-39)
    end
    color(gc,171,193,207)
    label(gc,'UP/DOWN L/250 / L/300',7,h-25)
    label(gc,'LEFT/RIGHT plots | TAB sections',7,h-13)
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
-- Compact selector-only supports; the diagram support() above is unchanged.
local function mini_support(gc,x,y,isleft,clamp)
    color(gc,91,195,203)
    if clamp then
        gc:drawLine(x,y-5,x,y+5)
        for j=0,4 do gc:drawLine(x-3,y-3+j*2,x,y-5+j*2) end
    else
        gc:drawLine(x,y,x-5,y+6);gc:drawLine(x,y,x+5,y+6)
        gc:drawLine(x-5,y+6,x+5,y+6)
        if not isleft then gc:drawLine(x-5,y+9,x+5,y+9) end
    end
end
-- Reference UDL moments / (q*L^2), independent of the current model.
local selector_moment_ends={{0,0},{-1/2,0},{-1/12,-1/12},{-1/8,0}}
local function selector_moment(index,xi)
    local ends=selector_moment_ends[index]
    return xi*(1-xi)/2+ends[1]*(1-xi)+ends[2]*xi
end
local function draw_selector(gc,w,h)
    color(gc,215,225,236);gc:setFont('sansserif','r',10)
    label(gc,'SELECT SYSTEM',8,28)
    gc:setFont('sansserif','r',9)
    label(gc,'M (q>0)',w-76,28)
    local margin,gap,top=8,8,46
    local card_w=(w-2*margin-gap)/2
    local card_h=(h-43-top-gap)/2
    gc:setPen('thin','smooth')
    for i=1,4 do
        local x=margin+((i-1)%2)*(card_w+gap)
        local y=top+math.floor((i-1)/2)*(card_h+gap)
        if i==sel_index then color(gc,213,232,245)
        else color(gc,23,46,62) end
        gc:fillRect(x,y,card_w,card_h)
        if i==sel_index then color(gc,18,44,66)
        else color(gc,215,225,236) end
        -- Zones: name [y+2,y+14], schematic [y+15,y+33],
        -- moment [y+35,y+card_h-2]. The last zone follows the window height.
        label(gc,presets[i],x+8,y+2)
        local left,right,ybeam=x+21,x+card_w-21,y+22
        gc:drawLine(left,ybeam,right,ybeam)
        mini_support(gc,left,ybeam,true,i~=1)
        if i~=2 then mini_support(gc,right,ybeam,false,i==3) end
        local moment_top,moment_bottom=y+35,y+card_h-2
        local moment_h=moment_bottom-moment_top
        if moment_h>=14 then
            local mid=(moment_top+moment_bottom)/2
            local data,max_m={},0
            for j=0,32 do
                local m=selector_moment(i,j/32)
                data[j+1]=m;max_m=math.max(max_m,math.abs(m))
            end
            color(gc,115,132,148);gc:drawLine(left,mid,right,mid)
            color(gc,242,177,103) -- same color and thin smooth pen as diagram M
            for j=1,32 do
                local x0=left+(right-left)*(j-1)/32
                local x1=left+(right-left)*j/32
                -- Positive sagging moments are below the reference axis.
                gc:drawLine(x0,mid+data[j]*moment_h/(2*max_m),
                    x1,mid+data[j+1]*moment_h/(2*max_m))
            end
        end
    end
    gc:setFont('sansserif','r',9)
    if selector_error then
        color(gc,255,140,120)
        local message=selector_error
        while #message>0 and gc:getStringWidth(message)>w-16 do
            message=string.sub(message,1,-2)
        end
        label(gc,message,8,h-33)
    end
    color(gc,171,193,207)
    label(gc,'ARROWS select | ENTER open',8,h-15)
end
-- Draw one signed load arrow: shaft stops at the solid triangular head.
-- Pixel-aligned geometry prevents two open V strokes from resembling stacked heads.
local function load_arrow(gc,xc,tail,tip,halfwidth)
    local x=math.floor(xc+0.5)
    local direction=tip>=tail and 1 or -1
    local base=tip-7*direction
    gc:drawLine(x,tail,x,base)
    gc:fillPolygon({x-halfwidth,base,x+halfwidth,base,x,tip})
end
local function diagram(gc,w,h)
    local p=result.parameters
    local left,right=23,w-23
    local info=sec_info()
    color(gc,215,225,236);gc:setFont('sansserif','r',10)
    local title=presets[p.support]..'  L='..fmt(p.L)..'m  '..info.label
    label(gc,title,7,29)
    local title_h=gc.getStringHeight and gc:getStringHeight(title)
    -- Without font metrics, use the 10 pt font plus 4 px for its text box.
    if type(title_h)~='number' then title_h=10+4 end
    local title_bottom=29+title_h
    local ybeam=math.ceil(title_bottom+4+26) -- 4 px clearance, 26 px P arrow
    color(gc,216,228,237);gc:setPen('medium','smooth')
    gc:drawLine(left,ybeam,right,ybeam)
    support(gc,left,ybeam,true,p.support~=1)
    if p.support~=2 then support(gc,right,ybeam,false,p.support==3) end
    gc:setPen('thin','smooth')
    if p.q~=0 then
        color(gc,230,179,83)
        local qleft,qright=left+10,right-10
        local qtop=ybeam-18
        gc:drawLine(qleft,qtop,qright,qtop)
        for i=0,8 do
            local xx=qleft+(qright-qleft)*i/8
            load_arrow(gc,xx,p.q>0 and qtop or ybeam,p.q>0 and ybeam or qtop,3)
        end
    end
    if p.P~=0 then
        local xp=left+(right-left)*p.a/p.L
        color(gc,235,100,105)
        load_arrow(gc,xp,p.P>0 and ybeam-26 or ybeam,p.P>0 and ybeam or ybeam-26,4)
    end
    local namesplot={'M [kNm]','V [kN]','w [mm]'}
    color(gc,225,235,246);gc:setPen('thin','smooth')
    local plot_label_y=math.max(91,ybeam+18)
    label(gc,namesplot[mode]..'   LEFT/RIGHT: change',8,plot_label_y)
    local top,bottom=math.max(111,plot_label_y+title_h+2),h-50
    local mid=(top+bottom)/2
    color(gc,115,132,148);gc:drawLine(left,mid,right,mid)
    local data={}
    local min,max=math.huge,-math.huge
    for i=0,100 do
        local x=p.L*i/100
        local v=BeamPreset.at(result,x)
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
    local v=BeamPreset.at(result,p.L*cursor)
    local ordinate=(mode==1 and v.M) or (mode==2 and v.V) or (v.w*1000)
    color(gc,173,198,210);gc:setPen('thin','dotted')
    gc:drawLine(xx,top,xx,bottom)
    color(gc,244,244,244);gc:setFont('sansserif','r',10)
    label(gc,'x='..fmt(cursor*p.L)..' m  '..namesplot[mode]..'='..fmt(ordinate),8,h-42)
    local r=result.reactions
    label(gc,'RA='..fmt(r.left.Ry)..' RB='..fmt(r.right.Ry)..' kN',8,h-29)
    color(gc,171,193,207);gc:setFont('sansserif','r',9)
    label(gc,'UP/DOWN cursor | ENTER results',8,h-17)
end

on=on or {}
function on.paint(gc)
    local w=platform.window:width()
    local h=platform.window:height()
    color(gc,12,25,36);gc:fillRect(0,0,w,h)
    header(gc,w)
    if page==0 then draw_selector(gc,w,h);return end
    if page==3 then draw_section(gc,w,h)
    elseif page==2 and result then
        if mode==4 then draw_results(gc,w,h) else diagram(gc,w,h) end
    else draw_edit(gc,w,h) end
end
local function redraw() platform.window:invalidate() end
local function apply_edit(key,v)
    if key=='manualEI' or key=='b' or key=='h' then
        local old=section[key]
        section[key]=v
        local info,msg=sec_info()
        if not info then
            section[key]=old;result=nil;summary=nil;export_message=nil;err=msg;return
        end
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
        if not recalc() then params[key]=old;params.a=olda end
    end
end
local function commit()
    if typing==nil then return end
    local v=tonumber(typing)
    -- Invalid text never changed the model; retain its last valid solution.
    if v==nil then export_message=nil;err='invalid number'
    elseif page==1 then apply_edit(names[edit_index],v)
    elseif page==3 then
        local row=active_section_index()[sec_index]
        if row and row.editable and row.key~='material' and row.key~='profile'
           and row.key~='self_weight' then
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
        elseif row.key=='self_weight' then
            local info=sec_info()
            if info and info.q_sw then settings.self_weight=not settings.self_weight end
            recalc()
        end
    end
end
function on.tabKey()
    if page==0 then return end
    commit()
    if result then
        if page==1 then page=2
        elseif page==2 then page=3
        elseif page==3 then page=1 end
    end
    redraw()
end
function on.enterKey()
    if page==0 then open_selected_system();redraw();return end
    if page==1 then
        if edit_index==1 then step_selection(1) else commit() end
    elseif page==2 then
        if mode==4 then export_cas() else mode=4 end
    elseif page==3 then
        local row=active_section_index()[sec_index]
        if row.key=='material' or row.key=='profile' or row.key=='self_weight' then step_selection(1)
        else commit() end
    end
    redraw()
end
function on.charIn(ch)
    if page==0 then return end
    local can=false
    if page==1 then can=edit_index~=1 and (names[edit_index]~='EI' or section.material==1)
    elseif page==3 then
        local row=active_section_index()[sec_index]
        can=row.editable and row.key~='material' and row.key~='profile' and row.key~='self_weight'
    end
    if not can then return end
    if ch=='−' then ch='-' end -- TI handheld minus key can send U+2212
    if string.match(ch,'^[0-9%.%-]$') then
        typing=(typing or '')..ch
        redraw()
    end
end
function on.backspaceKey()
    if page==0 then return end
    if typing and #typing>0 then typing=string.sub(typing,1,-2) end
    redraw()
end
function on.escapeKey()
    if page==0 then return end
    if typing~=nil then typing=nil;err=nil
    else
        if result~=nil then err=nil end
        page=0;sel_index=params.support;selector_error=nil
    end
    redraw()
end
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
    if page==0 then
        if sel_index>2 then sel_index=sel_index-2 end
        redraw();return
    end
    if page==2 and mode==4 then
        settings.limit=settings.limit==250 and 300 or 250
        if result then
            result.deflection_check=BeamPreset.deflection_check(result,settings.limit,lref_factor())
        end
    elseif page==2 then cursor=math.min(1,cursor+0.025)
    else commit();move_field(-1) end
    redraw()
end
function on.arrowDown()
    if page==0 then
        if sel_index<=2 then sel_index=sel_index+2 end
        redraw();return
    end
    if page==2 and mode==4 then
        settings.limit=settings.limit==250 and 300 or 250
        if result then
            result.deflection_check=BeamPreset.deflection_check(result,settings.limit,lref_factor())
        end
    elseif page==2 then cursor=math.max(0,cursor-0.025)
    else commit();move_field(1) end
    redraw()
end
function on.arrowLeft()
    if page==0 then
        if sel_index%2==0 then sel_index=sel_index-1 end
        redraw();return
    end
    if page==2 then mode=(mode+2)%4+1
    else commit();step_selection(-1) end
    redraw()
end
function on.arrowRight()
    if page==0 then
        if sel_index%2==1 then sel_index=sel_index+1 end
        redraw();return
    end
    if page==2 then mode=mode%4+1
    else commit();step_selection(1) end
    redraw()
end
-- Saved inside the .tns document when the user saves it (TI Lua API on.save/restore).
function on.save()
    local p,s={},{}
    for k,v in pairs(params) do p[k]=v end
    for k,v in pairs(section) do s[k]=v end
    return {params=p,section=s,page=page,mode=mode,cursor=cursor,
        settings={self_weight=settings.self_weight,limit=settings.limit}}
end
function on.restore(data)
    if type(data)~='table' then return end
    settings={self_weight=false,limit=250}
    if type(data.settings)=='table' then
        settings.self_weight=data.settings.self_weight==true
        if data.settings.limit==300 then settings.limit=300 end
    end
    typing=nil
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
    if type(data.page)=='number' and data.page>=0 and data.page<=3 then page=data.page end
    if page==0 then sel_index=params.support;selector_error=nil end
    if type(data.mode)=='number' and data.mode>=1 and data.mode<=4 then mode=data.mode end
    if type(data.cursor)=='number' and data.cursor>=0 and data.cursor<=1 then cursor=data.cursor end
end
