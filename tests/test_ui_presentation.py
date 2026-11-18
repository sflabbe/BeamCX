"""R2: English presentation, precision, saved contracts and complete small-screen layout."""
import ctypes
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
spanish = re.compile(r'\b(?:CONTINUA|entrada|salida|vanos?|apoyos?|extremo|izq|der|'
                     r'envolvente|caracteristica|naranja|azul|impares|pares|flecha|'
                     r'resultado|guardado|tabla|modo|seccion|sección|aplicar|resultados|'
                     r'calculando|desactualizado|documento|válido|valores|defecto)\b', re.I)
for path in [*sorted((root/'src').glob('*.lua')), root/'tools/bench_ti.lua']:
    source = path.read_text()
    assert not spanish.search(source), f'Spanish application text in {path}'
    for name in re.findall(r'\bfunction\s+([\w.:]+)\s*\(', source):
        assert not spanish.search(name.replace('_', ' ')), f'Spanish function {name}'
    assert not re.search(r'\bcar\b', source), f'Spanish characteristic-result identifier in {path}'
print('PASS English source strings and function/characteristic-result identifiers', flush=True)
script = f"local root={str(root)!r}\n" + (root/'tests/ui_presentation.lua').read_text()
lib = ctypes.CDLL('liblua5.4.so.0')
lib.luaL_newstate.restype = ctypes.c_void_p
lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
lib.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                           ctypes.c_longlong, ctypes.c_void_p]
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
