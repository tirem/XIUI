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
local horizonRetailOnlyJa = require('modules.hotbar.database.horizon_retail_only_job_abilities');
local universalTwoHour = require('modules.hotbar.universal_two_hour');
-- Pre-existing name->id hashmap module (built lazily, session-cached). Replaces several
-- per-call O(1024) `for abilityId = 1, 1024 do ... resMgr:GetAbilityById(...)` scans for
-- name-based lookups. Audit pass: both 1.8.0 and Ferris kept this module but neither
-- propagated it into playerdata.lua's scans.
local actiondb = require('modules.hotbar.actiondb');

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

    -- Build id → horizonspells entry and name → type lookups in one pass.
    -- Using the horizonspells `levels` table for job/level data avoids the
    -- unreliable LevelRequired indexing in Ashita's resource manager (the
    -- offset between Ashita's C++ array and Lua indexing is inconsistent).
    -- This is the same data source used by GetAllSpellsForCurrentJob (Show All
    -- mode), which is known to work correctly.
    -- When the same spell name exists as both a castable spell and a SummonerPact
    -- blood pact, prefer the non-blood-pact type so spells like "Blizzard II"
    -- sort into the correct section rather than the Rage section.
    local horizonById = {};
    local spellTypeByName = {};
    for _, s in pairs(horizonSpells) do
        -- Exclude unlearnable entries (NPC/monster-only variants like Sleepga id=363).
        -- They share names with the learnable versions and would otherwise cause duplicates.
        if s.id and not s.unlearnable then horizonById[s.id] = s; end
        if s.en and s.type and not s.unlearnable then
            local existing = spellTypeByName[s.en];
            if not existing or (s.type ~= 'SummonerPact' and existing == 'SummonerPact') then
                spellTypeByName[s.en] = s.type;
            end
        end
    end

    local spells = {};
    local addedSpells = {};

    for spellId = 1, 895 do
        if player:HasSpell(spellId) then
            local spell = resMgr:GetSpellById(spellId);
            if spell and spell.Name and spell.Name[1] and spell.Name[1] ~= '' then
                local spellName = spell.Name[1];

                if not IsGarbageSpellName(spellName) and not addedSpells[spellName] then
                    -- Use horizonspells levels table for job filtering — same indexing
                    -- ([mainJobId] directly, e.g. [4]=BLM) as the working Show All path.
                    local hSpell = horizonById[spellId];
                    local hLevels = hSpell and hSpell.levels;
                    local mainReqLevel = (hLevels and hLevels[mainJobId]) or 0;
                    local subReqLevel = (subJobId > 0 and hLevels and hLevels[subJobId]) or 0;

                    local validMainReq = mainReqLevel > 0 and mainReqLevel < 255;
                    local validSubReq = subReqLevel > 0 and subReqLevel < 255;

                    -- Spell must belong to the player's current job or subjob.
                    -- We don't require canCast (level >= req) because HorizonXI may
                    -- grant spells at different thresholds than the static DB records;
                    -- HasSpell() already proves the player can cast it.
                    local isForCurrentJob = validMainReq or validSubReq;
                    if isForCurrentJob then
                        local displayLevel = validMainReq and mainReqLevel or subReqLevel;
                        local source = validMainReq and 'main' or 'sub';

                        table.insert(spells, {
                            id = spellId,
                            name = spellName,
                            level = displayLevel,
                            source = source,
                            type = (hSpell and hSpell.type) or spellTypeByName[spellName] or 'Unknown',
                        });
                        addedSpells[spellName] = true;
                    end
                end
            end
        end
    end

    table.sort(spells, MakeSpellSortFn(mainJobId));

    return spells;
end

-- Ability Type constants — IAbility.Type is a plain uint8 enum (NOT a bitfield).
-- Authoritative source: ai/references/Ashita-v4beta/plugins/sdk/ffxi/enums.h `AbilityType`.
local ABILITY_TYPE = {
    General           = 0,
    JobAbility        = 1,
    PetCommand        = 2,
    WeaponSkill       = 3,
    Trait             = 4,
    BloodPactRage     = 6,
    CorsairRoll       = 8,
    CorsairShot       = 9,
    BloodPactWard     = 10,
    DancerSamba       = 11,
    DancerWaltz       = 12,
    DancerStep        = 13,
    DancerFlourish1   = 14,
    ScholarStratagem  = 15,
    DancerJig         = 16,
    DancerFlourish2   = 17,
    BeastmasterSic    = 18,
    DancerFlourish3   = 19,
    MonsterSkill      = 20,
    RuneEnhancement   = 21,
    RuneWard          = 22,
    RuneEffusion      = 23,
};
-- Backward-compat alias for Ferris's existing code paths.
local ABILITY_TYPE_WEAPON_SKILL = ABILITY_TYPE.WeaponSkill;

-- Pet commands shown under Pet Command in the macro UI — excluded from the Job Ability dropdown only.
-- Players may still macro these as `/ja "Name"` in-game; IsAbilityInCache() accepts them when HasAbility is true.
-- Note: 'Assault' (BST pet) intentionally OMITTED — confusable with the Treasures of Aht Urhgan in-game system.
local PET_COMMAND_NAMES = {
    ['Retreat'] = true,
    ['Stay'] = true,
    ['Heel'] = true,
    ['Release'] = true,
    ['Leave'] = true,
    ['Fight'] = true,
    ['Sic'] = true,
    ['Ready'] = true,
    ['Avatar\'s Favor'] = true,
    ['Steady Wing'] = true,
    ['Deploy'] = true,
    ['Retrieve'] = true,
    ['Activate'] = true,
    ['Deactivate'] = true,
};

-- FFXI macro-maker subcategory headers ("Sambas", "Waltzes", etc.) are present as ability
-- entries in the resource manager and HasAbility() returns true for them, but they aren't
-- executable. Filter them out of the JA dropdown and IsAbilityInCache.
local CATEGORY_PLACEHOLDER_NAMES = {
    ['Sambas']         = true,
    ['Waltzes']        = true,
    ['Steps']          = true,
    ['Jigs']           = true,
    ['Flourishes I']   = true,
    ['Flourishes II']  = true,
    ['Flourishes III'] = true,
};

local function sortRankFamiliarFirst(name)
    return (name == 'Familiar') and 0 or 1;
end

local function horizonHasBstReadyPetCommand()
    local ha = require('modules.hotbar.database.horizon_abilities');
    local row = ha['Ready'];
    return row ~= nil and row.pet == true;
end

local function playerHasLearnedNonWsAbilityByName(abilityName)
    if horizonRetailOnlyJa[abilityName] then
        return false;
    end
    if not abilityName or abilityName == '' then
        return false;
    end
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then
        return false;
    end
    local resMgr = AshitaCore:GetResourceManager();
    if not resMgr then
        return false;
    end
    -- Audit win: O(1) name->id via actiondb (session-cached lazy hashmap) replaces the
    -- O(1024) scan that was here. Same semantics: confirm player has learned it AND it
    -- is not a weapon-skill type. Falls back to scan if actiondb returns nil (e.g. before
    -- the lookup table is populated for some edge resource-manager state).
    local id = actiondb.GetAbilityId(abilityName);
    if id and id > 0 and player:HasAbility(id) then
        local ability = resMgr:GetAbilityById(id);
        if ability and ability.Name and ability.Name[1] == abilityName then
            local abilityType = ability.Type or 0;
            return abilityType ~= ABILITY_TYPE_WEAPON_SKILL;
        end
    end
    return false;
end

--- Get player's available job abilities (includes both main job and subjob abilities)
--- Filters out weapon skills (Type 3) and PET_COMMAND_NAMES (those stay in the Pet Command picker).
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
                local abilityType = ability.Type or 0;

                local abilityName = ability.Name[1];
                -- Exclude: weapon skills (separate dropdown), passive traits (not macroable),
                -- pet commands (separate section), Horizon retail-only entries, and FFXI's
                -- subcategory header placeholders ("Sambas", "Waltzes", etc.).
                if not horizonRetailOnlyJa[abilityName]
                    and abilityType ~= ABILITY_TYPE.WeaponSkill
                    and abilityType ~= ABILITY_TYPE.Trait
                    and not PET_COMMAND_NAMES[abilityName]
                    and not CATEGORY_PLACEHOLDER_NAMES[abilityName] then

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

                        local hj = dbEntry and dbEntry.job;
                        table.insert(abilities, {
                            id = abilityId,
                            name = abilityName,
                            level = displayLevel,
                            source = source,
                            jobId = hj,
                            pinkStarTooltip = universalTwoHour.GetTwoHourPinkTooltipIfApplicable(hj, abilityName),
                        });
                        addedAbilities[abilityId] = true;
                    end
                end
            end
        end
    end

    table.sort(abilities, function(a, b)
        local ta = universalTwoHour.TwoHourSortRank(a.jobId, a.name);
        local tb = universalTwoHour.TwoHourSortRank(b.jobId, b.name);
        if ta ~= tb then return ta < tb; end
        local fa = sortRankFamiliarFirst(a.name);
        local fb = sortRankFamiliarFirst(b.name);
        if fa ~= fb then return fa < fb; end
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

    -- Audit win: iterate the static WS-ability-ID list from actiondb instead of scanning
    -- all 1024 ability slots. The Type==3 filter is moved into the one-time list build,
    -- so the per-call loop only has to check HasAbility + dedup.
    local wsIds = actiondb.GetWeaponSkillAbilityIds();
    for i = 1, #wsIds do
        local abilityId = wsIds[i];
        if player:HasAbility(abilityId) then
            local ability = resMgr:GetAbilityById(abilityId);
            if ability and ability.Name and ability.Name[1] and ability.Name[1] ~= '' then
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
    -- Audit win: same actiondb-driven optimization. The WS-id list already filters by Type == 3
    -- so the per-call body just needs HasAbility check + counter increment.
    local wsIds = actiondb.GetWeaponSkillAbilityIds();
    for i = 1, #wsIds do
        if player:HasAbility(wsIds[i]) then
            c = c + 1;
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
--- Used for `/ja` macro availability: matches the Job Ability dropdown when populated, plus PET_COMMAND_NAMES when learned.
---@param abilityName string The ability name to check
---@return boolean isAvailable True if ability is in cached list
function M.IsAbilityInCache(abilityName)
    if abilityName == universalTwoHour.ACTION_SENTINEL then
        abilityName = universalTwoHour.ResolveJaActionName(abilityName);
        if not abilityName then
            return false;
        end
    end
    if horizonRetailOnlyJa[abilityName] then
        return false;
    end
    -- Ready: honor horizon_abilities pet row (HorizonXI defines Ready for jug pets).
    if abilityName == 'Ready' and not horizonHasBstReadyPetCommand() then
        return false;
    end
    if cachedAbilities and #cachedAbilities > 0 then
        for _, ability in ipairs(cachedAbilities) do
            if ability.name == abilityName then
                return true;
            end
        end
    end
    -- Omitted from JA dropdown; `/ja` in macros still uses client HasAbility when the name is a known pet command.
    if PET_COMMAND_NAMES[abilityName] then
        return playerHasLearnedNonWsAbilityByName(abilityName);
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

    -- Audit win: same actiondb-driven optimization as GetPlayerWeaponskills.
    local wsIds = actiondb.GetWeaponSkillAbilityIds();
    for i = 1, #wsIds do
        local abilityId = wsIds[i];
        if player:HasAbility(abilityId) then
            local ability = resMgr:GetAbilityById(abilityId);
            if ability and ability.Name and ability.Name[1] and ability.Name[1] ~= '' then
                local wsName = ability.Name[1];
                if not knownWeaponskills[wsName] then
                    knownWeaponskills[wsName] = true;
                    found = true;
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
--- Green = have, Yellow = learnable (right job/level but spell not yet on character), Red = unavailable.
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
            if spell.unlearnable then goto continue; end
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
                reason = 'Not yet learned';
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

    -- Audit win: previously this function did TWO O(1024) resource-manager scans per
    -- cache miss (one to build name->id, one to populate playerHas). Both are now driven
    -- by `actiondb` (lazy session-cached name->id hashmap) + iterating the ~80-entry
    -- horizon_abilities table instead. Net: ~4096 resource calls collapses to ~160 on
    -- a cache miss (job change / profile load), with actiondb's one-time hashmap build
    -- amortized across all callers.
    local playerHas = {};
    for abilityName, _ in pairs(horizonAbilities) do
        local id = actiondb.GetAbilityId(abilityName);
        if id and id > 0 and player:HasAbility(id) then
            playerHas[abilityName] = true;
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

        local hj = info.job;
        table.insert(abilities, {
            id = actiondb.GetAbilityId(abilityName) or 0,
            name = abilityName,
            level = info.level,
            jobId = hj,
            source = source,
            status = status,
            reason = reason,
            pinkStarTooltip = universalTwoHour.GetTwoHourPinkTooltipIfApplicable(hj, abilityName),
        });
        ::continue::
    end

    table.sort(abilities, function(a, b)
        local ta = universalTwoHour.TwoHourSortRank(a.jobId, a.name);
        local tb = universalTwoHour.TwoHourSortRank(b.jobId, b.name);
        if ta ~= tb then return ta < tb; end
        local fa = sortRankFamiliarFirst(a.name);
        local fb = sortRankFamiliarFirst(b.name);
        if fa ~= fb then return fa < fb; end
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

    -- Show All: group by weapon type A→Z, then skill requirement low→high (relic last per type), then name.
    -- Availability color stays on rows; order does not shuffle unknown WS out of weapon clusters.
    table.sort(weaponskills, function(a, b)
        if a.weapon ~= b.weapon then return a.weapon < b.weapon; end
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
    local petregistry = require('modules.hotbar.petregistry');
    return petregistry.GetBstPetCommandsExpanded(playerLevel, nil);
end

M.STATUS_HAVE = STATUS_HAVE;
M.STATUS_LEARNABLE = STATUS_LEARNABLE;
M.STATUS_UNAVAILABLE = STATUS_UNAVAILABLE;

-- Export helper for external use
M.IsGarbageSpellName = IsGarbageSpellName;
M.CONTAINERS = CONTAINERS;

return M;
