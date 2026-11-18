"""Independent 60-digit closed-form arbitration of flagged golden cases.

Run: python3 tools/adjudicate_beam_golden.py
Writes /tmp/beamcx-p2a-arbitration.json. A nonzero exit flags Frame errors
above 1e-11 or Beam errors above 1e-6; no production solver is modified.
Requires mpmath and the Lua 5.1 CLI, only for offline adjudication.
"""
import argparse
import importlib.util
import json
import subprocess
from pathlib import Path
import mpmath as mp
mp.mp.dps=60
root=Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('golden_builder',root/'tools/make_beam_golden.py')
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
fixture=json.loads((root/'tests/fixtures/beam_v033_golden.json').read_text())
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output',type=Path,default=Path('/tmp/beamcx-p2a-arbitration.json'))
args=parser.parse_args()
ids=['random_0550','random_0752','near_2_1e-07','near_3_1e-07','near_4_1e-07']
cases=[c for c in fixture['cases'] if c['name'] in ids]
code="Frame=dofile('src/frame_core.lua')\nlocal Preset=dofile('src/beam_preset.lua')\nlocal cases="+builder.literal(cases)+'''\nfor _,c in ipairs(cases) do
local s,e=Preset.solve(c.p);assert(s,e)
for i=0,100 do local v=Preset.at(s,c.p.L*i/100);print(string.format('DATA %s %d %.17g %.17g %.17g',c.name,i,v.M,v.V,v.w)) end
for _,side in ipairs{'left','right'} do local r=s.reactions[side];print(string.format('REACTION %s %s %.17g %.17g',c.name,side,r.Ry,r.Mz)) end
end
'''
r=subprocess.run(['lua5.1','-'],cwd=root,input=code,text=True,capture_output=True,check=True)
actual={name:dict(samples=[],reactions={}) for name in ids}
for line in r.stdout.splitlines():
    cols=line.split()
    if cols[0]=='DATA': actual[cols[1]]['samples'].append([mp.mpf(v) for v in cols[3:]])
    else: actual[cols[1]]['reactions'][cols[2]]=[mp.mpf(v) for v in cols[3:]]
rows=[]
for case in cases:
    p=case['p'];L,q,P,a,EI=(mp.mpf(p[k]) for k in ('L','q','P','a','EI'));b=L-a
    if p['support']==1: rb=q*L/2+P*a/L;ra=q*L+P-rb;m0=mp.mpf(0)
    elif p['support']==2: rb=mp.mpf(0);ra=q*L+P;m0=-q*L**2/2-P*a
    elif p['support']==3: rb=q*L/2+P*a*a*(a+3*b)/L**3;ra=q*L+P-rb;m0=-q*L**2/12-P*a*b*b/L**2
    else: rb=3*q*L/8+P*a*a*(3*L-a)/(2*L**3);ra=q*L+P-rb;m0=-q*L**2/2-P*a+rb*L
    samples=[]
    for i in range(101):
        x=min(L,max(mp.mpf(0),mp.mpf(float(p['L']*i/100))));t=max(mp.mpf(0),x-a)
        V=ra-q*x-(P if x>a or a==0 else 0);M=m0+ra*x-q*x*x/2-P*t
        if p['support']==1:
            w=-q*x*(L**3-2*L*x*x+x**3)/(24*EI)
            if x<=a: w-=P*b*x*(L*L-b*b-x*x)/(6*L*EI)
            else: w-=P*a*(L-x)*(L*L-a*a-(L-x)**2)/(6*L*EI)
        else: w=(m0*x*x/2+ra*x**3/6-q*x**4/24-P*t**3/6)/EI
        if x==0 or (x==L and p['support']!=2): w=mp.mpf(0)
        samples.append([M,V,w])
    for index,name in enumerate(['M','V','w']):
        scale=max(abs(s[index]) for s in samples)
        diffs=[abs(actual[case['name']]['samples'][i][index]-v[index])/(scale or 1) for i,v in enumerate(samples)]
        bd=[abs(mp.mpf(case['beam']['samples'][i][index])-v[index])/(scale or 1) for i,v in enumerate(samples)]
        at=max(range(101),key=lambda i:diffs[i])
        row=dict(case=case['name'],input=case['p'],short_segment=float(L-a),quantity=name,x=float(p['L']*at/100),arbiter=mp.nstr(samples[at][index],60),
                 frame=mp.nstr(actual[case['name']]['samples'][at][index],20),beam=repr(case['beam']['samples'][at][index]),
                 frame_error=mp.nstr(diffs[at],20),beam_error=mp.nstr(bd[at],20),max_beam_error=mp.nstr(max(bd),20),scale=mp.nstr(scale,20))
        rows.append(row)
        print(json.dumps(row))
args.output.write_text(json.dumps(dict(precision=60,rows=rows),indent=2))
if any(mp.mpf(row['max_beam_error'])>mp.mpf('1e-6') for row in rows):
    raise SystemExit('STOP: Beam error exceeds 1e-6')
if len(cases)>len(fixture['cases'])*.01:
    raise SystemExit('STOP: adjudications exceed 1% of fixture')
if any(mp.mpf(row['frame_error'])>mp.mpf('1e-11') for row in rows):
    raise SystemExit('STOP: Frame error exceeds the adjudication tolerance 1e-11')
