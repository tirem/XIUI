local breader = require('bitreader')
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

    function M.clear_caches()
        satchel.names = {}
        satchel.item_types = {}
        satchel.item_sort_keys = {}
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
        if not slot or slot.container_id == nil or not slot.id or slot.id <= 0 then
            return nil
        end

        local source_container_id = tonumber(slot.container_id)
        local target_container = tonumber(target_container_id)
        if not source_container_id or not target_container then
            return nil
        end

        if source_container_id == target_container then
            return nil
        end

        local move_count = tonumber(slot.count) or 1
        if move_count < 1 then
            move_count = 1
        end

        local source_index = tonumber(slot.property_index)
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

        return ('<%s %s/[%s, %s]>'):format(uses_text or '--/--', current_timer_text, reuse_text, equip_text)
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

        return table.concat(jobs, ' ')
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

    local function get_item_flags_text(item)
        if not item then
            return ''
        end

        local ok, raw = pcall(function() return item.Flags end)
        local flags_val = (ok and tonumber(raw)) or 0
        local flags = {}

        if bit.band(flags_val, 0x8000) ~= 0 then table.insert(flags, 'RARE') end
        if bit.band(flags_val, 0x4000) ~= 0 then table.insert(flags, 'EX') end

        return table.concat(flags, ' ')
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

    local function normalize_description_text(value)
        if type(value) ~= 'string' then
            return ''
        end

        local text = value
        text = text:gsub('\r\n', '\n')
        text = text:gsub('\r', '\n')

        text = text:gsub('\239\191\189', '?')
        text = text:gsub('\239\188\133', '%%')
        local element_icon_names = { 'Fire', 'Ice', 'Wind', 'Earth', 'Lightning', 'Water', 'Light', 'Dark' }
        text = text:gsub('\239(.)', function(b)
            local b_byte = b:byte(1)
            if b_byte >= 31 and b_byte <= 38 then
                return element_icon_names[b_byte - 30] .. ' '
            end
            return ''
        end)

        text = text:gsub('\30.', '')
        text = text:gsub('\31.', '')
        text = text:gsub('[%z\1-\8\11\12\14-\31]', ' ')
        text = text:gsub('\194\160', ' ')

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

    local function get_item_description_text(item, item_id)
        local resources = AshitaCore:GetResourceManager()
        if resources and item_id and item_id > 0 then
            local ok_string, value = pcall(function()
                return resources:GetString('items.descriptions', item_id)
            end)
            if ok_string and type(value) == 'string' then
                local cleaned = normalize_description_text(value)
                cleaned = fix_known_element_placeholders(cleaned)
                if cleaned ~= '' and not cleaned:find('userdata', 1, true) then
                    return cleaned
                end
            end
        end

        if not item then
            return ''
        end

        local candidates = {
            function() return item.Description and item.Description[1] end,
            function() return item.Description and item.Description[0] end,
            function() return item.Description and item.Description[2] end,
            function() return item.Description and item.Description:get() end,
            function() return item.Description and tostring(item.Description) end,
        }

        for _, getter in ipairs(candidates) do
            local ok, val = pcall(getter)
            if ok and type(val) == 'string' then
                local cleaned = normalize_description_text(val)
                cleaned = fix_known_element_placeholders(cleaned)
                if cleaned ~= '' and not cleaned:find('userdata', 1, true) then
                    return cleaned
                end
            end
        end

        return ''
    end

    local function render_desc_with_elements(text)
        local gray = {0.88, 0.88, 0.88, 1.0}
        local lines = {}
        local s = 1
        while true do
            local nl = text:find('\n', s, true)
            if nl then
                table.insert(lines, text:sub(s, nl - 1))
                s = nl + 1
            else
                table.insert(lines, text:sub(s))
                break
            end
        end

        for _, line in ipairs(lines) do
            if line == '' then
                imgui.Spacing()
            else
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
                            table.insert(tokens, {kind = 'text', value = line:sub(pos, best_s - 1)})
                        end
                        table.insert(tokens, {kind = 'elem', value = best_elem})
                        pos = best_e + 1
                    else
                        table.insert(tokens, {kind = 'text', value = line:sub(pos)})
                        break
                    end
                end
                for ti, token in ipairs(tokens) do
                    if ti > 1 then imgui.SameLine(0, 0) end
                    if token.kind == 'elem' then
                        imgui.TextColored(element_colors[token.value], token.value)
                    else
                        imgui.TextColored(gray, (token.value:gsub('%%', '%%%%')))
                    end
                end
            end
        end
    end

    function M.render_item_detail_tooltip(slot)
        local item = M.get_item_resource(slot.id)
        local item_name = M.get_item_name(slot.id)
        local item_type = M.get_item_type(slot.id)
        local enchant_info = get_enchantment_info(slot, item, item)
        local is_bazaar_listed = is_slot_in_bazaar(slot)

        imgui.BeginTooltip()
        imgui.TextColored({ 1.0, 0.9, 0.55, 1.0 }, item_name)
        
        local flags_text = get_item_flags_text(item)
        if flags_text ~= '' then
            imgui.SameLine(0, 20)
            imgui.TextColored({ 1.0, 0.2, 0.2, 1.0 }, flags_text)
        end
        
        if is_bazaar_listed then
            imgui.TextColored({ 0.95, 0.32, 0.32, 1.0 }, 'Listed in Bazaar (cannot use/equip)')
        end

        if item_type == 7 then
            local desc = get_item_description_text(item, slot.id)
            if desc ~= '' then
                imgui.Separator()
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

            local desc_has_combat_row = false
            if desc ~= '' then
                for line in (desc .. '\n'):gmatch('([^\n]*)\n') do
                    if line:match('^%s*DMG:%s*[+%-]?%d+%s+Delay:%s*[+%-]?%d+%s*$') then
                        desc_has_combat_row = true
                        break
                    end
                end
            end

            local has_stat = false

            if races ~= '' then
                imgui.Text(('(%s) %s'):format(family, races))
            else
                imgui.Text(('(%s)'):format(family))
            end

            if item_type == 4 then
                local combat_parts = {}
                if dmg then table.insert(combat_parts, ('DMG:%d'):format(dmg)) end
                if delay then table.insert(combat_parts, ('Delay:%d'):format(delay)) end
                if #combat_parts > 0 and not desc_has_combat_row then
                    imgui.Text(table.concat(combat_parts, '  '))
                    has_stat = true
                end
            else
                if def then
                    imgui.Text(('DEF:%d'):format(def))
                    has_stat = true
                end
                if delay then
                    imgui.Text(('Delay:%d'):format(delay))
                    has_stat = true
                end
            end

            if desc ~= '' then
                if item_type == 4 and not desc_has_combat_row then
                    -- Strip the basic DMG/Delay line when we already rendered weapon stats above.
                    local filtered_lines = {}
                    for line in (desc .. '\n'):gmatch('([^\n]*)\n') do
                        if not line:match('^%s*DMG:%s*[+%-]?%d+%s+Delay:%s*[+%-]?%d+%s*$') then
                            table.insert(filtered_lines, line)
                        end
                    end
                    -- Remove leading/trailing empty lines
                    while #filtered_lines > 0 and filtered_lines[1] == '' do table.remove(filtered_lines, 1) end
                    while #filtered_lines > 0 and filtered_lines[#filtered_lines] == '' do table.remove(filtered_lines) end
                    desc = table.concat(filtered_lines, '\n')
                end
                if desc ~= '' then
                    render_desc_with_elements(desc)
                    has_stat = true
                end
            end

            local level_jobs_parts = {}
            if level then table.insert(level_jobs_parts, ('Lv.%d'):format(level)) end
            if jobs ~= '' then table.insert(level_jobs_parts, jobs) end
            if #level_jobs_parts > 0 then
                imgui.TextWrapped(table.concat(level_jobs_parts, '  '))
                has_stat = true
            end

            local enchant_status = format_enchant_status(enchant_info)
            if enchant_status then
                imgui.Text(enchant_status)
                has_stat = true
            end

            if not has_stat then
                imgui.TextColored({ 0.72, 0.72, 0.72, 1.0 }, 'No additional stats found.')
            end
        else
            local desc = get_item_description_text(item, slot.id)
            if desc ~= '' then
                imgui.Separator()
                render_desc_with_elements(desc)
            end
        end

        local signature = get_item_signature_text(slot, item_type)
        if signature ~= '' then
            local signature_text = ('[%s]'):format(signature)
            local text_w = imgui.CalcTextSize(signature_text)
            text_w = tonumber(text_w) or 0

            local right_x = math.max(0, (tonumber(imgui.GetWindowWidth()) or 0) - text_w - 10)
            imgui.SameLine(right_x)
            imgui.TextColored({ 0.92, 0.92, 0.92, 1.0 }, signature_text)
        end

        imgui.EndTooltip()
    end

    function M.get_slot_border_color(slot)
        if not slot.id or slot.id <= 0 then
            return { 0.28, 0.28, 0.28, 0.80 }
        end

        if is_slot_in_bazaar(slot) then
            return { 0.92, 0.22, 0.22, 1.0 }
        end

        local item_type = M.get_item_type(slot.id)
        if item_type == 4 or item_type == 5 then
            return { 0.35, 0.63, 0.95, 1.0 }
        end
        if item_type == 7 then
            return { 0.58, 0.86, 0.50, 1.0 }
        end

        return { 0.72, 0.60, 0.35, 1.0 }
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
        local item_flags   = item_res and (tonumber(item_res.Flags) or 0) or 0
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

    function M.matches_search(item_id, query)
        if not item_id or item_id <= 0 then
            return false
        end

        local normalized = normalize_search_query(query)
        if normalized == '' then
            return true
        end

        local compact = compact_search_query(query)
        local item_name = M.get_item_name(item_id)
        local lowered_name = item_name:lower()

        if lowered_name:find(normalized, 1, true) then
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

        return false
    end

    return M
end

return {
    create = create_item_logic,
}
