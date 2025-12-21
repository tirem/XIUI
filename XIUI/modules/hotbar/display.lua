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
    -- Render a themed hotbar with three primitive buttons

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
    local buttonSize = iconSize;
    local buttonGap = 6;
    local buttonCount = 3;

    -- Compute content size to fit buttons + padding
    local contentWidth = (padding * 2) + (buttonSize * buttonCount) + (buttonGap * (buttonCount - 1));
    local contentHeight = (padding * 2) + buttonSize + 4 + imgui.GetTextLineHeight();

    -- Position (default top-left offset)
    local winX = 100;
    local winY = 100;

    -- Background options (use theme settings like partylist)
    local bgTheme = gConfig.hotbarBackgroundTheme or 'Plain';
    local bgScale = gConfig.hotbarBgScale or 1.0;
    local borderScale = gConfig.hotbarBorderScale or 1.0;
    local bgOpacity = gConfig.hotbarBackgroundOpacity or 0.87;
    local borderOpacity = gConfig.hotbarBorderOpacity or 1.0;

    local bgOptions = {
        theme = bgTheme,
        padding = padding,
        paddingY = padding,
        bgScale = bgScale,
        borderScale = borderScale,
        bgOpacity = bgOpacity,
        borderOpacity = borderOpacity,
    };

    -- Update background primitive
    windowBg.update(bgPrimHandle, winX, winY, contentWidth, contentHeight, bgOptions);

    -- Foreground draw list for text and overlays
    local drawList = drawing.GetUIDrawList();

    -- Draw title above the hotbar
    local title = 'Hotbar';
    local titleWidth = imgui.CalcTextSize(title) or 0;
    local titleX = winX + (contentWidth / 2) - (titleWidth / 2);
    local titleY = winY - imgui.GetTextLineHeight() - 6;
    drawList:AddText({titleX, titleY}, imgui.GetColorU32({0.9, 0.9, 0.9, 1.0}), title);

    -- Draw buttons inside the background using button.Draw
    local btnX = winX + padding;
    local btnY = winY + padding;

    for i = 1, buttonCount do
        local id = 'hotbar_btn_' .. i;
        local clicked, hovered = button.Draw(id, btnX, btnY, buttonSize, buttonSize, {
            colors = button.COLORS_NEUTRAL,
            rounding = 4,
            borderThickness = 1,
            tooltip = 'Hotbar Button #' .. i,
        });

        -- Draw a simple numeric label beneath each button
        local label = tostring(i);
        local labelW = imgui.CalcTextSize(label) or 0;
        local labelX = btnX + (buttonSize / 2) - (labelW / 2);
        local labelY = btnY + buttonSize + 4;
        drawList:AddText({labelX, labelY}, imgui.GetColorU32({0.9, 0.9, 0.9, 1.0}), label);

        -- Demo actions for each button (replace with configurable actions later)
        if clicked then
            if i == 1 then
                AshitaCore:GetChatManager():QueueCommand(-1, '/ma "Cure" <t>');
            elseif i == 2 then
                AshitaCore:GetChatManager():QueueCommand(-1, '/ma "Cure II" <t>');
            elseif i == 3 then
                AshitaCore:GetChatManager():QueueCommand(-1, '/ma "Protect" <t>');
            end
        end

        btnX = btnX + buttonSize + buttonGap;
    end
end

function M.HideWindow()
    if bgPrimHandle then
        windowBg.hide(bgPrimHandle);
    end

    -- Hide primitive-backed buttons
    button.HidePrim('hotbar_btn_1');
    button.HidePrim('hotbar_btn_2');
    button.HidePrim('hotbar_btn_3');
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
    button.DestroyPrim('hotbar_btn_1');
    button.DestroyPrim('hotbar_btn_2');
    button.DestroyPrim('hotbar_btn_3');
end

return M;
