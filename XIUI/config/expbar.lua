--[[
* XIUI Config Menu - Exp Bar Settings
* Contains settings and color settings for Exp Bar
]]--

require('common');
require('handlers.helpers');
local components = require('config.components');
local imgui = require('imgui');

local M = {};

-- Section: Exp Bar Settings
function M.DrawSettings()
    components.DrawCheckbox('Enabled', 'showExpBar', CheckVisibility);
    components.DrawCheckbox('Limit Points Mode', 'expBarLimitPointsMode');
    imgui.ShowHelp('Shows Limit Points if character is set to earn Limit Points in the game.');

    components.DrawCheckbox('Inline Mode', 'expBarInlineMode');
    components.DrawCheckbox('Show Bookends', 'showExpBarBookends');
    components.DrawCheckbox('Show Text', 'expBarShowText');
    components.DrawCheckbox('Show Percent', 'expBarShowPercent');

    components.DrawSlider('Scale X', 'expBarScaleX', 0.1, 3.0, '%.2f');
    components.DrawSlider('Scale Y', 'expBarScaleY', 0.1, 3.0, '%.2f');
    components.DrawSlider('Font Size', 'expBarFontSize', 8, 36);
end

-- Section: Exp Bar Color Settings
function M.DrawColorSettings()
    if components.CollapsingSection('Bar Color##expBarColor') then
        components.DrawGradientPicker("Exp/Merit Bar", gConfig.colorCustomization.expBar.barGradient, "Color for EXP/Merit/Capacity bar");
    end

    if components.CollapsingSection('Text Colors##expBarColor') then
        components.DrawTextColorPicker("Job Text", gConfig.colorCustomization.expBar, 'jobTextColor', "Color of job level text");
        components.DrawTextColorPicker("Exp Text", gConfig.colorCustomization.expBar, 'expTextColor', "Color of experience numbers");
        components.DrawTextColorPicker("Percent Text", gConfig.colorCustomization.expBar, 'percentTextColor', "Color of percentage text");
    end
end

return M;
