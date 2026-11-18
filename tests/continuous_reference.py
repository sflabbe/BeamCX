"""Independent rational Euler beam reference. No Lua/Frame imports or calls.

Only joint rotations are unknown (all vertical translations are zero). Exact
SymPy rational stiffness and load vectors are solved for every full-load pattern.
Stationary deflection positions use rational polynomial root isolation.
"""
import itertools
import sympy as sp

X = sp.Symbol('x')
R = lambda x: sp.Rational(str(x))


class Reference:
    def __init__(self, p):
        self.p = p
        self.lengths = list(map(R, p['spans']))
        self.ei = R(p['EI'])
        n = len(self.lengths)
        K = sp.zeros(n+1)
        for i, L in enumerate(self.lengths):
            K[i,i] += 4*self.ei/L
            K[i+1,i+1] += 4*self.ei/L
            K[i,i+1] += 2*self.ei/L
            K[i+1,i] += 2*self.ei/L
        self.free = [i for i in range(n+1) if not (i==0 and p['left']=='FIX' or i==n and p['right']=='FIX')]
        self.inverse = K.extract(self.free, self.free).inv()

    def solve(self, loads):
        loads = list(map(R, loads))
        n = len(self.lengths)
        rhs = sp.zeros(n+1, 1)
        for i, (L, q) in enumerate(zip(self.lengths, loads)):
            rhs[i] -= q*L**2/12
            rhs[i+1] += q*L**2/12
        theta = [sp.S.Zero]*(n+1)
        solution = self.inverse*rhs.extract(self.free, [0])
        for i, value in zip(self.free, solution):
            theta[i] = value
        reactions = [sp.S.Zero]*(n+1)
        spans = []
        for i, (L, q) in enumerate(zip(self.lengths, loads)):
            M = -(4*self.ei*theta[i]/L+2*self.ei*theta[i+1]/L+q*L**2/12)
            V = 6*self.ei*(theta[i]+theta[i+1])/L**2+q*L/2
            reactions[i] += V
            reactions[i+1] += q*L-V
            # Down-positive physical deflection, derived from EI*w_up'' = M.
            w = -(theta[i]*X+M*X**2/(2*self.ei)+V*X**3/(6*self.ei)-q*X**4/(24*self.ei))
            assert sp.expand(w).subs(X,L)==0 and w.subs(X,0)==0
            spans.append(dict(L=L, q=q, M=M, V=V, w=sp.Poly(w,X)))
        moments = [spans[0]['M']]+[s['M']+s['V']*s['L']-s['q']*s['L']**2/2 for s in spans]
        return dict(spans=spans, reactions=reactions, moments=moments)

    @staticmethod
    def at(s, x):
        x=R(x)
        return (s['M']+s['V']*x-s['q']*x**2/2, s['V']-s['q']*x, s['w'].eval(x))

    @staticmethod
    def extrema(s, deflection=False):
        L=s['L']
        candidates=[sp.S.Zero,L]
        if deflection:
            derivative=s['w'].diff()
            if not derivative.is_zero:
                for (lo,hi), multiplicity in derivative.intervals(eps=sp.Rational(1,10**28)):
                    root=(lo+hi)/2
                    if 0<root<L:
                        candidates.append(root)
            values=[float(s['w'].eval(x)) for x in candidates]
        else:
            if s['q'] and 0<s['V']/s['q']<L:
                candidates.append(s['V']/s['q'])
            values=[float(s['M']+s['V']*x-s['q']*x*x/2) for x in candidates]
        minimum=min(range(len(values)), key=values.__getitem__)
        maximum=max(range(len(values)), key=values.__getitem__)
        return dict(lo=values[minimum],xlo=float(candidates[minimum]),hi=values[maximum],xhi=float(candidates[maximum]))

    def envelope(self):
        p=self.p
        n=len(self.lengths)
        spans=[dict() for _ in self.lengths]
        supports=[dict() for _ in range(n+1)]
        grid=[dict(Mmax=-float('inf'),Mmin=float('inf'),Vmax=-float('inf'),Vmin=float('inf')) for _ in range(n*101)]
        vabs=0
        def set_extreme(target,key,value,x,pattern,gamma,maximum):
            if key not in target or (value>target[key]['value'] if maximum else value<target[key]['value']):
                target[key]=dict(value=value,x=x,pattern=pattern,gammaG=gamma)
        for active in itertools.product((0,1),repeat=n):
            name='-'.join(str(i+1) for i,a in enumerate(active) if a) or '-'
            characteristic_result=self.solve([R(p['g'])+a*R(p['q']) for a in active])
            for i,s in enumerate(characteristic_result['spans']):
                e=self.extrema(s,True)
                set_extreme(spans[i],'down',max(0,e['hi']),e['xhi'],name,None,True)
                set_extreme(spans[i],'up',min(0,e['lo']),e['xlo'],name,None,False)
            for gamma in (p.get('gG_sup',1.35),p.get('gG_inf',1)):
                sol=self.solve([R(gamma)*R(p['g'])+R(p.get('gQ',1.5))*a*R(p['q']) for a in active])
                for i,s in enumerate(sol['spans']):
                    e=self.extrema(s)
                    set_extreme(spans[i],'Mmax',e['hi'],e['xhi'],name,gamma,True)
                    vabs=max(vabs,abs(float(s['V'])),abs(float(s['V']-s['q']*s['L'])))
                    for j in range(101):
                        M,V,_=self.at(s,s['L']*j/100)
                        point=grid[i*101+j]
                        for key,v in (('Mmax',M),('Mmin',M),('Vmax',V),('Vmin',V)):
                            point[key]=(max if key.endswith('max') else min)(point[key],float(v))
                for i in range(n+1):
                    for key,value,maximum in (('Mmin',sol['moments'][i],False),('Rmax',sol['reactions'][i],True),('Rmin',sol['reactions'][i],False)):
                        set_extreme(supports[i],key,float(value),0,name,gamma,maximum)
        return dict(spans=spans,supports=supports,grid=grid,vabs=vabs)
