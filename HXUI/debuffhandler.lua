-- GNU Licensed by mousseng's XITools repository [https://github.com/mousseng/xitools]
require('common');
require('helpers');
local buffTable = require('bufftable');

local debuffHandler = 
T{
    -- All enemies we have seen take a debuff
    enemies = T{};
};

local function ApplyMessage(debuffs, action)
    local now = os.time()

    for _, target in pairs(action.targets) do
        for _, ability in pairs(target.actions) do
            if action.category == 4 then
                -- Set up our state
                local spell = action.param
                local message = ability.message
                if (debuffs[target.id] == nil) then
                    debuffs[target.id] = {};
                end

                -- Find our buff Id
                local buffId = buffTable.GetBuffIdBySpellId(spell);
                if (buffId == nil) then
                    return
                end

                -- Bio and Dia
                if message == 2 or message == 264 then
                    local expiry = 0

                    if spell == 23 or spell == 33 or spell == 230 then
                        expiry = now + 60
                    elseif spell == 24 or spell == 231 then
                        expiry = now + 120
                    elseif spell == 25 or spell == 232 then
                        expiry = now + 150
                    else
                        -- something went wrong
                        expiry = nil
                    end

                    if spell == 23 or spell == 24 or spell == 25 or spell == 33 then
                        debuffs[target.id][buffId] = expiry
                        bioId = buffTable.GetBuffIdBySpellName("bio");
                        debuffs[target.id][bioId] = 0
                    elseif spell == 230 or spell == 231 or spell == 232 then
                        diaId = buffTable.GetBuffIdBySpellName("dia");
                        debuffs[target.id][diaId] = 0
                        debuffs[target.id][buffId] = expiry
                    end
                -- Regular debuffs
                elseif message == 236 or message == 277 then
                    if spell == 58 or spell == 80 then -- para/para2
                        debuffs[target.id][buffId] = now + 120
                    elseif spell == 56 or spell == 79 then -- slow/slow2
                        debuffs[target.id][buffId] = now + 180
                    elseif spell == 216 then -- gravity
                        debuffs[target.id][buffId] = now + 120
                    elseif spell == 254 or spell == 276 then -- blind/blind2
                        debuffs[target.id][buffId] = now + 180
                    elseif spell == 59 or spell == 359 then -- silence/ga
                        debuffs[target.id][buffId] = now + 120
                    elseif spell == 253 or spell == 259 or spell == 273 or spell == 274 then -- sleep/2/ga/2
                        debuffs[target.id][buffId] = now + 90
                    elseif spell == 258 or spell == 362 then -- bind
                        debuffs[target.id][buffId] = now + 60
                    elseif spell == 252 then -- stun
                        debuffs[target.id][buffId] = now + 5
                    elseif spell <= 229 and spell >= 220 then -- poison/2
                        debuffs[target.id][buffId] = now + 120
                    end
                -- Elemental debuffs
                elseif message == 237 or message == 278 then
                    if spell == 239 then -- shock
                        debuffs[target.id][buffId] = now + 120
                    elseif spell == 238 then -- rasp
                        debuffs[target.id][buffId] = now + 120
                    elseif spell == 237 then -- choke
                        debuffs[target.id][buffId] = now + 120
                    elseif spell == 236 then -- frost
                        debuffs[target.id][buffId] = now + 120
                    elseif spell == 235 then -- burn
                        debuffs[target.id][buffId] = now + 120
                    elseif spell == 240 then -- drown
                        debuffs[target.id][buffId] = now + 120
                    end
                end
            end
        end
    end
end

local function ClearMessage(debuffs, basic)
    -- if we're tracking a mob that dies, reset its status
    if basic.message == 6 and debuffs[basic.target] then
        debuffs[basic.target] = nil
    elseif basic.message == 206 then
        if debuffs[basic.target] == nil then
            return
        end

        -- Clear the buffid that just wore off
        if (basic.param ~= nil) then
            debuffs[basic.target][basic.param] = nil;
        end
    end
end

debuffHandler.HandlePacket = function(e)
    if e.id == 0x0A then
        debuffHandler.enemies = {};
    elseif e.id == 0x0028 then
        ApplyMessage(debuffHandler.enemies, ParseActionPacketAlt(e));
    elseif e.id == 0x0029 then
        ClearMessage(debuffHandler.enemies, ParseMessagePacket(e.data))
    end
end

debuffHandler.GetActiveDebuffs = function(serverId)

    if (debuffHandler.enemies[serverId] == nil) then
        return nil
    end
    local returnTable = {};
    for k,v in pairs(debuffHandler.enemies[serverId]) do
        if (v ~= nil and v ~= 0 and v > os.time()) then
            table.insert(returnTable, k);
        end
    end
    return returnTable;
end

return debuffHandler;