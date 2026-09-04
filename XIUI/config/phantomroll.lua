--[[
* XIUI Config Menu - Phantom Roll Settings
]]--

require('common');
require('handlers.helpers');
local components = require('config.components');
local imgui = require('imgui');

local M = {};

function M.DrawSettings()
    components.DrawCheckbox('Enabled', 'showPhantomRoll', CheckVisibility);
    imgui.ShowHelp('Show your two active Corsair Phantom Rolls as dice, with potency, time left and bust odds.');
    components.DrawHideWhenMenuOpenOptions('phantomRollHideOnMenuFocus', 'phantomRollHideMacroPalette');

    if components.CollapsingSection('Display Options##phantomRoll') then
        components.DrawCheckbox('Horizon Mode', 'phantomRollHorizonMode', UpdateUserSettings);
        imgui.ShowHelp('Use HorizonXI potency tables instead of retail. Party-job bonuses are off.');
    end

    if components.CollapsingSection('Scale & Position##phantomRoll') then
        components.DrawSlider('Scale', 'phantomRollScale', 0.5, 3.0, '%.1f');
    end
end

function M.DrawColorSettings()
    imgui.TextDisabled('No color settings for Phantom Roll.');
end

return M;
