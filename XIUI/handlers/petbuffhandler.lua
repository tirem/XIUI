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

-- Message IDs for status gain, loss, and death
local statusOnMes = {
    [32]=true, [82]=true, [127]=true, [141]=true, [146]=true, [186]=true, [194]=true,
    [203]=true, [205]=true, [236]=true, [238]=true, [242]=true, [243]=true, [364]=true,
};
local statusOffMes = {
    [64]=true, [159]=true, [168]=true, [204]=true, [206]=true,
    [321]=true, [322]=true, [341]=true, [342]=true, [343]=true,
    [344]=true, [350]=true, [378]=true, [531]=true, [647]=true,
    [805]=true, [806]=true,
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

local function GetHorizonRageDuration()
    local player = GetPlayerSafe();
    if not player then return 60; end
    local tp = player:GetPetTP();
    if not tp or tp > 3000 then tp = 0; end
    if tp < 1000 then return 60; end
    return 60 + math.floor((tp - 1000) * 0.06);
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
    if pkt.Type == 4 and (not effectId or effectId == 0 or effectId > 1000) then
        effectId = buffTable.GetBuffIdBySpellId(pkt.Param);
    end
    if not effectId or effectId <= 0 or effectId >= 1000 then return; end
    ApplyEffect({ effect = effectId });
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

    for _, target in pairs(actionPacket.Targets or {}) do
        if target.Id == petServerId then
            for _, action in pairs(target.Actions or {}) do
                local message = action.Message;
                local param = action.Param;
                local handled = false;

                local buffData = PET_ABILITY_BUFFS[abilityId];
                if buffData then
                    local duration = buffData.duration;
                    if buffData.effectId == 56 and _G.HzLimitedMode then
                        duration = GetHorizonRageDuration();
                    end
                    ApplyEffect({ effect = buffData.effectId, duration = duration });
                    handled = true;
                end

                tryApplyUnknownStatus(message, param, actionPacket, handled);

                if statusOffMes[message] and param and petEffects[param] then
                    RemoveEffect(param);
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
    local message = messagePacket.message;
    local param = messagePacket.param;

    if targetId ~= petServerId then return; end

    if deathMes[message] then
        ClearAllEffects();
        return;
    end

    if statusOnMes[message] and param and param > 0 and param < 1000 then
        ApplyEffect({ effect = param });
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
