local containerlogic = require('modules.satchel.containerlogic')
local slipslogic = require('modules.satchel.slipslogic')

local altcache = {}

local CACHE_CONTAINERS = containerlogic.SCAN_CONTAINERS
local DISPLAY_SLOTS = containerlogic.DISPLAY_SLOTS
local SAVE_DEBOUNCE_SECONDS = 5.0
local SCAN_INTERVAL_SECONDS = 1.0

local pending_save_at = 0
local last_scan_at = 0
local last_hash = nil

local function get_player_identity()
    local mm = AshitaCore:GetMemoryManager()
    if not mm then return nil, nil end

    local party = mm:GetParty()
    local entity = mm:GetEntity()
    if not party or not entity then return nil, nil end

    local index = party:GetMemberTargetIndex(0)
    if not index then return nil, nil end

    local name = entity:GetName(index)
    local server_id = tonumber(entity:GetServerId(index)) or 0
    if not name or #name == 0 or server_id <= 0 then
        return nil, nil
    end

    return name, server_id
end

local function get_xiui_config_root()
    return AshitaCore:GetInstallPath() .. 'config\\addons\\xiui\\'
end

local function get_live_gil_amount()
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    if not inv then
        return 0
    end

    local ok, gil_item = pcall(function()
        return inv:GetContainerItem(0, 0)
    end)
    if not ok or not gil_item then
        return 0
    end

    return tonumber(gil_item.Count) or 0
end

local function build_live_snapshot()
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    if not inv then
        return nil
    end

    local snapshot = {}
    for _, container_id in ipairs(CACHE_CONTAINERS) do
        local max_slots = tonumber(inv:GetContainerCountMax(container_id) or 0) or 0
        local slots = {}
        local limit = math.min(DISPLAY_SLOTS, max_slots)

        for slot_index = 1, DISPLAY_SLOTS do
            local item_id = 0
            if slot_index <= limit then
                local ok, item = pcall(inv.GetContainerItem, inv, container_id, slot_index)
                if ok and item and item.Id and item.Id > 0 and item.Id ~= 65535 then
                    item_id = tonumber(item.Id) or 0
                end
            end
            slots[slot_index] = item_id
        end

        snapshot[tostring(container_id)] = slots
    end

    return snapshot
end

local function build_slip_snapshot()
    local instances = slipslogic.find_owned_slip_instances()
    local slips = {}
    for _, instance in ipairs(instances) do
        slips[#slips + 1] = {
            slip_id = instance.slip_id,
            extra = instance.extra or '',
        }
    end
    return slips
end

local function hash_slips(slips)
    local parts = {}
    for _, entry in ipairs(slips or {}) do
        parts[#parts + 1] = tostring(entry.slip_id or 0) .. ':' .. tostring(entry.extra or '')
    end
    return table.concat(parts, '|')
end

local function hash_snapshot(snapshot, slips, gil)
    if not snapshot then
        return ''
    end

    local parts = {}
    for _, container_id in ipairs(CACHE_CONTAINERS) do
        local key = tostring(container_id)
        local slots = snapshot[key]
        if slots then
            for slot_index = 1, DISPLAY_SLOTS do
                parts[#parts + 1] = tostring(slots[slot_index] or 0)
            end
        end
    end

    parts[#parts + 1] = hash_slips(slips)
    parts[#parts + 1] = tostring(tonumber(gil) or 0)

    return table.concat(parts, ',')
end

local function write_cache_to_character_settings(cache_entry)
    if not config then
        return
    end

    config.satchelInventoryCache = cache_entry
    if SaveCharacterSettingsInternal then
        SaveCharacterSettingsInternal()
    end
end

function altcache.tick()
    local now = os.clock()
    if pending_save_at > 0 and now >= pending_save_at then
        pending_save_at = 0
        if config and config.satchelInventoryCache then
            write_cache_to_character_settings(config.satchelInventoryCache)
        end
    end

    if (now - last_scan_at) < SCAN_INTERVAL_SECONDS then
        return
    end
    last_scan_at = now

    local name, server_id = get_player_identity()
    if not name or not server_id then
        return
    end

    local snapshot = build_live_snapshot()
    if not snapshot then
        return
    end

    local slips = build_slip_snapshot()
    local gil = get_live_gil_amount()
    local hash = hash_snapshot(snapshot, slips, gil)
    if hash == last_hash then
        return
    end
    last_hash = hash

    local cache_entry = {
        name = name,
        serverId = server_id,
        containers = snapshot,
        slips = slips,
        gil = gil,
    }

    if config then
        config.satchelInventoryCache = cache_entry
    end

    pending_save_at = now + SAVE_DEBOUNCE_SECONDS
end

function altcache.container_has_items(cache_entry, container_id)
    local cached_slots = cache_entry
        and cache_entry.containers
        and cache_entry.containers[tostring(container_id)]
    if not cached_slots then
        return false
    end

    for slot_index = 1, DISPLAY_SLOTS do
        if (tonumber(cached_slots[slot_index]) or 0) > 0 then
            return true
        end
    end

    return false
end

function altcache.list_character_caches()
    local entries = {}
    local current_name, current_id = get_player_identity()
    local root = get_xiui_config_root()
    local directories = ashita.fs.get_directory(root)

    if not directories then
        return entries
    end

    for _, dir in ipairs(directories) do
        local name, id = string.match(dir, '^([%a]+)_(%d+)$')
        if name and id then
            if not (current_name == name and tonumber(id) == current_id) then
                local settings_path = root .. dir .. '\\settings.lua'
                if ashita.fs.exists(settings_path) then
                    local ok, data = pcall(dofile, settings_path)
                    if ok and type(data) == 'table' and type(data.satchelInventoryCache) == 'table' then
                        local cache = data.satchelInventoryCache
                        if cache.name and cache.containers then
                            entries[#entries + 1] = {
                                key = dir,
                                name = cache.name,
                                serverId = cache.serverId or tonumber(id),
                                containers = cache.containers,
                                slips = cache.slips or {},
                                gil = tonumber(cache.gil),
                            }
                        end
                    end
                end
            end
        end
    end

    table.sort(entries, function(a, b)
        return (a.name or '') < (b.name or '')
    end)

    return entries
end

function altcache.build_slots_from_cache(cache_entry, container_id)
    local slots = {}
    local key = tostring(container_id)
    local cached_slots = cache_entry and cache_entry.containers and cache_entry.containers[key]

    for slot_index = 1, DISPLAY_SLOTS do
        local item_id = 0
        if cached_slots then
            item_id = tonumber(cached_slots[slot_index]) or 0
        end
        slots[#slots + 1] = {
            container_id = container_id,
            slot_index = slot_index - 1,
            property_index = slot_index,
            id = item_id,
            count = item_id > 0 and 1 or 0,
            locked = false,
            read_only = true,
            alt_view = true,
        }
    end

    return slots
end

function altcache.invalidate()
    last_hash = nil
    last_scan_at = 0
end

return altcache
