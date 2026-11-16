-- BeamCX offline catalogue. E in MPa, Iy (major bending axis) in cm^4.
-- Source tables are recorded in README; no files or network needed on TI.
local DB = {}
DB.materials = {
    {name='MANUAL',kind='manual'},
    {name='C20/25',kind='concrete',E=30000},
    {name='C25/30',kind='concrete',E=31000},
    {name='C30/37',kind='concrete',E=33000},
    {name='S235',kind='steel',E=210000},
    {name='S355',kind='steel',E=210000}
}
-- Rolled profile nominal strong-axis second moment Iy. Standard profile tables.
DB.profiles = {
    {'IPE 100',171}, {'IPE 120',317.8}, {'IPE 140',541.2},
    {'IPE 160',869.3}, {'IPE 180',1317}, {'IPE 200',1943},
    {'IPE 220',2772}, {'IPE 240',3892}, {'IPE 270',5790},
    {'IPE 300',8356}, {'HEA 100',349.2}, {'HEA 120',606.2},
    {'HEA 140',1033}, {'HEA 160',1673}, {'HEA 180',2510},
    {'HEA 200',3692}, {'HEA 220',5410}, {'HEA 240',7763},
    {'HEA 260',10455}, {'HEA 280',13670}, {'HEA 300',18260}
}
local function positive(v)
    return type(v)=='number' and v>0 and v<math.huge and v==v
end
function DB.compute(s)
    local mat=DB.materials[s.material]
    if not mat then return nil,'invalid material' end
    if mat.kind=='manual' then
        if not positive(s.manualEI) then return nil,'invalid manual EI' end
        return {EI=s.manualEI,I=nil,E=nil,label='MANUAL',kind='manual'}
    end
    local I,label
    if mat.kind=='concrete' then
        if not positive(s.b) or not positive(s.h) then return nil,'invalid rectangle b/h' end
        -- b,h are in mm. m^4 to cm^4 conversion is 1e8.
        I=(s.b/1000)*(s.h/1000)^3/12
        label='RECT '..s.b..'x'..s.h
    else
        local shape=DB.profiles[s.profile]
        if not shape then return nil,'invalid profile' end
        I=shape[2]*1e-8
        label=shape[1]
    end
    -- E in N/mm2 (MPa) -> kN/m2: x1000; I in m4 -> EI in kN m2.
    return {E=mat.E,I=I,EI=mat.E*1000*I,label=label,kind=mat.kind}
end
return DB
