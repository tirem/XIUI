-- Mob information from bundled LandSandBoat and Phoenix YAML snapshots.

require('common');

local mobdata = {};
local providers = {
    lsb = require('modules.mobinfo.providers.lsb'),
    phoenix = require('modules.mobinfo.providers.phoenix'),
    horizon = require('modules.mobinfo.providers.horizon'),
};
local files = require('modules.mobinfo.providers.files');

-- Current zone data
local currentZoneId = 0;
local currentProvider;
local zoneData = {
    Names = {},    -- Lookup by mob name
    Indices = {}   -- Spawn-specific information by entity index
};

local function GetProviderKey()
    local key = gConfig and gConfig.mobInfoDataSource or 'lsb';
    return providers[key] and key or 'lsb';
end

mobdata.GetProvider = function()
    return providers[GetProviderKey()];
end

local function MergeInfo(base, override)
    local result = {};
    if base then
        for key, value in pairs(base) do result[key] = value; end
    end
    for key, value in pairs(override) do result[key] = value; end
    return result;
end

local function ApplyHorizonOverlay(overlay)
    if not overlay then return; end
    local byName = {};
    for index, info in pairs(overlay.Indices) do
        local base = zoneData.Indices[index] or zoneData.Names[info.Name];
        local merged = MergeInfo(base, info);
        zoneData.Indices[index] = merged;
        byName[info.Name] = merged;
    end
    for name, info in pairs(overlay.Names) do
        local base = zoneData.Names[name] or zoneData.Names[info.Name] or byName[info.Name];
        local merged = MergeInfo(base, info);
        zoneData.Names[name] = merged;
        -- Abbreviated keys ('D.Club') and full Name fields both need to resolve.
        if info.Name and info.Name ~= name then
            zoneData.Names[info.Name] = merged;
        end
    end
end

--[[
    Load mob data for a specific zone
    @param zoneId: The zone ID to load data for
    @return boolean: true if data was loaded successfully
]]
mobdata.LoadZone = function(zoneId)
    zoneId = tonumber(zoneId) or 0;
    local provider = GetProviderKey();
    if zoneId == currentZoneId and provider == currentProvider then
        return zoneData.Names ~= nil and next(zoneData.Names) ~= nil;
    end

    -- Clear existing data
    zoneData.Names = {};
    zoneData.Indices = {};
    currentZoneId = zoneId;
    currentProvider = provider;

    -- Zone 0 is invalid
    if zoneId <= 0 then
        return false;
    end

    local result = providers[provider].LoadZone(zoneId);
    if result then
        zoneData = result;
        if provider == 'horizon' then ApplyHorizonOverlay(files.LoadZone('horizon', zoneId)); end
    elseif provider == 'horizon' then
        -- Custom Horizon-only zone: no LSB snapshot, overlay is the data.
        local overlay = files.LoadZone('horizon', zoneId);
        if overlay then zoneData = overlay; end
    end

    return zoneData.Names ~= nil and next(zoneData.Names) ~= nil;
end

--[[
    Get mob information by entity index (preferred) or name
    @param mobName: The name of the mob to look up (used as fallback)
    @param entityIndex: Optional entity index for more accurate lookup (different spawn points may have different jobs)
    @return table or nil: Mob data table or nil if not found

    Mob data table fields:
    - Name: string - Mob name
    - MinLevel / MaxLevel: number - Level range
    - Job: number - Job ID (0 for standard mobs)
    - Aggro: boolean - Whether mob is aggressive
    - Link: boolean - Whether mob links with others
    - Sight: boolean - Detects by sight
    - TrueSight / TrueSound: boolean - Detects through Invisible / Sneak
    - Sound: boolean - Detects by sound
    - Scent: boolean - Tracks targets by scent
    - Magic: boolean - Detects magic casting
    - JA: boolean - Detects job abilities
    - Blood: boolean - Detects low HP targets
    - Immunities: number - Bitfield of status immunities
    - Modifiers: table - Damage type modifiers (multipliers)
        - Fire, Ice, Wind, Earth, Lightning, Water, Light, Dark
        - Slashing, Piercing, H2H, Impact
    - ElementRanks: table - Elemental resistance ranks, separate from damage taken

    Note: Many mobs (like Om'aern) have different jobs depending on spawn point.
    The Indices table contains spawn-specific data, while Names has generic fallback data.
]]
mobdata.GetMobInfo = function(mobName, entityIndex)
    -- Profiles can change the provider without a zone packet.
    mobdata.LoadZone(currentZoneId);
    if mobName == nil then
        return nil;
    end

    -- Try index lookup first for spawn-specific data (more accurate job info)
    if entityIndex ~= nil and zoneData.Indices ~= nil then
        local indexData = zoneData.Indices[entityIndex];
        if indexData ~= nil then
            return indexData;
        end
    end

    -- Fall back to name lookup
    if zoneData.Names == nil then
        return nil;
    end
    return zoneData.Names[mobName] or zoneData.Names[string.gsub(mobName, '_', ' ')];
end

--[[
    Get the current zone ID
    @return number: The currently loaded zone ID
]]
mobdata.GetCurrentZoneId = function()
    return currentZoneId;
end

--[[
    Check if mob data is available for the current zone
    @return boolean: true if data is loaded
]]
mobdata.HasData = function()
    return zoneData.Names ~= nil and next(zoneData.Names) ~= nil;
end

--[[
    Handle zone packet (0x00A) to load new zone data
    @param e: The packet event data
]]
mobdata.HandleZonePacket = function(e)
    if e == nil or e.data == nil then
        return;
    end

    -- Extract zone ID from packet at offset 0x30 (0x31 with 1-based indexing)
    local zoneId = struct.unpack('H', e.data, 0x30 + 1);

    -- Load data for the new zone
    mobdata.LoadZone(zoneId);
end

--[[
    Clear all loaded data (called on unload)
]]
mobdata.Cleanup = function()
    zoneData.Names = {};
    zoneData.Indices = {};
    currentZoneId = 0;
    currentProvider = nil;
end

-- Force-reload the current zone after a source setting changes.
mobdata.ReloadCurrentZone = function()
    local zoneId = currentZoneId;
    if zoneId == 0 then
        local party = AshitaCore:GetMemoryManager():GetParty();
        if party then
            zoneId = party:GetMemberZone(0) or 0;
        end
    end
    currentZoneId = 0;
    if zoneId and zoneId > 0 then
        mobdata.LoadZone(zoneId);
    end
end

--[[
    Get detection methods as a table of booleans
    @param mobInfo: The mob data table from GetMobInfo
    @return table: Detection methods that are active
]]
mobdata.GetDetectionMethods = function(mobInfo)
    if mobInfo == nil then
        return {};
    end

    local methods = {};

    if mobInfo.Sight then methods.sight = true; end
    if mobInfo.TrueSight then methods.truesight = true; end
    if mobInfo.Sound then methods.sound = true; end
    if mobInfo.TrueSound then methods.truesound = true; end
    if mobInfo.Scent then methods.scent = true; end
    if mobInfo.Magic then methods.magic = true; end
    if mobInfo.JA then methods.ja = true; end
    if mobInfo.Blood then methods.blood = true; end

    return methods;
end

--[[
    Get level display string
    @param mobInfo: The mob data table from GetMobInfo
    @return string: Level display (e.g., "75" or "75-80")
]]
mobdata.GetLevelString = function(mobInfo)
    if mobInfo == nil then
        return '';
    end

    local minLevel = mobInfo.MinLevel or mobInfo.Level;
    local maxLevel = mobInfo.MaxLevel or mobInfo.Level;

    if minLevel == nil and maxLevel == nil then
        return '?';
    end

    if minLevel == maxLevel or maxLevel == nil then
        return tostring(minLevel or '?');
    end

    return tostring(minLevel) .. '-' .. tostring(maxLevel);
end

--[[
    Get job abbreviation string
    @param mobInfo: The mob data table from GetMobInfo
    @return string or nil: Job abbreviation (WAR, MNK, etc.) or nil if no job
]]
mobdata.GetJobString = function(mobInfo)
    if mobInfo == nil or mobInfo.Job == nil or mobInfo.Job == 0 then
        return nil;
    end
    return AshitaCore:GetResourceManager():GetString("jobs.names_abbr", mobInfo.Job);
end

--[[
    Get resistances (modifiers < 1.0)
    @param mobInfo: The mob data table from GetMobInfo
    @return table: Table of {type = modifier} for resistances
]]
mobdata.GetResistances = function(mobInfo)
    if mobInfo == nil or mobInfo.Modifiers == nil then
        return {};
    end

    local resistances = {};
    for damageType, modifier in pairs(mobInfo.Modifiers) do
        if modifier < 1.0 then
            resistances[damageType] = modifier;
        end
    end
    return resistances;
end

--[[
    Get weaknesses (modifiers > 1.0)
    @param mobInfo: The mob data table from GetMobInfo
    @return table: Table of {type = modifier} for weaknesses
]]
mobdata.GetWeaknesses = function(mobInfo)
    if mobInfo == nil or mobInfo.Modifiers == nil then
        return {};
    end

    local weaknesses = {};
    for damageType, modifier in pairs(mobInfo.Modifiers) do
        if modifier > 1.0 then
            weaknesses[damageType] = modifier;
        end
    end
    return weaknesses;
end

-- LSB scripts/combat/basic/magic_hit_rate.lua: resistance rank -> magic evasion multiplier.
local rankMagicEvasion = {
    [-3] = 0.95, [-2] = 0.96019, [-1] = 0.98, [0] = 1,
    [1] = 1.023, [2] = 1.049, [3] = 1.0905, [4] = 1.126, [5] = 1.2075, [6] = 1.3475,
    [7] = 1.70065, [8] = 2.141, [9] = 2.2, [10] = 2.275, [11] = 2.35,
};

-- Magic evasion change for an elemental resistance rank, as a rounded percent.
mobdata.GetRankMagicEvasionPercent = function(rank)
    local multiplier = rankMagicEvasion[math.max(-3, math.min(11, rank))];
    return math.floor((multiplier - 1) * 100 + 0.5);
end

-- LSB data/enums/immunity.yaml flags. Sleep types have separate bits.
mobdata.ImmunityFlags = {
    Gravity = 0x02,
    Bind = 0x04,
    Stun = 0x08,
    Silence = 0x10,
    Paralyze = 0x20,
    Blind = 0x40,
    Slow = 0x80,
    Poison = 0x100,
    Elegy = 0x200,
    Requiem = 0x400,
    LightSleep = 0x800,
    DarkSleep = 0x1000,
    Petrify = 0x10000,
};

--[[
    Get immunities as a table of booleans
    @param mobInfo: The mob data table from GetMobInfo
    @return table: Table of {immunityName = true} for each immunity
]]
mobdata.GetImmunities = function(mobInfo)
    if mobInfo == nil or mobInfo.Immunities == nil or mobInfo.Immunities == 0 then
        return {};
    end

    local immunities = {};
    for name, flag in pairs(mobdata.ImmunityFlags) do
        if bit.band(mobInfo.Immunities, flag) ~= 0 then
            immunities[name] = true;
        end
    end
    return immunities;
end

return mobdata;
