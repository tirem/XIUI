require ("common");
require('helpers');
local statusHandler = require('statushandler');
local imgui = require("imgui");

local config = {};

config.DrawWindow = function(us)
    imgui.PushStyleColor(ImGuiCol_WindowBg, {0,0.06,.16,.9});
	imgui.PushStyleColor(ImGuiCol_TitleBg, {0,0.06,.16, .7});
	imgui.PushStyleColor(ImGuiCol_TitleBgActive, {0,0.06,.16, .9});
	imgui.PushStyleColor(ImGuiCol_TitleBgCollapsed, {0,0.06,.16, .5});
    imgui.PushStyleColor(ImGuiCol_Header, {0,0.06,.16,.7});
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, {0,0.06,.16, .9});
    imgui.PushStyleColor(ImGuiCol_HeaderActive, {0,0.06,.16, 1});
    imgui.PushStyleColor(ImGuiCol_FrameBg, {0,0.06,.16, 1});
    imgui.SetNextWindowSize({ 600, 600 }, ImGuiCond_FirstUseEver);
    if(showConfig[1] and imgui.Begin(("HXUI Config"):fmt(addon.version), showConfig, bit.bor(ImGuiWindowFlags_NoSavedSettings))) then
        if(imgui.Button("Restore Defaults", { 130, 20 })) then
            ResetSettings();
            UpdateSettings();
        end
        imgui.SameLine();
        if(imgui.Button("Patch Notes", { 130, 20 })) then
            gConfig.patchNotesVer = -1;
            gShowPatchNotes = { true; }
            UpdateSettings();
        end
        imgui.BeginChild("Config Options", { 0, 0 }, true);
        if (imgui.CollapsingHeader("General")) then
            imgui.BeginChild("GeneralSettings", { 0, 210 }, true);
            if (imgui.Checkbox('Lock HUD Position', { gConfig.lockPositions })) then
                gConfig.lockPositions = not gConfig.lockPositions;
                UpdateSettings();
            end
            -- Status Icon Theme
            local status_theme_paths = statusHandler.get_status_theme_paths();
            if (imgui.BeginCombo('Status Icon Theme', gConfig.statusIconTheme)) then
                for i = 1,#status_theme_paths,1 do
                    local is_selected = i == gConfig.statusIconTheme;

                    if (imgui.Selectable(status_theme_paths[i], is_selected) and status_theme_paths[i] ~= gConfig.statusIconTheme) then
                        gConfig.statusIconTheme = status_theme_paths[i];
                        statusHandler.clear_cache();
                        UpdateSettings();
                    end

                    if (is_selected) then
                        imgui.SetItemDefaultFocus();
                    end
                end
                imgui.EndCombo();
            end
            imgui.ShowHelp('The folder to pull status icons from. [HXUI\\assets\\status]');

            -- Job Icon Theme
            local job_theme_paths = statusHandler.get_job_theme_paths();
            if (imgui.BeginCombo('Job Icon Theme', gConfig.jobIconTheme)) then
                for i = 1,#job_theme_paths,1 do
                    local is_selected = i == gConfig.jobIconTheme;

                    if (imgui.Selectable(job_theme_paths[i], is_selected) and job_theme_paths[i] ~= gConfig.jobIconTheme) then
                        gConfig.jobIconTheme = job_theme_paths[i];
                        statusHandler.clear_cache();
                        UpdateSettings();
                    end

                    if (is_selected) then
                        imgui.SetItemDefaultFocus();
                    end
                end
                imgui.EndCombo();
            end
            imgui.ShowHelp('The folder to pull job icons from. [HXUI\\assets\\jobs]');

            if (imgui.Checkbox('Show Health Bar Flash Effects', { gConfig.healthBarFlashEnabled })) then
                gConfig.healthBarFlashEnabled = not gConfig.healthBarFlashEnabled;
                UpdateSettings();
            end

            local noBookendRounding = { gConfig.noBookendRounding };
            if (imgui.SliderInt('Basic Bar Roundness', noBookendRounding, 0, 10)) then
                gConfig.noBookendRounding = noBookendRounding[1];
                UpdateSettings();
            end
            imgui.ShowHelp('For bars with no bookends, how round they should be.');

            local tooltipScale = { gConfig.tooltipScale };
            if (imgui.SliderFloat('Tooltip Scale', tooltipScale, 0.1, 3.0, '%.2f')) then
                gConfig.tooltipScale = tooltipScale[1];
                UpdateSettings();
            end
            imgui.ShowHelp('Scales the size of the tooltip. Note that text may appear blured if scaled too large.');

            if (imgui.Checkbox('Hide During Events', { gConfig.hideDuringEvents })) then
                gConfig.hideDuringEvents = not gConfig.hideDuringEvents;
                UpdateSettings();
            end

            imgui.EndChild();
        end
        if (imgui.CollapsingHeader("Player Bar")) then
            imgui.BeginChild("PlayerBarSettings", { 0, 210 }, true);
            if (imgui.Checkbox('Enabled', { gConfig.showPlayerBar })) then
                gConfig.showPlayerBar = not gConfig.showPlayerBar;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Bookends', { gConfig.showPlayerBarBookends })) then
                gConfig.showPlayerBarBookends = not gConfig.showPlayerBarBookends;
                UpdateSettings();
            end
            if (imgui.Checkbox('Hide During Events', { gConfig.playerBarHideDuringEvents })) then
                gConfig.playerBarHideDuringEvents = not gConfig.playerBarHideDuringEvents;
                UpdateSettings();
            end
            if (imgui.Checkbox('Always Show MP Bar', { gConfig.alwaysShowMpBar })) then
                gConfig.alwaysShowMpBar = not gConfig.alwaysShowMpBar;
                UpdateSettings();
            end
            imgui.ShowHelp('Always display the MP Bar even if your current jobs cannot cast spells.'); 
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
            if (imgui.SliderInt('Font Scale', fontOffset, -5, 10)) then
                gConfig.playerBarFontOffset = fontOffset[1];
                UpdateSettings();
            end
            imgui.EndChild();
        end
        if (imgui.CollapsingHeader("Target Bar")) then
            imgui.BeginChild("TargetBarSettings", { 0, 270 }, true);
            if (imgui.Checkbox('Enabled', { gConfig.showTargetBar })) then
                gConfig.showTargetBar = not gConfig.showTargetBar;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Bookends', { gConfig.showTargetBarBookends })) then
                gConfig.showTargetBarBookends = not gConfig.showTargetBarBookends;
                UpdateSettings();
            end
            if (imgui.Checkbox('Hide During Events', { gConfig.targetBarHideDuringEvents })) then
                gConfig.targetBarHideDuringEvents = not gConfig.targetBarHideDuringEvents;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Enemy Id', { gConfig.showEnemyId })) then
                gConfig.showEnemyId = not gConfig.showEnemyId;
                UpdateSettings();
            end
            imgui.ShowHelp('Display the internal ID of the monster next to its name.'); 
            if (imgui.Checkbox('Always Show Health Percent', { gConfig.alwaysShowHealthPercent })) then
                gConfig.alwaysShowHealthPercent = not gConfig.alwaysShowHealthPercent;
                UpdateSettings();
            end
            imgui.ShowHelp('Always display the percent of HP remanining regardless if the target is an enemy or not.');
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
            local fontOffset = { gConfig.targetBarFontOffset };
            if (imgui.SliderInt('Font Scale', fontOffset, -5, 10)) then
                gConfig.targetBarFontOffset = fontOffset[1];
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
            imgui.BeginChild("EnemyListSettings", { 0, 180 }, true);
            if (imgui.Checkbox('Enabled', { gConfig.showEnemyList })) then
                gConfig.showEnemyList = not gConfig.showEnemyList;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Bookends', { gConfig.showEnemyListBookends })) then
                gConfig.showEnemyListBookends = not gConfig.showEnemyListBookends;
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
            imgui.BeginChild("PartyListSettings", { 0, 580 }, true);
            if (imgui.Checkbox('Enabled', { gConfig.showPartyList })) then
                gConfig.showPartyList = not gConfig.showPartyList;
                UpdateSettings();
            end
            if (imgui.Checkbox('Preview Full Party (when config open)', { gConfig.partyListPreview })) then
                gConfig.partyListPreview = not gConfig.partyListPreview;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Bookends', { gConfig.showPartyListBookends })) then
                gConfig.showPartyListBookends = not gConfig.showPartyListBookends;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show When Solo', { gConfig.showPartyListWhenSolo })) then
                gConfig.showPartyListWhenSolo = not gConfig.showPartyListWhenSolo;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Title', { gConfig.showPartyListTitle })) then
                gConfig.showPartyListTitle = not gConfig.showPartyListTitle;
                UpdateSettings();
            end
            if (imgui.Checkbox('Hide During Events', { gConfig.partyListHideDuringEvents })) then
                gConfig.partyListHideDuringEvents = not gConfig.partyListHideDuringEvents;
                UpdateSettings();
            end
            if (imgui.Checkbox('Align Bottom', { gConfig.partyListAlignBottom })) then
                gConfig.partyListAlignBottom = not gConfig.partyListAlignBottom;
                UpdateSettings();
            end
            if (imgui.Checkbox('Expand Height', { gConfig.partyListExpandHeight })) then
                gConfig.partyListExpandHeight = not gConfig.partyListExpandHeight;
                UpdateSettings();
            end
            local minRows = { gConfig.partyListMinRows };
            if (imgui.SliderInt('Min Rows', minRows, 1, 6)) then
                gConfig.partyListMinRows = minRows[1];
                UpdateSettings();
            end
            local scaleX = { gConfig.partyListScaleX };
            if (imgui.SliderFloat('Scale X', scaleX, 0.1, 3.0, '%.2f')) then
                gConfig.partyListScaleX = scaleX[1];
                UpdateSettings();
            end
            local scaleY = { gConfig.partyListScaleY };
            if (imgui.SliderFloat('Scale Y', scaleY, 0.1, 3.0, '%.2f')) then
                gConfig.partyListScaleY = scaleY[1];
                UpdateSettings();
            end

            -- Background
            local bgScale = { gConfig.partyListBgScale };
            if (imgui.SliderFloat('Background Scale', bgScale, 0.1, 3.0, '%.2f')) then
                gConfig.partyListBgScale = bgScale[1];
                UpdateSettings();
            end

            local bgColor = { gConfig.partyListBgColor[1] / 255, gConfig.partyListBgColor[2] / 255, gConfig.partyListBgColor[3] / 255, gConfig.partyListBgColor[4] / 255 };
            if (imgui.ColorEdit4('Background Color', bgColor, ImGuiColorEditFlags_AlphaBar)) then
                gConfig.partyListBgColor[1] = bgColor[1] * 255;
                gConfig.partyListBgColor[2] = bgColor[2] * 255;
                gConfig.partyListBgColor[3] = bgColor[3] * 255;
                gConfig.partyListBgColor[4] = bgColor[4] * 255;
                UpdateSettings();
            end

            local borderColor = { gConfig.partyListBorderColor[1] / 255, gConfig.partyListBorderColor[2] / 255, gConfig.partyListBorderColor[3] / 255, gConfig.partyListBorderColor[4] / 255 };
            if (imgui.ColorEdit4('Border Color', borderColor, ImGuiColorEditFlags_AlphaBar)) then
                gConfig.partyListBorderColor[1] = borderColor[1] * 255;
                gConfig.partyListBorderColor[2] = borderColor[2] * 255;
                gConfig.partyListBorderColor[3] = borderColor[3] * 255;
                gConfig.partyListBorderColor[4] = borderColor[4] * 255;
                UpdateSettings();
            end

            local bg_theme_paths = statusHandler.get_background_paths();
            if (imgui.BeginCombo('Background', gConfig.partyListBackgroundName)) then
                for i = 1,#bg_theme_paths,1 do
                    local is_selected = i == gConfig.partyListBackgroundName;

                    if (imgui.Selectable(bg_theme_paths[i], is_selected) and bg_theme_paths[i] ~= gConfig.partyListBackgroundName) then
                        gConfig.partyListBackgroundName = bg_theme_paths[i];
                        statusHandler.clear_cache();
                        UpdateSettings();
                    end

                    if (is_selected) then
                        imgui.SetItemDefaultFocus();
                    end
                end
                imgui.EndCombo();
            end
            imgui.ShowHelp('The image to use for the party list background. [Resolution: 512x512 @ HXUI\\assets\\backgrounds]'); 
            
            -- Arrow
            local cursor_paths = statusHandler.get_cursor_paths();
            if (imgui.BeginCombo('Cursor', gConfig.partyListCursor)) then
                for i = 1,#cursor_paths,1 do
                    local is_selected = i == gConfig.partyListCursor;

                    if (imgui.Selectable(cursor_paths[i], is_selected) and cursor_paths[i] ~= gConfig.partyListCursor) then
                        gConfig.partyListCursor = cursor_paths[i];
                        statusHandler.clear_cache();
                        UpdateSettings();
                    end

                    if (is_selected) then
                        imgui.SetItemDefaultFocus();
                    end
                end
                imgui.EndCombo();
            end
            imgui.ShowHelp('The image to use for the party list cursor. [@ HXUI\\assets\\cursors]'); 
            

            local comboBoxItems = {};
            comboBoxItems[0] = 'HorizonXI';
            comboBoxItems[1] = 'HorizonXI-R';
            comboBoxItems[2] = 'FFXIV';
            comboBoxItems[3] = 'FFXI';
            comboBoxItems[4] = 'Disabled';
            gConfig.partyListStatusTheme = math.clamp(gConfig.partyListStatusTheme, 0, 4);
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
            if (imgui.SliderFloat('Icon Scale', buffScale, 0.1, 3.0, '%.1f')) then
                gConfig.partyListBuffScale = buffScale[1];
                UpdateSettings();
            end
            local fontOffset = { gConfig.partyListFontOffset };
            if (imgui.SliderInt('Font Scale', fontOffset, -5, 10)) then
                gConfig.partyListFontOffset = fontOffset[1];
                UpdateSettings();
            end
            local entrySpacing = { gConfig.partyListEntrySpacing };
            if (imgui.SliderInt('Entry Spacing', entrySpacing, -20, 20)) then
                gConfig.partyListEntrySpacing = entrySpacing[1];
                UpdateSettings();
            end
            imgui.EndChild();
        end
        if (imgui.CollapsingHeader("Exp Bar")) then
            imgui.BeginChild("ExpBarSettings", { 0, 300 }, true);
            if (imgui.Checkbox('Enabled', { gConfig.showExpBar })) then
                gConfig.showExpBar = not gConfig.showExpBar;
                UpdateSettings();
            end
            if (imgui.Checkbox('Limit Points Mode', { gConfig.expBarLimitPointsMode })) then
                gConfig.expBarLimitPointsMode = not gConfig.expBarLimitPointsMode;
                UpdateSettings();
            end
            imgui.ShowHelp('Shows Limit Points if character is set to earn Limit Points in the game.');
            if (imgui.Checkbox('Inline Mode', { gConfig.expBarInlineMode })) then
                gConfig.expBarInlineMode = not gConfig.expBarInlineMode;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Bookends', { gConfig.showExpBarBookends })) then
                gConfig.showExpBarBookends = not gConfig.showExpBarBookends;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Text', { gConfig.expBarShowText })) then
                gConfig.expBarShowText = not gConfig.expBarShowText;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Percent', { gConfig.expBarShowPercent })) then
                gConfig.expBarShowPercent = not gConfig.expBarShowPercent;
                UpdateSettings();
            end
            local scaleX = { gConfig.expBarScaleX };
            if (imgui.SliderFloat('Scale X', scaleX, 0.1, 3.0, '%.2f')) then
                gConfig.expBarScaleX = scaleX[1];
                UpdateSettings();
            end
            local scaleY = { gConfig.expBarScaleY };
            if (imgui.SliderFloat('Scale Y', scaleY, 0.1, 3.0, '%.2f')) then
                gConfig.expBarScaleY = scaleY[1];
                UpdateSettings();
            end
            local textScaleX = { gConfig.expBarTextScaleX };
            if (imgui.SliderFloat('Text Scale X', textScaleX, 0.1, 3.0, '%.2f')) then
                gConfig.expBarTextScaleX = textScaleX[1];
                UpdateSettings();
            end
            local fontOffset = { gConfig.expBarFontOffset };
            if (imgui.SliderInt('Font Height', fontOffset, -5, 10)) then
                gConfig.expBarFontOffset = fontOffset[1];
                UpdateSettings();
            end
            imgui.EndChild();
        end
        if (imgui.CollapsingHeader("Gil Tracker")) then
            imgui.BeginChild("GilTrackerSettings", { 0, 160 }, true);
            if (imgui.Checkbox('Enabled', { gConfig.showGilTracker })) then
                gConfig.showGilTracker = not gConfig.showGilTracker;
                UpdateSettings();
            end
            local scale = { gConfig.gilTrackerScale };
            if (imgui.SliderFloat('Scale', scale, 0.1, 3.0, '%.1f')) then
                gConfig.gilTrackerScale = scale[1];
                UpdateSettings();
            end
            local fontOffset = { gConfig.gilTrackerFontOffset };
            if (imgui.SliderInt('Font Scale', fontOffset, -5, 10)) then
                gConfig.gilTrackerFontOffset = fontOffset[1];
                UpdateSettings();
            end
            if (imgui.Checkbox('Right Align', { gConfig.gilTrackerRightAlign })) then
                gConfig.gilTrackerRightAlign = not gConfig.gilTrackerRightAlign;
                UpdateSettings();
            end
            local posOffset = { gConfig.gilTrackerPosOffset[1], gConfig.gilTrackerPosOffset[2] };
            if (imgui.InputInt2('Position Offset', posOffset)) then
                gConfig.gilTrackerPosOffset[1] = posOffset[1];
                gConfig.gilTrackerPosOffset[2] = posOffset[2];
                UpdateSettings();
            end
            imgui.EndChild();
        end
        if (imgui.CollapsingHeader("Inventory Tracker")) then
            imgui.BeginChild("InventoryTrackerSettings", { 0, 210 }, true);
            if (imgui.Checkbox('Enabled', { gConfig.showInventoryTracker })) then
                gConfig.showInventoryTracker = not gConfig.showInventoryTracker;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Count', { gConfig.inventoryShowCount })) then
                gConfig.inventoryShowCount = not gConfig.inventoryShowCount;
                UpdateSettings();
            end
            local columnCount = { gConfig.inventoryTrackerColumnCount };
            if (imgui.SliderInt('Columns', columnCount, 1, 80)) then
                gConfig.inventoryTrackerColumnCount = columnCount[1];
                UpdateSettings();
            end
            local rowCount = { gConfig.inventoryTrackerRowCount };
            if (imgui.SliderInt('Rows', rowCount, 1, 80)) then
                gConfig.inventoryTrackerRowCount = rowCount[1];
                UpdateSettings();
            end
            local opacity = { gConfig.inventoryTrackerOpacity };
            if (imgui.SliderFloat('Opacity', opacity, 0, 1.0, '%.2f')) then
                gConfig.inventoryTrackerOpacity = opacity[1];
                UpdateSettings();
            end
            local scale = { gConfig.inventoryTrackerScale };
            if (imgui.SliderFloat('Scale', scale, 0.1, 3.0, '%.1f')) then
                gConfig.inventoryTrackerScale = scale[1];
                UpdateSettings();
            end
            local fontOffset = { gConfig.inventoryTrackerFontOffset };
            if (imgui.SliderInt('Font Scale', fontOffset, -5, 10)) then
                gConfig.inventoryTrackerFontOffset = fontOffset[1];
                UpdateSettings();
            end
            imgui.EndChild();
        end
        if (imgui.CollapsingHeader("Cast Bar")) then
            imgui.BeginChild("CastBarSettings", { 0, 160 }, true);
            if (imgui.Checkbox('Enabled', { gConfig.showCastBar })) then
                gConfig.showCastBar = not gConfig.showCastBar;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Bookends', { gConfig.showCastBarBookends })) then
                gConfig.showCastBarBookends = not gConfig.showCastBarBookends;
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
            local fontOffset = { gConfig.castBarFontOffset };
            if (imgui.SliderInt('Font Scale', fontOffset, -5, 10)) then
                gConfig.castBarFontOffset = fontOffset[1];
                UpdateSettings();
            end
            imgui.EndChild();
        end
        imgui.EndChild();
    end
    imgui.PopStyleColor(8);
	imgui.End();
end

return config;