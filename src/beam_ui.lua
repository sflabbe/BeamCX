-- BeamCX v0.6.1, UI (TI-Lua 5.1). Single productive Frame engine.
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
local portal_sections={columns=copy(default_section),beam=copy(default_section)}
portal_sections.beam.manualEI=default_portal.EIb
local portal_section_group,portal_beam_self_weight='columns',false
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
local function active_section(group)
    return params.support==6 and portal_sections[group or portal_section_group] or section
end
local function sec_info(group) return SectionDB.compute(active_section(group)) end
local function lref_factor()
    local material=SectionDB.materials[section.material]
    if params.support==2 and material and material.kind=='concrete' then
        -- DIN EN 1992-1-1/NA 7.4.1: cantilever span = 2.5 x cantilever length
        return 2.5
    end
    return 1
end
local function recalc()
    if params.support==6 then
        local columns,message=sec_info('columns')
        if not columns then err=message;return false end
        local beam;beam,message=sec_info('beam')
        if not beam then err=message;return false end
        local p=copy(portal)
        p.EIc=columns.EI;p.EIb=beam.EI
        p.q=p.q+(portal_beam_self_weight and beam.q_sw or 0)
        local valid;valid,message=PortalPreset.model(p)
        if not valid then err=message;return false end
        portal.EIc=columns.EI;portal.EIb=beam.EI
        if beam.q_sw==nil then portal_beam_self_weight=false end
        dirty_portal();return true
    end
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
    for _,group in ipairs{'columns','beam'} do
        local info=sec_info(group)
        row(group=='columns' and 'Columns' or 'Beam',info.label..
            (info.kind=='manual' and '' or ' '..SectionDB.materials[portal_sections[group].material].name))
    end
    row('Self-weight',(portal_beam_self_weight and ('beam '..fmt(sec_info('beam').q_sw)..' kN/m') or 'beam OFF')..' | columns excluded')
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
        portal_sections=b.portal_sections;portal_section_group=b.portal_section_group
        portal_beam_self_weight=b.portal_beam_self_weight
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
        portal_sections=copy(portal_sections),portal_section_group=portal_section_group,
        portal_beam_self_weight=portal_beam_self_weight,
        mode=mode,table_page=table_page,edit_index=edit_index,edit_top=edit_top,
        portal_member=portal_member,portal_s=portal_s,portal_side=portal_side}
    params.support=sel_index
    if sel_index~=6 then mode=math.min(mode,4) end
    if sel_index==6 then
        selection_before=before.params.support~=6 and before or nil
        selector_error=nil;page=1;edit_index=1;edit_top=1;mode=1;table_page=1
        if before.params.support~=6 and not recalc() then rollback_selection(err) end
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
    label(gc,'BeamCX | EB 2D | v0.6.1',6,4)
end

local function scroll_top(index,top,count)
    if index<top then return index end
    if index>=top+count then return index-count+1 end
    return top
end

-- Compact supports shared by the selector and continuous diagrams.
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
                -- Close member ordinates onto the frame at bases and eaves.
                gc:drawLine(left,bottom,left+3,bottom)
                gc:drawLine(right,bottom,right-3,bottom)
                gc:drawLine(left-6,top,left,top)
                gc:drawLine(left,top,left,top-6)
                gc:drawLine(right+6,top,right,top)
                gc:drawLine(right,top,right,top-6)
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

-- Static presentation fragments; all share the state and helpers above.
-- @include beam_ui_single.lua
-- @include beam_ui_continuous.lua
-- @include beam_ui_portal.lua
-- @include beam_ui_sections.lua

on=on or {}
function on.paint(gc)
    local w=platform.window:width()
    local h=platform.window:height()
    color(gc,12,25,36);gc:fillRect(0,0,w,h)
    header(gc,w)
    if page==0 then draw_selector(gc,w,h);return end
    if params.support==6 then
        if page==1 then draw_portal_edit(gc,w,h)
        elseif page==3 then draw_section(gc,w,h)
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
    if isportal then
        local p=copy(portal)
        p.q=p.q+(portal_beam_self_weight and sec_info('beam').q_sw or 0)
        ok,sol,message=pcall(PortalPreset.solve,p)
    else ok,sol,message=pcall(ContinuousPreset.solve,continuous_parameters()) end
    if ok and sol then
        result=sol;summary=sol.summary
        local cached,problem=pcall(isportal and cache_portal or cache_samples)
        if not cached then ok=false;message=problem end
    end
    calculating=false
    if ok and sol then
        stale=false;err=nil;selection_before=nil
        if isportal then portal_confirmed={parameters=copy(portal),sections=copy(portal_sections),
            group=portal_section_group,self_weight=portal_beam_self_weight,result=result,samples=samples} end
    else
        if not ok and not message then message=sol end
        if isportal and not selection_before and portal_confirmed then
            portal=copy(portal_confirmed.parameters);result=portal_confirmed.result;summary=result.summary
            portal_sections=copy(portal_confirmed.sections);portal_section_group=portal_confirmed.group
            portal_beam_self_weight=portal_confirmed.self_weight
            samples=portal_confirmed.samples;stale=false;cache_cursor()
            page=1;err=message or 'calculation failed'
        else
            samples=nil;cursor_value=nil;characteristic=nil;result=nil;summary=nil
            rollback_selection(message or 'calculation failed')
        end
    end
    redraw()
end
local function apply_edit(key,v,group)
    local selected=active_section(group)
    if key=='manualEI' or key=='b' or key=='h' then
        local old=selected[key]
        selected[key]=v
        local info,msg=sec_info(group)
        if not info then
            selected[key]=old
            if params.support~=5 and params.support~=6 then result=nil;summary=nil end
            export_message=nil;err=msg;return
        end
        if params.support==6 and old==v then err=nil;return end
        local valid=recalc()
        if params.support==6 and not valid then selected[key]=old end
        return
    end
    if key=='EI' and selected.material~=1 then
        err='EI from section; use TAB';return
    end
    local old=params[key]
    local olda=params.a
    if key=='EI' then apply_edit('manualEI',v,group)
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
    local effective=copy(candidate)
    effective.q=effective.q+(portal_beam_self_weight and sec_info('beam').q_sw or 0)
    local valid,message=PortalPreset.model(effective)
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
    elseif page==1 and params.support==6 then
        local key=portal_fields[edit_index][1]
        if key=='EIc' or key=='EIb' then apply_edit('EI',v,key=='EIc' and 'columns' or 'beam')
        else apply_portal(key,v) end
    elseif page==1 and params.support==5 then
        local key=continuous_rows()[edit_index].key
        if type(key)=='number' or key=='g' or key=='q' or key=='gG_sup' or key=='gG_inf' or key=='gQ' then
            apply_continuous(key,v)
        end
    elseif page==1 then apply_edit(names[edit_index],v)
    elseif page==3 then
        local row=active_section_index()[sec_index]
        if row and row.editable and row.key~='material' and row.key~='profile'
           and row.key~='self_weight' and row.key~='group' then
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
        local selected=active_section()
        local before=params.support==6 and copy(selected)
        local weight=portal_beam_self_weight
        if not row.editable then return end
        if row.key=='group' then
            portal_section_group=portal_section_group=='columns' and 'beam' or 'columns';sec_top=1
            return
        elseif row.key=='material' then
            selected.material=(selected.material-1+d+#SectionDB.materials)%#SectionDB.materials+1
            sec_index=params.support==6 and 2 or 1
        elseif row.key=='profile' then
            selected.profile=(selected.profile-1+d+#SectionDB.profiles)%#SectionDB.profiles+1
        elseif row.key=='self_weight' then
            local info=sec_info()
            if info and info.q_sw then
                if params.support==6 then portal_beam_self_weight=not portal_beam_self_weight
                else settings.self_weight=not settings.self_weight end
            end
        elseif row.key=='limit' then
            settings.limit=settings.limit==250 and 300 or 250
        else return end
        local valid=recalc()
        if before and not valid then portal_sections[portal_section_group]=before;portal_beam_self_weight=weight end
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
        if was_editing and err then redraw();return end
        if page==1 then err=nil end
    end
    if result or params.support==5 or params.support==6 then
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
        if row.key=='group' or row.key=='material' or row.key=='profile' or row.key=='self_weight' or row.key=='limit' then step_selection(1)
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
        can=row.editable and row.key~='group' and row.key~='material' and row.key~='profile' and row.key~='self_weight' and row.key~='limit'
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
    return {format='0.6.1',params=copy(params),section=copy(section),portal=copy(portal),
        portal_sections=copy(portal_sections),portal_section_group=portal_section_group,
        portal_beam_self_weight=portal_beam_self_weight,
        continuous=copy(continuous),page=page,mode=mode,cursor=cursor,
        portal_member=portal_member,portal_s=portal_s,portal_side=portal_side,
        settings=copy(settings)}
end
local function valid_document(data)
    if type(data)~='table' or data.format~='0.6.1' then return false end
    local p,s,c,t=data.params,data.section,data.continuous,data.settings
    if type(p)~='table' or type(s)~='table' or type(c)~='table' or type(t)~='table' then return false end
    local function integer(v,lo,hi) return finite(v) and v%1==0 and v>=lo and v<=hi end
    local function valid_section(s)
        if type(s)~='table' or not integer(s.material,1,#SectionDB.materials)
           or not integer(s.profile,1,#SectionDB.profiles) then return nil end
        for _,key in ipairs{'b','h','manualEI'} do
            if not finite(s[key]) or s[key]<=0 then return nil end
        end
        local info=SectionDB.compute(s)
        if info and finite(info.EI) and info.EI>0 then return info end
    end
    if not valid_section(s) or type(data.portal_sections)~='table' then return false end
    local columns,beam=valid_section(data.portal_sections.columns),valid_section(data.portal_sections.beam)
    if not columns or not beam or type(data.portal)~='table' or not finite(data.portal.q)
       or (data.portal_section_group~='columns' and data.portal_section_group~='beam')
       or type(data.portal_beam_self_weight)~='boolean'
       or (data.portal_beam_self_weight and not beam.q_sw) then return false end
    local effective=copy(data.portal)
    effective.EIc=columns.EI;effective.EIb=beam.EI
    effective.q=effective.q+(data.portal_beam_self_weight and beam.q_sw or 0)
    if not PortalPreset.model(effective) or not integer(data.portal_member,1,3)
       or not finite(data.portal_s) or data.portal_s<0
       or data.portal_s>(data.portal_member==2 and data.portal.l or data.portal.h)
       or (data.portal_side~='left' and data.portal_side~='right') then return false end
    if not integer(data.page,0,3) or not integer(data.mode,1,p.support==6 and 5 or 4)
       or not finite(data.cursor) or data.cursor<0 or data.cursor>1 then return false end
    if not integer(p.support,1,6) or not finite(p.L) or p.L<=0
       or not finite(p.EI) or p.EI<=0 or not finite(p.q) or not finite(p.P)
       or not finite(p.a) or p.a<0 or p.a>p.L then return false end
    if type(t.self_weight)~='boolean' or (t.limit~=250 and t.limit~=300) then return false end
    if type(c.spans)~='table' or not integer(#c.spans,2,ContinuousPreset.MAX_SPANS) then return false end
    for key in pairs(c.spans) do if not integer(key,1,#c.spans) then return false end end
    for i=1,#c.spans do if not finite(c.spans[i]) or c.spans[i]<=0 then return false end end
    if (c.left~='PIN' and c.left~='FIX') or (c.right~='PIN' and c.right~='FIX') then return false end
    if not finite(c.g) or not finite(c.q) then return false end
    for _,key in ipairs{'gG_sup','gG_inf','gQ'} do
        if not finite(c[key]) or c[key]<=0 then return false end
    end
    effective.q=data.portal.q
    return true,effective
end
function on.restore(data)
    if calculating then timer.stop() end
    local valid,restored_portal=valid_document(data)
    params=copy(default_params);section=copy(default_section);continuous=copy(default_continuous)
    portal=copy(default_portal);portal_member=2;portal_s=3;portal_side='left';portal_confirmed=nil
    portal_sections={columns=copy(default_section),beam=copy(default_section)}
    portal_sections.beam.manualEI=default_portal.EIb
    portal_section_group='columns';portal_beam_self_weight=false
    settings={self_weight=false,limit=250}
    page=0;mode=1;cursor=.5;table_page=1;edit_index=1;sec_index=1;edit_top=1;sec_top=1
    typing=nil;selector_error=nil;selection_before=nil;restore_notice=nil
    dirty()
    if valid then
        params=copy(data.params);section=copy(data.section);continuous=copy(data.continuous)
        portal=restored_portal;portal_member=data.portal_member;portal_s=data.portal_s;portal_side=data.portal_side
        portal_sections=copy(data.portal_sections);portal_section_group=data.portal_section_group
        portal_beam_self_weight=data.portal_beam_self_weight
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
