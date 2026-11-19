-- Single-span presentation; statically included by build.py in the UI scope.
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
        end
        fitted(gc,text,100,y+2,w-184,10)
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
    local section_label=info.kind=='concrete' and 'RECT '..fmt(section.b)..'x'..fmt(section.h) or info.label
    local title=presets[p.support]..'  L='..fmt(p.L)..'m  '..section_label
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
    label(gc,'UP/DOWN cursor | ENTER results',8,h-15)
end
