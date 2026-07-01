local imgui = require('imgui')
local bor = bit.bor
local components = require('config.components')
local searchhighlight = require('modules.satchel.searchhighlight')
local containerlogic = require('modules.satchel.containerlogic')
local satchelcolors = require('modules.satchel.colors')
local satchelfonts = require('modules.satchel.satchelfonts')

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

function ui.should_block_satchel_window_move()
    return block_window_move == true or pending_drag ~= nil
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

function ui.get_tab_sidebar_width(scale)
    return ui.scaled(132, scale or ui.get_global_scale())
end

function ui.get_tab_button_width(scale)
    scale = scale or ui.get_global_scale()
    return ui.get_tab_sidebar_width(scale) - ui.scaled(14, scale)
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
    if type(avail) == 'number' then
        return avail
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

local function get_content_avail_height()
    local h = select(2, imgui.GetContentRegionAvail())
    if type(h) == 'number' then
        return h
    end

    local win_h = imgui.GetWindowHeight()
    local cursor_y = imgui.GetCursorPosY()
    if type(win_h) == 'number' and type(cursor_y) == 'number' then
        return math.max(0, win_h - cursor_y - ui.scaled(10, ui.get_global_scale()))
    end

    return ui.scaled(100, ui.get_global_scale())
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

function ui.clear_pending_drag()
    pending_drag = nil
end

local function draw_outlined_text(draw_list, x, y, text, color, outline_px)
    if not draw_list or not text or text == '' then
        return
    end

    outline_px = outline_px or 1
    local outline = imgui.GetColorU32({ 0.0, 0.0, 0.0, 1.0 })
    local fill = imgui.GetColorU32(color or COLOR_QTY)

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

local function get_viewport_rows(settings)
    return get_configured_rows(settings) + 1
end

local function get_layout_rows(settings)
    return get_viewport_rows(settings)
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

local function normalize_search_query(query)
    if type(query) ~= 'string' then
        return ''
    end
    return (query:match('^%s*(.-)%s*$') or '')
end

local function estimate_button_width(label, scale)
    local text_w = get_text_width(label, ui.scaled(80, scale))
    return text_w + ui.scaled(32, scale)
end

function ui.render_toolbar_with_search(search_buffer, scale, id_suffix, buttons)
    scale = scale or ui.get_global_scale()
    buttons = buttons or {}

    local gap = ui.scaled(8, scale)
    local visible_buttons = {}
    for _, button in ipairs(buttons) do
        if button.visible ~= false then
            visible_buttons[#visible_buttons + 1] = button
        end
    end

    local buttons_w = 0
    for index, button in ipairs(visible_buttons) do
        buttons_w = buttons_w + estimate_button_width(button.label, scale)
        if index > 1 then
            buttons_w = buttons_w + gap
        end
    end

    local avail_w = get_content_avail_width()
    local search_w = math.max(ui.scaled(80, scale), avail_w - buttons_w - (buttons_w > 0 and gap or 0))
    ui.render_search_bar(search_buffer, search_w, scale, id_suffix)

    local clicks = {}
    if #visible_buttons > 0 then
        imgui.SameLine(0, gap)
        local row_start = imgui.GetCursorPosX()
        local remaining_w = get_content_avail_width()
        imgui.SetCursorPosX(row_start + remaining_w - buttons_w)

        for index, button in ipairs(visible_buttons) do
            if index > 1 then
                imgui.SameLine(0, gap)
            end
            clicks[button.id] = ui.render_toolbar_button(button.label)
        end
    end

    return clicks
end

function ui.render_search_bar(buffer, width, scale, id_suffix)
    scale = scale or ui.get_global_scale()
    if type(buffer) ~= 'table' then
        return
    end

    local widget_id = ('##satchel_search_%s'):format(tostring(id_suffix or 'main'))
    imgui.PushStyleColor(ImGuiCol_FrameBg, { 0.067, 0.063, 0.055, 0.95 })
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, COLOR_HOVER)
    imgui.PushStyleColor(ImGuiCol_FrameBgActive, COLOR_IDLE)
    imgui.PushItemWidth(width or ui.scaled(180, scale))
    local ok = pcall(imgui.InputTextWithHint, widget_id, 'Search items...', buffer, 64)
    if not ok then
        imgui.InputText(('Search%s'):format(widget_id), buffer, 64)
    end
    imgui.PopItemWidth()
    imgui.PopStyleColor(3)
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

function ui.render_inventory_footer(stat, ctx, opts)
    opts = opts or {}
    local scale = opts.scale or ui.get_global_scale()
    local sidebar_width = opts.sidebar_width or 0
    local gap = opts.gap or ui.scaled(8, scale)

    local used = (stat and stat.used) or 0
    local total = (stat and stat.total) or 0

    if sidebar_width > 0 then
        imgui.SetCursorPosX(imgui.GetCursorPosX() + sidebar_width + gap)
    end
    imgui.TextColored(COLOR_USED_TEXT, ('Used: %d / %d'):format(used, total))

    if not ctx or not ctx.get_gil_amount or not ctx.format_gil_text or ctx.hide_gil then
        return
    end

    local gil_amount = ctx.get_gil_amount()
    if gil_amount == nil then
        return
    end

    local gil_text = ctx.format_gil_text(gil_amount)
    local gil_icon = ctx.load_gil_icon and ctx.load_gil_icon() or nil
    local _, text_h = imgui.CalcTextSize(gil_text)
    text_h = type(text_h) == 'number' and text_h or ui.scaled(14, scale)
    local icon_size = math.min(ui.scaled(14, scale), text_h)
    local icon_gap = ui.scaled(4, scale)
    local text_w = get_text_width(gil_text, 0)
    local right_width = text_w + (gil_icon and (icon_size + icon_gap) or 0)
    local right_x = math.max(0, get_full_content_width() - right_width)
    imgui.SameLine(right_x)

    if gil_icon then
        local ptr = ctx.tex_ptr and ctx.tex_ptr(gil_icon) or nil
        if ptr then
            imgui.Image(ptr, { icon_size, icon_size })
            imgui.SameLine(0, icon_gap)
        end
    end

    imgui.TextColored(COLOR_GIL_TEXT, gil_text)
end

local function draw_slot_icon(draw_list, tex_ptr, screen_x, screen_y, icon_size, icon_alpha)
    if not draw_list or not tex_ptr or tex_ptr == 0 or icon_alpha <= 0.01 then
        return
    end

    local tint = imgui.GetColorU32({ icon_alpha, icon_alpha, icon_alpha, 1.0 })
    draw_list:AddImage(
        tex_ptr,
        { screen_x, screen_y },
        { screen_x + icon_size, screen_y + icon_size },
        { 0, 0 },
        { 1, 1 },
        tint
    )
end

local function draw_slot(slot, index, key_prefix, ctx)
    local slot_size = ctx.slot_size or ctx.settings.slot_size
    local icon_padding = math.max(1, math.floor(slot_size * 0.05))
    local icon_size = math.max(20, slot_size - (icon_padding * 2))
    local locked = slot.locked == true
    local read_only = slot.read_only == true or ctx.read_only == true
    local search_query = normalize_search_query(ctx.search_query or '')
    local search_active = search_query ~= ''
    local search_match = false
    if search_active and slot.id and slot.id > 0 and ctx.item_matches_search then
        search_match = ctx.item_matches_search(slot, search_query) == true
    end

    local border_color = locked and dim_color(satchelcolors.get_locked_slot_border(), 0.5) or ctx.get_slot_border_color(slot)
    if not locked and (not slot.id or slot.id <= 0) then
        border_color = satchelcolors.get_empty_slot_border()
    end

    local is_dragging = ctx.is_dragging and ctx.is_dragging() == true
    local is_drag_source = is_dragging
        and ctx.is_drag_source
        and ctx.is_drag_source(slot) == true
    local can_accept_drop = is_dragging
        and ctx.can_drop_to_slot
        and not read_only
        and not locked
        and ctx.can_drop_to_slot(slot) == true
    local is_empty_slot = not locked and (not slot.id or slot.id <= 0)

    local search_dim = search_active and slot.id and slot.id > 0 and not search_match
    local icon_alpha = 1.0
    if locked then
        icon_alpha = 0.35
    elseif is_drag_source then
        icon_alpha = DIM_SEARCH
    elseif search_dim then
        icon_alpha = DIM_SEARCH
        border_color = dim_color(border_color, DIM_SEARCH)
    elseif search_match then
        border_color = COLOR_SLOT_BG
    end

    local tex = nil
    local slot_id = ('##satchel_slot_%s_%d'):format(tostring(key_prefix or 'all'), index)
    imgui.InvisibleButton(slot_id, { slot_size, slot_size })

    local drag_source_hovered = is_dragging
        and is_drag_source
        and imgui.IsItemHovered(DRAG_HOVER_FLAGS)

    local drop_target_hovered = is_dragging
        and not is_drag_source
        and not read_only
        and not locked
        and imgui.IsItemHovered(DRAG_HOVER_FLAGS)

    local min_x, min_y = imgui.GetItemRectMin()
    local max_x, max_y = imgui.GetItemRectMax()
    local draw_list = imgui.GetWindowDrawList()
    local slot_bg = locked and COLOR_SLOT_LOCKED_BG or COLOR_SLOT_BG

    if is_drag_source then
        slot_bg, border_color = apply_drag_slot_colors(slot_bg, false, false)
    elseif is_dragging and not read_only and not locked and is_empty_slot then
        slot_bg, border_color = apply_drag_slot_colors(slot_bg, can_accept_drop, false)
    end

    if drag_source_hovered then
        slot_bg, border_color = apply_drag_slot_colors(slot_bg, false, true)
    elseif drop_target_hovered then
        slot_bg, border_color = apply_drag_slot_colors(slot_bg, can_accept_drop, true)
    end

    if is_drag_source then
        border_color = satchelcolors.get_drag_drop_invalid_highlight_hover()
    end

    if not read_only and not locked and slot.id and slot.id > 0
        and imgui.IsItemActive() and imgui.IsMouseDown(MOUSE_LEFT) then
        block_window_move = true
    end

    if draw_list and type(min_x) == 'number' and type(min_y) == 'number'
        and type(max_x) == 'number' and type(max_y) == 'number' then
        draw_list:AddRectFilled({ min_x, min_y }, { max_x, max_y }, imgui.GetColorU32(slot_bg))
        draw_list:AddRect({ min_x, min_y }, { max_x, max_y }, imgui.GetColorU32(border_color), 0, 0, 1.0)

        if slot.id and slot.id > 0 then
            tex = ctx.load_item_icon(slot.id)
            if tex then
                draw_slot_icon(
                    draw_list,
                    ctx.tex_ptr(tex),
                    min_x + icon_padding,
                    min_y + icon_padding,
                    icon_size,
                    icon_alpha
                )
            else
                draw_list:AddText(
                    { min_x + 4, min_y + 8 },
                    imgui.GetColorU32(dim_color(COLOR_MISSING_ICON, icon_alpha)),
                    '?'
                )
            end

            if slot.count and slot.count > 1 then
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
                    dim_color(COLOR_QTY, icon_alpha),
                    outline_px
                )
            end
        end
    end

    if search_match and ctx.search_highlights then
        local min_x, min_y = imgui.GetItemRectMin()
        local max_x, max_y = imgui.GetItemRectMax()
        local size = slot_size
        if type(min_x) == 'number' and type(max_x) == 'number' then
            size = max_x - min_x
        end
        if type(min_y) == 'number' and type(max_y) == 'number' then
            size = max_y - min_y
        end
        ctx.search_highlights[#ctx.search_highlights + 1] = { min_x, min_y, size }
    end

    if drop_target_hovered and can_accept_drop then
        ctx.pending_drop_target = slot
    end

    local slot_hovered = is_dragging and imgui.IsItemHovered(DRAG_HOVER_FLAGS) or imgui.IsItemHovered()
    if not locked and slot_hovered and slot.id and slot.id > 0 and ctx.render_item_detail_tooltip then
        local ok, err = pcall(ctx.render_item_detail_tooltip, slot)
        if not ok and ashita and ashita.log and ashita.log.error then
            ashita.log.error(('[XIUI Satchel] tooltip error: %s'):format(tostring(err)))
        end
    end

    if not read_only and not locked and slot.id and slot.id > 0 and imgui.IsItemClicked(MOUSE_RIGHT) and ctx.on_slot_right_click then
        ctx.on_slot_right_click(slot)
    end

    if not read_only and not locked and slot.id and slot.id > 0 and ctx.on_slot_drag_start
        and imgui.IsItemClicked(MOUSE_LEFT) then
        pending_drag = { slot = slot, item_id = slot.id }
    end

    if not read_only and not locked and slot.id and slot.id > 0 and ctx.on_slot_double_click
        and imgui.IsItemHovered() and imgui.IsMouseDoubleClicked(MOUSE_LEFT) then
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
        local viewport_rows = get_viewport_rows(settings)
        local total_slots = math.max(1, tonumber(slot_count) or DISPLAY_SLOTS)
        local natural_rows = math.max(1, math.ceil(total_slots / columns))
        local needs_scroll = natural_rows > viewport_rows
        local grid_width = (columns * slot_size) + ((columns - 1) * cell_gap)
        local grid_height = compute_row_grid_height(viewport_rows, slot_size, cell_gap)
        local content_height = compute_row_grid_height(natural_rows, slot_size, cell_gap)
        if needs_scroll then
            content_height = content_height + slot_size + cell_gap
        end

        return {
            columns = columns,
            used_columns = columns,
            total_slots = total_slots,
            visible_rows = viewport_rows,
            configured_rows = get_configured_rows(settings),
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
    block_window_move = false

    local packed = get_slots_for_grid(slots, ctx.settings)
    local packed_count = #packed
    local slot_count_for_metrics = DISPLAY_SLOTS
    if ctx.settings.hide_empty_slots == true then
        slot_count_for_metrics = math.max(packed_count, 1)
    end
    local metrics = ui.compute_grid_metrics(ctx.settings, slot_count_for_metrics, scale, { layout_size = true })
    ctx.search_highlights = {}
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

    for i = 1, packed_count do
        draw_slot(packed[i], i, tostring(key_prefix), ctx)
        if i % metrics.columns ~= 0 then
            imgui.SameLine(0, metrics.cell_gap)
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
        and ctx.is_dragging
        and ctx.is_dragging() == true
        and ctx.can_drop_to_slot
        and ctx.can_drop_to_slot(ctx.pending_drop_target) == true
        and imgui.IsMouseReleased(MOUSE_LEFT) then
        ctx.on_drop_to_slot(ctx.pending_drop_target)
    end

    imgui.EndChild()
    imgui.PopStyleVar(1)

    local foreground = imgui.GetForegroundDrawList()
    if foreground and ctx.search_highlights then
        for _, highlight in ipairs(ctx.search_highlights) do
            local inset = 1
            searchhighlight.draw_match_border(
                foreground,
                highlight[1] + inset,
                highlight[2] + inset,
                math.max(1, highlight[3] - (inset * 2)),
                1.0
            )
        end
    end
    ctx.search_highlights = nil

    if not ctx.read_only and pending_drag and ctx.on_slot_drag_start then
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
    elseif pending_drag and not imgui.IsMouseDown(MOUSE_LEFT) then
        pending_drag = nil
    end

    return metrics
end

function ui.render_toolbar_button(label, enabled)
    if enabled == false then
        imgui.PushStyleColor(ImGuiCol_Button, COLOR_DISABLED_BUTTON)
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_DISABLED_BUTTON)
        imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR_DISABLED_BUTTON)
        imgui.PushStyleColor(ImGuiCol_Text, COLOR_DISABLED_TEXT)
        imgui.Button(label)
        imgui.PopStyleColor(4)
        return false
    end

    ui.push_tab_button_style()
    local clicked = imgui.Button(label)
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

    local pad_y = math.max(0, (avail_h - total_h) * 0.5)
    if pad_y > 0 then
        imgui.Dummy({ 0, pad_y })
    end

    if opts.use_tab_style then
        ui.push_tab_button_style()
    end

    for index, item in ipairs(items) do
        center_cursor_for_width(button_width)
        local label = opts.format_label(item, index)
        if imgui.Button(label, { button_width, 0 }) and opts.on_select then
            opts.on_select(item)
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

function ui.render_slip_picker(slip_ids, on_select, scale, format_label_fn)
    render_centered_button_list('##satchel_slip_picker_list', slip_ids, scale, {
        empty_text = 'No storage slips found.',
        use_tab_style = true,
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
        format_label = function(entry)
            return ('%s##alt_%s'):format(entry.name or 'Unknown', entry.key or '')
        end,
        on_select = on_select,
    })
end

return ui
