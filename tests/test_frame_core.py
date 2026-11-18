"""P1A + P1B oracles under real Lua: ctypes/5.4, or --lua lua5.1.

--write-lua PATH also exports the identical Lua test chunk for direct execution.
All beam comparisons use relative 1e-9 (absolute 1e-9 for expected zero),
frames 1e-4. Performance timings are informational CPU seconds on this PC.
"""
import argparse
import ctypes
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
core_source = (root / 'src/frame_core.lua').read_text()
assert core_source.rstrip().endswith('return Frame')
# Test-only access to assembly internals, injected in the module's lexical scope.
snapshot_source = core_source[:core_source.rfind('return Frame')] + r'''
return Frame,function(model)
    local ok,result=pcall(assemble,model)
    if ok then return result end
    return nil,result
end
'''
script = 'local Frame,assembly_snapshot=assert((loadstring or load)(' + json.dumps(snapshot_source) + '))()\n' + r'''
print('RUNTIME '.._VERSION)
local rows=0
local max_equilibrium,max_residual=0,0
local function eq(id,got,want,tol)
    tol=tol or 1e-9
    local err=math.abs(got-want)/(want==0 and 1 or math.abs(want))
    assert(got==got and err<=tol,id..': '..string.format('%.17g != %.17g (relative %.4g)',got,want,err))
    print(string.format('ORACLE | %s | %.17g | %.17g | %.6g',id,want,got,err))
    rows=rows+1
end
local function checks(s)
    max_equilibrium=math.max(max_equilibrium,s.checks.equilibrium_relative)
    max_residual=math.max(max_residual,s.checks.residual_relative)
    assert(s.checks.equilibrium_relative<=1e-8)
    assert(s.checks.residual_relative<=1e-8)
end
local function solve(m)
    local s,e=Frame.solve(m);assert(s,e);checks(s);return s
end
local function fail(m,fragment)
    local s,e=Frame.solve(m)
    assert(s==nil and type(e)=='string' and string.find(e,fragment,1,true),tostring(e))
    print('PASS failure: '..e)
    return e
end
local function beam(n,loaded,point,support)
    local m={nodes={},members={},supports={},member_loads={}}
    for i=1,n+1 do
        m.nodes[i]={x=6*(i-1),y=0}
        m.supports[i]={node=i,ux=i==1,uy=true,rz=false}
    end
    for i=1,n do
        m.members[i]={i=i,j=i+1,EA=1e8,EI=1e4}
        if loaded and loaded[i] then m.member_loads[#m.member_loads+1]={member=i,type='udl',q=-10} end
    end
    if point then m.member_loads[#m.member_loads+1]={member=1,type='point',a=point,P=-12} end
    if support=='cantilever' then
        m.supports={{node=1,ux=true,uy=true,rz=true}}
    elseif support=='fixed' then
        m.supports={{node=1,ux=true,uy=true,rz=true},{node=2,ux=true,uy=true,rz=true}}
    elseif support=='propped' then m.supports[1].rz=true end
    return m
end
local function portal(fixed)
    return {nodes={{x=0,y=0},{x=0,y=4},{x=6,y=4},{x=6,y=0}},
        members={{i=1,j=2,EI=10000,EA=1e8},{i=2,j=3,EI=15000,EA=1e8},
                 {i=4,j=3,EI=10000,EA=1e8}},
        supports={{node=1,ux=true,uy=true,rz=fixed},{node=4,ux=true,uy=true,rz=fixed}},
        member_loads={},nodal_loads={}}
end
-- E1: full fixed matrix transcribed from dc's E=210e9, A=.02, I=5e-4,
-- L=2, beam_theory='euler' fixture, including every zero and sign.
local expected={
 {2100000000,0,0,-2100000000,0,0},
 {0,157500000,157500000,0,-157500000,157500000},
 {0,157500000,210000000,0,-157500000,105000000},
 {-2100000000,0,0,2100000000,0,0},
 {0,-157500000,-157500000,0,157500000,-157500000},
 {0,157500000,105000000,0,-157500000,210000000}}
local k=Frame.local_k(2,4200000000,105000000)
local maxerr=0
for i=1,6 do for j=1,6 do
    maxerr=math.max(maxerr,math.abs(k[i][j]-expected[i][j])/math.max(1,math.abs(expected[i][j])))
end end
eq('E1 matrix max relative',maxerr,0,1e-12)
-- E2: independent rotation at 30 degrees, compared to assembled K.
local c,s=math.sqrt(3)/2,0.5
local T={{c,s,0,0,0,0},{-s,c,0,0,0,0},{0,0,1,0,0,0},
         {0,0,0,c,s,0},{0,0,0,-s,c,0},{0,0,0,0,0,1}}
local model={nodes={{x=0,y=0},{x=2*c,y=2*s}},members={{i=1,j=2,EA=4200000000,EI=105000000}}}
local asm=assert(assembly_snapshot(model))
maxerr=0
local TT=Frame.transformation(c,s)
for i=1,6 do for j=1,6 do
    assert(T[i][j]==TT[i][j])
    local v=0
    for a=1,6 do for b=1,6 do v=v+T[a][i]*expected[a][b]*T[b][j] end end
    maxerr=math.max(maxerr,math.abs(asm.K[i][j]-v)/math.max(1,math.abs(v)))
end end
eq('E2 rotation max relative',maxerr,0,1e-12)
-- E3: two rigid translations and rotation r=(-y,x,1), including free portal.
for mi,m in ipairs{model,portal(false)} do
    m.supports={}
    local a=assert(assembly_snapshot(m))
    local norm=0
    for i=1,a.ndof do
        local r=0;for j=1,a.ndof do r=r+math.abs(a.K[i][j]) end
        norm=math.max(norm,r)
    end
    for mode=1,3 do
        local r={}
        for i,node in ipairs(a.nodes) do
            r[3*i-2]=mode==1 and 1 or (mode==3 and -node.y or 0)
            r[3*i-1]=mode==2 and 1 or (mode==3 and node.x or 0)
            r[3*i]=mode==3 and 1 or 0
        end
        local resid=0
        for i=1,a.ndof do
            local v=0;for j=1,a.ndof do v=v+a.K[i][j]*r[j] end
            resid=math.max(resid,math.abs(v))
        end
        eq('E3 structure '..mi..' rigid mode '..mode,resid/norm,0)
    end
end
local sol=solve(beam(1,{true}))
eq('1 A',sol.reactions[1].Ry,30);eq('1 B',sol.reactions[2].Ry,30)
eq('1 M(3)',Frame.at(sol,1,3).M,45);eq('1 w(3)',Frame.at(sol,1,3).w,-0.016875)
local w,x=Frame.deflection_extrema(sol,1)
eq('1 w extreme',w,-0.016875);eq('1 xw',x,3)
sol=solve(beam(1,nil,2))
local l,r=Frame.at(sol,1,2,'left'),Frame.at(sol,1,2,'right')
eq('2 A',sol.reactions[1].Ry,8);eq('2 B',sol.reactions[2].Ry,4)
eq('2 M(a)',l.M,16);eq('2 w(a)',l.w,-12*2^2*4^2/(3*1e4*6))
eq('2 V left',l.V,8);eq('2 V right',r.V,-4);eq('2 V jump',l.V-r.V,12)
assert(l.V-r.V==12)
-- Shared nodal DOFs are continuous; force recovery needs no offset epsilon.
assert(l.w==r.w and l.u==r.u)
assert(not pcall(Frame.at,sol,1,2))
local lo,xlo,hi,xhi=Frame.moment_extrema(sol,1)
eq('2 Mmax',hi,16);eq('2 xMmax',xhi,2)
-- Exact deflection maximum for off-centre point: x=L-sqrt((L^2-a^2)/3).
w,x=Frame.deflection_extrema(sol,1)
local xp=6-math.sqrt(32/3)
eq('2 xw',x,xp)
eq('2 w extreme',w,-12*2*(6-xp)*(36-4-(6-xp)^2)/(6*6*1e4))
for _,kind in ipairs{'q','P'} do
    sol=solve(beam(1,kind=='q' and {true} or nil,kind=='P' and 6 or nil,'cantilever'))
    eq('9 '..kind..' w(L)',Frame.at(sol,1,6,kind=='P' and 'left' or nil).w,kind=='q' and -0.162 or -0.0864)
    eq('9 '..kind..' M(0)',Frame.at(sol,1,0).M,kind=='q' and -180 or -72)
    w,x=Frame.deflection_extrema(sol,1)
    eq('9 '..kind..' w extreme',w,kind=='q' and -0.162 or -0.0864);eq('9 '..kind..' xw',x,6)
end
sol=solve(beam(1,{true},nil,'fixed'))
eq('10 q M(0)',Frame.at(sol,1,0).M,-30);eq('10 q M(L)',Frame.at(sol,1,6).M,-30)
eq('10 q M(3)',Frame.at(sol,1,3).M,15);eq('10 q w(3)',Frame.at(sol,1,3).w,-0.003375)
sol=solve(beam(1,nil,2,'fixed'))
eq('10 P M(0)',Frame.at(sol,1,0).M,-12*2*4^2/36)
eq('10 P M(L)',Frame.at(sol,1,6).M,-12*2^2*4/36)
sol=solve(beam(1,{true},nil,'propped'))
eq('13 M(0)',Frame.at(sol,1,0).M,-45);eq('13 B',sol.reactions[2].Ry,22.5)
lo,xlo,hi,xhi=Frame.moment_extrema(sol,1)
eq('13 Mmax',hi,25.3125);eq('13 xMmax',xhi,3.75)
local cases={
 {14,2,{true,true},-0.125,9/128},
 {15,2,{true,false},-1/16,49/512},
 {16,3,{true,true,true},-0.1,0.08},
 {17,3,{true,false,true},-1/20,0.10125},
 {18,3,{false,true,false},-1/20,nil},
 {19,3,{true,true,false},-7/60,nil}}
for _,case in ipairs(cases) do
    local id,n,loads=case[1],case[2],case[3]
    sol=solve(beam(n,loads))
    eq(id..' MB',Frame.at(sol,1,6).M,case[4]*360)
    if case[5] then
        lo,xlo,hi,xhi=Frame.moment_extrema(sol,1)
        eq(id..' Mmax span1',hi,case[5]*360)
    end
    if id==14 then eq('14 A',sol.reactions[1].Ry,.375*60);eq('14 B',sol.reactions[2].Ry,1.25*60) end
    if id==16 then
        eq('16 MC',Frame.at(sol,2,6).M,-.1*360)
        lo,xlo,hi,xhi=Frame.moment_extrema(sol,2);eq('16 Mmax span2',hi,.025*360)
        eq('16 A',sol.reactions[1].Ry,.4*60);eq('16 B',sol.reactions[2].Ry,1.1*60)
    end
    if id==18 then lo,xlo,hi,xhi=Frame.moment_extrema(sol,2);eq('18 Mmax span2',hi,.075*360) end
end
local m=beam(1,{true});m.supports[1].ux=false
local err=fail(m,'mechanism');assert(string.find(err,'ux',1,true))
sol=solve(beam(1,{true}));eq('22b real beam w',Frame.at(sol,1,3).w,-.016875)
sol=solve(beam(1,nil,1e-7))
eq('23 merged A',sol.reactions[1].Ry,12*(6-1e-7)/6);eq('23 merged B',sol.reactions[2].Ry,12*1e-7/6)
assert(#sol.nodes==2 and sol.members[1].points[1].position==1e-7)
sol=solve(beam(1,nil,.006))
local a,b=.006,5.994
assert(#sol.nodes==2)
eq('23 near A',sol.reactions[1].Ry,12*b/6)
eq('23 near B',sol.reactions[2].Ry,12*a/6)
eq('23 near M(a)',Frame.at(sol,1,a,'left').M,12*a*b/6)
eq('23 near w(a)',Frame.at(sol,1,a,'right').w,-12*a^2*b^2/(3*1e4*6))
-- Kleinlogel magnitudes; EA is FINITE. Relative tolerance 1e-4.
for id=24,28 do
    m=portal(id>=26)
    if id==24 or id==26 then m.member_loads={{member=2,type='udl',q=-10}}
    elseif id==27 then m.member_loads={{member=2,type='point',a=3,P=-10}}
    else m.nodal_loads={{node=2,Fx=10}} end
    sol=solve(m)
    if id==24 then
        eq('24 |H left|',math.abs(sol.reactions[1].Rx),4.5,1e-4)
        eq('24 |H right|',math.abs(sol.reactions[4].Rx),4.5,1e-4)
    elseif id==25 then
        eq('25 |corner left|',math.abs(Frame.at(sol,2,0).M),20,1e-4)
        eq('25 |corner right|',math.abs(Frame.at(sol,2,6).M),20,1e-4)
    elseif id==26 then
        eq('26 |base left|',math.abs(sol.reactions[1].Mz),10,1e-4)
        eq('26 |corner left|',math.abs(Frame.at(sol,2,0).M),20,1e-4)
        eq('26 |base right|',math.abs(sol.reactions[4].Mz),10,1e-4)
        eq('26 |corner right|',math.abs(Frame.at(sol,2,6).M),20,1e-4)
    elseif id==27 then eq('27 |base|',math.abs(sol.reactions[1].Mz),2.5,1e-4)
    else eq('28 |base|',math.abs(sol.reactions[1].Mz),80/7,1e-4) end
end
-- P1A contract boundaries and mechanics not covered by the scalar oracles.
for _,kind in ipairs{'axial','unknown'} do
    m=beam(1);m.member_loads={{member=1,type=kind}}
    assert(fail(m,'unsupported member load type: '..kind)=='unsupported member load type: '..kind)
end
for _,field in ipairs{'releases','springs','settlements','dT'} do
    m=beam(1);m.members[1][field]={};fail(m,'unsupported member field')
end
m=beam(1);m.supports[1].uy=.01;fail(m,'unsupported prescribed displacement')
-- Exactly inactive free rz, and a nonzero but small relative pivot.
m={nodes={{x=0,y=0},{x=6,y=0},{x=9,y=0}},members={{i=1,j=2,EA=1e8,EI=1e4}},
 supports={{node=1,ux=true,uy=true},{node=2,uy=true},{node=3,ux=true,uy=true}}}
err=fail(m,'mechanism');assert(string.find(err,'rz',1,true))
m={nodes={{x=0,y=0},{x=1,y=0},{x=2,y=0}},
 members={{i=1,j=2,EA=1e8,EI=1e4},{i=2,j=3,EA=1e-6,EI=1e-10}},
 supports={{node=3,ux=true,uy=true,rz=true}}}
fail(m,'ill-conditioned')
-- Axial tension and displacement on a 30-degree cantilever, nodal loads only.
m={nodes={{x=0,y=0},{x=6*c,y=6*s}},members={{i=1,j=2,EA=1e8,EI=1e4}},
 supports={{node=1,ux=true,uy=true,rz=true}},nodal_loads={{node=2,Fx=12*c,Fy=12*s}}}
sol=solve(m)
eq('axial N',Frame.at(sol,1,3).N,12);eq('axial u',Frame.at(sol,1,3).u,36/1e8)
eq('axial w',Frame.at(sol,1,3).w,0)
-- Close but distinct interior points, repeated udl and nodal loads;
-- original user coordinates and records must remain unchanged.
m=beam(1,{true},2)
m.member_loads[3]={member=1,type='point',a=2+3e-6,P=-3}
m.member_loads[4]={member=1,type='point',a=2+7e-6,P=-2}
m.member_loads[5]={member=1,type='udl',q=2}
m.nodal_loads={{node=2,Fy=1},{node=2,Fy=2}}
sol=solve(m);assert(#sol.nodes==2 and #sol.members[1].elements==1)
assert(m.member_loads[3].a==2+3e-6 and m.member_loads[3].node==nil)
l,r=Frame.at(sol,1,2,'left'),Frame.at(sol,1,2,'right')
eq('merged interior V jump',l.V-r.V,12)
-- Points near ends retain their exact positions; no extra nodes.
sol=solve(beam(1,nil,6-1e-7));assert(#sol.nodes==2)
eq('23 merged right B',sol.reactions[2].Ry,12*(6-1e-7)/6)
local aa=assert(assembly_snapshot(beam(1,nil,6e-6)));assert(#aa.nodes==2)
assert(pcall(Frame.at,sol,1,6));assert(not pcall(Frame.at,sol,1,6,'right'))
assert(not pcall(Frame.at,sol,1,-1));assert(not pcall(Frame.at,sol,1,3,'bad'))
-- Reversed member orientation preserves physical nodal solutions.
m=beam(1,{true});m.members[1].i=2;m.members[1].j=1;m.member_loads[1].q=10
sol=solve(m);eq('reversed global Ry',sol.reactions[1].Ry,30)
eq('reversed local w',Frame.at(sol,1,3).w,.016875)
-- All supports prescribed / unloaded zero response.
sol=solve(beam(1,nil,nil,'fixed'));w,x=Frame.deflection_extrema(sol,1);eq('zero w',w,0)
-- Performance: three spans with interior points, then the 20-model-node CX guard.
m=beam(3,{true,true,true})
for i=1,3 do m.member_loads[#m.member_loads+1]={member=i,type='point',a=2,P=-12} end
local t=os.clock();sol=solve(m);local elapsed=os.clock()-t
print(string.format('PERF 3 spans: nodes=%d dofs=%d free=%d seconds=%.6f',#sol.nodes,sol.ndof,#sol.free,elapsed))
m={nodes={},members={},supports={},member_loads={}}
for i=1,20 do
    m.nodes[i]={x=(i-1)*6,y=0}
    m.supports[i]={node=i,ux=i==1,uy=true}
    if i>1 then
        m.members[i-1]={i=i-1,j=i,EA=1e8,EI=1e4}
        m.member_loads[#m.member_loads+1]={member=i-1,type='point',a=2,P=-12}
    end
end
m.member_loads[#m.member_loads+1]={member=1,type='point',a=4,P=-12}
t=os.clock();sol=solve(m);elapsed=os.clock()-t
assert(#sol.nodes==20)
print(string.format('PERF 20 nodes: nodes=%d dofs=%d free=%d seconds=%.6f',#sol.nodes,sol.ndof,#sol.free,elapsed))
m.member_loads[#m.member_loads+1]={member=2,type='point',a=4,P=-12}
m.nodes[21]={x=120,y=0}
assert(fail(m,'model too large for handheld')=='model too large for handheld')
print('PASS handheld guard: 20 nodes solve; 21 rejected with exact message')
print(string.format('CHECKS max equilibrium_relative=%.6g residual_relative=%.6g tolerance=1e-8',max_equilibrium,max_residual))
print('PASS P1A: '..rows..' numeric oracles, contracts, checks and performance')
-- P1B: append-only numeric oracles; the 85 P1A numeric checks above remain.
assert(rows==85)
local p1a_rows=rows
local function linear_beam(q1,q2,support,a,b)
    local m=beam(1,nil,nil,support)
    m.member_loads={{member=1,type='dist',a=a or 0,b=b or 6,q1=q1,q2=q2}}
    return m
end
sol=solve(linear_beam(0,-10))
eq('3 A',sol.reactions[1].Ry,10);eq('3 B',sol.reactions[2].Ry,20)
lo,xlo,hi,xhi=Frame.moment_extrema(sol,1)
eq('3 Mmax',hi,360/(9*math.sqrt(3)));eq('3 xMmax',xhi,6/math.sqrt(3))
-- Exact simply-supported solution, rather than the rounded prompt decimals:
-- EI*w/(q0*L^4)=-t^5/120+t^3/36-7t/360;
-- w'=0 gives t=sqrt(1-sqrt(8/15)).
local tw=math.sqrt(1-math.sqrt(8/15))
w,x=Frame.deflection_extrema(sol,1)
eq('3 wmin',w,10*6^4/1e4*(-tw^5/120+tw^3/36-7*tw/360))
eq('3 xwmin',x,6*tw)
local triangular=sol
m=linear_beam(0,-10,nil,0,3)
m.member_loads[2]={member=1,type='dist',a=3,b=6,q1=-10,q2=0}
sol=solve(m)
eq('4 A',sol.reactions[1].Ry,15);eq('4 B',sol.reactions[2].Ry,15)
eq('4 M(3)',Frame.at(sol,1,3).M,30);eq('4 w(3)',Frame.at(sol,1,3).w,-.0108)
w,x=Frame.deflection_extrema(sol,1)
eq('4 wmin',w,-.0108);eq('4 xwmin',x,3)
sol=solve(linear_beam(-10,-10,nil,0,2.5))
local RA=10*2.5*(6-2.5/2)/6
lo,xlo,hi,xhi=Frame.moment_extrema(sol,1)
eq('5 A',sol.reactions[1].Ry,RA);eq('5 B',sol.reactions[2].Ry,25-RA)
eq('5 Mmax',hi,RA^2/20);eq('5 xMmax',xhi,RA/10)
sol=solve(linear_beam(-10,-20))
eq('5b A',sol.reactions[1].Ry,40);eq('5b B',sol.reactions[2].Ry,50)
local uniform=solve(beam(1,{true}))
for i=0,6 do
    local v=Frame.at(sol,1,i)
    local v1,v3=Frame.at(uniform,1,i),Frame.at(triangular,1,i)
    eq('5b M('..i..')',v.M,v1.M+v3.M)
    eq('5b w('..i..')',v.w,v1.w+v3.w)
end
m=beam(1);m.member_loads={{member=1,type='moment',a=0,M=30}}
sol=solve(m)
eq('6 A',sol.reactions[1].Ry,5);eq('6 B',sol.reactions[2].Ry,-5)
eq('6 M(0 right)',Frame.at(sol,1,0,'right').M,-30)
eq('6 M(L)',Frame.at(sol,1,6).M,0)
eq('6 theta i',sol.u[3],.006);eq('6 theta j',sol.u[6],-.003)
m.member_loads[1].a=3
sol=solve(m)
eq('7 A',sol.reactions[1].Ry,5);eq('7 B',sol.reactions[2].Ry,-5)
l,r=Frame.at(sol,1,3,'left'),Frame.at(sol,1,3,'right')
eq('7 M left',l.M,15);eq('7 M right',r.M,-15)
eq('7 M jump',l.M-r.M,30);assert(l.M-r.M==30)
eq('7 w(3)',l.w,0);assert(l.w==r.w)
assert(not pcall(Frame.at,sol,1,3))
lo,xlo,hi,xhi=Frame.moment_extrema(sol,1)
eq('7 Mmin',lo,-15);eq('7 xmin',xlo,3)
eq('7 Mmax',hi,15);eq('7 xmax',xhi,3)
sol=solve(linear_beam(0,-10,'fixed'))
eq('7b M(0)',Frame.at(sol,1,0).M,-12);eq('7b M(L)',Frame.at(sol,1,6).M,-18)
-- Triangular consistent loads, with their NODAL signs, independently fixed.
local fe=sol.elements[1].fe
eq('C4 fe Vi',fe[2],-9);eq('C4 fe Mi',fe[3],-12)
eq('C4 fe Vj',fe[5],-21);eq('C4 fe Mj',fe[6],18)
sol=solve(linear_beam(-10,0,'cantilever'))
eq('7c M(0)',Frame.at(sol,1,0).M,-60);eq('7c w(L)',Frame.at(sol,1,6).w,-.0432)
sol=solve(linear_beam(0,-10,'cantilever'))
eq('7d M(0)',Frame.at(sol,1,0).M,-120);eq('7d w(L)',Frame.at(sol,1,6).w,-.1188)
local function inclined(c,s,loads)
    return {nodes={{x=0,y=0},{x=6*c,y=6*s}},members={{i=1,j=2,EI=1e4,EA=1e8}},
        supports={{node=1,ux=true,uy=true,rz=true}},member_loads=loads}
end
for _,angle in ipairs{0,30,90,135} do
    local c,s=math.cos(angle*math.pi/180),math.sin(angle*math.pi/180)
    m=inclined(c,s,{{member=1,type='udl',q=-10}})
    sol=solve(m)
    eq('8a '..angle..' w(L)',Frame.at(sol,1,sol.members[1].L).w,-.162)
    eq('8a '..angle..' M(0)',Frame.at(sol,1,0).M,-180)
    eq('8a '..angle..' Rx',sol.reactions[1].Rx,-60*s)
    eq('8a '..angle..' Ry',sol.reactions[1].Ry,60*c)
    eq('8a '..angle..' Mz',sol.reactions[1].Mz,180)
end
m=inclined(math.sqrt(3)/2,.5,{{member=1,type='point',a=6,P=-12},
                            {member=1,type='moment',a=6,M=30}})
sol=solve(m)
eq('8b w(L)',Frame.at(sol,1,6,'left').w,-.0864+30*36/(2*1e4))
eq('8b M(0)',Frame.at(sol,1,0).M,-72+30)
eq('8b Rx',sol.reactions[1].Rx,-6)
eq('8b Ry',sol.reactions[1].Ry,12*math.sqrt(3)/2)
eq('8b Mz',sol.reactions[1].Mz,42)
-- Also rotate a PARTIAL dist, including its partition, to all four angles.
local horizontal=solve(linear_beam(-10,-20,'cantilever',1,4))
for _,angle in ipairs{0,30,90,135} do
    local c,s=math.cos(angle*math.pi/180),math.sin(angle*math.pi/180)
    sol=solve(inclined(c,s,{{member=1,type='dist',a=1,b=4,q1=-10,q2=-20}}))
    eq('8 dist '..angle..' w(L)',Frame.at(sol,1,6).w,Frame.at(horizontal,1,6).w)
    eq('8 dist '..angle..' M(0)',Frame.at(sol,1,0).M,Frame.at(horizontal,1,0).M)
    eq('8 dist '..angle..' Rx',sol.reactions[1].Rx,-45*s)
    eq('8 dist '..angle..' Ry',sol.reactions[1].Ry,45*c)
    eq('8 dist '..angle..' Mz',sol.reactions[1].Mz,120)
end
m=portal(false);m.member_loads={{member=1,type='udl',q=-10}}
sol=solve(m)
eq('8c |H right|',math.abs(sol.reactions[4].Rx),11,1e-4)
eq('8c |H left|',math.abs(sol.reactions[1].Rx),29,1e-4)
eq('8c |Ry left|',math.abs(sol.reactions[1].Ry),40/3,1e-4)
eq('8c |Ry right|',math.abs(sol.reactions[4].Ry),40/3,1e-4)
-- C1: type takes precedence over fields that belong to a future load type.
m=beam(1);m.member_loads={{member=1,type='foo',anything=1}}
assert(fail(m,'unsupported member load type: foo')=='unsupported member load type: foo')
for _,load in ipairs{
    {type='udl',q=-10,other=1},{type='dist',a=0,b=6,q1=-10,q2=0,other=1},
    {type='point',a=2,P=-12,other=1},{type='moment',a=3,M=30,other=1}} do
    load.member=1;m=beam(1);m.member_loads={load};fail(m,'field')
end
-- C2: invalid intervals/positions and non-finite inputs must never solve.
for _,interval in ipairs{{2,2},{3,2},{-1,2},{0,7},{7,8},{0,-1}} do
    fail(linear_beam(-10,0,nil,interval[1],interval[2]),'dist')
end
for _,bad in ipairs{math.huge,-math.huge,0/0} do
    for _,field in ipairs{'a','b','q1','q2'} do
        m=linear_beam(-10,0);m.member_loads[1][field]=bad;fail(m,'invalid')
    end
    m=beam(1);m.member_loads={{member=1,type='moment',a=3,M=bad}};fail(m,'invalid')
    m.member_loads[1]={member=1,type='moment',a=bad,M=30};fail(m,'invalid')
end
for _,a in ipairs{-1,7} do
    m=beam(1);m.member_loads={{member=1,type='moment',a=a,M=30}};fail(m,'outside member')
end
-- C4: recover the PARTICULAR polynomial independently by six-point Lagrange
-- interpolation; differentiate the recovered coefficients analytically.
-- Frame.at on an equivalent fixed-fixed member supplies the physical polynomial.
for index,pair in ipairs{{-3,-11},{11,-2},{-10,-10}} do
    local L,EI=6,1e4
    local particular=solve(linear_beam(pair[1],pair[2],'fixed'))
    local coeff={}
    for i=0,5 do coeff[i]=0 end
    for j=0,5 do
        local basis,degree,denom={[0]=1},0,1
        for k=0,5 do if k~=j then
            local next_basis={}
            for p=0,degree+1 do next_basis[p]=0 end
            for p=0,degree do
                next_basis[p]=next_basis[p]-k/5*basis[p]
                next_basis[p+1]=next_basis[p+1]+basis[p]
            end
            basis=next_basis;degree=degree+1;denom=denom*(j-k)/5
        end end
        local wp=Frame.at(particular,1,L*j/5).w
        for p=0,5 do coeff[p]=coeff[p]+wp*basis[p]/denom end
    end
    for j=0,4 do
        local t=j/4
        eq('C4 '..index..' EI*w4 t='..t,EI*(24*coeff[4]+120*coeff[5]*t)/L^4,
            pair[1]+(pair[2]-pair[1])*t)
    end
    for _,s in ipairs{0,L} do
        local wp,dwp=Frame.at(particular,1,s).w,0
        for p=1,5 do dwp=dwp+p*coeff[p]*(s/L)^(p-1)/L end
        eq('C4 '..index..' w('..s..')',wp,0);eq('C4 '..index..' dw('..s..')',dwp,0)
        assert(particular.u[s==0 and 2 or 5]==0 and particular.u[s==0 and 3 or 6]==0)
    end
end
-- Two real shear roots, sign-changing q and ZERO resultant (finite couple).
sol=solve(linear_beam(-10,10))
lo,xlo,hi,xhi=Frame.moment_extrema(sol,1)
eq('roots Mmin',lo,-10*math.sqrt(3)/3);eq('roots xmin',xlo,3+math.sqrt(3))
eq('roots Mmax',hi,10*math.sqrt(3)/3);eq('roots xmax',xhi,3-math.sqrt(3))
-- Stable small root: V(s)=epsilon-s-s^2/6 on a cantilever.
m=linear_beam(-1,-3,'cantilever');m.nodal_loads={{node=2,Fy=12-1e-4}}
sol=solve(m);lo,xlo,hi,xhi=Frame.moment_extrema(sol,1)
eq('roots small xmax',xhi,6e-4/(3+math.sqrt(9+6e-4)))
-- Overlapping partial distributions + udl + point + moment. Compare exact
-- superposition across distinct partitions, and continuity at dist borders.
local loads={{member=1,type='dist',a=1,b=5,q1=-10,q2=-20},
             {member=1,type='dist',a=2,b=4,q1=5,q2=-5},
             {member=1,type='udl',q=-2},{member=1,type='point',a=3,P=-12},
             {member=1,type='moment',a=3,M=30}}
m=beam(1);m.member_loads=loads;sol=solve(m)
local singles={}
for _,load in ipairs(loads) do
    local single=beam(1);single.member_loads={load};singles[#singles+1]=solve(single)
end
for _,s in ipairs{.5,1,2,3,4,5,5.5} do
    local got=Frame.at(sol,1,s,'right')
    for _,field in ipairs{'V','M','w'} do
        local want=0
        for _,single in ipairs(singles) do want=want+Frame.at(single,1,s,'right')[field] end
        eq('overlap '..field..' s='..s,got[field],want)
    end
end
for _,s in ipairs{1,2,4,5} do
    assert(pcall(Frame.at,sol,1,s))
    l,r=Frame.at(sol,1,s,'left'),Frame.at(sol,1,s,'right')
    eq('border V s='..s,l.V,r.V);eq('border M s='..s,l.M,r.M)
end
-- Moments/dist boundaries remain distinct recovery cuts and do not mutate input.
m=linear_beam(-10,-20,nil,1e-7,3+3e-6)
m.member_loads[2]={member=1,type='moment',a=3,M=30}
sol=solve(m)
assert(#sol.nodes==2 and #sol.members[1].cuts==5 and sol.members[1].cuts[3]==3)
assert(m.member_loads[1].a==1e-7 and m.member_loads[1].b==3+3e-6)
assert(not pcall(Frame.at,sol,1,3))
-- This narrow interval retains its nonzero physical load without snapping.
sol=solve(linear_beam(-10,-20,nil,2,2+1e-7))
local short_length=(2+1e-7)-2
local short_B=(2*15*short_length+short_length^2*50/6)/6
eq('collapsed dist A',sol.reactions[1].Ry,15*short_length-short_B);eq('collapsed dist B',sol.reactions[2].Ry,short_B)
-- Loaded partition/recovery regression at the 20-model-node CX guard.
m={nodes={},members={},supports={},member_loads={}}
for i=1,20 do
    m.nodes[i]={x=(i-1)*6,y=0};m.supports[i]={node=i,ux=i==1,uy=true}
    if i>1 then
        m.members[i-1]={i=i-1,j=i,EA=1e8,EI=1e4}
        m.member_loads[#m.member_loads+1]={member=i-1,type='dist',a=2,b=6,q1=-10,q2=-20}
        m.member_loads[#m.member_loads+1]={member=i-1,type='moment',a=2,M=30}
    end
end
m.member_loads[#m.member_loads+1]={member=1,type='moment',a=4,M=30}
t=os.clock();sol=solve(m);elapsed=os.clock()-t;assert(#sol.nodes==20)
print(string.format('PERF P1B 20 nodes: nodes=%d dofs=%d free=%d seconds=%.6f',#sol.nodes,sol.ndof,#sol.free,elapsed))
print(string.format('CHECKS P1B max equilibrium_relative=%.6g residual_relative=%.6g tolerance=1e-8',max_equilibrium,max_residual))
print('PASS P1B: '..(rows-p1a_rows)..' new numeric oracles; 85 P1A preserved')
'''


# The supplied fixture is retained byte-for-byte; JSON is converted to Lua
# literals by the Python harness, so target Lua needs no JSON dependency.
def lua_literal(value):
    if value is None:
        return 'nil'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, list):
        return '{' + ','.join(lua_literal(v) for v in value) + '}'
    return '{' + ','.join('[' + lua_literal(k) + ']=' + lua_literal(v)
                          for k, v in value.items()) + '}'


fixture = json.loads((root / 'tests/fixtures/frame_core_hp_regressions.json').read_text())
script += '\nlocal hp_cases=' + lua_literal(fixture['cases']) + '\n' + r'''
-- P1B.1: 255 legacy numeric checks precede these regressions. Six expected
-- values tied to the deleted merge were updated with explicit user approval.
assert(rows==255)
local function solve_compatible(model)
    local s=solve(model)
    assert(s.ndof==3*#model.nodes and #s.nodes==#model.nodes)
    assert(#s.elements==#model.members)
    assert(s.checks.compatibility_relative<=1e-8)
    return s
end
for _,case in ipairs(hp_cases) do
    local s=solve_compatible(case.model)
    assert(s.checks.equilibrium_relative<=1e-11)
    local rscale,uscale=0,0
    for _,r in pairs(case.reference.reactions) do
        for _,v in pairs(r) do rscale=math.max(rscale,math.abs(tonumber(v))) end
    end
    for _,u in pairs(case.reference.displacements) do
        for _,v in pairs(u) do uscale=math.max(uscale,math.abs(tonumber(v))) end
    end
    local function hp_value(field,got,want,scale)
        want=tonumber(want)
        local error=math.abs(got-want)/scale
        assert(error<=1e-8,case.name..' '..field..': '..error)
        print(string.format('HP | %s | %s | %.17g | %.17g | %.6g',case.name,field,want,got,error))
    end
    for node,r in pairs(case.reference.reactions) do
        for _,name in ipairs{'Rx','Ry','Mz'} do
            hp_value('node '..node..' '..name,s.reactions[tonumber(node)][name],r[name],rscale)
        end
    end
    for node,u in pairs(case.reference.displacements) do
        for dof,name in ipairs{'ux','uy','rz'} do
            hp_value('node '..node..' '..name,s.u[3*tonumber(node)-3+dof],u[name],uscale)
        end
    end
    print(string.format('HP_CHECKS | %s | equilibrium=%.17g | residual=%.17g | compatibility=%.17g',
        case.name,s.checks.equilibrium_relative,s.checks.residual_relative,s.checks.compatibility_relative))
end
-- Close loads: the 1 mm gaps create only polynomial spans, never extra DOFs.
local close_loads={{member=1,type='dist',a=0,b=2.999,q1=-10,q2=-10},
                   {member=1,type='point',a=3,P=-12},
                   {member=1,type='moment',a=3.001,M=30}}
m=beam(1);m.member_loads=close_loads
sol=solve_compatible(m);assert(sol.checks.equilibrium_relative<=1e-11)
local separate={}
for _,load in ipairs(close_loads) do
    local one=beam(1);one.member_loads={load};separate[#separate+1]=solve_compatible(one)
end
for _,s in ipairs{3,3.001} do for _,side in ipairs{'left','right'} do
    local want=0
    for _,single in ipairs(separate) do want=want+Frame.at(single,1,s,side).M end
    eq('P1B.1 close M '..s..' '..side,Frame.at(sol,1,s,side).M,want)
end end
print(string.format('CLOSE_CHECKS equilibrium=%.17g compatibility=%.17g',sol.checks.equilibrium_relative,sol.checks.compatibility_relative))
m=beam(1)
for i=1,4 do
    m.member_loads[#m.member_loads+1]={member=1,type='point',a=.5*i,P=-12}
    m.member_loads[#m.member_loads+1]={member=1,type='moment',a=3+.1*i,M=30}
    m.member_loads[#m.member_loads+1]={member=1,type='dist',a=.1*i,b=1+.2*i,q1=-10,q2=-20}
end
sol=solve_compatible(m);assert(#m.member_loads==12 and sol.ndof==6)
sol=solve_compatible(beam(3,{true,true,true}));assert(sol.ndof==12)
sol=solve_compatible(beam(1,{true},nil,'cantilever'))
local edge,rounded=Frame.at(sol,1,6),Frame.at(sol,1,6*(1+1e-14))
for _,field in ipairs{'N','V','M','w','u'} do eq('P1B.1 edge '..field,rounded[field],edge[field]) end
local left_edge=Frame.at(sol,1,-6e-14)
eq('P1B.1 left edge w',left_edge.w,Frame.at(sol,1,0).w)
assert(not pcall(Frame.at,sol,1,6*1.01))
assert(not pcall(Frame.at,sol,1,-6e-10))
-- The compatibility guard is independent of assembled equilibrium: a
-- deliberately inconsistent EI/stiffness must fail rather than return data.
local original_k=Frame.local_k
Frame.local_k=function(L,EA,EI) return original_k(L,EA,2*EI) end
local no_result,compat_error=Frame.solve(beam(1,{true}))
Frame.local_k=original_k
assert(no_result==nil and string.find(compat_error,'member compatibility failed',1,true))
-- 20 MODEL nodes, several loads per member: P1A-like and P1B-like cases.
for _,kind in ipairs{'P1A','P1B'} do
    m={nodes={},members={},supports={},member_loads={}}
    for i=1,20 do
        m.nodes[i]={x=6*(i-1),y=0};m.supports[i]={node=i,ux=i==1,uy=true}
        if i>1 then
            local member=i-1
            m.members[member]={i=i-1,j=i,EA=1e8,EI=1e4}
            if kind=='P1A' then
                m.member_loads[#m.member_loads+1]={member=member,type='udl',q=-10}
                m.member_loads[#m.member_loads+1]={member=member,type='point',a=2,P=-12}
                m.member_loads[#m.member_loads+1]={member=member,type='point',a=4,P=-6}
            else
                m.member_loads[#m.member_loads+1]={member=member,type='dist',a=2,b=6,q1=-10,q2=-20}
                m.member_loads[#m.member_loads+1]={member=member,type='moment',a=2.001,M=30}
                m.member_loads[#m.member_loads+1]={member=member,type='point',a=3,P=-12}
            end
        end
    end
    t=os.clock();sol=solve_compatible(m);elapsed=os.clock()-t
    assert(sol.ndof==60)
    print(string.format('PERF P1B.1 %s 20 model nodes: nodes=%d dofs=%d free=%d seconds=%.6f compatibility=%.6g',
        kind,#sol.nodes,sol.ndof,#sol.free,elapsed,sol.checks.compatibility_relative))
end
print('PASS P1B.1: two HP fixtures, close loads, model-only DOFs, endpoint tolerance and compatibility')
'''


script += r'''
-- P1C: all 265 preceding oracle rows retain their expected values.
assert(rows==265)
local p1c_start=rows
local function checked(model)
    local s=solve(model)
    assert(s.checks.compatibility_relative<=1e-8)
    assert(s.ndof==3*#model.nodes)
    return s
end
local function gerber(right_release)
    return {nodes={{x=0,y=0},{x=4,y=0},{x=10,y=0}},
        members={{i=1,j=2,EA=1e8,EI=1e4,hinge_j=not right_release},
                 {i=2,j=3,EA=1e8,EI=1e4,hinge_i=right_release}},
        supports={{node=1,ux=true,uy=true,rz=true},{node=3,uy=true}},
        member_loads={{member=1,type='udl',q=-10},{member=2,type='udl',q=-10}}}
end
local reference_gerber=checked(gerber(false))
for _,right_release in ipairs{false,true} do
    local id=right_release and '20b' or '20'
    sol=checked(gerber(right_release))
    eq('P1C '..id..' M(4 left)',Frame.at(sol,1,4).M,0)
    eq('P1C '..id..' M(4 right)',Frame.at(sol,2,0).M,0)
    eq('P1C '..id..' Ry(10)',sol.reactions[3].Ry,30)
    eq('P1C '..id..' M(0)',Frame.at(sol,1,0).M,-200)
    eq('P1C '..id..' Ry(0)',sol.reactions[1].Ry,70)
    if right_release then
        for member,L in ipairs{4,6} do for k=1,5 do
            local s=L*k/6
            eq('P1C 20b w member '..member..' s='..s,Frame.at(sol,member,s).w,Frame.at(reference_gerber,member,s).w)
        end end
    end
end
m={nodes={{x=0,y=0},{x=3,y=0},{x=6,y=0}},
   members={{i=1,j=2,EI=1e4,EA=1e8,hinge_j=true},{i=2,j=3,EI=1e4,EA=1e8,hinge_i=true}},
   supports={{node=1,ux=true,uy=true},{node=3,uy=true}},member_loads={{member=1,type='udl',q=-10}}}
fail(m,'mechanism') -- 29: genuine internal hinge mechanism, not an unused rz.
local function three_hinged()
    return {nodes={{x=0,y=0},{x=0,y=4},{x=3,y=4},{x=6,y=4},{x=6,y=0}},
        members={{i=1,j=2,EI=1e4,EA=1e8},{i=2,j=3,EI=15000,EA=1e8,hinge_j=true},
                 {i=3,j=4,EI=15000,EA=1e8,hinge_i=true},{i=5,j=4,EI=1e4,EA=1e8}},
        supports={{node=1,ux=true,uy=true},{node=5,ux=true,uy=true}},
        member_loads={{member=2,type='udl',q=-10},{member=3,type='udl',q=-10}}}
end
m=three_hinged();sol=checked(m)
eq('P1C 30 |H left|',math.abs(sol.reactions[1].Rx),11.25,1e-4)
eq('P1C 30 |H right|',math.abs(sol.reactions[5].Rx),11.25,1e-4)
eq('P1C 30 M key left',Frame.at(sol,2,3).M,0)
eq('P1C 30 M key right',Frame.at(sol,3,0).M,0)
eq('P1C 30 |corner left|',math.abs(Frame.at(sol,2,0).M),45,1e-4)
eq('P1C 30 |corner right|',math.abs(Frame.at(sol,3,3).M),45,1e-4)
assert(sol.inactive_rotations[1]==3 and sol.u[9]==0)
m.nodal_loads={{node=3,M=5}}
err=fail(m,'mechanism');assert(string.find(err,'node 3',1,true)) -- 30b.
local function pendular(vertical)
    local m=portal(false)
    m.supports[1].rz=true
    m.members[2].hinge_i=true;m.members[2].hinge_j=true
    m.members[3].hinge_i=true;m.members[3].hinge_j=true
    m.nodal_loads=vertical and {{node=3,Fy=-20}} or {{node=2,Fx=10}}
    return m
end
sol=checked(pendular(false))
eq('P1C 31 |base left|',math.abs(sol.reactions[1].Mz),40,1e-4)
for _,member in ipairs{2,3} do for _,s in ipairs{0,2,4} do
    eq('P1C 31 M member '..member..' s='..s,Frame.at(sol,member,s).M,0)
    eq('P1C 31 V member '..member..' s='..s,Frame.at(sol,member,s).V,0)
end end
assert(sol.u[9]==0 and sol.u[12]==0)
sol=checked(pendular(true))
eq('P1C 31b N pendular',Frame.at(sol,3,2).N,-20)
eq('P1C 31b M pendular',Frame.at(sol,3,2).M,0)
m=beam(1,{true},nil,'fixed');m.members[1].hinge_i=true;m.members[1].hinge_j=true
sol=checked(m)
eq('P1C 32 M(0)',Frame.at(sol,1,0).M,0);eq('P1C 32 M(L)',Frame.at(sol,1,6).M,0)
eq('P1C 32 M(3)',Frame.at(sol,1,3).M,45);eq('P1C 32 w(3)',Frame.at(sol,1,3).w,-.016875)
eq('P1C 32 theta member i',sol.elements[1].u[3],-.009)
eq('P1C 32 theta member j',sol.elements[1].u[6],.009)
assert(sol.elements[1].f[3]==0 and sol.elements[1].f[6]==0 and sol.u[3]==0 and sol.u[6]==0)
-- 21: midspan vertical spring; reaction sign is force ON the structure.
m={nodes={{x=0,y=0},{x=3,y=0},{x=6,y=0}},
   members={{i=1,j=2,EI=1e4,EA=1e8},{i=2,j=3,EI=1e4,EA=1e8}},
   supports={{node=1,ux=true,uy=true},{node=3,uy=true},{node=2,ky=5000}},
   member_loads={{member=1,type='udl',q=-10},{member=2,type='udl',q=-10}}}
sol=checked(m)
local spring_R=.016875/(1/5000+6^3/(48*1e4))
eq('P1C 21 spring Ry',sol.reactions[2].Ry,spring_R)
eq('P1C 21 A',sol.reactions[1].Ry,(60-spring_R)/2)
eq('P1C 21 B',sol.reactions[3].Ry,(60-spring_R)/2)
eq('P1C 21 sum Ry',sol.reactions[1].Ry+sol.reactions[2].Ry+sol.reactions[3].Ry,60)
eq('P1C 21 spring displacement',sol.u[5],-spring_R/5000)
for _,kr in ipairs{5000,1e12,1e-6} do
    m=beam(1,{true});m.supports[1].kr=kr
    sol=checked(m)
    local moment=Frame.at(sol,1,0).M
    if kr==5000 then
        eq('P1C 21b M(0)',moment,-22.5)
        eq('P1C 21b spring Mz',sol.reactions[1].Mz,22.5)
    elseif kr==1e12 then eq('P1C 21c stiff M(0)',moment,-45,1e-6)
    else eq('P1C 21c soft M(0)',moment,0,1e-6);assert(math.abs(moment)<1e-6) end
end
-- Settlements: positive Delta below denotes the magnitude of dy=-Delta.
m=beam(1,nil,nil,'fixed');m.supports[2].dy=-.01
sol=checked(m)
eq('P1C 11 M(0)',Frame.at(sol,1,0).M,-6*1e4*.01/36)
eq('P1C 11 M(L)',Frame.at(sol,1,6).M,6*1e4*.01/36)
eq('P1C 11 Ry i',sol.reactions[1].Ry,12*1e4*.01/216)
eq('P1C 11 Ry j',sol.reactions[2].Ry,-12*1e4*.01/216)
eq('P1C 11 w(L)',Frame.at(sol,1,6).w,-.01)
m=beam(1,nil,nil,'propped');m.supports[2].dy=-.01
sol=checked(m)
eq('P1C 13s M(0)',Frame.at(sol,1,0).M,-3*1e4*.01/36)
eq('P1C 13s Ry i',sol.reactions[1].Ry,3*1e4*.01/216)
eq('P1C 13s Ry j',sol.reactions[2].Ry,-3*1e4*.01/216)
m=beam(1);m.supports[2].dy=-.01
sol=checked(m)
eq('P1C 11b Ry i',sol.reactions[1].Ry,0);eq('P1C 11b Ry j',sol.reactions[2].Ry,0)
for _,s in ipairs{0,1.5,3,4.5,6} do
    eq('P1C 11b M s='..s,Frame.at(sol,1,s).M,0)
    eq('P1C 11b w s='..s,Frame.at(sol,1,s).w,-.01*s/6)
end
local function thermal(support,q,hinges)
    local m=beam(1,q and {true} or nil,nil,support)
    m.members[1].alphaT=1.2e-5;m.members[1].h=.3
    m.members[1].hinge_i=hinges;m.members[1].hinge_j=hinges
    m.member_loads[#m.member_loads+1]={member=1,type='dT',dT=20}
    return m
end
local temp_pin=checked(thermal())
eq('P1C 8 thermal w(3)',Frame.at(temp_pin,1,3).w,.0036)
eq('P1C 8 thermal Ry i',temp_pin.reactions[1].Ry,0)
eq('P1C 8 thermal Ry j',temp_pin.reactions[2].Ry,0)
for _,s in ipairs{0,1.5,3,4.5,6} do eq('P1C 8 thermal M s='..s,Frame.at(temp_pin,1,s).M,0) end
sol=checked(thermal('cantilever'))
eq('P1C 8b thermal w(L)',Frame.at(sol,1,6).w,-.0144)
eq('P1C 8b thermal M(3)',Frame.at(sol,1,3).M,0)
sol=checked(thermal('fixed'))
for _,s in ipairs{0,1.5,3,4.5,6} do
    eq('P1C 12 thermal M s='..s,Frame.at(sol,1,s).M,8)
    eq('P1C 12 thermal w s='..s,Frame.at(sol,1,s).w,0)
end
eq('P1C 12 thermal Ry i',sol.reactions[1].Ry,0)
eq('P1C 12 thermal Ry j',sol.reactions[2].Ry,0)
eq('P1C 12 thermal Mz i',sol.reactions[1].Mz,-8)
eq('P1C 12 thermal Mz j',sol.reactions[2].Mz,8)
sol=checked(thermal('propped'))
eq('P1C 12b thermal M(0)',Frame.at(sol,1,0).M,12)
eq('P1C 12b thermal M(L)',Frame.at(sol,1,6).M,0)
local temp_q=checked(thermal(nil,true))
local q_only=checked(beam(1,{true}))
for s=0,6 do
    eq('P1C 12c M s='..s,Frame.at(temp_q,1,s).M,Frame.at(temp_pin,1,s).M+Frame.at(q_only,1,s).M)
    eq('P1C 12c w s='..s,Frame.at(temp_q,1,s).w,Frame.at(temp_pin,1,s).w+Frame.at(q_only,1,s).w)
end
-- Thermal load must be condensed with the mechanical loads.
sol=checked(thermal('fixed',true,true))
eq('P1C thermal hinges M(0)',Frame.at(sol,1,0).M,0)
eq('P1C thermal hinges M(L)',Frame.at(sol,1,6).M,0)
eq('P1C thermal hinges w(3)',Frame.at(sol,1,3).w,-.016875+.0036)
-- kx and imposed dx/drz complete the three global components.
m=beam(1,nil,nil,'fixed');m.supports[2].ux=false;m.supports[2].kx=1000
m.nodal_loads={{node=2,Fx=10}}
sol=checked(m)
local axial_u=10/(1e8/6+1000)
eq('P1C kx ux',sol.u[4],axial_u)
eq('P1C kx reaction j',sol.reactions[2].Rx,-1000*axial_u)
eq('P1C kx reaction i',sol.reactions[1].Rx,-1e8/6*axial_u)
m=beam(1,nil,nil,'fixed');m.supports[2].dx=1e-5
sol=checked(m)
eq('P1C dx axial N',Frame.at(sol,1,3).N,1e8*1e-5/6)
eq('P1C dx reaction i',sol.reactions[1].Rx,-1e8*1e-5/6)
m=beam(1,nil,nil,'fixed');m.supports[2].drz=.001
sol=checked(m)
eq('P1C drz M(0)',Frame.at(sol,1,0).M,-2*1e4*.001/6)
eq('P1C drz M(L)',Frame.at(sol,1,6).M,4*1e4*.001/6)
-- A disconnected nodal rotation CAN carry a moment through its own kr.
m=beam(1);m.members[1].hinge_i=true;m.members[1].hinge_j=true
m.supports[2].kr=1000;m.nodal_loads={{node=2,M=5}}
sol=checked(m)
eq('P1C released joint spring rz',sol.u[6],.005)
eq('P1C released joint spring Mz',sol.reactions[2].Mz,-5)
eq('P1C released joint spring member M',Frame.at(sol,1,3).M,0)
-- Validation: dT is supported, but requires positive finite alphaT AND h.
for _,properties in ipairs{{},{alphaT=1.2e-5},{h=.3},{alphaT=0,h=.3},
                           {alphaT=-1,h=.3},{alphaT=1.2e-5,h=0},{alphaT=1.2e-5,h=-1},
                           {alphaT=math.huge,h=.3},{alphaT=1.2e-5,h=0/0}} do
    m=beam(1)
    m.members[1].alphaT=properties.alphaT;m.members[1].h=properties.h
    m.member_loads={{member=1,type='dT',dT=20}}
    fail(m,'dT requires positive finite alphaT and h')
end
for _,key in ipairs{'kx','ky','kr'} do
    for _,value in ipairs{0,-1,math.huge,-math.huge,0/0} do
        m=beam(1);m.supports[2][key]=value;fail(m,'spring must be positive and finite')
    end
    m=beam(1,nil,nil,'fixed');m.supports[1][key]=1000
    fail(m,'spring and restraint on same DOF')
end
for _,key in ipairs{'dx','dy','drz'} do
    m=beam(1);m.supports[3]={node=2,[key]=.01}
    if key=='dy' then m.supports[2].uy=false end
    fail(m,'prescribed displacement on unrestricted')
end
m=thermal();m.member_loads[1].dT=math.huge;fail(m,'invalid dT')
m=beam(1);m.members[1].hinge_i=1;fail(m,'invalid hinge_i')
-- Performance: 20 model nodes, Gerber-like one-ended releases and positive
-- vertical springs at all interior nodes; springs stabilize every released span.
m={nodes={},members={},supports={},member_loads={}}
for i=1,20 do
    m.nodes[i]={x=6*(i-1),y=0}
    if i==1 then m.supports[#m.supports+1]={node=i,ux=true,uy=true,rz=true}
    elseif i==20 then m.supports[#m.supports+1]={node=i,uy=true}
    else m.supports[#m.supports+1]={node=i,ky=5000} end
    if i>1 then
        m.members[i-1]={i=i-1,j=i,EI=1e4,EA=1e8,hinge_j=true}
        m.member_loads[#m.member_loads+1]={member=i-1,type='udl',q=-10}
    end
end
t=os.clock();sol=checked(m);elapsed=os.clock()-t
print(string.format('PERF P1C hinges+springs: nodes=%d dofs=%d free=%d seconds=%.6f',#sol.nodes,sol.ndof,#sol.free,elapsed))
print(string.format('CHECKS P1C equilibrium=%.17g residual=%.17g compatibility=%.17g',
    sol.checks.equilibrium_relative,sol.checks.residual_relative,sol.checks.compatibility_relative))
print('PASS P1C: '..(rows-p1c_start)..' new numeric rows; 265 previous rows unchanged; contracts and performance')
'''


# P1C.1: the mutation exists only in the harness. Restore the original two
# scale initializers to build the pre-patch control, then alter ONLY span EI.
core_source = (root / 'src/frame_core.lua').read_text()
scale_start = core_source.index('    -- End-force reference prevents')
scale_end = core_source.index('    local function candidate(span,x)', scale_start)
pre_patch_source = (core_source[:scale_start] +
                    '    local w_scale=math.max(math.abs(el.u[2]),math.abs(el.u[5]))\n' +
                    '    local theta_scale=math.max(math.abs(el.u[3]),math.abs(el.u[6]))\n' +
                    '    local raw_w_scale=w_scale;local raw_theta_scale=theta_scale\n' +
                    core_source[scale_end:])
span_marker = 'EI=el.EI,V='
assert core_source.count(span_marker) == pre_patch_source.count(span_marker) == 1
mutate = lambda source: source.replace(span_marker, 'EI=el.EI*(1+1e-6),V=', 1)
script += '\nlocal pre_patch_mutated=' + json.dumps(mutate(pre_patch_source))
assert core_source.count('return V,M,w,theta') == 1
script += '\nlocal large_near_mutation=' + json.dumps(core_source.replace('return V,M,w,theta', 'return V,M,w+1e-10,theta', 1))
script += '\nlocal post_patch_mutated=' + json.dumps(mutate(core_source)) + '\n' + r'''
assert(rows==394)
local function end_model(support,kind,a,from_right)
    local left={node=1,ux=true,uy=true,rz=false}
    local right={node=2,uy=true,rz=false}
    if support==1 then left.rz=true -- FIX-PIN
    elseif support==2 then right.rz=true -- PIN-FIX
    elseif support==3 then left.rz=true;right.rz=true;right.ux=true
    elseif support==4 then left.rz=true;right.uy=false
    elseif support==5 then left.uy=false;right.ux=true;right.rz=true end
    local load
    if kind==1 then load={member=1,type='point',a=a,P=-12}
    elseif kind==2 then load={member=1,type='moment',a=a,M=30}
    else load={member=1,type='dist',a=from_right and a or 0,b=from_right and 6 or a,q1=-10,q2=-20} end
    return {nodes={{x=0,y=0},{x=6,y=0}},members={{i=1,j=2,EI=10000,EA=1e8}},
            supports={left,right},member_loads={load}}
end
for _,a in ipairs{1e-7,1e-5,1e-3} do
    local minimum=assert(Frame.solve(end_model(1,1,a,false)))
    local ratio=(18-a)/12
    local normalized=minimum.reactions[2].Ry/(12*(a/6)^2)
    assert(math.abs(normalized-ratio)<=1e-10*ratio)
    local RB=12*(a/6)^2*ratio
    -- P is positive down: clamp reaction Mz=P*a-RB*L;
    -- the diagram convention is the opposite, M(0)=-Mz.
    local expected_M=-12*a+RB*6
    local moment=Frame.at(minimum,1,0).M
    assert(math.abs(moment/expected_M-1)<=1e-10)
    print(string.format('P1C.1 CLOSED a=%.17g RB_relative=%.17g M_relative=%.17g',
        a,math.abs(normalized/ratio-1),math.abs(moment/expected_M-1)))
end
local large=assert((loadstring or load)(large_near_mutation,'large near-support mutation'))()
local rejected,message=large.solve(end_model(1,1,1e-7,false))
assert(rejected==nil and string.find(message,'member compatibility failed',1,true))
print('P1C.1 LARGE MUTATION: rejected near support')
local total,worst=0,0
for support=1,6 do for kind=1,3 do for _,right in ipairs{false,true} do
    for exponent=-12,-3 do
        local distance=10^exponent
        local a=right and 6-distance or distance
        local model=end_model(support,kind,a,right)
        local sol,err=Frame.solve(model)
        assert(sol,'near support '..support..' kind '..kind..' distance '..distance..': '..tostring(err))
        assert(sol.checks.compatibility_relative<1e-9)
        worst=math.max(worst,sol.checks.compatibility_relative);total=total+1
    end
end end end
assert(total==360)
print(string.format('P1C.1 NEAR: cases=%d rejected=0 worst_compatibility=%.17g',total,worst))

local pair_count,pair_worst=0,0
for _,support in ipairs{3,1,6} do for _,kind in ipairs{1,2} do
    for _,x0 in ipairs{1e-6,1e-3,.5,3,5.5} do for _,distance in ipairs{1e-9,1e-7,1e-5,1e-3} do
        local model=end_model(support,kind,x0,false)
        local first=model.member_loads[1]
        model.member_loads[2]=kind==1 and {member=1,type='point',a=x0+distance,P=-first.P}
                                      or {member=1,type='moment',a=x0+distance,M=-first.M}
        local sol,err=Frame.solve(model);assert(sol,tostring(err))
        assert(sol.checks.compatibility_relative<1e-9)
        local check=sol.checks.compatibility_members[1]
        assert(check.relative_raw>=check.relative)
        pair_worst=math.max(pair_worst,check.relative);pair_count=pair_count+1
    end end
end end
assert(pair_count==120)
print(string.format('P1C.1 PAIRS: cases=%d rejected=0 worst_compatibility=%.17g',pair_count,pair_worst))

local loader=loadstring or load
local before=assert(loader(pre_patch_mutated,'pre-patch mutation'))()
local after=assert(loader(post_patch_mutated,'post-patch mutation'))()
local rejected_before,rejected_after,cases=0,0,0
for support=1,6 do for kind=1,3 do for a=1,5 do
    local model=end_model(support,kind,a,false)
    local old=before.solve(model)
    local new=after.solve(model)
    assert((old==nil)==(new==nil),'changed mutation rejection support='..support..' kind='..kind..' a='..a)
    if not old then rejected_before=rejected_before+1 end
    if not new then rejected_after=rejected_after+1 end
    cases=cases+1
end end end
assert(cases==90)
print(string.format('P1C.1 MUTATION: cases=%d rejected_before=%d rejected_after=%d same_cases=true',cases,rejected_before,rejected_after))
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lua', help='Execute the same chunk with a Lua CLI')
    parser.add_argument('--write-lua', type=Path, help='Export chunk, then execute')
    args = parser.parse_args()
    if args.write_lua:
        args.write_lua.write_text(script, encoding='utf-8')
    if args.lua:
        subprocess.run([args.lua, '-'], input=script, text=True, check=True)
        return
    lib = ctypes.CDLL('liblua5.4.so.0')
    lib.luaL_newstate.restype = ctypes.c_void_p
    lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
    lib.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lib.luaL_loadstring.restype = ctypes.c_int
    lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int,
                             ctypes.c_int, ctypes.c_longlong, ctypes.c_void_p]
    lib.lua_pcallk.restype = ctypes.c_int
    lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
    lib.lua_tolstring.restype = ctypes.c_char_p
    lib.lua_close.argtypes = [ctypes.c_void_p]
    vm = lib.luaL_newstate()
    try:
        lib.luaL_openlibs(vm)
        code = lib.luaL_loadstring(vm, script.encode())
        if code == 0:
            code = lib.lua_pcallk(vm, 0, 0, 0, 0, None)
        if code:
            raise RuntimeError(lib.lua_tolstring(vm, -1, None).decode())
    finally:
        lib.lua_close(vm)


if __name__ == '__main__':
    main()
