local searchhighlight = {}

local imgui = require('imgui')

local SEARCH_HIGHLIGHT_COLOR = 0xFFD4AA44

local last_clock_read = 0
local cached_anim_offset = 0

local function get_animation_offset()
    local now = os.clock()
    if now ~= last_clock_read then
        last_clock_read = now
        cached_anim_offset = (now * 50) % 16
    end
    return cached_anim_offset
end

local function draw_dashed_line(draw_list, x1, y1, x2, y2, color, thickness, dash_len, gap_len, offset)
    local dx = x2 - x1
    local dy = y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len == 0 then
        return
    end

    local nx = dx / len
    local ny = dy / len
    local total_len = dash_len + gap_len
    local start_offset = offset % total_len
    local pos = -start_offset

    while pos < len do
        local dash_start = math.max(0, pos)
        local dash_end = math.min(len, pos + dash_len)

        if dash_end > dash_start then
            local sx = x1 + nx * dash_start
            local sy = y1 + ny * dash_start
            local ex = x1 + nx * dash_end
            local ey = y1 + ny * dash_end
            draw_list:AddLine({ sx, sy }, { ex, ey }, color, thickness)
        end

        pos = pos + total_len
    end
end

function searchhighlight.draw_match_border(draw_list, x, y, size, opacity)
    if not draw_list or not size or size <= 0 or (opacity or 1) <= 0.01 then
        return
    end

    local color = SEARCH_HIGHLIGHT_COLOR
    local anim_offset = get_animation_offset()
    local alpha = math.floor(bit.rshift(bit.band(color, 0xFF000000), 24) * (opacity or 1))
    local r = bit.rshift(bit.band(color, 0x00FF0000), 16) / 255
    local g = bit.rshift(bit.band(color, 0x0000FF00), 8) / 255
    local b = bit.band(color, 0x000000FF) / 255
    local line_color = imgui.GetColorU32({ r, g, b, alpha / 255 })

    local dash_len = 4
    local gap_len = 4
    local thickness = 2

    draw_dashed_line(draw_list, x, y, x + size, y, line_color, thickness, dash_len, gap_len, anim_offset)
    draw_dashed_line(draw_list, x + size, y, x + size, y + size, line_color, thickness, dash_len, gap_len, anim_offset)
    draw_dashed_line(draw_list, x + size, y + size, x, y + size, line_color, thickness, dash_len, gap_len, anim_offset)
    draw_dashed_line(draw_list, x, y + size, x, y, line_color, thickness, dash_len, gap_len, anim_offset)
end

return searchhighlight
