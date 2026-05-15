--[[
* XIUI Window Background Library
* Immediate-mode background + border renderer using ImGui draw lists.
*
* The 5 textures (bg + tl/tr/bl/br) are tinted/positioned per-frame and submitted
* to the supplied draw list. No persistent handles — callers re-issue Draw every
* frame as part of their DrawWindow.
*
* Theme types:
*   - '-None-':   nothing rendered
*   - 'Plain':    background only (no borders)
*   - 'Window1-8': background + L-shaped borders
*
* Render order within Draw:
*   1. bg
*   2. tl, tr, bl, br (borders sit on top so corners are crisp)
* Callers needing middle-layer content (e.g. petbar's pet image) should call
* DrawBackground / DrawBorders separately and emit their content between.
]]--

require('common');
local imgui = require('imgui');
local TextureManager = require('libs.texturemanager');

local M = {};

-- ============================================
-- Constants
-- ============================================

local DEFAULT_PADDING = 8;
local DEFAULT_BORDER_SIZE = 21;
local DEFAULT_BG_OFFSET = 1;

-- ============================================
-- Internal Helpers
-- ============================================

local function IsWindowTheme(themeName)
    if themeName == nil then return false; end
    return themeName:match('^Window%d+$') ~= nil;
end

-- Replace the alpha byte of an ARGB color with opacity*255
local function ApplyOpacityToColor(color, opacity)
    local alphaByte = math.floor((opacity or 1.0) * 255);
    local rgb = bit.band(color or 0xFFFFFFFF, 0x00FFFFFF);
    return bit.bor(bit.lshift(alphaByte, 24), rgb);
end

local function ResolveTint(color, opacity)
    if opacity ~= nil then
        return ApplyOpacityToColor(color or 0xFFFFFFFF, opacity);
    end
    return color or 0xFFFFFFFF;
end

-- Cached ARGB -> ImU32 conversion (drawList:AddImage takes ImU32 tints)
local tintCache = {};
local function TintU32(argb)
    local v = tintCache[argb];
    if v ~= nil then return v; end
    v = imgui.GetColorU32(ARGBToImGui(argb));
    tintCache[argb] = v;
    return v;
end

local function LoadPiecePtr(theme, piece)
    local tex = TextureManager.getFileTexture(string.format('backgrounds/%s-%s', theme, piece));
    if tex == nil then return nil; end
    return TextureManager.getTexturePtr(tex);
end

-- Compute padded background rect from content rect.
-- Returns: bgX, bgY, bgW, bgH
local function ComputeBgRect(x, y, w, h, padding, paddingY)
    return x - padding, y - paddingY, w + (padding * 2), h + (paddingY * 2);
end

-- ============================================
-- Public API
-- ============================================

M.isWindowTheme = IsWindowTheme;
M.IsWindowTheme = IsWindowTheme;

--[[
    Render the background piece only.

    @param drawList    ImGui draw list
    @param x, y, w, h  Content rect (not including padding)
    @param options     Theme + padding/color options (see Draw())
]]--
function M.DrawBackground(drawList, x, y, w, h, options)
    if drawList == nil then return; end
    options = options or {};
    local theme = options.theme or 'Window1';
    if theme == '-None-' then return; end

    local padding  = options.padding  or DEFAULT_PADDING;
    local paddingY = options.paddingY or padding;
    local bgColor  = options.bgColor  or 0xFFFFFFFF;

    local bgX, bgY, bgW, bgH = ComputeBgRect(x, y, w, h, padding, paddingY);

    local ptr = LoadPiecePtr(theme, 'bg');
    if ptr == nil then return; end

    local tint = TintU32(ResolveTint(bgColor, options.bgOpacity));
    drawList:AddImage(ptr, {bgX, bgY}, {bgX + bgW, bgY + bgH}, {0, 0}, {1, 1}, tint);
end

--[[
    Render the four border pieces (Window themes only). Skips silently for
    '-None-' and 'Plain'.
]]--
function M.DrawBorders(drawList, x, y, w, h, options)
    if drawList == nil then return; end
    options = options or {};
    local theme = options.theme or 'Window1';
    if not IsWindowTheme(theme) then return; end

    local padding      = options.padding      or DEFAULT_PADDING;
    local paddingY     = options.paddingY     or padding;
    local borderSize   = options.borderSize   or DEFAULT_BORDER_SIZE;
    local bgOffset     = options.bgOffset     or DEFAULT_BG_OFFSET;
    local borderScale  = options.borderScale  or 1.0;
    local borderColor  = options.borderColor  or 0xFFFFFFFF;

    local bgX, bgY, bgW, bgH = ComputeBgRect(x, y, w, h, padding, paddingY);
    local tint = TintU32(ResolveTint(borderColor, options.borderOpacity));

    local pieceSize = borderSize * borderScale;
    local offset = bgOffset * borderScale;

    -- Bottom-right (fixed pieceSize x pieceSize)
    local brX = bgX + bgW - math.floor(pieceSize - offset);
    local brY = bgY + bgH - math.floor(pieceSize - offset);
    local brPtr = LoadPiecePtr(theme, 'br');
    if brPtr ~= nil then
        drawList:AddImage(brPtr, {brX, brY}, {brX + pieceSize, brY + pieceSize}, {0, 0}, {1, 1}, tint);
    end

    -- Top-right (pieceSize wide, spans down to br)
    local trX = brX;
    local trY = bgY - offset;
    local trH = brY - trY;
    local trPtr = LoadPiecePtr(theme, 'tr');
    if trPtr ~= nil then
        drawList:AddImage(trPtr, {trX, trY}, {trX + pieceSize, trY + trH}, {0, 0}, {1, 1}, tint);
    end

    -- Top-left (L-shape: spans top edge to tr, and left edge down to bl)
    local tlX = bgX - offset;
    local tlY = bgY - offset;
    local tlW = trX - tlX;
    local tlPtr = LoadPiecePtr(theme, 'tl');
    if tlPtr ~= nil then
        drawList:AddImage(tlPtr, {tlX, tlY}, {tlX + tlW, tlY + trH}, {0, 0}, {1, 1}, tint);
    end

    -- Bottom-left (spans bottom edge to br)
    local blX = tlX;
    local blY = brY;
    local blPtr = LoadPiecePtr(theme, 'bl');
    if blPtr ~= nil then
        drawList:AddImage(blPtr, {blX, blY}, {blX + tlW, blY + pieceSize}, {0, 0}, {1, 1}, tint);
    end
end

--[[
    Render background + borders in one call.

    Call once per frame inside DrawWindow. No state retained.

    @param drawList ImGui draw list (e.g. from GetUIDrawList())
    @param x, y     Content top-left in screen coords (does NOT include padding)
    @param w, h     Content size (does NOT include padding)
    @param options  table:
        theme         = string   -- '-None-' | 'Plain' | 'Window1'..'Window8'
        padding       = number   -- Horizontal pad (default 8)
        paddingY      = number   -- Vertical pad (defaults to padding)
        bgScale       = number   -- Reserved for future use (default 1.0)
        borderScale   = number   -- Scales border piece size (default 1.0)
        bgOpacity     = number   -- Optional 0..1; overrides bgColor's alpha
        bgColor       = number   -- ARGB tint (default 0xFFFFFFFF)
        borderSize    = number   -- Corner piece size in px (default 21)
        bgOffset      = number   -- Border offset from bg edge (default 1)
        borderOpacity = number   -- Optional 0..1; overrides borderColor's alpha
        borderColor   = number   -- ARGB tint (default 0xFFFFFFFF)
]]--
function M.Draw(drawList, x, y, w, h, options)
    M.DrawBackground(drawList, x, y, w, h, options);
    M.DrawBorders(drawList, x, y, w, h, options);
end

-- ============================================
-- Utility Functions
-- ============================================

--[[
    Compute the clip bounds for middle-layer content rendered between bg and
    borders. Use with drawList:PushClipRect / PopClipRect.

    @return table { left, top, right, bottom } in screen coords
]]--
function M.GetClipBounds(x, y, w, h, options)
    options = options or {};
    local padding  = options.padding  or DEFAULT_PADDING;
    local paddingY = options.paddingY or padding;
    return {
        left   = x - padding,
        top    = y - paddingY,
        right  = x + w + padding,
        bottom = y + h + paddingY,
    };
end

-- Backward-compat alias (camelCase) for any external consumer still calling the old name.
M.getClipBounds = M.GetClipBounds;

return M;
