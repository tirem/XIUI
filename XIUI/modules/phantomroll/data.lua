--[[
* Phantom Roll potency tables (mirrors LSB corsair.lua).
]]--

local M = {};

local PCT, FLAT = 'pct', 'flat';

M.MAX_TOTAL = 11;
M.BUST_TOTAL = 12;
M.BASE_DURATION = 300;
M.JOB_ABILITY_CATEGORY = 6;
M.BUST_STATUS = 309;       -- occupies a roll seat after a bust
M.DOUBLE_UP_STATUS = 308;  -- window to Double-Up the last roll
M.DOUBLE_UP_DURATION = 45;
M.DOUBLE_UP_ABILITY = 123;

-- powers[1..11] + bust; step = Phantom Roll+1; bonus = party job boost; scale for Gallant's.
local ROLLS = {
    { name = "Fighter's",     ability =  98, status = 310, lucky = 5, unlucky =  9, job =  1, stat = 'Double Atk.', unit = PCT,  step =   1, bonus =   6,
      powers = {   2,   2,    3,   4,   12,    5,   6,    7,    1,    9,   18,   6 } },
    { name = "Monk's",        ability =  99, status = 311, lucky = 3, unlucky =  7, job =  2, stat = 'Subtle Blow', unit = PCT,  step =   4, bonus =  10,
      powers = {   8,  10,   32,  12,   14,   16,   4,   20,   22,   24,   40,  11 } },
    { name = "Healer's",      ability = 100, status = 312, lucky = 3, unlucky =  7, job =  3, stat = 'Cure Pot.',   unit = PCT,  step =   3, bonus =   4,
      powers = {   3,   4,   12,   5,    6,    7,   1,    8,    9,   10,   16,   4 } },
    { name = "Wizard's",      ability = 101, status = 313, lucky = 5, unlucky =  9, job =  4, stat = 'MAB',         unit = FLAT, step =   2, bonus =  10,
      powers = {   4,   6,    8,  10,   25,   12,  14,   17,    2,   20,   30,  10 } },
    { name = "Warlock's",     ability = 102, status = 314, lucky = 4, unlucky =  8, job =  5, stat = 'MACC',        unit = FLAT, step =   1, bonus =   5,
      powers = {   2,   3,    4,  12,    5,    6,   7,    1,    8,    9,   15,   5 } },
    { name = "Rogue's",       ability = 103, status = 315, lucky = 5, unlucky =  9, job =  6, stat = 'Crit Rate',   unit = PCT,  step =   1, bonus =   6,
      powers = {   2,   2,    3,   4,   12,    5,   6,    6,    1,    8,   19,   6 } },
    { name = "Gallant's",     ability = 104, status = 316, lucky = 3, unlucky =  7, job =  7, stat = 'Dmg Taken',   unit = PCT,  step = 234, bonus = 500, scale = 100,
      powers = { 600, 800, 2400, 900, 1100, 1200, 300, 1500, 1700, 1800, 3000, 500 } },
    { name = 'Chaos',         ability = 105, status = 317, lucky = 4, unlucky =  8, job =  8, stat = 'ATK',         unit = PCT,  step =   3, bonus =  10,
      powers = {   6,   8,    9,  25,   11,   13,  16,    3,   17,   19,   31,  10 } },
    { name = 'Beast',         ability = 106, status = 318, lucky = 4, unlucky =  8, job =  9, stat = 'Pet ATK',     unit = PCT,  step =   3, bonus =  10,
      powers = {   4,   5,    7,  19,    8,    9,  11,    2,   13,   14,   23,   7 } },
    { name = 'Choral',        ability = 107, status = 319, lucky = 2, unlucky =  6, job = 10, stat = 'Spell Intr.', unit = PCT,  step =   4, bonus =  25,
      powers = {  13,  55,   17,  20,   25,    8,  30,   35,   40,   45,   65,  25 } },
    { name = "Hunter's",      ability = 108, status = 320, lucky = 4, unlucky =  8, job = 11, stat = 'ACC',         unit = FLAT, step =   5, bonus =  15,
      powers = {  10,  13,   15,  40,   18,   20,  25,    5,   27,   30,   50,   5 } },
    { name = 'Samurai',       ability = 109, status = 321, lucky = 2, unlucky =  6, job = 12, stat = 'Store TP',    unit = FLAT, step =   4, bonus =  10,
      powers = {   8,  32,   10,  12,   14,    4,  16,   20,   22,   24,   40,   5 } },
    { name = 'Ninja',         ability = 110, status = 322, lucky = 4, unlucky =  8, job = 13, stat = 'EVA',         unit = FLAT, step =   2, bonus =   6,
      powers = {   4,   5,    5,  14,    6,    7,   9,    2,   10,   11,   18,   6 } },
    { name = 'Drachen',       ability = 111, status = 323, lucky = 4, unlucky =  8, job = 14, stat = 'Pet ACC',     unit = FLAT, step =   5, bonus =  15,
      powers = {  10,  13,   15,  40,   18,   20,  25,    5,   28,   30,   50,  15 } },
    { name = "Evoker's",      ability = 112, status = 324, lucky = 5, unlucky =  9, job = 15, stat = 'Refresh',     unit = FLAT, step =   1, bonus =   1,
      powers = {   1,   1,    1,   1,    3,    2,   2,    2,    1,    3,    4,   1 } },
    { name = "Magus's",       ability = 113, status = 325, lucky = 2, unlucky =  6, job = 16, stat = 'MDB',         unit = FLAT, step =   2, bonus =   8,
      powers = {   5,  20,    6,   8,    9,    3,  10,   13,   14,   15,   25,   5 } },
    { name = "Corsair's",     ability = 114, status = 326, lucky = 5, unlucky =  9, job = 17, stat = 'EXP',         unit = PCT,  step =   2, bonus =   0,
      powers = {  10,  11,   11,  12,   20,   13,  15,   16,    8,   17,   24,   6 } },
    { name = 'Puppet',        ability = 115, status = 327, lucky = 3, unlucky =  7, job = 18, stat = 'Pet MAB',     unit = FLAT, step =   3, bonus =   8,
      powers = {   4,   5,   18,   7,    9,   10,   2,   11,   13,   15,   22,   8 } },
    { name = "Dancer's",      ability = 116, status = 328, lucky = 3, unlucky =  7, job = 19, stat = 'Regen',       unit = FLAT, step =   2, bonus =   4,
      powers = {   3,   4,   12,   5,    6,    7,   1,    8,    9,   10,   16,   4 } },
    { name = "Scholar's",     ability = 117, status = 329, lucky = 2, unlucky =  6, job = 20, stat = 'Conserve MP', unit = FLAT, step =   1, bonus =   4,
      powers = {   2,   9,    3,   4,    5,    2,   6,    6,    7,    9,   14,   4 } },
    { name = "Bolter's",      ability = 118, status = 330, lucky = 3, unlucky =  9, job =  0, stat = 'Move Speed',  unit = PCT,  step =   4, bonus =   0,
      powers = {   6,   6,   16,   8,    8,   10,  10,   12,    4,   14,   20,   0 } },
    { name = "Caster's",      ability = 119, status = 331, lucky = 2, unlucky =  7, job =  0, stat = 'Fast Cast',   unit = PCT,  step =   3, bonus =  10,
      powers = {   6,  15,    7,   8,    9,   10,   5,   11,   12,   13,   20, -10 } },
    { name = "Courser's",     ability = 120, status = 332, lucky = 3, unlucky =  9, job =  0, stat = 'Snapshot',    unit = PCT,  step =   1, bonus =   3,
      powers = {   2,   3,   11,   4,    5,    6,   7,    8,    1,   10,   12,  -5 } },
    { name = "Blitzer's",     ability = 121, status = 333, lucky = 4, unlucky =  9, job =  0, stat = 'Atk Delay',   unit = PCT,  step =  -1, bonus =  -3,
      powers = {  -2,  -3,   -4, -11,   -5,   -6,  -7,   -8,   -1,  -10,  -12,   3 } },
    { name = "Tactician's",   ability = 122, status = 334, lucky = 5, unlucky =  8, job =  0, stat = 'Regain',      unit = FLAT, step =   2, bonus =  10,
      powers = {  10,  10,   10,  10,   30,   10,  10,    0,   20,   20,   40, -10 } },
    { name = "Allies'",       ability = 302, status = 335, lucky = 3, unlucky = 10, job =  0, stat = 'SC Dmg',      unit = PCT,  step =   1, bonus =   5,
      powers = {   2,   3,   20,   5,    7,    9,  11,   13,   15,    1,   25,  -5 } },
    { name = "Miser's",       ability = 303, status = 336, lucky = 5, unlucky =  7, job =  0, stat = 'Save TP',     unit = FLAT, step =  15, bonus =   0,
      powers = {  30,  50,   70,  90,  200,  110,  20,  130,  150,  170,  250,   0 } },
    { name = "Companion's",   ability = 304, status = 337, lucky = 2, unlucky = 10, job =  0, stat = 'Pet Regen',   unit = FLAT, step =  10, bonus =   0, unknown = true,
      powers = {   1,   2,    3,   4,    5,    6,   7,    8,    9,   10,   11,   0 } },
    { name = "Avenger's",     ability = 305, status = 338, lucky = 4, unlucky =  8, job =  0, stat = 'Counter',     unit = PCT,  step =   1, bonus =   0,
      powers = {   2,   2,    3,  12,    4,    5,   6,    1,    7,    9,   18,   6 } },
    { name = "Naturalist's",  ability = 390, status = 339, lucky = 3, unlucky =  7, job = 21, stat = 'Enh. Dur.',   unit = PCT,  step =   1, bonus =   5,
      powers = {   6,   7,   15,   8,    9,   10,   5,   11,   12,   13,   20,  -5 } },
    { name = "Runeist's",     ability = 391, status = 600, lucky = 4, unlucky =  8, job = 22, stat = 'MEVA',        unit = FLAT, step =   2, bonus =   7,
      powers = {   4,   6,    8,  25,   10,   12,  14,    2,   17,   20,   30, -10 } },
};

--[[
* Horizon: no party-job bonus. Main Job column from horizonffxi.wiki (lv75).
]]--
local HORIZON = {
    rolls = {
        ['Chaos'] = { unit = FLAT, perLevel = true, pctStep = 0.095, -- measured: Phantom Roll+ adds ~9.5% of native lv75 power per rank
          powers = { 29, 36, 39, 92, 45, 54, 61, 21, 64, 71, 111, -15 } },
        ["Gallant's"] = { unit = FLAT, stat = 'DEF', scale = 1, step = 4,
          powers = { 48, 60, 200, 72, 88, 104, 32, 120, 140, 160, 240, -120 } },
        ["Healer's"] = { unit = FLAT, stat = 'hMP', step = 1, -- measured: Phantom Roll+1 gear adds +1
          powers = { 2, 3, 10, 4, 4, 5, 1, 6, 6, 7, 12, -3 } },
        ["Evoker's"] = { noGearBonus = true, -- measured: Phantom Roll+ gear adds nothing to Evoker's
          powers = { 1, 1, 1, 1, 3, 2, 2, 2, 1, 2, 4, -1 } },
        ['Ninja'] = {
          powers = { 10, 13, 15, 40, 18, 20, 25, 5, 27, 30, 50, -15 } },
        ["Hunter's"] = { step = 3, -- measured in-game: Phantom Roll+1 gear adds +3, not retail's +5
          powers = { 10, 13, 15, 40, 18, 20, 25, 5, 27, 30, 50, -15 } },
        ["Magus's"] = {
          powers = { 5, 20, 6, 8, 9, 3, 10, 13, 14, 15, 25, -5 } },
        ['Choral'] = {
          powers = { -13, -55, -17, -20, -25, -8, -30, -35, -40, -45, -65, 25 } },
        ["Monk's"] = {
          powers = { 8, 10, 32, 12, 14, 16, 4, 20, 22, 24, 40, -11 } },
        ['Samurai'] = { step = 2, -- measured: Phantom Roll+1 gear adds +2 STP, not retail's +4
          powers = { 8, 32, 10, 12, 14, 4, 16, 20, 22, 24, 40, -5 } },
        ["Rogue's"] = {
          powers = { 2, 2, 3, 4, 12, 5, 6, 6, 1, 8, 19, -6 } },
        ["Warlock's"] = {
          powers = { 2, 3, 4, 12, 5, 6, 7, 1, 8, 9, 15, -5 } },
        ["Fighter's"] = {
          powers = { 2, 2, 3, 4, 12, 5, 6, 6, 1, 9, 18, -6 } },
        ['Drachen'] = {
          powers = { 10, 13, 15, 40, 18, 20, 25, 5, 27, 30, 50, 0 } },
        ["Wizard's"] = {
          powers = { 2, 3, 4, 4, 10, 5, 6, 7, 1, 7, 12, -4 } },
        ["Corsair's"] = {
          powers = { 10, 11, 11, 12, 20, 13, 15, 16, 8, 17, 24, -6 } },
        ['Puppet'] = {
          powers = { 4, 5, 18, 7, 9, 10, 2, 11, 13, 15, 22, -8 } },
    },
    gear = {
        [15601] = 1,  -- Corsair's Culottes
        [16348] = 1,  -- Cor. Culottes +1
        [26114] = 1,  -- Luzaf's Fang (right ear)
        [26115] = 1,  -- Luzaf's Fang +1 (right ear)
    },
};

-- Highest equipped Phantom Roll+ rank wins (not summed).
local ROLL_BONUS_GEAR = {
    [26038] = 7,
    [28548] = 5,
    [28547] = 3,
};

local BONUS_GEAR_SLOTS = { 7, 9, 12, 13, 14 };  -- legs, neck, r.ear, rings

local function BuildIndex(useHorizon)
    local byAbility = {};

    for _, base in ipairs(ROLLS) do
        local roll = base;
        local override = useHorizon and HORIZON.rolls[base.name];

        if override then
            roll = {};
            for key, value in pairs(base) do roll[key] = value; end
            for key, value in pairs(override) do roll[key] = value; end
        end

        byAbility[base.ability] = roll;
    end

    return byAbility;
end

local INDEX = { [false] = BuildIndex(false), [true] = BuildIndex(true) };

local TRACKED_STATUS = {
    [M.BUST_STATUS] = true,
    [M.DOUBLE_UP_STATUS] = true,
};
for i = 1, #ROLLS do
    TRACKED_STATUS[ROLLS[i].status] = true;
end

M.ByAbility = function(abilityId, horizonMode)
    return INDEX[horizonMode == true][abilityId];
end

M.IsTrackedStatus = function(statusId)
    return TRACKED_STATUS[statusId] == true;
end

local function EquippedRollBonus(horizonMode)
    local inventory = AshitaCore:GetMemoryManager():GetInventory();
    if inventory == nil then return 0; end

    local best = 0;
    for _, slot in ipairs(BONUS_GEAR_SLOTS) do
        local equipped = inventory:GetEquippedItem(slot);
        local index = equipped and bit.band(equipped.Index, 0x00FF) or 0;

        if index ~= 0 then
            local container = bit.rshift(bit.band(equipped.Index, 0xFF00), 8);
            local item = inventory:GetContainerItem(container, index);
            local bonus = item and item.Id ~= 0 and ROLL_BONUS_GEAR[item.Id];
            if bonus == nil and horizonMode and item and item.Id ~= 0 then
                bonus = HORIZON.gear[item.Id];
            end
            if bonus and bonus > best then best = bonus; end
        end
    end

    return best;
end

local function PartyJobs()
    local party = AshitaCore:GetMemoryManager():GetParty();
    if party == nil then return {}; end

    local present = {};
    for i = 0, 5 do
        if party:GetMemberIsActive(i) == 1 then
            present[party:GetMemberMainJob(i)] = true;
        end
    end
    return present;
end

local function PlayerLevel()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    return player and player:GetMainJobLevel() or 0;
end

M.Context = function(horizonMode)
    local horizon = horizonMode == true;
    return {
        gear = EquippedRollBonus(horizon),
        partyJobs = (not horizon) and PartyJobs() or nil,
        level = PlayerLevel(),
    };
end

M.Potency = function(roll, total, context)
    if roll == nil or roll.unknown or total == nil then return nil; end
    context = context or {};

    local power = roll.powers[total];
    if power == nil then return nil; end

    if total <= M.MAX_TOTAL then
        -- Gear % bonus (pctStep) is a fraction of the base lv75 power, before the
        -- party-job bonus and level scaling.
        local nativePower = power;

        local partyJobs = context.partyJobs or {};
        if partyJobs[roll.job] then power = power + roll.bonus; end

        if not roll.noGearBonus and roll.pctStep == nil then
            power = power + roll.step * (context.gear or 0);
        end

        if roll.perLevel then
            local level = context.level or 0;
            if level < 1 then level = 75; end
            power = math.floor(power * level / 75);
        end

        -- Percentage Phantom Roll+ (e.g. Chaos): added after level scaling.
        -- Measured ~9.5% of native power per rank.
        if not roll.noGearBonus and roll.pctStep ~= nil then
            power = power + math.floor(nativePower * roll.pctStep * (context.gear or 0));
        end
    end

    return power / (roll.scale or 1);
end

local function FormatValue(value)
    if math.abs(value % 1) < 0.05 then
        return string.format('%d', math.floor(math.abs(value) + 0.5));
    end
    return string.format('%.1f', math.abs(value));
end

M.PotencyText = function(roll, total, context)
    local value = M.Potency(roll, total, context);
    if value == nil or roll == nil then return ''; end

    local sign = (value < 0) and '-' or '+';
    local unit = (roll.unit == PCT) and '%' or '';
    return string.format('%s%s%s %s', sign, FormatValue(value), unit, roll.stat);
end

M.BustChance = function(total)
    if total == nil or total < 1 or total > M.MAX_TOTAL then return 0; end
    return math.max(0, total - 5) / 6;
end

M.IsLucky = function(roll, total)
    return roll ~= nil and total ~= nil and (total == M.MAX_TOTAL or total == roll.lucky);
end

M.IsUnlucky = function(roll, total)
    return roll ~= nil and total ~= nil and total == roll.unlucky;
end

return M;
