--[[
* XIUI Window Background Library
* Unified API for managing window backgrounds with the 5-piece border system
*
* The 5-piece system consists of:
*   - bg: Main background texture (scaled)
*   - tl, tr, bl, br: L-shaped corner/edge border pieces (not scaled)
*
* Render order (Ashita primitives render in creation order):
*   1. Background (bg) - created first, renders at bottom
*   2. [Consumer creates their own middle-layer content here]
*   3. Borders (tl, tr, bl, br) - created last, render on top
*
* Theme types:
*   - '-None-': No background or borders (everything hidden)
*   - 'Plain': Background only (borders hidden)
*   - 'Window1-8': Background AND borders visible
]]--

require('common');
local primitives = require('primitives');

local M = {};

-- ============================================
-- Constants
-- ============================================
M.BG_IMAGE_KEYS = { 'bg', 'tl', 'tr', 'br', 'bl' };
M.BORDER_KEYS = { 'tl', 'tr', 'br', 'bl' };

-- Default values
local DEFAULT_PADDING = 8;
local DEFAULT_BORDER_SIZE = 21;
local DEFAULT_BG_OFFSET = 1;
local DEFAULT_BG_SCALE = 1.0;

-- ============================================
-- Internal Helpers
-- ============================================

-- Check if theme is a Window theme (has borders)
local function IsWindowTheme(themeName)
    if themeName == nil then return false; end
    return themeName:match('^Window%d+$') ~= nil;
end

-- Apply opacity to a color (extract RGB, combine with opacity alpha)
local function ApplyOpacityToColor(color, opacity)
    local alphaByte = math.floor((opacity or 1.0) * 255);
    local rgb = bit.band(color or 0xFFFFFFFF, 0x00FFFFFF);
    return bit.bor(bit.lshift(alphaByte, 24), rgb);
end

-- ============================================
-- Creation Functions
-- ============================================

--[[
    Create background primitive (call first for correct render order)

    @param primData table: Base primitive data (visible, can_focus, locked, etc.)
    @param themeName string: Theme name ('-None-', 'Plain', 'Window1', etc.)
    @param bgScale number: Background texture scale (default 1.0)
    @return table: Background primitive handle with 'bg' key
]]--
function M.createBackground(primData, themeName, bgScale)
    bgScale = bgScale or DEFAULT_BG_SCALE;

    local bgPrim = primitives:new(primData);
    bgPrim.visible = false;
    bgPrim.can_focus = false;
    bgPrim.exists = false;
    bgPrim.scale_x = bgScale;
    bgPrim.scale_y = bgScale;

    -- Load texture if not '-None-'
    if themeName ~= '-None-' then
        local filepath = string.format('%s/assets/backgrounds/%s-bg.png', addon.path, themeName);
        bgPrim.texture = filepath;
        bgPrim.exists = ashita.fs.exists(filepath);
    end

    return {
        bg = bgPrim,
        themeName = themeName,
        bgScale = bgScale,
    };
end

--[[
    Create border primitives (call after creating middle-layer content)

    @param primData table: Base primitive data
    @param themeName string: Theme name
    @return table: Border primitives handle with 'tl', 'tr', 'bl', 'br' keys
]]--
function M.createBorders(primData, themeName)
    local borders = {
        themeName = themeName,
    };

    for _, k in ipairs(M.BORDER_KEYS) do
        local prim = primitives:new(primData);
        prim.visible = false;
        prim.can_focus = false;
        prim.exists = false;
        prim.scale_x = 1.0;  -- Borders never scale
        prim.scale_y = 1.0;

        -- Load texture if Window theme
        if IsWindowTheme(themeName) then
            local filepath = string.format('%s/assets/backgrounds/%s-%s.png', addon.path, themeName, k);
            prim.texture = filepath;
            prim.exists = ashita.fs.exists(filepath);
        end

        borders[k] = prim;
    end

    return borders;
end

--[[
    Create complete window background (background + borders)
    Convenience function that creates both in correct order.
    Note: If you need middle-layer content, use createBackground() and createBorders() separately.

    @param primData table: Base primitive data
    @param themeName string: Theme name
    @param bgScale number: Background texture scale (default 1.0)
    @return table: Combined handle with 'bg', 'tl', 'tr', 'bl', 'br' keys
]]--
function M.create(primData, themeName, bgScale)
    local bgHandle = M.createBackground(primData, themeName, bgScale);
    local borderHandle = M.createBorders(primData, themeName);

    return {
        bg = bgHandle.bg,
        tl = borderHandle.tl,
        tr = borderHandle.tr,
        bl = borderHandle.bl,
        br = borderHandle.br,
        themeName = themeName,
        bgScale = bgScale or DEFAULT_BG_SCALE,
    };
end

-- ============================================
-- Update Functions
-- ============================================

--[[
    Update background primitive position and visibility

    @param bgHandle table: Background handle from createBackground()
    @param x number: Window X position
    @param y number: Window Y position
    @param width number: Window width (content area, not including padding)
    @param height number: Window height (content area, not including padding)
    @param options table: {
        theme = string,         -- Theme name (required for visibility logic)
        padding = number,       -- Horizontal padding (default 8)
        paddingY = number,      -- Vertical padding (defaults to padding)
        bgScale = number,       -- Background scale (default 1.0)
        bgOpacity = number,     -- Background opacity 0-1 (optional, for separate opacity mode)
        bgColor = number,       -- Background color ARGB (default 0xFFFFFFFF)
    }
]]--
function M.updateBackground(bgHandle, x, y, width, height, options)
    options = options or {};
    local theme = options.theme or bgHandle.themeName or 'Window1';
    local padding = options.padding or DEFAULT_PADDING;
    local paddingY = options.paddingY or padding;
    local bgScale = options.bgScale or bgHandle.bgScale or DEFAULT_BG_SCALE;
    local bgColor = options.bgColor or 0xFFFFFFFF;

    local bgPrim = bgHandle.bg;

    -- Handle '-None-' theme
    if theme == '-None-' then
        bgPrim.visible = false;
        return;
    end

    -- Calculate background dimensions
    local bgWidth = width + (padding * 2);
    local bgHeight = height + (paddingY * 2);

    -- Update background
    bgPrim.visible = bgPrim.exists;
    bgPrim.position_x = x - padding;
    bgPrim.position_y = y - paddingY;
    bgPrim.width = bgWidth / bgScale;
    bgPrim.height = bgHeight / bgScale;
    bgPrim.scale_x = bgScale;
    bgPrim.scale_y = bgScale;

    -- Apply color (with optional separate opacity)
    if options.bgOpacity ~= nil then
        bgPrim.color = ApplyOpacityToColor(bgColor, options.bgOpacity);
    else
        bgPrim.color = bgColor;
    end
end

--[[
    Update border primitives position and visibility

    @param borderHandle table: Border handle from createBorders()
    @param x number: Window X position
    @param y number: Window Y position
    @param width number: Window width (content area)
    @param height number: Window height (content area)
    @param options table: {
        theme = string,         -- Theme name (required)
        padding = number,       -- Horizontal padding (default 8)
        paddingY = number,      -- Vertical padding (defaults to padding)
        borderSize = number,    -- Corner piece size (default 21)
        bgOffset = number,      -- Border offset from background (default 1)
        borderOpacity = number, -- Border opacity 0-1 (optional)
        borderColor = number,   -- Border color ARGB (default 0xFFFFFFFF)
    }
]]--
function M.updateBorders(borderHandle, x, y, width, height, options)
    options = options or {};
    local theme = options.theme or borderHandle.themeName or 'Window1';
    local padding = options.padding or DEFAULT_PADDING;
    local paddingY = options.paddingY or padding;
    local borderSize = options.borderSize or DEFAULT_BORDER_SIZE;
    local bgOffset = options.bgOffset or DEFAULT_BG_OFFSET;
    local borderColor = options.borderColor or 0xFFFFFFFF;

    local isWindowTheme = IsWindowTheme(theme);

    -- Hide borders for non-Window themes
    if not isWindowTheme then
        for _, k in ipairs(M.BORDER_KEYS) do
            if borderHandle[k] then
                borderHandle[k].visible = false;
            end
        end
        return;
    end

    -- Calculate background bounds
    local bgWidth = width + (padding * 2);
    local bgHeight = height + (paddingY * 2);
    local bgX = x - padding;
    local bgY = y - paddingY;

    -- Apply color (with optional separate opacity)
    local finalColor;
    if options.borderOpacity ~= nil then
        finalColor = ApplyOpacityToColor(borderColor, options.borderOpacity);
    else
        finalColor = borderColor;
    end

    -- Bottom-right corner
    local br = borderHandle.br;
    br.visible = br.exists;
    br.position_x = bgX + bgWidth - borderSize + bgOffset;
    br.position_y = bgY + bgHeight - borderSize + bgOffset;
    br.width = borderSize;
    br.height = borderSize;
    br.color = finalColor;

    -- Top-right edge (L-shaped from top to br)
    local tr = borderHandle.tr;
    tr.visible = tr.exists;
    tr.position_x = br.position_x;
    tr.position_y = bgY - bgOffset;
    tr.width = borderSize;
    tr.height = br.position_y - tr.position_y;
    tr.color = finalColor;

    -- Top-left (L-shaped: top and left edges)
    local tl = borderHandle.tl;
    tl.visible = tl.exists;
    tl.position_x = bgX - bgOffset;
    tl.position_y = bgY - bgOffset;
    tl.width = tr.position_x - tl.position_x;
    tl.height = br.position_y - tl.position_y;
    tl.color = finalColor;

    -- Bottom-left edge (L-shaped from left to br)
    local bl = borderHandle.bl;
    bl.visible = bl.exists;
    bl.position_x = tl.position_x;
    bl.position_y = bgY + bgHeight - borderSize + bgOffset;
    bl.width = br.position_x - bl.position_x;
    bl.height = borderSize;
    bl.color = finalColor;
end

--[[
    Update complete window background (background + borders)
    Convenience function for combined handles from create()

    @param handle table: Combined handle from create()
    @param x number: Window X position
    @param y number: Window Y position
    @param width number: Window width (content area)
    @param height number: Window height (content area)
    @param options table: All options from updateBackground() and updateBorders()
]]--
function M.update(handle, x, y, width, height, options)
    M.updateBackground(handle, x, y, width, height, options);
    M.updateBorders(handle, x, y, width, height, options);
end

-- ============================================
-- Hide Functions
-- ============================================

--[[
    Hide background primitive
    @param bgHandle table: Background handle
]]--
function M.hideBackground(bgHandle)
    if bgHandle and bgHandle.bg then
        bgHandle.bg.visible = false;
    end
end

--[[
    Hide border primitives
    @param borderHandle table: Border handle
]]--
function M.hideBorders(borderHandle)
    if borderHandle then
        for _, k in ipairs(M.BORDER_KEYS) do
            if borderHandle[k] then
                borderHandle[k].visible = false;
            end
        end
    end
end

--[[
    Hide complete window background (combined handle)
    @param handle table: Combined handle from create()
]]--
function M.hide(handle)
    M.hideBackground(handle);
    M.hideBorders(handle);
end

-- ============================================
-- Theme Change Functions
-- ============================================

--[[
    Change background theme (reloads texture)
    @param bgHandle table: Background handle
    @param themeName string: New theme name
    @param bgScale number: Optional new scale
]]--
function M.setBackgroundTheme(bgHandle, themeName, bgScale)
    if not bgHandle or not bgHandle.bg then return; end

    bgHandle.themeName = themeName;
    if bgScale then
        bgHandle.bgScale = bgScale;
        bgHandle.bg.scale_x = bgScale;
        bgHandle.bg.scale_y = bgScale;
    end

    if themeName == '-None-' then
        bgHandle.bg.exists = false;
        bgHandle.bg.visible = false;
    else
        local filepath = string.format('%s/assets/backgrounds/%s-bg.png', addon.path, themeName);
        bgHandle.bg.texture = filepath;
        bgHandle.bg.exists = ashita.fs.exists(filepath);
    end
end

--[[
    Change border theme (reloads textures)
    @param borderHandle table: Border handle
    @param themeName string: New theme name
]]--
function M.setBordersTheme(borderHandle, themeName)
    if not borderHandle then return; end

    borderHandle.themeName = themeName;
    local isWindow = IsWindowTheme(themeName);

    for _, k in ipairs(M.BORDER_KEYS) do
        local prim = borderHandle[k];
        if prim then
            if isWindow then
                local filepath = string.format('%s/assets/backgrounds/%s-%s.png', addon.path, themeName, k);
                prim.texture = filepath;
                prim.exists = ashita.fs.exists(filepath);
            else
                prim.exists = false;
                prim.visible = false;
            end
        end
    end
end

--[[
    Change theme for combined handle
    @param handle table: Combined handle from create()
    @param themeName string: New theme name
    @param bgScale number: Optional new scale
]]--
function M.setTheme(handle, themeName, bgScale)
    M.setBackgroundTheme(handle, themeName, bgScale);
    M.setBordersTheme(handle, themeName);
    handle.themeName = themeName;
    if bgScale then
        handle.bgScale = bgScale;
    end
end

-- ============================================
-- Destroy Functions
-- ============================================

--[[
    Destroy background primitive
    @param bgHandle table: Background handle
]]--
function M.destroyBackground(bgHandle)
    if bgHandle and bgHandle.bg then
        bgHandle.bg:destroy();
        bgHandle.bg = nil;
    end
end

--[[
    Destroy border primitives
    @param borderHandle table: Border handle
]]--
function M.destroyBorders(borderHandle)
    if borderHandle then
        for _, k in ipairs(M.BORDER_KEYS) do
            if borderHandle[k] then
                borderHandle[k]:destroy();
                borderHandle[k] = nil;
            end
        end
    end
end

--[[
    Destroy complete window background
    @param handle table: Combined handle from create()
]]--
function M.destroy(handle)
    M.destroyBackground(handle);
    M.destroyBorders(handle);
end

-- ============================================
-- Utility Functions
-- ============================================

--[[
    Check if a theme name is a Window theme (has borders)
    @param themeName string: Theme name to check
    @return boolean: True if Window theme
]]--
M.isWindowTheme = IsWindowTheme;

--[[
    Get the primitive keys used for backgrounds
    @return table: { 'bg', 'tl', 'tr', 'br', 'bl' }
]]--
function M.getImageKeys()
    return M.BG_IMAGE_KEYS;
end

--[[
    Get clip bounds for middle-layer content (e.g., pet images)

    Use this to calculate the visible area for content rendered between
    the background and borders. Content outside these bounds should be
    clipped or hidden.

    @param x number: Window content X position
    @param y number: Window content Y position
    @param width number: Window content width
    @param height number: Window content height
    @param options table: {
        theme = string,     -- Theme name (required for border offset calculation)
        padding = number,   -- Horizontal padding (default 8)
        paddingY = number,  -- Vertical padding (defaults to padding)
        bgOffset = number,  -- Border offset (default 1, only applies to Window themes)
    }
    @return table: { left, top, right, bottom } - clip bounds in screen coordinates
]]--
function M.getClipBounds(x, y, width, height, options)
    options = options or {};
    local theme = options.theme or 'Window1';
    local padding = options.padding or DEFAULT_PADDING;
    local paddingY = options.paddingY or padding;
    local bgOffset = options.bgOffset or DEFAULT_BG_OFFSET;

    -- For Window themes, extend clip bounds to include border area
    local borderOffset = IsWindowTheme(theme) and bgOffset or 0;

    return {
        left = x - padding - borderOffset,
        top = y - paddingY - borderOffset,
        right = x + width + padding + borderOffset,
        bottom = y + height + paddingY + borderOffset,
    };
end

--[[
    Clip an image/primitive to the window background bounds

    Calculates the visible portion of an image when clipped to the background.
    Returns nil if the image is completely outside the clip bounds.

    @param imgX number: Image X position
    @param imgY number: Image Y position
    @param imgWidth number: Image display width (after scaling)
    @param imgHeight number: Image display height (after scaling)
    @param clipBounds table: Clip bounds from getClipBounds()
    @param imgScale number: Image scale factor (optional, default 1.0)
    @return table or nil: {
        x, y = clipped position,
        width, height = clipped dimensions (in texture pixels),
        texOffsetX, texOffsetY = texture offset (in texture pixels),
        scaleX, scaleY = scale to apply
    } or nil if completely clipped
]]--
function M.clipImageToBounds(imgX, imgY, imgWidth, imgHeight, clipBounds, imgScale)
    imgScale = imgScale or 1.0;

    -- Calculate image bounds
    local imgRight = imgX + imgWidth;
    local imgBottom = imgY + imgHeight;

    -- Calculate intersection with clip bounds
    local clipLeft = math.max(imgX, clipBounds.left);
    local clipTop = math.max(imgY, clipBounds.top);
    local clipRight = math.min(imgRight, clipBounds.right);
    local clipBottom = math.min(imgBottom, clipBounds.bottom);

    -- Check if there's any visible area
    if clipLeft >= clipRight or clipTop >= clipBottom then
        return nil; -- Completely outside bounds
    end

    -- Calculate texture offset in pixels (how much of the texture to skip)
    local texOffsetX = (clipLeft - imgX) / imgScale;
    local texOffsetY = (clipTop - imgY) / imgScale;

    -- Calculate visible dimensions in texture pixels
    local visibleWidth = (clipRight - clipLeft) / imgScale;
    local visibleHeight = (clipBottom - clipTop) / imgScale;

    return {
        x = clipLeft,
        y = clipTop,
        width = visibleWidth,
        height = visibleHeight,
        texOffsetX = texOffsetX,
        texOffsetY = texOffsetY,
        scaleX = imgScale,
        scaleY = imgScale,
    };
end

return M;
