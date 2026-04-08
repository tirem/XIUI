--[[
    ImGui Text Rendering Library
    Shared text drawing and measurement for modules migrated from GDI fonts.
    Uses Ashita's imgui.AddFontFromFileTTF() for custom font loading and
    ImGui's drawList:AddText API for outlined/plain text rendering.

    Usage:
        local imtext = require('libs.imtext');
        imtext.SetConfigFromSettings(settings.font_settings);
        local w, h = imtext.Measure('Hello', 14);
        imtext.Draw(drawList, 'Hello', x, y, 0xFFFFFFFF, 14);
]]

require('common');
local imgui = require('imgui');

local M = {};

-- GDI visual parity offsets (ImGui fonts render smaller than GDI at same size)
local GDI_SIZE_OFFSET = 2;
local GDI_OUTLINE_OFFSET = -1;

-- Font cache: fontKey -> font handle (loaded once, reused across modules)
local fontCache = {};
local activeFont = nil;
local activeFontKey = '';
local outlineWidth = 2;

local cachedLineHeight = 0;
local lineHeightFrame = -1;
local cachedOutlineCol = nil;

-- Multi-entry color cache keyed by ARGB integer
local colorCache = {};

local pos = {0, 0};

local fontFamilyToFile = {
    tahoma        = { regular = 'tahoma.ttf',     bold = 'tahomabd.ttf' },
    arial         = { regular = 'arial.ttf',       bold = 'arialbd.ttf' },
    consolas      = { regular = 'consola.ttf',     bold = 'consolab.ttf' },
    calibri       = { regular = 'calibri.ttf',     bold = 'calibrib.ttf' },
    segoeui       = { regular = 'segoeui.ttf',     bold = 'segoeuib.ttf' },
    ['segoe ui']  = { regular = 'segoeui.ttf',     bold = 'segoeuib.ttf' },
    verdana       = { regular = 'verdana.ttf',     bold = 'verdanab.ttf' },
    trebuchet     = { regular = 'trebuc.ttf',      bold = 'trebucbd.ttf' },
    lucida        = { regular = 'lucon.ttf',       bold = 'lucon.ttf' },
    ['courier new'] = { regular = 'cour.ttf',      bold = 'courbd.ttf' },
    georgia       = { regular = 'georgia.ttf',     bold = 'georgiab.ttf' },
};

local function resolveFontPath(fontFamily, isBold)
    local key = fontFamily:lower():gsub('^%s+', ''):gsub('%s+$', '');
    local variant = isBold and 'bold' or 'regular';
    local mapping = fontFamilyToFile[key];
    local fileName = mapping and mapping[variant] or (key .. '.ttf');
    return 'C:\\Windows\\Fonts\\' .. fileName;
end

local function loadFont(fontFamily, isBold)
    local fontKey = (fontFamily or 'Tahoma') .. (isBold and ':bold' or ':regular');
    if fontKey == activeFontKey then return; end

    -- Check cache first (font already loaded in a previous call)
    local cached = fontCache[fontKey];
    if cached then
        activeFont = cached;
        activeFontKey = fontKey;
        return;
    end

    -- Not cached — try loading from disk (only attempted once per key)
    if fontCache[fontKey] == false then
        activeFontKey = fontKey;
        return;
    end

    local path = resolveFontPath(fontFamily or 'Tahoma', isBold);
    local ok, result = pcall(function()
        return imgui.AddFontFromFileTTF(path, 20.0);
    end);
    if ok and result then
        fontCache[fontKey] = result;
        activeFont = result;
        activeFontKey = fontKey;
    else
        fontCache[fontKey] = false;
        activeFontKey = fontKey;
        print(string.format('[XIUI] Failed to load font: %s (%s)', fontKey, path));
    end
end

local function getLineHeight()
    local now = os.clock();
    if now - lineHeightFrame < 0.001 then return cachedLineHeight; end
    lineHeightFrame = now;
    cachedLineHeight = imgui.GetTextLineHeight();
    return cachedLineHeight;
end

local function getOutlineCol()
    if cachedOutlineCol then return cachedOutlineCol; end
    cachedOutlineCol = imgui.GetColorU32({0, 0, 0, 1});
    return cachedOutlineCol;
end

local function argbToU32(argb)
    if not argb then return 0xFFFFFFFF; end
    local cached = colorCache[argb];
    if cached then return cached; end
    cached = imgui.GetColorU32(ARGBToImGui(argb));
    colorCache[argb] = cached;
    return cached;
end

function M.GetFont()
    return activeFont or imgui.GetFont();
end

--- Configure the text renderer from individual parameters.
--- @param fontFamily string Font family name (e.g. 'Tahoma')
--- @param isBold boolean Whether to use bold variant
--- @param ow number Outline width in pixels
function M.SetConfig(fontFamily, isBold, ow)
    loadFont(fontFamily, isBold);
    outlineWidth = math.max(0, (ow or 2) + GDI_OUTLINE_OFFSET);
end

--- Apply font settings from a font_settings table (as used by gAdjustedSettings).
--- @param fontSettings table with font_family, font_flags, outline_width
function M.SetConfigFromSettings(fontSettings)
    if not fontSettings then return; end
    local family = fontSettings.font_family or 'Tahoma';
    local flags = fontSettings.font_flags or 0;
    local isBold = bit.band(flags, 1) ~= 0;
    local ow = fontSettings.outline_width or 2;
    M.SetConfig(family, isBold, ow);
end

--- Reset font state (call on settings change to force font reload).
function M.Reset()
    fontCache = {};
    activeFont = nil;
    activeFontKey = '';
    cachedOutlineCol = nil;
    lineHeightFrame = -1;
    colorCache = {};
end

--- Measure text width and height at the given font size.
--- @param text string
--- @param fontSize number|nil Pixel size (nil uses ImGui default)
--- @return number width, number height
function M.Measure(text, fontSize)
    if not text or text == '' then return 0, 0; end
    if fontSize then fontSize = fontSize + GDI_SIZE_OFFSET; end

    local font = activeFont;
    if font and fontSize then
        local pushOk = pcall(imgui.PushFont, font);
        if pushOk then
            local lineH = imgui.GetTextLineHeight();
            local w = imgui.CalcTextSize(text);
            imgui.PopFont();
            if lineH > 0 then
                local scale = fontSize / lineH;
                return w * scale, fontSize;
            end
        end
    end

    local defaultHeight = getLineHeight();
    if fontSize and defaultHeight > 0 then
        local scale = fontSize / defaultHeight;
        return imgui.CalcTextSize(text) * scale, fontSize;
    end
    return imgui.CalcTextSize(text), defaultHeight;
end

--- Draw outlined text on an ImGui draw list.
--- @param drawList userdata ImGui draw list
--- @param text string
--- @param x number Screen X position
--- @param y number Screen Y position
--- @param argbColor number ARGB color (e.g. 0xFFFFFFFF)
--- @param fontSize number|nil Pixel size (nil uses ImGui default)
function M.Draw(drawList, text, x, y, argbColor, fontSize)
    if not drawList or not text or text == '' then return; end
    if fontSize then fontSize = fontSize + GDI_SIZE_OFFSET; end
    local font = M.GetFont();
    local col = argbToU32(argbColor);
    local ow = outlineWidth;
    if ow > 0 then
        local outlineCol = getOutlineCol();
        if fontSize and font then
            pos[1] = x - ow; pos[2] = y;
            drawList:AddText(font, fontSize, pos, outlineCol, text);
            pos[1] = x + ow;
            drawList:AddText(font, fontSize, pos, outlineCol, text);
            pos[1] = x; pos[2] = y - ow;
            drawList:AddText(font, fontSize, pos, outlineCol, text);
            pos[2] = y + ow;
            drawList:AddText(font, fontSize, pos, outlineCol, text);
        else
            pos[1] = x - ow; pos[2] = y;
            drawList:AddText(pos, outlineCol, text);
            pos[1] = x + ow;
            drawList:AddText(pos, outlineCol, text);
            pos[1] = x; pos[2] = y - ow;
            drawList:AddText(pos, outlineCol, text);
            pos[2] = y + ow;
            drawList:AddText(pos, outlineCol, text);
        end
    end
    pos[1] = x; pos[2] = y;
    if fontSize and font then
        drawList:AddText(font, fontSize, pos, col, text);
    else
        drawList:AddText(pos, col, text);
    end
end

--- Draw text without outline.
--- @param drawList userdata
--- @param text string
--- @param x number
--- @param y number
--- @param argbColor number ARGB color
--- @param fontSize number|nil
function M.DrawSimple(drawList, text, x, y, argbColor, fontSize)
    if not drawList or not text or text == '' then return; end
    if fontSize then fontSize = fontSize + GDI_SIZE_OFFSET; end
    local font = M.GetFont();
    local col = argbToU32(argbColor);
    pos[1] = x; pos[2] = y;
    if fontSize and font then
        drawList:AddText(font, fontSize, pos, col, text);
    else
        drawList:AddText(pos, col, text);
    end
end

return M;
