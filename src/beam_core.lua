-- BeamCX: minimal Euler-Bernoulli static port from dc_solver/fem/frame2d.py.
-- Units: m, kN, kN*m, kN*m^2. Positive q/P act DOWN; y and theta positive UP/CCW.
-- Single horizontal span; a point load can occur at either end or inside.
local Beam = {}

local function zeros(n,m)
    local a={}
    for i=1,n do
        a[i]={}
        for j=1,m do a[i][j]=0 end
    end
    return a
end

-- 6x6 local Euler-Bernoulli stiffness; same terms as FrameElementLinear2D.k_local.
local function local_k(L, EA, EI)
    local k=zeros(6,6)
    local a=EA/L
    k[1][1]=a; k[1][4]=-a; k[4][1]=-a; k[4][4]=a
    local b=12*EI/(L^3)
    local c=6*EI/(L^2)
    local d=4*EI/L
    local e=2*EI/L
    local v={2,3,5,6}
    local m={{b,c,-b,c},{c,d,-c,e},{-b,-c,b,-c},{c,e,-c,d}}
    for i=1,4 do
        for j=1,4 do k[v[i]][v[j]]=m[i][j] end
    end
    return k
end

-- Global/local map, kept from dc_solver/fem/frame2d.py rot2d.
local function transformation(c,s)
    return {
        {c,s,0,0,0,0},{-s,c,0,0,0,0},{0,0,1,0,0,0},
        {0,0,0,c,s,0},{0,0,0,-s,c,0},{0,0,0,0,0,1}
    }
end

-- Relative scaled partial pivoting. Inactive/unstable free DOFs fail closed.
local function linear_solve(K, f)
    local n=#f
    local a=zeros(n,n+1)
    local scale={}
    for i=1,n do
        local r=0
        for j=1,n do
            local v=K[i][j]
            a[i][j]=v
            r=math.max(r,math.abs(v))
        end
        a[i][n+1]=f[i]
        if r==0 then return nil, 'mechanism: zero stiffness row' end
        scale[i]=r
    end
    for k=1,n do
        local imax=k
        local score=-1
        for i=k,n do
            local p=math.abs(a[i][k])/scale[i]
            if p>score then score=p; imax=i end
        end
        if score<1e-11 then return nil,'mechanism or ill-conditioned stiffness' end
        a[k],a[imax]=a[imax],a[k]
        scale[k],scale[imax]=scale[imax],scale[k]
        local pivot=a[k][k]
        for i=k+1,n do
            local fac=a[i][k]/pivot
            a[i][k]=0
            for j=k+1,n+1 do
                a[i][j]=a[i][j]-fac*a[k][j]
            end
        end
    end
    local x={}
    for i=n,1,-1 do
        local rhs=a[i][n+1]
        for j=i+1,n do rhs=rhs-a[i][j]*x[j] end
        x[i]=rhs/a[i][i]
        if x[i]~=x[i] or math.abs(x[i])==math.huge then
            return nil,'non-finite linear solution'
        end
    end
    return x
end

local function valid(x)
    return type(x)=='number' and x==x and math.abs(x)<math.huge
end

function Beam.solve(p)
    local L,q,P,a,EI=p.L,p.q,p.P,p.a,p.EI
    if not valid(L) or L<=0 or not valid(q) or not valid(P)
       or not valid(a) or a<0 or a>L or not valid(EI) or EI<=0 then
        return nil,'invalid L, q, P, a or EI'
    end
    if p.support~=1 and p.support~=2 and p.support~=3 and p.support~=4 then
        return nil,'invalid support preset'
    end
    local x={0}
    if P~=0 and a>1e-9*L and a<L-1e-9*L then x[#x+1]=a end
    x[#x+1]=L
    local nn=#x
    local nd=nn*3
    local EA=1000*EI/L^2 -- only axial kinematic regularity; no axial loads in this v0
    local K=zeros(nd,nd)
    local F={}
    for i=1,nd do F[i]=0 end
    local elems={}
    for e=1,nn-1 do
        local le=x[e+1]-x[e]
        local kl=local_k(le,EA,EI)
        local T=transformation(1,0)
        local fe={0,-q*le/2,-q*le^2/12,0,-q*le/2,q*le^2/12}
        local ge={}
        local kg=zeros(6,6)
        for i=1,6 do
            local fi=0
            for m=1,6 do fi=fi+T[m][i]*fe[m] end
            ge[i]=fi
            for j=1,6 do
                local kij=0
                for m=1,6 do
                    for n=1,6 do kij=kij+T[m][i]*kl[m][n]*T[n][j] end
                end
                kg[i][j]=kij
            end
        end
        local map={3*e-2,3*e-1,3*e,3*e+1,3*e+2,3*e+3}
        for i=1,6 do
            F[map[i]]=F[map[i]]+ge[i]
            for j=1,6 do
                K[map[i]][map[j]]=K[map[i]][map[j]]+kg[i][j]
            end
        end
        elems[e]={x0=x[e],L=le,q=q,kl=kl,fe=fe,map=map}
    end
    if P~=0 then
        local node=1
        local best=math.huge
        for i=1,nn do
            local dist=math.abs(x[i]-a)
            if dist<best then best=dist; node=i end
        end
        F[3*node-1]=F[3*node-1]-P
    end
    local fixed={}
    fixed[1]=true      -- left UX (pin or clamp, prevents rigid translation)
    fixed[2]=true      -- left UY
    if p.support~=1 then fixed[3]=true end -- clamp left
    if p.support==1 or p.support==3 or p.support==4 then
        fixed[nd-1]=true -- right UY
    end
    if p.support==3 then
        fixed[nd-2]=true -- right UX
        fixed[nd]=true   -- right theta
    end
    local free={}
    for i=1,nd do if not fixed[i] then free[#free+1]=i end end
    local Kr=zeros(#free,#free)
    local Fr={}
    for i=1,#free do
        Fr[i]=F[free[i]]
        for j=1,#free do Kr[i][j]=K[free[i]][free[j]] end
    end
    local u={}
    for i=1,nd do u[i]=0 end
    if #free>0 then
        local uf,err=linear_solve(Kr,Fr)
        if not uf then return nil,err end
        for i=1,#free do u[free[i]]=uf[i] end
    end
    local r={}
    for i=1,nd do
        local v=-F[i]
        for j=1,nd do v=v+K[i][j]*u[j] end
        r[i]=v
    end
    for e=1,#elems do
        local el=elems[e]
        local f={}
        for i=1,6 do
            local v=-el.fe[i]
            for j=1,6 do v=v+el.kl[i][j]*u[el.map[j]] end
            f[i]=v
        end
        el.f=f
        el.u={}
        for i=1,6 do el.u[i]=u[el.map[i]] end
    end
    local force=r[2]+r[nd-1]-q*L-P
    if p.support==2 then force=r[2]-q*L-P end
    local moment=r[3]+r[nd]+r[nd-1]*L-q*L^2/2-P*a
    if p.support==1 then moment=r[nd-1]*L-q*L^2/2-P*a end
    local tol=2e-7*math.max(1,math.abs(q*L)+math.abs(P),math.abs(q*L^2)+math.abs(P*a))
    if math.abs(force)>tol or math.abs(moment)>tol then
        return nil,'global equilibrium failed'
    end
    return {p=p,x=x,u=u,r=r,elems=elems,force_residual=force,moment_residual=moment}
end

-- V and M use the positive-sagging convention for a beam viewed left to right.
-- w is physical vertical displacement (positive UP); N positive tension.
function Beam.at(sol, pos)
    local x=math.max(0,math.min(sol.p.L,pos))
    local el=sol.elems[#sol.elems]
    for i=1,#sol.elems do
        if x<=sol.elems[i].x0+sol.elems[i].L+1e-10 then
            el=sol.elems[i]; break
        end
    end
    local s=x-el.x0
    local t=s/el.L
    local f=el.f
    local V=f[2]-el.q*s
    local M=-f[3]+f[2]*s-el.q*s*s/2
    local N=-f[1]
    local d=el.u
    local tt=t*t
    local ttt=tt*t
    local w=(1-3*tt+2*ttt)*d[2]
      + el.L*(t-2*tt+ttt)*d[3]
      + (3*tt-2*ttt)*d[5]
      + el.L*(-tt+ttt)*d[6]
      -el.q*el.L^4/(24*sol.p.EI)*tt*(1-t)*(1-t)
    return {N=N,V=V,M=M,w=w}
end

-- Exact bending extrema from V(x)=0 on every (uniformly loaded) segment.
function Beam.moment_extrema(sol)
    local low,high=math.huge,-math.huge
    local xmin,xmax=0,0
    for _,el in ipairs(sol.elems) do
        local candidates={0,el.L}
        if el.q~=0 then
            local s=el.f[2]/el.q
            if s>0 and s<el.L then candidates[#candidates+1]=s end
        end
        for _,s in ipairs(candidates) do
            local m=-el.f[3]+el.f[2]*s-el.q*s*s/2
            if m<low then low=m; xmin=el.x0+s end
            if m>high then high=m; xmax=el.x0+s end
        end
    end
    return low,xmin,high,xmax
end

-- Roots of a quadratic, used only to partition the cubic slope into monotone
-- intervals. Stable product form avoids cancellation at a small root.
local function quadratic_roots(a,b,c)
    if a==0 then
        if b==0 then return {} end
        return {-c/b}
    end
    local disc=b*b-4*a*c
    if disc<0 then return {} end
    local v=-0.5*(b+(b>=0 and 1 or -1)*math.sqrt(disc))
    if v==0 then return {-b/(2*a)} end
    return {v/a,c/v}
end

-- Extrema of the SAME quartic w(t) used by Beam.at, t=s/element length.
-- All boundaries and stationary points are considered. Cubic roots are isolated
-- by the exact quadratic turning points, then bisected (no graphical sampling).
function Beam.deflection_extrema(sol)
    local best,xbest=0,0
    for _,el in ipairs(sol.elems) do
        local d,L=el.u,el.L
        local k=el.q*L^4/(24*sol.p.EI)
        local c1=L*d[3]
        local c2=-3*d[2]-2*L*d[3]+3*d[5]-L*d[6]-k
        local c3=2*d[2]+L*d[3]-2*d[5]+L*d[6]+2*k
        local c4=-k
        -- Normalize to keep root tolerances independent of load / EI magnitude.
        local scale=math.max(math.abs(c1),math.abs(2*c2),math.abs(3*c3),math.abs(4*c4))
        local cuts={0,1}
        local candidates={0,1}
        if scale>0 then
            local a,b,c,d0=4*c4/scale,3*c3/scale,2*c2/scale,c1/scale
            local function slope(t) return ((a*t+b)*t+c)*t+d0 end
            for _,t in ipairs(quadratic_roots(3*a,2*b,c)) do
                if t>0 and t<1 then cuts[#cuts+1]=t end
            end
            table.sort(cuts)
            for _,t in ipairs(cuts) do
                -- Includes repeated stationary roots with no sign change.
                if math.abs(slope(t))<1e-13 then candidates[#candidates+1]=t end
            end
            for i=1,#cuts-1 do
                local lo,hi=cuts[i],cuts[i+1]
                local flo,fhi=slope(lo),slope(hi)
                if (flo<0 and fhi>0) or (flo>0 and fhi<0) then
                    for j=1,60 do
                        local mid=(lo+hi)/2
                        local fm=slope(mid)
                        if fm==0 then lo=mid;hi=mid;break end
                        if (flo<0 and fm<0) or (flo>0 and fm>0) then
                            lo=mid;flo=fm
                        else hi=mid end
                    end
                    candidates[#candidates+1]=(lo+hi)/2
                end
            end
        end
        for _,t in ipairs(candidates) do
            local x=el.x0+el.L*t
            local w=math.abs(Beam.at(sol,x).w)*1000 -- m -> mm
            if w>best then best=w;xbest=x end
        end
    end
    return best,xbest
end

-- Deflection comparison only; not a code-compliance certificate.
function Beam.deflection_check(sol,limit,lref_factor)
    local w,x=Beam.deflection_extrema(sol)
    lref_factor=lref_factor or 1
    local lref=lref_factor*sol.p.L
    local ratio=w>0 and lref*1000/w or nil
    local u250=w/(lref*1000/250)
    local u300=w/(lref*1000/300)
    local utilization=(limit==300) and u300 or u250
    local status='N/A'
    if ratio then status=utilization<=1+1e-12 and 'OK' or 'EXCEEDED' end
    return {w_abs_max=w,x_wmax=x,ratio=ratio,u250=u250,u300=u300,status=status,
        lref=lref,lref_factor=lref_factor}
end

-- Numeric results in the documented bx_ export units. Shear extrema include
-- both faces of every segment, including jumps at the point load.
function Beam.summary(sol,limit,lref_factor)
    local out=Beam.deflection_check(sol,limit,lref_factor)
    local low,_,high=Beam.moment_extrema(sol)
    out.mmin=low;out.mmax=high
    out.vabs=0
    for _,el in ipairs(sol.elems) do
        out.vabs=math.max(out.vabs,math.abs(el.f[2]),math.abs(el.f[2]-el.q*el.L))
    end
    out.ra=sol.r[2];out.rb=sol.r[#sol.r-1];out.ei=sol.p.EI
    return out
end

return Beam
