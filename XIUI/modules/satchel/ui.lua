local imgui = require('imgui')
local bor = bit.bor

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
local COLOR_QTY = { 0.99, 0.95, 0.75, 1.0 }
local COLOR_MISSING_ICON = { 0.9, 0.82, 0.50, 1.0 }
local COLOR_EMPTY_TEXT = { 0.75, 0.75, 0.75, 1.0 }
local COLOR_USED_TEXT = { 0.78, 0.78, 0.78, 1.0 }
local COLOR_GIL_TEXT = { 0.98, 0.88, 0.48, 1.0 }

local SLOT_CHILD_FLAGS = bor(ImGuiWindowFlags_NoScrollbar or 0, ImGuiWindowFlags_NoScrollWithMouse or 0)
local DRAG_HOVER_FLAGS = ImGuiHoveredFlags_AllowWhenBlockedByActiveItem or 0
local DRAG_START_THRESHOLD = 4

-- Ashita 4.3 adjusted BeginChild overloads; try multiple signatures for compatibility.
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

function ui.render_left_tab_column(available_tabs, current_tab, format_tab_label, drag_ctx)
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

        local clicked = imgui.Button(label .. ('##satchel_tab_%d'):format(container_id), { 110, 0 })
        if clicked and not is_dragging then
            current_tab = container_id
        end

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

        if i < #available_tabs then
            imgui.Dummy({ 0, 2 })
        end
    end

    imgui.PopStyleVar(1)
    imgui.PopStyleColor(3)

    return current_tab
end

local function draw_slot(slot, index, key_prefix, ctx)
    local slot_size = ctx.settings.slot_size
    local icon_padding = 2
    local icon_size = math.max(20, slot_size - (icon_padding * 2))
    imgui.PushStyleColor(ImGuiCol_ChildBg, COLOR_SLOT_BG)
    imgui.PushStyleColor(ImGuiCol_Border, ctx.get_slot_border_color(slot))
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 })

    local tex = nil
    local began = begin_child_compat(('##satchel_slot_%s_%d'):format(tostring(key_prefix or 'all'), index), { slot_size, slot_size }, true, SLOT_CHILD_FLAGS)
    if began then
        if slot.id and slot.id > 0 then
            tex = ctx.load_item_icon(slot.id)
            if tex then
                imgui.SetCursorPos({ icon_padding, icon_padding })
                imgui.Image(ctx.tex_ptr(tex), { icon_size, icon_size }, { 0, 0 }, { 1, 1 }, { 1, 1, 1, 1 }, { 0, 0, 0, 0 })
            else
                imgui.SetCursorPos({ 4, 8 })
                imgui.TextColored(COLOR_MISSING_ICON, '?')
            end

            if slot.count and slot.count > 1 then
                local qty_text = tostring(slot.count)
                local text_w, text_h = imgui.CalcTextSize(qty_text)
                text_w = tonumber(text_w) or 0
                text_h = tonumber(text_h) or 0
                local x = math.max(2, slot_size - text_w - 3)
                local y = math.max(2, slot_size - text_h - 2)
                imgui.SetCursorPos({ x, y })
                imgui.TextColored(COLOR_QTY, qty_text)
            end
        end
    end
    imgui.EndChild()

    imgui.PopStyleVar(1)
    imgui.PopStyleColor(2)

    if imgui.IsItemHovered() and slot.id and slot.id > 0 then
        ctx.render_item_detail_tooltip(slot)
    end

    if slot.id and slot.id > 0 and imgui.IsItemClicked(ImGuiMouseButton_Right) and ctx.on_slot_right_click then
        ctx.on_slot_right_click(slot)
    end

    -- Start dragging only after the mouse moves past a small threshold (not on a bare
    -- click), so a click/double-click doesn't flash the drop-target colors.
    if slot.id and slot.id > 0 and ctx.on_slot_drag_start then
        local hovered_for_drag = imgui.IsItemHovered(DRAG_HOVER_FLAGS)
        if hovered_for_drag and imgui.IsMouseDragging(ImGuiMouseButton_Left, DRAG_START_THRESHOLD) then
            ctx.on_slot_drag_start(slot, tex)
        end
    end

    -- After the drag block: a double-click transfers and cancels the drag it started.
    if slot.id and slot.id > 0 and ctx.on_slot_double_click
        and imgui.IsItemHovered() and imgui.IsMouseDoubleClicked(ImGuiMouseButton_Left) then
        ctx.on_slot_double_click(slot)
    end
end

-- Build the display order: non-empty items sorted by category/name, then (optionally)
-- the empty slots appended in their original order.
local function prepare_slot_order(slots, ctx)
    local packed = {}
    local packed_count = 0
    local empties = {}
    local empties_count = 0

    for _, slot in ipairs(slots or {}) do
        if slot and slot.id and slot.id > 0 then
            packed_count = packed_count + 1
            packed[packed_count] = slot
        else
            empties_count = empties_count + 1
            empties[empties_count] = slot
        end
    end

    if packed_count > 1 then
        local sortable = {}
        for i = 1, packed_count do
            local slot = packed[i]
            local primary, secondary = ctx.get_item_sort_key(slot.id)
            sortable[i] = {
                slot = slot,
                primary = primary,
                secondary = secondary,
                name = (ctx.get_item_name(slot.id) or ''):lower(),
                id = slot.id or 0,
                slot_index = slot.slot_index or 0,
            }
        end

        table.sort(sortable, function(a, b)
            if a.primary ~= b.primary then
                return a.primary < b.primary
            end

            if a.secondary ~= b.secondary then
                return a.secondary < b.secondary
            end

            if a.name == b.name then
                if a.id ~= b.id then
                    return a.id < b.id
                end
                return a.slot_index < b.slot_index
            end
            return a.name < b.name
        end)

        for i = 1, packed_count do
            packed[i] = sortable[i].slot
        end
    end

    if ctx.settings.show_empty_slots then
        for i = 1, empties_count do
            packed_count = packed_count + 1
            packed[packed_count] = empties[i]
        end
    end

    return packed, packed_count
end

-- Memoized sorted layout per container. build_slot_data hands us a fresh `slots`
-- table on every cache rebuild (~6x/sec), so reuse the sort while that table and the
-- show-empty toggle are unchanged instead of re-sorting every frame (~60x/sec).
local sort_cache = {}

function ui.render_slot_grid(slots, key_prefix, stat, ctx)
    local cache_key = tostring(key_prefix)
    local show_empty = ctx.settings.show_empty_slots and true or false
    local cached = sort_cache[cache_key]

    local packed, packed_count
    if cached and cached.slots == slots and cached.show_empty == show_empty then
        packed = cached.packed
        packed_count = cached.packed_count
    else
        packed, packed_count = prepare_slot_order(slots, ctx)
        sort_cache[cache_key] = {
            slots = slots,
            show_empty = show_empty,
            packed = packed,
            packed_count = packed_count,
        }
    end

    local columns = math.max(4, tonumber(ctx.settings.columns) or 10)
    local total_slots = packed_count
    local shown_slots = math.max(1, total_slots)
    local used_columns = math.max(1, math.min(columns, shown_slots))
    local row_count = math.max(1, math.ceil(shown_slots / columns))
    local cell_gap = 2
    local slot_size = ctx.settings.slot_size or ctx.default_slot_size
    local grid_width = (used_columns * slot_size) + ((used_columns - 1) * cell_gap)

    -- Cap the visible height to the configured row count and scroll the overflow.
    local max_rows = math.max(1, tonumber(ctx.settings.rows) or row_count)
    local visible_rows = math.min(row_count, max_rows)
    local needs_scroll = row_count > visible_rows
    local grid_height = (visible_rows * slot_size) + ((visible_rows - 1) * cell_gap)
    local scrollbar_w = needs_scroll and 16 or 0

    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { cell_gap, cell_gap })
    begin_child_compat(('##satchel_grid_%s'):format(tostring(key_prefix)), { grid_width + scrollbar_w, grid_height }, false, 0)
    for i = 1, total_slots do
        local slot = packed[i]

        draw_slot(slot, i, tostring(key_prefix), ctx)

        if i % columns ~= 0 then
            imgui.SameLine(0, cell_gap)
        end
    end

    if total_slots == 0 then
        imgui.TextColored(COLOR_EMPTY_TEXT, 'No slots to display.')
    end
    imgui.EndChild()
    imgui.PopStyleVar(1)

    local used = (stat and stat.used) or 0
    local total = (stat and stat.total) or 0
    imgui.TextColored(COLOR_USED_TEXT, ('Used: %d / %d'):format(used, total))

    if ctx.get_gil_amount and ctx.format_gil_text then
        local gil_amount = ctx.get_gil_amount()
        if gil_amount ~= nil then
            local gil_text = ctx.format_gil_text(gil_amount)
            local gil_icon = ctx.load_gil_icon and ctx.load_gil_icon() or nil
            local icon_size = 14
            local gap = 4

            local text_w = imgui.CalcTextSize(gil_text)
            text_w = tonumber(text_w) or 0

            local right_width = text_w
            if gil_icon then
                right_width = right_width + icon_size + gap
            end

            local right_x = math.max(0, grid_width - right_width)
            imgui.SameLine(right_x)

            if gil_icon then
                imgui.Image(ctx.tex_ptr(gil_icon), { icon_size, icon_size })
                imgui.SameLine(0, gap)
            end

            imgui.TextColored(COLOR_GIL_TEXT, gil_text)
        end
    end
end

return ui
