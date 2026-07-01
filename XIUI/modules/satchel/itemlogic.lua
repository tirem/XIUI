local breader = require('bitreader')
local tooltipicons = require('modules.satchel.tooltipicons')
local tooltipfonts = require('modules.satchel.tooltipfonts')
local tooltiplayout = require('modules.satchel.tooltiplayout')
local satchelcolors = require('modules.satchel.colors')
local searchlogic = require('modules.satchel.searchlogic')
local augmentlogic = require('modules.satchel.augmentlogic')
local sortstate = require('modules.satchel.sortstate')
local encoding = nil
do
    local ok_encoding, encoding_lib = pcall(require, 'libs.encoding')
    if ok_encoding then
        encoding = encoding_lib
    end
end
local time = nil
do
    local ok_time, time_lib = pcall(require, 'ffxi.time')
    if ok_time then
        time = time_lib
    end
end
local itemdata = nil
do
    local ok_data, data_lib = pcall(require, 'ffxi.data')
    if ok_data and data_lib then
        itemdata = data_lib
    else
        local ok_itemdata, itemdata_lib = pcall(require, 'ffxi.itemdata')
        if ok_itemdata and itemdata_lib then
            itemdata = itemdata_lib
        end
    end
end

local function create_item_logic(ctx)
    local satchel = ctx.satchel
    local imgui = ctx.imgui
    local addon_path = ctx.addon_path or ''

    local job_abbr = {
        [1] = 'WAR',
        [2] = 'MNK',
        [3] = 'WHM',
        [4] = 'BLM',
        [5] = 'RDM',
        [6] = 'THF',
        [7] = 'PLD',
        [8] = 'DRK',
        [9] = 'BST',
        [10] = 'BRD',
        [11] = 'RNG',
        [12] = 'SAM',
        [13] = 'NIN',
        [14] = 'DRG',
        [15] = 'SMN',
        [16] = 'BLU',
        [17] = 'COR',
        [18] = 'PUP',
        [19] = 'DNC',
        [20] = 'SCH',
        [21] = 'GEO',
        [22] = 'RUN',
    }

    local job_full_names = {
        [1] = 'warrior',
        [2] = 'monk',
        [3] = 'white mage',
        [4] = 'black mage',
        [5] = 'red mage',
        [6] = 'thief',
        [7] = 'paladin',
        [8] = 'dark knight',
        [9] = 'beastmaster',
        [10] = 'bard',
        [11] = 'ranger',
        [12] = 'samurai',
        [13] = 'ninja',
        [14] = 'dragoon',
        [15] = 'summoner',
        [16] = 'blue mage',
        [17] = 'corsair',
        [18] = 'puppetmaster',
        [19] = 'dancer',
        [20] = 'scholar',
        [21] = 'geomancer',
        [22] = 'rune fencer',
    }

    local element_colors = {
        Fire      = {1.00, 0.35, 0.12, 1.0},
        Ice       = {0.50, 0.90, 1.00, 1.0},
        Wind      = {0.30, 0.92, 0.35, 1.0},
        Earth     = {0.78, 0.58, 0.22, 1.0},
        Lightning = {1.00, 0.95, 0.25, 1.0},
        Water     = {0.25, 0.55, 1.00, 1.0},
        Light     = {1.00, 1.00, 0.85, 1.0},
        Dark      = {0.70, 0.22, 0.90, 1.0},
    }
    local element_list_ordered = {'Lightning', 'Water', 'Light', 'Dark', 'Fire', 'Ice', 'Wind', 'Earth'}
    tooltipicons.set_element_colors(element_colors)

    local armor_slot_masks = {
        head = 0x0010,
        body = 0x0020,
        hands = 0x0040,
        legs = 0x0080,
        feet = 0x0100,
        neck = 0x0200,
        waist = 0x0400,
        ear = bit.bor(0x0800, 0x1000),
        ring = bit.bor(0x2000, 0x4000),
        back = 0x8000,
    }

    local weapon_slot_masks = {
        main = 0x0001,
        sub = 0x0002,
        range = 0x0004,
        ammo = 0x0008,
    }

    local equip_slot_priority = {
        { mask = weapon_slot_masks.main, name = 'main' },
        { mask = weapon_slot_masks.sub, name = 'sub' },
        { mask = weapon_slot_masks.range, name = 'range' },
        { mask = weapon_slot_masks.ammo, name = 'ammo' },
        { mask = armor_slot_masks.head, name = 'head' },
        { mask = armor_slot_masks.body, name = 'body' },
        { mask = armor_slot_masks.hands, name = 'hands' },
        { mask = armor_slot_masks.legs, name = 'legs' },
        { mask = armor_slot_masks.feet, name = 'feet' },
        { mask = armor_slot_masks.neck, name = 'neck' },
        { mask = armor_slot_masks.waist, name = 'waist' },
        { mask = 0x0800, name = 'ear1' },
        { mask = 0x1000, name = 'ear2' },
        { mask = 0x2000, name = 'ring1' },
        { mask = 0x4000, name = 'ring2' },
        { mask = armor_slot_masks.back, name = 'back' },
    }

    local function is_wardrobe_container(container_id)
        return container_id == 8
            or container_id == 10
            or container_id == 11
            or container_id == 12
            or container_id == 13
            or container_id == 14
            or container_id == 15
            or container_id == 16
    end

    local M = {}

    local function trim_text(value)
        if type(value) ~= 'string' then
            return ''
        end
        return value:match('^%s*(.-)%s*$') or ''
    end

    local function escape_command_text(value)
        return trim_text(value):gsub('"', '\\"')
    end

    local function get_primary_equip_slot_name(item)
        if not item then
            return nil
        end

        local slots = tonumber(item.Slots) or 0
        if slots <= 0 then
            return nil
        end

        for _, entry in ipairs(equip_slot_priority) do
            if bit.band(slots, entry.mask) ~= 0 then
                return entry.name
            end
        end

        return nil
    end

    local search_text_cache = {}
    local description_text_cache = {}

    function M.clear_caches()
        satchel.names = {}
        satchel.item_types = {}
        satchel.item_sort_keys = {}
        search_text_cache = {}
        description_text_cache = {}
    end

    function M.get_item_name(item_id)
        if not item_id or item_id <= 0 then
            return 'Empty'
        end

        local cached = satchel.names[item_id]
        if cached then
            return cached
        end

        local rm = AshitaCore:GetResourceManager()
        local ok, item = pcall(rm.GetItemById, rm, item_id)

        local name = ('Item #%d'):format(item_id)
        if ok and item and item.Name and item.Name[1] and item.Name[1] ~= '' then
            name = item.Name[1]
        end

        satchel.names[item_id] = name
        return name
    end

    function M.get_item_type(item_id)
        if not item_id or item_id <= 0 then
            return 0
        end

        local cached = satchel.item_types[item_id]
        if cached ~= nil then
            return cached
        end

        local kind = 0
        local rm = AshitaCore:GetResourceManager()
        local ok, item = pcall(rm.GetItemById, rm, item_id)
        if ok and item and item.Type then
            kind = tonumber(item.Type) or 0
        end

        satchel.item_types[item_id] = kind
        return kind
    end

    function M.is_gear_item(item_id)
        local item_type = M.get_item_type(item_id)
        return item_type == 4 or item_type == 5
    end

    function M.is_wardrobe_container(container_id)
        return is_wardrobe_container(container_id)
    end

    function M.build_move_commands(slot, target_container_id, target_slot_index)
        return M.build_slot_move_commands(slot, target_container_id, target_slot_index, false)
    end

    local AUTO_EMPTY_SLOT_INDEX = 0x52

    local function get_live_container_item(slot)
        if not slot or slot.container_id == nil or slot.slot_index == nil then
            return nil
        end

        local inv = AshitaCore:GetMemoryManager():GetInventory()
        if not inv then
            return nil
        end

        local ok, item = pcall(function()
            return inv:GetContainerItem(slot.container_id, (tonumber(slot.slot_index) or 0) + 1)
        end)
        if ok and item and item.Id and tonumber(item.Id) > 0 and tonumber(item.Id) ~= 65535 then
            return item
        end
        return nil
    end

    function M.resolve_move_source_index(slot)
        local item = get_live_container_item(slot)
        if item then
            local item_index = tonumber(item.Index)
            if item_index and item_index > 0 and item_index < AUTO_EMPTY_SLOT_INDEX then
                return item_index
            end
        end

        local cached_index = slot and tonumber(slot.property_index) or nil
        if cached_index and cached_index > 0 and cached_index < AUTO_EMPTY_SLOT_INDEX then
            return cached_index
        end

        return nil
    end

    function M.get_item_stack_size(item_id)
        local item = M.get_item_resource(item_id)
        if not item then
            return 1
        end
        return math.max(1, tonumber(item.StackSize) or 1)
    end

    function M.can_stack_slots(source, target_slot)
        if not source or not target_slot then
            return false
        end
        if tonumber(source.container_id) ~= tonumber(target_slot.container_id) then
            return false
        end
        if tonumber(source.id) ~= tonumber(target_slot.id) then
            return false
        end
        if tonumber(source.slot_index) == tonumber(target_slot.slot_index) then
            return false
        end

        local target_index = tonumber(target_slot.property_index)
        if not target_index or target_index <= 0 or target_index >= AUTO_EMPTY_SLOT_INDEX then
            return false
        end

        local stack_size = M.get_item_stack_size(source.id)
        if stack_size <= 1 then
            return false
        end

        local src_count = tonumber(source.count) or 1
        local dst_count = tonumber(target_slot.count) or 1
        return (src_count + dst_count) <= stack_size
    end

    function M.resolve_drop_target_index(source, target_slot)
        if not source or not target_slot then
            return nil
        end

        local source_container = tonumber(source.container_id)
        local target_container = tonumber(target_slot.container_id)
        if not source_container or not target_container then
            return nil
        end

        local target_occupied = target_slot.id and target_slot.id > 0
        if target_occupied then
            if not M.can_stack_slots(source, target_slot) then
                return nil
            end
            return tonumber(target_slot.property_index)
        end

        if source_container ~= target_container then
            return AUTO_EMPTY_SLOT_INDEX
        end

        if tonumber(source.slot_index) == tonumber(target_slot.slot_index) then
            return nil
        end

        -- Retail/LSB: target_index < 0x52 is stack-only. Empty-slot moves use 0x52
        -- (server picks the first available slot in the destination container).
        return AUTO_EMPTY_SLOT_INDEX
    end

    function M.can_drop_drag_to_slot(source, target_slot, can_drop_to_container_fn)
        if not source or not target_slot or target_slot.locked then
            return false
        end

        local source_container = tonumber(source.container_id)
        local target_container = tonumber(target_slot.container_id)
        if not source_container or not target_container then
            return false
        end

        if source_container == target_container then
            if not sortstate.is_auto_sort_enabled()
                and not sortstate.should_visually_sort(source_container, satchel.container_sorted) then
                if not source.id or source.id <= 0 then
                    return false
                end
                if M.can_stack_slots(source, target_slot) then
                    return true
                end
                local src_display = tonumber(source.display_index)
                local dst_display = tonumber(target_slot.display_index)
                if src_display ~= nil and dst_display ~= nil then
                    return src_display ~= dst_display
                end
                return tonumber(source.slot_index) ~= tonumber(target_slot.slot_index)
            end

            if target_slot.id and target_slot.id > 0 then
                return M.can_stack_slots(source, target_slot)
            end
            return false
        end

        if target_slot.id and target_slot.id > 0 then
            return M.can_stack_slots(source, target_slot)
        end

        return can_drop_to_container_fn and can_drop_to_container_fn(target_container) == true
    end

    function M.build_slot_move_commands(slot, target_container_id, target_slot_index, allow_same_container)
        if not slot or slot.container_id == nil or not slot.id or slot.id <= 0 then
            return nil
        end

        local source_container_id = tonumber(slot.container_id)
        local target_container = tonumber(target_container_id)
        if not source_container_id or not target_container then
            return nil
        end

        if source_container_id == target_container and not allow_same_container then
            return nil
        end

        local move_count = tonumber(slot.count) or 1
        if move_count < 1 then
            move_count = 1
        end

        local source_index = M.resolve_move_source_index(slot)
        if source_index == nil or source_index <= 0 then
            return nil
        end

        local destination_index = tonumber(target_slot_index)
        if destination_index == nil or destination_index <= 0 then
            return nil
        end

        return T{
            {
                packet_id = 0x29,
                item_count = move_count,
                source_container = source_container_id,
                target_container = target_container,
                source_index = source_index,
                target_index = destination_index,
            },
        }
    end

    function M.get_item_resource(item_id)
        if not item_id or item_id <= 0 then
            return nil
        end

        local rm = AshitaCore:GetResourceManager()
        local ok, item = pcall(rm.GetItemById, rm, item_id)
        if ok and item then
            return item
        end
        return nil
    end

    local function get_armor_slot_rank(item)
        if not item then
            return 99
        end

        local slots = tonumber(item.Slots) or 0
        if slots <= 0 then
            return 99
        end

        if bit.band(slots, armor_slot_masks.head) ~= 0 then return 1 end
        if bit.band(slots, armor_slot_masks.body) ~= 0 then return 2 end
        if bit.band(slots, armor_slot_masks.hands) ~= 0 then return 3 end
        if bit.band(slots, armor_slot_masks.legs) ~= 0 then return 4 end
        if bit.band(slots, armor_slot_masks.feet) ~= 0 then return 5 end
        if bit.band(slots, armor_slot_masks.neck) ~= 0 then return 6 end
        if bit.band(slots, armor_slot_masks.waist) ~= 0 then return 7 end
        if bit.band(slots, armor_slot_masks.back) ~= 0 then return 8 end
        if bit.band(slots, armor_slot_masks.ear) ~= 0 then return 9 end
        if bit.band(slots, armor_slot_masks.ring) ~= 0 then return 10 end
        return 99
    end

    local function get_weapon_slot_rank(item)
        if not item then
            return 99
        end

        local slots = tonumber(item.Slots) or 0
        if slots <= 0 then
            return 99
        end

        if bit.band(slots, weapon_slot_masks.main) ~= 0 then return 1 end
        if bit.band(slots, weapon_slot_masks.sub) ~= 0 then return 2 end
        if bit.band(slots, weapon_slot_masks.range) ~= 0 then return 3 end
        if bit.band(slots, weapon_slot_masks.ammo) ~= 0 then return 4 end
        return 99
    end

    local function get_crystal_subrank(item_name)
        local name = (item_name or ''):lower()
        if name:find('cluster', 1, true) then
            return 2
        end
        if name:find(' crystal', 1, true) then
            return 1
        end
        return 3
    end

    local function get_element_rank_from_name(name)
        if type(name) ~= 'string' then
            return 99
        end
        local lowered = name:lower()

        if lowered:find('fire', 1, true) then return 1 end
        if lowered:find('ice', 1, true) then return 2 end
        if lowered:find('wind', 1, true) then return 3 end
        if lowered:find('earth', 1, true) then return 4 end
        if lowered:find('lightning', 1, true) then return 5 end
        if lowered:find('water', 1, true) then return 6 end
        if lowered:find('light', 1, true) then return 7 end
        if lowered:find('dark', 1, true) then return 8 end
        return 99
    end

    function M.get_item_sort_key(item_id)
        if not item_id or item_id <= 0 then
            return 99, 99
        end

        local cached = satchel.item_sort_keys[item_id]
        if cached then
            return cached.primary, cached.secondary
        end

        local item_type = M.get_item_type(item_id)
        local item = M.get_item_resource(item_id)
        local item_name = M.get_item_name(item_id)
        local crystal_rank = get_crystal_subrank(item_name)
        local primary = 5
        local secondary = 99

        if crystal_rank <= 2 then
            primary = 1
            local element_rank = get_element_rank_from_name(item_name)
            secondary = (crystal_rank * 100) + element_rank
        elseif item_type == 7 then
            primary = 2
        elseif item_type == 4 then
            primary = 3
            secondary = get_weapon_slot_rank(item)
        elseif item_type == 5 then
            primary = 4
            secondary = get_armor_slot_rank(item)
        end

        satchel.item_sort_keys[item_id] = { primary = primary, secondary = secondary }
        return primary, secondary
    end

    local function read_number_field(item, field_name)
        local ok, value = pcall(function()
            return item[field_name]
        end)
        if not ok then
            return nil
        end
        local n = tonumber(value)
        if n and n > 0 then
            return n
        end
        return nil
    end

    local function get_item_level_value(item)
        if not item then
            return nil
        end

        local ok_method, method_value = pcall(function()
            if type(item.GetItemLevel) == 'function' then
                return item:GetItemLevel()
            end
            return nil
        end)
        if ok_method then
            local n = tonumber(method_value)
            if n and n > 0 then
                return n
            end
        end

        return read_number_field(item, 'ItemLevel')
    end

    local function format_duration(seconds)
        local total = math.max(0, math.floor(tonumber(seconds) or 0))
        local hours = math.floor(total / 3600)
        local minutes = math.floor((total % 3600) / 60)
        local secs = total % 60

        if hours > 0 then
            return ('%d:%02d:%02d'):format(hours, minutes, secs)
        end
        return ('%d:%02d'):format(minutes, secs)
    end

    local function format_enchant_status(enchant_info)
        if not enchant_info then
            return nil
        end

        local remaining = tonumber(enchant_info.remaining_charges)
        local max_charges = tonumber(enchant_info.max_charges) or 0
        local equip_delay = tonumber(enchant_info.equip_delay) or 0
        local reuse_delay = tonumber(enchant_info.reuse_delay) or 0

        local uses_text = nil
        if max_charges > 0 and max_charges ~= 255 then
            if remaining ~= nil then
                uses_text = ('%d/%d'):format(remaining, max_charges)
            else
                uses_text = ('%d/%d'):format(max_charges, max_charges)
            end
        end

        if not uses_text and equip_delay <= 0 and reuse_delay <= 0 then
            return nil
        end

        local current_timer_text = format_duration(tonumber(enchant_info.use_delay) or 0)
        local reuse_text = format_duration(reuse_delay)
        local equip_text = format_duration(equip_delay)

        -- ImGui 4.16 treats "<7" style prefixes as color markup; keep the literal brackets.
        return ('\194\160<%s %s/[%s, %s]>'):format(uses_text or '--/--', current_timer_text, reuse_text, equip_text)
    end

    local function get_inventory_item(slot)
        if not slot or slot.container_id == nil or slot.slot_index == nil then
            return nil
        end

        local inv = AshitaCore:GetMemoryManager():GetInventory()
        if not inv then
            return nil
        end

        local ok, item = pcall(function()
            return inv:GetContainerItem(slot.container_id, (slot.slot_index or 0) + 1)
        end)
        if ok and item and item.Id and tonumber(item.Id) == tonumber(slot.id) then
            return item
        end
        return nil
    end

    local function is_slot_currently_equipped(slot)
        if not slot or slot.container_id == nil then
            return false
        end

        local inv = AshitaCore:GetMemoryManager():GetInventory()
        if not inv then
            return false
        end

        local target_container = tonumber(slot.container_id)
        local target_property_index = tonumber(slot.property_index)
        if target_container == nil or target_property_index == nil or target_property_index <= 0 then
            return false
        end

        for equip_slot = 0, 15 do
            local equipped = inv:GetEquippedItem(equip_slot)
            if equipped and equipped.Index then
                local raw_index = tonumber(equipped.Index) or 0
                local equipped_index = bit.band(raw_index, 0x00FF)
                if equipped_index > 0 then
                    local equipped_container = bit.rshift(bit.band(raw_index, 0xFF00), 8)
                    if equipped_container == target_container and equipped_index == target_property_index then
                        return true
                    end
                end
            end
        end

        return false
    end

    local function is_slot_in_bazaar(slot)
        if not slot or slot.container_id ~= 0 or not slot.id or slot.id <= 0 then
            return false
        end

        local inv_item = get_inventory_item(slot)
        if not inv_item then
            return false
        end

        return (tonumber(inv_item.Price) or 0) > 0
    end

    local function get_enchantment_info(slot, item, resource)
        if not resource or not item then
            return nil
        end

        local max_charges = tonumber(resource.MaxCharges) or 0
        local equip_delay = tonumber(resource.CastDelay) or 0
        local reuse_delay = tonumber(resource.RecastDelay) or 0
        if max_charges <= 0 and equip_delay <= 0 and reuse_delay <= 0 then
            return nil
        end

        local info = {
            max_charges = max_charges,
            equip_delay = equip_delay,
            reuse_delay = reuse_delay,
            remaining_charges = nil,
            use_delay = 0,
        }

        local inv_item = get_inventory_item(slot)
        if inv_item and inv_item.Extra then
            local ok, reader = pcall(function()
                return breader:new(T{}, inv_item.Extra)
            end)
            if ok and reader and reader:read(8) == 1 then
                info.remaining_charges = reader:read(8)
                local _flags = reader:read(16)
                local time_value1 = reader:read(32)
                local time_value2 = reader:read(32)

                if time and time.game_time_diff then
                    local use_delay = tonumber(time.game_time_diff(time_value1)) or 0
                    local equip_delay_current = tonumber(time.game_time_diff(time_value2)) or 0
                    local is_equipped = is_slot_currently_equipped(slot)

                    -- Only force cast-delay minimum when item is not equipped.
                    if (not is_equipped) and equip_delay_current < info.equip_delay then
                        equip_delay_current = info.equip_delay
                    end
                    if use_delay < equip_delay_current then
                        use_delay = equip_delay_current
                    end

                    if info.max_charges ~= 255 and info.remaining_charges == 0 then
                        use_delay = 0
                    end

                    info.use_delay = math.max(0, use_delay)
                end

                if info.max_charges == 255 then
                    info.remaining_charges = 255
                end
            end
        end

        return info
    end

    local function get_item_signature_text(slot, item_type)
        if item_type ~= 4 and item_type ~= 5 then
            return ''
        end

        if not itemdata or not itemdata.parse_signature then
            return ''
        end

        local inv_item = get_inventory_item(slot)
        if not inv_item or type(inv_item.Extra) ~= 'string' or inv_item.Extra == '' then
            return ''
        end

        local ok, value = pcall(itemdata.parse_signature, inv_item.Extra, 12)
        if not ok or type(value) ~= 'string' then
            return ''
        end

        local signature = trim_text(value)
        if signature == '' then
            return ''
        end

        return signature
    end

    local function slot_has_augments(slot)
        local inv_item = get_inventory_item(slot)
        if not inv_item or type(inv_item.Extra) ~= 'string' or inv_item.Extra == '' then
            return false
        end

        return augmentlogic.has_augments(slot.id, inv_item.Extra)
    end

    local function get_slot_augment_lines(slot)
        local inv_item = get_inventory_item(slot)
        if not inv_item or type(inv_item.Extra) ~= 'string' or inv_item.Extra == '' then
            return {}
        end

        return augmentlogic.get_augment_lines(slot.id, inv_item.Extra)
    end

    local function is_augment_description_line(line)
        return type(line) == 'string' and line:match('^%[%d+%]') ~= nil
    end

    local function split_description_augment_lines(desc)
        local body_lines = {}
        local augment_lines = {}

        if type(desc) ~= 'string' or desc == '' then
            return '', augment_lines
        end

        for line in (desc .. '\n'):gmatch('([^\n]*)\n') do
            if is_augment_description_line(line) then
                augment_lines[#augment_lines + 1] = line
            elseif line ~= '' then
                body_lines[#body_lines + 1] = line
            end
        end

        return table.concat(body_lines, '\n'), augment_lines
    end

    local function collect_augment_display_lines(slot, desc)
        local _, desc_augment_lines = split_description_augment_lines(desc)
        if #desc_augment_lines > 0 then
            return desc_augment_lines
        end

        local ext_lines = get_slot_augment_lines(slot)
        if #ext_lines == 0 then
            return {}
        end

        local parts = {}
        for _, augment in ipairs(ext_lines) do
            if type(augment) == 'string' and augment ~= '' then
                parts[#parts + 1] = augment
            end
        end

        if #parts == 0 then
            return {}
        end

        return { table.concat(parts, ' ') }
    end

    local function get_effective_item_flags(item, slot)
        local flags_val = 0

        if item then
            local ok, raw = pcall(function() return item.Flags end)
            flags_val = (ok and tonumber(raw)) or 0
        end

        local inv_item = slot and get_inventory_item(slot)
        if inv_item then
            local instance_flags = tonumber(inv_item.Flags) or 0
            flags_val = bit.bor(flags_val, instance_flags)
        end

        if slot and augmentlogic.augment_makes_exclusive(slot.id, inv_item and inv_item.Extra) then
            flags_val = bit.bor(flags_val, 0x4000)
        end

        return flags_val
    end

    local function get_equip_jobs_text(item)
        if not item then
            return ''
        end

        local mask = nil
        local mask_fields = { 'Jobs', 'JobMask', 'EquipJobs', 'JobsMask' }
        for _, field_name in ipairs(mask_fields) do
            local n = read_number_field(item, field_name)
            if n then
                mask = n
                break
            end
        end

        if not mask then
            local probes = {
                function() return item.Jobs and item.Jobs[1] end,
                function() return item.Jobs and item.Jobs[0] end,
                function() return item.EquipJobs and item.EquipJobs[1] end,
                function() return item.EquipJobs and item.EquipJobs[0] end,
            }
            for _, probe in ipairs(probes) do
                local ok, val = pcall(probe)
                if ok then
                    local n = tonumber(val)
                    if n and n > 0 then
                        mask = n
                        break
                    end
                end
            end
        end

        if not mask then
            return ''
        end

        local jobs = {}
        for i = 1, 22 do
            local bitval = bit.lshift(1, i)
            if bit.band(mask, bitval) ~= 0 then
                local abbr = job_abbr[i]
                if abbr then
                    table.insert(jobs, abbr)
                end
            end
        end

        if #jobs == 0 then
            return ''
        end

        if #jobs == 22 then
            return 'All Jobs'
        end

        return table.concat(jobs, '/')
    end

    local COMBAT_ROW_STANDALONE = '^%s*DMG:%s*[+%-]?%d+%s+Delay:%s*[+%-]?%d+%s*$'
    local COMBAT_ROW_PREFIX = '^(%s*DMG:%s*[+%-]?%d+%s+Delay:%s*[+%-]?%d+%s*)'

    local function line_has_combat_stats(line)
        return line:match(COMBAT_ROW_STANDALONE) ~= nil
            or line:match(COMBAT_ROW_PREFIX) ~= nil
    end

    local function strip_leading_combat_stats(line)
        local stripped = line:gsub(COMBAT_ROW_PREFIX, '', 1)
        return trim_text(stripped)
    end

    local function description_has_combat_stats(desc)
        if desc == '' then
            return false
        end

        for line in (desc .. '\n'):gmatch('([^\n]*)\n') do
            if line_has_combat_stats(line) then
                return true
            end
        end

        return false
    end

    local function filter_weapon_description_lines(desc)
        local filtered_lines = {}
        for line in (desc .. '\n'):gmatch('([^\n]*)\n') do
            if line:match(COMBAT_ROW_STANDALONE) then
                -- Drop duplicate standalone combat rows.
            elseif line_has_combat_stats(line) then
                local remainder = strip_leading_combat_stats(line)
                if remainder ~= '' then
                    filtered_lines[#filtered_lines + 1] = remainder
                end
            elseif line ~= '' then
                filtered_lines[#filtered_lines + 1] = line
            end
        end

        return table.concat(filtered_lines, '\n')
    end

    local function is_plausible_delay(delay)
        local value = tonumber(delay)
        return value ~= nil and value > 0 and value < 900
    end

    local function get_item_races_text(item)
        if not item then
            return ''
        end

        local mask = read_number_field(item, 'Races')
        if not mask then
            return ''
        end

        local race_masks = {
            hume_m = 0x0002,
            hume_f = 0x0004,
            elvaan_m = 0x0008,
            elvaan_f = 0x0010,
            tarutaru_m = 0x0020,
            tarutaru_f = 0x0040,
            hume = bit.bor(0x0002, 0x0004),
            elvaan = bit.bor(0x0008, 0x0010),
            tarutaru = bit.bor(0x0020, 0x0040),
            mithra = 0x0080,
            galka = 0x0100,
            male = 0x012A,
            female = 0x00D4,
            all = 0x01FE,
        }

        local male_symbol = 'M'
        local female_symbol = 'F'

        if bit.band(mask, race_masks.all) == race_masks.all then
            return 'All Races'
        end

        if bit.band(mask, race_masks.male) == race_masks.male and bit.band(mask, race_masks.female) == 0 then
            return ('All Races %s'):format(male_symbol)
        end

        if bit.band(mask, race_masks.female) == race_masks.female and bit.band(mask, race_masks.male) == 0 then
            return ('All Races %s'):format(female_symbol)
        end

        local names = {}

        local function append_race_with_gender(base_name, male_bit, female_bit)
            local has_m = bit.band(mask, male_bit) ~= 0
            local has_f = bit.band(mask, female_bit) ~= 0
            if has_m and has_f then
                table.insert(names, base_name)
            elseif has_m then
                table.insert(names, ('%s %s'):format(base_name, male_symbol))
            elseif has_f then
                table.insert(names, ('%s %s'):format(base_name, female_symbol))
            end
        end

        append_race_with_gender('Hume', race_masks.hume_m, race_masks.hume_f)
        append_race_with_gender('Elvaan', race_masks.elvaan_m, race_masks.elvaan_f)
        append_race_with_gender('Tarutaru', race_masks.tarutaru_m, race_masks.tarutaru_f)
        if bit.band(mask, race_masks.mithra) ~= 0 then table.insert(names, 'Mithra') end
        if bit.band(mask, race_masks.galka) ~= 0 then table.insert(names, 'Galka') end

        return table.concat(names, ' ')
    end

    local function get_item_flag_tags(item, slot)
        if not item and not slot then
            return {}
        end

        local flags_val = get_effective_item_flags(item, slot)
        local tags = {}

        if bit.band(flags_val, 0x0010) ~= 0 then tags[#tags + 1] = 'alt' end
        if bit.band(flags_val, 0x8000) ~= 0 then tags[#tags + 1] = 'rare' end

        if slot_has_augments(slot) then
            tags[#tags + 1] = 'aug'
        end

        if bit.band(flags_val, 0x4000) ~= 0 then tags[#tags + 1] = 'ex' end

        if slot and tonumber(slot.container_id) == 3 then
            tags[#tags + 1] = 'tmp'
        end

        return tags
    end

    local function render_tooltip_name_separator(color)
        imgui.Dummy({ 0, 3 })
        imgui.PushStyleColor(ImGuiCol_Separator, color)
        imgui.Separator()
        imgui.PopStyleColor(1)
        imgui.Dummy({ 0, 3 })
    end

    local function render_tooltip_tags_top_right(item, slot, start_x, start_y, wrap_width)
        local tags = get_item_flag_tags(item, slot)
        if #tags == 0 then
            return 0
        end

        local as_words = tooltipicons.icons_as_words()
        local tags_width = tooltipicons.measure_status_tags_width(satchel, addon_path, tags, as_words)

        imgui.SetCursorPos({ start_x + wrap_width - tags_width, start_y })
        for index, tag_key in ipairs(tags) do
            if index > 1 then
                imgui.SameLine(0, 0)
            end
            tooltipicons.render_status_tag(satchel, addon_path, tag_key, as_words)
        end

        return math.max(
            tonumber(imgui.GetTextLineHeight()) or tooltipicons.TAG_ICON_SIZE,
            tooltipicons.TAG_ICON_SIZE
        )
    end

    local function render_tooltip_header(item, slot, item_name, name_color, wrap_width, is_bazaar_listed)
        local start_x = imgui.GetCursorPosX()
        local start_y = imgui.GetCursorPosY()
        local tags = get_item_flag_tags(item, slot)
        local tags_width = 0

        if #tags > 0 then
            tags_width = tooltipicons.measure_status_tags_width(
                satchel,
                addon_path,
                tags,
                tooltipicons.icons_as_words()
            )
        end

        local tag_row_h = render_tooltip_tags_top_right(item, slot, start_x, start_y, wrap_width)

        imgui.SetCursorPos({ start_x, start_y })
        local name_wrap = start_x + wrap_width
        if tags_width > 0 then
            name_wrap = start_x + wrap_width - tags_width - 8
        end
        imgui.PushTextWrapPos(name_wrap)
        imgui.TextColored(name_color, item_name)
        imgui.PopTextWrapPos()

        if is_bazaar_listed then
            imgui.TextColored({ 0.95, 0.32, 0.32, 1.0 }, 'Listed in Bazaar (cannot use/equip)')
        end

        local content_bottom = imgui.GetCursorPosY()
        if content_bottom < start_y + tag_row_h then
            imgui.SetCursorPosY(start_y + tag_row_h)
        end
    end

    local function get_weapon_type_text(item)
        local skill = item and read_number_field(item, 'Skill') or nil
        if not skill then
            return 'Weapon'
        end

        local by_skill = {
            [1] = 'Hand-to-Hand',
            [2] = 'Dagger',
            [3] = 'Sword',
            [4] = 'Great Sword',
            [5] = 'Axe',
            [6] = 'Great Axe',
            [7] = 'Scythe',
            [8] = 'Polearm',
            [9] = 'Katana',
            [10] = 'Great Katana',
            [11] = 'Club',
            [12] = 'Staff',
            [25] = 'Archery',
            [26] = 'Marksmanship',
            [27] = 'Throwing',
        }

        return by_skill[skill] or 'Weapon'
    end

    local function get_armor_type_text(item)
        local slot = get_primary_equip_slot_name(item)
        if not slot then
            return 'Armor'
        end

        local by_slot = {
            head = 'Head',
            body = 'Body',
            hands = 'Hands',
            legs = 'Legs',
            feet = 'Feet',
            neck = 'Neck',
            waist = 'Waist',
            ear1 = 'Earring',
            ear2 = 'Earring',
            ring1 = 'Ring',
            ring2 = 'Ring',
            back = 'Back',
        }

        return by_slot[slot] or 'Armor'
    end

    local WAVE_DASH_MARKER = tooltipfonts.get_wave_dash_marker()

    local function apply_description_punctuation(text)
        if type(text) ~= 'string' or text == '' then
            return text
        end

        local replacements = {
            ['\239\188\133'] = '%',
        }

        for from, to in pairs(replacements) do
            text = text:gsub(from, to)
        end

        text = text:gsub('\239\191\189', '?')
        return text
    end

    local function replace_literal(text, search, replace)
        if type(text) ~= 'string' or search == '' then
            return text
        end

        local parts = {}
        local start = 1
        while true do
            local match_start, match_end = text:find(search, start, true)
            if not match_start then
                parts[#parts + 1] = text:sub(start)
                break
            end

            parts[#parts + 1] = text:sub(start, match_start - 1)
            parts[#parts + 1] = replace
            start = match_end + 1
        end

        return table.concat(parts)
    end

    local function normalize_trait_quote_delimiters(text)
        if type(text) ~= 'string' or text == '' then
            return text
        end

        -- RS/US bytes often wrap trait names (e.g. "Subtle Blow") in raw item descriptions.
        -- Must run before bare 0x1F fire-icon handling, which used to treat those
        -- delimiters as Fire element icons and crash tooltips on Ashita 4.16.
        text = text:gsub('\30([^%z\30]+)\30', '"%1"')
        text = text:gsub('\31([^%z\31]+)\31', '"%1"')

        return text
    end

    local function protect_bare_fire_icon_byte(text)
        if type(text) ~= 'string' or text == '' then
            return text
        end

        -- Bare 0x1F is only a fire icon when directly followed by a signed number.
        return text:gsub(string.char(0x1F) .. '([%+%-]%d)', '{{ICON1}}%1')
    end

    local function protect_ef_icon_bytes(text)
        for index, entry in ipairs(tooltipicons.ELEMENTS) do
            local marker = string.char(0xEF, entry.byte)
            text = replace_literal(text, marker, ('{{ICON%d}}'):format(index))
        end

        text = protect_bare_fire_icon_byte(text)

        return text
    end

    local function restore_ef_icon_bytes(text)
        for index, entry in ipairs(tooltipicons.ELEMENTS) do
            text = replace_literal(text, ('{{ICON%d}}'):format(index), string.char(0xEF, entry.byte))
        end
        return text
    end

    local function strip_description_controls(text)
        text = protect_ef_icon_bytes(text)
        text = text:gsub('\30.', '')
        text = text:gsub('\31.', '')
        text = text:gsub('[%z\1-\8\11\12\14-\31]', ' ')
        text = text:gsub('\194\160', ' ')
        text = restore_ef_icon_bytes(text)
        return text
    end

    local function protect_wave_dash_bytes(text)
        if type(text) ~= 'string' or text == '' then
            return text
        end

        -- Longer sequences must be matched before their prefixes.
        local replacements = {
            '\239\191\189\96',
            '\239\191\189',
            '\239\189\158',
            '\227\128\156',
            '\239\188\140',
            '\129\96',
            '\126',
            '〜',
            '～',
            '~',
        }

        for _, from in ipairs(replacements) do
            text = replace_literal(text, from, WAVE_DASH_MARKER)
        end

        return text
    end

    local function repair_stat_range_questions(text)
        if type(text) ~= 'string' or text == '' then
            return text
        end

        return text:gsub('(%d)%?(%d)', '%1' .. WAVE_DASH_MARKER .. '%2')
    end

    local function normalize_description_text(value)
        if type(value) ~= 'string' then
            return ''
        end

        local text = value
        text = text:gsub('\r\n', '\n')
        text = text:gsub('\r', '\n')
        text = normalize_trait_quote_delimiters(text)
        text = protect_ef_icon_bytes(text)
        text = protect_wave_dash_bytes(text)
        text = apply_description_punctuation(text)
        text = repair_stat_range_questions(text)
        text = strip_description_controls(text)
        text = text:gsub('[ \t]+', ' ')
        text = text:gsub(' *\n *', '\n')

        return trim_text(text)
    end

    local function fix_known_element_placeholders(text)
        if type(text) ~= 'string' or text == '' then
            return text
        end
        local element_order = { 'Fire', 'Ice', 'Wind', 'Earth', 'Lightning', 'Water', 'Light', 'Dark' }
        local idx = 1
        text = text:gsub('[%?％]%s*([%+%-]?%d+)(%%?)', function(amount, pct)
            if idx > #element_order then return '?' .. amount .. (pct or '') end
            local n = tonumber(amount)
            if not n then return '?' .. amount .. (pct or '') end
            local elem = element_order[idx]
            idx = idx + 1
            local sign = (n >= 0) and '+' or ''
            return ('%s %s%d%s'):format(elem, sign, n, pct or '')
        end)
        return text
    end

    local function adjust_element_token_spacing(tokens, as_words)
        for index = 2, #tokens do
            if tokens[index - 1].kind == 'elem' and tokens[index].kind == 'text' then
                tokens[index].value = tokens[index].value:gsub('^%s+', '')
            end
        end
        return tokens
    end

    local function title_case_words(text)
        return tooltiplayout.title_case_words(text)
    end

    local function format_augment_display_line(line)
        return tooltiplayout.format_augment_display_line(line)
    end

    local function strip_elemental_resist_words(line)
        return tooltiplayout.strip_elemental_resist_words(line)
    end

    local function line_has_element_tokens(tokens)
        for _, token in ipairs(tokens) do
            if token.kind == 'elem' then
                return true
            end
        end
        return false
    end

    local function parse_description_line(line)
        local tokens = {}
        local index = 1
        local text_start = 1

        local function flush_text(end_index)
            if end_index < text_start then
                return
            end
            local chunk = line:sub(text_start, end_index)
            if chunk ~= '' then
                tokens[#tokens + 1] = { kind = 'text', value = chunk }
            end
        end

        while index <= #line do
            local byte = line:byte(index)
            if byte == 0xEF and (index + 1) <= #line then
                flush_text(index - 1)
                local second = line:byte(index + 1)
                local element_entry = tooltipicons.ELEMENT_BY_BYTE[second]
                if element_entry then
                    tokens[#tokens + 1] = { kind = 'elem', entry = element_entry }
                    index = index + 2
                    text_start = index
                else
                    index = index + 2
                    text_start = index
                end
            else
                index = index + 1
            end
        end

        flush_text(#line)
        return tokens
    end

    local AUGMENT_TEXT_COLOR = { 0.98, 0.96, 0.72, 1.0 }

    local function render_inline_wave_dash(color)
        tooltipfonts.ensure_tooltip_font_glyphs()

        local wave_font = tooltipfonts.get_wave_font()
        if wave_font then
            imgui.PushFont(wave_font)
            imgui.TextColored(color, tooltipfonts.get_wave_dash_char())
            imgui.PopFont()
            return
        end

        if tooltipfonts.try_render_merged_glyph(color) then
            return
        end

        local x, y = imgui.GetCursorScreenPos()
        local h = tonumber(imgui.GetTextLineHeight()) or 14
        local w = tooltipfonts.measure_wave_dash_width()
        local draw = imgui.GetWindowDrawList()

        if draw then
            local col = imgui.GetColorU32(color or { 0.88, 0.88, 0.88, 1.0 })
            local baseline = y + h * 0.68
            local amp = h * 0.14
            local segments = 14
            local prev_x = x
            local prev_y = baseline - amp * math.sin(0)

            for i = 1, segments do
                local t = i / segments
                local px = x + w * t
                local py
                if t <= 0.5 then
                    py = baseline - amp * math.sin(t * math.pi * 2)
                else
                    py = baseline + amp * math.sin((t - 0.5) * math.pi * 2)
                end
                draw:AddLine({ prev_x, prev_y }, { px, py }, col, 1.1)
                prev_x = px
                prev_y = py
            end
        end

        imgui.Dummy({ w, h })
    end

    local function render_text_with_wave_dash(color, text)
        if type(text) ~= 'string' or text == '' then
            return
        end

        if not text:find(WAVE_DASH_MARKER, 1, true) then
            imgui.TextColored(color, text)
            return
        end

        local started = false
        local pos = 1
        while pos <= #text do
            local marker_start = text:find(WAVE_DASH_MARKER, pos, true)
            if not marker_start then
                local chunk = text:sub(pos)
                if chunk ~= '' then
                    if started then
                        imgui.SameLine(0, 0)
                    end
                    imgui.TextColored(color, chunk)
                end
                break
            end

            local chunk = text:sub(pos, marker_start - 1)
            if chunk ~= '' then
                if started then
                    imgui.SameLine(0, 0)
                end
                imgui.TextColored(color, chunk)
                started = true
            end

            if started or chunk ~= '' then
                imgui.SameLine(0, 0)
            end
            render_inline_wave_dash(color)
            started = true
            pos = marker_start + #WAVE_DASH_MARKER
        end
    end

    local function render_tooltip_text_colored(color, text)
        if type(text) ~= 'string' or text == '' then
            return
        end

        if text:find(WAVE_DASH_MARKER, 1, true) then
            render_text_with_wave_dash(color, text)
            return
        end

        imgui.TextColored(color, text)
    end

    local function render_description_line_tokens(tokens, as_words)
        local gray = { 0.88, 0.88, 0.88, 1.0 }

        for token_index, token in ipairs(tokens) do
            if token_index > 1 then
                imgui.SameLine(0, 0)
            end

            if token.kind == 'text' then
                render_tooltip_text_colored(gray, token.value)
            elseif token.kind == 'elem' then
                tooltipicons.render_element_token(satchel, addon_path, token.entry, as_words)
            end
        end
    end

    local function build_element_word_tokens(line)
        line = strip_elemental_resist_words(line)
        local tokens = {}
        local pos = 1

        while pos <= #line do
            local best_s, best_e, best_elem = nil, nil, nil
            for _, elem in ipairs(element_list_ordered) do
                local es, ee = line:find(elem, pos, true)
                if es and (not best_s or es < best_s) then
                    local prev_char = es > 1 and line:sub(es - 1, es - 1) or ''
                    local next_char = line:sub(ee + 1, ee + 1)
                    if not prev_char:match('%a') and not next_char:match('%a') then
                        best_s, best_e, best_elem = es, ee, elem
                    end
                end
            end

            if best_s then
                if best_s > pos then
                    tokens[#tokens + 1] = { kind = 'text', value = line:sub(pos, best_s - 1) }
                end
                tokens[#tokens + 1] = { kind = 'elem_word', name = best_elem }
                pos = best_e + 1
            else
                tokens[#tokens + 1] = { kind = 'text', value = line:sub(pos) }
                break
            end
        end

        return tokens
    end

    local function render_element_word_tokens(tokens, gray)
        gray = gray or { 0.88, 0.88, 0.88, 1.0 }

        for token_index, token in ipairs(tokens) do
            if token_index > 1 then
                imgui.SameLine(0, 0)
            end
            if token.kind == 'elem_word' then
                imgui.TextColored(element_colors[token.name], token.name)
            else
                render_tooltip_text_colored(gray, token.value)
            end
        end
    end

    local function render_description_line_with_element_words(line)
        render_element_word_tokens(build_element_word_tokens(line))
    end

    local function render_inline_text_with_element_words(text)
        if type(text) ~= 'string' or text == '' then
            return
        end

        render_element_word_tokens(build_element_word_tokens(text))
    end

    local function render_description_line_tokens_hybrid(tokens)
        for token_index, token in ipairs(tokens) do
            if token_index > 1 then
                imgui.SameLine(0, 0)
            end

            if token.kind == 'text' then
                render_inline_text_with_element_words(token.value)
            elseif token.kind == 'elem' then
                tooltipicons.render_element_token(satchel, addon_path, token.entry, false)
            end
        end
    end

    local function render_augment_description_line(line)
        line = format_augment_display_line(strip_elemental_resist_words(line))
        local as_words = tooltipicons.icons_as_words()
        local metrics = tooltipfonts.get_metrics()

        if as_words and tooltiplayout.line_needs_option_c(line, true) then
            tooltiplayout.render_augment_option_c_line(
                line,
                AUGMENT_TEXT_COLOR,
                element_colors,
                metrics.wrap_width,
                metrics.family,
                metrics.pixel_size,
                render_tooltip_text_colored
            )
            return
        end

        local tokens = parse_description_line(line)

        if line_has_element_tokens(tokens) then
            adjust_element_token_spacing(tokens, as_words)
            if as_words then
                for token_index, token in ipairs(tokens) do
                    if token_index > 1 then
                        imgui.SameLine(0, 0)
                    end

                    if token.kind == 'text' then
                        render_tooltip_text_colored(AUGMENT_TEXT_COLOR, token.value)
                    elseif token.kind == 'elem' then
                        tooltipicons.render_element_token(satchel, addon_path, token.entry, as_words)
                    end
                end
            else
                for token_index, token in ipairs(tokens) do
                    if token_index > 1 then
                        imgui.SameLine(0, 0)
                    end

                    if token.kind == 'text' then
                        render_tooltip_text_colored(AUGMENT_TEXT_COLOR, token.value)
                    elseif token.kind == 'elem' then
                        tooltipicons.render_element_token(satchel, addon_path, token.entry, false)
                    end
                end
            end
        else
            render_tooltip_text_colored(AUGMENT_TEXT_COLOR, fix_known_element_placeholders(line))
        end
    end

    local function render_augment_display_lines(lines)
        for _, line in ipairs(lines or {}) do
            if type(line) == 'string' and line ~= '' then
                render_augment_description_line(line)
            end
        end
    end

    local DESCRIPTION_MAX_LEN = 1024

    local function read_resource_string_field(field, index)
        if not field then
            return nil
        end

        local ok, value = pcall(function()
            return field[index]
        end)
        if not ok or type(value) ~= 'string' or value == '' then
            return nil
        end

        return value
    end

    local function coerce_resource_string(value)
        if type(value) ~= 'string' or value == '' then
            return nil
        end

        if encoding and encoding.ShiftJIS_To_UTF8 then
            local ok, converted = pcall(encoding.ShiftJIS_To_UTF8, encoding, value, true)
            if ok and type(converted) == 'string' and converted ~= '' then
                return converted
            end
        end

        return value
    end

    local function looks_like_memory_dump(text)
        if type(text) ~= 'string' or text == '' then
            return true
        end

        if text:find('##', 1, true) then
            return true
        end
        if text:find('userdata', 1, true) then
            return true
        end
        if text:find('satchel_', 1, true) or text:find('grid_slip', 1, true) then
            return true
        end
        if text:match('0[Xx]%x+%.?%s*[%xA-F]+DEF') then
            return true
        end
        if #text > 48 and text:match('[%xA-F]{8,}') and text:match('DEF') then
            return true
        end

        local question_count = select(2, text:gsub('%?', ''))
        if question_count > 12 then
            return true
        end

        return false
    end

    local function is_plausible_raw_description(text)
        if type(text) ~= 'string' then
            return false
        end

        local len = #text
        if len == 0 or len > DESCRIPTION_MAX_LEN then
            return false
        end

        return not looks_like_memory_dump(text)
    end

    local function is_plausible_description_text(text)
        if type(text) ~= 'string' then
            return false
        end

        local len = #text
        if len == 0 or len > DESCRIPTION_MAX_LEN then
            return false
        end

        if looks_like_memory_dump(text) then
            return false
        end

        local bad = 0
        for i = 1, len do
            local b = text:byte(i)
            if b < 32 and b ~= 10 and b ~= 13 and b ~= 9 then
                bad = bad + 1
            end
        end

        return bad <= 2
    end

    local function looks_like_game_description(text)
        if type(text) ~= 'string' or text == '' then
            return false
        end

        return text:match('DEF:%s*%d')
            or text:match('DMG:%s*%d')
            or text:match('HP[%+%-]%d')
            or text:match('MP[%+%-]%d')
            or text:match('STR[%+%-]%d')
            or text:match('INT[%+%-]%d')
            or text:match('"%s*[%w%s]+"')
            or text:match('Enchantment')
            or text:match('Latent effect')
            or text:match('Latent Effect')
            or text:match('Augment')
            or text:match('Regen')
            or text:match('Refresh')
            or text:match('Reraise')
    end

    local function finalize_description_text(raw)
        if not is_plausible_raw_description(raw) then
            return nil
        end

        local cleaned = normalize_description_text(raw)
        if cleaned == '' or looks_like_memory_dump(cleaned) then
            return nil
        end

        if is_plausible_description_text(cleaned) or looks_like_game_description(cleaned) then
            return cleaned
        end

        return nil
    end

    local function try_resolve_description(raw)
        if type(raw) ~= 'string' or raw == '' then
            return nil
        end

        local cleaned = finalize_description_text(raw)
        if cleaned then
            return cleaned
        end

        local coerced = coerce_resource_string(raw)
        return coerced and finalize_description_text(coerced) or nil
    end

    local function append_description_candidate(candidates, seen, raw)
        if type(raw) ~= 'string' or raw == '' then
            return
        end

        if seen[raw] then
            return
        end

        seen[raw] = true
        candidates[#candidates + 1] = raw
    end

    local function collect_description_candidates(item, item_id, resources)
        local candidates = {}
        local seen = {}

        if item and item.Description then
            for _, index in ipairs({ 1, 0, 2 }) do
                append_description_candidate(candidates, seen, read_resource_string_field(item.Description, index))
            end
        end

        if resources and item_id then
            local lookup_ids = { item_id }
            if item then
                local resource_id = tonumber(item.ResourceId)
                if resource_id and resource_id > 0 and resource_id ~= item_id then
                    lookup_ids[#lookup_ids + 1] = resource_id
                end
            end

            for _, string_key in ipairs({ 'items.descriptions', 'item.descriptions' }) do
                for _, lookup_id in ipairs(lookup_ids) do
                    local attempts = {
                        function() return resources:GetString(string_key, lookup_id) end,
                        function() return resources:GetString(string_key, lookup_id, 2) end,
                        function() return resources:GetString(string_key, lookup_id, 1) end,
                        function() return resources:GetString(string_key, lookup_id, 0) end,
                    }

                    for _, attempt in ipairs(attempts) do
                        local ok, value = pcall(attempt)
                        append_description_candidate(candidates, seen, ok and value or nil)
                    end
                end
            end
        end

        return candidates
    end

    local function get_item_description_text(item, item_id)
        if not item_id or item_id <= 0 then
            return ''
        end

        local cache_key = tostring(item_id)
        if description_text_cache[cache_key] ~= nil then
            return description_text_cache[cache_key]
        end

        if not item then
            item = M.get_item_resource(item_id)
        end

        local resolved = ''
        local resources = AshitaCore:GetResourceManager()
        for _, raw in ipairs(collect_description_candidates(item, item_id, resources)) do
            local cleaned = try_resolve_description(raw)
            if cleaned then
                resolved = cleaned
                break
            end
        end

        description_text_cache[cache_key] = resolved
        return resolved
    end

    local function measure_text_width(text)
        if type(text) ~= 'string' or text == '' then
            return 0
        end

        if text:find(WAVE_DASH_MARKER, 1, true) then
            local marker_width = tooltipfonts.measure_wave_dash_width()
            local _, marker_count = text:gsub(WAVE_DASH_MARKER, '')
            local placeholder = text:gsub(WAVE_DASH_MARKER, '~')
            local base_width = tooltipfonts.calc_text_width(placeholder)
            if marker_count > 0 then
                local tilde_width = tooltipfonts.calc_text_width('~')
                if tilde_width > 0 then
                    return base_width + (marker_width - tilde_width) * marker_count
                end
            end
            return base_width
        end

        return tooltipfonts.calc_text_width(text)
    end

    local function get_tooltip_layout_metrics()
        return tooltipfonts.get_metrics()
    end

    local function get_tooltip_wrap_width(lines, extra_width)
        local metrics = get_tooltip_layout_metrics()
        local target = tonumber(extra_width) or 0

        for _, line in ipairs(lines or {}) do
            if type(line) == 'string' and line ~= '' then
                target = math.max(target, measure_text_width(line))
            end
        end

        return math.min(metrics.max_width, target + metrics.width_pad)
    end

    local JOBS_FIRST_LINE_COUNT = 6
    local JOBS_CONTINUATION_LINE_COUNT = 8

    local function parse_job_tokens(jobs)
        local tokens = {}
        for job in jobs:gmatch('[^/]+') do
            if job ~= '' then
                tokens[#tokens + 1] = job
            end
        end
        return tokens
    end

    local function format_job_chunk(tokens, start_index, count)
        local end_index = math.min(start_index + count - 1, #tokens)
        if start_index > end_index then
            return '', end_index + 1
        end

        local parts = {}
        for index = start_index, end_index do
            parts[#parts + 1] = tokens[index]
        end

        local line = table.concat(parts, '/')
        if end_index < #tokens then
            line = line .. '/'
        end

        return line, end_index + 1
    end

    local function format_jobs_display_lines(level, jobs)
        jobs = jobs or ''
        if jobs == '' and not level then
            return {}
        end

        if jobs == '' then
            return { ('Lv.%d'):format(level) }
        end

        if not jobs:find('/', 1, true) then
            if level then
                return { ('Lv.%d %s'):format(level, jobs) }
            end
            return { jobs }
        end

        local tokens = parse_job_tokens(jobs)
        if #tokens == 0 then
            if level then
                return { ('Lv.%d'):format(level) }
            end
            return {}
        end

        local lines = {}
        local chunk, next_index = format_job_chunk(tokens, 1, JOBS_FIRST_LINE_COUNT)

        if level then
            lines[#lines + 1] = ('Lv.%d %s'):format(level, chunk)
        else
            lines[#lines + 1] = chunk
        end

        while next_index <= #tokens do
            chunk, next_index = format_job_chunk(tokens, next_index, JOBS_CONTINUATION_LINE_COUNT)
            lines[#lines + 1] = chunk
        end

        return lines
    end

    local function append_jobs_measure_lines(lines, level, jobs)
        for _, line in ipairs(format_jobs_display_lines(level, jobs)) do
            lines[#lines + 1] = line
        end
    end

    local function render_jobs_display(level, jobs, color)
        for _, line in ipairs(format_jobs_display_lines(level, jobs)) do
            imgui.TextColored(color, line)
        end
    end

    local function get_elemental_footer_entries(slot)
        local inv_item = get_inventory_item(slot)
        if not inv_item or type(inv_item.Extra) ~= 'string' or inv_item.Extra == '' then
            return {}
        end

        return augmentlogic.get_elemental_footer_entries(slot and slot.id, inv_item.Extra)
    end

    local function append_footer_measure_lines(lines, slot, item, item_type, enchant_info)
        local extra_width = 0
        local signature = get_item_signature_text(slot, item_type)
        if signature ~= '' then
            lines[#lines + 1] = ('[%s]'):format(signature)
        end

        local enchant_status = format_enchant_status(enchant_info)
        if enchant_status then
            lines[#lines + 1] = enchant_status
        end

        local item_level = get_item_level_value(item)
        if item_level then
            lines[#lines + 1] = ('<Item Level:%d>'):format(item_level)
        end

        local elemental_entries = get_elemental_footer_entries(slot)
        if #elemental_entries > 0 then
            extra_width = tooltipicons.measure_elemental_footer_width(
                satchel,
                addon_path,
                elemental_entries,
                tooltipicons.icons_as_words()
            )
        end

        return extra_width
    end

    local FOOTER_TEXT_COLOR = { 0.92, 0.92, 0.92, 1.0 }

    local function render_tooltip_footer_right(text, color)
        if type(text) ~= 'string' or text == '' then
            return
        end

        color = color or FOOTER_TEXT_COLOR
        local text_w = imgui.CalcTextSize(text)
        text_w = tonumber(text_w) or 0
        local right_x = math.max(0, (tonumber(imgui.GetWindowWidth()) or 0) - text_w - 10)
        imgui.SetCursorPosX(right_x)
        imgui.TextColored(color, text)
    end

    local function render_tooltip_footer(slot, item, item_type, enchant_info)
        local signature = get_item_signature_text(slot, item_type)
        if signature ~= '' then
            render_tooltip_footer_right(('[%s]'):format(signature))
        end

        local enchant_status = format_enchant_status(enchant_info)
        if enchant_status then
            render_tooltip_footer_right(enchant_status)
        end

        local item_level = get_item_level_value(item)
        if item_level then
            render_tooltip_footer_right(('<Item Level:%d>'):format(item_level))
        end

        local elemental_entries = get_elemental_footer_entries(slot)
        if #elemental_entries > 0 then
            tooltipicons.render_elemental_footer_right(satchel, addon_path, elemental_entries, FOOTER_TEXT_COLOR, tooltipicons.icons_as_words())
        end
    end

    local function append_description_measure_lines(lines, desc)
        if desc == '' then
            return
        end

        for line in (desc .. '\n'):gmatch('([^\n]*)\n') do
            if line ~= '' then
                lines[#lines + 1] = line
            end
        end
    end

    local function collect_tooltip_measure_lines(slot, item, item_name, item_type, enchant_info)
        local lines = { item_name or '' }
        local desc = get_item_description_text(item, slot and slot.id)

        if item_type == 4 or item_type == 5 then
            local level = item and read_number_field(item, 'Level') or nil
            local jobs = get_equip_jobs_text(item)
            local family = (item_type == 4) and get_weapon_type_text(item) or get_armor_type_text(item)
            local races = get_item_races_text(item)
            if races ~= '' then
                lines[#lines + 1] = ('(%s) %s'):format(family, races)
            else
                lines[#lines + 1] = ('(%s)'):format(family)
            end

            local dmg = item and read_number_field(item, 'Damage') or nil
            local def = item and read_number_field(item, 'Defense') or nil
            local delay = item and read_number_field(item, 'Delay') or nil
            local desc_has_combat_row = description_has_combat_stats(desc)
            local body_desc, _ = split_description_augment_lines(desc)

            if item_type == 4 then
                local combat_parts = {}
                if dmg then table.insert(combat_parts, ('DMG:%d'):format(dmg)) end
                if dmg and is_plausible_delay(delay) then
                    table.insert(combat_parts, ('Delay:%d'):format(delay))
                end
                if #combat_parts > 0 and not desc_has_combat_row then
                    lines[#lines + 1] = table.concat(combat_parts, '  ')
                end
            else
                if def then
                    lines[#lines + 1] = ('DEF:%d'):format(def)
                end
                if def and is_plausible_delay(delay) then
                    lines[#lines + 1] = ('Delay:%d'):format(delay)
                end
            end

            if body_desc ~= '' then
                local measure_desc = body_desc
                if item_type == 4 and not desc_has_combat_row then
                    measure_desc = filter_weapon_description_lines(body_desc)
                end
                append_description_measure_lines(lines, measure_desc)
            end

            for _, augment_line in ipairs(collect_augment_display_lines(slot, desc)) do
                lines[#lines + 1] = augment_line
            end

            append_jobs_measure_lines(lines, level, jobs)
        else
            append_description_measure_lines(lines, desc)
        end

        local footer_extra_width = append_footer_measure_lines(lines, slot, item, item_type, enchant_info)

        return lines, footer_extra_width
    end

    local function render_wrapped_gray_text(text, gray)
        gray = gray or { 0.88, 0.88, 0.88, 1.0 }
        render_tooltip_text_colored(gray, text)
    end

    local function render_desc_with_elements(text)
        local as_words = tooltipicons.icons_as_words()
        local metrics = tooltipfonts.get_metrics()
        local gray = { 0.88, 0.88, 0.88, 1.0 }

        for line in (text .. '\n'):gmatch('([^\n]*)\n') do
            if line == '' then
                imgui.Spacing()
            else
                local tokens = parse_description_line(line)
                local line_as_words = as_words or line:find('"', 1, true) ~= nil
                if line_as_words and tooltiplayout.line_needs_option_c(fix_known_element_placeholders(line), true) then
                    tooltiplayout.render_option_c_line(
                        fix_known_element_placeholders(line),
                        gray,
                        element_colors,
                        metrics.wrap_width,
                        metrics.family,
                        metrics.pixel_size,
                        render_tooltip_text_colored
                    )
                elseif line_has_element_tokens(tokens) then
                    adjust_element_token_spacing(tokens, line_as_words)
                    if line_as_words then
                        render_description_line_tokens(tokens, line_as_words)
                    else
                        render_description_line_tokens_hybrid(tokens)
                    end
                elseif line_as_words then
                    render_description_line_with_element_words(fix_known_element_placeholders(line))
                else
                    local has_elem_word = false
                    for _, elem in ipairs(element_list_ordered) do
                        if line:find(elem, 1, true) then
                            has_elem_word = true
                            break
                        end
                    end
                    if has_elem_word then
                        render_description_line_with_element_words(line)
                    else
                        render_wrapped_gray_text(line)
                    end
                end
            end
        end
    end

    function M.render_item_detail_tooltip(slot)
        if not slot or not slot.id or slot.id <= 0 then
            return
        end

        local catalog_only = slot.virtual == true
        tooltipicons.set_catalog_mode(catalog_only)

        local ok, err = pcall(function()
        local item = M.get_item_resource(slot.id)
        local item_name = M.get_item_name(slot.id)
        local item_type = M.get_item_type(slot.id)
        local enchant_info = get_enchantment_info(slot, item, item)
        local is_bazaar_listed = is_slot_in_bazaar(slot)
        local layout_metrics = get_tooltip_layout_metrics()

        imgui.BeginTooltip()
        local font_pushed = tooltipfonts.push_tooltip_font()
        local ok_render, render_err = pcall(function()
        local measure_lines, footer_extra_width = collect_tooltip_measure_lines(slot, item, item_name, item_type, enchant_info)
        if is_bazaar_listed then
            table.insert(measure_lines, 2, 'Listed in Bazaar (cannot use/equip)')
        end
        local wrap_width = get_tooltip_wrap_width(measure_lines, footer_extra_width)
        local body_start_x = imgui.GetCursorPosX()
        local tags = get_item_flag_tags(item, slot)
        if #tags > 0 then
            local tags_width = tooltipicons.measure_status_tags_width(
                satchel,
                addon_path,
                tags,
                tooltipicons.icons_as_words()
            )
            wrap_width = math.max(wrap_width, measure_text_width(item_name) + tags_width + layout_metrics.width_pad)
            wrap_width = math.min(layout_metrics.max_width, wrap_width)
        end
        local name_color = M.get_slot_border_color(slot)
        render_tooltip_header(item, slot, item_name, name_color, wrap_width, is_bazaar_listed)
        render_tooltip_name_separator(name_color)
        imgui.PushTextWrapPos(body_start_x + wrap_width)

        if item_type == 7 then
            local desc = get_item_description_text(item, slot.id)
            if desc ~= '' then
                render_desc_with_elements(desc)
            end
        elseif item_type == 4 or item_type == 5 then
            local dmg = item and read_number_field(item, 'Damage') or nil
            local def = item and read_number_field(item, 'Defense') or nil
            local delay = item and read_number_field(item, 'Delay') or nil
            local level = item and read_number_field(item, 'Level') or nil
            local jobs = get_equip_jobs_text(item)
            local races = get_item_races_text(item)
            local family = (item_type == 4) and get_weapon_type_text(item) or get_armor_type_text(item)
            local desc = get_item_description_text(item, slot.id)
            local desc_has_combat_row = description_has_combat_stats(desc)
            local body_desc, _ = split_description_augment_lines(desc)
            local augment_lines = collect_augment_display_lines(slot, desc)

            local has_stat = false

            if races ~= '' then
                imgui.Text(('(%s) %s'):format(family, races))
            else
                imgui.Text(('(%s)'):format(family))
            end

            if item_type == 4 then
                local combat_parts = {}
                if dmg then table.insert(combat_parts, ('DMG:%d'):format(dmg)) end
                if dmg and is_plausible_delay(delay) then
                    table.insert(combat_parts, ('Delay:%d'):format(delay))
                end
                if #combat_parts > 0 and not desc_has_combat_row then
                    imgui.Text(table.concat(combat_parts, '  '))
                    has_stat = true
                end
            else
                if def then
                    imgui.Text(('DEF:%d'):format(def))
                    has_stat = true
                end
                if def and is_plausible_delay(delay) then
                    imgui.Text(('Delay:%d'):format(delay))
                    has_stat = true
                end
            end

            if body_desc ~= '' then
                if item_type == 4 and not desc_has_combat_row then
                    body_desc = filter_weapon_description_lines(body_desc)
                end
                if body_desc ~= '' then
                    render_desc_with_elements(body_desc)
                    has_stat = true
                end
            end

            if #augment_lines > 0 then
                render_augment_display_lines(augment_lines)
                has_stat = true
            end

            local level_jobs_color = { 0.88, 0.88, 0.88, 1.0 }
            if level or jobs ~= '' then
                render_jobs_display(level, jobs, level_jobs_color)
                has_stat = true
            end

            if not has_stat then
                imgui.TextColored({ 0.72, 0.72, 0.72, 1.0 }, 'No additional stats found.')
            end
        else
            local desc = get_item_description_text(item, slot.id)
            if desc ~= '' then
                render_desc_with_elements(desc)
            end
        end

        render_tooltip_footer(slot, item, item_type, enchant_info)

        imgui.PopTextWrapPos()
        end)

        if font_pushed then
            tooltipfonts.pop_tooltip_font()
        end
        imgui.EndTooltip()

        if not ok_render then
            error(render_err)
        end
        end)

        tooltipicons.set_catalog_mode(false)
        if not ok then
            error(err)
        end
    end

    function M.get_slot_border_color(slot)
        if not slot.id or slot.id <= 0 then
            return satchelcolors.get_empty_slot_border()
        end

        if is_slot_in_bazaar(slot) then
            return satchelcolors.get_bazaar_border()
        end

        local item_type = M.get_item_type(slot.id)
        if item_type == 4 or item_type == 5 then
            return satchelcolors.get_equipment_border()
        end
        if item_type == 7 then
            return satchelcolors.get_usable_border()
        end

        return satchelcolors.get_item_border()
    end

    function M.get_context_menu_actions(slot)
        if not slot or slot.container_id == nil or not slot.id or slot.id <= 0 then
            return nil
        end

        local item_type    = M.get_item_type(slot.id)
        local item_res     = M.get_item_resource(slot.id)
        local item_name    = escape_command_text(M.get_item_name(slot.id))
        local in_inventory = (slot.container_id == 0)
        local in_bazaar    = is_slot_in_bazaar(slot)
        local in_wardrobe  = is_wardrobe_container(slot.container_id)
        local is_equipped  = is_slot_currently_equipped(slot)
        local item_flags   = get_effective_item_flags(item_res, slot)
        local is_exclusive = bit.band(item_flags, 0x4000) ~= 0
        local count        = tonumber(slot.count) or 1

        -- USE (consumables in inventory, or equipped gear with an available enchant use)
        local use_enabled = false
        local use_cmd = nil
        if not in_bazaar then
            if item_type == 7 and in_inventory then
                use_enabled = true
                use_cmd = ('/item "%s" <me>'):format(item_name)
            elseif (item_type == 4 or item_type == 5) and (in_inventory or in_wardrobe) and is_equipped then
                local enchant = get_enchantment_info(slot, item_res, item_res)
                if enchant and (tonumber(enchant.use_delay) or 0) <= 0 then
                    use_enabled = true
                    use_cmd = ('/item "%s" <me>'):format(item_name)
                end
            end
        end

        -- EQUIP
        local equip_enabled = false
        local equip_cmd = nil
        if not in_bazaar and (item_type == 4 or item_type == 5) and (in_inventory or in_wardrobe) and not is_equipped then
            local eq_slot = get_primary_equip_slot_name(item_res)
            if eq_slot then
                equip_enabled = true
                equip_cmd = ('/equip %s "%s"'):format(eq_slot, item_name)
            end
        end

        -- BAZAAR
        local bazaar_label    = in_bazaar and 'Modify/Unlist Bazaar' or 'List in Bazaar'
        local bazaar_kind     = 'bazaar_list'
        local bazaar_enabled  = in_inventory and not is_exclusive and not is_equipped
        local bazaar_tooltip  = is_exclusive and 'EX items cannot be listed in Bazaar'
                             or (is_equipped and 'Unequip the item before listing in Bazaar')
                             or nil
        local bazaar_price    = 0
        if in_bazaar then
            local inv_item = get_inventory_item(slot)
            bazaar_price = inv_item and (tonumber(inv_item.Price) or 0) or 0
        end

        -- DROP
        local drop_enabled = in_inventory and not in_bazaar and not is_equipped
        local drop_tooltip = (not in_inventory and 'Move the item to Inventory before dropping')
                          or (in_bazaar and 'Unlist the item from Bazaar before dropping')
                          or (is_equipped and 'Unequip the item before dropping')
                          or nil

        -- SPLIT
        local split_enabled = in_inventory and not in_bazaar and count > 1

        return {
            { label = 'Use',          enabled = use_enabled,    command = use_cmd },
            { label = 'Equip',        enabled = equip_enabled,  command = equip_cmd },
            { separator = true },
            { label = bazaar_label,   enabled = bazaar_enabled, kind = bazaar_kind, tooltip = bazaar_tooltip, bazaar_price = bazaar_price },
            { label = 'Drop Item...', enabled = drop_enabled,   kind = 'drop', tooltip = drop_tooltip },
            { label = 'Split...',     enabled = split_enabled,  kind = 'split' },
        }
    end

    function M.build_right_click_command(slot)
        if not slot or slot.container_id == nil or not slot.id or slot.id <= 0 then
            return nil
        end

        if is_slot_in_bazaar(slot) then
            return nil
        end

        local item_type = M.get_item_type(slot.id)
        local item_resource = M.get_item_resource(slot.id)
        local item_name = escape_command_text(M.get_item_name(slot.id))
        if item_name == '' then
            return nil
        end

        if item_type == 7 then
            if slot.container_id == 0 then
                return ('/item "%s" <me>'):format(item_name)
            end
            return nil
        end

        if item_type == 4 or item_type == 5 then
            if slot.container_id == 0 or is_wardrobe_container(slot.container_id) then
                local enchant_info = get_enchantment_info(slot, item_resource, item_resource)
                local is_equipped = is_slot_currently_equipped(slot)
                local is_ready_to_use = enchant_info and (tonumber(enchant_info.use_delay) or 0) <= 0

                if is_equipped and is_ready_to_use then
                    return ('/item "%s" <me>'):format(item_name)
                end

                local equip_slot = get_primary_equip_slot_name(item_resource)
                if equip_slot then
                    return ('/equip %s "%s"'):format(equip_slot, item_name)
                end
            end
        end

        return nil
    end

    local function item_has_slot(item, mask)
        if not item then
            return false
        end
        local slots = tonumber(item.Slots) or 0
        return bit.band(slots, mask) ~= 0
    end

    local function is_crystal_item_name(item_name)
        local name = (item_name or ''):lower()
        return name:find(' crystal', 1, true) ~= nil
    end

    local function is_cluster_item_name(item_name)
        local name = (item_name or ''):lower()
        return name:find('cluster', 1, true) ~= nil
    end

    local function is_inventory_key_item(item_id, item_resource, item_name)
        local item_type = M.get_item_type(item_id)
        if item_type == 2 then
            return true
        end
        local name = (item_name or ''):lower()
        return name:find('key item', 1, true) ~= nil
    end

    local function normalize_search_query(query)
        if type(query) ~= 'string' then
            return ''
        end
        return trim_text(query):lower()
    end

    local function compact_search_query(query)
        return normalize_search_query(query):gsub('%s+', '')
    end

    local function escape_pattern(text)
        return (text:gsub('[%%^$().%[%]*+%?-]', '%%%1'))
    end

    local function name_matches_word_start(item_name, query)
        if type(item_name) ~= 'string' or item_name == '' or query == '' then
            return false
        end

        local lowered_name = item_name:lower()
        local pattern = '^' .. escape_pattern(query)

        if lowered_name:find(pattern, 1) then
            return true
        end

        for word in lowered_name:gmatch('[%w\']+') do
            if word:find(pattern, 1) then
                return true
            end
        end

        return false
    end

    local function get_item_job_mask(item)
        if not item then
            return nil
        end

        local mask_fields = { 'Jobs', 'JobMask', 'EquipJobs', 'JobsMask' }
        for _, field_name in ipairs(mask_fields) do
            local n = read_number_field(item, field_name)
            if n then
                return n
            end
        end

        local probes = {
            function() return item.Jobs and item.Jobs[1] end,
            function() return item.Jobs and item.Jobs[0] end,
            function() return item.EquipJobs and item.EquipJobs[1] end,
            function() return item.EquipJobs and item.EquipJobs[0] end,
        }
        for _, probe in ipairs(probes) do
            local ok, val = pcall(probe)
            if ok then
                local n = tonumber(val)
                if n and n > 0 then
                    return n
                end
            end
        end

        return nil
    end

    local function job_query_matches_entry(query, abbr, full_name)
        query = query:lower()
        abbr = (abbr or ''):lower()
        full_name = (full_name or ''):lower()

        if query == abbr or query == full_name then
            return true
        end

        if full_name:find('%s') then
            local compact_query = query:gsub('%s+', '')
            local compact_name = full_name:gsub('%s+', '')
            if compact_query ~= '' and compact_query == compact_name then
                return true
            end
        end

        return false
    end

    local function matches_job_requirement(item, normalized, compact)
        if normalized == '' then
            return false
        end

        local mask = get_item_job_mask(item)
        if not mask then
            return false
        end

        if normalized == 'all jobs' or compact == 'alljobs' then
            local count = 0
            for i = 1, 22 do
                if bit.band(mask, bit.lshift(1, i)) ~= 0 then
                    count = count + 1
                end
            end
            return count == 22
        end

        for i = 1, 22 do
            if bit.band(mask, bit.lshift(1, i)) ~= 0 then
                local abbr = job_abbr[i]
                local full_name = job_full_names[i]
                if job_query_matches_entry(normalized, abbr, full_name) then
                    return true
                end
                if compact ~= '' and compact ~= normalized
                    and job_query_matches_entry(compact, abbr, full_name) then
                    return true
                end
            end
        end

        return false
    end

    local function append_description_search_lines(parts, text)
        if type(text) ~= 'string' or text == '' then
            return
        end

        text = fix_known_element_placeholders(text)
        for line in (text .. '\n'):gmatch('([^\n]*)\n') do
            if line ~= '' then
                parts[#parts + 1] = line:lower()
            end
        end
    end

    local function get_item_search_blob(item_id, slot)
        local cache_key = tostring(item_id or 0)
        if slot and slot.container_id ~= nil and slot.slot_index ~= nil then
            cache_key = ('%s:%s:%s'):format(item_id, slot.container_id, slot.slot_index)
        end

        local cached = search_text_cache[cache_key]
        if cached then
            return cached
        end

        local parts = {}
        local item = M.get_item_resource(item_id)
        local item_type = M.get_item_type(item_id)
        local item_name = M.get_item_name(item_id)
        if item_name ~= '' then
            parts[#parts + 1] = item_name:lower()
        end

        local desc = get_item_description_text(item, item_id)
        local searchable_desc = desc

        if item_type == 4 or item_type == 5 then
            local family = (item_type == 4) and get_weapon_type_text(item) or get_armor_type_text(item)
            local races = get_item_races_text(item)
            if races ~= '' then
                parts[#parts + 1] = ('(%s) %s'):format(family, races):lower()
            else
                parts[#parts + 1] = ('(%s)'):format(family):lower()
            end

            if family ~= '' then
                parts[#parts + 1] = family:lower()
            end

            local desc_has_combat_row = description_has_combat_stats(desc)
            searchable_desc = select(1, split_description_augment_lines(desc))

            if item_type == 4 then
                local dmg = item and read_number_field(item, 'Damage') or nil
                local delay = item and read_number_field(item, 'Delay') or nil
                if dmg and not desc_has_combat_row then
                    local combat_line = ('dmg:%d'):format(dmg)
                    if is_plausible_delay(delay) then
                        combat_line = combat_line .. ('  delay:%d'):format(delay)
                    end
                    parts[#parts + 1] = combat_line:lower()
                end
                if searchable_desc ~= '' and not desc_has_combat_row then
                    searchable_desc = filter_weapon_description_lines(searchable_desc)
                end
            else
                local def = item and read_number_field(item, 'Defense') or nil
                local delay = item and read_number_field(item, 'Delay') or nil
                if def and not desc_has_combat_row then
                    parts[#parts + 1] = ('def:%d'):format(def):lower()
                end
                if def and is_plausible_delay(delay) and not desc_has_combat_row then
                    parts[#parts + 1] = ('delay:%d'):format(delay):lower()
                end
            end

        end

        append_description_search_lines(parts, searchable_desc ~= '' and searchable_desc or desc)

        if slot then
            for _, augment_line in ipairs(collect_augment_display_lines(slot, desc)) do
                parts[#parts + 1] = augment_line:lower()
            end

            local enchant_info = get_enchantment_info(slot, item, item)
            local enchant_status = format_enchant_status(enchant_info)
            if enchant_status then
                parts[#parts + 1] = enchant_status:lower()
            end

            local signature = get_item_signature_text(slot, item_type)
            if signature ~= '' then
                parts[#parts + 1] = ('[%s]'):format(signature):lower()
            end

            local item_level = get_item_level_value(item)
            if item_level then
                parts[#parts + 1] = ('<item level:%d>'):format(item_level):lower()
            end
        end

        local blob = table.concat(parts, '\n')
        search_text_cache[cache_key] = blob
        return blob
    end

    function M.matches_search(slot_or_id, query)
        local slot = type(slot_or_id) == 'table' and slot_or_id or nil
        local item_id = slot and slot.id or slot_or_id
        if not item_id or item_id <= 0 then
            return false
        end

        local normalized = normalize_search_query(query)
        if normalized == '' then
            return true
        end

        local compact = compact_search_query(query)
        local item_name = M.get_item_name(item_id)
        if name_matches_word_start(item_name, normalized) then
            return true
        end

        local item_type = M.get_item_type(item_id)
        local item_resource = M.get_item_resource(item_id)

        local function query_is(...)
            for i = 1, select('#', ...) do
                local candidate = select(i, ...)
                if normalized == candidate or compact == candidate then
                    return true
                end
            end
            return false
        end

        if query_is('crystal', 'crystals') then
            return is_crystal_item_name(item_name)
        end
        if query_is('cluster', 'clusters') then
            return is_cluster_item_name(item_name)
        end
        if query_is('usable') then
            return item_type == 7
        end
        if query_is('weapon', 'weapons') then
            return item_type == 4
        end
        if query_is('armor') then
            return item_type == 5
        end
        if query_is('key item', 'key items', 'keyitem', 'keyitems') then
            return is_inventory_key_item(item_id, item_resource, item_name)
        end
        if query_is('main') then
            return item_has_slot(item_resource, weapon_slot_masks.main)
        end
        if query_is('sub') then
            return item_has_slot(item_resource, weapon_slot_masks.sub)
        end
        if query_is('range') then
            return item_has_slot(item_resource, weapon_slot_masks.range)
        end
        if query_is('ammo') then
            return item_has_slot(item_resource, weapon_slot_masks.ammo)
        end
        if query_is('head') then
            return item_has_slot(item_resource, armor_slot_masks.head)
        end
        if query_is('body') then
            return item_has_slot(item_resource, armor_slot_masks.body)
        end
        if query_is('hand', 'hands') then
            return item_has_slot(item_resource, armor_slot_masks.hands)
        end
        if query_is('leg', 'legs') then
            return item_has_slot(item_resource, armor_slot_masks.legs)
        end
        if query_is('foot', 'feet') then
            return item_has_slot(item_resource, armor_slot_masks.feet)
        end
        if query_is('neck') then
            return item_has_slot(item_resource, armor_slot_masks.neck)
        end
        if query_is('waist') then
            return item_has_slot(item_resource, armor_slot_masks.waist)
        end
        if query_is('back') then
            return item_has_slot(item_resource, armor_slot_masks.back)
        end
        if query_is('ear', 'ears') then
            return item_has_slot(item_resource, armor_slot_masks.ear)
        end
        if query_is('ring', 'rings') then
            return item_has_slot(item_resource, armor_slot_masks.ring)
        end

        if matches_job_requirement(item_resource, normalized, compact) then
            return true
        end

        local search_blob = get_item_search_blob(item_id, slot)

        if item_type == 4 and searchlogic.matches_weapon_alias(item_resource, normalized, compact, read_number_field) then
            return true
        end

        if searchlogic.blob_matches_query(search_blob, normalized, compact) then
            return true
        end

        return false
    end

    return M
end

return {
    create = create_item_logic,
}
