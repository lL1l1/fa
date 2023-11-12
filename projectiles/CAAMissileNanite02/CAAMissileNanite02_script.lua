local CAAMissileNaniteProjectile = import("/lua/cybranprojectiles.lua").CAAMissileNaniteProjectile

-- AA Missile for Cybrans
---@class CAAMissileNanite02: CAAMissileNaniteProjectile
CAAMissileNanite02 = ClassProjectile(CAAMissileNaniteProjectile) {

    ---@param self CAAMissileNanite02
    OnCreate = function(self)
        CAAMissileNaniteProjectile.OnCreate(self)
        self.Trash:Add(ForkThread(self.UpdateThread,self))
    end,

    ---@param self CAAMissileNanite02
    UpdateThread = function(self)
        WaitTicks(16)
        self:SetMaxSpeed(80)
        self:SetAcceleration(10 + Random() * 8)
        self:ChangeMaxZigZag(0.5)
        self:ChangeZigZagFrequency(2)
    end,

    ---@param self CAAMissileNanite02
    ---@param TargetType string
    ---@param TargetEntity Prop|Unit
    OnImpact = function(self, TargetType, TargetEntity)
        CAAMissileNaniteProjectile.OnImpact(self, TargetType, TargetEntity)
    end,
}
TypeClass = CAAMissileNanite02