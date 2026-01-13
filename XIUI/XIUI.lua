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
addon.version   = '1.6.23';
addon.desc      = 'Multiple UI elements with manager';
addon.link      = 'https://github.com/tirem/XIUI'

-- Ashita version targeting (for ImGui compatibility)
_G._XIUI_USE_ASHITA_4_3 = false;
require('handlers.imgui_compat');

require('common');
local chat = require('chat');
local settings = require('settings');
local gdi = require('submodules.gdifonts.include');

-- Core modules
local settingsDefaults = require('core.settings.init');
local settingsMigration = require('core.settings.migration');
local settingsUpdater = require('core.settings.updater');
local gameState = require('core.gamestate');
local uiModules = require('core.moduleregistry');
local profileManager = require('core.profile_manager');

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
local configMenu = require('config');
local debuffHandler = require('handlers.debuffhandler');
local actionTracker = require('handlers.actiontracker');
local mobInfo = require('modules.mobinfo.init');
local statusHandler = require('handlers.statushandler');
local progressbar = require('libs.progressbar');
local TextureManager = require('libs.texturemanager');

-- Global switch to hard-disable functionality that is limited on HX servers
HzLimitedMode = true;

-- Developer override to allow editing the Default profile
g_AllowDefaultEdit = false;

-- =================
-- = XIUI DEV ONLY =
-- =================
local _XIUI_DEV_HOT_RELOADING_ENABLED = false;
local _XIUI_DEV_HOT_RELOAD_POLL_TIME_SECONDS = 1;
local _XIUI_DEV_HOT_RELOAD_LAST_RELOAD_TIME;
local _XIUI_DEV_HOT_RELOAD_FILES = {};

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
                    print(chat.header(addon.name):append(chat.message("Development file " .. filename .. " changed, reloading XIUI.")));
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
uiModules.Register('notifications', {
    module = notifications,
    settingsKey = 'notificationsSettings',
    configKey = 'showNotifications',
    hideOnEventKey = 'notificationsHideDuringEvents',
    hasSetHidden = true,
});
uiModules.Register('treasurePool', {
    module = treasurePool,
    settingsKey = 'treasurePoolSettings',
    configKey = 'treasurePoolEnabled',
    hasSetHidden = true,
});

-- Initialize settings from defaults
gAdjustedSettings = deep_copy_table(settingsDefaults.default_settings);
defaultUserSettings = deep_copy_table(settingsDefaults.user_settings);

-- Run HXUI file migration BEFORE loading settings
local migrationResult = settingsMigration.MigrateFromHXUI();

-- ==========================================================
-- = MIGRATION LOGIC (Legacy -> Profile System) =
-- ==========================================================

-- Load raw settings to detect legacy data (without default filtering)
local rawSettings = settings.load({});

-- 1. Check for intermediate "profiles" table (from recent dev versions)
if (rawSettings.profiles ~= nil) then
    print(chat.header(addon.name):append(chat.message('Migrating internal profiles to file system...')));
    local globalProfiles = profileManager.GetGlobalProfiles();
    
    for name, data in pairs(rawSettings.profiles) do
        if not profileManager.ProfileExists(name) then
            profileManager.SaveProfileSettings(name, data);
        end
        if not table.contains(globalProfiles.names, name) then
            table.insert(globalProfiles.names, name);
            table.insert(globalProfiles.order, name);
        end
    end
    profileManager.SaveGlobalProfiles(globalProfiles);
    
    -- Clean up
    rawSettings.profiles = nil;
    rawSettings.profileOrder = nil;
    settings.save();
end

-- 2. Check for legacy flat settings (Global Scan)
local function MigrateAllLegacySettings()
    local installPath = AshitaCore:GetInstallPath();
    local xiuiPath = installPath .. 'config\\addons\\xiui\\';
    local imguiPath = installPath .. 'config\\imgui.ini';
    local imguiBakPath = installPath .. 'config\\imgui.bak';
    local legacyFound = false;

    -- Helper to list directories
    local function GetCharacterFolders()
        local folders = {};
        -- Use dir command to list directories
        local p = io.popen('dir "' .. xiuiPath .. '" /b /ad');
        if p then
            for dir in p:lines() do
                local name, id = string.match(dir, "^([%a]+)_(%d+)$");
                if name and id then
                    table.insert(folders, { name = name, id = id, dir = dir });
                end
            end
            p:close();
        end
        return folders;
    end

    local charFolders = GetCharacterFolders();

    -- Iterate and check for legacy settings
    for _, char in ipairs(charFolders) do
        local settingsPath = xiuiPath .. char.dir .. '\\settings.lua';
        
        if (ashita.fs.exists(settingsPath)) then
            -- Safely load settings table
            local success, result = pcall(dofile, settingsPath);
            
            if (success and type(result) == 'table' and result.currentProfile == nil and next(result) ~= nil) then
                -- FOUND LEGACY SETTINGS
                
                -- 1. Create global imgui.ini backup (Once)
                if (not legacyFound) then
                    legacyFound = true;
                    if (ashita.fs.exists(imguiPath)) then
                        local inp = io.open(imguiPath, "rb");
                        local outp = io.open(imguiBakPath, "wb");
                        if (inp and outp) then
                            outp:write(inp:read("*all"));
                            inp:close();
                            outp:close();
                            print(chat.header(addon.name):append(chat.message('Created imgui.ini backup at: ')):append(chat.success(imguiBakPath)));
                        end
                    end
                end
                
                -- 2. Backup character settings
                local backupPath = xiuiPath .. char.dir .. '\\settings.bak';
                local inp = io.open(settingsPath, "rb");
                local outp = io.open(backupPath, "wb");
                if (inp and outp) then
                    outp:write(inp:read("*all"));
                    inp:close();
                    outp:close();
                    print(chat.header(addon.name):append(chat.message('Created legacy settings backup at: ')):append(chat.success(backupPath)));
                end
                
                -- 3. Create Legacy Profile
                local profileName = 'Legacy ' .. char.name;
                local legacyData = deep_copy_table(defaultUserSettings);
                
                -- Merge settings
                if (result.userSettings ~= nil and type(result.userSettings) == 'table') then
                    for k, v in pairs(result.userSettings) do legacyData[k] = v; end
                    for k, v in pairs(result) do
                        if (k ~= 'profiles' and k ~= 'profileOrder' and k ~= 'userSettings' and result.userSettings[k] == nil) then
                            legacyData[k] = v;
                        end
                    end
                else
                    for k, v in pairs(result) do
                        if (k ~= 'profiles' and k ~= 'profileOrder') then
                            legacyData[k] = v;
                        end
                    end
                end
                
                -- Import window positions from imgui.ini (if available)
                local legacyPositions = profileManager.GetImguiPositions();
                if (legacyPositions) then
                    legacyData.windowPositions = legacyPositions;
                end
                
                -- Save Profile
                profileManager.SaveProfileSettings(profileName, legacyData);
                
                -- Register Global Profile
                local globalProfiles = profileManager.GetGlobalProfiles();
                if not table.contains(globalProfiles.names, profileName) then
                    table.insert(globalProfiles.names, profileName);
                    table.insert(globalProfiles.order, profileName);
                    profileManager.SaveGlobalProfiles(globalProfiles);
                end
                
                -- 4. Update settings.lua
                local f = io.open(settingsPath, "w+");
                if f then
                    f:write("return {\n");
                    f:write(string.format("    currentProfile = %q,\n", profileName));
                    f:write("};\n");
                    f:close();
                end
                
                print(chat.header(addon.name):append(chat.message('Migrated ' .. char.name .. ' to profile: ')):append(chat.success(profileName)));
            end
        end
    end
end

MigrateAllLegacySettings();

-- ==========================================================
-- = LOAD PROFILE SETTINGS =
-- ==========================================================

-- Load character settings (tracks which profile is active)
local charSettings = settings.load({ currentProfile = 'Default' });
config = charSettings; -- Keep reference to character config

-- Global profiles list
local globalProfiles = profileManager.GetGlobalProfiles();

-- Ensure Default profile exists
if (not profileManager.ProfileExists('Default')) then
    profileManager.SaveProfileSettings('Default', deep_copy_table(defaultUserSettings));
end

-- Load active profile
local currentProfileName = charSettings.currentProfile;
if (not profileManager.ProfileExists(currentProfileName)) then
    currentProfileName = 'Default';
    charSettings.currentProfile = 'Default';
    settings.save();
end

gConfig = profileManager.GetProfileSettings(currentProfileName);
    if (gConfig == nil) then
        -- Fallback if load fails
        gConfig = deep_copy_table(defaultUserSettings);
    end
    
    gConfig.appliedPositions = {};

    gConfigVersion = 0;
settingsMigration.RunStructureMigrations(gConfig, defaultUserSettings);

-- Show migration message


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

function CreateProfile(name)
    if (profileManager.ProfileExists(name)) then return false; end
    
    local newSettings = deep_copy_table(defaultUserSettings);
    profileManager.SaveProfileSettings(name, newSettings);
    
    local globalProfiles = profileManager.GetGlobalProfiles();
    table.insert(globalProfiles.names, name);
    table.insert(globalProfiles.order, name);
    profileManager.SaveGlobalProfiles(globalProfiles);
    
    ChangeProfile(name);
    return true;
end

function DuplicateProfile(name)
    local baseName = name;
    -- If duplicating Default, we might want to name it "Profile (1)" or just "Default (1)"
    
    local counter = 1;
    local newName = baseName .. " (" .. counter .. ")";
    
    while (profileManager.ProfileExists(newName)) do
        counter = counter + 1;
        newName = baseName .. " (" .. counter .. ")";
    end
    
    local currentSettings = profileManager.GetProfileSettings(name);
    if (currentSettings == nil) then return false; end
    
    local newSettings = deep_copy_table(currentSettings);
    profileManager.SaveProfileSettings(newName, newSettings);
    
    local globalProfiles = profileManager.GetGlobalProfiles();
    table.insert(globalProfiles.names, newName);
    table.insert(globalProfiles.order, newName);
    profileManager.SaveGlobalProfiles(globalProfiles);
    
    ChangeProfile(newName);
    return true;
end

local function GetDefaultWindowPositions()
    return {
        PlayerBar = { x = 20, y = 20 },
        TargetBar = { x = 20, y = 100 },
        PartyList = { x = 20, y = 200 },
        CastBar = { x = 300, y = 300 },
        Notifications_Group1 = { x = 800, y = 20 },
        Notifications_Group2 = { x = 800, y = 200 },
        TreasurePool = { x = 800, y = 200 },
        PetBar = { x = 300, y = 400 },
        ExpBar = { x = 20, y = 0 }, -- Top edge
        GilTracker = { x = 20, y = 500 },
        InventoryTracker = { x = 150, y = 500 },
    };
end

function ChangeProfile(name)
    if (not profileManager.ProfileExists(name)) then return false; end
    
    -- Save current settings before switching
    if (config.currentProfile ~= 'Default' or g_AllowDefaultEdit) then
        profileManager.SaveProfileSettings(config.currentProfile, gConfig);
    end
    
    config.currentProfile = name;
    settings.save(); -- Save character preference
    
    -- Clear textures to prevent ghosting
    TextureManager.clear();
    
    uiModules.HideAll();
    
    gConfig = profileManager.GetProfileSettings(name);
    gConfig.appliedPositions = {}; -- Ensure we re-apply positions for the new profile
    
    -- If Default profile has no saved positions, inject defaults
    if (name == 'Default' and (not gConfig.windowPositions or next(gConfig.windowPositions) == nil)) then
        gConfig.windowPositions = GetDefaultWindowPositions();
    end
    
    settingsMigration.RunStructureMigrations(gConfig, defaultUserSettings);
    UpdateSettings();
    return true;
end

function GetProfileNames()
    local globalProfiles = profileManager.GetGlobalProfiles();
    local profiles = {};
    for _, name in ipairs(globalProfiles.order) do
        table.insert(profiles, name);
    end
    table.sort(profiles);
    return profiles;
end

function GetCurrentProfileName()
    return config.currentProfile;
end

function ResetSettings()
    gConfig = deep_copy_table(defaultUserSettings);
    gConfig.appliedPositions = {};
    profileManager.SaveProfileSettings(config.currentProfile, gConfig);
    UpdateSettings();
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
    
    if (config.currentProfile ~= 'Default' or g_AllowDefaultEdit) then
        profileManager.SaveProfileSettings(config.currentProfile, gConfig);
    end
end

function SaveSettingsOnly()
    if gConfig.colorCustomization == nil then
        gConfig.colorCustomization = deep_copy_table(defaultUserSettings.colorCustomization);
    end
    gConfigVersion = gConfigVersion + 1; -- Notify caches of settings change
    
    if (config.currentProfile ~= 'Default' or g_AllowDefaultEdit) then
        profileManager.SaveProfileSettings(config.currentProfile, gConfig);
    end
    UpdateUserSettings();
end

-- New functions for profile management

function RenameProfile(oldName, newName)
    if (oldName == 'Default') then return false; end
    if (profileManager.ProfileExists(newName)) then return false; end
    if (not profileManager.ProfileExists(oldName)) then return false; end
    
    local settingsData = profileManager.GetProfileSettings(oldName);
    profileManager.SaveProfileSettings(newName, settingsData);
    profileManager.DeleteProfile(oldName);
    
    local globalProfiles = profileManager.GetGlobalProfiles();
    
    -- Update names list
    for i, name in ipairs(globalProfiles.names) do
        if name == oldName then
            globalProfiles.names[i] = newName;
            break;
        end
    end
    
    -- Update order list
    for i, name in ipairs(globalProfiles.order) do
        if name == oldName then
            globalProfiles.order[i] = newName;
            break;
        end
    end
    
    profileManager.SaveGlobalProfiles(globalProfiles);
    
    if (config.currentProfile == oldName) then
        config.currentProfile = newName;
        settings.save();
    end
    
    return true;
end

function DeleteProfile(name)
    if (name == 'Default') then return false; end
    
    -- If deleting the active profile, switch to Default first
    if (config.currentProfile == name) then
        if (not ChangeProfile('Default')) then
            return false;
        end
    end
    
    profileManager.DeleteProfile(name);
    
    local globalProfiles = profileManager.GetGlobalProfiles();
    
    -- Remove from names
    for i, n in ipairs(globalProfiles.names) do
        if n == name then
            table.remove(globalProfiles.names, i);
            break;
        end
    end
    
    -- Remove from order
    for i, n in ipairs(globalProfiles.order) do
        if n == name then
            table.remove(globalProfiles.order, i);
            break;
        end
    end
    
    profileManager.SaveGlobalProfiles(globalProfiles);
    return true;
end

function MoveProfileUp(name)
    local globalProfiles = profileManager.GetGlobalProfiles();
    local order = globalProfiles.order;
    
    for i, n in ipairs(order) do
        if n == name then
            if i > 1 then
                order[i], order[i-1] = order[i-1], order[i];
                profileManager.SaveGlobalProfiles(globalProfiles);
                return true;
            end
            break;
        end
    end
    return false;
end

function MoveProfileDown(name)
    local globalProfiles = profileManager.GetGlobalProfiles();
    local order = globalProfiles.order;
    
    for i, n in ipairs(order) do
        if n == name then
            if i < #order then
                order[i], order[i+1] = order[i+1], order[i];
                profileManager.SaveGlobalProfiles(globalProfiles);
                return true;
            end
            break;
        end
    end
    return false;
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

        -- Validate profile existence
        local currentProfileName = config.currentProfile;
        if (not profileManager.ProfileExists(currentProfileName)) then
            print(chat.header(addon.name):append(chat.message('Profile not found: ')):append(chat.error(currentProfileName)));
            currentProfileName = 'Default';
            config.currentProfile = 'Default';
            settings.save();
        end

        -- Reload profile settings
        local newGConfig = profileManager.GetProfileSettings(currentProfileName);
        if (newGConfig) then
            gConfig = newGConfig;
        else
            -- Fallback
             gConfig = deep_copy_table(defaultUserSettings);
        end
        
        -- Initialize runtime state
        gConfig.appliedPositions = {};
        
        -- Run migrations
        settingsMigration.RunStructureMigrations(gConfig, defaultUserSettings);
        
        -- Update visuals
        UpdateSettings();
        
        print(chat.header(addon.name):append(chat.message('Loaded profile: ')):append(chat.success(currentProfileName)));
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
    gConfig.appliedPositions = {};
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

        -- Reset gil tracking: /xiui gil reset (or legacy: /xiui resetgil)
        if (command_args[2] == 'gil' and command_args[3] == 'reset') or (command_args[2] == 'resetgil') then
            gilTracker.ResetTracking();
            return;
        end

        -- ============================================
        -- Profile Commands
        -- ============================================

        if (command_args[2] == 'profile') then
            -- /xiui profile reset
            if (command_args[3] == 'reset') then
                 configMenu.OpenResetSettingsPopup();
                 return;
            end
            
            -- /xiui profile next
            if (command_args[3] == 'next') then
                local profiles = GetProfileNames();
                local current = GetCurrentProfileName();
                local index = 0;
                for i, name in ipairs(profiles) do
                    if name == current then index = i; break; end
                end
                if index > 0 then
                    local nextIndex = (index % #profiles) + 1;
                    ChangeProfile(profiles[nextIndex]);
                    print(chat.header(addon.name):append(chat.message('Switched to profile: ')):append(chat.success(profiles[nextIndex])));
                end
                return;
            end

            -- /xiui profile previous
            if (command_args[3] == 'previous') then
                local profiles = GetProfileNames();
                local current = GetCurrentProfileName();
                local index = 0;
                for i, name in ipairs(profiles) do
                    if name == current then index = i; break; end
                end
                if index > 0 then
                    local prevIndex = (index - 2 + #profiles) % #profiles + 1;
                    ChangeProfile(profiles[prevIndex]);
                    print(chat.header(addon.name):append(chat.message('Switched to profile: ')):append(chat.success(profiles[prevIndex])));
                end
                return;
            end

            -- /xiui profile "name" (switch to profile)
            -- This catches anything else as a profile name
            if (command_args[3] ~= nil) then
                local profileName = command_args[3];
                if (ChangeProfile(profileName)) then
                     print(chat.header(addon.name):append(chat.message('Switched to profile: ')):append(chat.success(profileName)));
                else
                     print(chat.header(addon.name):append(chat.message('Profile not found: ')):append(chat.error(profileName)));
                end
                return;
            end
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
            print(chat.header(addon.name):append(chat.message('TextureManager cache cleared')));
            return;
        end

        -- Clear all caches: /xiui clearcache
        if (command_args[2] == 'clearcache') then
            progressbar.ForceClearCache();
            TextureManager.clear();
            statusHandler.clear_cache();
            print(chat.header(addon.name):append(chat.message('All texture caches cleared')));
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
            print(chat.header(addon.name):append(chat.message(string.format('Stress testing TextureManager with %d status icons...', count))));
            local statsBefore = TextureManager.getStats();
            local beforeEvictions = statsBefore.categories.status_icons.evictions;

            -- Request many status icons (valid IDs are 0-640)
            for i = 0, count - 1 do
                TextureManager.getStatusIcon(i, nil);
            end

            local statsAfter = TextureManager.getStats();
            local afterEvictions = statsAfter.categories.status_icons.evictions;
            local newEvictions = afterEvictions - beforeEvictions;

            print(chat.header(addon.name):append(chat.message(string.format('Created %d status icons, %d evictions triggered',
                statsAfter.categories.status_icons.size, newEvictions))));
            TextureManager.printStats();
            return;
        end

        -- Force garbage collection: /xiui gc
        if (command_args[2] == 'gc') then
            local before = collectgarbage('count');
            collectgarbage('collect');
            local after = collectgarbage('count');
            print(chat.header(addon.name):append(chat.message('Garbage collection: ')):append(chat.success(string.format('%.1f KB -> %.1f KB (freed %.1f KB)',
                before, after, before - after))));
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
        gilTracker.HandleZoneInPacket();  -- Only reset on fresh login, not zone changes (issue #111)
        TextureManager.clearOnZone();
        MarkPartyCacheDirty();
        ClearEntityCache();
        bLoggedIn = true;
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
