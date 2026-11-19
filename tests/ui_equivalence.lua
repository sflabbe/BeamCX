-- P6C-0: replay public TI events against the preserved P6B and current bundles.
-- baseline_source is supplied verbatim by test_ui_equivalence.py.
local load_ui=dofile(root..'/tests/load_ui.lua')
local function copy(value)
    if type(value)~='table' then return value end
    local out={};for k,v in pairs(value) do out[k]=copy(v) end;return out
end
-- Canonical structural encoding: sorted keys, exact round-trip numbers, no
-- dependence on pairs order or function addresses. No numerical tolerance.
local function encode(v)
    local t=type(v)
    if t=='number' then return string.format('%.17g',v) end
    if t=='string' then return string.format('%q',v) end
    if t~='table' then return t=='function' and '<function>' or tostring(v) end
    local keys,out={},{}
    for k in pairs(v) do keys[#keys+1]=k end
    table.sort(keys,function(a,b)
        if type(a)==type(b) then return a<b end
        return type(a)<type(b)
    end)
    for _,k in ipairs(keys) do out[#out+1]='['..encode(k)..']='..encode(v[k]) end
    return '{'..table.concat(out,',')..'}'
end
local expected={}
local counts={events=0,commands=0,screens=0}
local function replay(path,baseline)
    local width,height=318,212
    local effects,stores,solves={}, {}, {Frame=0,BeamPreset=0,ContinuousPreset=0,PortalPreset=0}
    local queries={Frame=0,BeamPreset=0,PortalPreset=0}
    local running=false
    platform={window={width=function() return width end,height=function() return height end,
        invalidate=function() effects[#effects+1]={'invalidate'} end}}
    timer={start=function(t) effects[#effects+1]={'start',t};running=true end,
        stop=function() effects[#effects+1]={'stop'};running=false end}
    var={store=function(k,v) stores[#stores+1]={k,v} end}
    on=nil;_BX_TEST_STATE=nil;DB=nil;Frame=nil;BeamPreset=nil;ContinuousPreset=nil;PortalPreset=nil
    -- Count the unchanged initial calculation as well as later event solves.
    debug.sethook(function()
        local f=debug.getinfo(2,'f').func
        for _,name in ipairs{'Frame','BeamPreset','ContinuousPreset','PortalPreset'} do
            local module=_G[name]
            if module and module.solve==f then solves[name]=solves[name]+1 end
        end
    end,'c')
    load_ui(path)
    debug.sethook()
    for _,name in ipairs{'Frame','BeamPreset','ContinuousPreset','PortalPreset'} do
        local module=_G[name]
        local solve=module.solve
        module.solve=function(...) solves[name]=solves[name]+1;return solve(...) end
        if module.at then
            local at=module.at
            module.at=function(...) queries[name]=queries[name]+1;return at(...) end
        end
    end
    local identities,nextid={},0
    local function state()
        local s=_BX_TEST_STATE()
        s.format_number=nil
        local ids={}
        for _,key in ipairs{'result','summary','samples','cursor_value','characteristic'} do
            local ref=s[key]
            if ref then
                if not identities[ref] then nextid=nextid+1;identities[ref]=nextid end
                ids[key]=identities[ref]
            end
        end
        -- Observe public result records without private matrices/closures.
        if s.result then
            local r={}
            for _,key in ipairs{'parameters','reactions','members','corners','drift','deflection',
                'deflection_check','moments','shear','spans','supports','summary'} do r[key]=s.result[key] end
            s.result=r
        end
        s.characteristic=nil -- lifetime is checked above; samples contain its readings
        return {snapshot=s,identities=ids,document=on.save()}
    end
    local graphics={size=10,commands={}}
    local function command(name,...)
        graphics.commands[#graphics.commands+1]={name,...}
    end
    function graphics:setFont(face,style,size) self.size=size;command('font',face,style,size) end
    function graphics:getStringWidth(t) return #t:gsub('[\128-\191]','')*self.size*.7 end
    function graphics:getStringHeight() return self.size+3 end
    function graphics:setColorRGB(...) command('color',...) end
    function graphics:setPen(...) command('pen',...) end
    function graphics:drawString(...) command('text',...) end
    function graphics:fillRect(...) command('rect',...) end
    function graphics:drawLine(...) command('line',...) end
    function graphics:fillPolygon(points) command('polygon',(table.unpack or unpack)(points)) end
    local trace_dir=os.getenv('BX_TRACE_DIR')
    local trace=trace_dir and assert(io.open(trace_dir..'/'..(baseline and 'before' or 'after')..'.trace','w'))
    local graphics_dir=os.getenv('BX_GRAPHICS_DIR')
    local frames=graphics_dir and assert(io.open(graphics_dir..'/'..(baseline and 'before' or 'after')..'.jsonl','w'))
    local index=0
    local function check(label,screen)
        index=index+1
        local globals,callbacks={},{}
        for k,v in pairs(_G) do globals[k]=type(v) end
        for k,v in pairs(on) do callbacks[k]=type(v) end
        local before=state()
        local nsolve=encode(solves)
        graphics.commands={};on.paint(graphics)
        assert(encode(solves)==nsolve,'paint solved at '..label)
        local observation=encode{label=label,width=width,height=height,before=before,after=state(),
            graphics=graphics.commands,solves=solves,queries=queries,effects=effects,
            stores=stores,running=running,globals=globals,callbacks=callbacks}
        if trace then trace:write(observation,'\n') end
        if baseline then expected[index]=observation
        else assert(expected[index]==observation,'P6B differential mismatch at '..index..': '..label..' ('..width..'x'..height..')') end
        if frames and screen then
            frames:write('['..string.format('%q',screen)..','..width..','..height..']\n')
            for _,c in ipairs(graphics.commands) do
                local values={}
                for _,v in ipairs(c) do values[#values+1]=type(v)=='number' and string.format('%.17g',v) or string.format('%q',v) end
                frames:write('['..table.concat(values,',')..']\n')
            end
        end
        counts.events=counts.events+1;counts.commands=counts.commands+#graphics.commands
        if screen then counts.screens=counts.screens+1 end
        effects={};stores={}
    end
    local function event(name,arg)
        assert(on[name],name)(arg);check(name..(arg~=nil and ':'..encode(arg) or ''))
    end
    local function field(index)
        while _BX_TEST_STATE().edit_index<index do event('arrowDown') end
        while _BX_TEST_STATE().edit_index>index do event('arrowUp') end
    end
    local function edit(text)
        for ch in text:gmatch('.') do event('charIn',ch) end
        event('enterKey')
    end
    local function open(card)
        if _BX_TEST_STATE().page~=0 then event('escapeKey') end
        event('arrowUp');event('arrowLeft');event('arrowLeft')
        for _=1,(card-1)%3 do event('arrowRight') end
        if card>3 then event('arrowDown') end
        assert(_BX_TEST_STATE().sel_index==card);check('selector '..card)
        event('enterKey');assert(_BX_TEST_STATE().support==card)
    end
    local function calculate()
        local card=_BX_TEST_STATE().support
        local before=copy(solves)
        event('tabKey')
        assert(_BX_TEST_STATE().calculating and running)
        assert(encode(solves)==encode(before),'results entry solved synchronously')
        event('timer')
        assert(not running and not _BX_TEST_STATE().stale)
        local n=card==6 and 1 or #on.save().continuous.spans+1
        assert(solves.Frame-before.Frame==n,'deferred Frame solve count')
        assert(solves[card==6 and 'PortalPreset' or 'ContinuousPreset']-before[card==6 and 'PortalPreset' or 'ContinuousPreset']==1)
    end
    local defaults=on.save()
    check('initial')
    assert(solves.Frame==1 and solves.BeamPreset==1,'initial single-span calculation changed')
    for _,size in ipairs{{318,212},{320,212},{320,240}} do
        width,height=size[1],size[2]
        event('restore',copy(defaults));check('selector','Six-card selector')
        for card=1,4 do
            open(card);check('single input',card==1 and 'Single input' or nil)
            field(2);edit('6.125');edit('0');assert(_BX_TEST_STATE().err)
            edit('6.125');event('charIn','9');event('backspaceKey');event('charIn','8');event('escapeKey')
            field(4);edit('-12');field(5);edit('2.2')
            event('tabKey');check('single M',card==1 and 'Single M' or nil)
            event('arrowUp');event('arrowDown');event('arrowRight');check('single V',card==1 and 'Single V' or nil)
            event('arrowRight');check('single w',card==1 and 'Single w' or nil)
            event('arrowRight');check('single results',card==1 and 'Single results' or nil)
            event('enterKey');assert(_BX_TEST_STATE().export_message=='CAS: 8 variables stored')
            event('arrowUp');event('arrowDown')
            event('restore',on.save());event('tabKey');check('manual sections',card==1 and 'Manual sections' or nil)
            for _=1,8 do event('arrowUp') end
            event('arrowRight');check('concrete sections',card==1 and 'Concrete sections' or nil)
            event('arrowDown');edit('300')
            for _=1,8 do event('arrowUp') end
            for _=1,3 do event('arrowRight') end
            event('arrowDown');event('arrowRight');event('arrowDown');event('enterKey')
            assert(on.save().settings.self_weight);check('steel sections',card==1 and 'Steel sections' or nil)
            event('tabKey');event('tabKey');event('enterKey');event('enterKey')
            event('restore',on.save());event('escapeKey')
            event('restore',copy(defaults))
        end
        open(5);event('arrowRight');event('arrowRight') -- 3 -> 5 spans
        assert(#on.save().continuous.spans==5)
        for i=1,5 do field(i+1);edit(string.format('%.1f',3+i*.5)) end
        -- left/right end choices, then g/q and all three factors
        field(7);event('arrowRight');field(8);event('arrowRight')
        for _,item in ipairs{{9,'8.75'},{10,'6.25'},{11,'1.4'},{12,'0.95'},{13,'1.6'}} do field(item[1]);edit(item[2]) end
        field(2);edit('0');assert(_BX_TEST_STATE().err);edit('3.5')
        check('continuous input','Continuous input')
        -- Cancel pending work, then use the same timer on next entry.
        event('tabKey');event('tabKey');assert(not running)
        event('timer');check('continuous sections','Continuous sections')
        event('arrowRight');event('arrowDown');edit('300')
        for _=1,10 do event('arrowDown') end
        event('enterKey');event('tabKey');calculate()
        check('continuous M','Continuous M');event('arrowUp');event('arrowDown')
        event('arrowRight');check('continuous V','Continuous V')
        event('arrowRight');check('continuous w','Continuous w')
        event('arrowRight');check('continuous table','Continuous results');event('arrowDown');event('arrowUp')
        event('enterKey');assert(_BX_TEST_STATE().export_message=='CAS: 8 variables stored')
        event('restore',on.save());assert(_BX_TEST_STATE().page==1);calculate()
        event('restore',copy(defaults));open(6)
        event('arrowLeft');assert(on.save().portal.base=='PIN');event('arrowRight')
        for _,item in ipairs{{2,'4.125'},{3,'6.25'},{4,'11000.125'},{5,'17000.875'},
            {6,'8'},{7,'17'},{8,'2.2'},{9,'11'},{10,'6'}} do field(item[1]);edit(item[2]) end
        field(2);edit('0');assert(_BX_TEST_STATE().err);edit('4.125')
        check('portal input','Portal input')
        event('tabKey');event('tabKey');event('timer');assert(not running)
        calculate();check('portal M','Portal M')
        for _,member in ipairs{'1','3','2'} do event('charIn',member);event('arrowUp');event('arrowDown') end
        event('arrowRight');check('portal V','Portal V')
        for _=1,24 do event('arrowDown') end
        local saw_left,saw_right=false,false
        for _=1,24 do
            event('arrowUp');local s=_BX_TEST_STATE()
            if s.portal_s==on.save().portal.a then
                saw_left=saw_left or s.portal_side=='left';saw_right=saw_right or s.portal_side=='right'
            end
        end
        assert(saw_left and saw_right,'point-load jump was not traversed')
        event('arrowRight');check('portal N','Portal N');event('arrowRight');check('portal deformation','Portal deformation')
        event('arrowRight');check('portal table','Portal results')
        for _=1,29 do event('arrowDown') end
        for _=1,29 do event('arrowUp') end
        event('enterKey');assert(_BX_TEST_STATE().export_message=='CAS: 14 variables stored')
        -- Returned CAS errors, throws and unavailable API preserve old feedback.
        var.store=function() return 'store rejected' end;event('enterKey')
        var.store=function() error('store failed',0) end;event('enterKey')
        var=nil;event('enterKey');var={store=function(k,v) stores[#stores+1]={k,v} end}
        event('restore',on.save());calculate()
        -- Later portal failure restores confirmed model/result/cache identities.
        event('tabKey');field(6);edit('9')
        local solve=PortalPreset.solve;PortalPreset.solve=function() return nil,'forced portal failure' end
        event('tabKey');event('timer');assert(_BX_TEST_STATE().err=='forced portal failure')
        PortalPreset.solve=solve
        -- Initial candidate failures roll back the prior system transaction.
        for _,card in ipairs{5,6} do
            event('restore',copy(defaults));open(card)
            local module=card==5 and ContinuousPreset or PortalPreset
            local saved=module.solve;module.solve=function() return nil,'forced selection failure' end
            event('tabKey');event('timer');module.solve=saved
            assert(_BX_TEST_STATE().page==0 and _BX_TEST_STATE().support==1)
        end
        event('restore',copy(defaults));open(1);event('escapeKey')
        local saved=BeamPreset.solve;BeamPreset.solve=function() return nil,'forced single failure' end
        event('arrowRight');event('enterKey');BeamPreset.solve=saved
        assert(_BX_TEST_STATE().page==0 and _BX_TEST_STATE().support==1)
        -- Strict version/schema rejection uses historical fixtures unchanged.
        for _,doc in ipairs(dofile(root..'/tests/fixtures/beam_v050_saved.lua')) do event('restore',doc) end
        for _,doc in ipairs{false,{}, {format='0.6.0'}, {format='0.5.0'}} do event('restore',doc) end
        local bad=copy(defaults);bad.portal.EIc=0;event('restore',bad)
        assert(_BX_TEST_STATE().restore_notice=='Invalid document or version: defaults restored')
    end
    if trace then trace:close() end
    if frames then frames:close() end
    if not baseline then assert(index==#expected,'event count mismatch') end
end
local original=os.tmpname()
local file=assert(io.open(original,'w'));file:write(baseline_source);file:close()
replay(original,true);os.remove(original)
replay(root..'/BeamCX.lua',false)
print(string.format('PASS exact P6B UI equivalence: %d observations, %d ordered graphics commands, %d selected screens; all three canvas sizes',
    counts.events/2,counts.commands/2,counts.screens/2))
