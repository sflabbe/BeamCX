-- BeamCX independent benchmark P6A (generated).
-- BeamCX v0.4-P1C: pure Lua 5.1, static prismatic Euler-Bernoulli frames.
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
-- hinge_i/j release MEMBER rotations; reconstructed rotations drive recovery.
-- Thermal kappa_T=alphaT*dT/h: total curvature w''=M/EI-kappa_T.
-- Springs act in global DOFs; reactions include their force -k*u.
-- Global/projected member loads and axial thermal expansion are outside P1C.
-- solve/assemble return nil,message on failure; at/extrema reject bad queries.
-- moment_extrema and deflection_extrema return min, s_min, max, s_max.
Frame = {}

local PIVOT_TOL = 1e-12 -- |pivot| / original row maximum, after scaled pivoting.
local CHECK_TOL = 1e-8 -- relative to largest applied force or origin moment.
local MAX_NODES = 20 -- medido en CX CAS (BXBENCH): 20 nudos 2,7 s; 40 nudos 8,8 s; 60 nudos 20,7 s

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

-- Stable factored Hermite shapes, and derivatives with respect to s.
-- Work-conjugate pairs are (local uy, CCW rz); hence a concentrated
-- moment contributes +M*H'(a), while a transverse force contributes P*H(a).
local function hermite(L,s)
    local t=s/L
    local r=1-t
    return {r*r*(1+2*t),L*t*r*r,t*t*(3-2*t),-L*t*t*r},
           {-6*t*r/L,r*(1-3*t),6*t*r/L,t*(3*t-2)}
end
-- Retain low-order terms when loads nearly cancel an end shear. This is
-- essential for a point a few nanometres from an end: the remaining diagram
-- may be tiny compared to the support reaction, even without a short element.
local function compensated_add(sum,correction,value)
    local next_sum=sum+value
    local lost
    if math.abs(sum)>=math.abs(value) then lost=(sum-next_sum)+value
    else lost=(value-next_sum)+sum end
    return next_sum,correction+lost
end
local function add_component(fe,i,value)
    fe.correction=fe.correction or vector(6)
    fe[i],fe.correction[i]=compensated_add(fe[i],fe.correction[i],value)
end
local function add_transverse(fe,shape,factor)
    local map={2,3,5,6}
    for k=1,4 do add_component(fe,map[k],factor*shape[k]) end
end
local function add_line_load(fe,L,a,b,qa,qb)
    if a==0 and b==L then
        -- Integral H(s)^T*q(s) ds: uniform plus triangular contribution.
        -- Keep the closed full-length form (and uniform P1A arithmetic).
        if qa==qb then
            add_transverse(fe,{L/2,L^2/12,L/2,-L^2/12},qa)
        else
            add_transverse(fe,{L*(7*qa+3*qb)/20,L^2*(3*qa+2*qb)/60,
                               L*(3*qa+7*qb)/20,-L^2*(2*qa+3*qb)/60},1)
        end
    else
        -- H is cubic and q linear: 3-point Gauss-Legendre integrates the
        -- degree-4 product exactly, without subtracting close antiderivatives.
        local half=(b-a)/2
        local z=math.sqrt(3/5)
        local points,weights={-z,0,z},{5/9,8/9,5/9}
        for k=1,3 do
            local t=(points[k]+1)/2
            local shape=hermite(L,a+(b-a)*t)
            add_transverse(fe,shape,half*weights[k]*(qa+(qb-qa)*t))
        end
    end
end

-- Static release condensation, r = released local rotations, c = retained:
-- k*=k_cc-k_cr inv(k_rr) k_rc; f*=f_c-k_cr inv(k_rr) f_r.
-- Embed in six DOFs with exactly zero rows/columns at released rotations.
-- Keep the originals to reconstruct theta_r=inv(k_rr)*(f_r-k_rc*u_c).
local function condense(kl,fe,hinge_i,hinge_j)
    if not hinge_i and not hinge_j then return kl,fe end
    local r,c={},{}
    if hinge_i then r[#r+1]=3 end
    if hinge_j then r[#r+1]=6 end
    for i=1,6 do if not (i==3 and hinge_i or i==6 and hinge_j) then c[#c+1]=i end end
    local inv
    if #r==1 then inv={{1/kl[r[1]][r[1]]}}
    else
        local a,b,d=kl[3][3],kl[3][6],kl[6][6]
        local scale=math.max(math.abs(a),math.abs(b),math.abs(d))
        a,b,d=a/scale,b/scale,d/scale
        local den=(a*d-b*b)*scale
        inv={{d/den,-b/den},{-b/den,a/den}}
    end
    local ks,fs=zeros(6,6),vector(6)
    fs.correction=vector(6)
    for _,i in ipairs(c) do
        local value,low=fe[i],fe.correction[i]
        for a,ra in ipairs(r) do for b,rb in ipairs(r) do
            value,low=compensated_add(value,low,-kl[i][ra]*inv[a][b]*(fe[rb]+fe.correction[rb]))
        end end
        fs[i]=value+low;fs.correction[i]=(value-fs[i])+low
        for _,j in ipairs(c) do if j>=i then
            local v=kl[i][j]
            for a,ra in ipairs(r) do for b,rb in ipairs(r) do v=v-kl[i][ra]*inv[a][b]*kl[rb][j] end end
            -- Both releases leave ONLY the axial stiffness, exactly. Do not
            -- retain roundoff-sized transverse stiffness as a false restraint.
            if hinge_i and hinge_j and i~=1 and i~=4 then v=0 end
            ks[i][j]=v;ks[j][i]=v
        end end
    end
    return ks,fs,{r=r,c=c,inv=inv}
end
-- Zero-energy kinematics are independent of EA/EI. For released models, rank
-- the axial/chord-rotation constraints (row normalized, tolerance 1e-12).
-- This distinguishes a physical hinge mechanism from an ill-conditioned
-- stiffness with positive but disparate rigidities or spring constants.
local function check_hinge_kinematics(members,free,springs)
    local has_hinge=false
    for _,m in ipairs(members) do if m.hinge_i or m.hinge_j then has_hinge=true end end
    if not has_hinge then return end
    local rows={}
    local function add(full)
        local row,scale={},0
        for i,d in ipairs(free) do row[i]=full[d] or 0;scale=math.max(scale,math.abs(row[i])) end
        if scale>0 then
            for i=1,#free do row[i]=row[i]/scale end
            rows[#rows+1]=row
        end
    end
    for _,m in ipairs(members) do
        local i,j=3*m.i,3*m.j
        add({[i-2]=-m.c,[i-1]=-m.s,[j-2]=m.c,[j-1]=m.s})
        for _,endnode in ipairs{1,2} do
            if not (endnode==1 and m.hinge_i or endnode==2 and m.hinge_j) then
                local row={[i-2]=-m.s/m.L,[i-1]=m.c/m.L,[j-2]=m.s/m.L,[j-1]=-m.c/m.L}
                row[endnode==1 and i or j]=1;add(row)
            end
        end
    end
    for d in pairs(springs) do add({[d]=1}) end
    local rank,missing=0,nil
    for col=1,#free do
        local pivot,best=nil,0
        for i=rank+1,#rows do
            if math.abs(rows[i][col])>best then best=math.abs(rows[i][col]);pivot=i end
        end
        if best>1e-12 then
            rank=rank+1;rows[rank],rows[pivot]=rows[pivot],rows[rank]
            for i=rank+1,#rows do
                local factor=rows[i][col]/rows[rank][col]
                for j=col,#free do rows[i][j]=rows[i][j]-factor*rows[rank][j] end
            end
        else missing=missing or free[col] end
    end
    if rank<#free then error('mechanism: hinge kinematics at '..dof_label(missing),0) end
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
        fields(m,{i=true,j=true,EI=true,EA=true,hinge_i=true,hinge_j=true,alphaT=true,h=true},'member')
        for _,key in ipairs{'hinge_i','hinge_j'} do
            if m[key]~=nil and type(m[key])~='boolean' then error('invalid '..key,0) end
        end
        local ni,nj=node_index(m.i,nn),node_index(m.j,nn)
        local EI,EA=require_number(m.EI,'EI'),require_number(m.EA,'EA')
        local dx,dy=nodes[nj].x-nodes[ni].x,nodes[nj].y-nodes[ni].y
        local L=math.sqrt(dx*dx+dy*dy)
        if not finite(L) or L<=0 or EI<=0 or EA<=0 then error('invalid member geometry or rigidity',0) end
        members[i]={i=ni,j=nj,EI=EI,EA=EA,L=L,c=dx/L,s=dy/L,
                    q=0,kappa=0,hinge_i=m.hinge_i,hinge_j=m.hinge_j,alphaT=m.alphaT,h=m.h,
                    points={},moments={},distributed={},cuts={0,L},elements={}}
    end
    for _,load in ipairs(model.member_loads or {}) do
        if type(load)~='table' then error('invalid member load',0) end
        local kind=load.type
        -- Diagnose unsupported TYPE before inspecting its possible fields.
        if kind~='udl' and kind~='point' and kind~='dist' and kind~='moment' and kind~='dT' then
            error('unsupported member load type: '..tostring(kind),0)
        end
        if kind=='udl' then
            fields(load,{member=true,type=true,q=true},'udl load')
        elseif kind=='dist' then
            fields(load,{member=true,type=true,a=true,b=true,q1=true,q2=true},'dist load')
        elseif kind=='point' then
            fields(load,{member=true,type=true,a=true,P=true},'point load')
        elseif kind=='moment' then
            fields(load,{member=true,type=true,a=true,M=true},'moment load')
        else
            fields(load,{member=true,type=true,dT=true},'dT load')
        end
        local mi=load.member
        if not finite(mi) or mi%1~=0 or not members[mi] then error('invalid member index',0) end
        local m=members[mi]
        if kind=='udl' then
            m.q=m.q+require_number(load.q,'q')
        elseif kind=='dT' then
            if not finite(m.alphaT) or m.alphaT<=0 or not finite(m.h) or m.h<=0 then
                error('dT requires positive finite alphaT and h on member '..mi,0)
            end
            m.kappa=m.kappa+m.alphaT*require_number(load.dT,'dT')/m.h
        else
            local a=require_number(load.a,kind..' a')
            if a<0 or a>m.L then error(kind..' a outside member',0) end
            if kind=='dist' then
                local b=require_number(load.b,'dist b')
                if b<=a or b>m.L then error('invalid dist interval: require 0 <= a < b <= L',0) end
                m.distributed[#m.distributed+1]={left={a=a},right={a=b},
                    q1=require_number(load.q1,'q1'),q2=require_number(load.q2,'q2')}
            elseif kind=='point' then
                m.points[#m.points+1]={a=a,position=a,P=require_number(load.P,'P')}
            else
                m.moments[#m.moments+1]={a=a,M=require_number(load.M,'M')}
            end
        end
    end
    local elements={}
    for mi,m in ipairs(members) do
        -- Cuts are recovery coordinates only. No snapping, merging or nodes:
        -- one user member is always ONE element, independent of its loads.
        local positions={0,m.L}
        m.point_positions={}
        for _,p in ipairs(m.points) do
            positions[#positions+1]=p.a;m.point_positions[p.a]=true
        end
        for _,p in ipairs(m.moments) do
            positions[#positions+1]=p.a;m.point_positions[p.a]=true
        end
        for _,d in ipairs(m.distributed) do
            positions[#positions+1]=d.left.a;positions[#positions+1]=d.right.a
        end
        table.sort(positions)
        local cuts={}
        for _,a in ipairs(positions) do
            if cuts[#cuts]~=a then cuts[#cuts+1]=a end
        end
        m.cuts=cuts
        local L=m.L
        local fe=vector(6)
        add_line_load(fe,L,0,L,m.q,m.q)
        for _,d in ipairs(m.distributed) do
            add_line_load(fe,L,d.left.a,d.right.a,d.q1,d.q2)
        end
        for _,p in ipairs(m.points) do
            local H=hermite(L,p.a)
            -- Ni+Nj=1: form the large force as P minus the small force,
            -- keeping its low part instead of rounding P*(1-small) twice.
            if p.a<=L/2 then
                add_component(fe,2,p.P);add_component(fe,2,-p.P*H[3]);add_component(fe,5,p.P*H[3])
            else
                add_component(fe,5,p.P);add_component(fe,5,-p.P*H[1]);add_component(fe,2,p.P*H[1])
            end
            add_component(fe,3,p.P*H[2]);add_component(fe,6,p.P*H[4])
        end
        for _,p in ipairs(m.moments) do
            local _,derivative=hermite(L,p.a)
            add_transverse(fe,derivative,p.M)
        end
        -- M=EI*(w''+kappa_T). Integrating B^T*EI*kappa gives internal
        -- nodal moments (-EI*kappa,+EI*kappa). Since f=k*u-fe, the thermal
        -- consistent load has the opposite signs: fe[3]=+, fe[6]=-.
        add_component(fe,3,m.EI*m.kappa);add_component(fe,6,-m.EI*m.kappa)
        for k=1,6 do
            local value=fe[k]+fe.correction[k]
            fe.correction[k]=(fe[k]-value)+fe.correction[k];fe[k]=value
        end
        local ni,nj=m.i,m.j
        local T=Frame.transformation(m.c,m.s)
        local kl=Frame.local_k(L,m.EA,m.EI)
        local ks,fs,release=condense(kl,fe,m.hinge_i,m.hinge_j)
        local el={member=mi,L=L,EI=m.EI,T=T,kl=ks,kg=rotate_k(ks,T),fe=fs,
                  full_kl=kl,full_fe=fe,release=release,
                  map={3*ni-2,3*ni-1,3*ni,3*nj-2,3*nj-1,3*nj}}
        elements[mi]=el;m.elements={el}
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
        -- Member loads already enter F through their consistent vectors.
        -- Here tally their physical resultants independently for equilibrium.
        for _,p in ipairs(m.points) do
            local Fx,Fy=-m.s*p.P,m.c*p.P
            local n=nodes[m.i]
            local mom=(n.x+m.c*p.a)*Fy-(n.y+m.s*p.a)*Fx
            applied.Fx=applied.Fx+Fx;applied.Fy=applied.Fy+Fy;applied.Mz=applied.Mz+mom
            applied.scale=math.max(applied.scale,math.abs(Fx),math.abs(Fy),math.abs(mom))
        end
        for _,p in ipairs(m.moments) do
            applied.Mz=applied.Mz+p.M;applied.scale=math.max(applied.scale,math.abs(p.M))
        end
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
        -- Use original user positions; no geometric alteration of loads.
        line_resultant(0,m.L,m.q,m.q)
        for _,d in ipairs(m.distributed) do
            line_resultant(d.left.a,d.right.a,d.q1,d.q2)
        end
    end
    for _,el in ipairs(elements) do
        for i=1,6 do
            local d=el.map[i]
            for a=1,6 do F[d]=F[d]+el.T[a][i]*el.fe[a] end
            for j=1,6 do K[d][el.map[j]]=K[d][el.map[j]]+el.kg[i][j] end
        end
    end
    local fixed,prescribed,springs={},{},{}
    local spring_names={'kx','ky','kr'}
    local imposed_names={'dx','dy','drz'}
    for _,support in ipairs(model.supports or {}) do
        fields(support,{node=true,ux=true,uy=true,rz=true,kx=true,ky=true,kr=true,dx=true,dy=true,drz=true},'support')
        local ni=node_index(support.node,nn)
        for j,name in ipairs(dof_names) do
            local d=3*ni-3+j
            local v=support[name]
            if v~=nil and type(v)~='boolean' then error('unsupported prescribed displacement '..name,0) end
            if v then fixed[d]=true end
            local spring=support[spring_names[j]]
            if spring~=nil then
                if not finite(spring) or spring<=0 then error('spring must be positive and finite: '..dof_label(d),0) end
                springs[d]=(springs[d] or 0)+spring
            end
            local imposed=support[imposed_names[j]]
            if imposed~=nil then
                require_number(imposed,'prescribed displacement '..name)
                if prescribed[d]~=nil and prescribed[d]~=imposed then error('conflicting prescribed displacement '..dof_label(d),0) end
                prescribed[d]=imposed
            end
        end
    end
    for d,value in pairs(prescribed) do
        -- Zero defaults do not impose motion on an unrestricted DOF.
        if not fixed[d] and value~=0 then error('prescribed displacement on unrestricted '..dof_label(d),0) end
    end
    for d,k in pairs(springs) do
        if fixed[d] then error('spring and restraint on same DOF: '..dof_label(d),0) end
        K[d][d]=K[d][d]+k
    end
    local connected,rotation_active={},{}
    for _,m in ipairs(members) do
        connected[m.i]=true;connected[m.j]=true
        if not m.hinge_i then rotation_active[m.i]=true end
        if not m.hinge_j then rotation_active[m.j]=true end
    end
    -- A joint rotation disconnected by ALL incident releases is a redundant
    -- coordinate, not a physical mechanism. Fix it internally to zero; a
    -- nodal moment there has no load path and must instead fail as mechanism.
    -- Record these node indices in sol.inactive_rotations for inspection.
    local inactive_rotations={}
    for i=1,nn do
        local d=3*i
        if connected[i] and not rotation_active[i] and not fixed[d] and not springs[d] then
            if F[d]~=0 then error('mechanism: nodal moment at released '..dof_label(d),0) end
            fixed[d]=true;prescribed[d]=0;inactive_rotations[#inactive_rotations+1]=i
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
    check_hinge_kinematics(members,free,springs)
    return {nodes=nodes,members=members,elements=elements,K=K,F=F,ndof=nd,
            fixed=fixed,prescribed=prescribed,springs=springs,inactive_rotations=inactive_rotations,
            free=free,applied=applied}
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
        local rhs=F[free[i]]
        for d=1,sol.ndof do
            local value=sol.prescribed[d] or 0
            if sol.fixed[d] and value~=0 then rhs=rhs-K[free[i]][d]*value end
        end
        a[i][n+1]=rhs;scale[i]=rowmax
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
-- Exact polynomials on a RECOVERY span, x measured from its left cut.
-- w''=M/EI-kappa_T, integrated from preceding w and rotation. Horner evaluation
-- keeps all powers local to the span; no new stiffness matrix is introduced.
local function span_value(span,x)
    local V=span.V+x*(span.qa+x*span.g/2)
    local M=span.M+x*(span.V+x*(span.qa/2+x*span.g/6))
    local mechanical=span.M-span.EI*(span.kappa or 0)
    local theta=span.theta+x*(mechanical+x*(span.V/2+x*(span.qa/6+x*span.g/24)))/span.EI
    local w=span.w+x*(span.theta+x*(mechanical/2+x*(span.V/6+x*(span.qa/24+x*span.g/120)))/span.EI)
    return V,M,w,theta
end
-- The ONLY nodal -> diagram conversion. Starting at i: N=-Ni, V=Vi,
-- M=-Mi. Crossing a point adds P to V; crossing a CCW moment subtracts M0
-- from M. Integrate dV/ds=q, dM/ds=V, w''=M/EI-kappa_T between load cuts.
-- Loads AT i are crossed before the first span; loads AT j act outside its
-- left limit. Thus diagrams still describe the physical interior of a member.
local function nodal_to_diagram(el,m)
    local V,Vlow=el.f[2],el.f_correction[2]
    local M,Mlow=-el.f[3],-el.f_correction[3]
    local w,theta=el.u[2],el.u[3]
    el.N=-el.f[1];el.spans={}
    for k=1,#m.cuts-1 do
        local a,b=m.cuts[k],m.cuts[k+1]
        for _,p in ipairs(m.points) do if p.a==a then V,Vlow=compensated_add(V,Vlow,p.P) end end
        for _,p in ipairs(m.moments) do if p.a==a then M,Mlow=compensated_add(M,Mlow,-p.M) end end
        local qa,g=m.q,0
        for _,d in ipairs(m.distributed) do
            local da,db=d.left.a,d.right.a
            if a>=da and b<=db then
                local gradient=(d.q2-d.q1)/(db-da)
                qa=qa+d.q1+gradient*(a-da);g=g+gradient
            end
        end
        local span={x0=a,x1=b,L=b-a,EI=el.EI,V=V+Vlow,M=M+Mlow,w=w,theta=theta,qa=qa,g=g,kappa=m.kappa}
        el.spans[#el.spans+1]=span
        local h=span.L
        local _,_,next_w,next_theta=span_value(span,h)
        M,Mlow=compensated_add(M,Mlow,h*(Vlow+V+h*(qa/2+h*g/6)))
        V,Vlow=compensated_add(V,Vlow,h*(qa+h*g/2))
        w,theta=next_w,next_theta
    end
    return w,theta
end
-- Isolate stationary points on each span with the P1A 64-interval rule.
local function roots_on_span(span,value,visit)
    local a,fa=0,value(0)
    for k=1,64 do
        local b=span.L*k/64
        local fb=value(b)
        if fa==0 then visit(a) end
        if fb==0 then visit(b) end
        if fa~=0 and fb~=0 and (fa<0)~=(fb<0) then
            local left,right,fleft=a,b,fa
            while right-left>1e-12*span.L do
                local mid=(left+right)/2
                local fm=value(mid)
                if fm==0 then left=mid;right=mid
                elseif (fm<0)==(fleft<0) then left=mid;fleft=fm else right=mid end
            end
            visit((left+right)/2)
        end
        a,fa=b,fb
    end
end
local function compatibility(el,w_end,theta_end,member)
    -- End-force reference prevents a vanishing response from setting the
    -- entire error scale for loads approaching a rigid support.
    local L,EI=el.L,el.EI
    local F_ends=math.max(math.abs(el.f[2]),math.abs(el.f[5]),math.abs(el.f[3])/L,math.abs(el.f[6])/L)
    local F_loads=math.abs(member.q)*L+EI*math.abs(member.kappa)/L
    for _,p in ipairs(member.points) do F_loads=F_loads+math.abs(p.P) end
    for _,p in ipairs(member.moments) do F_loads=F_loads+math.abs(p.M)/L end
    for _,d in ipairs(member.distributed) do
        F_loads=F_loads+math.max(math.abs(d.q1),math.abs(d.q2))*(d.right.a-d.left.a)
    end
    local F=math.max(F_ends,F_loads)
    local raw_w_scale=math.max(math.abs(el.u[2]),math.abs(el.u[5]))
    local raw_theta_scale=math.max(math.abs(el.u[3]),math.abs(el.u[6]))
    local w_scale=math.max(math.abs(el.u[2]),math.abs(el.u[5]),1e-6*F*L^3/EI)
    local theta_scale=math.max(math.abs(el.u[3]),math.abs(el.u[6]),1e-6*F*L^2/EI)
    local function candidate(span,x)
        local _,_,w,theta=span_value(span,x)
        if not finite(w) or not finite(theta) then error('ill-conditioned: non-finite recovery',0) end
        w_scale=math.max(w_scale,math.abs(w));theta_scale=math.max(theta_scale,math.abs(theta))
        raw_w_scale=math.max(raw_w_scale,math.abs(w));raw_theta_scale=math.max(raw_theta_scale,math.abs(theta))
    end
    for _,span in ipairs(el.spans) do
        local function visit(x) candidate(span,x) end
        candidate(span,0);candidate(span,span.L)
        roots_on_span(span,function(x) local _,_,_,t=span_value(span,x);return t end,visit)
        roots_on_span(span,function(x) local _,M=span_value(span,x);return M-span.EI*(span.kappa or 0) end,visit)
    end
    local dw,dt=w_end-el.u[5],theta_end-el.u[6]
    local rw=w_scale==0 and (dw==0 and 0 or math.huge) or math.abs(dw)/w_scale
    local rt=theta_scale==0 and (dt==0 and 0 or math.huge) or math.abs(dt)/theta_scale
    local raw_w=raw_w_scale==0 and (dw==0 and 0 or math.huge) or math.abs(dw)/raw_w_scale
    local raw_theta=raw_theta_scale==0 and (dt==0 and 0 or math.huge) or math.abs(dt)/raw_theta_scale
    return {w_residual=dw,rz_residual=dt,w_scale=w_scale,rz_scale=theta_scale,
            relative=math.max(rw,rt),relative_raw=math.max(raw_w,raw_theta)}
end

local function solve(model)
    local sol=assemble(model)
    local uf=linear_solve(sol)
    local u=vector(sol.ndof)
    for d,value in pairs(sol.prescribed) do if sol.fixed[d] then u[d]=value end end
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
        -- Spring reaction is the force ON the structure, -k*u. K already
        -- includes +k on its diagonal for the free-DOF residual check.
        local rx=sol.fixed[3*i-2] and residual[3*i-2] or -(sol.springs[3*i-2] or 0)*u[3*i-2]
        local ry=sol.fixed[3*i-1] and residual[3*i-1] or -(sol.springs[3*i-1] or 0)*u[3*i-1]
        local mz=sol.fixed[3*i] and residual[3*i] or -(sol.springs[3*i] or 0)*u[3*i]
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
    sol.checks.compatibility_relative=0
    sol.checks.compatibility_members={}
    for _,el in ipairs(sol.elements) do
        el.u=vector(6);el.f=vector(6);el.f_correction=vector(6)
        for i=1,6 do for j=1,6 do el.u[i]=el.u[i]+el.T[i][j]*u[el.map[j]] end end
        if el.release then
            local release,rhs=el.release,{}
            for a,r in ipairs(release.r) do
                local value,low=el.full_fe[r],el.full_fe.correction[r]
                for _,c in ipairs(release.c) do value,low=compensated_add(value,low,-el.full_kl[r][c]*el.u[c]) end
                rhs[a]=value+low
            end
            for a,r in ipairs(release.r) do
                el.u[r]=0
                for b=1,#release.r do el.u[r]=el.u[r]+release.inv[a][b]*rhs[b] end
            end
        end
        -- Use CONDENSED k and fe for end forces; released moments are zero.
        -- Actual reconstructed member rotations above drive w and compatibility.
        -- Essential: subtract the consistent fixed-end load vector.
        for i=1,6 do
            local value,low=-el.fe[i],-el.fe.correction[i]
            for j=1,6 do value,low=compensated_add(value,low,el.kl[i][j]*el.u[j]) end
            el.f[i]=value+low;el.f_correction[i]=(value-el.f[i])+low
            if not finite(el.f[i]) then error('ill-conditioned: non-finite end forces',0) end
        end
        local w_end,theta_end=nodal_to_diagram(el,sol.members[el.member])
        local check=compatibility(el,w_end,theta_end,sol.members[el.member])
        sol.checks.compatibility_members[el.member]=check
        sol.checks.compatibility_relative=math.max(sol.checks.compatibility_relative,check.relative)
        if check.relative>CHECK_TOL then error(string.format('member compatibility failed: member %d (relative %.6g, dw %.6g, drz %.6g, w scale %.6g, rz scale %.6g)',el.member,check.relative,check.w_residual,check.rz_residual,check.w_scale,check.rz_scale),0) end
    end
    return sol
end
function Frame.solve(model)
    local ok,result=pcall(solve,model)
    if ok then return result end
    return nil,result
end

local function member_result(sol,member)
    if not finite(member) or member%1~=0 or not sol.members[member] then error('invalid member index',0) end
    return sol.members[member]
end
local function at_span(el,span,x,s)
    local V,M,w=span_value(span,x)
    local t=s/el.L
    return {N=el.N,V=V,M=M,w=w,u=(1-t)*el.u[1]+t*el.u[4]}
end
function Frame.at(sol,member,s,side)
    local m=member_result(sol,member)
    if not finite(s) or s< -1e-12*m.L or s>m.L*(1+1e-12) then error('s outside member',0) end
    s=math.max(0,math.min(m.L,s))
    if side~=nil and side~='left' and side~='right' then error('invalid side',0) end
    if m.point_positions[s] and side==nil then error('side required at point or moment load node',0) end
    if s==0 and side=='left' or s==m.L and side=='right' then error('side outside member',0) end
    local el=m.elements[1]
    -- Exact lateral limit at each recovery cut; never sample s +/- epsilon.
    for _,span in ipairs(el.spans) do
        if s==span.x0 and side~='left' then return at_span(el,span,0,s) end
        if s==span.x1 and side~='right' then return at_span(el,span,span.L,s) end
        if s>span.x0 and s<span.x1 then return at_span(el,span,s-span.x0,s) end
    end
    error('no recovery span at s',0)
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
    for _,span in ipairs(m.elements[1].spans) do
        local candidates={0,span.L}
        for _,t in ipairs(quadratic_roots(span.g*span.L^2/2,span.qa*span.L,span.V)) do
            if t>0 and t<1 then candidates[#candidates+1]=t*span.L end
        end
        for _,s in ipairs(candidates) do
            local _,v=span_value(span,s)
            if v<lo then lo=v;xlo=span.x0+s end
            if v>hi then hi=v;xhi=span.x0+s end
        end
    end
    return lo,xlo,hi,xhi
end
function Frame.deflection_extrema(sol,member)
    local m=member_result(sol,member)
    local lo,xlo,hi,xhi=math.huge,0,-math.huge,0
    for _,span in ipairs(m.elements[1].spans) do
        local function candidate(x)
            local _,_,w=span_value(span,x)
            if w<lo then lo=w;xlo=span.x0+x end
            if w>hi then hi=w;xhi=span.x0+x end
        end
        candidate(0);candidate(span.L)
        roots_on_span(span,function(x) local _,_,_,theta=span_value(span,x);return theta end,candidate)
    end
    return lo,xlo,hi,xhi
end

-- Superposition of already recovered solutions; no assembly or linear solve.
function Frame.combine(solutions,factors)
    local function incompatible(reason) error('incompatible solutions: '..reason,0) end
    local function copy(value,memo)
        if type(value)~='table' then return value end
        memo=memo or {}
        if memo[value] then return memo[value] end
        local out={};memo[value]=out
        for k,v in pairs(value) do out[k]=copy(v,memo) end
        return out
    end
    local function same(a,b)
        if type(a)~=type(b) then return false end
        if type(a)~='table' then return a==b end
        for k,v in pairs(a) do if not same(v,b[k]) then return false end end
        for k in pairs(b) do if a[k]==nil then return false end end
        return true
    end
    local function combine()
        if type(solutions)~='table' or type(factors)~='table' or #solutions==0 or #solutions~=#factors then
            incompatible('solution/factor counts')
        end
        local base=solutions[1]
        if type(base)~='table' or not base.u or not base.reactions or not base.members then incompatible('not a solved model') end
        for k=1,#solutions do
            local s=solutions[k]
            if not finite(factors[k]) then incompatible('non-finite factor') end
            if type(s)~='table' or not s.u or not s.reactions or not s.members then incompatible('not a solved model') end
            if not same(base.nodes,s.nodes) then incompatible('nodes') end
            for _,name in ipairs{'ndof','fixed','prescribed','springs','free','inactive_rotations'} do
                if not same(base[name],s[name]) then incompatible(name) end
            end
            if #base.members~=#s.members then incompatible('member count') end
            for i,m in ipairs(base.members) do
                local other=s.members[i]
                for _,key in ipairs{'i','j','L','c','s','EI','EA','hinge_i','hinge_j','alphaT','h','cuts'} do
                    if not same(m[key],other[key]) then incompatible('member '..i..' '..key) end
                end
                local a,b=m.elements[1],other.elements[1]
                if not a.spans or not b.spans or #a.spans~=#b.spans then incompatible('recovery spans') end
                for j,span in ipairs(a.spans) do
                    for _,key in ipairs{'x0','x1','L','EI'} do
                        if span[key]~=b.spans[j][key] then incompatible('recovery '..key) end
                    end
                end
            end
        end
        local out=copy(base)
        if #solutions==1 and factors[1]==1 then return out end
        local function sum(get)
            local value,low=0,0
            for k,s in ipairs(solutions) do value,low=compensated_add(value,low,factors[k]*get(s)) end
            value=value+low
            if not finite(value) then incompatible('non-finite combined response') end
            return value
        end
        local function vector_sum(target,get)
            for j=1,#target do
                target[j]=sum(function(s) return get(s)[j] end)
            end
            if target.correction then
                for j=1,#target.correction do
                    target.correction[j]=sum(function(s) return get(s).correction[j] end)
                end
            end
        end
        vector_sum(out.u,function(s) return s.u end)
        vector_sum(out.F,function(s) return s.F end)
        for d in pairs(out.prescribed) do out.prescribed[d]=sum(function(s) return s.prescribed[d] end) end
        for _,key in ipairs{'Fx','Fy','Mz'} do out.applied[key]=sum(function(s) return s.applied[key] end) end
        out.applied.scale=0
        for k,s in ipairs(solutions) do out.applied.scale=out.applied.scale+math.abs(factors[k])*s.applied.scale end
        for i,r in ipairs(out.reactions) do
            for _,key in ipairs{'Rx','Ry','Mz'} do r[key]=sum(function(s) return s.reactions[i][key] end) end
        end
        for i,m in ipairs(out.members) do
            m.q=sum(function(s) return s.members[i].q end)
            m.kappa=sum(function(s) return s.members[i].kappa end)
            m.points={};m.moments={};m.distributed={};m.point_positions={}
            for k,s in ipairs(solutions) do
                local source=s.members[i]
                for x in pairs(source.point_positions) do m.point_positions[x]=true end
                for _,list in ipairs{{'points','P'},{'moments','M'},{'distributed','q1','q2'}} do
                    for _,load in ipairs(source[list[1]]) do
                        local item=copy(load)
                        for j=2,#list do item[list[j]]=item[list[j]]*factors[k] end
                        m[list[1]][#m[list[1]]+1]=item
                    end
                end
            end
            local el=m.elements[1]
            for _,key in ipairs{'u','f','f_correction','fe','full_fe'} do
                vector_sum(el[key],function(s) return s.members[i].elements[1][key] end)
            end
            el.N=sum(function(s) return s.members[i].elements[1].N end)
            for j,span in ipairs(el.spans) do
                for _,key in ipairs{'V','M','w','theta','qa','g','kappa'} do
                    span[key]=sum(function(s) return s.members[i].elements[1].spans[j][key] end)
                end
            end
        end
        -- Source diagnostics certify their own solves, not this superposition.
        out.checks=nil
        return out
    end
    local ok,result=pcall(combine)
    if ok then return result end
    local message=tostring(result)
    if not string.find(message,'incompatible solutions: ',1,true) then message='incompatible solutions: malformed solution' end
    return nil,message
end


local BENCH_CORE_VERSION='v0.4-P1C'
local BENCH_CORE_SHA='4eeb568504db1b9471b8aef72934f8bf70d7f2dd8dccd47204f092feeb807e4b'

-- Continuous single-EI beams on Frame. No UI or CAS namespace (P5A).
-- m, kN, kNm, EI in kN*m^2; g/q and reported deflection positive DOWN.
ContinuousPreset = {MAX_SPANS=5}
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


-- Rectangular one-bay portal on Frame, calculation only (P6A).
-- m, kN, kNm; EIc/EIb in kN*m^2. q/P DOWN; H/w global RIGHT.
-- EA=1e6*EI/L^2 approximates negligible axial deformation for THIS preset.
-- The six analytical witnesses differ by order 1e-5, not a universal bound.
-- Frame signs: N tension positive, V=dM/ds, deflection local +y.
-- M>0 tensions local -y: global RIGHT for columns 1 (1->2) and 3 (4->3),
-- global DOWN for beam 2 (2->3). Both columns run from base to top.
PortalPreset={}
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

-- Independent CX benchmark; bundled by tools/build_bench.py, not build.py.
-- Official TI API: timer.getMilliSecCounter(), wraps at 2^32 ms.
-- https://education.ti.com/html/webhelp/EG_TINspireLUA/EN/content/libraries/timerlib/getmilliseccounter.htm
local Bench={version='P6A '..(BENCH_CORE_VERSION or 'Frame (unbundled)'),sha=BENCH_CORE_SHA or '',rows={}}
local function clock_ms()
    if timer and timer.getMilliSecCounter then return timer.getMilliSecCounter() end
    if os and os.clock then return os.clock()*1000 end -- PC reference only.
    error('No millisecond clock available',0)
end
Bench.clock_name=timer and timer.getMilliSecCounter and 'TI millisecond counter' or 'PC CPU os.clock'
local function continuous(spans,synthetic)
    local m={nodes={},members={},supports={},member_loads={}}
    for i=1,spans+1 do
        m.nodes[i]={x=6*(i-1),y=0};m.supports[i]={node=i,ux=i==1,uy=true}
        if i>1 then
            local id=i-1
            m.members[id]={i=id,j=i,EI=10000,EA=1e8}
            m.member_loads[#m.member_loads+1]={member=id,type='udl',q=-10}
            m.member_loads[#m.member_loads+1]={member=id,type='point',a=2,P=-12}
            if synthetic then m.member_loads[#m.member_loads+1]={member=id,type='moment',a=3,M=5} end
        end
    end
    return m
end
local gable={nodes={{x=0,y=0},{x=0,y=4},{x=3,y=6},{x=6,y=4},{x=6,y=0}},
    members={{i=1,j=2,EI=10000,EA=1e8},{i=2,j=3,EI=15000,EA=1e8,hinge_j=true},
             {i=3,j=4,EI=15000,EA=1e8,hinge_i=true},{i=5,j=4,EI=10000,EA=1e8}},
    supports={{node=1,ux=true,uy=true,rz=true},{node=5,ux=true,uy=true,rz=true}},
    member_loads={{member=2,type='udl',q=-10},{member=3,type='udl',q=-10}}}
Bench.cases={{name='simple q+P',model=continuous(1)},
             {name='5 spans q+P',model=continuous(5)},
             {name='gable hinges',model=gable},
             {name='synthetic 20',model=continuous(19,true)},
             {name='synthetic 40',model=continuous(39,true)},
             {name='synthetic 60',model=continuous(59,true)}}
-- P5A.1 complete envelopes: n+1 bases, exact ULS pieces and two SLS patterns.
for n=2,5 do
    local lengths={4,6,5,3,7}
    local spans={};for i=1,n do spans[i]=lengths[i] end
    Bench.cases[#Bench.cases+1]={name='continuous '..n..' env',
        preset={spans=spans,left='PIN',right='PIN',g=8,q=5,EI=20000}}
end
Bench.cases[#Bench.cases+1]={name='portal FIX q+P+H+w',
    portal={h=4,l=6,base='FIX',EIc=10000,EIb=15000,q=10,P=20,a=1.7,H=10,w=7}}
local function recover(sol)
    local checksum=0
    if sol.bases then
        local L=sol.supports[#sol.supports].position
        for sample=0,100 do
            local v=sol.envelope_at(L*sample/100)
            checksum=checksum+v.Mmax+v.Vmin
        end
        return checksum
    end
    sol=sol.frame or sol
    -- Exactly 101 queries across user members; include physical end limits.
    for sample=0,100 do
        local member=sample%#sol.members+1
        local s=sol.members[member].L*sample/100
        local v=Frame.at(sol,member,s,s==0 and 'right' or 'left')
        checksum=checksum+v.M+v.w
    end
    return checksum
end
function Bench.measure(index,step)
    local case=Bench.cases[index]
    local solved,solve_ms,recovery_ms,ns,nr=nil,0,0,0,0
    repeat
        local start=clock_ms()
        local sol,err
        if case.portal then sol,err=PortalPreset.solve(case.portal)
        elseif case.preset then sol,err=ContinuousPreset.solve(case.preset) else sol,err=Frame.solve(case.model) end
        if not sol and err=='model too large for handheld' then return {name=case.name,guard=err} end
        if not sol then error(case.name..': '..tostring(err),0) end
        solve_ms=solve_ms+(clock_ms()-start)%4294967296
        solved=sol;ns=ns+1
        if step then step() end
    until (ns>=3 and solve_ms>=200) or ns>=4096
    local checksum=0
    repeat
        local start=clock_ms()
        checksum=checksum+recover(solved)
        recovery_ms=recovery_ms+(clock_ms()-start)%4294967296
        nr=nr+1
        if step then step() end
    until (nr>=3 and recovery_ms>=200) or nr>=4096
    local frame=solved.frame or (solved.bases and solved.bases[1]) or solved
    return {name=case.name,nodes=#frame.nodes,dofs=frame.ndof,free=#frame.free,
        solve_ms=solve_ms/ns,recovery_ms=recovery_ms/nr,Nsolve=ns,Nrecover=nr,checksum=checksum}
end
function Bench.pc()
    for i=1,#Bench.cases do
        local r=Bench.measure(i)
        if r.guard then print('BENCH | '..r.name..' | '..r.guard) else
        print(string.format('BENCH | %s | %d | %d | %d | %.6f | %.6f | %d | %d',
            r.name,r.nodes,r.dofs,r.free,r.solve_ms,r.recovery_ms,r.Nsolve,r.Nrecover))
        end
    end
end
function Bench.start()
    if Bench.task then return end
    Bench.rows={};Bench.current=1;Bench.done=false;Bench.error=nil
    Bench.task=coroutine.create(function()
        for i=1,#Bench.cases do
            Bench.current=i;Bench.page=math.floor((i-1)/6)
            Bench.rows[i]=Bench.measure(i,coroutine.yield)
        end
        Bench.done=true
    end)
    timer.start(.01)
end
on=on or {}
function on.timer()
    if not Bench.task then return end
    local ok,err=coroutine.resume(Bench.task)
    if not ok then Bench.error=tostring(err) end
    if not ok or coroutine.status(Bench.task)=='dead' then timer.stop();Bench.task=nil end
    platform.window:invalidate()
end
function on.paint(gc)
    gc:setColorRGB(255,255,255);gc:fillRect(0,0,platform.window:width(),platform.window:height())
    gc:setColorRGB(0,0,0);gc:setFont('sansserif','r',8)
    local function text(s,x,y) gc:drawString(s,x,y,'top') end
    text('BXBENCH '..Bench.version..' '..string.sub(Bench.sha,1,8),4,3)
    text(Bench.clock_name..' / ms per operation',4,17)
    text('case',4,35);text('n/dof',105,35);text('solve',160,35);text('101 at',235,35)
    local first=(Bench.page or 0)*6+1
    for i=first,math.min(first+5,#Bench.cases) do
        local case=Bench.cases[i]
        local y=51+(i-first)*23
        text(case.name,4,y)
        local r=Bench.rows[i]
        if r and r.guard then text('guard 20 nodes',160,y)
        elseif r then
            text(r.nodes..'/'..r.dofs,105,y)
            text(string.format('%.2f',r.solve_ms),160,y)
            text(string.format('%.2f',r.recovery_ms),235,y)
            text('N solve/rec='..r.Nsolve..'/'..r.Nrecover,8,y+10)
        else text(i==Bench.current and 'running...' or '--',160,y) end
    end
    if Bench.error then text(string.sub(Bench.error,1,60),4,192)
    else text(Bench.done and 'Done. Arrows: page. env=full envelope.' or 'Measuring; painting is not timed.',4,192) end
end
function on.arrowRight()
    Bench.page=((Bench.page or 0)+1)%math.ceil(#Bench.cases/6)
    platform.window:invalidate()
end
function on.arrowLeft()
    Bench.page=((Bench.page or 0)+math.ceil(#Bench.cases/6)-1)%math.ceil(#Bench.cases/6)
    platform.window:invalidate()
end
if platform and platform.window and timer and timer.start then Bench.start() end
return Bench
