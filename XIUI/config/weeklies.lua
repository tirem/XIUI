--[[
* XIUI Config Menu - Weeklies Settings
* Contains settings for Weeklies module
]]--

require('common');
require('handlers.helpers');
local components = require('config.components');
local imgui = require('imgui');

local M = {};

-- Ensure defaults exist before drawing
local function ensureDefaults()
    if gConfig.weekliesEnabled == nil then gConfig.weekliesEnabled = true; end
    if gConfig.weekliesZoneAlerts == nil then gConfig.weekliesZoneAlerts = true; end
    if gConfig.weekliesPreview == nil then gConfig.weekliesPreview = true; end
    if gConfig.weekliesBackgroundTheme == nil then gConfig.weekliesBackgroundTheme = 'Window1'; end
    if gConfig.weekliesBgScale == nil then gConfig.weekliesBgScale = 1.0; end
    if gConfig.weekliesBorderScale == nil then gConfig.weekliesBorderScale = 1.0; end
    if gConfig.weekliesBackgroundOpacity == nil then gConfig.weekliesBackgroundOpacity = 0.87; end
    if gConfig.weekliesBorderOpacity == nil then gConfig.weekliesBorderOpacity = 1.0; end
    if gConfig.weekliesTimers == nil then gConfig.weekliesTimers = {}; end
    if gConfig.weekliesTextSize == nil then gConfig.weekliesTextSize = 12; end
    if gConfig.weekliesHeaderTextSize == nil then gConfig.weekliesHeaderTextSize = 13; end
    if gConfig.weekliesZoneAlertTextSize == nil then gConfig.weekliesZoneAlertTextSize = 14; end
    if gConfig.weekliesActivityFilters == nil then gConfig.weekliesActivityFilters = {}; end
    if gConfig.weekliesZoneAlertFilters == nil then gConfig.weekliesZoneAlertFilters = {}; end
end

-- Get available background themes
local function getBackgroundThemes()
    local themes = { '-None-', 'Plain' };
    for i = 1, 8 do
        table.insert(themes, 'Window' .. i);
    end
    return themes;
end

-- Section: Weeklies Settings
function M.DrawSettings()
    ensureDefaults();

    components.DrawCheckbox('Enabled', 'weekliesEnabled', CheckVisibility);
    components.DrawCheckbox('Zone Alerts', 'weekliesZoneAlerts');
    imgui.ShowHelp('Show chat alert when entering a zone with available weekly objective');
    components.DrawCheckbox('Preview Weeklies (when config open)', 'weekliesPreview');

    if components.CollapsingSection('Display Settings', true) then
        if gConfig.weekliesEnabled then
            components.DrawSlider('Row Text Size', 'weekliesTextSize', 8, 24);
            components.DrawSlider('Header Text Size', 'weekliesHeaderTextSize', 8, 24);
            components.DrawSlider('Zone Alert Text Size', 'weekliesZoneAlertTextSize', 8, 24);
        end
    end

    if components.CollapsingSection('Activity Filters', false) then
        imgui.Text('Tracked Activities');
        for _, objective in ipairs(require('modules.weeklies.data').Objectives) do
            local filters = gConfig.weekliesActivityFilters;
            local key = tostring(objective.KeyItem.Id);
            if filters[key] == nil then
                filters[key] = true;
            end
            components.DrawPartyCheckbox(filters, objective.Name .. ' (' .. objective.Level .. ')', key);
        end

        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();

        imgui.Text('Zone Alert Activities');
        for _, objective in ipairs(require('modules.weeklies.data').Objectives) do
            local filters = gConfig.weekliesZoneAlertFilters;
            local key = tostring(objective.KeyItem.Id);
            if filters[key] == nil then
                filters[key] = true;
            end
            components.DrawPartyCheckbox(filters, objective.Name .. ' (' .. objective.Level .. ')', key);
        end
    end

    if components.CollapsingSection('Background', false) then
        -- Background theme dropdown
        local themes = getBackgroundThemes();
        local currentTheme = gConfig.weekliesBackgroundTheme;
        local themeIndex = 1;
        for i, theme in ipairs(themes) do
            if theme == currentTheme then
                themeIndex = i;
                break;
            end
        end

        if imgui.BeginCombo('Theme', currentTheme) then
            for i, theme in ipairs(themes) do
                local isSelected = (i == themeIndex);
                if imgui.Selectable(theme, isSelected) then
                    gConfig.weekliesBackgroundTheme = theme;
                    UpdateSettings(); -- Force visual update
                end
                if isSelected then
                    imgui.SetItemDefaultFocus();
                end
            end
            imgui.EndCombo();
        end
        imgui.ShowHelp('Background style theme');

        components.DrawSlider('Background Opacity', 'weekliesBackgroundOpacity', 0.0, 1.0, '%.2f');
        components.DrawSlider('Border Opacity', 'weekliesBorderOpacity', 0.0, 1.0, '%.2f');
        
        if gConfig.weekliesBackgroundTheme ~= '-None-' and gConfig.weekliesBackgroundTheme ~= 'Plain' then
             components.DrawSlider('Background Scale', 'weekliesBgScale', 0.1, 2.0, '%.2f');
             components.DrawSlider('Border Scale', 'weekliesBorderScale', 0.1, 2.0, '%.2f');
        end
    end

    if components.CollapsingSection('Timers Debug', false) then
        if imgui.Button('Reset All Timers') then
            gConfig.weekliesTimers = {};
            print('[XIUI] All weeklies timers reset.');
        end

        -- List current timers
        if gConfig.weekliesTimers then
            for name, data in pairs(gConfig.weekliesTimers) do
                imgui.Text(string.format('%s: %s', name, data.desc or 'Unknown'));
            end
        end
    end
end

-- Section: Weeklies Color Settings
function M.DrawColorSettings()
    if components.CollapsingSection('Weeklies Colors') then
        local cc = gConfig.colorCustomization.weeklies;
        if cc then
            components.DrawTextColorPicker('Missing Key Item', cc, 'keyMissingColor', 'Color when required key item is missing');
            components.DrawTextColorPicker('Have Key Item', cc, 'keyObtainedColor', 'Color when required key item is obtained');
            components.DrawTextColorPicker('Timer Ready', cc, 'timerReadyColor', 'Color when weekly objective timer is ready');
            components.DrawTextColorPicker('Timer Not Ready', cc, 'timerNotReadyColor', 'Color when weekly objective timer is still cooling down');
            components.DrawTextColorPicker('Timer Unknown', cc, 'timerUnknownColor', 'Color when timer information is unavailable');
        end
    end
end

return M;
