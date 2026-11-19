"""Exact P6B/current event and graphics replay, offline in both Lua runtimes."""
import ctypes
import gzip
import hashlib
from pathlib import Path

root = Path(__file__).resolve().parents[1]
baseline = gzip.decompress((root/'tests/fixtures/p6b_bundle.lua.gz').read_bytes())
assert hashlib.sha256(baseline).hexdigest() == '88b7b433044a75564ff92876cc4568e2c42eab40a23e916b94aa91a42368b55f'
source = baseline.decode()
assert ']====]' not in source
script = (f'local root={str(root)!r}\nlocal baseline_source=[====[\n{source}]====]\n'
          + (root/'tests/ui_equivalence.lua').read_text())
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
