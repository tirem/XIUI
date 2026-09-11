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
local cachedPetCommands = nil;
local cachedWeaponskills = nil;
local cachedItems = nil;
local cacheJobId = nil;
local cacheSubJobId = nil;

local JOB_CAP = 99;

-- ============================================
-- Spell / ability access rules (Ashita APIs)
-- ============================================

-- GetJobPointsSpent is missing on older Ashita builds; probe once rather than
-- paying for a pcall on every spell we evaluate.
local jobPointsApi = nil;

local function GetSpentJobPoints(player, jobId)
    if not player or not jobId or jobId <= 0 then return 0; end

    if jobPointsApi == nil then
        jobPointsApi = pcall(function()
            return player:GetJobPointsSpent(jobId);
        end);
    end
    if not jobPointsApi then return 0; end

    local spent = player:GetJobPointsSpent(jobId);
    return type(spent) == 'number' and spent or 0;
end

--- Whether the player can cast a spell on main or sub (HasSpell + level/JP gates)
---@param spell table Resource spell
---@param player table|nil Optional player; fetched if nil
---@return boolean ok
---@return string|nil source 'main'|'sub'
---@return number|nil requirement
function M.EvaluateSpellAccess(spell, player)
    if not spell or not spell.Index then
        return false, nil, nil;
    end

    player = player or AshitaCore:GetMemoryManager():GetPlayer();
    if not player then return false, nil, nil; end

    if not player:HasSpell(spell.Index) then
        return false, nil, nil;
    end

    local levels = spell.LevelRequired;
    if not levels then
        return true, 'main', 0;
    end

    local mainJob = player:GetMainJob() or 0;
    local mainLevel = player:GetMainJobLevel() or 0;
    local subJob = player:GetSubJob() or 0;
    local subLevel = player:GetSubJobLevel() or 0;
    local jpMask = spell.JobPointMask or 0;

    local mainReq = levels[mainJob + 1];
    if mainReq and mainReq ~= -1 then
        local jpGated = bit.band(bit.rshift(jpMask, mainJob), 1) == 1;
        if jpGated then
            if mainLevel >= JOB_CAP and GetSpentJobPoints(player, mainJob) >= mainReq then
                return true, 'main', mainReq;
            end
        elseif mainReq > 0 and mainReq < 255 and mainLevel >= mainReq then
            return true, 'main', mainReq;
        end
    end

    if subJob > 0 and bit.band(bit.rshift(jpMask, subJob), 1) == 0 then
        local subReq = levels[subJob + 1];
        if subReq and subReq ~= -1 and subReq > 0 and subReq < 255 and subLevel >= subReq then
            return true, 'sub', subReq;
        end
    end

    return false, nil, mainReq;
end

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

-- Containers reachable from the field without mog house / special access
local ACCESSIBLE_CONTAINERS = { 0, 8, 10, 11, 12, 13, 14, 15, 16 };

-- ISpell.Type for Trust magic; used to exclude trusts by type instead of an ID
-- range (real spells exist above the old cutoff, e.g. Death = 904).
local MAGIC_TYPE_TRUST = 8;

-- ============================================
-- Per-frame memoization
-- ============================================
-- Equipment/inventory scans used to build the availability cache key can't change
-- mid-frame, so memoize them per ImGui frame count (recomputes on the next frame).
local frameMemo = {
    frame = nil,
    equipSig = nil,
    owned = {},            -- itemKey -> boolean
    accessibleCount = {},  -- itemKey -> number
};

local function CurrentFrame()
    local gui = AshitaCore:GetGuiManager();
    return gui and gui:GetFrameCount() or 0;
end

-- Reset the per-frame memo if we've advanced to a new frame.
local function EnsureFrameMemo()
    local f = CurrentFrame();
    if f ~= frameMemo.frame then
        frameMemo.frame = f;
        frameMemo.equipSig = nil;
        frameMemo.owned = {};
        frameMemo.accessibleCount = {};
    end
end

local function ItemMemoKey(itemId, itemName)
    return tostring(itemId or '') .. '|' .. (itemName or '');
end

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

---@param item table
---@param itemId number|nil
---@param itemName string|nil
---@param resMgr table|nil
---@return boolean
local function ItemSlotMatches(item, itemId, itemName, resMgr)
    if not item or not item.Id or item.Id <= 0 or item.Id == 65535 then
        return false;
    end
    if itemId and item.Id == itemId then
        return true;
    end
    if itemName and resMgr then
        local itemRes = resMgr:GetItemById(item.Id);
        if itemRes and itemRes.Name and itemRes.Name[1] == itemName then
            return true;
        end
    end
    return false;
end

--- Scan container IDs for a matching item; optionally sum stack counts
---@param containerIds number[]
---@param itemId number|nil
---@param itemName string|nil
---@param sumCounts boolean When true, return total count; when false, return 1 if found else 0
---@return number
local function ScanContainersForItem(containerIds, itemId, itemName, sumCounts)
    if not itemId and (not itemName or itemName == '') then
        return 0;
    end

    local memMgr = AshitaCore:GetMemoryManager();
    if not memMgr then return 0; end

    local inventory = memMgr:GetInventory();
    if not inventory then return 0; end

    local resMgr = AshitaCore:GetResourceManager();
    local total = 0;

    for _, containerId in ipairs(containerIds) do
        local maxSlots = inventory:GetContainerCountMax(containerId);
        if maxSlots and maxSlots > 0 then
            for slotIndex = 1, maxSlots do
                local item = inventory:GetContainerItem(containerId, slotIndex);
                if ItemSlotMatches(item, itemId, itemName, resMgr) then
                    if sumCounts then
                        total = total + (item.Count or 1);
                    else
                        return 1;
                    end
                end
            end
        end
    end

    return total;
end

local ALL_CONTAINER_IDS = {};
for _, container in ipairs(CONTAINERS) do
    ALL_CONTAINER_IDS[#ALL_CONTAINER_IDS + 1] = container.id;
end

-- ============================================
-- Player Data Retrieval Functions
-- ============================================

--- Get player's known spells for current job (excludes trusts and garbage entries)
--- Supports both main job and subjob spell access, including JP-gated spells.
---@return table Array of {id, name, level, source} where source is 'main' or 'sub'
function M.GetPlayerSpells()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then return {}; end

    local resMgr = AshitaCore:GetResourceManager();
    if not resMgr then return {}; end

    local spells = {};
    local addedSpells = {};

    for spellId = 1, 0x400 do
        if player:HasSpell(spellId) then
            local spell = resMgr:GetSpellById(spellId);
            if spell and spell.Name and spell.Name[1] and spell.Name[1] ~= ''
                and (spell.Type or 0) ~= MAGIC_TYPE_TRUST then
                local spellName = spell.Name[1];
                if not IsGarbageSpellName(spellName) then
                    local canCast, source, reqLevel = M.EvaluateSpellAccess(spell, player);
                    if canCast and not addedSpells[spellId] then
                        table.insert(spells, {
                            id = spellId,
                            name = spellName,
                            level = reqLevel or 0,
                            source = source or 'main',
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

-- Types that belong in the Pet Command editor list (/pet actions).
local PET_MENU_TYPES = {
    [ABILITY_TYPE.PetCommand] = true,
    [ABILITY_TYPE.BloodPactRage] = true,
    [ABILITY_TYPE.BloodPactWard] = true,
    [ABILITY_TYPE.BeastmasterSic] = true,
};

-- Menu subcategory headers (not executable actions).
local CATEGORY_STUB_IDS = {
    [567] = true, -- Pet Commands
    [603] = true, -- Blood Pact: Rage
    [609] = true, -- Phantom Roll
    [636] = true, -- Quick Draw
    [684] = true, -- Blood Pact: Ward
    [694] = true, -- Sambas
    [695] = true, -- Waltzes
    [710] = true, -- Jigs
    [711] = true, -- Steps
    [712] = true, -- Flourishes I
    [725] = true, -- Flourishes II
    [735] = true, -- Stratagems
    [763] = true, -- Ready
    [775] = true, -- Flourishes III
    [869] = true, -- Rune Enchantment
    [891] = true, -- Ward
    [892] = true, -- Effusion
};

-- Job ability / pet command resource id range used by HasAbility scans.
local ABILITY_SCAN_MIN = 0x200;
local ABILITY_SCAN_MAX = 0x600;

--- Live pet check (jug / charm / avatar / automaton / wyvern).
---@return boolean
local function PlayerHasActivePet()
    local memMgr = AshitaCore:GetMemoryManager();
    if not memMgr then return false; end

    local party = memMgr:GetParty();
    local playerIndex = party and party:GetMemberTargetIndex(0);
    if not playerIndex or playerIndex == 0 then
        return false;
    end

    local playerEntity = GetEntity(playerIndex);
    if not playerEntity or not playerEntity.PetTargetIndex or playerEntity.PetTargetIndex == 0 then
        return false;
    end

    local petEntity = GetEntity(playerEntity.PetTargetIndex);
    return petEntity ~= nil and petEntity.Name ~= nil and petEntity.Name ~= '';
end

--- Whether the player currently knows an ability resource (HasAbility / HasPetCommand).
local function PlayerKnowsAbility(player, ability)
    if not player or not ability or not ability.Id then
        return false;
    end
    if player:HasAbility(ability.Id) then
        return true;
    end
    if player.HasPetCommand and player:HasPetCommand(ability.Id) then
        return true;
    end
    return false;
end

--- Scan known abilities: resource ids 0x200..0x600 + HasAbility.
---@param includePetTypes boolean If true, only pet /pet types; if false, exclude them
---@return table Array of {id, name, type, source}
local function ScanKnownAbilities(includePetTypes)
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then return {}; end

    local resMgr = AshitaCore:GetResourceManager();
    if not resMgr then return {}; end

    local mainJobId = player:GetMainJob() or 0;
    local mainJobLevel = player:GetMainJobLevel() or 0;
    local subJobId = player:GetSubJob() or 0;
    local subJobLevel = player:GetSubJobLevel() or 0;

    local results = {};
    local added = {};

    for index = ABILITY_SCAN_MIN, ABILITY_SCAN_MAX do
        if not CATEGORY_STUB_IDS[index] then
            local ability = resMgr:GetAbilityById(index);
            if ability and ability.Name and ability.Name[1] and ability.Name[1] ~= ''
                and PlayerKnowsAbility(player, ability)
                and not added[ability.Id]
            then
                local abilityType = ability.Type or 0;
                local isPetType = PET_MENU_TYPES[abilityType] == true;
                local isWeaponSkill = abilityType == ABILITY_TYPE.WeaponSkill;
                local isTrait = abilityType == ABILITY_TYPE.Trait;
                local isMonsterSkill = abilityType == ABILITY_TYPE.MonsterSkill;

                local include = false;
                if includePetTypes then
                    include = isPetType;
                else
                    include = not isPetType and not isWeaponSkill and not isTrait and not isMonsterSkill;
                end

                if include then
                    local source = 'main';
                    if ability.Level then
                        local mainReqLevel = ability.Level[mainJobId + 1] or 0;
                        local subReqLevel = subJobId > 0 and (ability.Level[subJobId + 1] or 0) or 0;
                        local canUseMain = mainReqLevel > 0 and mainReqLevel < 255 and mainReqLevel <= mainJobLevel;
                        local canUseSub = subReqLevel > 0 and subReqLevel < 255 and subReqLevel <= subJobLevel;
                        if canUseSub and not canUseMain then
                            source = 'sub';
                        end
                    end

                    table.insert(results, {
                        id = ability.Id,
                        name = ability.Name[1],
                        type = abilityType,
                        source = source,
                    });
                    added[ability.Id] = true;
                end
            end
        end
    end

    table.sort(results, function(a, b)
        return a.name < b.name;
    end);

    return results;
end

--- Get player's available job abilities (main + sub).
--- HasAbility on 0x200..0x600, excluding pet-typed resources.
---@return table Array of {id, name, source}
function M.GetPlayerAbilities()
    return ScanKnownAbilities(false);
end

--- Get player's available pet commands (/pet), blood pacts, and Ready moves.
--- HasAbility scan filtered to pet types. Also requires an active pet:
--- some BST abilities (Spur, Run Wild) stay known in the bitfield with no pet.
---@return table Array of {id, name, type, source}
function M.GetPlayerPetCommands()
    if not PlayerHasActivePet() then
        return {};
    end
    return ScanKnownAbilities(true);
end

--- Get player's available weaponskills
---@return table Array of {id, name}
function M.GetPlayerWeaponskills()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then return {}; end

    local resMgr = AshitaCore:GetResourceManager();
    if not resMgr then return {}; end

    local weaponskills = {};
    local addedWeaponskills = {};

    for abilityId = 1, 0x200 do
        if player:HasAbility(abilityId) then
            local ability = resMgr:GetAbilityById(abilityId);
            if ability and ability.Name and ability.Name[1] and ability.Name[1] ~= '' then
                local abilityType = ability.Type or 0;
                if abilityType == ABILITY_TYPE.WeaponSkill then
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
        cachedPetCommands = M.GetPlayerPetCommands();
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
    cachedPetCommands = nil;
    cachedWeaponskills = nil;
    cachedItems = nil;
    cacheJobId = nil;
    cacheSubJobId = nil;
end

--- Force rebuild spell cache (call when macro editor dropdown opens)
function M.ForceRefreshSpells()
    cachedSpells = M.GetPlayerSpells();
end

--- Force rebuild ability cache (call when macro editor dropdown opens)
function M.ForceRefreshAbilities()
    cachedAbilities = M.GetPlayerAbilities();
end

--- Force rebuild pet-command cache (HasAbility bits change on summon/release)
function M.ForceRefreshPetCommands()
    cachedPetCommands = M.GetPlayerPetCommands();
    return cachedPetCommands;
end

--- Force rebuild weaponskill cache (call when macro editor dropdown opens)
function M.ForceRefreshWeaponskills()
    cachedWeaponskills = M.GetPlayerWeaponskills();
end

--- Force rebuild item cache (call when macro editor dropdown opens)
function M.ForceRefreshItems()
    cachedItems = M.GetPlayerItems();
end

--- Get cached pet commands (call RefreshCachedLists / ForceRefreshPetCommands first)
---@return table|nil
function M.GetCachedPetCommands()
    return cachedPetCommands;
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
    if not cachedAbilities then return true; end  -- No cache = assume available
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
    if not cachedWeaponskills then return true; end
    for _, ws in ipairs(cachedWeaponskills) do
        if ws.name == wsName then
            return true;
        end
    end
    return false;
end

-- Equipment slot bitmasks for equip availability checks
local EQUIP_SLOT_MASKS = {
    main = 0x0001,
    sub = 0x0002,
    range = 0x0004,
    ammo = 0x0008,
    head = 0x0010,
    body = 0x0020,
    hands = 0x0040,
    legs = 0x0080,
    feet = 0x0100,
    neck = 0x0200,
    waist = 0x0400,
    ear1 = 0x0800,
    ear2 = 0x1000,
    ring1 = 0x2000,
    ring2 = 0x4000,
    back = 0x8000,
};

--- Build a signature of currently equipped combat slots (main/sub/range/ammo)
--- Used to invalidate availability cache when weapons change
---@return string
function M.GetEquipmentSignature()
    EnsureFrameMemo();
    if frameMemo.equipSig ~= nil then
        return frameMemo.equipSig;
    end

    local inventory = AshitaCore:GetMemoryManager():GetInventory();
    if not inventory then
        frameMemo.equipSig = '0:0:0:0';
        return frameMemo.equipSig;
    end

    local parts = {};
    for slot = 0, 3 do
        local itemId = 0;
        local equipped = inventory:GetEquippedItem(slot);
        if equipped and equipped.Index then
            local index = bit.band(equipped.Index, 0x00FF);
            if index > 0 then
                local container = bit.rshift(bit.band(equipped.Index, 0xFF00), 8);
                local item = inventory:GetContainerItem(container, index);
                if item and item.Id and item.Id > 0 and item.Id ~= 65535 then
                    itemId = item.Id;
                end
            end
        end
        parts[#parts + 1] = tostring(itemId);
    end

    frameMemo.equipSig = table.concat(parts, ':');
    return frameMemo.equipSig;
end

--- Check if the player owns an item anywhere in tracked storage containers
---@param itemId number|nil
---@param itemName string|nil
---@return boolean
function M.IsItemOwned(itemId, itemName)
    EnsureFrameMemo();
    local key = ItemMemoKey(itemId, itemName);
    local cached = frameMemo.owned[key];
    if cached ~= nil then
        return cached;
    end
    local owned = ScanContainersForItem(ALL_CONTAINER_IDS, itemId, itemName, false) > 0;
    frameMemo.owned[key] = owned;
    return owned;
end

--- Count an item in accessible inventory (inventory + wardrobes)
---@param itemId number|nil
---@param itemName string|nil
---@return number
function M.CountAccessibleItem(itemId, itemName)
    EnsureFrameMemo();
    local key = ItemMemoKey(itemId, itemName);
    local cached = frameMemo.accessibleCount[key];
    if cached ~= nil then
        return cached;
    end
    local count = ScanContainersForItem(ACCESSIBLE_CONTAINERS, itemId, itemName, true);
    frameMemo.accessibleCount[key] = count;
    return count;
end

--- Check if an item is in accessible inventory (inventory + wardrobes, not mog safe/storage/satchel)
---@param itemId number|nil
---@param itemName string|nil
---@return boolean
function M.IsItemInAccessibleInventory(itemId, itemName)
    return M.CountAccessibleItem(itemId, itemName) > 0;
end

--- Check if an equip macro/action can currently be used
---@param equipSlot string|nil
---@param itemName string|nil
---@param itemId number|nil
---@return boolean
function M.IsEquipActionAvailable(equipSlot, itemName, itemId)
    if not itemName or itemName == '' then
        return false;
    end

    if not itemId then
        local actiondb = require('modules.hotbar.actiondb');
        itemId = actiondb.GetItemId(itemName);
    end

    if not M.IsItemOwned(itemId, itemName) then
        return false;
    end

    if equipSlot and itemId then
        local resMgr = AshitaCore:GetResourceManager();
        local item = resMgr and resMgr:GetItemById(itemId);
        local slotMask = EQUIP_SLOT_MASKS[equipSlot];
        if item and slotMask and item.Slots and bit.band(item.Slots, slotMask) == 0 then
            return false;
        end
    end

    return true;
end

--- Check if a pet command is currently known (HasAbility on the pet resource Id).
--- Requires an active pet — Spur/Run Wild bits can stay set with no pet out.
---@param commandName string
---@return boolean
function M.IsPetCommandAvailable(commandName)
    if not commandName or commandName == '' then
        return false;
    end

    if not PlayerHasActivePet() then
        return false;
    end

    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then return true; end

    local actiondb = require('modules.hotbar.actiondb');
    local abilityId = actiondb.GetPetAbilityId(commandName);
    if not abilityId then
        return false;
    end

    if player:HasAbility(abilityId) then
        return true;
    end
    if player.HasPetCommand and player:HasPetCommand(abilityId) then
        return true;
    end
    return false;
end

-- Export helper for external use
M.IsGarbageSpellName = IsGarbageSpellName;
M.CONTAINERS = CONTAINERS;
M.ACCESSIBLE_CONTAINERS = ACCESSIBLE_CONTAINERS;

return M;
