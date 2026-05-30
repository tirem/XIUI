--[[
* XIUI hotbar - Action Database
* Maps action names to spell/ability IDs for recast lookups
]]--

local M = {};

-- Lookup tables (built on first use)
M.spellNameToId = nil;
M.abilityNameToId = nil;
M.itemNameToId = nil;
-- Lazy list of all ability IDs whose ability.Type == 3 (WeaponSkill). The resource manager's
-- ability list is static for the session, so this is built once on first call. Callers
-- iterating WS abilities should use this rather than scanning all 1024 ids per call.
M.weaponSkillAbilityIds = nil;

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

-- Build a list of all weapon-skill ability IDs (resource Type == 3). Static for the session.
-- Avoids the per-call O(1024) scans in playerdata's GetPlayerWeaponskills and
-- DiscoverNewWeaponskills, which previously iterated every ability id and only kept WS ones.
local function BuildWeaponSkillIdList()
    if M.weaponSkillAbilityIds then return; end
    M.weaponSkillAbilityIds = {};
    local resourceMgr = AshitaCore:GetResourceManager();
    if not resourceMgr then return; end
    for id = 0, 1024 do
        local ability = resourceMgr:GetAbilityById(id);
        if ability and ability.Type and ability.Type == 3 then
            M.weaponSkillAbilityIds[#M.weaponSkillAbilityIds + 1] = id;
        end
    end
end

-- Get the list of all weapon-skill ability IDs (caller still filters by player:HasAbility).
function M.GetWeaponSkillAbilityIds()
    BuildWeaponSkillIdList();
    return M.weaponSkillAbilityIds;
end

-- Clear caches (call on zone if needed)
function M.Clear()
    M.spellNameToId = nil;
    M.abilityNameToId = nil;
    M.itemNameToId = nil;
    M.weaponSkillAbilityIds = nil;
end

return M;
