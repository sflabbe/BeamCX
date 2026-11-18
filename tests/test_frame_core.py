"""P1A oracles under real Lua: ctypes/5.4, or --lua lua5.1.

--write-lua PATH also exports the identical Lua test chunk for direct execution.
All beam comparisons use relative 1e-9 (absolute 1e-9 for expected zero),
frames 1e-4. Performance timings are informational CPU seconds on this PC.
"""
import argparse
import ctypes
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
script = f"local Frame=dofile({str(root / 'src/frame_core.lua')!r})\n" + r'''
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
local asm=assert(Frame.assemble(model))
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
    local a=assert(Frame.assemble(m))
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
eq('23 merged A',sol.reactions[1].Ry,12);eq('23 merged B',sol.reactions[2].Ry,0)
assert(#sol.nodes==2 and sol.members[1].points[1].position==0)
sol=solve(beam(1,nil,.006))
local a,b=.006,5.994
assert(#sol.nodes==3)
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
for _,kind in ipairs{'dist','moment','dT','unknown'} do
    m=beam(1);m.member_loads={{member=1,type=kind}}
    fail(m,'unsupported member load type')
end
for _,field in ipairs{'releases','springs','settlements','dT'} do
    m=beam(1);m.members[1][field]={};fail(m,'unsupported member field')
end
m=beam(1);m.supports[1].uy=.01;fail(m,'unsupported prescribed displacement')
m=beam(1);m.nodes[2].y=1;m.member_loads={{member=1,type='udl',q=-10}}
fail(m,'inclined member loads')
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
-- Fused interior points, transitive cluster, repeated udl and nodal loads;
-- original user coordinates and records must remain unchanged.
m=beam(1,{true},2)
m.member_loads[3]={member=1,type='point',a=2+3e-6,P=-3}
m.member_loads[4]={member=1,type='point',a=2+7e-6,P=-2}
m.member_loads[5]={member=1,type='udl',q=2}
m.nodal_loads={{node=2,Fy=1},{node=2,Fy=2}}
sol=solve(m);assert(#sol.nodes==3 and #sol.members[1].elements==2)
assert(m.member_loads[3].a==2+3e-6 and m.member_loads[3].node==nil)
l,r=Frame.at(sol,1,2,'left'),Frame.at(sol,1,2,'right')
eq('merged interior V jump',l.V-r.V,17)
-- Point near right end and strict merge threshold (not <=).
sol=solve(beam(1,nil,6-1e-7));assert(#sol.nodes==2)
eq('23 merged right B',sol.reactions[2].Ry,12)
local aa=assert(Frame.assemble(beam(1,nil,6e-6)));assert(#aa.nodes==3)
assert(not pcall(Frame.at,sol,1,6));assert(not pcall(Frame.at,sol,1,6,'right'))
assert(not pcall(Frame.at,sol,1,-1));assert(not pcall(Frame.at,sol,1,3,'bad'))
-- Reversed member orientation preserves physical nodal solutions.
m=beam(1,{true});m.members[1].i=2;m.members[1].j=1;m.member_loads[1].q=10
sol=solve(m);eq('reversed global Ry',sol.reactions[1].Ry,30)
eq('reversed local w',Frame.at(sol,1,3).w,.016875)
-- All supports prescribed / unloaded zero response.
sol=solve(beam(1,nil,nil,'fixed'));w,x=Frame.deflection_extrema(sol,1);eq('zero w',w,0)
-- Performance: three spans with one interior point in each, then exactly
-- 60 nodes AFTER partition (30 original nodes + 30 point nodes).
m=beam(3,{true,true,true})
for i=1,3 do m.member_loads[#m.member_loads+1]={member=i,type='point',a=2,P=-12} end
local t=os.clock();sol=solve(m);local elapsed=os.clock()-t
print(string.format('PERF 3 spans: nodes=%d dofs=%d free=%d seconds=%.6f',#sol.nodes,sol.ndof,#sol.free,elapsed))
m={nodes={},members={},supports={},member_loads={}}
for i=1,30 do
    m.nodes[i]={x=(i-1)*6,y=0}
    m.supports[i]={node=i,ux=i==1,uy=true}
    if i>1 then
        m.members[i-1]={i=i-1,j=i,EA=1e8,EI=1e4}
        m.member_loads[#m.member_loads+1]={member=i-1,type='point',a=2,P=-12}
    end
end
m.member_loads[#m.member_loads+1]={member=1,type='point',a=4,P=-12}
t=os.clock();sol=solve(m);elapsed=os.clock()-t
assert(#sol.nodes==60)
print(string.format('PERF 60 nodes: nodes=%d dofs=%d free=%d seconds=%.6f',#sol.nodes,sol.ndof,#sol.free,elapsed))
m.member_loads[#m.member_loads+1]={member=2,type='point',a=4,P=-12}
fail(m,'model too large for handheld')
print(string.format('CHECKS max equilibrium_relative=%.6g residual_relative=%.6g tolerance=1e-8',max_equilibrium,max_residual))
print('PASS P1A: '..rows..' numeric oracles, contracts, checks and performance')
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
