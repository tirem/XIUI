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

-- Job IDs that have MP (aspirable via /aspir).
-- WHM=3, BLM=4, RDM=5, PLD=7, DRK=8, SMN=15, SCH=20, GEO=21
local ASPIRABLE_JOBS = {
    [3]=true, [4]=true, [5]=true, [7]=true,
    [8]=true, [15]=true, [20]=true, [21]=true,
};

-- Plain-text substrings matched case-insensitively against the mob name.
-- Covers the vast majority of each aspirable family by name convention.
local ASPIRABLE_NAME_PATTERNS = {
    -- ── Beetles ──────────────────────────────────────────────────────────────
    'beetle',
    -- ── Buffalo ──────────────────────────────────────────────────────────────
    'buffalo',
    -- ── Cockatrice ───────────────────────────────────────────────────────────
    'cockatrice',
    ' beak',    -- Axe Beak, Tabar Beak, Waraxe Beak, Unlucky Beak
                -- NOTE: leading space required — Yagudo "Spinebeak" and Goblin
                -- "Eaglebeak"/"Pimplebeak" contain "beak" without a preceding space.
    'ziz',      -- Ziz, Molted Ziz, Zizzy Zillah, Attack Ziz
    -- ── Colibri ──────────────────────────────────────────────────────────────
    'colibri',
    -- ── Crabs ────────────────────────────────────────────────────────────────
    'crab',
    'snipper', 'clipper',  -- crab-family mobs without "crab" in name
    -- NOTE: 'cutter' removed — it matched Tonberry Cutter (NIN, non-aspirable).
    -- Specific crab mobs with "cutter" in name are in the explicit table below.
    'thickshell', 'ironshell',
    -- ── Diremites ────────────────────────────────────────────────────────────
    'diremite',
    'hoarmite', -- Abyssea-Uleguerand variant without "diremite"
    -- ── Elementals ───────────────────────────────────────────────────────────
    'elemental',
    -- ── Evil Weapons (Animated Weapons) ──────────────────────────────────────
    'weapon',
    'boggart',      -- Inner Horutoto / Jugner / Meriphataud weapon-type
    'poltergeist',  -- Konschtat / La Theine / Tahrongi weapon-type
    -- ── Flans ────────────────────────────────────────────────────────────────
    'flan',
    'pudding',  -- Black Pudding, Ebony Pudding, Pitchy Pudding, Princess Pudding…
    'custard',  -- Nyzul Isle flan NMs (Anise Custard, Caraway Custard…)
    -- ── Ahriman ──────────────────────────────────────────────────────────────
    -- Ahriman are aspirable. Most carry "Eye" (singular) or "Ahriman" in the name.
    -- The ones that don't (Fachan, Gawper, Doom Lens, Angra Mainyu, etc.) are in
    -- the explicit table below.
    'ahriman',  -- Ahriman, Arch Ahriman, Enhanced Ahriman, Vanguard's Ahriman…
    'eye',      -- Floating Eye, Bat Eye, Evil Eye, Morbid Eye, Menacing Eye,
                -- Vanguard Eye, Deep Eye, Gloom Eye, Shadow Eye, Rogue Eye,
                -- Blurry Eye, Shadoweye, All-Seeing Onyx Eye, Rearguard Eye…
                -- (also catches all Hecteyes "* Eyes" names, which is correct)
    -- ── Hecteyes ─────────────────────────────────────────────────────────────
    'hecteyes',
    -- 'eyes' (plural) still useful as a direct compound match for Myriadeyes,
    -- Blubber Eyes, Thousand Eyes, Million Eyes, etc.
    'eyes',
    'gazer',    -- Gazer, Mindgazer
    -- ── Hippogryphs ──────────────────────────────────────────────────────────
    'hippogryph',
    -- ── Magic Pots ───────────────────────────────────────────────────────────
    -- Most carry "magic" or "pot/jar/urn/millstone/jug/flagon/carafe" in the name
    'magic pot', 'magic jar', 'magic urn',
    'magic millstone', 'magic jug', 'magic flagon',
    'droma',          -- Droma family (Fei'Yin / Garlaige) without "magic" prefix
    'clockwork pod',  -- Fei'Yin / Garlaige variant
    'aura pot',       -- Pso'Xja variant
    -- ── Rafflesia ────────────────────────────────────────────────────────────
    'rafflesia',
    -- ── Roc ──────────────────────────────────────────────────────────────────
    -- NOTE: bare 'roc' removed — it is a substring of "rock", "ferocious",
    -- "bedrock", "ferrocrab", etc. causing many false positives (the original
    -- "Ferocious Pugil" report was caused by this). Use ' roc' (space-prefixed)
    -- to match "* Roc" multi-word names; standalone "Roc" NM is in explicit table.
    ' roc',     -- Nightmare Roc, Lofty Roc, Embattled Roc, Ill Roc, Zu…
                -- NOTE: does NOT match standalone "Roc" (no leading space) → see explicit
    'titanis',  -- Titanis Dax/Jax/Max/Xax (BCNM rocs)
    'suparna',  -- Suparna / Suparna Fledgling (Mission rocs)
    -- ── Soulflayers ──────────────────────────────────────────────────────────
    -- NOTE: bare 'flayer' removed — it matched Goblin "Fleshflayer Killakriq" (BST).
    'soulflayer',   -- Soulflayer, Nepionic Soulflayer, Locus Soulflayer, Vanguard Soulflayer…
    'psycheflayer', -- Psycheflayer variants
    'pneumaflayer', -- Pneumaflayer variants
    -- ── Wanderers (Promyvion family) ─────────────────────────────────────────
    'wanderer',
    -- ── Worms ────────────────────────────────────────────────────────────────
    'worm',
    ' eater',   -- Stone Eater, Rock Eater, Flesh Eater, Sand Eater… (worm sub-family)
                -- NOTE: leading space required — "greater" contains the substring "eater"
    'grub',     -- Witchetty Grub, Giant Grub
    -- NOTE: 'digger' removed — it matched Goblin Digger / Goblin Welldigger (THF/BST,
    -- non-aspirable). "Sand Digger" and "Kuftal Digger" are in the explicit table.
    -- ── Wamoura ──────────────────────────────────────────────────────────────
    'wamoura',
    -- ── Phuabo ───────────────────────────────────────────────────────────────
    'phuabo',
    -- ── Yovra ────────────────────────────────────────────────────────────────
    'yovra',
    -- ── Wyverns ──────────────────────────────────────────────────────────────
    'wyvern',
    'drake',    -- Firedrake, Flamedrake, Pyrodrake, Ignidrake, Blazedrake…
    'vouivre',  -- Vouivre, Kindred's Vouivre, Andras's Vouivre, Caim's Vouivre
    'guivre',   -- Guivre (Kuftal / Ruhotz)
};

-- Explicit mob names (exact, lowercased) for aspirable mobs whose names don't
-- match any pattern above. Keyed as a set for O(1) lookup.
-- Sourced from FFXI community data on aspirable monster families.
local ASPIRABLE_EXPLICIT = {
    -- ── Beetles ──────────────────────────────────────────────────────────────
    ['starmite']            = true,  -- Toraimarai Canal (beetle-type)
    ['starborer']           = true,  -- Toraimarai Canal (beetle-type)
    ['boll weevil']         = true,  -- Jugner Forest (S) NM
    ['diamond daig']        = true,  -- Quicksand Caves NM
    ['donnergugi']          = true,  -- Eastern Altepa Desert NM
    ['lumber jack']         = true,  -- Batallia Downs NM
    ['panzer percival']     = true,  -- Jugner Forest NM
    ['kettenkaefer']        = true,  -- Quest / Limbus NM
    ['bisan']               = true,  -- BCNM beetle
    ['pilwiz']              = true,  -- BCNM beetle
    ['gawky gawain']        = true,  -- Fields of Valor NM

    -- ── Cockatrice (compound "beak" names — not caught by ' beak') ────────────
    ['gorebeak']            = true,  -- cockatrice-type NM (compound name, no space before beak)

    -- ── Cockatrice ───────────────────────────────────────────────────────────
    ['chonchon']            = true,  -- Meriphataud Mountains NM
    ['deadly dodo']         = true,  -- Sauromugue Champaign NM
    ['killer jonny']        = true,  -- Cape Teriggan NM
    ['pelican']             = true,  -- Kuftal Tunnel NM (cockatrice family)
    ['skewer sam']          = true,  -- Garlaige Citadel NM
    ['zebra zachary']       = true,  -- Salvage NM
    ['giant moa']           = true,  -- BCNM cockatrice

    -- ── Crabs (cutter-type names — removed from patterns to avoid Tonberry Cutter) ─
    ['rock cutter']         = true,  -- Kuftal Tunnel crab-type
    ['stone cutter']        = true,  -- crab-type variant
    ['cutter']              = true,  -- standalone crab name (some areas)

    -- ── Worms ────────────────────────────────────────────────────────────────
    ['sand digger']         = true,  -- worm family (removed 'digger' pattern)
    ['kuftal digger']       = true,  -- worm family
    ['amphisbaena']         = true,  -- Gusgen Mines worm-type
    ['rockmill']            = true,  -- Gusgen Mines worm-type
    ['maze maker']          = true,  -- Maze of Shakhrami worm-type
    ['ectozoon']            = true,  -- Abyssea-Uleguerand worm-type
    ['entozoon']            = true,  -- Abyssea-Attohwa worm-type
    ['bedrock barry']       = true,  -- North Gustaberg NM
    ['bigmouth billy']      = true,  -- East Ronfaure NM
    ['megamaw mikey']       = true,  -- Abyssea-La Theine NM
    ['olgoi-khorkhoi']      = true,  -- North Gustaberg (S) NM
    ['trembler tabitha']    = true,  -- Maze of Shakhrami NM
    ['anemic aloysius']     = true,  -- Abyssea-Uleguerand NM
    ['pallid percy']        = true,  -- Abyssea-Attohwa NM

    -- ── Flans ────────────────────────────────────────────────────────────────
    ['licorice']            = true,  -- Abyssea-Konschtat NM flan
    ['dextrose']            = true,  -- Halvung NM flan
    ['flammeri']            = true,  -- Halvung NM flan
    ['guimauve']            = true,  -- Abyssea-Konschtat NM flan
    ['roly-poly']           = true,  -- Voidwatch Jeuno T2 flan
    ['treasure gobbler']    = true,  -- MMM Appropriation Team flan
    ['mokkuralfi']          = true,  -- Einherjar Wing II flan
    ['liquified einherjar'] = true,  -- Einherjar Wing III flan

    -- ── Hecteyes ─────────────────────────────────────────────────────────────
    ['taisai']              = true,  -- Ranguemont Pass hecteyes
    ['taisaijin']           = true,  -- Ranguemont Pass NM hecteyes
    ['dodomeki']            = true,  -- Ifrit's Cauldron hecteyes
    ['beholder']            = true,  -- Abyssea-Tahrongi hecteyes
    ['shoggoth']            = true,  -- Pashhow / North Gustaberg hecteyes
    ['argus']               = true,  -- Maze of Shakhrami NM
    ['hakutaku']            = true,  -- Den of Rancor NM
    ['hyakume']             = true,  -- Ranguemont Pass NM
    ['ophanim']             = true,  -- Abyssea-Tahrongi NM
    ['amun']                = true,  -- Abyssea-Attohwa NM
    ['waldgeist']           = true,  -- Einherjar Wing II hecteyes
    ['galgalim']            = true,  -- Quest NM hecteyes
    ['mokumokuren']         = true,  -- Quest NM hecteyes

    -- ── Hippogryphs ──────────────────────────────────────────────────────────
    ['alkonost']            = true,  -- Abyssea-Konschtat NM
    ['boroka']              = true,  -- Riverne-B01 NM
    ['heliodromos']         = true,  -- Riverne-A01 NM
    ['imdugud']             = true,  -- Riverne-B01 NM
    ['kotan-kor kamuy']     = true,  -- Grauberg (S) NM
    ['hippocentaur']        = true,  -- ANNM hippogryph
    ['hippalectryon']       = true,  -- MMM hippogryph

    -- ── Magic Pots ───────────────────────────────────────────────────────────
    ['hover tank']          = true,  -- Temple of Uggalepih
    ['sprinkler']           = true,  -- Ru'Aun Gardens
    ['dustbuster']          = true,  -- Ve'Lugannon Palace
    ['sentient carafe']     = true,  -- Fei'Yin
    ['sinister seidel']     = true,  -- Abyssea-Grauberg NM
    ['hovering hotpot']     = true,  -- Garlaige Citadel NM
    ['mind hoarder']        = true,  -- Fei'Yin NM
    ['nightmare vase']      = true,  -- Ro'Maeve NM
    ['olla grande']         = true,  -- Shrine of Ru'Avitau NM
    ['olla media']          = true,  -- Shrine of Ru'Avitau NM
    ['olla pequena']        = true,  -- Shrine of Ru'Avitau NM
    ['rogue receptacle']    = true,  -- Ro'Maeve NM
    ['sacrificial goblet']  = true,  -- Temple of Uggalepih NM
    ['steam cleaner']       = true,  -- Ve'Lugannon Palace NM
    ['jackpot']             = true,  -- Fields of Valor NM
    ['eldhrimnir']          = true,  -- Quest NM pot
    ['illusory pot']        = true,  -- Quest NM pot
    ['ancient vessel']      = true,  -- Mission NM pot
    ['fired urn']           = true,  -- Mission NM pot
    ['apollyon cleaner']    = true,  -- Limbus NM
    ['temenos cleaner']     = true,  -- Limbus NM

    -- ── Rafflesia ────────────────────────────────────────────────────────────
    ['belladonna']          = true,  -- West Sarutabaruta (S) NM
    ['kirtimukha']          = true,  -- Fort Karugo-Narugo (S) NM
    ['raskovnik']           = true,  -- Abyssea-Konschtat NM
    ['pixiebane']           = true,  -- Quest NM rafflesia
    ['amaranth']            = true,  -- ANNM rafflesia
    ['siltim']              = true,  -- MMM rafflesia

    -- ── Roc (standalone or non-"* Roc" names not caught by ' roc' pattern) ────
    ['roc']                 = true,  -- Sauromugue Champaign NM (bare 3-char name)
    ['zu']                  = true,  -- Rolanberry Fields / Sauromugue roc-family
    ['thunderbird']         = true,  -- Misareaux Coast roc-family

    -- ── Roc ──────────────────────────────────────────────────────────────────
    ['diatryma']            = true,  -- Eastern Altepa / Misareaux roc-type
    ['phorusrhacos']        = true,  -- Western Altepa roc-type
    ['peryton']             = true,  -- Valley of Sorrows / Nyzul roc-type
    ['abraxas']             = true,  -- Lufaise Meadows roc-type
    ['gastornis']           = true,  -- Abyssea-Altepa roc-type
    ['stryx']               = true,  -- Marjami Ravine roc-type
    ['bennu']               = true,  -- Abyssea-Altepa NM
    ['kreutzet']            = true,  -- Cape Teriggan NM
    ['okyupete']            = true,  -- Misareaux Coast NM
    ['ouzelum']             = true,  -- Abyssea-Altepa NM
    ['picolaton']           = true,  -- Western Altepa NM
    ['quetzalli']           = true,  -- Abyssea-Tahrongi NM
    ['simurgh']             = true,  -- Rolanberry Fields NM
    ['suzaku']              = true,  -- Ru'Aun Gardens NM
    ['ubume']               = true,  -- Quest NM roc
    ['bialozar']            = true,  -- Limbus NM roc
    ['thiazi']              = true,  -- Limbus NM roc
    ['zhu que']             = true,  -- Assists Qilin (roc-type)

    -- ── Soulflayers ──────────────────────────────────────────────────────────
    ['amnaf']               = true,  -- Mission NM soulflayer
    ['balrahn']             = true,  -- Einherjar Wing II soulflayer
    ['demented jalaawa']    = true,  -- Salvage NM soulflayer

    -- ── Wanderers (Promyvion family) ─────────────────────────────────────────
    ['deviator']            = true,  -- Promyvion-Vahzl NM
    ['meanderer']           = true,  -- Abyssea-Konschtat NM
    ['stray']               = true,  -- Assists Memory Receptacle

    -- ── Wyverns ──────────────────────────────────────────────────────────────
    ['ajattara']            = true,  -- Grauberg (S) / Campaign wyvern-type
    ['ladon']               = true,  -- Kuftal Tunnel wyvern-type
    ['skoffin']             = true,  -- Bhaflau Thickets wyvern-type
    ['aiatar']              = true,  -- Riverne-A01 NM
    ['balaur']              = true,  -- Abyssea-Konschtat NM
    ['bune']                = true,  -- Gustav Tunnel NM
    ['minaruja']            = true,  -- Abyssea-Grauberg NM
    ['scitalis']            = true,  -- Grauberg (S) NM
    ['seiryu']              = true,  -- Ru'Aun Gardens NM
    ['ungur']               = true,  -- Gustav Tunnel NM
    ['veri selen']          = true,  -- Abyssea-Uleguerand NM
    ['tatzlwurm']           = true,  -- Mission NM wyvern
    ['gorynich']            = true,  -- Limbus NM wyvern
    ['centycore']           = true,  -- MMM wyvern
    ['haietlik']            = true,  -- MMM wyvern
    ['terrormonger']        = true,  -- MMM wyvern
    ['cyranuce m cutauleon'] = true, -- Mission NM wyvern

    -- ── Wamoura ──────────────────────────────────────────────────────────────
    ['achamoth']            = true,  -- Halvung NM wamoura
    ['ignamoth']            = true,  -- Mount Zhayolm NM wamoura
    ['itzpapalotl']         = true,  -- Abyssea-Attohwa NM wamoura
    ['achamoth nympha']     = true,  -- Assists Achamoth

    -- ── Diremites ────────────────────────────────────────────────────────────
    ['awahondo']            = true,  -- Abyssea-Uleguerand NM
    ['gyre-carlin']         = true,  -- Pso'Xja NM
    ['resheph']             = true,  -- Abyssea-Uleguerand NM
    ['pasuk']               = true,  -- BCNM diremite
    ['gnyan']               = true,  -- MMM diremite

    -- ── Phuabo ───────────────────────────────────────────────────────────────
    ['jailer of hope']      = true,  -- Al'Taieu NM phuabo
    ['tristitia']           = true,  -- Abyssea-Misareaux NM phuabo
    ['warder of hope']      = true,  -- Escha-Ru'Aun NM phuabo

    -- ── Yovra ────────────────────────────────────────────────────────────────
    ['jailer of love']      = true,  -- Al'Taieu NM yovra
    ['ovni']                = true,  -- Abyssea-La Theine yovra-type

    -- ── Evil Weapon NMs without "weapon" ─────────────────────────────────────
    ['blighting brand']     = true,  -- Sauromugue Champaign NM
    ['brigandish blade']    = true,  -- Ve'Lugannon Palace NM
    ['eldritch edge']       = true,  -- Rolanberry Fields NM
    ['juggler hecatomb']    = true,  -- Gusgen Mines NM
    ['prankster maverix']   = true,  -- Batallia Downs NM
    ['trickster kinetix']   = true,  -- Qufim Island NM
    ['flying spear']        = true,  -- SE Apollyon Limbus NM
    ['evil armory']         = true,  -- SE Apollyon Limbus NM
    ['malefic fencer']      = true,  -- Fields of Valor NM

    -- ── Ahriman (no "eye" or "ahriman" in name) ───────────────────────────────
    -- The 'eye' and 'ahriman' patterns in ASPIRABLE_NAME_PATTERNS cover the bulk
    -- of the family. These are the NMs whose names don't match either.
    ['fachan']              = true,  -- Riverne Site #A01 NM
    ['gawper']              = true,  -- Misareaux Coast NM
    ['ogler']               = true,  -- Lufaise Meadows NM
    ['smolenkos']           = true,  -- Riverne Site #B01 NM
    ['scowlenkos']          = true,  -- Riverne Site #B01 NM
    ['doom lens']           = true,  -- Promyvion NM
    ['deadly iris']         = true,  -- Promyvion NM
    ['likho']               = true,  -- Abyssea-Uleguerand NM
    ['arimaspi']            = true,  -- Abyssea-Grauberg NM
    ['angra mainyu']        = true,  -- Abyssea-Empyreal Paradox NM (apex Ahriman)
    ['osschaart']           = true,  -- Balga's Dais BCNM NM
    ['margygr']             = true,  -- Einherjar Wing III NM
    ['tartalo']             = true,  -- Quest NM (San d'Oria area)
    ['agas']                = true,  -- Quest NM
    ['pyracmon']            = true,  -- Einherjar/Special Event NM
    ['searcher']            = true,  -- Mission Ahriman
    ['seeker']              = true,  -- Mission Ahriman
    ['spotter']             = true,  -- Mission Ahriman
    ['watcher']             = true,  -- MMM Ahriman
};

--[[
    Determine if a mob is aspirable (has MP, i.e. /aspir will drain it).
    Three signals are checked, any one is sufficient:
      1. MobDB Job field — most accurate when database data exists.
      2. Exact name lookup — O(1) hash check for documented edge-case NMs.
      3. Substring pattern — covers entire families by naming convention.
    @param mobInfo  table|nil  MobDB entry from GetMobInfo (may be nil)
    @param mobName  string|nil Raw entity name (fallback when mobInfo is nil)
    @return boolean
]]
mobdata.IsAspirable = function(mobInfo, mobName)
    -- Signal 1: Job (most reliable when MobDB data is present)
    if mobInfo ~= nil and mobInfo.Job ~= nil and ASPIRABLE_JOBS[mobInfo.Job] then
        return true;
    end

    local name = (mobInfo and mobInfo.Name) or mobName;
    if name == nil then return false; end
    local nameLower = string.lower(name);

    -- Signal 2: Exact name match (O(1))
    if ASPIRABLE_EXPLICIT[nameLower] then
        return true;
    end

    -- Signal 3: Substring pattern (covers whole families)
    for _, pattern in ipairs(ASPIRABLE_NAME_PATTERNS) do
        if nameLower:find(pattern, 1, true) then
            return true;
        end
    end

    return false;
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
