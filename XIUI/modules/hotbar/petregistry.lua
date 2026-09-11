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
-- Each jug pet gets its own palette keyed by entity name.
-- Lists match server availability (Horizon vs retail).
-- ============================================

if HzLimitedMode then
    M.jugPets = {
        'HareFamiliar', 'SheepFamiliar', 'FlowerpotBill', 'FlytrapFamiliar',
        'TigerFamiliar', 'BeetleFamiliar', 'EftFamiliar', 'LizardFamiliar',
        'MayflyFamiliar', 'AntlionFamiliar', 'CrabFamiliar', 'MiteFamiliar',
        'FunguarFamiliar', 'AmbusherAllie', 'AmigoSabotender', 'ChopsueyChucky',
        'ColdbloodComo', 'CourierCarrie', 'FlowerpotBen', 'Homunculus',
        'KeenearedSteffi', 'LifedrinkerLars', 'LullabyMelodia', 'PanzerGalahad',
        'SaberSiravarde', 'ShellbusterOrob', 'VoraciousAudrey',
    };
else
    M.jugPets = {
        'Homunculus', 'HareFamiliar', 'KeenearedSteffi', 'CrabFamiliar',
        'CourierCarrie', 'SheepFamiliar', 'LullabyMelodia', 'TigerFamiliar',
        'SaberSiravarde', 'MayflyFamiliar', 'ShellbusterOrob', 'LizardFamiliar',
        'ColdbloodComo', 'EftFamiliar', 'AmbusherAllie', 'FunguarFamiliar',
        'FlytrapFamiliar', 'VoraciousAudrey', 'FlowerpotBill', 'FlowerpotBen',
        'AntlionFamiliar', 'ChopsueyChucky', 'BeetleFamiliar', 'PanzerGalahad',
        'MiteFamiliar', 'LifedrinkerLars', 'TurbidToloi', 'AmigoSabotender',
        'SlipperySilas', 'DapperMac', 'CraftyClyvonne', 'NurseryNazuna',
        'LuckyLulush', 'FlowerpotMerle', 'DipperYuly', 'DiscreetLouise',
        'FatsoFargann', 'PrestoJulio', 'AudaciousAnna', 'MailbusterCetas',
        'FaithfulFalcorr', 'SwiftSieghard', 'BloodclawShasra', 'BugeyedBroncha',
        'GorefangHobs', 'GooeyGerard', 'CrudeRaphie', 'AmiableRoche',
        'SweetCaroline', 'HeadbreakerKen', 'AnklebiterJedd', 'CursedAnnabelle',
        'BrainyWaluis', 'RedolentCandi', 'AlluringHoney', 'CaringKiyomaro',
        'VivaciousVickie', 'SuspiciousAlice', 'SurgingStorm', 'SubmergedIyo',
        'WarlikePatrick', 'RhymingShizuna', 'BlackbeardRandy', 'ThreestarLynn',
        'HurlerPercival', 'AcuexFamiliar', 'FluffyBredo', 'SlimeFamiliar',
        'SultryPatrice', 'GenerousArthur', 'DaringRoland', 'AttentiveIbuki',
        'SwoopingZhivago', 'ChoralLeera', 'ColibriFamiliar', 'HippogrypFamiliar',
        'SunburstMalfik', 'AgedAngus', 'HeraldHenry', 'BraveHeroGlenn',
        'PorterCrabFamiliar', 'JovialEdwin', 'ScissorlegXerin',
        'BouncingBertha', 'SharpwitHermes', 'FleetReinhard', 'DroopyDortwin',
        'PonderingPeter', 'MosquitoFamilia', 'Left-HandedYoko',
    };
end

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

-- Canonical pet-palette keys for pets that share one palette regardless of
-- custom entity name (renamed wyvern, automaton nickname, any charmed mob).
M.PET_KEY_WYVERN = 'Wyvern';
M.PET_KEY_AUTOMATON = 'Automaton';
M.PET_KEY_CHARMED = 'Charmed';

-- ============================================
-- Display Names for Pet Types
-- ============================================

M.petTypeDisplayNames = {
    [M.PET_TYPE_AVATAR] = 'Avatar',
    [M.PET_TYPE_SPIRIT] = 'Spirit',
    [M.PET_TYPE_WYVERN] = M.PET_KEY_WYVERN,
    [M.PET_TYPE_AUTOMATON] = M.PET_KEY_AUTOMATON,
    [M.PET_TYPE_JUG] = 'Jug Pet',
    [M.PET_TYPE_CHARM] = M.PET_KEY_CHARMED,
};

-- ============================================
-- Functions
-- ============================================

-- Check if a job is a pet job
function M.IsPetJob(jobId)
    return M.jobPetCategories[jobId] ~= nil;
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

-- Get the pet palette storage key for a live pet entity name.
-- Keys are the pet name itself (no job/subjob): "Fenrir", "HareFamiliar", etc.
-- Shared exceptions: Wyvern, Automaton, and all charmed pets -> "Charmed".
function M.GetPetKey(petName, jobId)
    if petName == nil then return nil; end

    local petType = M.GetPetType(petName, jobId);
    if not petType then return nil; end

    if petType == M.PET_TYPE_CHARM then
        return M.PET_KEY_CHARMED;
    elseif petType == M.PET_TYPE_WYVERN then
        return M.PET_KEY_WYVERN;
    elseif petType == M.PET_TYPE_AUTOMATON then
        return M.PET_KEY_AUTOMATON;
    end

    -- Avatars, spirits, and jug pets: one palette per entity name
    return petName;
end

-- Display label for a pet palette key (keys are already human-readable names)
function M.GetDisplayNameForKey(petKey)
    if not petKey then return 'Base'; end
    return petKey;
end

-- Get all available pet keys for a job (for cycling / dropdowns)
function M.GetAvailablePetKeys(jobId)
    local keys = {};

    if jobId == M.JOB_SMN then
        for _, name in ipairs(M.GetAvatarList()) do
            table.insert(keys, name);
        end
        for _, name in ipairs(M.GetSpiritList()) do
            table.insert(keys, name);
        end
    elseif jobId == M.JOB_DRG then
        table.insert(keys, M.PET_KEY_WYVERN);
    elseif jobId == M.JOB_PUP then
        table.insert(keys, M.PET_KEY_AUTOMATON);
    elseif jobId == M.JOB_BST then
        for _, petName in ipairs(M.jugPets) do
            table.insert(keys, petName);
        end
        table.insert(keys, M.PET_KEY_CHARMED);
    end

    return keys;
end

-- Insert spaces before capitals for jug dropdown labels (CourierCarrie -> Courier Carrie).
-- Storage keys stay as the raw entity name.
function M.FormatJugPetDisplayName(petName)
    if petName == nil or petName == '' then
        return '';
    end
    return (tostring(petName):gsub('(%l)(%u)', '%1 %2'):gsub('(%d)(%u)', '%1 %2'));
end

-- Ordered jug pet list for dropdowns (key = entity name, displayName = spaced label)
function M.GetJugPetList()
    local list = {};
    for _, petName in ipairs(M.jugPets) do
        table.insert(list, {
            name = petName,
            key = petName,
            displayName = M.FormatJugPetDisplayName(petName),
        });
    end
    return list;
end

-- Get pet key for a known jug entity name
function M.GetPetKeyForJug(petName)
    if not M.IsJugPet(petName) then return nil; end
    return petName;
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

local function CopyAndSortNames(names)
    local list = {};
    for _, name in ipairs(names) do
        table.insert(list, name);
    end
    table.sort(list, function(a, b)
        return string.lower(a) < string.lower(b);
    end);
    return list;
end

-- Alphabetical avatar names for UI lists
function M.GetSortedAvatarList()
    return CopyAndSortNames(M.GetAvatarList());
end

-- Alphabetical spirit names for UI lists
function M.GetSortedSpiritList()
    return CopyAndSortNames(M.GetSpiritList());
end

-- Alphabetical jug pet list for UI (sorted by spaced display name)
function M.GetSortedJugPetList()
    local list = M.GetJugPetList();
    table.sort(list, function(a, b)
        return string.lower(a.displayName) < string.lower(b.displayName);
    end);
    return list;
end

-- Combined list of all summons (avatars + spirits)
function M.GetAllSummonsList()
    local list = {};
    for _, avatar in ipairs(M.GetAvatarList()) do
        table.insert(list, { name = avatar, category = 'avatar' });
    end
    for _, spirit in ipairs(M.GetSpiritList()) do
        table.insert(list, { name = spirit, category = 'spirit' });
    end
    return list;
end

-- Get the pet key for a summon name (avatar or spirit)
function M.GetPetKeyForSummon(summonName)
    if M.avatars[summonName] or M.spirits[summonName] then
        return summonName;
    end
    return nil;
end

-- DRG/PUP pets cannot be active when the job is only subbed.
function M.IsMainOnlyPetJob(jobId)
    return jobId == M.JOB_DRG or jobId == M.JOB_PUP;
end

-- Which pet jobs should appear in the macro-palette pet dropdown.
-- Includes the job being edited, plus live main/sub (sub skips DRG/PUP).
-- Returns a set: { [jobId] = true }
function M.GetPetJobsForPaletteEditor(selectedJobId, mainJobId, subJobId)
    local jobs = {};

    local function addJob(jobId, isSub)
        if type(jobId) ~= 'number' or not M.IsPetJob(jobId) then
            return;
        end
        if isSub and M.IsMainOnlyPetJob(jobId) then
            return;
        end
        jobs[jobId] = true;
    end

    addJob(selectedJobId, false);
    addJob(mainJobId, false);
    addJob(subJobId, true);

    return jobs;
end

-- ============================================
-- Pet ability menus
-- ============================================
-- Macro editor / hotbar pet dropdowns use a HasAbility scan for known
-- pet-typed resources. No static SMN/BST/DRG/PUP command lists here.
-- Ready-move family data below is only for skillchain highlighting.

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

-- Get ready moves for a jug pet by name (skillchain highlighting)
function M.GetReadyMovesForPet(petName)
    local family = M.GetJugPetFamily(petName);
    if family and M.petFamilyReadyMoves[family] then
        return M.petFamilyReadyMoves[family];
    end
    return nil;
end

return M;
