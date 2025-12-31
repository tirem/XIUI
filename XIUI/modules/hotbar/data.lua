--[[
* XIUI hotbar - Data Module
* Handles state, font storage, and primitive handles
]]--

require('common');

local M = {};

-- ============================================
-- Constants
-- ============================================

M.NUM_BARS = 6;                    -- Total number of hotbars
M.SLOTS_PER_BAR = 12;              -- Default slots per hotbar
M.MAX_SLOTS_PER_BAR = 12;          -- Maximum slots per hotbar

-- Layout constants
M.PADDING = 4;
M.BUTTON_GAP = 8;
M.LABEL_GAP = 4;
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

-- Cooldown timer fonts (per bar, per slot)
-- Shows remaining recast time (e.g., "2:30", "45s")
M.timerFonts = {};

-- MP cost fonts (per bar, per slot)
-- Shows MP cost for magic spells
M.mpCostFonts = {};

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
-- Returns 'global' for global mode, or numeric job ID for job-specific mode
local function getStorageKey(barSettings, jobId)
    if barSettings.jobSpecific == false then
        return GLOBAL_SLOT_KEY;
    end
    return normalizeJobId(jobId);
end

-- Helper to get slotActions with normalized job ID key
-- JSON serialization converts numeric keys to strings, so we need to check both
local function getSlotActionsForJob(slotActions, jobId)
    if not slotActions then return nil; end
    -- Handle 'global' key specially
    if jobId == GLOBAL_SLOT_KEY then
        return slotActions[GLOBAL_SLOT_KEY];
    end
    local numericKey = normalizeJobId(jobId);
    local stringKey = tostring(numericKey);
    -- Check numeric key first (preferred), then string key (from JSON)
    return slotActions[numericKey] or slotActions[stringKey];
end

-- Helper to ensure slotActions structure exists for a job (or global)
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
    local numericKey = normalizeJobId(storageKey);
    if not barSettings.slotActions[numericKey] then
        -- Also check for string key and migrate if found
        local stringKey = tostring(numericKey);
        if barSettings.slotActions[stringKey] then
            -- Migrate string key to numeric key
            barSettings.slotActions[numericKey] = barSettings.slotActions[stringKey];
            barSettings.slotActions[stringKey] = nil;
        else
            barSettings.slotActions[numericKey] = {};
        end
    end
    return barSettings.slotActions[numericKey];
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
};

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
            backgroundTheme = 'Window1',
            showHotbarNumber = true,
            showSlotFrame = false,
            showActionLabels = false,
            actionLabelOffsetX = 0,
            actionLabelOffsetY = 0,
            slotXPadding = 8,
            slotYPadding = 6,
            slotBackgroundColor = 0x55000000,
            bgColor = 0xFFFFFFFF,
            borderColor = 0xFFFFFFFF,
            keybindFontSize = 8,
            keybindFontColor = 0xFFFFFFFF,
            labelFontSize = 10,
            showMpCost = true,
            mpCostFontSize = 8,
            mpCostFontColor = 0xFFD4FF97,
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
local function GetMacroById(macroId, jobId)
    if not gConfig or not gConfig.macroDB then return nil; end
    local jobMacros = gConfig.macroDB[jobId];
    if not jobMacros then return nil; end
    for _, macro in ipairs(jobMacros) do
        if macro.id == macroId then
            return macro;
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
        -- Use storage key based on jobSpecific setting (either 'global' or job ID)
        local storageKey = getStorageKey(barSettings, M.jobId);
        local jobSlotActions = getSlotActionsForJob(barSettings.slotActions, storageKey);
        if jobSlotActions then
            local slotAction = jobSlotActions[slotIndex];
            if slotAction then
                -- Check for "cleared" marker - slot was explicitly emptied
                if slotAction.cleared then
                    return nil;  -- Don't fall back to defaults
                end

                -- If this slot has a macro reference, look up the current macro data
                -- This ensures icon changes in the palette are reflected on the hotbar
                local macroData = slotAction;
                if slotAction.macroRef then
                    local liveMacro = GetMacroById(slotAction.macroRef, M.jobId);
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
local function getCrossbarStorageKey(crossbarSettings, jobId)
    if crossbarSettings.jobSpecific == false then
        return GLOBAL_SLOT_KEY;
    end
    return normalizeJobId(jobId);
end

-- Helper to get crossbar slotActions with normalized job ID key
local function getCrossbarSlotActionsForJob(slotActions, storageKey)
    if not slotActions then return nil; end
    -- Handle 'global' key specially
    if storageKey == GLOBAL_SLOT_KEY then
        return slotActions[GLOBAL_SLOT_KEY];
    end
    local numericKey = normalizeJobId(storageKey);
    local stringKey = tostring(numericKey);
    return slotActions[numericKey] or slotActions[stringKey];
end

-- Helper to ensure crossbar slotActions structure exists for a storage key and combo mode
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
    local numericKey = normalizeJobId(storageKey);
    if not crossbarSettings.slotActions[numericKey] then
        -- Also check for string key and migrate if found
        local stringKey = tostring(numericKey);
        if crossbarSettings.slotActions[stringKey] then
            crossbarSettings.slotActions[numericKey] = crossbarSettings.slotActions[stringKey];
            crossbarSettings.slotActions[stringKey] = nil;
        else
            crossbarSettings.slotActions[numericKey] = {};
        end
    end
    if not crossbarSettings.slotActions[numericKey][comboMode] then
        crossbarSettings.slotActions[numericKey][comboMode] = {};
    end
    return crossbarSettings.slotActions[numericKey][comboMode];
end

-- Get slot data for a crossbar slot
-- comboMode: 'L2', 'R2', 'L2R2', 'R2L2', 'L2x2', or 'R2x2'
-- slotIndex: 1-8
-- Returns nil if no data exists
function M.GetCrossbarSlotData(comboMode, slotIndex)
    local jobId = M.jobId or 1;

    if not gConfig.hotbarCrossbar then return nil; end
    -- Use storage key based on jobSpecific setting
    local storageKey = getCrossbarStorageKey(gConfig.hotbarCrossbar, jobId);
    local jobSlotActions = getCrossbarSlotActionsForJob(gConfig.hotbarCrossbar.slotActions, storageKey);
    if not jobSlotActions then return nil; end
    if not jobSlotActions[comboMode] then return nil; end

    local slotAction = jobSlotActions[comboMode][slotIndex];
    if not slotAction then return nil; end

    -- If this slot has a macro reference, look up the current macro data
    -- This ensures icon changes in the palette are reflected on the crossbar
    if slotAction.macroRef then
        local liveMacro = GetMacroById(slotAction.macroRef, jobId);
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
                macroRef = slotAction.macroRef,
            };
        end
        -- If macro was deleted, fall back to cached slotAction data
    end

    return slotAction;
end

-- Set slot data for a crossbar slot
-- comboMode: 'L2', 'R2', 'L2R2', 'R2L2', 'L2x2', or 'R2x2'
-- slotIndex: 1-8
-- slotData: { actionType, action, target, displayName, equipSlot, macroText, itemId, customIconType, customIconId }
--           or nil to clear the slot
function M.SetCrossbarSlotData(comboMode, slotIndex, slotData)
    local jobId = M.jobId or 1;

    -- If slotData is nil, clear the slot instead
    if not slotData then
        M.ClearCrossbarSlotData(comboMode, slotIndex);
        return;
    end

    -- Ensure config structure exists using helper (handles key normalization)
    if not gConfig.hotbarCrossbar then
        gConfig.hotbarCrossbar = {};
    end
    -- Use storage key based on jobSpecific setting
    local storageKey = getCrossbarStorageKey(gConfig.hotbarCrossbar, jobId);
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
        macroRef = slotData.macroRef or slotData.id,  -- Store reference to source macro for live updates
    };

    SaveSettingsToDisk();
end

-- Clear a crossbar slot (sets to nil)
-- comboMode: 'L2', 'R2', 'L2R2', 'R2L2', 'L2x2', or 'R2x2'
-- slotIndex: 1-8
function M.ClearCrossbarSlotData(comboMode, slotIndex)
    local jobId = M.jobId or 1;

    -- Early return if structure doesn't exist
    if not gConfig.hotbarCrossbar then return; end
    -- Use storage key based on jobSpecific setting
    local storageKey = getCrossbarStorageKey(gConfig.hotbarCrossbar, jobId);
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
-- Font Visibility Helpers
-- ============================================

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
    M.keybindFonts = {};
    M.labelFonts = {};
    M.timerFonts = {};
    M.mpCostFonts = {};
    M.hotbarNumberFonts = {};
    M.allFonts = nil;
end

return M;
