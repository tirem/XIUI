--[[
* XIUI Item Recast Library
* Provides item and equipment cooldown tracking via memory reading
* Based on tCrossBar implementation by Thorny
*
* Equipment cooldowns are stored in the item's Extra data:
* - Offset 5: Use timestamp (when item was last used)
* - Offset 9: Equip timestamp (for items with Flags == 5)
]]--

local struct = require('struct');
local vanatime = require('libs.vanatime');

local M = {};

-- VanaOffset constant for timestamp conversion
local VANA_OFFSET = 0x3C307D70;

-- Container IDs to scan for equipment
local EQUIPMENT_CONTAINERS = { 0, 8, 10, 11, 12, 13, 14, 15, 16 };  -- Inventory, Wardrobes

-- Container IDs to scan for consumable items
local ITEM_CONTAINERS = { 0, 3 };  -- Inventory, Temp items

local function GetCurrentTime()
    return vanatime.Utc() or 0;
end

-- Parse 4-byte unsigned int from item.Extra at given offset (1-indexed)
-- @param extra: The item.Extra byte string
-- @param offset: 1-indexed offset into the Extra data
-- @return: Unsigned 32-bit integer, or 0 if invalid
local function ReadExtraUInt32(extra, offset)
    if not extra or #extra < (offset + 3) then return 0; end
    -- struct.unpack returns the value and next position
    local value = struct.unpack('I', extra, offset);
    return value or 0;
end

-- Get equipment recast by scanning inventory containers
-- @param itemId: The item ID to check
-- @return: remaining seconds, item count
function M.GetEquipmentRecast(itemId)
    if not itemId or itemId == 0 then return 0, 0; end

    local inventory = AshitaCore:GetMemoryManager():GetInventory();
    if not inventory then return 0, 0; end

    local currentTime = GetCurrentTime();
    if currentTime == 0 then return 0, 0; end

    local lowestRecast = 0;
    local totalCount = 0;

    for _, containerId in ipairs(EQUIPMENT_CONTAINERS) do
        local containerMax = inventory:GetContainerCountMax(containerId);
        if containerMax and containerMax > 0 then
            for slotIndex = 1, containerMax do
                local item = inventory:GetContainerItem(containerId, slotIndex);
                if item and item.Id == itemId then
                    totalCount = totalCount + (item.Count or 1);

                    -- Check for recast timestamps in Extra data
                    if item.Extra and #item.Extra >= 12 then
                        local recast = 0;

                        -- Read use timestamp at offset 5
                        local useTime = ReadExtraUInt32(item.Extra, 5);
                        if useTime > 0 then
                            local useRecast = (useTime + VANA_OFFSET) - currentTime;
                            if useRecast > 0 then
                                recast = math.max(recast, useRecast);
                            end
                        end

                        -- Read equip timestamp at offset 9 (only for items with Flags == 5)
                        if item.Flags == 5 then
                            local equipTime = ReadExtraUInt32(item.Extra, 9);
                            if equipTime > 0 then
                                local equipRecast = (equipTime + VANA_OFFSET) - currentTime;
                                if equipRecast > 0 then
                                    recast = math.max(recast, equipRecast);
                                end
                            end
                        end

                        -- Track lowest non-zero recast (soonest available)
                        if recast > 0 then
                            if lowestRecast == 0 or recast < lowestRecast then
                                lowestRecast = recast;
                            end
                        end
                    end
                end
            end
        end
    end

    return lowestRecast, totalCount;
end

-- Get consumable item count (items typically don't have individual recasts)
-- @param itemId: The item ID to check
-- @return: remaining seconds (usually 0), item count
function M.GetItemRecast(itemId)
    if not itemId or itemId == 0 then return 0, 0; end

    local inventory = AshitaCore:GetMemoryManager():GetInventory();
    if not inventory then return 0, 0; end

    local totalCount = 0;

    for _, containerId in ipairs(ITEM_CONTAINERS) do
        local containerMax = inventory:GetContainerCountMax(containerId);
        if containerMax and containerMax > 0 then
            for slotIndex = 1, containerMax do
                local item = inventory:GetContainerItem(containerId, slotIndex);
                if item and item.Id == itemId then
                    totalCount = totalCount + (item.Count or 1);
                end
            end
        end
    end

    -- Consumable items don't have persistent recasts in their Extra data
    -- Their cooldowns are typically status-effect based (e.g., Medicated)
    return 0, totalCount;
end

-- Get item recast - tries equipment first, falls back to consumable
-- @param itemId: The item ID to check
-- @return: remaining seconds, item count
function M.GetRecast(itemId)
    -- Try equipment containers first (has recast data)
    local recast, count = M.GetEquipmentRecast(itemId);
    if count > 0 then
        return recast, count;
    end

    -- Fall back to consumable item containers
    return M.GetItemRecast(itemId);
end

-- Format recast time to readable string
-- @param seconds: Remaining time in seconds
-- @return: Formatted string (e.g., "1:30", "45s", "3")
function M.FormatRecast(seconds)
    if not seconds or seconds <= 0 then return nil; end

    seconds = math.floor(seconds);

    if seconds >= 3600 then
        local hours = math.floor(seconds / 3600);
        local mins = math.floor((seconds % 3600) / 60);
        return string.format('%d:%02d', hours, mins);
    elseif seconds >= 60 then
        local mins = math.floor(seconds / 60);
        local secs = seconds % 60;
        return string.format('%d:%02d', mins, secs);
    elseif seconds >= 10 then
        return string.format('%ds', seconds);
    else
        return string.format('%d', seconds);
    end
end

-- Check if the shared game-clock pointer resolved (for debugging)
function M.IsInitialized()
    return vanatime.Utc() ~= nil;
end

return M;
