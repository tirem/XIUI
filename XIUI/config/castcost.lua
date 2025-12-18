--[[
* XIUI Config Menu - Cast Cost Settings
* Contains settings and color settings for Cast Cost display
]]--

require('common');
require('handlers.helpers');
local components = require('config.components');
local imgui = require('imgui');
local statusHandler = require('handlers.statushandler');

local M = {};

-- Section: Cast Cost Settings
function M.DrawSettings()
    components.DrawCheckbox('Enabled', 'showCastCost', CheckVisibility);

    if components.CollapsingSection('Display Options##castCost') then
        components.DrawPartyCheckbox(gConfig.castCost, 'Spell/Ability Name', 'showName');
        components.DrawPartyCheckbox(gConfig.castCost, 'MP Cost', 'showMpCost');
        components.DrawPartyCheckbox(gConfig.castCost, 'Recast Time', 'showRecast');
        components.DrawCheckbox('MP Cost Preview', 'showMpCostPreview');
        imgui.ShowHelp('Shows spell MP cost on your MP bar when hovering over spells');
        components.DrawPartyCheckbox(gConfig.castCost, 'Show Cooldown', 'showCooldown');
        imgui.ShowHelp('Shows "Next: ready" when available, or progress bar with timer when on cooldown');
    end

    if components.CollapsingSection('Scale & Position##castCost') then
        components.DrawPartySlider(gConfig.castCost, 'Bar Scale Y', 'barScaleY', 0.5, 2.0, '%.1f');
        components.DrawPartySlider(gConfig.castCost, 'Minimum Width', 'minWidth', 50, 300);
        components.DrawPartySlider(gConfig.castCost, 'Padding (Horizontal)', 'padding', 0, 20);
        components.DrawPartySlider(gConfig.castCost, 'Padding (Vertical)', 'paddingY', 0, 20);
        components.DrawPartyCheckbox(gConfig.castCost, 'Align Bottom', 'alignBottom');
        imgui.ShowHelp('When enabled, content grows upward instead of downward');
    end

    if components.CollapsingSection('Text Settings##castCost') then
        components.DrawPartySlider(gConfig.castCost, 'Name Text Size', 'nameFontSize', 8, 24);
        components.DrawPartySlider(gConfig.castCost, 'Cost Text Size', 'costFontSize', 8, 24);
        components.DrawPartySlider(gConfig.castCost, 'Recast Text Size', 'timeFontSize', 8, 24);
        components.DrawPartySlider(gConfig.castCost, 'Cooldown Timer Text Size', 'recastFontSize', 8, 24);
    end

    if components.CollapsingSection('Background##castCost') then
        -- Background theme dropdown
        local themes = statusHandler.get_background_paths();
        local currentTheme = gConfig.castCost.backgroundTheme or 'Window1';
        local themeIndex = 1;
        for i, theme in ipairs(themes) do
            if theme == currentTheme then
                themeIndex = i;
                break;
            end
        end

        if imgui.BeginCombo('Theme##castCostTheme', currentTheme) then
            for i, theme in ipairs(themes) do
                local isSelected = (theme == currentTheme);
                if imgui.Selectable(theme, isSelected) then
                    gConfig.castCost.backgroundTheme = theme;
                    UpdateCastCostVisuals();
                end
                if isSelected then
                    imgui.SetItemDefaultFocus();
                end
            end
            imgui.EndCombo();
        end

        -- Scale/opacity sliders don't need callbacks - changes are picked up from gConfig on next frame
        components.DrawPartySlider(gConfig.castCost, 'Background Scale', 'bgScale', 0.1, 3.0, '%.2f');
        components.DrawPartySlider(gConfig.castCost, 'Border Scale', 'borderScale', 0.1, 3.0, '%.2f');
        components.DrawPartySlider(gConfig.castCost, 'Background Opacity', 'backgroundOpacity', 0.0, 1.0, '%.2f');
        components.DrawPartySlider(gConfig.castCost, 'Border Opacity', 'borderOpacity', 0.0, 1.0, '%.2f');
    end
end

-- Section: Cast Cost Color Settings
function M.DrawColorSettings()
    if components.CollapsingSection('Text Colors##castCostColor') then
        components.DrawTextColorPicker("Name Text", gConfig.colorCustomization.castCost, 'nameTextColor', "Color of spell/ability name");
        components.DrawTextColorPicker("Name (On Cooldown)", gConfig.colorCustomization.castCost, 'nameOnCooldownColor', "Greyed out color when spell is on cooldown");
        components.DrawTextColorPicker("MP Cost Text", gConfig.colorCustomization.castCost, 'mpCostTextColor', "Color of MP cost display");
        components.DrawTextColorPicker("Not Enough MP", gConfig.colorCustomization.castCost, 'mpNotEnoughColor', "Color when you don't have enough MP");
        components.DrawTextColorPicker("TP Cost Text", gConfig.colorCustomization.castCost, 'tpCostTextColor', "Color of TP cost display (weapon skills)");
        components.DrawTextColorPicker("Time Text", gConfig.colorCustomization.castCost, 'timeTextColor', "Color of cast/recast time display");
    end

    if components.CollapsingSection('Cooldown##castCostColor') then
        components.DrawTextColorPicker("Ready Text", gConfig.colorCustomization.castCost, 'readyTextColor', "Color of 'Next: ready' text");
        components.DrawGradientPicker("Cooldown Bar", gConfig.colorCustomization.castCost.cooldownBarGradient, "Cooldown bar gradient (fills as spell comes off cooldown)");
        components.DrawTextColorPicker("Cooldown Timer", gConfig.colorCustomization.castCost, 'cooldownTextColor', "Color of countdown timer text on cooldown bar");
    end

    if components.CollapsingSection('MP Cost Preview##castCostColor') then
        components.DrawGradientPicker("Cost Bar", gConfig.colorCustomization.castCost.mpCostPreviewGradient, "Base gradient for the cost preview segment");
        components.DrawHexColorPicker("Flash Color", gConfig.colorCustomization.castCost, 'mpCostPreviewFlashColor', "Pulsing flash color overlay");
        components.DrawNestedSliderFloat("Pulse Speed", gConfig.colorCustomization.castCost, 'mpCostPreviewPulseSpeed', 0.1, 3.0, '%.1f', "Speed of the pulsing effect (seconds per pulse)");
    end

    if components.CollapsingSection('Background Colors##castCostColor') then
        components.DrawTextColorPicker("Background", gConfig.colorCustomization.castCost, 'bgColor', "Background tint color");
        components.DrawTextColorPicker("Border", gConfig.colorCustomization.castCost, 'borderColor', "Border tint color");
    end
end

return M;
