require ("common");
require('helpers');
local statusHandler = require('statushandler');
local imgui = require("imgui");

local config = {};

-- State for confirmation dialogs
local showRestoreDefaultsConfirm = false;

-- List of common Windows fonts
local available_fonts = {
    'Arial',
    'Calibri',
    'Consolas',
    'Courier New',
    'Georgia',
    'Lucida Console',
    'Microsoft Sans Serif',
    'Tahoma',
    'Times New Roman',
    'Trebuchet MS',
    'Verdana',
};

-- Helper function for checkbox with auto-save
local function DrawCheckbox(label, configKey, callback)
    if (imgui.Checkbox(label, { gConfig[configKey] })) then
        gConfig[configKey] = not gConfig[configKey];
        SaveSettingsOnly();
        if callback then callback() end
    end
end

-- Helper function for slider with deferred save
local function DrawSlider(label, configKey, min, max, format, callback)
    local value = { gConfig[configKey] };
    local changed = false;

    -- Use SliderFloat if format is specified, otherwise check if value is integer
    if format ~= nil then
        -- Format specified, use float slider
        changed = imgui.SliderFloat(label, value, min, max, format);
    elseif type(gConfig[configKey]) == 'number' and math.floor(gConfig[configKey]) == gConfig[configKey] then
        -- No format and value is integer, use int slider
        changed = imgui.SliderInt(label, value, min, max);
    else
        -- No format but value is float, use float slider with default format
        changed = imgui.SliderFloat(label, value, min, max, '%.2f');
    end

    if changed then
        gConfig[configKey] = value[1];
        if callback then callback() end
        UpdateUserSettings();
    end

    if (imgui.IsItemDeactivatedAfterEdit()) then
        SaveSettingsToDisk();
    end
end

-- Helper function for party layout-specific checkbox (saves to current layout table)
local function DrawPartyLayoutCheckbox(label, configKey, callback)
    local currentLayout = (gConfig.partyListLayout == 1) and gConfig.partyListLayout2 or gConfig.partyListLayout1;
    if (imgui.Checkbox(label, { currentLayout[configKey] })) then
        currentLayout[configKey] = not currentLayout[configKey];
        SaveSettingsOnly();
        if callback then callback() end
    end
end

-- Helper function for party layout-specific slider (saves to current layout table)
local function DrawPartyLayoutSlider(label, configKey, min, max, format, callback)
    local currentLayout = (gConfig.partyListLayout == 1) and gConfig.partyListLayout2 or gConfig.partyListLayout1;
    local value = { currentLayout[configKey] };
    local changed = false;

    -- Use SliderFloat if format is specified, otherwise check if value is integer
    if format ~= nil then
        -- Format specified, use float slider
        changed = imgui.SliderFloat(label, value, min, max, format);
    elseif type(currentLayout[configKey]) == 'number' and math.floor(currentLayout[configKey]) == currentLayout[configKey] then
        -- No format and value is integer, use int slider
        changed = imgui.SliderInt(label, value, min, max);
    else
        -- No format but value is float, use float slider with default format
        changed = imgui.SliderFloat(label, value, min, max, '%.2f');
    end

    if changed then
        currentLayout[configKey] = value[1];
        if callback then callback() end
        UpdateUserSettings();
    end

    if (imgui.IsItemDeactivatedAfterEdit()) then
        SaveSettingsToDisk();
    end
end

-- Helper function for combo box selection
local function DrawComboBox(label, currentValue, items, callback)
    local changed = false;
    local newValue = currentValue;

    if (imgui.BeginCombo(label, currentValue)) then
        for i = 1, #items do
            local is_selected = items[i] == currentValue;

            if (imgui.Selectable(items[i], is_selected) and items[i] ~= currentValue) then
                newValue = items[i];
                changed = true;
            end

            if (is_selected) then
                imgui.SetItemDefaultFocus();
            end
        end
        imgui.EndCombo();
    end

    if changed and callback then
        callback(newValue);
    end

    return changed, newValue;
end

-- Section: General Settings
local function DrawGeneralSettings()
    if (imgui.CollapsingHeader("General")) then
        imgui.BeginChild("GeneralSettings", { 0, 180 }, true);

        DrawCheckbox('Lock HUD Position', 'lockPositions');

        -- Status Icon Theme
        local status_theme_paths = statusHandler.get_status_theme_paths();
        DrawComboBox('Status Icon Theme', gConfig.statusIconTheme, status_theme_paths, function(newValue)
            gConfig.statusIconTheme = newValue;
            SaveSettingsOnly();
            DeferredUpdateVisuals();
        end);
        imgui.ShowHelp('The folder to pull status icons from. [HXUI\\assets\\status]');

        -- Job Icon Theme
        local job_theme_paths = statusHandler.get_job_theme_paths();
        DrawComboBox('Job Icon Theme', gConfig.jobIconTheme, job_theme_paths, function(newValue)
            gConfig.jobIconTheme = newValue;
            SaveSettingsOnly();
            DeferredUpdateVisuals();
        end);
        imgui.ShowHelp('The folder to pull job icons from. [HXUI\\assets\\jobs]');

        DrawSlider('Tooltip Scale', 'tooltipScale', 0.1, 3.0, '%.2f');
        imgui.ShowHelp('Scales the size of the tooltip. Note that text may appear blured if scaled too large.');

        DrawCheckbox('Hide During Events', 'hideDuringEvents');

        imgui.EndChild();
    end
end

-- Section: Font Settings
local function DrawFontSettings()
    if (imgui.CollapsingHeader("Fonts")) then
        imgui.BeginChild("FontSettings", { 0, 180 }, true);

        -- Font Family Selector
        DrawComboBox('Font Family', gConfig.fontFamily, available_fonts, function(newValue)
            gConfig.fontFamily = newValue;
            ClearDebuffFontCache();
            UpdateSettings();
        end);
        imgui.ShowHelp('The font family to use for all text in HXUI. Fonts must be installed on your system.');

        -- Font Weight Selector
        DrawComboBox('Font Weight', gConfig.fontWeight, {'Normal', 'Bold'}, function(newValue)
            gConfig.fontWeight = newValue;
            ClearDebuffFontCache();
            UpdateSettings();
        end);
        imgui.ShowHelp('The font weight (boldness) to use for all text in HXUI.');

        -- Font Outline Width Slider
        DrawSlider('Font Outline Width', 'fontOutlineWidth', 0, 5, nil, function()
            ClearDebuffFontCache();
            DeferredUpdateVisuals(); -- Tell all modules to recreate fonts with new outline width
        end);
        imgui.ShowHelp('The thickness of the text outline/stroke for all text in HXUI.');

        imgui.EndChild();
    end
end

-- Section: Bar Settings
local function DrawBarSettings()
    if (imgui.CollapsingHeader("Bar Settings")) then
        imgui.BeginChild("BarSettings", { 0, 200 }, true);

        DrawCheckbox('Show Bookends', 'showBookends');
        imgui.ShowHelp('Global setting to show or hide bookends on all progress bars.');

        DrawCheckbox('Health Bar Flash Effects', 'healthBarFlashEnabled');
        imgui.ShowHelp('Flash effect when taking damage on health bars.');

        DrawCheckbox('TP Bar Flash Effects', 'tpBarFlashEnabled');
        imgui.ShowHelp('Flash effect when TP reaches 100% or higher.');

        DrawSlider('Bar Roundness', 'noBookendRounding', 0, 10);
        imgui.ShowHelp('Corner roundness for bars without bookends (0 = square corners, 10 = very rounded).');

        DrawSlider('Bar Border Thickness', 'barBorderThickness', 0, 5);
        imgui.ShowHelp('Thickness of the border around all progress bars.');

        imgui.EndChild();
    end
end

-- Section: Player Bar Settings
local function DrawPlayerBarSettings()
    if (imgui.CollapsingHeader("Player Bar")) then
        imgui.BeginChild("PlayerBarSettings", { 0, 210 }, true);

        DrawCheckbox('Enabled', 'showPlayerBar', CheckVisibility);
        DrawCheckbox('Show Bookends', 'showPlayerBarBookends');
        DrawCheckbox('Hide During Events', 'playerBarHideDuringEvents');
        DrawCheckbox('Always Show MP Bar', 'alwaysShowMpBar');
        imgui.ShowHelp('Always display the MP Bar even if your current jobs cannot cast spells.');

        DrawSlider('Scale X', 'playerBarScaleX', 0.1, 3.0, '%.1f');
        DrawSlider('Scale Y', 'playerBarScaleY', 0.1, 3.0, '%.1f');
        DrawSlider('Font Size', 'playerBarFontSize', 8, 36);

        imgui.EndChild();
    end
end

-- Section: Target Bar Settings
local function DrawTargetBarSettings()
    if (imgui.CollapsingHeader("Target Bar")) then
        imgui.BeginChild("TargetBarSettings", { 0, 420 }, true);

        DrawCheckbox('Enabled', 'showTargetBar', CheckVisibility);
        DrawCheckbox('Show Distance', 'showTargetDistance');
        DrawCheckbox('Show Bookends', 'showTargetBarBookends');
        DrawCheckbox('Show Lock On', 'showTargetBarLockOnBorder');
        imgui.ShowHelp('Display the lock icon and colored border when locked on to a target.');
        DrawCheckbox('Show Cast Bar', 'showTargetBarCastBar');
        imgui.ShowHelp('Display the enemy cast bar under the HP bar when the target is casting.');
        DrawCheckbox('Hide During Events', 'targetBarHideDuringEvents');
        DrawCheckbox('Show Enemy Id', 'showEnemyId');
        imgui.ShowHelp('Display the internal ID of the monster next to its name.');

        DrawCheckbox('Always Show Health Percent', 'alwaysShowHealthPercent');
        imgui.ShowHelp('Always display the percent of HP remanining regardless if the target is an enemy or not.');

        DrawCheckbox('Split Target Bars', 'splitTargetOfTarget');
        imgui.ShowHelp('Separate the Target of Target bar into its own window that can be moved independently.');

        DrawSlider('Scale X', 'targetBarScaleX', 0.1, 3.0, '%.1f');
        DrawSlider('Scale Y', 'targetBarScaleY', 0.1, 3.0, '%.1f');
        DrawSlider('Name Font Size', 'targetBarNameFontSize', 8, 36);
        DrawSlider('Distance Font Size', 'targetBarDistanceFontSize', 8, 36);
        DrawSlider('HP% Font Size', 'targetBarPercentFontSize', 8, 36);

        -- Cast bar settings (only show if cast bar is enabled)
        if (gConfig.showTargetBarCastBar) then
            DrawSlider('Cast Font Size', 'targetBarCastFontSize', 8, 36);
            imgui.ShowHelp('Font size for enemy cast text that appears under the HP bar.');

            imgui.Text('Cast Bar Position & Scale:');
            DrawSlider('Cast Bar Offset Y', 'targetBarCastBarOffsetY', 0, 50, '%.0f');
            imgui.ShowHelp('Vertical distance below the HP bar (in pixels).');
            DrawSlider('Cast Bar Scale X', 'targetBarCastBarScaleX', 0.1, 3.0, '%.1f');
            imgui.ShowHelp('Horizontal scale multiplier for cast bar width.');
            DrawSlider('Cast Bar Scale Y', 'targetBarCastBarScaleY', 0.1, 3.0, '%.1f');
            imgui.ShowHelp('Vertical scale multiplier for cast bar height.');
        end

        imgui.Text('Buffs/Debuffs Position:');
        DrawSlider('Buffs Offset Y', 'targetBarBuffsOffsetY', -20, 50, '%.0f');
        imgui.ShowHelp('Vertical offset for buffs/debuffs below the HP bar (in pixels).');

        DrawSlider('Icon Scale', 'targetBarIconScale', 0.1, 3.0, '%.1f');
        DrawSlider('Icon Font Size', 'targetBarIconFontSize', 8, 36);

        imgui.EndChild();

        -- Target of Target Bar settings (only show when split is enabled)
        if (gConfig.splitTargetOfTarget) then
            imgui.BeginChild("TargetOfTargetSettings", { 0, 150 }, true);
            imgui.Text('Target of Target Bar');

            DrawSlider('Scale X', 'totBarScaleX', 0.1, 3.0, '%.1f');
            DrawSlider('Scale Y', 'totBarScaleY', 0.1, 3.0, '%.1f');
            DrawSlider('Font Size', 'totBarFontSize', 8, 36);

            imgui.EndChild();
        end
    end
end

-- Section: Enemy List Settings
local function DrawEnemyListSettings()
    if (imgui.CollapsingHeader("Enemy List")) then
        imgui.BeginChild("EnemyListSettings", { 0, 250 }, true);

        DrawCheckbox('Enabled', 'showEnemyList', CheckVisibility);
        DrawCheckbox('Show Distance', 'showEnemyDistance');
        DrawCheckbox('Show HP% Text', 'showEnemyHPPText');
        DrawCheckbox('Show Enemy Targets', 'showEnemyListTargets');
        imgui.ShowHelp('Shows who each enemy is targeting based on their last action.');
        DrawCheckbox('Show Bookends', 'showEnemyListBookends');

        DrawSlider('Scale X', 'enemyListScaleX', 0.1, 3.0, '%.1f');
        DrawSlider('Scale Y', 'enemyListScaleY', 0.1, 3.0, '%.1f');
        DrawSlider('Name Font Size', 'enemyListNameFontSize', 8, 36);
        DrawSlider('Distance Font Size', 'enemyListDistanceFontSize', 8, 36);
        DrawSlider('HP% Font Size', 'enemyListPercentFontSize', 8, 36);
        DrawSlider('Icon Scale', 'enemyListIconScale', 0.1, 3.0, '%.1f');

        imgui.EndChild();
    end
end

-- Section: Party List Settings
local function DrawPartyListSettings()
    if (imgui.CollapsingHeader("Party List")) then
        imgui.BeginChild("PartyListSettings", { 0, 460 }, true);

        DrawCheckbox('Enabled', 'showPartyList', CheckVisibility);

        -- Layout Selector
        local layoutItems = { [0] = 'Layout 1 (Horizontal)', [1] = 'Layout 2 (Compact Vertical)' };
        if imgui.BeginCombo('Layout', layoutItems[gConfig.partyListLayout]) then
            for i = 0, 1 do
                local is_selected = i == gConfig.partyListLayout;
                if imgui.Selectable(layoutItems[i], is_selected) then
                    if gConfig.partyListLayout ~= i then
                        gConfig.partyListLayout = i;
                        UpdateSettings();  -- Reload settings from new layout
                        SaveSettingsOnly();
                        if partyList ~= nil then
                            partyList.UpdateVisuals(gAdjustedSettings.partyListSettings);  -- Recreate fonts
                        end
                    end
                end
                if is_selected then
                    imgui.SetItemDefaultFocus();
                end
            end
            imgui.EndCombo();
        end
        imgui.ShowHelp('Select between horizontal (Layout 1) and compact vertical (Layout 2) party list layouts. Each layout has independent settings.');

        DrawCheckbox('Preview Full Party (when config open)', 'partyListPreview');
        DrawCheckbox('Flash TP at 100%', 'partyListFlashTP');
        DrawCheckbox('Show Distance', 'showPartyListDistance');
        DrawCheckbox('Show Job Icons', 'showPartyJobIcon');
        DrawCheckbox('Show Job/Subjob', 'showPartyListJob');
        imgui.ShowHelp('Display job and subjob info on the right side of the name row (Layout 1 only).');

        DrawSlider('Distance Highlighting', 'partyListDistanceHighlight', 0.0, 50.0, '%.1f');

        DrawCheckbox('Show Bookends', 'showPartyListBookends');
        DrawCheckbox('Show When Solo', 'showPartyListWhenSolo');
        DrawCheckbox('Show Title', 'showPartyListTitle');
        DrawCheckbox('Hide During Events', 'partyListHideDuringEvents');
        DrawCheckbox('Align Bottom', 'partyListAlignBottom');
        DrawCheckbox('Expand Height', 'partyListExpandHeight');
        DrawCheckbox('Alliance Windows', 'partyListAlliance');

        -- Background
        DrawSlider('Background Scale', 'partyListBgScale', 0.1, 3.0, '%.2f', UpdatePartyListVisuals);

        local bg_theme_paths = statusHandler.get_background_paths();
        DrawComboBox('Background', gConfig.partyListBackgroundName, bg_theme_paths, function(newValue)
            gConfig.partyListBackgroundName = newValue;
            SaveSettingsOnly();
            DeferredUpdateVisuals();
        end);
        imgui.ShowHelp('The image to use for the party list background. [Resolution: 512x512 @ HXUI\\assets\\backgrounds]');

        -- Cursor
        local cursor_paths = statusHandler.get_cursor_paths();
        DrawComboBox('Cursor', gConfig.partyListCursor, cursor_paths, function(newValue)
            gConfig.partyListCursor = newValue;
            SaveSettingsOnly();
            DeferredUpdateVisuals();
        end);
        imgui.ShowHelp('The image to use for the party list cursor. [@ HXUI\\assets\\cursors]');

        -- Status Theme
        local comboBoxItems = { [0] = 'HorizonXI', [1] = 'HorizonXI-R', [2] = 'FFXIV', [3] = 'FFXI', [4] = 'Disabled' };
        gConfig.partyListStatusTheme = math.clamp(gConfig.partyListStatusTheme, 0, 4);
        if(imgui.BeginCombo('Status Theme', comboBoxItems[gConfig.partyListStatusTheme])) then
            for i = 0, #comboBoxItems do
                local is_selected = i == gConfig.partyListStatusTheme;

                if (imgui.Selectable(comboBoxItems[i], is_selected) and gConfig.partyListStatusTheme ~= i) then
                    gConfig.partyListStatusTheme = i;
                    SaveSettingsOnly();
                end
                if(is_selected) then
                    imgui.SetItemDefaultFocus();
                end
            end
            imgui.EndCombo();
        end

        DrawSlider('Status Icon Scale', 'partyListBuffScale', 0.1, 3.0, '%.1f');
        DrawCheckbox('Show Cast Bars', 'partyListCastBars');
        if (gConfig.partyListCastBars) then
            DrawSlider('Cast Bar Scale Y', 'partyListCastBarScaleY', 0.1, 3.0, '%.1f');
        end

        imgui.EndChild();

        -- Main Party Settings
        if true then
            imgui.BeginChild('PartyListSettings.Party1', { 0, 230 }, true);
            imgui.Text('Party');

            DrawPartyLayoutCheckbox('Show TP', 'partyListTP');
            DrawPartyLayoutSlider('Min Rows', 'partyListMinRows', 1, 6);

            -- Layout 1: General Scale X and Y
            if gConfig.partyListLayout == 0 then
                DrawPartyLayoutSlider('Scale X', 'partyListScaleX', 0.1, 3.0, '%.2f');
                DrawPartyLayoutSlider('Scale Y', 'partyListScaleY', 0.1, 3.0, '%.2f');
            end

            -- Layout 2: Individual HP and MP bar X and Y scales
            if gConfig.partyListLayout == 1 then
                DrawPartyLayoutSlider('HP Bar Scale X', 'hpBarScaleX', 0.1, 3.0, '%.2f');
                DrawPartyLayoutSlider('MP Bar Scale X', 'mpBarScaleX', 0.1, 3.0, '%.2f');
                DrawPartyLayoutSlider('HP Bar Scale Y', 'hpBarScaleY', 0.1, 3.0, '%.2f');
                DrawPartyLayoutSlider('MP Bar Scale Y', 'mpBarScaleY', 0.1, 3.0, '%.2f');
            end

            -- Font Size: Layout 2 has separate controls, Layout 1 has single control
            if gConfig.partyListLayout == 1 then
                DrawPartyLayoutSlider('Name Font Size', 'partyListNameFontSize', 8, 36);
                DrawPartyLayoutSlider('HP Font Size', 'partyListHpFontSize', 8, 36);
                DrawPartyLayoutSlider('MP Font Size', 'partyListMpFontSize', 8, 36);
                DrawPartyLayoutSlider('TP Font Size', 'partyListTpFontSize', 8, 36);
            else
                DrawPartyLayoutSlider('Font Size', 'partyListFontSize', 8, 36);
            end
            if gConfig.showPartyJobIcon then
                DrawPartyLayoutSlider('Job Icon Scale', 'partyListJobIconScale', 0.1, 3.0, '%.1f');
            end
            DrawPartyLayoutSlider('Entry Spacing', 'partyListEntrySpacing', -4, 16);
            DrawPartyLayoutSlider('Selection Box Scale Y', 'selectionBoxScaleY', 0.5, 2.0, '%.2f');

            imgui.EndChild();
        end

        -- Party B (Alliance)
        if (gConfig.partyListAlliance) then
            imgui.BeginChild('PartyListSettings.Party2', { 0, 205 }, true);
            imgui.Text('Party B (Alliance)');

            DrawPartyLayoutCheckbox('Show TP', 'partyList2TP');
            DrawPartyLayoutSlider('Scale X', 'partyList2ScaleX', 0.1, 3.0, '%.2f');
            DrawPartyLayoutSlider('Scale Y', 'partyList2ScaleY', 0.1, 3.0, '%.2f');

            -- Layout 2: Individual HP and MP bar X and Y scales
            if gConfig.partyListLayout == 1 then
                DrawPartyLayoutSlider('HP Bar Scale X', 'partyList2HpBarScaleX', 0.1, 3.0, '%.2f');
                DrawPartyLayoutSlider('MP Bar Scale X', 'partyList2MpBarScaleX', 0.1, 3.0, '%.2f');
                DrawPartyLayoutSlider('HP Bar Scale Y', 'partyList2HpBarScaleY', 0.1, 3.0, '%.2f');
                DrawPartyLayoutSlider('MP Bar Scale Y', 'partyList2MpBarScaleY', 0.1, 3.0, '%.2f');
            end

            -- Font Size: Layout 2 has separate controls, Layout 1 has single control
            if gConfig.partyListLayout == 1 then
                DrawPartyLayoutSlider('Name Font Size', 'partyList2NameFontSize', 8, 36);
                DrawPartyLayoutSlider('HP Font Size', 'partyList2HpFontSize', 8, 36);
                DrawPartyLayoutSlider('MP Font Size', 'partyList2MpFontSize', 8, 36);
            else
                DrawPartyLayoutSlider('Font Size', 'partyList2FontSize', 8, 36);
            end

            if gConfig.showPartyJobIcon then
                DrawPartyLayoutSlider('Job Icon Scale', 'partyList2JobIconScale', 0.1, 3.0, '%.1f');
            end
            DrawPartyLayoutSlider('Entry Spacing', 'partyList2EntrySpacing', -4, 16);

            imgui.EndChild();
        end

        -- Party C (Alliance)
        if (gConfig.partyListAlliance) then
            imgui.BeginChild('PartyListSettings.Party3', { 0, 205 }, true);
            imgui.Text('Party C (Alliance)');

            DrawPartyLayoutCheckbox('Show TP', 'partyList3TP');
            DrawPartyLayoutSlider('Scale X', 'partyList3ScaleX', 0.1, 3.0, '%.2f');
            DrawPartyLayoutSlider('Scale Y', 'partyList3ScaleY', 0.1, 3.0, '%.2f');

            -- Layout 2: Individual HP and MP bar X and Y scales
            if gConfig.partyListLayout == 1 then
                DrawPartyLayoutSlider('HP Bar Scale X', 'partyList3HpBarScaleX', 0.1, 3.0, '%.2f');
                DrawPartyLayoutSlider('MP Bar Scale X', 'partyList3MpBarScaleX', 0.1, 3.0, '%.2f');
                DrawPartyLayoutSlider('HP Bar Scale Y', 'partyList3HpBarScaleY', 0.1, 3.0, '%.2f');
                DrawPartyLayoutSlider('MP Bar Scale Y', 'partyList3MpBarScaleY', 0.1, 3.0, '%.2f');
            end

            -- Font Size: Layout 2 has separate controls, Layout 1 has single control
            if gConfig.partyListLayout == 1 then
                DrawPartyLayoutSlider('Name Font Size', 'partyList3NameFontSize', 8, 36);
                DrawPartyLayoutSlider('HP Font Size', 'partyList3HpFontSize', 8, 36);
                DrawPartyLayoutSlider('MP Font Size', 'partyList3MpFontSize', 8, 36);
            else
                DrawPartyLayoutSlider('Font Size', 'partyList3FontSize', 8, 36);
            end

            if gConfig.showPartyJobIcon then
                DrawPartyLayoutSlider('Job Icon Scale', 'partyList3JobIconScale', 0.1, 3.0, '%.1f');
            end
            DrawPartyLayoutSlider('Entry Spacing', 'partyList3EntrySpacing', -4, 16);

            imgui.EndChild();
        end
    end
end

-- Section: Exp Bar Settings
local function DrawExpBarSettings()
    if (imgui.CollapsingHeader("Exp Bar")) then
        imgui.BeginChild("ExpBarSettings", { 0, 300 }, true);

        DrawCheckbox('Enabled', 'showExpBar', CheckVisibility);
        DrawCheckbox('Limit Points Mode', 'expBarLimitPointsMode');
        imgui.ShowHelp('Shows Limit Points if character is set to earn Limit Points in the game.');

        DrawCheckbox('Inline Mode', 'expBarInlineMode');
        DrawCheckbox('Show Bookends', 'showExpBarBookends');
        DrawCheckbox('Show Text', 'expBarShowText');
        DrawCheckbox('Show Percent', 'expBarShowPercent');

        DrawSlider('Scale X', 'expBarScaleX', 0.1, 3.0, '%.2f');
        DrawSlider('Scale Y', 'expBarScaleY', 0.1, 3.0, '%.2f');
        DrawSlider('Font Size', 'expBarFontSize', 8, 36);

        imgui.EndChild();
    end
end

-- Section: Gil Tracker Settings
local function DrawGilTrackerSettings()
    if (imgui.CollapsingHeader("Gil Tracker")) then
        imgui.BeginChild("GilTrackerSettings", { 0, 120 }, true);

        DrawCheckbox('Enabled', 'showGilTracker', CheckVisibility);
        DrawSlider('Scale', 'gilTrackerScale', 0.1, 3.0, '%.1f');
        DrawSlider('Font Size', 'gilTrackerFontSize', 8, 36);
        DrawCheckbox('Right Align', 'gilTrackerRightAlign', UpdateGilTrackerVisuals);

        imgui.EndChild();
    end
end

-- Section: Inventory Tracker Settings
local function DrawInventoryTrackerSettings()
    if (imgui.CollapsingHeader("Inventory Tracker")) then
        imgui.BeginChild("InventoryTrackerSettings", { 0, 210 }, true);

        DrawCheckbox('Enabled', 'showInventoryTracker', CheckVisibility);
        DrawCheckbox('Show Count', 'inventoryShowCount');

        local columnCount = { gConfig.inventoryTrackerColumnCount };
        if (imgui.SliderInt('Columns', columnCount, 1, 80)) then
            gConfig.inventoryTrackerColumnCount = columnCount[1];
            UpdateUserSettings(); -- Update visuals in real-time
        end
        if (imgui.IsItemDeactivatedAfterEdit()) then
            SaveSettingsOnly();
        end

        local rowCount = { gConfig.inventoryTrackerRowCount };
        if (imgui.SliderInt('Rows', rowCount, 1, 80)) then
            gConfig.inventoryTrackerRowCount = rowCount[1];
            UpdateUserSettings(); -- Update visuals in real-time
        end
        if (imgui.IsItemDeactivatedAfterEdit()) then
            SaveSettingsOnly();
        end

        DrawSlider('Scale', 'inventoryTrackerScale', 0.5, 3.0, '%.1f');
        DrawSlider('Font Size', 'inventoryTrackerFontSize', 8, 36);

        imgui.EndChild();
    end
end

-- Helper for Cast Bar: Draw a single fast cast slider
local function DrawFastCastSlider(jobName, jobIndex)
    local value = { gConfig.castBarFastCast[jobIndex] };
    if (imgui.SliderFloat('Fast Cast - ' .. jobName, value, 0.00, 1.00, '%.2f')) then
        gConfig.castBarFastCast[jobIndex] = value[1];
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then
        SaveSettingsOnly();
    end
end

-- Section: Cast Bar Settings
local function DrawCastBarSettings()
    if (imgui.CollapsingHeader("Cast Bar")) then
        imgui.BeginChild("CastBarSettings", { 0, 160 }, true);

        DrawCheckbox('Enabled', 'showCastBar', CheckVisibility);
        DrawCheckbox('Show Bookends', 'showCastBarBookends');

        DrawSlider('Scale X', 'castBarScaleX', 0.1, 3.0, '%.1f');
        DrawSlider('Scale Y', 'castBarScaleY', 0.1, 3.0, '%.1f');
        DrawSlider('Font Size', 'castBarFontSize', 8, 36);

        DrawCheckbox('Enable Fast Cast / True Display', 'castBarFastCastEnabled');

        -- Special fast cast sliders
        local castBarFCRDMSJ = { gConfig.castBarFastCastRDMSJ };
        if (imgui.SliderFloat('Fast Cast - RDM SubJob', castBarFCRDMSJ, 0.00, 1.00, '%.2f')) then
            gConfig.castBarFastCastRDMSJ = castBarFCRDMSJ[1];
        end
        if (imgui.IsItemDeactivatedAfterEdit()) then
            SaveSettingsOnly();
        end

        local castBarFCWHMCureSpeed = { gConfig.castBarFastCastWHMCureSpeed };
        if (imgui.SliderFloat('WHM Cure Speed', castBarFCWHMCureSpeed, 0.00, 1.00, '%.2f')) then
            gConfig.castBarFastCastWHMCureSpeed = castBarFCWHMCureSpeed[1];
        end
        if (imgui.IsItemDeactivatedAfterEdit()) then
            SaveSettingsOnly();
        end

        local castBarFCBRDSingSpeed = { gConfig.castBarFastCastBRDSingSpeed };
        if (imgui.SliderFloat('BRD Sing Speed', castBarFCBRDSingSpeed, 0.00, 1.00, '%.2f')) then
            gConfig.castBarFastCastBRDSingSpeed = castBarFCBRDSingSpeed[1];
        end
        if (imgui.IsItemDeactivatedAfterEdit()) then
            SaveSettingsOnly();
        end

        -- Job-specific fast cast sliders (using helper function)
        local jobs = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM', 'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP', 'DNC', 'SCH', 'GEO', 'RUN' };
        for i = 1, #jobs do
            DrawFastCastSlider(jobs[i], i);
        end

        imgui.EndChild();
    end
end

config.DrawWindow = function(us)
    imgui.PushStyleColor(ImGuiCol_WindowBg, {0,0.06,.16,.9});
	imgui.PushStyleColor(ImGuiCol_TitleBg, {0,0.06,.16, .7});
	imgui.PushStyleColor(ImGuiCol_TitleBgActive, {0,0.06,.16, .9});
	imgui.PushStyleColor(ImGuiCol_TitleBgCollapsed, {0,0.06,.16, .5});
    imgui.PushStyleColor(ImGuiCol_Header, {0,0.06,.16,.7});
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, {0,0.06,.16, .9});
    imgui.PushStyleColor(ImGuiCol_HeaderActive, {0,0.06,.16, 1});
    imgui.PushStyleColor(ImGuiCol_FrameBg, {0,0.06,.16, 1});

    -- Set proper spacing and padding for config menu
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {8, 8});
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {4, 3});
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {8, 4});

    imgui.SetNextWindowSize({ 600, 600 }, ImGuiCond_FirstUseEver);
    if(showConfig[1] and imgui.Begin(("HXUI Config"):fmt(addon.version), showConfig, bit.bor(ImGuiWindowFlags_NoSavedSettings))) then
        if(imgui.Button("Color Config", { 160, 20 })) then
            gShowColorCustom[1] = true;
        end
        imgui.SameLine();
        if(imgui.Button("Reset Settings", { 160, 20 })) then
            showRestoreDefaultsConfirm = true;
            imgui.OpenPopup("Confirm Reset Settings");
        end
        imgui.SameLine();
        if(imgui.Button("Patch Notes", { 130, 20 })) then
            gConfig.patchNotesVer = -1;
            gShowPatchNotes = { true; }
            UpdateSettings();
        end

        -- Reset Settings confirmation popup
        if (showRestoreDefaultsConfirm) then
            imgui.OpenPopup("Confirm Reset Settings");
            showRestoreDefaultsConfirm = false;
        end

        if (imgui.BeginPopupModal("Confirm Reset Settings", true, ImGuiWindowFlags_AlwaysAutoResize)) then
            imgui.Text("Are you sure you want to reset all settings to defaults?");
            imgui.Text("This will reset all your customizations including:");
            imgui.BulletText("UI positions, scales, and visibility");
            imgui.BulletText("Font settings");
            imgui.BulletText("Color customizations");
            imgui.NewLine();

            if (imgui.Button("Confirm", { 120, 0 })) then
                ResetSettings();
                UpdateSettings();
                imgui.CloseCurrentPopup();
            end
            imgui.SameLine();
            if (imgui.Button("Cancel", { 120, 0 })) then
                imgui.CloseCurrentPopup();
            end

            imgui.EndPopup();
        end

        imgui.BeginChild("Config Options", { 0, 0 }, true);

        -- Draw all configuration sections
        DrawGeneralSettings();
        DrawFontSettings();
        DrawBarSettings();
        DrawPlayerBarSettings();
        DrawTargetBarSettings();
        DrawEnemyListSettings();
        DrawPartyListSettings();
        DrawExpBarSettings();
        DrawGilTrackerSettings();
        DrawInventoryTrackerSettings();
        DrawCastBarSettings();

        imgui.EndChild();
    end

    imgui.PopStyleVar(3);
    imgui.PopStyleColor(8);
	imgui.End();
end

return config;
