local load_ui=dofile(root..'/tests/load_ui.lua')
local width,height=318,212
local running=false
platform={window={width=function() return width end,height=function() return height end,invalidate=function() end}}
timer={start=function() running=true end,stop=function() running=false end}
local gc=dofile(root..'/tests/portal_graphics.lua')(function() return width end,function() return height end)
local function state() return _BX_TEST_STATE() end
local function fresh() on=nil;running=false;load_ui(root..'/BeamCX.lua') end
local function same(a,b)
    assert(type(a)==type(b),'type mismatch')
    if type(a)~='table' then assert(a==b,tostring(a)..' != '..tostring(b));return end
    for k,v in pairs(a) do same(v,b[k]) end
    for k in pairs(b) do assert(a[k]~=nil,'extra '..tostring(k)) end
end
local function copy(t)
    if type(t)~='table' then return t end
    local out={};for k,v in pairs(t) do out[k]=copy(v) end;return out
end
local function eq(a,b,tol) assert(math.abs(a-b)<=(tol or 1e-10)*math.max(1,math.abs(b)),tostring(a)..' != '..tostring(b)) end
local function contains(text,s) assert(text:find(s,1,true),s..' absent from '..text) end
local function paint()
    local f,p,at=Frame.solve,PortalPreset.solve,PortalPreset.at
    Frame.solve=function() error('paint solved Frame') end
    PortalPreset.solve=function() error('paint solved Portal') end
    PortalPreset.at=function() error('paint recovered Portal') end
    local fat=Frame.at;Frame.at=function() error('paint recovered Frame') end
    gc:reset();on.paint(gc)
    Frame.solve=f;PortalPreset.solve=p;PortalPreset.at=at;Frame.at=fat
    local texts={};for _,t in ipairs(gc.texts) do texts[#texts+1]=t.t end
    return table.concat(texts,'\n')
end
local function open()
    on.arrowUp();on.arrowLeft();on.arrowLeft();on.arrowRight();on.arrowRight();on.arrowDown()
    assert(state().sel_index==6);on.enterKey()
    assert(state().support==6 and state().page==1 and not running)
end
local function field(index)
    while state().edit_index<index do on.arrowDown() end
    while state().edit_index>index do on.arrowUp() end
end
local function input()
    while state().page~=1 do on.tabKey() end
end
local function edit(text)
    for ch in text:gmatch('.') do on.charIn(ch) end
    on.enterKey()
end
local function calculate()
    local fs,ps=Frame.solve,PortalPreset.solve
    local nf,np=0,0
    Frame.solve=function(p) nf=nf+1;return fs(p) end
    PortalPreset.solve=function(p) np=np+1;return ps(p) end
    on.tabKey();assert(state().page==2 and running and state().calculating)
    contains(paint(),'Calculating...');assert(nf==0 and np==0)
    on.timer();assert(not running and state().result and state().samples and not state().stale)
    assert(nf==1 and np==1,'exactly one productive solve required')
    Frame.solve=fs;PortalPreset.solve=ps
    local effective=copy(on.save().portal)
    if state().portal_beam_self_weight then effective.q=effective.q+DB.compute(state().portal_sections.beam).q_sw end
    local reference=assert(ps(effective))
    same(reference.reactions,state().result.reactions)
    same(reference.members,state().result.members)
    same(reference.corners,state().result.corners)
    same(reference.drift,state().result.drift)
    same(reference.deflection,state().result.deflection)
    return state().result
end
local function expected_export(sol)
    local mmax,mmin,nabs,vabs=-math.huge,math.huge,0,0
    for i,m in ipairs(sol.members) do
        mmax=math.max(mmax,m.moments.maximum.value);mmin=math.min(mmin,m.moments.minimum.value)
        nabs=math.max(nabs,m.axial.absolute)
        local L=i==2 and sol.parameters.l or sol.parameters.h
        vabs=math.max(vabs,math.abs(PortalPreset.at(sol,i,0,'right').V),math.abs(PortalPreset.at(sol,i,L,'left').V))
        if i==2 and sol.parameters.P~=0 and sol.parameters.a>0 and sol.parameters.a<L then
            for _,side in ipairs{'left','right'} do vabs=math.max(vabs,math.abs(PortalPreset.at(sol,2,sol.parameters.a,side).V)) end
        end
    end
    local l,r=sol.reactions.left,sol.reactions.right
    return {bp_hl=l.H,bp_vl=l.V,bp_ml=l.M or 0,bp_hr=r.H,bp_vr=r.V,bp_mr=r.M or 0,
        bp_mmax=mmax,bp_mmin=mmin,bp_nabs=nabs,bp_vabs=vabs,
        bp_dxl=sol.drift.left*1000,bp_dxr=sol.drift.right*1000,
        bp_wrel=sol.deflection.value*1000,bp_xwrel=sol.deflection.position}
end
local function export()
    on.enterKey();assert(on.save().mode==5)
    local values,count={},0
    var={store=function(k,v) count=count+1;assert(k:sub(1,3)=='bp_');values[k]=v end}
    local fs=Frame.solve;Frame.solve=function() error('export solved') end
    on.enterKey();Frame.solve=fs
    same(values,expected_export(state().result));assert(count==14)
    assert(state().export_message=='CAS: 14 variables stored')
    return values
end
fresh();paint();local defaults=on.save();open()
-- Inputs and transactionality: all ten fields, full precision, no immediate solve.
local f=Frame.solve;Frame.solve=function() error('input solved') end
field(1);on.arrowLeft();assert(on.save().portal.base=='PIN');on.arrowRight()
for _,item in ipairs{{2,'4.123456789012345','h'},{3,'7.125','l'},{4,'11000.123456789','EIc'},
    {5,'17000.987654321','EIb'},{6,'-8.75','q'},{7,'17.125','P'},{8,'2.375','a'},
    {9,'-9.5','H'},{10,'6.25','w'}} do
    field(item[1]);edit(item[2]);assert(on.save().portal[item[3]]==tonumber(item[2]));paint()
end
local valid=on.save().portal
for _,item in ipairs{{2,'0'},{3,'-1'},{4,'0'},{5,'0'},{8,'99'}} do
    field(item[1]);edit(item[2]);same(on.save().portal,valid);assert(state().err);paint()
end
field(6);on.charIn('9');on.escapeKey();same(on.save().portal,valid)
Frame.solve=f
field(6);edit('-8.75');local result=calculate();export()
local saved=on.save();local old_samples=state().samples
input();field(6);edit('-8.75');assert(state().samples==old_samples and not state().stale)
field(2);edit('0');assert(state().result==result and state().samples==old_samples)
contains(paint(),'invalid h');on.tabKey();assert(not running);input()
-- Inactive a resets only with P=0; active a makes shortening fail.
field(7);edit('0');field(8);edit('7');field(3);edit('4')
eq(on.save().portal.a,2);field(7);edit('4');field(8);edit('3.5');field(3);edit('3')
eq(on.save().portal.l,4);eq(on.save().portal.a,3.5)
field(3);edit('4');result=calculate()
print('PASS portal inputs: ten fields, validation, precision, inactive a, deferred lifecycle')

-- Physical UI witnesses, including combined loads for both base options.
for _,case in ipairs{
    {base='FIX',q=10,P=0,a=3,H=0,w=0},
    {base='PIN',q=0,P=0,a=3,H=0,w=10},
    {base='PIN',q=0,P=0,a=3,H=10,w=0},
    {base='PIN',q=8,P=17,a=2.2,H=11,w=6},
    {base='FIX',q=8,P=17,a=2.2,H=11,w=6}
} do
    local doc=copy(defaults);doc.params.support=6;doc.page=1
    for k,v in pairs(case) do doc.portal[k]=v end
    on.restore(doc);result=calculate()
    if case.base=='FIX' and case.P==0 then
        eq(result.reactions.left.V,30);eq(result.reactions.right.V,30)
        eq(math.abs(result.reactions.left.M),10,5e-5);eq(math.abs(result.corners.left.beam),20,5e-5)
    elseif case.w==10 then eq(result.reactions.left.H,-29,5e-5);eq(result.reactions.right.H,-11,5e-5)
    elseif case.H==10 then eq(result.drift.left,.016,5e-5) end
    export()
    local rows=state().samples.table;local format=state().format_number
    assert(#rows==32)
    assert(rows[1][1]=='Columns' and rows[2][1]=='Beam' and rows[3][1]=='Self-weight')
    assert(rows[4][2]==format(result.reactions.left.H) and rows[8][2]==format(result.reactions.right.V))
    assert(rows[6][2]==(result.reactions.left.M and format(result.reactions.left.M) or '—'))
    assert(rows[22][2]==format(result.corners.left.column) and rows[25][2]==format(result.corners.right.beam))
    assert(rows[26][2]==format(result.drift.left*1000) and rows[28][2]==format(result.drift.right*1000))
    assert(rows[30][2]==format(result.deflection.value*1000) and rows[32][2]==format(result.deflection.position))
    -- At least one exported value keeps precision beyond the display string.
    assert(result.drift.left*1000~=tonumber(state().format_number(result.drift.left*1000)))
end
print('PASS portal UI witnesses A/B/C and combined PIN/FIX; 14 unrounded CAS values')

-- All diagram data is cached; movement has exactly one local recovery query.
on.arrowRight();assert(on.save().mode==1)
local queries,solves=0,0
local at,solve,psolve=PortalPreset.at,Frame.solve,PortalPreset.solve
PortalPreset.at=function(...) queries=queries+1;return at(...) end
Frame.solve=function(...) solves=solves+1;return solve(...) end
PortalPreset.solve=function() error('navigation solved preset') end
for member=1,3 do
    on.charIn(tostring(member));local s=state()
    assert(s.portal_member==member)
    same(s.cursor_value,at(s.result,member,s.portal_s,s.portal_side))
    for _=1,24 do
        local before=queries;local old=state().portal_s;local side=state().portal_side
        on.arrowUp();local now=state()
        assert(queries-before==((now.portal_s~=old or now.portal_side~=side) and 1 or 0))
        same(now.cursor_value,at(now.result,member,now.portal_s,now.portal_side))
        paint()
    end
    for _=1,24 do on.arrowDown() end
    assert(state().portal_s==0)
end
for mode=1,5 do paint();on.arrowRight() end
on.enterKey();for _=1,35 do paint();on.arrowDown() end
for _=1,35 do on.arrowUp();paint() end
assert(solves==0)
PortalPreset.at=at;Frame.solve=solve;PortalPreset.solve=psolve
print('PASS portal cursor: IDs, local s, point sides, one query/movement; no solves or recovery during paint')

-- Exact sample cut and V jump; local/global displacement transformations.
local ss=state().samples
local beam=ss.members[2];local found=false
for i=1,#beam-1 do
    if beam[i].s==2.2 and beam[i+1].s==2.2 then
        assert(beam[i].side=='left' and beam[i+1].side=='right')
        eq(beam[i+1].V-beam[i].V,-17);found=true
    end
end
assert(found)
for i,data in ipairs(ss.members) do
    for _,v in ipairs(data) do
        if i==2 then assert(v.dx==v.u and v.dy==v.w) else assert(v.dx==-v.w and v.dy==v.u) end
    end
end
local function joint(a,b) eq(a.x+a.dx,b.x+b.dx);eq(a.y+a.dy,b.y+b.dy) end
joint(ss.members[1][#ss.members[1]],ss.members[2][1]);joint(ss.members[2][#ss.members[2]],ss.members[3][#ss.members[3]])
same(state().result.deflection,psolve(on.save().portal).deflection)
-- Find the actual vertical screen jump, and M endpoints on the tension side.
local function geometry()
    local p=on.save().portal;local scale=math.min((width-100)/p.l,(height-164)/p.h)
    return (width-p.l*scale)/2,height-82,scale
end
local function diagram_lines()
    local out={}
    for _,line in ipairs(gc.lines) do
        if line.color[1]==242 then out[#out+1]=line end
    end
    return out
end
on.arrowRight();assert(on.save().mode==1);paint()
local lines=diagram_lines();local offset=0;local left,bottom,scale=geometry()
for i,data in ipairs(ss.members) do
    local line=lines[offset+1];local v=data[1]
    if i==2 then eq(line[2],bottom-v.y*scale+18*v.M/ss.scales.M)
    else eq(line[1],left+v.x*scale+18*v.M/ss.scales.M) end
    offset=offset+#data-1+2
end
on.arrowRight();paint();local jump=false
for _,line in ipairs(diagram_lines()) do
    if math.abs(line[1]-(left+2.2*scale))<1e-8 and line[1]==line[3] and math.abs(line[2]-line[4])>1e-8 then jump=true end
end
assert(jump)
print('PASS portal plots: signed tension sides, exact shear jump, absolute deformed coordinates and joints, chord-relative authority')

-- Export failures and complete prevalidation; never report partial success.
on.enterKey();var=nil;on.enterKey();contains(state().export_message,'API unavailable')
for _,failure in ipairs{'return','throw'} do
    local writes=0
    var={store=function() writes=writes+1;if writes==7 then if failure=='throw' then error('blocked') else return 'blocked' end end end}
    on.enterKey();assert(writes==7);contains(state().export_message,'CAS ERROR')
end
local old=state().result.drift.left;state().result.drift.left=0/0
local writes=0;var={store=function() writes=writes+1 end};on.enterKey();assert(writes==0)
state().result.drift.left=old
print('PASS portal CAS error handling: missing API, partial return/exception, prevalidation before any store')

-- Full persistence and all-or-nothing rejection, including BOTH frozen v0.5 documents.
fresh();defaults=on.save()
for _,doc in ipairs(dofile(root..'/tests/fixtures/beam_v050_saved.lua')) do
    on.restore(doc);same(on.save(),defaults)
    assert(state().restore_notice=='Invalid document or version: defaults restored')
end
for _,support in ipairs{1,5,6} do
    local doc=copy(defaults);doc.params.support=support;doc.page=1
    doc.portal_sections.columns.manualEI=12345.123456789;doc.portal.EIc=12345.123456789
    doc.portal.H=-3.123456789;doc.portal_s=1.234567890123
    on.restore(doc);same(on.save(),doc)
end
local good=on.save()
for _,change in ipairs{{'format','0.5.0'},{'format','0.6.0'},{'portal',nil},{'portal_member',4},{'portal_s',99},{'portal_side','bad'},
    {'portal','h',0},{'portal','l',-1},{'portal','P',0/0},
    {'portal','a',7},{'continuous','q',false},{'params','L',0}} do
    local doc=copy(good)
    if #change==3 then doc[change[1]][change[2]]=change[3] else doc[change[1]]=change[2] end
    on.restore(doc);same(on.save(),defaults);assert(state().restore_notice)
end
good.page=2;good.mode=4;on.restore(good);assert(state().page==1 and state().stale and not running)
calculate();local roundtrip=on.save();on.restore(roundtrip);assert(state().page==1 and state().stale)
-- No solutions, samples or timers are serialized.
for _,key in ipairs{'result','frame','samples','calculating','portal_confirmed'} do assert(on.save()[key]==nil) end
print('PASS strict v0.6.1 persistence: precision round trips, v0.5/v0.6.0 rejected, malformed state reset atomically')

-- Deferred calculation failure returns the last confirmed portal parameters/result/cache.
calculate();local before=state();local model=on.save().portal
input();field(6);edit('7');local ps=PortalPreset.solve
PortalPreset.solve=function() return nil,'portal failure' end
on.tabKey();on.timer();PortalPreset.solve=ps
assert(state().page==1 and state().err=='portal failure' and state().result==before.result and state().samples==before.samples)
same(on.save().portal,model)
on.tabKey();assert(state().page==2 and not running)
-- Initial selector candidate failure rolls back the previous system atomically.
fresh();local initial=state();local initialsave=on.save();open()
PortalPreset.solve=function() error('initial portal failure') end
on.tabKey();on.timer();PortalPreset.solve=ps
assert(state().page==0 and state().support==1 and state().result==initial.result and state().selector_error)
same(on.save(),initialsave)
print('PASS portal deferred failures: previous portal and selector model restored transactionally')

-- Real drawing layouts, load reversals, all rows/modes at all requested sizes.
for _,size in ipairs{{318,212},{320,212},{320,240}} do
    width,height=size[1],size[2]
    fresh();paint();open()
    for i=1,10 do field(i);paint() end
    for _,base in ipairs{'PIN','FIX'} do for _,sign in ipairs{-1,0,1} do
        local doc=copy(defaults);doc.params.support=6;doc.page=1
        doc.portal.base=base;doc.portal.q=sign*8;doc.portal.P=sign*17;doc.portal.H=sign*11;doc.portal.w=sign*6;doc.portal.a=2.2
        on.restore(doc);calculate()
        for mode=1,4 do
            local text=paint();assert(#gc.polygons==(sign==0 and 0 or 8))
            local supports=0
            for _,line in ipairs(gc.lines) do if line.color[1]==91 then supports=supports+1 end end
            assert(supports==(base=='FIX' and 8 or 6),'incorrect base support drawing')
            for _,polygon in ipairs(gc.polygons) do
                local p=polygon.points
                local bx,by=(p[1]+p[3])/2,(p[2]+p[4])/2
                if p[6]~=by then assert((p[6]-by)*sign>0) else assert((p[5]-bx)*sign>0) end
            end
            if mode==4 then contains(text,'Magnification') end
            on.arrowRight()
        end
        if sign==0 then
            assert(state().samples.table[27][2]=='—' and state().samples.table[29][2]=='—' and state().samples.table[31][2]=='—')
        end
        for _=1,32 do paint();on.arrowUp() end
        for _=1,32 do on.arrowDown();paint() end
    end end
end
print('PASS portal layouts/arrows: 318x212, 320x212, 320x240; both bases, signed/zero loads, all modes and scroll rows')
-- P6C-R1 extends this same productive harness; no second renderer or solver.
local function sections()
    while state().page~=3 do on.tabKey() end
    assert(not running);paint()
end
local function section_field(key)
    while state().sec_index>1 do on.arrowUp() end
    while state().section_rows()[state().sec_index].key~=key do
        local old=state().sec_index;on.arrowDown()
        assert(state().sec_index~=old,'unreachable section field '..key)
    end
end
local function group(name)
    section_field('group')
    if state().portal_section_group~=name then on.arrowRight() end
    assert(state().portal_section_group==name)
end
local function catalogue_doc(case)
    local doc=copy(defaults);doc.params.support=6;doc.page=1
    doc.portal=copy(case.parameters);doc.portal.q=10
    for _,name in ipairs{'columns','beam'} do
        for k,v in pairs(case[name]) do doc.portal_sections[name][k]=v end
    end
    doc.portal_beam_self_weight=true
    -- Deliberately contradictory cached values: groups always prevail.
    doc.portal.EIc=-77;doc.portal.EIb=0
    return doc
end
fresh();defaults=on.save();assert(defaults.format=='0.6.1')
open();local baseline=assert(PortalPreset.solve(copy(defaults.portal)))
local default_result=calculate();same(default_result.reactions,baseline.reactions)
same(default_result.members,baseline.members);same(export(),expected_export(baseline))
eq(default_result.corners.left.beam,-20,5e-5)
eq(PortalPreset.at(default_result,2,3).M,25,5e-5)
eq(PortalPreset.at(default_result,2,3).N,-7.5,5e-5)
print('PASS P6C-R1 defaults: P6B reactions, member forces and all fourteen bp_* unchanged')

for _,case in ipairs(section_cases) do
    local doc=catalogue_doc(case);local untouched=copy(doc)
    on.restore(doc);same(doc,untouched)
    local columns,beam=DB.compute(doc.portal_sections.columns),DB.compute(doc.portal_sections.beam)
    assert(state().portal.EIc==columns.EI and state().portal.EIb==beam.EI)
    local sol=calculate();local ref=case.reference
    local p=sol.parameters;local force=math.abs(p.q*p.l)+math.abs(p.P)+math.abs(p.H)+math.abs(p.w*p.h)
    local length=math.max(p.h,p.l);local mscale=force*length
    local dscale=math.max(math.abs(ref.drift.left),math.abs(ref.drift.right),1e-6*force*length^3/math.min(p.EIc,p.EIb))
    local function reference_eq(actual,want,scale,tol)
        assert(math.abs(actual-want)<=(tol or 1e-9)*scale,case.name..': independent reference mismatch')
    end
    for i,side in ipairs{'left','right'} do
        for _,key in ipairs{'H','V','M'} do
            if sol.reactions[side][key] then reference_eq(sol.reactions[side][key],ref.reactions[i][key],key=='M' and mscale or force) end
        end
        reference_eq(sol.drift[side],ref.drift[side],dscale,case.displacement_tol)
    end
    for d=1,12 do reference_eq(sol.frame.u[d],ref.nodal_displacements[d],d%3==0 and dscale/length or dscale,case.displacement_tol) end
    for i,m in ipairs(sol.members) do
        reference_eq(m.axial.value,ref.members[i].N,force)
        for _,key in ipairs{'minimum','maximum'} do reference_eq(m.moments[key].value,ref.members[i].moments[key].value,mscale) end
    end
    reference_eq(sol.deflection.value,ref.deflection.value,math.max(ref.deflection.absolute,1e-6*force*p.l^3/p.EIb),case.displacement_tol)
    assert(p.EIc==columns.EI and p.EIb==beam.EI and p.q==10+beam.q_sw)
    assert(on.save().portal.q==10)
    same(export(),expected_export(sol));contains(paint(),'Self-weight')
    if case.kleinlogel then
        local k=case.kleinlogel
        eq(columns.EI,7753.2);eq(beam.EI,17547.6);eq(beam.q_sw,.413982);eq(p.q,10.413982)
        eq(k.k,1.508848,1e-6)
        eq(sol.corners.left.beam,k.corner,1e-4);eq(math.abs(sol.reactions.left.M),k.base,1e-4)
        eq(math.abs(sol.reactions.left.H),k.thrust,1e-4);eq(PortalPreset.at(sol,2,3).M,k.center,1e-4)
        eq(k.corner,-17.807523,1e-7);eq(k.base,8.903762,1e-7)
        eq(k.thrust,6.677821,1e-7);eq(k.center,29.055396,1e-7)
        on.arrowRight();contains(paint(),'sw=0.41')
        print(string.format('KLEINLOGEL | EIc=%.12g EIb=%.12g sw=%.12g total=%.12g k=%.12g corner=%.12g base=%.12g thrust=%.12g center=%.12g',
            columns.EI,beam.EI,beam.q_sw,p.q,k.k,sol.corners.left.beam,math.abs(sol.reactions.left.M),math.abs(sol.reactions.left.H),PortalPreset.at(sol,2,3).M))
    end
    for _=1,2 do
        on.restore(on.save());calculate()
        assert(on.save().portal.q==10 and state().result.parameters.q==10+beam.q_sw)
    end
    sections();group('columns');contains(paint(),'Excluded (axial)')
    local rows=state().section_rows()
    assert(rows[1].key=='group' and rows[#rows].key=='self_weight' and not rows[#rows].editable)
    for _,r in ipairs(rows) do assert(r.key~='limit') end
    group('beam');assert(state().portal_sections.columns.material==case.columns.material)
    local saved_group=on.save();on.restore(saved_group);same(on.save(),saved_group)
    assert(state().page==3 and state().portal_section_group=='beam' and not running)
    print('PASS section route + finite-EA Python reference: '..case.name)
end

-- All shared handlers, actual keyboard selection and the existing TAB cycle.
fresh();open();local solve=Frame.solve;Frame.solve=function() error('section page solved') end
sections();group('columns');section_field('manualEI');edit('11000.125')
assert(state().portal.EIc==11000.125 and state().portal.EIb==15000)
section_field('material');for _=1,4 do on.arrowRight() end
section_field('profile');for _=1,10 do on.arrowRight() end -- IPE 200 -> HEA 200
assert(state().portal_sections.columns.profile==16)
for _=1,12 do on.arrowDown() end -- excluded row is never focusable
assert(state().portal_beam_self_weight==false)
group('beam');section_field('material');for _=1,4 do on.arrowRight() end
section_field('profile');for _=1,4 do on.arrowRight() end -- IPE 300
section_field('self_weight');on.enterKey();assert(state().portal_beam_self_weight)
assert(state().stale and not running);paint()
Frame.solve=solve;input();local steel=on.save();local sol=calculate()
assert(sol.parameters.q==10+DB.compute(steel.portal_sections.beam).q_sw)
input();field(4);edit('123');assert(state().err=='EI from section; use TAB')
assert(state().portal.EIc==DB.compute(steel.portal_sections.columns).EI)
field(5);edit('456');assert(state().err=='EI from section; use TAB')
assert(state().portal.EIb==DB.compute(steel.portal_sections.beam).EI)
sections();group('beam');section_field('material')
for _=1,4 do on.arrowLeft() end -- MANUAL disables only portal beam self-weight
assert(not state().portal_beam_self_weight and state().portal_sections.beam.material==1)
section_field('manualEI');edit('17000.875');assert(state().portal.EIb==17000.875)
input();field(5);edit('18000.125');assert(state().portal_sections.beam.manualEI==18000.125)
assert(state().portal_sections.columns.profile==16 and not state().self_weight)
print('PASS shared group/material/profile/manual EI/edit/TAB handlers; deferred sections and beam-only self-weight')

-- Actual UDL arrows use the effective load, including q_user <= 0.
for _,q in ipairs{0,-.2} do
    local doc=catalogue_doc(section_cases[1]);doc.portal.q=q
    on.restore(doc);calculate();paint();assert(#gc.polygons==3)
    for _,shape in ipairs(gc.polygons) do assert(shape.points[6]>(shape.points[2]+shape.points[4])/2) end
    assert(on.save().portal.q==q)
end

-- Complete current documents, isolated validation and derived-cache precedence.
for _,doc in ipairs(dofile(root..'/tests/current_documents.lua')(defaults,true)) do
    on.restore(doc);same(on.save(),doc)
end
local good=catalogue_doc(section_cases[1]);good.page=3;good.portal_section_group='beam'
for _,support in ipairs{1,5,6} do
    local doc=copy(good);doc.params.support=support
    on.restore(doc);local saved=on.save()
    assert(saved.portal.EIc==DB.compute(doc.portal_sections.columns).EI and saved.portal.EIb==DB.compute(doc.portal_sections.beam).EI)
    assert(doc.portal.EIc==-77 and doc.portal.EIb==0)
end
for _,change in ipairs{
    function(d) d.format='0.6.0' end,
    function(d) d.portal_sections=nil end,
    function(d) d.portal_sections.columns=nil end,
    function(d) d.portal_sections.beam=false end,
    function(d) d.portal_sections.columns.material=1.5 end,
    function(d) d.portal_sections.beam.profile=999 end,
    function(d) d.portal_sections.columns.b=-1 end,
    function(d) d.portal_sections.beam.h=0 end,
    function(d) d.portal_sections.columns.manualEI=0/0 end,
    function(d) d.portal_sections.beam.material=2;d.portal_sections.beam.h=1e200 end,
    function(d) d.portal_sections.beam.material=1 end,
    function(d) d.portal_section_group='bad' end,
    function(d) d.portal_beam_self_weight=1 end,
    function(d) d.portal.q=false end,
    function(d) d.portal.h=0 end,
} do
    on.restore(good);local bad=copy(good);change(bad)
    on.restore(bad);same(on.save(),defaults)
    assert(state().restore_notice=='Invalid document or version: defaults restored' and not running)
end
print('PASS strict v0.6.1 groups/page 3 round-trip; derived EI wins; invalid groups/weight/model/version reset atomically')

-- Failed deferred work also rolls back the section groups and weight flag.
on.restore(good);input();sol=calculate();local confirmed=on.save();local cache=state().samples
sections();group('beam');section_field('material');for _=1,4 do on.arrowLeft() end
input();local preset=PortalPreset.solve;PortalPreset.solve=function() return nil,'section failure' end
on.tabKey();on.timer();PortalPreset.solve=preset
assert(state().err=='section failure' and state().result==sol and state().samples==cache)
same(state().portal_sections,confirmed.portal_sections);assert(state().portal_beam_self_weight)

-- New section/provenance layouts at every supported viewport and material mix.
for _,size in ipairs{{318,212},{320,212},{320,240}} do
    width,height=size[1],size[2]
    for _,case in ipairs(section_cases) do
        on.restore(catalogue_doc(case));sections()
        for _,name in ipairs{'columns','beam'} do
            group(name);paint();for _=1,10 do on.arrowDown();paint() end
        end
        input();calculate()
        for _=1,5 do paint();on.arrowRight() end
        on.enterKey();for _=1,35 do on.arrowDown();paint() end
    end
end
print('PASS P6C-R1 portal productive bundle; catalogue, self-weight, provenance and all target layouts')
