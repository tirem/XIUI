--[[
* XIUI hotbar - Action Database
* Maps action names to spell/ability IDs for recast lookups
]]--

local M = {};

-- Lookup tables (built on first use)
M.spellNameToId = nil;
M.abilityNameToId = nil;

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

-- Clear caches (call on zone if needed)
function M.Clear()
    M.spellNameToId = nil;
    M.abilityNameToId = nil;
end

return M;
