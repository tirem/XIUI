--[[
* XIUI Weeklies Module
* Tracks weekly objectives and cooldowns
]]--

require('common');
local data = require('modules.weeklies.data');
local display = require('modules.weeklies.display');

local M = {};
M.initialized = false;

local isListeningForKeyItems = true;
local lastZoneId = 0;

local PACKET_KEY_ITEMS = 0x055;
local PACKET_ZONE_IN = 0x00A;
local PACKET_ZONE_OUT = 0x00B;
local PACKET_DOWNLOAD_STOP = 0x041;

local function ParseZonePacket(data)
    local zoneId = struct.unpack('H', data, 0x30 + 1);
    return { zone = zoneId };
end

local function ParseKeyItems(packet)
    local keyItems = {
        heldList = {},
        seenList = {},
        type = ashita.bits.unpack_be(packet, 0x84 * 8, 8)
    };

    local idBase = keyItems.type * 512;
    local heldBit = 0x04 * 8;
    local seenBit = 0x44 * 8;

    for i = 0, 511 do
        keyItems.heldList[idBase + i] = ashita.bits.unpack_be(packet, heldBit + i, 1) == 1;
        keyItems.seenList[idBase + i] = ashita.bits.unpack_be(packet, seenBit + i, 1) == 1;
    end

    return keyItems;
end

local function GetNextConquestReset()
    local now = os.time();
    local utc = os.date("!*t", now);

    local daysUntilSat = 7 - utc.wday;

    if utc.wday == 7 and utc.hour >= 15 then
        daysUntilSat = 7;
    elseif utc.wday == 7 and utc.hour < 15 then
        daysUntilSat = 0;
    elseif utc.wday == 1 then
        daysUntilSat = 6;
    end
    
    local target_utc = {
        year = utc.year,
        month = utc.month,
        day = utc.day + daysUntilSat,
        hour = 15,
        minute = 0,
        second = 0
    };

    local local_time = os.time();
    local utc_time = os.time(os.date("!*t", local_time));
    local offset = os.difftime(local_time, utc_time);
    
    return os.time(target_utc) + offset;
end

local function setListening(listening)
    isListeningForKeyItems = listening;
    display.SetListening(listening);
end

local function handleKeyItemsPacket(e)
    local player = GetPlayerSafe();
    if not player then return; end

    local keyItems = ParseKeyItems(e.data_raw);
    local now = os.time();
    local timers = gConfig.weekliesTimers or {};
    local changed = false;

    for _, objective in ipairs(data.Objectives) do
        local keyItemId = objective.KeyItem.Id;
        local timerKey = tostring(keyItemId);

        local hasItem = keyItems.heldList[keyItemId] == true;

        if objective.Cooldown == "Conquest" then
            -- For Conquest KIs:
            -- If we HAVE the item, the timer must be pushed to the NEXT conquest reset
            -- because we cannot get another one until then.
            if hasItem then
                local nextReset = GetNextConquestReset();
                if not timers[timerKey] or timers[timerKey].time ~= nextReset then
                    timers[timerKey] = {
                        time = nextReset,
                        desc = os.date('%a, %b %d at %X', nextReset),
                    };
                    changed = true;
                end
            end
            -- If we DON'T have the item, we rely on whatever timer is there.
            -- If the timer has expired (past reset), it means it's available.
            -- We don't need to force a timer if one isn't set, or we can leave it as is.
        else
            -- For standard cooldowns (Non-Conquest):
            -- We only care when the item is LOST (used).
            local hadItem = player:HasKeyItem(keyItemId);
            if hadItem and not hasItem then
                local timestamp = now + objective.Cooldown;
                timers[timerKey] = {
                    time = timestamp,
                    desc = os.date('%a, %b %d at %X', timestamp),
                };
                changed = true;
            elseif hasItem then
                -- If we have the item, clear the timer so it shows "Obtained" (or logic handled in display)
                -- Actually, if we have the item, we don't need a "Ready Time" because we have it.
                if timers[timerKey] then
                    timers[timerKey] = nil;
                    changed = true;
                end
            end
        end
    end

    if changed then
        gConfig.weekliesTimers = timers;
    end
end

local function isZoneMatch(objectiveZones, zoneId)
    if not objectiveZones then return false; end
    for _, zid in ipairs(objectiveZones) do
        if zid == zoneId then return true; end
    end
    return false;
end

local function handleZonePacket(e)
    if not gConfig.weekliesZoneAlerts then return; end
    if e.id ~= PACKET_ZONE_IN then return; end

    local zonePacket = ParseZonePacket(e.data);
    local zoneId = zonePacket.zone;

    if zoneId == lastZoneId then return; end
    lastZoneId = zoneId;

    local now = os.time();
    local timers = gConfig.weekliesTimers or {};

    local filters = gConfig.weekliesZoneAlertFilters or {};

    for _, objective in ipairs(data.Objectives) do
        local key = tostring(objective.KeyItem.Id);
        local enabled = filters[key];
        if enabled ~= false and isZoneMatch(objective.ZoneIds, zoneId) then
            local timerKey = key;
            local timer = timers[timerKey];
            local available = true;

            -- If the timer is in the future, it's NOT available.
            if timer and timer.time > now then
                available = false;
            end
            
            -- If the timer is UNKNOWN (nil), we assume it's NOT available for alert purposes
            -- (to avoid false positives), unless the user specifically wants to know.
            -- But typically unknown = ???, so we shouldn't spam alerts.
            if not timer then
                -- Actually, if there is NO timer, it might mean it's ready?
                -- For Conquest KIs, no timer = ready (if we don't have it).
                -- For others, no timer = ready (if we don't have it).
                -- So available = true is correct default if we treat "no timer" as "ready".
                -- However, let's be safe: "available" implies we KNOW it's ready.
                -- If we haven't seen a timer set, it usually means ready.
                available = true;
            end

            local player = GetPlayerSafe();
            local hasItem = player and player:HasKeyItem(objective.KeyItem.Id);

            -- Alert ONLY if available AND we don't have it
            if available and (not hasItem) then
                display.ShowAlert(string.format('%s available to obtain!', objective.Name), 5);
            end
        end
    end
end

M.Initialize = function(settings)
    if M.initialized then return; end
    M.initialized = true;
    setListening(true);
end

M.UpdateVisuals = function(settings)
end

M.SetHidden = function(hidden)
    display.SetHidden(hidden);
end

M.HandlePacket = function(e)
    if not M.initialized then return; end

    if e.id == PACKET_ZONE_IN or e.id == PACKET_ZONE_OUT then
        setListening(false);
        handleZonePacket(e);
    elseif e.id == PACKET_DOWNLOAD_STOP then
        setListening(true);
    elseif e.id == PACKET_KEY_ITEMS then
        handleKeyItemsPacket(e);
    end
end

M.DrawWindow = function()
    display.DrawWindow();
end

M.Cleanup = function()
    M.initialized = false;
    setListening(false);
end

return M;
