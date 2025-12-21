--[[
* XIUI Config Menu - Gil Tracker Settings
* Contains settings and color settings for Gil Tracker
]]--

require('common');
require('handlers.helpers');
local components = require('config.components');
local imgui = require('imgui');
local giltracker = require('modules.giltracker');

local M = {};

-- Section: Gil Tracker Settings
function M.DrawSettings()
    components.DrawCheckbox('Enabled', 'showGilTracker', CheckVisibility);

    if components.CollapsingSection('Display Options##gilTracker') then
        components.DrawCheckbox('Show Icon', 'gilTrackerShowIcon');
        imgui.ShowHelp('Show gil icon. Disable for text-only mode.');
        components.DrawCheckbox('Icon Right', 'gilTrackerIconRight');
        imgui.ShowHelp('Position icon to the right of text (when icon enabled).');
        components.DrawCheckbox('Right Align Text', 'gilTrackerRightAlign', UpdateGilTrackerVisuals);
        imgui.ShowHelp('Right-align text so numbers anchor at the right edge.');
    end

    if components.CollapsingSection('Gil Per Hour##gilTracker') then
        components.DrawCheckbox('Show Gil/Hour', 'gilTrackerShowGilPerHour');
        imgui.ShowHelp('Display gil earned per hour below current gil amount. Resets on login.');

        -- Reset button
        if imgui.Button('Reset Tracking##gilPerHour') then
            giltracker.ResetTracking();
        end
        imgui.ShowHelp('Reset gil/hour tracking to start fresh from current gil amount.');
    end

    if components.CollapsingSection('Scale & Position##gilTracker') then
        components.DrawSlider('Scale', 'gilTrackerScale', 0.1, 3.0, '%.1f');

        imgui.Separator();
        imgui.Text('Gil Amount Offset');
        components.DrawSlider('X Offset##gilAmount', 'gilTrackerTextOffsetX', -100, 100);
        components.DrawSlider('Y Offset##gilAmount', 'gilTrackerTextOffsetY', -100, 100);

        imgui.Separator();
        imgui.Text('Gil/Hour Offset');
        components.DrawSlider('X Offset##gilPerHour', 'gilTrackerGilPerHourOffsetX', -100, 100);
        components.DrawSlider('Y Offset##gilPerHour', 'gilTrackerGilPerHourOffsetY', -100, 100);
    end

    if components.CollapsingSection('Text Settings##gilTracker') then
        components.DrawSlider('Text Size', 'gilTrackerFontSize', 8, 36);
    end
end

-- Section: Gil Tracker Color Settings
function M.DrawColorSettings()
    if components.CollapsingSection('Text Colors##gilTrackerColor') then
        components.DrawTextColorPicker("Gil Text", gConfig.colorCustomization.gilTracker, 'textColor', "Color of gil amount text");
        components.DrawTextColorPicker("Positive Gil/Hr", gConfig.colorCustomization.gilTracker, 'positiveColor', "Color when earning gil per hour");
        components.DrawTextColorPicker("Negative Gil/Hr", gConfig.colorCustomization.gilTracker, 'negativeColor', "Color when losing gil per hour");
    end
end

return M;
