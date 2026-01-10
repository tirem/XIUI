--[[
* XIUI Target Utilities
* Target detection and sub-target handling
]]--

local M = {};

-- ========================================
-- ST (Sub-Target) Party Index
-- ========================================

function M.GetStPartyIndex()
    local ptr = AshitaCore:GetPointerManager():Get('party');
    if ptr == nil or ptr == 0 then
        return nil;
    end
    ptr = ashita.memory.read_uint32(ptr);
    if ptr == 0 then
        return nil;
    end
    ptr = ashita.memory.read_uint32(ptr);
    if ptr == 0 then
        return nil;
    end
    local isActive = (ashita.memory.read_uint32(ptr + 0x54) ~= 0);
    if isActive then
        return ashita.memory.read_uint8(ptr + 0x50);
    else
        return nil;
    end
end

-- ========================================
-- Sub-Target Detection
-- ========================================

function M.GetSubTargetActive()
    local playerTarget = AshitaCore:GetMemoryManager():GetTarget();
    if (playerTarget == nil) then
        return false;
    end

    -- Primary check: Ashita API reports sub-target is active
    if playerTarget:GetIsSubTargetActive() == 1 then
        return true;
    end

    -- Check if party sub-target selection is active (<stal>/<stpt>)
    if M.GetStPartyIndex() ~= nil then
        return true;
    end

    -- Fallback: Check if there's a valid entity in sub-target slot (index 1)
    -- that differs from main target - indicates sub-targeting even if API doesn't report it
    local mainTarget = playerTarget:GetTargetIndex(0);
    local subTarget = playerTarget:GetTargetIndex(1);
    if mainTarget ~= 0 and subTarget ~= 0 and subTarget ~= mainTarget then
        return true;
    end

    return false;
end

-- ========================================
-- Target Retrieval
-- ========================================

-- Returns mainTarget, secondaryTarget indices
-- When sub-targeting, mainTarget is the sub-target (party member) and secondaryTarget is the original target
function M.GetTargets()
    local playerTarget = AshitaCore:GetMemoryManager():GetTarget();
    local party = AshitaCore:GetMemoryManager():GetParty();

    if (playerTarget == nil or party == nil) then
        return nil, nil;
    end

    local mainTarget = playerTarget:GetTargetIndex(0);
    local secondaryTarget = playerTarget:GetTargetIndex(1);
    local partyTarget = M.GetStPartyIndex();

    -- If party sub-target selection is active (<stal>/<stpt>), swap to put party member first
    if (partyTarget ~= nil) then
        secondaryTarget = mainTarget;
        mainTarget = party:GetMemberTargetIndex(partyTarget);
    -- Otherwise, if sub-targeting is active via Ashita API and we have both targets,
    -- swap them so the sub-target (slot 1) becomes the "main" for highlighting purposes
    elseif playerTarget:GetIsSubTargetActive() == 1 and secondaryTarget ~= 0 then
        local temp = mainTarget;
        mainTarget = secondaryTarget;
        secondaryTarget = temp;
    end

    return mainTarget, secondaryTarget;
end

-- ========================================
-- Lock-On Detection
-- ========================================

function M.GetIsTargetLockedOn()
    local playerTarget = AshitaCore:GetMemoryManager():GetTarget();
    if (playerTarget == nil) then
        return false;
    end

    -- Primary: Use GetIsLockedOn which returns 1 if locked on, 0 otherwise
    -- This is the cleaner API that directly returns lock state
    if (playerTarget.GetIsLockedOn ~= nil) then
        return playerTarget:GetIsLockedOn() == 1;
    end

    -- Fallback: Use GetLockedOnFlags and check the low bit (0x01)
    -- LockedOnFlags uses bit 0 to indicate lock status per SDK docs
    if (playerTarget.GetLockedOnFlags ~= nil) then
        local flags = playerTarget:GetLockedOnFlags();
        return bit.band(flags, 0x01) == 0x01;
    end

    -- Method not available
    return false;
end

return M;
