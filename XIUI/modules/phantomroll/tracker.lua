--[[
* Tracks the two Phantom Rolls a Corsair can keep. Action packets own totals
* and duration; 0x63 type 9 (id + time in one packet) corrects and clears.
]]--

local data = require('modules.phantomroll.data');
local vanatime = require('libs.vanatime');

local M = {};

local MAX_SLOTS = 2;
-- Action packet lands before 0x63; keep the new seat until its buff id shows.
local CLEAR_GRACE = 3;

local slots = {};
local rollSequence = 0;
local doubleUp = nil;

local presentBuf, timersBuf, bustTimesBuf = {}, {}, {};
local bustTimesN = 0;
local bustUsedBuf = {};

local function Remaining(expiresAt)
    if expiresAt == nil then return 0; end
    return math.max(0, expiresAt - os.clock());
end

local function ClearMap(map)
    for key in pairs(map) do map[key] = nil; end
end

local function HorizonMode()
    local settings = gAdjustedSettings and gAdjustedSettings.phantomRollSettings;
    return settings ~= nil and settings.horizonMode == true;
end

local function ArmTimer(entry, duration)
    local now = os.clock();
    entry.expiresAt = now + duration;
    entry.duration = duration;
    entry.armedAt = now;
    entry.pending = true;
end

-- 0x63 pairs each id with its own time, so a live Evoker's (324) and a
-- busted Evoker's (309) keep independent clocks even when both are named the same.
local function AdoptTimer(entry, seconds, now)
    if entry == nil or seconds == nil or seconds < 0 then return; end
    entry.expiresAt = now + seconds;
    if seconds > 0 then
        entry.duration = math.max(entry.duration or seconds, seconds);
    end
end

local function MatchBustStamp(entry)
    local left = Remaining(entry.expiresAt);
    local best, bestDist = nil, math.huge;
    for j = 1, bustTimesN do
        if not bustUsedBuf[j] then
            local seconds = bustTimesBuf[j];
            if seconds ~= nil then
                local dist = math.abs(seconds - left);
                if dist < bestDist then
                    best, bestDist = j, dist;
                end
            end
        end
    end
    if best == nil then return nil; end
    bustUsedBuf[best] = true;
    return bustTimesBuf[best];
end

-- Reuse this roll, else an empty seat, else the live roll that expires first.
-- Never evicts a bust (Hunter replacing Chaos must leave a busted seat).
local function ClaimSlot(statusId)
    local empty, oldest, shortest = nil, nil, math.huge;
    for i = 1, MAX_SLOTS do
        local entry = slots[i];
        if entry == nil then
            empty = empty or i;
        elseif not entry.busted then
            if entry.status == statusId then return i; end
            local left = Remaining(entry.expiresAt);
            if left < shortest then
                oldest, shortest = i, left;
            end
        end
    end
    return empty or oldest;
end

local function LatestOpenRoll()
    local best = nil;
    for i = 1, MAX_SLOTS do
        local entry = slots[i];
        if entry ~= nil and not entry.busted then
            if best == nil or entry.sequence > slots[best].sequence then
                best = i;
            end
        end
    end
    return best;
end

local function RollTotal(actionPacket, serverId)
    if actionPacket.Targets == nil then return nil; end

    local fallback = nil;
    for _, target in ipairs(actionPacket.Targets) do
        local action = target.Actions and target.Actions[1];
        if action ~= nil then
            if target.Id == serverId then return action.Param; end
            fallback = fallback or action.Param;
        end
    end
    return fallback;
end

local function ApplyRoll(roll, total, reuse)
    local index = ClaimSlot(roll.status);
    if index == nil then return; end

    local entry = slots[index];
    if not reuse then
        entry = { ability = roll.ability, status = roll.status, sequence = 0 };
        slots[index] = entry;
    elseif entry == nil or entry.status ~= roll.status then
        entry = { ability = roll.ability, status = roll.status, sequence = 0 };
        slots[index] = entry;
        reuse = false;
    end

    -- This server resets roll duration on Double-Up as well as a new roll.
    ArmTimer(entry, data.BASE_DURATION);

    rollSequence = rollSequence + 1;
    entry.total = total;
    entry.sequence = rollSequence;
    entry.busted = total > data.MAX_TOTAL;
    entry.context = data.Context(HorizonMode());

    if entry.busted then
        doubleUp = nil;
        return;
    end

    if not reuse or doubleUp == nil then
        doubleUp = {};
        ArmTimer(doubleUp, data.DOUBLE_UP_DURATION);
    end
end

M.HandleActionPacket = function(actionPacket)
    if actionPacket == nil or actionPacket.Type ~= data.JOB_ABILITY_CATEGORY then return; end

    local party = AshitaCore:GetMemoryManager():GetParty();
    local serverId = party and party:GetMemberServerId(0);
    if serverId == nil or actionPacket.UserId ~= serverId then return; end

    local total = RollTotal(actionPacket, serverId);
    if total == nil then return; end

    if actionPacket.Param == data.DOUBLE_UP_ABILITY then
        local index = LatestOpenRoll();
        if index == nil then return; end
        local entry = slots[index];
        local roll = data.ByAbility(entry.ability, HorizonMode());
        if roll == nil then return; end
        ApplyRoll(roll, total, true);
        return;
    end

    local roll = data.ByAbility(actionPacket.Param);
    if roll == nil then return; end

    local reuse = false;
    for i = 1, MAX_SLOTS do
        if slots[i] ~= nil and slots[i].status == roll.status and not slots[i].busted then
            reuse = true;
            break;
        end
    end
    ApplyRoll(roll, total, reuse);
end

-- 0x63 type 9 lists each buff id next to its duration. Never poll GetStatusTimers.
M.HandleBuffPacket = function(packet)
    if packet == nil then return; end
    local blob = packet.data_modified or packet.data;
    if blob == nil or blob:byte(5) ~= 9 then return; end

    ClearMap(presentBuf);
    ClearMap(timersBuf);
    ClearMap(bustUsedBuf);
    bustTimesN = 0;

    local stamp = vanatime.Utc();
    for i = 0, 31 do
        local statusId = struct.unpack('H', blob, 0x08 + (i * 2) + 1);
        if statusId ~= 0 and statusId ~= 0xFF and data.IsTrackedStatus(statusId) then
            local raw = struct.unpack('L', blob, 0x48 + (i * 4) + 1);
            local seconds = vanatime.StatusSeconds(raw, stamp);
            if statusId == data.BUST_STATUS then
                bustTimesN = bustTimesN + 1;
                bustTimesBuf[bustTimesN] = seconds;
                presentBuf[statusId] = true;
            else
                presentBuf[statusId] = true;
                if seconds ~= nil then timersBuf[statusId] = seconds; end
            end
        end
    end

    local now = os.clock();
    for i = 1, MAX_SLOTS do
        local entry = slots[i];
        if entry ~= nil then
            if entry.busted then
                -- Timer is 309 only. Do not read entry.status: a re-roll of the
                -- same roll (live 324 + busted 324) must not keep or clear this seat.
                local seconds = MatchBustStamp(entry);
                if seconds ~= nil then
                    entry.pending = false;
                    AdoptTimer(entry, seconds, now);
                elseif (not entry.pending) or (now - (entry.armedAt or 0) > CLEAR_GRACE) then
                    slots[i] = nil;
                end
            elseif presentBuf[entry.status] then
                entry.pending = false;
                AdoptTimer(entry, timersBuf[entry.status], now);
            elseif (not entry.pending) or (now - (entry.armedAt or 0) > CLEAR_GRACE) then
                slots[i] = nil;
            end
        end
    end

    if doubleUp ~= nil then
        if presentBuf[data.DOUBLE_UP_STATUS] then
            doubleUp.pending = false;
            AdoptTimer(doubleUp, timersBuf[data.DOUBLE_UP_STATUS], now);
        elseif (not doubleUp.pending) or (now - (doubleUp.armedAt or 0) > CLEAR_GRACE) then
            doubleUp = nil;
        end
    end
end

M.DoubleUp = function()
    local seconds = Remaining(doubleUp and doubleUp.expiresAt);
    if seconds <= 0 then return nil, 0; end

    local best = LatestOpenRoll();
    if best == nil then return nil, seconds; end
    return best, seconds;
end

-- Presence is 0x63's job. Local 0:00 on two 300s seeds started seconds apart
-- would wipe live Evoker's with its bust even while 324 is still on you.
M.Sync = function()
    if doubleUp ~= nil and Remaining(doubleUp.expiresAt) <= 0 and not doubleUp.pending then
        doubleUp = nil;
    end
end

M.SecondsLeft = function(entry)
    if entry == nil or entry.expiresAt == nil then return nil; end
    return Remaining(entry.expiresAt);
end

M.Slots = function()
    return slots;
end

M.HasAny = function()
    return slots[1] ~= nil or slots[2] ~= nil;
end

M.Clear = function()
    slots = {};
    rollSequence = 0;
    doubleUp = nil;
end

M.Demo = function()
    local horizon = HorizonMode();
    local hunters = data.ByAbility(108, horizon);
    local chaos = data.ByAbility(105, horizon);
    local now = os.clock();

    local function DemoSeat(roll, total, left, sequence)
        return {
            ability = roll.ability,
            status = roll.status,
            total = total,
            sequence = sequence,
            busted = false,
            expiresAt = now + left,
            duration = data.BASE_DURATION,
        };
    end

    slots = {
        DemoSeat(hunters, hunters.lucky, 268, 1),
        DemoSeat(chaos, chaos.unlucky, 154, 2),
    };
    rollSequence = 2;
    doubleUp = { expiresAt = now + 32, duration = data.DOUBLE_UP_DURATION };
end

return M;
