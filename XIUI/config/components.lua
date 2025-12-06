--[[
* XIUI Config Menu - Shared UI Components
* Contains all reusable UI helper functions for config menu
]]--

require('common');
require('handlers.helpers');
local imgui = require('imgui');

local components = {};

-- Column spacing for horizontal color picker layouts
components.COLOR_COLUMN_SPACING = 200;

-- List of common Windows fonts
components.available_fonts = {
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

-- Helper function for collapsible section headers
-- Returns true if the section is expanded, false if collapsed
-- defaultOpen: if true, section starts expanded (default behavior)
function components.CollapsingSection(label, defaultOpen)
    if defaultOpen == nil then defaultOpen = true; end
    imgui.Spacing();
    local flags = defaultOpen and ImGuiTreeNodeFlags_DefaultOpen or 0;
    local isOpen = imgui.CollapsingHeader(label, flags);
    if isOpen then
        imgui.Spacing();
    end
    return isOpen;
end

-- Draw a single gradient picker column (for horizontal layout)
function components.DrawGradientPickerColumn(label, gradientTable, helpText)
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
function components.DrawHPBarColorsRow(hpGradient, idSuffix)
    idSuffix = idSuffix or "";

    -- Column headers
    imgui.Text("High (75-100%)");
    imgui.SameLine(components.COLOR_COLUMN_SPACING);
    imgui.Text("Med-High (50-75%)");
    imgui.SameLine(components.COLOR_COLUMN_SPACING * 2);
    imgui.Text("Med-Low (25-50%)");
    imgui.SameLine(components.COLOR_COLUMN_SPACING * 3);
    imgui.Text("Low (0-25%)");

    -- High HP column
    components.DrawGradientPickerColumn("High"..idSuffix, hpGradient.high, "HP bar when health is above 75%");

    imgui.SameLine(components.COLOR_COLUMN_SPACING);

    -- Med-High HP column
    components.DrawGradientPickerColumn("Med-High"..idSuffix, hpGradient.medHigh, "HP bar when health is 50-75%");

    imgui.SameLine(components.COLOR_COLUMN_SPACING * 2);

    -- Med-Low HP column
    components.DrawGradientPickerColumn("Med-Low"..idSuffix, hpGradient.medLow, "HP bar when health is 25-50%");

    imgui.SameLine(components.COLOR_COLUMN_SPACING * 3);

    -- Low HP column
    components.DrawGradientPickerColumn("Low"..idSuffix, hpGradient.low, "HP bar when health is below 25%");
end

-- Draw a 2-column row for MP/TP or similar pairs
-- Optional: flashColorTable and flashKey to add a flash color picker in the second column
function components.DrawTwoColumnRow(label1, gradient1, help1, label2, gradient2, help2, idSuffix, flashColorTable, flashKey, flashHelp)
    idSuffix = idSuffix or "";

    -- Column headers
    imgui.Text(label1);
    imgui.SameLine(components.COLOR_COLUMN_SPACING);
    imgui.Text(label2);

    -- First column
    components.DrawGradientPickerColumn(label1..idSuffix, gradient1, help1);

    imgui.SameLine(components.COLOR_COLUMN_SPACING);

    -- Second column with optional flash color
    imgui.BeginGroup();
    components.DrawGradientPickerColumn(label2..idSuffix, gradient2, help2);

    -- Add flash color picker if provided
    if flashColorTable and flashKey then
        local flashColor = ARGBToImGui(flashColorTable[flashKey]);
        if (imgui.ColorEdit4('Flash##'..label2..idSuffix, flashColor, bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar))) then
            flashColorTable[flashKey] = ImGuiToARGB(flashColor);
        end
        if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end
        if flashHelp then imgui.ShowHelp(flashHelp); end
    end
    imgui.EndGroup();
end

-- Draw a single effect column (gradient + flash color)
function components.DrawEffectColumn(label, gradientTable, gradientHelp, parentTable, flashKey, flashHelp, idSuffix)
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
function components.DrawHPEffectsRow(shared, idSuffix)
    idSuffix = idSuffix or "";

    -- Column headers
    imgui.Text("Damage Effect");
    imgui.SameLine(components.COLOR_COLUMN_SPACING);
    imgui.Text("Healing Effect");

    -- Damage column
    components.DrawEffectColumn("Damage", shared.hpDamageGradient, "Color of the trailing bar when HP decreases",
                     shared, 'hpDamageFlashColor', "Flash overlay color when taking damage", idSuffix);

    imgui.SameLine(components.COLOR_COLUMN_SPACING);

    -- Healing column
    components.DrawEffectColumn("Healing", shared.hpHealGradient, "Color of the leading bar when HP increases",
                     shared, 'hpHealFlashColor', "Flash overlay color when healing", idSuffix);
end

-- Color picker helper functions (for color settings tabs)
function components.DrawGradientPicker(label, gradientTable, helpText)
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

function components.DrawHexColorPicker(label, parentTable, key, helpText)
    if not parentTable or not parentTable[key] then return; end

    local colorValue = parentTable[key];
    local colorRGBA = HexToImGui(colorValue);

    if (imgui.ColorEdit4(label, colorRGBA, bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar))) then
        parentTable[key] = ImGuiToHex(colorRGBA);
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end

    if helpText then imgui.ShowHelp(helpText); end
end

function components.DrawThreeStepGradientPicker(label, gradientTable, helpText)
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

function components.DrawTextColorPicker(label, parentTable, key, helpText)
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
function components.DrawCheckbox(label, configKey, callback)
    if (imgui.Checkbox(label, { gConfig[configKey] })) then
        gConfig[configKey] = not gConfig[configKey];
        SaveSettingsOnly();
        if callback then callback() end
    end
end

-- Helper function for slider with deferred save
function components.DrawSlider(label, configKey, min, max, format, callback)
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
function components.DrawPartyLayoutCheckbox(label, configKey, callback)
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
function components.DrawPartyLayoutSlider(label, configKey, min, max, format, callback)
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
function components.DrawComboBox(label, currentValue, items, callback)
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
function components.DrawPartyCheckbox(partyTable, label, configKey, callback)
    local uniqueLabel = label .. '##party_' .. configKey;
    if (imgui.Checkbox(uniqueLabel, { partyTable[configKey] })) then
        partyTable[configKey] = not partyTable[configKey];
        SaveSettingsOnly();
        UpdateUserSettings();
        if callback then callback() end
    end
end

-- Helper function for per-party slider (saves to partyA/B/C table)
function components.DrawPartySlider(partyTable, label, configKey, min, max, format, callback)
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
function components.DrawPartyComboBox(partyTable, label, configKey, items, callback)
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
function components.DrawPartyComboBoxIndexed(partyTable, label, configKey, items, callback)
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
function components.DrawPartyColorPicker(partyTable, label, configKey, helpText, defaultColor)
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

return components;
