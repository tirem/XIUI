--[[
* XIUI Treasure Pool - Data Module
* Reads treasure pool state from Ashita memory API
* Memory is single source of truth - no packet handling for pool state
]]--

require('common');

local M = {};

-- Debug logging (set to true to enable)
local DEBUG_ENABLED = false;
local function debugLog(msg, ...)
    if DEBUG_ENABLED then
        local formatted = string.format('[TP Data] ' .. msg, ...);
        print(formatted);
    end
end

-- ============================================
-- Constants
-- ============================================

M.MAX_POOL_SLOTS = 10;              -- Maximum treasure pool slots (0-9)
M.POOL_TIMEOUT_SECONDS = 300;       -- 5 minutes pool timeout
M.MAX_HISTORY_ITEMS = 20;           -- Maximum items to keep in won history

-- ============================================
-- State
-- ============================================

-- Current pool state from memory (slot -> item data)
M.poolItems = {};

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

-- Won item history (for recent history tab)
-- Structure: array of { itemId, itemName, winnerName, winnerLot, wonAt (os.time) }
-- Newest items at front of array (index 1)
M.wonHistory = {};

-- Preview won history (for config preview mode)
M.previewWonHistory = {};

-- ============================================
-- Helper Functions
-- ============================================

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

            -- Note: Notifications are handled by notificationhandler.lua via 0x00D2 packet
            -- to properly handle auto-award vs staying-in-pool scenarios

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
        -- Sort by expiration time descending (newest items at top)
        table.sort(M.sortedCache, function(a, b)
            return (a.expiresAt or 0) > (b.expiresAt or 0);
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

-- Mock won history items for preview (15 items to test scrolling)
-- Item IDs verified from FFXIAH.com
local PREVIEW_WON_HISTORY = {
    { itemId = 17440, name = 'Kraken Club', winner = 'Aetherius', lot = 987 },       -- https://www.ffxiah.com/item/17440
    { itemId = 13014, name = 'Leaping Boots', winner = 'Brutalix', lot = 876 },      -- https://www.ffxiah.com/item/13014
    { itemId = 12579, name = 'Scorpion Harness', winner = 'Celestine', lot = 765 },  -- https://www.ffxiah.com/item/12579
    { itemId = 16555, name = 'Ridill', winner = 'Darkblade', lot = 943 },            -- https://www.ffxiah.com/item/16555
    { itemId = 13189, name = 'Speed Belt', winner = 'Elyndra', lot = 654 },          -- https://www.ffxiah.com/item/13189
    { itemId = 13280, name = 'Sniper\'s Ring', winner = 'Frostwind', lot = 821 },    -- https://www.ffxiah.com/item/13280
    { itemId = 13056, name = 'Peacock Charm', winner = 'Galeheart', lot = 432 },     -- https://www.ffxiah.com/item/13056
    { itemId = 13281, name = 'Sniper\'s Ring +1', winner = 'Havocborn', lot = 567 }, -- https://www.ffxiah.com/item/13281
    { itemId = 844, name = 'Phoenix Feather', winner = 'Ironveil', lot = 234 },      -- https://www.ffxiah.com/item/844
    { itemId = 1313, name = 'Siren\'s Hair', winner = 'Jadestorm', lot = 789 },      -- https://www.ffxiah.com/item/1313
    { itemId = 644, name = 'Mythril Ore', winner = 'Kiraflame', lot = 345 },         -- https://www.ffxiah.com/item/644
    { itemId = 4145, name = 'Elixir', winner = 'Lunashade', lot = 456 },             -- https://www.ffxiah.com/item/4145
    { itemId = 4116, name = 'Hi-Potion', winner = 'Moonsaber', lot = 123 },          -- https://www.ffxiah.com/item/4116
    { itemId = 13748, name = 'Vermillion Cloak', winner = 'Nightfall', lot = 678 },  -- https://www.ffxiah.com/item/13748
    { itemId = 12555, name = 'Haubergeon', winner = 'Oakenshield', lot = 912 },      -- https://www.ffxiah.com/item/12555
};

-- Generate mock won history for preview mode
local function generateMockWonHistory()
    local history = {};
    local now = os.time();
    for i, item in ipairs(PREVIEW_WON_HISTORY) do
        history[i] = {
            itemId = item.itemId,
            itemName = item.name,
            winnerName = item.winner,
            winnerLot = item.lot,
            wonAt = now - (i * 60),  -- Stagger times (1 minute apart)
        };
    end
    return history;
end

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
        -- Generate mock won history for preview
        M.previewWonHistory = generateMockWonHistory();
    else
        M.previewItems = {};
        M.previewWonHistory = {};
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
    M.previewWonHistory = {};
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
    debugLog('HandleLotPacket: slot=%s judge=%s winner=%s lot=%s entry=%s',
        tostring(slot), tostring(judgeFlg), tostring(winnerName), tostring(winnerLot), tostring(entryName));

    -- Validate slot
    if slot == nil or slot < 0 or slot >= M.MAX_POOL_SLOTS then
        debugLog('HandleLotPacket: Invalid slot %s', tostring(slot));
        return;
    end

    -- Handle item won/cleared (JudgeFlg >= 1)
    if judgeFlg and judgeFlg >= 1 then
        -- Get item info before clearing (from current pool)
        local item = M.poolItems[slot];
        debugLog('HandleLotPacket: judgeFlg=%d, item=%s, poolItems[%d]=%s',
            judgeFlg, item and item.itemName or 'nil', slot, item and 'exists' or 'nil');

        -- The judge=1 packet often has winnerLot=0, so use stored winner info from lotHistory
        -- which was populated from earlier judge=0 packets that had the actual lot value
        local storedWinner = M.lotHistory[slot] and M.lotHistory[slot].winner;
        local finalWinnerName = winnerName;
        local finalWinnerLot = winnerLot;

        -- If packet has winnerLot=0 but we have stored winner data, use that
        if (not finalWinnerLot or finalWinnerLot <= 0) and storedWinner then
            finalWinnerName = storedWinner.name or finalWinnerName;
            finalWinnerLot = storedWinner.lot or 0;
            debugLog('HandleLotPacket: Using stored winner data: %s lot=%d',
                finalWinnerName, finalWinnerLot);
        end

        if item and finalWinnerName and finalWinnerName ~= '' and finalWinnerLot and finalWinnerLot > 0 then
            -- Add to won history (insert at front)
            local historyEntry = {
                itemId = item.itemId,
                itemName = item.itemName or getItemName(item.itemId),
                winnerName = finalWinnerName,
                winnerLot = finalWinnerLot,
                wonAt = os.time(),
            };
            table.insert(M.wonHistory, 1, historyEntry);
            debugLog('HandleLotPacket: Added to history: %s won by %s (%d), total history=%d',
                historyEntry.itemName, historyEntry.winnerName, historyEntry.winnerLot, #M.wonHistory);

            -- Trim history to max size
            while #M.wonHistory > M.MAX_HISTORY_ITEMS do
                table.remove(M.wonHistory);
            end
        else
            debugLog('HandleLotPacket: NOT added to history - item=%s winnerName=%s winnerLot=%s',
                item and 'exists' or 'nil', tostring(finalWinnerName), tostring(finalWinnerLot));
        end

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
    -- entryFlg: 0 = lot action, 1 = pass action (primary indicator)
    -- entryLot: lot value if lotting, -1 (0xFFFF signed) if passing without prior lot
    if entryServerId and entryServerId > 0 and entryName and entryName ~= '' then
        local isPass = (entryFlg and entryFlg == 1) or (entryLot and entryLot < 0);
        if isPass then
            -- Pass action
            history.passers[entryServerId] = { name = entryName };
            -- Remove from lotters if they previously lotted
            history.lotters[entryServerId] = nil;
        elseif entryLot and entryLot >= 0 then
            -- Lot action (entryLot is the actual lot value, 0-999)
            history.lotters[entryServerId] = { name = entryName, lot = entryLot };
            -- Remove from passers if they previously passed (re-lot)
            history.passers[entryServerId] = nil;
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

-- Get all party members organized by party with their status for a slot
-- Returns: { partyA = {members}, partyB = {members}, partyC = {members} }
-- Each party array has up to 6 members in slot order (index 0-5 within party)
function M.GetMembersByParty(slot)
    local result = {
        partyA = {},  -- indices 0-5
        partyB = {},  -- indices 6-11
        partyC = {},  -- indices 12-17
    };

    -- In preview mode, use mock data (put all in party A for simplicity)
    if M.previewEnabled and M.lotHistory[slot] then
        local history = M.lotHistory[slot];
        local idx = 1;
        for serverId, data in pairs(history.lotters or {}) do
            if idx <= 6 then
                result.partyA[idx] = { serverId = serverId, name = data.name, status = 'lotted', lot = data.lot };
                idx = idx + 1;
            end
        end
        for serverId, data in pairs(history.passers or {}) do
            if idx <= 6 then
                result.partyA[idx] = { serverId = serverId, name = data.name, status = 'passed' };
                idx = idx + 1;
            end
        end
        for serverId, data in pairs(history.pending or {}) do
            if idx <= 6 then
                result.partyA[idx] = { serverId = serverId, name = data.name, status = 'pending' };
                idx = idx + 1;
            end
        end
        return result;
    end

    -- Get party interface
    local party = GetPartySafe();
    if not party then return result; end

    -- Build lookup tables for this slot
    local lotters = {};
    local passers = {};
    if M.lotHistory[slot] then
        for serverId, data in pairs(M.lotHistory[slot].lotters or {}) do
            lotters[serverId] = data;
        end
        for serverId, data in pairs(M.lotHistory[slot].passers or {}) do
            passers[serverId] = data;
        end
    end

    -- Helper to add member to appropriate party (uses GetMemberIsActive like partylist)
    local function addMember(i, targetParty)
        -- Use GetMemberIsActive to filter out stale/inactive slots (same as partylist module)
        if party:GetMemberIsActive(i) == 0 then
            return;
        end

        local serverId = party:GetMemberServerId(i);
        if serverId and serverId > 0 then
            local name = party:GetMemberName(i);
            if name and name ~= '' then
                -- Build member data
                local member = { serverId = serverId, name = name, partyIndex = i };
                if lotters[serverId] then
                    member.status = 'lotted';
                    member.lot = lotters[serverId].lot;
                elseif passers[serverId] then
                    member.status = 'passed';
                else
                    member.status = 'pending';
                end

                -- Find next available slot in target party
                for s = 1, 6 do
                    if not targetParty[s] then
                        targetParty[s] = member;
                        break;
                    end
                end
            end
        end
    end

    -- Party A: indices 0-5 (your party)
    for i = 0, 5 do
        addMember(i, result.partyA);
    end

    -- Party B: indices 6-11 (alliance party 2)
    for i = 6, 11 do
        addMember(i, result.partyB);
    end

    -- Party C: indices 12-17 (alliance party 3)
    for i = 12, 17 do
        addMember(i, result.partyC);
    end

    return result;
end

-- Check if a party has any members
function M.PartyHasMembers(partyData)
    for i = 1, 6 do
        if partyData[i] then return true; end
    end
    return false;
end

-- Count actual members in a party (returns 0-6)
function M.GetPartyMemberCount(partyData)
    local count = 0;
    for i = 1, 6 do
        if partyData[i] then count = count + 1; end
    end
    return count;
end

-- Get max member count across all parties for a slot
-- Used to calculate dynamic row height in expanded view
function M.GetMaxMemberCount(partyData)
    local countA = M.GetPartyMemberCount(partyData.partyA);
    local countB = M.GetPartyMemberCount(partyData.partyB);
    local countC = M.GetPartyMemberCount(partyData.partyC);
    local maxCount = math.max(countA, countB, countC);
    -- Minimum of 1 row if any party has members
    if maxCount < 1 and (countA > 0 or countB > 0 or countC > 0) then
        maxCount = 1;
    end
    return maxCount;
end

-- Check if we have any lot history for a slot
function M.HasLotHistory(slot)
    if not M.lotHistory[slot] then return false; end
    local history = M.lotHistory[slot];
    return next(history.lotters) ~= nil or next(history.passers) ~= nil or history.winner ~= nil;
end

-- ============================================
-- Won History (Recent History Tab)
-- ============================================

-- Get all won history items (newest first)
function M.GetWonHistory()
    if M.previewEnabled then
        return M.previewWonHistory;
    end
    return M.wonHistory;
end

-- Get won history count
function M.GetWonHistoryCount()
    if M.previewEnabled then
        return #M.previewWonHistory;
    end
    return #M.wonHistory;
end

-- Check if there is any won history
function M.HasWonHistory()
    if M.previewEnabled then
        return #M.previewWonHistory > 0;
    end
    return #M.wonHistory > 0;
end

-- Clear won history
function M.ClearWonHistory()
    M.wonHistory = {};
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

-- Tab fonts
M.tabPoolFont = nil;    -- "Pool" tab label
M.tabHistoryFont = nil; -- "History" tab label

-- History fonts (for recent history tab)
-- Each history entry needs: item name, winner name + lot
M.historyItemFonts = {};    -- index -> font (item name)
M.historyWinnerFonts = {};  -- index -> font (winner: lot)

M.allFonts = nil;

-- Error message state (for displaying validation errors)
M.lastErrorMessage = nil;        -- Last error message to display
M.lastErrorSlot = nil;           -- Slot the error is for
M.lastErrorTime = 0;             -- When the error occurred (os.clock())
M.ERROR_DISPLAY_DURATION = 3.0;  -- How long to show error messages (seconds)

-- Set an error message for a slot
function M.SetError(slot, message)
    M.lastErrorMessage = message;
    M.lastErrorSlot = slot;
    M.lastErrorTime = os.clock();
end

-- Get current error for a slot (returns nil if expired or different slot)
function M.GetError(slot)
    if M.lastErrorMessage == nil then return nil; end
    if M.lastErrorSlot ~= slot then return nil; end

    local elapsed = os.clock() - M.lastErrorTime;
    if elapsed > M.ERROR_DISPLAY_DURATION then
        M.lastErrorMessage = nil;
        M.lastErrorSlot = nil;
        return nil;
    end

    return M.lastErrorMessage;
end

-- Clear error message
function M.ClearError()
    M.lastErrorMessage = nil;
    M.lastErrorSlot = nil;
    M.lastErrorTime = 0;
end

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
    tabPool = nil,
    tabHistory = nil,
    historyItems = {},   -- [index] = color
    historyWinners = {}, -- [index] = color
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
        tabPool = nil,
        tabHistory = nil,
        historyItems = {},
        historyWinners = {},
    };
end

-- ============================================
-- Item Validation Helpers
-- ============================================

-- Item flag constants
local ITEM_FLAG_RARE = 0x8000;  -- 32768 - Can only have one
local ITEM_FLAG_EX   = 0x4000;  -- 16384 - Cannot be traded

-- Check if an item has the Rare flag set (via resource data)
function M.IsItemRare(itemId)
    if itemId == nil or itemId == 0 or itemId == 65535 then
        return false;
    end

    local item = AshitaCore:GetResourceManager():GetItemById(itemId);
    if item == nil or item.Flags == nil then
        return false;
    end

    return bit.band(item.Flags, ITEM_FLAG_RARE) == ITEM_FLAG_RARE;
end

-- Check if player already has an item in main inventory (container 0)
function M.PlayerHasItemInInventory(itemId)
    if itemId == nil or itemId == 0 or itemId == 65535 then
        return false;
    end

    local memMgr = AshitaCore:GetMemoryManager();
    if not memMgr then return false; end

    local inventory = memMgr:GetInventory();
    if not inventory then return false; end

    -- Container 0 = main inventory
    local maxSlots = inventory:GetContainerCountMax(0);
    if maxSlots == nil or maxSlots <= 0 then return false; end

    -- Iterate through all inventory slots (1-based indexing for item slots)
    for slotIndex = 1, maxSlots do
        local item = inventory:GetContainerItem(0, slotIndex);
        if item ~= nil and item.Id == itemId then
            return true;
        end
    end

    return false;
end

-- Check if player's main inventory is full
function M.IsInventoryFull()
    local memMgr = AshitaCore:GetMemoryManager();
    if not memMgr then return false; end

    local inventory = memMgr:GetInventory();
    if not inventory then return false; end

    -- Container 0 = main inventory
    local usedSlots = inventory:GetContainerCount(0);
    local maxSlots = inventory:GetContainerCountMax(0);

    if usedSlots == nil or maxSlots == nil then return false; end

    return usedSlots >= maxSlots;
end

-- Preview mode validation overrides (only these items show warnings in preview)
local PREVIEW_VALIDATION = {
    [17440] = 'Already have Kraken Club (Rare)',  -- Kraken Club - show as already owned
    [13014] = 'Inventory is full',                 -- Leaping Boots - show as full inventory
};

-- Validate if player can lot on an item
-- Returns: canLot (boolean), errorMessage (string or nil)
function M.ValidateLotItem(slot)
    -- In preview mode, use mock validation
    if M.previewEnabled then
        local item = M.previewItems[slot];
        if not item then
            return true, nil;  -- No item = no validation needed
        end
        -- Check if this item has a mock validation error
        local mockError = PREVIEW_VALIDATION[item.itemId];
        if mockError then
            return false, mockError;
        end
        return true, nil;  -- Most preview items pass validation
    end

    -- Normal mode: check real pool items
    local item = M.poolItems[slot];
    if not item then
        return false, nil;  -- No error message for missing item
    end

    local itemId = item.itemId;

    -- Check if inventory is full
    if M.IsInventoryFull() then
        return false, 'Inventory is full';
    end

    -- Check if item is Rare and player already has one
    if M.IsItemRare(itemId) and M.PlayerHasItemInInventory(itemId) then
        local itemName = item.itemName or 'this item';
        return false, 'Already have ' .. itemName .. ' (Rare)';
    end

    return true, nil;
end

-- ============================================
-- Lifecycle
-- ============================================

-- Initialize data module
function M.Initialize()
    M.poolItems = {};
    M.timestampCache = {};
    M.sortedCache = {};
    M.sortedCacheDirty = true;
    M.previewEnabled = false;
    M.previewItems = {};
    M.lotHistory = {};
    M.missingFrameCount = {};
    -- Note: wonHistory is NOT cleared on init to preserve history across reloads
end

-- Clear all state (call on zone change)
function M.Clear()
    M.poolItems = {};
    M.timestampCache = {};
    M.sortedCache = {};
    M.sortedCacheDirty = true;
    M.lotHistory = {};
    M.missingFrameCount = {};
    M.ClearError();
end

-- Cleanup (call on addon unload)
function M.Cleanup()
    M.Clear();
end

return M;
