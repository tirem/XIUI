--[[
* XIUI Config Menu - Satchel Settings
]]--

require('common');
local imgui = require('imgui');
local components = require('config.components');

local M = {};

function M.DrawSettings()
    components.DrawCheckbox('Enabled', 'showSatchelModule', CheckVisibility);

    components.DrawCheckbox('Override /satchel', 'satchelOverrideCommand');
    imgui.ShowHelp('Let XIUI handle the /satchel command (toggles this window). When off, /satchel is left for the game or other addons. /xiui satchel always works.');

    if components.CollapsingSection('Layout##satchelModule') then
        components.SliderInt('Columns', gConfig, 'satchelColumns', 4, 18);
        components.SliderInt('Rows', gConfig, 'satchelRows', 4, 16);
        components.SliderInt('Cell Size', gConfig, 'satchelSlotSize', 24, 96);
        components.DrawCheckbox('Show Empty Slots', 'satchelShowEmptySlots');
    end

    if components.CollapsingSectionWarning('Reset##satchelModule', false) then
        imgui.TextWrapped('Reset satchel settings to defaults for the current profile.');
        if imgui.Button('Reset Satchel Settings') then
            gConfig.satchelColumns = 10;
            gConfig.satchelRows = 10;
            gConfig.satchelSlotSize = 40;
            gConfig.satchelShowEmptySlots = true;
            SaveSettingsOnly();
        end
    end
end

function M.DrawColorSettings()
    imgui.TextDisabled('No color settings for Satchel module.');
end

return M;
