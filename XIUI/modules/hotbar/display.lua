--[[
* XIUI hotbar - Display Module
* Renders 6 independent hotbar windows with primitives and GDI fonts
]]--

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local windowBg = require('libs.windowbackground');

local data = require('modules.hotbar.data');
local actions = require('modules.hotbar.actions');
local textures = require('modules.hotbar.textures');
local macropalette = require('modules.hotbar.macropalette');
local dragdrop = require('libs.dragdrop');
local recast = require('modules.hotbar.recast');
local slotrenderer = require('modules.hotbar.slotrenderer');
local hotbarConfig = require('config.hotbar');

local M = {};

-- ============================================
-- Constants
-- ============================================

local KEYBIND_OFFSET_X = 2;
local KEYBIND_OFFSET_Y = 2;

-- ============================================
-- State
-- ============================================

-- Loaded theme tracking
local loadedBgTheme = nil;

-- Textures initialized flag
local texturesInitialized = false;

-- ============================================
-- Helper Functions
-- ============================================

-- Get default position for a bar
local function GetDefaultBarPosition(barIndex)
    local screenWidth = imgui.GetIO().DisplaySize.x or 1920;
    local screenHeight = imgui.GetIO().DisplaySize.y or 1080;

    -- Use per-bar settings for accurate dimensions
    local barSettings = data.GetBarSettings(barIndex);
    local slotSize = barSettings.slotSize or 32;
    local slotGap = barSettings.slotXPadding or data.BUTTON_GAP;
    local padding = data.PADDING;
    local layout = data.GetBarLayout(barIndex);

    -- All bars: stack vertically, centered horizontally
    -- Bar 1 at the bottom, bar 2 above it, etc.
    local barWidth = (slotSize * layout.columns) + (slotGap * (layout.columns - 1)) + (padding * 2);
    local barHeight = slotSize + (padding * 2);
    local x = (screenWidth - barWidth) / 2;
    local y = screenHeight - 120 - ((barIndex - 1) * (barHeight + 4));
    return x, y;
end

-- Calculate bar dimensions using per-bar settings
local function GetBarDimensions(barIndex)
    local barSettings = data.GetBarSettings(barIndex);
    local slotSize = barSettings.slotSize or 32;
    -- Use per-bar slot padding settings
    local slotGap = barSettings.slotXPadding or data.BUTTON_GAP;
    local padding = data.PADDING;
    local rowGap = barSettings.slotYPadding or data.ROW_GAP;

    local layout = data.GetBarLayout(barIndex);

    -- Calculate dimensions based on rows and columns
    local width = (slotSize * layout.columns) + (slotGap * (layout.columns - 1)) + (padding * 2);
    local height = (slotSize * layout.rows) + (rowGap * (layout.rows - 1)) + (padding * 2);

    return width, height, slotSize, slotGap, rowGap, layout;
end

-- Cached asset path
local assetsPath = nil;

local function GetAssetsPath()
    if not assetsPath then
        assetsPath = string.format('%saddons\\XIUI\\assets\\hotbar\\', AshitaCore:GetInstallPath());
    end
    return assetsPath;
end

-- Draw a single hotbar slot using shared renderer
local function DrawSlot(barIndex, slotIndex, x, y, buttonSize, bind, barSettings)
    -- Gather resources for this slot
    local resources = {
        slotPrim = data.slotPrims[barIndex] and data.slotPrims[barIndex][slotIndex],
        iconPrim = data.iconPrims[barIndex] and data.iconPrims[barIndex][slotIndex],
        timerFont = data.timerFonts[barIndex] and data.timerFonts[barIndex][slotIndex],
        keybindFont = data.keybindFonts[barIndex] and data.keybindFonts[barIndex][slotIndex],
        labelFont = data.labelFonts[barIndex] and data.labelFonts[barIndex][slotIndex],
    };

    -- Get icon for this action
    local icon = nil;
    local labelText = '';
    if bind then
        labelText = bind.displayName or bind.action or '';
        _, icon = actions.BuildCommand(bind);
    end

    -- Get per-bar display settings
    local showActionLabels = barSettings and barSettings.showActionLabels or false;
    local showSlotFrame = barSettings and barSettings.showSlotFrame or false;

    -- Apply keybind font settings before rendering
    if resources.keybindFont then
        local keybindSize = barSettings and barSettings.keybindFontSize or 8;
        local keybindColor = barSettings and barSettings.keybindFontColor or 0xFFFFFFFF;
        resources.keybindFont:set_font_height(keybindSize);
        resources.keybindFont:set_font_color(keybindColor);
    end

    -- Hide cooldown overlay primitive (not used - we tint the icon instead)
    local cooldownPrim = data.cooldownPrims[barIndex] and data.cooldownPrims[barIndex][slotIndex];
    if cooldownPrim then cooldownPrim.visible = false; end

    -- Check if this slot is currently pressed (keyboard)
    local pressedHotbar = actions.GetPressedHotbar();
    local pressedSlot = actions.GetPressedSlot();
    local isPressed = (pressedHotbar == barIndex and pressedSlot == slotIndex);

    -- Render slot using shared renderer (handles ALL rendering and interactions)
    local result = slotrenderer.DrawSlot(resources, {
        -- Position/Size
        x = x,
        y = y,
        size = buttonSize,

        -- Action Data
        bind = bind,
        icon = icon,

        -- Visual Settings
        slotBgColor = barSettings and barSettings.slotBackgroundColor or 0xFFFFFFFF,
        keybindText = data.GetKeybindDisplay(barIndex, slotIndex),
        keybindFontSize = barSettings and barSettings.keybindFontSize or 8,
        keybindFontColor = barSettings and barSettings.keybindFontColor or 0xFFFFFFFF,
        showLabel = showActionLabels,
        labelText = labelText,
        labelOffsetX = barSettings and barSettings.actionLabelOffsetX or 0,
        labelOffsetY = (barSettings and barSettings.actionLabelOffsetY or 0) + data.LABEL_GAP,
        showFrame = showSlotFrame,
        isPressed = isPressed,

        -- Interaction Config
        buttonId = string.format('##hotbarslot_%d_%d', barIndex, slotIndex),
        dropZoneId = string.format('hotbar_%d_%d', barIndex, slotIndex),
        dropAccepts = {'macro', 'slot'},
        onDrop = function(payload)
            macropalette.HandleDropOnSlot(payload, barIndex, slotIndex);
        end,
        dragType = 'slot',
        getDragData = function()
            macropalette.StartDragSlot(barIndex, slotIndex, bind);
            return nil;  -- StartDragSlot handles the drag itself
        end,
        onRightClick = function()
            macropalette.ClearSlot(barIndex, slotIndex);
        end,
        showTooltip = true,
    });

    return result.isHovered;
end

-- Draw a single hotbar window
local function DrawBarWindow(barIndex, settings)
    -- Get per-bar settings
    local barSettings = data.GetBarSettings(barIndex);

    -- Check if bar is enabled
    if not barSettings.enabled then
        -- Hide bar resources
        data.SetBarFontsVisible(barIndex, false);
        if data.bgHandles[barIndex] then
            windowBg.hide(data.bgHandles[barIndex]);
        end
        -- Hide unused slot, icon, and cooldown primitives
        for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
            if data.slotPrims[barIndex] and data.slotPrims[barIndex][slotIndex] then
                data.slotPrims[barIndex][slotIndex].visible = false;
            end
            if data.iconPrims[barIndex] and data.iconPrims[barIndex][slotIndex] then
                data.iconPrims[barIndex][slotIndex].visible = false;
            end
            if data.cooldownPrims[barIndex] and data.cooldownPrims[barIndex][slotIndex] then
                data.cooldownPrims[barIndex][slotIndex].visible = false;
            end
        end
        return;
    end

    -- Get saved position or default
    local savedPos = gConfig.hotbarBarPositions and gConfig.hotbarBarPositions[barIndex];
    local defaultX, defaultY = GetDefaultBarPosition(barIndex);
    local posX = savedPos and savedPos.x or defaultX;
    local posY = savedPos and savedPos.y or defaultY;

    -- Safety check: if position is at or near (0,0), use default instead
    -- This prevents bars from being stuck in the corner due to bad saved positions
    if posX < 10 and posY < 10 then
        posX = defaultX;
        posY = defaultY;
        -- Clear the bad saved position
        if gConfig.hotbarBarPositions and gConfig.hotbarBarPositions[barIndex] then
            gConfig.hotbarBarPositions[barIndex] = nil;
        end
    end

    -- Get dimensions (now includes layout)
    local barWidth, barHeight, buttonSize, buttonGap, rowGap, layout = GetBarDimensions(barIndex);

    -- Pre-hide any slot primitives/fonts beyond the current slot count
    -- This prevents orphaned primitives when layout changes (e.g., reducing columns)
    local slotCount = layout.slots;
    for hiddenSlot = slotCount + 1, data.MAX_SLOTS_PER_BAR do
        if data.slotPrims[barIndex] and data.slotPrims[barIndex][hiddenSlot] then
            data.slotPrims[barIndex][hiddenSlot].visible = false;
        end
        if data.iconPrims[barIndex] and data.iconPrims[barIndex][hiddenSlot] then
            data.iconPrims[barIndex][hiddenSlot].visible = false;
        end
        if data.cooldownPrims[barIndex] and data.cooldownPrims[barIndex][hiddenSlot] then
            data.cooldownPrims[barIndex][hiddenSlot].visible = false;
        end
        if data.keybindFonts[barIndex] and data.keybindFonts[barIndex][hiddenSlot] then
            data.keybindFonts[barIndex][hiddenSlot]:set_visible(false);
        end
        if data.labelFonts[barIndex] and data.labelFonts[barIndex][hiddenSlot] then
            data.labelFonts[barIndex][hiddenSlot]:set_visible(false);
        end
        if data.timerFonts[barIndex] and data.timerFonts[barIndex][hiddenSlot] then
            data.timerFonts[barIndex][hiddenSlot]:set_visible(false);
        end
    end

    -- Window flags (dummy window for positioning)
    local windowFlags = GetBaseWindowFlags(gConfig.lockPositions);

    local windowName = string.format('Hotbar%d', barIndex);

    imgui.SetNextWindowPos({posX, posY}, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowSize({barWidth, barHeight}, ImGuiCond_Always);

    local windowPosX, windowPosY;

    if imgui.Begin(windowName, true, windowFlags) then
        windowPosX, windowPosY = imgui.GetWindowPos();

        -- Reserve space
        imgui.Dummy({barWidth, barHeight});

        -- Update background using per-bar settings
        local bgTheme = barSettings.backgroundTheme or 'Window1';
        local bgScale = barSettings.bgScale or 1.0;
        local borderScale = barSettings.borderScale or 1.0;
        local bgOpacity = barSettings.backgroundOpacity or 0.87;
        local borderOpacity = barSettings.borderOpacity or 1.0;

        -- Use per-bar color settings
        local bgColor = barSettings.bgColor or 0xFFFFFFFF;
        local borderColor = barSettings.borderColor or 0xFFFFFFFF;

        local bgOptions = {
            theme = bgTheme,
            padding = 0,  -- Padding already included in barWidth/barHeight
            paddingY = 0,
            bgScale = bgScale,
            borderScale = borderScale,
            bgOpacity = bgOpacity,
            borderOpacity = borderOpacity,
            bgColor = bgColor,
            borderColor = borderColor,
        };

        if data.bgHandles[barIndex] then
            windowBg.update(data.bgHandles[barIndex], windowPosX, windowPosY, barWidth, barHeight, bgOptions);
        end

        -- Draw hotbar number to the LEFT of the bar (outside container)
        if data.hotbarNumberFonts[barIndex] then
            local showNumber = barSettings.showHotbarNumber;
            if showNumber == nil then showNumber = true; end
            if showNumber then
                data.hotbarNumberFonts[barIndex]:set_text(tostring(barIndex));
                -- Position to the left of the bar
                data.hotbarNumberFonts[barIndex]:set_position_x(windowPosX - 16);
                data.hotbarNumberFonts[barIndex]:set_position_y(windowPosY + (barHeight / 2) - 6);
                data.hotbarNumberFonts[barIndex]:set_visible(true);
            else
                data.hotbarNumberFonts[barIndex]:set_visible(false);
            end
        end

        -- Draw slots based on layout (rows x columns)
        local padding = data.PADDING;
        local slotCount = layout.slots;
        local slotIndex = 1;

        -- Check if we should hide empty slots
        local hideEmptySlots = barSettings.hideEmptySlots or false;
        local paletteOpen = macropalette.IsPaletteOpen();
        local keybindEditorOpen = hotbarConfig.IsKeybindModalOpen();

        for row = 1, layout.rows do
            for col = 1, layout.columns do
                if slotIndex <= slotCount then
                    local slotX = windowPosX + padding + (col - 1) * (buttonSize + buttonGap);
                    local slotY = windowPosY + padding + (row - 1) * (buttonSize + rowGap);

                    local bind = data.GetKeybindForSlot(barIndex, slotIndex);

                    -- Hide empty slots if setting enabled and neither palette nor keybind editor is open
                    if hideEmptySlots and not paletteOpen and not keybindEditorOpen and not bind then
                        -- Hide this slot's primitives and fonts
                        if data.slotPrims[barIndex] and data.slotPrims[barIndex][slotIndex] then
                            data.slotPrims[barIndex][slotIndex].visible = false;
                        end
                        if data.iconPrims[barIndex] and data.iconPrims[barIndex][slotIndex] then
                            data.iconPrims[barIndex][slotIndex].visible = false;
                        end
                        if data.keybindFonts[barIndex] and data.keybindFonts[barIndex][slotIndex] then
                            data.keybindFonts[barIndex][slotIndex]:set_visible(false);
                        end
                        if data.labelFonts[barIndex] and data.labelFonts[barIndex][slotIndex] then
                            data.labelFonts[barIndex][slotIndex]:set_visible(false);
                        end
                        if data.timerFonts[barIndex] and data.timerFonts[barIndex][slotIndex] then
                            data.timerFonts[barIndex][slotIndex]:set_visible(false);
                        end
                    else
                        DrawSlot(barIndex, slotIndex, slotX, slotY, buttonSize, bind, barSettings);
                    end
                end
                slotIndex = slotIndex + 1;
            end
        end

        -- Hide unused slot primitives and fonts
        for hiddenSlot = slotCount + 1, data.MAX_SLOTS_PER_BAR do
            if data.slotPrims[barIndex] and data.slotPrims[barIndex][hiddenSlot] then
                data.slotPrims[barIndex][hiddenSlot].visible = false;
            end
            if data.iconPrims[barIndex] and data.iconPrims[barIndex][hiddenSlot] then
                data.iconPrims[barIndex][hiddenSlot].visible = false;
            end
            if data.cooldownPrims[barIndex] and data.cooldownPrims[barIndex][hiddenSlot] then
                data.cooldownPrims[barIndex][hiddenSlot].visible = false;
            end
            if data.keybindFonts[barIndex] and data.keybindFonts[barIndex][hiddenSlot] then
                data.keybindFonts[barIndex][hiddenSlot]:set_visible(false);
            end
            if data.labelFonts[barIndex] and data.labelFonts[barIndex][hiddenSlot] then
                data.labelFonts[barIndex][hiddenSlot]:set_visible(false);
            end
            if data.timerFonts[barIndex] and data.timerFonts[barIndex][hiddenSlot] then
                data.timerFonts[barIndex][hiddenSlot]:set_visible(false);
            end
        end

        imgui.End();
    end

    -- Save position if changed
    if windowPosX ~= nil then
        if gConfig.hotbarBarPositions == nil then
            gConfig.hotbarBarPositions = {};
        end
        if gConfig.hotbarBarPositions[barIndex] == nil then
            gConfig.hotbarBarPositions[barIndex] = {};
        end
        if gConfig.hotbarBarPositions[barIndex].x ~= windowPosX or
           gConfig.hotbarBarPositions[barIndex].y ~= windowPosY then
            gConfig.hotbarBarPositions[barIndex].x = windowPosX;
            gConfig.hotbarBarPositions[barIndex].y = windowPosY;
        end
    end
end

-- ============================================
-- Public Functions
-- ============================================

function M.DrawWindow(settings)
    -- Note: dragdrop.Update() is called from init.lua before this

    -- Update recast timers once per frame
    recast.Update();

    -- Initialize textures on first draw
    if not texturesInitialized then
        textures:Initialize();
        texturesInitialized = true;
    end

    -- Check if backgrounds are initialized
    local anyInitialized = false;
    for i = 1, data.NUM_BARS do
        if data.bgHandles[i] then
            anyInitialized = true;
            break;
        end
    end
    if not anyInitialized then
        return;
    end

    -- Draw each bar as its own window (per-bar themes handled in DrawBarWindow)
    for barIndex = 1, data.NUM_BARS do
        DrawBarWindow(barIndex, settings);
    end

    -- Note: Macro palette, dragdrop.Render(), and outside drop handling are in init.lua
end

function M.HideWindow()
    -- Hide all backgrounds
    for barIndex = 1, data.NUM_BARS do
        if data.bgHandles[barIndex] then
            windowBg.hide(data.bgHandles[barIndex]);
        end
    end

    -- Hide all fonts
    data.SetAllFontsVisible(false);

    -- Hide slot primitives
    for barIndex = 1, data.NUM_BARS do
        if data.slotPrims[barIndex] then
            for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
                if data.slotPrims[barIndex][slotIndex] then
                    data.slotPrims[barIndex][slotIndex].visible = false;
                end
            end
        end
    end

    -- Hide icon primitives
    for barIndex = 1, data.NUM_BARS do
        if data.iconPrims[barIndex] then
            for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
                if data.iconPrims[barIndex][slotIndex] then
                    data.iconPrims[barIndex][slotIndex].visible = false;
                end
            end
        end
    end

    -- Hide cooldown primitives
    for barIndex = 1, data.NUM_BARS do
        if data.cooldownPrims[barIndex] then
            for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
                if data.cooldownPrims[barIndex][slotIndex] then
                    data.cooldownPrims[barIndex][slotIndex].visible = false;
                end
            end
        end
    end
end

-- ============================================
-- Lifecycle
-- ============================================

function M.Initialize(settings)
    local bgTheme = gConfig.hotbarBackgroundTheme or 'Plain';
    loadedBgTheme = bgTheme;
    -- Background primitives are now created in init.lua
end

function M.UpdateVisuals(settings)
    -- Update each bar's theme from per-bar settings
    for barIndex = 1, data.NUM_BARS do
        local barSettings = data.GetBarSettings(barIndex);
        local bgTheme = barSettings.backgroundTheme or 'Plain';
        local bgScale = barSettings.bgScale or 1.0;
        local borderScale = barSettings.borderScale or 1.0;

        if data.bgHandles[barIndex] then
            windowBg.setTheme(data.bgHandles[barIndex], bgTheme, bgScale, borderScale);
        end
    end
end

function M.SetHidden(hidden)
    if hidden then
        M.HideWindow();
    end
end

function M.Cleanup()
    -- Background cleanup is handled in init.lua
    loadedBgTheme = nil;
    texturesInitialized = false;
end

return M;
