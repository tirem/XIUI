--[[
* XIUI hotbar - Display Module
* Renders 6 independent hotbar windows with primitives and GDI fonts
]]--

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local ffi = require('ffi');
local windowBg = require('libs.windowbackground');
local drawing = require('libs.drawing');

local data = require('modules.hotbar.data');
local actions = require('modules.hotbar.actions');
local textures = require('modules.hotbar.textures');
local macropalette = require('modules.hotbar.macropalette');
local dragdrop = require('libs.dragdrop');

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

-- Draw a single hotbar slot using primitives and fonts
local function DrawSlot(barIndex, slotIndex, x, y, buttonSize, bind, barSettings)
    local slotPrim = data.slotPrims[barIndex] and data.slotPrims[barIndex][slotIndex];
    local keybindFont = data.keybindFonts[barIndex] and data.keybindFonts[barIndex][slotIndex];
    local labelFont = data.labelFonts[barIndex] and data.labelFonts[barIndex][slotIndex];

    -- Get per-bar display settings
    local showSlotFrame = barSettings and barSettings.showSlotFrame or false;
    local showActionLabels = barSettings and barSettings.showActionLabels or false;

    -- Check hover state first
    local mouseX, mouseY = imgui.GetMousePos();
    local isHovered = mouseX >= x and mouseX <= x + buttonSize and
                      mouseY >= y and mouseY <= y + buttonSize;

    -- Update slot background primitive
    if slotPrim then
        local texturePath = GetAssetsPath() .. 'slot.png';
        slotPrim.texture = texturePath;
        slotPrim.position_x = x;
        slotPrim.position_y = y;
        -- Don't set width/height (let it use texture's native size)
        -- Use scale to size the output to buttonSize
        -- slot.png is 40x40 pixels
        local textureSize = 40;
        local scale = buttonSize / textureSize;
        slotPrim.scale_x = scale;
        slotPrim.scale_y = scale;

        -- Get slot background color from per-bar settings
        local slotBgColor = barSettings and barSettings.slotBackgroundColor or 0xFFFFFFFF;

        -- Hover state: brighten on hover (blend with slot color)
        if isHovered then
            -- Darken the color slightly on hover (multiply RGB by ~0.8)
            local a = bit.rshift(bit.band(slotBgColor, 0xFF000000), 24);
            local r = math.floor(bit.rshift(bit.band(slotBgColor, 0x00FF0000), 16) * 0.8);
            local g = math.floor(bit.rshift(bit.band(slotBgColor, 0x0000FF00), 8) * 0.8);
            local b = math.floor(bit.band(slotBgColor, 0x000000FF) * 0.8);
            slotPrim.color = bit.bor(bit.lshift(a, 24), bit.lshift(r, 16), bit.lshift(g, 8), b);
        else
            slotPrim.color = slotBgColor;
        end

        -- Set visibility last, after all other properties are set
        slotPrim.visible = true;
    end

    -- Get keybind display text
    local keybindDisplay = data.GetKeybindDisplay(barIndex, slotIndex);

    -- Update keybind font
    if keybindFont then
        keybindFont:set_text(keybindDisplay);
        keybindFont:set_position_x(x + KEYBIND_OFFSET_X);
        keybindFont:set_position_y(y + KEYBIND_OFFSET_Y);
        -- Apply per-bar keybind size and color
        local keybindSize = barSettings and barSettings.keybindFontSize or 8;
        local keybindColor = barSettings and barSettings.keybindFontColor or 0xFFFFFFFF;
        keybindFont:set_font_height(keybindSize);
        keybindFont:set_font_color(keybindColor);
        keybindFont:set_visible(true);
    end

    -- Get action label and command
    local labelText = '';
    local command = nil;
    local spellIcon = nil;

    if bind then
        labelText = bind.displayName or bind.action or '';
        command, spellIcon = actions.BuildCommand(bind);
    end

    -- Action label (optional, shown outside/below the bar)
    if labelFont then
        if showActionLabels and labelText ~= '' then
            labelFont:set_text(labelText);
            -- Center the label under the slot (font has center alignment)
            local labelOffsetX = barSettings and barSettings.actionLabelOffsetX or 0;
            local labelOffsetY = barSettings and barSettings.actionLabelOffsetY or 0;
            labelFont:set_position_x(x + (buttonSize / 2) + labelOffsetX);
            labelFont:set_position_y(y + buttonSize + data.LABEL_GAP + labelOffsetY);
            labelFont:set_visible(true);
        else
            labelFont:set_visible(false);
        end
    end

    -- Draw spell icon and optional frame using ImGui window draw list
    -- (Use window draw list so tooltips render on top)
    local drawList = imgui.GetWindowDrawList();
    if drawList then
        -- Draw spell icon if available
        if spellIcon and spellIcon.image then
            local iconPtr = tonumber(ffi.cast("uint32_t", spellIcon.image));
            if iconPtr then
                local iconPadding = buttonSize * 0.125;
                local iconSize = buttonSize * 0.75;
                drawList:AddImage(iconPtr,
                    {x + iconPadding, y + iconPadding},
                    {x + iconPadding + iconSize, y + iconPadding + iconSize}
                );
            end
        end

        -- Draw frame overlay if enabled in per-bar settings
        if showSlotFrame then
            local frameTexture = textures:Get('frame');
            if frameTexture and frameTexture.image then
                local framePtr = tonumber(ffi.cast("uint32_t", frameTexture.image));
                if framePtr then
                    drawList:AddImage(framePtr, {x, y}, {x + buttonSize, y + buttonSize});
                end
            end
        end

        -- Draw hover effect when mouse is over the slot
        if isHovered and not dragdrop.IsDragging() then
            local hoverTintColor = imgui.GetColorU32({1.0, 1.0, 1.0, 0.15});  -- White at 15% opacity
            local hoverBorderColor = imgui.GetColorU32({1.0, 1.0, 1.0, 0.10});  -- White at 10% opacity
            drawList:AddRectFilled(
                {x, y},
                {x + buttonSize, y + buttonSize},
                hoverTintColor,
                2  -- slight rounding
            );
            drawList:AddRect(
                {x, y},
                {x + buttonSize, y + buttonSize},
                hoverBorderColor,
                2,  -- slight rounding
                0,
                1   -- border thickness
            );
        end
    end

    -- Draw tooltip when hovering over a slot with content
    if isHovered and bind and not dragdrop.IsDragging() then
        -- Style the tooltip
        imgui.PushStyleColor(ImGuiCol_PopupBg, {0.067, 0.063, 0.055, 0.95});
        imgui.PushStyleColor(ImGuiCol_Border, {0.3, 0.28, 0.24, 0.8});
        imgui.PushStyleColor(ImGuiCol_Text, {0.9, 0.9, 0.9, 1.0});
        imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {8, 6});
        imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 4);

        imgui.BeginTooltip();

        -- Action name (gold color)
        local actionName = bind.displayName or bind.action or 'Unknown';
        imgui.TextColored({0.957, 0.855, 0.592, 1.0}, actionName);

        -- Action type
        local typeLabels = {
            ma = 'Spell',
            ja = 'Ability',
            ws = 'Weaponskill',
            item = 'Item',
            equip = 'Equip',
            macro = 'Macro',
            pet = 'Pet Command',
        };
        local typeLabel = typeLabels[bind.actionType] or bind.actionType or '?';

        imgui.Spacing();
        imgui.TextColored({0.6, 0.6, 0.6, 1.0}, 'Type: ' .. typeLabel);

        -- Target (if applicable)
        if bind.target and bind.actionType ~= 'equip' and bind.actionType ~= 'macro' then
            imgui.TextColored({0.6, 0.6, 0.6, 1.0}, 'Target: <' .. bind.target .. '>');
        end

        -- Equipment slot (if equip type)
        if bind.actionType == 'equip' and bind.equipSlot then
            local slotLabels = {
                main = 'Main Hand', sub = 'Sub/Shield', range = 'Range', ammo = 'Ammo',
                head = 'Head', body = 'Body', hands = 'Hands', legs = 'Legs', feet = 'Feet',
                neck = 'Neck', waist = 'Waist', ear1 = 'Ear 1', ear2 = 'Ear 2',
                ring1 = 'Ring 1', ring2 = 'Ring 2', back = 'Back',
            };
            local slotLabel = slotLabels[bind.equipSlot] or bind.equipSlot;
            imgui.TextColored({0.6, 0.6, 0.6, 1.0}, 'Slot: ' .. slotLabel);
        end

        -- Macro text (if macro type)
        if bind.actionType == 'macro' and bind.macroText then
            imgui.TextColored({0.6, 0.6, 0.6, 1.0}, 'Command:');
            imgui.TextColored({0.5, 0.7, 0.5, 1.0}, bind.macroText);
        end

        -- Custom icon indicator
        if bind.customIconType then
            imgui.Spacing();
            imgui.TextColored({0.4, 0.4, 0.4, 1.0}, '(Custom icon)');
        end

        imgui.EndTooltip();

        imgui.PopStyleVar(2);
        imgui.PopStyleColor(3);
    end

    -- Handle drag & drop with ImGui invisible button overlay
    imgui.SetCursorScreenPos({x, y});
    local buttonId = string.format('##hotbarslot_%d_%d', barIndex, slotIndex);
    imgui.InvisibleButton(buttonId, {buttonSize, buttonSize});

    local isItemHovered = imgui.IsItemHovered();
    local isItemActive = imgui.IsItemActive();

    -- Drag source (if slot has content)
    if bind and isItemActive and imgui.IsMouseDragging(0, 3) then
        if not dragdrop.IsDragging() and not dragdrop.IsDragPending() then
            macropalette.StartDragSlot(barIndex, slotIndex, bind);
        end
    end

    -- Drop zone - register this slot as a valid drop target
    local zoneId = string.format('hotbar_%d_%d', barIndex, slotIndex);
    local dropped = dragdrop.DropZone(zoneId, x, y, buttonSize, buttonSize, {
        accepts = {'macro', 'slot'},
        highlightColor = 0xA8FFFFFF,  -- White at 66% opacity
        onDrop = function(payload)
            macropalette.HandleDropOnSlot(payload, barIndex, slotIndex);
        end,
    });

    -- Handle click interaction on mouse RELEASE (not click)
    -- Only execute if: hovering, mouse released, has command, not dragging, and no drag was attempted
    if isItemHovered and imgui.IsMouseReleased(0) and command then
        if not dragdrop.IsDragging() and not dragdrop.WasDragAttempted() then
            AshitaCore:GetChatManager():QueueCommand(-1, command);
        end
    end

    -- Right-click to clear slot
    if isItemHovered and imgui.IsMouseClicked(1) and bind then
        macropalette.ClearSlot(barIndex, slotIndex);
    end

    return isHovered;
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
        -- Hide unused slot primitives
        for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
            if data.slotPrims[barIndex] and data.slotPrims[barIndex][slotIndex] then
                data.slotPrims[barIndex][slotIndex].visible = false;
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
        if data.keybindFonts[barIndex] and data.keybindFonts[barIndex][hiddenSlot] then
            data.keybindFonts[barIndex][hiddenSlot]:set_visible(false);
        end
        if data.labelFonts[barIndex] and data.labelFonts[barIndex][hiddenSlot] then
            data.labelFonts[barIndex][hiddenSlot]:set_visible(false);
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

        for row = 1, layout.rows do
            for col = 1, layout.columns do
                if slotIndex <= slotCount then
                    local slotX = windowPosX + padding + (col - 1) * (buttonSize + buttonGap);
                    local slotY = windowPosY + padding + (row - 1) * (buttonSize + rowGap);

                    local bind = data.GetKeybindForSlot(barIndex, slotIndex);
                    DrawSlot(barIndex, slotIndex, slotX, slotY, buttonSize, bind, barSettings);
                end
                slotIndex = slotIndex + 1;
            end
        end

        -- Hide unused slot primitives and fonts
        for hiddenSlot = slotCount + 1, data.MAX_SLOTS_PER_BAR do
            if data.slotPrims[barIndex] and data.slotPrims[barIndex][hiddenSlot] then
                data.slotPrims[barIndex][hiddenSlot].visible = false;
            end
            if data.keybindFonts[barIndex] and data.keybindFonts[barIndex][hiddenSlot] then
                data.keybindFonts[barIndex][hiddenSlot]:set_visible(false);
            end
            if data.labelFonts[barIndex] and data.labelFonts[barIndex][hiddenSlot] then
                data.labelFonts[barIndex][hiddenSlot]:set_visible(false);
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
