--[[
* XIUI Hotbar - Skillchain Prediction Module
* Based on tHotBar's skillchain implementation by Thorny
* Property tables: Chains-Horizon (HzLimitedMode) or LandSandBoat retail port
]]--

require('common');

local ffi = require('ffi');
local actiondb = require('modules.hotbar.actiondb');

local M = {};

-- Resonation type constants (matching tHotBar)
local Resonation = {
    None = 0,
    Liquefaction = 1,
    Induration = 2,
    Detonation = 3,
    Scission = 4,
    Impaction = 5,
    Reverberation = 6,
    Transfixion = 7,
    Compression = 8,
    Fusion = 9,
    Gravitation = 10,
    Distortion = 11,
    Fragmentation = 12,
    Light = 13,
    Darkness = 14,
    Light2 = 15,
    Darkness2 = 16,
    Radiance = 17,
    Umbra = 18
};

local resonationNames = {
    'Liquefaction',
    'Induration',
    'Detonation',
    'Scission',
    'Impaction',
    'Reverberation',
    'Transfixion',
    'Compression',
    'Fusion',
    'Gravitation',
    'Distortion',
    'Fragmentation',
    'Light',
    'Darkness',
    'Light',
    'Darkness',
    'Light',
    'Darkness',
};

-- Inverse of Resonation (name -> id); None is not a real skillchain.
local nameToResonation = {};
for name, id in pairs(Resonation) do
    if name ~= 'None' then
        nameToResonation[name] = id;
    end
end

-- Elements each burst can hit. Light and Darkness use a single orb.
local resonationBurstElements = {
    [Resonation.Transfixion]   = { 'light' },
    [Resonation.Compression]   = { 'dark' },
    [Resonation.Liquefaction]  = { 'fire' },
    [Resonation.Scission]      = { 'earth' },
    [Resonation.Reverberation] = { 'water' },
    [Resonation.Detonation]    = { 'wind' },
    [Resonation.Induration]    = { 'ice' },
    [Resonation.Impaction]     = { 'lightning' },
    [Resonation.Gravitation]   = { 'dark', 'earth' },
    [Resonation.Distortion]    = { 'water', 'ice' },
    [Resonation.Fusion]        = { 'light', 'fire' },
    [Resonation.Fragmentation] = { 'wind', 'lightning' },
    [Resonation.Light]         = { 'light' },
    [Resonation.Light2]        = { 'light' },
    [Resonation.Darkness]      = { 'dark' },
    [Resonation.Darkness2]     = { 'dark' },
    [Resonation.Radiance]      = { 'light' },
    [Resonation.Umbra]         = { 'dark' },
};

local possibleSkillchains = {
    { Resonation.Light, Resonation.Light, Resonation.Light },
    { Resonation.Light, Resonation.Fragmentation, Resonation.Fusion },
    { Resonation.Light, Resonation.Fusion, Resonation.Fragmentation },
    { Resonation.Darkness, Resonation.Darkness, Resonation.Darkness },
    { Resonation.Darkness, Resonation.Distortion, Resonation.Gravitation },
    { Resonation.Darkness, Resonation.Gravitation, Resonation.Distortion },
    { Resonation.Fusion, Resonation.Liquefaction, Resonation.Impaction },
    { Resonation.Fusion, Resonation.Distortion, Resonation.Fusion },
    { Resonation.Gravitation, Resonation.Detonation, Resonation.Compression },
    { Resonation.Gravitation, Resonation.Fusion, Resonation.Gravitation },
    { Resonation.Distortion, Resonation.Transfixion, Resonation.Scission },
    { Resonation.Distortion, Resonation.Fragmentation, Resonation.Distortion },
    { Resonation.Fragmentation, Resonation.Induration, Resonation.Reverberation },
    { Resonation.Fragmentation, Resonation.Gravitation, Resonation.Fragmentation },
    { Resonation.Liquefaction, Resonation.Impaction, Resonation.Liquefaction },
    { Resonation.Liquefaction, Resonation.Scission, Resonation.Liquefaction },
    { Resonation.Scission, Resonation.Liquefaction, Resonation.Scission },
    { Resonation.Scission, Resonation.Detonation, Resonation.Scission },
    { Resonation.Reverberation, Resonation.Scission, Resonation.Reverberation },
    { Resonation.Reverberation, Resonation.Transfixion, Resonation.Reverberation },
    { Resonation.Detonation, Resonation.Scission, Resonation.Detonation },
    { Resonation.Detonation, Resonation.Impaction, Resonation.Detonation },
    { Resonation.Detonation, Resonation.Compression, Resonation.Detonation },
    { Resonation.Induration, Resonation.Reverberation, Resonation.Induration },
    { Resonation.Impaction, Resonation.Reverberation, Resonation.Impaction },
    { Resonation.Impaction, Resonation.Induration, Resonation.Impaction },
    { Resonation.Transfixion, Resonation.Compression, Resonation.Transfixion },
    { Resonation.Compression, Resonation.Transfixion, Resonation.Compression },
    { Resonation.Compression, Resonation.Induration, Resonation.Compression }
};

local skillchainMessageIds = {
    [288] = Resonation.Light,
    [289] = Resonation.Darkness,
    [290] = Resonation.Gravitation,
    [291] = Resonation.Fragmentation,
    [292] = Resonation.Distortion,
    [293] = Resonation.Fusion,
    [294] = Resonation.Compression,
    [295] = Resonation.Liquefaction,
    [296] = Resonation.Induration,
    [297] = Resonation.Reverberation,
    [298] = Resonation.Transfixion,
    [299] = Resonation.Scission,
    [300] = Resonation.Detonation,
    [301] = Resonation.Impaction,
    [385] = Resonation.Light,
    [386] = Resonation.Darkness,
    [387] = Resonation.Gravitation,
    [388] = Resonation.Fragmentation,
    [389] = Resonation.Distortion,
    [390] = Resonation.Fusion,
    [391] = Resonation.Compression,
    [392] = Resonation.Liquefaction,
    [393] = Resonation.Induration,
    [394] = Resonation.Reverberation,
    [395] = Resonation.Transfixion,
    [396] = Resonation.Scission,
    [397] = Resonation.Detonation,
    [398] = Resonation.Impaction,
    [767] = Resonation.Radiance,
    [768] = Resonation.Umbra,
    [769] = Resonation.Radiance,
    [770] = Resonation.Umbra
};

local hitMessageIds = {
    [2] = true,
    [103] = true,
    [110] = true,
    [185] = true,
    [187] = true,
    [238] = true,
    [317] = true,
    [802] = true,
};

local petDamageMessageIds = {
    [110] = true,
    [317] = true,
};

local TRACK_TYPES = {
    [3] = true,
    [4] = true,
    [6] = true,
    [11] = true,
    [13] = true,
    [14] = true,
};

local BUFF_AZURE_LORE = 163;
local BUFF_CHAIN_AFFINITY = 164;
local BUFF_IMMANENCE = 470;
local CHAIN_BUFF_DURATION = {
    [BUFF_AZURE_LORE] = 30,
    [BUFF_CHAIN_AFFINITY] = 30,
    [BUFF_IMMANENCE] = 60,
};

local resonationMap = {};
local chainBuffs = {};
local attrCache = {};
local nameIndex = {};

local function CopySkillTables(src)
    local dst = {};
    for cat, entries in pairs(src) do
        if type(entries) == 'table' then
            local copy = {};
            for id, skill in pairs(entries) do
                copy[id] = skill;
            end
            dst[cat] = copy;
        else
            dst[cat] = entries;
        end
    end
    return dst;
end

local function CloneSkill(skill)
    if type(skill) ~= 'table' then
        return skill;
    end
    local copy = {};
    for k, v in pairs(skill) do
        copy[k] = v;
    end
    return copy;
end

local function ResolveSkillRef(base, skill, depth)
    if type(skill) ~= 'table' then
        return skill;
    end
    if skill.ref == nil or skill.id == nil then
        return skill;
    end
    if depth > 8 then
        return nil;
    end
    local cat = base[skill.ref];
    local target = cat and cat[skill.id];
    return ResolveSkillRef(base, target, depth + 1);
end

local function ApplyHorizonOverlay(base, overlay)
    for cat, entries in pairs(overlay) do
        if type(entries) == 'table' then
            if base[cat] == nil then
                base[cat] = {};
            end
            for id, skill in pairs(entries) do
                if skill == false then
                    base[cat][id] = nil;
                elseif type(skill) == 'table' and skill.ref ~= nil then
                    base[cat][id] = skill;
                elseif type(skill) == 'table' and skill.skillchain ~= nil and skill.en == nil then
                    local existing = base[cat][id];
                    if type(existing) == 'table' then
                        local merged = CloneSkill(existing);
                        merged.skillchain = skill.skillchain;
                        base[cat][id] = merged;
                    else
                        base[cat][id] = CloneSkill(skill);
                    end
                else
                    base[cat][id] = skill;
                end
            end
        end
    end

    for _, entries in pairs(base) do
        if type(entries) == 'table' then
            for id, skill in pairs(entries) do
                if type(skill) == 'table' and skill.ref ~= nil then
                    local resolved = ResolveSkillRef(base, skill, 0);
                    entries[id] = resolved and CloneSkill(resolved) or nil;
                end
            end
        end
    end
    return base;
end

local skills = CopySkillTables(require('modules.hotbar.database.skillchain_retail'));
if HzLimitedMode then
    skills = ApplyHorizonOverlay(skills, require('modules.hotbar.database.skillchain_horizon'));
end

local function NormalizeName(name)
    if not name then return nil; end
    return string.lower(tostring(name)):gsub('[^%w]', '');
end

local function IndexCategory(catKey, cat)
    if not cat then return; end
    local bucket = {};
    nameIndex[catKey] = bucket;
    for id, skill in pairs(cat) do
        if type(skill) == 'table' and skill.en then
            bucket[NormalizeName(skill.en)] = skill;
            skill._id = id;
            skill._cat = catKey;
        end
    end
end

IndexCategory(3, skills[3]);
IndexCategory(4, skills[4]);
IndexCategory(11, skills[11]);
IndexCategory(13, skills[13]);
IndexCategory(14, skills[14]);
IndexCategory('pup', skills.pup);
IndexCategory('immanence', skills.immanence);

local function GetAttrIds(skill)
    if not skill then return nil; end
    local cached = attrCache[skill];
    if cached then return cached; end
    local ids = {};
    for _, name in ipairs(skill.skillchain or {}) do
        local id = nameToResonation[name];
        if id then
            ids[#ids + 1] = id;
        end
    end
    if #ids == 0 then
        attrCache[skill] = nil;
        return nil;
    end
    attrCache[skill] = ids;
    return ids;
end

local function FindSkillById(actionType, skillId)
    if not skillId or skillId == 0 then return nil; end

    local skill = skills[actionType] and skills[actionType][skillId];
    if skill then return skill; end

    if actionType == 11 then
        return (skills[11] and skills[11][skillId]) or (skills.pup and skills.pup[skillId]);
    end
    if actionType == 6 or actionType == 14 then
        return skills[14] and skills[14][skillId];
    end
    if actionType == 13 then
        return skills[13] and skills[13][skillId];
    end
    return nil;
end

local function FindSkillByName(catKey, actionName)
    local bucket = nameIndex[catKey];
    if not bucket then return nil; end
    return bucket[NormalizeName(actionName)];
end

local function FindSlotSkillUncached(actionType, actionName)
    if not actionName then return nil; end
    if actionType == 'ws' then
        if type(actionName) == 'number' then
            return skills[3] and skills[3][actionName];
        end
        return FindSkillByName(3, actionName);
    end
    if actionType == 'ma' then
        local spellId = type(actionName) == 'number' and actionName or actiondb.GetSpellId(actionName);
        if spellId and skills[4] then
            return skills[4][spellId];
        end
        return FindSkillByName(4, actionName);
    end
    if actionType == 'pet' then
        return FindSkillByName(13, actionName)
            or FindSkillByName(11, actionName)
            or FindSkillByName('pup', actionName);
    end
    if actionType == 'ja' then
        return FindSkillByName(14, actionName);
    end
    return nil;
end

-- Memoize (actionType, actionName) -> skill. Skill tables are static after load,
-- so this avoids the per-slot per-frame string normalization/lookups. NO_SKILL is a
-- negative sentinel so misses are cached too.
local slotSkillCache = {};
local NO_SKILL = {};
local function FindSlotSkill(actionType, actionName)
    if not actionName then return nil; end
    local bucket = slotSkillCache[actionType];
    if not bucket then
        bucket = {};
        slotSkillCache[actionType] = bucket;
    end
    local cached = bucket[actionName];
    if cached ~= nil then
        return cached ~= NO_SKILL and cached or nil;
    end
    local skill = FindSlotSkillUncached(actionType, actionName);
    bucket[actionName] = skill or NO_SKILL;
    return skill;
end

local function tableContains(tbl, val)
    if not tbl then return false; end
    for _, v in ipairs(tbl) do
        if v == val then return true; end
    end
    return false;
end

local function GetIndexFromId(id)
    local entMgr = AshitaCore:GetMemoryManager():GetEntity();
    if not entMgr then return 0; end

    if bit.band(id, 0x1000000) ~= 0 then
        local index = bit.band(id, 0xFFF);
        if index >= 0x900 then
            index = index - 0x100;
        end
        if index < 0x900 and entMgr:GetServerId(index) == id then
            return index;
        end
    end

    for i = 1, 0x8FF do
        if entMgr:GetServerId(i) == id then
            return i;
        end
    end

    return 0;
end

-- Per-frame snapshot of the player's buff array. SlotPassesGates can query buffs
-- for many spell slots each frame while a skillchain window is open; rebuilding
-- the lookup once per frame avoids a 32-iteration scan per slot per buff id.
local buffSnapshot = {};
local buffSnapshotClock = -1;

local function RefreshBuffSnapshot()
    local now = os.clock();
    if now == buffSnapshotClock then return; end
    buffSnapshotClock = now;
    for k in pairs(buffSnapshot) do buffSnapshot[k] = nil; end
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player or not player.GetBuffs then return; end
    local buffs = player:GetBuffs();
    if not buffs then return; end
    for i = 0, 31 do
        local id = buffs[i];
        if id and id ~= 0 and id ~= 255 then
            buffSnapshot[id] = true;
        end
    end
end

local function PlayerHasBuff(buffId)
    RefreshBuffSnapshot();
    return buffSnapshot[buffId] == true;
end

local function GetLocalServerId()
    local party = AshitaCore:GetMemoryManager():GetParty();
    if not party then return nil; end
    return party:GetMemberServerId(0);
end

local function ActorHasSpellChainBuff(actorId)
    local now = os.clock();
    local t = chainBuffs[actorId];
    if t then
        for _, exp in pairs(t) do
            if exp > now then
                return true;
            end
        end
    end
    if actorId == GetLocalServerId() then
        return PlayerHasBuff(BUFF_AZURE_LORE)
            or PlayerHasBuff(BUFF_CHAIN_AFFINITY)
            or PlayerHasBuff(BUFF_IMMANENCE);
    end
    return false;
end

local bluSetCache = nil;
local bluSetCacheTime = 0;
local bluOffset = nil;
local bluOffsetTried = false;

local function GetBluSetIds()
    local now = os.clock();
    if bluSetCache and (now - bluSetCacheTime) < 0.25 then
        return bluSetCache;
    end

    local set = {};
    local ok = pcall(function()
        if not bluOffsetTried then
            bluOffsetTried = true;
            local found = ashita.memory.find('FFXiMain.dll', 0, 'C1E1032BC8B0018D????????????B9????????F3A55F5E5B', 10, 0);
            if found and found ~= 0 then
                bluOffset = ffi.cast('uint32_t*', found);
            end
        end
        if not bluOffset then return; end
        local ptr = ashita.memory.read_uint32(AshitaCore:GetPointerManager():Get('inventory'));
        if ptr == 0 then return; end
        ptr = ashita.memory.read_uint32(ptr);
        if ptr == 0 then return; end
        local bytes = ashita.memory.read_array((ptr + bluOffset[0]) + 0x04, 0x14);
        if not bytes then return; end
        for i = 1, #bytes do
            local v = bytes[i];
            if v and v ~= 0 then
                set[v + 512] = true;
            end
        end
    end);
    if not ok then
        set = {};
    end

    bluSetCache = set;
    bluSetCacheTime = now;
    return set;
end

local function IsBluSpellSet(spellId)
    if not spellId or spellId < 512 then
        return true;
    end
    return GetBluSetIds()[spellId] == true;
end

local petpalette;
local petregistry;
local function GetPetPalette()
    if not petpalette then
        petpalette = require('modules.hotbar.petpalette');
    end
    return petpalette;
end
local function GetPetRegistry()
    if not petregistry then
        petregistry = require('modules.hotbar.petregistry');
    end
    return petregistry;
end

-- Per-frame cache of the current pet's normalized ready-move name set, so a bar
-- full of pet slots doesn't re-fetch + re-normalize the move list per slot.
local petMovesClock = -1;
local petMovesName = nil;
local petMovesSet = nil;

local function GetCurrentPetReadyMoveSet()
    local now = os.clock();
    if now ~= petMovesClock then
        petMovesClock = now;
        petMovesName = GetPetPalette().GetCurrentPetEntityName();
        petMovesSet = nil;
        local moves = petMovesName and GetPetRegistry().GetReadyMovesForPet(petMovesName);
        if moves then
            petMovesSet = {};
            for _, move in ipairs(moves) do
                petMovesSet[NormalizeName(move.name)] = true;
            end
        end
    end
    return petMovesSet, petMovesName;
end

local function SlotPassesGates(skill, actionType)
    if not skill then return false; end

    local cfg = gConfig and gConfig.hotbarGlobal or {};

    if actionType == 'ma' then
        local spellId = skill._id;
        if spellId and spellId >= 512 and not IsBluSpellSet(spellId) then
            return false;
        end
        if cfg.skillchainRequireAbility then
            if spellId and spellId >= 512 then
                if not (PlayerHasBuff(BUFF_AZURE_LORE) or PlayerHasBuff(BUFF_CHAIN_AFFINITY)) then
                    return false;
                end
            else
                if not PlayerHasBuff(BUFF_IMMANENCE) then
                    return false;
                end
            end
        end
    end

    if actionType == 'pet' then
        if skill.avatar then
            local highlightAll = cfg.skillchainHighlightAllBloodPacts == true
                or (cfg.skillchainHighlightAllBloodPacts == nil and cfg.skillchainRequireSummonedAvatar == false);
            if not highlightAll then
                local petName = GetPetPalette().GetCurrentPetEntityName();
                if not petName or string.lower(petName) ~= string.lower(skill.avatar) then
                    return false;
                end
            end
        elseif skill._cat == 11 then
            local moveSet = GetCurrentPetReadyMoveSet();
            if not moveSet or not moveSet[NormalizeName(skill.en)] then
                return false;
            end
        end
    end

    return true;
end

-- Target's open resonation, or nil. Callers pass the entity index from
-- targetLib.GetTargets(); do not reverse-map ServerId on the draw path.
local function ResolveOpenResonation(targetIndex)
    if not targetIndex or targetIndex == 0 then
        return nil;
    end

    local resonation = resonationMap[targetIndex];
    if not resonation then
        return nil;
    end

    local now = os.clock();
    if now > resonation.WindowClose then
        resonationMap[targetIndex] = nil;
        return nil;
    end
    if now < resonation.WindowOpen then
        return nil;
    end

    return resonation;
end

local function MatchCloser(wsAttributes, resonation)
    if not wsAttributes or not resonation then return nil; end

    for _, sc in ipairs(possibleSkillchains) do
        local result, opening, closing = sc[1], sc[2], sc[3];
        if tableContains(resonation.Attributes, opening) then
            if tableContains(wsAttributes, closing) then
                return resonationNames[result];
            end
        end
    end
    return nil;
end

function M.DebugDumpState()
    print('[XIUI SC] Current resonation state:');
    local now = os.clock();
    local found = false;
    for idx, state in pairs(resonationMap or {}) do
        found = true;
        local attrs = {};
        for _, a in ipairs(state.Attributes or {}) do
            table.insert(attrs, tostring(a));
        end
        local windowStatus = (now >= state.WindowOpen and now <= state.WindowClose) and 'OPEN' or 'closed';
        print(string.format('  Target %d: attrs={%s}, %s', idx, table.concat(attrs, ','), windowStatus));
    end
    if not found then
        print('  (no targets tracked)');
    end
end

function M.GetSkillchainForSlot(targetIndex, actionType, actionName)
    if not actionType then return nil; end
    -- Legacy: GetSkillchainForSlot(target, wsIdOrName)
    if actionName == nil then
        actionName = actionType;
        actionType = 'ws';
    end

    local resonation = ResolveOpenResonation(targetIndex);
    if not resonation then return nil; end

    local skill = FindSlotSkill(actionType, actionName);
    local attrs = GetAttrIds(skill);
    if not attrs then return nil; end
    if not SlotPassesGates(skill, actionType) then return nil; end

    return MatchCloser(attrs, resonation);
end

function M.HandleActionPacket(actionPacket)
    if not actionPacket then return; end
    local actionType = actionPacket.Type;
    if not TRACK_TYPES[actionType] then return; end

    local skillId = actionPacket.Param;
    if type(skillId) == 'number' then
        skillId = bit.band(skillId, 0xFFFF);
    end

    if actionType == 6 and skillId and CHAIN_BUFF_DURATION[skillId] then
        local actor = actionPacket.UserId;
        chainBuffs[actor] = chainBuffs[actor] or {};
        chainBuffs[actor][skillId] = os.clock() + CHAIN_BUFF_DURATION[skillId];
    end

    for _, target in ipairs(actionPacket.Targets or {}) do
        local targetIndex = GetIndexFromId(target.Id);
        if targetIndex ~= 0 then
            for _, action in ipairs(target.Actions or {}) do
                local lookupType = actionType;
                if petDamageMessageIds[action.Message] then
                    lookupType = 13;
                end
                local skill = FindSkillById(lookupType, skillId);
                if not skill then
                    skill = FindSkillById(actionType, skillId);
                end
                local attributes = GetAttrIds(skill);

                local skillchain = nil;
                if action.AdditionalEffect then
                    skillchain = skillchainMessageIds[action.AdditionalEffect.Message];
                end

                if skillchain == Resonation.None then
                    resonationMap[targetIndex] = nil;

                elseif skillchain then
                    local resonation = resonationMap[targetIndex];
                    local now = os.clock();

                    if resonation and (now + 1) > resonation.WindowOpen and (now - 1) < resonation.WindowClose then
                        resonation.Depth = resonation.Depth + 1;
                        if skillchain == Resonation.Light and tableContains(resonation.Attributes, Resonation.Light) then
                            resonation.Attributes = { Resonation.Light2 };
                        elseif skillchain == Resonation.Darkness and tableContains(resonation.Attributes, Resonation.Darkness) then
                            resonation.Attributes = { Resonation.Darkness2 };
                        else
                            resonation.Attributes = { skillchain };
                        end
                        resonation.WindowOpen = now + 3.5;
                        resonation.WindowClose = now + (9.8 - resonation.Depth);
                    else
                        resonation = {
                            Depth = 1,
                            Attributes = { skillchain },
                            WindowOpen = now + 3.5,
                            WindowClose = now + 8.8,
                        };
                        resonationMap[targetIndex] = resonation;
                    end

                    resonation.BurstElements = resonationBurstElements[resonation.Attributes[1]];
                    resonation.BurstStart = now;

                elseif attributes and (hitMessageIds[action.Message] or action.Message == 529) then
                    local allowOpener = true;
                    if actionType == 4 then
                        allowOpener = ActorHasSpellChainBuff(actionPacket.UserId);
                    elseif actionType == 11 and HzLimitedMode then
                        -- Horizon: NPC/PUP only. BST ready IDs are not in the Horizon table.
                        allowOpener = skill and (skill._cat == 11 or skill._cat == 'pup');
                    end

                    if allowOpener then
                        local now = os.clock();
                        resonationMap[targetIndex] = {
                            Depth = 0,
                            Attributes = attributes,
                            WindowOpen = now,
                            WindowClose = now + 10.0,
                        };
                    end
                elseif hitMessageIds[action.Message] and actionType == 3 then
                    resonationMap[targetIndex] = nil;
                end

                if skill and actionType == 4 then
                    local actor = actionPacket.UserId;
                    if chainBuffs[actor] then
                        chainBuffs[actor][BUFF_CHAIN_AFFINITY] = nil;
                        chainBuffs[actor][BUFF_IMMANENCE] = nil;
                    end
                end
            end
        end
    end
end

function M.ClearState()
    resonationMap = {};
    chainBuffs = {};
    bluSetCache = nil;
end

function M.ClearTargetState(targetServerId)
    if targetServerId then
        local targetIndex = GetIndexFromId(targetServerId);
        if targetIndex ~= 0 then
            resonationMap[targetIndex] = nil;
        end
    end
end

function M.IsWindowOpen()
    local now = os.clock();
    for _, state in pairs(resonationMap) do
        if state.WindowOpen and now >= state.WindowOpen and now <= state.WindowClose then
            return true;
        end
    end
    return false;
end

-- Active magic burst window, newest chain wins when several mobs are chained.
-- Returns element name list, seconds remaining, total window length -- or nil.
function M.GetActiveBurst()
    local now = os.clock();
    local newest, newestStart = nil, -1;

    for _, state in pairs(resonationMap) do
        if state.BurstElements and state.BurstStart and now < state.WindowClose
            and state.BurstStart > newestStart then
            newest, newestStart = state, state.BurstStart;
        end
    end

    if not newest then
        return nil;
    end

    return newest.BurstElements, newest.WindowClose - now, newest.WindowClose - newest.BurstStart;
end

local lastClockRead = 0;
local cachedAnimOffset = 0;

function M.GetAnimationOffset()
    local now = os.clock();
    if now ~= lastClockRead then
        lastClockRead = now;
        cachedAnimOffset = (now * 50) % 16;
    end
    return cachedAnimOffset;
end

function M.GetSkillchainNames()
    return {
        'Compression', 'Darkness', 'Detonation', 'Distortion',
        'Fragmentation', 'Fusion', 'Gravitation', 'Impaction',
        'Induration', 'Light', 'Liquefaction', 'Reverberation',
        'Scission', 'Transfixion',
    };
end

function M.GetWSAttributesByName(wsName)
    local skill = FindSkillByName(3, wsName);
    if skill then
        return GetAttrIds(skill), skill._id;
    end
    return nil, nil;
end

return M;
