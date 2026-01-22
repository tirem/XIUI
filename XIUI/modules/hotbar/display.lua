--[[
* XIUI hotbar - Display Module
* Renders 6 independent hotbar windows with primitives and GDI fonts
]]--

require('common');
require('handlers.helpers');
local ffi = require('ffi');
local imgui = require('imgui');
local windowBg = require('libs.windowbackground');
local drawing = require('libs.drawing');

local data = require('modules.hotbar.data');
local actions = require('modules.hotbar.actions');
local textures = require('modules.hotbar.textures');
local macropalette = require('modules.hotbar.macropalette');
local dragdrop = require('libs.dragdrop');
local recast = require('modules.hotbar.recast');
local slotrenderer = require('modules.hotbar.slotrenderer');
local hotbarConfig = require('config.hotbar');
local petpalette = require('modules.hotbar.petpalette');
local palette = require('modules.hotbar.palette');
local skillchain = require('modules.hotbar.skillchain');
local targetLib = require('libs.target');

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

-- Force position reset flag (set by ResetPositions, cleared after applying)
local forcePositionReset = false;

-- Icon cache per slot: iconCache[barIndex][slotIndex] = { bind = lastBind, icon = cachedIcon }
-- We compare the bind reference to detect changes
local iconCache = {};

-- ============================================
-- Palette Change Animation
-- ============================================

-- Animation state per bar
local paletteAnimation = {
    -- [barIndex] = { active, startTime, duration, phase }
};

local PALETTE_ANIM_DURATION = 0.25;  -- Total animation duration in seconds
local PALETTE_ANIM_FADE_OUT = 0.12;  -- Fade out phase duration

-- Easing function (ease out cubic)
local function EaseOutCubic(t)
    return 1 - math.pow(1 - t, 3);
end

-- Start palette change animation for a bar
local function StartPaletteAnimation(barIndex)
    paletteAnimation[barIndex] = {
        active = true,
        startTime = os.clock(),
        duration = PALETTE_ANIM_DURATION,
    };
end

-- Get animation opacity for a bar (1.0 = fully visible)
local function GetPaletteAnimationOpacity(barIndex)
    local anim = paletteAnimation[barIndex];
    if not anim or not anim.active then
        return 1.0;
    end

    local elapsed = os.clock() - anim.startTime;
    if elapsed >= anim.duration then
        anim.active = false;
        return 1.0;
    end

    -- Two-phase animation: fade out then fade in
    if elapsed < PALETTE_ANIM_FADE_OUT then
        -- Fade out phase
        local progress = elapsed / PALETTE_ANIM_FADE_OUT;
        return 1.0 - EaseOutCubic(progress) * 0.7;  -- Fade to 30% opacity
    else
        -- Fade in phase
        local fadeInElapsed = elapsed - PALETTE_ANIM_FADE_OUT;
        local fadeInDuration = anim.duration - PALETTE_ANIM_FADE_OUT;
        local progress = fadeInElapsed / fadeInDuration;
        return 0.3 + EaseOutCubic(progress) * 0.7;  -- Fade from 30% to 100%
    end
end

-- Callback registered with palette system
local function OnPaletteChanged(barIndex, oldPalette, newPalette)
    StartPaletteAnimation(barIndex);
end

-- Build a cache key that includes all fields that affect the icon
local function BuildBindKey(bind)
    if not bind then return 'nil'; end
    -- Include customIconType, customIconId, and customIconPath so icon changes invalidate the cache
    local iconPart = '';
    if bind.customIconType or bind.customIconId or bind.customIconPath then
        iconPart = ':icon:' .. (bind.customIconType or '') .. ':' .. tostring(bind.customIconId or '') .. ':' .. (bind.customIconPath or '');
    end
    return (bind.actionType or '') .. ':' .. (bind.action or '') .. ':' .. (bind.target or '') .. iconPart;
end

-- Get cached icon for a slot, recompute only if bind changed
local function GetCachedIcon(barIndex, slotIndex, bind)
    if not iconCache[barIndex] then
        iconCache[barIndex] = {};
    end

    local cached = iconCache[barIndex][slotIndex];

    -- Check if we have a valid cache entry for this bind
    -- Compare by actionType+action+target+icon to detect actual changes
    -- Also invalidate if cached icon doesn't have path (try to get primitive-enabled icon)
    if cached then
        local bindKey = BuildBindKey(bind);
        if cached.bindKey == bindKey and cached.icon and cached.icon.path then
            return cached.icon;
        end
    end

    -- Cache miss or icon needs path - compute icon
    local icon = nil;
    if bind then
        _, icon = actions.BuildCommand(bind);
    end

    -- Store in cache
    local bindKey = BuildBindKey(bind);
    iconCache[barIndex][slotIndex] = {
        bindKey = bindKey,
        icon = icon,
    };

    return icon;
end

-- Clear icon cache (call when slots change)
local function ClearIconCache()
    iconCache = {};
end

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
local function DrawSlot(barIndex, slotIndex, x, y, buttonSize, bind, barSettings, animOpacity, skillchainName)
    -- Gather resources for this slot
    local resources = {
        slotPrim = data.slotPrims[barIndex] and data.slotPrims[barIndex][slotIndex],
        iconPrim = data.iconPrims[barIndex] and data.iconPrims[barIndex][slotIndex],
        framePrim = data.framePrims[barIndex] and data.framePrims[barIndex][slotIndex],
        timerFont = data.timerFonts[barIndex] and data.timerFonts[barIndex][slotIndex],
        keybindFont = data.keybindFonts[barIndex] and data.keybindFonts[barIndex][slotIndex],
        labelFont = data.labelFonts[barIndex] and data.labelFonts[barIndex][slotIndex],
        mpCostFont = data.mpCostFonts[barIndex] and data.mpCostFonts[barIndex][slotIndex],
        quantityFont = data.quantityFonts[barIndex] and data.quantityFonts[barIndex][slotIndex],
    };

    -- Get icon for this action (cached - only rebuilds when bind changes)
    local icon = GetCachedIcon(barIndex, slotIndex, bind);
    local labelText = bind and (bind.displayName or bind.action or '') or '';

    -- Get per-bar display settings
    local showActionLabels = barSettings and barSettings.showActionLabels or false;
    local showSlotFrame = barSettings and barSettings.showSlotFrame or false;
    local customFramePath = barSettings and barSettings.customFramePath or '';

    -- NOTE: Keybind font settings are now applied in slotrenderer with caching
    -- (removed redundant set_font_height/set_font_color calls that happened every frame)

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
        slotOpacity = barSettings and barSettings.slotOpacity or 1.0,
        keybindText = (barSettings and barSettings.showKeybinds ~= false) and data.GetKeybindDisplay(barIndex, slotIndex) or nil,
        keybindFontSize = barSettings and barSettings.keybindFontSize or 10,
        keybindFontColor = barSettings and barSettings.keybindFontColor or 0xFFFFFFFF,
        keybindAnchor = barSettings and barSettings.keybindAnchor or 'topLeft',
        keybindOffsetX = barSettings and barSettings.keybindOffsetX or 0,
        keybindOffsetY = barSettings and barSettings.keybindOffsetY or 0,
        showLabel = showActionLabels,
        labelText = labelText,
        labelOffsetX = barSettings and barSettings.actionLabelOffsetX or 0,
        labelOffsetY = (barSettings and barSettings.actionLabelOffsetY or 0) + data.LABEL_GAP,
        labelFontSize = barSettings and barSettings.labelFontSize or 10,
        recastTimerFontSize = barSettings and barSettings.recastTimerFontSize or 11,
        recastTimerFontColor = barSettings and barSettings.recastTimerFontColor or 0xFFFFFFFF,
        flashCooldownUnder5 = barSettings and barSettings.flashCooldownUnder5 or false,
        useHHMMCooldownFormat = barSettings and barSettings.useHHMMCooldownFormat or false,
        labelFontColor = barSettings and barSettings.labelFontColor or 0xFFFFFFFF,
        labelCooldownColor = barSettings and barSettings.labelCooldownColor or 0xFF888888,
        labelNoMpColor = barSettings and barSettings.labelNoMpColor or 0xFFFF4444,
        showFrame = showSlotFrame,
        customFramePath = customFramePath,
        isPressed = isPressed,
        showMpCost = barSettings and barSettings.showMpCost ~= false,
        mpCostFontSize = barSettings and barSettings.mpCostFontSize or 10,
        mpCostFontColor = barSettings and barSettings.mpCostFontColor or 0xFFD4FF97,
        mpCostNoMpColor = barSettings and barSettings.labelNoMpColor or 0xFFFF4444,
        mpCostAnchor = barSettings and barSettings.mpCostAnchor or 'topRight',
        mpCostOffsetX = barSettings and barSettings.mpCostOffsetX or 0,
        mpCostOffsetY = barSettings and barSettings.mpCostOffsetY or 0,
        showQuantity = barSettings and barSettings.showQuantity ~= false,
        quantityFontSize = barSettings and barSettings.quantityFontSize or 10,
        quantityFontColor = barSettings and barSettings.quantityFontColor or 0xFFFFFFFF,
        quantityAnchor = barSettings and barSettings.quantityAnchor or 'bottomRight',
        quantityOffsetX = barSettings and barSettings.quantityOffsetX or 0,
        quantityOffsetY = barSettings and barSettings.quantityOffsetY or 0,

        -- Interaction Config
        buttonId = string.format('##hotbarslot_%d_%d', barIndex, slotIndex),
        dropZoneId = string.format('hotbar_%d_%d', barIndex, slotIndex),
        dropAccepts = {'macro', 'slot', 'crossbar_slot'},
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

        -- Animation
        animOpacity = animOpacity or 1.0,

        -- Skillchain highlight
        skillchainName = skillchainName,
        skillchainColor = gConfig.hotbarGlobal.skillchainHighlightColor or 0xFFD4AA44,
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
        -- Hide unused slot, icon, cooldown, and frame primitives
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
            if data.framePrims[barIndex] and data.framePrims[barIndex][slotIndex] then
                data.framePrims[barIndex][slotIndex].visible = false;
            end
        end
        return;
    end

    -- Get default position for fallback
    local defaultX, defaultY = GetDefaultBarPosition(barIndex);
    local windowName = string.format('Hotbar%d', barIndex);

    -- Apply saved position if exists (using helper for profile support), otherwise set default
    local hasSaved = gConfig.windowPositions and gConfig.windowPositions[windowName];
    
    -- Migration: Check for legacy position if not found in standard system
    if not hasSaved and gConfig.hotbarBarPositions and gConfig.hotbarBarPositions[barIndex] then
        if not gConfig.windowPositions then gConfig.windowPositions = {}; end
        gConfig.windowPositions[windowName] = { 
            x = gConfig.hotbarBarPositions[barIndex].x, 
            y = gConfig.hotbarBarPositions[barIndex].y 
        };
        hasSaved = true;
    end

    if hasSaved then
        ApplyWindowPosition(windowName);
    else
        imgui.SetNextWindowPos({defaultX, defaultY}, ImGuiCond_FirstUseEver);
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
        if data.framePrims[barIndex] and data.framePrims[barIndex][hiddenSlot] then
            data.framePrims[barIndex][hiddenSlot].visible = false;
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
        if data.mpCostFonts[barIndex] and data.mpCostFonts[barIndex][hiddenSlot] then
            data.mpCostFonts[barIndex][hiddenSlot]:set_visible(false);
        end
        if data.quantityFonts[barIndex] and data.quantityFonts[barIndex][hiddenSlot] then
            data.quantityFonts[barIndex][hiddenSlot]:set_visible(false);
        end
    end

    -- Window flags (dummy window for positioning)
    local windowFlags = GetBaseWindowFlags(gConfig.lockPositions);

    -- Check if anchor is currently being dragged or positions are being reset - if so, force position
    local anchorDragging = drawing.IsAnchorDragging(windowName);
    
    if anchorDragging or forcePositionReset then
        -- Force position update during drag
        local saved = gConfig.windowPositions and gConfig.windowPositions[windowName];
        local targetX = saved and saved.x or defaultX;
        local targetY = saved and saved.y or defaultY;
        imgui.SetNextWindowPos({targetX, targetY}, ImGuiCond_Always);
    end

    imgui.SetNextWindowSize({barWidth, barHeight}, ImGuiCond_Always);

    local windowPosX, windowPosY;

    if imgui.Begin(windowName, true, windowFlags) then
        -- Save position if moved
        SaveWindowPosition(windowName);
        windowPosX, windowPosY = imgui.GetWindowPos();

        -- Reserve space
        imgui.Dummy({barWidth, barHeight});

        -- Update background using per-bar settings
        local bgTheme = barSettings.backgroundTheme or '-None-';
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
                -- Position to the left of the bar with optional offsets
                local hbnOffsetX = barSettings.hotbarNumberOffsetX or 0;
                local hbnOffsetY = barSettings.hotbarNumberOffsetY or 0;
                data.hotbarNumberFonts[barIndex]:set_position_x(windowPosX - 16 + hbnOffsetX);
                data.hotbarNumberFonts[barIndex]:set_position_y(windowPosY + (barHeight / 2) - 6 + hbnOffsetY);
                data.hotbarNumberFonts[barIndex]:set_visible(true);
            else
                data.hotbarNumberFonts[barIndex]:set_visible(false);
            end
        end

        -- Draw slots based on layout (rows x columns)
        local padding = data.PADDING;
        local slotCount = layout.slots;
        local slotIndex = 1;

        -- Get palette change animation opacity
        local animOpacity = GetPaletteAnimationOpacity(barIndex);

        -- Check if we should hide empty slots
        local hideEmptySlots = barSettings.hideEmptySlots or false;
        local paletteOpen = macropalette.IsPaletteOpen();
        local keybindEditorOpen = hotbarConfig.IsKeybindModalOpen();
        -- Use both IsDragging and IsDragPending to show empty slots during entire drag process
        -- IsDragging only returns true after drag threshold is met, but we need to show
        -- drop zones earlier so they're registered when the drag activates
        local isDragging = dragdrop.IsDragging() or dragdrop.IsDragPending();

        -- Get target server ID for skillchain prediction (cached for all slots)
        local targetServerId = nil;
        local skillchainEnabled = gConfig.hotbarGlobal.skillchainHighlightEnabled ~= false;
        if skillchainEnabled then
            local mainTargetIdx = targetLib.GetTargets();
            if mainTargetIdx and mainTargetIdx ~= 0 then
                local targetEntity = GetEntity(mainTargetIdx);
                if targetEntity then
                    targetServerId = targetEntity.ServerId;
                end
            end
        end

        for row = 1, layout.rows do
            for col = 1, layout.columns do
                if slotIndex <= slotCount then
                    local slotX = windowPosX + padding + (col - 1) * (buttonSize + buttonGap);
                    local slotY = windowPosY + padding + (row - 1) * (buttonSize + rowGap);

                    local bind = data.GetKeybindForSlot(barIndex, slotIndex);

                    -- Hide empty slots if setting enabled and not editing/dragging
                    if hideEmptySlots and not paletteOpen and not keybindEditorOpen and not isDragging and not bind then
                        -- Hide this slot's primitives and fonts
                        if data.slotPrims[barIndex] and data.slotPrims[barIndex][slotIndex] then
                            data.slotPrims[barIndex][slotIndex].visible = false;
                        end
                        if data.iconPrims[barIndex] and data.iconPrims[barIndex][slotIndex] then
                            data.iconPrims[barIndex][slotIndex].visible = false;
                        end
                        if data.framePrims[barIndex] and data.framePrims[barIndex][slotIndex] then
                            data.framePrims[barIndex][slotIndex].visible = false;
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
                        if data.mpCostFonts[barIndex] and data.mpCostFonts[barIndex][slotIndex] then
                            data.mpCostFonts[barIndex][slotIndex]:set_visible(false);
                        end
                        if data.quantityFonts[barIndex] and data.quantityFonts[barIndex][slotIndex] then
                            data.quantityFonts[barIndex][slotIndex]:set_visible(false);
                        end
                    else
                        -- Check for skillchain prediction on weapon skill slots
                        local slotSkillchainName = nil;
                        if skillchainEnabled and bind and bind.actionType == 'ws' and bind.action then
                            -- Pass WS name directly - skillchain module handles name->ID conversion
                            slotSkillchainName = skillchain.GetSkillchainForSlot(targetServerId, bind.action);
                        end
                        DrawSlot(barIndex, slotIndex, slotX, slotY, buttonSize, bind, barSettings, animOpacity, slotSkillchainName);
                    end
                end
                slotIndex = slotIndex + 1;
            end
        end

        -- NOTE: Hide loop for unused slots already handled at lines 226-245
        -- (removed duplicate hide loop that was here)

        imgui.End();
    end

    -- Draw pet palette indicator dot OUTSIDE window bounds (above bar number)
    -- Must be after End() and use ForegroundDrawList to avoid clipping
    -- Only shows for pet-aware bars (gold indicator)
    local hasPetIndicator = barSettings.petAware and barSettings.showPetIndicator ~= false;

    if windowPosX and hasPetIndicator then
        local dotX = windowPosX - 12;  -- Centered above bar number
        local dotY = windowPosY + (barHeight / 2) - 20;  -- Above the number
        local dotRadius = 5;
        local fgDrawList = GetUIDrawList();

        local indicatorColor = {1.0, 0.8, 0.2, 1.0};  -- Gold

        fgDrawList:AddCircleFilled({dotX, dotY}, dotRadius, imgui.GetColorU32(indicatorColor), 12);
        fgDrawList:AddCircle({dotX, dotY}, dotRadius, imgui.GetColorU32({0.0, 0.0, 0.0, 1.0}), 12, 1.0);

        -- Check hover for tooltip
        local mouseX, mouseY = imgui.GetMousePos();
        local dx = mouseX - dotX;
        local dy = mouseY - dotY;
        local hoverRadius = dotRadius + 3;
        if (dx * dx + dy * dy) <= (hoverRadius * hoverRadius) then
            imgui.BeginTooltip();

            imgui.TextColored({1.0, 0.8, 0.2, 1.0}, 'Pet Palette Bar ' .. barIndex);
            imgui.Separator();

            -- Current pet info
            local currentPet = petpalette.GetCurrentPetDisplayName();
            if currentPet then
                imgui.Text('Current Pet: ' .. currentPet);
            else
                imgui.TextColored({0.6, 0.6, 0.6, 1.0}, 'No pet summoned');
            end

            -- Palette mode
            local hasOverride = petpalette.HasManualOverride(barIndex);
            if hasOverride then
                local overrideName = petpalette.GetPaletteDisplayName(barIndex, data.jobId);
                imgui.Text('Palette: ' .. overrideName .. ' (Manual)');
            else
                imgui.Text('Palette: Auto');
            end

            imgui.EndTooltip();
        end
    end

    -- Draw move anchor (only visible when config is open)
    -- Must be called after we have window position
    if windowPosX ~= nil then
        -- Use same window name as ImGui window so positions are shared
        local anchorName = string.format('Hotbar%d', barIndex);
        local anchorNewX, anchorNewY = drawing.DrawMoveAnchor(anchorName, windowPosX, windowPosY);
        if anchorNewX ~= nil then
            windowPosX = anchorNewX;
            windowPosY = anchorNewY;
            
            -- Update config immediately so next frame's positioning logic picks it up
            if not gConfig.windowPositions then gConfig.windowPositions = {}; end
            gConfig.windowPositions[anchorName] = { x = anchorNewX, y = anchorNewY };
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

    -- Clear force position reset flag after all bars have been drawn
    if forcePositionReset then
        forcePositionReset = false;
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

    -- Hide frame primitives
    for barIndex = 1, data.NUM_BARS do
        if data.framePrims[barIndex] then
            for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
                if data.framePrims[barIndex][slotIndex] then
                    data.framePrims[barIndex][slotIndex].visible = false;
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

    -- Register palette change callback for animation
    palette.OnPaletteChanged(OnPaletteChanged);
end

function M.UpdateVisuals(settings)
    -- Update each bar's theme from per-bar settings
    for barIndex = 1, data.NUM_BARS do
        local barSettings = data.GetBarSettings(barIndex);
        local bgTheme = barSettings.backgroundTheme or '-None-';
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
    -- Clear icon cache
    ClearIconCache();
    -- Clear slotrenderer cache
    slotrenderer.ClearAllCache();
end

-- Expose cache clear for external callers (e.g., when slot actions change)
function M.ClearIconCache()
    ClearIconCache();
end

-- Reset all bar positions to defaults (called when settings are reset)
function M.ResetPositions()
    forcePositionReset = true;
end

return M;
