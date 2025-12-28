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

local HORIZONTAL_COLUMNS = 10; -- buttons per row
local HORIZONTAL_ROWS = 4; -- number of HORIZONTAL_ROWS

-- Keybind constants for hotbar HORIZONTAL_ROWS
local KEYBIND_SHIFT = 10;
local KEYBIND_CTRL = 20;
local KEYBIND_ALT = 30;
local KEYBIND_BASE = 40;


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
    local sampleLabel = 'Shellra2';
    local labelPadding = 12; -- horizontal padding to give breathing room for text
    local baseButtonSize = 100
    local button_scale = gConfig.hotbarButtonScale or 0.56; -- final scale (default ~56%)
    local buttonSize = math.max(8, math.floor(baseButtonSize * button_scale));

    -- Label spacing and heights
    local labelGap = 4;
    local textHeight = imgui.GetTextLineHeight();
    local rowGap = 6; -- vertical gap between HORIZONTAL_ROWS

    -- Compute content size to fit buttons + padding + labels and inter-row gap
    local contentWidth = (padding * 2) + (buttonSize * HORIZONTAL_COLUMNS) + (buttonGap * (HORIZONTAL_COLUMNS - 1));
    local contentHeight = (padding * 2) + (buttonSize + labelGap + textHeight) * HORIZONTAL_ROWS + (rowGap * (HORIZONTAL_ROWS - 1));

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
    local windowFlags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoBringToFrontOnFocus, ImGuiWindowFlags_NoDocking);
    if (gConfig.lockPositions) then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
    end

    local windowName = 'Hotbar';

    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {0,0});
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { buttonGap, 0 });
    imgui.SetNextWindowPos({savedX, savedY});

    local imguiPosX, imguiPosY;
    if (imgui.Begin(windowName, true, windowFlags)) then
        imguiPosX, imguiPosY = imgui.GetWindowPos();

        -- Foreground draw list for text and overlays
        local drawList = drawing.GetUIDrawList();

        -- Draw title above the hotbar (centered)
        local title = 'Hotbar';
        local titleWidth = imgui.CalcTextSize(title) or 0;
        local titleX = imguiPosX + (contentWidth / 2) - (titleWidth / 2);
        local titleY = imguiPosY - imgui.GetTextLineHeight() - 6;
        drawList:AddText({titleX, titleY}, imgui.GetColorU32({0.9, 0.9, 0.9, 1.0}), title);

        -- Draw buttons inside the background using button. Draw in a HORIZONTAL_ROWS x HORIZONTAL_COLUMNS grid
        local idx = 1;
        for row = 1, HORIZONTAL_ROWS do
            local btnX = imguiPosX + padding;
            local btnY = imguiPosY + padding + (row - 1) * (buttonSize + labelGap + textHeight + rowGap);
            for column = 1, HORIZONTAL_COLUMNS do
                local id = 'hotbar_btn_' .. idx;
                local labelText = (idx == 1) and 'Cure' or sampleLabel;
                local clicked, hovered = button.Draw(id, btnX, btnY, buttonSize, buttonSize, {
                    colors = button.COLORS_NEUTRAL,
                    rounding = 4,
                    borderThickness = 1,
                    tooltip = labelText,
                });

                -- Draw keybind in top-left corner of button
                local keybindX = btnX + 4;
                local keybindY = btnY + 2;

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
                drawList:AddText({labelX, labelY}, imgui.GetColorU32({0.9, 0.9, 0.9, 1.0}), labelText);

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

        -- Force window content size so the window background primitive matches
        imgui.Dummy({contentWidth, contentHeight});

        -- Update background primitive using imgui window position
        pcall(function()
            windowBg.update(bgPrimHandle, imguiPosX, imguiPosY, contentWidth, contentHeight, bgOptions);
        end);
    end

    imgui.PopStyleVar(2);
end

function M.HideWindow()
    if bgPrimHandle then
        windowBg.hide(bgPrimHandle);
    end

    -- Hide primitive-backed buttons
    for i = 1, HORIZONTAL_ROWS * HORIZONTAL_COLUMNS do
        button.HidePrim('hotbar_btn_' .. i);
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

    -- Destroy primitive-backed buttons
    for i = 1, HORIZONTAL_ROWS * HORIZONTAL_COLUMNS do
        button.DestroyPrim('hotbar_btn_' .. i);
    end
end

return M;
