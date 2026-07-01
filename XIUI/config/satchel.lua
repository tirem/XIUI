--[[
* XIUI Config Menu - Satchel Settings
]]--

require('common');
local imgui = require('imgui');
local components = require('config.components');

local M = {};

local function ensure_satchel_colors()
    if not gConfig.colorCustomization then
        return nil
    end

    if not gConfig.colorCustomization.satchelModule then
        local defaults = require('core.settings.colors');
        gConfig.colorCustomization.satchelModule =
            deep_copy_table(defaults.createColorCustomizationDefaults().satchelModule);
    end

    return gConfig.colorCustomization.satchelModule;
end

function M.DrawSettings()
    components.DrawCheckbox('Enabled', 'showSatchelModule', CheckVisibility);

    components.DrawCheckbox('Override /satchel', 'satchelOverrideCommand');
    imgui.ShowHelp('Let XIUI handle the /satchel command (toggles this window). When off, /satchel is left for the game or other addons. /xiui satchel always works.');

    components.DrawCheckbox('Close on ESC', 'satchelCloseOnEscape');
    imgui.ShowHelp('When any Satchel window is open, pressing ESC closes the most recently opened Satchel window first (slip viewers, pickers, alt inventories, then the main window). Does not close the XIUI config. Window and search state are not saved between sessions.');

    components.DrawCheckbox('Auto Sort Bags', 'satchelAutoSortBags');
    if HzLimitedMode then
        imgui.ShowHelp('Always keep inventory bags visually sorted in Satchel (client-side display order).');
    else
        imgui.ShowHelp('Always keep inventory bags visually sorted in Satchel (client-side display order). Also merges stackable items when you manually sort a bag.');
    end

    if components.CollapsingSection('Layout##satchelModule') then
        components.SliderInt('Columns', gConfig, 'satchelColumns', 5, 18);
        components.SliderInt('Rows', gConfig, 'satchelRows', 5, 16);
        components.SliderInt('Cell Size', gConfig, 'satchelSlotSize', 24, 96);
        components.DrawCheckbox('Hide Empty Slots', 'satchelHideEmptySlots');
    end

    if components.CollapsingSection('Tooltips##satchelModule') then
        components.DrawComboBox('Tooltip Font', gConfig.satchelTooltipFontFamily, components.available_tooltip_fonts, function(newValue)
            gConfig.satchelTooltipFontFamily = newValue;
            SaveSettingsOnly();
        end);
        imgui.ShowHelp('Font for Satchel item tooltips. Independent from the Global tab font. Agave matches Ashita\'s default ImGui font.');

        components.DrawSlider('Tooltip Scale', 'satchelTooltipScale', 0.1, 5.0, '%.2f');
        imgui.ShowHelp('Sharp tooltip text scaling via font size (not window stretch). 1.0 matches the 14px baseline.');

        components.DrawCheckbox('Tooltip Icons As Words', 'satchelTooltipIconsAsWords');
        imgui.ShowHelp('When enabled, inline tooltip icons (elements and item tags) are shown as colored words with row-packed layout.');
    end

    if components.CollapsingSectionWarning('Reset##satchelModule', false) then
        imgui.TextWrapped('Reset satchel settings to defaults for the current profile.');
        if imgui.Button('Reset Satchel Settings') then
            gConfig.satchelColumns = 10;
            gConfig.satchelRows = 8;
            gConfig.satchelSlotSize = 40;
            gConfig.satchelHideEmptySlots = false;
            gConfig.satchelTooltipIconsAsWords = false;
            gConfig.satchelTooltipFontFamily = 'Agave';
            gConfig.satchelTooltipScale = 1.0;
            gConfig.satchelAutoSortBags = false;
            SaveSettingsOnly();
        end
    end
end

function M.DrawColorSettings()
    local colors = ensure_satchel_colors();
    if not colors then
        imgui.TextDisabled('Color settings are unavailable.');
        return;
    end

    if components.CollapsingSection('Item Border Colors##satchelModuleColors') then
        components.DrawTextColorPicker('Empty Slot', colors, 'emptySlotBorderColor', 'Border color for empty inventory slots.');
        components.DrawTextColorPicker('Locked Slot', colors, 'lockedSlotBorderColor', 'Border color for locked or unavailable slots.');
        components.DrawTextColorPicker('Bazaar Listed', colors, 'bazaarBorderColor', 'Border color for items listed in the bazaar.');
        components.DrawTextColorPicker('Equipment', colors, 'equipmentBorderColor', 'Border color for weapons and armor.');
        components.DrawTextColorPicker('Usable', colors, 'usableBorderColor', 'Border color for usable items.');
        components.DrawTextColorPicker('Other Items', colors, 'itemBorderColor', 'Border color for all other item types.');
    end

    if components.CollapsingSection('Drag and Drop##satchelModuleDragColors') then
        components.DrawTextColorPicker('Valid Drop Highlight', colors, 'dragDropHighlightColor', 'Highlight color for valid drop targets while dragging.');
        components.DrawTextColorPicker('Valid Drop Highlight (Hovered)', colors, 'dragDropHighlightHoverColor', 'Highlight color when hovering a valid drop target while dragging.');
        components.DrawTextColorPicker('Invalid Drop Highlight', colors, 'dragDropInvalidHighlightColor', 'Highlight color for invalid drop targets while dragging.');
        components.DrawTextColorPicker('Invalid Drop Highlight (Hovered)', colors, 'dragDropInvalidHighlightHoverColor', 'Highlight color when hovering an invalid drop target while dragging.');
    end
end

return M;
