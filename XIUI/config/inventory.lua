--[[
* XIUI Config Menu - Inventory Settings
* Contains settings and color settings for Inventory and Satchel trackers
]]--

require('common');
require('handlers.helpers');
local components = require('config.components');
local imgui = require('imgui');

local M = {};

-- Section: Inventory Settings (combined with tabs for Inventory/Satchel)
-- state.selectedInventoryTab: tab selection state (1=Inventory, 2=Satchel)
function M.DrawSettings(state)
    local selectedInventoryTab = state.selectedInventoryTab or 1;

    -- Tab styling colors
    local tabHeight = 24;
    local tabPadding = 12; -- Horizontal padding for text
    local gold = {0.957, 0.855, 0.592, 1.0};
    local bgMedium = {0.098, 0.090, 0.075, 1.0};
    local bgLight = {0.137, 0.125, 0.106, 1.0};
    local bgLighter = {0.176, 0.161, 0.137, 1.0};

    -- Calculate tab widths based on text size
    local invTextWidth = imgui.CalcTextSize('Inventory');
    local satchelTextWidth = imgui.CalcTextSize('Satchel');
    local invTabWidth = invTextWidth + tabPadding * 2;
    local satchelTabWidth = satchelTextWidth + tabPadding * 2;

    -- Inventory tab button
    local invPosX, invPosY = imgui.GetCursorScreenPos();
    if selectedInventoryTab == 1 then
        imgui.PushStyleColor(ImGuiCol_Button, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonActive, {0, 0, 0, 0});
    else
        imgui.PushStyleColor(ImGuiCol_Button, bgMedium);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, bgLight);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, bgLighter);
    end
    if imgui.Button('Inventory##invTab', { invTabWidth, tabHeight }) then
        selectedInventoryTab = 1;
    end
    if selectedInventoryTab == 1 then
        local draw_list = imgui.GetWindowDrawList();
        draw_list:AddRectFilled(
            {invPosX + 4, invPosY + tabHeight - 2},
            {invPosX + invTabWidth - 4, invPosY + tabHeight},
            imgui.GetColorU32(gold),
            1.0
        );
    end
    imgui.PopStyleColor(3);

    -- Satchel tab button
    imgui.SameLine();
    local satchelPosX, satchelPosY = imgui.GetCursorScreenPos();
    if selectedInventoryTab == 2 then
        imgui.PushStyleColor(ImGuiCol_Button, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonActive, {0, 0, 0, 0});
    else
        imgui.PushStyleColor(ImGuiCol_Button, bgMedium);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, bgLight);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, bgLighter);
    end
    if imgui.Button('Satchel##invTab', { satchelTabWidth, tabHeight }) then
        selectedInventoryTab = 2;
    end
    if selectedInventoryTab == 2 then
        local draw_list = imgui.GetWindowDrawList();
        draw_list:AddRectFilled(
            {satchelPosX + 4, satchelPosY + tabHeight - 2},
            {satchelPosX + satchelTabWidth - 4, satchelPosY + tabHeight},
            imgui.GetColorU32(gold),
            1.0
        );
    end
    imgui.PopStyleColor(3);

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Draw settings based on selected tab
    if selectedInventoryTab == 1 then
        -- Inventory settings
        components.DrawCheckbox('Enabled', 'showInventoryTracker', CheckVisibility);
        components.DrawCheckbox('Show Count', 'inventoryShowCount');

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

        components.DrawSlider('Scale', 'inventoryTrackerScale', 0.5, 3.0, '%.1f');
        components.DrawSlider('Font Size', 'inventoryTrackerFontSize', 8, 36);
    else
        -- Satchel settings
        components.DrawCheckbox('Enabled', 'showSatchelTracker', CheckVisibility);
        components.DrawCheckbox('Show Count', 'satchelShowCount');

        local columnCount = { gConfig.satchelTrackerColumnCount };
        if (imgui.SliderInt('Columns', columnCount, 1, 80)) then
            gConfig.satchelTrackerColumnCount = columnCount[1];
            UpdateUserSettings();
        end
        if (imgui.IsItemDeactivatedAfterEdit()) then
            SaveSettingsOnly();
        end

        local rowCount = { gConfig.satchelTrackerRowCount };
        if (imgui.SliderInt('Rows', rowCount, 1, 80)) then
            gConfig.satchelTrackerRowCount = rowCount[1];
            UpdateUserSettings();
        end
        if (imgui.IsItemDeactivatedAfterEdit()) then
            SaveSettingsOnly();
        end

        components.DrawSlider('Scale', 'satchelTrackerScale', 0.5, 3.0, '%.1f');
        components.DrawSlider('Font Size', 'satchelTrackerFontSize', 8, 36);
    end

    -- Return updated state
    return { selectedInventoryTab = selectedInventoryTab };
end

-- Section: Inventory Color Settings (combined with tabs for Inventory/Satchel)
-- state.selectedInventoryColorTab: tab selection state (1=Inventory, 2=Satchel)
function M.DrawColorSettings(state)
    local selectedInventoryColorTab = state.selectedInventoryColorTab or 1;

    -- Tab styling colors
    local tabHeight = 24;
    local tabPadding = 12; -- Horizontal padding for text
    local gold = {0.957, 0.855, 0.592, 1.0};
    local bgMedium = {0.098, 0.090, 0.075, 1.0};
    local bgLight = {0.137, 0.125, 0.106, 1.0};
    local bgLighter = {0.176, 0.161, 0.137, 1.0};

    -- Calculate tab widths based on text size
    local invTextWidth = imgui.CalcTextSize('Inventory');
    local satchelTextWidth = imgui.CalcTextSize('Satchel');
    local invTabWidth = invTextWidth + tabPadding * 2;
    local satchelTabWidth = satchelTextWidth + tabPadding * 2;

    -- Inventory tab button
    local invPosX, invPosY = imgui.GetCursorScreenPos();
    if selectedInventoryColorTab == 1 then
        imgui.PushStyleColor(ImGuiCol_Button, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonActive, {0, 0, 0, 0});
    else
        imgui.PushStyleColor(ImGuiCol_Button, bgMedium);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, bgLight);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, bgLighter);
    end
    if imgui.Button('Inventory##invColorTab', { invTabWidth, tabHeight }) then
        selectedInventoryColorTab = 1;
    end
    if selectedInventoryColorTab == 1 then
        local draw_list = imgui.GetWindowDrawList();
        draw_list:AddRectFilled(
            {invPosX + 4, invPosY + tabHeight - 2},
            {invPosX + invTabWidth - 4, invPosY + tabHeight},
            imgui.GetColorU32(gold),
            1.0
        );
    end
    imgui.PopStyleColor(3);

    -- Satchel tab button
    imgui.SameLine();
    local satchelPosX, satchelPosY = imgui.GetCursorScreenPos();
    if selectedInventoryColorTab == 2 then
        imgui.PushStyleColor(ImGuiCol_Button, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonActive, {0, 0, 0, 0});
    else
        imgui.PushStyleColor(ImGuiCol_Button, bgMedium);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, bgLight);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, bgLighter);
    end
    if imgui.Button('Satchel##invColorTab', { satchelTabWidth, tabHeight }) then
        selectedInventoryColorTab = 2;
    end
    if selectedInventoryColorTab == 2 then
        local draw_list = imgui.GetWindowDrawList();
        draw_list:AddRectFilled(
            {satchelPosX + 4, satchelPosY + tabHeight - 2},
            {satchelPosX + satchelTabWidth - 4, satchelPosY + tabHeight},
            imgui.GetColorU32(gold),
            1.0
        );
    end
    imgui.PopStyleColor(3);

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Draw color settings based on selected tab
    if selectedInventoryColorTab == 1 then
        -- Inventory color settings
        if components.CollapsingSection('Text Color##inventoryColor') then
            components.DrawTextColorPicker("Count Text", gConfig.colorCustomization.inventoryTracker, 'textColor', "Color of inventory count text");
        end

        if components.CollapsingSection('Dot Colors##inventoryColor') then
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
        end

        if components.CollapsingSection('Color Thresholds##inventoryColor') then
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
    else
        -- Satchel color settings
        if components.CollapsingSection('Text Color##satchelColor') then
            components.DrawTextColorPicker("Count Text", gConfig.colorCustomization.satchelTracker, 'textColor', "Color of satchel count text");
        end

        if components.CollapsingSection('Dot Colors##satchelColor') then
            local emptySlot = {
                gConfig.colorCustomization.satchelTracker.emptySlotColor.r,
                gConfig.colorCustomization.satchelTracker.emptySlotColor.g,
                gConfig.colorCustomization.satchelTracker.emptySlotColor.b,
                gConfig.colorCustomization.satchelTracker.emptySlotColor.a
            };
            if (imgui.ColorEdit4('Empty Slot', emptySlot, bit.bor(ImGuiColorEditFlags_AlphaBar, ImGuiColorEditFlags_NoInputs))) then
                gConfig.colorCustomization.satchelTracker.emptySlotColor.r = emptySlot[1];
                gConfig.colorCustomization.satchelTracker.emptySlotColor.g = emptySlot[2];
                gConfig.colorCustomization.satchelTracker.emptySlotColor.b = emptySlot[3];
                gConfig.colorCustomization.satchelTracker.emptySlotColor.a = emptySlot[4];
            end
            if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end
            imgui.ShowHelp('Color for empty satchel slots');

            local usedSlot = {
                gConfig.colorCustomization.satchelTracker.usedSlotColor.r,
                gConfig.colorCustomization.satchelTracker.usedSlotColor.g,
                gConfig.colorCustomization.satchelTracker.usedSlotColor.b,
                gConfig.colorCustomization.satchelTracker.usedSlotColor.a
            };
            if (imgui.ColorEdit4('Used Slot (Normal)', usedSlot, bit.bor(ImGuiColorEditFlags_AlphaBar, ImGuiColorEditFlags_NoInputs))) then
                gConfig.colorCustomization.satchelTracker.usedSlotColor.r = usedSlot[1];
                gConfig.colorCustomization.satchelTracker.usedSlotColor.g = usedSlot[2];
                gConfig.colorCustomization.satchelTracker.usedSlotColor.b = usedSlot[3];
                gConfig.colorCustomization.satchelTracker.usedSlotColor.a = usedSlot[4];
            end
            if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end
            imgui.ShowHelp('Color for used satchel slots (normal)');

            local usedSlotThreshold1 = {
                gConfig.colorCustomization.satchelTracker.usedSlotColorThreshold1.r,
                gConfig.colorCustomization.satchelTracker.usedSlotColorThreshold1.g,
                gConfig.colorCustomization.satchelTracker.usedSlotColorThreshold1.b,
                gConfig.colorCustomization.satchelTracker.usedSlotColorThreshold1.a
            };
            if (imgui.ColorEdit4('Used Slot (Warning)', usedSlotThreshold1, bit.bor(ImGuiColorEditFlags_AlphaBar, ImGuiColorEditFlags_NoInputs))) then
                gConfig.colorCustomization.satchelTracker.usedSlotColorThreshold1.r = usedSlotThreshold1[1];
                gConfig.colorCustomization.satchelTracker.usedSlotColorThreshold1.g = usedSlotThreshold1[2];
                gConfig.colorCustomization.satchelTracker.usedSlotColorThreshold1.b = usedSlotThreshold1[3];
                gConfig.colorCustomization.satchelTracker.usedSlotColorThreshold1.a = usedSlotThreshold1[4];
            end
            if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end
            imgui.ShowHelp('Color for used satchel slots when at warning threshold');

            local usedSlotThreshold2 = {
                gConfig.colorCustomization.satchelTracker.usedSlotColorThreshold2.r,
                gConfig.colorCustomization.satchelTracker.usedSlotColorThreshold2.g,
                gConfig.colorCustomization.satchelTracker.usedSlotColorThreshold2.b,
                gConfig.colorCustomization.satchelTracker.usedSlotColorThreshold2.a
            };
            if (imgui.ColorEdit4('Used Slot (Critical)', usedSlotThreshold2, bit.bor(ImGuiColorEditFlags_AlphaBar, ImGuiColorEditFlags_NoInputs))) then
                gConfig.colorCustomization.satchelTracker.usedSlotColorThreshold2.r = usedSlotThreshold2[1];
                gConfig.colorCustomization.satchelTracker.usedSlotColorThreshold2.g = usedSlotThreshold2[2];
                gConfig.colorCustomization.satchelTracker.usedSlotColorThreshold2.b = usedSlotThreshold2[3];
                gConfig.colorCustomization.satchelTracker.usedSlotColorThreshold2.a = usedSlotThreshold2[4];
            end
            if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end
            imgui.ShowHelp('Color for used satchel slots when at critical threshold');
        end

        if components.CollapsingSection('Color Thresholds##satchelColor') then
            local threshold1 = { gConfig.satchelTrackerColorThreshold1 };
            if (imgui.SliderInt('Warning Threshold', threshold1, 0, 80)) then
                gConfig.satchelTrackerColorThreshold1 = threshold1[1];
            end
            if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end
            imgui.ShowHelp('Satchel count at which dots turn to warning color');

            local threshold2 = { gConfig.satchelTrackerColorThreshold2 };
            if (imgui.SliderInt('Critical Threshold', threshold2, 0, 80)) then
                gConfig.satchelTrackerColorThreshold2 = threshold2[1];
            end
            if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end
            imgui.ShowHelp('Satchel count at which dots turn to critical color');
        end
    end

    -- Return updated state
    return { selectedInventoryColorTab = selectedInventoryColorTab };
end

return M;
