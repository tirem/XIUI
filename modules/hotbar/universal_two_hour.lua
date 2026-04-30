--[[
  HorizonXI main-job two-hour ability names (job ID → English name).
  Used for: JA list pink marker + sort + Global "Universal 2 Hour" macro resolution.
]]--

local M = {};

-- Stored on macro rows as action name; resolved at command/icon/recast time.
M.ACTION_SENTINEL = '__XIUI_UNIVERSAL_TWO_HOUR__';

M.PINK_STAR_TWO_HOUR_TOOLTIP =
    '2Hour - Main Job Only - Universal Macro available under "Global"';

M.PINK_STAR_ASTRAL_FLOW_TOOLTIP = 'This Ability is only available during Astral Flow';

-- Horizon roster (no GEO/RUN in this list — extend when those jobs exist in data).
local JOB_TWO_HOUR = {
    [1]  = 'Mighty Strikes',
    [2]  = 'Hundred Fists',
    [3]  = 'Benediction',
    [4]  = 'Manafont',
    [5]  = 'Chainspell',
    [6]  = 'Perfect Dodge',
    [7]  = 'Invincible',
    [8]  = 'Blood Weapon',
    [9]  = 'Familiar',
    [10] = 'Soul Voice',
    [11] = 'Eagle Eye Shot',
    [12] = 'Meikyo Shisui',
    [13] = 'Mikage',
    [14] = 'Spirit Surge',
    [15] = 'Astral Flow',
    [16] = 'Azure Lore',
    [17] = 'Wild Card',
    [18] = 'Overdrive',
    [19] = 'Trance',
    [20] = 'Tabula Rasa',
};

--- Macro /ja target token (no <me> / <t>): stpc = confirm player (self two-hours); stnpc = confirm NPC (Eagle Eye Shot).
local JOB_TWO_HOUR_TARGET = {
    [1]  = 'stpc',
    [2]  = 'stpc',
    [3]  = 'stpc',
    [4]  = 'stpc',
    [5]  = 'stpc',
    [6]  = 'stpc',
    [7]  = 'stpc',
    [8]  = 'stpc',
    [9]  = 'stpc',
    [10] = 'stpc',
    [11] = 'stnpc',
    [12] = 'stpc',
    [13] = 'stpc',
    [14] = 'stpc',
    [15] = 'stpc',
    [16] = 'stpc',
    [17] = 'stpc',
    [18] = 'stpc',
    [19] = 'stpc',
    [20] = 'stpc',
};

-- After firing /ja "<two-hour>" <stpc|stnpc>, glow this slot while subtarget is open; disarm when subtarget closes.
local subtargetGlowArmUntil = 0;
local sawSubtargetWhileArmed = false;
local SUBTARGET_GLOW_ARM_SECONDS = 45;
--- After /ja queues, subtarget may open a frame later (especially with no prior target).
local lastUniversalTwoHourNotifyClock = 0;
local ARMING_SHIMMER_SECONDS = 7.5;
--- During pre-subtarget arming only: full opacity until this elapsed second, then linear fade to 0 at ARMING_SHIMMER_SECONDS.
local ARMING_OPACITY_FADE_START = 6.5;

function M.GetTwoHourNameForJobId(jobId)
    if not jobId or jobId <= 0 then
        return nil;
    end
    return JOB_TWO_HOUR[jobId];
end

function M.GetTwoHourAbilityNameForMainJob()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then
        return nil;
    end
    return M.GetTwoHourNameForJobId(player:GetMainJob());
end

function M.GetTwoHourTargetTokenForJobId(jobId)
    if not jobId or jobId < 1 then
        return nil;
    end
    return JOB_TWO_HOUR_TARGET[jobId];
end

function M.GetTwoHourTargetTokenForMainJob()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then
        return 'stpc';
    end
    local jid = player:GetMainJob();
    return M.GetTwoHourTargetTokenForJobId(jid) or 'stpc';
end

function M.ResolveJaActionName(action)
    if action == M.ACTION_SENTINEL then
        return M.GetTwoHourAbilityNameForMainJob();
    end
    return action;
end

--- Resolved palette/hotbar target for JA rows (forces stpc/stnpc for the Universal 2 Hour sentinel).
function M.ResolveJaBindTarget(bind)
    if not bind or bind.actionType ~= 'ja' then
        return bind and bind.target;
    end
    if bind.action == M.ACTION_SENTINEL then
        return M.GetTwoHourTargetTokenForMainJob();
    end
    return bind.target;
end

function M.NotifyUniversalTwoHourExecuted()
    subtargetGlowArmUntil = os.clock() + SUBTARGET_GLOW_ARM_SECONDS;
    sawSubtargetWhileArmed = false;
    lastUniversalTwoHourNotifyClock = os.clock();
end

function M.ResetUniversalTwoHourSubtargetGlowArm()
    subtargetGlowArmUntil = 0;
    sawSubtargetWhileArmed = false;
    lastUniversalTwoHourNotifyClock = 0;
end

--- 1 while subtarget is active or before fade window; during pre-subtarget arming after ARMING_OPACITY_FADE_START, ramps to 0 at ARMING_SHIMMER_SECONDS.
function M.GetArmingShimmerOpacityScale()
    if sawSubtargetWhileArmed then
        return 1.0;
    end
    local elapsed = os.clock() - lastUniversalTwoHourNotifyClock;
    if elapsed < ARMING_OPACITY_FADE_START then
        return 1.0;
    end
    if elapsed >= ARMING_SHIMMER_SECONDS then
        return 0.0;
    end
    local dur = ARMING_SHIMMER_SECONDS - ARMING_OPACITY_FADE_START;
    if dur <= 0 then
        return 1.0;
    end
    return 1.0 - ((elapsed - ARMING_OPACITY_FADE_START) / dur);
end

--- Hotbar/crossbar slot glow: armed after executing this bind, while game subtarget UI is active.
function M.ShouldGlowUniversalTwoHourSlot(bind)
    if not bind or bind.actionType ~= 'ja' or bind.action ~= M.ACTION_SENTINEL then
        return false;
    end
    local now = os.clock();
    if subtargetGlowArmUntil <= 0 or now > subtargetGlowArmUntil then
        subtargetGlowArmUntil = 0;
        sawSubtargetWhileArmed = false;
        return false;
    end
    local ok, targetLib = pcall(require, 'libs.target');
    local active = false;
    if ok and targetLib and targetLib.GetSubTargetActive then
        active = targetLib.GetSubTargetActive();
    end
    if active then
        sawSubtargetWhileArmed = true;
        return true;
    end
    -- Arm shimmer: game may open subtarget shortly after QueueCommand (visible when main target was empty).
    if not sawSubtargetWhileArmed and (now - lastUniversalTwoHourNotifyClock) < ARMING_SHIMMER_SECONDS then
        return true;
    end
    -- Subtarget closed after we saw it: confirm or cancel — stop glowing and disarm.
    if sawSubtargetWhileArmed then
        subtargetGlowArmUntil = 0;
        sawSubtargetWhileArmed = false;
    end
    return false;
end

function M.IsHorizonTwoHourAbility(jobId, abilityName)
    if not abilityName or not jobId then
        return false;
    end
    return JOB_TWO_HOUR[jobId] == abilityName;
end

function M.GetTwoHourPinkTooltipIfApplicable(jobId, abilityName)
    if M.IsHorizonTwoHourAbility(jobId, abilityName) then
        return M.PINK_STAR_TWO_HOUR_TOOLTIP;
    end
    return nil;
end

--- Sort rank: 0 = main-job two-hour for this row's job, 1 = normal.
function M.TwoHourSortRank(jobId, abilityName)
    return M.IsHorizonTwoHourAbility(jobId, abilityName) and 0 or 1;
end

return M;
