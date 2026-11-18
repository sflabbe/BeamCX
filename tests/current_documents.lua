-- Current-format precision witnesses, separate from the historical rejection fixture.
return function(defaults)
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
    return {a,b}
end
