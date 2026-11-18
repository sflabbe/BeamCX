"""Frozen v0.3.3 fixture input provenance and Lua literal serialization.

The legacy solver and its live-output generator were retired in v0.4.0.
The versioned golden and independent adjudication remain the authorities.
"""
import json
from pathlib import Path
import random

ROOT = Path(__file__).resolve().parent.parent
SEED = 20261118


def literal(value):
    if value is None:
        return 'nil'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, (float, int)):
        return repr(value)
    if isinstance(value, list):
        return '{' + ','.join(literal(v) for v in value) + '}'
    return '{' + ','.join('[' + literal(k) + ']=' + literal(v) for k, v in value.items()) + '}'


def cases():
    rng = random.Random(SEED)
    out = []
    for i in range(2000):
        L = 1 + 11*rng.random()
        p = dict(L=L, q=-30+60*rng.random(), P=-50+100*rng.random(),
                 a=L*rng.random(), EI=1000+99000*rng.random(), support=1+int(4*rng.random()))
        if i % 20 < 3:
            p['q'] = 0
        if 7 <= i % 20 <= 9:
            p['P'] = 0
        if i % 40 == 0:
            p['a'] = 0
        elif i % 40 == 20:
            p['a'] = L
        out.append(dict(name=f'random_{i:04d}', p=p, limit=250 if rng.random()<.5 else 300,
                        lref_factor=1 if rng.random()<.5 else 2.5, valid=True))
    for support in range(1,5):
        p=dict(L=6,q=10,P=0,a=3,EI=10000,support=support)
        out.append(dict(name=f'P0_{support}',p=p,limit=250,lref_factor=1,valid=True))
        out.append(dict(name=f'zero_{support}',p=dict(p,q=0),limit=300,lref_factor=2.5,valid=True))
        for a in (1e-7,6-1e-7):
            out.append(dict(name=f'near_{support}_{a}',p=dict(p,q=0,P=12,a=a),
                            limit=250,lref_factor=1,valid=True))
    base=dict(L=6,q=10,P=12,a=2,EI=10000,support=1)
    bad=[('L',0),('L',-1),('a',-1),('a',7),('EI',0),('EI',-1),('support',0),('support',5)]
    bad += [(key,value) for key in base for value in ('@nan','@inf','@-inf')]
    for i,(key,value) in enumerate(bad):
        out.append(dict(name=f'invalid_{i:02d}_{key}',p=dict(base,**{key:value}),
                        limit=250,lref_factor=1,valid=False))
    return out
