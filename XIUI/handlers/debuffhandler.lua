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

-- Message type hash tables for O(1) lookup (converted from T{} arrays)
local statusOnMes = {[101]=true, [127]=true, [160]=true, [164]=true, [166]=true, [186]=true, [194]=true, [203]=true, [205]=true, [230]=true, [236]=true, [266]=true, [267]=true, [268]=true, [269]=true, [237]=true, [271]=true, [272]=true, [277]=true, [278]=true, [279]=true, [280]=true, [319]=true, [320]=true, [375]=true, [412]=true, [645]=true, [754]=true, [755]=true, [804]=true};
local statusOffMes = {[64]=true, [159]=true, [168]=true, [204]=true, [206]=true, [321]=true, [322]=true, [341]=true, [342]=true, [343]=true, [344]=true, [350]=true, [378]=true, [531]=true, [647]=true, [805]=true, [806]=true};
local deathMes = {[6]=true, [20]=true, [97]=true, [113]=true, [406]=true, [605]=true, [646]=true};
local spellDamageMes = {[2]=true, [252]=true, [264]=true, [265]=true};
-- Physical/ability hits (110 = bash/jump, 185 = WS). Not a per-ability list.
local physicalHitMes = {[103]=true, [110]=true, [185]=true, [187]=true, [238]=true, [242]=true, [317]=true, [802]=true};
local additionalEffectMes = {[160]=true, [164]=true};
-- Ability / WS miss — do not infer a debuff from the action alone.
-- 158 = JA_MISS, 324 = JA_MISS_2 (Light Shot / Feral Howl etc.)
local missMes = {[15]=true, [63]=true, [158]=true, [188]=true, [213]=true, [324]=true, [354]=true};
-- "No effect" confirms a matching uncertain debuff is already present (do not refresh timer).
-- Distinct from complete resist / immunity (655), which means the effect is not present.
-- 75 MAGIC_NO_EFFECT, 156 JA_NO_EFFECT, 189 SKILL_NO_EFFECT, 283 NO_EFFECT, 323 JA_NO_EFFECT_2
local noEffectMes = {[75]=true, [156]=true, [189]=true, [283]=true, [323]=true};
local immuneMes = {[655]=true}; -- MAGIC_COMPLETE_RESIST — target immune / cannot take the effect
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

local function CopyDurationTables(src)
    local dst = {};
    for cat, entries in pairs(src) do
        if type(entries) == 'table' then
            local copy = {};
            for id, data in pairs(entries) do
                copy[id] = data;
            end
            dst[cat] = copy;
        else
            dst[cat] = entries;
        end
    end
    return dst;
end

local function CloneDurationEntry(entry)
    local copy = {};
    for k, v in pairs(entry) do
        copy[k] = v;
    end
    return copy;
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
    local prev = targetDebuffs[buffId];
    -- Keep certainty if an active certain timer already exists (do not downgrade).
    if type(prev) == 'table' and prev.expiry and prev.expiry >= os.time() and not prev.uncertain then
        uncertain = false;
    end
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

local function GetActorTp(actorId)
    if actorId == nil then return nil; end
    local mem = AshitaCore:GetMemoryManager();
    if not mem then return nil; end
    local party = mem:GetParty();
    if not party then return nil; end
    for memIdx = 0, ALLIANCE_MEMBER_SLOTS - 1 do
        if party:GetMemberIsActive(memIdx) ~= 0 then
            if party:GetMemberServerId(memIdx) == actorId then
                return party:GetMemberTP(memIdx);
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

-- uncertain: true when land is inferred (WS hit) or TP is unknown for a TP-scaled duration.
local function ApplyWeaponSkillData(targetDebuffs, wsData, actorId, now, uncertain)
    local duration, tpKnown = ResolveWeaponSkillDuration(wsData, actorId);
    if uncertain == nil then
        uncertain = true;
    end
    -- Unknown TP only matters when duration depends on TP.
    if not tpKnown and UsesTpDuration(wsData) then
        uncertain = true;
    end
    -- Guaranteed land (e.g. Angon-like) stays certain even if TP was assumed.
    if wsData.certainOnHit then
        uncertain = false;
    end
    local entry = CloneDurationEntry(wsData);
    entry.duration = duration;
    ApplySpellData(targetDebuffs, entry, false, now, nil, uncertain);
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

local function ApplySpellData(targetDebuffs, spellData, isOwnActor, now, packetBuffId, uncertain)
    local expiry = now + ResolveDuration(spellData, isOwnActor);
    if spellData.clearsBuffs then
        for _, clearBuffId in ipairs(spellData.clearsBuffs) do
            targetDebuffs[clearBuffId] = nil;
        end
    end
    if spellData.buffIds then
        for _, buffId in ipairs(spellData.buffIds) do
            ApplyBuffExpiry(targetDebuffs, buffId, expiry, uncertain);
        end
        return;
    end
    local buffId = spellData.buffId or packetBuffId;
    ApplyBuffExpiry(targetDebuffs, buffId, expiry, uncertain);
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

            -- Set up our state
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

            -- Handle pet abilities (Type 13)
            if action.Type == 13 then
                if spellData then
                    ApplySpellData(targetDebuffs, spellData, isOwnActor, now, 2, true);
                end
            -- Type 1 melee only: Feint applies on regular melee hits (not ranged, not WS).
            elseif action.Type == 1 and physicalHitMes[message] then
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
                    local uncertain = jaPhys.certainOnHit ~= true;
                    ApplySpellData(targetDebuffs, jaPhys, isOwnActor, now, nil, uncertain);
                elseif wsData then
                    -- certainOnHit (e.g. Horizon Geirskogul) lands whenever the WS hits.
                    local uncertain = wsData.certainOnHit ~= true;
                    ApplyWeaponSkillData(targetDebuffs, wsData, actorId, now, uncertain);
                elseif spellData then
                    local uncertain = spellData.certainOnHit ~= true;
                    ApplySpellData(targetDebuffs, spellData, isOwnActor, now, nil, uncertain);
                end
            -- Handle dia/bio/helix and physical additional-effect spells (Type 4 damage)
            elseif action.Type == 4 and spellDamageMes[message] then
                if spellData then
                    local expiry = now + ResolveDuration(spellData, isOwnActor);
                    if spell == 23 or spell == 24 or spell == 25 or spell == 33 then
                        ApplyBuffExpiry(targetDebuffs, 134, expiry, false);
                        targetDebuffs[135] = nil;
                    elseif spell == 230 or spell == 231 or spell == 232 then
                        targetDebuffs[134] = nil;
                        ApplyBuffExpiry(targetDebuffs, 135, expiry, false);
                    elseif (spell >= 278 and spell <= 285) or (spell >= 885 and spell <= 892) then
                        ApplyBuffExpiry(targetDebuffs, spellData.buffId, expiry, false);
                    elseif spellData.onDamage then
                        ApplySpellData(targetDebuffs, spellData, isOwnActor, now, buffTable.GetBuffIdBySpellId(spell), true);
                    end
                end
            -- Handle regular status effect spells and magical BLU / confirmed WS status
            elseif statusOnMes[message] then
                local buffId = ability.Param or (action.Type == 4 and buffTable.GetBuffIdBySpellId(spell) or nil);
                local wsData = action.Type == 3 and WEAPON_SKILL_DURATIONS[spell] or nil;
                if wsData or (spellData and UsesTpDuration(spellData)) then
                    ApplyWeaponSkillData(targetDebuffs, wsData or spellData, actorId, now, false);
                elseif spellData then
                    ApplySpellData(targetDebuffs, spellData, isOwnActor, now, buffId, false);
                elseif buffId ~= nil then
                    ApplyBuffExpiry(targetDebuffs, buffId, now + 300, false);
                end
            -- Handle dispel effects
            elseif statusOffMes[message] then
                if ability.Param ~= nil then
                    targetDebuffs[ability.Param] = nil
                end
            -- "No effect": debuff already present — confirm uncertain, keep timer.
            -- Not used for immunity (that is complete resist / immuneMes).
            elseif noEffectMes[message] then
                for _, buffId in ipairs(ResolveActionBuffIds(action.Type, spell, ability.Param)) do
                    ConfirmUncertainDebuff(targetDebuffs, buffId, now);
                end
            -- Complete resist / immunity: effect is not on the target — clear tracker.
            elseif immuneMes[message] then
                for _, buffId in ipairs(ResolveActionBuffIds(action.Type, spell, ability.Param)) do
                    ClearTrackedDebuff(targetDebuffs, buffId);
                end
            -- Type 11: ja/jaPhysical/pet only (spell ids collide with WS/BLU).
            elseif action.Type == 11 and not missMes[message] then
                local nonSpell = LookupNonSpell(spell, action.Type);
                if nonSpell then
                    local uncertain = nonSpell.uncertain == true;
                    ApplySpellData(targetDebuffs, nonSpell, isOwnActor, now, ability.Param, uncertain);
                end
            -- Type 6 / 14: job abilities (512-normalized in GetDurationData).
            elseif (action.Type == 6 or action.Type == 14) and not missMes[message] then
                local jaId = JobAbilityId(spell);
                local onHitData = ON_HIT_DURATIONS[jaId];
                if onHitData then
                    debuffHandler.pendingOnHit[actorId] = {
                        buffId = onHitData.buffId,
                        duration = onHitData.duration,
                        expires = now + (onHitData.window or 60),
                    };
                elseif spellData then
                    -- uncertain flag, or certainOnHit for guaranteed lands (Angon).
                    local uncertain = spellData.uncertain == true;
                    if spellData.certainOnHit == true then
                        uncertain = false;
                    end
                    ApplySpellData(targetDebuffs, spellData, isOwnActor, now, ability.Param, uncertain);
                end
            end

            -- Additional-effect procs. Do not replace a known timer with the 30s guess.
            if additionalEffect ~= nil and additionalEffectMes[additionalEffect] then
                local buffId = ability.AdditionalEffect.Param;
                if buffId ~= nil then
                    local aeData = ADDITIONAL_EFFECT_DURATIONS[buffId];
                    if aeData then
                        ApplyBuffExpiry(targetDebuffs, buffId, now + aeData.duration, false);
                    else
                        local prev = targetDebuffs[buffId];
                        local prevExpiry = type(prev) == 'table' and prev.expiry or prev;
                        if prevExpiry == nil or prevExpiry < now then
                            ApplyBuffExpiry(targetDebuffs, buffId, now + 30, true);
                        end
                    end
                end
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
                debuffs[basic.target][2] = nil
                debuffs[basic.target][193] = nil
                debuffs[basic.target][19] = nil
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

    -- Clear and reuse tables instead of allocating new ones every frame
    -- This significantly reduces garbage collection pressure
    local count = 0;
    for i = 1, #reusableDebuffIds do
        reusableDebuffIds[i] = nil;
        reusableDebuffTimes[i] = nil;
    end
    for k in pairs(reusableDebuffUncertain) do
        reusableDebuffUncertain[k] = nil;
    end

    -- Cache os.time() once instead of calling it repeatedly in the loop
    local currentTime = os.time();

    for buffId, entry in pairs(debuffHandler.enemies[serverId]) do
        local expiryTime = type(entry) == 'table' and entry.expiry or entry;
        if (expiryTime ~= 0 and expiryTime ~= nil and expiryTime > currentTime) then
            count = count + 1;
            reusableDebuffIds[count] = buffId;
            reusableDebuffTimes[count] = expiryTime - currentTime;
            if type(entry) == 'table' and entry.uncertain then
                reusableDebuffUncertain[buffId] = true;
            end
        end
    end

    -- Return nil if no active debuffs (same behavior as before)
    if count == 0 then
        return nil;
    end

    return reusableDebuffIds, reusableDebuffTimes, reusableDebuffUncertain;
end

return debuffHandler;
