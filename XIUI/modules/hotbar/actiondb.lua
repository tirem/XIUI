--[[
* XIUI hotbar - Action Database
* Maps action names to spell/ability IDs for recast lookups
]]--

local M = {};

-- Lookup tables (built on first use)
M.spellNameToId = nil;
M.abilityNameToId = nil;
M.itemNameToId = nil;

-- Build spell name lookup table
local function BuildSpellLookup()
    if M.spellNameToId then return; end

    M.spellNameToId = {};
    local resourceMgr = AshitaCore:GetResourceManager();
    if not resourceMgr then return; end

    for id = 0, 1024 do
        local spell = resourceMgr:GetSpellById(id);
        if spell and spell.Name and spell.Name[1] then
            local name = spell.Name[1]:lower();
            M.spellNameToId[name] = id;
        end
    end
end

-- Build ability name lookup table
local function BuildAbilityLookup()
    if M.abilityNameToId then return; end

    M.abilityNameToId = {};
    local resourceMgr = AshitaCore:GetResourceManager();
    if not resourceMgr then return; end

    for id = 0, 1024 do
        local ability = resourceMgr:GetAbilityById(id);
        if ability and ability.Name and ability.Name[1] then
            local name = ability.Name[1]:lower();
            M.abilityNameToId[name] = id;
        end
    end
end

-- Get spell ID by name
function M.GetSpellId(spellName)
    if not spellName then return nil; end
    BuildSpellLookup();
    return M.spellNameToId[spellName:lower()];
end

-- Get ability ID by name
function M.GetAbilityId(abilityName)
    if not abilityName then return nil; end
    BuildAbilityLookup();
    return M.abilityNameToId[abilityName:lower()];
end

-- Build item name lookup table
local function BuildItemLookup()
    if M.itemNameToId then return; end

    M.itemNameToId = {};
    local resourceMgr = AshitaCore:GetResourceManager();
    if not resourceMgr then return; end

    for id = 1, 65535 do
        local item = resourceMgr:GetItemById(id);
        if item and item.Name and item.Name[1] then
            local name = item.Name[1]:lower();
            M.itemNameToId[name] = id;
        end
    end
end

-- Get item ID by name
function M.GetItemId(itemName)
    if not itemName then return nil; end
    BuildItemLookup();
    return M.itemNameToId[itemName:lower()];
end

-- Clear caches (call on zone if needed)
function M.Clear()
    M.spellNameToId = nil;
    M.abilityNameToId = nil;
    M.itemNameToId = nil;
end

return M;
