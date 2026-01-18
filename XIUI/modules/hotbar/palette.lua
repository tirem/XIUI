--[[
* XIUI Hotbar - General Palette Module
* Manages user-defined named palettes for hotbars
* Works alongside petpalette.lua (pet palettes take precedence when petAware is enabled)
*
* GLOBAL PALETTE SYSTEM (v3):
* - All hotbars share ONE global palette (not per-bar)
* - Crossbar has its own single palette (not per-combo-mode)
* - Storage key format: '{jobId}:palette:{name}' (no subjob - palettes are job-wide)
* - Every job always has at least one palette (auto-created if none exist)
* - NO special "Base" palette - the first palette IS the default
* - All palettes are equal: renamable, reorderable, deletable (except can't delete last one)
*
* This matches tHotBar/tCrossBar behavior: one palette switch changes everything.
]]--

require('common');
require('handlers.helpers');

local M = {};

-- ============================================
-- Constants
-- ============================================

M.DEFAULT_PALETTE_NAME = 'Default';  -- Name for auto-created palettes
M.PALETTE_KEY_PREFIX = 'palette:';

-- ============================================
-- State
-- ============================================

local state = {
    -- GLOBAL active palette for ALL hotbars
    -- NOTE: For hotbars, this should always be set (EnsureDefaultPaletteExists handles this)
    activePalette = nil,

    -- Single active palette for crossbar (nil = use default slots)
    -- NOTE: Crossbar can have 0 palettes and use default slots
    crossbarActivePalette = nil,

    -- Callbacks for palette change events
    onPaletteChangedCallbacks = {},
};

-- ============================================
-- Config Structure Helpers
-- ============================================

-- Helper: Ensure gConfig.hotbar structure exists
local function EnsureHotbarConfigExists()
    if not gConfig then return false; end
    if not gConfig.hotbar then
        gConfig.hotbar = {};
    end
    if not gConfig.hotbar.paletteOrder then
        gConfig.hotbar.paletteOrder = {};
    end
    return true;
end

-- Save active palette state to config (for persistence across reloads)
-- Called when palette changes to remember last-used palette per job
local function SavePaletteState(jobId)
    if not EnsureHotbarConfigExists() then return; end
    if not gConfig.hotbar.activePalettePerJob then
        gConfig.hotbar.activePalettePerJob = {};
    end
    gConfig.hotbar.activePalettePerJob[jobId] = state.activePalette;
    -- Note: Don't call SaveSettingsToDisk() here - it will be called by the caller if needed
end

-- Load active palette state from config (for persistence across reloads)
local function LoadPaletteState(jobId)
    if not gConfig or not gConfig.hotbar or not gConfig.hotbar.activePalettePerJob then
        return nil;
    end
    return gConfig.hotbar.activePalettePerJob[jobId];
end

-- ============================================
-- Palette Name Validation
-- ============================================

-- Validate palette name (no colons, reasonable length)
local function IsValidPaletteName(name)
    if not name or type(name) ~= 'string' then return false; end
    if name == '' or name:len() > 32 then return false; end
    if name:find(':') then return false; end  -- Colons used in storage keys
    return true;
end

-- ============================================
-- Palette Key Generation
-- ============================================

-- Build storage key suffix for a palette name
-- Returns nil if no palette name (uses base job:subjob key)
function M.GetPaletteKeySuffix(paletteName)
    if not paletteName then
        return nil;
    end
    return M.PALETTE_KEY_PREFIX .. paletteName;
end

-- Build full storage key for a palette (NEW FORMAT: job-only, no subjob)
-- jobId: The main job ID (number)
-- paletteName: palette name or nil for base key
-- Returns: '{jobId}:palette:{name}' for palettes, or just jobId as string for base
function M.BuildPaletteStorageKey(jobId, paletteName)
    local normalizedJobId = jobId or 1;
    if not paletteName then
        return tostring(normalizedJobId);
    end
    return string.format('%d:%s%s', normalizedJobId, M.PALETTE_KEY_PREFIX, paletteName);
end

-- DEPRECATED: Old format - kept for backwards compatibility during migration
-- Build full storage key for a palette using old format (includes subjob)
-- baseKey: '{jobId}:{subjobId}' format
-- paletteName: palette name or nil for default slot data
function M.BuildStorageKey(baseKey, paletteName)
    local suffix = M.GetPaletteKeySuffix(paletteName);
    if not suffix then
        return baseKey;
    end
    return string.format('%s:%s', baseKey, suffix);
end

-- Parse a storage key to extract palette name
-- Returns nil if no palette suffix (default slots)
function M.ParsePaletteFromKey(storageKey)
    if not storageKey or type(storageKey) ~= 'string' then return nil; end

    -- Look for :palette: in the key
    local paletteStart = storageKey:find(':' .. M.PALETTE_KEY_PREFIX);
    if not paletteStart then return nil; end

    -- Extract everything after :palette:
    local paletteName = storageKey:sub(paletteStart + 1 + #M.PALETTE_KEY_PREFIX);
    if paletteName == '' then return nil; end

    return paletteName;
end

-- ============================================
-- Active Palette Management (GLOBAL - all hotbars share one palette)
-- ============================================

-- Get active palette name (GLOBAL - same for all bars)
-- barIndex param kept for backwards compatibility but ignored
function M.GetActivePalette(barIndex)
    return state.activePalette;
end

-- Get active palette display name (GLOBAL)
-- barIndex param kept for backwards compatibility but ignored
-- Returns nil if no palette is active
function M.GetActivePaletteDisplayName(barIndex)
    return state.activePalette;
end

-- Set active palette (GLOBAL - affects all hotbars)
-- barIndex param kept for backwards compatibility but ignored
-- paletteName: name to activate, or nil to clear
-- jobId: optional job ID for persistence (saves which palette was last used for this job)
function M.SetActivePalette(barIndex, paletteName, jobId)
    local oldPalette = state.activePalette;

    -- Skip if no change
    if oldPalette == paletteName then
        return false;
    end

    state.activePalette = paletteName;

    -- Save state for persistence if jobId provided
    if jobId then
        SavePaletteState(jobId);
    end

    -- Fire callbacks for ALL bars (they all share the same palette now)
    for i = 1, 6 do
        M.FirePaletteChangedCallbacks(i, oldPalette, paletteName);
    end

    return true;
end

-- Clear active palette (uses default slot data)
-- barIndex param kept for backwards compatibility but ignored
function M.ClearActivePalette(barIndex)
    return M.SetActivePalette(barIndex, nil);
end

-- Clear all active palettes (just clears the single global palette)
function M.ClearAllActivePalettes()
    if state.activePalette then
        return M.ClearActivePalette(1);
    end
    return false;
end

-- ============================================
-- Available Palettes Discovery (GLOBAL - scans all bars)
-- ============================================

-- Get list of available palette names for ALL hotbars (GLOBAL)
-- Uses NEW FORMAT only: Palettes are stored with job-only keys: '{jobId}:palette:{name}'
-- barIndex param kept for backwards compatibility but all bars are scanned
-- subjobId param kept for backwards compatibility but ignored (palettes are job-wide)
-- Returns: { 'Stuns', 'Heals', ... } (empty if no palettes defined)
function M.GetAvailablePalettes(barIndex, jobId, subjobId)
    local normalizedJobId = jobId or 1;

    -- Collect palettes from ALL hotbars (they share the same palette pool)
    local existingPalettes = {};

    -- NEW format pattern: '{jobId}:palette:{name}'
    local newFormatPattern = string.format('%d:%s', normalizedJobId, M.PALETTE_KEY_PREFIX);

    for barIdx = 1, 6 do
        local configKey = 'hotbarBar' .. barIdx;
        local barSettings = gConfig and gConfig[configKey];
        if barSettings and barSettings.slotActions then
            for storageKey, _ in pairs(barSettings.slotActions) do
                if type(storageKey) == 'string' then
                    -- Check NEW format only: '{jobId}:palette:{name}'
                    if storageKey:find(newFormatPattern, 1, true) == 1 then
                        local paletteName = storageKey:sub(#newFormatPattern + 1);
                        if paletteName and paletteName ~= '' then
                            existingPalettes[paletteName] = true;
                        end
                    end
                end
            end
        end
    end

    -- Get the stored palette order (GLOBAL: stored at hotbar level, keyed by jobId only)
    local storedOrder = gConfig and gConfig.hotbar and gConfig.hotbar.paletteOrder
                        and gConfig.hotbar.paletteOrder[normalizedJobId];

    -- Build ordered result: first add palettes from storedOrder that exist
    local palettes = {};
    local seen = {};
    if storedOrder then
        for _, paletteName in ipairs(storedOrder) do
            if existingPalettes[paletteName] and not seen[paletteName] then
                seen[paletteName] = true;
                table.insert(palettes, paletteName);
            end
        end
    end

    -- Collect any remaining palettes not in the stored order
    local remaining = {};
    for paletteName, _ in pairs(existingPalettes) do
        if not seen[paletteName] then
            table.insert(remaining, paletteName);
        end
    end

    -- Sort remaining palettes alphabetically and append
    table.sort(remaining);
    for _, paletteName in ipairs(remaining) do
        table.insert(palettes, paletteName);
    end

    return palettes;
end

-- Check if a specific palette exists for a bar
function M.PaletteExists(barIndex, paletteName, jobId, subjobId)
    if not paletteName then
        return false;
    end

    local available = M.GetAvailablePalettes(barIndex, jobId, subjobId);
    for _, name in ipairs(available) do
        if name == paletteName then
            return true;
        end
    end
    return false;
end

-- ============================================
-- Palette Cycling (GLOBAL)
-- ============================================

-- Cycle through palettes (GLOBAL - affects all hotbars)
-- barIndex param kept for backwards compatibility but ignored (all bars share one palette)
-- subjobId param kept for backwards compatibility but ignored (palettes are job-wide)
-- direction: 1 for next, -1 for previous
-- NOTE: Only cycles through existing palettes - no "Base" option
function M.CyclePalette(barIndex, direction, jobId, subjobId)
    direction = direction or 1;

    local palettes = M.GetAvailablePalettes(barIndex, jobId, subjobId);
    if #palettes <= 1 then
        return nil;  -- No palettes to cycle (0 or 1 palette)
    end

    local currentName = state.activePalette;
    local currentIndex = 1;  -- Default to first palette

    -- Find current palette index
    if currentName then
        for i, name in ipairs(palettes) do
            if name == currentName then
                currentIndex = i;
                break;
            end
        end
    end

    -- Calculate new index with wrap-around (1..#palettes)
    local newIndex = currentIndex + direction;
    if newIndex < 1 then newIndex = #palettes; end
    if newIndex > #palettes then newIndex = 1; end

    local newPalette = palettes[newIndex];
    M.SetActivePalette(barIndex, newPalette, jobId);  -- Pass jobId for persistence

    return newPalette;
end

-- ============================================
-- Palette CRUD Operations
-- ============================================

-- Helper: Find the actual storage key for a palette
-- Uses NEW format only: '{jobId}:palette:{name}' (job-wide, no subjob)
-- Returns storageKey or nil if not found
local function FindPaletteStorageKey(barIndex, paletteName, jobId, subjobId)
    local configKey = 'hotbarBar' .. barIndex;
    local barSettings = gConfig and gConfig[configKey];
    if not barSettings or not barSettings.slotActions then
        return nil;
    end

    local normalizedJobId = jobId or 1;

    -- Use NEW format only: '{jobId}:palette:{name}' (job-wide, no subjob)
    local storageKey = M.BuildPaletteStorageKey(normalizedJobId, paletteName);
    if barSettings.slotActions[storageKey] then
        return storageKey;
    end

    return nil;
end

-- Create a new palette (GLOBAL - creates empty palette entries on all bars)
-- Uses NEW key format: '{jobId}:palette:{name}' (no subjob)
-- barIndex param kept for backwards compatibility
-- subjobId param kept for backwards compatibility but ignored
-- Returns true on success, false with error message on failure
function M.CreatePalette(barIndex, paletteName, jobId, subjobId)
    if not IsValidPaletteName(paletteName) then
        return false, 'Invalid palette name';
    end

    local normalizedJobId = jobId or 1;

    -- Build new format storage key: '{jobId}:palette:{name}'
    local newStorageKey = M.BuildPaletteStorageKey(normalizedJobId, paletteName);

    -- Check if palette already exists on any bar
    for barIdx = 1, 6 do
        local configKey = 'hotbarBar' .. barIdx;
        local barSettings = gConfig and gConfig[configKey];
        if barSettings and barSettings.slotActions and barSettings.slotActions[newStorageKey] then
            return false, 'Palette already exists';
        end
    end

    -- Create empty palette entry on ALL bars
    for barIdx = 1, 6 do
        local configKey = 'hotbarBar' .. barIdx;
        local barSettings = gConfig and gConfig[configKey];
        if barSettings then
            -- Ensure slotActions structure
            if not barSettings.slotActions then
                barSettings.slotActions = {};
            end
            -- Create empty palette (users will populate it)
            barSettings.slotActions[newStorageKey] = {};
        end
    end

    -- Store palette order at GLOBAL level (gConfig.hotbar.paletteOrder[jobId])
    if not gConfig.hotbar then
        gConfig.hotbar = {};
    end
    if not gConfig.hotbar.paletteOrder then
        gConfig.hotbar.paletteOrder = {};
    end
    if not gConfig.hotbar.paletteOrder[normalizedJobId] then
        gConfig.hotbar.paletteOrder[normalizedJobId] = {};
    end
    table.insert(gConfig.hotbar.paletteOrder[normalizedJobId], paletteName);

    SaveSettingsToDisk();
    return true;
end

-- Ensure at least one palette exists for a job
-- Creates a "Default" palette if none exist
-- Returns the name of the first available palette
function M.EnsureDefaultPaletteExists(jobId, subjobId)
    local normalizedJobId = jobId or 1;

    -- Check if any palettes exist for this job
    local availablePalettes = M.GetAvailablePalettes(1, normalizedJobId, subjobId);

    if #availablePalettes == 0 then
        -- No palettes exist, create the default one
        local success, err = M.CreatePalette(1, M.DEFAULT_PALETTE_NAME, normalizedJobId, subjobId);
        if success then
            return M.DEFAULT_PALETTE_NAME;
        else
            -- If "Default" already exists somehow, try numbered names
            for i = 1, 99 do
                local name = 'Palette ' .. i;
                success, err = M.CreatePalette(1, name, normalizedJobId, subjobId);
                if success then
                    return name;
                end
            end
        end
        return nil;  -- Failed to create
    end

    return availablePalettes[1];  -- Return first existing palette
end

-- Delete a palette (GLOBAL - removes from all bars)
-- barIndex param kept for backwards compatibility but ignored
-- subjobId param kept for backwards compatibility but ignored
-- NOTE: Cannot delete the last palette - at least one must always exist
-- Returns true on success, false with error message on failure
function M.DeletePalette(barIndex, paletteName, jobId, subjobId)
    if not paletteName then
        return false, 'No palette specified';
    end

    local normalizedJobId = jobId or 1;

    -- Check if this is the last palette - cannot delete if so
    local availablePalettes = M.GetAvailablePalettes(barIndex, normalizedJobId, subjobId);
    if #availablePalettes <= 1 then
        return false, 'Cannot delete the last palette';
    end

    -- Build new format storage key: '{jobId}:palette:{name}'
    local storageKey = M.BuildPaletteStorageKey(normalizedJobId, paletteName);

    -- Delete palette from ALL bars
    local found = false;
    for barIdx = 1, 6 do
        local configKey = 'hotbarBar' .. barIdx;
        local barSettings = gConfig and gConfig[configKey];
        if barSettings and barSettings.slotActions then
            if barSettings.slotActions[storageKey] then
                barSettings.slotActions[storageKey] = nil;
                found = true;
            end
        end
    end

    if not found then
        return false, 'Palette not found';
    end

    -- Remove from GLOBAL paletteOrder
    if gConfig.hotbar and gConfig.hotbar.paletteOrder and gConfig.hotbar.paletteOrder[normalizedJobId] then
        for i, name in ipairs(gConfig.hotbar.paletteOrder[normalizedJobId]) do
            if name == paletteName then
                table.remove(gConfig.hotbar.paletteOrder[normalizedJobId], i);
                break;
            end
        end
    end

    -- If this was the active palette, switch to the first available palette
    if state.activePalette == paletteName then
        -- Get updated list after deletion
        local remainingPalettes = M.GetAvailablePalettes(barIndex, normalizedJobId, subjobId);
        local newActive = remainingPalettes[1];  -- First palette becomes active
        M.SetActivePalette(1, newActive);
    end

    SaveSettingsToDisk();
    return true;
end

-- Rename a palette (GLOBAL - renames across all bars)
-- barIndex param kept for backwards compatibility but ignored
-- subjobId param kept for backwards compatibility but ignored
-- Returns true on success, false with error message on failure
function M.RenamePalette(barIndex, oldName, newName, jobId, subjobId)
    if not oldName then
        return false, 'No palette specified';
    end

    if not IsValidPaletteName(newName) then
        return false, 'Invalid new palette name';
    end

    if oldName == newName then
        return false, 'New name is the same as the old name';
    end

    local normalizedJobId = jobId or 1;

    -- Build new format storage keys
    local oldStorageKey = M.BuildPaletteStorageKey(normalizedJobId, oldName);
    local newStorageKey = M.BuildPaletteStorageKey(normalizedJobId, newName);

    -- Check if new name already exists on any bar
    for barIdx = 1, 6 do
        local configKey = 'hotbarBar' .. barIdx;
        local barSettings = gConfig and gConfig[configKey];
        if barSettings and barSettings.slotActions and barSettings.slotActions[newStorageKey] then
            return false, 'A palette with that name already exists';
        end
    end

    -- Rename palette on ALL bars
    local found = false;
    for barIdx = 1, 6 do
        local configKey = 'hotbarBar' .. barIdx;
        local barSettings = gConfig and gConfig[configKey];
        if barSettings and barSettings.slotActions then
            if barSettings.slotActions[oldStorageKey] then
                barSettings.slotActions[newStorageKey] = barSettings.slotActions[oldStorageKey];
                barSettings.slotActions[oldStorageKey] = nil;
                found = true;
            end
        end
    end

    if not found then
        return false, 'Palette not found';
    end

    -- Update GLOBAL paletteOrder (rename entry in place)
    if gConfig.hotbar and gConfig.hotbar.paletteOrder and gConfig.hotbar.paletteOrder[normalizedJobId] then
        for i, name in ipairs(gConfig.hotbar.paletteOrder[normalizedJobId]) do
            if name == oldName then
                gConfig.hotbar.paletteOrder[normalizedJobId][i] = newName;
                break;
            end
        end
    end

    -- Update active palette if this was active
    if state.activePalette == oldName then
        state.activePalette = newName;
    end

    SaveSettingsToDisk();
    return true;
end

-- Move a palette up or down in the order (GLOBAL)
-- barIndex param kept for backwards compatibility but ignored
-- subjobId param kept for backwards compatibility but ignored
-- direction: -1 for up (earlier in list), 1 for down (later in list)
-- Returns true on success, false with error message on failure
function M.MovePalette(barIndex, paletteName, direction, jobId, subjobId)
    if not paletteName then
        return false, 'No palette specified';
    end

    if direction ~= -1 and direction ~= 1 then
        return false, 'Invalid direction';
    end

    local normalizedJobId = jobId or 1;

    -- Ensure GLOBAL paletteOrder exists and is populated
    if not gConfig.hotbar then
        gConfig.hotbar = {};
    end
    if not gConfig.hotbar.paletteOrder then
        gConfig.hotbar.paletteOrder = {};
    end
    if not gConfig.hotbar.paletteOrder[normalizedJobId] then
        -- Initialize paletteOrder from current available palettes
        gConfig.hotbar.paletteOrder[normalizedJobId] = {};
        local available = M.GetAvailablePalettes(barIndex, jobId, subjobId);
        for _, name in ipairs(available) do
            table.insert(gConfig.hotbar.paletteOrder[normalizedJobId], name);
        end
    end

    local order = gConfig.hotbar.paletteOrder[normalizedJobId];

    -- Find palette index in order
    local currentIndex = nil;
    for i, name in ipairs(order) do
        if name == paletteName then
            currentIndex = i;
            break;
        end
    end

    if not currentIndex then
        return false, 'Palette not found in order';
    end

    local newIndex = currentIndex + direction;

    -- Check bounds
    if newIndex < 1 or newIndex > #order then
        return false, 'Cannot move palette further';
    end

    -- Swap positions
    order[currentIndex], order[newIndex] = order[newIndex], order[currentIndex];

    SaveSettingsToDisk();
    return true;
end

-- Set the complete palette order from an array (GLOBAL)
-- barIndex param kept for backwards compatibility but ignored
-- subjobId param kept for backwards compatibility but ignored
-- palettes: array of palette names in desired order (excluding Base)
-- Returns true on success, false with error message on failure
function M.SetPaletteOrder(barIndex, palettes, jobId, subjobId)
    if not palettes or type(palettes) ~= 'table' then
        return false, 'Invalid palette list';
    end

    local normalizedJobId = jobId or 1;

    -- Ensure GLOBAL paletteOrder exists
    if not gConfig.hotbar then
        gConfig.hotbar = {};
    end
    if not gConfig.hotbar.paletteOrder then
        gConfig.hotbar.paletteOrder = {};
    end

    -- Set the new order directly
    gConfig.hotbar.paletteOrder[normalizedJobId] = {};
    for _, name in ipairs(palettes) do
        table.insert(gConfig.hotbar.paletteOrder[normalizedJobId], name);
    end

    SaveSettingsToDisk();
    return true;
end

-- Get the index of a palette in the order (1-based) (GLOBAL)
-- barIndex param kept for backwards compatibility but ignored
-- subjobId param kept for backwards compatibility but ignored
-- Returns the index, or nil if not found
function M.GetPaletteIndex(barIndex, paletteName, jobId, subjobId)
    if not paletteName then
        return nil;
    end

    local available = M.GetAvailablePalettes(barIndex, jobId, subjobId);
    for i, name in ipairs(available) do
        if name == paletteName then
            return i;
        end
    end
    return nil;
end

-- Get the total number of palettes (GLOBAL)
-- barIndex param kept for backwards compatibility but ignored
-- subjobId param kept for backwards compatibility but ignored
function M.GetPaletteCount(barIndex, jobId, subjobId)
    local available = M.GetAvailablePalettes(barIndex, jobId, subjobId);
    return #available;
end

-- ============================================
-- Effective Storage Key for data.lua Integration
-- ============================================

-- Get the palette key suffix (GLOBAL - same for all bars)
-- barIndex param kept for backwards compatibility but ignored
-- Returns nil if no palette active (use default storage key)
-- This is called by data.lua to build the full storage key
function M.GetEffectivePaletteKeySuffix(barIndex)
    local activePalette = state.activePalette;
    return M.GetPaletteKeySuffix(activePalette);
end

-- Check if palette mode is enabled (GLOBAL - palettes exist for this job)
-- barIndex param kept for backwards compatibility but ignored
-- subjobId param kept for backwards compatibility but ignored
function M.IsPaletteModeEnabled(barIndex, jobId, subjobId)
    local palettes = M.GetAvailablePalettes(barIndex, jobId, subjobId);
    return #palettes > 0;
end

-- ============================================
-- Callback System
-- ============================================

-- Register a callback for palette changes
-- callback(barIndex, oldPaletteName, newPaletteName)
function M.OnPaletteChanged(callback)
    if callback then
        table.insert(state.onPaletteChangedCallbacks, callback);
    end
end

-- Fire all palette changed callbacks
function M.FirePaletteChangedCallbacks(barIndex, oldPalette, newPalette)
    for _, callback in ipairs(state.onPaletteChangedCallbacks) do
        local success, err = pcall(callback, barIndex, oldPalette, newPalette);
        if not success then
            print('[XIUI palette] Callback error: ' .. tostring(err));
        end
    end
end

-- ============================================
-- Crossbar Palette Management
-- ============================================

-- Crossbar combo modes for iteration
local CROSSBAR_COMBO_MODES = { 'L2', 'R2', 'L2R2', 'R2L2', 'L2x2', 'R2x2' };

-- Get all available palette names for crossbar only
-- Uses NEW FORMAT: '{jobId}:palette:{name}' (job-wide, no subjob)
-- Returns: { 'Stuns', 'Heals', ... } - palettes available ONLY for crossbar (empty if none defined)
-- Crossbar palettes are SEPARATE from hotbar palettes
function M.GetCrossbarAvailablePalettes(jobId, subjobId)
    local palettes = {};

    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings or not crossbarSettings.slotActions then
        return palettes;
    end

    local normalizedJobId = jobId or 1;

    -- NEW format pattern: '{jobId}:palette:{name}'
    local palettePattern = string.format('%d:%s', normalizedJobId, M.PALETTE_KEY_PREFIX);

    -- Collect all palette names from crossbar slotActions
    local existingPalettes = {};
    for storageKey, _ in pairs(crossbarSettings.slotActions) do
        if type(storageKey) == 'string' then
            -- Check NEW format only: '{jobId}:palette:{name}'
            if storageKey:find(palettePattern, 1, true) == 1 then
                local paletteName = storageKey:sub(#palettePattern + 1);
                if paletteName and paletteName ~= '' then
                    existingPalettes[paletteName] = true;
                end
            end
        end
    end

    -- Get the stored palette order for crossbar (keyed by jobId only)
    local storedOrder = crossbarSettings.crossbarPaletteOrder and crossbarSettings.crossbarPaletteOrder[normalizedJobId];

    -- Build ordered result: first add palettes from storedOrder that exist
    local seen = {};
    if storedOrder then
        for _, paletteName in ipairs(storedOrder) do
            if existingPalettes[paletteName] and not seen[paletteName] then
                seen[paletteName] = true;
                table.insert(palettes, paletteName);
            end
        end
    end

    -- Collect any remaining palettes not in the stored order
    local remaining = {};
    for paletteName, _ in pairs(existingPalettes) do
        if not seen[paletteName] then
            table.insert(remaining, paletteName);
        end
    end

    -- Sort remaining palettes alphabetically and append
    table.sort(remaining);
    for _, paletteName in ipairs(remaining) do
        table.insert(palettes, paletteName);
    end

    return palettes;
end

-- DEPRECATED: GetAllAvailablePalettes - kept for backwards compatibility
-- Now just returns hotbar palettes since crossbar has its own separate palettes
function M.GetAllAvailablePalettes(jobId, subjobId)
    local palettes = {};
    local seen = {};

    -- Scan all 6 hotbar bars only (NOT crossbar - they are separate now)
    for barIndex = 1, 6 do
        local barPalettes = M.GetAvailablePalettes(barIndex, jobId, subjobId);
        for _, paletteName in ipairs(barPalettes) do
            if not seen[paletteName] then
                seen[paletteName] = true;
                table.insert(palettes, paletteName);
            end
        end
    end

    return palettes;
end

-- Get active palette name for crossbar (GLOBAL - single palette for all combo modes)
-- comboMode param kept for backwards compatibility but ignored
-- Returns nil if no palette (using default slots)
function M.GetActivePaletteForCombo(comboMode)
    return state.crossbarActivePalette;
end

-- Get active palette display name for crossbar (GLOBAL)
-- comboMode param kept for backwards compatibility but ignored
-- Returns nil if no palette is active
function M.GetActivePaletteDisplayNameForCombo(comboMode)
    return state.crossbarActivePalette;
end

-- Set active palette for crossbar (GLOBAL - affects all combo modes)
-- comboMode param kept for backwards compatibility but ignored
-- paletteName: name to activate, or nil to clear
function M.SetActivePaletteForCombo(comboMode, paletteName)
    local oldPalette = state.crossbarActivePalette;

    -- Skip if no change
    if oldPalette == paletteName then
        return false;
    end

    state.crossbarActivePalette = paletteName;

    -- Fire callbacks for all combo modes (they all share the same palette now)
    for _, mode in ipairs(CROSSBAR_COMBO_MODES) do
        M.FirePaletteChangedCallbacks('crossbar:' .. mode, oldPalette, paletteName);
    end

    return true;
end

-- Clear active palette for crossbar (uses default slot data)
-- comboMode param kept for backwards compatibility but ignored
function M.ClearActivePaletteForCombo(comboMode)
    return M.SetActivePaletteForCombo(comboMode, nil);
end

-- Cycle through palettes for crossbar (GLOBAL - affects all combo modes)
-- comboMode param kept for backwards compatibility but ignored
-- direction: 1 for next, -1 for previous
function M.CyclePaletteForCombo(comboMode, direction, jobId, subjobId)
    direction = direction or 1;

    -- Use crossbar-only palette list (separate from hotbar)
    local palettes = M.GetCrossbarAvailablePalettes(jobId, subjobId);
    if #palettes == 0 then
        return nil, false;  -- No palettes defined, second return = no palettes exist
    end

    if #palettes == 1 then
        -- Only one palette, just make sure it's active
        M.SetActivePaletteForCombo(comboMode, palettes[1]);
        return palettes[1], true;
    end

    local currentName = state.crossbarActivePalette;
    local currentIndex = 1;  -- Default to first palette

    -- Find current palette index
    if currentName then
        for i, name in ipairs(palettes) do
            if name == currentName then
                currentIndex = i;
                break;
            end
        end
    end

    -- Calculate new index with wrap-around (1..#palettes only, no "empty" state)
    local newIndex = currentIndex + direction;
    if newIndex < 1 then newIndex = #palettes; end
    if newIndex > #palettes then newIndex = 1; end

    local newPalette = palettes[newIndex];
    M.SetActivePaletteForCombo(comboMode, newPalette);

    return newPalette, true;  -- Second return = palettes exist
end

-- Get the palette key suffix for crossbar (GLOBAL - same for all combo modes)
-- comboMode param kept for backwards compatibility but ignored
-- Returns nil if no palette (using default slots)
function M.GetEffectivePaletteKeySuffixForCombo(comboMode)
    local activePalette = state.crossbarActivePalette;
    return M.GetPaletteKeySuffix(activePalette);
end

-- Create a new palette for crossbar (stores in crossbar slotActions)
-- Uses NEW FORMAT: '{jobId}:palette:{name}' (job-wide, no subjob)
-- Returns true on success, false with error message on failure
function M.CreateCrossbarPalette(paletteName, jobId, subjobId)
    if not IsValidPaletteName(paletteName) then
        return false, 'Invalid palette name';
    end

    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings then
        return false, 'Crossbar settings not found';
    end

    -- Ensure slotActions structure
    if not crossbarSettings.slotActions then
        crossbarSettings.slotActions = {};
    end

    local normalizedJobId = jobId or 1;

    -- Build NEW format storage key: '{jobId}:palette:{name}'
    local storageKey = M.BuildPaletteStorageKey(normalizedJobId, paletteName);

    -- Check if palette already exists
    if crossbarSettings.slotActions[storageKey] then
        return false, 'Palette already exists';
    end

    -- Create empty palette structure for all combo modes
    crossbarSettings.slotActions[storageKey] = {};

    -- Add to crossbarPaletteOrder (keyed by jobId only)
    if not crossbarSettings.crossbarPaletteOrder then
        crossbarSettings.crossbarPaletteOrder = {};
    end
    if not crossbarSettings.crossbarPaletteOrder[normalizedJobId] then
        crossbarSettings.crossbarPaletteOrder[normalizedJobId] = {};
    end
    table.insert(crossbarSettings.crossbarPaletteOrder[normalizedJobId], paletteName);

    SaveSettingsToDisk();
    return true;
end

-- Ensure at least one crossbar palette exists for a job
-- Creates a "Default" palette if none exist
-- Returns the name of the first available palette
function M.EnsureCrossbarDefaultPaletteExists(jobId, subjobId)
    local normalizedJobId = jobId or 1;

    -- Check if any palettes exist for this job
    local availablePalettes = M.GetCrossbarAvailablePalettes(normalizedJobId, subjobId);

    if #availablePalettes == 0 then
        -- No palettes exist, create the default one
        local success, err = M.CreateCrossbarPalette(M.DEFAULT_PALETTE_NAME, normalizedJobId, subjobId);
        if success then
            -- Auto-activate the new palette
            M.SetActivePaletteForCombo('L2', M.DEFAULT_PALETTE_NAME);
            return M.DEFAULT_PALETTE_NAME;
        else
            -- If "Default" already exists somehow, try numbered names
            for i = 1, 99 do
                local name = 'Palette ' .. i;
                success, err = M.CreateCrossbarPalette(name, normalizedJobId, subjobId);
                if success then
                    M.SetActivePaletteForCombo('L2', name);
                    return name;
                end
            end
        end
        return nil;  -- Failed to create
    end

    return availablePalettes[1];  -- Return first existing palette
end

-- Helper: Find the actual crossbar storage key for a palette
-- Uses NEW FORMAT only: '{jobId}:palette:{name}' (job-wide, no subjob)
-- Returns storageKey or nil if not found
local function FindCrossbarPaletteStorageKey(paletteName, jobId, subjobId)
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings or not crossbarSettings.slotActions then
        return nil;
    end

    local normalizedJobId = jobId or 1;

    -- Use NEW format only: '{jobId}:palette:{name}'
    local storageKey = M.BuildPaletteStorageKey(normalizedJobId, paletteName);
    if crossbarSettings.slotActions[storageKey] then
        return storageKey;
    end

    return nil;
end

-- Delete a crossbar palette
-- Uses NEW FORMAT: '{jobId}:palette:{name}' (job-wide, no subjob)
-- Returns true on success, false with error message on failure
function M.DeleteCrossbarPalette(paletteName, jobId, subjobId)
    if not paletteName then
        return false, 'No palette specified';
    end

    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings or not crossbarSettings.slotActions then
        return false, 'Palette not found';
    end

    local normalizedJobId = jobId or 1;

    -- Find the storage key using NEW format
    local storageKey = FindCrossbarPaletteStorageKey(paletteName, jobId, subjobId);
    if not storageKey then
        return false, 'Palette not found';
    end

    -- Delete the palette
    crossbarSettings.slotActions[storageKey] = nil;

    -- Remove from crossbarPaletteOrder (keyed by jobId only)
    if crossbarSettings.crossbarPaletteOrder and crossbarSettings.crossbarPaletteOrder[normalizedJobId] then
        for i, name in ipairs(crossbarSettings.crossbarPaletteOrder[normalizedJobId]) do
            if name == paletteName then
                table.remove(crossbarSettings.crossbarPaletteOrder[normalizedJobId], i);
                break;
            end
        end
    end

    -- If the GLOBAL crossbar palette was this palette, clear it
    if state.crossbarActivePalette == paletteName then
        state.crossbarActivePalette = nil;
    end

    SaveSettingsToDisk();
    return true;
end

-- Rename a crossbar palette
-- Uses NEW FORMAT: '{jobId}:palette:{name}' (job-wide, no subjob)
-- Returns true on success, false with error message on failure
function M.RenameCrossbarPalette(oldName, newName, jobId, subjobId)
    if not oldName then
        return false, 'No palette specified';
    end

    if not IsValidPaletteName(newName) then
        return false, 'Invalid new palette name';
    end

    if oldName == newName then
        return false, 'New name is the same as the old name';
    end

    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings or not crossbarSettings.slotActions then
        return false, 'Palette not found';
    end

    local normalizedJobId = jobId or 1;

    -- Find the storage key for the old palette using NEW format
    local oldStorageKey = FindCrossbarPaletteStorageKey(oldName, jobId, subjobId);
    if not oldStorageKey then
        return false, 'Palette not found';
    end

    -- Build new storage key using NEW format
    local newStorageKey = M.BuildPaletteStorageKey(normalizedJobId, newName);

    -- Check if new name already exists
    local existingKey = FindCrossbarPaletteStorageKey(newName, jobId, subjobId);
    if existingKey then
        return false, 'A palette with that name already exists';
    end

    -- Move data to new key
    crossbarSettings.slotActions[newStorageKey] = crossbarSettings.slotActions[oldStorageKey];
    crossbarSettings.slotActions[oldStorageKey] = nil;

    -- Update crossbarPaletteOrder (keyed by jobId only)
    if crossbarSettings.crossbarPaletteOrder and crossbarSettings.crossbarPaletteOrder[normalizedJobId] then
        for i, name in ipairs(crossbarSettings.crossbarPaletteOrder[normalizedJobId]) do
            if name == oldName then
                crossbarSettings.crossbarPaletteOrder[normalizedJobId][i] = newName;
                break;
            end
        end
    end

    -- Update GLOBAL crossbar active palette if this was the active one
    if state.crossbarActivePalette == oldName then
        state.crossbarActivePalette = newName;
    end

    SaveSettingsToDisk();
    return true;
end

-- Move a crossbar palette up or down in the order
-- Uses NEW FORMAT: crossbarPaletteOrder keyed by jobId only (not job:subjob)
-- direction: -1 for up (earlier in list), 1 for down (later in list)
-- Returns true on success, false with error message on failure
function M.MoveCrossbarPalette(paletteName, direction, jobId, subjobId)
    if not paletteName then
        return false, 'No palette specified';
    end

    if direction ~= -1 and direction ~= 1 then
        return false, 'Invalid direction';
    end

    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings then
        return false, 'Crossbar settings not found';
    end

    local normalizedJobId = jobId or 1;

    -- Ensure crossbarPaletteOrder exists and is populated (keyed by jobId only)
    if not crossbarSettings.crossbarPaletteOrder then
        crossbarSettings.crossbarPaletteOrder = {};
    end
    if not crossbarSettings.crossbarPaletteOrder[normalizedJobId] then
        -- Initialize crossbarPaletteOrder from current available palettes
        crossbarSettings.crossbarPaletteOrder[normalizedJobId] = {};
        local available = M.GetCrossbarAvailablePalettes(jobId, subjobId);
        for _, name in ipairs(available) do
            table.insert(crossbarSettings.crossbarPaletteOrder[normalizedJobId], name);
        end
    end

    local order = crossbarSettings.crossbarPaletteOrder[normalizedJobId];

    -- Find palette index in order
    local currentIndex = nil;
    for i, name in ipairs(order) do
        if name == paletteName then
            currentIndex = i;
            break;
        end
    end

    if not currentIndex then
        return false, 'Palette not found in order';
    end

    local newIndex = currentIndex + direction;

    -- Check bounds
    if newIndex < 1 or newIndex > #order then
        return false, 'Cannot move palette further';
    end

    -- Swap positions
    order[currentIndex], order[newIndex] = order[newIndex], order[currentIndex];

    SaveSettingsToDisk();
    return true;
end

-- Check if a specific crossbar palette exists
function M.CrossbarPaletteExists(paletteName, jobId, subjobId)
    if not paletteName then
        return false;
    end

    local available = M.GetCrossbarAvailablePalettes(jobId, subjobId);
    for _, name in ipairs(available) do
        if name == paletteName then
            return true;
        end
    end
    return false;
end

-- Get the index of a crossbar palette in the order list
-- Returns nil if palette not found
function M.GetCrossbarPaletteIndex(paletteName, jobId, subjobId)
    if not paletteName then
        return nil;
    end

    local available = M.GetCrossbarAvailablePalettes(jobId, subjobId);
    for i, name in ipairs(available) do
        if name == paletteName then
            return i;
        end
    end
    return nil;
end

-- Get the total number of crossbar palettes
function M.GetCrossbarPaletteCount(jobId, subjobId)
    local available = M.GetCrossbarAvailablePalettes(jobId, subjobId);
    return #available;
end

-- ============================================
-- State Management (GLOBAL)
-- ============================================

-- Validate active palettes against current job's available palettes
-- Ensures at least one palette exists, and auto-selects the first palette if none is active
-- Should be called on job change
function M.ValidatePalettesForJob(jobId, subjobId)
    -- Ensure gConfig.hotbar structure exists before any palette operations
    if not EnsureHotbarConfigExists() then
        print('[XIUI palette] Warning: gConfig not available, skipping palette validation');
        return;
    end

    -- Ensure at least one palette exists for this job
    local firstPalette = M.EnsureDefaultPaletteExists(jobId, subjobId);
    if not firstPalette then
        print('[XIUI palette] Warning: Failed to create default palette for job ' .. tostring(jobId));
        return;
    end

    -- Get available palettes
    local availablePalettes = M.GetAvailablePalettes(1, jobId, subjobId);

    -- Try to restore saved palette state for this job
    local savedPalette = LoadPaletteState(jobId);

    -- Check if current hotbar palette is valid
    if state.activePalette then
        local found = false;
        for _, name in ipairs(availablePalettes) do
            if name == state.activePalette then
                found = true;
                break;
            end
        end
        if not found then
            -- Palette doesn't exist for this job, try saved state or use first available
            local oldPalette = state.activePalette;
            local newPalette = nil;

            -- Check if saved palette exists for this job
            if savedPalette then
                for _, name in ipairs(availablePalettes) do
                    if name == savedPalette then
                        newPalette = savedPalette;
                        break;
                    end
                end
            end

            state.activePalette = newPalette or firstPalette;
            -- Fire callbacks for all bars
            for i = 1, 6 do
                M.FirePaletteChangedCallbacks(i, oldPalette, state.activePalette);
            end
        end
    else
        -- No palette active, try saved state or select the first one
        local newPalette = nil;

        -- Check if saved palette exists for this job
        if savedPalette then
            for _, name in ipairs(availablePalettes) do
                if name == savedPalette then
                    newPalette = savedPalette;
                    break;
                end
            end
        end

        state.activePalette = newPalette or firstPalette;
        -- Fire callbacks for all bars
        for i = 1, 6 do
            M.FirePaletteChangedCallbacks(i, nil, state.activePalette);
        end
    end

    -- Ensure at least one crossbar palette exists for this job
    local firstCrossbarPalette = M.EnsureCrossbarDefaultPaletteExists(jobId, subjobId);
    if not firstCrossbarPalette then
        print('[XIUI palette] Warning: Failed to create default crossbar palette for job ' .. tostring(jobId));
    end

    -- Get available crossbar palettes
    local availableCrossbarPalettes = M.GetCrossbarAvailablePalettes(jobId, subjobId);

    -- Check if current crossbar palette is valid
    if state.crossbarActivePalette then
        local found = false;
        for _, name in ipairs(availableCrossbarPalettes) do
            if name == state.crossbarActivePalette then
                found = true;
                break;
            end
        end
        if not found then
            -- Palette doesn't exist for this job, use first available
            local oldPalette = state.crossbarActivePalette;
            state.crossbarActivePalette = firstCrossbarPalette;
            -- Fire callbacks for all combo modes
            for _, mode in ipairs(CROSSBAR_COMBO_MODES) do
                M.FirePaletteChangedCallbacks('crossbar:' .. mode, oldPalette, state.crossbarActivePalette);
            end
        end
    else
        -- No crossbar palette active, select the first one
        if firstCrossbarPalette then
            state.crossbarActivePalette = firstCrossbarPalette;
            -- Fire callbacks for all combo modes
            for _, mode in ipairs(CROSSBAR_COMBO_MODES) do
                M.FirePaletteChangedCallbacks('crossbar:' .. mode, nil, state.crossbarActivePalette);
            end
        end
    end
end

-- Reset all state
function M.Reset()
    state.activePalette = nil;
    state.crossbarActivePalette = nil;
end

-- Get state for persistence (if needed)
function M.GetState()
    return {
        activePalette = state.activePalette,
        crossbarActivePalette = state.crossbarActivePalette,
    };
end

-- Restore state from persistence (if needed)
function M.RestoreState(savedState)
    if savedState then
        state.activePalette = savedState.activePalette;
        state.crossbarActivePalette = savedState.crossbarActivePalette;
    end
end

return M;
