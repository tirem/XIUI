--[[
* XIUI Config Menu - Satchel Settings
]]--

require('common');
local imgui = require('imgui');
local components = require('config.components');
local tooltips = require('modules.satchel.tooltips');

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
    imgui.ShowHelp('ESC always clears an active search first. When enabled, a second ESC closes the most recently opened Satchel window (slip viewers, pickers, alt inventories, then main). Does not close the XIUI config.');

    components.DrawCheckbox('Auto Sort Bags', 'satchelAutoSortBags');
    if HzLimitedMode then
        imgui.ShowHelp('Always keep inventory bags visually sorted in Satchel (client-side display order only).');
    else
        imgui.ShowHelp('Always keep inventory bags visually sorted in Satchel, and send server-side sort to merge stackable items. Manual Sort Bag does the same for one bag.');
    end

    if components.CollapsingSection('Layout##satchelModule') then
        components.SliderInt('Columns', gConfig, 'satchelColumns', 5, 18);
        components.SliderInt('Rows', gConfig, 'satchelRows', 5, 16);
        components.SliderInt('Cell Size', gConfig, 'satchelSlotSize', 24, 96);
        components.DrawCheckboxInverted('Hide Empty Slots', 'satchelShowEmptySlots');
    end

    if components.CollapsingSection('Tooltips##satchelModuleTooltips') then
        local font_preview = tooltips.font_display_name(gConfig.satchelTooltipFontFamily);

        imgui.SetNextItemWidth(components.CONTENT_MAX_WIDTH);
        if imgui.BeginCombo('Tooltip Font', font_preview) then
            for i = 1, #components.available_fonts do
                local font_name = components.available_fonts[i];
                local label = tooltips.font_display_name(font_name);
                local is_selected = font_name == gConfig.satchelTooltipFontFamily;
                if imgui.Selectable(label, is_selected) and not is_selected then
                    gConfig.satchelTooltipFontFamily = font_name;
                    SaveSettingsOnly();
                    tooltips.notify_font_changed();
                end
                if is_selected then
                    imgui.SetItemDefaultFocus();
                end
            end
            imgui.EndCombo();
        end
        imgui.ShowHelp('Font for Satchel item tooltips. Independent from the Global tab font.');

        local current_size = tooltips.normalize_font_size(gConfig.satchelTooltipFontSize);
        local size_preview = tooltips.label_for_font_size(current_size);

        imgui.SetNextItemWidth(components.CONTENT_MAX_WIDTH);
        if imgui.BeginCombo('Tooltip Font Size', size_preview) then
            for i = 1, #tooltips.FONT_SIZES do
                local size = tooltips.FONT_SIZES[i];
                local label = tooltips.label_for_font_size(size);
                local is_selected = size == current_size;
                if imgui.Selectable(label, is_selected) and not is_selected then
                    gConfig.satchelTooltipFontSize = size;
                    SaveSettingsOnly();
                    tooltips.notify_size_changed();
                end
                if is_selected then
                    imgui.SetItemDefaultFocus();
                end
            end
            imgui.EndCombo();
        end
        imgui.ShowHelp('Exact tooltip font size. Each size is a sharp raster font (not stretched).');

        if components.CollapsingSection('Experimental##satchelTooltipExperimental') then
            imgui.PushTextWrapPos(0);
            imgui.TextColored(
                { 0.95, 0.32, 0.32, 1.0 },
                'Features may not work as intended and can cause addon crashes.'
            );
            imgui.PopTextWrapPos();
            imgui.Spacing();

            components.DrawCheckbox('Tooltip Icons As Words', 'satchelTooltipIconsAsWords');
            imgui.ShowHelp('When enabled, inline tooltip icons (elements and item tags) are shown as colored words with row-packed layout.');
        end
    end

    if components.CollapsingSectionWarning('Reset##satchelModule', false) then
        imgui.TextWrapped('Reset satchel settings to defaults for the current profile.');
        if imgui.Button('Reset Satchel Settings') then
            gConfig.satchelColumns = 10;
            gConfig.satchelRows = 8;
            gConfig.satchelSlotSize = 40;
            gConfig.satchelShowEmptySlots = true;
            gConfig.satchelTooltipIconsAsWords = false;
            gConfig.satchelTooltipFontFamily = 'Consolas';
            gConfig.satchelTooltipFontSize = 14;
            gConfig.satchelTooltipScale = nil;
            gConfig.satchelAutoSortBags = false;
            SaveSettingsOnly();
            tooltips.notify_font_changed();
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
        components.DrawTextColorPicker('Equipped', colors, 'equippedBorderColor', 'Border color for items currently equipped from inventory or wardrobes.');
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
