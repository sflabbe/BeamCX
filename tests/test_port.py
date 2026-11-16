"""Execute the actual Lua solver under the available liblua runtime (5.4)."""
import ctypes
from pathlib import Path

lib=ctypes.CDLL('liblua5.4.so.0')
lib.luaL_newstate.restype=ctypes.c_void_p
lib.luaL_openlibs.argtypes=[ctypes.c_void_p]
lib.luaL_loadstring.argtypes=[ctypes.c_void_p,ctypes.c_char_p]
lib.luaL_loadstring.restype=ctypes.c_int
lib.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_longlong,ctypes.c_void_p]
lib.lua_pcallk.restype=ctypes.c_int
lib.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p]
lib.lua_tolstring.restype=ctypes.c_char_p
lib.lua_close.argtypes=[ctypes.c_void_p]
vm=lib.luaL_newstate()
lib.luaL_openlibs(vm)
root=Path(__file__).resolve().parent.parent
script = f'''\nBeam=dofile({str(root/'src'/'beam_core.lua')!r})
local function eq(x,y) assert(math.abs(x-y)<1e-7*math.max(1,math.abs(y)),tostring(x)..' != '..tostring(y)) end
local function solve(p) local s,e=Beam.solve(p); assert(s,e); eq(s.force_residual,0);eq(s.moment_residual,0); return s end
local s=solve{{L=6,q=10,P=0,a=3,EI=10000,support=1}}
eq(s.r[2],30);eq(s.r[#s.r-1],30)
eq(Beam.at(s,3).M,45)
eq(Beam.at(s,3).w,-5*10*6^4/(384*10000))
local a,b,c,d=Beam.moment_extrema(s);eq(c,45);eq(d,3)
s=solve{{L=6,q=0,P=12,a=6,EI=10000,support=2}}
eq(s.r[2],12);eq(s.r[3],72);eq(Beam.at(s,0).M,-72);eq(Beam.at(s,6).w,-12*6^3/(3*10000))
s=solve{{L=6,q=10,P=0,a=3,EI=10000,support=3}}
eq(Beam.at(s,0).M,-30);eq(Beam.at(s,3).M,15)
s=solve{{L=6,q=10,P=0,a=3,EI=10000,support=4}}
eq(Beam.at(s,0).M,-45);eq(Beam.at(s,3.75).M,9*10*6^2/128)
eq(s.r[#s.r-1],3*10*6/8)
s=solve{{L=6,q=0,P=12,a=2,EI=10000,support=1}}
eq(s.r[2],8);eq(s.r[#s.r-1],4);eq(Beam.at(s,2).M,16)
local before=Beam.at(s,2-1e-6).V;local after=Beam.at(s,2+1e-6).V;eq(before-after,12)
local fail,msg=Beam.solve{{L=0,q=10,P=0,a=0,EI=10000,support=1}};assert(fail==nil and msg)
print('PASS: 5 structural cases + mechanics + negative input')
-- Smoke test the UI with a draw-only fake graphics context and keyboard handlers.
platform={{window={{width=function() return 320 end,height=function() return 212 end,invalidate=function() end}}}}
dofile({str(root/'BeamCX.lua')!r})
local gc=setmetatable({{}},{{__index=function() return function() end end}})
on.paint(gc);on.tabKey();on.paint(gc)
on.arrowRight();on.arrowUp();on.arrowDown();on.paint(gc)
on.tabKey();on.arrowDown();on.charIn('8');on.enterKey();on.paint(gc)
print('PASS: UI paint, navigation and numeric input smoke')
'''
code=lib.luaL_loadstring(vm,script.encode('utf-8'))
if code==0: code=lib.lua_pcallk(vm,0,0,0,0,None)
if code:
    print('LUA ERROR:',lib.lua_tolstring(vm,-1,None).decode('utf-8'))
    raise SystemExit(1)
lib.lua_close(vm)
