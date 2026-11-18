-- Independent CX benchmark; bundled by tools/build_bench.py, not build.py.
-- Official TI API: timer.getMilliSecCounter(), wraps at 2^32 ms.
-- https://education.ti.com/html/webhelp/EG_TINspireLUA/EN/content/libraries/timerlib/getmilliseccounter.htm
local Bench={version=BENCH_CORE_VERSION or 'Frame (unbundled)',sha=BENCH_CORE_SHA or '',rows={}}
local function clock_ms()
    if timer and timer.getMilliSecCounter then return timer.getMilliSecCounter() end
    if os and os.clock then return os.clock()*1000 end -- PC reference only.
    error('No millisecond clock available',0)
end
Bench.clock_name=timer and timer.getMilliSecCounter and 'TI millisecond counter' or 'PC CPU os.clock'
local function continuous(spans,synthetic)
    local m={nodes={},members={},supports={},member_loads={}}
    for i=1,spans+1 do
        m.nodes[i]={x=6*(i-1),y=0};m.supports[i]={node=i,ux=i==1,uy=true}
        if i>1 then
            local id=i-1
            m.members[id]={i=id,j=i,EI=10000,EA=1e8}
            m.member_loads[#m.member_loads+1]={member=id,type='udl',q=-10}
            m.member_loads[#m.member_loads+1]={member=id,type='point',a=2,P=-12}
            if synthetic then m.member_loads[#m.member_loads+1]={member=id,type='moment',a=3,M=5} end
        end
    end
    return m
end
local gable={nodes={{x=0,y=0},{x=0,y=4},{x=3,y=6},{x=6,y=4},{x=6,y=0}},
    members={{i=1,j=2,EI=10000,EA=1e8},{i=2,j=3,EI=15000,EA=1e8,hinge_j=true},
             {i=3,j=4,EI=15000,EA=1e8,hinge_i=true},{i=5,j=4,EI=10000,EA=1e8}},
    supports={{node=1,ux=true,uy=true,rz=true},{node=5,ux=true,uy=true,rz=true}},
    member_loads={{member=2,type='udl',q=-10},{member=3,type='udl',q=-10}}}
Bench.cases={{name='simple q+P',model=continuous(1)},
             {name='5 spans q+P',model=continuous(5)},
             {name='gable hinges',model=gable},
             {name='synthetic 20',model=continuous(19,true)},
             {name='synthetic 40',model=continuous(39,true)},
             {name='synthetic 60',model=continuous(59,true)}}
local function recover(sol)
    local checksum=0
    -- Exactly 101 queries across user members; include physical end limits.
    for sample=0,100 do
        local member=sample%#sol.members+1
        local s=sol.members[member].L*sample/100
        local v=Frame.at(sol,member,s,s==0 and 'right' or 'left')
        checksum=checksum+v.M+v.w
    end
    return checksum
end
function Bench.measure(index,step)
    local case=Bench.cases[index]
    local solved,solve_ms,recovery_ms,ns,nr=nil,0,0,0,0
    repeat
        local start=clock_ms()
        local sol,err=Frame.solve(case.model)
        if not sol then error(case.name..': '..tostring(err),0) end
        solve_ms=solve_ms+(clock_ms()-start)%4294967296
        solved=sol;ns=ns+1
        if step then step() end
    until (ns>=3 and solve_ms>=200) or ns>=4096
    local checksum=0
    repeat
        local start=clock_ms()
        checksum=checksum+recover(solved)
        recovery_ms=recovery_ms+(clock_ms()-start)%4294967296
        nr=nr+1
        if step then step() end
    until (nr>=3 and recovery_ms>=200) or nr>=4096
    return {name=case.name,nodes=#solved.nodes,dofs=solved.ndof,free=#solved.free,
        solve_ms=solve_ms/ns,recovery_ms=recovery_ms/nr,Nsolve=ns,Nrecover=nr,checksum=checksum}
end
function Bench.pc()
    for i=1,#Bench.cases do
        local r=Bench.measure(i)
        print(string.format('BENCH | %s | %d | %d | %d | %.6f | %.6f | %d | %d',
            r.name,r.nodes,r.dofs,r.free,r.solve_ms,r.recovery_ms,r.Nsolve,r.Nrecover))
    end
end
function Bench.start()
    if Bench.task then return end
    Bench.rows={};Bench.current=1;Bench.done=false;Bench.error=nil
    Bench.task=coroutine.create(function()
        for i=1,#Bench.cases do
            Bench.current=i
            Bench.rows[i]=Bench.measure(i,coroutine.yield)
        end
        Bench.done=true
    end)
    timer.start(.01)
end
on=on or {}
function on.timer()
    if not Bench.task then return end
    local ok,err=coroutine.resume(Bench.task)
    if not ok then Bench.error=tostring(err) end
    if not ok or coroutine.status(Bench.task)=='dead' then timer.stop();Bench.task=nil end
    platform.window:invalidate()
end
function on.paint(gc)
    gc:setColorRGB(255,255,255);gc:fillRect(0,0,platform.window:width(),platform.window:height())
    gc:setColorRGB(0,0,0);gc:setFont('sansserif','r',8)
    local function text(s,x,y) gc:drawString(s,x,y,'top') end
    text('BXBENCH '..Bench.version..' '..string.sub(Bench.sha,1,8),4,3)
    text(Bench.clock_name..' / ms per operation',4,17)
    text('case',4,35);text('n/dof',105,35);text('solve',160,35);text('101 at',235,35)
    for i,case in ipairs(Bench.cases) do
        local y=51+(i-1)*23
        text(case.name,4,y)
        local r=Bench.rows[i]
        if r then
            text(r.nodes..'/'..r.dofs,105,y)
            text(string.format('%.2f',r.solve_ms),160,y)
            text(string.format('%.2f',r.recovery_ms),235,y)
            text('N solve/rec='..r.Nsolve..'/'..r.Nrecover,8,y+10)
        else text(i==Bench.current and 'running...' or '--',160,y) end
    end
    if Bench.error then text(string.sub(Bench.error,1,60),4,192)
    else text(Bench.done and 'Done. N>=3; target >=200 ms/batch.' or 'Measuring; painting is not timed.',4,192) end
end
if platform and platform.window and timer and timer.start then Bench.start() end
return Bench
