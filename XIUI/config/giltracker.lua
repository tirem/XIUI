--[[
* XIUI Config Menu - Gil Tracker Settings
* Contains settings and color settings for Gil Tracker
]]--

require('common');
require('handlers.helpers');
local components = require('config.components');
local imgui = require('imgui');

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

    if components.CollapsingSection('Scale & Position##gilTracker') then
        components.DrawSlider('Scale', 'gilTrackerScale', 0.1, 3.0, '%.1f');
    end

    if components.CollapsingSection('Text Settings##gilTracker') then
        components.DrawSlider('Text Size', 'gilTrackerFontSize', 8, 36);
    end
end

-- Section: Gil Tracker Color Settings
function M.DrawColorSettings()
    if components.CollapsingSection('Text Colors##gilTrackerColor') then
        components.DrawTextColorPicker("Gil Text", gConfig.colorCustomization.gilTracker, 'textColor', "Color of gil amount text");
    end
end

return M;
