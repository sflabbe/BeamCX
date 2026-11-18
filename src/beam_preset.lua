-- Permanent beam presets on Frame. Load global Frame before this module.
-- Input L,a in m, EI in kN*m^2; q/P positive DOWN. Physical results:
-- reactions global, M sagging positive, w UP in metres. Summary bx_wmax in mm.
local BeamPreset = {}
local Core = assert(Frame,'load Frame before beam_preset.lua')

-- ONLY sign/unit conversion boundary. All other mechanics delegate to Frame.
local function convert(kind,value)
    if kind=='load' then return -value end
    if kind=='mm' then return value*1000 end
    error('invalid conversion',0)
end
local function finite(x)
    return type(x)=='number' and x==x and math.abs(x)<math.huge
end
function BeamPreset.model(p)
    if type(p)~='table' or not finite(p.L) or p.L<=0 or not finite(p.EI) or p.EI<=0
       or not finite(p.q) or not finite(p.P) or not finite(p.a) or p.a<0 or p.a>p.L then
        return nil,'invalid beam dimensions, rigidity or loads'
    end
    if p.support~=1 and p.support~=2 and p.support~=3 and p.support~=4 then
        return nil,'unknown beam preset'
    end
    local loads={{member=1,type='udl',q=convert('load',p.q)}}
    if p.P~=0 then loads[#loads+1]={member=1,type='point',a=p.a,P=convert('load',p.P)} end
    return {nodes={{x=0,y=0},{x=p.L,y=0}},members={{i=1,j=2,EI=p.EI,EA=1000*p.EI/p.L^2}},
        supports={{node=1,ux=true,uy=true,rz=p.support~=1},
                  {node=2,ux=p.support==3,uy=p.support~=2,rz=p.support==3}},member_loads=loads}
end
function BeamPreset.at(sol,x,side)
    x=math.max(0,math.min(sol.parameters.L,x))
    -- Default physical limit at a discontinuity: left, except at x=0 where
    -- only the right/interior limit exists. Callers may explicitly select side.
    return Core.at(sol.frame,1,x,side or (x==0 and 'right' or 'left'))
end
function BeamPreset.moment_extrema(sol)
    local lo,xlo,hi,xhi=Core.moment_extrema(sol.frame,1)
    return {minimum={value=lo,position=xlo},maximum={value=hi,position=xhi}}
end
function BeamPreset.deflection_extrema(sol)
    local w,x=Core.deflection_extrema(sol.frame,1)
    return {value=w,absolute=math.abs(w),position=x}
end
function BeamPreset.deflection_check(sol,limit,lref_factor)
    limit=limit==300 and 300 or 250
    lref_factor=lref_factor or 1
    local maximum=sol.deflection or BeamPreset.deflection_extrema(sol)
    local lref=lref_factor*sol.parameters.L
    local w=convert('mm',maximum.absolute)
    local mm=convert('mm',lref)
    local ratio=w>0 and mm/w or nil
    local u250,u300=w/(mm/250),w/(mm/300)
    local selected=limit==300 and u300 or u250
    local status='N/A'
    if ratio then status=selected<=1+1e-12 and 'OK' or 'EXCEEDED' end
    return {lref_factor=lref_factor,reference_length=lref,span_deflection_ratio=ratio,
            utilization={L250=u250,L300=u300},selected_limit=limit,status=status}
end
function BeamPreset.summary(sol)
    local p=sol.parameters
    local vabs=0
    local positions={0,p.L}
    if p.P~=0 and p.a>0 and p.a<p.L then positions[#positions+1]=p.a end
    for _,x in ipairs(positions) do
        if x>0 then vabs=math.max(vabs,math.abs(Core.at(sol.frame,1,x,'left').V)) end
        if x<p.L then vabs=math.max(vabs,math.abs(Core.at(sol.frame,1,x,'right').V)) end
    end
    return {bx_mmax=sol.moments.maximum.value,bx_mmin=sol.moments.minimum.value,
            bx_vabs=vabs,bx_wmax=convert('mm',sol.deflection.absolute),bx_xwmax=sol.deflection.position,
            bx_ra=sol.reactions.left.Ry,bx_rb=sol.reactions.right.Ry,bx_ei=p.EI}
end
function BeamPreset.solve(p,limit,lref_factor)
    local model,err=BeamPreset.model(p)
    if not model then return nil,err end
    local frame
    frame,err=Core.solve(model)
    if not frame then return nil,err end
    local result={parameters={L=p.L,q=p.q,P=p.P,a=p.a,EI=p.EI,support=p.support},frame=frame,
                  reactions={left=frame.reactions[1],right=frame.reactions[2]}}
    result.moments=BeamPreset.moment_extrema(result)
    result.deflection=BeamPreset.deflection_extrema(result)
    result.deflection_check=BeamPreset.deflection_check(result,limit,lref_factor)
    result.summary=BeamPreset.summary(result)
    return result
end

return BeamPreset
