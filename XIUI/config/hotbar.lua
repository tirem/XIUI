--[[
* XIUI Config Menu - Hotbar Settings
* Contains settings and color settings for Hotbar
]]--

require('common');
require('handlers.helpers');
local components = require('config.components');
local statusHandler = require('handlers.statushandler');
local imgui = require('imgui');

local M = {};

-- Section: Hotbar Settings
function M.DrawSettings()
    components.DrawCheckbox('Enabled', 'hotbarEnabled');
    components.DrawCheckbox('Preview Hotbar (when config open)', 'hotbarPreview');

    if components.CollapsingSection('Background##hotbar') then
        local bg_theme_paths = statusHandler.get_background_paths();
        components.DrawComboBox('Background', gConfig.hotbarBackgroundTheme, bg_theme_paths, function(newValue)
            gConfig.hotbarBackgroundTheme = newValue;
            SaveSettingsOnly();
            DeferredUpdateVisuals();
        end);
        imgui.ShowHelp('The background theme for the hotbar window.');
        
        components.DrawSlider('Background Scale', 'hotbarBgScale', 0.1, 3.0, '%.2f');
        imgui.ShowHelp('Scale of the background texture.');
        
        components.DrawSlider('Border Scale', 'hotbarBorderScale', 0.1, 3.0, '%.2f');
        imgui.ShowHelp('Scale of the border textures (Window themes only).');
        
        components.DrawSlider('Background Opacity', 'hotbarBackgroundOpacity', 0.0, 1.0, '%.2f');
        imgui.ShowHelp('Opacity of the background.');
        
        components.DrawSlider('Border Opacity', 'hotbarBorderOpacity', 0.0, 1.0, '%.2f');
        imgui.ShowHelp('Opacity of the window borders (Window themes only).');
    end

    if components.CollapsingSection('Scale##hotbar') then
        components.DrawSlider('Scale X', 'hotbarScaleX', 0.1, 3.0, '%.2f');
        imgui.ShowHelp('Horizontal scale of the hotbar.');
        
        components.DrawSlider('Scale Y', 'hotbarScaleY', 0.1, 3.0, '%.2f');
        imgui.ShowHelp('Vertical scale of the hotbar.');
    end

    if components.CollapsingSection('Text Settings##hotbar') then
        components.DrawSlider('Font Size', 'hotbarFontSize', 8, 36);
        imgui.ShowHelp('Font size for hotbar text.');
    end
end

-- Section: Hotbar Color Settings
function M.DrawColorSettings()
    if components.CollapsingSection('Background Colors##hotbarColor') then
        -- Add color customization here when needed
        imgui.Text('Color settings coming soon...');
    end
end

return M;
