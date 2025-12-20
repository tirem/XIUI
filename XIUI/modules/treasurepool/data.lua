--[[
* XIUI Treasure Pool - Data Module
* Reads treasure pool state from Ashita memory API
* Memory is single source of truth - no packet handling for pool state
]]--

require('common');

local M = {};

-- ============================================
-- Constants
-- ============================================

M.MAX_POOL_SLOTS = 10;              -- Maximum treasure pool slots (0-9)
M.POOL_TIMEOUT_SECONDS = 300;       -- 5 minutes pool timeout

-- ============================================
-- State
-- ============================================

-- Current pool state from memory (slot -> item data)
M.poolItems = {};

-- Previous frame pool state (for detecting new items)
M.previousPoolState = {};

-- Timestamp cache for expiration times
-- Maps DropTime -> cached expiration time
M.timestampCache = {};

-- Sorted pool cache (avoid allocation every frame)
M.sortedCache = {};
M.sortedCacheDirty = true;

-- Preview mode state
M.previewEnabled = false;
M.previewItems = {};

-- Lot history per slot (tracked from 0x00D3 packets)
-- Structure: lotHistory[slot] = { lotters = {}, passers = {}, winner = {} }
M.lotHistory = {};

-- ============================================
-- Helper Functions
-- ============================================

-- Get notifications module lazily (avoid circular require)
local notificationsModule = nil;
local function getNotificationsModule()
    if notificationsModule == nil then
        local success, mod = pcall(require, 'modules.notifications.init');
        if success then
            notificationsModule = mod;
        end
    end
    return notificationsModule;
end

-- Get item name from resource manager
local function getItemName(itemId)
    if itemId == nil or itemId == 0 or itemId == -1 or itemId == 65535 then
        return 'Unknown Item';
    end
    local item = AshitaCore:GetResourceManager():GetItemById(itemId);
    if item and item.Name and item.Name[1] then
        local name = item.Name[1];
        if name ~= nil and name ~= '' then
            return name;
        end
    end
    return 'Unknown Item';
end

-- Mark sorted cache as needing rebuild
local function markCacheDirty()
    M.sortedCacheDirty = true;
end

-- ============================================
-- Memory Reading
-- ============================================

-- Grace period tracking - items must be missing for multiple frames before removal
-- This handles race conditions where memory state may be temporarily invalid
M.missingFrameCount = {};  -- slot -> number of consecutive frames item was missing
local GRACE_FRAMES = 3;    -- Number of frames item must be missing before removal

-- Read treasure pool state from memory API
-- Call this every frame in DrawWindow
-- Returns true if pool has items, false otherwise
function M.ReadFromMemory()
    local memMgr = AshitaCore:GetMemoryManager();
    if not memMgr then return false; end

    local inventory = memMgr:GetInventory();
    if not inventory then return false; end

    local now = os.time();
    local hasItems = false;
    local activeSlots = {};

    -- Read all 10 pool slots from memory
    for slot = 0, M.MAX_POOL_SLOTS - 1 do
        local item = inventory:GetTreasurePoolItem(slot);

        if item ~= nil and item.ItemId ~= nil and item.ItemId > 0 and item.ItemId ~= 65535 then
            hasItems = true;
            activeSlots[slot] = true;
            M.missingFrameCount[slot] = 0;  -- Reset missing count

            -- Check if this is a NEW item we haven't seen
            local isNewItem = not M.previousPoolState[slot] or
                             M.previousPoolState[slot].itemId ~= item.ItemId;

            -- Cache expiration time
            if not M.timestampCache[item.DropTime] then
                M.timestampCache[item.DropTime] = now + M.POOL_TIMEOUT_SECONDS;
            end

            -- Build pool item data
            M.poolItems[slot] = {
                slot = slot,
                itemId = item.ItemId,
                itemName = getItemName(item.ItemId),
                count = 1,
                expiresAt = M.timestampCache[item.DropTime],
                dropTime = item.DropTime,
                -- Lot info from memory
                playerLot = item.Lot,
                winningLot = item.WinningLot,
                winningLotterName = item.WinningEntityName or '',
            };

            -- Trigger toast notification for NEW items
            if isNewItem then
                -- Check if notifications are enabled
                if gConfig and gConfig.notificationsShowTreasure then
                    local notifMod = getNotificationsModule();
                    if notifMod and notifMod.AddTreasurePoolNotification then
                        notifMod.AddTreasurePoolNotification(item.ItemId, 1);
                    end
                end
            end

            markCacheDirty();
        end
    end

    -- Remove items no longer in memory (with grace period)
    for slot, poolItem in pairs(M.poolItems) do
        if not activeSlots[slot] then
            -- Increment missing frame count
            M.missingFrameCount[slot] = (M.missingFrameCount[slot] or 0) + 1;

            if M.missingFrameCount[slot] >= GRACE_FRAMES then
                -- Item has been missing for multiple frames, safe to remove
                M.poolItems[slot] = nil;
                M.missingFrameCount[slot] = nil;
                markCacheDirty();
            else
                -- Keep item for grace period
                hasItems = true;  -- Still has items during grace period
            end
        end
    end

    -- Update previous state for next frame comparison
    M.previousPoolState = {};
    for slot, item in pairs(M.poolItems) do
        M.previousPoolState[slot] = {
            itemId = item.itemId,
        };
    end

    return hasItems;
end

-- ============================================
-- Pool State Queries
-- ============================================

-- Get pool item by slot
function M.GetPoolItem(slot)
    return M.poolItems[slot];
end

-- Check if preview mode is active
function M.IsPreviewActive()
    return M.previewEnabled;
end

-- Get all pool items (returns the internal table directly)
function M.GetPoolItems()
    if M.IsPreviewActive() then
        return M.previewItems;
    end
    return M.poolItems;
end

-- Get sorted pool items for display (cached to avoid allocation every frame)
function M.GetSortedPoolItems()
    local sourceItems = M.IsPreviewActive() and M.previewItems or M.poolItems;

    if M.sortedCacheDirty then
        M.sortedCache = {};
        local idx = 1;
        for slot, item in pairs(sourceItems) do
            if item and item.slot ~= nil and item.slot >= 0 and item.slot < M.MAX_POOL_SLOTS then
                M.sortedCache[idx] = item;
                idx = idx + 1;
            end
        end
        -- Sort by slot index
        table.sort(M.sortedCache, function(a, b)
            return (a.slot or 999) < (b.slot or 999);
        end);
        M.sortedCacheDirty = false;
    end
    return M.sortedCache;
end

-- Get pool item count
function M.GetPoolCount()
    local count = 0;
    for _ in pairs(M.poolItems) do
        count = count + 1;
    end
    return count;
end

-- Check if pool has items (includes preview items when preview is active)
function M.HasItems()
    if M.IsPreviewActive() then
        return next(M.previewItems) ~= nil;
    end
    return next(M.poolItems) ~= nil;
end

-- Check if pool has real items (from memory, ignores preview)
function M.HasRealItems()
    return next(M.poolItems) ~= nil;
end

-- Get time remaining for a pool item (in seconds)
function M.GetTimeRemaining(slot)
    local sourceItems = M.IsPreviewActive() and M.previewItems or M.poolItems;
    local item = sourceItems[slot];
    if not item then return 0; end

    local remaining = item.expiresAt - os.time();
    return math.max(0, remaining);
end

-- Format time as M:SS
function M.FormatTime(seconds)
    local mins = math.floor(seconds / 60);
    local secs = seconds % 60;
    return string.format("%d:%02d", mins, secs);
end

-- Check if player has lotted on this item
-- Returns: 'lotted' (1-999), 'passed' (65535), 'pending' (0 or nil)
function M.GetPlayerLotStatus(slot)
    local item = M.poolItems[slot];
    if not item then return 'pending'; end

    local lot = item.playerLot;
    if lot == nil or lot == 0 then
        return 'pending';
    elseif lot >= 65535 then
        return 'passed';
    else
        return 'lotted';
    end
end

-- Get player's lot value (nil if not lotted)
function M.GetPlayerLotValue(slot)
    local item = M.poolItems[slot];
    if not item then return nil; end

    local lot = item.playerLot;
    if lot and lot > 0 and lot < 65535 then
        return lot;
    end
    return nil;
end

-- ============================================
-- Preview Mode
-- ============================================

-- Test item IDs for preview (8 items)
-- Item IDs verified from FFXIAH.com
local PREVIEW_ITEMS = {
    { itemId = 13014, name = 'Leaping Boots' },     -- https://www.ffxiah.com/item/13014
    { itemId = 17440, name = 'Kraken Club' },       -- https://www.ffxiah.com/item/17440
    { itemId = 12579, name = 'Scorpion Harness' },  -- https://www.ffxiah.com/item/12579
    { itemId = 4116, name = 'Hi-Potion' },          -- https://www.ffxiah.com/item/4116
    { itemId = 4145, name = 'Elixir' },             -- https://www.ffxiah.com/item/4145
    { itemId = 644, name = 'Mythril Ore' },         -- https://www.ffxiah.com/item/644
    { itemId = 1313, name = 'Siren\'s Hair' },      -- https://www.ffxiah.com/item/1313
    { itemId = 844, name = 'Phoenix Feather' },     -- https://www.ffxiah.com/item/844
};

-- Mock alliance member names for preview
local PREVIEW_MEMBERS = {
    -- Party 1
    { serverId = 1001, name = 'Aetherius' },
    { serverId = 1002, name = 'Brutalix' },
    { serverId = 1003, name = 'Celestine' },
    { serverId = 1004, name = 'Darkblade' },
    { serverId = 1005, name = 'Elyndra' },
    { serverId = 1006, name = 'Frostwind' },
    -- Party 2
    { serverId = 2001, name = 'Galeheart' },
    { serverId = 2002, name = 'Havocborn' },
    { serverId = 2003, name = 'Ironveil' },
    { serverId = 2004, name = 'Jadestorm' },
    { serverId = 2005, name = 'Kiraflame' },
    { serverId = 2006, name = 'Lunashade' },
    -- Party 3
    { serverId = 3001, name = 'Moonsaber' },
    { serverId = 3002, name = 'Nightfall' },
    { serverId = 3003, name = 'Oakenshield' },
    { serverId = 3004, name = 'Pyrewing' },
    { serverId = 3005, name = 'Quicksilver' },
    { serverId = 3006, name = 'Ravencrest' },
};

-- Generate mock lot history for a slot with varied states
local function generateMockLotHistory(slot)
    local history = { lotters = {}, passers = {}, pending = {}, winner = nil };

    -- Different distribution patterns per slot for variety
    local patterns = {
        [0] = { lotted = {1,2,3}, passed = {4,5}, pending = {6,7,8,9,10,11,12,13,14,15,16,17,18} },  -- Few lots, few passes
        [1] = { lotted = {1,3,5,7,9,11}, passed = {2,4,6}, pending = {8,10,12,13,14,15,16,17,18} },  -- Many lots
        [2] = { lotted = {1}, passed = {2,3,4,5,6,7,8,9}, pending = {10,11,12,13,14,15,16,17,18} },  -- Many passes
        [3] = { lotted = {1,2,3,4,5,6}, passed = {7,8,9,10,11,12}, pending = {13,14,15,16,17,18} },  -- Half and half
        [4] = { lotted = {}, passed = {}, pending = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18} },  -- All pending
        [5] = { lotted = {1,2}, passed = {3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18}, pending = {} },  -- Mostly passed
        [6] = { lotted = {1,2,3,4,5,6,7,8,9,10}, passed = {11,12}, pending = {13,14,15,16,17,18} },  -- Mostly lotted
        [7] = { lotted = {1,4,7,10,13,16}, passed = {2,5,8,11,14,17}, pending = {3,6,9,12,15,18} },  -- Even spread
    };

    local pattern = patterns[slot] or patterns[0];

    -- Add lotters
    for _, idx in ipairs(pattern.lotted) do
        local member = PREVIEW_MEMBERS[idx];
        if member then
            history.lotters[member.serverId] = {
                name = member.name,
                lot = math.random(100, 999),
            };
        end
    end

    -- Add passers
    for _, idx in ipairs(pattern.passed) do
        local member = PREVIEW_MEMBERS[idx];
        if member then
            history.passers[member.serverId] = {
                name = member.name,
            };
        end
    end

    -- Add pending members
    for _, idx in ipairs(pattern.pending) do
        local member = PREVIEW_MEMBERS[idx];
        if member then
            history.pending[member.serverId] = {
                name = member.name,
            };
        end
    end

    -- Set winner (highest lotter if any exist)
    local highestLot = 0;
    local winnerId = nil;
    for serverId, data in pairs(history.lotters) do
        if data.lot > highestLot then
            highestLot = data.lot;
            winnerId = serverId;
        end
    end
    if winnerId then
        history.winner = {
            serverId = winnerId,
            name = history.lotters[winnerId].name,
            lot = highestLot,
        };
    end

    return history;
end

-- Populate preview items if not already done
local function ensurePreviewItems()
    if next(M.previewItems) ~= nil then return; end

    local now = os.time();
    for i, item in ipairs(PREVIEW_ITEMS) do
        local slot = i - 1;

        -- Generate mock lot history for this slot
        local history = generateMockLotHistory(slot);
        M.lotHistory[slot] = history;

        -- Get winner info from history
        local winningLot = history.winner and history.winner.lot or 0;
        local winningName = history.winner and history.winner.name or '';

        M.previewItems[slot] = {
            slot = slot,
            itemId = item.itemId,
            itemName = item.name,
            count = 1,
            expiresAt = now + (300 - (i * 30)),  -- Stagger expiration times (30s apart)
            dropTime = 0,
            playerLot = 0,
            winningLot = winningLot,
            winningLotterName = winningName,
        };
    end
    markCacheDirty();
end

-- Set preview mode
function M.SetPreview(enabled)
    M.previewEnabled = enabled;
    if enabled then
        ensurePreviewItems();
    else
        M.previewItems = {};
        -- Clear mock lot history
        for slot = 0, M.MAX_POOL_SLOTS - 1 do
            M.lotHistory[slot] = nil;
        end
    end
    markCacheDirty();
end

-- Clear all preview state (call when config closes)
function M.ClearPreview()
    M.previewEnabled = false;
    M.previewItems = {};
    -- Clear mock lot history
    for slot = 0, M.MAX_POOL_SLOTS - 1 do
        M.lotHistory[slot] = nil;
    end
    markCacheDirty();
end

-- ============================================
-- Lot History Tracking (from 0x00D3 packets)
-- ============================================

-- Handle lot packet from XIUI.lua
-- Called when 0x00D3 packet is received
function M.HandleLotPacket(slot, entryServerId, entryName, entryFlg, entryLot,
                           winnerServerId, winnerName, winnerLot, judgeFlg)
    -- Validate slot
    if slot == nil or slot < 0 or slot >= M.MAX_POOL_SLOTS then return; end

    -- Handle item won/cleared (JudgeFlg >= 1)
    if judgeFlg and judgeFlg >= 1 then
        -- Item awarded or cleared - remove from tracking
        M.lotHistory[slot] = nil;
        return;
    end

    -- Initialize slot if needed
    if not M.lotHistory[slot] then
        M.lotHistory[slot] = { lotters = {}, passers = {}, winner = nil };
    end

    local history = M.lotHistory[slot];

    -- Track the action if we have valid entry data
    if entryServerId and entryServerId > 0 and entryName and entryName ~= '' then
        if entryFlg == 1 then
            -- Lot action
            history.lotters[entryServerId] = { name = entryName, lot = entryLot or 0 };
            -- Remove from passers if they previously passed (re-lot)
            history.passers[entryServerId] = nil;
        else
            -- Pass action
            history.passers[entryServerId] = { name = entryName };
            -- Remove from lotters if they previously lotted (shouldn't happen but be safe)
            history.lotters[entryServerId] = nil;
        end
    end

    -- Update current winner
    if winnerServerId and winnerServerId > 0 and winnerLot and winnerLot > 0 then
        history.winner = { serverId = winnerServerId, name = winnerName or '', lot = winnerLot };
    end
end

-- Get all lotters for a slot (sorted by lot value, highest first)
function M.GetLotters(slot)
    if not M.lotHistory[slot] then return {}; end
    local result = {};
    for serverId, data in pairs(M.lotHistory[slot].lotters) do
        table.insert(result, { serverId = serverId, name = data.name, lot = data.lot });
    end
    table.sort(result, function(a, b) return (a.lot or 0) > (b.lot or 0); end);
    return result;
end

-- Get all passers for a slot
function M.GetPassers(slot)
    if not M.lotHistory[slot] then return {}; end
    local result = {};
    for serverId, data in pairs(M.lotHistory[slot].passers) do
        table.insert(result, { serverId = serverId, name = data.name });
    end
    return result;
end

-- Get pending party members (those who haven't lotted or passed)
function M.GetPending(slot)
    local result = {};

    -- In preview mode, use mock pending data
    if M.previewEnabled and M.lotHistory[slot] and M.lotHistory[slot].pending then
        for serverId, data in pairs(M.lotHistory[slot].pending) do
            table.insert(result, { serverId = serverId, name = data.name });
        end
        return result;
    end

    -- Get party interface
    local party = GetPartySafe();
    if not party then return result; end

    -- Build set of acted players
    local acted = {};
    if M.lotHistory[slot] then
        for serverId, _ in pairs(M.lotHistory[slot].lotters) do
            acted[serverId] = true;
        end
        for serverId, _ in pairs(M.lotHistory[slot].passers) do
            acted[serverId] = true;
        end
    end

    -- Check main party (indices 0-5)
    for i = 0, 5 do
        local serverId = party:GetMemberServerId(i);
        if serverId and serverId > 0 and not acted[serverId] then
            local name = party:GetMemberName(i);
            if name and name ~= '' then
                table.insert(result, { serverId = serverId, name = name });
            end
        end
    end

    return result;
end

-- Get winner for a slot (from lot history, may have more detail than memory)
function M.GetWinner(slot)
    if not M.lotHistory[slot] then return nil; end
    return M.lotHistory[slot].winner;
end

-- Check if we have any lot history for a slot
function M.HasLotHistory(slot)
    if not M.lotHistory[slot] then return false; end
    local history = M.lotHistory[slot];
    return next(history.lotters) ~= nil or next(history.passers) ~= nil or history.winner ~= nil;
end

-- ============================================
-- Font Storage (created by init.lua, used by display.lua)
-- ============================================

M.headerFont = nil;
M.itemNameFonts = {};   -- slot -> font
M.timerFonts = {};      -- slot -> font
M.lotFonts = {};        -- slot -> font

-- Expanded view fonts (per slot)
M.lottersFonts = {};    -- slot -> font (for "Lotters: ..." line)
M.passersFonts = {};    -- slot -> font (for "Passed: ..." line)
M.pendingFonts = {};    -- slot -> font (for "Pending: ..." line)

-- Expanded member fonts: 18 members per slot (3 columns x 6 rows for alliance)
-- Structure: memberFonts[slot][memberIdx] where memberIdx = 0-17
M.MAX_MEMBERS_PER_ITEM = 18;
M.memberFonts = {};     -- slot -> { [0] = font, [1] = font, ... [17] = font }

-- Button label fonts
M.lotAllFont = nil;     -- "Lot" button label
M.passAllFont = nil;    -- "Pass" button label
M.lotItemFonts = {};    -- slot -> font ("L" button per item)
M.passItemFonts = {};   -- slot -> font ("P" button per item)
M.toggleFont = nil;     -- [v]/[^] toggle icon

M.allFonts = nil;

-- Color cache (to avoid expensive set_font_color calls)
M.lastColors = {
    header = nil,
    itemNames = {},
    timers = {},
    lots = {},
    lotters = {},
    passers = {},
    pending = {},
    lotAll = nil,
    passAll = nil,
    lotItems = {},
    passItems = {},
    toggle = nil,
    members = {},  -- [slot][memberIdx] = color
};

-- Helper to set all fonts visible/hidden
function M.SetAllFontsVisible(visible)
    if M.allFonts then
        SetFontsVisible(M.allFonts, visible);
    end
end

-- Clear color cache
function M.ClearColorCache()
    M.lastColors = {
        header = nil,
        itemNames = {},
        timers = {},
        lots = {},
        lotters = {},
        passers = {},
        pending = {},
        lotAll = nil,
        passAll = nil,
        lotItems = {},
        passItems = {},
        toggle = nil,
        members = {},
    };
end

-- ============================================
-- Lifecycle
-- ============================================

-- Initialize data module
function M.Initialize()
    M.poolItems = {};
    M.previousPoolState = {};
    M.timestampCache = {};
    M.sortedCache = {};
    M.sortedCacheDirty = true;
    M.previewEnabled = false;
    M.previewItems = {};
    M.lotHistory = {};
    M.missingFrameCount = {};
end

-- Clear all state (call on zone change)
function M.Clear()
    M.poolItems = {};
    M.previousPoolState = {};
    M.timestampCache = {};
    M.sortedCache = {};
    M.sortedCacheDirty = true;
    M.lotHistory = {};
    M.missingFrameCount = {};
end

-- Cleanup (call on addon unload)
function M.Cleanup()
    M.Clear();
end

return M;
