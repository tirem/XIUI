--[[
* XIUI Packet Parsing Utilities
* Parse action, mob update, and message packets
]]--

require('common');

local M = {};

-- ========================================
-- Entity Index Cache
-- ========================================

local entityIndexCache = {};

function M.ClearEntityCache()
    entityIndexCache = {};
end

-- ========================================
-- Index/ID Conversion
-- ========================================

function M.GetIndexFromId(id)
    -- Check cache first
    if entityIndexCache[id] then
        return entityIndexCache[id];
    end

    local entMgr = AshitaCore:GetMemoryManager():GetEntity();

    -- Shortcut for monsters/static npcs
    if (bit.band(id, 0x1000000) ~= 0) then
        local index = bit.band(id, 0xFFF);
        if (index >= 0x900) then
            index = index - 0x100;
        end

        if (index < 0x900) and (entMgr:GetServerId(index) == id) then
            entityIndexCache[id] = index;
            return index;
        end
    end

    for i = 1, 0x8FF do
        if entMgr:GetServerId(i) == id then
            entityIndexCache[id] = i;
            return i;
        end
    end

    entityIndexCache[id] = 0;
    return 0;
end

-- ========================================
-- Action Packet Parsing
-- ========================================

function M.ParseActionPacket(e)
    local bitData;
    local bitOffset;
    local maxLength = e.size * 8;
    local function UnpackBits(length)
        if ((bitOffset + length) >= maxLength) then
            maxLength = 0; -- Using this as a flag since any malformed fields mean the data is trash anyway
            return 0;
        end
        local value = ashita.bits.unpack_be(bitData, 0, bitOffset, length);
        bitOffset = bitOffset + length;
        return value;
    end

    local actionPacket = T{};
    bitData = e.data_raw;
    bitOffset = 40;
    actionPacket.UserId = UnpackBits(32);
    actionPacket.UserIndex = M.GetIndexFromId(actionPacket.UserId);
    local targetCount = UnpackBits(6);
    -- Unknown 4 bits
    bitOffset = bitOffset + 4;
    actionPacket.Type = UnpackBits(4);
    -- Bandaid fix until we have more flexible packet parsing
    if actionPacket.Type == 8 or actionPacket.Type == 9 then
        actionPacket.Param = UnpackBits(16);
        actionPacket.SpellGroup = UnpackBits(16);
    else
        -- Not every action packet has the same data at the same offsets so we just skip this for now
        actionPacket.Param = UnpackBits(32);
    end

    actionPacket.Recast = UnpackBits(32);

    actionPacket.Targets = T{};
    if (targetCount > 0) then
        for i = 1, targetCount do
            local target = T{};
            target.Id = UnpackBits(32);
            local actionCount = UnpackBits(4);
            target.Actions = T{};
            if (actionCount == 0) then
                break;
            else
                for j = 1, actionCount do
                    local action = {};
                    action.Reaction = UnpackBits(5);
                    action.Animation = UnpackBits(12);
                    action.SpecialEffect = UnpackBits(7);
                    action.Knockback = UnpackBits(3);
                    action.Param = UnpackBits(17);
                    action.Message = UnpackBits(10);
                    action.Flags = UnpackBits(31);

                    local hasAdditionalEffect = (UnpackBits(1) == 1);
                    if hasAdditionalEffect then
                        local additionalEffect = {};
                        additionalEffect.Damage = UnpackBits(10);
                        additionalEffect.Param = UnpackBits(17);
                        additionalEffect.Message = UnpackBits(10);
                        action.AdditionalEffect = additionalEffect;
                    end

                    local hasSpikesEffect = (UnpackBits(1) == 1);
                    if hasSpikesEffect then
                        local spikesEffect = {};
                        spikesEffect.Damage = UnpackBits(10);
                        spikesEffect.Param = UnpackBits(14);
                        spikesEffect.Message = UnpackBits(10);
                        action.SpikesEffect = spikesEffect;
                    end

                    target.Actions:append(action);
                end
            end
            actionPacket.Targets:append(target);
        end
    end

    if (maxLength ~= 0) and (#actionPacket.Targets > 0) then
        return actionPacket;
    end
end

-- ========================================
-- Mob Update Packet Parsing
-- ========================================

function M.ParseMobUpdatePacket(e)
    if (e.id == 0x00E) then
        local mobPacket = T{};
        mobPacket.monsterId = struct.unpack('L', e.data, 0x04 + 1);
        mobPacket.monsterIndex = struct.unpack('H', e.data, 0x08 + 1);
        mobPacket.updateFlags = struct.unpack('B', e.data, 0x0A + 1);
        if (bit.band(mobPacket.updateFlags, 0x02) == 0x02) then
            mobPacket.newClaimId = struct.unpack('L', e.data, 0x2C + 1);
        end
        return mobPacket;
    end
end

-- ========================================
-- Message Packet Parsing
-- ========================================

function M.ParseMessagePacket(e)
    -- Use unsigned integers per FFXI packet structure
    -- 'I4' = unsigned 4-byte int, 'H' = unsigned 2-byte short
    local basic = {
        sender     = struct.unpack('I4', e, 0x04 + 1),
        target     = struct.unpack('I4', e, 0x08 + 1),
        param      = struct.unpack('I4', e, 0x0C + 1),
        value      = struct.unpack('I4', e, 0x10 + 1),
        sender_tgt = struct.unpack('H', e, 0x14 + 1),
        target_tgt = struct.unpack('H', e, 0x16 + 1),
        message    = struct.unpack('H', e, 0x18 + 1),
    }
    return basic;
end

-- ========================================
-- Validation Helpers
-- ========================================

function M.valid_server_id(server_id)
    return server_id > 0 and server_id < 0x4000000;
end

return M;
