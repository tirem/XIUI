local packets = {}

local band = bit.band
local lshift = bit.lshift
local rshift = bit.rshift

local container_fixed_max = {
    [0]  = 80,
    [1]  = 80,
    [2]  = 80,
    [3]  = 32,
    [4]  = 80,
    [5]  = 80,
    [6]  = 80,
    [7]  = 80,
    [8]  = 80,
    [9]  = 80,
    [10] = 80,
    [11] = 80,
    [12] = 80,
    [13] = 80,
    [14] = 80,
    [15] = 80,
    [16] = 80,
}

function packets.create(ctx)
    local satchel = ctx.satchel

    local M = {}

    local function read_u8(bytes, offset)
        return tonumber(bytes[(offset or 0) + 1] or 0) or 0
    end

    function M.read_u16_le(bytes, offset)
        local b0 = read_u8(bytes, offset)
        local b1 = read_u8(bytes, offset + 1)
        return b0 + lshift(b1, 8)
    end

    function M.packet_to_bytes(data)
        local bytes = {}
        if type(data) == 'string' then
            for i = 1, #data do
                bytes[i] = string.byte(data, i) or 0
            end
            return bytes
        end

        if data and data.totable then
            local ok, t = pcall(function() return data:totable() end)
            if ok and type(t) == 'table' and #t > 0 then
                return t
            end
        end

        return bytes
    end

    function M.send_item_move_packet(op)
        local packet_manager = AshitaCore:GetPacketManager()
        if not packet_manager then
            return
        end

        local item_count = math.max(1, tonumber(op.item_count) or 1)
        local source_container = tonumber(op.source_container) or 0
        local target_container = tonumber(op.target_container) or 0
        local source_index = tonumber(op.source_index) or 0
        local target_index = tonumber(op.target_index) or 0

        local sync_value = tonumber(satchel.packet_sync.value)
        if sync_value == nil then
            sync_value = 0
        else
            sync_value = band(sync_value + 1, 0xFFFF)
        end
        satchel.packet_sync.value = sync_value

        local packet = {
            0x29,
            0x06,
            band(sync_value, 0xFF),
            band(rshift(sync_value, 8), 0xFF),
            band(item_count, 0xFF),
            band(rshift(item_count, 8), 0xFF),
            band(rshift(item_count, 16), 0xFF),
            band(rshift(item_count, 24), 0xFF),
            band(source_container, 0xFF),
            band(target_container, 0xFF),
            band(source_index, 0xFF),
            band(target_index, 0xFF),
        }

        packet_manager:AddOutgoingPacket(packet[1], packet)
    end

    function M.find_first_empty_slot_index(container_id)
        return 0x52
    end

    function M.send_bazaar_close()
        local pm = AshitaCore:GetPacketManager()
        if not pm then return end
        pm:AddOutgoingPacket(0x10B, { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 })
    end

    function M.send_bazaar_set_and_open(item_index, price)
        local pm = AshitaCore:GetPacketManager()
        if not pm then return end
        local idx = math.max(0, math.floor(tonumber(item_index) or 0))
        local gil = math.max(0, math.floor(tonumber(price) or 0))

        pm:AddOutgoingPacket(0x10A, {
            0x00, 0x00, 0x00, 0x00,
            band(idx, 0xFF),
            0x00, 0x00, 0x00,
            band(gil, 0xFF),
            band(rshift(gil, 8), 0xFF),
            band(rshift(gil, 16), 0xFF),
            band(rshift(gil, 24), 0xFF),
        })

        pm:AddOutgoingPacket(0x109, { 0x00, 0x00, 0x00, 0x00 })
    end

    function M.send_bazaar_open()
        local pm = AshitaCore:GetPacketManager()
        if not pm then return end
        pm:AddOutgoingPacket(0x109, { 0x00, 0x00, 0x00, 0x00 })
    end

    function M.send_drop_packet(slot)
        if not slot or slot.container_id == nil or not slot.id or slot.id <= 0 then return end

        local pm = AshitaCore:GetPacketManager()
        if not pm then return end

        local item_count = math.max(1, math.floor(tonumber(slot.count) or 1))
        local container_id = math.max(0, math.floor(tonumber(slot.container_id) or 0))
        local item_index = math.max(0, math.floor(tonumber(slot.property_index) or 0))
        if item_index <= 0 then return end

        pm:AddOutgoingPacket(0x028, {
            0x00, 0x00, 0x00, 0x00,
            band(item_count, 0xFF),
            band(rshift(item_count, 8), 0xFF),
            band(rshift(item_count, 16), 0xFF),
            band(rshift(item_count, 24), 0xFF),
            band(container_id, 0xFF),
            band(item_index, 0xFF),
        })
    end

    -- Native FFXI sort (0x3A): asks the server to merge/stack items in one bag.
    -- Byte 0 of the payload is the container id; the rest is padding.
    function M.send_sort_packet(container_id)
        local pm = AshitaCore:GetPacketManager()
        if not pm then return end

        local bag = math.max(0, math.floor(tonumber(container_id) or 0))
        pm:AddOutgoingPacket(0x03A, {
            0x00, 0x00, 0x00, 0x00,
            band(bag, 0xFF),
            0x00, 0x00, 0x00,
        })
    end

    function M.queue_split_command(slot, qty)
        if not slot or not slot.id or slot.id <= 0 then return end
        local source_index = tonumber(slot.property_index)
        if not source_index or source_index <= 0 then return end
        local target_index = M.find_first_empty_slot_index(slot.container_id)
        if not target_index then return end

        M.send_item_move_packet({
            item_count = math.max(1, math.min(tonumber(qty) or 1, (slot.count or 1) - 1)),
            source_container = slot.container_id,
            target_container = slot.container_id,
            source_index = source_index,
            target_index = target_index,
        })
    end

    return M
end

return packets
