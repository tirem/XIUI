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
    components.DrawCheckbox('Hide When Menu Open', 'expBarHideOnMenuFocus');
    imgui.ShowHelp('Hide this module when a game menu is open (equipment, map, etc.).');

    if components.CollapsingSection('Display Options##expBar') then
        components.DrawCheckbox('Limit Points Mode', 'expBarLimitPointsMode');
        imgui.ShowHelp('Shows Limit Points if character is set to earn Limit Points in the game.');
        components.DrawCheckbox('Inline Mode', 'expBarInlineMode');
        components.DrawCheckbox('Show Bookends', 'showExpBarBookends');
        components.DrawCheckbox('Show Text', 'expBarShowText');
        components.DrawCheckbox('Show Percent', 'expBarShowPercent');
    end

    if components.CollapsingSection('Scale & Position##expBar') then
        components.DrawSlider('Scale X', 'expBarScaleX', 0.1, 8.0, '%.2f');
        components.DrawSlider('Scale Y', 'expBarScaleY', 0.2, 3.0, '%.2f');
    end

    if components.CollapsingSection('Text Settings##expBar') then
        components.DrawSlider('Text Size', 'expBarFontSize', 8, 36);
    end

    if components.CollapsingSection('Text Positions##expBar') then
        imgui.Text('Job Text Offset');
        components.DrawSlider('X##jobTextX', 'expBarJobTextOffsetX', -200, 200);
        components.DrawSlider('Y##jobTextY', 'expBarJobTextOffsetY', -100, 100);
        imgui.Spacing();
        imgui.Text('Exp Text Offset');
        components.DrawSlider('X##expTextX', 'expBarExpTextOffsetX', -200, 200);
        components.DrawSlider('Y##expTextY', 'expBarExpTextOffsetY', -100, 100);
        imgui.Spacing();
        imgui.Text('Percent Text Offset');
        components.DrawSlider('X##percentTextX', 'expBarPercentTextOffsetX', -200, 200);
        components.DrawSlider('Y##percentTextY', 'expBarPercentTextOffsetY', -100, 100);
    end
end

-- Section: Exp Bar Color Settings
function M.DrawColorSettings()
    if components.CollapsingSection('Bar Colors##expBarColor') then
        components.DrawGradientPicker("Exp Bar", gConfig.colorCustomization.expBar.expBarGradient, "Color for EXP/Capacity/Mastery bar");
        components.DrawGradientPicker("Merit Bar", gConfig.colorCustomization.expBar.meritBarGradient, "Color for Merit/Limit Points bar");
    end

    if components.CollapsingSection('Text Colors##expBarColor') then
        components.DrawTextColorPicker("Job Text", gConfig.colorCustomization.expBar, 'jobTextColor', "Color of job level text");
        components.DrawTextColorPicker("Exp Text", gConfig.colorCustomization.expBar, 'expTextColor', "Color of experience numbers");
        components.DrawTextColorPicker("Percent Text", gConfig.colorCustomization.expBar, 'percentTextColor', "Color of percentage text");
    end
end

return M;
