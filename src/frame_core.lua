-- BeamCX v0.4-P1B: pure Lua 5.1, static prismatic Euler-Bernoulli frames.
-- Units: m, kN, kNm; EA in kN, EI in kN*m^2. No TI API or Beam dependency.
-- Global x right, y up, rotations CCW; downward loads are NEGATIVE.
-- Local x follows i -> j; local y is local x rotated +90 degrees.
-- DOFs: [ux_i, uy_i, rz_i, ux_j, uy_j, rz_j]. End forces are NODAL:
-- [N_i, V_i, M_i, N_j, V_j, M_j], positive moments CCW (dc ADR-002).
-- Diagrams: N positive tension; M positive when local -y fibre is in tension;
-- textbook V positive on the left face, dM/ds=V and dV/ds=q.
-- nodal_to_diagram is the ONLY end-force -> diagram sign conversion:
-- M(0)=-M_i, M(L)=+M_j. w is physical local-y displacement, u local-x.
-- Member udl/dist/point act along local y, per unit MEMBER length, for any
-- orientation. Concentrated moments act CCW about z (unchanged by rotation).
-- Global/projected member loads and axial member loads are outside P1B.
-- solve/assemble return nil,message on failure; at/extrema reject bad queries.
-- moment_extrema returns min, s_min, max, s_max; deflection_extrema w, s.
local Frame = {}

local PIVOT_TOL = 1e-12 -- |pivot| / original row maximum, after scaled pivoting.
local CHECK_TOL = 1e-8 -- relative to largest applied force or origin moment.
local MERGE_TOL = 1e-6 -- fraction of USER member length, strict '<'.
local MAX_NODES = 60 -- provisional: measure on the CX in P2.

local function finite(x)
    return type(x)=='number' and x==x and math.abs(x)<math.huge
end
local function require_number(x, name)
    if not finite(x) then error('invalid '..name, 0) end
    return x
end
local function fields(t, allowed, name)
    if type(t)~='table' then error('invalid '..name, 0) end
    for k in pairs(t) do
        if not allowed[k] then error('unsupported '..name..' field: '..tostring(k), 0) end
    end
end
local function zeros(n,m)
    local a={}
    for i=1,n do
        a[i]={}
        for j=1,m do a[i][j]=0 end
    end
    return a
end
local function vector(n)
    local v={}
    for i=1,n do v[i]=0 end
    return v
end

-- Euler branch of dc_solver/fem/frame2d.py, without shear flexibility.
function Frame.local_k(L,EA,EI)
    local k=zeros(6,6)
    local a,b,c,d,e=EA/L,12*EI/L^3,6*EI/L^2,4*EI/L,2*EI/L
    k[1][1]=a; k[1][4]=-a; k[4][1]=-a; k[4][4]=a
    local v={2,3,5,6}
    local bend={{b,c,-b,c},{c,d,-c,e},{-b,-c,b,-c},{c,e,-c,d}}
    for i=1,4 do for j=1,4 do k[v[i]][v[j]]=bend[i][j] end end
    return k
end
function Frame.transformation(c,s)
    return {{c,s,0,0,0,0},{-s,c,0,0,0,0},{0,0,1,0,0,0},
            {0,0,0,c,s,0},{0,0,0,-s,c,0},{0,0,0,0,0,1}}
end
local function rotate_k(k,T)
    local temp,kg=zeros(6,6),zeros(6,6)
    for i=1,6 do for j=1,6 do
        for a=1,6 do temp[i][j]=temp[i][j]+k[i][a]*T[a][j] end
    end end
    for i=1,6 do for j=1,6 do
        for a=1,6 do kg[i][j]=kg[i][j]+T[a][i]*temp[a][j] end
    end end
    return kg
end
local dof_names={'ux','uy','rz'}
local function dof_label(d)
    return 'node '..math.floor((d-1)/3+1)..' '..dof_names[(d-1)%3+1]
end
local function node_index(n,nn)
    if not finite(n) or n%1~=0 or n<1 or n>nn then error('invalid node index',0) end
    return n
end

local function assemble(model)
    fields(model,{nodes=true,members=true,supports=true,nodal_loads=true,member_loads=true},'model')
    if type(model.nodes)~='table' or #model.nodes==0 or
       type(model.members)~='table' or #model.members==0 then error('empty model',0) end
    local nodes,members={},{}
    for i,n in ipairs(model.nodes) do
        fields(n,{x=true,y=true},'node')
        nodes[i]={x=require_number(n.x,'node x'),y=require_number(n.y,'node y')}
    end
    if #nodes>MAX_NODES then error('model too large for handheld',0) end
    local nn=#nodes
    for i,m in ipairs(model.members) do
        fields(m,{i=true,j=true,EI=true,EA=true},'member')
        local ni,nj=node_index(m.i,nn),node_index(m.j,nn)
        local EI,EA=require_number(m.EI,'EI'),require_number(m.EA,'EA')
        local dx,dy=nodes[nj].x-nodes[ni].x,nodes[nj].y-nodes[ni].y
        local L=math.sqrt(dx*dx+dy*dy)
        if not finite(L) or L<=0 or EI<=0 or EA<=0 then error('invalid member geometry or rigidity',0) end
        members[i]={i=ni,j=nj,EI=EI,EA=EA,L=L,c=dx/L,s=dy/L,
                    q=0,points={},moments={},distributed={},cuts={0,L},elements={}}
    end
    for _,load in ipairs(model.member_loads or {}) do
        if type(load)~='table' then error('invalid member load',0) end
        local kind=load.type
        -- Diagnose unsupported TYPE before inspecting its possible fields.
        if kind~='udl' and kind~='point' and kind~='dist' and kind~='moment' then
            error('unsupported member load type: '..tostring(kind),0)
        end
        if kind=='udl' then
            fields(load,{member=true,type=true,q=true},'udl load')
        elseif kind=='dist' then
            fields(load,{member=true,type=true,a=true,b=true,q1=true,q2=true},'dist load')
        elseif kind=='point' then
            fields(load,{member=true,type=true,a=true,P=true},'point load')
        else
            fields(load,{member=true,type=true,a=true,M=true},'moment load')
        end
        local mi=load.member
        if not finite(mi) or mi%1~=0 or not members[mi] then error('invalid member index',0) end
        local m=members[mi]
        if kind=='udl' then
            m.q=m.q+require_number(load.q,'q')
        else
            local a=require_number(load.a,kind..' a')
            if a<0 or a>m.L then error(kind..' a outside member',0) end
            if kind=='dist' then
                local b=require_number(load.b,'dist b')
                if b<=a or b>m.L then error('invalid dist interval: require 0 <= a < b <= L',0) end
                m.distributed[#m.distributed+1]={left={a=a},right={a=b},
                    q1=require_number(load.q1,'q1'),q2=require_number(load.q2,'q2')}
            elseif kind=='point' then
                m.points[#m.points+1]={a=a,P=require_number(load.P,'P')}
            else
                m.moments[#m.moments+1]={a=a,M=require_number(load.M,'M')}
            end
        end
    end
    local elements={}
    for mi,m in ipairs(members) do
        -- Sorted adjacent positions form transitive clusters. An end wins;
        -- otherwise use the leftmost position, independent of load input order.
        local positions={{a=0},{a=m.L}}
        for _,p in ipairs(m.points) do positions[#positions+1]=p end
        for _,p in ipairs(m.moments) do positions[#positions+1]=p end
        for _,d in ipairs(m.distributed) do
            positions[#positions+1]=d.left;positions[#positions+1]=d.right
        end
        table.sort(positions,function(a,b) return a.a<b.a end)
        local cuts,point_nodes={},{}
        local first=1
        while first<=#positions do
            local last=first
            while last<#positions and positions[last+1].a-positions[last].a<MERGE_TOL*m.L do
                last=last+1
            end
            local a=positions[first].a
            if positions[last].a==m.L then a=m.L end
            cuts[#cuts+1]=a
            local id
            if a==0 then id=m.i elseif a==m.L then id=m.j else
                nodes[#nodes+1]={x=nodes[m.i].x+m.c*a,y=nodes[m.i].y+m.s*a}
                if #nodes>MAX_NODES then error('model too large for handheld',0) end
                id=#nodes
            end
            point_nodes[#cuts]=id
            for j=first,last do
                positions[j].position=a;positions[j].node=id
            end
            first=last+1
        end
        m.cuts=cuts;m.point_positions={}
        for _,p in ipairs(m.points) do m.point_positions[p.position]=true end
        for _,p in ipairs(m.moments) do m.point_positions[p.position]=true end
        for j=1,#cuts-1 do
            local L=cuts[j+1]-cuts[j]
            local qa,qb=m.q,m.q
            for _,d in ipairs(m.distributed) do
                local a,b=d.left.position,d.right.position
                -- Snapping preserves endpoint intensities on the snapped
                -- interval. A collapsed interval has zero measure/load.
                if b>a and cuts[j]>=a and cuts[j+1]<=b then
                    qa=qa+d.q1+(d.q2-d.q1)*(cuts[j]-a)/(b-a)
                    qb=qb+d.q1+(d.q2-d.q1)*(cuts[j+1]-a)/(b-a)
                end
            end
            -- Consistent loads: integrate Hermite N(t)^T * q(t) * L dt.
            -- Uniform qa plus triangle 0 -> (qb-qa) gives transverse
            -- forces L*(7qa+3qb)/20, L*(3qa+7qb)/20 and nodal CCW
            -- moments L^2*(3qa+2qb)/60, -L^2*(2qa+3qb)/60.
            -- Uniform branch retains the P1A arithmetic exactly.
            local fe
            if qa==qb then fe={0,qa*L/2,qa*L^2/12,0,qa*L/2,-qa*L^2/12}
            else fe={0,L*(7*qa+3*qb)/20,L^2*(3*qa+2*qb)/60,
                     0,L*(3*qa+7*qb)/20,-L^2*(2*qa+3*qb)/60} end
            local ni,nj=point_nodes[j],point_nodes[j+1]
            local T=Frame.transformation(m.c,m.s)
            local kl=Frame.local_k(L,m.EA,m.EI)
            local el={member=mi,x0=cuts[j],x1=cuts[j+1],L=L,EI=m.EI,qa=qa,qb=qb,
                      T=T,kl=kl,kg=rotate_k(kl,T),
                      fe=fe,
                      map={3*ni-2,3*ni-1,3*ni,3*nj-2,3*nj-1,3*nj}}
            elements[#elements+1]=el;m.elements[#m.elements+1]=el
        end
    end
    local nd=3*#nodes
    local K,F=zeros(nd,nd),vector(nd)
    local applied={Fx=0,Fy=0,Mz=0,scale=0}
    local function external(node,Fx,Fy,Mz)
        local n=nodes[node]
        local mom=n.x*Fy-n.y*Fx+Mz
        applied.Fx=applied.Fx+Fx;applied.Fy=applied.Fy+Fy;applied.Mz=applied.Mz+mom
        applied.scale=math.max(applied.scale,math.abs(Fx),math.abs(Fy),math.abs(mom),math.abs(Mz))
        F[3*node-2]=F[3*node-2]+Fx;F[3*node-1]=F[3*node-1]+Fy;F[3*node]=F[3*node]+Mz
    end
    for _,load in ipairs(model.nodal_loads or {}) do
        fields(load,{node=true,Fx=true,Fy=true,M=true},'nodal load')
        external(node_index(load.node,nn),require_number(load.Fx or 0,'Fx'),
                 require_number(load.Fy or 0,'Fy'),require_number(load.M or 0,'M'))
    end
    for _,m in ipairs(members) do
        for _,p in ipairs(m.points) do external(p.node,-m.s*p.P,m.c*p.P,0) end
        for _,p in ipairs(m.moments) do external(p.node,0,0,p.M) end
        local function line_resultant(a,b,qa,qb)
            local length=b-a
            local R=(qa+qb)*length/2
            -- Signed first moment integral s*q(s) ds, equivalent to R*s_c
            -- when R~=0. No centroid division: R=0 can leave a pure couple.
            local J=a*R+length^2*(qa+2*qb)/6
            local Fx,Fy=-m.s*R,m.c*R
            local origin=nodes[m.i]
            local mom=origin.x*Fy-origin.y*Fx+J
            applied.Fx=applied.Fx+Fx;applied.Fy=applied.Fy+Fy;applied.Mz=applied.Mz+mom
            applied.scale=math.max(applied.scale,math.abs(Fx),math.abs(Fy),math.abs(mom))
        end
        -- Use user loads (at snapped boundaries), not mesh-dependent pieces.
        line_resultant(0,m.L,m.q,m.q)
        for _,d in ipairs(m.distributed) do
            line_resultant(d.left.position,d.right.position,d.q1,d.q2)
        end
    end
    for _,el in ipairs(elements) do
        for i=1,6 do
            local d=el.map[i]
            for a=1,6 do F[d]=F[d]+el.T[a][i]*el.fe[a] end
            for j=1,6 do K[d][el.map[j]]=K[d][el.map[j]]+el.kg[i][j] end
        end
    end
    local fixed={}
    for _,support in ipairs(model.supports or {}) do
        fields(support,{node=true,ux=true,uy=true,rz=true},'support')
        local ni=node_index(support.node,nn)
        for j,name in ipairs(dof_names) do
            local v=support[name]
            if v~=nil and type(v)~='boolean' then error('unsupported prescribed displacement '..name,0) end
            if v then fixed[3*ni-3+j]=true end
        end
    end
    local free={}
    for i=1,nd do
        if not finite(F[i]) then error('ill-conditioned: non-finite load',0) end
        for j=1,nd do
            if not finite(K[i][j]) then error('ill-conditioned: non-finite stiffness',0) end
        end
        if not fixed[i] then free[#free+1]=i end
    end
    return {nodes=nodes,members=members,elements=elements,K=K,F=F,ndof=nd,
            fixed=fixed,free=free,applied=applied}
end
function Frame.assemble(model)
    local ok,result=pcall(assemble,model)
    if ok then return result end
    return nil,result
end

-- Dense LU, partial pivoting by |a_ik| / max_j |original a_ij|.
-- Exactly zero row/column or pivot => mechanism; nonzero relative pivot below
-- 1e-12 => ill-conditioned. Row scaling avoids comparing EA directly to EI.
local function linear_solve(sol)
    local free,K,F=sol.free,sol.K,sol.F
    local n=#free
    local a,scale=zeros(n,n+1),{}
    for i=1,n do
        local rowmax=0
        for j=1,n do a[i][j]=K[free[i]][free[j]];rowmax=math.max(rowmax,math.abs(a[i][j])) end
        if rowmax==0 then error('mechanism: zero stiffness at '..dof_label(free[i]),0) end
        a[i][n+1]=F[free[i]];scale[i]=rowmax
    end
    for k=1,n do
        local imax,score=k,-1
        for i=k,n do
            local p=math.abs(a[i][k])/scale[i]
            if not finite(p) then error('ill-conditioned: non-finite factorization',0) end
            if p>score then score=p;imax=i end
        end
        if score==0 then error('mechanism: zero pivot at '..dof_label(free[k]),0) end
        if score<PIVOT_TOL then error('ill-conditioned: small relative pivot at '..dof_label(free[k]),0) end
        a[k],a[imax]=a[imax],a[k];scale[k],scale[imax]=scale[imax],scale[k]
        for i=k+1,n do
            local fac=a[i][k]/a[k][k]
            a[i][k]=0
            for j=k+1,n+1 do a[i][j]=a[i][j]-fac*a[k][j] end
        end
    end
    local x={}
    for i=n,1,-1 do
        local v=a[i][n+1]
        for j=i+1,n do v=v-a[i][j]*x[j] end
        x[i]=v/a[i][i]
        if not finite(x[i]) then error('ill-conditioned: non-finite solution',0) end
    end
    return x
end
local function solve(model)
    local sol=assemble(model)
    local uf=linear_solve(sol)
    local u=vector(sol.ndof)
    for i,d in ipairs(sol.free) do u[d]=uf[i] end
    sol.u=u
    local residual=vector(sol.ndof)
    for i=1,sol.ndof do
        local v=-sol.F[i]
        for j=1,sol.ndof do v=v+sol.K[i][j]*u[j] end
        if not finite(v) then error('ill-conditioned: non-finite residual',0) end
        residual[i]=v
    end
    sol.reactions={}
    local Fx,Fy,Mz=sol.applied.Fx,sol.applied.Fy,sol.applied.Mz
    local free_residual=0
    for _,d in ipairs(sol.free) do free_residual=math.max(free_residual,math.abs(residual[d])) end
    for i,node in ipairs(sol.nodes) do
        local rx=sol.fixed[3*i-2] and residual[3*i-2] or 0
        local ry=sol.fixed[3*i-1] and residual[3*i-1] or 0
        local mz=sol.fixed[3*i] and residual[3*i] or 0
        sol.reactions[i]={Rx=rx,Ry=ry,Mz=mz}
        Fx=Fx+rx;Fy=Fy+ry;Mz=Mz+node.x*ry-node.y*rx+mz
    end
    -- Zero applied load uses scale=1 solely to define normalized zero checks.
    local scale=sol.applied.scale>0 and sol.applied.scale or 1
    local eq=math.max(math.abs(Fx),math.abs(Fy),math.abs(Mz))
    sol.checks={Fx=Fx,Fy=Fy,Mz=Mz,free_residual=free_residual,scale=scale,
                equilibrium_relative=eq/scale,residual_relative=free_residual/scale,tolerance=CHECK_TOL}
    if not finite(eq) or eq/scale>CHECK_TOL then error('global equilibrium failed',0) end
    if free_residual/scale>CHECK_TOL then error('free DOF residual failed',0) end
    for _,el in ipairs(sol.elements) do
        el.u=vector(6);el.f=vector(6)
        for i=1,6 do for j=1,6 do el.u[i]=el.u[i]+el.T[i][j]*u[el.map[j]] end end
        -- Essential: subtract the consistent fixed-end load vector.
        for i=1,6 do
            el.f[i]=-el.fe[i]
            for j=1,6 do el.f[i]=el.f[i]+el.kl[i][j]*el.u[j] end
            if not finite(el.f[i]) then error('ill-conditioned: non-finite end forces',0) end
        end
    end
    return sol
end
function Frame.solve(model)
    local ok,result=pcall(solve,model)
    if ok then return result end
    return nil,result
end

-- Single nodal -> diagram conversion. Integrate dV/ds=q, dM/ds=V.
-- At j, equilibrium gives V(L)=-V_j and M(L)=+M_j; N=-N_i=N_j.
local function nodal_to_diagram(el,s)
    local g=(el.qb-el.qa)/el.L
    return -el.f[1], el.f[2]+el.qa*s+g*s*s/2,
           -el.f[3]+el.f[2]*s+el.qa*s*s/2+g*s*s*s/6
end
-- Integrate EI*w^(4)=qa+g*s four times, imposing w=w'=0 at 0,L.
-- The integration constants (before dividing by EI) are
-- C3=-qa*L/2-3*g*L^2/20, C2=qa*L^2/12+g*L^3/30, C1=C0=0.
-- Factoring gives w_p=s^2*(L-s)^2*[5qa+g*(s+2L)]/(120EI), degree 5.
-- Return both w_p and its exact derivative; exposed for the particular test.
function Frame.load_particular(L,EI,qa,qb,s)
    if qa==qb then
        return qa*s^2*(L-s)^2/(24*EI),qa*s*(L-s)*(L-2*s)/(12*EI)
    end
    local g=(qb-qa)/L
    local h=5*qa+g*(s+2*L)
    return s^2*(L-s)^2*h/(120*EI),
           (2*s*(L-s)*(L-2*s)*h+g*s^2*(L-s)^2)/(120*EI)
end
local function displacement(el,s)
    local t=s/el.L
    local d,L=el.u,el.L
    local w=(1-3*t^2+2*t^3)*d[2]+L*(t-2*t^2+t^3)*d[3]
          +(3*t^2-2*t^3)*d[5]+L*(-t^2+t^3)*d[6]
          +Frame.load_particular(L,el.EI,el.qa,el.qb,s)
    local u=(1-t)*d[1]+t*d[4]
    return w,u
end
local function at_element(el,s)
    local N,V,M=nodal_to_diagram(el,s)
    local w,u=displacement(el,s)
    return {N=N,V=V,M=M,w=w,u=u}
end
local function member_result(sol,member)
    if not finite(member) or member%1~=0 or not sol.members[member] then error('invalid member index',0) end
    return sol.members[member]
end
function Frame.at(sol,member,s,side)
    local m=member_result(sol,member)
    if not finite(s) or s<0 or s>m.L then error('s outside member',0) end
    if side~=nil and side~='left' and side~='right' then error('invalid side',0) end
    if m.point_positions[s] and side==nil then error('side required at point or moment load node',0) end
    if s==0 and side=='left' or s==m.L and side=='right' then error('side outside member',0) end
    -- Compare to stored boundaries, never s +/- epsilon. Evaluate each limit
    -- at exactly 0 or L of the corresponding subelement.
    for _,el in ipairs(m.elements) do
        if s==el.x0 and side~='left' then return at_element(el,0) end
        if s==el.x1 and side~='right' then return at_element(el,el.L) end
        if s>el.x0 and s<el.x1 then return at_element(el,s-el.x0) end
    end
    error('no subelement at s',0)
end
-- Stable quadratic roots: Q=-0.5*(b+sign(b)*sqrt(D)); roots Q/a,c/Q.
-- Avoids subtracting nearly equal values for the small root. Scale first.
local function quadratic_roots(a,b,c)
    local scale=math.max(math.abs(a),math.abs(b),math.abs(c))
    if scale==0 then return {} end
    a,b,c=a/scale,b/scale,c/scale
    if a==0 then
        if b==0 then return {} end
        return {-c/b}
    end
    local disc=b*b-4*a*c
    if disc<0 then return {} end
    local sign=b<0 and -1 or 1
    local Q=-0.5*(b+sign*math.sqrt(disc))
    if Q==0 then return {-b/(2*a)} end
    return {Q/a,c/Q}
end
function Frame.moment_extrema(sol,member)
    local m=member_result(sol,member)
    local lo,xlo,hi,xhi=math.huge,0,-math.huge,0
    for _,el in ipairs(m.elements) do
        local candidates={0,el.L}
        -- Preserve P1A arithmetic for uniform loads; otherwise solve
        -- V(t)=V_i + qa*L*t + (qb-qa)*L*t^2/2, t=s/L.
        if el.qa==el.qb then
            if el.qa~=0 then
                local s=-el.f[2]/el.qa
                if s>0 and s<el.L then candidates[#candidates+1]=s end
            end
        else
            for _,t in ipairs(quadratic_roots((el.qb-el.qa)*el.L/2,el.qa*el.L,el.f[2])) do
                if t>0 and t<1 then candidates[#candidates+1]=t*el.L end
            end
        end
        for _,s in ipairs(candidates) do
            local _,_,v=nodal_to_diagram(el,s)
            if v<lo then lo=v;xlo=el.x0+s end
            if v>hi then hi=v;xhi=el.x0+s end
        end
    end
    return lo,xlo,hi,xhi
end
function Frame.deflection_extrema(sol,member)
    local m=member_result(sol,member)
    local best,xbest=0,0
    for _,el in ipairs(m.elements) do
        local d,L=el.u,el.L
        local function slope(s)
            local t=s/L
            local _,particular_slope=Frame.load_particular(L,el.EI,el.qa,el.qb,s)
            return (-6*t+6*t^2)*d[2]/L+(1-4*t+3*t^2)*d[3]
                 +(6*t-6*t^2)*d[5]/L+(-2*t+3*t^2)*d[6]
                 +particular_slope
        end
        local function candidate(s)
            local w=displacement(el,s)
            if math.abs(w)>math.abs(best) then best=w;xbest=el.x0+s end
        end
        candidate(0);candidate(L)
        local a,fa=0,slope(0)
        for i=1,64 do
            local b=L*i/64
            local fb=slope(b)
            if fa==0 then candidate(a) end
            if fb==0 then candidate(b) end
            if fa~=0 and fb~=0 and (fa<0)~=(fb<0) then
                local left,right,fleft=a,b,fa
                while right-left>1e-12*L do
                    local mid=(left+right)/2
                    local fm=slope(mid)
                    if fm==0 then left=mid;right=mid
                    elseif (fm<0)==(fleft<0) then left=mid;fleft=fm else right=mid end
                end
                candidate((left+right)/2)
            end
            a,fa=b,fb
        end
    end
    return best,xbest
end

return Frame
