-- Existing material/section page; central events retain edit coordination.
local function section_rows()
    local selected=active_section()
    local m=SectionDB.materials[selected.material]
    local info=sec_info()
    local rows={{key='material',caption='Material',value=m.name,editable=true}}
    if params.support==6 then
        table.insert(rows,1,{key='group',caption='Group',value=portal_section_group=='columns' and 'Columns' or 'Beam',editable=true})
    end
    if m.kind=='manual' then
        rows[#rows+1]={key='manualEI',caption='EI [kNm2]',value=fmt(selected.manualEI),editable=true}
    elseif m.kind=='concrete' then
        rows[#rows+1]={key='shape',caption='Section',value='RECT',editable=false}
        rows[#rows+1]={key='b',caption='b [mm]',value=fmt(selected.b),editable=true}
        rows[#rows+1]={key='h',caption='h [mm]',value=fmt(selected.h),editable=true}
        rows[#rows+1]={key='E',caption='E [GPa]',value=info and fmt(info.E/1000) or '--',editable=false}
        rows[#rows+1]={key='I',caption='I [cm4]',value=info and fmt(info.I*1e8) or '--',editable=false}
        rows[#rows+1]={key='EI',caption='EI [kNm2]',value=info and fmt(info.EI) or '--',editable=false}
    else
        rows[#rows+1]={key='profile',caption='Profile',value=SectionDB.profiles[selected.profile][1],editable=true}
        rows[#rows+1]={key='E',caption='E [GPa]',value=info and fmt(info.E/1000) or '--',editable=false}
        rows[#rows+1]={key='I',caption='Iy [cm4]',value=info and fmt(info.I*1e8) or '--',editable=false}
        rows[#rows+1]={key='EI',caption='EI [kNm2]',value=info and fmt(info.EI) or '--',editable=false}
    end
    local excluded=params.support==6 and portal_section_group=='columns'
    local weight=params.support==6 and portal_beam_self_weight or (params.support~=6 and settings.self_weight)
    rows[#rows+1]={key='self_weight',caption='Self-weight',value=excluded and 'Excluded (axial)' or
        (info and info.q_sw and (weight and 'ON' or 'OFF') or 'N/A'),editable=not excluded}
    if params.support==5 then
        rows[#rows+1]={key='limit',caption='Defl. limit',value='L/'..settings.limit,editable=true}
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
    local spacing,size=params.support==6 and 14 or 17,params.support==6 and 9 or 10
    local count=params.support>=5 and math.max(1,math.floor((h-82)/spacing)) or #rows
    sec_top=params.support>=5 and scroll_top(sec_index,sec_top,count) or 1
    if params.support==6 then gc:setFont('sansserif','r',size) end
    for i=sec_top,math.min(#rows,sec_top+count-1) do
        local row=rows[i]
        local y=45+(i-sec_top)*spacing
        if i==sec_index then
            color(gc,213,232,245);gc:fillRect(6,y-1,w-12,spacing)
            color(gc,18,44,66)
        elseif row.editable then color(gc,215,225,236)
        else color(gc,129,164,181) end
        label(gc,row.caption,14,y+2)
        fitted(gc,(i==sec_index and typing~=nil) and (typing..'_') or row.value,122,y+2,w-130,size)
    end
    if err then color(gc,255,140,120);label(gc,err,7,h-31) end
    color(gc,171,193,207);gc:setFont('sansserif','r',9)
    if not err then label(gc,'UP/DOWN field  |  LEFT/RIGHT select',7,h-31) end
    label(gc,'Type dimensions  |  TAB input',7,h-19)
end
