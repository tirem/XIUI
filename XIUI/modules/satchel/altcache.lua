local containerlogic = require('modules.satchel.containerlogic')
local slipslogic = require('modules.satchel.slipslogic')

local altcache = {}

local CACHE_CONTAINERS = containerlogic.SCAN_CONTAINERS
local DISPLAY_SLOTS = containerlogic.DISPLAY_SLOTS
local SAVE_DEBOUNCE_SECONDS = 5.0
local REBUILD_DEBOUNCE_SECONDS = 1.0

local pending_save_at = 0
-- 0 = no rebuild pending. Armed here because a mid-session /addon load sees no
-- zone or item packet, so the first snapshot has to be self-scheduled.
local rebuild_at = os.clock() + REBUILD_DEBOUNCE_SECONDS

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
            local item_count = 0
            if slot_index <= limit then
                local ok, item = pcall(inv.GetContainerItem, inv, container_id, slot_index)
                if ok and item and item.Id and item.Id > 0 and item.Id ~= 65535 then
                    item_id = tonumber(item.Id) or 0
                    item_count = math.max(1, tonumber(item.Count) or 1)
                end
            end
            -- Store { id, count } so stacks survive in alt views; keep bare 0 for empty.
            slots[slot_index] = item_id > 0 and { id = item_id, count = item_count } or 0
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

-- Kept out of settings.lua.
local CACHE_FILE_NAME = 'inventory_cache.lua'

local function cache_file_path(name, server_id)
    return get_xiui_config_root() .. name .. '_' .. tostring(server_id) .. '\\' .. CACHE_FILE_NAME
end

-- Binary-safe Lua string literal.
local function lua_string(str)
    return '"' .. tostring(str or ''):gsub('[%c"\\\128-\255]', function(c)
        return string.format('\\%03d', c:byte())
    end) .. '"'
end

local function serialize_cache(entry)
    local out = {
        '-- XIUI satchel inventory cache, written by XIUI (safe to delete; rebuilt on the next inventory change)\n',
        'return {\n',
        ('    name = %s, serverId = %d, gil = %d,\n'):format(lua_string(entry.name), tonumber(entry.serverId) or 0, tonumber(entry.gil) or 0),
        '    slips = {',
    }
    for _, slip in ipairs(entry.slips or {}) do
        out[#out + 1] = ('{ slip_id = %d, extra = %s },'):format(tonumber(slip.slip_id) or 0, lua_string(slip.extra))
    end
    out[#out + 1] = '},\n    containers = {\n'
    local keys = {}
    for key in pairs(entry.containers or {}) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
    for _, key in ipairs(keys) do
        out[#out + 1] = ('        [%s] = {'):format(lua_string(key))
        local slots = entry.containers[key]
        for i = 1, #slots do
            local slot = slots[i]
            if type(slot) == 'table' then
                out[#out + 1] = ('{id=%d,count=%d},'):format(tonumber(slot.id) or 0, tonumber(slot.count) or 1)
            else
                out[#out + 1] = tostring(tonumber(slot) or 0) .. ','
            end
        end
        out[#out + 1] = '},\n'
    end
    out[#out + 1] = '    },\n}\n'
    return table.concat(out)
end

-- Write .tmp then rename.
local function write_cache_file(entry)
    if not entry or not entry.name or not entry.serverId then return false end
    local path = cache_file_path(entry.name, entry.serverId)
    -- The character folder may not exist yet.
    pcall(ashita.fs.create_dir, get_xiui_config_root() .. entry.name .. '_' .. tostring(entry.serverId))
    local tmp = path .. '.tmp'
    local f = io.open(tmp, 'w')
    if not f then return false end
    local ok = f:write(serialize_cache(entry))
    f:close()
    if not ok then
        pcall(os.remove, tmp)
        return false
    end
    if ashita.fs.exists(path) then pcall(os.remove, path) end
    return os.rename(tmp, path) and true or false
end

local function read_cache_file(path)
    if not ashita.fs.exists(path) then return nil end
    local ok, data = pcall(dofile, path)
    if ok and type(data) == 'table' and data.name and type(data.containers) == 'table' then
        return data
    end
    return nil
end

-- Last written cache and its key.
local latest_entry, latest_key = nil, nil

-- Load the cache file, or migrate it from settings.lua.
local function ensure_character_loaded(name, server_id)
    local key = name .. '_' .. tostring(server_id)
    if latest_key == key then return end
    latest_key = key
    latest_entry = read_cache_file(cache_file_path(name, server_id))
    if config and type(config.satchelInventoryCache) == 'table' then
        -- Move the old cache out of settings.lua.
        if not latest_entry then
            if not write_cache_file(config.satchelInventoryCache) then
                return  -- write failed: keep the old cache, retry on next load
            end
            latest_entry = config.satchelInventoryCache
        end
        config.satchelInventoryCache = nil
        if SaveCharacterSettingsInternal then
            SaveCharacterSettingsInternal()
        end
    end
end

-- Called on 0x01D AllLoaded, which the server sends after the zone-in container
-- sync and after every inventory mutation. Debounced so a bag sort rebuilds once.
function altcache.mark_dirty()
    rebuild_at = os.clock() + REBUILD_DEBOUNCE_SECONDS
end

-- Deep equality for plain data.
local function same_value(x, y)
    if x == y then return true end
    if type(x) ~= 'table' or type(y) ~= 'table' then return false end
    for k, v in pairs(x) do
        if not same_value(v, y[k]) then return false end
    end
    for k in pairs(y) do
        if x[k] == nil then return false end
    end
    return true
end

function altcache.tick()
    local now = os.clock()
    if pending_save_at > 0 and now >= pending_save_at then
        pending_save_at = 0
        if latest_entry and not write_cache_file(latest_entry) then
            pending_save_at = now + SAVE_DEBOUNCE_SECONDS  -- retry
        end
    end

    if rebuild_at == 0 or now < rebuild_at then
        return
    end

    local name, server_id = get_player_identity()
    local snapshot = name and server_id and build_live_snapshot() or nil
    if not snapshot then
        -- Not logged in or mid-zone; retry instead of dropping the request.
        rebuild_at = now + REBUILD_DEBOUNCE_SECONDS
        return
    end
    rebuild_at = 0

    ensure_character_loaded(name, server_id)
    local entry = {
        name = name,
        serverId = server_id,
        containers = snapshot,
        slips = build_slip_snapshot(),
        gil = get_live_gil_amount(),
    }
    -- Skip the write if nothing changed.
    if same_value(latest_entry, entry) then
        return
    end
    latest_entry = entry

    pending_save_at = now + SAVE_DEBOUNCE_SECONDS
end

local function read_cached_slot(entry)
    if type(entry) == 'table' then
        local item_id = tonumber(entry.id) or tonumber(entry[1]) or 0
        local item_count = tonumber(entry.count) or tonumber(entry[2])
        if item_id > 0 then
            return item_id, math.max(1, item_count or 1)
        end
        return 0, 0
    end

    local item_id = tonumber(entry) or 0
    return item_id, item_id > 0 and 1 or 0
end

function altcache.container_has_items(cache_entry, container_id)
    local cached_slots = cache_entry
        and cache_entry.containers
        and cache_entry.containers[tostring(container_id)]
    if not cached_slots then
        return false
    end

    for slot_index = 1, DISPLAY_SLOTS do
        local item_id = read_cached_slot(cached_slots[slot_index])
        if item_id > 0 then
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
                -- Cache file first, then settings.lua.
                local cache = read_cache_file(root .. dir .. '\\' .. CACHE_FILE_NAME)
                local settings_path = root .. dir .. '\\settings.lua'
                if not cache and ashita.fs.exists(settings_path) then
                    local ok, data = pcall(dofile, settings_path)
                    if ok and type(data) == 'table' and type(data.satchelInventoryCache) == 'table' then
                        cache = data.satchelInventoryCache
                    end
                end
                if cache and cache.name and cache.containers then
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

    table.sort(entries, function(a, b)
        return (a.name or '') < (b.name or '')
    end)

    return entries
end

-- Alt slots built once (entries are read only).
local slotsFromCacheMemo = setmetatable({}, { __mode = 'k' })

function altcache.build_slots_from_cache(cache_entry, container_id)
    local memo = cache_entry and slotsFromCacheMemo[cache_entry]
    local hit = memo and memo[container_id]
    if hit then
        return hit
    end
    local slots = altcache.build_slots_from_cache_uncached(cache_entry, container_id)
    if cache_entry then
        if not memo then
            memo = {}
            slotsFromCacheMemo[cache_entry] = memo
        end
        memo[container_id] = slots
    end
    return slots
end

function altcache.build_slots_from_cache_uncached(cache_entry, container_id)
    local slots = {}
    local key = tostring(container_id)
    local cached_slots = cache_entry and cache_entry.containers and cache_entry.containers[key]

    for slot_index = 1, DISPLAY_SLOTS do
        local item_id, item_count = 0, 0
        if cached_slots then
            item_id, item_count = read_cached_slot(cached_slots[slot_index])
        end
        slots[#slots + 1] = {
            container_id = container_id,
            slot_index = slot_index - 1,
            property_index = slot_index,
            id = item_id,
            count = item_count,
            locked = false,
            read_only = true,
            alt_view = true,
        }
    end

    return slots
end

-- Writes a pending save now (unload).
function altcache.flush()
    if pending_save_at > 0 then
        pending_save_at = 0
        if latest_entry then
            write_cache_file(latest_entry)
        end
    end
end

-- Zone teardown: drop any pending rebuild so we never snapshot a half-loaded
-- inventory. The 0x01D AllLoaded that closes the zone-in sync re-arms it.
function altcache.invalidate()
    rebuild_at = 0
end

return altcache
