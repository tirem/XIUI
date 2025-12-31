--[[
* XIUI hotbar - Recast Tracking Module
* Tracks spell, ability, and item cooldowns via Ashita memory
* Provides shared cooldown info for hotbar and crossbar
]]--

local abilityRecast = require('libs.abilityrecast');
local itemRecast = require('libs.itemrecast');
local actiondb = require('modules.hotbar.actiondb');

local M = {};

-- Cached spell recasts (refreshed periodically)
-- Key: spellId, Value: remaining seconds
M.spellRecasts = {};

-- Frame tracking to prevent multiple updates per frame
M.lastUpdateTime = 0;

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

-- Update all spell recasts (call once per frame in DrawWindow)
function M.Update()
    local currentTime = os.clock();
    -- Only update every 0.05 seconds (20 times per second)
    if currentTime - M.lastUpdateTime < 0.05 then
        return;
    end
    M.lastUpdateTime = currentTime;

    -- Get spell recasts from Ashita memory
    local recastMgr = AshitaCore:GetMemoryManager():GetRecast();
    if not recastMgr then return; end

    -- Clear table instead of replacing to avoid GC pressure
    for k in pairs(M.spellRecasts) do
        M.spellRecasts[k] = nil;
    end

    -- Scan spell recast timers (0-1024 covers all spells)
    for spellId = 0, 1024 do
        local timer = recastMgr:GetSpellTimer(spellId);
        if timer and timer > 0 then
            -- Timer is in 1/60th seconds, convert to seconds
            M.spellRecasts[spellId] = timer / 60;
        end
    end
end

-- Get spell recast by ID
-- Returns: remaining seconds, or 0 if ready
function M.GetSpellRecast(spellId)
    if not spellId then return 0; end
    return M.spellRecasts[spellId] or 0;
end

-- Get ability recast by ability ID
-- Uses abilityrecast.lua which scans memory slots
-- Returns: remaining seconds, or 0 if ready
function M.GetAbilityRecast(abilityId)
    if not abilityId then return 0; end
    return abilityRecast.GetAbilityRecastByAbilityId(abilityId);
end

-- Get item/equipment recast by item ID
-- Uses itemrecast.lua which reads from item.Extra data
-- Returns: remaining seconds, or 0 if ready
function M.GetItemRecast(itemId)
    if not itemId then return 0; end
    local recast, count = itemRecast.GetRecast(itemId);
    return recast or 0;
end

-- Format recast time for display
-- Returns: formatted string or nil if ready
function M.FormatRecast(seconds)
    if not seconds or seconds <= 0 then
        return nil;
    end

    if seconds >= 60 then
        -- Show as M:SS for times >= 1 minute
        local mins = math.floor(seconds / 60);
        local secs = math.floor(seconds % 60);
        return string.format('%d:%02d', mins, secs);
    elseif seconds >= 10 then
        -- Show as whole seconds for 10-59s
        return string.format('%ds', math.floor(seconds));
    else
        -- Show with decimal for < 10s
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

    -- Look up action IDs based on action type
    local spellId = nil;
    local abilityId = nil;
    local itemId = nil;

    if actionData.actionType == 'ma' then
        spellId = actiondb.GetSpellId(actionData.action);
    elseif actionData.actionType == 'ja' or actionData.actionType == 'pet' then
        abilityId = actiondb.GetAbilityId(actionData.action);
    elseif actionData.actionType == 'item' or actionData.actionType == 'equip' then
        -- itemId should already be stored in the action data
        itemId = actionData.itemId;
    end

    -- Get recast state
    local remaining, recastText = M.GetActionRecast(actionData.actionType, spellId, abilityId, itemId);

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
