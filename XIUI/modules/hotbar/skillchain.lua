--[[
* XIUI Hotbar - Skillchain Prediction Module
* Based on tHotBar's skillchain implementation by Thorny
* Tracks weapon skill usage and predicts resulting skillchains
]]--

require('common');

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

-- Resonation names for display (index = resonation ID)
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
    'Light',      -- Light2
    'Darkness',   -- Darkness2
    'Light',      -- Radiance
    'Darkness',   -- Umbra
};

-- Possible skillchain combinations: {result, opening, closing}
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

-- Message IDs that indicate a skillchain occurred
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

-- Message IDs that indicate a weapon skill hit
local weaponskillMessageIds = {
    [103] = true, -- WS recovers HP
    [185] = true, -- WS deals damage
    [187] = true, -- WS drains HP
    [238] = true, -- WS recovers HP (alt)
};

-- Weapon skill resonation attributes (wsId -> table of resonation types)
local weaponskillResonationMap = {
    [1] = { Resonation.Impaction }, --Combo
    [2] = { Resonation.Reverberation, Resonation.Impaction }, --Shoulder Tackle
    [3] = { Resonation.Compression }, --One Inch Punch
    [4] = { Resonation.Detonation }, --Backhand Blow
    [5] = { Resonation.Impaction }, --Raging Fists
    [6] = { Resonation.Liquefaction, Resonation.Impaction }, --Spinning Attack
    [7] = { Resonation.Transfixion, Resonation.Impaction }, --Howling Fist
    [8] = { Resonation.Fragmentation }, --Dragon Kick
    [9] = { Resonation.Gravitation, Resonation.Liquefaction }, --Asuran Fists
    [10] = { Resonation.Light, Resonation.Fusion }, --Final Heaven
    [11] = { Resonation.Fusion, Resonation.Transfixion }, --Ascetic's Fury
    [12] = { Resonation.Gravitation, Resonation.Liquefaction }, --Stringing Pummel
    [13] = { Resonation.Induration, Resonation.Detonation, Resonation.Impaction }, --Tornado Kick
    [14] = { Resonation.Light, Resonation.Fragmentation }, --Victory Smite
    [15] = { Resonation.Fusion, Resonation.Reverberation }, --Shijin Spiral
    [16] = { Resonation.Scission }, --Wasp Sting
    [17] = { Resonation.Scission }, --Viper Bite
    [18] = { Resonation.Reverberation }, --Shadowstitch
    [19] = { Resonation.Detonation }, --Gust Slash
    [20] = { Resonation.Detonation, Resonation.Impaction }, --Cyclone
    [23] = { Resonation.Scission, Resonation.Detonation }, --Dancing Edge
    [24] = { Resonation.Fragmentation }, --Shark Bite
    [25] = { Resonation.Gravitation, Resonation.Transfixion }, --Evisceration
    [26] = { Resonation.Darkness, Resonation.Gravitation }, --Mercy Stroke
    [27] = { Resonation.Fusion, Resonation.Compression }, --Mandalic Stab
    [28] = { Resonation.Fragmentation, Resonation.Distortion }, --Mordant Rime
    [29] = { Resonation.Distortion, Resonation.Scission }, --Pyrrhic Kleos
    [30] = { Resonation.Scission, Resonation.Detonation, Resonation.Impaction }, --Aeolian Edge
    [31] = { Resonation.Darkness, Resonation.Distortion }, --Rudra's Storm
    [32] = { Resonation.Scission }, --Fast Blade
    [33] = { Resonation.Liquefaction }, --Burning Blade
    [34] = { Resonation.Liquefaction, Resonation.Detonation }, --Red Lotus Blade
    [35] = { Resonation.Impaction }, --Flat Blade
    [36] = { Resonation.Scission }, --Shining Blade
    [37] = { Resonation.Scission }, --Seraph Blade
    [38] = { Resonation.Reverberation, Resonation.Impaction }, --Circle Blade
    [40] = { Resonation.Scission, Resonation.Impaction }, --Vorpal Blade
    [41] = { Resonation.Gravitation }, --Swift Blade
    [42] = { Resonation.Fragmentation, Resonation.Scission }, --Savage Blade
    [43] = { Resonation.Light, Resonation.Fusion }, --Knights of Round
    [44] = { Resonation.Fragmentation, Resonation.Distortion }, --Death Blossom
    [45] = { Resonation.Fusion, Resonation.Reverberation }, --Atonement
    [46] = { Resonation.Distortion, Resonation.Scission }, --Expiacion
    [48] = { Resonation.Scission }, --Hard Slash
    [49] = { Resonation.Transfixion }, --Power Slash
    [50] = { Resonation.Induration }, --Frostbite
    [51] = { Resonation.Induration, Resonation.Detonation }, --Freezebite
    [52] = { Resonation.Reverberation }, --Shockwave
    [53] = { Resonation.Scission }, --Crescent Moon
    [54] = { Resonation.Scission, Resonation.Impaction }, --Sickle Moon
    [55] = { Resonation.Fragmentation }, --Spinning Slash
    [56] = { Resonation.Fragmentation, Resonation.Distortion }, --Ground Strike
    [57] = { Resonation.Light, Resonation.Fusion }, --Scourge
    [58] = { Resonation.Induration, Resonation.Detonation, Resonation.Impaction }, --Herculean Slash
    [59] = { Resonation.Light, Resonation.Distortion }, --Torcleaver
    [60] = { Resonation.Fragmentation, Resonation.Scission }, --Resolution
    [61] = { Resonation.Light, Resonation.Fragmentation }, --Dimidiation
    [64] = { Resonation.Detonation, Resonation.Impaction }, --Raging Axe
    [65] = { Resonation.Induration, Resonation.Reverberation }, --Smash Axe
    [66] = { Resonation.Detonation }, --Gale Axe
    [67] = { Resonation.Scission, Resonation.Impaction }, --Avalanche Axe
    [68] = { Resonation.Liquefaction, Resonation.Scission, Resonation.Impaction }, --Spinning Axe
    [69] = { Resonation.Scission }, --Rampage
    [70] = { Resonation.Scission, Resonation.Impaction }, --Calamity
    [71] = { Resonation.Fusion }, --Mistral Axe
    [72] = { Resonation.Fusion, Resonation.Reverberation }, --Decimation
    [73] = { Resonation.Darkness, Resonation.Gravitation }, --Onslaught
    [74] = { Resonation.Gravitation, Resonation.Reverberation }, --Primal Rend
    [75] = { Resonation.Scission, Resonation.Detonation }, --Bora Axe
    [76] = { Resonation.Darkness, Resonation.Fragmentation }, --Cloudsplitter
    [77] = { Resonation.Distortion, Resonation.Detonation }, --Ruinator
    [80] = { Resonation.Impaction }, --Shield Break
    [81] = { Resonation.Scission }, --Iron Tempest
    [82] = { Resonation.Reverberation, Resonation.Scission }, --Sturmwind
    [83] = { Resonation.Impaction }, --Armor Break
    [84] = { Resonation.Compression }, --Keen Edge
    [85] = { Resonation.Impaction }, --Weapon Break
    [86] = { Resonation.Induration, Resonation.Reverberation }, --Raging Rush
    [87] = { Resonation.Distortion }, --Full Break
    [88] = { Resonation.Distortion, Resonation.Detonation }, --Steel Cyclone
    [89] = { Resonation.Light, Resonation.Fusion }, --Metatron Torment
    [90] = { Resonation.Fragmentation, Resonation.Scission }, --King's Justice
    [91] = { Resonation.Scission, Resonation.Detonation, Resonation.Impaction }, --Fell Cleave
    [92] = { Resonation.Light, Resonation.Fragmentation }, --Ukko's Fury
    [93] = { Resonation.Fusion, Resonation.Compression }, --Upheaval
    [96] = { Resonation.Scission }, --Slice
    [97] = { Resonation.Reverberation }, --Dark Harvest
    [98] = { Resonation.Induration, Resonation.Reverberation }, --Shadow of Death
    [99] = { Resonation.Compression, Resonation.Scission }, --Nightmare Scythe
    [100] = { Resonation.Reverberation, Resonation.Scission }, --Spinning Scythe
    [101] = { Resonation.Transfixion, Resonation.Scission }, --Vorpal Scythe
    [102] = { Resonation.Induration }, --Guillotine
    [103] = { Resonation.Distortion }, --Cross Reaper
    [104] = { Resonation.Distortion, Resonation.Scission }, --Spiral Hell
    [105] = { Resonation.Darkness, Resonation.Gravitation }, --Catastrophe
    [106] = { Resonation.Fusion, Resonation.Compression }, --Insurgency
    [107] = { Resonation.Compression, Resonation.Reverberation }, --Infernal Scythe
    [108] = { Resonation.Darkness, Resonation.Distortion }, --Quietus
    [109] = { Resonation.Gravitation, Resonation.Reverberation }, --Entropy
    [112] = { Resonation.Transfixion }, --Double Thrust
    [113] = { Resonation.Transfixion, Resonation.Impaction }, --Thunder Thrust
    [114] = { Resonation.Transfixion, Resonation.Impaction }, --Raiden Thrust
    [115] = { Resonation.Impaction }, --Leg Sweep
    [116] = { Resonation.Compression }, --Penta Thrust
    [117] = { Resonation.Reverberation, Resonation.Transfixion }, --Vorpal Thrust
    [118] = { Resonation.Transfixion, Resonation.Impaction }, --Skewer
    [119] = { Resonation.Fusion }, --Wheeling Thrust
    [120] = { Resonation.Gravitation, Resonation.Induration }, --Impulse Drive
    [121] = { Resonation.Light, Resonation.Distortion }, --Geirskogul
    [122] = { Resonation.Fusion, Resonation.Transfixion }, --Drakesbane
    [123] = { Resonation.Transfixion, Resonation.Scission }, --Sonic Thrust
    [124] = { Resonation.Light, Resonation.Fragmentation }, --Camlann's Torment
    [125] = { Resonation.Gravitation, Resonation.Transfixion }, --Stardiver
    [128] = { Resonation.Transfixion }, --Blade: Rin
    [129] = { Resonation.Scission }, --Blade: Retsu
    [130] = { Resonation.Reverberation }, --Blade: Teki
    [131] = { Resonation.Induration, Resonation.Detonation }, --Blade: To
    [132] = { Resonation.Transfixion, Resonation.Impaction }, --Blade: Chi
    [133] = { Resonation.Compression }, --Blade: Ei
    [134] = { Resonation.Detonation, Resonation.Impaction }, --Blade: Jin
    [135] = { Resonation.Gravitation }, --Blade: Ten
    [136] = { Resonation.Gravitation, Resonation.Transfixion }, --Blade: Ku
    [137] = { Resonation.Darkness, Resonation.Fragmentation }, --Blade: Metsu
    [138] = { Resonation.Fragmentation, Resonation.Compression }, --Blade: Kamu
    [139] = { Resonation.Reverberation, Resonation.Scission }, --Blade: Yu
    [140] = { Resonation.Darkness, Resonation.Gravitation }, --Blade: Hi
    [141] = { Resonation.Fusion, Resonation.Impaction }, --Blade: Shun
    [144] = { Resonation.Transfixion, Resonation.Scission }, --Tachi: Enpi
    [145] = { Resonation.Induration }, --Tachi: Hobaku
    [146] = { Resonation.Transfixion, Resonation.Impaction }, --Tachi: Goten
    [147] = { Resonation.Liquefaction }, --Tachi: Kagero
    [148] = { Resonation.Scission, Resonation.Detonation }, --Tachi: Jinpu
    [149] = { Resonation.Reverberation, Resonation.Impaction }, --Tachi: Koki
    [150] = { Resonation.Induration, Resonation.Detonation }, --Tachi: Yukikaze
    [151] = { Resonation.Distortion, Resonation.Reverberation }, --Tachi: Gekko
    [152] = { Resonation.Fusion, Resonation.Compression }, --Tachi: Kasha
    [153] = { Resonation.Light, Resonation.Fragmentation }, --Tachi: Kaiten
    [154] = { Resonation.Gravitation, Resonation.Induration }, --Tachi: Rana
    [155] = { Resonation.Compression, Resonation.Scission }, --Tachi: Ageha
    [156] = { Resonation.Light, Resonation.Distortion }, --Tachi: Fudo
    [157] = { Resonation.Fragmentation, Resonation.Compression }, --Tachi: Shoha
    [160] = { Resonation.Impaction }, --Shining Strike
    [161] = { Resonation.Impaction }, --Seraph Strike
    [162] = { Resonation.Reverberation }, --Brainshaker
    [165] = { Resonation.Induration, Resonation.Reverberation }, --Skullbreaker
    [166] = { Resonation.Detonation, Resonation.Impaction }, --True Strike
    [167] = { Resonation.Impaction }, --Judgment
    [168] = { Resonation.Fusion }, --Hexa Strike
    [169] = { Resonation.Fragmentation, Resonation.Compression }, --Black Halo
    [170] = { Resonation.Light, Resonation.Fragmentation }, --Randgrith
    [172] = { Resonation.Induration, Resonation.Reverberation }, --Flash Nova
    [174] = { Resonation.Fusion, Resonation.Impaction }, --Realmrazer
    [175] = { Resonation.Darkness, Resonation.Fragmentation }, --Exudation
    [176] = { Resonation.Impaction }, --Heavy Swing
    [177] = { Resonation.Impaction }, --Rock Crusher
    [178] = { Resonation.Detonation, Resonation.Impaction }, --Earth Crusher
    [179] = { Resonation.Compression, Resonation.Reverberation }, --Starburst
    [180] = { Resonation.Compression, Resonation.Reverberation }, --Sunburst
    [181] = { Resonation.Detonation }, --Shell Crusher
    [182] = { Resonation.Liquefaction, Resonation.Impaction }, --Full Swing
    [184] = { Resonation.Gravitation, Resonation.Reverberation }, --Retribution
    [185] = { Resonation.Darkness, Resonation.Distortion }, --Gate of Tartarus
    [186] = { Resonation.Fragmentation, Resonation.Distortion }, --Vidohunir
    [187] = { Resonation.Fusion, Resonation.Reverberation }, --Garland of Bliss
    [188] = { Resonation.Gravitation, Resonation.Transfixion }, --Omniscience
    [189] = { Resonation.Compression, Resonation.Reverberation }, --Cataclysm
    [191] = { Resonation.Gravitation, Resonation.Induration }, --Shattersoul
    [192] = { Resonation.Liquefaction, Resonation.Transfixion }, --Flaming Arrow
    [193] = { Resonation.Reverberation, Resonation.Transfixion }, --Piercing Arrow
    [194] = { Resonation.Liquefaction, Resonation.Transfixion }, --Dulling Arrow
    [196] = { Resonation.Reverberation, Resonation.Transfixion, Resonation.Detonation }, --Sidewinder
    [197] = { Resonation.Induration, Resonation.Transfixion }, --Blast Arrow
    [198] = { Resonation.Fusion }, --Arching Arrow
    [199] = { Resonation.Fusion, Resonation.Transfixion }, --Empyreal Arrow
    [200] = { Resonation.Light, Resonation.Distortion }, --Namas Arrow
    [201] = { Resonation.Reverberation, Resonation.Transfixion }, --Refulgent Arrow
    [202] = { Resonation.Light, Resonation.Fusion }, --Jishnu's Radiance
    [203] = { Resonation.Fragmentation, Resonation.Transfixion }, --Apex Arrow
    [208] = { Resonation.Liquefaction, Resonation.Transfixion }, --Hot Shot
    [209] = { Resonation.Reverberation, Resonation.Transfixion }, --Split Shot
    [210] = { Resonation.Liquefaction, Resonation.Transfixion }, --Sniper Shot
    [212] = { Resonation.Reverberation, Resonation.Transfixion, Resonation.Detonation }, --Slug Shot
    [213] = { Resonation.Induration, Resonation.Transfixion }, --Blast Shot
    [214] = { Resonation.Fusion }, --Heavy Shot
    [215] = { Resonation.Fusion, Resonation.Transfixion }, --Detonator
    [216] = { Resonation.Darkness, Resonation.Fragmentation }, --Coronach
    [217] = { Resonation.Fragmentation, Resonation.Scission }, --Trueflight
    [218] = { Resonation.Gravitation, Resonation.Transfixion }, --Leaden Salute
    [219] = { Resonation.Induration, Resonation.Detonation, Resonation.Impaction }, --Numbing Shot
    [220] = { Resonation.Darkness, Resonation.Gravitation }, --Wildfire
    [221] = { Resonation.Fusion, Resonation.Reverberation }, --Last Stand
    [224] = { Resonation.Fragmentation, Resonation.Scission }, --Exenterator
    [225] = { Resonation.Light, Resonation.Distortion }, --Chant du Cygne
    [226] = { Resonation.Gravitation, Resonation.Scission }, --Requiescat
};

-- Per-target resonation state (keyed by entity index, NOT server ID)
-- state = { Attributes = {}, Depth = number, WindowOpen = time, WindowClose = time }
local resonationMap = {};

-- Hardcoded WS name -> ID map (resource manager lookup is unreliable)
local wsNameToIdMap = {
    -- Hand-to-Hand
    ['Combo'] = 1, ['Shoulder Tackle'] = 2, ['One Inch Punch'] = 3, ['Backhand Blow'] = 4,
    ['Raging Fists'] = 5, ['Spinning Attack'] = 6, ['Howling Fist'] = 7, ['Dragon Kick'] = 8,
    ['Asuran Fists'] = 9, ['Final Heaven'] = 10, ["Ascetic's Fury"] = 11, ['Stringing Pummel'] = 12,
    ['Tornado Kick'] = 13, ['Victory Smite'] = 14, ['Shijin Spiral'] = 15,
    -- Dagger
    ['Wasp Sting'] = 16, ['Viper Bite'] = 17, ['Shadowstitch'] = 18, ['Gust Slash'] = 19,
    ['Cyclone'] = 20, ['Dancing Edge'] = 23, ['Shark Bite'] = 24, ['Evisceration'] = 25,
    ['Mercy Stroke'] = 26, ['Mandalic Stab'] = 27, ['Mordant Rime'] = 28, ['Pyrrhic Kleos'] = 29,
    ['Aeolian Edge'] = 30, ["Rudra's Storm"] = 31,
    -- Sword
    ['Fast Blade'] = 32, ['Burning Blade'] = 33, ['Red Lotus Blade'] = 34, ['Flat Blade'] = 35,
    ['Shining Blade'] = 36, ['Seraph Blade'] = 37, ['Circle Blade'] = 38, ['Vorpal Blade'] = 40,
    ['Swift Blade'] = 41, ['Savage Blade'] = 42, ['Knights of Round'] = 43, ['Death Blossom'] = 44,
    ['Atonement'] = 45, ['Expiacion'] = 46,
    -- Great Sword
    ['Hard Slash'] = 48, ['Power Slash'] = 49, ['Frostbite'] = 50, ['Freezebite'] = 51,
    ['Shockwave'] = 52, ['Crescent Moon'] = 53, ['Sickle Moon'] = 54, ['Spinning Slash'] = 55,
    ['Ground Strike'] = 56, ['Scourge'] = 57, ['Herculean Slash'] = 58, ['Torcleaver'] = 59,
    ['Resolution'] = 60, ['Dimidiation'] = 61,
    -- Axe
    ['Raging Axe'] = 64, ['Smash Axe'] = 65, ['Gale Axe'] = 66, ['Avalanche Axe'] = 67,
    ['Spinning Axe'] = 68, ['Rampage'] = 69, ['Calamity'] = 70, ['Mistral Axe'] = 71,
    ['Decimation'] = 72, ['Onslaught'] = 73, ['Primal Rend'] = 74, ['Bora Axe'] = 75,
    ['Cloudsplitter'] = 76, ['Ruinator'] = 77,
    -- Great Axe
    ['Shield Break'] = 80, ['Iron Tempest'] = 81, ['Sturmwind'] = 82, ['Armor Break'] = 83,
    ['Keen Edge'] = 84, ['Weapon Break'] = 85, ['Raging Rush'] = 86, ['Full Break'] = 87,
    ['Steel Cyclone'] = 88, ['Metatron Torment'] = 89, ["King's Justice"] = 90, ['Fell Cleave'] = 91,
    ["Ukko's Fury"] = 92, ['Upheaval'] = 93,
    -- Scythe
    ['Slice'] = 96, ['Dark Harvest'] = 97, ['Shadow of Death'] = 98, ['Nightmare Scythe'] = 99,
    ['Spinning Scythe'] = 100, ['Vorpal Scythe'] = 101, ['Guillotine'] = 102, ['Cross Reaper'] = 103,
    ['Spiral Hell'] = 104, ['Catastrophe'] = 105, ['Insurgency'] = 106, ['Infernal Scythe'] = 107,
    ['Quietus'] = 108, ['Entropy'] = 109,
    -- Polearm
    ['Double Thrust'] = 112, ['Thunder Thrust'] = 113, ['Raiden Thrust'] = 114, ['Leg Sweep'] = 115,
    ['Penta Thrust'] = 116, ['Vorpal Thrust'] = 117, ['Skewer'] = 118, ['Wheeling Thrust'] = 119,
    ['Impulse Drive'] = 120, ['Geirskogul'] = 121, ['Drakesbane'] = 122, ['Sonic Thrust'] = 123,
    ["Camlann's Torment"] = 124, ['Stardiver'] = 125,
    -- Katana
    ['Blade: Rin'] = 128, ['Blade: Retsu'] = 129, ['Blade: Teki'] = 130, ['Blade: To'] = 131,
    ['Blade: Chi'] = 132, ['Blade: Ei'] = 133, ['Blade: Jin'] = 134, ['Blade: Ten'] = 135,
    ['Blade: Ku'] = 136, ['Blade: Metsu'] = 137, ['Blade: Kamu'] = 138, ['Blade: Yu'] = 139,
    ['Blade: Hi'] = 140, ['Blade: Shun'] = 141,
    -- Great Katana
    ['Tachi: Enpi'] = 144, ['Tachi: Hobaku'] = 145, ['Tachi: Goten'] = 146, ['Tachi: Kagero'] = 147,
    ['Tachi: Jinpu'] = 148, ['Tachi: Koki'] = 149, ['Tachi: Yukikaze'] = 150, ['Tachi: Gekko'] = 151,
    ['Tachi: Kasha'] = 152, ['Tachi: Kaiten'] = 153, ['Tachi: Rana'] = 154, ['Tachi: Ageha'] = 155,
    ['Tachi: Fudo'] = 156, ['Tachi: Shoha'] = 157,
    -- Club
    ['Shining Strike'] = 160, ['Seraph Strike'] = 161, ['Brainshaker'] = 162, ['Skullbreaker'] = 165,
    ['True Strike'] = 166, ['Judgment'] = 167, ['Hexa Strike'] = 168, ['Black Halo'] = 169,
    ['Randgrith'] = 170, ['Flash Nova'] = 172, ['Realmrazer'] = 174, ['Exudation'] = 175,
    -- Staff
    ['Heavy Swing'] = 176, ['Rock Crusher'] = 177, ['Earth Crusher'] = 178, ['Starburst'] = 179,
    ['Sunburst'] = 180, ['Shell Crusher'] = 181, ['Full Swing'] = 182, ['Retribution'] = 184,
    ['Gate of Tartarus'] = 185, ['Vidohunir'] = 186, ['Garland of Bliss'] = 187, ['Omniscience'] = 188,
    ['Cataclysm'] = 189, ['Shattersoul'] = 191,
    -- Archery
    ['Flaming Arrow'] = 192, ['Piercing Arrow'] = 193, ['Dulling Arrow'] = 194, ['Sidewinder'] = 196,
    ['Blast Arrow'] = 197, ['Arching Arrow'] = 198, ['Empyreal Arrow'] = 199, ['Namas Arrow'] = 200,
    ['Refulgent Arrow'] = 201, ["Jishnu's Radiance"] = 202, ['Apex Arrow'] = 203,
    -- Marksmanship
    ['Hot Shot'] = 208, ['Split Shot'] = 209, ['Sniper Shot'] = 210, ['Slug Shot'] = 212,
    ['Blast Shot'] = 213, ['Heavy Shot'] = 214, ['Detonator'] = 215, ['Coronach'] = 216,
    ['Trueflight'] = 217, ['Leaden Salute'] = 218, ['Numbing Shot'] = 219, ['Wildfire'] = 220,
    ['Last Stand'] = 221, ['Exenterator'] = 224, ['Chant du Cygne'] = 225, ['Requiescat'] = 226,
};

-- Debug function to dump skillchain state (call with /xiui scdebug)
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

-- Get WS ID from name (simple lookup in hardcoded table)
local function GetWSIdFromName(wsName)
    if not wsName then return nil; end
    return wsNameToIdMap[wsName];
end

-- Check if a table contains a value
local function tableContains(tbl, val)
    if not tbl then return false; end
    for _, v in ipairs(tbl) do
        if v == val then return true; end
    end
    return false;
end

-- Convert server ID to entity index
local function GetIndexFromId(id)
    local entMgr = AshitaCore:GetMemoryManager():GetEntity();
    if not entMgr then return 0; end

    -- Shortcut for monsters/static npcs
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

-- Get skillchain result for a WS against current target state
-- targetServerId: server ID of the target (can be nil to check all targets)
-- wsIdOrName: weapon skill ID (number) or name (string)
-- Returns skillchain name or nil
function M.GetSkillchainForSlot(targetServerId, wsIdOrName)
    if not wsIdOrName then return nil; end

    -- Convert name to ID if needed
    local wsId = wsIdOrName;
    if type(wsIdOrName) == 'string' then
        wsId = GetWSIdFromName(wsIdOrName);
        if not wsId then return nil; end
    end

    -- Get WS attributes early (needed for all checks)
    local wsAttributes = weaponskillResonationMap[wsId];
    if not wsAttributes then return nil; end

    -- Convert server ID to entity index if provided
    local targetIndex = nil;
    if targetServerId and targetServerId > 0x8FF then
        targetIndex = GetIndexFromId(targetServerId);
    elseif targetServerId and targetServerId > 0 and targetServerId <= 0x8FF then
        targetIndex = targetServerId;  -- Already an entity index
    end

    -- If we have a specific target, check just that one
    -- Otherwise, check ALL tracked targets (fallback when target lookup fails)
    local targetsToCheck = {};
    if targetIndex and targetIndex > 0 then
        targetsToCheck[targetIndex] = resonationMap[targetIndex];
    else
        -- No specific target - check all tracked resonations
        targetsToCheck = resonationMap;
    end

    local now = os.clock();

    -- Check each target for skillchain potential
    for idx, resonation in pairs(targetsToCheck) do
        if resonation then
            -- Check if window is still valid
            if now <= resonation.WindowClose and now >= resonation.WindowOpen then
                -- Check for skillchain match
                for _, sc in ipairs(possibleSkillchains) do
                    local result, opening, closing = sc[1], sc[2], sc[3];
                    if tableContains(resonation.Attributes, opening) then
                        if tableContains(wsAttributes, closing) then
                            return resonationNames[result];
                        end
                    end
                end
            elseif now > resonation.WindowClose then
                -- Window expired, clean up
                resonationMap[idx] = nil;
            end
        end
    end

    return nil;
end

-- Handle action packet (0x0028)
-- XIUI's ParseActionPacket stores WS ID in .Param (not .Id like tHotBar)
function M.HandleActionPacket(actionPacket)
    if not actionPacket then return; end

    -- Only process weapon skill actions (Type 3)
    if actionPacket.Type ~= 3 then return; end

    -- WS ID is stored in Param field by XIUI's packet parser
    local wsId = actionPacket.Param;
    if not wsId or wsId == 0 then return; end

    -- Process each target
    for _, target in ipairs(actionPacket.Targets or {}) do
        local targetIndex = GetIndexFromId(target.Id);
        if targetIndex ~= 0 then
            for _, action in ipairs(target.Actions or {}) do
                -- Check for skillchain message
                local skillchain = nil;
                if action.AdditionalEffect then
                    skillchain = skillchainMessageIds[action.AdditionalEffect.Message];
                end

                if skillchain == Resonation.None then
                    -- Skillchain interrupted
                    resonationMap[targetIndex] = nil;

                elseif skillchain then
                    -- Skillchain occurred - update state
                    local resonation = resonationMap[targetIndex];
                    local now = os.clock();

                    if resonation and (now + 1) > resonation.WindowOpen and (now - 1) < resonation.WindowClose then
                        -- Continuing existing chain
                        resonation.Depth = resonation.Depth + 1;

                        -- Handle Light/Darkness level escalation
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
                        -- New chain from skillchain
                        resonation = {
                            Depth = 1,
                            Attributes = { skillchain },
                            WindowOpen = now + 3.5,
                            WindowClose = now + 8.8,
                        };
                        resonationMap[targetIndex] = resonation;
                    end

                elseif weaponskillMessageIds[action.Message] then
                    -- WS hit without skillchain - set up new resonation
                    local attributes = weaponskillResonationMap[wsId];
                    if attributes then
                        local now = os.clock();
                        resonationMap[targetIndex] = {
                            Depth = 0,
                            Attributes = attributes,
                            -- For UI prediction, show immediately (window opens now)
                            -- Actual skillchain can land ~3-10 seconds after opener
                            WindowOpen = now,
                            WindowClose = now + 10.0,
                        };
                    end
                end
            end
        end
    end
end

-- Clear all state (call on zone change)
function M.ClearState()
    resonationMap = {};
end

-- Clear state for a specific target
function M.ClearTargetState(targetServerId)
    if targetServerId then
        local targetIndex = GetIndexFromId(targetServerId);
        if targetIndex ~= 0 then
            resonationMap[targetIndex] = nil;
        end
    end
end

-- Check if skillchain window is open for any target
function M.IsWindowOpen()
    local now = os.clock();
    for _, state in pairs(resonationMap) do
        if state.WindowOpen and now >= state.WindowOpen and now <= state.WindowClose then
            return true;
        end
    end
    return false;
end

-- Animation helper for marching ants effect
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

-- Get list of all skillchain names (for icon preloading)
function M.GetSkillchainNames()
    return {
        'Compression', 'Darkness', 'Detonation', 'Distortion',
        'Fragmentation', 'Fusion', 'Gravitation', 'Impaction',
        'Induration', 'Light', 'Liquefaction', 'Reverberation',
        'Scission', 'Transfixion',
    };
end

-- Legacy compatibility
function M.GetWSAttributesByName(wsName)
    local wsId = GetWSIdFromName(wsName);
    if wsId then
        return weaponskillResonationMap[wsId], wsId;
    end
    return nil, nil;
end

return M;
