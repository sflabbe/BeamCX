"""Run the real generated TI-Lua file under liblua5.4 and test catalog+UI."""
import ctypes
from pathlib import Path
root=Path(__file__).resolve().parent.parent
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
script=f'''
local src=dofile({str(root/'src'/'section_db.lua')!r})
local db=src
local function eq(a,b)
  assert(a and math.abs(a-b)<1e-8*math.max(1,math.abs(b)),tostring(a)..' != '..tostring(b))
end
local s={{material=1,profile=6,b=250,h=450,manualEI=10000}}
eq(db.compute(s).EI,10000)
s.material=3
local ic=(0.25*0.45^3/12)
eq(db.compute(s).I,ic)
eq(db.compute(s).EI,31000000*ic)
s.material=5
eq(db.compute(s).EI,210000*1943*1e-5)
s.material=6
eq(db.compute(s).EI,210000*1943*1e-5)
s.profile=16
eq(db.compute(s).EI,210000*3692*1e-5)
s.material=2;s.b=0
assert(db.compute(s)==nil)
print('PASS: catalog manual/concrete/steel, IPE/HEA, units, invalid dimension')

platform={{window={{width=function() return 320 end,height=function() return 212 end,invalidate=function() end}}}}
dofile({str(root/'BeamCX.lua')!r})
on.enterKey()
local gc=setmetatable({{}},{{__index=function() return function() end end}})
on.paint(gc)
local start=on.save()
eq(start.params.EI,10000)
-- Keep legacy first TAB -> plot; second TAB -> new section page.
on.tabKey();eq(on.save().page,2);on.paint(gc)
on.tabKey();eq(on.save().page,3);on.paint(gc)
-- material MANUAL -> C20/25; 250x450 mm initial
on.arrowRight()
local saved=on.save()
eq(saved.section.material,2)
eq(saved.params.EI,30000000*ic)
on.paint(gc)
-- Down skips readonly Section row, reaches width
on.arrowDown();eq(on.save().section.b,250)
on.charIn('3');on.charIn('0');on.charIn('0');on.enterKey()
eq(on.save().section.b,300)
eq(on.save().params.EI,30000000*(.30*.45^3/12))
-- Save/restore material, dimensions and screen.
local frozen=on.save()
on.arrowUp();on.arrowRight() -- C25/30
on.restore(frozen)
eq(on.save().section.material,2)
eq(on.save().section.b,300)
-- Move 3 full TAB cycles, then load new material S235.
on.tabKey();eq(on.save().page,1)
on.tabKey();eq(on.save().page,2)
on.tabKey();eq(on.save().page,3)
on.arrowRight();on.arrowRight();on.arrowRight();eq(on.save().section.material,5)
-- Manual solver physics unchanged: M=45 and reactions=30 independent of EI.
on.tabKey();on.tabKey();eq(on.save().page,2)
local r=Beam.solve(on.save().params)
assert(r)
eq(Beam.at(r,3).M,45)
eq(r.r[2],30)
eq(Beam.at(r,3).w,-5*10*6^4/(384*on.save().params.EI))
-- Negative keyboard value: go to beam page and edit P field.
on.tabKey();eq(on.save().page,3)
on.tabKey();eq(on.save().page,1)
on.arrowDown();on.arrowDown();on.arrowDown()
on.charIn('−');on.charIn('1');on.enterKey()
eq(on.save().params.P,-1)
eq(on.save().params.L,6)
-- The unused a should not prevent reducing L when P becomes zero.
on.charIn('0');on.enterKey() -- P=0
on.arrowUp();on.arrowUp() -- L field
on.charIn('2');on.enterKey()
eq(on.save().params.L,2)
eq(on.save().params.a,1)
print('PASS: TI-Lua catalogue navigation, auto-EI, save/restore, negative key, reduced length')
'''
code=lib.luaL_loadstring(vm,script.encode())
if code==0:code=lib.lua_pcallk(vm,0,0,0,0,None)
if code:
    print('LUA ERROR:',lib.lua_tolstring(vm,-1,None).decode())
    raise SystemExit(1)
lib.lua_close(vm)
