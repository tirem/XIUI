-- Static WS lookup table: weapon type, skill-level requirement, and relic flag.
-- Source: HorizonXI Weapon Skill Reference spreadsheet (141 entries, 14 weapon types).
-- "skill" = weapon skill level required to learn the WS (not character level).
-- "relic = true" means the WS requires having the corresponding relic weapon equipped.

return {
    -- Archery (8)
    ['Flaming Arrow']       = { weapon = 'Archery',        skill = 5 },
    ['Piercing Arrow']      = { weapon = 'Archery',        skill = 40 },
    ['Dulling Arrow']       = { weapon = 'Archery',        skill = 80 },
    ['Sidewinder']          = { weapon = 'Archery',        skill = 175 },
    ['Blast Arrow']         = { weapon = 'Archery',        skill = 200 },
    ['Arching Arrow']       = { weapon = 'Archery',        skill = 225 },
    ['Empyreal Arrow']      = { weapon = 'Archery',        skill = 250 },
    ['Namas Arrow']         = { weapon = 'Archery',        skill = 0, relic = true },

    -- Axe (10)
    ['Raging Axe']          = { weapon = 'Axe',            skill = 5 },
    ['Smash Axe']           = { weapon = 'Axe',            skill = 40 },
    ['Gale Axe']            = { weapon = 'Axe',            skill = 70 },
    ['Avalanche Axe']       = { weapon = 'Axe',            skill = 100 },
    ['Spinning Axe']        = { weapon = 'Axe',            skill = 150 },
    ['Rampage']             = { weapon = 'Axe',            skill = 175 },
    ['Calamity']            = { weapon = 'Axe',            skill = 200 },
    ['Mistral Axe']         = { weapon = 'Axe',            skill = 225 },
    ['Decimation']          = { weapon = 'Axe',            skill = 240 },
    ['Onslaught']           = { weapon = 'Axe',            skill = 0, relic = true },

    -- Club (11)
    ['Shining Strike']      = { weapon = 'Club',           skill = 5 },
    ['Starlight']           = { weapon = 'Club',           skill = 40 },
    ['Brainshaker']         = { weapon = 'Club',           skill = 70 },
    ['Seraph Strike']       = { weapon = 'Club',           skill = 100 },
    ['Moonlight']           = { weapon = 'Club',           skill = 125 },
    ['Skullbreaker']        = { weapon = 'Club',           skill = 150 },
    ['True Strike']         = { weapon = 'Club',           skill = 175 },
    ['Judgment']            = { weapon = 'Club',           skill = 200 },
    ['Hexa Strike']         = { weapon = 'Club',           skill = 220 },
    ['Black Halo']          = { weapon = 'Club',           skill = 230 },
    ['Randgrith']           = { weapon = 'Club',           skill = 0, relic = true },

    -- Dagger (11)
    ['Wasp Sting']          = { weapon = 'Dagger',         skill = 5 },
    ['Gust Slash']          = { weapon = 'Dagger',         skill = 40 },
    ['Shadowstitch']        = { weapon = 'Dagger',         skill = 70 },
    ['Viper Bite']          = { weapon = 'Dagger',         skill = 100 },
    ['Cyclone']             = { weapon = 'Dagger',         skill = 125 },
    ['Energy Steal']        = { weapon = 'Dagger',         skill = 150 },
    ['Energy Drain']        = { weapon = 'Dagger',         skill = 175 },
    ['Dancing Edge']        = { weapon = 'Dagger',         skill = 200 },
    ['Shark Bite']          = { weapon = 'Dagger',         skill = 225 },
    ['Evisceration']        = { weapon = 'Dagger',         skill = 230 },
    ['Mercy Stroke']        = { weapon = 'Dagger',         skill = 0, relic = true },

    -- Great Axe (10)
    ['Shield Break']        = { weapon = 'Great Axe',      skill = 5 },
    ['Iron Tempest']        = { weapon = 'Great Axe',      skill = 40 },
    ['Sturmwind']           = { weapon = 'Great Axe',      skill = 70 },
    ['Armor Break']         = { weapon = 'Great Axe',      skill = 100 },
    ['Keen Edge']           = { weapon = 'Great Axe',      skill = 150 },
    ['Weapon Break']        = { weapon = 'Great Axe',      skill = 175 },
    ['Raging Rush']         = { weapon = 'Great Axe',      skill = 200 },
    ['Full Break']          = { weapon = 'Great Axe',      skill = 225 },
    ['Steel Cyclone']       = { weapon = 'Great Axe',      skill = 240 },
    ['Metatron Torment']    = { weapon = 'Great Axe',      skill = 0, relic = true },

    -- Great Katana (10)
    ['Tachi: Enpi']         = { weapon = 'Great Katana',   skill = 5 },
    ['Tachi: Hobaku']       = { weapon = 'Great Katana',   skill = 30 },
    ['Tachi: Goten']        = { weapon = 'Great Katana',   skill = 70 },
    ['Tachi: Kagero']       = { weapon = 'Great Katana',   skill = 100 },
    ['Tachi: Jinpu']        = { weapon = 'Great Katana',   skill = 150 },
    ['Tachi: Koki']         = { weapon = 'Great Katana',   skill = 175 },
    ['Tachi: Yukikaze']     = { weapon = 'Great Katana',   skill = 200 },
    ['Tachi: Gekko']        = { weapon = 'Great Katana',   skill = 225 },
    ['Tachi: Kasha']        = { weapon = 'Great Katana',   skill = 250 },
    ['Tachi: Kaiten']       = { weapon = 'Great Katana',   skill = 0, relic = true },

    -- Great Sword (11)
    ['Hard Slash']          = { weapon = 'Great Sword',    skill = 5 },
    ['Power Slash']         = { weapon = 'Great Sword',    skill = 30 },
    ['Frostbite']           = { weapon = 'Great Sword',    skill = 70 },
    ['Freezebite']          = { weapon = 'Great Sword',    skill = 100 },
    ['Shockwave']           = { weapon = 'Great Sword',    skill = 150 },
    ['Crescent Moon']       = { weapon = 'Great Sword',    skill = 175 },
    ['Sickle Moon']         = { weapon = 'Great Sword',    skill = 200 },
    ['Spinning Slash']      = { weapon = 'Great Sword',    skill = 225 },
    ['Ground Strike']       = { weapon = 'Great Sword',    skill = 250 },
    ['Scourge']             = { weapon = 'Great Sword',    skill = 0, relic = true },

    -- Hand-to-Hand (10)
    ['Combo']               = { weapon = 'Hand-to-Hand',   skill = 5 },
    ['Shoulder Tackle']     = { weapon = 'Hand-to-Hand',   skill = 40 },
    ['One Inch Punch']      = { weapon = 'Hand-to-Hand',   skill = 75 },
    ['Backhand Blow']       = { weapon = 'Hand-to-Hand',   skill = 100 },
    ['Raging Fists']        = { weapon = 'Hand-to-Hand',   skill = 125 },
    ['Spinning Attack']     = { weapon = 'Hand-to-Hand',   skill = 150 },
    ['Howling Fist']        = { weapon = 'Hand-to-Hand',   skill = 200 },
    ['Dragon Kick']         = { weapon = 'Hand-to-Hand',   skill = 225 },
    ['Asuran Fists']        = { weapon = 'Hand-to-Hand',   skill = 250 },
    ['Final Heaven']        = { weapon = 'Hand-to-Hand',   skill = 0, relic = true },

    -- Katana (10)
    ['Blade: Rin']          = { weapon = 'Katana',         skill = 5 },
    ['Blade: Retsu']        = { weapon = 'Katana',         skill = 30 },
    ['Blade: Teki']         = { weapon = 'Katana',         skill = 70 },
    ['Blade: To']           = { weapon = 'Katana',         skill = 100 },
    ['Blade: Chi']          = { weapon = 'Katana',         skill = 150 },
    ['Blade: Ei']           = { weapon = 'Katana',         skill = 175 },
    ['Blade: Jin']          = { weapon = 'Katana',         skill = 200 },
    ['Blade: Ten']          = { weapon = 'Katana',         skill = 225 },
    ['Blade: Ku']           = { weapon = 'Katana',         skill = 250 },
    ['Blade: Metsu']        = { weapon = 'Katana',         skill = 0, relic = true },

    -- Marksmanship (8)
    ['Hot Shot']            = { weapon = 'Marksmanship',   skill = 5 },
    ['Split Shot']          = { weapon = 'Marksmanship',   skill = 40 },
    ['Sniper Shot']         = { weapon = 'Marksmanship',   skill = 80 },
    ['Slug Shot']           = { weapon = 'Marksmanship',   skill = 175 },
    ['Blast Shot']          = { weapon = 'Marksmanship',   skill = 200 },
    ['Heavy Shot']          = { weapon = 'Marksmanship',   skill = 225 },
    ['Detonator']           = { weapon = 'Marksmanship',   skill = 250 },
    ['Coronach']            = { weapon = 'Marksmanship',   skill = 0, relic = true },

    -- Polearm (10)
    ['Double Thrust']       = { weapon = 'Polearm',        skill = 5 },
    ['Thunder Thrust']      = { weapon = 'Polearm',        skill = 30 },
    ['Raiden Thrust']       = { weapon = 'Polearm',        skill = 70 },
    ['Leg Sweep']           = { weapon = 'Polearm',        skill = 100 },
    ['Penta Thrust']        = { weapon = 'Polearm',        skill = 150 },
    ['Vorpal Thrust']       = { weapon = 'Polearm',        skill = 175 },
    ['Skewer']              = { weapon = 'Polearm',        skill = 200 },
    ['Wheeling Thrust']     = { weapon = 'Polearm',        skill = 225 },
    ['Impulse Drive']       = { weapon = 'Polearm',        skill = 240 },
    ['Geirskogul']          = { weapon = 'Polearm',        skill = 0, relic = true },

    -- Scythe (10)
    ['Slice']               = { weapon = 'Scythe',         skill = 5 },
    ['Dark Harvest']        = { weapon = 'Scythe',         skill = 30 },
    ['Shadow of Death']     = { weapon = 'Scythe',         skill = 70 },
    ['Nightmare Scythe']    = { weapon = 'Scythe',         skill = 100 },
    ['Spinning Scythe']     = { weapon = 'Scythe',         skill = 125 },
    ['Vorpal Scythe']       = { weapon = 'Scythe',         skill = 150 },
    ['Guillotine']          = { weapon = 'Scythe',         skill = 200 },
    ['Cross Reaper']        = { weapon = 'Scythe',         skill = 225 },
    ['Spiral Hell']         = { weapon = 'Scythe',         skill = 240 },
    ['Catastrophe']         = { weapon = 'Scythe',         skill = 0, relic = true },

    -- Staff (10)
    ['Heavy Swing']         = { weapon = 'Staff',          skill = 5 },
    ['Rock Crusher']        = { weapon = 'Staff',          skill = 40 },
    ['Earth Crusher']       = { weapon = 'Staff',          skill = 70 },
    ['Starburst']           = { weapon = 'Staff',          skill = 100 },
    ['Sunburst']            = { weapon = 'Staff',          skill = 150 },
    ['Shell Crusher']       = { weapon = 'Staff',          skill = 175 },
    ['Full Swing']          = { weapon = 'Staff',          skill = 200 },
    ['Spirit Taker']        = { weapon = 'Staff',          skill = 215 },
    ['Retribution']         = { weapon = 'Staff',          skill = 230 },
    ['Gate of Tartarus']    = { weapon = 'Staff',          skill = 0, relic = true },

    -- Sword (12)
    ['Fast Blade']          = { weapon = 'Sword',          skill = 5 },
    ['Burning Blade']       = { weapon = 'Sword',          skill = 30 },
    ['Red Lotus Blade']     = { weapon = 'Sword',          skill = 50 },
    ['Flat Blade']          = { weapon = 'Sword',          skill = 75 },
    ['Shining Blade']       = { weapon = 'Sword',          skill = 100 },
    ['Seraph Blade']        = { weapon = 'Sword',          skill = 125 },
    ['Circle Blade']        = { weapon = 'Sword',          skill = 150 },
    ['Spirits Within']      = { weapon = 'Sword',          skill = 175 },
    ['Vorpal Blade']        = { weapon = 'Sword',          skill = 200 },
    ['Swift Blade']         = { weapon = 'Sword',          skill = 225 },
    ['Savage Blade']        = { weapon = 'Sword',          skill = 240 },
    ['Knights of Round']    = { weapon = 'Sword',          skill = 0, relic = true },
}
