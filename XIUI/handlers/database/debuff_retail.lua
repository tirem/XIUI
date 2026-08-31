-- Retail debuff durations (shared base). Horizon loads this table, then
-- applies handlers/database/debuff_horizon.lua for duration diffs only.
-- Spell/WS/JA/pet data from existing XIUI tables plus LSB scripts.

local durations = {};

durations.spells = {
    -- Dia/Bio: damage message is the apply (no separate status-on). They overwrite each other.
    [23] = {duration = 60, buffId = 134, clearsBuffs = {135}, kind = 'enfeeble', applyOnDamage = true},   -- Dia
    [33] = {duration = 60, buffId = 134, clearsBuffs = {135}, kind = 'enfeeble', applyOnDamage = true},   -- Diaga
    [24] = {duration = 120, buffId = 134, clearsBuffs = {135}, kind = 'enfeeble', applyOnDamage = true},  -- Dia II
    [25] = {duration = 180, buffId = 134, clearsBuffs = {135}, kind = 'enfeeble', applyOnDamage = true},  -- Dia III
    [230] = {duration = 60, buffId = 135, clearsBuffs = {134}, kind = 'enfeeble', applyOnDamage = true},  -- Bio
    [231] = {duration = 120, buffId = 135, clearsBuffs = {134}, kind = 'enfeeble', applyOnDamage = true}, -- Bio II
    [232] = {duration = 180, buffId = 135, clearsBuffs = {134}, kind = 'enfeeble', applyOnDamage = true}, -- Bio III

    -- Helix: applyOnDamage (DoT lands on the damage message). Dark Arts JP added in ResolveDuration.
    [278] = {duration = 90, buffId = 186, kind = 'helix', applyOnDamage = true}, [279] = {duration = 90, buffId = 186, kind = 'helix', applyOnDamage = true},
    [280] = {duration = 90, buffId = 186, kind = 'helix', applyOnDamage = true}, [281] = {duration = 90, buffId = 186, kind = 'helix', applyOnDamage = true},
    [282] = {duration = 90, buffId = 186, kind = 'helix', applyOnDamage = true}, [283] = {duration = 90, buffId = 186, kind = 'helix', applyOnDamage = true},
    [284] = {duration = 90, buffId = 186, kind = 'helix', applyOnDamage = true}, [285] = {duration = 90, buffId = 186, kind = 'helix', applyOnDamage = true},
    [885] = {duration = 90, buffId = 186, kind = 'helix', applyOnDamage = true}, [886] = {duration = 90, buffId = 186, kind = 'helix', applyOnDamage = true},
    [887] = {duration = 90, buffId = 186, kind = 'helix', applyOnDamage = true}, [888] = {duration = 90, buffId = 186, kind = 'helix', applyOnDamage = true},
    [889] = {duration = 90, buffId = 186, kind = 'helix', applyOnDamage = true}, [890] = {duration = 90, buffId = 186, kind = 'helix', applyOnDamage = true},
    [891] = {duration = 90, buffId = 186, kind = 'helix', applyOnDamage = true}, [892] = {duration = 90, buffId = 186, kind = 'helix', applyOnDamage = true},

    -- Regular debuff spells
    [58] = {duration = 120, kind = 'enfeeble'},  -- Paralyze
    [80] = {duration = 120, kind = 'enfeeble'},  -- Paralyze II
    [356] = {duration = 120, kind = 'enfeeble'}, -- Paralyga
    [56] = {duration = 180, kind = 'enfeeble'},  -- Slow
    [79] = {duration = 180, kind = 'enfeeble'},  -- Slow II
    [357] = {duration = 180, kind = 'enfeeble'}, -- Slowga
    [216] = {duration = 120, kind = 'enfeeble'}, -- Gravity
    [217] = {duration = 180, kind = 'enfeeble'}, -- Gravity II
    [366] = {duration = 120, kind = 'enfeeble'}, -- Graviga
    [254] = {duration = 180, kind = 'enfeeble'}, -- Blind
    [276] = {duration = 180, kind = 'enfeeble'}, -- Blind II
    [361] = {duration = 180, kind = 'enfeeble'}, -- Blindga
    [112] = {duration = 12, kind = 'enfeeble'},  -- Flash
    [59] = {duration = 120, kind = 'enfeeble'},  -- Silence
    [359] = {duration = 120, kind = 'enfeeble'}, -- Silencega
    [253] = {duration = 60, buffId = 2, clearsBuffs = {19}, kind = 'enfeeble'},  -- Sleep
    [273] = {duration = 60, buffId = 2, clearsBuffs = {19}, kind = 'enfeeble'},  -- Sleepga
    [259] = {duration = 90, displayBuffId = 19, clearsBuffs = {2, 193}, kind = 'enfeeble'}, -- Sleep II
    [274] = {duration = 90, displayBuffId = 19, clearsBuffs = {2, 193}, kind = 'enfeeble'}, -- Sleepga II
    [258] = {duration = 60, kind = 'enfeeble'},  -- Bind
    [362] = {duration = 60, kind = 'enfeeble'},  -- Bindga
    [252] = {duration = 5, kind = 'enfeeble'},   -- Stun
    [220] = {duration = 90, kind = 'enfeeble'},  -- Poison
    [221] = {duration = 120, kind = 'enfeeble'}, -- Poison II
    [222] = {duration = 150, kind = 'enfeeble'}, -- Poison III
    [225] = {duration = 90, kind = 'enfeeble'},  -- Poisonga
    [226] = {duration = 120, kind = 'enfeeble'}, -- Poisonga II
    [227] = {duration = 150, kind = 'enfeeble'}, -- Poisonga III
    [286] = {duration = 180, kind = 'enfeeble'}, -- Addle
    [884] = {duration = 180, kind = 'enfeeble'}, -- Addle II
    [256] = {duration = 60, kind = 'enfeeble'},  -- Virus - Plague
    [257] = {duration = 300, kind = 'enfeeble'}, -- Curse
    [98] = {duration = 90, displayBuffId = 19, clearsBuffs = {2, 193}, kind = 'enfeeble'}, -- Repose
    [841] = {duration = 120, kind = 'enfeeble'}, -- Distract
    [842] = {duration = 120, kind = 'enfeeble'}, -- Distract II
    [843] = {duration = 120, kind = 'enfeeble'}, -- Distract III
    [844] = {duration = 120, kind = 'enfeeble'}, -- Frazzle
    [845] = {duration = 120, kind = 'enfeeble'}, -- Frazzle II
    [846] = {duration = 120, kind = 'enfeeble'}, -- Frazzle III
    [255] = {duration = 30, kind = 'enfeeble'},  -- Break
    [365] = {duration = 30, kind = 'enfeeble'},  -- Breakga
    [879] = {duration = 300, kind = 'enfeeble'}, -- Inundation

    -- Ninjutsu debuffs (LSB enfeebling_spell.lua base durations)
    [319] = { duration = 120, buffId = 147 }, -- Aisha: Ichi - Attack Down
    [341] = { duration = 180 }, -- Jubaku: Ichi
    [342] = { duration = 300 }, -- Jubaku: Ni
    [343] = { duration = 420 }, -- Jubaku: San
    [344] = { duration = 180 }, -- Hojo: Ichi
    [345] = { duration = 300 }, -- Hojo: Ni
    [346] = { duration = 420 }, -- Hojo: San
    [347] = { duration = 180 }, -- Kurayami: Ichi
    [348] = { duration = 300 }, -- Kurayami: Ni
    [349] = { duration = 420 }, -- Kurayami: San
    [350] = { duration = 60 },  -- Dokumori: Ichi
    [351] = { duration = 120 }, -- Dokumori: Ni
    [352] = { duration = 360 }, -- Dokumori: San
    [508] = { duration = 180, buffId = 168 }, -- Yurin: Ichi - Inhibit TP
    -- Elemental debuffs (Burn, Frost, Choke, Rasp, Shock, Drown)
    [235] = {duration = 90, kind = 'elemental'}, [236] = {duration = 90, kind = 'elemental'},
    [237] = {duration = 90, kind = 'elemental'}, [238] = {duration = 90, kind = 'elemental'},
    [239] = {duration = 90, kind = 'elemental'}, [240] = {duration = 90, kind = 'elemental'},

    -- Threnodies I
    [454] = {duration = 60, songFamily = 'songPlusThrenody'},
    [455] = {duration = 60, songFamily = 'songPlusThrenody'},
    [456] = {duration = 60, songFamily = 'songPlusThrenody'},
    [457] = {duration = 60, songFamily = 'songPlusThrenody'},
    [458] = {duration = 60, songFamily = 'songPlusThrenody'},
    [459] = {duration = 60, songFamily = 'songPlusThrenody'},
    [460] = {duration = 60, songFamily = 'songPlusThrenody'},
    [461] = {duration = 60, songFamily = 'songPlusThrenody'},
    -- Threnodies II
    [871] = {duration = 90, songFamily = 'songPlusThrenody'},
    [872] = {duration = 90, songFamily = 'songPlusThrenody'},
    [873] = {duration = 90, songFamily = 'songPlusThrenody'},
    [874] = {duration = 90, songFamily = 'songPlusThrenody'},
    [875] = {duration = 90, songFamily = 'songPlusThrenody'},
    [876] = {duration = 90, songFamily = 'songPlusThrenody'},
    [877] = {duration = 90, songFamily = 'songPlusThrenody'},
    [878] = {duration = 90, songFamily = 'songPlusThrenody'},

    -- Elegies
    [421] = {duration = 120, songFamily = 'songPlusElegy'}, -- Battlefield Elegy
    [422] = {duration = 180, songFamily = 'songPlusElegy'}, -- Carnage Elegy
    [423] = {duration = 180, songFamily = 'songPlusElegy'}, -- Massacre Elegy

    -- Requiem I-VII
    [368] = {duration = 64, songFamily = 'songPlusRequiem'},
    [369] = {duration = 80, songFamily = 'songPlusRequiem'},
    [370] = {duration = 96, songFamily = 'songPlusRequiem'},
    [371] = {duration = 112, songFamily = 'songPlusRequiem'},
    [372] = {duration = 128, songFamily = 'songPlusRequiem'},
    [373] = {duration = 144, songFamily = 'songPlusRequiem'},
    [374] = {duration = 160, songFamily = 'songPlusRequiem'},

    -- Lullaby (376/377 Horde, 463/471 Foe)
    [376] = {duration = 30, songFamily = 'songPlusLullaby'}, -- Horde Lullaby
    [377] = {duration = 60, songFamily = 'songPlusLullaby'}, -- Horde Lullaby II
    [463] = {duration = 30, songFamily = 'songPlusLullaby'}, -- Foe Lullaby
    [471] = {duration = 60, songFamily = 'songPlusLullaby'}, -- Foe Lullaby II

    [466] = {duration = 30, songFamily = 'songPlusVirelai'}, -- Maiden's Virelai
    [472] = {duration = 120, songFamily = 'songPlusNocturne'}, -- Pining Nocturne

    -- Blue Magic. onDamage = status is an additional effect of a damaging spell.
    [513] = {duration = 60, buffId = 3}, -- Venom Shell - Poison
    [515] = {duration = 60, buffId = 136, onDamage = true}, -- Maelstrom - STR Down
    [524] = {duration = 60, buffId = 146, onDamage = true}, -- Sandspin - Accuracy Down
    [531] = {duration = 30, buffId = 11, onDamage = true}, -- Ice Break - Bind
    [532] = {duration = 5, buffId = 10, onDamage = true}, -- Blitzstrahl - Stun
    [534] = {duration = 60, buffId = 12, onDamage = true}, -- Mysterious Light - Weight
    [535] = {duration = 60, buffId = 129}, -- Cold Wave - Frost
    [536] = {duration = 60, buffId = 3, onDamage = true}, -- Poison Breath - Poison
    [537] = {duration = 60, buffId = 138}, -- Stinking Gas - VIT Down
    [539] = {duration = 60, buffId = 147, onDamage = true}, -- Terror Touch - Attack Down
    [548] = {duration = 90, buffId = 13}, -- Filamented Hold - Slow
    [555] = {duration = 60, buffId = 12, onDamage = true}, -- Magnetite Cloud - Weight
    [561] = {duration = 180, buffId = 149}, -- Frightful Roar - Defense Down
    [563] = {duration = 60, buffId = 5, onDamage = true}, -- Hecatomb Wave - Blind
    [565] = {duration = 60, buffId = 13, buffIds = {13, 6}, onDamage = true}, -- Radiant Breath - Slow + Silence
    [572] = {duration = 30, buffId = 140}, -- Sound Blast - INT Down
    [575] = {duration = 5, buffId = 28}, -- Jettatura - Terror
    [576] = {duration = 90, buffId = 2}, -- Yawn - Sleep
    [582] = {duration = 120, buffId = 6}, -- Chaotic Eye - Silence
    [584] = {duration = 60, buffId = 2}, -- Sheep Song - Sleep
    [588] = {duration = 60, buffId = 31}, -- Lowing - Plague
    [596] = {duration = 60, buffId = 2, onDamage = true}, -- Pinecone Bomb - Sleep
    [597] = {duration = 180, buffId = 13, onDamage = true}, -- Sprout Smack - Slow
    [598] = {duration = 90, buffId = 2}, -- Soporific - Sleep
    [599] = {duration = 180, buffId = 3, onDamage = true}, -- Queasyshroom - Poison
    [603] = {duration = 60, buffId = 138, onDamage = true}, -- Wild Oats - VIT Down
    [604] = {duration = 60, buffId = 13, buffIds = {13, 6, 4, 11, 12, 3, 5}, onDamage = true}, -- Bad Breath
    [606] = {duration = 30, buffId = 136}, -- Awful Eye - STR Down
    [608] = {duration = 60, buffId = 4, onDamage = true}, -- Frost Breath - Paralyze
    [610] = {duration = 60, buffId = 148}, -- Infrasonics - Evasion Down
    [611] = {duration = 180, buffId = 3, onDamage = true}, -- Disseverment - Poison
    [612] = {duration = 16, buffId = 156}, -- Actinic Burst - Flash
    [616] = {duration = 5, buffId = 10}, -- Temporal Shift - Stun
    [618] = {duration = 30, buffId = 11, onDamage = true}, -- Blastbomb - Bind
    [620] = {duration = 60, buffId = 137, onDamage = true}, -- Battle Dance - DEX Down
    [621] = {duration = 120, buffId = 5}, -- Sandspray - Blind
    [623] = {duration = 5, buffId = 10, onDamage = true}, -- Head Butt - Stun
    [628] = {duration = 5, buffId = 10, onDamage = true}, -- Frypan - Stun
    [633] = {duration = 30, buffId = 149, buffIds = {149, 167}}, -- Enervation - Def Down + MDB Down
    [634] = {duration = 30, buffId = 5, buffIds = {5, 11}}, -- Light of Penance - Blind + Bind
    [638] = {duration = 180, buffId = 3, onDamage = true}, -- Feather Storm - Poison
    [640] = {duration = 5, buffId = 10, onDamage = true}, -- Tail Slap - Stun
    [644] = {duration = 90, buffId = 4, onDamage = true}, -- Mind Blast - Paralyze
    [648] = {duration = 30, buffId = 11, onDamage = true}, -- Regurgitation - Bind
    [650] = {duration = 120, buffId = 149, onDamage = true}, -- Seedspray - Defense Down
    [651] = {duration = 90, buffId = 149, buffIds = {149, 147}, onDamage = true}, -- Corrosive Ooze - Def/Atk Down
    [652] = {duration = 60, buffId = 146, onDamage = true}, -- Spiral Spin - Accuracy Down
    [654] = {duration = 180, buffId = 4, onDamage = true}, -- Sub-zero Smash - Paralyze
    [660] = {duration = 90, buffId = 13}, -- Cimicine Discharge - Slow
    [669] = {duration = 5, buffId = 10, onDamage = true}, -- Whirl of Rage - Stun
    [671] = {duration = 60, buffId = 6, buffIds = {6, 11}, onDamage = true}, -- Auroral Drape - Silence + Bind
    [675] = {duration = 60, buffId = 5, onDamage = true}, -- Thermal Pulse - Blind
    [678] = {duration = 90, buffId = 2}, -- Dream Flower - Sleep
    [682] = {duration = 60, buffId = 31, onDamage = true}, -- Delta Thrust - Plague
    [687] = {duration = 90, buffId = 6, onDamage = true}, -- Water Bomb - Silence (BG: 60~90)
    [692] = {duration = 5, buffId = 10, onDamage = true}, -- Sudden Lunge - Stun
    [699] = {duration = 120, buffId = 146, onDamage = true}, -- Barbed Crescent - Accuracy Down
    [703] = {duration = 180, buffId = 13, onDamage = true}, -- Embalming Earth - Slow
    [704] = {duration = 60, buffId = 4, onDamage = true}, -- Paralyzing Triad - Paralyze
    [705] = {duration = 180, buffId = 133, onDamage = true}, -- Foul Waters - Drown
    [707] = {duration = 15, buffId = 156, onDamage = true}, -- Retinal Glare - Flash
};

-- Type 3 WS secondaries (same pattern as BLU onDamage). ? unless certainOnHit.
durations.weaponSkills = {
    [2] = {buffId = 10, tpPer500 = 1}, -- Shoulder Tackle - Stun
    [15] = {buffId = 31, tpDuration = {base = 15, per1000Tp = 3}}, -- Shijin Spiral - Plague
    [16] = {buffId = 3, tpDuration = {base = 75, per1000Tp = 15}}, -- Wasp Sting - Poison
    [17] = {buffId = 3, tpDuration = {base = 30, per100Tp = 6}}, -- Viper Bite - Poison
    [18] = {buffId = 11, tpDuration = {base = 5, per200Tp = 1}}, -- Shadowstitch - Bind
    [28] = {buffId = 12, duration = 60}, -- Mordant Rime - Weight
    [29] = {buffId = 148, tpDuration = {per100Tp = 6}}, -- Pyrrhic Kleos - Evasion Down
    [31] = {buffId = 12, duration = 60}, -- Rudra's Storm - Weight
    [35] = {buffId = 10, duration = 4}, -- Flat Blade - Stun
    [44] = {buffId = 404, duration = 60}, -- Death Blossom - Magic Evasion Down
    [52] = {buffId = 2, tpDuration = {per100Tp = 6}}, -- Shockwave - Sleep
    [58] = {buffId = 4, tpDuration = {per100Tp = 6}}, -- Herculean Slash - Paralyze
    [65] = {buffId = 10, tpPer500 = 1}, -- Smash Axe - Stun
    [66] = {buffId = 130, duration = 60}, -- Gale Axe - Choke
    [73] = {buffId = 146, duration = 120}, -- Onslaught - Accuracy Down
    [75] = {buffId = 11, duration = 20}, -- Bora Axe - Bind
    [80] = {buffId = 148, tpDuration = {base = 120, per100Tp = 6}}, -- Shield Break - Evasion Down
    [83] = {buffId = 149, tpDuration = {base = 120, per100Tp = 6}}, -- Armor Break - Defense Down
    [85] = {buffId = 147, tpDuration = {base = 120, per100Tp = 6}}, -- Weapon Break - Attack Down
    [87] = {buffIds = {147, 149, 146, 148}, tpDuration = {base = 60, per100Tp = 3}}, -- Full Break
    [89] = {buffId = 149, duration = 120}, -- Metatron Torment - Defense Down
    [92] = {buffId = 13, duration = 60}, -- Ukko's Fury - Slow
    [102] = {buffId = 6, tpDuration = {base = 30, per100Tp = 3}}, -- Guillotine - Silence
    [107] = {buffId = 147, tpDuration = {per100Tp = 18}}, -- Infernal Scythe - Attack Down
    [115] = {buffId = 10, duration = 4}, -- Leg Sweep - Stun
    [125] = {buffId = 298, duration = 60}, -- Stardiver - Crit Hit Evasion Down
    [129] = {buffId = 4, tpFTP = {30, 60, 120}}, -- Blade: Retsu - Paralyze
    [137] = {buffId = 4, duration = 60}, -- Blade: Metsu - Paralyze
    [138] = {buffId = 146, tpDuration = {per100Tp = 6}}, -- Blade: Kamu - Accuracy Down
    [139] = {buffId = 3, tpDuration = {base = 75, per1000Tp = 15}}, -- Blade: Yu - Poison
    [145] = {buffId = 10, duration = 3}, -- Tachi: Hobaku - Stun
    [150] = {buffId = 5, duration = 60}, -- Tachi: Yukikaze - Blind
    [151] = {buffId = 6, duration = 45}, -- Tachi: Gekko - Silence
    [152] = {buffId = 4, duration = 60}, -- Tachi: Kasha - Paralyze
    [155] = {buffId = 149, tpDuration = {per100Tp = 6}}, -- Tachi: Ageha - Defense Down
    [162] = {buffId = 10, tpPer500 = 1}, -- Brainshaker - Stun
    [165] = {buffId = 140, duration = 140}, -- Skullbreaker - INT Down
    [170] = {buffId = 148, duration = 120}, -- Randgrith - Evasion Down
    [181] = {buffId = 149, tpDuration = {base = 120, per100Tp = 6}}, -- Shell Crusher - Defense Down
    [185] = {buffId = 147, duration = 120}, -- Gate of Tartarus - Attack Down
    [186] = {buffId = 167, tpDuration = {per100Tp = 6}}, -- Vidohunir - Magic Def Down
    [187] = {buffId = 149, tpDuration = {per100Tp = 6}}, -- Garland of Bliss - Defense Down
    [188] = {buffId = 175, tpDuration = {per100Tp = 6}}, -- Omniscience - Magic Atk Down
    [191] = {buffId = 167, duration = 120}, -- Shattersoul - Magic Def Down
    [210] = {buffId = 140, duration = 140}, -- Sniper Shot - INT Down
    [219] = {buffId = 4, tpDuration = {per100Tp = 6}}, -- Numbing Shot - Paralyze
    [224] = {buffId = 146, tpDuration = {base = 45, per1000Tp = 45}}, -- Exenterator - Accuracy Down
    [238] = {buffId = 156, duration = 15}, -- Uriel Blade - Flash
    [239] = {buffId = 10, tpPer500 = 1}, -- Glory Slash - Stun
    [99] = {buffId = 5, tpDuration = {per100Tp = 6}}, -- Nightmare Scythe - Blind
};

-- Job abilities that apply a debuff on the next melee/ranged hit (not on use).
durations.onHit = {
    [156] = {buffId = 148, duration = 30, window = 60}, -- Feint -> Evasion Down
};

-- Type 3 physical JAs (sometimes type 6). uncertain = hidden second roll (?); certainOnHit = absolute.
durations.jaPhysical = {
    [57] = {duration = 30, buffId = 11},   -- Shadowbind - Bind (msg 203)
    [46] = {duration = 8, buffId = 10, uncertain = true}, -- Shield Bash - Stun
    [77] = {duration = 8, buffId = 10, uncertain = true}, -- Weapon Bash - Stun
    [168] = {duration = 30, buffId = 31, buffIds = {10, 31}, uncertain = true}, -- Blade Bash - Stun (~6s) + Plague (15+merits); resist each
    [170] = {duration = 30, buffId = 149, certainOnHit = true}, -- Angon - Defense Down (15+merit; 30 at 1)
};

-- Type 6 / 14 job abilities. Keys are ability IDs (action Param), not buff IDs.
-- Applied from status-on (127 etc.), not from "uses". Bash-style hits live in jaPhysical.
durations.ja = {
    [57] = {duration = 30, buffId = 11}, -- Shadowbind - Bind (also type 3 / jaPhysical)
    [46] = {duration = 8, buffId = 10, uncertain = true}, -- Shield Bash - Stun (also type 3 / jaPhysical)
    [77] = {duration = 8, buffId = 10, uncertain = true}, -- Weapon Bash - Stun (also type 3 / jaPhysical)
    [168] = {duration = 30, buffId = 31, buffIds = {10, 31}, uncertain = true}, -- Blade Bash - Stun (~6s) + Plague (15+merits); resist each (also type 3 / jaPhysical)
    [170] = {duration = 30, buffId = 149, certainOnHit = true}, -- Angon (also type 3 / jaPhysical)
    [82] = {duration = 100, buffId = 168, uncertain = true}, -- Chi Blast - Inhibit TP only with Penance
    [131] = {duration = 90, buffId = 2}, -- Light Shot - Sleep
    [150] = {duration = 30, buffId = 805}, -- Tomahawk (silent client icon; not Defense Down 149)
    [161] = {duration = 10, buffId = 28, uncertain = true}, -- Feral Howl - Terror    
    [201] = {duration = 60, buffId = 386}, -- Quickstep - Lethargic Daze
    [202] = {duration = 60, buffId = 391}, -- Box Step - Sluggish Daze
    [203] = {duration = 60, buffId = 396}, -- Stutter Step - Weakened Daze
    [205] = {duration = 60, buffId = 12, uncertain = true}, -- Desperate Flourish - Weight
    [207] = {duration = 2, buffId = 10, uncertain = true}, -- Violent Flourish - Stun
    [209] = {duration = 10, buffId = 798}, -- Wild Flourish - Chainbound
    [228] = {duration = 90, uncertain = true}, -- Despoil - only on successful steal (buff id from packet)
    [277] = {duration = 180, buffId = 463}, -- Sepulcher
    [279] = {duration = 180, buffId = 464}, -- Arcane Crest
    [287] = {duration = 180, buffId = 465}, -- Hamanoha
    [292] = {duration = 180, buffId = 466}, -- Dragon Breaker
    [312] = {duration = 60, buffId = 448}, -- Feather Step - Bewildered Daze
    [320] = {duration = 10, buffId = 798}, -- Konzen-Ittai - Chainbound
    [321] = {duration = 30, buffId = 576}, -- Bully - Doubt
    [329] = {duration = 30, buffId = 496}, -- Intervene
    [372] = {duration = 60, buffId = 536}, -- Gambit
    [375] = {duration = 30, buffId = 571}, -- Rayke (27 + merits; 30 at 1)
    [378] = {duration = 30, buffId = 509}, -- Odyllic Subterfuge
    [16] = {duration = 45, buffId = 44}, -- Mighty Strikes
    [17] = {duration = 45, buffId = 46}, -- Hundred Fists
    [19] = {duration = 60, buffId = 47}, -- Manafont
    [20] = {duration = 60, buffId = 48}, -- Chainspell
    [21] = {duration = 30, buffId = 49}, -- Perfect Dodge
    [22] = {duration = 30, buffId = 50}, -- Invincible
    [23] = {duration = 30, buffId = 51}, -- Blood Weapon
    [688] = {duration = 45, buffId = 44}, -- Mighty Strikes (mob skill)
    [690] = {duration = 45, buffId = 46}, -- Hundred Fists
    [691] = {duration = 60, buffId = 47}, -- Manafont
    [692] = {duration = 60, buffId = 48}, -- Chainspell
    [693] = {duration = 30, buffId = 49}, -- Perfect Dodge
    [694] = {duration = 30, buffId = 50}, -- Invincible
    [695] = {duration = 30, buffId = 51}, -- Blood Weapon
    [696] = {duration = 180, buffId = 52}, -- Soul Voice (mob skill)
    [730] = {duration = 30, buffId = 54}, -- Meikyo Shisui (mob skill)
    [1933] = {duration = 45, buffId = 163}, -- Azure Lore (mob skill)
};

-- Pet / blood pact ids (ability id). Damaging pacts land the secondary silently
-- (resist-scaled), so the handler infers them as ? on the hit (like BLU onDamage).
durations.pet = {
    [513] = {duration = 90, buffId = 3}, -- Poison Nails - Poison
    [522] = {duration = 90, buffId = 2}, -- Mewing Lullaby - Sleep
    [523] = {duration = 30, buffId = 6, buffIds = {6, 16}}, -- Eerie Eye - Silence (+ Amnesia)-- Silence 30s; Amnesia is 15s in LSB (shared timer uses Silence).
    [528] = {duration = 60, buffId = 5}, -- Moonlit Charge - Blind
    [529] = {duration = 60, buffId = 4}, -- Crescent Fang - Paralyze
    [530] = {duration = 180, buffId = 146, buffIds = {146, 148}}, -- Lunar Cry - Acc/Eva Down
    [560] = {duration = 120, buffId = 13}, -- Rock Throw - Slow
    [562] = {duration = 120, buffId = 11}, -- Rock Buster - Bind
    [563] = {duration = 120, buffId = 13}, -- Megalith Throw - Slow
    [566] = {duration = 60, buffId = 11}, -- Mountain Buster - Bind
    [567] = {duration = 4, buffId = 10}, -- Geocrush - Stun
    [578] = {duration = 120, buffId = 12}, -- Tail Whip - Weight
    [580] = {duration = 180, buffId = 13}, -- Slowga
    [585] = {duration = 60, buffId = 147}, -- Tidal Roar - Attack Down
    [611] = {duration = 90, buffId = 2}, -- Sleepga
    [624] = {duration = 12, buffId = 10}, -- Shock Strike - Stun
    [627] = {duration = 60, buffId = 4}, -- Thunderspark - Paralyze
    [630] = {duration = 12, buffId = 10}, -- Chaotic Strike - Stun
    [657] = {duration = 120, buffId = 12}, -- Somnolence - Weight
    [658] = {duration = 90, buffId = 2, buffIds = {2, 135}}, -- Nightmare - Sleep + Bio
    [1947] = {duration = 12, buffId = 156}, -- Flashbulb - Flash
    [2066] = {duration = 4, buffId = 10}, -- Daze - Stun
    [2067] = {duration = 30, buffId = 148}, -- Knockout - Evasion Down
    [2299] = {duration = 4, buffId = 10}, -- Bone Crusher - Stun
    [2744] = {duration = 150, buffId = 149}, -- Armor Shatterer - Defense Down
    [1908] = {duration = 90, buffId = 2, buffIds = {2, 135}}, -- Nightmare (mob-skill id form)
};

-- Additional-effect procs keyed by landed buff id. Max duration for that status.
durations.additionalEffect = {
    [2] = {duration = 25},   -- Sleep
    [3] = {duration = 90},   -- Poison
    [4] = {duration = 120},  -- Paralyze
    [5] = {duration = 180},  -- Blind
    [6] = {duration = 120},  -- Silence
    [10] = {duration = 5},   -- Stun
    [11] = {duration = 30},  -- Bind
    [12] = {duration = 30},  -- Weight / Gravity
    [13] = {duration = 180}, -- Slow
    [16] = {duration = 30},  -- Amnesia
    [28] = {duration = 10},  -- Terror
    [31] = {duration = 60},  -- Plague
    [130] = {duration = 90}, -- Choke
    [136] = {duration = 60}, -- STR Down
    [140] = {duration = 120}, -- INT Down
    [146] = {duration = 120}, -- Accuracy Down
    [147] = {duration = 120}, -- Attack Down
    [148] = {duration = 120}, -- Evasion Down
    [149] = {duration = 60}, -- Defense Down / Acid Bolt
    [156] = {duration = 12}, -- Flash
    [167] = {duration = 120}, -- Magic Def Down
    [168] = {duration = 100}, -- Inhibit TP
    [175] = {duration = 120}, -- Magic Atk Down
    [298] = {duration = 60}, -- Crit Hit Evasion Down
    [378] = {duration = 10}, -- Drain Daze (Drain Samba hits)
    [379] = {duration = 10}, -- Aspir Daze (Aspir Samba hits)
    [380] = {duration = 10}, -- Haste Daze (Haste Samba hits)
    [404] = {duration = 60}, -- Magic Evasion Down
    [448] = {duration = 60}, -- Bewildered Daze
    [463] = {duration = 180}, -- Sepulcher
    [464] = {duration = 180}, -- Arcane Crest
    [465] = {duration = 180}, -- Hamanoha
    [466] = {duration = 180}, -- Dragon Breaker
    [496] = {duration = 30}, -- Intervene
    [509] = {duration = 30}, -- Odyllic Subterfuge
    [536] = {duration = 60}, -- Gambit
    [571] = {duration = 30}, -- Rayke
    [576] = {duration = 30}, -- Doubt / Bully
    [798] = {duration = 10}, -- Chainbound
    [805] = {duration = 30}, -- Tomahawk
};

-- Mob self-buffs applied by mob skills, keyed by the landed status id (packet
-- Param). Any mob skill that grants status X shows this duration, so we don't
-- need to map every skill id. Durations are the max seen across LSB mobskills.
durations.mobBuff = {
    [33] = 180,   -- Haste
    [34] = 180,   -- Blaze Spikes
    [35] = 180,   -- Ice Spikes
    [36] = 180,   -- Blink
    [37] = 300,   -- Stoneskin
    [38] = 180,   -- Shock Spikes
    [40] = 300,   -- Protect
    [41] = 180,   -- Shell
    [42] = 300,   -- Regen
    [43] = 198,   -- Refresh
    [45] = 180,   -- Boost
    [56] = 180,   -- Berserk
    [61] = 300,   -- Counterstance
    [68] = 180,   -- Warcry
    [90] = 60,    -- Accuracy Boost
    [92] = 180,   -- Evasion Boost
    [93] = 300,   -- Defense Boost
    [94] = 1800,  -- Enfire
    [95] = 1800,  -- Enblizzard
    [96] = 1800,  -- Enaero
    [97] = 1800,  -- Enstone
    [98] = 1800,  -- Enthunder
    [99] = 1800,  -- Enwater
    [116] = 120,  -- Phalanx
    [150] = 60,   -- Physical Shield
    [151] = 60,   -- Arrow Shield
    [152] = 300,  -- Magic Shield
    [170] = 60,   -- Regain
    [190] = 300,  -- Magic Atk Boost
    [191] = 180,  -- Magic Def Boost
};

return durations;
