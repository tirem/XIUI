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

-- Helper: Draw Pet Bar specific settings (used in tab)
local function DrawPetBarSettingsContent()
    components.DrawCheckbox('Enabled', 'showPetBar', CheckVisibility);
    components.DrawCheckbox('Hide During Events', 'petBarHideDuringEvents');
    components.DrawCheckbox('Show Bookends', 'petBarShowBookends');
    components.DrawCheckbox('Preview Mode', 'petBarPreview');
    imgui.ShowHelp('Show a preview of the pet bar with mock data. Use the dropdown below to select pet type.');

    -- Preview type selector (only shown when preview mode is enabled)
    if gConfig.petBarPreview then
        local previewTypes = {'Wyvern (DRG)', 'Avatar (SMN)', 'Automaton (PUP)', 'Jug Pet (BST)', 'Charmed Pet (BST)'};
        local currentType = gConfig.petBarPreviewType or petData.PREVIEW_AVATAR;
        local currentTypeName = previewTypes[currentType] or 'Avatar (SMN)';
        components.DrawComboBox('Preview Type##petBarPreviewType', currentTypeName, previewTypes, function(newValue)
            for i, name in ipairs(previewTypes) do
                if name == newValue then
                    gConfig.petBarPreviewType = i;
                    break;
                end
            end
            SaveSettingsOnly();
        end);
        imgui.ShowHelp('Select which type of pet to preview.');
    end

    if components.CollapsingSection('Display Options##petBar') then
        components.DrawCheckbox('Show Distance', 'petBarShowDistance');
        imgui.ShowHelp('Show distance from player to pet.');
        components.DrawCheckbox('Show Vitals (HP/MP/TP)', 'petBarShowVitals');
        imgui.ShowHelp('Show pet HP, MP, and TP bars.');
        components.DrawCheckbox('Show Ability Timers', 'petBarShowTimers');
        imgui.ShowHelp('Show pet-related ability recast timers (Blood Pact, Ready, Sic, etc.).');
    end

    if components.CollapsingSection('Background##petBar') then
        local bgThemes = {'-None-', 'Plain', 'Window1', 'Window2', 'Window3', 'Window4', 'Window5', 'Window6', 'Window7', 'Window8'};
        local currentTheme = gConfig.petBarBackgroundTheme or 'Window1';
        components.DrawComboBox('Theme##petBarBg', currentTheme, bgThemes, function(newValue)
            gConfig.petBarBackgroundTheme = newValue;
            DeferredUpdateVisuals();
        end);
        imgui.ShowHelp('Select the background window theme.');
        components.DrawSlider('Background Opacity##petBarBg', 'petBarBackgroundOpacity', 0.0, 1.0, '%.2f');
        imgui.ShowHelp('Opacity of the background.');
        components.DrawSlider('Border Opacity##petBarBg', 'petBarBorderOpacity', 0.0, 1.0, '%.2f');
        imgui.ShowHelp('Opacity of the window borders (Window themes only).');
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

    if components.CollapsingSection('Ability Icons##petBar') then
        components.DrawCheckbox('Show 2-Hour Ability', 'petBarShow2HourAbility');
        imgui.ShowHelp('Show the 2-hour ability timer (Astral Flow, Familiar, Spirit Surge, Overdrive).');

        imgui.Spacing();

        -- Position mode
        local positionModes = {'In Container', 'Absolute'};
        local currentMode = gConfig.petBarIconsAbsolute and 'Absolute' or 'In Container';
        components.DrawComboBox('Position Mode##petBarIcons', currentMode, positionModes, function(newValue)
            local wasAbsolute = gConfig.petBarIconsAbsolute;
            gConfig.petBarIconsAbsolute = (newValue == 'Absolute');
            -- Reset offsets when switching modes
            if wasAbsolute ~= gConfig.petBarIconsAbsolute then
                if gConfig.petBarIconsAbsolute then
                    -- Switching to Absolute: use absolute defaults
                    gConfig.petBarIconsOffsetX = 112;
                    gConfig.petBarIconsOffsetY = 79;
                else
                    -- Switching to In Container: reset to 0
                    gConfig.petBarIconsOffsetX = 0;
                    gConfig.petBarIconsOffsetY = 0;
                end
            end
            SaveSettingsOnly();
        end);
        imgui.ShowHelp('In Container: Icons flow within the pet bar.\nAbsolute: Icons positioned independently from the pet bar.');

        -- Scale
        components.DrawSlider('Scale##petBarIcons', 'petBarIconsScale', 0.5, 2.0, '%.1f');
        imgui.ShowHelp('Scale of the ability icons.');

        -- X/Y Offset
        components.DrawSlider('Offset X##petBarIcons', 'petBarIconsOffsetX', -200, 200);
        imgui.ShowHelp('Horizontal offset for ability icons.');
        components.DrawSlider('Offset Y##petBarIcons', 'petBarIconsOffsetY', -200, 200);
        imgui.ShowHelp('Vertical offset for ability icons.');
    end

    -- ============================================
    -- Job-Specific Settings
    -- ============================================

    if components.CollapsingSection('(BST) Beastmaster##petBar') then
        imgui.TextColored({0.8, 0.8, 0.4, 1.0}, 'Ability Icons');
        imgui.Separator();

        components.DrawCheckbox('Ready', 'petBarBstShowReady');
        imgui.ShowHelp('Show Ready ability timer (offensive pet command).');
        components.DrawCheckbox('Sic', 'petBarBstShowSic');
        imgui.ShowHelp('Show Sic ability timer (offensive pet command).');
        components.DrawCheckbox('Reward', 'petBarBstShowReward');
        imgui.ShowHelp('Show Reward ability timer (pet healing).');
        components.DrawCheckbox('Call Beast', 'petBarBstShowCallBeast');
        imgui.ShowHelp('Show Call Beast ability timer (summon jug pet).');
        components.DrawCheckbox('Bestial Loyalty', 'petBarBstShowBestialLoyalty');
        imgui.ShowHelp('Show Bestial Loyalty ability timer (summon jug pet without charm).');

        imgui.Spacing();
        imgui.TextColored({0.8, 0.8, 0.4, 1.0}, 'Pet Timers');
        imgui.Separator();

        components.DrawCheckbox('Show Jug Pet Timer', 'petBarShowJugTimer');
        imgui.ShowHelp('Show countdown timer for jug pet duration (time remaining).');

        components.DrawCheckbox('Show Charm Indicator', 'petBarShowCharmIndicator');
        imgui.ShowHelp('Show heart icon and elapsed timer for charmed pets.');

        imgui.Spacing();

        -- Icon size
        components.DrawSlider('Icon Size##petBarCharm', 'petBarCharmIconSize', 8, 32);
        imgui.ShowHelp('Size of the heart icon.');

        -- Timer font size
        components.DrawSlider('Timer Font Size##petBarCharm', 'petBarCharmTimerFontSize', 6, 18);
        imgui.ShowHelp('Font size for charm duration timer.');

        imgui.Spacing();
        imgui.Text('Position (relative to window)');

        -- X/Y Offset
        components.DrawSlider('Offset X##petBarCharm', 'petBarCharmOffsetX', -200, 200);
        imgui.ShowHelp('Horizontal offset from window left.');
        components.DrawSlider('Offset Y##petBarCharm', 'petBarCharmOffsetY', -200, 200);
        imgui.ShowHelp('Vertical offset from window top. Negative values position above the window.');
    end

    if components.CollapsingSection('(SMN) Summoner##petBar') then
        imgui.TextColored({0.8, 0.8, 0.4, 1.0}, 'Ability Icons');
        imgui.Separator();

        components.DrawCheckbox('Blood Pact: Rage', 'petBarSmnShowBPRage');
        imgui.ShowHelp('Show Blood Pact: Rage ability timer (offensive blood pacts).');
        components.DrawCheckbox('Blood Pact: Ward', 'petBarSmnShowBPWard');
        imgui.ShowHelp('Show Blood Pact: Ward ability timer (defensive/support blood pacts).');
        components.DrawCheckbox('Apogee', 'petBarSmnShowApogee');
        imgui.ShowHelp('Show Apogee ability timer (enhances next blood pact).');
        components.DrawCheckbox('Mana Cede', 'petBarSmnShowManaCede');
        imgui.ShowHelp('Show Mana Cede ability timer (transfer MP to avatar).');

        imgui.Spacing();
        imgui.TextColored({0.8, 0.8, 0.4, 1.0}, 'Avatar Image');
        imgui.Separator();

        components.DrawCheckbox('Show Avatar Image', 'petBarShowImage');
        imgui.ShowHelp('Show avatar image overlay on the pet bar.');

        if gConfig.petBarShowImage then
            imgui.Spacing();

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
    end

    if components.CollapsingSection('(DRG) Dragoon##petBar') then
        imgui.TextColored({0.8, 0.8, 0.4, 1.0}, 'Ability Icons');
        imgui.Separator();

        components.DrawCheckbox('Call Wyvern', 'petBarDrgShowCallWyvern');
        imgui.ShowHelp('Show Call Wyvern ability timer (summon wyvern).');
        components.DrawCheckbox('Spirit Link', 'petBarDrgShowSpiritLink');
        imgui.ShowHelp('Show Spirit Link ability timer (heal wyvern).');
        components.DrawCheckbox('Deep Breathing', 'petBarDrgShowDeepBreathing');
        imgui.ShowHelp('Show Deep Breathing ability timer (enhance wyvern breath).');
        components.DrawCheckbox('Steady Wing', 'petBarDrgShowSteadyWing');
        imgui.ShowHelp('Show Steady Wing ability timer (wyvern stoneskin).');
    end

    if components.CollapsingSection('(PUP) Puppetmaster##petBar') then
        imgui.TextColored({0.8, 0.8, 0.4, 1.0}, 'Ability Icons');
        imgui.Separator();

        components.DrawCheckbox('Activate', 'petBarPupShowActivate');
        imgui.ShowHelp('Show Activate ability timer (summon automaton).');
        components.DrawCheckbox('Repair', 'petBarPupShowRepair');
        imgui.ShowHelp('Show Repair ability timer (heal automaton).');
        components.DrawCheckbox('Deus Ex Automata', 'petBarPupShowDeusExAutomata');
        imgui.ShowHelp('Show Deus Ex Automata ability timer (revive automaton).');
        components.DrawCheckbox('Deploy', 'petBarPupShowDeploy');
        imgui.ShowHelp('Show Deploy ability timer (send automaton to engage).');
        components.DrawCheckbox('Deactivate', 'petBarPupShowDeactivate');
        imgui.ShowHelp('Show Deactivate ability timer (dismiss automaton).');
        components.DrawCheckbox('Retrieve', 'petBarPupShowRetrieve');
        imgui.ShowHelp('Show Retrieve ability timer (call automaton back).');
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

    if components.CollapsingSection('Background##petTarget') then
        local bgThemes = {'-None-', 'Plain', 'Window1', 'Window2', 'Window3', 'Window4', 'Window5', 'Window6', 'Window7', 'Window8'};
        local currentTheme = gConfig.petTargetBackgroundTheme or gConfig.petBarBackgroundTheme or 'Window1';
        components.DrawComboBox('Theme##petTargetBg', currentTheme, bgThemes, function(newValue)
            gConfig.petTargetBackgroundTheme = newValue;
            DeferredUpdateVisuals();
        end);
        imgui.ShowHelp('Select the background window theme for pet target. Uses Pet Bar theme by default.');
        components.DrawSlider('Background Opacity##petTargetBg', 'petTargetBackgroundOpacity', 0.0, 1.0, '%.2f');
        imgui.ShowHelp('Opacity of the background. Uses Pet Bar opacity by default.');
        components.DrawSlider('Border Opacity##petTargetBg', 'petTargetBorderOpacity', 0.0, 1.0, '%.2f');
        imgui.ShowHelp('Opacity of the window borders. Uses Pet Bar border opacity by default.');
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
            hpTextColor = 0xFFFFA7A7,
            mpTextColor = 0xFFD4FF97,
            tpTextColor = 0xFF8DC7FF,
            targetTextColor = 0xFFFFFFFF,
            -- Rage timer colors (offensive abilities)
            timerRageReadyColor = 0xE6FF6600,
            timerRageRecastColor = 0xD9FF9933,
            -- Ward timer colors (defensive abilities)
            timerWardReadyColor = 0xE600CCFF,
            timerWardRecastColor = 0xD966E0FF,
            -- 2-Hour timer colors
            timer2hReadyColor = 0xE6FF00FF,
            timer2hRecastColor = 0xD9FF66FF,
            -- Other timer colors (utility - legacy)
            timerReadyColor = 0xE600FF00,
            timerRecastColor = 0xD9FFFF00,
            bgColor = 0xFFFFFFFF,
            borderColor = 0xFFFFFFFF,
        };
    end
    -- Ensure borderColor exists (for existing configs)
    if gConfig.colorCustomization.petBar.borderColor == nil then
        gConfig.colorCustomization.petBar.borderColor = 0xFFFFFFFF;
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
        -- Ensure timer color settings exist for all categories
        -- Rage (offensive) - Orange tones
        if gConfig.colorCustomization.petBar.timerRageReadyColor == nil then
            gConfig.colorCustomization.petBar.timerRageReadyColor = 0xE6FF6600;
        end
        if gConfig.colorCustomization.petBar.timerRageRecastColor == nil then
            gConfig.colorCustomization.petBar.timerRageRecastColor = 0xD9FF9933;
        end
        -- Ward (defensive) - Cyan tones
        if gConfig.colorCustomization.petBar.timerWardReadyColor == nil then
            gConfig.colorCustomization.petBar.timerWardReadyColor = 0xE600CCFF;
        end
        if gConfig.colorCustomization.petBar.timerWardRecastColor == nil then
            gConfig.colorCustomization.petBar.timerWardRecastColor = 0xD966E0FF;
        end
        -- 2-Hour - Magenta tones
        if gConfig.colorCustomization.petBar.timer2hReadyColor == nil then
            gConfig.colorCustomization.petBar.timer2hReadyColor = 0xE6FF00FF;
        end
        if gConfig.colorCustomization.petBar.timer2hRecastColor == nil then
            gConfig.colorCustomization.petBar.timer2hRecastColor = 0xD9FF66FF;
        end
        -- Other (utility) - Green/Yellow (legacy)
        if gConfig.colorCustomization.petBar.timerReadyColor == nil then
            gConfig.colorCustomization.petBar.timerReadyColor = 0xE600FF00;
        end
        if gConfig.colorCustomization.petBar.timerRecastColor == nil then
            gConfig.colorCustomization.petBar.timerRecastColor = 0xD9FFFF00;
        end

        imgui.Text('Rage (Blood Pact: Rage, Ready, Sic, Deploy)');
        components.DrawTextColorPicker("Ready##rage", gConfig.colorCustomization.petBar, 'timerRageReadyColor', "Color when Rage ability is ready");
        components.DrawTextColorPicker("Recast##rage", gConfig.colorCustomization.petBar, 'timerRageRecastColor', "Color when Rage ability is on cooldown");

        imgui.Spacing();
        imgui.Text('Ward (Blood Pact: Ward, Reward, Repair, Spirit Link)');
        components.DrawTextColorPicker("Ready##ward", gConfig.colorCustomization.petBar, 'timerWardReadyColor', "Color when Ward ability is ready");
        components.DrawTextColorPicker("Recast##ward", gConfig.colorCustomization.petBar, 'timerWardRecastColor', "Color when Ward ability is on cooldown");

        imgui.Spacing();
        imgui.Text('Two-Hour (Astral Flow, Familiar, Spirit Surge, Overdrive)');
        components.DrawTextColorPicker("Ready##2h", gConfig.colorCustomization.petBar, 'timer2hReadyColor', "Color when 2-Hour ability is ready");
        components.DrawTextColorPicker("Recast##2h", gConfig.colorCustomization.petBar, 'timer2hRecastColor', "Color when 2-Hour ability is on cooldown");

        imgui.Spacing();
        imgui.Text('Other (Apogee, Call Beast, Activate, etc.)');
        components.DrawTextColorPicker("Ready##other", gConfig.colorCustomization.petBar, 'timerReadyColor', "Color when utility ability is ready");
        components.DrawTextColorPicker("Recast##other", gConfig.colorCustomization.petBar, 'timerRecastColor', "Color when utility ability is on cooldown");
    end

    if components.CollapsingSection('(BST) Beastmaster##petBarColor') then
        -- Ensure color settings exist
        if gConfig.colorCustomization.petBar.charmHeartColor == nil then
            gConfig.colorCustomization.petBar.charmHeartColor = 0xFFFF6699;
        end
        if gConfig.colorCustomization.petBar.jugIconColor == nil then
            gConfig.colorCustomization.petBar.jugIconColor = 0xFFFFFFFF;
        end
        if gConfig.colorCustomization.petBar.charmTimerColor == nil then
            gConfig.colorCustomization.petBar.charmTimerColor = 0xFFFFFFFF;
        end

        imgui.TextColored({0.8, 0.8, 0.4, 1.0}, 'Pet Timer Icons');
        imgui.Separator();
        components.DrawTextColorPicker("Charm Heart Icon", gConfig.colorCustomization.petBar, 'charmHeartColor', "Color/tint of the heart icon for charmed pets");
        components.DrawTextColorPicker("Jug Icon", gConfig.colorCustomization.petBar, 'jugIconColor', "Color/tint of the jug icon for jug pets");
        components.DrawTextColorPicker("Timer Text", gConfig.colorCustomization.petBar, 'charmTimerColor', "Color of the pet timer text (charm/jug)");
    end

    if components.CollapsingSection('Background Colors##petBarColor') then
        components.DrawTextColorPicker("Background Tint", gConfig.colorCustomization.petBar, 'bgColor', "Tint color for background");
        components.DrawTextColorPicker("Border Color", gConfig.colorCustomization.petBar, 'borderColor', "Color of window borders (Window themes only)");
    end
end

-- Helper: Draw Pet Target specific color settings (used in tab)
local function DrawPetTargetColorSettingsContent()
    -- Ensure petTarget color config exists
    if gConfig.colorCustomization.petTarget == nil then
        gConfig.colorCustomization.petTarget = T{
            hpGradient = T{ enabled = true, start = '#e26c6c', stop = '#fb9494' },
            bgColor = 0xFFFF8D8D,
            targetTextColor = 0xFFFFFFFF,
            borderColor = 0xFFFF8D8D,
        };
    end
    -- Ensure borderColor exists (for existing configs)
    if gConfig.colorCustomization.petTarget.borderColor == nil then
        gConfig.colorCustomization.petTarget.borderColor = 0xFFFF8D8D;
    end
    -- Ensure hpGradient exists (for existing configs)
    if gConfig.colorCustomization.petTarget.hpGradient == nil then
        gConfig.colorCustomization.petTarget.hpGradient = T{ enabled = true, start = '#e26c6c', stop = '#fb9494' };
    end

    if components.CollapsingSection('Bar Colors##petTargetColor') then
        components.DrawGradientPickerColumn("HP Bar##petTarget", gConfig.colorCustomization.petTarget.hpGradient, "Pet target HP bar color gradient");
    end

    if components.CollapsingSection('Text Colors##petTargetColor') then
        components.DrawTextColorPicker("Target Info", gConfig.colorCustomization.petTarget, 'targetTextColor', "Color of pet target text");
    end

    if components.CollapsingSection('Background Colors##petTargetColor') then
        components.DrawTextColorPicker("Background Tint", gConfig.colorCustomization.petTarget, 'bgColor', "Tint color for background");
        components.DrawTextColorPicker("Border Color", gConfig.colorCustomization.petTarget, 'borderColor', "Color of window borders (Window themes only)");
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
