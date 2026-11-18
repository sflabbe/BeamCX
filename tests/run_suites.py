"""Run every suite, optionally executing its existing Lua chunk with --lua CLI."""
import argparse
import ctypes
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--lua', help='e.g. lua5.1; default: each suite uses liblua5.4')
args = parser.parse_args()
paths = sorted((root/'tests').glob('test_*.py'))
if args.lua:
    subprocess.run([args.lua, '-v'], check=True)
    original_cdll = ctypes.CDLL

    class Captured(BaseException):
        pass

    for path in paths:
        chunks = []

        def capture_cdll(*a, **kw):
            lib = original_cdll(*a, **kw)
            close = lib.lua_close

            def capture(vm, source):
                chunks.append(source)
                close(vm)
                raise Captured()

            lib.luaL_loadstring = capture
            lib.lua_close = lambda vm: None  # VM already closed at capture.
            return lib

        print('RUN ' + path.name, flush=True)
        ctypes.CDLL = capture_cdll
        sys.argv = [str(path)]
        try:
            runpy.run_path(str(path), run_name='__main__')
        except Captured:
            pass
        finally:
            ctypes.CDLL = original_cdll
        assert len(chunks) == 1, path
        with tempfile.TemporaryDirectory(prefix='beamcx-tests-') as tmp:
            chunk = Path(tmp)/'suite.lua'
            chunk.write_bytes(chunks[0])
            subprocess.run([args.lua, str(chunk)], cwd=root, check=True)
else:
    for path in paths:
        print('RUN ' + path.name, flush=True)
        subprocess.run([sys.executable, str(path)], cwd=root, check=True)
print(f'PASS: {len(paths)} suites ({args.lua or "liblua5.4"})', flush=True)
