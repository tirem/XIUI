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

local M = {};

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

    -- Initial position (ImGui will handle persistence via imgui.ini)
    local x, y = GetDefaultPosition(settings);
    state.windowX = x;
    state.windowY = y;

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

            -- Timer font for cooldowns (centered, with outline)
            local timerFontSettings = moduleSettings and deep_copy_table(moduleSettings.label_font_settings) or {};
            timerFontSettings.font_height = 11;
            timerFontSettings.font_alignment = 1;  -- Center
            timerFontSettings.font_color = 0xFFFFFFFF;
            timerFontSettings.outline_color = 0xFF000000;
            timerFontSettings.outline_width = 2;
            state.timerFonts[comboMode][slotIndex] = FontManager.create(timerFontSettings);

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
local function DrawSlot(comboMode, slotIndex, x, y, slotSize, settings, isActive, isPressed, animOpacity, yOffset)
    animOpacity = animOpacity or 1.0;
    yOffset = yOffset or 0;

    -- Apply Y offset for animation
    local drawY = y + yOffset;

    -- Get slot data
    local slotData = data.GetCrossbarSlotData(comboMode, slotIndex);

    -- Get icon for this action
    local icon = nil;
    if slotData and slotData.actionType then
        icon = actions.GetBindIcon(slotData);
    end

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
        end,
        showTooltip = true,
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
    local controllerTheme = settings.controllerTheme or 'PlayStation';

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
        iconConfig = CENTER_ICON_CONFIG.face[controllerTheme] or CENTER_ICON_CONFIG.face.PlayStation;
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
    local scale = settings.triggerIconScale or 1.0;
    local iconWidth = 49 * scale;
    local iconHeight = 28 * scale;
    local iconY = groupY - (iconHeight * 0.5); -- Position overlapping top edge

    -- L2 icon position (centered above L2 group)
    local l2IconX = l2GroupX + (groupWidth / 2) - (iconWidth / 2);

    -- R2 icon position (centered above R2 group)
    local r2IconX = r2GroupX + (groupWidth / 2) - (iconWidth / 2);

    -- Determine active state for each trigger
    local l2Active = activeCombo == COMBO_MODES.L2 or activeCombo == COMBO_MODES.L2_THEN_R2 or activeCombo == COMBO_MODES.R2_THEN_L2 or activeCombo == COMBO_MODES.L2_DOUBLE;
    local r2Active = activeCombo == COMBO_MODES.R2 or activeCombo == COMBO_MODES.L2_THEN_R2 or activeCombo == COMBO_MODES.R2_THEN_L2 or activeCombo == COMBO_MODES.R2_DOUBLE;

    -- When no combo active, show both dimmed
    if activeCombo == COMBO_MODES.NONE then
        l2Active = false;
        r2Active = false;
    end

    -- Draw L2 icon
    local l2Texture = textures:GetControllerIcon('L2');
    if l2Texture and l2Texture.image then
        local iconPtr = tonumber(ffi.cast("uint32_t", l2Texture.image));
        if iconPtr then
            local tintColor = l2Active and 0xFFFFFFFF or 0x88FFFFFF;
            drawList:AddImage(
                iconPtr,
                {l2IconX, iconY},
                {l2IconX + iconWidth, iconY + iconHeight},
                {0, 0}, {1, 1},
                tintColor
            );
        end
    end

    -- Draw R2 icon
    local r2Texture = textures:GetControllerIcon('R2');
    if r2Texture and r2Texture.image then
        local iconPtr = tonumber(ffi.cast("uint32_t", r2Texture.image));
        if iconPtr then
            local tintColor = r2Active and 0xFFFFFFFF or 0x88FFFFFF;
            drawList:AddImage(
                iconPtr,
                {r2IconX, iconY},
                {r2IconX + iconWidth, iconY + iconHeight},
                {0, 0}, {1, 1},
                tintColor
            );
        end
    end
end

-- Draw combo text in center for complex combos (L2R2, R2L2, L2x2, R2x2)
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
        comboText = 'L2+R2';
    elseif activeCombo == COMBO_MODES.R2_THEN_L2 then
        comboText = 'R2+L2';
    elseif activeCombo == COMBO_MODES.L2_DOUBLE then
        comboText = 'L2x2';
    elseif activeCombo == COMBO_MODES.R2_DOUBLE then
        comboText = 'R2x2';
    end

    -- Only show for complex combos
    if not comboText then
        if state.comboTextFont then
            state.comboTextFont:set_visible(false);
        end
        return;
    end

    -- Get font size from settings
    local fontSize = settings.comboTextFontSize or 10;

    -- Update and show GDI font for text (centered)
    if state.comboTextFont then
        state.comboTextFont:set_font_height(fontSize);
        state.comboTextFont:set_text(comboText);
        state.comboTextFont:set_position_x(centerX);
        state.comboTextFont:set_position_y(topY);
        state.comboTextFont:set_visible(true);
    end
end

-- Helper to draw just the left side
local function DrawLeftSide(mode, groupX, groupY, slotSize, settings, isActive, pressedSlot, showPressed, animOpacity, drawList, yOffset)
    animOpacity = animOpacity or 1.0;
    yOffset = yOffset or 0;

    -- Draw left side slots
    for slotIndex = 1, SLOTS_PER_SIDE do
        local slotX, slotY = GetSlotPositionInWindow('L2', slotIndex, state.windowX, state.windowY, settings);
        local isPressed = showPressed and pressedSlot == slotIndex;
        DrawSlot(mode, slotIndex, slotX, slotY, slotSize, settings, isActive, isPressed, animOpacity, yOffset);
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
local function DrawRightSide(mode, groupX, groupY, slotSize, settings, isActive, pressedSlot, showPressed, animOpacity, drawList, yOffset)
    animOpacity = animOpacity or 1.0;
    yOffset = yOffset or 0;

    -- Draw right side slots
    for slotIndex = 1, SLOTS_PER_SIDE do
        local slotX, slotY = GetSlotPositionInWindow('R2', slotIndex, state.windowX, state.windowY, settings);
        local isPressed = showPressed and pressedSlot == slotIndex;
        DrawSlot(mode, slotIndex, slotX, slotY, slotSize, settings, isActive, isPressed, animOpacity, yOffset);
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
                          leftShowPressed, rightShowPressed, animOpacity, drawList, yOffset)
    DrawLeftSide(leftMode, leftGroupX, leftGroupY, slotSize, settings, leftActive, pressedSlot, leftShowPressed, animOpacity, drawList, yOffset);
    DrawRightSide(rightMode, rightGroupX, rightGroupY, slotSize, settings, rightActive, pressedSlot, rightShowPressed, animOpacity, drawList, yOffset);
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

    -- Set initial position (FirstUseEver means only set if window hasn't been positioned yet)
    local defaultX, defaultY = GetDefaultPosition(settings);
    imgui.SetNextWindowPos({defaultX, defaultY}, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowSize({width, height}, ImGuiCond_Always);

    -- Get current combo mode and pressed slot from controller
    local activeCombo = controller.GetActiveCombo();
    local pressedSlot = controller.GetPressedSlot();

    -- Determine which bar set to display based on active combo
    local targetLeftMode, targetRightMode, isExpanded, expandedSide = GetDisplayModes(activeCombo);

    -- Check if bar set changed and start animation
    if targetLeftMode ~= state.currentLeftMode or targetRightMode ~= state.currentRightMode then
        if not state.animation.active then
            StartBarTransition(state.currentLeftMode, state.currentRightMode, targetLeftMode, targetRightMode);
        end
    end

    -- Update animation progress
    UpdateAnimation();

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

    -- Hide all slot primitives first (we'll show the ones we need)
    local allModes = { 'L2', 'R2', 'L2R2', 'R2L2', 'L2x2', 'R2x2' };
    for _, mode in ipairs(allModes) do
        for slotIndex = 1, SLOTS_PER_SIDE do
            local slotPrim = state.slotPrims[mode] and state.slotPrims[mode][slotIndex];
            if slotPrim then slotPrim.visible = false; end
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
                        fromLeftActive, pressedSlot, false, outOpacity, drawList, outYOffset);
                end
                if inOpacity > 0.01 then
                    DrawLeftSide(state.animation.toLeftMode, leftGroupX, leftGroupY, slotSize, settings,
                        leftActive, pressedSlot, leftShowPressed, inOpacity, drawList, inYOffset);
                end
            else
                -- Left side didn't change - draw at full opacity
                DrawLeftSide(state.animation.toLeftMode, leftGroupX, leftGroupY, slotSize, settings,
                    leftActive, pressedSlot, leftShowPressed, 1.0, drawList, 0);
            end

            -- Draw RIGHT side
            if state.animation.rightChanged then
                -- Right side changed - animate it
                if outOpacity > 0.01 then
                    DrawRightSide(state.animation.fromRightMode, rightGroupX, rightGroupY, slotSize, settings,
                        fromRightActive, pressedSlot, false, outOpacity, drawList, outYOffset);
                end
                if inOpacity > 0.01 then
                    DrawRightSide(state.animation.toRightMode, rightGroupX, rightGroupY, slotSize, settings,
                        rightActive, pressedSlot, rightShowPressed, inOpacity, drawList, inYOffset);
                end
            else
                -- Right side didn't change - draw at full opacity
                DrawRightSide(state.animation.toRightMode, rightGroupX, rightGroupY, slotSize, settings,
                    rightActive, pressedSlot, rightShowPressed, 1.0, drawList, 0);
            end
        else
            -- No animation, draw current bar set at full opacity with no offset
            DrawBarSet(
                state.currentLeftMode, state.currentRightMode,
                leftGroupX, leftGroupY, rightGroupX, rightGroupY,
                slotSize, settings,
                leftActive, rightActive,
                pressedSlot, leftShowPressed, rightShowPressed,
                1.0, drawList, 0
            );
        end

        imgui.End();
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

    -- Get player job for slot lookup
    local player = GetPlayerSafe();
    if not player then return; end

    local jobId = player:GetMainJob();
    if not jobId or jobId == 0 then return; end

    -- Get slot action from settings
    local slotActions = gConfig and gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.slotActions;
    if not slotActions then return; end

    local jobActions = slotActions[jobId];
    if not jobActions then return; end

    local modeActions = jobActions[comboMode];
    if not modeActions then return; end

    local slotAction = modeActions[slotIndex];
    if not slotAction then return; end

    -- Execute the action via the actions module
    if slotAction.actionType and slotAction.action then
        actions.ExecuteAction(slotAction);
    end
end

return M;
