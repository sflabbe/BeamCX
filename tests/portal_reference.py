"""Independent 12-DOF direct stiffness reference; no Lua or Frame data.

Decimal (50 digits) assembly/solution and exact rational polynomial root
isolation for chord-relative deflection. Same finite EA as the portal preset.
"""
from decimal import Decimal as D, localcontext

import sympy as sp


def zeros(n, m):
    return [[D(0) for _ in range(m)] for _ in range(n)]


def transpose(a):
    return list(map(list, zip(*a)))


def multiply(a, b):
    return [[sum(x*y for x, y in zip(row, col)) for col in zip(*b)] for row in a]


def linear_solve(a, b):
    rows = [row[:] + [rhs] for row, rhs in zip(a, b)]
    for col in range(len(rows)):
        pivot = max(range(col, len(rows)), key=lambda i: abs(rows[i][col]))
        rows[col], rows[pivot] = rows[pivot], rows[col]
        for i in range(col+1, len(rows)):
            factor = rows[i][col]/rows[col][col]
            for j in range(col, len(rows)+1):
                rows[i][j] -= factor*rows[col][j]
    x = [D(0)]*len(rows)
    for i in reversed(range(len(rows))):
        x[i] = (rows[i][-1]-sum(rows[i][j]*x[j] for j in range(i+1, len(rows))))/rows[i][i]
    return x


def real_roots(coefficients, length):
    """All roots in (0,length), including repeated roots, by rational isolation."""
    x = sp.Symbol('x')
    poly = sp.Poly(sum(sp.Rational(str(c))*x**i for i, c in enumerate(coefficients)), x)
    if poly.is_zero:
        return []
    out = []
    for (lo, hi), _multiplicity in sp.polys.polytools.intervals(poly, eps=sp.Rational(1, 10**25)):
        root = D(str(sp.N((lo+hi)/2, 45)))
        if 0 < root < length:
            out.append(root)
    return out


class Reference:
    def __init__(self, parameters):
        with localcontext() as ctx:
            ctx.prec = 50
            self.p = {k: v if k == 'base' else D(str(v)) for k, v in parameters.items()}
            p = self.p
            h, l = p['h'], p['l']
            self.nodes = [(0, 0), (0, h), (l, h), (l, 0)]
            K, F = zeros(12, 12), [D(0)]*12
            self.members = []
            for number, (i, j, EI, q, point) in enumerate([
                    (0, 1, p['EIc'], -p['w'], D(0)),
                    (1, 2, p['EIb'], -p['q'], -p['P']),
                    (3, 2, p['EIc'], D(0), D(0))]):
                dx = self.nodes[j][0]-self.nodes[i][0]
                dy = self.nodes[j][1]-self.nodes[i][1]
                L = (dx*dx+dy*dy).sqrt()
                c, s = dx/L, dy/L
                EA = D(1000000)*EI/L**2
                k = zeros(6, 6)
                k[0][0] = k[3][3] = EA/L
                k[0][3] = k[3][0] = -EA/L
                bending = [[12, 6*L, -12, 6*L], [6*L, 4*L**2, -6*L, 2*L**2],
                           [-12, -6*L, 12, -6*L], [6*L, 2*L**2, -6*L, 4*L**2]]
                for u, a in enumerate([1, 2, 4, 5]):
                    for v, b in enumerate([1, 2, 4, 5]):
                        k[a][b] = EI/L**3*bending[u][v]
                T = [[c, s, 0, 0, 0, 0], [-s, c, 0, 0, 0, 0], [0, 0, 1, 0, 0, 0],
                     [0, 0, 0, c, s, 0], [0, 0, 0, -s, c, 0], [0, 0, 0, 0, 0, 1]]
                fe = [D(0), q*L/2, q*L**2/12, D(0), q*L/2, -q*L**2/12]
                a = p['a'] if number == 1 else D(0)
                t = a/L
                shape = [(1-t)**2*(1+2*t), L*t*(1-t)**2, t**2*(3-2*t), -L*t*t*(1-t)]
                for d, v in zip([1, 2, 4, 5], shape):
                    fe[d] += point*v
                kg = multiply(transpose(T), multiply(k, T))
                fg = multiply(transpose(T), [[v] for v in fe])
                dofs = [3*i, 3*i+1, 3*i+2, 3*j, 3*j+1, 3*j+2]
                for u, d in enumerate(dofs):
                    F[d] += fg[u][0]
                    for v, e in enumerate(dofs):
                        K[d][e] += kg[u][v]
                self.members.append(dict(L=L, EI=EI, q=q, P=point, a=a, k=k, T=T, fe=fe, dofs=dofs))
            F[3] += p['H']
            fixed = {0, 1, 9, 10} | ({2, 11} if p['base'] == 'FIX' else set())
            free = [d for d in range(12) if d not in fixed]
            u = [D(0)]*12
            for d, value in zip(free, linear_solve([[K[i][j] for j in free] for i in free], [F[i] for i in free])):
                u[d] = value
            self.u = u
            self.reactions = [sum(K[i][j]*u[j] for j in range(12))-F[i] for i in range(12)]
            for m in self.members:
                m['u'] = [row[0] for row in multiply(m['T'], [[u[d]] for d in m['dofs']])]
                m['f'] = [sum(row[j]*m['u'][j] for j in range(6))-m['fe'][i] for i, row in enumerate(m['k'])]

    def at(self, member, s, side='left'):
        with localcontext() as ctx:
            ctx.prec = 50
            s = D(str(s))
            m = self.members[member-1]
            f, u, q, P, a, EI = (m[k] for k in ('f', 'u', 'q', 'P', 'a', 'EI'))
            crossed = s > a or (s == a and side == 'right')
            distance = max(D(0), s-a)
            return dict(N=-f[0], V=f[1]+q*s+(P if crossed else 0),
                        M=-f[2]+f[1]*s+q*s*s/2+P*distance,
                        w=u[1]+u[2]*s+(-f[2]*s*s/2+f[1]*s**3/6+q*s**4/24+P*distance**3/6)/EI)

    def relative(self, s):
        L = self.p['l']
        s = D(str(s))
        return self.at(2, s)['w']-(1-s/L)*self.at(2, 0)['w']-s/L*self.at(2, L)['w']

    def extrema(self, member):
        with localcontext() as ctx:
            ctx.prec = 50
            m = self.members[member-1]
            L = m['L']
            cuts = sorted({D(0), L} | ({m['a']} if m['P'] != 0 else set()))
            positions = cuts[:]
            for a, b in zip(cuts, cuts[1:]):
                v = self.at(member, a, 'right')
                if m['q'] != 0:
                    x = -v['V']/m['q']
                    if 0 < x < b-a:
                        positions.append(a+x)
            moments = [dict(value=self.at(member, s)['M'], position=s) for s in positions]
            return dict(minimum=min(moments, key=lambda v: v['value']), maximum=max(moments, key=lambda v: v['value']))

    def deflection(self):
        with localcontext() as ctx:
            ctx.prec = 50
            m = self.members[1]
            L, EI = m['L'], m['EI']
            chord = (self.at(2, L)['w']-self.at(2, 0)['w'])/L
            positions = [D(0), L]
            cuts = sorted({D(0), L} | ({m['a']} if m['P'] != 0 else set()))
            for a, b in zip(cuts, cuts[1:]):
                distance = max(D(0), a-m['a'])
                theta = m['u'][2]+(-m['f'][2]*a+m['f'][1]*a*a/2+m['q']*a**3/6+m['P']*distance**2/2)/EI
                v = self.at(2, a, 'right')
                positions += [a+x for x in real_roots([theta-chord, v['M']/EI, v['V']/(2*EI), m['q']/(6*EI)], b-a)]
                positions.append(a)
            s = max(positions, key=lambda x: abs(self.relative(x)))
            value = self.relative(s)
            return dict(value=value, absolute=abs(value), position=s)

    def export(self):
        return dict(reactions=[dict(H=self.reactions[d], V=self.reactions[d+1], M=self.reactions[d+2]) for d in (0, 9)],
                    drift=dict(left=self.u[3], right=self.u[6]), deflection=self.deflection(),
                    members=[dict(moments=self.extrema(i), N=self.at(i, 0)['N']) for i in range(1, 4)])
