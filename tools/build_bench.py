"""Bundle the independent benchmark: python3 tools/build_bench.py.

Package separately: python3 tools/package.py --bench (Luna a9924a9).
Never reads or writes BeamCX.lua, and never imports the app UI.
"""
import argparse
import hashlib
from pathlib import Path
import re

root=Path(__file__).resolve().parent.parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output',type=Path,default=root/'bench.lua')
args=parser.parse_args()
source=(root/'src/frame_core.lua').read_text()
version=re.match(r'-- BeamCX ([^:]+):',source).group(1)
sha=hashlib.sha256(source.encode()).hexdigest()
assert source.rstrip().endswith('return Frame')
source=source[:source.rfind('return Frame')].replace('local Frame = {}','Frame = {}',1)
output='-- BeamCX independent benchmark P6A (generated).\n'+source
output+=f'\nlocal BENCH_CORE_VERSION={version!r}\nlocal BENCH_CORE_SHA={sha!r}\n'
preset=(root/'src/continuous_preset.lua').read_text()
assert preset.rstrip().endswith('return ContinuousPreset')
output+='\n'+preset[:preset.rfind('return ContinuousPreset')].replace('local ContinuousPreset =','ContinuousPreset =',1)
preset=(root/'src/portal_preset.lua').read_text()
assert preset.rstrip().endswith('return PortalPreset')
output+='\n'+preset[:preset.rfind('return PortalPreset')].replace('local PortalPreset=','PortalPreset=',1)
output+=(root/'tools/bench_ti.lua').read_text()
args.output.write_text(output)
print(f'Wrote {args.output}: {len(output.encode())} bytes; Frame {version} {sha[:8]}')
