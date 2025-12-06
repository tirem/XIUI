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
    components.DrawSlider('Scale', 'gilTrackerScale', 0.1, 3.0, '%.1f');
    components.DrawSlider('Font Size', 'gilTrackerFontSize', 8, 36);
    components.DrawCheckbox('Right Align', 'gilTrackerRightAlign', UpdateGilTrackerVisuals);
end

-- Section: Gil Tracker Color Settings
function M.DrawColorSettings()
    imgui.Text("Text Color:");
    imgui.Separator();
    imgui.Spacing();
    components.DrawTextColorPicker("Gil Text", gConfig.colorCustomization.gilTracker, 'textColor', "Color of gil amount text");
end

return M;
