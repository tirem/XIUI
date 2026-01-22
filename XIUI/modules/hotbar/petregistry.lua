--[[
* XIUI Hotbar - Pet Registry Module
* Centralized pet name-to-key mapping for pet-aware hotbar palettes
]]--

local M = {};

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
-- Returns: string like "avatar:ifrit", "wyvern", "jug", "automaton", etc.
-- For SMN avatars/spirits, returns per-entity keys
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
    end

    -- Other jobs: Per-type palettes (wyvern, automaton, jug, charm)
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
        table.insert(keys, M.PET_TYPE_CHARM);
    end

    return keys;
end

-- Get ordered list of avatar names (for dropdowns, etc.)
function M.GetAvatarList()
    return {
        'Carbuncle', 'Ifrit', 'Shiva', 'Garuda', 'Titan', 'Ramuh',
        'Leviathan', 'Fenrir', 'Diabolos', 'Atomos', 'Odin', 'Alexander',
        'Cait Sith', 'Siren',
    };
end

-- Get ordered list of spirit names
function M.GetSpiritList()
    return {
        'Fire Spirit', 'Ice Spirit', 'Air Spirit', 'Earth Spirit',
        'Thunder Spirit', 'Water Spirit', 'Light Spirit', 'Dark Spirit',
    };
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

-- ============================================
-- Pet Commands Data
-- ============================================

-- Generic pet commands (all pet jobs)
M.genericPetCommands = {
    { name = 'Assault', category = 'Command' },
    { name = 'Retreat', category = 'Command' },
    { name = 'Stay', category = 'Command' },
    { name = 'Heel', category = 'Command' },
    { name = 'Release', category = 'Command' },
};

-- SMN Blood Pacts - Rage (offensive)
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
    -- Shiva
    { name = 'Axe Kick', avatars = {'Shiva'} },
    { name = 'Blizzard II', avatars = {'Shiva'} },
    { name = 'Double Slap', avatars = {'Shiva'} },
    { name = 'Blizzard IV', avatars = {'Shiva'} },
    { name = 'Rush', avatars = {'Shiva'} },
    { name = 'Heavenly Strike', avatars = {'Shiva'} },
    -- Garuda
    { name = 'Claw', avatars = {'Garuda'} },
    { name = 'Aero II', avatars = {'Garuda'} },
    { name = 'Aero IV', avatars = {'Garuda'} },
    { name = 'Predator Claws', avatars = {'Garuda'} },
    { name = 'Wind Blade', avatars = {'Garuda'} },
    -- Titan
    { name = 'Rock Throw', avatars = {'Titan'} },
    { name = 'Stone II', avatars = {'Titan'} },
    { name = 'Stone IV', avatars = {'Titan'} },
    { name = 'Rock Buster', avatars = {'Titan'} },
    { name = 'Megalith Throw', avatars = {'Titan'} },
    { name = 'Mountain Buster', avatars = {'Titan'} },
    { name = 'Geocrush', avatars = {'Titan'} },
    { name = 'Crag Throw', avatars = {'Titan'} },
    -- Ramuh
    { name = 'Shock Strike', avatars = {'Ramuh'} },
    { name = 'Thunder II', avatars = {'Ramuh'} },
    { name = 'Thunder IV', avatars = {'Ramuh'} },
    { name = 'Chaotic Strike', avatars = {'Ramuh'} },
    { name = 'Thunderstorm', avatars = {'Ramuh'} },
    { name = 'Thunderspark', avatars = {'Ramuh'} },
    { name = 'Volt Strike', avatars = {'Ramuh'} },
    -- Leviathan
    { name = 'Barracuda Dive', avatars = {'Leviathan'} },
    { name = 'Water II', avatars = {'Leviathan'} },
    { name = 'Water IV', avatars = {'Leviathan'} },
    { name = 'Tail Whip', avatars = {'Leviathan'} },
    { name = 'Spinning Dive', avatars = {'Leviathan'} },
    { name = 'Grand Fall', avatars = {'Leviathan'} },
    -- Fenrir
    { name = 'Moonlit Charge', avatars = {'Fenrir'} },
    { name = 'Crescent Fang', avatars = {'Fenrir'} },
    { name = 'Eclipse Bite', avatars = {'Fenrir'} },
    { name = 'Howling Moon', avatars = {'Fenrir'} },
    { name = 'Impact', avatars = {'Fenrir'} },
    -- Diabolos
    { name = 'Camisado', avatars = {'Diabolos'} },
    { name = 'Nether Blast', avatars = {'Diabolos'} },
    { name = 'Night Terror', avatars = {'Diabolos'} },
    -- Carbuncle
    { name = 'Poison Nails', avatars = {'Carbuncle'} },
    { name = 'Holy Mist', avatars = {'Carbuncle'} },
    { name = 'Meteorite', avatars = {'Carbuncle'} },
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
    { name = 'Aerial Armor', avatars = {'Garuda'} },
    { name = 'Whispering Wind', avatars = {'Garuda'} },
    { name = 'Hastega', avatars = {'Garuda'} },
    { name = 'Fleet Wind', avatars = {'Garuda'} },
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
    -- Fenrir
    { name = 'Ecliptic Growl', avatars = {'Fenrir'} },
    { name = 'Ecliptic Howl', avatars = {'Fenrir'} },
    { name = 'Lunar Cry', avatars = {'Fenrir'} },
    { name = 'Lunar Roar', avatars = {'Fenrir'} },
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

-- DRG Wyvern abilities
M.wyvernCommands = {
    { name = 'Steady Wing', category = 'Ability' },
    { name = 'Spirit Bond', category = 'Ability' },
    { name = 'Dragon Breaker', category = 'Ability' },
    { name = 'Spirit Jump', category = 'Ability' },
    { name = 'Soul Jump', category = 'Ability' },
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

-- BST pet commands (not job abilities - those go in Ability section)
M.bstReadyCommands = {
    { name = 'Fight', category = 'Command' },
    { name = 'Sic', category = 'Command' },
    { name = 'Ready', category = 'Command' },
    { name = 'Reward', category = 'Command' },
};

-- ============================================
-- BST Jug Pet Ready Moves by Family
-- ============================================

M.petFamilyReadyMoves = {
    ['Rabbit'] = {
        { name = 'Foot Kick', category = 'Ready' },
        { name = 'Dust Cloud', category = 'Ready' },
        { name = 'Whirl Claws', category = 'Ready' },
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
    },
    ['Lynx'] = {
        { name = 'Chaotic Eye', category = 'Ready' },
        { name = 'Blaster', category = 'Ready' },
        { name = 'Charged Whisker', category = 'Ready' },
        { name = 'Frenzied Rage', category = 'Ready' },
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
};

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

-- Get the family for a jug pet name
function M.GetJugPetFamily(petName)
    if petName == nil then return nil; end
    return M.jugPetFamilies[petName];
end

-- Get ready moves for a jug pet by name
function M.GetReadyMovesForPet(petName)
    local family = M.GetJugPetFamily(petName);
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

    -- Add generic commands first
    for _, cmd in ipairs(M.genericPetCommands) do
        table.insert(commands, { name = cmd.name, category = cmd.category });
    end

    if jobId == M.JOB_SMN then
        -- SMN: Blood Pacts
        if avatarName and M.avatars[avatarName] then
            -- Specific avatar - add only their pacts
            local avatarPacts = M.GetBloodPactsForAvatar(avatarName);
            for _, pact in ipairs(avatarPacts) do
                table.insert(commands, pact);
            end
        else
            -- No specific avatar - add all pacts
            local allPacts = M.GetAllBloodPacts();
            for _, pact in ipairs(allPacts) do
                table.insert(commands, pact);
            end
        end
    elseif jobId == M.JOB_DRG then
        -- DRG: Wyvern commands
        for _, cmd in ipairs(M.wyvernCommands) do
            table.insert(commands, { name = cmd.name, category = cmd.category });
        end
    elseif jobId == M.JOB_PUP then
        -- PUP: Automaton commands
        for _, cmd in ipairs(M.automatonCommands) do
            table.insert(commands, { name = cmd.name, category = cmd.category });
        end
    elseif jobId == M.JOB_BST then
        -- BST: Ready commands (abilities)
        for _, cmd in ipairs(M.bstReadyCommands) do
            table.insert(commands, { name = cmd.name, category = cmd.category });
        end
        -- BST: Ready moves for the active pet
        if activePetName then
            local readyMoves = M.GetReadyMovesForPet(activePetName);
            if readyMoves then
                for _, move in ipairs(readyMoves) do
                    table.insert(commands, { name = move.name, category = move.category });
                end
            end
        else
            -- No specific pet - add all ready moves
            local allMoves = M.GetAllReadyMoves();
            for _, move in ipairs(allMoves) do
                table.insert(commands, move);
            end
        end
    end

    return commands;
end

return M;
