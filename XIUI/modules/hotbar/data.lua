--[[
* XIUI hotbar - Data Module
* Handles state, font storage, and primitive handles
]]--

require('common');

local M = {};

-- Lazy-loaded to avoid circular dependencies
local petpalette = nil;
local function getPetPalette()
    if not petpalette then
        petpalette = require('modules.hotbar.petpalette');
    end
    return petpalette;
end

local palette = nil;
local function getPalette()
    if not palette then
        palette = require('modules.hotbar.palette');
    end
    return palette;
end

-- ============================================
-- Constants
-- ============================================

M.NUM_BARS = 6;                    -- Total number of hotbars
M.SLOTS_PER_BAR = 12;              -- Default slots per hotbar
M.MAX_SLOTS_PER_BAR = 12;          -- Maximum slots per hotbar

-- Layout constants
M.PADDING = 4;
M.BUTTON_GAP = 8;
M.LABEL_GAP = -8;  -- Default label position offset (was 4, moved up by 12px)
M.ROW_GAP = 6;

-- ============================================
-- Per-Bar State
-- ============================================

-- Background primitive handles (one per bar)
M.bgHandles = {};

-- Button slot primitives (per bar, per slot)
-- M.slotPrims[barIndex][slotIndex] = primitive
M.slotPrims = {};

-- Fonts for keybind labels (per bar, per slot)
-- M.keybindFonts[barIndex][slotIndex] = font
M.keybindFonts = {};

-- Fonts for action labels (per bar, per slot)
-- M.labelFonts[barIndex][slotIndex] = font
M.labelFonts = {};

-- Icon primitives (per bar, per slot)
-- Renders action icons as primitives instead of ImGui
M.iconPrims = {};

-- Cooldown overlay primitives (per bar, per slot)
-- Dark overlay shown when action is on cooldown
M.cooldownPrims = {};

-- Frame overlay primitives (per bar, per slot)
-- Decorative frame rendered above icons
M.framePrims = {};

-- Cooldown timer fonts (per bar, per slot)
-- Shows remaining recast time (e.g., "2:30", "45s")
M.timerFonts = {};

-- MP cost fonts (per bar, per slot)
-- Shows MP cost for magic spells
M.mpCostFonts = {};

-- Item quantity fonts (per bar, per slot)
-- Shows quantity of usable items (e.g., "x5")
M.quantityFonts = {};

-- Fonts for hotbar numbers (1-6)
M.hotbarNumberFonts = {};

-- All fonts for batch operations
M.allFonts = nil;

-- ============================================
-- Job State
-- ============================================

M.jobId = nil;
M.subjobId = nil;

-- ============================================
-- Helper Functions
-- ============================================

-- Special key for global (non-job-specific) slot storage
local GLOBAL_SLOT_KEY = 'global';

-- Helper to normalize job ID to number (handles string keys from JSON)
local function normalizeJobId(jobId)
    if type(jobId) == 'string' then
        return tonumber(jobId) or 1;
    end
    return jobId or 1;
end

-- Helper to get the storage key based on jobSpecific setting
-- Returns 'global' for global mode, or '{jobId}:{subjobId}' for job-specific mode
local function getStorageKey(barSettings, jobId, subjobId)
    if barSettings.jobSpecific == false then
        return GLOBAL_SLOT_KEY;
    end
    -- Always return composite key with job:subjob
    local normalizedJobId = normalizeJobId(jobId);
    local normalizedSubjobId = normalizeJobId(subjobId or 0);
    return string.format('%d:%d', normalizedJobId, normalizedSubjobId);
end


-- Helper to get slotActions with storage key
-- Handles: 'global' and composite keys ('15:10', '15:10:avatar:ifrit', '15:10:palette:name')
-- Falls back to base job key (jobId:0) or base palette key (jobId:0:palette:name) if exact key doesn't exist
local function getSlotActionsForJob(slotActions, storageKey)
    if not slotActions then return nil; end
    -- Handle 'global' key specially
    if storageKey == GLOBAL_SLOT_KEY then
        return slotActions[GLOBAL_SLOT_KEY];
    end
    -- Try exact storage key first (e.g., '3:5' for WHM/RDM, '3:5:palette:Esuna')
    local result = slotActions[storageKey];
    if result then
        return result;
    end
    -- Fallback: try base job key (jobId:0) for imported data without subjob
    -- This handles tHotBar imports which don't track subjobs
    local jobId, subjobId, suffix = storageKey:match('^(%d+):(%d+)(.*)$');
    if jobId and subjobId ~= '0' then
        -- Build fallback key with subjob=0, preserving any suffix (palette, avatar, etc.)
        local fallbackKey = jobId .. ':0' .. (suffix or '');
        result = slotActions[fallbackKey];
        if result then
            return result;
        end
    end
    return nil;
end

-- Helper to deep copy a table (for migrating slot data)
local function deepCopyTable(tbl)
    if type(tbl) ~= 'table' then return tbl; end
    local copy = {};
    for k, v in pairs(tbl) do
        copy[k] = deepCopyTable(v);
    end
    return copy;
end

-- Helper to ensure slotActions structure exists for a storage key
-- Handles: 'global' and composite keys ('15:10', '15:10:avatar:ifrit')
-- IMPORTANT: When creating a new key, copies data from fallback keys to preserve slot data
local function ensureSlotActionsStructure(barSettings, storageKey)
    if not barSettings.slotActions then
        barSettings.slotActions = {};
    end
    -- Handle 'global' key specially
    if storageKey == GLOBAL_SLOT_KEY then
        if not barSettings.slotActions[GLOBAL_SLOT_KEY] then
            barSettings.slotActions[GLOBAL_SLOT_KEY] = {};
        end
        return barSettings.slotActions[GLOBAL_SLOT_KEY];
    end
    -- All job-specific keys are composite strings (job:subjob format)
    if not barSettings.slotActions[storageKey] then
        -- Before creating empty table, check for fallback data to migrate
        -- This preserves slot data when subjob changes (e.g., '1:0' -> '1:5')
        local jobId, subjobId, suffix = storageKey:match('^(%d+):(%d+)(.*)$');
        if jobId and subjobId ~= '0' then
            -- Build fallback key with subjob=0, preserving any suffix (palette, avatar, etc.)
            local fallbackKey = jobId .. ':0' .. (suffix or '');
            local fallbackData = barSettings.slotActions[fallbackKey];
            if fallbackData then
                -- Deep copy fallback data to the new key to preserve all slots
                barSettings.slotActions[storageKey] = deepCopyTable(fallbackData);
            else
                barSettings.slotActions[storageKey] = {};
            end
        else
            barSettings.slotActions[storageKey] = {};
        end
    end
    return barSettings.slotActions[storageKey];
end

-- Keys that are always per-bar (never pulled from global)
local PER_BAR_ONLY_KEYS = {
    enabled = true,
    rows = true,
    columns = true,
    slots = true,
    useGlobalSettings = true,
    keybinds = true,
    slotActions = true,
    jobSpecific = true,
    petAware = true,
};

-- ============================================
-- Job/Subjob Storage Key Resolution
-- ============================================

-- Build full storage key for a bar, considering job, subjob, pet awareness, and general palettes
-- Returns: 'global', '{jobId}:{subjobId}', '{jobId}:{subjobId}:{petKey}', or '{jobId}:{subjobId}:palette:{name}'
-- Priority: global > pet-aware > general palette > base
function M.GetStorageKeyForBar(barIndex)
    local configKey = 'hotbarBar' .. barIndex;
    local barSettings = gConfig and gConfig[configKey];
    local jobId = M.jobId or 1;
    local subjobId = M.subjobId or 0;

    -- Build base job:subjob key
    local baseKey = string.format('%d:%d', normalizeJobId(jobId), normalizeJobId(subjobId));

    if not barSettings then
        return baseKey;
    end

    -- Global mode (non-job-specific)
    if barSettings.jobSpecific == false then
        return GLOBAL_SLOT_KEY;
    end

    -- Check if pet-aware mode is enabled for this bar
    if barSettings.petAware then
        -- Get pet palette module (lazy load)
        local pp = getPetPalette();
        if pp then
            -- Check for manual override or auto-detected pet
            local effectivePetKey = pp.GetEffectivePetKey(barIndex);
            if effectivePetKey then
                return string.format('%s:%s', baseKey, effectivePetKey);
            end
        end
    end

    -- Check for general palette (user-defined named palettes)
    local p = getPalette();
    if p then
        local paletteSuffix = p.GetEffectivePaletteKeySuffix(barIndex);
        if paletteSuffix then
            return string.format('%s:%s', baseKey, paletteSuffix);
        end
    end

    -- No pet or palette - fall back to base job:subjob key
    return baseKey;
end

-- Get available storage keys (palettes) for a bar
-- Used for cycling and display
-- Returns combined list of pet palettes (if petAware) and general palettes
function M.GetAvailablePalettes(barIndex)
    local configKey = 'hotbarBar' .. barIndex;
    local barSettings = gConfig and gConfig[configKey];
    local jobId = M.jobId or 1;
    local subjobId = M.subjobId or 0;

    local palettes = {};

    -- Add pet palettes if pet-aware mode is enabled
    if barSettings and barSettings.petAware then
        local pp = getPetPalette();
        if pp then
            local petPalettes = pp.GetAvailablePalettes(barIndex, jobId, subjobId);
            for _, p in ipairs(petPalettes) do
                table.insert(palettes, p);
            end
        end
    end

    -- Add general palettes (if any exist)
    local p = getPalette();
    if p then
        local generalPalettes = p.GetAvailablePalettes(barIndex, jobId, subjobId);
        for _, name in ipairs(generalPalettes) do
            -- Convert general palette name to the same format as pet palettes
            table.insert(palettes, {
                key = p.PALETTE_KEY_PREFIX .. name,
                displayName = name,
                isPetPalette = false,
            });
        end
    end

    return palettes;
end

-- Get the current palette display name for a bar
-- Returns: nil (no palette), pet name (e.g., 'Ifrit'), or general palette name (e.g., 'Stuns')
function M.GetCurrentPaletteDisplayName(barIndex)
    local configKey = 'hotbarBar' .. barIndex;
    local barSettings = gConfig and gConfig[configKey];
    local jobId = M.jobId or 1;

    -- Check pet palette first (if pet-aware)
    if barSettings and barSettings.petAware then
        local pp = getPetPalette();
        if pp then
            local petDisplayName = pp.GetPaletteDisplayName(barIndex, jobId);
            if petDisplayName and petDisplayName ~= 'Base' then
                return petDisplayName;
            end
        end
    end

    -- Check general palette
    local p = getPalette();
    if p then
        return p.GetActivePaletteDisplayName(barIndex);
    end

    return nil;
end

-- Get the palette module for direct access
function M.GetPaletteModule()
    return getPalette();
end

-- Get the pet palette module for direct access
function M.GetPetPaletteModule()
    return getPetPalette();
end

-- ============================================
-- Crossbar Storage Key Resolution (Per-Combo-Mode)
-- ============================================

-- Build full storage key for a crossbar combo mode, considering job, subjob, pet awareness, and palettes
-- Each combo mode (L2, R2, L2R2, etc.) has its own petAware and activePalette settings
-- Returns: 'global', '{jobId}:{subjobId}', '{jobId}:{subjobId}:{petKey}', or '{jobId}:{subjobId}:palette:{name}'
function M.GetCrossbarStorageKeyForCombo(comboMode)
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings then
        return string.format('%d:%d', M.jobId or 1, M.subjobId or 0);
    end

    local jobId = M.jobId or 1;
    local subjobId = M.subjobId or 0;

    -- Global mode (non-job-specific)
    if crossbarSettings.jobSpecific == false then
        return GLOBAL_SLOT_KEY;
    end

    -- Build base job:subjob key
    local baseKey = string.format('%d:%d', normalizeJobId(jobId), normalizeJobId(subjobId));

    -- Get per-combo-mode settings
    local modeSettings = crossbarSettings.comboModeSettings and crossbarSettings.comboModeSettings[comboMode];

    -- Check pet-aware mode for this combo mode
    if modeSettings and modeSettings.petAware then
        local pp = getPetPalette();
        if pp then
            local effectivePetKey = pp.GetEffectivePetKeyForCombo(comboMode);
            if effectivePetKey then
                return string.format('%s:%s', baseKey, effectivePetKey);
            end
        end
    end

    -- Check for general palette for this combo mode
    if modeSettings and modeSettings.activePalette then
        local p = getPalette();
        if p then
            return p.BuildStorageKey(baseKey, modeSettings.activePalette);
        end
    end

    -- No pet or palette - fall back to base job:subjob key
    return baseKey;
end

-- Get the current palette display name for a crossbar combo mode
-- Returns: 'Base', pet name (e.g., 'Ifrit'), or general palette name (e.g., 'Stuns')
function M.GetCrossbarPaletteDisplayName(comboMode)
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    local modeSettings = crossbarSettings and crossbarSettings.comboModeSettings and crossbarSettings.comboModeSettings[comboMode];
    local jobId = M.jobId or 1;

    -- Check pet palette first (if pet-aware)
    if modeSettings and modeSettings.petAware then
        local pp = getPetPalette();
        if pp then
            local petDisplayName = pp.GetCrossbarPaletteDisplayName(comboMode, jobId);
            if petDisplayName and petDisplayName ~= 'Base' then
                return petDisplayName;
            end
        end
    end

    -- Check general palette
    if modeSettings and modeSettings.activePalette then
        return modeSettings.activePalette;
    end

    return 'Base';
end

-- Get per-bar settings from gConfig, merging with global if useGlobalSettings is true
function M.GetBarSettings(barIndex)
    local configKey = 'hotbarBar' .. barIndex;
    local barConfig = gConfig and gConfig[configKey];

    if not barConfig then
        -- Return fallback defaults
        return {
            enabled = true,
            useGlobalSettings = true,
            rows = 1,
            columns = 12,
            slots = 12,
            slotSize = 48,
            bgScale = 1.0,
            borderScale = 1.0,
            backgroundOpacity = 0.87,
            borderOpacity = 1.0,
            backgroundTheme = '-None-',
            showHotbarNumber = true,
            showSlotFrame = false,
            customFramePath = '',
            showActionLabels = false,
            actionLabelOffsetX = 0,
            actionLabelOffsetY = 0,
            slotXPadding = 8,
            slotYPadding = 6,
            slotBackgroundColor = 0x55000000,
            bgColor = 0xFFFFFFFF,
            borderColor = 0xFFFFFFFF,
            showKeybinds = true,
            keybindFontSize = 10,
            keybindFontColor = 0xFFFFFFFF,
            labelFontSize = 10,
            labelFontColor = 0xFFFFFFFF,
            labelCooldownColor = 0xFF888888,
            labelNoMpColor = 0xFFFF4444,
            showMpCost = true,
            mpCostFontSize = 10,
            mpCostFontColor = 0xFFD4FF97,
            showQuantity = true,
            quantityFontSize = 10,
            quantityFontColor = 0xFFFFFFFF,
        };
    end

    -- If useGlobalSettings is true, merge global visual settings
    if barConfig.useGlobalSettings and gConfig.hotbarGlobal then
        local merged = {};
        -- Start with global settings
        for k, v in pairs(gConfig.hotbarGlobal) do
            merged[k] = v;
        end
        -- Override with per-bar settings (layout and per-bar-only keys)
        for k, v in pairs(barConfig) do
            if PER_BAR_ONLY_KEYS[k] then
                merged[k] = v;
            end
        end
        return merged;
    end

    return barConfig;
end

-- Get bar layout info (reads from per-bar settings)
function M.GetBarLayout(barIndex)
    local barSettings = M.GetBarSettings(barIndex);
    local rows = barSettings.rows or 1;
    local columns = barSettings.columns or 12;

    -- Always calculate slots from rows * columns (ignore stored slots value)
    local slots = rows * columns;

    -- Ensure slots doesn't exceed max
    slots = math.min(slots, M.MAX_SLOTS_PER_BAR);

    return {
        isVertical = rows > 1,
        columns = columns,
        rows = rows,
        slots = slots,
    };
end

-- Get number of slots for a bar
function M.GetBarSlotCount(barIndex)
    local layout = M.GetBarLayout(barIndex);
    return layout.slots;
end

-- Virtual key code to short display string mapping
local VK_SHORT_NAMES = {
    [8] = 'Bksp', [9] = 'Tab', [13] = 'Ent', [27] = 'Esc', [32] = 'Spc',
    [33] = 'PgU', [34] = 'PgD', [35] = 'End', [36] = 'Hom',
    [37] = 'L', [38] = 'U', [39] = 'R', [40] = 'D',
    [45] = 'Ins', [46] = 'Del',
    [96] = 'N0', [97] = 'N1', [98] = 'N2', [99] = 'N3', [100] = 'N4',
    [101] = 'N5', [102] = 'N6', [103] = 'N7', [104] = 'N8', [105] = 'N9',
    [106] = 'N*', [107] = 'N+', [109] = 'N-', [110] = 'N.', [111] = 'N/',
    [112] = 'F1', [113] = 'F2', [114] = 'F3', [115] = 'F4', [116] = 'F5', [117] = 'F6',
    [118] = 'F7', [119] = 'F8', [120] = 'F9', [121] = 'F10', [122] = 'F11', [123] = 'F12',
    [186] = ';', [187] = '=', [188] = ',', [189] = '-', [190] = '.', [191] = '/',
    [192] = '`', [219] = '[', [220] = '\\', [221] = ']', [222] = "'",
};

-- Convert virtual key code to short display string
local function VKToShortString(vk)
    if VK_SHORT_NAMES[vk] then return VK_SHORT_NAMES[vk]; end
    if vk >= 48 and vk <= 57 then return tostring(vk - 48); end  -- 0-9
    if vk >= 65 and vk <= 90 then return string.char(vk); end    -- A-Z
    return '?';
end

-- Format a keybind for short display (e.g., "C1" for Ctrl+1)
local function FormatKeybindShort(binding)
    if not binding or not binding.key then return ''; end
    local prefix = '';
    if binding.ctrl then prefix = prefix .. 'C'; end
    if binding.alt then prefix = prefix .. 'A'; end
    if binding.shift then prefix = prefix .. 'S'; end
    local keyStr = VKToShortString(binding.key);
    return prefix .. keyStr;
end

-- Get keybind display string for a slot
function M.GetKeybindDisplay(barIndex, slotIndex)
    -- Check for custom keybind first
    local configKey = 'hotbarBar' .. barIndex;
    local barSettings = gConfig and gConfig[configKey];
    if barSettings and barSettings.keyBindings then
        -- Handle both numeric and string keys (JSON serialization converts numeric keys to strings)
        local binding = barSettings.keyBindings[slotIndex] or barSettings.keyBindings[tostring(slotIndex)];
        if binding and binding.key then
            return FormatKeybindShort(binding);
        end
    end

    -- No custom keybind - return empty or slot number
    return '';
end

-- Helper to look up a macro from macroDB by id
-- paletteKey can be a job ID (number) or composite key (string like "15:avatar:ifrit")
local function GetMacroById(macroId, paletteKey)
    if not gConfig or not gConfig.macroDB then return nil; end

    -- Try the specific palette key first
    local macros = gConfig.macroDB[paletteKey];
    if macros then
        for _, macro in ipairs(macros) do
            if macro.id == macroId then
                return macro;
            end
        end
    end

    -- If paletteKey is a composite key and macro not found, try base job palette
    if type(paletteKey) == 'string' then
        local baseJobId = tonumber(paletteKey:match('^(%d+)'));
        if baseJobId then
            local baseMacros = gConfig.macroDB[baseJobId];
            if baseMacros then
                for _, macro in ipairs(baseMacros) do
                    if macro.id == macroId then
                        return macro;
                    end
                end
            end
        end
    end

    return nil;
end

-- Get action assignment for a specific bar and slot
function M.GetKeybindForSlot(barIndex, slotIndex)
    -- First check for custom slot actions in per-bar settings
    local configKey = 'hotbarBar' .. barIndex;
    if gConfig and gConfig[configKey] then
        local barSettings = gConfig[configKey];
        -- Use pet-aware storage key (handles global, job-specific, and pet palettes)
        local storageKey = M.GetStorageKeyForBar(barIndex);
        local jobSlotActions = getSlotActionsForJob(barSettings.slotActions, storageKey);

        -- NOTE: Do NOT fall back to base job when pet palette is active
        -- If user has a pet out and petAware enabled, show the pet-specific palette (even if empty)
        -- This prevents the base job summon macros from showing when an avatar is summoned
        if jobSlotActions then
            -- Handle both numeric and string keys (JSON serialization converts numeric keys to strings)
            local numericSlot = tonumber(slotIndex) or slotIndex;
            local slotAction = jobSlotActions[numericSlot] or jobSlotActions[tostring(numericSlot)];
            if slotAction then
                -- Check for "cleared" marker - slot was explicitly emptied
                if slotAction.cleared then
                    return nil;  -- Don't fall back to defaults
                end

                -- If this slot has a macro reference, look up the current macro data
                -- This ensures icon changes in the palette are reflected on the hotbar
                local macroData = slotAction;
                if slotAction.macroRef then
                    -- Use stored palette key if available, otherwise fall back to job ID
                    local paletteKey = slotAction.macroPaletteKey or M.jobId;
                    local liveMacro = GetMacroById(slotAction.macroRef, paletteKey);
                    if liveMacro then
                        macroData = liveMacro;
                    end
                    -- If macro was deleted, fall back to the cached slotAction data
                end

                -- Return slot action in the same format as parsed keybinds
                return {
                    context = 'battle',
                    hotbar = barIndex,
                    slot = slotIndex,
                    actionType = macroData.actionType,
                    action = macroData.action,
                    target = macroData.target,
                    displayName = macroData.displayName or macroData.action,
                    equipSlot = macroData.equipSlot,
                    macroText = macroData.macroText,
                    itemId = macroData.itemId,
                    customIconType = macroData.customIconType,
                    customIconId = macroData.customIconId,
                    customIconPath = macroData.customIconPath,
                };
            end
        end
    end

    return nil;
end

-- ============================================
-- Crossbar Slot Data Helpers
-- ============================================

-- Helper to get the crossbar storage key based on jobSpecific setting
-- Returns 'global' or '{jobId}:{subjobId}' format
local function getCrossbarStorageKey(crossbarSettings, jobId, subjobId)
    if crossbarSettings.jobSpecific == false then
        return GLOBAL_SLOT_KEY;
    end
    -- Always return composite key with job:subjob
    local normalizedJobId = normalizeJobId(jobId);
    local normalizedSubjobId = normalizeJobId(subjobId or 0);
    return string.format('%d:%d', normalizedJobId, normalizedSubjobId);
end

-- Helper to get crossbar slotActions with storage key
-- Handles: 'global' and composite keys ('15:10', '15:10:palette:Stuns', '15:10:avatar:ifrit')
-- Falls back to base job key (jobId:0) preserving any suffix if full job:subjob key doesn't exist
local function getCrossbarSlotActionsForJob(slotActions, storageKey)
    if not slotActions then return nil; end
    -- Handle 'global' key specially
    if storageKey == GLOBAL_SLOT_KEY then
        return slotActions[GLOBAL_SLOT_KEY];
    end
    -- Try exact storage key first (e.g., '3:5' for WHM/RDM, '3:5:palette:Stuns')
    local result = slotActions[storageKey];
    if result then
        return result;
    end
    -- Fallback: try base job key (jobId:0) for imported data without subjob
    -- IMPORTANT: Preserve any suffix (palette:X, avatar:Y) in the fallback key
    local jobId, subjobId, suffix = storageKey:match('^(%d+):(%d+)(.*)$');
    if jobId and subjobId ~= '0' then
        local fallbackKey = jobId .. ':0' .. (suffix or '');
        if fallbackKey ~= storageKey then
            return slotActions[fallbackKey];
        end
    end
    return nil;
end

-- Helper to ensure crossbar slotActions structure exists for a storage key and combo mode
-- Handles: 'global' and composite keys ('15:10')
local function ensureCrossbarSlotActionsStructure(crossbarSettings, storageKey, comboMode)
    if not crossbarSettings.slotActions then
        crossbarSettings.slotActions = {};
    end
    -- Handle 'global' key specially
    if storageKey == GLOBAL_SLOT_KEY then
        if not crossbarSettings.slotActions[GLOBAL_SLOT_KEY] then
            crossbarSettings.slotActions[GLOBAL_SLOT_KEY] = {};
        end
        if not crossbarSettings.slotActions[GLOBAL_SLOT_KEY][comboMode] then
            crossbarSettings.slotActions[GLOBAL_SLOT_KEY][comboMode] = {};
        end
        return crossbarSettings.slotActions[GLOBAL_SLOT_KEY][comboMode];
    end
    -- All job-specific keys are composite strings (job:subjob format)
    if not crossbarSettings.slotActions[storageKey] then
        crossbarSettings.slotActions[storageKey] = {};
    end
    if not crossbarSettings.slotActions[storageKey][comboMode] then
        crossbarSettings.slotActions[storageKey][comboMode] = {};
    end
    return crossbarSettings.slotActions[storageKey][comboMode];
end

-- Get slot data for a crossbar slot
-- comboMode: 'L2', 'R2', 'L2R2', 'R2L2', 'L2x2', or 'R2x2'
-- slotIndex: 1-8
-- Returns nil if no data exists
function M.GetCrossbarSlotData(comboMode, slotIndex)
    local jobId = M.jobId or 1;

    if not gConfig.hotbarCrossbar then return nil; end

    -- Use per-combo-mode storage key (considers pet-aware and palette settings per combo)
    local storageKey = M.GetCrossbarStorageKeyForCombo(comboMode);
    local jobSlotActions = getCrossbarSlotActionsForJob(gConfig.hotbarCrossbar.slotActions, storageKey);
    if not jobSlotActions then return nil; end
    if not jobSlotActions[comboMode] then return nil; end

    local slotAction = jobSlotActions[comboMode][slotIndex];
    if not slotAction then return nil; end

    -- If this slot has a macro reference, look up the current macro data
    -- This ensures icon changes in the palette are reflected on the crossbar
    if slotAction.macroRef then
        -- Use stored palette key if available, otherwise fall back to job ID
        local paletteKey = slotAction.macroPaletteKey or jobId;
        local liveMacro = GetMacroById(slotAction.macroRef, paletteKey);
        if liveMacro then
            -- Return fresh macro data (preserving any slot-specific overrides if needed)
            return {
                actionType = liveMacro.actionType,
                action = liveMacro.action,
                target = liveMacro.target,
                displayName = liveMacro.displayName,
                equipSlot = liveMacro.equipSlot,
                macroText = liveMacro.macroText,
                itemId = liveMacro.itemId,
                customIconType = liveMacro.customIconType,
                customIconId = liveMacro.customIconId,
                customIconPath = liveMacro.customIconPath,
                macroRef = slotAction.macroRef,
                macroPaletteKey = slotAction.macroPaletteKey,
            };
        end
        -- If macro was deleted, fall back to cached slotAction data
    end

    return slotAction;
end

-- Set slot data for a crossbar slot
-- comboMode: 'L2', 'R2', 'L2R2', 'R2L2', 'L2x2', or 'R2x2'
-- slotIndex: 1-8
-- slotData: { actionType, action, target, displayName, equipSlot, macroText, itemId, customIconType, customIconId, customIconPath }
--           or nil to clear the slot
function M.SetCrossbarSlotData(comboMode, slotIndex, slotData)
    -- If slotData is nil, clear the slot instead
    if not slotData then
        M.ClearCrossbarSlotData(comboMode, slotIndex);
        return;
    end

    -- Ensure config structure exists using helper (handles key normalization)
    if not gConfig.hotbarCrossbar then
        gConfig.hotbarCrossbar = {};
    end

    -- Use per-combo-mode storage key (considers pet-aware and palette settings per combo)
    local storageKey = M.GetCrossbarStorageKeyForCombo(comboMode);
    local comboSlots = ensureCrossbarSlotActionsStructure(gConfig.hotbarCrossbar, storageKey, comboMode);

    -- Store the slot data
    -- Use macroRef if present (from slot swap), otherwise use id (from macro palette drop)
    comboSlots[slotIndex] = {
        actionType = slotData.actionType,
        action = slotData.action,
        target = slotData.target,
        displayName = slotData.displayName,
        equipSlot = slotData.equipSlot,
        macroText = slotData.macroText,
        itemId = slotData.itemId,
        customIconType = slotData.customIconType,
        customIconId = slotData.customIconId,
        customIconPath = slotData.customIconPath,
        macroRef = slotData.macroRef or slotData.id,  -- Store reference to source macro for live updates
        macroPaletteKey = slotData.macroPaletteKey,  -- Store which palette the macro came from
    };

    SaveSettingsToDisk();
end

-- Clear a crossbar slot (sets to nil)
-- comboMode: 'L2', 'R2', 'L2R2', 'R2L2', 'L2x2', or 'R2x2'
-- slotIndex: 1-8
function M.ClearCrossbarSlotData(comboMode, slotIndex)
    -- Early return if structure doesn't exist
    if not gConfig.hotbarCrossbar then return; end

    -- Use per-combo-mode storage key (considers pet-aware and palette settings per combo)
    local storageKey = M.GetCrossbarStorageKeyForCombo(comboMode);
    local jobSlotActions = getCrossbarSlotActionsForJob(gConfig.hotbarCrossbar.slotActions, storageKey);
    if not jobSlotActions then return; end
    if not jobSlotActions[comboMode] then return; end

    -- Clear the slot
    jobSlotActions[comboMode][slotIndex] = nil;

    SaveSettingsToDisk();
end

-- Clear all slot actions for a hotbar (used when switching between job-specific and global modes)
function M.ClearAllBarSlotActions(barIndex)
    local configKey = 'hotbarBar' .. barIndex;
    if gConfig and gConfig[configKey] then
        gConfig[configKey].slotActions = {};
        SaveSettingsToDisk();
    end
end

-- Clear all slot actions for the crossbar (used when switching between job-specific and global modes)
function M.ClearAllCrossbarSlotActions()
    if gConfig.hotbarCrossbar then
        gConfig.hotbarCrossbar.slotActions = {};
        SaveSettingsToDisk();
    end
end

-- ============================================
-- Pet-Aware Slot Data Functions
-- ============================================

-- Set slot data for a hotbar slot (pet-aware)
-- Uses current storage key (which considers pet-aware mode)
function M.SetSlotData(barIndex, slotIndex, slotData)
    local configKey = 'hotbarBar' .. barIndex;
    if not gConfig or not gConfig[configKey] then return; end

    local barSettings = gConfig[configKey];
    local storageKey = M.GetStorageKeyForBar(barIndex);
    local jobSlotActions = ensureSlotActionsStructure(barSettings, storageKey);

    if slotData then
        jobSlotActions[slotIndex] = {
            actionType = slotData.actionType,
            action = slotData.action,
            target = slotData.target,
            displayName = slotData.displayName,
            equipSlot = slotData.equipSlot,
            macroText = slotData.macroText,
            itemId = slotData.itemId,
            customIconType = slotData.customIconType,
            customIconId = slotData.customIconId,
            customIconPath = slotData.customIconPath,
            macroRef = slotData.macroRef or slotData.id,
            macroPaletteKey = slotData.macroPaletteKey,  -- Store which palette the macro came from
        };
    else
        -- Mark as explicitly cleared
        jobSlotActions[slotIndex] = { cleared = true };
    end

    SaveSettingsToDisk();
end

-- Clear slot data for a hotbar slot (pet-aware)
function M.ClearSlotData(barIndex, slotIndex)
    local configKey = 'hotbarBar' .. barIndex;
    if not gConfig or not gConfig[configKey] then return; end

    local barSettings = gConfig[configKey];
    local storageKey = M.GetStorageKeyForBar(barIndex);
    local jobSlotActions = getSlotActionsForJob(barSettings.slotActions, storageKey);

    if jobSlotActions then
        -- Mark as explicitly cleared
        jobSlotActions[slotIndex] = { cleared = true };
        SaveSettingsToDisk();
    end
end

-- Get the current storage key for external use (e.g., macropalette)
function M.GetCurrentStorageKey(barIndex)
    return M.GetStorageKeyForBar(barIndex);
end

-- ============================================
-- Font Visibility Helpers
-- ============================================

-- Rebuild the flattened all-fonts list used for batch operations.
-- IMPORTANT: When fonts are recreated (FontManager.recreate), references change, so we must refresh this list
-- or SetAllFontsVisible() will toggle stale/destroyed objects and leave the new fonts visible.
function M.RebuildAllFonts()
    local all = {};

    for barIndex = 1, M.NUM_BARS do
        -- Per-slot fonts
        for slotIndex = 1, M.MAX_SLOTS_PER_BAR do
            local f;

            f = M.keybindFonts[barIndex] and M.keybindFonts[barIndex][slotIndex];
            if f then table.insert(all, f); end

            f = M.labelFonts[barIndex] and M.labelFonts[barIndex][slotIndex];
            if f then table.insert(all, f); end

            f = M.timerFonts[barIndex] and M.timerFonts[barIndex][slotIndex];
            if f then table.insert(all, f); end

            f = M.mpCostFonts[barIndex] and M.mpCostFonts[barIndex][slotIndex];
            if f then table.insert(all, f); end

            f = M.quantityFonts[barIndex] and M.quantityFonts[barIndex][slotIndex];
            if f then table.insert(all, f); end
        end

        -- Per-bar fonts
        if M.hotbarNumberFonts[barIndex] then
            table.insert(all, M.hotbarNumberFonts[barIndex]);
        end
    end

    M.allFonts = all;
end

function M.SetAllFontsVisible(visible)
    if M.allFonts then
        SetFontsVisible(M.allFonts, visible);
    end
end

function M.SetBarFontsVisible(barIndex, visible)
    -- Hotbar number font
    if M.hotbarNumberFonts[barIndex] then
        M.hotbarNumberFonts[barIndex]:set_visible(visible);
    end

    -- Keybind fonts for this bar
    if M.keybindFonts[barIndex] then
        for _, font in pairs(M.keybindFonts[barIndex]) do
            if font then
                font:set_visible(visible);
            end
        end
    end

    -- Label fonts for this bar
    if M.labelFonts[barIndex] then
        for _, font in pairs(M.labelFonts[barIndex]) do
            if font then
                font:set_visible(visible);
            end
        end
    end

    -- Timer fonts for this bar
    if M.timerFonts[barIndex] then
        for _, font in pairs(M.timerFonts[barIndex]) do
            if font then
                font:set_visible(visible);
            end
        end
    end

    -- MP cost fonts for this bar
    if M.mpCostFonts[barIndex] then
        for _, font in pairs(M.mpCostFonts[barIndex]) do
            if font then
                font:set_visible(visible);
            end
        end
    end

    -- Item quantity fonts for this bar
    if M.quantityFonts[barIndex] then
        for _, font in pairs(M.quantityFonts[barIndex]) do
            if font then
                font:set_visible(visible);
            end
        end
    end
end

-- ============================================
-- Preview Mode (stub for compatibility)
-- ============================================

function M.SetPreview(enabled)
end

function M.ClearPreview()
end

function M.ClearError()
end

-- ============================================
-- Lifecycle
-- ============================================

-- Initialize (called from init.lua)
function M.Initialize()
    M.SetPlayerJob();
end

function M.SetPlayerJob()
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    local currentJobId = player:GetMainJob();
    if(currentJobId == 0) then
       return;
    end
    local currentSubjobId = player:GetSubJob();

    M.jobId = currentJobId;
    M.subjobId = currentSubjobId;
end

-- Clear all state (call on zone change)
function M.Clear()
end

-- Cleanup (call on addon unload)
function M.Cleanup()
    M.Clear();
    M.bgHandles = {};
    M.slotPrims = {};
    M.iconPrims = {};
    M.cooldownPrims = {};
    M.framePrims = {};
    M.keybindFonts = {};
    M.labelFonts = {};
    M.timerFonts = {};
    M.mpCostFonts = {};
    M.quantityFonts = {};
    M.hotbarNumberFonts = {};
    M.allFonts = nil;
end

return M;
