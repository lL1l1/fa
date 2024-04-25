---@meta

---@class BeamEntitySpec
---@field Weapon
---@field BeamBone
---@field OtherBone
---@field CollisionCheckInterval

---@class moho.CollisionBeamEntity : moho.entity_methods
local CCollisionBeamEntity = {}

--- Toggles whether the beam is enabled or disabled
function CCollisionBeamEntity:Enable()
end

--- Returns the Weapon object that the beam belongs to
function CCollisionBeamEntity:GetLauncher()
end

---@return boolean Enabled
function CCollisionBeamEntity:IsEnabled()
end

--- Set an emitter whose length parameter will be controlled by the beam entity's collision distance
---@param beamEmitter moho.IEffect
---@param checkCollision boolean
function CCollisionBeamEntity:SetBeamFx(beamEmitter,  checkCollision)
end

---@param ... BeamEntitySpec
function CCollisionBeamEntity:__init(...)
end

return CCollisionBeamEntity
