local width,height=318,212
platform={window={width=function() return width end,height=function() return height end,invalidate=function() end}}
timer={start=function() end,stop=function() end}
local load_ui=dofile(root..'/tests/load_ui.lua')
if docs_mode then load_ui(root..'/BeamCX.lua') else dofile(root..'/BeamCX.lua') end
local gc=dofile(root..'/tests/portal_graphics.lua')(function() return width end,function() return height end)
local function emit(values)
    local parts={}
    for _,v in ipairs(values) do parts[#parts+1]=type(v)=='number' and string.format('%.17g',v) or string.format('%q',v) end
    print('['..table.concat(parts,',')..']')
end
local function capture(name)
    gc:reset();on.paint(gc);emit({'screen',name})
    for _,command in ipairs(gc.commands) do emit(command) end
end
if docs_mode then
    -- Documentation scenes use only real application events and read-only assertions.
    local function key(name,count)
        for _=1,count or 1 do assert(on[name],name)() end
    end
    local function open(card)
        key('arrowRight',(card-1)%3)
        if card>3 then key('arrowDown') end
        key('enterKey');assert(_BX_TEST_STATE().support==card)
    end
    local function results()
        key('tabKey')
        if _BX_TEST_STATE().calculating then key('timer') end
        assert(_BX_TEST_STATE().page==2 and _BX_TEST_STATE().result)
    end
    local function steel(portal)
        if portal then
            open(6);results();key('tabKey');key('arrowDown');key('arrowRight',4)
            key('arrowDown');key('arrowRight',10);key('arrowUp',2);key('arrowRight');key('arrowDown')
            assert(_BX_TEST_STATE().portal_section_group=='beam')
        else open(1);results();key('tabKey') end
        key('arrowRight',4);key('arrowDown');key('arrowRight',4);key('arrowDown');key('enterKey')
        local saved=on.save()
        local section=portal and saved.portal_sections.beam or saved.section
        assert(section.material==5 and section.profile==10)
        if portal then assert(saved.portal_sections.columns.material==5 and saved.portal_sections.columns.profile==16) end
        assert(portal and saved.portal_beam_self_weight or (not portal and saved.settings.self_weight))
    end
    local scenes={
        selector=function() assert(_BX_TEST_STATE().page==0) end,
        ['single-moment']=function() open(1);results();assert(on.save().cursor==.5) end,
        ['single-deflection']=function() open(1);results();key('enterKey');assert(on.save().settings.limit==250) end,
        ['sections-steel']=function() steel(false) end,
        ['continuous-input']=function() open(5) end,
        ['continuous-envelope']=function() open(5);results() end,
        ['continuous-table']=function() open(5);results();key('enterKey');key('arrowDown') end,
        ['portal-input']=function() open(6) end,
        ['portal-moment']=function() open(6);results() end,
        ['portal-deformed']=function() open(6);results();key('arrowRight',3) end,
        ['portal-sections']=function() steel(true) end,
        ['portal-results']=function() steel(true);key('tabKey');results();key('enterKey') end,
        ['cas-export']=function()
            open(6);results();key('enterKey')
            local stores={}
            var={store=function(name,value)
                assert(name:match('^bp_') and type(value)=='number' and value==value)
                stores[#stores+1]={name,value}
            end}
            key('enterKey');assert(#stores==14 and _BX_TEST_STATE().export_message=='CAS: 14 variables stored')
            var=nil
        end,
    }
    if #docs_scenes==0 then
        docs_scenes={'selector','single-moment','single-deflection','sections-steel',
            'continuous-input','continuous-envelope','continuous-table','portal-input',
            'portal-moment','portal-deformed','portal-sections','portal-results','cas-export'}
    end
    local used={}
    for _,name in ipairs(docs_scenes) do
        assert(scenes[name],'unknown documentation scene: '..name)
        assert(not used[name],'duplicate documentation scene: '..name);used[name]=true
        on=nil;var=nil;load_ui(root..'/BeamCX.lua')
        scenes[name]();capture(name)
    end
    return
end
capture('Six-card selector')
on.arrowRight();on.arrowRight();on.arrowDown();on.enterKey()
local doc=on.save();doc.portal={h=4,l=6,base='FIX',EIc=10000,EIb=15000,q=8,P=17,a=2.2,H=11,w=6}
on.restore(doc)
capture('Portal input: geometry / EI')
for _=1,9 do on.arrowDown() end
capture('Portal input: loads')
on.tabKey();on.timer()
for _,title in ipairs{'M: tension side','V: point-load jump','N: signed member forces','Deformed: absolute / magnified'} do
    capture(title);on.arrowRight()
end
capture('Results: base reactions')
for _=1,6 do on.arrowDown() end
capture('Results: member forces / extrema')
for _=1,25 do on.arrowDown() end
capture('Results: drifts / chord-relative w')

-- P6C-R1: shared catalogue and effective beam self-weight, actual bundled UI.
doc=on.save();doc.page=3;doc.mode=1;doc.portal_section_group='columns'
doc.portal={h=4,l=6,base='FIX',EIc=0,EIb=0,q=10,P=0,a=3,H=0,w=0}
doc.portal_sections.columns.material=5;doc.portal_sections.columns.profile=16
doc.portal_sections.beam.material=5;doc.portal_sections.beam.profile=10
doc.portal_beam_self_weight=true
on.restore(doc);capture('Columns: HEA 200 S235 / axial weight excluded')
on.arrowRight();capture('Beam: IPE 300 S235 / self-weight ON')
on.tabKey();on.tabKey();on.timer();capture('Kleinlogel: M center 29.06 / sw=0.41')
on.enterKey();capture('Results: section and self-weight provenance')
