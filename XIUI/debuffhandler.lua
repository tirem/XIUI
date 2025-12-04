-- GNU Licensed by mousseng's XITools repository [https://github.com/mousseng/xitools]
require('common');
require('helpers');
local buffTable = require('bufftable');

local debuffHandler =
T{
    -- All enemies we have seen take a debuff
    enemies = T{};
};

-- Reusable tables for GetActiveDebuffs to avoid per-frame allocations
-- These are cleared and reused each call instead of creating new tables
local reusableDebuffIds = {};
local reusableDebuffTimes = {};

-- TO DO: Audit these messages for which ones are actually useful
local statusOnMes = T{101, 127, 160, 164, 166, 186, 194, 203, 205, 230, 236, 266, 267, 268, 269, 237, 271, 272, 277, 278, 279, 280, 319, 320, 375, 412, 645, 754, 755, 804};
local statusOffMes = T{64, 159, 168, 204, 206, 321, 322, 341, 342, 343, 344, 350, 378, 531, 647, 805, 806};
local deathMes = T{6, 20, 97, 113, 406, 605, 646};
local spellDamageMes = T{2, 252, 264, 265};
local additionalEffectJobAbilities = T{22, 45, 46, 77}; --energy drain, mug, shield bash, weapon bash
local additionalEffectMes = T{160};

local function ApplyMessage(debuffs, action)

    if (action == nil) then
        return;
    end

    local now = os.time()

    for _, target in pairs(action.Targets) do
        for _, ability in pairs(target.Actions) do

            -- Set up our state
            local spell = action.Param
            local message = ability.Message
            local additionalEffect

            if (ability.AdditionalEffect ~= nil and ability.AdditionalEffect.Message ~= nil) then
                additionalEffect = ability.AdditionalEffect.Message
            end

            if (debuffs[target.Id] == nil) then
                debuffs[target.Id] = T{}; 
            end

            if action.Type == 13 then
                if spell == 1908 then -- nightmare
                    debuffs[target.Id][2] = now + 60
                end
            elseif action.Type == 4 and spellDamageMes:contains(message) then -- dia / bio damage handling
                local expiry = nil

                if spell == 23 or spell == 33 or spell == 230 then
                    expiry = now + 60
                elseif spell == 24 or spell == 231 then
                    expiry = now + 120
                elseif spell == 25 or spell == 232 then
                    expiry = now + 150
                end

                if spell == 23 or spell == 24 or spell == 25 or spell == 33 then
                    debuffs[target.Id][134] = expiry
                    debuffs[target.Id][135] = nil
                elseif spell == 230 or spell == 231 or spell == 232 then
                    debuffs[target.Id][134] = nil
                    debuffs[target.Id][135] = expiry
                end
            elseif statusOnMes:contains(message) then
                -- Regular (de)buffs
                local buffId = ability.Param or (action.Type == 4 and buffTable.GetBuffIdBySpellId(spell) or nil);
                if (buffId == nil) then
                    return
                end

                if spell == 58 or spell == 80 then -- para/para2
                    debuffs[target.Id][buffId] = now + 120
                elseif spell == 56 or spell == 79 then -- slow/slow2
                    debuffs[target.Id][buffId] = now + 180
                elseif spell == 216 then -- gravity
                    debuffs[target.Id][buffId] = now + 120
                elseif spell == 254 or spell == 276 then -- blind/blind2
                    debuffs[target.Id][buffId] = now + 180
                elseif spell == 341 or spell == 344 or spell == 347 then -- ninjutsu debuffs: ichi
                    debuffs[target.Id][buffId] = now + 180
                elseif spell == 342 or spell == 345 or spell == 348 then -- ninjutsu debuffs: ni
                    debuffs[target.Id][buffId] = now + 300
                elseif spell == 23 then -- dia
                    debuffs[target.Id][buffId] = now + 60
                elseif spell == 24 then -- dia2
                    debuffs[target.Id][buffId] = now + 120
                elseif spell == 230 then -- bio
                    debuffs[target.Id][buffId] = now + 60
                elseif spell == 231 then -- bio2
                    debuffs[target.Id][buffId] = now + 120
                elseif spell == 59 or spell == 359 then -- silence/ga
                    debuffs[target.Id][buffId] = now + 120
                elseif spell == 253 or spell == 273 or spell == 363 then -- sleep/ga
                    debuffs[target.Id][buffId] = now + 60
                elseif spell == 259 or spell == 274 or spell == 364 then -- sleep2/ga2
                    debuffs[target.Id][2] = nil
                    debuffs[target.Id][193] = nil 
                    debuffs[target.Id][buffId] = now + 90 --id 19
                elseif spell == 376 or spell == 463 then -- foe/horde lullaby
                    debuffs[target.Id][buffId] = now + 30
                elseif spell == 258 or spell == 362 then -- bind
                    debuffs[target.Id][buffId] = now + 60
                elseif spell == 252 then -- stun
                    debuffs[target.Id][buffId] = now + 5
                elseif spell == 220 then -- poison
                    debuffs[target.Id][buffId] = now + 90
                elseif spell == 221 then -- poison2
                    debuffs[target.Id][buffId] = now + 120
                elseif spell >= 235 and spell <= 240 then -- elemental debuffs
                    debuffs[target.Id][buffId] = now + 120
                elseif spell >= 454 and spell <= 461 then -- threnodies
                    debuffs[target.Id][buffId] = now + 78
                elseif spell == 422 or spell == 421 then -- elegies
                    debuffs[target.Id][buffId] = now + 216
                elseif spell == 321 then -- bully
                    debuffs[target.Id][buffId] = now + 60
                elseif spell == 688 then -- mighty strikes
                    debuffs[target.Id][buffId] = now + 45
                elseif spell == 690 then -- hundred fist
                    debuffs[target.Id][buffId] = now + 45
                elseif spell == 691 then -- manafont
                    debuffs[target.Id][buffId] = now + 60
                elseif spell == 692 then -- chainspell
                    debuffs[target.Id][buffId] = now + 60
                elseif spell == 693 then -- perfect dodge
                    debuffs[target.Id][buffId] = now + 30
                elseif spell == 694 then -- invincible
                    debuffs[target.Id][buffId] = now + 30
                elseif spell == 695 then -- blood weapon
                    debuffs[target.Id][buffId] = now + 30
                else -- Handle unknown status effect @ 5 minutes
                    debuffs[target.Id][buffId] = now + 300;
                end
            elseif statusOffMes:contains(message) then --341 dispel
                if (ability.Param == nil) then
                    return
                else
                    debuffs[target.Id][ability.Param] = nil
                end
            elseif action.Type == 3 and additionalEffectJobAbilities:contains(spell) then
                if spell == 22 and message == 185 then -- energy drain
                    if (debuffs[target.Id][13] == nil or debuffs[target.Id][13] < now) then
                        debuffs[target.Id][13] = now + 120
                    end
                elseif spell == 45 then -- mug
                    if (debuffs[target.Id][448] == nil or debuffs[target.Id][448] < now) then
                        debuffs[target.Id][448] = now + 30
                    end
                elseif spell == 46 then -- shield bash
                    if (debuffs[target.Id][10] == nil or debuffs[target.Id][10] < now) then
                        debuffs[target.Id][10] = now + 6
                    end
                elseif spell == 77 then -- weapon bash
                    if (debuffs[target.Id][10] == nil or debuffs[target.Id][10] < now) then
                        debuffs[target.Id][10] = now + 6
                    end
                --elseif spell == 82 then -- chi blast (will need this later for handling penance)
                end
            elseif additionalEffect ~= nil and additionalEffectMes:contains(additionalEffect) then
                local buffId = ability.AdditionalEffect.Param;
                if (buffId == nil) then
                    return
                end

                if buffId == 2 then -- sleep bolt
                    debuffs[target.Id][buffId] = now + 25
                elseif buffId == 149 then -- defense down/acid bolt
                    debuffs[target.Id][buffId] = now + 60
                elseif buffId == 12 then -- gravity/mandau
                    debuffs[target.Id][buffId] = now + 30
                else
                    debuffs[target.Id][buffId] = now + 30
                end
            end
        end
    end
end

local function ClearMessage(debuffs, basic)
    -- if we're tracking a mob that dies, reset its status
    if deathMes:contains(basic.message) and debuffs[basic.target] then
        debuffs[basic.target] = nil
    elseif (basic.message == 321) then --Custom Chi Blast dispel message
        if (debuffs[basic.target] == nil or basic.value == nil) then
            return
        end

        debuffs[basic.target][basic.value] = nil
    elseif statusOffMes:contains(basic.message) then
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

debuffHandler.HandleActionPacket = function(e)
    ApplyMessage(debuffHandler.enemies, e);
end

debuffHandler.HandleZonePacket = function(e)
    debuffHandler.enemies = {};
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

    -- Cache os.time() once instead of calling it repeatedly in the loop
    local currentTime = os.time();

    for buffId, expiryTime in pairs(debuffHandler.enemies[serverId]) do
        if (expiryTime ~= 0 and expiryTime > currentTime) then
            count = count + 1;
            reusableDebuffIds[count] = buffId;
            reusableDebuffTimes[count] = expiryTime - currentTime;
        end
    end

    -- Return nil if no active debuffs (same behavior as before)
    if count == 0 then
        return nil;
    end

    return reusableDebuffIds, reusableDebuffTimes;
end

return debuffHandler;