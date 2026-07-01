--[[
    Shared Satchel ImGui font loading (tooltip + chrome).
    Never mutates the atlas during d3d_present; prewarm at init/settings sync only.
    Never clears font cache entries — ImFont pointers remain valid for addon lifetime.
]]--

local imgui = require('imgui')

local M = {}

local fontCache = {}

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

function M.get_font(fontFamily, pixelSize)
    local px = quantize_pixel_size(pixelSize)
    local key = cache_key(fontFamily, px)

    local cached = fontCache[key]
    if cached ~= nil then
        if cached == false then
            return imgui.GetFont()
        end
        return cached
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

function M.prewarm(fontFamily, pixelSizes)
    if type(pixelSizes) ~= 'table' then
        return
    end
    for _, px in ipairs(pixelSizes) do
        M.get_font(fontFamily, px)
    end
end

function M.push_font(fontFamily, pixelSize)
    local font = M.get_font(fontFamily, pixelSize)
    if not font then
        return false
    end
    local ok = pcall(imgui.PushFont, font)
    return ok == true
end

function M.pop_font()
    imgui.PopFont()
end

function M.calc_text_width(text, fontFamily, pixelSize)
    if type(text) ~= 'string' or text == '' then
        return 0
    end

    local pushed = M.push_font(fontFamily, pixelSize)
    local width = imgui.CalcTextSize(text)
    if pushed then
        M.pop_font()
    end

    if type(width) == 'number' then
        return width
    end
    return tonumber(select(1, imgui.CalcTextSize(text))) or 0
end

function M.get_line_height(fontFamily, pixelSize)
    local pushed = M.push_font(fontFamily, pixelSize)
    local h = tonumber(imgui.GetTextLineHeight()) or quantize_pixel_size(pixelSize)
    if pushed then
        M.pop_font()
    end
    return h
end

return M
