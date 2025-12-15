-- GNU Licensed by mousseng's XITools repository [https://github.com/mousseng/xitools]
require('common');
require('handlers.helpers');
local buffTable = require('libs.bufftable');

local debuffHandler =
T{
    -- All enemies we have seen take a debuff
    enemies = T{};
};

-- Reusable tables for GetActiveDebuffs to avoid per-frame allocations
-- These are cleared and reused each call instead of creating new tables
local reusableDebuffIds = {};
local reusableDebuffTimes = {};

-- Message type hash tables for O(1) lookup (converted from T{} arrays)
local statusOnMes = {[101]=true, [127]=true, [160]=true, [164]=true, [166]=true, [186]=true, [194]=true, [203]=true, [205]=true, [230]=true, [236]=true, [266]=true, [267]=true, [268]=true, [269]=true, [237]=true, [271]=true, [272]=true, [277]=true, [278]=true, [279]=true, [280]=true, [319]=true, [320]=true, [375]=true, [412]=true, [645]=true, [754]=true, [755]=true, [804]=true};
local statusOffMes = {[64]=true, [159]=true, [168]=true, [204]=true, [206]=true, [321]=true, [322]=true, [341]=true, [342]=true, [343]=true, [344]=true, [350]=true, [378]=true, [531]=true, [647]=true, [805]=true, [806]=true};
local deathMes = {[6]=true, [20]=true, [97]=true, [113]=true, [406]=true, [605]=true, [646]=true};
local spellDamageMes = {[2]=true, [252]=true, [264]=true, [265]=true};
local additionalEffectJobAbilities = {[22]=true, [45]=true, [46]=true, [77]=true}; --energy drain, mug, shield bash, weapon bash
local additionalEffectMes = {[160]=true, [164]=true};

-- Spell duration lookup table for O(1) performance
-- Maps spell IDs to duration (in seconds) and optionally buff ID overrides
local SPELL_DURATIONS = {
    -- Weapon skills with debuffs
    [181] = {duration = 180, buffId = 149}, -- Shell Crusher - Defense Down
    [83] = {duration = 180, buffId = 149},  -- Armor Break - Defense Down
    [87] = {duration = 180, buffIds = {149, 147}}, -- Full Break - Defense Down & Attack Down
    [155] = {duration = 180, buffId = 149}, -- Tachi: Ageha - Defense Down
    [187] = {duration = 180, buffId = 149}, -- Garland of Bliss - Defense Down
    [89] = {duration = 180, buffId = 149},  -- Metatron Torment - Defense Down
    [85] = {duration = 180, buffId = 147},  -- Weapon Break - Attack Down
    [185] = {duration = 180, buffId = 147}, -- Gate of Tartarus - Attack Down
    [107] = {duration = 180, buffId = 147}, -- Infernal Scythe - Attack Down
    [16] = {duration = 90, buffId = 3},     -- Wasp Sting - Poison
    [17] = {duration = 90, buffId = 3},     -- Viper Bite - Poison
    [18] = {duration = 30, buffId = 11},    -- Shadowstitch - Bind
    [35] = {duration = 5, buffId = 10},     -- Flat Blade - Stun
    [115] = {duration = 5, buffId = 10},    -- Leg Sweep - Stun
    [2] = {duration = 5, buffId = 10},      -- Shoulder Tackle - Stun
    [65] = {duration = 5, buffId = 10},     -- Smash Axe - Stun
    [162] = {duration = 5, buffId = 10},    -- Brainshaker - Stun
    [145] = {duration = 5, buffId = 10},    -- Tachi: Hobaku - Stun
    [80] = {duration = 180, buffId = 148},  -- Shield Break - Evasion Down

    -- Dia/Bio spells
    [23] = {duration = 60},   -- Dia
    [33] = {duration = 60},   -- Diaga
    [230] = {duration = 60},  -- Bio
    [24] = {duration = 120},  -- Dia II
    [231] = {duration = 120}, -- Bio II
    [25] = {duration = 150},  -- Dia III
    [232] = {duration = 150}, -- Bio III

    -- Helix spells (278-285 and 885-892)
    [278] = {duration = 90, buffId = 186}, [279] = {duration = 90, buffId = 186},
    [280] = {duration = 90, buffId = 186}, [281] = {duration = 90, buffId = 186},
    [282] = {duration = 90, buffId = 186}, [283] = {duration = 90, buffId = 186},
    [284] = {duration = 90, buffId = 186}, [285] = {duration = 90, buffId = 186},
    [885] = {duration = 90, buffId = 186}, [886] = {duration = 90, buffId = 186},
    [887] = {duration = 90, buffId = 186}, [888] = {duration = 90, buffId = 186},
    [889] = {duration = 90, buffId = 186}, [890] = {duration = 90, buffId = 186},
    [891] = {duration = 90, buffId = 186}, [892] = {duration = 90, buffId = 186},

    -- Regular debuff spells
    [58] = {duration = 120},  -- Paralyze
    [80] = {duration = 120},  -- Paralyze II
    [56] = {duration = 180},  -- Slow
    [79] = {duration = 180},  -- Slow II
    [216] = {duration = 120}, -- Gravity
    [254] = {duration = 180}, -- Blind
    [276] = {duration = 180}, -- Blind II
    [59] = {duration = 120},  -- Silence
    [359] = {duration = 120}, -- Silencega
    [253] = {duration = 60},  -- Sleep
    [273] = {duration = 60},  -- Sleepga
    [363] = {duration = 60},  -- Sleepga II
    [259] = {duration = 90, buffId = 19, clearsBuffs = {2, 193}}, -- Sleep II
    [274] = {duration = 90, buffId = 19, clearsBuffs = {2, 193}}, -- Sleepga II
    [364] = {duration = 90, buffId = 19, clearsBuffs = {2, 193}}, -- Sleepga III
    [258] = {duration = 60},  -- Bind
    [362] = {duration = 60},  -- Bindga
    [252] = {duration = 5},   -- Stun
    [220] = {duration = 90},  -- Poison
    [221] = {duration = 120}, -- Poison II

    -- Ninjutsu debuffs
    [341] = {duration = 180}, -- Kurayami: Ichi
    [344] = {duration = 180}, -- Hojo: Ichi
    [347] = {duration = 180}, -- Dokumori: Ichi
    [342] = {duration = 300}, -- Kurayami: Ni
    [345] = {duration = 300}, -- Hojo: Ni
    [348] = {duration = 300}, -- Dokumori: Ni

    -- Elemental debuffs (Burn, Frost, Choke, Rasp, Shock, Drown)
    [235] = {duration = 120}, [236] = {duration = 120},
    [237] = {duration = 120}, [238] = {duration = 120},
    [239] = {duration = 120}, [240] = {duration = 120},

    -- Threnodies (454-461)
    [454] = {duration = 78}, [455] = {duration = 78},
    [456] = {duration = 78}, [457] = {duration = 78},
    [458] = {duration = 78}, [459] = {duration = 78},
    [460] = {duration = 78}, [461] = {duration = 78},

    -- Elegies
    [422] = {duration = 216}, -- Carnage Elegy
    [421] = {duration = 216}, -- Battlefield Elegy

    -- Bard songs
    [376] = {duration = 30}, -- Foe Lullaby
    [463] = {duration = 30}, -- Horde Lullaby
    [321] = {duration = 60}, -- Bully

    -- 2-Hour abilities
    [688] = {duration = 45}, -- Mighty Strikes
    [690] = {duration = 45}, -- Hundred Fists
    [691] = {duration = 60}, -- Manafont
    [692] = {duration = 60}, -- Chainspell
    [693] = {duration = 30}, -- Perfect Dodge
    [694] = {duration = 30}, -- Invincible
    [695] = {duration = 30}, -- Blood Weapon

    -- Job abilities with debuffs
    [22] = {duration = 120, buffId = 13},  -- Energy Drain - Max HP Down
    [45] = {duration = 30, buffId = 448},  -- Mug - ???
    [46] = {duration = 6, buffId = 10},    -- Shield Bash - Stun
    [77] = {duration = 6, buffId = 10},    -- Weapon Bash - Stun

    -- Additional effect debuffs
    [2] = {duration = 25, additionalEffect = true},   -- Sleep Bolt
    [149] = {duration = 60, additionalEffect = true}, -- Defense Down/Acid Bolt
    [12] = {duration = 30, additionalEffect = true},  -- Gravity/Mandau

    -- Special cases
    [1908] = {duration = 60, buffId = 2, type = 13}, -- Nightmare (pet ability)
};

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

            -- Handle pet abilities (Type 13)
            if action.Type == 13 and spell == 1908 then
                -- Nightmare
                debuffs[target.Id][2] = now + 60
            -- Handle weapon skills (Type 3 with damage message)
            elseif action.Type == 3 and message == 185 then
                local spellData = SPELL_DURATIONS[spell];
                if spellData then
                    if spellData.buffId then
                        debuffs[target.Id][spellData.buffId] = now + spellData.duration;
                    end
                    if spellData.buffIds then
                        for _, buffId in ipairs(spellData.buffIds) do
                            debuffs[target.Id][buffId] = now + spellData.duration;
                        end
                    end
                end
            -- Handle dia/bio/helix spells (Type 4 with damage message)
            elseif action.Type == 4 and spellDamageMes[message] then
                local spellData = SPELL_DURATIONS[spell];
                if spellData then
                    local expiry = now + spellData.duration;
                    if spell == 23 or spell == 24 or spell == 25 or spell == 33 then
                        -- Dia spells - set dia, clear bio
                        debuffs[target.Id][134] = expiry;
                        debuffs[target.Id][135] = nil;
                    elseif spell == 230 or spell == 231 or spell == 232 then
                        -- Bio spells - set bio, clear dia
                        debuffs[target.Id][134] = nil;
                        debuffs[target.Id][135] = expiry;
                    elseif spellData.buffId then
                        -- Helix spells
                        debuffs[target.Id][spellData.buffId] = expiry;
                    end
                end
            -- Handle regular status effect spells
            elseif statusOnMes[message] then
                local buffId = ability.Param or (action.Type == 4 and buffTable.GetBuffIdBySpellId(spell) or nil);
                if (buffId == nil) then
                    return
                end

                local spellData = SPELL_DURATIONS[spell];
                if spellData then
                    -- Handle special clear buffs (Sleep II clears Sleep I)
                    if spellData.clearsBuffs then
                        for _, clearBuffId in ipairs(spellData.clearsBuffs) do
                            debuffs[target.Id][clearBuffId] = nil;
                        end
                    end
                    -- Apply the debuff
                    local finalBuffId = spellData.buffId or buffId;
                    debuffs[target.Id][finalBuffId] = now + spellData.duration;
                else
                    -- Unknown status effect - default to 5 minutes
                    debuffs[target.Id][buffId] = now + 300;
                end
            -- Handle dispel effects
            elseif statusOffMes[message] then
                if (ability.Param == nil) then
                    return
                else
                    debuffs[target.Id][ability.Param] = nil
                end
            -- Handle job abilities with additional effects
            elseif action.Type == 3 and additionalEffectJobAbilities[spell] then
                local spellData = SPELL_DURATIONS[spell];
                if spellData and spellData.buffId and (message == 185 or spell ~= 22) then
                    -- Only apply if not already present or expired
                    if (debuffs[target.Id][spellData.buffId] == nil or debuffs[target.Id][spellData.buffId] < now) then
                        debuffs[target.Id][spellData.buffId] = now + spellData.duration;
                    end
                end
            -- Handle additional effects (weapon procs, etc.)
            elseif additionalEffect ~= nil and additionalEffectMes[additionalEffect] then
                local buffId = ability.AdditionalEffect.Param;
                if (buffId == nil) then
                    return
                end

                local spellData = SPELL_DURATIONS[buffId];
                if spellData and spellData.additionalEffect then
                    debuffs[target.Id][buffId] = now + spellData.duration;
                else
                    -- Default duration for unknown additional effects
                    debuffs[target.Id][buffId] = now + 30;
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