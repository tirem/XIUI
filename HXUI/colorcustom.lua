require("common");
require('helpers');
local imgui = require("imgui");

local colorcustom = {};
gShowColorCustom = { false };

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

    imgui.SetNextWindowSize({ 700, 600 }, ImGuiCond_FirstUseEver);
    if (imgui.Begin("HXUI Color Customization", gShowColorCustom, bit.bor(ImGuiWindowFlags_NoSavedSettings))) then

        if (imgui.Button("Restore Default Colors", { 240, 20 })) then
            -- Reset all colors to defaults
            gConfig.colorCustomization = deep_copy_table(defaultUserSettings.colorCustomization);
            UpdateSettings();
        end
        imgui.ShowHelp('Reset all custom colors back to default values');

        imgui.BeginChild("Color Options", { 0, 0 }, true);

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
            imgui.BeginChild("TargetBarColors", { 0, 500 }, true);

            imgui.Text("HP Bar Color:");
            imgui.Separator();
            DrawGradientPicker("Target HP Bar", gConfig.colorCustomization.targetBar.hpGradient, "Target HP bar color");

            imgui.Separator();
            imgui.Text("Target Name Colors (by type):");
            imgui.Separator();
            DrawTextColorPicker("Party/Alliance Player", gConfig.colorCustomization.targetBar, 'playerPartyTextColor', "Color for party/alliance member names");
            DrawTextColorPicker("Other Player", gConfig.colorCustomization.targetBar, 'playerOtherTextColor', "Color for other player names");
            DrawTextColorPicker("NPC", gConfig.colorCustomization.targetBar, 'npcTextColor', "Color for NPC names");
            DrawTextColorPicker("Unclaimed Mob", gConfig.colorCustomization.targetBar, 'mobUnclaimedTextColor', "Color for unclaimed mob names");
            DrawTextColorPicker("Party-Claimed Mob", gConfig.colorCustomization.targetBar, 'mobPartyClaimedTextColor', "Color for mobs claimed by your party");
            DrawTextColorPicker("Other-Claimed Mob", gConfig.colorCustomization.targetBar, 'mobOtherClaimedTextColor', "Color for mobs claimed by others");

            imgui.Separator();
            imgui.Text("Other Text Colors:");
            imgui.Separator();
            DrawTextColorPicker("Distance Text", gConfig.colorCustomization.targetBar, 'distanceTextColor', "Color of distance text");
            imgui.ShowHelp("HP Percent text color is set dynamically based on HP amount");

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
            imgui.BeginChild("EnemyListColors", { 0, 150 }, true);

            imgui.Text("HP Bar Color:");
            imgui.Separator();
            DrawGradientPicker("Enemy HP Bar", gConfig.colorCustomization.enemyList.hpGradient, "Enemy HP bar color");
            imgui.ShowHelp('Note: Enemy name colors are dynamic based on claim status');

            imgui.EndChild();
        end

        -- Party List
        if (imgui.CollapsingHeader("Party List")) then
            imgui.BeginChild("PartyListColors", { 0, 700 }, true);

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
            imgui.Text("Text Colors:");
            imgui.Separator();
            DrawTextColorPicker("Name Text", gConfig.colorCustomization.partyList, 'nameTextColor', "Color of party member name");
            DrawTextColorPicker("HP Text", gConfig.colorCustomization.partyList, 'hpTextColor', "Color of HP numbers");
            DrawTextColorPicker("MP Text", gConfig.colorCustomization.partyList, 'mpTextColor', "Color of MP numbers");
            DrawTextColorPicker("TP Text (Empty, <1000)", gConfig.colorCustomization.partyList, 'tpEmptyTextColor', "Color of TP numbers when below 1000");
            DrawTextColorPicker("TP Text (Full, >=1000)", gConfig.colorCustomization.partyList, 'tpFullTextColor', "Color of TP numbers when 1000 or higher");

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
            imgui.BeginChild("InventoryTrackerColors", { 0, 250 }, true);

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
            if (imgui.ColorEdit4('Empty Slot', emptySlot, ImGuiColorEditFlags_AlphaBar)) then
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
            if (imgui.ColorEdit4('Used Slot', usedSlot, ImGuiColorEditFlags_AlphaBar)) then
                gConfig.colorCustomization.inventoryTracker.usedSlotColor.r = usedSlot[1];
                gConfig.colorCustomization.inventoryTracker.usedSlotColor.g = usedSlot[2];
                gConfig.colorCustomization.inventoryTracker.usedSlotColor.b = usedSlot[3];
                gConfig.colorCustomization.inventoryTracker.usedSlotColor.a = usedSlot[4];
            end
            -- Only save settings when user finishes editing
            if (imgui.IsItemDeactivatedAfterEdit()) then
                SaveSettingsOnly();
            end
            imgui.ShowHelp('Color for used inventory slots');

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

        -- Global
        if (imgui.CollapsingHeader("Global")) then
            imgui.BeginChild("GlobalColors", { 0, 150 }, true);

            imgui.Text("Background Color:");
            imgui.Separator();
            DrawGradientPicker("Bar Background", gConfig.colorCustomization.shared.backgroundGradient, "Background color for all progress bars");

            imgui.EndChild();
        end

        imgui.EndChild();
    end

    imgui.PopStyleColor(8);
    imgui.End();
end

return colorcustom;
