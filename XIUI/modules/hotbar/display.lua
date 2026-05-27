--[[
* XIUI hotbar - Display Module
* Renders 6 independent hotbar windows with primitives and imtext
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
local imtext = require('libs.imtext');

local M = {};

-- ============================================
-- Anchored Layout Helpers (hotbar only)
-- ============================================

local function GetHotbarBarConfig(barIndex)
    return gConfig and gConfig['hotbarBar' .. barIndex];
end

local function IsAnchoredMode()
    return gConfig.hotbarGlobal and gConfig.hotbarGlobal.positionMode == 'anchored';
end

local function IsBarInAnchorStack(barIndex)
    if not IsAnchoredMode() then
        return false;
    end

    local barConfig = GetHotbarBarConfig(barIndex);
    if not barConfig or barConfig.enabled == false then
        return false;
    end

    return barConfig.anchoredInStack ~= false;
end

local function GetAnchoredStackBars()
    local stack = {};
    if not IsAnchoredMode() then
        return stack;
    end

    for barIndex = 1, data.NUM_BARS do
        if IsBarInAnchorStack(barIndex) then
            stack[#stack + 1] = barIndex;
        end
    end

    return stack;
end

local function GetBackgroundPadding(barSettings)
    local gs = (gConfig and gConfig.globalScale) or 1.0;
    local padX = (barSettings and barSettings.backgroundPaddingX) or 0;
    local padY = (barSettings and barSettings.backgroundPaddingY) or 0;
    return padX * gs, padY * gs;
end

local function GetBarSavedPosition(barIndex, defaultX, defaultY)
    local windowName = string.format('Hotbar%d', barIndex);
    local saved = gConfig.windowPositions and gConfig.windowPositions[windowName];
    if saved then
        return saved.x, saved.y;
    end
    return defaultX, defaultY;
end

-- Forward declarations (defined after GetBarDimensions)
local GetBarMetrics;
local ComputeAnchoredLayout;
local DrawWindowBackground;
local DrawBarBackground;

-- ============================================
-- State
-- ============================================

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

-- Get cached icon (and precomputed abbreviation) for a slot, recompute only if bind changed.
-- Returns: icon, abbr, abbrW. When the slot has an icon, abbr/abbrW are nil.
-- When the slot has no icon, abbr/abbrW are precomputed so DrawSlot doesn't have to
-- run GetActionAbbreviation + imtext.Measure per frame.
local function GetCachedIcon(barIndex, slotIndex, bind)
    if not iconCache[barIndex] then
        iconCache[barIndex] = {};
    end

    local cached = iconCache[barIndex][slotIndex];

    -- Check if we have a valid cache entry for this bind
    if cached then
        local bindKey = BuildBindKey(bind);
        if cached.bindKey == bindKey then
            -- Cache hit - return cached values (icon may be nil; that's a valid "no icon" memo)
            return cached.icon, cached.abbr, cached.abbrW;
        end
    end

    -- Cache miss - compute icon and (if no icon) abbreviation
    local icon = nil;
    if bind then
        _, icon = actions.BuildCommand(bind);
    end

    local abbr, abbrW = nil, nil;
    if not icon and bind then
        abbr, abbrW = slotrenderer.ComputeAbbreviation(bind);
    end

    -- Store in cache
    local bindKey = BuildBindKey(bind);
    iconCache[barIndex][slotIndex] = {
        bindKey = bindKey,
        icon = icon,
        abbr = abbr,
        abbrW = abbrW,
    };

    return icon, abbr, abbrW;
end

-- Clear icon cache (call when slots change)
local function ClearIconCache()
    iconCache = {};
end

-- Clear icon cache for a specific slot (call on targeted slot updates)
local function ClearIconCacheForSlot(barIndex, slotIndex)
    if iconCache[barIndex] then
        iconCache[barIndex][slotIndex] = nil;
    end
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
    local gs = (gConfig and gConfig.globalScale) or 1.0;
    local slotSize = (barSettings.slotSize or 32) * gs;
    -- Use per-bar slot padding settings
    local slotGap = (barSettings.slotXPadding or data.BUTTON_GAP) * gs;
    local padding = data.PADDING * gs;
    local rowGap = (barSettings.slotYPadding or data.ROW_GAP) * gs;

    local layout = data.GetBarLayout(barIndex);

    -- Calculate dimensions based on rows and columns
    local width = (slotSize * layout.columns) + (slotGap * (layout.columns - 1)) + (padding * 2);
    local height = (slotSize * layout.rows) + (rowGap * (layout.rows - 1)) + (padding * 2);

    return width, height, slotSize, slotGap, rowGap, layout;
end

GetBarMetrics = function(barIndex, inAnchoredStack)
    local barSettings = data.GetBarSettings(barIndex);
    local contentW, contentH, buttonSize, buttonGap, rowGap, layout = GetBarDimensions(barIndex);
    local gs = (gConfig and gConfig.globalScale) or 1.0;

    if inAnchoredStack then
        return {
            contentW = contentW,
            contentH = contentH,
            windowW = contentW,
            windowH = contentH,
            bgPadX = 0,
            bgPadY = 0,
            buttonSize = buttonSize,
            buttonGap = buttonGap,
            rowGap = rowGap,
            layout = layout,
            slotPadding = data.PADDING * gs,
        };
    end

    local bgPadX, bgPadY = GetBackgroundPadding(barSettings);

    return {
        contentW = contentW,
        contentH = contentH,
        windowW = contentW + (bgPadX * 2),
        windowH = contentH + (bgPadY * 2),
        bgPadX = bgPadX,
        bgPadY = bgPadY,
        buttonSize = buttonSize,
        buttonGap = buttonGap,
        rowGap = rowGap,
        layout = layout,
        slotPadding = data.PADDING * gs,
    };
end

ComputeAnchoredLayout = function(stack)
    local layout = {};
    if #stack == 0 then
        return layout;
    end

    local anchorBar = stack[1];
    local defaultX, defaultY = GetDefaultBarPosition(anchorBar);
    local anchorX, anchorY = GetBarSavedPosition(anchorBar, defaultX, defaultY);
    local globalSettings = gConfig.hotbarGlobal or {};
    local bgPadX, bgPadY = GetBackgroundPadding(globalSettings);
    local gs = (gConfig and gConfig.globalScale) or 1.0;
    local stackSpacing = (globalSettings.hotbarSpacing or 0) * gs;
    local currentY = anchorY;
    local maxContentW = 0;
    local topBarY = anchorY;

    for i, barIndex in ipairs(stack) do
        if i > 1 then
            currentY = currentY - stackSpacing;
        end

        local metrics = GetBarMetrics(barIndex, true);
        maxContentW = math.max(maxContentW, metrics.contentW);
        layout[barIndex] = {
            x = anchorX,
            y = currentY,
            metrics = metrics,
        };
        topBarY = currentY;
        currentY = currentY - metrics.contentH;
    end

    local bottomEntry = layout[anchorBar];
    local bottomY = bottomEntry.y + bottomEntry.metrics.contentH;
    -- Outer background rect for the whole anchored stack (not per-bar).
    layout._stackBackground = {
        x = anchorX - bgPadX,
        y = topBarY - bgPadY,
        width = maxContentW + (bgPadX * 2),
        height = (bottomY - topBarY) + (bgPadY * 2),
    };

    return layout;
end

local function BuildWindowBgOptions(settings)
    return {
        theme = settings.backgroundTheme or '-None-',
        padding = 0,
        paddingY = 0,
        bgScale = settings.bgScale or 1.0,
        borderScale = settings.borderScale or 1.0,
        bgOpacity = settings.backgroundOpacity or 0.87,
        borderOpacity = settings.borderOpacity or 1.0,
        bgColor = settings.bgColor or 0xFFFFFFFF,
        borderColor = settings.borderColor or 0xFFFFFFFF,
    };
end

DrawWindowBackground = function(x, y, width, height, settings)
    local bgOptions = BuildWindowBgOptions(settings);
    if bgOptions.theme == '-None-' then
        return;
    end

    local drawList = GetUIDrawList();
    if not drawList then
        return;
    end

    windowBg.Draw(drawList, x, y, width, height, bgOptions);
end

DrawBarBackground = function(windowPosX, windowPosY, metrics, barSettings)
    DrawWindowBackground(windowPosX, windowPosY, metrics.windowW, metrics.windowH, barSettings);
end

-- Cached asset path
local assetsPath = nil;

local function GetAssetsPath()
    if not assetsPath then
        assetsPath = string.format('%saddons\\XIUI\\assets\\hotbar\\', AshitaCore:GetInstallPath());
    end
    return assetsPath;
end

-- Pre-allocated reusable table for DrawSlot
local slotParams = {};
local HOTBAR_DROP_ACCEPTS = {'macro', 'slot', 'crossbar_slot'};

-- Pre-created closures and string IDs per slot (avoids ~288 closure + 72 array allocations per frame)
local slotInteraction = {};

local function GetSlotInteraction(barIndex, slotIndex)
    if not slotInteraction[barIndex] then
        slotInteraction[barIndex] = {};
    end
    if not slotInteraction[barIndex][slotIndex] then
        slotInteraction[barIndex][slotIndex] = {
            buttonId = string.format('##hotbarslot_%d_%d', barIndex, slotIndex),
            dropZoneId = string.format('hotbar_%d_%d', barIndex, slotIndex),
            onDrop = function(payload)
                macropalette.HandleDropOnSlot(payload, barIndex, slotIndex);
            end,
            getDragData = function()
                local b = data.GetKeybindForSlot(barIndex, slotIndex);
                macropalette.StartDragSlot(barIndex, slotIndex, b);
                return nil;  -- StartDragSlot handles the drag itself
            end,
            onRightClick = function()
                macropalette.ClearSlot(barIndex, slotIndex);
            end,
        };
    end
    return slotInteraction[barIndex][slotIndex];
end

-- Draw a single hotbar slot using shared renderer
local function DrawSlot(barIndex, slotIndex, x, y, buttonSize, bind, barSettings, animOpacity, skillchainName)
    -- Get icon (and pre-resolved abbreviation, if no icon) for this slot.
    -- All three are cached together; recomputed only when bind changes.
    local icon, cachedAbbr, cachedAbbrW = GetCachedIcon(barIndex, slotIndex, bind);

    -- Check if this slot is currently pressed (keyboard)
    local pressedHotbar = actions.GetPressedHotbar();
    local pressedSlot = actions.GetPressedSlot();

    -- Get pre-created interaction closures and IDs
    local interaction = GetSlotInteraction(barIndex, slotIndex);

    -- Global UI scale (applied to font sizes and pixel offsets that aren't
    -- already pre-scaled via GetBarDimensions). Position/size args (x, y,
    -- buttonSize) come in already scaled by the caller.
    local gs = (gConfig and gConfig.globalScale) or 1.0;

    -- Update reusable params table in-place
    local p = slotParams;
    -- Position/Size
    p.x = x;
    p.y = y;
    p.size = buttonSize;
    -- Action Data
    p.bind = bind;
    p.icon = icon;
    p.cachedAbbr = cachedAbbr;
    p.cachedAbbrW = cachedAbbrW;
    -- Visual Settings
    p.slotBgColor = barSettings and barSettings.slotBackgroundColor or 0xFFFFFFFF;
    p.slotOpacity = barSettings and barSettings.slotOpacity or 1.0;
    p.keybindText = (barSettings and barSettings.showKeybinds ~= false) and data.GetKeybindDisplay(barIndex, slotIndex) or nil;
    p.keybindFontSize = (barSettings and barSettings.keybindFontSize or 10) * gs;
    p.keybindFontColor = barSettings and barSettings.keybindFontColor or 0xFFFFFFFF;
    p.keybindAnchor = barSettings and barSettings.keybindAnchor or 'topLeft';
    p.keybindOffsetX = (barSettings and barSettings.keybindOffsetX or 0) * gs;
    p.keybindOffsetY = (barSettings and barSettings.keybindOffsetY or 0) * gs;
    p.showLabel = barSettings and barSettings.showActionLabels or false;
    p.labelText = bind and (bind.displayName or bind.action or '') or '';
    p.labelOffsetX = (barSettings and barSettings.actionLabelOffsetX or 0) * gs;
    p.labelOffsetY = ((barSettings and barSettings.actionLabelOffsetY or 0) + data.LABEL_GAP) * gs;
    p.labelFontSize = (barSettings and barSettings.labelFontSize or 10) * gs;
    p.recastTimerFontSize = (barSettings and barSettings.recastTimerFontSize or 11) * gs;
    p.recastTimerFontColor = barSettings and barSettings.recastTimerFontColor or 0xFFFFFFFF;
    p.flashCooldownUnder5 = barSettings and barSettings.flashCooldownUnder5 or false;
    p.useHHMMCooldownFormat = barSettings and barSettings.useHHMMCooldownFormat or false;
    p.labelFontColor = barSettings and barSettings.labelFontColor or 0xFFFFFFFF;
    p.labelCooldownColor = barSettings and barSettings.labelCooldownColor or 0xFF888888;
    p.labelNoMpColor = barSettings and barSettings.labelNoMpColor or 0xFFFF4444;
    p.showFrame = barSettings and barSettings.showSlotFrame or false;
    p.customFramePath = barSettings and barSettings.customFramePath or '';
    p.isPressed = (pressedHotbar == barIndex and pressedSlot == slotIndex);
    p.showMpCost = barSettings and barSettings.showMpCost ~= false;
    p.mpCostFontSize = (barSettings and barSettings.mpCostFontSize or 10) * gs;
    p.mpCostFontColor = barSettings and barSettings.mpCostFontColor or 0xFFD4FF97;
    p.mpCostNoMpColor = barSettings and barSettings.labelNoMpColor or 0xFFFF4444;
    p.mpCostAnchor = barSettings and barSettings.mpCostAnchor or 'topRight';
    p.mpCostOffsetX = (barSettings and barSettings.mpCostOffsetX or 0) * gs;
    p.mpCostOffsetY = (barSettings and barSettings.mpCostOffsetY or 0) * gs;
    p.showQuantity = barSettings and barSettings.showQuantity ~= false;
    p.showStackQuantity = barSettings and barSettings.showStackQuantity == true;
    p.quantityFontSize = (barSettings and barSettings.quantityFontSize or 10) * gs;
    p.quantityFontColor = barSettings and barSettings.quantityFontColor or 0xFFFFFFFF;
    p.quantityAnchor = barSettings and barSettings.quantityAnchor or 'bottomRight';
    p.quantityOffsetX = (barSettings and barSettings.quantityOffsetX or 0) * gs;
    p.quantityOffsetY = (barSettings and barSettings.quantityOffsetY or 0) * gs;
    -- Interaction Config
    p.buttonId = interaction.buttonId;
    p.dropZoneId = interaction.dropZoneId;
    p.dropAccepts = HOTBAR_DROP_ACCEPTS;
    p.onDrop = interaction.onDrop;
    p.dragType = 'slot';
    p.getDragData = interaction.getDragData;
    p.onRightClick = interaction.onRightClick;
    p.showTooltip = true;
    -- Animation
    p.animOpacity = animOpacity or 1.0;
    -- Skillchain highlight
    p.skillchainName = skillchainName;
    p.skillchainColor = gConfig.hotbarGlobal.skillchainHighlightColor or 0xFFD4AA44;

    -- Render slot using shared renderer (handles ALL rendering and interactions)
    local result = slotrenderer.DrawSlot(p);
    return result.isHovered;
end

-- Draw a single hotbar window
local function DrawBarWindow(barIndex, settings, drawContext)
    drawContext = drawContext or {};

    -- Get per-bar settings
    local barSettings = data.GetBarSettings(barIndex);

    -- Check if bar is enabled
    if not barSettings.enabled then
        return;
    end

    local metrics = drawContext.metrics or GetBarMetrics(barIndex);
    local barWidth = metrics.windowW;
    local barHeight = metrics.windowH;
    local buttonSize = metrics.buttonSize;
    local buttonGap = metrics.buttonGap;
    local rowGap = metrics.rowGap;
    local layout = metrics.layout;
    local bgPadX = metrics.bgPadX;
    local bgPadY = metrics.bgPadY;
    local slotPadding = metrics.slotPadding;

    local defaultX, defaultY = GetDefaultBarPosition(barIndex);
    local windowName = string.format('Hotbar%d', barIndex);
    local hasSaved = gConfig.windowPositions and gConfig.windowPositions[windowName];
    local useAnchoredPosition = drawContext.resolvedPosition ~= nil;
    local skipBackground = drawContext.skipBackground == true;
    local isAnchorBar = drawContext.isAnchorBar == true;
    local savePosition = drawContext.savePosition ~= false;
    local anchorDragging = drawing.IsAnchorDragging(windowName);

    if useAnchoredPosition then
        if isAnchorBar and (anchorDragging or forcePositionReset) then
            local targetX, targetY = GetBarSavedPosition(barIndex, defaultX, defaultY);
            imgui.SetNextWindowPos({targetX, targetY}, ImGuiCond_Always);
        else
            imgui.SetNextWindowPos({drawContext.resolvedPosition.x, drawContext.resolvedPosition.y}, ImGuiCond_Always);
        end
    elseif hasSaved then
        ApplyWindowPosition(windowName);
    else
        imgui.SetNextWindowPos({defaultX, defaultY}, ImGuiCond_FirstUseEver);
    end

    -- Window flags (dummy window for positioning)
    local windowFlags = GetBaseWindowFlags(gConfig.lockPositions);

    if not useAnchoredPosition and (anchorDragging or forcePositionReset) then
        local targetX, targetY = GetBarSavedPosition(barIndex, defaultX, defaultY);
        imgui.SetNextWindowPos({targetX, targetY}, ImGuiCond_Always);
    end

    imgui.SetNextWindowSize({barWidth, barHeight}, ImGuiCond_Always);

    local windowPosX, windowPosY;

    if imgui.Begin(windowName, true, windowFlags) then
        if savePosition then
            SaveWindowPosition(windowName);
        end
        windowPosX, windowPosY = imgui.GetWindowPos();

        -- Reserve space
        imgui.Dummy({barWidth, barHeight});

        if not skipBackground then
            DrawBarBackground(windowPosX, windowPosY, metrics, barSettings);
        end

        -- Draw hotbar number to the LEFT of the bar (outside container)
        local showNumber = barSettings.showHotbarNumber;
        if showNumber == nil then showNumber = true; end
        if showNumber then
            local hbnOffsetX = barSettings.hotbarNumberOffsetX or 0;
            local hbnOffsetY = barSettings.hotbarNumberOffsetY or 0;
            local hbnText = tostring(barIndex);
            local hbnX = windowPosX - 16 + hbnOffsetX;
            local hbnY = windowPosY + (barHeight / 2) - 6 + hbnOffsetY;
            local hbnDrawList = GetUIDrawList();
            if hbnDrawList then
                imtext.Draw(hbnDrawList, hbnText, hbnX, hbnY, 0xFFFFFFFF, 12);
            end
        end

        -- Draw slots based on layout (rows x columns)
        slotCount = layout.slots;
        local slotIndex = 1;

        local animOpacity = GetPaletteAnimationOpacity(barIndex);

        local hideEmptySlots = barSettings.hideEmptySlots or false;
        local paletteOpen = macropalette.IsPaletteOpen();
        local keybindEditorOpen = hotbarConfig.IsKeybindModalOpen();
        local isDragging = dragdrop.IsDragging() or dragdrop.IsDragPending();

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
                    local slotX = windowPosX + bgPadX + slotPadding + (col - 1) * (buttonSize + buttonGap);
                    local slotY = windowPosY + bgPadY + slotPadding + (row - 1) * (buttonSize + rowGap);

                    local bind = data.GetKeybindForSlot(barIndex, slotIndex);

                    if hideEmptySlots and not paletteOpen and not keybindEditorOpen and not isDragging and not bind then
                        -- Empty slot: skip rendering
                    else
                        local slotSkillchainName = nil;
                        if skillchainEnabled and bind and bind.actionType == 'ws' and bind.action then
                            slotSkillchainName = skillchain.GetSkillchainForSlot(targetServerId, bind.action);
                        end
                        DrawSlot(barIndex, slotIndex, slotX, slotY, buttonSize, bind, barSettings, animOpacity, slotSkillchainName);
                    end
                end
                slotIndex = slotIndex + 1;
            end
        end

        imgui.End();
    end

    -- Draw pet palette indicator dot OUTSIDE window bounds (above bar number)
    local hasPetIndicator = barSettings.petAware and barSettings.showPetIndicator ~= false;

    if windowPosX and hasPetIndicator then
        local dotX = windowPosX - 12;
        local dotY = windowPosY + (barHeight / 2) - 20;
        local dotRadius = 5;
        local fgDrawList = GetUIDrawList();

        local indicatorColor = {1.0, 0.8, 0.2, 1.0};

        fgDrawList:AddCircleFilled({dotX, dotY}, dotRadius, imgui.GetColorU32(indicatorColor), 12);
        fgDrawList:AddCircle({dotX, dotY}, dotRadius, imgui.GetColorU32({0.0, 0.0, 0.0, 1.0}), 12, 1.0);

        local mouseX, mouseY = imgui.GetMousePos();
        local dx = mouseX - dotX;
        local dy = mouseY - dotY;
        local hoverRadius = dotRadius + 3;
        if (dx * dx + dy * dy) <= (hoverRadius * hoverRadius) then
            imgui.BeginTooltip();

            imgui.TextColored({1.0, 0.8, 0.2, 1.0}, 'Pet Palette Bar ' .. barIndex);
            imgui.Separator();

            local currentPet = petpalette.GetCurrentPetDisplayName();
            if currentPet then
                imgui.Text('Current Pet: ' .. currentPet);
            else
                imgui.TextColored({0.6, 0.6, 0.6, 1.0}, 'No pet summoned');
            end

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
    if windowPosX ~= nil then
        local globalLocked = gConfig and gConfig.hotbarLockMovement;
        local showAnchor = not globalLocked and (not useAnchoredPosition or isAnchorBar);
        if showAnchor then
            local anchorName = string.format('Hotbar%d', barIndex);
            local anchorNewX, anchorNewY = drawing.DrawMoveAnchor(anchorName, windowPosX, windowPosY);
            if anchorNewX ~= nil then
                windowPosX = anchorNewX;
                windowPosY = anchorNewY;

                if not gConfig.windowPositions then gConfig.windowPositions = {}; end
                gConfig.windowPositions[anchorName] = { x = anchorNewX, y = anchorNewY };
            end
        end
    end
end

-- ============================================
-- Public Functions
-- ============================================

function M.DrawWindow(settings)
    -- Note: dragdrop.Update() is called from init.lua before this

    -- Initialize textures on first draw
    if not texturesInitialized then
        textures:Initialize();
        texturesInitialized = true;
    end

    local anchoredStack = GetAnchoredStackBars();
    local anchoredLayout = ComputeAnchoredLayout(anchoredStack);
    local anchorBar = anchoredStack[1];

    local stackBackground = anchoredLayout._stackBackground;
    if stackBackground then
        DrawWindowBackground(
            stackBackground.x,
            stackBackground.y,
            stackBackground.width,
            stackBackground.height,
            gConfig.hotbarGlobal or {}
        );
    end

    for barIndex = 1, data.NUM_BARS do
        local drawContext = {};
        local anchoredEntry = anchoredLayout[barIndex];

        if anchoredEntry then
            drawContext.resolvedPosition = { x = anchoredEntry.x, y = anchoredEntry.y };
            drawContext.metrics = anchoredEntry.metrics;
            drawContext.skipBackground = true;
            drawContext.isAnchorBar = (barIndex == anchorBar);
            drawContext.savePosition = (barIndex == anchorBar);
        end

        DrawBarWindow(barIndex, settings, drawContext);
    end

    if forcePositionReset then
        forcePositionReset = false;
    end

    -- Note: Macro palette, dragdrop.Render(), and outside drop handling are in init.lua
end

function M.HideWindow()
end

-- ============================================
-- Lifecycle
-- ============================================

function M.Initialize(settings)
    -- Register palette change callback for animation
    palette.OnPaletteChanged(OnPaletteChanged);
end

function M.UpdateVisuals(settings)
    -- Font/visual settings can change the measured width of cached abbreviations.
    -- Drop the per-slot cache so abbreviation strings and widths get recomputed
    -- against the new font on the next frame.
    ClearIconCache();
end

function M.SetHidden(hidden)
    if hidden then
        M.HideWindow();
    end
end

function M.Cleanup()
    texturesInitialized = false;
    -- Clear icon cache
    ClearIconCache();
    -- Clear pre-created closures so they're recreated on reinit
    slotInteraction = {};
    -- Clear slotrenderer cache
    slotrenderer.ClearAllCache();
end

-- Expose cache clear for external callers (e.g., when slot actions change)
function M.ClearIconCache()
    ClearIconCache();
end

-- Expose targeted cache clear for single slot updates (e.g., drag/drop)
function M.ClearIconCacheForSlot(barIndex, slotIndex)
    ClearIconCacheForSlot(barIndex, slotIndex);
end

-- Reset all bar positions to defaults (called when settings are reset)
-- Note: Hotbar uses forcePositionReset + nil positions instead of explicit defaults
-- because it has its own position pipeline with per-bar default calculation at render time.
function M.ResetPositions()
    forcePositionReset = true;
    if gConfig.windowPositions and gConfig.appliedPositions then
        for barIndex = 1, data.NUM_BARS do
            local windowName = string.format('Hotbar%d', barIndex);
            gConfig.windowPositions[windowName] = nil;
            gConfig.appliedPositions[windowName] = nil;
        end
    end
end

return M;
