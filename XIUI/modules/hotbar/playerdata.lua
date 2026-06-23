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

-- Actual level cap; Job Points unlock spells above this without raising job level
local MAX_JOB_LEVEL = 99;

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
        if player:HasSpell(spellId) then
            local spell = resMgr:GetSpellById(spellId);
            -- Skip trusts by magic type, not ID range (the old ID-896 cutoff also
            -- hid real spells above it, e.g. Death = 904).
            if spell and spell.Name and spell.Name[1] and spell.Name[1] ~= ''
                and (spell.Type or 0) ~= MAGIC_TYPE_TRUST then
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

                    -- Check if castable by main job (Job Point spells report level > 99)
                    local canCastMain = validMainReq and (mainReqLevel <= mainJobLevel or mainReqLevel > MAX_JOB_LEVEL);
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
    ['Avatar\'s Favor'] = true,
    -- DRG commands
    ['Steady Wing'] = true,
    -- PUP commands
    ['Deploy'] = true,
    ['Retrieve'] = true,
    ['Activate'] = true,
    ['Deactivate'] = true,
};

-- FFXI macro-maker subcategory headers ("Sambas", "Waltzes", etc.) are present
-- as ability entries in the resource manager and HasAbility() returns true for
-- them, but they aren't executable. Filter them out of the JA dropdown.
local CATEGORY_PLACEHOLDER_NAMES = {
    ['Sambas']         = true,
    ['Waltzes']        = true,
    ['Steps']          = true,
    ['Jigs']           = true,
    ['Flourishes I']   = true,
    ['Flourishes II']  = true,
    ['Flourishes III'] = true,
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
                local abilityType = ability.Type or 0;
                local abilityName = ability.Name[1];

                -- Exclude: weapon skills (separate dropdown), passive traits (not
                -- macroable), pet commands (separate section), and subcategory
                -- header placeholders ("Sambas", "Waltzes", etc.).
                local isWeaponSkill = abilityType == ABILITY_TYPE.WeaponSkill;
                local isTrait       = abilityType == ABILITY_TYPE.Trait;
                if not isWeaponSkill
                    and not isTrait
                    and not PET_COMMAND_NAMES[abilityName]
                    and not CATEGORY_PLACEHOLDER_NAMES[abilityName]
                then

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

    -- Scan HasAbility and filter by Type == WeaponSkill (3)
    for abilityId = 1, 1024 do
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

--- Force rebuild spell cache (call when macro editor dropdown opens)
function M.ForceRefreshSpells()
    cachedSpells = M.GetPlayerSpells();
end

--- Force rebuild ability cache (call when macro editor dropdown opens)
function M.ForceRefreshAbilities()
    cachedAbilities = M.GetPlayerAbilities();
end

--- Force rebuild weaponskill cache (call when macro editor dropdown opens)
function M.ForceRefreshWeaponskills()
    cachedWeaponskills = M.GetPlayerWeaponskills();
end

--- Force rebuild item cache (call when macro editor dropdown opens)
function M.ForceRefreshItems()
    cachedItems = M.GetPlayerItems();
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

--- Check if a pet command is available for the current job/pet context
---@param commandName string
---@return boolean
function M.IsPetCommandAvailable(commandName)
    if not commandName or commandName == '' then
        return false;
    end

    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then return true; end

    local jobId = player:GetMainJob();
    local petregistry = require('modules.hotbar.petregistry');
    local petpalette = require('modules.hotbar.petpalette');

    if not petregistry.IsPetJob(jobId) then
        return false;
    end

    local avatarName = nil;
    local activePetName = nil;
    if jobId == petregistry.JOB_BST then
        activePetName = petpalette.GetCurrentPetEntityName();
    end

    local commands = petregistry.GetPetCommandsForJob(jobId, avatarName, activePetName);
    for _, cmd in ipairs(commands) do
        if cmd.name == commandName then
            return true;
        end
    end

    return false;
end

-- Export helper for external use
M.IsGarbageSpellName = IsGarbageSpellName;
M.CONTAINERS = CONTAINERS;
M.ACCESSIBLE_CONTAINERS = ACCESSIBLE_CONTAINERS;

return M;
