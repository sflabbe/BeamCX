-- Continuous single-EI beams on Frame. No UI or CAS namespace (P5A).
-- m, kN, kNm, EI in kN*m^2; g/q and reported deflection positive DOWN.
local ContinuousPreset = {MAX_SPANS=5}
local Core=assert(Frame,'load Frame before continuous_preset.lua')
local function convert(value) return -value end -- sole sign boundary
local function finite(x) return type(x)=='number' and x==x and math.abs(x)<math.huge end
local function parameters(p)
    if type(p)~='table' or type(p.spans)~='table' or #p.spans<2 or #p.spans>ContinuousPreset.MAX_SPANS then
        return nil,'expected 2 to '..ContinuousPreset.MAX_SPANS..' spans'
    end
    local out={spans={},EI=p.EI,g=p.g,q=p.q,left=p.left,right=p.right,
        gG_sup=p.gG_sup==nil and 1.35 or p.gG_sup,gG_inf=p.gG_inf==nil and 1 or p.gG_inf,
        gQ=p.gQ==nil and 1.5 or p.gQ,limit=p.limit==nil and 250 or p.limit}
    for i,L in ipairs(p.spans) do
        if not finite(L) or L<=0 then return nil,'invalid span length' end
        out.spans[i]=L
    end
    if not finite(out.EI) or out.EI<=0 then return nil,'invalid EI' end
    if not finite(out.g) or not finite(out.q) then return nil,'invalid uniform load' end
    if (out.left~='PIN' and out.left~='FIX') or (out.right~='PIN' and out.right~='FIX') then return nil,'invalid end support' end
    for _,key in ipairs{'gG_sup','gG_inf','gQ'} do
        if not finite(out[key]) or out[key]<=0 then return nil,'invalid factor '..key end
    end
    if out.limit~=250 and out.limit~=300 then return nil,'invalid deflection limit' end
    return out
end
function ContinuousPreset.model(p,case)
    local p,err=parameters(p)
    if not p then return nil,err end
    local n=#p.spans
    if case~='G' and (not finite(case) or case%1~=0 or case<1 or case>n) then return nil,'invalid load case' end
    local m={nodes={{x=0,y=0}},members={},supports={},member_loads={}}
    local x=0
    for i,L in ipairs(p.spans) do
        x=x+L;m.nodes[i+1]={x=x,y=0}
        m.members[i]={i=i,j=i+1,EI=p.EI,EA=1000*p.EI/L^2}
        m.member_loads[i]={member=i,type='udl',q=convert(case=='G' and p.g or (case==i and p.q or 0))}
    end
    for i=1,n+1 do
        m.supports[i]={node=i,uy=true,ux=i==1 or (i==n+1 and p.right=='FIX'),
            rz=(i==1 and p.left=='FIX') or (i==n+1 and p.right=='FIX')}
    end
    return m
end
local function pattern(mask,n)
    local factors,names={1},{}
    for i=1,n do
        local active=math.floor(mask/2^(i-1))%2==1
        factors[i+1]=active and 1 or 0
        if active then names[#names+1]=tostring(i) end
    end
    return factors,#names>0 and table.concat(names,'-') or '-'
end
local function record(value,x,offset,name,gamma)
    return {value=value,absolute=math.abs(value),x=x,position=offset+x,pattern=name,gammaG=gamma}
end
local function update(current,candidate,maximum)
    if not current or (maximum and candidate.value>current.value) or (not maximum and candidate.value<current.value) then return candidate end
    return current
end
local function solve(p)
    local p,err=parameters(p)
    if not p then return nil,err end
    local n=#p.spans
    local bases={}
    for case=0,n do
        local model=assert(ContinuousPreset.model(p,case==0 and 'G' or case))
        local sol,message=Core.solve(model)
        if not sol then return nil,message end
        bases[case+1]=sol
    end
    local out={parameters=p,bases=bases,spans={},supports={},deflection_label='w car.',
        factor_convention={status='OPEN',reference='EN 1990 Annex A1 and applicable NA'}}
    local offsets={0}
    for i,L in ipairs(p.spans) do
        out.spans[i]={length=L,offset=offsets[i],deflection={label='w car.'}}
        offsets[i+1]=offsets[i]+L
    end
    for i=1,n+1 do out.supports[i]={position=offsets[i]} end
    local function moment(v,x,i)
        -- Prescribed PIN boundary zeros; no response/sign recalculation.
        if (i==1 and x==0 and p.left=='PIN') or (i==n and x==p.spans[i] and p.right=='PIN') then return 0 end
        return v
    end
    for mask=0,2^n-1 do
        local active,name=pattern(mask,n)
        local car,message=Core.combine(bases,active)
        if not car then return nil,message end
        for i,L in ipairs(p.spans) do
            local lo,xlo,hi,xhi=Core.deflection_extrema(car,i)
            xlo=math.max(0,math.min(L,xlo));xhi=math.max(0,math.min(L,xhi))
            if xlo==0 or xlo==L then lo=0 end
            if xhi==0 or xhi==L then hi=0 end
            local d=out.spans[i].deflection
            d.down=update(d.down,record(math.max(0,convert(lo)),xlo,offsets[i],name),true)
            d.up=update(d.up,record(math.min(0,convert(hi)),xhi,offsets[i],name),false)
        end
        for _,gamma in ipairs{p.gG_sup,p.gG_inf} do
            local factors={gamma}
            for j=1,n do factors[j+1]=p.gQ*active[j+1] end
            local sol,message=Core.combine(bases,factors)
            if not sol then return nil,message end
            for i,L in ipairs(p.spans) do
                local lo,xlo,hi,xhi=Core.moment_extrema(sol,i)
                xlo=math.max(0,math.min(L,xlo));xhi=math.max(0,math.min(L,xhi))
                hi=moment(hi,xhi,i)
                out.spans[i].Mmax=update(out.spans[i].Mmax,record(hi,xhi,offsets[i],name,gamma),true)
                for _,s in ipairs{0,L} do
                    local v=Core.at(sol,i,s,s==0 and 'right' or 'left').V
                    out.shear=update(out.shear,record(math.abs(v),s,offsets[i],name,gamma),true)
                end
            end
            for j=1,n+1 do
                local i=j==1 and 1 or j-1
                local x=j==1 and 0 or p.spans[i]
                local M=moment(Core.at(sol,i,x,x==0 and 'right' or 'left').M,x,i)
                local support=out.supports[j]
                support.Mmin=update(support.Mmin,record(M,0,offsets[j],name,gamma),false)
                local R=sol.reactions[j].Ry
                support.Rmax=update(support.Rmax,record(R,0,offsets[j],name,gamma),true)
                support.Rmin=update(support.Rmin,record(R,0,offsets[j],name,gamma),false)
            end
        end
    end
    local Mmax,Mmin,Rmax,Wmax,Xw=-math.huge,math.huge,-math.huge,0,0
    for i,span in ipairs(out.spans) do
        if span.Mmax.value>0 then span.Mplus=span.Mmax end
        local d=span.deflection
        d.governing=d.down.absolute>=d.up.absolute and d.down or d.up
        d.ratio=d.governing.absolute>0 and span.length/d.governing.absolute or nil
        d.utilization={L250=d.governing.absolute/(span.length/250),L300=d.governing.absolute/(span.length/300)}
        d.selected_limit=p.limit
        d.status=not d.ratio and 'N/A' or (d.governing.absolute/(span.length/p.limit)<=1+1e-12 and 'OK' or 'EXCEEDED')
        Mmax=math.max(Mmax,span.Mmax.value)
        if d.governing.absolute>Wmax then Wmax=d.governing.absolute;Xw=d.governing.position end
    end
    for _,s in ipairs(out.supports) do Mmin=math.min(Mmin,s.Mmin.value);Rmax=math.max(Rmax,s.Rmax.value) end
    out.summary={moment_max=Mmax,moment_min=Mmin,shear_absolute_max=out.shear.value,reaction_max=Rmax,
        deflection_absolute_max=Wmax,deflection_position=Xw,rigidity=p.EI,span_count=n}
    function out.envelope_at(x,side)
        if not finite(x) or (side~=nil and side~='left' and side~='right') then error('invalid envelope query',0) end
        x=math.max(0,math.min(offsets[n+1],x))
        local i=1
        while i<n and (x>offsets[i+1] or (x==offsets[i+1] and side=='right')) do i=i+1 end
        local s=x-offsets[i]
        local limit=side or (x==0 and 'right' or 'left')
        local G=Core.at(bases[1],i,s,limit)
        local values={Mmax=math.max(p.gG_sup*G.M,p.gG_inf*G.M),Mmin=math.min(p.gG_sup*G.M,p.gG_inf*G.M),
            Vmax=math.max(p.gG_sup*G.V,p.gG_inf*G.V),Vmin=math.min(p.gG_sup*G.V,p.gG_inf*G.V)}
        for j=2,#bases do
            local Q=Core.at(bases[j],i,s,limit)
            values.Mmax=values.Mmax+p.gQ*math.max(0,Q.M);values.Mmin=values.Mmin+p.gQ*math.min(0,Q.M)
            values.Vmax=values.Vmax+p.gQ*math.max(0,Q.V);values.Vmin=values.Vmin+p.gQ*math.min(0,Q.V)
        end
        return values
    end
    return out
end
function ContinuousPreset.solve(p)
    return solve(p)
end

return ContinuousPreset
