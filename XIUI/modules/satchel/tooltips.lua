--[[
    Satchel tooltips: layout metrics, fonts, glyph fallbacks, and status/element icons.

    Font atlas loads only via satchelfontcore with allowLoad/force from addon load
    or present-start tick_load — never mid-draw (Ashita 4.16 AV risk).
]]--

local imgui = require('imgui')
local fontcore = require('modules.satchel.satchelfontcore')
local TextureManager = require('libs.texturemanager')

local M = {}

-- Layout / font-size helpers
M.BASE_FONT_PX = 14
M.FONT_SIZES = { 14, 18, 24, 32, 40, 48 }
M.FONT_SIZE_LABELS = {
    [14] = '14px (Default)',
    [18] = '18px',
    [24] = '24px',
    [32] = '32px',
    [40] = '40px',
    [48] = '48px',
}

function M.is_valid_font_size(px)
    px = tonumber(px)
    if not px then
        return false
    end
    for i = 1, #M.FONT_SIZES do
        if M.FONT_SIZES[i] == px then
            return true
        end
    end
    return false
end

function M.normalize_font_size(px)
    px = tonumber(px)
    if not px then
        return M.BASE_FONT_PX
    end
    if M.is_valid_font_size(px) then
        return px
    end

    local best = M.BASE_FONT_PX
    local best_dist = math.huge
    for i = 1, #M.FONT_SIZES do
        local size = M.FONT_SIZES[i]
        local dist = math.abs(size - px)
        if dist < best_dist then
            best_dist = dist
            best = size
        end
    end
    return best
end

function M.label_for_font_size(px)
    px = M.normalize_font_size(px)
    return M.FONT_SIZE_LABELS[px] or (tostring(px) .. 'px')
end

function M.smaller_font_sizes(px)
    px = M.normalize_font_size(px)
    local result = {}
    for i = #M.FONT_SIZES, 1, -1 do
        local size = M.FONT_SIZES[i]
        if size < px then
            result[#result + 1] = size
        end
    end
    return result
end
-- satchel_sim.py baseline: WRAP_WIDTH=305, BOX_PAD=10, shell=325.
M.BASE_WRAP_WIDTH = 305
M.BASE_PADDING = 10
M.BASE_TOOLTIP_WIDTH = M.BASE_WRAP_WIDTH + M.BASE_PADDING * 2
M.BASE_TAG_SIZE = 14
M.BASE_ICON_SIZE = 14
M.BASE_ICON_GAP = 2
M.BASE_NAME_TAG_GAP = 8
M.BASE_SEP_PAD = 3
M.BASE_FOOTER_GAP = 4
M.FOOTER_MIN_SHRINK_PX = 9

local ELEMENT_ORDER = { 'Lightning', 'Water', 'Light', 'Dark', 'Fire', 'Ice', 'Wind', 'Earth' }

local scratch_tokens = {}
local scratch_units = {}
local scratch_rows = {}

local function clear_table(t)
    for i = #t, 1, -1 do
        t[i] = nil
    end
end

function M.title_case_words(text)
    if type(text) ~= 'string' or text == '' then
        return text
    end

    -- Only retitle words that contain lowercase letters (preserves DEF, STR, HP+15, etc.).
    return text:gsub('[%a][%a\']*', function(word)
        if word:find('%l') then
            return word:sub(1, 1):upper() .. word:sub(2):lower()
        end
        return word
    end)
end

function M.format_item_name(text)
    if type(text) ~= 'string' or text == '' then
        return text
    end

    return (text:gsub('(%a)([%w\']*)', function(first, rest)
        return first:upper() .. rest:lower()
    end))
end

function M.format_augment_display_line(line)
    if type(line) ~= 'string' or line == '' then
        return line
    end

    line = line:gsub('^(%[%d+%])(%S)', '%1 %2')
    return M.title_case_words(line)
end

function M.strip_elemental_resist_words(line)
    if type(line) ~= 'string' or line == '' then
        return line
    end

    if line:lower():find('all elemental resist', 1, true) then
        return line
    end

    for _, elem in ipairs(ELEMENT_ORDER) do
        line = line:gsub('(' .. elem .. ')%s+[Rr]esistance%s*([%+%-]%d+)', '%1%2')
        line = line:gsub('(' .. elem .. ')%s+[Rr]esist%s*([%+%-]%d+)', '%1%2')
    end

    return line
end

local function is_element_name(text)
    if type(text) ~= 'string' or text == '' then
        return false
    end
    for _, elem in ipairs(ELEMENT_ORDER) do
        if text == elem then
            return true
        end
    end
    return false
end

local function push_token(tokens, kind, value, extra)
    tokens[#tokens + 1] = {
        kind = kind,
        value = value,
        name = extra,
    }
end

function M.word_split_tokens(line)
    clear_table(scratch_tokens)
    if type(line) ~= 'string' or line == '' then
        return scratch_tokens
    end

    local pos = 1
    while pos <= #line do
        local ws_end = line:find('%S', pos)
        if not ws_end then
            break
        end
        local word_end = line:find('%s', ws_end) or (#line + 1)
        local word = line:sub(ws_end, word_end - 1)
        if word ~= '' then
            if is_element_name(word) then
                push_token(scratch_tokens, 'elem_word', word, word)
            else
                push_token(scratch_tokens, 'text', word)
            end
        end
        pos = word_end
    end

    return scratch_tokens
end

function M.merge_element_groups(tokens)
    clear_table(scratch_units)
    local i = 1
    while i <= #tokens do
        local token = tokens[i]
        if token.kind == 'elem_word' then
            local unit = { kind = 'elem_group', parts = { token } }
            local next_token = tokens[i + 1]
            if next_token and next_token.kind == 'text' then
                local value = next_token.value:gsub('^%s+', '')
                if value:match('^[%+%-]') then
                    unit.parts[#unit.parts + 1] = { kind = 'text', value = value }
                    i = i + 2
                    scratch_units[#scratch_units + 1] = unit
                else
                    scratch_units[#scratch_units + 1] = unit
                    i = i + 1
                end
            else
                scratch_units[#scratch_units + 1] = unit
                i = i + 1
            end
        elseif token.kind == 'text' then
            scratch_units[#scratch_units + 1] = { kind = 'text_group', parts = { token } }
            i = i + 1
        else
            i = i + 1
        end
    end
    return scratch_units
end

local function measure_part_width(part, font_family, pixel_size, element_colors)
    if part.kind == 'elem_word' then
        return fontcore.calc_text_width(part.value, font_family, pixel_size)
    end
    if part.kind == 'text' then
        return fontcore.calc_text_width(part.value, font_family, pixel_size)
    end
    return 0
end

local function measure_unit_width(unit, font_family, pixel_size, element_colors)
    local total = 0
    for index, part in ipairs(unit.parts or {}) do
        total = total + measure_part_width(part, font_family, pixel_size, element_colors)
    end
    return total
end

local function get_space_width(font_family, pixel_size)
    return fontcore.calc_text_width(' ', font_family, pixel_size)
end

function M.layout_row_pack(units, wrap_width, font_family, pixel_size)
    clear_table(scratch_rows)
    local space_w = get_space_width(font_family, pixel_size)
    local row = { units = {}, width = 0 }
    scratch_rows[#scratch_rows + 1] = row

    for _, unit in ipairs(units or {}) do
        local unit_w = measure_unit_width(unit, font_family, pixel_size)
        local gap = (#row.units > 0) and space_w or 0
        if #row.units > 0 and (row.width + gap + unit_w) > wrap_width then
            row = { units = {}, width = 0 }
            scratch_rows[#scratch_rows + 1] = row
            gap = 0
        end
        row.width = row.width + gap + unit_w
        row.units[#row.units + 1] = unit
    end

    return scratch_rows
end

function M.render_unit_parts(parts, color, element_colors, render_text_fn)
    for index, part in ipairs(parts or {}) do
        if index > 1 then
            imgui.SameLine(0, 0)
        end
        if part.kind == 'elem_word' then
            local elem_color = element_colors[part.name] or { 0.88, 0.88, 0.88, 1.0 }
            imgui.TextColored(elem_color, part.value)
        elseif render_text_fn then
            render_text_fn(color, part.value)
        else
            imgui.TextColored(color, part.value)
        end
    end
end

function M.render_layout_rows(rows, color, element_colors, render_text_fn)
    for row_index, row in ipairs(rows or {}) do
        if row_index > 1 then
            imgui.Spacing()
        end
        local started = false
        for unit_index, unit in ipairs(row.units or {}) do
            if unit_index > 1 then
                imgui.SameLine(0, 0)
                imgui.TextColored(color, ' ')
                imgui.SameLine(0, 0)
            end
            M.render_unit_parts(unit.parts, color, element_colors, render_text_fn)
            started = true
        end
        if not started then
            imgui.Dummy({ 0, 0 })
        end
    end
end

function M.render_option_c_line(line, color, element_colors, wrap_width, font_family, pixel_size, render_text_fn)
    line = M.strip_elemental_resist_words(line)
    local tokens = M.word_split_tokens(line)
    local units = M.merge_element_groups(tokens)
    local rows = M.layout_row_pack(units, wrap_width, font_family, pixel_size)
    M.render_layout_rows(rows, color, element_colors, render_text_fn)
end

function M.render_augment_option_c_line(line, color, element_colors, wrap_width, font_family, pixel_size, render_text_fn)
    line = M.format_augment_display_line(M.strip_elemental_resist_words(line))
    M.render_option_c_line(line, color, element_colors, wrap_width, font_family, pixel_size, render_text_fn)
end

function M.get_scaled_metrics(pixel_size_or_scale)
    local px
    local scale
    if M.is_valid_font_size(pixel_size_or_scale) then
        px = M.normalize_font_size(pixel_size_or_scale)
        scale = px / M.BASE_FONT_PX
    else
        -- Legacy scale multiplier (e.g. 1.0).
        scale = tonumber(pixel_size_or_scale) or 1.0
        px = M.normalize_font_size(M.BASE_FONT_PX * scale)
        scale = px / M.BASE_FONT_PX
    end

    local padding = math.floor(M.BASE_PADDING * scale + 0.5)
    local icon_size = fontcore.quantize_pixel_size(M.BASE_ICON_SIZE * scale)
    local smaller = M.smaller_font_sizes(px)
    local footer_min_px = (#smaller > 0) and smaller[#smaller] or px
    return {
        pixel_size = px,
        tooltip_width = math.floor(M.BASE_TOOLTIP_WIDTH * scale + 0.5),
        padding = padding,
        wrap_width = math.floor(M.BASE_WRAP_WIDTH * scale + 0.5),
        tag_size = icon_size,
        icon_size = icon_size,
        icon_gap = math.max(1, math.floor(M.BASE_ICON_GAP * scale + 0.5)),
        name_tag_gap = math.floor(M.BASE_NAME_TAG_GAP * scale + 0.5),
        sep_padding = math.max(1, math.floor(M.BASE_SEP_PAD * scale + 0.5)),
        footer_gap = math.max(1, math.floor(M.BASE_FOOTER_GAP * scale + 0.5)),
        footer_min_px = footer_min_px,
    }
end

function M.line_needs_option_c(line, as_words)
    if not as_words or type(line) ~= 'string' or line == '' then
        return false
    end
    for _, elem in ipairs(ELEMENT_ORDER) do
        if line:find(elem, 1, true) then
            return true
        end
    end
    return false
end

-- Fonts and glyph fallbacks
M.WAVE_DASH = '\227\128\156' -- UTF-8 U+301C ?
M.TRI_SOLID = '\226\150\178' -- UTF-8 U+25B2 ?
M.TRI_HOLLOW = '\226\150\179' -- UTF-8 U+25B3 ?
M.WAVE_PAD_X = 2

local WAVE_DASH_CHAR = M.WAVE_DASH
local WAVE_DASH_MARKER = '{{WAVE}}'

local sync_state = {
    family = '',
    pixel_size = 0,
}

-- Pending pair to load at the start of the next present (nil when idle).
local pending_load = nil
local push_depth = 0

local function get_tooltip_family()
    return (gConfig and gConfig.satchelTooltipFontFamily) or 'Consolas'
end

local function get_tooltip_font_size()
    return M.normalize_font_size(gConfig and gConfig.satchelTooltipFontSize)
end

local function apply_settings_change(family, pixel_size)
    pixel_size = M.normalize_font_size(pixel_size)
    local changed = sync_state.family ~= family or sync_state.pixel_size ~= pixel_size

    if changed then
        sync_state.family = family
        sync_state.pixel_size = pixel_size
        M.clear_glyph_cache()
    end

    return pixel_size
end

local function load_pair_now(family, pixel_size)
    pixel_size = apply_settings_change(family, pixel_size)
    fontcore.load_font(family, pixel_size, true)
    return fontcore.is_cached(family, pixel_size)
end

-- Queue active selection if not already in the atlas. Present-safe (no load).
local function queue_active_pair()
    local family = get_tooltip_family()
    local pixel_size = get_tooltip_font_size()
    apply_settings_change(family, pixel_size)

    if fontcore.is_cached(family, pixel_size) then
        pending_load = nil
        return false
    end

    pending_load = {
        family = family,
        pixel_size = pixel_size,
    }
    return true
end

function M.font_display_name(family)
    if family == 'Consolas' then
        return 'Consolas (Default)'
    end
    return family
end

function M.get_metrics()
    local family = get_tooltip_family()
    local pixel_size = get_tooltip_font_size()
    local metrics = M.get_scaled_metrics(pixel_size)
    metrics.family = family
    metrics.scale = pixel_size / M.BASE_FONT_PX
    metrics.line_height = fontcore.get_tooltip_line_height(family, pixel_size)
    return metrics
end

function M.notify_font_changed()
    queue_active_pair()
end

function M.notify_size_changed()
    queue_active_pair()
end

-- Load-event only: active family + active size.
function M.prewarm_startup()
    pending_load = nil
    -- Bake every selectable size for the active family at the load event so runtime
    -- size changes are a pure cache lookup (mid-frame atlas mutation is unsafe).
    local family = get_tooltip_family()
    for i = 1, #M.FONT_SIZES do
        fontcore.load_font(family, M.FONT_SIZES[i], true)
    end
    -- Point sync_state/glyph cache at the active size (already baked above).
    return load_pair_now(family, get_tooltip_font_size())
end

function M.on_satchel_config_hidden()
end

function M.has_pending_load()
    return pending_load ~= nil
end

-- Call once at the top of d3d_present, before any module/config draw.
-- Loads at most one queued family+size pair.
function M.tick_load()
    if not pending_load then
        return false
    end

    local family = pending_load.family
    local pixel_size = pending_load.pixel_size
    pending_load = nil
    load_pair_now(family, pixel_size)
    return true
end

function M.get_wave_dash_marker()
    return WAVE_DASH_MARKER
end

function M.push_tooltip_font()
    local metrics = M.get_metrics()
    local ok = fontcore.push_tooltip_font(metrics.family, metrics.pixel_size)
    if ok then
        push_depth = push_depth + 1
    end
    return ok, metrics
end

function M.pop_tooltip_font()
    if push_depth > 0 then
        fontcore.pop_tooltip_font()
        push_depth = push_depth - 1
    end
end

function M.calc_text_width(text)
    local metrics = M.get_metrics()
    return fontcore.calc_tooltip_text_width(text, metrics.family, metrics.pixel_size)
end

function M.sync()
    apply_settings_change(get_tooltip_family(), get_tooltip_font_size())
    return true
end


-- Glyph fallbacks (wave / triangles) for fonts missing those codepoints.
local SPECIALS = {
    { char = M.WAVE_DASH, len = #M.WAVE_DASH },
    { char = M.TRI_SOLID, len = #M.TRI_SOLID },
    { char = M.TRI_HOLLOW, len = #M.TRI_HOLLOW },
}

local glyph_cache = {}

-- Ashita main/4.16 TextColored is printf-style; 4.3 is not.
local imgui_needs_printf_escape = (ImGuiChildFlags_Borders == nil)

local function escape_imgui_format(text)
    if type(text) ~= 'string' or text == '' then
        return text
    end
    if not imgui_needs_printf_escape then
        return text
    end
    return (text:gsub('%%', '%%%%'))
end

local function cache_key(family, pixel_size, char)
    return string.format('%s:%d:%s', tostring(family or ''), math.floor(tonumber(pixel_size) or 14), char)
end

function M.clear_glyph_cache()
    for key in pairs(glyph_cache) do
        glyph_cache[key] = nil
    end
end

local function calc_width_with_font(text, family, pixel_size)
    if type(text) ~= 'string' or text == '' then
        return 0
    end
    return fontcore.calc_text_width(text, family, pixel_size)
end

local function glyph_renders_distinct(char, family, pixel_size)
    local char_width = calc_width_with_font(char, family, pixel_size)
    if char_width < 2 then
        return false
    end

    local missing_width = calc_width_with_font('?', family, pixel_size)
    local space_width = calc_width_with_font(' ', family, pixel_size)

    if math.abs(char_width - missing_width) < 0.5 then
        return false
    end
    if math.abs(char_width - space_width) < 0.5 then
        return false
    end
    return true
end

function M.font_has_glyph(family, pixel_size, char)
    if type(char) ~= 'string' or char == '' then
        return false
    end

    local key = cache_key(family, pixel_size, char)
    local cached = glyph_cache[key]
    if cached ~= nil then
        return cached == true
    end

    local distinct = glyph_renders_distinct(char, family, pixel_size)
    glyph_cache[key] = distinct
    return distinct
end

function M.should_use_fallback(family, pixel_size, char)
    if type(char) ~= 'string' or char == '' then
        return false
    end
    for _, entry in ipairs(SPECIALS) do
        if entry.char == char then
            return not M.font_has_glyph(family, pixel_size, char)
        end
    end
    return false
end

function M.text_has_fallback_symbols(text, family, pixel_size)
    if type(text) ~= 'string' or text == '' then
        return false
    end

    for _, entry in ipairs(SPECIALS) do
        if text:find(entry.char, 1, true) and M.should_use_fallback(family, pixel_size, entry.char) then
            return true
        end
    end
    return false
end

function M.line_height(pixel_size, family)
    local pushed_h = tonumber(imgui.GetTextLineHeight())
    if pushed_h and pushed_h > 0 then
        return pushed_h
    end
    pixel_size = math.floor(tonumber(pixel_size) or 14)
    if family then
        return fontcore.get_line_height(family, pixel_size)
    end
    return pixel_size + 2
end

function M.visual_text_center_y(screen_y, pixel_size, family)
    return screen_y + M.line_height(pixel_size, family) * 0.42
end

function M.wave_body_width(pixel_size)
    pixel_size = math.floor(tonumber(pixel_size) or 14)
    return math.max(9.0, pixel_size * 0.95)
end

function M.wave_metrics(pixel_size, family)
    local h = M.line_height(pixel_size, family)
    local wave_height = math.max(3.0, h * 0.15)
    return wave_height, wave_height / 2.0
end

function M.wave_dash_width(family, pixel_size)
    if not M.should_use_fallback(family, pixel_size, M.WAVE_DASH) then
        return calc_width_with_font(M.WAVE_DASH, family, pixel_size)
    end
    return M.wave_body_width(pixel_size) + M.WAVE_PAD_X * 2
end

function M.triangle_width(family, pixel_size, char)
    if not M.should_use_fallback(family, pixel_size, char) then
        return calc_width_with_font(char, family, pixel_size)
    end
    pixel_size = math.floor(tonumber(pixel_size) or 14)
    return math.max(8.0, pixel_size * 0.82)
end

function M.symbol_width(family, pixel_size, char)
    if char == M.WAVE_DASH then
        return M.wave_dash_width(family, pixel_size)
    end
    if char == M.TRI_SOLID or char == M.TRI_HOLLOW then
        return M.triangle_width(family, pixel_size, char)
    end
    return calc_width_with_font(char, family, pixel_size)
end

local function find_next_special(text, from_index)
    local best_index = nil
    local best_entry = nil

    for _, entry in ipairs(SPECIALS) do
        local found = text:find(entry.char, from_index, true)
        if found and (not best_index or found < best_index) then
            best_index = found
            best_entry = entry
        end
    end

    return best_index, best_entry
end

function M.text_width(family, pixel_size, text)
    if type(text) ~= 'string' or text == '' then
        return 0
    end

    local total = 0
    local pos = 1

    while pos <= #text do
        local special_at, entry = find_next_special(text, pos)
        if not special_at then
            total = total + calc_width_with_font(text:sub(pos), family, pixel_size)
            break
        end

        if special_at > pos then
            total = total + calc_width_with_font(text:sub(pos, special_at - 1), family, pixel_size)
        end

        total = total + M.symbol_width(family, pixel_size, entry.char)
        pos = special_at + entry.len
    end

    return total
end

function M.draw_wave_fallback(draw_list, x, y, body_w, color, pixel_size, family)
    if not draw_list then
        return
    end

    local _, amp = M.wave_metrics(pixel_size, family)
    local center_y = M.visual_text_center_y(y, pixel_size, family)
    local col = imgui.GetColorU32(color or { 0.88, 0.88, 0.88, 1.0 })
    local segments = 14
    local prev_x = x
    local prev_y = center_y

    for i = 1, segments do
        local t = i / segments
        local px = x + body_w * t
        local py
        if t <= 0.5 then
            py = center_y - amp * math.sin(t * math.pi * 2)
        else
            py = center_y + amp * math.sin((t - 0.5) * math.pi * 2)
        end
        draw_list:AddLine({ prev_x, prev_y }, { px, py }, col, 1.0)
        prev_x = px
        prev_y = py
    end
end

function M.draw_triangle_fallback(draw_list, x, y, w, color, hollow, pixel_size, family)
    if not draw_list then
        return
    end

    local center_y = M.visual_text_center_y(y, pixel_size, family)
    local half = M.line_height(pixel_size, family) * 0.5 * 0.82
    local top = center_y - half * 0.82
    local bottom = center_y + half * 0.82
    local left = x + w * 0.12
    local right = x + w * 0.88
    local center_x = x + w * 0.5
    local col = imgui.GetColorU32(color or { 0.88, 0.88, 0.88, 1.0 })

    local p1 = { center_x, top }
    local p2 = { right, bottom }
    local p3 = { left, bottom }

    if hollow then
        draw_list:AddTriangle(p1, p2, p3, col, 1.0)
    else
        draw_list:AddTriangleFilled(p1, p2, p3, col)
    end
end

function M.draw_symbol_fallback(draw_list, char, x, y, color, family, pixel_size)
    if char == M.WAVE_DASH then
        local body_w = M.wave_body_width(pixel_size)
        M.draw_wave_fallback(draw_list, x + M.WAVE_PAD_X, y, body_w, color, pixel_size, family)
        return body_w + M.WAVE_PAD_X * 2
    end

    local w = M.symbol_width(family, pixel_size, char)
    if char == M.TRI_SOLID then
        M.draw_triangle_fallback(draw_list, x, y, w, color, false, pixel_size, family)
    elseif char == M.TRI_HOLLOW then
        M.draw_triangle_fallback(draw_list, x, y, w, color, true, pixel_size, family)
    end
    return w
end

function M.render_symbol_inline(char, color, family, pixel_size)
    if not M.should_use_fallback(family, pixel_size, char) then
        imgui.TextColored(color, char)
        return
    end

    local x, y = imgui.GetCursorScreenPos()
    local h = M.line_height(pixel_size, family)
    local draw_list = imgui.GetWindowDrawList()
    local w = M.draw_symbol_fallback(draw_list, char, x, y, color, family, pixel_size)
    imgui.Dummy({ w, h })
end

function M.render_text_with_symbols(color, text, family, pixel_size)
    if type(text) ~= 'string' or text == '' then
        return
    end

    local pos = 1
    local started = false

    while pos <= #text do
        local special_at, entry = find_next_special(text, pos)
        if not special_at then
            local chunk = escape_imgui_format(text:sub(pos))
            if chunk ~= '' then
                if started then
                    imgui.SameLine(0, 0)
                end
                imgui.TextColored(color, chunk)
            end
            break
        end

        if special_at > pos then
            local chunk = escape_imgui_format(text:sub(pos, special_at - 1))
            if chunk ~= '' then
                if started then
                    imgui.SameLine(0, 0)
                end
                imgui.TextColored(color, chunk)
                started = true
            end
        end

        if started then
            imgui.SameLine(0, 0)
        end
        M.render_symbol_inline(entry.char, color, family, pixel_size)
        started = true
        pos = special_at + entry.len
    end
end

-- Status and element icons
local preload_state = {
    attempted = false,
    complete = false,
}

local ELEMENT_ICON_SIZE = 14
local TAG_ICON_SIZE = 14

local function get_icon_sizes()
    local metrics = M.get_metrics()
    return metrics.icon_size or ELEMENT_ICON_SIZE, metrics.icon_size or TAG_ICON_SIZE
end

local function calc_width(text, pixel_size)
    if pixel_size then
        local metrics = M.get_metrics()
        return fontcore.calc_text_width(text, metrics.family, pixel_size)
    end
    return tonumber(imgui.CalcTextSize(text)) or 0
end

M.ELEMENT_ICON_SIZE = ELEMENT_ICON_SIZE
M.TAG_ICON_SIZE = TAG_ICON_SIZE

M.ELEMENTS = {
    { byte = 0x1F, id = 1, name = 'Fire', file = 'fire.png' },
    { byte = 0x20, id = 2, name = 'Ice', file = 'ice.png' },
    { byte = 0x21, id = 3, name = 'Wind', file = 'wind.png' },
    { byte = 0x22, id = 4, name = 'Earth', file = 'earth.png' },
    { byte = 0x23, id = 5, name = 'Lightning', file = 'lightning.png' },
    { byte = 0x24, id = 6, name = 'Water', file = 'water.png' },
    { byte = 0x25, id = 7, name = 'Light', file = 'light.png' },
    { byte = 0x26, id = 8, name = 'Dark', file = 'dark.png' },
}

M.ELEMENT_BY_BYTE = {}
M.ELEMENT_COLORS = {}
for _, entry in ipairs(M.ELEMENTS) do
    M.ELEMENT_BY_BYTE[entry.byte] = entry
end

M.STATUS_TAGS = {
    rare = { label = 'Rare', file = 'Rare.png', color = { 0.95, 0.88, 0.35, 1.0 } },
    ex = { label = 'Ex', file = 'Ex.png', color = { 0.28, 0.78, 0.38, 1.0 } },
    alt = { label = 'Alt', file = 'Alt.png', color = { 0.35, 0.55, 0.95, 1.0 } },
    tmp = { label = 'Tmp', file = 'Tmp.png', color = { 0.55, 0.65, 0.78, 1.0 } },
    aug = { label = 'Aug', file = 'Aug.png', color = { 0.85, 0.28, 0.28, 1.0 } },
}

function M.icons_as_words()
    return gConfig and gConfig.satchelTooltipIconsAsWords == true
end

local function strip_png_extension(file_name)
    if type(file_name) ~= 'string' then
        return ''
    end
    return file_name:gsub('%.png$', '')
end

local function try_load_file_texture(paths)
    for _, path in ipairs(paths or {}) do
        if type(path) == 'string' and path ~= '' then
            local tex = TextureManager.getFileTexture(path)
            if tex and TextureManager.getTexturePtr(tex) then
                return tex
            end
        end
    end
    return nil
end

function M.load_element_icon(_satchel, _addon_path, element_entry)
    local root = 'satchel/elements/' .. strip_png_extension(element_entry.file)
    return try_load_file_texture({
        root,
        ('satchel/upscaled/%d'):format(element_entry.id),
    })
end

function M.load_status_icon(_satchel, _addon_path, tag_key)
    local tag = M.STATUS_TAGS[tag_key]
    if not tag then
        return nil
    end

    return try_load_file_texture({
        'satchel/tags/' .. strip_png_extension(tag.file),
    })
end

function M.preload_assets(_satchel, _addon_path)
    if preload_state.complete then
        return true
    end

    if preload_state.attempted then
        return false
    end

    preload_state.attempted = true

    for _, entry in ipairs(M.ELEMENTS) do
        M.load_element_icon(nil, nil, entry)
    end

    for tag_key in pairs(M.STATUS_TAGS) do
        M.load_status_icon(nil, nil, tag_key)
    end

    preload_state.complete = true
    return true
end

function M.get_status_color(tag_key)
    local tag = M.STATUS_TAGS[tag_key]
    return tag and tag.color or { 1.0, 1.0, 1.0, 1.0 }
end

function M.get_status_label(tag_key)
    local tag = M.STATUS_TAGS[tag_key]
    return tag and tag.label or tag_key
end

function M.get_element_color(name)
    return M.ELEMENT_COLORS[name] or { 0.88, 0.88, 0.88, 1.0 }
end

function M.set_element_colors(color_table)
    M.ELEMENT_COLORS = color_table or {}
end

local function render_tooltip_icon_image(texture, size)
    local ptr = texture and TextureManager.getTexturePtr(texture) or nil
    if not ptr or ptr == 0 then
        return false
    end

    local draw_list = imgui.GetWindowDrawList()
    if not draw_list then
        return false
    end

    local x, y = imgui.GetCursorScreenPos()
    draw_list:AddImage(
        ptr,
        { x, y },
        { x + size, y + size },
        { 0, 0 },
        { 1, 1 }
    )
    imgui.Dummy({ size, size })
    return true
end

function M.measure_status_tag_width(satchel, addon_path, tag_key, as_words)
    if as_words then
        return calc_width(M.get_status_label(tag_key))
    end

    local _, tag_size = get_icon_sizes()
    local tex = M.load_status_icon(satchel, addon_path, tag_key)
    if tex then
        return tag_size
    end

    return calc_width(M.get_status_label(tag_key))
end

function M.measure_status_tags_width(satchel, addon_path, tags, as_words)
    local total = 0
    for _, tag_key in ipairs(tags or {}) do
        total = total + M.measure_status_tag_width(satchel, addon_path, tag_key, as_words)
    end
    return total
end

function M.render_status_tag(satchel, addon_path, tag_key, as_words)
    if as_words then
        imgui.TextColored(M.get_status_color(tag_key), M.get_status_label(tag_key))
        return
    end

    local _, tag_size = get_icon_sizes()
    local tex = M.load_status_icon(satchel, addon_path, tag_key)
    if tex and render_tooltip_icon_image(tex, tag_size) then
        return
    end

    imgui.TextColored(M.get_status_color(tag_key), M.get_status_label(tag_key))
end

function M.render_element_token(satchel, addon_path, element_entry, as_words)
    if as_words then
        imgui.TextColored(M.get_element_color(element_entry.name), element_entry.name)
        return
    end

    local element_size = get_icon_sizes()
    local tex = M.load_element_icon(satchel, addon_path, element_entry)
    if tex and render_tooltip_icon_image(tex, element_size) then
        return
    end

    imgui.TextColored(M.get_element_color(element_entry.name), element_entry.name)
end

local function get_element_entry_by_index(element_index)
    for _, entry in ipairs(M.ELEMENTS) do
        if entry.id == element_index then
            return entry
        end
    end
    return nil
end

function M.measure_elemental_footer_entry_width(entry, as_words, pixel_size, family)
    if type(entry) ~= 'table' then
        return 0
    end

    family = family or M.get_metrics().family
    pixel_size = pixel_size or M.get_metrics().pixel_size

    local slot_text = ('[%d]'):format(tonumber(entry.slot) or 0)
    local triangle = entry.positive == false and M.TRI_HOLLOW or M.TRI_SOLID
    local value_text = tostring(tonumber(entry.value) or 0)
    -- No gap between [n], element icon/name, and ▲value.
    local width = M.text_width(family, pixel_size, slot_text)

    local element_entry = get_element_entry_by_index(entry.element_index)
    if as_words then
        width = width + M.text_width(family, pixel_size, element_entry and element_entry.name or '?')
    elseif element_entry then
        local _, tag_size = get_icon_sizes()
        width = width + tag_size
    else
        width = width + M.text_width(family, pixel_size, '?')
    end

    width = width + M.text_width(family, pixel_size, triangle .. value_text)
    return width
end

function M.measure_elemental_footer_width(satchel, addon_path, entries, as_words, pixel_size, family)
    family = family or M.get_metrics().family
    pixel_size = pixel_size or M.get_metrics().pixel_size
    local total = M.text_width(family, pixel_size, '<')
        + M.text_width(family, pixel_size, '>')
    for index, entry in ipairs(entries or {}) do
        if index > 1 then
            total = total + M.text_width(family, pixel_size, ' ')
        end
        total = total + M.measure_elemental_footer_entry_width(entry, as_words, pixel_size, family)
    end
    return total
end

local function draw_footer_text(draw_list, x, y, text, color, family, pixel_size)
    if not draw_list or type(text) ~= 'string' or text == '' then
        return 0
    end

    local col = imgui.GetColorU32(color)
    local font = fontcore.get_font(family, pixel_size, false)
    if font then
        draw_list:AddText(font, pixel_size * 1.0, { x, y }, col, text)
    else
        draw_list:AddText({ x, y }, col, text)
    end
    return M.text_width(family, pixel_size, text)
end

local function draw_footer_entry(draw_list, x, y, satchel, addon_path, entry, as_words, color, family, pixel_size)
    if type(entry) ~= 'table' then
        return 0
    end

    local cursor_x = x
    local slot_text = ('[%d]'):format(tonumber(entry.slot) or 0)
    cursor_x = cursor_x + draw_footer_text(draw_list, cursor_x, y, slot_text, color, family, pixel_size)

    local element_entry = get_element_entry_by_index(entry.element_index)
    local icon_size = select(1, get_icon_sizes())
    if as_words then
        local name = element_entry and element_entry.name or '?'
        local name_color = element_entry and M.get_element_color(element_entry.name) or color
        cursor_x = cursor_x + draw_footer_text(draw_list, cursor_x, y, name, name_color, family, pixel_size)
    elseif element_entry then
        local tex = M.load_element_icon(satchel, addon_path, element_entry)
        local ptr = tex and TextureManager.getTexturePtr(tex) or nil
        if ptr and ptr ~= 0 then
            draw_list:AddImage(ptr, { cursor_x, y }, { cursor_x + icon_size, y + icon_size }, { 0, 0 }, { 1, 1 })
            cursor_x = cursor_x + icon_size
        else
            cursor_x = cursor_x + draw_footer_text(draw_list, cursor_x, y, element_entry.name, color, family, pixel_size)
        end
    else
        cursor_x = cursor_x + draw_footer_text(draw_list, cursor_x, y, '?', color, family, pixel_size)
    end

    local triangle = entry.positive == false and M.TRI_HOLLOW or M.TRI_SOLID
    local value_text = tostring(tonumber(entry.value) or 0)
    if M.text_has_fallback_symbols(triangle, family, pixel_size) then
        local tri_w = M.draw_symbol_fallback(
            draw_list, triangle, cursor_x, y, color, family, pixel_size) or 0
        cursor_x = cursor_x + tri_w
        cursor_x = cursor_x + draw_footer_text(draw_list, cursor_x, y, value_text, color, family, pixel_size)
    else
        cursor_x = cursor_x + draw_footer_text(
            draw_list, cursor_x, y, triangle .. value_text, color, family, pixel_size)
    end

    return cursor_x - x
end

function M.render_elemental_footer_entry(satchel, addon_path, entry, as_words, color)
    -- Kept for callers that still use layout widgets; prefer draw-list footer path.
    if type(entry) ~= 'table' then
        return
    end

    color = color or { 0.92, 0.92, 0.92, 1.0 }
    local metrics = M.get_metrics()

    imgui.TextColored(color, ('[%d]'):format(tonumber(entry.slot) or 0))
    imgui.SameLine(0, 0)

    local element_entry = get_element_entry_by_index(entry.element_index)
    if element_entry then
        M.render_element_token(satchel, addon_path, element_entry, as_words)
        imgui.SameLine(0, 0)
    end

    local triangle = entry.positive == false and M.TRI_HOLLOW or M.TRI_SOLID
    local value_text = tostring(tonumber(entry.value) or 0)
    if M.text_has_fallback_symbols(triangle, metrics.family, metrics.pixel_size) then
        M.render_text_with_symbols(color, triangle, metrics.family, metrics.pixel_size)
        imgui.SameLine(0, 0)
        imgui.TextColored(color, value_text)
    else
        imgui.TextColored(color, triangle .. value_text)
    end
end

function M.render_elemental_footer_right(satchel, addon_path, entries, color, as_words)
    entries = entries or {}
    if #entries == 0 then
        return
    end

    color = color or { 0.92, 0.92, 0.92, 1.0 }
    as_words = as_words == true

    local metrics = M.get_metrics()
    local padding = metrics.padding or 10
    local window_w = tonumber(imgui.GetWindowWidth()) or 0
    local avail_w = math.max(0, window_w - padding * 2)
    local pixel_size = metrics.pixel_size
    local family = metrics.family
    local width = M.measure_elemental_footer_width(
        satchel, addon_path, entries, as_words, pixel_size, family)

    -- Prefer shrinking over wrapping when icons-as-words is on.
    if width > avail_w then
        local smaller = M.smaller_font_sizes(pixel_size)
        for i = 1, #smaller do
            local shrink_px = smaller[i]
            local shrunk_w = M.measure_elemental_footer_width(
                satchel, addon_path, entries, as_words, shrink_px, family)
            if shrunk_w <= avail_w then
                pixel_size = shrink_px
                width = shrunk_w
                break
            end
        end
    end

    local draw_list = imgui.GetWindowDrawList()
    local line_h = tonumber(imgui.GetTextLineHeight()) or pixel_size
    local window_x = select(1, imgui.GetWindowPos())
    local screen_y = select(2, imgui.GetCursorScreenPos())

    -- Draw-list path never wraps. Right-align when it fits; otherwise start at
    -- the left padding (may clip) rather than breaking onto multiple lines.
    if draw_list and window_x and screen_y then
        local start_x = padding
        if width <= avail_w then
            start_x = math.max(padding, window_w - width - padding)
        end

        local x = window_x + start_x
        x = x + draw_footer_text(draw_list, x, screen_y, '<', color, family, pixel_size)

        for index, entry in ipairs(entries) do
            if index > 1 then
                x = x + draw_footer_text(draw_list, x, screen_y, ' ', color, family, pixel_size)
            end
            x = x + draw_footer_entry(
                draw_list, x, screen_y, satchel, addon_path, entry, as_words, color, family, pixel_size)
        end

        draw_footer_text(draw_list, x, screen_y, '>', color, family, pixel_size)
        imgui.Dummy({ 0, line_h })
        return
    end

    -- Fallback if draw list is unavailable: still avoid wrap when content fits.
    local right_x = (width <= avail_w) and math.max(0, avail_w - width) or 0
    imgui.PushTextWrapPos((width <= avail_w) and 100000 or (padding + avail_w))
    imgui.SetCursorPosX(right_x)
    imgui.TextColored(color, '<')
    imgui.SameLine(0, 0)

    for index, entry in ipairs(entries) do
        if index > 1 then
            imgui.SameLine(0, 0)
            imgui.TextColored(color, ' ')
        end
        M.render_elemental_footer_entry(satchel, addon_path, entry, as_words, color)
    end

    imgui.SameLine(0, 0)
    imgui.TextColored(color, '>')
    imgui.PopTextWrapPos()
end

return M
