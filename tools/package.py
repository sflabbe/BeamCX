"""Package generated Lua with a bounded guard for libnspire's USB packet size."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def last_packet_size(size):
    return 17 + size % 253


def unsafe_size(size):
    return last_packet_size(size) % 64 == 0


def package(lua, output, luna=Path.home()/'Luna/luna'):
    max_attempts = 8
    lua, output = Path(lua), Path(output)
    for attempt in range(1, max_attempts+1):
        subprocess.run([str(luna), str(lua), str(output)], check=True)
        size = output.stat().st_size
        if not unsafe_size(size):
            print(f'{output.name}: {size} bytes; last USB packet: {last_packet_size(size)} bytes')
            return size
        if attempt < max_attempts:
            print(f'{output.name}: unsafe size {size}; adding generated-Lua padding (attempt {attempt})')
            newline = b'' if lua.read_bytes().endswith(b'\n') else b'\n'
            with lua.open('ab') as file:
                file.write(newline + f'-- N-Link USB padding {attempt}\n'.encode('ascii'))
    raise RuntimeError(f'{output.name}: unsafe USB packet size after {max_attempts} attempts')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bench', action='store_true', help='package bench.lua as BXBENCH.tns')
    parser.add_argument('--luna', type=Path, default=Path.home()/'Luna/luna')
    parser.add_argument('--output', type=Path, help='override the output document path')
    args = parser.parse_args()
    lua, output = ('bench.lua', 'BXBENCH.tns') if args.bench else ('BeamCX.lua', 'BeamCX.tns')
    package(ROOT/lua, args.output or ROOT/output, args.luna)


if __name__ == '__main__':
    main()
