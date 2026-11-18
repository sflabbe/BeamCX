-- BeamCX v0.5.0, UI (TI-Lua 5.1). Single productive Frame engine.
local SectionDB=DB -- the offline DB from the generated single-file script
local presets={'PIN-PIN','FIX-FREE','FIX-FIX','FIX-PIN','CONTINUA'}
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
local function continuous_parameters()
    local p=copy(continuous)
    p.EI=params.EI;p.limit=settings.limit
    p.g=p.g+(settings.self_weight and q_sw or 0)
    return p
end
local function continuous_rows()
    local rows={{key='n',caption='n vanos',value=#continuous.spans}}
    for i,L in ipairs(continuous.spans) do
        rows[#rows+1]={key=i,caption='L'..i..' [m]',value=L}
    end
    for _,r in ipairs{{'left','Extremo izq.'},{'right','Extremo der.'},
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
        stale=b.stale;continuous=b.continuous
        page=0;selector_error=message;selection_before=nil
    else err=message;page=1 end
end
local function open_selected_system()
    local before={params=copy(params),section=copy(section),settings=copy(settings),
        result=result,summary=summary,err=err,export_message=export_message,q_sw=q_sw,
        samples=samples,cursor_value=cursor_value,characteristic=characteristic,
        stale=stale,continuous=copy(continuous)}
    params.support=sel_index
    if sel_index==5 then
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
    if params.support==5 and stale then
        calculating=true
        platform.window:invalidate()
        timer.start(0.05)
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
    if params.support==5 then
        values={{'bc_mmax',summary.moment_max},{'bc_mmin',summary.moment_min},
            {'bc_vabs',summary.shear_absolute_max},{'bc_rmax',summary.reaction_max},
            {'bc_wmax',summary.deflection_absolute_max*1000},
            {'bc_xwmax',summary.deflection_position},{'bc_ei',summary.rigidity},
            {'bc_n',summary.span_count}}
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
    export_message='CAS: 8 variables stored'
end

local function color(gc,r,g,b) gc:setColorRGB(r,g,b) end
local function label(gc,t,x,y) gc:drawString(t,x,y,'top') end
local function fitted(gc,t,x,y,width)
    while #t>0 and gc:getStringWidth(t)>width do
        local last=#t
        while last>1 and string.byte(t,last)>=128 and string.byte(t,last)<192 do last=last-1 end
        t=string.sub(t,1,last-1)
    end
    label(gc,t,x,y)
end
local function header(gc,w)
    color(gc,18,44,66);gc:fillRect(0,0,w,22)
    color(gc,255,255,255);gc:setFont('sansserif','b',11)
    label(gc,'BeamCX | EB 2D | v0.5.0',6,4)
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

local function scroll_top(index,top,count)
    if index<top then return index end
    if index>=top+count then return index-count+1 end
    return top
end
local function draw_continuous_edit(gc,w,h)
    color(gc,215,225,236);gc:setFont('sansserif','r',10)
    label(gc,'CONTINUA | entrada',8,28)
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
        fitted(gc,i==edit_index and typing~=nil and typing..'_' or value,160,y,w-174)
    end
    gc:setFont('sansserif','r',9);color(gc,255,200,112)
    fitted(gc,err or (stale and 'Desactualizado | TAB: calcular' or 'Resultado guardado'),7,h-45,w-14)
    color(gc,171,193,207)
    label(gc,'UP/DOWN fila | LEFT/RIGHT n, PIN/FIX',7,h-30)
    label(gc,'ENTER aplicar | TAB resultados',7,h-16)
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
        rows[#rows+1]={key='limit',caption='Limite flecha',value='L/'..settings.limit,editable=true}
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
    for i=1,5 do
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
    end
    gc:setFont('sansserif','r',9)
    if restore_notice then
        color(gc,255,200,112)
        label(gc,'Documento no válido o de otra versión:',8,h-42)
        label(gc,'valores por defecto',8,h-29)
    elseif selector_error then
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

local function draw_continuous_table(gc,w,h)
    color(gc,215,225,236);gc:setFont('sansserif','r',9)
    label(gc,'CONTINUA | '..(table_page==1 and 'Vanos' or 'Apoyos')..' | L/'..settings.limit,7,27)
    gc:setFont('sansserif','r',8)
    if table_page==1 then
        for _,c in ipairs{{'#',7},{'L [m]',27},{'M+ kNm',61},{'w mm',119},{'L/|w|',185},{'Estado',253}} do
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
    label(gc,'UP/DOWN tabla | LEFT/RIGHT modos | TAB seccion',7,h-15)
end
local function continuous_diagram(gc,w,h)
    color(gc,215,225,236);gc:setFont('sansserif','r',9)
    local titles={'M envolvente [kNm]','V envolvente [kN]','w caracteristica [mm]'}
    label(gc,'CONTINUA | '..titles[mode],7,28)
    label(gc,mode==3 and 'Naranja: impares | Azul: pares' or 'Naranja: max | Azul: min',7,43)
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
        label(gc,'w impares='..fmt(v.wodd)..' | pares='..fmt(v.weven)..' mm',7,h-61)
    else
        label(gc,'Mmax='..fmt(v.Mmax)..' | Mmin='..fmt(v.Mmin)..' kNm',7,h-61)
        if v.left then
            label(gc,'V izq max/min: '..fmt(v.left.Vmax)..' / '..fmt(v.left.Vmin)..' kN',7,h-47)
            label(gc,'V der max/min: '..fmt(v.right.Vmax)..' / '..fmt(v.right.Vmin)..' kN',7,h-33)
        else label(gc,'Vmax='..fmt(v.Vmax)..' | Vmin='..fmt(v.Vmin)..' kN',7,h-47) end
    end
    color(gc,171,193,207)
    label(gc,'UP/DOWN cursor | LEFT/RIGHT modo | ENTER tabla',7,h-15)
end

on=on or {}
function on.paint(gc)
    local w=platform.window:width()
    local h=platform.window:height()
    color(gc,12,25,36);gc:fillRect(0,0,w,h)
    header(gc,w)
    if page==0 then draw_selector(gc,w,h);return end
    if params.support==5 and page==2 then
        if calculating then
            color(gc,255,200,112);gc:setFont('sansserif','r',12)
            label(gc,'Calculando…',20,65)
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
    if not calculating or params.support~=5 or page~=2 then return end
    local ok,sol,message=pcall(ContinuousPreset.solve,continuous_parameters())
    if ok and sol then
        result=sol;summary=sol.summary
        local cached,problem=pcall(cache_samples)
        if not cached then ok=false;message=problem end
    end
    calculating=false
    if ok and sol then stale=false;err=nil;selection_before=nil
    else
        if not ok and not message then message=sol end
        samples=nil;cursor_value=nil;characteristic=nil;result=nil;summary=nil
        rollback_selection(message or 'calculation failed')
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
local function commit()
    if typing==nil then return end
    local v=tonumber(typing)
    -- Invalid text never changed the model; retain its last valid solution.
    if v==nil then export_message=nil;err='invalid number'
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
    if page==1 and params.support==5 then
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
    commit()
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
        if params.support==5 then
            if typing~=nil then commit() else step_selection(1) end
        elseif edit_index==1 then step_selection(1) else commit() end
    elseif page==2 then
        if not calculating then
            if mode==4 then export_cas() else mode=4 end
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
    local can=false
    if page==1 and params.support==5 then
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
        local count=params.support==5 and #continuous_rows() or #names
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
function on.arrowUp()
    dismiss_restore_notice()
    if page==0 then
        if sel_index>3 then sel_index=sel_index-3 end
        redraw();return
    end
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
        if sel_index<=3 then sel_index=math.min(5,sel_index+3) end
        redraw();return
    end
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
    if page==2 then mode=(mode+2)%4+1
    else commit();step_selection(-1) end
    redraw()
end
function on.arrowRight()
    dismiss_restore_notice()
    if page==0 then
        if (sel_index-1)%3<2 and sel_index<5 then sel_index=sel_index+1 end
        redraw();return
    end
    if page==2 then mode=mode%4+1
    else commit();step_selection(1) end
    redraw()
end
-- Saved inside the .tns document when the user saves it (TI Lua API on.save/restore).
function on.save()
    return {format='0.5.0',params=copy(params),section=copy(section),
        continuous=copy(continuous),page=page,mode=mode,cursor=cursor,
        settings=copy(settings)}
end
local function valid_document(data)
    if type(data)~='table' or data.format~='0.5.0' then return false end
    local p,s,c,t=data.params,data.section,data.continuous,data.settings
    if type(p)~='table' or type(s)~='table' or type(c)~='table' or type(t)~='table' then return false end
    local function integer(v,lo,hi) return finite(v) and v%1==0 and v>=lo and v<=hi end
    if not integer(data.page,0,3) or not integer(data.mode,1,4)
       or not finite(data.cursor) or data.cursor<0 or data.cursor>1 then return false end
    if not integer(p.support,1,5) or not finite(p.L) or p.L<=0
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
    settings={self_weight=false,limit=250}
    page=0;mode=1;cursor=.5;table_page=1;edit_index=1;sec_index=1;edit_top=1;sec_top=1
    typing=nil;selector_error=nil;selection_before=nil;restore_notice=nil
    dirty()
    if valid then
        params=copy(data.params);section=copy(data.section);continuous=copy(data.continuous)
        settings=copy(data.settings)
    else
        restore_notice='Documento no válido o de otra versión: valores por defecto'
    end
    recalc()
    if valid then
        page=data.page;mode=data.mode;cursor=data.cursor
        -- Results reopen at input; no continuous solve until the user enters results.
        if params.support==5 and page==2 then page=1 end
    end
    sel_index=params.support
    redraw()
end
