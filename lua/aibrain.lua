---------------------------------------------------------------------------------------------------
-- File     :  /lua/aibrain.lua
-- Author(s):
-- Summary  :
-- Copyright Š 2005 Gas Powered Games, Inc.  All rights reserved.
---------------------------------------------------------------------------------------------------

-- AIBrain Lua Module

local SUtils = import("/lua/ai/sorianutilities.lua")
local TransferUnitsOwnership = import("/lua/simutils.lua").TransferUnitsOwnership
local TransferUnfinishedUnitsAfterDeath = import("/lua/simutils.lua").TransferUnfinishedUnitsAfterDeath
local KillArmy = import("/lua/simutils.lua").KillArmy
local KillArmyOnDelayedRecall = import("/lua/simutils.lua").KillArmyOnDelayedRecall
local KillArmyOnACUDeath = import("/lua/simutils.lua").KillArmyOnACUDeath
local DisableAI = import("/lua/simutils.lua").DisableAI
local TransferUnitsToBrain = import("/lua/simutils.lua").TransferUnitsToBrain
local TransferUnitsToHighestBrain = import("/lua/simutils.lua").TransferUnitsToHighestBrain
local UpdateUnitCap = import("/lua/simutils.lua").UpdateUnitCap
local OnArmyDefeat = import("/lua/simping.lua").OnArmyDefeat
local CalculateBrainScore = import("/lua/sim/score.lua").CalculateBrainScore
local FakeTeleportUnits = import("/lua/scenarioframework.lua").FakeTeleportUnits
local Factions = import('/lua/factions.lua').GetFactions(true)

local CommanderSafeTime = import("/lua/simutils.lua").CommanderSafeTime

local CoroutineYield = coroutine.yield

---@class TriggerSpec
---@field Callback function
---@field ReconTypes ReconTypes
---@field Blip boolean
---@field Value boolean
---@field Category EntityCategory
---@field OnceOnly boolean
---@field TargetAIBrain AIBrain

---@class ScoutLocation
---@field Position Vector
---@field TaggedBy Unit

---@class PlatoonTable
---@alias AIResult "defeat" | "draw" | "victor"
---@alias HqTech "TECH2" | "TECH3"
---@alias HqLayer "AIR" | "LAND" | "NAVY"
---@alias HqFaction "UEF" | "AEON" | "CYBRAN" | "SERAPHIM" | "NOMADS"
---@alias BrainState "Defeat" | "Draw" | "InProgress" | "Recalled" | "Victory"
---@alias BrainType "AI" | "Human"
---@alias ReconTypes 'Radar' | 'Sonar' | 'Omni' | 'LOSNow'
---@alias PlatoonType 'Air' | 'Land' | 'Sea'
---@alias AllianceStatus 'Ally' | 'Enemy' | 'Neutral'

---@class AIBrainHQComponent
---@field HQs table
local AIBrainHQComponent = ClassSimple {

    ---@param self AIBrainHQComponent | AIBrain
    CreateBrainShared = function(self)
        local layers = { "LAND", "AIR", "NAVAL" }
        local techs = { "TECH2", "TECH3" }

        self.HQs = {}
        for _, facData in Factions do
            local faction = facData.Category
            self.HQs[faction] = {}
            for _, layer in layers do
                self.HQs[faction][layer] = {}
                for _, tech in techs do
                    self.HQs[faction][layer][tech] = 0
                end
            end
        end

        -- restrict all support factories by default
        AddBuildRestriction(self:GetArmyIndex(), (categories.TECH3 + categories.TECH2) * categories.SUPPORTFACTORY)
    end,

    --- Adds a HQ so that the engi mod knows we have it
    ---@param self AIBrain
    ---@param faction HqFaction
    ---@param layer HqLayer
    ---@param tech HqTech
    AddHQ = function(self, faction, layer, tech)
        self.HQs[faction][layer][tech] = self.HQs[faction][layer][tech] + 1
    end,

    --- Removes an HQ so that the engi mod knows we lost it for the engi mod.
    ---@param self AIBrain
    ---@param faction HqFaction
    ---@param layer HqLayer
    ---@param tech HqTech
    RemoveHQ = function(self, faction, layer, tech)
        self.HQs[faction][layer][tech] = math.max(0, self.HQs[faction][layer][tech] - 1)
    end,

    --- Completely re evaluates the support factory restrictions of the engi mod
    ---@param self AIBrain
    ReEvaluateHQSupportFactoryRestrictions = function(self)
        local layers = { "AIR", "LAND", "NAVAL" }
        local factions = { "UEF", "AEON", "CYBRAN", "SERAPHIM" }

        if categories.NOMADS then
            table.insert(factions, 'NOMADS')
        end

        for _, faction in factions do
            for _, layer in layers do
                self:SetHQSupportFactoryRestrictions(faction, layer)
            end
        end
    end,

    --- Manages the support factory restrictions of the engi mod
    ---@param self AIBrain
    ---@param faction HqFaction
    ---@param layer HqLayer
    SetHQSupportFactoryRestrictions = function(self, faction, layer)

        -- localize for performance
        local army = self:GetArmyIndex()

        -- the pessimists we are, restrict everything!
        AddBuildRestriction(army,
            categories[faction] * categories[layer] * categories["TECH2"] * categories.SUPPORTFACTORY)
        AddBuildRestriction(army,
            categories[faction] * categories[layer] * categories["TECH3"] * categories.SUPPORTFACTORY)

        -- lift t2 / t3 support factory restrictions
        if self.HQs[faction][layer]["TECH3"] > 0 then
            RemoveBuildRestriction(army,
                categories[faction] * categories[layer] * categories["TECH2"] * categories.SUPPORTFACTORY)
            RemoveBuildRestriction(army,
                categories[faction] * categories[layer] * categories["TECH3"] * categories.SUPPORTFACTORY)
        end

        -- lift t2 support factory restrictions
        if self.HQs[faction][layer]["TECH2"] > 0 then
            RemoveBuildRestriction(army,
                categories[faction] * categories[layer] * categories["TECH2"] * categories.SUPPORTFACTORY)
        end
    end,

    --- Counts all HQs of specific faction, layer and tech for the engi mod.
    ---@param self AIBrain
    ---@param faction HqFaction
    ---@param layer HqLayer
    ---@param tech HqTech
    ---@return number
    CountHQs = function(self, faction, layer, tech)
        return self.HQs[faction][layer][tech]
    end,

    --- Counts all HQs of faction and tech, regardless of layer
    ---@param self AIBrain
    ---@param faction HqFaction
    ---@param tech HqTech
    ---@return number
    CountHQsAllLayers = function(self, faction, tech)
        local count = self.HQs[faction]["LAND"][tech]
        count = count + self.HQs[faction]["AIR"][tech]
        count = count + self.HQs[faction]["NAVAL"][tech]
        return count
    end,
}

---@class AIBrainStatisticsComponent
---@field UnitStats table<UnitId, table<string, number>>
local AIBrainStatisticsComponent = ClassSimple {

    ---@param self AIBrainHQComponent | AIBrain
    CreateBrainShared = function(self)
        self.UnitStats = {}
    end,

    ---@param self AIBrain
    ---@param unitId UnitId
    ---@param statName string
    ---@param value number
    AddUnitStat = function(self, unitId, statName, value)
        if self.UnitStats[unitId] == nil then
            self.UnitStats[unitId] = {}
        end

        if self.UnitStats[unitId][statName] == nil then
            self.UnitStats[unitId][statName] = value
        else
            self.UnitStats[unitId][statName] = self.UnitStats[unitId][statName] + value
        end
    end,

    ---@param self AIBrain
    ---@param unitId EntityId
    ---@param statName string
    ---@param value number
    SetUnitStat = function(self, unitId, statName, value)
        if self.UnitStats[unitId] == nil then
            self.UnitStats[unitId] = {}
        end

        self.UnitStats[unitId][statName] = value
    end,

    ---@param self AIBrain
    ---@param unitId EntityId
    ---@param statName string
    ---@return number
    GetUnitStat = function(self, unitId, statName)
        if self.UnitStats[unitId] == nil or self.UnitStats[unitId][statName] == nil then
            return 0
        end

        return self.UnitStats[unitId][statName]
    end,

    ---@param self AIBrain
    GetUnitStats = function(self)
        return self.UnitStats
    end,
}

---@class AIBrainJammerComponent
---@field Jammers table<EntityId, Unit>
local AIBrainJammerComponent = ClassSimple {

    ---@param self AIBrainHQComponent | AIBrain
    CreateBrainShared = function(self)
        self.JammerResetTime = 15
        self.Jammers = {}
        setmetatable(self.Jammers, { __mode = 'v' })
        ForkThread(self.JammingToggleThread, self)
    end,

    --- Adds a unit to a list of all units with jammers
    ---@param self AIBrain
    ---@param unit Unit Jammer unit
    TrackJammer = function(self, unit)
        self.Jammers[unit.EntityId] = unit
    end,

    --- Removes a unit to a list of all units with jammers
    ---@param self AIBrain
    ---@param unit Unit Jammer unit
    UntrackJammer = function(self, unit)
        self.Jammers[unit.EntityId] = nil
    end,

    --- Creates a thread that interates over all jammer units to reset them when vision is lost on them
    ---@param self AIBrain
    JammingToggleThread = function(self)
        while true do
            for i, jammer in self.Jammers do
                if jammer.ResetJammer == 0 then
                    self:ForkThread(self.JammingFollowUpThread, jammer)
                    jammer.ResetJammer = -1
                else
                    if jammer.ResetJammer > 0 then
                        jammer.ResetJammer = jammer.ResetJammer - 1
                    end
                end
            end
            WaitSeconds(1)
        end
    end,

    --- Toggles a given unit's jammer
    ---@param self AIBrain
    ---@param unit Unit Jammer to be toggled
    JammingFollowUpThread = function(self, unit)
        unit:DisableUnitIntel('AutoToggle', 'Jammer')
        WaitSeconds(1)
        if not unit:BeenDestroyed() then
            unit:EnableUnitIntel('AutoToggle', 'Jammer')
            unit.ResetJammer = -1
        end
    end,

    ---@param self AIBrain
    ---@param blip Blip
    ---@param reconType ReconTypes
    ---@param val boolean
    OnIntelChange = function(self, blip, reconType, val)
        if reconType == 'LOSNow' or reconType == 'Omni' then
            if not val then
                local unit = blip:GetSource()
                if unit.Blueprint.Intel.JammerBlips > 0 then
                    unit.ResetJammer = self.JammerResetTime
                end
            end
        end
    end,
}

---@class AIBrainEnergyComponent
---@field EnergyDepleted boolean
---@field EnergyDependingUnits table<EntityId, Unit>
---@field EnergyExcessConsumed number
---@field EnergyExcessRequired number
---@field EnergyExcessConverted number
---@field EnergyExcessUnitsEnabled table<EntityId, Unit>
---@field EnergyExcessUnitsDisabled table<EntityId, Unit>
local AIBrainEnergyComponent = ClassSimple {
    CreateBrainShared = function(self)
        -- make sure there is always some storage
        self:GiveStorage('Energy', 100)

        -- make sure the army stats exist
        self:SetArmyStat('Economy_Ratio_Mass', 1.0)
        self:SetArmyStat('Economy_Ratio_Energy', 1.0)

        -- add initial trigger and assume we're not depleted
        self:SetArmyStatsTrigger('Economy_Ratio_Energy', 'EnergyDepleted', 'LessThanOrEqual', 0.0)
        self.EnergyDepleted = false
        self.EnergyDependingUnits = setmetatable({}, { __mode = 'v' })

        --- Units that we toggle on / off depending on whether we have excess energy
        self.EnergyExcessConsumed = 0
        self.EnergyExcessRequired = 0
        self.EnergyExcessConverted = 0
        self.EnergyExcessUnitsEnabled = setmetatable({}, { __mode = 'v' })
        self.EnergyExcessUnitsDisabled = setmetatable({}, { __mode = 'v' })
    end,

    --- Adds an entity to the list of entities that receive callbacks when the energy storage is depleted or viable, expects the functions OnEnergyDepleted and OnEnergyViable on the unit
    ---@param self AIBrain
    ---@param entity Unit
    AddEnergyDependingEntity = function(self, entity)
        self.EnergyDependingUnits[entity.EntityId] = entity

        -- guarantee callback when entity is depleted
        if self.EnergyDepleted then
            entity:OnEnergyDepleted()
        end
    end,

    --- Adds a unit that is enabled / disabled depending on how much energy storage we have. The unit starts enabled
    ---@param self AIBrain The brain itself
    ---@param unit MassFabricationUnit The unit to keep track of
    AddEnabledEnergyExcessUnit = function(self, unit)
        self.EnergyExcessUnitsEnabled[unit.EntityId] = unit
        self.EnergyExcessUnitsDisabled[unit.EntityId] = nil

        local ecobp = unit.Blueprint.Economy
        self.EnergyExcessConsumed = self.EnergyExcessConsumed + ecobp.MaintenanceConsumptionPerSecondEnergy
        self.EnergyExcessConverted = self.EnergyExcessConverted + ecobp.ProductionPerSecondMass
    end,

    --- Adds a unit that is enabled / disabled depending on how much energy storage we have. The unit starts disabled
    ---@param self AIBrain
    ---@param unit MassFabricationUnit The unit to keep track of
    AddDisabledEnergyExcessUnit = function(self, unit)
        self.EnergyExcessUnitsEnabled[unit.EntityId] = nil
        self.EnergyExcessUnitsDisabled[unit.EntityId] = unit
        self.EnergyExcessRequired = self.EnergyExcessRequired +
            unit.Blueprint.Economy.MaintenanceConsumptionPerSecondEnergy
    end,

    --- Removes a unit that is enabled / disabled depending on how much energy storage we have
    ---@param self AIBrain
    ---@param unit MassFabricationUnit The unit to forget about
    RemoveEnergyExcessUnit = function(self, unit)
        local ecobp = unit.Blueprint.Economy
        if self.EnergyExcessUnitsEnabled[unit.EntityId] then
            self.EnergyExcessConsumed = self.EnergyExcessConsumed - ecobp.MaintenanceConsumptionPerSecondEnergy
            self.EnergyExcessConverted = self.EnergyExcessConverted - ecobp.ProductionPerSecondMass
            self.EnergyExcessUnitsEnabled[unit.EntityId] = nil
        elseif self.EnergyExcessUnitsDisabled[unit.EntityId] then
            self.EnergyExcessRequired = self.EnergyExcessRequired - ecobp.MaintenanceConsumptionPerSecondEnergy
            self.EnergyExcessUnitsDisabled[unit.EntityId] = nil
        end
    end,

    --- A continious thread that across the life span of the brain. Is the heart and sole of the enabling and disabling of units that are designed to eliminate excess energy.
    ---@param self AIBrain
    ToggleEnergyExcessUnitsThread = function(self)

        -- allow for protected calls without closures
        ---@param unitToProcess MassFabricationUnit
        local function ProtectedOnExcessEnergy(unitToProcess)
            unitToProcess:OnExcessEnergy()
        end

        ---@param unitToProcess MassFabricationUnit
        local function ProtectedOnNoExcessEnergy(unitToProcess)
            unitToProcess:OnNoExcessEnergy()
        end

        local fabricatorParameters = import("/lua/shared/fabricatorbehaviorparams.lua")
        local disableRatio = fabricatorParameters.DisableRatio
        local disableStorage = fabricatorParameters.DisableStorage

        local enableRatio = fabricatorParameters.EnableRatio
        local enableTrend = fabricatorParameters.EnableTrend
        local enableStorage = fabricatorParameters.EnableStorage

        -- localize scope for better performance
        local pcall = pcall
        local TableSize = table.getsize
        local CoroutineYield = coroutine.yield

        local ok, msg


        -- Instead of creating a new sync table each tick, we'll reuse two tables as a double
        -- buffer: one table represents the data from the current tick, the other the data last
        -- synced. We only send the data when one field in the current tick differs from the last
        -- data synced, and then swap the two tables when that happens.
        local syncTable = {
            on = 0,
            off = 0,
            totalEnergyConsumed = 0,
            totalEnergyRequired = 0,
            totalMassProduced = 0,
        }
        local lastSyncTable = {
            on = 0,
            off = 0,
            totalEnergyConsumed = 0,
            totalEnergyRequired = 0,
            totalMassProduced = 0,
        }

        local EnergyExcessUnitsDisabled = self.EnergyExcessUnitsDisabled
        local EnergyExcessUnitsEnabled = self.EnergyExcessUnitsEnabled

        while true do

            local energyStoredRatio = self:GetEconomyStoredRatio('ENERGY')
            local energyStored = self:GetEconomyStored('ENERGY')
            local energyTrend = 10 * self:GetEconomyTrend('ENERGY')

            -- low on storage, start disabling them to fill our storages asap
            if energyStoredRatio < disableRatio and energyStored < disableStorage then

                -- while we have units to disable
                for id, unit in EnergyExcessUnitsEnabled do
                    if not unit:BeenDestroyed() then

                        local ecobp = unit.Blueprint.Economy
                        self.EnergyExcessConsumed = self.EnergyExcessConsumed -
                            ecobp.MaintenanceConsumptionPerSecondEnergy
                        self.EnergyExcessRequired = self.EnergyExcessRequired +
                            ecobp.MaintenanceConsumptionPerSecondEnergy
                        self.EnergyExcessConverted = self.EnergyExcessConverted - ecobp.ProductionPerSecondMass

                        -- update internal state
                        EnergyExcessUnitsDisabled[id] = unit
                        EnergyExcessUnitsEnabled[id] = nil

                        -- try to disable unit
                        ok, msg = pcall(unit.OnNoExcessEnergy, unit)

                        -- allow for debugging
                        if not ok then
                            WARN(string.format("ToggleEnergyExcessUnitsThread: %s", tostring(msg)))
                        end

                        break
                    end
                end

                -- high on storage and sufficient energy income, enable units
            elseif (energyStoredRatio >= enableRatio and energyTrend > enableTrend) or energyStored > enableStorage then

                -- while we have units to retrieve
                for id, unit in EnergyExcessUnitsDisabled do
                    if not unit:BeenDestroyed() then
                        local ecobp = unit.Blueprint.Economy
                        self.EnergyExcessConsumed = self.EnergyExcessConsumed +
                            ecobp.MaintenanceConsumptionPerSecondEnergy
                        self.EnergyExcessRequired = self.EnergyExcessRequired -
                            ecobp.MaintenanceConsumptionPerSecondEnergy
                        self.EnergyExcessConverted = self.EnergyExcessConverted + ecobp.ProductionPerSecondMass

                        -- update internal state
                        EnergyExcessUnitsDisabled[id] = nil
                        EnergyExcessUnitsEnabled[id] = unit

                        -- try to enable unit
                        ok, msg = pcall(unit.OnExcessEnergy, unit)

                        -- allow for debugging
                        if not ok then
                            WARN(string.format("ToggleEnergyExcessUnitsThread: %s", tostring(msg)))
                        end

                        break
                    end
                end
            end

            if self.Army == GetFocusArmy() then
                syncTable.on = TableSize(EnergyExcessUnitsEnabled)
                syncTable.off = TableSize(EnergyExcessUnitsDisabled)
                syncTable.totalEnergyConsumed = self.EnergyExcessConsumed
                syncTable.totalEnergyRequired = self.EnergyExcessRequired
                syncTable.totalMassProduced = self.EnergyExcessConverted
                -- only send new data
                if lastSyncTable.on ~= syncTable.on
                    or lastSyncTable.off ~= syncTable.off
                    or lastSyncTable.totalEnergyConsumed ~= syncTable.totalEnergyConsumed
                    or lastSyncTable.totalEnergyRequired ~= syncTable.totalEnergyRequired
                    or lastSyncTable.totalMassProduced ~= syncTable.totalMassProduced
                then
                    Sync.MassFabs = syncTable
                    -- swap the data buffers
                    syncTable, lastSyncTable = lastSyncTable, syncTable
                end
            end
            CoroutineYield(1)
        end
    end,

    OnStatsTrigger = function(self, triggerName)
        if triggerName == "EnergyDepleted" or triggerName == "EnergyViable" then
            self:OnEnergyTrigger(triggerName)
        end
    end,


    ---@param self AIBrain
    ---@param triggerName string
    OnEnergyTrigger = function(self, triggerName)
        if triggerName == "EnergyDepleted" then
            -- add trigger when we can recover units
            self:SetArmyStatsTrigger('Economy_Ratio_Energy', 'EnergyViable', 'GreaterThanOrEqual', 0.1)
            self.EnergyDepleted = true

            -- recurse over the list of units and do callbacks accordingly
            for id, entity in self.EnergyDependingUnits do
                if not IsDestroyed(entity) then
                    entity:OnEnergyDepleted()
                end
            end
        else
            -- add trigger when we're depleted
            self:SetArmyStatsTrigger('Economy_Ratio_Energy', 'EnergyDepleted', 'LessThanOrEqual', 0.0)
            self.EnergyDepleted = false

            -- recurse over the list of units and do callbacks accordingly
            for id, entity in self.EnergyDependingUnits do
                if not IsDestroyed(entity) then
                    entity:OnEnergyViable()
                end
            end
        end
    end,

}

local BrainGetUnitsAroundPoint = moho.aibrain_methods.GetUnitsAroundPoint
local BrainGetListOfUnits = moho.aibrain_methods.GetListOfUnits
local CategoriesDummyUnit = categories.DUMMYUNIT

---@class AIBrain: AIBrainHQComponent, AIBrainStatisticsComponent, AIBrainJammerComponent, AIBrainEnergyComponent, moho.aibrain_methods
---@field AI boolean
---@field Name string           # Army name
---@field Nickname string       # Player / AI / character name
---@field Status BrainState
---@field Human boolean
---@field Civilian boolean
---@field Trash TrashBag
---@field UnitBuiltTriggerList table
---@field PingCallbackList { CallbackFunction: fun(pingData: any), PingType: string }[]
---@field BrainType 'Human' | 'AI'
---@field CustomUnits { [string]: EntityId[] }
AIBrain = Class(AIBrainHQComponent, AIBrainStatisticsComponent, AIBrainJammerComponent, AIBrainEnergyComponent,
    moho.aibrain_methods) {

    Status = 'InProgress',

    --- Called after `SetupSession` but before `BeginSession` - no initial units, props or resources exist at this point
    ---@param self AIBrain
    ---@param planName string
    OnCreateHuman = function(self, planName)
        self.BrainType = 'Human'
        self:CreateBrainShared(planName)

        self.EnergyExcessThread = ForkThread(self.ToggleEnergyExcessUnitsThread, self)
    end,

    --- Called after `SetupSession` but before `BeginSession` - no initial units, props or resources exist at this point
    ---@param self AIBrain
    ---@param planName string
    OnCreateAI = function(self, planName)
        self.BrainType = 'AI'
        self:CreateBrainShared(planName)
    end,

    --- Called after `SetupSession` but before `BeginSession` - no initial units, props or resources exist at this point
    ---@param self AIBrain
    ---@param planName string
    CreateBrainShared = function(self, planName)
        self.Army = self:GetArmyIndex()
        self.Trash = TrashBag()
        self.TriggerList = {}

        -- local notInteresting = {
        --     GetArmyStat = true,
        --     GetBlueprintStat = true,
        --     GetEconomyStored = true,
        --     IsDefeated = true,
        --     Status = true,
        --     GetEconomyTrend = true,
        --     GetEconomyRatio = true,
        --     GetEconomyStoredRatio = true,
        -- }
        -- local meta = getmetatable(self)
        -- meta.__index = function(t, key)
        --     if not notInteresting[key] then
        --         LOG("BrainAccess: " .. tostring(key))
        --     end
        --     return meta[key]
        -- end

        -- keep track of radars
        self.Radars = {
            TECH1 = {},
            TECH2 = {},
            TECH3 = {},
            EXPERIMENTAL = {},
        }

        self.PingCallbackList = {}

        AIBrainEnergyComponent.CreateBrainShared(self)
        AIBrainHQComponent.CreateBrainShared(self)
        AIBrainStatisticsComponent.CreateBrainShared(self)
        AIBrainJammerComponent.CreateBrainShared(self)
    end,

    --- Called after `BeginSession`, at this point all props, resources and initial units exist
    ---@param self AIBrain
    OnBeginSession = function(self)
    end,

    ---@param self AIBrain
    OnDestroy = function(self)
        self.Trash:Destroy()
    end,

    ---@param self AIBrain
    OnSpawnPreBuiltUnits = function(self)
        local factionIndex = self:GetFactionIndex()
        local resourceStructures = nil
        local initialUnits = nil
        local posX, posY = self:GetArmyStartPos()

        if factionIndex == 1 then
            resourceStructures = { 'UEB1103', 'UEB1103', 'UEB1103', 'UEB1103' }
            initialUnits = { 'UEB0101', 'UEB1101', 'UEB1101', 'UEB1101', 'UEB1101' }
        elseif factionIndex == 2 then
            resourceStructures = { 'UAB1103', 'UAB1103', 'UAB1103', 'UAB1103' }
            initialUnits = { 'UAB0101', 'UAB1101', 'UAB1101', 'UAB1101', 'UAB1101' }
        elseif factionIndex == 3 then
            resourceStructures = { 'URB1103', 'URB1103', 'URB1103', 'URB1103' }
            initialUnits = { 'URB0101', 'URB1101', 'URB1101', 'URB1101', 'URB1101' }
        elseif factionIndex == 4 then
            resourceStructures = { 'XSB1103', 'XSB1103', 'XSB1103', 'XSB1103' }
            initialUnits = { 'XSB0101', 'XSB1101', 'XSB1101', 'XSB1101', 'XSB1101' }
        end

        if resourceStructures then
            -- Place resource structures down
            for k, v in resourceStructures do
                local unit = self:CreateResourceBuildingNearest(v, posX, posY)
            end
        end

        if initialUnits then
            -- Place initial units down
            for k, v in initialUnits do
                local unit = self:CreateUnitNearSpot(v, posX, posY)
            end
        end

        self.PreBuilt = true
    end,

    ---@param self AIBrain
    OnUnitCapLimitReached = function(self) end,

    ---@param self AIBrain
    OnFailedUnitTransfer = function(self)
        self:PlayVOSound('OnFailedUnitTransfer')
    end,

    ---@param self AIBrain
    OnPlayNoStagingPlatformsVO = function(self)
        self:PlayVOSound('OnPlayNoStagingPlatformsVO')
    end,

    ---@param self AIBrain
    OnPlayBusyStagingPlatformsVO = function(self)
        self:PlayVOSound('OnPlayBusyStagingPlatformsVO')
    end,

    ---@param self AIBrain
    OnPlayCommanderUnderAttackVO = function(self)
        self:PlayVOSound('OnPlayCommanderUnderAttackVO')
    end,

    ---@param self AIBrain
    ---@param sound SoundHandle
    NuclearLaunchDetected = function(self, sound)
        self:PlayVOSound('NuclearLaunchDetected', sound)
    end,

    ---@param self AIBrain
    ---@param triggerSpec TriggerSpec
    SetupArmyIntelTrigger = function(self, triggerSpec)
        local intelTriggerList = self.IntelTriggerList
        if not intelTriggerList then
            intelTriggerList = {}
            self.IntelTriggerList = intelTriggerList
        end

        table.insert(intelTriggerList, triggerSpec)
    end,

    ---@param self AIBrain
    ---@param blip any the unit (could be fake) in question
    ---@param reconType ReconTypes
    ---@param val boolean
    OnIntelChange = function(self, blip, reconType, val)
        local intelTriggerList = self.IntelTriggerList
        if intelTriggerList then
            for k, v in intelTriggerList do
                if EntityCategoryContains(v.Category, blip:GetBlueprint().BlueprintId)
                    and v.Type == reconType and (not v.Blip or v.Blip == blip:GetSource())
                    and v.Value == val and v.TargetAIBrain == blip:GetAIBrain() then
                    v.CallbackFunction(blip)
                    if v.OnceOnly then
                        intelTriggerList[k] = nil
                    end
                end
            end
        end

        AIBrainJammerComponent.OnIntelChange(self, blip, reconType, val)
    end,

    -- System for playing VOs to the Player
    VOSounds = {
        NuclearLaunchDetected = { timeout = 1, bank = nil, obs = true },
        OnTransportFull = { timeout = 1, bank = nil },
        OnFailedUnitTransfer = { timeout = 10, bank = 'Computer_Computer_CommandCap_01298' },
        OnPlayNoStagingPlatformsVO = { timeout = 5, bank = 'XGG_Computer_CV01_04756' },
        OnPlayBusyStagingPlatformsVO = { timeout = 5, bank = 'XGG_Computer_CV01_04755' },
        OnPlayCommanderUnderAttackVO = { timeout = 15, bank = 'Computer_Computer_Commanders_01314' },
    },

    ---@param self AIBrain
    ---@param key string
    ---@param sound SoundHandle
    PlayVOSound = function(self, key, sound)
        if not self.VOSounds[key] then
            WARN("PlayVOSound: " .. key .. " not found")
            return
        end

        local cue, bank
        if sound then
            cue, bank = GetCueBank(sound)
        else
            -- note: what the VO sound table calls a "bank" is actually a "cue"
            cue, bank = self.VOSounds[key]["bank"], "XGG"
        end

        if not (bank and cue) then
            WARN("PlayVOSound: No valid bank/cue for " .. key)
            return
        end

        ForkThread(self.PlayVOSoundThread, self, key, {
            Cue = cue,
            Bank = bank,
        })
    end,

    ---@param self AIBrain
    ---@param key string
    ---@param data SoundBlueprint
    PlayVOSoundThread = function(self, key, data)
        if not self.VOTable then
            self.VOTable = {}
        end
        if self.VOTable[key] then
            return
        end
        local sound = self.VOSounds[key]
        local focusArmy = GetFocusArmy()
        local armyIndex = self:GetArmyIndex()
        if focusArmy ~= armyIndex and not (focusArmy == -1 and armyIndex == 1 and sound.obs) then
            return
        end

        self.VOTable[key] = true

        import("/lua/SimSyncUtils.lua").SyncVoice(data)
        WaitSeconds(sound.timeout)

        self.VOTable[key] = nil
    end,

    --- Triggers based on an AiBrain
    ---@param self AIBrain
    ---@param triggerName string
    OnStatsTrigger = function(self, triggerName)
        AIBrainEnergyComponent.OnStatsTrigger(self, triggerName)

        for k, v in self.TriggerList do
            if v.Name == triggerName then
                if v.CallingObject then
                    if not v.CallingObject:BeenDestroyed() then
                        v.CallbackFunction(v.CallingObject)
                    end
                else
                    v.CallbackFunction(self)
                end
                table.remove(self.TriggerList, k)
            end
        end
    end,

    ---@param self AIBrain
    ---@param triggerName string
    RemoveEconomyTrigger = function(self, triggerName)
        for k, v in self.TriggerList do
            if v.Name == triggerName then
                table.remove(self.TriggerList, k)
            end
        end
    end,

    ---@param self AIBrain
    ---@param callback fun(unit:Unit)
    ---@param category EntityCategory
    ---@param percent number
    AddUnitBuiltPercentageCallback = function(self, callback, category, percent)
        if not callback or not category or not percent then
            error('*ERROR: Attempt to add UnitBuiltPercentageCallback but invalid data given', 2)
        end

        local unitBuiltTriggerList = self.UnitBuiltTriggerList
        if not unitBuiltTriggerList then
            unitBuiltTriggerList = {}
            self.UnitBuiltTriggerList = unitBuiltTriggerList
        end

        table.insert(unitBuiltTriggerList, {
            Callback = callback,
            Category = category,
            Percent = percent
        })
    end,

    ---@param self AIBrain
    ---@param triggerSpec TriggerSpec
    SetupBrainVeterancyTrigger = function(self, triggerSpec)
        if not triggerSpec.CallCount then
            triggerSpec.CallCount = 1
        end

        local veterancyTriggerList = self.VeterancyTriggerList
        if not veterancyTriggerList then
            veterancyTriggerList = {}
            self.VeterancyTriggerList = veterancyTriggerList
        end

        table.insert(veterancyTriggerList, triggerSpec)
    end,

    ---@param self AIBrain
    ---@param unit Unit
    ---@param level number
    OnBrainUnitVeterancyLevel = function(self, unit, level)
        local veterancyTriggerList = self.VeterancyTriggerList
        if veterancyTriggerList then
            for _, v in veterancyTriggerList do
                if v.CallCount > 0 and
                    level == v.Level and
                    EntityCategoryContains(v.Category, unit)
                then
                    v.CallCount = v.CallCount - 1
                    v.CallbackFunction(unit)
                end
            end
        end
    end,

    ---@param self AIBrain
    ---@param fn function
    ---@param ... any
    ---@return thread|nil
    ForkThread = function(self, fn, ...)
        if fn then
            local thread = ForkThread(fn, self, unpack(arg))
            self.Trash:Add(thread)
            return thread
        else
            return nil
        end
    end,

    ---@param self AIBrain
    IsDefeated = function(self)
        local status = self.Status
        return status == "Defeat" or status == "Recalled" or ArmyIsOutOfGame(self.Army)
    end,

    ---@param self AIBrain
    OnTransportFull = function(self)
        if not self.loadingTransport or self.loadingTransport.full then return end

        local cue
        self.loadingTransport.transData.full = true
        if EntityCategoryContains(categories.uaa0310, self.loadingTransport) then
            -- "CZAR FULL"
            cue = 'XGG_Computer_CV01_04753'
        elseif EntityCategoryContains(categories.NAVALCARRIER, self.loadingTransport) then
            -- "Aircraft Carrier Full"
            cue = 'XGG_Computer_CV01_04751'
        else
            cue = 'Computer_TransportIsFull'
        end

        self:PlayVOSound('OnTransportFull', Sound { Bank = 'XGG', Cue = cue })
    end,

    ---@param self AIBrain
    OnDraw = function(self)
        self.Status = 'Draw'
    end,

    ---@param self AIBrain
    OnVictory = function(self)
        self.Status = 'Victory'
    end,

    ---@param self AIBrain
    OnDefeat = function(self)
        -- OnDefeat runs after AbandonedByPlayer, so we need to prevent killing the army twice
        if self.Status == 'Defeat' then
            return
        end 
        self.Status = 'Defeat'

        local selfIndex = self:GetArmyIndex()
        UpdateUnitCap(selfIndex)
        OnArmyDefeat(selfIndex)

        -- AI
        if self.BrainType == 'AI' then
            DisableAI(self)
        end

        ForkThread(KillArmy, self, ScenarioInfo.Options.Share)

        if self.Trash then
            self.Trash:Destroy()
        end
    end,

    --- Called by the engine when a player disconnects.
    ---@param self AIBrain
    AbandonedByPlayer = function(self)
        if not IsGameOver() then
            self.Status = 'Defeat'

            import("/lua/simutils.lua").UpdateUnitCap(self:GetArmyIndex())
            import("/lua/simping.lua").OnArmyDefeat(self:GetArmyIndex())

            -- AI
            if self.BrainType == 'AI' then
                DisableAI(self)
            end

            local shareOption = ScenarioInfo.Options.DisconnectShare
            local shareAcuOption = ScenarioInfo.Options.DisconnectShareCommanders
            local victoryOption = ScenarioInfo.Options.Victory
            
            if shareOption == 'SameAsShare' then
                shareOption = ScenarioInfo.Options.Share
            end

            -- Don't apply instant-effect disconnect rules for players/ACUs that might be defeated soon,
            -- and might have intentionally disconnected.
            if shareAcuOption == 'Explode' or shareAcuOption == 'Recall' then
                local safeCommanders = {}

                local commanders = self:GetListOfUnits(categories.COMMAND, false)
                for _, com in commanders do
                    if com.LastTickDamaged + CommanderSafeTime <= GetGameTick() then
                        table.insert(safeCommanders, com)
                    end
                end

                -- Only handle Assassination victory, as in other settings the player is unlikely to be defeated soon
                if victoryOption == 'demoralization' and table.empty(safeCommanders) then
                    shareOption = ScenarioInfo.Options.Share
                end

                -- non-assassination modes can have armies abandon without commanders
                if shareAcuOption == 'Recall' and not table.empty(safeCommanders) then
                    -- KillArmy waits 10 seconds before acting, while FakeTeleport waits 3 seconds, so the ACU shouldn't explode.
                    ForkThread(FakeTeleportUnits, safeCommanders, true)
                end

                ForkThread(KillArmy, self, shareOption)

            elseif shareAcuOption == 'RecallDelayed' or shareAcuOption == 'Permanent' then

                if victoryOption ~= 'demoralization' then
                    shareOption = 'FullShare'
                end

                if shareAcuOption == 'RecallDelayed' then
                    local shareTime = GetGameTick() + CommanderSafeTime
                    if shareTime < 3000 then
                        shareTime = 3000
                    end
                    ForkThread(KillArmyOnDelayedRecall, self, shareOption, shareTime)
                else
                    ForkThread(KillArmyOnACUDeath, self, shareOption)
                end
            else
                WARN('Invalid disconnection ACU share condition was used for this game. Defaulting to exploding ACU.')
                ForkThread(KillArmy, self, shareOption)
            end


            if self.Trash then
                self.Trash:Destroy()
            end
        end
    end,

    ---@param self AIBrain
    RecallAllCommanders = function(self)
        local commandCat = categories.COMMAND + categories.SUBCOMMANDER
        self:ForkThread(self.RecallArmyThread, self:GetListOfUnits(commandCat, false))
    end,

    ---@param self AIBrain
    ---@param recallingUnits Unit[]
    RecallArmyThread = function(self, recallingUnits)
        if recallingUnits then
            FakeTeleportUnits(recallingUnits, true)
        end
        self:OnRecalled()
    end,

    OnRecalled = function(self)
        -- TODO: create a common function for `OnDefeat` and `OnRecall`
        self.Status = "Recalled"

        local selfIndex = self:GetArmyIndex()
        UpdateUnitCap(selfIndex)
        OnArmyDefeat(selfIndex)

        -- AI
        if self.BrainType == "AI" then
            DisableAI(self)
        end

        local enemies, civilians = {}, {}

        -- Sort brains out into mutually exclusive categories
        for index, brain in ArmyBrains do
            brain.index = index

            if not brain:IsDefeated() and selfIndex ~= index then
                if ArmyIsCivilian(index) then
                    table.insert(civilians, brain)
                elseif IsEnemy(selfIndex, brain:GetArmyIndex()) then
                    table.insert(enemies, brain)
                end
            end
        end

        -- Recalling has different share conditions than defeat because the entire team recalls simultaneously.
        -- Recalling recalls all SACU, so they shouldn't be transferred.
        local recallCat = categories.ALLUNITS - categories.WALL - categories.COMMAND - categories.SUBCOMMANDER
        local shareOption = ScenarioInfo.Options.Share
        if shareOption == 'CivilianDeserter' then
            TransferUnitsToBrain(self, civilians, false, recallCat, "CivilianDeserter")
        elseif shareOption == 'Defectors' then
            TransferUnitsToHighestBrain(self, enemies, false, recallCat, "Defectors")
        end

        -- let the average, team vs team game end first
        WaitSeconds(10.0)

        -- Kill all units left over
        local tokill = self:GetListOfUnits(categories.ALLUNITS - categories.WALL, false)
        if tokill then
            for _, unit in tokill do
                if not IsDestroyed(unit) then
                    unit:Kill()
                end
            end
        end

        local trash = self.Trash
        if trash then
            trash:Destroy()
        end
    end,

    --------------------------------------------------------------------------------
    --#region ping functionality

    ---@param self AIBrain
    ---@param callback function
    ---@param pingType string
    AddPingCallback = function(self, callback, pingType)
        if callback and pingType then
            table.insert(self.PingCallbackList, { CallbackFunction = callback, PingType = pingType })
        end
    end,

    ---@param self AIBrain
    ---@param pingData table
    DoPingCallbacks = function(self, pingData)
        for _, v in self.PingCallbackList do
            v.CallbackFunction(self, pingData)
        end
    end,

    ---@param self AIBrain
    ---@param pingData table
    DoAIPing = function(self, pingData)
        if self.Sorian then
            if pingData.Type then
                SUtils.AIHandlePing(self, pingData)
            end
        end
    end,

    --#endregion
    -------------------------------------------------------------------------------

    -------------------------------------------------------------------------------
    --#region overwritten c-functionality

    --- Retrieves all units that fit the criteria around some point. Excludes dummy units.
    ---@param self AIBrain
    ---@param category EntityCategory The categories the units should fit.
    ---@param position Vector The center point to start looking for units.
    ---@param radius number The radius of the circle we look for units in.
    ---@param alliance AllianceStatus
    ---@return Unit[]
    GetUnitsAroundPoint = function(self, category, position, radius, alliance)
        if alliance then
            -- call where we do care about alliance
            return BrainGetUnitsAroundPoint(self, category - CategoriesDummyUnit, position, radius, alliance)
        else
            -- call where we do not, which is different from providing nil (as there would be a fifth argument then)
            return BrainGetUnitsAroundPoint(self, category - CategoriesDummyUnit, position, radius)
        end
    end,

    --- Returns list of units by category. Excludes dummy units.
    ---@param self AIBrain
    ---@param cats EntityCategory Unit's category, example: categories.TECH2 .
    ---@param needToBeIdle boolean true/false Unit has to be idle (appears to be not functional).
    ---@param requireBuilt? boolean true/false defaults to false which excludes units that are NOT finished (appears to be not functional).
    ---@return Unit[]
    GetListOfUnits = function(self, cats, needToBeIdle, requireBuilt)
        -- defaults to false, prevent sending nil
        requireBuilt = requireBuilt or false

        -- retrieve units, excluding insignificant units
        return BrainGetListOfUnits(self, cats - CategoriesDummyUnit, needToBeIdle, requireBuilt)
    end,

    --#endregion
    -------------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    --#region Unit events

    --- Represents a list of unit events that are communicated to the brain. It makes it
    --- easier to respond to conditions that are happening on the battlefield. The following
    --- unit events are not communicated to the brain:
    ---
    --- - OnStorageChange (use OnAddToStorage and OnRemoveFromStorage instead)
    --- - OnAnimCollision
    --- - OnTerrainTypeChange
    --- - OnMotionVertEventChange
    --- - OnMotionHorzEventChange
    --- - OnLayerChange
    --- - OnPrepareArmToBuild
    --- - OnStartBuilderTracking
    --- - OnStopBuilderTracking
    --- - OnStopRepeatQueue
    --- - OnStartRepeatQueue
    --- - OnAssignedFocusEntity
    ---
    --- And events that are purposefully not communicated:
    ---
    --- - OnDamage
    --- - OnDamageBy
    --- - OnMotionHorzEventChange
    --- - OnMotionVertEventChange
    ---
    --- If you're interested for one of these events then you're encouraged to make a pull
    --- request to add the event!


    --- Called by a unit as it starts being built
    ---@param self AIBrain
    ---@param unit Unit
    ---@param builder Unit
    ---@param layer Layer
    OnUnitStartBeingBuilt = function(self, unit, builder, layer)
        -- do nothing
    end,

    --- Called by a unit as it is finished being built
    ---@param self AIBrain
    ---@param unit Unit
    ---@param builder Unit
    ---@param layer Layer
    OnUnitStopBeingBuilt = function(self, unit, builder, layer)
        -- do nothing
    end,

    --- Called by a unit as it is destroyed
    ---@param self AIBrain
    ---@param unit Unit
    OnUnitDestroy = function(self, unit)
        -- do nothing
    end,

    --- Called by a unit when it loses or gains health. It is also called when the unit is being built. It is called at fixed intervals of 25%
    ---@param self AIBrain
    ---@param unit Unit
    ---@param new number # 0.25 / 0.50 / 0.75 / 1.0
    ---@param old number # 0.25 / 0.50 / 0.75 / 1.0
    OnUnitHealthChanged = function(self, unit, new, old)
        -- do nothing
    end,

    --- Called by a unit of this army when it stops reclaiming
    ---@param self AIBrain
    ---@param unit Unit
    ---@param target Unit | Prop | nil      # is nil when the prop or unit is completely reclaimed
    OnUnitStopReclaim = function(self, unit, target)
        -- do nothing
    end,

    --- Called by a unit of this army when it starts reclaiming
    ---@param self AIBrain
    ---@param unit Unit
    ---@param target Unit | Prop
    OnUnitStartReclaim = function(self, unit, target)
        -- do nothing
    end,

    --- Called by a unit of this army when it starts repairing
    ---@param self AIBrain
    ---@param unit Unit
    ---@param target Unit
    OnUnitStartRepair = function(self, unit, target)
        -- do nothing
    end,

    --- Called by a unit of this army when it stops repairing
    ---@param self AIBrain
    ---@param unit Unit
    ---@param target Unit
    OnUnitStopRepair = function(self, unit, target)
        -- do nothing
    end,

    --- Called by a unit of this army when it is killed
    ---@param self AIBrain
    ---@param unit Unit
    ---@param instigator Unit | Projectile | nil
    ---@param damageType DamageType
    ---@param overkillRatio number
    OnUnitKilled = function(self, unit, instigator, damageType, overkillRatio)
        -- do nothing
    end,

    --- Called by a unit of this army when it is reclaimed
    ---@param self AIBrain
    ---@param unit Unit
    ---@param reclaimer Unit
    OnUnitReclaimed = function(self, unit, reclaimer)
        -- do nothing
    end,

    --- Called by a unit of this army when it starts a capture command
    ---@param self AIBrain
    ---@param unit Unit
    ---@param target Unit
    OnUnitStartCapture = function(self, unit, target)
        -- do nothing
    end,

    --- Called by a unit of this army when it stops a capture command
    ---@param self AIBrain
    ---@param unit Unit
    ---@param target Unit
    OnUnitStopCapture = function(self, unit, target)
        -- do nothing
    end,

    --- Called by a unit of this army when it fails a capture command
    ---@param self AIBrain
    ---@param unit Unit
    ---@param target Unit
    OnUnitFailedCapture = function(self, unit, target)
        -- do nothing
    end,

    --- Called by a unit of this army when it starts being captured
    ---@param self AIBrain
    ---@param unit Unit
    ---@param captor Unit
    OnUnitStartBeingCaptured = function(self, unit, captor)
        -- do nothing
    end,

    --- Called by a unit of this army when it stops being captured
    ---@param self AIBrain
    ---@param unit Unit
    ---@param captor Unit
    OnUnitStopBeingCaptured = function(self, unit, captor)
        -- do nothing
    end,

    --- Called by a unit of this army when it failed being captured
    ---@param self AIBrain
    ---@param unit Unit
    ---@param captor Unit
    OnUnitFailedBeingCaptured = function(self, unit, captor)
        -- do nothing
    end,

    --- Called by a unit when it starts building a missile
    ---@param self AIBrain
    ---@param unit Unit
    ---@param weapon Weapon
    OnUnitSiloBuildStart = function(self, unit, weapon)
        -- do nothing
    end,

    --- Called by a unit when it stops building a missile
    ---@param self AIBrain
    ---@param unit Unit
    ---@param weapon Weapon
    OnUnitSiloBuildEnd = function(self, unit, weapon)
        -- do nothing
    end,

    --- Called by a unit when it starts building another unit
    ---@param self AIBrain
    ---@param unit Unit
    ---@param target Unit
    ---@param order string
    OnUnitStartBuild = function(self, unit, target, order)
        -- do nothing
    end,

    --- Called by a unit when it stops building another unit
    ---@param self AIBrain
    ---@param unit Unit
    ---@param target Unit
    ---@param order string
    OnUnitStopBuild = function(self, unit, target, order)
        -- do nothing
    end,

    --- Called by a unit as it is being built
    ---@param self AIBrain
    ---@param unit Unit
    ---@param target Unit
    ---@param old number
    ---@param new number
    OnUnitBuildProgress = function(self, unit, target, old, new)
        -- do nothing
    end,

    --- Called by a unit as it is paused
    ---@param self AIBrain
    ---@param unit Unit
    OnUnitPaused = function(self, unit)
        -- do nothing
    end,

    --- Called by a unit as it is unpaused
    ---@param self AIBrain
    ---@param unit Unit
    OnUnitUnpaused = function(self, unit)
        -- do nothing
    end,

    --- Called by a unit as it is being built. It is called for every builder. it is called in intervals of 25%.
    ---@param self AIBrain
    ---@param unit Unit
    ---@param builder Unit
    ---@param old number
    ---@param new number
    OnUnitBeingBuiltProgress = function(self, unit, builder, old, new)
        -- do nothing
    end,

    --- Called by a unit as it failed to be built
    ---@param self AIBrain
    ---@param unit Unit
    OnUnitFailedToBeBuilt = function(self, unit)
        -- do nothing
    end,

    --- Called by a transport as it attaches a unit
    ---@param self AIBrain
    ---@param unit Unit
    ---@param attachBone Bone
    ---@param attachedUnit Unit
    OnUnitTransportAttach = function(self, unit, attachBone, attachedUnit)
        -- do nothing
    end,

    --- Called by a transport as it deattaches a unit
    ---@param self AIBrain
    ---@param unit Unit
    ---@param attachBone Bone
    ---@param detachedUnit Unit
    OnUnitTransportDetach = function(self, unit, attachBone, detachedUnit)
        -- do nothing
    end,

    --- Called by a transport as it aborts the transport order
    ---@param self AIBrain
    ---@param unit Unit
    OnUnitTransportAborted = function(self, unit)
        -- do nothing
    end,

    --- Called by a transport as it starts the transport order
    ---@param self AIBrain
    ---@param unit Unit
    OnUnitTransportOrdered = function(self, unit)
        -- do nothing
    end,

    --- Called by a transport as units that are attached are killed
    ---@param self AIBrain
    ---@param unit Unit
    ---@param attachedUnit Unit
    OnUnitAttachedKilled = function(self, unit, attachedUnit)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Starts the loading sequence (transports, carriers)
    --- - Deploys its cargo (transports, carriers)
    ---@param self AIBrain
    ---@param unit Unit
    OnUnitStartTransportLoading = function(self, unit)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Starts the loading sequence (transports, carriers)
    --- - Deploys its cargo (transports, carriers)
    ---@param self AIBrain
    ---@param unit Unit
    OnUnitStopTransportLoading = function(self, unit)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Starts beaming up to a transport
    ---@param self AIBrain
    ---@param unit Unit
    ---@param transport Unit
    ---@param bone Bone
    OnUnitStartTransportBeamUp = function(self, unit, transport, bone)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Stops beaming up to a transport regardless whether it succeeded
    ---@param self AIBrain
    ---@param unit Unit
    OnUnitStoptransportBeamUp = function(self, unit)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Attaches to a transport
    ---@param self AIBrain
    ---@param unit Unit
    ---@param transport Unit
    ---@param bone Bone
    OnUnitAttachedToTransport = function(self, unit, transport, bone)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Deattaches to a transport
    ---@param self AIBrain
    ---@param unit Unit
    ---@param transport Unit
    ---@param bone Bone
    OnUnitDetachedFromTransport = function(self, unit, transport, bone)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Enters the storage of a carrier
    ---@param self AIBrain
    ---@param unit Unit
    ---@param carrier Unit
    OnUnitAddToStorage = function(self, unit, carrier)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Leaves the storage of a carrier
    ---@param self AIBrain
    ---@param unit Unit
    ---@param carrier Unit
    OnUnitRemoveFromStorage = function(self, unit, carrier)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Starts a teleport sequence
    ---@param self AIBrain
    ---@param unit Unit
    ---@param teleporter any
    ---@param location Vector
    ---@param orientation Quaternion
    OnUnitTeleportUnit = function(self, unit, teleporter, location, orientation)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Aborts a teleport sequence
    ---@param self AIBrain
    ---@param unit Unit
    OnUnitFailedTeleport = function(self, unit)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Enables its shield
    ---@param self AIBrain
    ---@param unit Unit
    OnUnitShieldEnabled = function(self, unit)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Disables its shield, regardless of the cause
    ---@param self AIBrain
    ---@param unit Unit
    OnUnitShieldDisabled = function(self, unit)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Finishes the construction of a tactical or strategical missile
    ---@param self AIBrain
    ---@param unit Unit
    OnUnitNukeArmed = function(self, unit)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Starts the launch sequence of a strategic missile
    ---@param self AIBrain
    ---@param unit Unit
    OnUnitNukeLaunched = function(self, unit)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Starts an enhancement
    ---@param self AIBrain
    ---@param unit Unit
    ---@param work any
    OnUnitWorkBegin = function(self, unit, work)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Finishes an enhancement
    ---@param self AIBrain
    ---@param unit Unit
    ---@param work any
    OnUnitWorkEnd = function(self, unit, work)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Aborts an enhancement
    ---@param self AIBrain
    ---@param unit Unit
    ---@param work any
    OnUnitWorkFail = function(self, unit, work)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Launches a missile that impacts with a shield
    ---@param self AIBrain
    ---@param target Vector
    ---@param shield Unit
    ---@param position Vector
    OnUnitMissileImpactShield = function(self, unit, target, shield, position)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Launches a missile that impacts with the terrain (unlike a unit or a shield)
    ---@param self AIBrain
    ---@param unit Unit
    ---@param target Vector
    ---@param position Vector
    OnUnitMissileImpactTerrain = function(self, unit, target, position)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Launches a missile that is intercepted by tactical missile defenses
    ---@param self AIBrain
    ---@param unit Unit
    ---@param target Vector
    ---@param defense Unit
    ---@param position Vector
    OnUnitMissileIntercepted = function(self, unit, target, defense, position)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Starts finishes the sacrifice command
    ---@param self AIBrain
    ---@param unit Unit
    ---@param target Unit
    OnUnitStartSacrifice = function(self, unit, target)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Succesfully finishes the sacrifice command
    ---@param self AIBrain
    ---@param unit Unit
    ---@param target Unit
    OnUnitStopSacrifice = function(self, unit, target)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Starts building/repairing another unit (engineers, factories)
    --- - Starts consuming resources for unit properties (fabricators that produce mass, radars that produce intel)
    ---@param self AIBrain
    ---@param unit Unit
    OnUnitConsumptionActive = function(self, unit)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Stops building/repairing another unit (engineers, factories)
    --- - Stops consuming resources for unit properties (fabricators that produce mass, radars that produce intel)
    ---@param self AIBrain
    ---@param unit Unit
    OnUnitConsumptionInActive = function(self, unit)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Starts producing resources (power generators, extractors, ...)
    ---@param self AIBrain
    ---@param unit Unit
    OnUnitProductionActive = function(self, unit)
        -- do nothing
    end,

    --- Event happens when a unit:
    --- - Stops producing resources (power generators, extractors, ...)
    ---
    --- Note: it may not trigger when a unit is killed.
    ---@param self AIBrain
    ---@param unit Unit
    OnUnitProductionInActive = function(self, unit)
        -- do nothing
    end,

    --#endregion
    ---------------------------------------------------------------------------

    -------------------------------------------------------------------------------
    --#region deprecated

    --- All functions in this region exist because they may still be called from
    --- unmaintained mods. They no longer serve any purpose.

    ---@deprecated
    ---@param self AIBrain
    ReportScore = function(self)
    end,

    ---@deprecated
    ---@param self AIBrain
    ---@param result AIResult
    SetResult = function(self, result)
    end,

    --#endregion
    -------------------------------------------------------------------------------

    -------------------------------------------------------------------------------
    --#region legacy functionality

    --- All functions below solely exist because the code is too tightly coupled.
    --- We can't remove them without drastically changing how the code base works.
    --- We can't do that because it would break mod compatibility

    ---@deprecated
    ---@param self AIBrain
    SetConstantEvaluate = function(self)
    end,

    ---@deprecated
    ---@param self AIBrain
    InitializeSkirmishSystems = function(self)
    end,

    ---@deprecated
    ---@param self AIBrain
    ForceManagerSort = function(self)
    end,

    ---@deprecated
    ---@param self AIBrain
    InitializePlatoonBuildManager = function(self)
    end,

    --#endregion
    -------------------------------------------------------------------------------
}
