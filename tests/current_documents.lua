-- Current-format precision witnesses, separate from the historical rejection fixture.
return function(defaults,include_portal)
    local function copy(t)
        if type(t)~='table' then return t end
        local out={};for k,v in pairs(t) do out[k]=copy(v) end;return out
    end
    local a,b=copy(defaults),copy(defaults)
    for _,doc in ipairs{a,b} do
        doc.params={L=6.123456789012345,P=2.125,a=2.375,q=10.123456789012344,EI=10000.123456789,support=1}
        doc.section.manualEI=10000.123456789;doc.page=2;doc.mode=4;doc.cursor=.425
    end
    b.params.support=5;b.page=3;b.settings.limit=300
    b.continuous={spans={4.123456789012345,6.375,5.625},left='FIX',right='PIN',
        g=12.1234567890123,q=5,gG_sup=1.35,gG_inf=1,gQ=1.51234567890123}
    local docs={a,b}
    if include_portal then
        local c=copy(defaults);c.params.support=6;c.page=3;c.mode=5
        c.portal_sections.columns.manualEI=12345.123456789
        c.portal_sections.beam.material=2;c.portal_sections.beam.b=300.125
        c.portal_section_group='beam';c.portal_beam_self_weight=true
        c.portal.EIc=DB.compute(c.portal_sections.columns).EI
        c.portal.EIb=DB.compute(c.portal_sections.beam).EI
        c.portal.H=-3.123456789;c.portal_s=1.234567890123
        docs[#docs+1]=c
    end
    return docs
end
