"""Regression for the actual generated TI-Lua plot drawing, via a fake canvas."""
import ctypes
from pathlib import Path

root = Path(__file__).resolve().parent.parent
lib = ctypes.CDLL('liblua5.4.so.0')
lib.luaL_newstate.restype = ctypes.c_void_p
lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
lib.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lib.luaL_loadstring.restype = ctypes.c_int
lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                           ctypes.c_longlong, ctypes.c_void_p]
lib.lua_pcallk.restype = ctypes.c_int
lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
lib.lua_tolstring.restype = ctypes.c_char_p
lib.lua_close.argtypes = [ctypes.c_void_p]

script = f'''
platform={{window={{width=function() return 320 end,height=function() return 212 end,
                 invalidate=function() end}}}}
dofile({str(root / 'BeamCX.lua')!r})
on.enterKey()
local gc={{pen='', segments={{}}}}
function gc:setColorRGB() end
function gc:setFont() end
function gc:fillRect() end
function gc:fillPolygon() end
function gc:drawString() end
function gc:setPen(p,style) self.pen=p;self.style=style end
function gc:drawLine(x0,y0,x1,y1)
    if self.pen=='thin' and self.style=='smooth' and x1>x0 and x1-x0<8 then self.segments[#self.segments+1]={{x0=x0,y0=y0,x1=x1,y1=y1}} end
end
local function trace()
    gc.segments={{}}
    on.paint(gc)
    assert(#gc.segments==100,'expected 100 diagram strokes, got '..#gc.segments)
    return gc.segments
end
local mid=(111+(212-50))/2
-- The original positive uniform-load moment must be BELOW the reference axis.
on.tabKey()
local a=trace()
assert(a[50].y0>mid and a[1].y0==mid, 'sagging (+) M must point down')
-- Set FIX-FIX: negative moments at ends UP, positive span moment DOWN.
on.tabKey();on.tabKey()  -- sections, input
on.arrowRight();on.arrowRight() -- PIN-PIN -> FIX-FIX
on.tabKey()
a=trace()
assert(a[2].y0<mid and a[50].y0>mid and a[100].y1<mid,
       'hogging (-) M must point up, sagging (+) down')
-- Neither V nor w plots change convention.
on.arrowRight() -- V
local v=trace()
assert(v[1].y0<mid,'positive shear must still be above axis')
on.arrowRight() -- w
local w=trace()
assert(w[50].y0>mid,'negative downward deflection must still be below axis')
local p=on.save().params
local s=Beam.solve(p)
assert(s and math.abs(Beam.at(s,3).M-15)<1e-9, 'numerical moment unchanged')
print('PASS: actual TI-Lua plots M(+)/M(-), V and w; solver values unchanged')
'''
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
