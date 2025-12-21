--[[
* XIUI Config Menu - Enemy List Settings
* Contains settings and color settings for Enemy List
]]--

require('common');
require('handlers.helpers');
local components = require('config.components');
local imgui = require('imgui');

local M = {};

-- Section: Enemy List Settings
function M.DrawSettings()
    components.DrawCheckbox('Enabled', 'showEnemyList', CheckVisibility);
    components.DrawCheckbox('Preview Enemies (when config open)', 'enemyListPreview');

    if components.CollapsingSection('Display Options##enemyList') then
        components.DrawCheckbox('Show Distance', 'showEnemyDistance');
        components.DrawCheckbox('Show HP% Text', 'showEnemyHPPText');
        components.DrawCheckbox('Show Enemy Targets', 'showEnemyListTargets');
        imgui.ShowHelp('Shows who each enemy is targeting based on their last action.');
        components.DrawCheckbox('Show Bookends', 'showEnemyListBookends');
        components.DrawCheckbox('Show Borders', 'showEnemyListBorders');
        imgui.ShowHelp('Draws a border around each enemy in the list');
        if gConfig.showEnemyListBorders then
            imgui.SameLine();
            components.DrawCheckbox('Use Name Color', 'showEnemyListBordersUseNameColor');
            imgui.ShowHelp('Use enemy name color as the default border color');
        end

        if (not HzLimitedMode) then
            components.DrawCheckbox('Click to Target', 'enableEnemyListClickTarget');
            imgui.ShowHelp('Click on an enemy entry to target it. Requires /shorthand to be enabled.');
        end
    end

    if components.CollapsingSection('Scale & Position##enemyList') then
        components.DrawSlider('Scale X', 'enemyListScaleX', 0.1, 3.0, '%.1f');
        components.DrawSlider('Scale Y', 'enemyListScaleY', 0.1, 3.0, '%.1f');
        components.DrawSlider('Rows Per Column', 'enemyListRowsPerColumn', 1, 20);
        imgui.ShowHelp('Number of enemies to show per column before starting a new column.');
        components.DrawSlider('Max Columns', 'enemyListMaxColumns', 1, 5);
        imgui.ShowHelp('Maximum number of columns to display. Total enemies = Rows x Columns.');
        components.DrawSlider('Row Spacing', 'enemyListRowSpacing', 0, 20);
        imgui.ShowHelp('Vertical space between enemy entries.');
        components.DrawSlider('Column Spacing', 'enemyListColumnSpacing', 0, 50);
        imgui.ShowHelp('Horizontal space between columns.');
    end

    if components.CollapsingSection('Text Settings##enemyList') then
        components.DrawSlider('Name Text Size', 'enemyListNameFontSize', 8, 36);
        if (gConfig.showEnemyDistance) then
            components.DrawSlider('Distance Text Size', 'enemyListDistanceFontSize', 8, 36);
        end
        if (gConfig.showEnemyHPPText) then
            components.DrawSlider('HP% Text Size', 'enemyListPercentFontSize', 8, 36);
        end
        if (gConfig.showEnemyListTargets) then
            components.DrawSlider('Target Text Size', 'enemyListTargetFontSize', 8, 36);
        end
    end

    if components.CollapsingSection('Debuffs##enemyList') then
        components.DrawCheckbox('Show Debuffs', 'showEnemyListDebuffs');
        if (gConfig.showEnemyListDebuffs) then
            components.DrawAnchorDropdown('Debuff Anchor', gConfig, 'enemyListDebuffsAnchor',
                'Which side of the enemy entry to anchor debuff icons.');
            components.DrawSlider('Debuff Offset X', 'enemyListDebuffOffsetX', -100, 200);
            imgui.ShowHelp('Horizontal offset for debuff icons from the anchor edge.');
            components.DrawSlider('Debuff Offset Y', 'enemyListDebuffOffsetY', -100, 200);
            imgui.ShowHelp('Vertical offset for debuff icons from top of entry.');
            components.DrawSlider('Status Effect Icon Size', 'enemyListIconScale', 0.1, 3.0, '%.1f');
        end
    end

    if components.CollapsingSection('Enemy Targets##enemyList', false) then
        if (gConfig.showEnemyListTargets) then
            components.DrawSlider('Target Offset X', 'enemyListTargetOffsetX', -100, 200);
            imgui.ShowHelp('Horizontal offset for enemy target container from the enemy entry.');
            components.DrawSlider('Target Offset Y', 'enemyListTargetOffsetY', -100, 100);
            imgui.ShowHelp('Vertical offset for enemy target container.');
            components.DrawSlider('Target Width', 'enemyListTargetWidth', 50, 200);
            imgui.ShowHelp('Width of the enemy target container.');
        else
            imgui.TextDisabled('Enable "Show Enemy Targets" in Display Options to configure.');
        end
    end
end

-- Section: Enemy List Color Settings
function M.DrawColorSettings()
    if components.CollapsingSection('HP Bar Color##enemyListColor') then
        components.DrawGradientPicker("Enemy HP Bar", gConfig.colorCustomization.enemyList.hpGradient, "Enemy HP bar color");
    end

    if components.CollapsingSection('Text Colors##enemyListColor') then
        components.DrawTextColorPicker("Distance Text", gConfig.colorCustomization.enemyList, 'distanceTextColor', "Color of distance text");
        components.DrawTextColorPicker("HP% Text", gConfig.colorCustomization.enemyList, 'percentTextColor', "Color of HP percentage text");
        components.DrawTextColorPicker("Target Name Text", gConfig.colorCustomization.enemyList, 'targetNameTextColor', "Color of enemy's target name");
        imgui.ShowHelp("Enemy name colors are in the Global section");
    end

    if components.CollapsingSection('Background Colors##enemyListColor') then
        components.DrawTextColorPicker("Background", gConfig.colorCustomization.enemyList, 'backgroundColor', "Background color for list entries");
        components.DrawTextColorPicker("Default Border", gConfig.colorCustomization.enemyList, 'borderColor', "Default border color for enemies");
        components.DrawTextColorPicker("Target Border", gConfig.colorCustomization.enemyList, 'targetBorderColor', "Border color for currently targeted enemy");
        components.DrawTextColorPicker("Subtarget Border", gConfig.colorCustomization.enemyList, 'subtargetBorderColor', "Border color for subtargeted enemy");
    end
end

return M;
