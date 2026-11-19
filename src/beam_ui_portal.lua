-- Portal presentation; uses the existing timer-built member and table caches.
local function draw_portal_edit(gc,w,h)
    color(gc,215,225,236);gc:setFont('sansserif','r',10)
    label(gc,'PORTAL | Input',8,28)
    local count=math.max(1,math.floor((h-94)/18))
    edit_top=scroll_top(edit_index,edit_top,count)
    for i=edit_top,math.min(10,edit_top+count-1) do
        local field=portal_fields[i];local y=46+(i-edit_top)*18
        if i==edit_index then color(gc,213,232,245);gc:fillRect(6,y-1,w-12,18);color(gc,18,44,66)
        else color(gc,215,225,236) end
        fitted(gc,field[2],12,y,170,10)
        local value=portal[field[1]]
        if type(value)=='number' then value=fmt(value) end
        fitted(gc,i==edit_index and typing~=nil and typing..'_' or value,186,y,w-198,10)
    end
    color(gc,255,200,112);gc:setFont('sansserif','r',9)
    fitted(gc,err or (stale and 'Outdated | TAB: calculate' or 'Result saved'),7,h-45,w-14)
    color(gc,171,193,207)
    label(gc,'UP/DOWN field | LEFT/RIGHT base',7,h-30)
    label(gc,'ENTER apply | TAB results | ESC systems',7,h-16)
end

local function portal_arrow(gc,x0,y0,x1,y1)
    local dx,dy=x1-x0,y1-y0
    local L=math.sqrt(dx*dx+dy*dy);dx=dx/L;dy=dy/L
    local bx,by=x1-5*dx,y1-5*dy
    gc:drawLine(x0,y0,bx,by)
    gc:fillPolygon({bx-3*dy,by+3*dx,bx+3*dy,by-3*dx,x1,y1})
end

local function draw_portal_table(gc,w,h)
    color(gc,215,225,236);gc:setFont('sansserif','r',9)
    label(gc,'PORTAL | Results',7,28)
    local count=math.max(1,math.floor((h-100)/15))
    table_page=math.max(1,math.min(#samples.table-count+1,table_page))
    for i=table_page,math.min(#samples.table,table_page+count-1) do
        local row=samples.table[i];local y=46+(i-table_page)*15
        fitted(gc,row[1],8,y,166,9);fitted(gc,row[2],178,y,w-186,9)
    end
    color(gc,255,200,112);label(gc,'limits: OPEN (project / NA)',7,h-47)
    color(gc,128,222,181);fitted(gc,export_message or 'ENTER: EXPORT CAS bp_* (14)',7,h-31,w-14,9)
    color(gc,171,193,207);gc:setFont('sansserif','r',8)
    label(gc,'UP/DOWN scroll | LEFT/RIGHT mode | TAB input',7,h-15)
end

local function portal_diagram(gc,w,h)
    local titles={'M [kNm] | + tension side','V [kN] | local +y side','N [kN] | + tension','Deformed | absolute'}
    color(gc,215,225,236);gc:setFont('sansserif','r',9)
    fitted(gc,'PORTAL '..portal.base..' | '..titles[mode],7,28,w-14,9)
    fitted(gc,'q='..fmt(portal.q)..' P='..fmt(portal.P)..' H='..fmt(portal.H)..' w='..fmt(portal.w),7,43,w-14,8)
    local scale=math.min((w-100)/portal.l,(h-164)/portal.h)
    local left=(w-portal.l*scale)/2
    local bottom=h-82
    local function px(x) return left+x*scale end
    local function py(y) return bottom-y*scale end
    gc:setPen('thin','smooth')
    -- Original geometry, including both bottom->top columns.
    for i,data in ipairs(samples.members) do
        if i==portal_member then color(gc,151,184,203) else color(gc,79,105,125) end
        gc:drawLine(px(data[1].x),py(data[1].y),px(data[#data].x),py(data[#data].y))
    end
    color(gc,91,195,203)
    for _,x in ipairs{0,portal.l} do
        local xx,yy=px(x),py(0)
        if portal.base=='FIX' then
            gc:drawLine(xx-8,yy,xx+8,yy)
            for k=-1,1 do gc:drawLine(xx+k*5,yy,xx+k*5-3,yy+5) end
        else
            gc:drawLine(xx,yy,xx-7,yy+9);gc:drawLine(xx,yy,xx+7,yy+9);gc:drawLine(xx-7,yy+9,xx+7,yy+9)
        end
    end
    color(gc,246,207,97)
    local function vertical(load,x,length)
        if load~=0 then
            local a,b=py(portal.h)-length,py(portal.h)
            if load<0 then a,b=b,a end
            portal_arrow(gc,px(x),a,px(x),b)
        end
    end
    if portal.q~=0 then for k=1,3 do vertical(portal.q,portal.l*k/4,12) end end
    vertical(portal.P,portal.a,22)
    local function horizontal(load,y,length)
        if load~=0 then
            local a,b=px(0)-length,px(0)
            if load<0 then a,b=b,a end
            portal_arrow(gc,a,py(y),b,py(y))
        end
    end
    horizontal(portal.H,portal.h,24)
    if portal.w~=0 then for k=1,3 do horizontal(portal.w,portal.h*k/4,17) end end
    local key=({'M','V','N'})[mode]
    for i,data in ipairs(samples.members) do
        local function plot(v)
            if mode==4 then return px(v.x+samples.magnification*v.dx),py(v.y+samples.magnification*v.dy) end
            local amplitude=samples.scales[key]>0 and 18*v[key]/samples.scales[key] or 0
            -- M uses -local y (tension). V/N use +local y, with an explicit legend.
            local sign=mode==1 and -1 or 1
            if i==2 then return px(v.x),py(v.y)-sign*amplitude end
            return px(v.x)-sign*amplitude,py(v.y)
        end
        if mode==3 and data[1].N<0 then color(gc,80,213,235) else color(gc,242,177,103) end
        for j=1,#data-1 do
            local a,b=data[j],data[j+1]
            local ax,ay=plot(a);local bx,by=plot(b)
            -- Equal-s left/right entries draw the exact V jump, never a diagonal.
            gc:drawLine(ax,ay,bx,by)
        end
        if mode~=4 then
            for _,j in ipairs{1,#data} do
                local v=data[j];local x,y=plot(v);gc:drawLine(px(v.x),py(v.y),x,y)
            end
        end
    end
    if cursor_value then
        local x,y=portal_member==2 and portal_s or (portal_member==1 and 0 or portal.l),portal_member==2 and portal.h or portal_s
        color(gc,255,255,255);gc:fillRect(px(x)-2,py(y)-2,4,4)
        gc:setFont('sansserif','r',9)
        local side=portal_member==2 and portal.P~=0 and portal_s==portal.a and (' '..portal_side) or ''
        label(gc,'MEMBER '..portal_member..' | '..(portal_member==2 and 'BEAM' or 'COLUMN')..' | s='..fmt(portal_s)..side,7,h-64)
        fitted(gc,'N='..fmt(cursor_value.N)..' V='..fmt(cursor_value.V)..' kN  M='..fmt(cursor_value.M)..' kNm',7,h-48,w-14,9)
    end
    color(gc,171,193,207);gc:setFont('sansserif','r',8)
    fitted(gc,mode==4 and ('Magnification x'..fmt(samples.magnification)..' | beam w_rel in table') or '1/2/3 member | UP/DOWN s | ENTER table',7,h-31,w-14,8)
    label(gc,'LEFT/RIGHT mode | TAB input | ESC systems',7,h-15)
end
