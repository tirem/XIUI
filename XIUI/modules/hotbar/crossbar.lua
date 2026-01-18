--[[
* XIUI Crossbar - Display Module
* Renders crossbar UI with controller-friendly layout
* Uses primitives for backgrounds, GDI fonts for text, ImGui for icons
]]--

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local ffi = require('ffi');
local primitives = require('primitives');
local windowBg = require('libs.windowbackground');
local drawing = require('libs.drawing');
local fonts = require('libs.fonts');
local FontManager = fonts.FontManager;
local dragdrop = require('libs.dragdrop');

local data = require('modules.hotbar.data');
local actions = require('modules.hotbar.actions');
local textures = require('modules.hotbar.textures');
local controller = require('modules.hotbar.controller');
local recast = require('modules.hotbar.recast');
local slotrenderer = require('modules.hotbar.slotrenderer');
local animation = require('libs.animation');
local skillchain = require('modules.hotbar.skillchain');
local targetLib = require('libs.target');

local M = {};

-- ============================================
-- Helper Functions for Job/Subjob Key Normalization
-- ============================================

-- Special key for global (non-job-specific) slot storage
local GLOBAL_SLOT_KEY = 'global';

-- Helper to get the storage key based on jobSpecific setting
-- Returns 'global' or '{jobId}:{subjobId}' format
local function getStorageKey(crossbarSettings, jobId, subjobId)
    if crossbarSettings.jobSpecific == false then
        return GLOBAL_SLOT_KEY;
    end
    return string.format('%d:%d', jobId or 1, subjobId or 0);
end

-- Helper to get slotActions with storage key
-- Handles: 'global' and composite keys ('15:10', '15:10:palette:Stuns')
-- Falls back to base job key (jobId:0) preserving any suffix if full job:subjob key doesn't exist
local function getSlotActionsForJob(slotActions, storageKey)
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

-- ============================================
-- Constants
-- ============================================

local SLOTS_PER_SIDE = 8;
local COMBO_MODES = controller.COMBO_MODES;

-- ============================================
-- Layout Calculation Functions
-- ============================================

-- Calculate group dimensions based on settings (uses separate H/V gaps)
-- slotGapV: vertical gap between top and bottom slots
-- slotGapH: horizontal gap affecting left/right slot positioning
local function CalculateGroupDimensions(slotSize, slotGapV, slotGapH, diamondSpacing)
    -- Diamond dimensions (cross/plus pattern):
    -- Width: left slot + horizontal gap + center column + horizontal gap + right slot
    local diamondWidth = slotSize + slotGapH + slotSize + slotGapH + slotSize;
    -- Height: top slot + vertical gap + bottom slot
    local diamondHeight = slotSize + slotGapV + slotSize;

    -- Group contains two diamonds side by side
    local groupWidth = diamondWidth + diamondSpacing + diamondWidth;
    local groupHeight = diamondHeight;

    return groupWidth, groupHeight, diamondWidth, diamondHeight;
end

-- Get slot position within a group
-- slotIndex: 1-8 (1-4 = dpad, 5-8 = face)
-- Returns x, y offset from group origin
--
-- Layout (cross/plus pattern):
--        [TOP]
--  [LEFT]     [RIGHT]
--        [BOT]
--
-- - Top and Bottom are stacked vertically (centered horizontally) with slotGapV between them
-- - Left and Right are on the sides, vertically centered with slotGapH from center
local function GetSlotOffset(slotIndex, slotSize, slotGapV, slotGapH, diamondSpacing)
    -- Diamond dimensions
    local diamondWidth = slotSize + slotGapH + slotSize + slotGapH + slotSize;
    local diamondHeight = slotSize + slotGapV + slotSize;

    -- Determine which diamond and position within it
    local isDpad = slotIndex <= 4;
    local posIndex = isDpad and slotIndex or (slotIndex - 4);

    -- Diamond origin (dpad at 0, face at diamondWidth + spacing)
    local diamondOriginX = isDpad and 0 or (diamondWidth + diamondSpacing);
    local diamondOriginY = 0;

    -- Slot offset within diamond (from top-left of diamond)
    local offsetX, offsetY;
    if posIndex == 1 then     -- Top (centered horizontally, at top)
        offsetX = slotSize + slotGapH;         -- Center column starts after left slot + gap
        offsetY = 0;                           -- Top of diamond
    elseif posIndex == 2 then -- Right (right side, vertically centered)
        offsetX = slotSize + slotGapH + slotSize + slotGapH;  -- After left + gap + center + gap
        offsetY = (diamondHeight - slotSize) / 2;              -- Vertically centered
    elseif posIndex == 3 then -- Bottom (centered horizontally, at bottom)
        offsetX = slotSize + slotGapH;         -- Center column
        offsetY = slotSize + slotGapV;         -- Below top slot + vertical gap
    else                      -- Left (left side, vertically centered)
        offsetX = 0;                           -- Left column
        offsetY = (diamondHeight - slotSize) / 2;  -- Vertically centered
    end

    -- Final position: diamond origin + slot offset
    local x = diamondOriginX + offsetX;
    local y = diamondOriginY + offsetY;

    return x, y;
end

-- Get diamond center position within a group
-- diamondType: 'dpad' or 'face'
-- Returns the center point where all 4 slots meet (for placing center icons)
local function GetDiamondCenter(diamondType, slotSize, slotGapV, slotGapH, diamondSpacing)
    -- Diamond dimensions
    local diamondWidth = slotSize + slotGapH + slotSize + slotGapH + slotSize;
    local diamondHeight = slotSize + slotGapV + slotSize;

    -- Center is in the middle of the diamond
    local centerX = diamondWidth / 2;
    local centerY = diamondHeight / 2;

    if diamondType == 'dpad' then
        return centerX, centerY;
    else -- 'face'
        return diamondWidth + diamondSpacing + centerX, centerY;
    end
end

-- Center icon textures configuration (icon names match textures module keys)
-- Supports PlayStation, Xbox, and Nintendo themes
local CENTER_ICON_CONFIG = {
    dpad = {
        { dir = 'up',    iconName = 'UP' },
        { dir = 'right', iconName = 'RIGHT' },
        { dir = 'down',  iconName = 'DOWN' },
        { dir = 'left',  iconName = 'LEFT' },
    },
    face = {
        PlayStation = {
            { dir = 'up',    iconName = 'Triangle' },
            { dir = 'right', iconName = 'Circle' },
            { dir = 'down',  iconName = 'X' },
            { dir = 'left',  iconName = 'Square' },
        },
        Xbox = {
            { dir = 'up',    iconName = 'Y' },
            { dir = 'right', iconName = 'B' },
            { dir = 'down',  iconName = 'A' },
            { dir = 'left',  iconName = 'Xbox_X' },
        },
        Nintendo = {
            { dir = 'up',    iconName = 'Xbox_X' },  -- X on top
            { dir = 'right', iconName = 'A' },       -- A on right
            { dir = 'down',  iconName = 'B' },       -- B on bottom
            { dir = 'left',  iconName = 'Y' },       -- Y on left
        },
    },
};

-- Get center icon offset from diamond center
-- iconIndex: 1=up, 2=right, 3=down, 4=left
-- gapH/gapV: horizontal and vertical spacing from center
local function GetCenterIconOffset(iconIndex, iconSize, gapH, gapV)
    local offsetH = (iconSize / 2) + (gapH or 0);
    local offsetV = (iconSize / 2) + (gapV or 0);
    if iconIndex == 1 then     -- Up
        return 0, -offsetV;
    elseif iconIndex == 2 then -- Right
        return offsetH, 0;
    elseif iconIndex == 3 then -- Down
        return 0, offsetV;
    else                       -- Left
        return -offsetH, 0;
    end
end

-- ============================================
-- State
-- ============================================

-- Icon cache per slot: iconCache[comboMode][slotIndex] = { bindKey = key, icon = cachedIcon }
local iconCache = {};

-- Build a cache key that includes all fields that affect the icon
local function BuildCrossbarBindKey(slotData)
    if not slotData then return 'nil'; end
    -- Include customIconType, customIconId, and customIconPath so icon changes invalidate the cache
    local iconPart = '';
    if slotData.customIconType or slotData.customIconId or slotData.customIconPath then
        iconPart = ':icon:' .. (slotData.customIconType or '') .. ':' .. tostring(slotData.customIconId or '') .. ':' .. (slotData.customIconPath or '');
    end
    return (slotData.actionType or '') .. ':' .. (slotData.action or '') .. ':' .. (slotData.target or '') .. iconPart;
end

-- Get cached icon for a crossbar slot, recompute only if bind changed
local function GetCachedCrossbarIcon(comboMode, slotIndex, slotData)
    if not iconCache[comboMode] then
        iconCache[comboMode] = {};
    end

    local cached = iconCache[comboMode][slotIndex];

    -- Check if we have a valid cache entry for this bind (including icon info)
    -- Also invalidate if cached icon doesn't have path (try to get primitive-enabled icon)
    local bindKey = BuildCrossbarBindKey(slotData);
    if cached and cached.bindKey == bindKey and cached.icon and cached.icon.path then
        return cached.icon;
    end

    -- Cache miss or icon needs path - compute icon
    local icon = nil;
    if slotData and slotData.actionType then
        icon = actions.GetBindIcon(slotData);
    end

    -- Store in cache
    iconCache[comboMode][slotIndex] = {
        bindKey = bindKey,
        icon = icon,
    };

    return icon;
end

-- Clear crossbar icon cache
local function ClearCrossbarIconCache()
    iconCache = {};
end

local state = {
    initialized = false,

    -- Window background
    bgHandle = nil,

    -- Slot primitives per combo mode
    -- slotPrims[comboMode][slotIndex] = primitive
    slotPrims = {},

    -- Icon primitives per combo mode (action icons)
    -- iconPrims[comboMode][slotIndex] = primitive
    iconPrims = {},

    -- Timer fonts per combo mode (cooldown timers)
    -- timerFonts[comboMode][slotIndex] = font
    timerFonts = {},

    -- MP cost fonts per combo mode
    -- mpCostFonts[comboMode][slotIndex] = font
    mpCostFonts = {},

    -- Item quantity fonts per combo mode
    -- quantityFonts[comboMode][slotIndex] = font
    quantityFonts = {},

    -- Center icon primitives per combo mode (in the middle of each diamond)
    -- centerIconPrims[comboMode][diamondType][iconIndex] = primitive
    -- diamondType: 'dpad' or 'face'
    -- iconIndex: 1-4 (the 4 icons in the center mini-diamond)
    centerIconPrims = {},

    -- GDI Fonts per combo mode (for action labels, not keybinds)
    labelFonts = {},

    -- Trigger label font (shows current combo mode)
    triggerLabelFont = nil,

    -- Combo text font (shows L2+R2, R2+L2, etc. in center)
    comboTextFont = nil,

    -- Window position (updated by ImGui window)
    windowX = 0,
    windowY = 0,

    -- Loaded theme
    loadedBgTheme = nil,

    -- Animation state for bar transitions
    animation = {
        active = false,
        startTime = 0,
        duration = 0.5,         -- Animation duration in seconds
        progress = 1.0,         -- 0 to 1 (eased)
        rawProgress = 1.0,      -- 0 to 1 (linear, for different easing per element)
        fromBarSet = 'base',    -- 'base' (L2/R2) or 'expanded' (L2R2/R2L2)
        toBarSet = 'base',
        fromLeftMode = 'L2',
        fromRightMode = 'R2',
        toLeftMode = 'L2',
        toRightMode = 'R2',
        slideDistance = 20,     -- Pixels to slide during transition
        leftChanged = false,    -- Did left side change?
        rightChanged = false,   -- Did right side change?
    },

    -- Current displayed bar set (for detecting transitions)
    currentBarSet = 'base',
    currentLeftMode = 'L2',
    currentRightMode = 'R2',
};

-- ============================================
-- Primitive Creation
-- ============================================

-- Base primitive data for creating new primitives
local basePrimData = {
    visible = false,
    can_focus = false,
    locked = true,
    width = 48,
    height = 48,
};

-- Create a primitive using the primitives module
local function CreatePrimitive(primData)
    local prim = primitives.new(primData or basePrimData);
    if prim then
        prim.visible = false;
        prim.can_focus = false;
    end
    return prim;
end

-- ============================================
-- Helper Functions
-- ============================================

-- Get the assets path
local function GetAssetsPath()
    return string.format('%saddons\\XIUI\\assets\\hotbar\\', AshitaCore:GetInstallPath());
end

-- Calculate crossbar window dimensions based on settings
local function GetCrossbarDimensions(settings)
    local slotSize = settings.slotSize or 48;
    local slotGapV = settings.slotGapV or 4;
    local slotGapH = settings.slotGapH or 4;
    local diamondSpacing = settings.diamondSpacing or 20;
    local groupSpacing = settings.groupSpacing or 40;

    -- Calculate group dimensions using layout functions
    local groupWidth, groupHeight = CalculateGroupDimensions(slotSize, slotGapV, slotGapH, diamondSpacing);

    -- Total width: L2 group + spacing + R2 group
    local width = (groupWidth * 2) + groupSpacing;
    local height = groupHeight;

    return width, height, groupWidth, groupHeight;
end

-- Get default window position (centered at bottom of screen)
local function GetDefaultPosition(settings)
    local screenWidth = imgui.GetIO().DisplaySize.x or 1920;
    local screenHeight = imgui.GetIO().DisplaySize.y or 1080;

    local width, height = GetCrossbarDimensions(settings);

    local x = (screenWidth - width) / 2;
    local y = screenHeight - height - 100;

    return x, y;
end

-- ============================================
-- Bar Set Determination
-- ============================================

-- Determine which combo modes to display on left/right based on active combo
-- Returns: leftMode, rightMode, isExpanded, expandedSide ('left', 'right', 'both', or nil)
local function GetDisplayModes(activeCombo)
    if activeCombo == COMBO_MODES.L2_THEN_R2 then
        -- Expanded: L2 first, then R2 -> show L2R2 on left side only, right side dimmed (shows R2)
        return 'L2R2', 'R2', true, 'left';
    elseif activeCombo == COMBO_MODES.R2_THEN_L2 then
        -- Expanded: R2 first, then L2 -> show R2L2 on right side only, left side dimmed (shows L2)
        return 'L2', 'R2L2', true, 'right';
    elseif activeCombo == COMBO_MODES.L2_DOUBLE then
        -- Double-tap L2: show L2x2 on left side only, right side dimmed (shows R2)
        return 'L2x2', 'R2', true, 'left';
    elseif activeCombo == COMBO_MODES.R2_DOUBLE then
        -- Double-tap R2: show R2x2 on right side only, left side dimmed (shows L2)
        return 'L2', 'R2x2', true, 'right';
    else
        -- Base mode (NONE, L2, R2): show L2 left, R2 right
        return 'L2', 'R2', false, nil;
    end
end

-- ============================================
-- Animation System
-- ============================================

-- Easing function (ease out cubic for smooth deceleration)
local function EaseOutCubic(t)
    return 1 - math.pow(1 - t, 3);
end

-- Easing function (ease in cubic for acceleration)
local function EaseInCubic(t)
    return t * t * t;
end

-- Easing function (ease out quad - slightly snappier)
local function EaseOutQuad(t)
    return 1 - (1 - t) * (1 - t);
end

-- Get current time in seconds
local function GetTime()
    return os.clock();
end

-- Start a bar transition animation
local function StartBarTransition(fromLeftMode, fromRightMode, toLeftMode, toRightMode)
    local fromExpanded = (fromLeftMode ~= 'L2' and fromLeftMode ~= 'R2');
    local toExpanded = (toLeftMode ~= 'L2' and toLeftMode ~= 'R2');

    state.animation.active = true;
    state.animation.startTime = GetTime();
    state.animation.progress = 0;
    state.animation.rawProgress = 0;
    state.animation.fromBarSet = fromExpanded and 'expanded' or 'base';
    state.animation.toBarSet = toExpanded and 'expanded' or 'base';
    state.animation.fromLeftMode = fromLeftMode;
    state.animation.fromRightMode = fromRightMode;
    state.animation.toLeftMode = toLeftMode;
    state.animation.toRightMode = toRightMode;
    -- Track which sides actually changed
    state.animation.leftChanged = (fromLeftMode ~= toLeftMode);
    state.animation.rightChanged = (fromRightMode ~= toRightMode);
end

-- Update animation progress
local function UpdateAnimation()
    if not state.animation.active then return; end

    local elapsed = GetTime() - state.animation.startTime;
    local rawProgress = math.min(elapsed / state.animation.duration, 1.0);

    if rawProgress >= 1.0 then
        -- Animation complete
        state.animation.active = false;
        state.animation.progress = 1.0;
        state.animation.rawProgress = 1.0;
        state.currentLeftMode = state.animation.toLeftMode;
        state.currentRightMode = state.animation.toRightMode;
        state.currentBarSet = state.animation.toBarSet;
    else
        state.animation.rawProgress = rawProgress;
        state.animation.progress = EaseOutCubic(rawProgress);
    end
end

-- Calculate animation values for outgoing (from) bar set
-- Returns: opacity (0-1), yOffset (pixels)
local function GetOutgoingAnimationValues()
    if not state.animation.active then
        return 0, 0;
    end

    local progress = state.animation.progress;
    local slideDistance = state.animation.slideDistance;

    -- Outgoing: fade out quickly, slide up
    local opacity = 1.0 - EaseOutQuad(math.min(progress * 1.5, 1.0));  -- Fade out faster
    local yOffset = -slideDistance * EaseOutCubic(progress);  -- Slide up (negative Y)

    return opacity, yOffset;
end

-- Calculate animation values for incoming (to) bar set
-- Returns: opacity (0-1), yOffset (pixels)
local function GetIncomingAnimationValues()
    if not state.animation.active then
        return 1.0, 0;
    end

    local progress = state.animation.progress;
    local slideDistance = state.animation.slideDistance;

    -- Incoming: start from below, slide up into place while fading in
    local opacity = EaseOutCubic(progress);
    local yOffset = slideDistance * (1.0 - EaseOutCubic(progress));  -- Start below, move to 0

    return opacity, yOffset;
end

-- Get slot position within the crossbar window
local function GetSlotPositionInWindow(side, slotIndex, windowX, windowY, settings)
    local slotSize = settings.slotSize or 48;
    local slotGapV = settings.slotGapV or 4;
    local slotGapH = settings.slotGapH or 4;
    local diamondSpacing = settings.diamondSpacing or 20;
    local groupSpacing = settings.groupSpacing or 40;

    -- Calculate group width for positioning
    local groupWidth = CalculateGroupDimensions(slotSize, slotGapV, slotGapH, diamondSpacing);

    -- Calculate group origin based on side
    local groupX = windowX;
    if side == 'R2' or side == 'R2L2' then
        -- R2 group is on the right
        groupX = windowX + groupWidth + groupSpacing;
    end
    -- L2 and L2R2 stay on the left (groupX = windowX)

    -- Get slot offset within the group
    local offsetX, offsetY = GetSlotOffset(slotIndex, slotSize, slotGapV, slotGapH, diamondSpacing);

    return groupX + offsetX, windowY + offsetY;
end

-- ============================================
-- Initialization
-- ============================================

function M.Initialize(settings, moduleSettings)
    if state.initialized then return; end

    -- Initial position - use saved position or default
    local savedPos = gConfig and gConfig.hotbarCrossbarPosition;
    local defaultX, defaultY = GetDefaultPosition(settings);
    state.windowX = savedPos and savedPos.x or defaultX;
    state.windowY = savedPos and savedPos.y or defaultY;

    local width, height, groupWidth, groupHeight = GetCrossbarDimensions(settings);

    -- Create window background
    local primData = moduleSettings and moduleSettings.prim_data or {};
    state.bgHandle = windowBg.create(primData, settings.backgroundTheme, settings.bgScale, settings.borderScale);

    -- Create primitives and fonts for each combo mode (including double-tap modes)
    local comboModes = { 'L2', 'R2', 'L2R2', 'R2L2', 'L2x2', 'R2x2' };

    for _, comboMode in ipairs(comboModes) do
        state.slotPrims[comboMode] = {};
        state.iconPrims[comboMode] = {};
        state.timerFonts[comboMode] = {};
        state.mpCostFonts[comboMode] = {};
        state.quantityFonts[comboMode] = {};
        state.centerIconPrims[comboMode] = {};
        state.labelFonts[comboMode] = {};

        -- Create slot background primitives, icon primitives, and fonts
        for slotIndex = 1, SLOTS_PER_SIDE do
            -- Slot background primitive
            local slotPrim = CreatePrimitive(basePrimData);
            state.slotPrims[comboMode][slotIndex] = slotPrim;

            -- Icon primitive (renders above slot background)
            local iconPrim = CreatePrimitive(basePrimData);
            state.iconPrims[comboMode][slotIndex] = iconPrim;

            -- Timer font for cooldowns (centered)
            local timerFontSettings = moduleSettings and deep_copy_table(moduleSettings.label_font_settings) or {};
            timerFontSettings.font_height = 11;
            timerFontSettings.font_alignment = 1;  -- Center
            timerFontSettings.font_color = 0xFFFFFFFF;
            timerFontSettings.outline_color = 0xFF000000;
            timerFontSettings.outline_width = 2;
            state.timerFonts[comboMode][slotIndex] = FontManager.create(timerFontSettings);

            -- MP cost font (right-aligned, for spell MP cost display)
            local mpCostFontSettings = moduleSettings and deep_copy_table(moduleSettings.label_font_settings) or {};
            mpCostFontSettings.font_height = settings.mpCostFontSize or 10;
            mpCostFontSettings.font_alignment = 2;  -- Right
            mpCostFontSettings.font_color = settings.mpCostFontColor or 0xFFD4FF97;
            mpCostFontSettings.outline_color = 0xFF000000;
            mpCostFontSettings.outline_width = 2;
            state.mpCostFonts[comboMode][slotIndex] = FontManager.create(mpCostFontSettings);

            -- Item quantity font (right-aligned, for item count display)
            local quantityFontSettings = moduleSettings and deep_copy_table(moduleSettings.label_font_settings) or {};
            quantityFontSettings.font_height = settings.quantityFontSize or 10;
            quantityFontSettings.font_alignment = 2;  -- Right
            quantityFontSettings.font_color = settings.quantityFontColor or 0xFFFFFFFF;
            quantityFontSettings.outline_color = 0xFF000000;
            quantityFontSettings.outline_width = 2;
            state.quantityFonts[comboMode][slotIndex] = FontManager.create(quantityFontSettings);

            -- Create label font for action names
            local labelFontSettings = moduleSettings and moduleSettings.label_font_settings or {};
            state.labelFonts[comboMode][slotIndex] = FontManager.create(labelFontSettings);
        end

        -- Create center icon primitives for each diamond (4 icons per diamond)
        state.centerIconPrims[comboMode]['dpad'] = {};
        state.centerIconPrims[comboMode]['face'] = {};

        for iconIdx = 1, 4 do
            -- D-pad center icons
            local dpadIconPrim = CreatePrimitive(basePrimData);
            state.centerIconPrims[comboMode]['dpad'][iconIdx] = dpadIconPrim;

            -- Face button center icons
            local faceIconPrim = CreatePrimitive(basePrimData);
            state.centerIconPrims[comboMode]['face'][iconIdx] = faceIconPrim;
        end
    end

    -- Create trigger label font
    local triggerFontSettings = moduleSettings and moduleSettings.trigger_font_settings or {};
    state.triggerLabelFont = FontManager.create(triggerFontSettings);

    -- Create combo text font (uses global font settings with center alignment)
    local comboTextFontSettings = moduleSettings and deep_copy_table(moduleSettings.trigger_font_settings) or {};
    comboTextFontSettings.font_height = settings.comboTextFontSize or 10;
    comboTextFontSettings.font_color = 0xFFFFFFFF;  -- White
    comboTextFontSettings.font_alignment = 1;  -- Center alignment
    state.comboTextFont = FontManager.create(comboTextFontSettings);

    -- Set loaded theme
    state.loadedBgTheme = settings.backgroundTheme;

    state.initialized = true;
end

-- ============================================
-- Rendering
-- ============================================

-- Draw a single slot with drag/drop support using shared renderer
-- animOpacity: 0-1 for animation fade (default 1.0)
-- yOffset: Y offset in pixels for animation (default 0)
-- skillchainName: (optional) Skillchain name for WS slots
local function DrawSlot(comboMode, slotIndex, x, y, slotSize, settings, isActive, isPressed, animOpacity, yOffset, skillchainName)
    animOpacity = animOpacity or 1.0;
    yOffset = yOffset or 0;

    -- Apply Y offset for animation
    local drawY = y + yOffset;

    -- Get press scale animation for icon (scales up when pressed, animates back down on release)
    local pressKey = comboMode .. '_' .. slotIndex;
    local iconPressScale = 1.0;
    if settings.enablePressScale ~= false then
        iconPressScale = animation.getPressScale(pressKey, isPressed and isActive);
    end

    -- Get slot data
    local slotData = data.GetCrossbarSlotData(comboMode, slotIndex);

    -- Get icon for this action (cached - only rebuilds when bind changes)
    local icon = GetCachedCrossbarIcon(comboMode, slotIndex, slotData);

    -- Calculate dim factor for inactive slots
    local dimFactor = 1.0;
    if not isActive then
        dimFactor = settings.inactiveSlotDim or 0.5;
    end

    -- Gather resources for this slot
    local resources = {
        slotPrim = state.slotPrims[comboMode] and state.slotPrims[comboMode][slotIndex],
        iconPrim = state.iconPrims[comboMode] and state.iconPrims[comboMode][slotIndex],
        timerFont = state.timerFonts[comboMode] and state.timerFonts[comboMode][slotIndex],
        mpCostFont = state.mpCostFonts[comboMode] and state.mpCostFonts[comboMode][slotIndex],
        quantityFont = state.quantityFonts[comboMode] and state.quantityFonts[comboMode][slotIndex],
        labelFont = state.labelFonts[comboMode] and state.labelFonts[comboMode][slotIndex],
    };

    -- Render slot using shared renderer (handles ALL rendering and interactions)
    slotrenderer.DrawSlot(resources, {
        -- Position/Size
        x = x,
        y = drawY,
        size = slotSize,

        -- Action Data
        bind = slotData,
        icon = icon,

        -- Visual Settings
        slotBgColor = settings.slotBackgroundColor or 0x55000000,
        dimFactor = dimFactor,
        animOpacity = animOpacity,
        isPressed = isPressed and isActive,
        iconPressScale = iconPressScale,
        showMpCost = settings.showMpCost ~= false,
        mpCostFontSize = settings.mpCostFontSize or 10,
        mpCostFontColor = settings.mpCostFontColor or 0xFFD4FF97,
        mpCostNoMpColor = settings.mpCostNoMpColor or 0xFFFF4444,
        mpCostOffsetX = settings.mpCostOffsetX or 0,
        mpCostOffsetY = settings.mpCostOffsetY or 0,
        showQuantity = settings.showQuantity ~= false,
        quantityFontSize = settings.quantityFontSize or 10,
        quantityFontColor = settings.quantityFontColor or 0xFFFFFFFF,
        quantityOffsetX = settings.quantityOffsetX or 0,
        quantityOffsetY = settings.quantityOffsetY or 0,
        showLabel = settings.showActionLabels or false,
        labelText = slotData and (slotData.displayName or slotData.action or '') or '',
        labelOffsetX = settings.actionLabelOffsetX or 0,
        labelOffsetY = (settings.actionLabelOffsetY or 0) + 2,
        labelFontSize = settings.labelFontSize or 10,
        labelFontColor = settings.labelFontColor or 0xFFFFFFFF,
        labelCooldownColor = settings.labelCooldownColor or 0xFF888888,
        labelNoMpColor = settings.labelNoMpColor or 0xFFFF4444,

        -- Interaction Config (use original Y for interaction, not animated Y)
        buttonId = string.format('##crossbar_%s_%d', comboMode, slotIndex),
        dropZoneId = string.format('crossbar_%s_%d', comboMode, slotIndex),
        dropAccepts = {'macro', 'crossbar_slot', 'slot'},
        onDrop = function(payload)
            if payload.type == 'macro' then
                data.SetCrossbarSlotData(comboMode, slotIndex, payload.data);
            elseif payload.type == 'crossbar_slot' then
                -- Swap crossbar slots
                local targetData = data.GetCrossbarSlotData(comboMode, slotIndex);
                data.SetCrossbarSlotData(comboMode, slotIndex, payload.data);
                data.SetCrossbarSlotData(payload.comboMode, payload.slotIndex, targetData);
            elseif payload.type == 'slot' then
                -- Copy from hotbar slot to crossbar (one-way copy, doesn't clear source)
                if payload.data then
                    data.SetCrossbarSlotData(comboMode, slotIndex, payload.data);
                end
            end
            -- Clear icon cache so slots update immediately
            M.ClearIconCache();
        end,
        dragType = 'crossbar_slot',
        getDragData = function()
            return {
                comboMode = comboMode,
                slotIndex = slotIndex,
                data = slotData,
                icon = icon,
                label = slotData and (slotData.displayName or slotData.action) or ('Slot ' .. slotIndex),
            };
        end,
        onRightClick = function()
            data.ClearCrossbarSlotData(comboMode, slotIndex);
            -- Clear icon cache so slot updates immediately
            M.ClearIconCache();
        end,
        showTooltip = true,

        -- Skillchain highlight
        skillchainName = skillchainName,
        skillchainColor = gConfig.hotbarGlobal.skillchainHighlightColor or 0xFFD4AA44,
    });
end

-- Note: HandleSlotInteraction removed - now handled by slotrenderer.DrawSlot

-- Draw center icons for a diamond via ImGui (renders on top of everything)
-- animOpacity: 0-1 for animation fade (default 1.0)
local function DrawDiamondCenterIconsImGui(diamondType, groupX, groupY, settings, isActive, drawList, animOpacity)
    animOpacity = animOpacity or 1.0;
    if animOpacity <= 0.01 then return; end

    local slotSize = settings.slotSize or 48;
    local slotGapV = settings.slotGapV or 4;
    local slotGapH = settings.slotGapH or 4;
    local diamondSpacing = settings.diamondSpacing or 20;
    local iconSize = settings.buttonIconSize or 24;
    local iconGapH = settings.buttonIconGapH or 2;
    local iconGapV = settings.buttonIconGapV or 2;
    local controllerTheme = settings.controllerTheme or 'Xbox';

    -- Get diamond center position using layout calculation
    local diamondCenterX, diamondCenterY = GetDiamondCenter(diamondType, slotSize, slotGapV, slotGapH, diamondSpacing);
    local centerX = groupX + diamondCenterX;
    local centerY = groupY + diamondCenterY;

    -- Get icon config for this diamond type
    -- D-pad is same for all themes, face buttons differ by theme
    local iconConfig;
    if diamondType == 'dpad' then
        iconConfig = CENTER_ICON_CONFIG.dpad;
    else
        iconConfig = CENTER_ICON_CONFIG.face[controllerTheme] or CENTER_ICON_CONFIG.face.Xbox;
    end
    if not iconConfig then return; end

    -- Draw each center icon via ImGui
    for iconIdx, iconData in ipairs(iconConfig) do
        -- Get icon offset from diamond center
        local offsetX, offsetY = GetCenterIconOffset(iconIdx, iconSize, iconGapH, iconGapV);
        local iconX = centerX + offsetX - (iconSize / 2);
        local iconY = centerY + offsetY - (iconSize / 2);

        -- Get texture from textures module (preloaded in Initialize)
        local texture = textures:GetControllerIcon(iconData.iconName);
        if texture and texture.image then
            local iconPtr = tonumber(ffi.cast("uint32_t", texture.image));
            if iconPtr then
                -- Apply tint color based on active state and animation opacity (opacity-based dimming)
                local dimFactor = isActive and 1.0 or (settings.inactiveSlotDim or 0.5);
                local alpha = math.floor(255 * animOpacity * dimFactor);
                local tintColor = bit.bor(bit.lshift(alpha, 24), 0x00FFFFFF);
                drawList:AddImage(
                    iconPtr,
                    {iconX, iconY},
                    {iconX + iconSize, iconY + iconSize},
                    {0, 0}, {1, 1},
                    tintColor
                );
            end
        end
    end
end

-- Legacy primitive-based drawing (kept for compatibility but not used)
local function DrawDiamondCenterIcons(comboMode, diamondType, groupX, groupY, settings, isActive)
    -- Hide primitives since we're using ImGui now
    local centerPrims = state.centerIconPrims[comboMode] and state.centerIconPrims[comboMode][diamondType];
    if centerPrims then
        for iconIdx = 1, 4 do
            if centerPrims[iconIdx] then
                centerPrims[iconIdx].visible = false;
            end
        end
    end
end

-- Draw trigger icons (L2, R2) above their respective groups via ImGui
local function DrawTriggerIcons(activeCombo, l2GroupX, r2GroupX, groupY, groupWidth, settings, drawList)
    if not settings.showTriggerLabels then return; end
    if not drawList then return; end

    -- Trigger icons base size is 49x28 pixels, scaled by triggerIconScale
    local baseScale = settings.triggerIconScale or 1.0;
    local baseIconWidth = 49 * baseScale;
    local baseIconHeight = 28 * baseScale;

    -- Determine active state for each trigger
    local l2Active = activeCombo == COMBO_MODES.L2 or activeCombo == COMBO_MODES.L2_THEN_R2 or activeCombo == COMBO_MODES.R2_THEN_L2 or activeCombo == COMBO_MODES.L2_DOUBLE;
    local r2Active = activeCombo == COMBO_MODES.R2 or activeCombo == COMBO_MODES.L2_THEN_R2 or activeCombo == COMBO_MODES.R2_THEN_L2 or activeCombo == COMBO_MODES.R2_DOUBLE;

    -- When no combo active, show both dimmed
    if activeCombo == COMBO_MODES.NONE then
        l2Active = false;
        r2Active = false;
    end

    -- Get press scale animations for triggers
    local l2PressScale = 1.0;
    local r2PressScale = 1.0;
    if settings.enablePressScale ~= false then
        l2PressScale = animation.getPressScale('trigger_L2', l2Active);
        r2PressScale = animation.getPressScale('trigger_R2', r2Active);
    end

    -- Draw L2 icon with press scale
    local l2Texture = textures:GetControllerIcon('L2');
    if l2Texture and l2Texture.image then
        local iconPtr = tonumber(ffi.cast("uint32_t", l2Texture.image));
        if iconPtr then
            local l2Width = baseIconWidth * l2PressScale;
            local l2Height = baseIconHeight * l2PressScale;
            local l2IconX = l2GroupX + (groupWidth / 2) - (l2Width / 2);
            local l2IconY = groupY - (l2Height * 0.5);
            local tintColor = l2Active and 0xFFFFFFFF or 0x88FFFFFF;
            drawList:AddImage(
                iconPtr,
                {l2IconX, l2IconY},
                {l2IconX + l2Width, l2IconY + l2Height},
                {0, 0}, {1, 1},
                tintColor
            );
        end
    end

    -- Draw R2 icon with press scale
    local r2Texture = textures:GetControllerIcon('R2');
    if r2Texture and r2Texture.image then
        local iconPtr = tonumber(ffi.cast("uint32_t", r2Texture.image));
        if iconPtr then
            local r2Width = baseIconWidth * r2PressScale;
            local r2Height = baseIconHeight * r2PressScale;
            local r2IconX = r2GroupX + (groupWidth / 2) - (r2Width / 2);
            local r2IconY = groupY - (r2Height * 0.5);
            local tintColor = r2Active and 0xFFFFFFFF or 0x88FFFFFF;
            drawList:AddImage(
                iconPtr,
                {r2IconX, r2IconY},
                {r2IconX + r2Width, r2IconY + r2Height},
                {0, 0}, {1, 1},
                tintColor
            );
        end
    end
end

-- Draw combo text in center for complex combos (L2R2, R2L2, L2x2, R2x2) or edit mode
local function DrawComboText(activeCombo, centerX, topY, settings)
    if not settings.showComboText and not settings.editMode then
        if state.comboTextFont then
            state.comboTextFont:set_visible(false);
        end
        return;
    end

    -- Determine combo text based on active combo
    local comboText = nil;
    if activeCombo == COMBO_MODES.L2_THEN_R2 then
        comboText = 'L2+R2';
    elseif activeCombo == COMBO_MODES.R2_THEN_L2 then
        comboText = 'R2+L2';
    elseif activeCombo == COMBO_MODES.L2_DOUBLE then
        comboText = 'L2x2';
    elseif activeCombo == COMBO_MODES.R2_DOUBLE then
        comboText = 'R2x2';
    elseif activeCombo == COMBO_MODES.L2 then
        comboText = 'L2';
    elseif activeCombo == COMBO_MODES.R2 then
        comboText = 'R2';
    end

    -- In edit mode, always show with warning indicator
    if settings.editMode then
        comboText = '(!) ' .. (comboText or 'EDIT');
    end

    -- Only show for complex combos (or edit mode)
    if not comboText then
        if state.comboTextFont then
            state.comboTextFont:set_visible(false);
        end
        return;
    end

    -- Get font size and offsets from settings
    local fontSize = settings.comboTextFontSize or 10;
    local offsetX = settings.comboTextOffsetX or 0;
    local offsetY = settings.comboTextOffsetY or 0;

    -- Update and show GDI font for text (centered)
    if state.comboTextFont then
        state.comboTextFont:set_font_height(fontSize);
        state.comboTextFont:set_text(comboText);
        state.comboTextFont:set_position_x(centerX + offsetX);
        state.comboTextFont:set_position_y(topY + offsetY);
        -- Yellow warning color in edit mode, white otherwise
        local fontColor = settings.editMode and 0xFFFFFF00 or 0xFFFFFFFF;
        state.comboTextFont:set_font_color(fontColor);
        state.comboTextFont:set_visible(true);
    end
end

-- Helper to draw just the left side
local function DrawLeftSide(mode, groupX, groupY, slotSize, settings, isActive, pressedSlot, showPressed, animOpacity, drawList, yOffset, targetServerId, skillchainEnabled)
    animOpacity = animOpacity or 1.0;
    yOffset = yOffset or 0;

    -- Draw left side slots
    for slotIndex = 1, SLOTS_PER_SIDE do
        local slotX, slotY = GetSlotPositionInWindow('L2', slotIndex, state.windowX, state.windowY, settings);
        local isPressed = showPressed and pressedSlot == slotIndex;
        -- Check for skillchain prediction on weapon skill slots
        local slotSkillchainName = nil;
        if skillchainEnabled then
            local slotData = data.GetCrossbarSlotData(mode, slotIndex);
            if slotData and slotData.actionType == 'ws' and slotData.action then
                slotSkillchainName = skillchain.GetSkillchainForSlot(targetServerId, slotData.action);
            end
        end
        DrawSlot(mode, slotIndex, slotX, slotY, slotSize, settings, isActive, isPressed, animOpacity, yOffset, slotSkillchainName);
    end

    -- Hide left center icon primitives (legacy)
    DrawDiamondCenterIcons(mode, 'dpad', groupX, groupY, settings, isActive);
    DrawDiamondCenterIcons(mode, 'face', groupX, groupY, settings, isActive);

    -- Draw center button icons via ImGui (if visible enough)
    if drawList and settings.showButtonIcons and animOpacity > 0.1 then
        local drawY = groupY + yOffset;
        DrawDiamondCenterIconsImGui('dpad', groupX, drawY, settings, isActive, drawList, animOpacity);
        DrawDiamondCenterIconsImGui('face', groupX, drawY, settings, isActive, drawList, animOpacity);
    end
end

-- Helper to draw just the right side
local function DrawRightSide(mode, groupX, groupY, slotSize, settings, isActive, pressedSlot, showPressed, animOpacity, drawList, yOffset, targetServerId, skillchainEnabled)
    animOpacity = animOpacity or 1.0;
    yOffset = yOffset or 0;

    -- Draw right side slots
    for slotIndex = 1, SLOTS_PER_SIDE do
        local slotX, slotY = GetSlotPositionInWindow('R2', slotIndex, state.windowX, state.windowY, settings);
        local isPressed = showPressed and pressedSlot == slotIndex;
        -- Check for skillchain prediction on weapon skill slots
        local slotSkillchainName = nil;
        if skillchainEnabled then
            local slotData = data.GetCrossbarSlotData(mode, slotIndex);
            if slotData and slotData.actionType == 'ws' and slotData.action then
                slotSkillchainName = skillchain.GetSkillchainForSlot(targetServerId, slotData.action);
            end
        end
        DrawSlot(mode, slotIndex, slotX, slotY, slotSize, settings, isActive, isPressed, animOpacity, yOffset, slotSkillchainName);
    end

    -- Hide right center icon primitives (legacy)
    DrawDiamondCenterIcons(mode, 'dpad', groupX, groupY, settings, isActive);
    DrawDiamondCenterIcons(mode, 'face', groupX, groupY, settings, isActive);

    -- Draw center button icons via ImGui (if visible enough)
    if drawList and settings.showButtonIcons and animOpacity > 0.1 then
        local drawY = groupY + yOffset;
        DrawDiamondCenterIconsImGui('dpad', groupX, drawY, settings, isActive, drawList, animOpacity);
        DrawDiamondCenterIconsImGui('face', groupX, drawY, settings, isActive, drawList, animOpacity);
    end
end

-- Helper to draw a complete bar set (both sides) - used for non-animated drawing
local function DrawBarSet(leftMode, rightMode, leftGroupX, leftGroupY, rightGroupX, rightGroupY,
                          slotSize, settings, leftActive, rightActive, pressedSlot,
                          leftShowPressed, rightShowPressed, animOpacity, drawList, yOffset, targetServerId, skillchainEnabled)
    DrawLeftSide(leftMode, leftGroupX, leftGroupY, slotSize, settings, leftActive, pressedSlot, leftShowPressed, animOpacity, drawList, yOffset, targetServerId, skillchainEnabled);
    DrawRightSide(rightMode, rightGroupX, rightGroupY, slotSize, settings, rightActive, pressedSlot, rightShowPressed, animOpacity, drawList, yOffset, targetServerId, skillchainEnabled);
end

-- Main draw function
function M.DrawWindow(settings, moduleSettings)
    if not state.initialized then return; end

    -- Update recast timers once per frame
    recast.Update();

    local slotSize = settings.slotSize or 48;
    local slotGapV = settings.slotGapV or 4;
    local slotGapH = settings.slotGapH or 4;
    local diamondSpacing = settings.diamondSpacing or 20;
    local groupSpacing = settings.groupSpacing or 40;

    -- Calculate dimensions using layout functions
    local width, height, groupWidth, groupHeight = GetCrossbarDimensions(settings);

    -- Window flags (dummy window for positioning, like hotbar display.lua)
    local windowFlags = GetBaseWindowFlags(gConfig.lockPositions);

    -- Get saved position or use default
    local savedPos = gConfig.hotbarCrossbarPosition;
    local defaultX, defaultY = GetDefaultPosition(settings);
    local posX = savedPos and savedPos.x or defaultX;
    local posY = savedPos and savedPos.y or defaultY;

    -- Check if anchor is currently being dragged - if so, force position from saved config
    local anchorDragging = drawing.IsAnchorDragging('crossbar');
    local posCondition = anchorDragging and ImGuiCond_Always or ImGuiCond_FirstUseEver;
    imgui.SetNextWindowPos({posX, posY}, posCondition);
    imgui.SetNextWindowSize({width, height}, ImGuiCond_Always);

    -- Get current combo mode and pressed slot from controller
    local activeCombo = controller.GetActiveCombo();
    local pressedSlot = controller.GetPressedSlot();

    -- Edit Mode: Override activeCombo to show selected bar for setup
    if settings.editMode then
        local editBar = settings.editModeBar or 'L2';
        activeCombo = editBar;
        pressedSlot = nil;  -- Don't show pressed state in edit mode
    end

    -- Determine which bar set to display based on active combo
    local targetLeftMode, targetRightMode, isExpanded, expandedSide = GetDisplayModes(activeCombo);

    -- Check if animations are disabled - if so, force complete any in-progress animation
    if settings.enableTransitionAnimations == false and state.animation.active then
        state.currentLeftMode = state.animation.toLeftMode;
        state.currentRightMode = state.animation.toRightMode;
        state.currentBarSet = state.animation.toBarSet;
        state.animation.active = false;
    end

    -- Check if bar set changed and start animation (or instant transition if disabled)
    if targetLeftMode ~= state.currentLeftMode or targetRightMode ~= state.currentRightMode then
        if settings.enableTransitionAnimations == false then
            -- Instant transition - skip animation
            state.currentLeftMode = targetLeftMode;
            state.currentRightMode = targetRightMode;
            local toExpanded = (targetLeftMode ~= 'L2' and targetLeftMode ~= 'R2');
            state.currentBarSet = toExpanded and 'expanded' or 'base';
            state.animation.active = false;
        elseif not state.animation.active then
            StartBarTransition(state.currentLeftMode, state.currentRightMode, targetLeftMode, targetRightMode);
        end
    end

    -- Update animation progress (only if animations enabled)
    if settings.enableTransitionAnimations ~= false then
        UpdateAnimation();
    end

    -- Window position will be updated by ImGui's built-in dragging
    local windowPosX, windowPosY = state.windowX, state.windowY;

    -- Calculate group positions (needed before window for proper sizing)
    local leftGroupX = state.windowX;
    local leftGroupY = state.windowY;
    local rightGroupX = state.windowX + groupWidth + groupSpacing;
    local rightGroupY = state.windowY;

    -- Determine active states based on combo mode and expanded side
    local leftActive, rightActive;
    if isExpanded then
        -- In expanded mode, only the expanded side is active, other side is dimmed
        if expandedSide == 'left' then
            leftActive = true;
            rightActive = false;
        elseif expandedSide == 'right' then
            leftActive = false;
            rightActive = true;
        else
            -- 'both' or unexpected - both active
            leftActive = true;
            rightActive = true;
        end
    else
        leftActive = activeCombo == COMBO_MODES.L2 or activeCombo == COMBO_MODES.NONE;
        rightActive = activeCombo == COMBO_MODES.R2 or activeCombo == COMBO_MODES.NONE;
        -- When no trigger held, show both sides equally
        if activeCombo == COMBO_MODES.NONE then
            leftActive = true;
            rightActive = true;
        end
    end

    -- Determine which side should show pressed state (for slot button press visual)
    local leftShowPressed = leftActive and activeCombo ~= COMBO_MODES.NONE;
    local rightShowPressed = rightActive and activeCombo ~= COMBO_MODES.NONE;

    -- Get draw list for ImGui-based rendering (foreground works outside window context)
    local drawList = imgui.GetForegroundDrawList();

    -- Get target server ID for skillchain prediction (cached for all slots)
    local targetServerId = nil;
    local skillchainEnabled = gConfig.hotbarGlobal.skillchainHighlightEnabled ~= false;
    if skillchainEnabled then
        local mainTargetIdx = targetLib.GetTargets();
        if mainTargetIdx and mainTargetIdx ~= 0 then
            local targetEntity = GetEntitySafe(mainTargetIdx);
            if targetEntity then
                targetServerId = targetEntity.ServerId;
            end
        end
    end

    -- Hide all slot and icon primitives first (we'll show the ones we need)
    local allModes = { 'L2', 'R2', 'L2R2', 'R2L2', 'L2x2', 'R2x2' };
    for _, mode in ipairs(allModes) do
        for slotIndex = 1, SLOTS_PER_SIDE do
            local slotPrim = state.slotPrims[mode] and state.slotPrims[mode][slotIndex];
            if slotPrim then slotPrim.visible = false; end
            local iconPrim = state.iconPrims[mode] and state.iconPrims[mode][slotIndex];
            if iconPrim then iconPrim.visible = false; end
        end
    end

    -- Begin ImGui window - ALL slot rendering happens inside to enable interactions
    if imgui.Begin('Crossbar', true, windowFlags) then
        windowPosX, windowPosY = imgui.GetWindowPos();

        -- Update stored position for primitives
        state.windowX = windowPosX;
        state.windowY = windowPosY;

        -- Recalculate group positions with updated window position
        leftGroupX = state.windowX;
        leftGroupY = state.windowY;
        rightGroupX = state.windowX + groupWidth + groupSpacing;
        rightGroupY = state.windowY;

        -- Draw bar sets based on animation state
        -- NOTE: DrawSlot calls must be inside imgui.Begin/End for interactions to work
        if state.animation.active then
            -- Get animation values for outgoing and incoming elements
            local outOpacity, outYOffset = GetOutgoingAnimationValues();
            local inOpacity, inYOffset = GetIncomingAnimationValues();

            -- Determine active states for "from" bar set
            local fromExpanded = state.animation.fromBarSet == 'expanded';
            local fromLeftActive = fromExpanded or state.animation.fromLeftMode == 'L2';
            local fromRightActive = fromExpanded or state.animation.fromRightMode == 'R2';

            -- Draw LEFT side
            if state.animation.leftChanged then
                -- Left side changed - animate it
                if outOpacity > 0.01 then
                    DrawLeftSide(state.animation.fromLeftMode, leftGroupX, leftGroupY, slotSize, settings,
                        fromLeftActive, pressedSlot, false, outOpacity, drawList, outYOffset, targetServerId, skillchainEnabled);
                end
                if inOpacity > 0.01 then
                    DrawLeftSide(state.animation.toLeftMode, leftGroupX, leftGroupY, slotSize, settings,
                        leftActive, pressedSlot, leftShowPressed, inOpacity, drawList, inYOffset, targetServerId, skillchainEnabled);
                end
            else
                -- Left side didn't change - draw at full opacity
                DrawLeftSide(state.animation.toLeftMode, leftGroupX, leftGroupY, slotSize, settings,
                    leftActive, pressedSlot, leftShowPressed, 1.0, drawList, 0, targetServerId, skillchainEnabled);
            end

            -- Draw RIGHT side
            if state.animation.rightChanged then
                -- Right side changed - animate it
                if outOpacity > 0.01 then
                    DrawRightSide(state.animation.fromRightMode, rightGroupX, rightGroupY, slotSize, settings,
                        fromRightActive, pressedSlot, false, outOpacity, drawList, outYOffset, targetServerId, skillchainEnabled);
                end
                if inOpacity > 0.01 then
                    DrawRightSide(state.animation.toRightMode, rightGroupX, rightGroupY, slotSize, settings,
                        rightActive, pressedSlot, rightShowPressed, inOpacity, drawList, inYOffset, targetServerId, skillchainEnabled);
                end
            else
                -- Right side didn't change - draw at full opacity
                DrawRightSide(state.animation.toRightMode, rightGroupX, rightGroupY, slotSize, settings,
                    rightActive, pressedSlot, rightShowPressed, 1.0, drawList, 0, targetServerId, skillchainEnabled);
            end
        else
            -- No animation, draw current bar set at full opacity with no offset
            DrawBarSet(
                state.currentLeftMode, state.currentRightMode,
                leftGroupX, leftGroupY, rightGroupX, rightGroupY,
                slotSize, settings,
                leftActive, rightActive,
                pressedSlot, leftShowPressed, rightShowPressed,
                1.0, drawList, 0, targetServerId, skillchainEnabled
            );
        end

        imgui.End();
    end

    -- Draw move anchor (only visible when config is open)
    local anchorNewX, anchorNewY = drawing.DrawMoveAnchor('crossbar', state.windowX, state.windowY);
    if anchorNewX ~= nil then
        state.windowX = anchorNewX;
        state.windowY = anchorNewY;
    end

    -- Save position if changed
    if gConfig.hotbarCrossbarPosition == nil then
        gConfig.hotbarCrossbarPosition = {};
    end
    if gConfig.hotbarCrossbarPosition.x ~= state.windowX or
       gConfig.hotbarCrossbarPosition.y ~= state.windowY then
        gConfig.hotbarCrossbarPosition.x = state.windowX;
        gConfig.hotbarCrossbarPosition.y = state.windowY;
    end

    -- Update window background (can happen after window closes)
    if state.bgHandle then
        windowBg.update(state.bgHandle, state.windowX, state.windowY, width, height, {
            theme = settings.backgroundTheme,
            bgScale = settings.bgScale,
            borderScale = settings.borderScale,
            bgOpacity = settings.backgroundOpacity,
            borderOpacity = settings.borderOpacity,
            bgColor = settings.bgColor,
            borderColor = settings.borderColor,
        });
    end

    -- Draw center divider (optional) - uses foreground draw list, works outside window
    if settings.showDivider and drawList then
        local dividerX = state.windowX + groupWidth + (groupSpacing / 2);
        local dividerY1 = state.windowY + 10;
        local dividerY2 = state.windowY + height - 10;

        drawList:AddLine(
            { dividerX, dividerY1 },
            { dividerX, dividerY2 },
            imgui.GetColorU32({ 1, 1, 1, 0.3 }),
            2
        );
    end

    -- Draw combo text in center for complex combos (positioned at top)
    local centerX = state.windowX + groupWidth + (groupSpacing / 2);
    local topY = state.windowY - 4;  -- Above the window
    DrawComboText(activeCombo, centerX, topY, settings);

    -- Draw L2/R2 trigger icons above the groups (controlled by showTriggerLabels)
    if drawList then
        DrawTriggerIcons(activeCombo, leftGroupX, rightGroupX, leftGroupY, groupWidth, settings, drawList);
    end

    -- Draw palette modifier indicator (refresh icon when modifier key is held)
    if state.windowX and actions.IsPaletteModifierHeld() then
        local refreshTexture = textures:Get('ui_refresh');
        if refreshTexture and refreshTexture.image then
            local iconSize = 18;
            -- Position centered above the crossbar
            local iconX = centerX - (iconSize / 2);
            local iconY = state.windowY - 24;
            local fgDrawList = imgui.GetForegroundDrawList();

            -- Draw with a pulsing effect for visibility
            local pulseAlpha = 0.7 + 0.3 * math.sin(os.clock() * 6);
            local iconColor = imgui.GetColorU32({1.0, 1.0, 1.0, pulseAlpha});
            local iconPtr = tonumber(ffi.cast("uint32_t", refreshTexture.image));

            if iconPtr then
                fgDrawList:AddImage(
                    iconPtr,
                    {iconX, iconY},
                    {iconX + iconSize, iconY + iconSize},
                    {0, 0}, {1, 1},
                    iconColor
                );
            end
        end
    end
end

-- ============================================
-- Visibility
-- ============================================

function M.SetHidden(hidden)
    -- Hide window background
    if state.bgHandle then
        if hidden then
            windowBg.hide(state.bgHandle);
        end
        -- Note: Don't show bgHandle here - DrawWindow handles showing it after positioning
    end

    -- Only HIDE primitives when hidden=true
    -- DrawWindow is responsible for showing them at the correct positions
    -- Setting visible=true here would show them at (0,0) before they're positioned
    if hidden then
        local comboModes = { 'L2', 'R2', 'L2R2', 'R2L2', 'L2x2', 'R2x2' };
        for _, comboMode in ipairs(comboModes) do
            for slotIndex = 1, SLOTS_PER_SIDE do
                local slotPrim = state.slotPrims[comboMode] and state.slotPrims[comboMode][slotIndex];
                if slotPrim then slotPrim.visible = false; end

                local iconPrim = state.iconPrims[comboMode] and state.iconPrims[comboMode][slotIndex];
                if iconPrim then iconPrim.visible = false; end

                local timerFont = state.timerFonts[comboMode] and state.timerFonts[comboMode][slotIndex];
                if timerFont then timerFont:set_visible(false); end

                local mpCostFont = state.mpCostFonts[comboMode] and state.mpCostFonts[comboMode][slotIndex];
                if mpCostFont then mpCostFont:set_visible(false); end

                local quantityFont = state.quantityFonts[comboMode] and state.quantityFonts[comboMode][slotIndex];
                if quantityFont then quantityFont:set_visible(false); end

                local labelFont = state.labelFonts[comboMode] and state.labelFonts[comboMode][slotIndex];
                if labelFont then labelFont:set_visible(false); end
            end

            -- Hide center icon primitives
            for _, diamondType in ipairs({'dpad', 'face'}) do
                local centerPrims = state.centerIconPrims[comboMode] and state.centerIconPrims[comboMode][diamondType];
                if centerPrims then
                    for iconIdx = 1, 4 do
                        if centerPrims[iconIdx] then
                            centerPrims[iconIdx].visible = false;
                        end
                    end
                end
            end
        end

        -- Hide trigger label
        if state.triggerLabelFont then
            state.triggerLabelFont:set_visible(false);
        end

        -- Hide combo text
        if state.comboTextFont then
            state.comboTextFont:set_visible(false);
        end
    end
    -- When hidden=false, don't do anything - DrawWindow will handle visibility
end

-- ============================================
-- Visual Updates
-- ============================================

function M.UpdateVisuals(settings, moduleSettings)
    if not state.initialized then return; end

    -- Update theme if changed
    if settings.backgroundTheme ~= state.loadedBgTheme then
        if state.bgHandle then
            windowBg.setTheme(state.bgHandle, settings.backgroundTheme, settings.bgScale, settings.borderScale);
        end
        state.loadedBgTheme = settings.backgroundTheme;
    end

    -- Recreate fonts if settings changed
    local comboModes = { 'L2', 'R2', 'L2R2', 'R2L2', 'L2x2', 'R2x2' };
    for _, comboMode in ipairs(comboModes) do
        for slotIndex = 1, SLOTS_PER_SIDE do
            -- Recreate label font
            local labelFont = state.labelFonts[comboMode] and state.labelFonts[comboMode][slotIndex];
            local labelSettings = moduleSettings and moduleSettings.label_font_settings or {};
            if labelFont then
                state.labelFonts[comboMode][slotIndex] = FontManager.recreate(labelFont, labelSettings);
            end
        end
    end

    -- Recreate trigger label font
    if state.triggerLabelFont then
        local triggerSettings = moduleSettings and moduleSettings.trigger_font_settings or {};
        state.triggerLabelFont = FontManager.recreate(state.triggerLabelFont, triggerSettings);
    end

    -- Recreate combo text font
    if state.comboTextFont then
        local comboTextSettings = moduleSettings and deep_copy_table(moduleSettings.trigger_font_settings) or {};
        comboTextSettings.font_height = settings.comboTextFontSize or 10;
        comboTextSettings.font_color = 0xFFFFFFFF;  -- White
        comboTextSettings.font_alignment = 1;  -- Center alignment
        state.comboTextFont = FontManager.recreate(state.comboTextFont, comboTextSettings);
    end

    -- Clear slot cache since fonts were recreated (cache tracks font text state)
    slotrenderer.ClearAllCache();
end

-- ============================================
-- Cleanup
-- ============================================

function M.Cleanup()
    if not state.initialized then return; end

    -- Destroy window background
    if state.bgHandle then
        windowBg.destroy(state.bgHandle);
        state.bgHandle = nil;
    end

    -- Destroy all primitives and fonts
    local comboModes = { 'L2', 'R2', 'L2R2', 'R2L2', 'L2x2', 'R2x2' };
    for _, comboMode in ipairs(comboModes) do
        -- Destroy slot primitives, icon primitives, and fonts
        for slotIndex = 1, SLOTS_PER_SIDE do
            local slotPrim = state.slotPrims[comboMode] and state.slotPrims[comboMode][slotIndex];
            if slotPrim then slotPrim:destroy(); end

            local iconPrim = state.iconPrims[comboMode] and state.iconPrims[comboMode][slotIndex];
            if iconPrim then iconPrim:destroy(); end

            local timerFont = state.timerFonts[comboMode] and state.timerFonts[comboMode][slotIndex];
            if timerFont then FontManager.destroy(timerFont); end

            local mpCostFont = state.mpCostFonts[comboMode] and state.mpCostFonts[comboMode][slotIndex];
            if mpCostFont then FontManager.destroy(mpCostFont); end

            local quantityFont = state.quantityFonts[comboMode] and state.quantityFonts[comboMode][slotIndex];
            if quantityFont then FontManager.destroy(quantityFont); end

            local labelFont = state.labelFonts[comboMode] and state.labelFonts[comboMode][slotIndex];
            if labelFont then FontManager.destroy(labelFont); end
        end

        -- Destroy center icon primitives
        for _, diamondType in ipairs({'dpad', 'face'}) do
            local centerPrims = state.centerIconPrims[comboMode] and state.centerIconPrims[comboMode][diamondType];
            if centerPrims then
                for iconIdx = 1, 4 do
                    if centerPrims[iconIdx] then
                        centerPrims[iconIdx]:destroy();
                    end
                end
            end
        end

        state.slotPrims[comboMode] = nil;
        state.iconPrims[comboMode] = nil;
        state.timerFonts[comboMode] = nil;
        state.mpCostFonts[comboMode] = nil;
        state.quantityFonts[comboMode] = nil;
        state.centerIconPrims[comboMode] = nil;
        state.labelFonts[comboMode] = nil;
    end

    -- Destroy trigger label font
    if state.triggerLabelFont then
        FontManager.destroy(state.triggerLabelFont);
        state.triggerLabelFont = nil;
    end

    -- Destroy combo text font
    if state.comboTextFont then
        FontManager.destroy(state.comboTextFont);
        state.comboTextFont = nil;
    end

    -- Clear icon cache
    ClearCrossbarIconCache();

    -- Clear slotrenderer cache
    slotrenderer.ClearAllCache();

    state.initialized = false;
end

-- ============================================
-- Position Management
-- ============================================

function M.SetPosition(x, y)
    state.windowX = x;
    state.windowY = y;
end

function M.GetPosition()
    return state.windowX, state.windowY;
end

-- ============================================
-- Slot Activation
-- ============================================

-- Activate a slot (execute bound action)
function M.ActivateSlot(comboMode, slotIndex)
    if not state.initialized then return; end

    -- Note: Native macro blocking for controller is handled by zeroing trigger values
    -- in state_modified in controller.lua, so no StopNativeMacros call needed here

    -- Get slot action using data module (handles per-combo storage keys, palettes, pet-aware)
    local slotAction = data.GetCrossbarSlotData(comboMode, slotIndex);
    if not slotAction then return; end

    -- Execute the action via the actions module
    if slotAction.actionType and slotAction.action then
        actions.ExecuteAction(slotAction);
    end
end

-- ============================================
-- Cache Management
-- ============================================

-- Clear icon cache (call when job changes)
function M.ClearIconCache()
    ClearCrossbarIconCache();
end

-- Reset crossbar position to default (called when settings are reset)
function M.ResetPositions()
    if not state.initialized then return; end
    local settings = gConfig and gConfig.hotbarCrossbar or {};
    local defaultX, defaultY = GetDefaultPosition(settings);
    state.windowX = defaultX;
    state.windowY = defaultY;
end

return M;
