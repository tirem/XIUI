--[[
* XIUI Config Menu - Cast Bar Settings
* Contains settings and color settings for Cast Bar
]]--

require('common');
require('handlers.helpers');
local components = require('config.components');
local imgui = require('imgui');

local M = {};

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
function M.DrawSettings()
    components.DrawCheckbox('Enabled', 'showCastBar', CheckVisibility);

    if components.CollapsingSection('Display Options##castBar') then
        components.DrawCheckbox('Show Bookends', 'showCastBarBookends');
    end

    if components.CollapsingSection('Scale & Position##castBar') then
        components.DrawSlider('Scale X', 'castBarScaleX', 0.1, 3.0, '%.1f');
        components.DrawSlider('Scale Y', 'castBarScaleY', 0.1, 3.0, '%.1f');
    end

    if components.CollapsingSection('Text Settings##castBar') then
        components.DrawSlider('Text Size', 'castBarFontSize', 8, 36);
    end

    if components.CollapsingSection('Fast Cast Settings##castBar') then
        components.DrawCheckbox('Enable Fast Cast / True Display', 'castBarFastCastEnabled');

        if gConfig.castBarFastCastEnabled then
            imgui.Spacing();
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

            imgui.Spacing();
            imgui.Text('Per-Job Fast Cast:');
            -- Job-specific fast cast sliders (using helper function)
            local jobs = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM', 'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP', 'DNC', 'SCH', 'GEO', 'RUN' };
            for i = 1, #jobs do
                DrawFastCastSlider(jobs[i], i);
            end
        end
    end
end

-- Section: Cast Bar Color Settings
function M.DrawColorSettings()
    if components.CollapsingSection('Bar Color##castBarColor') then
        components.DrawGradientPicker("Cast Bar", gConfig.colorCustomization.castBar.barGradient, "Color of casting progress bar");
    end

    if components.CollapsingSection('Text Colors##castBarColor') then
        components.DrawTextColorPicker("Spell Text", gConfig.colorCustomization.castBar, 'spellTextColor', "Color of spell/ability name");
        components.DrawTextColorPicker("Percent Text", gConfig.colorCustomization.castBar, 'percentTextColor', "Color of cast percentage");
    end
end

return M;
