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

-- Full invalidation signature (job/level/equip/level sync) + periodic WS-count poll
local cacheFullSignature = nil;
local lastWsCountPollClock = 0;
local lastCachedWsAbilityCount = -1;
local WS_ABILITY_COUNT_POLL_INTERVAL = 0.75;
local lastEquipSignaturePollClock = 0;
local EQUIP_SIGNATURE_POLL_INTERVAL = 0.6;

local equipmentWs = require('modules.hotbar.equipment_ws');

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
-- Spell Sorting Helpers
-- ============================================

-- Base type rank (canonical display order when no job context)
local BASE_TYPE_RANK = {
    WhiteMagic=1, BlackMagic=2, BardSong=3, Ninjutsu=4,
    SummonerPact=5, BlueMagic=6, Geomancy=7, Trust=8,
};

-- Which type to surface first for each job
local JOB_PRIMARY_TYPE = {
    [3]  = 'WhiteMagic',    -- WHM
    [4]  = 'BlackMagic',    -- BLM
    [5]  = 'WhiteMagic',    -- RDM (has both; white magic is their healing focus)
    [7]  = 'WhiteMagic',    -- PLD
    [8]  = 'BlackMagic',    -- DRK
    [10] = 'BardSong',      -- BRD
    [13] = 'Ninjutsu',      -- NIN
    [15] = 'SummonerPact',  -- SMN
    [16] = 'BlueMagic',     -- BLU
    [20] = 'WhiteMagic',    -- SCH
    [21] = 'Geomancy',      -- GEO
};

--- Build a sort comparator for spells, context-aware by job.
--- Primary type for the given job sorts to the top.
--- Within SummonerPact, avatars come before spirits.
---@param mainJobId number
--- Spells sort by type group, then level, then name. Status is communicated by colour only.
---@return function
local function MakeSpellSortFn(mainJobId)
    local primaryType = JOB_PRIMARY_TYPE[mainJobId];
    return function(a, b)
        local ra = BASE_TYPE_RANK[a.type] or 9;
        local rb = BASE_TYPE_RANK[b.type] or 9;
        if primaryType then
            if a.type == primaryType then ra = 0; end
            if b.type == primaryType then rb = 0; end
        end
        if ra ~= rb then return ra < rb; end
        -- Within SummonerPact: avatars before spirits
        if a.type == 'SummonerPact' and b.type == 'SummonerPact' then
            local aIsSpirit = a.name:find(' Spirit') ~= nil;
            local bIsSpirit = b.name:find(' Spirit') ~= nil;
            if aIsSpirit ~= bIsSpirit then return not aIsSpirit; end
        end
        -- Sort by level then name; status is communicated by text colour alone
        if a.level ~= b.level then return a.level < b.level; end
        return a.name < b.name;
    end;
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
    local horizonSpells = require('modules.hotbar.database.horizonspells');

    -- Build a name→type lookup from the static DB
    local spellTypeByName = {};
    for _, s in pairs(horizonSpells) do
        if s.en and s.type then spellTypeByName[s.en] = s.type; end
    end

    local spells = {};
    local addedSpells = {};

    for spellId = 1, 1024 do
        if spellId >= 896 then break; end

        if player:HasSpell(spellId) then
            local spell = resMgr:GetSpellById(spellId);
            if spell and spell.Name and spell.Name[1] and spell.Name[1] ~= '' then
                local spellName = spell.Name[1];

                if not IsGarbageSpellName(spellName) then
                    local mainReqLevel = spell.LevelRequired[mainJobId + 1] or 0;
                    local subReqLevel = subJobId > 0 and (spell.LevelRequired[subJobId + 1] or 0) or 0;

                    local validMainReq = mainReqLevel > 0 and mainReqLevel < 255;
                    local validSubReq = subReqLevel > 0 and subReqLevel < 255;

                    local canCastMain = validMainReq and mainReqLevel <= mainJobLevel;
                    local canCastSub = validSubReq and subReqLevel <= subJobLevel;

                    if (canCastMain or canCastSub) and not addedSpells[spellId] then
                        local displayLevel = canCastMain and mainReqLevel or subReqLevel;
                        local source = canCastMain and 'main' or 'sub';

                        table.insert(spells, {
                            id = spellId,
                            name = spellName,
                            level = displayLevel,
                            source = source,
                            type = spellTypeByName[spellName] or 'Unknown',
                        });
                        addedSpells[spellId] = true;
                    end
                end
            end
        end
    end

    table.sort(spells, MakeSpellSortFn(mainJobId));

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
    -- DRG commands
    ['Steady Wing'] = true,
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
    local horizonAbilities = require('modules.hotbar.database.horizon_abilities');

    local abilities = {};
    local addedAbilities = {};

    for abilityId = 1, 1024 do
        if player:HasAbility(abilityId) then
            local ability = resMgr:GetAbilityById(abilityId);
            if ability and ability.Name and ability.Name[1] and ability.Name[1] ~= '' then
                local abilityType = ability.Type and bit.band(ability.Type, 7) or 0;

                local abilityName = ability.Name[1];
                if abilityType ~= ABILITY_TYPE_WEAPON_SKILL and not PET_COMMAND_NAMES[abilityName] then

                    if not addedAbilities[abilityId] then
                        local source = 'main';
                        local displayLevel = nil;

                        local dbEntry = horizonAbilities[abilityName];
                        if dbEntry and dbEntry.level then
                            displayLevel = dbEntry.level;
                        end

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
                            level = displayLevel,
                            source = source,
                        });
                        addedAbilities[abilityId] = true;
                    end
                end
            end
        end
    end

    table.sort(abilities, function(a, b)
        if a.level and b.level and a.level ~= b.level then return a.level < b.level; end
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
    local wsDb = require('modules.hotbar.database.ws_weapon_types');
    local weaponskills = {};
    local addedWeaponskills = {};

    for abilityId = 1, 1024 do
        if player:HasAbility(abilityId) then
            local ability = resMgr:GetAbilityById(abilityId);
            if ability and ability.Name and ability.Name[1] and ability.Name[1] ~= '' then
                local abilityType = ability.Type and bit.band(ability.Type, 7) or 0;
                if abilityType == ABILITY_TYPE_WEAPON_SKILL then
                    local wsName = ability.Name[1];
                    if not addedWeaponskills[wsName] then
                        local info = wsDb[wsName];
                        local reqStr = nil;
                        if info then
                            reqStr = info.relic and 'Relic Weapon' or ('Skill ' .. tostring(info.skill));
                        end
                        table.insert(weaponskills, {
                            id = abilityId,
                            name = wsName,
                            reqStr = reqStr,
                            skill = info and info.skill or 0,
                            relic = info and info.relic or false,
                        });
                        addedWeaponskills[wsName] = true;
                    end
                end
            end
        end
    end

    table.sort(weaponskills, function(a, b)
        if a.relic ~= b.relic then return not a.relic; end
        if a.skill ~= b.skill then return a.skill < b.skill; end
        return a.name < b.name;
    end);

    return weaponskills;
end

--- Count type-3 abilities the player has (cheap drift detector for new WS without job change).
local function countLearnedWeaponSkillAbilities(player)
    if not player then return 0; end
    local resMgr = AshitaCore:GetResourceManager();
    if not resMgr then return 0; end
    local c = 0;
    for abilityId = 1, 1024 do
        if player:HasAbility(abilityId) then
            local ability = resMgr:GetAbilityById(abilityId);
            if ability and ability.Type and bit.band(ability.Type, 7) == ABILITY_TYPE_WEAPON_SKILL then
                c = c + 1;
            end
        end
    end
    return c;
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

    local equipSig = equipmentWs.GetPlayerWeaponskillCacheSignature(player);
    local fullSig = equipSig .. '|' .. tostring(dataJobId) .. '|' .. tostring(dataSubjobId);

    local nowClock = os.clock();
    local pendingChange = cacheJobId ~= nil and (cacheJobId ~= dataJobId or cacheSubJobId ~= dataSubjobId);
    local needRefresh = (fullSig ~= cacheFullSignature)
        or pendingChange
        or (not cachedSpells);

    if (not needRefresh) and (nowClock - lastWsCountPollClock >= WS_ABILITY_COUNT_POLL_INTERVAL) then
        lastWsCountPollClock = nowClock;
        local wsCountNow = countLearnedWeaponSkillAbilities(player);
        if wsCountNow ~= lastCachedWsAbilityCount then
            needRefresh = true;
        end
    end

    -- Throttled equip/sync signature poll: catches rare drift if memory state updates without a frame-tied signature change
    if (not needRefresh) and cacheFullSignature and (nowClock - lastEquipSignaturePollClock >= EQUIP_SIGNATURE_POLL_INTERVAL) then
        lastEquipSignaturePollClock = nowClock;
        local equipSigPoll = equipmentWs.GetPlayerWeaponskillCacheSignature(player);
        local fullSigPoll = equipSigPoll .. '|' .. tostring(dataJobId) .. '|' .. tostring(dataSubjobId);
        if fullSigPoll ~= cacheFullSignature then
            needRefresh = true;
        end
    end

    if needRefresh then
        cachedSpells = M.GetPlayerSpells();
        cachedAbilities = M.GetPlayerAbilities();
        -- WS list: trust client HasAbility only; gear/job/sync in signature refreshes cache.
        cachedWeaponskills = M.GetPlayerWeaponskills();
        cachedItems = nil;  -- Clear items cache to refresh on next access
        cacheJobId = currentJobId;
        cacheSubJobId = currentSubJobId;
        cacheFullSignature = fullSig;
        lastCachedWsAbilityCount = countLearnedWeaponSkillAbilities(player);

        -- Clear expanded caches on job change so they rebuild with fresh data
        expandedSpellsCache = nil;
        expandedAbilitiesCache = nil;
        expandedWsCache = nil;

        -- Discover any newly learned WS and persist to charSettings
        if M.DiscoverNewWeaponskills() and SaveCharacterSettingsInternal then
            SaveCharacterSettingsInternal();
        end

        local okSr, slotrenderer = pcall(require, 'modules.hotbar.slotrenderer');
        if okSr and slotrenderer and slotrenderer.ClearAvailabilityCache then
            slotrenderer.ClearAvailabilityCache();
        end
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
    cacheFullSignature = nil;
    lastCachedWsAbilityCount = -1;
    expandedSpellsCache = nil;
    expandedAbilitiesCache = nil;
    expandedWsCache = nil;
    expandedAbilitiesFilterJobId = nil;
    expandedSpellsFilterType = nil;
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

--- Check if an ability name is in the cached abilities list
--- This ensures availability check uses same data as dropdown
---@param abilityName string The ability name to check
---@return boolean isAvailable True if ability is in cached list
function M.IsAbilityInCache(abilityName)
    -- No cache yet (or empty): do not assume the player has the ability — avoids wrong-job JAs looking usable
    if not cachedAbilities or #cachedAbilities == 0 then
        return false;
    end
    for _, ability in ipairs(cachedAbilities) do
        if ability.name == abilityName then
            return true;
        end
    end
    return false;
end

--- Check if a weaponskill name is in the cached weaponskills list
---@param wsName string The weaponskill name to check
---@return boolean isAvailable True if weaponskill is in cached list
function M.IsWeaponskillInCache(wsName)
    if not cachedWeaponskills or #cachedWeaponskills == 0 then
        return false;
    end
    for _, ws in ipairs(cachedWeaponskills) do
        if ws.name == wsName then
            return true;
        end
    end
    return false;
end

-- ============================================
-- Per-Character WS Knowledge Cache
-- ============================================

-- Known WS set: {['Savage Blade']=true, ...}. Populated externally from charSettings.
local knownWeaponskills = {};

--- Set the known WS table (call from XIUI.lua after loading charSettings)
function M.SetKnownWeaponskills(tbl)
    knownWeaponskills = tbl or {};
end

--- Get the known WS table reference
function M.GetKnownWeaponskills()
    return knownWeaponskills;
end

--- Scan player's current abilities for any new WS and add them to the known set.
--- Returns true if any new WS were discovered (caller should save charSettings).
function M.DiscoverNewWeaponskills()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then return false; end

    local resMgr = AshitaCore:GetResourceManager();
    local found = false;

    for abilityId = 1, 1024 do
        if player:HasAbility(abilityId) then
            local ability = resMgr:GetAbilityById(abilityId);
            if ability and ability.Name and ability.Name[1] and ability.Name[1] ~= '' then
                local abilityType = ability.Type and bit.band(ability.Type, 7) or 0;
                if abilityType == ABILITY_TYPE_WEAPON_SKILL then
                    local wsName = ability.Name[1];
                    if not knownWeaponskills[wsName] then
                        knownWeaponskills[wsName] = true;
                        found = true;
                    end
                end
            end
        end
    end

    return found;
end

-- ============================================
-- "Show All" Expanded List Builders
-- ============================================

local expandedSpellsCache = nil;
local expandedAbilitiesCache = nil;
local expandedWsCache = nil;
local expandedCacheJobId = nil;
local expandedCacheSubJobId = nil;
local expandedAbilitiesFilterJobId = nil;
local expandedSpellsFilterType = nil;

local STATUS_HAVE = 'have';
local STATUS_LEARNABLE = 'learnable';
local STATUS_UNAVAILABLE = 'unavailable';

local STATUS_SORT = { [STATUS_HAVE] = 1, [STATUS_LEARNABLE] = 2, [STATUS_UNAVAILABLE] = 3 };

--- Get expanded spell list from horizonspells DB with availability status.
--- When filterMagicType is 'All' or nil, only spells for the current main/sub job are shown.
--- When a specific type is given, ALL spells of that type are shown regardless of job.
--- Green = have, Yellow = learnable (right job/level but missing scroll), Red = unavailable.
---@param filterMagicType string|nil Magic type filter ('All', 'WhiteMagic', 'BlackMagic', etc.)
---@return table Array of {id, name, level, source, type, status, icon_id}
function M.GetAllSpellsForCurrentJob(filterMagicType)
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then return {}; end

    local mainJobId = player:GetMainJob();
    local mainJobLevel = player:GetMainJobLevel();
    local subJobId = player:GetSubJob();
    local subJobLevel = player:GetSubJobLevel();

    local effectiveType = (filterMagicType and filterMagicType ~= 'All') and filterMagicType or 'All';

    -- Self-invalidate when job changes
    if expandedCacheJobId ~= mainJobId or expandedCacheSubJobId ~= subJobId then
        expandedSpellsCache = nil;
        expandedAbilitiesCache = nil;
        expandedWsCache = nil;
        expandedCacheJobId = mainJobId;
        expandedCacheSubJobId = subJobId;
        expandedSpellsFilterType = nil;
    end
    if expandedSpellsFilterType ~= effectiveType then
        expandedSpellsCache = nil;
        expandedSpellsFilterType = effectiveType;
    end
    if expandedSpellsCache then return expandedSpellsCache; end

    local filterByType = (effectiveType ~= 'All');

    local horizonSpells = require('modules.hotbar.database.horizonspells');
    local omitList = require('modules.hotbar.database.horizon_spell_omissions');
    local omitSet = {};
    for _, name in ipairs(omitList) do omitSet[name] = true; end
    local spells = {};

    for _, spell in pairs(horizonSpells) do
        if spell.en and spell.en ~= '' and spell.id and not IsGarbageSpellName(spell.en) then
            if spell.id >= 896 then goto continue; end
            if omitSet[spell.en] then goto continue; end

            if filterByType and spell.type ~= effectiveType then goto continue; end

            local levels = spell.levels;
            if not levels then goto continue; end

            local mainReq = levels[mainJobId];
            local subReq = (subJobId and subJobId > 0) and levels[subJobId] or nil;
            local validMain = mainReq and mainReq > 0 and mainReq < 255;
            local validSub = subReq and subReq > 0 and subReq < 255;

            if not filterByType and not validMain and not validSub then goto continue; end

            local status;
            local displayLevel;
            local source;

            local hasSpell = player:HasSpell(spell.id);
            local canCastMain = validMain and mainReq <= mainJobLevel;
            local canCastSub = validSub and subReq <= subJobLevel;

            local reason = nil;
            if hasSpell and (canCastMain or canCastSub) then
                status = STATUS_HAVE;
                displayLevel = canCastMain and mainReq or subReq;
                source = canCastMain and 'main' or 'sub';
            elseif (validMain and mainReq <= mainJobLevel) or (validSub and subReq <= subJobLevel) then
                status = STATUS_LEARNABLE;
                displayLevel = canCastMain and mainReq or (validSub and subReq or mainReq);
                source = validMain and 'main' or 'sub';
                reason = 'Not yet learned (obtain the scroll)';
            else
                status = STATUS_UNAVAILABLE;
                local bestLevel = nil;
                for _, lv in pairs(levels) do
                    if lv and lv > 0 and lv < 255 then
                        if not bestLevel or lv < bestLevel then bestLevel = lv; end
                    end
                end
                displayLevel = (validMain and mainReq) or (validSub and subReq) or bestLevel or 99;
                source = validMain and 'main' or (validSub and 'sub' or 'other');
                if source == 'other' then
                    reason = 'Not available to your current job';
                else
                    reason = 'Level too low (requires Lv. ' .. tostring(displayLevel) .. ')';
                end
            end

            table.insert(spells, {
                id = spell.id,
                name = spell.en,
                level = displayLevel,
                source = source,
                type = spell.type or 'Unknown',
                status = status,
                reason = reason,
                icon_id = spell.icon_id,
            });
            ::continue::
        end
    end

    table.sort(spells, MakeSpellSortFn(mainJobId));

    expandedSpellsCache = spells;
    return spells;
end

--- Get expanded ability list with availability status.
--- Uses the static horizon_abilities database for reliable job-ability mapping,
--- cross-referenced with player:HasAbility() for ownership status.
---@param filterJobId number|nil Specific job ID to show abilities for. 0 or nil = main+sub (default).
---@return table Array of {id, name, level, source, status}
function M.GetAllAbilitiesForCurrentJob(filterJobId)
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then return {}; end

    local mainJobId = player:GetMainJob();
    local mainJobLevel = player:GetMainJobLevel();
    local subJobId = player:GetSubJob();
    local subJobLevel = player:GetSubJobLevel();
    local resMgr = AshitaCore:GetResourceManager();

    local effectiveFilter = (filterJobId and filterJobId > 0) and filterJobId or 0;

    if expandedCacheJobId ~= mainJobId or expandedCacheSubJobId ~= subJobId then
        expandedSpellsCache = nil;
        expandedAbilitiesCache = nil;
        expandedWsCache = nil;
        expandedCacheJobId = mainJobId;
        expandedCacheSubJobId = subJobId;
        expandedAbilitiesFilterJobId = nil;
    end
    if expandedAbilitiesFilterJobId ~= effectiveFilter then
        expandedAbilitiesCache = nil;
        expandedAbilitiesFilterJobId = effectiveFilter;
    end
    if expandedAbilitiesCache then return expandedAbilitiesCache; end

    local horizonAbilities = require('modules.hotbar.database.horizon_abilities');

    -- Build a name->abilityId lookup from the resource manager (for icon resolution)
    local nameToId = {};
    for abilityId = 1, 1024 do
        local ability = resMgr:GetAbilityById(abilityId);
        if ability and ability.Name and ability.Name[1] and ability.Name[1] ~= '' then
            if not nameToId[ability.Name[1]] then
                nameToId[ability.Name[1]] = abilityId;
            end
        end
    end

    -- Build a set of abilities the player currently has
    local playerHas = {};
    for abilityId = 1, 1024 do
        if player:HasAbility(abilityId) then
            local ability = resMgr:GetAbilityById(abilityId);
            if ability and ability.Name and ability.Name[1] and ability.Name[1] ~= '' then
                playerHas[ability.Name[1]] = true;
            end
        end
    end

    local abilities = {};

    for abilityName, info in pairs(horizonAbilities) do
        if info.pet then goto continue; end

        local matchesMain = info.job == mainJobId;
        local matchesSub = subJobId and subJobId > 0 and info.job == subJobId;

        if effectiveFilter > 0 then
            -- Specific job filter: only show abilities for that job
            if info.job ~= effectiveFilter then goto continue; end
        else
            -- Default: show main + sub job abilities
            if not matchesMain and not matchesSub then goto continue; end
        end

        local status;
        local source;
        local reason = nil;

        if playerHas[abilityName] then
            status = STATUS_HAVE;
            source = matchesMain and 'main' or (matchesSub and 'sub' or 'other');
        elseif matchesMain and mainJobLevel >= info.level then
            -- Right job and level met but HasAbility returned false (edge case)
            status = STATUS_LEARNABLE;
            source = 'main';
            reason = 'Should be available — try zoning or checking your abilities menu';
        elseif matchesSub and subJobLevel >= info.level then
            status = STATUS_LEARNABLE;
            source = 'sub';
            reason = 'Should be available — try zoning or checking your abilities menu';
        else
            status = STATUS_UNAVAILABLE;
            source = matchesMain and 'main' or (matchesSub and 'sub' or 'other');
            reason = 'Level too low (requires Lv. ' .. tostring(info.level) .. ')';
        end

        table.insert(abilities, {
            id = nameToId[abilityName] or 0,
            name = abilityName,
            level = info.level,
            source = source,
            status = status,
            reason = reason,
        });
        ::continue::
    end

    table.sort(abilities, function(a, b)
        local sa = STATUS_SORT[a.status] or 9;
        local sb = STATUS_SORT[b.status] or 9;
        if sa ~= sb then return sa < sb; end
        if a.level ~= b.level then return a.level < b.level; end
        return a.name < b.name;
    end);

    expandedAbilitiesCache = abilities;
    return abilities;
end

--- Get expanded weaponskill list from static WS lookup with known/unknown status.
---@param knownWsTable table|nil Per-character set of known WS names (defaults to internal set)
---@return table Array of {name, weapon, skill, relic, status}
function M.GetAllWeaponskillsExpanded(knownWsTable)
    if expandedWsCache then return expandedWsCache; end

    knownWsTable = knownWsTable or knownWeaponskills;
    local wsDb = require('modules.hotbar.database.ws_weapon_types');
    local weaponskills = {};

    for wsName, info in pairs(wsDb) do
        local status = knownWsTable[wsName] and STATUS_HAVE or STATUS_UNAVAILABLE;
        local reqStr;
        local reason = nil;
        if info.relic then
            reqStr = 'Relic Weapon';
            if status == STATUS_UNAVAILABLE then
                reason = 'Requires the relic weapon to be equipped';
            end
        else
            reqStr = 'Skill ' .. tostring(info.skill);
            if status == STATUS_UNAVAILABLE then
                reason = 'Not yet learned — use a ' .. info.weapon .. ' in battle (skill Lv. ' .. tostring(info.skill) .. ')';
            end
        end
        table.insert(weaponskills, {
            name = wsName,
            weapon = info.weapon,
            skill = info.skill,
            relic = info.relic or false,
            status = status,
            reqStr = reqStr,
            reason = reason,
        });
    end

    table.sort(weaponskills, function(a, b)
        local sa = STATUS_SORT[a.status] or 9;
        local sb = STATUS_SORT[b.status] or 9;
        if sa ~= sb then return sa < sb; end
        if a.weapon ~= b.weapon then return a.weapon < b.weapon; end
        -- Relic WS sort to bottom within their weapon group
        if a.relic ~= b.relic then return not a.relic; end
        if a.skill ~= b.skill then return a.skill < b.skill; end
        return a.name < b.name;
    end);

    expandedWsCache = weaponskills;
    return weaponskills;
end

--- Clear expanded list caches (call on job change, etc.)
function M.ClearExpandedCaches()
    expandedSpellsCache = nil;
    expandedAbilitiesCache = nil;
    expandedWsCache = nil;
    expandedCacheJobId = nil;
    expandedCacheSubJobId = nil;
    expandedAbilitiesFilterJobId = nil;
    expandedSpellsFilterType = nil;
end

-- Internal type names used in horizonspells.lua mapped to display labels
local MAGIC_TYPE_LABELS = {
    WhiteMagic    = 'White Magic',
    BlackMagic    = 'Black Magic',
    BardSong      = 'Songs',
    Ninjutsu      = 'Ninjutsu',
    SummonerPact  = 'Summoning',
    BlueMagic     = 'Blue Magic',
    Geomancy      = 'Geomancy',
    Trust         = 'Trust',
};

local MAGIC_TYPE_ORDER = {
    'WhiteMagic', 'BlackMagic', 'BardSong', 'Ninjutsu',
    'SummonerPact', 'BlueMagic', 'Geomancy', 'Trust',
};

-- Job ID -> which magic types that job can natively use (sorted alphabetically by label)
local JOB_MAGIC_TYPES = {
    [1]  = {},                                                       -- WAR
    [2]  = {},                                                       -- MNK
    [3]  = { 'WhiteMagic' },                                         -- WHM
    [4]  = { 'BlackMagic' },                                         -- BLM
    [5]  = { 'BlackMagic', 'WhiteMagic' },                           -- RDM
    [6]  = {},                                                       -- THF
    [7]  = { 'WhiteMagic' },                                         -- PLD
    [8]  = { 'BlackMagic' },                                         -- DRK
    [9]  = {},                                                       -- BST
    [10] = { 'BardSong', 'WhiteMagic' },                             -- BRD
    [11] = {},                                                       -- RNG
    [12] = {},                                                       -- SAM
    [13] = { 'Ninjutsu' },                                           -- NIN
    [14] = {},                                                       -- DRG
    [15] = { 'SummonerPact', 'WhiteMagic' },                         -- SMN
    [16] = { 'BlueMagic' },                                          -- BLU
    [17] = {},                                                       -- COR
    [18] = {},                                                       -- PUP
    [19] = {},                                                       -- DNC
    [20] = { 'BlackMagic', 'WhiteMagic' },                           -- SCH
    [21] = { 'Geomancy' },                                           -- GEO
    [22] = {},                                                       -- RUN
};

--- Get the ordered list of magic types for a given job (or current main+sub).
--- Returns entries like {key='WhiteMagic', label='White Magic'}.
---@param mainJobId number|nil Main job ID (uses current player if nil)
---@param subJobId number|nil Sub job ID (uses current player if nil)
---@return table Array of {key, label} sorted by MAGIC_TYPE_ORDER
function M.GetMagicTypesForJob(mainJobId, subJobId)
    if not mainJobId then
        local player = AshitaCore:GetMemoryManager():GetPlayer();
        if not player then return {}; end
        mainJobId = player:GetMainJob();
        subJobId = player:GetSubJob();
    end

    local seen = {};
    local mainTypes = JOB_MAGIC_TYPES[mainJobId] or {};
    local subTypes = (subJobId and subJobId > 0) and (JOB_MAGIC_TYPES[subJobId] or {}) or {};
    for _, t in ipairs(mainTypes) do seen[t] = true; end
    for _, t in ipairs(subTypes) do seen[t] = true; end

    local result = {};
    for _, key in ipairs(MAGIC_TYPE_ORDER) do
        if seen[key] then
            table.insert(result, { key = key, label = MAGIC_TYPE_LABELS[key] });
        end
    end
    return result;
end

--- Get display label for a magic type key.
---@param key string Internal type key (e.g. 'WhiteMagic')
---@return string Display label (e.g. 'White Magic')
function M.GetMagicTypeLabel(key)
    return MAGIC_TYPE_LABELS[key] or key;
end

--- Get all magic type options in canonical order.
---@return table Array of {key, label}
function M.GetAllMagicTypes()
    local result = {};
    for _, key in ipairs(MAGIC_TYPE_ORDER) do
        table.insert(result, { key = key, label = MAGIC_TYPE_LABELS[key] });
    end
    return result;
end

--- Get all unique weapon types from the WS lookup.
---@return table Array of weapon type strings, sorted alphabetically
function M.GetWeaponTypes()
    local wsDb = require('modules.hotbar.database.ws_weapon_types');
    local types = {};
    local seen = {};
    for _, info in pairs(wsDb) do
        if not seen[info.weapon] then
            seen[info.weapon] = true;
            table.insert(types, info.weapon);
        end
    end
    table.sort(types);
    return types;
end

--- Get BST pet commands from the static database with level-gated availability.
--- Uses horizon_abilities entries flagged with pet = true.
---@param playerLevel number The BST job level to check against
---@return table Array of {name, level, status}
function M.GetBstPetCommandsExpanded(playerLevel)
    local horizonAbilities = require('modules.hotbar.database.horizon_abilities');
    local commands = {};

    for cmdName, info in pairs(horizonAbilities) do
        if not info.pet then goto continue; end

        local status;
        if playerLevel >= info.level then
            status = STATUS_HAVE;
        else
            status = STATUS_UNAVAILABLE;
        end

        table.insert(commands, {
            name = cmdName,
            level = info.level,
            status = status,
        });
        ::continue::
    end

    table.sort(commands, function(a, b)
        if a.level ~= b.level then return a.level < b.level; end
        return a.name < b.name;
    end);

    return commands;
end

M.STATUS_HAVE = STATUS_HAVE;
M.STATUS_LEARNABLE = STATUS_LEARNABLE;
M.STATUS_UNAVAILABLE = STATUS_UNAVAILABLE;

-- Export helper for external use
M.IsGarbageSpellName = IsGarbageSpellName;
M.CONTAINERS = CONTAINERS;

return M;
