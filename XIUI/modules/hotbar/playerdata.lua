--[[
* XIUI Hotbar - Player Data Module
* Shared module for retrieving player spells, abilities, weaponskills, and items
* Used by both macropalette.lua and config/hotbar.lua
]]--

require('common');

local M = {};

-- ============================================
-- Cache State
-- ============================================

local cachedSpells = nil;
local cachedAbilities = nil;
local cachedWeaponskills = nil;
local cachedItems = nil;
local cacheJobId = nil;
local cacheSubJobId = nil;

-- ============================================
-- Container Definitions
-- ============================================

local CONTAINERS = {
    { id = 0, name = 'Inventory' },
    { id = 5, name = 'Satchel' },
    { id = 6, name = 'Sack' },
    { id = 7, name = 'Case' },
    { id = 1, name = 'Safe' },
    { id = 2, name = 'Storage' },
    { id = 4, name = 'Locker' },
    { id = 8, name = 'Wardrobe' },
    { id = 10, name = 'Wardrobe 2' },
    { id = 11, name = 'Wardrobe 3' },
    { id = 12, name = 'Wardrobe 4' },
    { id = 13, name = 'Wardrobe 5' },
    { id = 14, name = 'Wardrobe 6' },
    { id = 15, name = 'Wardrobe 7' },
    { id = 16, name = 'Wardrobe 8' },
};

-- ============================================
-- Helper Functions
-- ============================================

--- Check if a spell name looks like a garbage/test entry (e.g., AAEV, AAGK)
---@param name string The spell name to check
---@return boolean True if garbage, false if valid
local function IsGarbageSpellName(name)
    if not name or #name < 2 then return true; end
    -- Check if it's all uppercase letters with no spaces (garbage codes)
    if #name <= 5 and name:match('^[A-Z]+$') then
        return true;
    end
    return false;
end

-- ============================================
-- Player Data Retrieval Functions
-- ============================================

--- Get player's known spells for current job (excludes trusts and garbage entries)
--- Supports both main job and subjob spell access
---@return table Array of {id, name, level, source} where source is 'main' or 'sub'
function M.GetPlayerSpells()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then return {}; end

    local mainJobId = player:GetMainJob();
    local mainJobLevel = player:GetMainJobLevel();
    local subJobId = player:GetSubJob();
    local subJobLevel = player:GetSubJobLevel();
    local resMgr = AshitaCore:GetResourceManager();

    local spells = {};
    local addedSpells = {};  -- Track by spell ID to avoid duplicates

    for spellId = 1, 1024 do
        -- Skip trust spells (IDs 896+)
        if spellId >= 896 then
            break;
        end

        if player:HasSpell(spellId) then
            local spell = resMgr:GetSpellById(spellId);
            if spell and spell.Name and spell.Name[1] and spell.Name[1] ~= '' then
                local spellName = spell.Name[1];

                -- Skip garbage/test spell names
                if not IsGarbageSpellName(spellName) then
                    -- LevelRequired array uses jobId + 1 offset
                    -- WHM (jobId=3) -> LevelRequired[4], BLM (jobId=4) -> LevelRequired[5]
                    local mainReqLevel = spell.LevelRequired[mainJobId + 1] or 0;
                    local subReqLevel = subJobId > 0 and (spell.LevelRequired[subJobId + 1] or 0) or 0;

                    -- Filter invalid level values (0 = can't learn, 255 = can't learn)
                    local validMainReq = mainReqLevel > 0 and mainReqLevel < 255;
                    local validSubReq = subReqLevel > 0 and subReqLevel < 255;

                    -- Check if castable by main job
                    local canCastMain = validMainReq and mainReqLevel <= mainJobLevel;
                    -- Check if castable by sub job
                    local canCastSub = validSubReq and subReqLevel <= subJobLevel;

                    if (canCastMain or canCastSub) and not addedSpells[spellId] then
                        -- Use main job level if castable, otherwise sub job level
                        local displayLevel = canCastMain and mainReqLevel or subReqLevel;
                        local source = canCastMain and 'main' or 'sub';

                        table.insert(spells, {
                            id = spellId,
                            name = spellName,
                            level = displayLevel,
                            source = source,
                        });
                        addedSpells[spellId] = true;
                    end
                end
            end
        end
    end

    table.sort(spells, function(a, b)
        if a.level == b.level then
            return a.name < b.name;
        end
        return a.level < b.level;
    end);

    return spells;
end

-- Ability Type constants (from IAbility.Type & 7)
-- Type 3: Weapon Skill
local ABILITY_TYPE_WEAPON_SKILL = 3;

-- Pet commands to filter out from ability list (these belong in Pet Command section)
local PET_COMMAND_NAMES = {
    ['Assault'] = true,
    ['Retreat'] = true,
    ['Stay'] = true,
    ['Heel'] = true,
    ['Release'] = true,
    ['Leave'] = true,
    ['Fight'] = true,
    ['Sic'] = true,
    ['Ready'] = true,
    -- SMN commands
    ['Assault'] = true,
    ['Avatar\'s Favor'] = true,
    -- PUP commands
    ['Deploy'] = true,
    ['Retrieve'] = true,
    ['Activate'] = true,
    ['Deactivate'] = true,
};

--- Get player's available job abilities (includes both main job and subjob abilities)
--- Filters out weapon skills (Type 3) and pet commands
---@return table Array of {id, name, source} where source is 'main' or 'sub'
function M.GetPlayerAbilities()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then return {}; end

    local mainJobId = player:GetMainJob();
    local mainJobLevel = player:GetMainJobLevel();
    local subJobId = player:GetSubJob();
    local subJobLevel = player:GetSubJobLevel();
    local resMgr = AshitaCore:GetResourceManager();

    local abilities = {};
    local addedAbilities = {};  -- Track by ability ID to avoid duplicates

    -- Scan ability IDs 1-1024 (job abilities can be in higher ranges like 500+)
    for abilityId = 1, 1024 do
        if player:HasAbility(abilityId) then
            local ability = resMgr:GetAbilityById(abilityId);
            if ability and ability.Name and ability.Name[1] and ability.Name[1] ~= '' then
                local abilityType = ability.Type and bit.band(ability.Type, 7) or 0;

                -- Filter out weapon skills (Type 3) and pet commands (by name)
                local abilityName = ability.Name[1];
                if abilityType ~= ABILITY_TYPE_WEAPON_SKILL and not PET_COMMAND_NAMES[abilityName] then

                    if not addedAbilities[abilityId] then
                        local source = 'main';

                        if ability.Level then
                            local mainReqLevel = ability.Level[mainJobId + 1] or 0;
                            local subReqLevel = subJobId > 0 and (ability.Level[subJobId + 1] or 0) or 0;

                            local validMainReq = mainReqLevel > 0 and mainReqLevel < 255;
                            local validSubReq = subReqLevel > 0 and subReqLevel < 255;

                            local canUseMain = validMainReq and mainReqLevel <= mainJobLevel;
                            local canUseSub = validSubReq and subReqLevel <= subJobLevel;

                            if canUseSub and not canUseMain then
                                source = 'sub';
                            end
                        end

                        table.insert(abilities, {
                            id = abilityId,
                            name = abilityName,
                            source = source,
                        });
                        addedAbilities[abilityId] = true;
                    end
                end
            end
        end
    end

    table.sort(abilities, function(a, b)
        return a.name < b.name;
    end);

    return abilities;
end

--- Get player's available weaponskills
--- Uses HasAbility and filters by Type 3 (weapon skills)
---@return table Array of {id, name}
function M.GetPlayerWeaponskills()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then return {}; end

    local resMgr = AshitaCore:GetResourceManager();
    local weaponskills = {};
    local addedWeaponskills = {};  -- Track by name to avoid duplicates

    -- Scan HasAbility and filter by Type 3 (weapon skills)
    for abilityId = 1, 1024 do
        if player:HasAbility(abilityId) then
            local ability = resMgr:GetAbilityById(abilityId);
            if ability and ability.Name and ability.Name[1] and ability.Name[1] ~= '' then
                local abilityType = ability.Type and bit.band(ability.Type, 7) or 0;
                if abilityType == ABILITY_TYPE_WEAPON_SKILL then
                    local wsName = ability.Name[1];
                    if not addedWeaponskills[wsName] then
                        table.insert(weaponskills, {
                            id = abilityId,
                            name = wsName,
                        });
                        addedWeaponskills[wsName] = true;
                    end
                end
            end
        end
    end

    table.sort(weaponskills, function(a, b)
        return a.name < b.name;
    end);

    return weaponskills;
end

--- Get items from all player storage containers
---@return table Array of {id, name, container, count, slots, usable}
function M.GetPlayerItems()
    local memMgr = AshitaCore:GetMemoryManager();
    if not memMgr then return {}; end

    local inventory = memMgr:GetInventory();
    if not inventory then return {}; end

    local resMgr = AshitaCore:GetResourceManager();
    local items = {};
    local seenItems = {};  -- Track unique items by name to avoid duplicates

    for _, container in ipairs(CONTAINERS) do
        local maxSlots = inventory:GetContainerCountMax(container.id);
        if maxSlots and maxSlots > 0 then
            for slotIndex = 1, maxSlots do
                local item = inventory:GetContainerItem(container.id, slotIndex);
                if item and item.Id and item.Id > 0 and item.Id ~= 65535 then
                    local itemRes = resMgr:GetItemById(item.Id);
                    if itemRes and itemRes.Name and itemRes.Name[1] and itemRes.Name[1] ~= '' then
                        local itemName = itemRes.Name[1];
                        -- Only add if we haven't seen this item name yet
                        if not seenItems[itemName] then
                            seenItems[itemName] = true;
                            -- Check if item is usable (has activation time or recast delay)
                            local isUsable = false;
                            if itemRes.CastTime and itemRes.CastTime > 0 then
                                isUsable = true;
                            elseif itemRes.RecastDelay and itemRes.RecastDelay > 0 then
                                isUsable = true;
                            end
                            table.insert(items, {
                                id = item.Id,
                                name = itemName,
                                container = container.name,
                                count = item.Count or 1,
                                slots = itemRes.Slots or 0,  -- Equipment slot bitmask
                                usable = isUsable,
                            });
                        end
                    end
                end
            end
        end
    end

    table.sort(items, function(a, b)
        return a.name < b.name;
    end);

    return items;
end

-- ============================================
-- Cache Management
-- ============================================

--- Refresh cached lists if job changed or cache is empty
--- Call this before accessing cached data
---@param dataModule table|nil Optional data module for pending job change detection
function M.RefreshCachedLists(dataModule)
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then return; end

    local currentJobId = player:GetMainJob();
    local currentSubJobId = player:GetSubJob();

    -- Ignore invalid job IDs (can happen during menu transitions)
    -- This prevents the cache from being corrupted with job 0
    if not currentJobId or currentJobId == 0 then return; end

    -- Check if dataModule indicates a pending job change we haven't processed yet
    -- This catches cases where the packet handler updated data.jobId but player API was slower
    local dataJobId = dataModule and dataModule.jobId or currentJobId;
    local dataSubjobId = dataModule and dataModule.subjobId or currentSubJobId;

    -- Refresh if main job, sub job changed, or cache is empty
    -- Also refresh if data.jobId differs from cache (pending job change)
    local jobChanged = cacheJobId ~= currentJobId or cacheSubJobId ~= currentSubJobId;
    local pendingChange = cacheJobId ~= nil and (cacheJobId ~= dataJobId or cacheSubJobId ~= dataSubjobId);

    if jobChanged or pendingChange or not cachedSpells then
        cachedSpells = M.GetPlayerSpells();
        cachedAbilities = M.GetPlayerAbilities();
        cachedWeaponskills = M.GetPlayerWeaponskills();
        cachedItems = nil;  -- Clear items cache to refresh on next access
        cacheJobId = currentJobId;
        cacheSubJobId = currentSubJobId;
    end

    -- Only refresh items if cache is empty (expensive operation)
    if not cachedItems then
        cachedItems = M.GetPlayerItems();
    end
end

--- Get cached spells (call RefreshCachedLists first)
---@return table|nil Cached spells array
function M.GetCachedSpells()
    return cachedSpells;
end

--- Get cached abilities (call RefreshCachedLists first)
---@return table|nil Cached abilities array
function M.GetCachedAbilities()
    return cachedAbilities;
end

--- Get cached weaponskills (call RefreshCachedLists first)
---@return table|nil Cached weaponskills array
function M.GetCachedWeaponskills()
    return cachedWeaponskills;
end

--- Get cached items (call RefreshCachedLists first)
---@return table|nil Cached items array
function M.GetCachedItems()
    return cachedItems;
end

--- Force clear all caches (call on job change packet, etc.)
function M.ClearCache()
    cachedSpells = nil;
    cachedAbilities = nil;
    cachedWeaponskills = nil;
    cachedItems = nil;
    cacheJobId = nil;
    cacheSubJobId = nil;
end

--- Get current cache job ID
---@return number|nil Current cached job ID
function M.GetCacheJobId()
    return cacheJobId;
end

--- Get current cache subjob ID
---@return number|nil Current cached subjob ID
function M.GetCacheSubJobId()
    return cacheSubJobId;
end

-- Export helper for external use
M.IsGarbageSpellName = IsGarbageSpellName;
M.CONTAINERS = CONTAINERS;

return M;
