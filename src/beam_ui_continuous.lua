-- Continuous-beam presentation; shares main UI locals through static inclusion.
local function draw_continuous_edit(gc,w,h)
    color(gc,215,225,236);gc:setFont('sansserif','r',10)
    label(gc,'CONTINUOUS | Input',8,28)
    local rows=continuous_rows()
    local count=math.max(1,math.floor((h-94)/18))
    edit_top=scroll_top(edit_index,edit_top,count)
    for i=edit_top,math.min(#rows,edit_top+count-1) do
        local row=rows[i]
        local y=46+(i-edit_top)*18
        if i==edit_index then
            color(gc,213,232,245);gc:fillRect(6,y-1,w-12,18)
            color(gc,18,44,66)
        else color(gc,215,225,236) end
        label(gc,row.caption,12,y)
        local value=type(row.value)=='number' and fmt(row.value) or row.value
        fitted(gc,i==edit_index and typing~=nil and typing..'_' or value,160,y,w-174,10)
    end
    gc:setFont('sansserif','r',9);color(gc,255,200,112)
    fitted(gc,err or (stale and 'Outdated | TAB: calculate' or 'Result saved'),7,h-45,w-14)
    color(gc,171,193,207)
    label(gc,'UP/DOWN field | LEFT/RIGHT spans, ends',7,h-30)
    label(gc,'ENTER apply | TAB results',7,h-16)
end

local function draw_continuous_table(gc,w,h)
    color(gc,215,225,236);gc:setFont('sansserif','r',9)
    label(gc,'CONTINUOUS | '..(table_page==1 and 'Spans' or 'Supports')..' | L/'..settings.limit,7,27)
    gc:setFont('sansserif','r',8)
    if table_page==1 then
        for _,c in ipairs{{'#',7},{'L [m]',27},{'M+ kNm',61},{'w mm',119},{'L/|w|',185},{'Status',253}} do
            label(gc,c[1],c[2],44)
        end
        for i,s in ipairs(result.spans) do
            local y=59+(i-1)*13
            local d=s.deflection
            label(gc,tostring(i),7,y);label(gc,fmt(s.length),27,y)
            label(gc,s.Mplus and fmt(s.Mplus.value) or '—',61,y)
            label(gc,(d.governing.value<0 and '↑' or '↓')..fmt(d.governing.absolute*1000),119,y)
            label(gc,d.ratio and fmt(d.ratio) or 'N/A',185,y)
            label(gc,d.status,253,y)
        end
    else
        for _,c in ipairs{{'#',7},{'Mmin',32},{'Mmax>0',104},{'Rmax',176},{'Rmin',248}} do
            label(gc,c[1],c[2],44)
        end
        for i,s in ipairs(result.supports) do
            local y=59+(i-1)*13
            label(gc,tostring(i),7,y);label(gc,fmt(s.Mmin.value),32,y)
            label(gc,s.Mmax.value>0 and fmt(s.Mmax.value) or '—',104,y)
            label(gc,fmt(s.Rmax.value),176,y);label(gc,fmt(s.Rmin.value),248,y)
        end
    end
    label(gc,'|V|max='..fmt(result.shear.value)..' kN | M kNm, R kN',7,h-69)
    local p=result.parameters
    label(gc,'γG,sup='..fmt(p.gG_sup)..'  γG,inf='..fmt(p.gG_inf)..'  γQ='..fmt(p.gQ),7,h-56)
    label(gc,'γ: OPEN (EN 1990 A1 + NA)',7,h-43)
    color(gc,128,222,181)
    fitted(gc,export_message or 'ENTER: EXPORT CAS bc_*',7,h-29,w-14)
    color(gc,171,193,207)
    label(gc,'UP/DOWN table | LEFT/RIGHT mode | TAB section',7,h-15)
end

local function continuous_diagram(gc,w,h)
    color(gc,215,225,236);gc:setFont('sansserif','r',9)
    local titles={'M envelope [kNm]','V envelope [kN]','w characteristic [mm]'}
    label(gc,'CONTINUOUS | '..titles[mode],7,28)
    label(gc,mode==3 and 'Orange: odd | Blue: even' or 'Orange: max | Blue: min',7,43)
    local left,right=23,w-23
    local total=result.supports[#result.supports].position
    local function px(x) return left+(right-left)*x/total end
    gc:setPen('thin','smooth');gc:drawLine(left,66,right,66)
    for i,s in ipairs(result.supports) do
        local clamp=(i==1 and continuous.left=='FIX') or (i==#result.supports and continuous.right=='FIX')
        mini_support(gc,px(s.position),66,i==1,clamp)
    end
    local top,bottom=85,h-82
    local mid=(top+bottom)/2
    local keys=mode==1 and {'Mmax','Mmin'} or (mode==2 and {'Vmax','Vmin'} or {'wodd','weven'})
    local scale=1e-10
    for _,v in ipairs(samples) do
        for _,key in ipairs(keys) do scale=math.max(scale,math.abs(v[key])) end
    end
    color(gc,115,132,148);gc:drawLine(left,mid,right,mid)
    -- M and characteristic w are positive downward; V retains its usual sign.
    local sign=mode==2 and -1 or 1
    for k,key in ipairs(keys) do
        if k==1 then color(gc,242,177,103) else color(gc,80,213,235) end
        for j=1,#samples-1 do
            local a,b=samples[j],samples[j+1]
            gc:drawLine(px(a.x),mid+sign*(bottom-top)*.45*a[key]/scale,
                px(b.x),mid+sign*(bottom-top)*.45*b[key]/scale)
        end
    end
    local v=cursor_value
    color(gc,173,198,210);gc:setPen('thin','dotted')
    gc:drawLine(px(v.x),top,px(v.x),bottom)
    color(gc,244,244,244);gc:setFont('sansserif','r',8)
    label(gc,'x='..fmt(v.x)..' m',7,h-76)
    if mode==3 then
        label(gc,'w odd='..fmt(v.wodd)..' | even='..fmt(v.weven)..' mm',7,h-61)
    else
        label(gc,'Mmax='..fmt(v.Mmax)..' | Mmin='..fmt(v.Mmin)..' kNm',7,h-61)
        if v.left then
            label(gc,'V left max/min: '..fmt(v.left.Vmax)..' / '..fmt(v.left.Vmin)..' kN',7,h-47)
            label(gc,'V right max/min: '..fmt(v.right.Vmax)..' / '..fmt(v.right.Vmin)..' kN',7,h-33)
        else label(gc,'Vmax='..fmt(v.Vmax)..' | Vmin='..fmt(v.Vmin)..' kN',7,h-47) end
    end
    color(gc,171,193,207)
    label(gc,'UP/DOWN cursor | LEFT/RIGHT mode | ENTER table',7,h-15)
end
