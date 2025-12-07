--[[
* XIUI Config Menu - Pet Bar Settings
* Contains settings and color settings for Pet Bar and Pet Target (SMN, BST, DRG, PUP)
]]--

require('common');
require('handlers.helpers');
local components = require('config.components');
local imgui = require('imgui');
local petData = require('modules.petbar.data');

local M = {};

-- Track selected avatar in config dropdown
local selectedAvatarIndex = 1;

-- Display mode options for HP text
local displayModeLabels = {
    percent = 'Percent',
    number = 'Number'
};

-- Helper: Draw Pet Bar specific settings (used in tab)
local function DrawPetBarSettingsContent()
    components.DrawCheckbox('Enabled', 'showPetBar', CheckVisibility);
    components.DrawCheckbox('Hide During Events', 'petBarHideDuringEvents');
    components.DrawCheckbox('Show Bookends', 'petBarShowBookends');

    if components.CollapsingSection('Display Options##petBar') then
        components.DrawCheckbox('Show Distance', 'petBarShowDistance');
        imgui.ShowHelp('Show distance from player to pet.');
        components.DrawCheckbox('Show Vitals (HP/MP/TP)', 'petBarShowVitals');
        imgui.ShowHelp('Show pet HP, MP, and TP bars.');
        components.DrawCheckbox('Show Ability Timers', 'petBarShowTimers');
        imgui.ShowHelp('Show pet-related ability recast timers (Blood Pact, Ready, Sic, etc.).');
        components.DrawCheckbox('Show Pet Image', 'petBarShowImage');
        imgui.ShowHelp('Show avatar/pet image overlay on the pet bar.');
    end

    if components.CollapsingSection('Background##petBar') then
        local bgThemes = {'-None-', 'Plain', 'Window1', 'Window2', 'Window3', 'Window4', 'Window5', 'Window6', 'Window7', 'Window8'};
        local currentTheme = gConfig.petBarBackgroundTheme or 'Window1';
        components.DrawComboBox('Theme##petBarBg', currentTheme, bgThemes, function(newValue)
            gConfig.petBarBackgroundTheme = newValue;
            DeferredUpdateVisuals();
        end);
        imgui.ShowHelp('Select the background window theme.');
        components.DrawSlider('Opacity##petBarBg', 'petBarBackgroundOpacity', 0.0, 1.0, '%.2f');
        imgui.ShowHelp('Opacity of the background.');
    end

    if gConfig.petBarShowImage and components.CollapsingSection('Pet Image##petBar') then
        -- Ensure petBarAvatarSettings exists
        if gConfig.petBarAvatarSettings == nil then
            gConfig.petBarAvatarSettings = T{};
        end

        -- Avatar dropdown
        local avatarList = petData.avatarList;
        local currentAvatar = avatarList[selectedAvatarIndex] or 'Carbuncle';

        if imgui.BeginCombo('Avatar##petBarAvatarSelect', currentAvatar) then
            for i, avatarName in ipairs(avatarList) do
                local isSelected = (i == selectedAvatarIndex);
                if imgui.Selectable(avatarName, isSelected) then
                    selectedAvatarIndex = i;
                end
                if isSelected then
                    imgui.SetItemDefaultFocus();
                end
            end
            imgui.EndCombo();
        end
        imgui.ShowHelp('Select an avatar to adjust its image settings.');

        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();

        -- Get settings key for current avatar
        local settingsKey = petData.GetPetSettingsKey(currentAvatar);

        -- Ensure this avatar has settings
        if gConfig.petBarAvatarSettings[settingsKey] == nil then
            gConfig.petBarAvatarSettings[settingsKey] = T{
                scale = 0.4,
                opacity = 0.3,
                offsetX = 0,
                offsetY = 0,
                clipToBackground = false,
            };
        end

        local avatarSettings = gConfig.petBarAvatarSettings[settingsKey];

        -- Scale slider
        local scaleValue = { avatarSettings.scale or 0.4 };
        if imgui.SliderFloat('Scale##petBarAvatarScale', scaleValue, 0.1, 2.0, '%.2f') then
            avatarSettings.scale = scaleValue[1];
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Scale of the avatar image overlay.');

        -- Opacity slider
        local opacityValue = { avatarSettings.opacity or 0.3 };
        if imgui.SliderFloat('Opacity##petBarAvatarOpacity', opacityValue, 0.0, 1.0, '%.2f') then
            avatarSettings.opacity = opacityValue[1];
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Opacity of the avatar image overlay.');

        -- Offset X slider
        local offsetXValue = { avatarSettings.offsetX or 0 };
        if imgui.SliderInt('Offset X##petBarAvatarOffsetX', offsetXValue, -600, 600) then
            avatarSettings.offsetX = offsetXValue[1];
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Horizontal offset for the avatar image.');

        -- Offset Y slider
        local offsetYValue = { avatarSettings.offsetY or 0 };
        if imgui.SliderInt('Offset Y##petBarAvatarOffsetY', offsetYValue, -600, 600) then
            avatarSettings.offsetY = offsetYValue[1];
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Vertical offset for the avatar image.');

        -- Clip to Background checkbox
        local clipValue = { avatarSettings.clipToBackground or false };
        if imgui.Checkbox('Clip to Background##petBarAvatarClip', clipValue) then
            avatarSettings.clipToBackground = clipValue[1];
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Clip the avatar image to the pet bar background bounds.');
    end

    if components.CollapsingSection('Bar Scale##petBar') then
        imgui.Text('HP Bar');
        components.DrawSlider('Scale X##petBarHp', 'petBarHpScaleX', 0.5, 2.0, '%.1f');
        components.DrawSlider('Scale Y##petBarHp', 'petBarHpScaleY', 0.5, 2.0, '%.1f');
        imgui.Spacing();
        imgui.Text('MP Bar');
        components.DrawSlider('Scale X##petBarMp', 'petBarMpScaleX', 0.5, 2.0, '%.1f');
        components.DrawSlider('Scale Y##petBarMp', 'petBarMpScaleY', 0.5, 2.0, '%.1f');
        imgui.Spacing();
        imgui.Text('TP Bar');
        components.DrawSlider('Scale X##petBarTp', 'petBarTpScaleX', 0.5, 2.0, '%.1f');
        components.DrawSlider('Scale Y##petBarTp', 'petBarTpScaleY', 0.5, 2.0, '%.1f');
    end

    if components.CollapsingSection('Font Sizes##petBar') then
        components.DrawSlider('Pet Name', 'petBarNameFontSize', 8, 24);
        components.DrawSlider('Distance', 'petBarDistanceFontSize', 6, 18);
        components.DrawSlider('Vitals (HP/MP/TP)', 'petBarVitalsFontSize', 6, 18);
        components.DrawSlider('Timers', 'petBarTimerFontSize', 6, 18);
    end

    if components.CollapsingSection('HP Display##petBar') then
        local hpDisplayLabel = displayModeLabels[gConfig.petBarHpDisplayMode] or 'Percent';
        components.DrawComboBox('HP Display##petBarMode', hpDisplayLabel, {'Percent', 'Number'}, function(newValue)
            if newValue == 'Percent' then
                gConfig.petBarHpDisplayMode = 'percent';
            else
                gConfig.petBarHpDisplayMode = 'number';
            end
            SaveSettingsOnly();
        end);
        imgui.ShowHelp('How pet HP is displayed on the bar.');
    end
end

-- Helper: Draw Pet Target specific settings (used in tab)
local function DrawPetTargetSettingsContent()
    components.DrawCheckbox('Show Pet Target', 'petBarShowTarget');
    imgui.ShowHelp('Show information about what the pet is targeting in a separate window.');

    if components.CollapsingSection('Display Options##petTarget') then
        components.DrawSlider('Font Size', 'petBarTargetFontSize', 6, 24);
        imgui.ShowHelp('Font size for pet target text.');
    end

    if components.CollapsingSection('Background Theme##petTarget') then
        local bgThemes = {'-None-', 'Plain', 'Window1', 'Window2', 'Window3', 'Window4', 'Window5', 'Window6', 'Window7', 'Window8'};
        local currentTheme = gConfig.petTargetBackgroundTheme or gConfig.petBarBackgroundTheme or 'Window1';
        components.DrawComboBox('Theme##petTargetBg', currentTheme, bgThemes, function(newValue)
            gConfig.petTargetBackgroundTheme = newValue;
            DeferredUpdateVisuals();
        end);
        imgui.ShowHelp('Select the background window theme for pet target. Uses Pet Bar theme by default.');
    end
end

-- Section: Pet Bar Settings (with tabs for Pet Bar / Pet Target)
-- state.selectedPetBarTab: tab selection state
function M.DrawSettings(state)
    local selectedPetBarTab = state.selectedPetBarTab or 1;

    -- Tab styling colors
    local tabHeight = 24;
    local tabPadding = 12;
    local gold = {0.957, 0.855, 0.592, 1.0};
    local bgMedium = {0.098, 0.090, 0.075, 1.0};
    local bgLight = {0.137, 0.125, 0.106, 1.0};
    local bgLighter = {0.176, 0.161, 0.137, 1.0};

    -- Calculate tab widths based on text size
    local petBarTextWidth = imgui.CalcTextSize('Pet Bar');
    local petTargetTextWidth = imgui.CalcTextSize('Pet Target');
    local petBarTabWidth = petBarTextWidth + tabPadding * 2;
    local petTargetTabWidth = petTargetTextWidth + tabPadding * 2;

    -- Pet Bar tab button
    local petBarPosX, petBarPosY = imgui.GetCursorScreenPos();
    if selectedPetBarTab == 1 then
        imgui.PushStyleColor(ImGuiCol_Button, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonActive, {0, 0, 0, 0});
    else
        imgui.PushStyleColor(ImGuiCol_Button, bgMedium);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, bgLight);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, bgLighter);
    end
    if imgui.Button('Pet Bar##petBarTab', { petBarTabWidth, tabHeight }) then
        selectedPetBarTab = 1;
    end
    if selectedPetBarTab == 1 then
        local draw_list = imgui.GetWindowDrawList();
        draw_list:AddRectFilled(
            {petBarPosX + 4, petBarPosY + tabHeight - 2},
            {petBarPosX + petBarTabWidth - 4, petBarPosY + tabHeight},
            imgui.GetColorU32(gold),
            1.0
        );
    end
    imgui.PopStyleColor(3);

    -- Pet Target tab button
    imgui.SameLine();
    local petTargetPosX, petTargetPosY = imgui.GetCursorScreenPos();
    if selectedPetBarTab == 2 then
        imgui.PushStyleColor(ImGuiCol_Button, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonActive, {0, 0, 0, 0});
    else
        imgui.PushStyleColor(ImGuiCol_Button, bgMedium);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, bgLight);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, bgLighter);
    end
    if imgui.Button('Pet Target##petBarTab', { petTargetTabWidth, tabHeight }) then
        selectedPetBarTab = 2;
    end
    if selectedPetBarTab == 2 then
        local draw_list = imgui.GetWindowDrawList();
        draw_list:AddRectFilled(
            {petTargetPosX + 4, petTargetPosY + tabHeight - 2},
            {petTargetPosX + petTargetTabWidth - 4, petTargetPosY + tabHeight},
            imgui.GetColorU32(gold),
            1.0
        );
    end
    imgui.PopStyleColor(3);

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Draw settings based on selected tab
    if selectedPetBarTab == 1 then
        DrawPetBarSettingsContent();
    else
        DrawPetTargetSettingsContent();
    end

    -- Return updated state
    return { selectedPetBarTab = selectedPetBarTab };
end

-- Helper: Draw Pet Bar specific color settings (used in tab)
local function DrawPetBarColorSettingsContent()
    -- Ensure petBar color config exists
    if gConfig.colorCustomization.petBar == nil then
        gConfig.colorCustomization.petBar = T{
            hpGradient = T{ enabled = true, start = '#e26c6c', stop = '#fa9c9c' },
            mpGradient = T{ enabled = true, start = '#9abb5a', stop = '#bfe07d' },
            tpGradient = T{ enabled = true, start = '#3898ce', stop = '#78c4ee' },
            nameTextColor = 0xFFFFFFFF,
            distanceTextColor = 0xFFFFFFFF,
            hpTextColor = 0xFFFFFFFF,
            mpTextColor = 0xFFFFFFFF,
            tpTextColor = 0xFFFFFFFF,
            targetTextColor = 0xFFFFFFFF,
            timerReadyColor = 0xFF00FF00,
            timerRecastColor = 0xFFFFFF00,
            durationWarningColor = 0xFFFF6600,
        };
    end

    if components.CollapsingSection('Bar Colors##petBarColor') then
        -- Column headers
        imgui.Text("HP Bar");
        imgui.SameLine(components.COLOR_COLUMN_SPACING);
        imgui.Text("MP Bar");
        imgui.SameLine(components.COLOR_COLUMN_SPACING * 2);
        imgui.Text("TP Bar");

        -- HP Bar
        components.DrawGradientPickerColumn("HP Bar##petBar", gConfig.colorCustomization.petBar.hpGradient, "Pet HP bar color gradient");

        imgui.SameLine(components.COLOR_COLUMN_SPACING);

        -- MP Bar
        components.DrawGradientPickerColumn("MP Bar##petBar", gConfig.colorCustomization.petBar.mpGradient, "Pet MP bar color gradient");

        imgui.SameLine(components.COLOR_COLUMN_SPACING * 2);

        -- TP Bar
        components.DrawGradientPickerColumn("TP Bar##petBar", gConfig.colorCustomization.petBar.tpGradient, "Pet TP bar color gradient");
    end

    if components.CollapsingSection('Text Colors##petBarColor') then
        components.DrawTextColorPicker("Pet Name", gConfig.colorCustomization.petBar, 'nameTextColor', "Color of pet name text");
        components.DrawTextColorPicker("Distance", gConfig.colorCustomization.petBar, 'distanceTextColor', "Color of distance text");
        components.DrawTextColorPicker("HP Text", gConfig.colorCustomization.petBar, 'hpTextColor', "Color of HP value text");
        components.DrawTextColorPicker("MP Text", gConfig.colorCustomization.petBar, 'mpTextColor', "Color of MP value text");
        components.DrawTextColorPicker("TP Text", gConfig.colorCustomization.petBar, 'tpTextColor', "Color of TP value text");
    end

    if components.CollapsingSection('Timer Colors##petBarColor') then
        components.DrawTextColorPicker("Timer Ready", gConfig.colorCustomization.petBar, 'timerReadyColor', "Color when ability is ready to use");
        components.DrawTextColorPicker("Timer Recast", gConfig.colorCustomization.petBar, 'timerRecastColor', "Color when ability is on cooldown");
        components.DrawTextColorPicker("Duration Warning", gConfig.colorCustomization.petBar, 'durationWarningColor', "Color when charm/jug is about to expire");
    end

    if components.CollapsingSection('Background Colors##petBarColor') then
        components.DrawTextColorPicker("Background Tint", gConfig.colorCustomization.petBar, 'bgColor', "Tint color for Plain background theme");
    end
end

-- Helper: Draw Pet Target specific color settings (used in tab)
local function DrawPetTargetColorSettingsContent()
    -- Ensure petTarget color config exists
    if gConfig.colorCustomization.petTarget == nil then
        gConfig.colorCustomization.petTarget = T{
            bgColor = 0xFFFFFFFF,
            targetTextColor = 0xFFFFFFFF,
        };
    end

    if components.CollapsingSection('Text Colors##petTargetColor') then
        components.DrawTextColorPicker("Target Info", gConfig.colorCustomization.petTarget, 'targetTextColor', "Color of pet target text");
    end

    if components.CollapsingSection('Background Colors##petTargetColor') then
        components.DrawTextColorPicker("Background Tint", gConfig.colorCustomization.petTarget, 'bgColor', "Tint color for Plain background theme");
    end
end

-- Section: Pet Bar Color Settings (with tabs for Pet Bar / Pet Target)
-- state.selectedPetBarColorTab: tab selection state
function M.DrawColorSettings(state)
    local selectedPetBarColorTab = state.selectedPetBarColorTab or 1;

    -- Tab styling colors
    local tabHeight = 24;
    local tabPadding = 12;
    local gold = {0.957, 0.855, 0.592, 1.0};
    local bgMedium = {0.098, 0.090, 0.075, 1.0};
    local bgLight = {0.137, 0.125, 0.106, 1.0};
    local bgLighter = {0.176, 0.161, 0.137, 1.0};

    -- Calculate tab widths based on text size
    local petBarTextWidth = imgui.CalcTextSize('Pet Bar');
    local petTargetTextWidth = imgui.CalcTextSize('Pet Target');
    local petBarTabWidth = petBarTextWidth + tabPadding * 2;
    local petTargetTabWidth = petTargetTextWidth + tabPadding * 2;

    -- Pet Bar tab button
    local petBarPosX, petBarPosY = imgui.GetCursorScreenPos();
    if selectedPetBarColorTab == 1 then
        imgui.PushStyleColor(ImGuiCol_Button, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonActive, {0, 0, 0, 0});
    else
        imgui.PushStyleColor(ImGuiCol_Button, bgMedium);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, bgLight);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, bgLighter);
    end
    if imgui.Button('Pet Bar##petBarColorTab', { petBarTabWidth, tabHeight }) then
        selectedPetBarColorTab = 1;
    end
    if selectedPetBarColorTab == 1 then
        local draw_list = imgui.GetWindowDrawList();
        draw_list:AddRectFilled(
            {petBarPosX + 4, petBarPosY + tabHeight - 2},
            {petBarPosX + petBarTabWidth - 4, petBarPosY + tabHeight},
            imgui.GetColorU32(gold),
            1.0
        );
    end
    imgui.PopStyleColor(3);

    -- Pet Target tab button
    imgui.SameLine();
    local petTargetPosX, petTargetPosY = imgui.GetCursorScreenPos();
    if selectedPetBarColorTab == 2 then
        imgui.PushStyleColor(ImGuiCol_Button, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0, 0, 0, 0});
        imgui.PushStyleColor(ImGuiCol_ButtonActive, {0, 0, 0, 0});
    else
        imgui.PushStyleColor(ImGuiCol_Button, bgMedium);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, bgLight);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, bgLighter);
    end
    if imgui.Button('Pet Target##petBarColorTab', { petTargetTabWidth, tabHeight }) then
        selectedPetBarColorTab = 2;
    end
    if selectedPetBarColorTab == 2 then
        local draw_list = imgui.GetWindowDrawList();
        draw_list:AddRectFilled(
            {petTargetPosX + 4, petTargetPosY + tabHeight - 2},
            {petTargetPosX + petTargetTabWidth - 4, petTargetPosY + tabHeight},
            imgui.GetColorU32(gold),
            1.0
        );
    end
    imgui.PopStyleColor(3);

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Draw color settings based on selected tab
    if selectedPetBarColorTab == 1 then
        DrawPetBarColorSettingsContent();
    else
        DrawPetTargetColorSettingsContent();
    end

    -- Return updated state
    return { selectedPetBarColorTab = selectedPetBarColorTab };
end

return M;
