"""P6C-R1: actual portal UI, shared sections, independent oracles and regression."""
import ctypes
from decimal import Decimal
import importlib.util
from pathlib import Path

from portal_reference import section_witnesses

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('portal_literals', root/'tools/make_beam_golden.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def floats(value):
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, list):
        return [floats(v) for v in value]
    if isinstance(value, dict):
        return {k: floats(v) for k, v in value.items()}
    return value


script = (f"local root={str(root)!r}\nlocal section_cases="
          + builder.literal(floats(section_witnesses()))+'\n'
          + (root/'tests/portal_ui.lua').read_text())
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
