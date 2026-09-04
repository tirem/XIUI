-- Horizon skillchain overlay on skillchain_retail.lua.
-- skills[3]: only skillchain properties that differ from retail.
-- skills[4]/[13]: extra BLU and Blood Pacts with no SC on Horizon.
-- skills[11]: NPC action IDs. {ref=,id=} reuses an existing skill;
-- full tables are NPC-only names (listed once; other IDs ref that entry).

local skills = {};

skills[3] = {
 [13] = {skillchain={'Induration','Detonation','Impaction'}}, -- Tornado Kick
 [37] = {skillchain={'Scission','Transfixion'}}, -- Seraph Blade
 [53] = {skillchain={'Scission','Compression'}}, -- Crescent Moon
 [54] = {skillchain={'Scission','Reverberation'}}, -- Sickle Moon
 [58] = {skillchain={'Induration','Detonation','Impaction'}}, -- Herculean Slash
 [67] = {skillchain={'Induration'}}, -- Avalanche Axe
 [68] = {skillchain={'Liquefaction','Scission'}}, -- Spinning Axe
 [72] = {skillchain={'Fusion','Detonation'}}, -- Decimation
 [97] = {skillchain={'Compression'}}, -- Dark Harvest
 [104] = {skillchain={'Gravitation','Compression'}}, -- Spiral Hell
 [118] = {skillchain={'Transfixion','Induration'}}, -- Skewer
 [160] = {skillchain={'Transfixion'}}, -- Shining Strike
 [161] = {skillchain={'Scission'}}, -- Seraph Strike
 [166] = {skillchain={'Detonation','Impaction'}}, -- True Strike
 [175] = {skillchain={'Darkness','Fragmentation'}}, -- Exudation
 [179] = {skillchain={'Compression','Transfixion'}}, -- Starburst
 [180] = {skillchain={'Transfixion','Reverberation'}}, -- Sunburst
};

skills[4] = {
 [667] = {en='Vanity Dive',skillchain={'Transfixion','Scission'}},
};

skills[13] = {
 [521] = false, -- Regal Scratch
 [534] = false, -- Eclipse Bite
 [550] = false, -- Flaming Crush
 [566] = false, -- Mountain Buster
 [570] = false, -- Crag Throw
 [582] = false, -- Spinning Dive
 [598] = false, -- Predator Claws
 [614] = false, -- Rush
 [630] = false, -- Chaotic Strike
 [634] = false, -- Volt Strike
 [656] = false, -- Camisado
 [667] = false, -- Blindside
};

skills[11] = {
 [829] = {en='Great Wheel',skillchain={'Fragmentation','Scission'}},
 [1914] = {ref=11, id=829}, -- Great Wheel
 [3470] = {ref=11, id=829}, -- Great Wheel
 [830] = {en='Light Blade',skillchain={'Light','Fusion'}},
 [3214] = {ref=11, id=830}, -- Light Blade
 [3471] = {ref=11, id=830}, -- Light Blade
 [838] = {en='Howling Moon',skillchain={'Darkness','Distortion'}},
 [839] = {ref=11, id=838}, -- Howling Moon
 [1520] = {ref=11, id=838}, -- Howling Moon
 [3336] = {ref=11, id=838}, -- Howling Moon
 [938] = {ref=3, id=38}, -- Circle Blade
 [3707] = {ref=3, id=38}, -- Circle Blade
 [939] = {ref=3, id=41}, -- Swift Blade
 [3708] = {ref=3, id=41}, -- Swift Blade
 [940] = {ref=3, id=69}, -- Rampage
 [3715] = {ref=3, id=69}, -- Rampage
 [941] = {ref=3, id=70}, -- Calamity
 [3716] = {ref=3, id=70}, -- Calamity
 [943] = {ref=3, id=40}, -- Vorpal Blade
 [975] = {ref=3, id=40}, -- Vorpal Blade
 [1444] = {ref=3, id=40}, -- Vorpal Blade
 [1483] = {ref=3, id=40}, -- Vorpal Blade
 [1737] = {ref=3, id=40}, -- Vorpal Blade
 [3192] = {ref=3, id=40}, -- Vorpal Blade
 [3711] = {ref=3, id=40}, -- Vorpal Blade
 [944] = {ref=3, id=100}, -- Spinning Scythe
 [3719] = {ref=3, id=100}, -- Spinning Scythe
 [945] = {ref=3, id=102}, -- Guillotine
 [3721] = {ref=3, id=102}, -- Guillotine
 [946] = {en='Tachi: Yukikaze',skillchain={'Detonation','Induration'}},
 [3722] = {ref=11, id=946}, -- Tachi: Yukikaze
 [947] = {ref=3, id=151}, -- Tachi: Gekko
 [3723] = {ref=3, id=151}, -- Tachi: Gekko
 [948] = {ref=3, id=152}, -- Tachi: Kasha
 [3437] = {ref=3, id=152}, -- Tachi: Kasha
 [3725] = {ref=3, id=152}, -- Tachi: Kasha
 [951] = {en='Hurricane Wing',skillchain={'Scission','Detonation'}},
 [956] = {ref=11, id=951}, -- Hurricane Wing
 [1039] = {ref=11, id=951}, -- Hurricane Wing
 [3439] = {ref=11, id=951}, -- Hurricane Wing
 [953] = {en='Dragon Breath',skillchain={'Light','Fusion'}},
 [1041] = {ref=11, id=953}, -- Dragon Breath
 [3438] = {ref=11, id=953}, -- Dragon Breath
 [968] = {ref=3, id=34}, -- Red Lotus Blade
 [973] = {ref=3, id=34}, -- Red Lotus Blade
 [1476] = {ref=3, id=34}, -- Red Lotus Blade
 [1481] = {ref=3, id=34}, -- Red Lotus Blade
 [3190] = {ref=3, id=34}, -- Red Lotus Blade
 [3216] = {ref=3, id=34}, -- Red Lotus Blade
 [969] = {ref=3, id=35}, -- Flat Blade
 [1477] = {ref=3, id=35}, -- Flat Blade
 [3425] = {ref=3, id=35}, -- Flat Blade
 [970] = {ref=3, id=42}, -- Savage Blade
 [1478] = {ref=3, id=42}, -- Savage Blade
 [3217] = {ref=3, id=42}, -- Savage Blade
 [3432] = {ref=3, id=42}, -- Savage Blade
 [979] = {ref=3, id=49}, -- Power Slash
 [3411] = {ref=3, id=49}, -- Power Slash
 [980] = {en='Freezebite',skillchain={'Detonation','Induration'}},
 [3412] = {ref=11, id=980}, -- Freezebite
 [981] = {ref=3, id=56}, -- Ground Strike
 [3197] = {ref=3, id=56}, -- Ground Strike
 [3495] = {ref=3, id=56}, -- Ground Strike
 [985] = {en='Stellar Burst',skillchain={'Darkness','Gravitation'}},
 [1854] = {ref=11, id=985}, -- Stellar Burst
 [3473] = {ref=11, id=985}, -- Stellar Burst
 [986] = {en='Vortex',skillchain={'Distortion','Reverberation'}},
 [3213] = {ref=11, id=986}, -- Vortex
 [3472] = {ref=11, id=986}, -- Vortex
 [987] = {ref=3, id=52}, -- Shockwave
 [1027] = {ref=3, id=1}, -- Combo
 [3413] = {ref=3, id=1}, -- Combo
 [1029] = {en='One-Ilm Punch',skillchain={'Compression'}},
 [3414] = {ref=11, id=1029}, -- One-Ilm Punch
 [1030] = {ref=3, id=4}, -- Backhand Blow
 [1031] = {ref=3, id=6}, -- Spinning Attack
 [1032] = {ref=3, id=7}, -- Howling Fist
 [3415] = {ref=3, id=7}, -- Howling Fist
 [1033] = {ref=3, id=8}, -- Dragon Kick
 [3416] = {ref=3, id=8}, -- Dragon Kick
 [1034] = {ref=3, id=9}, -- Asuran Fists
 [3417] = {ref=3, id=9}, -- Asuran Fists
 [1088] = {ref=4, id=666}, -- Goblin Rush
 [1517] = {ref=4, id=666}, -- Goblin Rush
 [3262] = {ref=4, id=666}, -- Goblin Rush
 [1089] = {en='Bomb Toss',skillchain={'Liquefaction'}},
 [1090] = {ref=11, id=1089}, -- Bomb Toss
 [3261] = {ref=11, id=1089}, -- Bomb Toss
 [4124] = {ref=11, id=1089}, -- Bomb Toss
 [1188] = {ref=3, id=10}, -- Final Heaven
 [1189] = {ref=3, id=26}, -- Mercy Stroke
 [1190] = {ref=3, id=43}, -- Knights of Round
 [1191] = {ref=3, id=57}, -- Scourge
 [1192] = {ref=3, id=73}, -- Onslaught
 [1193] = {ref=3, id=89}, -- Metatron Torment
 [1194] = {ref=3, id=105}, -- Catastrophe
 [1195] = {ref=3, id=121}, -- Geirskogul
 [1196] = {ref=3, id=137}, -- Blade: Metsu
 [4158] = {ref=3, id=137}, -- Blade: Metsu
 [1197] = {ref=3, id=153}, -- Tachi: Kaiten
 [1198] = {ref=3, id=170}, -- Randgrith
 [1199] = {ref=3, id=185}, -- Gate of Tartarus
 [1201] = {ref=3, id=216}, -- Coronach
 [1390] = {en='Amatsu: Torimai',skillchain={'Transfixion','Scission'}},
 [3418] = {ref=11, id=1390}, -- Amatsu: Torimai
 [1391] = {en='Amatsu: Kazakiri',skillchain={'Scission','Detonation'}},
 [3419] = {ref=11, id=1391}, -- Amatsu: Kazakiri
 [1392] = {en='Amatsu: Yukiarashi',skillchain={'Induration','Detonation'}},
 [3420] = {ref=11, id=1392}, -- Amatsu: Yukiarashi
 [1393] = {en='Amatsu: Tsukioboro',skillchain={'Distortion','Reverberation'}},
 [3421] = {ref=11, id=1393}, -- Amatsu: Tsukioboro
 [1394] = {en='Amatsu: Hanaikusa',skillchain={'Fusion','Compression'}},
 [3422] = {ref=11, id=1394}, -- Amatsu: Hanaikusa
 [1395] = {en='Amatsu: Tsukikage',skillchain={'Darkness','Fragmentation'}},
 [3204] = {ref=11, id=1395}, -- Amatsu: Tsukikage
 [1397] = {en='Oisoya',skillchain={'Light','Distortion'}},
 [3542] = {ref=11, id=1397}, -- Oisoya
 [1489] = {en='Nullifying Dropkick',skillchain={'Induration','Detonation','Impaction'}},
 [1982] = {ref=11, id=1489}, -- Nullifying Dropkick
 [3234] = {ref=11, id=1489}, -- Nullifying Dropkick
 [1490] = {en='Auroral Uppercut',skillchain={'Light','Fragmentation'}},
 [1983] = {ref=11, id=1490}, -- Auroral Uppercut
 [3235] = {ref=11, id=1490}, -- Auroral Uppercut
 [1508] = {en='Luminous Lance',skillchain={'Light','Fusion'},delay=7},
 [3621] = {ref=11, id=1508}, -- Luminous Lance
 [1510] = {en='Revelation',skillchain={'Fusion','Transfixion'},delay=6},
 [3623] = {ref=11, id=1510}, -- Revelation
 [1586] = {ref=4, id=603}, -- Wild Oats
 [3351] = {ref=4, id=603}, -- Wild Oats
 [4050] = {ref=4, id=603}, -- Wild Oats
 [1618] = {en='Uppercut',skillchain={'Liquefaction'}},
 [3356] = {ref=11, id=1618}, -- Uppercut
 [3448] = {ref=11, id=1618}, -- Uppercut
 [1936] = {en='Shibaraku',skillchain={'Darkness','Gravitation'}},
 [3257] = {ref=11, id=1936}, -- Shibaraku
 [1998] = {en='Hane Fubuki',skillchain={'Transfixion'}},
 [3256] = {ref=11, id=1998}, -- Hane Fubuki
 [2001] = {en='Happobarai',skillchain={'Reverberation','Impaction'}},
 [3259] = {ref=11, id=2001}, -- Happobarai
 [2088] = {en='Victory Beacon',skillchain={'Light','Distortion'}},
 [2134] = {ref=11, id=2088}, -- Victory Beacon
 [3237] = {ref=11, id=2088}, -- Victory Beacon
 [2089] = {en='Salamander Flame',skillchain={'Light','Fusion'}},
 [2135] = {ref=11, id=2089}, -- Salamander Flame
 [3238] = {ref=11, id=2089}, -- Salamander Flame
 [2090] = {en='Typhonic Arrow',skillchain={'Light','Fragmentation'}},
 [2136] = {ref=11, id=2090}, -- Typhonic Arrow
 [3239] = {ref=11, id=2090}, -- Typhonic Arrow
 [2091] = {en='Meteoric Impact',skillchain={'Darkness','Fragmentation'}},
 [2137] = {ref=11, id=2091}, -- Meteoric Impact
 [3240] = {ref=11, id=2091}, -- Meteoric Impact
 [2092] = {en='Scouring Bubbles',skillchain={'Darkness','Distortion'}},
 [2138] = {ref=11, id=2092}, -- Scouring Bubbles
 [3203] = {ref=11, id=2092}, -- Scouring Bubbles
 [2140] = {en='Peacebreaker',skillchain={'Distortion','Reverberation'}},
 [3215] = {ref=11, id=2140}, -- Peacebreaker
 [2272] = {en='Bear Killer',skillchain={'Reverberation','Impaction'}},
 [3263] = {ref=11, id=2272}, -- Bear Killer
 [2273] = {ref=3, id=238}, -- Uriel Blade
 [3202] = {ref=3, id=238}, -- Uriel Blade
 [2274] = {en='Spine Chiller',skillchain={'Distortion','Detonation'}},
 [3536] = {ref=11, id=2274}, -- Spine Chiller
 [2278] = {ref=3, id=239}, -- Glory Slash
 [2280] = {en='Iainuki',skillchain={'Light','Fragmentation'},delay=7},
 [3435] = {ref=11, id=2280}, -- Iainuki
 [2386] = {en='Cobra Clamp',skillchain={'Fragmentation','Distortion'}},
 [3297] = {ref=11, id=2386}, -- Cobra Clamp
 [2444] = {en='Dancer\'s Fury',skillchain={'Fragmentation','Scission'}},
 [3310] = {ref=11, id=2444}, -- Dancer\'s Fury
 [2445] = {en='Whirling Edge',skillchain={'Distortion','Reverberation'}},
 [3311] = {ref=11, id=2445}, -- Whirling Edge
 [3544] = {ref=11, id=2445}, -- Whirling Edge
 [2468] = {en='King Cobra Clamp',skillchain={'Fragmentation','Distortion'}},
 [3189] = {ref=11, id=2468}, -- King Cobra Clamp
 [2469] = {ref=3, id=16}, -- Wasp Sting
 [3423] = {ref=3, id=16}, -- Wasp Sting
 [2470] = {ref=3, id=23}, -- Dancing Edge
 [3424] = {ref=3, id=23}, -- Dancing Edge
 [2472] = {en='Songbird Swoop',skillchain={'Reverberation','Impaction'}},
 [3295] = {ref=11, id=2472}, -- Songbird Swoop
 [2476] = {en='Gyre Strike',skillchain={'Fragmentation'}},
 [3292] = {ref=11, id=2476}, -- Gyre Strike
 [2477] = {en='Stag\'s Charge',skillchain={'Gravitation','Induration'}},
 [3293] = {ref=11, id=2477}, -- Stag\'s Charge
 [2478] = {en='Orcsbane',skillchain={'Light','Distortion'}},
 [3294] = {ref=11, id=2478}, -- Orcsbane
 [2479] = {en='Temblor Blade',skillchain={'Reverberation','Impaction'}},
 [3296] = {ref=11, id=2479}, -- Temblor Blade
 [2486] = {en='Salvation Scythe',skillchain={'Darkness'}},
 [2487] = {ref=11, id=2486}, -- Salvation Scythe
 [3264] = {ref=11, id=2486}, -- Salvation Scythe
 [2588] = {en='Debonair Rush',skillchain={'Scission','Detonation'}},
 [3231] = {ref=11, id=2588}, -- Debonair Rush
 [2589] = {en='Iridal Pierce',skillchain={'Light','Fragmentation'}},
 [3232] = {ref=11, id=2589}, -- Iridal Pierce
 [2590] = {en='Lunar Revolution',skillchain={'Gravitation','Reverberation'}},
 [3233] = {ref=11, id=2590}, -- Lunar Revolution
 [2594] = {en='Quietus Sphere',skillchain={'Darkness','Gravitation'}},
 [3537] = {ref=11, id=2594}, -- Quietus Sphere
 [2891] = {en='Grapeshot',skillchain={'Reverberation','Transfixion'}},
 [3198] = {ref=11, id=2891}, -- Grapeshot
 [3491] = {ref=11, id=2891}, -- Grapeshot
 [2892] = {en='Pirate Pummel',skillchain={'Fusion','Impaction'}},
 [3199] = {ref=11, id=2892}, -- Pirate Pummel
 [3492] = {ref=11, id=2892}, -- Pirate Pummel
 [2893] = {en='Powder Keg',skillchain={'Fusion','Compression'}},
 [3200] = {ref=11, id=2893}, -- Powder Keg
 [3493] = {ref=11, id=2893}, -- Powder Keg
 [2894] = {en='Walk the Plank',skillchain={'Light','Distortion'}},
 [3201] = {ref=11, id=2894}, -- Walk the Plank
 [3494] = {ref=11, id=2894}, -- Walk the Plank
 [2895] = {en='Knuckle Sandwich',skillchain={'Fusion','Compression'}},
 [3236] = {ref=11, id=2895}, -- Knuckle Sandwich
 [3543] = {ref=11, id=2895}, -- Knuckle Sandwich
 [2896] = {en='Imperial Authority',skillchain={'Fragmentation','Distortion'}},
 [3243] = {ref=11, id=2896}, -- Imperial Authority
 [2897] = {en='Sixth Element',skillchain={'Darkness','Gravitation'}},
 [3244] = {ref=11, id=2897}, -- Sixth Element
 [2898] = {en='Shield Subverter',skillchain={'Light','Fusion'}},
 [3245] = {ref=11, id=2898}, -- Shield Subverter
 [2899] = {en='Shining Summer Samba',skillchain={'Liquefaction','Transfixion'}},
 [3637] = {ref=11, id=2899}, -- Shining Summer Samba
 [2900] = {en='Lovely Miracle Waltz',skillchain={'Liquefaction','Scission','Impaction'}},
 [3638] = {ref=11, id=2900}, -- Lovely Miracle Waltz
 [2901] = {en='Neo Crystal Jig',skillchain={'Fusion','Transfixion'}},
 [3639] = {ref=11, id=2901}, -- Neo Crystal Jig
 [2902] = {en='Super Crusher Jig',skillchain={'Gravitation','Reverberation'},delay=7},
 [3640] = {ref=11, id=2902}, -- Super Crusher Jig
 [3161] = {en='Camaraderie of the Crevasse',skillchain={'Detonation','Impaction'}},
 [3677] = {ref=11, id=3161}, -- Camaraderie of the Crevasse
 [3162] = {en='Into the Light',skillchain={'Fusion','Impaction'}},
 [3678] = {ref=11, id=3162}, -- Into the Light
 [3163] = {en='Arduous Decision',skillchain={'Fragmentation','Compression'}},
 [3679] = {ref=11, id=3163}, -- Arduous Decision
 [3164] = {en='12 Blades of Remorse',skillchain={'Light','Distortion'}},
 [3680] = {ref=11, id=3164}, -- 12 Blades of Remorse
 [3168] = {en='Aurous Charge',skillchain={'Liquefaction','Transfixion'}},
 [3684] = {ref=11, id=3168}, -- Aurous Charge
 [3169] = {en='Howling Gust',skillchain={'Fragmentation','Compression'},delay=6},
 [3685] = {ref=11, id=3169}, -- Howling Gust
 [3170] = {en='Righteous Rasp',skillchain={'Fusion','Transfixion'}},
 [3686] = {ref=11, id=3170}, -- Righteous Rasp
 [3171] = {en='Starward Yowl',skillchain={'Gravitation','Reverberation'}},
 [3687] = {ref=11, id=3171}, -- Starward Yowl
 [3172] = {en='Stalking Prey',skillchain={'Light','Fragmentation'}},
 [3688] = {ref=11, id=3172}, -- Stalking Prey
 [3176] = {ref=3, id=225}, -- Chant du Cygne
 [3179] = {ref=3, id=225}, -- Chant du Cygne
 [3709] = {ref=3, id=225}, -- Chant du Cygne
 [3713] = {ref=3, id=225}, -- Chant du Cygne
 [3185] = {ref=3, id=76}, -- Cloudsplitter
 [3718] = {ref=3, id=76}, -- Cloudsplitter
 [3188] = {ref=3, id=156}, -- Tachi: Fudo
 [3726] = {ref=3, id=156}, -- Tachi: Fudo
 [3252] = {en='Bisection',skillchain={'Scission','Detonation'}},
 [3253] = {ref=3, id=218}, -- Leaden Salute
 [3254] = {en='Akimbo Shot',skillchain={'Compression'},delay=5},
 [3255] = {en='Grisly Horizon',skillchain={'Darkness','Distortion'}},
 [3283] = {en='Iniquitous Stab',skillchain={'Gravitation','Transfixion'}},
 [4211] = {ref=11, id=3283}, -- Iniquitous Stab
 [3284] = {en='Shockstorm Edge',skillchain={'Detonation','Impaction'}},
 [4212] = {ref=11, id=3284}, -- Shockstorm Edge
 [3285] = {en='Choreographed Carnage',skillchain={'Darkness','Distortion'}},
 [4213] = {ref=11, id=3285}, -- Choreographed Carnage
 [3286] = {en='Lock and Load',skillchain={'Fusion','Reverberation'}},
 [4214] = {ref=11, id=3286}, -- Lock and Load
 [3303] = {en='Feast of Arrows',skillchain={'Gravitation','Transfixion'}},
 [3617] = {ref=11, id=3303}, -- Feast of Arrows
 [3305] = {en='Regurgitated Swarm',skillchain={'Fusion','Compression'},delay=7},
 [3618] = {ref=11, id=3305}, -- Regurgitated Swarm
 [3306] = {en='Setting the Stage',skillchain={'Gravitation','Induration'}},
 [3619] = {ref=11, id=3306}, -- Setting the Stage
 [3307] = {en='Last Laugh',skillchain={'Darkness','Gravitation'}},
 [3620] = {ref=11, id=3307}, -- Last Laugh
 [3314] = {ref=3, id=166}, -- True Strike
 [3315] = {ref=3, id=168}, -- Hexa Strike
 [3322] = {en='Critical Mass',skillchain={'Fusion','Impaction'}},
 [3323] = {en='Fiery Tailings',skillchain={'Light','Fusion'}},
 [3337] = {en='Lunar Bay',skillchain={'Gravitation','Transfixion'}},
 [3551] = {ref=11, id=3337}, -- Lunar Bay
 [3381] = {en='Frenzied Thrust',skillchain={'Fragmentation','Transfixion'}},
 [3632] = {ref=11, id=3381}, -- Frenzied Thrust
 [3382] = {en='Sinner\'s Cross',skillchain={'Gravitation','Scission'}},
 [3633] = {ref=11, id=3382}, -- Sinner\'s Cross
 [3383] = {en='Open Coffin',skillchain={'Fusion','Compression'}},
 [3634] = {ref=11, id=3383}, -- Open Coffin
 [3385] = {en='Hemocladis',skillchain={'Darkness','Distortion'}},
 [3636] = {ref=11, id=3385}, -- Hemocladis
 [3431] = {ref=3, id=32}, -- Fast Blade
 [3434] = {en='Tachi: Kamai',skillchain={'Gravitation','Scission'}},
 [3436] = {ref=3, id=146}, -- Tachi: Goten
 [3445] = {en='Merciless Strike',skillchain={'Detonation','Impaction'}},
 [3647] = {ref=11, id=3445}, -- Merciless Strike
 [3454] = {en='Coming Up Roses',skillchain={'Light','Fusion'},delay=7},
 [3466] = {en='Paralyzing Microtube',skillchain={'Induration'},delay=6},
 [3467] = {en='Silencing Microtube',skillchain={'Liquefaction','Detonation'},delay=6},
 [3468] = {en='Binding Microtube',skillchain={'Gravitation','Induration'},delay=6},
 [3469] = {en='Twirling Dervish',skillchain={'Light','Fusion'},delay=8},
 [3487] = {ref=3, id=196}, -- Sidewinder
 [3488] = {ref=3, id=198}, -- Arching Arrow
 [3489] = {en='Stellar Arrow',skillchain={'Darkness','Gravitation'}},
 [3490] = {en='Lux Arrow',skillchain={'Fragmentation','Distortion'}},
 [3496] = {en='Hollow Smite',skillchain={'Light','Fragmentation'}},
 [3497] = {en='Sarva\'s Storm',skillchain={'Darkness','Distortion'}},
 [3498] = {ref=11, id=3497}, -- Sarva\'s Storm
 [3499] = {en='Soturi\'s Fury',skillchain={'Light','Fragmentation'}},
 [3500] = {en='Celidon\'s Torment',skillchain={'Light','Fragmentation'}},
 [3501] = {en='Tachi: Mudo',skillchain={'Light','Distortion'}},
 [3503] = {en='Justicebreaker',skillchain={'Darkness','Gravitation'},delay=5},
 [3538] = {en='Null Blast',skillchain={'Fusion','Compression'}},
 [3556] = {en='Amatsu: Fuga',skillchain={'Impaction'},delay=6},
 [3732] = {ref=11, id=3556}, -- Amatsu: Fuga
 [3557] = {en='Amatsu: Kyori',skillchain={'Induration'},delay=7},
 [3733] = {ref=11, id=3557}, -- Amatsu: Kyori
 [3558] = {en='Amatsu: Hanadoki',skillchain={'Reverberation','Impaction'}},
 [3734] = {ref=11, id=3558}, -- Amatsu: Hanadoki
 [3559] = {en='Amatsu: Choun',skillchain={'Liquefaction'}},
 [3735] = {ref=11, id=3559}, -- Amatsu: Choun
 [3560] = {en='Amatsu: Gachirin',skillchain={'Light','Fragmentation'},delay=7},
 [3736] = {ref=11, id=3560}, -- Amatsu: Gachirin
 [3561] = {en='Amatsu: Suien',skillchain={'Fusion'},delay=6},
 [3737] = {ref=11, id=3561}, -- Amatsu: Suien
 [3579] = {en='Expunge Magic',skillchain={'Distortion','Scission'}},
 [3699] = {ref=11, id=3579}, -- Expunge Magic
 [3580] = {en='Harmonic Displacement',skillchain={'Fusion','Reverberation'}},
 [3700] = {ref=11, id=3580}, -- Harmonic Displacement
 [3581] = {en='Sight Unseen',skillchain={'Fragmentation','Compression'}},
 [3701] = {ref=11, id=3581}, -- Sight Unseen
 [3582] = {en='Darkest Hour',skillchain={'Gravitation','Liquefaction'}},
 [3702] = {ref=11, id=3582}, -- Darkest Hour
 [3585] = {en='Naakual\'s Vengeance',skillchain={'Light','Fusion'},delay=7},
 [3705] = {ref=11, id=3585}, -- Naakual\'s Vengeance
 [3591] = {en='Tartaric Sigil',skillchain={'Compression','Scission'}},
 [3653] = {ref=11, id=3591}, -- Tartaric Sigil
 [3592] = {en='Null Field',skillchain={'Fusion','Transfixion'}},
 [3654] = {ref=11, id=3592}, -- Null Field
 [3593] = {en='Alabaster Burst',skillchain={'Distortion','Detonation'}},
 [3655] = {ref=11, id=3593}, -- Alabaster Burst
 [3594] = {en='Noble Frenzy',skillchain={'Gravitation','Scission'}},
 [3656] = {ref=11, id=3594}, -- Noble Frenzy
 [3595] = {en='Fulminous Fury',skillchain={'Fragmentation','Scission'},delay=6},
 [3657] = {ref=11, id=3595}, -- Fulminous Fury
 [3596] = {en='No Quarter',skillchain={'Light','Distortion'},delay=7},
 [3658] = {ref=11, id=3596}, -- No Quarter
 [3611] = {en='Inexorable Strike',skillchain={'Light','Fusion'}},
 [3645] = {ref=11, id=3611}, -- Inexorable Strike
 [3691] = {en='Bludgeon',skillchain={'Fusion'}},
 [3740] = {en='Final Exam',skillchain={'Light','Fusion'}},
 [3741] = {en='Doctor\'s Orders',skillchain={'Darkness','Gravitation'}},
 [3742] = {en='Empirical Research',skillchain={'Fragmentation','Transfixion'}},
 [3743] = {en='Lesson in Pain',skillchain={'Distortion','Scission'}},
 [3854] = {ref=11, id=686}, -- Brain Crush
};

return skills;
