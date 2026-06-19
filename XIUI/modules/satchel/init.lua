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

local M = {}

local band = bit.band
local bor = bit.bor

local WINDOW_COLORS = {
    { ImGuiCol_WindowBg, { 0.051, 0.051, 0.051, 0.95 } },
    { ImGuiCol_Border, { 0.3, 0.275, 0.235, 1.0 } },
    { ImGuiCol_TitleBg, { 0.098, 0.090, 0.075, 1.0 } },
    { ImGuiCol_TitleBgActive, { 0.137, 0.125, 0.106, 1.0 } },
}

local FIELD_BAGS = { [0] = true, [5] = true, [6] = true, [7] = true }
local WINDOW_HOVER_FLAGS = bor(ImGuiHoveredFlags_AllowWhenBlockedByPopup or 0, ImGuiHoveredFlags_AllowWhenBlockedByActiveItem or 0)
local WINDOW_BASE_FLAGS = bor(ImGuiWindowFlags_NoCollapse or 0, ImGuiWindowFlags_NoMove or 0)
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
}

local items = itemlogic.create({
    satchel = satchel,
    imgui = imgui,
})

local footer = footerlogic.create({
    satchel = satchel,
    icons = icons,
    gil_icon_path = addon.path .. '..\\satchel\\assets\\gil.png',
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

local menus = contextmenu.create({
    satchel = satchel,
    imgui = imgui,
    items = items,
    packets = packets,
})

local is_module_enabled = settings.is_module_enabled
local persist_settings = settings.persist_settings
local read_settings = settings.read_settings
local toggle_visible = settings.toggle_visible
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
            local delta_x = tonumber(io.MouseDelta.x) or 0
            local delta_y = tonumber(io.MouseDelta.y) or 0
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

local function render_left_tab_column(available_tabs, stats)
    return ui.render_left_tab_column(available_tabs, satchel.active_tab, function(container_id)
        return containerlogic.format_tab_label(container_id)
    end, {
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
    })
end

local set_mog_house = mog.set_mog_house
local read_mog_state = mog.read_mog_state
local render_context_menu = menus.render

local function render_slot_grid(slots, key_prefix, stat)
    ui.render_slot_grid(slots, key_prefix, stat, {
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
        on_slot_right_click = function(slot)
            satchel.context_menu.slot = copy_slot_ref(slot)
            satchel.context_menu.pending_open = true
        end,
        on_slot_drag_start = function(slot, icon_texture)
            if satchel.drag.active then
                return
            end

            if mog_house_bags[tonumber(slot.container_id)] and not is_mog_house_context() then
                return
            end

            satchel.drag.active = true
            satchel.drag.source_slot = copy_slot_ref(slot)
            satchel.drag.source_icon = icon_texture
            satchel.drag.source_name = items.get_item_name(slot.id) or ''
        end,
        get_gil_amount = footer.get_player_gil_amount,
        format_gil_text = footer.format_gil_text,
        load_gil_icon = footer.load_gil_icon,
    })
end

function M.Initialize()
    if satchel.initialized then
        return
    end

    read_settings()

    local login_status = AshitaCore:GetMemoryManager():GetPlayer():GetLoginStatus()
    local in_game = (login_status == 2)
    satchel.in_mog_house = in_game and read_mog_state() or false
    satchel.visible[1] = in_game and (satchel.settings.visible == true)
    satchel.last_visible = satchel.visible[1]

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

    if not satchel.visible[1] then
        return
    end

    local _, slots_by_container, stats = get_slot_data(false)

    for i = 1, #WINDOW_COLORS do
        imgui.PushStyleColor(WINDOW_COLORS[i][1], WINDOW_COLORS[i][2])
    end
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 6.0)
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 2.0)
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 4.0)
    imgui.PushStyleVar(ImGuiStyleVar_ChildRounding, 3.0)
    local pushed_style_vars = 4
    if ImGuiStyleVar_WindowTitleAlign ~= nil then
        imgui.PushStyleVar(ImGuiStyleVar_WindowTitleAlign, { 0.5, 0.5 })
        pushed_style_vars = pushed_style_vars + 1
    end

    local consume_resize = satchel.resize_on_next_frame == true
    local window_flags = WINDOW_BASE_FLAGS
    if consume_resize then
        window_flags = bor(window_flags, ImGuiWindowFlags_AlwaysAutoResize or 0)
    end
    satchel.resize_on_next_frame = false

    local began = imgui.Begin('Satchel', satchel.visible, window_flags)
    if began then
        handle_title_bar_drag()
        satchel.settings.visible = satchel.visible[1]

        local available_tabs = {}
        for _, container_id in ipairs(tab_order) do
            if containerlogic.is_tab_available(container_id, stats) then
                available_tabs[#available_tabs + 1] = container_id
            end
        end

        if #available_tabs == 0 then
            satchel.active_tab = nil
            imgui.TextColored({ 0.9, 0.72, 0.55, 1.0 }, 'No available inventory containers.')
        else
            local top_x, top_y = imgui.GetCursorPos()

            imgui.BeginGroup()
            local current_tab = render_left_tab_column(available_tabs, stats)
            imgui.EndGroup()

            if current_tab ~= satchel.active_tab then
                satchel.active_tab = current_tab
                satchel.resize_on_next_frame = true
            end

            imgui.SameLine(0, 8)
            imgui.SetCursorPos({ top_x + 118, top_y })
            imgui.BeginGroup()
            local active_slots = slots_by_container[satchel.active_tab] or {}
            local active_stats = stats[satchel.active_tab] or { used = 0, total = 0 }
            render_slot_grid(active_slots, tostring(satchel.active_tab or 0), active_stats)
            imgui.EndGroup()
        end

        render_drag_preview()

        if satchel.drag.active and imgui.IsMouseReleased(ImGuiMouseButton_Left) then
            clear_drag_state()
        end

        render_context_menu()
    end
    imgui.End()

    if satchel.visible[1] ~= satchel.last_visible then
        satchel.last_visible = satchel.visible[1]
        satchel.settings.visible = satchel.visible[1]
        persist_settings()
    end

    imgui.PopStyleVar(pushed_style_vars)
    imgui.PopStyleColor(4)
end

function M.SetHidden(hidden)
    satchel.hidden = hidden == true
    if satchel.hidden then
        clear_drag_state()
        satchel.window_drag.active = false
    end
end

function M.Cleanup()
    satchel.icons = {}
    satchel.file_icons = {}
    items.clear_caches()
    invalidate_slot_cache()
    satchel.initialized = false
end

function M.ResetPositions()
    -- Position is managed by ImGui window state for the standalone-style satchel window.
end

function M.HandleCommand(e)
    local args = e.command:args()
    if #args == 0 or args[1]:lower() ~= '/satchel' then
        return false
    end

    e.blocked = true

    if not is_module_enabled() then
        print_disabled_message()
        return true
    end

    if #args == 1 then
        toggle_visible()
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
        toggle_visible()
        return true
    end

    show_help(true)
    return true
end

function M.HandleKey(e)
    if satchel.hidden or not is_module_enabled() then
        return
    end

    if not satchel.visible[1] then
        return
    end

    if e.wparam ~= 0x1B then
        return
    end

    local is_key_down = band(e.lparam, 0x80000000) == 0
    if not is_key_down then
        return
    end

    local changed_visibility = false
    if satchel.visible[1] then
        satchel.visible[1] = false
        satchel.last_visible = false
        satchel.settings.visible = false
        changed_visibility = true
    end

    if changed_visibility then
        persist_settings()
    end
    e.blocked = true
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
        satchel.visible[1] = satchel.settings.visible == true
        satchel.last_visible = satchel.visible[1]
        invalidate_slot_cache()
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
