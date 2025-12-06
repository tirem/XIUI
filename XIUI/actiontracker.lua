-- Action Tracker for improved Target-of-Target detection
require('common');
require('helpers');

local actionTracker = T{
    -- Tracks last action target for each enemy
    -- Format: [enemyServerId] = {targetId = <id>, targetIndex = <index>, timestamp = <time>}
    lastTargets = T{};
};

-- Action types that indicate combat targeting
-- Type 1: Basic Attack
-- Type 4: Magic (Finish)
-- Type 7: Mon/WepSkill (Start)
-- Type 11: Monster Skill (Finish)
local COMBAT_ACTION_TYPES = T{1, 4, 7, 11};

-- Time in seconds before an action target entry expires
local ACTION_EXPIRY_TIME = 30;

-- Note: Uses SPAWN_FLAG_PLAYER global from helpers.lua

--[[
* Determines if an entity is NOT a player (i.e., could be enemy/NPC/etc)
* @param {number} serverId - The server ID to check
* @return {boolean} True if the entity is not a player
--]]
local function IsNotPlayer(serverId)
    local index = GetIndexFromId(serverId);
    if (index == nil or index == 0) then
        return false;
    end
    local entity = GetEntity(index);
    if (entity == nil) then
        return false;
    end
    -- Check if this is NOT a player
    return bit.band(entity.SpawnFlags, SPAWN_FLAG_PLAYER) ~= SPAWN_FLAG_PLAYER;
end

--[[
* Cleans up expired action target entries
--]]
local function CleanupStaleEntries()
    local now = os.time();
    local toRemove = T{};

    for serverId, data in pairs(actionTracker.lastTargets) do
        if (data.timestamp + ACTION_EXPIRY_TIME < now) then
            table.insert(toRemove, serverId);
        end
    end

    for _, serverId in ipairs(toRemove) do
        actionTracker.lastTargets[serverId] = nil;
    end
end

--[[
* Handles incoming action packets to track enemy targets
* @param {table} actionPacket - The parsed action packet
--]]
actionTracker.HandleActionPacket = function(actionPacket)
    if (actionPacket == nil or actionPacket.UserId == nil) then
        return;
    end

    -- Only track combat action types
    if (not COMBAT_ACTION_TYPES:contains(actionPacket.Type)) then
        return;
    end

    -- Only track non-players (enemies/NPCs/monsters)
    if (not IsNotPlayer(actionPacket.UserId)) then
        return;
    end

    -- Get the first target (primary target of the action)
    if (actionPacket.Targets == nil or #actionPacket.Targets == 0) then
        return;
    end

    local firstTarget = actionPacket.Targets[1];
    if (firstTarget == nil or firstTarget.Id == nil) then
        return;
    end

    local targetIndex = GetIndexFromId(firstTarget.Id);

    -- Store the last target for this enemy
    actionTracker.lastTargets[actionPacket.UserId] = T{
        targetId = firstTarget.Id,
        targetIndex = targetIndex,
        timestamp = os.time()
    };

    -- Periodically clean up stale entries (every 100 actions)
    if (math.random(1, 100) == 1) then
        CleanupStaleEntries();
    end
end

--[[
* Gets the last known target of an enemy based on their actions
* @param {number} enemyServerId - The server ID of the enemy
* @return {number|nil} The target index, or nil if no recent action
--]]
actionTracker.GetLastTarget = function(enemyServerId)
    if (enemyServerId == nil) then
        return nil;
    end

    local data = actionTracker.lastTargets[enemyServerId];
    if (data == nil) then
        return nil;
    end

    -- Check if the entry has expired
    if (data.timestamp + ACTION_EXPIRY_TIME < os.time()) then
        actionTracker.lastTargets[enemyServerId] = nil;
        return nil;
    end

    return data.targetIndex;
end

--[[
* Handles zone packets to clear all tracking data
--]]
actionTracker.HandleZonePacket = function()
    actionTracker.lastTargets = T{};
end

return actionTracker;
