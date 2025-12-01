require("common");
require('helpers');
local imgui = require("imgui");

local colorcustom = {};
gShowColorCustom = { false };

-- State for confirmation dialogs
local showRestoreColorsConfirm = false;

-- Helper function to draw gradient color pickers
local function DrawGradientPicker(label, gradientTable, helpText)
    if not gradientTable then
        return;
    end

    -- Checkbox for gradient vs static color
    local enabled = { gradientTable.enabled };
    if (imgui.Checkbox('Use Gradient##'..label, enabled)) then
        gradientTable.enabled = enabled[1];
        SaveSettingsOnly();
    end
    imgui.ShowHelp('Enable gradient (2 colors) or use static color (single color)');

    -- Start color picker
    local startColor = HexToImGui(gradientTable.start);
    if (imgui.ColorEdit4(label..' Start##'..label, startColor, bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar))) then
        gradientTable.start = ImGuiToHex(startColor);
    end
    -- Only save settings when user finishes editing (not on every frame while dragging)
    if (imgui.IsItemDeactivatedAfterEdit()) then
        SaveSettingsOnly();
    end

    -- Stop color picker (only if gradient is enabled)
    if gradientTable.enabled then
        local stopColor = HexToImGui(gradientTable.stop);
        if (imgui.ColorEdit4(label..' End##'..label, stopColor, bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar))) then
            gradientTable.stop = ImGuiToHex(stopColor);
        end
        -- Only save settings when user finishes editing
        if (imgui.IsItemDeactivatedAfterEdit()) then
            SaveSettingsOnly();
        end
    end

    if helpText then
        imgui.ShowHelp(helpText);
    end
end

-- Helper function to draw 3-step gradient color pickers (for bookends)
local function DrawThreeStepGradientPicker(label, gradientTable, helpText)
    if not gradientTable then
        return;
    end

    -- Start color picker (top)
    local startColor = HexToImGui(gradientTable.start);
    if (imgui.ColorEdit4(label..' Top##'..label, startColor, bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar))) then
        gradientTable.start = ImGuiToHex(startColor);
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then
        SaveSettingsOnly();
    end

    -- Mid color picker (middle)
    local midColor = HexToImGui(gradientTable.mid);
    if (imgui.ColorEdit4(label..' Middle##'..label, midColor, bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar))) then
        gradientTable.mid = ImGuiToHex(midColor);
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then
        SaveSettingsOnly();
    end

    -- Stop color picker (bottom)
    local stopColor = HexToImGui(gradientTable.stop);
    if (imgui.ColorEdit4(label..' Bottom##'..label, stopColor, bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar))) then
        gradientTable.stop = ImGuiToHex(stopColor);
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then
        SaveSettingsOnly();
    end

    if helpText then
        imgui.ShowHelp(helpText);
    end
end

-- Helper function to draw text color picker (with alpha)
local function DrawTextColorPicker(label, parentTable, key, helpText)
    if not parentTable or not parentTable[key] then
        return;
    end

    local colorValue = parentTable[key];
    local colorRGBA = ARGBToImGui(colorValue);

    if (imgui.ColorEdit4(label, colorRGBA, bit.bor(ImGuiColorEditFlags_AlphaBar, ImGuiColorEditFlags_NoInputs))) then
        parentTable[key] = ImGuiToARGB(colorRGBA);
    end
    -- Only save settings when user finishes editing (not on every frame while dragging)
    if (imgui.IsItemDeactivatedAfterEdit()) then
        SaveSettingsOnly();
    end

    if helpText then
        imgui.ShowHelp(helpText);
    end
end

colorcustom.DrawWindow = function()
    if not gShowColorCustom[1] then
        return;
    end

    imgui.PushStyleColor(ImGuiCol_WindowBg, {0,0.06,.16,.9});
    imgui.PushStyleColor(ImGuiCol_TitleBg, {0,0.06,.16, .7});
    imgui.PushStyleColor(ImGuiCol_TitleBgActive, {0,0.06,.16, .9});
    imgui.PushStyleColor(ImGuiCol_TitleBgCollapsed, {0,0.06,.16, .5});
    imgui.PushStyleColor(ImGuiCol_Header, {0,0.06,.16,.7});
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, {0,0.06,.16, .9});
    imgui.PushStyleColor(ImGuiCol_HeaderActive, {0,0.06,.16, 1});
    imgui.PushStyleColor(ImGuiCol_FrameBg, {0,0.06,.16, 1});

    -- Set proper spacing and padding for color customization menu
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {8, 8});
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {4, 3});
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {8, 4});

    imgui.SetNextWindowSize({ 700, 600 }, ImGuiCond_FirstUseEver);
    if (imgui.Begin("HXUI Color Customization", gShowColorCustom, bit.bor(ImGuiWindowFlags_NoSavedSettings))) then

        if (imgui.Button("Open Config", { 160, 20 })) then
            showConfig[1] = true;
        end
        imgui.SameLine();

        if (imgui.Button("Restore Default Colors", { 240, 20 })) then
            showRestoreColorsConfirm = true;
            imgui.OpenPopup("Confirm Restore Colors");
        end

        -- Restore Default Colors confirmation popup
        if (showRestoreColorsConfirm) then
            imgui.OpenPopup("Confirm Restore Colors");
            showRestoreColorsConfirm = false;
        end

        if (imgui.BeginPopupModal("Confirm Restore Colors", true, ImGuiWindowFlags_AlwaysAutoResize)) then
            imgui.Text("Are you sure you want to restore all colors to defaults?");
            imgui.Text("This will reset all your custom colors.");
            imgui.NewLine();

            if (imgui.Button("Confirm", { 120, 0 })) then
                -- Reset all colors to defaults
                gConfig.colorCustomization = deep_copy_table(defaultUserSettings.colorCustomization);
                UpdateSettings();
                imgui.CloseCurrentPopup();
            end
            imgui.SameLine();
            if (imgui.Button("Cancel", { 120, 0 })) then
                imgui.CloseCurrentPopup();
            end

            imgui.EndPopup();
        end

        imgui.BeginChild("Color Options", { 0, 0 }, true);

        -- Global
        if (imgui.CollapsingHeader("Global")) then
            imgui.BeginChild("GlobalColors", { 0, 600 }, true);

            imgui.Text("Background Color:");
            imgui.Separator();
            DrawGradientPicker("Bar Background", gConfig.colorCustomization.shared.backgroundGradient, "Background color for all progress bars");

            imgui.Separator();
            imgui.Text("Bookend Gradient:");
            imgui.Separator();
            DrawThreeStepGradientPicker("Bookend", gConfig.colorCustomization.shared.bookendGradient, "3-step gradient for progress bar bookends (top -> middle -> bottom)");

            imgui.Separator();
            imgui.Text("Entity Name Colors (by type):");
            imgui.Separator();
            DrawTextColorPicker("Party/Alliance Player", gConfig.colorCustomization.shared, 'playerPartyTextColor', "Color for party/alliance member names");
            DrawTextColorPicker("Other Player", gConfig.colorCustomization.shared, 'playerOtherTextColor', "Color for other player names");
            DrawTextColorPicker("NPC", gConfig.colorCustomization.shared, 'npcTextColor', "Color for NPC names");
            DrawTextColorPicker("Unclaimed Mob", gConfig.colorCustomization.shared, 'mobUnclaimedTextColor', "Color for unclaimed mob names");
            DrawTextColorPicker("Party-Claimed Mob", gConfig.colorCustomization.shared, 'mobPartyClaimedTextColor', "Color for mobs claimed by your party");
            DrawTextColorPicker("Other-Claimed Mob", gConfig.colorCustomization.shared, 'mobOtherClaimedTextColor', "Color for mobs claimed by others");

            imgui.EndChild();
        end

        -- Player Bar
        if (imgui.CollapsingHeader("Player Bar")) then
            imgui.BeginChild("PlayerBarColors", { 0, 600 }, true);

            imgui.Text("HP Bar Colors:");
            imgui.Separator();
            DrawGradientPicker("HP High (75-100%)", gConfig.colorCustomization.playerBar.hpGradient.high, "HP bar color when health is above 75%");
            DrawGradientPicker("HP Med-High (50-75%)", gConfig.colorCustomization.playerBar.hpGradient.medHigh, "HP bar color when health is 50-75%");
            DrawGradientPicker("HP Med-Low (25-50%)", gConfig.colorCustomization.playerBar.hpGradient.medLow, "HP bar color when health is 25-50%");
            DrawGradientPicker("HP Low (0-25%)", gConfig.colorCustomization.playerBar.hpGradient.low, "HP bar color when health is below 25%");

            imgui.Separator();
            imgui.Text("MP/TP Bar Colors:");
            imgui.Separator();
            DrawGradientPicker("MP Bar", gConfig.colorCustomization.playerBar.mpGradient, "MP bar color gradient");
            DrawGradientPicker("TP Bar", gConfig.colorCustomization.playerBar.tpGradient, "TP bar color gradient");

            imgui.Separator();
            imgui.Text("Text Colors:");
            imgui.Separator();
            DrawTextColorPicker("HP Text", gConfig.colorCustomization.playerBar, 'hpTextColor', "Color of HP number text");
            DrawTextColorPicker("MP Text", gConfig.colorCustomization.playerBar, 'mpTextColor', "Color of MP number text");
            DrawTextColorPicker("TP Text (Empty, <1000)", gConfig.colorCustomization.playerBar, 'tpEmptyTextColor', "Color of TP number text when below 1000");
            DrawTextColorPicker("TP Text (Full, >=1000)", gConfig.colorCustomization.playerBar, 'tpFullTextColor', "Color of TP number text when 1000 or higher");

            imgui.EndChild();
        end

        -- Target Bar
        if (imgui.CollapsingHeader("Target Bar")) then
            imgui.BeginChild("TargetBarColors", { 0, 250 }, true);

            imgui.Text("Bar Colors:");
            imgui.Separator();
            DrawGradientPicker("Target HP Bar", gConfig.colorCustomization.targetBar.hpGradient, "Target HP bar color");
            DrawGradientPicker("Cast Bar", gConfig.colorCustomization.targetBar.castBarGradient, "Enemy cast bar color");

            imgui.Separator();
            imgui.Text("Text Colors:");
            imgui.Separator();
            DrawTextColorPicker("Distance Text", gConfig.colorCustomization.targetBar, 'distanceTextColor', "Color of distance text");
            DrawTextColorPicker("Cast Text", gConfig.colorCustomization.targetBar, 'castTextColor', "Color of enemy cast text");
            imgui.ShowHelp("Target name colors are in the Global section\nHP Percent text color is set dynamically based on HP amount");

            imgui.EndChild();
        end

        -- Target of Target Bar
        if (imgui.CollapsingHeader("Target of Target Bar")) then
            imgui.BeginChild("TotBarColors", { 0, 200 }, true);

            imgui.Text("HP Bar Color:");
            imgui.Separator();
            DrawGradientPicker("ToT HP Bar", gConfig.colorCustomization.totBar.hpGradient, "Target of Target HP bar color");

            imgui.Separator();
            imgui.Text("Text Colors:");
            imgui.Separator();
            DrawTextColorPicker("Name Text", gConfig.colorCustomization.totBar, 'nameTextColor', "Color of target of target name text");

            imgui.EndChild();
        end

        -- Enemy List
        if (imgui.CollapsingHeader("Enemy List")) then
            imgui.BeginChild("EnemyListColors", { 0, 350 }, true);

            imgui.Text("HP Bar Color:");
            imgui.Separator();
            DrawGradientPicker("Enemy HP Bar", gConfig.colorCustomization.enemyList.hpGradient, "Enemy HP bar color");

            imgui.Separator();
            imgui.Text("Text Colors:");
            imgui.Separator();
            DrawTextColorPicker("Distance Text", gConfig.colorCustomization.enemyList, 'distanceTextColor', "Color of distance text");
            DrawTextColorPicker("HP% Text", gConfig.colorCustomization.enemyList, 'percentTextColor', "Color of HP percentage text");
            imgui.ShowHelp("Enemy name colors are in the Global section");

            imgui.Separator();
            imgui.Text("Border Colors:");
            imgui.Separator();
            DrawTextColorPicker("Target Border", gConfig.colorCustomization.enemyList, 'targetBorderColor', "Border color for currently targeted enemy");
            DrawTextColorPicker("Subtarget Border", gConfig.colorCustomization.enemyList, 'subtargetBorderColor', "Border color for subtargeted enemy");

            imgui.EndChild();
        end

        -- Party List
        if (imgui.CollapsingHeader("Party List")) then
            imgui.BeginChild("PartyListColors", { 0, 800 }, true);

            imgui.Text("HP Bar Colors:");
            imgui.Separator();
            DrawGradientPicker("Party HP High (75-100%)", gConfig.colorCustomization.partyList.hpGradient.high, "Party member HP bar when health is above 75%");
            DrawGradientPicker("Party HP Med-High (50-75%)", gConfig.colorCustomization.partyList.hpGradient.medHigh, "Party member HP bar when health is 50-75%");
            DrawGradientPicker("Party HP Med-Low (25-50%)", gConfig.colorCustomization.partyList.hpGradient.medLow, "Party member HP bar when health is 25-50%");
            DrawGradientPicker("Party HP Low (0-25%)", gConfig.colorCustomization.partyList.hpGradient.low, "Party member HP bar when health is below 25%");

            imgui.Separator();
            imgui.Text("MP/TP Bar Colors:");
            imgui.Separator();
            DrawGradientPicker("Party MP Bar", gConfig.colorCustomization.partyList.mpGradient, "Party member MP bar color");
            DrawGradientPicker("Party TP Bar", gConfig.colorCustomization.partyList.tpGradient, "Party member TP bar color");

            imgui.Separator();
            imgui.Text("Cast Bar Colors:");
            imgui.Separator();
            DrawGradientPicker("Party Cast Bar", gConfig.colorCustomization.partyList.castBarGradient, "Party member cast bar color (appears when casting)");

            imgui.Separator();
            imgui.Text("Bar Background Override:");
            imgui.Separator();
            local overrideActive = {gConfig.colorCustomization.partyList.barBackgroundOverride.active};
            if (imgui.Checkbox("Enable Background Override", overrideActive)) then
                gConfig.colorCustomization.partyList.barBackgroundOverride.active = overrideActive[1];
                UpdateSettings();
            end
            imgui.ShowHelp("When enabled, uses the colors below instead of the global bar background color");
            if gConfig.colorCustomization.partyList.barBackgroundOverride.active then
                DrawGradientPicker("Background Color", gConfig.colorCustomization.partyList.barBackgroundOverride, "Override color for party list bar backgrounds");
            end

            imgui.Separator();
            imgui.Text("Bar Border Override:");
            imgui.Separator();
            local borderOverrideActive = {gConfig.colorCustomization.partyList.barBorderOverride.active};
            if (imgui.Checkbox("Enable Border Override", borderOverrideActive)) then
                gConfig.colorCustomization.partyList.barBorderOverride.active = borderOverrideActive[1];
                UpdateSettings();
            end
            imgui.ShowHelp("When enabled, uses the color below instead of the global bar background color for borders");
            if gConfig.colorCustomization.partyList.barBorderOverride.active then
                local borderColor = HexToImGui(gConfig.colorCustomization.partyList.barBorderOverride.color);
                if (imgui.ColorEdit4('Border Color##barBorderOverride', borderColor, bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar))) then
                    gConfig.colorCustomization.partyList.barBorderOverride.color = ImGuiToHex(borderColor);
                end
                if (imgui.IsItemDeactivatedAfterEdit()) then
                    SaveSettingsOnly();
                end
                imgui.ShowHelp("Override color for party list bar borders");
            end

            imgui.Separator();
            imgui.Text("Text Colors:");
            imgui.Separator();
            DrawTextColorPicker("Name Text", gConfig.colorCustomization.partyList, 'nameTextColor', "Color of party member name");
            DrawTextColorPicker("HP Text", gConfig.colorCustomization.partyList, 'hpTextColor', "Color of HP numbers");
            DrawTextColorPicker("MP Text", gConfig.colorCustomization.partyList, 'mpTextColor', "Color of MP numbers");
            DrawTextColorPicker("TP Text (Empty, <1000)", gConfig.colorCustomization.partyList, 'tpEmptyTextColor', "Color of TP numbers when below 1000");
            DrawTextColorPicker("TP Text (Full, >=1000)", gConfig.colorCustomization.partyList, 'tpFullTextColor', "Color of TP numbers when 1000 or higher");

            imgui.Separator();
            imgui.Text("Background Colors:");
            imgui.Separator();
            DrawTextColorPicker("Background Color", gConfig.colorCustomization.partyList, 'bgColor', "Color of party list background");
            DrawTextColorPicker("Border Color", gConfig.colorCustomization.partyList, 'borderColor', "Color of party list borders");

            imgui.Separator();
            imgui.Text("Selection Colors:");
            imgui.Separator();
            DrawGradientPicker("Selection Box", gConfig.colorCustomization.partyList.selectionGradient, "Color gradient for the selection box around targeted party members");
            DrawTextColorPicker("Selection Border", gConfig.colorCustomization.partyList, 'selectionBorderColor', "Color of the selection box border");

            imgui.EndChild();
        end

        -- Exp Bar
        if (imgui.CollapsingHeader("Exp Bar")) then
            imgui.BeginChild("ExpBarColors", { 0, 300 }, true);

            imgui.Text("Bar Color:");
            imgui.Separator();
            DrawGradientPicker("Exp/Merit Bar", gConfig.colorCustomization.expBar.barGradient, "Color for EXP/Merit/Capacity bar");

            imgui.Separator();
            imgui.Text("Text Colors:");
            imgui.Separator();
            DrawTextColorPicker("Job Text", gConfig.colorCustomization.expBar, 'jobTextColor', "Color of job level text");
            DrawTextColorPicker("Exp Text", gConfig.colorCustomization.expBar, 'expTextColor', "Color of experience numbers");
            DrawTextColorPicker("Percent Text", gConfig.colorCustomization.expBar, 'percentTextColor', "Color of percentage text");

            imgui.EndChild();
        end

        -- Gil Tracker
        if (imgui.CollapsingHeader("Gil Tracker")) then
            imgui.BeginChild("GilTrackerColors", { 0, 100 }, true);

            imgui.Text("Text Color:");
            imgui.Separator();
            DrawTextColorPicker("Gil Text", gConfig.colorCustomization.gilTracker, 'textColor', "Color of gil amount text");

            imgui.EndChild();
        end

        -- Inventory Tracker
        if (imgui.CollapsingHeader("Inventory Tracker")) then
            imgui.BeginChild("InventoryTrackerColors", { 0, 450 }, true);

            imgui.Text("Text Color:");
            imgui.Separator();
            DrawTextColorPicker("Count Text", gConfig.colorCustomization.inventoryTracker, 'textColor', "Color of inventory count text");

            imgui.Separator();
            imgui.Text("Dot Colors:");
            imgui.Separator();

            local emptySlot = {
                gConfig.colorCustomization.inventoryTracker.emptySlotColor.r,
                gConfig.colorCustomization.inventoryTracker.emptySlotColor.g,
                gConfig.colorCustomization.inventoryTracker.emptySlotColor.b,
                gConfig.colorCustomization.inventoryTracker.emptySlotColor.a
            };
            if (imgui.ColorEdit4('Empty Slot', emptySlot, bit.bor(ImGuiColorEditFlags_AlphaBar, ImGuiColorEditFlags_NoInputs))) then
                gConfig.colorCustomization.inventoryTracker.emptySlotColor.r = emptySlot[1];
                gConfig.colorCustomization.inventoryTracker.emptySlotColor.g = emptySlot[2];
                gConfig.colorCustomization.inventoryTracker.emptySlotColor.b = emptySlot[3];
                gConfig.colorCustomization.inventoryTracker.emptySlotColor.a = emptySlot[4];
            end
            -- Only save settings when user finishes editing
            if (imgui.IsItemDeactivatedAfterEdit()) then
                SaveSettingsOnly();
            end
            imgui.ShowHelp('Color for empty inventory slots');

            local usedSlot = {
                gConfig.colorCustomization.inventoryTracker.usedSlotColor.r,
                gConfig.colorCustomization.inventoryTracker.usedSlotColor.g,
                gConfig.colorCustomization.inventoryTracker.usedSlotColor.b,
                gConfig.colorCustomization.inventoryTracker.usedSlotColor.a
            };
            if (imgui.ColorEdit4('Used Slot (Normal)', usedSlot, bit.bor(ImGuiColorEditFlags_AlphaBar, ImGuiColorEditFlags_NoInputs))) then
                gConfig.colorCustomization.inventoryTracker.usedSlotColor.r = usedSlot[1];
                gConfig.colorCustomization.inventoryTracker.usedSlotColor.g = usedSlot[2];
                gConfig.colorCustomization.inventoryTracker.usedSlotColor.b = usedSlot[3];
                gConfig.colorCustomization.inventoryTracker.usedSlotColor.a = usedSlot[4];
            end
            -- Only save settings when user finishes editing
            if (imgui.IsItemDeactivatedAfterEdit()) then
                SaveSettingsOnly();
            end
            imgui.ShowHelp('Color for used inventory slots (normal)');

            local usedSlotThreshold1 = {
                gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold1.r,
                gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold1.g,
                gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold1.b,
                gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold1.a
            };
            if (imgui.ColorEdit4('Used Slot (Warning)', usedSlotThreshold1, bit.bor(ImGuiColorEditFlags_AlphaBar, ImGuiColorEditFlags_NoInputs))) then
                gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold1.r = usedSlotThreshold1[1];
                gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold1.g = usedSlotThreshold1[2];
                gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold1.b = usedSlotThreshold1[3];
                gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold1.a = usedSlotThreshold1[4];
            end
            -- Only save settings when user finishes editing
            if (imgui.IsItemDeactivatedAfterEdit()) then
                SaveSettingsOnly();
            end
            imgui.ShowHelp('Color for used inventory slots when at warning threshold');

            local usedSlotThreshold2 = {
                gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold2.r,
                gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold2.g,
                gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold2.b,
                gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold2.a
            };
            if (imgui.ColorEdit4('Used Slot (Critical)', usedSlotThreshold2, bit.bor(ImGuiColorEditFlags_AlphaBar, ImGuiColorEditFlags_NoInputs))) then
                gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold2.r = usedSlotThreshold2[1];
                gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold2.g = usedSlotThreshold2[2];
                gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold2.b = usedSlotThreshold2[3];
                gConfig.colorCustomization.inventoryTracker.usedSlotColorThreshold2.a = usedSlotThreshold2[4];
            end
            -- Only save settings when user finishes editing
            if (imgui.IsItemDeactivatedAfterEdit()) then
                SaveSettingsOnly();
            end
            imgui.ShowHelp('Color for used inventory slots when at critical threshold');

            imgui.Separator();
            imgui.Text("Color Thresholds:");
            imgui.Separator();

            local threshold1 = { gConfig.inventoryTrackerColorThreshold1 };
            if (imgui.SliderInt('Warning Threshold', threshold1, 0, 80)) then
                gConfig.inventoryTrackerColorThreshold1 = threshold1[1];
            end
            if (imgui.IsItemDeactivatedAfterEdit()) then
                SaveSettingsOnly();
            end
            imgui.ShowHelp('Inventory count at which dots turn to warning color');

            local threshold2 = { gConfig.inventoryTrackerColorThreshold2 };
            if (imgui.SliderInt('Critical Threshold', threshold2, 0, 80)) then
                gConfig.inventoryTrackerColorThreshold2 = threshold2[1];
            end
            if (imgui.IsItemDeactivatedAfterEdit()) then
                SaveSettingsOnly();
            end
            imgui.ShowHelp('Inventory count at which dots turn to critical color');

            imgui.EndChild();
        end

        -- Cast Bar
        if (imgui.CollapsingHeader("Cast Bar")) then
            imgui.BeginChild("CastBarColors", { 0, 250 }, true);

            imgui.Text("Bar Color:");
            imgui.Separator();
            DrawGradientPicker("Cast Bar", gConfig.colorCustomization.castBar.barGradient, "Color of casting progress bar");

            imgui.Separator();
            imgui.Text("Text Colors:");
            imgui.Separator();
            DrawTextColorPicker("Spell Text", gConfig.colorCustomization.castBar, 'spellTextColor', "Color of spell/ability name");
            DrawTextColorPicker("Percent Text", gConfig.colorCustomization.castBar, 'percentTextColor', "Color of cast percentage");

            imgui.EndChild();
        end

        imgui.EndChild();
    end

    imgui.PopStyleVar(3);
    imgui.PopStyleColor(8);
    imgui.End();
end

return colorcustom;
