--[[
    Shared Satchel ImGui font loading (tooltip + chrome helpers).

    Tooltip fonts use exact pixel sizes from tooltips.FONT_SIZES.
    Each family+size is loaded once via AddFontFromFileTTF and cached for the
    addon lifetime. Loads are ONLY allowed with allowLoad == 'force', and must
    run from the addon load event — never from d3d_present (atlas mutation
    mid-frame causes EXCEPTION_ACCESS_VIOLATION on Ashita 4.16).

    Chrome text uses Ashita's default font + SetWindowFontScale (push_chrome_font).
]]--

local imgui = require('imgui')

local M = {}

local fontCache = {}
local tooltip_push_depth = 0

local fontFamilyToFile = {
    arial                    = { regular = 'arial.ttf' },
    calibri                  = { regular = 'calibri.ttf' },
    consolas                 = { regular = 'consola.ttf' },
    ['courier new']          = { regular = 'cour.ttf' },
    georgia                  = { regular = 'georgia.ttf' },
    ['lucida console']       = { regular = 'lucon.ttf' },
    ['microsoft sans serif'] = { regular = 'micross.ttf' },
    ['segoe ui']             = { regular = 'segoeui.ttf' },
    tahoma                   = { regular = 'tahoma.ttf' },
    ['times new roman']      = { regular = 'times.ttf' },
    ['trebuchet ms']         = { regular = 'trebuc.ttf' },
    verdana                  = { regular = 'verdana.ttf' },
}

local AGAVE_FILE_NAMES = {
    'Agave-Regular.ttf',
    'Agave.ttf',
    'agave.ttf',
}

local function normalize_family(fontFamily)
    if type(fontFamily) ~= 'string' or fontFamily == '' then
        return 'agave'
    end
    return fontFamily:lower():gsub('^%s+', ''):gsub('%s+$', '')
end

local function file_exists(path)
    if type(path) ~= 'string' or path == '' then
        return false
    end
    local f = io.open(path, 'rb')
    if f then
        f:close()
        return true
    end
    return false
end

local function ashita_fonts_dir()
    if not AshitaCore or not AshitaCore.GetInstallPath then
        return nil
    end
    return AshitaCore:GetInstallPath():gsub('\\$', '') .. '\\resources\\fonts\\'
end

function M.resolve_font_path(fontFamily)
    local key = normalize_family(fontFamily)

    if key == 'agave' then
        local dir = ashita_fonts_dir()
        if dir then
            for _, fileName in ipairs(AGAVE_FILE_NAMES) do
                local path = dir .. fileName
                if file_exists(path) then
                    return path
                end
            end
        end
        return nil
    end

    local mapping = fontFamilyToFile[key]
    local fileName = mapping and mapping.regular or (key .. '.ttf')
    return 'C:\\Windows\\Fonts\\' .. fileName
end

local function cache_key(fontFamily, pixelSize)
    return normalize_family(fontFamily) .. ':' .. tostring(math.floor(tonumber(pixelSize) or 14))
end

local function quantize_pixel_size(pixelSize)
    return math.max(1, math.floor((tonumber(pixelSize) or 14) + 0.5))
end

function M.quantize_pixel_size(pixelSize)
    return quantize_pixel_size(pixelSize)
end

function M.find_nearest_cached_font(fontFamily, pixelSize)
    local px = quantize_pixel_size(pixelSize)
    local prefix = normalize_family(fontFamily) .. ':'
    local best = nil
    local best_dist = math.huge

    for key, font in pairs(fontCache) do
        if font and font ~= false and key:sub(1, #prefix) == prefix then
            local cached_px = tonumber(key:match(':(%d+)$'))
            if cached_px then
                local dist = math.abs(cached_px - px)
                if dist < best_dist then
                    best_dist = dist
                    best = font
                end
            end
        end
    end

    return best
end

function M.get_font(fontFamily, pixelSize, allowLoad)
    local px = quantize_pixel_size(pixelSize)
    local key = cache_key(fontFamily, px)

    local cached = fontCache[key]
    if cached ~= nil then
        if cached == false then
            return imgui.GetFont()
        end
        return cached
    end

    -- Only 'force' may call AddFontFromFileTTF, and only from the load event.
    -- Any present-path caller must pass false/nil and use the cache or nearest.
    if allowLoad ~= 'force' then
        return M.find_nearest_cached_font(fontFamily, px) or imgui.GetFont()
    end

    if normalize_family(fontFamily) == 'agave' then
        local default_font = imgui.GetFont()
        local default_h = tonumber(imgui.GetTextLineHeight()) or 0
        if default_font and math.abs(default_h - px) < 0.75 then
            fontCache[key] = default_font
            return default_font
        end
    end

    local path = M.resolve_font_path(fontFamily)
    if not path then
        fontCache[key] = false
        return imgui.GetFont()
    end

    local ok, result = pcall(function()
        return imgui.AddFontFromFileTTF(path, px * 1.0)
    end)

    if ok and result then
        fontCache[key] = result
        return result
    end

    fontCache[key] = false
    print(string.format('[XIUI Satchel] Failed to load font %s @ %dpx (%s)', tostring(fontFamily), px, tostring(path)))
    return imgui.GetFont()
end

function M.is_cached(fontFamily, pixelSize)
    local key = cache_key(fontFamily, quantize_pixel_size(pixelSize))
    local cached = fontCache[key]
    return cached ~= nil and cached ~= false
end

function M.load_font(fontFamily, pixelSize, force)
    return M.get_font(fontFamily, pixelSize, force and 'force' or false)
end

-- Load-event only. Never call from d3d_present.
function M.prewarm(fontFamily, pixelSizes)
    if type(pixelSizes) ~= 'table' then
        return
    end
    for _, px in ipairs(pixelSizes) do
        M.get_font(fontFamily, px, 'force')
    end
end

function M.push_font(fontFamily, pixelSize, allowLoad)
    local font = M.get_font(fontFamily, pixelSize, allowLoad)
    if not font then
        return false
    end
    local ok = pcall(imgui.PushFont, font)
    return ok == true
end

function M.pop_font()
    imgui.PopFont()
end

function M.calc_text_width(text, fontFamily, pixelSize, allowLoad)
    if type(text) ~= 'string' or text == '' then
        return 0
    end

    local pushed = M.push_font(fontFamily, pixelSize, allowLoad == true)
    local width = imgui.CalcTextSize(text)
    if pushed then
        M.pop_font()
    end

    if type(width) == 'number' then
        return width
    end
    return tonumber(select(1, imgui.CalcTextSize(text))) or 0
end

function M.get_line_height(fontFamily, pixelSize, allowLoad)
    local pushed = M.push_font(fontFamily, pixelSize, allowLoad == true)
    local h = tonumber(imgui.GetTextLineHeight()) or quantize_pixel_size(pixelSize)
    if pushed then
        M.pop_font()
    end
    return h
end

-- Tooltip helpers: exact pixel fonts only (never SetWindowFontScale).

function M.calc_tooltip_text_width(text, fontFamily, pixelSize)
    return M.calc_text_width(text, fontFamily, pixelSize, false)
end

function M.get_tooltip_line_height(fontFamily, pixelSize)
    if M.is_cached(fontFamily, pixelSize) then
        return M.get_line_height(fontFamily, pixelSize, false)
    end
    return quantize_pixel_size(pixelSize)
end

function M.push_tooltip_font(fontFamily, pixelSize)
    local ok = M.push_font(fontFamily, pixelSize, false)
    if ok then
        tooltip_push_depth = tooltip_push_depth + 1
    end
    return ok
end

function M.pop_tooltip_font()
    if tooltip_push_depth <= 0 then
        return
    end
    M.pop_font()
    tooltip_push_depth = tooltip_push_depth - 1
end


-- Window chrome fonts (Ashita default Agave + SetWindowFontScale). Present-safe.
local has_window_font_scale = (type(imgui.SetWindowFontScale) == 'function')
local SetWindowFontScale = has_window_font_scale and imgui.SetWindowFontScale or function() end
local chrome_base_px = nil
local chrome_scale_stack = {}

local function get_global_scale()
    return tonumber(gConfig and gConfig.globalScale) or 1.0
end

function M.capture_chrome_base_px()
    if chrome_base_px then
        return chrome_base_px
    end
    chrome_base_px = tonumber(imgui.GetTextLineHeight()) or 18
    return chrome_base_px
end

function M.prewarm_startup()
    M.capture_chrome_base_px()
end

-- Kept for callers that sync chrome each frame (no-op; Agave is always present).
function M.sync(_scale)
    return false
end

function M.push_chrome_font(scale)
    scale = scale or get_global_scale()
    if not has_window_font_scale then
        return false
    end
    local factor = scale
    if factor <= 0 then
        factor = 1.0
    end
    chrome_scale_stack[#chrome_scale_stack + 1] = factor
    SetWindowFontScale(factor)
    return true
end

function M.pop_chrome_font()
    if not has_window_font_scale then
        return
    end
    if #chrome_scale_stack > 0 then
        chrome_scale_stack[#chrome_scale_stack] = nil
        local prev = chrome_scale_stack[#chrome_scale_stack]
        SetWindowFontScale(prev or 1.0)
    else
        SetWindowFontScale(1.0)
    end
end

function M.get_outline_px(scale)
    return math.max(1, math.floor((scale or get_global_scale()) + 0.5))
end

return M