--[[
* XIUI Hotbar - General Palette Module
* Manages user-defined named palettes for hotbars
* Works alongside petpalette.lua (pet palettes take precedence when petAware is enabled)
*
* Storage key format: '{jobId}:{subjobId}:palette:{name}' (e.g., '15:10:palette:Stuns')
* Base palette uses: '{jobId}:{subjobId}' (no palette suffix)
]]--

require('common');
require('handlers.helpers');

local M = {};

-- ============================================
-- Constants
-- ============================================

M.BASE_PALETTE_NAME = 'Base';
M.PALETTE_KEY_PREFIX = 'palette:';

-- ============================================
-- State
-- ============================================

local state = {
    -- Active palette name per bar: [barIndex] = paletteName or nil (nil = Base)
    activePalettes = {},

    -- Callbacks for palette change events
    onPaletteChangedCallbacks = {},
};

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

-- Build full storage key for a palette
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
-- Returns nil if no palette suffix (base palette)
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
-- Active Palette Management
-- ============================================

-- Get active palette name for a bar (nil = Base)
function M.GetActivePalette(barIndex)
    return state.activePalettes[barIndex];
end

-- Get active palette display name for a bar
-- Returns nil if no palette is active
function M.GetActivePaletteDisplayName(barIndex)
    return state.activePalettes[barIndex];
end

-- Set active palette for a bar
-- paletteName: name to activate, or nil to clear
function M.SetActivePalette(barIndex, paletteName)
    local oldPalette = state.activePalettes[barIndex];

    -- Skip if no change
    if oldPalette == paletteName then
        return false;
    end

    state.activePalettes[barIndex] = paletteName;

    -- Fire callbacks
    M.FirePaletteChangedCallbacks(barIndex, oldPalette, paletteName);

    return true;
end

-- Clear active palette for a bar (uses default slot data)
function M.ClearActivePalette(barIndex)
    return M.SetActivePalette(barIndex, nil);
end

-- Clear all active palettes
function M.ClearAllActivePalettes()
    local hadChanges = false;
    for barIndex, _ in pairs(state.activePalettes) do
        if M.ClearActivePalette(barIndex) then
            hadChanges = true;
        end
    end
    return hadChanges;
end

-- ============================================
-- Available Palettes Discovery
-- ============================================

-- Get list of available palette names for a bar based on stored slotActions
-- Returns palettes in the user-defined order from paletteOrder, with any missing palettes appended alphabetically
-- Returns: { 'Stuns', 'Heals', ... } (empty if no palettes defined)
function M.GetAvailablePalettes(barIndex, jobId, subjobId)
    local palettes = {};

    local configKey = 'hotbarBar' .. barIndex;
    local barSettings = gConfig and gConfig[configKey];
    if not barSettings or not barSettings.slotActions then
        return palettes;
    end

    -- Build base key pattern to match
    local normalizedJobId = jobId or 1;
    local normalizedSubjobId = subjobId or 0;
    local baseKey = string.format('%d:%d', normalizedJobId, normalizedSubjobId);
    local palettePattern = baseKey .. ':' .. M.PALETTE_KEY_PREFIX;

    -- Also check for fallback pattern with subjob=0 (for imported palettes)
    local fallbackPattern = nil;
    if normalizedSubjobId ~= 0 then
        local fallbackKey = string.format('%d:0', normalizedJobId);
        fallbackPattern = fallbackKey .. ':' .. M.PALETTE_KEY_PREFIX;
    end

    -- First, collect all palette names that exist in slotActions
    local existingPalettes = {};
    for storageKey, _ in pairs(barSettings.slotActions) do
        if type(storageKey) == 'string' then
            local paletteName = nil;

            -- Check primary pattern first
            if storageKey:find(palettePattern, 1, true) == 1 then
                paletteName = storageKey:sub(#palettePattern + 1);
            -- Check fallback pattern (subjob=0) for imported palettes
            elseif fallbackPattern and storageKey:find(fallbackPattern, 1, true) == 1 then
                paletteName = storageKey:sub(#fallbackPattern + 1);
            end

            if paletteName and paletteName ~= '' then
                existingPalettes[paletteName] = true;
            end
        end
    end

    -- Get the stored palette order for this job:subjob combination
    local orderKey = baseKey;
    local storedOrder = barSettings.paletteOrder and barSettings.paletteOrder[orderKey];

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
-- Palette Cycling
-- ============================================

-- Cycle through palettes for a bar
-- direction: 1 for next, -1 for previous
function M.CyclePalette(barIndex, direction, jobId, subjobId)
    direction = direction or 1;

    local palettes = M.GetAvailablePalettes(barIndex, jobId, subjobId);
    if #palettes <= 1 then
        return nil;  -- Nothing to cycle (only Base)
    end

    local currentName = M.GetActivePaletteDisplayName(barIndex);
    local currentIndex = 1;

    -- Find current palette index
    for i, name in ipairs(palettes) do
        if name == currentName then
            currentIndex = i;
            break;
        end
    end

    -- Calculate new index with wrap-around
    local newIndex = currentIndex + direction;
    if newIndex < 1 then newIndex = #palettes; end
    if newIndex > #palettes then newIndex = 1; end

    local newPalette = palettes[newIndex];
    M.SetActivePalette(barIndex, newPalette);

    return newPalette;
end

-- ============================================
-- Palette CRUD Operations
-- ============================================

-- Helper: Find the actual storage key for a palette
-- Checks both current subjob key and fallback subjob=0 key
-- Returns storageKey, baseKey or nil, nil if not found
local function FindPaletteStorageKey(barIndex, paletteName, jobId, subjobId)
    local configKey = 'hotbarBar' .. barIndex;
    local barSettings = gConfig and gConfig[configKey];
    if not barSettings or not barSettings.slotActions then
        return nil, nil;
    end

    local normalizedJobId = jobId or 1;
    local normalizedSubjobId = subjobId or 0;

    -- Try primary key first (current job:subjob)
    local baseKey = string.format('%d:%d', normalizedJobId, normalizedSubjobId);
    local storageKey = M.BuildStorageKey(baseKey, paletteName);
    if barSettings.slotActions[storageKey] then
        return storageKey, baseKey;
    end

    -- Try fallback key (job:0) if subjob is not already 0
    if normalizedSubjobId ~= 0 then
        local fallbackBaseKey = string.format('%d:0', normalizedJobId);
        local fallbackStorageKey = M.BuildStorageKey(fallbackBaseKey, paletteName);
        if barSettings.slotActions[fallbackStorageKey] then
            return fallbackStorageKey, fallbackBaseKey;
        end
    end

    return nil, nil;
end

-- Create a new palette by copying current slot data
-- Returns true on success, false with error message on failure
function M.CreatePalette(barIndex, paletteName, jobId, subjobId)
    if not IsValidPaletteName(paletteName) then
        return false, 'Invalid palette name';
    end

    if paletteName == M.BASE_PALETTE_NAME then
        return false, 'Cannot create palette named "Base"';
    end

    local configKey = 'hotbarBar' .. barIndex;
    local barSettings = gConfig and gConfig[configKey];
    if not barSettings then
        return false, 'Bar settings not found';
    end

    -- Build storage keys
    local baseKey = string.format('%d:%d', jobId or 1, subjobId or 0);
    local newStorageKey = M.BuildStorageKey(baseKey, paletteName);

    -- Check if palette already exists
    if barSettings.slotActions and barSettings.slotActions[newStorageKey] then
        return false, 'Palette already exists';
    end

    -- Ensure slotActions structure
    if not barSettings.slotActions then
        barSettings.slotActions = {};
    end

    -- Copy current palette's data to new palette
    local currentStorageKey = M.BuildStorageKey(baseKey, state.activePalettes[barIndex]);
    local currentData = barSettings.slotActions[currentStorageKey];

    if currentData then
        -- Deep copy
        barSettings.slotActions[newStorageKey] = deep_copy_table(currentData);
    else
        -- Create empty palette
        barSettings.slotActions[newStorageKey] = {};
    end

    -- Add to paletteOrder for this job:subjob
    if not barSettings.paletteOrder then
        barSettings.paletteOrder = {};
    end
    if not barSettings.paletteOrder[baseKey] then
        barSettings.paletteOrder[baseKey] = {};
    end
    table.insert(barSettings.paletteOrder[baseKey], paletteName);

    SaveSettingsToDisk();
    return true;
end

-- Delete a palette
-- Returns true on success, false with error message on failure
function M.DeletePalette(barIndex, paletteName, jobId, subjobId)
    if not paletteName then
        return false, 'No palette specified';
    end

    local configKey = 'hotbarBar' .. barIndex;
    local barSettings = gConfig and gConfig[configKey];
    if not barSettings or not barSettings.slotActions then
        return false, 'Palette not found';
    end

    -- Find the actual storage key (handles fallback to subjob=0)
    local storageKey = FindPaletteStorageKey(barIndex, paletteName, jobId, subjobId);
    if not storageKey then
        return false, 'Palette not found';
    end

    -- Delete the palette
    barSettings.slotActions[storageKey] = nil;

    -- Remove from paletteOrder for this job:subjob
    local baseKey = string.format('%d:%d', jobId or 1, subjobId or 0);
    if barSettings.paletteOrder and barSettings.paletteOrder[baseKey] then
        for i, name in ipairs(barSettings.paletteOrder[baseKey]) do
            if name == paletteName then
                table.remove(barSettings.paletteOrder[baseKey], i);
                break;
            end
        end
    end

    -- If this was the active palette, switch to Base
    if state.activePalettes[barIndex] == paletteName then
        M.SetActivePalette(barIndex, nil);
    end

    SaveSettingsToDisk();
    return true;
end

-- Rename a palette
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

    local configKey = 'hotbarBar' .. barIndex;
    local barSettings = gConfig and gConfig[configKey];
    if not barSettings or not barSettings.slotActions then
        return false, 'Palette not found';
    end

    -- Find the actual storage key for the old palette (handles fallback to subjob=0)
    local oldStorageKey, foundBaseKey = FindPaletteStorageKey(barIndex, oldName, jobId, subjobId);
    if not oldStorageKey then
        return false, 'Palette not found';
    end

    -- Build new storage key using the same base key as the found palette
    local newStorageKey = M.BuildStorageKey(foundBaseKey, newName);

    -- Check if new name already exists (check both current subjob and fallback)
    local existingKey = FindPaletteStorageKey(barIndex, newName, jobId, subjobId);
    if existingKey then
        return false, 'A palette with that name already exists';
    end

    -- Move data to new key
    barSettings.slotActions[newStorageKey] = barSettings.slotActions[oldStorageKey];
    barSettings.slotActions[oldStorageKey] = nil;

    -- Update paletteOrder for this job:subjob (rename the entry in place)
    if barSettings.paletteOrder and barSettings.paletteOrder[foundBaseKey] then
        for i, name in ipairs(barSettings.paletteOrder[foundBaseKey]) do
            if name == oldName then
                barSettings.paletteOrder[foundBaseKey][i] = newName;
                break;
            end
        end
    end

    -- Update active palette if this was active
    if state.activePalettes[barIndex] == oldName then
        state.activePalettes[barIndex] = newName;
    end

    SaveSettingsToDisk();
    return true;
end

-- Move a palette up or down in the order
-- direction: -1 for up (earlier in list), 1 for down (later in list)
-- Returns true on success, false with error message on failure
function M.MovePalette(barIndex, paletteName, direction, jobId, subjobId)
    if not paletteName then
        return false, 'No palette specified';
    end

    if direction ~= -1 and direction ~= 1 then
        return false, 'Invalid direction';
    end

    local configKey = 'hotbarBar' .. barIndex;
    local barSettings = gConfig and gConfig[configKey];
    if not barSettings then
        return false, 'Bar settings not found';
    end

    local baseKey = string.format('%d:%d', jobId or 1, subjobId or 0);

    -- Ensure paletteOrder exists and is populated
    if not barSettings.paletteOrder then
        barSettings.paletteOrder = {};
    end
    if not barSettings.paletteOrder[baseKey] then
        -- Initialize paletteOrder from current available palettes
        barSettings.paletteOrder[baseKey] = {};
        local available = M.GetAvailablePalettes(barIndex, jobId, subjobId);
        for _, name in ipairs(available) do
            table.insert(barSettings.paletteOrder[baseKey], name);
        end
    end

    local order = barSettings.paletteOrder[baseKey];

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

-- Set the complete palette order from an array
-- palettes: array of palette names in desired order (excluding Base)
-- Returns true on success, false with error message on failure
function M.SetPaletteOrder(barIndex, palettes, jobId, subjobId)
    if not palettes or type(palettes) ~= 'table' then
        return false, 'Invalid palette list';
    end

    local configKey = 'hotbarBar' .. barIndex;
    local barSettings = gConfig and gConfig[configKey];
    if not barSettings then
        return false, 'Bar settings not found';
    end

    local baseKey = string.format('%d:%d', jobId or 1, subjobId or 0);

    -- Ensure paletteOrder exists
    if not barSettings.paletteOrder then
        barSettings.paletteOrder = {};
    end

    -- Set the new order directly
    barSettings.paletteOrder[baseKey] = {};
    for _, name in ipairs(palettes) do
        table.insert(barSettings.paletteOrder[baseKey], name);
    end

    SaveSettingsToDisk();
    return true;
end

-- Get the index of a palette in the order (1-based)
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

-- Get the total number of palettes for a bar
function M.GetPaletteCount(barIndex, jobId, subjobId)
    local available = M.GetAvailablePalettes(barIndex, jobId, subjobId);
    return #available;
end

-- ============================================
-- Effective Storage Key for data.lua Integration
-- ============================================

-- Get the palette key suffix for a bar (to be appended to base job:subjob key)
-- Returns nil if Base palette (no suffix needed)
-- This is called by data.lua to build the full storage key
function M.GetEffectivePaletteKeySuffix(barIndex)
    local activePalette = state.activePalettes[barIndex];
    return M.GetPaletteKeySuffix(activePalette);
end

-- Check if palette mode is enabled for a bar
-- Palette mode is enabled if the bar has any palettes defined (beyond Base)
function M.IsPaletteModeEnabled(barIndex, jobId, subjobId)
    local palettes = M.GetAvailablePalettes(barIndex, jobId, subjobId);
    return #palettes > 1;
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
-- Returns: { 'Stuns', 'Heals', ... } - palettes available ONLY for crossbar (empty if none defined)
-- Crossbar palettes are SEPARATE from hotbar palettes
function M.GetCrossbarAvailablePalettes(jobId, subjobId)
    local palettes = {};

    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings or not crossbarSettings.slotActions then
        return palettes;
    end

    local normalizedJobId = jobId or 1;
    local normalizedSubjobId = subjobId or 0;
    local baseKey = string.format('%d:%d', normalizedJobId, normalizedSubjobId);
    local palettePattern = baseKey .. ':' .. M.PALETTE_KEY_PREFIX;

    -- Also check for fallback pattern with subjob=0 (for imported palettes)
    local fallbackPattern = nil;
    if normalizedSubjobId ~= 0 then
        local fallbackKey = string.format('%d:0', normalizedJobId);
        fallbackPattern = fallbackKey .. ':' .. M.PALETTE_KEY_PREFIX;
    end

    -- Collect all palette names from crossbar slotActions
    local existingPalettes = {};
    for storageKey, _ in pairs(crossbarSettings.slotActions) do
        if type(storageKey) == 'string' then
            local paletteName = nil;

            -- Check primary pattern first
            if storageKey:find(palettePattern, 1, true) == 1 then
                paletteName = storageKey:sub(#palettePattern + 1);
            -- Check fallback pattern (subjob=0) for imported palettes
            elseif fallbackPattern and storageKey:find(fallbackPattern, 1, true) == 1 then
                paletteName = storageKey:sub(#fallbackPattern + 1);
            end

            if paletteName and paletteName ~= '' then
                existingPalettes[paletteName] = true;
            end
        end
    end

    -- Get the stored palette order for crossbar
    local orderKey = baseKey;
    local storedOrder = crossbarSettings.crossbarPaletteOrder and crossbarSettings.crossbarPaletteOrder[orderKey];

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

-- Get active palette name for a crossbar combo mode (from settings)
-- Returns nil for Base palette
function M.GetActivePaletteForCombo(comboMode)
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    local modeSettings = crossbarSettings and crossbarSettings.comboModeSettings and crossbarSettings.comboModeSettings[comboMode];
    return modeSettings and modeSettings.activePalette;
end

-- Get active palette display name for a crossbar combo mode
-- Returns nil if no palette is active
function M.GetActivePaletteDisplayNameForCombo(comboMode)
    return M.GetActivePaletteForCombo(comboMode);
end

-- Set active palette for a crossbar combo mode
-- paletteName: name to activate, or nil to clear
function M.SetActivePaletteForCombo(comboMode, paletteName)
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings then return false; end

    -- Ensure comboModeSettings exists
    if not crossbarSettings.comboModeSettings then
        crossbarSettings.comboModeSettings = {};
    end
    if not crossbarSettings.comboModeSettings[comboMode] then
        crossbarSettings.comboModeSettings[comboMode] = { petAware = false, activePalette = nil };
    end

    local oldPalette = crossbarSettings.comboModeSettings[comboMode].activePalette;

    -- Skip if no change
    if oldPalette == paletteName then
        return false;
    end

    crossbarSettings.comboModeSettings[comboMode].activePalette = paletteName;

    -- Fire callbacks (using negative "bar index" to indicate crossbar)
    -- We use comboMode as identifier instead
    M.FirePaletteChangedCallbacks('crossbar:' .. comboMode, oldPalette, paletteName);

    return true;
end

-- Clear active palette for a crossbar combo mode (uses default slot data)
function M.ClearActivePaletteForCombo(comboMode)
    return M.SetActivePaletteForCombo(comboMode, nil);
end

-- Cycle through palettes for a crossbar combo mode
-- direction: 1 for next, -1 for previous
function M.CyclePaletteForCombo(comboMode, direction, jobId, subjobId)
    direction = direction or 1;

    -- Use crossbar-only palette list (separate from hotbar)
    local palettes = M.GetCrossbarAvailablePalettes(jobId, subjobId);
    if #palettes <= 1 then
        return nil;  -- Nothing to cycle (only Base)
    end

    local currentName = M.GetActivePaletteDisplayNameForCombo(comboMode);
    local currentIndex = 1;

    -- Find current palette index
    for i, name in ipairs(palettes) do
        if name == currentName then
            currentIndex = i;
            break;
        end
    end

    -- Calculate new index with wrap-around
    local newIndex = currentIndex + direction;
    if newIndex < 1 then newIndex = #palettes; end
    if newIndex > #palettes then newIndex = 1; end

    local newPalette = palettes[newIndex];
    M.SetActivePaletteForCombo(comboMode, newPalette);

    return newPalette;
end

-- Get the palette key suffix for a crossbar combo mode
-- Returns nil if Base palette (no suffix needed)
function M.GetEffectivePaletteKeySuffixForCombo(comboMode)
    local activePalette = M.GetActivePaletteForCombo(comboMode);
    return M.GetPaletteKeySuffix(activePalette);
end

-- Create a new palette for crossbar (stores in crossbar slotActions)
-- Returns true on success, false with error message on failure
function M.CreateCrossbarPalette(paletteName, jobId, subjobId)
    if not IsValidPaletteName(paletteName) then
        return false, 'Invalid palette name';
    end

    if paletteName == M.BASE_PALETTE_NAME then
        return false, 'Cannot create palette named "Base"';
    end

    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings then
        return false, 'Crossbar settings not found';
    end

    -- Ensure slotActions structure
    if not crossbarSettings.slotActions then
        crossbarSettings.slotActions = {};
    end

    -- Build storage key
    local baseKey = string.format('%d:%d', jobId or 1, subjobId or 0);
    local newStorageKey = M.BuildStorageKey(baseKey, paletteName);

    -- Check if palette already exists
    if crossbarSettings.slotActions[newStorageKey] then
        return false, 'Palette already exists';
    end

    -- Create empty palette structure for all combo modes
    crossbarSettings.slotActions[newStorageKey] = {};

    -- Add to crossbarPaletteOrder for this job:subjob
    if not crossbarSettings.crossbarPaletteOrder then
        crossbarSettings.crossbarPaletteOrder = {};
    end
    if not crossbarSettings.crossbarPaletteOrder[baseKey] then
        crossbarSettings.crossbarPaletteOrder[baseKey] = {};
    end
    table.insert(crossbarSettings.crossbarPaletteOrder[baseKey], paletteName);

    SaveSettingsToDisk();
    return true;
end

-- Helper: Find the actual crossbar storage key for a palette
-- Checks both current subjob key and fallback subjob=0 key
-- Returns storageKey, baseKey or nil, nil if not found
local function FindCrossbarPaletteStorageKey(paletteName, jobId, subjobId)
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings or not crossbarSettings.slotActions then
        return nil, nil;
    end

    local normalizedJobId = jobId or 1;
    local normalizedSubjobId = subjobId or 0;

    -- Try primary key first (current job:subjob)
    local baseKey = string.format('%d:%d', normalizedJobId, normalizedSubjobId);
    local storageKey = M.BuildStorageKey(baseKey, paletteName);
    if crossbarSettings.slotActions[storageKey] then
        return storageKey, baseKey;
    end

    -- Try fallback key (job:0) if subjob is not already 0
    if normalizedSubjobId ~= 0 then
        local fallbackBaseKey = string.format('%d:0', normalizedJobId);
        local fallbackStorageKey = M.BuildStorageKey(fallbackBaseKey, paletteName);
        if crossbarSettings.slotActions[fallbackStorageKey] then
            return fallbackStorageKey, fallbackBaseKey;
        end
    end

    return nil, nil;
end

-- Delete a crossbar palette
-- Returns true on success, false with error message on failure
function M.DeleteCrossbarPalette(paletteName, jobId, subjobId)
    if not paletteName then
        return false, 'No palette specified';
    end

    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings or not crossbarSettings.slotActions then
        return false, 'Palette not found';
    end

    -- Find the actual storage key (handles fallback to subjob=0)
    local storageKey, foundBaseKey = FindCrossbarPaletteStorageKey(paletteName, jobId, subjobId);
    if not storageKey then
        return false, 'Palette not found';
    end

    -- Delete the palette
    crossbarSettings.slotActions[storageKey] = nil;

    -- Remove from crossbarPaletteOrder for this job:subjob
    local baseKey = string.format('%d:%d', jobId or 1, subjobId or 0);
    if crossbarSettings.crossbarPaletteOrder and crossbarSettings.crossbarPaletteOrder[foundBaseKey] then
        for i, name in ipairs(crossbarSettings.crossbarPaletteOrder[foundBaseKey]) do
            if name == paletteName then
                table.remove(crossbarSettings.crossbarPaletteOrder[foundBaseKey], i);
                break;
            end
        end
    end

    -- If any combo mode was using this palette, switch them to Base
    if crossbarSettings.comboModeSettings then
        for comboMode, modeSettings in pairs(crossbarSettings.comboModeSettings) do
            if modeSettings.activePalette == paletteName then
                modeSettings.activePalette = nil;
            end
        end
    end

    SaveSettingsToDisk();
    return true;
end

-- Rename a crossbar palette
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

    -- Find the actual storage key for the old palette (handles fallback to subjob=0)
    local oldStorageKey, foundBaseKey = FindCrossbarPaletteStorageKey(oldName, jobId, subjobId);
    if not oldStorageKey then
        return false, 'Palette not found';
    end

    -- Build new storage key using the same base key as the found palette
    local newStorageKey = M.BuildStorageKey(foundBaseKey, newName);

    -- Check if new name already exists (check both current subjob and fallback)
    local existingKey = FindCrossbarPaletteStorageKey(newName, jobId, subjobId);
    if existingKey then
        return false, 'A palette with that name already exists';
    end

    -- Move data to new key
    crossbarSettings.slotActions[newStorageKey] = crossbarSettings.slotActions[oldStorageKey];
    crossbarSettings.slotActions[oldStorageKey] = nil;

    -- Update crossbarPaletteOrder for this job:subjob (rename the entry in place)
    if crossbarSettings.crossbarPaletteOrder and crossbarSettings.crossbarPaletteOrder[foundBaseKey] then
        for i, name in ipairs(crossbarSettings.crossbarPaletteOrder[foundBaseKey]) do
            if name == oldName then
                crossbarSettings.crossbarPaletteOrder[foundBaseKey][i] = newName;
                break;
            end
        end
    end

    -- Update active palette if any combo mode was using this palette
    if crossbarSettings.comboModeSettings then
        for comboMode, modeSettings in pairs(crossbarSettings.comboModeSettings) do
            if modeSettings.activePalette == oldName then
                modeSettings.activePalette = newName;
            end
        end
    end

    SaveSettingsToDisk();
    return true;
end

-- Move a crossbar palette up or down in the order
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

    local baseKey = string.format('%d:%d', jobId or 1, subjobId or 0);

    -- Ensure crossbarPaletteOrder exists and is populated
    if not crossbarSettings.crossbarPaletteOrder then
        crossbarSettings.crossbarPaletteOrder = {};
    end
    if not crossbarSettings.crossbarPaletteOrder[baseKey] then
        -- Initialize crossbarPaletteOrder from current available palettes
        crossbarSettings.crossbarPaletteOrder[baseKey] = {};
        local available = M.GetCrossbarAvailablePalettes(jobId, subjobId);
        for _, name in ipairs(available) do
            table.insert(crossbarSettings.crossbarPaletteOrder[baseKey], name);
        end
    end

    local order = crossbarSettings.crossbarPaletteOrder[baseKey];

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

-- Get the total number of crossbar palettes
function M.GetCrossbarPaletteCount(jobId, subjobId)
    local available = M.GetCrossbarAvailablePalettes(jobId, subjobId);
    return #available;
end

-- ============================================
-- State Management
-- ============================================

-- Reset all state
function M.Reset()
    state.activePalettes = {};
end

-- Get state for persistence (if needed)
function M.GetState()
    return {
        activePalettes = state.activePalettes,
    };
end

-- Restore state from persistence (if needed)
function M.RestoreState(savedState)
    if savedState and savedState.activePalettes then
        state.activePalettes = savedState.activePalettes;
    end
end

return M;
