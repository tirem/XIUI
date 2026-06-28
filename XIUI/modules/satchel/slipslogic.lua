local slipsdata = require('modules.satchel.slipsdata')
local containerlogic = require('modules.satchel.containerlogic')

local slipslogic = {}

slipslogic.PAGE_SIZE = 80

local SCAN_CONTAINERS = containerlogic.SCAN_CONTAINERS

local slip_ids = slipsdata.ids
local slip_items = slipsdata.items

local function read_bit(extra, bit_position)
    if not extra or type(extra) ~= 'string' or extra == '' then
        return false
    end

    local byte_index = math.floor((bit_position - 1) / 8) + 1
    local bitmask = extra:byte(byte_index)
    if not bitmask then
        return false
    end
    if bitmask < 0 then
        bitmask = bitmask + 256
    end

    local bit_index = (bit_position - 1) % 8
    return bit.band(bit.rshift(bitmask, bit_index), 1) ~= 0
end

function slipslogic.get_slip_ids()
    return slip_ids
end

function slipslogic.get_slip_number(slip_item_id)
    for index, id in ipairs(slip_ids) do
        if id == slip_item_id then
            return index
        end
    end
    return nil
end

function slipslogic.format_slip_label(slip_item_id)
    local number = slipslogic.get_slip_number(slip_item_id)
    if number then
        return ('Storage Slip %02d'):format(number)
    end
    return 'Storage Slip'
end

local function for_each_inventory_item(callback)
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    if not inv or not callback then
        return
    end

    for _, container_id in ipairs(SCAN_CONTAINERS) do
        local max_slots = tonumber(inv:GetContainerCountMax(container_id) or 0) or 0
        for slot_index = 1, max_slots do
            local ok, item = pcall(inv.GetContainerItem, inv, container_id, slot_index)
            if ok and item and callback(container_id, slot_index, item) == true then
                return
            end
        end
    end
end

function slipslogic.find_owned_slip_instances()
    local instances = {}
    for_each_inventory_item(function(container_id, slot_index, item)
        local item_id = tonumber(item.Id)
        if item_id and slipslogic.get_slip_number(item_id) then
            instances[#instances + 1] = {
                slip_id = item_id,
                container_id = container_id,
                slot_index = slot_index - 1,
                extra = item.Extra,
            }
        end
    end)

    return instances
end

function slipslogic.is_slip_owned(slip_item_id)
    local target_id = tonumber(slip_item_id)
    if not target_id then
        return false
    end

    local found = false
    for_each_inventory_item(function(_, _, item)
        if tonumber(item.Id) == target_id then
            found = true
            return true
        end
    end)

    return found
end

function slipslogic.has_any_owned_slips()
    local has_slip = false
    for_each_inventory_item(function(_, _, item)
        if slipslogic.get_slip_number(tonumber(item.Id)) then
            has_slip = true
            return true
        end
    end)
    return has_slip
end

function slipslogic.get_owned_slip_ids()
    local owned = {}
    local seen = {}
    for _, instance in ipairs(slipslogic.find_owned_slip_instances()) do
        local slip_id = instance.slip_id
        if slip_id and not seen[slip_id] then
            seen[slip_id] = true
            owned[#owned + 1] = slip_id
        end
    end

    table.sort(owned, function(a, b)
        return (slipslogic.get_slip_number(a) or 0) < (slipslogic.get_slip_number(b) or 0)
    end)

    return owned
end

function slipslogic.get_cached_slip_ids(slips_cache)
    local ids = {}
    for _, entry in ipairs(slips_cache or {}) do
        if entry.slip_id then
            ids[#ids + 1] = entry.slip_id
        end
    end
    return ids
end

function slipslogic.has_cached_slips(slips_cache)
    return #slipslogic.get_cached_slip_ids(slips_cache) > 0
end

function slipslogic.get_stored_items_from_cache(slips_cache, slip_item_id)
    local extra = nil
    for _, entry in ipairs(slips_cache or {}) do
        if tonumber(entry.slip_id) == tonumber(slip_item_id) then
            extra = entry.extra
            break
        end
    end
    return slipslogic.get_stored_items(slip_item_id, extra)
end

function slipslogic.get_stored_items(slip_item_id, extra_override)
    local catalog = slip_items[slip_item_id]
    if not catalog then
        return {}
    end

    local extra = extra_override
    if extra == nil then
        for _, instance in ipairs(slipslogic.find_owned_slip_instances()) do
            if instance.slip_id == slip_item_id then
                extra = instance.extra
                break
            end
        end
    end

    local stored = {}
    for bit_position, item_id in ipairs(catalog) do
        if read_bit(extra, bit_position) then
            stored[#stored + 1] = item_id
        end
    end

    return stored
end

function slipslogic.build_page_slots(stored_items, page_index)
    local page_size = slipslogic.PAGE_SIZE
    local page = tonumber(page_index) or 0
    local start_index = (page * page_size) + 1
    local slots = {}

    for offset = 0, page_size - 1 do
        local item_id = stored_items[start_index + offset] or 0
        slots[#slots + 1] = {
            id = item_id,
            count = item_id > 0 and 1 or 0,
            locked = false,
            read_only = true,
            virtual = true,
        }
    end

    return slots, #stored_items
end

return slipslogic
