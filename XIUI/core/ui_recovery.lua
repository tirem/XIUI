--[[
* Per-module UI position recovery registry and helpers.
* Recovery moves windows to the top-left corner ({ x = 20, y = 20 }).
]]--

local persistedWindow = require('libs.persisted_window');

local M = {};

local RECOVER_ORIGIN = persistedWindow.RECOVER_ORIGIN;

local saveHandler = nil;
local recoverCommandsEnabled = false;

-- Modal-selectable modules (aligned with config.lua categories, excluding global).
local MODULE_REGISTRY = {
    { key = 'playerBar', aliases = { 'playerbar' }, keys = { 'PlayerBar' } },
    { key = 'targetBar', aliases = { 'targetbar' }, keys = { 'TargetBar' } },
    { key = 'enemyList', aliases = { 'enemylist' }, keys = { 'EnemyList' } },
    {
        key = 'partyList',
        aliases = { 'partylist' },
        keys = { 'PartyList', 'PartyList2', 'PartyList3' },
        onRecover = function()
            if gConfig then
                gConfig.partyListState = {};
            end
        end,
    },
    { key = 'expBar', aliases = { 'expbar' }, keys = { 'ExpBar' } },
    { key = 'gilTracker', aliases = { 'giltracker' }, keys = { 'GilTracker' } },
    {
        key = 'inventory',
        aliases = { 'inventory' },
        keys = {
            'InventoryTracker',
            'SatchelTracker',
            'SafeTracker',
            'StorageTracker',
            'LockerTracker',
            'WardrobeTracker',
        },
        patterns = {
            '^InventoryTracker_%d+$',
            '^SatchelTracker_%d+$',
            '^SafeTracker_%d+$',
            '^StorageTracker_%d+$',
            '^LockerTracker_%d+$',
            '^WardrobeTracker_%d+$',
        },
    },
    {
        key = 'satchel',
        aliases = { 'satchel' },
        keys = {
            'Satchel',
            'Satchel_SlipsPicker',
            'Satchel_SlipView',
            'Satchel_AltInventories',
            'Satchel_AltView',
        },
        patterns = { '^Satchel_' },
        excludePatterns = { '^SatchelTracker' },
        onRecover = function()
            require('modules.satchel.init').ResetPositions();
        end,
    },
    { key = 'castBar', aliases = { 'castbar' }, keys = { 'CastBar' } },
    { key = 'castCost', aliases = { 'castcost' }, keys = { 'CastCost' } },
    { key = 'petBar', aliases = { 'petbar' }, keys = { 'PetBar', 'PetBarTarget' } },
    { key = 'phantomRoll', aliases = { 'phantomroll' }, keys = { 'PhantomRoll' } },
    {
        key = 'notifications',
        aliases = { 'notifications' },
        keys = { 'BlueMagicLearned' },
        patterns = { '^Notifications_' },
    },
    { key = 'treasurePool', aliases = { 'treasurepool' }, keys = { 'TreasurePool' } },
    {
        key = 'hotbar',
        aliases = { 'hotbar' },
        keys = { 'Hotbar1', 'Hotbar2', 'Hotbar3', 'Hotbar4', 'Hotbar5', 'Hotbar6', 'Crossbar' },
    },
    {
        key = 'readyCheck',
        aliases = { 'readycheck' },
        keys = { 'ReadyCheck_Prompt', 'ReadyCheck_Tracker' },
    },
};

local registryByAlias = {};

for _, entry in ipairs(MODULE_REGISTRY) do
    for _, alias in ipairs(entry.aliases) do
        registryByAlias[alias] = entry;
    end
end

function M.Configure(opts)
    saveHandler = opts and opts.save or nil;
end

function M.IsCommandsEnabled()
    return recoverCommandsEnabled;
end

function M.ToggleCommands()
    recoverCommandsEnabled = not recoverCommandsEnabled;
    return recoverCommandsEnabled;
end

local function persist()
    if saveHandler then
        saveHandler();
    end
end

local function matchesAnyPattern(name, patterns)
    for _, pattern in ipairs(patterns) do
        if name:match(pattern) then
            return true;
        end
    end
    return false;
end

local function isExcluded(name, entry)
    return entry.excludePatterns and matchesAnyPattern(name, entry.excludePatterns);
end

local function collectWindowNames(entry)
    local names = {};
    local seen = {};

    local function add(name)
        if name and not seen[name] then
            seen[name] = true;
            names[#names + 1] = name;
        end
    end

    if entry.keys then
        for _, key in ipairs(entry.keys) do
            add(key);
        end
    end

    if gConfig and gConfig.windowPositions and entry.patterns then
        for windowName, _ in pairs(gConfig.windowPositions) do
            if matchesAnyPattern(windowName, entry.patterns) and not isExcluded(windowName, entry) then
                add(windowName);
            end
        end
    end

    return names;
end

local function setWindowPosition(windowName)
    if not gConfig then return; end
    if not gConfig.windowPositions then gConfig.windowPositions = {}; end
    gConfig.windowPositions[windowName] = { x = RECOVER_ORIGIN[1], y = RECOVER_ORIGIN[2] };
    if gConfig.appliedPositions then
        gConfig.appliedPositions[windowName] = nil;
    end
end

local function recoverEntry(entry)
    for _, windowName in ipairs(collectWindowNames(entry)) do
        setWindowPosition(windowName);
    end
    if entry.onRecover then
        entry.onRecover();
    end
end

local function runRecovery(entry)
    recoverEntry(entry);
    persist();
end

function M.RecoverModulePositionsByAlias(alias)
    if not alias or alias == '' then
        return false;
    end
    local entry = registryByAlias[alias:lower()];
    if not entry then
        return false;
    end
    runRecovery(entry);
    return true;
end

function M.RecoverSelectedModulePositions(selections)
    if not selections then
        return false;
    end

    local anySelected = false;
    for _, entry in ipairs(MODULE_REGISTRY) do
        local sel = selections[entry.key];
        if sel and sel[1] then
            anySelected = true;
            recoverEntry(entry);
        end
    end

    if not anySelected then
        return false;
    end

    persist();
    return true;
end

function M.RecoverAllModulePositions()
    if not gConfig then return; end
    if not gConfig.windowPositions then gConfig.windowPositions = {}; end

    for _, entry in ipairs(MODULE_REGISTRY) do
        recoverEntry(entry);
    end

    persist();
end

function M.RecoverConfigWindow()
    require('config').RecoverWindowPosition();
end

function M.RecoverCommandsWindow()
    require('libs.help').RecoverWindowPosition();
    persist();
end

return M;
