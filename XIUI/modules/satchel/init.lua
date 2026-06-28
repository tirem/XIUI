require('common')
local imgui = require('imgui')
local struct = require('struct')

local ui = require('modules.satchel.ui')
local itemlogic = require('modules.satchel.itemlogic')
local containerlogic = require('modules.satchel.containerlogic')
local icons = require('modules.satchel.icons')
local footerlogic = require('modules.satchel.footerlogic')
local settingslogic = require('modules.satchel.settings')
local packetslogic = require('modules.satchel.packets')
local mogstate = require('modules.satchel.mogstate')
local contextmenu = require('modules.satchel.contextmenu')
local slipslogic = require('modules.satchel.slipslogic')
local altcache = require('modules.satchel.altcache')

local M = {}

local band = bit.band
local bor = bit.bor

local WINDOW_FLAGS = bor(
    ImGuiWindowFlags_NoCollapse or 0,
    ImGuiWindowFlags_NoResize or 0
)
local SLIP_WINDOW_PAD_X = 44
local SLIP_WINDOW_PAD_BOTTOM = 174
local FIELD_BAGS = { [0] = true, [5] = true, [6] = true, [7] = true }
local WINDOW_HOVER_FLAGS = bor(ImGuiHoveredFlags_AllowWhenBlockedByPopup or 0, ImGuiHoveredFlags_AllowWhenBlockedByActiveItem or 0)
local DISPLAY_SLOTS = containerlogic.DISPLAY_SLOTS
local SLOT_CACHE_TTL_SECONDS = 0.15

local satchel = T{
    initialized = false,
    hidden = false,
    settings = T{},
    visible = { true },
    last_visible = true,
    active_tab = nil,
    resize_on_next_frame = false,
    icons = {},
    file_icons = {},
    names = {},
    item_types = {},
    item_sort_keys = {},
    drag = {
        active = false,
        source_slot = nil,
        source_icon = nil,
        source_name = '',
    },
    window_drag = {
        active = false,
    },
    packet_sync = {
        value = nil,
    },
    slot_cache = {
        checked_at = 0,
        all_slots = nil,
        slots_by_container = nil,
        stats = nil,
    },
    in_mog_house = false,
    context_menu = {
        pending_open = false,
        slot = nil,
    },
    split_dialog = {
        pending_open = false,
        slot = nil,
        quantity = { 1 },
    },
    bazaar_dialog = {
        pending_open = false,
        slot = nil,
        price = { 0 },
        is_modify = false,
    },
    drop_dialog = {
        pending_open = false,
        slot = nil,
    },
    slips_picker = {
        visible = { false },
        alt_entry = nil,
    },
    slip_view = {
        visible = { false },
        slip_id = nil,
        page = 0,
        alt_entry = nil,
    },
    alt_picker = {
        visible = { false },
    },
    alt_view = {
        visible = { false },
        entry = nil,
        active_tab = nil,
    },
    search = {
        main = { '' },
        slip = { '' },
        alt = { '' },
    },
    window_stack = {},
}

local items = itemlogic.create({
    satchel = satchel,
    imgui = imgui,
})

local footer = footerlogic.create({
    satchel = satchel,
    icons = icons,
    gil_icon_path = addon.path .. '\\assets\\gil.png',
})

local tab_order = containerlogic.tab_order
local default_settings = settingslogic.default_settings

local mog_house_bags = { [1] = true, [2] = true, [4] = true, [9] = true }

local settings = settingslogic.create({
    satchel = satchel,
    containerlogic = containerlogic,
})

local packets = packetslogic.create({
    satchel = satchel,
})

local mog = mogstate.create({
    satchel = satchel,
})

-- Forward-declared so the context menu's "Sort Bag" entry can reuse the same
-- cooldown/guard logic defined further down.
local handle_sort_container

local menus = contextmenu.create({
    satchel = satchel,
    imgui = imgui,
    items = items,
    packets = packets,
    on_sort = function(slot)
        handle_sort_container(slot)
    end,
})

local is_module_enabled = settings.is_module_enabled
local read_settings = settings.read_settings
local sync_display_settings = settings.sync_display_settings
local open_xiui_satchel_config = settings.open_xiui_satchel_config
local show_help = settings.show_help
local print_disabled_message = settings.print_disabled_message

local function clear_drag_state()
    satchel.drag.active = false
    satchel.drag.source_slot = nil
    satchel.drag.source_icon = nil
    satchel.drag.source_name = ''
end

local function copy_slot_ref(slot)
    if not slot then
        return nil
    end

    return {
        container_id = slot.container_id,
        slot_index = slot.slot_index,
        property_index = slot.property_index,
        id = slot.id,
        count = slot.count,
    }
end

local packet_to_bytes = packets.packet_to_bytes
local read_u16_le = packets.read_u16_le

local function is_mog_house_context()
    return satchel.in_mog_house == true
end

local function invalidate_slot_cache()
    satchel.slot_cache.checked_at = 0
    satchel.slot_cache.all_slots = nil
    satchel.slot_cache.slots_by_container = nil
    satchel.slot_cache.stats = nil
end

local function get_slot_data(force_refresh)
    local cache = satchel.slot_cache
    local now = os.clock()
    if not force_refresh and cache.stats and ((now - cache.checked_at) < SLOT_CACHE_TTL_SECONDS) then
        return cache.all_slots or {}, cache.slots_by_container or {}, cache.stats
    end

    local all_slots, slots_by_container, stats = containerlogic.build_slot_data(satchel)
    cache.checked_at = now
    cache.all_slots = all_slots
    cache.slots_by_container = slots_by_container
    cache.stats = stats

    return all_slots, slots_by_container, stats
end

local function can_drop_slot_to_container(slot, target_container_id, stats)
    if not slot or not slot.id or slot.id <= 0 then
        return false
    end

    local source_container = tonumber(slot.container_id)
    local target_container = tonumber(target_container_id)
    if source_container == nil or target_container == nil or source_container == target_container then
        return false
    end

    if mog_house_bags[source_container] and not is_mog_house_context() then
        return false
    end

    local target_stats = stats[target_container]
    local used = target_stats and (tonumber(target_stats.used) or 0) or 0
    local total = target_stats and (tonumber(target_stats.total) or 0) or 0
    if total <= 0 or used >= total then
        return false
    end

    local is_gear = items.is_gear_item(slot.id)

    if items.is_wardrobe_container(target_container) then
        return is_gear
    end

    if FIELD_BAGS[target_container] then
        return true
    end

    if is_mog_house_context() then
        return true
    end

    return false
end

local send_item_move_packet = packets.send_item_move_packet
local find_first_empty_slot_index = packets.find_first_empty_slot_index
local send_sort_packet = packets.send_sort_packet

function handle_sort_container(slot)
    local container_id = slot and tonumber(slot.container_id)
    if not container_id then
        return
    end

    if mog_house_bags[container_id] and not is_mog_house_context() then
        return
    end

    send_sort_packet(container_id)
    invalidate_slot_cache()
end

local function queue_commands(commands_to_run)
    if not commands_to_run or #commands_to_run == 0 then
        return
    end

    local chat_manager = AshitaCore:GetChatManager()

    for _, command in ipairs(commands_to_run) do
        if type(command) == 'table' and tonumber(command.packet_id) == 0x29 then
            send_item_move_packet(command)
        elseif type(command) == 'string' and chat_manager then
            chat_manager:QueueCommand(1, command)
        end
    end
end

local function handle_drop_to_container(target_container_id)
    if not satchel.drag.active or not satchel.drag.source_slot then
        return
    end

    local _, _, stats = get_slot_data(false)
    if not can_drop_slot_to_container(satchel.drag.source_slot, target_container_id, stats) then
        return
    end

    local target_slot_index = find_first_empty_slot_index(target_container_id)
    if not target_slot_index then
        return
    end

    local move_commands = items.build_move_commands(satchel.drag.source_slot, target_container_id, target_slot_index)
    if move_commands and #move_commands > 0 then
        queue_commands(move_commands)
    end

    clear_drag_state()
end

-- Double-click quick transfer: Inventory sends to Satchel; any other container
-- sends back to Inventory. can_drop_slot_to_container gates inaccessible moves.
local INVENTORY_CONTAINER = 0
local SATCHEL_CONTAINER = 5

local function handle_double_click_transfer(slot)
    if not slot or not slot.id or slot.id <= 0 then
        return
    end

    local source_container_id = tonumber(slot.container_id)
    if source_container_id == nil then
        return
    end

    local target_container_id = (source_container_id == INVENTORY_CONTAINER)
        and SATCHEL_CONTAINER or INVENTORY_CONTAINER
    if target_container_id == source_container_id then
        return
    end

    -- A click also starts a drag; cancel it so the transfer is the only action.
    clear_drag_state()

    local _, _, stats = get_slot_data(false)
    if not can_drop_slot_to_container(slot, target_container_id, stats) then
        return
    end

    local target_slot_index = find_first_empty_slot_index(target_container_id)
    if not target_slot_index then
        return
    end

    local move_commands = items.build_move_commands(slot, target_container_id, target_slot_index)
    if move_commands and #move_commands > 0 then
        queue_commands(move_commands)
    end
end

local function handle_title_bar_drag()
    if satchel.drag.active then
        satchel.window_drag.active = false
        return
    end

    local left_button = ImGuiMouseButton_Left
    local mouse_down = imgui.IsMouseDown(left_button)

    if satchel.window_drag.active then
        if not mouse_down then
            satchel.window_drag.active = false
            return
        end

        local io = imgui.GetIO()
        if io and io.MouseDelta then
            local mouse_delta = io.MouseDelta
            local delta_x = 0
            local delta_y = 0
            if type(mouse_delta) == 'table' or type(mouse_delta) == 'cdata' then
                local ok_x, val_x = pcall(function() return mouse_delta.x end)
                local ok_y, val_y = pcall(function() return mouse_delta.y end)
                if ok_x and val_x ~= nil then
                    delta_x = tonumber(val_x) or 0
                elseif type(mouse_delta) == 'table' then
                    delta_x = tonumber(mouse_delta[1]) or 0
                end
                if ok_y and val_y ~= nil then
                    delta_y = tonumber(val_y) or 0
                elseif type(mouse_delta) == 'table' then
                    delta_y = tonumber(mouse_delta[2]) or 0
                end
            end
            if delta_x ~= 0 or delta_y ~= 0 then
                local win_x, win_y = imgui.GetWindowPos()
                imgui.SetWindowPos('Satchel', { win_x + delta_x, win_y + delta_y })
            end
        end
        return
    end

    if not imgui.IsWindowHovered(WINDOW_HOVER_FLAGS) then
        return
    end

    local win_x, win_y = imgui.GetWindowPos()
    local mouse_x, mouse_y = imgui.GetMousePos()
    local title_height = (tonumber(imgui.GetFontSize()) or 14) + 12
    local in_title_bar = (mouse_x >= win_x) and (mouse_y >= win_y) and (mouse_y <= (win_y + title_height))
    if not in_title_bar then
        return
    end

    if imgui.IsMouseClicked(left_button) then
        satchel.window_drag.active = true
    end
end

local function render_drag_preview()
    if not satchel.drag.active then
        return
    end

    local label = satchel.drag.source_name or ''
    if label == '' and satchel.drag.source_slot and satchel.drag.source_slot.id then
        label = items.get_item_name(satchel.drag.source_slot.id)
    end

    imgui.BeginTooltip()
    if satchel.drag.source_icon then
        imgui.Image(icons.tex_ptr(satchel.drag.source_icon), { 28, 28 })
        imgui.SameLine(0, 6)
    end
    imgui.TextColored({ 0.97, 0.92, 0.72, 1.0 }, label ~= '' and label or 'Dragging item')
    imgui.EndTooltip()
end

local function render_left_tab_column(available_tabs, stats, scale)
    scale = scale or ui.get_global_scale()
    local drag_ctx = nil
    if not HzLimitedMode then
        drag_ctx = {
            is_dragging = satchel.drag.active,
            can_drop_to_container = function(container_id)
                if not satchel.drag.source_slot then
                    return false
                end
                return can_drop_slot_to_container(satchel.drag.source_slot, container_id, stats)
            end,
            on_drop_to_container = function(container_id)
                handle_drop_to_container(container_id)
            end,
            is_container_full = function(container_id)
                local s = stats[container_id]
                return s ~= nil and (s.total or 0) > 0 and (s.used or 0) >= s.total
            end,
        }
    end

    return ui.render_left_tab_column(available_tabs, satchel.active_tab, function(container_id)
        return containerlogic.format_tab_label(container_id)
    end, drag_ctx, scale)
end

local set_mog_house = mog.set_mog_house
local read_mog_state = mog.read_mog_state
local render_context_menu = menus.render

local function build_grid_context(include_gil, search_buffer)
    local grid_ctx = {
        settings = satchel.settings,
        default_slot_size = default_settings.slot_size,
        get_item_sort_key = items.get_item_sort_key,
        get_item_name = items.get_item_name,
        load_item_icon = function(item_id)
            return icons.load_item_icon(satchel, item_id)
        end,
        tex_ptr = icons.tex_ptr,
        get_slot_border_color = items.get_slot_border_color,
        render_item_detail_tooltip = items.render_item_detail_tooltip,
        item_matches_search = items.matches_search,
        search_query = search_buffer and search_buffer[1] or '',
        scale = ui.get_global_scale(),
        hide_gil = not include_gil,
        grid_opts = { show_all_rows = true },
    }

    if include_gil then
        grid_ctx.get_gil_amount = footer.get_player_gil_amount
        grid_ctx.format_gil_text = footer.format_gil_text
        grid_ctx.load_gil_icon = footer.load_gil_icon
    end

    if not HzLimitedMode then
        grid_ctx.on_slot_right_click = function(slot)
            if slot.read_only or slot.locked then
                return
            end
            satchel.context_menu.slot = copy_slot_ref(slot)
            satchel.context_menu.pending_open = true
        end
        grid_ctx.on_slot_double_click = function(slot)
            if slot.read_only or slot.locked then
                return
            end
            handle_double_click_transfer(copy_slot_ref(slot))
        end
        grid_ctx.on_slot_drag_start = function(slot, icon_texture)
            if slot.read_only or slot.locked or satchel.drag.active then
                return
            end

            if mog_house_bags[tonumber(slot.container_id)] and not is_mog_house_context() then
                return
            end

            satchel.drag.active = true
            satchel.drag.source_slot = copy_slot_ref(slot)
            satchel.drag.source_icon = icon_texture
            satchel.drag.source_name = items.get_item_name(slot.id) or ''
        end
    end

    return grid_ctx
end

local function apply_cached_gil_display(grid_ctx, gil_amount)
    if gil_amount == nil then
        return
    end

    grid_ctx.hide_gil = false
    grid_ctx.get_gil_amount = function()
        return gil_amount
    end
    grid_ctx.format_gil_text = footer.format_gil_text
    grid_ctx.load_gil_icon = footer.load_gil_icon
end

local function ensure_active_tab(active_tab, available_tabs)
    for _, container_id in ipairs(available_tabs) do
        if container_id == active_tab then
            return active_tab
        end
    end
    return available_tabs[1]
end

local function render_slot_grid(slots, key_prefix, stat, search_buffer)
    local grid_ctx = build_grid_context(true, search_buffer)
    ui.render_slot_grid(slots, key_prefix, stat, grid_ctx)
end

local function format_slip_button_label(slip_id)
    return ('%s##slip_pick_%d'):format(slipslogic.format_slip_label(slip_id), slip_id)
end

local function get_slip_picker_ids(alt_entry)
    if alt_entry then
        return slipslogic.get_cached_slip_ids(alt_entry.slips)
    end
    return slipslogic.get_owned_slip_ids()
end

local function clear_search_buffer(key)
    local buffer = satchel.search[key]
    if buffer then
        buffer[1] = ''
    end
end

local function clear_all_searches()
    clear_search_buffer('main')
    clear_search_buffer('slip')
    clear_search_buffer('alt')
end

local function close_all_satchel_windows()
    satchel.visible[1] = false
    satchel.last_visible = false
    satchel.settings.visible = false
    satchel.slips_picker.visible[1] = false
    satchel.slips_picker.alt_entry = nil
    satchel.slip_view.visible[1] = false
    satchel.slip_view.slip_id = nil
    satchel.slip_view.page = 0
    satchel.slip_view.alt_entry = nil
    satchel.alt_picker.visible[1] = false
    satchel.alt_view.visible[1] = false
    satchel.alt_view.entry = nil
    satchel.alt_view.active_tab = nil
    satchel.window_stack = {}
    clear_all_searches()
    clear_drag_state()
    satchel.window_drag.active = false
end

local function register_window_open(window_key)
    for i = #satchel.window_stack, 1, -1 do
        if satchel.window_stack[i] == window_key then
            table.remove(satchel.window_stack, i)
        end
    end
    satchel.window_stack[#satchel.window_stack + 1] = window_key
end

local function open_main_satchel()
    clear_search_buffer('main')
    satchel.visible[1] = true
    satchel.last_visible = true
    satchel.settings.visible = true
    register_window_open('main')
end

local function is_satchel_window_visible(window_key)
    if window_key == 'main' then
        return satchel.visible[1] == true
    elseif window_key == 'slips_picker' then
        return satchel.slips_picker.visible[1] == true
    elseif window_key == 'slip_view' then
        return satchel.slip_view.visible[1] == true
    elseif window_key == 'alt_picker' then
        return satchel.alt_picker.visible[1] == true
    elseif window_key == 'alt_view' then
        return satchel.alt_view.visible[1] == true
    end
    return false
end

local function any_satchel_window_visible()
    return is_satchel_window_visible('main')
        or is_satchel_window_visible('slips_picker')
        or is_satchel_window_visible('slip_view')
        or is_satchel_window_visible('alt_picker')
        or is_satchel_window_visible('alt_view')
end

local function toggle_satchel_command()
    if any_satchel_window_visible() then
        close_all_satchel_windows()
    else
        open_main_satchel()
    end
end

local function close_satchel_window(window_key)
    if window_key == 'main' then
        satchel.visible[1] = false
        satchel.last_visible = false
        satchel.settings.visible = false
        clear_search_buffer('main')
    elseif window_key == 'slips_picker' then
        satchel.slips_picker.visible[1] = false
        satchel.slips_picker.alt_entry = nil
    elseif window_key == 'slip_view' then
        satchel.slip_view.visible[1] = false
        satchel.slip_view.slip_id = nil
        satchel.slip_view.alt_entry = nil
        clear_search_buffer('slip')
    elseif window_key == 'alt_picker' then
        satchel.alt_picker.visible[1] = false
    elseif window_key == 'alt_view' then
        satchel.alt_view.visible[1] = false
        satchel.alt_view.entry = nil
        satchel.alt_view.active_tab = nil
        clear_search_buffer('alt')
    end
end

local function close_top_satchel_window()
    for i = #satchel.window_stack, 1, -1 do
        local window_key = satchel.window_stack[i]
        if is_satchel_window_visible(window_key) then
            close_satchel_window(window_key)
            table.remove(satchel.window_stack, i)
            return true
        end
        table.remove(satchel.window_stack, i)
    end

    if is_satchel_window_visible('main') then
        close_satchel_window('main')
        return true
    end

    return false
end

local function open_alt_picker()
    satchel.alt_picker.visible[1] = true
    register_window_open('alt_picker')
end

local function open_slips_picker(alt_entry)
    satchel.slips_picker.alt_entry = alt_entry
    satchel.slips_picker.visible[1] = true
    register_window_open('slips_picker')
end

local function open_slip_view(slip_id, alt_entry)
    clear_search_buffer('slip')
    satchel.slip_view.slip_id = slip_id
    satchel.slip_view.page = 0
    satchel.slip_view.alt_entry = alt_entry
    satchel.slip_view.visible[1] = true
    close_satchel_window('slips_picker')
    register_window_open('slip_view')
end

local function open_alt_view(entry)
    clear_search_buffer('alt')
    satchel.alt_view.entry = entry
    satchel.alt_view.active_tab = 0
    satchel.alt_view.visible[1] = true
    close_satchel_window('alt_picker')
    register_window_open('alt_view')
end

local function compute_content_window_size(available_tabs, slot_count, scale, toolbar_h, toolbar_opts)
    local metrics = ui.compute_grid_metrics(satchel.settings, slot_count, scale, { show_all_rows = true })
    local tab_width = ui.scaled(110, scale)
    local tab_button_h = ui.scaled(24, scale)
    local tab_gap = ui.scaled(2, scale)
    local tab_column_h = (#available_tabs * (tab_button_h + tab_gap))
    local toolbar_height = toolbar_h or ui.scaled(34, scale)
    local content_h = metrics.grid_height + ui.scaled(52, scale)
    local win_w = tab_width + ui.scaled(16, scale) + metrics.grid_width + ui.scaled(24, scale)
    local win_h = toolbar_height + math.max(tab_column_h, content_h) + ui.scaled(40, scale)

    toolbar_opts = toolbar_opts or {}
    if toolbar_opts.enabled then
        local gap = ui.scaled(8, scale)
        local buttons_w = 0
        if toolbar_opts.show_alt_button then
            buttons_w = buttons_w + ui.scaled(132, scale)
        end
        if toolbar_opts.show_slips_button then
            buttons_w = buttons_w + (buttons_w > 0 and gap or 0) + ui.scaled(128, scale)
        end
        local toolbar_min_w = buttons_w + (buttons_w > 0 and gap or 0) + ui.scaled(120, scale)
        win_w = math.max(win_w, toolbar_min_w + ui.scaled(24, scale))
    end

    return win_w, win_h, metrics, tab_width
end

local function compute_main_window_size(available_tabs, scale, show_slips_button)
    return compute_content_window_size(available_tabs, DISPLAY_SLOTS, scale, ui.scaled(34, scale), {
        enabled = true,
        show_alt_button = true,
        show_slips_button = show_slips_button == true,
    })
end

local function compute_picker_window_height(item_count, scale, extra)
    local button_h = ui.scaled(24, scale) + ui.scaled(2, scale)
    return ui.scaled(extra or 48, scale) + (item_count * button_h)
end

local function get_picker_window_height(item_count, scale)
    local full_h = compute_picker_window_height(math.max(1, item_count), scale, 48)
    return math.max(ui.scaled(140, scale), math.floor(full_h * 0.5))
end

local function draw_slips_picker_window(scale)
    if not satchel.slips_picker.visible[1] then
        return
    end

    local alt_entry = satchel.slips_picker.alt_entry
    local owned_slip_ids = get_slip_picker_ids(alt_entry)
    ui.push_config_window_style()
    local picker_w = ui.scaled(220, scale)
    local picker_h = get_picker_window_height(math.max(1, #owned_slip_ids), scale)
    imgui.SetNextWindowSize({ picker_w, picker_h }, ImGuiCond_Always)

    local title = alt_entry and ('Storage Slips: %s'):format(alt_entry.name or 'Alt') or 'Satchel Storage Slips'
    local began = imgui.Begin(title, satchel.slips_picker.visible, WINDOW_FLAGS)
    if began then
        ui.render_slip_picker(owned_slip_ids, function(slip_id)
            open_slip_view(slip_id, alt_entry)
        end, scale, format_slip_button_label)
    end
    imgui.End()

    if not satchel.slips_picker.visible[1] then
        satchel.slips_picker.alt_entry = nil
    end
    ui.pop_config_window_style()
end

local function draw_slip_content_window(scale)
    if not satchel.slip_view.visible[1] or not satchel.slip_view.slip_id then
        return
    end

    local slip_id = satchel.slip_view.slip_id
    local alt_entry = satchel.slip_view.alt_entry
    local stored_items = alt_entry
        and slipslogic.get_stored_items_from_cache(alt_entry.slips, slip_id)
        or slipslogic.get_stored_items(slip_id)
    local page_count = math.max(1, math.ceil(#stored_items / slipslogic.PAGE_SIZE))
    if satchel.slip_view.page >= page_count then
        satchel.slip_view.page = math.max(0, page_count - 1)
    end

    local slots, total_items = slipslogic.build_page_slots(stored_items, satchel.slip_view.page)
    local title = slipslogic.format_slip_label(slip_id)
    if alt_entry and alt_entry.name then
        title = ('%s - %s'):format(alt_entry.name, title)
    end
    local metrics = ui.compute_grid_metrics(satchel.settings, slipslogic.PAGE_SIZE, scale, { show_all_rows = true })
    local win_w = metrics.grid_width + ui.scaled(SLIP_WINDOW_PAD_X, scale)
    local win_h = metrics.grid_height + ui.scaled(SLIP_WINDOW_PAD_BOTTOM, scale)

    ui.push_config_window_style()
    imgui.SetNextWindowSize({ win_w, win_h }, ImGuiCond_Always)

    local began = imgui.Begin(title, satchel.slip_view.visible, WINDOW_FLAGS)
    if began then
        ui.render_toolbar_with_search(satchel.search.slip, scale, 'slip', {})
        imgui.Spacing()
        ui.render_centered_colored_text({ 0.78, 0.78, 0.78, 1.0 }, ('Stored: %d items'):format(total_items))
        ui.render_pagination_controls(satchel.slip_view.page, page_count, function(new_page)
            satchel.slip_view.page = math.max(0, math.min(page_count - 1, new_page))
        end, scale, { centered = true })
        imgui.Spacing()

        local grid_ctx = build_grid_context(false, satchel.search.slip)
        grid_ctx.read_only = true
        grid_ctx.centered = true
        ui.render_slot_grid(slots, ('slip_%d_%d'):format(slip_id, satchel.slip_view.page), {
            used = #stored_items,
            total = #stored_items,
        }, grid_ctx)
    end
    imgui.End()
    if not satchel.slip_view.visible[1] then
        satchel.slip_view.slip_id = nil
        satchel.slip_view.alt_entry = nil
        clear_search_buffer('slip')
    end
    ui.pop_config_window_style()
end

local function draw_alt_picker_window(scale)
    if not satchel.alt_picker.visible[1] then
        return
    end

    local entries = altcache.list_character_caches()
    ui.push_config_window_style()
    local picker_w = ui.scaled(220, scale)
    local picker_h = get_picker_window_height(math.max(1, #entries), scale)
    imgui.SetNextWindowSize({ picker_w, picker_h }, ImGuiCond_Always)

    local began = imgui.Begin('Satchel Alt Inventories', satchel.alt_picker.visible, WINDOW_FLAGS)
    if began then
        ui.render_alt_character_list(entries, function(entry)
            open_alt_view(entry)
        end, scale)
    end
    imgui.End()
    ui.pop_config_window_style()
end

local function get_alt_available_tabs(entry)
    local available_tabs = {}
    for _, container_id in ipairs(tab_order) do
        if container_id ~= 3 and not (container_id == 9 and HzLimitedMode) then
            if altcache.container_has_items(entry, container_id) then
                available_tabs[#available_tabs + 1] = container_id
            end
        end
    end
    return available_tabs
end

local function draw_auxiliary_windows(scale)
    draw_slips_picker_window(scale)
    draw_slip_content_window(scale)
    draw_alt_picker_window(scale)
    draw_alt_inventory_window(scale)
end

local function draw_alt_inventory_window(scale)
    if not satchel.alt_view.visible[1] or not satchel.alt_view.entry then
        return
    end

    local entry = satchel.alt_view.entry
    local available_tabs = get_alt_available_tabs(entry)

    if #available_tabs == 0 then
        ui.push_config_window_style()
        imgui.SetNextWindowSize({ ui.scaled(320, scale), ui.scaled(120, scale) }, ImGuiCond_Always)
        local title = ('Satchel: %s'):format(entry.name or 'Alt')
        local began = imgui.Begin(title, satchel.alt_view.visible, WINDOW_FLAGS)
        if began then
            imgui.TextColored({ 0.9, 0.72, 0.55, 1.0 }, 'No cached inventory data for this character.')
        end
        imgui.End()
        ui.pop_config_window_style()
        return
    end

    satchel.alt_view.active_tab = ensure_active_tab(satchel.alt_view.active_tab, available_tabs)

    local active_tab = satchel.alt_view.active_tab
    local active_slots = altcache.build_slots_from_cache(entry, active_tab)
    local used = 0
    for _, slot in ipairs(active_slots) do
        if slot.id and slot.id > 0 then
            used = used + 1
        end
    end

    local win_w, win_h, _, tab_width = compute_content_window_size(
        available_tabs,
        DISPLAY_SLOTS,
        scale,
        ui.scaled(40, scale),
        {
            enabled = true,
            show_alt_button = false,
            show_slips_button = slipslogic.has_cached_slips(entry.slips),
        }
    )

    ui.push_config_window_style()
    imgui.SetNextWindowSize({ win_w, win_h }, ImGuiCond_Always)

    local title = ('Satchel: %s'):format(entry.name or 'Alt')
    local began = imgui.Begin(title, satchel.alt_view.visible, WINDOW_FLAGS)
    if began then
        local toolbar_clicks = ui.render_toolbar_with_search(satchel.search.alt, scale, 'alt', {
            { id = 'slips', label = 'Storage Slips', visible = slipslogic.has_cached_slips(entry.slips) },
        })
        if toolbar_clicks.slips then
            open_slips_picker(entry)
        end
        imgui.Spacing()

        local top_x, top_y = imgui.GetCursorPos()

        imgui.BeginGroup()
        local current_tab = ui.render_left_tab_column(available_tabs, active_tab, function(container_id)
            return containerlogic.format_tab_label(container_id)
        end, nil, scale)
        imgui.EndGroup()

        if current_tab ~= satchel.alt_view.active_tab then
            satchel.alt_view.active_tab = current_tab
        end

        imgui.SameLine(0, ui.scaled(8, scale))
        imgui.SetCursorPos({ top_x + tab_width + ui.scaled(8, scale), top_y })
        imgui.BeginGroup()

        local grid_ctx = build_grid_context(false, satchel.search.alt)
        grid_ctx.read_only = true
        apply_cached_gil_display(grid_ctx, entry.gil)
        ui.render_slot_grid(active_slots, ('alt_%s_%d'):format(entry.key or 'alt', active_tab or 0), {
            used = used,
            total = DISPLAY_SLOTS,
        }, grid_ctx)
        imgui.EndGroup()
    end
    imgui.End()
    if not satchel.alt_view.visible[1] then
        satchel.alt_view.entry = nil
        satchel.alt_view.active_tab = nil
        clear_search_buffer('alt')
    end
    ui.pop_config_window_style()
end

function M.Initialize()
    if satchel.initialized then
        return
    end

    read_settings()
    close_all_satchel_windows()

    local in_game = (AshitaCore:GetMemoryManager():GetPlayer():GetLoginStatus() == 2)
    satchel.in_mog_house = in_game and read_mog_state() or false

    satchel.initialized = true
end

function M.UpdateVisuals()
    read_settings()
    invalidate_slot_cache()
end

function M.DrawWindow()
    if not satchel.initialized then
        return
    end

    if satchel.hidden then
        return
    end

    if is_module_enabled() then
        altcache.tick()
    end

    local scale = ui.get_global_scale()

    if not satchel.visible[1] then
        draw_auxiliary_windows(scale)
        return
    end

    if sync_display_settings() then
        invalidate_slot_cache()
    end
    local _, slots_by_container, stats = get_slot_data(false)

    local available_tabs = {}
    for _, container_id in ipairs(tab_order) do
        if containerlogic.is_tab_available(container_id, stats) then
            available_tabs[#available_tabs + 1] = container_id
        end
    end

    local show_slips_button = slipslogic.has_any_owned_slips()
    local win_w, win_h = compute_main_window_size(available_tabs, scale, show_slips_button)
    ui.push_config_window_style()
    imgui.SetNextWindowSize({ win_w, win_h }, ImGuiCond_Always)

    local began = imgui.Begin('Satchel', satchel.visible, WINDOW_FLAGS)
    if began then
        satchel.settings.visible = satchel.visible[1]

        local toolbar_clicks = ui.render_toolbar_with_search(satchel.search.main, scale, 'main', {
            { id = 'alt', label = 'Alt Inventories' },
            { id = 'slips', label = 'Storage Slips', visible = show_slips_button },
        })
        if toolbar_clicks.alt then
            open_alt_picker()
        end
        if toolbar_clicks.slips then
            open_slips_picker(nil)
        end
        imgui.Spacing()

        if #available_tabs == 0 then
            satchel.active_tab = nil
            imgui.TextColored({ 0.9, 0.72, 0.55, 1.0 }, 'No available inventory containers.')
        else
            local top_x, top_y = imgui.GetCursorPos()

            imgui.BeginGroup()
            local current_tab, tab_width = render_left_tab_column(available_tabs, stats, scale)
            imgui.EndGroup()

            if current_tab ~= satchel.active_tab then
                satchel.active_tab = current_tab
            end

            imgui.SameLine(0, ui.scaled(8, scale))
            imgui.SetCursorPos({ top_x + tab_width + ui.scaled(8, scale), top_y })
            imgui.BeginGroup()
            local active_slots = slots_by_container[satchel.active_tab] or {}
            local active_stats = stats[satchel.active_tab] or { used = 0, total = 0, display = DISPLAY_SLOTS }
            render_slot_grid(active_slots, tostring(satchel.active_tab or 0), active_stats, satchel.search.main)
            imgui.EndGroup()
        end

        if not HzLimitedMode then
            render_drag_preview()

            if satchel.drag.active and imgui.IsMouseReleased(ImGuiMouseButton_Left) then
                clear_drag_state()
            end

            render_context_menu()
        end
    end
    imgui.End()

    if not satchel.visible[1] then
        satchel.settings.visible = false
        clear_search_buffer('main')
    end
    satchel.last_visible = satchel.visible[1]

    ui.pop_config_window_style()

    draw_auxiliary_windows(scale)
end

function M.SetHidden(hidden)
    satchel.hidden = hidden == true
    if satchel.hidden then
        clear_drag_state()
        satchel.window_drag.active = false
    end
end

function M.Cleanup()
    close_all_satchel_windows()
    satchel.icons = {}
    satchel.file_icons = {}
    items.clear_caches()
    invalidate_slot_cache()
    altcache.invalidate()
    satchel.initialized = false
end

function M.ResetPositions()
    -- Position is managed by ImGui window state for the standalone-style satchel window.
end

--@cmd /satchel : Toggle the satchel window
function M.HandleCommand(e)
    local args = e.command:args()
    if #args == 0 or args[1]:lower() ~= '/satchel' then
        return false
    end

    -- Only hijack the global /satchel command when the user has opted in; otherwise
    -- leave it for the game/other addons. /xiui satchel always works regardless.
    if not (gConfig and gConfig.satchelOverrideCommand) then
        return false
    end

    e.blocked = true

    if not is_module_enabled() then
        print_disabled_message()
        return true
    end

    if #args == 1 then
        toggle_satchel_command()
        return true
    end

    show_help(true)
    return true
end

function M.HandleXiuiCommand(command_args)
    if #command_args < 2 or command_args[2] ~= 'satchel' then
        return false
    end

    if #command_args >= 3 and (command_args[3] or '') == 'config' then
        open_xiui_satchel_config()
        return true
    end

    if not is_module_enabled() then
        print_disabled_message()
        return true
    end

    if #command_args == 2 then
        toggle_satchel_command()
        return true
    end

    show_help(true)
    return true
end

function M.HandleKey(e)
    if satchel.hidden or not is_module_enabled() then
        return
    end

    if not any_satchel_window_visible() then
        return
    end

    -- Only intercept ESC when the user has opted in; otherwise ESC behaves normally.
    if not (gConfig and gConfig.satchelCloseOnEscape == true) then
        return
    end

    if e.wparam ~= 0x1B then
        return
    end

    local is_key_down = band(e.lparam, 0x80000000) == 0
    if not is_key_down then
        return
    end

    if close_top_satchel_window() then
        e.blocked = true
    end
end

function M.HandlePacketIn(e)
    if not is_module_enabled() then
        return
    end

    local id = tonumber(e.id)
    if id == 0x0A then
        local data = e.data_modified or e.data
        local ok, flag = pcall(struct.unpack, 'B', data, 0x80 + 1)
        if ok then set_mog_house(flag == 1) end
        close_all_satchel_windows()
        invalidate_slot_cache()
        altcache.invalidate()
    elseif id == 0x096 then
        set_mog_house(true)
        invalidate_slot_cache()
    elseif id == 0x097 then
        set_mog_house(false)
        invalidate_slot_cache()
    end
end

function M.HandlePacketOut(e)
    if not is_module_enabled() then
        return
    end

    if e.injected == true then
        return
    end

    local bytes = packet_to_bytes(e.data_modified or e.data)
    if #bytes >= 4 then
        satchel.packet_sync.value = read_u16_le(bytes, 0x02)
    end
end

return M
