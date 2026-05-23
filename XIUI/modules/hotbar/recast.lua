--[[
* XIUI hotbar - Recast Tracking Module
* Tracks spell, ability, and item cooldowns via Ashita memory
* Provides shared cooldown info for hotbar and crossbar
]]--

local abilityRecast = require('libs.abilityrecast');
local itemRecast = require('libs.itemrecast');
local actiondb = require('modules.hotbar.actiondb');
local petregistry = require('modules.hotbar.petregistry');
local universalTwoHour = require('modules.hotbar.universal_two_hour');

local M = {};

-- Lazy require: actions.lua requires recast.lua (circular). Resolved at first call.
local actionsModule = nil;
local function getActionsModule()
    if not actionsModule then
        actionsModule = require('modules.hotbar.actions');
    end
    return actionsModule;
end

local function normalizeCommandName(name)
    if not name then return nil; end
    local s = tostring(name):gsub('^%s+', ''):gsub('%s+$', '');
    if s == '' then return nil; end
    return s:lower();
end

-- Module-level setting for Hh:MM format (set once per frame, used by all functions)
local useHHMMFormat = false;

-- Set the Hh:MM format preference (call once per frame before any recast queries)
function M.SetHHMMFormat(enabled)
    useHHMMFormat = enabled or false;
end

-- Blood Pact timer IDs
local BP_RAGE_TIMER_ID = 173;
local BP_WARD_TIMER_ID = 174;

-- Get Blood Pact timer ID by command name.
-- Case-insensitive: slot labels / macro text can differ in casing from registry entries; otherwise
-- we fall through to ability-id lookup and miss the shared BP timer (173/174) entirely.
local function GetBloodPactTimerId(commandName)
    local want = normalizeCommandName(commandName);
    if not want then return nil; end

    for _, pact in ipairs(petregistry.bloodPactsRage or {}) do
        if pact.name and normalizeCommandName(pact.name) == want then
            return BP_RAGE_TIMER_ID;
        end
    end

    for _, pact in ipairs(petregistry.bloodPactsWard or {}) do
        if pact.name and normalizeCommandName(pact.name) == want then
            return BP_WARD_TIMER_ID;
        end
    end

    return nil;
end

-- Use Horizon spell list / recast index for /ma. Same resolution as castcost/icons —
-- otherwise duplicate English names (e.g. SummonerPact) can return the wrong spell ID.
local function resolveSpellIndexForMa(spellName)
    if not spellName then return nil; end
    local am = getActionsModule();
    if am and am.GetHorizonSpellForIconResolution then
        local row = am.GetHorizonSpellForIconResolution(spellName, 'ma');
        if row then
            local idx = row.recast_id or row.id;
            if idx then return idx; end
        end
    end
    return actiondb.GetSpellId(spellName);
end

-- Fixed ability recast component IDs (Windower recast_id / memory compId) for /pet-style commands.
-- FindAbilityRecast(abilityId) often fails when no pet is active because slots are cleared/rebound,
-- but GetAbilityRecastSeconds(timerId) still reads the correct timer (e.g. Release 172).
-- Source: Windower Resources job_abilities (PetCommand); aligns with castcost abilityLookup where present.
local PET_COMMAND_TIMER_ID_BY_NAME = {
    ['fight'] = 100,
    ['heel'] = 101,
    ['stay'] = 101,
    ['leave'] = 101,
    ['sic'] = 102,
    ['ready'] = 102,
    ['snarl'] = 107,
    ['dismiss'] = 161,
    ['assault'] = 170,
    ['retreat'] = 171,
    ['release'] = 172,
    ['deploy'] = 207,
    ['deactivate'] = 208,
    ['retrieve'] = 209,
    ["avatar's favor"] = 176,
    ['steady wing'] = 70,
    ['smiting breath'] = 238,
    ['restoring breath'] = 239,
};

local function getPetCommandTimerIdByName(commandName)
    local n = normalizeCommandName(commandName);
    if not n then return nil; end
    local tid = PET_COMMAND_TIMER_ID_BY_NAME[n];
    if tid then return tid; end
    if n:match('maneuver$') then
        return 210;
    end
    return nil;
end

-- Fallback: read timer component id from Ashita ability resource when available
-- (covers gaps / Horizon-specific rows the static table doesn't list).
local function getRecastTimerIdFromAbilityResource(commandName)
    local resMgr = AshitaCore:GetResourceManager();
    if not resMgr then return nil; end
    local aid = actiondb.GetAbilityId(commandName);
    if not aid then return nil; end
    local ab = resMgr:GetAbilityById(aid);
    if not ab then return nil; end
    local tid = ab.TimerId or ab.RecastTimerId or ab.timer_id or ab.RecastId;
    if type(tid) == 'number' and tid > 0 then
        return tid;
    end
    return nil;
end

-- Resolve recast using shared BP timer, static pet-command timer id, or resource timer id
-- BEFORE falling back to ability-id scan. Returns (remaining, formattedText) or (nil, nil).
local function getRemainingForPetLikeAbilityName(commandName)
    local bp = GetBloodPactTimerId(commandName);
    if bp then
        local r = M.GetPetCommandRecast(bp);
        return r, M.FormatRecast(r);
    end
    local tid = getPetCommandTimerIdByName(commandName);
    if not tid then
        tid = getRecastTimerIdFromAbilityResource(commandName);
    end
    if tid then
        local r = M.GetPetCommandRecast(tid);
        return r, M.FormatRecast(r);
    end
    return nil, nil;
end

-- Get pet command recast by timer ID
-- Returns: remaining seconds, or 0 if ready
function M.GetPetCommandRecast(timerId)
    if not timerId then return 0; end
    return abilityRecast.GetAbilityRecastSeconds(timerId);
end

-- Cached spell recasts. Populated lazily by GetSpellRecast — only spell IDs
-- actually queried during a frame get a memory hit. Previously this was a
-- 1025-id scan every 50ms; with another action-heavy addon loaded that
-- baseline ate frame budget that didn't need to be spent.
-- Key: spellId, Value: remaining seconds (entry absent => 0).
M.spellRecasts = {};
local spellRecastExpiry = {};      -- spellId -> os.clock() at which entry is stale
local SPELL_RECAST_TTL = 0.05;     -- 20 Hz refresh, matches old prescan cadence

-- Reusable result table for GetCooldownInfo to avoid GC pressure
-- (Creating ~7200 tables/sec with 120 slots @ 60fps causes periodic GC hitches)
local cooldownResult = {
    isOnCooldown = false,
    recastText = nil,
    remaining = 0,
    spellId = nil,
    abilityId = nil,
    itemId = nil,
};

-- Get spell recast by ID. Fetches from Ashita memory on cache miss / expiry,
-- otherwise reuses the last value. TTL matches the old prescan interval so
-- visible cooldown text refreshes at the same rate.
-- Returns: remaining seconds, or 0 if ready.
function M.GetSpellRecast(spellId)
    if not spellId then return 0; end
    local now = os.clock();
    local exp = spellRecastExpiry[spellId];
    if exp and now < exp then
        return M.spellRecasts[spellId] or 0;
    end
    local recastMgr = AshitaCore:GetMemoryManager():GetRecast();
    if not recastMgr then return M.spellRecasts[spellId] or 0; end
    local timer = recastMgr:GetSpellTimer(spellId);
    if timer and timer > 0 then
        M.spellRecasts[spellId] = timer / 60;
    else
        M.spellRecasts[spellId] = nil;
    end
    spellRecastExpiry[spellId] = now + SPELL_RECAST_TTL;
    return M.spellRecasts[spellId] or 0;
end

-- Get ability recast by ability ID
-- Uses abilityrecast.lua which scans memory slots
-- Returns: remaining seconds, or 0 if ready
function M.GetAbilityRecast(abilityId)
    if not abilityId then return 0; end
    return abilityRecast.GetAbilityRecastByAbilityId(abilityId);
end

-- Get item/equipment recast by item ID
-- Uses itemrecast.lua which reads from item.Extra data
-- Returns: remaining seconds, or 0 if ready
function M.GetItemRecast(itemId)
    if not itemId then return 0; end
    local recast, count = itemRecast.GetRecast(itemId);
    return recast or 0;
end

-- Format recast time for display
-- Returns: formatted string or nil if ready
-- @param seconds: Time in seconds
function M.FormatRecast(seconds)
    if not seconds or seconds <= 0 then
        return nil;
    end

    local days = math.floor(seconds / 86400);
    local hours = math.floor((seconds % 86400) / 3600);
    local mins = math.floor((seconds % 3600) / 60);
    local secs = math.floor(seconds % 60);

    if days >= 1 then
        -- Show as Xd Yh for times >= 24 hours (e.g. "7d 5h" or "1d")
        if hours > 0 then
            return string.format('%dd %dh', days, hours);
        else
            return string.format('%dd', days);
        end
    elseif hours >= 1 then
        if useHHMMFormat then
            -- Show as Hh:MM for times >= 1 hour (e.g. "1h:24" to distinguish from MM:SS)
            return string.format('%dh:%02d', hours, mins);
        else
            -- Show as Xh Ym for times >= 1 hour (e.g. "1h 30m")
            return string.format('%dh %dm', hours, mins);
        end
    elseif seconds >= 60 then
        -- Show as MM:SS for times >= 1 minute (e.g. "14:49")
        return string.format('%d:%02d', mins, secs);
    elseif seconds >= 10 then
        -- Show as whole seconds for 10-59s (e.g. "45")
        return string.format('%d', secs);
    else
        -- Show with decimal for < 10s (e.g. "5.2")
        return string.format('%.1f', seconds);
    end
end

-- Get recast for any action type
-- Returns: remainingSeconds, formattedText
function M.GetActionRecast(actionType, spellId, abilityId, itemId)
    local remaining = 0;

    if actionType == 'ma' and spellId then
        remaining = M.GetSpellRecast(spellId);
    elseif actionType == 'ja' and abilityId then
        remaining = M.GetAbilityRecast(abilityId);
    elseif actionType == 'pet' and abilityId then
        remaining = M.GetAbilityRecast(abilityId);
    elseif (actionType == 'item' or actionType == 'equip') and itemId then
        remaining = M.GetItemRecast(itemId);
    end
    -- Note: 'ws' (weaponskills) don't have individual recasts

    return remaining, M.FormatRecast(remaining);
end

-- ============================================
-- Macro Recast Source Sniffing
-- ============================================
--
-- Macros and palette rows can fire /ma, /pet, or /ja lines. To display a meaningful cooldown
-- timer on the slot we need to figure out WHICH action's recast applies. There are two paths:
--   1. Explicit override: actionData.recastSourceType set by the macro editor.
--   2. Implicit sniff: scan the first few lines of macroText for /ma, /pet, /ja and use that
--      as the recast source.
--
-- For palette rows whose actionType is ma / pet / ja (not the literal "macro" type), we sniff
-- in TYPE-SPECIFIC mode so a leading /ma line in a Pet Command row doesn't replace the shared
-- BP Ward/Rage timer with a spell recast, and a leading /pet line in a Spell row doesn't steal
-- Carbuncle's spell timer.

local function trimRecastStr(s)
    if not s then return nil; end
    s = tostring(s):gsub('^%s+', ''):gsub('%s+$', '');
    return (s ~= '' and s) or nil;
end

local function extractNameAfterMacroCommand(line, commandToken)
    if not line or not commandToken then return nil; end
    local quoted = line:match('^' .. commandToken .. '%s+"([^"]+)"');
    if quoted then return trimRecastStr(quoted); end
    local unquoted = line:match('^' .. commandToken .. '%s+([^<\r\n]+)');
    if unquoted then
        unquoted = unquoted:gsub('%s+<.*$', '');
        return trimRecastStr(unquoted);
    end
    return nil;
end

-- Generic macro: first /ma, /pet, or /ja per line (order within each line: ma → pet → ja).
local function sniffRecastTargetFromMacroText(macroText)
    macroText = trimRecastStr(macroText);
    if not macroText then return nil, nil; end

    local inspectedLines = 0;
    for line in macroText:gmatch('[^\r\n]+') do
        inspectedLines = inspectedLines + 1;
        if inspectedLines > 6 then break; end

        local l = trimRecastStr(line);
        if l then
            local spellName = extractNameAfterMacroCommand(l, '/ma') or extractNameAfterMacroCommand(l, '/magic');
            if spellName then
                return 'ma', spellName;
            end

            local petName = extractNameAfterMacroCommand(l, '/pet');
            if petName then
                return 'pet', petName;
            end

            local jaName = extractNameAfterMacroCommand(l, '/ja');
            if jaName then
                if petregistry.GetBloodPactByName and petregistry.GetBloodPactByName(jaName) then
                    return 'pet', jaName;
                end
                return 'ja', jaName;
            end
        end
    end
    return nil, nil;
end

-- Spell (ma) palette rows: only /ma and /magic — ignores leading /pet so summon/buff lines
-- do not steal Carbuncle's spell timer.
local function sniffRecastTargetFromMaMacroText(macroText)
    macroText = trimRecastStr(macroText);
    if not macroText then return nil, nil; end

    local inspectedLines = 0;
    for line in macroText:gmatch('[^\r\n]+') do
        inspectedLines = inspectedLines + 1;
        if inspectedLines > 8 then break; end

        local l = trimRecastStr(line);
        if l then
            local spellName = extractNameAfterMacroCommand(l, '/ma') or extractNameAfterMacroCommand(l, '/magic');
            if spellName then
                return 'ma', spellName;
            end
        end
    end
    return nil, nil;
end

-- Pet Command palette rows: only /pet and blood-pact /ja — ignores leading /ma so BP Ward/Rage
-- shared timers (173/174) are not replaced by a spell recast.
local function sniffRecastTargetFromPetMacroText(macroText)
    macroText = trimRecastStr(macroText);
    if not macroText then return nil, nil; end

    local inspectedLines = 0;
    for line in macroText:gmatch('[^\r\n]+') do
        inspectedLines = inspectedLines + 1;
        if inspectedLines > 8 then break; end

        local l = trimRecastStr(line);
        if l then
            local petName = extractNameAfterMacroCommand(l, '/pet');
            if petName then
                return 'pet', petName;
            end

            local jaName = extractNameAfterMacroCommand(l, '/ja');
            if jaName and petregistry.GetBloodPactByName and petregistry.GetBloodPactByName(jaName) then
                return 'pet', jaName;
            end
        end
    end
    return nil, nil;
end

-- Job ability (ja) rows: /ja only — blood pacts map to pet timers, else ability recast.
local function sniffRecastTargetFromJaMacroText(macroText)
    macroText = trimRecastStr(macroText);
    if not macroText then return nil, nil; end

    local inspectedLines = 0;
    for line in macroText:gmatch('[^\r\n]+') do
        inspectedLines = inspectedLines + 1;
        if inspectedLines > 8 then break; end

        local l = trimRecastStr(line);
        if l then
            local jaName = extractNameAfterMacroCommand(l, '/ja');
            if jaName then
                if petregistry.GetBloodPactByName and petregistry.GetBloodPactByName(jaName) then
                    return 'pet', jaName;
                end
                return 'ja', jaName;
            end
        end
    end
    return nil, nil;
end

local function macroHasRecastSourceOverride(actionData)
    local t = actionData.recastSourceType;
    if not t or t == '' or t == 'none' then
        return false;
    end
    return true;
end

-- Get complete cooldown info for an action
-- This is the main entry point for hotbar/crossbar cooldown display
-- @param actionData: Table with actionType and action fields (bind or slotData)
-- @return table: { isOnCooldown, recastText, remaining, spellId, abilityId, itemId }
-- NOTE: Returns a reused table - do NOT cache the return value, read values immediately
function M.GetCooldownInfo(actionData)
    if not actionData or not actionData.actionType then
        cooldownResult.isOnCooldown = false;
        cooldownResult.recastText = nil;
        cooldownResult.remaining = 0;
        cooldownResult.spellId = nil;
        cooldownResult.abilityId = nil;
        cooldownResult.itemId = nil;
        return cooldownResult;
    end

    -- Macro: optional explicit recast source (editor override)
    if actionData.actionType == 'macro' and macroHasRecastSourceOverride(actionData) then
        local recastData = {
            actionType = actionData.recastSourceType,
            action = actionData.recastSourceAction,
            itemId = actionData.recastSourceItemId,
        };
        return M.GetCooldownInfo(recastData);
    end

    -- Macro: no override — infer from /ma, /pet, /ja (including job abilities like Divine Seal)
    if actionData.actionType == 'macro' then
        local st, name = sniffRecastTargetFromMacroText(actionData.macroText);
        if st and name then
            return M.GetCooldownInfo({
                actionType = st,
                action = name,
                itemId = nil,
            });
        end
        cooldownResult.isOnCooldown = false;
        cooldownResult.recastText = nil;
        cooldownResult.remaining = 0;
        cooldownResult.spellId = nil;
        cooldownResult.abilityId = nil;
        cooldownResult.itemId = nil;
        return cooldownResult;
    end

    -- Pet Command / Magic / Job Ability palette rows (not actionType "macro"):
    -- Use type-specific sniffing so shared BP Rage/Ward timers are not replaced by a leading /ma line,
    -- and Carbuncle (ma row) is not replaced by a leading /pet line.
    local mt = actionData.macroText;
    if mt and mt ~= '' then
        if actionData.actionType == 'pet' then
            local st, name = sniffRecastTargetFromPetMacroText(mt);
            if st and name then
                return M.GetCooldownInfo({ actionType = st, action = name, itemId = nil });
            end
        elseif actionData.actionType == 'ma' then
            local st, name = sniffRecastTargetFromMaMacroText(mt);
            if st and name then
                return M.GetCooldownInfo({ actionType = st, action = name, itemId = nil });
            end
        elseif actionData.actionType == 'ja' then
            local st, name = sniffRecastTargetFromJaMacroText(mt);
            if st and name then
                return M.GetCooldownInfo({ actionType = st, action = name, itemId = nil });
            end
        end
    end

    -- Look up action IDs based on action type
    local spellId = nil;
    local abilityId = nil;
    local itemId = nil;
    local remaining = 0;
    local recastText = nil;

    if actionData.actionType == 'ma' then
        spellId = resolveSpellIndexForMa(actionData.action);
        remaining, recastText = M.GetActionRecast(actionData.actionType, spellId, nil, nil);
    elseif actionData.actionType == 'pet' then
        -- Pet commands (Blood Pacts, pet-command IDs, resource-derived timer IDs) before ability scan.
        local rPet, rtPet = getRemainingForPetLikeAbilityName(actionData.action);
        if rPet ~= nil then
            remaining = rPet;
            recastText = rtPet;
        else
            abilityId = actiondb.GetAbilityId(actionData.action);
            remaining, recastText = M.GetActionRecast(actionData.actionType, nil, abilityId, nil);
        end
    elseif actionData.actionType == 'ja' then
        -- Universal 2hr: route to the player's current job-specific 2hr ability when applicable.
        local jaActionName = universalTwoHour.ResolveJaActionName(actionData.action) or actionData.action;
        local rJa, rtJa = getRemainingForPetLikeAbilityName(jaActionName);
        if rJa ~= nil then
            remaining = rJa;
            recastText = rtJa;
        else
            abilityId = actiondb.GetAbilityId(jaActionName);
            remaining, recastText = M.GetActionRecast(actionData.actionType, nil, abilityId, nil);
        end
    elseif actionData.actionType == 'item' or actionData.actionType == 'equip' then
        -- itemId should already be stored in the action data
        itemId = actionData.itemId;
        -- Fallback: look up itemId by name if not set (for macros saved via manual text input)
        if not itemId and actionData.action then
            itemId = actiondb.GetItemId(actionData.action);
        end
        remaining, recastText = M.GetActionRecast(actionData.actionType, nil, nil, itemId);
    end

    -- Reuse result table to avoid GC pressure
    cooldownResult.isOnCooldown = remaining > 0;
    cooldownResult.recastText = recastText;
    cooldownResult.remaining = remaining;
    cooldownResult.spellId = spellId;
    cooldownResult.abilityId = abilityId;
    cooldownResult.itemId = itemId;
    return cooldownResult;
end

return M;
