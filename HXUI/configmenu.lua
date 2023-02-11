require ("common");
require('helpers');
local statusHandler = require('statushandler');
local imgui = require("imgui");

local config = {};

config.DrawWindow = function(us)
    imgui.SetNextWindowSize({ 500, 500 }, ImGuiCond_FirstUseEver);
    if(showConfig[1] and imgui.Begin(("HXUI Config"):fmt(addon.version), showConfig, bit.bor(ImGuiWindowFlags_NoSavedSettings))) then
        if(imgui.Button("Restore Defaults", { 130, 20 })) then
            ResetSettings();
            UpdateSettings();
        end
        imgui.BeginChild("Config Options", { 0, 0 }, true);
        if (imgui.CollapsingHeader("General")) then
            imgui.BeginChild("GeneralSettings", { 0, 100 }, true);
            
            -- Status Icon Theme
            local status_theme_paths = statusHandler.get_status_theme_paths();
            if (imgui.BeginCombo('Status Icon Theme', gConfig.statusIconTheme)) then
                for i = 1,#status_theme_paths,1 do
                    local is_selected = i == gConfig.statusIconTheme;

                    if (imgui.Selectable(status_theme_paths[i], is_selected)) then
                        gConfig.statusIconTheme = status_theme_paths[i];
                        statusHandler.clear_cache();
                    end

                    if (is_selected) then
                        imgui.SetItemDefaultFocus();
                    end
                end
                imgui.EndCombo();
            end

            -- Job Icon Theme
            local job_theme_paths = statusHandler.get_job_theme_paths();

            if (imgui.BeginCombo('Job Icon Theme', gConfig.jobIconTheme)) then
                for i = 1,#job_theme_paths,1 do
                    local is_selected = i == gConfig.jobIconTheme;

                    if (imgui.Selectable(job_theme_paths[i], is_selected)) then
                        gConfig.jobIconTheme = job_theme_paths[i];
                        statusHandler.clear_cache();
                    end

                    if (is_selected) then
                        imgui.SetItemDefaultFocus();
                    end
                end
                imgui.EndCombo();
            end

            imgui.EndChild();
        end
        if (imgui.CollapsingHeader("Player Bar")) then
            imgui.BeginChild("PlayerBarSettings", { 0, 160 }, true);
            if (imgui.Checkbox(' Enabled', { gConfig.showPlayerBar })) then
                gConfig.showPlayerBar = not gConfig.showPlayerBar;
                UpdateSettings();
            end
            local scaleX = { gConfig.playerBarScaleX };
            if (imgui.SliderFloat('Scale X', scaleX, 0.1, 3.0, '%.1f')) then
                gConfig.playerBarScaleX = scaleX[1];
                UpdateSettings();
            end
            local scaleY = { gConfig.playerBarScaleY };
            if (imgui.SliderFloat('Scale Y', scaleY, 0.1, 3.0, '%.1f')) then
                gConfig.playerBarScaleY = scaleY[1];
                UpdateSettings();
            end
            local fontOffset = { gConfig.playerBarFontOffset };
            if (imgui.SliderInt('Font Offset', fontOffset, -5, 10)) then
                gConfig.playerBarFontOffset = fontOffset[1];
                UpdateSettings();
            end
            imgui.EndChild();
        end
        if (imgui.CollapsingHeader("Target Bar")) then
            imgui.BeginChild("TargetBarSettings", { 0, 160 }, true);
            if (imgui.Checkbox(' Enabled', { gConfig.showTargetBar })) then
                gConfig.showTargetBar = not gConfig.showTargetBar;
                UpdateSettings();
            end
            if (imgui.Checkbox(' Show Percent', { gConfig.showTargetBarPercent })) then
                gConfig.showTargetBarPercent = not gConfig.showTargetBarPercent;
                UpdateSettings();
            end
            local scaleX = { gConfig.targetBarScaleX };
            if (imgui.SliderFloat('Scale X', scaleX, 0.1, 3.0, '%.1f')) then
                gConfig.targetBarScaleX = scaleX[1];
                UpdateSettings();
            end
            local scaleY = { gConfig.targetBarScaleY };
            if (imgui.SliderFloat('Scale Y', scaleY, 0.1, 3.0, '%.1f')) then
                gConfig.targetBarScaleY = scaleY[1];
                UpdateSettings();
            end
            local fontScale = { gConfig.targetBarFontScale };
            if (imgui.SliderFloat('Font Scale', fontScale, 0.1, 3.0, '%.1f')) then
                gConfig.targetBarFontScale = fontScale[1];
                UpdateSettings();
            end
            local iconScale = { gConfig.targetBarIconScale };
            if (imgui.SliderFloat('Icon Scale', iconScale, 0.1, 3.0, '%.1f')) then
                gConfig.targetBarIconScale = iconScale[1];
                UpdateSettings();
            end
            imgui.EndChild();
        end
        if (imgui.CollapsingHeader("Enemy List")) then
            imgui.BeginChild("EnemyListSettings", { 0, 160 }, true);
            if (imgui.Checkbox(' Enabled', { gConfig.showEnemyList })) then
                gConfig.showEnemyList = not gConfig.showEnemyList;
                UpdateSettings();
            end
            local scaleX = { gConfig.enemyListScaleX };
            if (imgui.SliderFloat('Scale X', scaleX, 0.1, 3.0, '%.1f')) then
                gConfig.enemyListScaleX = scaleX[1];
                UpdateSettings();
            end
            local scaleY = { gConfig.enemyListScaleY };
            if (imgui.SliderFloat('Scale Y', scaleY, 0.1, 3.0, '%.1f')) then
                gConfig.enemyListScaleY = scaleY[1];
                UpdateSettings();
            end
            local fontScale = { gConfig.enemyListFontScale };
            if (imgui.SliderFloat('Font Scale', fontScale, 0.1, 3.0, '%.1f')) then
                gConfig.enemyListFontScale = fontScale[1];
                UpdateSettings();
            end
            local iconScale = { gConfig.enemyListIconScale };
            if (imgui.SliderFloat('Icon Scale', iconScale, 0.1, 3.0, '%.1f')) then
                gConfig.enemyListIconScale = iconScale[1];
                UpdateSettings();
            end
            imgui.EndChild();
        end
        if (imgui.CollapsingHeader("Party List")) then
            imgui.BeginChild("PartyListSettings", { 0, 160 }, true);
            if (imgui.Checkbox(' Enabled', { gConfig.showPartyList })) then
                gConfig.showPartyList = not gConfig.showPartyList;
                UpdateSettings();
            end
            if (imgui.Checkbox(' Show When Solo', { gConfig.showPartyListWhenSolo })) then
                gConfig.showPartyListWhenSolo = not gConfig.showPartyListWhenSolo;
                UpdateSettings();
            end
            local scaleX = { gConfig.partyListScaleX };
            if (imgui.SliderFloat('Scale X', scaleX, 0.1, 3.0, '%.1f')) then
                gConfig.partyListScaleX = scaleX[1];
                UpdateSettings();
            end
            local scaleY = { gConfig.partyListScaleY };
            if (imgui.SliderFloat('Scale Y', scaleY, 0.1, 3.0, '%.1f')) then
                gConfig.partyListScaleY = scaleY[1];
                UpdateSettings();
            end
            local comboBoxItems = {};
            comboBoxItems[0] = 'HorizonXI';
            comboBoxItems[1] = 'FFXIV';
            comboBoxItems[2] = 'FFXI';
            gConfig.partyListStatusTheme = math.clamp(gConfig.partyListStatusTheme, 0, 2);
            if(imgui.BeginCombo('Status Theme', comboBoxItems[gConfig.partyListStatusTheme])) then
                for i = 0,#comboBoxItems do
                    local is_selected = i == gConfig.partyListStatusTheme;

                    if (imgui.Selectable(comboBoxItems[i], is_selected) and gConfig.partyListStatusTheme ~= i) then
                        gConfig.partyListStatusTheme = i;
                        UpdateSettings();
                    end
                    if(is_selected) then
                        imgui.SetItemDefaultFocus();
                    end
                end
                imgui.EndCombo();
            end
            local buffScale = { gConfig.partyListBuffScale };
            if (imgui.SliderFloat('Buff Scale', buffScale, 0.1, 3.0, '%.1f')) then
                gConfig.partyListBuffScale = buffScale[1];
                UpdateSettings();
            end
            local fontOffset = { gConfig.partyListFontOffset };
            if (imgui.SliderInt('Font Offset', fontOffset, -5, 10)) then
                gConfig.partyListFontOffset = fontOffset[1];
                UpdateSettings();
            end
            imgui.EndChild();
        end
        if (imgui.CollapsingHeader("Exp Bar")) then
            imgui.BeginChild("ExpBarSettings", { 0, 160 }, true);
            if (imgui.Checkbox(' Enabled', { gConfig.showExpBar })) then
                gConfig.showExpBar = not gConfig.showExpBar;
                UpdateSettings();
            end
            local scaleX = { gConfig.expBarScaleX };
            if (imgui.SliderFloat('Scale X', scaleX, 0.1, 3.0, '%.1f')) then
                gConfig.expBarScaleX = scaleX[1];
                UpdateSettings();
            end
            local scaleY = { gConfig.expBarScaleY };
            if (imgui.SliderFloat('Scale Y', scaleY, 0.1, 3.0, '%.1f')) then
                gConfig.expBarScaleY = scaleY[1];
                UpdateSettings();
            end
            local fontOffset = { gConfig.expBarFontOffset };
            if (imgui.SliderInt('Font Offset', fontOffset, -5, 10)) then
                gConfig.expBarFontOffset = fontOffset[1];
                UpdateSettings();
            end
            imgui.EndChild();
        end
        if (imgui.CollapsingHeader("Gil Tracker")) then
            imgui.BeginChild("GilTrackerSettings", { 0, 160 }, true);
            if (imgui.Checkbox(' Enabled', { gConfig.showGilTracker })) then
                gConfig.showGilTracker = not gConfig.showGilTracker;
                UpdateSettings();
            end
            local scale = { gConfig.gilTrackerScale };
            if (imgui.SliderFloat('Scale', scale, 0.1, 3.0, '%.1f')) then
                gConfig.gilTrackerScale = scale[1];
                UpdateSettings();
            end
            local fontOffset = { gConfig.gilTrackerFontOffset };
            if (imgui.SliderInt('Font Offset', fontOffset, -5, 10)) then
                gConfig.gilTrackerFontOffset = fontOffset[1];
                UpdateSettings();
            end
            imgui.EndChild();
        end
        if (imgui.CollapsingHeader("Inventory Tracker")) then
            imgui.BeginChild("InventoryTrackerSettings", { 0, 160 }, true);
            if (imgui.Checkbox('Enabled', { gConfig.showInventoryTracker })) then
                gConfig.showInventoryTracker = not gConfig.showInventoryTracker;
                UpdateSettings();
            end
            local scale = { gConfig.inventoryTrackerScale };
            if (imgui.SliderFloat('Scale', scale, 0.1, 3.0, '%.1f')) then
                gConfig.inventoryTrackerScale = scale[1];
                UpdateSettings();
            end
            local fontOffset = { gConfig.inventoryTrackerFontOffset };
            if (imgui.SliderInt('Font Offset', fontOffset, -5, 10)) then
                gConfig.inventoryTrackerFontOffset = fontOffset[1];
                UpdateSettings();
            end
            imgui.EndChild();
        end
        if (imgui.CollapsingHeader("Cast Bar")) then
            imgui.BeginChild("CastBarSettings", { 0, 160 }, true);
            if (imgui.Checkbox(' Enabled', { gConfig.showCastBar })) then
                gConfig.showCastBar = not gConfig.showCastBar;
                UpdateSettings();
            end
            local scaleX = { gConfig.castBarScaleX };
            if (imgui.SliderFloat('Scale X', scaleX, 0.1, 3.0, '%.1f')) then
                gConfig.castBarScaleX = scaleX[1];
                UpdateSettings();
            end
            local scaleY = { gConfig.castBarScaleY };
            if (imgui.SliderFloat('Scale Y', scaleY, 0.1, 3.0, '%.1f')) then
                gConfig.castBarScaleY = scaleY[1];
                UpdateSettings();
            end
            imgui.EndChild();
        end
        imgui.EndChild();
    end
	imgui.End();
end

return config;