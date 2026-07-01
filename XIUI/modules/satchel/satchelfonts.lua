--[[
    Satchel window chrome fonts — global fontFamily + globalScale via PushFont.
]]--

local imgui = require('imgui')
local fontcore = require('modules.satchel.satchelfontcore')

local M = {}

local BASE_TOOLTIP_PX = 14
local chrome_base_px = nil
local sync_state = {
    version = -1,
    family = '',
    scale = 1.0,
    pixel_size = 0,
}

local function get_global_scale()
    return tonumber(gConfig and gConfig.globalScale) or 1.0
end

local function get_font_family()
    return (gConfig and gConfig.fontFamily) or 'Tahoma'
end

function M.capture_chrome_base_px()
    if chrome_base_px then
        return chrome_base_px
    end
    chrome_base_px = tonumber(imgui.GetTextLineHeight()) or 18
    return chrome_base_px
end

function M.get_chrome_pixel_size(scale)
    scale = scale or get_global_scale()
    local base = M.capture_chrome_base_px()
    return fontcore.quantize_pixel_size(base * scale)
end

function M.get_metrics(scale)
    scale = scale or get_global_scale()
    local px = M.get_chrome_pixel_size(scale)
    return {
        family = get_font_family(),
        scale = scale,
        pixel_size = px,
        line_height = fontcore.get_line_height(get_font_family(), px),
    }
end

function M.sync()
    local version = gConfigVersion or 0
    local family = get_font_family()
    local scale = get_global_scale()
    local px = M.get_chrome_pixel_size(scale)

    if sync_state.version == version
        and sync_state.family == family
        and sync_state.scale == scale
        and sync_state.pixel_size == px then
        return false
    end

    sync_state.version = version
    sync_state.family = family
    sync_state.scale = scale
    sync_state.pixel_size = px

    fontcore.prewarm(family, { px })
    return true
end

function M.push_chrome_font(scale)
    M.sync()
    local metrics = M.get_metrics(scale)
    return fontcore.push_font(metrics.family, metrics.pixel_size)
end

function M.pop_chrome_font()
    fontcore.pop_font()
end

function M.get_outline_px(scale)
    return math.max(1, math.floor((scale or get_global_scale()) + 0.5))
end

return M
