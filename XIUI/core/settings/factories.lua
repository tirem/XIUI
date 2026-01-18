--[[
* XIUI Settings Factory Functions
* Reusable factory functions for creating default settings with overrides
]]--

local M = {};

-- Virtual key codes for number row keys
-- https://learn.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes
local VK_KEYS = {
    ['1'] = 0x31,  -- 49
    ['2'] = 0x32,  -- 50
    ['3'] = 0x33,  -- 51
    ['4'] = 0x34,  -- 52
    ['5'] = 0x35,  -- 53
    ['6'] = 0x36,  -- 54
    ['7'] = 0x37,  -- 55
    ['8'] = 0x38,  -- 56
    ['9'] = 0x39,  -- 57
    ['0'] = 0x30,  -- 48
    ['-'] = 0xBD,  -- 189 (OEM_MINUS)
    ['='] = 0xBB,  -- 187 (OEM_PLUS)
};

-- Helper to create default number row keybindings (1-9, 0) with optional modifiers
-- @param ctrl boolean - require Ctrl modifier
-- @param alt boolean - require Alt modifier
-- @param shift boolean - require Shift modifier
-- @param keyCount number - number of keys to bind (default 10: keys 1-9, 0)
-- @return table - keyBindings table for up to 12 slots
function M.createNumberRowKeybindings(ctrl, alt, shift, keyCount)
    local allKeys = {'1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '='};
    keyCount = keyCount or 10;  -- Default to 10 keys (1-9, 0), no - or =
    local bindings = {};
    for i = 1, math.min(keyCount, #allKeys) do
        local keyName = allKeys[i];
        bindings[i] = {
            key = VK_KEYS[keyName],
            ctrl = ctrl or false,
            alt = alt or false,
            shift = shift or false,
        };
    end
    return bindings;
end

-- Factory function to create party settings with overrides
-- Reduces duplication since partyA/B/C are 95% identical
function M.createPartyDefaults(overrides)
    local defaults = T{
        -- Layout mode (0 = Horizontal, 1 = Compact Vertical)
        layout = 0,
        -- Display options
        showDistance = false,
        distanceHighlight = 0,
        -- HP/MP display modes ('number', 'percent', 'both', 'both_percent_first', 'current_max')
        hpDisplayMode = 'number',
        mpDisplayMode = 'number',
        -- Job display options
        showJobIcon = true,
        jobIconScale = 1,
        showJob = false,
        showMainJob = true,
        showMainJobLevel = true,
        showSubJob = true,
        showSubJobLevel = true,
        showCastBars = true,
        castBarStyle = 'name', -- 'name' = replace name, 'mp' = use MP bar, 'tp' = use TP bar
        alwaysShowMpBar = true, -- Show MP bar even for jobs without MP
        castBarScaleX = 1.0,
        castBarScaleY = 0.6,
        castBarOffsetX = 0,
        castBarOffsetY = 0,
        showBookends = false,
        showTitle = true,
        flashTP = false,
        showTP = true,
        -- Appearance
        backgroundName = 'Window1',
        bgScale = 1.0,
        borderScale = 1.0,
        backgroundOpacity = 1.0,
        borderOpacity = 1.0,
        cursor = 'GreyArrow.png',
        statusTheme = 0, -- 0: HorizonXI, 1: HorizonXI-R, 2: FFXIV, 3: FFXI, 4: Disabled
        statusSide = 0, -- 0: Left, 1: Right
        buffScale = 1.0,
        -- Positioning
        expandHeight = false,
        expandHeightInAlliance = false,
        alignBottom = false,
        minRows = 1,
        entrySpacing = 0,
        showSelectionBox = true,
        selectionBoxScaleY = 1,
        selectionBoxOffsetY = 0,
        -- Scale
        scaleX = 1,
        scaleY = 1,
        -- Font sizes
        fontSize = 12,
        splitFontSizes = false,
        nameFontSize = 12,
        hpFontSize = 12,
        mpFontSize = 12,
        tpFontSize = 12,
        distanceFontSize = 12,
        jobFontSize = 12,
        zoneFontSize = 10,
        -- Bar scales (for all layouts)
        hpBarScaleX = 1,
        mpBarScaleX = 1,
        tpBarScaleX = 1,
        hpBarScaleY = 1,
        mpBarScaleY = 1,
        tpBarScaleY = 1,
        -- Text position offsets (per-party overrides)
        nameTextOffsetX = 0,
        nameTextOffsetY = 0,
        hpTextOffsetX = 0,
        hpTextOffsetY = 0,
        mpTextOffsetX = 0,
        mpTextOffsetY = 0,
        tpTextOffsetX = 0,
        tpTextOffsetY = 0,
        distanceTextOffsetX = 0,
        distanceTextOffsetY = 0,
        jobTextOffsetX = 0,
        jobTextOffsetY = 0,
    };
    if overrides then
        for k, v in pairs(overrides) do
            defaults[k] = v;
        end
    end
    return defaults;
end

-- Factory function to create per-pet-type settings with overrides
-- Each pet type (Avatar, Charm, Jug, Automaton, Wyvern) can have independent visual settings
function M.createPetBarTypeDefaults(overrides)
    local defaults = T{
        -- Display toggles
        showLevel = false,
        showDistance = true,
        showHP = true,
        showMP = true,
        showTP = true,
        showTimers = true,
        -- Positioning
        alignBottom = false,
        -- Scale settings
        scaleX = 1.0,
        scaleY = 1.0,
        hpScaleX = 1.0,
        hpScaleY = 1.0,
        mpScaleX = 1.0,
        mpScaleY = 1.0,
        tpScaleX = 1.0,
        tpScaleY = 1.0,
        recastScaleX = 1.0,
        recastScaleY = 0.8,
        -- Font sizes
        nameFontSize = 12,
        distanceFontSize = 10,
        hpFontSize = 10,
        mpFontSize = 10,
        tpFontSize = 10,
        -- Background settings
        backgroundTheme = 'Window1',
        backgroundOpacity = 1.0,
        borderOpacity = 1.0,
        showBookends = false,
        -- Recast icon positioning (absolute for compact mode, anchored for full mode)
        iconsAbsolute = false,
        iconsScale = 0.6,
        iconsOffsetX = 0,
        iconsOffsetY = 0,
        -- Recast icon fill style: 'square', 'circle', or 'clock'
        timerFillStyle = 'square',
        -- Recast display style: 'compact' or 'full'
        recastDisplayStyle = 'full',
        -- Full display style settings
        recastFullShowName = true,
        recastFullShowTimer = true,
        recastFullNameFontSize = 10,
        recastFullTimerFontSize = 10,
        recastFullAlignment = 'left',
        recastFullSpacing = 4,
        -- Spacing between vitals and recast section (anchored mode only)
        recastTopSpacing = 2,
        -- Distance text positioning
        distanceOffsetX = 0,
        distanceOffsetY = 0,
    };
    if overrides then
        for k, v in pairs(overrides) do
            defaults[k] = v;
        end
    end
    return defaults;
end

-- Factory function to create per-pet-type color settings
function M.createPetBarTypeColorDefaults()
    return T{
        -- Bar gradients
        hpGradient = T{ enabled = true, start = '#e26c6c', stop = '#fa9c9c' },
        mpGradient = T{ enabled = true, start = '#9abb5a', stop = '#bfe07d' },
        tpGradient = T{ enabled = true, start = '#3898ce', stop = '#78c4ee' },
        -- Text colors
        nameTextColor = 0xFFFFFFFF,
        distanceTextColor = 0xFFFFFFFF,
        hpTextColor = 0xFFFFA7A7,
        mpTextColor = 0xFFD4FF97,
        tpTextColor = 0xFF8DC7FF,
        targetTextColor = 0xFFFFFFFF,
        -- SMN ability gradients
        timerBPRageReadyGradient = T{ enabled = true, start = '#ff3333e6', stop = '#ff6666e6' },
        timerBPRageRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerBPWardReadyGradient = T{ enabled = true, start = '#00cccce6', stop = '#66dddde6' },
        timerBPWardRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerApogeeReadyGradient = T{ enabled = true, start = '#ffcc00e6', stop = '#ffdd66e6' },
        timerApogeeRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerManaCedeReadyGradient = T{ enabled = true, start = '#009999e6', stop = '#66bbbbe6' },
        timerManaCedeRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        -- BST ability gradients
        timerReadyReadyGradient = T{ enabled = true, start = '#ff6600e6', stop = '#ff9933e6' },
        timerReadyRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerRewardReadyGradient = T{ enabled = true, start = '#00cc66e6', stop = '#66dd99e6' },
        timerRewardRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerCallBeastReadyGradient = T{ enabled = true, start = '#3399ffe6', stop = '#66bbffe6' },
        timerCallBeastRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerBestialLoyaltyReadyGradient = T{ enabled = true, start = '#9966ffe6', stop = '#bb99ffe6' },
        timerBestialLoyaltyRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        -- DRG ability gradients
        timerCallWyvernReadyGradient = T{ enabled = true, start = '#3366ffe6', stop = '#6699ffe6' },
        timerCallWyvernRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerSpiritLinkReadyGradient = T{ enabled = true, start = '#33cc33e6', stop = '#66dd66e6' },
        timerSpiritLinkRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerDeepBreathingReadyGradient = T{ enabled = true, start = '#ffff33e6', stop = '#ffff99e6' },
        timerDeepBreathingRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerSteadyWingReadyGradient = T{ enabled = true, start = '#cc66ffe6', stop = '#dd99ffe6' },
        timerSteadyWingRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        -- PUP ability gradients
        timerActivateReadyGradient = T{ enabled = true, start = '#3399ffe6', stop = '#66bbffe6' },
        timerActivateRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerRepairReadyGradient = T{ enabled = true, start = '#33cc66e6', stop = '#66dd99e6' },
        timerRepairRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerDeployReadyGradient = T{ enabled = true, start = '#ff9933e6', stop = '#ffbb66e6' },
        timerDeployRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerDeactivateReadyGradient = T{ enabled = true, start = '#999999e6', stop = '#bbbbbbe6' },
        timerDeactivateRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerRetrieveReadyGradient = T{ enabled = true, start = '#66ccffe6', stop = '#99ddffe6' },
        timerRetrieveRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerDeusExAutomataReadyGradient = T{ enabled = true, start = '#ffcc33e6', stop = '#ffdd66e6' },
        timerDeusExAutomataRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        -- 2-Hour timer gradients
        timer2hReadyGradient = T{ enabled = true, start = '#ff00ffe6', stop = '#ff66ffe6' },
        timer2hRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        -- BST specific
        durationWarningColor = 0xFFFF6600,
        charmHeartColor = 0xFFFF6699,
        jugIconColor = 0xFFFFFFFF,
        charmTimerColor = 0xFFFFFFFF,
        -- Background
        bgColor = 0xFFFFFFFF,
        borderColor = 0xFFFFFFFF,
    };
end

-- Factory function to create global hotbar settings (shared across all bars when useGlobalSettings is true)
function M.createHotbarGlobalDefaults()
    return T{
        -- Game UI patches
        disableMacroBars = false,  -- Disable native XI macros (macro bar display + controller macro blocking)

        -- Blocked game keys - array of key definitions that should be blocked from reaching the game
        -- Each entry: { key = virtualKeyCode, ctrl = bool, alt = bool, shift = bool }
        -- Example: { key = 189, ctrl = false, alt = false, shift = false } blocks '-' key
        blockedGameKeys = {},

        -- Palette cycling keybinds (keyboard)
        -- Set key to 0 to disable
        paletteCycleEnabled = true,       -- Enable keyboard palette cycling
        paletteCyclePrevKey = 38,         -- VK_UP (Up Arrow)
        paletteCycleNextKey = 40,         -- VK_DOWN (Down Arrow)
        paletteCycleModifier = 'ctrl',    -- 'ctrl', 'alt', 'shift', or 'none'

        -- Palette cycling controller (RB + Dpad)
        paletteCycleControllerEnabled = true,  -- Enable controller palette cycling
        hotbarPaletteCycleButton = 'R1',       -- 'R1' or 'L1' for hotbar cycling

        -- Visual settings
        slotSize = 48,          -- Slot size in pixels
        bgScale = 1.0,
        borderScale = 1.0,
        backgroundOpacity = 0.87,
        borderOpacity = 1.0,
        backgroundTheme = '-None-',
        showHotbarNumber = true,
        showSlotFrame = false,
        customFramePath = '',   -- Custom frame image path (empty = use default)
        showActionLabels = false,
        actionLabelOffsetX = 0,
        actionLabelOffsetY = 0,
        hideEmptySlots = false, -- Hide slots with no action assigned

        -- Slot padding (gap between slots)
        slotXPadding = 8,
        slotYPadding = 6,

        -- Slot appearance
        slotBackgroundColor = 0x55000000,

        -- Window colors
        bgColor = 0xFFFFFFFF,
        borderColor = 0xFFFFFFFF,

        -- Font settings
        keybindFontSize = 8,
        keybindFontColor = 0xFFFFFFFF,
        labelFontSize = 10,
        labelFontColor = 0xFFFFFFFF,
        labelCooldownColor = 0xFF888888,
        labelNoMpColor = 0xFFFF4444,
        
        -- Text position settings
        showKeybinds = true,
        keybindAnchor = 'topLeft',      -- topLeft, topRight, bottomLeft, bottomRight
        keybindOffsetX = 0,
        keybindOffsetY = 0,
        showMpCost = true,
        mpCostAnchor = 'topRight',
        mpCostOffsetX = 0,
        mpCostOffsetY = 0,
        showQuantity = true,
        quantityAnchor = 'bottomRight',
        quantityOffsetX = 0,
        quantityOffsetY = 0,
        hotbarNumberOffsetX = 0,
        hotbarNumberOffsetY = 0,

        -- Skillchain highlight settings
        skillchainHighlightEnabled = true,      -- Show skillchain highlight on WS slots
        skillchainHighlightColor = 0xFFD4AA44,  -- Gold color for highlight border (ARGB)
    };
end

-- Factory function to create per-hotbar settings with overrides
-- Each hotbar (1-6) can have independent layout and visual settings
function M.createHotbarBarDefaults(overrides)
    local defaults = T{
        -- Global settings toggle (when true, uses hotbarGlobal settings for visuals)
        useGlobalSettings = true,

        -- Job-specific toggle (when true, actions are stored per-job; when false, actions are shared across all jobs)
        jobSpecific = true,

        -- Pet-aware toggle (when true, hotbar can have different palettes per pet for SMN/BST/DRG/PUP)
        petAware = false,
        showPetIndicator = true,  -- Show indicator dot when petAware is enabled

        -- Layout settings (always per-bar)
        enabled = true,
        rows = 1,               -- Number of rows (1-12)
        columns = 12,           -- Number of columns (1-12)
        slots = 12,             -- Total slots, auto-calculated from rows*columns

        -- Visual settings (used when useGlobalSettings = false)
        slotSize = 48,          -- Slot size in pixels
        bgScale = 1.0,
        borderScale = 1.0,
        backgroundOpacity = 0.87,
        borderOpacity = 1.0,
        backgroundTheme = '-None-',
        showHotbarNumber = true,
        showSlotFrame = false,
        customFramePath = '',       -- Custom frame image path (empty = use default)
        showActionLabels = false,
        actionLabelOffsetX = 0,     -- X offset for action labels
        actionLabelOffsetY = 0,     -- Y offset for action labels
        hideEmptySlots = false,     -- Hide slots with no action assigned

        -- Slot padding (gap between slots)
        slotXPadding = 8,       -- Horizontal gap between slots
        slotYPadding = 6,       -- Vertical gap between rows

        -- Slot appearance
        slotBackgroundColor = 0x55000000,  -- ARGB color for slot backgrounds (black at 33% opacity)

        -- Window colors (per-bar)
        bgColor = 0xFFFFFFFF,              -- Background color tint (ARGB)
        borderColor = 0xFFFFFFFF,          -- Border color tint (ARGB)

        -- Font settings
        keybindFontSize = 8,
        keybindFontColor = 0xFFFFFFFF,     -- Keybind text color (ARGB)
        labelFontSize = 10,
        labelFontColor = 0xFFFFFFFF,       -- Action label text color (ARGB)
        labelCooldownColor = 0xFF888888,   -- Action label color when on cooldown (grey)
        labelNoMpColor = 0xFFFF4444,       -- Action label color when not enough MP (red)
        
        -- Text position settings
        showKeybinds = true,
        keybindAnchor = 'topLeft',         -- topLeft, topRight, bottomLeft, bottomRight
        keybindOffsetX = 0,
        keybindOffsetY = 0,
        showMpCost = true,
        mpCostAnchor = 'topRight',
        mpCostOffsetX = 0,
        mpCostOffsetY = 0,
        showQuantity = true,
        quantityAnchor = 'bottomRight',
        quantityOffsetX = 0,
        quantityOffsetY = 0,
        hotbarNumberOffsetX = 0,
        hotbarNumberOffsetY = 0,

        -- Keybind assignments per job (nil = use job file defaults)
        -- Structure: keybinds[jobId][slotIndex] = { type, action, target, display }
        keybinds = nil,

        -- Keyboard shortcut bindings per slot (not job-specific)
        -- Structure: keyBindings[slotIndex] = { key = virtualKeyCode, ctrl = bool, alt = bool, shift = bool }
        keyBindings = {},

        -- Palette ordering for user-defined palettes (per job:subjob combination)
        -- Structure: paletteOrder['{jobId}:{subjobId}'] = { 'paletteName1', 'paletteName2', ... }
        -- Palettes are displayed in this order; missing palettes are appended alphabetically
        paletteOrder = {},
    };
    if overrides then
        for k, v in pairs(overrides) do
            defaults[k] = v;
        end
        -- Auto-calculate slots if rows/columns changed but slots wasn't explicitly set
        if (overrides.rows or overrides.columns) and not overrides.slots then
            defaults.slots = defaults.rows * defaults.columns;
        end
    end
    return defaults;
end

-- Factory function to create crossbar settings (controller-based hotbar layout)
-- The crossbar provides 4 combo modes: L2, R2, L2+R2, R2+L2 (32 total slots)
function M.createCrossbarDefaults()
    return T{
        -- Layout mode: 'hotbar', 'crossbar', or 'both'
        mode = 'hotbar',

        -- Job-specific toggle (when true, actions are stored per-job; when false, actions are shared across all jobs)
        jobSpecific = true,

        -- Per-combo-mode settings (pet-aware is per-combo, palettes are GLOBAL)
        -- NOTE: activePalette was removed - crossbar palettes are now global (see palette.lua state.crossbarActivePalette)
        comboModeSettings = {
            L2 = { petAware = false },
            R2 = { petAware = false },
            L2R2 = { petAware = false },
            R2L2 = { petAware = false },
            L2x2 = { petAware = false },
            R2x2 = { petAware = false },
        },

        -- Palette cycling button for crossbar (R1 + DPad while trigger held)
        crossbarPaletteCycleButton = 'R1',  -- 'R1' or 'L1'

        -- Layout
        slotSize = 40,              -- Slot size in pixels
        slotGapV = 2,               -- Vertical gap between top and bottom slots
        slotGapH = 2,               -- Horizontal gap between left and right slots
        diamondSpacing = 16,        -- Space between dpad and face button diamonds
        groupSpacing = 24,          -- Space between L2 and R2 groups
        showDivider = true,         -- Show center divider line
        showTriggerLabels = true,   -- Show L2/R2 trigger icons

        -- Visual settings
        backgroundTheme = '-None-',
        bgScale = 1.0,
        borderScale = 1.0,
        backgroundOpacity = 0.10,
        borderOpacity = 1.0,
        slotBackgroundColor = 0x55000000,
        activeSlotHighlight = 0x44FFFFFF,   -- Highlight color when trigger held
        inactiveSlotDim = 0.5,              -- Dim multiplier for inactive side

        -- Window colors
        bgColor = 0xFFFFFFFF,
        borderColor = 0xFFFFFFFF,

        -- Button icons
        showButtonIcons = true,             -- Show d-pad/face button icons on slots
        buttonIconSize = 16,                -- Size of controller button icons
        buttonIconGapH = 8,                 -- Horizontal spacing between center icons
        buttonIconGapV = 2,                 -- Vertical spacing between center icons
        buttonIconPosition = 'corner',      -- 'corner' or 'replace_keybind'
        controllerTheme = 'Xbox',           -- 'PlayStation', 'Xbox', or 'Nintendo' button icons
        controllerScheme = 'xbox',          -- Controller profile: 'xbox', 'dualsense', 'switchpro', 'dinput'
        triggerIconScale = 0.8,             -- Scale for L2/R2 trigger icons (base 49x28)

        -- Font settings
        keybindFontSize = 8,
        keybindFontColor = 0xFFFFFFFF,
        labelFontSize = 10,
        triggerLabelFontSize = 14,
        triggerLabelColor = 0xFFFFCC00,     -- Gold color for trigger labels

        -- MP cost display
        showMpCost = true,                  -- Show MP cost on spell slots
        mpCostFontSize = 10,                -- Font size for MP cost
        mpCostFontColor = 0xFFD4FF97,       -- MP cost text color
        mpCostNoMpColor = 0xFFFF4444,       -- MP cost color when not enough MP
        mpCostOffsetX = 0,                  -- X offset for MP cost position
        mpCostOffsetY = 0,                  -- Y offset for MP cost position

        -- Item quantity display
        showQuantity = true,                -- Show item quantity on item slots
        quantityFontSize = 10,              -- Font size for item quantity
        quantityFontColor = 0xFFFFFFFF,     -- Item quantity text color
        quantityOffsetX = 0,                -- X offset for quantity position
        quantityOffsetY = 0,                -- Y offset for quantity position

        -- Combo text (shows current mode in center for complex combos)
        showComboText = true,               -- Show combo mode text in center
        comboTextFontSize = 10,             -- Font size for combo text
        comboTextOffsetX = 0,               -- X offset for combo text position
        comboTextOffsetY = 0,               -- Y offset for combo text position

        -- Expanded crossbar (L2+R2 combos)
        enableExpandedCrossbar = true,      -- Enable L2+R2 and R2+L2 combos

        -- Double-tap crossbar (tap trigger twice quickly)
        enableDoubleTap = false,            -- Enable L2x2 and R2x2 double-tap modes
        doubleTapWindow = 0.3,              -- Time window for double-tap detection (seconds)

        -- Window position (saved on drag)
        windowX = nil,                      -- nil = use default centered position
        windowY = nil,

        -- Per-job slot actions for each combo mode
        -- slotActions[jobId][comboMode][slotIndex] = action
        -- comboMode: 'L2', 'R2', 'L2R2', 'R2L2'
        -- slotIndex: 1-8 (1-4 = d-pad, 5-8 = face buttons)
        slotActions = {},

        -- Crossbar palette order (separate from hotbar palettes)
        -- Structure: crossbarPaletteOrder['{jobId}:{subjobId}'] = { 'paletteName1', 'paletteName2', ... }
        -- Note: Crossbar palettes are independent from hotbar palettes
        crossbarPaletteOrder = {},
    };
end

-- Factory function to create party color settings
function M.createPartyColorDefaults(includeTP)
    local colors = T{
        hpGradient = T{
            low = T{ enabled = true, start = '#ec3232', stop = '#f16161' },
            medLow = T{ enabled = true, start = '#ee9c06', stop = '#ecb44e' },
            medHigh = T{ enabled = true, start = '#ffff0c', stop = '#ffff97' },
            high = T{ enabled = true, start = '#e26c6c', stop = '#fa9c9c' },
        },
        mpGradient = T{ enabled = true, start = '#9abb5a', stop = '#bfe07d' },
        barBackgroundOverride = T{ active = false, enabled = true, start = '#01122b', stop = '#061c39' },
        barBorderOverride = T{ active = false, color = '#01122b' },
        nameTextColor = 0xFFFFFFFF,
        hpTextColor = 0xFFFFA7A7,
        mpTextColor = 0xFFD4FF97,
        tpEmptyTextColor = 0xFF8DC7FF,
        tpFullTextColor = 0xFF8DC7FF,
        tpFlashColor = 0xFF3ECE00,
        bgColor = 0xFFFFFFFF,
        borderColor = 0xFFFFFFFF,
        selectionGradient = T{ enabled = true, start = '#4da5d9', stop = '#78c0ed' },
        selectionBorderColor = 0xFF78C0ED,
        subtargetGradient = T{ enabled = true, start = '#d9a54d', stop = '#edcf78' },
        subtargetBorderColor = 0xFFfdd017,
        castBarGradient = T{ enabled = true, start = '#ffaa00', stop = '#ffcc44' },
        castTextColor = 0xFFFFCC44,
    };
    if includeTP then
        colors.tpGradient = T{ enabled = true, start = '#3898ce', stop = '#78c4ee' };
    end
    return colors;
end

-- Factory function to create notification group settings with overrides
-- Each notification group (1-6) can have independent visual settings
function M.createNotificationGroupDefaults(overrides)
    local defaults = T{
        -- Scale
        scaleX = 1.0,
        scaleY = 1.0,
        -- Progress bar
        progressBarScaleY = 1.0,
        progressBarDirection = 'left', -- 'left' or 'right'
        -- Layout
        padding = 8,
        spacing = 8,
        maxVisible = 5,
        direction = 'down', -- 'down' or 'up'
        -- Font sizes
        titleFontSize = 14,
        subtitleFontSize = 12,
        -- Background/Border
        backgroundTheme = 'Plain',
        bgScale = 1.0,
        borderScale = 1.0,
        bgOpacity = 0.87,
        borderOpacity = 1.0,
        -- Timing
        displayDuration = 3.0,
        inviteMinifyTimeout = 10.0,
    };
    if overrides then
        for k, v in pairs(overrides) do
            defaults[k] = v;
        end
    end
    return defaults;
end

return M;
