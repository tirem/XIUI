--[[
* XIUI Treasure Pool - Actions Module
* Handles lot/pass packet sending for treasure pool items
*
* Full packet format with header required for Ashita v4
* Lot: { 0x41, size, sync, sync, slot, propertyIndex, pad, pad }
* Pass: { 0x42, size, sync, sync, slot, pad }
]]--

require('common');
local data = require('modules.treasurepool.data');

local M = {};

-- ============================================
-- Single Item Actions
-- ============================================

-- Lot on a specific treasure pool item by slot
function M.LotItem(slot)
    -- Validate slot
    if slot == nil or slot < 0 or slot >= data.MAX_POOL_SLOTS then
        return false;
    end

    -- Check if item exists in pool
    local item = data.GetPoolItem(slot);
    if not item then
        return false;
    end

    -- Check if already lotted
    local status = data.GetPlayerLotStatus(slot);
    if status == 'lotted' then
        return false;
    end

    -- Build and send lot packet (0x041)
    local lotPacket = struct.pack('bbbbbbbb', 0x41, 0x04, 0x00, 0x00, slot, 0x00, 0x00, 0x00):totable();
    AshitaCore:GetPacketManager():AddOutgoingPacket(lotPacket[1], lotPacket);
    return true;
end

-- Pass on a specific treasure pool item by slot
function M.PassItem(slot)
    -- Validate slot
    if slot == nil or slot < 0 or slot >= data.MAX_POOL_SLOTS then
        return false;
    end

    -- Check if item exists in pool
    local item = data.GetPoolItem(slot);
    if not item then
        return false;
    end

    -- Check if already passed or lotted
    local status = data.GetPlayerLotStatus(slot);
    if status == 'passed' or status == 'lotted' then
        return false;  -- Already decided
    end

    -- Build pass packet with full header
    local passPacket = struct.pack('bbbbbbbb', 0x42, 0x04, 0x00, 0x00, slot, 0x00, 0x00, 0x00):totable();

    -- Send using SDK pattern
    local mgr = AshitaCore:GetPacketManager();
    mgr:AddOutgoingPacket(passPacket[1], passPacket);
    return true;
end

-- ============================================
-- Batch Actions
-- ============================================

-- Lot on all items that player has NOT already lotted/passed on
function M.LotAll()
    local inventory = AshitaCore:GetMemoryManager():GetInventory();
    if not inventory then
        return 0;
    end

    local mgr = AshitaCore:GetPacketManager();
    local count = 0;
    for slot = 0, data.MAX_POOL_SLOTS - 1 do
        local item = inventory:GetTreasurePoolItem(slot);
        if item and item.ItemId and item.ItemId > 0 and item.ItemId ~= 65535 then
            local lot = item.Lot;
            -- Only lot if pending (0, nil, or 65535+ means not lotted)
            if lot == nil or lot == 0 or lot >= 65535 then
                local lotPacket = struct.pack('bbbbbbbb', 0x41, 0x04, 0x00, 0x00, slot, 0x00, 0x00, 0x00):totable();
                mgr:AddOutgoingPacket(lotPacket[1], lotPacket);
                count = count + 1;
            end
        end
    end

    return count;
end

-- Pass on all items that player has NOT already lotted/passed on
function M.PassAll()
    local inventory = AshitaCore:GetMemoryManager():GetInventory();
    if not inventory then
        return 0;
    end

    local mgr = AshitaCore:GetPacketManager();
    local count = 0;
    for slot = 0, data.MAX_POOL_SLOTS - 1 do
        local item = inventory:GetTreasurePoolItem(slot);
        if item and item.ItemId and item.ItemId > 0 and item.ItemId ~= 65535 then
            local lot = item.Lot;
            -- Only pass if pending (0, nil means not decided, 65535 means already passed)
            if lot == nil or lot == 0 then
                local passPacket = struct.pack('bbbbbbbb', 0x42, 0x04, 0x00, 0x00, slot, 0x00, 0x00, 0x00):totable();
                mgr:AddOutgoingPacket(passPacket[1], passPacket);
                count = count + 1;
            end
        end
    end

    return count;
end

return M;
