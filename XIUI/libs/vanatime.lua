--[[
* Game UTC clock for decoding Vana'diel status / item timestamps.
]]--

local M = {};

local TIME_PATTERN = '8B0D????????8B410C8B49108D04808D04808D04808D04C1C3';
local VANA_BASE = 0x3C307D70;
local INFINITE = 0x7FFFFFFF;

local timeStruct = nil;  -- struct whose +0x0C field is the live UTC stamp

local function Ensure()
    if timeStruct ~= nil then return timeStruct ~= 0; end

    local pointer = ashita.memory.find('FFXiMain.dll', 0, TIME_PATTERN, 2, 0);
    if pointer == nil or pointer == 0 then
        timeStruct = 0;
        return false;
    end

    local ptr = ashita.memory.read_uint32(pointer);
    if ptr == nil or ptr == 0 then
        timeStruct = 0;
        return false;
    end

    ptr = ashita.memory.read_uint32(ptr);
    if ptr == nil or ptr == 0 then
        timeStruct = 0;
        return false;
    end

    timeStruct = ptr;
    return true;
end

M.Utc = function()
    if not Ensure() then return nil; end
    return ashita.memory.read_uint32(timeStruct + 0x0C);
end

-- GetStatusTimers raw value -> earth seconds, or -1 if it never expires.
-- Pass stamp from Utc() when converting several timers in one pass.
M.StatusSeconds = function(raw, stamp)
    if raw == nil then return nil; end
    if raw == INFINITE then return -1; end

    stamp = stamp or M.Utc();
    if stamp == nil then return nil; end

    local remaining = raw - ((stamp - VANA_BASE) * 60);
    while remaining < -2147483648 do
        remaining = remaining + 0x100000000;
    end

    if remaining < 0 then return 0; end
    return remaining / 60;
end

return M;
