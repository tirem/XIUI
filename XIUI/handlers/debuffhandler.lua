-- GNU Licensed by mousseng's XITools repository [https://github.com/mousseng/xitools]
require('common');
require('handlers.helpers');
local buffTable = require('libs.bufftable');

local debuffHandler =
T{
    -- All enemies we have seen take a debuff
    enemies = T{};
    -- Feint and similar: debuff lands on next melee/ranged hit from this actor
    pendingOnHit = T{};
};

-- Reusable tables for GetActiveDebuffs to avoid per-frame allocations
-- These are cleared and reused each call instead of creating new tables
local reusableDebuffIds = {};
local reusableDebuffTimes = {};
local reusableDebuffUncertain = {};

-- Status-on = the server said the effect is on the target (no ?).
-- 101 USES is only "entity uses", not a land — keep it out.
local statusOnMes = {[127]=true, [160]=true, [164]=true, [166]=true, [186]=true, [194]=true, [203]=true, [205]=true, [230]=true, [236]=true, [266]=true, [267]=true, [268]=true, [269]=true, [237]=true, [271]=true, [272]=true, [277]=true, [278]=true, [279]=true, [280]=true, [319]=true, [320]=true, [375]=true, [412]=true, [645]=true, [754]=true, [755]=true, [804]=true};
local statusOffMes = {[64]=true, [159]=true, [168]=true, [204]=true, [206]=true, [321]=true, [322]=true, [341]=true, [342]=true, [343]=true, [344]=true, [350]=true, [378]=true, [531]=true, [647]=true, [805]=true, [806]=true};
local deathMes = {[6]=true, [20]=true, [97]=true, [113]=true, [406]=true, [605]=true, [646]=true};
local spellDamageMes = {[2]=true, [252]=true, [264]=true, [265]=true};
-- Physical/ability hits (110 = bash/jump, 185 = WS). Not a per-ability list.
local physicalHitMes = {[103]=true, [110]=true, [185]=true, [187]=true, [238]=true, [242]=true, [317]=true, [802]=true};
local additionalEffectMes = {[160]=true, [164]=true};
-- Ability / WS miss — do not infer a debuff from the action alone.
-- 158 = JA_MISS, 324 = JA_MISS_2 (Light Shot / Feral Howl etc.)
local missMes = {[15]=true, [63]=true, [158]=true, [188]=true, [213]=true, [324]=true, [354]=true};
-- Hits that deal HP damage (wakes Sleep). Healing messages are omitted.
local damageHitMes = {
    [1]=true, [2]=true, [67]=true, [110]=true, [163]=true, [185]=true,
    [187]=true, [229]=true, [252]=true, [264]=true, [265]=true, [317]=true,
    [352]=true, [353]=true, [379]=true, [576]=true, [577]=true, [802]=true,
};
local SLEEP_BUFF_IDS = { 2, 19, 193 };
-- "No effect" confirms a matching uncertain debuff is already present (do not refresh timer).
-- Distinct from complete resist / immunity (655), which means the effect is not present.
-- 75 MAGIC_NO_EFFECT, 156 JA_NO_EFFECT, 189 SKILL_NO_EFFECT, 283 NO_EFFECT, 323 JA_NO_EFFECT_2
local noEffectMes = {[75]=true, [156]=true, [189]=true, [283]=true, [323]=true};
local immuneMes = {[655]=true}; -- MagicCompleteResist — target immune / cannot take the effect
local MAX_TP = 3000;
local ALLIANCE_MEMBER_SLOTS = 18;

local BUFF_SABOTEUR = 454;
local BUFF_STYMIE = 494;
local BUFF_DARK_ARTS = 359;
local JOB_BLM = 4;
local JOB_RDM = 5;
local JOB_BRD = 10;
local JOB_SCH = 20;
-- Client merit IDs from 0x08C (DSP/LSB group-2 offsets). Packet stores upgrade count.
local MERIT_ENFEEBLING_MAGIC_DURATION = 0x090C;
local MERIT_ELEMENTAL_DEBUFF_DURATION = 0x08D2;
-- tHotBar 0x08D category index is 0-based (menu order; 0x2/0x1 swapped in LSB).
local JP_RDM_STYMIE_EFFECT = 2;
local JP_RDM_ENFEEBLE_DURATION = 7;
local JP_BRD_LULLABY_DURATION = 7;
local JP_SCH_DARK_ARTS_EFFECT = 3;
local BRD_SONG_DURATION_GIFT_JP = 1200;
local BRD_SONG_DURATION_GIFT_PCT = 5;

local meritCounts = {};
local jobPointCategories = {};

local function CloneDurationEntry(entry)
    local copy = {};
    for k, v in pairs(entry) do
        copy[k] = v;
    end
    return copy;
end

local function CopyDurationTables(src)
    local dst = {};
    for cat, entries in pairs(src) do
        if type(entries) == 'table' then
            local copy = {};
            for id, data in pairs(entries) do
                copy[id] = type(data) == 'table' and CloneDurationEntry(data) or data;
            end
            dst[cat] = copy;
        else
            dst[cat] = entries;
        end
    end
    return dst;
end

local function ApplyHorizonOverlay(base, overlay)
    for cat, entries in pairs(overlay) do
        if type(entries) == 'table' then
            if base[cat] == nil then
                base[cat] = {};
            end
            for id, patch in pairs(entries) do
                if patch == false then
                    base[cat][id] = nil;
                elseif type(patch) == 'table' and type(base[cat][id]) == 'table' then
                    local merged = CloneDurationEntry(base[cat][id]);
                    for k, v in pairs(patch) do
                        -- false clears a retail field (e.g. fixed duration -> TP formula).
                        if v == false then
                            merged[k] = nil;
                        else
                            merged[k] = v;
                        end
                    end
                    base[cat][id] = merged;
                else
                    base[cat][id] = patch;
                end
            end
        end
    end
    return base;
end

local durations = CopyDurationTables(require('handlers.database.debuff_retail'));
if HzLimitedMode then
    durations = ApplyHorizonOverlay(durations, require('handlers.database.debuff_horizon'));
end

local SPELL_DURATIONS = durations.spells;
local WEAPON_SKILL_DURATIONS = durations.weaponSkills or {};
local JA_PHYSICAL_DURATIONS = durations.jaPhysical;
local JA_DURATIONS = durations.ja;
local PET_DURATIONS = durations.pet;
local ADDITIONAL_EFFECT_DURATIONS = durations.additionalEffect;
local ON_HIT_DURATIONS = durations.onHit or {};

-- Longest known duration per buff (spells/JA/WS/pets). Unknown status-on uses this, not bolt AE times.
local STATUS_MAX_DURATIONS = {};
local function RecordMaxDuration(data)
    if type(data) ~= 'table' or type(data.duration) ~= 'number' then return; end
    local function consider(buffId)
        if buffId ~= nil and (STATUS_MAX_DURATIONS[buffId] == nil or data.duration > STATUS_MAX_DURATIONS[buffId]) then
            STATUS_MAX_DURATIONS[buffId] = data.duration;
        end
    end
    consider(data.buffId);
    if data.buffIds then
        for i = 1, #data.buffIds do
            consider(data.buffIds[i]);
        end
    end
end
local function RecordTableMax(tbl)
    if not tbl then return; end
    for _, data in pairs(tbl) do
        RecordMaxDuration(data);
    end
end
RecordTableMax(SPELL_DURATIONS);
RecordTableMax(WEAPON_SKILL_DURATIONS);
RecordTableMax(JA_PHYSICAL_DURATIONS);
RecordTableMax(JA_DURATIONS);
RecordTableMax(PET_DURATIONS);

local function UnknownStatusDuration(buffId)
    local maxDur = STATUS_MAX_DURATIONS[buffId];
    if maxDur then return maxDur; end
    local aeData = ADDITIONAL_EFFECT_DURATIONS[buffId];
    return aeData and aeData.duration or 30;
end

local function ClampSongPlus(value)
    value = tonumber(value) or 0;
    if value < 0 then return 0; end
    if value > 9 then return 9; end
    return math.floor(value);
end

local function PlayerHasBuff(buffId)
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player or not player.GetBuffs then return false; end
    local buffs = player:GetBuffs();
    if not buffs then return false; end
    for i = 0, 63 do
        if buffs[i] == buffId then
            return true;
        end
    end
    return false;
end

local function GetMainJob()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then return 0; end
    return player:GetMainJob() or 0;
end

local function GetMeritCount(meritId)
    return meritCounts[meritId] or 0;
end

local function GetJobPointCount(job, categoryIndex)
    local jobTable = jobPointCategories[job];
    if not jobTable then return 0; end
    return jobTable[categoryIndex + 1] or 0;
end

local function GetJobPointsSpent(job)
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player or not player.GetJobPointsSpent then return 0; end
    return player:GetJobPointsSpent(job) or 0;
end

local function GetLocalPetServerId()
    local mem = AshitaCore:GetMemoryManager();
    if not mem then return nil; end
    local party = mem:GetParty();
    local entity = mem:GetEntity();
    if not party or not entity then return nil; end
    local playerIndex = party:GetMemberTargetIndex(0);
    if not playerIndex or playerIndex == 0 then return nil; end
    local petIndex = entity:GetPetTargetIndex(playerIndex);
    if not petIndex or petIndex == 0 then return nil; end
    return entity:GetServerId(petIndex);
end

local function IsOwnActor(actorId)
    if actorId == nil then return false; end
    local mem = AshitaCore:GetMemoryManager();
    if not mem then return false; end
    local party = mem:GetParty();
    if party and party:GetMemberServerId(0) == actorId then
        return true;
    end
    return GetLocalPetServerId() == actorId;
end

local function IsAllianceActor(actorId)
    if actorId == nil then return false; end
    if IsOwnActor(actorId) then return true; end
    local mem = AshitaCore:GetMemoryManager();
    local party = mem and mem:GetParty();
    if not party then return false; end
    for memIdx = 0, ALLIANCE_MEMBER_SLOTS - 1 do
        if party:GetMemberIsActive(memIdx) ~= 0 and party:GetMemberServerId(memIdx) == actorId then
            return true;
        end
    end
    return false;
end

local function ResolveDuration(spellData, isOwnActor)
    local duration = spellData.duration or 0;
    if not isOwnActor then
        return duration;
    end

    if spellData.songFamily then
        local plus = 0;
        if gConfig then
            plus = ClampSongPlus(gConfig[spellData.songFamily]);
        end
        -- Virelai skips song-duration gifts (LSB calculateSongDuration).
        local giftPct = 0;
        if spellData.songFamily ~= 'songPlusVirelai' and GetMainJob() == JOB_BRD and GetJobPointsSpent(JOB_BRD) >= BRD_SONG_DURATION_GIFT_JP then
            giftPct = BRD_SONG_DURATION_GIFT_PCT;
        end
        duration = math.floor(duration * (1 + plus / 10 + giftPct / 100));
        if spellData.songFamily == 'songPlusLullaby' and GetMainJob() == JOB_BRD then
            duration = duration + GetJobPointCount(JOB_BRD, JP_BRD_LULLABY_DURATION);
        end
        return duration;
    end

    if spellData.kind == 'enfeeble' then
        if PlayerHasBuff(BUFF_SABOTEUR) then
            duration = math.floor(duration * 2);
        end
        if GetMainJob() == JOB_RDM then
            duration = duration + (GetMeritCount(MERIT_ENFEEBLING_MAGIC_DURATION) * 6);
            duration = duration + GetJobPointCount(JOB_RDM, JP_RDM_ENFEEBLE_DURATION);
            if PlayerHasBuff(BUFF_STYMIE) then
                duration = duration + GetJobPointCount(JOB_RDM, JP_RDM_STYMIE_EFFECT);
            end
        end
        return duration;
    end

    if spellData.kind == 'elemental' then
        if GetMainJob() == JOB_BLM then
            duration = duration + (GetMeritCount(MERIT_ELEMENTAL_DEBUFF_DURATION) * 12);
        end
        return duration;
    end

    if spellData.kind == 'helix' then
        if PlayerHasBuff(BUFF_DARK_ARTS) then
            duration = duration + (3 * GetJobPointCount(JOB_SCH, JP_SCH_DARK_ARTS_EFFECT));
        end
        return duration;
    end

    return duration;
end

local function ApplyBuffExpiry(targetDebuffs, buffId, expiry, uncertain)
    if buffId == nil then return; end
    targetDebuffs[buffId] = { expiry = expiry, uncertain = uncertain == true };
end

-- Status already present ("no effect"): upgrade uncertain -> certain without refreshing timer.
local function ConfirmUncertainDebuff(targetDebuffs, buffId, now)
    if buffId == nil or buffId == 0 then return; end
    local prev = targetDebuffs[buffId];
    if type(prev) == 'table' and prev.uncertain and prev.expiry and prev.expiry >= now then
        prev.uncertain = false;
    end
end

-- Immunity / complete resist: effect cannot be on the target — clear tracked entry.
local function ClearTrackedDebuff(targetDebuffs, buffId)
    if buffId == nil or buffId == 0 then return; end
    targetDebuffs[buffId] = nil;
end

local function ClearSleepDebuffs(targetDebuffs)
    for i = 1, #SLEEP_BUFF_IDS do
        targetDebuffs[SLEEP_BUFF_IDS[i]] = nil;
    end
end

local function SpellHasBuff(spellData, buffId)
    if spellData == nil or buffId == nil then return false; end
    if spellData.buffIds then
        for i = 1, #spellData.buffIds do
            if spellData.buffIds[i] == buffId then return true; end
        end
        return false;
    end
    return spellData.buffId == buffId;
end

-- Low 16 bits are the action id. 512-1023 is Ashita's JA resource range.
-- Type 11 must not subtract 512: 688-695 are 2-hour mob skills.
local function PacketParamId(id)
    return bit.band(id or 0, 0xFFFF);
end

local function JobAbilityId(id)
    id = PacketParamId(id);
    if id >= 512 and id < 1024 then
        return id - 512;
    end
    return id;
end

local function ResolveActionBuffIds(actionType, spellId, abilityParam)
    local ids = {};
    if abilityParam ~= nil and abilityParam ~= 0 then
        ids[#ids + 1] = abilityParam;
        return ids;
    end
    if actionType == 4 then
        local buffId = buffTable.GetBuffIdBySpellId(spellId);
        if buffId ~= nil and buffId ~= 0 then
            ids[#ids + 1] = buffId;
        end
        return ids;
    end
    spellId = PacketParamId(spellId);
    local jaId = JobAbilityId(spellId);
    local data = nil;
    if actionType == 3 then
        data = WEAPON_SKILL_DURATIONS[spellId] or JA_PHYSICAL_DURATIONS[jaId];
    elseif actionType == 6 or actionType == 14 then
        data = JA_DURATIONS[jaId] or JA_DURATIONS[spellId];
    elseif actionType == 13 then
        data = PET_DURATIONS[spellId] or PET_DURATIONS[jaId];
    else
        data = JA_DURATIONS[spellId] or JA_PHYSICAL_DURATIONS[spellId] or PET_DURATIONS[spellId]
            or JA_DURATIONS[jaId] or JA_PHYSICAL_DURATIONS[jaId] or PET_DURATIONS[jaId]
            or WEAPON_SKILL_DURATIONS[spellId];
    end
    if data then
        if data.buffIds then
            for _, id in ipairs(data.buffIds) do
                ids[#ids + 1] = id;
            end
        elseif data.buffId then
            ids[#ids + 1] = data.buffId;
        end
    end
    return ids;
end

-- 0x028 is sent after SpendCost; party TP is 0 or a stale 0x0DD value.
-- Treat <100 as unknown so tpPer500 stuns are not applied as 0s.
local function GetActorTp(actorId)
    if actorId == nil then return nil; end
    local mem = AshitaCore:GetMemoryManager();
    if not mem then return nil; end
    local party = mem:GetParty();
    if not party then return nil; end
    for memIdx = 0, ALLIANCE_MEMBER_SLOTS - 1 do
        if party:GetMemberIsActive(memIdx) ~= 0 then
            if party:GetMemberServerId(memIdx) == actorId then
                local tp = party:GetMemberTP(memIdx);
                if tp ~= nil and tp >= 100 then
                    return tp;
                end
                return nil;
            end
        end
    end
    return nil;
end

local function ResolveTpTierDuration(tpTier, tp)
    for i = #tpTier, 1, -1 do
        if tp >= tpTier[i][1] then
            return tpTier[i][2];
        end
    end
    if tpTier[1][1] > 0 then
        return math.floor(tpTier[1][2] * tp / tpTier[1][1]);
    end
    return tpTier[1][2];
end

local function ResolveTpDuration(wsData, tp)
    if wsData.duration then
        return wsData.duration;
    end
    if wsData.tpTier then
        return ResolveTpTierDuration(wsData.tpTier, tp);
    end
    if wsData.tpFTP then
        local anchors = wsData.tpFTP;
        if tp >= 3000 then
            return anchors[3];
        elseif tp >= 2000 then
            return math.floor(anchors[2] + (anchors[3] - anchors[2]) * (tp - 2000) / 1000);
        elseif tp >= 1000 then
            return math.floor(anchors[1] + (anchors[2] - anchors[1]) * (tp - 1000) / 1000);
        end
        return math.floor(anchors[1] * tp / 1000);
    end
    if wsData.tpPer500 then
        return math.floor(tp / 500);
    end
    local formula = wsData.tpDuration or wsData;
    local duration = formula.base or 0;
    if formula.per100Tp then
        duration = duration + formula.per100Tp * tp / 100;
    end
    if formula.per1000Tp then
        duration = duration + formula.per1000Tp * tp / 1000;
    end
    if formula.per200Tp then
        duration = duration + formula.per200Tp * tp / 200;
    end
    return math.floor(duration);
end

local function ResolveWeaponSkillDuration(wsData, actorId)
    local tp = GetActorTp(actorId);
    local tpKnown = tp ~= nil;
    if not tpKnown then
        tp = MAX_TP;
    end
    return ResolveTpDuration(wsData, tp), tpKnown;
end

local function UsesTpDuration(data)
    return data.tpTier ~= nil or data.tpDuration ~= nil or data.tpFTP ~= nil or data.tpPer500 ~= nil;
end

-- Non-spell Param lookup. Order matters for id collisions (e.g. Invincible vs Energy Drain).
local function LookupNonSpell(id, actionType)
    if actionType == 3 then
        return WEAPON_SKILL_DURATIONS[id] or JA_PHYSICAL_DURATIONS[id];
    end
    if actionType == 6 or actionType == 14 then
        return JA_DURATIONS[id] or JA_PHYSICAL_DURATIONS[id];
    end
    return JA_DURATIONS[id] or JA_PHYSICAL_DURATIONS[id] or PET_DURATIONS[id];
end

-- Type 4 is spells-only so BLU ids do not collide with 2-hours or weapon skills.
local function GetDurationData(actionType, id)
    id = PacketParamId(id);
    local jaId = JobAbilityId(id);
    if actionType == 4 then
        return SPELL_DURATIONS[id];
    end
    if actionType == 3 then
        return WEAPON_SKILL_DURATIONS[id] or JA_PHYSICAL_DURATIONS[jaId];
    end
    if actionType == 6 or actionType == 14 then
        -- Physical JAs (Angon/Shield Bash) may arrive as type 6; keep out of WS id collisions.
        return JA_DURATIONS[jaId] or JA_DURATIONS[id]
            or JA_PHYSICAL_DURATIONS[jaId] or JA_PHYSICAL_DURATIONS[id];
    end
    if actionType == 13 then
        return PET_DURATIONS[id] or PET_DURATIONS[jaId];
    end
    if actionType == 11 then
        return LookupNonSpell(id, actionType) or SPELL_DURATIONS[id];
    end
    return SPELL_DURATIONS[id] or LookupNonSpell(id, actionType) or LookupNonSpell(jaId, actionType);
end

-- Hidden second roll after a connecting hit (BLU onDamage / bash / resistable WS).
-- Returns the ? flag, or nil to skip (visible AE or wait for status-on).
local function HiddenSecondaryMarker(data, additionalEffect, defaultHidden)
    if not data then return nil; end
    if data.certainOnHit then return false; end
    if additionalEffect ~= nil then return nil; end
    if defaultHidden or data.uncertain or data.onDamage then return true; end
    return nil;
end

-- uncertain is only "inferred from a hit". Confirmed lands pass false.
local function ApplySpellData(targetDebuffs, spellData, isOwnActor, now, packetBuffId, uncertain)
    local expiry = now + ResolveDuration(spellData, isOwnActor);
    if spellData.clearsBuffs then
        for _, clearBuffId in ipairs(spellData.clearsBuffs) do
            targetDebuffs[clearBuffId] = nil;
        end
    end
    -- onDamage AEs land one buff per message. Magical multi-enfeeble (Enervation) lands together.
    if spellData.buffIds and not spellData.onDamage then
        for _, buffId in ipairs(spellData.buffIds) do
            ApplyBuffExpiry(targetDebuffs, buffId, expiry, uncertain);
        end
        return;
    end
    local buffId = packetBuffId;
    if buffId == nil or buffId == 0 then
        buffId = spellData.buffId;
    end
    ApplyBuffExpiry(targetDebuffs, buffId, expiry, uncertain);
end

-- uncertain: true when the WS secondary is inferred (no land message).
local function ApplyWeaponSkillData(targetDebuffs, wsData, actorId, now, uncertain)
    local duration = ResolveWeaponSkillDuration(wsData, actorId);
    if wsData.certainOnHit then
        uncertain = false;
    elseif uncertain == nil then
        uncertain = true;
    end
    local entry = CloneDurationEntry(wsData);
    entry.duration = duration;
    ApplySpellData(targetDebuffs, entry, false, now, nil, uncertain);
end

-- applyOnDamage: certain land on the damage message. onDamage: infer when the packet has no AE block.
local function ApplyType4Damage(targetDebuffs, spellData, isOwnActor, now, damage, additionalEffect)
    if not spellData then return; end
    if spellData.onDamage then
        if (damage or 0) > 0 and additionalEffect == nil then
            ApplySpellData(targetDebuffs, spellData, isOwnActor, now, nil, true);
        end
        return;
    end
    if spellData.applyOnDamage then
        ApplySpellData(targetDebuffs, spellData, isOwnActor, now, nil, false);
    end
end

local function ApplyPacketAdditionalEffect(targetDebuffs, spellData, isOwnActor, now, buffId)
    if buffId == nil then return; end
    if SpellHasBuff(spellData, buffId) then
        local landed = CloneDurationEntry(spellData);
        landed.buffIds = nil;
        landed.buffId = buffId;
        ApplySpellData(targetDebuffs, landed, isOwnActor, now, buffId, false);
        return;
    end
    local prev = targetDebuffs[buffId];
    local prevExpiry = prev and prev.expiry;
    local prevCertain = prev and prevExpiry and prevExpiry >= now and not prev.uncertain;
    local aeData = ADDITIONAL_EFFECT_DURATIONS[buffId];
    local newExpiry = now + (aeData and aeData.duration or 30);
    if prevCertain and prevExpiry >= newExpiry then return; end
    local expiry = newExpiry;
    if prevExpiry and prevExpiry > expiry then expiry = prevExpiry; end
    ApplyBuffExpiry(targetDebuffs, buffId, expiry, false);
end

local function ApplyMessage(debuffs, action)

    if (action == nil) then
        return;
    end

    local now = os.time()
    local actorId = action.UserId;
    -- Constant for the whole packet; resolve once instead of per target.
    local isOwnActor = IsOwnActor(actorId);

    for _, target in pairs(action.Targets) do
        for _, ability in pairs(target.Actions) do

            local spell = PacketParamId(action.Param);
            local message = ability.Message
            local additionalEffect

            if (ability.AdditionalEffect ~= nil and ability.AdditionalEffect.Message ~= nil) then
                additionalEffect = ability.AdditionalEffect.Message
            end

            if (debuffs[target.Id] == nil) then
                debuffs[target.Id] = T{};
            end

            local targetDebuffs = debuffs[target.Id];
            local spellData = GetDurationData(action.Type, spell);

            -- Damage wakes Sleep; this action may re-apply it afterward.
            if damageHitMes[message] then
                ClearSleepDebuffs(targetDebuffs);
            end

            -- Type 1 melee only: Feint applies on regular melee hits (not ranged, not WS).
            if action.Type == 1 and physicalHitMes[message] then
                local pending = debuffHandler.pendingOnHit[actorId];
                if pending and pending.expires > now then
                    -- Guaranteed on connecting melee hit (including 0 dmg / countered).
                    ApplyBuffExpiry(targetDebuffs, pending.buffId, now + pending.duration, false);
                    debuffHandler.pendingOnHit[actorId] = nil;
                end
            -- Type 3 WS or physical JA on a hit
            elseif action.Type == 3 and physicalHitMes[message] then
                local jaId = JobAbilityId(spell);
                -- Ashita JA params are often 512+id; prefer jaPhysical to avoid WS id collisions
                -- (e.g. Angon 170 vs Randgrith 170, Shield Bash 46 vs Expiacion 46).
                local jaPhys = (spell ~= jaId) and JA_PHYSICAL_DURATIONS[jaId] or nil;
                local wsData = (not jaPhys) and WEAPON_SKILL_DURATIONS[spell] or nil;
                if jaPhys then
                    local marker = HiddenSecondaryMarker(jaPhys, additionalEffect, false);
                    if marker ~= nil then
                        ApplySpellData(targetDebuffs, jaPhys, isOwnActor, now, nil, marker);
                    end
                elseif wsData then
                    local marker = HiddenSecondaryMarker(wsData, additionalEffect, true);
                    if marker ~= nil then
                        ApplyWeaponSkillData(targetDebuffs, wsData, actorId, now, marker);
                    end
                elseif spellData then
                    local marker = HiddenSecondaryMarker(spellData, additionalEffect, false);
                    if marker ~= nil then
                        ApplySpellData(targetDebuffs, spellData, isOwnActor, now, nil, marker);
                    end
                end
            -- Type 13 pet/blood pact damage: hidden secondary (e.g. Poison Nails)
            -- lands silently (messageBypass) with resist-scaled duration. Confirmed
            -- lands (Nightmare msg 266) fall through to the status-on branch below.
            elseif action.Type == 13 and physicalHitMes[message] then
                local marker = HiddenSecondaryMarker(spellData, additionalEffect, true);
                if marker ~= nil then
                    ApplySpellData(targetDebuffs, spellData, isOwnActor, now, nil, marker);
                end
            elseif action.Type == 4 and spellDamageMes[message] then
                ApplyType4Damage(targetDebuffs, spellData, isOwnActor, now, ability.Param, additionalEffect);
            elseif statusOnMes[message] then
                local buffId = ability.Param or (action.Type == 4 and buffTable.GetBuffIdBySpellId(spell) or nil);
                local wsData = action.Type == 3 and WEAPON_SKILL_DURATIONS[spell] or nil;
                if wsData or (spellData and UsesTpDuration(spellData)) then
                    ApplyWeaponSkillData(targetDebuffs, wsData or spellData, actorId, now, false);
                elseif spellData then
                    ApplySpellData(targetDebuffs, spellData, isOwnActor, now, buffId, false);
                elseif buffId ~= nil then
                    ApplyBuffExpiry(targetDebuffs, buffId, now + UnknownStatusDuration(buffId), false);
                end
            elseif statusOffMes[message] then
                if ability.Param ~= nil then
                    targetDebuffs[ability.Param] = nil
                end
            -- Confirm ? without refreshing. Only alliance actors.
            elseif noEffectMes[message] then
                if IsAllianceActor(actorId) then
                    for _, buffId in ipairs(ResolveActionBuffIds(action.Type, spell, ability.Param)) do
                        ConfirmUncertainDebuff(targetDebuffs, buffId, now);
                    end
                end
            elseif immuneMes[message] then
                for _, buffId in ipairs(ResolveActionBuffIds(action.Type, spell, ability.Param)) do
                    ClearTrackedDebuff(targetDebuffs, buffId);
                end
            -- Type 6 / 14: Feint pending, or bash-style physical JA inferred from a hit.
            -- Do not apply ja[] on "uses" — lands are status-on (e.g. Light Shot 127).
            elseif (action.Type == 6 or action.Type == 14) and not missMes[message] then
                local jaId = JobAbilityId(spell);
                local onHitData = ON_HIT_DURATIONS[jaId];
                if onHitData then
                    debuffHandler.pendingOnHit[actorId] = {
                        buffId = onHitData.buffId,
                        duration = onHitData.duration,
                        expires = now + (onHitData.window or 60),
                    };
                elseif physicalHitMes[message] then
                    local jaPhys = JA_PHYSICAL_DURATIONS[jaId] or JA_PHYSICAL_DURATIONS[spell];
                    local marker = HiddenSecondaryMarker(jaPhys, additionalEffect, false);
                    if marker ~= nil then
                        ApplySpellData(targetDebuffs, jaPhys, isOwnActor, now, nil, marker);
                    end
                end
            end

            if additionalEffect ~= nil and additionalEffectMes[additionalEffect] then
                ApplyPacketAdditionalEffect(targetDebuffs, spellData, isOwnActor, now, ability.AdditionalEffect.Param);
            end
        end
    end
end

local function ClearMessage(debuffs, basic)
    -- if we're tracking a mob that dies, reset its status
    if deathMes[basic.message] and debuffs[basic.target] then
        debuffs[basic.target] = nil
    elseif (basic.message == 321) then --Custom Chi Blast dispel message
        if (debuffs[basic.target] == nil or basic.value == nil) then
            return
        end

        debuffs[basic.target][basic.value] = nil
    elseif statusOffMes[basic.message] then
        if debuffs[basic.target] == nil then
            return
        end

        -- Clear the buffid that just wore off
        if (basic.param ~= nil) then
            if (basic.param == 2) then --Sleep/Lullaby Handling
                ClearSleepDebuffs(debuffs[basic.target]);
            else
                debuffs[basic.target][basic.param] = nil
            end
        end
    end
end

debuffHandler.HandleIncomingPacket = function(e)
    if (e.id == 0x08C) then
        local meritNum = struct.unpack('B', e.data, 0x04 + 1);
        for i = 1, meritNum, 1 do
            local meritId = struct.unpack('H', e.data, 0x04 + (4 * i) + 1);
            local meritCount = struct.unpack('B', e.data, 0x04 + (4 * i) + 0x03 + 1);
            meritCounts[meritId] = meritCount;
        end
    elseif (e.id == 0x08D) then
        local jobPointCount = (e.size / 4) - 1;
        for i = 1, jobPointCount, 1 do
            local offset = i * 4;
            local index = ashita.bits.unpack_be(e.data_raw, offset, 0, 5);
            local job = ashita.bits.unpack_be(e.data_raw, offset, 5, 11);
            local count = ashita.bits.unpack_be(e.data_raw, offset + 3, 2, 6);
            if job ~= 0 then
                if jobPointCategories[job] == nil then
                    jobPointCategories[job] = {};
                end
                jobPointCategories[job][index + 1] = count;
            end
        end
    end
end

debuffHandler.HandleActionPacket = function(e)
    ApplyMessage(debuffHandler.enemies, e);
end

debuffHandler.HandleZonePacket = function(e)
    debuffHandler.enemies = {};
    debuffHandler.pendingOnHit = T{};
end

debuffHandler.HandleMessagePacket = function(e)
    ClearMessage(debuffHandler.enemies, e)
end

debuffHandler.GetActiveDebuffs = function(serverId)
    if (debuffHandler.enemies[serverId] == nil) then
        return nil
    end

    local count = 0;
    for i = 1, #reusableDebuffIds do
        reusableDebuffIds[i] = nil;
        reusableDebuffTimes[i] = nil;
    end
    for k in pairs(reusableDebuffUncertain) do
        reusableDebuffUncertain[k] = nil;
    end

    local currentTime = os.time();
    for buffId, entry in pairs(debuffHandler.enemies[serverId]) do
        local expiryTime = entry and entry.expiry;
        if expiryTime ~= nil and expiryTime > currentTime then
            count = count + 1;
            reusableDebuffIds[count] = buffId;
            reusableDebuffTimes[count] = expiryTime - currentTime;
            if entry.uncertain then
                reusableDebuffUncertain[buffId] = true;
            end
        end
    end

    if count == 0 then
        return nil;
    end

    return reusableDebuffIds, reusableDebuffTimes, reusableDebuffUncertain;
end

return debuffHandler;
