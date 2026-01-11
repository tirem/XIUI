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

-- Pet type definitions for sub-tabs
-- previewType maps to data.PREVIEW_* constants: WYVERN=1, AVATAR=2, AUTOMATON=3, JUG=4, CHARM=5
local PET_TYPES = {
    { key = 'Avatar', configKey = 'petBarAvatar', label = 'Avatar', previewType = 2 },
    { key = 'Charm', configKey = 'petBarCharm', label = 'Charm', previewType = 5 },
    { key = 'Jug', configKey = 'petBarJug', label = 'Jug', previewType = 4 },
    { key = 'Automaton', configKey = 'petBarAutomaton', label = 'Automaton', previewType = 3 },
    { key = 'Wyvern', configKey = 'petBarWyvern', label = 'Wyvern', previewType = 1 },
};

-- Copy settings between pet types
local function CopyPetTypeSettings(sourceKey, targetKey)
    local source = gConfig[sourceKey];
    local target = gConfig[targetKey];
    -- Validate both source and target are tables
    if source and target and type(source) == 'table' and type(target) == 'table' then
        for k, v in pairs(source) do
            if type(v) == 'table' then
                target[k] = deep_copy_table(v);
            else
                target[k] = v;
            end
        end
        SaveSettingsOnly();
    end
end

-- Copy color settings between pet types
local function CopyPetTypeColors(sourceKey, targetKey)
    local colorSource = gConfig.colorCustomization and gConfig.colorCustomization[sourceKey];
    -- Validate source is a table
    if colorSource and type(colorSource) == 'table' then
        gConfig.colorCustomization[targetKey] = deep_copy_table(colorSource);
        SaveSettingsOnly();
    end
end

-- Helper: Draw per-pet-type visual settings
local function DrawPetTypeVisualSettings(configKey, petTypeLabel)
    local typeSettings = gConfig[configKey];
    -- Validate typeSettings is a table with expected properties
    if not typeSettings or type(typeSettings) ~= 'table' or typeSettings.hpScaleX == nil then
        imgui.TextColored({1.0, 0.5, 0.5, 1.0}, 'Settings not initialized for ' .. petTypeLabel);
        imgui.Text('Please reload the addon to initialize per-type settings.');
        return;
    end

    if components.CollapsingSection('Display Options##' .. configKey, false) then
        -- Charmed pets don't have levels, so hide this option for Charm
        if configKey ~= 'petBarCharm' then
            components.DrawPartyCheckbox(typeSettings, 'Show Pet Level##' .. configKey, 'showLevel');
            imgui.ShowHelp('Show pet level before the name (e.g., "Lv.35 FunguarFamiliar").');
            imgui.Spacing();
        end

        components.DrawPartyCheckbox(typeSettings, 'Align Bottom##' .. configKey, 'alignBottom');
        imgui.ShowHelp('Anchor the pet bar to its bottom edge. When the window height changes, it expands upward.');
        imgui.Spacing();

        components.DrawPartyCheckbox(typeSettings, 'Show Distance##' .. configKey, 'showDistance');
        imgui.ShowHelp('Show distance from player to pet.');

        if typeSettings.showDistance then
            components.DrawPartySlider(typeSettings, 'Offset X##dist' .. configKey, 'distanceOffsetX', -200, 200);
            components.DrawPartySlider(typeSettings, 'Offset Y##dist' .. configKey, 'distanceOffsetY', -200, 200);
        end
    end

    if components.CollapsingSection('Bar Settings##' .. configKey, false) then
        -- HP Bar
        components.DrawPartyCheckbox(typeSettings, 'Show HP Bar##' .. configKey, 'showHP');
        imgui.ShowHelp('Show pet HP bar.');
        if typeSettings.showHP then
            components.DrawPartySlider(typeSettings, 'Scale X##hp' .. configKey, 'hpScaleX', 0.5, 2.0, '%.1f');
            components.DrawPartySlider(typeSettings, 'Scale Y##hp' .. configKey, 'hpScaleY', 0.5, 2.0, '%.1f');
        end

        imgui.Spacing();

        -- MP Bar (only Automaton uses MP in era)
        if configKey == 'petBarAutomaton' then
            components.DrawPartyCheckbox(typeSettings, 'Show MP Bar##' .. configKey, 'showMP');
            imgui.ShowHelp('Show pet MP bar.');
            if typeSettings.showMP then
                components.DrawPartySlider(typeSettings, 'Scale X##mp' .. configKey, 'mpScaleX', 0.5, 2.0, '%.1f');
                components.DrawPartySlider(typeSettings, 'Scale Y##mp' .. configKey, 'mpScaleY', 0.5, 2.0, '%.1f');
            end

            imgui.Spacing();
        end

        -- TP Bar
        components.DrawPartyCheckbox(typeSettings, 'Show TP Bar##' .. configKey, 'showTP');
        imgui.ShowHelp('Show pet TP bar.');
        if typeSettings.showTP then
            components.DrawPartySlider(typeSettings, 'Scale X##tp' .. configKey, 'tpScaleX', 0.5, 2.0, '%.1f');
            components.DrawPartySlider(typeSettings, 'Scale Y##tp' .. configKey, 'tpScaleY', 0.5, 2.0, '%.1f');
        end

    end

    if components.CollapsingSection('Text Settings##' .. configKey, false) then
        components.DrawPartySlider(typeSettings, 'Pet Name Text Size##' .. configKey, 'nameFontSize', 8, 24);
        components.DrawPartySlider(typeSettings, 'Distance Text Size##' .. configKey, 'distanceFontSize', 6, 18);
        components.DrawPartySlider(typeSettings, 'HP Text Size##' .. configKey, 'hpFontSize', 6, 18);
        -- Only Automaton uses MP in era
        if configKey == 'petBarAutomaton' then
            components.DrawPartySlider(typeSettings, 'MP Text Size##' .. configKey, 'mpFontSize', 6, 18);
        end
        components.DrawPartySlider(typeSettings, 'TP Text Size##' .. configKey, 'tpFontSize', 6, 18);
    end

    if components.CollapsingSection('Background##' .. configKey, false) then
        local bgThemes = {'-None-', 'Plain', 'Window1', 'Window2', 'Window3', 'Window4', 'Window5', 'Window6', 'Window7', 'Window8'};
        local currentTheme = typeSettings.backgroundTheme or 'Window1';
        components.DrawPartyComboBox(typeSettings, 'Theme##bg' .. configKey, 'backgroundTheme', bgThemes, DeferredUpdateVisuals);
        imgui.ShowHelp('Select the background window theme for this pet type.');
        -- Scale/opacity sliders don't need callbacks - changes are picked up from gConfig on next frame
        components.DrawPartySlider(typeSettings, 'Background Scale##' .. configKey, 'bgScale', 0.1, 3.0, '%.2f', nil, 1.0);
        imgui.ShowHelp('Scale of the background texture.');
        components.DrawPartySlider(typeSettings, 'Border Scale##' .. configKey, 'borderScale', 0.1, 3.0, '%.2f', nil, 1.0);
        imgui.ShowHelp('Scale of the window borders (Window themes only).');
        components.DrawPartySlider(typeSettings, 'Background Opacity##' .. configKey, 'backgroundOpacity', 0.0, 1.0, '%.2f');
        imgui.ShowHelp('Opacity of the background.');
        components.DrawPartySlider(typeSettings, 'Border Opacity##' .. configKey, 'borderOpacity', 0.0, 1.0, '%.2f');
        imgui.ShowHelp('Opacity of the window borders (Window themes only).');
    end

    if components.CollapsingSection('Ability Recasts##' .. configKey, false) then
        components.DrawPartyCheckbox(typeSettings, 'Show Ability Timers##' .. configKey, 'showTimers');
        imgui.ShowHelp('Show pet-related ability recast timers (Blood Pact, Ready, Sic, etc.).');

        if typeSettings.showTimers then
            imgui.Spacing();

            -- Display style selection (Compact vs Full)
            local displayStyles = {'compact', 'full'};
            local displayStyleLabels = {
                compact = 'Compact (Icons Only)',
                full = 'Full (Name + Timer)'
            };
            local currentDisplayStyle = typeSettings.recastDisplayStyle or 'compact';

            imgui.SetNextItemWidth(components.CONTENT_MAX_WIDTH);
            if imgui.BeginCombo('Display Style##icons' .. configKey, displayStyleLabels[currentDisplayStyle]) then
                for _, style in ipairs(displayStyles) do
                    if imgui.Selectable(displayStyleLabels[style], style == currentDisplayStyle) then
                        typeSettings.recastDisplayStyle = style;
                        SaveSettingsOnly();
                    end
                end
                imgui.EndCombo();
            end
            imgui.ShowHelp('Compact: Shows only the icon indicators in a horizontal row.\nFull: Shows icon, ability name, and recast timer in a vertical list.');

            imgui.Spacing();

            -- Full display style options (only show when full mode is selected)
            if currentDisplayStyle == 'full' then
                imgui.Indent(10);

                -- Show/hide individual elements
                local showName = {typeSettings.recastFullShowName ~= false};
                if imgui.Checkbox('Show Name##recastFull' .. configKey, showName) then
                    typeSettings.recastFullShowName = showName[1];
                    SaveSettingsOnly();
                end
                imgui.SameLine();

                local showRecast = {typeSettings.recastFullShowTimer ~= false};
                if imgui.Checkbox('Show Timer##recastFull' .. configKey, showRecast) then
                    typeSettings.recastFullShowTimer = showRecast[1];
                    SaveSettingsOnly();
                end

                -- Name text size (only show if name is enabled)
                if showName[1] then
                    components.SliderInt('Name Text Size##recastFull' .. configKey, typeSettings, 'recastFullNameFontSize', 8, 20, 10);
                    imgui.ShowHelp('Text size for ability name.');
                end

                -- Timer text size (only show if timer is enabled)
                if showRecast[1] then
                    components.SliderInt('Timer Text Size##recastFull' .. configKey, typeSettings, 'recastFullTimerFontSize', 8, 20, 10);
                    imgui.ShowHelp('Text size for recast timer.');
                end

                -- Bar scale settings
                components.SliderFloat('Bar Width##recast' .. configKey, typeSettings, 'recastScaleX', 0.5, 2.0, '%.1f', 1.0);
                imgui.ShowHelp('Horizontal scale for recast progress bars (based on HP bar width).');

                components.SliderFloat('Bar Height##recast' .. configKey, typeSettings, 'recastScaleY', 0.5, 2.0, '%.1f', 0.5);
                imgui.ShowHelp('Vertical scale for recast progress bars (based on bar height).');

                -- Row spacing
                components.SliderInt('Row Spacing##recastFull' .. configKey, typeSettings, 'recastFullSpacing', -50, 50, 4);
                imgui.ShowHelp('Vertical spacing between recast rows.');

                -- Top spacing (anchored mode only) - space between vitals and recasts
                if not typeSettings.iconsAbsolute then
                    components.SliderInt('Top Spacing##recastFull' .. configKey, typeSettings, 'recastTopSpacing', -50, 50, 2);
                    imgui.ShowHelp('Vertical spacing between vitals (HP/MP/TP) and ability recasts.');
                end

                imgui.Unindent(10);
                imgui.Spacing();
            end

            -- Fill style selection (icon shape) - only show for compact mode
            if currentDisplayStyle ~= 'full' then
                local fillStyles = {'square', 'circle', 'clock'};
                local fillStyleLabels = {
                    square = 'Square (Vertical Fill)',
                    circle = 'Circle (Radial Fill)',
                    clock = 'Clock (Arc Sweep)'
                };
                local currentFillStyle = typeSettings.timerFillStyle or 'square';

                -- Check if clock fill is available (requires Ashita 4.3+)
                local clockAvailable = imgui.GetForegroundDrawList().PathClear ~= nil;

                imgui.SetNextItemWidth(components.CONTENT_MAX_WIDTH);
                if imgui.BeginCombo('Icon Shape##icons' .. configKey, fillStyleLabels[currentFillStyle]) then
                    for _, style in ipairs(fillStyles) do
                        local isDisabled = (style == 'clock' and not clockAvailable);
                        local label = fillStyleLabels[style];
                        if isDisabled then
                            label = label .. ' (Ashita 4.3+)';
                        end

                        if isDisabled then
                            imgui.PushStyleColor(ImGuiCol_Text, {0.5, 0.5, 0.5, 1.0});
                        end

                        if imgui.Selectable(label, style == currentFillStyle, isDisabled and ImGuiSelectableFlags_Disabled or 0) then
                            typeSettings.timerFillStyle = style;
                            SaveSettingsOnly();
                        end

                        if isDisabled then
                            imgui.PopStyleColor();
                        end
                    end
                    imgui.EndCombo();
                end
                imgui.ShowHelp('Shape and fill animation for the icon indicator.\nSquare: Fills vertically from bottom to top.\nCircle: Grows outward from center.\nClock: Sweeps clockwise like a clock (requires Ashita 4.3+).');
                imgui.Spacing();
            end

            -- Position mode
            local positionModes = {'Anchored', 'Absolute'};
            local currentMode = typeSettings.iconsAbsolute and 'Absolute' or 'Anchored';
            imgui.SetNextItemWidth(components.CONTENT_MAX_WIDTH);
            if imgui.BeginCombo('Position Mode##icons' .. configKey, currentMode) then
                for _, mode in ipairs(positionModes) do
                    if imgui.Selectable(mode, mode == currentMode) then
                        local wasAbsolute = typeSettings.iconsAbsolute;
                        typeSettings.iconsAbsolute = (mode == 'Absolute');
                        -- Reset offsets when switching modes
                        if wasAbsolute and not typeSettings.iconsAbsolute then
                            -- Switching to anchored: reset to 0,0 (flows within container)
                            typeSettings.iconsOffsetX = 0;
                            typeSettings.iconsOffsetY = 0;
                        elseif not wasAbsolute and typeSettings.iconsAbsolute then
                            -- Switching to absolute: set reasonable defaults
                            typeSettings.iconsOffsetX = 8;
                            typeSettings.iconsOffsetY = 78;
                        end
                        SaveSettingsOnly();
                    end
                end
                imgui.EndCombo();
            end
            imgui.ShowHelp('Anchored: Icons flow within the pet bar container.\nAbsolute: Icons positioned independently.');

            -- Scale only applies in compact mode
            if currentDisplayStyle ~= 'full' then
                components.DrawPartySlider(typeSettings, 'Scale##icons' .. configKey, 'iconsScale', 0.5, 2.0, '%.1f');
                imgui.ShowHelp('Scale of the ability icons.');
            end

            -- Offsets only apply when not in anchored + full mode
            local isAnchoredFull = not typeSettings.iconsAbsolute and currentDisplayStyle == 'full';
            if not isAnchoredFull then
                components.DrawPartySlider(typeSettings, 'Offset X##icons' .. configKey, 'iconsOffsetX', -200, 200);
                imgui.ShowHelp('Horizontal offset for ability icons.');
                components.DrawPartySlider(typeSettings, 'Offset Y##icons' .. configKey, 'iconsOffsetY', -200, 200);
                imgui.ShowHelp('Vertical offset for ability icons.');
            end

            -- Pet-type specific ability toggles
            if configKey == 'petBarAvatar' then
                imgui.Spacing();
                imgui.Separator();
                imgui.Spacing();
                components.DrawCheckbox('Blood Pact: Rage', 'petBarSmnShowBPRage');
                imgui.ShowHelp('Show Blood Pact: Rage ability timer (offensive blood pacts).');
                components.DrawCheckbox('Blood Pact: Ward', 'petBarSmnShowBPWard');
                imgui.ShowHelp('Show Blood Pact: Ward ability timer (defensive/support blood pacts).');
                components.DrawCheckbox('Apogee', 'petBarSmnShowApogee');
                imgui.ShowHelp('Show Apogee ability timer (enhances next blood pact).');
                components.DrawCheckbox('Mana Cede', 'petBarSmnShowManaCede');
                imgui.ShowHelp('Show Mana Cede ability timer (transfer MP to avatar).');
            elseif configKey == 'petBarCharm' then
                imgui.Spacing();
                imgui.Separator();
                imgui.Spacing();
                components.DrawCheckbox('Ready/Sic', 'petBarBstShowReady');
                imgui.ShowHelp('Show Ready/Sic ability timer (offensive pet command).');
                if gConfig.petBarBstShowReady then
                    imgui.Indent(10);
                    components.DrawSlider('Base Charge Time (s)##readyCharm', 'petBarReadyBaseRecast', 15, 60);
                    imgui.ShowHelp('Base recast time per Ready charge in seconds.\nDefault: 30s (retail/LSB)\nHorizon: 45s\nMerits will automatically reduce the timer.');
                    imgui.Unindent(10);
                end
                components.DrawCheckbox('Reward', 'petBarBstShowReward');
                imgui.ShowHelp('Show Reward ability timer (pet healing).');
            elseif configKey == 'petBarJug' then
                imgui.Spacing();
                imgui.Separator();
                imgui.Spacing();
                components.DrawCheckbox('Ready/Sic', 'petBarBstShowReady');
                imgui.ShowHelp('Show Ready/Sic ability timer (offensive pet command).');
                if gConfig.petBarBstShowReady then
                    imgui.Indent(10);
                    components.DrawSlider('Base Charge Time (s)##ready', 'petBarReadyBaseRecast', 15, 60);
                    imgui.ShowHelp('Base recast time per Ready charge in seconds.\nDefault: 30s (retail/LSB)\nHorizon: 45s\nMerits will automatically reduce the timer.');
                    imgui.Unindent(10);
                end
                components.DrawCheckbox('Reward', 'petBarBstShowReward');
                imgui.ShowHelp('Show Reward ability timer (pet healing).');
                components.DrawCheckbox('Call Beast', 'petBarBstShowCallBeast');
                imgui.ShowHelp('Show Call Beast ability timer (summon jug pet).');
                components.DrawCheckbox('Bestial Loyalty', 'petBarBstShowBestialLoyalty');
                imgui.ShowHelp('Show Bestial Loyalty ability timer (summon jug pet without charm).');
            elseif configKey == 'petBarAutomaton' then
                imgui.Spacing();
                imgui.Separator();
                imgui.Spacing();
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
            elseif configKey == 'petBarWyvern' then
                imgui.Spacing();
                imgui.Separator();
                imgui.Spacing();
                components.DrawCheckbox('Call Wyvern', 'petBarDrgShowCallWyvern');
                imgui.ShowHelp('Show Call Wyvern ability timer (summon wyvern).');
                components.DrawCheckbox('Spirit Link', 'petBarDrgShowSpiritLink');
                imgui.ShowHelp('Show Spirit Link ability timer (heal wyvern).');
                components.DrawCheckbox('Deep Breathing', 'petBarDrgShowDeepBreathing');
                imgui.ShowHelp('Show Deep Breathing ability timer (enhance wyvern breath).');
                components.DrawCheckbox('Steady Wing', 'petBarDrgShowSteadyWing');
                imgui.ShowHelp('Show Steady Wing ability timer (wyvern stoneskin).');
            end
        end
    end

    -- ============================================
    -- Pet-Type-Specific Settings
    -- ============================================

    -- Avatar (SMN) specific settings
    if configKey == 'petBarAvatar' then
        if components.CollapsingSection('Avatar Image##avatar', false) then
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
                -- Sync selectedAvatarIndex with saved preview avatar
                if gConfig.petBarPreviewAvatar then
                    for i, name in ipairs(avatarList) do
                        if name == gConfig.petBarPreviewAvatar then
                            selectedAvatarIndex = i;
                            break;
                        end
                    end
                end
                local currentAvatar = avatarList[selectedAvatarIndex] or 'Carbuncle';

                imgui.SetNextItemWidth(components.CONTENT_MAX_WIDTH);
                if imgui.BeginCombo('Avatar##petBarAvatarSelect', currentAvatar) then
                    for i, avatarName in ipairs(avatarList) do
                        local isSelected = (i == selectedAvatarIndex);
                        if imgui.Selectable(avatarName, isSelected) then
                            selectedAvatarIndex = i;
                            -- Update preview avatar name so preview shows this avatar
                            gConfig.petBarPreviewAvatar = avatarName;
                            SaveSettingsOnly();
                        end
                        if isSelected then
                            imgui.SetItemDefaultFocus();
                        end
                    end
                    imgui.EndCombo();
                end
                imgui.ShowHelp('Select an avatar to adjust its image settings. Preview will show this avatar.');

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
                components.SliderFloat('Scale##petBarAvatarScale', avatarSettings, 'scale', 0.1, 2.0, '%.2f', 0.4);
                imgui.ShowHelp('Scale of the avatar image overlay.');

                -- Opacity slider
                components.SliderFloat('Opacity##petBarAvatarOpacity', avatarSettings, 'opacity', 0.0, 1.0, '%.2f', 0.3);
                imgui.ShowHelp('Opacity of the avatar image overlay.');

                -- Offset X slider
                components.SliderInt('Offset X##petBarAvatarOffsetX', avatarSettings, 'offsetX', -600, 600, 0);
                imgui.ShowHelp('Horizontal offset for the avatar image.');

                -- Offset Y slider
                components.SliderInt('Offset Y##petBarAvatarOffsetY', avatarSettings, 'offsetY', -600, 600, 0);
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
    end

    -- Charm (BST charmed pets) specific settings
    if configKey == 'petBarCharm' then
        if components.CollapsingSection('Charm Indicator##charm', false) then
            components.DrawCheckbox('Show Charm Indicator', 'petBarShowCharmIndicator');
            imgui.ShowHelp('Show heart icon and elapsed timer for charmed pets.');

            imgui.Spacing();

            -- Icon size
            components.DrawSlider('Icon Size##petBarCharm', 'petBarCharmIconSize', 8, 32);
            imgui.ShowHelp('Size of the heart icon.');

            -- Timer font size
            components.DrawSlider('Timer Text Size##petBarCharm', 'petBarCharmTimerFontSize', 6, 18);
            imgui.ShowHelp('Font size for charm duration timer.');

            imgui.Spacing();
            imgui.Text('Position (relative to window)');

            -- X/Y Offset
            components.DrawSlider('Offset X##petBarCharm', 'petBarCharmOffsetX', -200, 200);
            imgui.ShowHelp('Horizontal offset from window left.');
            components.DrawSlider('Offset Y##petBarCharm', 'petBarCharmOffsetY', -200, 200);
            imgui.ShowHelp('Vertical offset from window top.');
        end
    end

    -- Jug (BST jug pets) specific settings
    if configKey == 'petBarJug' then
        if components.CollapsingSection('Jug Pet Timer##jug', false) then
            components.DrawCheckbox('Show Jug Pet Timer', 'petBarShowJugTimer');
            imgui.ShowHelp('Show countdown timer for jug pet duration (time remaining).');

            imgui.Spacing();

            -- Icon size
            components.DrawSlider('Icon Size##petBarJug', 'petBarJugIconSize', 8, 32);
            imgui.ShowHelp('Size of the jug icon.');

            -- Timer font size
            components.DrawSlider('Timer Text Size##petBarJug', 'petBarJugTimerFontSize', 6, 18);
            imgui.ShowHelp('Font size for jug duration timer.');

            imgui.Spacing();
            imgui.Text('Position (relative to window)');

            -- X/Y Offset
            components.DrawSlider('Offset X##petBarJug', 'petBarJugOffsetX', -200, 200);
            imgui.ShowHelp('Horizontal offset from window left.');
            components.DrawSlider('Offset Y##petBarJug', 'petBarJugOffsetY', -200, 200);
            imgui.ShowHelp('Vertical offset from window top.');
        end
    end

    -- Wyvern (DRG) specific settings
    if configKey == 'petBarWyvern' then
        if components.CollapsingSection('Wyvern Image##wyvern', false) then
            components.DrawPartyCheckbox(typeSettings, 'Show Wyvern Image##wyvern', 'showImage');
            imgui.ShowHelp('Show wyvern image overlay on the pet bar.');

            if typeSettings.showImage then
                imgui.Spacing();

                -- Scale slider
                components.DrawPartySlider(typeSettings, 'Scale##wyvernImage', 'imageScale', 0.1, 2.0, '%.2f');
                imgui.ShowHelp('Scale of the wyvern image overlay.');

                -- Opacity slider
                components.DrawPartySlider(typeSettings, 'Opacity##wyvernImage', 'imageOpacity', 0.0, 1.0, '%.2f');
                imgui.ShowHelp('Opacity of the wyvern image overlay.');

                -- Offset X slider
                components.DrawPartySlider(typeSettings, 'Offset X##wyvernImage', 'imageOffsetX', -600, 600);
                imgui.ShowHelp('Horizontal offset for the wyvern image.');

                -- Offset Y slider
                components.DrawPartySlider(typeSettings, 'Offset Y##wyvernImage', 'imageOffsetY', -600, 600);
                imgui.ShowHelp('Vertical offset for the wyvern image.');

                -- Clip to Background checkbox
                components.DrawPartyCheckbox(typeSettings, 'Clip to Background##wyvernImage', 'imageClipToBackground');
                imgui.ShowHelp('Clip the wyvern image to the pet bar background bounds.');
            end
        end
    end

end

-- Helper: Draw copy buttons for pet type settings
local function DrawPetTypeCopyButtons(currentConfigKey, currentLabel, settingsType)
    if components.CollapsingSectionWarning('Copy Settings##' .. currentConfigKey .. settingsType) then
        imgui.TextColored({0.7, 0.7, 0.7, 1.0}, 'Copy ' .. settingsType .. ' from:');
        for _, petType in ipairs(PET_TYPES) do
            if petType.configKey ~= currentConfigKey then
                imgui.SameLine();
                if imgui.Button(petType.label .. '##copy' .. settingsType .. petType.configKey .. 'to' .. currentConfigKey) then
                    if settingsType == 'Settings' then
                        CopyPetTypeSettings(petType.configKey, currentConfigKey);
                    else
                        CopyPetTypeColors(petType.configKey, currentConfigKey);
                    end
                end
            end
        end
    end
end

-- Helper: Draw per-pet-type color settings
local function DrawPetTypeColorSettings(configKey, petTypeLabel)
    local colorConfig = gConfig.colorCustomization and gConfig.colorCustomization[configKey];
    -- Validate colorConfig is a table with expected properties
    if not colorConfig or type(colorConfig) ~= 'table' or colorConfig.hpGradient == nil then
        imgui.TextColored({1.0, 0.5, 0.5, 1.0}, 'Color settings not initialized for ' .. petTypeLabel);
        imgui.Text('Please reload the addon to initialize per-type colors.');
        return;
    end

    if components.CollapsingSection('Bar Colors##' .. configKey .. 'color', false) then
        -- Column headers
        imgui.Text("HP Bar");
        imgui.SameLine(components.COLOR_COLUMN_SPACING);
        imgui.Text("MP Bar");
        imgui.SameLine(components.COLOR_COLUMN_SPACING * 2);
        imgui.Text("TP Bar");

        -- HP Bar
        if colorConfig.hpGradient then
            components.DrawGradientPickerColumn("HP Bar##" .. configKey, colorConfig.hpGradient, "HP bar color gradient");
        end

        imgui.SameLine(components.COLOR_COLUMN_SPACING);

        -- MP Bar
        if colorConfig.mpGradient then
            components.DrawGradientPickerColumn("MP Bar##" .. configKey, colorConfig.mpGradient, "MP bar color gradient");
        end

        imgui.SameLine(components.COLOR_COLUMN_SPACING * 2);

        -- TP Bar
        if colorConfig.tpGradient then
            components.DrawGradientPickerColumn("TP Bar##" .. configKey, colorConfig.tpGradient, "TP bar color gradient");
        end
    end

    if components.CollapsingSection('Text Colors##' .. configKey .. 'color', false) then
        components.DrawTextColorPicker("Pet Name##" .. configKey, colorConfig, 'nameTextColor', "Color of pet name text");
        components.DrawTextColorPicker("Distance##" .. configKey, colorConfig, 'distanceTextColor', "Color of distance text");
        components.DrawTextColorPicker("HP Text##" .. configKey, colorConfig, 'hpTextColor', "Color of HP value text");
        components.DrawTextColorPicker("MP Text##" .. configKey, colorConfig, 'mpTextColor', "Color of MP value text");
        components.DrawTextColorPicker("TP Text##" .. configKey, colorConfig, 'tpTextColor', "Color of TP value text");
    end

    -- ============================================
    -- Pet-Type-Specific Color Settings
    -- ============================================

    -- Avatar (SMN) specific color settings
    if configKey == 'petBarAvatar' then
        if components.CollapsingSection('Ability Timer Colors##' .. configKey .. 'color', false) then
            -- Ensure timer gradients exist
            if colorConfig.timerBPRageReadyGradient == nil then colorConfig.timerBPRageReadyGradient = T{ enabled = true, start = '#ff3333e6', stop = '#ff6666e6' }; end
            if colorConfig.timerBPRageRecastGradient == nil then colorConfig.timerBPRageRecastGradient = T{ enabled = true, start = '#ff6666d9', stop = '#ff9999d9' }; end
            if colorConfig.timerBPWardReadyGradient == nil then colorConfig.timerBPWardReadyGradient = T{ enabled = true, start = '#00cccce6', stop = '#66dddde6' }; end
            if colorConfig.timerBPWardRecastGradient == nil then colorConfig.timerBPWardRecastGradient = T{ enabled = true, start = '#66ddddd9', stop = '#99eeeed9' }; end
            if colorConfig.timerApogeeReadyGradient == nil then colorConfig.timerApogeeReadyGradient = T{ enabled = true, start = '#ffcc00e6', stop = '#ffdd66e6' }; end
            if colorConfig.timerApogeeRecastGradient == nil then colorConfig.timerApogeeRecastGradient = T{ enabled = true, start = '#ffdd66d9', stop = '#ffee99d9' }; end
            if colorConfig.timerManaCedeReadyGradient == nil then colorConfig.timerManaCedeReadyGradient = T{ enabled = true, start = '#009999e6', stop = '#66bbbbe6' }; end
            if colorConfig.timerManaCedeRecastGradient == nil then colorConfig.timerManaCedeRecastGradient = T{ enabled = true, start = '#66bbbbd9', stop = '#99ccccd9' }; end
            if colorConfig.timer2hReadyGradient == nil then colorConfig.timer2hReadyGradient = T{ enabled = true, start = '#ff00ffe6', stop = '#ff66ffe6' }; end
            if colorConfig.timer2hRecastGradient == nil then colorConfig.timer2hRecastGradient = T{ enabled = true, start = '#ff66ffd9', stop = '#ff99ffd9' }; end

            -- Column headers
            imgui.Text(''); imgui.SameLine(120); imgui.Text('Ready'); imgui.SameLine(120 + components.COLOR_COLUMN_SPACING); imgui.Text('Recast');

            imgui.Text('Blood Pact: Rage');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##rage" .. configKey, colorConfig.timerBPRageReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##rage" .. configKey, colorConfig.timerBPRageRecastGradient, "Gradient when on cooldown");

            imgui.Text('Blood Pact: Ward');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##ward" .. configKey, colorConfig.timerBPWardReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##ward" .. configKey, colorConfig.timerBPWardRecastGradient, "Gradient when on cooldown");

            imgui.Text('Apogee');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##apogee" .. configKey, colorConfig.timerApogeeReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##apogee" .. configKey, colorConfig.timerApogeeRecastGradient, "Gradient when on cooldown");

            imgui.Text('Mana Cede');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##manacede" .. configKey, colorConfig.timerManaCedeReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##manacede" .. configKey, colorConfig.timerManaCedeRecastGradient, "Gradient when on cooldown");

            imgui.Text('Astral Flow');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##2h" .. configKey, colorConfig.timer2hReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##2h" .. configKey, colorConfig.timer2hRecastGradient, "Gradient when on cooldown");
        end
    end

    -- Charm (BST charmed pets) specific color settings
    if configKey == 'petBarCharm' then
        if components.CollapsingSection('Charm Indicator Colors##' .. configKey .. 'color', false) then
            if colorConfig.charmHeartColor == nil then colorConfig.charmHeartColor = 0xFFFF6699; end
            if colorConfig.charmTimerColor == nil then colorConfig.charmTimerColor = 0xFFFFFFFF; end
            if colorConfig.durationWarningColor == nil then colorConfig.durationWarningColor = 0xFFFF6600; end

            components.DrawTextColorPicker("Charm Heart##" .. configKey, colorConfig, 'charmHeartColor', "Color of heart icon for charmed pets");
            components.DrawTextColorPicker("Timer Text##" .. configKey, colorConfig, 'charmTimerColor', "Color of pet timer text");
            components.DrawTextColorPicker("Duration Warning##" .. configKey, colorConfig, 'durationWarningColor', "Color when charm is about to break");
        end

        if components.CollapsingSection('Ability Timer Colors##' .. configKey .. 'color', false) then
            if colorConfig.timerReadyReadyGradient == nil then colorConfig.timerReadyReadyGradient = T{ enabled = true, start = '#ff6600e6', stop = '#ff9933e6' }; end
            if colorConfig.timerReadyRecastGradient == nil then colorConfig.timerReadyRecastGradient = T{ enabled = true, start = '#ff9933d9', stop = '#ffbb66d9' }; end
            if colorConfig.timerRewardReadyGradient == nil then colorConfig.timerRewardReadyGradient = T{ enabled = true, start = '#00cc66e6', stop = '#66dd99e6' }; end
            if colorConfig.timerRewardRecastGradient == nil then colorConfig.timerRewardRecastGradient = T{ enabled = true, start = '#66dd99d9', stop = '#99eebbd9' }; end
            if colorConfig.timer2hReadyGradient == nil then colorConfig.timer2hReadyGradient = T{ enabled = true, start = '#ff00ffe6', stop = '#ff66ffe6' }; end
            if colorConfig.timer2hRecastGradient == nil then colorConfig.timer2hRecastGradient = T{ enabled = true, start = '#ff66ffd9', stop = '#ff99ffd9' }; end

            -- Column headers
            imgui.Text(''); imgui.SameLine(120); imgui.Text('Ready'); imgui.SameLine(120 + components.COLOR_COLUMN_SPACING); imgui.Text('Recast');

            imgui.Text('Ready/Sic');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##ready" .. configKey, colorConfig.timerReadyReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##ready" .. configKey, colorConfig.timerReadyRecastGradient, "Gradient when on cooldown");

            imgui.Text('Reward');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##reward" .. configKey, colorConfig.timerRewardReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##reward" .. configKey, colorConfig.timerRewardRecastGradient, "Gradient when on cooldown");

            imgui.Text('Familiar');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##2h" .. configKey, colorConfig.timer2hReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##2h" .. configKey, colorConfig.timer2hRecastGradient, "Gradient when on cooldown");
        end
    end

    -- Jug (BST jug pets) specific color settings
    if configKey == 'petBarJug' then
        if components.CollapsingSection('Jug Pet Indicator Colors##' .. configKey .. 'color', false) then
            if colorConfig.jugIconColor == nil then colorConfig.jugIconColor = 0xFFFFFFFF; end
            if colorConfig.charmTimerColor == nil then colorConfig.charmTimerColor = 0xFFFFFFFF; end
            if colorConfig.durationWarningColor == nil then colorConfig.durationWarningColor = 0xFFFF6600; end

            components.DrawTextColorPicker("Jug Icon##" .. configKey, colorConfig, 'jugIconColor', "Color of jug icon");
            components.DrawTextColorPicker("Timer Text##" .. configKey, colorConfig, 'charmTimerColor', "Color of pet timer text");
            components.DrawTextColorPicker("Duration Warning##" .. configKey, colorConfig, 'durationWarningColor', "Color when jug pet duration is low");
        end

        if components.CollapsingSection('Ability Timer Colors##' .. configKey .. 'color', false) then
            if colorConfig.timerReadyReadyGradient == nil then colorConfig.timerReadyReadyGradient = T{ enabled = true, start = '#ff6600e6', stop = '#ff9933e6' }; end
            if colorConfig.timerReadyRecastGradient == nil then colorConfig.timerReadyRecastGradient = T{ enabled = true, start = '#ff9933d9', stop = '#ffbb66d9' }; end
            if colorConfig.timerRewardReadyGradient == nil then colorConfig.timerRewardReadyGradient = T{ enabled = true, start = '#00cc66e6', stop = '#66dd99e6' }; end
            if colorConfig.timerRewardRecastGradient == nil then colorConfig.timerRewardRecastGradient = T{ enabled = true, start = '#66dd99d9', stop = '#99eebbd9' }; end
            if colorConfig.timerCallBeastReadyGradient == nil then colorConfig.timerCallBeastReadyGradient = T{ enabled = true, start = '#3399ffe6', stop = '#66bbffe6' }; end
            if colorConfig.timerCallBeastRecastGradient == nil then colorConfig.timerCallBeastRecastGradient = T{ enabled = true, start = '#66bbffd9', stop = '#99ccffd9' }; end
            if colorConfig.timerBestialLoyaltyReadyGradient == nil then colorConfig.timerBestialLoyaltyReadyGradient = T{ enabled = true, start = '#9966ffe6', stop = '#bb99ffe6' }; end
            if colorConfig.timerBestialLoyaltyRecastGradient == nil then colorConfig.timerBestialLoyaltyRecastGradient = T{ enabled = true, start = '#bb99ffd9', stop = '#ccaaffd9' }; end
            if colorConfig.timer2hReadyGradient == nil then colorConfig.timer2hReadyGradient = T{ enabled = true, start = '#ff00ffe6', stop = '#ff66ffe6' }; end
            if colorConfig.timer2hRecastGradient == nil then colorConfig.timer2hRecastGradient = T{ enabled = true, start = '#ff66ffd9', stop = '#ff99ffd9' }; end

            -- Column headers
            imgui.Text(''); imgui.SameLine(120); imgui.Text('Ready'); imgui.SameLine(120 + components.COLOR_COLUMN_SPACING); imgui.Text('Recast');

            imgui.Text('Ready/Sic');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##ready" .. configKey, colorConfig.timerReadyReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##ready" .. configKey, colorConfig.timerReadyRecastGradient, "Gradient when on cooldown");

            imgui.Text('Reward');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##reward" .. configKey, colorConfig.timerRewardReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##reward" .. configKey, colorConfig.timerRewardRecastGradient, "Gradient when on cooldown");

            imgui.Text('Call Beast');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##callbeast" .. configKey, colorConfig.timerCallBeastReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##callbeast" .. configKey, colorConfig.timerCallBeastRecastGradient, "Gradient when on cooldown");

            imgui.Text('Bestial Loyalty');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##bestialloyalty" .. configKey, colorConfig.timerBestialLoyaltyReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##bestialloyalty" .. configKey, colorConfig.timerBestialLoyaltyRecastGradient, "Gradient when on cooldown");

            imgui.Text('Familiar');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##2h" .. configKey, colorConfig.timer2hReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##2h" .. configKey, colorConfig.timer2hRecastGradient, "Gradient when on cooldown");
        end
    end

    -- Automaton (PUP) specific color settings
    if configKey == 'petBarAutomaton' then
        if components.CollapsingSection('Ability Timer Colors##' .. configKey .. 'color', false) then
            if colorConfig.timerActivateReadyGradient == nil then colorConfig.timerActivateReadyGradient = T{ enabled = true, start = '#3399ffe6', stop = '#66bbffe6' }; end
            if colorConfig.timerActivateRecastGradient == nil then colorConfig.timerActivateRecastGradient = T{ enabled = true, start = '#66bbffd9', stop = '#99ccffd9' }; end
            if colorConfig.timerRepairReadyGradient == nil then colorConfig.timerRepairReadyGradient = T{ enabled = true, start = '#33cc66e6', stop = '#66dd99e6' }; end
            if colorConfig.timerRepairRecastGradient == nil then colorConfig.timerRepairRecastGradient = T{ enabled = true, start = '#66dd99d9', stop = '#99eebbd9' }; end
            if colorConfig.timerDeployReadyGradient == nil then colorConfig.timerDeployReadyGradient = T{ enabled = true, start = '#ff9933e6', stop = '#ffbb66e6' }; end
            if colorConfig.timerDeployRecastGradient == nil then colorConfig.timerDeployRecastGradient = T{ enabled = true, start = '#ffbb66d9', stop = '#ffcc99d9' }; end
            if colorConfig.timerDeactivateReadyGradient == nil then colorConfig.timerDeactivateReadyGradient = T{ enabled = true, start = '#999999e6', stop = '#bbbbbbe6' }; end
            if colorConfig.timerDeactivateRecastGradient == nil then colorConfig.timerDeactivateRecastGradient = T{ enabled = true, start = '#bbbbbbd9', stop = '#ccccccd9' }; end
            if colorConfig.timerRetrieveReadyGradient == nil then colorConfig.timerRetrieveReadyGradient = T{ enabled = true, start = '#66ccffe6', stop = '#99ddffe6' }; end
            if colorConfig.timerRetrieveRecastGradient == nil then colorConfig.timerRetrieveRecastGradient = T{ enabled = true, start = '#99ddffd9', stop = '#bbeeffd9' }; end
            if colorConfig.timerDeusExAutomataReadyGradient == nil then colorConfig.timerDeusExAutomataReadyGradient = T{ enabled = true, start = '#ffcc33e6', stop = '#ffdd66e6' }; end
            if colorConfig.timerDeusExAutomataRecastGradient == nil then colorConfig.timerDeusExAutomataRecastGradient = T{ enabled = true, start = '#ffdd66d9', stop = '#ffee99d9' }; end
            if colorConfig.timer2hReadyGradient == nil then colorConfig.timer2hReadyGradient = T{ enabled = true, start = '#ff00ffe6', stop = '#ff66ffe6' }; end
            if colorConfig.timer2hRecastGradient == nil then colorConfig.timer2hRecastGradient = T{ enabled = true, start = '#ff66ffd9', stop = '#ff99ffd9' }; end

            -- Column headers
            imgui.Text(''); imgui.SameLine(120); imgui.Text('Ready'); imgui.SameLine(120 + components.COLOR_COLUMN_SPACING); imgui.Text('Recast');

            imgui.Text('Activate');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##activate" .. configKey, colorConfig.timerActivateReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##activate" .. configKey, colorConfig.timerActivateRecastGradient, "Gradient when on cooldown");

            imgui.Text('Repair');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##repair" .. configKey, colorConfig.timerRepairReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##repair" .. configKey, colorConfig.timerRepairRecastGradient, "Gradient when on cooldown");

            imgui.Text('Deploy');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##deploy" .. configKey, colorConfig.timerDeployReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##deploy" .. configKey, colorConfig.timerDeployRecastGradient, "Gradient when on cooldown");

            imgui.Text('Deactivate');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##deactivate" .. configKey, colorConfig.timerDeactivateReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##deactivate" .. configKey, colorConfig.timerDeactivateRecastGradient, "Gradient when on cooldown");

            imgui.Text('Retrieve');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##retrieve" .. configKey, colorConfig.timerRetrieveReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##retrieve" .. configKey, colorConfig.timerRetrieveRecastGradient, "Gradient when on cooldown");

            imgui.Text('Deus Ex Automata');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##deusex" .. configKey, colorConfig.timerDeusExAutomataReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##deusex" .. configKey, colorConfig.timerDeusExAutomataRecastGradient, "Gradient when on cooldown");

            imgui.Text('Overdrive');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##2h" .. configKey, colorConfig.timer2hReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##2h" .. configKey, colorConfig.timer2hRecastGradient, "Gradient when on cooldown");
        end
    end

    -- Wyvern (DRG) specific color settings
    if configKey == 'petBarWyvern' then
        if components.CollapsingSection('Ability Timer Colors##' .. configKey .. 'color', false) then
            if colorConfig.timerCallWyvernReadyGradient == nil then colorConfig.timerCallWyvernReadyGradient = T{ enabled = true, start = '#3366ffe6', stop = '#6699ffe6' }; end
            if colorConfig.timerCallWyvernRecastGradient == nil then colorConfig.timerCallWyvernRecastGradient = T{ enabled = true, start = '#6699ffd9', stop = '#99bbffd9' }; end
            if colorConfig.timerSpiritLinkReadyGradient == nil then colorConfig.timerSpiritLinkReadyGradient = T{ enabled = true, start = '#33cc33e6', stop = '#66dd66e6' }; end
            if colorConfig.timerSpiritLinkRecastGradient == nil then colorConfig.timerSpiritLinkRecastGradient = T{ enabled = true, start = '#66dd66d9', stop = '#99ee99d9' }; end
            if colorConfig.timerDeepBreathingReadyGradient == nil then colorConfig.timerDeepBreathingReadyGradient = T{ enabled = true, start = '#ffff33e6', stop = '#ffff99e6' }; end
            if colorConfig.timerDeepBreathingRecastGradient == nil then colorConfig.timerDeepBreathingRecastGradient = T{ enabled = true, start = '#ffff99d9', stop = '#ffffc0d9' }; end
            if colorConfig.timerSteadyWingReadyGradient == nil then colorConfig.timerSteadyWingReadyGradient = T{ enabled = true, start = '#cc66ffe6', stop = '#dd99ffe6' }; end
            if colorConfig.timerSteadyWingRecastGradient == nil then colorConfig.timerSteadyWingRecastGradient = T{ enabled = true, start = '#dd99ffd9', stop = '#eeaaffd9' }; end
            if colorConfig.timer2hReadyGradient == nil then colorConfig.timer2hReadyGradient = T{ enabled = true, start = '#ff00ffe6', stop = '#ff66ffe6' }; end
            if colorConfig.timer2hRecastGradient == nil then colorConfig.timer2hRecastGradient = T{ enabled = true, start = '#ff66ffd9', stop = '#ff99ffd9' }; end

            -- Column headers
            imgui.Text(''); imgui.SameLine(120); imgui.Text('Ready'); imgui.SameLine(120 + components.COLOR_COLUMN_SPACING); imgui.Text('Recast');

            imgui.Text('Call Wyvern');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##callwyvern" .. configKey, colorConfig.timerCallWyvernReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##callwyvern" .. configKey, colorConfig.timerCallWyvernRecastGradient, "Gradient when on cooldown");

            imgui.Text('Spirit Link');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##spiritlink" .. configKey, colorConfig.timerSpiritLinkReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##spiritlink" .. configKey, colorConfig.timerSpiritLinkRecastGradient, "Gradient when on cooldown");

            imgui.Text('Deep Breathing');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##deepbreathing" .. configKey, colorConfig.timerDeepBreathingReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##deepbreathing" .. configKey, colorConfig.timerDeepBreathingRecastGradient, "Gradient when on cooldown");

            imgui.Text('Steady Wing');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##steadywing" .. configKey, colorConfig.timerSteadyWingReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##steadywing" .. configKey, colorConfig.timerSteadyWingRecastGradient, "Gradient when on cooldown");

            imgui.Text('Spirit Surge');
            imgui.SameLine(120);
            components.DrawGradientPickerColumn("Ready##2h" .. configKey, colorConfig.timer2hReadyGradient, "Gradient when ability is ready");
            imgui.SameLine(120 + components.COLOR_COLUMN_SPACING);
            components.DrawGradientPickerColumn("Recast##2h" .. configKey, colorConfig.timer2hRecastGradient, "Gradient when on cooldown");
        end
    end

    if components.CollapsingSection('Background Colors##' .. configKey .. 'color', false) then
        if colorConfig.bgColor == nil then colorConfig.bgColor = 0xFFFFFFFF; end
        if colorConfig.borderColor == nil then colorConfig.borderColor = 0xFFFFFFFF; end

        components.DrawTextColorPicker("Background Tint##" .. configKey, colorConfig, 'bgColor', "Tint color for background");
        components.DrawTextColorPicker("Border Color##" .. configKey, colorConfig, 'borderColor', "Color of window borders");
    end
end

-- Helper: Draw Pet Bar specific settings (used in tab)
local function DrawPetBarSettingsContent()
    components.DrawCheckbox('Enabled', 'showPetBar', CheckVisibility);
    components.DrawCheckbox('Hide When Menu Open', 'petBarHideOnMenuFocus');
    imgui.ShowHelp('Hide this module when a game menu is open (equipment, map, etc.).');
    components.DrawCheckbox('Hide During Events', 'petBarHideDuringEvents');
    components.DrawCheckbox('Preview Mode', 'petBarPreview');
    imgui.ShowHelp('Show the pet bar with mock data. Preview shows the pet type from the selected tab below.');
end

-- Helper: Draw Pet Target specific settings (used in tab)
local function DrawPetTargetSettingsContent()
    components.DrawCheckbox('Show Pet Target', 'petBarShowTarget');
    imgui.ShowHelp('Show information about what the pet is targeting in a separate window.');

    components.DrawCheckbox('Snap to Pet Bar', 'petTargetSnapToPetBar');
    imgui.ShowHelp('Position the pet target window directly below the pet bar.');

    if gConfig.petTargetSnapToPetBar then
        components.DrawSlider('Snap Offset X##petTargetSnap', 'petTargetSnapOffsetX', -200, 200);
        components.DrawSlider('Snap Offset Y##petTargetSnap', 'petTargetSnapOffsetY', -200, 200);
    end

    if components.CollapsingSection('Display Options##petTarget', false) then
        components.DrawSlider('Text Size', 'petBarTargetFontSize', 6, 24);
        imgui.ShowHelp('Font size for pet target text.');

        imgui.Spacing();

        -- Target Name positioning
        imgui.Text('Target Name');
        imgui.SameLine();
        imgui.SetNextItemWidth(120);
        local namePositionModes = {'Anchored', 'Absolute'};
        local nameCurrentMode = gConfig.petTargetNameAbsolute and 'Absolute' or 'Anchored';
        components.DrawComboBox('Position Mode##petTargetName', nameCurrentMode, namePositionModes, function(newValue)
            local wasAbsolute = gConfig.petTargetNameAbsolute;
            gConfig.petTargetNameAbsolute = (newValue == 'Absolute');
            -- Reset offsets when switching modes
            if wasAbsolute ~= gConfig.petTargetNameAbsolute and not gConfig.petTargetNameAbsolute then
                gConfig.petTargetNameOffsetX = 0;
                gConfig.petTargetNameOffsetY = 0;
            end
            SaveSettingsOnly();
        end);
        imgui.ShowHelp('Anchored: Name flows within layout.\nAbsolute: Name positioned relative to window top-left.');

        if gConfig.petTargetNameAbsolute then
            components.DrawSlider('Offset X##petTargetName', 'petTargetNameOffsetX', -200, 200);
            imgui.ShowHelp('Horizontal offset from window left.');
            components.DrawSlider('Offset Y##petTargetName', 'petTargetNameOffsetY', -200, 200);
            imgui.ShowHelp('Vertical offset from window top.');
        end

        imgui.Spacing();

        -- HP% positioning
        imgui.Text('HP%');
        imgui.SameLine();
        imgui.SetNextItemWidth(120);
        local hpPositionModes = {'Anchored', 'Absolute'};
        local hpCurrentMode = gConfig.petTargetHpAbsolute and 'Absolute' or 'Anchored';
        components.DrawComboBox('Position Mode##petTargetHp', hpCurrentMode, hpPositionModes, function(newValue)
            local wasAbsolute = gConfig.petTargetHpAbsolute;
            gConfig.petTargetHpAbsolute = (newValue == 'Absolute');
            -- Reset offsets when switching modes
            if wasAbsolute ~= gConfig.petTargetHpAbsolute and not gConfig.petTargetHpAbsolute then
                gConfig.petTargetHpOffsetX = 0;
                gConfig.petTargetHpOffsetY = 0;
            end
            SaveSettingsOnly();
        end);
        imgui.ShowHelp('Anchored: HP% right-aligned on name row.\nAbsolute: HP% positioned relative to window top-left.');

        if gConfig.petTargetHpAbsolute then
            components.DrawSlider('Offset X##petTargetHp', 'petTargetHpOffsetX', -200, 200);
            imgui.ShowHelp('Horizontal offset from window left.');
            components.DrawSlider('Offset Y##petTargetHp', 'petTargetHpOffsetY', -200, 200);
            imgui.ShowHelp('Vertical offset from window top.');
        end

        imgui.Spacing();

        -- Distance positioning
        imgui.Text('Distance');
        imgui.SameLine();
        imgui.SetNextItemWidth(120);
        local distPositionModes = {'Anchored', 'Absolute'};
        local distCurrentMode = gConfig.petTargetDistanceAbsolute and 'Absolute' or 'Anchored';
        components.DrawComboBox('Position Mode##petTargetDistance', distCurrentMode, distPositionModes, function(newValue)
            local wasAbsolute = gConfig.petTargetDistanceAbsolute;
            gConfig.petTargetDistanceAbsolute = (newValue == 'Absolute');
            -- Reset offsets when switching modes
            if wasAbsolute ~= gConfig.petTargetDistanceAbsolute and not gConfig.petTargetDistanceAbsolute then
                gConfig.petTargetDistanceOffsetX = 0;
                gConfig.petTargetDistanceOffsetY = 0;
            end
            SaveSettingsOnly();
        end);
        imgui.ShowHelp('Anchored: Distance below HP bar.\nAbsolute: Distance positioned relative to window top-left.');

        if gConfig.petTargetDistanceAbsolute then
            components.DrawSlider('Offset X##petTargetDistance', 'petTargetDistanceOffsetX', -200, 200);
            imgui.ShowHelp('Horizontal offset from window left.');
            components.DrawSlider('Offset Y##petTargetDistance', 'petTargetDistanceOffsetY', -200, 200);
            imgui.ShowHelp('Vertical offset from window top.');
        end
    end

    if components.CollapsingSection('Bar Scale##petTarget', false) then
        components.DrawSlider('Scale X##petTargetBar', 'petTargetBarScaleX', 0.5, 2.0, '%.1f');
        imgui.ShowHelp('Horizontal scale of the HP bar.');
        components.DrawSlider('Scale Y##petTargetBar', 'petTargetBarScaleY', 0.5, 2.0, '%.1f');
        imgui.ShowHelp('Vertical scale of the HP bar.');
    end

    if components.CollapsingSection('Background##petTarget', false) then
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
-- state.selectedPetTypeTab: pet type sub-tab selection (1=Avatar, 2=Charm, etc.)
function M.DrawSettings(state)
    local selectedPetBarTab = state.selectedPetBarTab or 1;
    local selectedPetTypeTab = state.selectedPetTypeTab or 1;

    -- Sync preview type with selected pet type tab
    local currentPetType = PET_TYPES[selectedPetTypeTab];
    if currentPetType and gConfig.petBarPreviewType ~= currentPetType.previewType then
        gConfig.petBarPreviewType = currentPetType.previewType;
    end

    -- Pet Bar / Pet Target tabs
    if components.DrawStyledTab('Pet Bar', 'petBarTab', selectedPetBarTab == 1) then
        selectedPetBarTab = 1;
    end
    imgui.SameLine();
    if components.DrawStyledTab('Pet Target', 'petBarTab', selectedPetBarTab == 2) then
        selectedPetBarTab = 2;
    end

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Draw settings based on selected tab
    if selectedPetBarTab == 1 then
        -- Draw global pet bar settings first
        DrawPetBarSettingsContent();

        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();

        -- Pet Type Sub-Tabs
        imgui.TextColored(components.TAB_STYLE.gold, 'Per-Pet-Type Visual Settings');
        imgui.ShowHelp('Customize the appearance for each pet type independently.');
        imgui.Spacing();

        -- Draw pet type sub-tabs
        for i, petType in ipairs(PET_TYPES) do
            if components.DrawStyledTab(petType.label, 'petTypeTab', selectedPetTypeTab == i, nil, components.TAB_STYLE.smallHeight, components.TAB_STYLE.smallPadding) then
                selectedPetTypeTab = i;
                gConfig.petBarPreviewType = petType.previewType;
            end
            if i < #PET_TYPES then
                imgui.SameLine();
            end
        end

        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();

        -- Draw per-type settings for selected pet type
        currentPetType = PET_TYPES[selectedPetTypeTab];
        if currentPetType then
            -- Copy buttons
            DrawPetTypeCopyButtons(currentPetType.configKey, currentPetType.label, 'Settings');

            -- Per-type visual settings
            DrawPetTypeVisualSettings(currentPetType.configKey, currentPetType.label);
        end
    else
        DrawPetTargetSettingsContent();
    end

    -- Return updated state
    return { selectedPetBarTab = selectedPetBarTab, selectedPetTypeTab = selectedPetTypeTab };
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

    if components.CollapsingSection('Bar Colors##petBarColor', false) then
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

    if components.CollapsingSection('Text Colors##petBarColor', false) then
        components.DrawTextColorPicker("Pet Name", gConfig.colorCustomization.petBar, 'nameTextColor', "Color of pet name text");
        components.DrawTextColorPicker("Distance", gConfig.colorCustomization.petBar, 'distanceTextColor', "Color of distance text");
        components.DrawTextColorPicker("HP Text", gConfig.colorCustomization.petBar, 'hpTextColor', "Color of HP value text");
        components.DrawTextColorPicker("MP Text", gConfig.colorCustomization.petBar, 'mpTextColor', "Color of MP value text");
        components.DrawTextColorPicker("TP Text", gConfig.colorCustomization.petBar, 'tpTextColor', "Color of TP value text");
    end

    if components.CollapsingSection('Background Colors##petBarColor', false) then
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
            hpTextColor = 0xFFFFA7A7,
            distanceTextColor = 0xFFFFFFFF,
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
    -- Ensure hpTextColor exists (for existing configs)
    if gConfig.colorCustomization.petTarget.hpTextColor == nil then
        gConfig.colorCustomization.petTarget.hpTextColor = 0xFFFFA7A7;
    end
    -- Ensure distanceTextColor exists (for existing configs)
    if gConfig.colorCustomization.petTarget.distanceTextColor == nil then
        gConfig.colorCustomization.petTarget.distanceTextColor = 0xFFFFFFFF;
    end

    if components.CollapsingSection('Bar Colors##petTargetColor', false) then
        components.DrawGradientPickerColumn("HP Bar##petTarget", gConfig.colorCustomization.petTarget.hpGradient, "Pet target HP bar color gradient");
    end

    if components.CollapsingSection('Text Colors##petTargetColor', false) then
        components.DrawTextColorPicker("Target Name", gConfig.colorCustomization.petTarget, 'targetTextColor', "Color of pet target name text");
        components.DrawTextColorPicker("HP%", gConfig.colorCustomization.petTarget, 'hpTextColor', "Color of HP percent text");
        components.DrawTextColorPicker("Distance", gConfig.colorCustomization.petTarget, 'distanceTextColor', "Color of distance text");
    end

    if components.CollapsingSection('Background Colors##petTargetColor', false) then
        components.DrawTextColorPicker("Background Tint", gConfig.colorCustomization.petTarget, 'bgColor', "Tint color for background");
        components.DrawTextColorPicker("Border Color", gConfig.colorCustomization.petTarget, 'borderColor', "Color of window borders (Window themes only)");
    end
end

-- Section: Pet Bar Color Settings (with tabs for Pet Bar / Pet Target)
-- state.selectedPetBarColorTab: tab selection state
-- state.selectedPetTypeColorTab: pet type sub-tab selection for colors
function M.DrawColorSettings(state)
    local selectedPetBarColorTab = state.selectedPetBarColorTab or 1;
    local selectedPetTypeColorTab = state.selectedPetTypeColorTab or 1;

    -- Sync preview type with selected pet type color tab
    local currentPetType = PET_TYPES[selectedPetTypeColorTab];
    if currentPetType and gConfig.petBarPreviewType ~= currentPetType.previewType then
        gConfig.petBarPreviewType = currentPetType.previewType;
    end

    -- Pet Bar / Pet Target tabs
    if components.DrawStyledTab('Pet Bar', 'petBarColorTab', selectedPetBarColorTab == 1) then
        selectedPetBarColorTab = 1;
    end
    imgui.SameLine();
    if components.DrawStyledTab('Pet Target', 'petBarColorTab', selectedPetBarColorTab == 2) then
        selectedPetBarColorTab = 2;
    end

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Draw color settings based on selected tab
    if selectedPetBarColorTab == 1 then
        -- Draw pet type sub-tabs
        for i, petType in ipairs(PET_TYPES) do
            if components.DrawStyledTab(petType.label, 'petTypeColorTab', selectedPetTypeColorTab == i, nil, components.TAB_STYLE.smallHeight, components.TAB_STYLE.smallPadding) then
                selectedPetTypeColorTab = i;
                gConfig.petBarPreviewType = petType.previewType;
            end
            if i < #PET_TYPES then
                imgui.SameLine();
            end
        end

        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();

        -- Draw per-type color settings for selected pet type
        currentPetType = PET_TYPES[selectedPetTypeColorTab];
        if currentPetType then
            -- Copy buttons
            DrawPetTypeCopyButtons(currentPetType.configKey, currentPetType.label, 'Colors');

            -- Per-type color settings
            DrawPetTypeColorSettings(currentPetType.configKey, currentPetType.label);
        end
    else
        DrawPetTargetColorSettingsContent();
    end

    -- Return updated state
    return { selectedPetBarColorTab = selectedPetBarColorTab, selectedPetTypeColorTab = selectedPetTypeColorTab };
end

return M;
