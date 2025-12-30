--[[
* XIUI Config Menu - Party List Settings
* Contains settings and color settings for Party List (A/B/C)
]]--

require('common');
require('handlers.helpers');
local components = require('config.components');
local statusHandler = require('handlers.statushandler');
local imgui = require('imgui');

local M = {};

-- Helper function to copy all settings from one party to another
local function CopyPartySettings(sourcePartyName, targetPartyName)
    -- Get source and target party tables
    local sourceParty = gConfig['party' .. sourcePartyName];
    local targetParty = gConfig['party' .. targetPartyName];

    -- Copy regular settings (deep copy to avoid reference issues)
    local sourceCopy = deep_copy_table(sourceParty);
    for key, value in pairs(sourceCopy) do
        targetParty[key] = value;
    end

    -- Get source and target color tables
    local sourceColors = gConfig.colorCustomization['partyList' .. sourcePartyName];
    local targetColors = gConfig.colorCustomization['partyList' .. targetPartyName];

    -- Copy color settings (deep copy)
    local sourceColorsCopy = deep_copy_table(sourceColors);
    for key, value in pairs(sourceColorsCopy) do
        targetColors[key] = value;
    end

    -- Save and update
    UpdateSettings();
end

-- Helper function to draw per-party settings tab content
local function DrawPartyTabContent(party, partyName)
    local layoutItems = { [0] = 'Horizontal', [1] = 'Compact Vertical' };
    local statusThemeItems = { [0] = 'HorizonXI', [1] = 'HorizonXI-R', [2] = 'FFXIV', [3] = 'FFXI', [4] = 'Disabled' };
    local statusSideItems = { [0] = 'Left', [1] = 'Right' };
    local bg_theme_paths = statusHandler.get_background_paths();
    local cursor_paths = statusHandler.get_cursor_paths();

    -- Copy settings section (only for Party B and C)
    if partyName == 'B' or partyName == 'C' then
        imgui.Text('Copy Settings');
        imgui.Separator();
        imgui.Spacing();

        -- Build list of other parties to copy from
        local copyOptions = {};
        if partyName == 'B' then
            copyOptions = { 'A', 'C' };
        else -- partyName == 'C'
            copyOptions = { 'A', 'B' };
        end

        imgui.Text('Copy all settings from another party:');
        for _, sourceName in ipairs(copyOptions) do
            imgui.SameLine();
            if imgui.Button('Party ' .. sourceName .. '##copy_from_' .. sourceName .. '_to_' .. partyName) then
                CopyPartySettings(sourceName, partyName);
            end
        end
        imgui.ShowHelp('Copies all settings and colors from the selected party to this one.');

        imgui.Spacing();
    end

    -- Layout Selector
    components.DrawPartyComboBoxIndexed(party, 'Layout', 'layout', layoutItems, function()
        if partyList ~= nil then
            partyList.UpdateVisuals(gAdjustedSettings.partyListSettings);
        end
    end);

    if components.CollapsingSection('Display Options##party' .. partyName) then
        components.DrawPartyCheckbox(party, 'Show TP', 'showTP');
        if party.showTP then
            components.DrawPartyCheckbox(party, 'Flash TP at 100%', 'flashTP');
            if party.layout == 1 then
                imgui.ShowHelp('In compact mode, the TP text will flash when at 1000+ TP.');
            end
        end
        components.DrawPartyCheckbox(party, 'Show Distance', 'showDistance');
        if party.showDistance then
            imgui.SameLine();
            imgui.PushItemWidth(100);
            components.DrawPartySlider(party, 'Highlight', 'distanceHighlight', 0.0, 50.0, '%.1f');
            imgui.PopItemWidth();
        end
        components.DrawPartyCheckbox(party, 'Show Bookends', 'showBookends');
        components.DrawPartyCheckbox(party, 'Show Title', 'showTitle');
        components.DrawPartyCheckbox(party, 'Align Bottom', 'alignBottom');
        components.DrawPartyCheckbox(party, 'Expand Height', 'expandHeight');

        -- HP Display Mode dropdown
        components.DrawDisplayModeDropdown('HP Display##party' .. partyName, party, 'hpDisplayMode',
            'How HP is displayed: number (1234), percent (100%), number first (1234 (100%)), percent first (100% (1234)), or current/max (1234/1500).');

        -- MP Display Mode dropdown
        components.DrawDisplayModeDropdown('MP Display##party' .. partyName, party, 'mpDisplayMode',
            'How MP is displayed: number (1234), percent (100%), number first (1234 (100%)), percent first (100% (1234)), or current/max (750/1000).');

        components.DrawPartyCheckbox(party, 'Always Show MP Bar', 'alwaysShowMpBar');
        imgui.ShowHelp('When disabled, hides the MP bar for jobs without MP (WAR, MNK, THF, etc.). Cast bars will still appear when casting.');
    end

    if components.CollapsingSection('Scale & Spacing##party' .. partyName) then
        components.DrawPartySlider(party, 'Min Rows', 'minRows', 1, 6);
        components.DrawPartySlider(party, 'Entry Spacing', 'entrySpacing', -50, 50);
        components.DrawPartySlider(party, 'Selection Box Scale Y', 'selectionBoxScaleY', 0.5, 2.0, '%.2f');
        components.DrawPartySlider(party, 'Selection Box Offset Y', 'selectionBoxOffsetY', -50, 50);

        -- General scale controls (applies to all elements)
        components.DrawPartySlider(party, 'Scale X', 'scaleX', 0.1, 3.0, '%.2f');
        components.DrawPartySlider(party, 'Scale Y', 'scaleY', 0.1, 3.0, '%.2f');
    end

    if components.CollapsingSection('Bar Scales##party' .. partyName) then
        components.DrawPartySlider(party, 'HP Bar Scale X', 'hpBarScaleX', 0.1, 3.0, '%.2f');
        components.DrawPartySlider(party, 'HP Bar Scale Y', 'hpBarScaleY', 0.1, 3.0, '%.2f');
        components.DrawPartySlider(party, 'MP Bar Scale X', 'mpBarScaleX', 0.1, 3.0, '%.2f');
        components.DrawPartySlider(party, 'MP Bar Scale Y', 'mpBarScaleY', 0.1, 3.0, '%.2f');
        if party.showTP then
            components.DrawPartySlider(party, 'TP Bar Scale X', 'tpBarScaleX', 0.1, 3.0, '%.2f');
            components.DrawPartySlider(party, 'TP Bar Scale Y', 'tpBarScaleY', 0.1, 3.0, '%.2f');
        end
    end

    if components.CollapsingSection('Text Settings##party' .. partyName) then
        components.DrawPartyCheckbox(party, 'Split Text Sizes', 'splitFontSizes');
        imgui.ShowHelp('When enabled, allows individual text size control for each element.');

        if party.splitFontSizes then
            components.DrawPartySlider(party, 'Name Text Size', 'nameFontSize', 8, 36);
            components.DrawPartySlider(party, 'HP Text Size', 'hpFontSize', 8, 36);
            components.DrawPartySlider(party, 'MP Text Size', 'mpFontSize', 8, 36);
            components.DrawPartySlider(party, 'TP Text Size', 'tpFontSize', 8, 36);
            components.DrawPartySlider(party, 'Distance Text Size', 'distanceFontSize', 8, 36);
            if party.showJob then
                components.DrawPartySlider(party, 'Job Text Size', 'jobFontSize', 8, 36);
            end
            components.DrawPartySlider(party, 'Zone Text Size', 'zoneFontSize', 8, 36);
        else
            components.DrawPartySlider(party, 'Text Size', 'fontSize', 8, 36);
        end
    end

    if components.CollapsingSection('Text Offsets##party' .. partyName, false) then
        imgui.Text('Name Text');
        components.DrawPartySlider(party, 'X Offset##nameText', 'nameTextOffsetX', -50, 50);
        components.DrawPartySlider(party, 'Y Offset##nameText', 'nameTextOffsetY', -50, 50);

        imgui.Spacing();
        imgui.Text('HP Text');
        components.DrawPartySlider(party, 'X Offset##hpText', 'hpTextOffsetX', -50, 50);
        components.DrawPartySlider(party, 'Y Offset##hpText', 'hpTextOffsetY', -50, 50);

        imgui.Spacing();
        imgui.Text('MP Text');
        components.DrawPartySlider(party, 'X Offset##mpText', 'mpTextOffsetX', -50, 50);
        components.DrawPartySlider(party, 'Y Offset##mpText', 'mpTextOffsetY', -50, 50);

        if party.showTP then
            imgui.Spacing();
            imgui.Text('TP Text');
            components.DrawPartySlider(party, 'X Offset##tpText', 'tpTextOffsetX', -50, 50);
            components.DrawPartySlider(party, 'Y Offset##tpText', 'tpTextOffsetY', -50, 50);
        end

        if party.showDistance then
            imgui.Spacing();
            imgui.Text('Distance Text');
            components.DrawPartySlider(party, 'X Offset##distText', 'distanceTextOffsetX', -200, 200);
            components.DrawPartySlider(party, 'Y Offset##distText', 'distanceTextOffsetY', -200, 200);
        end

        if party.showJob and party.layout == 0 then
            imgui.Spacing();
            imgui.Text('Job Text');
            components.DrawPartySlider(party, 'X Offset##jobText', 'jobTextOffsetX', -50, 50);
            components.DrawPartySlider(party, 'Y Offset##jobText', 'jobTextOffsetY', -50, 50);
        end
    end

    if components.CollapsingSection('Background##party' .. partyName) then
        components.DrawPartyComboBox(party, 'Background', 'backgroundName', bg_theme_paths, DeferredUpdateVisuals);
        -- Scale/opacity sliders don't need callbacks - changes are picked up from gConfig on next frame
        components.DrawPartySlider(party, 'Background Scale', 'bgScale', 0.1, 3.0, '%.2f', nil, 1.0);
        components.DrawPartySlider(party, 'Border Scale', 'borderScale', 0.1, 3.0, '%.2f', nil, 1.0);
        components.DrawPartySlider(party, 'Background Opacity', 'backgroundOpacity', 0.0, 1.0, '%.2f');
        imgui.ShowHelp('Opacity of the background.');
        components.DrawPartySlider(party, 'Border Opacity', 'borderOpacity', 0.0, 1.0, '%.2f');
        imgui.ShowHelp('Opacity of the window borders (Window themes only).');
        components.DrawPartyComboBox(party, 'Cursor', 'cursor', cursor_paths, DeferredUpdateVisuals);
    end

    if components.CollapsingSection('Job Display##party' .. partyName) then
        components.DrawPartyCheckbox(party, 'Show Job Icons', 'showJobIcon');
        if party.showJobIcon then
            imgui.SameLine();
            imgui.PushItemWidth(100);
            components.DrawPartySlider(party, 'Scale', 'jobIconScale', 0.1, 3.0, '%.1f');
            imgui.PopItemWidth();
        end
        components.DrawPartyCheckbox(party, 'Show Job Text', 'showJob');
        imgui.ShowHelp('Display job and subjob text (Horizontal layout only).');
        if party.showJob then
            imgui.Indent();
            components.DrawPartyCheckbox(party, 'Show Main Job', 'showMainJob');
            imgui.ShowHelp('Display main job abbreviation (e.g., "BLM").');
            if party.showMainJob then
                imgui.SameLine();
                components.DrawPartyCheckbox(party, 'Main Job Level', 'showMainJobLevel');
                imgui.ShowHelp('Display main job level (e.g., "BLM75").');
            end
            components.DrawPartyCheckbox(party, 'Show Sub Job', 'showSubJob');
            imgui.ShowHelp('Display sub job abbreviation (e.g., "/RDM").');
            if party.showSubJob then
                imgui.SameLine();
                components.DrawPartyCheckbox(party, 'Sub Job Level', 'showSubJobLevel');
                imgui.ShowHelp('Display sub job level (e.g., "/RDM37").');
            end
            imgui.Unindent();
        end
    end

    if components.CollapsingSection('Cast Bars##party' .. partyName) then
        components.DrawPartyCheckbox(party, 'Show Cast Bars', 'showCastBars');
        if party.showCastBars then
            local castBarStyleItems = { [0] = 'Replace Name', [1] = 'Use MP Bar', [2] = 'Use TP Bar' };
            local currentStyleIndex = party.castBarStyle == 'mp' and 1 or (party.castBarStyle == 'tp' and 2 or 0);
            local styleLabel = castBarStyleItems[currentStyleIndex];
            if imgui.BeginCombo('Style##castBarStyle' .. partyName, styleLabel) then
                for i = 0, 2 do
                    local isSelected = (currentStyleIndex == i);
                    if imgui.Selectable(castBarStyleItems[i] .. '##' .. i, isSelected) then
                        party.castBarStyle = (i == 1) and 'mp' or ((i == 2) and 'tp' or 'name');
                        UpdateSettings();
                    end
                    if isSelected then
                        imgui.SetItemDefaultFocus();
                    end
                end
                imgui.EndCombo();
            end
            imgui.ShowHelp('Replace Name: replaces player name with spell name during cast.\nUse MP Bar: replaces MP bar with cast bar and MP text with spell name.\nUse TP Bar: replaces TP bar with cast bar and TP text with spell name.');

            if party.castBarStyle == 'name' then
                imgui.Text('Scale');
                imgui.PushItemWidth(100);
                components.DrawPartySlider(party, 'X##castScaleX', 'castBarScaleX', 0.1, 3.0, '%.1f');
                imgui.SameLine();
                components.DrawPartySlider(party, 'Y##castScaleY', 'castBarScaleY', 0.1, 3.0, '%.1f');
                imgui.PopItemWidth();
                imgui.Text('Offset');
                imgui.PushItemWidth(100);
                components.DrawPartySlider(party, 'X##castOffsetX', 'castBarOffsetX', -200, 200);
                imgui.SameLine();
                components.DrawPartySlider(party, 'Y##castOffsetY', 'castBarOffsetY', -200, 200);
                imgui.PopItemWidth();
            end
        end
    end

    if components.CollapsingSection('Status Icons##party' .. partyName) then
        components.DrawPartyComboBoxIndexed(party, 'Status Theme', 'statusTheme', statusThemeItems);
        components.DrawPartyComboBoxIndexed(party, 'Status Side', 'statusSide', statusSideItems);
        components.DrawPartySlider(party, 'Status Icon Scale', 'buffScale', 0.1, 3.0, '%.1f');
        components.DrawPartySlider(party, 'Status Offset X', 'statusOffsetX', -100, 100, nil, nil, 0);
        components.DrawPartySlider(party, 'Status Offset Y', 'statusOffsetY', -100, 100, nil, nil, 0);
    end
end

-- Section: Party List Settings
-- state.selectedPartyTab: tab selection state (1=A, 2=B, 3=C)
function M.DrawSettings(state)
    local selectedPartyTab = state.selectedPartyTab or 1;

    components.DrawCheckbox('Enabled', 'showPartyList', CheckVisibility);
    components.DrawCheckbox('Preview Full Party (when config open)', 'partyListPreview');

    -- Global settings (shared across all parties)
    imgui.Spacing();
    imgui.Text('Global Settings');
    imgui.Separator();
    imgui.Spacing();

    components.DrawCheckbox('Show When Solo', 'showPartyListWhenSolo');
    components.DrawCheckbox('Hide During Events', 'partyListHideDuringEvents');
    components.DrawCheckbox('Alliance Windows', 'partyListAlliance');
    components.DrawCheckbox('Click to Target', 'enablePartyListClickTarget');
    imgui.ShowHelp('Click on a party member to target them. Requires /shorthand to be enabled.');
    
    imgui.Spacing();

    -- Party tab buttons
    local partyTabWidth = 80;
    if components.DrawStyledTab('Party A', 'partyListTab', selectedPartyTab == 1, partyTabWidth) then
        selectedPartyTab = 1;
    end

    -- Party B and C buttons (only if alliance enabled)
    if gConfig.partyListAlliance then
        imgui.SameLine();
        if components.DrawStyledTab('Party B', 'partyListTab', selectedPartyTab == 2, partyTabWidth) then
            selectedPartyTab = 2;
        end

        imgui.SameLine();
        if components.DrawStyledTab('Party C', 'partyListTab', selectedPartyTab == 3, partyTabWidth) then
            selectedPartyTab = 3;
        end
    else
        -- Reset to Party A if alliance is disabled and B or C was selected
        if selectedPartyTab > 1 then
            selectedPartyTab = 1;
        end
    end

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Draw content for selected party tab
    if selectedPartyTab == 1 then
        DrawPartyTabContent(gConfig.partyA, 'A');
    elseif selectedPartyTab == 2 then
        DrawPartyTabContent(gConfig.partyB, 'B');
    elseif selectedPartyTab == 3 then
        DrawPartyTabContent(gConfig.partyC, 'C');
    end

    -- Return updated state
    return { selectedPartyTab = selectedPartyTab };
end

-- Helper function to copy only color settings from one party to another
local function CopyPartyColorSettings(sourcePartyName, targetPartyName)
    -- Get source and target color tables
    local sourceColors = gConfig.colorCustomization['partyList' .. sourcePartyName];
    local targetColors = gConfig.colorCustomization['partyList' .. targetPartyName];

    -- Copy color settings (deep copy)
    local sourceColorsCopy = deep_copy_table(sourceColors);
    for key, value in pairs(sourceColorsCopy) do
        targetColors[key] = value;
    end

    -- Save and update
    UpdateSettings();
end

-- Helper function to draw color settings for a specific party
local function DrawPartyColorTabContent(colors, partyName)
    -- Copy colors section (only for Party B and C)
    if partyName == 'B' or partyName == 'C' then
        if components.CollapsingSection('Copy Colors##partyColor' .. partyName) then
            -- Build list of other parties to copy from
            local copyOptions = {};
            if partyName == 'B' then
                copyOptions = { 'A', 'C' };
            else -- partyName == 'C'
                copyOptions = { 'A', 'B' };
            end

            imgui.Text('Copy colors from another party:');
            for _, sourceName in ipairs(copyOptions) do
                imgui.SameLine();
                if imgui.Button('Party ' .. sourceName .. '##copy_colors_from_' .. sourceName .. '_to_' .. partyName) then
                    CopyPartyColorSettings(sourceName, partyName);
                end
            end
            imgui.ShowHelp('Copies all color settings from the selected party to this one.');
        end
    end

    if components.CollapsingSection('HP Bar Colors##partyColor' .. partyName) then
        components.DrawHPBarColorsRow(colors.hpGradient, "##party" .. partyName);
    end

    if partyName == 'A' then
        if components.CollapsingSection('MP/TP Bar Colors##partyColor' .. partyName) then
            components.DrawTwoColumnRow("MP Bar", colors.mpGradient, "MP bar color",
                             "TP Bar", colors.tpGradient, "TP bar color", "##party" .. partyName);
        end
    else
        if components.CollapsingSection('MP Bar Colors##partyColor' .. partyName) then
            components.DrawGradientPickerColumn("MP Bar##party" .. partyName, colors.mpGradient, "MP bar color");
        end
    end

    if components.CollapsingSection('Cast Bar Colors##partyColor' .. partyName) then
        components.DrawGradientPicker("Cast Bar##" .. partyName, colors.castBarGradient, "Cast bar color (appears when casting)");
        components.DrawTextColorPicker("Cast Text##" .. partyName, colors, 'castTextColor', "Cast text color (spell name when using MP bar style)");
    end

    if components.CollapsingSection('Bar Overrides##partyColor' .. partyName) then
        imgui.Text("Background Override:");
        local overrideActive = {colors.barBackgroundOverride.active};
        if (imgui.Checkbox("Enable Background Override##" .. partyName, overrideActive)) then
            colors.barBackgroundOverride.active = overrideActive[1];
            UpdateSettings();
        end
        imgui.ShowHelp("When enabled, uses the colors below instead of the global bar background color");
        if colors.barBackgroundOverride.active then
            components.DrawGradientPicker("Background Color##bgOverride" .. partyName, colors.barBackgroundOverride, "Override color for bar backgrounds");
        end

        imgui.Spacing();
        imgui.Text("Border Override:");
        local borderOverrideActive = {colors.barBorderOverride.active};
        if (imgui.Checkbox("Enable Border Override##" .. partyName, borderOverrideActive)) then
            colors.barBorderOverride.active = borderOverrideActive[1];
            UpdateSettings();
        end
        imgui.ShowHelp("When enabled, uses the color below instead of the global bar background color for borders");
        if colors.barBorderOverride.active then
            local borderColor = HexToImGui(colors.barBorderOverride.color);
            if (imgui.ColorEdit4('Border Color##barBorderOverride' .. partyName, borderColor, bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar))) then
                colors.barBorderOverride.color = ImGuiToHex(borderColor);
            end
            if (imgui.IsItemDeactivatedAfterEdit()) then
                SaveSettingsOnly();
            end
            imgui.ShowHelp("Override color for bar borders");
        end
    end

    if components.CollapsingSection('Text Colors##partyColor' .. partyName) then
        components.DrawTextColorPicker("Name Text##" .. partyName, colors, 'nameTextColor', "Color of member name");
        components.DrawTextColorPicker("HP Text##" .. partyName, colors, 'hpTextColor', "Color of HP numbers");
        components.DrawTextColorPicker("MP Text##" .. partyName, colors, 'mpTextColor', "Color of MP numbers");
        components.DrawTextColorPicker("TP Text (Empty, <1000)##" .. partyName, colors, 'tpEmptyTextColor', "Color of TP numbers when below 1000");
        components.DrawTextColorPicker("TP Text (Full, >=1000)##" .. partyName, colors, 'tpFullTextColor', "Color of TP numbers when 1000 or higher");
        components.DrawTextColorPicker("TP Flash Color##" .. partyName, colors, 'tpFlashColor', "Color to flash when TP is 1000+");
    end

    if components.CollapsingSection('Background Colors##partyColor' .. partyName) then
        components.DrawTextColorPicker("Background Color##" .. partyName, colors, 'bgColor', "Color of party list background");
        components.DrawTextColorPicker("Border Color##" .. partyName, colors, 'borderColor', "Color of party list borders");
    end

    if components.CollapsingSection('Selection Colors##partyColor' .. partyName) then
        components.DrawGradientPicker("Selection Box##" .. partyName, colors.selectionGradient, "Color gradient for the selection box around targeted members");
        components.DrawTextColorPicker("Selection Border##" .. partyName, colors, 'selectionBorderColor', "Color of the selection box border");
    end

    if components.CollapsingSection('Subtarget Colors##partyColor' .. partyName) then
        -- Initialize subtarget colors if not present
        if not colors.subtargetGradient then
            colors.subtargetGradient = T{ enabled = true, start = '#d9a54d', stop = '#edcf78' };
        end
        if not colors.subtargetBorderColor then
            colors.subtargetBorderColor = 0xFFfdd017;
        end
        components.DrawGradientPicker("Subtarget Box##" .. partyName, colors.subtargetGradient, "Color gradient for the selection box around subtargeted members");
        components.DrawTextColorPicker("Subtarget Border##" .. partyName, colors, 'subtargetBorderColor', "Color of the subtarget selection box border");
    end

    if components.CollapsingSection('Cursor Tint Colors##partyColor' .. partyName) then
        local partyConfig = gConfig['party' .. partyName];
        components.DrawPartyColorPicker(partyConfig, 'Target Cursor Tint##' .. partyName, 'targetArrowTint', 'Color tint applied to the cursor when targeting a party member', 0xFFFFFFFF);
        components.DrawPartyColorPicker(partyConfig, 'Subtarget Cursor Tint##' .. partyName, 'subtargetArrowTint', 'Color tint applied to the cursor when subtargeting a party member', 0xFFfdd017);
    end
end

-- Section: Party List Color Settings
-- state.selectedPartyColorTab: tab selection state (1=A, 2=B, 3=C)
function M.DrawColorSettings(state)
    local selectedPartyColorTab = state.selectedPartyColorTab or 1;

    -- Party color tab buttons
    local partyTabWidth = 80;
    if components.DrawStyledTab('Party A', 'partyColorTab', selectedPartyColorTab == 1, partyTabWidth) then
        selectedPartyColorTab = 1;
    end

    -- Party B and C buttons (only if alliance enabled)
    if gConfig.partyListAlliance then
        imgui.SameLine();
        if components.DrawStyledTab('Party B', 'partyColorTab', selectedPartyColorTab == 2, partyTabWidth) then
            selectedPartyColorTab = 2;
        end

        imgui.SameLine();
        if components.DrawStyledTab('Party C', 'partyColorTab', selectedPartyColorTab == 3, partyTabWidth) then
            selectedPartyColorTab = 3;
        end
    else
        -- Reset to Party A if alliance is disabled and B or C was selected
        if selectedPartyColorTab > 1 then
            selectedPartyColorTab = 1;
        end
    end

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Draw content for selected party color tab
    if selectedPartyColorTab == 1 then
        DrawPartyColorTabContent(gConfig.colorCustomization.partyListA, 'A');
    elseif selectedPartyColorTab == 2 then
        DrawPartyColorTabContent(gConfig.colorCustomization.partyListB, 'B');
    elseif selectedPartyColorTab == 3 then
        DrawPartyColorTabContent(gConfig.colorCustomization.partyListC, 'C');
    end

    -- Return updated state
    return { selectedPartyColorTab = selectedPartyColorTab };
end

return M;
