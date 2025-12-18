--[[
* XIUI Config Menu - Player Bar Settings
* Contains settings and color settings for Player Bar
]]--

require('common');
require('handlers.helpers');
local components = require('config.components');
local imgui = require('imgui');

local M = {};

-- Section: Player Bar Settings
function M.DrawSettings()
    components.DrawCheckbox('Enabled', 'showPlayerBar', CheckVisibility);

    if components.CollapsingSection('Display Options##playerBar') then
        components.DrawCheckbox('Show Bookends', 'showPlayerBarBookends');
        components.DrawCheckbox('Hide During Events', 'playerBarHideDuringEvents');
        components.DrawCheckbox('Always Show MP Bar', 'alwaysShowMpBar');
        imgui.ShowHelp('Always display the MP Bar even if your current jobs cannot cast spells.');
        components.DrawCheckbox('TP Bar Flash Effects', 'playerBarTpFlashEnabled');
        imgui.ShowHelp('Flash effect when TP reaches 1000 or higher.');
    end

    if components.CollapsingSection('Scale & Position##playerBar') then
        components.DrawSlider('Scale X', 'playerBarScaleX', 0.1, 3.0, '%.1f');
        components.DrawSlider('Scale Y', 'playerBarScaleY', 0.1, 3.0, '%.1f');
    end

    if components.CollapsingSection('Text Settings##playerBar') then
        components.DrawSlider('Text Size', 'playerBarFontSize', 8, 36);

        imgui.Spacing();

        -- HP Display Mode dropdown
        components.DrawDisplayModeDropdown('HP Display##playerBar', gConfig, 'playerBarHpDisplayMode',
            'How HP is displayed: number (1234), percent (100%), number first (1234 (100%)), percent first (100% (1234)), or current/max (1234/1500).');

        -- MP Display Mode dropdown
        components.DrawDisplayModeDropdown('MP Display##playerBar', gConfig, 'playerBarMpDisplayMode',
            'How MP is displayed: number (1234), percent (100%), number first (1234 (100%)), percent first (100% (1234)), or current/max (750/1000).');
    end

    -- Text offsets section (collapsed by default)
    if components.CollapsingSection('Text Offsets##playerBar', false) then
        imgui.Text('HP Text');
        components.DrawAlignmentDropdown('Alignment##hpText', gConfig, 'playerBarHpTextAlignment');
        components.DrawSlider('X Offset##hpText', 'playerBarHpTextOffsetX', -50, 50);
        components.DrawSlider('Y Offset##hpText', 'playerBarHpTextOffsetY', -50, 50);

        imgui.Spacing();
        imgui.Text('MP Text');
        components.DrawAlignmentDropdown('Alignment##mpText', gConfig, 'playerBarMpTextAlignment');
        components.DrawSlider('X Offset##mpText', 'playerBarMpTextOffsetX', -50, 50);
        components.DrawSlider('Y Offset##mpText', 'playerBarMpTextOffsetY', -50, 50);

        imgui.Spacing();
        imgui.Text('TP Text');
        components.DrawAlignmentDropdown('Alignment##tpText', gConfig, 'playerBarTpTextAlignment');
        components.DrawSlider('X Offset##tpText', 'playerBarTpTextOffsetX', -50, 50);
        components.DrawSlider('Y Offset##tpText', 'playerBarTpTextOffsetY', -50, 50);
    end
end

-- Section: Player Bar Color Settings
function M.DrawColorSettings()
    if components.CollapsingSection('HP Bar Colors##playerBarColor') then
        components.DrawHPBarColorsRow(gConfig.colorCustomization.playerBar.hpGradient, "##playerBar");
    end

    if components.CollapsingSection('MP/TP Bar Colors##playerBarColor') then
        -- Column headers
        imgui.Text("MP Bar");
        imgui.SameLine(components.COLOR_COLUMN_SPACING);
        imgui.Text("TP Bar");
        imgui.SameLine(components.COLOR_COLUMN_SPACING * 2);
        imgui.Text("TP Overlay (1000+)");

        -- First column - MP Bar
        components.DrawGradientPickerColumn("MP Bar##playerBar", gConfig.colorCustomization.playerBar.mpGradient, "MP bar color gradient");

        imgui.SameLine(components.COLOR_COLUMN_SPACING);

        -- Second column - TP Bar
        components.DrawGradientPickerColumn("TP Bar##playerBar", gConfig.colorCustomization.playerBar.tpGradient, "TP bar color gradient");

        imgui.SameLine(components.COLOR_COLUMN_SPACING * 2);

        -- Third column - TP Overlay with flash color
        imgui.BeginGroup();
        components.DrawGradientPickerColumn("TP Overlay##playerBar", gConfig.colorCustomization.playerBar.tpOverlayGradient, "TP overlay bar color when storing TP above 1000");
        local flashColor = ARGBToImGui(gConfig.colorCustomization.playerBar.tpFlashColor);
        if (imgui.ColorEdit4('Flash##tpFlashPlayerBar', flashColor, bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar))) then
            gConfig.colorCustomization.playerBar.tpFlashColor = ImGuiToARGB(flashColor);
        end
        if (imgui.IsItemDeactivatedAfterEdit()) then SaveSettingsOnly(); end
        imgui.ShowHelp("Color to flash when TP is 1000+");
        imgui.EndGroup();
    end

    if components.CollapsingSection('Text Colors##playerBarColor') then
        components.DrawTextColorPicker("HP Text", gConfig.colorCustomization.playerBar, 'hpTextColor', "Color of HP number text");
        components.DrawTextColorPicker("MP Text", gConfig.colorCustomization.playerBar, 'mpTextColor', "Color of MP number text");
        components.DrawTextColorPicker("TP Text (Empty, <1000)", gConfig.colorCustomization.playerBar, 'tpEmptyTextColor', "Color of TP number text when below 1000");
        components.DrawTextColorPicker("TP Text (Full, >=1000)", gConfig.colorCustomization.playerBar, 'tpFullTextColor', "Color of TP number text when 1000 or higher");
    end
end

return M;
