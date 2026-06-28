local imgui = require('imgui')
local bor = bit.bor
local components = require('config.components')
local searchhighlight = require('modules.satchel.searchhighlight')

local ui = {}

local COLOR_SELECTED = { 0.957, 0.855, 0.592, 0.25 }
local COLOR_HOVER = { 0.137, 0.125, 0.106, 1.0 }
local COLOR_IDLE = { 0.098, 0.090, 0.075, 1.0 }
local COLOR_TEXT = { 0.878, 0.855, 0.812, 1.0 }
local COLOR_DRAG_VALID = { 0.15, 0.48, 0.18, 1.0 }
local COLOR_DRAG_VALID_HOVER = { 0.19, 0.58, 0.23, 1.0 }
local COLOR_DRAG_INVALID = { 0.48, 0.16, 0.14, 1.0 }
local COLOR_DRAG_INVALID_HOVER = { 0.58, 0.20, 0.18, 1.0 }
local COLOR_SLOT_BG = { 0.098, 0.090, 0.075, 1.0 }
local COLOR_SLOT_LOCKED_BG = { 0.055, 0.050, 0.045, 1.0 }
local COLOR_SLOT_LOCKED_BORDER = { 0.38, 0.36, 0.32, 0.75 }
local COLOR_WINDOW_BORDER = { 0.3, 0.28, 0.24, 0.8 }
local DIM_SEARCH = 0.3
local COLOR_QTY = { 0.99, 0.95, 0.75, 1.0 }
local COLOR_MISSING_ICON = { 0.9, 0.82, 0.50, 1.0 }
local COLOR_EMPTY_TEXT = { 0.75, 0.75, 0.75, 1.0 }
local COLOR_USED_TEXT = { 0.78, 0.78, 0.78, 1.0 }
local COLOR_GIL_TEXT = { 0.98, 0.88, 0.48, 1.0 }
local COLOR_FULL = { 0.92, 0.24, 0.20, 1.0 }
local COLOR_DISABLED_TEXT = { 0.42, 0.42, 0.42, 1.0 }
local COLOR_DISABLED_BUTTON = { 0.07, 0.07, 0.07, 0.85 }

local SLOT_CHILD_FLAGS = bor(ImGuiWindowFlags_NoScrollbar or 0, ImGuiWindowFlags_NoScrollWithMouse or 0)
local DRAG_HOVER_FLAGS = ImGuiHoveredFlags_AllowWhenBlockedByActiveItem or 0
local DRAG_START_THRESHOLD = 4

local pending_drag = nil

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
end

function ui.pop_config_window_style()
    components.PopWindowStyle()
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

function ui.render_left_tab_column(available_tabs, current_tab, format_tab_label, drag_ctx, scale)
    scale = scale or ui.get_global_scale()
    local tab_width = ui.scaled(110, scale)

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

    imgui.PushStyleColor(ImGuiCol_Button, COLOR_IDLE)
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLOR_HOVER)
    imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR_SELECTED)
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 4.0)

    local is_dragging = drag_ctx and drag_ctx.is_dragging == true

    for i, container_id in ipairs(available_tabs) do
        local is_selected = (container_id == current_tab)
        local label = format_tab_label(container_id)
        local can_drop_here = false

        if is_dragging and drag_ctx.can_drop_to_container then
            can_drop_here = drag_ctx.can_drop_to_container(container_id) == true
        end

        if is_dragging then
            local drag_color = can_drop_here and COLOR_DRAG_VALID or COLOR_DRAG_INVALID
            local drag_hover = can_drop_here and COLOR_DRAG_VALID_HOVER or COLOR_DRAG_INVALID_HOVER
            imgui.PushStyleColor(ImGuiCol_Button, drag_color)
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, drag_hover)
            imgui.PushStyleColor(ImGuiCol_Text, COLOR_TEXT)
        elseif is_selected then
            imgui.PushStyleColor(ImGuiCol_Button, COLOR_SELECTED)
            imgui.PushStyleColor(ImGuiCol_Text, COLOR_TEXT)
        else
            imgui.PushStyleColor(ImGuiCol_Text, COLOR_TEXT)
        end

        local clicked = imgui.Button(label .. ('##satchel_tab_%d'):format(container_id), { tab_width, 0 })
        if clicked and not is_dragging then
            current_tab = container_id
        end

        local _, btn_min_y = imgui.GetItemRectMin()
        local btn_max_x, btn_max_y = imgui.GetItemRectMax()
        local is_full = drag_ctx and drag_ctx.is_container_full and drag_ctx.is_container_full(container_id)

        local hovered_for_drop = imgui.IsItemHovered(DRAG_HOVER_FLAGS)
        if is_dragging and drag_ctx.on_drop_to_container and hovered_for_drop and imgui.IsMouseReleased(ImGuiMouseButton_Left) then
            drag_ctx.on_drop_to_container(container_id)
        end

        if is_dragging then
            imgui.PopStyleColor(3)
        elseif is_selected then
            imgui.PopStyleColor(2)
        else
            imgui.PopStyleColor(1)
        end

        if is_full and not is_dragging then
            draw_full_badge(btn_max_x, btn_min_y, btn_max_y)
        end

        if i < #available_tabs then
            imgui.Dummy({ 0, ui.scaled(2, scale) })
        end
    end

    imgui.PopStyleVar(1)
    imgui.PopStyleColor(3)

    return current_tab, tab_width
end

local function draw_slot_icon(draw_list, tex_ptr, screen_x, screen_y, icon_size, icon_alpha)
    if not draw_list or not tex_ptr or icon_alpha <= 0.01 then
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
        search_match = ctx.item_matches_search(slot.id, search_query) == true
    end

    local border_color = locked and dim_color(COLOR_SLOT_LOCKED_BORDER, 0.5) or ctx.get_slot_border_color(slot)
    if not locked and (not slot.id or slot.id <= 0) then
        border_color = COLOR_WINDOW_BORDER
    end

    local search_dim = search_active and slot.id and slot.id > 0 and not search_match
    local icon_alpha = 1.0
    if locked then
        icon_alpha = 0.35
    elseif search_dim then
        icon_alpha = DIM_SEARCH
        border_color = dim_color(border_color, DIM_SEARCH)
    elseif search_match then
        border_color = COLOR_SLOT_BG
    end

    imgui.PushStyleColor(ImGuiCol_ChildBg, locked and COLOR_SLOT_LOCKED_BG or COLOR_SLOT_BG)
    imgui.PushStyleColor(ImGuiCol_Border, border_color)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 })
    imgui.PushStyleVar(ImGuiStyleVar_ChildRounding, 0.0)

    local tex = nil
    local began = begin_child_compat(('##satchel_slot_%s_%d'):format(tostring(key_prefix or 'all'), index), { slot_size, slot_size }, true, SLOT_CHILD_FLAGS)
    if began then
        if slot.id and slot.id > 0 then
            tex = ctx.load_item_icon(slot.id)
            if tex then
                imgui.SetCursorPos({ icon_padding, icon_padding })
                local icon_x, icon_y = imgui.GetCursorScreenPos()
                imgui.Dummy({ icon_size, icon_size })
                local draw_list = imgui.GetWindowDrawList()
                if draw_list then
                    draw_slot_icon(draw_list, ctx.tex_ptr(tex), icon_x, icon_y, icon_size, icon_alpha)
                end
            else
                imgui.SetCursorPos({ 4, 8 })
                imgui.TextColored(dim_color(COLOR_MISSING_ICON, icon_alpha), '?')
            end

            if slot.count and slot.count > 1 then
                local qty_text = tostring(slot.count)
                local text_w, text_h = imgui.CalcTextSize(qty_text)
                text_w = type(text_w) == 'number' and text_w or 0
                text_h = type(text_h) == 'number' and text_h or 0
                local x = math.max(2, slot_size - text_w - 3)
                local y = math.max(2, slot_size - text_h - 2)
                imgui.SetCursorPos({ x, y })
                imgui.TextColored(dim_color(COLOR_QTY, icon_alpha), qty_text)
            end
        end
    end
    imgui.EndChild()

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

    imgui.PopStyleVar(2)
    imgui.PopStyleColor(2)

    if not locked and imgui.IsItemHovered() and slot.id and slot.id > 0 then
        ctx.render_item_detail_tooltip(slot)
    end

    if not read_only and not locked and slot.id and slot.id > 0 and imgui.IsItemClicked(ImGuiMouseButton_Right) and ctx.on_slot_right_click then
        ctx.on_slot_right_click(slot)
    end

    if not read_only and not locked and slot.id and slot.id > 0 and ctx.on_slot_drag_start
        and imgui.IsItemClicked(ImGuiMouseButton_Left) then
        pending_drag = { slot = slot, tex = tex }
    end

    if not read_only and not locked and slot.id and slot.id > 0 and ctx.on_slot_double_click
        and imgui.IsItemHovered() and imgui.IsMouseDoubleClicked(ImGuiMouseButton_Left) then
        ctx.on_slot_double_click(slot)
    end
end

function ui.compute_grid_metrics(settings, slot_count, scale, opts)
    scale = scale or ui.get_global_scale()
    opts = opts or {}
    local columns = math.max(4, tonumber(settings.columns) or 10)
    local configured_rows = math.max(1, tonumber(settings.rows) or 8)
    local total_slots = math.max(1, tonumber(slot_count) or 1)
    local used_columns = math.max(1, math.min(columns, total_slots))
    local natural_rows = math.max(1, math.ceil(total_slots / used_columns))
    local visible_rows = natural_rows
    if not opts.show_all_rows then
        visible_rows = math.min(configured_rows, natural_rows)
    end
    local cell_gap = ui.scaled(2, scale)
    local slot_size = ui.scaled(settings.slot_size or 40, scale)
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

    local packed = slots or {}
    local packed_count = #packed
    local metrics = ui.compute_grid_metrics(ctx.settings, packed_count, scale, ctx.grid_opts)
    ctx.search_highlights = {}

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

    if not ctx.read_only and pending_drag and ctx.on_slot_drag_start
        and imgui.IsMouseDragging(ImGuiMouseButton_Left, DRAG_START_THRESHOLD) then
        ctx.on_slot_drag_start(pending_drag.slot, pending_drag.tex)
    end
    if not imgui.IsMouseDown(ImGuiMouseButton_Left) then
        pending_drag = nil
    end

    local used = (stat and stat.used) or 0
    local total = (stat and stat.total) or 0
    imgui.TextColored(COLOR_USED_TEXT, ('Used: %d / %d'):format(used, total))

    if ctx.get_gil_amount and ctx.format_gil_text and not ctx.hide_gil then
        local gil_amount = ctx.get_gil_amount()
        if gil_amount ~= nil then
            local gil_text = ctx.format_gil_text(gil_amount)
            local gil_icon = ctx.load_gil_icon and ctx.load_gil_icon() or nil
            local _, text_h = imgui.CalcTextSize(gil_text)
            text_h = type(text_h) == 'number' and text_h or ui.scaled(14, scale)
            local icon_size = math.min(ui.scaled(14, scale), text_h)
            local gap = ui.scaled(4, scale)

            local text_w = get_text_width(gil_text, 0)

            local right_width = text_w
            if gil_icon then
                right_width = right_width + icon_size + gap
            end

            local right_x = math.max(0, metrics.grid_width - right_width)
            imgui.SameLine(right_x)

            if gil_icon then
                imgui.Image(ctx.tex_ptr(gil_icon), { icon_size, icon_size })
                imgui.SameLine(0, gap)
            end

            imgui.TextColored(COLOR_GIL_TEXT, gil_text)
        end
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
