--[[
* XIUI hotbar - Recast Tracking Module
* Tracks spell and ability cooldowns via Ashita memory
* Provides shared cooldown info for hotbar and crossbar
]]--

local abilityRecast = require('libs.abilityrecast');
local actiondb = require('modules.hotbar.actiondb');

local M = {};

-- Cached spell recasts (refreshed periodically)
-- Key: spellId, Value: remaining seconds
M.spellRecasts = {};

-- Frame tracking to prevent multiple updates per frame
M.lastUpdateTime = 0;

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

    M.spellRecasts = {};

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
function M.GetActionRecast(actionType, spellId, abilityId)
    local remaining = 0;

    if actionType == 'ma' and spellId then
        remaining = M.GetSpellRecast(spellId);
    elseif actionType == 'ja' and abilityId then
        remaining = M.GetAbilityRecast(abilityId);
    elseif actionType == 'pet' and abilityId then
        remaining = M.GetAbilityRecast(abilityId);
    end
    -- Note: 'ws' (weaponskills) don't have individual recasts

    return remaining, M.FormatRecast(remaining);
end

-- Get complete cooldown info for an action
-- This is the main entry point for hotbar/crossbar cooldown display
-- @param actionData: Table with actionType and action fields (bind or slotData)
-- @return table: { isOnCooldown, recastText, remaining, spellId, abilityId }
function M.GetCooldownInfo(actionData)
    if not actionData or not actionData.actionType then
        return {
            isOnCooldown = false,
            recastText = nil,
            remaining = 0,
            spellId = nil,
            abilityId = nil,
        };
    end

    -- Look up action IDs based on action type
    local spellId = nil;
    local abilityId = nil;

    if actionData.actionType == 'ma' then
        spellId = actiondb.GetSpellId(actionData.action);
    elseif actionData.actionType == 'ja' or actionData.actionType == 'pet' then
        abilityId = actiondb.GetAbilityId(actionData.action);
    end

    -- Get recast state
    local remaining, recastText = M.GetActionRecast(actionData.actionType, spellId, abilityId);

    return {
        isOnCooldown = remaining > 0,
        recastText = recastText,
        remaining = remaining,
        spellId = spellId,
        abilityId = abilityId,
    };
end

return M;
