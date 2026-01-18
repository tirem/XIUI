--[[
* XIUI Config Menu - Notifications Settings
* Contains settings and color settings for Notifications
]]--

require('common');
require('handlers.helpers');
local components = require('config.components');
local imgui = require('imgui');
local notificationData = require('modules.notifications.data');

local M = {};

-- Test notification data for each type
-- Item IDs from FFXI resources (loaded via GetItemById)
local testData = {
    [notificationData.NOTIFICATION_TYPE.PARTY_INVITE] = {
        playerName = 'TestPlayer',
    },
    [notificationData.NOTIFICATION_TYPE.TRADE_INVITE] = {
        playerName = 'TestPlayer',
    },
    [notificationData.NOTIFICATION_TYPE.TREASURE_POOL] = {
        itemId = 13014,  -- Leaping Boots
        itemName = 'Leaping Boots',
        quantity = 1,
    },
    [notificationData.NOTIFICATION_TYPE.ITEM_OBTAINED] = {
        itemId = 4116,   -- Hi-Potion
        itemName = 'Hi-Potion',
        quantity = 3,
    },
    [notificationData.NOTIFICATION_TYPE.KEY_ITEM_OBTAINED] = {
        itemId = 1,
        itemName = 'Adventurer Certificate',
    },
    [notificationData.NOTIFICATION_TYPE.GIL_OBTAINED] = {
        amount = 12500,
    },
};

-- Trigger a test notification
local function triggerTestNotification(notifType)
    notificationData.Add(notifType, testData[notifType] or {});
end

-- Clear notifications of a specific type
local function clearNotificationType(notifType)
    notificationData.RemoveByType(notifType);
end

-- Draw a checkbox with a test button on the same line
-- For persistent types (party/trade), also add a clear button
local function DrawCheckboxWithTest(label, configKey, notifType)
    components.DrawCheckbox(label, configKey);
    imgui.SameLine();
    if imgui.SmallButton('Test##' .. configKey) then
        triggerTestNotification(notifType);
    end
    -- Add clear button for persistent notification types
    if notificationData.IsPersistentType(notifType) then
        imgui.SameLine();
        if imgui.SmallButton('Clear##' .. configKey) then
            clearNotificationType(notifType);
        end
    end
end

-- Map of notification type keys to their config enable keys
local typeConfigKeys = {
    partyInvite = 'notificationsShowPartyInvite',
    tradeInvite = 'notificationsShowTradeInvite',
    treasurePool = 'notificationsShowTreasure',
    itemObtained = 'notificationsShowItems',
    keyItemObtained = 'notificationsShowKeyItems',
    gilObtained = 'notificationsShowGil',
};

-- Map of notification type keys to their display labels
local typeLabels = {
    partyInvite = 'Party Invites',
    tradeInvite = 'Trade Requests',
    treasurePool = 'Treasure Pool',
    itemObtained = 'Items Obtained',
    keyItemObtained = 'Key Items',
    gilObtained = 'Gil',
};

-- Map of notification type keys to notification data type constants
local typeToNotifType = {
    partyInvite = notificationData.NOTIFICATION_TYPE.PARTY_INVITE,
    tradeInvite = notificationData.NOTIFICATION_TYPE.TRADE_INVITE,
    treasurePool = notificationData.NOTIFICATION_TYPE.TREASURE_POOL,
    itemObtained = notificationData.NOTIFICATION_TYPE.ITEM_OBTAINED,
    keyItemObtained = notificationData.NOTIFICATION_TYPE.KEY_ITEM_OBTAINED,
    gilObtained = notificationData.NOTIFICATION_TYPE.GIL_OBTAINED,
};

-- Track which group we're currently drawing (for unique widget IDs)
local currentDrawingGroup = 1;

-- Draw group-specific slider (saves to notificationGroupN table)
local function DrawGroupSlider(groupSettings, label, configKey, min, max, format, callback)
    local value = { groupSettings[configKey] };
    local changed = false;
    local uniqueLabel = label .. '##group' .. currentDrawingGroup .. '_' .. configKey;

    if format ~= nil then
        changed = imgui.SliderFloat(uniqueLabel, value, min, max, format);
    elseif type(groupSettings[configKey]) == 'number' and math.floor(groupSettings[configKey]) == groupSettings[configKey] then
        changed = imgui.SliderInt(uniqueLabel, value, min, max);
    else
        changed = imgui.SliderFloat(uniqueLabel, value, min, max, '%.2f');
    end

    if changed then
        groupSettings[configKey] = value[1];
        if callback then callback() end
        UpdateUserSettings();
    end

    if (imgui.IsItemDeactivatedAfterEdit()) then
        SaveSettingsToDisk();
    end
end

-- Draw settings for a specific group
local function DrawGroupSettings(groupNum)
    currentDrawingGroup = groupNum;
    local groupKey = 'notificationGroup' .. groupNum;
    local groupSettings = gConfig[groupKey];
    if not groupSettings then return; end

    -- Stack Direction dropdown
    local stackDirections = {'Down', 'Up'};
    local stackDirectionValues = {'down', 'up'};
    local currentDirIndex = groupSettings.direction == 'up' and 2 or 1;
    imgui.SetNextItemWidth(100);
    if imgui.BeginCombo('Stack Direction##group' .. groupNum, stackDirections[currentDirIndex]) then
        for i, label in ipairs(stackDirections) do
            if imgui.Selectable(label, i == currentDirIndex) then
                groupSettings.direction = stackDirectionValues[i];
                notificationData.ClearGroupAnchor(groupNum);
                SaveSettingsOnly();
            end
        end
        imgui.EndCombo();
    end
    imgui.ShowHelp('Direction notifications stack. Up: window anchors at bottom, grows upward. Down: window anchors at top, grows downward.');

    -- Progress Bar Direction dropdown
    local progressBarDirections = {'Left', 'Right'};
    local progressBarDirectionValues = {'left', 'right'};
    local currentBarDirIndex = groupSettings.progressBarDirection == 'right' and 2 or 1;
    imgui.SetNextItemWidth(100);
    if imgui.BeginCombo('Progress Bar Direction##group' .. groupNum, progressBarDirections[currentBarDirIndex]) then
        for i, label in ipairs(progressBarDirections) do
            if imgui.Selectable(label, i == currentBarDirIndex) then
                groupSettings.progressBarDirection = progressBarDirectionValues[i];
                SaveSettingsOnly();
            end
        end
        imgui.EndCombo();
    end
    imgui.ShowHelp('Direction the progress bar drains as time elapses.');

    DrawGroupSlider(groupSettings, 'Max Visible', 'maxVisible', 1, 10, '%.0f');
    imgui.ShowHelp('Maximum notifications shown at once');
    DrawGroupSlider(groupSettings, 'Display Duration', 'displayDuration', 1.0, 10.0, '%.1f sec');
    DrawGroupSlider(groupSettings, 'Minimize Time', 'inviteMinifyTimeout', 3.0, 30.0, '%.0f sec');
    imgui.ShowHelp('Party and trade invites minimize after this time but stay pinned');

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    DrawGroupSlider(groupSettings, 'Scale X', 'scaleX', 0.5, 2.0, '%.1f');
    DrawGroupSlider(groupSettings, 'Scale Y', 'scaleY', 0.5, 2.0, '%.1f');
    DrawGroupSlider(groupSettings, 'Progress Bar Scale Y', 'progressBarScaleY', 0.5, 3.0, '%.1f');
    imgui.ShowHelp('Height scale for the countdown progress bar');
    DrawGroupSlider(groupSettings, 'Padding', 'padding', 2, 16, '%.0f px');
    DrawGroupSlider(groupSettings, 'Spacing', 'spacing', 0, 24, '%.0f px');
    imgui.ShowHelp('Space between notifications in the list');

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    DrawGroupSlider(groupSettings, 'Title Text Size', 'titleFontSize', 8, 24, '%.0f');
    DrawGroupSlider(groupSettings, 'Subtitle Text Size', 'subtitleFontSize', 8, 24, '%.0f');

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Background Theme dropdown
    local bgThemes = {'-None-', 'Plain', 'Window1', 'Window2', 'Window3', 'Window4', 'Window5', 'Window6', 'Window7', 'Window8'};
    local currentTheme = groupSettings.backgroundTheme or 'Plain';
    imgui.SetNextItemWidth(150);
    if imgui.BeginCombo('Theme##group' .. groupNum, currentTheme) then
        for _, theme in ipairs(bgThemes) do
            if imgui.Selectable(theme, theme == currentTheme) then
                groupSettings.backgroundTheme = theme;
                DeferredUpdateVisuals();
            end
        end
        imgui.EndCombo();
    end
    imgui.ShowHelp('Select the background window theme for this group.');

    DrawGroupSlider(groupSettings, 'Background Scale', 'bgScale', 0.1, 3.0, '%.2f', DeferredUpdateVisuals);
    imgui.ShowHelp('Scale of the background texture.');
    DrawGroupSlider(groupSettings, 'Border Scale', 'borderScale', 0.1, 3.0, '%.2f', DeferredUpdateVisuals);
    imgui.ShowHelp('Scale of the window borders (Window themes only).');
    DrawGroupSlider(groupSettings, 'Background Opacity', 'bgOpacity', 0.0, 1.0, '%.2f');
    imgui.ShowHelp('Opacity of the background.');
    DrawGroupSlider(groupSettings, 'Border Opacity', 'borderOpacity', 0.0, 1.0, '%.2f');
    imgui.ShowHelp('Opacity of the window borders (Window themes only).');
end

-- Section: Notifications Settings
function M.DrawSettings()
    components.DrawCheckbox('Enabled', 'showNotifications', CheckVisibility);
    components.DrawCheckbox('Hide When Menu Open', 'notificationsHideOnMenuFocus');
    imgui.ShowHelp('Hide this module when a game menu is open (equipment, map, etc.).');
    components.DrawCheckbox('Hide During Events', 'notificationsHideDuringEvents');

    -- Group count slider (outside collapsible sections)
    local groupCountValue = { gConfig.notificationGroupCount or 2 };
    if imgui.SliderInt('Number of Groups', groupCountValue, notificationData.MIN_GROUPS, notificationData.MAX_GROUPS) then
        local oldCount = gConfig.notificationGroupCount or 2;
        local newCount = groupCountValue[1];
        gConfig.notificationGroupCount = newCount;

        -- If reducing group count, reassign types from removed groups to group 1
        if newCount < oldCount then
            local typeGroup = gConfig.notificationTypeGroup;
            if typeGroup then
                for typeKey, assignedGroup in pairs(typeGroup) do
                    if assignedGroup > newCount then
                        typeGroup[typeKey] = 1;
                    end
                end
            end
        end
        UpdateUserSettings();
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then
        -- Trigger resource recreation for new group count
        DeferredUpdateVisuals();
        SaveSettingsToDisk();
    end
    imgui.ShowHelp('Number of independent notification groups (2-6). Each group has its own position and settings.');

    imgui.Spacing();

    -- Show each group's settings in its own collapsible section
    local maxGroups = gConfig.notificationGroupCount or 2;
    for groupNum = 1, maxGroups do
        local sectionLabel = 'Group ' .. groupNum .. '##groupSection' .. groupNum;
        if components.CollapsingSection(sectionLabel, false) then
            DrawGroupSettings(groupNum);
        end
    end

    if components.CollapsingSection('Notification Types##notifications') then
        local indentAmount = 20;
        local maxGroups = gConfig.notificationGroupCount or 2;

        -- Build group dropdown options
        local groupOptions = {};
        for i = 1, maxGroups do
            table.insert(groupOptions, 'Group ' .. i);
        end

        -- Helper to draw group dropdown for a notification type
        local function DrawTypeGroupDropdown(typeKey, label)
            local currentGroup = gConfig.notificationTypeGroup[typeKey] or 1;
            imgui.SetNextItemWidth(100);
            if imgui.BeginCombo('Group##' .. typeKey, 'Group ' .. currentGroup) then
                for i = 1, maxGroups do
                    if imgui.Selectable('Group ' .. i, i == currentGroup) then
                        gConfig.notificationTypeGroup[typeKey] = i;
                        SaveSettingsOnly();
                    end
                end
                imgui.EndCombo();
            end
            imgui.ShowHelp('Which group this notification type appears in');
        end

        -- Party Invites
        DrawCheckboxWithTest('Party Invites', 'notificationsShowPartyInvite', notificationData.NOTIFICATION_TYPE.PARTY_INVITE);
        if gConfig.notificationsShowPartyInvite then
            imgui.Indent(indentAmount);
            DrawTypeGroupDropdown('partyInvite', 'Party Invites');
            imgui.Unindent(indentAmount);
        end

        imgui.Spacing();

        -- Trade Requests
        DrawCheckboxWithTest('Trade Requests', 'notificationsShowTradeInvite', notificationData.NOTIFICATION_TYPE.TRADE_INVITE);
        if gConfig.notificationsShowTradeInvite then
            imgui.Indent(indentAmount);
            DrawTypeGroupDropdown('tradeInvite', 'Trade Requests');
            imgui.Unindent(indentAmount);
        end

        imgui.Spacing();

        -- Items Obtained
        DrawCheckboxWithTest('Items Obtained', 'notificationsShowItems', notificationData.NOTIFICATION_TYPE.ITEM_OBTAINED);
        if gConfig.notificationsShowItems then
            imgui.Indent(indentAmount);
            DrawTypeGroupDropdown('itemObtained', 'Items Obtained');
            imgui.Unindent(indentAmount);
        end

        imgui.Spacing();

        -- Key Items
        DrawCheckboxWithTest('Key Items', 'notificationsShowKeyItems', notificationData.NOTIFICATION_TYPE.KEY_ITEM_OBTAINED);
        if gConfig.notificationsShowKeyItems then
            imgui.Indent(indentAmount);
            DrawTypeGroupDropdown('keyItemObtained', 'Key Items');
            imgui.Unindent(indentAmount);
        end

        imgui.Spacing();

        -- Gil
        DrawCheckboxWithTest('Gil', 'notificationsShowGil', notificationData.NOTIFICATION_TYPE.GIL_OBTAINED);
        if gConfig.notificationsShowGil then
            imgui.Indent(indentAmount);
            DrawTypeGroupDropdown('gilObtained', 'Gil');
            imgui.Unindent(indentAmount);
        end

        imgui.Spacing();

        -- Treasure Pool (moved to bottom)
        DrawCheckboxWithTest('Treasure Pool', 'notificationsShowTreasure', notificationData.NOTIFICATION_TYPE.TREASURE_POOL);
        if gConfig.notificationsShowTreasure then
            imgui.Indent(indentAmount);
            DrawTypeGroupDropdown('treasurePool', 'Treasure Pool');
            imgui.Unindent(indentAmount);
        end
    end
end

-- Section: Notifications Color Settings
function M.DrawColorSettings()
    if components.CollapsingSection('Notification Colors') then
        -- Ensure colorCustomization and notifications exist
        if not gConfig.colorCustomization then
            gConfig.colorCustomization = {};
        end
        if not gConfig.colorCustomization.notifications then
            gConfig.colorCustomization.notifications = deep_copy_table(defaultUserSettings.colorCustomization.notifications);
        end
        local colors = gConfig.colorCustomization.notifications;
        components.DrawTextColorPicker('Background', colors, 'bgColor', 'Notification card background');
        components.DrawTextColorPicker('Border', colors, 'borderColor', 'Notification card border');
        imgui.Separator();
        components.DrawTextColorPicker('Party Invite', colors, 'partyInviteColor', 'Party invite accent color');
        components.DrawTextColorPicker('Trade Request', colors, 'tradeInviteColor', 'Trade request accent color');
        components.DrawTextColorPicker('Treasure Pool', colors, 'treasurePoolColor', 'Treasure pool accent color');
        components.DrawTextColorPicker('Item Obtained', colors, 'itemObtainedColor', 'Item obtained accent color');
        components.DrawTextColorPicker('Key Item', colors, 'keyItemColor', 'Key item accent color');
        components.DrawTextColorPicker('Gil', colors, 'gilColor', 'Gil accent color');
        imgui.Separator();
        components.DrawTextColorPicker('Text', colors, 'textColor', 'Main text color');
        components.DrawTextColorPicker('Subtitle', colors, 'subtitleColor', 'Subtitle/secondary text color');
    end
end

return M;
