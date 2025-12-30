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

-- Section: Notifications Settings
function M.DrawSettings()
    components.DrawCheckbox('Enabled', 'showNotifications', CheckVisibility);
    components.DrawCheckbox('Hide During Events', 'notificationsHideDuringEvents');

    if components.CollapsingSection('Display Options##notifications') then
        -- Stack Direction dropdown
        local stackDirections = {'Down', 'Up'};
        local stackDirectionValues = {'down', 'up'};
        local currentDirIndex = gConfig.notificationsDirection == 'up' and 2 or 1;
        if imgui.BeginCombo('Stack Direction', stackDirections[currentDirIndex]) then
            for i, label in ipairs(stackDirections) do
                if imgui.Selectable(label, i == currentDirIndex) then
                    gConfig.notificationsDirection = stackDirectionValues[i];
                    -- Clear window anchors when direction changes
                    notificationData.ClearWindowAnchors();
                    SaveSettingsOnly();
                end
            end
            imgui.EndCombo();
        end
        imgui.ShowHelp('Direction notifications stack. Up: window anchors at bottom, grows upward. Down: window anchors at top, grows downward.');

        -- Progress Bar Direction dropdown
        local progressBarDirections = {'Left', 'Right'};
        local progressBarDirectionValues = {'left', 'right'};
        local currentBarDirIndex = gConfig.notificationsProgressBarDirection == 'right' and 2 or 1;
        if imgui.BeginCombo('Progress Bar Direction', progressBarDirections[currentBarDirIndex]) then
            for i, label in ipairs(progressBarDirections) do
                if imgui.Selectable(label, i == currentBarDirIndex) then
                    gConfig.notificationsProgressBarDirection = progressBarDirectionValues[i];
                    SaveSettingsOnly();
                end
            end
            imgui.EndCombo();
        end
        imgui.ShowHelp('Direction the progress bar drains as time elapses.');

        components.DrawSlider('Max Visible', 'notificationsMaxVisible', 1, 10, '%.0f');
        imgui.ShowHelp('Maximum notifications shown at once');
        components.DrawSlider('Display Duration', 'notificationsDisplayDuration', 1.0, 10.0, '%.1f sec');
        components.DrawSlider('Minimize Time', 'notificationsInviteMinifyTimeout', 3.0, 30.0, '%.0f sec');
        imgui.ShowHelp('Party and trade invites minimize after this time but stay pinned');
    end

    if components.CollapsingSection('Scale & Position##notifications') then
        components.DrawSlider('Scale X', 'notificationsScaleX', 0.5, 2.0, '%.1f');
        components.DrawSlider('Scale Y', 'notificationsScaleY', 0.5, 2.0, '%.1f');
        components.DrawSlider('Progress Bar Scale Y', 'notificationsProgressBarScaleY', 0.5, 3.0, '%.1f');
        imgui.ShowHelp('Height scale for the countdown progress bar');
        components.DrawSlider('Padding', 'notificationsPadding', 2, 16, '%.0f px');
        components.DrawSlider('Spacing', 'notificationsSpacing', 0, 24, '%.0f px');
        imgui.ShowHelp('Space between notifications in the list');
    end

    if components.CollapsingSection('Text Settings##notifications') then
        components.DrawSlider('Title Text Size', 'notificationsTitleFontSize', 8, 24, '%.0f');
        components.DrawSlider('Subtitle Text Size', 'notificationsSubtitleFontSize', 8, 24, '%.0f');
    end

    if components.CollapsingSection('Background##notifications') then
        local bgThemes = {'-None-', 'Plain', 'Window1', 'Window2', 'Window3', 'Window4', 'Window5', 'Window6', 'Window7', 'Window8'};
        local currentTheme = gConfig.notificationsBackgroundTheme or 'Plain';
        imgui.SetNextItemWidth(150);
        if imgui.BeginCombo('Theme##notifBg', currentTheme) then
            for _, theme in ipairs(bgThemes) do
                if imgui.Selectable(theme, theme == currentTheme) then
                    gConfig.notificationsBackgroundTheme = theme;
                    DeferredUpdateVisuals();
                end
            end
            imgui.EndCombo();
        end
        imgui.ShowHelp('Select the background window theme for notifications.');

        components.DrawSlider('Background Scale', 'notificationsBgScale', 0.1, 3.0, '%.2f', DeferredUpdateVisuals);
        imgui.ShowHelp('Scale of the background texture.');
        components.DrawSlider('Border Scale', 'notificationsBorderScale', 0.1, 3.0, '%.2f', DeferredUpdateVisuals);
        imgui.ShowHelp('Scale of the window borders (Window themes only).');
        components.DrawSlider('Background Opacity', 'notificationsBgOpacity', 0.0, 1.0, '%.2f');
        imgui.ShowHelp('Opacity of the background.');
        components.DrawSlider('Border Opacity', 'notificationsBorderOpacity', 0.0, 1.0, '%.2f');
        imgui.ShowHelp('Opacity of the window borders (Window themes only).');
    end

    if components.CollapsingSection('Notification Types##notifications') then
        local indentAmount = 20;

        -- Party Invites
        DrawCheckboxWithTest('Party Invites', 'notificationsShowPartyInvite', notificationData.NOTIFICATION_TYPE.PARTY_INVITE);
        if gConfig.notificationsShowPartyInvite then
            imgui.Indent(indentAmount);
            components.DrawCheckbox('Split Window##PartyInvite', 'notificationsSplitPartyInvite');
            imgui.ShowHelp('Display party invites in a separate draggable window');
            imgui.Unindent(indentAmount);
        end

        imgui.Spacing();

        -- Trade Requests
        DrawCheckboxWithTest('Trade Requests', 'notificationsShowTradeInvite', notificationData.NOTIFICATION_TYPE.TRADE_INVITE);
        if gConfig.notificationsShowTradeInvite then
            imgui.Indent(indentAmount);
            components.DrawCheckbox('Split Window##TradeInvite', 'notificationsSplitTradeInvite');
            imgui.ShowHelp('Display trade requests in a separate draggable window');
            imgui.Unindent(indentAmount);
        end

        imgui.Spacing();

        -- Items Obtained
        DrawCheckboxWithTest('Items Obtained', 'notificationsShowItems', notificationData.NOTIFICATION_TYPE.ITEM_OBTAINED);
        if gConfig.notificationsShowItems then
            imgui.Indent(indentAmount);
            components.DrawCheckbox('Split Window##ItemObtained', 'notificationsSplitItemObtained');
            imgui.ShowHelp('Display item notifications in a separate draggable window');
            imgui.Unindent(indentAmount);
        end

        imgui.Spacing();

        -- Key Items
        DrawCheckboxWithTest('Key Items', 'notificationsShowKeyItems', notificationData.NOTIFICATION_TYPE.KEY_ITEM_OBTAINED);
        if gConfig.notificationsShowKeyItems then
            imgui.Indent(indentAmount);
            components.DrawCheckbox('Split Window##KeyItemObtained', 'notificationsSplitKeyItemObtained');
            imgui.ShowHelp('Display key item notifications in a separate draggable window');
            imgui.Unindent(indentAmount);
        end

        imgui.Spacing();

        -- Gil
        DrawCheckboxWithTest('Gil', 'notificationsShowGil', notificationData.NOTIFICATION_TYPE.GIL_OBTAINED);
        if gConfig.notificationsShowGil then
            imgui.Indent(indentAmount);
            components.DrawCheckbox('Split Window##GilObtained', 'notificationsSplitGilObtained');
            imgui.ShowHelp('Display gil notifications in a separate draggable window');
            imgui.Unindent(indentAmount);
        end

        imgui.Spacing();

        -- Treasure Pool (moved to bottom)
        DrawCheckboxWithTest('Treasure Pool', 'notificationsShowTreasure', notificationData.NOTIFICATION_TYPE.TREASURE_POOL);
        if gConfig.notificationsShowTreasure then
            imgui.Indent(indentAmount);
            components.DrawCheckbox('Split Window##TreasurePool', 'notificationsSplitTreasurePool');
            imgui.ShowHelp('Display treasure pool toasts in a separate draggable window');
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
