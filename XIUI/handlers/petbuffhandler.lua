-- XIUI Pet Buff Handler
-- Tracks status effects on the player's pet. Buffs show timer, debuffs show icon only.

require('common');
require('handlers.helpers');
local buffTable = require('libs.bufftable');

local petBuffHandler = {};
local petEffects = {};
local currentPetServerId = nil;
local activeEffectIds = {};
local activeEffectTimes = {};

-- Pet ability buffs: [abilityId] = { effectId, duration, playerCast (optional) }
local PET_ABILITY_BUFFS = {
    [688] = { effectId = 92, duration = 180 },  -- Lizard Secretion (Evasion Boost)
    [690] = { effectId = 56, duration = 120 },  -- Sheep/Ram Rage (Berserk)
    [694] = { effectId = 41, duration = 180 },  -- Crab Bubble Curtain (Shell)
    [696] = { effectId = 93, duration = 60 },   -- Crab Scissor Guard (Defense Boost)
    [710] = { effectId = 92, duration = 180 },  -- Beetle Rhino Guard (Evasion Boost)
    [295] = { effectId = 37, duration = 300, playerCast = true },  -- DRG Steady Wing
    [78]  = { effectId = 42, duration = 180, playerCast = true },  -- BST Reward (Regen)
};

-- Message IDs for "target gains/receives/is <status>" (LSB msg_basic.h + msg_std.h). Param = effect icon/ID.
local statusOnMes = {
    [29]=true, [84]=true,   -- IS_PARALYZED, IS_PARALYZED_2 (<target> is paralyzed)
    [186]=true,             -- USES_SKILL_GAINS_EFFECT
    [203]=true,             -- IS_STATUS
    [205]=true,             -- MsgStd::GainsEffect
    [230]=true, [236]=true, [237]=true,  -- MAGIC_GAINS_EFFECT, MAGIC_STATUS, MAGIC_RECEIVES_EFFECT
    [242]=true, [243]=true, -- USES_SKILL_STATUS, USES_SKILL_RECEIVES_EFFECT
    [266]=true, [277]=true, [278]=true,  -- TARGET_GAINS_EFFECT, TARGET_STATUS, TARGET_RECEIVES_EFFECT
    [374]=true,             -- STATUS_SPIKES (attacker gains from spikes)
    [420]=true, [421]=true, -- ROLL_MAIN, ROLL_SUB (target receives effect)
};
-- Message IDs for "effect wears off / target loses status" (LSB msg_basic.h + msg_std.h). Param = effect icon/ID.
-- Includes normal expiry, dispel, DRG Spirit Link and BST Reward II clearing pet buffs (server sends 206 per effect).
local statusOffMes = {
    [206]=true,             -- MsgStd::EffectWearsOff
    [343]=true,             -- MsgBasic::TARGET_EFFECT_DISAPPEARS
    [378]=true,             -- MsgBasic::USES_ABILITY_DISPEL
    [426]=true, [427]=true, -- MsgBasic::DOUBLEUP_BUST, DOUBLEUP_BUST_SUB
};
local deathMes = {
    [6]=true, [20]=true, [97]=true, [113]=true, [406]=true, [605]=true, [646]=true,
};

local function GetPetServerId()
    local playerEntity = GetPlayerEntity();
    if not playerEntity or playerEntity.PetTargetIndex == 0 then return nil; end
    local pet = GetEntity(playerEntity.PetTargetIndex);
    return pet and pet.ServerId or nil;
end

local function ClearAllEffects()
    petEffects = {};
end

local function ApplyEffect(opts)
    if not opts or not opts.effect then return; end
    local effectId = opts.effect;
    local duration = opts.duration;
    local isBuff = duration ~= nil;
    if isBuff and (type(duration) ~= 'number' or duration < 0) then return; end
    local existing = petEffects[effectId];
    if existing and existing.isBuff and not isBuff then return; end
    local expiry = isBuff and (os.time() + duration) or nil;
    petEffects[effectId] = { expiryTime = expiry, isBuff = isBuff };
end

local function RemoveEffect(effectId)
    if effectId then petEffects[effectId] = nil; end
end

local function tryApplyUnknownStatus(message, param, pkt, alreadyHandled)
    if alreadyHandled or not statusOnMes[message] then return; end
    local effectId = param;
    if (not effectId or effectId == 0 or effectId > 1000) and pkt and pkt.Type == 4 then
        effectId = buffTable.GetBuffIdBySpellId(pkt.Param);
    end
    if not effectId or effectId <= 0 or effectId >= 1000 then return; end
    local duration;
    for _, buffData in pairs(PET_ABILITY_BUFFS) do
        if buffData.effectId == effectId then
            duration = buffData.duration;
            break;
        end
    end
    ApplyEffect({ effect = effectId, duration = duration });
end

petBuffHandler.HandleActionPacket = function(actionPacket)
    if not actionPacket then return; end

    local petServerId = GetPetServerId();
    if not petServerId then return; end

    if currentPetServerId ~= petServerId then
        ClearAllEffects();
        currentPetServerId = petServerId;
    end

    local abilityId = actionPacket.Param;
    local playerEntity = GetPlayerEntity();
    local playerServerId = playerEntity and playerEntity.ServerId or nil;
    local actorIsMyPet = (actionPacket.UserId == petServerId);
    local actorIsMe = playerServerId and (actionPacket.UserId == playerServerId);

    for _, target in pairs(actionPacket.Targets or {}) do
        if target.Id == petServerId then
            for _, action in pairs(target.Actions or {}) do
                local message = action.Message;
                local param = action.Param;
                local handled = false;

                local buffData = PET_ABILITY_BUFFS[abilityId];
                -- Jug pets: server sends mob skill ID in Param, not ability ID; match by result effect ID
                if not buffData and param and param > 0 and param < 1000 then
                    for _, b in pairs(PET_ABILITY_BUFFS) do
                        if b.effectId == param then
                            buffData = b;
                            break;
                        end
                    end
                end
                if buffData then
                    local allowApply = actorIsMyPet or (buffData.playerCast and actorIsMe);
                    if allowApply then
                        ApplyEffect({ effect = buffData.effectId, duration = buffData.duration });
                        handled = true;
                    end
                end

                tryApplyUnknownStatus(message, param, actionPacket, handled);

                if action.AdditionalEffect and action.AdditionalEffect.Message and action.AdditionalEffect.Param then
                    tryApplyUnknownStatus(action.AdditionalEffect.Message, action.AdditionalEffect.Param, actionPacket, false);
                end

                if statusOffMes[message] and param and petEffects[param] then
                    RemoveEffect(param);
                end
                if action.AdditionalEffect and action.AdditionalEffect.Param and statusOffMes[action.AdditionalEffect.Message] and petEffects[action.AdditionalEffect.Param] then
                    RemoveEffect(action.AdditionalEffect.Param);
                end
            end
        end
    end
end

petBuffHandler.HandleMessagePacket = function(messagePacket)
    if not messagePacket then return; end

    local petServerId = GetPetServerId();
    if not petServerId then return; end

    local targetId = messagePacket.target;
    local senderId = messagePacket.sender;
    local message = messagePacket.message;
    local param = messagePacket.param;

    local isPetRelevant = (targetId == petServerId) or (message == 206 and senderId == petServerId);
    if not isPetRelevant then return; end

    if deathMes[message] then
        ClearAllEffects();
        return;
    end

    if statusOnMes[message] and param and param > 0 and param < 1000 then
        local duration;
        for _, buffData in pairs(PET_ABILITY_BUFFS) do
            if buffData.effectId == param then
                duration = buffData.duration;
                break;
            end
        end
        ApplyEffect({ effect = param, duration = duration });
    end

    if statusOffMes[message] and param and petEffects[param] then
        RemoveEffect(param);
    end
end

petBuffHandler.HandleZonePacket = function()
    ClearAllEffects();
    currentPetServerId = nil;
end

petBuffHandler.GetActiveEffects = function()
    local petServerId = GetPetServerId();
    if not petServerId then return nil, nil; end

    if currentPetServerId ~= petServerId then
        ClearAllEffects();
        currentPetServerId = petServerId;
        return nil, nil;
    end

    for i = 1, #activeEffectIds do
        activeEffectIds[i] = nil;
        activeEffectTimes[i] = nil;
    end

    local count = 0;
    local currentTime = os.time();
    local toRemove = {};

    for effectId, effectData in pairs(petEffects) do
        local expiryTime = effectData.expiryTime;
        local remaining = expiryTime and (expiryTime - currentTime) or nil;
        if expiryTime and remaining > 300 then
            toRemove[effectId] = true;
        else
            count = count + 1;
            activeEffectIds[count] = effectId;
            activeEffectTimes[count] = (effectData.isBuff and remaining and remaining > 0) and remaining or nil;
        end
    end

    for effectId in pairs(toRemove) do
        petEffects[effectId] = nil;
    end

    if count == 0 then return nil, nil; end
    return activeEffectIds, activeEffectTimes;
end

petBuffHandler.HasEffect = function(effectId)
    return effectId and petEffects[effectId] ~= nil;
end

petBuffHandler.GetEffectRemainingTime = function(effectId)
    if not effectId then return 0; end
    local data = petEffects[effectId];
    if not data then return 0; end
    if not data.isBuff then return nil; end
    return math.max(0, data.expiryTime - os.time());
end

petBuffHandler.ClearAll = function()
    ClearAllEffects();
    currentPetServerId = nil;
end

return petBuffHandler;
