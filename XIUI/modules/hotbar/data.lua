--[[
* XIUI hotbar - Data Module
* Handles state, keybinds, font storage, and primitive handles
]]--

require('common');
local jobs = require('libs.jobs');

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

-- Fonts for hotbar numbers (1-6)
M.hotbarNumberFonts = {};

-- All fonts for batch operations
M.allFonts = nil;

-- ============================================
-- Keybinds State (preserved from original)
-- ============================================

-- Keybinds cache (job -> keybind entries)
M.allKeybinds = {};
M.currentKeybinds = nil;  -- Cached parsed keybinds for current job/subjob
M.jobId = nil;
M.subjobId = nil;

-- ============================================
-- Helper Functions
-- ============================================

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

-- Get keybind display string for a slot
function M.GetKeybindDisplay(barIndex, slotIndex)
    local keybindKey = tostring(slotIndex);
    if slotIndex == 11 then
        keybindKey = '-';
    elseif slotIndex == 12 then
        keybindKey = '+';
    end

    if barIndex == 1 then
        return keybindKey;           -- 1-12
    elseif barIndex == 2 then
        return 'C' .. keybindKey;    -- Ctrl+1-12
    elseif barIndex == 3 then
        return 'A' .. keybindKey;    -- Alt+1-12
    elseif barIndex == 4 then
        return 'S' .. keybindKey;    -- Shift+1-12
    elseif barIndex == 5 then
        return 'CS' .. keybindKey;   -- Ctrl+Shift+1-12
    elseif barIndex == 6 then
        return 'CA' .. keybindKey;   -- Ctrl+Alt+1-12
    end
    return keybindKey;
end

-- Parse a keybind entry from array format to object format
function M.ParseKeybindEntry(entry)
    if type(entry) ~= 'table' or #entry < 2 then
        return nil;
    end

    -- Parse the first element: 'battle 1 1' -> context, hotbar, slot
    local battleStr = entry[1];
    local context, hotbar, slot = battleStr:match('(%w+)%s+(%d+)%s+(%d+)');

    local parsed = {
        context = context or 'battle',
        hotbar = tonumber(hotbar) or 1,
        slot = tonumber(slot) or 1,
        actionType = entry[2],           -- 'ma', 'ja', 'ws', 'macro', etc.
        action = entry[3],                -- Spell/ability/ws name
        target = entry[4],                -- 'stpc', 'stnpc', 'me', 't', etc.
        displayName = entry[5] or entry[3],  -- Display name (defaults to action if not provided)
        extraType = entry[6],             -- Optional: 'item', texture name, etc.
        raw = entry                       -- Keep original array for reference
    };

    return parsed;
end

-- Get current keybinds
function M.GetCurrentKeybinds()
    -- Return cached keybinds if available
    if M.currentKeybinds then
        return M.currentKeybinds;
    end

    local rawKeybinds = M.GetBaseKeybindsForJob(M.jobId);
    if not rawKeybinds then
        return nil;
    end

    -- Get subjob keybinds if available
    local subjobKeybinds = M.GetSubjobKeybindsForJob(M.jobId, M.subjobId);

    -- Combine base and subjob keybinds
    local combinedKeybinds = {};
    for i, entry in ipairs(rawKeybinds) do
        table.insert(combinedKeybinds, entry);
    end

    if subjobKeybinds then
        for i, entry in ipairs(subjobKeybinds) do
            table.insert(combinedKeybinds, entry);
        end
    end

    -- Parse raw array entries into object format
    local parsedKeybinds = {};
    for i, entry in ipairs(combinedKeybinds) do
        local parsed = M.ParseKeybindEntry(entry);
        if parsed then
            table.insert(parsedKeybinds, parsed);
        else
            print(string.format("[XIUI hotbar] Failed to parse entry %d (has %d elements)", i, #entry));
        end
    end

    -- Cache the parsed keybinds
    M.currentKeybinds = parsedKeybinds;

    return parsedKeybinds;
end

-- Get action assignment for a specific bar and slot
function M.GetKeybindForSlot(barIndex, slotIndex)
    -- First check for custom slot actions in per-bar settings
    local configKey = 'hotbarBar' .. barIndex;
    if gConfig and gConfig[configKey] then
        local barSettings = gConfig[configKey];
        if barSettings.slotActions and barSettings.slotActions[M.jobId] then
            local slotAction = barSettings.slotActions[M.jobId][slotIndex];
            if slotAction then
                -- Check for "cleared" marker - slot was explicitly emptied
                if slotAction.cleared then
                    return nil;  -- Don't fall back to defaults
                end
                -- Return slot action in the same format as parsed keybinds
                return {
                    context = 'battle',
                    hotbar = barIndex,
                    slot = slotIndex,
                    actionType = slotAction.actionType,
                    action = slotAction.action,
                    target = slotAction.target,
                    displayName = slotAction.displayName or slotAction.action,
                    equipSlot = slotAction.equipSlot,
                    macroText = slotAction.macroText,
                    itemId = slotAction.itemId,
                    customIconType = slotAction.customIconType,
                    customIconId = slotAction.customIconId,
                };
            end
        end
    end

    -- Fall back to job keybinds from lua files
    local keybinds = M.GetCurrentKeybinds();
    if not keybinds then
        return nil;
    end

    for _, bind in ipairs(keybinds) do
        if bind.hotbar == barIndex and bind.slot == slotIndex then
            return bind;
        end
    end
    return nil;
end

-- Get keybinds for a specific job
function M.GetBaseKeybindsForJob(jobId)
    if not jobId then
        return nil;
    end

    local jobKeybinds = M.allKeybinds[jobId];
    if not jobKeybinds then
        return nil;
    end

    if not jobKeybinds['Base'] then
        return nil;
    end

    return jobKeybinds['Base'];
end

-- Get subjob-specific keybinds for a job
function M.GetSubjobKeybindsForJob(jobId, subjobId)
    if not jobId or not subjobId or subjobId == 0 then
        return nil;
    end

    local jobKeybinds = M.allKeybinds[jobId];
    if not jobKeybinds then
        return nil;
    end

    local subjobName = jobs[subjobId];
    if not subjobName then
        return nil;
    end

    local subjobKeybinds = jobKeybinds[subjobName];

    return subjobKeybinds;
end

-- Get all cached keybinds
function M.GetAllKeybinds()
    return M.allKeybinds;
end

-- Check if keybinds are loaded
function M.HasKeybinds()
    return M.allKeybinds and next(M.allKeybinds) ~= nil;
end

-- ============================================
-- Crossbar Slot Data Helpers
-- ============================================

-- Get slot data for a crossbar slot
-- comboMode: 'L2', 'R2', 'L2R2', 'R2L2', 'L2x2', or 'R2x2'
-- slotIndex: 1-8
-- Returns nil if no data exists
function M.GetCrossbarSlotData(comboMode, slotIndex)
    local jobId = M.jobId or 1;

    if not gConfig.hotbarCrossbar then return nil; end
    if not gConfig.hotbarCrossbar.slotActions then return nil; end
    if not gConfig.hotbarCrossbar.slotActions[jobId] then return nil; end
    if not gConfig.hotbarCrossbar.slotActions[jobId][comboMode] then return nil; end

    return gConfig.hotbarCrossbar.slotActions[jobId][comboMode][slotIndex];
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

    -- Ensure config structure exists
    if not gConfig.hotbarCrossbar then
        gConfig.hotbarCrossbar = {};
    end
    if not gConfig.hotbarCrossbar.slotActions then
        gConfig.hotbarCrossbar.slotActions = {};
    end
    if not gConfig.hotbarCrossbar.slotActions[jobId] then
        gConfig.hotbarCrossbar.slotActions[jobId] = {};
    end
    if not gConfig.hotbarCrossbar.slotActions[jobId][comboMode] then
        gConfig.hotbarCrossbar.slotActions[jobId][comboMode] = {};
    end

    -- Store the slot data
    gConfig.hotbarCrossbar.slotActions[jobId][comboMode][slotIndex] = {
        actionType = slotData.actionType,
        action = slotData.action,
        target = slotData.target,
        displayName = slotData.displayName,
        equipSlot = slotData.equipSlot,
        macroText = slotData.macroText,
        itemId = slotData.itemId,
        customIconType = slotData.customIconType,
        customIconId = slotData.customIconId,
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
    if not gConfig.hotbarCrossbar.slotActions then return; end
    if not gConfig.hotbarCrossbar.slotActions[jobId] then return; end
    if not gConfig.hotbarCrossbar.slotActions[jobId][comboMode] then return; end

    -- Clear the slot
    gConfig.hotbarCrossbar.slotActions[jobId][comboMode][slotIndex] = nil;

    SaveSettingsToDisk();
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

-- Initialize keybinds (called from init.lua)
function M.InitializeKeybinds()
    -- Clear any existing cache
    M.allKeybinds = {};
    M.currentKeybinds = nil;

    -- Only load keybind lua files if explicitly enabled
    -- By default, hotbar slots are empty until user configures them via macro palette
    if gConfig and gConfig.hotbarLoadDefaultKeybinds then
        -- Get the addon path
        local addonPath = AshitaCore:GetInstallPath();

        -- Loop over all jobs and load their keybinds
        for jobId, jobName in ipairs(jobs) do
            local jobNameLower = jobName:lower();
            local keybindsPath = string.format('%saddons\\XIUI\\modules\\hotbar\\keybinds\\%s.lua', addonPath, jobNameLower);

            -- Load the keybinds file for this job
            local success, result = pcall(function()
                local chunk, err = loadfile(keybindsPath);
                if chunk then
                    local keybinds = chunk();
                    if keybinds and next(keybinds) ~= nil then
                        M.allKeybinds[jobId] = keybinds;
                    end
                end
            end);
        end
    end

    M.SetPlayerJob();
end

-- Legacy Initialize (for backwards compatibility)
function M.Initialize()
    M.InitializeKeybinds();
end

function M.SetPlayerJob()
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    local currentJobId = player:GetMainJob();
    if(currentJobId == 0) then
       return;
    end
    local currentSubjobId = player:GetSubJob();

    -- Clear cached keybinds if job changed
    if M.jobId ~= currentJobId or M.subjobId ~= currentSubjobId then
        M.currentKeybinds = nil;
    end

    M.jobId = currentJobId;
    M.subjobId = currentSubjobId;
end

-- Clear all state (call on zone change)
function M.Clear()
    -- Note: We keep keybindsCache intact on zone change
    -- as keybinds don't need to be reloaded
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
    M.hotbarNumberFonts = {};
    M.allFonts = nil;
end

return M;
