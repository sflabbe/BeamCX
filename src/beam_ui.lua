-- BeamCX v0.6.0, UI (TI-Lua 5.1). Single productive Frame engine.
local SectionDB=DB -- the offline DB from the generated single-file script
local presets={'PIN-PIN','FIX-FREE','FIX-FIX','FIX-PIN','CONTINUOUS','PORTAL'}
local params={L=6,q=10,P=0,a=3,EI=10000,support=1}
local section={material=1,profile=6,b=250,h=450,manualEI=10000}
local settings={self_weight=false,limit=250}
local names={'support','L','q','P','a','EI'}
local units={'','m','kN/m','kN','m','kN*m2'}
local page=0 -- 0 system selector, 1 beam input, 2 diagram, 3 sections
local sel_index=params.support -- temporary focus; params.support is authoritative
local selector_error=nil
local restore_notice=nil
local mode=1 -- 1 M, 2 V, 3 w, 4 compact results (inside page 2)
local edit_index,sec_index=1,1
local typing=nil
local cursor=0.5
local result,err=nil,nil
local summary,export_message=nil,nil
local q_sw=nil -- available section self-weight; params.q always remains q_user

local continuous={spans={6,6,6},left='PIN',right='PIN',g=10,q=5,
    gG_sup=1.35,gG_inf=1,gQ=1.5}
local portal={h=4,l=6,base='FIX',EIc=10000,EIb=15000,q=10,P=0,a=3,H=0,w=0}
local portal_fields={{'base','Base'},{'h','Height h [m]'},{'l','Width l [m]'},
    {'EIc','EI columns [kNm2]'},{'EIb','EI beam [kNm2]'},{'q','Beam q [kN/m]'},
    {'P','Beam P [kN]'},{'a','Position a [m]'},{'H','Nodal H [kN]'},{'w','Wind w [kN/m]'}}
local portal_member,portal_s,portal_side=2,3,'left'
local portal_confirmed=nil
local samples,cursor_value,characteristic=nil,nil,nil
local stale,calculating=true,false
local table_page,edit_top,sec_top=1,1,1
local selection_before=nil -- retained until the first deferred solve succeeds
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function copy(t)
    local out={}
    for k,v in pairs(t) do out[k]=type(v)=='table' and copy(v) or v end
    return out
end
local default_params,default_section,default_continuous=copy(params),copy(section),copy(continuous)
local default_portal=copy(portal)
local function continuous_parameters()
    local p=copy(continuous)
    p.EI=params.EI;p.limit=settings.limit
    p.g=p.g+(settings.self_weight and q_sw or 0)
    return p
end
local function continuous_rows()
    local rows={{key='n',caption='Spans',value=#continuous.spans}}
    for i,L in ipairs(continuous.spans) do
        rows[#rows+1]={key=i,caption='L'..i..' [m]',value=L}
    end
    for _,r in ipairs{{'left','Left end'},{'right','Right end'},
        {'g','g [kN/m]'},{'q','q [kN/m]'}, {'gG_sup','γG,sup'},
        {'gG_inf','γG,inf'},{'gQ','γQ'}} do
        rows[#rows+1]={key=r[1],caption=r[2],value=continuous[r[1]]}
    end
    return rows
end
local function dirty()
    stale=true;calculating=false;samples=nil;cursor_value=nil;characteristic=nil
    result=nil;summary=nil;export_message=nil;err=nil
end
local function dirty_portal()
    stale=true;calculating=false;samples=nil;cursor_value=nil;export_message=nil;err=nil
end

local function fmt(x)
    if x==nil then return '--' end
    if x==0 then return '0.00' end -- also normalize IEEE negative zero
    if math.abs(x)<0.005 or math.abs(x)>=1e7 then return string.format('%.2e',x) end
    return string.format('%.2f',x)
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
    if params.support==6 then dirty_portal();return true end
    if params.support==5 then
        local info,message=sec_info()
        if not info then err=message;return false end
        params.EI=info.EI;q_sw=info.q_sw
        if q_sw==nil then settings.self_weight=false end
        dirty();return true
    end
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

-- Only the timer invokes this calculation and creates the drawing cache.
local function deflections_at(x)
    local i=1
    while i<#result.spans and x>result.supports[i+1].position do i=i+1 end
    local local_x=x-result.spans[i].offset
    return -Frame.at(characteristic[1],i,local_x).w*1000,
        -Frame.at(characteristic[2],i,local_x).w*1000
end
local function cache_cursor()
    if not result or not samples then return end
    if params.support==6 then
        local L=portal_member==2 and portal.l or portal.h
        portal_s=math.max(0,math.min(L,portal_s))
        if portal_s==0 then portal_side='right' elseif portal_s==L then portal_side='left' end
        cursor_value=PortalPreset.at(result,portal_member,portal_s,portal_side)
        return
    end
    local total=result.supports[#result.supports].position
    local x=cursor*total
    for _,s in ipairs(result.supports) do
        if math.abs(s.position-x)<1e-9*math.max(1,total) then x=s.position;break end
    end
    cursor_value=result.envelope_at(x) -- exactly one envelope query per movement
    cursor_value.x=x
    cursor_value.wodd,cursor_value.weven=deflections_at(x)
    for i,s in ipairs(result.supports) do
        if s.position==x and i>1 and i<#result.supports then
            cursor_value.left=samples.supports[i].left
            cursor_value.right=samples.supports[i].right
        end
    end
end
local function cache_portal()
    samples={members={},scales={M=0,V=0,N=0},vabs={},table={}}
    local max_displacement=0
    for member=1,3 do
        local L=member==2 and portal.l or portal.h
        local positions={0,L}
        for j=1,19 do positions[#positions+1]=L*j/20 end
        if member==2 and portal.P~=0 and portal.a>0 and portal.a<L then positions[#positions+1]=portal.a end
        table.sort(positions)
        local data={};samples.members[member]=data
        local last=nil
        for _,s in ipairs(positions) do
            if s~=last then
                local sides={s==0 and 'right' or 'left'}
                if member==2 and portal.P~=0 and s==portal.a and s>0 and s<L then sides={'left','right'} end
                for _,side in ipairs(sides) do
                    local v=PortalPreset.at(result,member,s,side)
                    v.s=s;v.side=side
                    -- Local x bottom->top on BOTH columns; beam left->right.
                    if member==2 then v.x=s;v.y=portal.h;v.dx=v.u;v.dy=v.w
                    else v.x=member==1 and 0 or portal.l;v.y=s;v.dx=-v.w;v.dy=v.u end
                    max_displacement=math.max(max_displacement,math.abs(v.dx),math.abs(v.dy))
                    data[#data+1]=v
                end
            end
            last=s
        end
        -- V is linear between the endpoint/P cuts in this preset. These
        -- exact cuts determine |V|max, independently of screen sampling.
        local cuts={{0,'right'},{L,'left'}}
        if member==2 and portal.P~=0 and portal.a>0 and portal.a<L then
            cuts[#cuts+1]={portal.a,'left'};cuts[#cuts+1]={portal.a,'right'}
        end
        local vabs=0
        for _,cut in ipairs(cuts) do vabs=math.max(vabs,math.abs(PortalPreset.at(result,member,cut[1],cut[2]).V)) end
        samples.vabs[member]=vabs;samples.scales.V=math.max(samples.scales.V,vabs)
        local m=result.members[member]
        samples.scales.M=math.max(samples.scales.M,math.abs(m.moments.minimum.value),math.abs(m.moments.maximum.value))
        samples.scales.N=math.max(samples.scales.N,m.axial.absolute)
    end
    samples.magnification=max_displacement>0 and .12*math.max(portal.h,portal.l)/max_displacement or 1
    local function row(caption,value) samples.table[#samples.table+1]={caption,value} end
    for _,side in ipairs{'left','right'} do
        local r=result.reactions[side]
        row(side..' base H [kN]',fmt(r.H));row(side..' base V [kN]',fmt(r.V))
        row(side..' base M [kNm]',r.M and fmt(r.M) or '—')
    end
    for i,m in ipairs(result.members) do
        row('Member '..i..' N [kN]',fmt(m.axial.value))
        row('M'..i..' min [kNm]',fmt(m.moments.minimum.value)..' @ '..fmt(m.moments.minimum.position)..' m')
        row('M'..i..' max [kNm]',fmt(m.moments.maximum.value)..' @ '..fmt(m.moments.maximum.position)..' m')
        row('Member '..i..' |V|max [kN]',fmt(samples.vabs[i]))
    end
    for _,side in ipairs{'left','right'} do
        row(side..' corner col [kNm]',fmt(result.corners[side].column))
        row(side..' corner beam [kNm]',fmt(result.corners[side].beam))
    end
    for _,side in ipairs{'left','right'} do
        local drift=result.drift[side]
        row(side..' drift [mm]',fmt(drift*1000))
        row(side..' h/|drift|',drift~=0 and fmt(portal.h/math.abs(drift)) or '—')
    end
    row('Beam w_rel [mm]',fmt(result.deflection.value*1000))
    row('Beam l/|w_rel|',result.deflection.absolute>0 and fmt(portal.l/result.deflection.absolute) or '—')
    row('w_rel position [m]',fmt(result.deflection.position))
    cache_cursor()
end
local function cache_samples()
    characteristic={}
    for parity=1,2 do
        local factors={1}
        for i=1,#continuous.spans do factors[i+1]=i%2==parity%2 and 1 or 0 end
        characteristic[parity]=assert(Frame.combine(result.bases,factors))
    end
    samples={supports={}}
    for i,span in ipairs(result.spans) do
        for j=0,20 do
            local x=span.offset+span.length*j/20
            local side=j==20 and 'left' or 'right'
            local v=result.envelope_at(x,side)
            v.x=x;v.wodd,v.weven=deflections_at(x)
            samples[#samples+1]=v
            if j==0 then
                samples.supports[i]=samples.supports[i] or {}
                samples.supports[i].right=v
            elseif j==20 then samples.supports[i+1]={left=v} end
        end
    end
    cache_cursor()
end
local function rollback_selection(message)
    if selection_before then
        local b=selection_before
        params=b.params;section=b.section;settings=b.settings
        result=b.result;summary=b.summary;err=b.err;export_message=b.export_message
        q_sw=b.q_sw;samples=b.samples;cursor_value=b.cursor_value;characteristic=b.characteristic
        stale=b.stale;continuous=b.continuous;portal=b.portal
        portal_confirmed=b.portal_confirmed
        mode=b.mode;table_page=b.table_page;edit_index=b.edit_index;edit_top=b.edit_top
        portal_member=b.portal_member;portal_s=b.portal_s;portal_side=b.portal_side
        page=0;selector_error=message;selection_before=nil
    else err=message;page=1 end
end
local function open_selected_system()
    local before={params=copy(params),section=copy(section),settings=copy(settings),
        result=result,summary=summary,err=err,export_message=export_message,q_sw=q_sw,
        samples=samples,cursor_value=cursor_value,characteristic=characteristic,
        stale=stale,continuous=copy(continuous),portal=copy(portal),portal_confirmed=portal_confirmed,
        mode=mode,table_page=table_page,edit_index=edit_index,edit_top=edit_top,
        portal_member=portal_member,portal_s=portal_s,portal_side=portal_side}
    params.support=sel_index
    if sel_index~=6 then mode=math.min(mode,4) end
    if sel_index==6 then
        selection_before=before.params.support~=6 and before or nil
        selector_error=nil;page=1;edit_index=1;edit_top=1;mode=1;table_page=1
        if before.params.support~=6 then dirty_portal() end
    elseif sel_index==5 then
        selection_before=before
        if recalc() then selector_error=nil;page=1;edit_index=1;edit_top=1
        else rollback_selection(err) end
    else
        recalc()
        if result~=nil then selector_error=nil;page=1;selection_before=nil;edit_index=1
        else
            selection_before=before
            rollback_selection(err or 'calculation failed')
        end
    end
end
local function show_results()
    page=2
    if params.support==6 and not stale then err=nil end
    if (params.support==5 or params.support==6) and stale then
        calculating=true
        platform.window:invalidate()
        timer.start(0.05)
    end
end

local function export_cas()
    export_message=nil
    if not result or not summary or err or (params.support==6 and stale) then
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
    if params.support==5 then
        values={{'bc_mmax',summary.moment_max},{'bc_mmin',summary.moment_min},
            {'bc_vabs',summary.shear_absolute_max},{'bc_rmax',summary.reaction_max},
            {'bc_wmax',summary.deflection_absolute_max*1000},
            {'bc_xwmax',summary.deflection_position},{'bc_ei',summary.rigidity},
            {'bc_n',summary.span_count}}
    elseif params.support==6 then
        local r=result.reactions
        local mmax,mmin=-math.huge,math.huge
        for _,m in ipairs(result.members) do
            mmax=math.max(mmax,m.moments.maximum.value);mmin=math.min(mmin,m.moments.minimum.value)
        end
        values={{'bp_hl',r.left.H},{'bp_vl',r.left.V},{'bp_ml',r.left.M or 0},
            {'bp_hr',r.right.H},{'bp_vr',r.right.V},{'bp_mr',r.right.M or 0},
            {'bp_mmax',mmax},{'bp_mmin',mmin},{'bp_nabs',samples.scales.N},{'bp_vabs',samples.scales.V},
            {'bp_dxl',result.drift.left*1000},{'bp_dxr',result.drift.right*1000},
            {'bp_wrel',result.deflection.value*1000},{'bp_xwrel',result.deflection.position}}
    end
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
    export_message='CAS: '..#values..' variables stored'
end

local function color(gc,r,g,b) gc:setColorRGB(r,g,b) end
local function label(gc,t,x,y) gc:drawString(t,x,y,'top') end
local function fitted(gc,t,x,y,width,size)
    size=size or 9
    gc:setFont('sansserif','r',size)
    local fitted_size=size
    local text_width=gc.getStringWidth and gc:getStringWidth(t)
    while type(text_width)=='number' and text_width>width and fitted_size>6 do
        fitted_size=fitted_size-1
        gc:setFont('sansserif','r',fitted_size)
        text_width=gc:getStringWidth(t)
    end
    label(gc,t,x,y)
    gc:setFont('sansserif','r',size)
end
local function selector_message(gc,text,w,h)
    -- Use the reserved footer area without dropping diagnostic text.
    local lines,size={},9
    repeat
        gc:setFont('sansserif','r',size)
        lines={''}
        for word in string.gmatch(text,'%S+') do
            local i=#lines
            local candidate=lines[i]=='' and word or lines[i]..' '..word
            if gc:getStringWidth(candidate)>w-16 and lines[i]~='' then
                lines[i+1]=word
            else lines[i]=candidate end
        end
        if #lines*(size+3)<=27 or size==6 then break end
        size=size-1
    until false
    for i,line in ipairs(lines) do label(gc,line,8,h-42+(i-1)*(size+3)) end
    gc:setFont('sansserif','r',9)
end
local function header(gc,w)
    color(gc,18,44,66);gc:fillRect(0,0,w,22)
    color(gc,255,255,255);gc:setFont('sansserif','b',11)
    label(gc,'BeamCX | EB 2D | v0.6.0',6,4)
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

local function scroll_top(index,top,count)
    if index<top then return index end
    if index>=top+count then return index-count+1 end
    return top
end
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
    if index==5 then
        local i=math.min(3,math.floor(xi*3)+1)
        local t=xi*3-(i-1)
        local ends={0,-.1,-.1,0}
        return t*(1-t)/2+ends[i]*(1-t)+ends[i+1]*t
    end
    local ends=selector_moment_ends[index]
    return xi*(1-xi)/2+ends[1]*(1-xi)+ends[2]*xi
end
local function draw_selector(gc,w,h)
    color(gc,215,225,236);gc:setFont('sansserif','r',10)
    label(gc,'SELECT SYSTEM',8,28)
    gc:setFont('sansserif','r',9)
    label(gc,'M (q>0)',w-76,28)
    local margin,gap,top=8,8,46
    local card_w=(w-2*margin-2*gap)/3
    local card_h=(h-43-top-gap)/2
    gc:setPen('thin','smooth')
    for i=1,6 do
        local x=margin+((i-1)%3)*(card_w+gap)
        local y=top+math.floor((i-1)/3)*(card_h+gap)
        if i==sel_index then color(gc,213,232,245)
        else color(gc,23,46,62) end
        gc:fillRect(x,y,card_w,card_h)
        if i==sel_index then color(gc,18,44,66)
        else color(gc,215,225,236) end
        -- Zones: name [y+2,y+14], schematic [y+15,y+33],
        -- moment [y+35,y+card_h-2]. The last zone follows the window height.
        gc:setFont('sansserif','r',9)
        if gc:getStringWidth(presets[i])>card_w-8 then gc:setFont('sansserif','r',8) end
        label(gc,presets[i],x+(card_w-gc:getStringWidth(presets[i]))/2,y+2)
        if i==6 then
            local left,right,top,bottom=x+24,x+card_w-24,y+18,y+card_h-8
            gc:drawLine(left,bottom,left,top);gc:drawLine(left,top,right,top);gc:drawLine(right,top,right,bottom)
            color(gc,91,195,203)
            for _,base in ipairs{left,right} do
                gc:drawLine(base-6,bottom,base+6,bottom)
                for k=-1,1 do gc:drawLine(base+k*4,bottom,base+k*4-2,bottom+3) end
            end
            if card_h>=55 then
                -- Illustrative fixed portal under q>0, unrelated to live inputs.
                color(gc,242,177,103)
                gc:drawLine(left+3,bottom,left-6,top)
                gc:drawLine(right-3,bottom,right+6,top)
                for k=0,15 do
                    local a,b=k/16,(k+1)/16
                    gc:drawLine(left+(right-left)*a,top-6+32*a*(1-a),
                        left+(right-left)*b,top-6+32*b*(1-b))
                end
            end
        else
        local left,right,ybeam=x+12,x+card_w-12,y+22
        gc:drawLine(left,ybeam,right,ybeam)
        if i==5 then
            for k=0,3 do mini_support(gc,left+(right-left)*k/3,ybeam,k==0,false) end
        else
            mini_support(gc,left,ybeam,true,i~=1)
            if i~=2 then mini_support(gc,right,ybeam,false,i==3) end
        end
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
        end -- beam/continuous reference card
    end
    gc:setFont('sansserif','r',9)
    if restore_notice then
        color(gc,255,200,112)
        label(gc,'Invalid document or version:',8,h-42)
        label(gc,'defaults restored',8,h-29)
    elseif selector_error then
        color(gc,255,140,120)
        selector_message(gc,selector_error,w,h)
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

on=on or {}
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
function on.paint(gc)
    local w=platform.window:width()
    local h=platform.window:height()
    color(gc,12,25,36);gc:fillRect(0,0,w,h)
    header(gc,w)
    if page==0 then draw_selector(gc,w,h);return end
    if params.support==6 then
        if page==1 then draw_portal_edit(gc,w,h)
        elseif calculating then
            color(gc,255,200,112);gc:setFont('sansserif','r',12);label(gc,'Calculating...',20,65)
        elseif result and samples and not stale then
            if mode==5 then draw_portal_table(gc,w,h) else portal_diagram(gc,w,h) end
        end
        return
    end
    if params.support==5 and page==2 then
        if calculating then
            color(gc,255,200,112);gc:setFont('sansserif','r',12)
            label(gc,'Calculating…',20,65)
        elseif result and samples then
            if mode==4 then draw_continuous_table(gc,w,h) else continuous_diagram(gc,w,h) end
        end
        return
    end
    if page==3 then draw_section(gc,w,h)
    elseif page==2 and result then
        if mode==4 then draw_results(gc,w,h) else diagram(gc,w,h) end
    elseif params.support==5 then draw_continuous_edit(gc,w,h)
    else draw_edit(gc,w,h) end
end
local function redraw() platform.window:invalidate() end
function on.timer()
    timer.stop()
    if not calculating or (params.support~=5 and params.support~=6) or page~=2 then return end
    local isportal=params.support==6
    local ok,sol,message
    if isportal then ok,sol,message=pcall(PortalPreset.solve,copy(portal))
    else ok,sol,message=pcall(ContinuousPreset.solve,continuous_parameters()) end
    if ok and sol then
        result=sol;summary=sol.summary
        local cached,problem=pcall(isportal and cache_portal or cache_samples)
        if not cached then ok=false;message=problem end
    end
    calculating=false
    if ok and sol then
        stale=false;err=nil;selection_before=nil
        if isportal then portal_confirmed={parameters=copy(portal),result=result,samples=samples} end
    else
        if not ok and not message then message=sol end
        if isportal and not selection_before and portal_confirmed then
            portal=copy(portal_confirmed.parameters);result=portal_confirmed.result;summary=result.summary
            samples=portal_confirmed.samples;stale=false;cache_cursor()
            page=1;err=message or 'calculation failed'
        else
            samples=nil;cursor_value=nil;characteristic=nil;result=nil;summary=nil
            rollback_selection(message or 'calculation failed')
        end
    end
    redraw()
end
local function apply_edit(key,v)
    if key=='manualEI' or key=='b' or key=='h' then
        local old=section[key]
        section[key]=v
        local info,msg=sec_info()
        if not info then
            section[key]=old
            if params.support~=5 then result=nil;summary=nil end
            export_message=nil;err=msg;return
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
local function apply_continuous(key,v)
    local candidate=copy(continuous)
    if type(key)=='number' then candidate.spans[key]=v else candidate[key]=v end
    local p=copy(candidate)
    p.EI=params.EI;p.limit=settings.limit
    p.g=p.g+(settings.self_weight and q_sw or 0)
    local valid,message=ContinuousPreset.model(p,'G')
    if not valid then err=message;return end
    continuous=candidate;dirty()
end
local function apply_portal(key,value)
    local candidate=copy(portal);candidate[key]=value
    if key=='l' and candidate.P==0 and finite(value) and value>0 and candidate.a>value then candidate.a=value/2 end
    local valid,message=PortalPreset.model(candidate)
    if not valid then err=message;export_message=nil;return end
    if candidate[key]==portal[key] and candidate.a==portal.a then err=nil;return end
    portal=candidate;portal_s=math.min(portal_s,portal_member==2 and portal.l or portal.h)
    dirty_portal()
end
local function commit()
    if typing==nil then return end
    local v=tonumber(typing)
    -- Invalid text never changed the model; retain its last valid solution.
    if v==nil then export_message=nil;err='invalid number'
    elseif page==1 and params.support==6 then apply_portal(portal_fields[edit_index][1],v)
    elseif page==1 and params.support==5 then
        local key=continuous_rows()[edit_index].key
        if type(key)=='number' or key=='g' or key=='q' or key=='gG_sup' or key=='gG_inf' or key=='gQ' then
            apply_continuous(key,v)
        end
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
    if page==1 and params.support==6 then
        if edit_index==1 then apply_portal('base',portal.base=='PIN' and 'FIX' or 'PIN') end
    elseif page==1 and params.support==5 then
        local key=continuous_rows()[edit_index].key
        if key=='n' then
            local n=math.max(2,math.min(ContinuousPreset.MAX_SPANS,#continuous.spans+d))
            if n~=#continuous.spans then
                local spans={}
                for i=1,n do spans[i]=continuous.spans[i] or continuous.spans[#continuous.spans] end
                continuous.spans=spans;dirty()
            end
        elseif key=='left' or key=='right' then
            apply_continuous(key,continuous[key]=='PIN' and 'FIX' or 'PIN')
        end
    elseif page==1 and edit_index==1 then
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
        elseif row.key=='limit' then
            settings.limit=settings.limit==250 and 300 or 250
            recalc()
        end
    end
end
local function dismiss_restore_notice()
    if restore_notice then restore_notice=nil;redraw() end
end
function on.tabKey()
    dismiss_restore_notice()
    if page==0 then return end
    local was_editing=typing~=nil
    commit()
    if params.support==6 then
        if not was_editing or not err then
            if page==1 then err=nil;show_results() else page=1 end
        elseif page==2 then page=1 end
        if calculating and page~=2 then timer.stop();calculating=false end
        redraw();return
    end
    if result or params.support==5 then
        if page==1 then show_results()
        elseif page==2 then page=3
        elseif page==3 then page=1 end
    end
    if calculating and page~=2 then timer.stop();calculating=false end
    redraw()
end
function on.enterKey()
    dismiss_restore_notice()
    if page==0 then open_selected_system();redraw();return end
    if page==1 then
        if params.support==6 then commit()
        elseif params.support==5 then
            if typing~=nil then commit() else step_selection(1) end
        elseif edit_index==1 then step_selection(1) else commit() end
    elseif page==2 then
        if not calculating then
            local tablemode=params.support==6 and 5 or 4
            if mode==tablemode then export_cas() else mode=tablemode end
        end
    elseif page==3 then
        local row=active_section_index()[sec_index]
        if row.key=='material' or row.key=='profile' or row.key=='self_weight' or row.key=='limit' then step_selection(1)
        else commit() end
    end
    redraw()
end
function on.charIn(ch)
    dismiss_restore_notice()
    if page==0 then return end
    if params.support==6 and page==2 then
        local member=tonumber(ch)
        if not calculating and mode~=5 and member and member%1==0 and member>=1 and member<=3 and member~=portal_member then
            portal_member=member;cache_cursor();redraw()
        end
        return
    end
    local can=false
    if page==1 and params.support==6 then can=edit_index~=1
    elseif page==1 and params.support==5 then
        local key=continuous_rows()[edit_index].key
        can=key~='n' and key~='left' and key~='right'
    elseif page==1 then can=edit_index~=1 and (names[edit_index]~='EI' or section.material==1)
    elseif page==3 then
        local row=active_section_index()[sec_index]
        can=row.editable and row.key~='material' and row.key~='profile' and row.key~='self_weight' and row.key~='limit'
    end
    if not can then return end
    if ch=='−' then ch='-' end -- TI handheld minus key can send U+2212
    if string.match(ch,'^[0-9%.%-]$') then
        typing=(typing or '')..ch
        redraw()
    end
end
function on.backspaceKey()
    dismiss_restore_notice()
    if page==0 then return end
    if typing and #typing>0 then typing=string.sub(typing,1,-2) end
    redraw()
end
function on.escapeKey()
    dismiss_restore_notice()
    if page==0 then return end
    if typing~=nil then typing=nil;err=nil
    else
        if calculating then timer.stop();calculating=false end
        if result~=nil then err=nil end
        page=0;sel_index=params.support;selector_error=nil
    end
    redraw()
end
local function move_field(d)
    if page==1 then
        local count=params.support==6 and 10 or (params.support==5 and #continuous_rows() or #names)
        edit_index=math.max(1,math.min(count,edit_index+d))
    elseif page==3 then
        local rows=section_rows()
        local i=sec_index+d
        while i>=1 and i<=#rows do
            if rows[i].editable then sec_index=i;break end
            i=i+d
        end
    end
end
local function move_continuous_cursor(d)
    if not result or not samples then return end
    local total=result.supports[#result.supports].position
    local old=cursor*total
    local x=math.max(0,math.min(total,old+d*.025*total))
    -- Include every support in the cursor path, also with unequal span lengths.
    for _,s in ipairs(result.supports) do
        if d>0 and s.position>old+1e-9*total and s.position<x then x=s.position end
        if d<0 and s.position<old-1e-9*total and s.position>x then x=s.position end
    end
    if x~=old then cursor=x/total;cache_cursor() end
end
local function move_portal_cursor(direction)
    if calculating or not samples then return end
    if mode==5 then
        table_page=math.max(1,math.min(#samples.table,table_page-direction));return
    end
    local data=samples.members[portal_member]
    local index=direction>0 and #data or 1
    if direction>0 then
        for i,v in ipairs(data) do
            if v.s>portal_s or (v.s==portal_s and v.side=='right' and portal_side=='left') then index=i;break end
        end
    else
        for i=#data,1,-1 do
            local v=data[i]
            if v.s<portal_s or (v.s==portal_s and v.side=='left' and portal_side=='right') then index=i;break end
        end
    end
    local v=data[index]
    if v.s~=portal_s or v.side~=portal_side then portal_s=v.s;portal_side=v.side;cache_cursor() end
end
function on.arrowUp()
    dismiss_restore_notice()
    if page==0 then
        if sel_index>3 then sel_index=sel_index-3 end
        redraw();return
    end
    if page==2 and params.support==6 then move_portal_cursor(1);redraw();return end
    if page==2 and params.support==5 then
        if not calculating then
            if mode==4 then table_page=1 else move_continuous_cursor(1) end
        end
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
    dismiss_restore_notice()
    if page==0 then
        if sel_index<=3 then sel_index=sel_index+3 end
        redraw();return
    end
    if page==2 and params.support==6 then move_portal_cursor(-1);redraw();return end
    if page==2 and params.support==5 then
        if not calculating then
            if mode==4 then table_page=2 else move_continuous_cursor(-1) end
        end
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
    dismiss_restore_notice()
    if page==0 then
        if (sel_index-1)%3>0 then sel_index=sel_index-1 end
        redraw();return
    end
    if page==2 and params.support==6 then mode=(mode+3)%5+1
    elseif page==2 then mode=(mode+2)%4+1
    else commit();step_selection(-1) end
    redraw()
end
function on.arrowRight()
    dismiss_restore_notice()
    if page==0 then
        if (sel_index-1)%3<2 then sel_index=sel_index+1 end
        redraw();return
    end
    if page==2 and params.support==6 then mode=mode%5+1
    elseif page==2 then mode=mode%4+1
    else commit();step_selection(1) end
    redraw()
end
-- Saved inside the .tns document when the user saves it (TI Lua API on.save/restore).
function on.save()
    return {format='0.6.0',params=copy(params),section=copy(section),portal=copy(portal),
        continuous=copy(continuous),page=page,mode=mode,cursor=cursor,
        portal_member=portal_member,portal_s=portal_s,portal_side=portal_side,
        settings=copy(settings)}
end
local function valid_document(data)
    if type(data)~='table' or data.format~='0.6.0' then return false end
    local p,s,c,t=data.params,data.section,data.continuous,data.settings
    if type(p)~='table' or type(s)~='table' or type(c)~='table' or type(t)~='table' then return false end
    local function integer(v,lo,hi) return finite(v) and v%1==0 and v>=lo and v<=hi end
    if not PortalPreset.model(data.portal) or not integer(data.portal_member,1,3)
       or not finite(data.portal_s) or data.portal_s<0
       or data.portal_s>(data.portal_member==2 and data.portal.l or data.portal.h)
       or (data.portal_side~='left' and data.portal_side~='right') then return false end
    if not integer(data.page,0,3) or not integer(data.mode,1,p.support==6 and 5 or 4)
       or not finite(data.cursor) or data.cursor<0 or data.cursor>1 then return false end
    if p.support==6 and data.page==3 then return false end
    if not integer(p.support,1,6) or not finite(p.L) or p.L<=0
       or not finite(p.EI) or p.EI<=0 or not finite(p.q) or not finite(p.P)
       or not finite(p.a) or p.a<0 or p.a>p.L then return false end
    if not integer(s.material,1,#SectionDB.materials)
       or not integer(s.profile,1,#SectionDB.profiles) then return false end
    for _,key in ipairs{'b','h','manualEI'} do
        if not finite(s[key]) or s[key]<=0 then return false end
    end
    local info=SectionDB.compute(s)
    if not info or not finite(info.EI) or info.EI<=0 then return false end
    if type(t.self_weight)~='boolean' or (t.limit~=250 and t.limit~=300) then return false end
    if type(c.spans)~='table' or not integer(#c.spans,2,ContinuousPreset.MAX_SPANS) then return false end
    for key in pairs(c.spans) do if not integer(key,1,#c.spans) then return false end end
    for i=1,#c.spans do if not finite(c.spans[i]) or c.spans[i]<=0 then return false end end
    if (c.left~='PIN' and c.left~='FIX') or (c.right~='PIN' and c.right~='FIX') then return false end
    if not finite(c.g) or not finite(c.q) then return false end
    for _,key in ipairs{'gG_sup','gG_inf','gQ'} do
        if not finite(c[key]) or c[key]<=0 then return false end
    end
    return true
end
function on.restore(data)
    if calculating then timer.stop() end
    local valid=valid_document(data)
    params=copy(default_params);section=copy(default_section);continuous=copy(default_continuous)
    portal=copy(default_portal);portal_member=2;portal_s=3;portal_side='left';portal_confirmed=nil
    settings={self_weight=false,limit=250}
    page=0;mode=1;cursor=.5;table_page=1;edit_index=1;sec_index=1;edit_top=1;sec_top=1
    typing=nil;selector_error=nil;selection_before=nil;restore_notice=nil
    dirty()
    if valid then
        params=copy(data.params);section=copy(data.section);continuous=copy(data.continuous)
        portal=copy(data.portal);portal_member=data.portal_member;portal_s=data.portal_s;portal_side=data.portal_side
        settings=copy(data.settings)
    else
        restore_notice='Invalid document or version: defaults restored'
    end
    recalc()
    if valid then
        page=data.page;mode=data.mode;cursor=data.cursor
        -- Results reopen at input; no continuous solve until the user enters results.
        if (params.support==5 or params.support==6) and page==2 then page=1 end
    end
    sel_index=params.support
    redraw()
end
