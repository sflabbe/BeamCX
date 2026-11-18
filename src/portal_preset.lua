-- Rectangular one-bay portal on Frame, calculation only (P6A).
-- m, kN, kNm; EIc/EIb in kN*m^2. q/P DOWN; H/w global RIGHT.
-- EA=1e6*EI/L^2 approximates negligible axial deformation for THIS preset.
-- The six analytical witnesses differ by order 1e-5, not a universal bound.
-- Frame signs: N tension positive, V=dM/ds, deflection local +y.
-- M>0 tensions local -y: global RIGHT for columns 1 (1->2) and 3 (4->3),
-- global DOWN for beam 2 (2->3). Both columns run from base to top.
local PortalPreset={}
local Core=assert(Frame,'load Frame before portal_preset.lua')
local function finite(x) return type(x)=='number' and x==x and math.abs(x)<math.huge end
local function convert(value) return -value end -- sole sign boundary; units stay m/kN

function PortalPreset.model(p)
    if type(p)~='table' then return nil,'expected portal parameters' end
    for _,key in ipairs{'h','l','EIc','EIb'} do
        if not finite(p[key]) or p[key]<=0 then return nil,'invalid '..key end
    end
    if p.base~='PIN' and p.base~='FIX' then return nil,'invalid base' end
    for _,key in ipairs{'q','P','a','H','w'} do
        if not finite(p[key]) then return nil,'invalid '..key end
    end
    if p.a<0 or p.a>p.l then return nil,'a outside beam' end
    local loads={{member=1,type='udl',q=convert(p.w)},
                 {member=2,type='udl',q=convert(p.q)}}
    if p.P~=0 then loads[#loads+1]={member=2,type='point',a=p.a,P=convert(p.P)} end
    return {nodes={{x=0,y=0},{x=0,y=p.h},{x=p.l,y=p.h},{x=p.l,y=0}},
        members={{i=1,j=2,EI=p.EIc,EA=1e6*p.EIc/p.h^2},
                 {i=2,j=3,EI=p.EIb,EA=1e6*p.EIb/p.l^2},
                 {i=4,j=3,EI=p.EIc,EA=1e6*p.EIc/p.h^2}},
        supports={{node=1,ux=true,uy=true,rz=p.base=='FIX'},
                  {node=4,ux=true,uy=true,rz=p.base=='FIX'}},
        nodal_loads={{node=2,Fx=p.H}},member_loads=loads}
end

function PortalPreset.at(sol,member,s,side)
    return Core.at(sol.frame,member,s,side or (s==0 and 'right' or 'left'))
end

-- Roots of a+b*t+c*t^2, in normalized interval coordinates.
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

-- w_rel=w-(1-s/l)*w(0)-(s/l)*w(l). Its stationary equation is
-- theta(s)=chord slope, a cubic on each q/P interval. Split at M=0 so
-- that theta-chord is monotone; bisection then finds ALL sign-changing
-- roots, and split boundaries also cover repeated roots. No grid search.
function PortalPreset.deflection_extrema(sol)
    local p=sol.parameters
    local L=p.l
    local w0=PortalPreset.at(sol,2,0).w
    local wL=PortalPreset.at(sol,2,L).w
    local chord=(wL-w0)/L
    local best={value=0,absolute=0,position=0}
    local function candidate(s)
        local value=PortalPreset.at(sol,2,s).w-(1-s/L)*w0-(s/L)*wL
        if s==0 or s==L then value=0 end
        if math.abs(value)>best.absolute then
            best={value=value,absolute=math.abs(value),position=s}
        end
    end
    local cuts={0,L}
    if p.P~=0 and p.a>0 and p.a<L then cuts={0,p.a,L} end
    local theta=sol.frame.u[6]
    for i=1,#cuts-1 do
        local start,finish=cuts[i],cuts[i+1]
        local d=finish-start
        local v=PortalPreset.at(sol,2,start,'right')
        local q=convert(p.q)
        local function slope(t)
            local x=t*d
            return theta-chord+x*(v.M+x*(v.V/2+x*q/6))/p.EIb
        end
        local split={0,1}
        for _,t in ipairs(roots(v.M,v.V*d,q*d*d/2)) do
            if t>0 and t<1 then split[#split+1]=t end
        end
        table.sort(split)
        for j=1,#split-1 do
            local a,b=split[j],split[j+1]
            candidate(start+a*d);candidate(start+b*d)
            local fa,fb=slope(a),slope(b)
            if (fa<0 and fb>0) or (fa>0 and fb<0) then
                for _=1,60 do
                    local mid=(a+b)/2
                    local fm=slope(mid)
                    if (fa<0 and fm<0) or (fa>0 and fm>0) then a=mid;fa=fm
                    else b=mid end
                end
                candidate(start+(a+b)*d/2)
            end
        end
        theta=theta+d*(v.M+d*(v.V/2+d*q/6))/p.EIb
    end
    return best
end

function PortalPreset.summary(sol)
    return {reactions=sol.reactions,member_extrema=sol.members,
        corner_moments=sol.corners,drift=sol.drift,beam_deflection=sol.deflection}
end

function PortalPreset.solve(p)
    local model,err=PortalPreset.model(p)
    if not model then return nil,err end
    local frame
    frame,err=Core.solve(model) -- exactly one solve, simultaneous characteristic loads
    if not frame then return nil,err end
    local sol={parameters={},frame=frame,members={},reactions={}}
    for _,key in ipairs{'h','l','base','EIc','EIb','q','P','a','H','w'} do sol.parameters[key]=p[key] end
    for _,base in ipairs{{'left',1},{'right',4}} do
        local r=frame.reactions[base[2]]
        sol.reactions[base[1]]={H=r.Rx,V=r.Ry,M=p.base=='FIX' and r.Mz or nil}
    end
    for member=1,3 do
        local lo,xlo,hi,xhi=Core.moment_extrema(frame,member)
        local L=member==2 and p.l or p.h
        local function position(x) return math.max(0,math.min(L,x)) end
        local N=PortalPreset.at(sol,member,0).N -- constant: no axial member loads
        sol.members[member]={moments={minimum={value=lo,position=position(xlo)},
            maximum={value=hi,position=position(xhi)}},
            axial={value=N,absolute=math.abs(N),position=0}}
    end
    sol.corners={left={column=PortalPreset.at(sol,1,p.h).M,beam=PortalPreset.at(sol,2,0).M},
        right={column=PortalPreset.at(sol,3,p.h).M,beam=PortalPreset.at(sol,2,p.l).M}}
    sol.drift={left=frame.u[4],right=frame.u[7]}
    sol.deflection=PortalPreset.deflection_extrema(sol)
    function sol.at(member,s,side) return PortalPreset.at(sol,member,s,side) end
    sol.summary=PortalPreset.summary(sol)
    return sol
end

return PortalPreset
