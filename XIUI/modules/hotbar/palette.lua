--[[
* XIUI Hotbar - General Palette Module
* Manages user-defined named palettes for hotbars
* Works alongside petpalette.lua (pet palettes take precedence when petAware is enabled)
*
* GLOBAL PALETTE SYSTEM (v4):
* - All hotbars share ONE global palette (not per-bar)
* - Crossbar has its own single palette (not per-combo-mode)
* - Storage key format: '{jobId}:{subjobId}:palette:{name}' (subjob-specific)
* - Fallback: If no subjob-specific palettes exist, falls back to shared palettes (subjob 0)
* - tHotBar imports go to shared slot (subjob 0), accessible from any subjob
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

-- ============================================
-- Migration: Convert old format palettes to new format
-- Old format: '{jobId}:palette:{name}'
-- New format: '{jobId}:{subjobId}:palette:{name}' (with subjobId=0 for shared)
-- ============================================

local PALETTE_MIGRATION_VERSION = 2;  -- Increment when migration logic changes

-- Check if migration is needed
local function NeedsPaletteMigration()
    if not gConfig then return false; end
    local currentVersion = gConfig.hotbar and gConfig.hotbar.paletteMigrationVersion or 0;
    return currentVersion < PALETTE_MIGRATION_VERSION;
end

-- Migrate a single slotActions table from old to new format
local function MigrateSlotActions(slotActions)
    if not slotActions then return 0; end

    local keysToMigrate = {};
    local migrationCount = 0;

    -- Find old format keys: '{jobId}:palette:{name}' (2 parts before 'palette')
    for storageKey, data in pairs(slotActions) do
        if type(storageKey) == 'string' then
            -- Check for old format: jobId:palette:name (3 parts total, no subjob)
            local jobId, suffix = storageKey:match('^(%d+):(palette:.+)$');
            if jobId and suffix then
                -- This is old format - check if it's NOT new format by ensuring no subjob
                local _, subjobCheck = storageKey:match('^(%d+):(%d+):');
                if not subjobCheck then
                    -- Old format detected - migrate to new format with subjob 0
                    local newKey = string.format('%s:0:%s', jobId, suffix);
                    keysToMigrate[storageKey] = newKey;
                end
            end
        end
    end

    -- Perform migration
    for oldKey, newKey in pairs(keysToMigrate) do
        if not slotActions[newKey] then
            slotActions[newKey] = slotActions[oldKey];
            slotActions[oldKey] = nil;
            migrationCount = migrationCount + 1;
        end
    end

    return migrationCount;
end

-- Migrate palette order keys from old to new format
local function MigratePaletteOrder(paletteOrder)
    if not paletteOrder then return 0; end

    local keysToMigrate = {};
    local migrationCount = 0;

    -- Find numeric keys (old format used jobId as number)
    for key, orderList in pairs(paletteOrder) do
        if type(key) == 'number' then
            -- Old format: numeric jobId -> migrate to 'jobId:0' string
            local newKey = string.format('%d:0', key);
            keysToMigrate[key] = newKey;
        end
    end

    -- Perform migration
    for oldKey, newKey in pairs(keysToMigrate) do
        if not paletteOrder[newKey] then
            paletteOrder[newKey] = paletteOrder[oldKey];
            paletteOrder[oldKey] = nil;
            migrationCount = migrationCount + 1;
        end
    end

    return migrationCount;
end

-- Migrate activePalettePerJob keys from old to new format
local function MigrateActivePalettePerJob(activePalettePerJob)
    if not activePalettePerJob then return 0; end

    local keysToMigrate = {};
    local migrationCount = 0;

    -- Find numeric keys (old format used jobId as number)
    for key, paletteName in pairs(activePalettePerJob) do
        if type(key) == 'number' then
            -- Old format: numeric jobId -> migrate to 'jobId:0' string
            local newKey = string.format('%d:0', key);
            keysToMigrate[key] = newKey;
        end
    end

    -- Perform migration
    for oldKey, newKey in pairs(keysToMigrate) do
        if not activePalettePerJob[newKey] then
            activePalettePerJob[newKey] = activePalettePerJob[oldKey];
            activePalettePerJob[oldKey] = nil;
            migrationCount = migrationCount + 1;
        end
    end

    return migrationCount;
end

-- Run full palette migration
local function RunPaletteMigration()
    if not gConfig then return; end

    local totalMigrated = 0;

    -- Migrate hotbar slotActions
    for barIdx = 1, 6 do
        local configKey = 'hotbarBar' .. barIdx;
        local barSettings = gConfig[configKey];
        if barSettings and barSettings.slotActions then
            totalMigrated = totalMigrated + MigrateSlotActions(barSettings.slotActions);
        end
    end

    -- Migrate crossbar slotActions
    if gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.slotActions then
        totalMigrated = totalMigrated + MigrateSlotActions(gConfig.hotbarCrossbar.slotActions);
    end

    -- Migrate palette order
    if gConfig.hotbar and gConfig.hotbar.paletteOrder then
        totalMigrated = totalMigrated + MigratePaletteOrder(gConfig.hotbar.paletteOrder);
    end

    -- Migrate crossbar palette order
    if gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.crossbarPaletteOrder then
        totalMigrated = totalMigrated + MigratePaletteOrder(gConfig.hotbarCrossbar.crossbarPaletteOrder);
    end

    -- Migrate active palette per job
    if gConfig.hotbar and gConfig.hotbar.activePalettePerJob then
        totalMigrated = totalMigrated + MigrateActivePalettePerJob(gConfig.hotbar.activePalettePerJob);
    end

    -- Mark migration as complete
    if not gConfig.hotbar then
        gConfig.hotbar = {};
    end
    gConfig.hotbar.paletteMigrationVersion = PALETTE_MIGRATION_VERSION;

    if totalMigrated > 0 then
        print('[XIUI palette] Migrated ' .. totalMigrated .. ' palette entries to new subjob-aware format');
        SaveSettingsToDisk();
    end
end

-- Build job:subjob key string for palette state storage
local function BuildJobSubjobKey(jobId, subjobId)
    local normalizedJobId = jobId or 1;
    local normalizedSubjobId = subjobId or 0;
    return string.format('%d:%d', normalizedJobId, normalizedSubjobId);
end

-- Save active palette state to config (for persistence across reloads)
-- Called when palette changes to remember last-used palette per job:subjob
local function SavePaletteState(jobId, subjobId)
    if not EnsureHotbarConfigExists() then return; end
    if not gConfig.hotbar.activePalettePerJob then
        gConfig.hotbar.activePalettePerJob = {};
    end
    local key = BuildJobSubjobKey(jobId, subjobId);
    gConfig.hotbar.activePalettePerJob[key] = state.activePalette;
    -- Note: Don't call SaveSettingsToDisk() here - it will be called by the caller if needed
end

-- Load active palette state from config (for persistence across reloads)
local function LoadPaletteState(jobId, subjobId)
    if not gConfig or not gConfig.hotbar or not gConfig.hotbar.activePalettePerJob then
        return nil;
    end
    local key = BuildJobSubjobKey(jobId, subjobId);
    return gConfig.hotbar.activePalettePerJob[key];
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

-- Build full storage key for a palette (NEW FORMAT: includes subjob for subjob-specific palettes)
-- jobId: The main job ID (number)
-- subjobId: The subjob ID (number), 0 = shared/imported palettes
-- paletteName: palette name or nil for base key
-- Returns: '{jobId}:{subjobId}:palette:{name}' for palettes, or '{jobId}:{subjobId}' for base
function M.BuildPaletteStorageKey(jobId, subjobId, paletteName)
    local normalizedJobId = jobId or 1;
    local normalizedSubjobId = subjobId or 0;
    if not paletteName then
        return string.format('%d:%d', normalizedJobId, normalizedSubjobId);
    end
    return string.format('%d:%d:%s%s', normalizedJobId, normalizedSubjobId, M.PALETTE_KEY_PREFIX, paletteName);
end

-- Build storage key for shared/imported palettes (subjob 0)
-- Used by tHotBar migration and for palettes accessible from any subjob
function M.BuildSharedPaletteStorageKey(jobId, paletteName)
    return M.BuildPaletteStorageKey(jobId, 0, paletteName);
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
-- jobId: optional job ID for persistence (saves which palette was last used for this job:subjob)
-- subjobId: optional subjob ID for persistence
function M.SetActivePalette(barIndex, paletteName, jobId, subjobId)
    local oldPalette = state.activePalette;

    -- Skip if no change
    if oldPalette == paletteName then
        return false;
    end

    state.activePalette = paletteName;

    -- Save state for persistence if jobId provided
    if jobId then
        SavePaletteState(jobId, subjobId);
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

-- Helper: Scan all hotbars for palettes matching a pattern prefix
-- Returns: table of { [paletteName] = true }
local function ScanForPalettes(patternPrefix)
    local existingPalettes = {};

    for barIdx = 1, 6 do
        local configKey = 'hotbarBar' .. barIdx;
        local barSettings = gConfig and gConfig[configKey];
        if barSettings and barSettings.slotActions then
            for storageKey, _ in pairs(barSettings.slotActions) do
                if type(storageKey) == 'string' then
                    if storageKey:find(patternPrefix, 1, true) == 1 then
                        local paletteName = storageKey:sub(#patternPrefix + 1);
                        if paletteName and paletteName ~= '' then
                            existingPalettes[paletteName] = true;
                        end
                    end
                end
            end
        end
    end

    return existingPalettes;
end

-- Get list of available palette names for ALL hotbars (GLOBAL)
-- Uses NEW FORMAT: '{jobId}:{subjobId}:palette:{name}'
-- Fallback: If no subjob-specific palettes exist, falls back to shared palettes (subjob 0)
-- barIndex param kept for backwards compatibility but all bars are scanned
-- Returns: { 'Stuns', 'Heals', ... } (empty if no palettes defined)
function M.GetAvailablePalettes(barIndex, jobId, subjobId)
    local normalizedJobId = jobId or 1;
    local normalizedSubjobId = subjobId or 0;

    -- Check subjob-specific palettes first: '{jobId}:{subjobId}:palette:{name}'
    local subjobPattern = string.format('%d:%d:%s', normalizedJobId, normalizedSubjobId, M.PALETTE_KEY_PREFIX);
    local existingPalettes = ScanForPalettes(subjobPattern);

    -- Count subjob-specific palettes
    local subjobPaletteCount = 0;
    for _ in pairs(existingPalettes) do
        subjobPaletteCount = subjobPaletteCount + 1;
    end

    -- Fallback to shared palettes (subjob 0) if no subjob-specific palettes exist
    local usingFallback = false;
    if subjobPaletteCount == 0 and normalizedSubjobId ~= 0 then
        local sharedPattern = string.format('%d:0:%s', normalizedJobId, M.PALETTE_KEY_PREFIX);
        existingPalettes = ScanForPalettes(sharedPattern);
        usingFallback = true;
    end

    -- Get the stored palette order (keyed by job:subjob or fallback to job:0)
    local orderKey = BuildJobSubjobKey(normalizedJobId, normalizedSubjobId);
    local storedOrder = gConfig and gConfig.hotbar and gConfig.hotbar.paletteOrder
                        and gConfig.hotbar.paletteOrder[orderKey];

    -- If using fallback, also check for shared order
    if not storedOrder and usingFallback then
        local sharedOrderKey = BuildJobSubjobKey(normalizedJobId, 0);
        storedOrder = gConfig and gConfig.hotbar and gConfig.hotbar.paletteOrder
                      and gConfig.hotbar.paletteOrder[sharedOrderKey];
    end

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

-- Check if palettes are using fallback (shared) mode
-- Returns true if using shared palettes because no subjob-specific ones exist
function M.IsUsingFallbackPalettes(jobId, subjobId)
    local normalizedJobId = jobId or 1;
    local normalizedSubjobId = subjobId or 0;

    if normalizedSubjobId == 0 then
        return false;  -- Already using shared palettes
    end

    -- Check for subjob-specific palettes
    local subjobPattern = string.format('%d:%d:%s', normalizedJobId, normalizedSubjobId, M.PALETTE_KEY_PREFIX);
    local existingPalettes = ScanForPalettes(subjobPattern);

    for _ in pairs(existingPalettes) do
        return false;  -- Found at least one subjob-specific palette
    end

    return true;  -- Using fallback
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
    M.SetActivePalette(barIndex, newPalette, jobId, subjobId);  -- Pass jobId and subjobId for persistence

    return newPalette;
end

-- ============================================
-- Palette CRUD Operations
-- ============================================

-- Helper: Find the actual storage key for a palette
-- Uses NEW format: '{jobId}:{subjobId}:palette:{name}'
-- Falls back to shared key '{jobId}:0:palette:{name}' if subjob-specific not found
-- Returns storageKey or nil if not found
local function FindPaletteStorageKey(barIndex, paletteName, jobId, subjobId)
    local configKey = 'hotbarBar' .. barIndex;
    local barSettings = gConfig and gConfig[configKey];
    if not barSettings or not barSettings.slotActions then
        return nil;
    end

    local normalizedJobId = jobId or 1;
    local normalizedSubjobId = subjobId or 0;

    -- Try subjob-specific key first: '{jobId}:{subjobId}:palette:{name}'
    local storageKey = M.BuildPaletteStorageKey(normalizedJobId, normalizedSubjobId, paletteName);
    if barSettings.slotActions[storageKey] then
        return storageKey;
    end

    -- Fallback to shared key: '{jobId}:0:palette:{name}'
    if normalizedSubjobId ~= 0 then
        local sharedKey = M.BuildPaletteStorageKey(normalizedJobId, 0, paletteName);
        if barSettings.slotActions[sharedKey] then
            return sharedKey;
        end
    end

    return nil;
end

-- Create a new palette (GLOBAL - creates empty palette entries on all bars)
-- Uses NEW key format: '{jobId}:{subjobId}:palette:{name}'
-- barIndex param kept for backwards compatibility
-- Returns true on success, false with error message on failure
function M.CreatePalette(barIndex, paletteName, jobId, subjobId)
    if not IsValidPaletteName(paletteName) then
        return false, 'Invalid palette name';
    end

    local normalizedJobId = jobId or 1;
    local normalizedSubjobId = subjobId or 0;

    -- Build new format storage key: '{jobId}:{subjobId}:palette:{name}'
    local newStorageKey = M.BuildPaletteStorageKey(normalizedJobId, normalizedSubjobId, paletteName);

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

    -- Store palette order keyed by job:subjob
    local orderKey = BuildJobSubjobKey(normalizedJobId, normalizedSubjobId);
    if not gConfig.hotbar then
        gConfig.hotbar = {};
    end
    if not gConfig.hotbar.paletteOrder then
        gConfig.hotbar.paletteOrder = {};
    end
    if not gConfig.hotbar.paletteOrder[orderKey] then
        gConfig.hotbar.paletteOrder[orderKey] = {};
    end
    table.insert(gConfig.hotbar.paletteOrder[orderKey], paletteName);

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
        -- No palettes exist, create the default one at subjob 0 (shared)
        -- This ensures imported data at subjob 0 isn't shadowed by empty subjob-specific palettes
        local success, err = M.CreatePalette(1, M.DEFAULT_PALETTE_NAME, normalizedJobId, 0);
        if success then
            return M.DEFAULT_PALETTE_NAME;
        else
            -- If "Default" already exists somehow, try numbered names
            for i = 1, 99 do
                local name = 'Palette ' .. i;
                success, err = M.CreatePalette(1, name, normalizedJobId, 0);
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
-- NOTE: Cannot delete the last palette - at least one must always exist
-- Returns true on success, false with error message on failure
function M.DeletePalette(barIndex, paletteName, jobId, subjobId)
    if not paletteName then
        return false, 'No palette specified';
    end

    local normalizedJobId = jobId or 1;
    local normalizedSubjobId = subjobId or 0;

    -- Check if this is the last palette - cannot delete if so
    local availablePalettes = M.GetAvailablePalettes(barIndex, normalizedJobId, normalizedSubjobId);
    if #availablePalettes <= 1 then
        return false, 'Cannot delete the last palette';
    end

    -- Find the storage key (could be subjob-specific or shared)
    local storageKey = FindPaletteStorageKey(1, paletteName, normalizedJobId, normalizedSubjobId);
    if not storageKey then
        return false, 'Palette not found';
    end

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

    -- Determine which order key to use based on the storage key found
    local orderKey;
    local keyJobId, keySubjobId = storageKey:match('^(%d+):(%d+):');
    if keyJobId and keySubjobId then
        orderKey = BuildJobSubjobKey(tonumber(keyJobId), tonumber(keySubjobId));
    else
        orderKey = BuildJobSubjobKey(normalizedJobId, normalizedSubjobId);
    end

    -- Remove from paletteOrder
    if gConfig.hotbar and gConfig.hotbar.paletteOrder and gConfig.hotbar.paletteOrder[orderKey] then
        for i, name in ipairs(gConfig.hotbar.paletteOrder[orderKey]) do
            if name == paletteName then
                table.remove(gConfig.hotbar.paletteOrder[orderKey], i);
                break;
            end
        end
    end

    -- If this was the active palette, switch to the first available palette
    if state.activePalette == paletteName then
        -- Get updated list after deletion
        local remainingPalettes = M.GetAvailablePalettes(barIndex, normalizedJobId, normalizedSubjobId);
        local newActive = remainingPalettes[1];  -- First palette becomes active
        M.SetActivePalette(1, newActive, normalizedJobId, normalizedSubjobId);
    end

    SaveSettingsToDisk();
    return true;
end

-- Rename a palette (GLOBAL - renames across all bars)
-- barIndex param kept for backwards compatibility but ignored
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
    local normalizedSubjobId = subjobId or 0;

    -- Find the old storage key (could be subjob-specific or shared)
    local oldStorageKey = FindPaletteStorageKey(1, oldName, normalizedJobId, normalizedSubjobId);
    if not oldStorageKey then
        return false, 'Palette not found';
    end

    -- Extract the subjobId from the old storage key to build new key with same subjob
    local keyJobId, keySubjobId = oldStorageKey:match('^(%d+):(%d+):');
    local effectiveSubjobId = keySubjobId and tonumber(keySubjobId) or normalizedSubjobId;

    -- Build new storage key with same subjob as the old key
    local newStorageKey = M.BuildPaletteStorageKey(normalizedJobId, effectiveSubjobId, newName);

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

    -- Update paletteOrder (rename entry in place)
    local orderKey = BuildJobSubjobKey(normalizedJobId, effectiveSubjobId);
    if gConfig.hotbar and gConfig.hotbar.paletteOrder and gConfig.hotbar.paletteOrder[orderKey] then
        for i, name in ipairs(gConfig.hotbar.paletteOrder[orderKey]) do
            if name == oldName then
                gConfig.hotbar.paletteOrder[orderKey][i] = newName;
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
    local normalizedSubjobId = subjobId or 0;

    -- If using fallback palettes, modify the shared order (subjob 0) instead
    local effectiveSubjobId = normalizedSubjobId;
    if normalizedSubjobId ~= 0 and M.IsUsingFallbackPalettes(normalizedJobId, normalizedSubjobId) then
        effectiveSubjobId = 0;
    end
    local orderKey = BuildJobSubjobKey(normalizedJobId, effectiveSubjobId);

    -- Ensure paletteOrder exists and is populated
    if not gConfig.hotbar then
        gConfig.hotbar = {};
    end
    if not gConfig.hotbar.paletteOrder then
        gConfig.hotbar.paletteOrder = {};
    end
    if not gConfig.hotbar.paletteOrder[orderKey] then
        -- Initialize paletteOrder from current available palettes
        gConfig.hotbar.paletteOrder[orderKey] = {};
        local available = M.GetAvailablePalettes(barIndex, jobId, subjobId);
        for _, name in ipairs(available) do
            table.insert(gConfig.hotbar.paletteOrder[orderKey], name);
        end
    end

    local order = gConfig.hotbar.paletteOrder[orderKey];

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
-- palettes: array of palette names in desired order (excluding Base)
-- Returns true on success, false with error message on failure
function M.SetPaletteOrder(barIndex, palettes, jobId, subjobId)
    if not palettes or type(palettes) ~= 'table' then
        return false, 'Invalid palette list';
    end

    local normalizedJobId = jobId or 1;
    local normalizedSubjobId = subjobId or 0;
    local orderKey = BuildJobSubjobKey(normalizedJobId, normalizedSubjobId);

    -- Ensure paletteOrder exists
    if not gConfig.hotbar then
        gConfig.hotbar = {};
    end
    if not gConfig.hotbar.paletteOrder then
        gConfig.hotbar.paletteOrder = {};
    end

    -- Set the new order directly
    gConfig.hotbar.paletteOrder[orderKey] = {};
    for _, name in ipairs(palettes) do
        table.insert(gConfig.hotbar.paletteOrder[orderKey], name);
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

-- Helper: Scan crossbar for palettes matching a pattern prefix
-- Returns: table of { [paletteName] = true }
local function ScanCrossbarForPalettes(patternPrefix)
    local existingPalettes = {};

    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings or not crossbarSettings.slotActions then
        return existingPalettes;
    end

    for storageKey, _ in pairs(crossbarSettings.slotActions) do
        if type(storageKey) == 'string' then
            if storageKey:find(patternPrefix, 1, true) == 1 then
                local paletteName = storageKey:sub(#patternPrefix + 1);
                if paletteName and paletteName ~= '' then
                    existingPalettes[paletteName] = true;
                end
            end
        end
    end

    return existingPalettes;
end

-- Get all available palette names for crossbar only
-- Uses NEW FORMAT: '{jobId}:{subjobId}:palette:{name}'
-- Fallback: If no subjob-specific palettes exist, falls back to shared palettes (subjob 0)
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

    -- Check subjob-specific palettes first: '{jobId}:{subjobId}:palette:{name}'
    local subjobPattern = string.format('%d:%d:%s', normalizedJobId, normalizedSubjobId, M.PALETTE_KEY_PREFIX);
    local existingPalettes = ScanCrossbarForPalettes(subjobPattern);

    -- Count subjob-specific palettes
    local subjobPaletteCount = 0;
    for _ in pairs(existingPalettes) do
        subjobPaletteCount = subjobPaletteCount + 1;
    end

    -- Fallback to shared palettes (subjob 0) if no subjob-specific palettes exist
    local usingFallback = false;
    if subjobPaletteCount == 0 and normalizedSubjobId ~= 0 then
        local sharedPattern = string.format('%d:0:%s', normalizedJobId, M.PALETTE_KEY_PREFIX);
        existingPalettes = ScanCrossbarForPalettes(sharedPattern);
        usingFallback = true;
    end

    -- Get the stored palette order (keyed by job:subjob or fallback to job:0)
    local orderKey = BuildJobSubjobKey(normalizedJobId, normalizedSubjobId);
    local storedOrder = crossbarSettings.crossbarPaletteOrder and crossbarSettings.crossbarPaletteOrder[orderKey];

    -- If using fallback, also check for shared order
    if not storedOrder and usingFallback then
        local sharedOrderKey = BuildJobSubjobKey(normalizedJobId, 0);
        storedOrder = crossbarSettings.crossbarPaletteOrder and crossbarSettings.crossbarPaletteOrder[sharedOrderKey];
    end

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

-- Check if crossbar palettes are using fallback (shared) mode
-- Returns true if using shared palettes because no subjob-specific ones exist
function M.IsUsingCrossbarFallbackPalettes(jobId, subjobId)
    local normalizedJobId = jobId or 1;
    local normalizedSubjobId = subjobId or 0;

    if normalizedSubjobId == 0 then
        return false;  -- Already using shared palettes
    end

    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings or not crossbarSettings.slotActions then
        return true;  -- No settings, would use fallback
    end

    -- Check for subjob-specific palettes
    local subjobPattern = string.format('%d:%d:%s', normalizedJobId, normalizedSubjobId, M.PALETTE_KEY_PREFIX);
    for storageKey, _ in pairs(crossbarSettings.slotActions) do
        if type(storageKey) == 'string' and storageKey:find(subjobPattern, 1, true) == 1 then
            return false;  -- Found at least one subjob-specific palette
        end
    end

    return true;  -- Using fallback
end

-- Unified fallback check for both hotbar and crossbar
-- paletteType: 'hotbar' or 'crossbar'
function M.IsUsingFallback(jobId, subjobId, paletteType)
    if subjobId == 0 then return false; end
    if paletteType == 'crossbar' then
        return M.IsUsingCrossbarFallbackPalettes(jobId, subjobId);
    else
        return M.IsUsingFallbackPalettes(jobId, subjobId);
    end
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
-- Uses NEW FORMAT: '{jobId}:{subjobId}:palette:{name}'
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
    local normalizedSubjobId = subjobId or 0;

    -- Build NEW format storage key: '{jobId}:{subjobId}:palette:{name}'
    local storageKey = M.BuildPaletteStorageKey(normalizedJobId, normalizedSubjobId, paletteName);

    -- Check if palette already exists
    if crossbarSettings.slotActions[storageKey] then
        return false, 'Palette already exists';
    end

    -- Create empty palette structure for all combo modes
    crossbarSettings.slotActions[storageKey] = {};

    -- Add to crossbarPaletteOrder (keyed by job:subjob)
    local orderKey = BuildJobSubjobKey(normalizedJobId, normalizedSubjobId);
    if not crossbarSettings.crossbarPaletteOrder then
        crossbarSettings.crossbarPaletteOrder = {};
    end
    if not crossbarSettings.crossbarPaletteOrder[orderKey] then
        crossbarSettings.crossbarPaletteOrder[orderKey] = {};
    end
    table.insert(crossbarSettings.crossbarPaletteOrder[orderKey], paletteName);

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
        -- No palettes exist, create the default one at subjob 0 (shared)
        -- This ensures imported data at subjob 0 isn't shadowed by empty subjob-specific palettes
        local success, err = M.CreateCrossbarPalette(M.DEFAULT_PALETTE_NAME, normalizedJobId, 0);
        if success then
            -- Auto-activate the new palette
            M.SetActivePaletteForCombo('L2', M.DEFAULT_PALETTE_NAME);
            return M.DEFAULT_PALETTE_NAME;
        else
            -- If "Default" already exists somehow, try numbered names
            for i = 1, 99 do
                local name = 'Palette ' .. i;
                success, err = M.CreateCrossbarPalette(name, normalizedJobId, 0);
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
-- Uses NEW FORMAT: '{jobId}:{subjobId}:palette:{name}'
-- Falls back to shared key '{jobId}:0:palette:{name}' if subjob-specific not found
-- Returns storageKey or nil if not found
local function FindCrossbarPaletteStorageKey(paletteName, jobId, subjobId)
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings or not crossbarSettings.slotActions then
        return nil;
    end

    local normalizedJobId = jobId or 1;
    local normalizedSubjobId = subjobId or 0;

    -- Try subjob-specific key first: '{jobId}:{subjobId}:palette:{name}'
    local storageKey = M.BuildPaletteStorageKey(normalizedJobId, normalizedSubjobId, paletteName);
    if crossbarSettings.slotActions[storageKey] then
        return storageKey;
    end

    -- Fallback to shared key: '{jobId}:0:palette:{name}'
    if normalizedSubjobId ~= 0 then
        local sharedKey = M.BuildPaletteStorageKey(normalizedJobId, 0, paletteName);
        if crossbarSettings.slotActions[sharedKey] then
            return sharedKey;
        end
    end

    return nil;
end

-- Delete a crossbar palette
-- Uses NEW FORMAT: '{jobId}:{subjobId}:palette:{name}'
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
    local normalizedSubjobId = subjobId or 0;

    -- Find the storage key (could be subjob-specific or shared)
    local storageKey = FindCrossbarPaletteStorageKey(paletteName, jobId, subjobId);
    if not storageKey then
        return false, 'Palette not found';
    end

    -- Delete the palette
    crossbarSettings.slotActions[storageKey] = nil;

    -- Determine which order key to use based on the storage key found
    local orderKey;
    local keyJobId, keySubjobId = storageKey:match('^(%d+):(%d+):');
    if keyJobId and keySubjobId then
        orderKey = BuildJobSubjobKey(tonumber(keyJobId), tonumber(keySubjobId));
    else
        orderKey = BuildJobSubjobKey(normalizedJobId, normalizedSubjobId);
    end

    -- Remove from crossbarPaletteOrder
    if crossbarSettings.crossbarPaletteOrder and crossbarSettings.crossbarPaletteOrder[orderKey] then
        for i, name in ipairs(crossbarSettings.crossbarPaletteOrder[orderKey]) do
            if name == paletteName then
                table.remove(crossbarSettings.crossbarPaletteOrder[orderKey], i);
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
-- Uses NEW FORMAT: '{jobId}:{subjobId}:palette:{name}'
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
    local normalizedSubjobId = subjobId or 0;

    -- Find the storage key for the old palette (could be subjob-specific or shared)
    local oldStorageKey = FindCrossbarPaletteStorageKey(oldName, jobId, subjobId);
    if not oldStorageKey then
        return false, 'Palette not found';
    end

    -- Extract the subjobId from the old storage key to build new key with same subjob
    local keyJobId, keySubjobId = oldStorageKey:match('^(%d+):(%d+):');
    local effectiveSubjobId = keySubjobId and tonumber(keySubjobId) or normalizedSubjobId;

    -- Build new storage key using same subjob as the old key
    local newStorageKey = M.BuildPaletteStorageKey(normalizedJobId, effectiveSubjobId, newName);

    -- Check if new name already exists
    local existingKey = FindCrossbarPaletteStorageKey(newName, jobId, subjobId);
    if existingKey then
        return false, 'A palette with that name already exists';
    end

    -- Move data to new key
    crossbarSettings.slotActions[newStorageKey] = crossbarSettings.slotActions[oldStorageKey];
    crossbarSettings.slotActions[oldStorageKey] = nil;

    -- Update crossbarPaletteOrder
    local orderKey = BuildJobSubjobKey(normalizedJobId, effectiveSubjobId);
    if crossbarSettings.crossbarPaletteOrder and crossbarSettings.crossbarPaletteOrder[orderKey] then
        for i, name in ipairs(crossbarSettings.crossbarPaletteOrder[orderKey]) do
            if name == oldName then
                crossbarSettings.crossbarPaletteOrder[orderKey][i] = newName;
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
-- Uses NEW FORMAT: crossbarPaletteOrder keyed by job:subjob
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
    local normalizedSubjobId = subjobId or 0;

    -- If using fallback palettes, modify the shared order (subjob 0) instead
    local effectiveSubjobId = normalizedSubjobId;
    if normalizedSubjobId ~= 0 and M.IsUsingCrossbarFallbackPalettes(normalizedJobId, normalizedSubjobId) then
        effectiveSubjobId = 0;
    end
    local orderKey = BuildJobSubjobKey(normalizedJobId, effectiveSubjobId);

    -- Ensure crossbarPaletteOrder exists and is populated
    if not crossbarSettings.crossbarPaletteOrder then
        crossbarSettings.crossbarPaletteOrder = {};
    end
    if not crossbarSettings.crossbarPaletteOrder[orderKey] then
        -- Initialize crossbarPaletteOrder from current available palettes
        crossbarSettings.crossbarPaletteOrder[orderKey] = {};
        local available = M.GetCrossbarAvailablePalettes(jobId, subjobId);
        for _, name in ipairs(available) do
            table.insert(crossbarSettings.crossbarPaletteOrder[orderKey], name);
        end
    end

    local order = crossbarSettings.crossbarPaletteOrder[orderKey];

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

    -- Run migration if needed (converts old format palettes to new subjob-aware format)
    if NeedsPaletteMigration() then
        RunPaletteMigration();
    end

    -- Ensure at least one palette exists for this job
    local firstPalette = M.EnsureDefaultPaletteExists(jobId, subjobId);
    if not firstPalette then
        print('[XIUI palette] Warning: Failed to create default palette for job ' .. tostring(jobId));
        return;
    end

    -- Get available palettes
    local availablePalettes = M.GetAvailablePalettes(1, jobId, subjobId);

    -- Try to restore saved palette state for this job:subjob
    local savedPalette = LoadPaletteState(jobId, subjobId);

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

-- ============================================
-- Palette Copy/Move Operations (for Palette Manager)
-- ============================================

-- Copy a hotbar palette to a different job:subjob combination
-- Returns true on success, false with error message on failure
function M.CopyPalette(paletteName, fromJobId, fromSubjobId, toJobId, toSubjobId, newName)
    if not paletteName then
        return false, 'No palette specified';
    end

    local destName = newName or paletteName;
    if not IsValidPaletteName(destName) then
        return false, 'Invalid destination palette name';
    end

    -- Find source storage key
    local sourceKey = FindPaletteStorageKey(1, paletteName, fromJobId, fromSubjobId);
    if not sourceKey then
        return false, 'Source palette not found';
    end

    -- Build destination storage key
    local destKey = M.BuildPaletteStorageKey(toJobId, toSubjobId, destName);

    -- Check if destination already exists
    for barIdx = 1, 6 do
        local configKey = 'hotbarBar' .. barIdx;
        local barSettings = gConfig and gConfig[configKey];
        if barSettings and barSettings.slotActions and barSettings.slotActions[destKey] then
            return false, 'Palette already exists at destination';
        end
    end

    -- Copy palette data to all bars
    for barIdx = 1, 6 do
        local configKey = 'hotbarBar' .. barIdx;
        local barSettings = gConfig and gConfig[configKey];
        if barSettings then
            if not barSettings.slotActions then
                barSettings.slotActions = {};
            end
            -- Deep copy slot data
            local sourceData = barSettings.slotActions[sourceKey];
            if sourceData then
                local copiedData = {};
                for slotIdx, slotData in pairs(sourceData) do
                    if type(slotData) == 'table' then
                        copiedData[slotIdx] = {};
                        for k, v in pairs(slotData) do
                            copiedData[slotIdx][k] = v;
                        end
                    else
                        copiedData[slotIdx] = slotData;
                    end
                end
                barSettings.slotActions[destKey] = copiedData;
            else
                barSettings.slotActions[destKey] = {};
            end
        end
    end

    -- Add to destination's palette order
    local destOrderKey = BuildJobSubjobKey(toJobId, toSubjobId);
    if not gConfig.hotbar then
        gConfig.hotbar = {};
    end
    if not gConfig.hotbar.paletteOrder then
        gConfig.hotbar.paletteOrder = {};
    end
    if not gConfig.hotbar.paletteOrder[destOrderKey] then
        gConfig.hotbar.paletteOrder[destOrderKey] = {};
    end
    table.insert(gConfig.hotbar.paletteOrder[destOrderKey], destName);

    SaveSettingsToDisk();
    return true;
end

-- Copy a crossbar palette to a different job:subjob combination
-- Returns true on success, false with error message on failure
function M.CopyCrossbarPalette(paletteName, fromJobId, fromSubjobId, toJobId, toSubjobId, newName)
    if not paletteName then
        return false, 'No palette specified';
    end

    local destName = newName or paletteName;
    if not IsValidPaletteName(destName) then
        return false, 'Invalid destination palette name';
    end

    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings then
        return false, 'Crossbar settings not found';
    end

    -- Find source storage key
    local sourceKey = FindCrossbarPaletteStorageKey(paletteName, fromJobId, fromSubjobId);
    if not sourceKey then
        return false, 'Source palette not found';
    end

    -- Build destination storage key
    local destKey = M.BuildPaletteStorageKey(toJobId, toSubjobId, destName);

    -- Check if destination already exists
    if crossbarSettings.slotActions and crossbarSettings.slotActions[destKey] then
        return false, 'Palette already exists at destination';
    end

    -- Ensure slotActions structure
    if not crossbarSettings.slotActions then
        crossbarSettings.slotActions = {};
    end

    -- Deep copy slot data
    local sourceData = crossbarSettings.slotActions[sourceKey];
    if sourceData then
        local copiedData = {};
        for comboMode, modeData in pairs(sourceData) do
            if type(modeData) == 'table' then
                copiedData[comboMode] = {};
                for slotIdx, slotData in pairs(modeData) do
                    if type(slotData) == 'table' then
                        copiedData[comboMode][slotIdx] = {};
                        for k, v in pairs(slotData) do
                            copiedData[comboMode][slotIdx][k] = v;
                        end
                    else
                        copiedData[comboMode][slotIdx] = slotData;
                    end
                end
            else
                copiedData[comboMode] = modeData;
            end
        end
        crossbarSettings.slotActions[destKey] = copiedData;
    else
        crossbarSettings.slotActions[destKey] = {};
    end

    -- Add to destination's palette order
    local destOrderKey = BuildJobSubjobKey(toJobId, toSubjobId);
    if not crossbarSettings.crossbarPaletteOrder then
        crossbarSettings.crossbarPaletteOrder = {};
    end
    if not crossbarSettings.crossbarPaletteOrder[destOrderKey] then
        crossbarSettings.crossbarPaletteOrder[destOrderKey] = {};
    end
    table.insert(crossbarSettings.crossbarPaletteOrder[destOrderKey], destName);

    SaveSettingsToDisk();
    return true;
end

-- Get all job IDs that have palettes defined
function M.GetJobsWithPalettes()
    local jobs = {};
    local seenJobs = {};

    -- Scan hotbar palettes
    for barIdx = 1, 6 do
        local configKey = 'hotbarBar' .. barIdx;
        local barSettings = gConfig and gConfig[configKey];
        if barSettings and barSettings.slotActions then
            for storageKey, _ in pairs(barSettings.slotActions) do
                if type(storageKey) == 'string' then
                    local jobIdStr = storageKey:match('^(%d+):');
                    if jobIdStr then
                        local jobId = tonumber(jobIdStr);
                        if jobId and not seenJobs[jobId] then
                            seenJobs[jobId] = true;
                            table.insert(jobs, jobId);
                        end
                    end
                end
            end
        end
    end

    -- Sort jobs by ID
    table.sort(jobs);
    return jobs;
end

-- Get all subjob IDs for a given job that have palettes defined
function M.GetSubjobsWithPalettes(jobId)
    local subjobs = {};
    local seenSubjobs = {};
    local normalizedJobId = jobId or 1;

    -- Scan hotbar palettes
    for barIdx = 1, 6 do
        local configKey = 'hotbarBar' .. barIdx;
        local barSettings = gConfig and gConfig[configKey];
        if barSettings and barSettings.slotActions then
            for storageKey, _ in pairs(barSettings.slotActions) do
                if type(storageKey) == 'string' then
                    local keyJobId, keySubjobId = storageKey:match('^(%d+):(%d+):');
                    if keyJobId and keySubjobId and tonumber(keyJobId) == normalizedJobId then
                        local subjobId = tonumber(keySubjobId);
                        if subjobId and not seenSubjobs[subjobId] then
                            seenSubjobs[subjobId] = true;
                            table.insert(subjobs, subjobId);
                        end
                    end
                end
            end
        end
    end

    -- Sort subjobs by ID (0 = shared comes first)
    table.sort(subjobs);
    return subjobs;
end

-- ============================================
-- Delete All Subjob Palettes (for "Use Shared Library" feature)
-- ============================================

-- Delete all subjob-specific hotbar palettes for a job/subjob combination
-- This allows reverting to using the shared library (subjob 0) palettes
-- Returns true on success
function M.DeleteAllSubjobPalettes(jobId, subjobId)
    if not subjobId or subjobId == 0 then
        return false;  -- Can't delete shared palettes this way
    end

    local normalizedJobId = jobId or 1;
    local pattern = string.format('%d:%d:%s', normalizedJobId, subjobId, M.PALETTE_KEY_PREFIX);
    local deletedCount = 0;

    -- Delete from all hotbars
    for barIdx = 1, 6 do
        local configKey = 'hotbarBar' .. barIdx;
        local barSettings = gConfig and gConfig[configKey];
        if barSettings and barSettings.slotActions then
            local keysToDelete = {};
            for storageKey, _ in pairs(barSettings.slotActions) do
                if type(storageKey) == 'string' and storageKey:find(pattern, 1, true) == 1 then
                    table.insert(keysToDelete, storageKey);
                end
            end
            for _, key in ipairs(keysToDelete) do
                barSettings.slotActions[key] = nil;
                deletedCount = deletedCount + 1;
            end
        end
    end

    -- Clear palette order for this subjob
    local orderKey = BuildJobSubjobKey(normalizedJobId, subjobId);
    if gConfig.hotbar and gConfig.hotbar.paletteOrder then
        gConfig.hotbar.paletteOrder[orderKey] = nil;
    end

    -- Clear active palette per job for this subjob
    if gConfig.hotbar and gConfig.hotbar.activePalettePerJob then
        gConfig.hotbar.activePalettePerJob[orderKey] = nil;
    end

    -- Reset active palette to pick up from shared library
    if state.activePalette then
        local oldPalette = state.activePalette;
        state.activePalette = nil;
        -- The next call to ValidatePalettesForJob will set up shared library
        for i = 1, 6 do
            M.FirePaletteChangedCallbacks(i, oldPalette, nil);
        end
    end

    if deletedCount > 0 then
        SaveSettingsToDisk();
    end

    return true;
end

-- Delete all subjob-specific crossbar palettes for a job/subjob combination
-- This allows reverting to using the shared library (subjob 0) palettes
-- Returns true on success
function M.DeleteAllCrossbarSubjobPalettes(jobId, subjobId)
    if not subjobId or subjobId == 0 then
        return false;  -- Can't delete shared palettes this way
    end

    local normalizedJobId = jobId or 1;
    local pattern = string.format('%d:%d:%s', normalizedJobId, subjobId, M.PALETTE_KEY_PREFIX);
    local deletedCount = 0;

    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if crossbarSettings and crossbarSettings.slotActions then
        local keysToDelete = {};
        for storageKey, _ in pairs(crossbarSettings.slotActions) do
            if type(storageKey) == 'string' and storageKey:find(pattern, 1, true) == 1 then
                table.insert(keysToDelete, storageKey);
            end
        end
        for _, key in ipairs(keysToDelete) do
            crossbarSettings.slotActions[key] = nil;
            deletedCount = deletedCount + 1;
        end

        -- Clear crossbar palette order for this subjob
        local orderKey = BuildJobSubjobKey(normalizedJobId, subjobId);
        if crossbarSettings.crossbarPaletteOrder then
            crossbarSettings.crossbarPaletteOrder[orderKey] = nil;
        end
    end

    -- Reset active crossbar palette to pick up from shared library
    if state.crossbarActivePalette then
        local oldPalette = state.crossbarActivePalette;
        state.crossbarActivePalette = nil;
        -- Fire callbacks for all combo modes
        for _, mode in ipairs(CROSSBAR_COMBO_MODES) do
            M.FirePaletteChangedCallbacks('crossbar:' .. mode, oldPalette, nil);
        end
    end

    if deletedCount > 0 then
        SaveSettingsToDisk();
    end

    return true;
end

return M;
