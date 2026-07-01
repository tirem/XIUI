local containerlogic = {}

containerlogic.DISPLAY_SLOTS = 80
containerlogic.SCAN_CONTAINERS = { 0, 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }

containerlogic.container_names = {
    [0] = 'Inventory',
    [1] = 'Safe',
    [2] = 'Storage',
    [3] = 'Temporary',
    [4] = 'Locker',
    [5] = 'Satchel',
    [6] = 'Sack',
    [7] = 'Case',
    [8] = 'Wardrobe1',
    [9] = 'Safe2',
    [10] = 'Wardrobe2',
    [11] = 'Wardrobe3',
    [12] = 'Wardrobe4',
    [13] = 'Wardrobe5',
    [14] = 'Wardrobe6',
    [15] = 'Wardrobe7',
    [16] = 'Wardrobe8',
}

containerlogic.tab_order = { 0, 1, 9, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16 }

local canonical_containers = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }

local function append_unique(list, value)
    for _, existing in ipairs(list) do
        if tonumber(existing) == tonumber(value) then
            return
        end
    end
    list:append(value)
end

function containerlogic.normalize_include_containers(value)
    local existing = {}
    if type(value) == 'table' then
        for _, v in ipairs(value) do
            local id = tonumber(v)
            if id then
                existing[id] = true
            end
        end
    end

    local normalized = T{}
    for _, id in ipairs(canonical_containers) do
        if existing[id] or value == nil then
            normalized:append(id)
        end
    end

    if #normalized == 0 then
        normalized = T{}
        for _, id in ipairs(canonical_containers) do
            normalized:append(id)
        end
    end

    append_unique(normalized, 1)

    return normalized
end

function containerlogic.build_slot_data(satchel)
    local all_slots = {}
    local slots_by_container = {}
    local stats = {
        all = { used = 0, total = 0 },
    }

    local inv = AshitaCore:GetMemoryManager():GetInventory()
    if not inv then
        return all_slots, slots_by_container, stats
    end

    for _, container_id in ipairs(satchel.settings.include_containers) do
        local cid = tonumber(container_id)
        if cid == nil or (cid == 9 and HzLimitedMode) then
            goto continue
        end

        local memory_max = tonumber(inv:GetContainerCountMax(cid) or 0) or 0
        if cid == 3 then
            local used_count = memory_max > 0 and (tonumber(inv:GetContainerCount(cid) or 0) or 0) or 0
            if used_count <= 0 then
                goto continue
            end
        elseif memory_max <= 0 then
            goto continue
        end

        local accessible_slots = math.min(containerlogic.DISPLAY_SLOTS, memory_max)
        local used_slots = 0
        if memory_max > 0 then
            used_slots = tonumber(inv:GetContainerCount(cid) or 0) or 0
        end

        local container_slots = {}
        slots_by_container[cid] = container_slots
        stats[cid] = {
            used = used_slots,
            total = accessible_slots,
            display = containerlogic.DISPLAY_SLOTS,
        }
        stats.all.total = stats.all.total + accessible_slots
        stats.all.used = stats.all.used + used_slots

        for memory_slot_index = 1, containerlogic.DISPLAY_SLOTS do
            local item_id = 0
            local item_count = 0
            local property_index = memory_slot_index
            local locked = memory_slot_index > accessible_slots

            if memory_slot_index <= memory_max then
                local ok, item = pcall(inv.GetContainerItem, inv, cid, memory_slot_index)
                if ok and item and item.Id and item.Id > 0 and item.Id ~= 65535 then
                    item_id = tonumber(item.Id) or 0
                    item_count = tonumber(item.Count) or 1
                    local item_index = tonumber(item.Index)
                    if item_index and item_index > 0 then
                        property_index = item_index
                    end
                end
            end

            local entry = {
                container_id = cid,
                slot_index = memory_slot_index - 1,
                property_index = property_index,
                id = item_id,
                count = item_count,
                locked = locked,
            }
            all_slots[#all_slots + 1] = entry
            container_slots[#container_slots + 1] = entry
        end

        ::continue::
    end

    return all_slots, slots_by_container, stats
end

-- True when an accessible empty slot appears before a later occupied slot.
function containerlogic.has_internal_gap(slots)
    local saw_empty = false
    for _, slot in ipairs(slots or {}) do
        if slot.locked then
            break
        end

        local has_item = slot.id and slot.id > 0
        if not has_item then
            saw_empty = true
        elseif saw_empty then
            return true
        end
    end

    return false
end

-- Client-side display order: occupied slots first, then empties, then locked.
-- Each slot keeps its real memory slot_index for move packets.
function containerlogic.pack_slots_for_display(slots)
    local occupied = {}
    local empty_accessible = {}
    local locked = {}

    for _, slot in ipairs(slots or {}) do
        if slot.locked then
            locked[#locked + 1] = slot
        elseif slot.id and slot.id > 0 then
            occupied[#occupied + 1] = slot
        else
            empty_accessible[#empty_accessible + 1] = slot
        end
    end

    local packed = {}
    for _, slot in ipairs(occupied) do
        packed[#packed + 1] = slot
    end
    for _, slot in ipairs(empty_accessible) do
        packed[#packed + 1] = slot
    end
    for _, slot in ipairs(locked) do
        packed[#packed + 1] = slot
    end

    return packed
end

function containerlogic.sort_slots_for_display(slots, get_sort_key_fn, get_name_fn)
    local occupied = {}
    local empty_accessible = {}
    local locked = {}

    for _, slot in ipairs(slots or {}) do
        if slot.locked then
            locked[#locked + 1] = slot
        elseif slot.id and slot.id > 0 then
            occupied[#occupied + 1] = slot
        else
            empty_accessible[#empty_accessible + 1] = slot
        end
    end

    table.sort(occupied, function(a, b)
        local primary_a, secondary_a = get_sort_key_fn(a.id)
        local primary_b, secondary_b = get_sort_key_fn(b.id)
        if primary_a ~= primary_b then
            return primary_a < primary_b
        end
        if secondary_a ~= secondary_b then
            return secondary_a < secondary_b
        end
        local name_a = get_name_fn(a.id) or ''
        local name_b = get_name_fn(b.id) or ''
        if name_a ~= name_b then
            return name_a < name_b
        end
        return (tonumber(a.slot_index) or 0) < (tonumber(b.slot_index) or 0)
    end)

    local sorted = {}
    for _, slot in ipairs(occupied) do
        sorted[#sorted + 1] = slot
    end
    for _, slot in ipairs(empty_accessible) do
        sorted[#sorted + 1] = slot
    end
    for _, slot in ipairs(locked) do
        sorted[#sorted + 1] = slot
    end

    return sorted
end

function containerlogic.should_use_visual_compact(container_id, slots, used_count, usage_snapshot)
    usage_snapshot = usage_snapshot or {}
    container_id = tonumber(container_id)
    used_count = tonumber(used_count) or 0

    local snapshot_key = container_id
    local previous_used = usage_snapshot[snapshot_key]
    usage_snapshot[snapshot_key] = used_count

    if previous_used ~= nil and used_count > previous_used then
        return false
    end

    return containerlogic.has_internal_gap(slots)
end

function containerlogic.apply_visual_layout(slots, use_compact)
    if use_compact then
        return containerlogic.pack_slots_for_display(slots)
    end
    return slots or {}
end

function containerlogic.format_tab_label(container_id)
    return containerlogic.container_names[container_id] or ('Bag ' .. tostring(container_id))
end

function containerlogic.is_tab_available(container_id, stats)
    if tonumber(container_id) == 9 and HzLimitedMode then
        return false
    end

    local s = stats[container_id]
    if not s then
        return false
    end

    return (s.total or 0) > 0
end

return containerlogic
