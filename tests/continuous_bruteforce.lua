-- Test-only exhaustive oracle. Appended to the P5A harness with Frame/C/random_cases.
-- Every ULS pattern and both global gammaG choices; every characteristic pattern.
local worst={M=0,V=0,R=0,w=0,position=0,summary=0}
local total_patterns,total_spans=0,0
local function check(kind,got,want,scale,context)
    local err=math.abs(got-want)/math.max(scale,1e-300)
    worst[kind]=math.max(worst[kind],err)
    assert(got==got and err<=1e-9,context..' '..kind..' '..string.format('%.17g vs %.17g err %.6g',got,want,err))
end
local function bound(values,v,x,name,gamma,maximum)
    if not values or (maximum and v>values.value) or (not maximum and v<values.value) then
        return {value=v,x=x,pattern=name,gammaG=gamma}
    end
    return values
end
local function brute(p,bases)
    local n=#p.spans
    local spans,supports,points={},{},{}
    for i=1,n do
        spans[i]={};points[i]={}
        for j=1,5 do points[i][j]={Mmax=-math.huge,Mmin=math.huge,Vmax=-math.huge,Vmin=math.huge} end
    end
    for i=1,n+1 do supports[i]={} end
    local out={spans=spans,supports=supports,points=points,vabs=0}
    local function moment(v,x,i)
        if (i==1 and x==0 and p.left=='PIN') or (i==n and x==p.spans[i] and p.right=='PIN') then return 0 end
        return v
    end
    for mask=0,2^n-1 do
        total_patterns=total_patterns+1
        local names,factors={},{1}
        for i=1,n do
            factors[i+1]=math.floor(mask/2^(i-1))%2
            if factors[i+1]==1 then names[#names+1]=tostring(i) end
        end
        local name=#names>0 and table.concat(names,'-') or '-'
        local car=assert(Frame.combine(bases,factors))
        for i,L in ipairs(p.spans) do
            local lo,xlo,hi,xhi=Frame.deflection_extrema(car,i)
            xlo=math.max(0,math.min(L,xlo));xhi=math.max(0,math.min(L,xhi))
            if xlo==0 or xlo==L then lo=0 end
            if xhi==0 or xhi==L then hi=0 end
            spans[i].down=bound(spans[i].down,math.max(0,-lo),xlo,name,nil,true)
            spans[i].up=bound(spans[i].up,math.min(0,-hi),xhi,name,nil,false)
        end
        for _,gamma in ipairs{p.gG_sup,p.gG_inf} do
            local ultimate={gamma}
            for j=2,#factors do ultimate[j]=p.gQ*factors[j] end
            local sol=assert(Frame.combine(bases,ultimate))
            for i,L in ipairs(p.spans) do
                local lo,xlo,hi,xhi=Frame.moment_extrema(sol,i)
                xlo=math.max(0,math.min(L,xlo));xhi=math.max(0,math.min(L,xhi))
                spans[i].Mmax=bound(spans[i].Mmax,moment(hi,xhi,i),xhi,name,gamma,true)
                spans[i].Mmin=bound(spans[i].Mmin,moment(lo,xlo,i),xlo,name,gamma,false)
                for j,t in ipairs{0,.211,.5,.789,1} do
                    local x=L*t
                    local v=Frame.at(sol,i,x,t==0 and 'right' or 'left')
                    local point=points[i][j]
                    point.Mmax=math.max(point.Mmax,v.M);point.Mmin=math.min(point.Mmin,v.M)
                    point.Vmax=math.max(point.Vmax,v.V);point.Vmin=math.min(point.Vmin,v.V)
                    if t==0 or t==1 then out.vabs=math.max(out.vabs,math.abs(v.V)) end
                end
            end
            for node,s in ipairs(supports) do
                local i=node==1 and 1 or node-1
                local x=node==1 and 0 or p.spans[i]
                local M=moment(Frame.at(sol,i,x,x==0 and 'right' or 'left').M,x,i)
                local R=sol.reactions[node].Ry
                s.Mmax=bound(s.Mmax,M,0,name,gamma,true);s.Mmin=bound(s.Mmin,M,0,name,gamma,false)
                s.Rmax=bound(s.Rmax,R,0,name,gamma,true);s.Rmin=bound(s.Rmin,R,0,name,gamma,false)
            end
        end
    end
    return out
end
for case,p in ipairs(random_cases) do
    local context='random '..case
    local solve,combine=Frame.solve,Frame.combine
    local ns,nc=0,0
    Frame.solve=function(m) ns=ns+1;return solve(m) end
    Frame.combine=function(s,f) nc=nc+1;return combine(s,f) end
    local got=assert(C.solve(p))
    Frame.solve,Frame.combine=solve,combine
    assert(ns==#p.spans+1 and nc==2,context..' work must stay n+1 solves / two combinations')
    local want=brute(p,got.bases)
    local length=got.supports[#got.supports].position
    local F=(math.abs(p.g)+math.abs(p.q))*length
    local Mscale,Vscale,Wscale=1e-6*F*length,1e-6*F,1e-6*F*length^3/p.EI
    for _,s in ipairs(want.spans) do
        Mscale=math.max(Mscale,math.abs(s.Mmax.value),math.abs(s.Mmin.value))
        Wscale=math.max(Wscale,math.abs(s.down.value),math.abs(s.up.value))
    end
    for _,s in ipairs(want.supports) do Vscale=math.max(Vscale,math.abs(s.Rmax.value),math.abs(s.Rmin.value)) end
    local function response(rec,i,key,characteristic)
        local active=number_pattern(rec.pattern,#p.spans)
        local gamma=characteristic and 1 or rec.gammaG
        if not characteristic then assert(gamma==p.gG_sup or gamma==p.gG_inf,context..' gamma') end
        local value=gamma*Frame.at(got.bases[1],i,rec.x,rec.x==0 and 'right' or 'left')[key]
        for j=1,#p.spans do
            if active[j] then value=value+(characteristic and 1 or p.gQ)*Frame.at(got.bases[j+1],i,rec.x,rec.x==0 and 'right' or 'left')[key] end
        end
        return characteristic and -value or value
    end
    local offset,maxM,minM,maxR,maxW=0,-math.huge,math.huge,-math.huge,0
    for i,L in ipairs(p.spans) do
        total_spans=total_spans+1
        local g,w=got.spans[i],want.spans[i]
        for _,key in ipairs{'Mmax','Mmin'} do
            check('M',g[key].value,w[key].value,Mscale,context..' '..i..' '..key)
            assert(g[key].x>=0 and g[key].x<=L,context..' x range')
            check('position',response(g[key],i,'M'),w[key].value,Mscale,context..' moment position/pattern')
            assert(g[key].position==offset+g[key].x)
        end
        if w.Mmax.value>0 then assert(g.Mplus and g.Mplus==g.Mmax) else assert(g.Mplus==nil) end
        maxM=math.max(maxM,w.Mmax.value);minM=math.min(minM,w.Mmin.value)
        for _,key in ipairs{'down','up'} do
            check('w',g.deflection[key].value,w[key].value,Wscale,context..' '..i..' '..key)
            check('position',response(g.deflection[key],i,'w',true),w[key].value,Wscale,context..' deflection position/pattern')
            assert(g.deflection[key].position==offset+g.deflection[key].x)
        end
        local absw=math.max(math.abs(w.down.value),math.abs(w.up.value))
        maxW=math.max(maxW,absw)
        check('w',g.deflection.governing.absolute,absw,Wscale,context..' governing')
        if absw==0 then assert(g.deflection.ratio==nil and g.deflection.status=='N/A')
        else
            check('w',L/g.deflection.ratio,absw,Wscale,context..' ratio')
            assert(g.deflection.status==(absw/(L/p.limit)<=1+1e-12 and 'OK' or 'EXCEEDED'))
        end
        for j,t in ipairs{0,.211,.5,.789,1} do
            local v=got.envelope_at(offset+L*t,t==0 and 'right' or 'left')
            for _,key in ipairs{'Mmax','Mmin','Vmax','Vmin'} do
                check(key:sub(1,1),v[key],want.points[i][j][key],key:sub(1,1)=='M' and Mscale or Vscale,context..' point envelope')
            end
        end
        offset=offset+L
    end
    for node,s in ipairs(got.supports) do
        for _,key in ipairs{'Mmax','Mmin','Rmax','Rmin'} do
            local scale=key:sub(1,1)=='M' and Mscale or Vscale
            check(key:sub(1,1),s[key].value,want.supports[node][key].value,scale,context..' support '..key)
            local active=number_pattern(s[key].pattern,#p.spans)
            local i=node==1 and 1 or node-1
            local x=node==1 and 0 or p.spans[i]
            local function base_value(base)
                return key:sub(1,1)=='M' and Frame.at(base,i,x,x==0 and 'right' or 'left').M or base.reactions[node].Ry
            end
            local actual=s[key].gammaG*base_value(got.bases[1])
            for j=1,#p.spans do if active[j] then actual=actual+p.gQ*base_value(got.bases[j+1]) end end
            check('position',actual,want.supports[node][key].value,scale,context..' support pattern/gamma')
        end
        maxR=math.max(maxR,want.supports[node].Rmax.value)
    end
    check('V',got.shear.value,want.vabs,Vscale,context..' Vabs')
    local summary=got.summary
    for _,row in ipairs{{summary.moment_max,maxM,Mscale},{summary.moment_min,minM,Mscale},{summary.reaction_max,maxR,Vscale},
                         {summary.shear_absolute_max,want.vabs,Vscale},{summary.deflection_absolute_max,maxW,Wscale}} do
        check('summary',row[1],row[2],row[3],context)
    end
    local found=false
    for _,s in ipairs(got.spans) do
        if s.deflection.governing.position==summary.deflection_position and s.deflection.governing.absolute==summary.deflection_absolute_max then found=true end
    end
    assert(found and summary.rigidity==p.EI and summary.span_count==#p.spans)
end
assert(#random_cases>=300)
for _,key in ipairs{'M','V','R','w','position','summary'} do print(string.format('P5A.1 RANDOM MAX | %s | %.17g',key,worst[key])) end
print(string.format('PASS P5A.1 brute force: cases=%d spans=%d patterns=%d; all quantities/patterns/positions; n+1 solves and exactly two combinations',#random_cases,total_spans,total_patterns))
local regression={spans={6.741127285017325,3.043382368681142,9.32755849384785},left='FIX',right='PIN',
    g=12.111990602786538,q=18.185486163687962,EI=20000,gG_sup=1.35,gG_inf=1,gQ=1.5}
local result=assert(C.solve(regression))
local b=result.supports[2].Mmax
check('M',b.value,28.081141172746,math.abs(28.081141172746),'positive support B')
assert(b.value>0 and b.pattern=='3' and b.gammaG==1)
local exhaustive=brute(regression,result.bases)
check('M',b.value,exhaustive.supports[2].Mmax.value,math.abs(b.value),'positive support B brute force')
print(string.format('PASS P5A.1 positive B: %.15g pattern=%s gammaG=%.2f',b.value,b.pattern,b.gammaG))
