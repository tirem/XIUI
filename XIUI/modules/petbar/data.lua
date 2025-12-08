--[[
* XIUI Pet Bar - Data Module
* Handles state, caches, font objects, primitives, and helper functions
]]--

require('common');
require('handlers.helpers');
local windowBg = require('libs.windowbackground');

local data = {};

-- ============================================
-- Constants
-- ============================================
data.PADDING = 8;
data.JOB_SMN = 15;
data.JOB_BST = 9;
data.JOB_DRG = 14;
data.JOB_PUP = 18;

data.MAX_ABILITY_ICONS = 6;
data.ABILITY_ICON_SIZE = 24;

data.bgImageKeys = { 'bg', 'tl', 'tr', 'br', 'bl' };

-- Preview type constants
data.PREVIEW_WYVERN = 1;
data.PREVIEW_AVATAR = 2;
data.PREVIEW_AUTOMATON = 3;
data.PREVIEW_JUG = 4;
data.PREVIEW_CHARMED = 5;

-- Preview type names for config dropdown
data.previewTypeNames = {
    [data.PREVIEW_WYVERN] = 'Wyvern (DRG)',
    [data.PREVIEW_AVATAR] = 'Avatar (SMN)',
    [data.PREVIEW_AUTOMATON] = 'Automaton (PUP)',
    [data.PREVIEW_JUG] = 'Jug Pet (BST)',
    [data.PREVIEW_CHARMED] = 'Charmed Pet (BST)',
};

-- Pet name to image file mapping
-- Maps in-game pet names to their image file paths
data.petImageMap = {
    -- Avatars
    ['Carbuncle'] = 'avatars/carbuncle.png',
    ['Ifrit'] = 'avatars/ifrit.png',
    ['Shiva'] = 'avatars/shiva.png',
    ['Garuda'] = 'avatars/garuda.png',
    ['Titan'] = 'avatars/titan.png',
    ['Ramuh'] = 'avatars/ramuh.png',
    ['Leviathan'] = 'avatars/leviathan.png',
    ['Fenrir'] = 'avatars/fenrir.png',
    ['Diabolos'] = 'avatars/diabolos.png',
    ['Atomos'] = 'avatars/atomos.png',
    ['Odin'] = 'avatars/odin.png',
    ['Alexander'] = 'avatars/alexander.png',
    ['Cait Sith'] = 'avatars/caitsith.png',
    ['Siren'] = 'avatars/siren.png',
    -- Spirits
    ['Fire Spirit'] = 'spirits/firespirit.png',
    ['Ice Spirit'] = 'spirits/icespirit.png',
    ['Air Spirit'] = 'spirits/windspirit.png',
    ['Earth Spirit'] = 'spirits/earthspirit.png',
    ['Thunder Spirit'] = 'spirits/thunderspirit.png',
    ['Water Spirit'] = 'spirits/waterspirit.png',
    ['Light Spirit'] = 'spirits/lightspirit.png',
    ['Dark Spirit'] = 'spirits/darkspirit.png',
};

-- Ordered list of avatars for config dropdown
data.avatarList = {
    'Carbuncle', 'Ifrit', 'Shiva', 'Garuda', 'Titan', 'Ramuh',
    'Leviathan', 'Fenrir', 'Diabolos', 'Atomos', 'Odin', 'Alexander',
    'Cait Sith', 'Siren',
    'Fire Spirit', 'Ice Spirit', 'Air Spirit', 'Earth Spirit',
    'Thunder Spirit', 'Water Spirit', 'Light Spirit', 'Dark Spirit',
};

-- ============================================
-- Jug Pet Database (from PetMe addon)
-- ============================================
-- Each entry: name (in-game), maxLevel, duration (minutes)
data.jugPets = {
    -- 90 minute pets (lower level)
    {name = 'FunguarFamiliar', maxLevel = 35, duration = 90},
    {name = 'CourierCarrie', maxLevel = 23, duration = 90},
    {name = 'SheepFamiliar', maxLevel = 35, duration = 90},
    {name = 'TigerFamiliar', maxLevel = 40, duration = 90},
    {name = 'FlytrapFamiliar', maxLevel = 40, duration = 90},
    {name = 'LizardFamiliar', maxLevel = 45, duration = 90},
    {name = 'MayflyFamiliar', maxLevel = 45, duration = 90},

    -- 60 minute pets (mid level)
    {name = 'EftFamiliar', maxLevel = 50, duration = 60},
    {name = 'BeetleFamiliar', maxLevel = 55, duration = 60},
    {name = 'AntlionFamiliar', maxLevel = 55, duration = 60},
    {name = 'MiteFamiliar', maxLevel = 55, duration = 60},
    {name = 'KeenearedSteffi', maxLevel = 75, duration = 60},
    {name = 'LullabyMelodia', maxLevel = 75, duration = 60},
    {name = 'FlowerpotBen', maxLevel = 75, duration = 60},
    {name = 'FlowerpotBill', maxLevel = 75, duration = 60},
    {name = 'Homunculus', maxLevel = 75, duration = 60},
    {name = 'VoraciousAudrey', maxLevel = 75, duration = 60},
    {name = 'AmbusherAllie', maxLevel = 75, duration = 60},
    {name = 'LifedrinkerLars', maxLevel = 75, duration = 60},
    {name = 'PanzerGalahad', maxLevel = 75, duration = 60},
    {name = 'ChopsueyChucky', maxLevel = 75, duration = 60},
    {name = 'AmigoSabotender', maxLevel = 75, duration = 60},

    -- 30 minute pets (high level)
    {name = 'CraftyClyvonne', maxLevel = 75, duration = 30},
    {name = 'BloodclawShasra', maxLevel = 75, duration = 30},
    {name = 'GorefangHobs', maxLevel = 75, duration = 30},
    {name = 'DipperYuly', maxLevel = 75, duration = 30},
    {name = 'SunburstMalfik', maxLevel = 75, duration = 30},
    {name = 'WarlikePatrick', maxLevel = 75, duration = 30},
    {name = 'ScissorlegXerin', maxLevel = 75, duration = 30},
    {name = 'BouncingBertha', maxLevel = 75, duration = 30},
    {name = 'RhymingShizuna', maxLevel = 75, duration = 30},
    {name = 'AttentiveIbuki', maxLevel = 75, duration = 30},
    {name = 'SwoopingZhivago', maxLevel = 75, duration = 30},
    {name = 'GenerousArthur', maxLevel = 75, duration = 30},
    {name = 'ThreestarLynn', maxLevel = 75, duration = 30},
    {name = 'BrainyWaluis', maxLevel = 75, duration = 30},
    {name = 'FaithfulFalcorr', maxLevel = 75, duration = 30},
    {name = 'SharpwitHermes', maxLevel = 99, duration = 30},
    {name = 'HeadbreakerKen', maxLevel = 99, duration = 30},
    {name = 'RedolentCandi', maxLevel = 99, duration = 30},
    {name = 'AlluringHoney', maxLevel = 99, duration = 30},
    {name = 'CaringKiyomaro', maxLevel = 99, duration = 30},
    {name = 'VivaciousVickie', maxLevel = 99, duration = 30},
    {name = 'HurlerPercival', maxLevel = 99, duration = 30},
    {name = 'BlackbeardRandy', maxLevel = 99, duration = 30},
    {name = 'FleetReinhard', maxLevel = 99, duration = 30},
    {name = 'GooeyGerard', maxLevel = 99, duration = 30},
    {name = 'CrudeRaphie', maxLevel = 99, duration = 30},
    {name = 'DroopyDortwin', maxLevel = 99, duration = 30},
    {name = 'SunburstMalfik', maxLevel = 99, duration = 30},
    {name = 'PonderingPeter', maxLevel = 99, duration = 30},
    {name = 'MosquitoFamilia', maxLevel = 99, duration = 30},
    {name = 'Left-HandedYoko', maxLevel = 99, duration = 30},
};

-- Build a lookup table for faster access
data.jugPetLookup = {};
for _, pet in ipairs(data.jugPets) do
    data.jugPetLookup[pet.name] = pet;
end

-- Get jug pet info by name
function data.GetJugPetInfo(petName)
    if petName == nil then return nil; end
    return data.jugPetLookup[petName];
end

-- Check if a pet name is a jug pet
function data.IsJugPet(petName)
    return data.GetJugPetInfo(petName) ~= nil;
end

-- Get pet level based on player level and pet type
function data.GetPetLevel(petName, playerLevel)
    if petName == nil or playerLevel == nil then return nil; end

    -- For jug pets, level is min(playerLevel, petMaxLevel)
    local jugInfo = data.GetJugPetInfo(petName);
    if jugInfo then
        return math.min(playerLevel, jugInfo.maxLevel);
    end

    -- For avatars/spirits, they match player's SMN level (main or sub)
    if data.petImageMap[petName] then
        return playerLevel;
    end

    -- For charmed pets, we can't know the level without tracking the charm action
    return nil;
end

-- ============================================
-- Pet Timer Tracking Functions
-- ============================================

-- Detect and track a new pet summon
function data.TrackPetSummon(petName, petJob)
    if petName == nil then
        -- Pet dismissed - clear tracking
        data.petSummonTime = nil;
        data.petExpireTime = nil;
        data.petType = nil;
        data.lastTrackedPetName = nil;
        data.charmStartTime = nil;
        -- Clear persisted timer data
        if gConfig then
            gConfig.petBarPetSummonTime = nil;
            gConfig.petBarPetExpireTime = nil;
            gConfig.petBarPetType = nil;
            gConfig.petBarPetName = nil;
            gConfig.petBarCharmStartTime = nil;
        end
        return;
    end

    -- Only track if pet name changed (new summon)
    if petName == data.lastTrackedPetName then
        return;
    end

    data.lastTrackedPetName = petName;
    data.petSummonTime = os.time();

    -- Determine pet type and calculate expiration
    local jugInfo = data.GetJugPetInfo(petName);
    if jugInfo then
        data.petType = 'jug';
        data.petExpireTime = data.petSummonTime + (jugInfo.duration * 60);
        data.charmStartTime = nil;
    elseif petJob == data.JOB_BST and not data.petImageMap[petName] then
        -- BST pet that isn't an avatar = charmed pet
        data.petType = 'charm';
        data.petExpireTime = nil;  -- Charm duration is complex to calculate
        data.charmStartTime = os.time();
    elseif petJob == data.JOB_SMN then
        data.petType = 'avatar';
        data.petExpireTime = nil;  -- Avatars don't expire on timer
        data.charmStartTime = nil;
    elseif petJob == data.JOB_DRG then
        data.petType = 'wyvern';
        data.petExpireTime = nil;  -- Wyverns don't expire on timer
        data.charmStartTime = nil;
    elseif petJob == data.JOB_PUP then
        data.petType = 'automaton';
        data.petExpireTime = nil;  -- Automatons don't expire on timer
        data.charmStartTime = nil;
    else
        data.petType = nil;
        data.petExpireTime = nil;
        data.charmStartTime = nil;
    end

    -- Persist timer data for session survival
    if gConfig then
        gConfig.petBarPetSummonTime = data.petSummonTime;
        gConfig.petBarPetExpireTime = data.petExpireTime;
        gConfig.petBarPetType = data.petType;
        gConfig.petBarPetName = petName;
        gConfig.petBarCharmStartTime = data.charmStartTime;
    end
end

-- Restore timers from persisted config (called on addon load)
function data.RestoreTimersFromConfig()
    if gConfig == nil then return; end

    -- Check if we have persisted timer data
    if gConfig.petBarPetSummonTime and gConfig.petBarPetName then
        local now = os.time();

        -- For jug pets, check if timer hasn't expired
        if gConfig.petBarPetExpireTime then
            if gConfig.petBarPetExpireTime > now then
                -- Timer still valid, restore it
                data.petSummonTime = gConfig.petBarPetSummonTime;
                data.petExpireTime = gConfig.petBarPetExpireTime;
                data.petType = gConfig.petBarPetType;
                data.lastTrackedPetName = gConfig.petBarPetName;
                data.charmStartTime = gConfig.petBarCharmStartTime;
            else
                -- Timer expired, clear persisted data
                gConfig.petBarPetSummonTime = nil;
                gConfig.petBarPetExpireTime = nil;
                gConfig.petBarPetType = nil;
                gConfig.petBarPetName = nil;
                gConfig.petBarCharmStartTime = nil;
            end
        elseif gConfig.petBarCharmStartTime then
            -- Charm timer - restore if it was within last 30 min (reasonable max)
            if now - gConfig.petBarCharmStartTime < 1800 then
                data.petSummonTime = gConfig.petBarPetSummonTime;
                data.petType = gConfig.petBarPetType;
                data.lastTrackedPetName = gConfig.petBarPetName;
                data.charmStartTime = gConfig.petBarCharmStartTime;
            else
                -- Too old, clear
                gConfig.petBarPetSummonTime = nil;
                gConfig.petBarPetExpireTime = nil;
                gConfig.petBarPetType = nil;
                gConfig.petBarPetName = nil;
                gConfig.petBarCharmStartTime = nil;
            end
        end
    end
end

-- Get remaining time for jug pet (in seconds)
function data.GetJugTimeRemaining()
    if data.petType ~= 'jug' or data.petExpireTime == nil then
        return nil;
    end
    local remaining = data.petExpireTime - os.time();
    return math.max(0, remaining);
end

-- Get elapsed time for charm (in seconds)
function data.GetCharmElapsedTime()
    if data.petType ~= 'charm' or data.charmStartTime == nil then
        return nil;
    end
    return os.time() - data.charmStartTime;
end

-- Format seconds to MM:SS string
function data.FormatTimeMMSS(seconds)
    if seconds == nil then return nil; end
    local mins = math.floor(seconds / 60);
    local secs = math.floor(seconds % 60);
    return string.format('%d:%02d', mins, secs);
end

-- Get settings key for a pet name (converts to lowercase, removes spaces)
function data.GetPetSettingsKey(petName)
    if petName == nil then return nil; end
    return petName:lower():gsub(' ', '');
end

-- Get the image path for a pet by name
function data.GetPetImagePath(petName)
    if petName == nil then return nil; end
    local imageFile = data.petImageMap[petName];
    if imageFile then
        return string.format('%s/assets/pets/%s', addon.path, imageFile);
    end
    return nil;
end

-- ============================================
-- State Variables
-- ============================================

-- Font objects (main pet bar)
data.nameText = nil;
data.distanceText = nil;
data.hpText = nil;
data.mpText = nil;
data.tpText = nil;
data.allFonts = nil;

-- Cached colors
data.lastNameColor = nil;
data.lastDistanceColor = nil;
data.lastHpColor = nil;
data.lastMpColor = nil;
data.lastTpColor = nil;

-- Pet target tracking (from packet data)
data.petTargetServerId = nil;

-- Current pet name (for image loading)
data.currentPetName = nil;

-- Pet timer tracking (jug pets and charm)
data.petSummonTime = nil;       -- os.time() when pet was summoned
data.petExpireTime = nil;       -- os.time() when pet will despawn (jug only)
data.petType = nil;             -- 'jug', 'charm', 'avatar', 'wyvern', 'automaton'
data.lastTrackedPetName = nil;  -- Track pet name changes to detect new summons
data.charmStartTime = nil;      -- os.time() when charm started (for elapsed timer)

-- Background primitives
data.backgroundPrim = {};
data.loadedBgName = nil;

-- Pet image primitive (overlay on background)
data.petImagePrim = nil;

-- Pet image textures for ImGui rendering (used when clip mode enabled)
data.petImageTextures = {};

-- Clipped pet image render info (set by UpdateBackground, rendered by display)
data.clippedPetImageInfo = nil;

-- Ability timer tracking
data.abilityMaxTimers = {};

-- Window positioning (shared with pet target)
data.lastMainWindowPosX = 0;
data.lastMainWindowBottom = 0;
data.lastTotalRowWidth = 150;
data.lastWindowFlags = nil;
data.lastColorConfig = nil;
data.lastSettings = nil;

-- Cached window flags
local baseWindowFlags = nil;

-- ============================================
-- Helper Functions
-- ============================================

-- Get cached base window flags
function data.getBaseWindowFlags()
    if baseWindowFlags == nil then
        baseWindowFlags = bit.bor(
            ImGuiWindowFlags_NoDecoration,
            ImGuiWindowFlags_AlwaysAutoResize,
            ImGuiWindowFlags_NoFocusOnAppearing,
            ImGuiWindowFlags_NoNav,
            ImGuiWindowFlags_NoBackground,
            ImGuiWindowFlags_NoBringToFrontOnFocus,
            ImGuiWindowFlags_NoDocking
        );
    end
    return baseWindowFlags;
end

-- Get pet entity from player's pet target index
function data.GetPetEntity()
    local playerEntity = GetPlayerEntity();
    if playerEntity == nil or playerEntity.PetTargetIndex == 0 then
        return nil;
    end
    return GetEntity(playerEntity.PetTargetIndex);
end

-- Get entity by server ID
function data.GetEntityByServerId(sid)
    if sid == nil or sid == 0 then return nil; end
    for x = 0, 2303 do
        local ent = GetEntity(x);
        if ent ~= nil and ent.ServerId == sid then
            return ent;
        end
    end
    return nil;
end

-- Get primary pet job (main takes precedence)
function data.GetPetJob()
    local player = GetPlayerSafe();
    if player == nil then return nil; end

    local mainJob = player:GetMainJob();
    local subJob = player:GetSubJob();

    if mainJob == data.JOB_SMN or mainJob == data.JOB_BST or mainJob == data.JOB_DRG or mainJob == data.JOB_PUP then
        return mainJob;
    elseif subJob == data.JOB_SMN or subJob == data.JOB_BST or subJob == data.JOB_DRG or subJob == data.JOB_PUP then
        return subJob;
    end
    return nil;
end

-- Get pet data - single entry point for both preview and real data
-- This follows the partylist pattern where preview is handled inside the data function
function data.GetPetData()
    -- Preview check inside data function (like partylist's GetMemberInformation)
    if showConfig[1] and gConfig.petBarPreview then
        local previewType = gConfig.petBarPreviewType or data.PREVIEW_AVATAR;
        return data.GetPreviewPetData(previewType);
    end

    -- Real data
    local player = GetPlayerSafe();
    local party = GetPartySafe();
    local playerEnt = GetPlayerEntity();

    if player == nil or party == nil or playerEnt == nil then
        -- No pet - clear tracking
        data.TrackPetSummon(nil, nil);
        return nil;
    end

    if player.isZoning or player:GetMainJob() == 0 then
        return nil;
    end

    local pet = data.GetPetEntity();
    if pet == nil then
        -- No pet - clear tracking
        data.TrackPetSummon(nil, nil);
        return nil;
    end

    local petJob = data.GetPetJob();
    local showMp = petJob == data.JOB_SMN or petJob == data.JOB_PUP;
    local petName = pet.Name or 'Pet';

    -- Track pet summon for timer tracking
    data.TrackPetSummon(petName, petJob);

    -- Calculate pet level
    local playerLevel = player:GetMainJobLevel();
    if petJob and petJob ~= player:GetMainJob() then
        playerLevel = player:GetSubJobLevel();
    end
    local petLevel = data.GetPetLevel(petName, playerLevel);

    -- Check pet type and get timer info
    local isJug = data.IsJugPet(petName);
    local isCharmed = (data.petType == 'charm');
    local jugTimeRemaining = data.GetJugTimeRemaining();
    local charmElapsed = data.GetCharmElapsedTime();

    return {
        name = petName,
        hpPercent = pet.HPPercent or 0,
        distance = math.sqrt(pet.Distance),
        mpPercent = player:GetPetMPPercent() or 0,
        tp = player:GetPetTP() or 0,
        job = petJob,
        showMp = showMp,
        -- New fields
        level = petLevel,
        isJug = isJug,
        isCharmed = isCharmed,
        jugTimeRemaining = jugTimeRemaining,
        charmElapsed = charmElapsed,
        petType = data.petType,
    };
end

-- Format timer from frames to readable string
function data.FormatTimer(frames)
    if frames <= 0 then return 'Ready'; end
    local seconds = frames / 60;
    if seconds >= 60 then
        local mins = math.floor(seconds / 60);
        local secs = math.floor(seconds % 60);
        return string.format('%d:%02d', mins, secs);
    else
        return string.format('%ds', math.floor(seconds));
    end
end

-- Check if an ability should be shown based on config settings
local function ShouldShowAbility(name, petJob)
    if petJob == data.JOB_SMN then
        if name:find('Blood Pact') then
            if name:find('Rage') then
                return gConfig.petBarSmnShowBPRage ~= false;
            elseif name:find('Ward') then
                return gConfig.petBarSmnShowBPWard ~= false;
            else
                return gConfig.petBarSmnShowBPRage ~= false or gConfig.petBarSmnShowBPWard ~= false;
            end
        elseif name == 'Astral Flow' then return gConfig.petBarShow2HourAbility;
        elseif name == 'Apogee' then return gConfig.petBarSmnShowApogee ~= false;
        elseif name == 'Mana Cede' then return gConfig.petBarSmnShowManaCede ~= false;
        end
    elseif petJob == data.JOB_BST then
        if name == 'Ready' then return gConfig.petBarBstShowReady ~= false;
        elseif name == 'Sic' then return gConfig.petBarBstShowSic ~= false;
        elseif name == 'Reward' then return gConfig.petBarBstShowReward ~= false;
        elseif name == 'Call Beast' then return gConfig.petBarBstShowCallBeast ~= false;
        elseif name == 'Bestial Loyalty' then return gConfig.petBarBstShowBestialLoyalty ~= false;
        elseif name == 'Familiar' then return gConfig.petBarShow2HourAbility;
        end
    elseif petJob == data.JOB_DRG then
        if name == 'Call Wyvern' then return gConfig.petBarDrgShowCallWyvern ~= false;
        elseif name == 'Spirit Link' then return gConfig.petBarDrgShowSpiritLink ~= false;
        elseif name == 'Deep Breathing' then return gConfig.petBarDrgShowDeepBreathing ~= false;
        elseif name == 'Steady Wing' then return gConfig.petBarDrgShowSteadyWing ~= false;
        elseif name == 'Spirit Surge' then return gConfig.petBarShow2HourAbility;
        end
    elseif petJob == data.JOB_PUP then
        if name == 'Activate' then return gConfig.petBarPupShowActivate ~= false;
        elseif name == 'Repair' then return gConfig.petBarPupShowRepair ~= false;
        elseif name == 'Deus Ex Automata' then return gConfig.petBarPupShowDeusExAutomata ~= false;
        elseif name == 'Deploy' then return gConfig.petBarPupShowDeploy ~= false;
        elseif name == 'Deactivate' then return gConfig.petBarPupShowDeactivate ~= false;
        elseif name == 'Retrieve' then return gConfig.petBarPupShowRetrieve ~= false;
        elseif name == 'Overdrive' then return gConfig.petBarShow2HourAbility;
        end
    end
    return false;
end

-- Mock ability data for preview mode
local mockAbilities = {
    [data.JOB_SMN] = {
        {name = 'Blood Pact: Rage', timer = 0, maxTimer = 60, isReady = true},
        {name = 'Blood Pact: Ward', timer = 30, maxTimer = 60, isReady = false},
        {name = 'Apogee', timer = 0, maxTimer = 60, isReady = true},
        {name = 'Mana Cede', timer = 45, maxTimer = 60, isReady = false},
    },
    [data.JOB_BST] = {
        {name = 'Ready', timer = 0, maxTimer = 30, isReady = true},
        {name = 'Sic', timer = 10, maxTimer = 30, isReady = false},
        {name = 'Reward', timer = 0, maxTimer = 90, isReady = true},
        {name = 'Call Beast', timer = 20, maxTimer = 60, isReady = false},
    },
    [data.JOB_DRG] = {
        {name = 'Call Wyvern', timer = 0, maxTimer = 20, isReady = true},
        {name = 'Spirit Link', timer = 30, maxTimer = 120, isReady = false},
        {name = 'Deep Breathing', timer = 0, maxTimer = 60, isReady = true},
        {name = 'Steady Wing', timer = 40, maxTimer = 120, isReady = false},
    },
    [data.JOB_PUP] = {
        {name = 'Activate', timer = 0, maxTimer = 60, isReady = true},
        {name = 'Repair', timer = 15, maxTimer = 180, isReady = false},
        {name = 'Deploy', timer = 0, maxTimer = 60, isReady = true},
        {name = 'Retrieve', timer = 10, maxTimer = 30, isReady = false},
    },
};

-- ============================================
-- Ability Recast Memory Reading (like PetMe)
-- ============================================

-- Memory pointer for ability recasts (initialized on first use)
local AbilityRecastPointer = nil;

-- Initialize the ability recast pointer by scanning memory
local function InitAbilityRecastPointer()
    if AbilityRecastPointer ~= nil then return true; end

    -- Memory pattern from PetMe addon
    local pointer = ashita.memory.find('FFXiMain.dll', 0,
        '894124E9????????8B46??6A006A00508BCEE8', 0x19, 0);

    if pointer == 0 then
        print('[PetBar] Failed to find AbilityRecastPointer');
        return false;
    end

    AbilityRecastPointer = ashita.memory.read_uint32(pointer);
    print('[PetBar] AbilityRecastPointer initialized: ' .. string.format('0x%X', AbilityRecastPointer));
    return true;
end

-- Get ability timer data by ability ID (direct memory read)
local function GetAbilityTimerById(abilityId)
    if not InitAbilityRecastPointer() then
        return nil;
    end

    for i = 1, 31 do
        local compId = ashita.memory.read_uint8(AbilityRecastPointer + (i * 8) + 3);
        if compId == abilityId then
            local recast = ashita.memory.read_uint32(AbilityRecastPointer + (i * 4) + 0xF8);
            return recast;
        end
    end

    return 0;  -- Not found or ready
end

-- Get job from preview type (for preview mode)
local function GetPreviewJob(previewType)
    if previewType == data.PREVIEW_WYVERN then
        return data.JOB_DRG;
    elseif previewType == data.PREVIEW_AVATAR then
        return data.JOB_SMN;
    elseif previewType == data.PREVIEW_AUTOMATON then
        return data.JOB_PUP;
    else -- PREVIEW_JUG or PREVIEW_CHARMED
        return data.JOB_BST;
    end
end

-- Get pet ability timers - single entry point for both preview and real data
-- This follows the partylist pattern where preview is handled inside the data function
function data.GetPetAbilityTimers()
    local timers = {};

    -- Preview check FIRST (before getting real job) - like partylist's GetMemberInformation
    if showConfig[1] and gConfig.petBarPreview then
        -- Derive job from preview type, not real player job
        local previewType = gConfig.petBarPreviewType or data.PREVIEW_AVATAR;
        local petJob = GetPreviewJob(previewType);

        local mockData = mockAbilities[petJob];
        if mockData then
            for _, ability in ipairs(mockData) do
                if ShouldShowAbility(ability.name, petJob) then
                    table.insert(timers, ability);
                end
            end
        end
        return timers;
    end

    -- Real mode: get actual pet job
    local petJob = data.GetPetJob();
    if not petJob then return timers; end

    -- Pet ability IDs for direct memory reading
    -- These are the actual ability IDs used by the game
    local petAbilityIds = {
        [data.JOB_SMN] = {
            {id = 173, name = 'Blood Pact: Rage', maxTimer = 3600},
            {id = 174, name = 'Blood Pact: Ward', maxTimer = 3600},
            {id = 254, name = 'Apogee', maxTimer = 3600},
            {id = 255, name = 'Mana Cede', maxTimer = 3600},
        },
        [data.JOB_BST] = {
            {id = 102, name = 'Call Beast', maxTimer = 3600},
            {id = 94, name = 'Reward', maxTimer = 5400},
            {id = 103, name = 'Sic', maxTimer = 1800},
        },
        [data.JOB_DRG] = {
            {id = 163, name = 'Call Wyvern', maxTimer = 72000},
            {id = 164, name = 'Spirit Link', maxTimer = 7200},
            {id = 221, name = 'Deep Breathing', maxTimer = 3600},
            {id = 224, name = 'Steady Wing', maxTimer = 7200},
        },
        [data.JOB_PUP] = {
            {id = 205, name = 'Activate', maxTimer = 3600},
            {id = 206, name = 'Repair', maxTimer = 10800},
            {id = 210, name = 'Deploy', maxTimer = 3600},
            {id = 209, name = 'Deactivate', maxTimer = 3600},
            {id = 211, name = 'Retrieve', maxTimer = 3600},
            {id = 242, name = 'Deus Ex Automata', maxTimer = 3600},
        },
    };

    local abilityList = petAbilityIds[petJob];
    if not abilityList then return timers; end

    -- Use direct memory reading to get ability timers (like PetMe)
    for _, abilityInfo in ipairs(abilityList) do
        local name = abilityInfo.name;

        if ShouldShowAbility(name, petJob) then
            local timer = GetAbilityTimerById(abilityInfo.id);
            if timer ~= nil then
                local maxTimer = abilityInfo.maxTimer;
                if timer > 0 then
                    if data.abilityMaxTimers[name] == nil or timer > data.abilityMaxTimers[name] then
                        data.abilityMaxTimers[name] = timer;
                    end
                    maxTimer = data.abilityMaxTimers[name] or maxTimer;
                else
                    data.abilityMaxTimers[name] = nil;
                end

                table.insert(timers, {
                    name = name,
                    timer = timer,
                    maxTimer = maxTimer,
                    formatted = data.FormatTimer(timer),
                    isReady = timer <= 0,
                });
            end
        end
    end

    return timers;
end

-- ============================================
-- Background Primitive Helpers
-- ============================================

-- Hide all background primitives
function data.HideBackground()
    -- Hide background and borders using windowbackground library
    windowBg.hide(data.backgroundPrim);

    -- Hide all pet image primitives (petbar-specific)
    if data.petImagePrims then
        for _, prim in pairs(data.petImagePrims) do
            if prim then
                prim.visible = false;
            end
        end
    end
end

-- Update background primitives position and visibility
function data.UpdateBackground(x, y, width, height, settings)
    local bgTheme = gConfig.petBarBackgroundTheme or 'Window1';
    local bgOpacity = gConfig.petBarBackgroundOpacity or 1.0;
    local bgColor = gConfig.colorCustomization and gConfig.colorCustomization.petBar and gConfig.colorCustomization.petBar.bgColor or 0xFFFFFFFF;
    local borderColor = gConfig.colorCustomization and gConfig.colorCustomization.petBar and gConfig.colorCustomization.petBar.borderColor or 0xFFFFFFFF;
    local borderOpacity = gConfig.petBarBorderOpacity or 1.0;

    -- Common options for windowbackground library
    local bgOptions = {
        theme = bgTheme,
        padding = settings.bgPadding or data.PADDING,
        paddingY = settings.bgPaddingY or data.PADDING,
        bgScale = settings.bgScale or 1.0,
        bgOpacity = bgOpacity,
        bgColor = bgColor,
        borderSize = settings.borderSize or 21,
        bgOffset = settings.bgOffset or 1,
        borderOpacity = borderOpacity,
        borderColor = borderColor,
    };

    -- Update background and borders using windowbackground library
    windowBg.update(data.backgroundPrim, x, y, width, height, bgOptions);

    -- Pet image overlay (petbar-specific - show correct avatar based on current pet)
    -- Clear clipped image info
    data.clippedPetImageInfo = nil;

    -- First hide all pet image primitives
    if data.petImagePrims then
        for _, prim in pairs(data.petImagePrims) do
            if prim then
                prim.visible = false;
            end
        end
    end

    -- Show current pet's image if we have one and setting is enabled
    if gConfig.petBarShowImage and data.currentPetName and data.petImagePrims then
        local petKey = data.GetPetSettingsKey(data.currentPetName);
        local prim = data.petImagePrims[petKey];
        if prim and prim.exists then
            -- Get per-avatar settings, fall back to legacy global settings
            local avatarSettings = gConfig.petBarAvatarSettings and gConfig.petBarAvatarSettings[petKey];
            local petImageScale, petImageOpacity, petImageOffsetX, petImageOffsetY, clipToBackground;

            if avatarSettings then
                petImageScale = avatarSettings.scale or 0.4;
                petImageOpacity = avatarSettings.opacity or 0.3;
                petImageOffsetX = avatarSettings.offsetX or 0;
                petImageOffsetY = avatarSettings.offsetY or 0;
                clipToBackground = avatarSettings.clipToBackground or false;
            else
                -- Fall back to legacy global settings
                petImageScale = gConfig.petBarImageScale or 0.4;
                petImageOpacity = gConfig.petBarImageOpacity or 0.3;
                petImageOffsetX = gConfig.petBarImageOffsetX or 0;
                petImageOffsetY = gConfig.petBarImageOffsetY or 0;
                clipToBackground = false;
            end

            -- Calculate base image position and dimensions
            local imgX = x + petImageOffsetX;
            local imgY = y + petImageOffsetY;
            local baseWidth = prim.baseWidth or 256;
            local baseHeight = prim.baseHeight or 256;
            local imgWidth = baseWidth * petImageScale;
            local imgHeight = baseHeight * petImageScale;

            -- Convert 0-1 opacity to alpha byte (0x00-0xFF), keep RGB as white
            local alphaByte = math.floor(petImageOpacity * 255);
            local color = bit.bor(bit.lshift(alphaByte, 24), 0x00FFFFFF);

            if clipToBackground then
                -- Get clip bounds using windowbackground library
                local clipBounds = windowBg.getClipBounds(x, y, width, height, {
                    theme = bgTheme,
                    padding = settings.bgPadding or data.PADDING,
                    paddingY = settings.bgPaddingY or data.PADDING,
                    bgOffset = settings.bgOffset or 1,
                });

                -- Clip image to background bounds
                local clipped = windowBg.clipImageToBounds(imgX, imgY, imgWidth, imgHeight, clipBounds, petImageScale);

                if clipped then
                    prim.visible = true;
                    prim.position_x = clipped.x;
                    prim.position_y = clipped.y;
                    prim.texture_offset_x = clipped.texOffsetX;
                    prim.texture_offset_y = clipped.texOffsetY;
                    prim.width = clipped.width;
                    prim.height = clipped.height;
                    prim.scale_x = clipped.scaleX;
                    prim.scale_y = clipped.scaleY;
                    prim.color = color;
                else
                    -- Image is completely outside background bounds
                    prim.visible = false;
                end
            else
                -- No clipping - show full image via primitive
                prim.visible = true;
                prim.position_x = imgX;
                prim.position_y = imgY;
                prim.texture_offset_x = 0;
                prim.texture_offset_y = 0;
                prim.width = baseWidth;
                prim.height = baseHeight;
                prim.scale_x = petImageScale;
                prim.scale_y = petImageScale;
                prim.color = color;
            end
        end
    end
end

-- ============================================
-- Font Visibility Helper
-- ============================================

function data.SetAllFontsVisible(visible)
    if data.allFonts then
        SetFontsVisible(data.allFonts, visible);
    end
end

-- ============================================
-- Clear Cached Colors
-- ============================================

function data.ClearColorCache()
    data.lastNameColor = nil;
    data.lastDistanceColor = nil;
    data.lastHpColor = nil;
    data.lastMpColor = nil;
    data.lastTpColor = nil;
end

-- ============================================
-- Preview Mock Data
-- ============================================

-- Returns mock pet data for preview mode
-- Returns values that match what DrawWindow expects from real pet data
function data.GetPreviewPetData(previewType)
    local mockData = {
        name = 'Pet',
        hpPercent = 85,
        distance = 5.2,
        mpPercent = 75,
        tp = 1200,
        job = nil,
        showMp = false,
        isCharmed = false,
        isJug = false,
        level = nil,
        jugTimeRemaining = nil,
        charmElapsed = nil,
        petType = nil,
    };

    if previewType == data.PREVIEW_WYVERN then
        mockData.name = 'Wyvern';
        mockData.hpPercent = 85;
        mockData.distance = 5.2;
        mockData.mpPercent = 0;
        mockData.tp = 1200;
        mockData.job = data.JOB_DRG;
        mockData.showMp = false;
        mockData.level = 75;
        mockData.petType = 'wyvern';
    elseif previewType == data.PREVIEW_AVATAR then
        mockData.name = 'Ifrit';
        mockData.hpPercent = 100;
        mockData.distance = 8.5;
        mockData.mpPercent = 75;
        mockData.tp = 800;
        mockData.job = data.JOB_SMN;
        mockData.showMp = true;
        mockData.level = 75;
        mockData.petType = 'avatar';
    elseif previewType == data.PREVIEW_AUTOMATON then
        mockData.name = 'Automaton';
        mockData.hpPercent = 90;
        mockData.distance = 3.1;
        mockData.mpPercent = 60;
        mockData.tp = 1500;
        mockData.job = data.JOB_PUP;
        mockData.showMp = true;
        mockData.level = 75;
        mockData.petType = 'automaton';
    elseif previewType == data.PREVIEW_JUG then
        mockData.name = 'FunguarFamiliar';
        mockData.hpPercent = 70;
        mockData.distance = 6.8;
        mockData.mpPercent = 0;
        mockData.tp = 500;
        mockData.job = data.JOB_BST;
        mockData.showMp = false;
        mockData.isJug = true;
        mockData.level = 35;  -- FunguarFamiliar max level
        mockData.jugTimeRemaining = 2732;  -- ~45 minutes remaining
        mockData.petType = 'jug';
    elseif previewType == data.PREVIEW_CHARMED then
        mockData.name = 'Goblin Gambler';
        mockData.hpPercent = 45;
        mockData.distance = 4.5;
        mockData.mpPercent = 0;
        mockData.tp = 2000;
        mockData.job = data.JOB_BST;
        mockData.showMp = false;
        mockData.isCharmed = true;
        mockData.level = nil;  -- Unknown for charmed pets
        mockData.charmElapsed = 183;  -- ~3 minutes elapsed
        mockData.petType = 'charm';
    end

    return mockData;
end

-- ============================================
-- State Reset
-- ============================================

function data.Reset()
    data.nameText = nil;
    data.distanceText = nil;
    data.hpText = nil;
    data.mpText = nil;
    data.tpText = nil;
    data.allFonts = nil;
    data.backgroundPrim = {};
    data.petImagePrim = nil;
    data.petImageTextures = {};
    data.clippedPetImageInfo = nil;
    data.petTargetServerId = nil;
    data.currentPetName = nil;
    data.abilityMaxTimers = {};
    data.loadedBgName = nil;
    -- Pet timer tracking reset
    data.petSummonTime = nil;
    data.petExpireTime = nil;
    data.petType = nil;
    data.lastTrackedPetName = nil;
    data.charmStartTime = nil;
    data.ClearColorCache();
end

return data;
