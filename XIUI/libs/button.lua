--[[
* XIUI Button Library
* Reusable button component with hover states and image overlay support
*
* Usage:
*   local button = require('libs.button');
*
*   -- Simple button with callback
*   if button.Draw('myButton', x, y, width, height, options) then
*       -- Button was clicked
*   end
*
*   -- Button with image
*   button.Draw('arrowBtn', x, y, 24, 24, {
*       image = arrowTexture,
*       imageSize = {16, 16},
*       colors = { normal = 0xFF333333, hovered = 0xFF444444, pressed = 0xFF222222 },
*   });
*
* Options:
*   colors = { normal, hovered, pressed, border }  -- ARGB colors
*   rounding = number                               -- Corner rounding (default 4)
*   borderThickness = number                        -- Border thickness (default 1)
*   image = texture pointer or number               -- Image to draw on button
*   imageSize = {width, height}                     -- Image dimensions (defaults to button size)
*   imageOffset = {x, y}                            -- Image offset from button top-left
*   imageColor = ARGB                               -- Image tint color (default white)
*   tooltip = string                                -- Tooltip text on hover
*   disabled = boolean                              -- Disable interaction
*   drawList = ImGui draw list                      -- Custom draw list (default: background)
]]--

require('common');
local imgui = require('imgui');
local ffi = require('ffi');
local primitives = require('primitives');

local M = {};

-- ============================================
-- Primitive-based Button Management
-- ============================================

-- Store created primitive buttons for reuse
M.primButtons = {};

--[[
    Get or create a primitive button by ID
    @param id string: Unique button identifier
    @return table: Primitive object
]]--
function M.GetOrCreatePrim(id)
    if not M.primButtons[id] then
        M.primButtons[id] = primitives:new({
            visible = false,
            can_focus = false,
            locked = true,
        });
    end
    return M.primButtons[id];
end

--[[
    Destroy a primitive button by ID
    @param id string: Button identifier
]]--
function M.DestroyPrim(id)
    if M.primButtons[id] then
        M.primButtons[id]:destroy();
        M.primButtons[id] = nil;
    end
end

--[[
    Destroy all primitive buttons
]]--
function M.DestroyAllPrims()
    for id, prim in pairs(M.primButtons) do
        if prim then
            prim:destroy();
        end
    end
    M.primButtons = {};
end

--[[
    Draw a primitive-based button (background renders behind GDI fonts)

    @param id string: Unique button identifier
    @param x number: X position
    @param y number: Y position
    @param width number: Button width
    @param height number: Button height
    @param options table: Button options (colors, disabled, tooltip)
    @return boolean: True if clicked
    @return boolean: True if hovered
]]--
function M.DrawPrim(id, x, y, width, height, options)
    options = options or {};

    local colors = options.colors or M.DEFAULT_COLORS;
    local disabled = options.disabled or false;

    -- Get or create the primitive
    local prim = M.GetOrCreatePrim(id);

    -- Set cursor position for invisible button (hover/click detection)
    imgui.SetCursorScreenPos({x, y});

    -- Create invisible button for interaction
    local clicked = false;
    local hovered = false;
    local held = false;

    if not disabled then
        imgui.InvisibleButton(id, {width, height});
        clicked = imgui.IsItemClicked();
        hovered = imgui.IsItemHovered();
        held = imgui.IsItemActive();
    else
        imgui.Dummy({width, height});
    end

    -- Determine current color based on state
    local bgColor;
    if disabled then
        bgColor = colors.disabled or M.DEFAULT_COLORS.disabled;
    elseif held then
        bgColor = colors.pressed or colors.hovered or M.DEFAULT_COLORS.pressed;
    elseif hovered then
        bgColor = colors.hovered or M.DEFAULT_COLORS.hovered;
    else
        bgColor = colors.normal or M.DEFAULT_COLORS.normal;
    end

    -- Update primitive
    prim.visible = true;
    prim.position_x = x;
    prim.position_y = y;
    prim.width = width;
    prim.height = height;
    prim.color = bgColor;

    -- Show tooltip if provided
    if hovered and options.tooltip then
        imgui.SetTooltip(options.tooltip);
    end

    return clicked, hovered;
end

--[[
    Hide a primitive button
    @param id string: Button identifier
]]--
function M.HidePrim(id)
    if M.primButtons[id] then
        M.primButtons[id].visible = false;
    end
end

--[[
    Draw a primitive-based arrow button

    @param id string: Unique button identifier
    @param x number: X position
    @param y number: Y position
    @param size number: Button size (square)
    @param direction string: 'up', 'down', 'left', 'right'
    @param options table: Button options
    @param drawList: ImGui draw list for arrow rendering
    @return boolean: True if clicked
    @return boolean: True if hovered
]]--
function M.DrawArrowPrim(id, x, y, size, direction, options, drawList)
    options = options or {};

    local colors = options.colors or M.DEFAULT_COLORS;
    local disabled = options.disabled or false;

    -- Arrow colors
    local arrowColors = options.arrowColors or M.ARROW_COLORS;
    local arrowColor = options.arrowColor or arrowColors.normal or 0xFFCCCCCC;
    local arrowHoverColor = options.arrowHoverColor or arrowColors.hovered or 0xFFFFFFFF;

    -- Get or create the primitive for background
    local prim = M.GetOrCreatePrim(id);

    -- Set cursor position for invisible button
    imgui.SetCursorScreenPos({x, y});

    -- Create invisible button for interaction
    local clicked = false;
    local hovered = false;
    local held = false;

    if not disabled then
        imgui.InvisibleButton(id, {size, size});
        clicked = imgui.IsItemClicked();
        hovered = imgui.IsItemHovered();
        held = imgui.IsItemActive();
    else
        imgui.Dummy({size, size});
    end

    -- Determine background color based on state
    local bgColor;
    if disabled then
        bgColor = colors.disabled or M.DEFAULT_COLORS.disabled;
    elseif held then
        bgColor = colors.pressed or colors.hovered or M.DEFAULT_COLORS.pressed;
    elseif hovered then
        bgColor = colors.hovered or M.DEFAULT_COLORS.hovered;
    else
        bgColor = colors.normal or M.DEFAULT_COLORS.normal;
    end

    -- Update primitive background
    prim.visible = true;
    prim.position_x = x;
    prim.position_y = y;
    prim.width = size;
    prim.height = size;
    prim.color = bgColor;

    -- Draw arrow using ImGui draw list (renders on top of primitive)
    drawList = drawList or imgui.GetForegroundDrawList();
    local currentArrowColor = (hovered or held) and arrowHoverColor or arrowColor;
    local arrowColorU32 = ARGBToU32(currentArrowColor);

    -- Calculate arrow points
    local centerX = x + size / 2;
    local centerY = y + size / 2;
    local arrowSize = size * 0.35;

    local p1, p2, p3;

    if direction == 'up' then
        p1 = {centerX, centerY - arrowSize};
        p2 = {centerX - arrowSize, centerY + arrowSize * 0.6};
        p3 = {centerX + arrowSize, centerY + arrowSize * 0.6};
    elseif direction == 'down' then
        p1 = {centerX, centerY + arrowSize};
        p2 = {centerX - arrowSize, centerY - arrowSize * 0.6};
        p3 = {centerX + arrowSize, centerY - arrowSize * 0.6};
    elseif direction == 'left' then
        p1 = {centerX - arrowSize, centerY};
        p2 = {centerX + arrowSize * 0.6, centerY - arrowSize};
        p3 = {centerX + arrowSize * 0.6, centerY + arrowSize};
    elseif direction == 'right' then
        p1 = {centerX + arrowSize, centerY};
        p2 = {centerX - arrowSize * 0.6, centerY - arrowSize};
        p3 = {centerX - arrowSize * 0.6, centerY + arrowSize};
    end

    if p1 and p2 and p3 then
        drawList:AddTriangleFilled(p1, p2, p3, arrowColorU32);
    end

    -- Show tooltip
    if hovered and options.tooltip then
        imgui.SetTooltip(options.tooltip);
    end

    return clicked, hovered;
end

-- ============================================
-- Default Colors
-- ============================================

M.DEFAULT_COLORS = {
    normal = 0xCC333333,
    hovered = 0xDD4a4a4a,
    pressed = 0xDD222222,
    border = 0xFF1a1a1a,
    disabled = 0x88222222,
};

-- ============================================
-- Preset Color Schemes
-- ============================================

-- Neutral/default button
M.COLORS_NEUTRAL = {
    normal = 0xCC333333,
    hovered = 0xDD4a4a4a,
    pressed = 0xDD222222,
    border = 0xFF1a1a1a,
};

-- Positive button (lot, confirm, accept, yes)
M.COLORS_POSITIVE = {
    normal = 0xCC2d5a2d,
    hovered = 0xDD3d7a3d,
    pressed = 0xDD1d4a1d,
    border = 0xFF1a331a,
};

-- Negative button (pass, cancel, decline, no)
M.COLORS_NEGATIVE = {
    normal = 0xCC5a2d2d,
    hovered = 0xDD7a3d3d,
    pressed = 0xDD4a1d1d,
    border = 0xFF331a1a,
};

-- Info button (toggle, info, neutral action)
M.COLORS_INFO = {
    normal = 0xCC2d3d5a,
    hovered = 0xDD3d4d7a,
    pressed = 0xDD1d2d4a,
    border = 0xFF1a1a33,
};

-- Special button (highlight, important)
M.COLORS_SPECIAL = {
    normal = 0xCC5a4a2d,
    hovered = 0xDD7a6a3d,
    pressed = 0xDD4a3a1d,
    border = 0xFF33291a,
};

-- ============================================
-- Arrow Color Presets
-- ============================================

M.ARROW_COLORS = {
    normal = 0xFFAAAAAA,
    hovered = 0xFFFFFFFF,
};

M.ARROW_COLORS_POSITIVE = {
    normal = 0xFF88CC88,
    hovered = 0xFFAAFFAA,
};

M.ARROW_COLORS_NEGATIVE = {
    normal = 0xFFCC8888,
    hovered = 0xFFFFAAAA,
};

-- ============================================
-- Helper Functions
-- ============================================

-- Convert ARGB hex to ImGui U32
local function ARGBToU32(argb)
    if type(argb) == 'table' then
        -- Already a table {r, g, b, a}
        return imgui.GetColorU32(argb);
    end
    -- ARGB hex to ABGR (ImGui format)
    local a = bit.rshift(bit.band(argb, 0xFF000000), 24);
    local r = bit.rshift(bit.band(argb, 0x00FF0000), 16);
    local g = bit.rshift(bit.band(argb, 0x0000FF00), 8);
    local b = bit.band(argb, 0x000000FF);
    return imgui.GetColorU32({r / 255, g / 255, b / 255, a / 255});
end

-- Get texture pointer as number for ImGui
local function GetTexturePtr(texture)
    if texture == nil then
        return nil;
    end
    if type(texture) == 'number' then
        return texture;
    end
    if type(texture) == 'table' and texture.image then
        return tonumber(ffi.cast("uint32_t", texture.image));
    end
    if type(texture) == 'cdata' then
        return tonumber(ffi.cast("uint32_t", texture));
    end
    return nil;
end

-- ============================================
-- Button Drawing
-- ============================================

--[[
    Draw a button with hover states and optional image overlay

    @param id string: Unique button identifier (used for ImGui)
    @param x number: X position (screen coordinates)
    @param y number: Y position (screen coordinates)
    @param width number: Button width
    @param height number: Button height
    @param options table: Optional settings (see module header)
    @return boolean: True if button was clicked
    @return boolean: True if button is hovered
]]--
function M.Draw(id, x, y, width, height, options)
    options = options or {};

    local colors = options.colors or M.DEFAULT_COLORS;
    local rounding = options.rounding or 4;
    local borderThickness = options.borderThickness or 1;
    local disabled = options.disabled or false;

    -- Get draw list (default to background so it renders behind other UI)
    local drawList = options.drawList or imgui.GetBackgroundDrawList();

    -- Set cursor position for invisible button
    imgui.SetCursorScreenPos({x, y});

    -- Create invisible button for interaction
    local clicked = false;
    local hovered = false;
    local held = false;

    if not disabled then
        imgui.InvisibleButton(id, {width, height});
        clicked = imgui.IsItemClicked();
        hovered = imgui.IsItemHovered();
        held = imgui.IsItemActive();
    else
        -- Still need to reserve space even when disabled
        imgui.Dummy({width, height});
    end

    -- Determine current color based on state
    local bgColor;
    if disabled then
        bgColor = colors.disabled or M.DEFAULT_COLORS.disabled;
    elseif held then
        bgColor = colors.pressed or colors.hovered or M.DEFAULT_COLORS.pressed;
    elseif hovered then
        bgColor = colors.hovered or M.DEFAULT_COLORS.hovered;
    else
        bgColor = colors.normal or M.DEFAULT_COLORS.normal;
    end

    local borderColor = colors.border or M.DEFAULT_COLORS.border;

    -- Convert to ImGui U32
    local bgColorU32 = ARGBToU32(bgColor);
    local borderColorU32 = ARGBToU32(borderColor);

    -- Draw button background
    drawList:AddRectFilled({x, y}, {x + width, y + height}, bgColorU32, rounding);

    -- Draw border if thickness > 0
    if borderThickness > 0 then
        drawList:AddRect({x, y}, {x + width, y + height}, borderColorU32, rounding, nil, borderThickness);
    end

    -- Draw image if provided
    local image = options.image;
    local imagePtr = GetTexturePtr(image);

    if imagePtr then
        local imageSize = options.imageSize or {width, height};
        local imageOffset = options.imageOffset or {0, 0};
        local imageColor = options.imageColor or 0xFFFFFFFF;

        -- Center image if smaller than button
        local imgX = x + imageOffset[1] + (width - imageSize[1]) / 2;
        local imgY = y + imageOffset[2] + (height - imageSize[2]) / 2;

        local imageColorU32 = ARGBToU32(imageColor);

        drawList:AddImage(
            imagePtr,
            {imgX, imgY},
            {imgX + imageSize[1], imgY + imageSize[2]},
            {0, 0}, {1, 1},
            imageColorU32
        );
    end

    -- Show tooltip if provided and hovered
    if hovered and options.tooltip then
        imgui.SetTooltip(options.tooltip);
    end

    return clicked, hovered;
end

--[[
    Draw a button that renders an arrow icon (up, down, left, right)

    @param id string: Unique button identifier
    @param x number: X position
    @param y number: Y position
    @param size number: Button size (square)
    @param direction string: 'up', 'down', 'left', 'right'
    @param options table: Button options (same as Draw)
    @return boolean: True if clicked
    @return boolean: True if hovered
]]--
function M.DrawArrow(id, x, y, size, direction, options)
    options = options or {};

    local colors = options.colors or M.DEFAULT_COLORS;
    local rounding = options.rounding or 4;
    local borderThickness = options.borderThickness or 1;
    local disabled = options.disabled or false;

    -- Arrow colors can be passed as a table or individual values
    local arrowColors = options.arrowColors or M.ARROW_COLORS;
    local arrowColor = options.arrowColor or arrowColors.normal or 0xFFCCCCCC;
    local arrowHoverColor = options.arrowHoverColor or arrowColors.hovered or 0xFFFFFFFF;

    -- Get draw list
    local drawList = options.drawList or imgui.GetBackgroundDrawList();

    -- Set cursor position for invisible button
    imgui.SetCursorScreenPos({x, y});

    -- Create invisible button for interaction
    local clicked = false;
    local hovered = false;
    local held = false;

    if not disabled then
        imgui.InvisibleButton(id, {size, size});
        clicked = imgui.IsItemClicked();
        hovered = imgui.IsItemHovered();
        held = imgui.IsItemActive();
    else
        imgui.Dummy({size, size});
    end

    -- Determine current color based on state
    local bgColor;
    if disabled then
        bgColor = colors.disabled or M.DEFAULT_COLORS.disabled;
    elseif held then
        bgColor = colors.pressed or colors.hovered or M.DEFAULT_COLORS.pressed;
    elseif hovered then
        bgColor = colors.hovered or M.DEFAULT_COLORS.hovered;
    else
        bgColor = colors.normal or M.DEFAULT_COLORS.normal;
    end

    local borderColor = colors.border or M.DEFAULT_COLORS.border;

    -- Convert to ImGui U32
    local bgColorU32 = ARGBToU32(bgColor);
    local borderColorU32 = ARGBToU32(borderColor);

    -- Draw button background
    drawList:AddRectFilled({x, y}, {x + size, y + size}, bgColorU32, rounding);

    -- Draw border
    if borderThickness > 0 then
        drawList:AddRect({x, y}, {x + size, y + size}, borderColorU32, rounding, nil, borderThickness);
    end

    -- Draw arrow triangle
    local currentArrowColor = (hovered or held) and arrowHoverColor or arrowColor;
    local arrowColorU32 = ARGBToU32(currentArrowColor);

    -- Calculate arrow points based on direction
    local centerX = x + size / 2;
    local centerY = y + size / 2;
    local arrowSize = size * 0.35;  -- Arrow size relative to button

    local p1, p2, p3;

    if direction == 'up' then
        p1 = {centerX, centerY - arrowSize};              -- Top point
        p2 = {centerX - arrowSize, centerY + arrowSize * 0.6};  -- Bottom left
        p3 = {centerX + arrowSize, centerY + arrowSize * 0.6};  -- Bottom right
    elseif direction == 'down' then
        p1 = {centerX, centerY + arrowSize};              -- Bottom point
        p2 = {centerX - arrowSize, centerY - arrowSize * 0.6};  -- Top left
        p3 = {centerX + arrowSize, centerY - arrowSize * 0.6};  -- Top right
    elseif direction == 'left' then
        p1 = {centerX - arrowSize, centerY};              -- Left point
        p2 = {centerX + arrowSize * 0.6, centerY - arrowSize};  -- Top right
        p3 = {centerX + arrowSize * 0.6, centerY + arrowSize};  -- Bottom right
    elseif direction == 'right' then
        p1 = {centerX + arrowSize, centerY};              -- Right point
        p2 = {centerX - arrowSize * 0.6, centerY - arrowSize};  -- Top left
        p3 = {centerX - arrowSize * 0.6, centerY + arrowSize};  -- Bottom left
    end

    if p1 and p2 and p3 then
        drawList:AddTriangleFilled(p1, p2, p3, arrowColorU32);
    end

    -- Show tooltip if provided
    if hovered and options.tooltip then
        imgui.SetTooltip(options.tooltip);
    end

    return clicked, hovered;
end

--[[
    Draw a text button (button with text label)

    @param id string: Unique button identifier
    @param x number: X position
    @param y number: Y position
    @param text string: Button label text
    @param options table: Button options plus:
        - font: GDI font object for text rendering
        - fontSize: Font size (default 10)
        - textColor: Text color ARGB (default white)
        - textHoverColor: Text color on hover (default textColor)
        - padding: {horizontal, vertical} padding around text
    @return boolean: True if clicked
    @return boolean: True if hovered
]]--
function M.DrawText(id, x, y, text, options)
    options = options or {};

    local font = options.font;
    local fontSize = options.fontSize or 10;
    local padding = options.padding or {8, 4};
    local textColor = options.textColor or 0xFFFFFFFF;
    local textHoverColor = options.textHoverColor or textColor;

    -- Calculate button size based on text if font provided
    local textWidth = 0;
    local textHeight = fontSize;

    if font then
        font:set_font_height(fontSize);
        font:set_text(text);
        textWidth, textHeight = font:get_text_size();
        textWidth = textWidth or (fontSize * #text * 0.6);  -- Fallback estimate
        textHeight = textHeight or fontSize;
    else
        -- Estimate text size without font
        textWidth = fontSize * #text * 0.6;
    end

    local width = options.width or (textWidth + padding[1] * 2);
    local height = options.height or (textHeight + padding[2] * 2);

    -- Draw button background
    local clicked, hovered = M.Draw(id, x, y, width, height, options);

    -- Position and show text if font provided
    if font then
        local textX = x + (width - textWidth) / 2;
        local textY = y + (height - textHeight) / 2;

        font:set_position_x(textX);
        font:set_position_y(textY);
        font:set_font_color(hovered and textHoverColor or textColor);
        font:set_visible(true);
    end

    return clicked, hovered, width, height;
end

--[[
    Draw a primitive-based minimize/maximize button

    @param id string: Unique button identifier
    @param x number: X position
    @param y number: Y position
    @param size number: Button size (square)
    @param isMinimized boolean: True shows maximize icon (□), false shows minimize icon (_)
    @param options table: Button options
    @param drawList: ImGui draw list for icon rendering
    @return boolean: True if clicked
    @return boolean: True if hovered
]]--
function M.DrawMinimizePrim(id, x, y, size, isMinimized, options, drawList)
    options = options or {};

    local colors = options.colors or M.DEFAULT_COLORS;
    local disabled = options.disabled or false;

    -- Icon colors
    local iconColors = options.iconColors or M.ARROW_COLORS;
    local iconColor = options.iconColor or iconColors.normal or 0xFFCCCCCC;
    local iconHoverColor = options.iconHoverColor or iconColors.hovered or 0xFFFFFFFF;

    -- Get or create the primitive for background
    local prim = M.GetOrCreatePrim(id);

    -- Set cursor position for invisible button
    imgui.SetCursorScreenPos({x, y});

    -- Create invisible button for interaction
    local clicked = false;
    local hovered = false;
    local held = false;

    if not disabled then
        imgui.InvisibleButton(id, {size, size});
        clicked = imgui.IsItemClicked();
        hovered = imgui.IsItemHovered();
        held = imgui.IsItemActive();
    else
        imgui.Dummy({size, size});
    end

    -- Determine background color based on state
    local bgColor;
    if disabled then
        bgColor = colors.disabled or M.DEFAULT_COLORS.disabled;
    elseif held then
        bgColor = colors.pressed or colors.hovered or M.DEFAULT_COLORS.pressed;
    elseif hovered then
        bgColor = colors.hovered or M.DEFAULT_COLORS.hovered;
    else
        bgColor = colors.normal or M.DEFAULT_COLORS.normal;
    end

    -- Update primitive background
    prim.visible = true;
    prim.position_x = x;
    prim.position_y = y;
    prim.width = size;
    prim.height = size;
    prim.color = bgColor;

    -- Draw icon using ImGui draw list (renders on top of primitive)
    drawList = drawList or imgui.GetForegroundDrawList();
    local currentIconColor = (hovered or held) and iconHoverColor or iconColor;
    local iconColorU32 = ARGBToU32(currentIconColor);

    -- Calculate icon dimensions
    local centerX = x + size / 2;
    local centerY = y + size / 2;
    local iconSize = size * 0.4;
    local lineThickness = math.max(2, size * 0.1);

    if isMinimized then
        -- Maximize icon: small square (□)
        local halfSize = iconSize * 0.5;
        drawList:AddRect(
            {centerX - halfSize, centerY - halfSize},
            {centerX + halfSize, centerY + halfSize},
            iconColorU32, 0, nil, lineThickness
        );
    else
        -- Minimize icon: horizontal line at bottom (_)
        local halfWidth = iconSize * 0.6;
        local lineY = centerY + iconSize * 0.3;
        drawList:AddLine(
            {centerX - halfWidth, lineY},
            {centerX + halfWidth, lineY},
            iconColorU32, lineThickness
        );
    end

    -- Show tooltip
    if hovered and options.tooltip then
        imgui.SetTooltip(options.tooltip);
    end

    return clicked, hovered;
end

return M;
