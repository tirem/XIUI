--[[
* MIT License
*
* Copyright (c) 2023 tirem [github.com/tirem]
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
]]--

addon.name      = 'XIUI';
addon.author    = 'Team XIUI';
addon.version   = '1.5.4';
addon.desc      = 'Multiple UI elements with manager';
addon.link      = 'https://github.com/tirem/XIUI'

-- Ashita version targeting (for ImGui compatibility)
_G._XIUI_USE_ASHITA_4_3 = false;
require('handlers.imgui_compat');

require('common');
local settings = require('settings');
local gdi = require('submodules.gdifonts.include');

-- Core modules
local settingsDefaults = require('core.settingsdefaults');
local settingsMigration = require('core.settingsmigration');
local settingsUpdater = require('core.settingsupdater');
local gameState = require('core.gamestate');
local uiModules = require('core.moduleregistry');

-- UI modules
local uiMods = require('modules.init');
local playerBar = uiMods.playerbar;
local targetBar = uiMods.targetbar;
local enemyList = uiMods.enemylist;
local expBar = uiMods.expbar;
local gilTracker = uiMods.giltracker;
local inventoryTracker = uiMods.inventory.inventory;
local satchelTracker = uiMods.inventory.satchel;
local lockerTracker = uiMods.inventory.locker;
local safeTracker = uiMods.inventory.safe;
local storageTracker = uiMods.inventory.storage;
local wardrobeTracker = uiMods.inventory.wardrobe;
local partyList = uiMods.partylist;
local castBar = uiMods.castbar;
local petBar = uiMods.petbar;
local castCost = uiMods.castcost;
local configMenu = require('config');
local debuffHandler = require('handlers.debuffhandler');
local actionTracker = require('handlers.actiontracker');
local mobInfo = require('modules.mobinfo.init');
local statusHandler = require('handlers.statushandler');

-- Global switch to hard-disable functionality that is limited on HX servers
HzLimitedMode = true;

-- =================
-- = XIUI DEV ONLY =
-- =================
local _XIUI_DEV_HOT_RELOADING_ENABLED = false;
local _XIUI_DEV_HOT_RELOAD_POLL_TIME_SECONDS = 1;
local _XIUI_DEV_HOT_RELOAD_LAST_RELOAD_TIME;
local _XIUI_DEV_HOT_RELOAD_FILES = {};

function string:split(sep)
   local sep, fields = sep or ":", {}
   local pattern = string.format("([^%s]+)", sep)
   self:gsub(pattern, function(c) fields[#fields+1] = c end)
   return fields
end

function _check_hot_reload()
    local path = string.gsub(addon.path, '\\\\', '\\');
    local result = io.popen("forfiles /P " .. path .. ' /M *.lua /C "cmd /c echo @file @fdate @ftime"');
    local needsReload = false;

    for line in result:lines() do
        if #line > 0 then
            local splitLine = line:split(" ");
            local filename = splitLine[1];
            local dateModified = splitLine[2];
            local timeModified = splitLine[3];
            filename = string.gsub(filename, '"', '');
            local fileTable = {dateModified, timeModified};

            if _XIUI_DEV_HOT_RELOAD_FILES[filename] ~= nil then
                if table.concat(_XIUI_DEV_HOT_RELOAD_FILES[filename]) ~= table.concat(fileTable) then
                    needsReload = true;
                    print("[XIUI] Development file " .. filename .. " changed, reloading XIUI.")
                end
            end
            _XIUI_DEV_HOT_RELOAD_FILES[filename] = fileTable;
        end
    end
    result:close();

    if needsReload then
        AshitaCore:GetChatManager():QueueCommand(-1, '/addon reload xiui', channelCommand);
    end
end
-- ==================
-- = /XIUI DEV ONLY =
-- ==================

-- Register all UI modules
uiModules.Register('playerBar', {
    module = playerBar,
    settingsKey = 'playerBarSettings',
    configKey = 'showPlayerBar',
    hideOnEventKey = 'playerBarHideDuringEvents',
    hasSetHidden = true,
});
uiModules.Register('targetBar', {
    module = targetBar,
    settingsKey = 'targetBarSettings',
    configKey = 'showTargetBar',
    hideOnEventKey = 'targetBarHideDuringEvents',
    hasSetHidden = true,
});
uiModules.Register('enemyList', {
    module = enemyList,
    settingsKey = 'enemyListSettings',
    configKey = 'showEnemyList',
    hasSetHidden = true,
});
uiModules.Register('expBar', {
    module = expBar,
    settingsKey = 'expBarSettings',
    configKey = 'showExpBar',
    hasSetHidden = true,
});
uiModules.Register('gilTracker', {
    module = gilTracker,
    settingsKey = 'gilTrackerSettings',
    configKey = 'showGilTracker',
    hasSetHidden = true,
});
uiModules.Register('inventoryTracker', {
    module = inventoryTracker,
    settingsKey = 'inventoryTrackerSettings',
    configKey = 'showInventoryTracker',
    hasSetHidden = true,
});
uiModules.Register('satchelTracker', {
    module = satchelTracker,
    settingsKey = 'satchelTrackerSettings',
    configKey = 'showSatchelTracker',
    hasSetHidden = true,
});
uiModules.Register('lockerTracker', {
    module = lockerTracker,
    settingsKey = 'lockerTrackerSettings',
    configKey = 'showLockerTracker',
    hasSetHidden = true,
});
uiModules.Register('safeTracker', {
    module = safeTracker,
    settingsKey = 'safeTrackerSettings',
    configKey = 'showSafeTracker',
    hasSetHidden = true,
});
uiModules.Register('storageTracker', {
    module = storageTracker,
    settingsKey = 'storageTrackerSettings',
    configKey = 'showStorageTracker',
    hasSetHidden = true,
});
uiModules.Register('wardrobeTracker', {
    module = wardrobeTracker,
    settingsKey = 'wardrobeTrackerSettings',
    configKey = 'showWardrobeTracker',
    hasSetHidden = true,
});
uiModules.Register('partyList', {
    module = partyList,
    settingsKey = 'partyListSettings',
    configKey = 'showPartyList',
    hideOnEventKey = 'partyListHideDuringEvents',
    hasSetHidden = true,
});
uiModules.Register('castBar', {
    module = castBar,
    settingsKey = 'castBarSettings',
    configKey = 'showCastBar',
    hasSetHidden = true,
});
uiModules.Register('castCost', {
    module = castCost,
    settingsKey = 'castCostSettings',
    configKey = 'showCastCost',
    hasSetHidden = true,
});
uiModules.Register('mobInfo', {
    module = mobInfo.display,
    settingsKey = 'mobInfoSettings',
    configKey = 'showMobInfo',
    hasSetHidden = true,
});
uiModules.Register('petBar', {
    module = petBar,
    settingsKey = 'petBarSettings',
    configKey = 'showPetBar',
    hideOnEventKey = 'petBarHideDuringEvents',
    hasSetHidden = true,
});

-- Initialize settings from defaults
local user_settings_container = T{
    userSettings = settingsDefaults.user_settings;
};

gAdjustedSettings = deep_copy_table(settingsDefaults.default_settings);
defaultUserSettings = deep_copy_table(settingsDefaults.user_settings);

-- Run HXUI file migration BEFORE loading settings (so migrated files are picked up)
local migrationResult = settingsMigration.MigrateFromHXUI();

-- Load settings and run structure migrations
local config = settings.load(user_settings_container);
gConfig = config.userSettings;
settingsMigration.RunStructureMigrations(gConfig, defaultUserSettings);

-- Show migration message after settings are loaded (deferred to ensure chat is ready)
if migrationResult and migrationResult.count > 0 then
    ashita.tasks.once(1, function()
        print('[XIUI] Successfully migrated settings for ' .. migrationResult.count .. ' character(s) from HXUI.');
    end);
end

-- State variables
showConfig = { false };
local pendingVisualUpdate = false;
bLoggedIn = gameState.CheckLoggedIn();
local bInitialized = false;

-- Helper function to get party settings by index (1=A, 2=B, 3=C)
function GetPartySettings(partyIndex)
    if partyIndex == 3 then return gConfig.partyC;
    elseif partyIndex == 2 then return gConfig.partyB;
    else return gConfig.partyA;
    end
end

-- Helper function to get layout template for a party
function GetLayoutTemplate(partyIndex)
    local party = GetPartySettings(partyIndex);
    return party.layout == 1 and gConfig.layoutCompact or gConfig.layoutHorizontal;
end

function ResetSettings()
    gConfig = deep_copy_table(defaultUserSettings);
    config.userSettings = gConfig;
    UpdateSettings();
    settings.save();
end

function SavePartyListLayoutSetting(key, value)
    local currentLayout = (gConfig.partyListLayout == 1) and gConfig.partyListLayout2 or gConfig.partyListLayout1;
    currentLayout[key] = value;
end

function CheckVisibility()
    uiModules.CheckVisibility(gConfig);
end

function UpdateUserSettings()
    settingsUpdater.UpdateUserSettings(gAdjustedSettings, settingsDefaults.default_settings, gConfig);
end

function SaveSettingsToDisk()
    if gConfig.colorCustomization == nil then
        gConfig.colorCustomization = deep_copy_table(defaultUserSettings.colorCustomization);
    end
    settings.save();
end

function SaveSettingsOnly()
    if gConfig.colorCustomization == nil then
        gConfig.colorCustomization = deep_copy_table(defaultUserSettings.colorCustomization);
    end
    settings.save();
    UpdateUserSettings();
end

-- Module-specific visual updaters
UpdatePlayerBarVisuals = uiModules.CreateVisualUpdater('playerBar', SaveSettingsOnly, gAdjustedSettings);
UpdateTargetBarVisuals = uiModules.CreateVisualUpdater('targetBar', SaveSettingsOnly, gAdjustedSettings);
UpdatePartyListVisuals = uiModules.CreateVisualUpdater('partyList', SaveSettingsOnly, gAdjustedSettings);
UpdateEnemyListVisuals = uiModules.CreateVisualUpdater('enemyList', SaveSettingsOnly, gAdjustedSettings);
UpdateExpBarVisuals = uiModules.CreateVisualUpdater('expBar', SaveSettingsOnly, gAdjustedSettings);
UpdateInventoryTrackerVisuals = uiModules.CreateVisualUpdater('inventoryTracker', SaveSettingsOnly, gAdjustedSettings);
UpdateCastBarVisuals = uiModules.CreateVisualUpdater('castBar', SaveSettingsOnly, gAdjustedSettings);
UpdateCastCostVisuals = uiModules.CreateVisualUpdater('castCost', SaveSettingsOnly, gAdjustedSettings);

function UpdateGilTrackerVisuals()
    UpdateUserSettings();
    gilTracker.UpdateVisuals(gAdjustedSettings.gilTrackerSettings);
end

function UpdateSettings()
    SaveSettingsOnly();
    CheckVisibility();
    uiModules.UpdateVisualsAll(gAdjustedSettings);
end

function DeferredUpdateVisuals()
    pendingVisualUpdate = true;
end

settings.register('settings', 'settings_update', function (s)
    if (s ~= nil) then
        config = s;
        gConfig = config.userSettings;
        UpdateSettings();
    end
end);

--[[
* Event Handlers
]]--

ashita.events.register('d3d_present', 'present_cb', function ()
    if not bInitialized then return; end

    -- Process pending visual updates outside the render loop
    if pendingVisualUpdate then
        pendingVisualUpdate = false;
        statusHandler.clear_cache();
        UpdateUserSettings();
        uiModules.UpdateVisualsAll(gAdjustedSettings);
    end

    local eventSystemActive = gameState.GetEventSystemActive();

    if not gameState.ShouldHideUI(gConfig.hideDuringEvents, bLoggedIn) then
        -- Render all registered modules
        for name, _ in pairs(uiModules.GetAll()) do
            uiModules.RenderModule(name, gConfig, gAdjustedSettings, eventSystemActive);
        end

        configMenu.DrawWindow();
    else
        uiModules.HideAll();
    end

    -- XIUI DEV ONLY
    if _XIUI_DEV_HOT_RELOADING_ENABLED then
        local currentTime = os.time();
        if not _XIUI_DEV_HOT_RELOAD_LAST_RELOAD_TIME then
            _XIUI_DEV_HOT_RELOAD_LAST_RELOAD_TIME = currentTime;
        end
        if currentTime - _XIUI_DEV_HOT_RELOAD_LAST_RELOAD_TIME > _XIUI_DEV_HOT_RELOAD_POLL_TIME_SECONDS then
            _check_hot_reload();
            _XIUI_DEV_HOT_RELOAD_LAST_RELOAD_TIME = currentTime;
        end
    end
end);

ashita.events.register('load', 'load_cb', function ()
    UpdateUserSettings();
    uiModules.InitializeAll(gAdjustedSettings);

    -- Load mob data for current zone
    local party = AshitaCore:GetMemoryManager():GetParty();
    if party then
        local currentZone = party:GetMemberZone(0);
        if currentZone and currentZone > 0 then
            mobInfo.data.LoadZone(currentZone);
        end
    end

    bInitialized = true;
end);

ashita.events.register('unload', 'unload_cb', function ()
    ashita.events.unregister('d3d_present', 'present_cb');
    ashita.events.unregister('packet_in', 'packet_in_cb');
    ashita.events.unregister('command', 'command_cb');

    statusHandler.clear_cache();
    if ClearDebuffFontCache then ClearDebuffFontCache(); end

    uiModules.CleanupAll();

    if mobInfo.data and mobInfo.data.Cleanup then
        mobInfo.data.Cleanup();
    end

    gdi:destroy_interface();
end);

ashita.events.register('command', 'command_cb', function (e)
    local command_args = e.command:lower():args()
    if table.contains({'/xiui', '/hui', '/hxui', '/horizonxiui'}, command_args[1]) then
        e.blocked = true;

        if (#command_args == 1) then
            showConfig[1] = not showConfig[1];
            return;
        end

        if (#command_args == 2 and command_args[2]:any('partylist')) then
            gConfig.showPartyList = not gConfig.showPartyList;
            CheckVisibility();
            return;
        end
    end
end);

ashita.events.register('packet_in', 'packet_in_cb', function (e)
    expBar.HandlePacket(e)

    -- Pet bar packet handling (0x0028 Action, 0x0068 Pet Sync)
    if gConfig.showPetBar then
        petBar.HandlePacket(e);
    end

    if (e.id == 0x0028) then
        local actionPacket = ParseActionPacket(e);
        if actionPacket then
            if gConfig.showEnemyList then enemyList.HandleActionPacket(actionPacket); end
            if gConfig.showCastBar then castBar.HandleActionPacket(actionPacket); end
            if gConfig.showTargetBar and gConfig.showTargetBarCastBar and not HzLimitedMode then
                targetBar.HandleActionPacket(actionPacket);
            end
            if gConfig.showPartyList then partyList.HandleActionPacket(actionPacket); end
            debuffHandler.HandleActionPacket(actionPacket);
            actionTracker.HandleActionPacket(actionPacket);
        end
    elseif (e.id == 0x00E) then
        local mobUpdatePacket = ParseMobUpdatePacket(e);
        if gConfig.showEnemyList then enemyList.HandleMobUpdatePacket(mobUpdatePacket); end
    elseif (e.id == 0x00A) then
        enemyList.HandleZonePacket(e);
        partyList.HandleZonePacket(e);
        debuffHandler.HandleZonePacket(e);
        actionTracker.HandleZonePacket();
        mobInfo.data.HandleZonePacket(e);
        MarkPartyCacheDirty();
        ClearEntityCache();
        bLoggedIn = true;
    elseif (e.id == 0x0029) then
        local messagePacket = ParseMessagePacket(e.data);
        if messagePacket then debuffHandler.HandleMessagePacket(messagePacket); end
    elseif (e.id == 0x00B) then
        bLoggedIn = false;
    elseif (e.id == 0x076) then
        statusHandler.ReadPartyBuffsFromPacket(e);
    elseif (e.id == 0x0DD) then
        MarkPartyCacheDirty();
    end
end);
