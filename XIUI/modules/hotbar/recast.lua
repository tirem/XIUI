--[[
* XIUI hotbar - Recast Tracking Module
* Tracks spell, ability, and item cooldowns via Ashita memory
* Provides shared cooldown info for hotbar and crossbar
]]--

local abilityRecast = require('libs.abilityrecast');
local itemRecast = require('libs.itemrecast');
local actiondb = require('modules.hotbar.actiondb');
local petregistry = require('modules.hotbar.petregistry');

local M = {};

-- Module-level setting for Hh:MM format (set once per frame, used by all functions)
local useHHMMFormat = false;

-- Set the Hh:MM format preference (call once per frame before any recast queries)
function M.SetHHMMFormat(enabled)
    useHHMMFormat = enabled or false;
end

-- Blood Pact timer IDs
local BP_RAGE_TIMER_ID = 173;
local BP_WARD_TIMER_ID = 174;

-- Get Blood Pact timer ID by command name
-- Returns timer ID (173 for Rage, 174 for Ward) or nil if not a blood pact
local function GetBloodPactTimerId(commandName)
    if not commandName then return nil; end

    -- Check if it's a Rage pact
    for _, pact in ipairs(petregistry.bloodPactsRage or {}) do
        if pact.name == commandName then
            return BP_RAGE_TIMER_ID;
        end
    end

    -- Check if it's a Ward pact
    for _, pact in ipairs(petregistry.bloodPactsWard or {}) do
        if pact.name == commandName then
            return BP_WARD_TIMER_ID;
        end
    end

    return nil;
end

-- Get pet command recast by timer ID
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

    if actionData.actionType == 'ma' then
        spellId = actiondb.GetSpellId(actionData.action);
        remaining, recastText = M.GetActionRecast(actionData.actionType, spellId, nil, nil);
    elseif actionData.actionType == 'pet' then
        -- Pet commands (Blood Pacts, Ready, etc.) - check for known timer IDs
        local bpTimerId = GetBloodPactTimerId(actionData.action);
        if bpTimerId then
            -- Blood Pact - use timer ID directly
            remaining = M.GetPetCommandRecast(bpTimerId);
            recastText = M.FormatRecast(remaining);
        else
            -- Other pet commands - try ability lookup
            abilityId = actiondb.GetAbilityId(actionData.action);
            remaining, recastText = M.GetActionRecast(actionData.actionType, nil, abilityId, nil);
        end
    elseif actionData.actionType == 'ja' then
        abilityId = actiondb.GetAbilityId(actionData.action);
        remaining, recastText = M.GetActionRecast(actionData.actionType, nil, abilityId, nil);
    elseif actionData.actionType == 'item' or actionData.actionType == 'equip' then
        -- itemId should already be stored in the action data
        itemId = actionData.itemId;
        -- Fallback: look up itemId by name if not set (for macros saved via manual text input)
        if not itemId and actionData.action then
            itemId = actiondb.GetItemId(actionData.action);
        end
        remaining, recastText = M.GetActionRecast(actionData.actionType, nil, nil, itemId);
    end

    -- Reuse result table to avoid GC pressure
    cooldownResult.isOnCooldown = remaining > 0;
    cooldownResult.recastText = recastText;
    cooldownResult.remaining = remaining;
    cooldownResult.spellId = spellId;
    cooldownResult.abilityId = abilityId;
    cooldownResult.itemId = itemId;
    return cooldownResult;
end

return M;
