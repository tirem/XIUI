--[[
* XIUI Settings Defaults
* Contains all default settings definitions for user settings and module defaults
]]--

local gdi = require('submodules.gdifonts.include');

local M = {};

-- Factory function to create party settings with overrides
-- Reduces duplication since partyA/B/C are 95% identical
local function createPartyDefaults(overrides)
    local defaults = T{
        -- Layout mode (0 = Horizontal, 1 = Compact Vertical)
        layout = 0,
        -- Display options
        showDistance = false,
        distanceHighlight = 0,
        -- HP/MP display modes ('number', 'percent', 'both', 'both_percent_first', 'current_max')
        hpDisplayMode = 'number',
        mpDisplayMode = 'number',
        -- Job display options
        showJobIcon = true,
        jobIconScale = 1,
        showJob = false,
        showMainJob = true,
        showMainJobLevel = true,
        showSubJob = true,
        showSubJobLevel = true,
        showCastBars = true,
        castBarStyle = 'name', -- 'name' = replace name, 'mp' = use MP bar, 'tp' = use TP bar
        alwaysShowMpBar = true, -- Show MP bar even for jobs without MP
        castBarScaleX = 1.0,
        castBarScaleY = 0.6,
        castBarOffsetX = 0,
        castBarOffsetY = 0,
        showBookends = false,
        showTitle = true,
        flashTP = false,
        showTP = true,
        -- Appearance
        backgroundName = 'Window1',
        bgScale = 1.0,
        cursor = 'GreyArrow.png',
        statusTheme = 0, -- 0: HorizonXI, 1: HorizonXI-R, 2: FFXIV, 3: FFXI, 4: Disabled
        statusSide = 0, -- 0: Left, 1: Right
        buffScale = 1.0,
        -- Positioning
        expandHeight = false,
        alignBottom = false,
        minRows = 1,
        entrySpacing = 0,
        selectionBoxScaleY = 1,
        -- Scale
        scaleX = 1,
        scaleY = 1,
        -- Font sizes
        fontSize = 12,
        splitFontSizes = false,
        nameFontSize = 12,
        hpFontSize = 12,
        mpFontSize = 12,
        tpFontSize = 12,
        distanceFontSize = 12,
        jobFontSize = 12,
        zoneFontSize = 10,
        -- Bar scales (for all layouts)
        hpBarScaleX = 1,
        mpBarScaleX = 1,
        tpBarScaleX = 1,
        hpBarScaleY = 1,
        mpBarScaleY = 1,
        tpBarScaleY = 1,
        -- Text position offsets (per-party overrides)
        nameTextOffsetX = 0,
        nameTextOffsetY = 0,
        hpTextOffsetX = 0,
        hpTextOffsetY = 0,
        mpTextOffsetX = 0,
        mpTextOffsetY = 0,
        tpTextOffsetX = 0,
        tpTextOffsetY = 0,
        distanceTextOffsetX = 0,
        distanceTextOffsetY = 0,
        jobTextOffsetX = 0,
        jobTextOffsetY = 0,
    };
    if overrides then
        for k, v in pairs(overrides) do
            defaults[k] = v;
        end
    end
    return defaults;
end

-- Factory function to create per-pet-type settings with overrides
-- Each pet type (Avatar, Charm, Jug, Automaton, Wyvern) can have independent visual settings
local function createPetBarTypeDefaults(overrides)
    local defaults = T{
        -- Display toggles
        showLevel = false,
        showDistance = true,
        showHP = true,
        showMP = true,
        showTP = true,
        showTimers = true,
        -- Positioning
        alignBottom = false,
        -- Scale settings
        scaleX = 1.0,
        scaleY = 1.0,
        hpScaleX = 1.0,
        hpScaleY = 1.0,
        mpScaleX = 1.0,
        mpScaleY = 1.0,
        tpScaleX = 1.0,
        tpScaleY = 1.0,
        recastScaleX = 1.0,
        recastScaleY = 0.8,
        -- Font sizes
        nameFontSize = 12,
        distanceFontSize = 10,
        hpFontSize = 10,
        mpFontSize = 10,
        tpFontSize = 10,
        -- Background settings
        backgroundTheme = 'Window1',
        backgroundOpacity = 1.0,
        borderOpacity = 1.0,
        showBookends = false,
        -- Recast icon positioning (absolute for compact mode, anchored for full mode)
        iconsAbsolute = false,
        iconsScale = 0.6,
        iconsOffsetX = 0,
        iconsOffsetY = 0,
        -- Recast icon fill style: 'square', 'circle', or 'clock'
        timerFillStyle = 'square',
        -- Recast display style: 'compact' or 'full'
        recastDisplayStyle = 'full',
        -- Full display style settings
        recastFullShowName = true,
        recastFullShowTimer = true,
        recastFullNameFontSize = 10,
        recastFullTimerFontSize = 10,
        recastFullAlignment = 'left',
        recastFullSpacing = 4,
        -- Spacing between vitals and recast section (anchored mode only)
        recastTopSpacing = 2,
        -- Distance text positioning
        distanceOffsetX = 0,
        distanceOffsetY = 0,
    };
    if overrides then
        for k, v in pairs(overrides) do
            defaults[k] = v;
        end
    end
    return defaults;
end

-- Factory function to create per-pet-type color settings
local function createPetBarTypeColorDefaults()
    return T{
        -- Bar gradients
        hpGradient = T{ enabled = true, start = '#e26c6c', stop = '#fa9c9c' },
        mpGradient = T{ enabled = true, start = '#9abb5a', stop = '#bfe07d' },
        tpGradient = T{ enabled = true, start = '#3898ce', stop = '#78c4ee' },
        -- Text colors
        nameTextColor = 0xFFFFFFFF,
        distanceTextColor = 0xFFFFFFFF,
        hpTextColor = 0xFFFFA7A7,
        mpTextColor = 0xFFD4FF97,
        tpTextColor = 0xFF8DC7FF,
        targetTextColor = 0xFFFFFFFF,
        -- SMN ability gradients
        timerBPRageReadyGradient = T{ enabled = true, start = '#ff3333e6', stop = '#ff6666e6' },
        timerBPRageRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerBPWardReadyGradient = T{ enabled = true, start = '#00cccce6', stop = '#66dddde6' },
        timerBPWardRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerApogeeReadyGradient = T{ enabled = true, start = '#ffcc00e6', stop = '#ffdd66e6' },
        timerApogeeRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerManaCedeReadyGradient = T{ enabled = true, start = '#009999e6', stop = '#66bbbbe6' },
        timerManaCedeRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        -- BST ability gradients
        timerReadyReadyGradient = T{ enabled = true, start = '#ff6600e6', stop = '#ff9933e6' },
        timerReadyRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerRewardReadyGradient = T{ enabled = true, start = '#00cc66e6', stop = '#66dd99e6' },
        timerRewardRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerCallBeastReadyGradient = T{ enabled = true, start = '#3399ffe6', stop = '#66bbffe6' },
        timerCallBeastRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerBestialLoyaltyReadyGradient = T{ enabled = true, start = '#9966ffe6', stop = '#bb99ffe6' },
        timerBestialLoyaltyRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        -- DRG ability gradients
        timerCallWyvernReadyGradient = T{ enabled = true, start = '#3366ffe6', stop = '#6699ffe6' },
        timerCallWyvernRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerSpiritLinkReadyGradient = T{ enabled = true, start = '#33cc33e6', stop = '#66dd66e6' },
        timerSpiritLinkRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerDeepBreathingReadyGradient = T{ enabled = true, start = '#ffff33e6', stop = '#ffff99e6' },
        timerDeepBreathingRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerSteadyWingReadyGradient = T{ enabled = true, start = '#cc66ffe6', stop = '#dd99ffe6' },
        timerSteadyWingRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        -- PUP ability gradients
        timerActivateReadyGradient = T{ enabled = true, start = '#3399ffe6', stop = '#66bbffe6' },
        timerActivateRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerRepairReadyGradient = T{ enabled = true, start = '#33cc66e6', stop = '#66dd99e6' },
        timerRepairRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerDeployReadyGradient = T{ enabled = true, start = '#ff9933e6', stop = '#ffbb66e6' },
        timerDeployRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerDeactivateReadyGradient = T{ enabled = true, start = '#999999e6', stop = '#bbbbbbbe6' },
        timerDeactivateRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerRetrieveReadyGradient = T{ enabled = true, start = '#66ccffe6', stop = '#99ddffe6' },
        timerRetrieveRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        timerDeusExAutomataReadyGradient = T{ enabled = true, start = '#ffcc33e6', stop = '#ffdd66e6' },
        timerDeusExAutomataRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        -- 2-Hour timer gradients
        timer2hReadyGradient = T{ enabled = true, start = '#ff00ffe6', stop = '#ff66ffe6' },
        timer2hRecastGradient = T{ enabled = true, start = '#888888d9', stop = '#aaaaaad9' },
        -- BST specific
        durationWarningColor = 0xFFFF6600,
        charmHeartColor = 0xFFFF6699,
        jugIconColor = 0xFFFFFFFF,
        charmTimerColor = 0xFFFFFFFF,
        -- Background
        bgColor = 0xFFFFFFFF,
        borderColor = 0xFFFFFFFF,
    };
end

-- Factory function to create party color settings
local function createPartyColorDefaults(includeTP)
    local colors = T{
        hpGradient = T{
            low = T{ enabled = true, start = '#ec3232', stop = '#f16161' },
            medLow = T{ enabled = true, start = '#ee9c06', stop = '#ecb44e' },
            medHigh = T{ enabled = true, start = '#ffff0c', stop = '#ffff97' },
            high = T{ enabled = true, start = '#e26c6c', stop = '#fa9c9c' },
        },
        mpGradient = T{ enabled = true, start = '#9abb5a', stop = '#bfe07d' },
        barBackgroundOverride = T{ active = false, enabled = true, start = '#01122b', stop = '#061c39' },
        barBorderOverride = T{ active = false, color = '#01122b' },
        nameTextColor = 0xFFFFFFFF,
        hpTextColor = 0xFFFFA7A7,
        mpTextColor = 0xFFD4FF97,
        tpEmptyTextColor = 0xFF8DC7FF,
        tpFullTextColor = 0xFF8DC7FF,
        tpFlashColor = 0xFF3ECE00,
        bgColor = 0xFFFFFFFF,
        borderColor = 0xFFFFFFFF,
        selectionGradient = T{ enabled = true, start = '#4da5d9', stop = '#78c0ed' },
        selectionBorderColor = 0xFF78C0ED,
        subtargetGradient = T{ enabled = true, start = '#d9a54d', stop = '#edcf78' },
        subtargetBorderColor = 0xFFfdd017,
        castBarGradient = T{ enabled = true, start = '#ffaa00', stop = '#ffcc44' },
        castTextColor = 0xFFFFCC44,
    };
    if includeTP then
        colors.tpGradient = T{ enabled = true, start = '#3898ce', stop = '#78c4ee' };
    end
    return colors;
end

-- User-configurable settings
M.user_settings = T{
    lockPositions = false,
    tooltipScale = 1.0,
    hideDuringEvents = true,

    showPlayerBar = true,
    showTargetBar = true,
    showEnemyList = true,
    showExpBar = true,
    showGilTracker = true,
    showInventoryTracker = true,
    showPartyList = true,
    showCastBar = true,
    showPetBar = true,
    showCastCost = true,

    -- Cast Cost settings
    castCostScaleX = 1.0,
    castCostScaleY = 1.0,
    castCostBackgroundTheme = 'Window1',
    castCostBackgroundOpacity = 1.0,
    castCostBorderOpacity = 1.0,
    castCostShowName = true,
    castCostShowMpCost = true,
    castCostShowRecast = false,
    castCostNameFontSize = 12,
    castCostCostFontSize = 12,
    castCostTimeFontSize = 10,
    castCostMinWidth = 100,
    castCostPadding = 8,
    castCostPaddingY = 8,
    castCostAlignBottom = false,
    castCostShowCooldown = true,
    castCostBarScaleY = 1.0,
    castCostRecastFontSize = 10,

    statusIconTheme = 'XIView',
    jobIconTheme = 'FFXI',
    fontFamily = 'Tahoma',
    fontWeight = 'Bold', -- Options: 'Normal', 'Bold'
    fontOutlineWidth = 2, -- Global outline width for all text (range: 0-5)

    showPartyListWhenSolo = false,
    maxEnemyListEntries = 8,  -- Legacy, now calculated from rows * columns
    enemyListRowsPerColumn = 8,
    enemyListMaxColumns = 1,
    enemyListRowSpacing = 5,
    enemyListColumnSpacing = 10,
    enemyListDebuffOffsetX = 131,
    enemyListDebuffOffsetY = 0,
    showEnemyListDebuffs = true,
    enemyListDebuffsRightAlign = false,
    showEnemyListTargets = true,
    enableEnemyListClickTarget = true,
    enemyListPreview = true,

    playerBarScaleX = 1,
    playerBarScaleY = 1,
    playerBarFontSize = 12,
    showPlayerBarBookends = false,
    alwaysShowMpBar = true,
    playerBarTpFlashEnabled = true,
    playerBarHideDuringEvents = true,
    playerBarHpDisplayMode = 'number', -- 'number', 'percent', 'both', 'both_percent_first', 'current_max'
    playerBarMpDisplayMode = 'number', -- 'number', 'percent', 'both', 'both_percent_first', 'current_max'
    showMpCostPreview = true, -- Show spell MP cost preview on MP bars when hovering spells

    -- Text positioning settings for player bar (per stat)
    playerBarHpTextOffsetX = 0,
    playerBarHpTextOffsetY = 0,
    playerBarHpTextAlignment = 'right', -- 'left', 'right'
    playerBarMpTextOffsetX = 0,
    playerBarMpTextOffsetY = 0,
    playerBarMpTextAlignment = 'right', -- 'left', 'right'
    playerBarTpTextOffsetX = 0,
    playerBarTpTextOffsetY = 0,
    playerBarTpTextAlignment = 'right', -- 'left', 'right'

    targetBarScaleX = 1,
    targetBarScaleY = 1,
    targetBarNameFontSize = 12,
    targetBarDistanceFontSize = 12,
    targetBarDistanceOffsetX = 0,
    targetBarDistanceOffsetY = 0,
    targetBarPercentFontSize = 12,
    targetBarPercentOffsetX = 0,
    targetBarPercentOffsetY = 0,
    targetBarCastFontSize = 12,
    targetBarIconScale = 1,
    targetBarIconFontSize = 10,
    targetBarBuffsOffsetY = 4,
    targetBarCastBarOffsetY = 6,
    targetBarCastBarScaleX = 0.4,
    targetBarCastBarScaleY = 1,
    showTargetDistance = true,
    showTargetHpPercent = true,
    showTargetHpPercentAllTargets = false,
    showTargetName = true,
    showTargetBarBookends = false,
    showTargetBarLockOnBorder = true,
    showTargetBarCastBar = true,
    showEnemyId = false,
    targetBarHideDuringEvents = true,
    splitTargetOfTarget = false,
    totBarScaleX = 1,
    totBarScaleY = 1,
    totBarFontSize = 12,

    enemyListScaleX = 1,
    enemyListScaleY = 1,
    enemyListNameFontSize = 10,
    enemyListDistanceFontSize = 8,
    enemyListPercentFontSize = 8,
    enemyListIconScale = 1,
    showEnemyDistance = true,
    showEnemyHPPText = true,
    showEnemyListBookends = false,
    -- Enemy target container settings
    enemyListTargetOffsetX = 0,
    enemyListTargetOffsetY = 43,
    enemyListTargetWidth = 64,
    enemyListTargetFontSize = 8,

    expBarScaleX = 1,
    expBarScaleY = 1,
    showExpBarBookends = false,
    expBarFontSize = 12,
    expBarShowText = true,
    expBarShowPercent = true,
    expBarInlineMode = false,
    expBarLimitPointsMode = false,

    gilTrackerScale = 1,
    gilTrackerFontSize = 12,
    gilTrackerRightAlign = false,
    gilTrackerIconRight = true,
    gilTrackerShowIcon = true,

    inventoryTrackerScale = 1,
    inventoryTrackerFontSize = 12,
    inventoryTrackerOpacity = 1.0,
    inventoryTrackerColumnCount = 5,
    inventoryTrackerRowCount = 6,
    inventoryTrackerColorThreshold1 = 15,
    inventoryTrackerColorThreshold2 = 29,
    inventoryShowCount = true,
    inventoryShowDots = true,
    inventoryShowLabels = false,
    inventoryTextUseThresholdColor = false,

    showSatchelTracker = false,
    satchelTrackerScale = 1,
    satchelTrackerFontSize = 12,
    satchelTrackerColumnCount = 5,
    satchelTrackerRowCount = 6,
    satchelTrackerColorThreshold1 = 15,
    satchelTrackerColorThreshold2 = 29,
    satchelShowCount = true,
    satchelShowDots = true,
    satchelShowLabels = false,
    satchelTextUseThresholdColor = false,

    showLockerTracker = false,
    lockerTrackerScale = 1,
    lockerTrackerFontSize = 12,
    lockerTrackerColumnCount = 5,
    lockerTrackerRowCount = 6,
    lockerTrackerColorThreshold1 = 60,
    lockerTrackerColorThreshold2 = 75,
    lockerShowCount = true,
    lockerShowDots = true,
    lockerShowLabels = false,
    lockerTextUseThresholdColor = false,

    showSafeTracker = false,
    safeTrackerScale = 1,
    safeTrackerFontSize = 12,
    safeTrackerColumnCount = 5,
    safeTrackerRowCount = 6,
    safeTrackerColorThreshold1 = 120,
    safeTrackerColorThreshold2 = 150,
    safeShowCount = true,
    safeShowDots = true,
    safeShowPerContainer = false,
    safeShowLabels = true,
    safeTextUseThresholdColor = false,

    showStorageTracker = false,
    storageTrackerScale = 1,
    storageTrackerFontSize = 12,
    storageTrackerColumnCount = 5,
    storageTrackerRowCount = 6,
    storageTrackerColorThreshold1 = 60,
    storageTrackerColorThreshold2 = 75,
    storageShowCount = true,
    storageShowDots = true,
    storageShowLabels = false,
    storageTextUseThresholdColor = false,

    showWardrobeTracker = false,
    wardrobeTrackerScale = 1,
    wardrobeTrackerFontSize = 12,
    wardrobeTrackerColumnCount = 10,
    wardrobeTrackerRowCount = 8,
    wardrobeTrackerColorThreshold1 = 400,
    wardrobeTrackerColorThreshold2 = 550,
    wardrobeShowCount = true,
    wardrobeShowDots = true,
    wardrobeShowPerContainer = false,
    wardrobeShowLabels = true,
    wardrobeTextUseThresholdColor = false,

    -- Mob Info settings
    showMobInfo = true,
    mobInfoSnapToTargetBar = true,
    mobInfoShowLevel = true,
    mobInfoShowDetection = true,
    mobInfoShowLink = true,
    mobInfoShowResistances = false,
    mobInfoShowWeaknesses = false,
    mobInfoShowImmunities = false,
    mobInfoIconScale = 1.0,
    mobInfoShowNoData = false,
    mobInfoFontSize = 12,
    mobInfoSingleRow = true, -- false = stacked layout, true = single row layout
    mobInfoHideWhenEngaged = false, -- hide mob info when engaged in combat
    mobInfoShowJob = false, -- show mob's job type (WAR, MNK, etc.)
    mobInfoShowModifierText = false, -- show +25%/-50% next to icons
    mobInfoGroupModifiers = true, -- group icons by percentage (Wind Earth Water -25%) vs individual (Wind -25% Earth -25%)
    mobInfoSeparatorStyle = 'space', -- separator style: 'space', 'pipe', 'dot'
    mobInfoShowServerId = false, -- show target's server ID
    mobInfoServerIdHex = true, -- true = hex format (0x1C0), false = decimal

    -- Party List global settings (shared across all parties)
    partyListTitleFontSize = 12,
    partyListHideDuringEvents = true,
    partyListPreview = true,
    partyListAlliance = true,

    -- Per-party settings (Party A, B, C each have independent configurations)
    partyA = createPartyDefaults(),
    partyB = createPartyDefaults({
        jobIconScale = 0.8,
        entrySpacing = 6,
        showTP = false,
        scaleX = 0.7,
        scaleY = 0.7,
    }),
    partyC = createPartyDefaults({
        jobIconScale = 0.8,
        entrySpacing = 6,
        showTP = false,
        scaleX = 0.7,
        scaleY = 0.7,
    }),

    -- Layout templates (bar dimensions and text offsets per layout mode)
    -- These are shared across all parties using the same layout mode
    layoutHorizontal = T{
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
    },

    layoutCompact = T{
        hpBarWidth = 200,
        mpBarWidth = 120,
        tpBarWidth = 0,
        barHeight = 20,
        barSpacing = 8,
        nameTextOffsetX = 1,
        nameTextOffsetY = 0,
        hpTextOffsetX = -8,
        hpTextOffsetY = -1,
        mpTextOffsetX = -4,
        mpTextOffsetY = -1,
        tpTextOffsetX = 0,
        tpTextOffsetY = 1,
    },

    -- Legacy settings (kept for migration, will be removed in future)
    partyListLayout = 0,
    partyListDistanceHighlight = 0,
    partyListBuffScale = 1,
    partyListCastBarScaleY = 0.6,
    partyListCastBars = true,
    partyListStatusTheme = 0,
    partyListTheme = 0,
    partyListFlashTP = false,
    showPartyListBookends = false,
    showPartyJobIcon = true,
    showPartyListTitle = true,
    showPartyListDistance = false,
    showPartyListJob = true,
    partyListCursor = 'GreyArrow.png',
    partyListBackgroundName = 'Window1',
    partyListExpandHeight = false,
    partyListAlignBottom = false,
    partyListBgScale = 1.0,
    partyListBgColor = { 255, 255, 255, 255 },
    partyListBorderColor = { 255, 255, 255, 255 },

    -- Legacy layout settings (kept for migration)
    partyListLayout1 = T{
        partyListScaleX = 1,
        partyListScaleY = 1,
        partyListFontSize = 12,
        splitFontSizes = false,
        partyListNameFontSize = 12,
        partyListHpFontSize = 12,
        partyListMpFontSize = 12,
        partyListTpFontSize = 12,
        partyListDistanceFontSize = 12,
        partyListJobFontSize = 12,
        partyListJobIconScale = 1,
        partyListEntrySpacing = 0,
        partyListTP = true,
        partyListMinRows = 1,
        selectionBoxScaleY = 1,
        partyList2ScaleX = 0.7,
        partyList2ScaleY = 0.7,
        partyList2FontSize = 12,
        partyList2NameFontSize = 12,
        partyList2HpFontSize = 12,
        partyList2MpFontSize = 12,
        partyList2TpFontSize = 12,
        partyList2DistanceFontSize = 12,
        partyList2JobFontSize = 12,
        partyList2JobIconScale = 0.8,
        partyList2EntrySpacing = 6,
        partyList2TP = false,
        partyList3ScaleX = 0.7,
        partyList3ScaleY = 0.7,
        partyList3FontSize = 12,
        partyList3NameFontSize = 12,
        partyList3HpFontSize = 12,
        partyList3MpFontSize = 12,
        partyList3TpFontSize = 12,
        partyList3DistanceFontSize = 12,
        partyList3JobFontSize = 12,
        partyList3JobIconScale = 0.8,
        partyList3EntrySpacing = 6,
        partyList3TP = false,
        hpBarWidth = 150,
        mpBarWidth = 100,
        tpBarWidth = 100,
        barHeight = 20,
        barSpacing = 8,
        hpBarScaleX = 1,
        mpBarScaleX = 1,
        hpBarScaleY = 1,
        mpBarScaleY = 1,
        nameTextOffsetX = 1,
        nameTextOffsetY = 0,
        hpTextOffsetX = -2,
        hpTextOffsetY = -1,
        mpTextOffsetX = -2,
        mpTextOffsetY = -1,
        tpTextOffsetX = -2,
        tpTextOffsetY = -1,
    },

    partyListLayout2 = T{
        partyListScaleX = 1,
        partyListScaleY = 1,
        partyListFontSize = 12,
        splitFontSizes = true,
        partyListNameFontSize = 12,
        partyListHpFontSize = 12,
        partyListMpFontSize = 12,
        partyListTpFontSize = 12,
        partyListDistanceFontSize = 12,
        partyListJobFontSize = 12,
        partyListJobIconScale = 1,
        partyListEntrySpacing = 3,
        partyListTP = true,
        partyListMinRows = 1,
        selectionBoxScaleY = 1,
        partyList2ScaleX = 0.55,
        partyList2ScaleY = 0.55,
        partyList2FontSize = 12,
        partyList2NameFontSize = 12,
        partyList2HpFontSize = 12,
        partyList2MpFontSize = 12,
        partyList2TpFontSize = 12,
        partyList2DistanceFontSize = 12,
        partyList2JobFontSize = 12,
        partyList2JobIconScale = 0.65,
        partyList2EntrySpacing = 1,
        partyList2TP = true,
        partyList2HpBarScaleX = 0.9,
        partyList2MpBarScaleX = 0.6,
        partyList2HpBarScaleY = 1,
        partyList2MpBarScaleY = 0.7,
        partyList3ScaleX = 0.55,
        partyList3ScaleY = 0.55,
        partyList3FontSize = 12,
        partyList3NameFontSize = 12,
        partyList3HpFontSize = 12,
        partyList3MpFontSize = 12,
        partyList3TpFontSize = 12,
        partyList3DistanceFontSize = 12,
        partyList3JobFontSize = 12,
        partyList3JobIconScale = 0.65,
        partyList3EntrySpacing = 1,
        partyList3TP = true,
        partyList3HpBarScaleX = 0.9,
        partyList3MpBarScaleX = 0.6,
        partyList3HpBarScaleY = 1,
        partyList3MpBarScaleY = 0.7,
        hpBarWidth = 200,
        mpBarWidth = 120,
        tpBarWidth = 0,
        barHeight = 20,
        barSpacing = 8,
        hpBarScaleX = 0.9,
        mpBarScaleX = 0.6,
        hpBarScaleY = 1,
        mpBarScaleY = 0.7,
        nameTextOffsetX = 1,
        nameTextOffsetY = 0,
        hpTextOffsetX = -8,
        hpTextOffsetY = -1,
        mpTextOffsetX = -4,
        mpTextOffsetY = -1,
        tpTextOffsetX = 0,
        tpTextOffsetY = 1,
    },

    castBarScaleX = 1,
    castBarScaleY = 1,
    showCastBarBookends = false,
    castBarFontSize = 12,
    castBarFastCastEnabled = false,
    castBarFastCastRDMSJ = 0.17,
    castBarFastCastWHMCureSpeed = 0.15,
    castBarFastCastBRDSingSpeed = 0.37,
    castBarFastCast = {
        [1] = 0.02, -- WAR
        [2] = 0.02, -- MNK
        [3] = 0.04, -- WHM
        [4] = 0.04, -- BLM
        [5] = 0.42, -- RDM
        [6] = 0.07, -- THF
        [7] = 0.07, -- PLD
        [8] = 0.07, -- DRK
        [9] = 0.02, -- BST
        [10] = 0.04, -- BRD
        [11] = 0.02, -- RNG
        [12] = 0.02, -- SAM
        [13] = 0.02, -- NIN
        [14] = 0.07, -- DRG
        [15] = 0.04, -- SMN
        [16] = 0.07, -- BLU
        [17] = 0.02, -- COR
        [18] = 0.04, -- PUP
        [19] = 0.02, -- DNC
        [20] = 0.02, -- SCH
        [21] = 0.02, -- GEO
        [22] = 0.02, -- RUN
    },

    -- Pet Bar settings
    petBarScaleX = 1.0,
    petBarScaleY = 1.0,
    petBarHideDuringEvents = true,
    petBarPreview = true,
    petBarPreviewType = 2, -- Avatar (SMN)
    petBarShowDistance = true,
    petBarShowTarget = true,
    petBarShowVitals = true,
    petBarShowTimers = true,
    petBarShow2HourAbility = false,
    petBarShowImage = true,
    petBarShowBookends = false,
    petBarShowLevel = true, -- Show pet level in name
    petBarIconsAbsolute = true,
    petBarIconsScale = 0.6,
    petBarIconsOffsetX = 128,
    petBarIconsOffsetY = 78,
    -- Distance text positioning (absolute = relative to window top-left)
    petBarDistanceAbsolute = true,
    petBarDistanceOffsetX = 11,
    petBarDistanceOffsetY = 79,
    petBarBackgroundTheme = 'Window1',
    petBarBackgroundOpacity = 1.0,
    -- BST Charm indicator settings (absolute positioned relative to window)
    petBarShowCharmIndicator = true,
    petBarShowJugTimer = true,
    petBarCharmIconSize = 16,
    petBarCharmTimerFontSize = 12,
    petBarCharmOffsetX = 0,
    petBarCharmOffsetY = -16,
    petBarJugIconSize = 16,
    petBarJugTimerFontSize = 12,
    petBarJugOffsetX = 5,
    petBarJugOffsetY = -17,

    -- Pet ability icon toggles per job
    -- SMN abilities
    petBarSmnShowBPRage = true,
    petBarSmnShowBPWard = true,
    petBarSmnShowApogee = false,
    petBarSmnShowManaCede = false,
    -- BST abilities (Ready and Sic share same timer ID 102, tracked as Ready)
    petBarBstShowReady = true,
    petBarBstShowReward = true,
    petBarBstShowCallBeast = false,
    petBarBstShowBestialLoyalty = false,
    -- DRG abilities
    petBarDrgShowCallWyvern = true,
    petBarDrgShowSpiritLink = true,
    petBarDrgShowDeepBreathing = true,
    petBarDrgShowSteadyWing = true,
    -- PUP abilities
    petBarPupShowActivate = true,
    petBarPupShowRepair = true,
    petBarPupShowDeusExAutomata = true,
    petBarPupShowDeploy = true,
    petBarPupShowDeactivate = true,
    petBarPupShowRetrieve = true,
    -- Legacy global pet image settings (kept for migration)
    petBarImageScale = 0.4,
    petBarImageOpacity = 0.3,
    petBarImageOffsetX = 0,
    petBarImageOffsetY = 0,

    -- Per-avatar image settings
    petBarAvatarSettings = T{
        carbuncle = T{ scale = 0.5, opacity = 0.3, offsetX = 70, offsetY = -135, clipToBackground = true },
        ifrit = T{ scale = 0.4, opacity = 0.3, offsetX = -40, offsetY = -60, clipToBackground = true },
        shiva = T{ scale = 0.4, opacity = 0.3, offsetX = -70, offsetY = -40, clipToBackground = true },
        garuda = T{ scale = 0.6, opacity = 0.3, offsetX = -35, offsetY = -194, clipToBackground = true },
        titan = T{ scale = 0.44, opacity = 0.3, offsetX = -24, offsetY = -88, clipToBackground = true },
        ramuh = T{ scale = 0.44, opacity = 0.3, offsetX = -96, offsetY = -24, clipToBackground = true },
        leviathan = T{ scale = 0.4, opacity = 0.3, offsetX = -200, offsetY = -102, clipToBackground = true },
        fenrir = T{ scale = 0.2, opacity = 0.35, offsetX = 49, offsetY = -60, clipToBackground = true },
        diabolos = T{ scale = 0.4, opacity = 0.3, offsetX = 0, offsetY = 0, clipToBackground = true },
        atomos = T{ scale = 0.4, opacity = 0.3, offsetX = 0, offsetY = 0, clipToBackground = true },
        odin = T{ scale = 0.4, opacity = 0.3, offsetX = 0, offsetY = 0, clipToBackground = true },
        alexander = T{ scale = 0.4, opacity = 0.3, offsetX = 0, offsetY = 0, clipToBackground = true },
        caitsith = T{ scale = 0.63, opacity = 0.3, offsetX = 21, offsetY = -180, clipToBackground = true },
        siren = T{ scale = 0.66, opacity = 0.3, offsetX = -263, offsetY = -113, clipToBackground = true },
        firespirit = T{ scale = 0.4, opacity = 0.3, offsetX = 0, offsetY = 0, clipToBackground = true },
        icespirit = T{ scale = 0.4, opacity = 0.3, offsetX = 0, offsetY = 0, clipToBackground = true },
        airspirit = T{ scale = 0.4, opacity = 0.3, offsetX = 0, offsetY = 0, clipToBackground = true },
        earthspirit = T{ scale = 0.4, opacity = 0.3, offsetX = 0, offsetY = 0, clipToBackground = true },
        thunderspirit = T{ scale = 0.4, opacity = 0.3, offsetX = 0, offsetY = 0, clipToBackground = true },
        waterspirit = T{ scale = 0.4, opacity = 0.3, offsetX = 0, offsetY = 0, clipToBackground = true },
        lightspirit = T{ scale = 0.4, opacity = 0.3, offsetX = 0, offsetY = 0, clipToBackground = true },
        darkspirit = T{ scale = 0.4, opacity = 0.3, offsetX = 0, offsetY = 0, clipToBackground = true },
    },
    petBarHpScaleX = 1.0,
    petBarHpScaleY = 1.0,
    petBarMpScaleX = 1.0,
    petBarMpScaleY = 1.0,
    petBarTpScaleX = 1.0,
    petBarTpScaleY = 1.0,
    petBarNameFontSize = 12,
    petBarDistanceFontSize = 10,
    petBarVitalsFontSize = 10,
    petBarTimerFontSize = 10,
    petBarHpDisplayMode = 'percent', -- 'percent', 'number'
    petBarTargetFontSize = 10,
    petTargetBackgroundTheme = nil,  -- Uses petBarBackgroundTheme by default
    petTargetBackgroundOpacity = 1.0,
    petTargetBorderOpacity = 1.0,
    petTargetBarScaleX = 1.0,
    petTargetBarScaleY = 1.0,

    -- Pet Target text positioning (absolute = relative to window top-left, anchored = flow with layout)
    -- Target Name positioning
    petTargetNameAbsolute = false,       -- Anchored by default (in row with HP%)
    petTargetNameOffsetX = 0,
    petTargetNameOffsetY = 0,
    -- HP% text positioning
    petTargetHpAbsolute = false,         -- Anchored by default (right side of name row)
    petTargetHpOffsetX = 0,
    petTargetHpOffsetY = 0,
    -- Distance text positioning
    petTargetDistanceAbsolute = true,    -- Absolute by default
    petTargetDistanceOffsetX = 11,
    petTargetDistanceOffsetY = 44,

    -- Pet Target snap to petbar (positions pet target directly below petbar)
    petTargetSnapToPetBar = true,        -- When enabled, pet target snaps below petbar
    petTargetSnapOffsetX = 0,            -- Horizontal offset from petbar position
    petTargetSnapOffsetY = 16,           -- Vertical offset below petbar (accounts for background border)

    -- Per-pet-type settings (Avatar, Charm, Jug, Automaton, Wyvern each have independent visual settings)
    petBarAvatar = createPetBarTypeDefaults(),
    petBarCharm = createPetBarTypeDefaults({ iconsOffsetX = 94 }),
    petBarJug = createPetBarTypeDefaults({ iconsOffsetX = 94 }),
    petBarAutomaton = createPetBarTypeDefaults({ iconsOffsetX = 60 }),
    petBarWyvern = createPetBarTypeDefaults({
        iconsOffsetX = 94,
        -- Wyvern image settings
        showImage = true,
        imageScale = 0.69,
        imageOpacity = 0.40,
        imageOffsetX = -99,
        imageOffsetY = -46,
        imageClipToBackground = true,
    }),

    -- Bar Settings (global progress bar configuration)
    showBookends = false,            -- Global toggle that sets all module bookend settings
    bookendSize = 10,               -- Minimum bookend width in pixels (5-20)
    healthBarFlashEnabled = true,   -- Flash effect when taking damage
    noBookendRounding = 4,          -- Bar roundness for bars without bookends (0-10)
    barBorderThickness = 1,         -- Border thickness for all progress bars (1-5)

    -- Color customization settings
    colorCustomization = T{
        -- Player Bar
        playerBar = T{
            hpGradient = T{
                low = T{ enabled = true, start = '#ec3232', stop = '#f16161' },      -- 0-25%
                medLow = T{ enabled = true, start = '#ee9c06', stop = '#ecb44e' },   -- 25-50%
                medHigh = T{ enabled = true, start = '#ffff0c', stop = '#ffff97' },  -- 50-75%
                high = T{ enabled = true, start = '#e26c6c', stop = '#fa9c9c' },     -- 75-100%
            },
            mpGradient = T{ enabled = true, start = '#9abb5a', stop = '#bfe07d' },
            tpGradient = T{ enabled = true, start = '#3898ce', stop = '#78c4ee' },
            tpOverlayGradient = T{ enabled = true, start = '#0078CC', stop = '#0078CC' },  -- TP overlay bar (1000+ stored)
            hpTextColor = 0xFFFFA7A7,
            mpTextColor = 0xFFD4FF97,
            tpEmptyTextColor = 0xFF8DC7FF,  -- TP < 1000
            tpFullTextColor = 0xFF8DC7FF,   -- TP >= 1000
            tpFlashColor = 0xFF2fa9ff,      -- TP flash effect color
        },

        -- Target Bar
        targetBar = T{
            hpGradient = T{ enabled = true, start = '#e26c6c', stop = '#fb9494' },
            castBarGradient = T{ enabled = true, start = '#ffaa00', stop = '#ffcc44' },
            distanceTextColor = 0xFFFFFFFF,
            castTextColor = 0xFFFFAA00,  -- Orange color for enemy casting
            -- Note: HP percent text color is set dynamically based on HP amount
            -- Note: Entity name colors are in shared section
        },

        -- Target of Target Bar
        totBar = T{
            hpGradient = T{ enabled = true, start = '#e16c6c', stop = '#fb9494' },
        },

        -- Enemy List
        enemyList = T{
            hpGradient = T{ enabled = true, start = '#e16c6c', stop = '#fb9494' },
            distanceTextColor = 0xFFFFFFFF,
            percentTextColor = 0xFFFFFFFF,
            targetBorderColor = 0xFFFFFFFF,      -- white - border for main target
            subtargetBorderColor = 0xFF8080FF,   -- blue - border for subtarget
            targetNameTextColor = 0xFFFFAA00,    -- orange - enemy's target name
            -- Note: Entity name colors are in shared section
        },

        -- Party List (per-party color settings)
        partyListA = createPartyColorDefaults(true),  -- Include TP colors
        partyListB = createPartyColorDefaults(false), -- No TP colors
        partyListC = createPartyColorDefaults(false), -- No TP colors

        -- Exp Bar
        expBar = T{
            expBarGradient = T{ enabled = true, start = '#c39040', stop = '#e9c466' },
            meritBarGradient = T{ enabled = true, start = '#3064c3', stop = '#66a0e9' },
            jobTextColor = 0xFFFFFFFF,
            expTextColor = 0xFFFFFFFF,
            percentTextColor = 0xFFFFFF00,
        },

        -- Gil Tracker
        gilTracker = T{
            textColor = 0xFFFFFFFF,
        },

        -- Inventory Tracker
        inventoryTracker = T{
            textColor = 0xFFFFFFFF,
            emptySlotColor = T{ r = 0, g = 0.07, b = 0.17, a = 1 },
            usedSlotColor = T{ r = 0.37, g = 0.7, b = 0.88, a = 1 },        -- Normal (white/blue)
            usedSlotColorThreshold1 = T{ r = 1.0, g = 1.0, b = 0, a = 1 },  -- Warning (yellow)
            usedSlotColorThreshold2 = T{ r = 1.0, g = 0, b = 0, a = 1 },    -- Critical (red)
        },

        -- Satchel Tracker
        satchelTracker = T{
            textColor = 0xFFFFFFFF,
            emptySlotColor = T{ r = 0, g = 0.07, b = 0.17, a = 1 },
            usedSlotColor = T{ r = 0.37, g = 0.7, b = 0.88, a = 1 },        -- Normal (white/blue)
            usedSlotColorThreshold1 = T{ r = 1.0, g = 1.0, b = 0, a = 1 },  -- Warning (yellow)
            usedSlotColorThreshold2 = T{ r = 1.0, g = 0, b = 0, a = 1 },    -- Critical (red)
        },

        -- Locker Tracker
        lockerTracker = T{
            textColor = 0xFFFFFFFF,
            emptySlotColor = T{ r = 0, g = 0.07, b = 0.17, a = 1 },
            usedSlotColor = T{ r = 0.37, g = 0.7, b = 0.88, a = 1 },        -- Normal (white/blue)
            usedSlotColorThreshold1 = T{ r = 1.0, g = 1.0, b = 0, a = 1 },  -- Warning (yellow)
            usedSlotColorThreshold2 = T{ r = 1.0, g = 0, b = 0, a = 1 },    -- Critical (red)
        },

        -- Safe Tracker (Safe + Safe2)
        safeTracker = T{
            textColor = 0xFFFFFFFF,
            emptySlotColor = T{ r = 0, g = 0.07, b = 0.17, a = 1 },
            usedSlotColor = T{ r = 0.37, g = 0.7, b = 0.88, a = 1 },        -- Normal (white/blue)
            usedSlotColorThreshold1 = T{ r = 1.0, g = 1.0, b = 0, a = 1 },  -- Warning (yellow)
            usedSlotColorThreshold2 = T{ r = 1.0, g = 0, b = 0, a = 1 },    -- Critical (red)
        },

        -- Storage Tracker
        storageTracker = T{
            textColor = 0xFFFFFFFF,
            emptySlotColor = T{ r = 0, g = 0.07, b = 0.17, a = 1 },
            usedSlotColor = T{ r = 0.37, g = 0.7, b = 0.88, a = 1 },        -- Normal (white/blue)
            usedSlotColorThreshold1 = T{ r = 1.0, g = 1.0, b = 0, a = 1 },  -- Warning (yellow)
            usedSlotColorThreshold2 = T{ r = 1.0, g = 0, b = 0, a = 1 },    -- Critical (red)
        },

        -- Wardrobe Tracker (all 8 wardrobes)
        wardrobeTracker = T{
            textColor = 0xFFFFFFFF,
            emptySlotColor = T{ r = 0, g = 0.07, b = 0.17, a = 1 },
            usedSlotColor = T{ r = 0.37, g = 0.7, b = 0.88, a = 1 },        -- Normal (white/blue)
            usedSlotColorThreshold1 = T{ r = 1.0, g = 1.0, b = 0, a = 1 },  -- Warning (yellow)
            usedSlotColorThreshold2 = T{ r = 1.0, g = 0, b = 0, a = 1 },    -- Critical (red)
        },

        -- Cast Bar
        castBar = T{
            barGradient = T{ enabled = true, start = '#3798ce', stop = '#78c5ee' },
            spellTextColor = 0xFFFFFFFF,
            percentTextColor = 0xFFFFFFFF,
        },

        -- Cast Cost
        castCost = T{
            nameTextColor = 0xFFFFFFFF,
            nameOnCooldownColor = 0xFF888888, -- Grey when spell is on cooldown
            mpCostTextColor = 0xFFD4FF97,   -- Green (matches MP color)
            mpNotEnoughColor = 0xFFFF6666,  -- Red when not enough MP
            tpCostTextColor = 0xFF8DC7FF,   -- Blue (matches TP color)
            timeTextColor = 0xFFCCCCCC,     -- Light gray for cast/recast times
            readyTextColor = 0xFF44CC44,    -- Green when spell is ready
            cooldownTextColor = 0xFFFFFFFF, -- White text on cooldown bar
            cooldownBarGradient = T{ enabled = false, start = '#FFFFFF', stop = '#44CC44' },
            bgColor = 0xFFFFFFFF,
            borderColor = 0xFFFFFFFF,
            -- MP Cost Preview on Player/Party MP bars
            mpCostPreviewGradient = T{ enabled = true, start = '#9abb5a', stop = '#bfe07d' }, -- Base: MP green
            mpCostPreviewFlashColor = '#FFFFFF',  -- Pulse flash color (white)
            mpCostPreviewPulseSpeed = 1.0,        -- Pulse duration in seconds
        },

        -- Pet Bar
        petBar = T{
            hpGradient = T{ enabled = true, start = '#e26c6c', stop = '#fa9c9c' },  -- Match playerBar high HP
            mpGradient = T{ enabled = true, start = '#9abb5a', stop = '#bfe07d' },  -- Match playerBar MP
            tpGradient = T{ enabled = true, start = '#3898ce', stop = '#78c4ee' },  -- Match playerBar TP
            nameTextColor = 0xFFFFFFFF,
            distanceTextColor = 0xFFFFFFFF,
            hpTextColor = 0xFFFFA7A7,
            mpTextColor = 0xFFD4FF97,
            tpTextColor = 0xFF8DC7FF,
            targetTextColor = 0xFFFFFFFF,
            -- SMN ability colors (individual)
            timerBPRageReadyColor = 0xE6FF3333,     -- Red - Blood Pact: Rage ready
            timerBPRageRecastColor = 0xD9FF6666,    -- Light red - Blood Pact: Rage recast
            timerBPWardReadyColor = 0xE600CCCC,     -- Teal - Blood Pact: Ward ready
            timerBPWardRecastColor = 0xD966DDDD,    -- Light teal - Blood Pact: Ward recast
            timerApogeeReadyColor = 0xE6FFCC00,     -- Gold - Apogee ready
            timerApogeeRecastColor = 0xD9FFDD66,    -- Light gold - Apogee recast
            timerManaCedeReadyColor = 0xE6009999,   -- Dark teal - Mana Cede ready
            timerManaCedeRecastColor = 0xD966BBBB,  -- Light dark teal - Mana Cede recast
            -- BST ability colors (individual)
            timerReadyReadyColor = 0xE6FF6600,      -- Orange - Ready ready
            timerReadyRecastColor = 0xD9FF9933,     -- Light orange - Ready recast
            timerRewardReadyColor = 0xE600CC66,     -- Green - Reward ready
            timerRewardRecastColor = 0xD966DD99,    -- Light green - Reward recast
            timerCallBeastReadyColor = 0xE63399FF,  -- Blue - Call Beast ready
            timerCallBeastRecastColor = 0xD966BBFF, -- Light blue - Call Beast recast
            timerBestialLoyaltyReadyColor = 0xE69966FF,  -- Purple - Bestial Loyalty ready
            timerBestialLoyaltyRecastColor = 0xD9BB99FF, -- Light purple - Bestial Loyalty recast
            -- DRG ability colors (individual)
            timerCallWyvernReadyColor = 0xE63366FF,     -- Blue - Call Wyvern ready
            timerCallWyvernRecastColor = 0xD96699FF,    -- Light blue - Call Wyvern recast
            timerSpiritLinkReadyColor = 0xE633CC33,     -- Green - Spirit Link ready
            timerSpiritLinkRecastColor = 0xD966DD66,    -- Light green - Spirit Link recast
            timerDeepBreathingReadyColor = 0xE6FFFF33,  -- Yellow - Deep Breathing ready
            timerDeepBreathingRecastColor = 0xD9FFFF99, -- Light yellow - Deep Breathing recast
            timerSteadyWingReadyColor = 0xE6CC66FF,     -- Purple - Steady Wing ready
            timerSteadyWingRecastColor = 0xD9DD99FF,    -- Light purple - Steady Wing recast
            -- PUP ability colors (individual)
            timerActivateReadyColor = 0xE63399FF,       -- Blue - Activate ready
            timerActivateRecastColor = 0xD966BBFF,      -- Light blue - Activate recast
            timerRepairReadyColor = 0xE633CC66,         -- Green - Repair ready
            timerRepairRecastColor = 0xD966DD99,        -- Light green - Repair recast
            timerDeployReadyColor = 0xE6FF9933,         -- Orange - Deploy ready
            timerDeployRecastColor = 0xD9FFBB66,        -- Light orange - Deploy recast
            timerDeactivateReadyColor = 0xE6999999,     -- Gray - Deactivate ready
            timerDeactivateRecastColor = 0xD9BBBBBB,    -- Light gray - Deactivate recast
            timerRetrieveReadyColor = 0xE666CCFF,       -- Light blue - Retrieve ready
            timerRetrieveRecastColor = 0xD999DDFF,      -- Lighter blue - Retrieve recast
            timerDeusExAutomataReadyColor = 0xE6FFCC33, -- Gold - Deus Ex Automata ready
            timerDeusExAutomataRecastColor = 0xD9FFDD66,-- Light gold - Deus Ex Automata recast
            -- 2-Hour timer colors (Astral Flow, Familiar, Spirit Surge, Overdrive)
            timer2hReadyColor = 0xE6FF00FF,     -- Magenta
            timer2hRecastColor = 0xD9FF66FF,    -- Light magenta
            durationWarningColor = 0xFFFF6600, -- Charm/Jug about to expire (orange)
            charmHeartColor = 0xFFFF6699,      -- BST charm heart icon (pink)
            jugIconColor = 0xFFFFFFFF,         -- BST jug pet icon
            charmTimerColor = 0xFFFFFFFF,      -- BST pet timer text (charm/jug)
            bgColor = 0xFFFFFFFF,              -- Background tint (for Plain theme)
        },

        -- Pet Target
        petTarget = T{
            hpGradient = T{ enabled = true, start = '#e26c6c', stop = '#fb9494' },
            bgColor = 0xFFFF8D8D,              -- Background tint (for Plain theme)
            targetTextColor = 0xFFFFFFFF,
            hpTextColor = 0xFFFFA7A7,          -- HP% text color
            distanceTextColor = 0xFFFFFFFF,    -- Distance text color
            borderColor = 0xFFFF8D8D,
        },

        -- Per-pet-type color settings (Avatar, Charm, Jug, Automaton, Wyvern)
        petBarAvatar = createPetBarTypeColorDefaults(),
        petBarCharm = createPetBarTypeColorDefaults(),
        petBarJug = createPetBarTypeColorDefaults(),
        petBarAutomaton = createPetBarTypeColorDefaults(),
        petBarWyvern = createPetBarTypeColorDefaults(),

        -- Mob Info
        mobInfo = T{
            levelTextColor = 0xFFFFFFFF,
        },

        -- Global/Shared
        shared = T{
            backgroundGradient = T{ enabled = true, start = '#01122b', stop = '#061c39' },
            bookendGradient = T{ start = '#576C92', mid = '#B7C9FF', stop = '#576C92' },
            -- Entity name colors (used by target bar, enemy list, etc.)
            playerPartyTextColor = 0xFF00FFFF,     -- cyan - party/alliance members
            playerOtherTextColor = 0xFFFFFFFF,     -- white - other players
            npcTextColor = 0xFF66FF66,             -- green - NPCs
            mobUnclaimedTextColor = 0xFFFFFF66,    -- yellow - unclaimed mobs
            mobPartyClaimedTextColor = 0xFFFF6666, -- red - mobs claimed by party
            mobOtherClaimedTextColor = 0xFFFF66FF, -- magenta - mobs claimed by others
            -- HP bar interpolation effect colors
            hpDamageGradient = T{ enabled = true, start = '#cf3437', stop = '#c54d4d' },
            hpDamageFlashColor = '#ffacae',
            hpHealGradient = T{ enabled = true, start = '#4ade80', stop = '#86efac' },
            hpHealFlashColor = '#c8ffc8',
        },
    },
};

-- Internal module default settings (dimensions, fonts, etc.)
M.default_settings = T{
    -- global settings
    currentPatchVer = 2,
    tpEmptyColor = 0xFF9acce8,
    tpFullColor = 0xFF2fa9ff,
    mpColor = 0xFFdef2db,

    -- settings for the targetbar
    targetBarSettings = T{
        -- Damage interpolation
        hitInterpolationDecayPercentPerSecond = 150,
        hitDelayDuration = 0.5,
        hitFlashDuration = 0.4,

        -- Everything else
        barWidth = 500,
        barHeight = 18,
        totBarHeight = 14,
        totBarOffset = -1,
        textScale = 1.2,
        cornerOffset = 5,
        nameXOffset = 12,
        nameYOffset = 9,
        iconSize = 22,
        arrowSize = 30,
        maxIconColumns = 12,
        topTextYOffset = 6,
        topTextXOffset = 5,
        bottomTextYOffset = 0,
        bottomTextXOffset = 15,
        -- Buff/Debuff positioning
        buffsOffsetY = 4,
        -- Cast bar positioning and scaling
        castBarOffsetY = 6,
        castBarOffsetX = 12,
        castBarWidth = 500,  -- Base width (will be adjusted by scale and inset)
        name_font_settings = T{
            font_alignment = gdi.Alignment.Left,
            font_family = 'Consolas',
            font_height = 13,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        totName_font_settings = T{
            font_alignment = gdi.Alignment.Left,
            font_family = 'Consolas',
            font_height = 12,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        distance_font_settings = T{
            font_alignment = gdi.Alignment.Right,
            font_family = 'Consolas',
            font_height = 11,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        percent_font_settings = T{
            font_alignment = gdi.Alignment.Right,
            font_family = 'Consolas',
            font_height = 11,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        cast_font_settings = T{
            font_alignment = gdi.Alignment.Center,
            font_family = 'Consolas',
            font_height = 12,
            font_color = 0xFFFFAA00,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
    },

    -- settings for the playerbar
    playerBarSettings = T{
        -- Damage interpolation
        hitInterpolationDecayPercentPerSecond = 150,
        hitDelayDuration = 0.5,
        hitFlashDuration = 0.4,
        barWidth = 500,
        barSpacing = 10,
        barHeight = 20,
        textYOffset = -1,
        font_settings = T{
            font_alignment = gdi.Alignment.Right,
            font_family = 'Consolas',
            font_height = 15,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
    },

    -- settings for enemy list
    enemyListSettings = T{
        barWidth = 125,
        barHeight = 10,
        textScale = 1,
        entrySpacing = 1,
        bgPadding = 7,
        bgTopPadding = -3,
        maxIcons = 5,
        iconSize = 18,
        debuffOffsetX = -10,
        debuffOffsetY = 0,
        name_font_settings = T{
            font_alignment = gdi.Alignment.Left,
            font_family = 'Consolas',
            font_height = 10,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        distance_font_settings = T{
            font_alignment = gdi.Alignment.Left,
            font_family = 'Consolas',
            font_height = 8,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        percent_font_settings = T{
            font_alignment = gdi.Alignment.Right,
            font_family = 'Consolas',
            font_height = 8,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        target_font_settings = T{
            font_alignment = gdi.Alignment.Left,
            font_family = 'Consolas',
            font_height = 8,
            font_color = 0xFFFFAA00,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        prim_data = {
            texture_offset_x= 0.0,
            texture_offset_y= 0.0,
            border_visible  = false,
            border_flags    = FontBorderFlags.None,
            border_sizes    = '0,0,0,0',
            visible         = false,
            position_x      = 0,
            position_y      = 0,
            can_focus       = true,
            locked          = false,
            lockedz         = false,
            scale_x         = 1.0,
            scale_y         = 1.0,
            width           = 0.0,
            height          = 0.0,
            color           = 0xFFFFFFFF,
        },
    },

    -- settings for the exp bar
    expBarSettings = T{
        barWidth = 550,
        barHeight = 12,
        textOffsetY = 4,
        percentOffsetX = -5,
        job_font_settings = T{
            font_alignment = gdi.Alignment.Left,
            font_family = 'Consolas',
            font_height = 11,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        exp_font_settings = T{
            font_alignment = gdi.Alignment.Right,
            font_family = 'Consolas',
            font_height = 11,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        percent_font_settings = T{
            font_alignment = gdi.Alignment.Right,
            font_family = 'Consolas',
            font_height = 8,
            font_color = 0xFFFFFF00,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
    },

    -- settings for gil tracker
    gilTrackerSettings = T{
        iconScale = 30,
        font_settings = T{
            font_family = 'Consolas',
            font_height = 13,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
    },

    inventoryTrackerSettings = T{
        columnCount = 5,
        rowCount = 6,
        dotRadius = 5,
        dotSpacing = 1,
        groupSpacing = 8,
        textOffsetY = -3,
        font_settings = T{
            font_alignment = gdi.Alignment.Right,
            font_family = 'Consolas',
            font_height = 13,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
    },

    satchelTrackerSettings = T{
        columnCount = 5,
        rowCount = 6,
        dotRadius = 5,
        dotSpacing = 1,
        groupSpacing = 8,
        textOffsetY = -3,
        font_settings = T{
            font_alignment = gdi.Alignment.Right,
            font_family = 'Consolas',
            font_height = 13,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
    },

    lockerTrackerSettings = T{
        columnCount = 5,
        rowCount = 6,
        dotRadius = 5,
        dotSpacing = 1,
        groupSpacing = 8,
        textOffsetY = -3,
        font_settings = T{
            font_alignment = gdi.Alignment.Right,
            font_family = 'Consolas',
            font_height = 13,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
    },

    safeTrackerSettings = T{
        columnCount = 5,
        rowCount = 6,
        dotRadius = 5,
        dotSpacing = 1,
        groupSpacing = 8,
        textOffsetY = -3,
        font_settings = T{
            font_alignment = gdi.Alignment.Right,
            font_family = 'Consolas',
            font_height = 13,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
    },

    storageTrackerSettings = T{
        columnCount = 5,
        rowCount = 6,
        dotRadius = 5,
        dotSpacing = 1,
        groupSpacing = 8,
        textOffsetY = -3,
        font_settings = T{
            font_alignment = gdi.Alignment.Right,
            font_family = 'Consolas',
            font_height = 13,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
    },

    wardrobeTrackerSettings = T{
        columnCount = 10,
        rowCount = 8,
        dotRadius = 5,
        dotSpacing = 1,
        groupSpacing = 8,
        textOffsetY = -3,
        font_settings = T{
            font_alignment = gdi.Alignment.Right,
            font_family = 'Consolas',
            font_height = 13,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
    },

    -- settings for mob info
    mobInfoSettings = T{
        iconSize = 20,
        iconSpacing = 2,
        rowSpacing = 4,
        maxIconsPerRow = 10,
        level_font_settings = T{
            font_alignment = gdi.Alignment.Left,
            font_family = 'Consolas',
            font_height = 12,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
    },

    partyListSettings = T{
        -- Damage interpolation
        hitInterpolationDecayPercentPerSecond = 150,
        hitDelayDuration = 0.5,
        hitFlashDuration = 0.4,
        hpBarWidth = 150,
        tpBarWidth = 100,
        mpBarWidth = 100,
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

        borderSize = 21,
        bgPadding = 4,
        bgPaddingY = 10,
        bgOffset = 1,

        cursorPaddingX1 = 8,
        cursorPaddingX2 = 8,
        cursorPaddingY1 = 7,
        cursorPaddingY2 = 10,
        dotRadius = 3,

        arrowSize = 1,

        subtargetArrowTint = 0xFFfdd017,
        targetArrowTint = 0xFFFFFFFF,

        iconSize = 22,
        maxIconColumns = 6,
        buffOffset = 10,
        xivBuffOffsetY = 1,
        entrySpacing = 8,
        expandHeight = false,
        alignBottom = false,
        minRows = 1,

        hp_font_settings = T{
            font_alignment = gdi.Alignment.Right,
            font_family = 'Consolas',
            font_height = 13,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        mp_font_settings = T{
            font_alignment = gdi.Alignment.Left,
            font_family = 'Consolas',
            font_height = 12,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        tp_font_settings = T{
            font_alignment = gdi.Alignment.Left,
            font_family = 'Consolas',
            font_height = 12,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        name_font_settings = T{
            font_alignment = gdi.Alignment.Left,
            font_family = 'Consolas',
            font_height = 13,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        title_font_settings = T{
            font_alignment = gdi.Alignment.None,
            font_family = 'Consolas',
            font_height = 14,
            font_color = 0xFFC5CFDC,
            font_flags = gdi.FontFlags.Italic,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        prim_data = {
            texture_offset_x= 0.0,
            texture_offset_y= 0.0,
            border_visible  = false,
            border_flags    = FontBorderFlags.None,
            border_sizes    = '0,0,0,0',
            visible         = true,
            position_x      = 0,
            position_y      = 0,
            can_focus       = false,
            locked          = true,
            lockedz         = true,
            scale_x         = 1.0,
            scale_y         = 1.0,
            width           = 0.0,
            height          = 0.0,
        },
    },

    castBarSettings = T{
        barWidth = 500,
        barHeight = 20,
        spellOffsetY = 2,
        percentOffsetY = 2,
        percentOffsetX = -10,
        spell_font_settings = T{
            font_alignment = gdi.Alignment.Left,
            font_family = 'Consolas',
            font_height = 15,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        percent_font_settings = T{
            font_alignment = gdi.Alignment.Right,
            font_family = 'Consolas',
            font_height = 15,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
    },

    -- settings for cast cost
    castCostSettings = T{
        minWidth = 100,
        alignBottom = false,
        showCooldown = true,
        barScaleY = 1.0,
        bgPadding = 8,
        bgPaddingY = 8,
        borderSize = 21,
        bgOffset = 1,
        bgScale = 1.0,
        backgroundTheme = 'Window1',
        backgroundOpacity = 1.0,
        borderOpacity = 1.0,
        showName = true,
        showMpCost = true,
        showRecast = true,
        name_font_settings = T{
            font_alignment = gdi.Alignment.Left,
            font_family = 'Consolas',
            font_height = 12,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        cost_font_settings = T{
            font_alignment = gdi.Alignment.Left,
            font_family = 'Consolas',
            font_height = 12,
            font_color = 0xFFD4FF97,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        time_font_settings = T{
            font_alignment = gdi.Alignment.Left,
            font_family = 'Consolas',
            font_height = 10,
            font_color = 0xFFCCCCCC,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        recast_font_settings = T{
            font_alignment = gdi.Alignment.Right,
            font_family = 'Consolas',
            font_height = 10,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        cooldown_font_settings = T{
            font_alignment = gdi.Alignment.Left,
            font_family = 'Consolas',
            font_height = 10,
            font_color = 0xFF44CC44,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        prim_data = T{
            visible = false,
            can_focus = false,
            locked = true,
            width = 100,
            height = 100,
        },
    },

    -- settings for pet bar
    petBarSettings = T{
        barWidth = 150,
        barHeight = 12,
        barSpacing = 4,
        bgPadding = 8,
        bgPaddingY = 8,
        bgOffset = 1,
        bgScale = 1.0,
        borderSize = 21,
        -- HP interpolation settings
        hitInterpolationDecayPercentPerSecond = 150,
        hitDelayDuration = 0.5,
        hitFlashDuration = 0.4,
        prim_data = T{
            visible = false,
            can_focus = false,
            locked = true,
            width = 100,
            height = 100,
        },
        name_font_settings = T{
            font_alignment = gdi.Alignment.Left,
            font_family = 'Consolas',
            font_height = 12,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        distance_font_settings = T{
            font_alignment = gdi.Alignment.Left,
            font_family = 'Consolas',
            font_height = 10,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        vitals_font_settings = T{
            font_alignment = gdi.Alignment.Left,
            font_family = 'Consolas',
            font_height = 10,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        timer_font_settings = T{
            font_alignment = gdi.Alignment.Left,
            font_family = 'Consolas',
            font_height = 10,
            font_color = 0xFFFFFF00,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
    },

};

return M;
