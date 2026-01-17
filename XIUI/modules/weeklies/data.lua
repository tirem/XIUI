--[[
* XIUI Weeklies Module - Data
* Contains static data for weekly objectives
]]--

local M = {};

-- Key Items
M.KeyItems = {
    ChocoboLicense           = { Id = 138, Name = "Chocobo License" },
    CenserOfAbandonment      = { Id = 670, Name = "Censer of Abandonment" },
    CenserOfAntipathy        = { Id = 671, Name = "Censer of Antipathy" },
    CenserOfAnimus           = { Id = 672, Name = "Censer of Animus" },
    CenserOfAcrimony         = { Id = 673, Name = "Censer of Acrimony" },
    MonarchBeard             = { Id = 674, Name = "Monarch Beard" },
    AstralCovenant           = { Id = 675, Name = "Astral Covenant" },
    ShaftLever               = { Id = 676, Name = "Shaft #2716 Operating Lever" },
    ZephyrFan                = { Id = 677, Name = "Zephyr Fan" },
    MiasmaFilter             = { Id = 678, Name = "Miasma Filter" },
    MonarchLinnPatrolPermit  = { Id = 720, Name = "Monarch Linn Patrol Permit" },
    LetterFromMithranTracker = { Id = 722, Name = "Letter from the Mithran Tracker" },
    CosmoCleanse             = { Id = 734, Name = "Cosmo Cleanse" },
};

-- Weekly Objectives
M.Objectives = {
    {
        Level = '75',
        Name = 'Limbus',
        KeyItem = M.KeyItems.CosmoCleanse,
        Cooldown = 72 * 3600,
        ZoneIds = { 37, 38, 246 },
    },
    {
        Level = '75',
        Name = 'Boneyard Gully',
        KeyItem = M.KeyItems.MiasmaFilter,
        Cooldown = 120 * 3600,
        ZoneIds = { 7, 8, 26 },
    },
    {
        Level = '75',
        Name = 'Boneyard Gully',
        KeyItem = M.KeyItems.LetterFromMithranTracker,
        Cooldown = "Conquest",
        ZoneIds = { 7, 8, 26 },
    },
    {
        Level = '75',
        Name = 'Bearclaw Pinnacle',
        KeyItem = M.KeyItems.ZephyrFan,
        Cooldown = 120 * 3600,
        ZoneIds = { 5, 6 },
    },
    {
        Level =  '60/75',
        Name = 'Mine Shaft #2716',
        KeyItem = M.KeyItems.ShaftLever,
        Cooldown = 120 * 3600,
        ZoneIds = { 11, 13 },
    },
    {
        Level = '75',
        Name = 'Monarch Linn',
        KeyItem = M.KeyItems.MonarchLinnPatrolPermit,
        Cooldown = "Conquest",
        ZoneIds = { 26, 31 },
    },
    {
        Level = '40/50',
        Name = 'Monarch Linn',
        KeyItem = M.KeyItems.MonarchBeard,
        Cooldown = 120 * 3600,
        ZoneIds = { 26, 31 },
    },
    {
        Level = '40',
        Name = 'The Shrouded Maw',
        KeyItem = M.KeyItems.AstralCovenant,
        Cooldown = 120 * 3600,
        ZoneIds = { 10, 245 },
    },
    {
        Level = '50',
        Name = 'Spire of Vahzl',
        KeyItem = M.KeyItems.CenserOfAcrimony,
        Cooldown = 120 * 3600,
        ZoneIds = { 23, 243 },
    },
    {
        Level = '30',
        Name = 'Spire of Holla',
        KeyItem = M.KeyItems.CenserOfAbandonment,
        Cooldown = 120 * 3600,
        ZoneIds = { 17, 243 },
    },
    {
        Level = '30',
        Name = 'Spire of Mea',
        KeyItem = M.KeyItems.CenserOfAnimus,
        Cooldown = 120 * 3600,
        ZoneIds = { 21, 243 },
    },
    {
        Level = '30',
        Name = 'Spire of Dem',
        KeyItem = M.KeyItems.CenserOfAntipathy,
        Cooldown = 120 * 3600,
        ZoneIds = { 19, 243 },
    },
};

return M;
