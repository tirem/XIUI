--[[
    Satchel tooltip Option C row-pack layout for icons-as-words mode.
]]--

local imgui = require('imgui')
local fontcore = require('modules.satchel.satchelfontcore')

local M = {}

M.BASE_FONT_PX = 14
M.BASE_WRAP_WIDTH = 305
M.BASE_MAX_WIDTH = 325
M.BASE_WIDTH_PAD = 16
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

    return text:gsub('%a+', function(word)
        if #word <= 1 then
            return word:upper()
        end
        return word:sub(1, 1):upper() .. word:sub(2):lower()
    end)
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

function M.measure_layout_width(rows, font_family, pixel_size)
    local max_w = 0
    for _, row in ipairs(rows or {}) do
        max_w = math.max(max_w, row.width or 0)
    end
    return max_w
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

function M.get_scaled_metrics(tooltip_scale)
    local scale = tonumber(tooltip_scale) or 1.0
    local px = fontcore.quantize_pixel_size(M.BASE_FONT_PX * scale)
    return {
        pixel_size = px,
        wrap_width = math.floor(M.BASE_WRAP_WIDTH * scale + 0.5),
        max_width = math.floor(M.BASE_MAX_WIDTH * scale + 0.5),
        width_pad = math.floor(M.BASE_WIDTH_PAD * scale + 0.5),
        icon_size = fontcore.quantize_pixel_size(14 * scale),
        sep_padding = math.max(1, math.floor(3 * scale + 0.5)),
        footer_min_px = math.max(M.FOOTER_MIN_SHRINK_PX, fontcore.quantize_pixel_size(M.FOOTER_MIN_SHRINK_PX * scale)),
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

return M
