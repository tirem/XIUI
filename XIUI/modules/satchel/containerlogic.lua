local containerlogic = {}

local SAFE2_MIRROR_CACHE_SECONDS = 2.0
local SAFE2_SUPPORT_CACHE_SECONDS = 5.0
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

    local function does_safe2_mirror_safe()
        local cache = satchel and satchel.safe2_mirror_cache
        local now = os.clock()
        if cache and cache.checked_at and ((now - cache.checked_at) < SAFE2_MIRROR_CACHE_SECONDS) then
            return cache.value == true
        end

        local safe_max = tonumber(inv:GetContainerCountMax(1) or 0) or 0
        local safe2_max = tonumber(inv:GetContainerCountMax(9) or 0) or 0
        if safe_max <= 0 or safe2_max <= 0 then
            if satchel then
                satchel.safe2_mirror_cache = { checked_at = now, value = false }
            end
            return false
        end

        local safe_used = tonumber(inv:GetContainerCount(1) or 0) or 0
        local safe2_used = tonumber(inv:GetContainerCount(9) or 0) or 0
        if safe_used ~= safe2_used then
            if satchel then
                satchel.safe2_mirror_cache = { checked_at = now, value = false }
            end
            return false
        end

        -- If both are empty, we still attempt to infer mirror behavior from slot indices.
        if safe_used <= 0 and safe2_used <= 0 then
            local sample_count = math.min(safe_max, safe2_max, 10)
            local appears_distinct = false

            for slot_index = 1, sample_count do
                local ok_safe, safe_item = pcall(function()
                    return inv:GetContainerItem(1, slot_index)
                end)
                local ok_safe2, safe2_item = pcall(function()
                    return inv:GetContainerItem(9, slot_index)
                end)

                if not ok_safe or not ok_safe2 then
                    appears_distinct = true
                    break
                end

                local safe_index = (safe_item and tonumber(safe_item.Index)) or 0
                local safe2_index = (safe2_item and tonumber(safe2_item.Index)) or 0

                if safe2_index >= 81 or safe_index ~= safe2_index then
                    appears_distinct = true
                    break
                end
            end

            if satchel then
                satchel.safe2_mirror_cache = { checked_at = now, value = not appears_distinct }
            end
            return not appears_distinct
        end

        if safe_used <= 0 then
            if satchel then
                satchel.safe2_mirror_cache = { checked_at = now, value = false }
            end
            return false
        end

        local sample_count = math.min(safe_max, safe2_max, 30)
        for slot_index = 1, sample_count do
            local ok_safe, safe_item = pcall(function()
                return inv:GetContainerItem(1, slot_index)
            end)
            local ok_safe2, safe2_item = pcall(function()
                return inv:GetContainerItem(9, slot_index)
            end)

            if not ok_safe or not ok_safe2 then
                if satchel then
                    satchel.safe2_mirror_cache = { checked_at = now, value = false }
                end
                return false
            end

            local safe_id = (safe_item and tonumber(safe_item.Id)) or 0
            local safe2_id = (safe2_item and tonumber(safe2_item.Id)) or 0
            local safe_count = (safe_item and tonumber(safe_item.Count)) or 0
            local safe2_count = (safe2_item and tonumber(safe2_item.Count)) or 0
            local safe_index = (safe_item and tonumber(safe_item.Index)) or 0
            local safe2_index = (safe2_item and tonumber(safe2_item.Index)) or 0

            if safe_id ~= safe2_id or safe_count ~= safe2_count or safe_index ~= safe2_index then
                if satchel then
                    satchel.safe2_mirror_cache = { checked_at = now, value = false }
                end
                return false
            end
        end

        if satchel then
            satchel.safe2_mirror_cache = { checked_at = now, value = true }
        end
        return true
    end

    local function is_safe2_supported()
        local cache = satchel and satchel.safe2_support_cache
        local now = os.clock()
        if cache and cache.checked_at and ((now - cache.checked_at) < SAFE2_SUPPORT_CACHE_SECONDS) then
            return cache.value == true
        end

        local safe2_max = tonumber(inv:GetContainerCountMax(9) or 0) or 0
        if safe2_max <= 0 then
            if satchel then
                satchel.safe2_support_cache = { checked_at = now, value = false }
            end
            return false
        end

        local safe2_used = tonumber(inv:GetContainerCount(9) or 0) or 0
        local sample_count = math.min(safe2_max, 10)
        local saw_distinct_index = false
        for slot_index = 1, sample_count do
            local ok, item = pcall(function()
                return inv:GetContainerItem(9, slot_index)
            end)
            if not ok then
                if satchel then
                    satchel.safe2_support_cache = { checked_at = now, value = false }
                end
                return false
            end

            local raw_index = item and tonumber(item.Index) or 0
            if raw_index >= 81 then
                saw_distinct_index = true
                if satchel then
                    satchel.safe2_support_cache = { checked_at = now, value = true }
                end
                return true
            end
        end

        -- Conservative fallback: if the container has contents, allow mirror detection
        -- to determine if it is a distinct container or an alias of Mog Safe.
        if safe2_used > 0 or saw_distinct_index then
            if satchel then
                satchel.safe2_support_cache = { checked_at = now, value = true }
            end
            return true
        end

        if satchel then
            satchel.safe2_support_cache = { checked_at = now, value = false }
        end
        return false
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

    local safe2_enabled = is_safe2_supported() and (not does_safe2_mirror_safe())

    local function is_container_enabled(container_id, max_slots)
        local cid = tonumber(container_id)
        if cid == nil then
            return false
        end

        if cid == 1 then
            return (tonumber(max_slots) or 0) > 0
        end

        if cid == 9 then
            return safe2_enabled
        end

        return is_container_supported(cid, max_slots)
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
