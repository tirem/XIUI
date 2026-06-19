local containerlogic = {}

local CONTAINER_SUPPORT_CACHE_SECONDS = 5.0

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

    -- Mog Safe is always available in supported environments and should never be hidden.
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

    local function is_container_supported(container_id, max_slots)
        local cid = tonumber(container_id)
        local total = tonumber(max_slots) or 0
        if cid == nil or total <= 0 then
            return false
        end

        local cache_root = satchel and satchel.container_support_cache
        if not cache_root and satchel then
            satchel.container_support_cache = {}
            cache_root = satchel.container_support_cache
        end

        local now = os.clock()
        local cache = cache_root and cache_root[cid]
        if cache and cache.checked_at and ((now - cache.checked_at) < CONTAINER_SUPPORT_CACHE_SECONDS) then
            return cache.value == true
        end

        local used = tonumber(inv:GetContainerCount(cid) or -1) or -1
        if used < 0 or used > total then
            if cache_root then
                cache_root[cid] = { checked_at = now, value = false }
            end
            return false
        end

        local sample_count = math.min(total, 3)
        for slot_index = 1, sample_count do
            local ok, item = pcall(function()
                return inv:GetContainerItem(cid, slot_index)
            end)
            if not ok then
                if cache_root then
                    cache_root[cid] = { checked_at = now, value = false }
                end
                return false
            end

            local raw_index = item and tonumber(item.Index) or 0
            if raw_index < 0 or raw_index > 255 then
                if cache_root then
                    cache_root[cid] = { checked_at = now, value = false }
                end
                return false
            end
        end

        if cache_root then
            cache_root[cid] = { checked_at = now, value = true }
        end
        return true
    end

    local function is_container_enabled(container_id, max_slots)
        local cid = tonumber(container_id)
        if cid == nil then
            return false
        end

        local total = tonumber(max_slots) or 0

        -- Mog Safe is always available when allocated.
        if cid == 1 then
            return total > 0
        end

        -- Safe2 is a phantom on Horizon: it reports a non-zero size like a real bag but is
        -- never actually accessible, and is byte-identical to a legitimate empty Safe2 (so
        -- no packet/memory check can catch it). Hide it in limited mode; retail/LSB falls
        -- through to the normal size/slot detection below.
        if cid == 9 and HzLimitedMode then
            return false
        end

        return is_container_supported(cid, total)
    end

    local show_empty_slots = satchel.settings.show_empty_slots == true

    for _, container_id in ipairs(satchel.settings.include_containers) do
        local max_slots = inv:GetContainerCountMax(container_id) or 0
        if not is_container_enabled(container_id, max_slots) then
            goto continue
        end

        local container_slots = {}
        slots_by_container[container_id] = container_slots
        local used_slots = tonumber(inv:GetContainerCount(container_id) or 0) or 0
        stats[container_id] = { used = used_slots, total = max_slots }
        stats.all.total = stats.all.total + max_slots
        stats.all.used = stats.all.used + used_slots

        for memory_slot_index = 1, max_slots do
            local item_id = 0
            local item_count = 0
            local property_index = memory_slot_index

            local ok, item = pcall(function()
                return inv:GetContainerItem(container_id, memory_slot_index)
            end)

            if ok and item and item.Id and item.Id > 0 and item.Id ~= 65535 then
                item_id = tonumber(item.Id) or 0
                item_count = tonumber(item.Count) or 1
                property_index = tonumber(item.Index) or property_index
            elseif ok and item and item.Index then
                property_index = tonumber(item.Index) or property_index
            end

            if show_empty_slots or item_id > 0 then
                local entry = {
                    container_id = container_id,
                    slot_index = memory_slot_index - 1,
                    property_index = property_index,
                    id = item_id,
                    count = item_count,
                }
                all_slots[#all_slots + 1] = entry
                container_slots[#container_slots + 1] = entry
            end
        end

        ::continue::
    end

    return all_slots, slots_by_container, stats
end

function containerlogic.format_tab_label(container_id)
    return containerlogic.container_names[container_id] or ('Bag ' .. tostring(container_id))
end

function containerlogic.is_tab_available(container_id, stats)
    if tonumber(container_id) == 3 then
        return false
    end

    local s = stats[container_id]
    if not s then
        return false
    end

    return (s.total or 0) > 0
end

return containerlogic
