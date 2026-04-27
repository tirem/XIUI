--[[
 * Cache-bust signature for weaponskill lists: job, levels, level sync, equipped item ids.
 * We do not interpret weapon type — WS availability comes from HasAbility only.
 * Including main/sub/range item ids forces a refresh when gear changes so caches stay in sync
 * with the client without modeling main-hand vs sub-hand weapon families.
 *
 * Equip slots: IInventory:GetEquippedItem(index) — main=0, sub=1, range=2 (FFXI layout).
]]--

local M = {};

local EQUIP_MAIN = 0;
local EQUIP_SUB = 1;
local EQUIP_RANGE = 2;

local function getEquippedItemId(inventory, equipSlot)
    if not inventory then return 0; end
    local equipped = inventory:GetEquippedItem(equipSlot);
    if not equipped then return 0; end
    local idx = bit.band(equipped.Index or 0, 0x00FF);
    if idx == 0 then return 0; end
    local container = bit.rshift(bit.band(equipped.Index or 0, 0xFF00), 8);
    local item = inventory:GetContainerItem(container, idx);
    if not item or not item.Id then return 0; end
    return item.Id;
end

--- Stable signature for invalidating cached spells/abilities/WS: no weapon-category logic.
---@return string
function M.GetPlayerWeaponskillCacheSignature(player)
    if not player then return ''; end
    local memMgr = AshitaCore:GetMemoryManager();
    local inventory = memMgr and memMgr:GetInventory() or nil;

    local mainId = getEquippedItemId(inventory, EQUIP_MAIN);
    local subId = getEquippedItemId(inventory, EQUIP_SUB);
    local rangeId = getEquippedItemId(inventory, EQUIP_RANGE);

    local hasSync = false;
    local buffs = player.GetBuffs and player:GetBuffs() or nil;
    if buffs then
        for i = 1, 32 do
            if buffs[i] == 269 then
                hasSync = true;
                break;
            end
        end
    end

    -- Party slot 0 often reflects effective (level sync) job levels as soon as packets update; Player
    -- API can lag briefly. Including both avoids stale spell/WS caches when the sync cap moves (e.g.
    -- sync target levels up) while buff 269 stays on.
    local partyMainLv = 0;
    local partySubLv = 0;
    local party = memMgr and memMgr:GetParty() or nil;
    if party and party.GetMemberIsActive and party:GetMemberIsActive(0) == 1 then
        partyMainLv = party:GetMemberMainJobLevel(0) or 0;
        partySubLv = party:GetMemberSubJobLevel(0) or 0;
    end

    return string.format(
        '%d:%d:%d:%d:%d:%d:%d:%d:%d:%d',
        player:GetMainJob() or 0,
        player:GetSubJob() or 0,
        player:GetMainJobLevel() or 0,
        player:GetSubJobLevel() or 0,
        mainId,
        subId,
        rangeId,
        hasSync and 1 or 0,
        partyMainLv,
        partySubLv
    );
end

-- Back-compat alias (same signature, clearer name going forward)
M.GetPlayerEquipmentWeaponskillSignature = M.GetPlayerWeaponskillCacheSignature;

return M;
