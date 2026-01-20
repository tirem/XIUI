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

-- Position options for text elements
local positionLabels = { 'Above', 'Below', 'Left', 'Right' };

-- Helper to draw a position dropdown
local function DrawPositionDropdown(configKey, width)
    local currentPos = gConfig[configKey] or 0;
    imgui.SetNextItemWidth(width or 85);
    if imgui.BeginCombo('##' .. configKey, positionLabels[currentPos + 1]) then
        for i, label in ipairs(positionLabels) do
            local isSelected = (currentPos == i - 1);
            if imgui.Selectable(label, isSelected) then
                gConfig[configKey] = i - 1;
                SaveSettingsOnly();
            end
            if isSelected then
                imgui.SetItemDefaultFocus();
            end
        end
        imgui.EndCombo();
    end
end

-- Helper: Draw Target Bar specific settings (used in tab)
local function DrawTargetBarSettingsContent()
    components.DrawCheckbox('Enabled', 'showTargetBar', CheckVisibility);
    components.DrawCheckbox('Hide When Menu Open', 'targetBarHideOnMenuFocus');
    imgui.ShowHelp('Hide this module when a game menu is open (equipment, map, etc.).');

    if components.CollapsingSection('Display Options##targetBar') then
        -- Show Name with position dropdown
        components.DrawCheckbox('Show Name', 'showTargetName');
        if gConfig.showTargetName then
            imgui.SameLine();
            DrawPositionDropdown('targetNamePosition');
        end

        -- Show Distance with position dropdown
        components.DrawCheckbox('Show Distance', 'showTargetDistance');
        if gConfig.showTargetDistance then
            imgui.SameLine();
            DrawPositionDropdown('targetDistancePosition');
        end

        -- Show HP% with position dropdown
        components.DrawCheckbox('Show HP%', 'showTargetHpPercent');
        if gConfig.showTargetHpPercent then
            imgui.SameLine();
            DrawPositionDropdown('targetHpPercentPosition');
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
        if gConfig.showEnemyId then
            imgui.SameLine();
            components.DrawCheckbox('Convert to hex', 'showEnemyIdHex');
            imgui.ShowHelp('Converts the internal ID of the monster to hexadecimal format.');
        end

        components.DrawCheckbox('Split Target Bars', 'splitTargetOfTarget');
        imgui.ShowHelp('Separate the Target of Target bar into its own window that can be moved independently.');

    end

    if components.CollapsingSection('Scale & Position##targetBar') then
        components.DrawSlider('Scale X', 'targetBarScaleX', 0.1, 3.0, '%.1f');
        components.DrawSlider('Scale Y', 'targetBarScaleY', 0.1, 3.0, '%.1f');
    end

    if components.CollapsingSection('Text Settings##targetBar') then
        components.DrawSlider('Name Text Size', 'targetBarNameFontSize', 8, 36);
        components.DrawSlider('Distance Text Size', 'targetBarDistanceFontSize', 8, 36);
        components.DrawSlider('HP% Text Size', 'targetBarPercentFontSize', 8, 36);
    end

    if components.CollapsingSection('Text Offsets##targetBar', false) then
        imgui.Text('Distance Text');
        components.DrawSlider('X Offset##distanceText', 'targetBarDistanceOffsetX', -600, 600);
        components.DrawSlider('Y Offset##distanceText', 'targetBarDistanceOffsetY', -300, 300);

        imgui.Spacing();
        imgui.Text('HP% Text');
        components.DrawSlider('X Offset##hpPercentText', 'targetBarPercentOffsetX', -600, 600);
        components.DrawSlider('Y Offset##hpPercentText', 'targetBarPercentOffsetY', -300, 300);
    end

    -- Cast bar settings (only show if cast bar is enabled)
    if (gConfig.showTargetBarCastBar and (not HzLimitedMode)) then
        if components.CollapsingSection('Cast Bar##targetBar') then
            components.DrawSlider('Cast Bar Offset Y', 'targetBarCastBarOffsetY', 0, 50, '%.0f');
            imgui.ShowHelp('Vertical distance below the HP bar (in pixels).');
            components.DrawSlider('Cast Bar Scale X', 'targetBarCastBarScaleX', 0.1, 3.0, '%.1f');
            imgui.ShowHelp('Horizontal scale multiplier for cast bar width.');
            components.DrawSlider('Cast Bar Scale Y', 'targetBarCastBarScaleY', 0.1, 3.0, '%.1f');
            imgui.ShowHelp('Vertical scale multiplier for cast bar height.');
            components.DrawSlider('Cast Text Size', 'targetBarCastFontSize', 8, 36);
            imgui.ShowHelp('Text size for enemy cast text that appears under the HP bar.');
        end
    end

    if components.CollapsingSection('Buffs/Debuffs##targetBar') then
        components.DrawSlider('Buffs Offset Y', 'targetBarBuffsOffsetY', -20, 50, '%.0f');
        imgui.ShowHelp('Vertical offset for buffs/debuffs below the HP bar (in pixels).');
        components.DrawSlider('Icon Scale', 'targetBarIconScale', 0.1, 3.0, '%.1f');
        components.DrawSlider('Icon Text Size', 'targetBarIconFontSize', 8, 36);
    end

    -- Target of Target Bar settings (only show when split is enabled)
    if (gConfig.splitTargetOfTarget) then
        if components.CollapsingSection('Target of Target Bar##targetBar') then
            components.DrawSlider('ToT Scale X', 'totBarScaleX', 0.1, 3.0, '%.1f');
            components.DrawSlider('ToT Scale Y', 'totBarScaleY', 0.1, 3.0, '%.1f');
            components.DrawSlider('ToT Text Size', 'totBarFontSize', 8, 36);
        end
    end

end

-- Helper: Draw Subtarget Bar specific settings (used in tab)
local function DrawSubtargetBarSettingsContent()
    components.DrawCheckbox('Enabled', 'showSubtargetBar', CheckVisibility);
    imgui.ShowHelp('Shows the subtarget in a separate bar while subtargeting (e.g., /ta <stpc>).');

    if components.CollapsingSection('Display Options##subtargetBar') then
        components.DrawCheckbox('Show Distance', 'subtargetBarShowDistance');
        imgui.ShowHelp('Show distance to subtarget.');

        components.DrawCheckbox('Show HP%', 'subtargetBarShowHpPercent');
        imgui.ShowHelp('Show HP percentage of subtarget.');

        components.DrawCheckbox('Show Mob Level', 'subtargetBarShowMobLevel');
        imgui.ShowHelp('Show mob level next to name (requires Mob Info data).');

        components.DrawCheckbox('Show Bookends', 'subtargetBarShowBookends');
        imgui.ShowHelp('Use the same bookend style as the main target bar.');
    end

    if components.CollapsingSection('Scale & Position##subtargetBar') then
        components.DrawSlider('Scale X', 'subtargetBarScaleX', 0.1, 3.0, '%.1f');
        components.DrawSlider('Scale Y', 'subtargetBarScaleY', 0.1, 3.0, '%.1f');
    end

    if components.CollapsingSection('Text Settings##subtargetBar') then
        components.DrawSlider('Name Text Size', 'subtargetBarFontSize', 8, 36);
        components.DrawSlider('HP% Text Size', 'subtargetBarPercentFontSize', 8, 36);
    end
end

-- Helper: Draw Mob Info specific settings (used in tab)
local function DrawMobInfoSettingsContent(githubTexture)
    components.DrawCheckbox('Enabled', 'showMobInfo', CheckVisibility);
    components.DrawCheckbox('Hide When Menu Open', 'mobInfoHideOnMenuFocus');
    imgui.ShowHelp('Hide this module when a game menu is open (equipment, map, etc.).');

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

    components.DrawCheckbox('Snap to Target Bar', 'mobInfoSnapToTargetBar');
    imgui.ShowHelp('Position mob info directly after the target name in the target bar.');

    components.DrawCheckbox('Single Row Layout', 'mobInfoSingleRow');
    imgui.ShowHelp('Display all mob info on a single horizontal line with pipe separators.');

    if components.CollapsingSection('Display Options##mobInfo') then
        components.DrawCheckbox('Show Job', 'mobInfoShowJob');
        imgui.ShowHelp('Display the mob\'s job type (WAR, MNK, BLM, etc.).');

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

        components.DrawCheckbox('Show Modifier Percentages', 'mobInfoShowModifierText');
        imgui.ShowHelp('Show +25%/-50% text next to weakness/resistance icons.');

        if gConfig.mobInfoShowModifierText then
            imgui.Indent(20);
            components.DrawCheckbox('Group by Percentage', 'mobInfoGroupModifiers');
            imgui.ShowHelp('Group icons with the same percentage together (Wind Earth Water -25%%) vs showing each individually (Wind -25%% Earth -25%%).');
            imgui.Unindent(20);
        end

        components.DrawCheckbox('Show Server ID', 'mobInfoShowServerId');
        imgui.ShowHelp('Display the target\'s server ID.');

        if gConfig.mobInfoShowServerId then
            imgui.Indent(20);
            components.DrawCheckbox('Hex Format', 'mobInfoServerIdHex');
            imgui.ShowHelp('Show server ID in hexadecimal format (0x1C0) instead of decimal.');
            imgui.Unindent(20);
        end

        components.DrawCheckbox('Show When No Data', 'mobInfoShowNoData');
        imgui.ShowHelp('Show the window even when no mob data is available for the current zone.');

        components.DrawCheckbox('Hide When Engaged', 'mobInfoHideWhenEngaged');
        imgui.ShowHelp('Hide mob info when you are engaged in combat.');
    end

    if components.CollapsingSection('Scale & Position##mobInfo') then
        components.DrawSlider('Icon Scale', 'mobInfoIconScale', 0.5, 3.0, '%.1f');
        imgui.ShowHelp('Scale multiplier for mob info icons.');
    end

    if components.CollapsingSection('Text Settings##mobInfo') then
        components.DrawSlider('Text Size', 'mobInfoFontSize', 8, 36);
        imgui.ShowHelp('Text size for level text.');

        -- Separator style dropdown
        local separatorStyles = { 'space', 'pipe', 'dot' };
        local separatorLabels = { 'Space (none)', 'Pipe |', 'Dot \194\183' };
        local currentStyle = gConfig.mobInfoSeparatorStyle or 'space';
        local currentIndex = 1;
        for i, style in ipairs(separatorStyles) do
            if style == currentStyle then
                currentIndex = i;
                break;
            end
        end

        if imgui.BeginCombo('Separator Style', separatorLabels[currentIndex]) then
            for i, label in ipairs(separatorLabels) do
                local isSelected = (i == currentIndex);
                if imgui.Selectable(label, isSelected) then
                    gConfig.mobInfoSeparatorStyle = separatorStyles[i];
                end
                if isSelected then
                    imgui.SetItemDefaultFocus();
                end
            end
            imgui.EndCombo();
        end
        imgui.ShowHelp('Style of separator between sections in single-row mode.');
    end
end

-- Section: Target Bar Settings (with tabs for Target Bar / Subtarget Bar / Mob Info)
-- state.selectedTargetBarTab: tab selection state
-- state.githubTexture: texture for GitHub icon
function M.DrawSettings(state)
    local selectedTargetBarTab = state.selectedTargetBarTab or 1;
    local githubTexture = state.githubTexture;

    -- Target Bar tab button
    if components.DrawStyledTab('Target Bar', 'targetBarTab', selectedTargetBarTab == 1) then
        selectedTargetBarTab = 1;
    end

    -- Subtarget Bar tab button
    imgui.SameLine();
    if components.DrawStyledTab('Subtarget Bar', 'targetBarTab', selectedTargetBarTab == 2) then
        selectedTargetBarTab = 2;
    end

    -- Mob Info tab button
    imgui.SameLine();
    if components.DrawStyledTab('Mob Info', 'targetBarTab', selectedTargetBarTab == 3) then
        selectedTargetBarTab = 3;
    end

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Draw settings based on selected tab
    if selectedTargetBarTab == 1 then
        DrawTargetBarSettingsContent();
    elseif selectedTargetBarTab == 2 then
        DrawSubtargetBarSettingsContent();
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

-- Helper: Draw Subtarget Bar specific color settings (used in tab)
local function DrawSubtargetBarColorSettingsContent()
    if components.CollapsingSection('Bar Colors##subtargetBarColor') then
        components.DrawGradientPicker("HP Bar", gConfig.colorCustomization.subtargetBar.hpGradient, "Subtarget HP bar color");
    end

    if components.CollapsingSection('Text Colors##subtargetBarColor') then
        components.DrawTextColorPicker("Distance Text", gConfig.colorCustomization.subtargetBar, 'distanceTextColor', "Color of distance text");
        imgui.ShowHelp("Name text color is set dynamically based on target type\nHP% text color is set dynamically based on HP amount");
    end
end

-- Helper: Draw Mob Info specific color settings (used in tab)
local function DrawMobInfoColorSettingsContent()
    if components.CollapsingSection('Text Colors##mobInfoColor') then
        components.DrawTextColorPicker("Level Text", gConfig.colorCustomization.mobInfo, 'levelTextColor', "Color of level text");
    end
end

-- Section: Target Bar Color Settings (with tabs for Target Bar / Subtarget Bar / Mob Info)
-- state.selectedTargetBarColorTab: tab selection state
function M.DrawColorSettings(state)
    local selectedTargetBarColorTab = state.selectedTargetBarColorTab or 1;

    -- Target Bar tab button
    if components.DrawStyledTab('Target Bar', 'targetBarColorTab', selectedTargetBarColorTab == 1) then
        selectedTargetBarColorTab = 1;
    end

    -- Subtarget Bar tab button
    imgui.SameLine();
    if components.DrawStyledTab('Subtarget Bar', 'targetBarColorTab', selectedTargetBarColorTab == 2) then
        selectedTargetBarColorTab = 2;
    end

    -- Mob Info tab button
    imgui.SameLine();
    if components.DrawStyledTab('Mob Info', 'targetBarColorTab', selectedTargetBarColorTab == 3) then
        selectedTargetBarColorTab = 3;
    end

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Draw color settings based on selected tab
    if selectedTargetBarColorTab == 1 then
        DrawTargetBarColorSettingsContent();
    elseif selectedTargetBarColorTab == 2 then
        DrawSubtargetBarColorSettingsContent();
    else
        DrawMobInfoColorSettingsContent();
    end

    -- Return updated state
    return { selectedTargetBarColorTab = selectedTargetBarColorTab };
end

return M;
