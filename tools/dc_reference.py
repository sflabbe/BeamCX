"""Offline dc oracle: python3 tools/dc_reference.py ~/dinamica-computacional.

Only this generator needs numpy and the supplied checkout. It uses dc's Euler
frame element and consistent GLOBAL uniform loads. No end_forces_local call.
E is N/m², EA N, EI N*m²; multiply BeamCX kN-based quantities by 1000 before
dc assembly, divide reactions by 1000 afterwards. Displacements remain m/rad.
"""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from zoneinfo import ZoneInfo

ROOT=Path(__file__).resolve().parent.parent


def models():
    out=[]
    for support,loads in [(1,'both'),(2,'P'),(3,'q'),(4,'both')]:
        model=dict(nodes=[dict(x=0,y=0),dict(x=6,y=0)],members=[dict(i=1,j=2,EI=10000,EA=1e8)],
            supports=[dict(node=1,ux=True,uy=True,rz=support!=1),
                      dict(node=2,ux=support==3,uy=support!=2,rz=support==3)],member_loads=[])
        if loads!='P': model['member_loads'].append(dict(member=1,type='udl',q=-10))
        if loads!='q': model['member_loads'].append(dict(member=1,type='point',a=2,P=-12))
        out.append(dict(name=f'preset_{support}_{loads}',model=model))
    for spans in (2,3):
        model=dict(nodes=[dict(x=6*i,y=0) for i in range(spans+1)],
            members=[dict(i=i,j=i+1,EI=10000,EA=1e8) for i in range(1,spans+1)],
            supports=[dict(node=i,ux=i==1,uy=True) for i in range(1,spans+2)],
            member_loads=[dict(member=i,type='udl',q=-10) for i in range(1,spans+1)])
        out.append(dict(name=f'continuous_{spans}',model=model))
    for fixed in (False,True):
        for load in ('q','H'):
            model=dict(nodes=[dict(x=0,y=0),dict(x=0,y=4),dict(x=6,y=4),dict(x=6,y=0)],
                members=[dict(i=1,j=2,EI=10000,EA=1e8),dict(i=2,j=3,EI=15000,EA=1e8),dict(i=4,j=3,EI=10000,EA=1e8)],
                supports=[dict(node=1,ux=True,uy=True,rz=fixed),dict(node=4,ux=True,uy=True,rz=fixed)],
                member_loads=[dict(member=2,type='udl',q=-10)] if load=='q' else [],
                nodal_loads=[dict(node=2,Fx=10)] if load=='H' else [])
            out.append(dict(name=f'portal_{"fixed" if fixed else "pinned"}_{load}',model=model))
    return out


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('checkout',type=Path)
    parser.add_argument('--output',type=Path,default=ROOT/'tests/fixtures/dc_reference.json')
    args=parser.parse_args();checkout=args.checkout.expanduser().resolve()
    sys.path.insert(0,str(checkout/'src'))
    import numpy as np
    from dc_solver.fem.frame2d import FrameElementLinear2D, rot2d
    from dc_solver.fem.nodes import Node,DofManager
    cases=models()
    for case in cases:
        m=case['model'];dm=DofManager()
        nodes=[Node(n['x'],n['y'],dm.new_trans(),dm.new_rot()) for n in m['nodes']]
        K=np.zeros((dm.ndof,dm.ndof));F=np.zeros(dm.ndof);elements=[]
        for member in m['members']:
            E=210e9
            el=FrameElementLinear2D(member['i']-1,member['j']-1,E=E,A=member['EA']*1000/E,
                                    I=member['EI']*1000/E,nodes=nodes,beam_theory='euler')
            dofs,kg,_,_=el.stiffness_and_force_global(np.zeros(dm.ndof))
            K[np.ix_(dofs,dofs)]+=kg;elements.append(el)
        for load in m.get('member_loads',[]):
            el=elements[load['member']-1];L,c,s=el._geom()
            if s!=0 or c!=1: raise ValueError('reference loads must be on left-to-right horizontal members')
            if load['type']=='udl': F[el.dofs()]+=el.equiv_nodal_load_global((0,1000*load['q']))
            else:
                t=load['a']/L
                H=np.array([0,(1-t)**2*(1+2*t),L*t*(1-t)**2,0,t*t*(3-2*t),-L*t*t*(1-t)])
                F[el.dofs()]+=rot2d(c,s).T@(1000*load['P']*H)
        for load in m.get('nodal_loads',[]):
            base=3*(load['node']-1)
            F[base:base+3]+=1000*np.array([load.get('Fx',0),load.get('Fy',0),load.get('M',0)])
        fixed=set()
        for support in m['supports']:
            for i,name in enumerate(('ux','uy','rz')):
                if support.get(name): fixed.add(3*(support['node']-1)+i)
        free=[i for i in range(dm.ndof) if i not in fixed]
        u=np.zeros(dm.ndof)
        if free: u[free]=np.linalg.solve(K[np.ix_(free,free)],F[free])
        r=(K@u-F)/1000
        reactions={}
        for support in m['supports']:
            base=3*(support['node']-1)
            reactions[str(support['node'])]={name:float(r[base+i]) if base+i in fixed else 0.0
                                              for i,name in enumerate(('Rx','Ry','Mz'))}
        case['reference']=dict(reactions=reactions,displacements=u.reshape((-1,3)).tolist())
    commit=subprocess.check_output(['git','-C',str(checkout),'rev-parse','HEAD'],text=True).strip()
    frame_file=checkout/'src/dc_solver/fem/frame2d.py'
    data=dict(dc_commit=commit,date=datetime.now(ZoneInfo('Europe/Berlin')).date().isoformat(),
        frame2d_sha256=hashlib.sha256(frame_file.read_bytes()).hexdigest(),beam_theory='euler',
        units='dc: N,m,N*m,rad; BeamCX: kN,m,kNm,rad. EA/EI/loads x1000 into dc; reactions /1000; u unchanged.',
        load_axes='dc UDL global per member length, horizontal loaded members only',cases=cases)
    args.output.write_text(json.dumps(data,indent=2,allow_nan=False)+'\n')
    print(f'Generated {len(cases)} cases; dc commit {commit}; numpy {np.__version__}; {args.output.stat().st_size} bytes')


if __name__=='__main__': main()
