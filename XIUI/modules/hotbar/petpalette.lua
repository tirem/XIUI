--[[
* XIUI Hotbar - Pet Palette Module
* Manages pet-aware palette state and detection.
* Hotbar and crossbar share the same core logic via props (state table selection).
]]--

require('common');
require('handlers.helpers');
local petregistry = require('modules.hotbar.petregistry');

local M = {};

-- ============================================
-- State
-- ============================================

local state = {
    currentPetKey = nil,
    lastKnownPetName = nil,

    -- Hotbar: keyed by barIndex
    hotbar = { overrides = {}, cycleIndices = {} },
    -- Crossbar: keyed by comboMode
    crossbar = { overrides = {}, cycleIndices = {} },

    onPetChangedCallbacks = {},
};

-- ============================================
-- Pet Detection
-- ============================================

local function GetPetEntity()
    local playerEntity = GetPlayerEntity();
    if playerEntity == nil or playerEntity.PetTargetIndex == 0 then
        return nil;
    end
    return GetEntity(playerEntity.PetTargetIndex);
end

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

function M.CheckPetState()
    local petEntity = GetPetEntity();
    local petJob = GetPetJob();

    local newPetKey = nil;
    local newPetName = nil;

    if petEntity and petEntity.Name and petEntity.Name ~= '' then
        newPetName = petEntity.Name;
        newPetKey = petregistry.GetPetKey(newPetName, petJob);
    end

    if newPetName ~= state.lastKnownPetName then
        local oldPetKey = state.currentPetKey;
        state.lastKnownPetName = newPetName;
        state.currentPetKey = newPetKey;

        M.FirePetChangedCallbacks(oldPetKey, newPetKey);
        M.ClearAllManualOverrides();
    end

    return newPetKey;
end

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

function M.GetCurrentPetKey()
    return state.currentPetKey;
end

function M.GetCurrentPetDisplayName()
    return petregistry.GetDisplayNameForKey(state.currentPetKey);
end

function M.GetCurrentPetEntityName()
    return state.lastKnownPetName;
end

function M.HasPet()
    return state.currentPetKey ~= nil;
end

-- ============================================
-- Shared Core (props-driven)
-- Callers pass a context table: state.hotbar or state.crossbar
-- and a key (barIndex for hotbar, comboMode for crossbar).
-- ============================================

local function getOverride(ctx, key)
    return ctx.overrides[key];
end

local function hasOverride(ctx, key)
    return ctx.overrides[key] ~= nil;
end

local function setOverride(ctx, key, petKey)
    ctx.overrides[key] = petKey;
end

local function clearOverride(ctx, key)
    ctx.overrides[key] = nil;
    ctx.cycleIndices[key] = nil;
end

local function clearAllOverrides(ctx)
    ctx.overrides = {};
    ctx.cycleIndices = {};
end

function M.GetAvailablePalettes(barIndex, jobId, subjobId)
    local palettes = {};

    table.insert(palettes, {
        key = nil,
        displayName = 'Base',
    });

    local petKeys = petregistry.GetAvailablePetKeys(jobId);
    for _, petKey in ipairs(petKeys) do
        table.insert(palettes, {
            key = petKey,
            displayName = petregistry.GetDisplayNameForKey(petKey),
        });
    end

    return palettes;
end

local function setPalette(ctx, key, petKey)
    if petKey == nil then
        ctx.overrides[key] = nil;
        ctx.cycleIndices[key] = nil;
    else
        ctx.overrides[key] = petKey;
    end
    return true;
end

local function cyclePalette(ctx, key, direction, jobId)
    direction = direction or 1;
    jobId = jobId or GetPetJob();
    if not jobId then return; end

    local palettes = M.GetAvailablePalettes(1, jobId);
    if #palettes == 0 then return; end

    local currentIndex = ctx.cycleIndices[key] or 1;

    local currentOverride = ctx.overrides[key];
    if currentOverride then
        for i, p in ipairs(palettes) do
            if p.key == currentOverride then
                currentIndex = i;
                break;
            end
        end
    elseif state.currentPetKey then
        for i, p in ipairs(palettes) do
            if p.key == state.currentPetKey then
                currentIndex = i;
                break;
            end
        end
    end

    local newIndex = currentIndex + direction;
    if newIndex < 1 then newIndex = #palettes; end
    if newIndex > #palettes then newIndex = 1; end

    ctx.cycleIndices[key] = newIndex;
    ctx.overrides[key] = palettes[newIndex].key;

    return palettes[newIndex];
end

local function getEffectivePetKey(ctx, key)
    local override = ctx.overrides[key];
    if override then return override; end
    return state.currentPetKey;
end

local function getPaletteDisplayName(ctx, key)
    local override = ctx.overrides[key];
    if override then
        return petregistry.GetDisplayNameForKey(override);
    end
    if state.currentPetKey then
        return petregistry.GetDisplayNameForKey(state.currentPetKey);
    end
    return 'Base';
end

-- ============================================
-- Hotbar Public API (barIndex keyed)
-- ============================================

function M.GetManualOverride(barIndex)
    return getOverride(state.hotbar, barIndex);
end

function M.HasManualOverride(barIndex)
    return hasOverride(state.hotbar, barIndex);
end

function M.SetManualOverride(barIndex, petKey)
    setOverride(state.hotbar, barIndex, petKey);
end

function M.ClearManualOverride(barIndex)
    clearOverride(state.hotbar, barIndex);
end

function M.SetPalette(barIndex, petKey)
    return setPalette(state.hotbar, barIndex, petKey);
end

function M.CyclePalette(barIndex, direction, jobId)
    return cyclePalette(state.hotbar, barIndex, direction, jobId);
end

function M.GetEffectivePetKey(barIndex)
    return getEffectivePetKey(state.hotbar, barIndex);
end

function M.GetPaletteDisplayName(barIndex, jobId)
    return getPaletteDisplayName(state.hotbar, barIndex);
end

-- ============================================
-- Crossbar Public API (comboMode keyed)
-- ============================================

function M.GetCrossbarOverride(comboMode)
    return getOverride(state.crossbar, comboMode);
end

function M.HasCrossbarOverride(comboMode)
    return hasOverride(state.crossbar, comboMode);
end

function M.SetCrossbarOverride(comboMode, petKey)
    setOverride(state.crossbar, comboMode, petKey);
end

function M.ClearCrossbarOverride(comboMode)
    clearOverride(state.crossbar, comboMode);
end

function M.ClearAllCrossbarOverrides()
    clearAllOverrides(state.crossbar);
end

function M.SetCrossbarPalette(comboMode, petKey)
    return setPalette(state.crossbar, comboMode, petKey);
end

function M.CycleCrossbarPalette(comboMode, direction, jobId)
    return cyclePalette(state.crossbar, comboMode, direction, jobId);
end

function M.GetEffectivePetKeyForCombo(comboMode)
    return getEffectivePetKey(state.crossbar, comboMode);
end

function M.GetCrossbarPaletteDisplayName(comboMode, jobId)
    return getPaletteDisplayName(state.crossbar, comboMode);
end

-- ============================================
-- Bulk Clear (clears both hotbar and crossbar)
-- ============================================

function M.ClearAllManualOverrides()
    clearAllOverrides(state.hotbar);
    clearAllOverrides(state.crossbar);
end

-- ============================================
-- Callback System
-- ============================================

function M.OnPetChanged(callback)
    if callback then
        table.insert(state.onPetChangedCallbacks, callback);
    end
end

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
    clearAllOverrides(state.hotbar);
    clearAllOverrides(state.crossbar);
end

return M;
