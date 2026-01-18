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
local diagnostics = require('libs.diagnostics');

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
local DEFAULT_BORDER_SCALE = 1.0;

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
    diagnostics.TrackPrimitiveCreate();  -- Track primitive creation
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
    @param borderScale number: Border texture scale (default 1.0)
    @return table: Border primitives handle with 'tl', 'tr', 'bl', 'br' keys
]]--
function M.createBorders(primData, themeName, borderScale)
    borderScale = borderScale or DEFAULT_BORDER_SCALE;

    local borders = {
        themeName = themeName,
        borderScale = borderScale,
    };

    for _, k in ipairs(M.BORDER_KEYS) do
        local prim = primitives:new(primData);
        diagnostics.TrackPrimitiveCreate();  -- Track primitive creation
        prim.visible = false;
        prim.can_focus = false;
        prim.exists = false;
        prim.scale_x = borderScale;
        prim.scale_y = borderScale;

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
    @param borderScale number: Border texture scale (default 1.0, or bgScale if not specified)
    @return table: Combined handle with 'bg', 'tl', 'tr', 'bl', 'br' keys
]]--
function M.create(primData, themeName, bgScale, borderScale)
    bgScale = bgScale or DEFAULT_BG_SCALE;
    borderScale = borderScale or DEFAULT_BORDER_SCALE;

    local bgHandle = M.createBackground(primData, themeName, bgScale);
    local borderHandle = M.createBorders(primData, themeName, borderScale);

    return {
        bg = bgHandle.bg,
        tl = borderHandle.tl,
        tr = borderHandle.tr,
        bl = borderHandle.bl,
        br = borderHandle.br,
        themeName = themeName,
        bgScale = bgScale,
        borderScale = borderScale,
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

    -- Update background - set position and size BEFORE visibility
    -- to avoid a frame where primitive is visible at old position
    bgPrim.position_x = x - padding;
    bgPrim.position_y = y - paddingY;
    bgPrim.width = math.ceil(bgWidth / bgScale);
    bgPrim.height = math.ceil(bgHeight / bgScale);
    bgPrim.scale_x = bgScale;
    bgPrim.scale_y = bgScale;

    -- Apply color (with optional separate opacity)
    if options.bgOpacity ~= nil then
        bgPrim.color = ApplyOpacityToColor(bgColor, options.bgOpacity);
    else
        bgPrim.color = bgColor;
    end

    -- Set visibility last, after all other properties are set
    bgPrim.visible = bgPrim.exists;
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
        borderScale = number,   -- Border scale (default 1.0)
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
    local borderScale = options.borderScale or borderHandle.borderScale or DEFAULT_BORDER_SCALE;
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

    -- Bottom-right corner - set properties before visibility
    local br = borderHandle.br;
    br.position_x = bgX + bgWidth - math.floor((borderSize * borderScale) - (bgOffset * borderScale));
    br.position_y = bgY + bgHeight - math.floor((borderSize * borderScale) - (bgOffset * borderScale));
    br.width = borderSize;
    br.height = borderSize;
    br.color = finalColor;
    br.scale_x = borderScale;
    br.scale_y = borderScale;

    -- Top-right edge (L-shaped from top to br) - set properties before visibility
    local tr = borderHandle.tr;
    tr.position_x = br.position_x;
    tr.position_y = bgY - (bgOffset * borderScale);
    tr.width = borderSize;
    tr.height = math.ceil((br.position_y - tr.position_y) / borderScale);
    tr.color = finalColor;
    tr.scale_x = borderScale;
    tr.scale_y = borderScale;

    -- Top-left (L-shaped: top and left edges) - set properties before visibility
    local tl = borderHandle.tl;
    tl.position_x = bgX - (bgOffset * borderScale);
    tl.position_y = bgY - (bgOffset * borderScale);
    tl.width = math.ceil((tr.position_x - tl.position_x) / borderScale);
    tl.height =  tr.height;
    tl.color = finalColor;
    tl.scale_x = borderScale;
    tl.scale_y = borderScale;

    -- Bottom-left edge (L-shaped from left to br) - set properties before visibility
    local bl = borderHandle.bl;
    bl.position_x = tl.position_x;
    bl.position_y = br.position_y;
    bl.width = tl.width;
    bl.height = br.height;
    bl.color = finalColor;
    bl.scale_x = borderScale;
    bl.scale_y = borderScale;

    -- Set visibility last for all borders, after all properties are set
    br.visible = br.exists;
    tr.visible = tr.exists;
    tl.visible = tl.exists;
    bl.visible = bl.exists;
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
    Change background theme (reloads texture only if theme changed)
    @param bgHandle table: Background handle
    @param themeName string: New theme name
    @param bgScale number: Optional new scale
]]--
function M.setBackgroundTheme(bgHandle, themeName, bgScale)
    if not bgHandle or not bgHandle.bg then return; end

    -- Always update scale if provided (lightweight operation)
    if bgScale then
        bgHandle.bgScale = bgScale;
        bgHandle.bg.scale_x = bgScale;
        bgHandle.bg.scale_y = bgScale;
    end

    -- Only reload texture if theme actually changed (expensive file I/O)
    local themeChanged = bgHandle.themeName ~= themeName;
    if themeChanged then
        bgHandle.themeName = themeName;
        if themeName == '-None-' then
            bgHandle.bg.exists = false;
            bgHandle.bg.visible = false;
        else
            local filepath = string.format('%s/assets/backgrounds/%s-bg.png', addon.path, themeName);
            bgHandle.bg.texture = filepath;
            bgHandle.bg.exists = ashita.fs.exists(filepath);
        end
    end
end

--[[
    Change border theme (reloads textures only if theme changed)
    @param borderHandle table: Border handle
    @param themeName string: New theme name
    @param borderScale number: Optional new border scale
]]--
function M.setBordersTheme(borderHandle, themeName, borderScale)
    if not borderHandle then return; end

    -- Always update scale if provided (lightweight operation)
    if borderScale then
        borderHandle.borderScale = borderScale;
        for _, k in ipairs(M.BORDER_KEYS) do
            local prim = borderHandle[k];
            if prim then
                prim.scale_x = borderScale;
                prim.scale_y = borderScale;
            end
        end
    end

    -- Only reload textures if theme actually changed (expensive file I/O)
    local themeChanged = borderHandle.themeName ~= themeName;
    if themeChanged then
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
end

--[[
    Change theme for combined handle (optimized: skips file I/O if only scale changed)
    @param handle table: Combined handle from create()
    @param themeName string: New theme name
    @param bgScale number: Optional new background scale
    @param borderScale number: Optional new border scale
]]--
function M.setTheme(handle, themeName, bgScale, borderScale)
    -- Save old themeName before sub-functions modify it
    -- (setBackgroundTheme updates handle.themeName, which would cause
    -- setBordersTheme's change detection to fail)
    local oldThemeName = handle.themeName;

    -- Temporarily restore old name for each check
    M.setBackgroundTheme(handle, themeName, bgScale);
    handle.themeName = oldThemeName; -- Restore for border check
    M.setBordersTheme(handle, themeName, borderScale);

    -- Now set final values
    handle.themeName = themeName;
    if bgScale then
        handle.bgScale = bgScale;
    end
    if borderScale then
        handle.borderScale = borderScale;
    end
end

--[[
    Lightweight scale-only update (no file I/O, no texture changes)
    Use this when only scale is changing, not theme.
    @param handle table: Combined handle from create()
    @param bgScale number: New background scale
    @param borderScale number: New border scale
]]--
function M.setScale(handle, bgScale, borderScale)
    if not handle then return; end

    -- Update background scale
    if bgScale and handle.bg then
        handle.bgScale = bgScale;
        handle.bg.scale_x = bgScale;
        handle.bg.scale_y = bgScale;
    end

    -- Update border scale
    if borderScale then
        handle.borderScale = borderScale;
        for _, k in ipairs(M.BORDER_KEYS) do
            local prim = handle[k];
            if prim then
                prim.scale_x = borderScale;
                prim.scale_y = borderScale;
            end
        end
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
        diagnostics.TrackPrimitiveDestroy();
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
                diagnostics.TrackPrimitiveDestroy();
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
    clipped or hidden. The clip region matches the background bounds exactly,
    keeping content within the background area.

    @param x number: Window content X position
    @param y number: Window content Y position
    @param width number: Window content width
    @param height number: Window content height
    @param options table: {
        theme = string,     -- Theme name (unused, kept for API compatibility)
        padding = number,   -- Horizontal padding (default 8)
        paddingY = number,  -- Vertical padding (defaults to padding)
    }
    @return table: { left, top, right, bottom } - clip bounds in screen coordinates
]]--
function M.getClipBounds(x, y, width, height, options)
    options = options or {};
    local padding = options.padding or DEFAULT_PADDING;
    local paddingY = options.paddingY or padding;

    -- Clip bounds match background bounds exactly (no border offset extension)
    return {
        left = x - padding,
        top = y - paddingY,
        right = x + width + padding,
        bottom = y + height + paddingY,
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
