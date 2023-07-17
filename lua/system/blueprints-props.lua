---@param prop PropBlueprint
local function PostProcessProp(prop)

    prop.Categories = prop.Categories or {}

    prop.CategoriesHash = {}
    for k, category in prop.Categories do
        prop.CategoriesHash[category] = true
    end

    -- make invulnerable props actually invulnerable
    if prop.Categories then
        if table.find(prop.Categories, 'INVULNERABLE') then
            prop.ScriptClass = 'PropInvulnerable'
            prop.ScriptModule = '/lua/sim/prop.lua'
        end
    end

    -- check for props that should block pathing
    if not (prop.ScriptClass == "Tree" or prop.ScriptClass == "TreeGroup") and prop.CategoriesHash['RECLAIMABLE'] then
        if prop.Economy and prop.Economy.ReclaimMassMax and prop.Economy.ReclaimMassMax > 0 and not prop.CategoriesHash['OBSTRUCTSBUILDING'] then
            if not prop.CategoriesHash['OBSTRUCTSBUILDING'] then
                WARN("Prop is missing 'OBSTRUCTSBUILDING' category: " .. prop.BlueprintId)
            end
        end
    end
end

--- Post-processes all props
---@param props PropBlueprint[]
function PostProcessProps(props)
    for _, prop in props do
        PostProcessProp(prop)
    end
end
