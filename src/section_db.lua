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
-- Entries: name, nominal strong-axis Iy [cm4], mass [kg/m].
-- Mass: ArcelorMittal Sections and Merchant Bars (2021), IPE / HE A tables.
-- Source URL and table pages in README. Existing Iy values are unchanged.
DB.profiles = {
    {'IPE 100',171,8.1}, {'IPE 120',317.8,10.4}, {'IPE 140',541.2,12.9},
    {'IPE 160',869.3,15.8}, {'IPE 180',1317,18.8}, {'IPE 200',1943,22.4},
    {'IPE 220',2772,26.2}, {'IPE 240',3892,30.7}, {'IPE 270',5790,36.1},
    {'IPE 300',8356,42.2}, {'HEA 100',349.2,16.7}, {'HEA 120',606.2,19.9},
    {'HEA 140',1033,24.7}, {'HEA 160',1673,30.4}, {'HEA 180',2510,35.5},
    {'HEA 200',3692,42.3}, {'HEA 220',5410,50.5}, {'HEA 240',7763,60.3},
    {'HEA 260',10455,68.2}, {'HEA 280',13670,76.4}, {'HEA 300',18260,88.3}
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
    local I,label,q_sw
    if mat.kind=='concrete' then
        if not positive(s.b) or not positive(s.h) then return nil,'invalid rectangle b/h' end
        -- b,h are in mm. m^4 to cm^4 conversion is 1e8.
        I=(s.b/1000)*(s.h/1000)^3/12
        label='RECT '..s.b..'x'..s.h
        -- Nominal normal-weight reinforced concrete: 25 kN/m3.
        q_sw=25*(s.b/1000)*(s.h/1000)
    else
        local shape=DB.profiles[s.profile]
        if not shape then return nil,'invalid profile' end
        I=shape[2]*1e-8
        label=shape[1]
        if positive(shape[3]) then q_sw=shape[3]*9.81/1000 end
    end
    -- E in N/mm2 (MPa) -> kN/m2: x1000; I in m4 -> EI in kN m2.
    return {E=mat.E,I=I,EI=mat.E*1000*I,label=label,kind=mat.kind,q_sw=q_sw}
end
return DB
