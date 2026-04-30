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
-- All-jobs crossbar palettes (slotActions key prefix: global:palette:{name})
M.UNIVERSAL_CROSSBAR_PREFIX = 'global:palette:';

-- Deferred save state for palette selection changes
-- Instead of saving immediately, track dirty state and save at natural pause points
local paletteStateDirty = false;

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

    -- All-jobs universal crossbar sets (enableUniversalCrossbarPalettes in config)
    crossbarPaletteScope = 'job', -- 'job' | 'universal'
    crossbarActiveUniversalPalette = nil,

    -- Job-scope crossbar: which storage tier is active — 0 = Job-wide (all subjobs), N = that subjob only
    -- Only meaningful when the character has a support job (live subjob ~= 0)
    crossbarActiveStorageSubjob = nil,

    -- Callbacks for palette change events
    onPaletteChangedCallbacks = {},
};

-- Pending: profile/gConfig was swapped before player job was readable (addon startup). Consumed by hotbar init.
local pendingApplyDefaultCrossbarScopeFromProfile = false;

function M.NotifyProfileSettingsLoaded()
    pendingApplyDefaultCrossbarScopeFromProfile = true;
end

function M.ConsumePendingApplyDefaultCrossbarScopeFromProfile()
    if pendingApplyDefaultCrossbarScopeFromProfile then
        pendingApplyDefaultCrossbarScopeFromProfile = false;
        return true;
    end
    return false;
end

-- After hotbarCrossbar exists: seed one blank Job [J] Default palette per job (1–22) without touching live active palette.
local crossbarBlankDefaultsSeeded = false;

-- ============================================
-- Performance: Palette List Cache
-- ============================================
-- Caches GetAvailablePalettes results to avoid ~11,100 iterations/frame in config UI
-- Uses TTL-based invalidation for freshness

local paletteListCache = {};  -- paletteListCache[cacheKey] = { palettes, timestamp }
local crossbarPaletteListCache = {};  -- crossbarPaletteListCache[cacheKey] = { palettes, timestamp }
local PALETTE_CACHE_TTL = 0.5;  -- 500ms cache validity

local function BuildPaletteCacheKey(jobId, subjobId)
    return string.format('%d:%d', jobId or 1, subjobId or 0);
end

local function InvalidatePaletteListCache()
    paletteListCache = {};
    crossbarPaletteListCache = {};
end

-- Prefer the palette that was next in list after delete (below), else above (typical "stay nearby" UX)
local function PickNeighborPaletteName(orderedList, deletedName)
    if not orderedList or not deletedName then
        return nil;
    end
    local idx = nil;
    for i, n in ipairs(orderedList) do
        if n == deletedName then
            idx = i;
            break;
        end
    end
    if not idx then
        return nil;
    end
    if orderedList[idx + 1] then
        return orderedList[idx + 1];
    end
    if orderedList[idx - 1] then
        return orderedList[idx - 1];
    end
    return nil;
end

-- Token for GetCrossbarAvailablePalettes when live subjob ~= 0: tier + palette name (names cannot contain ':')
local CROSSBAR_ENTRY_SEP = '\1';

function M.EncodeCrossbarEntryToken(storageSubjob, name)
    return tostring(storageSubjob or 0) .. CROSSBAR_ENTRY_SEP .. (name or '');
end

-- Returns storageSubjob, name or nil, plainToken if not an encoded entry
function M.DecodeCrossbarEntryToken(token)
    if not token or type(token) ~= 'string' then
        return nil, nil;
    end
    local st, name = token:match('^(%d+)' .. CROSSBAR_ENTRY_SEP .. '(.+)$');
    if st then
        return tonumber(st), name;
    end
    return nil, token;
end

-- Display suffix: Job-wide vs Subjob-specific tier (not Global [G], which is separate scope)
function M.FormatCrossbarTierSuffixLabel(storageSubjob, liveSubjobId)
    local live = liveSubjobId or 0;
    if live == 0 then
        return ' (J)';
    end
    if (storageSubjob or 0) == 0 then
        return ' (J)';
    end
    return ' (SJ)';
end

-- Crossbar combo modes (single list for callbacks / universal scope)
local CROSSBAR_COMBO_MODES = { 'L2', 'R2', 'L2R2', 'R2L2', 'L2x2', 'R2x2' };

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
    paletteStateDirty = true;  -- Mark for deferred save
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

-- Key for hotbar RB-cycle exclude map: matches palette order when using shared fallback (subjob 0)
local function GetEffectiveHotbarPaletteMetaKey(jobId, subjobId)
    local jid = jobId or 1;
    local sj = subjobId or 0;
    if sj ~= 0 and M.IsUsingFallbackPalettes(jid, sj) then
        return BuildJobSubjobKey(jid, 0);
    end
    return BuildJobSubjobKey(jid, sj);
end

local function PrunePaletteExcludeSubtable(root, key)
    if not root or not root[key] then
        return;
    end
    local empty = true;
    for _ in pairs(root[key]) do
        empty = false;
        break;
    end
    if empty then
        root[key] = nil;
    end
end

-- When true, palette is included in RB+D-pad / keyboard palette cycling for hotbars
function M.IsHotbarPaletteInRbCycle(jobId, subjobId, paletteName)
    if not paletteName then
        return true;
    end
    local key = GetEffectiveHotbarPaletteMetaKey(jobId, subjobId);
    local t = gConfig and gConfig.hotbar and gConfig.hotbar.paletteExcludeFromCycle and gConfig.hotbar.paletteExcludeFromCycle[key];
    if t and t[paletteName] then
        return false;
    end
    return true;
end

function M.SetHotbarPaletteInRbCycle(jobId, subjobId, paletteName, inCycle)
    if not paletteName or not IsValidPaletteName(paletteName) then
        return false, 'Invalid palette name';
    end
    if not EnsureHotbarConfigExists() then
        return false, 'Config unavailable';
    end
    if not gConfig.hotbar.paletteExcludeFromCycle then
        gConfig.hotbar.paletteExcludeFromCycle = {};
    end
    local key = GetEffectiveHotbarPaletteMetaKey(jobId, subjobId);
    if not gConfig.hotbar.paletteExcludeFromCycle[key] then
        gConfig.hotbar.paletteExcludeFromCycle[key] = {};
    end
    local ex = gConfig.hotbar.paletteExcludeFromCycle[key];
    if inCycle then
        ex[paletteName] = nil;
        PrunePaletteExcludeSubtable(gConfig.hotbar.paletteExcludeFromCycle, key);
    else
        ex[paletteName] = true;
    end
    SaveSettingsToDisk();
    return true;
end

-- Job crossbar (non-universal): per storage tier orderKey job:tier
function M.IsCrossbarPaletteInRbCycle(jobId, tierStorageSubjob, paletteName)
    if not paletteName then
        return true;
    end
    local key = BuildJobSubjobKey(jobId or 1, tierStorageSubjob or 0);
    local cbs = gConfig.hotbarCrossbar;
    local t = cbs and cbs.crossbarPaletteExcludeFromCycle and cbs.crossbarPaletteExcludeFromCycle[key];
    if t and t[paletteName] then
        return false;
    end
    return true;
end

function M.SetCrossbarPaletteInRbCycle(jobId, tierStorageSubjob, paletteName, inCycle)
    if not paletteName or not IsValidPaletteName(paletteName) then
        return false, 'Invalid palette name';
    end
    local cbs = gConfig.hotbarCrossbar;
    if not cbs then
        return false, 'Crossbar settings not found';
    end
    if not cbs.crossbarPaletteExcludeFromCycle then
        cbs.crossbarPaletteExcludeFromCycle = {};
    end
    local key = BuildJobSubjobKey(jobId or 1, tierStorageSubjob or 0);
    if not cbs.crossbarPaletteExcludeFromCycle[key] then
        cbs.crossbarPaletteExcludeFromCycle[key] = {};
    end
    local ex = cbs.crossbarPaletteExcludeFromCycle[key];
    if inCycle then
        ex[paletteName] = nil;
        PrunePaletteExcludeSubtable(cbs.crossbarPaletteExcludeFromCycle, key);
    else
        ex[paletteName] = true;
    end
    SaveSettingsToDisk();
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

-- REMOVED: BuildStorageKey — was deprecated, no callers remain. Use BuildPaletteStorageKey instead.

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
-- OPTIMIZED: Results are cached with TTL to avoid ~11,100 iterations/frame in config UI
function M.GetAvailablePalettes(barIndex, jobId, subjobId)
    local normalizedJobId = jobId or 1;
    local normalizedSubjobId = subjobId or 0;

    -- Check cache first
    local cacheKey = BuildPaletteCacheKey(normalizedJobId, normalizedSubjobId);
    local cached = paletteListCache[cacheKey];
    local now = os.clock();
    if cached and (now - cached.timestamp) < PALETTE_CACHE_TTL then
        return cached.palettes;
    end

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

    -- Cache the result
    paletteListCache[cacheKey] = { palettes = palettes, timestamp = now };

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

    local all = M.GetAvailablePalettes(barIndex, jobId, subjobId);
    local palettes = {};
    for _, name in ipairs(all) do
        if M.IsHotbarPaletteInRbCycle(jobId, subjobId, name) then
            table.insert(palettes, name);
        end
    end
    if #palettes <= 1 then
        return nil;  -- No palettes to cycle (0 or 1 in RB cycle list)
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

    -- Invalidate cache since palettes changed
    InvalidatePaletteListCache();

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
    local neighborName = PickNeighborPaletteName(availablePalettes, paletteName);

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

    if gConfig.hotbar and gConfig.hotbar.paletteExcludeFromCycle and gConfig.hotbar.paletteExcludeFromCycle[orderKey] then
        gConfig.hotbar.paletteExcludeFromCycle[orderKey][paletteName] = nil;
        PrunePaletteExcludeSubtable(gConfig.hotbar.paletteExcludeFromCycle, orderKey);
    end

    -- Invalidate cache since palettes changed
    InvalidatePaletteListCache();

    -- If this was the active palette, switch to a nearby palette in the old order (below, else above)
    if state.activePalette == paletteName then
        local remainingPalettes = M.GetAvailablePalettes(barIndex, normalizedJobId, normalizedSubjobId);
        local newActive = nil;
        if neighborName then
            for _, n in ipairs(remainingPalettes) do
                if n == neighborName then
                    newActive = n;
                    break;
                end
            end
        end
        if not newActive and #remainingPalettes > 0 then
            newActive = remainingPalettes[1];
        end
        if newActive then
            local changed = M.SetActivePalette(1, newActive, normalizedJobId, normalizedSubjobId);
            if not changed then
                for i = 1, 6 do
                    M.FirePaletteChangedCallbacks(i, newActive, newActive);
                end
            end
        end
    end

    InvalidateAllVisualCachesAfterPaletteListMutation();
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

    if gConfig.hotbar and gConfig.hotbar.paletteExcludeFromCycle and gConfig.hotbar.paletteExcludeFromCycle[orderKey] then
        local ex = gConfig.hotbar.paletteExcludeFromCycle[orderKey];
        if ex[oldName] then
            ex[oldName] = nil;
            ex[newName] = true;
        end
    end

    -- Update active palette if this was active
    if state.activePalette == oldName then
        state.activePalette = newName;
    end

    -- Invalidate cache since palettes changed
    InvalidatePaletteListCache();

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

    if not gConfig.hotbar then
        gConfig.hotbar = {};
    end
    if not gConfig.hotbar.paletteOrder then
        gConfig.hotbar.paletteOrder = {};
    end

    -- Match the merged list used by the Palette Manager / cycling (stored order can omit new palettes)
    local canonical = M.GetAvailablePalettes(barIndex, normalizedJobId, normalizedSubjobId);
    gConfig.hotbar.paletteOrder[orderKey] = {};
    for _, name in ipairs(canonical) do
        table.insert(gConfig.hotbar.paletteOrder[orderKey], name);
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

    -- Invalidate cache since palette order changed
    InvalidatePaletteListCache();

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

    -- Invalidate cache since palette order changed
    InvalidatePaletteListCache();

    SaveSettingsToDisk();
    return true;
end

-- Ordered palette names included in RB / keyboard cycling (excludes "Inactive" in Palette Manager).
function M.GetHotbarPaletteNamesInRbCycle(barIndex, jobId, subjobId)
    local out = {};
    for _, name in ipairs(M.GetAvailablePalettes(barIndex, jobId, subjobId)) do
        if M.IsHotbarPaletteInRbCycle(jobId, subjobId, name) then
            table.insert(out, name);
        end
    end
    return out;
end

-- Get the index of a palette within RB-cycle order only (1-based) (GLOBAL)
-- Returns nil if the palette is not in the cycle list (e.g. marked Inactive).
function M.GetPaletteIndex(barIndex, paletteName, jobId, subjobId)
    if not paletteName then
        return nil;
    end

    local cycle = M.GetHotbarPaletteNamesInRbCycle(barIndex, jobId, subjobId);
    for i, name in ipairs(cycle) do
        if name == paletteName then
            return i;
        end
    end
    return nil;
end

-- Count of palettes that participate in RB / keyboard cycling (not total defined palettes).
function M.GetPaletteCount(barIndex, jobId, subjobId)
    return #M.GetHotbarPaletteNamesInRbCycle(barIndex, jobId, subjobId);
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

-- SetActive* skips callbacks when name (and tier) match current state, but storage may still
-- have changed (e.g. same palette name on another tier, or recreated empty Default).
local function FireCrossbarComboRefreshNoop(displayName)
    if not displayName then
        return;
    end
    for _, mode in ipairs(CROSSBAR_COMBO_MODES) do
        M.FirePaletteChangedCallbacks('crossbar:' .. mode, displayName, displayName);
    end
end

-- Palette OnPaletteChanged only clears slotrenderer rendering cache + crossbar icons; hotbar also uses
-- display-layer icon cache. After delete + redirect, force a full flush so binds resolve to the new storage key.
local function InvalidateAllVisualCachesAfterPaletteListMutation()
    local ok, dataMod = pcall(require, 'modules.hotbar.data');
    if ok and dataMod and dataMod.InvalidateStorageKeyCache then
        dataMod.InvalidateStorageKeyCache();
    end
    local ok2, sr = pcall(require, 'modules.hotbar.slotrenderer');
    if ok2 and sr and sr.ClearAllCache then
        sr.ClearAllCache();
    end
    pcall(function()
        local disp = require('modules.hotbar.display');
        if disp.ClearIconCache then
            disp.ClearIconCache();
        end
    end);
    pcall(function()
        local xb = require('modules.hotbar.crossbar');
        if xb.ClearIconCache then
            xb.ClearIconCache();
        end
    end);
end

--- Re-run palette validation (active names vs lists) then fire a no-op palette change per bar/combo so
--- hotbar/crossbar UIs reload binds from gConfig (JSON import changes data under the same palette name).
function M.RefreshActivePaletteVisualsAfterExternalEdit()
    local okData, dataMod = pcall(require, 'modules.hotbar.data');
    if okData and dataMod and dataMod.jobId then
        pcall(function()
            M.ValidatePalettesForJob(dataMod.jobId, dataMod.subjobId or 0, { applyDefaultCrossbarScope = false });
        end);
    end
    local hotbarName = state.activePalette;
    if hotbarName then
        for i = 1, 6 do
            M.FirePaletteChangedCallbacks(i, hotbarName, hotbarName);
        end
    end
    if state.crossbarActivePalette then
        for _, mode in ipairs(CROSSBAR_COMBO_MODES) do
            M.FirePaletteChangedCallbacks('crossbar:' .. mode, state.crossbarActivePalette, state.crossbarActivePalette);
        end
    end
    if state.crossbarActiveUniversalPalette then
        for _, mode in ipairs(CROSSBAR_COMBO_MODES) do
            M.FirePaletteChangedCallbacks('crossbar:' .. mode, state.crossbarActiveUniversalPalette, state.crossbarActiveUniversalPalette);
        end
    end
end

--- Called after tools import or replace slot data outside normal palette APIs (e.g. JSON import).
function M.InvalidateCachesAfterExternalSlotMutation()
    InvalidatePaletteListCache();
    InvalidateAllVisualCachesAfterPaletteListMutation();
    M.RefreshActivePaletteVisualsAfterExternalEdit();
end

-- ============================================
-- Crossbar Palette Management
-- ============================================

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

-- Build ordered list of crossbar palette rows for a job + live subjob context (no Either/Or hiding).
-- storageSubjob 0 = Job-wide [J]; storageSubjob == subjobId (when ~=0) = Subjob-only [SJ] entries.
local function BuildCrossbarMergedRowsInternal(jobId, subjobId)
    local jid = jobId or 1;
    local sj = subjobId or 0;
    local rows = {};
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;

    local function orderedNamesForTier(tierSj, existingSet)
        local orderKey = BuildJobSubjobKey(jid, tierSj);
        local storedOrder = crossbarSettings and crossbarSettings.crossbarPaletteOrder
            and crossbarSettings.crossbarPaletteOrder[orderKey];
        local out = {};
        local seen = {};
        if storedOrder then
            for _, paletteName in ipairs(storedOrder) do
                if existingSet[paletteName] and not seen[paletteName] then
                    seen[paletteName] = true;
                    table.insert(out, paletteName);
                end
            end
        end
        local remaining = {};
        for paletteName, _ in pairs(existingSet) do
            if not seen[paletteName] then
                table.insert(remaining, paletteName);
            end
        end
        table.sort(remaining);
        for _, paletteName in ipairs(remaining) do
            table.insert(out, paletteName);
        end
        return out;
    end

    if sj == 0 then
        local pattern0 = string.format('%d:0:%s', jid, M.PALETTE_KEY_PREFIX);
        local set0 = ScanCrossbarForPalettes(pattern0);
        for _, n in ipairs(orderedNamesForTier(0, set0)) do
            table.insert(rows, { name = n, storageSubjob = 0 });
        end
        return rows;
    end

    local pattern0 = string.format('%d:0:%s', jid, M.PALETTE_KEY_PREFIX);
    local set0 = ScanCrossbarForPalettes(pattern0);
    local seen = {};
    for _, n in ipairs(orderedNamesForTier(0, set0)) do
        seen[n] = true;
        table.insert(rows, { name = n, storageSubjob = 0 });
    end

    local subPattern = string.format('%d:%d:%s', jid, sj, M.PALETTE_KEY_PREFIX);
    local setS = ScanCrossbarForPalettes(subPattern);
    local extraSet = {};
    for name, _ in pairs(setS) do
        if not seen[name] then
            extraSet[name] = true;
        end
    end
    for _, n in ipairs(orderedNamesForTier(sj, extraSet)) do
        table.insert(rows, { name = n, storageSubjob = sj });
    end

    return rows;
end

-- Get all available crossbar entries for the current job/subjob context.
-- When live subjob is 0: returns plain palette names (Job [J] tier only).
-- When live subjob ~= 0: returns encoded tokens 'storageSubjob' .. sep .. 'name' so Job + Subjob tiers stay distinct.
-- Crossbar palettes are SEPARATE from hotbar palettes. OPTIMIZED: cached with TTL.
function M.GetCrossbarAvailablePalettes(jobId, subjobId)
    local normalizedJobId = jobId or 1;
    local normalizedSubjobId = subjobId or 0;

    local cacheKey = BuildPaletteCacheKey(normalizedJobId, normalizedSubjobId);
    local cached = crossbarPaletteListCache[cacheKey];
    local now = os.clock();
    if cached and (now - cached.timestamp) < PALETTE_CACHE_TTL then
        return cached.palettes;
    end

    local palettes = {};
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings or not crossbarSettings.slotActions then
        crossbarPaletteListCache[cacheKey] = { palettes = palettes, timestamp = now };
        return palettes;
    end

    if normalizedSubjobId == 0 then
        local rows = BuildCrossbarMergedRowsInternal(normalizedJobId, 0);
        for _, r in ipairs(rows) do
            table.insert(palettes, r.name);
        end
    else
        local rows = BuildCrossbarMergedRowsInternal(normalizedJobId, normalizedSubjobId);
        for _, r in ipairs(rows) do
            table.insert(palettes, M.EncodeCrossbarEntryToken(r.storageSubjob, r.name));
        end
    end

    crossbarPaletteListCache[cacheKey] = { palettes = palettes, timestamp = now };
    return palettes;
end

-- Rows for Manage / embedded Palette Manager (and cycle order): Job [J] then Subjob [SJ]-only names.
function M.GetCrossbarManagePaletteRows(jobId, subjobId)
    return BuildCrossbarMergedRowsInternal(jobId or 1, subjobId or 0);
end

-- Ordered palette names for a single storage tier (used when reordering within that tier)
function M.GetCrossbarPaletteNamesForOrderTier(jobId, tierSubjob)
    local jid = jobId or 1;
    local tier = tierSubjob or 0;
    local pattern = string.format('%d:%d:%s', jid, tier, M.PALETTE_KEY_PREFIX);
    local existing = ScanCrossbarForPalettes(pattern);
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    local orderKey = BuildJobSubjobKey(jid, tier);
    local storedOrder = crossbarSettings and crossbarSettings.crossbarPaletteOrder
        and crossbarSettings.crossbarPaletteOrder[orderKey];
    local out = {};
    local seen = {};
    if storedOrder then
        for _, paletteName in ipairs(storedOrder) do
            if existing[paletteName] and not seen[paletteName] then
                seen[paletteName] = true;
                table.insert(out, paletteName);
            end
        end
    end
    local remaining = {};
    for paletteName, _ in pairs(existing) do
        if not seen[paletteName] then
            table.insert(remaining, paletteName);
        end
    end
    table.sort(remaining);
    for _, paletteName in ipairs(remaining) do
        table.insert(out, paletteName);
    end
    return out;
end

-- ============================================
-- Universal (all-jobs) crossbar palettes
-- Storage key: global:palette:{name} in hotbarCrossbar.slotActions
-- Pet overlays never apply to these keys (handled in data.lua).
-- ============================================

function M.BuildUniversalCrossbarStorageKey(paletteName)
    if not paletteName or paletteName == '' then
        return nil;
    end
    return M.UNIVERSAL_CROSSBAR_PREFIX .. paletteName;
end

local function ScanUniversalCrossbarPaletteNames()
    local existing = {};
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings or not crossbarSettings.slotActions then
        return existing;
    end
    local prefix = M.UNIVERSAL_CROSSBAR_PREFIX;
    for storageKey, _ in pairs(crossbarSettings.slotActions) do
        if type(storageKey) == 'string' and storageKey:sub(1, #prefix) == prefix then
            local name = storageKey:sub(#prefix + 1);
            if name and name ~= '' then
                existing[name] = true;
            end
        end
    end
    return existing;
end

--- Ordered list of all universal crossbar palette names (for UI).
function M.GetUniversalCrossbarPaletteNamesOrdered()
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings then
        return {};
    end
    local existing = ScanUniversalCrossbarPaletteNames();
    local ordered = {};
    local seen = {};
    local orderList = crossbarSettings.universalCrossbarPaletteOrder;
    if orderList then
        for _, name in ipairs(orderList) do
            if existing[name] and not seen[name] then
                seen[name] = true;
                table.insert(ordered, name);
            end
        end
    end
    local rest = {};
    for name, _ in pairs(existing) do
        if not seen[name] then
            table.insert(rest, name);
        end
    end
    table.sort(rest);
    for _, name in ipairs(rest) do
        table.insert(ordered, name);
    end
    return ordered;
end

function M.GetUniversalPaletteIncludeInCycle(name)
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    local meta = crossbarSettings and crossbarSettings.crossbarUniversalPaletteMeta;
    if not meta or not meta[name] then
        return true;
    end
    if meta[name].includeInCycle == false then
        return false;
    end
    return true;
end

function M.SetUniversalPaletteIncludeInCycle(name, includeInCycle)
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings then
        return false;
    end
    if not crossbarSettings.crossbarUniversalPaletteMeta then
        crossbarSettings.crossbarUniversalPaletteMeta = {};
    end
    if not crossbarSettings.crossbarUniversalPaletteMeta[name] then
        crossbarSettings.crossbarUniversalPaletteMeta[name] = {};
    end
    crossbarSettings.crossbarUniversalPaletteMeta[name].includeInCycle = includeInCycle and true or false;
    SaveSettingsToDisk();
    return true;
end

--- Palettes RB+D-pad cycles when scope is universal (respects includeInCycle).
function M.GetUniversalCrossbarPalettesForCycle()
    local all = M.GetUniversalCrossbarPaletteNamesOrdered();
    local out = {};
    for _, name in ipairs(all) do
        if M.GetUniversalPaletteIncludeInCycle(name) then
            table.insert(out, name);
        end
    end
    return out;
end

function M.CreateUniversalCrossbarPalette(paletteName)
    if not IsValidPaletteName(paletteName) then
        return false, 'Invalid palette name';
    end
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings then
        return false, 'Crossbar settings not found';
    end
    if not crossbarSettings.slotActions then
        crossbarSettings.slotActions = {};
    end
    local key = M.BuildUniversalCrossbarStorageKey(paletteName);
    if crossbarSettings.slotActions[key] then
        return false, 'Palette already exists';
    end
    crossbarSettings.slotActions[key] = {};
    if not crossbarSettings.universalCrossbarPaletteOrder then
        crossbarSettings.universalCrossbarPaletteOrder = {};
    end
    table.insert(crossbarSettings.universalCrossbarPaletteOrder, paletteName);
    if not crossbarSettings.crossbarUniversalPaletteMeta then
        crossbarSettings.crossbarUniversalPaletteMeta = {};
    end
    if not crossbarSettings.crossbarUniversalPaletteMeta[paletteName] then
        crossbarSettings.crossbarUniversalPaletteMeta[paletteName] = { includeInCycle = true };
    end
    InvalidatePaletteListCache();
    SaveSettingsToDisk();
    return true;
end

function M.EnsureUniversalCrossbarDefaultExists()
    local names = M.GetUniversalCrossbarPaletteNamesOrdered();
    if #names > 0 then
        return names[1];
    end
    local ok = M.CreateUniversalCrossbarPalette(M.DEFAULT_PALETTE_NAME);
    if ok == true then
        return M.DEFAULT_PALETTE_NAME;
    end
    return nil;
end

function M.DeleteUniversalCrossbarPalette(paletteName)
    if not paletteName or paletteName == '' then
        return false, 'No palette name';
    end
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings or not crossbarSettings.slotActions then
        return false, 'Not found';
    end
    local key = M.BuildUniversalCrossbarStorageKey(paletteName);
    if not crossbarSettings.slotActions[key] then
        return false, 'Palette not found';
    end
    local orderedBefore = M.GetUniversalCrossbarPaletteNamesOrdered();
    local neighborName = PickNeighborPaletteName(orderedBefore, paletteName);
    crossbarSettings.slotActions[key] = nil;
    if crossbarSettings.universalCrossbarPaletteOrder then
        for i, n in ipairs(crossbarSettings.universalCrossbarPaletteOrder) do
            if n == paletteName then
                table.remove(crossbarSettings.universalCrossbarPaletteOrder, i);
                break;
            end
        end
    end
    if crossbarSettings.crossbarUniversalPaletteMeta then
        crossbarSettings.crossbarUniversalPaletteMeta[paletteName] = nil;
    end
    M.EnsureUniversalCrossbarDefaultExists();
    if state.crossbarActiveUniversalPalette == paletteName then
        local rest = M.GetUniversalCrossbarPaletteNamesOrdered();
        local pickName = nil;
        if neighborName then
            for _, n in ipairs(rest) do
                if n == neighborName then
                    pickName = n;
                    break;
                end
            end
        end
        if not pickName and #rest > 0 then
            pickName = rest[1];
        end
        if pickName then
            local changed = M.SetActiveUniversalCrossbarPalette(pickName);
            if not changed then
                FireCrossbarComboRefreshNoop(pickName);
            end
        end
    end
    if crossbarSettings.comboModeSettings then
        for _, mode in ipairs(CROSSBAR_COMBO_MODES) do
            local ms = crossbarSettings.comboModeSettings[mode];
            if ms and ms.universalOverridePalette == paletteName then
                ms.universalOverridePalette = nil;
            end
        end
    end
    if crossbarSettings.namedPaletteComboModeSettings then
        for _, perPal in pairs(crossbarSettings.namedPaletteComboModeSettings) do
            if type(perPal) == 'table' then
                for _, mode in ipairs(CROSSBAR_COMBO_MODES) do
                    local o = perPal[mode];
                    if o and o.universalOverridePalette == paletteName then
                        o.universalOverridePalette = nil;
                    end
                end
            end
        end
    end
    if crossbarSettings.segmentOverrides then
        for jid, modes in pairs(crossbarSettings.segmentOverrides) do
            if type(modes) == 'table' then
                for mode, seg in pairs(modes) do
                    if type(seg) == 'table' and seg.scope == 'global' and seg.globalPalette == paletteName then
                        modes[mode] = nil;
                    end
                end
                if next(modes) == nil then
                    crossbarSettings.segmentOverrides[jid] = nil;
                end
            end
        end
        if next(crossbarSettings.segmentOverrides) == nil then
            crossbarSettings.segmentOverrides = nil;
        end
    end
    InvalidatePaletteListCache();
    InvalidateAllVisualCachesAfterPaletteListMutation();
    SaveSettingsToDisk();
    return true;
end

function M.RenameUniversalCrossbarPalette(oldName, newName)
    if not oldName or oldName == '' then
        return false, 'No palette name';
    end
    if not newName or newName == '' then
        return false, 'No new name';
    end
    if oldName == newName then
        return false, 'New name is the same as the old name';
    end
    if not IsValidPaletteName(newName) then
        return false, 'Invalid new palette name';
    end
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings or not crossbarSettings.slotActions then
        return false, 'Crossbar settings not found';
    end
    local oldKey = M.BuildUniversalCrossbarStorageKey(oldName);
    local newKey = M.BuildUniversalCrossbarStorageKey(newName);
    if not crossbarSettings.slotActions[oldKey] then
        return false, 'Palette not found';
    end
    if crossbarSettings.slotActions[newKey] then
        return false, 'A palette with that name already exists';
    end
    crossbarSettings.slotActions[newKey] = crossbarSettings.slotActions[oldKey];
    crossbarSettings.slotActions[oldKey] = nil;
    if crossbarSettings.universalCrossbarPaletteOrder then
        for i, n in ipairs(crossbarSettings.universalCrossbarPaletteOrder) do
            if n == oldName then
                crossbarSettings.universalCrossbarPaletteOrder[i] = newName;
                break;
            end
        end
    end
    if crossbarSettings.crossbarUniversalPaletteMeta then
        if crossbarSettings.crossbarUniversalPaletteMeta[oldName] then
            crossbarSettings.crossbarUniversalPaletteMeta[newName] = crossbarSettings.crossbarUniversalPaletteMeta[oldName];
            crossbarSettings.crossbarUniversalPaletteMeta[oldName] = nil;
        end
    end
    if state.crossbarActiveUniversalPalette == oldName then
        state.crossbarActiveUniversalPalette = newName;
    end
    if crossbarSettings.comboModeSettings then
        for _, mode in ipairs(CROSSBAR_COMBO_MODES) do
            local ms = crossbarSettings.comboModeSettings[mode];
            if ms and ms.universalOverridePalette == oldName then
                ms.universalOverridePalette = newName;
            end
        end
    end
    if crossbarSettings.namedPaletteComboModeSettings then
        for _, perPal in pairs(crossbarSettings.namedPaletteComboModeSettings) do
            if type(perPal) == 'table' then
                for _, mode in ipairs(CROSSBAR_COMBO_MODES) do
                    local o = perPal[mode];
                    if o and o.universalOverridePalette == oldName then
                        o.universalOverridePalette = newName;
                    end
                end
            end
        end
    end
    if crossbarSettings.segmentOverrides then
        for _, modes in pairs(crossbarSettings.segmentOverrides) do
            if type(modes) == 'table' then
                for _, seg in pairs(modes) do
                    if type(seg) == 'table' and seg.scope == 'global' and seg.globalPalette == oldName then
                        seg.globalPalette = newName;
                    end
                end
            end
        end
    end
    InvalidatePaletteListCache();
    SaveSettingsToDisk();
    return true;
end

--- Reorder Global [G] crossbar palettes (same list as GetUniversalCrossbarPaletteNamesOrdered).
function M.MoveUniversalCrossbarPalette(paletteName, direction)
    if not paletteName or paletteName == '' then
        return false, 'No palette specified';
    end
    if direction ~= -1 and direction ~= 1 then
        return false, 'Invalid direction';
    end
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings then
        return false, 'Crossbar settings not found';
    end
    local ordered = M.GetUniversalCrossbarPaletteNamesOrdered();
    local currentIndex = nil;
    for i, name in ipairs(ordered) do
        if name == paletteName then
            currentIndex = i;
            break;
        end
    end
    if not currentIndex then
        return false, 'Palette not found in order';
    end
    local newIndex = currentIndex + direction;
    if newIndex < 1 or newIndex > #ordered then
        return false, 'Cannot move palette further';
    end
    ordered[currentIndex], ordered[newIndex] = ordered[newIndex], ordered[currentIndex];
    crossbarSettings.universalCrossbarPaletteOrder = {};
    for _, n in ipairs(ordered) do
        table.insert(crossbarSettings.universalCrossbarPaletteOrder, n);
    end
    InvalidatePaletteListCache();
    SaveSettingsToDisk();
    return true;
end

--- Deep-copy one Global [G] palette's slot data to a new or existing palette name.
function M.CopyUniversalCrossbarPalette(sourceName, destName, overwriteExisting)
    if not sourceName or sourceName == '' then
        return false, 'No palette specified';
    end
    local dest = destName or sourceName;
    if not IsValidPaletteName(dest) then
        return false, 'Invalid destination palette name';
    end
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings then
        return false, 'Crossbar settings not found';
    end
    if not crossbarSettings.slotActions then
        crossbarSettings.slotActions = {};
    end
    local sourceKey = M.BuildUniversalCrossbarStorageKey(sourceName);
    local destKey = M.BuildUniversalCrossbarStorageKey(dest);
    if not crossbarSettings.slotActions[sourceKey] then
        return false, 'Source palette not found';
    end
    local destExists = crossbarSettings.slotActions[destKey] ~= nil;
    overwriteExisting = overwriteExisting == true;
    if destExists then
        if not overwriteExisting then
            return false, 'Palette already exists at destination';
        end
    elseif overwriteExisting then
        return false, 'No palette at that destination to overwrite';
    end
    local sourceData = crossbarSettings.slotActions[sourceKey];
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
    if not destExists then
        if not crossbarSettings.universalCrossbarPaletteOrder then
            crossbarSettings.universalCrossbarPaletteOrder = {};
        end
        table.insert(crossbarSettings.universalCrossbarPaletteOrder, dest);
        if not crossbarSettings.crossbarUniversalPaletteMeta then
            crossbarSettings.crossbarUniversalPaletteMeta = {};
        end
        if not crossbarSettings.crossbarUniversalPaletteMeta[dest] then
            crossbarSettings.crossbarUniversalPaletteMeta[dest] = { includeInCycle = true };
        end
    end
    InvalidatePaletteListCache();
    InvalidateAllVisualCachesAfterPaletteListMutation();
    SaveSettingsToDisk();
    return true;
end

function M.GetCrossbarPaletteScope()
    return state.crossbarPaletteScope or 'job';
end

function M.SetCrossbarPaletteScope(scope)
    if scope ~= 'job' and scope ~= 'universal' then
        return false;
    end
    if state.crossbarPaletteScope == scope then
        return false;
    end
    state.crossbarPaletteScope = scope;
    for _, mode in ipairs(CROSSBAR_COMBO_MODES) do
        M.FirePaletteChangedCallbacks('crossbar:' .. mode, nil, nil);
    end
    return true;
end

local lastCrossbarScopeToggleClock = 0;

function M.ToggleCrossbarPaletteScope()
    local now = os.clock();
    if now - lastCrossbarScopeToggleClock < 0.25 then
        return false;
    end
    lastCrossbarScopeToggleClock = now;
    local nextScope = (state.crossbarPaletteScope == 'universal') and 'job' or 'universal';
    return M.SetCrossbarPaletteScope(nextScope);
end

function M.GetActiveUniversalCrossbarPalette()
    return state.crossbarActiveUniversalPalette;
end

function M.SetActiveUniversalCrossbarPalette(paletteName)
    local old = state.crossbarActiveUniversalPalette;
    if old == paletteName then
        return false;
    end
    state.crossbarActiveUniversalPalette = paletteName;
    state.crossbarPaletteScope = 'universal';
    for _, mode in ipairs(CROSSBAR_COMBO_MODES) do
        M.FirePaletteChangedCallbacks('crossbar:' .. mode, old, paletteName);
    end
    return true;
end

-- Unified fallback check: crossbar never uses fallback (both J and SJ tiers are visible).
function M.IsUsingFallback(jobId, subjobId, paletteType)
    if subjobId == 0 then return false; end
    if paletteType == 'crossbar' then
        return false;
    end
    return M.IsUsingFallbackPalettes(jobId, subjobId);
end

-- Get active palette name for crossbar (job-tier or universal-tier depending on scope)
-- comboMode param kept for backwards compatibility but ignored
-- Returns nil if no palette (using default slots)
function M.GetActivePaletteForCombo(comboMode)
    if state.crossbarPaletteScope == 'universal' then
        return state.crossbarActiveUniversalPalette;
    end
    return state.crossbarActivePalette;
end

-- Get active palette display name for crossbar
-- comboMode param kept for backwards compatibility but ignored
-- Returns nil if no palette is active
function M.GetActivePaletteDisplayNameForCombo(comboMode)
    if state.crossbarPaletteScope == 'universal' then
        return state.crossbarActiveUniversalPalette;
    end
    return state.crossbarActivePalette;
end

-- Set active palette for crossbar (job / job+subjob tier — affects all combo modes)
-- comboMode param kept for backwards compatibility but ignored
-- paletteName: name to activate, or nil to clear
-- storageSubjob: 0 = Job [J] tier; live subjob id = Subjob [SJ] tier (omit/nil = infer from merged list later)
function M.SetActivePaletteForCombo(comboMode, paletteName, storageSubjob)
    local oldPalette = state.crossbarActivePalette;
    local oldScope = state.crossbarPaletteScope;
    local oldSt = state.crossbarActiveStorageSubjob;

    state.crossbarPaletteScope = 'job';
    state.crossbarActivePalette = paletteName;
    if storageSubjob ~= nil then
        state.crossbarActiveStorageSubjob = storageSubjob;
    elseif paletteName == nil or oldPalette ~= paletteName then
        state.crossbarActiveStorageSubjob = nil;
    end

    if oldPalette == paletteName and oldScope == 'job' and oldSt == state.crossbarActiveStorageSubjob then
        return false;
    end

    for _, mode in ipairs(CROSSBAR_COMBO_MODES) do
        M.FirePaletteChangedCallbacks('crossbar:' .. mode, oldPalette, paletteName);
    end

    return true;
end

-- Persisted / current Job-scope storage tier (nil = infer from merged list by name)
function M.GetCrossbarActiveStorageSubjob()
    return state.crossbarActiveStorageSubjob;
end

-- Storage tier for slot key resolution when [J] scope (not Global [G])
function M.GetCrossbarActivePaletteStorageSubjobForResolution(jobId, liveSubjobId)
    local lj = liveSubjobId or 0;
    if lj == 0 then
        return 0;
    end
    local st = state.crossbarActiveStorageSubjob;
    if st ~= nil then
        return st;
    end
    if state.crossbarActivePalette then
        local rows = M.GetCrossbarManagePaletteRows(jobId, lj);
        for _, r in ipairs(rows) do
            if r.name == state.crossbarActivePalette then
                return r.storageSubjob;
            end
        end
    end
    return 0;
end

-- Clear active palette for crossbar (uses default slot data)
-- comboMode param kept for backwards compatibility but ignored
function M.ClearActivePaletteForCombo(comboMode)
    return M.SetActivePaletteForCombo(comboMode, nil);
end

-- Cycle through palettes for crossbar (job tier or all-jobs universal tier)
-- comboMode param kept for backwards compatibility but ignored
-- direction: 1 for next, -1 for previous
function M.CyclePaletteForCombo(comboMode, direction, jobId, subjobId)
    direction = direction or 1;

    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if crossbarSettings and crossbarSettings.enableUniversalCrossbarPalettes and state.crossbarPaletteScope == 'universal' then
        local palettes = M.GetUniversalCrossbarPalettesForCycle();
        if #palettes == 0 then
            return nil, false;
        end
        if #palettes == 1 then
            M.SetActiveUniversalCrossbarPalette(palettes[1]);
            return palettes[1], true;
        end
        local currentName = state.crossbarActiveUniversalPalette;
        local currentIndex = 1;
        if currentName then
            for i, name in ipairs(palettes) do
                if name == currentName then
                    currentIndex = i;
                    break;
                end
            end
        end
        local newIndex = currentIndex + direction;
        if newIndex < 1 then newIndex = #palettes; end
        if newIndex > #palettes then newIndex = 1; end
        local newPalette = palettes[newIndex];
        M.SetActiveUniversalCrossbarPalette(newPalette);
        return newPalette, true;
    end

    local rowsAll = M.GetCrossbarManagePaletteRows(jobId, subjobId);
    local rows = {};
    for _, r in ipairs(rowsAll) do
        if M.IsCrossbarPaletteInRbCycle(jobId, r.storageSubjob, r.name) then
            table.insert(rows, r);
        end
    end
    if #rows == 0 then
        return nil, false;
    end

    local currentIndex = 1;
    for i, r in ipairs(rows) do
        if r.name == state.crossbarActivePalette
            and (state.crossbarActiveStorageSubjob == nil or state.crossbarActiveStorageSubjob == r.storageSubjob) then
            currentIndex = i;
            break;
        end
    end

    if #rows == 1 then
        local r = rows[1];
        M.SetActivePaletteForCombo(comboMode, r.name, r.storageSubjob);
        return r.name, true;
    end

    local newIndex = currentIndex + direction;
    if newIndex < 1 then newIndex = #rows; end
    if newIndex > #rows then newIndex = 1; end

    local pick = rows[newIndex];
    M.SetActivePaletteForCombo(comboMode, pick.name, pick.storageSubjob);

    return pick.name, true;
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
-- skipSave: when true, caller batches SaveSettingsToDisk (e.g. multi-job seed)
-- Returns true on success, false with error message on failure
function M.CreateCrossbarPalette(paletteName, jobId, subjobId, skipSave)
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

    -- Invalidate cache since palettes changed
    InvalidatePaletteListCache();

    if not skipSave then
        SaveSettingsToDisk();
    end
    return true;
end

-- Ensure at least one crossbar palette exists for a job
-- Creates a "Default" palette at Job [J] tier if none exist
-- Does not change the live active crossbar palette (config must not flip in-game scope)
-- Returns the name of the first palette in merged order for this context
function M.EnsureCrossbarDefaultPaletteExists(jobId, subjobId)
    local normalizedJobId = jobId or 1;
    local sj = subjobId or 0;

    local rows = M.GetCrossbarManagePaletteRows(normalizedJobId, sj);

    if #rows == 0 then
        local success, err = M.CreateCrossbarPalette(M.DEFAULT_PALETTE_NAME, normalizedJobId, 0);
        if success then
            return M.DEFAULT_PALETTE_NAME;
        end
        for i = 1, 99 do
            local name = 'Palette ' .. i;
            success, err = M.CreateCrossbarPalette(name, normalizedJobId, 0);
            if success then
                return name;
            end
        end
        return nil;
    end

    return rows[1].name;
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

-- If a Job [J] / Subjob [SJ] storage tier has zero palettes, create one blank Default (or Palette N).
local function EnsureCrossbarStorageTierHasDefaultPalette(jobId, storageTier, skipSave)
    local jid = jobId or 1;
    local tier = storageTier or 0;
    if #M.GetCrossbarPaletteNamesForOrderTier(jid, tier) > 0 then
        return;
    end
    local ok, err = M.CreateCrossbarPalette(M.DEFAULT_PALETTE_NAME, jid, tier, skipSave);
    if ok then
        return;
    end
    for i = 1, 99 do
        ok, err = M.CreateCrossbarPalette('Palette ' .. i, jid, tier, skipSave);
        if ok then
            return;
        end
    end
end

local CROSSBAR_JOB_SEED_MAX = 22;

local function MaybeSeedBlankCrossbarDefaultPalettesForAllJobs()
    if crossbarBlankDefaultsSeeded then
        return;
    end
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings then
        return;
    end
    crossbarBlankDefaultsSeeded = true;

    local any = false;
    for jid = 1, CROSSBAR_JOB_SEED_MAX do
        if #M.GetCrossbarManagePaletteRows(jid, 0) == 0 then
            EnsureCrossbarStorageTierHasDefaultPalette(jid, 0, true);
            any = true;
        end
    end
    if any then
        InvalidatePaletteListCache();
        SaveSettingsToDisk();
    end
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

    local keyJobId, keySubjobId = storageKey:match('^(%d+):(%d+):');
    local jidOrder = (keyJobId and tonumber(keyJobId)) or normalizedJobId;
    local tierForOrder = (keySubjobId and tonumber(keySubjobId)) or normalizedSubjobId;
    local orderedBefore = M.GetCrossbarPaletteNamesForOrderTier(jidOrder, tierForOrder);
    local neighborName = PickNeighborPaletteName(orderedBefore, paletteName);

    -- Delete the palette
    crossbarSettings.slotActions[storageKey] = nil;

    if crossbarSettings.namedPaletteComboModeSettings then
        crossbarSettings.namedPaletteComboModeSettings[storageKey] = nil;
    end

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

    if crossbarSettings.crossbarPaletteExcludeFromCycle and crossbarSettings.crossbarPaletteExcludeFromCycle[orderKey] then
        crossbarSettings.crossbarPaletteExcludeFromCycle[orderKey][paletteName] = nil;
        PrunePaletteExcludeSubtable(crossbarSettings.crossbarPaletteExcludeFromCycle, orderKey);
    end

    EnsureCrossbarStorageTierHasDefaultPalette(jidOrder, tierForOrder);

    if state.crossbarActivePalette == paletteName
        and (state.crossbarActiveStorageSubjob == nil or state.crossbarActiveStorageSubjob == tierForOrder) then
        local rest = M.GetCrossbarPaletteNamesForOrderTier(jidOrder, tierForOrder);
        local pickName = nil;
        if neighborName then
            for _, n in ipairs(rest) do
                if n == neighborName then
                    pickName = n;
                    break;
                end
            end
        end
        if not pickName and #rest > 0 then
            pickName = rest[1];
        end
        if pickName then
            local changed = M.SetActivePaletteForCombo('L2', pickName, tierForOrder);
            if not changed then
                FireCrossbarComboRefreshNoop(pickName);
            end
        end
    end

    -- Invalidate cache since palettes changed
    InvalidatePaletteListCache();
    InvalidateAllVisualCachesAfterPaletteListMutation();

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

    if crossbarSettings.namedPaletteComboModeSettings then
        local np = crossbarSettings.namedPaletteComboModeSettings;
        if np[oldStorageKey] then
            np[newStorageKey] = np[oldStorageKey];
            np[oldStorageKey] = nil;
        end
    end

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

    if crossbarSettings.crossbarPaletteExcludeFromCycle and crossbarSettings.crossbarPaletteExcludeFromCycle[orderKey] then
        local ex = crossbarSettings.crossbarPaletteExcludeFromCycle[orderKey];
        if ex[oldName] then
            ex[oldName] = nil;
            ex[newName] = true;
        end
    end

    if state.crossbarActivePalette == oldName
        and (state.crossbarActiveStorageSubjob == nil or state.crossbarActiveStorageSubjob == effectiveSubjobId) then
        state.crossbarActivePalette = newName;
    end

    -- Invalidate cache since palettes changed
    InvalidatePaletteListCache();

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

    -- subjobId is the storage tier for this palette (0 = Job [J], N = Subjob [SJ])
    local orderKey = BuildJobSubjobKey(normalizedJobId, normalizedSubjobId);

    if not crossbarSettings.crossbarPaletteOrder then
        crossbarSettings.crossbarPaletteOrder = {};
    end

    -- Same merged order the UI lists (raw crossbarPaletteOrder can be stale or missing names)
    local canonical = M.GetCrossbarPaletteNamesForOrderTier(normalizedJobId, normalizedSubjobId);
    crossbarSettings.crossbarPaletteOrder[orderKey] = {};
    for _, name in ipairs(canonical) do
        table.insert(crossbarSettings.crossbarPaletteOrder[orderKey], name);
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

    -- Invalidate cache since palette order changed
    InvalidatePaletteListCache();

    SaveSettingsToDisk();
    return true;
end

-- Check if a specific crossbar palette exists (optional storage tier: 0 = Job [J], else Subjob [SJ])
function M.CrossbarPaletteExists(paletteName, jobId, subjobId, storageTier)
    if not paletteName then
        return false;
    end

    local rows = M.GetCrossbarManagePaletteRows(jobId, subjobId);
    for _, r in ipairs(rows) do
        if r.name == paletteName and (storageTier == nil or r.storageSubjob == storageTier) then
            return true;
        end
    end
    return false;
end

-- Crossbar rows that participate in RB+D-pad cycling (excludes Inactive in Palette Manager).
function M.GetCrossbarManagePaletteRowsInRbCycle(jobId, subjobId)
    local out = {};
    for _, r in ipairs(M.GetCrossbarManagePaletteRows(jobId, subjobId)) do
        if M.IsCrossbarPaletteInRbCycle(jobId, r.storageSubjob, r.name) then
            table.insert(out, r);
        end
    end
    return out;
end

-- Index in RB-cycle order only (1-based). Nil if palette is inactive or not found.
function M.GetCrossbarPaletteIndex(paletteName, jobId, subjobId, storageTier)
    if not paletteName then
        return nil;
    end

    local rows = M.GetCrossbarManagePaletteRowsInRbCycle(jobId, subjobId);
    for i, r in ipairs(rows) do
        if r.name == paletteName and (storageTier == nil or r.storageSubjob == storageTier) then
            return i;
        end
    end
    return nil;
end

function M.GetCrossbarPaletteCount(jobId, subjobId)
    return #M.GetCrossbarManagePaletteRowsInRbCycle(jobId, subjobId);
end

--- Index and total for the on-screen palette label (RB cycle): universal [G] uses universal cycle; job [J] uses job rows.
function M.GetCrossbarPaletteLabelIndexAndTotal(paletteName, jobId, subjobId)
    if not paletteName then
        return nil, nil;
    end
    if M.GetCrossbarPaletteScope() == 'universal' then
        local cycle = M.GetUniversalCrossbarPalettesForCycle();
        local total = #cycle;
        for i, n in ipairs(cycle) do
            if n == paletteName then
                return i, total;
            end
        end
        return nil, (total > 0) and total or nil;
    end
    return M.GetCrossbarPaletteIndex(paletteName, jobId, subjobId), M.GetCrossbarPaletteCount(jobId, subjobId);
end

-- ============================================
-- State Management (GLOBAL)
-- ============================================

-- Validate active palettes against current job's available palettes
-- Ensures at least one palette exists, and auto-selects the first palette if none is active
-- opts.applyDefaultCrossbarScope: only pass true when loading/reloading a profile (see XIUI xiuiApplyDefaultCrossbarPaletteScopeAfterProfileLoad).
-- Zone/job packets and leveling must not flip scope — user toggles L1+R1 for that session.
function M.ValidatePalettesForJob(jobId, subjobId, opts)
    -- Ensure gConfig.hotbar structure exists before any palette operations
    if not EnsureHotbarConfigExists() then
        print('[XIUI palette] Warning: gConfig not available, skipping palette validation');
        return;
    end

    -- Run migration if needed (converts old format palettes to new subjob-aware format)
    if NeedsPaletteMigration() then
        RunPaletteMigration();
    end

    -- Blank Default crossbar palette per job (no live palette activation; avoids config/job clicks)
    MaybeSeedBlankCrossbarDefaultPalettesForAllJobs();

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

    -- First palette that participates in RB / keyboard cycling (Palette Manager "Active")
    local function firstHotbarPaletteInCycle()
        for _, name in ipairs(availablePalettes) do
            if M.IsHotbarPaletteInRbCycle(jobId, subjobId, name) then
                return name;
            end
        end
        if #availablePalettes > 0 then
            return availablePalettes[1];
        end
        return firstPalette;
    end

    local function savedHotbarPaletteIfInCycle(name)
        if not name then
            return nil;
        end
        for _, n in ipairs(availablePalettes) do
            if n == name and M.IsHotbarPaletteInRbCycle(jobId, subjobId, n) then
                return name;
            end
        end
        return nil;
    end

    -- Hotbar: do not keep a palette marked Inactive as the active palette after load / job change
    local oldHotbarPalette = state.activePalette;
    local desiredHotbar = nil;
    if state.activePalette then
        local exists = false;
        for _, name in ipairs(availablePalettes) do
            if name == state.activePalette then
                exists = true;
                break;
            end
        end
        if exists and M.IsHotbarPaletteInRbCycle(jobId, subjobId, state.activePalette) then
            desiredHotbar = state.activePalette;
        else
            desiredHotbar = savedHotbarPaletteIfInCycle(savedPalette) or firstHotbarPaletteInCycle();
        end
    else
        desiredHotbar = savedHotbarPaletteIfInCycle(savedPalette) or firstHotbarPaletteInCycle();
    end

    if oldHotbarPalette ~= desiredHotbar then
        state.activePalette = desiredHotbar;
        for i = 1, 6 do
            M.FirePaletteChangedCallbacks(i, oldHotbarPalette, desiredHotbar);
        end
    end

    SavePaletteState(jobId, subjobId);

    -- Ensure at least one crossbar palette exists for this job
    local firstCrossbarPalette = M.EnsureCrossbarDefaultPaletteExists(jobId, subjobId);
    if not firstCrossbarPalette then
        print('[XIUI palette] Warning: Failed to create default crossbar palette for job ' .. tostring(jobId));
    end

    -- Merge factory crossbar defaults into gConfig so keys like defaultCrossbarPaletteScope and
    -- enableUniversalCrossbarPalettes always resolve (older/partial profiles omit nested fields).
    if not gConfig.hotbarCrossbar then
        gConfig.hotbarCrossbar = {};
    end
    local factories = require('core.settings.factories');
    DeepMergeWithDefaults(gConfig.hotbarCrossbar, factories.createCrossbarDefaults());

    local function ProfileDefaultWantsUniversalCrossbar(cs)
        local v = cs and cs.defaultCrossbarPaletteScope;
        if type(v) ~= 'string' then
            return false;
        end
        local l = (v:lower():match('^%s*(.-)%s*$')) or '';
        return l == 'universal' or l == 'global';
    end

    local crossbarSettings = gConfig.hotbarCrossbar;
    local firstUniversal = nil;
    -- Apply Job vs Global [G] scope from profile before reconciling [J] tier palettes so callbacks see correct scope.
    if crossbarSettings and crossbarSettings.enableUniversalCrossbarPalettes then
        firstUniversal = M.EnsureUniversalCrossbarDefaultExists();
        if opts and opts.applyDefaultCrossbarScope == true then
            pendingApplyDefaultCrossbarScopeFromProfile = false;
            if ProfileDefaultWantsUniversalCrossbar(crossbarSettings) then
                state.crossbarPaletteScope = 'universal';
            else
                state.crossbarPaletteScope = 'job';
            end
        end
        if state.crossbarActiveUniversalPalette then
            local ulist = M.GetUniversalCrossbarPaletteNamesOrdered();
            local ufound = false;
            for _, n in ipairs(ulist) do
                if n == state.crossbarActiveUniversalPalette then
                    ufound = true;
                    break;
                end
            end
            if not ufound then
                local cyc = M.GetUniversalCrossbarPalettesForCycle();
                state.crossbarActiveUniversalPalette = (cyc[1] or firstUniversal);
            end
        elseif firstUniversal and state.crossbarPaletteScope == 'universal' then
            state.crossbarActiveUniversalPalette = firstUniversal;
        end
    elseif crossbarSettings then
        -- Feature explicitly disabled in profile — scope must be job tier only.
        state.crossbarPaletteScope = 'job';
    end

    local crossbarRowsAll = M.GetCrossbarManagePaletteRows(jobId, subjobId);
    local crossbarRowsCycle = M.GetCrossbarManagePaletteRowsInRbCycle(jobId, subjobId);

    local function pickFirstCrossbarRowInCycle()
        if #crossbarRowsCycle > 0 then
            return crossbarRowsCycle[1];
        end
        if #crossbarRowsAll > 0 then
            return crossbarRowsAll[1];
        end
        return nil;
    end

    if state.crossbarActivePalette then
        local matchRow = nil;
        for _, r in ipairs(crossbarRowsAll) do
            if r.name == state.crossbarActivePalette then
                if state.crossbarActiveStorageSubjob == nil then
                    state.crossbarActiveStorageSubjob = r.storageSubjob;
                end
                if r.storageSubjob == state.crossbarActiveStorageSubjob then
                    matchRow = r;
                    break;
                end
            end
        end
        local ok = matchRow and M.IsCrossbarPaletteInRbCycle(jobId, matchRow.storageSubjob, matchRow.name);
        if not ok then
            local oldPalette = state.crossbarActivePalette;
            local pick = pickFirstCrossbarRowInCycle();
            if pick then
                state.crossbarActivePalette = pick.name;
                state.crossbarActiveStorageSubjob = pick.storageSubjob;
            elseif firstCrossbarPalette then
                state.crossbarActivePalette = firstCrossbarPalette;
                state.crossbarActiveStorageSubjob = 0;
            end
            for _, mode in ipairs(CROSSBAR_COMBO_MODES) do
                M.FirePaletteChangedCallbacks('crossbar:' .. mode, oldPalette, state.crossbarActivePalette);
            end
        end
    else
        local pick = pickFirstCrossbarRowInCycle();
        if pick then
            state.crossbarActivePalette = pick.name;
            state.crossbarActiveStorageSubjob = pick.storageSubjob;
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
    state.crossbarActiveStorageSubjob = nil;
    state.crossbarPaletteScope = 'job';
    state.crossbarActiveUniversalPalette = nil;
end

-- Get state for persistence (if needed)
function M.GetState()
    return {
        activePalette = state.activePalette,
        crossbarActivePalette = state.crossbarActivePalette,
        crossbarActiveStorageSubjob = state.crossbarActiveStorageSubjob,
        crossbarPaletteScope = state.crossbarPaletteScope,
        crossbarActiveUniversalPalette = state.crossbarActiveUniversalPalette,
    };
end

-- Restore state from persistence (if needed)
function M.RestoreState(savedState)
    if savedState then
        state.activePalette = savedState.activePalette;
        state.crossbarActivePalette = savedState.crossbarActivePalette;
        state.crossbarActiveStorageSubjob = savedState.crossbarActiveStorageSubjob;
        if savedState.crossbarPaletteScope == 'job' or savedState.crossbarPaletteScope == 'universal' then
            state.crossbarPaletteScope = savedState.crossbarPaletteScope;
        end
        state.crossbarActiveUniversalPalette = savedState.crossbarActiveUniversalPalette;
    end
end

-- ============================================
-- Palette Copy/Move Operations (for Palette Manager)
-- ============================================

-- Copy a hotbar palette to a different job:subjob combination
-- newName: destination palette name (nil = same as source name)
-- overwriteExisting: if true, replace data on an existing destination palette (slot actions / macros on all 6 bars)
function M.CopyPalette(paletteName, fromJobId, fromSubjobId, toJobId, toSubjobId, newName, overwriteExisting)
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

    local destExists = false;
    for barIdx = 1, 6 do
        local configKey = 'hotbarBar' .. barIdx;
        local barSettings = gConfig and gConfig[configKey];
        if barSettings and barSettings.slotActions and barSettings.slotActions[destKey] then
            destExists = true;
            break;
        end
    end

    overwriteExisting = overwriteExisting == true;
    if destExists then
        if not overwriteExisting then
            return false, 'Palette already exists at destination';
        end
    elseif overwriteExisting then
        return false, 'No palette at that destination to overwrite';
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

    -- Add to destination's palette order (new palette only)
    if not destExists then
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
    end

    InvalidatePaletteListCache();
    SaveSettingsToDisk();
    return true;
end

-- Copy a crossbar palette to a different job:subjob combination
-- overwriteExisting: replace slot data on an existing destination palette
function M.CopyCrossbarPalette(paletteName, fromJobId, fromSubjobId, toJobId, toSubjobId, newName, overwriteExisting)
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

    local destExists = crossbarSettings.slotActions and crossbarSettings.slotActions[destKey] ~= nil;
    overwriteExisting = overwriteExisting == true;
    if destExists then
        if not overwriteExisting then
            return false, 'Palette already exists at destination';
        end
    elseif overwriteExisting then
        return false, 'No palette at that destination to overwrite';
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

    -- Add to destination's palette order (new palette only)
    if not destExists then
        local destOrderKey = BuildJobSubjobKey(toJobId, toSubjobId);
        if not crossbarSettings.crossbarPaletteOrder then
            crossbarSettings.crossbarPaletteOrder = {};
        end
        if not crossbarSettings.crossbarPaletteOrder[destOrderKey] then
            crossbarSettings.crossbarPaletteOrder[destOrderKey] = {};
        end
        table.insert(crossbarSettings.crossbarPaletteOrder[destOrderKey], destName);
    end

    InvalidatePaletteListCache();
    SaveSettingsToDisk();
    return true;
end

-- Copy a Job [J]/Subjob-tier crossbar palette into the Global [G] (all-jobs universal) namespace.
function M.CopyCrossbarPaletteToUniversal(paletteName, fromJobId, fromSubjobId, destName, overwriteExisting)
    if not paletteName then
        return false, 'No palette specified';
    end
    local outName = destName or paletteName;
    if not IsValidPaletteName(outName) then
        return false, 'Invalid destination palette name';
    end
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings then
        return false, 'Crossbar settings not found';
    end
    local sourceKey = FindCrossbarPaletteStorageKey(paletteName, fromJobId, fromSubjobId);
    if not sourceKey then
        return false, 'Source palette not found';
    end
    if not crossbarSettings.slotActions then
        crossbarSettings.slotActions = {};
    end
    local destKey = M.BuildUniversalCrossbarStorageKey(outName);
    if not destKey then
        return false, 'Invalid destination key';
    end
    local destExists = crossbarSettings.slotActions[destKey] ~= nil;
    overwriteExisting = overwriteExisting == true;
    if destExists then
        if not overwriteExisting then
            return false, 'Palette already exists at destination';
        end
    elseif overwriteExisting then
        return false, 'No palette at that destination to overwrite';
    end
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
    if not destExists then
        if not crossbarSettings.universalCrossbarPaletteOrder then
            crossbarSettings.universalCrossbarPaletteOrder = {};
        end
        table.insert(crossbarSettings.universalCrossbarPaletteOrder, outName);
        if not crossbarSettings.crossbarUniversalPaletteMeta then
            crossbarSettings.crossbarUniversalPaletteMeta = {};
        end
        if not crossbarSettings.crossbarUniversalPaletteMeta[outName] then
            crossbarSettings.crossbarUniversalPaletteMeta[outName] = { includeInCycle = true };
        end
    end
    InvalidatePaletteListCache();
    InvalidateAllVisualCachesAfterPaletteListMutation();
    SaveSettingsToDisk();
    return true;
end

-- Copy a Global [G] universal crossbar palette into a Job [J]/Subjob-tier palette.
function M.CopyUniversalCrossbarPaletteToJob(sourceName, destName, toJobId, toSubjobId, overwriteExisting)
    if not sourceName or sourceName == '' then
        return false, 'No palette specified';
    end
    local outName = destName or sourceName;
    if not IsValidPaletteName(outName) then
        return false, 'Invalid destination palette name';
    end
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings then
        return false, 'Crossbar settings not found';
    end
    if not crossbarSettings.slotActions then
        crossbarSettings.slotActions = {};
    end
    local sourceKey = M.BuildUniversalCrossbarStorageKey(sourceName);
    if not crossbarSettings.slotActions[sourceKey] then
        return false, 'Source palette not found';
    end
    local normalizedJobId = toJobId or 1;
    local normalizedSubjobId = toSubjobId or 0;
    local destKey = M.BuildPaletteStorageKey(normalizedJobId, normalizedSubjobId, outName);
    local destExists = crossbarSettings.slotActions[destKey] ~= nil;
    overwriteExisting = overwriteExisting == true;
    if destExists then
        if not overwriteExisting then
            return false, 'Palette already exists at destination';
        end
    elseif overwriteExisting then
        return false, 'No palette at that destination to overwrite';
    end
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
    if not destExists then
        local destOrderKey = BuildJobSubjobKey(normalizedJobId, normalizedSubjobId);
        if not crossbarSettings.crossbarPaletteOrder then
            crossbarSettings.crossbarPaletteOrder = {};
        end
        if not crossbarSettings.crossbarPaletteOrder[destOrderKey] then
            crossbarSettings.crossbarPaletteOrder[destOrderKey] = {};
        end
        table.insert(crossbarSettings.crossbarPaletteOrder[destOrderKey], outName);
    end
    InvalidatePaletteListCache();
    InvalidateAllVisualCachesAfterPaletteListMutation();
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

-- ============================================
-- Deferred Save State Management
-- ============================================

-- Check if palette state has unsaved changes
function M.IsPaletteStateDirty()
    return paletteStateDirty;
end

-- Clear the dirty flag (call after saving)
function M.ClearPaletteStateDirty()
    paletteStateDirty = false;
end

-- Flush any pending save (call on unload)
function M.FlushPendingSave()
    if paletteStateDirty then
        SaveSettingsToDisk();
        paletteStateDirty = false;
    end
end

return M;
