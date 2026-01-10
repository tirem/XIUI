--[[
* XIUI Color Utilities
* Color conversion and manipulation functions
* HSV conversion logic taken from @EmmanuelOga
* https://github.com/EmmanuelOga/columns/blob/master/utils/color.lua
]]--

local M = {};

-- Color conversion caches (cleared via InvalidateColorCaches)
local hexToImGuiCache = {};

-- Invalidate color caches (call when settings change)
function M.InvalidateColorCaches()
    hexToImGuiCache = {};
end

-- Helper to validate and convert input to hex string
-- Returns a valid hex string or nil if invalid
local function ensureHexString(value)
    if type(value) == 'string' then
        return value;
    elseif type(value) == 'number' then
        -- If it's a number, assume it's an ARGB value and convert to hex
        return string.format('#%08X', value);
    end
    return nil;
end

-- ========================================
-- RGB/HSV Conversion
-- ========================================

--[[
 * Converts an RGB color value to HSV. Conversion formula
 * adapted from http://en.wikipedia.org/wiki/HSV_color_space.
 * Assumes r, g, and b are contained in the set [0, 255] and
 * returns h, s, and v in the set [0, 1].
 *
 * @param   Number  r       The red color value
 * @param   Number  g       The green color value
 * @param   Number  b       The blue color value
 * @return  Array           The HSV representation
]]
function M.rgbToHsv(r, g, b)
    local max, min = math.max(r, g, b), math.min(r, g, b)
    local h, s, v
    v = max

    local d = max - min
    if max == 0 then s = 0 else s = d / max end

    if max == min then
        h = 0 -- achromatic
    else
        if max == r then
            h = (g - b) / d
            if g < b then h = h + 6 end
        elseif max == g then h = (b - r) / d + 2
        elseif max == b then h = (r - g) / d + 4
        end
        h = h / 6
    end

    return h, s, v
end

--[[
 * Converts an HSV color value to RGB. Conversion formula
 * adapted from http://en.wikipedia.org/wiki/HSV_color_space.
 * Assumes h, s, and v are contained in the set [0, 1] and
 * returns r, g, and b in the set [0, 255].
 *
 * @param   Number  h       The hue
 * @param   Number  s       The saturation
 * @param   Number  v       The value
 * @return  Array           The RGB representation
]]
function M.hsvToRgb(h, s, v)
    local r, g, b

    local i = math.floor(h * 6);
    local f = h * 6 - i;
    local p = v * (1 - s);
    local q = v * (1 - f * s);
    local t = v * (1 - (1 - f) * s);

    i = i % 6

    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    elseif i == 5 then r, g, b = v, p, q
    end

    return r, g, b
end

-- ========================================
-- Hex/RGB Conversion
-- ========================================

function M.hex2rgb(hex)
    local hex = hex:gsub("#","")
    return tonumber("0x"..hex:sub(1,2)), tonumber("0x"..hex:sub(3,4)), tonumber("0x"..hex:sub(5,6))
end

-- Extract RGBA from hex string (supports #RRGGBB or #RRGGBBAA)
function M.hex2rgba(hex)
    local hex = hex:gsub("#", "");
    local r = tonumber("0x"..hex:sub(1,2));
    local g = tonumber("0x"..hex:sub(3,4));
    local b = tonumber("0x"..hex:sub(5,6));
    local a = 255;
    if #hex >= 8 then
        a = tonumber("0x"..hex:sub(7,8));
    end
    return r, g, b, a;
end

function M.rgb2hex(red, green, blue)
    return string.format('#%02x%02x%02x', red, green, blue);
end

-- ========================================
-- Color Shifting
-- ========================================

function M.shiftSaturationAndBrightness(hex, saturationPercent, brightnessPercent)
    local red, green, blue = M.hex2rgb(hex);

    local hue, saturation, brightness = M.rgbToHsv(red / 255, green / 255, blue / 255);

    saturation = math.min(1, saturation * (1 + saturationPercent));
    brightness = math.min(1, saturation * (1 + brightnessPercent));

    red, green, blue = M.hsvToRgb(hue, saturation, brightness);

    return M.rgb2hex(red * 255, green * 255, blue * 255);
end

function M.shiftGradient(gradientTable, saturationPercent, brightnessPercent)
    return {
        M.shiftSaturationAndBrightness(gradientTable[1], saturationPercent, brightnessPercent),
        M.shiftSaturationAndBrightness(gradientTable[2], saturationPercent, brightnessPercent)
    };
end

-- ========================================
-- ARGB/RGBA Conversion
-- ========================================

-- Helper to convert ARGB (0xAARRGGBB) to RGBA table {R, G, B, A}
function M.ARGBToRGBA(argb)
    local a = bit.band(bit.rshift(argb, 24), 0xFF) / 255.0;
    local r = bit.band(bit.rshift(argb, 16), 0xFF) / 255.0;
    local g = bit.band(bit.rshift(argb, 8), 0xFF) / 255.0;
    local b = bit.band(argb, 0xFF) / 255.0;
    return {r, g, b, a};
end

-- Helper to convert RGBA table {R, G, B, A} to ARGB (0xAARRGGBB)
function M.RGBAToARGB(rgba)
    return bit.bor(
        bit.lshift(math.floor(rgba[4] * 255), 24), -- Alpha
        bit.lshift(math.floor(rgba[1] * 255), 16), -- Red
        bit.lshift(math.floor(rgba[2] * 255), 8),  -- Green
        math.floor(rgba[3] * 255)                   -- Blue
    );
end

-- ========================================
-- ImGui Color Conversion
-- ========================================

-- Convert ARGB integer (0xAARRGGBB) to ImGui RGBA float table {r, g, b, a}
function M.ARGBToImGui(argb)
    local a = bit.rshift(bit.band(argb, 0xFF000000), 24) / 255;
    local r = bit.rshift(bit.band(argb, 0x00FF0000), 16) / 255;
    local g = bit.rshift(bit.band(argb, 0x0000FF00), 8) / 255;
    local b = bit.band(argb, 0x000000FF) / 255;
    return {r, g, b, a};
end

-- Convert ImGui RGBA float table to ARGB integer
function M.ImGuiToARGB(rgba)
    local a = math.floor(rgba[4] * 255);
    local r = math.floor(rgba[1] * 255);
    local g = math.floor(rgba[2] * 255);
    local b = math.floor(rgba[3] * 255);
    return bit.bor(
        bit.lshift(a, 24),
        bit.lshift(r, 16),
        bit.lshift(g, 8),
        b
    );
end

-- Convert ARGB (0xAARRGGBB) to ABGR (0xAABBGGRR) for ImGui draw calls
function M.ARGBToABGR(argb)
    local a = bit.band(bit.rshift(argb, 24), 0xFF);
    local r = bit.band(bit.rshift(argb, 16), 0xFF);
    local g = bit.band(bit.rshift(argb, 8), 0xFF);
    local b = bit.band(argb, 0xFF);
    return bit.bor(
        bit.lshift(a, 24),
        bit.lshift(b, 16),
        bit.lshift(g, 8),
        r
    );
end

-- ========================================
-- Hex/ImGui Conversion
-- ========================================

-- Convert hex string (#RRGGBB or #RRGGBBAA) to ImGui RGBA float table
-- Cached for performance - do not modify the returned table
function M.HexToImGui(hex)
    local cached = hexToImGuiCache[hex];
    if cached then
        return cached;
    end

    local cleanHex = hex:gsub("#", "");
    local r = tonumber(cleanHex:sub(1,2), 16) / 255;
    local g = tonumber(cleanHex:sub(3,4), 16) / 255;
    local b = tonumber(cleanHex:sub(5,6), 16) / 255;
    local a = 1.0;
    if #cleanHex == 8 then
        a = tonumber(cleanHex:sub(7,8), 16) / 255;
    end
    local result = {r, g, b, a};
    hexToImGuiCache[hex] = result;
    return result;
end

-- Convert ImGui RGBA float table to hex string
function M.ImGuiToHex(rgba)
    local r = math.floor(rgba[1] * 255);
    local g = math.floor(rgba[2] * 255);
    local b = math.floor(rgba[3] * 255);
    if rgba[4] and rgba[4] < 1.0 then
        local a = math.floor(rgba[4] * 255);
        return string.format("#%02x%02x%02x%02x", r, g, b, a);
    end
    return string.format("#%02x%02x%02x", r, g, b);
end

-- Convert hex string to ARGB integer (for text colors)
function M.HexToARGB(hexString, alpha)
    hexString = hexString:gsub("#", "");
    local r = tonumber(hexString:sub(1,2), 16);
    local g = tonumber(hexString:sub(3,4), 16);
    local b = tonumber(hexString:sub(5,6), 16);
    local a = alpha or 0xFF;
    return bit.bor(
        bit.lshift(a, 24),
        bit.lshift(r, 16),
        bit.lshift(g, 8),
        b
    );
end


-- ========================================
-- Settings Color Accessors
-- ========================================

-- Safe accessor for color settings with fallback
function M.GetColorSetting(module, setting, defaultValue)
    if gConfig and gConfig.colorCustomization and gConfig.colorCustomization[module] then
        return gConfig.colorCustomization[module][setting] or defaultValue;
    end
    return defaultValue;
end

-- Safe accessor for gradient settings with fallback
-- Returns {startColor, endColor} if gradient is enabled
-- Returns {startColor, startColor} if gradient is disabled (static color)
-- Returns defaultGradient if setting not found
function M.GetGradientSetting(module, setting, defaultGradient)
    if gConfig and gConfig.colorCustomization and gConfig.colorCustomization[module] then
        local gradient = gConfig.colorCustomization[module][setting];
        if gradient and gradient.enabled then
            return {gradient.start, gradient.stop};
        elseif gradient then
            return {gradient.start, gradient.start};  -- Static color
        end
    end
    return defaultGradient;
end

-- ========================================
-- Helper Functions
-- ========================================

-- Extract text color from gradient (first color with full opacity)
-- Used for deriving text colors from gradient settings
function M.GetGradientTextColor(gradientStart)
    if not gradientStart then
        return 0xFFFFFFFF;  -- Default white
    end
    return M.HexToARGB(gradientStart:gsub('#', ''):sub(1, 6), 0xFF);
end

-- Convert hex string directly to U32 for ImGui drawing
-- Uses imgui.GetColorU32() at render time when available, falls back to manual ABGR conversion
function M.HexToU32(hexString)
    if not hexString then
        return 0xFFFFFFFF;  -- Default white
    end
    -- Prefer imgui.GetColorU32 when available (at render time)
    if imgui and imgui.GetColorU32 then
        return imgui.GetColorU32(M.HexToImGui(hexString));
    end
    -- Fallback: manual conversion to ABGR
    local argb = M.HexToARGB(hexString:gsub('#', ''), 0xFF);
    return M.ARGBToABGR(argb);
end

-- Convert ARGB hex to U32 for ImGui drawing
-- Uses imgui.GetColorU32() at render time when available, falls back to manual ABGR conversion
function M.ARGBToU32(argb)
    if not argb then
        return 0xFFFFFFFF;  -- Default white
    end
    -- Prefer imgui.GetColorU32 when available (at render time)
    if imgui and imgui.GetColorU32 then
        return imgui.GetColorU32(M.ARGBToImGui(argb));
    end
    -- Fallback: manual conversion to ABGR
    return M.ARGBToABGR(argb);
end

-- Safe color table accessor (for inventory tracker style colors)
-- Converts ImGui-style color table {r, g, b, a} to ARGB integer
function M.ColorTableToARGB(colorTable, fallback)
    if colorTable and colorTable.r and colorTable.g and colorTable.b then
        local a = colorTable.a or 1.0;
        return bit.bor(
            bit.lshift(math.floor(a * 255), 24),
            bit.lshift(math.floor(colorTable.r * 255), 16),
            bit.lshift(math.floor(colorTable.g * 255), 8),
            math.floor(colorTable.b * 255)
        );
    end
    return fallback or 0xFFFFFFFF;
end

-- ========================================
-- Legacy Global Exports (for backwards compatibility)
-- ========================================
-- These will be set up by helpers.lua

return M;
