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

-- ============================================
-- Magic Burst (MB) state
-- ============================================
--
-- A Magic Burst window opens IMMEDIATELY when a skillchain CLOSES (the SC's additional-effect
-- message fires on the closing WS's action packet) and stays open for 7.0s — any spell whose
-- ELEMENT matches one of the SC's burstable elements and that FINISHES casting inside the
-- window magic-bursts for bonus damage.
--
-- Note: retail's MB window is ~2s-7s post-WS (you can't burst before ~2s and the window
-- closes around 7s). We open at 0s on purpose so the player gets the visual cue at the
-- earliest possible moment and has the full 7s of slack to start their cast — the actual
-- burst-eligibility timing is enforced server-side anyway, so the only thing affected by
-- the visual is when the highlight is on screen.
--
-- Lifetime rules (per target):
--   * SC fires (skillchainMessageIds match)                  → write magicBurstMap entry,
--     overwriting any prior MB state on this target. Same path catches "another SC happened
--     during the previous MB window" → window restarts with the new SC's elements.
--   * WS lands WITH attributes (weaponskillResonationMap)    → clear magicBurstMap entry.
--     This matches the FFXI mechanic where a new WS overwrites the target's resonance and
--     closes the open MB window even if the new WS itself doesn't chain.
--   * WS lands WITHOUT attributes (Spirits Within etc.)      → MB window untouched. The WS
--     never reaches the weapon-skill-message branch in HandleActionPacket since its row
--     isn't in weaponskillResonationMap, so the no-op is automatic.
--   * Target cleared / window expired (consulted lazily on every Get*)  → entry dropped.
--
-- Window timing constants. Open delay 0 (highlight as soon as the SC packet arrives),
-- duration 7.0 (window closes at SC + 7s). See block comment above for rationale.
local MB_WINDOW_OPEN_DELAY = 0.0;
local MB_WINDOW_DURATION = 7.0;

-- Per-target Magic Burst state (entity index → { Elements, ScName, WindowOpen, WindowClose }).
-- Kept SEPARATE from resonationMap because the two have different lifetimes: resonationMap's
-- WindowOpen/Close describe the NEXT-SC prediction window (3.5–9.8s), MB's describe the
-- ACTUAL magic-burstable window (0.0–7.0s via the MB_WINDOW_* constants below). Trying to
-- share one map would conflate them.
local magicBurstMap = {};

-- Resonation result → list of burstable element IDs. Element IDs match horizonspells.lua's
-- `element` field: 0=Fire, 1=Ice, 2=Wind, 3=Earth, 4=Lightning, 5=Water, 6=Light, 7=Dark.
-- Level-1 SCs map to one element each; Lv2 (Fusion/Frag/Distortion/Gravitation) burst two;
-- Lv3 (Light/Darkness/Radiance/Umbra) burst four. Radiance and Umbra are the depth-3 "Light
-- after Light" / "Darkness after Darkness" upgrades — they burst the same element set.
local magicBurstElements = {
    [Resonation.Liquefaction]   = { 0 },                -- Fire
    [Resonation.Induration]     = { 1 },                -- Ice
    [Resonation.Detonation]     = { 2 },                -- Wind
    [Resonation.Scission]       = { 3 },                -- Earth
    [Resonation.Impaction]      = { 4 },                -- Lightning
    [Resonation.Reverberation]  = { 5 },                -- Water
    [Resonation.Transfixion]    = { 6 },                -- Light
    [Resonation.Compression]    = { 7 },                -- Dark
    [Resonation.Fusion]         = { 0, 6 },             -- Fire + Light
    [Resonation.Fragmentation]  = { 4, 2 },             -- Lightning + Wind
    [Resonation.Distortion]     = { 5, 1 },             -- Water + Ice
    [Resonation.Gravitation]    = { 3, 7 },             -- Earth + Dark
    [Resonation.Light]          = { 0, 6, 4, 2 },       -- Fire/Light/Lightning/Wind
    [Resonation.Darkness]       = { 5, 1, 3, 7 },       -- Water/Ice/Earth/Dark
    [Resonation.Light2]         = { 0, 6, 4, 2 },       -- depth-3 Light upgrade
    [Resonation.Darkness2]      = { 5, 1, 3, 7 },       -- depth-3 Darkness upgrade
    [Resonation.Radiance]       = { 0, 6, 4, 2 },       -- Radiance burst set = Light's
    [Resonation.Umbra]          = { 5, 1, 3, 7 },       -- Umbra burst set = Darkness's
};

-- SMN Magical Blood Pact Rage element overrides. horizon_bloodpacts.lua stores `element = 0`
-- as a placeholder for ALL pact rows (it's a synthetic spell-shaped DB; only mp_cost +
-- smn_lv are authoritative there), so we can't trust the resource for SMN MB eligibility.
-- This is the curated short list: only the spell-named "Magic" Blood Pact: Rages (Fire II,
-- Blizzard IV, etc.). The named flavor rages (Heavenly Strike, Inferno, Judgment Bolt, etc.)
-- and the Astral Flow 1HRs are deliberately OMITTED — the user wants MB highlight scoped to
-- just the BLM-shadow magic pacts. Names match petregistry English so /pet "Fire II" macros
-- and crossbar pet slots resolve via the same name key. Extend cautiously and never add
-- physical pacts here (Punch / Rock Throw / Crescent Fang / etc.) — they'd false-positive.
local bloodPactElementMap = {
    -- Fire (Ifrit)
    ['Fire II']     = 0,
    ['Fire IV']     = 0,
    -- Ice (Shiva)
    ['Blizzard II'] = 1,
    ['Blizzard IV'] = 1,
    -- Wind (Garuda)
    ['Aero II']     = 2,
    ['Aero IV']     = 2,
    -- Earth (Titan)
    ['Stone II']    = 3,
    ['Stone IV']    = 3,
    -- Lightning (Ramuh)
    ['Thunder II']  = 4,
    ['Thunder IV']  = 4,
    -- Water (Leviathan)
    ['Water II']    = 5,
    ['Water IV']    = 5,
};

-- Lazy lookup: lowercase English spell name → element id (0-7), or false if the spell exists
-- but isn't MB-eligible (no enemy-target bit, or non-elemental). Built on first request from
-- horizonspells.lua. Same lazy-cache pattern as actions.lua's spellsByLowerNameLookup, but
-- stays local to this module because MB is its only consumer right now.
--
-- MB eligibility filter (mirrors retail mechanic):
--   * `element` must be in 0-7 (i.e. one of the eight pure elements; 8 = non-elemental excluded)
--   * `targets` must include the enemy bit (32) — drops Protect/Raise/-na/healing-on-friendly
--     even though those rows technically carry a `element` value (most WHM utility spells are
--     element=6 / Light, but they can't be cast on an enemy so they could never magic burst).
local spellElementByLowerName = nil;

local function buildSpellElementLookup()
    spellElementByLowerName = {};
    local ok, horizonSpells = pcall(require, 'modules.hotbar.database.horizonspells');
    if not ok or type(horizonSpells) ~= 'table' then
        return;
    end
    for _, spell in pairs(horizonSpells) do
        if spell.en and spell.en ~= '' then
            local key = string.lower(spell.en);
            if spellElementByLowerName[key] == nil then
                local elem = spell.element;
                local tgts = spell.targets or 0;
                local enemyBit = bit.band(tgts, 32) ~= 0;
                if elem ~= nil and elem >= 0 and elem <= 7 and enemyBit then
                    spellElementByLowerName[key] = elem;
                else
                    spellElementByLowerName[key] = false;
                end
            end
        end
    end
end

local function spellNameToBurstElement(spellName)
    if not spellName or spellName == '' then return nil; end
    if spellElementByLowerName == nil then buildSpellElementLookup(); end
    local v = spellElementByLowerName[string.lower(spellName)];
    if v == false then return nil; end
    return v;  -- number or nil
end

local function pactNameToBurstElement(pactName)
    if not pactName or pactName == '' then return nil; end
    return bloodPactElementMap[pactName];
end

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

-- Blood Pact / avatar physical pacts: English ability name (as in /pet "Name") → Level-1 attributes.
-- Horizon: omit Level 70 pacts with no SC properties (unmapped here — no false resonance).
local bloodPactResonationMap = {
    ['Claw'] = { Resonation.Detonation },
    ['Rock Throw'] = { Resonation.Scission },
    ['Axe Kick'] = { Resonation.Induration },
    ['Punch'] = { Resonation.Liquefaction },
    ['Shock Strike'] = { Resonation.Impaction },
    ['Barracuda Dive'] = { Resonation.Reverberation },
    ['Camisado'] = { Resonation.Compression },
    ['Poison Nails'] = { Resonation.Transfixion },
    ['Moonlit Charge'] = { Resonation.Compression },
    ['Crescent Fang'] = { Resonation.Transfixion },
    ['Rock Buster'] = { Resonation.Reverberation },
    ['Burning Strike'] = { Resonation.Impaction },
    ['Tail Whip'] = { Resonation.Detonation },
    ['Double Punch'] = { Resonation.Compression },
    ['Megalith Throw'] = { Resonation.Induration },
    ['Double Slap'] = { Resonation.Scission },
};

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

-- Shared prediction: closing ability attributes vs per-target resonation window.
local function GetSkillchainFromClosingAttributes(targetServerId, closingAttributes)
    if not closingAttributes or #closingAttributes == 0 then return nil; end

    local targetIndex = nil;
    if targetServerId and targetServerId > 0x8FF then
        targetIndex = GetIndexFromId(targetServerId);
    elseif targetServerId and targetServerId > 0 and targetServerId <= 0x8FF then
        targetIndex = targetServerId;
    end

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

    for _, sc in ipairs(possibleSkillchains) do
        local result, opening, closing = sc[1], sc[2], sc[3];
        if tableContains(resonation.Attributes, opening) then
            if tableContains(closingAttributes, closing) then
                return resonationNames[result];
            end
        end
    end

    return nil;
end

-- Get skillchain result for a WS against current target state
-- targetServerId: server ID of the target
-- wsIdOrName: weapon skill ID (number) or name (string)
-- Returns skillchain name or nil
function M.GetSkillchainForSlot(targetServerId, wsIdOrName)
    if not wsIdOrName then return nil; end

    local wsId = wsIdOrName;
    if type(wsIdOrName) == 'string' then
        wsId = GetWSIdFromName(wsIdOrName);
        if not wsId then return nil; end
    end

    local wsAttributes = weaponskillResonationMap[wsId];
    if not wsAttributes then return nil; end

    return GetSkillchainFromClosingAttributes(targetServerId, wsAttributes);
end

--- @param pactName string English pact name (e.g. /pet "Shock Strike")
function M.GetSkillchainForBloodPact(targetServerId, pactName)
    if not pactName then return nil; end
    local attrs = bloodPactResonationMap[pactName];
    return GetSkillchainFromClosingAttributes(targetServerId, attrs);
end

-- Handle action packet (0x0028)
-- Type 3: weapon skill — Param is WS id. Type 13: pet/Blood Pact — Param is ability id; map name → attributes.
function M.HandleActionPacket(actionPacket)
    if not actionPacket then return; end

    local actionType = actionPacket.Type;
    if actionType ~= 3 and actionType ~= 13 then return; end

    local param = actionPacket.Param;
    if not param or param == 0 then return; end

    local pactAttributes = nil;
    if actionType == 13 then
        local resMgr = AshitaCore:GetResourceManager();
        local ability = resMgr and resMgr:GetAbilityById(param);
        local pactName = ability and ability.Name and ability.Name[1];
        if pactName then
            pactAttributes = bloodPactResonationMap[pactName];
        end
    end

    for _, target in ipairs(actionPacket.Targets or {}) do
        local targetIndex = GetIndexFromId(target.Id);
        if targetIndex ~= 0 then
            for _, action in ipairs(target.Actions or {}) do
                local skillchain = nil;
                if action.AdditionalEffect then
                    skillchain = skillchainMessageIds[action.AdditionalEffect.Message];
                end

                if skillchain == Resonation.None then
                    resonationMap[targetIndex] = nil;
                    magicBurstMap[targetIndex] = nil;

                elseif skillchain then
                    local resonation = resonationMap[targetIndex];
                    local now = os.clock();

                    -- Track the "effective" resonation that we'll use for the MB lookup. The
                    -- depth-3 upgrade branch below promotes Light → Light2 / Darkness → Darkness2,
                    -- but magicBurstElements has identical entries for both pairs so either key
                    -- resolves to the same element set. We capture the resolved value to keep
                    -- the MB write trivially correct even if the upgrade table ever diverges.
                    local effectiveSkillchain = skillchain;
                    if resonation and (now + 1) > resonation.WindowOpen and (now - 1) < resonation.WindowClose then
                        resonation.Depth = resonation.Depth + 1;

                        if skillchain == Resonation.Light and tableContains(resonation.Attributes, Resonation.Light) then
                            resonation.Attributes = { Resonation.Light2 };
                            effectiveSkillchain = Resonation.Light2;
                        elseif skillchain == Resonation.Darkness and tableContains(resonation.Attributes, Resonation.Darkness) then
                            resonation.Attributes = { Resonation.Darkness2 };
                            effectiveSkillchain = Resonation.Darkness2;
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

                    -- Open / overwrite the Magic Burst window. Overwriting (rather than checking
                    -- "is the prior MB still open?") matches the user spec: "If another
                    -- Skillchain is performed, stop lighting the previous, switch to the new."
                    -- The element set for an upgraded chain (Light2/Darkness2) is identical to
                    -- the base, so the lookup is safe either way.
                    local burstElements = magicBurstElements[effectiveSkillchain];
                    if burstElements then
                        magicBurstMap[targetIndex] = {
                            Elements = burstElements,
                            ScName = resonationNames[effectiveSkillchain] or resonationNames[skillchain],
                            WindowOpen = now + MB_WINDOW_OPEN_DELAY,
                            WindowClose = now + MB_WINDOW_OPEN_DELAY + MB_WINDOW_DURATION,
                        };
                    end

                elseif weaponskillMessageIds[action.Message] then
                    local attributes = nil;
                    if actionType == 3 then
                        attributes = weaponskillResonationMap[param];
                    else
                        attributes = pactAttributes;
                    end
                    if attributes and #attributes > 0 then
                        local now = os.clock();
                        resonationMap[targetIndex] = {
                            Depth = 0,
                            Attributes = attributes,
                            WindowOpen = now,
                            WindowClose = now + 10.0,
                        };
                        -- A WS WITH attributes overwrites the target's resonance and closes the
                        -- prior MB window even if this WS doesn't chain (matches FFXI). WS rows
                        -- that have NO attributes (Spirits Within etc.) never reach this branch
                        -- because they're absent from weaponskillResonationMap / pactAttributes,
                        -- so the MB window survives — exactly the spec'd no-op behavior.
                        magicBurstMap[targetIndex] = nil;
                    end
                end
            end
        end
    end
end

-- Clear all state (call on zone change)
function M.ClearState()
    resonationMap = {};
    magicBurstMap = {};
end

-- Clear state for a specific target
function M.ClearTargetState(targetServerId)
    if targetServerId then
        local targetIndex = GetIndexFromId(targetServerId);
        if targetIndex ~= 0 then
            resonationMap[targetIndex] = nil;
            magicBurstMap[targetIndex] = nil;
        end
    end
end

-- ============================================
-- Magic Burst public API
-- ============================================

-- Resolve a slot to its burst-eligible element (0-7) or nil if the slot can never magic burst.
-- Routes by actionType: 'ma' → spell name lookup, 'pet' → curated SMN pact map, 'macro' →
-- parse primary line and route accordingly. Mirrors display.lua's skillchain dispatch so the
-- same slot types light up for both prediction paths.
function M.GetBurstElementForSlot(slotData)
    if not slotData or not slotData.actionType then return nil; end
    local aType = slotData.actionType;
    if aType == 'ma' then
        return spellNameToBurstElement(slotData.action);
    elseif aType == 'pet' then
        return pactNameToBurstElement(slotData.action);
    elseif aType == 'macro' and slotData.macroText then
        -- macroparse loaded lazily so skillchain.lua doesn't carry a hard dep on it for the
        -- non-macro callers (display/crossbar require it themselves already, so the cost is
        -- a single cached `require` after first macro-slot resolution).
        local ok, macroparse = pcall(require, 'modules.hotbar.macroparse');
        if not ok or not macroparse or not macroparse.GetMacroPrimaryAndJaBadge then
            return nil;
        end
        local pType, pName = macroparse.GetMacroPrimaryAndJaBadge(slotData.macroText);
        if pType == 'ma' and pName then
            return spellNameToBurstElement(pName);
        elseif pType == 'pet' and pName then
            return pactNameToBurstElement(pName);
        end
    end
    return nil;
end

-- Returns the SC name (e.g. 'Fusion') that opened the currently-active MB window for
-- `targetServerId`, if the window is open AND `element` matches one of its burstable
-- elements. Returns nil otherwise. The SC name is what slotrenderer uses as the corner
-- icon (same `assets/hotbar/skillchain/<scName>.png` files as the skillchain highlight).
function M.GetMagicBurstForElement(targetServerId, element)
    if element == nil then return nil; end

    local targetIndex = nil;
    if targetServerId and targetServerId > 0x8FF then
        targetIndex = GetIndexFromId(targetServerId);
    elseif targetServerId and targetServerId > 0 and targetServerId <= 0x8FF then
        targetIndex = targetServerId;
    end
    if not targetIndex or targetIndex == 0 then return nil; end

    local mb = magicBurstMap[targetIndex];
    if not mb then return nil; end

    local now = os.clock();
    if now > mb.WindowClose then
        magicBurstMap[targetIndex] = nil;  -- lazy GC of expired entries
        return nil;
    end
    if now < mb.WindowOpen then return nil; end

    for i = 1, #mb.Elements do
        if mb.Elements[i] == element then
            return mb.ScName;
        end
    end
    return nil;
end

-- Convenience: route a slot through GetBurstElementForSlot + GetMagicBurstForElement so
-- display.lua / crossbar.lua only need a single call per slot for MB (matches the
-- GetSkillchainForSlot calling pattern).
function M.GetMagicBurstForSlot(targetServerId, slotData)
    local element = M.GetBurstElementForSlot(slotData);
    if element == nil then return nil; end
    return M.GetMagicBurstForElement(targetServerId, element);
end

-- Existence helper for any UI status indicator (e.g. an on-target "MB window open!" badge
-- the user might add later). Returns the active MB entry or nil; caller is responsible for
-- the now-check via WindowOpen / WindowClose if it wants timing info beyond "is it open".
function M.GetMagicBurstWindow(targetServerId)
    local targetIndex = nil;
    if targetServerId and targetServerId > 0x8FF then
        targetIndex = GetIndexFromId(targetServerId);
    elseif targetServerId and targetServerId > 0 and targetServerId <= 0x8FF then
        targetIndex = targetServerId;
    end
    if not targetIndex or targetIndex == 0 then return nil; end

    local mb = magicBurstMap[targetIndex];
    if not mb then return nil; end

    local now = os.clock();
    if now > mb.WindowClose then
        magicBurstMap[targetIndex] = nil;
        return nil;
    end
    return mb;
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
