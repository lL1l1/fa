--**********************************************************************************
--** Copyright (c) 2023 FAForever
--**
--** Permission is hereby granted, free of charge, to any person obtaining a copy
--** of this software and associated documentation files (the "Software"), to deal
--** in the Software without restriction, including without limitation the rights
--** to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
--** copies of the Software, and to permit persons to whom the Software is
--** furnished to do so, subject to the following conditions:
--**
--** The above copyright notice and this permission notice shall be included in all
--** copies or substantial portions of the Software.
--**
--** THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--** IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--** FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--** AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--** LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
--** OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
--** SOFTWARE.
--**********************************************************************************

-- upvalue for performance
local ChangeState = ChangeState
local GetSurfaceHeight = GetSurfaceHeight
local IssueToUnitMove = IssueToUnitMove
local Random = Random
local VDist3 = VDist3
local WaitSeconds = WaitSeconds

local TableInsert = table.insert

local EntityGetPosition = moho.entity_methods.GetPosition
local EntityGetPositionXYZ = moho.entity_methods.GetPositionXYZ


local SHoverLandUnit = import('/lua/seraphimunits.lua').SHoverLandUnit
local DefaultBeamWeapon = import('/lua/sim/DefaultWeapons.lua').DefaultBeamWeapon

-- Seraphim energy ball units
---@class SEnergyBallUnit : SHoverLandUnit
SEnergyBallUnit = ClassUnit(SHoverLandUnit) {
    timeAlive = 0,

    ---@param self SEnergyBallUnit
    OnCreate = function(self)
        SHoverLandUnit.OnCreate(self)
        self:SetUnSelectable(true)
        self.CanTakeDamage = false
        self.CanBeKilled = false
        self:PlayUnitSound('Spawn')
        ChangeState(self, self.KillingState)
    end,

    ---@class SEnergyBallUnit_KillingState : SEnergyBallUnit, State
    KillingState = State {
        ---@param self SEnergyBallUnit_KillingState
        LifeThread = function(self)
            WaitSeconds(self.Blueprint.Lifetime)
            ChangeState(self, self.DeathState)
        end,

        ---@param self SEnergyBallUnit_KillingState
        Main = function(self)
            local bp = self.Blueprint
            local aiBrain = self.Brain

            local reusedTable = {}

            -- Queue up random moves
            local x, y, z = EntityGetPositionXYZ(self)
            local maxMoveRange = bp.MaxMoveRange
            if maxMoveRange and maxMoveRange > 0 then
                reusedTable[2] = y
                for i = 1, 100 do
                    reusedTable[1], reusedTable[3] = x + Random(-maxMoveRange, maxMoveRange), z + Random(-maxMoveRange, maxMoveRange)
                    IssueToUnitMove(self, reusedTable)
                end
            end

            -- Weapon information
            local weaponMaxRange = bp.Weapon[1].MaxRadius
            local weaponMinRange = bp.Weapon[1].MinRadius or 0
            local beamLifetime = bp.Weapon[1].BeamLifetime or 1
            local reaquireTime = bp.Weapon[1].RequireTime or 0.5
            local weapon = self.WeaponInstances[1] --[[@as DefaultBeamWeapon]]

            self:ForkThread(self.LifeThread)

            while true do
                local location = EntityGetPosition(self)
                local targets = aiBrain:GetUnitsAroundPoint(categories.LAND - categories.UNTARGETABLE, location, weaponMaxRange)

                local filteredUnits = {}
                for _, v in targets do
                    reusedTable[1], reusedTable[2], reusedTable[3] = EntityGetPositionXYZ(v)
                    if VDist3(location, reusedTable) >= weaponMinRange and v ~= self then
                        TableInsert(filteredUnits, v)
                    end
                end

                local target = table.random(filteredUnits)
                if target then
                    weapon:SetTargetEntity(target)
                else
                    local x, z = location[1] + Random(-20, 20), location[3] + Random(-20, 20)
                    reusedTable[1], reusedTable[2], reusedTable[3] = x, GetSurfaceHeight(x, z), z
                    weapon:SetTargetGround(reusedTable)
                end
                -- Wait a tick to let the target update awesomely.
                WaitTicks(2)
                self.timeAlive = self.timeAlive + .1

                weapon:FireWeapon()

                WaitSeconds(beamLifetime)
                DefaultBeamWeapon.PlayFxBeamEnd(weapon, weapon.Beams[1].Beam)
                WaitSeconds(reaquireTime)
            end
        end,

        --- Unused.
        ---@param self SEnergyBallUnit_KillingState
        ComputeWaitTime = function(self)
            local timeLeft = self.Blueprint.Lifetime - self.timeAlive

            local maxWait = 75
            if timeLeft < 7.5 and timeLeft > 2.5 then
                maxWait = timeLeft * 10
            end
            local waitTime = timeLeft
            if timeLeft > 2.5 then
                waitTime = Random(5, maxWait)
            end

            self.timeAlive = self.timeAlive + (waitTime * .1)
            WaitSeconds(waitTime * .1)
        end,
    },

    ---@class SEnergyBallUnit_DeathState : SEnergyBallUnit, State
    DeathState = State {
        ---@param self SEnergyBallUnit_DeathState
        Main = function(self)
            self.CanBeKilled = true
            if self.Layer == 'Water' then
                self:PlayUnitSound('HoverKilledOnWater')
            end
            self:PlayUnitSound('Destroyed')
            self:Destroy()
        end,
    },
}
