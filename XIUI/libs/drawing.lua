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
        return imgui.GetBackgroundDrawList();
    else
        return imgui.GetForegroundDrawList();
    end
end

-- ========================================
-- Move Anchor Widget
-- ========================================

-- Track which anchors are currently being dragged (via ImGui window)
local anchorDragging = {};

-- Default anchor configuration (XIUI theme colors)
-- Gold: {0.957, 0.855, 0.592} = 0xF4DA97
-- GoldDark: {0.765, 0.684, 0.474} = 0xC3AE79
-- GoldDarker: {0.573, 0.512, 0.355} = 0x92835B
-- BgMedium: {0.098, 0.090, 0.075} = 0x191713
-- BgLight: {0.137, 0.125, 0.106} = 0x23201B
-- BorderDark: {0.3, 0.275, 0.235} = 0x4D463C
local ANCHOR_DEFAULTS = {
    size = 20,
    dotSize = 2,
    dotSpacingX = 6,
    dotSpacingY = 5,
    padding = 4,
    rounding = 3,
    bgColor = 0xEE191713,           -- bgMedium with high alpha
    bgColorActive = 0xEE23201B,     -- bgLight with high alpha
    borderColor = 0xCC4D463C,       -- borderDark
    borderColorActive = 0xFFF4DA97, -- gold
    dotColor = 0xFFC3AE79,          -- goldDark
    dotColorActive = 0xFFF4DA97,    -- gold
};

---Draw a move anchor for repositioning a window
---Uses a dummy ImGui window for native drag handling
---@param id string Unique identifier for this anchor
---@param windowX number Current window X position
---@param windowY number Current window Y position
---@param options table|nil Optional configuration (size, padding, colors, etc.)
---@return number|nil newX New X position if dragged, nil otherwise
---@return number|nil newY New Y position if dragged, nil otherwise
function M.DrawMoveAnchor(id, windowX, windowY, options)
    -- Only show when config menu is open
    if not showConfig or not showConfig[1] then
        return nil, nil;
    end

    options = options or {};
    local size = options.size or ANCHOR_DEFAULTS.size;
    local dotSize = options.dotSize or ANCHOR_DEFAULTS.dotSize;
    local dotSpacingX = options.dotSpacingX or ANCHOR_DEFAULTS.dotSpacingX;
    local dotSpacingY = options.dotSpacingY or ANCHOR_DEFAULTS.dotSpacingY;
    local padding = options.padding or ANCHOR_DEFAULTS.padding;
    local rounding = options.rounding or ANCHOR_DEFAULTS.rounding;

    -- Calculate anchor position (left of target window)
    local anchorX = windowX - size - padding;
    local anchorY = windowY;

    -- Window flags for the anchor (invisible, draggable)
    local windowFlags = bit.bor(
        ImGuiWindowFlags_NoTitleBar,
        ImGuiWindowFlags_NoResize,
        ImGuiWindowFlags_NoScrollbar,
        ImGuiWindowFlags_NoSavedSettings,
        ImGuiWindowFlags_NoFocusOnAppearing,
        ImGuiWindowFlags_NoBringToFrontOnFocus,
        ImGuiWindowFlags_NoBackground
    );

    local windowName = 'MoveAnchor_' .. id;

    -- Set window position (always follow target when not dragging)
    local isDragging = anchorDragging[id] or false;
    local posCondition = isDragging and ImGuiCond_Once or ImGuiCond_Always;
    imgui.SetNextWindowPos({anchorX, anchorY}, posCondition);
    imgui.SetNextWindowSize({size, size}, ImGuiCond_Always);

    local newAnchorX, newAnchorY;

    if imgui.Begin(windowName, true, windowFlags) then
        newAnchorX, newAnchorY = imgui.GetWindowPos();

        -- Track dragging state
        anchorDragging[id] = imgui.IsWindowFocused() and imgui.IsMouseDown(0);

        -- Reserve space for the anchor
        imgui.Dummy({size, size});

        imgui.End();
    end

    -- Determine colors based on drag/hover state
    local isActive = anchorDragging[id];
    local bgColor = isActive
        and (options.bgColorActive or ANCHOR_DEFAULTS.bgColorActive)
        or (options.bgColor or ANCHOR_DEFAULTS.bgColor);
    local borderColor = isActive
        and (options.borderColorActive or ANCHOR_DEFAULTS.borderColorActive)
        or (options.borderColor or ANCHOR_DEFAULTS.borderColor);
    local dotColor = isActive
        and (options.dotColorActive or ANCHOR_DEFAULTS.dotColorActive)
        or (options.dotColor or ANCHOR_DEFAULTS.dotColor);

    -- Draw visuals on appropriate draw list (behind config when open)
    local drawList = M.GetUIDrawList();
    local drawX = newAnchorX or anchorX;
    local drawY = newAnchorY or anchorY;

    -- Draw anchor background
    drawList:AddRectFilled(
        { drawX, drawY },
        { drawX + size, drawY + size },
        imgui.GetColorU32(ARGBToImGui(bgColor)),
        rounding
    );
    drawList:AddRect(
        { drawX, drawY },
        { drawX + size, drawY + size },
        imgui.GetColorU32(ARGBToImGui(borderColor)),
        rounding,
        0,
        1
    );

    -- Draw 2x3 dot grid (2 columns, 3 rows)
    local gridWidth = dotSpacingX;
    local gridHeight = 2 * dotSpacingY;
    local gridStartX = drawX + (size - gridWidth) / 2;
    local gridStartY = drawY + (size - gridHeight) / 2;

    for row = 0, 2 do
        for col = 0, 1 do
            local dotX = gridStartX + (col * dotSpacingX);
            local dotY = gridStartY + (row * dotSpacingY);
            drawList:AddCircleFilled(
                { dotX, dotY },
                dotSize,
                imgui.GetColorU32(ARGBToImGui(dotColor))
            );
        end
    end

    -- Calculate new target window position based on anchor movement
    if newAnchorX ~= nil then
        local deltaX = newAnchorX - anchorX;
        local deltaY = newAnchorY - anchorY;

        -- Only return new position if actually moved
        if deltaX ~= 0 or deltaY ~= 0 then
            return windowX + deltaX, windowY + deltaY;
        end
    end

    return nil, nil;
end

---Check if a specific anchor is currently being dragged
---@param id string Anchor identifier
---@return boolean
function M.IsAnchorDragging(id)
    return anchorDragging[id] or false;
end

---Reset drag state for an anchor (useful on cleanup)
---@param id string Anchor identifier
function M.ResetAnchorState(id)
    anchorDragging[id] = nil;
end

return M;
