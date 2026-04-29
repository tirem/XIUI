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
local macropalette = require('modules.hotbar.macropalette');
local playerdata = require('modules.hotbar.playerdata');
local actions = require('modules.hotbar.actions');
local textures = require('modules.hotbar.textures');
local controller = require('modules.hotbar.controller');
local recast = require('modules.hotbar.recast');
local slotrenderer = require('modules.hotbar.slotrenderer');
local animation = require('libs.animation');
local skillchain = require('modules.hotbar.skillchain');
local macroparse = require('modules.hotbar.macroparse');
local targetLib = require('libs.target');
local palette = require('modules.hotbar.palette');
local TextureManager = require('libs.texturemanager');

local function GetCrossbarSkillchainVisualsFromGlobal()
    local hg = gConfig.hotbarGlobal or {};
    return {
        enabled = hg.skillchainHighlightEnabled ~= false,
        color = hg.skillchainHighlightColor or 0xFFD4AA44,
        iconScale = hg.skillchainIconScale or 1.0,
        iconOffsetX = hg.skillchainIconOffsetX or 0,
        iconOffsetY = hg.skillchainIconOffsetY or 0,
    };
end

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

-- (Slot lookup uses data.lua's unified getSlotActionsForKey helper)

-- ============================================
-- Constants
-- ============================================

local SLOTS_PER_SIDE = 8;
local COMBO_MODES = controller.COMBO_MODES;
local ALL_COMBO_MODES = { 'L2', 'R2', 'L2R2', 'R2L2', 'L2x2', 'R2x2', 'Shared' };
local PAL_ED_PREFIX = 'PalEd_';

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
            { dir = 'left',  iconName = 'X' },
        },
        Nintendo = {
            { dir = 'up',    iconName = 'X' },  -- X on top
            { dir = 'right', iconName = 'A' },       -- A on right
            { dir = 'down',  iconName = 'B' },       -- B on bottom
            { dir = 'left',  iconName = 'Y' },       -- Y on left
        },
        Stadia = {
            { dir = 'up',    iconName = 'Y' },
            { dir = 'right', iconName = 'B' },
            { dir = 'down',  iconName = 'A' },
            { dir = 'left',  iconName = 'X' },
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

-- Icon cache per slot: iconCache[namespace][comboMode][slotIndex] = { bindKey = key, icon = cachedIcon }
local iconCache = {};

local function IconCacheNs()
    local sk = data.GetCrossbarPaletteEditSessionKey and data.GetCrossbarPaletteEditSessionKey();
    if sk then
        return 'pal_' .. tostring(sk);
    end
    -- HUD stays on live bindings during Edit Full Palette until Apply; draft edits affect palette row cache only.
    return '__live__';
end

-- Build a cache key that includes all fields that affect the icon
local function BuildCrossbarBindKey(slotData)
    if not slotData then return 'nil'; end
    -- Include customIconType, customIconId, and customIconPath so icon changes invalidate the cache
    local iconPart = '';
    if slotData.customIconType or slotData.customIconId or slotData.customIconPath then
        iconPart = ':icon:' .. (slotData.customIconType or '') .. ':' .. tostring(slotData.customIconId or '') .. ':' .. (slotData.customIconPath or '');
    end
    if slotData.actionType == 'macro' then
        iconPart = iconPart .. (actions.GetMacroJaBadgeIconCacheSuffix(slotData) or '');
    end
    return (slotData.actionType or '') .. ':' .. (slotData.action or '') .. ':' .. (slotData.target or '') .. iconPart;
end

-- Get cached icon for a crossbar slot, recompute only if bind changed
local function GetCachedCrossbarIcon(comboMode, slotIndex, slotData)
    -- Use effective combo mode for cache key (Shared when shared expanded bar is enabled)
    comboMode = data.GetEffectiveComboModeForStorage and data.GetEffectiveComboModeForStorage(comboMode) or comboMode;

    local ns = IconCacheNs();
    if not iconCache[ns] then
        iconCache[ns] = {};
    end
    if not iconCache[ns][comboMode] then
        iconCache[ns][comboMode] = {};
    end

    local cached = iconCache[ns][comboMode][slotIndex];

    -- Check if we have a valid cache entry for this bind
    local bindKey = BuildCrossbarBindKey(slotData);
    if cached and cached.bindKey == bindKey then
        -- Cache hit - return icon even if nil (nil = no icon exists)
        return cached.icon;
    end

    -- Cache miss - compute icon
    local icon = nil;
    if slotData and slotData.actionType then
        icon = actions.GetBindIcon(slotData);
    end

    -- Store in cache
    iconCache[ns][comboMode][slotIndex] = {
        bindKey = bindKey,
        icon = icon,
    };

    return icon;
end

-- Clear crossbar icon cache
local function ClearCrossbarIconCache()
    iconCache = {};
end

-- Clear crossbar icon cache for a specific slot
local function ClearCrossbarIconCacheForSlot(comboMode, slotIndex)
    -- Use effective combo mode for cache key (Shared when shared expanded bar is enabled)
    comboMode = data.GetEffectiveComboModeForStorage and data.GetEffectiveComboModeForStorage(comboMode) or comboMode;
    for _, byMode in pairs(iconCache) do
        if byMode[comboMode] then
            byMode[comboMode][slotIndex] = nil;
        end
    end
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

    -- Abbreviation fonts per combo mode (for actions without icons)
    abbreviationFonts = {},

    -- Trigger label font (shows current combo mode)
    triggerLabelFont = nil,

    -- Combo text font (shows L2+R2, R2+L2, etc. in center)
    comboTextFont = nil,

    -- Palette name font (shows current palette name and index)
    paletteNameFont = nil,

    -- Window position (updated by ImGui window)
    windowX = 0,
    windowY = 0,
    -- Wide (dual-group) window left X — frozen while shared expanded chord is centered so we can restore after chord
    lastWideCrossbarWindowX = nil,
    wasSharedCenterChordLayout = false,

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

    -- Visibility animation state for activeOnly display mode
    visibilityAnimation = {
        active = false,
        startTime = 0,
        fadeIn = true,
        progress = 1.0,
        wasHidden = false,
    },
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

-- Extra height at the top of the Crossbar ImGui window so palette scope / L2 / R2 / refresh draw inside the
-- window draw list (correct stacking vs other addons). Profile `windowPositions.Crossbar.y` stays the slot
-- grid top (unchanged from before this padding existed).
local CROSSBAR_WINDOW_TOP_DECOR_PAD = 80;

local function ApplyCrossbarWindowPositionOnce()
    if not gConfig or not gConfig.windowPositions or not gConfig.windowPositions['Crossbar'] then
        return false;
    end
    if not gConfig.appliedPositions then
        gConfig.appliedPositions = {};
    end
    if gConfig.appliedPositions['Crossbar'] then
        return false;
    end
    local pos = gConfig.windowPositions['Crossbar'];
    imgui.SetNextWindowPos({ pos.x, pos.y - CROSSBAR_WINDOW_TOP_DECOR_PAD }, ImGuiCond_Always);
    gConfig.appliedPositions['Crossbar'] = true;
    return true;
end

local function SaveCrossbarWindowSlotTopPosition()
    if not gConfig then
        return;
    end
    local wx, wy = imgui.GetWindowPos();
    if not gConfig.windowPositions then
        gConfig.windowPositions = {};
    end
    local slotTopY = wy + CROSSBAR_WINDOW_TOP_DECOR_PAD;
    local saved = gConfig.windowPositions['Crossbar'];
    if not saved then
        gConfig.windowPositions['Crossbar'] = { x = wx, y = slotTopY };
    elseif saved.x ~= wx or saved.y ~= slotTopY then
        saved.x = wx;
        saved.y = slotTopY;
    end
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
-- Returns: leftMode, rightMode, isExpanded, expandedSide ('left', 'right', 'center', 'both', or nil)
-- When useSharedExpandedBar and expandedSide == 'center', only the left column is drawn (Shared),
-- window width is one diamond group, and the bar is centered like a single 8-slot strip.
local function GetDisplayModes(activeCombo, settings)
    settings = settings or (gConfig and gConfig.hotbarCrossbar);
    local useSharedExp = settings and settings.useSharedExpandedBar == true;
    if activeCombo == COMBO_MODES.L2_THEN_R2 then
        if useSharedExp then
            return 'Shared', 'R2', true, 'center';
        end
        -- Expanded: L2 first, then R2 -> show L2R2 on left side only, right side dimmed (shows R2)
        return 'L2R2', 'R2', true, 'left';
    elseif activeCombo == COMBO_MODES.R2_THEN_L2 then
        if useSharedExp then
            return 'Shared', 'R2', true, 'center';
        end
        -- Expanded: R2 first, then L2 -> show R2L2 on right side only, left side dimmed (shows L2)
        return 'L2', 'R2L2', true, 'right';
    elseif activeCombo == 'Shared' then
        -- Shared expanded bar (edit mode only): show Shared on left side, right side dimmed
        return 'Shared', 'R2', true, 'left';
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

-- Determine which sides are visible based on display mode
-- Returns: leftVisible, rightVisible, crossbarVisible
local function GetVisibilityState(activeCombo, settings)
    if settings.displayMode ~= 'activeOnly' then
        return true, true, true;
    end

    -- activeOnly mode: hide when no trigger, show only active side
    if activeCombo == COMBO_MODES.NONE then
        return false, false, false;
    elseif activeCombo == COMBO_MODES.L2 or activeCombo == COMBO_MODES.L2_DOUBLE then
        return true, false, true;
    elseif activeCombo == COMBO_MODES.R2 or activeCombo == COMBO_MODES.R2_DOUBLE then
        return false, true, true;
    elseif activeCombo == COMBO_MODES.L2_THEN_R2 then
        -- L2+R2: show expanded L2R2 on left side only
        return true, false, true;
    elseif activeCombo == COMBO_MODES.R2_THEN_L2 then
        -- R2+L2: show expanded R2L2 on right side only
        return false, true, true;
    end

    -- Fallback: show both
    return true, true, true;
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

-- Start a visibility transition (fade in/out for activeOnly mode)
local function StartVisibilityTransition(fadeIn)
    state.visibilityAnimation.active = true;
    state.visibilityAnimation.startTime = GetTime();
    state.visibilityAnimation.fadeIn = fadeIn;
    state.visibilityAnimation.progress = fadeIn and 0.0 or 1.0;
end

-- Update visibility animation and return opacity multiplier (0-1)
local function UpdateVisibilityAnimation(settings)
    if not state.visibilityAnimation.active then
        return state.visibilityAnimation.fadeIn and 1.0 or 0.0;
    end

    local duration = settings.fadeAnimationDuration or 0.15;
    local elapsed = GetTime() - state.visibilityAnimation.startTime;
    local rawProgress = math.min(elapsed / duration, 1.0);

    if rawProgress >= 1.0 then
        state.visibilityAnimation.active = false;
        state.visibilityAnimation.progress = state.visibilityAnimation.fadeIn and 1.0 or 0.0;
    else
        -- Fade in: 0 -> 1, Fade out: 1 -> 0
        if state.visibilityAnimation.fadeIn then
            state.visibilityAnimation.progress = EaseOutCubic(rawProgress);
        else
            state.visibilityAnimation.progress = 1.0 - EaseOutCubic(rawProgress);
        end
    end

    return state.visibilityAnimation.progress;
end

local function GetModesToResetForFrame(settings, targetLeftMode, targetRightMode)
    local allModes = ALL_COMBO_MODES;
    if settings and settings.perfOptimizeHideVisibleModes == false then
        return allModes;
    end

    local modes = {};
    local seen = {};
    local function addMode(m)
        if m and not seen[m] then
            seen[m] = true;
            table.insert(modes, m);
        end
    end

    addMode(state.currentLeftMode);
    addMode(state.currentRightMode);
    addMode(targetLeftMode);
    addMode(targetRightMode);

    if state.animation.active then
        addMode(state.animation.fromLeftMode);
        addMode(state.animation.fromRightMode);
        addMode(state.animation.toLeftMode);
        addMode(state.animation.toRightMode);
    end

    if #modes == 0 then
        return allModes;
    end
    return modes;
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

-- Module settings captured at Initialize (used to lazily build PalEd_* primitives for the palette editor)
local crossbarInitModuleSettings = nil;

local function InitComboModeSlotResources(comboKey, moduleSettings, settings)
    state.slotPrims[comboKey] = {};
    state.iconPrims[comboKey] = {};
    state.timerFonts[comboKey] = {};
    state.mpCostFonts[comboKey] = {};
    state.quantityFonts[comboKey] = {};
    state.centerIconPrims[comboKey] = {};
    state.labelFonts[comboKey] = {};
    state.abbreviationFonts[comboKey] = {};

    for slotIndex = 1, SLOTS_PER_SIDE do
        local slotPrim = CreatePrimitive(basePrimData);
        state.slotPrims[comboKey][slotIndex] = slotPrim;

        local iconPrim = CreatePrimitive(basePrimData);
        state.iconPrims[comboKey][slotIndex] = iconPrim;

        local timerFontSettings = moduleSettings and deep_copy_table(moduleSettings.label_font_settings) or {};
        timerFontSettings.font_height = settings.recastTimerFontSize or 11;
        timerFontSettings.font_alignment = 1;
        timerFontSettings.font_color = settings.recastTimerFontColor or 0xFFFFFFFF;
        timerFontSettings.outline_color = 0xFF000000;
        timerFontSettings.outline_width = 2;
        state.timerFonts[comboKey][slotIndex] = FontManager.create(timerFontSettings);

        local mpCostFontSettings = moduleSettings and deep_copy_table(moduleSettings.label_font_settings) or {};
        mpCostFontSettings.font_height = settings.mpCostFontSize or 10;
        mpCostFontSettings.font_alignment = 2;
        mpCostFontSettings.font_color = settings.mpCostFontColor or 0xFFD4FF97;
        mpCostFontSettings.outline_color = 0xFF000000;
        mpCostFontSettings.outline_width = 2;
        state.mpCostFonts[comboKey][slotIndex] = FontManager.create(mpCostFontSettings);

        local quantityFontSettings = moduleSettings and deep_copy_table(moduleSettings.label_font_settings) or {};
        quantityFontSettings.font_height = settings.quantityFontSize or 10;
        quantityFontSettings.font_alignment = 2;
        quantityFontSettings.font_color = settings.quantityFontColor or 0xFFFFFFFF;
        quantityFontSettings.outline_color = 0xFF000000;
        quantityFontSettings.outline_width = 2;
        state.quantityFonts[comboKey][slotIndex] = FontManager.create(quantityFontSettings);

        local labelFontSettings = moduleSettings and moduleSettings.label_font_settings or {};
        state.labelFonts[comboKey][slotIndex] = FontManager.create(labelFontSettings);

        local abbrSettings = moduleSettings and deep_copy_table(moduleSettings.label_font_settings) or {};
        abbrSettings.font_height = 12;
        abbrSettings.font_alignment = 1;
        abbrSettings.font_color = 0xFFF4DA97;
        abbrSettings.outline_color = 0xFF000000;
        abbrSettings.outline_width = 2;
        state.abbreviationFonts[comboKey][slotIndex] = FontManager.create(abbrSettings);
    end

    state.centerIconPrims[comboKey]['dpad'] = {};
    state.centerIconPrims[comboKey]['face'] = {};

    for iconIdx = 1, 4 do
        local dpadIconPrim = CreatePrimitive(basePrimData);
        state.centerIconPrims[comboKey]['dpad'][iconIdx] = dpadIconPrim;

        local faceIconPrim = CreatePrimitive(basePrimData);
        state.centerIconPrims[comboKey]['face'][iconIdx] = faceIconPrim;
    end
end

local function EnsurePalEdPrimitivesForComboMode(comboMode, settings)
    local primKey = PAL_ED_PREFIX .. comboMode;
    if state.slotPrims[primKey] then
        return;
    end
    InitComboModeSlotResources(primKey, crossbarInitModuleSettings, settings);
end

function M.Initialize(settings, moduleSettings)
    if state.initialized then return; end

    crossbarInitModuleSettings = moduleSettings;

    -- Initial position - use saved position from profile or default
    local savedPos = gConfig and gConfig.windowPositions and gConfig.windowPositions['Crossbar'];

    local defaultX, defaultY = GetDefaultPosition(settings);
    state.windowX = savedPos and savedPos.x or defaultX;
    state.windowY = savedPos and savedPos.y or defaultY;
    state.lastWideCrossbarWindowX = state.windowX;

    local width, height, groupWidth, groupHeight = GetCrossbarDimensions(settings);

    -- Create window background
    local primData = moduleSettings and moduleSettings.prim_data or {};
    state.bgHandle = windowBg.create(primData, settings.backgroundTheme, settings.bgScale, settings.borderScale);

    for _, comboMode in ipairs(ALL_COMBO_MODES) do
        InitComboModeSlotResources(comboMode, moduleSettings, settings);
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

    -- Create palette name font (center aligned, below crossbar)
    local paletteNameFontSettings = moduleSettings and deep_copy_table(moduleSettings.trigger_font_settings) or {};
    paletteNameFontSettings.font_height = settings.paletteNameFontSize or 10;
    paletteNameFontSettings.font_color = 0xFFFFFFFF;
    paletteNameFontSettings.font_alignment = 1;  -- Center alignment
    state.paletteNameFont = FontManager.create(paletteNameFontSettings);

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
local function DrawSlot(comboMode, slotIndex, x, y, slotSize, settings, isActive, isPressed, animOpacity, yOffset, skillchainName, activeCombo, editorClipRect)
    animOpacity = animOpacity or 1.0;
    yOffset = yOffset or 0;

    local palSk = data.GetCrossbarPaletteEditSessionKey and data.GetCrossbarPaletteEditSessionKey();
    local draftLayer = data.IsCrossbarDraftLayerOpen and data.IsCrossbarDraftLayerOpen();
    local primKey = comboMode;
    if palSk then
        EnsurePalEdPrimitivesForComboMode(comboMode, settings);
        primKey = PAL_ED_PREFIX .. comboMode;
    end

    -- Apply Y offset for animation
    local drawY = y + yOffset;

    -- Get press scale animation for icon (scales up when pressed, animates back down on release)
    local pressKey = primKey .. '_' .. slotIndex;
    local iconPressScale = 1.0;
    if settings.enablePressScale ~= false then
        iconPressScale = animation.getPressScale(pressKey, isPressed and isActive);
    end

    local function rawForSwap(cm, si)
        if palSk then
            return data.GetCrossbarSlotRawForSwapOverlay(cm, si);
        end
        return data.GetRawCrossbarSlotAction(cm, si);
    end

    -- Palette row shows draft overlay; HUD uses live data (live edits sync into draft via SyncDraftSlotFromLive).
    local slotData;
    if palSk then
        slotData = data.GetDraftSlotData(comboMode, slotIndex);
    else
        slotData = data.GetCrossbarSlotData(comboMode, slotIndex);
    end

    -- Get icon for this action (cached - only rebuilds when bind changes)
    local icon = GetCachedCrossbarIcon(comboMode, slotIndex, slotData);

    -- Dim inactive side: much stronger while a trigger is held (non-active half of the bar).
    local dimFactor = 1.0;
    if not isActive then
        if activeCombo and activeCombo ~= COMBO_MODES.NONE then
            dimFactor = settings.inactiveSideWhileTriggerDim;
            if dimFactor == nil then dimFactor = 0.15; end
        else
            dimFactor = settings.inactiveSlotDim or 0.5;
        end
    end

    -- Crossbar layout: slotIndex maps to a position within the diamond:
    -- 1=Top, 2=Right, 3=Bottom, 4=Left (same mapping for face slots 5-8 via -4).
    -- Top-slot labels placed below can overlap the bottom slot's MP cost, so render them above.
    local posIndex = (slotIndex <= 4) and slotIndex or (slotIndex - 4);
    local labelAboveSlot = (posIndex == 1);

    -- Edit Full Palette: empty slots — lighter tint so they read clearly on the row panel (see palettemanager child BG).
    local PAL_ED_EMPTY_SLOT_BG = 0xFF8E96AC;
    local slotBgColor = settings.slotBackgroundColor or 0x55000000;
    local slotOpacity = settings.slotOpacity or 1.0;
    if palSk and not slotData then
        slotBgColor = PAL_ED_EMPTY_SLOT_BG;
        slotOpacity = 1.0;
    end

    -- Gather resources for this slot
    local resources = {
        slotPrim = state.slotPrims[primKey] and state.slotPrims[primKey][slotIndex],
        iconPrim = state.iconPrims[primKey] and state.iconPrims[primKey][slotIndex],
        timerFont = state.timerFonts[primKey] and state.timerFonts[primKey][slotIndex],
        mpCostFont = state.mpCostFonts[primKey] and state.mpCostFonts[primKey][slotIndex],
        quantityFont = state.quantityFonts[primKey] and state.quantityFonts[primKey][slotIndex],
        labelFont = state.labelFonts[primKey] and state.labelFonts[primKey][slotIndex],
        abbreviationFont = state.abbreviationFonts[primKey] and state.abbreviationFonts[primKey][slotIndex],
    };

    local idPrefix = palSk and 'paled' or 'crossbar';

    local scvForSlot = GetCrossbarSkillchainVisualsFromGlobal();

    -- Render slot using shared renderer (handles ALL rendering and interactions)
    slotrenderer.DrawSlot(resources, {
        -- Position/Size
        x = x,
        y = drawY,
        size = slotSize,
        
        -- Window wrapper name for inputs
        windowName = 'Crossbar',

        -- Action Data
        bind = slotData,
        icon = icon,

        -- Visual Settings
        slotBgColor = slotBgColor,
        slotOpacity = slotOpacity,
        dimFactor = dimFactor,
        animOpacity = animOpacity,
        isPressed = isPressed and isActive,
        iconPressScale = iconPressScale,
        showMpCost = palSk and false or (settings.showMpCost ~= false),
        mpCostFontSize = settings.mpCostFontSize or 10,
        mpCostFontColor = settings.mpCostFontColor or 0xFFD4FF97,
        mpCostNoMpColor = settings.mpCostNoMpColor or 0xFFFF4444,
        mpCostOffsetX = settings.mpCostOffsetX or 0,
        mpCostOffsetY = settings.mpCostOffsetY or 0,
        showQuantity = palSk and false or (settings.showQuantity ~= false),
        quantityFontSize = settings.quantityFontSize or 10,
        quantityFontColor = settings.quantityFontColor or 0xFFFFFFFF,
        quantityOffsetX = settings.quantityOffsetX or 0,
        quantityOffsetY = settings.quantityOffsetY or 0,
        showLabel = palSk and true or (settings.showActionLabels or false),
        labelText = slotData and (slotData.displayName or slotData.action or '') or '',
        labelOffsetX = palSk and 0 or (settings.actionLabelOffsetX or 0),
        labelOffsetY = palSk and 0 or ((settings.actionLabelOffsetY or 0) + 2),
        labelAboveSlot = labelAboveSlot,
        labelFontSize = settings.labelFontSize or 10,
        recastTimerFontSize = settings.recastTimerFontSize or 11,
        recastTimerFontColor = settings.recastTimerFontColor or 0xFFFFFFFF,
        flashCooldownUnder5 = settings.flashCooldownUnder5 or false,
        useHHMMCooldownFormat = settings.useHHMMCooldownFormat or false,
        labelFontColor = settings.labelFontColor or 0xFFFFFFFF,
        labelCooldownColor = settings.labelCooldownColor or 0xFF888888,
        labelNoMpColor = settings.labelNoMpColor or 0xFFFF4444,

        -- Interaction Config (use original Y for interaction, not animated Y)
        buttonId = string.format('##%s_%s_%d', idPrefix, comboMode, slotIndex),
        dropZoneId = string.format('%s_%s_%d', idPrefix, comboMode, slotIndex),
        dropAccepts = {'macro', 'crossbar_slot', 'slot'},
        onDrop = function(payload)
            if payload.type == 'macro' then
                -- Must match macropalette.HandleDropOnSlot: defaulting to data.jobId breaks Global/Items/Equipment/XIUI
                -- and custom bucket macros (same macroRef would resolve in the current job's macroDB).
                if payload.data and payload.data.macroPaletteKey == nil then
                    if macropalette.GetEffectivePaletteType then
                        payload.data.macroPaletteKey = macropalette.GetEffectivePaletteType();
                    else
                        payload.data.macroPaletteKey = data.jobId or 1;
                    end
                end
                if payload.data and macropalette.GetMacroSourceTagForDrops and payload.data.macroSourceStore == nil then
                    payload.data.macroSourceStore = macropalette.GetMacroSourceTagForDrops();
                end
                local m = payload.data;
                local arm = {};
                for k, v in pairs(m) do arm[k] = v; end
                if arm.macroRef == nil and m.id then
                    arm.macroRef = m.id;
                end
                local ex = data.NormalizeCrossbarSlotRawForSwap(rawForSwap(comboMode, slotIndex));
                local store = m.macroSourceStore or (macropalette.GetMacroSourceTagForDrops and macropalette.GetMacroSourceTagForDrops()) or 'profile';
                local built = data.BuildMacroSlotAfterDrop(arm, store, ex);
                if palSk then
                    data.SetDraftSlotData(comboMode, slotIndex, built);
                else
                    data.SetCrossbarSlotData(comboMode, slotIndex, built);
                end
            elseif payload.type == 'crossbar_slot' then
                -- Always read source/target from live draft/config at drop time. payload.data was captured at
                -- drag start and can alias stale tables after earlier moves in the same session (wrong swaps).
                local srcCombo = payload.comboMode;
                local srcSlot = payload.slotIndex;
                if srcCombo == comboMode and srcSlot == slotIndex then
                    return;
                end
                if palSk then data.BeginDraftUndoGroup(); end
                local srcRaw = data.NormalizeCrossbarSlotRawForSwap(rawForSwap(srcCombo, srcSlot));
                local tgtRaw = data.NormalizeCrossbarSlotRawForSwap(rawForSwap(comboMode, slotIndex));
                local newTgt, newSrc = data.SwapActiveMacroArmsInPlace(srcRaw, tgtRaw);
                local fT = data.FinalizeCrossbarRawSlotForStorage(newTgt);
                local fS = data.FinalizeCrossbarRawSlotForStorage(newSrc);
                if palSk then
                    if fT == nil then data.ClearDraftSlotData(comboMode, slotIndex) else data.SetDraftSlotData(comboMode, slotIndex, fT) end
                else
                    data.SetCrossbarSlotData(comboMode, slotIndex, fT);
                end
                if palSk then
                    if fS == nil then data.ClearDraftSlotData(payload.comboMode, payload.slotIndex) else data.SetDraftSlotData(payload.comboMode, payload.slotIndex, fS) end
                else
                    data.SetCrossbarSlotData(payload.comboMode, payload.slotIndex, fS);
                end
                if palSk then data.EndDraftUndoGroup(); end
            elseif payload.type == 'slot' then
                if payload.data then
                    local c = data.FinalizeCrossbarRawSlotForStorage(data.CopyTable(payload.data));
                    if palSk then
                        if c == nil then data.ClearDraftSlotData(comboMode, slotIndex) else data.SetDraftSlotData(comboMode, slotIndex, c) end
                    else
                        data.SetCrossbarSlotData(comboMode, slotIndex, c);
                    end
                end
            end
            -- Clear icon cache for affected slots (targeted - fast)
            ClearCrossbarIconCacheForSlot(comboMode, slotIndex);
            slotrenderer.InvalidateSlotByKey(comboMode .. ':' .. slotIndex);
            -- For crossbar slot swaps, also clear the source slot
            if payload.type == 'crossbar_slot' then
                ClearCrossbarIconCacheForSlot(payload.comboMode, payload.slotIndex);
                slotrenderer.InvalidateSlotByKey(payload.comboMode .. ':' .. payload.slotIndex);
            end
        end,
        dragType = 'crossbar_slot',
        getDragData = function()
            local raw = data.NormalizeCrossbarSlotRawForSwap(rawForSwap(comboMode, slotIndex));
            return {
                comboMode = comboMode,
                slotIndex = slotIndex,
                data = raw,
                icon = icon,
                label = slotData and (slotData.displayName or slotData.action) or ('Slot ' .. slotIndex),
                paletteEditStorageKey = draftLayer or palSk,
            };
        end,
        -- Edit Full Palette zones overlap HUD crossbar rects; FlushDeferredDrops picks highest priority first.
        dropPriority = palSk and 100 or 0,
        onRightClick = function()
            if palSk then
                data.ClearDraftSlotData(comboMode, slotIndex);
            else
                data.ClearCrossbarSlotData(comboMode, slotIndex);
            end
            -- Clear icon cache for this slot (targeted - fast)
            ClearCrossbarIconCacheForSlot(comboMode, slotIndex);
            slotrenderer.InvalidateSlotByKey(comboMode .. ':' .. slotIndex);
        end,
        onDoubleClick = palSk and function()
            data.SetPendingPaletteSlotEdit(slotData, comboMode, slotIndex);
        end or nil,
        showTooltip = true,

        -- Draw MP/Lv/Qty corner strings via ImGui foreground so they sit above D3D icon prims (and overlapping slots).
        drawCornerTextForeground = palSk and false or true,
        -- Edit Full Palette only: on-slot action labels via ImGui (not GDI); normal HUD uses labelFont above/below slots.
        labelForeground = palSk and true or false,

        -- Skillchain highlight (per-crossbar overrides with Hotbar Global fallback; palette editor uses helper when outside DrawWindow)
        skillchainName = skillchainName,
        skillchainColor = scvForSlot.color,
        skillchainIconScale = scvForSlot.iconScale,
        skillchainIconOffsetX = scvForSlot.iconOffsetX,
        skillchainIconOffsetY = scvForSlot.iconOffsetY,

        -- Scroll / parent clip (Edit Full Palette): hide D3D + GDI outside visible region
        editorClipRect = editorClipRect,
        editorStrictContain = false,
        -- Edit Full Palette: always use lightweight, non-reactive rendering.
        performanceLiteChecks = palSk and true or false,
        editorMinimalView = palSk and true or false,
        forceImGuiIcon = palSk and true or false,
        suppressActionOnClick = palSk and true or false,
    });
end

-- Note: HandleSlotInteraction removed - now handled by slotrenderer.DrawSlot

-- Draw center icons for a diamond via ImGui (renders on top of everything)
-- animOpacity: 0-1 for animation fade (default 1.0)
local function DrawDiamondCenterIconsImGui(diamondType, groupX, groupY, settings, isActive, drawList, animOpacity, activeCombo)
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
                local dimFactor = 1.0;
                if not isActive then
                    if activeCombo and activeCombo ~= COMBO_MODES.NONE then
                        dimFactor = settings.inactiveSideWhileTriggerDim;
                        if dimFactor == nil then dimFactor = 0.15; end
                    else
                        dimFactor = settings.inactiveSlotDim or 0.5;
                    end
                end
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

-- useSharedExpandedBar: L2+R2 / R2+L2 use one centered 8-slot row — chord glyph above that group only
local function DrawTriggerIconsSharedExpandedCenter(activeCombo, groupLeftX, groupY, groupWidth, settings, drawList)
    if not settings.showTriggerLabels then return; end
    if not drawList then return; end

    local baseScale = settings.triggerIconScale or 1.0;
    local iw = 49 * baseScale;
    local ih = 28 * baseScale;
    local textCol = imgui.GetColorU32({ 0.92, 0.86, 0.65, 0.95 });
    local chordTight = math.max(0.5, 0.65 * baseScale);
    local cx = groupLeftX + groupWidth * 0.5;
    local cy = groupY - ih * 0.5;

    local l2Active = activeCombo == COMBO_MODES.L2 or activeCombo == COMBO_MODES.L2_THEN_R2 or activeCombo == COMBO_MODES.R2_THEN_L2 or activeCombo == COMBO_MODES.L2_DOUBLE;
    local r2Active = activeCombo == COMBO_MODES.R2 or activeCombo == COMBO_MODES.L2_THEN_R2 or activeCombo == COMBO_MODES.R2_THEN_L2 or activeCombo == COMBO_MODES.R2_DOUBLE;
    if activeCombo == COMBO_MODES.NONE then
        l2Active = false;
        r2Active = false;
    end

    local l2PressScale = 1.0;
    local r2PressScale = 1.0;
    if settings.enablePressScale ~= false then
        l2PressScale = animation.getPressScale('trigger_L2', l2Active);
        r2PressScale = animation.getPressScale('trigger_R2', r2Active);
    end

    local function plusSize()
        local ptw, pth = 10, 14;
        if imgui.CalcTextSize then
            local ts = imgui.CalcTextSize('+');
            if type(ts) == 'table' then
                ptw = ts[1] or ts.x or ptw;
                pth = ts[2] or ts.y or pth;
            elseif type(ts) == 'number' then
                ptw = ts;
            end
        end
        return ptw, pth;
    end

    local function drawImageScaled(texName, ix, iy, w, h, tintColor)
        local tex = textures:GetControllerIcon(texName);
        if not tex or not tex.image then return; end
        local p = tonumber(ffi.cast('uint32_t', tex.image));
        if not p or p == 0 then return; end
        drawList:AddImage(p, { ix, iy }, { ix + w, iy + h }, { 0, 0 }, { 1, 1 }, tintColor);
    end

    local ptw, pth = plusSize();
    local gL, gR = chordTight, chordTight;
    local lw = iw * l2PressScale;
    local lh = ih * l2PressScale;
    local rw = iw * r2PressScale;
    local rh = ih * r2PressScale;
    local total = lw + gL + ptw + gR + rw;
    local leftX = cx - total * 0.5;
    local l2Tint = l2Active and 0xFFFFFFFF or 0x88FFFFFF;
    local r2Tint = r2Active and 0xFFFFFFFF or 0x88FFFFFF;
    drawImageScaled('L2', leftX, cy - lh * 0.5, lw, lh, l2Tint);
    drawList:AddText({ leftX + lw + gL, cy - pth * 0.5 }, textCol, '+');
    drawImageScaled('R2', leftX + lw + gL + ptw + gR, cy - rh * 0.5, rw, rh, r2Tint);
end

-- Draw combo text in center for complex combos (L2R2, R2L2, L2x2, R2x2), or L2/R2 when enabled
local function DrawComboText(activeCombo, centerX, topY, settings)
    if not settings.showComboText then
        if state.comboTextFont then
            state.comboTextFont:set_visible(false);
        end
        return;
    end

    -- Determine combo text based on active combo
    local comboText = nil;
    if activeCombo == COMBO_MODES.L2_THEN_R2 then
        -- Show "Shared" when shared expanded bar is enabled
        comboText = settings.useSharedExpandedBar and 'Shared' or 'L2+R2';
    elseif activeCombo == COMBO_MODES.R2_THEN_L2 then
        -- Show "Shared" when shared expanded bar is enabled
        comboText = settings.useSharedExpandedBar and 'Shared' or 'R2+L2';
    elseif activeCombo == 'Shared' then
        comboText = 'Shared';
    elseif activeCombo == COMBO_MODES.L2_DOUBLE then
        comboText = 'L2x2';
    elseif activeCombo == COMBO_MODES.R2_DOUBLE then
        comboText = 'R2x2';
    elseif activeCombo == COMBO_MODES.L2 then
        comboText = 'L2';
    elseif activeCombo == COMBO_MODES.R2 then
        comboText = 'R2';
    end

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
        state.comboTextFont:set_font_color(0xFFFFFFFF);
        state.comboTextFont:set_visible(true);
    end
end

-- Infinity icon for Global [G] (universal) crossbar palette scope
local cachedInfinityPaletteTex = nil;
local function GetInfinityPaletteIconTexture()
    if cachedInfinityPaletteTex and cachedInfinityPaletteTex.image then
        return cachedInfinityPaletteTex;
    end
    cachedInfinityPaletteTex = TextureManager.getFileTexture('jobs/FFXIV-1/infinite');
    if not cachedInfinityPaletteTex or not cachedInfinityPaletteTex.image then
        cachedInfinityPaletteTex = TextureManager.getFileTexture('jobs/Classic/infinite');
    end
    return cachedInfinityPaletteTex;
end

local function GetPaletteJobIconThemeFromSettings(settings)
    local t = settings and settings.paletteJobIconTheme;
    if t == 'Classic' or t == 'FFXI' or t == 'FFXIV-1' or t == 'ClassicFFXIV' then
        return t;
    end
    return 'Classic';
end

-- When showPaletteScopeIcon is nil (legacy profiles), scope icon followed showPaletteName; explicit true/false overrides.
local function ShouldShowPaletteScopeIcon(settings)
    if not settings then
        return false;
    end
    if settings.showPaletteScopeIcon == false then
        return false;
    end
    if settings.showPaletteScopeIcon == true then
        return true;
    end
    return settings.showPaletteName == true;
end

-- Scope icon (infinity = Global [G], else main job): centered above the center divider line
local function DrawPaletteScopeIconAboveDivider(dividerX, dividerTopY, settings, drawList)
    if not ShouldShowPaletteScopeIcon(settings) or not drawList then
        return;
    end

    local paletteName = palette.GetActivePaletteForCombo('L2');
    if not paletteName then
        return;
    end

    local jobId = data.jobId or 1;
    local iconTex;
    if palette.GetCrossbarPaletteScope() == 'universal' then
        iconTex = GetInfinityPaletteIconTexture();
    else
        iconTex = TextureManager.getJobIcon(jobId, GetPaletteJobIconThemeFromSettings(settings));
    end

    if not iconTex or not iconTex.image then
        return;
    end

    local iconPtr = tonumber(ffi.cast('uint32_t', iconTex.image));
    if not iconPtr then
        return;
    end

    local iconSize;
    local explicitSize = tonumber(settings.paletteScopeIconSize);
    if explicitSize and explicitSize > 0 then
        iconSize = math.floor(math.max(8, math.min(64, explicitSize)) + 0.5);
    else
        local fontSize = settings.paletteNameFontSize or 10;
        iconSize = math.max(12, math.min(22, math.floor(fontSize * 1.45)));
        iconSize = math.floor(iconSize * 1.50 + 0.5);
    end
    local gapAboveLine = 3;
    local scopeLiftY = tonumber(settings.paletteScopeIconOffsetY);
    if not scopeLiftY then
        scopeLiftY = 6;
    end
    -- Fixed gap between combo text ("L2"/"R2" at window top) and this icon; tune lift with the slider above.
    local clearanceAboveComboText = 6;
    -- Horizontally align with palette name offsets; sit just above the divider’s top endpoint
    local iconCenterX = dividerX + (settings.paletteNameOffsetX or 0);
    local iconTopY = dividerTopY - gapAboveLine - iconSize - scopeLiftY - clearanceAboveComboText;
    local leftX = iconCenterX - iconSize / 2;

    drawList:AddImage(
        iconPtr,
        { leftX, iconTopY },
        { leftX + iconSize, iconTopY + iconSize },
        { 0, 0 },
        { 1, 1 },
        imgui.GetColorU32({ 1, 1, 1, 1 })
    );
end

-- Draw palette name below crossbar (e.g., "Stuns (2/5)") — text only; scope icon is above the divider
local function DrawPaletteName(centerX, bottomY, settings)
    if not settings.showPaletteName then
        if state.paletteNameFont then
            state.paletteNameFont:set_visible(false);
        end
        return;
    end

    local paletteName = palette.GetActivePaletteForCombo('L2');
    if not paletteName then
        if state.paletteNameFont then
            state.paletteNameFont:set_visible(false);
        end
        return;
    end

    local jobId = data.jobId or 1;
    local subjobId = data.subjobId or 0;
    local index, total = palette.GetCrossbarPaletteLabelIndexAndTotal(paletteName, jobId, subjobId);

    local displayText;
    if index and total and total > 0 then
        displayText = string.format('%s (%d/%d)', paletteName, index, total);
    else
        displayText = paletteName;
    end
    local fontSize = settings.paletteNameFontSize or 10;
    local offsetX = settings.paletteNameOffsetX or 0;
    local offsetY = settings.paletteNameOffsetY or 0;
    local anchorX = centerX + offsetX;
    local anchorY = bottomY + offsetY;

    if state.paletteNameFont then
        state.paletteNameFont:set_font_height(fontSize);
        state.paletteNameFont:set_text(displayText);
        state.paletteNameFont:set_position_x(anchorX);
        state.paletteNameFont:set_position_y(anchorY);
        state.paletteNameFont:set_visible(true);
    end
end

-- Shared helper to draw one side (left or right) of the crossbar.
-- `side`: 'L2' or 'R2' — selects slot positions and center icon placement.
local function DrawSide(side, mode, groupX, groupY, slotSize, settings, isActive, pressedSlot, showPressed, animOpacity, drawList, yOffset, targetServerId, skillchainEnabled, activeCombo)
    animOpacity = animOpacity or 1.0;
    yOffset = yOffset or 0;

    for slotIndex = 1, SLOTS_PER_SIDE do
        local slotX, slotY = GetSlotPositionInWindow(side, slotIndex, state.windowX, state.windowY, settings);
        local isPressed = showPressed and pressedSlot == slotIndex;
        local slotSkillchainName = nil;
        if skillchainEnabled then
            local slotData = data.GetCrossbarSlotData(mode, slotIndex);
            if slotData then
                if slotData.actionType == 'ws' and slotData.action then
                    slotSkillchainName = skillchain.GetSkillchainForSlot(targetServerId, slotData.action);
                elseif slotData.actionType == 'pet' and slotData.action then
                    slotSkillchainName = skillchain.GetSkillchainForBloodPact(targetServerId, slotData.action);
                elseif slotData.actionType == 'macro' and slotData.macroText then
                    local primaryType, primaryName = macroparse.GetMacroPrimaryAndJaBadge(slotData.macroText);
                    if primaryType == 'ws' and primaryName then
                        slotSkillchainName = skillchain.GetSkillchainForSlot(targetServerId, primaryName);
                    elseif primaryType == 'pet' and primaryName then
                        slotSkillchainName = skillchain.GetSkillchainForBloodPact(targetServerId, primaryName);
                    end
                end
            end
        end
        DrawSlot(mode, slotIndex, slotX, slotY, slotSize, settings, isActive, isPressed, animOpacity, yOffset, slotSkillchainName, activeCombo);
    end

    DrawDiamondCenterIcons(mode, 'dpad', groupX, groupY, settings, isActive);
    DrawDiamondCenterIcons(mode, 'face', groupX, groupY, settings, isActive);

    if drawList and settings.showButtonIcons and animOpacity > 0.1 then
        local drawY = groupY + yOffset;
        DrawDiamondCenterIconsImGui('dpad', groupX, drawY, settings, isActive, drawList, animOpacity, activeCombo);
        DrawDiamondCenterIconsImGui('face', groupX, drawY, settings, isActive, drawList, animOpacity, activeCombo);
    end
end

local function DrawBarSet(leftMode, rightMode, leftGroupX, leftGroupY, rightGroupX, rightGroupY,
                          slotSize, settings, leftActive, rightActive, pressedSlot,
                          leftShowPressed, rightShowPressed, animOpacity, drawList, yOffset, targetServerId, skillchainEnabled, activeCombo)
    DrawSide('L2', leftMode, leftGroupX, leftGroupY, slotSize, settings, leftActive, pressedSlot, leftShowPressed, animOpacity, drawList, yOffset, targetServerId, skillchainEnabled, activeCombo);
    DrawSide('R2', rightMode, rightGroupX, rightGroupY, slotSize, settings, rightActive, pressedSlot, rightShowPressed, animOpacity, drawList, yOffset, targetServerId, skillchainEnabled, activeCombo);
end

-- Main draw function
function M.DrawWindow(settings, moduleSettings)
    if not state.initialized then return; end

    -- Update recast timers once per frame
    recast.Update();

    -- Ability/WS lists for IsActionAvailable (job dropdowns use same cache)
    playerdata.RefreshCachedLists(data);

    local slotSize = settings.slotSize or 48;

    -- Get current combo mode and pressed slot from controller (needed for layout + visibility)
    local activeCombo = controller.GetActiveCombo();
    local pressedSlot = controller.GetPressedSlot();

    -- Determine visibility for activeOnly display mode
    local leftVisible, rightVisible, crossbarVisible = GetVisibilityState(activeCombo, settings);

    -- Handle visibility animation for activeOnly mode
    local visibilityOpacity = 1.0;
    if settings.displayMode == 'activeOnly' then
        local wasHidden = state.visibilityAnimation.wasHidden;
        local isNowHidden = not crossbarVisible;

        -- Start fade animation on visibility change
        if isNowHidden ~= wasHidden then
            StartVisibilityTransition(not isNowHidden);  -- fadeIn = true when becoming visible
            state.visibilityAnimation.wasHidden = isNowHidden;
        end

        visibilityOpacity = UpdateVisibilityAnimation(settings);

        -- Early return if fully hidden and animation complete
        if visibilityOpacity <= 0.01 and not state.visibilityAnimation.active then
            M.SetHidden(true);
            return;
        end
    end

    -- Determine which bar set to display based on active combo
    local targetLeftMode, targetRightMode, isExpanded, expandedSide = GetDisplayModes(activeCombo, settings);

    local fullWidth, height, groupWidth, groupHeight = GetCrossbarDimensions(settings);
    local width = fullWidth;
    -- Shared expanded bar: one diamond width, centered on screen (window matches single 8-slot group)
    local hideRightForSharedCenter = (isExpanded and expandedSide == 'center');
    if hideRightForSharedCenter then
        width = groupWidth;
    end
    -- First frame after chord: wide bar again — restore stashed X so SaveWindowPosition doesn't persist narrow-centered X
    local exitingChordCenter = state.wasSharedCenterChordLayout and (not hideRightForSharedCenter);

    -- Window flags (dummy window for positioning, like hotbar display.lua)
    local windowFlags = GetBaseWindowFlags(gConfig.lockPositions);

    local windowName = 'Crossbar';
    local defaultX, defaultY = GetDefaultPosition(settings);

    local function storedCrossbarPosY()
        local posY = defaultY;
        local savedPos = gConfig.windowPositions and gConfig.windowPositions[windowName];
        if savedPos and savedPos.y ~= nil then
            posY = savedPos.y;
        elseif state.windowY ~= nil then
            posY = state.windowY;
        end
        return posY;
    end

    -- Check if anchor is currently being dragged - if so, force position
    local anchorDragging = drawing.IsAnchorDragging(windowName);

    if anchorDragging then
        -- Use state position directly during drag for immediate response (state Y = slot grid top).
        imgui.SetNextWindowPos({ state.windowX, state.windowY - CROSSBAR_WINDOW_TOP_DECOR_PAD }, ImGuiCond_Always);
    elseif hideRightForSharedCenter then
        -- Single centered strip: align window to horizontal screen center (Y from saved / last wide bar)
        local io = imgui.GetIO();
        local screenW = (io and io.DisplaySize and io.DisplaySize.x) or 1920;
        local slotY = storedCrossbarPosY();
        imgui.SetNextWindowPos({ (screenW - width) * 0.5, slotY - CROSSBAR_WINDOW_TOP_DECOR_PAD }, ImGuiCond_Always);
    elseif exitingChordCenter and state.lastWideCrossbarWindowX ~= nil then
        local slotY = storedCrossbarPosY();
        imgui.SetNextWindowPos({ state.lastWideCrossbarWindowX, slotY - CROSSBAR_WINDOW_TOP_DECOR_PAD }, ImGuiCond_Always);
    else
        -- Apply saved position (once) or default; saved Y is slot-grid top (see SaveCrossbarWindowSlotTopPosition).
        local hasSaved = gConfig.windowPositions and gConfig.windowPositions[windowName];

        if hasSaved then
            ApplyCrossbarWindowPositionOnce();
        else
            imgui.SetNextWindowPos({ defaultX, defaultY - CROSSBAR_WINDOW_TOP_DECOR_PAD }, ImGuiCond_FirstUseEver);
        end
    end

    imgui.SetNextWindowSize({ width, height + CROSSBAR_WINDOW_TOP_DECOR_PAD }, ImGuiCond_Always);

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

    local groupSpacing = settings.groupSpacing or 40;

    -- Calculate group positions (needed before window for proper sizing)
    local leftGroupX = state.windowX;
    local leftGroupY = state.windowY;
    local rightGroupX = state.windowX + groupWidth + groupSpacing;
    local rightGroupY = state.windowY;

    -- Determine active states based on combo mode and expanded side
    local leftActive, rightActive;
    if isExpanded then
        -- In expanded mode, only the expanded side is active, other side is dimmed
        if expandedSide == 'center' then
            -- useSharedExpandedBar: single Shared strip; no right column
            leftActive = true;
            rightActive = false;
        elseif expandedSide == 'left' then
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

    -- Get target server ID for skillchain prediction (cached for all slots)
    local targetServerId = nil;
    local scPreview = GetCrossbarSkillchainVisualsFromGlobal();
    local skillchainEnabled = scPreview.enabled;
    if skillchainEnabled then
        local mainTargetIdx = targetLib.GetTargets();
        if mainTargetIdx and mainTargetIdx ~= 0 then
            local targetEntity = GetEntity(mainTargetIdx);
            if targetEntity then
                targetServerId = targetEntity.ServerId;
            end
        end
    end

    -- Hide all slot and icon primitives first (we'll show the ones we need)
    local modesToReset = GetModesToResetForFrame(settings, targetLeftMode, targetRightMode);
    for _, mode in ipairs(modesToReset) do
        for slotIndex = 1, SLOTS_PER_SIDE do
            local slotPrim = state.slotPrims[mode] and state.slotPrims[mode][slotIndex];
            if slotPrim then slotPrim.visible = false; end
            local iconPrim = state.iconPrims[mode] and state.iconPrims[mode][slotIndex];
            if iconPrim then iconPrim.visible = false; end
        end
    end

    -- Hide all GDI fonts for all modes (we'll show the ones we need during DrawSlot)
    for _, mode in ipairs(modesToReset) do
        for slotIndex = 1, SLOTS_PER_SIDE do
            local labelFont = state.labelFonts[mode] and state.labelFonts[mode][slotIndex];
            if labelFont then labelFont:set_visible(false); end
            local timerFont = state.timerFonts[mode] and state.timerFonts[mode][slotIndex];
            if timerFont then timerFont:set_visible(false); end
            local mpCostFont = state.mpCostFonts[mode] and state.mpCostFonts[mode][slotIndex];
            if mpCostFont then mpCostFont:set_visible(false); end
            local quantityFont = state.quantityFonts[mode] and state.quantityFonts[mode][slotIndex];
            if quantityFont then quantityFont:set_visible(false); end
        end
    end

    -- Begin ImGui window - ALL slot rendering happens inside to enable interactions
    if imgui.Begin('Crossbar', true, windowFlags) then
        -- Save position if moved (profile support). While shared expanded chord is up, X is forced
        -- screen-centered each frame — only persist Y so wide-bar X isn't overwritten by the narrow window.
        if hideRightForSharedCenter then
            if gConfig.windowPositions and gConfig.windowPositions[windowName] then
                local wx, wy = imgui.GetWindowPos();
                local s = gConfig.windowPositions[windowName];
                local slotTopY = wy + CROSSBAR_WINDOW_TOP_DECOR_PAD;
                if s.y ~= slotTopY then
                    s.y = slotTopY;
                end
                if s.x ~= wx then
                    s.x = wx;
                end
            end
        else
            SaveCrossbarWindowSlotTopPosition();
        end
        windowPosX, windowPosY = imgui.GetWindowPos();

        -- Slot grid top (logical position); ImGui window top is `windowPosY` (higher on screen).
        state.windowX = windowPosX;
        state.windowY = windowPosY + CROSSBAR_WINDOW_TOP_DECOR_PAD;
        if not hideRightForSharedCenter then
            state.lastWideCrossbarWindowX = windowPosX;
        end

        -- Recalculate group positions with updated window position
        leftGroupX = state.windowX;
        leftGroupY = state.windowY;
        rightGroupX = state.windowX + groupWidth + groupSpacing;
        rightGroupY = state.windowY;

        -- Window draw list: keeps L2/R2, divider, palette scope, diamond center icons, and slot overlays
        -- in the Crossbar window layer (below other ImGui addon windows). Foreground was drawing on top of everything.
        local winDrawList = imgui.GetWindowDrawList();

        -- Draw bar sets based on animation state and display mode
        -- NOTE: DrawSlot calls must be inside imgui.Begin/End for interactions to work
        local isActiveOnlyMode = settings.displayMode == 'activeOnly';

        if state.animation.active then
            -- Get animation values for outgoing and incoming elements
            local outOpacity, outYOffset = GetOutgoingAnimationValues();
            local inOpacity, inYOffset = GetIncomingAnimationValues();

            -- Apply visibility fade for activeOnly mode
            outOpacity = outOpacity * visibilityOpacity;
            inOpacity = inOpacity * visibilityOpacity;

            -- Determine active states for "from" bar set
            local fromExpanded = state.animation.fromBarSet == 'expanded';
            local fromLeftActive = fromExpanded or state.animation.fromLeftMode == 'L2';
            local fromRightActive = fromExpanded or state.animation.fromRightMode == 'R2';

            if not isActiveOnlyMode or leftVisible then
                if state.animation.leftChanged then
                    if outOpacity > 0.01 then
                        DrawSide('L2', state.animation.fromLeftMode, leftGroupX, leftGroupY, slotSize, settings,
                            fromLeftActive, pressedSlot, false, outOpacity, winDrawList, outYOffset, targetServerId, skillchainEnabled, activeCombo);
                    end
                    if inOpacity > 0.01 then
                        DrawSide('L2', state.animation.toLeftMode, leftGroupX, leftGroupY, slotSize, settings,
                            leftActive, pressedSlot, leftShowPressed, inOpacity, winDrawList, inYOffset, targetServerId, skillchainEnabled, activeCombo);
                    end
                else
                    DrawSide('L2', state.animation.toLeftMode, leftGroupX, leftGroupY, slotSize, settings,
                        leftActive, pressedSlot, leftShowPressed, visibilityOpacity, winDrawList, 0, targetServerId, skillchainEnabled, activeCombo);
                end
            end

            if (not hideRightForSharedCenter) and (not isActiveOnlyMode or rightVisible) then
                if state.animation.rightChanged then
                    if outOpacity > 0.01 then
                        DrawSide('R2', state.animation.fromRightMode, rightGroupX, rightGroupY, slotSize, settings,
                            fromRightActive, pressedSlot, false, outOpacity, winDrawList, outYOffset, targetServerId, skillchainEnabled, activeCombo);
                    end
                    if inOpacity > 0.01 then
                        DrawSide('R2', state.animation.toRightMode, rightGroupX, rightGroupY, slotSize, settings,
                            rightActive, pressedSlot, rightShowPressed, inOpacity, winDrawList, inYOffset, targetServerId, skillchainEnabled, activeCombo);
                    end
                else
                    DrawSide('R2', state.animation.toRightMode, rightGroupX, rightGroupY, slotSize, settings,
                        rightActive, pressedSlot, rightShowPressed, visibilityOpacity, winDrawList, 0, targetServerId, skillchainEnabled, activeCombo);
                end
            end
        else
            if isActiveOnlyMode then
                if leftVisible then
                    DrawSide('L2', state.currentLeftMode, leftGroupX, leftGroupY, slotSize, settings,
                        leftActive, pressedSlot, leftShowPressed, visibilityOpacity, winDrawList, 0, targetServerId, skillchainEnabled, activeCombo);
                end
                if (not hideRightForSharedCenter) and rightVisible then
                    DrawSide('R2', state.currentRightMode, rightGroupX, rightGroupY, slotSize, settings,
                        rightActive, pressedSlot, rightShowPressed, visibilityOpacity, winDrawList, 0, targetServerId, skillchainEnabled, activeCombo);
                end
            elseif hideRightForSharedCenter then
                DrawSide('L2', state.currentLeftMode, leftGroupX, leftGroupY, slotSize, settings,
                    leftActive, pressedSlot, leftShowPressed, 1.0, winDrawList, 0, targetServerId, skillchainEnabled, activeCombo);
            else
                -- Normal mode: draw both sides at full opacity
                DrawBarSet(
                    state.currentLeftMode, state.currentRightMode,
                    leftGroupX, leftGroupY, rightGroupX, rightGroupY,
                    slotSize, settings,
                    leftActive, rightActive,
                    pressedSlot, leftShowPressed, rightShowPressed,
                    1.0, winDrawList, 0, targetServerId, skillchainEnabled, activeCombo
                );
            end
        end

        -- Center divider + palette scope + L2/R2 + refresh: window draw list (below other addon windows).
        -- CROSSBAR_WINDOW_TOP_DECOR_PAD expands the window upward so art above the slot grid is not clipped.
        local showCenterDecor = settings.displayMode ~= 'activeOnly';
        local centerXDecor = state.windowX + width * 0.5;
        local dividerTopYDecor = state.windowY + 10;
        if settings.showDivider and winDrawList and showCenterDecor and (not hideRightForSharedCenter) then
            local dividerY2 = state.windowY + height - 10;
            winDrawList:AddLine(
                { centerXDecor, dividerTopYDecor },
                { centerXDecor, dividerY2 },
                imgui.GetColorU32({ 1, 1, 1, 0.3 }),
                2
            );
        end
        if showCenterDecor and winDrawList then
            DrawPaletteScopeIconAboveDivider(centerXDecor, dividerTopYDecor, settings, winDrawList);
        end
        local topYDecor = state.windowY - 4;
        if showCenterDecor then
            DrawComboText(activeCombo, centerXDecor, topYDecor, settings);
        end
        local bottomYDecor = state.windowY + height + 4;
        if showCenterDecor then
            DrawPaletteName(centerXDecor, bottomYDecor, settings);
        end
        if winDrawList and showCenterDecor then
            if hideRightForSharedCenter then
                DrawTriggerIconsSharedExpandedCenter(activeCombo, leftGroupX, leftGroupY, groupWidth, settings, winDrawList);
            else
                DrawTriggerIcons(activeCombo, leftGroupX, rightGroupX, leftGroupY, groupWidth, settings, winDrawList);
            end
        end
        if state.windowX and actions.IsPaletteModifierHeld() then
            local refreshTexture = textures:Get('ui_refresh');
            if refreshTexture and refreshTexture.image and winDrawList then
                local iconSize = 18;
                local iconX = centerXDecor - (iconSize / 2);
                local iconY = state.windowY - 24;
                local pulseAlpha = 0.7 + 0.3 * math.sin(os.clock() * 6);
                local iconColor = imgui.GetColorU32({ 1.0, 1.0, 1.0, pulseAlpha });
                local iconPtr = tonumber(ffi.cast('uint32_t', refreshTexture.image));
                if iconPtr then
                    winDrawList:AddImage(
                        iconPtr,
                        { iconX, iconY },
                        { iconX + iconSize, iconY + iconSize },
                        { 0, 0 }, { 1, 1 },
                        iconColor
                    );
                end
            end
        end

        imgui.End();
    end

    -- Draw move anchor (only visible when config is open)
    local crossbarLocked = gConfig and gConfig.crossbarLockMovement;
    if not crossbarLocked then
        -- Use same window name as ImGui window so positions are shared
        local anchorNewX, anchorNewY = drawing.DrawMoveAnchor('Crossbar', state.windowX, state.windowY);
        if anchorNewX ~= nil then
            state.windowX = anchorNewX;
            state.windowY = anchorNewY;
            state.lastWideCrossbarWindowX = anchorNewX;

            -- Update config immediately so next frame's positioning logic picks it up
            if not gConfig.windowPositions then gConfig.windowPositions = {}; end
            gConfig.windowPositions['Crossbar'] = { x = anchorNewX, y = anchorNewY };
        end
    end

    local isActiveOnlyMode = settings.displayMode == 'activeOnly';

    -- Update window background (can happen after window closes)
    -- In activeOnly mode, apply visibility opacity to background
    if state.bgHandle then
        local bgOpacity = settings.backgroundOpacity;
        local borderOpacity = settings.borderOpacity;
        if isActiveOnlyMode then
            bgOpacity = bgOpacity * visibilityOpacity;
            borderOpacity = borderOpacity * visibilityOpacity;
        end
        windowBg.update(state.bgHandle, state.windowX, state.windowY, width, height, {
            theme = settings.backgroundTheme,
            bgScale = settings.bgScale,
            borderScale = settings.borderScale,
            bgOpacity = bgOpacity,
            borderOpacity = borderOpacity,
            bgColor = settings.bgColor,
            borderColor = settings.borderColor,
        });
    end

    state.wasSharedCenterChordLayout = hideRightForSharedCenter;
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
        for _, comboMode in ipairs(ALL_COMBO_MODES) do
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
                local abbrFont = state.abbreviationFonts[comboMode] and state.abbreviationFonts[comboMode][slotIndex];
                if abbrFont then abbrFont:set_visible(false); end
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

        -- Hide palette name
        if state.paletteNameFont then
            state.paletteNameFont:set_visible(false);
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

    for _, comboMode in ipairs(ALL_COMBO_MODES) do
        for slotIndex = 1, SLOTS_PER_SIDE do
            -- Recreate label font
            local labelFont = state.labelFonts[comboMode] and state.labelFonts[comboMode][slotIndex];
            local labelSettings = moduleSettings and moduleSettings.label_font_settings or {};
            if labelFont then
                state.labelFonts[comboMode][slotIndex] = FontManager.recreate(labelFont, labelSettings);
            end

            -- Recreate abbreviation font
            local abbrFont = state.abbreviationFonts[comboMode] and state.abbreviationFonts[comboMode][slotIndex];
            if abbrFont then
                local abbrSettings = moduleSettings and deep_copy_table(moduleSettings.label_font_settings) or {};
                abbrSettings.font_height = 12;
                abbrSettings.font_alignment = 1;  -- Center
                abbrSettings.font_color = 0xFFF4DA97;  -- Gold
                abbrSettings.outline_color = 0xFF000000;
                abbrSettings.outline_width = 2;
                state.abbreviationFonts[comboMode][slotIndex] = FontManager.recreate(abbrFont, abbrSettings);
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

    -- Recreate palette name font
    if state.paletteNameFont then
        local paletteNameSettings = moduleSettings and deep_copy_table(moduleSettings.trigger_font_settings) or {};
        paletteNameSettings.font_height = settings.paletteNameFontSize or 10;
        paletteNameSettings.font_color = 0xFFFFFFFF;
        paletteNameSettings.font_alignment = 1;  -- Center alignment
        state.paletteNameFont = FontManager.recreate(state.paletteNameFont, paletteNameSettings);
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

    for _, comboMode in ipairs(ALL_COMBO_MODES) do
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

            local abbrFont = state.abbreviationFonts[comboMode] and state.abbreviationFonts[comboMode][slotIndex];
            if abbrFont then FontManager.destroy(abbrFont); end
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
        state.abbreviationFonts[comboMode] = nil;
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

    -- Destroy palette name font
    if state.paletteNameFont then
        FontManager.destroy(state.paletteNameFont);
        state.paletteNameFont = nil;
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

-- Clear icon cache for a specific slot (call on targeted slot updates)
function M.ClearIconCacheForSlot(comboMode, slotIndex)
    ClearCrossbarIconCacheForSlot(comboMode, slotIndex);
end

-- Reset crossbar position to default (called when settings are reset)
function M.ResetPositions()
    if not state.initialized then return; end
    local settings = gConfig and gConfig.hotbarCrossbar or {};
    local defaultX, defaultY = GetDefaultPosition(settings);
    state.windowX = defaultX;
    state.windowY = defaultY;
    state.lastWideCrossbarWindowX = defaultX;
    if gConfig.windowPositions then
        gConfig.windowPositions['Crossbar'] = { x = defaultX, y = defaultY };
    end
    if gConfig.appliedPositions then
        gConfig.appliedPositions['Crossbar'] = nil;
    end
end

-- ============================================
-- Edit Full Palette (same DrawSlot path as gameplay; requires data.BeginCrossbarPaletteEditSession)
-- ============================================

-- Shared palette-editor slot row. Either or both of modeLeft (L2 group) and modeRight (R2 group) may be set.
-- When only one is set, the other trigger half is omitted (Pets tab filter).
local function DrawPaletteEditorRow(screenOriginX, screenOriginY, settings, modeLeft, modeRight, clipMinX, clipMinY, clipMaxX, clipMaxY)
    if not state.initialized then return; end
    if not modeLeft and not modeRight then
        return;
    end
    local editorClipRect;
    if clipMinX and clipMinY and clipMaxX and clipMaxY then
        editorClipRect = { clipMinX, clipMinY, clipMaxX, clipMaxY };
    end
    local slotSize = settings.slotSize or 48;
    for slotIndex = 1, SLOTS_PER_SIDE do
        if modeLeft then
            local sx, sy = GetSlotPositionInWindow('L2', slotIndex, screenOriginX, screenOriginY, settings);
            DrawSlot(modeLeft, slotIndex, sx, sy, slotSize, settings, true, false, 1.0, 0, nil, COMBO_MODES.NONE, editorClipRect);
        end
        if modeRight then
            local sx, sy = GetSlotPositionInWindow('R2', slotIndex, screenOriginX, screenOriginY, settings);
            DrawSlot(modeRight, slotIndex, sx, sy, slotSize, settings, true, false, 1.0, 0, nil, COMBO_MODES.NONE, editorClipRect);
        end
    end
end

function M.DrawPaletteEditorL2R2Row(screenOriginX, screenOriginY, settings, modeLeft, modeRight, clipMinX, clipMinY, clipMaxX, clipMaxY)
    DrawPaletteEditorRow(screenOriginX, screenOriginY, settings, modeLeft, modeRight, clipMinX, clipMinY, clipMaxX, clipMaxY);
end

function M.DrawPaletteEditorSingleRow(screenOriginX, screenOriginY, settings, modeOnly, clipMinX, clipMinY, clipMaxX, clipMaxY)
    DrawPaletteEditorRow(screenOriginX, screenOriginY, settings, modeOnly, nil, clipMinX, clipMinY, clipMaxX, clipMaxY);
end

-- Edit Full Palette trigger glyphs (raised above slot cluster). glyphMode:
--   'primary'    — L2 | R2 (one glyph per side, gap between d-pad and face).
--   'doubleTap'  — L2 + "×2", R2 + "×2".
--   'chordCombo' — Left: L2 + R2, Right: R2 + L2 (images with + between).
-- Optional 5th: sides = { l = bool, r = bool } (default both true) — hide L2 and/or R2 trigger art when the row is one-sided.
function M.DrawPaletteEditorL2R2TriggerGlyphs(screenOriginX, screenOriginY, settings, glyphMode, sides)
    local dl = imgui.GetWindowDrawList();
    if not dl then return; end
    glyphMode = glyphMode or 'primary';
    local sl = (not sides or sides.l ~= false);
    local sr = (not sides or sides.r ~= false);
    local totalW, _, groupW, ghgt = GetCrossbarDimensions(settings);
    local gs = totalW - 2 * groupW;
    local slotSize = settings.slotSize or 48;
    local scale = (settings.triggerIconScale or 1.0) * math.max(0.42, math.min(1.1, slotSize / 48));
    local iw = 49 * scale;
    local ih = 28 * scale;
    local yLift = 35;
    local cy = screenOriginY + ghgt * 0.5 - yLift;
    local tint = imgui.GetColorU32({ 1, 1, 1, 0.88 });
    local textCol = imgui.GetColorU32({ 0.92, 0.86, 0.65, 0.95 });
    local gap = math.max(3, 4 * scale);
    -- Tight spacing around '+' for L2+R2 / R2+L2 chord glyphs
    local chordTight = math.max(0.5, 0.65 * scale);
    -- Minimal space between trigger image and ×2 (double-tap row)
    local doubleTapImgGap = math.max(1, 2 * scale);

    local function plusSize()
        local ptw, pth = 10, 14;
        if imgui.CalcTextSize then
            local ts = imgui.CalcTextSize('+');
            if type(ts) == 'table' then
                ptw = ts[1] or ts.x or ptw;
                pth = ts[2] or ts.y or pth;
            elseif type(ts) == 'number' then
                ptw = ts;
            end
        end
        return ptw, pth;
    end

    local function drawImage(texName, ix, iy)
        local tex = textures:GetControllerIcon(texName);
        if not tex or not tex.image then return; end
        local p = tonumber(ffi.cast('uint32_t', tex.image));
        if not p or p == 0 then return; end
        dl:AddImage(p, { ix, iy }, { ix + iw, iy + ih }, { 0, 0 }, { 1, 1 }, tint);
    end

    local function drawComboAtCenter(cx, firstTex, secondTex)
        local ptw, pth = plusSize();
        local gL, gR = chordTight, chordTight;
        local total = iw + gL + ptw + gR + iw;
        local leftX = cx - total * 0.5;
        drawImage(firstTex, leftX, cy - ih * 0.5);
        dl:AddText({ leftX + iw + gL, cy - pth * 0.5 }, textCol, '+');
        drawImage(secondTex, leftX + iw + gL + ptw + gR, cy - ih * 0.5);
    end

    if glyphMode == 'sharedChord' then
        drawComboAtCenter(screenOriginX + groupW * 0.5, 'L2', 'R2');
        return;
    end

    if glyphMode == 'chordCombo' then
        local l2cx = screenOriginX + groupW * 0.5;
        local r2cx = screenOriginX + groupW + gs + groupW * 0.5;
        if sl then
            drawComboAtCenter(l2cx, 'L2', 'R2');
        end
        if sr then
            drawComboAtCenter(r2cx, 'R2', 'L2');
        end
        return;
    end

    if glyphMode == 'doubleTap' then
        local x2Str = 'x2';
        local tw, th = 18, 16;
        if imgui.CalcTextSize then
            local ts = imgui.CalcTextSize(x2Str);
            if type(ts) == 'table' then
                tw = ts[1] or ts.x or tw;
                th = ts[2] or ts.y or th;
            end
        end
        -- Center the trigger image on the gap; x2 follows to the right (do not center icon+text as one unit).
        local l2cx = screenOriginX + groupW * 0.5;
        local r2cx = screenOriginX + groupW + gs + groupW * 0.5;
        if sl then
            local l2Tex = textures:GetControllerIcon('L2');
            if l2Tex and l2Tex.image then
                local p = tonumber(ffi.cast('uint32_t', l2Tex.image));
                if p and p ~= 0 then
                    local ix = l2cx - iw * 0.5;
                    local iy = cy - ih * 0.5;
                    dl:AddImage(p, { ix, iy }, { ix + iw, iy + ih }, { 0, 0 }, { 1, 1 }, tint);
                    dl:AddText({ ix + iw + doubleTapImgGap, cy - th * 0.5 }, textCol, x2Str);
                end
            end
        end
        if sr then
            local r2Tex = textures:GetControllerIcon('R2');
            if r2Tex and r2Tex.image then
                local p = tonumber(ffi.cast('uint32_t', r2Tex.image));
                if p and p ~= 0 then
                    local ix = r2cx - iw * 0.5;
                    local iy = cy - ih * 0.5;
                    dl:AddImage(p, { ix, iy }, { ix + iw, iy + ih }, { 0, 0 }, { 1, 1 }, tint);
                    dl:AddText({ ix + iw + doubleTapImgGap, cy - th * 0.5 }, textCol, x2Str);
                end
            end
        end
        return;
    end

    -- primary
    local l2cx = screenOriginX + groupW * 0.5;
    local r2cx = screenOriginX + groupW + gs + groupW * 0.5;
    if sl then
        drawImage('L2', l2cx - iw * 0.5, cy - ih * 0.5);
    end
    if sr then
        drawImage('R2', r2cx - iw * 0.5, cy - ih * 0.5);
    end
end

-- Shared expanded bar row: delegates to the main glyph function with 'sharedChord' mode.
function M.DrawPaletteEditorSharedChordTriggerGlyphs(screenOriginX, screenOriginY, settings)
    M.DrawPaletteEditorL2R2TriggerGlyphs(screenOriginX, screenOriginY, settings, 'sharedChord');
end

function M.GetEditorCrossbarRowDimensions(settings)
    return GetCrossbarDimensions(settings);
end

-- Hide all PalEd_* D3D/GDI resources (call when Edit Full Palette ImGui window is not drawing).
function M.HidePaletteEditorPrimitives()
    if not state.initialized then return; end
    for _, mode in ipairs(ALL_COMBO_MODES) do
        local pk = PAL_ED_PREFIX .. mode;
        if state.slotPrims[pk] then
            for i = 1, SLOTS_PER_SIDE do
                local sp = state.slotPrims[pk][i];
                local ip = state.iconPrims[pk][i];
                if sp then sp.visible = false; end
                if ip then ip.visible = false; end
                if state.timerFonts[pk] and state.timerFonts[pk][i] then
                    state.timerFonts[pk][i]:set_visible(false);
                end
                if state.mpCostFonts[pk] and state.mpCostFonts[pk][i] then
                    state.mpCostFonts[pk][i]:set_visible(false);
                end
                if state.quantityFonts[pk] and state.quantityFonts[pk][i] then
                    state.quantityFonts[pk][i]:set_visible(false);
                end
                if state.labelFonts[pk] and state.labelFonts[pk][i] then
                    state.labelFonts[pk][i]:set_visible(false);
                end
                if state.abbreviationFonts[pk] and state.abbreviationFonts[pk][i] then
                    state.abbreviationFonts[pk][i]:set_visible(false);
                end
            end
        end
        local cip = state.centerIconPrims[pk];
        if cip then
            for _, d in pairs({ 'dpad', 'face' }) do
                local t = cip[d];
                if t then
                    for j = 1, 4 do
                        if t[j] then t[j].visible = false; end
                    end
                end
            end
        end
    end
end

return M;
