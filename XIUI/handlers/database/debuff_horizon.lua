-- Horizon debuff overlay on handlers/database/debuff_retail.lua.
-- Only fields that differ from retail. Names and kinds stay on the base table.
-- Field value `false` clears a retail field during merge (e.g. fixed duration -> TP formula).
-- IDs / buffIds / land rules verified against horizonffxi.wiki (Mug, Energy Drain, Gale Axe,
-- Geirskogul, Blast Arrow/Shot, Nightmare Scythe). Duration and tpTier are Horizon-specific.

local overlay = {};

overlay.spells = {
    [25] = {duration = 150}, -- Dia III
    [232] = {duration = 150}, -- Bio III
    [235] = {duration = 120}, -- Burn
    [236] = {duration = 120}, -- Frost
    [237] = {duration = 120}, -- Choke
    [238] = {duration = 120}, -- Rasp
    [239] = {duration = 120}, -- Shock
    [240] = {duration = 120}, -- Drown
};

overlay.jaPhysical = {
    [46] = {duration = 6}, -- Shield Bash (type 3 path; keep in sync with ja)
    [77] = {duration = 6}, -- Weapon Bash (type 3 path; keep in sync with ja)
};

overlay.ja = {
    [46] = {duration = 6}, -- Shield Bash (type 6 path; keep in sync with jaPhysical)
    [77] = {duration = 6}, -- Weapon Bash (type 6 path; keep in sync with jaPhysical)
    [45] = {duration = 30, buffId = 448}, -- Mug - Bewildered Daze (always applies, even if gil steal fails)
};

overlay.weaponSkills = {
    [22] = {buffId = 13, uncertain = true, tpTier = {{1000, 90}, {2000, 150}, {3000, 210}}}, -- Energy Drain - Slow (Uncertain: strong Haste can block Slow with no reliable signal)
    [66] = {buffId = 12, duration = false, uncertain = true, tpTier = {{1000, 20}, {2000, 40}, {3000, 60}}}, -- Gale Axe - Weight (Replaces retail Choke)
    [121] = {duration = 30, buffId = 149, certainOnHit = true}, -- Geirskogul - Defense Down (Matches effect of Angon)
    [197] = {duration = 5, buffId = 10, uncertain = true}, -- Blast Arrow - Stun
    [213] = {duration = 5, buffId = 10, uncertain = true}, -- Blast Shot - Stun
    [99] = {buffId = 28, uncertain = true}, -- Nightmare Scythe - Terror (Replaces retail Blind)
};

return overlay;
