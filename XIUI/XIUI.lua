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
addon.version   = '1.6.22';
addon.desc      = 'Multiple UI elements with manager';
addon.link      = 'https://github.com/tirem/XIUI'

-- Ashita version targeting (for ImGui compatibility)
_G._XIUI_USE_ASHITA_4_3 = false;
require('handlers.imgui_compat');

-- =================
-- = XIUI DEV ONLY =
-- =================
local _XIUI_DEV_HOT_RELOADING_ENABLED = false;
local _XIUI_DEV_HOT_RELOAD_POLL_TIME_SECONDS = 1;
local _XIUI_DEV_HOT_RELOAD_LAST_RELOAD_TIME;
local _XIUI_DEV_HOT_RELOAD_FILES = {};

-- Debug flag for raw controller input (enable with /xiui debug rawinput)
-- This logs ALL xinput/dinput events from Ashita before any XIUI processing
DEBUG_RAW_INPUT = false;

require('common');
local settings = require('settings');
local gdi = require('submodules.gdifonts.include');

-- Core modules
local settingsDefaults = require('core.settings.init');
local settingsMigration = require('core.settings.migration');
local settingsUpdater = require('core.settings.updater');
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
local notifications = uiMods.notifications;
local treasurePool = uiMods.treasurepool;
local hotbar = uiMods.hotbar;
local macropalette = require('modules.hotbar.macropalette');
local configMenu = require('config');
local debuffHandler = require('handlers.debuffhandler');
local actionTracker = require('handlers.actiontracker');
local mobInfo = require('modules.mobinfo.init');
local statusHandler = require('handlers.statushandler');
local progressbar = require('libs.progressbar');
local diagnostics = require('libs.diagnostics');
local TextureManager = require('libs.texturemanager');

-- Global switch to hard-disable functionality that is limited on HX servers
HzLimitedMode = false;



-- Local split function for hot reload (avoids monkeypatching string metatable)
local function _split_string(str, sep)
    sep = sep or ":";
    local fields = {};
    local pattern = string.format("([^%s]+)", sep);
    str:gsub(pattern, function(c) fields[#fields + 1] = c end);
    return fields;
end

function _check_hot_reload()
    local path = string.gsub(addon.path, '\\\\', '\\');
    local result = io.popen("forfiles /P " .. path .. ' /M *.lua /C "cmd /c echo @file @fdate @ftime"');
    local needsReload = false;

    for line in result:lines() do
        if #line > 0 then
            local splitLine = _split_string(line, " ");
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
    hideOnMenuFocusKey = 'playerBarHideOnMenuFocus',
    hasSetHidden = true,
});
uiModules.Register('targetBar', {
    module = targetBar,
    settingsKey = 'targetBarSettings',
    configKey = 'showTargetBar',
    hideOnEventKey = 'targetBarHideDuringEvents',
    hideOnMenuFocusKey = 'targetBarHideOnMenuFocus',
    hasSetHidden = true,
});
uiModules.Register('enemyList', {
    module = enemyList,
    settingsKey = 'enemyListSettings',
    configKey = 'showEnemyList',
    hideOnMenuFocusKey = 'enemyListHideOnMenuFocus',
    hasSetHidden = true,
});
uiModules.Register('expBar', {
    module = expBar,
    settingsKey = 'expBarSettings',
    configKey = 'showExpBar',
    hideOnMenuFocusKey = 'expBarHideOnMenuFocus',
    hasSetHidden = true,
});
uiModules.Register('gilTracker', {
    module = gilTracker,
    settingsKey = 'gilTrackerSettings',
    configKey = 'showGilTracker',
    hideOnMenuFocusKey = 'gilTrackerHideOnMenuFocus',
    hasSetHidden = true,
});
uiModules.Register('inventoryTracker', {
    module = inventoryTracker,
    settingsKey = 'inventoryTrackerSettings',
    configKey = 'showInventoryTracker',
    hideOnMenuFocusKey = 'inventoryTrackerHideOnMenuFocus',
    hasSetHidden = true,
});
uiModules.Register('satchelTracker', {
    module = satchelTracker,
    settingsKey = 'satchelTrackerSettings',
    configKey = 'showSatchelTracker',
    hideOnMenuFocusKey = 'inventoryTrackerHideOnMenuFocus',
    hasSetHidden = true,
});
uiModules.Register('lockerTracker', {
    module = lockerTracker,
    settingsKey = 'lockerTrackerSettings',
    configKey = 'showLockerTracker',
    hideOnMenuFocusKey = 'inventoryTrackerHideOnMenuFocus',
    hasSetHidden = true,
});
uiModules.Register('safeTracker', {
    module = safeTracker,
    settingsKey = 'safeTrackerSettings',
    configKey = 'showSafeTracker',
    hideOnMenuFocusKey = 'inventoryTrackerHideOnMenuFocus',
    hasSetHidden = true,
});
uiModules.Register('storageTracker', {
    module = storageTracker,
    settingsKey = 'storageTrackerSettings',
    configKey = 'showStorageTracker',
    hideOnMenuFocusKey = 'inventoryTrackerHideOnMenuFocus',
    hasSetHidden = true,
});
uiModules.Register('wardrobeTracker', {
    module = wardrobeTracker,
    settingsKey = 'wardrobeTrackerSettings',
    configKey = 'showWardrobeTracker',
    hideOnMenuFocusKey = 'inventoryTrackerHideOnMenuFocus',
    hasSetHidden = true,
});
uiModules.Register('partyList', {
    module = partyList,
    settingsKey = 'partyListSettings',
    configKey = 'showPartyList',
    hideOnEventKey = 'partyListHideDuringEvents',
    hideOnMenuFocusKey = 'partyListHideOnMenuFocus',
    hasSetHidden = true,
});
uiModules.Register('castBar', {
    module = castBar,
    settingsKey = 'castBarSettings',
    configKey = 'showCastBar',
    hideOnMenuFocusKey = 'castBarHideOnMenuFocus',
    hasSetHidden = true,
});
uiModules.Register('castCost', {
    module = castCost,
    settingsKey = 'castCostSettings',
    configKey = 'showCastCost',
    hideOnMenuFocusKey = 'castCostHideOnMenuFocus',
    hasSetHidden = true,
});
uiModules.Register('mobInfo', {
    module = mobInfo.display,
    settingsKey = 'mobInfoSettings',
    configKey = 'showMobInfo',
    hideOnMenuFocusKey = 'mobInfoHideOnMenuFocus',
    hasSetHidden = true,
});
uiModules.Register('petBar', {
    module = petBar,
    settingsKey = 'petBarSettings',
    configKey = 'showPetBar',
    hideOnEventKey = 'petBarHideDuringEvents',
    hideOnMenuFocusKey = 'petBarHideOnMenuFocus',
    hasSetHidden = true,
});
uiModules.Register('notifications', {
    module = notifications,
    settingsKey = 'notificationsSettings',
    configKey = 'showNotifications',
    hideOnEventKey = 'notificationsHideDuringEvents',
    hideOnMenuFocusKey = 'notificationsHideOnMenuFocus',
    hasSetHidden = true,
});
uiModules.Register('treasurePool', {
    module = treasurePool,
    settingsKey = 'treasurePoolSettings',
    configKey = 'treasurePoolEnabled',
    hideOnMenuFocusKey = 'treasurePoolHideOnMenuFocus',
    hasSetHidden = true,
});
uiModules.Register('hotbar', {
    module = hotbar,
    settingsKey = 'hotbarSettings',
    configKey = 'showhotbar',
    hideOnEventKey = 'hotbarHideDuringEvents',
    hideOnMenuFocusKey = 'hotbarHideOnMenuFocus',
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
gConfigVersion = 0; -- Incremented on settings changes for cache invalidation
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
local wasInParty = false;  -- Tracks party state for detecting party leave

-- Check if player is currently in a party (has other members)
local function IsInParty()
    local party = AshitaCore:GetMemoryManager():GetParty();
    if party == nil then return false; end
    -- Check if any other party members (slots 1-5) are active
    for i = 1, 5 do
        if party:GetMemberIsActive(i) == 1 then
            return true;
        end
    end
    return false;
end

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

    -- Reset all module positions to defaults
    uiMods.playerbar.ResetPositions();
    uiMods.targetbar.ResetPositions();
    uiMods.castbar.ResetPositions();
    uiMods.enemylist.ResetPositions();
    uiMods.expbar.ResetPositions();
    uiMods.giltracker.ResetPositions();
    uiMods.partylist.ResetPositions();
    uiMods.inventory.ResetPositions();
    uiMods.castcost.ResetPositions();
    uiMods.petbar.ResetPositions();
    uiMods.notifications.ResetPositions();
    uiMods.treasurepool.ResetPositions();
    hotbar.ResetPositions();
end

function SavePartyListLayoutSetting(key, value)
    local currentLayout = (gConfig.partyListLayout == 1) and gConfig.partyListLayout2 or gConfig.partyListLayout1;
    currentLayout[key] = value;
end

function CheckVisibility()
    uiModules.CheckVisibility(gConfig);
end

function UpdateUserSettings()
    gConfigVersion = gConfigVersion + 1; -- Notify caches of settings change (for real-time slider updates)
    settingsUpdater.UpdateUserSettings(gAdjustedSettings, settingsDefaults.default_settings, gConfig);
end

function SaveSettingsToDisk()
    if gConfig.colorCustomization == nil then
        gConfig.colorCustomization = deep_copy_table(defaultUserSettings.colorCustomization);
    end
    gConfigVersion = gConfigVersion + 1; -- Notify caches of settings change
    settings.save();
end

function SaveSettingsOnly()
    if gConfig.colorCustomization == nil then
        gConfig.colorCustomization = deep_copy_table(defaultUserSettings.colorCustomization);
    end
    gConfigVersion = gConfigVersion + 1; -- Notify caches of settings change
    settings.save();
    UpdateUserSettings();
end

-- Module-specific visual updaters (includes disk save - use for dropdowns, checkboxes)
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
    -- Clear cached colors to pick up new settings
    InvalidateInterpolationColorCache();
    InvalidateColorCaches();
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
    local menuOpen = gameState.GetMenuName() ~= '';

    if not gameState.ShouldHideUI(gConfig.hideDuringEvents, bLoggedIn) then
        -- Sync treasure pool from memory (authoritative source of truth)
        -- This ensures we never miss items, even if packets were dropped
        if gConfig.showNotifications then
            notifications.SyncTreasurePoolFromMemory();
            -- Check pending pool items - creates "Treasure Pool" notification if item
            -- hasn't been awarded (0x00D3) within 200ms of dropping (0x00D2)
            notifications.CheckPendingPoolNotifications();
        end

        -- Render all registered modules
        for name, _ in pairs(uiModules.GetAll()) do
            uiModules.RenderModule(name, gConfig, gAdjustedSettings, eventSystemActive, menuOpen);
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
    statusHandler.clear_cache();
    progressbar.Cleanup();
    TextureManager.clear();
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

        -- Open macro palette: /xiui macro or /xiui macros
        if (#command_args == 2 and command_args[2]:any('macro', 'macros')) then
            macropalette.TogglePalette();
            return;
        end

        -- Open keybind editor: /xiui keybinds or /xiui binds [bar]
        if (#command_args >= 2 and command_args[2]:any('keybinds', 'keybind', 'binds', 'bind')) then
            local hotbarConfig = require('config.hotbar');
            local barIndex = tonumber(command_args[3]) or 1;
            hotbarConfig.OpenKeybindEditor(barIndex);
            return;
        end

        -- Lot all unlotted items: /xiui lotall or /xiui lot
        if (#command_args == 2 and command_args[2]:any('lotall', 'lot')) then
            treasurePool.LotAll();
            return;
        end

        -- Pass all unlotted items: /xiui passall or /xiui pass
        if (#command_args == 2 and command_args[2]:any('passall', 'pass')) then
            treasurePool.PassAll();
            return;
        end

        -- Toggle treasure pool window: /xiui tp
        if (#command_args == 2 and command_args[2]:any('tp', 'treasurepool', 'pool')) then
            treasurePool.ToggleForceShow();
            return;
        end

        -- Test notification command: /xiui testnotif [type]
        if (command_args[2] == 'testnotif') then
            local testType = tonumber(command_args[3]) or 5;  -- default to ITEM_OBTAINED
            notifications.TestNotification(testType, {
                itemId = 4096,  -- Hi-Potion
                itemName = 'Hi-Potion',
                quantity = 1,
                playerName = 'TestPlayer',
                amount = 5000,
            });
            return;
        end

        -- Test treasure pool with 10 items: /xiui testpool10
        if (command_args[2] == 'testpool10') then
            notifications.TestTreasurePool10();
            return;
        end

        -- Stress test treasure pool with 25 items: /xiui testpool25
        if (command_args[2] == 'testpool25') then
            notifications.TestTreasurePool25();
            return;
        end

        -- Test pool only (no toasts) - for crash isolation: /xiui testpoolonly
        if (command_args[2] == 'testpoolonly') then
            notifications.TestPoolOnly();
            return;
        end

        -- Test toasts only (no pool) - for crash isolation: /xiui testtoastsonly
        if (command_args[2] == 'testtoastsonly') then
            notifications.TestToastsOnly();
            return;
        end

        -- Hotbar keybind execution: /xiui hotbar <bar> <slot>
        -- Called by Ashita /bind system to execute hotbar actions
        if (command_args[2] == 'hotbar' and #command_args >= 4) then
            local barIndex = tonumber(command_args[3]);
            local slotIndex = tonumber(command_args[4]);
            if barIndex and slotIndex then
                local hotbarActions = require('modules.hotbar.actions');
                hotbarActions.HandleKeybind(barIndex, slotIndex);
            end
            return;
        end

        -- Palette commands: /xiui palette <name|next|prev> [bar|all]
        -- Switch between named palettes for hotbars
        -- Use "all" to affect all bars at once (like tHotBar behavior)
        if (command_args[2] == 'palette' or command_args[2] == 'pal') then
            local paletteModule = require('modules.hotbar.palette');
            local hotbarData = require('modules.hotbar.data');
            local jobId = hotbarData.jobId or 1;
            local subjobId = hotbarData.subjobId or 0;

            if #command_args < 3 then
                -- No argument - show current palette info and help
                print('[XIUI] Palette commands:');
                print('  /xiui palette <name> [bar|all] - Switch to a named palette');
                print('  /xiui palette next [bar|all] - Cycle to next palette');
                print('  /xiui palette prev [bar|all] - Cycle to previous palette');
                print('  /xiui palette list [bar] - List available palettes');
                print('  /xiui palette base [bar|all] - Return to Base palette');
                print('');
                print('Keybinds: Ctrl+Up/Down (configure in Hotbar > Palette Cycling)');
                print('Controller: RB + Dpad Up/Down cycles palettes');
                return;
            end

            local action = command_args[3];
            local barArg = command_args[4];
            local affectAll = (barArg == 'all');
            local barIndex = affectAll and 1 or (tonumber(barArg) or 1);

            -- Helper to apply action to bar(s)
            local function applyToBar(idx)
                return paletteModule.CyclePalette(idx, action == 'next' and 1 or -1, jobId, subjobId);
            end

            if action == 'next' or action == 'prev' or action == 'previous' then
                local direction = (action == 'next') and 1 or -1;
                if affectAll then
                    -- Cycle all bars together
                    local anyChanged = false;
                    local newPaletteName = nil;
                    for i = 1, 6 do
                        local result = paletteModule.CyclePalette(i, direction, jobId, subjobId);
                        if result then
                            anyChanged = true;
                            newPaletteName = result;
                        end
                    end
                    if anyChanged then
                        print('[XIUI] All bars palette: ' .. (newPaletteName or 'Base'));
                    else
                        print('[XIUI] No palettes to cycle');
                    end
                else
                    -- Cycle single bar
                    local newPalette = paletteModule.CyclePalette(barIndex, direction, jobId, subjobId);
                    if newPalette then
                        print('[XIUI] Bar ' .. barIndex .. ' palette: ' .. newPalette);
                    else
                        print('[XIUI] No palettes to cycle for bar ' .. barIndex);
                    end
                end
            elseif action == 'list' then
                -- List available palettes
                local palettes = paletteModule.GetAvailablePalettes(barIndex, jobId, subjobId);
                local currentPalette = paletteModule.GetActivePaletteDisplayName(barIndex);
                print('[XIUI] Bar ' .. barIndex .. ' palettes:');
                for _, name in ipairs(palettes) do
                    local marker = (name == currentPalette) and ' *' or '';
                    print('  - ' .. name .. marker);
                end
            elseif action == 'base' or action == 'reset' then
                -- Switch to base palette
                if affectAll then
                    for i = 1, 6 do
                        paletteModule.ClearActivePalette(i);
                    end
                    print('[XIUI] All bars palette: Base');
                else
                    paletteModule.ClearActivePalette(barIndex);
                    print('[XIUI] Bar ' .. barIndex .. ' palette: Base');
                end
            else
                -- Switch to named palette
                -- Reconstruct palette name in case it has spaces (use original case from command)
                local originalArgs = e.command:args();
                local paletteName = originalArgs[3];  -- Use original case
                local targetIsAll = false;

                if #originalArgs >= 4 then
                    local lastArg = originalArgs[#originalArgs];
                    if lastArg:lower() == 'all' then
                        targetIsAll = true;
                        -- Palette name is everything between arg 3 and "all"
                        if #originalArgs > 4 then
                            local nameParts = {};
                            for i = 3, #originalArgs - 1 do
                                table.insert(nameParts, originalArgs[i]);
                            end
                            paletteName = table.concat(nameParts, ' ');
                        end
                    elseif tonumber(lastArg) then
                        barIndex = tonumber(lastArg);
                        -- Palette name is everything between arg 3 and the bar number
                        if #originalArgs > 4 then
                            local nameParts = {};
                            for i = 3, #originalArgs - 1 do
                                table.insert(nameParts, originalArgs[i]);
                            end
                            paletteName = table.concat(nameParts, ' ');
                        end
                    else
                        -- No bar number or "all", palette name is all remaining args
                        local nameParts = {};
                        for i = 3, #originalArgs do
                            table.insert(nameParts, originalArgs[i]);
                        end
                        paletteName = table.concat(nameParts, ' ');
                    end
                end

                if targetIsAll then
                    -- Apply to all bars
                    local anyFound = false;
                    for i = 1, 6 do
                        if paletteModule.PaletteExists(i, paletteName, jobId, subjobId) then
                            paletteModule.SetActivePalette(i, paletteName);
                            anyFound = true;
                        end
                    end
                    if anyFound then
                        print('[XIUI] All bars palette: ' .. paletteName);
                    else
                        print('[XIUI] Palette "' .. paletteName .. '" not found');
                    end
                else
                    -- Apply to single bar
                    if paletteModule.PaletteExists(barIndex, paletteName, jobId, subjobId) then
                        paletteModule.SetActivePalette(barIndex, paletteName);
                        print('[XIUI] Bar ' .. barIndex .. ' palette: ' .. paletteName);
                    else
                        print('[XIUI] Palette "' .. paletteName .. '" not found for bar ' .. barIndex);
                    end
                end
            end
            return;
        end

        -- Diagnostics commands: /xiui diag [on|off|stats|reset]
        if (command_args[2] == 'diag') then
            local subCmd = command_args[3] or 'stats';
            if subCmd == 'on' or subCmd == 'enable' then
                diagnostics.Enable();
                print('[XIUI] Diagnostics enabled - resource tracking active');
            elseif subCmd == 'off' or subCmd == 'disable' then
                diagnostics.Disable();
                print('[XIUI] Diagnostics disabled');
            elseif subCmd == 'reset' then
                diagnostics.ResetStats();
                print('[XIUI] Diagnostics counters reset');
            else
                -- Default: print stats
                diagnostics.PrintStats();
            end
            return;
        end

        -- Debug commands: /xiui debug <module>
        -- Toggles debug logging for specific modules
        if (command_args[2] == 'debug') then
            local moduleName = command_args[3];
            if moduleName == 'hotbar' then
                -- Toggle hotbar debug mode
                local currentState = hotbar.IsDebugEnabled();
                hotbar.SetDebugEnabled(not currentState);
            elseif moduleName == 'macroblock' then
                -- Toggle macro block debug mode (both memory patches AND controller)
                local macrosLib = require('libs.ffxi.macros');
                local controller = require('modules.hotbar.controller');
                local currentState = macrosLib.is_debug_enabled();
                local newState = not currentState;
                macrosLib.set_debug_enabled(newState);
                controller.SetMacroBlockDebugEnabled(newState);
            elseif moduleName == 'rawinput' then
                -- Toggle raw input debug (logs ALL controller events from Ashita)
                DEBUG_RAW_INPUT = not DEBUG_RAW_INPUT;
                print('[XIUI] Raw input debug: ' .. (DEBUG_RAW_INPUT and 'ON' or 'OFF'));
                print('[XIUI] This logs ALL xinput/dinput events from Ashita before any processing.');
            elseif moduleName == 'palette' then
                -- Toggle palette key debug mode (logs Ctrl+Up/Down key events)
                local currentState = hotbar.IsPaletteDebugEnabled();
                hotbar.SetPaletteDebugEnabled(not currentState);
            else
                print('[XIUI] Debug modules: hotbar, macroblock, rawinput, palette');
                print('[XIUI] Usage: /xiui debug <module>');
            end
            return;
        end

        -- Reset gil tracking: /xiui gil reset (or legacy: /xiui resetgil)
        if (command_args[2] == 'gil' and command_args[3] == 'reset') or (command_args[2] == 'resetgil') then
            gilTracker.ResetTracking();
            return;
        end

        -- ============================================
        -- Cache Debug Commands
        -- ============================================

        -- Show progressbar cache statistics: /xiui cachestats
        if (command_args[2] == 'cachestats') then
            progressbar.PrintCacheStats();
            return;
        end

        -- Show texture cache statistics: /xiui texturestats
        if (command_args[2] == 'texturestats') then
            TextureManager.printStats();
            return;
        end

        -- Clear texture cache: /xiui textureclear
        if (command_args[2] == 'textureclear') then
            TextureManager.clear();
            print('[XIUI] TextureManager cache cleared');
            return;
        end

        -- Clear all caches: /xiui clearcache
        if (command_args[2] == 'clearcache') then
            progressbar.ForceClearCache();
            TextureManager.clear();
            statusHandler.clear_cache();
            print('[XIUI] All texture caches cleared');
            return;
        end

        -- Stress test gradient cache: /xiui stresscache [count]
        if (command_args[2] == 'stresscache') then
            local count = tonumber(command_args[3]) or 100;
            progressbar.StressTestCache(count);
            return;
        end

        -- Stress test texture manager: /xiui stresstextures [count]
        if (command_args[2] == 'stresstextures') then
            local count = tonumber(command_args[3]) or 150;
            print(string.format('[XIUI] Stress testing TextureManager with %d status icons...', count));
            local statsBefore = TextureManager.getStats();
            local beforeEvictions = statsBefore.categories.status_icons.evictions;

            -- Request many status icons (valid IDs are 0-640)
            for i = 0, count - 1 do
                TextureManager.getStatusIcon(i, nil);
            end

            local statsAfter = TextureManager.getStats();
            local afterEvictions = statsAfter.categories.status_icons.evictions;
            local newEvictions = afterEvictions - beforeEvictions;

            print(string.format('[XIUI] Created %d status icons, %d evictions triggered',
                statsAfter.categories.status_icons.size, newEvictions));
            TextureManager.printStats();
            return;
        end

        -- Force garbage collection: /xiui gc
        if (command_args[2] == 'gc') then
            local before = collectgarbage('count');
            collectgarbage('collect');
            local after = collectgarbage('count');
            print(string.format('[XIUI] Garbage collection: %.1f KB -> %.1f KB (freed %.1f KB)',
                before, after, before - after));
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

    -- Hotbar pet palette sync (0x0068 Pet Sync)
    if e.id == 0x0068 and gConfig.hotbarEnabled then
        hotbar.HandlePetSyncPacket();
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
            if gConfig.showNotifications then notifications.HandleActionPacket(actionPacket); end
        end
    elseif (e.id == 0x00E) then
        local mobUpdatePacket = ParseMobUpdatePacket(e);
        if gConfig.showEnemyList then enemyList.HandleMobUpdatePacket(mobUpdatePacket); end
    elseif (e.id == 0x00A) then
        -- Note: We do NOT clear treasure pool on zone - items persist across zones
        -- The server will send 0x00D2 packets to sync pool state after zoning
        notifications.HandleZonePacket();
        treasurePool.HandleZonePacket();
        enemyList.HandleZonePacket(e);
        partyList.HandleZonePacket(e);
        debuffHandler.HandleZonePacket(e);
        actionTracker.HandleZonePacket();
        mobInfo.data.HandleZonePacket(e);
        statusHandler.clear_zone_cache();  -- Clear status icon cache to prevent accumulation
        gilTracker.HandleZoneInPacket();  -- Only reset on fresh login, not zone changes (issue #111)
        TextureManager.clearOnZone();
        MarkPartyCacheDirty();
        ClearEntityCache();
        bLoggedIn = true;
        -- Initialize hotbar job on zone-in (handles initial login and job change during zone)
        if gConfig.hotbarEnabled then
            hotbar.HandleJobChangePacket(e);
        end
    elseif (e.id == 0x0029) then
        local messagePacket = ParseMessagePacket(e.data);
        if messagePacket then
            debuffHandler.HandleMessagePacket(messagePacket);
            if gConfig.showNotifications then
                notifications.HandleMessagePacket(e, messagePacket, 0x0029);
            end
        end
    elseif (e.id == 0x002D) then
        -- Kill message packet (item/gil rewards from defeating mobs)
        -- Same structure as 0x0029, used for post-combat notifications
        local messagePacket = ParseMessagePacket(e.data);
        if messagePacket then
            if gConfig.showNotifications then
                notifications.HandleMessagePacket(e, messagePacket, 0x002D);
            end
        end
    elseif (e.id == 0x002A) then
        -- Message Standard packet (zone/container messages)
        -- Different structure than 0x0029 - use ParseMessageStandardPacket
        local messagePacket = ParseMessageStandardPacket(e.data);
        if messagePacket then
            if gConfig.showNotifications then
                notifications.HandleMessagePacket(e, messagePacket, 0x002A);
            end
        end
    elseif (e.id == 0x00B) then
        notifications.HandleZonePacket();
        treasurePool.HandleZonePacket();
        gilTracker.HandleZoneOutPacket();  -- Track zone-out time for login detection (issue #111)
        TextureManager.clearOnZone();
        bLoggedIn = false;
        -- Also notify hotbar of zone (clears state)
        if gConfig.hotbarEnabled then
            hotbar.HandleZonePacket();
        end
    elseif (e.id == 0x001B) then
        -- Job change packet - update hotbar to show new job's actions
        if gConfig.hotbarEnabled then
            hotbar.HandleJobChangePacket(e);
        end
    elseif (e.id == 0x076) then
        statusHandler.ReadPartyBuffsFromPacket(e);
    elseif (e.id == 0x0DD) then
        MarkPartyCacheDirty();
        -- Detect party leave and clear treasure pool
        local currentlyInParty = IsInParty();
        if wasInParty and not currentlyInParty then
            -- Player left party - clear treasure pool (forfeited)
            notifications.ClearTreasurePool();
        end
        wasInParty = currentlyInParty;
    elseif (e.id == 0x00DC) then
        -- Party invite packet
        if gConfig.showNotifications and gConfig.notificationsShowPartyInvite then
            notifications.HandlePartyInvite(e);
        end
    elseif (e.id == 0x0021) then
        -- Trade request packet
        if gConfig.showNotifications and gConfig.notificationsShowTradeInvite then
            notifications.HandleTradeRequest(e);
        end
    elseif (e.id == 0x0022) then
        -- Trade response packet (cancel, complete, error, etc.)
        if gConfig.showNotifications then
            notifications.HandleTradeResponse(e);
        end
    elseif (e.id == 0x0020) then
        -- Inventory item update packet (item added to inventory)
        if gConfig.showNotifications and gConfig.notificationsShowItems then
            notifications.HandleInventoryUpdate(e);
        end
    elseif (e.id == 0x00D2) then
        -- Treasure pool update packet (item dropped to pool)
        if gConfig.showNotifications and gConfig.notificationsShowTreasure then
            notifications.HandleTreasurePool(e);
        end
    elseif (e.id == 0x00D3) then
        -- Treasure lot/drop packet (party member lotted or item awarded)
        -- Parse packet for treasure pool lot tracking (always, not just for notifications)
        local winnerServerId = struct.unpack('I4', e.data, 0x04 + 1);
        local entryServerId = struct.unpack('I4', e.data, 0x08 + 1);
        local winnerLot = struct.unpack('H', e.data, 0x0E + 1);
        local entryActIndexAndFlag = struct.unpack('H', e.data, 0x10 + 1);
        local entryFlg = bit.band(bit.rshift(entryActIndexAndFlag, 15), 1);
        local entryLot = struct.unpack('h', e.data, 0x12 + 1);  -- signed
        local slot = struct.unpack('B', e.data, 0x14 + 1);
        local judgeFlg = struct.unpack('B', e.data, 0x15 + 1);
        -- Extract names (16-byte null-terminated strings)
        local winnerNameRaw = struct.unpack('c16', e.data, 0x16 + 1);
        local entryNameRaw = struct.unpack('c16', e.data, 0x26 + 1);
        local winnerName = winnerNameRaw and winnerNameRaw:match('^[^%z]+') or '';
        local entryName = entryNameRaw and entryNameRaw:match('^[^%z]+') or '';

        -- Route to treasure pool module for lot history tracking
        if gConfig.treasurePoolEnabled then
            treasurePool.HandleLotPacket(slot, entryServerId, entryName, entryFlg, entryLot,
                                         winnerServerId, winnerName, winnerLot, judgeFlg);
        end

        -- Route to notifications handler
        if gConfig.showNotifications and gConfig.notificationsShowTreasure then
            notifications.HandleTreasureLot(e);
        end
    end
end);

-- ============================================
-- Outgoing Packet Handler
-- ============================================

ashita.events.register('packet_out', 'packet_out_cb', function (e)
    if (e.id == 0x0074) then
        -- Party invite response (accept/decline)
        if gConfig.showNotifications then
            notifications.HandlePartyInviteResponse(e);
        end
    end
end);

-- ============================================
--Key Handler
-- ============================================

--[[ Valid Arguments

    e.wparam     - (ReadOnly) The wparam of the event.
    e.lparam     - (ReadOnly) The lparam of the event.
    e.blocked    - (Writable) Flag that states if the key has been, or should be, blocked.

    See the following article for how to process and use wparam/lparam values:
    https://docs.microsoft.com/en-us/previous-versions/windows/desktop/legacy/ms644984(v=vs.85)

    Note: Key codes used here are considered 'virtual key codes'.
--]]

--[[ Note

        The game uses WNDPROC keyboard information to process keyboard input for chat and other
        user-inputted text prompts. (Bazaar comment, search comment, etc.)

        Blocking a press here will only block it during inputs of those types. It will not block
        in-game button handling for things such as movement, menu interactions, etc.
--]]
ashita.events.register('key', 'key_cb', function (event)
    hotbar.HandleKey(event);
end);

-- ============================================
-- Controller Input Event Handlers
-- ============================================

-- XInput controller state event (for crossbar mode - analog triggers)
ashita.events.register('xinput_state', 'xinput_state_cb', function (e)
    if DEBUG_RAW_INPUT then
        print('[XIUI RawInput] xinput_state event received');
    end
    hotbar.HandleXInputState(e);
end);

-- XInput button event (for blocking game macros when crossbar is active)
--[[ Valid Arguments
    e.button    - (Writable) The controller button id.
    e.state     - (Writable) The controller button state value.
    e.blocked   - (Writable) Flag that states if the button has been, or should be, blocked.
    e.injected  - (ReadOnly) Flag that states if the button was injected by Ashita or an addon/plugin.
--]]
ashita.events.register('xinput_button', 'xinput_button_cb', function (e)
    if DEBUG_RAW_INPUT then
        print(string.format('[XIUI RawInput] xinput_button: button=%d state=%d', e.button or -1, e.state or -1));
    end
    local shouldBlock = hotbar.HandleXInputButton(e);
    if shouldBlock then
        e.blocked = true;
    end
end);

-- DirectInput controller button event (for crossbar mode with DirectInput controllers)
-- Used by: DualSense, Switch Pro, Stadia controllers
ashita.events.register('dinput_button', 'dinput_button_cb', function (e)
    if DEBUG_RAW_INPUT then
        print(string.format('[XIUI RawInput] dinput_button: button=%d state=%d', e.button or -1, e.state or -1));
    end
    local shouldBlock = hotbar.HandleDInputButton(e);
    if shouldBlock then
        e.blocked = true;
    end
end);

-- DirectInput controller state event (for D-pad POV on DirectInput controllers)
ashita.events.register('dinput_state', 'dinput_state_cb', function (e)
    if DEBUG_RAW_INPUT then
        print('[XIUI RawInput] dinput_state event received');
    end
    hotbar.HandleDInputState(e);
end);

-- ============================================
-- NOTE: Render order is fixed by Ashita core: Primitives > GDI Fonts > ImGui
-- We cannot change this from addon level - ImGui always renders last.