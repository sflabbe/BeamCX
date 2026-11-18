local width,height=318,212
platform={window={width=function() return width end,height=function() return height end,invalidate=function() end}}
timer={start=function() end,stop=function() end}
dofile(root..'/BeamCX.lua')
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
