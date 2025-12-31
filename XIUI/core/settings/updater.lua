--[[
* XIUI Settings Updater
* Handles applying user settings to the adjusted settings used by modules
]]--

local gdi = require('submodules.gdifonts.include');

local M = {};

-- Helper to apply global font settings to a font_settings table
local function applyGlobalFontSettings(fontSettings, family, flags, outlineWidth)
    fontSettings.font_family = family;
    fontSettings.font_flags = flags;
    fontSettings.outline_width = outlineWidth;
end

-- Helper function to get font size hash for change detection
local function getFontSizeHash(party)
    local nameSize = party.nameFontSize or 12;
    local hpSize = party.hpFontSize or 12;
    local mpSize = party.mpFontSize or 12;
    local tpSize = party.tpFontSize or 12;
    local distSize = party.distanceFontSize or 12;
    local jobSize = party.jobFontSize or 12;
    return nameSize + (hpSize * 100) + (mpSize * 10000) + (tpSize * 1000000) + (distSize * 100000000) + (jobSize * 10000000000);
end

-- Apply user settings to adjusted settings
function M.UpdateUserSettings(gAdjustedSettings, default_settings, gConfig)
    local ds = default_settings;
    local us = gConfig;

    -- Apply global font family, weight, and outline width to all font settings
    local fontWeightFlags = GetFontWeightFlags(us.fontWeight);

    -- Target Bar fonts
    applyGlobalFontSettings(gAdjustedSettings.targetBarSettings.name_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    applyGlobalFontSettings(gAdjustedSettings.targetBarSettings.totName_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    applyGlobalFontSettings(gAdjustedSettings.targetBarSettings.distance_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    applyGlobalFontSettings(gAdjustedSettings.targetBarSettings.percent_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    applyGlobalFontSettings(gAdjustedSettings.targetBarSettings.cast_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);

    -- Player Bar fonts
    applyGlobalFontSettings(gAdjustedSettings.playerBarSettings.font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);

    -- Exp Bar fonts
    applyGlobalFontSettings(gAdjustedSettings.expBarSettings.job_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    applyGlobalFontSettings(gAdjustedSettings.expBarSettings.exp_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    applyGlobalFontSettings(gAdjustedSettings.expBarSettings.percent_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);

    -- Gil Tracker fonts
    applyGlobalFontSettings(gAdjustedSettings.gilTrackerSettings.font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);

    -- Inventory Tracker fonts
    applyGlobalFontSettings(gAdjustedSettings.inventoryTrackerSettings.font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);

    -- Satchel Tracker fonts
    applyGlobalFontSettings(gAdjustedSettings.satchelTrackerSettings.font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);

    -- Locker Tracker fonts
    applyGlobalFontSettings(gAdjustedSettings.lockerTrackerSettings.font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);

    -- Safe Tracker fonts
    applyGlobalFontSettings(gAdjustedSettings.safeTrackerSettings.font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);

    -- Storage Tracker fonts
    applyGlobalFontSettings(gAdjustedSettings.storageTrackerSettings.font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);

    -- Wardrobe Tracker fonts
    applyGlobalFontSettings(gAdjustedSettings.wardrobeTrackerSettings.font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);

    -- Party List fonts
    applyGlobalFontSettings(gAdjustedSettings.partyListSettings.hp_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    applyGlobalFontSettings(gAdjustedSettings.partyListSettings.mp_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    applyGlobalFontSettings(gAdjustedSettings.partyListSettings.tp_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    applyGlobalFontSettings(gAdjustedSettings.partyListSettings.name_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    -- Title font has italic flag combined
    gAdjustedSettings.partyListSettings.title_font_settings.font_family = us.fontFamily;
    gAdjustedSettings.partyListSettings.title_font_settings.font_flags = bit.bor(fontWeightFlags, gdi.FontFlags.Italic);
    gAdjustedSettings.partyListSettings.title_font_settings.outline_width = us.fontOutlineWidth;

    -- Cast Bar fonts
    applyGlobalFontSettings(gAdjustedSettings.castBarSettings.spell_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    applyGlobalFontSettings(gAdjustedSettings.castBarSettings.percent_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);

    -- Cast Cost fonts
    applyGlobalFontSettings(gAdjustedSettings.castCostSettings.name_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    applyGlobalFontSettings(gAdjustedSettings.castCostSettings.cost_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    applyGlobalFontSettings(gAdjustedSettings.castCostSettings.time_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    applyGlobalFontSettings(gAdjustedSettings.castCostSettings.recast_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    applyGlobalFontSettings(gAdjustedSettings.castCostSettings.cooldown_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);

    -- Enemy List fonts
    applyGlobalFontSettings(gAdjustedSettings.enemyListSettings.name_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    applyGlobalFontSettings(gAdjustedSettings.enemyListSettings.distance_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    applyGlobalFontSettings(gAdjustedSettings.enemyListSettings.percent_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    applyGlobalFontSettings(gAdjustedSettings.enemyListSettings.target_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);

    -- Mob Info fonts
    applyGlobalFontSettings(gAdjustedSettings.mobInfoSettings.level_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);

    -- Pet Bar fonts
    applyGlobalFontSettings(gAdjustedSettings.petBarSettings.name_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    applyGlobalFontSettings(gAdjustedSettings.petBarSettings.distance_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    applyGlobalFontSettings(gAdjustedSettings.petBarSettings.vitals_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    applyGlobalFontSettings(gAdjustedSettings.petBarSettings.timer_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);

    -- Notifications fonts (title uses Bold + global weight, subtitle uses no weight flags)
    applyGlobalFontSettings(gAdjustedSettings.notificationsSettings.title_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    gAdjustedSettings.notificationsSettings.title_font_settings.font_flags = bit.bor(fontWeightFlags, gdi.FontFlags.Bold);
    -- Subtitle: only apply font family and outline, NOT weight flags (keep it normal/light)
    gAdjustedSettings.notificationsSettings.font_settings.font_family = us.fontFamily;
    gAdjustedSettings.notificationsSettings.font_settings.font_flags = gdi.FontFlags.None;
    gAdjustedSettings.notificationsSettings.font_settings.outline_width = us.fontOutlineWidth;

    -- Treasure Pool fonts
    applyGlobalFontSettings(gAdjustedSettings.treasurePoolSettings.font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    applyGlobalFontSettings(gAdjustedSettings.treasurePoolSettings.title_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    -- Title font uses bold
    gAdjustedSettings.treasurePoolSettings.title_font_settings.font_flags = bit.bor(fontWeightFlags, gdi.FontFlags.Bold);

    if _XIUI_DEV_ALPHA_HOTBAR == true then
        -- Hotbar fonts (dev-only)
        applyGlobalFontSettings(gAdjustedSettings.hotbarSettings.font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
        applyGlobalFontSettings(gAdjustedSettings.hotbarSettings.keybind_font_settings, us.fontFamily, fontWeightFlags, 1);
        applyGlobalFontSettings(gAdjustedSettings.hotbarSettings.label_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
        -- Apply font heights from user settings (ensure minimum)
        gAdjustedSettings.hotbarSettings.font_settings.font_height = math.max(us.hotbarFontSize or 10, 8);
        gAdjustedSettings.hotbarSettings.keybind_font_settings.font_height = math.max(us.hotbarKeybindFontSize or 8, 6);
        gAdjustedSettings.hotbarSettings.label_font_settings.font_height = math.max(us.hotbarLabelFontSize or 10, 8);
        -- Hotbar background and scaling settings (mirrors config defaults)
        gAdjustedSettings.hotbarSettings.scaleX = us.hotbarScaleX or 1.0;
        gAdjustedSettings.hotbarSettings.scaleY = us.hotbarScaleY or 1.0;
        gAdjustedSettings.hotbarSettings.bgScale = us.hotbarBgScale or 1.0;
        gAdjustedSettings.hotbarSettings.borderScale = us.hotbarBorderScale or 1.0;
        gAdjustedSettings.hotbarSettings.background_opacity = us.hotbarBackgroundOpacity or 0.87;
        gAdjustedSettings.hotbarSettings.border_opacity = us.hotbarBorderOpacity or 1.0;

        -- Crossbar fonts
        applyGlobalFontSettings(gAdjustedSettings.crossbarSettings.keybind_font_settings, us.fontFamily, fontWeightFlags, 1);
        applyGlobalFontSettings(gAdjustedSettings.crossbarSettings.label_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
        applyGlobalFontSettings(gAdjustedSettings.crossbarSettings.trigger_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
    end;

    -- Target Bar dimensions and settings
    gAdjustedSettings.targetBarSettings.barWidth = ds.targetBarSettings.barWidth * us.targetBarScaleX;
    gAdjustedSettings.targetBarSettings.barHeight = ds.targetBarSettings.barHeight * us.targetBarScaleY;
    gAdjustedSettings.targetBarSettings.totBarHeight = ds.targetBarSettings.totBarHeight * us.targetBarScaleY;
    gAdjustedSettings.targetBarSettings.name_font_settings.font_height = math.max(us.targetBarNameFontSize, 8);
    gAdjustedSettings.targetBarSettings.totName_font_settings.font_height = math.max(us.targetBarNameFontSize, 8);
    gAdjustedSettings.targetBarSettings.distance_font_settings.font_height = math.max(us.targetBarDistanceFontSize, 8);
    gAdjustedSettings.targetBarSettings.distanceOffsetX = us.targetBarDistanceOffsetX or 0;
    gAdjustedSettings.targetBarSettings.distanceOffsetY = us.targetBarDistanceOffsetY or 0;
    gAdjustedSettings.targetBarSettings.percent_font_settings.font_height = math.max(us.targetBarPercentFontSize, 8);
    gAdjustedSettings.targetBarSettings.percentOffsetX = us.targetBarPercentOffsetX or 0;
    gAdjustedSettings.targetBarSettings.percentOffsetY = us.targetBarPercentOffsetY or 0;
    gAdjustedSettings.targetBarSettings.cast_font_settings.font_height = math.max(us.targetBarCastFontSize, 8);
    gAdjustedSettings.targetBarSettings.iconSize = ds.targetBarSettings.iconSize * us.targetBarIconScale;
    gAdjustedSettings.targetBarSettings.arrowSize = ds.targetBarSettings.arrowSize * us.targetBarScaleY;
    -- Buff/Debuff positioning
    gAdjustedSettings.targetBarSettings.buffsOffsetY = us.targetBarBuffsOffsetY;
    -- Cast bar positioning and scaling
    gAdjustedSettings.targetBarSettings.castBarOffsetY = us.targetBarCastBarOffsetY;
    gAdjustedSettings.targetBarSettings.castBarOffsetX = ds.targetBarSettings.castBarOffsetX;
    gAdjustedSettings.targetBarSettings.castBarWidth = (gAdjustedSettings.targetBarSettings.barWidth - (ds.targetBarSettings.castBarOffsetX * 2)) * us.targetBarCastBarScaleX;
    gAdjustedSettings.targetBarSettings.castBarHeight = 8 * us.targetBarCastBarScaleY;

    -- Target of Target Bar (separate scaling when split is enabled)
    gAdjustedSettings.targetBarSettings.totBarWidth = (ds.targetBarSettings.barWidth / 3) * us.totBarScaleX;
    gAdjustedSettings.targetBarSettings.totBarHeightSplit = ds.targetBarSettings.totBarHeight * us.totBarScaleY;
    gAdjustedSettings.targetBarSettings.totName_font_settings_split = {
        visible = ds.targetBarSettings.totName_font_settings.visible,
        locked = ds.targetBarSettings.totName_font_settings.locked,
        font_family = us.fontFamily,
        font_height = math.max(us.totBarFontSize, 8),
        color = us.colorCustomization.totBar.nameTextColor,
        bold = ds.targetBarSettings.totName_font_settings.bold,
        color_outline = ds.targetBarSettings.totName_font_settings.color_outline,
        draw_flags = ds.targetBarSettings.totName_font_settings.draw_flags,
        background = ds.targetBarSettings.totName_font_settings.background,
        right_justified = ds.targetBarSettings.totName_font_settings.right_justified,
    };

    -- Party List settings
    gAdjustedSettings.partyListSettings.partySettings = {
        [1] = us.partyA,
        [2] = us.partyB,
        [3] = us.partyC,
    };

    -- Store layout templates
    gAdjustedSettings.partyListSettings.layoutTemplates = {
        [0] = us.layoutHorizontal,
        [1] = us.layoutCompact,
    };

    gAdjustedSettings.partyListSettings.baseIconSize = ds.partyListSettings.iconSize;

    -- Apply font sizes for each party (hash used for change detection)
    gAdjustedSettings.partyListSettings.fontSizes = {
        us.partyA.splitFontSizes and getFontSizeHash(us.partyA) or (us.partyA.fontSize or 12),
        us.partyB.splitFontSizes and getFontSizeHash(us.partyB) or (us.partyB.fontSize or 12),
        us.partyC.splitFontSizes and getFontSizeHash(us.partyC) or (us.partyC.fontSize or 12),
    };

    gAdjustedSettings.partyListSettings.title_font_settings.font_height = math.max(us.partyListTitleFontSize, 8);

    gAdjustedSettings.partyListSettings.entrySpacing = {
        ds.partyListSettings.entrySpacing + (us.partyA.entrySpacing or 0),
        ds.partyListSettings.entrySpacing + (us.partyB.entrySpacing or 0),
        ds.partyListSettings.entrySpacing + (us.partyC.entrySpacing or 0),
    };

    -- Backwards compatibility - read from party A's layout
    local layoutA = us.partyA.layout == 1 and us.layoutCompact or us.layoutHorizontal;
    gAdjustedSettings.partyListSettings.hpBarWidth = layoutA.hpBarWidth or 150;
    gAdjustedSettings.partyListSettings.mpBarWidth = layoutA.mpBarWidth or 100;
    gAdjustedSettings.partyListSettings.tpBarWidth = layoutA.tpBarWidth or 100;
    gAdjustedSettings.partyListSettings.barHeight = layoutA.barHeight or 20;
    gAdjustedSettings.partyListSettings.barSpacing = layoutA.barSpacing or 8;
    gAdjustedSettings.partyListSettings.hpBarScaleX = us.partyA.hpBarScaleX or 1;
    gAdjustedSettings.partyListSettings.mpBarScaleX = us.partyA.mpBarScaleX or 1;
    gAdjustedSettings.partyListSettings.hpBarScaleY = us.partyA.hpBarScaleY or 1;
    gAdjustedSettings.partyListSettings.mpBarScaleY = us.partyA.mpBarScaleY or 1;

    gAdjustedSettings.partyListSettings.nameTextOffsetX = layoutA.nameTextOffsetX or 1;
    gAdjustedSettings.partyListSettings.nameTextOffsetY = layoutA.nameTextOffsetY or 0;
    gAdjustedSettings.partyListSettings.hpTextOffsetX = layoutA.hpTextOffsetX or -2;
    gAdjustedSettings.partyListSettings.hpTextOffsetY = layoutA.hpTextOffsetY or -1;
    gAdjustedSettings.partyListSettings.mpTextOffsetX = layoutA.mpTextOffsetX or -2;
    gAdjustedSettings.partyListSettings.mpTextOffsetY = layoutA.mpTextOffsetY or -1;
    gAdjustedSettings.partyListSettings.tpTextOffsetX = layoutA.tpTextOffsetX or -2;
    gAdjustedSettings.partyListSettings.tpTextOffsetY = layoutA.tpTextOffsetY or -1;

    -- Legacy compatibility
    gAdjustedSettings.partyListSettings.iconSize = ds.partyListSettings.iconSize * (us.partyA.buffScale or 1);
    gAdjustedSettings.partyListSettings.expandHeight = us.partyA.expandHeight or false;
    gAdjustedSettings.partyListSettings.alignBottom = us.partyA.alignBottom or false;
    gAdjustedSettings.partyListSettings.minRows = us.partyA.minRows or 1;

    -- Player Bar
    gAdjustedSettings.playerBarSettings.barWidth = ds.playerBarSettings.barWidth * us.playerBarScaleX;
    gAdjustedSettings.playerBarSettings.barSpacing = ds.playerBarSettings.barSpacing * us.playerBarScaleX;
    gAdjustedSettings.playerBarSettings.barHeight = ds.playerBarSettings.barHeight * us.playerBarScaleY;
    gAdjustedSettings.playerBarSettings.font_settings.font_height = math.max(us.playerBarFontSize, 8);

    -- Exp Bar
    gAdjustedSettings.expBarSettings.barWidth = ds.expBarSettings.barWidth * us.expBarScaleX;
    gAdjustedSettings.expBarSettings.barHeight = ds.expBarSettings.barHeight * us.expBarScaleY;
    gAdjustedSettings.expBarSettings.job_font_settings.font_height = math.max(us.expBarFontSize, 8);
    gAdjustedSettings.expBarSettings.exp_font_settings.font_height = math.max(us.expBarFontSize, 8);
    gAdjustedSettings.expBarSettings.percent_font_settings.font_height = math.max(us.expBarFontSize, 8);
    -- Text position offsets
    gAdjustedSettings.expBarSettings.jobTextOffsetX = us.expBarJobTextOffsetX or 0;
    gAdjustedSettings.expBarSettings.jobTextOffsetY = us.expBarJobTextOffsetY or 0;
    gAdjustedSettings.expBarSettings.expTextOffsetX = us.expBarExpTextOffsetX or 0;
    gAdjustedSettings.expBarSettings.expTextOffsetY = us.expBarExpTextOffsetY or 0;
    gAdjustedSettings.expBarSettings.percentTextOffsetX = us.expBarPercentTextOffsetX or 0;
    gAdjustedSettings.expBarSettings.percentTextOffsetY = us.expBarPercentTextOffsetY or 0;

    -- Gil Tracker
    gAdjustedSettings.gilTrackerSettings.iconScale = ds.gilTrackerSettings.iconScale * us.gilTrackerScale;
    gAdjustedSettings.gilTrackerSettings.font_settings.font_height = math.max(us.gilTrackerFontSize, 8);
    gAdjustedSettings.gilTrackerSettings.font_settings.font_alignment = us.gilTrackerRightAlign and gdi.Alignment.Right or gdi.Alignment.Left;
    gAdjustedSettings.gilTrackerSettings.rightAlign = us.gilTrackerRightAlign;
    gAdjustedSettings.gilTrackerSettings.iconRight = us.gilTrackerIconRight;
    gAdjustedSettings.gilTrackerSettings.showIcon = us.gilTrackerShowIcon;

    -- Inventory Tracker
    gAdjustedSettings.inventoryTrackerSettings.dotRadius = ds.inventoryTrackerSettings.dotRadius * us.inventoryTrackerScale;
    gAdjustedSettings.inventoryTrackerSettings.dotSpacing = ds.inventoryTrackerSettings.dotSpacing * us.inventoryTrackerScale;
    gAdjustedSettings.inventoryTrackerSettings.groupSpacing = ds.inventoryTrackerSettings.groupSpacing * us.inventoryTrackerScale;
    gAdjustedSettings.inventoryTrackerSettings.font_settings.font_height = math.max(us.inventoryTrackerFontSize, 8);
    gAdjustedSettings.inventoryTrackerSettings.columnCount = us.inventoryTrackerColumnCount;
    gAdjustedSettings.inventoryTrackerSettings.rowCount = us.inventoryTrackerRowCount;
    gAdjustedSettings.inventoryTrackerSettings.showText = us.inventoryShowCount;
    gAdjustedSettings.inventoryTrackerSettings.showDots = us.inventoryShowDots;
    gAdjustedSettings.inventoryTrackerSettings.showLabels = us.inventoryShowLabels;
    gAdjustedSettings.inventoryTrackerSettings.textUseThresholdColor = us.inventoryTextUseThresholdColor;

    -- Satchel Tracker
    gAdjustedSettings.satchelTrackerSettings.dotRadius = ds.satchelTrackerSettings.dotRadius * us.satchelTrackerScale;
    gAdjustedSettings.satchelTrackerSettings.dotSpacing = ds.satchelTrackerSettings.dotSpacing * us.satchelTrackerScale;
    gAdjustedSettings.satchelTrackerSettings.groupSpacing = ds.satchelTrackerSettings.groupSpacing * us.satchelTrackerScale;
    gAdjustedSettings.satchelTrackerSettings.font_settings.font_height = math.max(us.satchelTrackerFontSize, 8);
    gAdjustedSettings.satchelTrackerSettings.columnCount = us.satchelTrackerColumnCount;
    gAdjustedSettings.satchelTrackerSettings.rowCount = us.satchelTrackerRowCount;
    gAdjustedSettings.satchelTrackerSettings.showText = us.satchelShowCount;
    gAdjustedSettings.satchelTrackerSettings.showDots = us.satchelShowDots;
    gAdjustedSettings.satchelTrackerSettings.showLabels = us.satchelShowLabels;
    gAdjustedSettings.satchelTrackerSettings.textUseThresholdColor = us.satchelTextUseThresholdColor;

    -- Locker Tracker
    gAdjustedSettings.lockerTrackerSettings.dotRadius = ds.lockerTrackerSettings.dotRadius * us.lockerTrackerScale;
    gAdjustedSettings.lockerTrackerSettings.dotSpacing = ds.lockerTrackerSettings.dotSpacing * us.lockerTrackerScale;
    gAdjustedSettings.lockerTrackerSettings.groupSpacing = ds.lockerTrackerSettings.groupSpacing * us.lockerTrackerScale;
    gAdjustedSettings.lockerTrackerSettings.font_settings.font_height = math.max(us.lockerTrackerFontSize, 8);
    gAdjustedSettings.lockerTrackerSettings.columnCount = us.lockerTrackerColumnCount;
    gAdjustedSettings.lockerTrackerSettings.rowCount = us.lockerTrackerRowCount;
    gAdjustedSettings.lockerTrackerSettings.showText = us.lockerShowCount;
    gAdjustedSettings.lockerTrackerSettings.showDots = us.lockerShowDots;
    gAdjustedSettings.lockerTrackerSettings.showLabels = us.lockerShowLabels;
    gAdjustedSettings.lockerTrackerSettings.textUseThresholdColor = us.lockerTextUseThresholdColor;

    -- Safe Tracker
    gAdjustedSettings.safeTrackerSettings.dotRadius = ds.safeTrackerSettings.dotRadius * us.safeTrackerScale;
    gAdjustedSettings.safeTrackerSettings.dotSpacing = ds.safeTrackerSettings.dotSpacing * us.safeTrackerScale;
    gAdjustedSettings.safeTrackerSettings.groupSpacing = ds.safeTrackerSettings.groupSpacing * us.safeTrackerScale;
    gAdjustedSettings.safeTrackerSettings.font_settings.font_height = math.max(us.safeTrackerFontSize, 8);
    gAdjustedSettings.safeTrackerSettings.columnCount = us.safeTrackerColumnCount;
    gAdjustedSettings.safeTrackerSettings.rowCount = us.safeTrackerRowCount;
    gAdjustedSettings.safeTrackerSettings.showText = us.safeShowCount;
    gAdjustedSettings.safeTrackerSettings.showDots = us.safeShowDots;
    gAdjustedSettings.safeTrackerSettings.showPerContainer = us.safeShowPerContainer;
    gAdjustedSettings.safeTrackerSettings.showLabels = us.safeShowLabels;
    gAdjustedSettings.safeTrackerSettings.textUseThresholdColor = us.safeTextUseThresholdColor;

    -- Storage Tracker
    gAdjustedSettings.storageTrackerSettings.dotRadius = ds.storageTrackerSettings.dotRadius * us.storageTrackerScale;
    gAdjustedSettings.storageTrackerSettings.dotSpacing = ds.storageTrackerSettings.dotSpacing * us.storageTrackerScale;
    gAdjustedSettings.storageTrackerSettings.groupSpacing = ds.storageTrackerSettings.groupSpacing * us.storageTrackerScale;
    gAdjustedSettings.storageTrackerSettings.font_settings.font_height = math.max(us.storageTrackerFontSize, 8);
    gAdjustedSettings.storageTrackerSettings.columnCount = us.storageTrackerColumnCount;
    gAdjustedSettings.storageTrackerSettings.rowCount = us.storageTrackerRowCount;
    gAdjustedSettings.storageTrackerSettings.showText = us.storageShowCount;
    gAdjustedSettings.storageTrackerSettings.showDots = us.storageShowDots;
    gAdjustedSettings.storageTrackerSettings.showLabels = us.storageShowLabels;
    gAdjustedSettings.storageTrackerSettings.textUseThresholdColor = us.storageTextUseThresholdColor;

    -- Wardrobe Tracker
    gAdjustedSettings.wardrobeTrackerSettings.dotRadius = ds.wardrobeTrackerSettings.dotRadius * us.wardrobeTrackerScale;
    gAdjustedSettings.wardrobeTrackerSettings.dotSpacing = ds.wardrobeTrackerSettings.dotSpacing * us.wardrobeTrackerScale;
    gAdjustedSettings.wardrobeTrackerSettings.groupSpacing = ds.wardrobeTrackerSettings.groupSpacing * us.wardrobeTrackerScale;
    gAdjustedSettings.wardrobeTrackerSettings.font_settings.font_height = math.max(us.wardrobeTrackerFontSize, 8);
    gAdjustedSettings.wardrobeTrackerSettings.columnCount = us.wardrobeTrackerColumnCount;
    gAdjustedSettings.wardrobeTrackerSettings.rowCount = us.wardrobeTrackerRowCount;
    gAdjustedSettings.wardrobeTrackerSettings.showText = us.wardrobeShowCount;
    gAdjustedSettings.wardrobeTrackerSettings.showDots = us.wardrobeShowDots;
    gAdjustedSettings.wardrobeTrackerSettings.showPerContainer = us.wardrobeShowPerContainer;
    gAdjustedSettings.wardrobeTrackerSettings.showLabels = us.wardrobeShowLabels;
    gAdjustedSettings.wardrobeTrackerSettings.textUseThresholdColor = us.wardrobeTextUseThresholdColor;

    -- Enemy List
    gAdjustedSettings.enemyListSettings.barWidth = ds.enemyListSettings.barWidth * us.enemyListScaleX;
    gAdjustedSettings.enemyListSettings.barHeight = ds.enemyListSettings.barHeight * us.enemyListScaleY;
    gAdjustedSettings.enemyListSettings.iconSize = ds.enemyListSettings.iconSize * us.enemyListIconScale;
    gAdjustedSettings.enemyListSettings.debuffOffsetX = us.enemyListDebuffOffsetX;
    gAdjustedSettings.enemyListSettings.debuffOffsetY = us.enemyListDebuffOffsetY;
    gAdjustedSettings.enemyListSettings.name_font_settings.font_height = math.max(us.enemyListNameFontSize, 8);
    gAdjustedSettings.enemyListSettings.distance_font_settings.font_height = math.max(us.enemyListDistanceFontSize, 8);
    gAdjustedSettings.enemyListSettings.percent_font_settings.font_height = math.max(us.enemyListPercentFontSize, 8);
    gAdjustedSettings.enemyListSettings.target_font_settings.font_height = math.max(us.enemyListTargetFontSize or 12, 8);

    -- Cast Bar
    gAdjustedSettings.castBarSettings.barWidth = ds.castBarSettings.barWidth * us.castBarScaleX;
    gAdjustedSettings.castBarSettings.barHeight = ds.castBarSettings.barHeight * us.castBarScaleY;
    gAdjustedSettings.castBarSettings.spell_font_settings.font_height = math.max(us.castBarFontSize, 8);
    gAdjustedSettings.castBarSettings.percent_font_settings.font_height = math.max(us.castBarFontSize, 8);

    -- Cast Cost (uses nested gConfig.castCost structure)
    local cc = us.castCost or ds.castCost;
    gAdjustedSettings.castCostSettings.bgScale = cc.bgScale or 1.0;
    gAdjustedSettings.castCostSettings.borderScale = cc.borderScale or 1.0;
    gAdjustedSettings.castCostSettings.backgroundTheme = cc.backgroundTheme or 'Window1';
    gAdjustedSettings.castCostSettings.backgroundOpacity = cc.backgroundOpacity or 1.0;
    gAdjustedSettings.castCostSettings.borderOpacity = cc.borderOpacity or 1.0;
    gAdjustedSettings.castCostSettings.showName = cc.showName;
    gAdjustedSettings.castCostSettings.showMpCost = cc.showMpCost;
    gAdjustedSettings.castCostSettings.showRecast = cc.showRecast;
    gAdjustedSettings.castCostSettings.name_font_settings.font_height = math.max(cc.nameFontSize or 12, 8);
    gAdjustedSettings.castCostSettings.cost_font_settings.font_height = math.max(cc.costFontSize or 12, 8);
    gAdjustedSettings.castCostSettings.time_font_settings.font_height = math.max(cc.timeFontSize or 10, 8);
    gAdjustedSettings.castCostSettings.minWidth = cc.minWidth or 100;
    gAdjustedSettings.castCostSettings.bgPadding = cc.padding or 8;
    gAdjustedSettings.castCostSettings.bgPaddingY = cc.paddingY or 8;
    gAdjustedSettings.castCostSettings.alignBottom = cc.alignBottom or false;
    gAdjustedSettings.castCostSettings.showCooldown = cc.showCooldown;
    if gAdjustedSettings.castCostSettings.showCooldown == nil then
        gAdjustedSettings.castCostSettings.showCooldown = true;
    end
    gAdjustedSettings.castCostSettings.barScaleY = cc.barScaleY or 1.0;
    gAdjustedSettings.castCostSettings.recast_font_settings.font_height = math.max(cc.recastFontSize or 10, 8);
    gAdjustedSettings.castCostSettings.cooldown_font_settings.font_height = math.max(cc.recastFontSize or 10, 8);

    -- Mob Info
    gAdjustedSettings.mobInfoSettings.level_font_settings.font_height = math.max(us.mobInfoFontSize, 8);

    -- Pet Bar (base dimensions from legacy flat settings)
    gAdjustedSettings.petBarSettings.barWidth = ds.petBarSettings.barWidth * us.petBarScaleX;
    gAdjustedSettings.petBarSettings.barHeight = ds.petBarSettings.barHeight * us.petBarScaleY;
    gAdjustedSettings.petBarSettings.barSpacing = ds.petBarSettings.barSpacing * us.petBarScaleY;
    gAdjustedSettings.petBarSettings.name_font_settings.font_height = math.max(us.petBarNameFontSize, 8);
    gAdjustedSettings.petBarSettings.distance_font_settings.font_height = math.max(us.petBarDistanceFontSize, 8);
    gAdjustedSettings.petBarSettings.vitals_font_settings.font_height = math.max(us.petBarVitalsFontSize, 8);
    gAdjustedSettings.petBarSettings.timer_font_settings.font_height = math.max(us.petBarTimerFontSize, 8);

    -- Per-pet-type settings (display module uses these based on active pet)
    gAdjustedSettings.petBarSettings.petTypeSettings = {
        avatar = us.petBarAvatar,
        charm = us.petBarCharm,
        jug = us.petBarJug,
        automaton = us.petBarAutomaton,
        wyvern = us.petBarWyvern,
    };

    -- Per-pet-type color settings
    gAdjustedSettings.petBarSettings.petTypeColors = {
        avatar = us.colorCustomization and us.colorCustomization.petBarAvatar,
        charm = us.colorCustomization and us.colorCustomization.petBarCharm,
        jug = us.colorCustomization and us.colorCustomization.petBarJug,
        automaton = us.colorCustomization and us.colorCustomization.petBarAutomaton,
        wyvern = us.colorCustomization and us.colorCustomization.petBarWyvern,
    };
end

return M;
