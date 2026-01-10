--[[
* XIUI Ability Recast Library
* Provides direct memory reading for ability recast timers
* Shared by petbar and castcost modules
*
* This uses the same memory reading approach as PetMe addon for reliable
* recast tracking of pet commands and job abilities.
]]--

local M = {};

-- Memory pointer for ability recasts (initialized on first use)
local AbilityRecastPointer = nil;

-- Initialize the ability recast pointer by scanning memory
local function InitAbilityRecastPointer()
    if AbilityRecastPointer ~= nil then return true; end

    -- Memory pattern from PetMe addon
    local pointer = ashita.memory.find('FFXiMain.dll', 0,
        '894124E9????????8B46??6A006A00508BCEE8', 0x19, 0);

    if pointer == 0 then
        return false;
    end

    local ptr = ashita.memory.read_uint32(pointer);
    if ptr == 0 then
        return false;
    end

    AbilityRecastPointer = ptr;
    return true;
end

-- Get ability recast timer by timer ID (direct memory read)
-- Returns: raw timer value in 1/60th seconds, or 0 if ready/not found
-- @param timerId: The ability's timer ID (e.g., 173 for Blood Pact: Rage, 174 for Blood Pact: Ward)
function M.GetAbilityTimerByTimerId(timerId)
    if timerId == nil then return 0; end
    if not InitAbilityRecastPointer() then
        return 0;
    end

    for i = 1, 31 do
        local compId = ashita.memory.read_uint8(AbilityRecastPointer + (i * 8) + 3);
        if compId == timerId then
            local recast = ashita.memory.read_uint32(AbilityRecastPointer + (i * 4) + 0xF8);
            return recast;
        end
    end

    return 0;  -- Not found or ready
end

-- Get ability timer data by timer ID (includes modifier for charge-based abilities)
-- Returns: { Modifier = int16, Recast = uint32 } or { Modifier = 0, Recast = 0 } if not found
-- The modifier adjusts the base recast time (used for merit calculations)
-- @param timerId: The ability's timer ID (e.g., 102 for Ready)
function M.GetAbilityTimerDataByTimerId(timerId)
    if timerId == nil then return { Modifier = 0, Recast = 0 }; end
    if not InitAbilityRecastPointer() then
        return { Modifier = 0, Recast = 0 };
    end

    for i = 1, 31 do
        local compId = ashita.memory.read_uint8(AbilityRecastPointer + (i * 8) + 3);
        if compId == timerId then
            local modifier = ashita.memory.read_int16(AbilityRecastPointer + (i * 8) + 4);
            local recast = ashita.memory.read_uint32(AbilityRecastPointer + (i * 4) + 0xF8);
            return { Modifier = modifier, Recast = recast };
        end
    end

    return { Modifier = 0, Recast = 0 };  -- Not found or ready
end

-- Get ability recast in seconds by timer ID
-- Returns: remaining recast time in seconds, or 0 if ready
-- @param timerId: The ability's timer ID
function M.GetAbilityRecastSeconds(timerId)
    local rawTimer = M.GetAbilityTimerByTimerId(timerId);
    if rawTimer <= 0 then return 0; end
    return rawTimer / 60;
end

-- Format raw timer value to readable string (mm:ss or Xs format)
-- @param rawTimer: Timer value in 1/60th seconds
function M.FormatTimer(rawTimer)
    if rawTimer <= 0 then return 'Ready'; end
    local totalSeconds = math.floor(rawTimer / 60);
    local mins = math.floor(totalSeconds / 60);
    local secs = totalSeconds % 60;
    if mins > 0 then
        return string.format('%d:%02d', mins, secs);
    else
        return string.format('%ds', secs);
    end
end

-- Check if memory pointer is initialized (for debugging)
function M.IsInitialized()
    return AbilityRecastPointer ~= nil;
end

-- Find timer ID for an ability by scanning active recast slots
-- Uses GetAbilityByTimerId to match ability IDs
-- Returns: timerId, currentRecast (raw 1/60th seconds), or nil if not found
-- @param abilityId: The ability ID to find
function M.FindAbilityRecast(abilityId)
    if abilityId == nil then return nil, 0; end
    if not InitAbilityRecastPointer() then
        return nil, 0;
    end

    local resourceMgr = AshitaCore:GetResourceManager();

    -- Scan all recast slots to find matching ability
    for i = 0, 31 do
        local slotTimerId = ashita.memory.read_uint8(AbilityRecastPointer + (i * 8) + 3);

        -- Skip empty slots (timer ID 0, except slot 0 which is 2-hour)
        if slotTimerId > 0 or i == 0 then
            -- Look up what ability uses this timer ID
            local slotAbility = resourceMgr:GetAbilityByTimerId(slotTimerId);
            if slotAbility and slotAbility.Id == abilityId then
                -- Found matching ability - get its recast
                local recast = ashita.memory.read_uint32(AbilityRecastPointer + (i * 4) + 0xF8);
                return slotTimerId, recast;
            end
        end
    end

    return nil, 0;  -- Not found (ability may be ready or not tracked)
end

-- Get ability recast by ability ID (scans slots to find it)
-- Returns: remaining recast time in seconds, or 0 if ready/not found
-- @param abilityId: The ability ID (not timer ID)
function M.GetAbilityRecastByAbilityId(abilityId)
    local timerId, rawTimer = M.FindAbilityRecast(abilityId);
    if rawTimer <= 0 then return 0; end
    return rawTimer / 60;
end

return M;
