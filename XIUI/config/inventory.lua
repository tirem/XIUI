--[[
* XIUI Config Menu - Inventory Settings
* Contains settings and color settings for Inventory, Satchel, Locker, Safe, Storage, and Wardrobe trackers
]]--

require('common');
require('handlers.helpers');
local components = require('config.components');
local imgui = require('imgui');

local M = {};

-- Tab definitions for easier management
-- hasMultipleContainers: if true, show "Show Per Container" option
local TABS = {
    { id = 1, name = 'Inventory', configKey = 'showInventoryTracker', showCountKey = 'inventoryShowCount',
      showDotsKey = 'inventoryShowDots', showLabelsKey = 'inventoryShowLabels',
      textUseThresholdColorKey = 'inventoryTextUseThresholdColor',
      columnCountKey = 'inventoryTrackerColumnCount', rowCountKey = 'inventoryTrackerRowCount',
      scaleKey = 'inventoryTrackerScale', fontSizeKey = 'inventoryTrackerFontSize',
      colorKey = 'inventoryTracker', threshold1Key = 'inventoryTrackerColorThreshold1', threshold2Key = 'inventoryTrackerColorThreshold2',
      hasMultipleContainers = false },
    { id = 2, name = 'Satchel', configKey = 'showSatchelTracker', showCountKey = 'satchelShowCount',
      showDotsKey = 'satchelShowDots', showLabelsKey = 'satchelShowLabels',
      textUseThresholdColorKey = 'satchelTextUseThresholdColor',
      columnCountKey = 'satchelTrackerColumnCount', rowCountKey = 'satchelTrackerRowCount',
      scaleKey = 'satchelTrackerScale', fontSizeKey = 'satchelTrackerFontSize',
      colorKey = 'satchelTracker', threshold1Key = 'satchelTrackerColorThreshold1', threshold2Key = 'satchelTrackerColorThreshold2',
      hasMultipleContainers = false },
    { id = 3, name = 'Locker', configKey = 'showLockerTracker', showCountKey = 'lockerShowCount',
      showDotsKey = 'lockerShowDots', showLabelsKey = 'lockerShowLabels',
      textUseThresholdColorKey = 'lockerTextUseThresholdColor',
      columnCountKey = 'lockerTrackerColumnCount', rowCountKey = 'lockerTrackerRowCount',
      scaleKey = 'lockerTrackerScale', fontSizeKey = 'lockerTrackerFontSize',
      colorKey = 'lockerTracker', threshold1Key = 'lockerTrackerColorThreshold1', threshold2Key = 'lockerTrackerColorThreshold2',
      hasMultipleContainers = false },
    { id = 4, name = 'Safe', configKey = 'showSafeTracker', showCountKey = 'safeShowCount',
      showDotsKey = 'safeShowDots', showPerContainerKey = 'safeShowPerContainer', showLabelsKey = 'safeShowLabels',
      textUseThresholdColorKey = 'safeTextUseThresholdColor',
      columnCountKey = 'safeTrackerColumnCount', rowCountKey = 'safeTrackerRowCount',
      scaleKey = 'safeTrackerScale', fontSizeKey = 'safeTrackerFontSize',
      colorKey = 'safeTracker', threshold1Key = 'safeTrackerColorThreshold1', threshold2Key = 'safeTrackerColorThreshold2',
      hasMultipleContainers = true, containerLabel = 'Show Safe 1 & 2 Separately' },
    { id = 5, name = 'Storage', configKey = 'showStorageTracker', showCountKey = 'storageShowCount',
      showDotsKey = 'storageShowDots', showLabelsKey = 'storageShowLabels',
      textUseThresholdColorKey = 'storageTextUseThresholdColor',
      columnCountKey = 'storageTrackerColumnCount', rowCountKey = 'storageTrackerRowCount',
      scaleKey = 'storageTrackerScale', fontSizeKey = 'storageTrackerFontSize',
      colorKey = 'storageTracker', threshold1Key = 'storageTrackerColorThreshold1', threshold2Key = 'storageTrackerColorThreshold2',
      hasMultipleContainers = false },
    { id = 6, name = 'Wardrobe', configKey = 'showWardrobeTracker', showCountKey = 'wardrobeShowCount',
      showDotsKey = 'wardrobeShowDots', showPerContainerKey = 'wardrobeShowPerContainer', showLabelsKey = 'wardrobeShowLabels',
      textUseThresholdColorKey = 'wardrobeTextUseThresholdColor',
      columnCountKey = 'wardrobeTrackerColumnCount', rowCountKey = 'wardrobeTrackerRowCount',
      scaleKey = 'wardrobeTrackerScale', fontSizeKey = 'wardrobeTrackerFontSize',
      colorKey = 'wardrobeTracker', threshold1Key = 'wardrobeTrackerColorThreshold1', threshold2Key = 'wardrobeTrackerColorThreshold2',
      hasMultipleContainers = true, containerLabel = 'Show Each Wardrobe Separately' },
};

-- Helper function to draw a single tab button
local function DrawTabButton(tab, selectedTab, uniqueSuffix)
    local clicked = components.DrawStyledTab(tab.name, uniqueSuffix, selectedTab == tab.id);
    return clicked, tab.id;
end

-- Helper function to draw settings for a tracker
local function DrawTrackerSettings(tab)
    components.DrawCheckbox('Enabled', tab.configKey, CheckVisibility);

    if components.CollapsingSection('Display Options##' .. tab.colorKey) then
        components.DrawCheckbox('Show Dots', tab.showDotsKey);
        imgui.ShowHelp('Show dot grid for slot usage. Disable for text-only mode.');

        components.DrawCheckbox('Show Count Text', tab.showCountKey);

        if gConfig[tab.showCountKey] then
            imgui.Indent(20);
            components.DrawCheckbox('Text Uses Threshold Color', tab.textUseThresholdColorKey);
            imgui.ShowHelp('When enabled, count text changes color based on dot thresholds');
            imgui.Unindent(20);
        end

        -- Show per-container option for multi-container trackers
        if tab.hasMultipleContainers and tab.showPerContainerKey then
            components.DrawCheckbox(tab.containerLabel, tab.showPerContainerKey);
            imgui.ShowHelp('Show each container separately instead of combined totals');
        end

        -- Show labels option for all trackers
        if tab.showLabelsKey then
            components.DrawCheckbox('Show Label', tab.showLabelsKey);
            imgui.ShowHelp('Show container label (e.g., Inv, Satchel, W1, S1)');
        end
    end

    -- Only show scale/position settings if dots are enabled
    local showDots = gConfig[tab.showDotsKey];
    if showDots then
        if components.CollapsingSection('Scale & Position##' .. tab.colorKey) then
            local columnCount = { gConfig[tab.columnCountKey] };
            if (imgui.SliderInt('Columns', columnCount, 1, 80)) then
                gConfig[tab.columnCountKey] = columnCount[1];
                UpdateUserSettings();
            end
            if (imgui.IsItemDeactivatedAfterEdit()) then
                SaveSettingsOnly();
            end

            local rowCount = { gConfig[tab.rowCountKey] };
            if (imgui.SliderInt('Rows', rowCount, 1, 80)) then
                gConfig[tab.rowCountKey] = rowCount[1];
                UpdateUserSettings();
            end
            if (imgui.IsItemDeactivatedAfterEdit()) then
                SaveSettingsOnly();
            end

            components.DrawSlider('Scale', tab.scaleKey, 0.5, 3.0, '%.1f');
        end
    end

    -- Text settings only if count text is enabled
    if gConfig[tab.showCountKey] then
        if components.CollapsingSection('Text Settings##' .. tab.colorKey) then
            local fontSize = { gConfig[tab.fontSizeKey] };
            if (imgui.SliderInt('Text Size', fontSize, 8, 36)) then
                gConfig[tab.fontSizeKey] = fontSize[1];
                UpdateUserSettings();
            end
            if (imgui.IsItemDeactivatedAfterEdit()) then
                SaveSettingsOnly();
            end
        end
    end
end

-- Helper function to draw color settings for a tracker
local function DrawTrackerColorSettings(tab)
    local colorConfig = gConfig.colorCustomization[tab.colorKey];

    if components.CollapsingSection('Text Color##' .. tab.colorKey .. 'Color') then
        components.DrawTextColorPicker("Count Text", colorConfig, 'textColor', "Color of " .. tab.name:lower() .. " count text");
    end

    if components.CollapsingSection('Dot Colors##' .. tab.colorKey .. 'Color') then
        local emptySlot = {
            colorConfig.emptySlotColor.r,
            colorConfig.emptySlotColor.g,
            colorConfig.emptySlotColor.b,
            colorConfig.emptySlotColor.a
        };
        if (imgui.ColorEdit4('Empty Slot', emptySlot, bit.bor(ImGuiColorEditFlags_AlphaBar, ImGuiColorEditFlags_NoInputs))) then
            colorConfig.emptySlotColor.r = emptySlot[1];
            colorConfig.emptySlotColor.g = emptySlot[2];
            colorConfig.emptySlotColor.b = emptySlot[3];
            colorConfig.emptySlotColor.a = emptySlot[4];
        end
        if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end
        imgui.ShowHelp('Color for empty ' .. tab.name:lower() .. ' slots');

        local usedSlot = {
            colorConfig.usedSlotColor.r,
            colorConfig.usedSlotColor.g,
            colorConfig.usedSlotColor.b,
            colorConfig.usedSlotColor.a
        };
        if (imgui.ColorEdit4('Used Slot (Normal)', usedSlot, bit.bor(ImGuiColorEditFlags_AlphaBar, ImGuiColorEditFlags_NoInputs))) then
            colorConfig.usedSlotColor.r = usedSlot[1];
            colorConfig.usedSlotColor.g = usedSlot[2];
            colorConfig.usedSlotColor.b = usedSlot[3];
            colorConfig.usedSlotColor.a = usedSlot[4];
        end
        if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end
        imgui.ShowHelp('Color for used ' .. tab.name:lower() .. ' slots (normal)');

        local usedSlotThreshold1 = {
            colorConfig.usedSlotColorThreshold1.r,
            colorConfig.usedSlotColorThreshold1.g,
            colorConfig.usedSlotColorThreshold1.b,
            colorConfig.usedSlotColorThreshold1.a
        };
        if (imgui.ColorEdit4('Used Slot (Warning)', usedSlotThreshold1, bit.bor(ImGuiColorEditFlags_AlphaBar, ImGuiColorEditFlags_NoInputs))) then
            colorConfig.usedSlotColorThreshold1.r = usedSlotThreshold1[1];
            colorConfig.usedSlotColorThreshold1.g = usedSlotThreshold1[2];
            colorConfig.usedSlotColorThreshold1.b = usedSlotThreshold1[3];
            colorConfig.usedSlotColorThreshold1.a = usedSlotThreshold1[4];
        end
        if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end
        imgui.ShowHelp('Color for used ' .. tab.name:lower() .. ' slots when at warning threshold');

        local usedSlotThreshold2 = {
            colorConfig.usedSlotColorThreshold2.r,
            colorConfig.usedSlotColorThreshold2.g,
            colorConfig.usedSlotColorThreshold2.b,
            colorConfig.usedSlotColorThreshold2.a
        };
        if (imgui.ColorEdit4('Used Slot (Critical)', usedSlotThreshold2, bit.bor(ImGuiColorEditFlags_AlphaBar, ImGuiColorEditFlags_NoInputs))) then
            colorConfig.usedSlotColorThreshold2.r = usedSlotThreshold2[1];
            colorConfig.usedSlotColorThreshold2.g = usedSlotThreshold2[2];
            colorConfig.usedSlotColorThreshold2.b = usedSlotThreshold2[3];
            colorConfig.usedSlotColorThreshold2.a = usedSlotThreshold2[4];
        end
        if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end
        imgui.ShowHelp('Color for used ' .. tab.name:lower() .. ' slots when at critical threshold');
    end

    if components.CollapsingSection('Color Thresholds##' .. tab.colorKey .. 'Color') then
        local threshold1 = { gConfig[tab.threshold1Key] };
        if (imgui.SliderInt('Warning Threshold', threshold1, 0, 600)) then
            gConfig[tab.threshold1Key] = threshold1[1];
        end
        if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end
        imgui.ShowHelp(tab.name .. ' count at which dots turn to warning color');

        local threshold2 = { gConfig[tab.threshold2Key] };
        if (imgui.SliderInt('Critical Threshold', threshold2, 0, 600)) then
            gConfig[tab.threshold2Key] = threshold2[1];
        end
        if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end
        imgui.ShowHelp(tab.name .. ' count at which dots turn to critical color');
    end
end

-- Section: Inventory Settings (with tabs for all storage types)
-- state.selectedInventoryTab: tab selection state
function M.DrawSettings(state)
    local selectedInventoryTab = state.selectedInventoryTab or 1;

    -- Draw tab buttons
    for i, tab in ipairs(TABS) do
        if i > 1 then imgui.SameLine(); end
        local clicked, tabId = DrawTabButton(tab, selectedInventoryTab, 'invTab');
        if clicked then
            selectedInventoryTab = tabId;
        end
    end

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Draw settings based on selected tab
    for _, tab in ipairs(TABS) do
        if selectedInventoryTab == tab.id then
            DrawTrackerSettings(tab);
            break;
        end
    end

    -- Return updated state
    return { selectedInventoryTab = selectedInventoryTab };
end

-- Section: Inventory Color Settings (with tabs for all storage types)
-- state.selectedInventoryColorTab: tab selection state
function M.DrawColorSettings(state)
    local selectedInventoryColorTab = state.selectedInventoryColorTab or 1;

    -- Draw tab buttons
    for i, tab in ipairs(TABS) do
        if i > 1 then imgui.SameLine(); end
        local clicked, tabId = DrawTabButton(tab, selectedInventoryColorTab, 'invColorTab');
        if clicked then
            selectedInventoryColorTab = tabId;
        end
    end

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Draw color settings based on selected tab
    for _, tab in ipairs(TABS) do
        if selectedInventoryColorTab == tab.id then
            DrawTrackerColorSettings(tab);
            break;
        end
    end

    -- Return updated state
    return { selectedInventoryColorTab = selectedInventoryColorTab };
end

return M;
