--[[
* XIUI Hotbar - Pet Palette Module
* Manages pet-aware palette state and detection
]]--

require('common');
require('handlers.helpers');
local petregistry = require('modules.hotbar.petregistry');

local M = {};

-- ============================================
-- State
-- ============================================

local state = {
    -- Current detected pet key (e.g., "avatar:ifrit", "wyvern", nil)
    currentPetKey = nil,

    -- Last known pet name (for change detection)
    lastKnownPetName = nil,

    -- Manual overrides per bar: [barIndex] = petKey or nil
    manualOverrides = {},

    -- Cycle indices per bar: [barIndex] = index into available palettes
    cycleIndices = {},

    -- Crossbar overrides per combo mode: [comboMode] = petKey or nil
    crossbarOverrides = {},

    -- Crossbar cycle indices per combo mode: [comboMode] = index into available palettes
    crossbarCycleIndices = {},

    -- Callbacks for pet change events
    onPetChangedCallbacks = {},
};

-- ============================================
-- Pet Detection
-- ============================================

-- Get the current pet entity from the player
local function GetPetEntity()
    local playerEntity = GetPlayerEntity();
    if playerEntity == nil or playerEntity.PetTargetIndex == 0 then
        return nil;
    end
    return GetEntity(playerEntity.PetTargetIndex);
end

-- Get the primary pet job (main takes precedence)
local function GetPetJob()
    local player = GetPlayerSafe();
    if player == nil then return nil; end

    local mainJob = player:GetMainJob();
    local subJob = player:GetSubJob();

    if petregistry.IsPetJob(mainJob) then
        return mainJob;
    elseif petregistry.IsPetJob(subJob) then
        return subJob;
    end

    return nil;
end

-- Check current pet state and update if changed
-- Called on packet hints (0x0068 Pet Sync, 0x000B Zone)
function M.CheckPetState()
    local petEntity = GetPetEntity();
    local petJob = GetPetJob();

    local newPetKey = nil;
    local newPetName = nil;

    if petEntity and petEntity.Name and petEntity.Name ~= '' then
        newPetName = petEntity.Name;
        newPetKey = petregistry.GetPetKey(newPetName, petJob);
    end

    -- Check if pet changed
    if newPetName ~= state.lastKnownPetName then
        local oldPetKey = state.currentPetKey;
        state.lastKnownPetName = newPetName;
        state.currentPetKey = newPetKey;

        -- Fire callbacks
        M.FirePetChangedCallbacks(oldPetKey, newPetKey);

        -- Always clear manual overrides when pet changes (auto-switch behavior)
        M.ClearAllManualOverrides();
    end

    return newPetKey;
end

-- Force clear pet state (for zone changes)
function M.ClearPetState()
    local oldPetKey = state.currentPetKey;
    state.lastKnownPetName = nil;
    state.currentPetKey = nil;

    if oldPetKey then
        M.FirePetChangedCallbacks(oldPetKey, nil);
    end
end

-- ============================================
-- Pet Key Access
-- ============================================

-- Get the current auto-detected pet key
function M.GetCurrentPetKey()
    return state.currentPetKey;
end

-- Get the current pet display name
function M.GetCurrentPetDisplayName()
    return petregistry.GetDisplayNameForKey(state.currentPetKey);
end

-- Get the current pet entity name (e.g., "HareFamiliar", "Ifrit")
function M.GetCurrentPetEntityName()
    return state.lastKnownPetName;
end

-- Check if player currently has a pet
function M.HasPet()
    return state.currentPetKey ~= nil;
end

-- ============================================
-- Manual Override Management
-- ============================================

-- Get manual override for a bar (returns petKey or nil)
function M.GetManualOverride(barIndex)
    return state.manualOverrides[barIndex];
end

-- Check if a bar has a manual override
function M.HasManualOverride(barIndex)
    return state.manualOverrides[barIndex] ~= nil;
end

-- Set manual override for a bar
function M.SetManualOverride(barIndex, petKey)
    state.manualOverrides[barIndex] = petKey;
end

-- Clear manual override for a bar (return to auto mode)
function M.ClearManualOverride(barIndex)
    state.manualOverrides[barIndex] = nil;
    state.cycleIndices[barIndex] = nil;
end

-- Clear all manual overrides (including crossbar)
function M.ClearAllManualOverrides()
    state.manualOverrides = {};
    state.cycleIndices = {};
    state.crossbarOverrides = {};
    state.crossbarCycleIndices = {};
end

-- ============================================
-- Palette Cycling
-- ============================================

-- Get available palettes for a bar (includes base job + all pet palettes)
-- Returns: { { key = storageKey, displayName = "Name" }, ... }
-- Note: subjobId parameter is accepted but not used (pet keys don't depend on subjob)
function M.GetAvailablePalettes(barIndex, jobId, subjobId)
    local palettes = {};

    -- Always include base job palette first
    table.insert(palettes, {
        key = nil,  -- nil means base job (no pet key)
        displayName = 'Base',
    });

    -- Add pet-specific palettes based on job
    local petKeys = petregistry.GetAvailablePetKeys(jobId);
    for _, petKey in ipairs(petKeys) do
        table.insert(palettes, {
            key = petKey,
            displayName = petregistry.GetDisplayNameForKey(petKey),
        });
    end

    return palettes;
end

-- Set a specific palette for a bar (by pet key)
-- petKey: The pet key to set (e.g., 'avatar:ifrit', 'spirit:fire'), or nil for Auto
function M.SetPalette(barIndex, petKey)
    if petKey == nil then
        -- Clear override (Auto mode)
        state.manualOverrides[barIndex] = nil;
        state.cycleIndices[barIndex] = nil;
    else
        state.manualOverrides[barIndex] = petKey;
    end
    return true;
end

-- Cycle through palettes for a bar
-- direction: 1 for next, -1 for previous
function M.CyclePalette(barIndex, direction, jobId)
    direction = direction or 1;
    jobId = jobId or GetPetJob();

    if not jobId then return; end

    local palettes = M.GetAvailablePalettes(barIndex, jobId);
    if #palettes == 0 then return; end

    -- Get current cycle index
    local currentIndex = state.cycleIndices[barIndex] or 1;

    -- If we have a manual override, find its index
    local currentOverride = state.manualOverrides[barIndex];
    if currentOverride then
        for i, p in ipairs(palettes) do
            if p.key == currentOverride then
                currentIndex = i;
                break;
            end
        end
    elseif state.currentPetKey then
        -- If no override but we have a pet, find auto-selected index
        for i, p in ipairs(palettes) do
            if p.key == state.currentPetKey then
                currentIndex = i;
                break;
            end
        end
    end

    -- Calculate new index
    local newIndex = currentIndex + direction;
    if newIndex < 1 then newIndex = #palettes; end
    if newIndex > #palettes then newIndex = 1; end

    -- Store cycle index and set override
    state.cycleIndices[barIndex] = newIndex;
    state.manualOverrides[barIndex] = palettes[newIndex].key;

    return palettes[newIndex];
end

-- ============================================
-- Crossbar Override Management
-- ============================================

-- Get crossbar manual override for a combo mode (returns petKey or nil)
function M.GetCrossbarOverride(comboMode)
    return state.crossbarOverrides[comboMode];
end

-- Check if a combo mode has a manual override
function M.HasCrossbarOverride(comboMode)
    return state.crossbarOverrides[comboMode] ~= nil;
end

-- Set manual override for a crossbar combo mode
function M.SetCrossbarOverride(comboMode, petKey)
    state.crossbarOverrides[comboMode] = petKey;
end

-- Clear manual override for a crossbar combo mode (return to auto mode)
function M.ClearCrossbarOverride(comboMode)
    state.crossbarOverrides[comboMode] = nil;
    state.crossbarCycleIndices[comboMode] = nil;
end

-- Clear all crossbar overrides only
function M.ClearAllCrossbarOverrides()
    state.crossbarOverrides = {};
    state.crossbarCycleIndices = {};
end

-- Set a specific palette for a crossbar combo mode (by pet key)
-- petKey: The pet key to set (e.g., 'avatar:ifrit'), or nil for Auto
function M.SetCrossbarPalette(comboMode, petKey)
    if petKey == nil then
        -- Clear override (Auto mode)
        state.crossbarOverrides[comboMode] = nil;
        state.crossbarCycleIndices[comboMode] = nil;
    else
        state.crossbarOverrides[comboMode] = petKey;
    end
    return true;
end

-- Cycle through palettes for a crossbar combo mode
-- direction: 1 for next, -1 for previous
function M.CycleCrossbarPalette(comboMode, direction, jobId)
    direction = direction or 1;
    jobId = jobId or GetPetJob();

    if not jobId then return; end

    -- Reuse same palette list as hotbar (palettes are job-based, not bar-based)
    local palettes = M.GetAvailablePalettes(1, jobId);
    if #palettes == 0 then return; end

    -- Get current cycle index
    local currentIndex = state.crossbarCycleIndices[comboMode] or 1;

    -- If we have a manual override, find its index
    local currentOverride = state.crossbarOverrides[comboMode];
    if currentOverride then
        for i, p in ipairs(palettes) do
            if p.key == currentOverride then
                currentIndex = i;
                break;
            end
        end
    elseif state.currentPetKey then
        -- If no override but we have a pet, find auto-selected index
        for i, p in ipairs(palettes) do
            if p.key == state.currentPetKey then
                currentIndex = i;
                break;
            end
        end
    end

    -- Calculate new index
    local newIndex = currentIndex + direction;
    if newIndex < 1 then newIndex = #palettes; end
    if newIndex > #palettes then newIndex = 1; end

    -- Store cycle index and set override
    state.crossbarCycleIndices[comboMode] = newIndex;
    state.crossbarOverrides[comboMode] = palettes[newIndex].key;

    return palettes[newIndex];
end

-- Get the effective pet key for a crossbar combo mode (considering overrides)
-- This is what data.lua will use to build the storage key
function M.GetEffectivePetKeyForCombo(comboMode)
    -- Check manual override first
    local override = state.crossbarOverrides[comboMode];
    if override then
        return override;
    end

    -- No override - use auto-detected pet
    return state.currentPetKey;
end

-- Get the current pet palette display name for a crossbar combo mode
-- Returns the name to show in the palette indicator overlay
function M.GetCrossbarPaletteDisplayName(comboMode, jobId)
    -- Check manual override first
    local override = state.crossbarOverrides[comboMode];
    if override then
        return petregistry.GetDisplayNameForKey(override);
    end

    -- No override - use auto-detected pet
    if state.currentPetKey then
        return petregistry.GetDisplayNameForKey(state.currentPetKey);
    end

    return 'Base';
end

-- ============================================
-- Palette Display Name for Indicator
-- ============================================

-- Get the current palette display name for a bar
-- Returns the name to show in the palette indicator overlay
function M.GetPaletteDisplayName(barIndex, jobId)
    -- Check manual override first
    local override = state.manualOverrides[barIndex];
    if override then
        return petregistry.GetDisplayNameForKey(override);
    end

    -- No override - use auto-detected pet
    if state.currentPetKey then
        return petregistry.GetDisplayNameForKey(state.currentPetKey);
    end

    return 'Base';
end

-- ============================================
-- Effective Storage Key Resolution
-- ============================================

-- Get the effective pet key for a bar (considering overrides)
-- This is what data.lua will use to build the storage key
function M.GetEffectivePetKey(barIndex)
    -- Check manual override first
    local override = state.manualOverrides[barIndex];
    if override then
        return override;
    end

    -- No override - use auto-detected pet
    return state.currentPetKey;
end

-- ============================================
-- Callback System
-- ============================================

-- Register a callback for pet changes
-- callback(oldPetKey, newPetKey)
function M.OnPetChanged(callback)
    if callback then
        table.insert(state.onPetChangedCallbacks, callback);
    end
end

-- Fire all pet changed callbacks
function M.FirePetChangedCallbacks(oldPetKey, newPetKey)
    for _, callback in ipairs(state.onPetChangedCallbacks) do
        local success, err = pcall(callback, oldPetKey, newPetKey);
        if not success then
            print('[XIUI petpalette] Callback error: ' .. tostring(err));
        end
    end
end

-- ============================================
-- State Reset
-- ============================================

function M.Reset()
    state.currentPetKey = nil;
    state.lastKnownPetName = nil;
    state.manualOverrides = {};
    state.cycleIndices = {};
    state.crossbarOverrides = {};
    state.crossbarCycleIndices = {};
end

return M;
