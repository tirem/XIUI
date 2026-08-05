--[[
* XIUI Ability Recast Library
* Provides direct memory reading for ability recast timers
* Shared by petbar and castcost modules
*
* This uses the same memory reading approach as PetMe addon for reliable
* recast tracking of pet commands and job abilities.
]]--

local abilityRecastIds = require('libs.abilityrecastids');

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

-- Find timer ID for an ability and read its current recast.
-- Returns: timerId, currentRecast (raw 1/60th seconds), or nil if not found
-- @param abilityId: The ability ID to find (as this server's resource manager knows it)
function M.FindAbilityRecast(abilityId)
    if abilityId == nil then return nil, 0; end
    if not InitAbilityRecastPointer() then
        return nil, 0;
    end

    local resourceMgr = AshitaCore:GetResourceManager();

    -- Preferred path: resolve THIS ability's name via this server's own
    -- resource manager (so it's correct no matter what numeric ID this
    -- particular server happens to assign), then look up its real
    -- recast/timer ID by name. Many abilities SHARE one timer with other,
    -- differently-named abilities (all DNC Steps share timer 220, Flourish I
    -- abilities share 221, Sic and Ready are on separate BST timers despite
    -- looking related, etc). Resolving by name sidesteps that entirely,
    -- unlike resolving a timer ID back to "the" ability via
    -- GetAbilityByTimerId, which can only ever return one canonical ability
    -- per timer.
    local ability = resourceMgr:GetAbilityById(abilityId);
    local knownTimerId = nil;
    if ability and ability.Name and ability.Name[1] then
        knownTimerId = abilityRecastIds.abilityNameToRecastId[ability.Name[1]:lower()];
    end

    if knownTimerId ~= nil and knownTimerId > 0 then
        for i = 0, 31 do
            local slotTimerId = ashita.memory.read_uint8(AbilityRecastPointer + (i * 8) + 3);
            if slotTimerId == knownTimerId then
                local recast = ashita.memory.read_uint32(AbilityRecastPointer + (i * 4) + 0xF8);
                return slotTimerId, recast;
            end
        end
        return knownTimerId, 0; -- Known timer, but not currently on cooldown
    end

    -- Fallback: reverse-lookup scan, for any ability not covered by the table
    -- (e.g. brand new content the table hasn't been updated for yet).
    for i = 0, 31 do
        local slotTimerId = ashita.memory.read_uint8(AbilityRecastPointer + (i * 8) + 3);

        -- Skip empty slots (timer ID 0, except slot 0 which is 2-hour)
        if slotTimerId > 0 or i == 0 then
            local slotAbility = resourceMgr:GetAbilityByTimerId(slotTimerId);
            if slotAbility and slotAbility.Id == abilityId then
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

-- Scan ALL recast slots and return every ability currently on cooldown.
-- Unlike FindAbilityRecast, this doesn't require knowing the ability ID in
-- advance - it reads whatever the game currently has active in the recast
-- slots and resolves each one back to its ability resource.
-- Returns: array of { timerId, abilityId, currentRecast (seconds), recastDelay (raw, 1/4 sec units) }
function M.GetAllActiveRecasts()
    local results = {};
    if not InitAbilityRecastPointer() then
        return results;
    end

    local resourceMgr = AshitaCore:GetResourceManager();

    for i = 0, 31 do
        local slotTimerId = ashita.memory.read_uint8(AbilityRecastPointer + (i * 8) + 3);
        local rawRecast = ashita.memory.read_uint32(AbilityRecastPointer + (i * 4) + 0xF8);

        if slotTimerId > 0 and rawRecast > 0 then
            local ability = resourceMgr:GetAbilityByTimerId(slotTimerId);
            if ability then
                table.insert(results, {
                    timerId = slotTimerId,
                    abilityId = ability.Id,
                    currentRecast = rawRecast / 60,
                    recastDelay = ability.RecastDelay or 0,
                });
            end
        end
    end

    return results;
end

return M;
