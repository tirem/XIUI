--[[
* XIUI Settings Migration
* Handles migration from older settings formats and HXUI
]]--

local M = {};

-- Migrate settings from HXUI to XIUI (one-time migration for users upgrading from HXUI)
-- IMPORTANT: This must be called BEFORE settings.load() so that copied files are picked up
-- Returns: { count = number } or nil if no migration occurred
function M.MigrateFromHXUI()
    local installPath = AshitaCore:GetInstallPath():gsub('\\$', ''); -- Remove trailing backslash if present
    local oldConfigDir = installPath .. '\\config\\addons\\HXUI';
    local newConfigDir = installPath .. '\\config\\addons\\XIUI';

    -- Check if old config directory exists
    if not ashita.fs.exists(oldConfigDir) then
        return nil;
    end

    -- Get all character folders in the old config directory
    local characterFolders = ashita.fs.get_directory(oldConfigDir);
    if characterFolders == nil then
        return nil;
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
                local success, content = pcall(function() return oldFile:read('*all'); end);
                oldFile:close();

                if success and content then
                    -- Write to new settings file
                    local newFile = io.open(newSettingsPath, 'wb');
                    if newFile then
                        local writeSuccess, writeError = pcall(function()
                            newFile:write(content);
                        end);
                        newFile:close();

                        if writeSuccess then
                            migratedCount = migratedCount + 1;
                        else
                            print(string.format('[XIUI] Warning: Failed to write settings migration to %s: %s', newSettingsPath, tostring(writeError)));
                        end
                    else
                        print(string.format('[XIUI] Warning: Failed to open settings file for writing: %s', newSettingsPath));
                    end
                else
                    print(string.format('[XIUI] Warning: Failed to read settings from %s', oldSettingsPath));
                end
            else
                print(string.format('[XIUI] Warning: Failed to open settings file for reading: %s', oldSettingsPath));
            end
        end
    end

    if migratedCount > 0 then
        return { count = migratedCount };
    end
    return nil;
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
        selectionBoxOffsetY = 0,
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
        selectionBoxOffsetY = 0,
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
        selectionBoxOffsetY = 0,
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

    -- Migrate old unified expBar barGradient to separate expBarGradient and meritBarGradient
    if gConfig.colorCustomization.expBar then
        if gConfig.colorCustomization.expBar.barGradient and not gConfig.colorCustomization.expBar.expBarGradient then
            -- Migrate old barGradient to expBarGradient
            gConfig.colorCustomization.expBar.expBarGradient = deep_copy_table(gConfig.colorCustomization.expBar.barGradient);
            gConfig.colorCustomization.expBar.barGradient = nil;
        end
        -- Initialize meritBarGradient if missing
        if not gConfig.colorCustomization.expBar.meritBarGradient then
            gConfig.colorCustomization.expBar.meritBarGradient = deep_copy_table(defaults.colorCustomization.expBar.meritBarGradient);
        end
        -- Initialize expBarGradient if missing (fresh installs)
        if not gConfig.colorCustomization.expBar.expBarGradient then
            gConfig.colorCustomization.expBar.expBarGradient = deep_copy_table(defaults.colorCustomization.expBar.expBarGradient);
        end
    end
end

-- Migrate to new per-pet-type settings structure (petBarAvatar, petBarCharm, etc.)
-- Copies current flat settings to all pet types for existing users
function M.MigratePerPetTypeSettings(gConfig, defaults)
    -- Skip if already migrated (check for petBarAvatar with actual properties)
    -- Also validate it's actually a table (not corrupted)
    if gConfig.petBarAvatar and type(gConfig.petBarAvatar) == 'table' and gConfig.petBarAvatar.hpScaleX ~= nil then
        return;
    end

    -- Helper to safely get old flat value or default
    local function getOld(key, defaultValue)
        if gConfig[key] ~= nil then return gConfig[key]; end
        return defaultValue;
    end

    -- Create base settings from current flat values
    local baseSettings = T{
        -- Display toggles (migrate from old global settings)
        showLevel = getOld('petBarShowLevel', true),
        showDistance = getOld('petBarShowDistance', true),
        showHP = getOld('petBarShowVitals', true),
        showMP = getOld('petBarShowVitals', true),
        showTP = getOld('petBarShowVitals', true),
        showTimers = getOld('petBarShowTimers', true),
        -- Scale settings
        scaleX = getOld('petBarScaleX', 1.0),
        scaleY = getOld('petBarScaleY', 1.0),
        hpScaleX = getOld('petBarHpScaleX', 1.0),
        hpScaleY = getOld('petBarHpScaleY', 1.0),
        mpScaleX = getOld('petBarMpScaleX', 1.0),
        mpScaleY = getOld('petBarMpScaleY', 1.0),
        tpScaleX = getOld('petBarTpScaleX', 1.0),
        tpScaleY = getOld('petBarTpScaleY', 1.0),
        nameFontSize = getOld('petBarNameFontSize', 12),
        distanceFontSize = getOld('petBarDistanceFontSize', 10),
        hpFontSize = getOld('petBarVitalsFontSize', 10),
        mpFontSize = getOld('petBarVitalsFontSize', 10),
        tpFontSize = getOld('petBarVitalsFontSize', 10),
        backgroundTheme = getOld('petBarBackgroundTheme', 'Window1'),
        backgroundOpacity = getOld('petBarBackgroundOpacity', 1.0),
        borderOpacity = 1.0,
        showBookends = getOld('petBarShowBookends', false),
        iconsAbsolute = getOld('petBarIconsAbsolute', true),
        iconsScale = getOld('petBarIconsScale', 0.6),
        iconsOffsetX = getOld('petBarIconsOffsetX', 128),
        iconsOffsetY = getOld('petBarIconsOffsetY', 78),
        distanceAbsolute = getOld('petBarDistanceAbsolute', true),
        distanceOffsetX = getOld('petBarDistanceOffsetX', 11),
        distanceOffsetY = getOld('petBarDistanceOffsetY', 79),
    };

    -- Copy base settings to all pet types
    gConfig.petBarAvatar = deep_copy_table(baseSettings);
    gConfig.petBarCharm = deep_copy_table(baseSettings);
    gConfig.petBarJug = deep_copy_table(baseSettings);
    gConfig.petBarAutomaton = deep_copy_table(baseSettings);
    gConfig.petBarWyvern = deep_copy_table(baseSettings);

    -- Apply pet-type-specific overrides
    gConfig.petBarCharm.iconsOffsetX = 94;
    gConfig.petBarJug.iconsOffsetX = 94;
    gConfig.petBarAutomaton.iconsOffsetX = 60;
    gConfig.petBarWyvern.iconsOffsetX = 94;
end

-- Migrate old petBar colors to per-pet-type color settings
function M.MigratePerPetTypeColorSettings(gConfig, defaults)
    if not gConfig.colorCustomization then
        return;
    end

    -- Skip if already migrated (check for actual properties)
    -- Also validate it's actually a table (not corrupted)
    if gConfig.colorCustomization.petBarAvatar and type(gConfig.colorCustomization.petBarAvatar) == 'table' and gConfig.colorCustomization.petBarAvatar.hpGradient then
        return;
    end

    -- Copy existing petBar colors to all pet types
    if gConfig.colorCustomization.petBar then
        gConfig.colorCustomization.petBarAvatar = deep_copy_table(gConfig.colorCustomization.petBar);
        gConfig.colorCustomization.petBarCharm = deep_copy_table(gConfig.colorCustomization.petBar);
        gConfig.colorCustomization.petBarJug = deep_copy_table(gConfig.colorCustomization.petBar);
        gConfig.colorCustomization.petBarAutomaton = deep_copy_table(gConfig.colorCustomization.petBar);
        gConfig.colorCustomization.petBarWyvern = deep_copy_table(gConfig.colorCustomization.petBar);
    else
        -- Use defaults if petBar colors don't exist
        gConfig.colorCustomization.petBarAvatar = deep_copy_table(defaults.colorCustomization.petBarAvatar);
        gConfig.colorCustomization.petBarCharm = deep_copy_table(defaults.colorCustomization.petBarCharm);
        gConfig.colorCustomization.petBarJug = deep_copy_table(defaults.colorCustomization.petBarJug);
        gConfig.colorCustomization.petBarAutomaton = deep_copy_table(defaults.colorCustomization.petBarAutomaton);
        gConfig.colorCustomization.petBarWyvern = deep_copy_table(defaults.colorCustomization.petBarWyvern);
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

    -- Add mobInfo color settings if missing
    if gConfig.colorCustomization and not gConfig.colorCustomization.mobInfo then
        gConfig.colorCustomization.mobInfo = deep_copy_table(defaults.colorCustomization.mobInfo);
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

    -- Migrate old enemyListDebuffsRightAlign boolean to enemyListDebuffsAnchor string
    if gConfig.enemyListDebuffsRightAlign ~= nil then
        -- Convert old boolean to new anchor string
        -- Old true meant "right-aligned" (icons on right), old false meant "left-aligned" (icons on left)
        -- New anchor is which side of the entry to position debuffs
        gConfig.enemyListDebuffsAnchor = gConfig.enemyListDebuffsRightAlign and 'right' or 'left';
        gConfig.enemyListDebuffsRightAlign = nil;
    end
    if gConfig.enemyListDebuffsAnchor == nil then
        gConfig.enemyListDebuffsAnchor = defaults.enemyListDebuffsAnchor;
    end

    -- Migrate new mob info settings (add missing fields for existing users)
    if gConfig.mobInfoShowJob == nil then
        gConfig.mobInfoShowJob = defaults.mobInfoShowJob;
    end
    if gConfig.mobInfoShowModifierText == nil then
        gConfig.mobInfoShowModifierText = defaults.mobInfoShowModifierText;
    end
    if gConfig.mobInfoShowServerId == nil then
        gConfig.mobInfoShowServerId = defaults.mobInfoShowServerId;
    end
    if gConfig.mobInfoServerIdHex == nil then
        gConfig.mobInfoServerIdHex = defaults.mobInfoServerIdHex;
    end
    if gConfig.mobInfoSingleRow == nil then
        gConfig.mobInfoSingleRow = defaults.mobInfoSingleRow;
    end
    if gConfig.mobInfoSeparatorStyle == nil then
        gConfig.mobInfoSeparatorStyle = defaults.mobInfoSeparatorStyle;
    end
    if gConfig.mobInfoGroupModifiers == nil then
        gConfig.mobInfoGroupModifiers = defaults.mobInfoGroupModifiers;
    end

    -- Migrate party text position offsets (add to all parties if missing)
    local partyTables = { gConfig.partyA, gConfig.partyB, gConfig.partyC };
    local partyDefaults = { defaults.partyA, defaults.partyB, defaults.partyC };
    for i, party in ipairs(partyTables) do
        if party then
            local partyDefault = partyDefaults[i];
            if party.nameTextOffsetX == nil then party.nameTextOffsetX = partyDefault.nameTextOffsetX or 0; end
            if party.nameTextOffsetY == nil then party.nameTextOffsetY = partyDefault.nameTextOffsetY or 0; end
            if party.hpTextOffsetX == nil then party.hpTextOffsetX = partyDefault.hpTextOffsetX or 0; end
            if party.hpTextOffsetY == nil then party.hpTextOffsetY = partyDefault.hpTextOffsetY or 0; end
            if party.mpTextOffsetX == nil then party.mpTextOffsetX = partyDefault.mpTextOffsetX or 0; end
            if party.mpTextOffsetY == nil then party.mpTextOffsetY = partyDefault.mpTextOffsetY or 0; end
            if party.tpTextOffsetX == nil then party.tpTextOffsetX = partyDefault.tpTextOffsetX or 0; end
            if party.tpTextOffsetY == nil then party.tpTextOffsetY = partyDefault.tpTextOffsetY or 0; end
            if party.distanceTextOffsetX == nil then party.distanceTextOffsetX = partyDefault.distanceTextOffsetX or 0; end
            if party.distanceTextOffsetY == nil then party.distanceTextOffsetY = partyDefault.distanceTextOffsetY or 0; end
            if party.jobTextOffsetX == nil then party.jobTextOffsetX = partyDefault.jobTextOffsetX or 0; end
            if party.jobTextOffsetY == nil then party.jobTextOffsetY = partyDefault.jobTextOffsetY or 0; end
        end
    end

    -- Migrate new per-pet-type display toggles (add missing fields to existing per-pet-type settings)
    local petTypeTables = { gConfig.petBarAvatar, gConfig.petBarCharm, gConfig.petBarJug, gConfig.petBarAutomaton, gConfig.petBarWyvern };
    local petTypeDefaults = { defaults.petBarAvatar, defaults.petBarCharm, defaults.petBarJug, defaults.petBarAutomaton, defaults.petBarWyvern };
    for i, petType in ipairs(petTypeTables) do
        if petType and type(petType) == 'table' then
            local petDefault = petTypeDefaults[i];
            -- Display toggles
            if petType.showLevel == nil then petType.showLevel = gConfig.petBarShowLevel or false; end
            if petType.showDistance == nil then petType.showDistance = gConfig.petBarShowDistance or true; end
            if petType.showHP == nil then petType.showHP = gConfig.petBarShowVitals or true; end
            if petType.showMP == nil then petType.showMP = gConfig.petBarShowVitals or true; end
            if petType.showTP == nil then petType.showTP = gConfig.petBarShowVitals or true; end
            if petType.showTimers == nil then petType.showTimers = gConfig.petBarShowTimers or true; end
            -- Individual font sizes (migrate from old vitalsFontSize)
            local oldVitalsFontSize = petType.vitalsFontSize or gConfig.petBarVitalsFontSize or 10;
            if petType.hpFontSize == nil then petType.hpFontSize = oldVitalsFontSize; end
            if petType.mpFontSize == nil then petType.mpFontSize = oldVitalsFontSize; end
            if petType.tpFontSize == nil then petType.tpFontSize = oldVitalsFontSize; end
        end
    end
end

-- Migrate flat castCost* settings to nested castCost table
function M.MigrateCastCostSettings(gConfig, defaults)
    -- Check if migration is needed (old flat settings exist, new nested doesn't)
    if gConfig.castCostScaleX ~= nil and gConfig.castCost == nil then
        -- Create nested structure from old flat settings
        gConfig.castCost = T{
            -- Display options
            showName = gConfig.castCostShowName,
            showMpCost = gConfig.castCostShowMpCost,
            showRecast = gConfig.castCostShowRecast,
            showCooldown = gConfig.castCostShowCooldown,

            -- Font sizes
            nameFontSize = gConfig.castCostNameFontSize or 12,
            costFontSize = gConfig.castCostCostFontSize or 12,
            timeFontSize = gConfig.castCostTimeFontSize or 10,
            recastFontSize = gConfig.castCostRecastFontSize or 10,

            -- Layout
            minWidth = gConfig.castCostMinWidth or 100,
            padding = gConfig.castCostPadding or 8,
            paddingY = gConfig.castCostPaddingY or 8,
            alignBottom = gConfig.castCostAlignBottom or false,
            barScaleY = gConfig.castCostBarScaleY or 1.0,

            -- Background/Border
            backgroundTheme = gConfig.castCostBackgroundTheme or 'Window1',
            bgScale = gConfig.castCostScaleX or 1.0,
            borderScale = gConfig.castCostBorderScale or 1.0,
            backgroundOpacity = gConfig.castCostBackgroundOpacity or 1.0,
            borderOpacity = gConfig.castCostBorderOpacity or 1.0,
        };

        -- Clean up old flat settings
        gConfig.castCostScaleX = nil;
        gConfig.castCostScaleY = nil;
        gConfig.castCostBorderScale = nil;
        gConfig.castCostBackgroundTheme = nil;
        gConfig.castCostBackgroundOpacity = nil;
        gConfig.castCostBorderOpacity = nil;
        gConfig.castCostShowName = nil;
        gConfig.castCostShowMpCost = nil;
        gConfig.castCostShowRecast = nil;
        gConfig.castCostNameFontSize = nil;
        gConfig.castCostCostFontSize = nil;
        gConfig.castCostTimeFontSize = nil;
        gConfig.castCostMinWidth = nil;
        gConfig.castCostPadding = nil;
        gConfig.castCostPaddingY = nil;
        gConfig.castCostAlignBottom = nil;
        gConfig.castCostShowCooldown = nil;
        gConfig.castCostBarScaleY = nil;
        gConfig.castCostRecastFontSize = nil;
    end

    -- Ensure castCost table exists with defaults
    if gConfig.castCost == nil then
        gConfig.castCost = defaults.castCost;
    end

    -- Fill in any missing fields with defaults
    if gConfig.castCost then
        local d = defaults.castCost;
        if gConfig.castCost.showName == nil then gConfig.castCost.showName = d.showName; end
        if gConfig.castCost.showMpCost == nil then gConfig.castCost.showMpCost = d.showMpCost; end
        if gConfig.castCost.showRecast == nil then gConfig.castCost.showRecast = d.showRecast; end
        if gConfig.castCost.showCooldown == nil then gConfig.castCost.showCooldown = d.showCooldown; end
        if gConfig.castCost.nameFontSize == nil then gConfig.castCost.nameFontSize = d.nameFontSize; end
        if gConfig.castCost.costFontSize == nil then gConfig.castCost.costFontSize = d.costFontSize; end
        if gConfig.castCost.timeFontSize == nil then gConfig.castCost.timeFontSize = d.timeFontSize; end
        if gConfig.castCost.recastFontSize == nil then gConfig.castCost.recastFontSize = d.recastFontSize; end
        if gConfig.castCost.minWidth == nil then gConfig.castCost.minWidth = d.minWidth; end
        if gConfig.castCost.padding == nil then gConfig.castCost.padding = d.padding; end
        if gConfig.castCost.paddingY == nil then gConfig.castCost.paddingY = d.paddingY; end
        if gConfig.castCost.alignBottom == nil then gConfig.castCost.alignBottom = d.alignBottom; end
        if gConfig.castCost.barScaleY == nil then gConfig.castCost.barScaleY = d.barScaleY; end
        if gConfig.castCost.backgroundTheme == nil then gConfig.castCost.backgroundTheme = d.backgroundTheme; end
        if gConfig.castCost.bgScale == nil then gConfig.castCost.bgScale = d.bgScale; end
        if gConfig.castCost.borderScale == nil then gConfig.castCost.borderScale = d.borderScale; end
        if gConfig.castCost.backgroundOpacity == nil then gConfig.castCost.backgroundOpacity = d.backgroundOpacity; end
        if gConfig.castCost.borderOpacity == nil then gConfig.castCost.borderOpacity = d.borderOpacity; end
    end
end

-- Migrate gil tracker settings (add missing fields for existing users)
function M.MigrateGilTrackerSettings(gConfig, defaults)
    -- Gil tracker display settings
    if gConfig.gilTrackerShowGilPerHour == nil then
        gConfig.gilTrackerShowGilPerHour = defaults.gilTrackerShowGilPerHour;
    end

    -- Gil tracker offset settings
    if gConfig.gilTrackerTextOffsetX == nil then
        gConfig.gilTrackerTextOffsetX = defaults.gilTrackerTextOffsetX or 0;
    end
    if gConfig.gilTrackerTextOffsetY == nil then
        gConfig.gilTrackerTextOffsetY = defaults.gilTrackerTextOffsetY or 0;
    end
    if gConfig.gilTrackerGilPerHourOffsetX == nil then
        gConfig.gilTrackerGilPerHourOffsetX = defaults.gilTrackerGilPerHourOffsetX or 0;
    end
    if gConfig.gilTrackerGilPerHourOffsetY == nil then
        gConfig.gilTrackerGilPerHourOffsetY = defaults.gilTrackerGilPerHourOffsetY or 0;
    end

    -- Gil tracker color settings
    if gConfig.colorCustomization and gConfig.colorCustomization.gilTracker then
        local gilColors = gConfig.colorCustomization.gilTracker;
        local defaultColors = defaults.colorCustomization.gilTracker;
        if gilColors.positiveColor == nil then
            gilColors.positiveColor = defaultColors.positiveColor;
        end
        if gilColors.negativeColor == nil then
            gilColors.negativeColor = defaultColors.negativeColor;
        end
    end
end

-- Run structure migrations (called AFTER settings.load())
-- These handle migrating old settings structures to new ones
function M.RunStructureMigrations(gConfig, defaults)
    M.MigratePartyListLayoutSettings(gConfig, defaults);
    M.MigratePerPartySettings(gConfig, defaults);
    M.MigratePerPetTypeSettings(gConfig, defaults);
    M.MigrateColorSettings(gConfig, defaults);
    M.MigratePerPetTypeColorSettings(gConfig, defaults);
    M.MigrateIndividualSettings(gConfig, defaults);
    M.MigrateGilTrackerSettings(gConfig, defaults);
    M.MigrateCastCostSettings(gConfig, defaults);
end

-- Legacy function for backward compatibility (if any external code calls it)
function M.RunAllMigrations(gConfig, defaults)
    -- NOTE: MigrateFromHXUI should be called separately BEFORE settings.load()
    -- This function now only runs structure migrations
    M.RunStructureMigrations(gConfig, defaults);
end

return M;
