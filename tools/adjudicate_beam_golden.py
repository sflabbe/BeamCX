"""Generate independent 60-digit references, without changing the golden fixture.

Run: python3 tools/adjudicate_beam_golden.py [--lua lua5.1]
Requires mpmath only for this offline generator; normal tests read its JSON.
Equivalence scales use max(response, 1e-6*engineering_reference). This is NOT a
precision guarantee for vanishing responses (covered by a separate oracle).
"""
import argparse
from datetime import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
from zoneinfo import ZoneInfo
import mpmath as mp

ROOT=Path(__file__).resolve().parent.parent
mp.mp.dps=60
ADJUDICATED={'random_0550','random_0752'}
spec=importlib.util.spec_from_file_location('golden_builder',ROOT/'tools/make_beam_golden.py')
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)


def reference(case):
    p=case['p'];L,q,P,a,EI=(mp.mpf(p[k]) for k in ('L','q','P','a','EI'));b=L-a
    if p['support']==1:
        rb=q*L/2+P*a/L;ra=q*L+P-rb;m0=mp.mpf(0)
        theta0=-q*L**3/(24*EI)-P*b*(L*L-b*b)/(6*L*EI)
    elif p['support']==2:
        rb=mp.mpf(0);ra=q*L+P;m0=-q*L*L/2-P*a;theta0=mp.mpf(0)
    elif p['support']==3:
        rb=q*L/2+P*a*a*(a+3*b)/L**3;ra=q*L+P-rb
        m0=-q*L*L/12-P*a*b*b/L**2;theta0=mp.mpf(0)
    else:
        rb=3*q*L/8+P*a*a*(3*L-a)/(2*L**3);ra=q*L+P-rb
        m0=-q*L*L/2-P*a+rb*L;theta0=mp.mpf(0)
    def value(x):
        t=max(mp.mpf(0),x-a)
        M=m0+ra*x-q*x*x/2-P*t
        V=ra-q*x-(P if x>a or a==0 else 0)
        theta=theta0+(m0*x+ra*x*x/2-q*x**3/6-P*t*t/2)/EI
        w=theta0*x+(m0*x*x/2+ra*x**3/6-q*x**4/24-P*t**3/6)/EI
        if x==0 or (x==L and p['support']!=2): w=mp.mpf(0)
        return M,V,w,theta
    cuts=sorted(set([mp.mpf(0),a,L]))
    moment_candidates=list(cuts);w_candidates=list(cuts);shears=[]
    for left,right in zip(cuts,cuts[1:]):
        if left==right: continue
        force=ra-(P if left>=a else 0)
        moment_const=m0+(P*a if left>=a else 0)
        if q:
            x=force/q
            if left<x<right: moment_candidates.append(x)
        shears.extend([force-q*left,force-q*right])
        # w' is cubic, and monotone between roots of M=w''*EI.
        turning=[left,right]
        if q:
            disc=force*force+2*q*moment_const
            if disc>=0:
                for x in ((force-mp.sqrt(disc))/q,(force+mp.sqrt(disc))/q):
                    if left<x<right: turning.append(x)
        elif force:
            x=-moment_const/force
            if left<x<right: turning.append(x)
        turning=sorted(set(turning));w_candidates.extend(turning)
        for low,high in zip(turning,turning[1:]):
            fl,fh=value(low)[3],value(high)[3]
            if fl*fh<0:
                for _ in range(180):
                    mid=(low+high)/2;fm=value(mid)[3]
                    if fl*fm>0: low=mid;fl=fm
                    else: high=mid
                w_candidates.append((low+high)/2)
    xmin=min(moment_candidates,key=lambda x:value(x)[0]);xmax=max(moment_candidates,key=lambda x:value(x)[0])
    xw=max(w_candidates,key=lambda x:abs(value(x)[2]));w=abs(value(xw)[2]);mm=1000*w
    lref=mp.mpf(case['lref_factor'])*L
    ratio=lref/w if w else None
    u250=w*250/lref;u300=w*300/lref
    selected=u300 if case['limit']==300 else u250
    status='N/A' if ratio is None else ('OK' if selected<=1+mp.mpf('1e-12') else 'EXCEEDED')
    mj=value(L)[0]
    data=dict(reactions=dict(left=dict(Rx=0,Ry=float(ra),Mz=float(-m0)),right=dict(Rx=0,Ry=float(rb),Mz=float(mj))),
        samples=[[float(v) for v in value(min(L,mp.mpf(float(p['L']*i/100))))[:3]] for i in range(101)],
        moments=dict(lo=float(value(xmin)[0]),xlo=float(xmin),hi=float(value(xmax)[0]),xhi=float(xmax)),
        deflection=dict(mm=float(mm),position=float(xw)),
        summary=dict(mmin=float(value(xmin)[0]),mmax=float(value(xmax)[0]),vabs=float(max(map(abs,shears))),
            w_abs_max=float(mm),x_wmax=float(xw),ra=float(ra),rb=float(rb),ei=p['EI'],
            lref=float(lref),lref_factor=case['lref_factor'],ratio=float(ratio) if ratio else None,
            u250=float(u250),u300=float(u300),status=status))
    return data,value


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'tests/fixtures/beam_v033_adjudicated.json')
    parser.add_argument('--lua',default='lua5.1');args=parser.parse_args()
    path=ROOT/'tests/fixtures/beam_v033_golden.json';golden=json.loads(path.read_text())
    cases=[c for c in golden['cases'] if c['name'] in ADJUDICATED or (c['valid'] and 'error' in c['beam'])]
    code="Frame=dofile('src/frame_core.lua')\nlocal Preset=dofile('src/beam_preset.lua')\nlocal cases="+builder.literal(cases)+r'''
for _,c in ipairs(cases) do
    local s,e=Preset.solve(c.p);assert(s,e)
    for i=0,100 do local v=Preset.at(s,c.p.L*i/100);print(string.format('DATA %s %d %.17g %.17g %.17g',c.name,i,v.M,v.V,v.w)) end
    for _,side in ipairs{'left','right'} do local r=s.reactions[side];print(string.format('REACTION %s %s %.17g %.17g',c.name,side,r.Ry,r.Mz)) end
end
'''
    run=subprocess.run([args.lua,'-'],cwd=ROOT,input=code,text=True,capture_output=True,check=True)
    actual={c['name']:dict(samples=[],reactions={}) for c in cases}
    for line in run.stdout.splitlines():
        cols=line.split()
        if cols[0]=='DATA': actual[cols[1]]['samples'].append([mp.mpf(v) for v in cols[3:]])
        else: actual[cols[1]]['reactions'][cols[2]]=[mp.mpf(v) for v in cols[3:]]
    refs={};rows=[]
    for case in cases:
        ref,value=reference(case);refs[case['name']]=ref
        if case['name'] not in ADJUDICATED: continue
        p=case['p'];F=abs(mp.mpf(p['q']))*p['L']+abs(mp.mpf(p['P']))
        engineering=[F*p['L'],F,F*p['L']**3/p['EI']]
        frame_worst,beam_worst=mp.mpf(0),mp.mpf(0)
        for index,name in enumerate(['M','V','w']):
            targets=[value(min(mp.mpf(p['L']),mp.mpf(float(p['L']*i/100))))[index] for i in range(101)]
            scale=max(max(map(abs,targets)),mp.mpf('1e-6')*engineering[index])
            fe=[abs(actual[case['name']]['samples'][i][index]-target)/scale for i,target in enumerate(targets)]
            be=[abs(mp.mpf(case['beam']['samples'][i][index])-target)/scale for i,target in enumerate(targets)]
            at=max(range(101),key=lambda i:be[i])
            rows.append(dict(case=case['name'],quantity=name,x=float(p['L']*at/100),
                beam=case['beam']['samples'][at][index],frame=str(actual[case['name']]['samples'][at][index]),
                arbiter=mp.nstr(targets[at],60),scale=mp.nstr(scale,30),
                beam_error=float(max(be)),frame_error=float(max(fe)),
                probable_cause=f"legacy short subelement L-a={p['L']-p['a']:.17g} m"))
            frame_worst=max(frame_worst,max(fe));beam_worst=max(beam_worst,max(be))
        # Include all support reactions in the independent adjudication gate.
        for side in ('left','right'):
            for i,name in enumerate(('Ry','Mz')):
                target=mp.mpf(ref['reactions'][side][name]);scale=engineering[0 if name=='Mz' else 1]
                frame_worst=max(frame_worst,abs(actual[case['name']]['reactions'][side][i]-target)/scale)
                beam_worst=max(beam_worst,abs(mp.mpf(case['beam']['reactions'][side][name])-target)/scale)
        assert frame_worst<=mp.mpf('1e-11'),(case['name'],'Frame',frame_worst)
        assert frame_worst<beam_worst<=mp.mpf('1e-6'),(case['name'],'Beam',beam_worst)
    assert len(ADJUDICATED)<=.01*len(golden['cases'])
    output=dict(precision=60,date=datetime.now(ZoneInfo('Europe/Berlin')).date().isoformat(),
        golden_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),adjudicated=sorted(ADJUDICATED),references=refs,evidence=rows)
    args.output.write_text(json.dumps(output,separators=(',',':'),allow_nan=False)+'\n')
    print(f'PASS: {len(ADJUDICATED)} adjudicated + {len(refs)-len(ADJUDICATED)} RESOLVED; 60 digits; golden unchanged')
    for row in rows: print('ADJUDICATION',json.dumps(row))


if __name__=='__main__': main()
