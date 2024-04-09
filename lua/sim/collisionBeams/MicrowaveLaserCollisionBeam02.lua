local EffectTemplate = import("/lua/effecttemplates.lua")

local MicrowaveLaserCollisionBeam01 = import("/lua/defaultcollisionbeams.lua").MicrowaveLaserCollisionBeam01

---@class MicrowaveLaserCollisionBeam02 : MicrowaveLaserCollisionBeam01
MicrowaveLaserCollisionBeam02 = Class(MicrowaveLaserCollisionBeam01) {
    TerrainImpactScale = 1,
    FxBeamStartPoint = EffectTemplate.CMicrowaveLaserMuzzle01,
    FxBeam = EffectTemplate.CMicrowaveLaserBeam02,
    FxBeamEndPoint = EffectTemplate.CMicrowaveLaserEndPoint01,
}
