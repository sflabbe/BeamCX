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
-- Stable roots in the unit span coordinate; no sampling or iterative search.
local function roots(a,b,c)
    local scale=math.max(math.abs(a),math.abs(b),math.abs(c))
    if scale==0 then return {} end
    a,b,c=a/scale,b/scale,c/scale
    if c==0 then return b==0 and {} or {-a/b} end
    local d=b*b-4*a*c
    if d<0 then return {} end
    local q=-.5*(b+(b<0 and -1 or 1)*math.sqrt(d))
    if q==0 then return {-b/(2*c)} end
    return {q/c,a/q}
end
local function polynomial(poly,t) return poly[1]+t*(poly[2]+t*poly[3]) end
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
    local out={parameters=p,bases=bases,spans={},supports={},deflection_label='w char.',
        factor_convention={status='OPEN',reference='EN 1990 Annex A1 and applicable NA'}}
    local offsets={0}
    for i,L in ipairs(p.spans) do
        out.spans[i]={length=L,offset=offsets[i],deflection={label='w char.'}}
        offsets[i+1]=offsets[i]+L
    end
    for i=1,n+1 do out.supports[i]={position=offsets[i]} end
    local function moment(v,x,i)
        -- Prescribed PIN boundary zeros; no response/sign recalculation.
        if (i==1 and x==0 and p.left=='PIN') or (i==n and x==p.spans[i] and p.right=='PIN') then return 0 end
        return v
    end
    -- Scalar response envelopes select each contribution independently.
    local function choose(values,maximum)
        local gamma=p.gG_sup
        if (maximum and p.gG_inf*values[1]>gamma*values[1]) or
           (not maximum and p.gG_inf*values[1]<gamma*values[1]) then gamma=p.gG_inf end
        local value=gamma*values[1]
        local weights,names={gamma},{}
        for j=2,#values do
            local active=(maximum and values[j]>0) or (not maximum and values[j]<0)
            weights[j]=active and p.gQ or 0
            if active then value=value+p.gQ*values[j];names[#names+1]=tostring(j-1) end
        end
        return value,#names>0 and table.concat(names,'-') or '-',gamma,weights
    end
    for i,L in ipairs(p.spans) do
        local polys={}
        for j,base in ipairs(bases) do
            local v=Core.at(base,i,0,'right')
            local q=j==1 and p.g or (j-1==i and p.q or 0)
            polys[j]={moment(v.M,0,i),v.V*L,convert(q)*L^2/2}
        end
        local function values_at(t)
            local values={}
            for j,poly in ipairs(polys) do values[j]=moment(polynomial(poly,t),t*L,i) end
            return values
        end
        -- Cuts at every base zero make both the Qi set and the gammaG fixed.
        local cuts={0,1}
        for _,poly in ipairs(polys) do
            for _,t in ipairs(roots(poly[1],poly[2],poly[3])) do
                if t>0 and t<1 then cuts[#cuts+1]=t end
            end
        end
        table.sort(cuts)
        local function candidate(t,maximum)
            local value,name,gamma=choose(values_at(t),maximum)
            local key=maximum and 'Mmax' or 'Mmin'
            out.spans[i][key]=update(out.spans[i][key],record(value,t*L,offsets[i],name,gamma),maximum)
        end
        for k=1,#cuts-1 do
            local left,right=cuts[k],cuts[k+1]
            if right>left then
                for _,maximum in ipairs{true,false} do
                    local _,_,_,weights=choose(values_at((left+right)/2),maximum)
                    local b,c=0,0
                    for j,poly in ipairs(polys) do b=b+weights[j]*poly[2];c=c+weights[j]*poly[3] end
                    candidate(left,maximum);candidate(right,maximum)
                    if c~=0 then
                        local vertex=-b/(2*c)
                        if vertex>left and vertex<right then candidate(vertex,maximum) end
                    end
                end
            end
        end
        -- Shear is linear on each full-UDL span: its absolute envelope peaks at an end.
        for _,x in ipairs{0,L} do
            local values={}
            for j,base in ipairs(bases) do values[j]=Core.at(base,i,x,x==0 and 'right' or 'left').V end
            for _,maximum in ipairs{true,false} do
                local v,name,gamma=choose(values,maximum)
                out.shear=update(out.shear,record(math.abs(v),x,offsets[i],name,gamma),true)
            end
        end
    end
    for node=1,n+1 do
        local i=node==1 and 1 or node-1
        local x=node==1 and 0 or p.spans[i]
        local M,R={},{}
        for j,base in ipairs(bases) do
            M[j]=moment(Core.at(base,i,x,x==0 and 'right' or 'left').M,x,i)
            R[j]=base.reactions[node].Ry
        end
        for _,field in ipairs{{'M',M},{'R',R}} do
            for _,maximum in ipairs{true,false} do
                local value,name,gamma=choose(field[2],maximum)
                out.supports[node][field[1]..(maximum and 'max' or 'min')]=record(value,0,offsets[node],name,gamma)
            end
        end
    end
    -- Characteristic deflection: two alternating patterns, a verified rule,
    -- not a theorem. The exhaustive comparison belongs only to the test harness.
    for parity=1,2 do
        local factors,names={1},{}
        for i=1,n do
            local active=i%2==parity%2
            factors[i+1]=active and 1 or 0
            if active then names[#names+1]=tostring(i) end
        end
        local name=table.concat(names,'-')
        local characteristic_result,message=Core.combine(bases,factors)
        if not characteristic_result then return nil,message end
        for i,L in ipairs(p.spans) do
            local lo,xlo,hi,xhi=Core.deflection_extrema(characteristic_result,i)
            xlo=math.max(0,math.min(L,xlo));xhi=math.max(0,math.min(L,xhi))
            if xlo==0 or xlo==L then lo=0 end
            if xhi==0 or xhi==L then hi=0 end
            local d=out.spans[i].deflection
            d.down=update(d.down,record(math.max(0,convert(lo)),xlo,offsets[i],name),true)
            d.up=update(d.up,record(math.min(0,convert(hi)),xhi,offsets[i],name),false)
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
        Mmax=math.max(Mmax,span.Mmax.value);Mmin=math.min(Mmin,span.Mmin.value)
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
        local moments,shears={},{}
        for j,base in ipairs(bases) do
            local v=Core.at(base,i,s,limit)
            moments[j]=moment(v.M,s,i);shears[j]=v.V
        end
        local values={Mmax=choose(moments,true),Mmin=choose(moments,false),
            Vmax=choose(shears,true),Vmin=choose(shears,false)}
        return values
    end
    return out
end
function ContinuousPreset.solve(p)
    return solve(p)
end

return ContinuousPreset
