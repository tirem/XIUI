--[[
* XIUI Config Menu - Global Settings
* Contains settings and color settings for Global configuration
]]--

require('common');
require('handlers.helpers');
local components = require('config.components');
local statusHandler = require('handlers.statushandler');
local imgui = require('imgui');

local M = {};

-- Section: Global Settings (combines General, Font, and Bar settings)
function M.DrawSettings()
    if components.CollapsingSection('General##global') then
        components.DrawCheckbox('Lock HUD Position', 'lockPositions');

        -- Status Icon Theme
        local status_theme_paths = statusHandler.get_status_theme_paths();
        components.DrawComboBox('Status Icon Theme', gConfig.statusIconTheme, status_theme_paths, function(newValue)
            gConfig.statusIconTheme = newValue;
            SaveSettingsOnly();
            DeferredUpdateVisuals();
        end);
        imgui.ShowHelp('The folder to pull status icons from. [XIUI\\assets\\status]');

        -- Job Icon Theme
        local job_theme_paths = statusHandler.get_job_theme_paths();
        components.DrawComboBox('Job Icon Theme', gConfig.jobIconTheme, job_theme_paths, function(newValue)
            gConfig.jobIconTheme = newValue;
            SaveSettingsOnly();
            DeferredUpdateVisuals();
        end);
        imgui.ShowHelp('The folder to pull job icons from. [XIUI\\assets\\jobs]');

        components.DrawSlider('Tooltip Scale', 'tooltipScale', 0.1, 3.0, '%.2f');
        imgui.ShowHelp('Scales the size of the tooltip. Note that text may appear blured if scaled too large.');

        components.DrawCheckbox('Hide During Events', 'hideDuringEvents');
    end

    if components.CollapsingSection('Text Settings##global') then
        -- Font Family Selector
        components.DrawComboBox('Font Family', gConfig.fontFamily, components.available_fonts, function(newValue)
            gConfig.fontFamily = newValue;
            ClearDebuffFontCache();
            UpdateSettings();
        end);
        imgui.ShowHelp('The font family to use for all text in XIUI. Fonts must be installed on your system.');

        -- Font Weight Selector
        components.DrawComboBox('Font Weight', gConfig.fontWeight, {'Normal', 'Bold'}, function(newValue)
            gConfig.fontWeight = newValue;
            ClearDebuffFontCache();
            UpdateSettings();
        end);
        imgui.ShowHelp('The font weight (boldness) to use for all text in XIUI.');

        -- Font Outline Width Slider
        components.DrawSlider('Font Outline Width', 'fontOutlineWidth', 0, 5, nil, function()
            ClearDebuffFontCache();
            DeferredUpdateVisuals();
        end);
        imgui.ShowHelp('The thickness of the text outline/stroke for all text in XIUI.');
    end

    if components.CollapsingSection('Bar Settings##global') then
        -- Global bookends toggle - sets all individual module bookend settings
        if (imgui.Checkbox('Show Bookends', { gConfig.showBookends })) then
            gConfig.showBookends = not gConfig.showBookends;
            -- Update all individual module bookend settings
            gConfig.showPlayerBarBookends = gConfig.showBookends;
            gConfig.showTargetBarBookends = gConfig.showBookends;
            gConfig.showEnemyListBookends = gConfig.showBookends;
            gConfig.showExpBarBookends = gConfig.showBookends;
            gConfig.showPartyListBookends = gConfig.showBookends;
            gConfig.showCastBarBookends = gConfig.showBookends;
            gConfig.petBarShowBookends = gConfig.showBookends;
            -- Update party A/B/C settings
            if gConfig.partyA then gConfig.partyA.showBookends = gConfig.showBookends; end
            if gConfig.partyB then gConfig.partyB.showBookends = gConfig.showBookends; end
            if gConfig.partyC then gConfig.partyC.showBookends = gConfig.showBookends; end
            -- Update pet bar type settings
            if gConfig.petBarTypeSettings then
                for _, petType in pairs(gConfig.petBarTypeSettings) do
                    if petType then petType.showBookends = gConfig.showBookends; end
                end
            end
            SaveSettingsOnly();
        end
        if gConfig.showBookends then
            imgui.SameLine();
            imgui.SetNextItemWidth(100);
            components.DrawSlider('Size##bookendSize', 'bookendSize', 5, 20);
        end
        imgui.ShowHelp('Toggle bookends on/off for all bars. Individual modules can still override.');

        components.DrawCheckbox('Health Bar Flash Effects', 'healthBarFlashEnabled');
        imgui.ShowHelp('Flash effect when taking damage on health bars.');

        components.DrawSlider('Bar Roundness', 'noBookendRounding', 0, 10);
        imgui.ShowHelp('Corner roundness for bars without bookends (0 = square corners, 10 = very rounded).');

        components.DrawSlider('Bar Border Thickness', 'barBorderThickness', 0, 5);
        imgui.ShowHelp('Thickness of the border around all progress bars.');
    end
end

-- Section: Global Color Settings
function M.DrawColorSettings()
    if components.CollapsingSection('Background Color##globalColor') then
        components.DrawGradientPicker("Bar Background", gConfig.colorCustomization.shared.backgroundGradient, "Background color for all progress bars");
    end

    if components.CollapsingSection('Bookend Gradient##globalColor') then
        components.DrawThreeStepGradientPicker("Bookend", gConfig.colorCustomization.shared.bookendGradient, "3-step gradient for progress bar bookends (top -> middle -> bottom)");
    end

    if components.CollapsingSection('Entity Name Colors##globalColor') then
        components.DrawTextColorPicker("Party/Alliance Player", gConfig.colorCustomization.shared, 'playerPartyTextColor', "Color for party/alliance member names");
        components.DrawTextColorPicker("Other Player", gConfig.colorCustomization.shared, 'playerOtherTextColor', "Color for other player names");
        components.DrawTextColorPicker("NPC", gConfig.colorCustomization.shared, 'npcTextColor', "Color for NPC names");
        components.DrawTextColorPicker("Unclaimed Mob", gConfig.colorCustomization.shared, 'mobUnclaimedTextColor', "Color for unclaimed mob names");
        components.DrawTextColorPicker("Party-Claimed Mob", gConfig.colorCustomization.shared, 'mobPartyClaimedTextColor', "Color for mobs claimed by your party");
        components.DrawTextColorPicker("Other-Claimed Mob", gConfig.colorCustomization.shared, 'mobOtherClaimedTextColor', "Color for mobs claimed by others");
    end

    if components.CollapsingSection('HP Bar Effects##globalColor') then
        components.DrawHPEffectsRow(gConfig.colorCustomization.shared, "##shared");
    end
end

return M;
