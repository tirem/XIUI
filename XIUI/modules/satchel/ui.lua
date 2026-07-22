local imgui = require('imgui')
local bor = bit.bor
local TextureManager = require('libs.texturemanager')
local components = require('config.components')
local searchlogic = require('modules.satchel.searchlogic')
local containerlogic = require('modules.satchel.containerlogic')
local satchelcolors = require('modules.satchel.colors')
local satchelfonts = require('modules.satchel.satchelfontcore')

local DISPLAY_SLOTS = containerlogic.DISPLAY_SLOTS

local ui = {}

local COLOR_SELECTED = { 0.957, 0.855, 0.592, 0.25 }
local COLOR_HOVER = { 0.137, 0.125, 0.106, 1.0 }
local COLOR_IDLE = { 0.098, 0.090, 0.075, 1.0 }
local COLOR_TEXT = { 0.878, 0.855, 0.812, 1.0 }
local TAB_GOLD = components.TAB_STYLE.gold
local TAB_ACTIVE = components.TAB_STYLE.bgLighter

local function get_invalid_tab_accent_color()
    local invalid = satchelcolors.get_drag_drop_invalid_highlight_hover()
    return {
        math.min(1.0, invalid[1] * 1.2),
        math.min(1.0, invalid[2] * 1.2),
        math.min(1.0, invalid[3] * 1.2),
        1.0,
    }
end
local COLOR_SLOT_BG = { 0.098, 0.090, 0.075, 1.0 }
local COLOR_SLOT_LOCKED_BG = { 0.055, 0.050, 0.045, 1.0 }
local DIM_SEARCH = 0.3
local DIM_SEARCH_MATCH_INNER = 0.7
local SEARCH_MATCH_INNER_DIM_PX = 2
local COLOR_QTY = { 0.99, 0.95, 0.75, 1.0 }
local COLOR_MISSING_ICON = { 0.9, 0.82, 0.50, 1.0 }
local COLOR_EMPTY_TEXT = { 0.75, 0.75, 0.75, 1.0 }
local COLOR_USED_TEXT = { 0.78, 0.78, 0.78, 1.0 }
local COLOR_GIL_TEXT = { 0.98, 0.88, 0.48, 1.0 }
local COLOR_FULL = { 0.92, 0.24, 0.20, 1.0 }
local COLOR_DISABLED_TEXT = { 0.42, 0.42, 0.42, 1.0 }
local COLOR_DISABLED_BUTTON = { 0.07, 0.07, 0.07, 0.85 }

local MIN_GRID_DIM = 5
local SLOT_CHILD_FLAGS = bor(ImGuiWindowFlags_NoScrollbar or 0, ImGuiWindowFlags_NoScrollWithMouse or 0)

function ui.get_min_grid_dim()
    return MIN_GRID_DIM
end
ui.NO_SCROLL_CHILD_FLAGS = SLOT_CHILD_FLAGS
local DRAG_HOVER_FLAGS = bor(
    ImGuiHoveredFlags_AllowWhenBlockedByActiveItem or 0,
    ImGuiHoveredFlags_AllowWhenOverlapped or 0
)
local DRAG_START_THRESHOLD = 4
local MOUSE_LEFT = 0
local MOUSE_RIGHT = 1

local pending_drag = nil
local block_window_move = false

function ui.should_block_satchel_window_move(scope)
    if block_window_move == true then
        return true
    end
    if pending_drag and scope and pending_drag.scope == scope then
        return true
    end
    if pending_drag and not scope then
        return true
    end
    return false
end

local begin_child_signature = 0
local function begin_child_compat(id, size, border, flags)
    if begin_child_signature == 1 then
        return imgui.BeginChild(id, size, border, flags)
    elseif begin_child_signature == 2 then
        return imgui.BeginChild(id, size, flags)
    elseif begin_child_signature == 3 then
        return imgui.BeginChild(id, size)
    end

    local ok, began = pcall(imgui.BeginChild, id, size, border, flags)
    if ok then
        begin_child_signature = 1
        return began
    end

    ok, began = pcall(imgui.BeginChild, id, size, flags)
    if ok then
        begin_child_signature = 2
        return began
    end

    ok, began = pcall(imgui.BeginChild, id, size)
    if ok then
        begin_child_signature = 3
        return began
    end

    return false
end

function ui.begin_child(id, size, border, flags)
    return begin_child_compat(id, size, border, flags)
end

function ui.end_child()
    imgui.EndChild()
end

function ui.get_tab_button_width(scale)
    return ui.scaled(118, scale or ui.get_global_scale())
end

function ui.tab_sidebar_needs_scrollbar(tab_count, height, scale)
    scale = scale or ui.get_global_scale()
    tab_count = tonumber(tab_count) or 0
    height = tonumber(height) or 0
    if tab_count <= 0 or height <= 0 then
        return false
    end

    local tab_height = ui.scaled(32, scale)
    local item_spacing = ui.scaled(6, scale)
    local content_h = (tab_count * tab_height) + (math.max(0, tab_count - 1) * item_spacing)
    return content_h > height
end

function ui.get_tab_sidebar_width(scale, needs_scrollbar)
    scale = scale or ui.get_global_scale()
    -- Button width + side padding; add a tight scrollbar gutter when tabs overflow.
    local width = ui.get_tab_button_width(scale) + ui.scaled(14, scale)
    if needs_scrollbar then
        width = width + ui.scaled(8, scale)
    end
    return width
end

function ui.render_drag_ghost(drag, tex_ptr, slot_size, scale)
    if not drag or drag.active ~= true then
        return
    end

    local draw_list = imgui.GetForegroundDrawList()
    if not draw_list then
        return
    end

    scale = scale or ui.get_global_scale()
    slot_size = slot_size or ui.scaled(40, scale)
    local mouse_x, mouse_y = imgui.GetMousePos()
    if type(mouse_x) ~= 'number' or type(mouse_y) ~= 'number' then
        return
    end

    local half = slot_size * 0.5
    local x1 = mouse_x - half
    local y1 = mouse_y - half
    local x2 = mouse_x + half
    local y2 = mouse_y + half

    draw_list:AddRectFilled({ x1, y1 }, { x2, y2 }, imgui.GetColorU32(COLOR_SLOT_BG), 0)
    local border_color = drag.source_border_color or { 0.72, 0.60, 0.35, 0.95 }
    draw_list:AddRect({ x1, y1 }, { x2, y2 }, imgui.GetColorU32(border_color), 0, 0, 2)

    if drag.source_icon and tex_ptr then
        local ptr = tex_ptr(drag.source_icon)
        if ptr then
            local padding = math.max(2, math.floor(slot_size * 0.08))
            draw_list:AddImage(
                ptr,
                { x1 + padding, y1 + padding },
                { x2 - padding, y2 - padding },
                { 0, 0 },
                { 1, 1 },
                imgui.GetColorU32({ 1.0, 1.0, 1.0, 0.92 })
            )
        end
    end
end

function ui.get_global_scale()
    return (gConfig and tonumber(gConfig.globalScale)) or 1.0
end

function ui.scaled(value, scale)
    return (tonumber(value) or 0) * (scale or ui.get_global_scale())
end

local function get_content_avail_width()
    local avail = imgui.GetContentRegionAvail()
    if type(avail) == 'table' then
        return tonumber(avail[1] or avail.x) or 0
    end
    if type(avail) == 'number' then
        return avail
    end
    return 0
end

local function get_content_avail_height()
    local avail = imgui.GetContentRegionAvail()
    if type(avail) == 'table' then
        return tonumber(avail[2] or avail.y) or 0
    end
    local h = select(2, imgui.GetContentRegionAvail())
    if type(h) == 'number' then
        return h
    end

    local win_h = imgui.GetWindowHeight()
    local cursor_y = imgui.GetCursorPosY()
    if type(win_h) == 'number' and type(cursor_y) == 'number' then
        return math.max(0, win_h - cursor_y - ui.scaled(10, ui.get_global_scale()))
    end
    return 0
end

local function get_full_content_width()
    local avail_w = get_content_avail_width()
    local cursor_x = imgui.GetCursorPosX()
    if type(cursor_x) == 'number' then
        return avail_w + cursor_x
    end
    return avail_w
end

local function center_cursor_for_width(width)
    imgui.SetCursorPosX(math.max(0, (get_full_content_width() - width) * 0.5))
end

local function measure_footer_button_height(scale)
    scale = scale or ui.get_global_scale()
    ui.push_tab_button_style()
    local frame_h = imgui.GetFrameHeight()
    ui.pop_tab_button_style()
    frame_h = (type(frame_h) == 'number' and frame_h > 0) and frame_h or ui.scaled(22, scale)
    local style = imgui.GetStyle()
    local border = (tonumber(style and style.FrameBorderSize) or 0) * 2
    return frame_h + border
end

local function begin_footer_row(scale)
    scale = scale or ui.get_global_scale()
    local row_h = ui.get_footer_row_height(scale)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 })
    ui.begin_child('##satchel_footer_row', { 0, row_h }, false, ui.NO_SCROLL_CHILD_FLAGS)

    local line_h = imgui.GetTextLineHeight()
    line_h = (type(line_h) == 'number' and line_h > 0) and line_h or ui.scaled(14, scale)
    local btn_h = measure_footer_button_height(scale)
    local margin = 2
    local button_y = math.max(0, row_h - btn_h - margin)
    local text_y = math.max(0, (row_h - line_h) * 0.5)

    return {
        text_y = text_y,
        button_y = button_y,
        button_h = btn_h,
        line_h = line_h,
    }
end

local function end_footer_row()
    ui.end_child()
    imgui.PopStyleVar()
end

local function set_footer_line_cursor(x, y)
    if type(x) == 'number' and type(y) == 'number' then
        imgui.SetCursorPos({ x, y })
    end
end

local function footer_sidebar_left_x(sidebar_width, gap)
    local left_x = imgui.GetCursorPosX()
    if sidebar_width > 0 then
        return left_x + sidebar_width + gap
    end
    return left_x
end

local function footer_centered_block_left_x(block_width)
    if not block_width or block_width <= 0 then
        return imgui.GetCursorPosX()
    end
    return math.max(0, (get_full_content_width() - block_width) * 0.5)
end

local function footer_align_right_in_block(left_x, block_width, right_width)
    if block_width and block_width > 0 then
        return left_x + block_width - right_width
    end
    return math.max(0, get_full_content_width() - right_width)
end

local function blend_slot_background(base_bg, highlight_color, strength)
    strength = strength or ((highlight_color[4] or 0.25) * 0.45)
    return {
        (base_bg[1] * (1.0 - strength)) + (highlight_color[1] * strength),
        (base_bg[2] * (1.0 - strength)) + (highlight_color[2] * strength),
        (base_bg[3] * (1.0 - strength)) + (highlight_color[3] * strength),
        base_bg[4] or 1.0,
    }
end

local function darken_drag_tint(color, factor)
    factor = factor or 0.9
    return {
        color[1] * factor,
        color[2] * factor,
        color[3] * factor,
        math.max(color[4] or 0.25, 0.45),
    }
end

local DRAG_SLOT_BG_BLEND = 0.0
local DRAG_SLOT_BG_BLEND_HOVER = 0.42

local function apply_drag_slot_colors(slot_bg, can_accept, hovered)
    if can_accept then
        local base_border = satchelcolors.get_drag_drop_highlight()
        local hover_border = satchelcolors.get_drag_drop_highlight_hover()
        local tint = darken_drag_tint(base_border)
        if hovered then
            return blend_slot_background(slot_bg, tint, DRAG_SLOT_BG_BLEND_HOVER), hover_border
        end
        return blend_slot_background(slot_bg, tint, DRAG_SLOT_BG_BLEND), base_border
    end

    local base_border = satchelcolors.get_drag_drop_invalid_highlight()
    local hover_border = satchelcolors.get_drag_drop_invalid_highlight_hover()
    local tint = darken_drag_tint(base_border)
    if hovered then
        return blend_slot_background(slot_bg, tint, DRAG_SLOT_BG_BLEND_HOVER), hover_border
    end
    return blend_slot_background(slot_bg, tint, DRAG_SLOT_BG_BLEND), base_border
end

local function dim_color(color, factor)
    factor = factor or 1.0
    return {
        color[1] * factor,
        color[2] * factor,
        color[3] * factor,
        (color[4] or 1.0) * factor,
    }
end

local function color_to_u32(color)
    if type(color) == 'number' then
        return color
    end
    return imgui.GetColorU32(color)
end

local function icon_tint_u32(alpha)
    alpha = alpha or 1
    return imgui.GetColorU32({ alpha, alpha, alpha, 1.0 })
end

local idle_grid_chrome = nil
local search_grid_chrome = nil

local function build_idle_grid_chrome()
    if idle_grid_chrome then
        return idle_grid_chrome
    end

    idle_grid_chrome = {
        slot_bg_u32 = imgui.GetColorU32(COLOR_SLOT_BG),
        locked_bg_u32 = imgui.GetColorU32(COLOR_SLOT_LOCKED_BG),
        locked_border_u32 = imgui.GetColorU32(dim_color(satchelcolors.get_locked_slot_border(), 0.5)),
        empty_border_u32 = imgui.GetColorU32(satchelcolors.get_empty_slot_border()),
        icon_full_u32 = icon_tint_u32(1.0),
        icon_locked_u32 = icon_tint_u32(0.35),
        qty_u32 = imgui.GetColorU32(COLOR_QTY),
        missing_icon_u32 = imgui.GetColorU32(COLOR_MISSING_ICON),
    }
    return idle_grid_chrome
end

local function build_search_grid_chrome()
    if search_grid_chrome then
        return search_grid_chrome
    end

    search_grid_chrome = {
        slot_bg_u32 = imgui.GetColorU32(COLOR_SLOT_BG),
        locked_bg_u32 = imgui.GetColorU32(COLOR_SLOT_LOCKED_BG),
        locked_border_u32 = imgui.GetColorU32(dim_color(satchelcolors.get_locked_slot_border(), 0.5)),
        empty_border_u32 = imgui.GetColorU32(satchelcolors.get_empty_slot_border()),
        icon_full_u32 = icon_tint_u32(1.0),
        icon_locked_u32 = icon_tint_u32(0.35),
        qty_u32 = imgui.GetColorU32(COLOR_QTY),
        missing_icon_u32 = imgui.GetColorU32(COLOR_MISSING_ICON),
        search_dim_slot_bg_u32 = imgui.GetColorU32(dim_color(COLOR_SLOT_BG, DIM_SEARCH)),
        search_dim_locked_bg_u32 = imgui.GetColorU32(dim_color(COLOR_SLOT_LOCKED_BG, DIM_SEARCH)),
        search_dim_border_u32 = imgui.GetColorU32(dim_color(satchelcolors.get_empty_slot_border(), DIM_SEARCH)),
        search_dim_locked_border_u32 = imgui.GetColorU32(
            dim_color(dim_color(satchelcolors.get_locked_slot_border(), 0.5), DIM_SEARCH)
        ),
        icon_search_dim_u32 = icon_tint_u32(DIM_SEARCH),
        icon_locked_search_dim_u32 = icon_tint_u32(0.35 * DIM_SEARCH),
        qty_search_dim_u32 = imgui.GetColorU32(dim_color(COLOR_QTY, DIM_SEARCH)),
        missing_icon_search_dim_u32 = imgui.GetColorU32(dim_color(COLOR_MISSING_ICON, DIM_SEARCH)),
        search_match_border_u32 = searchlogic.get_match_border_color_u32(1.0),
        search_match_inner_dim_u32 = searchlogic.get_match_inner_dim_u32(DIM_SEARCH_MATCH_INNER),
    }
    return search_grid_chrome
end

local function attach_grid_chrome(ctx)
    ctx.chrome = ctx.search_active and build_search_grid_chrome() or build_idle_grid_chrome()
end

local function get_text_width(text, fallback)
    local width = imgui.CalcTextSize(text)
    if type(width) == 'number' then
        return width
    end
    return fallback or 0
end

function ui.push_tab_button_style()
    imgui.PushStyleColor(ImGuiCol_Button, COLOR_IDLE)
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_HOVER)
    imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR_SELECTED)
    imgui.PushStyleColor(ImGuiCol_Text, COLOR_TEXT)
end

function ui.pop_tab_button_style()
    imgui.PopStyleColor(4)
end

function ui.push_config_window_style()
    components.PushWindowStyle()
    -- Let the main window background show through grid/tab/footer child regions.
    imgui.PushStyleColor(ImGuiCol_ChildBg, { 0, 0, 0, 0 })
    local s = components.TAB_STYLE
    imgui.PushStyleColor(ImGuiCol_ScrollbarBg, s.bgMedium)
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrab, s.bgLight)
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabHovered, s.bgLighter)
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabActive, s.gold)
    imgui.PushStyleVar(ImGuiStyleVar_ScrollbarRounding, 4.0)
    imgui.PushStyleVar(ImGuiStyleVar_GrabRounding, 4.0)
end

function ui.pop_config_window_style()
    imgui.PopStyleVar(2)
    imgui.PopStyleColor(4)
    imgui.PopStyleColor(1)
    components.PopWindowStyle()
end

function ui.get_title_bar_height(scale)
    return ui.scaled(28, scale or ui.get_global_scale())
end

function ui.set_window_size(width, height)
    imgui.SetNextWindowSize({ width, height }, ImGuiCond_Always)
end

function ui.has_pending_drag()
    return pending_drag ~= nil
end

function ui.clear_pending_drag(scope)
    if scope == nil or (pending_drag and pending_drag.scope == scope) then
        pending_drag = nil
    end
end

local function draw_outlined_text(draw_list, x, y, text, color, outline_px)
    if not draw_list or not text or text == '' then
        return
    end

    outline_px = outline_px or 1
    local outline = imgui.GetColorU32({ 0.0, 0.0, 0.0, 1.0 })
    local fill = color_to_u32(color or COLOR_QTY)

    for _, offset in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
        draw_list:AddText(
            { x + (offset[1] * outline_px), y + (offset[2] * outline_px) },
            outline,
            text
        )
    end
    draw_list:AddText({ x, y }, fill, text)
end

local function get_layout_columns(settings)
    return math.max(MIN_GRID_DIM, tonumber(settings.columns) or 10)
end

local function get_configured_rows(settings)
    return math.max(MIN_GRID_DIM, tonumber(settings.rows) or 8)
end

local function get_layout_rows(settings)
    return get_configured_rows(settings)
end

local function compute_row_grid_height(rows, slot_size, cell_gap)
    rows = math.max(1, tonumber(rows) or 1)
    return (rows * slot_size) + ((rows - 1) * cell_gap)
end

local function filter_display_slots(slots)
    local filtered = {}
    for _, slot in ipairs(slots or {}) do
        if slot.id and slot.id > 0 then
            filtered[#filtered + 1] = slot
        end
    end
    return filtered
end

local function get_slots_for_grid(slots, settings)
    if settings.hide_empty_slots ~= true then
        return slots or {}
    end
    return filter_display_slots(slots)
end

local function measure_toolbar_button_width(label)
    local display_label = label
    if type(label) == 'string' then
        display_label = label:match('^(.-)##') or label
    end

    ui.push_tab_button_style()
    local text_w = get_text_width(display_label, 0)
    local style = imgui.GetStyle()
    local fp = style and style.FramePadding or nil
    local pad_x = 8
    if type(fp) == 'table' then
        pad_x = (tonumber(fp[1]) or tonumber(fp.x) or 4) * 2
    elseif type(fp) == 'number' then
        pad_x = fp * 2
    end
    local border = (tonumber(style and style.FrameBorderSize) or 0) * 2
    ui.pop_tab_button_style()

    return text_w + pad_x + border
end

local function measure_toolbar_button_group(buttons, gap)
    if #buttons == 0 then
        return 0, {}
    end

    local widths = {}
    for _, button in ipairs(buttons) do
        widths[#widths + 1] = measure_toolbar_button_width(button.label)
    end

    local total = 0
    for index, width in ipairs(widths) do
        if index > 1 then
            total = total + gap
        end
        total = total + width
    end

    return total, widths
end

local function render_toolbar_buttons_right_aligned(buttons, widths, right_x, gap, line_y, highlight_ids, search_active, is_dragging)
    local clicks = {}
    if #buttons == 0 then
        return clicks
    end

    local draw_list = imgui.GetWindowDrawList()
    imgui.SetCursorPosY(line_y)
    local x = right_x
    for index = #buttons, 1, -1 do
        local button = buttons[index]
        local width = widths[index] or 0
        x = x - width
        imgui.SetCursorPos({ x, line_y })
        -- Only buttons present in highlight_ids participate (e.g. Storage Slips).
        local participates = highlight_ids and highlight_ids[button.id] ~= nil
        local is_match = participates and highlight_ids[button.id] == true
        -- Dim from highlight_ids alone so chrome (e.g. slips) can use a different
        -- query than the toolbar search field state.
        local dim_button = participates and not is_match and not is_dragging
        local btn_size = (width > 0) and { width, 0 } or nil
        local clicked
        if button.enabled == false then
            clicked = ui.render_toolbar_button(button.label, false, btn_size)
        elseif dim_button then
            local dim_btn = dim_color(COLOR_IDLE, DIM_SEARCH)
            local dim_text = dim_color(COLOR_TEXT, DIM_SEARCH)
            ui.push_tab_button_style()
            imgui.PushStyleColor(ImGuiCol_Button, dim_btn)
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, dim_btn)
            imgui.PushStyleColor(ImGuiCol_ButtonActive, dim_btn)
            imgui.PushStyleColor(ImGuiCol_Text, dim_text)
            if btn_size then
                clicked = imgui.Button(button.label, btn_size)
            else
                clicked = imgui.Button(button.label)
            end
            imgui.PopStyleColor(4)
            ui.pop_tab_button_style()
        else
            clicked = ui.render_toolbar_button(button.label, true, btn_size)
        end
        if clicked then
            clicks[button.id] = true
        end
        if is_match and draw_list then
            local min_x, min_y = imgui.GetItemRectMin()
            local max_x, max_y = imgui.GetItemRectMax()
            if type(min_x) == 'number' and type(max_x) == 'number' then
                searchlogic.draw_match_border_rect(
                    draw_list,
                    min_x,
                    min_y,
                    max_x - min_x,
                    max_y - min_y,
                    1.0
                )
            end
        end
        if index > 1 then
            x = x - gap
        end
    end

    return clicks
end

local function estimate_button_width(label, scale)
    local text_w = get_text_width(label, ui.scaled(80, scale))
    return text_w + ui.scaled(32, scale)
end

function ui.get_toolbar_grid_align_width(metrics, scale, tab_count, grid_height)
    scale = scale or ui.get_global_scale()
    local needs_sb = ui.tab_sidebar_needs_scrollbar(tab_count, grid_height, scale)
    local tab_width = ui.get_tab_sidebar_width(scale, needs_sb)
    local sidebar_gap = ui.scaled(8, scale)
    return tab_width + sidebar_gap + metrics.grid_width + metrics.scrollbar_w
end

function ui.render_toolbar_with_search(search_buffer, scale, id_suffix, buttons, opts)
    scale = scale or ui.get_global_scale()
    buttons = buttons or {}
    opts = opts or {}
    id_suffix = tostring(id_suffix or 'main')

    local gap = ui.scaled(8, scale)
    local visible_buttons = {}
    for _, button in ipairs(buttons) do
        if button.visible ~= false then
            visible_buttons[#visible_buttons + 1] = button
        end
    end

    local align_width = tonumber(opts.align_width) or get_full_content_width()
    if opts.centered and align_width > 0 then
        center_cursor_for_width(align_width)
    end

    local line_start_x = imgui.GetCursorPosX()
    local line_y = imgui.GetCursorPosY()
    local buttons_w, button_widths = measure_toolbar_button_group(visible_buttons, gap)
    local button_gap = (#visible_buttons > 0) and gap or 0
    local search_w = math.max(ui.scaled(80, scale), align_width - buttons_w - button_gap)
    local input_focused = ui.render_search_bar(
        search_buffer,
        search_w,
        scale,
        id_suffix
    )

    local clicks = render_toolbar_buttons_right_aligned(
        visible_buttons,
        button_widths,
        line_start_x + align_width,
        gap,
        line_y,
        opts.highlight_button_ids,
        opts.search_active == true,
        opts.is_dragging == true
    )

    return clicks, input_focused == true
end

function ui.render_search_bar(buffer, width, scale, id_suffix)
    scale = scale or ui.get_global_scale()
    if type(buffer) ~= 'table' then
        return false
    end

    local widget_id = ('##satchel_search_%s'):format(tostring(id_suffix or 'main'))
    imgui.PushStyleColor(ImGuiCol_FrameBg, { 0.067, 0.063, 0.055, 0.95 })
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, COLOR_HOVER)
    imgui.PushStyleColor(ImGuiCol_FrameBgActive, COLOR_IDLE)
    imgui.PushItemWidth(width or ui.scaled(180, scale))
    local ok, _ = pcall(imgui.InputTextWithHint, widget_id, 'Search items...', buffer, 64, 0)
    if not ok then
        local fallback_id = ('Search%s'):format(widget_id)
        local ok_fallback = pcall(imgui.InputText, fallback_id, buffer, 64, 0)
        if not ok_fallback then
            imgui.InputText(fallback_id, buffer, 64)
        end
    end
    imgui.PopItemWidth()
    imgui.PopStyleColor(3)

    local active_ok, is_active = pcall(function()
        return imgui.IsItemActive()
    end)
    local focused_ok, is_focused = pcall(function()
        return imgui.IsItemFocused()
    end)
    local field_active = (active_ok and is_active == true) or (focused_ok and is_focused == true)

    return field_active
end

local function draw_full_badge(max_x, min_y, max_y)
    local draw_list = imgui.GetWindowDrawList()
    if not draw_list then return end

    local color = imgui.GetColorU32(COLOR_FULL)
    local width = 3
    local inset = 3
    local v_pad = 4
    local x2 = max_x - inset
    local x1 = x2 - width

    draw_list:AddRectFilled({ x1, min_y + v_pad }, { x2, max_y - v_pad }, color, 1.5)
end

function ui.render_left_tab_column(available_tabs, current_tab, format_tab_label, drag_ctx, scale, tab_width)
    scale = scale or ui.get_global_scale()
    tab_width = tab_width or ui.get_tab_button_width(scale)
    local tab_height = ui.scaled(32, scale)

    local has_current = false
    for _, container_id in ipairs(available_tabs) do
        if container_id == current_tab then
            has_current = true
            break
        end
    end

    if not has_current then
        current_tab = nil
    end

    if current_tab == nil and #available_tabs > 0 then
        current_tab = available_tabs[1]
    end

    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 10, 8 })
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 8, 6 })
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 4.0)

    local is_dragging = drag_ctx and drag_ctx.is_dragging == true
    local draw_list = imgui.GetWindowDrawList()
    local source_container = drag_ctx and drag_ctx.get_source_container and drag_ctx.get_source_container() or nil
    local clicked_tab = nil

    for _, container_id in ipairs(available_tabs) do
        local selected_tab = current_tab
        if is_dragging and drag_ctx and drag_ctx.get_selected_tab then
            selected_tab = drag_ctx.get_selected_tab()
        end

        local is_selected = (container_id == selected_tab)
        local label = format_tab_label(container_id)
        local can_drop_here = false
        local match_containers = drag_ctx and drag_ctx.search_match_containers
        local search_active = drag_ctx and drag_ctx.search_active == true
        local tab_search_dim = search_active
            and not is_dragging
            and not (match_containers and match_containers[container_id])

        if is_dragging and drag_ctx.can_drop_to_container then
            can_drop_here = drag_ctx.can_drop_to_container(container_id) == true
        end

        local btn_pos_x, btn_pos_y = imgui.GetCursorScreenPos()
        local will_hover = is_dragging and imgui.IsMouseHoveringRect(
            { btn_pos_x, btn_pos_y },
            { btn_pos_x + tab_width, btn_pos_y + tab_height },
            true
        )

        local is_origin_tab = is_dragging
            and source_container ~= nil
            and tonumber(container_id) == tonumber(source_container)

        local tab_drop_valid = can_drop_here or is_origin_tab

        if is_dragging and will_hover then
            if tab_drop_valid then
                imgui.PushStyleColor(ImGuiCol_Button, satchelcolors.get_drag_drop_highlight_hover())
                imgui.PushStyleColor(ImGuiCol_ButtonHovered, satchelcolors.get_drag_drop_highlight_hover())
                imgui.PushStyleColor(ImGuiCol_ButtonActive, satchelcolors.get_drag_drop_highlight_hover())
            else
                imgui.PushStyleColor(ImGuiCol_Button, satchelcolors.get_drag_drop_invalid_highlight_hover())
                imgui.PushStyleColor(ImGuiCol_ButtonHovered, satchelcolors.get_drag_drop_invalid_highlight_hover())
                imgui.PushStyleColor(ImGuiCol_ButtonActive, satchelcolors.get_drag_drop_invalid_highlight_hover())
            end
            imgui.PushStyleColor(ImGuiCol_Text, COLOR_TEXT)
        elseif is_dragging and tab_drop_valid then
            imgui.PushStyleColor(ImGuiCol_Button, satchelcolors.get_drag_drop_highlight())
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, satchelcolors.get_drag_drop_highlight())
            imgui.PushStyleColor(ImGuiCol_ButtonActive, satchelcolors.get_drag_drop_highlight())
            imgui.PushStyleColor(ImGuiCol_Text, COLOR_TEXT)
        elseif is_dragging then
            imgui.PushStyleColor(ImGuiCol_Button, satchelcolors.get_drag_drop_invalid_highlight())
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, satchelcolors.get_drag_drop_invalid_highlight())
            imgui.PushStyleColor(ImGuiCol_ButtonActive, satchelcolors.get_drag_drop_invalid_highlight())
            imgui.PushStyleColor(ImGuiCol_Text, COLOR_TEXT)
        elseif tab_search_dim then
            local dim_btn = dim_color(is_selected and COLOR_SELECTED or COLOR_IDLE, DIM_SEARCH)
            local dim_text = dim_color(COLOR_TEXT, DIM_SEARCH)
            imgui.PushStyleColor(ImGuiCol_Button, dim_btn)
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, dim_btn)
            imgui.PushStyleColor(ImGuiCol_ButtonActive, dim_btn)
            imgui.PushStyleColor(ImGuiCol_Text, dim_text)
        elseif is_selected then
            imgui.PushStyleColor(ImGuiCol_Button, COLOR_SELECTED)
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_SELECTED)
            imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR_SELECTED)
            imgui.PushStyleColor(ImGuiCol_Text, COLOR_TEXT)
        else
            imgui.PushStyleColor(ImGuiCol_Button, { 0, 0, 0, 0 })
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_HOVER)
            imgui.PushStyleColor(ImGuiCol_ButtonActive, TAB_ACTIVE)
            imgui.PushStyleColor(ImGuiCol_Text, COLOR_TEXT)
        end

        local clicked = imgui.Button(label .. ('##satchel_tab_%d'):format(container_id), { tab_width, tab_height })
        if clicked and not is_dragging then
            clicked_tab = container_id
        end

        local _, btn_min_y = imgui.GetItemRectMin()
        local btn_max_x, btn_max_y = imgui.GetItemRectMax()
        local is_full = drag_ctx and drag_ctx.is_container_full and drag_ctx.is_container_full(container_id)

        if draw_list and is_dragging and is_selected and not tab_drop_valid then
            draw_list:AddRectFilled(
                { btn_pos_x, btn_pos_y + 4 },
                { btn_pos_x + 3, btn_pos_y + tab_height - 4 },
                imgui.GetColorU32(get_invalid_tab_accent_color()),
                1.5
            )
        elseif is_selected and draw_list then
            draw_list:AddRectFilled(
                { btn_pos_x, btn_pos_y + 4 },
                { btn_pos_x + 3, btn_pos_y + tab_height - 4 },
                imgui.GetColorU32(TAB_GOLD),
                1.5
            )
        end

        local hovered_for_drop = imgui.IsItemHovered(DRAG_HOVER_FLAGS)
        if is_dragging and hovered_for_drop and drag_ctx.on_tab_hover then
            drag_ctx.on_tab_hover(container_id)
        end
        if is_dragging and drag_ctx.on_drop_to_container and hovered_for_drop and imgui.IsMouseReleased(MOUSE_LEFT) then
            drag_ctx.on_drop_to_container(container_id)
        end

        imgui.PopStyleColor(4)

        if is_full and not is_dragging then
            draw_full_badge(btn_max_x, btn_min_y, btn_max_y)
        end

        if match_containers and match_containers[container_id] and draw_list then
            local min_x, min_y = imgui.GetItemRectMin()
            local max_x, max_y = imgui.GetItemRectMax()
            if type(min_x) == 'number' and type(max_x) == 'number' then
                searchlogic.draw_match_border_rect(
                    draw_list,
                    min_x,
                    min_y,
                    max_x - min_x,
                    max_y - min_y,
                    1.0
                )
            end
        end
    end

    imgui.PopStyleVar(3)

    return clicked_tab, tab_width
end

function ui.render_scrollable_tab_sidebar(child_id, width, height, available_tabs, current_tab, format_tab_label, drag_ctx, scale)
    scale = scale or ui.get_global_scale()
    width = width or ui.get_tab_sidebar_width(scale)
    local button_width = ui.get_tab_button_width(scale)
    begin_child_compat(child_id, { width, height }, false, 0)
    local tab, tab_width = ui.render_left_tab_column(
        available_tabs,
        current_tab,
        format_tab_label,
        drag_ctx,
        scale,
        button_width
    )
    imgui.EndChild()
    return tab, tab_width
end

function ui.get_footer_row_height(scale)
    scale = scale or ui.get_global_scale()
    local text_h = imgui.GetTextLineHeight()
    text_h = type(text_h) == 'number' and text_h or ui.scaled(14, scale)
    local btn_h = measure_footer_button_height(scale)
    return math.max(text_h, btn_h + 4, ui.scaled(30, scale))
end

function ui.render_inventory_footer(stat, ctx, opts)
    opts = opts or {}
    local scale = opts.scale or ui.get_global_scale()
    local sidebar_width = opts.sidebar_width or 0
    local gap = opts.gap or ui.scaled(8, scale)

    local layout = begin_footer_row(scale)

    local used = (stat and stat.used) or 0
    local total = (stat and stat.total) or 0
    local left_x = footer_sidebar_left_x(sidebar_width, gap)
    set_footer_line_cursor(left_x, layout.text_y)
    imgui.TextColored(COLOR_USED_TEXT, ('Used: %d / %d'):format(used, total))

    if not ctx or not ctx.get_gil_amount or not ctx.format_gil_text or ctx.hide_gil then
        end_footer_row()
        return
    end

    local gil_amount = ctx.get_gil_amount()
    if gil_amount == nil then
        end_footer_row()
        return
    end

    local gil_text = ctx.format_gil_text(gil_amount)
    local gil_icon = ctx.load_gil_icon and ctx.load_gil_icon() or nil
    local _, text_h = imgui.CalcTextSize(gil_text)
    text_h = type(text_h) == 'number' and text_h or ui.scaled(14, scale)
    local icon_size = math.min(ui.scaled(14, scale), text_h)
    local icon_gap = ui.scaled(4, scale)
    local text_w = get_text_width(gil_text, 0)
    local gil_ptr = nil
    if gil_icon then
        gil_ptr = ctx.get_gil_icon_ptr and ctx.get_gil_icon_ptr(gil_icon)
            or TextureManager.getTexturePtr(gil_icon)
            or (ctx.tex_ptr and ctx.tex_ptr(gil_icon) or nil)
    end
    local right_width = text_w + (gil_ptr and (icon_size + icon_gap) or 0)
    local grid_block_width = tonumber(opts.grid_block_width) or 0
    local right_x = footer_align_right_in_block(left_x, grid_block_width, right_width)
    set_footer_line_cursor(right_x, layout.text_y)

    if gil_ptr then
        imgui.Image(gil_ptr, { icon_size, icon_size })
        imgui.SameLine(0, icon_gap)
    end

    imgui.TextColored(COLOR_GIL_TEXT, gil_text)
    end_footer_row()
end

local function render_footer_pagination(page_index, page_count, on_page_change, scale, layout, opts)
    opts = opts or {}
    scale = scale or ui.get_global_scale()
    local page = tonumber(page_index) or 0
    local total_pages = math.max(1, tonumber(page_count) or 1)
    local gap = opts.gap or ui.scaled(8, scale)
    local page_text = ('Page %d / %d'):format(page + 1, total_pages)
    local grid_width = tonumber(opts.grid_width) or 0
    local left_x = footer_centered_block_left_x(grid_width)
    local right_inset = tonumber(opts.right_inset) or ui.scaled(2, scale)
    local prev_w = measure_toolbar_button_width('Prev##satchel_slip_page')
    local next_w = measure_toolbar_button_width('Next##satchel_slip_page')
    local page_w = get_text_width(page_text, 0)
    local page_text_y = layout.button_y + math.max(0, (layout.button_h - layout.line_h) * 0.5)
    local btn_size = { 0, layout.button_h }
    local grid_right = left_x + grid_width

    local x = grid_right - right_inset - next_w
    btn_size[1] = next_w
    set_footer_line_cursor(x, layout.button_y)
    if ui.render_toolbar_button('Next##satchel_slip_page', page < (total_pages - 1), btn_size) and on_page_change then
        on_page_change(page + 1)
    end

    x = x - gap - page_w
    set_footer_line_cursor(x, page_text_y)
    imgui.TextColored(COLOR_USED_TEXT, page_text)

    x = x - gap - prev_w
    btn_size[1] = prev_w
    set_footer_line_cursor(x, layout.button_y)
    if ui.render_toolbar_button('Prev##satchel_slip_page', page > 0, btn_size) and on_page_change then
        on_page_change(page - 1)
    end
end

function ui.render_slip_window_footer(stored_count, page_index, page_count, on_page_change, scale, opts)
    opts = opts or {}
    scale = scale or ui.get_global_scale()
    local stored_text = ('Stored: %d Items'):format(tonumber(stored_count) or 0)

    local layout = begin_footer_row(scale)
    local left_x = footer_centered_block_left_x(tonumber(opts.grid_width) or 0)
    set_footer_line_cursor(left_x, layout.text_y)
    imgui.TextColored(COLOR_USED_TEXT, stored_text)
    render_footer_pagination(page_index, page_count, on_page_change, scale, layout, opts)
    end_footer_row()
end

local function grid_slot_screen_bounds(grid_ox, grid_oy, index, columns, slot_size, cell_gap)
    local zero = index - 1
    local col = zero % columns
    local row = math.floor(zero / columns)
    local cell = slot_size + cell_gap
    local min_x = grid_ox + (col * cell)
    local min_y = grid_oy + (row * cell)
    return min_x, min_y, min_x + slot_size, min_y + slot_size
end

local function hit_test_grid_slot(mouse_x, mouse_y, grid_ox, grid_oy, columns, slot_size, cell_gap, slot_count)
    if type(mouse_x) ~= 'number' or type(mouse_y) ~= 'number' then
        return nil
    end

    local local_x = mouse_x - grid_ox
    local local_y = mouse_y - grid_oy
    if local_x < 0 or local_y < 0 then
        return nil
    end

    local cell = slot_size + cell_gap
    local col = math.floor(local_x / cell)
    local row = math.floor(local_y / cell)
    if col < 0 or col >= columns then
        return nil
    end

    local in_cell_x = local_x - (col * cell)
    local in_cell_y = local_y - (row * cell)
    if in_cell_x > slot_size or in_cell_y > slot_size then
        return nil
    end

    local index = (row * columns) + col + 1
    if index < 1 or index > slot_count then
        return nil
    end
    return index
end

local function draw_slot_icon(draw_list, tex_ptr, screen_x, screen_y, icon_size, tint_u32)
    if not draw_list or not tex_ptr or tex_ptr == 0 or not tint_u32 then
        return
    end

    draw_list:AddImage(
        tex_ptr,
        { screen_x, screen_y },
        { screen_x + icon_size, screen_y + icon_size },
        { 0, 0 },
        { 1, 1 },
        tint_u32
    )
end

-- Darken only the inner band of an icon so built-in icon borders do not wash out the gold highlight.
local function draw_search_match_inner_dim(draw_list, x1, y1, x2, y2, band_px, dim_u32)
    if not draw_list or not dim_u32 or band_px <= 0 then
        return
    end

    if (x2 - x1) <= band_px or (y2 - y1) <= band_px then
        return
    end

    draw_list:AddRectFilled({ x1, y1 }, { x2, y1 + band_px }, dim_u32)
    draw_list:AddRectFilled({ x1, y2 - band_px }, { x2, y2 }, dim_u32)
    draw_list:AddRectFilled({ x1, y1 }, { x1 + band_px, y2 }, dim_u32)
    draw_list:AddRectFilled({ x2 - band_px, y1 }, { x2, y2 }, dim_u32)
end

local function draw_slot(slot, index, key_prefix, ctx, layout)
    local slot_size = ctx.slot_size or ctx.settings.slot_size
    local icon_padding = ctx.icon_padding or math.max(1, math.floor(slot_size * 0.05))
    local icon_size = ctx.icon_size or math.max(20, slot_size - (icon_padding * 2))
    local locked = slot.locked == true
    local read_only = slot.read_only == true or ctx.read_only == true
    local allow_visual_drag = ctx.visual_sort_only == true
    local allow_drag = allow_visual_drag and not locked and slot.id and slot.id > 0
    local is_dragging = ctx.grid_is_dragging == true
    local search_active = ctx.search_active == true
    local search_match = false
    if search_active and slot.id and slot.id > 0 and ctx.item_matches_search then
        search_match = ctx.item_matches_search(slot, ctx.search_query) == true
    end

    local chrome = ctx.chrome
    local border_u32
    if search_active and search_match then
        border_u32 = nil
    elseif search_active and not is_dragging then
        border_u32 = locked and chrome.search_dim_locked_border_u32 or chrome.search_dim_border_u32
    elseif locked then
        border_u32 = chrome.locked_border_u32
    elseif not slot.id or slot.id <= 0 then
        border_u32 = chrome.empty_border_u32
    elseif ctx.get_slot_border_u32 then
        border_u32 = ctx.get_slot_border_u32(slot)
    else
        border_u32 = color_to_u32(ctx.get_slot_border_color(slot))
    end

    local is_drag_source = is_dragging
        and ctx.is_drag_source
        and ctx.is_drag_source(slot) == true
    local can_accept_drop = is_dragging
        and ctx.can_drop_to_slot
        and (allow_visual_drag or not read_only)
        and not locked
        and ctx.can_drop_to_slot(slot) == true
    local is_empty_slot = not locked and (not slot.id or slot.id <= 0)

    -- Dim non-matches while searching, including empty and locked slots.
    -- Suspend dimming during an active drag so the board is fully readable.
    local search_dim = search_active and not search_match and not is_dragging
    local icon_tint
    if is_drag_source then
        icon_tint = nil
    elseif locked then
        icon_tint = search_dim and chrome.icon_locked_search_dim_u32 or chrome.icon_locked_u32
    elseif search_dim then
        icon_tint = chrome.icon_search_dim_u32
    else
        icon_tint = chrome.icon_full_u32
    end

    local tex = nil
    local min_x, min_y, max_x, max_y
    local slot_hovered = false
    layout = layout or {}

    if layout.min_x ~= nil then
        min_x = layout.min_x
        min_y = layout.min_y
        max_x = layout.max_x
        max_y = layout.max_y
        slot_hovered = layout.is_hovered == true
    else
        local slot_id = ('##satchel_slot_%s_%d'):format(tostring(key_prefix or 'all'), index)
        imgui.InvisibleButton(slot_id, { slot_size, slot_size })
        slot_hovered = is_dragging and imgui.IsItemHovered(DRAG_HOVER_FLAGS) or imgui.IsItemHovered()
        min_x, min_y = imgui.GetItemRectMin()
        max_x, max_y = imgui.GetItemRectMax()
    end

    local drag_source_hovered = is_dragging
        and is_drag_source
        and slot_hovered

    local drop_target_hovered = is_dragging
        and not is_drag_source
        and (allow_visual_drag or not read_only)
        and not locked
        and slot_hovered

    local draw_list = imgui.GetWindowDrawList()
    local slot_bg_u32 = locked and chrome.locked_bg_u32 or chrome.slot_bg_u32
    if search_dim then
        slot_bg_u32 = locked and chrome.search_dim_locked_bg_u32 or chrome.search_dim_slot_bg_u32
    end

    if is_drag_source then
        local drag_bg, drag_border = apply_drag_slot_colors(
            locked and COLOR_SLOT_LOCKED_BG or COLOR_SLOT_BG,
            false,
            false
        )
        slot_bg_u32 = color_to_u32(drag_bg)
        border_u32 = color_to_u32(drag_border)
    elseif is_dragging and (allow_visual_drag or not read_only) and not locked and is_empty_slot then
        local drag_bg, drag_border = apply_drag_slot_colors(
            locked and COLOR_SLOT_LOCKED_BG or COLOR_SLOT_BG,
            can_accept_drop,
            false
        )
        slot_bg_u32 = color_to_u32(drag_bg)
        border_u32 = color_to_u32(drag_border)
    end

    if drag_source_hovered then
        local drag_bg, drag_border = apply_drag_slot_colors(
            locked and COLOR_SLOT_LOCKED_BG or COLOR_SLOT_BG,
            false,
            true
        )
        slot_bg_u32 = color_to_u32(drag_bg)
        border_u32 = color_to_u32(drag_border)
    elseif drop_target_hovered then
        local drag_bg, drag_border = apply_drag_slot_colors(
            locked and COLOR_SLOT_LOCKED_BG or COLOR_SLOT_BG,
            can_accept_drop,
            true
        )
        slot_bg_u32 = color_to_u32(drag_bg)
        border_u32 = color_to_u32(drag_border)
    end

    if is_drag_source then
        border_u32 = color_to_u32(satchelcolors.get_drag_drop_invalid_highlight_hover())
    end

    if not layout.defer_interaction
        and (allow_drag or (not read_only and not locked)) and slot.id and slot.id > 0
        and ((layout.min_x == nil and imgui.IsItemActive()) or slot_hovered)
        and imgui.IsMouseDown(MOUSE_LEFT) then
        block_window_move = true
    end

    if draw_list and type(min_x) == 'number' and type(min_y) == 'number'
        and type(max_x) == 'number' and type(max_y) == 'number' then
        draw_list:AddRectFilled({ min_x, min_y }, { max_x, max_y }, slot_bg_u32)

        local use_match_border = search_match and not is_drag_source
        if not use_match_border and border_u32 then
            draw_list:AddRect({ min_x, min_y }, { max_x, max_y }, border_u32, 0, 0, 1.0)
        end

        if slot.id and slot.id > 0 then
            tex = ctx.load_item_icon(slot.id)
            if tex and icon_tint then
                draw_slot_icon(
                    draw_list,
                    ctx.tex_ptr(tex),
                    min_x + icon_padding,
                    min_y + icon_padding,
                    icon_size,
                    icon_tint
                )
            elseif not tex then
                draw_list:AddText(
                    { min_x + 4, min_y + 8 },
                    search_dim and chrome.missing_icon_search_dim_u32 or chrome.missing_icon_u32,
                    '?'
                )
            end

            -- Hide quantity (and its opaque outline) while this cell is the drag source.
            if not is_drag_source and slot.count and slot.count > 1 then
                local qty_text = tostring(slot.count)
                local text_w, text_h = imgui.CalcTextSize(qty_text)
                text_w = type(text_w) == 'number' and text_w or 0
                text_h = type(text_h) == 'number' and text_h or 0
                local qty_x = min_x + math.max(2, slot_size - text_w - 3)
                local qty_y = min_y + math.max(2, slot_size - text_h - 2)
                local outline_px = satchelfonts.get_outline_px(ctx.scale)
                draw_outlined_text(
                    draw_list,
                    qty_x,
                    qty_y,
                    qty_text,
                    search_dim and chrome.qty_search_dim_u32 or chrome.qty_u32,
                    outline_px
                )
            end
        end

        if use_match_border and slot.id and slot.id > 0 and chrome.search_match_inner_dim_u32 then
            local ix = min_x + icon_padding
            local iy = min_y + icon_padding
            draw_search_match_inner_dim(
                draw_list,
                ix,
                iy,
                ix + icon_size,
                iy + icon_size,
                SEARCH_MATCH_INNER_DIM_PX,
                chrome.search_match_inner_dim_u32
            )
        end

        -- Search highlight on top of icon so built-in icon borders do not obscure it.
        if use_match_border and chrome.search_match_border_u32 then
            local thickness = 2
            local inset = thickness * 0.5
            local bx, by = min_x + inset, min_y + inset
            local bw, bh = (max_x - min_x) - thickness, (max_y - min_y) - thickness
            if bw > 0 and bh > 0 then
                draw_list:AddRect(
                    { bx, by },
                    { bx + bw, by + bh },
                    chrome.search_match_border_u32,
                    0,
                    0,
                    thickness
                )
            end
        end
    end

    if drop_target_hovered and can_accept_drop then
        ctx.pending_drop_target = slot
    end

    if layout.defer_interaction then
        return
    end

    if not locked and slot_hovered and slot.id and slot.id > 0 and ctx.render_item_detail_tooltip then
        local ok, err = pcall(ctx.render_item_detail_tooltip, slot)
        if not ok and ashita and ashita.log and ashita.log.error then
            ashita.log.error(('[XIUI Satchel] tooltip error: %s'):format(tostring(err)))
        end
    end

    if (allow_visual_drag or not read_only) and not locked and slot.id and slot.id > 0 and imgui.IsItemClicked(MOUSE_RIGHT) and ctx.on_slot_right_click then
        ctx.on_slot_right_click(slot)
    end

    if allow_drag and ctx.on_slot_drag_start and imgui.IsItemClicked(MOUSE_LEFT) then
        pending_drag = { scope = ctx.drag_scope, slot = slot, item_id = slot.id }
    elseif not read_only and not locked and slot.id and slot.id > 0 and ctx.on_slot_drag_start
        and imgui.IsItemClicked(MOUSE_LEFT) then
        pending_drag = { scope = ctx.drag_scope, slot = slot, item_id = slot.id }
    end

    if not read_only and not locked and slot.id and slot.id > 0 and ctx.on_slot_double_click
        and slot_hovered and imgui.IsMouseDoubleClicked(MOUSE_LEFT) then
        ctx.on_slot_double_click(slot)
    end
end

local function handle_fast_grid_slot_interactions(slot, ctx, grid_hovered, grid_active, hovered_idx)
    if not grid_hovered or not hovered_idx or not slot then
        return
    end

    local locked = slot.locked == true
    local read_only = slot.read_only == true or ctx.read_only == true
    local allow_visual_drag = ctx.visual_sort_only == true
    local allow_drag = allow_visual_drag and not locked and slot.id and slot.id > 0

    if grid_active
        and (allow_drag or (not read_only and not locked)) and slot.id and slot.id > 0
        and imgui.IsMouseDown(MOUSE_LEFT) then
        block_window_move = true
    end

    if not locked and slot.id and slot.id > 0 and ctx.render_item_detail_tooltip and not ctx.grid_is_dragging then
        local ok, err = pcall(ctx.render_item_detail_tooltip, slot)
        if not ok and ashita and ashita.log and ashita.log.error then
            ashita.log.error(('[XIUI Satchel] tooltip error: %s'):format(tostring(err)))
        end
    end

    if (allow_visual_drag or not read_only) and not locked and slot.id and slot.id > 0
        and imgui.IsItemClicked(MOUSE_RIGHT) and ctx.on_slot_right_click then
        ctx.on_slot_right_click(slot)
    end

    if allow_drag and ctx.on_slot_drag_start and imgui.IsItemClicked(MOUSE_LEFT) then
        pending_drag = { scope = ctx.drag_scope, slot = slot, item_id = slot.id }
    elseif not read_only and not locked and slot.id and slot.id > 0 and ctx.on_slot_drag_start
        and imgui.IsItemClicked(MOUSE_LEFT) then
        pending_drag = { scope = ctx.drag_scope, slot = slot, item_id = slot.id }
    end

    if not read_only and not locked and slot.id and slot.id > 0 and ctx.on_slot_double_click
        and imgui.IsMouseDoubleClicked(MOUSE_LEFT) then
        ctx.on_slot_double_click(slot)
    end
end

function ui.compute_grid_metrics(settings, slot_count, scale, opts)
    scale = scale or ui.get_global_scale()
    opts = opts or {}
    local cell_gap = ui.scaled(2, scale)
    local slot_size = ui.scaled(settings.slot_size or 40, scale)

    if opts.layout_size then
        local columns = get_layout_columns(settings)
        local configured_rows = get_configured_rows(settings)
        local total_slots = math.max(1, tonumber(slot_count) or DISPLAY_SLOTS)
        local natural_rows = math.max(1, math.ceil(total_slots / columns))
        local needs_scroll = natural_rows > configured_rows
        local visible_rows = needs_scroll and configured_rows or natural_rows
        local grid_width = (columns * slot_size) + ((columns - 1) * cell_gap)
        local grid_height = compute_row_grid_height(visible_rows, slot_size, cell_gap)
        local content_height = compute_row_grid_height(natural_rows, slot_size, cell_gap)
        if needs_scroll then
            content_height = content_height + slot_size + cell_gap
        end

        return {
            columns = columns,
            used_columns = columns,
            total_slots = total_slots,
            visible_rows = visible_rows,
            configured_rows = configured_rows,
            natural_rows = natural_rows,
            cell_gap = cell_gap,
            slot_size = slot_size,
            grid_width = grid_width,
            grid_height = grid_height,
            content_height = content_height,
            needs_scroll = needs_scroll,
            scrollbar_w = needs_scroll and ui.scaled(16, scale) or 0,
        }
    end

    local columns = get_layout_columns(settings)
    local configured_rows = get_layout_rows(settings)
    local total_slots = math.max(1, tonumber(slot_count) or 1)
    local used_columns = math.max(1, math.min(columns, total_slots))
    local natural_rows = math.max(1, math.ceil(total_slots / used_columns))
    local visible_rows = natural_rows
    if not opts.show_all_rows then
        visible_rows = math.min(configured_rows, natural_rows)
    end
    local grid_width = (used_columns * slot_size) + ((used_columns - 1) * cell_gap)
    local grid_height = (visible_rows * slot_size) + ((visible_rows - 1) * cell_gap)
    local needs_scroll = (not opts.show_all_rows) and natural_rows > visible_rows

    return {
        columns = columns,
        used_columns = used_columns,
        total_slots = total_slots,
        visible_rows = visible_rows,
        natural_rows = natural_rows,
        cell_gap = cell_gap,
        slot_size = slot_size,
        grid_width = grid_width,
        grid_height = grid_height,
        needs_scroll = needs_scroll,
        scrollbar_w = needs_scroll and ui.scaled(16, scale) or 0,
    }
end

function ui.render_slot_grid(slots, key_prefix, stat, ctx)
    local scale = ctx.scale or ui.get_global_scale()
    ctx.scale = scale
    ctx.slot_size = ui.scaled(ctx.settings.slot_size or ctx.default_slot_size or 40, scale)
    ctx.icon_padding = math.max(1, math.floor(ctx.slot_size * 0.05))
    ctx.icon_size = math.max(20, ctx.slot_size - (ctx.icon_padding * 2))
    ctx.grid_is_dragging = ctx.is_dragging and ctx.is_dragging() == true
    block_window_move = false

    ctx.search_active = ctx.search_active == true
    attach_grid_chrome(ctx)
    if ctx.prepare_slot_render then
        ctx.prepare_slot_render()
    end

    local packed = get_slots_for_grid(slots, ctx.settings)
    local packed_count = #packed
    local slot_count_for_metrics = tonumber(ctx.grid_slot_count) or DISPLAY_SLOTS
    local metrics = ui.compute_grid_metrics(ctx.settings, slot_count_for_metrics, scale, { layout_size = true })
    ctx.pending_drop_target = nil

    if ctx.centered then
        center_cursor_for_width(metrics.grid_width + metrics.scrollbar_w)
    end

    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { metrics.cell_gap, metrics.cell_gap })
    begin_child_compat(
        ('##satchel_grid_%s'):format(tostring(key_prefix)),
        { metrics.grid_width + metrics.scrollbar_w, metrics.grid_height },
        false,
        metrics.needs_scroll and 0 or SLOT_CHILD_FLAGS
    )

    local key = tostring(key_prefix)
    local use_fast_grid = not metrics.needs_scroll and packed_count > 0
    local grid_ox, grid_oy
    local hovered_idx = nil

    if use_fast_grid then
        grid_ox, grid_oy = imgui.GetCursorScreenPos()
        imgui.InvisibleButton(
            ('##satchel_grid_hit_%s'):format(key),
            { metrics.grid_width, metrics.grid_height }
        )
        local grid_hovered = imgui.IsItemHovered()
        local grid_active = imgui.IsItemActive()

        if grid_hovered then
            local mouse_x, mouse_y = imgui.GetMousePos()
            hovered_idx = hit_test_grid_slot(
                mouse_x,
                mouse_y,
                grid_ox,
                grid_oy,
                metrics.columns,
                metrics.slot_size,
                metrics.cell_gap,
                packed_count
            )
        end

        for i = 1, packed_count do
            local min_x, min_y, max_x, max_y = grid_slot_screen_bounds(
                grid_ox,
                grid_oy,
                i,
                metrics.columns,
                metrics.slot_size,
                metrics.cell_gap
            )
            draw_slot(packed[i], i, key, ctx, {
                min_x = min_x,
                min_y = min_y,
                max_x = max_x,
                max_y = max_y,
                is_hovered = grid_hovered and hovered_idx == i,
                defer_interaction = true,
            })
        end

        if hovered_idx then
            handle_fast_grid_slot_interactions(
                packed[hovered_idx],
                ctx,
                grid_hovered,
                grid_active,
                hovered_idx
            )
        elseif grid_active and imgui.IsMouseDown(MOUSE_LEFT) then
            block_window_move = true
        end
    else
        for i = 1, packed_count do
            draw_slot(packed[i], i, key, ctx)
            if i % metrics.columns ~= 0 then
                imgui.SameLine(0, metrics.cell_gap)
            end
        end
    end

    if packed_count == 0 then
        imgui.TextColored(COLOR_EMPTY_TEXT, 'No slots to display.')
    elseif metrics.needs_scroll then
        local used_h = imgui.GetCursorPosY()
        local target_h = metrics.content_height or used_h
        if used_h < target_h then
            imgui.Dummy({ metrics.grid_width, target_h - used_h })
        end
    end

    if ctx.pending_drop_target
        and ctx.on_drop_to_slot
        and ctx.grid_is_dragging
        and ctx.can_drop_to_slot
        and ctx.can_drop_to_slot(ctx.pending_drop_target) == true
        and imgui.IsMouseReleased(MOUSE_LEFT) then
        ctx.on_drop_to_slot(ctx.pending_drop_target)
    end

    imgui.EndChild()
    imgui.PopStyleVar(1)

    local pending_matches = pending_drag
        and ctx.drag_scope
        and pending_drag.scope == ctx.drag_scope

    if not ctx.read_only and pending_matches and ctx.on_slot_drag_start then
        if imgui.IsMouseDragging(MOUSE_LEFT, DRAG_START_THRESHOLD) then
            local drag_tex = nil
            if pending_drag.item_id and ctx.load_item_icon then
                drag_tex = ctx.load_item_icon(pending_drag.item_id)
            end
            ctx.on_slot_drag_start(pending_drag.slot, drag_tex)
            pending_drag = nil
        elseif not imgui.IsMouseDown(MOUSE_LEFT) then
            pending_drag = nil
        end
    elseif ctx.visual_sort_only and pending_matches and ctx.on_slot_drag_start then
        if imgui.IsMouseDragging(MOUSE_LEFT, DRAG_START_THRESHOLD) then
            local drag_tex = nil
            if pending_drag.item_id and ctx.load_item_icon then
                drag_tex = ctx.load_item_icon(pending_drag.item_id)
            end
            ctx.on_slot_drag_start(pending_drag.slot, drag_tex)
            pending_drag = nil
        elseif not imgui.IsMouseDown(MOUSE_LEFT) then
            pending_drag = nil
        end
    elseif pending_matches and not imgui.IsMouseDown(MOUSE_LEFT) then
        pending_drag = nil
    end

    return metrics
end

function ui.render_toolbar_button(label, enabled, size)
    if enabled == false then
        imgui.PushStyleColor(ImGuiCol_Button, COLOR_DISABLED_BUTTON)
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_DISABLED_BUTTON)
        imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR_DISABLED_BUTTON)
        imgui.PushStyleColor(ImGuiCol_Text, COLOR_DISABLED_TEXT)
        if size then
            imgui.Button(label, size)
        else
            imgui.Button(label)
        end
        imgui.PopStyleColor(4)
        return false
    end

    ui.push_tab_button_style()
    -- Use if/else: `size and Button(size) or Button()` calls Button twice when
    -- the sized button returns false (not clicked), which duplicates widgets.
    local clicked
    if size then
        clicked = imgui.Button(label, size)
    else
        clicked = imgui.Button(label)
    end
    ui.pop_tab_button_style()
    return clicked
end

local function render_centered_button_list(child_id, items, scale, opts)
    scale = scale or ui.get_global_scale()
    opts = opts or {}

    local button_width = ui.scaled(180, scale)
    local row_gap = ui.scaled(2, scale)
    local button_h = ui.scaled(24, scale)

    if #items == 0 then
        if opts.empty_text then
            imgui.TextColored(COLOR_EMPTY_TEXT, opts.empty_text)
        end
        if opts.empty_help then
            imgui.TextWrapped(opts.empty_help)
        end
        return
    end

    local avail_w = get_content_avail_width()
    local avail_h = get_content_avail_height()
    local total_h = (#items * (button_h + row_gap)) - row_gap

    begin_child_compat(child_id, { avail_w, avail_h }, false, 0)

    local pad_y = 0
    if not opts.top_aligned then
        pad_y = math.max(0, (avail_h - total_h) * 0.5)
    end
    if pad_y > 0 then
        imgui.Dummy({ 0, pad_y })
    end

    if opts.use_tab_style then
        ui.push_tab_button_style()
    end

    local draw_list = imgui.GetWindowDrawList()
    local match_items = opts.search_match_items
    local search_active = opts.search_active == true
    local is_dragging = opts.is_dragging == true
    for index, item in ipairs(items) do
        center_cursor_for_width(button_width)
        local label = opts.format_label(item, index)
        local is_match = match_items and match_items[item]
        local dim_button = search_active and not is_match and not is_dragging
        if dim_button then
            local dim_btn = dim_color(COLOR_IDLE, DIM_SEARCH)
            local dim_text = dim_color(COLOR_TEXT, DIM_SEARCH)
            imgui.PushStyleColor(ImGuiCol_Button, dim_btn)
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, dim_btn)
            imgui.PushStyleColor(ImGuiCol_ButtonActive, dim_btn)
            imgui.PushStyleColor(ImGuiCol_Text, dim_text)
        end
        if imgui.Button(label, { button_width, 0 }) and opts.on_select then
            opts.on_select(item)
        end
        if dim_button then
            imgui.PopStyleColor(4)
        end
        if is_match and draw_list then
            local min_x, min_y = imgui.GetItemRectMin()
            local max_x, max_y = imgui.GetItemRectMax()
            if type(min_x) == 'number' and type(max_x) == 'number' then
                searchlogic.draw_match_border_rect(
                    draw_list,
                    min_x,
                    min_y,
                    max_x - min_x,
                    max_y - min_y,
                    1.0
                )
            end
        end
        if index < #items then
            imgui.Dummy({ 0, row_gap })
        end
    end

    if opts.use_tab_style then
        ui.pop_tab_button_style()
    end

    imgui.EndChild()
end

function ui.render_slip_picker(slip_ids, on_select, scale, format_label_fn, search_match_slips, search_active, is_dragging)
    render_centered_button_list('##satchel_slip_picker_list', slip_ids, scale, {
        empty_text = 'No storage slips found.',
        use_tab_style = true,
        top_aligned = true,
        search_active = search_active,
        is_dragging = is_dragging,
        search_match_items = search_match_slips,
        format_label = function(slip_id, index)
            if format_label_fn then
                return format_label_fn(slip_id, index)
            end
            return ('Storage Slip %02d##slip_pick_%d'):format(index, slip_id)
        end,
        on_select = on_select,
    })
end

function ui.render_centered_colored_text(color, text)
    center_cursor_for_width(get_text_width(text, 0))
    imgui.TextColored(color, text)
end

function ui.render_pagination_controls(page_index, page_count, on_page_change, scale, opts)
    scale = scale or ui.get_global_scale()
    opts = opts or {}
    local page = tonumber(page_index) or 0
    local total_pages = math.max(1, tonumber(page_count) or 1)
    local can_prev = page > 0
    local can_next = page < (total_pages - 1)
    local gap = ui.scaled(8, scale)
    local page_text = ('Page %d / %d'):format(page + 1, total_pages)

    if opts.centered then
        local group_w = estimate_button_width('Prev', scale)
            + gap + get_text_width(page_text, 0) + gap
            + estimate_button_width('Next', scale)
        center_cursor_for_width(group_w)
    end

    if ui.render_toolbar_button('Prev##satchel_page', can_prev) and on_page_change then
        on_page_change(page - 1)
    end
    imgui.SameLine(0, gap)
    imgui.TextColored(COLOR_USED_TEXT, page_text)
    imgui.SameLine(0, gap)
    if ui.render_toolbar_button('Next##satchel_page', can_next) and on_page_change then
        on_page_change(page + 1)
    end
end

function ui.render_alt_character_list(entries, on_select, scale)
    render_centered_button_list('##satchel_alt_picker_list', entries, scale, {
        empty_text = 'No cached alt inventories found.',
        empty_help = 'Log each character in at least once to build a cache.',
        use_tab_style = true,
        top_aligned = true,
        format_label = function(entry)
            return ('%s##alt_%s'):format(entry.name or 'Unknown', entry.key or '')
        end,
        on_select = on_select,
    })
end

return ui
