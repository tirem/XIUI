require('common')
local imgui = require('imgui')
local struct = require('struct')
local persistedWindow = require('libs.persisted_window')
local drawing = require('libs.drawing')

local ui = require('modules.satchel.ui')
local itemlogic = require('modules.satchel.itemlogic')
local containerlogic = require('modules.satchel.containerlogic')
local icons = require('modules.satchel.icons')
local TextureManager = require('libs.texturemanager')
local settingslogic = require('modules.satchel.settings')
local packetslogic = require('modules.satchel.packets')
local contextmenu = require('modules.satchel.contextmenu')
local slipslogic = require('modules.satchel.slipslogic')
local altcache = require('modules.satchel.altcache')
local layoutstate = require('modules.satchel.layoutstate')
local tooltips = require('modules.satchel.tooltips')
local satchelfonts = require('modules.satchel.satchelfontcore')
local searchlogic = require('modules.satchel.searchlogic')

local M = {}

local band = bit.band
local bor = bit.bor

local GIL_ICON_PATH = addon.path .. '..\\satchel\\assets\\gil.png'

local WINDOW_FLAGS = bor(
    ImGuiWindowFlags_NoResize or 0,
    ImGuiWindowFlags_NoSavedSettings or 0,
    ImGuiWindowFlags_NoDocking or 0
)
local INVENTORY_CONTAINER = 0
local FIELD_BAGS = { [0] = true, [5] = true, [6] = true, [7] = true }
local WINDOW_HOVER_FLAGS = bor(ImGuiHoveredFlags_AllowWhenBlockedByPopup or 0, ImGuiHoveredFlags_AllowWhenBlockedByActiveItem or 0)
local DISPLAY_SLOTS = containerlogic.DISPLAY_SLOTS
local SLOT_CACHE_TTL_SECONDS = 0.15

local function create_drag_bucket()
    return {
        active = false,
        source_slot = nil,
        source_icon = nil,
        source_name = '',
        source_border_color = nil,
        drop_handled = false,
        origin_tab = nil,
        origin_alt_tab = nil,
        origin_slip_page = nil,
        alt_entry_key = nil,
        slip_layout_key = nil,
        view_tab = nil,
        window_move_blocked = false,
    }
end

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
        main = create_drag_bucket(),
        alt = create_drag_bucket(),
        slip = create_drag_bucket(),
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
    container_used_counts = {},
    container_sorted = {},
    display_layouts = {},
    alt_display_layouts = {},
    slip_display_layouts = {},
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
        draft = { '' },
        alt = {}, -- [entry.key] = { draft = { '' } }
        input_focused = false,
        focus_seen = false,
        input_scope = 'shared', -- 'shared' or 'alt'
        input_alt_key = nil,
        -- Bumped when inventory changes so search match cache can refresh.
        match_inv_gen = 0,
        index = nil, -- rebuilt when query or match_inv_gen changes
    },
    window_stack = {},
}

local footer = {
    gil_cache = { value = nil, stamp = 0, ttl = 0.5 },
}

function footer.get_player_gil_amount()
    local now = os.clock()
    if footer.gil_cache.value ~= nil and (now - footer.gil_cache.stamp) < footer.gil_cache.ttl then
        return footer.gil_cache.value
    end

    local inv = AshitaCore:GetMemoryManager():GetInventory()
    if not inv then
        return footer.gil_cache.value
    end

    local ok, gil_item = pcall(function()
        return inv:GetContainerItem(0, 0)
    end)
    if not ok or not gil_item then
        return footer.gil_cache.value
    end

    footer.gil_cache.value = tonumber(gil_item.Count) or 0
    footer.gil_cache.stamp = now
    return footer.gil_cache.value
end

function footer.format_gil_text(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local sign, num = s:match('^([%-]?)(%d+)$')
    if not num then
        return s
    end

    local parts = {}
    while #num > 3 do
        table.insert(parts, 1, num:sub(-3))
        num = num:sub(1, -4)
    end
    if #num > 0 then
        table.insert(parts, 1, num)
    end

    return (sign or '') .. table.concat(parts, ',')
end

function footer.load_gil_icon()
    local tex = icons.load_file_icon(satchel, 'gil', GIL_ICON_PATH)
    if tex then
        return tex
    end
    return TextureManager.getFileTexture('gil')
end

function footer.get_gil_icon_ptr(texture)
    if not texture then
        return nil
    end
    return icons.tex_ptr(texture) or TextureManager.getTexturePtr(texture)
end

local items = itemlogic.create({
    satchel = satchel,
    imgui = imgui,
    addon_path = addon.path,
    format_gil_text = footer.format_gil_text,
    load_gil_icon = footer.load_gil_icon,
    get_gil_icon_ptr = footer.get_gil_icon_ptr,
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

local function get_mog_state_path()
    local root = string.format('%s\\config\\addons\\%s\\', AshitaCore:GetInstallPath(), addon.name)
    local mm = AshitaCore:GetMemoryManager()
    local party = mm and mm:GetParty()
    local entity = mm and mm:GetEntity()
    local index = party and party:GetMemberTargetIndex(0)
    local name = index and entity and entity:GetName(index)
    local server_id = index and entity and (tonumber(entity:GetServerId(index)) or 0) or 0
    if name and #name > 0 and server_id > 0 then
        return string.format('%s%s_%d\\satchel_mog_state.dat', root, name, server_id),
            string.format('%s%s_%d\\', root, name, server_id)
    end
    return root .. 'defaults\\satchel_mog_state.dat', root .. 'defaults\\'
end

local function read_mog_state()
    local path = get_mog_state_path()
    local f = io.open(path, 'r')
    if not f then
        return false
    end
    local v = f:read('*a')
    f:close()
    return v == '1'
end

local function set_mog_house(value)
    satchel.in_mog_house = value == true
    local path, dir = get_mog_state_path()
    ashita.fs.create_dir(dir)
    local f = io.open(path, 'w')
    if f then
        f:write(satchel.in_mog_house and '1' or '0')
        f:close()
    end
end

-- Forward-declared so the context menu's "Sort Bag" entry can reuse the same
-- cooldown/guard logic defined further down.
local handle_sort_container
local handle_alt_sort_container
local handle_slip_sort_container

local menus = contextmenu.create({
    satchel = satchel,
    imgui = imgui,
    items = items,
    packets = packets,
    on_sort = function(slot)
        if slot and slot.slip_view then
            handle_slip_sort_container(slot)
        elseif slot and slot.alt_view then
            handle_alt_sort_container(slot)
        else
            handle_sort_container(slot)
        end
    end,
})

local is_module_enabled = settings.is_module_enabled
local read_settings = settings.read_settings
local sync_display_settings = settings.sync_display_settings
local open_xiui_satchel_config = settings.open_xiui_satchel_config
local show_help = settings.show_help
local print_disabled_message = settings.print_disabled_message

local function is_horizon_mode()
    return HzLimitedMode == true
end

local function normalize_search_text(query)
    if type(query) ~= 'string' then
        return ''
    end
    return (query:match('^%s*(.-)%s*$') or '')
end

local function current_search_inv_gen()
    return satchel.search.match_inv_gen or 0
end

local function get_draft_search()
    local draft = satchel.search.draft
    return normalize_search_text(draft and draft[1])
end

local function clear_search()
    if satchel.search.draft then
        satchel.search.draft[1] = ''
    end
end

local function alt_search_key(entry_or_key)
    if type(entry_or_key) == 'table' then
        return tostring(entry_or_key.key or entry_or_key.name or 'alt')
    end
    return tostring(entry_or_key or 'alt')
end

local function get_alt_search_state(entry_or_key)
    local key = alt_search_key(entry_or_key)
    local by_alt = satchel.search.alt
    if not by_alt[key] then
        by_alt[key] = {
            draft = { '' },
        }
    end
    return by_alt[key], key
end

local function get_alt_draft_search(entry_or_key)
    local state = get_alt_search_state(entry_or_key)
    return normalize_search_text(state.draft and state.draft[1])
end

local function get_alt_draft_buffer(entry_or_key)
    local state = get_alt_search_state(entry_or_key)
    return state.draft
end

local function clear_alt_search(entry_or_key)
    local state = get_alt_search_state(entry_or_key)
    if state.draft then
        state.draft[1] = ''
    end
end

local function clear_all_alt_searches()
    satchel.search.alt = {}
end

-- Scan inventory once when the query or inventory generation changes; render only lookups.
local function ensure_index_on(holder, field, query, slots_by_container, slip_ids, slip_items_fn)
    local normalized = normalize_search_text(query)
    local inv_gen = current_search_inv_gen()
    local cached = holder[field]
    if cached and cached.query == normalized and cached.inv_gen == inv_gen then
        return cached
    end

    holder[field] = items.build_search_index(
        normalized,
        inv_gen,
        slots_by_container,
        slip_ids,
        slip_items_fn
    )
    return holder[field]
end

local function ensure_search_index(query, slots_by_container, slip_ids, slip_items_fn)
    return ensure_index_on(satchel.search, 'index', query, slots_by_container, slip_ids, slip_items_fn)
end

local function ensure_alt_search_index(alt_key, query, slots_by_container, slip_ids, slip_items_fn)
    return ensure_index_on(get_alt_search_state(alt_key), 'index', query, slots_by_container, slip_ids, slip_items_fn)
end

local function ensure_slip_page_search_index(query, slots)
    local normalized = normalize_search_text(query)
    local inv_gen = current_search_inv_gen()
    local view = satchel.slip_view
    local cached = view.search_index
    if cached
        and cached.query == normalized
        and cached.inv_gen == inv_gen
        and cached.page == view.page then
        return cached
    end

    view.search_index = items.build_search_index_for_slots(normalized, inv_gen, slots)
    view.search_index.page = view.page
    return view.search_index
end

local function note_search_input_focused(focused, scope, alt_key)
    if focused then
        satchel.search.focus_seen = true
        satchel.search.input_focused = true
        satchel.search.input_scope = scope or 'shared'
        satchel.search.input_alt_key = alt_key
    end
end

local function finish_search_focus_frame()
    if not satchel.search.focus_seen then
        satchel.search.input_focused = false
    end
    satchel.search.focus_seen = false
end

local function annotate_display_indices(slots)
    for display_index, slot in ipairs(slots or {}) do
        slot.display_index = display_index - 1
    end
    return slots
end

local function copy_slot_ref(slot)
    if not slot then
        return nil
    end

    return {
        container_id = slot.container_id,
        slot_index = slot.slot_index,
        property_index = slot.property_index,
        display_index = slot.display_index,
        id = slot.id,
        count = slot.count,
        read_only = slot.read_only,
        alt_view = slot.alt_view,
        slip_view = slot.slip_view,
        slip_layout_key = slot.slip_layout_key,
    }
end

local function visual_sort_can_drop_to_slot(drag_state, target_slot, active_container)
    if not drag_state or not drag_state.active or not drag_state.source_slot or not target_slot then
        return false
    end

    if target_slot.locked then
        return false
    end

    local source = drag_state.source_slot
    local source_container = tonumber(source.container_id)
    local target_container = tonumber(target_slot.container_id)
    active_container = tonumber(active_container)
    if source_container == nil or target_container == nil or active_container == nil then
        return false
    end

    if source_container ~= target_container or source_container ~= active_container then
        return false
    end

    if not source.id or source.id <= 0 then
        return false
    end

    local src_display = tonumber(source.display_index)
    local dst_display = tonumber(target_slot.display_index)
    if src_display ~= nil and dst_display ~= nil then
        return src_display ~= dst_display
    end

    return tonumber(source.slot_index) ~= tonumber(target_slot.slot_index)
end

local DRAG_SCOPE_MAIN = 'main'
local DRAG_SCOPE_ALT = 'alt'
local DRAG_SCOPE_SLIP = 'slip'

local finish_visual_drag_move

local function drag_bucket_for_scope(scope)
    return satchel.drag[scope]
end

local function any_drag_active()
    return satchel.drag.main.active or satchel.drag.alt.active or satchel.drag.slip.active
end

local function get_active_drag_scope()
    if satchel.drag.slip.active then
        return DRAG_SCOPE_SLIP
    end
    if satchel.drag.alt.active then
        return DRAG_SCOPE_ALT
    end
    if satchel.drag.main.active then
        return DRAG_SCOPE_MAIN
    end
    return nil
end

local function is_slot_drag_source(drag_state, slot)
    if not drag_state or not drag_state.source_slot or not slot then
        return false
    end

    -- Only the source bag's cell is the drag origin (same display index in
    -- another inventory must not light up as the source).
    if tonumber(drag_state.source_slot.container_id) ~= tonumber(slot.container_id) then
        return false
    end

    -- Pin dimming to the display cell where the drag started, not the item's
    -- memory index (preview swaps would otherwise mark the hover cell as source).
    local source_display = tonumber(drag_state.source_slot.display_index)
    local slot_display = tonumber(slot.display_index)
    if source_display ~= nil and slot_display ~= nil then
        return source_display == slot_display
    end

    return tonumber(drag_state.source_slot.slot_index) == tonumber(slot.slot_index)
end

local function configure_visual_drag_context(grid_ctx, scope, can_drop_fn)
    local drag_state = drag_bucket_for_scope(scope)
    grid_ctx.drag_scope = scope
    grid_ctx.drag_state = drag_state
    grid_ctx.is_dragging = function()
        return drag_state.active == true
    end
    grid_ctx.is_drag_source = function(slot)
        if not drag_state.active then
            return false
        end
        return is_slot_drag_source(drag_state, slot)
    end
    grid_ctx.can_drop_to_slot = function(target_slot)
        if not drag_state.active then
            return false
        end
        return can_drop_fn(drag_state, target_slot)
    end
end

local function clear_drag_bucket(drag_state, scope)
    local revert_tab = drag_state.origin_tab
    local revert_alt_tab = drag_state.origin_alt_tab
    local revert_slip_page = drag_state.origin_slip_page

    drag_state.active = false
    drag_state.source_slot = nil
    drag_state.source_icon = nil
    drag_state.source_name = ''
    drag_state.drop_handled = false
    drag_state.source_border_color = nil
    drag_state.origin_tab = nil
    drag_state.alt_entry_key = nil
    drag_state.origin_alt_tab = nil
    drag_state.slip_layout_key = nil
    drag_state.origin_slip_page = nil
    drag_state.view_tab = nil
    drag_state.window_move_blocked = false

    if scope == DRAG_SCOPE_MAIN and revert_tab ~= nil then
        satchel.active_tab = revert_tab
    elseif scope == DRAG_SCOPE_ALT and revert_alt_tab ~= nil then
        satchel.alt_view.active_tab = revert_alt_tab
    elseif scope == DRAG_SCOPE_SLIP and revert_slip_page ~= nil then
        satchel.slip_view.page = revert_slip_page
    end
end

local function clear_drag_state(scope)
    if scope then
        clear_drag_bucket(drag_bucket_for_scope(scope), scope)
        ui.clear_pending_drag(scope)
        return
    end

    clear_drag_bucket(satchel.drag.main, DRAG_SCOPE_MAIN)
    clear_drag_bucket(satchel.drag.alt, DRAG_SCOPE_ALT)
    clear_drag_bucket(satchel.drag.slip, DRAG_SCOPE_SLIP)
    ui.clear_pending_drag()
end

local function sync_chrome_fonts(scale)
    satchelfonts.sync(scale)
end

-- startup=true: load-event only (may AddFontFromFileTTF).
-- startup=false: present-safe; never mutates the font atlas.
local function sync_all_satchel_fonts(scale, startup)
    if startup then
        satchelfonts.prewarm_startup()
        tooltips.prewarm_startup()
    end
    sync_chrome_fonts(scale)
end

local function begin_chrome_font(scale)
    return satchelfonts.push_chrome_font(scale)
end

local function end_chrome_font(pushed)
    if pushed then
        satchelfonts.pop_chrome_font()
    end
end

local function get_display_tab()
    local drag_state = satchel.drag.main
    if drag_state.active and drag_state.view_tab ~= nil then
        return drag_state.view_tab
    end
    return satchel.active_tab
end

local packet_to_bytes = packets.packet_to_bytes
local read_u16_le = packets.read_u16_le

local function is_mog_house_context()
    return satchel.in_mog_house == true
end

local function can_actually_modify_container(container_id)
    container_id = tonumber(container_id)
    if container_id == nil then
        return false
    end
    if mog_house_bags[container_id] and not is_mog_house_context() then
        return false
    end
    return true
end

local function invalidate_slot_cache()
    satchel.slot_cache.checked_at = 0
    satchel.slot_cache.all_slots = nil
    satchel.slot_cache.slots_by_container = nil
    satchel.slot_cache.stats = nil
    satchel.search.match_inv_gen = (satchel.search.match_inv_gen or 0) + 1
end

-- Force any cached search index to rebuild without discarding slot data. Used
-- when the item-name index finishes building so partial profile-search results
-- get re-resolved against the complete index.
local function bump_search_generation()
    satchel.search.match_inv_gen = (satchel.search.match_inv_gen or 0) + 1
end

-- Equipping/unequipping through the game (or another addon) doesn't move items
-- between bags, so nothing else bumps the inv generation. Poll the 16 equipped
-- slots and bump on change so the equipped-item lookup and slot borders refresh.
-- Compares against a reused array (no per-frame allocations); only called while a
-- satchel window is open, and self-heals changes made while closed on reopen.
local last_equipped = {}
local function poll_equipment_changes()
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    if not inv then
        return
    end

    local changed = false
    for equip_slot = 0, 15 do
        local equipped = inv:GetEquippedItem(equip_slot)
        local index = (equipped and equipped.Index) or 0
        if last_equipped[equip_slot] ~= index then
            last_equipped[equip_slot] = index
            changed = true
        end
    end

    if changed then
        bump_search_generation()
    end
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

    -- Equipped gear and bazaar-listed items cannot leave their bag.
    if items.is_slot_currently_equipped(slot) or items.is_slot_in_bazaar(slot) then
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

    if mog_house_bags[target_container] and not is_mog_house_context() then
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

    layoutstate.mark_container_sorted(container_id, satchel.container_sorted)
    local _, slots_by_container = get_slot_data(false)
    layoutstate.reset_container_layout(container_id, slots_by_container[container_id], satchel.display_layouts)

    -- Non-Horizon: also ask the server to merge/stack items in this bag.
    if not is_horizon_mode() then
        send_sort_packet(container_id)
    end

    invalidate_slot_cache()
end

-- Cache the sorted display order per source slots-table identity. build_slot_data
-- allocates fresh slots tables on every slot_cache rebuild, so a weak-keyed cache
-- self-invalidates and never needs manual clearing.
local sort_cache = setmetatable({}, { __mode = 'k' })

local function sort_key_for(item_id)
    return items.get_item_sort_key(item_id)
end

local function sort_name_for(item_id)
    return items.get_item_name(item_id) or ''
end

local function sort_slots_visually(slots)
    if slots == nil then
        return annotate_display_indices({})
    end
    local sorted = sort_cache[slots]
    if not sorted then
        sorted = containerlogic.sort_slots_for_display(slots, sort_key_for, sort_name_for)
        sort_cache[slots] = sorted
    end
    -- Re-annotate cheaply each frame so display_index stays correct even if the
    -- shared slot refs were annotated by another view in between.
    return annotate_display_indices(sorted)
end

local function resolve_visual_slots(layout_key, container, raw_slots, layouts_map)
    if layoutstate.is_auto_sort_enabled() then
        return sort_slots_visually(raw_slots)
    end
    if layoutstate.has_custom_alt_layout(layout_key, container, raw_slots, layouts_map) then
        return annotate_display_indices(
            layoutstate.build_alt_display_slots(layout_key, container, raw_slots, layouts_map)
        )
    end
    return annotate_display_indices(raw_slots)
end

local function get_alt_visual_slots(entry, container_id)
    local raw_slots = altcache.build_slots_from_cache(entry, container_id)
    return resolve_visual_slots(entry.key, container_id, raw_slots, satchel.alt_display_layouts)
end

local function sync_view_sorted(layout_key, container, raw_slots, layouts_map, variant)
    local sorted_slots = sort_slots_visually(raw_slots)
    layoutstate.sync_alt_map_from_visual_slots(layout_key, container, sorted_slots, layouts_map, variant)
end

function handle_alt_sort_container(slot)
    local entry = satchel.alt_view.entry
    local container_id = slot and tonumber(slot.container_id)
    if not entry or not container_id then
        return
    end

    local raw_slots = altcache.build_slots_from_cache(entry, container_id)
    sync_view_sorted(entry.key, container_id, raw_slots, satchel.alt_display_layouts)
end

-- get_visual is a thunk: the visual order is only built when the layout map has
-- to be seeded (no custom layout yet), avoiding the cost on the common path.
local function commit_alt_visual_move(layout_key, container, raw_slots, layouts_map, get_visual, src_display, dst_display, variant, scope)
    if not layoutstate.has_custom_alt_layout(layout_key, container, raw_slots, layouts_map) then
        layoutstate.sync_alt_map_from_visual_slots(layout_key, container, get_visual(), layouts_map, variant)
    end
    if layoutstate.apply_alt_display_move(layout_key, container, raw_slots, layouts_map, src_display, dst_display, variant) then
        finish_visual_drag_move(scope)
    end
end

local function handle_alt_visual_drop(entry, source, target_slot)
    if layoutstate.is_auto_sort_enabled() then
        return
    end

    local source_container = tonumber(source.container_id)
    local target_container = tonumber(target_slot.container_id)
    if not entry or source_container == nil or target_container == nil or source_container ~= target_container then
        return
    end

    if source_container ~= tonumber(satchel.alt_view.active_tab) then
        return
    end

    local src_display = tonumber(source.display_index)
    local dst_display = tonumber(target_slot.display_index)
    if src_display == nil or dst_display == nil or src_display == dst_display then
        return
    end

    local raw_slots = altcache.build_slots_from_cache(entry, source_container)
    commit_alt_visual_move(
        entry.key, source_container, raw_slots, satchel.alt_display_layouts,
        function() return get_alt_visual_slots(entry, source_container) end,
        src_display, dst_display, nil, DRAG_SCOPE_ALT
    )
end

local function queue_commands(commands_to_run)
    if is_horizon_mode() then
        return
    end

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

-- Non-Horizon auto-sort: send native 0x3A when auto-sort turns on or a bag's
-- used count changes, so the server merges stacks. Horizon is visual-only.
local function tick_auto_sort_server(stats)
    if is_horizon_mode() or not layoutstate.is_auto_sort_enabled() then
        satchel.auto_sort_server_sent = nil
        return
    end

    satchel.auto_sort_server_sent = satchel.auto_sort_server_sent or {}
    stats = stats or {}

    for container_id, container_stats in pairs(stats) do
        container_id = tonumber(container_id)
        if container_id ~= nil then
            local used_count = tonumber(container_stats.used) or 0
            local previous_used = satchel.container_used_counts[container_id]
            local contents_changed = previous_used ~= nil and used_count ~= previous_used
            local not_yet_sent = satchel.auto_sort_server_sent[container_id] ~= true

            if not_yet_sent or contents_changed then
                send_sort_packet(container_id)
                satchel.auto_sort_server_sent[container_id] = true
            end

            satchel.container_used_counts[container_id] = used_count
        end
    end
end

local function get_visual_slots_for_container(container_id, slots, stats)
    layoutstate.ensure_sort_loaded(satchel.container_sorted)

    local container_stats = stats and stats[container_id] or {}
    local used_count = tonumber(container_stats.used) or 0
    container_id = tonumber(container_id)
    if container_id == nil then
        return slots or {}
    end

    local previous_used = satchel.container_used_counts[container_id]
    -- Server auto-sort tick owns used-count updates on non-Horizon; keep a
    -- local copy here for the manual-sort "new item clears sorted" path.
    if is_horizon_mode() or not layoutstate.is_auto_sort_enabled() then
        satchel.container_used_counts[container_id] = used_count
    end

    local auto_sort = layoutstate.is_auto_sort_enabled()

    if not auto_sort
        and previous_used ~= nil
        and used_count > previous_used then
        layoutstate.clear_container_sorted(container_id, satchel.container_sorted)
    end

    -- Auto Sort: live sorted display only. Keep any custom layout so turning
    -- auto-sort off restores the previous arrangement. Server-side stacking is
    -- handled by tick_auto_sort_server.
    if auto_sort then
        return sort_slots_visually(slots)
    end

    if layoutstate.should_visually_sort(container_id, satchel.container_sorted)
        and not layoutstate.has_custom_layout(container_id, slots, satchel.display_layouts) then
        return sort_slots_visually(slots)
    end

    if layoutstate.uses_manual_layout(container_id, satchel.container_sorted)
        or layoutstate.has_custom_layout(container_id, slots, satchel.display_layouts) then
        return annotate_display_indices(
            layoutstate.build_display_slots(container_id, slots, satchel.display_layouts)
        )
    end

    return annotate_display_indices(slots or {})
end

local function ensure_manual_container_layout(container_id, raw_slots, stats)
    if not layoutstate.uses_manual_layout(container_id, satchel.container_sorted) then
        return false
    end

    if not layoutstate.has_custom_layout(container_id, raw_slots, satchel.display_layouts) then
        local visual_slots = get_visual_slots_for_container(container_id, raw_slots, stats)
        layoutstate.sync_map_from_visual_slots(container_id, visual_slots, satchel.display_layouts)
        layoutstate.clear_container_sorted(container_id, satchel.container_sorted)
    end

    return true
end

local function apply_cross_container_visual_placement(target_container_id, target_display_index, raw_slots, stats)
    if not ensure_manual_container_layout(target_container_id, raw_slots, stats) then
        return
    end

    local target_mem = layoutstate.find_first_empty_memory_index(raw_slots)
    if target_mem == nil then
        return
    end

    local dst_display = tonumber(target_display_index)
    if dst_display == nil then
        dst_display = layoutstate.find_first_empty_display_index(
            target_container_id,
            raw_slots,
            satchel.display_layouts
        )
    end
    if dst_display == nil then
        return
    end

    layoutstate.place_memory_at_display(
        target_container_id,
        raw_slots,
        satchel.display_layouts,
        target_mem,
        dst_display
    )
end

local function restore_drag_origin_tab()
    local drag_state = satchel.drag.main
    if drag_state.origin_tab ~= nil then
        satchel.active_tab = drag_state.origin_tab
    end
end

local function finish_drag_move(commands)
    if commands and #commands > 0 then
        queue_commands(commands)
        invalidate_slot_cache()
        satchel.drag.main.drop_handled = true
        restore_drag_origin_tab()
    end
    clear_drag_state()
end

finish_visual_drag_move = function(scope)
    invalidate_slot_cache()
    local drag_state = drag_bucket_for_scope(scope)
    drag_state.drop_handled = true
    clear_drag_state(scope)
end

local function handle_main_visual_drop(source, target_slot)
    local source_container = tonumber(source.container_id)
    local target_container = tonumber(target_slot.container_id)
    if source_container == nil or target_container == nil or source_container ~= target_container then
        return
    end

    if source_container ~= tonumber(satchel.active_tab) then
        return
    end

    local src_display = tonumber(source.display_index)
    local dst_display = tonumber(target_slot.display_index)
    if src_display == nil or dst_display == nil or src_display == dst_display then
        return
    end

    local _, slots_by_container, stats = get_slot_data(false)
    local raw_slots = slots_by_container[source_container] or {}
    if not layoutstate.has_custom_layout(source_container, raw_slots, satchel.display_layouts) then
        local visual_slots = get_visual_slots_for_container(source_container, raw_slots, stats)
        layoutstate.sync_map_from_visual_slots(source_container, visual_slots, satchel.display_layouts)
        layoutstate.clear_container_sorted(source_container, satchel.container_sorted)
    end

    if layoutstate.apply_display_move(
        source_container,
        raw_slots,
        satchel.display_layouts,
        src_display,
        dst_display
    ) then
        finish_visual_drag_move(DRAG_SCOPE_MAIN)
    end
end

local function get_slip_layout_key(slip_id, alt_entry)
    local alt_part = alt_entry and tostring(alt_entry.key) or 'player'
    return ('slip_%s_%d'):format(alt_part, tonumber(slip_id) or 0)
end

local function get_slip_stored_items(slip_id, alt_entry)
    if alt_entry then
        return slipslogic.get_stored_items_from_cache(alt_entry.slips, slip_id)
    end
    return slipslogic.get_stored_items(slip_id)
end

local function get_slip_raw_slots(stored_items, page)
    local slots, _ = slipslogic.build_page_slots(stored_items, page)
    local slip_key = get_slip_layout_key(satchel.slip_view.slip_id, satchel.slip_view.alt_entry)
    for index, slot in ipairs(slots) do
        slot.slip_view = true
        slot.slip_layout_key = slip_key
        slot.container_id = page
        slot.slot_index = index - 1
        slot.property_index = index - 1
    end
    return slots
end

local function get_slip_visual_slots(stored_items, page)
    local slip_key = get_slip_layout_key(satchel.slip_view.slip_id, satchel.slip_view.alt_entry)
    local raw_slots = get_slip_raw_slots(stored_items, page)
    return resolve_visual_slots(slip_key, page, raw_slots, satchel.slip_display_layouts)
end

function handle_slip_sort_container(slot)
    local slip_id = satchel.slip_view.slip_id
    local page = slot and tonumber(slot.container_id)
    if not slip_id or page == nil then
        return
    end

    local alt_entry = satchel.slip_view.alt_entry
    local stored_items = get_slip_stored_items(slip_id, alt_entry)
    local raw_slots = get_slip_raw_slots(stored_items, page)
    sync_view_sorted(get_slip_layout_key(slip_id, alt_entry), page, raw_slots, satchel.slip_display_layouts, 'slip')
end

local function handle_slip_visual_drop(source, target_slot)
    if layoutstate.is_auto_sort_enabled() then
        return
    end

    local slip_id = satchel.slip_view.slip_id
    local page = satchel.slip_view.page
    if not slip_id or page == nil then
        return
    end

    local source_page = tonumber(source.container_id)
    local target_page = tonumber(target_slot.container_id)
    if source_page == nil or target_page == nil or source_page ~= target_page or source_page ~= page then
        return
    end

    local src_display = tonumber(source.display_index)
    local dst_display = tonumber(target_slot.display_index)
    if src_display == nil or dst_display == nil or src_display == dst_display then
        return
    end

    local alt_entry = satchel.slip_view.alt_entry
    local stored_items = get_slip_stored_items(slip_id, alt_entry)
    local raw_slots = get_slip_raw_slots(stored_items, page)
    commit_alt_visual_move(
        get_slip_layout_key(slip_id, alt_entry), page, raw_slots, satchel.slip_display_layouts,
        function() return get_slip_visual_slots(stored_items, page) end,
        src_display, dst_display, 'slip', DRAG_SCOPE_SLIP
    )
end

local function handle_drop_to_container(target_container_id)
    local drag_state = satchel.drag.main
    if not drag_state.active or not drag_state.source_slot then
        return
    end

    local _, slots_by_container, stats = get_slot_data(false)
    if not can_drop_slot_to_container(drag_state.source_slot, target_container_id, stats) then
        return
    end

    local target_slot_index = find_first_empty_slot_index(target_container_id)
    if not target_slot_index then
        return
    end

    local raw_slots = slots_by_container[target_container_id] or {}
    apply_cross_container_visual_placement(target_container_id, nil, raw_slots, stats)

    local move_commands = items.build_move_commands(
        drag_state.source_slot, target_container_id, target_slot_index)
    finish_drag_move(move_commands)
end

local function handle_drop_to_slot(scope, target_slot)
    local drag_state = drag_bucket_for_scope(scope)
    if not drag_state.active or not drag_state.source_slot or not target_slot then
        return
    end

    if target_slot.locked then
        return
    end

    local source = drag_state.source_slot

    -- Alt / slip: always visual-only within the same container/page.
    if scope == DRAG_SCOPE_SLIP and satchel.slip_view.slip_id then
        if visual_sort_can_drop_to_slot(drag_state, target_slot, satchel.slip_view.page) then
            handle_slip_visual_drop(source, target_slot)
        end
        return
    end

    if scope == DRAG_SCOPE_ALT and satchel.alt_view.entry then
        if visual_sort_can_drop_to_slot(drag_state, target_slot, satchel.alt_view.active_tab) then
            handle_alt_visual_drop(satchel.alt_view.entry, source, target_slot)
        end
        return
    end

    if scope ~= DRAG_SCOPE_MAIN then
        return
    end

    -- Horizon: visual-only within the active bag.
    if is_horizon_mode() then
        if visual_sort_can_drop_to_slot(drag_state, target_slot, satchel.active_tab) then
            handle_main_visual_drop(source, target_slot)
        end
        return
    end

    -- Non-Horizon: real item moves (and visual layout within a manual bag).
    if not items.can_drop_drag_to_slot(source, target_slot, function(target_container)
        local _, _, stats = get_slot_data(false)
        return can_drop_slot_to_container(source, target_container, stats)
    end) then
        return
    end

    local source_container = tonumber(source.container_id)
    local target_container = tonumber(target_slot.container_id)
    if source_container == nil or target_container == nil then
        return
    end

    if source_container == target_container
        and layoutstate.uses_manual_layout(source_container, satchel.container_sorted) then
        if items.can_stack_slots(source, target_slot) then
            if not can_actually_modify_container(source_container) then
                return
            end
            local target_index = items.resolve_drop_target_index(source, target_slot)
            if not target_index then
                return
            end
            local move_commands = items.build_slot_move_commands(source, target_container, target_index, true)
            finish_drag_move(move_commands)
            return
        end

        local src_display = tonumber(source.display_index)
        local dst_display = tonumber(target_slot.display_index)
        if src_display == nil or dst_display == nil or src_display == dst_display then
            return
        end

        local _, slots_by_container = get_slot_data(false)
        local raw_slots = slots_by_container[source_container] or {}
        if not layoutstate.has_custom_layout(source_container, raw_slots, satchel.display_layouts) then
            local _, _, stats = get_slot_data(false)
            local visual_slots = get_visual_slots_for_container(source_container, raw_slots, stats)
            layoutstate.sync_map_from_visual_slots(source_container, visual_slots, satchel.display_layouts)
            layoutstate.clear_container_sorted(source_container, satchel.container_sorted)
        end

        if layoutstate.apply_display_move(
            source_container,
            raw_slots,
            satchel.display_layouts,
            src_display,
            dst_display
        ) then
            finish_visual_drag_move(DRAG_SCOPE_MAIN)
        end
        return
    end

    if not can_actually_modify_container(source_container)
        or not can_actually_modify_container(target_container) then
        return
    end

    local target_index = items.resolve_drop_target_index(source, target_slot)
    if not target_index then
        return
    end

    local target_occupied = target_slot.id and target_slot.id > 0
    if source_container ~= target_container and not target_occupied then
        local _, slots_by_container, stats = get_slot_data(false)
        local raw_slots = slots_by_container[target_container] or {}
        apply_cross_container_visual_placement(
            target_container,
            tonumber(target_slot.display_index),
            raw_slots,
            stats
        )
    end

    local move_commands
    if source_container == target_container then
        move_commands = items.build_slot_move_commands(source, target_container, target_index, true)
    else
        move_commands = items.build_slot_move_commands(source, target_container, target_index, false)
    end

    finish_drag_move(move_commands)
end

local SATCHEL_CONTAINER = 5

local function handle_double_click_transfer(slot)
    if is_horizon_mode() then
        return
    end

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

    clear_drag_state(DRAG_SCOPE_MAIN)

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
        invalidate_slot_cache()
    end
end

local function resolve_default_active_tab(display_tabs)
    if tab_is_available(INVENTORY_CONTAINER, display_tabs) then
        return INVENTORY_CONTAINER
    end
    return display_tabs[1]
end

local function get_window_flags_for_scope(scope)
    local drag_state = drag_bucket_for_scope(scope)
    if drag_state.active
        or ui.should_block_satchel_window_move(scope)
        or drag_state.window_move_blocked then
        return bor(WINDOW_FLAGS, ImGuiWindowFlags_NoMove)
    end
    return WINDOW_FLAGS
end

local function get_satchel_window_flags()
    return get_window_flags_for_scope(DRAG_SCOPE_MAIN)
end

local function render_drag_preview()
    local active_scope = get_active_drag_scope()
    if not active_scope then
        return
    end

    ui.render_drag_ghost(
        drag_bucket_for_scope(active_scope),
        icons.tex_ptr,
        ui.scaled(satchel.settings.slot_size or default_settings.slot_size, ui.get_global_scale())
    )
end

local function finalize_drag_frame()
    render_drag_preview()

    for _, scope in ipairs({ DRAG_SCOPE_MAIN, DRAG_SCOPE_ALT, DRAG_SCOPE_SLIP }) do
        local drag_state = drag_bucket_for_scope(scope)
        if drag_state.active then
            if imgui.IsMouseReleased(0) and not drag_state.drop_handled then
                clear_drag_state(scope)
            end
        else
            drag_state.drop_handled = false
        end
    end
end

local render_context_menu = menus.render

local function assign_gil_renderers(grid_ctx)
    grid_ctx.format_gil_text = footer.format_gil_text
    grid_ctx.load_gil_icon = footer.load_gil_icon
    grid_ctx.get_gil_icon_ptr = footer.get_gil_icon_ptr
end

local function open_slot_context_menu(slot)
    if slot.locked then
        return
    end
    satchel.context_menu.slot = copy_slot_ref(slot)
    satchel.context_menu.pending_open = true
end

local function drag_blocked_for_slot(drag_state, slot)
    return slot.locked or (any_drag_active() and not drag_state.active) or not slot.id or slot.id <= 0
end

local function populate_drag_source(drag_state, slot, icon_texture)
    drag_state.active = true
    drag_state.source_slot = copy_slot_ref(slot)
    drag_state.source_icon = icon_texture
    drag_state.source_name = items.get_item_name(slot.id) or ''
    drag_state.source_border_color = items.get_slot_border_color(slot)
end

local function build_grid_context(include_gil, search_index)
    search_index = search_index or satchel.search.index
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
        get_slot_border_u32 = items.get_slot_border_color_u32,
        get_empty_border_u32 = items.get_empty_slot_border_u32,
        prepare_slot_render = items.ensure_equipped_lookup,
        render_item_detail_tooltip = items.render_item_detail_tooltip,
        item_matches_search = function(slot, _)
            return items.index_matches_slot(search_index, slot)
        end,
        search_query = (search_index and search_index.query) or '',
        search_active = search_index ~= nil and search_index.query ~= '',
        search_index = search_index,
        scale = ui.get_global_scale(),
        hide_gil = not include_gil,
    }

    if include_gil then
        grid_ctx.get_gil_amount = footer.get_player_gil_amount
        assign_gil_renderers(grid_ctx)
    end

    configure_visual_drag_context(grid_ctx, DRAG_SCOPE_MAIN, function(drag_state, target_slot)
        if target_slot.alt_view or target_slot.slip_view then
            return false
        end

        if is_horizon_mode() then
            return visual_sort_can_drop_to_slot(drag_state, target_slot, satchel.active_tab)
        end

        if not drag_state.active or not drag_state.source_slot then
            return false
        end

        local source = drag_state.source_slot
        if not items.can_drop_drag_to_slot(source, target_slot, function(target_container)
            local _, _, stats = get_slot_data(false)
            return can_drop_slot_to_container(source, target_container, stats)
        end) then
            return false
        end

        local source_container = tonumber(source.container_id)
        local target_container = tonumber(target_slot.container_id)
        if source_container == nil or target_container == nil then
            return false
        end

        if source_container == target_container
            and layoutstate.uses_manual_layout(source_container, satchel.container_sorted)
            and not items.can_stack_slots(source, target_slot) then
            return true
        end

        return can_actually_modify_container(source_container)
            and can_actually_modify_container(target_container)
    end)
    grid_ctx.on_drop_to_slot = function(target_slot)
        handle_drop_to_slot(DRAG_SCOPE_MAIN, target_slot)
    end
    grid_ctx.on_slot_right_click = open_slot_context_menu
    grid_ctx.on_slot_double_click = function(slot)
        if is_horizon_mode() or slot.read_only or slot.locked then
            return
        end
        handle_double_click_transfer(copy_slot_ref(slot))
    end
    grid_ctx.on_slot_drag_start = function(slot, icon_texture)
        local drag_state = satchel.drag.main
        if drag_blocked_for_slot(drag_state, slot) then
            return
        end

        if is_horizon_mode() then
            local slot_container = tonumber(slot.container_id)
            local active_container = tonumber(satchel.active_tab)
            if slot_container == nil or active_container == nil or slot_container ~= active_container then
                return
            end
        end

        populate_drag_source(drag_state, slot, icon_texture)
        local live_index = items.resolve_move_source_index(slot)
        if live_index then
            drag_state.source_slot.property_index = live_index
        end
        drag_state.origin_tab = satchel.active_tab
        drag_state.view_tab = satchel.active_tab
    end

    return grid_ctx
end

local function build_readonly_grid_context(search_index, scope, can_drop, on_drag_start)
    local grid_ctx = build_grid_context(false, search_index)
    grid_ctx.read_only = true
    grid_ctx.visual_sort_only = true
    configure_visual_drag_context(grid_ctx, scope, can_drop)
    grid_ctx.on_drop_to_slot = function(target_slot)
        handle_drop_to_slot(scope, target_slot)
    end
    grid_ctx.on_slot_right_click = open_slot_context_menu
    grid_ctx.on_slot_double_click = function(_slot) end
    grid_ctx.on_slot_drag_start = on_drag_start
    return grid_ctx
end

local function build_slip_grid_context(search_index)
    return build_readonly_grid_context(search_index, DRAG_SCOPE_SLIP,
        function(drag_state, target_slot)
            if target_slot.slip_view ~= true then
                return false
            end
            if drag_state.slip_layout_key
                and target_slot.slip_layout_key ~= drag_state.slip_layout_key then
                return false
            end
            return visual_sort_can_drop_to_slot(drag_state, target_slot, satchel.slip_view.page)
        end,
        function(slot, icon_texture)
            local drag_state = satchel.drag.slip
            if drag_blocked_for_slot(drag_state, slot) then
                return
            end

            local slot_page = tonumber(slot.container_id)
            local active_page = tonumber(satchel.slip_view.page)
            if slot_page == nil or active_page == nil or slot_page ~= active_page then
                return
            end

            populate_drag_source(drag_state, slot, icon_texture)
            drag_state.slip_layout_key = slot.slip_layout_key
            drag_state.origin_slip_page = satchel.slip_view.page
        end)
end

local function build_alt_grid_context(entry, search_index)
    return build_readonly_grid_context(search_index, DRAG_SCOPE_ALT,
        function(drag_state, target_slot)
            if target_slot.alt_view ~= true then
                return false
            end
            return visual_sort_can_drop_to_slot(drag_state, target_slot, satchel.alt_view.active_tab)
        end,
        function(slot, icon_texture)
            local drag_state = satchel.drag.alt
            if drag_blocked_for_slot(drag_state, slot) then
                return
            end

            local slot_container = tonumber(slot.container_id)
            local active_container = tonumber(satchel.alt_view.active_tab)
            if slot_container == nil or active_container == nil or slot_container ~= active_container then
                return
            end

            populate_drag_source(drag_state, slot, icon_texture)
            drag_state.alt_entry_key = entry and entry.key or nil
            drag_state.origin_alt_tab = satchel.alt_view.active_tab
        end)
end

local function apply_cached_gil_display(grid_ctx, gil_amount)
    if gil_amount == nil then
        return
    end

    grid_ctx.hide_gil = false
    grid_ctx.get_gil_amount = function()
        return gil_amount
    end
    assign_gil_renderers(grid_ctx)
end

local function ensure_active_tab(active_tab, available_tabs)
    for _, container_id in ipairs(available_tabs) do
        if container_id == active_tab then
            return active_tab
        end
    end
    return available_tabs[1]
end

local function render_slot_grid(slots, key_prefix, stat)
    local grid_ctx = build_grid_context(true, satchel.search.index)
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
    clear_search()
    clear_all_alt_searches()
    clear_drag_state()
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
    clear_search()
    satchel.active_tab = INVENTORY_CONTAINER
    satchel.visible[1] = true
    satchel.last_visible = true
    satchel.settings.visible = true
    register_window_open('main')
end

-- Per-window spec routed by key; the dispatchers below replace parallel if-chains.
local WINDOW_DESCRIPTORS = {
    main = {
        is_visible = function() return satchel.visible[1] == true end,
        uses_shared_search = true,
        close = function()
            satchel.visible[1] = false
            satchel.last_visible = false
            satchel.settings.visible = false
            clear_search()
        end,
    },
    slips_picker = {
        is_visible = function() return satchel.slips_picker.visible[1] == true end,
        get_alt_entry = function() return satchel.slips_picker.alt_entry end,
        uses_shared_search = true,
        close = function()
            satchel.slips_picker.visible[1] = false
            satchel.slips_picker.alt_entry = nil
        end,
    },
    slip_view = {
        is_visible = function() return satchel.slip_view.visible[1] == true end,
        get_alt_entry = function() return satchel.slip_view.alt_entry end,
        uses_shared_search = true,
        close = function()
            satchel.slip_view.visible[1] = false
            satchel.slip_view.slip_id = nil
            satchel.slip_view.alt_entry = nil
        end,
    },
    alt_picker = {
        is_visible = function() return satchel.alt_picker.visible[1] == true end,
        close = function()
            satchel.alt_picker.visible[1] = false
        end,
    },
    alt_view = {
        is_visible = function() return satchel.alt_view.visible[1] == true end,
        get_alt_entry = function() return satchel.alt_view.entry end,
        close = function()
            if satchel.alt_view.entry then
                clear_alt_search(satchel.alt_view.entry)
            end
            satchel.alt_view.visible[1] = false
            satchel.alt_view.entry = nil
            satchel.alt_view.active_tab = nil
        end,
    },
}

local WINDOW_KEYS = { 'main', 'slips_picker', 'slip_view', 'alt_picker', 'alt_view' }

local function is_satchel_window_visible(window_key)
    local descriptor = WINDOW_DESCRIPTORS[window_key]
    return descriptor ~= nil and descriptor.is_visible()
end

local function alt_entry_for_window(window_key)
    local descriptor = WINDOW_DESCRIPTORS[window_key]
    if descriptor and descriptor.get_alt_entry then
        return descriptor.get_alt_entry()
    end
    return nil
end

-- Clears search for a scope. Returns true when text was cleared.
local function search_has_text(scope, alt_key)
    if scope == 'alt' and alt_key then
        return get_alt_draft_search(alt_key) ~= ''
    end
    return get_draft_search() ~= ''
end

local function clear_search_for(scope, alt_key)
    if scope == 'alt' and alt_key then
        clear_alt_search(alt_key)
    else
        clear_search()
    end
end

-- Clears search for the topmost visible window that has draft text.
-- Returns true when ESC should be consumed without closing a window.
local function clear_search_for_window(window_key)
    local alt_entry = alt_entry_for_window(window_key)
    if alt_entry then
        local alt_key = alt_search_key(alt_entry)
        if search_has_text('alt', alt_key) then
            clear_search_for('alt', alt_key)
            return true
        end
        return false
    end

    local descriptor = WINDOW_DESCRIPTORS[window_key]
    if descriptor and descriptor.uses_shared_search and search_has_text('shared') then
        clear_search_for('shared')
        return true
    end

    return false
end

local function try_clear_search()
    for i = #satchel.window_stack, 1, -1 do
        local window_key = satchel.window_stack[i]
        if is_satchel_window_visible(window_key) then
            return clear_search_for_window(window_key)
        end
        table.remove(satchel.window_stack, i)
    end

    if is_satchel_window_visible('main') and search_has_text('shared') then
        clear_search_for('shared')
        return true
    end

    return false
end

local function any_satchel_window_visible()
    for _, window_key in ipairs(WINDOW_KEYS) do
        if WINDOW_DESCRIPTORS[window_key].is_visible() then
            return true
        end
    end
    return false
end

local function toggle_satchel_command()
    if any_satchel_window_visible() then
        close_all_satchel_windows()
    else
        open_main_satchel()
    end
end

local function close_satchel_window(window_key)
    local descriptor = WINDOW_DESCRIPTORS[window_key]
    if descriptor then
        descriptor.close()
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
    satchel.slip_view.slip_id = slip_id
    satchel.slip_view.page = 0
    satchel.slip_view.alt_entry = alt_entry
    satchel.slip_view.visible[1] = true
    close_satchel_window('slips_picker')
    register_window_open('slip_view')
end

local function open_alt_view(entry)
    satchel.alt_view.entry = entry
    satchel.alt_view.active_tab = 0
    satchel.alt_view.visible[1] = true
    close_satchel_window('alt_picker')
    register_window_open('alt_view')
end

local function get_content_region_layout(scale, tab_count)
    local metrics = ui.compute_grid_metrics(satchel.settings, DISPLAY_SLOTS, scale, { layout_size = true })
    local needs_tab_sb = ui.tab_sidebar_needs_scrollbar(tab_count, metrics.grid_height, scale)
    local sidebar_width = ui.get_tab_sidebar_width(scale, needs_tab_sb)
    local sidebar_gap = ui.scaled(8, scale)
    return {
        metrics = metrics,
        sidebar_width = sidebar_width,
        sidebar_gap = sidebar_gap,
        grid_h = metrics.grid_height,
        grid_block_width = metrics.grid_width + metrics.scrollbar_w,
        toolbar_align_width = ui.get_toolbar_grid_align_width(metrics, scale, tab_count, metrics.grid_height),
    }
end

local function compute_inventory_window_size(scale, toolbar_opts, tab_count)
    local layout = get_content_region_layout(scale, tab_count)
    local footer_h = ui.get_footer_row_height(scale)
    local toolbar_height = ui.scaled(34, scale)
    local spacing_h = ui.scaled(8, scale)
    local chrome_h = ui.get_title_bar_height(scale) + ui.scaled(16, scale)
    -- Extra width so right-edge slot search highlight is not clipped.
    local pad_x = ui.scaled(24, scale) + ui.scaled(4, scale)
    local win_w = layout.sidebar_width + layout.sidebar_gap + layout.grid_block_width + pad_x
    local win_h = chrome_h + toolbar_height + spacing_h + layout.grid_h + footer_h

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
        win_w = math.max(win_w, toolbar_min_w + pad_x)
    end

    return win_w, win_h, layout
end

local function compute_main_window_size(scale, show_slips_button, tab_count)
    return compute_inventory_window_size(scale, {
        enabled = true,
        show_alt_button = true,
        show_slips_button = show_slips_button == true,
    }, tab_count)
end

local function compute_alt_window_size(scale, show_slips_button, tab_count)
    return compute_inventory_window_size(scale, {
        enabled = true,
        show_alt_button = false,
        show_slips_button = show_slips_button == true,
    }, tab_count)
end

local TEMPORARY_CONTAINER = 3

local function has_temporary_items(stats)
    local temporary_stats = stats and stats[TEMPORARY_CONTAINER]
    return temporary_stats ~= nil and (temporary_stats.used or 0) > 0
end

local function build_display_tabs(stats)
    local display_tabs = {}
    if has_temporary_items(stats) then
        display_tabs[#display_tabs + 1] = TEMPORARY_CONTAINER
    end
    for _, container_id in ipairs(tab_order) do
        if container_id ~= TEMPORARY_CONTAINER and containerlogic.is_tab_available(container_id, stats) then
            display_tabs[#display_tabs + 1] = container_id
        end
    end
    return display_tabs
end

local function tab_is_available(container_id, available_tabs)
    for _, tab_id in ipairs(available_tabs) do
        if tab_id == container_id then
            return true
        end
    end
    return false
end

local PICKER_MIN_VISIBLE_ROWS = 8

local function compute_picker_window_height(item_count, scale, extra)
    local button_h = ui.scaled(24, scale) + ui.scaled(2, scale)
    return ui.scaled(extra or 48, scale) + (item_count * button_h)
end

local function get_picker_window_height(item_count, scale)
    local row_count = math.max(PICKER_MIN_VISIBLE_ROWS, math.max(1, item_count))
    return compute_picker_window_height(row_count, scale, 48)
end

local function draw_slips_picker_window(scale)
    if not satchel.slips_picker.visible[1] then
        return
    end

    local alt_entry = satchel.slips_picker.alt_entry
    local owned_slip_ids = get_slip_picker_ids(alt_entry)
    local chrome_query = alt_entry and get_alt_draft_search(alt_entry) or get_draft_search()
    local search_index = alt_entry
        and ensure_alt_search_index(
            alt_search_key(alt_entry),
            chrome_query,
            nil,
            owned_slip_ids,
            function(slip_id)
                return slipslogic.get_stored_items_from_cache(alt_entry.slips, slip_id)
            end
        )
        or ensure_search_index(
            chrome_query,
            nil,
            owned_slip_ids,
            function(slip_id)
                return slipslogic.get_stored_items(slip_id)
            end
        )
    ui.push_config_window_style()
    local picker_w = ui.scaled(220, scale)
    local picker_h = get_picker_window_height(math.max(1, #owned_slip_ids), scale)
    ui.set_window_size(picker_w, picker_h)

    local title = alt_entry and ('Storage Slips: %s'):format(alt_entry.name or 'Alt') or 'Satchel Storage Slips'
    local began = imgui.Begin(title, satchel.slips_picker.visible, WINDOW_FLAGS)
    if began then
        local chrome_pushed = begin_chrome_font(scale)
        ui.render_slip_picker(
            owned_slip_ids,
            function(slip_id)
                open_slip_view(slip_id, alt_entry)
            end,
            scale,
            format_slip_button_label,
            search_index.slips,
            chrome_query ~= '',
            any_drag_active()
        )
        end_chrome_font(chrome_pushed)
    end
    imgui.End()

    if not satchel.slips_picker.visible[1] then
        satchel.slips_picker.alt_entry = nil
    end
    ui.pop_config_window_style()
end

local function compute_slip_window_size(scale)
    local metrics = ui.compute_grid_metrics(satchel.settings, slipslogic.PAGE_SIZE, scale, { layout_size = true })
    local toolbar_h = ui.scaled(34, scale)
    local spacing_h = ui.scaled(8, scale)
    local footer_h = ui.get_footer_row_height(scale)
    local pad_x = ui.scaled(24, scale)
    local chrome_h = ui.get_title_bar_height(scale) + ui.scaled(16, scale)
    -- Slight extra width so right-edge search highlight is not clipped.
    local win_w = metrics.grid_width + metrics.scrollbar_w + (pad_x * 2) + ui.scaled(4, scale)
    local win_h = chrome_h + toolbar_h + spacing_h + metrics.grid_height + footer_h
    return win_w, win_h, metrics, footer_h
end

local function draw_slip_content_window(scale)
    if not satchel.slip_view.visible[1] or not satchel.slip_view.slip_id then
        return
    end

    local slip_id = satchel.slip_view.slip_id
    local alt_entry = satchel.slip_view.alt_entry
    local stored_items = get_slip_stored_items(slip_id, alt_entry)
    local page_count = math.max(1, math.ceil(#stored_items / slipslogic.PAGE_SIZE))
    if satchel.slip_view.page >= page_count then
        satchel.slip_view.page = math.max(0, page_count - 1)
    end

    local page = satchel.slip_view.page
    local slots = get_slip_visual_slots(stored_items, page)
    local title = slipslogic.format_slip_label(slip_id)
    if alt_entry and alt_entry.name then
        title = ('%s - %s'):format(alt_entry.name, title)
    end
    local win_w, win_h, metrics, footer_h = compute_slip_window_size(scale)

    ui.push_config_window_style()
    ui.set_window_size(win_w, win_h)

    local began = imgui.Begin(title, satchel.slip_view.visible, bor(
        get_window_flags_for_scope(DRAG_SCOPE_SLIP),
        ImGuiWindowFlags_NoScrollbar or 0
    ))
    if began then
        local chrome_pushed = begin_chrome_font(scale)
        local alt_key = alt_entry and alt_search_key(alt_entry) or nil
        local active_search = alt_key and get_alt_draft_search(alt_key) or get_draft_search()
        local draft_buffer = alt_key and get_alt_draft_buffer(alt_key) or satchel.search.draft
        local _, slip_search_focused = ui.render_toolbar_with_search(
            draft_buffer,
            scale,
            alt_key and ('slip_alt_%s'):format(alt_key) or 'slip',
            {},
            {
                align_width = metrics.grid_width + metrics.scrollbar_w,
                centered = true,
                search_active = active_search ~= '',
            }
        )
        if alt_key then
            note_search_input_focused(slip_search_focused, 'alt', alt_key)
        else
            note_search_input_focused(slip_search_focused, 'shared')
        end
        active_search = alt_key and get_alt_draft_search(alt_key) or get_draft_search()
        imgui.Spacing()

        ui.begin_child('##satchel_slip_body', { 0, metrics.grid_height }, false, ui.NO_SCROLL_CHILD_FLAGS)
        local slip_search_index = ensure_slip_page_search_index(active_search, slots)
        local grid_ctx = build_slip_grid_context(slip_search_index)
        grid_ctx.centered = true
        grid_ctx.grid_slot_count = slipslogic.PAGE_SIZE
        ui.render_slot_grid(slots, ('slip_%d_%d'):format(slip_id, satchel.slip_view.page), {
            used = #stored_items,
            total = #stored_items,
        }, grid_ctx)
        satchel.drag.slip.window_move_blocked = ui.should_block_satchel_window_move(DRAG_SCOPE_SLIP)
        ui.end_child()

        ui.render_slip_window_footer(#stored_items, satchel.slip_view.page, page_count, function(new_page)
            satchel.slip_view.page = math.max(0, math.min(page_count - 1, new_page))
        end, scale, {
            grid_width = metrics.grid_width + metrics.scrollbar_w,
        })
        render_context_menu()
        end_chrome_font(chrome_pushed)
    end
    imgui.End()
    if not satchel.slip_view.visible[1] then
        satchel.slip_view.slip_id = nil
        satchel.slip_view.alt_entry = nil
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
    ui.set_window_size(picker_w, picker_h)

    local began = imgui.Begin('Satchel Alt Inventories', satchel.alt_picker.visible, WINDOW_FLAGS)
    if began then
        local chrome_pushed = begin_chrome_font(scale)
        ui.render_alt_character_list(entries, function(entry)
            open_alt_view(entry)
        end, scale)
        end_chrome_font(chrome_pushed)
    end
    imgui.End()
    ui.pop_config_window_style()
end

local function get_alt_available_tabs(entry)
    local available_tabs = {}
    for _, container_id in ipairs(tab_order) do
        if container_id ~= 3 then
            if altcache.container_has_items(entry, container_id) then
                available_tabs[#available_tabs + 1] = container_id
            end
        end
    end
    return available_tabs
end

local function draw_alt_inventory_window(scale)
    if not satchel.alt_view.visible[1] or not satchel.alt_view.entry then
        return
    end

    local entry = satchel.alt_view.entry
    local available_tabs = get_alt_available_tabs(entry)

    if #available_tabs == 0 then
        ui.push_config_window_style()
        local empty_w = ui.scaled(320, scale)
        local empty_h = ui.scaled(120, scale)
        ui.set_window_size(empty_w, empty_h)
        local title = ('Satchel: %s'):format(entry.name or 'Alt')
        local began = imgui.Begin(title, satchel.alt_view.visible, WINDOW_FLAGS)
        if began then
            local chrome_pushed = begin_chrome_font(scale)
            imgui.TextColored({ 0.9, 0.72, 0.55, 1.0 }, 'No cached inventory data for this character.')
            end_chrome_font(chrome_pushed)
        end
        imgui.End()
        ui.pop_config_window_style()
        return
    end

    satchel.alt_view.active_tab = ensure_active_tab(satchel.alt_view.active_tab, available_tabs)

    local active_tab = satchel.alt_view.active_tab
    local active_slots = get_alt_visual_slots(entry, active_tab)
    local used = 0
    for _, slot in ipairs(active_slots) do
        if slot.id and slot.id > 0 then
            used = used + 1
        end
    end

    local win_w, win_h, layout = compute_alt_window_size(
        scale,
        slipslogic.has_cached_slips(entry.slips),
        #available_tabs
    )

    local alt_slots_by_container = {}
    for _, container_id in ipairs(available_tabs) do
        alt_slots_by_container[container_id] = get_alt_visual_slots(entry, container_id)
    end
    local alt_slip_ids = slipslogic.has_cached_slips(entry.slips) and get_slip_picker_ids(entry) or {}

    ui.push_config_window_style()
    ui.set_window_size(win_w, win_h)

    local title = ('Satchel: %s'):format(entry.name or 'Alt')
    local began = imgui.Begin(title, satchel.alt_view.visible, get_window_flags_for_scope(DRAG_SCOPE_ALT))
    if began then
        local chrome_pushed = begin_chrome_font(scale)
        local alt_key = alt_search_key(entry)
        local alt_search = get_alt_draft_search(alt_key)
        local alt_search_index = ensure_alt_search_index(
            alt_key,
            alt_search,
            alt_slots_by_container,
            alt_slip_ids,
            function(slip_id)
                return slipslogic.get_stored_items_from_cache(entry.slips, slip_id)
            end
        )
        local alt_match_containers = alt_search_index.containers
        local alt_has_slip_matches = items.index_has_slip_matches(alt_search_index)
        local toolbar_clicks, alt_search_focused = ui.render_toolbar_with_search(
            get_alt_draft_buffer(alt_key),
            scale,
            ('alt_%s'):format(alt_key),
            {
                { id = 'slips', label = 'Storage Slips', visible = slipslogic.has_cached_slips(entry.slips) },
            },
            {
                align_width = layout.toolbar_align_width,
                search_active = alt_search ~= '',
                is_dragging = satchel.drag.alt.active == true,
                highlight_button_ids = alt_search ~= '' and {
                    slips = alt_has_slip_matches,
                } or nil,
            }
        )
        note_search_input_focused(alt_search_focused, 'alt', alt_key)
        alt_search = get_alt_draft_search(alt_key)
        alt_search_index = ensure_alt_search_index(
            alt_key,
            alt_search,
            alt_slots_by_container,
            alt_slip_ids,
            function(slip_id)
                return slipslogic.get_stored_items_from_cache(entry.slips, slip_id)
            end
        )
        alt_match_containers = alt_search_index.containers
        alt_has_slip_matches = items.index_has_slip_matches(alt_search_index)
        if toolbar_clicks.slips then
            open_slips_picker(entry)
        end
        imgui.Spacing()

        local sidebar_width = layout.sidebar_width
        local sidebar_gap = layout.sidebar_gap
        local grid_h = layout.grid_h
        local grid_ctx = build_alt_grid_context(entry, alt_search_index)
        apply_cached_gil_display(grid_ctx, entry.gil)

        ui.begin_child('##satchel_alt_body', { 0, grid_h }, false, ui.NO_SCROLL_CHILD_FLAGS)
        local current_tab = ui.render_scrollable_tab_sidebar(
            '##satchel_alt_tabs',
            sidebar_width,
            grid_h,
            available_tabs,
            active_tab,
            function(container_id)
                return containerlogic.format_tab_label(container_id)
            end,
            {
                search_active = alt_search ~= '',
                search_match_containers = alt_match_containers,
            },
            scale
        )

        if current_tab ~= nil and current_tab ~= satchel.alt_view.active_tab then
            satchel.alt_view.active_tab = current_tab
            active_tab = current_tab
            active_slots = get_alt_visual_slots(entry, active_tab)
            used = 0
            for _, slot in ipairs(active_slots) do
                if slot.id and slot.id > 0 then
                    used = used + 1
                end
            end
        end

        imgui.SameLine(0, sidebar_gap)
        ui.begin_child('##satchel_alt_grid', { 0, grid_h }, false, ui.NO_SCROLL_CHILD_FLAGS)
        ui.render_slot_grid(active_slots, ('alt_%s_%d'):format(entry.key or 'alt', active_tab or 0), {
            used = used,
            total = DISPLAY_SLOTS,
        }, grid_ctx)
        satchel.drag.alt.window_move_blocked = ui.should_block_satchel_window_move(DRAG_SCOPE_ALT)
        ui.end_child()
        ui.end_child()

        ui.render_inventory_footer({
            used = used,
            total = DISPLAY_SLOTS,
        }, grid_ctx, {
            scale = scale,
            sidebar_width = sidebar_width,
            gap = sidebar_gap,
            grid_block_width = layout.grid_block_width,
        })

        render_context_menu()
        end_chrome_font(chrome_pushed)
    end
    imgui.End()
    if not satchel.alt_view.visible[1] then
        if satchel.alt_view.entry then
            clear_alt_search(satchel.alt_view.entry)
        end
        satchel.alt_view.entry = nil
        satchel.alt_view.active_tab = nil
    end
    ui.pop_config_window_style()
end

local function draw_auxiliary_windows(scale)
    draw_slips_picker_window(scale)
    draw_slip_content_window(scale)
    draw_alt_picker_window(scale)
    draw_alt_inventory_window(scale)
end

function M.Initialize()
    if satchel.initialized then
        return
    end

    read_settings()
    layoutstate.reload_sort_from_config(satchel.container_sorted)
    layoutstate.reload_from_config(satchel.display_layouts)
    layoutstate.reload_alt_from_config(satchel.alt_display_layouts)
    layoutstate.reload_slip_from_config(satchel.slip_display_layouts)
    close_all_satchel_windows()

    local in_game = (AshitaCore:GetMemoryManager():GetPlayer():GetLoginStatus() == 2)
    satchel.in_mog_house = in_game and read_mog_state() or false

    tooltips.preload_assets(satchel, addon.path)
    satchelfonts.capture_chrome_base_px()
    sync_all_satchel_fonts(ui.get_global_scale(), true)

    satchel.initialized = true
end

function M.UpdateVisuals()
    read_settings()
    layoutstate.reload_sort_from_config(satchel.container_sorted)
    layoutstate.reload_from_config(satchel.display_layouts)
    layoutstate.reload_alt_from_config(satchel.alt_display_layouts)
    layoutstate.reload_slip_from_config(satchel.slip_display_layouts)
    sync_all_satchel_fonts(ui.get_global_scale(), false)
    invalidate_slot_cache()
end

function M.DrawWindow()
    if not satchel.initialized then
        return
    end

    drawing.SetOverlayBlocker('satchel', not satchel.hidden and any_satchel_window_visible())

    if satchel.hidden then
        return
    end

    satchel.search.focus_seen = false

    sync_chrome_fonts(ui.get_global_scale())

    if is_module_enabled() then
        altcache.tick()
        -- Equipped-slot borders only render while a satchel window is open, so skip
        -- the per-frame poll during normal play; reopen self-heals via last_equipped.
        if any_satchel_window_visible() then
            poll_equipment_changes()
        end
        -- Advance the chunked item-name index; refresh search once it completes.
        if searchlogic.tick_name_index() then
            bump_search_generation()
        end
    end

    local scale = ui.get_global_scale()

    if sync_display_settings() then
        invalidate_slot_cache()
    end

    if not satchel.visible[1] then
        draw_auxiliary_windows(scale)
        finish_search_focus_frame()
        finalize_drag_frame()
        return
    end

    local _, slots_by_container, stats = get_slot_data(false)
    tick_auto_sort_server(stats)

    local display_tabs = build_display_tabs(stats)
    local show_slips_button = slipslogic.has_any_owned_slips()
    local owned_slip_ids = show_slips_button and get_slip_picker_ids(nil) or {}

    if satchel.active_tab == nil or not tab_is_available(satchel.active_tab, display_tabs) then
        satchel.active_tab = resolve_default_active_tab(display_tabs)
    end
    local display_tab = get_display_tab()

    local win_w, win_h, layout = compute_main_window_size(scale, show_slips_button, #display_tabs)
    ui.push_config_window_style()
    ui.set_window_size(win_w, win_h)

    local began = imgui.Begin('Satchel', satchel.visible, get_satchel_window_flags())
    if began then
        satchel.settings.visible = satchel.visible[1]
        local chrome_pushed = begin_chrome_font(scale)
        local main_dragging = satchel.drag.main.active == true
        local main_search = get_draft_search()
        local main_search_index = ensure_search_index(
            main_search,
            slots_by_container,
            owned_slip_ids,
            function(slip_id)
                return slipslogic.get_stored_items(slip_id)
            end
        )
        local match_containers = main_search_index.containers
        local slips_with_matches = main_search_index.slips
        local has_slip_matches = items.index_has_slip_matches(main_search_index)

        local toolbar_clicks, main_search_focused = ui.render_toolbar_with_search(
            satchel.search.draft,
            scale,
            'main',
            {
                { id = 'alt', label = 'Alt Inventories' },
                { id = 'slips', label = 'Storage Slips', visible = show_slips_button },
            },
            {
                align_width = layout.toolbar_align_width,
                search_active = main_search ~= '',
                is_dragging = main_dragging,
                highlight_button_ids = main_search ~= '' and {
                    alt = false,
                    slips = has_slip_matches,
                } or nil,
            }
        )
        note_search_input_focused(main_search_focused, 'shared')
        main_search = get_draft_search()
        main_search_index = ensure_search_index(
            main_search,
            slots_by_container,
            owned_slip_ids,
            function(slip_id)
                return slipslogic.get_stored_items(slip_id)
            end
        )
        match_containers = main_search_index.containers
        slips_with_matches = main_search_index.slips
        has_slip_matches = items.index_has_slip_matches(main_search_index)
        if toolbar_clicks.alt then
            open_alt_picker()
        end
        if toolbar_clicks.slips then
            open_slips_picker(nil)
        end

        imgui.Spacing()

        local sidebar_width = layout.sidebar_width
        local sidebar_gap = layout.sidebar_gap
        local grid_h = layout.grid_h
        local grid_ctx = build_grid_context(true, main_search_index)

        if #display_tabs == 0 then
            satchel.active_tab = nil
            imgui.TextColored({ 0.9, 0.72, 0.55, 1.0 }, 'No available inventory containers.')
        else
            ui.begin_child('##satchel_main_body', { 0, grid_h }, false, ui.NO_SCROLL_CHILD_FLAGS)

            local tab_drag_ctx = {
                search_active = main_search ~= '',
                search_match_containers = match_containers,
            }
            if not is_horizon_mode() then
                tab_drag_ctx.is_dragging = satchel.drag.main.active
                tab_drag_ctx.get_source_container = function()
                    local slot = satchel.drag.main.source_slot
                    return slot and tonumber(slot.container_id) or nil
                end
                tab_drag_ctx.can_drop_to_container = function(container_id)
                    if not satchel.drag.main.source_slot then
                        return false
                    end
                    return can_drop_slot_to_container(satchel.drag.main.source_slot, container_id, stats)
                end
                tab_drag_ctx.on_tab_hover = function(container_id)
                    satchel.drag.main.view_tab = container_id
                end
                tab_drag_ctx.get_selected_tab = function()
                    return get_display_tab()
                end
                tab_drag_ctx.on_drop_to_container = function(container_id)
                    handle_drop_to_container(container_id)
                end
                tab_drag_ctx.is_container_full = function(container_id)
                    local s = stats[container_id]
                    return s ~= nil and (s.total or 0) > 0 and (s.used or 0) >= s.total
                end
            end

            local current_tab = ui.render_scrollable_tab_sidebar(
                '##satchel_main_tabs',
                sidebar_width,
                grid_h,
                display_tabs,
                display_tab,
                function(container_id)
                    return containerlogic.format_tab_label(container_id)
                end,
                tab_drag_ctx,
                scale
            )

            if not satchel.drag.main.active
                and not satchel.drag.main.drop_handled
                and current_tab ~= nil
                and current_tab ~= satchel.active_tab then
                satchel.active_tab = current_tab
                display_tab = current_tab
            end

            imgui.SameLine(0, sidebar_gap)

            if satchel.drag.main.active then
                display_tab = get_display_tab()
            else
                display_tab = satchel.active_tab
            end

            ui.begin_child('##satchel_main_grid', { 0, grid_h }, false, ui.NO_SCROLL_CHILD_FLAGS)
            local raw_slots = slots_by_container[display_tab] or {}
            local active_slots = get_visual_slots_for_container(display_tab, raw_slots, stats)
            local active_stats = stats[display_tab] or { used = 0, total = 0, display = DISPLAY_SLOTS }
            ui.render_slot_grid(active_slots, tostring(display_tab or 0), active_stats, grid_ctx)
            satchel.drag.main.window_move_blocked = ui.should_block_satchel_window_move(DRAG_SCOPE_MAIN)
            ui.end_child()
            ui.end_child()

            ui.render_inventory_footer(active_stats, grid_ctx, {
                scale = scale,
                sidebar_width = sidebar_width,
                gap = sidebar_gap,
                grid_block_width = layout.grid_block_width,
            })
        end

        render_context_menu()
        end_chrome_font(chrome_pushed)
    end
    imgui.End()

    if not satchel.visible[1] then
        satchel.settings.visible = false
        clear_search()
    end
    satchel.last_visible = satchel.visible[1]

    ui.pop_config_window_style()

    draw_auxiliary_windows(scale)
    finish_search_focus_frame()
    finalize_drag_frame()
end

function M.SetHidden(hidden)
    satchel.hidden = hidden == true
    if satchel.hidden then
        clear_drag_state()
        drawing.SetOverlayBlocker('satchel', false)
    end
end

function M.Cleanup()
    close_all_satchel_windows()
    satchel.icons = {}
    satchel.file_icons = {}
    ui.clear_pending_drag()
    items.clear_caches()
    invalidate_slot_cache()
    altcache.invalidate()
    drawing.SetOverlayBlocker('satchel', false)
    satchel.initialized = false
end

function M.ResetPositions()
    -- Registry recovery updates windowPositions; move the live window when it is open.
    if satchel.visible[1] then
        imgui.SetWindowPos('Satchel', persistedWindow.RECOVER_ORIGIN)
    end
end

--@cmd /satchel : Toggle all satchel windows (requires Override /satchel in settings)
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

    local is_key_down = band(e.lparam, 0x80000000) == 0
    local vk = tonumber(e.wparam) or e.wparam

    if vk ~= 0x1B or not is_key_down then
        return
    end

    local close_on_esc = gConfig and gConfig.satchelCloseOnEscape == true

    -- Focused: ImGui clears InputText on ESC — never block that path.
    if satchel.search.input_focused then
        if close_on_esc and not search_has_text(satchel.search.input_scope or 'shared', satchel.search.input_alt_key) then
            if close_top_satchel_window() then
                e.blocked = true
            end
        end
        return
    end

    if try_clear_search() then
        e.blocked = true
        return
    end

    if close_on_esc and close_top_satchel_window() then
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
    elseif id == 0x01D then
        -- State at 0x04: 1 = AllLoaded, sent once the containers are populated
        -- after a zone and after every inventory mutation.
        local ok, state = pcall(struct.unpack, 'B', e.data_modified or e.data, 0x04 + 1)
        if ok and state == 1 then
            altcache.mark_dirty()
        end
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
