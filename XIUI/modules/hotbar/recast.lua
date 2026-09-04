--[[
* XIUI hotbar - Recast Tracking Module
* Tracks spell, ability, and item cooldowns via Ashita memory
* Provides shared cooldown info for hotbar and crossbar
]]--

local abilityRecast = require('libs.abilityrecast');
local itemRecast = require('libs.itemrecast');
local actiondb = require('modules.hotbar.actiondb');

local M = {};

-- Module-level setting for Hh:MM format (set once per frame, used by all functions)
local useHHMMFormat = false;

-- Set the Hh:MM format preference (call once per frame before any recast queries)
function M.SetHHMMFormat(enabled)
    useHHMMFormat = enabled or false;
end

-- Get pet command recast by timer ID (shared pools: BP 173/174, Heel/Stay/Leave 101, etc.)
-- Returns: remaining seconds, or 0 if ready
function M.GetPetCommandRecast(timerId)
    if not timerId then return 0; end
    return abilityRecast.GetAbilityRecastSeconds(timerId);
end

-- Cached spell recasts. Populated lazily by GetSpellRecast — only spell IDs
-- actually queried during a frame get a memory hit. Previously this was a
-- 1025-id scan every 50ms; with another action-heavy addon loaded that
-- baseline ate frame budget that didn't need to be spent.
-- Key: spellId, Value: remaining seconds (entry absent => 0).
M.spellRecasts = {};
local spellRecastExpiry = {};      -- spellId -> os.clock() at which entry is stale
local SPELL_RECAST_TTL = 0.05;     -- 20 Hz refresh, matches old prescan cadence

-- Ability/item recasts are far more expensive than spells (slot scans / inventory
-- reads), so cache them at 20 Hz per id like spells, deduping slots that share one.
local abilityRecastCache = {};     -- abilityId -> remaining seconds
local abilityRecastExpiry = {};    -- abilityId -> os.clock() expiry
local itemRecastCache = {};        -- itemId -> remaining seconds
local itemRecastExpiry = {};       -- itemId -> os.clock() expiry
local ACTION_RECAST_TTL = 0.05;

-- Reusable result table for GetCooldownInfo to avoid GC pressure
-- (Creating ~7200 tables/sec with 120 slots @ 60fps causes periodic GC hitches)
local cooldownResult = {
    isOnCooldown = false,
    recastText = nil,
    remaining = 0,
    spellId = nil,
    abilityId = nil,
    itemId = nil,
    rechargingExtra = false,
};

-- Get spell recast by ID. Fetches from Ashita memory on cache miss / expiry,
-- otherwise reuses the last value. TTL matches the old prescan interval so
-- visible cooldown text refreshes at the same rate.
-- Returns: remaining seconds, or 0 if ready.
function M.GetSpellRecast(spellId)
    if not spellId then return 0; end
    local now = os.clock();
    local exp = spellRecastExpiry[spellId];
    if exp and now < exp then
        return M.spellRecasts[spellId] or 0;
    end
    local recastMgr = AshitaCore:GetMemoryManager():GetRecast();
    if not recastMgr then return M.spellRecasts[spellId] or 0; end
    local timer = recastMgr:GetSpellTimer(spellId);
    if timer and timer > 0 then
        M.spellRecasts[spellId] = timer / 60;
    else
        M.spellRecasts[spellId] = nil;
    end
    spellRecastExpiry[spellId] = now + SPELL_RECAST_TTL;
    return M.spellRecasts[spellId] or 0;
end

-- Get ability recast by ability ID
-- Uses abilityrecast.lua which scans memory slots
-- Returns: remaining seconds, or 0 if ready
function M.GetAbilityRecast(abilityId)
    if not abilityId then return 0; end
    local now = os.clock();
    local exp = abilityRecastExpiry[abilityId];
    if exp and now < exp then
        return abilityRecastCache[abilityId] or 0;
    end
    local remaining = abilityRecast.GetAbilityRecastByAbilityId(abilityId);
    abilityRecastCache[abilityId] = (remaining and remaining > 0) and remaining or nil;
    abilityRecastExpiry[abilityId] = now + ACTION_RECAST_TTL;
    return abilityRecastCache[abilityId] or 0;
end

-- Shared timer-id lookup (PUP maneuvers, etc. share one RecastTimerId)
---@param timerId number
---@return number remainingSeconds
function M.GetRecastByTimerId(timerId)
    if not timerId then return 0; end
    return abilityRecast.GetAbilityRecastSeconds(timerId) or 0;
end

-- Charge-based ability pools keyed by RecastTimerId.
-- baseSeconds is the full-pool recast (Quick Draw 2x60s = 120).
local CHARGE_TIMER = {
    READY = 102,
    QUICK_DRAW = 195,
    STRATAGEM = 231,
};
local CHARGE_POOL = {
    [102] = { maxCharges = 3, baseSeconds = 90 },
    [195] = { maxCharges = 2, baseSeconds = 120 },
};

local function RecastRawToDisplaySeconds(raw)
    if not raw or raw <= 0 then return 0; end
    return raw / 60;
end

-- Every slot sharing a pool (all stratagems, all ready moves) asks for the same
-- timer, so cache at 20 Hz like the other recasts instead of rescanning per slot.
local chargeCount = {};            -- timerId -> remaining charges
local chargeNext = {};             -- timerId -> seconds until the next charge
local chargeDur = {};              -- timerId -> seconds per charge
local chargeExpiry = {};           -- timerId -> os.clock() expiry

local function ComputeChargePool(timerId, maxCharges, baseSeconds)
    if maxCharges <= 0 then
        return 0, 0, 0;
    end
    local data = abilityRecast.GetAbilityTimerDataByTimerId(timerId);
    local modifier = (data and data.Modifier) or 0;
    local baseRecast = 60 * (baseSeconds + modifier);
    if baseRecast <= 0 then
        return 0, RecastRawToDisplaySeconds(data and data.Recast), 0;
    end
    local chargeValue = baseRecast / maxCharges;
    local duration = RecastRawToDisplaySeconds(chargeValue);
    if not data or not data.Recast or data.Recast == 0 then
        return maxCharges, 0, duration;
    end
    local remainingCharges = maxCharges - math.ceil(data.Recast / chargeValue);
    if remainingCharges < 0 then remainingCharges = 0; end
    if remainingCharges > maxCharges then remainingCharges = maxCharges; end
    -- Wrap so an exact multiple is a full charge window, not 0s.
    local timeUntilNext = ((data.Recast - 1) % chargeValue) + 1;
    return remainingCharges, RecastRawToDisplaySeconds(timeUntilNext), duration;
end

--- Remaining charges + seconds until next charge for a charge pool
---@param timerId number
---@param maxCharges number
---@param baseSeconds number Base full-pool recast in seconds (before modifier)
---@return number charges
---@return number nextChargeSeconds
---@return number chargeDurationSeconds
local function GetChargePool(timerId, maxCharges, baseSeconds)
    local now = os.clock();
    local exp = chargeExpiry[timerId];
    if exp and now < exp then
        return chargeCount[timerId], chargeNext[timerId], chargeDur[timerId];
    end

    local charges, nextCharge, duration = ComputeChargePool(timerId, maxCharges, baseSeconds);
    chargeCount[timerId], chargeNext[timerId], chargeDur[timerId] = charges, nextCharge, duration;
    chargeExpiry[timerId] = now + ACTION_RECAST_TTL;
    return charges, nextCharge, duration;
end

function M.GetReadyCharges()
    local pool = CHARGE_POOL[CHARGE_TIMER.READY];
    return GetChargePool(CHARGE_TIMER.READY, pool.maxCharges, pool.baseSeconds);
end

function M.GetQuickDrawCharges()
    local pool = CHARGE_POOL[CHARGE_TIMER.QUICK_DRAW];
    return GetChargePool(CHARGE_TIMER.QUICK_DRAW, pool.maxCharges, pool.baseSeconds);
end

--- SCH stratagem charges (level-scaled max)
---@return number charges
---@return number nextChargeSeconds
---@return number maxCharges
function M.GetStratagemCharges()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then return 0, 0, 0; end

    local lvl = 0;
    if player:GetMainJob() == 20 then
        lvl = player:GetMainJobLevel();
    elseif player:GetSubJob() == 20 then
        lvl = player:GetSubJobLevel();
    else
        return 0, 0, 0;
    end

    local maxCharges = math.floor((lvl - 10) / 20) + 1;
    if maxCharges < 1 then maxCharges = 0; end
    local charges, nextCharge = GetChargePool(CHARGE_TIMER.STRATAGEM, maxCharges, 240);
    return charges, nextCharge, maxCharges;
end

M.CHARGE_TIMER = CHARGE_TIMER;

--- Per-charge recast for overlay/bar display (not the full pool timer).
---@return table|nil { charges, nextCharge, maxCharges, chargeDuration }
function M.GetChargeDisplayByTimerId(timerId)
    if not timerId then return nil; end
    if timerId == CHARGE_TIMER.STRATAGEM then
        local charges, nextCharge, maxCharges = M.GetStratagemCharges();
        if maxCharges < 1 then return nil; end
        local _, _, duration = GetChargePool(CHARGE_TIMER.STRATAGEM, maxCharges, 240);
        return { charges = charges, nextCharge = nextCharge, maxCharges = maxCharges, chargeDuration = duration or 0 };
    end
    local pool = CHARGE_POOL[timerId];
    if not pool then return nil; end
    local charges, nextCharge, duration = GetChargePool(timerId, pool.maxCharges, pool.baseSeconds);
    return { charges = charges, nextCharge = nextCharge, maxCharges = pool.maxCharges, chargeDuration = duration or 0 };
end

function M.GetChargeDisplayByAbilityId(abilityId)
    if not abilityId then return nil; end
    local resourceMgr = AshitaCore:GetResourceManager();
    if not resourceMgr then return nil; end
    local ability = resourceMgr:GetAbilityById(abilityId);
    local display = M.GetChargeDisplayByTimerId(ability and (ability.RecastTimerId or ability.TimerId));
    if display then return display; end
    -- Menu/hotbar may bind the low stub id; JA RecastTimerId lives on id+512.
    if abilityId < 512 then
        ability = resourceMgr:GetAbilityById(abilityId + 512);
        display = M.GetChargeDisplayByTimerId(ability and (ability.RecastTimerId or ability.TimerId));
    end
    return display;
end

-- Get item/equipment recast by item ID
-- Uses itemrecast.lua which reads from item.Extra data
-- Returns: remaining seconds, or 0 if ready
function M.GetItemRecast(itemId)
    if not itemId then return 0; end
    local now = os.clock();
    local exp = itemRecastExpiry[itemId];
    if exp and now < exp then
        return itemRecastCache[itemId] or 0;
    end
    local recast = itemRecast.GetRecast(itemId);
    itemRecastCache[itemId] = (recast and recast > 0) and recast or nil;
    itemRecastExpiry[itemId] = now + ACTION_RECAST_TTL;
    return itemRecastCache[itemId] or 0;
end

-- Format recast time for display
-- Returns: formatted string or nil if ready
-- @param seconds: Time in seconds
function M.FormatRecast(seconds)
    if not seconds or seconds <= 0 then
        return nil;
    end

    local days = math.floor(seconds / 86400);
    local hours = math.floor((seconds % 86400) / 3600);
    local mins = math.floor((seconds % 3600) / 60);
    local secs = math.floor(seconds % 60);

    if days >= 1 then
        -- Show as Xd Yh for times >= 24 hours (e.g. "7d 5h" or "1d")
        if hours > 0 then
            return string.format('%dd %dh', days, hours);
        else
            return string.format('%dd', days);
        end
    elseif hours >= 1 then
        if useHHMMFormat then
            -- Show as Hh:MM for times >= 1 hour (e.g. "1h:24" to distinguish from MM:SS)
            return string.format('%dh:%02d', hours, mins);
        else
            -- Show as Xh Ym for times >= 1 hour (e.g. "1h 30m")
            return string.format('%dh %dm', hours, mins);
        end
    elseif seconds >= 60 then
        -- Show as MM:SS for times >= 1 minute (e.g. "14:49")
        return string.format('%d:%02d', mins, secs);
    elseif seconds >= 10 then
        -- Show as whole seconds for 10-59s (e.g. "45")
        return string.format('%d', secs);
    else
        -- Show with decimal for < 10s (e.g. "5.2")
        return string.format('%.1f', seconds);
    end
end

-- Get recast for any action type
-- Returns: remainingSeconds, formattedText
function M.GetActionRecast(actionType, spellId, abilityId, itemId)
    local remaining = 0;

    if actionType == 'ma' and spellId then
        remaining = M.GetSpellRecast(spellId);
    elseif actionType == 'ja' and abilityId then
        remaining = M.GetAbilityRecast(abilityId);
    elseif actionType == 'pet' and abilityId then
        remaining = M.GetAbilityRecast(abilityId);
    elseif (actionType == 'item' or actionType == 'equip') and itemId then
        remaining = M.GetItemRecast(itemId);
    end
    -- Note: 'ws' (weaponskills) don't have individual recasts

    return remaining, M.FormatRecast(remaining);
end

-- Get complete cooldown info for an action
-- This is the main entry point for hotbar/crossbar cooldown display
-- @param actionData: Table with actionType and action fields (bind or slotData)
-- @return table: { isOnCooldown, recastText, remaining, spellId, abilityId, itemId }
-- NOTE: Returns a reused table - do NOT cache the return value, read values immediately
function M.GetCooldownInfo(actionData)
    if not actionData or not actionData.actionType then
        cooldownResult.isOnCooldown = false;
        cooldownResult.recastText = nil;
        cooldownResult.remaining = 0;
        cooldownResult.spellId = nil;
        cooldownResult.abilityId = nil;
        cooldownResult.itemId = nil;
        cooldownResult.rechargingExtra = false;
        return cooldownResult;
    end

    -- Check for macro recast source override
    -- Allows macros to display cooldown from a different action type
    if actionData.actionType == 'macro' and actionData.recastSourceType then
        local recastData = {
            actionType = actionData.recastSourceType,
            action = actionData.recastSourceAction,
            itemId = actionData.recastSourceItemId,
        };
        -- Safe: recastSourceType can't be 'macro', so no infinite recursion
        return M.GetCooldownInfo(recastData);
    end

    -- Look up action IDs based on action type
    local spellId = nil;
    local abilityId = nil;
    local itemId = nil;
    local remaining = 0;
    local recastText = nil;
    local rechargingExtra = false;

    local onCooldown = false;

    if actionData.actionType == 'ma' then
        spellId = actiondb.GetSpellId(actionData.action);
        remaining, recastText = M.GetActionRecast(actionData.actionType, spellId, nil, nil);
        onCooldown = remaining > 0;
    elseif actionData.actionType == 'pet' then
        -- Prefer pet-typed resource so shared RecastTimerId pools match
        -- (Heel/Stay/Leave = 101, BP Rage = 173, BP Ward = 174, Ready = 102).
        abilityId = actiondb.GetPetAbilityId(actionData.action);
        remaining, recastText = M.GetActionRecast(actionData.actionType, nil, abilityId, nil);
        onCooldown = remaining > 0;
    elseif actionData.actionType == 'ja' then
        abilityId = actiondb.GetAbilityId(actionData.action);
        remaining, recastText = M.GetActionRecast(actionData.actionType, nil, abilityId, nil);
        onCooldown = remaining > 0;
    elseif actionData.actionType == 'item' or actionData.actionType == 'equip' then
        -- itemId should already be stored in the action data
        itemId = actionData.itemId;
        -- Fallback: look up itemId by name if not set (for macros saved via manual text input)
        if not itemId and actionData.action then
            itemId = actiondb.GetItemId(actionData.action);
        end
        remaining, recastText = M.GetActionRecast(actionData.actionType, nil, nil, itemId);
        onCooldown = remaining > 0;
    end

    -- Charge pools: show time until the next charge, not the full remaining pool.
    if abilityId then
        local charge = M.GetChargeDisplayByAbilityId(abilityId);
        if charge then
            remaining = charge.nextCharge;
            recastText = M.FormatRecast(remaining);
            onCooldown = charge.charges < 1;
            rechargingExtra = charge.charges >= 1 and remaining > 0;
        end
    end

    -- Reuse result table to avoid GC pressure
    cooldownResult.isOnCooldown = onCooldown;
    cooldownResult.recastText = recastText;
    cooldownResult.remaining = remaining;
    cooldownResult.spellId = spellId;
    cooldownResult.abilityId = abilityId;
    cooldownResult.itemId = itemId;
    cooldownResult.rechargingExtra = rechargingExtra;
    return cooldownResult;
end

return M;
