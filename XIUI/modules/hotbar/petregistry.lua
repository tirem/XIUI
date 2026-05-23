--[[
* XIUI Hotbar - Pet Registry Module
* Centralized pet name-to-key mapping for pet-aware hotbar palettes
]]--

local M = {};

-- MP cost + SMN level: `horizon_bloodpacts.lua`. XIUI-only labels/icons: `horizon_bloodpacts_xiui.lua`.
local horizonBloodPacts = require('modules.hotbar.database.horizon_bloodpacts');
local horizonBloodPactsXiui = require('modules.hotbar.database.horizon_bloodpacts_xiui');
local universalTwoHour = require('modules.hotbar.universal_two_hour');

-- Ready pet command when horizon_abilities lists it with pet=true (HorizonXI includes Ready for jug gameplay).
local function horizonDefinesBstReadyPetCommand()
    local ha = require('modules.hotbar.database.horizon_abilities');
    local row = ha['Ready'];
    return row ~= nil and row.pet == true;
end

-- Jug-family Ready moves: only when Ready exists as a pet command and jug_moves is not explicitly false.
local function horizonDefinesBstJugReadyMoves()
    local ha = require('modules.hotbar.database.horizon_abilities');
    local row = ha['Ready'];
    return row ~= nil and row.pet == true and row.jug_moves ~= false;
end

M.IsBstJugReadyMovesEnabled = horizonDefinesBstJugReadyMoves;

-- ============================================
-- Job Constants
-- ============================================

M.JOB_SMN = 15;
M.JOB_BST = 9;
M.JOB_DRG = 14;
M.JOB_PUP = 18;

-- ============================================
-- Pet Type Constants
-- ============================================

M.PET_TYPE_AVATAR = 'avatar';
M.PET_TYPE_SPIRIT = 'spirit';
M.PET_TYPE_WYVERN = 'wyvern';
M.PET_TYPE_AUTOMATON = 'automaton';
M.PET_TYPE_JUG = 'jug';
M.PET_TYPE_CHARM = 'charm';

-- `petpalette:*` keys omitted from the Edit Full Palette Pets picker (no practical pet-entity hotbar to bind for these avatars in Horizon).
M.PETBAR_EXCLUDED_STORAGE_KEYS = {
    ['avatar:odin'] = true,
    ['avatar:alexander'] = true,
    ['avatar:atomos'] = true,
};

-- ============================================
-- Avatar Mapping (petName -> storageKey)
-- ============================================

M.avatars = {
    ['Carbuncle'] = 'carbuncle',
    ['Ifrit'] = 'ifrit',
    ['Shiva'] = 'shiva',
    ['Garuda'] = 'garuda',
    ['Titan'] = 'titan',
    ['Ramuh'] = 'ramuh',
    ['Leviathan'] = 'leviathan',
    ['Fenrir'] = 'fenrir',
    ['Diabolos'] = 'diabolos',
    ['Atomos'] = 'atomos',
    ['Odin'] = 'odin',
    ['Alexander'] = 'alexander',
    ['Cait Sith'] = 'caitsith',
    ['Siren'] = 'siren',
};

-- ============================================
-- Spirit Mapping (petName -> storageKey)
-- ============================================

M.spirits = {
    ['Fire Spirit'] = 'firespirit',
    ['Ice Spirit'] = 'icespirit',
    ['Air Spirit'] = 'airspirit',
    ['Earth Spirit'] = 'earthspirit',
    ['Thunder Spirit'] = 'thunderspirit',
    ['Water Spirit'] = 'waterspirit',
    ['Light Spirit'] = 'lightspirit',
    ['Dark Spirit'] = 'darkspirit',
};

-- ============================================
-- Jug Pet Names (for BST)
-- Note: Jug pets share a common "jug" palette (too many for individual palettes)
-- ============================================

M.jugPets = {
    -- Low level (23-75)
    'Homunculus', 'HareFamiliar', 'KeenearedSteffi', 'CrabFamiliar',
    'CourierCarrie', 'SheepFamiliar', 'LullabyMelodia', 'TigerFamiliar',
    'SaberSiravarde', 'MayflyFamiliar', 'ShellbusterOrob', 'LizardFamiliar',
    'ColdbloodComo', 'EftFamiliar', 'AmbusherAllie', 'FunguarFamiliar',
    'FlytrapFamiliar', 'VoraciousAudrey', 'FlowerpotBill', 'FlowerpotBen',
    'AntlionFamiliar', 'ChopsueyChucky', 'BeetleFamiliar', 'PanzerGalahad',
    'MiteFamiliar', 'LifedrinkerLars', 'TurbidToloi', 'AmigoSabotender',
    -- High level (76-119)
    'DapperMac', 'CraftyClyvonne', 'NurseryNazuna', 'LuckyLulush',
    'FlowerpotMerle', 'DipperYuly', 'DiscreetLouise', 'FatsoFargann',
    'PrestoJulio', 'AudaciousAnna', 'MailbusterCetas', 'FaithfulFalcorr',
    'SwiftSieghard', 'BloodclawShasra', 'BugeyedBroncha', 'GorefangHobs',
    'GooeyGerard', 'CrudeRaphie', 'AmiableRoche', 'SweetCaroline',
    'HeadbreakerKen', 'AnklebiterJedd', 'CursedAnnabelle', 'BrainyWaluis',
    'RedolentCandi', 'AlluringHoney', 'CaringKiyomaro', 'VivaciousVickie',
    'SuspiciousAlice', 'SurgingStorm', 'SubmergedIyo', 'WarlikePatrick',
    'RhymingShizuna', 'BlackbeardRandy', 'ThreestarLynn', 'HurlerPercival',
    'AcuexFamiliar', 'FluffyBredo', 'SlimeFamiliar', 'SultryPatrice',
    'GenerousArthur', 'DaringRoland', 'AttentiveIbuki', 'SwoopingZhivago',
    'ChoralLeera', 'ColibriFamiliar', 'HippogrypFamiliar', 'SunburstMalfik',
    'AgedAngus', 'HeraldHenry', 'BraveHeroGlenn', 'PorterCrabFamiliar',
    'JovialEdwin', 'ScissorlegXerin',
    -- Legacy/alternate names (kept for backwards compatibility)
    'BouncingBertha', 'SharpwitHermes', 'FleetReinhard', 'DroopyDortwin',
    'PonderingPeter', 'MosquitoFamilia', 'Left-HandedYoko',
};

-- Build lookup table for jug pets
M.jugPetLookup = {};
for _, petName in ipairs(M.jugPets) do
    M.jugPetLookup[petName] = true;
end

-- ============================================
-- Job Pet Categories
-- Maps job IDs to valid pet categories for that job
-- ============================================

M.jobPetCategories = {
    [M.JOB_SMN] = { M.PET_TYPE_AVATAR, M.PET_TYPE_SPIRIT },
    [M.JOB_DRG] = { M.PET_TYPE_WYVERN },
    [M.JOB_PUP] = { M.PET_TYPE_AUTOMATON },
    [M.JOB_BST] = { M.PET_TYPE_JUG, M.PET_TYPE_CHARM },
};

-- ============================================
-- Display Names for Pet Types
-- ============================================

M.petTypeDisplayNames = {
    [M.PET_TYPE_AVATAR] = 'Avatar',
    [M.PET_TYPE_SPIRIT] = 'Spirit',
    [M.PET_TYPE_WYVERN] = 'Wyvern',
    [M.PET_TYPE_AUTOMATON] = 'Automaton',
    [M.PET_TYPE_JUG] = 'Jug Pet',
    [M.PET_TYPE_CHARM] = 'Charmed',
};

-- ============================================
-- Functions
-- ============================================

-- Check if a job is a pet job
function M.IsPetJob(jobId)
    return M.jobPetCategories[jobId] ~= nil;
end

-- Get pet categories for a job
function M.GetPetCategories(jobId)
    return M.jobPetCategories[jobId] or {};
end

-- Check if a pet name is a jug pet
function M.IsJugPet(petName)
    if petName == nil then return false; end
    return M.jugPetLookup[petName] == true;
end

-- Check if a pet name is an avatar
function M.IsAvatar(petName)
    if petName == nil then return false; end
    return M.avatars[petName] ~= nil;
end

-- Check if a pet name is a spirit
function M.IsSpirit(petName)
    if petName == nil then return false; end
    return M.spirits[petName] ~= nil;
end

-- Get the pet type from a pet name and job
-- Returns: petType (string) or nil if unknown
function M.GetPetType(petName, jobId)
    if petName == nil then return nil; end

    -- Check by name first
    if M.avatars[petName] then
        return M.PET_TYPE_AVATAR;
    elseif M.spirits[petName] then
        return M.PET_TYPE_SPIRIT;
    elseif M.jugPetLookup[petName] then
        return M.PET_TYPE_JUG;
    elseif petName == 'Wyvern' or (jobId == M.JOB_DRG) then
        -- Wyvern can be renamed, so check job too
        return M.PET_TYPE_WYVERN;
    elseif jobId == M.JOB_PUP then
        return M.PET_TYPE_AUTOMATON;
    elseif jobId == M.JOB_BST then
        -- Unknown BST pet = charmed
        return M.PET_TYPE_CHARM;
    end

    return nil;
end

-- Get the storage key suffix for a pet
-- Returns: string like "avatar:ifrit", "wyvern", "jug", "jug:rabbit", "automaton", etc.
-- For SMN avatars/spirits and BST jug families, returns per-family keys when known
-- For other jobs, returns per-type keys
function M.GetPetKey(petName, jobId)
    if petName == nil then return nil; end

    local petType = M.GetPetType(petName, jobId);
    if not petType then return nil; end

    -- SMN: Per-avatar/spirit palettes
    if petType == M.PET_TYPE_AVATAR then
        local avatarKey = M.avatars[petName];
        if avatarKey then
            return M.PET_TYPE_AVATAR .. ':' .. avatarKey;
        end
    elseif petType == M.PET_TYPE_SPIRIT then
        local spiritKey = M.spirits[petName];
        if spiritKey then
            return M.PET_TYPE_SPIRIT .. ':' .. spiritKey;
        end
    elseif petType == M.PET_TYPE_JUG then
        local mk = M.GetJugPetPaletteMovesKeyForEntity(petName);
        if mk then
            return M.PET_TYPE_JUG .. ':' .. M.JugPaletteSlugFromMovesKey(mk);
        end
        return M.PET_TYPE_JUG;
    end

    -- Other jobs: Per-type palettes (wyvern, automaton, charm)
    return petType;
end

-- Get display name for a pet key
-- Input: "avatar:ifrit", "wyvern", etc.
-- Output: "Ifrit", "Wyvern", etc.
function M.GetDisplayNameForKey(petKey)
    if not petKey then return 'Base'; end

    -- Check for avatar/spirit format
    local petType, petId = petKey:match('^([^:]+):(.+)$');
    if petType and petId then
        if petType == M.PET_TYPE_AVATAR then
            -- Find avatar name
            for name, key in pairs(M.avatars) do
                if key == petId then return name; end
            end
        elseif petType == M.PET_TYPE_SPIRIT then
            -- Find spirit name
            for name, key in pairs(M.spirits) do
                if key == petId then return name; end
            end
        elseif petType == M.PET_TYPE_JUG then
            for _, row in ipairs(M.bstJugReadyFamilyPicker) do
                if row.movesKey:lower() == petId:lower() then
                    return row.name;
                end
            end
            local slugLabel = M.bstJugPaletteSlugLabels and M.bstJugPaletteSlugLabels[petId:lower()];
            if slugLabel then
                return slugLabel;
            end
            return 'Jug (' .. petId .. ')';
        end
    end

    -- Check for simple type keys
    local displayName = M.petTypeDisplayNames[petKey];
    if displayName then return displayName; end

    return petKey;
end

-- Get all available pet keys for a job (for cycling)
-- Returns a table of pet keys that can be used for that job
function M.GetAvailablePetKeys(jobId)
    local keys = {};

    if jobId == M.JOB_SMN then
        -- All avatars
        for _, key in pairs(M.avatars) do
            table.insert(keys, M.PET_TYPE_AVATAR .. ':' .. key);
        end
        -- All spirits
        for _, key in pairs(M.spirits) do
            table.insert(keys, M.PET_TYPE_SPIRIT .. ':' .. key);
        end
    elseif jobId == M.JOB_DRG then
        table.insert(keys, M.PET_TYPE_WYVERN);
    elseif jobId == M.JOB_PUP then
        table.insert(keys, M.PET_TYPE_AUTOMATON);
    elseif jobId == M.JOB_BST then
        table.insert(keys, M.PET_TYPE_JUG);
        local seenSlug = {};
        for _, row in ipairs(M.bstJugReadyFamilyPicker) do
            local slug = row.movesKey:lower();
            if not seenSlug[slug] then
                seenSlug[slug] = true;
                table.insert(keys, M.PET_TYPE_JUG .. ':' .. slug);
            end
        end
        local function addJugSlugFromMovesKey(mk)
            if not mk or mk == '' then
                return;
            end
            local slug = mk:lower();
            if not seenSlug[slug] then
                seenSlug[slug] = true;
                table.insert(keys, M.PET_TYPE_JUG .. ':' .. slug);
            end
        end
        for _, mk in pairs(M.jugPetFamilies) do
            addJugSlugFromMovesKey(mk);
        end
        for _, mk in pairs(M.jugPetPaletteMovesKeyOverrides) do
            addJugSlugFromMovesKey(mk);
        end
        table.insert(keys, M.PET_TYPE_CHARM);
    end

    return keys;
end

-- Get ordered list of avatar names (for dropdowns, macro editor, Edit Full Palette Pets, etc.)
function M.GetAvatarList()
    return {
        'Carbuncle',
        'Ifrit',
        'Titan',
        'Leviathan',
        'Garuda',
        'Shiva',
        'Ramuh',
        'Fenrir',
        'Diabolos',
        'Alexander',
        'Odin',
        'Cait Sith',
        'Atomos',
        'Siren',
    };
end

-- Get ordered list of spirit names
function M.GetSpiritList()
    return {
        'Fire Spirit', 'Ice Spirit', 'Air Spirit', 'Earth Spirit',
        'Thunder Spirit', 'Water Spirit', 'Light Spirit', 'Dark Spirit',
    };
end

-- Display order for SMN pet keys (matches GetAvatarList then GetSpiritList). Used to align pickers and Edit Palette Pets.
local smnPetKeyOrderWeight;
function M.GetSmnPetKeyOrderWeight(petKey)
    if not smnPetKeyOrderWeight then
        smnPetKeyOrderWeight = {};
        local i = 1;
        for _, name in ipairs(M.GetAvatarList()) do
            local id = M.avatars[name];
            if id then
                smnPetKeyOrderWeight[M.PET_TYPE_AVATAR .. ':' .. id] = i;
                i = i + 1;
            end
        end
        for _, name in ipairs(M.GetSpiritList()) do
            local id = M.spirits[name];
            if id then
                smnPetKeyOrderWeight[M.PET_TYPE_SPIRIT .. ':' .. id] = i;
                i = i + 1;
            end
        end
    end
    return smnPetKeyOrderWeight[petKey] or 9999;
end

-- Get combined list of all summons (avatars + spirits)
function M.GetAllSummonsList()
    local list = {};
    -- Avatars first
    for _, avatar in ipairs(M.GetAvatarList()) do
        table.insert(list, { name = avatar, category = 'avatar' });
    end
    -- Then spirits
    for _, spirit in ipairs(M.GetSpiritList()) do
        table.insert(list, { name = spirit, category = 'spirit' });
    end
    return list;
end

-- Get the pet key for a summon name (avatar or spirit)
function M.GetPetKeyForSummon(summonName)
    -- Check avatars
    if M.avatars[summonName] then
        return 'avatar:' .. M.avatars[summonName];
    end
    -- Check spirits
    if M.spirits[summonName] then
        return 'spirit:' .. M.spirits[summonName];
    end
    return nil;
end

-- True if `key` is a valid pet subtype string used in slot storage (avatar:ifrit, wyvern, jug, jug:rabbit, etc.)
function M.IsValidPetKey(key)
    if not key or key == '' then
        return false;
    end
    if key == M.PET_TYPE_WYVERN or key == M.PET_TYPE_AUTOMATON
        or key == M.PET_TYPE_JUG or key == M.PET_TYPE_CHARM then
        return true;
    end
    local pt, pid = key:match('^([^:]+):(.+)$');
    if not pt or not pid then
        return false;
    end
    if pt == M.PET_TYPE_AVATAR then
        for _, shortId in pairs(M.avatars) do
            if shortId == pid then
                return true;
            end
        end
    elseif pt == M.PET_TYPE_SPIRIT then
        for _, shortId in pairs(M.spirits) do
            if shortId == pid then
                return true;
            end
        end
    elseif pt == M.PET_TYPE_JUG then
        return M.MovesKeyFromBstMacroPaletteSlug(pid) ~= nil;
    end
    return false;
end

-- ============================================
-- Pet Commands Data
-- ============================================

-- SMN pet commands (not blood pacts)
M.smnPetCommands = {
    { name = 'Assault', category = 'Command', level = 1 },
    { name = 'Release', category = 'Command', level = 1 },
    { name = 'Retreat', category = 'Command', level = 1 },
};

-- SMN Blood Pacts - Rage (offensive). Retail-style layout: Shared Ifrit block, then per-avatar sections.
M.bloodPactsRage = {
    -- Shared
    { name = 'Punch', avatars = {'Ifrit'} },
    { name = 'Fire II', avatars = {'Ifrit'} },
    { name = 'Burning Strike', avatars = {'Ifrit'} },
    { name = 'Double Punch', avatars = {'Ifrit'} },
    { name = 'Flaming Crush', avatars = {'Ifrit'} },
    { name = 'Meteor Strike', avatars = {'Ifrit'} },
    { name = 'Conflag Strike', avatars = {'Ifrit'} },
    { name = 'Fire IV', avatars = {'Ifrit'} },
    { name = 'Inferno', avatars = {'Ifrit'} },
    -- Shiva
    { name = 'Axe Kick', avatars = {'Shiva'} },
    { name = 'Blizzard II', avatars = {'Shiva'} },
    { name = 'Double Slap', avatars = {'Shiva'} },
    { name = 'Blizzard IV', avatars = {'Shiva'} },
    { name = 'Rush', avatars = {'Shiva'} },
    { name = 'Heavenly Strike', avatars = {'Shiva'} },
    { name = 'Diamond Dust', avatars = {'Shiva'} },
    -- Garuda
    { name = 'Claw', avatars = {'Garuda'} },
    { name = 'Aero II', avatars = {'Garuda'} },
    { name = 'Aero IV', avatars = {'Garuda'} },
    { name = 'Predator Claws', avatars = {'Garuda'} },
    { name = 'Wind Blade', avatars = {'Garuda'} },
    { name = 'Aerial Blast', avatars = {'Garuda'} },
    -- Titan
    { name = 'Rock Throw', avatars = {'Titan'} },
    { name = 'Stone II', avatars = {'Titan'} },
    { name = 'Rock Buster', avatars = {'Titan'} },
    { name = 'Megalith Throw', avatars = {'Titan'} },
    { name = 'Stone IV', avatars = {'Titan'} },
    { name = 'Mountain Buster', avatars = {'Titan'} },
    { name = 'Geocrush', avatars = {'Titan'} },
    { name = 'Crag Throw', avatars = {'Titan'} },
    { name = 'Earthen Fury', avatars = {'Titan'} },
    -- Ramuh
    { name = 'Shock Strike', avatars = {'Ramuh'} },
    { name = 'Thunder II', avatars = {'Ramuh'} },
    { name = 'Thunderspark', avatars = {'Ramuh'} },
    { name = 'Thunder IV', avatars = {'Ramuh'} },
    { name = 'Chaotic Strike', avatars = {'Ramuh'} },
    { name = 'Thunderstorm', avatars = {'Ramuh'} },
    { name = 'Volt Strike', avatars = {'Ramuh'} },
    { name = 'Judgment Bolt', avatars = {'Ramuh'} },
    -- Leviathan
    { name = 'Barracuda Dive', avatars = {'Leviathan'} },
    { name = 'Water II', avatars = {'Leviathan'} },
    { name = 'Tail Whip', avatars = {'Leviathan'} },
    { name = 'Water IV', avatars = {'Leviathan'} },
    { name = 'Spinning Dive', avatars = {'Leviathan'} },
    { name = 'Grand Fall', avatars = {'Leviathan'} },
    { name = 'Tidal Wave', avatars = {'Leviathan'} },
    -- Fenrir
    { name = 'Moonlit Charge', avatars = {'Fenrir'} },
    { name = 'Crescent Fang', avatars = {'Fenrir'} },
    { name = 'Eclipse Bite', avatars = {'Fenrir'} },
    { name = 'Lunar Bay', avatars = {'Fenrir'} },
    { name = 'Impact', avatars = {'Fenrir'} },
    { name = 'Howling Moon', avatars = {'Fenrir'} },
    -- Diabolos
    { name = 'Camisado', avatars = {'Diabolos'} },
    { name = 'Nether Blast', avatars = {'Diabolos'} },
    { name = 'Night Terror', avatars = {'Diabolos'} },
    { name = 'Blindside', avatars = {'Diabolos'} },
    { name = 'Ruinous Omen', avatars = {'Diabolos'} },
    -- Carbuncle
    { name = 'Poison Nails', avatars = {'Carbuncle'} },
    { name = 'Holy Mist', avatars = {'Carbuncle'} },
    { name = 'Meteorite', avatars = {'Carbuncle'} },
    { name = 'Searing Light', avatars = {'Carbuncle'} },
    -- Odin
    { name = 'Zantetsuken', avatars = {'Odin'} },
    -- Cait Sith
    { name = 'Regal Scratch', avatars = {'Cait Sith'} },
    { name = 'Level ? Holy', avatars = {'Cait Sith'} },
    { name = 'Regal Gash', avatars = {'Cait Sith'} },
    -- Siren
    { name = 'Clarsach Call', avatars = {'Siren'} },
    { name = 'Sonic Buffet', avatars = {'Siren'} },
    { name = 'Tornado II', avatars = {'Siren'} },
    { name = 'Hysteric Assault', avatars = {'Siren'} },
    { name = 'Welt', avatars = {'Siren'} },
    { name = 'Katabatic Blades', avatars = {'Siren'} },
};

-- SMN Blood Pacts - Ward (support)
M.bloodPactsWard = {
    -- Carbuncle
    { name = 'Soothing Ruby', avatars = {'Carbuncle'} },
    { name = 'Healing Ruby', avatars = {'Carbuncle'} },
    { name = 'Poison Ruby', avatars = {'Carbuncle'} },
    { name = 'Shining Ruby', avatars = {'Carbuncle'} },
    { name = 'Glittering Ruby', avatars = {'Carbuncle'} },
    { name = 'Healing Ruby II', avatars = {'Carbuncle'} },
    { name = 'Pacifying Ruby', avatars = {'Carbuncle'} },
    -- Ifrit
    { name = 'Crimson Howl', avatars = {'Ifrit'} },
    { name = 'Inferno Howl', avatars = {'Ifrit'} },
    -- Shiva
    { name = 'Frost Armor', avatars = {'Shiva'} },
    { name = 'Sleepga', avatars = {'Shiva'} },
    { name = 'Diamond Storm', avatars = {'Shiva'} },
    { name = 'Crystal Blessing', avatars = {'Shiva'} },
    -- Garuda
    { name = 'Whispering Wind', avatars = {'Garuda'} },
    { name = 'Hastega', avatars = {'Garuda'} },
    { name = 'Aerial Armor', avatars = {'Garuda'} },
    { name = 'Fleet Wind', avatars = {'Garuda'} },
    { name = "Wind's Blessing", avatars = {'Garuda'} },
    { name = 'Hastega II', avatars = {'Garuda'} },
    -- Titan
    { name = 'Earthen Ward', avatars = {'Titan'} },
    { name = 'Earthen Armor', avatars = {'Titan'} },
    -- Ramuh
    { name = 'Rolling Thunder', avatars = {'Ramuh'} },
    { name = 'Lightning Armor', avatars = {'Ramuh'} },
    { name = 'Shock Squall', avatars = {'Ramuh'} },
    -- Leviathan
    { name = 'Slowga', avatars = {'Leviathan'} },
    { name = 'Spring Water', avatars = {'Leviathan'} },
    { name = 'Tidal Roar', avatars = {'Leviathan'} },
    { name = 'Soothing Current', avatars = {'Leviathan'} },
    -- Fenrir
    { name = 'Ecliptic Growl', avatars = {'Fenrir'} },
    { name = 'Ecliptic Howl', avatars = {'Fenrir'} },
    { name = 'Lunar Cry', avatars = {'Fenrir'} },
    { name = 'Lunar Roar', avatars = {'Fenrir'} },
    { name = 'Heavenward Howl', avatars = {'Fenrir'} },
    -- Diabolos
    { name = 'Pavor Nocturnus', avatars = {'Diabolos'} },
    { name = 'Somnolence', avatars = {'Diabolos'} },
    { name = 'Nightmare', avatars = {'Diabolos'} },
    { name = 'Ultimate Terror', avatars = {'Diabolos'} },
    { name = 'Noctoshield', avatars = {'Diabolos'} },
    { name = 'Dream Shroud', avatars = {'Diabolos'} },
    -- Cait Sith
    { name = 'Mewing Lullaby', avatars = {'Cait Sith'} },
    { name = 'Eerie Eye', avatars = {'Cait Sith'} },
    { name = 'Altana\'s Favor', avatars = {'Cait Sith'} },
    { name = 'Raise II', avatars = {'Cait Sith'} },
    { name = 'Reraise II', avatars = {'Cait Sith'} },
    -- Alexander
    { name = 'Perfect Defense', avatars = {'Alexander'} },
    -- Atomos
    { name = 'Chronoshift', avatars = {'Atomos'} },
    -- Siren
    { name = 'Lunatic Voice', avatars = {'Siren'} },
    { name = 'Chinook', avatars = {'Siren'} },
    { name = 'Bitter Elegy', avatars = {'Siren'} },
};

-- ============================================
-- SMN Blood Pact Lookup Index (name -> pact data)
-- ============================================

-- Overlay MP/level from horizon_bloodpacts + XIUI fields from horizon_bloodpacts_xiui.
local function MergeBloodPactWithHorizonStats(base)
    if not base or not base.name then
        return base;
    end
    local merged = {};
    for k, v in pairs(base) do
        merged[k] = v;
    end
    local xiui = horizonBloodPactsXiui and horizonBloodPactsXiui[base.name];
    if xiui then
        for k, v in pairs(xiui) do
            merged[k] = v;
        end
    end
    local st = horizonBloodPacts.byName and horizonBloodPacts.byName[base.name];
    if st then
        merged.mp = st.mp_cost;
        merged.level = (st.levels and st.levels[15]) or 0;
    end
    return merged;
end

-- Build a fast lookup table for Blood Pact data by name.
-- This avoids scanning the pact lists every frame when rendering MP costs.
local function BuildBloodPactIndex()
    local idx = {};

    for _, pact in ipairs(M.bloodPactsRage or {}) do
        if pact and pact.name then
            idx[pact.name] = MergeBloodPactWithHorizonStats(pact);
        end
    end
    for _, pact in ipairs(M.bloodPactsWard or {}) do
        if pact and pact.name then
            idx[pact.name] = MergeBloodPactWithHorizonStats(pact);
        end
    end

    return idx;
end

-- NOTE: This is built once at load time. If you mutate blood pact tables at runtime,
-- call `M.RebuildBloodPactIndex()` after changes.
M.bloodPactIndexByName = BuildBloodPactIndex();

function M.RebuildBloodPactIndex()
    M.bloodPactIndexByName = BuildBloodPactIndex();
end

-- Get Blood Pact data by name (Rage or Ward).
-- Returns merged row: retail `avatars` + XIUI overlays + `mp`/`level` from horizon_bloodpacts, or nil.
function M.GetBloodPactByName(name)
    if not name then return nil; end
    return M.bloodPactIndexByName and M.bloodPactIndexByName[name] or nil;
end

-- DRG Wyvern abilities (Horizon-era only)
M.wyvernCommands = {
    { name = 'Dismiss', category = 'Command', level = 1 },
    { name = 'Steady Wing', category = 'Ability', level = 30 },
};

-- PUP Automaton commands
M.automatonCommands = {
    { name = 'Deploy', category = 'Command' },
    { name = 'Retrieve', category = 'Command' },
    { name = 'Activate', category = 'Ability' },
    { name = 'Deactivate', category = 'Ability' },
    { name = 'Deus Ex Automata', category = 'Ability' },
    { name = 'Repair', category = 'Ability' },
    { name = 'Maintenance', category = 'Ability' },
    { name = 'Role Reversal', category = 'Ability' },
    { name = 'Ventriloquy', category = 'Ability' },
    { name = 'Cooldown', category = 'Ability' },
    { name = 'Overdrive', category = 'Ability' },
    { name = 'Tactical Switch', category = 'Ability' },
    { name = 'Heady Artifice', category = 'Ability' },
};

-- BST pet commands (level-gated, displayed in pet section). Ready rows are inserted after Sic when progression allows.
M.bstPetCommands = {
    { name = 'Fight', category = 'Command', level = 1 },
    { name = 'Heel', category = 'Command', level = 10 },
    { name = 'Stay', category = 'Command', level = 15 },
    { name = 'Sic', category = 'Command', level = 25 },
    { name = 'Leave', category = 'Command', level = 35 },
};

-- ============================================
-- BST Jug Pet Ready Moves by Family
-- Optional `familyVarianceReason`: tooltip + yellow * in searchable combos when only some jugs in the merged UI row learn the move (do not use `reason` for that — `reason` is for level/learn/unavailability elsewhere).
M.petFamilyReadyMoves = {
    ['Rabbit'] = {
        { name = 'Foot Kick', category = 'Ready' },
        { name = 'Dust Cloud', category = 'Ready' },
        { name = 'Whirl Claws', category = 'Ready' },
        {
            name = 'Snow Cloud',
            category = 'Ready',
            familyVarianceReason = 'Arctic-line rabbit jugs only (standard rabbits do not get this Ready).',
        },
        { name = 'Wild Carrot', category = 'Ready' },
    },
    ['Sheep'] = {
        { name = 'Lamb Chop', category = 'Ready' },
        { name = 'Rage', category = 'Ready' },
        { name = 'Sheep Charge', category = 'Ready' },
        { name = 'Sheep Song', category = 'Ready' },
    },
    ['Tiger'] = {
        { name = 'Roar', category = 'Ready' },
        { name = 'Razor Fang', category = 'Ready' },
        { name = 'Claw Cyclone', category = 'Ready' },
        { name = 'Crossthrash', category = 'Ready' },
        { name = 'Predatory Glare', category = 'Ready' },
    },
    ['Crab'] = {
        { name = 'Bubble Shower', category = 'Ready' },
        { name = 'Bubble Curtain', category = 'Ready' },
        { name = 'Big Scissors', category = 'Ready' },
        { name = 'Scissor Guard', category = 'Ready' },
        { name = 'Metallic Body', category = 'Ready' },
    },
    ['Lizard'] = {
        { name = 'Tail Blow', category = 'Ready' },
        { name = 'Fireball', category = 'Ready' },
        { name = 'Blockhead', category = 'Ready' },
        { name = 'Brain Crush', category = 'Ready' },
        { name = 'Infrasonics', category = 'Ready' },
        { name = 'Secretion', category = 'Ready' },
    },
    ['Eft'] = {
        { name = 'Nimble Snap', category = 'Ready' },
        { name = 'Cyclotail', category = 'Ready' },
        { name = 'Geist Wall', category = 'Ready' },
        { name = 'Numbing Noise', category = 'Ready' },
        { name = 'Toxic Spit', category = 'Ready' },
    },
    ['Funguar'] = {
        { name = 'Frogkick', category = 'Ready' },
        { name = 'Spore', category = 'Ready' },
        { name = 'Queasyshroom', category = 'Ready' },
        { name = 'Numbshroom', category = 'Ready' },
        { name = 'Shakeshroom', category = 'Ready' },
        { name = 'Silence Gas', category = 'Ready' },
        { name = 'Dark Spore', category = 'Ready' },
    },
    ['Flytrap'] = {
        { name = 'Soporific', category = 'Ready' },
        { name = 'Gloeosuccus', category = 'Ready' },
        { name = 'Palsy Pollen', category = 'Ready' },
    },
    ['Fly'] = {
        { name = 'Cursed Sphere', category = 'Ready' },
        { name = 'Venom', category = 'Ready' },
        { name = 'Somersault', category = 'Ready' },
    },
    ['Beetle'] = {
        { name = 'Power Attack', category = 'Ready' },
        { name = 'High-Frequency Field', category = 'Ready' },
        { name = 'Rhino Attack', category = 'Ready' },
        { name = 'Rhino Guard', category = 'Ready' },
        { name = 'Spoil', category = 'Ready' },
    },
    ['Antlion'] = {
        { name = 'Mandibular Bite', category = 'Ready' },
        { name = 'Sandblast', category = 'Ready' },
        { name = 'Sandpit', category = 'Ready' },
        { name = 'Venom Spray', category = 'Ready' },
    },
    ['Diremite'] = {
        { name = 'Double Claw', category = 'Ready' },
        { name = 'Grapple', category = 'Ready' },
        { name = 'Spinning Top', category = 'Ready' },
        { name = 'Filamented Hold', category = 'Ready' },
    },
    ['Mandragora'] = {
        { name = 'Head Butt', category = 'Ready' },
        { name = 'Dream Flower', category = 'Ready' },
        { name = 'Wild Oats', category = 'Ready' },
        { name = 'Leaf Dagger', category = 'Ready' },
        { name = 'Scream', category = 'Ready' },
    },
    ['Sabotender'] = {
        { name = 'Needleshot', category = 'Ready' },
        { name = '1000 Needles', category = 'Ready' },
    },
    ['Coeurl'] = {
        { name = 'Chaotic Eye', category = 'Ready' },
        { name = 'Blaster', category = 'Ready' },
        {
            name = 'Charged Whisker',
            category = 'Ready',
            familyVarianceReason = 'Lynx-line jugs only (standard Coeurl jugs do not include this Ready).',
        },
        {
            name = 'Frenzied Rage',
            category = 'Ready',
            familyVarianceReason = 'Lynx-line jugs only (standard Coeurl jugs do not include this Ready).',
        },
    },
    ['Ladybug'] = {
        { name = 'Sudden Lunge', category = 'Ready' },
        { name = 'Spiral Spin', category = 'Ready' },
        { name = 'Noisome Powder', category = 'Ready' },
    },
    ['Hippogryph'] = {
        { name = 'Back Heel', category = 'Ready' },
        { name = 'Jettatura', category = 'Ready' },
        { name = 'Choke Breath', category = 'Ready' },
        { name = 'Fantod', category = 'Ready' },
        { name = 'Hoof Volley', category = 'Ready' },
        { name = 'Nihility Song', category = 'Ready' },
    },
    ['Slug'] = {
        { name = 'Purulent Ooze', category = 'Ready' },
        { name = 'Corrosive Ooze', category = 'Ready' },
    },
    ['Tulfaire'] = {
        { name = 'Molting Plumage', category = 'Ready' },
        { name = 'Swooping Frenzy', category = 'Ready' },
        { name = 'Pentapeck', category = 'Ready' },
    },
    ['Acuex'] = {
        { name = 'Foul Waters', category = 'Ready' },
        { name = 'Pestilent Plume', category = 'Ready' },
    },
    ['Colibri'] = {
        { name = 'Pecking Flurry', category = 'Ready' },
    },
    ['Raaz'] = {
        { name = 'Sweeping Gouge', category = 'Ready' },
        { name = 'Zealous Snort', category = 'Ready' },
    },
    ['Leech'] = {
        { name = 'Suction', category = 'Ready' },
        { name = 'Drainkiss', category = 'Ready' },
        { name = 'Acid Mist', category = 'Ready' },
        { name = 'TP Drainkiss', category = 'Ready' },
    },
    ['Chapuli'] = {
        { name = 'Sensilla Blades', category = 'Ready' },
        { name = 'Tegmina Buffet', category = 'Ready' },
    },
    ['Adamantoise'] = {
        { name = 'Tortoise Stomp', category = 'Ready' },
        { name = 'Harden Shell', category = 'Ready' },
        { name = 'Aqua Breath', category = 'Ready' },
    },
    ['Raptor'] = {
        { name = 'Ripper Fang', category = 'Ready' },
        { name = 'Scythe Tail', category = 'Ready' },
        { name = 'Chomp Rush', category = 'Ready' },
    },
    ['Toad'] = {
        { name = 'Croaker', category = 'Ready' },
        { name = 'Poison Breath', category = 'Ready' },
        { name = 'Toad Kick', category = 'Ready' },
    },
    ['Pugil'] = {
        { name = 'Terror Touch', category = 'Ready' },
        { name = 'Sucker Punch', category = 'Ready' },
        { name = 'Intimidate', category = 'Ready' },
    },
    ['Apkallu'] = {
        { name = 'Beak Lunge', category = 'Ready' },
        { name = 'Frigid Shuffle', category = 'Ready' },
        { name = 'Wisent Snort', category = 'Ready' },
    },
    ['Snapweed'] = {
        { name = 'Seedspray', category = 'Ready' },
        { name = 'Sprout Smack', category = 'Ready' },
        { name = 'Infernal Pestilence', category = 'Ready' },
    },
    ['Spider'] = {
        { name = 'Double Claw', category = 'Ready' },
        { name = 'Grapple', category = 'Ready' },
        { name = 'Spinning Top', category = 'Ready' },
        { name = 'Filamented Hold', category = 'Ready' },
    },
    ['Manticore'] = {
        { name = 'Thunderstrike', category = 'Ready' },
        { name = 'Barbed Crescent', category = 'Ready' },
        { name = 'Death Scissors', category = 'Ready' },
    },
    ['Mosquito'] = {
        { name = 'Infectious Dusk', category = 'Ready' },
        {
            name = 'Absorbing Kiss',
            category = 'Ready',
            familyVarianceReason = 'Higher-tier / select mosquito jugs only (lower-tier familiar omits this Ready).',
        },
        {
            name = 'Pandemic Nip',
            category = 'Ready',
            familyVarianceReason = 'Higher-tier / select mosquito jugs only (lower-tier familiar omits this Ready).',
        },
    },
};

-- Lynx / Arctic rabbits reuse merged family pools (aliases keep jug:lynx and jug:rabbitarctic palettes valid).
M.petFamilyReadyMoves['Lynx'] = M.petFamilyReadyMoves['Coeurl'];
M.petFamilyReadyMoves['RabbitArctic'] = M.petFamilyReadyMoves['Rabbit'];

-- Display labels for jug palette slugs not listed as their own picker row (family consolidated in UI).
M.bstJugPaletteSlugLabels = {
    ['lynx'] = 'Lynx',
    ['rabbitarctic'] = 'Rabbit (Arctic)',
};

-- Ordered jug-family rows for macro editor "Ready (Use)" — display label + petFamilyReadyMoves key (HorizonXI jug roster).
M.bstJugReadyFamilyPicker = {
    { name = 'Rabbit', movesKey = 'Rabbit' },
    { name = 'Sheep', movesKey = 'Sheep' },
    { name = 'Mandragora', movesKey = 'Mandragora' },
    { name = 'Tiger', movesKey = 'Tiger' },
    { name = 'Flytrap', movesKey = 'Flytrap' },
    { name = 'Lizard', movesKey = 'Lizard' },
    { name = 'Fly', movesKey = 'Fly' },
    { name = 'Eft', movesKey = 'Eft' },
    { name = 'Beetle', movesKey = 'Beetle' },
    { name = 'Antlion', movesKey = 'Antlion' },
    { name = 'Crab', movesKey = 'Crab' },
    { name = 'Diremite', movesKey = 'Diremite' },
    { name = 'Funguar', movesKey = 'Funguar' },
    { name = 'Sabotender', movesKey = 'Sabotender' },
    { name = 'Coeurl', movesKey = 'Coeurl' },
    { name = 'Raptor', movesKey = 'Raptor' },
    { name = 'Toad', movesKey = 'Toad' },
    { name = 'Pugil', movesKey = 'Pugil' },
    { name = 'Ladybug', movesKey = 'Ladybug' },
    { name = 'Apkallu', movesKey = 'Apkallu' },
    { name = 'Leech', movesKey = 'Leech' },
    { name = 'Hippogryph', movesKey = 'Hippogryph' },
    { name = 'Slug', movesKey = 'Slug' },
    { name = 'Adamantoise', movesKey = 'Adamantoise' },
    { name = 'Chapuli', movesKey = 'Chapuli' },
    { name = 'Tulfaire', movesKey = 'Tulfaire' },
    { name = 'Snapweed', movesKey = 'Snapweed' },
    { name = 'Raaz', movesKey = 'Raaz' },
    { name = 'Colibri', movesKey = 'Colibri' },
    { name = 'Spider', movesKey = 'Spider' },
    { name = 'Manticore', movesKey = 'Manticore' },
    { name = 'Mosquito', movesKey = 'Mosquito' },
    { name = 'Slime', movesKey = 'Slug' },
};

function M.JugPaletteSlugFromMovesKey(movesKey)
    if not movesKey then
        return nil;
    end
    return movesKey:lower();
end

--- Macro palette composite key `JOB_BST:jug:<slug>` from a Ready family movesKey (`petFamilyReadyMoves`).
---@param movesKey string|nil
---@return number|string
function M.FormatBstMacroPaletteSaveKeyFromMovesKey(movesKey)
    if not movesKey or movesKey == '' then
        return M.JOB_BST;
    end
    return string.format('%d:%s:%s', M.JOB_BST, M.PET_TYPE_JUG, M.JugPaletteSlugFromMovesKey(movesKey));
end

--- Reverse `FormatBstMacroPaletteSaveKeyFromMovesKey` slug segment → canonical movesKey casing.
---@param slug string|nil
---@return string|nil
function M.MovesKeyFromBstMacroPaletteSlug(slug)
    if not slug or slug == '' then
        return nil;
    end
    local lower = slug:lower();
    for _, row in ipairs(M.bstJugReadyFamilyPicker) do
        if row.movesKey:lower() == lower then
            return row.movesKey;
        end
    end
    for mk, _ in pairs(M.petFamilyReadyMoves) do
        if mk:lower() == lower then
            return mk;
        end
    end
    return nil;
end

local bstJugReadyMoveNameSet = {};
for _, familyMoves in pairs(M.petFamilyReadyMoves) do
    for _, move in ipairs(familyMoves) do
        bstJugReadyMoveNameSet[move.name] = true;
    end
end

---@param name string|nil
---@return boolean
function M.IsBstJugReadyMoveName(name)
    return name ~= nil and bstJugReadyMoveNameSet[name] == true;
end

--- Ready moves for a jug family key (`petFamilyReadyMoves`).
---@param movesKey string|nil
---@return table|nil
function M.GetReadyMovesForFamilyMovesKey(movesKey)
    if movesKey == nil or movesKey == '' then
        return nil;
    end
    return M.petFamilyReadyMoves[movesKey];
end

--- Macro editor: ordered family rows (unique labels).
---@return table
function M.GetBstJugReadyFamilyPickerList()
    return M.bstJugReadyFamilyPicker;
end

--- First picker-listed family whose move list contains this ability name (ambiguous moves pick earliest row).
---@param moveName string|nil
---@return string|nil movesKey
function M.ResolveBstJugMovesKeyFromMoveName(moveName)
    if moveName == nil or moveName == '' then
        return nil;
    end
    for _, row in ipairs(M.bstJugReadyFamilyPicker) do
        local moves = M.petFamilyReadyMoves[row.movesKey];
        if moves then
            for _, m in ipairs(moves) do
                if m.name == moveName then
                    return row.movesKey;
                end
            end
        end
    end
    return nil;
end

-- ============================================
-- Jug Pet to Family Mapping
-- ============================================

M.jugPetFamilies = {
    -- Rabbit family
    ['HareFamiliar'] = 'Rabbit',
    ['KeenearedSteffi'] = 'Rabbit',
    ['LuckyLulush'] = 'Rabbit',
    -- Sheep family
    ['SheepFamiliar'] = 'Sheep',
    ['LullabyMelodia'] = 'Sheep',
    ['NurseryNazuna'] = 'Sheep',
    -- Tiger family
    ['TigerFamiliar'] = 'Tiger',
    ['SaberSiravarde'] = 'Tiger',
    ['GorefangHobs'] = 'Tiger',
    ['DapperMac'] = 'Tiger',
    -- Crab family
    ['CrabFamiliar'] = 'Crab',
    ['CourierCarrie'] = 'Crab',
    ['ShellbusterOrob'] = 'Crab',
    ['SunburstMalfik'] = 'Crab',
    ['PorterCrabFamiliar'] = 'Crab',
    -- Lizard/Hill Lizard family
    ['LizardFamiliar'] = 'Lizard',
    ['ColdbloodComo'] = 'Lizard',
    ['WarlikePatrick'] = 'Lizard',
    -- Eft family
    ['EftFamiliar'] = 'Eft',
    ['AmbusherAllie'] = 'Eft',
    -- Funguar family
    ['FunguarFamiliar'] = 'Funguar',
    ['BrainyWaluis'] = 'Funguar',
    ['AudaciousAnna'] = 'Funguar',
    -- Flytrap family
    ['FlytrapFamiliar'] = 'Flytrap',
    ['VoraciousAudrey'] = 'Flytrap',
    -- Fly family
    ['MayflyFamiliar'] = 'Fly',
    -- Beetle family
    ['BeetleFamiliar'] = 'Beetle',
    ['PanzerGalahad'] = 'Beetle',
    ['HurlerPercival'] = 'Beetle',
    ['SharpwitHermes'] = 'Beetle',
    -- Antlion family
    ['AntlionFamiliar'] = 'Antlion',
    ['ChopsueyChucky'] = 'Antlion',
    -- Diremite family
    ['MiteFamiliar'] = 'Diremite',
    ['LifedrinkerLars'] = 'Diremite',
    -- Mandragora family
    ['Homunculus'] = 'Mandragora',
    ['FlowerpotBill'] = 'Mandragora',
    ['FlowerpotBen'] = 'Mandragora',
    ['FlowerpotMerle'] = 'Mandragora',
    ['JovialEdwin'] = 'Mandragora',
    -- Sabotender family
    ['AmigoSabotender'] = 'Sabotender',
    -- Coeurl family
    ['CraftyClyvonne'] = 'Coeurl',
    ['BouncingBertha'] = 'Coeurl',
    -- Lynx family
    ['BloodclawShasra'] = 'Lynx',
    -- Ladybug family
    ['DipperYuly'] = 'Ladybug',
    -- Hippogryph family
    ['FaithfulFalcorr'] = 'Hippogryph',
    ['HippogrypFamiliar'] = 'Hippogryph',
    ['SwiftSieghard'] = 'Hippogryph',
    -- Slug family
    ['GooeyGerard'] = 'Slug',
    ['CrudeRaphie'] = 'Slug',
    -- Tulfaire (Bird) family
    ['SwoopingZhivago'] = 'Tulfaire',
    ['AttentiveIbuki'] = 'Tulfaire',
    -- Acuex family
    ['AcuexFamiliar'] = 'Acuex',
    ['FluffyBredo'] = 'Acuex',
    -- Colibri family
    ['ColibriFamiliar'] = 'Colibri',
    ['ChoralLeera'] = 'Colibri',
    -- Raaz family
    ['CaringKiyomaro'] = 'Raaz',
    -- Slime family (same as Slug)
    ['SlimeFamiliar'] = 'Slug',
};

-- Jug entity -> Ready/`petpalette` family key when it differs from `jugPetFamilies` (same slug as `petFamilyReadyMoves`).
M.jugPetPaletteMovesKeyOverrides = {
    ['LuckyLulush'] = 'RabbitArctic',
};

-- Get the Ready moves / jug palette family key for an entity name (jug jugpets naming table).
function M.GetJugPetPaletteMovesKeyForEntity(petName)
    if petName == nil then
        return nil;
    end
    local ov = M.jugPetPaletteMovesKeyOverrides[petName];
    if ov then
        return ov;
    end
    return M.jugPetFamilies[petName];
end

-- Get the family for a jug pet name
function M.GetJugPetFamily(petName)
    if petName == nil then return nil; end
    return M.jugPetFamilies[petName];
end

-- Get ready moves for a jug pet by name
function M.GetReadyMovesForPet(petName)
    local family = M.GetJugPetPaletteMovesKeyForEntity(petName);
    if family and M.petFamilyReadyMoves[family] then
        return M.petFamilyReadyMoves[family];
    end
    return nil;
end

-- Get all ready moves (for when no specific pet selected)
function M.GetAllReadyMoves()
    local moves = {};
    local seen = {};
    for _, familyMoves in pairs(M.petFamilyReadyMoves) do
        for _, move in ipairs(familyMoves) do
            if not seen[move.name] then
                table.insert(moves, { name = move.name, category = 'Ready' });
                seen[move.name] = true;
            end
        end
    end
    -- Sort alphabetically
    table.sort(moves, function(a, b) return a.name < b.name; end);
    return moves;
end

-- ============================================
-- Pet Command Functions
-- ============================================

-- Get blood pacts for a specific avatar (both Rage and Ward)
function M.GetBloodPactsForAvatar(avatarName)
    local pacts = {};

    -- Add Rage pacts
    for _, pact in ipairs(M.bloodPactsRage) do
        for _, avatar in ipairs(pact.avatars) do
            if avatar == avatarName then
                table.insert(pacts, { name = pact.name, category = 'BP: Rage' });
                break;
            end
        end
    end

    -- Add Ward pacts
    for _, pact in ipairs(M.bloodPactsWard) do
        for _, avatar in ipairs(pact.avatars) do
            if avatar == avatarName then
                table.insert(pacts, { name = pact.name, category = 'BP: Ward' });
                break;
            end
        end
    end

    return pacts;
end

-- Get all blood pacts (for when no specific avatar selected)
function M.GetAllBloodPacts()
    local pacts = {};
    local seen = {};

    -- Add all Rage pacts
    for _, pact in ipairs(M.bloodPactsRage) do
        if not seen[pact.name] then
            table.insert(pacts, { name = pact.name, category = 'BP: Rage' });
            seen[pact.name] = true;
        end
    end

    -- Add all Ward pacts
    for _, pact in ipairs(M.bloodPactsWard) do
        if not seen[pact.name] then
            table.insert(pacts, { name = pact.name, category = 'BP: Ward' });
            seen[pact.name] = true;
        end
    end

    return pacts;
end

-- Get pet commands for a specific job
-- avatarName is optional, for SMN to filter by specific avatar
-- activePetName is optional, for BST to include ready moves for the active pet
function M.GetPetCommandsForJob(jobId, avatarName, activePetName)
    local commands = {};

    if jobId == M.JOB_SMN then
        -- SMN-specific commands
        for _, cmd in ipairs(M.smnPetCommands) do
            table.insert(commands, { name = cmd.name, category = cmd.category, level = cmd.level });
        end
        -- SMN: Blood Pacts
        if avatarName and M.avatars[avatarName] then
            local avatarPacts = M.GetBloodPactsForAvatar(avatarName);
            for _, pact in ipairs(avatarPacts) do
                table.insert(commands, pact);
            end
        else
            local allPacts = M.GetAllBloodPacts();
            for _, pact in ipairs(allPacts) do
                table.insert(commands, pact);
            end
        end
    elseif jobId == M.JOB_DRG then
        -- DRG: Wyvern commands
        for _, cmd in ipairs(M.wyvernCommands) do
            table.insert(commands, { name = cmd.name, category = cmd.category, level = cmd.level });
        end
    elseif jobId == M.JOB_PUP then
        -- PUP: Automaton commands
        for _, cmd in ipairs(M.automatonCommands) do
            table.insert(commands, { name = cmd.name, category = cmd.category });
        end
    elseif jobId == M.JOB_BST then
        local haProgress = require('modules.hotbar.database.horizon_abilities');
        local readyProg = haProgress['Ready'];
        local readyLvl = (readyProg and readyProg.level) or 25;

        -- BST-specific pet commands (Ready variants inserted after Sic when progression allows)
        for _, cmd in ipairs(M.bstPetCommands) do
            table.insert(commands, { name = cmd.name, category = cmd.category, level = cmd.level });
            if cmd.name == 'Sic' and horizonDefinesBstReadyPetCommand() then
                if horizonDefinesBstJugReadyMoves() then
                    table.insert(commands, {
                        name = 'Ready (Recast)',
                        category = 'Command',
                        level = readyLvl,
                        petMacroAction = 'Ready',
                        bstReadySynthetic = 'recast',
                    });
                    table.insert(commands, {
                        name = 'Ready (Use)',
                        category = 'Command',
                        level = readyLvl,
                        bstReadySynthetic = 'use',
                    });
                else
                    table.insert(commands, {
                        name = 'Ready',
                        category = 'Command',
                        level = readyLvl,
                    });
                end
            end
        end
    end

    return commands;
end

-- ============================================
-- "Show All" Expanded List Builders (level-gated)
-- ============================================

local STATUS_HAVE = 'have';
local STATUS_UNAVAILABLE = 'unavailable';

--- Get BST pet commands with level-gated status from horizon_abilities.
--- When jug Ready moves are enabled, replaces plain Ready with "Ready (Recast)" + "Ready (Use)"; jug abilities are chosen via the macro editor sub-picker, not this flat list.
---@param bstLevel number The player's BST level
---@param activePetName string|nil Reserved for callers (jug list no longer merged here)
---@return table Array of {name, category, level, status, reqStr}
function M.GetBstPetCommandsExpanded(bstLevel, activePetName)
    local horizonAbilities = require('modules.hotbar.database.horizon_abilities');
    local commands = {};

    for cmdName, info in pairs(horizonAbilities) do
        if not info.pet then goto continue; end

        if cmdName == 'Ready' and horizonDefinesBstJugReadyMoves() then
            local status = (bstLevel >= info.level) and STATUS_HAVE or STATUS_UNAVAILABLE;
            local reason = status == STATUS_UNAVAILABLE and ('Requires BST Lv. ' .. tostring(info.level)) or nil;
            local reqStr = 'Lv.' .. tostring(info.level);
            table.insert(commands, {
                name = 'Ready (Recast)',
                category = 'Command',
                level = info.level,
                status = status,
                reqStr = reqStr,
                reason = reason,
                petMacroAction = 'Ready',
                bstReadySynthetic = 'recast',
            });
            table.insert(commands, {
                name = 'Ready (Use)',
                category = 'Command',
                level = info.level,
                status = status,
                reqStr = reqStr,
                reason = reason,
                bstReadySynthetic = 'use',
            });
            goto continue;
        end

        local status = (bstLevel >= info.level) and STATUS_HAVE or STATUS_UNAVAILABLE;
        table.insert(commands, {
            name = cmdName,
            category = 'Command',
            level = info.level,
            status = status,
            reqStr = 'Lv.' .. tostring(info.level),
            reason = status == STATUS_UNAVAILABLE and ('Requires BST Lv. ' .. tostring(info.level)) or nil,
        });
        ::continue::
    end

    table.sort(commands, function(a, b)
        local sa = a.status == STATUS_HAVE and 1 or 2;
        local sb = b.status == STATUS_HAVE and 1 or 2;
        if sa ~= sb then return sa < sb; end
        local la = a.level or 999;
        local lb = b.level or 999;
        if la ~= lb then return la < lb; end
        return a.name < b.name;
    end);

    return commands;
end

--- Get blood pacts for a specific avatar (or all) with level-gated status.
---@param avatarName string|nil Avatar name to filter by, or nil for all
---@param smnLevel number The player's SMN level
---@return table Array of {name, category, level, mp, status, reqStr}
function M.GetBloodPactsExpanded(avatarName, smnLevel)
    local pacts = {};
    local seen = {};

    local function addPact(pact, cat)
        if seen[pact.name] then return; end
        if avatarName then
            local match = false;
            for _, av in ipairs(pact.avatars) do
                if av == avatarName then match = true; break; end
            end
            if not match then return; end
        end

        local bpData = horizonBloodPacts.byName and horizonBloodPacts.byName[pact.name];
        local level = 0;
        local mp = 0;
        if bpData then
            level = (bpData.levels and bpData.levels[15]) or 0;
            mp = bpData.mp_cost or 0;
        end

        local status;
        if level <= 0 or smnLevel >= level then
            status = STATUS_HAVE;
        else
            status = STATUS_UNAVAILABLE;
        end

        local reqStr;
        if level > 0 then
            reqStr = 'Lv.' .. tostring(level);
        end

        seen[pact.name] = true;
        local mergedRow = M.GetBloodPactByName(pact.name);
        local requiresAstralFlow = mergedRow and mergedRow.requiresFlow == true;
        local pinkStarTooltip = requiresAstralFlow and universalTwoHour.PINK_STAR_ASTRAL_FLOW_TOOLTIP or nil;
        table.insert(pacts, {
            name = pact.name,
            category = cat,
            level = level,
            mp = mp,
            status = status,
            reqStr = reqStr,
            reason = (status == STATUS_UNAVAILABLE and level > 0) and ('Requires SMN Lv. ' .. tostring(level)) or nil,
            pinkStarTooltip = pinkStarTooltip,
            requiresAstralFlow = requiresAstralFlow,
        });
    end

    -- SMN pet commands (Assault, Release, Retreat) — always available at level 1
    for _, cmd in ipairs(M.smnPetCommands) do
        local status = (smnLevel >= cmd.level) and STATUS_HAVE or STATUS_UNAVAILABLE;
        table.insert(pacts, {
            name = cmd.name,
            category = 'Command',
            level = cmd.level,
            mp = 0,
            status = status,
            reqStr = 'Lv.' .. tostring(cmd.level),
            reason = status == STATUS_UNAVAILABLE and ('Requires SMN Lv. ' .. tostring(cmd.level)) or nil,
            requiresAstralFlow = false,
        });
    end

    for _, pact in ipairs(M.bloodPactsRage) do
        addPact(pact, 'BP: Rage');
    end
    for _, pact in ipairs(M.bloodPactsWard) do
        addPact(pact, 'BP: Ward');
    end

    -- Sort: Astral Flow–only blood pacts first (SMN “two-hour style”), then Commands, BP: Rage, BP: Ward.
    -- Within each band: availability, level, name.
    local CAT_SORT = { ['Command'] = 1, ['BP: Rage'] = 2, ['BP: Ward'] = 3 };
    table.sort(pacts, function(a, b)
        local fa = a.requiresAstralFlow and 0 or 1;
        local fb = b.requiresAstralFlow and 0 or 1;
        if fa ~= fb then return fa < fb; end
        local ca = CAT_SORT[a.category] or 9;
        local cb = CAT_SORT[b.category] or 9;
        if ca ~= cb then return ca < cb; end
        local sa = a.status == STATUS_HAVE and 1 or 2;
        local sb = b.status == STATUS_HAVE and 1 or 2;
        if sa ~= sb then return sa < sb; end
        if a.level ~= b.level then return a.level < b.level; end
        return a.name < b.name;
    end);

    return pacts;
end

M.STATUS_HAVE = STATUS_HAVE;
M.STATUS_UNAVAILABLE = STATUS_UNAVAILABLE;

return M;
