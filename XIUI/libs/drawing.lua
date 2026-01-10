--[[
* XIUI Drawing Utilities
* Drawing primitives for rectangles, circles with optional shadows
]]--

local imgui = require('imgui');

local M = {};

-- ========================================
-- Internal Implementation
-- ========================================

-- Process shadow config and return shadow properties
-- Returns: offsetX, offsetY, shadowColorU32, or nil if no shadow
local function processShadowConfig(shadowConfig)
    if not shadowConfig then
        return nil;
    end

    local shadowOffsetX = shadowConfig.offsetX or 2;
    local shadowOffsetY = shadowConfig.offsetY or 2;
    local shadowColor = shadowConfig.color or 0x80000000;

    -- Apply alpha override if specified
    if shadowConfig.alpha then
        local baseColor = bit.band(shadowColor, 0x00FFFFFF);
        local alpha = math.floor(math.clamp(shadowConfig.alpha, 0, 1) * 255);
        shadowColor = bit.bor(baseColor, bit.lshift(alpha, 24));
    end

    local shadowColorU32 = imgui.GetColorU32(shadowColor);
    return shadowOffsetX, shadowOffsetY, shadowColorU32;
end

-- Eliminates code duplication between draw_rect and draw_rect_background
local function draw_rect_impl(top_left, bot_right, color, radius, fill, shadowConfig, drawList)
    -- Draw shadow first if configured
    local shadowOffsetX, shadowOffsetY, shadowColorU32 = processShadowConfig(shadowConfig);
    if shadowOffsetX then
        local shadow_top_left = {top_left[1] + shadowOffsetX, top_left[2] + shadowOffsetY};
        local shadow_bot_right = {bot_right[1] + shadowOffsetX, bot_right[2] + shadowOffsetY};
        local shadowDimensions = {
            { shadow_top_left[1], shadow_top_left[2] },
            { shadow_bot_right[1], shadow_bot_right[2] }
        };

        if (fill == true) then
            drawList:AddRectFilled(shadowDimensions[1], shadowDimensions[2], shadowColorU32, radius, ImDrawCornerFlags_All);
        else
            drawList:AddRect(shadowDimensions[1], shadowDimensions[2], shadowColorU32, radius, ImDrawCornerFlags_All, 1);
        end
    end

    -- Draw main rectangle
    local colorU32 = imgui.GetColorU32(color);
    local dimensions = {
        { top_left[1], top_left[2] },
        { bot_right[1], bot_right[2] }
    };
    if (fill == true) then
        drawList:AddRectFilled(dimensions[1], dimensions[2], colorU32, radius, ImDrawCornerFlags_All);
    else
        drawList:AddRect(dimensions[1], dimensions[2], colorU32, radius, ImDrawCornerFlags_All, 1);
    end
end

-- ========================================
-- Public API: Rectangle Drawing
-- ========================================

-- Draw rectangle using window draw list
function M.draw_rect(top_left, bot_right, color, radius, fill, shadowConfig)
    draw_rect_impl(top_left, bot_right, color, radius, fill, shadowConfig, imgui.GetWindowDrawList());
end

-- Draw rectangle using background draw list
function M.draw_rect_background(top_left, bot_right, color, radius, fill, shadowConfig)
    draw_rect_impl(top_left, bot_right, color, radius, fill, shadowConfig, imgui.GetBackgroundDrawList());
end

-- ========================================
-- Public API: Circle Drawing
-- ========================================

function M.draw_circle(center, radius, color, segments, fill, shadowConfig, drawList)
    drawList = drawList or imgui.GetWindowDrawList();

    -- Draw shadow first if configured
    local shadowOffsetX, shadowOffsetY, shadowColorU32 = processShadowConfig(shadowConfig);
    if shadowOffsetX then
        local shadow_center = {center[1] + shadowOffsetX, center[2] + shadowOffsetY};

        if (fill == true) then
            drawList:AddCircleFilled(shadow_center, radius, shadowColorU32, segments);
        else
            drawList:AddCircle(shadow_center, radius, shadowColorU32, segments, 1);
        end
    end

    -- Draw main circle
    local colorU32 = imgui.GetColorU32(color);

    if (fill == true) then
        drawList:AddCircleFilled(center, radius, colorU32, segments);
    else
        drawList:AddCircle(center, radius, colorU32, segments, 1);
    end
end

-- ========================================
-- Draw List Selection
-- ========================================

-- Get the appropriate draw list for UI rendering
-- Returns WindowDrawList when config is open (so config stays on top)
-- Returns ForegroundDrawList otherwise (so UI elements render on top of game)
-- Note: showConfig is a global from XIUI.lua
function M.GetUIDrawList()
    if showConfig and showConfig[1] then
        return imgui.GetWindowDrawList();
    else
        return imgui.GetForegroundDrawList();
    end
end

return M;
