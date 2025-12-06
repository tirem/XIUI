--[[
* XIUI Settings Migration
* Handles migration from older settings formats and HXUI
]]--

local M = {};

-- Migrate settings from HXUI to XIUI (one-time migration for users upgrading from HXUI)
function M.MigrateFromHXUI()
    local installPath = AshitaCore:GetInstallPath():gsub('\\$', ''); -- Remove trailing backslash if present
    local oldConfigDir = installPath .. '\\config\\addons\\HXUI';
    local newConfigDir = installPath .. '\\config\\addons\\XIUI';

    -- Check if old config directory exists
    if not ashita.fs.exists(oldConfigDir) then
        return;
    end

    -- Get all character folders in the old config directory
    local characterFolders = ashita.fs.get_directory(oldConfigDir);
    if characterFolders == nil then
        return;
    end

    local migratedCount = 0;

    for _, folderName in ipairs(characterFolders) do
        local oldSettingsPath = oldConfigDir .. '\\' .. folderName .. '\\settings.lua';
        local newSettingsDir = newConfigDir .. '\\' .. folderName;
        local newSettingsPath = newSettingsDir .. '\\settings.lua';

        -- Only migrate if old settings exist and new settings don't
        if ashita.fs.exists(oldSettingsPath) and not ashita.fs.exists(newSettingsPath) then
            -- Ensure the new directory exists
            ashita.fs.create_directory(newSettingsDir);

            -- Read old settings file
            local oldFile = io.open(oldSettingsPath, 'rb');
            if oldFile then
                local content = oldFile:read('*all');
                oldFile:close();

                -- Write to new settings file
                local newFile = io.open(newSettingsPath, 'wb');
                if newFile then
                    newFile:write(content);
                    newFile:close();
                    migratedCount = migratedCount + 1;
                end
            end
        end
    end

    if migratedCount > 0 then
        print('[XIUI] Successfully migrated settings for ' .. migratedCount .. ' character(s) from HXUI.');
    end
end

-- Migrate party list layout settings (convert old settings to layout-specific format)
function M.MigratePartyListLayoutSettings(gConfig, defaults)
    if not gConfig.partyListLayout1 then
        -- User has old settings format, migrate to Layout 1
        gConfig.partyListLayout1 = T{
            -- Migrate main party settings
            partyListScaleX = gConfig.partyListScaleX or 1,
            partyListScaleY = gConfig.partyListScaleY or 1,
            partyListFontSize = gConfig.partyListFontSize or 16,
            partyListJobIconScale = gConfig.partyListJobIconScale or 1,
            partyListEntrySpacing = gConfig.partyListEntrySpacing or 0,
            partyListTP = (gConfig.partyListTP ~= nil) and gConfig.partyListTP or true,
            partyListMinRows = gConfig.partyListMinRows or 1,

            -- Migrate alliance party 2 settings
            partyList2ScaleX = gConfig.partyList2ScaleX or 0.7,
            partyList2ScaleY = gConfig.partyList2ScaleY or 0.7,
            partyList2FontSize = gConfig.partyList2FontSize or 16,
            partyList2JobIconScale = gConfig.partyList2JobIconScale or 0.8,
            partyList2EntrySpacing = gConfig.partyList2EntrySpacing or 6,
            partyList2TP = (gConfig.partyList2TP ~= nil) and gConfig.partyList2TP or false,

            -- Migrate alliance party 3 settings
            partyList3ScaleX = gConfig.partyList3ScaleX or 0.7,
            partyList3ScaleY = gConfig.partyList3ScaleY or 0.7,
            partyList3FontSize = gConfig.partyList3FontSize or 16,
            partyList3JobIconScale = gConfig.partyList3JobIconScale or 0.8,
            partyList3EntrySpacing = gConfig.partyList3EntrySpacing or 6,
            partyList3TP = (gConfig.partyList3TP ~= nil) and gConfig.partyList3TP or false,

            -- Use default bar dimensions and text offsets from default_settings
            hpBarWidth = 150,
            mpBarWidth = 100,
            tpBarWidth = 100,
            barHeight = 20,
            barSpacing = 8,

            nameTextOffsetX = 1,
            nameTextOffsetY = 0,
            hpTextOffsetX = -2,
            hpTextOffsetY = -1,
            mpTextOffsetX = -2,
            mpTextOffsetY = -1,
            tpTextOffsetX = -2,
            tpTextOffsetY = -1,
        };

        -- Remove old party-specific settings from top level (they're now in partyListLayout1)
        gConfig.partyListScaleX = nil;
        gConfig.partyListScaleY = nil;
        gConfig.partyListFontSize = nil;
        gConfig.partyListJobIconScale = nil;
        gConfig.partyListEntrySpacing = nil;
        gConfig.partyListTP = nil;
        gConfig.partyListMinRows = nil;

        gConfig.partyList2ScaleX = nil;
        gConfig.partyList2ScaleY = nil;
        gConfig.partyList2FontSize = nil;
        gConfig.partyList2JobIconScale = nil;
        gConfig.partyList2EntrySpacing = nil;
        gConfig.partyList2TP = nil;

        gConfig.partyList3ScaleX = nil;
        gConfig.partyList3ScaleY = nil;
        gConfig.partyList3FontSize = nil;
        gConfig.partyList3JobIconScale = nil;
        gConfig.partyList3EntrySpacing = nil;
        gConfig.partyList3TP = nil;
    end

    -- Initialize Layout 2 if missing (use defaults from defaultUserSettings)
    if not gConfig.partyListLayout2 then
        gConfig.partyListLayout2 = deep_copy_table(defaults.partyListLayout2);
    end

    -- Ensure partyListLayout selector exists (default to Layout 1)
    if gConfig.partyListLayout == nil then
        gConfig.partyListLayout = 0;
    end
end

-- Migrate to new per-party settings structure (partyA, partyB, partyC)
function M.MigratePerPartySettings(gConfig, defaults)
    if gConfig.partyA then
        return; -- Already migrated
    end

    -- Migrate from old settings to new per-party structure
    local oldLayout = (gConfig.partyListLayout == 1) and gConfig.partyListLayout2 or gConfig.partyListLayout1;

    -- Helper to safely get old value or default
    local function getOld(key, default)
        if oldLayout and oldLayout[key] ~= nil then return oldLayout[key]; end
        if gConfig[key] ~= nil then return gConfig[key]; end
        return default;
    end

    gConfig.partyA = T{
        layout = gConfig.partyListLayout or 0,
        showDistance = gConfig.showPartyListDistance or false,
        distanceHighlight = gConfig.partyListDistanceHighlight or 0,
        showJobIcon = gConfig.showPartyJobIcon ~= false,
        showJob = gConfig.showPartyListJob ~= false,
        showCastBars = gConfig.partyListCastBars ~= false,
        castBarScaleY = gConfig.partyListCastBarScaleY or 0.6,
        showBookends = gConfig.showPartyListBookends ~= false,
        showTitle = gConfig.showPartyListTitle ~= false,
        flashTP = gConfig.partyListFlashTP or false,
        showTP = getOld('partyListTP', true),
        backgroundName = gConfig.partyListBackgroundName or 'Window1',
        bgScale = gConfig.partyListBgScale or 1.0,
        cursor = gConfig.partyListCursor or 'GreyArrow.png',
        subtargetArrowTint = 0xFFfdd017,
        targetArrowTint = 0xFFFFFFFF,
        statusTheme = gConfig.partyListStatusTheme or 0,
        buffScale = gConfig.partyListBuffScale or 1.0,
        expandHeight = gConfig.partyListExpandHeight or false,
        alignBottom = gConfig.partyListAlignBottom or false,
        minRows = getOld('partyListMinRows', 1),
        entrySpacing = getOld('partyListEntrySpacing', 0),
        selectionBoxScaleY = getOld('selectionBoxScaleY', 1),
        scaleX = getOld('partyListScaleX', 1),
        scaleY = getOld('partyListScaleY', 1),
        fontSize = getOld('partyListFontSize', 12),
        splitFontSizes = getOld('splitFontSizes', false),
        nameFontSize = getOld('partyListNameFontSize', 12),
        hpFontSize = getOld('partyListHpFontSize', 12),
        mpFontSize = getOld('partyListMpFontSize', 12),
        tpFontSize = getOld('partyListTpFontSize', 12),
        distanceFontSize = getOld('partyListDistanceFontSize', 12),
        jobFontSize = getOld('partyListJobFontSize', 12),
        jobIconScale = getOld('partyListJobIconScale', 1),
        hpBarScaleX = getOld('hpBarScaleX', 1),
        mpBarScaleX = getOld('mpBarScaleX', 1),
        tpBarScaleX = getOld('tpBarScaleX', 1),
        hpBarScaleY = getOld('hpBarScaleY', 1),
        mpBarScaleY = getOld('mpBarScaleY', 1),
        tpBarScaleY = getOld('tpBarScaleY', 1),
    };

    gConfig.partyB = T{
        layout = gConfig.partyListLayout or 0,
        showDistance = gConfig.showPartyListDistance or false,
        distanceHighlight = gConfig.partyListDistanceHighlight or 0,
        showJobIcon = gConfig.showPartyJobIcon ~= false,
        showJob = gConfig.showPartyListJob ~= false,
        showCastBars = gConfig.partyListCastBars ~= false,
        castBarScaleY = gConfig.partyListCastBarScaleY or 0.6,
        showBookends = gConfig.showPartyListBookends ~= false,
        showTitle = gConfig.showPartyListTitle ~= false,
        flashTP = gConfig.partyListFlashTP or false,
        showTP = getOld('partyList2TP', false),
        backgroundName = gConfig.partyListBackgroundName or 'Window1',
        bgScale = gConfig.partyListBgScale or 1.0,
        cursor = gConfig.partyListCursor or 'GreyArrow.png',
        subtargetArrowTint = 0xFFfdd017,
        targetArrowTint = 0xFFFFFFFF,
        statusTheme = gConfig.partyListStatusTheme or 0,
        buffScale = gConfig.partyListBuffScale or 1.0,
        expandHeight = gConfig.partyListExpandHeight or false,
        alignBottom = gConfig.partyListAlignBottom or false,
        minRows = 1,
        entrySpacing = getOld('partyList2EntrySpacing', 6),
        selectionBoxScaleY = 1,
        scaleX = getOld('partyList2ScaleX', 0.7),
        scaleY = getOld('partyList2ScaleY', 0.7),
        fontSize = getOld('partyList2FontSize', 12),
        splitFontSizes = getOld('splitFontSizes', false),
        nameFontSize = getOld('partyList2NameFontSize', 12),
        hpFontSize = getOld('partyList2HpFontSize', 12),
        mpFontSize = getOld('partyList2MpFontSize', 12),
        tpFontSize = getOld('partyList2TpFontSize', 12),
        distanceFontSize = getOld('partyList2DistanceFontSize', 12),
        jobFontSize = getOld('partyList2JobFontSize', 12),
        jobIconScale = getOld('partyList2JobIconScale', 0.8),
        hpBarScaleX = getOld('partyList2HpBarScaleX', 0.9),
        mpBarScaleX = getOld('partyList2MpBarScaleX', 0.6),
        tpBarScaleX = getOld('partyList2TpBarScaleX', 1),
        hpBarScaleY = getOld('partyList2HpBarScaleY', 1),
        mpBarScaleY = getOld('partyList2MpBarScaleY', 0.7),
        tpBarScaleY = getOld('partyList2TpBarScaleY', 1),
    };

    gConfig.partyC = T{
        layout = gConfig.partyListLayout or 0,
        showDistance = gConfig.showPartyListDistance or false,
        distanceHighlight = gConfig.partyListDistanceHighlight or 0,
        showJobIcon = gConfig.showPartyJobIcon ~= false,
        showJob = gConfig.showPartyListJob ~= false,
        showCastBars = gConfig.partyListCastBars ~= false,
        castBarScaleY = gConfig.partyListCastBarScaleY or 0.6,
        showBookends = gConfig.showPartyListBookends ~= false,
        showTitle = gConfig.showPartyListTitle ~= false,
        flashTP = gConfig.partyListFlashTP or false,
        showTP = getOld('partyList3TP', false),
        backgroundName = gConfig.partyListBackgroundName or 'Window1',
        bgScale = gConfig.partyListBgScale or 1.0,
        cursor = gConfig.partyListCursor or 'GreyArrow.png',
        subtargetArrowTint = 0xFFfdd017,
        targetArrowTint = 0xFFFFFFFF,
        statusTheme = gConfig.partyListStatusTheme or 0,
        buffScale = gConfig.partyListBuffScale or 1.0,
        expandHeight = gConfig.partyListExpandHeight or false,
        alignBottom = gConfig.partyListAlignBottom or false,
        minRows = 1,
        entrySpacing = getOld('partyList3EntrySpacing', 6),
        selectionBoxScaleY = 1,
        scaleX = getOld('partyList3ScaleX', 0.7),
        scaleY = getOld('partyList3ScaleY', 0.7),
        fontSize = getOld('partyList3FontSize', 12),
        splitFontSizes = getOld('splitFontSizes', false),
        nameFontSize = getOld('partyList3NameFontSize', 12),
        hpFontSize = getOld('partyList3HpFontSize', 12),
        mpFontSize = getOld('partyList3MpFontSize', 12),
        tpFontSize = getOld('partyList3TpFontSize', 12),
        distanceFontSize = getOld('partyList3DistanceFontSize', 12),
        jobFontSize = getOld('partyList3JobFontSize', 12),
        jobIconScale = getOld('partyList3JobIconScale', 0.8),
        hpBarScaleX = getOld('partyList3HpBarScaleX', 0.9),
        mpBarScaleX = getOld('partyList3MpBarScaleX', 0.6),
        tpBarScaleX = getOld('partyList3TpBarScaleX', 1),
        hpBarScaleY = getOld('partyList3HpBarScaleY', 1),
        mpBarScaleY = getOld('partyList3MpBarScaleY', 0.7),
        tpBarScaleY = getOld('partyList3TpBarScaleY', 1),
    };

    -- Initialize layout templates if missing
    if not gConfig.layoutHorizontal then
        gConfig.layoutHorizontal = deep_copy_table(defaults.layoutHorizontal);
    end
    if not gConfig.layoutCompact then
        gConfig.layoutCompact = deep_copy_table(defaults.layoutCompact);
    end
end

-- Migrate old partyList colors to per-party color settings (partyListA, partyListB, partyListC)
function M.MigrateColorSettings(gConfig, defaults)
    if not gConfig.colorCustomization then
        return;
    end

    -- Migrate old unified partyList colors to per-party
    if gConfig.colorCustomization.partyList and not gConfig.colorCustomization.partyListA then
        -- Copy old partyList colors to all three party color configs
        gConfig.colorCustomization.partyListA = deep_copy_table(gConfig.colorCustomization.partyList);
        gConfig.colorCustomization.partyListB = deep_copy_table(gConfig.colorCustomization.partyList);
        gConfig.colorCustomization.partyListC = deep_copy_table(gConfig.colorCustomization.partyList);

        -- Remove TP-related colors from Party B and C (alliance members don't have TP)
        gConfig.colorCustomization.partyListB.tpGradient = nil;
        gConfig.colorCustomization.partyListB.tpEmptyTextColor = nil;
        gConfig.colorCustomization.partyListB.tpFullTextColor = nil;
        gConfig.colorCustomization.partyListB.castBarGradient = nil;
        gConfig.colorCustomization.partyListC.tpGradient = nil;
        gConfig.colorCustomization.partyListC.tpEmptyTextColor = nil;
        gConfig.colorCustomization.partyListC.tpFullTextColor = nil;
        gConfig.colorCustomization.partyListC.castBarGradient = nil;

        -- Remove old partyList (now deprecated)
        gConfig.colorCustomization.partyList = nil;
    end

    -- Initialize per-party color settings if missing (for fresh installs after migration code)
    if not gConfig.colorCustomization.partyListA then
        gConfig.colorCustomization.partyListA = deep_copy_table(defaults.colorCustomization.partyListA);
    end
    if not gConfig.colorCustomization.partyListB then
        gConfig.colorCustomization.partyListB = deep_copy_table(defaults.colorCustomization.partyListB);
    end
    if not gConfig.colorCustomization.partyListC then
        gConfig.colorCustomization.partyListC = deep_copy_table(defaults.colorCustomization.partyListC);
    end
end

-- Migrate individual settings that may be missing for existing users
function M.MigrateIndividualSettings(gConfig, defaults)
    -- Add bookend gradient if missing
    if gConfig.colorCustomization and gConfig.colorCustomization.shared then
        if not gConfig.colorCustomization.shared.bookendGradient then
            gConfig.colorCustomization.shared.bookendGradient = deep_copy_table(defaults.colorCustomization.shared.bookendGradient);
        end
    end

    -- Migrate new target bar settings (add missing fields for existing users)
    if gConfig.showTargetHpPercent == nil then
        gConfig.showTargetHpPercent = true;
    end
    if gConfig.showTargetHpPercentAllTargets == nil then
        gConfig.showTargetHpPercentAllTargets = false;
    end
    if gConfig.showTargetName == nil then
        gConfig.showTargetName = true;
    end

    -- Remove deprecated setting
    if gConfig.alwaysShowHealthPercent ~= nil then
        gConfig.alwaysShowHealthPercent = nil;
    end
end

-- Run all migrations in the correct order
function M.RunAllMigrations(gConfig, defaults)
    -- Run HXUI migration first (file-level migration)
    pcall(M.MigrateFromHXUI);

    -- Run settings structure migrations
    M.MigratePartyListLayoutSettings(gConfig, defaults);
    M.MigratePerPartySettings(gConfig, defaults);
    M.MigrateColorSettings(gConfig, defaults);
    M.MigrateIndividualSettings(gConfig, defaults);
end

return M;
