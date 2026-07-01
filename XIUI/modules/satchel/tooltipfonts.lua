--[[
    Tooltip font helpers for Satchel item descriptions.
    Sharp scaling via PushFont at integer pixel sizes (never SetWindowFontScale).
]]--

local imgui = require('imgui')
local fontcore = require('modules.satchel.satchelfontcore')
local tooltiplayout = require('modules.satchel.tooltiplayout')

local M = {}

local WAVE_DASH_CHAR = '\227\128\156' -- UTF-8 U+301C 〜
local WAVE_DASH_MARKER = '{{WAVE}}'

local glyph_state = {
    checked = false,
    merged = false,
}

local sync_state = {
    version = -1,
    family = '',
    scale = 1.0,
    pixel_size = 0,
}

local push_depth = 0

local function get_tooltip_family()
    return (gConfig and gConfig.satchelTooltipFontFamily) or 'Agave'
end

local function get_tooltip_scale()
    return tonumber(gConfig and gConfig.satchelTooltipScale) or 1.0
end

local function calc_text_width_with_current_font(text)
    if type(text) ~= 'string' or text == '' then
        return 0
    end
    local width = imgui.CalcTextSize(text)
    if type(width) == 'number' then
        return width
    end
    return tonumber(select(1, imgui.CalcTextSize(text))) or 0
end

local function glyph_renders_distinct(char)
    local wave_width = calc_text_width_with_current_font(char)
    local missing_width = calc_text_width_with_current_font('?')
    local space_width = calc_text_width_with_current_font(' ')

    if wave_width < 2 then
        return false
    end
    if math.abs(wave_width - missing_width) < 0.5 then
        return false
    end
    if math.abs(wave_width - space_width) < 0.5 then
        return false
    end
    return true
end

local function refresh_glyph_state()
    if glyph_state.checked then
        return glyph_state.merged
    end
    glyph_state.checked = true
    glyph_state.merged = glyph_renders_distinct(WAVE_DASH_CHAR)
    return glyph_state.merged
end

function M.get_metrics()
    local scale = get_tooltip_scale()
    local metrics = tooltiplayout.get_scaled_metrics(scale)
    metrics.family = get_tooltip_family()
    metrics.scale = scale
    metrics.line_height = fontcore.get_line_height(metrics.family, metrics.pixel_size)
    return metrics
end

function M.sync()
    local version = gConfigVersion or 0
    local family = get_tooltip_family()
    local scale = get_tooltip_scale()
    local metrics = tooltiplayout.get_scaled_metrics(scale)
    local px = metrics.pixel_size

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

    local prewarm_sizes = { px }
    local min_px = metrics.footer_min_px
    if min_px < px then
        for size = px - 1, min_px, -1 do
            prewarm_sizes[#prewarm_sizes + 1] = size
        end
    end
    fontcore.prewarm(family, prewarm_sizes)
    glyph_state.checked = false
    return true
end

function M.prewarm_font_glyphs()
    M.sync()
    return refresh_glyph_state()
end

function M.ensure_tooltip_font_glyphs()
    return refresh_glyph_state()
end

function M.get_wave_dash_char()
    return WAVE_DASH_CHAR
end

function M.get_wave_dash_marker()
    return WAVE_DASH_MARKER
end

function M.get_wave_font()
    return nil
end

function M.push_tooltip_font()
    M.sync()
    local metrics = M.get_metrics()
    local ok = fontcore.push_font(metrics.family, metrics.pixel_size)
    if ok then
        push_depth = push_depth + 1
    end
    return ok, metrics
end

function M.pop_tooltip_font()
    if push_depth > 0 then
        fontcore.pop_font()
        push_depth = push_depth - 1
    end
end

function M.try_render_merged_glyph(color)
    if not refresh_glyph_state() then
        return false
    end
    imgui.TextColored(color, WAVE_DASH_CHAR)
    return true
end

function M.measure_wave_dash_width()
    if refresh_glyph_state() then
        return calc_text_width_with_current_font(WAVE_DASH_CHAR)
    end
    local h = tonumber(imgui.GetTextLineHeight()) or 14
    return math.max(9, h * 0.78)
end

function M.calc_text_width(text)
    local metrics = M.get_metrics()
    return fontcore.calc_text_width(text, metrics.family, metrics.pixel_size)
end

return M
