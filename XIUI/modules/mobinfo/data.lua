--[[
    Mob Database Module for XIUI
    Loads zone-specific mob data from MobDB submodule (ThornyFFXI/mobdb)
    Data format is compatible with MobDB addon
    MobDB is licensed under MIT License
    https://github.com/ThornyFFXI/mobdb
]]

require('common');

local mobdata = {};

-- Current zone data
local currentZoneId = 0;
local zoneData = {
    Names = {},    -- Lookup by mob name
    Indices = {}   -- Lookup by mob index (not used but kept for compatibility)
};

-- Get the base path for mob data files
local function GetMobDataPath()
    local path = string.gsub(addon.path, '\\\\', '\\');
    return path .. '/submodules/mobdb/addons/mobdb/data/';
end

--[[
    Load mob data for a specific zone
    @param zoneId: The zone ID to load data for
    @return boolean: true if data was loaded successfully
]]
mobdata.LoadZone = function(zoneId)
    -- Skip if already loaded or invalid zone
    if zoneId == currentZoneId then
        return zoneData.Names ~= nil and next(zoneData.Names) ~= nil;
    end

    -- Clear existing data
    zoneData.Names = {};
    zoneData.Indices = {};
    currentZoneId = zoneId;

    -- Zone 0 is invalid
    if zoneId == 0 then
        return false;
    end

    -- Construct file path
    local filePath = GetMobDataPath() .. tostring(zoneId) .. '.lua';

    -- Check if file exists
    local file = io.open(filePath, 'r');
    if file == nil then
        -- No data file for this zone - this is normal for many zones
        return false;
    end
    file:close();

    -- Load the data file
    local loadFunc, loadErr = loadfile(filePath);
    if loadFunc == nil then
        print('[XIUI] Error loading mob data for zone ' .. tostring(zoneId) .. ': ' .. tostring(loadErr));
        return false;
    end

    -- Execute the loaded function to get the data
    local success, result = pcall(loadFunc);
    if not success then
        print('[XIUI] Error executing mob data for zone ' .. tostring(zoneId) .. ': ' .. tostring(result));
        return false;
    end

    -- Store the data
    if result and result.Names then
        zoneData.Names = result.Names;
    end
    if result and result.Indices then
        zoneData.Indices = result.Indices;
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
    - TrueSight: boolean - Detects by true sight (ignores sneak/invis)
    - Sound: boolean - Detects by sound
    - Scent: boolean - Detects by scent (low HP aggro)
    - Magic: boolean - Detects magic casting
    - JA: boolean - Detects job abilities
    - Blood: boolean - Aggro based on blood (undead)
    - Immunities: number - Bitfield of status immunities
    - Modifiers: table - Damage type modifiers (multipliers)
        - Fire, Ice, Wind, Earth, Lightning, Water, Light, Dark
        - Slashing, Piercing, H2H, Impact

    Note: Many mobs (like Om'aern) have different jobs depending on spawn point.
    The Indices table contains spawn-specific data, while Names has generic fallback data.
]]
mobdata.GetMobInfo = function(mobName, entityIndex)
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
    return zoneData.Names[mobName];
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

--[[
    Immunity bit flags (matching MobDB format)
]]
mobdata.ImmunityFlags = {
    Sleep = 0x01,
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
