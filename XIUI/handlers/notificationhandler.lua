--[[
* XIUI Notification Handler
* Handles packet parsing for notifications (party invites, trade requests, item/gil obtained, treasure pool)
* Follows patterns from debuffhandler.lua for O(1) hash table lookups
]]--

require('common');
local struct = require('struct');

local M = {};

-- ========================================
-- Zoning/Load State Tracking
-- ========================================

-- Track zoning/load state to ignore inventory sync packets
-- Initialize to current time so grace period is active on addon load
M.zoningTimestamp = os.clock();
M.ZONING_GRACE_PERIOD = 5.0;  -- Ignore inventory/treasure updates for 5 seconds after zoning/load

-- Called when zone packet is received OR on addon load
function M.HandleZonePacket()
    M.zoningTimestamp = os.clock();

    -- Clear party invite notifications (invites are invalid after zoning)
    if M.dataModule and M.dataModule.RemoveByType and M.dataModule.NOTIFICATION_TYPE then
        M.dataModule.RemoveByType(M.dataModule.NOTIFICATION_TYPE.PARTY_INVITE);
    end
end

-- Check if we're in the zoning/load grace period
local function isInZoningGracePeriod()
    return (os.clock() - M.zoningTimestamp) < M.ZONING_GRACE_PERIOD;
end

-- ========================================
-- Message Type Lookup Tables (O(1) lookup)
-- ========================================

-- Debug flag - set to true to see message IDs and item IDs in log
M.DEBUG_ENABLED = false;

-- Item obtained message IDs
-- Reference: FFXI message packet (0x029) message types
-- Note: param field contains item ID, value field contains quantity
-- Important: Message 6 is a DEATH message, not item obtained!
local itemObtainedMes = {
    [9] = true,     -- [Player] obtains [item]
    [65] = true,    -- You find [item] on the [mob]
    [69] = true,    -- [Player] finds [item] on the [mob]
    [98] = true,    -- You obtain an [item] from [target]
    [145] = true,   -- You obtain [item] from the [container]
    [149] = true,   -- [Player] obtains [item] from the [container]
    [376] = true,   -- [actor] uses [ability]. [target] obtains [item]
    [600] = true,   -- [actor] eats an [item]. [actor] finds an [item] inside!
};

-- Key item obtained message IDs
local keyItemObtainedMes = {
    [658] = true,   -- You obtain the key item [item]
    [659] = true,   -- [Player] obtains the key item [item]
};

-- Gil obtained message IDs
-- Note: param field contains gil amount
local gilObtainedMes = {
    [8] = true,     -- You obtain [amount] gil
    [10] = true,    -- [Player] obtains [amount] gil
    [11] = true,    -- You find [amount] gil on the [mob]
    [565] = true,   -- [target] obtains [gil]
    [582] = true,   -- [actor] obtains [gil]
};

-- ========================================
-- Data Module Reference
-- ========================================

-- Will be set by modules/notifications/init.lua
M.dataModule = nil;

function M.SetDataModule(dataModule)
    M.dataModule = dataModule;
end

-- ========================================
-- Helper Functions
-- ========================================

-- Get entity name from server ID
local function getEntityName(serverId)
    local index = GetIndexFromId(serverId);
    if index and index > 0 then
        local entity = GetEntity(index);
        if entity then
            return entity.Name;
        end
    end
    return "Unknown";
end

-- Trim null bytes from a fixed-length string
local function trimNullString(str)
    if str == nil then return "" end
    local nullPos = str:find('\0');
    if nullPos then
        return str:sub(1, nullPos - 1);
    end
    return str;
end

-- ========================================
-- Packet Handlers
-- ========================================

-- Handle party invite packet (0x00DC)
-- Structure: Party invite from another player
function M.HandlePartyInvite(e)
    if M.dataModule == nil then return end

    -- Parse packet data
    -- Offset 0x04: Unknown (index or flags)
    -- Offset 0x08: Unknown (flags)
    -- Offset 0x0C: Inviter name (16 bytes, null-terminated string)
    local inviterName = e.data:sub(0x0C + 1, 0x0C + 16);
    inviterName = inviterName:match("^[^%z]+") or "";  -- Trim at first null byte

    -- Debug output
    if M.DEBUG_ENABLED then
        print(string.format('[XIUI] 0x00DC PARTY_INVITE: name=[%s]', inviterName));
    end

    -- Validate - need a name
    if inviterName == nil or inviterName == '' then
        inviterName = 'Unknown';
    end

    -- Add notification via data module
    if M.dataModule.AddPartyInviteNotification then
        M.dataModule.AddPartyInviteNotification(inviterName, nil);
    end
end

-- Handle party invite response (outgoing packet 0x0074)
-- Called when player accepts or declines a party invite
function M.HandlePartyInviteResponse(e)
    if M.dataModule == nil then return end

    -- Debug output
    if M.DEBUG_ENABLED then
        print('[XIUI] 0x0074 PARTY_INVITE_RESPONSE: Removing party invite notification');
    end

    -- Remove party invite notification when player responds
    if M.dataModule.RemoveByType and M.dataModule.NOTIFICATION_TYPE then
        M.dataModule.RemoveByType(M.dataModule.NOTIFICATION_TYPE.PARTY_INVITE);
    end
end

-- Handle trade request packet (0x0021)
-- Structure: Trade request from another player
function M.HandleTradeRequest(e)
    if M.dataModule == nil then return end

    -- Parse packet data
    -- Offset 0x04: Trader server ID (4 bytes)
    local traderId = struct.unpack('I4', e.data, 0x04 + 1);

    -- Validate server ID
    if not valid_server_id(traderId) then
        return;
    end

    -- Get trader name from entity
    local traderName = getEntityName(traderId);

    -- Add notification via data module
    if M.dataModule.AddTradeRequestNotification then
        M.dataModule.AddTradeRequestNotification(traderName, traderId);
    end
end

-- Trade response kind values (GP_ITEM_TRADE_RES_KIND enum)
local TRADE_KIND = {
    START = 0,          -- Trade window opened
    CANCEL = 1,         -- Trade cancelled
    MAKE = 2,           -- Trade completed
    MAKE_CANCEL = 3,    -- Trade completion cancelled
    -- 4+ are various error types
};

-- Handle trade response packet (0x0022)
-- Structure: Trade action response (cancel, complete, error, etc.)
function M.HandleTradeResponse(e)
    if M.dataModule == nil then return end

    -- Parse packet data
    -- Offset 0x04: UniqueNo (server ID) - 4 bytes
    -- Offset 0x08: Kind (trade action type) - 4 bytes
    local serverId = struct.unpack('I4', e.data, 0x04 + 1);
    local kind = struct.unpack('I4', e.data, 0x08 + 1);

    -- Debug output
    if M.DEBUG_ENABLED then
        print(string.format('[XIUI] 0x0022 TRADE_RES: kind=%d serverId=%d', kind, serverId));
    end

    -- Any kind except START means the trade is ending/ended
    -- Remove trade notification
    if kind ~= TRADE_KIND.START then
        if M.dataModule.RemoveByType and M.dataModule.NOTIFICATION_TYPE then
            M.dataModule.RemoveByType(M.dataModule.NOTIFICATION_TYPE.TRADE_INVITE);
        end
    end
end

-- Handle message packet (0x0029) for item/gil/key item obtained
-- This parses the already-parsed message packet structure
function M.HandleMessagePacket(e, messagePacket)
    if M.dataModule == nil then return end
    if messagePacket == nil then return end

    local message = messagePacket.message;
    local param = messagePacket.param;
    local value = messagePacket.value;

    -- Debug output when enabled - log ALL messages to find item drop message IDs
    if M.DEBUG_ENABLED then
        local item = AshitaCore:GetResourceManager():GetItemById(param);
        local itemName = (item and item.Name and item.Name[1]) or 'nil';
        local handled = itemObtainedMes[message] and 'ITEM' or (gilObtainedMes[message] and 'GIL' or '-');
        print(string.format('[XIUI] msg=%d p=%d v=%d item=%s [%s]',
            message, param, value, itemName, handled));
    end

    -- Check for item obtained
    if itemObtainedMes[message] then
        -- Check if items notifications are enabled
        if not gConfig.notificationsShowItems then return end
        -- param contains item ID
        -- value contains quantity
        if M.dataModule.AddItemObtainedNotification then
            M.dataModule.AddItemObtainedNotification(param, value or 1);
        end
    -- Check for key item obtained
    elseif keyItemObtainedMes[message] then
        -- Check if key items notifications are enabled
        if not gConfig.notificationsShowKeyItems then return end
        -- param contains key item ID
        if M.dataModule.AddKeyItemObtainedNotification then
            M.dataModule.AddKeyItemObtainedNotification(param);
        end
    -- Check for gil obtained
    elseif gilObtainedMes[message] then
        -- Check if gil notifications are enabled
        if not gConfig.notificationsShowGil then return end
        -- param contains gil amount (not value)
        if M.dataModule.AddGilObtainedNotification then
            M.dataModule.AddGilObtainedNotification(param or 0);
        end
    end
end

-- ========================================
-- Inventory Update Packet (0x020)
-- ========================================

-- Handle inventory item update packet (0x020)
-- NOTE: This packet fires for ALL inventory changes including zone sync.
-- We do NOT use this for notifications - item notifications come from
-- the message packet (0x0029) which shows actual "You obtained X" messages.
-- This handler is kept for potential future use but does nothing currently.
function M.HandleInventoryUpdate(e)
    -- Intentionally empty - do not create notifications from inventory sync packets
    -- Item obtained notifications are handled by HandleMessagePacket (0x0029)
end

-- ========================================
-- Treasure Pool Packet (0x00D2) - Found Item
-- ========================================

-- Handle treasure pool update packet (0x00D2)
-- Packet structure:
-- 0x08-0x0B: Dropper ID (mob server ID) - 4 bytes
-- 0x0C-0x0F: Count - 4 bytes
-- 0x10-0x11: Item ID - 2 bytes
-- 0x12-0x13: Dropper Index - 2 bytes
-- 0x14: Pool slot index (0-9) - 1 byte
-- 0x15: Old flag - 1 byte
-- 0x18-0x1B: Timestamp - 4 bytes
function M.HandleTreasurePool(e)
    if M.dataModule == nil then return end

    -- Skip treasure pool sync during zoning grace period
    if isInZoningGracePeriod() then return end

    -- Parse full packet structure
    local dropperId = struct.unpack('I4', e.data, 0x08 + 1);
    local count = struct.unpack('I4', e.data, 0x0C + 1);
    local itemId = struct.unpack('H', e.data, 0x10 + 1);
    local slot = struct.unpack('B', e.data, 0x14 + 1);
    local oldFlag = struct.unpack('B', e.data, 0x15 + 1);
    local timestamp = struct.unpack('I4', e.data, 0x18 + 1);

    -- Debug output
    if M.DEBUG_ENABLED then
        local item = AshitaCore:GetResourceManager():GetItemById(itemId);
        local itemName = (item and item.Name and item.Name[1]) or 'nil';
        print(string.format('[XIUI] 0x0D2 POOL: slot=%d item=%d(%s) count=%d old=%d ts=%d',
            slot, itemId, itemName, count, oldFlag, timestamp));
    end

    -- Check if treasure notifications are enabled
    if not gConfig.notificationsShowTreasure then return end

    -- Skip invalid item IDs
    if itemId == nil or itemId == 0 or itemId == 65535 then return end

    -- Check if we already have this item tracked in this slot (e.g., after zoning)
    -- If so, keep our existing data to preserve the timer
    if M.dataModule.treasurePool and M.dataModule.treasurePool[slot] then
        local existingItem = M.dataModule.treasurePool[slot];
        if existingItem.itemId == itemId then
            -- Same item in same slot - keep existing data (preserve timer)
            return;
        end
    end

    -- Add to treasure pool state
    -- showToast = false if oldFlag is set (item existed before we started tracking)
    local showToast = (oldFlag ~= 1);
    if M.dataModule.AddTreasurePoolItem then
        M.dataModule.AddTreasurePoolItem(slot, itemId, dropperId, count, timestamp, showToast);
    end
end

-- ========================================
-- Treasure Lot/Drop Packet (0x00D3)
-- ========================================

-- Handle treasure lot/drop packet (0x00D3)
-- Packet structure:
-- 0x04-0x07: Highest Lotter ID - 4 bytes
-- 0x08-0x0B: Current Lotter ID - 4 bytes
-- 0x0C-0x0D: Highest Lotter Index - 2 bytes
-- 0x0E-0x0F: Highest Lot value - 2 bytes
-- 0x10-0x11: Current Lotter Index - 2 bytes
-- 0x12-0x13: Current Lot value - 2 bytes
-- 0x14: Pool slot index - 1 byte
-- 0x15: Drop status (0=pending, 1=awarded, 2=lost) - 1 byte
-- 0x16-0x25: Highest Lotter Name - 16 bytes
-- 0x26-0x35: Current Lotter Name - 16 bytes
function M.HandleTreasureLot(e)
    if M.dataModule == nil then return end

    -- Skip treasure lot sync during zoning grace period
    if isInZoningGracePeriod() then return end

    -- Parse packet structure
    local highestLotterId = struct.unpack('I4', e.data, 0x04 + 1);
    local currentLotterId = struct.unpack('I4', e.data, 0x08 + 1);
    local highestLot = struct.unpack('H', e.data, 0x0E + 1);
    local currentLot = struct.unpack('H', e.data, 0x12 + 1);
    local slot = struct.unpack('B', e.data, 0x14 + 1);
    local dropStatus = struct.unpack('B', e.data, 0x15 + 1);
    local highestLotterNameRaw = struct.unpack('c16', e.data, 0x16 + 1);
    local currentLotterNameRaw = struct.unpack('c16', e.data, 0x26 + 1);
    local highestLotterName = trimNullString(highestLotterNameRaw);
    local currentLotterName = trimNullString(currentLotterNameRaw);

    -- Debug output
    if M.DEBUG_ENABLED then
        print(string.format('[XIUI] 0x0D3 LOT: slot=%d status=%d curr=%s(%d) high=%s(%d)',
            slot, dropStatus, currentLotterName or '-', currentLot or 0,
            highestLotterName or '-', highestLot or 0));
    end

    -- Check if treasure notifications are enabled
    if not gConfig.notificationsShowTreasure then return end

    -- Update treasure pool item with lot info
    if M.dataModule.UpdateTreasurePoolLot then
        M.dataModule.UpdateTreasurePoolLot(
            slot,
            currentLotterId,
            currentLotterName,
            currentLot,
            highestLotterId,
            highestLotterName,
            highestLot,
            dropStatus
        );
    end
end

-- Clear treasure state (call on zone change)
function M.ClearTreasureState()
    if M.dataModule and M.dataModule.ClearTreasurePool then
        M.dataModule.ClearTreasurePool();
    end
end

return M;
