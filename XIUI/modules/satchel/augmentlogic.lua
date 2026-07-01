--[[
    Augmented equipment extdata parsing for Satchel tooltips.
    Uses bundled system-1 augment tables; optionally defers to Windower extdata when available.
]]--

local augmentlogic = {}

local augmentdata = require('modules.satchel.augmentdata')

local function normalize_extra(extra)
    if type(extra) ~= 'string' or extra == '' then
        return nil
    end

    if #extra < 24 then
        return extra .. string.rep('\0', 24 - #extra)
    end

    if #extra > 24 then
        return extra:sub(1, 24)
    end

    return extra
end

local function unpack_augment(sys, short)
    if #short < 2 then
        return nil, nil
    end

    if sys == 1 then
        return short:byte(1) + short:byte(2) % 8 * 256, math.floor(short:byte(2) / 8)
    elseif sys == 2 then
        return short:byte(1), short:byte(2)
    elseif sys == 3 then
        return short:byte(1) + short:byte(2) % 8 * 256, math.floor(short:byte(2) % 128 / 8)
    elseif sys == 4 then
        return short:byte(1), short:byte(2)
    end

    return nil, nil
end

local function string_augment(sys, id, val, augment_values)
    local augment_table = augment_values[id]
    if not augment_table then
        return nil
    end

    local parts = {}
    for _, entry in ipairs(augment_table) do
        if entry.stat ~= 'none' then
            local potency = ((val + (entry.offset or 0)) * (entry.multiplier or 1))
            local text = entry.stat
            if potency > 0 then
                text = text .. '+' .. potency
            elseif potency < 0 then
                text = text .. potency
            end
            if entry.percent then
                text = text .. '%'
            end
            parts[#parts + 1] = text
        end
    end

    if #parts == 0 then
        return nil
    end

    return table.concat(parts, ' ')
end

local function augments_to_table(sys, str, augment_values)
    local augments = {}
    for i = 1, #str - 1, 2 do
        local pair = str:sub(i, i + 1)
        local id, val = unpack_augment(sys, pair)
        if id and val and not (id == 0 and val == 0) then
            local text = string_augment(sys, id, val, augment_values)
            if text and text ~= 'none' and text ~= '???' then
                augments[#augments + 1] = text
            end
        end
    end
    return augments
end

local function decode_augmented_local(str)
    if type(str) ~= 'string' or #str < 12 then
        return nil
    end

    local flag_1 = str:byte(1)
    if flag_1 ~= 2 and flag_1 ~= 3 then
        return nil
    end

    local flag_2 = str:byte(2)
    local rettab = { type = 'Augmented Equipment' }

    if flag_2 % 64 / 32 >= 1 then
        rettab.augment_system = 2
        rettab.augments = augments_to_table(2, str:sub(7, 12), augmentdata)
        return rettab
    end

    if flag_2 == 131 then
        return rettab
    end

    if flag_2 / 128 >= 1 then
        rettab.augment_system = 3
        rettab.augments = augments_to_table(3, str:sub(3, 8), augmentdata)
        rettab.slots = {
            [1] = { size = math.floor(str:byte(10) / 16) + 1, element = str:byte(12) % 8 },
            [2] = { size = str:byte(11) % 16 + 1, element = math.floor(str:byte(12) / 8) % 8 },
            [3] = { size = math.floor(str:byte(11) / 16) + 1, element = math.floor(str:byte(12) / 64) + math.floor(str:byte(8) / 128) },
        }
        return rettab
    end

    rettab.augment_system = 1
    local trial_number = nil
    if flag_2 % 128 / 64 >= 1 then
        trial_number = (str:byte(12) % 128) * 256 + str:byte(11)
    end

    if trial_number then
        rettab.augments = augments_to_table(1, str:sub(3, 10), augmentdata)
    else
        rettab.augments = augments_to_table(1, str:sub(3, 12), augmentdata)
    end

    return rettab
end

local function ensure_extdata_res_shim()
    if res and res.items then
        return true
    end

    local rm = AshitaCore and AshitaCore:GetResourceManager()
    if not rm then
        return false
    end

    res = res or {}
    res.items = setmetatable({}, {
        __index = function(_, item_id)
            local id = tonumber(item_id)
            if not id then
                return nil
            end

            local ok, item = pcall(rm.GetItemById, rm, id)
            if not ok or not item then
                return nil
            end

            local item_type = tonumber(item.Type) or 0
            return { type = item_type }
        end,
    })

    return true
end

local function try_extdata_decode(item_id, extra)
    local ok, extdata = pcall(require, 'extdata')
    if not ok or not extdata or not extdata.decode then
        return nil
    end

    if not ensure_extdata_res_shim() then
        return nil
    end

    local normalized = normalize_extra(extra)
    if not normalized then
        return nil
    end

    local decode_ok, decoded = pcall(extdata.decode, {
        id = tonumber(item_id),
        extdata = normalized,
    })

    if decode_ok and type(decoded) == 'table' then
        if type(decoded.augments) == 'table' or type(decoded.slots) == 'table' then
            return decoded
        end
    end

    return nil
end

function augmentlogic.decode_extra(item_id, extra)
    local normalized = normalize_extra(extra)
    if not normalized then
        return nil
    end

    local decoded = try_extdata_decode(item_id, normalized)
    if decoded then
        return decoded
    end

    return decode_augmented_local(normalized)
end

function augmentlogic.get_augment_lines(item_id, extra)
    local decoded = augmentlogic.decode_extra(item_id, extra)
    if not decoded or type(decoded.augments) ~= 'table' then
        return {}
    end

    local lines = {}
    for _, augment in ipairs(decoded.augments) do
        if type(augment) == 'string' and augment ~= '' then
            lines[#lines + 1] = augment
        end
    end

    return lines
end

function augmentlogic.has_augments(item_id, extra)
    if type(extra) ~= 'string' or extra == '' then
        return false
    end

    local first_byte = extra:byte(1)
    return first_byte == 2 or first_byte == 3
end

function augmentlogic.augment_makes_exclusive(item_id, extra)
    return augmentlogic.has_augments(item_id, extra)
end

local INSCRIPTION_AUGMENT_MIN = 0x300
local INSCRIPTION_AUGMENT_MAX = 0x30F
local DEFAULT_INSCRIPTION_SLOTS = 3

local function get_augment_pair_region(decoded, str)
    if not decoded or type(str) ~= 'string' then
        return nil, 0
    end

    local flag_2 = str:byte(2) or 0
    if decoded.augment_system == 2 or flag_2 % 64 / 32 >= 1 then
        return str:sub(7, 12), 3
    end

    if decoded.augment_system == 3 or flag_2 / 128 >= 1 then
        return str:sub(3, 8), 3
    end

    local trial_number = nil
    if flag_2 % 128 / 64 >= 1 then
        trial_number = (str:byte(12) % 128) * 256 + str:byte(11)
    end

    if trial_number then
        return str:sub(3, 10), 4
    end

    return str:sub(3, 12), 5
end

function augmentlogic.get_augment_slot_pairs(item_id, extra)
    local normalized = normalize_extra(extra)
    if not normalized then
        return {}, 1, 0
    end

    local decoded = augmentlogic.decode_extra(item_id, normalized)
    if not decoded then
        return {}, 1, 0
    end

    local region, slot_count = get_augment_pair_region(decoded, normalized)
    if not region or region == '' then
        return {}, decoded.augment_system or 1, slot_count
    end

    local sys = decoded.augment_system or 1
    local pairs = {}
    for i = 1, #region - 1, 2 do
        local id, val = unpack_augment(sys, region:sub(i, i + 1))
        pairs[#pairs + 1] = {
            index = math.floor((i + 1) / 2),
            id = id,
            val = val,
        }
    end

    return pairs, sys, slot_count
end

local function is_inscription_augment_id(id)
    return type(id) == 'number'
        and id >= INSCRIPTION_AUGMENT_MIN
        and id <= INSCRIPTION_AUGMENT_MAX
end

local function inscription_element_index(id)
    if id >= 0x300 and id <= 0x307 then
        return id - 0x300 + 1, true
    end

    if id >= 0x308 and id <= 0x30F then
        return id - 0x308 + 1, false
    end

    return nil
end

local function inscription_display_value(id, val)
    local entry = augmentdata[id] and augmentdata[id][1]
    if not entry then
        return math.abs(val)
    end

    local potency = ((val + (entry.offset or 0)) * (entry.multiplier or 1))
    return math.max(0, math.abs(math.floor(potency + 0.5)))
end

local function augment_has_negative_potency(sys, id, val)
    local augment_table = augmentdata[id]
    if not augment_table then
        return false
    end

    for _, entry in ipairs(augment_table) do
        if entry.stat ~= 'none' then
            local potency = ((val + (entry.offset or 0)) * (entry.multiplier or 1))
            if potency < 0 then
                return true
            end
        end
    end

    return false
end

local function is_real_augment_pair(pair)
    if not pair or not pair.id or not pair.val then
        return false
    end

    if pair.id == 0 and pair.val == 0 then
        return false
    end

    return not is_inscription_augment_id(pair.id)
end

local function make_inscription_entry(slot, pair, pairs_by_slot)
    local element_index, inscription_positive = inscription_element_index(pair.id)
    if not element_index then
        return nil
    end

    local slot_pair = pairs_by_slot[slot]
    local positive = inscription_positive
    if slot_pair and is_real_augment_pair(slot_pair) and augment_has_negative_potency(nil, slot_pair.id, slot_pair.val) then
        positive = false
    end

    return {
        slot = slot,
        element_index = element_index,
        value = inscription_display_value(pair.id, pair.val),
        positive = positive,
    }
end

local function get_evolith_footer_entries(decoded)
    if type(decoded.slots) ~= 'table' then
        return {}
    end

    local entries = {}
    for slot, data in ipairs(decoded.slots) do
        local element = tonumber(data and data.element) or 0
        local size = tonumber(data and data.size) or 0
        if element >= 0 and element <= 7 and size > 0 then
            entries[#entries + 1] = {
                slot = slot,
                element_index = element + 1,
                value = size,
                positive = true,
            }
        end
    end

    return entries
end

function augmentlogic.get_elemental_footer_entries(item_id, extra)
    local normalized = normalize_extra(extra)
    if not normalized then
        return {}
    end

    local decoded = augmentlogic.decode_extra(item_id, normalized)
    if not decoded then
        return {}
    end

    if decoded.augment_system == 3 and type(decoded.slots) == 'table' then
        return get_evolith_footer_entries(decoded)
    end

    local pairs, _sys, slot_count = augmentlogic.get_augment_slot_pairs(item_id, normalized)
    if #pairs == 0 then
        return {}
    end

    slot_count = math.max(DEFAULT_INSCRIPTION_SLOTS, slot_count or DEFAULT_INSCRIPTION_SLOTS)
    slot_count = math.min(slot_count, #pairs)

    local pairs_by_slot = {}
    for _, pair in ipairs(pairs) do
        pairs_by_slot[pair.index] = pair
    end

    local entries = {}
    local spare_inscriptions = {}

    for slot = 1, slot_count do
        local pair = pairs_by_slot[slot]
        if pair and is_inscription_augment_id(pair.id) then
            local entry = make_inscription_entry(slot, pair, pairs_by_slot)
            if entry then
                entries[slot] = entry
            end
        end
    end

    for _, pair in ipairs(pairs) do
        if is_inscription_augment_id(pair.id) and not entries[pair.index] then
            spare_inscriptions[#spare_inscriptions + 1] = pair
        end
    end

    for slot = 1, slot_count do
        if not entries[slot] and #spare_inscriptions > 0 then
            local pair = table.remove(spare_inscriptions, 1)
            local entry = make_inscription_entry(slot, pair, pairs_by_slot)
            if entry then
                entries[slot] = entry
            end
        end
    end

    local ordered = {}
    for slot = 1, slot_count do
        if entries[slot] then
            ordered[#ordered + 1] = entries[slot]
        end
    end

    return ordered
end

return augmentlogic
