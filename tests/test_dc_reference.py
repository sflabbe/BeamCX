"""Frame vs the versioned dc Euler oracle; no numpy/dc needed by this test."""
import argparse
import ctypes
import importlib.util
import json
from pathlib import Path
import subprocess

root=Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('golden_builder',root/'tools/make_beam_golden.py')
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
fixture=json.loads((root/'tests/fixtures/dc_reference.json').read_text())
script='local Frame=dofile('+builder.literal(str(root/'src/frame_core.lua'))+')\n'
script+='local cases='+builder.literal(fixture['cases'])+'\n'+r'''
for _,case in ipairs(cases) do
    local s,e=Frame.solve(case.model);assert(s,e)
    local R,U=0,0
    for _,r in pairs(case.reference.reactions) do for _,v in pairs(r) do R=math.max(R,math.abs(v)) end end
    for _,u in ipairs(case.reference.displacements) do for _,v in ipairs(u) do U=math.max(U,math.abs(v)) end end
    local er,eu=0,0
    for node,r in pairs(case.reference.reactions) do
        for _,key in ipairs{'Rx','Ry','Mz'} do er=math.max(er,math.abs(s.reactions[tonumber(node)][key]-r[key])/math.max(R,1e-300)) end
    end
    for node,u in ipairs(case.reference.displacements) do
        for j,v in ipairs(u) do eu=math.max(eu,math.abs(s.u[3*node-3+j]-v)/math.max(U,1e-300)) end
    end
    assert(er<=1e-6 and eu<=1e-6,case.name)
    assert(s.checks.equilibrium_relative<=1e-8 and s.checks.compatibility_relative<=1e-8)
    print(string.format('DC | %s | %.17g | %.17g',case.name,er,eu))
end
print('PASS dc Euler: '..#cases..' cases, reactions and nodal displacements')
'''


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--lua');args=parser.parse_args()
    if args.lua:
        subprocess.run([args.lua,'-'],input=script,text=True,check=True);return
    lib=ctypes.CDLL('liblua5.4.so.0')
    lib.luaL_newstate.restype=ctypes.c_void_p
    lib.luaL_openlibs.argtypes=[ctypes.c_void_p]
    lib.luaL_loadstring.argtypes=[ctypes.c_void_p,ctypes.c_char_p]
    lib.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_longlong,ctypes.c_void_p]
    lib.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];lib.lua_tolstring.restype=ctypes.c_char_p
    lib.lua_close.argtypes=[ctypes.c_void_p]
    vm=lib.luaL_newstate()
    try:
        lib.luaL_openlibs(vm);status=lib.luaL_loadstring(vm,script.encode())
        if status==0: status=lib.lua_pcallk(vm,0,0,0,0,None)
        if status: raise RuntimeError(lib.lua_tolstring(vm,-1,None).decode())
    finally: lib.lua_close(vm)


if __name__=='__main__': main()
