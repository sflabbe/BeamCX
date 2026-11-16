"""TI-Lua graph regression: both load types use one solid head each."""
import ctypes
from pathlib import Path
root = Path(__file__).resolve().parent.parent
lib = ctypes.CDLL('liblua5.4.so.0')
lib.luaL_newstate.restype = ctypes.c_void_p
lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
lib.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lib.luaL_loadstring.restype = ctypes.c_int
lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_longlong, ctypes.c_void_p]
lib.lua_pcallk.restype = ctypes.c_int
lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
lib.lua_tolstring.restype = ctypes.c_char_p
lib.lua_close.argtypes = [ctypes.c_void_p]
script = f'''\nplatform={{window={{width=function() return 320 end,height=function() return 212 end,invalidate=function() end}}}}
dofile({str(root/'BeamCX.lua')!r})
local gc={{lines={{}},heads={{}}}}
function gc:setColorRGB() end
function gc:setFont() end
function gc:fillRect() end
function gc:drawString() end
function gc:setPen() end
function gc:drawLine(x1,y1,x2,y2)
  self.lines[#self.lines+1]={{x1,y1,x2,y2}}
end
function gc:fillPolygon(points)
  self.heads[#self.heads+1]=points
end
local function paint(q,P,expected)
  local saved=on.save()
  saved.params.q=q
  saved.params.P=P
  saved.page=2
  on.restore(saved)
  gc.lines={{}}
  gc.heads={{}}
  on.paint(gc)
  assert(#gc.heads==expected,'expected '..expected..' load heads, found '..#gc.heads)
  for _,p in ipairs(gc.heads) do
    assert(#p==6 and p[2]==p[4] and p[6]>p[2], 'head must be one downward filled triangle')
    assert(p[3]-p[1] == 2*(p[5]-p[1]),'head must be symmetric')
    local found=false
    for _,l in ipairs(gc.lines) do
      if l[1]==p[5] and l[3]==p[5] and l[4]==p[2]
       and (l[2]==43 or l[2]==32) then found=true;break end
    end
    assert(found,'shaft must stop exactly at head base')
    assert(p[6]==60 and p[2]==53,'arrow geometry must retain gap from beam')
  end
end
paint(10,0,9)     -- distributed load: exactly 9 heads
paint(0,10,1)     -- point load: exactly one head
paint(10,10,10)   -- both load types coexist
print('PASS: 9 UDL heads, 1 point head, overlap model; one filled triangle per arrow')
'''
vm=lib.luaL_newstate()
try:
    lib.luaL_openlibs(vm)
    code=lib.luaL_loadstring(vm, script.encode())
    if code == 0:
        code = lib.lua_pcallk(vm,0,0,0,0,None)
    if code:
        raise RuntimeError(lib.lua_tolstring(vm,-1,None).decode())
finally:
    lib.lua_close(vm)
