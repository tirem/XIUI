--[[
* XIUI hotbar - Display Module
]]--

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local ffi = require('ffi');
local d3d8 = require('d3d8');
local windowBg = require('libs.windowbackground');
local progressbar = require('libs.progressbar');
local button = require('libs.button');
local data = require('modules.hotbar.data');
local actions = require('modules.hotbar.actions');

local M = {};

-- ============================================
-- Constants
-- ============================================

local ICON_SIZE = 24;
local ROW_HEIGHT = 32;  -- Icon (24) + top offset (2) + gap (4) + bar (3) - 1
local PADDING = 8;
local ICON_TEXT_GAP = 6;
local ROW_SPACING = 4;
local BAR_HEIGHT = 3;

-- Keybind text positioning
local KEYBIND_OFFSET = 0.04;  -- relative to button size

local HORIZONTAL_COLUMNS = 12; -- buttons per row
local HORIZONTAL_ROWS = 4; -- number of HORIZONTAL_ROWS

local VERTICAL_HOTBAR_COLUMNS = 2;
local VERTICAL_HOTBAR_ROWS = 6;
local VERTICAL_HOTBARS_COUNT = 2;
local VERTICAL_HOTBAR_SPACING = 20; -- spacing between vertical hotbars

-- Hotbar number label spacing
local HORIZONTAL_HOTBAR_NUMBER_OFFSET = 12; -- horizontal offset for left-side hotbar numbers
local HORIZONTAL_HOTBAR_NUMBER_POSITION = 2; -- x position of hotbar number text
local VERTICAL_HOTBAR_NUMBER_SPACING = 10; -- vertical spacing below vertical hotbars for number
local VERTICAL_HOTBAR_NUMBER_POSITION = 2; -- y position of hotbar number text below

-- Keybind constants for hotbar HORIZONTAL_ROWS
local KEYBIND_SHIFT = 12;
local KEYBIND_CTRL = 24;
local KEYBIND_ALT = 36;
local KEYBIND_BASE = 48;


-- ============================================
-- State
-- ============================================

-- Background primitive handle
local bgPrimHandle = nil;

-- Theme tracking (for detecting changes like petbar)
local loadedBgTheme = nil;

-- Item icon cache (itemId -> texture table with .image)
local iconCache = {};

-- Tab state: 1 = Pool view, 2 = History view
local selectedTab = 1;

-- ============================================
-- Item Icon Loading
-- ============================================

-- ============================================
-- Helper Functions
-- ============================================

-- ============================================
-- History View Constants
-- ============================================


-- ============================================
-- Treasure Pool Window
-- ============================================

-- Helper to build a comma-separated list of names

local drawing = require('libs.drawing');

function M.DrawWindow(settings)
    -- Render a themed hotbar with two HORIZONTAL_ROWS of buttons (10 per row, 20 total) using an imgui window

    -- Validate primitive
    if not bgPrimHandle then
        return;
    end

    -- Scales from config
    local scaleX = gConfig.hotbarScaleX or 1.0;
    local scaleY = gConfig.hotbarScaleY or 1.0;

    -- Dimensions
    local iconSize = math.floor(ICON_SIZE * scaleY);
    local padding = PADDING;

    -- Button layout
    local buttonGap = 12; -- increased horizontal spacing between buttons

    -- Determine button size to fit text ("Button Text") plus padding, then apply configured button scale
    local sampleLabel = 'Horizon2';
    local labelPadding = 12; -- horizontal padding to give breathing room for text
    local baseButtonSize = 100
    local button_scale = gConfig.hotbarButtonScale or 0.56; -- final scale (default ~56%)
    local buttonSize = math.max(8, math.floor(baseButtonSize * button_scale));

    -- Label spacing and heights
    local labelGap = 4;
    local textHeight = imgui.GetTextLineHeight();
    local rowGap = 6; -- vertical gap between HORIZONTAL_ROWS

    -- Compute content size for main hotbar
    local mainHotbarWidth = (buttonSize * HORIZONTAL_COLUMNS) + (buttonGap * (HORIZONTAL_COLUMNS - 1)) + HORIZONTAL_HOTBAR_NUMBER_OFFSET;
    local mainHotbarHeight = (buttonSize + labelGap + textHeight) * HORIZONTAL_ROWS + (rowGap * (HORIZONTAL_ROWS - 1));
    
    -- Compute content size for side hotbars (5, 6, 7)
    local verticalHotbarWidth = (buttonSize * VERTICAL_HOTBAR_COLUMNS) + (buttonGap * (VERTICAL_HOTBAR_COLUMNS - 1));
    local verticalHotbarHeight = (buttonSize + labelGap + textHeight) * VERTICAL_HOTBAR_ROWS + (rowGap * (VERTICAL_HOTBAR_ROWS - 1)) + VERTICAL_HOTBAR_NUMBER_SPACING;
    
    -- Compute total content size (main hotbar + gap + vertical hotbars)
    local verticalMargin = 50; -- margin between horizontal and vertical hotbars
    local verticalHotbarsExtraMargin = (VERTICAL_HOTBARS_COUNT - 1) * VERTICAL_HOTBAR_SPACING; -- accumulated margin from loop
    local contentWidth = (padding * 2) + mainHotbarWidth + verticalMargin + (verticalHotbarWidth * VERTICAL_HOTBARS_COUNT) + (buttonGap * (VERTICAL_HOTBARS_COUNT - 1)) + verticalHotbarsExtraMargin;
    local contentHeight = (padding * 2) + math.max(mainHotbarHeight, verticalHotbarHeight);

    -- Background options (use theme settings like partylist)
    local bgTheme = gConfig.hotbarBackgroundTheme or 'Plain';
    local bgScale = gConfig.hotbarBgScale or 1.0;
    local borderScale = gConfig.hotbarBorderScale or 1.0;
    local bgOpacity = gConfig.hotbarBackgroundOpacity or 0.87;
    local borderOpacity = gConfig.hotbarBorderOpacity or 1.0;

    -- Apply theme change safely
    if loadedBgTheme ~= bgTheme and bgPrimHandle then
        loadedBgTheme = bgTheme;
        pcall(function()
            windowBg.setTheme(bgPrimHandle, bgTheme, bgScale, borderScale);
        end);
    end

    -- Determine colors: prefer user color customization for hotbar, else fall back to theme sensible defaults
    local hotbarColors = gConfig and gConfig.colorCustomization and gConfig.colorCustomization.hotbar;
    local bgColor = hotbarColors and hotbarColors.bgColor or nil;
    local borderColor = hotbarColors and hotbarColors.borderColor or nil;

    if not bgColor then
        if bgTheme == 'Plain' then
            bgColor = 0xFF1A1A1A; -- dark tint for plain
        else
            bgColor = 0xFFFFFFFF; -- white (no tint) for themed textures
        end
    end
    if not borderColor then
        borderColor = 0xFFFFFFFF;
    end

    -- Use saved state if present (for drag-to-move later)
    local savedX = (gConfig.hotbarState and gConfig.hotbarState.x) or 1000;
    local savedY = (gConfig.hotbarState and gConfig.hotbarState.y) or 1000;

    local bgOptions = {
        theme = bgTheme,
        padding = padding,
        paddingY = padding,
        bgScale = bgScale,
        borderScale = borderScale,
        bgOpacity = bgOpacity,
        borderOpacity = borderOpacity,
        bgColor = bgColor,
        borderColor = borderColor,
    };

    -- Use an imgui window (no decoration / no background) to get a consistent position/size like PartyWindow
    local windowFlags = GetBaseWindowFlags(gConfig.lockPositions);

    local windowName = 'Hotbar';

    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {0,0});
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { buttonGap, 0 });
    -- Only set position on first use, then let ImGui track dragging
    imgui.SetNextWindowPos({savedX, savedY}, ImGuiCond_FirstUseEver);

    local imguiPosX, imguiPosY;
    if (imgui.Begin(windowName, true, windowFlags)) then
        imguiPosX, imguiPosY = imgui.GetWindowPos();

        -- Reserve window space IMMEDIATELY after Begin()
        -- This tells imgui about the window bounds before any button drawing
        imgui.Dummy({contentWidth, contentHeight});

        -- Foreground draw list for text and overlays
        local drawList = drawing.GetUIDrawList();

        -- Draw title above the hotbar (centered)
        local title = 'Hotbar';
        local titleWidth = imgui.CalcTextSize(title) or 0;
        local titleX = imguiPosX + (contentWidth / 2) - (titleWidth / 2);
        local titleY = imguiPosY - imgui.GetTextLineHeight() - 6;
        drawList:AddText({titleX, titleY}, imgui.GetColorU32({0.9, 0.9, 0.9, 1.0}), title);

        -- Draw main hotbar (4 rows x 10 columns)
        local idx = 1;
        for row = 1, HORIZONTAL_ROWS do
            local btnX = imguiPosX + padding + HORIZONTAL_HOTBAR_NUMBER_OFFSET;
            local btnY = imguiPosY + padding + (row - 1) * (buttonSize + labelGap + textHeight + rowGap);
            
            -- Draw hotbar number to the left
            local hotbarNumber = tostring(row);
            local hotbarNumX = imguiPosX + padding + HORIZONTAL_HOTBAR_NUMBER_POSITION;
            local hotbarNumY = btnY + (buttonSize - imgui.GetTextLineHeight()) / 2; -- center vertically
            drawList:AddText({hotbarNumX, hotbarNumY}, imgui.GetColorU32({0.8, 0.8, 0.8, 1.0}), hotbarNumber);
            
            for column = 1, HORIZONTAL_COLUMNS do
                local id = 'hotbar_btn_' .. idx;
                local labelText = (idx == 1) and 'Cure' or sampleLabel;
                
                -- Determine display text for special buttons
                local displayText = labelText;
                if column == 11 then
                    displayText = '-';
                elseif column == 12 then
                    displayText = '+';
                end
                
                local clicked, hovered = button.Draw(id, btnX, btnY, buttonSize, buttonSize, {
                    colors = button.COLORS_NEUTRAL,
                    rounding = 4,
                    borderThickness = 1,
                    tooltip = displayText,
                });

                -- Draw keybind in top-left corner of button
                local keybindX = btnX + buttonSize * KEYBIND_OFFSET;
                local keybindY = btnY + buttonSize * KEYBIND_OFFSET;

                local keybindDisplay = '';
                if(idx <= KEYBIND_SHIFT) then
                    keybindDisplay = 'S-' .. tostring(column);
                elseif(idx <= KEYBIND_CTRL) then
                    keybindDisplay = 'C-' .. tostring(column);                    
                elseif(idx <= KEYBIND_ALT) then
                    keybindDisplay = 'A-' .. tostring(column);
                else
                    keybindDisplay = tostring(column);
                end

                drawList:AddText({keybindX, keybindY}, imgui.GetColorU32({0.7, 0.7, 0.7, 1.0}), keybindDisplay);

                -- Draw label beneath each button
                local labelX = btnX;
                local labelY = btnY + buttonSize + labelGap;
                drawList:AddText({labelX, labelY}, imgui.GetColorU32({0.9, 0.9, 0.9, 1.0}), displayText);

                -- Demo action for the first button
                if clicked then
                    if idx == 1 then
                        AshitaCore:GetChatManager():QueueCommand(-1, '/ma "Cure" <t>');
                    end
                end

                btnX = btnX + buttonSize + buttonGap;
                idx = idx + 1;
            end
        end
        
        -- Draw vertical hotbars (5, 6, 7) - each with 4 rows x 2 columns
        local verticalStartX = imguiPosX + padding + mainHotbarWidth + verticalMargin;
        local hotbarMargin = 0;
        for hotbarNum = 1, VERTICAL_HOTBARS_COUNT do
            local hotbarOffsetX = verticalStartX + (hotbarNum - 1) * (verticalHotbarWidth + buttonGap) + hotbarMargin;
            local verticalIdx = 1;
            for row = 1, VERTICAL_HOTBAR_ROWS do
                local btnX = hotbarOffsetX;
                local btnY = imguiPosY + padding + (row - 1) * (buttonSize + labelGap + textHeight + rowGap);
                for column = 1, VERTICAL_HOTBAR_COLUMNS do
                    local buttonIndex = (hotbarNum - 1) * (VERTICAL_HOTBAR_ROWS * VERTICAL_HOTBAR_COLUMNS) + verticalIdx;
                    local id = 'hotbar_vertical_btn_' .. buttonIndex;
                    local labelText = 'Vertic' .. hotbarNum;
                    
                    -- Determine display text for special buttons
                    local displayText = labelText;
                    if verticalIdx == 11 then
                        displayText = '-';
                    elseif verticalIdx == 12 then
                        displayText = '+';
                    end
                    
                    local clicked, hovered = button.Draw(id, btnX, btnY, buttonSize, buttonSize, {
                        colors = button.COLORS_NEUTRAL,
                        rounding = 4,
                        borderThickness = 1,
                        tooltip = displayText,
                    });

                    -- Draw keybind in top-left corner of button
                    local keybindX = btnX + buttonSize * KEYBIND_OFFSET;
                    local keybindY = btnY + buttonSize * KEYBIND_OFFSET;
                    
                    if hotbarNum == 1 then
                        keybindDisplay = 'C-S-' .. tostring(verticalIdx);
                    else
                        keybindDisplay = 'C-A-' .. tostring(verticalIdx);
                    end
                    
                    drawList:AddText({keybindX, keybindY}, imgui.GetColorU32({0.7, 0.7, 0.7, 1.0}), keybindDisplay);

                    -- Draw label beneath each button
                    local labelX = btnX;
                    local labelY = btnY + buttonSize + labelGap;
                    drawList:AddText({labelX, labelY}, imgui.GetColorU32({0.9, 0.9, 0.9, 1.0}), displayText);

                    btnX = btnX + buttonSize + buttonGap;
                    verticalIdx = verticalIdx + 1;
                end
            end
            
            -- Draw hotbar number below vertical hotbar
            local hotbarNumber = tostring(4 + hotbarNum);
            local hotbarNumX = hotbarOffsetX + (verticalHotbarWidth / 2) - (imgui.CalcTextSize(hotbarNumber) / 2);
            local hotbarNumY = imguiPosY + padding + VERTICAL_HOTBAR_ROWS * (buttonSize + labelGap + textHeight + rowGap) + VERTICAL_HOTBAR_NUMBER_POSITION;
            drawList:AddText({hotbarNumX, hotbarNumY}, imgui.GetColorU32({0.8, 0.8, 0.8, 1.0}), hotbarNumber);
            
            hotbarMargin = hotbarMargin + VERTICAL_HOTBAR_SPACING;
        end

        -- Update background primitive using imgui window position
        pcall(function()
            windowBg.update(bgPrimHandle, imguiPosX, imguiPosY, contentWidth, contentHeight, bgOptions);
        end);

        imgui.End();
    end

    imgui.PopStyleVar(2);

    -- Save window position after dragging
    -- Get the current window position (in case it was dragged)
    local finalX, finalY = imguiPosX, imguiPosY;
    if imguiPosX ~= nil then
        -- The window was rendered, so we can try to get its final position
        -- Note: GetWindowPos only works inside Begin/End, so we use the value from inside
        if gConfig.hotbarState == nil then
            gConfig.hotbarState = {};
        end
        
        -- Only save if position has changed
        if gConfig.hotbarState.x ~= finalX or gConfig.hotbarState.y ~= finalY then
            gConfig.hotbarState.x = finalX;
            gConfig.hotbarState.y = finalY;
        end
    end
end

function M.HideWindow()
    if bgPrimHandle then
        windowBg.hide(bgPrimHandle);
    end

    -- Hide main hotbar buttons
    for i = 1, HORIZONTAL_ROWS * HORIZONTAL_COLUMNS do
        button.HidePrim('hotbar_btn_' .. i);
    end
    
    -- Hide side hotbar buttons
    for i = 1, VERTICAL_HOTBARS_COUNT * VERTICAL_HOTBAR_ROWS * VERTICAL_HOTBAR_COLUMNS do
        button.HidePrim('hotbar_vertical_btn_' .. i);
    end
end

-- ============================================
-- Lifecycle
-- ============================================

function M.Initialize(settings)
    -- Get background theme and scales from config (with defaults)
    local bgTheme = gConfig.hotbarBackgroundTheme or 'Plain';
    local bgScale = gConfig.hotbarBgScale or 1.0;
    local borderScale = gConfig.hotbarBorderScale or 1.0;
    loadedBgTheme = bgTheme;

    -- Create background primitive (fonts created by init.lua)
    local primData = {
        visible = false,
        can_focus = false,
        locked = true,
        width = 100,
        height = 100,
    };
    bgPrimHandle = windowBg.create(primData, bgTheme, bgScale, borderScale);
end

function M.UpdateVisuals(settings)
    -- Check if theme changed
    local bgTheme = gConfig.hotbarBackgroundTheme or 'Plain';
    local bgScale = gConfig.hotbarBgScale or 1.0;
    local borderScale = gConfig.hotbarBorderScale or 1.0;
    if loadedBgTheme ~= bgTheme and bgPrimHandle then
        loadedBgTheme = bgTheme;
        windowBg.setTheme(bgPrimHandle, bgTheme, bgScale, borderScale);
    end
end

function M.SetHidden(hidden)
    if hidden then
        M.HideWindow();
    end
end

function M.Cleanup()
    if bgPrimHandle then
        windowBg.destroy(bgPrimHandle);
        bgPrimHandle = nil;
    end

    -- Destroy main hotbar buttons
    for i = 1, HORIZONTAL_ROWS * HORIZONTAL_COLUMNS do
        button.DestroyPrim('hotbar_btn_' .. i);
    end
    
    -- Destroy side hotbar buttons
    for i = 1, VERTICAL_HOTBARS_COUNT * VERTICAL_HOTBAR_ROWS * VERTICAL_HOTBAR_COLUMNS do
        button.DestroyPrim('hotbar_vertical_btn_' .. i);
    end
end

return M;
