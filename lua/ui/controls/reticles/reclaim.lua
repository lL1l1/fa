--******************************************************************************************************
--** Copyright (c) 2024  IL1I1
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
--******************************************************************************************************

local Bitmap   = import("/lua/maui/bitmap.lua").Bitmap

local UIUtil = import("/lua/ui/uiutil.lua")
local LayoutHelpers = import("/lua/maui/layouthelpers.lua")
local Reticle = import('/lua/ui/controls/reticle.lua').Reticle

-- Local upvalues for performance
local GetRolloverInfo = GetRolloverInfo

--- Reticle for teleport cost info
---@class UIReclaimReticle : UIReticle
---@field MassValueIcon Bitmap
---@field mText Text
ReclaimReticle = ClassUI(Reticle) {

    ---@param self UIReclaimReticle
    SetLayout = function(self)
        self.MassValueIcon = Bitmap(self)
        self.MassValueIcon:SetTexture(UIUtil.UIFile('/game/unit_view_icons/mass.dds'))
        LayoutHelpers.SetDimensions(self.MassValueIcon, 19, 19)

        self.mText = UIUtil.CreateText(self, "mValue", 16, UIUtil.bodyFont, true)
        LayoutHelpers.CenteredRightOf(self.MassValueIcon, self, 4)
        LayoutHelpers.RightOf(self.mText, self.MassValueIcon, 2)

         -- from economy_mini.lua, same color as the mass stored/storage text
        self.mText:SetColor('ffb7e75f')
    end,

    ---@param self UIReclaimReticle
    UpdateDisplay = function(self)
        local rolloverInfo = GetRolloverInfo()
        if rolloverInfo then
            if self:IsHidden() then
                self:SetHidden(false)
            end

            -- copy the wreck logic from Unit.lua
            local bp = __blueprints[rolloverInfo.blueprintId]
            local mass = bp.Economy.BuildCostMass

            local mass_tech_mult = 0.9
            local tech_category = bp.TechCategory

            -- We reduce the mass value based on tech category
            if tech_category == 'TECH1' then
                mass_tech_mult = 0.9
            elseif tech_category == 'TECH2' then
                mass_tech_mult = 0.8
            elseif tech_category == 'TECH3' then
                mass_tech_mult = 0.7
            elseif tech_category == 'EXPERIMENTAL' then
                mass_tech_mult = 0.6
            end
            
            mass = mass * mass_tech_mult * bp.Wreckage.MassMult

            self.mText:SetText(string.format('%d', mass))
        else
            if not self:IsHidden() then
                self:Hide()
            end
        end
    end,

}
