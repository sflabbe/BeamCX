-- Existing material/section page; central events retain edit coordination.
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
    local count=params.support==5 and math.max(1,math.floor((h-82)/17)) or #rows
    sec_top=params.support==5 and scroll_top(sec_index,sec_top,count) or 1
    for i=sec_top,math.min(#rows,sec_top+count-1) do
        local row=rows[i]
        local y=45+(i-sec_top)*17
        if i==sec_index then
            color(gc,213,232,245);gc:fillRect(6,y-1,w-12,17)
            color(gc,18,44,66)
        elseif row.editable then color(gc,215,225,236)
        else color(gc,129,164,181) end
        label(gc,row.caption,14,y+2)
        fitted(gc,(i==sec_index and typing~=nil) and (typing..'_') or row.value,122,y+2,w-130,10)
    end
    if err then color(gc,255,140,120);label(gc,err,7,h-31) end
    color(gc,171,193,207);gc:setFont('sansserif','r',9)
    if not err then label(gc,'UP/DOWN field  |  LEFT/RIGHT select',7,h-31) end
    label(gc,'Type dimensions  |  TAB input',7,h-19)
end
