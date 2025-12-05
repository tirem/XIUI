require ("common");
require('helpers');
local statusHandler = require('statushandler');
local imgui = require("imgui");
local ffi = require("ffi");

local config = {};

-- State for confirmation dialogs
local showRestoreDefaultsConfirm = false;
local showRestoreColorsConfirm = false;

-- Social icon textures
local discordTexture = nil;
local githubTexture = nil;

-- Navigation state
local selectedCategory = 1;  -- 1-indexed category selection
local selectedTab = 1;       -- 1 = settings, 2 = color settings
local selectedPartyTab = 1;  -- 1 = Party A, 2 = Party B, 3 = Party C
local selectedPartyColorTab = 1;  -- 1 = Party A, 2 = Party B, 3 = Party C (for color settings)

-- Category definitions
local categories = {
    { name = 'global', label = 'Global' },
    { name = 'playerBar', label = 'Player Bar' },
    { name = 'targetBar', label = 'Target Bar' },
    { name = 'enemyList', label = 'Enemy List' },
    { name = 'partyList', label = 'Party List' },
    { name = 'expBar', label = 'Exp Bar' },
    { name = 'gilTracker', label = 'Gil Tracker' },
    { name = 'inventoryTracker', label = 'Inventory' },
    { name = 'castBar', label = 'Cast Bar' },
};

-- Column spacing for horizontal color picker layouts
local COLOR_COLUMN_SPACING = 200;

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

-- Draw a single gradient picker column (for horizontal layout)
local function DrawGradientPickerColumn(label, gradientTable, helpText)
    if not gradientTable then return; end

    imgui.BeginGroup();

    local enabled = { gradientTable.enabled };
    if (imgui.Checkbox('Use Gradient##'..label, enabled)) then
        gradientTable.enabled = enabled[1];
        SaveSettingsOnly();
    end
    imgui.ShowHelp('Enable gradient (2 colors) or use static color');

    local startColor = HexToImGui(gradientTable.start);
    if (imgui.ColorEdit4(label..'##start'..label, startColor, bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar))) then
        gradientTable.start = ImGuiToHex(startColor);
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end

    if gradientTable.enabled then
        local stopColor = HexToImGui(gradientTable.stop);
        if (imgui.ColorEdit4(label..'##end'..label, stopColor, bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar))) then
            gradientTable.stop = ImGuiToHex(stopColor);
        end
        if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end
        if helpText then imgui.ShowHelp(helpText); end
    end

    imgui.EndGroup();
end

-- Draw HP bar colors in a 4-column horizontal layout
local function DrawHPBarColorsRow(hpGradient, idSuffix)
    idSuffix = idSuffix or "";

    -- Column headers
    imgui.Text("High (75-100%)");
    imgui.SameLine(COLOR_COLUMN_SPACING);
    imgui.Text("Med-High (50-75%)");
    imgui.SameLine(COLOR_COLUMN_SPACING * 2);
    imgui.Text("Med-Low (25-50%)");
    imgui.SameLine(COLOR_COLUMN_SPACING * 3);
    imgui.Text("Low (0-25%)");

    -- High HP column
    DrawGradientPickerColumn("High"..idSuffix, hpGradient.high, "HP bar when health is above 75%");

    imgui.SameLine(COLOR_COLUMN_SPACING);

    -- Med-High HP column
    DrawGradientPickerColumn("Med-High"..idSuffix, hpGradient.medHigh, "HP bar when health is 50-75%");

    imgui.SameLine(COLOR_COLUMN_SPACING * 2);

    -- Med-Low HP column
    DrawGradientPickerColumn("Med-Low"..idSuffix, hpGradient.medLow, "HP bar when health is 25-50%");

    imgui.SameLine(COLOR_COLUMN_SPACING * 3);

    -- Low HP column
    DrawGradientPickerColumn("Low"..idSuffix, hpGradient.low, "HP bar when health is below 25%");
end

-- Draw a 2-column row for MP/TP or similar pairs
local function DrawTwoColumnRow(label1, gradient1, help1, label2, gradient2, help2, idSuffix)
    idSuffix = idSuffix or "";

    -- Column headers
    imgui.Text(label1);
    imgui.SameLine(COLOR_COLUMN_SPACING);
    imgui.Text(label2);

    -- First column
    DrawGradientPickerColumn(label1..idSuffix, gradient1, help1);

    imgui.SameLine(COLOR_COLUMN_SPACING);

    -- Second column
    DrawGradientPickerColumn(label2..idSuffix, gradient2, help2);
end

-- Draw a single effect column (gradient + flash color)
local function DrawEffectColumn(label, gradientTable, gradientHelp, parentTable, flashKey, flashHelp, idSuffix)
    if not gradientTable then return; end

    imgui.BeginGroup();

    local enabled = { gradientTable.enabled };
    if (imgui.Checkbox('Use Gradient##'..label..idSuffix, enabled)) then
        gradientTable.enabled = enabled[1];
        SaveSettingsOnly();
    end
    imgui.ShowHelp('Enable gradient (2 colors) or use static color');

    local startColor = HexToImGui(gradientTable.start);
    if (imgui.ColorEdit4(label..'##start'..label..idSuffix, startColor, bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar))) then
        gradientTable.start = ImGuiToHex(startColor);
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end

    if gradientTable.enabled then
        local stopColor = HexToImGui(gradientTable.stop);
        if (imgui.ColorEdit4(label..'##end'..label..idSuffix, stopColor, bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar))) then
            gradientTable.stop = ImGuiToHex(stopColor);
        end
        if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end
        if gradientHelp then imgui.ShowHelp(gradientHelp); end
    end

    -- Flash color
    if parentTable and flashKey and parentTable[flashKey] then
        local flashColor = HexToImGui(parentTable[flashKey]);
        if (imgui.ColorEdit4('Flash##'..label..idSuffix, flashColor, bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar))) then
            parentTable[flashKey] = ImGuiToHex(flashColor);
        end
        if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end
        if flashHelp then imgui.ShowHelp(flashHelp); end
    end

    imgui.EndGroup();
end

-- Draw HP effects (Damage/Healing) in 2-column layout
local function DrawHPEffectsRow(shared, idSuffix)
    idSuffix = idSuffix or "";

    -- Column headers
    imgui.Text("Damage Effect");
    imgui.SameLine(COLOR_COLUMN_SPACING);
    imgui.Text("Healing Effect");

    -- Damage column
    DrawEffectColumn("Damage", shared.hpDamageGradient, "Color of the trailing bar when HP decreases",
                     shared, 'hpDamageFlashColor', "Flash overlay color when taking damage", idSuffix);

    imgui.SameLine(COLOR_COLUMN_SPACING);

    -- Healing column
    DrawEffectColumn("Healing", shared.hpHealGradient, "Color of the leading bar when HP increases",
                     shared, 'hpHealFlashColor', "Flash overlay color when healing", idSuffix);
end

-- Color picker helper functions (for color settings tabs)
local function DrawGradientPicker(label, gradientTable, helpText)
    if not gradientTable then return; end

    local enabled = { gradientTable.enabled };
    if (imgui.Checkbox('Use Gradient##'..label, enabled)) then
        gradientTable.enabled = enabled[1];
        SaveSettingsOnly();
    end
    imgui.ShowHelp('Enable gradient (2 colors) or use static color (single color)');

    local startColor = HexToImGui(gradientTable.start);
    if (imgui.ColorEdit4(label..' Start##'..label, startColor, bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar))) then
        gradientTable.start = ImGuiToHex(startColor);
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end

    if gradientTable.enabled then
        local stopColor = HexToImGui(gradientTable.stop);
        if (imgui.ColorEdit4(label..' End##'..label, stopColor, bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar))) then
            gradientTable.stop = ImGuiToHex(stopColor);
        end
        if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end
    end

    if helpText then imgui.ShowHelp(helpText); end
end

local function DrawHexColorPicker(label, parentTable, key, helpText)
    if not parentTable or not parentTable[key] then return; end

    local colorValue = parentTable[key];
    local colorRGBA = HexToImGui(colorValue);

    if (imgui.ColorEdit4(label, colorRGBA, bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar))) then
        parentTable[key] = ImGuiToHex(colorRGBA);
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end

    if helpText then imgui.ShowHelp(helpText); end
end

local function DrawThreeStepGradientPicker(label, gradientTable, helpText)
    if not gradientTable then return; end

    local startColor = HexToImGui(gradientTable.start);
    if (imgui.ColorEdit4(label..' Top##'..label, startColor, bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar))) then
        gradientTable.start = ImGuiToHex(startColor);
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end

    local midColor = HexToImGui(gradientTable.mid);
    if (imgui.ColorEdit4(label..' Middle##'..label, midColor, bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar))) then
        gradientTable.mid = ImGuiToHex(midColor);
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end

    local stopColor = HexToImGui(gradientTable.stop);
    if (imgui.ColorEdit4(label..' Bottom##'..label, stopColor, bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar))) then
        gradientTable.stop = ImGuiToHex(stopColor);
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end

    if helpText then imgui.ShowHelp(helpText); end
end

local function DrawTextColorPicker(label, parentTable, key, helpText)
    if not parentTable or not parentTable[key] then return; end

    local colorValue = parentTable[key];
    local colorRGBA = ARGBToImGui(colorValue);

    if (imgui.ColorEdit4(label, colorRGBA, bit.bor(ImGuiColorEditFlags_AlphaBar, ImGuiColorEditFlags_NoInputs))) then
        parentTable[key] = ImGuiToARGB(colorRGBA);
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end

    if helpText then imgui.ShowHelp(helpText); end
end

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
    -- Use configKey as unique ID to prevent ImGui widget collision
    local uniqueLabel = label .. '##' .. configKey;
    if (imgui.Checkbox(uniqueLabel, { currentLayout[configKey] })) then
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
    -- Use configKey as unique ID to prevent ImGui widget collision
    local uniqueLabel = label .. '##' .. configKey;

    -- Use SliderFloat if format is specified, otherwise check if value is integer
    if format ~= nil then
        -- Format specified, use float slider
        changed = imgui.SliderFloat(uniqueLabel, value, min, max, format);
    elseif type(currentLayout[configKey]) == 'number' and math.floor(currentLayout[configKey]) == currentLayout[configKey] then
        -- No format and value is integer, use int slider
        changed = imgui.SliderInt(uniqueLabel, value, min, max);
    else
        -- No format but value is float, use float slider with default format
        changed = imgui.SliderFloat(uniqueLabel, value, min, max, '%.2f');
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

-- Helper function for per-party checkbox (saves to partyA/B/C table)
local function DrawPartyCheckbox(partyTable, label, configKey, callback)
    local uniqueLabel = label .. '##party_' .. configKey;
    if (imgui.Checkbox(uniqueLabel, { partyTable[configKey] })) then
        partyTable[configKey] = not partyTable[configKey];
        SaveSettingsOnly();
        UpdateUserSettings();
        if callback then callback() end
    end
end

-- Helper function for per-party slider (saves to partyA/B/C table)
local function DrawPartySlider(partyTable, label, configKey, min, max, format, callback)
    local value = { partyTable[configKey] or min };
    local changed = false;
    local uniqueLabel = label .. '##party_' .. configKey;

    if format ~= nil then
        changed = imgui.SliderFloat(uniqueLabel, value, min, max, format);
    elseif type(partyTable[configKey]) == 'number' and math.floor(partyTable[configKey]) == partyTable[configKey] then
        changed = imgui.SliderInt(uniqueLabel, value, min, max);
    else
        changed = imgui.SliderFloat(uniqueLabel, value, min, max, '%.2f');
    end

    if changed then
        partyTable[configKey] = value[1];
        if callback then callback() end
        UpdateUserSettings();
    end

    if (imgui.IsItemDeactivatedAfterEdit()) then
        SaveSettingsToDisk();
    end
end

-- Helper function for per-party combo box
local function DrawPartyComboBox(partyTable, label, configKey, items, callback)
    local currentValue = partyTable[configKey];
    local uniqueLabel = label .. '##party_' .. configKey;

    if (imgui.BeginCombo(uniqueLabel, currentValue)) then
        for i = 1, #items do
            local is_selected = items[i] == currentValue;
            if (imgui.Selectable(items[i], is_selected) and items[i] ~= currentValue) then
                partyTable[configKey] = items[i];
                SaveSettingsOnly();
                UpdateUserSettings();
                if callback then callback(items[i]) end
            end
            if (is_selected) then
                imgui.SetItemDefaultFocus();
            end
        end
        imgui.EndCombo();
    end
end

-- Helper function for per-party indexed combo box (0-based index)
local function DrawPartyComboBoxIndexed(partyTable, label, configKey, items, callback)
    local currentIndex = partyTable[configKey] or 0;
    local uniqueLabel = label .. '##party_' .. configKey;

    if (imgui.BeginCombo(uniqueLabel, items[currentIndex] or items[0])) then
        for i = 0, #items do
            local is_selected = i == currentIndex;
            if (imgui.Selectable(items[i], is_selected) and i ~= currentIndex) then
                partyTable[configKey] = i;
                SaveSettingsOnly();
                UpdateUserSettings();
                if callback then callback(i) end
            end
            if (is_selected) then
                imgui.SetItemDefaultFocus();
            end
        end
        imgui.EndCombo();
    end
end

-- Helper function for per-party color picker (ARGB format, saves to partyA/B/C table)
local function DrawPartyColorPicker(partyTable, label, configKey, helpText, defaultColor)
    local colorValue = partyTable[configKey];
    -- Initialize with default color if not set
    if not colorValue then
        colorValue = defaultColor or 0xFFFFFFFF;
        partyTable[configKey] = colorValue;
    end

    local colorRGBA = ARGBToImGui(colorValue);
    local uniqueLabel = label .. '##party_' .. configKey;

    if (imgui.ColorEdit4(uniqueLabel, colorRGBA, bit.bor(ImGuiColorEditFlags_AlphaBar, ImGuiColorEditFlags_NoInputs))) then
        partyTable[configKey] = ImGuiToARGB(colorRGBA);
        UpdateUserSettings();
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsToDisk(); end

    if helpText then imgui.ShowHelp(helpText); end
end

-- Section: Global Settings (combines General, Font, and Bar settings)
local function DrawGlobalSettings()
    DrawCheckbox('Lock HUD Position', 'lockPositions');

    -- Status Icon Theme
    local status_theme_paths = statusHandler.get_status_theme_paths();
    DrawComboBox('Status Icon Theme', gConfig.statusIconTheme, status_theme_paths, function(newValue)
        gConfig.statusIconTheme = newValue;
        SaveSettingsOnly();
        DeferredUpdateVisuals();
    end);
    imgui.ShowHelp('The folder to pull status icons from. [XIUI\\assets\\status]');

    -- Job Icon Theme
    local job_theme_paths = statusHandler.get_job_theme_paths();
    DrawComboBox('Job Icon Theme', gConfig.jobIconTheme, job_theme_paths, function(newValue)
        gConfig.jobIconTheme = newValue;
        SaveSettingsOnly();
        DeferredUpdateVisuals();
    end);
    imgui.ShowHelp('The folder to pull job icons from. [XIUI\\assets\\jobs]');

    DrawSlider('Tooltip Scale', 'tooltipScale', 0.1, 3.0, '%.2f');
    imgui.ShowHelp('Scales the size of the tooltip. Note that text may appear blured if scaled too large.');

    DrawCheckbox('Hide During Events', 'hideDuringEvents');

    imgui.Spacing();
    imgui.Text("Fonts");
    imgui.Separator();
    imgui.Spacing();

    -- Font Family Selector
    DrawComboBox('Font Family', gConfig.fontFamily, available_fonts, function(newValue)
        gConfig.fontFamily = newValue;
        ClearDebuffFontCache();
        UpdateSettings();
    end);
    imgui.ShowHelp('The font family to use for all text in XIUI. Fonts must be installed on your system.');

    -- Font Weight Selector
    DrawComboBox('Font Weight', gConfig.fontWeight, {'Normal', 'Bold'}, function(newValue)
        gConfig.fontWeight = newValue;
        ClearDebuffFontCache();
        UpdateSettings();
    end);
    imgui.ShowHelp('The font weight (boldness) to use for all text in XIUI.');

    -- Font Outline Width Slider
    DrawSlider('Font Outline Width', 'fontOutlineWidth', 0, 5, nil, function()
        ClearDebuffFontCache();
        DeferredUpdateVisuals();
    end);
    imgui.ShowHelp('The thickness of the text outline/stroke for all text in XIUI.');

    imgui.Spacing();
    imgui.Text("Bar Settings");
    imgui.Separator();
    imgui.Spacing();

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
end

-- Section: Global Color Settings
local function DrawGlobalColorSettings()
    imgui.Text("Background Color:");
    imgui.Separator();
    imgui.Spacing();
    DrawGradientPicker("Bar Background", gConfig.colorCustomization.shared.backgroundGradient, "Background color for all progress bars");

    imgui.Spacing();
    imgui.Text("Bookend Gradient:");
    imgui.Separator();
    imgui.Spacing();
    DrawThreeStepGradientPicker("Bookend", gConfig.colorCustomization.shared.bookendGradient, "3-step gradient for progress bar bookends (top -> middle -> bottom)");

    imgui.Spacing();
    imgui.Text("Entity Name Colors (by type):");
    imgui.Separator();
    imgui.Spacing();
    DrawTextColorPicker("Party/Alliance Player", gConfig.colorCustomization.shared, 'playerPartyTextColor', "Color for party/alliance member names");
    DrawTextColorPicker("Other Player", gConfig.colorCustomization.shared, 'playerOtherTextColor', "Color for other player names");
    DrawTextColorPicker("NPC", gConfig.colorCustomization.shared, 'npcTextColor', "Color for NPC names");
    DrawTextColorPicker("Unclaimed Mob", gConfig.colorCustomization.shared, 'mobUnclaimedTextColor', "Color for unclaimed mob names");
    DrawTextColorPicker("Party-Claimed Mob", gConfig.colorCustomization.shared, 'mobPartyClaimedTextColor', "Color for mobs claimed by your party");
    DrawTextColorPicker("Other-Claimed Mob", gConfig.colorCustomization.shared, 'mobOtherClaimedTextColor', "Color for mobs claimed by others");

    imgui.Spacing();
    imgui.Text("HP Bar Effects (Damage/Healing):");
    imgui.Separator();
    imgui.Spacing();
    DrawHPEffectsRow(gConfig.colorCustomization.shared, "##shared");
end

-- Section: Player Bar Settings
local function DrawPlayerBarSettings()
    DrawCheckbox('Enabled', 'showPlayerBar', CheckVisibility);
    DrawCheckbox('Show Bookends', 'showPlayerBarBookends');
    DrawCheckbox('Hide During Events', 'playerBarHideDuringEvents');
    DrawCheckbox('Always Show MP Bar', 'alwaysShowMpBar');
    imgui.ShowHelp('Always display the MP Bar even if your current jobs cannot cast spells.');

    DrawSlider('Scale X', 'playerBarScaleX', 0.1, 3.0, '%.1f');
    DrawSlider('Scale Y', 'playerBarScaleY', 0.1, 3.0, '%.1f');
    DrawSlider('Font Size', 'playerBarFontSize', 8, 36);
end

-- Section: Player Bar Color Settings
local function DrawPlayerBarColorSettings()
    imgui.Text("HP Bar Colors:");
    imgui.Separator();
    imgui.Spacing();
    DrawHPBarColorsRow(gConfig.colorCustomization.playerBar.hpGradient, "##playerBar");

    imgui.Spacing();
    imgui.Spacing();
    imgui.Text("MP/TP Bar Colors:");
    imgui.Separator();
    imgui.Spacing();
    DrawTwoColumnRow("MP Bar", gConfig.colorCustomization.playerBar.mpGradient, "MP bar color gradient",
                     "TP Bar", gConfig.colorCustomization.playerBar.tpGradient, "TP bar color gradient", "##playerBar");

    imgui.Spacing();
    imgui.Spacing();
    imgui.Text("Text Colors:");
    imgui.Separator();
    imgui.Spacing();
    DrawTextColorPicker("HP Text", gConfig.colorCustomization.playerBar, 'hpTextColor', "Color of HP number text");
    DrawTextColorPicker("MP Text", gConfig.colorCustomization.playerBar, 'mpTextColor', "Color of MP number text");
    DrawTextColorPicker("TP Text (Empty, <1000)", gConfig.colorCustomization.playerBar, 'tpEmptyTextColor', "Color of TP number text when below 1000");
    DrawTextColorPicker("TP Text (Full, >=1000)", gConfig.colorCustomization.playerBar, 'tpFullTextColor', "Color of TP number text when 1000 or higher");
end

-- Section: Target Bar Settings
local function DrawTargetBarSettings()
    DrawCheckbox('Enabled', 'showTargetBar', CheckVisibility);
    DrawCheckbox('Show Distance', 'showTargetDistance');
    DrawCheckbox('Show Bookends', 'showTargetBarBookends');
    DrawCheckbox('Show Lock On', 'showTargetBarLockOnBorder');
    imgui.ShowHelp('Display the lock icon and colored border when locked on to a target.');
    if (not HzLimitedMode) then
        DrawCheckbox('Show Cast Bar', 'showTargetBarCastBar');
        imgui.ShowHelp('Display the enemy cast bar under the HP bar when the target is casting.');
    end
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
    if (gConfig.showTargetBarCastBar and (not HzLimitedMode)) then
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

    -- Target of Target Bar settings (only show when split is enabled)
    if (gConfig.splitTargetOfTarget) then
        imgui.Spacing();
        imgui.Text('Target of Target Bar');
        imgui.Separator();
        imgui.Spacing();

        DrawSlider('ToT Scale X', 'totBarScaleX', 0.1, 3.0, '%.1f');
        DrawSlider('ToT Scale Y', 'totBarScaleY', 0.1, 3.0, '%.1f');
        DrawSlider('ToT Font Size', 'totBarFontSize', 8, 36);
    end
end

-- Section: Target Bar Color Settings
local function DrawTargetBarColorSettings()
    imgui.Text("Bar Colors:");
    imgui.Separator();
    imgui.Spacing();
    DrawGradientPicker("Target HP Bar", gConfig.colorCustomization.targetBar.hpGradient, "Target HP bar color");
    if (not HzLimitedMode) then
        DrawGradientPicker("Cast Bar", gConfig.colorCustomization.targetBar.castBarGradient, "Enemy cast bar color");
    end

    imgui.Spacing();
    imgui.Text("Text Colors:");
    imgui.Separator();
    imgui.Spacing();
    DrawTextColorPicker("Distance Text", gConfig.colorCustomization.targetBar, 'distanceTextColor', "Color of distance text");
    if (not HzLimitedMode) then
        DrawTextColorPicker("Cast Text", gConfig.colorCustomization.targetBar, 'castTextColor', "Color of enemy cast text");
    end
    imgui.ShowHelp("Target name colors are in the Global section\nHP Percent text color is set dynamically based on HP amount");

    -- Target of Target colors
    imgui.Spacing();
    imgui.Text("Target of Target:");
    imgui.Separator();
    imgui.Spacing();
    DrawGradientPicker("ToT HP Bar", gConfig.colorCustomization.totBar.hpGradient, "Target of Target HP bar color");
    DrawTextColorPicker("ToT Name Text", gConfig.colorCustomization.totBar, 'nameTextColor', "Color of target of target name text");
end

-- Section: Enemy List Settings
local function DrawEnemyListSettings()
    DrawCheckbox('Enabled', 'showEnemyList', CheckVisibility);
    DrawCheckbox('Show Distance', 'showEnemyDistance');
    if (gConfig.showEnemyDistance) then
        DrawSlider('Distance Font Size', 'enemyListDistanceFontSize', 8, 36);
    end
    DrawCheckbox('Show HP% Text', 'showEnemyHPPText');
    if (gConfig.showEnemyHPPText) then
        DrawSlider('HP% Font Size', 'enemyListPercentFontSize', 8, 36);
    end
    DrawCheckbox('Show Debuffs', 'showEnemyListDebuffs');
    if (gConfig.showEnemyListDebuffs) then
        DrawCheckbox('Right Align Debuffs', 'enemyListDebuffsRightAlign');
        imgui.ShowHelp('When enabled, debuff icons align to the right edge of each enemy entry instead of the left.');
        DrawSlider('Debuff Offset X', 'enemyListDebuffOffsetX', -100, 200);
        imgui.ShowHelp('Horizontal offset for debuff icons. Offsets from left edge (or right edge if right-aligned).');
        DrawSlider('Debuff Offset Y', 'enemyListDebuffOffsetY', -100, 200);
        imgui.ShowHelp('Vertical offset for debuff icons from top of entry.');
        DrawSlider('Status Effect Icon Size', 'enemyListIconScale', 0.1, 3.0, '%.1f');
    end
    DrawCheckbox('Show Enemy Targets', 'showEnemyListTargets');
    imgui.ShowHelp('Shows who each enemy is targeting based on their last action.');
    DrawCheckbox('Show Bookends', 'showEnemyListBookends');
    if (not HzLimitedMode) then
        DrawCheckbox('Click to Target', 'enableEnemyListClickTarget');
        imgui.ShowHelp('Click on an enemy entry to target it. Requires /shorthand to be enabled.');
    end

    DrawSlider('Scale X', 'enemyListScaleX', 0.1, 3.0, '%.1f');
    DrawSlider('Scale Y', 'enemyListScaleY', 0.1, 3.0, '%.1f');
    DrawSlider('Name Font Size', 'enemyListNameFontSize', 8, 36);
    DrawSlider('Rows Per Column', 'enemyListRowsPerColumn', 1, 20);
    imgui.ShowHelp('Number of enemies to show per column before starting a new column.');
    DrawSlider('Max Columns', 'enemyListMaxColumns', 1, 5);
    imgui.ShowHelp('Maximum number of columns to display. Total enemies = Rows x Columns.');
    DrawSlider('Row Spacing', 'enemyListRowSpacing', 0, 20);
    imgui.ShowHelp('Vertical space between enemy entries.');
    DrawSlider('Column Spacing', 'enemyListColumnSpacing', 0, 50);
    imgui.ShowHelp('Horizontal space between columns.');
end

-- Section: Enemy List Color Settings
local function DrawEnemyListColorSettings()
    imgui.Text("HP Bar Color:");
    imgui.Separator();
    imgui.Spacing();
    DrawGradientPicker("Enemy HP Bar", gConfig.colorCustomization.enemyList.hpGradient, "Enemy HP bar color");

    imgui.Spacing();
    imgui.Text("Text Colors:");
    imgui.Separator();
    imgui.Spacing();
    DrawTextColorPicker("Distance Text", gConfig.colorCustomization.enemyList, 'distanceTextColor', "Color of distance text");
    DrawTextColorPicker("HP% Text", gConfig.colorCustomization.enemyList, 'percentTextColor', "Color of HP percentage text");
    imgui.ShowHelp("Enemy name colors are in the Global section");

    imgui.Spacing();
    imgui.Text("Border Colors:");
    imgui.Separator();
    imgui.Spacing();
    DrawTextColorPicker("Target Border", gConfig.colorCustomization.enemyList, 'targetBorderColor', "Border color for currently targeted enemy");
    DrawTextColorPicker("Subtarget Border", gConfig.colorCustomization.enemyList, 'subtargetBorderColor', "Border color for subtargeted enemy");
end

-- Helper function to copy all settings from one party to another
local function CopyPartySettings(sourcePartyName, targetPartyName)
    -- Get source and target party tables
    local sourceParty = gConfig['party' .. sourcePartyName];
    local targetParty = gConfig['party' .. targetPartyName];

    -- Copy regular settings (deep copy to avoid reference issues)
    local sourceCopy = deep_copy_table(sourceParty);
    for key, value in pairs(sourceCopy) do
        targetParty[key] = value;
    end

    -- Get source and target color tables
    local sourceColors = gConfig.colorCustomization['partyList' .. sourcePartyName];
    local targetColors = gConfig.colorCustomization['partyList' .. targetPartyName];

    -- Copy color settings (deep copy)
    local sourceColorsCopy = deep_copy_table(sourceColors);
    for key, value in pairs(sourceColorsCopy) do
        targetColors[key] = value;
    end

    -- Save and update
    UpdateSettings();
end

-- Helper function to draw per-party settings tab content
local function DrawPartyTabContent(party, partyName)
    local layoutItems = { [0] = 'Horizontal', [1] = 'Compact Vertical' };
    local statusThemeItems = { [0] = 'HorizonXI', [1] = 'HorizonXI-R', [2] = 'FFXIV', [3] = 'FFXI', [4] = 'Disabled' };
    local statusSideItems = { [0] = 'Left', [1] = 'Right' };
    local bg_theme_paths = statusHandler.get_background_paths();
    local cursor_paths = statusHandler.get_cursor_paths();

    -- Copy settings section (only for Party B and C)
    if partyName == 'B' or partyName == 'C' then
        imgui.Text('Copy Settings');
        imgui.Separator();
        imgui.Spacing();

        -- Build list of other parties to copy from
        local copyOptions = {};
        if partyName == 'B' then
            copyOptions = { 'A', 'C' };
        else -- partyName == 'C'
            copyOptions = { 'A', 'B' };
        end

        imgui.Text('Copy all settings from another party:');
        for _, sourceName in ipairs(copyOptions) do
            imgui.SameLine();
            if imgui.Button('Party ' .. sourceName .. '##copy_from_' .. sourceName .. '_to_' .. partyName) then
                CopyPartySettings(sourceName, partyName);
            end
        end
        imgui.ShowHelp('Copies all settings and colors from the selected party to this one.');

        imgui.Spacing();
    end

    -- Layout Selector
    DrawPartyComboBoxIndexed(party, 'Layout', 'layout', layoutItems, function()
        if partyList ~= nil then
            partyList.UpdateVisuals(gAdjustedSettings.partyListSettings);
        end
    end);

    imgui.Spacing();
    imgui.Text('Display Options');
    imgui.Separator();
    imgui.Spacing();

    DrawPartyCheckbox(party, 'Show TP', 'showTP');
    if party.showTP then
        DrawPartyCheckbox(party, 'Flash TP at 100%', 'flashTP');
        if party.layout == 1 then
            imgui.ShowHelp('In compact mode, the TP text will flash when at 1000+ TP.');
        end
    end
    DrawPartyCheckbox(party, 'Show Distance', 'showDistance');
    if party.showDistance then
        imgui.SameLine();
        imgui.PushItemWidth(100);
        DrawPartySlider(party, 'Highlight', 'distanceHighlight', 0.0, 50.0, '%.1f');
        imgui.PopItemWidth();
    end
    DrawPartyCheckbox(party, 'Show Job Icons', 'showJobIcon');
    if party.showJobIcon then
        imgui.SameLine();
        imgui.PushItemWidth(100);
        DrawPartySlider(party, 'Scale', 'jobIconScale', 0.1, 3.0, '%.1f');
        imgui.PopItemWidth();
    end
    DrawPartyCheckbox(party, 'Show Job/Subjob', 'showJob');
    imgui.ShowHelp('Display job and subjob info (Horizontal layout only).');
    DrawPartyCheckbox(party, 'Show Cast Bars', 'showCastBars');
    if party.showCastBars then
        imgui.SameLine();
        imgui.PushItemWidth(100);
        DrawPartySlider(party, 'Scale Y', 'castBarScaleY', 0.1, 3.0, '%.1f');
        imgui.PopItemWidth();
    end
    DrawPartyCheckbox(party, 'Show Bookends', 'showBookends');
    DrawPartyCheckbox(party, 'Show Title', 'showTitle');
    DrawPartyCheckbox(party, 'Align Bottom', 'alignBottom');
    DrawPartyCheckbox(party, 'Expand Height', 'expandHeight');

    imgui.Spacing();
    imgui.Text('Appearance');
    imgui.Separator();
    imgui.Spacing();

    DrawPartyComboBox(party, 'Background', 'backgroundName', bg_theme_paths, DeferredUpdateVisuals);
    DrawPartySlider(party, 'Background Scale', 'bgScale', 0.1, 3.0, '%.2f', UpdatePartyListVisuals);
    DrawPartyComboBox(party, 'Cursor', 'cursor', cursor_paths, DeferredUpdateVisuals);
    DrawPartyComboBoxIndexed(party, 'Status Theme', 'statusTheme', statusThemeItems);
    DrawPartyComboBoxIndexed(party, 'Status Side', 'statusSide', statusSideItems);
    DrawPartySlider(party, 'Status Icon Scale', 'buffScale', 0.1, 3.0, '%.1f');

    imgui.Spacing();
    imgui.Text('Scale & Spacing');
    imgui.Separator();
    imgui.Spacing();

    DrawPartySlider(party, 'Min Rows', 'minRows', 1, 6);
    DrawPartySlider(party, 'Entry Spacing', 'entrySpacing', -4, 16);
    DrawPartySlider(party, 'Selection Box Scale Y', 'selectionBoxScaleY', 0.5, 2.0, '%.2f');

    -- General scale controls (applies to all elements)
    DrawPartySlider(party, 'Scale X', 'scaleX', 0.1, 3.0, '%.2f');
    DrawPartySlider(party, 'Scale Y', 'scaleY', 0.1, 3.0, '%.2f');

    -- Individual bar scale controls
    imgui.Spacing();
    imgui.Text('Bar Scales');
    imgui.Separator();
    imgui.Spacing();
    DrawPartySlider(party, 'HP Bar Scale X', 'hpBarScaleX', 0.1, 3.0, '%.2f');
    DrawPartySlider(party, 'HP Bar Scale Y', 'hpBarScaleY', 0.1, 3.0, '%.2f');
    DrawPartySlider(party, 'MP Bar Scale X', 'mpBarScaleX', 0.1, 3.0, '%.2f');
    DrawPartySlider(party, 'MP Bar Scale Y', 'mpBarScaleY', 0.1, 3.0, '%.2f');
    if party.showTP then
        DrawPartySlider(party, 'TP Bar Scale X', 'tpBarScaleX', 0.1, 3.0, '%.2f');
        DrawPartySlider(party, 'TP Bar Scale Y', 'tpBarScaleY', 0.1, 3.0, '%.2f');
    end

    imgui.Spacing();
    imgui.Text('Font Sizes');
    imgui.Separator();
    imgui.Spacing();

    DrawPartyCheckbox(party, 'Split Font Sizes', 'splitFontSizes');
    imgui.ShowHelp('When enabled, allows individual font size control for each text element.');

    if party.splitFontSizes then
        DrawPartySlider(party, 'Name Font Size', 'nameFontSize', 8, 36);
        DrawPartySlider(party, 'HP Font Size', 'hpFontSize', 8, 36);
        DrawPartySlider(party, 'MP Font Size', 'mpFontSize', 8, 36);
        DrawPartySlider(party, 'TP Font Size', 'tpFontSize', 8, 36);
        DrawPartySlider(party, 'Distance Font Size', 'distanceFontSize', 8, 36);
        DrawPartySlider(party, 'Job Font Size', 'jobFontSize', 8, 36);
        DrawPartySlider(party, 'Zone Font Size', 'zoneFontSize', 8, 36);
    else
        DrawPartySlider(party, 'Font Size', 'fontSize', 8, 36);
    end
end

-- Section: Party List Settings
local function DrawPartyListSettings()
    DrawCheckbox('Enabled', 'showPartyList', CheckVisibility);

    -- Global settings (shared across all parties)
    imgui.Spacing();
    imgui.Text('Global Settings');
    imgui.Separator();
    imgui.Spacing();

    DrawCheckbox('Preview Full Party (when config open)', 'partyListPreview');
    DrawCheckbox('Show When Solo', 'showPartyListWhenSolo');
    DrawCheckbox('Hide During Events', 'partyListHideDuringEvents');
    DrawCheckbox('Alliance Windows', 'partyListAlliance');

    imgui.Spacing();

    -- Party tab buttons with gold underline for selected
    local partyTabWidth = 80;
    local partyTabHeight = 24;
    local gold = {0.957, 0.855, 0.592, 1.0};
    local bgMedium = {0.098, 0.090, 0.075, 1.0};
    local bgLight = {0.137, 0.125, 0.106, 1.0};
    local bgLighter = {0.176, 0.161, 0.137, 1.0};

    -- Party A button
    local partyAPosX, partyAPosY = imgui.GetCursorScreenPos();
    if selectedPartyTab == 1 then
        imgui.PushStyleColor(ImGuiCol_Button, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonActive, {0, 0, 0, 0});
    else
        imgui.PushStyleColor(ImGuiCol_Button, bgMedium);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, bgLight);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, bgLighter);
    end
    if imgui.Button('Party A##partyListTab', { partyTabWidth, partyTabHeight }) then
        selectedPartyTab = 1;
    end
    if selectedPartyTab == 1 then
        local draw_list = imgui.GetWindowDrawList();
        draw_list:AddRectFilled(
            {partyAPosX + 4, partyAPosY + partyTabHeight - 2},
            {partyAPosX + partyTabWidth - 4, partyAPosY + partyTabHeight},
            imgui.GetColorU32(gold),
            1.0
        );
    end
    imgui.PopStyleColor(3);

    -- Party B and C buttons (only if alliance enabled)
    if gConfig.partyListAlliance then
        imgui.SameLine();
        local partyBPosX, partyBPosY = imgui.GetCursorScreenPos();
        if selectedPartyTab == 2 then
            imgui.PushStyleColor(ImGuiCol_Button, {0, 0, 0, 0});
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0, 0, 0, 0});
            imgui.PushStyleColor(ImGuiCol_ButtonActive, {0, 0, 0, 0});
        else
            imgui.PushStyleColor(ImGuiCol_Button, bgMedium);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, bgLight);
            imgui.PushStyleColor(ImGuiCol_ButtonActive, bgLighter);
        end
        if imgui.Button('Party B##partyListTab', { partyTabWidth, partyTabHeight }) then
            selectedPartyTab = 2;
        end
        if selectedPartyTab == 2 then
            local draw_list = imgui.GetWindowDrawList();
            draw_list:AddRectFilled(
                {partyBPosX + 4, partyBPosY + partyTabHeight - 2},
                {partyBPosX + partyTabWidth - 4, partyBPosY + partyTabHeight},
                imgui.GetColorU32(gold),
                1.0
            );
        end
        imgui.PopStyleColor(3);

        imgui.SameLine();
        local partyCPosX, partyCPosY = imgui.GetCursorScreenPos();
        if selectedPartyTab == 3 then
            imgui.PushStyleColor(ImGuiCol_Button, {0, 0, 0, 0});
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0, 0, 0, 0});
            imgui.PushStyleColor(ImGuiCol_ButtonActive, {0, 0, 0, 0});
        else
            imgui.PushStyleColor(ImGuiCol_Button, bgMedium);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, bgLight);
            imgui.PushStyleColor(ImGuiCol_ButtonActive, bgLighter);
        end
        if imgui.Button('Party C##partyListTab', { partyTabWidth, partyTabHeight }) then
            selectedPartyTab = 3;
        end
        if selectedPartyTab == 3 then
            local draw_list = imgui.GetWindowDrawList();
            draw_list:AddRectFilled(
                {partyCPosX + 4, partyCPosY + partyTabHeight - 2},
                {partyCPosX + partyTabWidth - 4, partyCPosY + partyTabHeight},
                imgui.GetColorU32(gold),
                1.0
            );
        end
        imgui.PopStyleColor(3);
    else
        -- Reset to Party A if alliance is disabled and B or C was selected
        if selectedPartyTab > 1 then
            selectedPartyTab = 1;
        end
    end

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Draw content for selected party tab
    if selectedPartyTab == 1 then
        DrawPartyTabContent(gConfig.partyA, 'A');
    elseif selectedPartyTab == 2 then
        DrawPartyTabContent(gConfig.partyB, 'B');
    elseif selectedPartyTab == 3 then
        DrawPartyTabContent(gConfig.partyC, 'C');
    end
end

-- Helper function to copy only color settings from one party to another
local function CopyPartyColorSettings(sourcePartyName, targetPartyName)
    -- Get source and target color tables
    local sourceColors = gConfig.colorCustomization['partyList' .. sourcePartyName];
    local targetColors = gConfig.colorCustomization['partyList' .. targetPartyName];

    -- Copy color settings (deep copy)
    local sourceColorsCopy = deep_copy_table(sourceColors);
    for key, value in pairs(sourceColorsCopy) do
        targetColors[key] = value;
    end

    -- Save and update
    UpdateSettings();
end

-- Helper function to draw color settings for a specific party
local function DrawPartyColorTabContent(colors, partyName)
    -- Copy colors section (only for Party B and C)
    if partyName == 'B' or partyName == 'C' then
        imgui.Text('Copy Colors');
        imgui.Separator();
        imgui.Spacing();

        -- Build list of other parties to copy from
        local copyOptions = {};
        if partyName == 'B' then
            copyOptions = { 'A', 'C' };
        else -- partyName == 'C'
            copyOptions = { 'A', 'B' };
        end

        imgui.Text('Copy colors from another party:');
        for _, sourceName in ipairs(copyOptions) do
            imgui.SameLine();
            if imgui.Button('Party ' .. sourceName .. '##copy_colors_from_' .. sourceName .. '_to_' .. partyName) then
                CopyPartyColorSettings(sourceName, partyName);
            end
        end
        imgui.ShowHelp('Copies all color settings from the selected party to this one.');

        imgui.Spacing();
    end

    imgui.Text("HP Bar Colors:");
    imgui.Separator();
    imgui.Spacing();
    DrawHPBarColorsRow(colors.hpGradient, "##party" .. partyName);

    imgui.Spacing();
    imgui.Spacing();
    if partyName == 'A' then
        imgui.Text("MP/TP Bar Colors:");
        imgui.Separator();
        imgui.Spacing();
        DrawTwoColumnRow("MP Bar", colors.mpGradient, "MP bar color",
                         "TP Bar", colors.tpGradient, "TP bar color", "##party" .. partyName);
    else
        imgui.Text("MP Bar Colors:");
        imgui.Separator();
        imgui.Spacing();
        DrawGradientPickerColumn("MP Bar##party" .. partyName, colors.mpGradient, "MP bar color");
    end

    -- Cast bar only for Party A
    if partyName == 'A' then
        imgui.Spacing();
        imgui.Text("Cast Bar Colors:");
        imgui.Separator();
        imgui.Spacing();
        DrawGradientPicker("Cast Bar##" .. partyName, colors.castBarGradient, "Cast bar color (appears when casting)");
    end

    imgui.Spacing();
    imgui.Text("Bar Background Override:");
    imgui.Separator();
    imgui.Spacing();
    local overrideActive = {colors.barBackgroundOverride.active};
    if (imgui.Checkbox("Enable Background Override##" .. partyName, overrideActive)) then
        colors.barBackgroundOverride.active = overrideActive[1];
        UpdateSettings();
    end
    imgui.ShowHelp("When enabled, uses the colors below instead of the global bar background color");
    if colors.barBackgroundOverride.active then
        DrawGradientPicker("Background Color##bgOverride" .. partyName, colors.barBackgroundOverride, "Override color for bar backgrounds");
    end

    imgui.Spacing();
    imgui.Text("Bar Border Override:");
    imgui.Separator();
    imgui.Spacing();
    local borderOverrideActive = {colors.barBorderOverride.active};
    if (imgui.Checkbox("Enable Border Override##" .. partyName, borderOverrideActive)) then
        colors.barBorderOverride.active = borderOverrideActive[1];
        UpdateSettings();
    end
    imgui.ShowHelp("When enabled, uses the color below instead of the global bar background color for borders");
    if colors.barBorderOverride.active then
        local borderColor = HexToImGui(colors.barBorderOverride.color);
        if (imgui.ColorEdit4('Border Color##barBorderOverride' .. partyName, borderColor, bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar))) then
            colors.barBorderOverride.color = ImGuiToHex(borderColor);
        end
        if (imgui.IsItemDeactivatedAfterEdit()) then
            SaveSettingsOnly();
        end
        imgui.ShowHelp("Override color for bar borders");
    end

    imgui.Spacing();
    imgui.Text("Text Colors:");
    imgui.Separator();
    imgui.Spacing();
    DrawTextColorPicker("Name Text##" .. partyName, colors, 'nameTextColor', "Color of member name");
    DrawTextColorPicker("HP Text##" .. partyName, colors, 'hpTextColor', "Color of HP numbers");
    DrawTextColorPicker("MP Text##" .. partyName, colors, 'mpTextColor', "Color of MP numbers");
    DrawTextColorPicker("TP Text (Empty, <1000)##" .. partyName, colors, 'tpEmptyTextColor', "Color of TP numbers when below 1000");
    DrawTextColorPicker("TP Text (Full, >=1000)##" .. partyName, colors, 'tpFullTextColor', "Color of TP numbers when 1000 or higher");
    DrawTextColorPicker("TP Flash Color##" .. partyName, colors, 'tpFlashColor', "Color to flash when TP is 1000+");

    imgui.Spacing();
    imgui.Text("Background Colors:");
    imgui.Separator();
    imgui.Spacing();
    DrawTextColorPicker("Background Color##" .. partyName, colors, 'bgColor', "Color of party list background");
    DrawTextColorPicker("Border Color##" .. partyName, colors, 'borderColor', "Color of party list borders");

    imgui.Spacing();
    imgui.Text("Selection Colors:");
    imgui.Separator();
    imgui.Spacing();
    DrawGradientPicker("Selection Box##" .. partyName, colors.selectionGradient, "Color gradient for the selection box around targeted members");
    DrawTextColorPicker("Selection Border##" .. partyName, colors, 'selectionBorderColor', "Color of the selection box border");

    imgui.Spacing();
    imgui.Text("Subtarget Colors:");
    imgui.Separator();
    imgui.Spacing();
    -- Initialize subtarget colors if not present
    if not colors.subtargetGradient then
        colors.subtargetGradient = T{ enabled = true, start = '#d9a54d', stop = '#edcf78' };
    end
    if not colors.subtargetBorderColor then
        colors.subtargetBorderColor = 0xFFfdd017;
    end
    DrawGradientPicker("Subtarget Box##" .. partyName, colors.subtargetGradient, "Color gradient for the selection box around subtargeted members");
    DrawTextColorPicker("Subtarget Border##" .. partyName, colors, 'subtargetBorderColor', "Color of the subtarget selection box border");

    -- Cursor tint colors (stored in party config, not color customization)
    imgui.Spacing();
    imgui.Text("Cursor Tint Colors:");
    imgui.Separator();
    imgui.Spacing();
    local partyConfig = gConfig['party' .. partyName];
    DrawPartyColorPicker(partyConfig, 'Target Cursor Tint##' .. partyName, 'targetArrowTint', 'Color tint applied to the cursor when targeting a party member', 0xFFFFFFFF);
    DrawPartyColorPicker(partyConfig, 'Subtarget Cursor Tint##' .. partyName, 'subtargetArrowTint', 'Color tint applied to the cursor when subtargeting a party member', 0xFFfdd017);
end

-- Section: Party List Color Settings
local function DrawPartyListColorSettings()
    -- Party color tab buttons with gold underline for selected
    local partyTabWidth = 80;
    local partyTabHeight = 24;
    local gold = {0.957, 0.855, 0.592, 1.0};
    local bgMedium = {0.098, 0.090, 0.075, 1.0};
    local bgLight = {0.137, 0.125, 0.106, 1.0};
    local bgLighter = {0.176, 0.161, 0.137, 1.0};

    -- Party A button
    local partyAPosX, partyAPosY = imgui.GetCursorScreenPos();
    if selectedPartyColorTab == 1 then
        imgui.PushStyleColor(ImGuiCol_Button, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonActive, {0, 0, 0, 0});
    else
        imgui.PushStyleColor(ImGuiCol_Button, bgMedium);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, bgLight);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, bgLighter);
    end
    if imgui.Button('Party A##partyColorTab', { partyTabWidth, partyTabHeight }) then
        selectedPartyColorTab = 1;
    end
    if selectedPartyColorTab == 1 then
        local draw_list = imgui.GetWindowDrawList();
        draw_list:AddRectFilled(
            {partyAPosX + 4, partyAPosY + partyTabHeight - 2},
            {partyAPosX + partyTabWidth - 4, partyAPosY + partyTabHeight},
            imgui.GetColorU32(gold),
            1.0
        );
    end
    imgui.PopStyleColor(3);

    -- Party B and C buttons (only if alliance enabled)
    if gConfig.partyListAlliance then
        imgui.SameLine();
        local partyBPosX, partyBPosY = imgui.GetCursorScreenPos();
        if selectedPartyColorTab == 2 then
            imgui.PushStyleColor(ImGuiCol_Button, {0, 0, 0, 0});
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0, 0, 0, 0});
            imgui.PushStyleColor(ImGuiCol_ButtonActive, {0, 0, 0, 0});
        else
            imgui.PushStyleColor(ImGuiCol_Button, bgMedium);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, bgLight);
            imgui.PushStyleColor(ImGuiCol_ButtonActive, bgLighter);
        end
        if imgui.Button('Party B##partyColorTab', { partyTabWidth, partyTabHeight }) then
            selectedPartyColorTab = 2;
        end
        if selectedPartyColorTab == 2 then
            local draw_list = imgui.GetWindowDrawList();
            draw_list:AddRectFilled(
                {partyBPosX + 4, partyBPosY + partyTabHeight - 2},
                {partyBPosX + partyTabWidth - 4, partyBPosY + partyTabHeight},
                imgui.GetColorU32(gold),
                1.0
            );
        end
        imgui.PopStyleColor(3);

        imgui.SameLine();
        local partyCPosX, partyCPosY = imgui.GetCursorScreenPos();
        if selectedPartyColorTab == 3 then
            imgui.PushStyleColor(ImGuiCol_Button, {0, 0, 0, 0});
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0, 0, 0, 0});
            imgui.PushStyleColor(ImGuiCol_ButtonActive, {0, 0, 0, 0});
        else
            imgui.PushStyleColor(ImGuiCol_Button, bgMedium);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, bgLight);
            imgui.PushStyleColor(ImGuiCol_ButtonActive, bgLighter);
        end
        if imgui.Button('Party C##partyColorTab', { partyTabWidth, partyTabHeight }) then
            selectedPartyColorTab = 3;
        end
        if selectedPartyColorTab == 3 then
            local draw_list = imgui.GetWindowDrawList();
            draw_list:AddRectFilled(
                {partyCPosX + 4, partyCPosY + partyTabHeight - 2},
                {partyCPosX + partyTabWidth - 4, partyCPosY + partyTabHeight},
                imgui.GetColorU32(gold),
                1.0
            );
        end
        imgui.PopStyleColor(3);
    else
        -- Reset to Party A if alliance is disabled and B or C was selected
        if selectedPartyColorTab > 1 then
            selectedPartyColorTab = 1;
        end
    end

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Draw content for selected party color tab
    if selectedPartyColorTab == 1 then
        DrawPartyColorTabContent(gConfig.colorCustomization.partyListA, 'A');
    elseif selectedPartyColorTab == 2 then
        DrawPartyColorTabContent(gConfig.colorCustomization.partyListB, 'B');
    elseif selectedPartyColorTab == 3 then
        DrawPartyColorTabContent(gConfig.colorCustomization.partyListC, 'C');
    end
end

-- Section: Exp Bar Settings
local function DrawExpBarSettings()
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
end

-- Section: Exp Bar Color Settings
local function DrawExpBarColorSettings()
    imgui.Text("Bar Color:");
    imgui.Separator();
    imgui.Spacing();
    DrawGradientPicker("Exp/Merit Bar", gConfig.colorCustomization.expBar.barGradient, "Color for EXP/Merit/Capacity bar");

    imgui.Spacing();
    imgui.Text("Text Colors:");
    imgui.Separator();
    imgui.Spacing();
    DrawTextColorPicker("Job Text", gConfig.colorCustomization.expBar, 'jobTextColor', "Color of job level text");
    DrawTextColorPicker("Exp Text", gConfig.colorCustomization.expBar, 'expTextColor', "Color of experience numbers");
    DrawTextColorPicker("Percent Text", gConfig.colorCustomization.expBar, 'percentTextColor', "Color of percentage text");
end

-- Section: Gil Tracker Settings
local function DrawGilTrackerSettings()
    DrawCheckbox('Enabled', 'showGilTracker', CheckVisibility);
    DrawSlider('Scale', 'gilTrackerScale', 0.1, 3.0, '%.1f');
    DrawSlider('Font Size', 'gilTrackerFontSize', 8, 36);
    DrawCheckbox('Right Align', 'gilTrackerRightAlign', UpdateGilTrackerVisuals);
end

-- Section: Gil Tracker Color Settings
local function DrawGilTrackerColorSettings()
    imgui.Text("Text Color:");
    imgui.Separator();
    imgui.Spacing();
    DrawTextColorPicker("Gil Text", gConfig.colorCustomization.gilTracker, 'textColor', "Color of gil amount text");
end

-- Section: Inventory Tracker Settings
local function DrawInventoryTrackerSettings()
    DrawCheckbox('Enabled', 'showInventoryTracker', CheckVisibility);
    DrawCheckbox('Show Count', 'inventoryShowCount');

    local columnCount = { gConfig.inventoryTrackerColumnCount };
    if (imgui.SliderInt('Columns', columnCount, 1, 80)) then
        gConfig.inventoryTrackerColumnCount = columnCount[1];
        UpdateUserSettings();
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then
        SaveSettingsOnly();
    end

    local rowCount = { gConfig.inventoryTrackerRowCount };
    if (imgui.SliderInt('Rows', rowCount, 1, 80)) then
        gConfig.inventoryTrackerRowCount = rowCount[1];
        UpdateUserSettings();
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then
        SaveSettingsOnly();
    end

    DrawSlider('Scale', 'inventoryTrackerScale', 0.5, 3.0, '%.1f');
    DrawSlider('Font Size', 'inventoryTrackerFontSize', 8, 36);
end

-- Section: Inventory Tracker Color Settings
local function DrawInventoryTrackerColorSettings()
    imgui.Text("Text Color:");
    imgui.Separator();
    imgui.Spacing();
    DrawTextColorPicker("Count Text", gConfig.colorCustomization.inventoryTracker, 'textColor', "Color of inventory count text");

    imgui.Spacing();
    imgui.Text("Dot Colors:");
    imgui.Separator();
    imgui.Spacing();

    local emptySlot = {
        gConfig.colorCustomization.inventoryTracker.emptySlotColor.r,
        gConfig.colorCustomization.inventoryTracker.emptySlotColor.g,
        gConfig.colorCustomization.inventoryTracker.emptySlotColor.b,
        gConfig.colorCustomization.inventoryTracker.emptySlotColor.a
    };
    if (imgui.ColorEdit4('Empty Slot', emptySlot, bit.bor(ImGuiColorEditFlags_AlphaBar, ImGuiColorEditFlags_NoInputs))) then
        gConfig.colorCustomization.inventoryTracker.emptySlotColor.r = emptySlot[1];
        gConfig.colorCustomization.inventoryTracker.emptySlotColor.g = emptySlot[2];
        gConfig.colorCustomization.inventoryTracker.emptySlotColor.b = emptySlot[3];
        gConfig.colorCustomization.inventoryTracker.emptySlotColor.a = emptySlot[4];
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end
    imgui.ShowHelp('Color for empty inventory slots');

    local usedSlot = {
        gConfig.colorCustomization.inventoryTracker.usedSlotColor.r,
        gConfig.colorCustomization.inventoryTracker.usedSlotColor.g,
        gConfig.colorCustomization.inventoryTracker.usedSlotColor.b,
        gConfig.colorCustomization.inventoryTracker.usedSlotColor.a
    };
    if (imgui.ColorEdit4('Used Slot (Normal)', usedSlot, bit.bor(ImGuiColorEditFlags_AlphaBar, ImGuiColorEditFlags_NoInputs))) then
        gConfig.colorCustomization.inventoryTracker.usedSlotColor.r = usedSlot[1];
        gConfig.colorCustomization.inventoryTracker.usedSlotColor.g = usedSlot[2];
        gConfig.colorCustomization.inventoryTracker.usedSlotColor.b = usedSlot[3];
        gConfig.colorCustomization.inventoryTracker.usedSlotColor.a = usedSlot[4];
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end
    imgui.ShowHelp('Color for used inventory slots (normal)');

    local usedSlotThreshold1 = {
        gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold1.r,
        gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold1.g,
        gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold1.b,
        gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold1.a
    };
    if (imgui.ColorEdit4('Used Slot (Warning)', usedSlotThreshold1, bit.bor(ImGuiColorEditFlags_AlphaBar, ImGuiColorEditFlags_NoInputs))) then
        gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold1.r = usedSlotThreshold1[1];
        gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold1.g = usedSlotThreshold1[2];
        gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold1.b = usedSlotThreshold1[3];
        gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold1.a = usedSlotThreshold1[4];
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end
    imgui.ShowHelp('Color for used inventory slots when at warning threshold');

    local usedSlotThreshold2 = {
        gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold2.r,
        gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold2.g,
        gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold2.b,
        gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold2.a
    };
    if (imgui.ColorEdit4('Used Slot (Critical)', usedSlotThreshold2, bit.bor(ImGuiColorEditFlags_AlphaBar, ImGuiColorEditFlags_NoInputs))) then
        gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold2.r = usedSlotThreshold2[1];
        gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold2.g = usedSlotThreshold2[2];
        gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold2.b = usedSlotThreshold2[3];
        gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold2.a = usedSlotThreshold2[4];
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end
    imgui.ShowHelp('Color for used inventory slots when at critical threshold');

    imgui.Spacing();
    imgui.Text("Color Thresholds:");
    imgui.Separator();
    imgui.Spacing();

    local threshold1 = { gConfig.inventoryTrackerColorThreshold1 };
    if (imgui.SliderInt('Warning Threshold', threshold1, 0, 80)) then
        gConfig.inventoryTrackerColorThreshold1 = threshold1[1];
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end
    imgui.ShowHelp('Inventory count at which dots turn to warning color');

    local threshold2 = { gConfig.inventoryTrackerColorThreshold2 };
    if (imgui.SliderInt('Critical Threshold', threshold2, 0, 80)) then
        gConfig.inventoryTrackerColorThreshold2 = threshold2[1];
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end
    imgui.ShowHelp('Inventory count at which dots turn to critical color');
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
    DrawCheckbox('Enabled', 'showCastBar', CheckVisibility);
    DrawCheckbox('Show Bookends', 'showCastBarBookends');

    DrawSlider('Scale X', 'castBarScaleX', 0.1, 3.0, '%.1f');
    DrawSlider('Scale Y', 'castBarScaleY', 0.1, 3.0, '%.1f');
    DrawSlider('Font Size', 'castBarFontSize', 8, 36);

    DrawCheckbox('Enable Fast Cast / True Display', 'castBarFastCastEnabled');

    if gConfig.castBarFastCastEnabled then
        -- Special fast cast sliders
        local castBarFCRDMSJ = { gConfig.castBarFastCastRDMSJ };
        if (imgui.SliderFloat('Fast Cast - RDM SubJob', castBarFCRDMSJ, 0.00, 1.00, '%.2f')) then
            gConfig.castBarFastCastRDMSJ = castBarFCRDMSJ[1];
        end
        if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end

        local castBarFCWHMCureSpeed = { gConfig.castBarFastCastWHMCureSpeed };
        if (imgui.SliderFloat('WHM Cure Speed', castBarFCWHMCureSpeed, 0.00, 1.00, '%.2f')) then
            gConfig.castBarFastCastWHMCureSpeed = castBarFCWHMCureSpeed[1];
        end
        if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end

        local castBarFCBRDSingSpeed = { gConfig.castBarFastCastBRDSingSpeed };
        if (imgui.SliderFloat('BRD Sing Speed', castBarFCBRDSingSpeed, 0.00, 1.00, '%.2f')) then
            gConfig.castBarFastCastBRDSingSpeed = castBarFCBRDSingSpeed[1];
        end
        if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end

        -- Job-specific fast cast sliders (using helper function)
        local jobs = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM', 'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP', 'DNC', 'SCH', 'GEO', 'RUN' };
        for i = 1, #jobs do
            DrawFastCastSlider(jobs[i], i);
        end
    end
end

-- Section: Cast Bar Color Settings
local function DrawCastBarColorSettings()
    imgui.Text("Bar Color:");
    imgui.Separator();
    imgui.Spacing();
    DrawGradientPicker("Cast Bar", gConfig.colorCustomization.castBar.barGradient, "Color of casting progress bar");

    imgui.Spacing();
    imgui.Text("Text Colors:");
    imgui.Separator();
    imgui.Spacing();
    DrawTextColorPicker("Spell Text", gConfig.colorCustomization.castBar, 'spellTextColor', "Color of spell/ability name");
    DrawTextColorPicker("Percent Text", gConfig.colorCustomization.castBar, 'percentTextColor', "Color of cast percentage");
end

-- Dispatch tables for settings and color settings
local settingsDrawFunctions = {
    DrawGlobalSettings,
    DrawPlayerBarSettings,
    DrawTargetBarSettings,
    DrawEnemyListSettings,
    DrawPartyListSettings,
    DrawExpBarSettings,
    DrawGilTrackerSettings,
    DrawInventoryTrackerSettings,
    DrawCastBarSettings,
};

local colorSettingsDrawFunctions = {
    DrawGlobalColorSettings,
    DrawPlayerBarColorSettings,
    DrawTargetBarColorSettings,
    DrawEnemyListColorSettings,
    DrawPartyListColorSettings,
    DrawExpBarColorSettings,
    DrawGilTrackerColorSettings,
    DrawInventoryTrackerColorSettings,
    DrawCastBarColorSettings,
};

config.DrawWindow = function(us)
    -- Early exit if config window isn't shown (atom0s recommendation)
    -- This prevents unnecessary style pushes and imgui.End() calls when window is hidden
    if (not showConfig[1]) then return; end

    -- XIUI Theme Colors (dark + gold accent)
    -- Base colors from XIUI branding
    local gold = {0.957, 0.855, 0.592, 1.0};           -- #F4DA97 - Primary gold accent
    local goldDark = {0.765, 0.684, 0.474, 1.0};       -- #C3AE79 - Darker gold for hover
    local goldDarker = {0.573, 0.512, 0.355, 1.0};     -- #92835B - Even darker gold
    local bgDark = {0.051, 0.051, 0.051, 0.95};        -- #0D0D0D - Deep black background
    local bgMedium = {0.098, 0.090, 0.075, 1.0};       -- #191713 - Slightly warm dark
    local bgLight = {0.137, 0.125, 0.106, 1.0};        -- #23201B - Lighter warm dark
    local bgLighter = {0.176, 0.161, 0.137, 1.0};      -- #2D2923 - Highlight dark
    local textLight = {0.878, 0.855, 0.812, 1.0};      -- #E0DACF - Warm off-white text
    local textMuted = {0.6, 0.58, 0.54, 1.0};          -- #999388 - Muted text
    local borderDark = {0.3, 0.275, 0.235, 1.0};       -- #4D463C - Warm dark border

    -- Mapped colors for UI elements
    local bgColor = bgDark;
    local buttonColor = bgMedium;
    local buttonHoverColor = bgLight;
    local buttonActiveColor = bgLighter;
    local selectedButtonColor = {gold[1], gold[2], gold[3], 0.25};  -- Gold tinted selection
    local tabColor = bgMedium;
    local tabHoverColor = bgLight;
    local tabActiveColor = {gold[1], gold[2], gold[3], 0.3};  -- Gold tinted for selected tab
    local tabSelectedColor = {gold[1], gold[2], gold[3], 0.25};  -- Gold tinted for selected settings/color tab buttons
    local borderColor = borderDark;
    local textColor = textLight;

    imgui.PushStyleColor(ImGuiCol_WindowBg, bgColor);
    imgui.PushStyleColor(ImGuiCol_ChildBg, {0, 0, 0, 0});
    imgui.PushStyleColor(ImGuiCol_TitleBg, bgMedium);
    imgui.PushStyleColor(ImGuiCol_TitleBgActive, bgLight);
    imgui.PushStyleColor(ImGuiCol_TitleBgCollapsed, bgDark);
    imgui.PushStyleColor(ImGuiCol_FrameBg, bgMedium);
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, bgLight);
    imgui.PushStyleColor(ImGuiCol_FrameBgActive, bgLighter);
    imgui.PushStyleColor(ImGuiCol_Header, bgLight);
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, bgLighter);
    imgui.PushStyleColor(ImGuiCol_HeaderActive, {gold[1], gold[2], gold[3], 0.3});
    imgui.PushStyleColor(ImGuiCol_Border, borderColor);
    imgui.PushStyleColor(ImGuiCol_Text, textColor);
    imgui.PushStyleColor(ImGuiCol_TextDisabled, goldDark);  -- Dropdown arrows
    imgui.PushStyleColor(ImGuiCol_Button, buttonColor);
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, buttonHoverColor);
    imgui.PushStyleColor(ImGuiCol_ButtonActive, buttonActiveColor);
    imgui.PushStyleColor(ImGuiCol_CheckMark, gold);
    imgui.PushStyleColor(ImGuiCol_SliderGrab, goldDark);
    imgui.PushStyleColor(ImGuiCol_SliderGrabActive, gold);
    imgui.PushStyleColor(ImGuiCol_ScrollbarBg, bgMedium);
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrab, bgLighter);
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabHovered, borderDark);
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabActive, goldDark);
    imgui.PushStyleColor(ImGuiCol_Separator, borderDark);
    imgui.PushStyleColor(ImGuiCol_PopupBg, bgMedium);
    imgui.PushStyleColor(ImGuiCol_Tab, tabColor);
    imgui.PushStyleColor(ImGuiCol_TabHovered, tabHoverColor);
    imgui.PushStyleColor(ImGuiCol_TabActive, tabActiveColor);
    imgui.PushStyleColor(ImGuiCol_TabUnfocused, bgDark);
    imgui.PushStyleColor(ImGuiCol_TabUnfocusedActive, bgMedium);

    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {12, 12});
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {6, 4});
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {8, 6});
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 4.0);
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 6.0);
    imgui.PushStyleVar(ImGuiStyleVar_ChildRounding, 4.0);
    imgui.PushStyleVar(ImGuiStyleVar_PopupRounding, 4.0);
    imgui.PushStyleVar(ImGuiStyleVar_ScrollbarRounding, 4.0);
    imgui.PushStyleVar(ImGuiStyleVar_GrabRounding, 4.0);

    imgui.SetNextWindowSize({ 900, 650 }, ImGuiCond_FirstUseEver);
    if(imgui.Begin("XIUI Config", showConfig, bit.bor(ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoDocking))) then
        local windowWidth = imgui.GetContentRegionAvail();
        local sidebarWidth = 180;
        local contentWidth = windowWidth - sidebarWidth - 20;

        -- Top bar with reset buttons and social links
        if(imgui.Button("Reset Settings")) then
            showRestoreDefaultsConfirm = true;
        end
        imgui.SameLine();
        if(imgui.Button("Reset Colors")) then
            showRestoreColorsConfirm = true;
        end
        -- Load social icon textures if not loaded
        if discordTexture == nil then
            discordTexture = LoadTexture("socials/discord");
        end
        if githubTexture == nil then
            githubTexture = LoadTexture("socials/github");
        end

        -- Social icon buttons with square background boxes
        local boxSize = 26;
        local boxSpacing = 4;
        local iconSize = 18;
        local iconPad = (boxSize - iconSize) / 2;
        local outlineColor = imgui.GetColorU32(borderDark);

        imgui.SameLine();
        imgui.SetCursorPosX(windowWidth - (boxSize * 2) - boxSpacing);

        -- Discord button
        if discordTexture ~= nil and discordTexture.image ~= nil then
            local screenPosX, screenPosY = imgui.GetCursorScreenPos();
            local isHovered = imgui.IsMouseHoveringRect({screenPosX, screenPosY}, {screenPosX + boxSize, screenPosY + boxSize});

            -- Draw box background and outline
            local draw_list = imgui.GetWindowDrawList();
            local boxColor = isHovered and imgui.GetColorU32(bgLighter) or imgui.GetColorU32(bgLight);
            draw_list:AddRectFilled(
                {screenPosX, screenPosY},
                {screenPosX + boxSize, screenPosY + boxSize},
                boxColor,
                4.0
            );
            draw_list:AddRect(
                {screenPosX, screenPosY},
                {screenPosX + boxSize, screenPosY + boxSize},
                outlineColor,
                4.0
            );

            -- Draw image centered in box
            draw_list:AddImage(
                tonumber(ffi.cast("uint32_t", discordTexture.image)),
                {screenPosX + iconPad, screenPosY + iconPad},
                {screenPosX + iconPad + iconSize, screenPosY + iconPad + iconSize},
                {0, 0}, {1, 1},
                IM_COL32_WHITE
            );

            -- Invisible button for interaction
            imgui.InvisibleButton("discord_btn", { boxSize, boxSize });
            if imgui.IsItemHovered() then
                imgui.SetMouseCursor(ImGuiMouseCursor_Hand);
            end
            if imgui.IsItemClicked() then
                ashita.misc.open_url("https://discord.gg/PDFJebrwN4");
            end
        end

        imgui.SameLine(0, boxSpacing);

        -- GitHub button
        if githubTexture ~= nil and githubTexture.image ~= nil then
            local screenPosX, screenPosY = imgui.GetCursorScreenPos();
            local isHovered = imgui.IsMouseHoveringRect({screenPosX, screenPosY}, {screenPosX + boxSize, screenPosY + boxSize});

            -- Draw box background and outline
            local draw_list = imgui.GetWindowDrawList();
            local boxColor = isHovered and imgui.GetColorU32(bgLighter) or imgui.GetColorU32(bgLight);
            draw_list:AddRectFilled(
                {screenPosX, screenPosY},
                {screenPosX + boxSize, screenPosY + boxSize},
                boxColor,
                4.0
            );
            draw_list:AddRect(
                {screenPosX, screenPosY},
                {screenPosX + boxSize, screenPosY + boxSize},
                outlineColor,
                4.0
            );

            -- Draw image centered in box
            draw_list:AddImage(
                tonumber(ffi.cast("uint32_t", githubTexture.image)),
                {screenPosX + iconPad, screenPosY + iconPad},
                {screenPosX + iconPad + iconSize, screenPosY + iconPad + iconSize},
                {0, 0}, {1, 1},
                IM_COL32_WHITE
            );

            -- Invisible button for interaction
            imgui.InvisibleButton("github_btn", { boxSize, boxSize });
            if imgui.IsItemHovered() then
                imgui.SetMouseCursor(ImGuiMouseCursor_Hand);
            end
            if imgui.IsItemClicked() then
                ashita.misc.open_url("https://github.com/tirem/xiui");
            end
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

        -- Reset Colors confirmation popup
        if (showRestoreColorsConfirm) then
            imgui.OpenPopup("Confirm Reset Colors");
            showRestoreColorsConfirm = false;
        end

        if (imgui.BeginPopupModal("Confirm Reset Colors", true, ImGuiWindowFlags_AlwaysAutoResize)) then
            imgui.Text("Are you sure you want to restore all colors to defaults?");
            imgui.Text("This will reset all your custom colors.");
            imgui.NewLine();

            if (imgui.Button("Confirm", { 120, 0 })) then
                gConfig.colorCustomization = deep_copy_table(defaultUserSettings.colorCustomization);
                UpdateSettings();
                imgui.CloseCurrentPopup();
            end
            imgui.SameLine();
            if (imgui.Button("Cancel", { 120, 0 })) then
                imgui.CloseCurrentPopup();
            end

            imgui.EndPopup();
        end

        imgui.Spacing();

        -- Main layout: sidebar + content area
        -- Left sidebar with category buttons
        imgui.BeginChild("Sidebar", { sidebarWidth, 0 }, ImGuiChildFlags_None);

        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {10, 8});

        for i, category in ipairs(categories) do
            -- Style the button differently if selected
            if i == selectedCategory then
                imgui.PushStyleColor(ImGuiCol_Button, selectedButtonColor);
                imgui.PushStyleColor(ImGuiCol_ButtonHovered, selectedButtonColor);
                imgui.PushStyleColor(ImGuiCol_ButtonActive, selectedButtonColor);
            else
                imgui.PushStyleColor(ImGuiCol_Button, {0, 0, 0, 0});
                imgui.PushStyleColor(ImGuiCol_ButtonHovered, buttonHoverColor);
                imgui.PushStyleColor(ImGuiCol_ButtonActive, buttonActiveColor);
            end

            -- Get position before drawing button for accent bar
            local btnPosX, btnPosY = imgui.GetCursorScreenPos();

            if (imgui.Button(category.label, { sidebarWidth - 16, 32 })) then
                selectedCategory = i;
            end

            -- Draw gold accent bar on the left edge for selected category
            if i == selectedCategory then
                local draw_list = imgui.GetWindowDrawList();
                draw_list:AddRectFilled(
                    {btnPosX, btnPosY + 4},
                    {btnPosX + 3, btnPosY + 28},
                    imgui.GetColorU32(gold),
                    1.5
                );
            end

            imgui.PopStyleColor(3);
        end

        imgui.PopStyleVar();
        imgui.EndChild();

        imgui.SameLine();

        -- Right content area
        imgui.BeginChild("ContentArea", { 0, 0 }, ImGuiChildFlags_None);

        -- Tab bar at top of content area
        local tabWidth = 140;
        local tabHeight = 28;

        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {12, 6});

        -- Settings tab
        local tabPosX, tabPosY = imgui.GetCursorScreenPos();
        if selectedTab == 1 then
            imgui.PushStyleColor(ImGuiCol_Button, tabSelectedColor);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, tabSelectedColor);
            imgui.PushStyleColor(ImGuiCol_ButtonActive, tabSelectedColor);
        else
            imgui.PushStyleColor(ImGuiCol_Button, tabColor);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, tabHoverColor);
            imgui.PushStyleColor(ImGuiCol_ButtonActive, tabActiveColor);
        end
        if (imgui.Button("settings", { tabWidth, tabHeight })) then
            selectedTab = 1;
        end
        -- Draw gold underline for selected tab
        if selectedTab == 1 then
            local draw_list = imgui.GetWindowDrawList();
            draw_list:AddRectFilled(
                {tabPosX + 4, tabPosY + tabHeight - 3},
                {tabPosX + tabWidth - 4, tabPosY + tabHeight},
                imgui.GetColorU32(gold),
                1.0
            );
        end
        imgui.PopStyleColor(3);

        imgui.SameLine();

        -- Color settings tab
        local tabPos2X, tabPos2Y = imgui.GetCursorScreenPos();
        if selectedTab == 2 then
            imgui.PushStyleColor(ImGuiCol_Button, tabSelectedColor);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, tabSelectedColor);
            imgui.PushStyleColor(ImGuiCol_ButtonActive, tabSelectedColor);
        else
            imgui.PushStyleColor(ImGuiCol_Button, tabColor);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, tabHoverColor);
            imgui.PushStyleColor(ImGuiCol_ButtonActive, tabActiveColor);
        end
        if (imgui.Button("color settings", { tabWidth, tabHeight })) then
            selectedTab = 2;
        end
        -- Draw gold underline for selected tab
        if selectedTab == 2 then
            local draw_list = imgui.GetWindowDrawList();
            draw_list:AddRectFilled(
                {tabPos2X + 4, tabPos2Y + tabHeight - 3},
                {tabPos2X + tabWidth - 4, tabPos2Y + tabHeight},
                imgui.GetColorU32(gold),
                1.0
            );
        end
        imgui.PopStyleColor(3);

        imgui.PopStyleVar();

        -- Divider between tabs and content
        imgui.Spacing();
        imgui.PushStyleColor(ImGuiCol_Separator, borderDark);
        imgui.Separator();
        imgui.PopStyleColor();
        imgui.Spacing();

        -- Content panel with border
        imgui.BeginChild("SettingsContent", { 0, 0 }, ImGuiChildFlags_None);

        -- Draw the appropriate settings based on selected category and tab
        if selectedTab == 1 then
            if settingsDrawFunctions[selectedCategory] then
                settingsDrawFunctions[selectedCategory]();
            end
        else
            if colorSettingsDrawFunctions[selectedCategory] then
                colorSettingsDrawFunctions[selectedCategory]();
            end
        end

        imgui.EndChild();

        imgui.EndChild();
    end

    imgui.End();
    imgui.PopStyleVar(9);
    imgui.PopStyleColor(31);  -- 26 base + 5 tab colors
end

return config;
