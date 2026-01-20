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
    components.DrawCheckbox('Hide When Menu Open', 'gilTrackerHideOnMenuFocus');
    imgui.ShowHelp('Hide this module when a game menu is open (equipment, map, etc.).');

    if components.CollapsingSection('Display Options##gilTracker') then
        components.DrawCheckbox('Show Icon', 'gilTrackerShowIcon');
        imgui.ShowHelp('Show gil icon. Disable for text-only mode.');
        components.DrawCheckbox('Icon Right', 'gilTrackerIconRight');
        imgui.ShowHelp('Position icon to the right of text (when icon enabled).');
        components.DrawCheckbox('Right Align Text', 'gilTrackerRightAlign', UpdateGilTrackerVisuals);
        imgui.ShowHelp('Right-align text so numbers anchor at the right edge.');
    end

    if components.CollapsingSection('Session Tracking##gilTracker') then
        components.DrawCheckbox('Show Tracking', 'gilTrackerShowGilPerHour');
        imgui.ShowHelp('Display session tracking below current gil amount. Resets on login.');

        -- Display mode dropdown
        local displayModes = { 'Session Net', 'Gil Per Hour' };
        local currentMode = gConfig.gilTrackerDisplayMode or 1;
        if imgui.BeginCombo('Display Mode##gilTracker', displayModes[currentMode]) then
            for i, mode in ipairs(displayModes) do
                if imgui.Selectable(mode, currentMode == i) then
                    gConfig.gilTrackerDisplayMode = i;
                    giltracker.InvalidateCache();  -- Force immediate update
                    SaveSettingsOnly();
                end
            end
            imgui.EndCombo();
        end
        imgui.ShowHelp('Session Net: Shows total gil gained/lost this session.\nGil Per Hour: Shows rate of gil gain/loss per hour.');

        -- Reset button
        if imgui.Button('Reset Tracking##gilTracker') then
            giltracker.ResetTracking();
        end
        imgui.ShowHelp('Reset tracking to start fresh from current gil amount.');
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
        components.DrawTextColorPicker("Positive Change", gConfig.colorCustomization.gilTracker, 'positiveColor', "Color when gaining gil");
        components.DrawTextColorPicker("Negative Change", gConfig.colorCustomization.gilTracker, 'negativeColor', "Color when losing gil");
    end
end

return M;
