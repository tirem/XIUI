--[[
* XIUI Enemy Cast Tracker
* Shared tracking of enemy spellcasting / TP abilities for the target bar and enemy list.
* Handles begin/finish/interrupt detection and the white "interrupted" flash.
]]--

require('common');
local encoding = require('libs.encoding');

local M = {};

-- Battle-message ids that mean an in-progress cast broke: 16 = interrupted
-- (damage/silence/move/range), 84 = paralyzed, 106 = intimidated.
local INTERRUPT_MESSAGES = { [16] = true, [84] = true, [106] = true };

-- How long the white "interrupted" flash lingers before the cast is removed.
M.FLASH_DURATION = 1;
-- Grace period after cast time before a bar with no finish packet is dropped.
local FINISH_GRACE = 2.0;
-- Absolute stale-cast cleanup (seconds).
local STALE_TIMEOUT = 30;

-- [serverId] = { spellName, spellId, castTime, startTime, timestamp,
--                interrupted, interruptTime, interruptProgress }
local casts = {};

function M.GetCast(serverId)
    return serverId ~= nil and casts[serverId] or nil;
end

-- Mark a tracked cast interrupted so consumers flash it white, freezing the
-- fill where it stopped. No-op if nothing is tracked for this actor.
function M.BeginInterruptFlash(serverId)
    local cast = M.GetCast(serverId);
    if cast == nil or cast.interrupted then
        return;
    end
    cast.interrupted = true;
    cast.interruptTime = os.clock();
    local elapsed = os.clock() - (cast.startTime or os.clock());
    cast.interruptProgress = math.min(elapsed / (cast.castTime or 1), 1.0);
end

-- Per-frame render state for a cast bar. Returns whether to draw, progress
-- (0..1), an optional white flash overlay { '#ffffff', alpha }, the spell name,
-- and the cast target's server id. Clears finished/expired casts as a side effect.
function M.GetRenderState(serverId)
    local cast = M.GetCast(serverId);
    if cast == nil then
        return false;
    end

    if cast.interrupted then
        local flashElapsed = os.clock() - (cast.interruptTime or os.clock());
        if flashElapsed >= M.FLASH_DURATION then
            casts[serverId] = nil;
            return false;
        end
        return true, cast.interruptProgress or 1.0,
            {'#ffffff', 1.0 - (flashElapsed / M.FLASH_DURATION)}, 'Interrupted', nil;
    end

    local elapsed = os.clock() - cast.startTime;
    if elapsed > cast.castTime + FINISH_GRACE then
        casts[serverId] = nil;
        return false;
    end
    return true, math.min(elapsed / cast.castTime, 1.0), nil, cast.spellName, cast.targetId;
end

-- 0x0028 action packets: Type 7/8 begins a cast, Type 4/11 finishes it.
M.HandleActionPacket = function(actionPacket)
    if actionPacket == nil or actionPacket.UserId == nil then
        return;
    end

    -- Type 7 = Ability / monster TP move (start)
    if actionPacket.Type == 7 then
        if actionPacket.Targets and #actionPacket.Targets > 0 and
           actionPacket.Targets[1].Actions and #actionPacket.Targets[1].Actions > 0 then
            local abilityId = actionPacket.Targets[1].Actions[1].Param;
            local actionMessage = actionPacket.Targets[1].Actions[1].Message;

            -- Interrupted ability (same signal as PR #396)
            if actionMessage == 0 then
                M.BeginInterruptFlash(actionPacket.UserId);
                return;
            end

            local abilityNameRaw = nil;
            if abilityId < 256 then
                local ability = AshitaCore:GetResourceManager():GetAbilityById(abilityId);
                if ability ~= nil and ability.Name ~= nil then
                    abilityNameRaw = ability.Name[1];
                end
            else
                abilityNameRaw = AshitaCore:GetResourceManager():GetString('monsters.abilities', abilityId - 256);
            end

            if abilityNameRaw ~= nil and abilityNameRaw ~= '' then
                casts[actionPacket.UserId] = {
                    spellName = encoding:ShiftJIS_To_UTF8(abilityNameRaw, true),
                    spellId = abilityId,
                    targetId = actionPacket.Targets[1].Id,
                    castTime = 3, -- ability ready time isn't exposed; progress caps until Type 11
                    startTime = os.clock(),
                    timestamp = os.time(),
                };
            end
        end
    elseif actionPacket.Type == 8 then
        if actionPacket.Targets and #actionPacket.Targets > 0 and
           actionPacket.Targets[1].Actions and #actionPacket.Targets[1].Actions > 0 then
            local spellId = actionPacket.Targets[1].Actions[1].Param;
            local existing = casts[actionPacket.UserId];

            -- Second Type 8 for the same spell = interruption signal; flash then clear.
            if existing ~= nil and existing.spellId == spellId then
                M.BeginInterruptFlash(actionPacket.UserId);
                return;
            end
            if existing ~= nil and existing.spellId ~= spellId then
                casts[actionPacket.UserId] = nil;
            end

            local spell = AshitaCore:GetResourceManager():GetSpellById(spellId);
            if spell ~= nil and spell.Name ~= nil and spell.Name[1] ~= nil then
                casts[actionPacket.UserId] = {
                    spellName = encoding:ShiftJIS_To_UTF8(spell.Name[1], true),
                    spellId = spellId,
                    -- Cast target straight from the begin-cast packet (reliable,
                    -- unlike the action tracker which ignores Type 8).
                    targetId = actionPacket.Targets[1].Id,
                    castTime = spell.CastTime / 4.0,  -- quarter seconds -> seconds
                    startTime = os.clock(),
                    timestamp = os.time(),
                };
            end
        end
    -- Type 4 = Magic (Finish); Type 11 = Monster Skill (Finish). Either resolved,
    -- or broke via paralyze/intimidate (msg 84/106) which flashes instead.
    elseif actionPacket.Type == 4 or actionPacket.Type == 11 then
        local finishMsg;
        if actionPacket.Targets and #actionPacket.Targets > 0 and
           actionPacket.Targets[1].Actions and #actionPacket.Targets[1].Actions > 0 then
            finishMsg = actionPacket.Targets[1].Actions[1].Message;
        end
        if finishMsg ~= nil and INTERRUPT_MESSAGES[finishMsg] then
            M.BeginInterruptFlash(actionPacket.UserId);
        else
            casts[actionPacket.UserId] = nil;
        end
    end

    local now = os.time();
    for serverId, data in pairs(casts) do
        if data.timestamp + STALE_TIMEOUT < now then
            casts[serverId] = nil;
        end
    end
end

-- 0x0029 battle messages: the cleanest interrupt signal (msg 16 = interrupted).
-- The message actor (sender) is the same server id casts are keyed on.
M.HandleMessagePacket = function(messagePacket)
    if messagePacket == nil or messagePacket.message == nil then
        return;
    end
    if INTERRUPT_MESSAGES[messagePacket.message] then
        M.BeginInterruptFlash(messagePacket.sender);
    end
end

M.HandleZonePacket = function()
    casts = {};
end

return M;
