--[[
* XIUI hotbar - Action Database
* Maps action names to spell/ability IDs for recast lookups
*
* Bind against the IAbility.Id that HasAbility / RecastTimerId actually use.
* Pet commands (Heel/Stay/Leave, blood pacts, Ready moves) often share a
* display name with a lower stub id, so pet lookups prefer Type PetCommand /
* Blood Pact / Sic.
]]--

local M = {};

-- Lookup tables (built on first use)
M.spellNameToId = nil;
M.abilityNameToId = nil;
M.abilityNameToPetId = nil;
M.itemNameToId = nil;

-- IAbility.Type values used by pet /pet actions (Ashita AbilityType enum).
local PET_ABILITY_TYPES = {
    [2] = true,  -- PetCommand
    [6] = true,  -- BloodPactRage
    [10] = true, -- BloodPactWard
    [18] = true, -- BeastmasterSic / Ready family
};

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
            -- Keep the lowest id for duplicate names: some spells (e.g. Sleepga)
            -- have an unlearnable higher-id variant that HasSpell never matches.
            if not M.spellNameToId[name] then
                M.spellNameToId[name] = id;
            end
        end
    end
end

-- Score a candidate ability id for pet-command lookups.
-- Higher score = better match for HasAbility + shared RecastTimerId.
local function ScorePetAbility(ability, id)
    if not ability then return -1; end
    local score = 0;
    local abilityType = ability.Type or 0;
    if PET_ABILITY_TYPES[abilityType] then
        score = score + 100;
    end
    local timerId = ability.RecastTimerId or ability.TimerId or 0;
    if timerId and timerId > 0 then
        score = score + 20;
    end
    -- Job-ability / pet resource ids live in 0x200..0x600 in Ashita.
    if id >= 0x200 and id <= 0x600 then
        score = score + 10;
    end
    -- Prefer higher id when scores tie (avoids low stub rows).
    score = score + (id / 10000);
    return score;
end

-- Build ability name lookup tables
local function BuildAbilityLookup()
    if M.abilityNameToId then return; end

    M.abilityNameToId = {};
    M.abilityNameToPetId = {};
    local resourceMgr = AshitaCore:GetResourceManager();
    if not resourceMgr then return; end

    local petBestScore = {};

    -- Up to 2048: Blood Pacts live at 1024+ (e.g. Healing Ruby II, Whispering Wind).
    for id = 0, 2048 do
        local ability = resourceMgr:GetAbilityById(id);
        if ability and ability.Name and ability.Name[1] then
            local name = ability.Name[1]:lower();
            -- JA/WS path: keep the lowest id (same rationale as spells).
            if not M.abilityNameToId[name] then
                M.abilityNameToId[name] = id;
            end

            local score = ScorePetAbility(ability, id);
            if score > (petBestScore[name] or -1) then
                petBestScore[name] = score;
                M.abilityNameToPetId[name] = id;
            end
        end
    end
end

-- Get spell ID by name
function M.GetSpellId(spellName)
    if not spellName then return nil; end
    BuildSpellLookup();
    return M.spellNameToId[spellName:lower()];
end

-- Get ability ID by name (job abilities / weaponskills)
function M.GetAbilityId(abilityName)
    if not abilityName then return nil; end
    BuildAbilityLookup();
    return M.abilityNameToId[abilityName:lower()];
end

-- Get ability ID for a /pet action (commands, blood pacts, Ready moves).
-- Prefers PetCommand/BP typed resources so Heel/Stay/Leave share RecastTimerId
-- and HasAbility matches the executable pet resource Id.
function M.GetPetAbilityId(abilityName)
    if not abilityName then return nil; end
    BuildAbilityLookup();
    local key = abilityName:lower();
    return M.abilityNameToPetId[key] or M.abilityNameToId[key];
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
    M.abilityNameToPetId = nil;
    M.itemNameToId = nil;
end

return M;
