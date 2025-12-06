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

    if components.CollapsingSection('Display Options##enemyList') then
        components.DrawCheckbox('Show Distance', 'showEnemyDistance');
        if (gConfig.showEnemyDistance) then
            components.DrawSlider('Distance Font Size', 'enemyListDistanceFontSize', 8, 36);
        end
        components.DrawCheckbox('Show HP% Text', 'showEnemyHPPText');
        if (gConfig.showEnemyHPPText) then
            components.DrawSlider('HP% Font Size', 'enemyListPercentFontSize', 8, 36);
        end
        components.DrawCheckbox('Show Enemy Targets', 'showEnemyListTargets');
        imgui.ShowHelp('Shows who each enemy is targeting based on their last action.');
        components.DrawCheckbox('Show Bookends', 'showEnemyListBookends');
        if (not HzLimitedMode) then
            components.DrawCheckbox('Click to Target', 'enableEnemyListClickTarget');
            imgui.ShowHelp('Click on an enemy entry to target it. Requires /shorthand to be enabled.');
        end
    end

    if components.CollapsingSection('Debuffs##enemyList') then
        components.DrawCheckbox('Show Debuffs', 'showEnemyListDebuffs');
        if (gConfig.showEnemyListDebuffs) then
            components.DrawCheckbox('Right Align Debuffs', 'enemyListDebuffsRightAlign');
            imgui.ShowHelp('When enabled, debuff icons align to the right edge of each enemy entry instead of the left.');
            components.DrawSlider('Debuff Offset X', 'enemyListDebuffOffsetX', -100, 200);
            imgui.ShowHelp('Horizontal offset for debuff icons. Offsets from left edge (or right edge if right-aligned).');
            components.DrawSlider('Debuff Offset Y', 'enemyListDebuffOffsetY', -100, 200);
            imgui.ShowHelp('Vertical offset for debuff icons from top of entry.');
            components.DrawSlider('Status Effect Icon Size', 'enemyListIconScale', 0.1, 3.0, '%.1f');
        end
    end

    if components.CollapsingSection('Scale & Layout##enemyList') then
        components.DrawSlider('Scale X', 'enemyListScaleX', 0.1, 3.0, '%.1f');
        components.DrawSlider('Scale Y', 'enemyListScaleY', 0.1, 3.0, '%.1f');
        components.DrawSlider('Name Font Size', 'enemyListNameFontSize', 8, 36);
        components.DrawSlider('Rows Per Column', 'enemyListRowsPerColumn', 1, 20);
        imgui.ShowHelp('Number of enemies to show per column before starting a new column.');
        components.DrawSlider('Max Columns', 'enemyListMaxColumns', 1, 5);
        imgui.ShowHelp('Maximum number of columns to display. Total enemies = Rows x Columns.');
        components.DrawSlider('Row Spacing', 'enemyListRowSpacing', 0, 20);
        imgui.ShowHelp('Vertical space between enemy entries.');
        components.DrawSlider('Column Spacing', 'enemyListColumnSpacing', 0, 50);
        imgui.ShowHelp('Horizontal space between columns.');
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
        imgui.ShowHelp("Enemy name colors are in the Global section");
    end

    if components.CollapsingSection('Border Colors##enemyListColor') then
        components.DrawTextColorPicker("Target Border", gConfig.colorCustomization.enemyList, 'targetBorderColor', "Border color for currently targeted enemy");
        components.DrawTextColorPicker("Subtarget Border", gConfig.colorCustomization.enemyList, 'subtargetBorderColor', "Border color for subtargeted enemy");
    end
end

return M;
