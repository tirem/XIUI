--[[
* XIUI Crossbar - Display Module
* Renders crossbar UI with controller-friendly layout
* Uses windowBg.Draw (ImGui draw list) for background, ImGui/imtext for text and icons
]]--

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local ffi = require('ffi');
local windowBg = require('libs.windowbackground');
-- Note: windowBg is now an immediate-mode renderer; call windowBg.Draw() per frame.
local drawing = require('libs.drawing');
local imtext = require('libs.imtext');
local dragdrop = require('libs.dragdrop');

local data = require('modules.hotbar.data');
local actions = require('modules.hotbar.actions');
local textures = require('modules.hotbar.textures');
-- TextureManager is used for the palette scope icon overlay (job icon / infinity for universal palettes).
local TextureManager = require('libs.texturemanager');
local controller = require('modules.hotbar.controller');
local recast = require('modules.hotbar.recast');
local slotrenderer = require('modules.hotbar.slotrenderer');
-- playerdata caches the player's known abilities + weaponskills; `IsActionAvailable` falls
-- back to "unavailable" when the caches are empty. Keyboard hotbars warm these from their
-- own DrawWindow, but crossbar-only setups (`hotbarEnabled=false, crossbarEnabled=true`)
-- never touched playerdata before — every JA/WS slot then read as unavailable (grayed +
-- "X") even on jobs that knew the abilities. We now refresh once per frame from crossbar
-- DrawWindow as well; the refresh is signature-gated internally (job/level/equip diff) so
-- the steady-state cost is a few cache reads, not a full re-scan.
local playerdata = require('modules.hotbar.playerdata');
local animation = require('libs.animation');
local skillchain = require('modules.hotbar.skillchain');
-- macroparse extracts the primary line + JA badge type from a /ws or /pet macro body, so we can
-- predict skillchain icons on macro slots whose first line is a weapon skill or blood pact.
-- Display.lua does the same thing for keyboard hotbars; without it, crossbar macro slots whose
-- primary line is /ws or /pet would never light up even though firing the macro IS the WS/pact.
local macroparse = require('modules.hotbar.macroparse');
local targetLib = require('libs.target');
local palette = require('modules.hotbar.palette');
-- Used to dim the crossbar when a blocking game menu is open AND `crossbarDisableInMenu`
-- is enabled, so the player can see at a glance that controller input is paused.
local gamestate = require('core.gamestate');
-- macropalette is required only for the palette-editor drop handlers (effective palette key
-- + macro source store). Required at module scope here (mirrors Ferris); if a future
-- circular dependency creeps in this can be flipped to a lazy `require` inside the closures.
local macropalette = require('modules.hotbar.macropalette');

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
-- Full enumeration of combo-mode storage keys (used by the Edit Full Palette editor and the
-- pet-tab filter). 'Shared' is the chord-fallback for sharedExpanded layouts where both
-- L2+R2 and R2+L2 collapse to one set.
local ALL_COMBO_MODES = { 'L2', 'R2', 'L2R2', 'R2L2', 'L2x2', 'R2x2', 'Shared' };
-- Naming prefix on resource maps + IDs used by the Edit Full Palette draft layer so its
-- ImGui drop zones / animation keys never collide with the live HUD's 'crossbar_*' set.
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

-- Get cached icon (and precomputed abbreviation, when no icon) for a crossbar slot.
-- Returns: icon, abbr, abbrW. Mirrors display.lua's GetCachedIcon shape so DrawSlot
-- can skip GetActionAbbreviation + imtext.Measure per frame.
local function GetCachedCrossbarIcon(comboMode, slotIndex, slotData)
    -- Use effective combo mode for cache key (Shared when shared expanded bar is enabled)
    comboMode = data.GetEffectiveComboModeForStorage and data.GetEffectiveComboModeForStorage(comboMode) or comboMode;

    if not iconCache[comboMode] then
        iconCache[comboMode] = {};
    end

    local cached = iconCache[comboMode][slotIndex];

    -- Check if we have a valid cache entry for this bind
    local bindKey = BuildCrossbarBindKey(slotData);
    if cached and cached.bindKey == bindKey then
        return cached.icon, cached.abbr, cached.abbrW;
    end

    -- Cache miss - compute icon and (when no icon) the abbreviation
    local icon = nil;
    if slotData and slotData.actionType then
        icon = actions.GetBindIcon(slotData);
    end

    local abbr, abbrW = nil, nil;
    if not icon and slotData then
        abbr, abbrW = slotrenderer.ComputeAbbreviation(slotData);
    end

    -- Store in cache
    iconCache[comboMode][slotIndex] = {
        bindKey = bindKey,
        icon = icon,
        abbr = abbr,
        abbrW = abbrW,
    };

    return icon, abbr, abbrW;
end

-- Clear crossbar icon cache
-- iconCache rows hold the only Lua ref to D3D textures returned by actions.GetBindIcon
-- (LoadTextureFromPath wires a gc_safe_release finalizer). Wiping mid-frame — e.g. palette
-- deletion fires InvalidateAllVisualCachesAfterPaletteListMutation while the crossbar
-- DrawWindow is still building this frame's ImGui draw list — lets Lua GC finalize the COM
-- texture while AddImage still references it (CTD on Ashita 4.16). DeferRelease holds the
-- old table alive until FlushPendingReleases runs at the top of the next d3d_present.
local function ClearCrossbarIconCache()
    TextureManager.DeferRelease(iconCache);
    iconCache = {};
end

-- Clear crossbar icon cache for a specific slot
local function ClearCrossbarIconCacheForSlot(comboMode, slotIndex)
    -- Use effective combo mode for cache key (Shared when shared expanded bar is enabled)
    comboMode = data.GetEffectiveComboModeForStorage and data.GetEffectiveComboModeForStorage(comboMode) or comboMode;
    if iconCache[comboMode] then
        local oldRow = iconCache[comboMode][slotIndex];
        if oldRow ~= nil then
            TextureManager.DeferRelease(oldRow);
        end
        iconCache[comboMode][slotIndex] = nil;
    end
end

local state = {
    initialized = false,

    -- Window position (updated by ImGui window)
    windowX = 0,
    windowY = 0,

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

    -- useSharedExpandedBar bookkeeping. The shared-center layout collapses the bar to one
    -- diamond width and forces the X anchor to screen-center every frame; without these the
    -- normal X anchor would either get persisted as the centered narrow value (chord persists
    -- across a save) or snap back to the leftmost saved position on chord exit. The two-step
    -- handoff is: while in chord we stash the last "wide" window X here, then on the first
    -- frame that exits chord we re-anchor to that stashed X so the bar returns where the
    -- user actually placed it (rather than wherever the centered narrow bar happened to land).
    lastWideCrossbarWindowX = nil,
    wasSharedCenterChordLayout = false,
};

-- ============================================
-- Helper Functions
-- ============================================

-- Get the assets path
local function GetAssetsPath()
    return string.format('%saddons\\XIUI\\assets\\hotbar\\', AshitaCore:GetInstallPath());
end

-- Calculate crossbar window dimensions based on settings
local function GetCrossbarDimensions(settings)
    local gs = (gConfig and gConfig.globalScale) or 1.0;
    local slotSize = (settings.slotSize or 48) * gs;
    local slotGapV = (settings.slotGapV or 4) * gs;
    local slotGapH = (settings.slotGapH or 4) * gs;
    local diamondSpacing = (settings.diamondSpacing or 20) * gs;
    local groupSpacing = (settings.groupSpacing or 40) * gs;

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
-- Returns: leftMode, rightMode, isExpanded, expandedSide ('left', 'right', 'center', 'both', or nil)
-- When useSharedExpandedBar is enabled and the user holds a chord (L2+R2 / R2+L2), expandedSide
-- becomes 'center': only the left column is drawn (using the 'Shared' storage key), the window
-- shrinks to one diamond width, and DrawWindow re-centers it to screen X (a single 8-slot strip
-- centered like the FFXIV controller bar) rather than the two-diamond wide layout.
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
local function GetVisibilityState(activeCombo, settings, isEditMode)
    -- Always show full crossbar in edit mode or normal display mode
    if isEditMode or settings.displayMode ~= 'activeOnly' then
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

-- Get slot position within the crossbar window
local function GetSlotPositionInWindow(side, slotIndex, windowX, windowY, settings)
    local gs = (gConfig and gConfig.globalScale) or 1.0;
    local slotSize = (settings.slotSize or 48) * gs;
    local slotGapV = (settings.slotGapV or 4) * gs;
    local slotGapH = (settings.slotGapH or 4) * gs;
    local diamondSpacing = (settings.diamondSpacing or 20) * gs;
    local groupSpacing = (settings.groupSpacing or 40) * gs;

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
-- Window-decor padding (slot-top vs window-top accounting)
-- ============================================
-- ImGui clips anything we draw OUTSIDE the window's content rect. The crossbar paints a
-- lot of decoration above the slot grid (L2/R2 trigger icons, combo text, R1 cpal-anchor
-- pulse, palette-modifier refresh glyph) and below it (palette name, action labels). To
-- keep all of that inside the window's draw region we open the ImGui window taller than
-- the slot grid by CROSSBAR_WINDOW_TOP_DECOR_PAD on top and `GetCrossbarWindowBottomPad`
-- on the bottom, then offset the window-top so the SLOT GRID still lands at the user's
-- saved (or default) Y. `state.windowY` continues to mean "slot grid top" everywhere
-- else in this module, which lets the rest of the layout code stay unchanged.
-- The same logic applies horizontally: CROSSBAR_WINDOW_SIDE_PAD pixels of extra window
-- width on each side prevent action labels (which can be wider than slotSize) from being
-- clipped against the window's left/right edges. `state.windowX` always means "slot grid
-- left" (= window.x + SIDE_PAD); `gConfig.windowPositions.Crossbar.x` stores slot grid X
-- so saved positions remain stable across upgrades.
local CROSSBAR_WINDOW_TOP_DECOR_PAD = 80;
local CROSSBAR_WINDOW_SIDE_PAD      = 60;

local function GetCrossbarWindowBottomPad(settings)
    settings = settings or {};
    local pad = 10;
    if settings.showActionLabels then
        pad = pad + (settings.labelFontSize or 10) + 6 + math.max(0, tonumber(settings.actionLabelOffsetY) or 0);
    end
    pad = pad + math.floor(((settings.mpCostFontSize or 10) + (settings.quantityFontSize or 10)) * 0.15 + 0.5);
    return math.min(72, math.max(10, pad));
end

-- Profile stores SLOT TOP Y (`gConfig.windowPositions.Crossbar.y`), not window-top. When
-- we apply a saved position we subtract the decor pad so the slot grid lands where the
-- user originally placed it. The `appliedPositions` flag keeps ImGui's drag from being
-- overridden every frame (ImGuiCond_Always otherwise).
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
    imgui.SetNextWindowPos({ pos.x - CROSSBAR_WINDOW_SIDE_PAD, pos.y - CROSSBAR_WINDOW_TOP_DECOR_PAD }, ImGuiCond_Always);
    gConfig.appliedPositions['Crossbar'] = true;
    return true;
end

-- Save SLOT TOP Y, not window-top, so the saved coordinate stays meaningful even if the
-- decor pad changes between releases (or a future patch adds more decoration above the
-- slot grid). Skips writes when nothing changed to avoid table churn / unnecessary disk
-- saves on every frame.
local function SaveCrossbarWindowSlotTopPosition()
    if not gConfig then return; end
    local wx, wy = imgui.GetWindowPos();
    if not gConfig.windowPositions then
        gConfig.windowPositions = {};
    end
    -- Store SLOT GRID X (= window X + SIDE_PAD) so the saved coordinate is independent of
    -- the padding constant — the same convention as SLOT_TOP_Y (window Y + TOP_PAD).
    local slotTopX = wx + CROSSBAR_WINDOW_SIDE_PAD;
    local slotTopY = wy + CROSSBAR_WINDOW_TOP_DECOR_PAD;
    local saved = gConfig.windowPositions['Crossbar'];
    if not saved then
        gConfig.windowPositions['Crossbar'] = { x = slotTopX, y = slotTopY };
    elseif saved.x ~= slotTopX or saved.y ~= slotTopY then
        saved.x = slotTopX;
        saved.y = slotTopY;
    end
end

-- ============================================
-- Initialization
-- ============================================

function M.Initialize(settings, moduleSettings)
    if state.initialized then return; end

    -- Initial position - use saved position from profile or default
    local savedPos = gConfig and gConfig.windowPositions and gConfig.windowPositions['Crossbar'];

    local defaultX, defaultY = GetDefaultPosition(settings);
    state.windowX = savedPos and savedPos.x or defaultX;
    state.windowY = savedPos and savedPos.y or defaultY;

    local width, height, groupWidth, groupHeight = GetCrossbarDimensions(settings);

    state.initialized = true;
end

-- ============================================
-- Rendering
-- ============================================

-- Pre-allocated reusable table for DrawSlot
local cbParams = {};
local CB_DROP_ACCEPTS = {'macro', 'crossbar_slot', 'slot'};

-- Pre-created closures and string IDs per combo/slot (avoids closure + string allocations per frame)
local cbInteraction = {};

local function GetCbInteraction(comboMode, slotIndex)
    if not cbInteraction[comboMode] then
        cbInteraction[comboMode] = {};
    end
    if not cbInteraction[comboMode][slotIndex] then
        cbInteraction[comboMode][slotIndex] = {
            buttonId = string.format('##crossbar_%s_%d', comboMode, slotIndex),
            dropZoneId = string.format('crossbar_%s_%d', comboMode, slotIndex),
            pressKey = comboMode .. '_' .. slotIndex,
            onDrop = function(payload)
                if payload.type == 'macro' then
                    -- Ensure stored slot has a macroPaletteKey (fallback to current job if missing)
                    if payload.data then payload.data.macroPaletteKey = payload.data.macroPaletteKey or data.jobId; end
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
                -- Clear icon cache for affected slots
                ClearCrossbarIconCacheForSlot(comboMode, slotIndex);
                -- For crossbar slot swaps, also clear the source slot
                if payload.type == 'crossbar_slot' then
                    ClearCrossbarIconCacheForSlot(payload.comboMode, payload.slotIndex);
                end
            end,
            getDragData = function()
                local sd = data.GetCrossbarSlotData(comboMode, slotIndex);
                local ic = GetCachedCrossbarIcon(comboMode, slotIndex, sd);
                return {
                    comboMode = comboMode,
                    slotIndex = slotIndex,
                    data = sd,
                    icon = ic,
                    label = sd and (sd.displayName or sd.action) or ('Slot ' .. slotIndex),
                };
            end,
            onRightClick = function()
                data.ClearCrossbarSlotData(comboMode, slotIndex);
                -- Clear icon cache for this slot
                ClearCrossbarIconCacheForSlot(comboMode, slotIndex);
            end,
        };
    end
    return cbInteraction[comboMode][slotIndex];
end

-- Draw a single slot with drag/drop support using shared renderer
-- animOpacity: 0-1 for animation fade (default 1.0)
-- yOffset: Y offset in pixels for animation (default 0)
-- skillchainName: (optional) Skillchain name for WS slots
-- Reusable cbInteraction sub-tables built lazily for palette-editor slots so the editor and
-- the live crossbar each get their own slotInteraction set (different idPrefix/buttonId/
-- dropZoneId — palette editor uses 'paled_*'; live crossbar uses 'crossbar_*'). Keeping
-- them separate also lets the slotrenderer drop-zone-lock semantics treat them differently
-- (paled_* are never locked; crossbar_* respect crossbarLockMovement).
local cbInteractionPalEd = {};

local function GetCbInteractionPaletteEditor(comboMode, slotIndex)
    if not cbInteractionPalEd[comboMode] then cbInteractionPalEd[comboMode] = {}; end
    local cached = cbInteractionPalEd[comboMode][slotIndex];
    if cached then return cached; end

    local entry = {
        buttonId = string.format('##paled_%s_%d', comboMode, slotIndex),
        dropZoneId = string.format('paled_%s_%d', comboMode, slotIndex),
        pressKey = 'paled_' .. comboMode .. '_' .. slotIndex,
        onDrop = function(payload)
            -- Palette-editor drops go through the draft layer; Apply Draft promotes them to live.
            -- All branches normalize through the overlay (draft falls back to live) and finalize
            -- before writing so dual-arm macros swap correctly and empty results clear properly.
            if payload.type == 'macro' then
                if payload.data and payload.data.macroPaletteKey == nil then
                    if macropalette.GetEffectivePaletteType then
                        payload.data.macroPaletteKey = macropalette.GetEffectivePaletteType();
                    else
                        payload.data.macroPaletteKey = data.jobId or 1;
                    end
                end
                if payload.data and macropalette.GetMacroSourceTagForDrops
                    and payload.data.macroSourceStore == nil then
                    payload.data.macroSourceStore = macropalette.GetMacroSourceTagForDrops();
                end
                local arm = {};
                for k, v in pairs(payload.data) do arm[k] = v; end
                if arm.macroRef == nil and payload.data.id then
                    arm.macroRef = payload.data.id;
                end
                local existingRaw = data.GetCrossbarSlotRawForSwapOverlay(comboMode, slotIndex);
                local existing = data.NormalizeCrossbarSlotRawForSwap(existingRaw);
                local store = arm.macroSourceStore
                    or (macropalette.GetMacroSourceTagForDrops and macropalette.GetMacroSourceTagForDrops())
                    or 'profile';
                local built = data.BuildMacroSlotAfterDrop(arm, store, existing);
                data.SetDraftSlotData(comboMode, slotIndex, built);
            elseif payload.type == 'crossbar_slot' then
                -- Always read source/target from overlay at drop time; payload.data was captured
                -- at drag start and can alias stale tables after earlier moves in the same session.
                local srcCombo = payload.comboMode;
                local srcSlot = payload.slotIndex;
                if srcCombo == comboMode and srcSlot == slotIndex then return; end
                if data.BeginDraftUndoGroup then data.BeginDraftUndoGroup(); end
                local srcRaw = data.NormalizeCrossbarSlotRawForSwap(data.GetCrossbarSlotRawForSwapOverlay(srcCombo, srcSlot));
                local tgtRaw = data.NormalizeCrossbarSlotRawForSwap(data.GetCrossbarSlotRawForSwapOverlay(comboMode, slotIndex));
                local newTgt, newSrc = data.SwapActiveMacroArmsInPlace(srcRaw, tgtRaw);
                local fT = data.FinalizeCrossbarRawSlotForStorage(newTgt);
                local fS = data.FinalizeCrossbarRawSlotForStorage(newSrc);
                if fT == nil then
                    data.ClearDraftSlotData(comboMode, slotIndex);
                else
                    data.SetDraftSlotData(comboMode, slotIndex, fT);
                end
                if fS == nil then
                    data.ClearDraftSlotData(srcCombo, srcSlot);
                else
                    data.SetDraftSlotData(srcCombo, srcSlot, fS);
                end
                if data.EndDraftUndoGroup then data.EndDraftUndoGroup(); end
                -- 1.8.0 immediate-mode renderer has no persistent slot prim cache to invalidate;
                -- the icon cache clear above is the only refresh needed for the source slot.
                ClearCrossbarIconCacheForSlot(srcCombo, srcSlot);
            elseif payload.type == 'slot' then
                if payload.data then
                    local c = data.FinalizeCrossbarRawSlotForStorage(data.CopyTable(payload.data));
                    if c == nil then
                        data.ClearDraftSlotData(comboMode, slotIndex);
                    else
                        data.SetDraftSlotData(comboMode, slotIndex, c);
                    end
                end
            end
            -- Visual refresh for the target slot (matches live-HUD drop behaviour).
            -- 1.8.0 immediate-mode renderer has no persistent slot prim cache to invalidate;
            -- the icon cache clear is the only refresh needed (the bind hash on next frame
            -- naturally re-derives slot draw state — see ClearSlotIconCache notes in macropalette).
            ClearCrossbarIconCacheForSlot(comboMode, slotIndex);
        end,
        getDragData = function()
            -- Use overlay (draft falling back to live) so dragging a slot that hasn't been
            -- touched in this edit session still carries its persisted data. Reading draft-only
            -- here would drag nil and the drop handler would clear the target slot.
            local raw = data.NormalizeCrossbarSlotRawForSwap(data.GetCrossbarSlotRawForSwapOverlay(comboMode, slotIndex));
            return {
                type = 'crossbar_slot',
                comboMode = comboMode,
                slotIndex = slotIndex,
                data = raw,
            };
        end,
        onRightClick = function()
            data.ClearDraftSlotData(comboMode, slotIndex);
            ClearCrossbarIconCacheForSlot(comboMode, slotIndex);
        end,
        -- Double-click in Edit Full Palette opens the macro editor for the slot's draft
        -- content. For empty slots that resolves to nil and macropalette.OpenEditorForSlotData
        -- starts a fresh "creating new" session seeded with the active palette type's defaults.
        -- The (comboMode, slotIndex) carried in the pending edit lets palettemanager auto-bind
        -- the new macro to this slot after Save (see config/palettemanager.lua consume site).
        -- We funnel through data.SetPendingPaletteSlotEdit so the editor opens on the NEXT
        -- frame (consumed by config/palettemanager.lua after slots draw); opening it directly
        -- inside this click handler would put a modal inside the hotbar's draw pass and skip
        -- the macropalette draw-order assumptions.
        onDoubleClick = function()
            local slotData = data.GetDraftSlotData
                and data.GetDraftSlotData(comboMode, slotIndex)
                or nil;
            data.SetPendingPaletteSlotEdit(slotData, comboMode, slotIndex);
        end,
    };
    cbInteractionPalEd[comboMode][slotIndex] = entry;
    return entry;
end

-- Palette-editor empty-slot panel tint (matches the Edit Full Palette row fill in palettemanager.lua).
-- Lighter than the live crossbar's 0x55000000 so slot outlines read clearly against the editor row.
local PAL_ED_EMPTY_SLOT_BG = 0xFF8E96AC;

local function DrawSlot(comboMode, slotIndex, x, y, slotSize, settings, isActive, isPressed, animOpacity, yOffset, skillchainName, activeCombo, editorClipRect, magicBurstName)
    animOpacity = animOpacity or 1.0;
    yOffset = yOffset or 0;

    -- Edit Full Palette state: when active, this slot belongs to the editor's draft layer
    -- rather than the live crossbar. palSk is the storage-key the editor is targeting; the
    -- draft layer is separate per-key (so editing one palette doesn't touch the live binding).
    local palSk = data.GetCrossbarPaletteEditSessionKey and data.GetCrossbarPaletteEditSessionKey();
    local isEditor = palSk ~= nil;

    -- Get pre-created interaction closures and IDs. Editor and live get different prefixes so
    -- the slotrenderer drop-zone-lock policy can distinguish them (paled_* are never locked).
    local interaction = isEditor
        and GetCbInteractionPaletteEditor(comboMode, slotIndex)
        or GetCbInteraction(comboMode, slotIndex);

    -- Apply Y offset for animation
    local drawY = y + yOffset;

    -- Get press scale animation for icon
    local iconPressScale = 1.0;
    if settings.enablePressScale ~= false then
        iconPressScale = animation.getPressScale(interaction.pressKey, isPressed and isActive);
    end

    -- Slot data source: editor reads from the draft layer (synced from live at session start
    -- via data.SyncDraftSlotFromLive); live crossbar always reads the persisted binding.
    local slotData;
    if isEditor then
        slotData = data.GetDraftSlotData and data.GetDraftSlotData(comboMode, slotIndex) or nil;
    else
        slotData = data.GetCrossbarSlotData(comboMode, slotIndex);
    end

    -- Get icon + cached abbreviation for this action (cached - only rebuilds when bind changes)
    local icon, cachedAbbr, cachedAbbrW = GetCachedCrossbarIcon(comboMode, slotIndex, slotData);

    -- Global UI scale (slotSize/x/y come in already scaled; we apply gs here to
    -- font sizes and pixel offsets that come straight from settings).
    local gs = (gConfig and gConfig.globalScale) or 1.0;

    -- Diamond position: 1=Top, 2=Right, 3=Bottom, 4=Left (slots 5-8 map via -4 for face buttons).
    -- Top-slot labels placed below would overlap the bottom slot's MP/quantity text, so the
    -- editor (and any caller that asks for labels) flips them above for the top position.
    local posIndex = (slotIndex <= 4) and slotIndex or (slotIndex - 4);
    local labelAboveSlot = (posIndex == 1);

    -- Dim policy. Live crossbar: inactive sides get a softer dim; when a trigger is held the
    -- non-active half dims much harder so the active set pops. Editor: nothing is "inactive".
    local dimFactor = 1.0;
    if not isEditor and not isActive then
        if activeCombo and activeCombo ~= COMBO_MODES.NONE then
            dimFactor = settings.inactiveSideWhileTriggerDim;
            if dimFactor == nil then dimFactor = 0.15; end
        else
            dimFactor = settings.inactiveSlotDim or 0.5;
        end
    end

    -- Editor background: lighter tint behind empty editor slots so slot borders pop on the
    -- panel row; filled editor slots use the user's normal background.
    local slotBgColor = settings.slotBackgroundColor or 0x55000000;
    local slotOpacity = settings.slotOpacity or 1.0;
    if isEditor and not slotData then
        slotBgColor = PAL_ED_EMPTY_SLOT_BG;
        slotOpacity = 1.0;
    end

    -- Update reusable params table in-place
    local p = cbParams;
    p.x = x;
    p.y = drawY;
    p.size = slotSize;
    p.windowName = 'Crossbar';
    p.cachedAbbr = cachedAbbr;
    p.cachedAbbrW = cachedAbbrW;
    p.bind = slotData;
    p.icon = icon;
    p.slotBgColor = slotBgColor;
    p.slotOpacity = slotOpacity;
    p.dimFactor = dimFactor;
    p.animOpacity = animOpacity;
    p.isPressed = isPressed and isActive;
    p.iconPressScale = iconPressScale;
    p.showMpCost = isEditor and false or (settings.showMpCost ~= false);
    p.mpCostFontSize = (settings.mpCostFontSize or 10) * gs;
    p.mpCostFontColor = settings.mpCostFontColor or 0xFFD4FF97;
    p.mpCostNoMpColor = settings.mpCostNoMpColor or 0xFFFF4444;
    p.mpCostOffsetX = (settings.mpCostOffsetX or 0) * gs;
    p.mpCostOffsetY = (settings.mpCostOffsetY or 0) * gs;
    p.showQuantity = isEditor and false or (settings.showQuantity ~= false);
    p.showStackQuantity = settings.showStackQuantity == true;
    p.quantityFontSize = (settings.quantityFontSize or 10) * gs;
    p.quantityFontColor = settings.quantityFontColor or 0xFFFFFFFF;
    p.quantityOffsetX = (settings.quantityOffsetX or 0) * gs;
    p.quantityOffsetY = (settings.quantityOffsetY or 0) * gs;
    -- Editor: always show labels (on-slot abbrev with hover popup); live crossbar respects the user setting.
    p.showLabel = isEditor and true or (settings.showActionLabels or false);
    p.labelText = slotData and (slotData.displayName or slotData.action or '') or '';
    p.labelOffsetX = isEditor and 0 or ((settings.actionLabelOffsetX or 0) * gs);
    p.labelOffsetY = isEditor and 0 or (((settings.actionLabelOffsetY or 0) + 2) * gs);
    p.labelAboveSlot = labelAboveSlot;
    p.labelFontSize = (settings.labelFontSize or 10) * gs;
    p.recastTimerFontSize = (settings.recastTimerFontSize or 11) * gs;
    p.recastTimerFontColor = settings.recastTimerFontColor or 0xFFFFFFFF;
    p.flashCooldownUnder5 = settings.flashCooldownUnder5 or false;
    p.useHHMMCooldownFormat = settings.useHHMMCooldownFormat or false;
    p.labelFontColor = settings.labelFontColor or 0xFFFFFFFF;
    p.labelCooldownColor = settings.labelCooldownColor or 0xFF888888;
    p.labelNoMpColor = settings.labelNoMpColor or 0xFFFF4444;
    p.buttonId = interaction.buttonId;
    p.dropZoneId = interaction.dropZoneId;
    p.dropAccepts = CB_DROP_ACCEPTS;
    p.onDrop = interaction.onDrop;
    p.dragType = 'crossbar_slot';
    p.getDragData = interaction.getDragData;
    p.onRightClick = interaction.onRightClick;
    -- Editor slots: double-click opens the macro editor (empty slot = new macro seeded
    -- with palette defaults, filled slot = edit existing). Live crossbar slots leave
    -- onDoubleClick nil so single-click executes the action immediately.
    p.onDoubleClick = isEditor and interaction.onDoubleClick or nil;
    -- Editor slots don't have a "live" action to execute; suppressing the single-click
    -- action is what enables the click-tracking pipeline in slotrenderer to detect a
    -- second click and dispatch onDoubleClick. Live HUD keeps the default behavior.
    p.suppressActionOnClick = isEditor and true or false;
    p.showTooltip = true;
    -- Editor-only params consumed by slotrenderer Pass 2 (clip culling + on-slot multi-line label).
    p.editorClipRect = editorClipRect;
    p.editorMinimalView = isEditor;
    p.labelForeground = isEditor;
    -- Editor drops should win against the live crossbar zone underneath when the editor preview
    -- overlaps the HUD (FlushDeferredDrops resolves overlaps by highest priority).
    p.dropPriority = isEditor and 10 or nil;
    -- Skillchain highlight (only on live crossbar; editor preview suppresses it).
    p.skillchainName = (not isEditor) and skillchainName or nil;
    p.skillchainColor = gConfig.hotbarGlobal.skillchainHighlightColor or 0xFFD4AA44;
    -- Magic Burst highlight — same suppression rules as skillchain (editor preview has no
    -- live target so the prediction would be meaningless / misleading there).
    p.magicBurstName = (not isEditor) and magicBurstName or nil;
    p.magicBurstColor = gConfig.hotbarGlobal.magicBurstHighlightColor or 0xFF44D4FF;

    -- Render slot using shared renderer (handles ALL rendering and interactions)
    slotrenderer.DrawSlot(p);
end

-- Note: HandleSlotInteraction removed - now handled by slotrenderer.DrawSlot

-- Draw center icons for a diamond via ImGui (renders on top of everything)
-- animOpacity: 0-1 for animation fade (default 1.0)
local function DrawDiamondCenterIconsImGui(diamondType, groupX, groupY, settings, isActive, drawList, animOpacity)
    animOpacity = animOpacity or 1.0;
    if animOpacity <= 0.01 then return; end

    local gs = (gConfig and gConfig.globalScale) or 1.0;
    local slotSize = (settings.slotSize or 48) * gs;
    local slotGapV = (settings.slotGapV or 4) * gs;
    local slotGapH = (settings.slotGapH or 4) * gs;
    local diamondSpacing = (settings.diamondSpacing or 20) * gs;
    local iconSize = (settings.buttonIconSize or 24) * gs;
    local iconGapH = (settings.buttonIconGapH or 2) * gs;
    local iconGapV = (settings.buttonIconGapV or 2) * gs;
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

            -- R1 return indicator: rendered above R2 when the user has set a "cpal" anchor
            -- (via `/xiui cpal <Job>`). Pulses to draw the eye toward the return-to-anchor
            -- shortcut. Per-scope so anchors don't leak across universal vs job-scoped views.
            local scope = palette.GetCrossbarPaletteScope();
            local anchor = palette.GetCpalAnchor and palette.GetCpalAnchor(scope);
            if anchor then
                local r1Texture = textures:GetControllerIcon('R1');
                if r1Texture and r1Texture.image then
                    local r1Ptr = tonumber(ffi.cast('uint32_t', r1Texture.image));
                    if r1Ptr then
                        local r1Width = baseIconWidth;
                        local r1Height = baseIconHeight;
                        local r1IconX = r2GroupX + (groupWidth / 2) - (r1Width / 2);
                        local r1IconY = r2IconY - r1Height - 4;

                        -- ~2.5 Hz size pulse (peak +30%) keeps the indicator visible without
                        -- being distracting. Sin → abs so the icon "breathes" symmetrically.
                        local pulse = math.abs(math.sin(os.clock() * 2.5));
                        local sizeScale = 1.0 + 0.30 * pulse;
                        local sw = r1Width * sizeScale;
                        local sh = r1Height * sizeScale;
                        local sx = r1IconX + r1Width * 0.5 - sw * 0.5;
                        local sy = r1IconY + r1Height * 0.5 - sh * 0.5;

                        -- Pill-shaped dark backdrop spans the icon + "x2" text so they read
                        -- as a single legend regardless of the underlying scene.
                        local textGap, textEstW, pad = 3, 14, 4;
                        drawList:AddRectFilled(
                            { r1IconX - pad, r1IconY - pad },
                            { r1IconX + r1Width + textGap + textEstW + pad, r1IconY + r1Height + pad },
                            0x99000000, 5
                        );

                        drawList:AddImage(r1Ptr, { sx, sy }, { sx + sw, sy + sh }, { 0, 0 }, { 1, 1 }, 0xFFFFFFFF);
                        -- Gold ARGB: A=FF R=FF G=C8 B=32 → ImGui's GetColorU32 byte order is 0xAABBGGRR
                        drawList:AddText(
                            { r1IconX + r1Width + textGap, r1IconY + r1Height * 0.5 - 6 },
                            0xFF32C8FF,
                            'x2'
                        );
                    end
                end
            end
        end
    end
end

-- Shared expanded bar (useSharedExpandedBar): the L2+R2 / R2+L2 chord collapses both diamonds
-- into a single centered 8-slot strip, so DrawTriggerIcons can't position L2 over the left group
-- and R2 over the (now-absent) right group. This variant renders an "L2 + R2" chord glyph centred
-- on the single visible diamond: both icons inline with a small "+" between them, tinted brighter
-- when their trigger is part of the active combo. Same draw list as DrawTriggerIcons so the chord
-- glyph layers with the same z-order as the regular trigger labels.
local function DrawTriggerIconsSharedExpandedCenter(activeCombo, groupLeftX, groupY, groupWidth, settings, drawList)
    if not settings.showTriggerLabels then return; end
    if not drawList then return; end

    local baseScale = settings.triggerIconScale or 1.0;
    local iw = 49 * baseScale;
    local ih = 28 * baseScale;
    local textCol = imgui.GetColorU32({ 0.92, 0.86, 0.65, 0.95 });
    -- chordTight: pull the +/glyphs closer together as the icons shrink so the legend stays compact
    -- (matches the spacing the editor's shared-chord glyph uses in DrawPaletteEditorL2R2TriggerGlyphs).
    local chordTight = math.max(0.5, 0.65 * baseScale);
    local cx = groupLeftX + groupWidth * 0.5;
    local cy = groupY - ih * 0.5;

    -- Both triggers participate in any chord / double-tap involving them, so animate accordingly.
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

    -- Measure the "+" once so the chord can be centered as a single unit (icon + plus + icon).
    -- Fallback dims 10x14 keep layout sensible on builds where imgui.CalcTextSize isn't bound.
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
    local lw = iw * l2PressScale;
    local lh = ih * l2PressScale;
    local rw = iw * r2PressScale;
    local rh = ih * r2PressScale;
    local total = lw + chordTight + ptw + chordTight + rw;
    local leftX = cx - total * 0.5;
    local l2Tint = l2Active and 0xFFFFFFFF or 0x88FFFFFF;
    local r2Tint = r2Active and 0xFFFFFFFF or 0x88FFFFFF;
    drawImageScaled('L2', leftX, cy - lh * 0.5, lw, lh, l2Tint);
    drawList:AddText({ leftX + lw + chordTight, cy - pth * 0.5 }, textCol, '+');
    drawImageScaled('R2', leftX + lw + chordTight + ptw + chordTight, cy - rh * 0.5, rw, rh, r2Tint);
end

-- Draw combo text in center for complex combos (L2R2, R2L2, L2x2, R2x2) or edit mode
local function DrawComboText(activeCombo, centerX, topY, settings)
    if not settings.showComboText and not settings.editMode then
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

    -- In edit mode, always show with warning indicator
    if settings.editMode then
        comboText = '(!) ' .. (comboText or 'EDIT');
    end

    if not comboText then return; end

    -- Get font size and offsets from settings (scaled by globalScale)
    local gs = (gConfig and gConfig.globalScale) or 1.0;
    local fontSize = (settings.comboTextFontSize or 10) * gs;
    local offsetX = (settings.comboTextOffsetX or 0) * gs;
    local offsetY = (settings.comboTextOffsetY or 0) * gs;

    -- Draw centered text via imtext
    local drawList = GetUIDrawList();
    if drawList then
        -- Yellow warning color in edit mode, white otherwise
        local fontColor = settings.editMode and 0xFFFFFF00 or 0xFFFFFFFF;
        local textW = imtext.Measure(comboText, fontSize);
        local drawX = centerX + offsetX - (textW / 2);
        local drawY = topY + offsetY;
        imtext.Draw(drawList, comboText, drawX, drawY, fontColor, fontSize);
    end
end

-- Draw palette name below crossbar (e.g., "Stuns (2/5)"). The index/total count is
-- restricted to ENABLED palettes (RB-cycle filtered) and is hidden entirely when there
-- is only one cycleable palette (a 1/1 badge is just noise). For universal [G] scope,
-- routes through GetCrossbarPaletteLabelIndexAndTotal which uses the universal cycle list
-- instead of the per-job rows. (Lookup is microseconds at typical 1-10 palette counts; a
-- per-frame label cache was tried and reverted because it could go stale on PaletteManager
-- CRUD without a roster-version invalidation hook.)
local function DrawPaletteName(centerX, bottomY, settings)
    if not settings.showPaletteName then return; end

    local paletteName = palette.GetActivePaletteForCombo('L2');
    if not paletteName then return; end

    local jobId = data.jobId or 1;
    local subjobId = data.subjobId or 0;
    local index, total = palette.GetCrossbarPaletteLabelIndexAndTotal(paletteName, jobId, subjobId);

    local displayText;
    if index and total and total > 1 then
        displayText = string.format('%s (%d/%d)', paletteName, index, total);
    else
        displayText = paletteName;
    end
    local gs = (gConfig and gConfig.globalScale) or 1.0;
    local fontSize = (settings.paletteNameFontSize or 10) * gs;
    local offsetX = (settings.paletteNameOffsetX or 0) * gs;
    local offsetY = (settings.paletteNameOffsetY or 0) * gs;

    local drawList = GetUIDrawList();
    if drawList then
        local textW = imtext.Measure(displayText, fontSize);
        local drawX = centerX + offsetX - (textW / 2);
        local drawY = bottomY + offsetY;
        imtext.Draw(drawList, displayText, drawX, drawY, 0xFFFFFFFF, fontSize);
    end
end

-- ============================================
-- Palette scope icon (above the center divider)
-- Shows the infinity glyph for Global/universal palettes, or the job icon for job-scoped.
-- Lazily caches the infinity texture; the job-icon TextureManager has its own cache.
-- ============================================
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
    if t == 'Classic' or t == 'FFXI' or t == 'FFXIV-1' then
        return t;
    end
    return 'Classic';
end

-- When showPaletteScopeIcon is nil (legacy profiles), the scope icon follows showPaletteName;
-- explicit true/false overrides. Keeps the icon visible by default for existing users without
-- forcing them through the settings menu after the upgrade.
local function ShouldShowPaletteScopeIcon(settings)
    if not settings then return false; end
    if settings.showPaletteScopeIcon == false then return false; end
    if settings.showPaletteScopeIcon == true then return true; end
    return settings.showPaletteName == true;
end

-- Draws the scope marker (infinity for Global / universal, job icon otherwise) centred just
-- above the divider. Only fires when a palette is actually active for the L2 group.
local function DrawPaletteScopeIconAboveDivider(dividerX, dividerTopY, settings, drawList)
    if not ShouldShowPaletteScopeIcon(settings) or not drawList then return; end

    local paletteName = palette.GetActivePaletteForCombo('L2');
    if not paletteName then return; end

    local jobId = data.jobId or 1;
    local iconTex;
    if palette.GetCrossbarPaletteScope() == 'universal' then
        iconTex = GetInfinityPaletteIconTexture();
    else
        iconTex = TextureManager.getJobIcon(jobId, GetPaletteJobIconThemeFromSettings(settings));
    end

    if not iconTex or not iconTex.image then return; end

    local iconPtr = tonumber(ffi.cast('uint32_t', iconTex.image));
    if not iconPtr then return; end

    -- Size: explicit slider override (8..64 px) or auto-derive from palette-name font size.
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
    local scopeLiftY = tonumber(settings.paletteScopeIconOffsetY) or 6;
    -- Clearance above the L2 / R2 combo-text strip at the top of the window.
    local clearanceAboveComboText = 6;
    -- Horizontally align with palette-name X offset so the icon stacks with the name.
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

-- Helper to draw just the left side. `activeCombo` is threaded through so DrawSlot's dim
-- policy can apply Ferris's "stronger dim on the inactive half while a trigger is held"
-- behavior (settings.inactiveSideWhileTriggerDim, default 0.15) — without it the inactive
-- half just gets settings.inactiveSlotDim (default 0.5) like 1.7.5/early-1.8.0.
local function DrawLeftSide(mode, groupX, groupY, slotSize, settings, isActive, pressedSlot, showPressed, animOpacity, drawList, yOffset, targetServerId, skillchainEnabled, activeCombo, magicBurstEnabled)
    animOpacity = animOpacity or 1.0;
    yOffset = yOffset or 0;

    -- Draw left side slots
    for slotIndex = 1, SLOTS_PER_SIDE do
        local slotX, slotY = GetSlotPositionInWindow('L2', slotIndex, state.windowX, state.windowY, settings);
        local isPressed = showPressed and pressedSlot == slotIndex;
        -- Resolve slotData ONCE per slot so both prediction paths (skillchain + magic burst)
        -- share the same fetch; previously the SC path re-fetched per branch. Cheap either
        -- way, but cleaner now that two features need the same row.
        local slotData = (skillchainEnabled or magicBurstEnabled) and data.GetCrossbarSlotData(mode, slotIndex) or nil;

        -- Skillchain prediction: matches display.lua's coverage so the crossbar lights up the
        -- same WS / Blood Pact / macro slots the keyboard hotbar does. Bloodpact slots use the
        -- separate name->attributes map in skillchain.lua (bloodPactResonationMap); macro slots
        -- run through macroparse to extract the primary /ws or /pet line and then route to the
        -- matching predictor. Without the pet/macro branches, SMN ability slots and any /pet or
        -- /ws macro would never get a skillchain icon overlay on the crossbar.
        local slotSkillchainName = nil;
        if skillchainEnabled and slotData and slotData.action then
            if slotData.actionType == 'ws' then
                slotSkillchainName = skillchain.GetSkillchainForSlot(targetServerId, slotData.action);
            elseif slotData.actionType == 'pet' then
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
        -- Magic Burst prediction: spells / magical pact rages / /ma|/pet-primary macros. The
        -- single GetMagicBurstForSlot call internally routes by actionType + (for macros) the
        -- macroparse primary line — mirrors the dispatch pattern used by display.lua.
        local slotMagicBurstName = nil;
        if magicBurstEnabled and slotData then
            slotMagicBurstName = skillchain.GetMagicBurstForSlot(targetServerId, slotData);
        end
        DrawSlot(mode, slotIndex, slotX, slotY, slotSize, settings, isActive, isPressed, animOpacity, yOffset, slotSkillchainName, activeCombo, nil, slotMagicBurstName);
    end

    -- Draw center button icons via ImGui (if visible enough)
    if drawList and settings.showButtonIcons and animOpacity > 0.1 then
        local drawY = groupY + yOffset;
        DrawDiamondCenterIconsImGui('dpad', groupX, drawY, settings, isActive, drawList, animOpacity);
        DrawDiamondCenterIconsImGui('face', groupX, drawY, settings, isActive, drawList, animOpacity);
    end
end

-- Helper to draw just the right side. See DrawLeftSide above for the rationale on the
-- trailing activeCombo / magicBurstEnabled parameters.
local function DrawRightSide(mode, groupX, groupY, slotSize, settings, isActive, pressedSlot, showPressed, animOpacity, drawList, yOffset, targetServerId, skillchainEnabled, activeCombo, magicBurstEnabled)
    animOpacity = animOpacity or 1.0;
    yOffset = yOffset or 0;

    -- Draw right side slots
    for slotIndex = 1, SLOTS_PER_SIDE do
        local slotX, slotY = GetSlotPositionInWindow('R2', slotIndex, state.windowX, state.windowY, settings);
        local isPressed = showPressed and pressedSlot == slotIndex;
        -- See DrawLeftSide for slotData / SC / MB routing rationale (identical logic).
        local slotData = (skillchainEnabled or magicBurstEnabled) and data.GetCrossbarSlotData(mode, slotIndex) or nil;

        local slotSkillchainName = nil;
        if skillchainEnabled and slotData and slotData.action then
            if slotData.actionType == 'ws' then
                slotSkillchainName = skillchain.GetSkillchainForSlot(targetServerId, slotData.action);
            elseif slotData.actionType == 'pet' then
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
        local slotMagicBurstName = nil;
        if magicBurstEnabled and slotData then
            slotMagicBurstName = skillchain.GetMagicBurstForSlot(targetServerId, slotData);
        end
        DrawSlot(mode, slotIndex, slotX, slotY, slotSize, settings, isActive, isPressed, animOpacity, yOffset, slotSkillchainName, activeCombo, nil, slotMagicBurstName);
    end

    -- Draw center button icons via ImGui (if visible enough)
    if drawList and settings.showButtonIcons and animOpacity > 0.1 then
        local drawY = groupY + yOffset;
        DrawDiamondCenterIconsImGui('dpad', groupX, drawY, settings, isActive, drawList, animOpacity);
        DrawDiamondCenterIconsImGui('face', groupX, drawY, settings, isActive, drawList, animOpacity);
    end
end

-- Helper to draw a complete bar set (both sides) - used for non-animated drawing.
-- activeCombo flows from M.DrawWindow down to DrawSlot for the trigger-held dim policy.
local function DrawBarSet(leftMode, rightMode, leftGroupX, leftGroupY, rightGroupX, rightGroupY,
                          slotSize, settings, leftActive, rightActive, pressedSlot,
                          leftShowPressed, rightShowPressed, animOpacity, drawList, yOffset, targetServerId, skillchainEnabled, activeCombo, magicBurstEnabled)
    DrawLeftSide(leftMode, leftGroupX, leftGroupY, slotSize, settings, leftActive, pressedSlot, leftShowPressed, animOpacity, drawList, yOffset, targetServerId, skillchainEnabled, activeCombo, magicBurstEnabled);
    DrawRightSide(rightMode, rightGroupX, rightGroupY, slotSize, settings, rightActive, pressedSlot, rightShowPressed, animOpacity, drawList, yOffset, targetServerId, skillchainEnabled, activeCombo, magicBurstEnabled);
end

-- ============================================
-- Double-Tap Preview Windows
-- ============================================
-- Reference floating windows that mirror the L2x2 / R2x2 bars at user-configurable scale
-- and opacity. Rendered as independent ImGui windows AFTER the main crossbar so they have
-- their own position/draw list (no shared primitives, no z-fighting). Drawn non-interactive
-- (suppressActionOnClick) — the previews are visual reference only; actual slot activation
-- still routes through the main bar's controller path.

-- Return a shallow copy of settings with all layout-affecting fields scaled. Preserves the
-- caller's settings unchanged so the main bar keeps its own layout numbers.
--
-- Result is cached on a (settings ref, scale, layout-key signature) tuple — the full
-- shallow-copy is the dominant cost when the preview is on (8 slots × 2 windows × scaled
-- settings every frame). Invalidates only when the caller passes a new settings table OR
-- changes one of the geometry/scale inputs. This avoids the per-frame table-copy churn
-- without going stale on slider drags (signature changes immediately).
local previewSettingsCache = {
    settingsRef = nil,
    scale       = nil,
    signature   = nil,
    result      = nil,
};

local function MakePreviewSettings(settings, scale)
    -- Cheap signature: only the fields MakePreviewSettings actually reads. Keep this in
    -- sync with the scaled fields below — additions need a sig entry or the cache goes stale.
    local sig = string.format('%s|%s|%s|%s|%s|%s|%s|%s|%s',
        tostring(settings.slotSize), tostring(settings.slotGapV), tostring(settings.slotGapH),
        tostring(settings.diamondSpacing), tostring(settings.groupSpacing),
        tostring(settings.buttonIconSize), tostring(settings.buttonIconGapH), tostring(settings.buttonIconGapV),
        tostring(settings.triggerIconScale));

    if previewSettingsCache.settingsRef == settings
        and previewSettingsCache.scale == scale
        and previewSettingsCache.signature == sig then
        return previewSettingsCache.result;
    end

    local s = {};
    for k, v in pairs(settings) do s[k] = v; end
    s.slotSize       = math.max(8, math.floor((settings.slotSize       or 40) * scale));
    s.slotGapV       = math.max(1, math.floor((settings.slotGapV       or 2)  * scale));
    s.slotGapH       = math.max(1, math.floor((settings.slotGapH       or 2)  * scale));
    s.diamondSpacing = math.max(2, math.floor((settings.diamondSpacing or 16) * scale));
    s.groupSpacing   = math.max(4, math.floor((settings.groupSpacing   or 24) * scale));
    s.buttonIconSize = math.max(4, math.floor((settings.buttonIconSize or 24) * scale));
    s.buttonIconGapH = math.max(1, math.floor((settings.buttonIconGapH or 2)  * scale));
    s.buttonIconGapV = math.max(1, math.floor((settings.buttonIconGapV or 2)  * scale));
    s.triggerIconScale = (settings.triggerIconScale or 1.0) * scale;

    previewSettingsCache.settingsRef = settings;
    previewSettingsCache.scale       = scale;
    previewSettingsCache.signature   = sig;
    previewSettingsCache.result      = s;
    return s;
end

-- Draw one side of a double-tap preview using ImGui-only rendering (non-interactive).
-- winX/winY    : top-left of the preview ImGui window (slot grid origin).
-- side         : always 'L2' for single-group preview windows (slots start at window left).
-- mode         : crossbar storage mode string ('L2x2', 'R2x2', 'L2', 'R2', etc.) whose slots to render.
-- baseOp       : base opacity for the slot backgrounds (NOT dimmed) so frames stay visible.
-- dimFactor    : 0-1 multiplier applied to icon/text rendering (mirrors main bar dim policy).
-- targetServerId / skillchainEnabled / magicBurstEnabled: same per-slot SC/MB resolution
--                inputs used by the main DrawLeftSide/DrawRightSide path. Letting the preview
--                share them keeps the highlight calculus identical between live and preview
--                (a slot that lights up on the live bar lights up on its preview).
local function DrawPreviewSide(winX, winY, windowKey, side, mode, ps, baseOp, dimFactor, drawList, activeCombo, targetServerId, skillchainEnabled, magicBurstEnabled, showQty)
    local slotSize  = ps.slotSize or 40;
    local contentOp = baseOp * dimFactor;

    -- Slot background (flat rounded rect). slotrenderer's built-in bg path requires a D3D
    -- slot primitive (we have none in preview), so paint it manually with baseOp so the
    -- frame stays visible while icons dim with contentOp.
    local bgArgb = ps.slotBackgroundColor or 0x55000000;
    local bgA_raw = bit.rshift(bit.band(bgArgb, 0xFF000000), 24) / 255;
    local bgA = math.max(bgA_raw, 0.55) * baseOp;
    local bgR = bit.rshift(bit.band(bgArgb, 0x00FF0000), 16) / 255;
    local bgG = bit.rshift(bit.band(bgArgb, 0x0000FF00), 8) / 255;
    local bgB = bit.band(bgArgb, 0x000000FF) / 255;
    local cornerR = math.max(4, math.min(10, math.floor(slotSize * 0.125 + 0.5)));
    local bgU32 = imgui.GetColorU32({ bgR, bgG, bgB, bgA });

    for slotIndex = 1, SLOTS_PER_SIDE do
        local slotX, slotY = GetSlotPositionInWindow(side, slotIndex, winX, winY, ps);

        if drawList then
            drawList:AddRectFilled({ slotX, slotY }, { slotX + slotSize, slotY + slotSize }, bgU32, cornerR);
        end

        local slotData = data.GetCrossbarSlotData(mode, slotIndex);
        local icon = GetCachedCrossbarIcon(mode, slotIndex, slotData);

        -- Per-slot skillchain + magic burst resolution — identical dispatch to DrawLeftSide
        -- so a slot that highlights on the live crossbar highlights on its preview window
        -- too. Without this the preview would silently omit both borders, hiding useful
        -- "you could chain/MB from the other bar" cues exactly when the player is deciding
        -- whether to commit to a double-tap.
        local slotSkillchainName = nil;
        if skillchainEnabled and slotData and slotData.action then
            if slotData.actionType == 'ws' then
                slotSkillchainName = skillchain.GetSkillchainForSlot(targetServerId, slotData.action);
            elseif slotData.actionType == 'pet' then
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
        local slotMagicBurstName = nil;
        if magicBurstEnabled and slotData then
            slotMagicBurstName = skillchain.GetMagicBurstForSlot(targetServerId, slotData);
        end

        slotrenderer.DrawSlot({
            x    = slotX,
            y    = slotY,
            size = slotSize,
            windowName = windowKey,
            bind = slotData,
            icon = icon,
            slotBgColor = 0x00000000,
            slotOpacity = 1.0,
            dimFactor   = 1.0,
            animOpacity = contentOp,
            isPressed   = false,
            iconPressScale = 1.0,
            -- MP cost + quantity are intentionally OFF on the double-tap preview regardless of
            -- the user's main-bar settings: the preview is a transient "what's on the other
            -- bar" overlay, not an action-resolution surface, so a player glancing at it just
            -- wants the icon + cooldown to decide if the next press is worth it. Showing MP /
            -- charges duplicates the info on the live bar and crowds an already-small preview.
            -- Cooldowns are kept (recastTimer* + flashCooldownUnder5) — they ARE useful here
            -- because the preview's whole purpose is "should I commit to this bar".
            -- showQuantity respects the per-user opt-in (doubleTapPreviewShowQty).
            showMpCost = false,
            showQuantity = showQty and true or false,
            showLabel = false,
            recastTimerFontSize   = ps.recastTimerFontSize or 11,
            recastTimerFontColor  = ps.recastTimerFontColor or 0xFFFFFFFF,
            flashCooldownUnder5   = ps.flashCooldownUnder5 or false,
            useHHMMCooldownFormat = ps.useHHMMCooldownFormat or false,
            -- Skillchain + Magic Burst highlights. Colors fall back to the live-bar defaults
            -- so the preview matches the main bar without requiring its own settings keys.
            skillchainName  = slotSkillchainName,
            skillchainColor = gConfig.hotbarGlobal.skillchainHighlightColor or 0xFFD4AA44,
            magicBurstName  = slotMagicBurstName,
            magicBurstColor = gConfig.hotbarGlobal.magicBurstHighlightColor or 0xFF44D4FF,
            buttonId              = string.format('##dtprev_%s_%s_%d', windowKey, mode, slotIndex),
            suppressActionOnClick = true,
            forceImGuiIcon        = true,
            drawCornerTextForeground = true,
        });
    end

    if drawList and ps.showButtonIcons and contentOp > 0.05 then
        DrawDiamondCenterIconsImGui('dpad', winX, winY, ps, true, drawList, contentOp);
        DrawDiamondCenterIconsImGui('face', winX, winY, ps, true, drawList, contentOp);
    end
end

-- Draw one double-tap preview window (L2x2 or R2x2 reference).
-- windowKey : unique ImGui window name and persisted-position key.
-- mode      : crossbar storage mode for the 8 slots displayed (e.g. 'L2x2', 'R2x2', 'L2', 'R2').
-- ps        : scaled settings table (from MakePreviewSettings).
-- baseOp    : base opacity (user slider * visibilityOpacity).
-- dimFactor : 0-1 content dim (1.0 = at rest, inactiveSideWhileTriggerDim while any trigger held).
-- settings  : raw crossbar settings (used for doubleTapPreviewLocked move-anchor gating).
local function DrawDoubleTapPreviewWindow(windowKey, mode, ps, baseOp, dimFactor, activeCombo, settings, targetServerId, skillchainEnabled, magicBurstEnabled)
    local slotSize = ps.slotSize or 40;
    local gw, gh = CalculateGroupDimensions(slotSize, ps.slotGapV or 2, ps.slotGapH or 2, ps.diamondSpacing or 16);
    local totalW = gw;
    local totalH = gh;

    local savedPos = gConfig.windowPositions and gConfig.windowPositions[windowKey];
    if savedPos then
        imgui.SetNextWindowPos({savedPos.x, savedPos.y}, ImGuiCond_Always);
    else
        imgui.SetNextWindowPos({200, 200}, ImGuiCond_FirstUseEver);
    end
    imgui.SetNextWindowSize({totalW, totalH}, ImGuiCond_Always);

    -- Preview windows intentionally omit NoBringToFrontOnFocus so they stay layered above the
    -- main crossbar (which has that flag set). NoMove + the move anchor below gives us
    -- explicit positioning control without ImGui drifting the window on focus.
    local flags = bit.bor(
        ImGuiWindowFlags_NoDecoration,
        ImGuiWindowFlags_NoResize,
        ImGuiWindowFlags_NoFocusOnAppearing,
        ImGuiWindowFlags_NoNav,
        ImGuiWindowFlags_NoBackground,
        ImGuiWindowFlags_NoDocking,
        ImGuiWindowFlags_NoMove
    );

    -- Zero window padding so the draw list clip rect matches the window bounds exactly.
    -- Without this the default 8 px padding clips slots at the left/right edges (same fix
    -- that landed for the main crossbar window in the previous smoke-test pass).
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {0, 0});
    local didBegin = imgui.Begin(windowKey, true, flags);
    imgui.PopStyleVar();

    if didBegin then
        local wX, wY = imgui.GetWindowPos();
        if not gConfig.windowPositions then gConfig.windowPositions = {}; end
        if savedPos == nil then
            gConfig.windowPositions[windowKey] = {x = wX, y = wY};
        end

        local dl = imgui.GetWindowDrawList();
        local showQty = settings and settings.doubleTapPreviewShowQty ~= false;
        DrawPreviewSide(wX, wY, windowKey, 'L2', mode, ps, baseOp, dimFactor, dl, activeCombo, targetServerId, skillchainEnabled, magicBurstEnabled, showQty);
    end
    imgui.End();

    -- Move anchor: independent lock so previews can be repositioned without unlocking the
    -- main crossbar (and vice versa).
    local previewLocked = settings and settings.doubleTapPreviewLocked;
    if not previewLocked then
        local pos = gConfig.windowPositions and gConfig.windowPositions[windowKey];
        local anchorX = pos and pos.x or 200;
        local anchorY = pos and pos.y or 200;
        local newX, newY = drawing.DrawMoveAnchor(windowKey, anchorX, anchorY, {
            anchorSide  = 'top',
            windowWidth = totalW,
        });
        if newX ~= nil then
            if not gConfig.windowPositions then gConfig.windowPositions = {}; end
            gConfig.windowPositions[windowKey] = {x = newX, y = newY};
        end
    end
end

-- Main draw function
function M.DrawWindow(settings, moduleSettings)
    if not state.initialized then return; end

    -- Warm playerdata caches even when keyboard hotbars are disabled. Cheap on cache hit
    -- (signature compare against job/level/equip ids), only does the heavy ability/WS scan
    -- when the signature changes. See the require-site comment for the user-visible bug
    -- this prevents (all JA/WS slots reading as unavailable on crossbar-only setups).
    playerdata.RefreshCachedLists(data);

    local gs = (gConfig and gConfig.globalScale) or 1.0;
    local slotSize = (settings.slotSize or 48) * gs;
    local slotGapV = (settings.slotGapV or 4) * gs;
    local slotGapH = (settings.slotGapH or 4) * gs;
    local diamondSpacing = (settings.diamondSpacing or 20) * gs;
    local groupSpacing = (settings.groupSpacing or 40) * gs;

    -- Calculate dimensions using layout functions
    local fullWidth, height, groupWidth, groupHeight = GetCrossbarDimensions(settings);
    local width = fullWidth;

    -- Get current combo mode and pressed slot from controller. Resolved BEFORE the window
    -- size/position calls so the useSharedExpandedBar branch can shrink the window to a single
    -- diamond and re-center it (a chord with useSharedExp on collapses to one 8-slot strip).
    local activeCombo = controller.GetActiveCombo();
    local pressedSlot = controller.GetPressedSlot();

    -- Edit Mode: Override activeCombo to show selected bar for setup
    local isEditMode = settings.editMode;
    if isEditMode then
        local editBar = settings.editModeBar or 'L2';
        activeCombo = editBar;
        pressedSlot = nil;  -- Don't show pressed state in edit mode
    end

    -- Determine which bar set to display based on active combo. expandedSide == 'center' is
    -- the useSharedExpandedBar branch (chord collapses both diamonds into one centered strip).
    local targetLeftMode, targetRightMode, isExpanded, expandedSide = GetDisplayModes(activeCombo, settings);

    -- useSharedExpandedBar special layout: shrink window to one diamond, re-center on screen X,
    -- skip the right group draw + center divider/scope icon (they have no meaning when there's
    -- only one diamond visible). Outside of chord, behaves identically to the standard 2-diamond
    -- layout. exitingChordCenter catches the FIRST frame after the user releases the chord: we
    -- restore the stashed wide-bar X so SaveCrossbarWindowSlotTopPosition doesn't persist the
    -- narrow centered value.
    local hideRightForSharedCenter = (isExpanded and expandedSide == 'center');
    if hideRightForSharedCenter then
        width = groupWidth;
    end
    local exitingChordCenter = state.wasSharedCenterChordLayout and (not hideRightForSharedCenter);

    -- Window flags (dummy window for positioning, like hotbar display.lua)
    -- NoMove when global lock OR crossbar-specific lock is on.
    local crossbarShouldLock = gConfig.lockPositions or (gConfig.crossbarLockMovement == true);
    local windowFlags = GetBaseWindowFlags(crossbarShouldLock);

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

    -- state.windowX / state.windowY track the SLOT GRID origin. ImGui's window must open
    -- CROSSBAR_WINDOW_TOP_DECOR_PAD pixels higher so the decoration above the slots
    -- (L2/R2 triggers, combo text, R1 cpal-anchor pulse) stays inside the window's
    -- content rect and doesn't get clipped. Likewise it opens CROSSBAR_WINDOW_SIDE_PAD
    -- pixels wider on each side so action labels wider than a single slot aren't clipped.
    if anchorDragging then
        -- Use state position directly during drag for immediate response
        imgui.SetNextWindowPos({ state.windowX - CROSSBAR_WINDOW_SIDE_PAD, state.windowY - CROSSBAR_WINDOW_TOP_DECOR_PAD }, ImGuiCond_Always);
    elseif hideRightForSharedCenter then
        -- Shared-center chord: force X to screen-center each frame so the narrow window reads as
        -- the FFXIV-style single 8-slot strip (Y persists from the last wide-bar position).
        local io = imgui.GetIO();
        local screenW = (io and io.DisplaySize and io.DisplaySize.x) or 1920;
        local slotY = storedCrossbarPosY();
        imgui.SetNextWindowPos({ (screenW - width) * 0.5 - CROSSBAR_WINDOW_SIDE_PAD, slotY - CROSSBAR_WINDOW_TOP_DECOR_PAD }, ImGuiCond_Always);
    elseif exitingChordCenter and state.lastWideCrossbarWindowX ~= nil then
        -- First frame after chord release: re-anchor to the wide-bar X we stashed before the
        -- chord, otherwise the user-visible position would briefly snap to the centered narrow X.
        local slotY = storedCrossbarPosY();
        imgui.SetNextWindowPos({ state.lastWideCrossbarWindowX - CROSSBAR_WINDOW_SIDE_PAD, slotY - CROSSBAR_WINDOW_TOP_DECOR_PAD }, ImGuiCond_Always);
    else
        -- Apply saved position (once, slot-top -> window-top offset handled inside) or default
        local hasSaved = gConfig.windowPositions and gConfig.windowPositions[windowName];

        if hasSaved then
            ApplyCrossbarWindowPositionOnce();
        else
            imgui.SetNextWindowPos({ defaultX - CROSSBAR_WINDOW_SIDE_PAD, defaultY - CROSSBAR_WINDOW_TOP_DECOR_PAD }, ImGuiCond_FirstUseEver);
        end
    end

    local bottomPad = GetCrossbarWindowBottomPad(settings);
    imgui.SetNextWindowSize({ width + 2 * CROSSBAR_WINDOW_SIDE_PAD, height + CROSSBAR_WINDOW_TOP_DECOR_PAD + bottomPad }, ImGuiCond_Always);

    -- When "Disable Crossbar While In Menu" is on, controller.lua clears the active combo
    -- while a game menu is open. activeOnly mode would otherwise treat that as "no trigger
    -- held" and fade the bar out completely — we keep it visible but dimmed instead.
    local menuCrossbarDisabled = gamestate.IsMenuOpen() and settings.crossbarDisableInMenu ~= false;

    -- Determine visibility for activeOnly display mode
    local leftVisible, rightVisible, crossbarVisible = GetVisibilityState(activeCombo, settings, isEditMode);
    if menuCrossbarDisabled then
        leftVisible, rightVisible, crossbarVisible = true, true, true;
    end

    -- Handle visibility animation for activeOnly mode
    local visibilityOpacity = 1.0;
    if settings.displayMode == 'activeOnly' and not isEditMode and not menuCrossbarDisabled then
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

    -- Menu-open dim: controller.lua already stops routing input — we additionally dim
    -- everything the crossbar draws so it visually reads as "paused" rather than just
    -- silently unresponsive. visibilityOpacity propagates into every slot via the per-slot
    -- animOpacity param plus the background / border / trigger / divider alpha scales below.
    if menuCrossbarDisabled then
        visibilityOpacity = visibilityOpacity * 0.35;
    end

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
        if expandedSide == 'center' then
            -- useSharedExpandedBar: only the left column is drawn (no right group exists this frame)
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

    -- Get draw list for ImGui-based rendering (behind config when open)
    local drawList = GetUIDrawList();

    -- Get target server ID for skillchain / magic burst prediction (cached for all slots).
    -- Both features key off the same target so a single resolve+cache covers everything; the
    -- per-slot SC and MB calls are no-ops when their respective enable flags are off.
    local targetServerId = nil;
    local skillchainEnabled = gConfig.hotbarGlobal.skillchainHighlightEnabled ~= false;
    local magicBurstEnabled = gConfig.hotbarGlobal.magicBurstHighlightEnabled ~= false;
    if skillchainEnabled or magicBurstEnabled then
        local mainTargetIdx = targetLib.GetTargets();
        if mainTargetIdx and mainTargetIdx ~= 0 then
            local targetEntity = GetEntity(mainTargetIdx);
            if targetEntity then
                targetServerId = targetEntity.ServerId;
            end
        end
    end

    -- Zero out WindowPadding so the leftmost and rightmost diamond slots (which sit flush
    -- against the window's content rect) aren't clipped by ImGui's default 8px padding.
    -- Without this the left/right slots of each diamond render partially off-window and
    -- their button hitboxes get pushed inward (slot interactions become unreliable).
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    -- Begin ImGui window - ALL slot rendering happens inside to enable interactions
    if imgui.Begin('Crossbar', true, windowFlags) then
        -- Save SLOT-TOP position if moved (decor-pad-aware; profile coordinate stays the
        -- slot grid top so the saved value is meaningful even if decor pad changes later).
        -- During the shared-center chord the X is force-centered each frame, so we MUST NOT
        -- let SaveCrossbarWindowSlotTopPosition persist that narrow centered X — only sync Y.
        if hideRightForSharedCenter then
            if gConfig.windowPositions and gConfig.windowPositions[windowName] then
                local wx, wy = imgui.GetWindowPos();
                local s = gConfig.windowPositions[windowName];
                local slotTopX = wx + CROSSBAR_WINDOW_SIDE_PAD;  -- save slot grid X
                local slotTopY = wy + CROSSBAR_WINDOW_TOP_DECOR_PAD;
                if s.y ~= slotTopY then
                    s.y = slotTopY;
                end
                -- Track the centered window X as slot grid X for lastWideCrossbarWindowX restore
                if s.x ~= slotTopX then
                    s.x = slotTopX;
                end
            end
        else
            SaveCrossbarWindowSlotTopPosition();
        end
        windowPosX, windowPosY = imgui.GetWindowPos();

        -- Update stored position. state.windowX = slot grid left (window left + SIDE_PAD);
        -- state.windowY = slot grid top (window top + TOP_PAD). All layout code below
        -- references state.windowX/Y as the slot origin.
        state.windowX = windowPosX + CROSSBAR_WINDOW_SIDE_PAD;
        state.windowY = windowPosY + CROSSBAR_WINDOW_TOP_DECOR_PAD;

        -- Stash the wide-bar SLOT GRID X so that when the user releases the chord we can
        -- restore it (state.windowX is already slot grid X at this point).
        if not hideRightForSharedCenter then
            state.lastWideCrossbarWindowX = state.windowX;
        end
        -- Remember the layout for the NEXT frame so exitingChordCenter (above) can detect
        -- the chord-release transition and re-anchor X.
        state.wasSharedCenterChordLayout = hideRightForSharedCenter;

        -- Recalculate group positions with updated window position
        leftGroupX = state.windowX;
        leftGroupY = state.windowY;
        rightGroupX = state.windowX + groupWidth + groupSpacing;
        rightGroupY = state.windowY;

        -- Draw bar sets based on animation state and display mode
        -- NOTE: DrawSlot calls must be inside imgui.Begin/End for interactions to work
        local isActiveOnlyMode = settings.displayMode == 'activeOnly' and not isEditMode and not menuCrossbarDisabled;

        -- Draw window background FIRST so it sits beneath all slot content on the draw list.
        -- Apply visibility opacity whenever the bar is faded (activeOnly or menu dim).
        do
            local bgOpacity = settings.backgroundOpacity;
            local borderOpacity = settings.borderOpacity;
            if visibilityOpacity < 1.0 then
                bgOpacity = bgOpacity * visibilityOpacity;
                borderOpacity = borderOpacity * visibilityOpacity;
            end
            windowBg.Draw(GetUIDrawList(), state.windowX, state.windowY, width, height, {
                theme = settings.backgroundTheme,
                bgScale = settings.bgScale,
                borderScale = settings.borderScale,
                bgOpacity = bgOpacity,
                borderOpacity = borderOpacity,
                bgColor = settings.bgColor,
                borderColor = settings.borderColor,
            });
        end

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

            -- Draw LEFT side (skip in activeOnly mode if not visible)
            if not isActiveOnlyMode or leftVisible then
                if state.animation.leftChanged then
                    -- Left side changed - animate it
                    if outOpacity > 0.01 then
                        DrawLeftSide(state.animation.fromLeftMode, leftGroupX, leftGroupY, slotSize, settings,
                            fromLeftActive, pressedSlot, false, outOpacity, drawList, outYOffset, targetServerId, skillchainEnabled, activeCombo, magicBurstEnabled);
                    end
                    if inOpacity > 0.01 then
                        DrawLeftSide(state.animation.toLeftMode, leftGroupX, leftGroupY, slotSize, settings,
                            leftActive, pressedSlot, leftShowPressed, inOpacity, drawList, inYOffset, targetServerId, skillchainEnabled, activeCombo, magicBurstEnabled);
                    end
                else
                    -- Left side didn't change - draw at full opacity (with visibility fade)
                    DrawLeftSide(state.animation.toLeftMode, leftGroupX, leftGroupY, slotSize, settings,
                        leftActive, pressedSlot, leftShowPressed, visibilityOpacity, drawList, 0, targetServerId, skillchainEnabled, activeCombo, magicBurstEnabled);
                end
            end

            -- Draw RIGHT side (skip in activeOnly mode if not visible, or whenever the chord
            -- collapsed both groups into a single centered strip — there is no right group).
            if (not hideRightForSharedCenter) and (not isActiveOnlyMode or rightVisible) then
                if state.animation.rightChanged then
                    -- Right side changed - animate it
                    if outOpacity > 0.01 then
                        DrawRightSide(state.animation.fromRightMode, rightGroupX, rightGroupY, slotSize, settings,
                            fromRightActive, pressedSlot, false, outOpacity, drawList, outYOffset, targetServerId, skillchainEnabled, activeCombo, magicBurstEnabled);
                    end
                    if inOpacity > 0.01 then
                        DrawRightSide(state.animation.toRightMode, rightGroupX, rightGroupY, slotSize, settings,
                            rightActive, pressedSlot, rightShowPressed, inOpacity, drawList, inYOffset, targetServerId, skillchainEnabled, activeCombo, magicBurstEnabled);
                    end
                else
                    -- Right side didn't change - draw at full opacity (with visibility fade)
                    DrawRightSide(state.animation.toRightMode, rightGroupX, rightGroupY, slotSize, settings,
                        rightActive, pressedSlot, rightShowPressed, visibilityOpacity, drawList, 0, targetServerId, skillchainEnabled, activeCombo, magicBurstEnabled);
                end
            end
        else
            -- No bar transition animation
            if isActiveOnlyMode then
                -- ActiveOnly mode: draw only visible sides with visibility fade
                if leftVisible then
                    DrawLeftSide(state.currentLeftMode, leftGroupX, leftGroupY, slotSize, settings,
                        leftActive, pressedSlot, leftShowPressed, visibilityOpacity, drawList, 0, targetServerId, skillchainEnabled, activeCombo, magicBurstEnabled);
                end
                if (not hideRightForSharedCenter) and rightVisible then
                    DrawRightSide(state.currentRightMode, rightGroupX, rightGroupY, slotSize, settings,
                        rightActive, pressedSlot, rightShowPressed, visibilityOpacity, drawList, 0, targetServerId, skillchainEnabled, activeCombo, magicBurstEnabled);
                end
            elseif hideRightForSharedCenter then
                -- Shared-center chord: render only the (now-Shared) left column as one centered strip.
                DrawLeftSide(state.currentLeftMode, leftGroupX, leftGroupY, slotSize, settings,
                    leftActive, pressedSlot, leftShowPressed, visibilityOpacity, drawList, 0, targetServerId, skillchainEnabled, activeCombo, magicBurstEnabled);
            else
                -- Normal mode: draw both sides (menu dim flows through visibilityOpacity)
                DrawBarSet(
                    state.currentLeftMode, state.currentRightMode,
                    leftGroupX, leftGroupY, rightGroupX, rightGroupY,
                    slotSize, settings,
                    leftActive, rightActive,
                    pressedSlot, leftShowPressed, rightShowPressed,
                    visibilityOpacity, drawList, 0, targetServerId, skillchainEnabled, activeCombo, magicBurstEnabled
                );
            end
        end

        imgui.End();
    end
    -- Pop the WindowPadding style we pushed before Begin. Has to be unconditional (must match
    -- the push even when Begin returns false / window is collapsed).
    imgui.PopStyleVar();

    -- Draw move anchor (only visible when config is open).
    -- Uses the crossbar-specific lock so Hotbar's lock toggle doesn't accidentally freeze
    -- the crossbar (fixes the issue where Lock Crossbar was tied to Hotbar's setting).
    local crossbarLocked = gConfig and gConfig.crossbarLockMovement;
    if not crossbarLocked then
        -- Use same window name as ImGui window so positions are shared
        local anchorNewX, anchorNewY = drawing.DrawMoveAnchor('Crossbar', state.windowX, state.windowY);
        if anchorNewX ~= nil then
            state.windowX = anchorNewX;
            state.windowY = anchorNewY;
            
            -- Update config immediately so next frame's positioning logic picks it up
            if not gConfig.windowPositions then gConfig.windowPositions = {}; end
            gConfig.windowPositions['Crossbar'] = { x = anchorNewX, y = anchorNewY };
        end
    end

    -- Determine if we should show center elements (hidden in activeOnly mode unless menu-dimmed)
    local isActiveOnlyMode = settings.displayMode == 'activeOnly' and not isEditMode;
    local showCenterElements = not isActiveOnlyMode or menuCrossbarDisabled;

    -- Center decor (divider line, scope icon, combo text, palette name): all hidden in
    -- activeOnly mode since that layout collapses to a single side and the divider has no meaning.
    -- Shared-center chord layout: centerX is the middle of the (now single-diamond) window so the
    -- scope icon / combo text / palette name still sit over the visible bar. The DIVIDER itself
    -- is suppressed in chord since there's no longer a left/right split to divide.
    local centerX;
    if hideRightForSharedCenter then
        centerX = state.windowX + width * 0.5;
    else
        centerX = state.windowX + groupWidth + (groupSpacing / 2);
    end
    local dividerTopY = state.windowY + 10;

    if settings.showDivider and drawList and showCenterElements and (not hideRightForSharedCenter) then
        local dividerY2 = state.windowY + height - 10;
        drawList:AddLine(
            { centerX, dividerTopY },
            { centerX, dividerY2 },
            imgui.GetColorU32({ 1, 1, 1, 0.3 }),
            2
        );
    end

    -- Palette scope icon (infinity for Global / job icon for job-scoped) — drawn above the
    -- divider's top endpoint. Same drawList as the divider so z-order is consistent.
    if showCenterElements and drawList then
        DrawPaletteScopeIconAboveDivider(centerX, dividerTopY, settings, drawList);
    end

    -- Draw combo text in center for complex combos (hidden in activeOnly mode)
    local topY = state.windowY - 4;  -- Above the window
    if showCenterElements then
        DrawComboText(activeCombo, centerX, topY, settings);
    end

    -- Draw palette name below the crossbar
    local bottomY = state.windowY + height + 4;
    if showCenterElements then
        DrawPaletteName(centerX, bottomY, settings);
    end

    -- Draw L2/R2 trigger icons above the groups (hidden in activeOnly mode). The shared-center
    -- chord uses a different glyph (L2 + R2 chord centred on the single visible diamond) since
    -- there's no left-vs-right group to position labels against.
    if drawList and showCenterElements then
        if hideRightForSharedCenter then
            DrawTriggerIconsSharedExpandedCenter(activeCombo, leftGroupX, leftGroupY, groupWidth, settings, drawList);
        else
            DrawTriggerIcons(activeCombo, leftGroupX, rightGroupX, leftGroupY, groupWidth, settings, drawList);
        end
    end

    -- Draw palette modifier indicator (refresh icon when modifier key is held)
    if state.windowX and actions.IsPaletteModifierHeld() then
        local refreshTexture = textures:Get('ui_refresh');
        if refreshTexture and refreshTexture.image then
            local iconSize = 18;
            -- Position centered above the crossbar
            local iconX = centerX - (iconSize / 2);
            local iconY = state.windowY - 24;
            local fgDrawList = GetUIDrawList();

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

    -- Double-tap preview windows. Drawn AFTER the main crossbar so they end up in
    -- separate ImGui windows with their own draw list / position, layered above the main
    -- bar. Gated on both `enableDoubleTap` (the L2x2/R2x2 modes have to be enabled at all)
    -- and `showDoubleTapPreview` (the per-feature visibility toggle). When the active combo
    -- IS the matching double-tap, the preview swaps to the BASE L2/R2 slots as a reference
    -- — the main bar is already showing the double-tap content.
    if settings.enableDoubleTap and settings.showDoubleTapPreview then
        local scale  = settings.doubleTapPreviewScale  or 0.60;
        local baseOp = (settings.doubleTapPreviewOpacity or 1.0) * visibilityOpacity;
        -- Skip the preview render path entirely when nothing would be visible (menu dim or
        -- activeOnly hide). Saves the 16-slot DrawSlot + ImGui begin/end overhead per frame.
        if baseOp <= 0.02 then return; end
        local dimFact = settings.inactiveSideWhileTriggerDim;
        if dimFact == nil then dimFact = 0.15; end
        local ps = MakePreviewSettings(settings, scale);

        local isL2xActive = (activeCombo == COMBO_MODES.L2_DOUBLE);
        local isR2xActive = (activeCombo == COMBO_MODES.R2_DOUBLE);
        local anyTriggerHeld = (activeCombo ~= COMBO_MODES.NONE);
        local previewDim = anyTriggerHeld and dimFact or 1.0;

        DrawDoubleTapPreviewWindow(
            'CrossbarPreviewL2x2',
            isL2xActive and 'L2' or 'L2x2',
            ps, baseOp, previewDim, activeCombo, settings,
            targetServerId, skillchainEnabled, magicBurstEnabled
        );
        DrawDoubleTapPreviewWindow(
            'CrossbarPreviewR2x2',
            isR2xActive and 'R2' or 'R2x2',
            ps, baseOp, previewDim, activeCombo, settings,
            targetServerId, skillchainEnabled, magicBurstEnabled
        );
    end
end

-- ============================================
-- Visibility
-- ============================================

function M.SetHidden(hidden)
end

-- ============================================
-- Visual Updates
-- ============================================

function M.UpdateVisuals(settings, moduleSettings)
    if not state.initialized then return; end

    -- Reset imtext so it reloads fonts on next draw
    imtext.Reset();

    -- Clear slot cache so text re-renders with new settings
    slotrenderer.ClearAllCache();

    -- Drop cached abbreviation widths (depend on the active font) so they re-measure.
    ClearCrossbarIconCache();
end

-- ============================================
-- Cleanup
-- ============================================

function M.Cleanup()
    if not state.initialized then return; end

    -- Clear icon cache
    ClearCrossbarIconCache();

    -- Clear pre-created closures so they're recreated on reinit
    cbInteraction = {};

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
    -- Mirror the wipe to actions.lua's negative-result cache so "no icon" decisions
    -- pinned from a previous state don't survive into the new job/palette context.
    if actions and actions.ClearNoIconCache then
        actions.ClearNoIconCache();
    end
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
    if gConfig.windowPositions then
        gConfig.windowPositions['Crossbar'] = { x = defaultX, y = defaultY };
    end
    if gConfig.appliedPositions then
        gConfig.appliedPositions['Crossbar'] = nil;
    end
end

-- ============================================
-- Edit Full Palette (called from config/palettemanager.lua's ImGui window)
-- ============================================
-- The editor draws a static representation of a crossbar row using the SAME DrawSlot path
-- as the live HUD, so layout (diamond geometry, slot size, label position, MP/quantity)
-- always matches what the user actually plays with. The editor differs from the HUD in:
--   * Slot data is read from the draft layer (data.GetDraftSlotData) not the live binding.
--   * MP / quantity / cooldown text are suppressed (showMpCost=false, showQuantity=false).
--   * The action name renders ON the slot (labelForeground + editorMinimalView).
--   * Drop zones use 'paled_*' IDs with dropPriority=10 so they win against the HUD zones
--     underneath when the editor window overlaps the live crossbar.
--   * Optional editorClipRect culls slots scrolled off the editor panel.
-- These are all set by the local DrawSlot wrapper above; the public functions here just
-- iterate the 8 slots of each diamond and call DrawSlot once per slot.

-- Shared palette-editor slot row. Either or both of modeLeft (L2 group) and modeRight
-- (R2 group) may be set; pass nil on a side to omit it (Pets tab filter renders single-sided rows).
local function DrawPaletteEditorRow(screenOriginX, screenOriginY, settings, modeLeft, modeRight, clipMinX, clipMinY, clipMaxX, clipMaxY)
    if not state.initialized then return; end
    if not modeLeft and not modeRight then return; end
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

-- Trigger glyphs raised above the editor's slot cluster. glyphMode:
--   'primary'     — L2 | R2 (one glyph per side, gap between d-pad and face).
--   'doubleTap'   — L2 + "x2", R2 + "x2".
--   'chordCombo'  — Left: L2+R2, Right: R2+L2 (with text "+" between).
--   'sharedChord' — Single L2+R2 glyph centred over the shared diamond.
-- Optional sides = { l=bool, r=bool } (default both true) — used by Pets-tab single-sided rows.
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
    local chordTight = math.max(0.5, 0.65 * scale);
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
        if sl then drawComboAtCenter(l2cx, 'L2', 'R2'); end
        if sr then drawComboAtCenter(r2cx, 'R2', 'L2'); end
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
    if sl then drawImage('L2', l2cx - iw * 0.5, cy - ih * 0.5); end
    if sr then drawImage('R2', r2cx - iw * 0.5, cy - ih * 0.5); end
end

-- Convenience wrapper used by the Shared (chord-fallback) row.
function M.DrawPaletteEditorSharedChordTriggerGlyphs(screenOriginX, screenOriginY, settings)
    M.DrawPaletteEditorL2R2TriggerGlyphs(screenOriginX, screenOriginY, settings, 'sharedChord');
end

-- Exposed so palettemanager.lua can size the editor row to match the live HUD dimensions
-- without duplicating the math (slot size, gaps, diamond spacing, etc. all flow through here).
function M.GetEditorCrossbarRowDimensions(settings)
    return GetCrossbarDimensions(settings);
end

-- Legacy GDI hook (kept as a no-op for API compatibility with `palettemanager.lua`).
-- Pre-1.8.0 this hid the persistent D3D/GDI primitives backing the editor's slot row when
-- the editor window was not currently drawing. Under 1.8.0's imtext architecture there are
-- no persistent objects to hide — un-emitted draw calls simply don't render. The function
-- is retained so callers don't break and so the contract is documented; consider removing
-- once palettemanager.lua's six call sites are updated.
function M.HidePaletteEditorPrimitives()
end

return M;
