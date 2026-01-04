--[[
* XIUI Config Menu - Treasure Pool Settings
* Contains settings for Treasure Pool module
]]--

require('common');
require('handlers.helpers');
local components = require('config.components');
local imgui = require('imgui');
local treasurePool = require('modules.treasurepool.init');

local M = {};

-- Preview toggle callback
local function onPreviewChanged()
    treasurePool.SetPreview(gConfig.treasurePoolPreview);
    SaveSettingsOnly();
end

-- Ensure defaults exist before drawing (config may draw before module init)
local function ensureDefaults()
    if gConfig.treasurePoolEnabled == nil then gConfig.treasurePoolEnabled = true; end
    if gConfig.treasurePoolShowTimerBar == nil then gConfig.treasurePoolShowTimerBar = true; end
    if gConfig.treasurePoolShowTimerText == nil then gConfig.treasurePoolShowTimerText = true; end
    if gConfig.treasurePoolShowLots == nil then gConfig.treasurePoolShowLots = true; end
    -- Font size MUST be valid (slider min is 8)
    if gConfig.treasurePoolFontSize == nil or gConfig.treasurePoolFontSize < 8 then
        gConfig.treasurePoolFontSize = 10;
    end
    if gConfig.treasurePoolScaleX == nil or gConfig.treasurePoolScaleX < 0.5 then
        gConfig.treasurePoolScaleX = 1.0;
    end
    if gConfig.treasurePoolScaleY == nil or gConfig.treasurePoolScaleY < 0.5 then
        gConfig.treasurePoolScaleY = 1.0;
    end
    -- Split background/border settings (like petbar)
    if gConfig.treasurePoolBgScale == nil or gConfig.treasurePoolBgScale < 0.1 then
        gConfig.treasurePoolBgScale = 1.0;
    end
    if gConfig.treasurePoolBorderScale == nil or gConfig.treasurePoolBorderScale < 0.1 then
        gConfig.treasurePoolBorderScale = 1.0;
    end
    if gConfig.treasurePoolBackgroundOpacity == nil then gConfig.treasurePoolBackgroundOpacity = 0.87; end
    if gConfig.treasurePoolBorderOpacity == nil then gConfig.treasurePoolBorderOpacity = 1.0; end
    if gConfig.treasurePoolBackgroundTheme == nil then gConfig.treasurePoolBackgroundTheme = 'Plain'; end
    if gConfig.treasurePoolExpanded == nil then gConfig.treasurePoolExpanded = false; end
    if gConfig.treasurePoolShowButtonsInCollapsed == nil then gConfig.treasurePoolShowButtonsInCollapsed = true; end
end

-- Get available background themes
local function getBackgroundThemes()
    local themes = { '-None-', 'Plain' };
    for i = 1, 8 do
        table.insert(themes, 'Window' .. i);
    end
    return themes;
end

-- Section: Treasure Pool Settings
function M.DrawSettings()
    -- Ensure defaults before drawing sliders
    ensureDefaults();

    components.DrawCheckbox('Enabled', 'treasurePoolEnabled', CheckVisibility);
    components.DrawCheckbox('Preview', 'treasurePoolPreview', onPreviewChanged);

    if components.CollapsingSection('Display Settings', true) then
        if gConfig.treasurePoolEnabled then
            components.DrawCheckbox('Show Timer Bar', 'treasurePoolShowTimerBar');
            imgui.ShowHelp('Show countdown progress bar on pool items');

            components.DrawCheckbox('Show Timer Text', 'treasurePoolShowTimerText');
            imgui.ShowHelp('Show timer text (countdown like "4:32")');

            components.DrawCheckbox('Show Lots', 'treasurePoolShowLots');
            imgui.ShowHelp('Show winning lot info');

            components.DrawCheckbox('Show Buttons In Collapsed View', 'treasurePoolShowButtonsInCollapsed');
            imgui.ShowHelp('Show Lot/Pass buttons even when not in expanded view');

            components.DrawCheckbox('Start Expanded', 'treasurePoolExpanded');
            imgui.ShowHelp('Start with expanded view showing all lot details');

            -- Size settings
            components.DrawSlider('Text Size', 'treasurePoolFontSize', 8, 16);
            imgui.ShowHelp('Font size for item names, timers, and lot info');
            components.DrawSlider('Scale X', 'treasurePoolScaleX', 0.5, 2.0, '%.1f');
            imgui.ShowHelp('Horizontal scale factor');
            components.DrawSlider('Scale Y', 'treasurePoolScaleY', 0.5, 2.0, '%.1f');
            imgui.ShowHelp('Vertical scale factor');
        end
    end

    if components.CollapsingSection('Background', false) then
        -- Background theme dropdown
        local themes = getBackgroundThemes();
        local currentTheme = gConfig.treasurePoolBackgroundTheme or 'Plain';
        if imgui.BeginCombo('Theme##treasurePoolBg', currentTheme) then
            for _, theme in ipairs(themes) do
                local isSelected = (theme == currentTheme);
                if imgui.Selectable(theme, isSelected) then
                    gConfig.treasurePoolBackgroundTheme = theme;
                    UpdateSettings();
                end
                if isSelected then
                    imgui.SetItemDefaultFocus();
                end
            end
            imgui.EndCombo();
        end
        imgui.ShowHelp('Window background style (Plain = solid, Window1-8 = themed with borders)');

        -- Scale/opacity sliders
        components.DrawSlider('Background Scale##treasurePool', 'treasurePoolBgScale', 0.1, 3.0, '%.2f');
        imgui.ShowHelp('Scale of the background texture.');
        components.DrawSlider('Border Scale##treasurePool', 'treasurePoolBorderScale', 0.1, 3.0, '%.2f');
        imgui.ShowHelp('Scale of the window borders (Window themes only).');
        components.DrawSlider('Background Opacity##treasurePool', 'treasurePoolBackgroundOpacity', 0.0, 1.0, '%.2f');
        imgui.ShowHelp('Opacity of the background.');
        components.DrawSlider('Border Opacity##treasurePool', 'treasurePoolBorderOpacity', 0.0, 1.0, '%.2f');
        imgui.ShowHelp('Opacity of the window borders (Window themes only).');
    end

    if components.CollapsingSection('Chat Commands##treasurepool') then
        imgui.BulletText('/xiui lotall - Lot on all items');
        imgui.BulletText('/xiui passall - Pass on all items');
    end
end

-- Section: Treasure Pool Color Settings
function M.DrawColorSettings()
    if components.CollapsingSection('Treasure Pool Colors') then
        imgui.TextDisabled('Color settings coming soon');
    end
end

return M;
