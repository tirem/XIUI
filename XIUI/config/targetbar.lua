--[[
* XIUI Config Menu - Target Bar Settings
* Contains settings and color settings for Target Bar and Mob Info
]]--

require('common');
require('handlers.helpers');
local components = require('config.components');
local imgui = require('imgui');
local ffi = require('ffi');

local M = {};

-- Helper: Draw Target Bar specific settings (used in tab)
local function DrawTargetBarSettingsContent()
    components.DrawCheckbox('Enabled', 'showTargetBar', CheckVisibility);

    if components.CollapsingSection('Display Options##targetBar') then
        components.DrawCheckbox('Show Name', 'showTargetName');
        components.DrawCheckbox('Show Distance', 'showTargetDistance');
        components.DrawCheckbox('Show HP%', 'showTargetHpPercent');
        if (gConfig.showTargetHpPercent) then
            imgui.Indent(20);
            components.DrawCheckbox('Include NPCs', 'showTargetHpPercentAllTargets');
            imgui.ShowHelp('Also show HP% for NPCs, players, and other non-monster targets.');
            imgui.Unindent(20);
        end
        components.DrawCheckbox('Show Bookends', 'showTargetBarBookends');
        components.DrawCheckbox('Show Lock On', 'showTargetBarLockOnBorder');
        imgui.ShowHelp('Display the lock icon and colored border when locked on to a target.');
        if (not HzLimitedMode) then
            components.DrawCheckbox('Show Cast Bar', 'showTargetBarCastBar');
            imgui.ShowHelp('Display the enemy cast bar under the HP bar when the target is casting.');
        end
        components.DrawCheckbox('Hide During Events', 'targetBarHideDuringEvents');
        components.DrawCheckbox('Show Enemy Id', 'showEnemyId');
        imgui.ShowHelp('Display the internal ID of the monster next to its name.');

        components.DrawCheckbox('Split Target Bars', 'splitTargetOfTarget');
        imgui.ShowHelp('Separate the Target of Target bar into its own window that can be moved independently.');
    end

    if components.CollapsingSection('Scale & Font##targetBar') then
        components.DrawSlider('Scale X', 'targetBarScaleX', 0.1, 3.0, '%.1f');
        components.DrawSlider('Scale Y', 'targetBarScaleY', 0.1, 3.0, '%.1f');
        components.DrawSlider('Name Font Size', 'targetBarNameFontSize', 8, 36);
        components.DrawSlider('Distance Font Size', 'targetBarDistanceFontSize', 8, 36);
        components.DrawSlider('HP% Font Size', 'targetBarPercentFontSize', 8, 36);
    end

    -- Cast bar settings (only show if cast bar is enabled)
    if (gConfig.showTargetBarCastBar and (not HzLimitedMode)) then
        if components.CollapsingSection('Cast Bar##targetBar') then
            components.DrawSlider('Cast Font Size', 'targetBarCastFontSize', 8, 36);
            imgui.ShowHelp('Font size for enemy cast text that appears under the HP bar.');

            components.DrawSlider('Cast Bar Offset Y', 'targetBarCastBarOffsetY', 0, 50, '%.0f');
            imgui.ShowHelp('Vertical distance below the HP bar (in pixels).');
            components.DrawSlider('Cast Bar Scale X', 'targetBarCastBarScaleX', 0.1, 3.0, '%.1f');
            imgui.ShowHelp('Horizontal scale multiplier for cast bar width.');
            components.DrawSlider('Cast Bar Scale Y', 'targetBarCastBarScaleY', 0.1, 3.0, '%.1f');
            imgui.ShowHelp('Vertical scale multiplier for cast bar height.');
        end
    end

    if components.CollapsingSection('Buffs/Debuffs##targetBar') then
        components.DrawSlider('Buffs Offset Y', 'targetBarBuffsOffsetY', -20, 50, '%.0f');
        imgui.ShowHelp('Vertical offset for buffs/debuffs below the HP bar (in pixels).');

        components.DrawSlider('Icon Scale', 'targetBarIconScale', 0.1, 3.0, '%.1f');
        components.DrawSlider('Icon Font Size', 'targetBarIconFontSize', 8, 36);
    end

    -- Target of Target Bar settings (only show when split is enabled)
    if (gConfig.splitTargetOfTarget) then
        if components.CollapsingSection('Target of Target Bar##targetBar') then
            components.DrawSlider('ToT Scale X', 'totBarScaleX', 0.1, 3.0, '%.1f');
            components.DrawSlider('ToT Scale Y', 'totBarScaleY', 0.1, 3.0, '%.1f');
            components.DrawSlider('ToT Font Size', 'totBarFontSize', 8, 36);
        end
    end
end

-- Helper: Draw Mob Info specific settings (used in tab)
local function DrawMobInfoSettingsContent(githubTexture)
    components.DrawCheckbox('Enabled', 'showMobInfo', CheckVisibility);
    imgui.ShowHelp('Show mob information window when targeting monsters.');

    -- Attribution for Thorny's MobDB (on same line as Enabled)
    imgui.SameLine();
    imgui.SetCursorPosX(imgui.GetCursorPosX() + 20); -- Add some spacing

    -- Style colors for the attribution box
    local bgLight = {0.137, 0.125, 0.106, 1.0};
    local bgLighter = {0.176, 0.161, 0.137, 1.0};
    local borderDark = {0.3, 0.275, 0.235, 1.0};
    local gold = {0.957, 0.855, 0.592, 1.0};

    -- Calculate box dimensions
    local boxHeight = 20;
    local iconSize = 14;
    local iconPad = (boxHeight - iconSize) / 2;
    local textPad = 6;
    local text = 'Powered by MobDB (Thorny)';
    local textWidth = imgui.CalcTextSize(text);
    local boxWidth = iconSize + textPad * 3 + textWidth;

    local screenPosX, screenPosY = imgui.GetCursorScreenPos();
    local isHovered = imgui.IsMouseHoveringRect({screenPosX, screenPosY}, {screenPosX + boxWidth, screenPosY + boxHeight});

    -- Draw box background and outline
    local draw_list = imgui.GetWindowDrawList();
    local boxColor = isHovered and imgui.GetColorU32(bgLighter) or imgui.GetColorU32(bgLight);
    local outlineColor = imgui.GetColorU32(borderDark);
    draw_list:AddRectFilled(
        {screenPosX, screenPosY},
        {screenPosX + boxWidth, screenPosY + boxHeight},
        boxColor,
        4.0
    );
    draw_list:AddRect(
        {screenPosX, screenPosY},
        {screenPosX + boxWidth, screenPosY + boxHeight},
        outlineColor,
        4.0
    );

    -- Draw GitHub icon if loaded
    if githubTexture ~= nil and githubTexture.image ~= nil then
        draw_list:AddImage(
            tonumber(ffi.cast("uint32_t", githubTexture.image)),
            {screenPosX + textPad, screenPosY + iconPad},
            {screenPosX + textPad + iconSize, screenPosY + iconPad + iconSize},
            {0, 0}, {1, 1},
            IM_COL32_WHITE
        );
    end

    -- Draw text
    local textColor = isHovered and imgui.GetColorU32(gold) or imgui.GetColorU32({0.8, 0.8, 0.8, 1.0});
    draw_list:AddText(
        {screenPosX + textPad + iconSize + textPad, screenPosY + (boxHeight - imgui.GetTextLineHeight()) / 2},
        textColor,
        text
    );

    -- Invisible button for interaction
    imgui.InvisibleButton("mobdb_attribution_btn", { boxWidth, boxHeight });
    if imgui.IsItemHovered() then
        imgui.SetMouseCursor(ImGuiMouseCursor_Hand);
        imgui.SetTooltip('Visit MobDB repository on GitHub');
    end
    if imgui.IsItemClicked() then
        ashita.misc.open_url('https://github.com/ThornyFFXI/mobdb');
    end

    if components.CollapsingSection('Display Options##mobInfo') then
        components.DrawCheckbox('Show Level', 'mobInfoShowLevel');
        imgui.ShowHelp('Display the mob level or level range.');

        components.DrawCheckbox('Show Detection Methods', 'mobInfoShowDetection');
        imgui.ShowHelp('Show icons for how the mob detects players (sight, sound, etc.).');

        if gConfig.mobInfoShowDetection then
            imgui.Indent(20);
            components.DrawCheckbox('Show Link', 'mobInfoShowLink');
            imgui.ShowHelp('Show if the mob links with nearby mobs.');
            imgui.Unindent(20);
        end

        components.DrawCheckbox('Show Weaknesses', 'mobInfoShowWeaknesses');
        imgui.ShowHelp('Show damage types the mob is weak to (takes extra damage).');

        components.DrawCheckbox('Show Resistances', 'mobInfoShowResistances');
        imgui.ShowHelp('Show damage types the mob resists (takes reduced damage).');

        components.DrawCheckbox('Show Immunities', 'mobInfoShowImmunities');
        imgui.ShowHelp('Show status effects the mob is immune to.');

        components.DrawCheckbox('Show When No Data', 'mobInfoShowNoData');
        imgui.ShowHelp('Show the window even when no mob data is available for the current zone.');
    end

    if components.CollapsingSection('Scale & Font##mobInfo') then
        components.DrawSlider('Icon Scale', 'mobInfoIconScale', 0.5, 3.0, '%.1f');
        imgui.ShowHelp('Scale multiplier for mob info icons.');

        components.DrawSlider('Font Size', 'mobInfoFontSize', 8, 36);
        imgui.ShowHelp('Font size for level text.');
    end
end

-- Section: Target Bar Settings (with tabs for Target Bar / Mob Info)
-- state.selectedTargetBarTab: tab selection state
-- state.githubTexture: texture for GitHub icon
function M.DrawSettings(state)
    local selectedTargetBarTab = state.selectedTargetBarTab or 1;
    local githubTexture = state.githubTexture;

    -- Tab styling colors
    local tabHeight = 24;
    local tabPadding = 12;
    local gold = {0.957, 0.855, 0.592, 1.0};
    local bgMedium = {0.098, 0.090, 0.075, 1.0};
    local bgLight = {0.137, 0.125, 0.106, 1.0};
    local bgLighter = {0.176, 0.161, 0.137, 1.0};

    -- Calculate tab widths based on text size
    local targetBarTextWidth = imgui.CalcTextSize('Target Bar');
    local mobInfoTextWidth = imgui.CalcTextSize('Mob Info');
    local targetBarTabWidth = targetBarTextWidth + tabPadding * 2;
    local mobInfoTabWidth = mobInfoTextWidth + tabPadding * 2;

    -- Target Bar tab button
    local targetBarPosX, targetBarPosY = imgui.GetCursorScreenPos();
    if selectedTargetBarTab == 1 then
        imgui.PushStyleColor(ImGuiCol_Button, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonActive, {0, 0, 0, 0});
    else
        imgui.PushStyleColor(ImGuiCol_Button, bgMedium);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, bgLight);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, bgLighter);
    end
    if imgui.Button('Target Bar##targetBarTab', { targetBarTabWidth, tabHeight }) then
        selectedTargetBarTab = 1;
    end
    if selectedTargetBarTab == 1 then
        local draw_list = imgui.GetWindowDrawList();
        draw_list:AddRectFilled(
            {targetBarPosX + 4, targetBarPosY + tabHeight - 2},
            {targetBarPosX + targetBarTabWidth - 4, targetBarPosY + tabHeight},
            imgui.GetColorU32(gold),
            1.0
        );
    end
    imgui.PopStyleColor(3);

    -- Mob Info tab button
    imgui.SameLine();
    local mobInfoPosX, mobInfoPosY = imgui.GetCursorScreenPos();
    if selectedTargetBarTab == 2 then
        imgui.PushStyleColor(ImGuiCol_Button, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonActive, {0, 0, 0, 0});
    else
        imgui.PushStyleColor(ImGuiCol_Button, bgMedium);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, bgLight);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, bgLighter);
    end
    if imgui.Button('Mob Info##targetBarTab', { mobInfoTabWidth, tabHeight }) then
        selectedTargetBarTab = 2;
    end
    if selectedTargetBarTab == 2 then
        local draw_list = imgui.GetWindowDrawList();
        draw_list:AddRectFilled(
            {mobInfoPosX + 4, mobInfoPosY + tabHeight - 2},
            {mobInfoPosX + mobInfoTabWidth - 4, mobInfoPosY + tabHeight},
            imgui.GetColorU32(gold),
            1.0
        );
    end
    imgui.PopStyleColor(3);

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Draw settings based on selected tab
    if selectedTargetBarTab == 1 then
        DrawTargetBarSettingsContent();
    else
        DrawMobInfoSettingsContent(githubTexture);
    end

    -- Return updated state
    return { selectedTargetBarTab = selectedTargetBarTab };
end

-- Helper: Draw Target Bar specific color settings (used in tab)
local function DrawTargetBarColorSettingsContent()
    if components.CollapsingSection('Bar Colors##targetBarColor') then
        components.DrawGradientPicker("Target HP Bar", gConfig.colorCustomization.targetBar.hpGradient, "Target HP bar color");
        if (not HzLimitedMode) then
            components.DrawGradientPicker("Cast Bar", gConfig.colorCustomization.targetBar.castBarGradient, "Enemy cast bar color");
        end
    end

    if components.CollapsingSection('Text Colors##targetBarColor') then
        components.DrawTextColorPicker("Distance Text", gConfig.colorCustomization.targetBar, 'distanceTextColor', "Color of distance text");
        if (not HzLimitedMode) then
            components.DrawTextColorPicker("Cast Text", gConfig.colorCustomization.targetBar, 'castTextColor', "Color of enemy cast text");
        end
        imgui.ShowHelp("Target name colors are in the Global section\nHP Percent text color is set dynamically based on HP amount");
    end

    if components.CollapsingSection('Target of Target##targetBarColor') then
        components.DrawGradientPicker("ToT HP Bar", gConfig.colorCustomization.totBar.hpGradient, "Target of Target HP bar color");
        imgui.ShowHelp("ToT name text color is set dynamically based on target type");
    end
end

-- Helper: Draw Mob Info specific color settings (used in tab)
local function DrawMobInfoColorSettingsContent()
    if components.CollapsingSection('Text Colors##mobInfoColor') then
        components.DrawTextColorPicker("Level Text", gConfig.colorCustomization.mobInfo, 'levelTextColor', "Color of level text");
    end

    if components.CollapsingSection('Icon Tints##mobInfoColor') then
        components.DrawTextColorPicker("Weakness Tint", gConfig.colorCustomization.mobInfo, 'weaknessColor', "Tint color for weakness icons (green recommended)");
        components.DrawTextColorPicker("Resistance Tint", gConfig.colorCustomization.mobInfo, 'resistanceColor', "Tint color for resistance icons (red recommended)");
        components.DrawTextColorPicker("Immunity Tint", gConfig.colorCustomization.mobInfo, 'immunityColor', "Tint color for immunity icons (yellow recommended)");
    end
end

-- Section: Target Bar Color Settings (with tabs for Target Bar / Mob Info)
-- state.selectedTargetBarColorTab: tab selection state
function M.DrawColorSettings(state)
    local selectedTargetBarColorTab = state.selectedTargetBarColorTab or 1;

    -- Tab styling colors
    local tabHeight = 24;
    local tabPadding = 12;
    local gold = {0.957, 0.855, 0.592, 1.0};
    local bgMedium = {0.098, 0.090, 0.075, 1.0};
    local bgLight = {0.137, 0.125, 0.106, 1.0};
    local bgLighter = {0.176, 0.161, 0.137, 1.0};

    -- Calculate tab widths based on text size
    local targetBarTextWidth = imgui.CalcTextSize('Target Bar');
    local mobInfoTextWidth = imgui.CalcTextSize('Mob Info');
    local targetBarTabWidth = targetBarTextWidth + tabPadding * 2;
    local mobInfoTabWidth = mobInfoTextWidth + tabPadding * 2;

    -- Target Bar tab button
    local targetBarPosX, targetBarPosY = imgui.GetCursorScreenPos();
    if selectedTargetBarColorTab == 1 then
        imgui.PushStyleColor(ImGuiCol_Button, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonActive, {0, 0, 0, 0});
    else
        imgui.PushStyleColor(ImGuiCol_Button, bgMedium);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, bgLight);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, bgLighter);
    end
    if imgui.Button('Target Bar##targetBarColorTab', { targetBarTabWidth, tabHeight }) then
        selectedTargetBarColorTab = 1;
    end
    if selectedTargetBarColorTab == 1 then
        local draw_list = imgui.GetWindowDrawList();
        draw_list:AddRectFilled(
            {targetBarPosX + 4, targetBarPosY + tabHeight - 2},
            {targetBarPosX + targetBarTabWidth - 4, targetBarPosY + tabHeight},
            imgui.GetColorU32(gold),
            1.0
        );
    end
    imgui.PopStyleColor(3);

    -- Mob Info tab button
    imgui.SameLine();
    local mobInfoPosX, mobInfoPosY = imgui.GetCursorScreenPos();
    if selectedTargetBarColorTab == 2 then
        imgui.PushStyleColor(ImGuiCol_Button, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonActive, {0, 0, 0, 0});
    else
        imgui.PushStyleColor(ImGuiCol_Button, bgMedium);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, bgLight);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, bgLighter);
    end
    if imgui.Button('Mob Info##targetBarColorTab', { mobInfoTabWidth, tabHeight }) then
        selectedTargetBarColorTab = 2;
    end
    if selectedTargetBarColorTab == 2 then
        local draw_list = imgui.GetWindowDrawList();
        draw_list:AddRectFilled(
            {mobInfoPosX + 4, mobInfoPosY + tabHeight - 2},
            {mobInfoPosX + mobInfoTabWidth - 4, mobInfoPosY + tabHeight},
            imgui.GetColorU32(gold),
            1.0
        );
    end
    imgui.PopStyleColor(3);

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Draw color settings based on selected tab
    if selectedTargetBarColorTab == 1 then
        DrawTargetBarColorSettingsContent();
    else
        DrawMobInfoColorSettingsContent();
    end

    -- Return updated state
    return { selectedTargetBarColorTab = selectedTargetBarColorTab };
end

return M;
