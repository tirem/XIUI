--[[
* XIUI User Settings Defaults
* User-configurable settings (gConfig defaults)
* Note: colorCustomization is defined separately in colors.lua
]]--

local factories = require('core.settings.factories');
local colors = require('core.settings.colors');

local M = {};

-- Create the user settings defaults table
-- This becomes gConfig after loading/merging with saved settings
function M.createUserSettingsDefaults()
    return T{
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
        showNotifications = true,

        -- Treasure Pool settings
        treasurePoolEnabled = true,           -- Show treasure pool when items in pool
        treasurePoolShowTimerBar = true,      -- Show countdown progress bar
        treasurePoolShowTimerText = true,     -- Show timer text (countdown like "4:32")
        treasurePoolShowLots = true,          -- Show winning lot info
        treasurePoolFontSize = 10,            -- Font size for text
        treasurePoolScaleX = 1.0,             -- Horizontal scale
        treasurePoolScaleY = 1.0,             -- Vertical scale
        treasurePoolBgScale = 1.0,            -- Background texture scale
        treasurePoolBorderScale = 1.0,        -- Border texture scale
        treasurePoolBackgroundOpacity = 0.87, -- Background opacity
        treasurePoolBorderOpacity = 1.0,      -- Border opacity
        treasurePoolBackgroundTheme = 'Plain', -- Background theme
        treasurePoolPreview = false,          -- Show preview with test data
        treasurePoolExpanded = false,         -- Expanded view (false = collapsed)

        -- Notifications settings
        notificationsShowPartyInvite = true,
        notificationsShowTradeInvite = true,
        notificationsShowTreasure = true,
        notificationsShowItems = true,
        notificationsShowKeyItems = true,
        notificationsShowGil = true,
        notificationsPosition = 'topright',
        notificationsDirection = 'down',
        notificationsDisplayDuration = 3.0,
        notificationsInviteMinifyTimeout = 10.0,
        notificationsScaleX = 1.0,
        notificationsScaleY = 1.0,
        notificationsPadding = 8,
        notificationsSpacing = 8,
        notificationsMaxVisible = 5,
        notificationsTitleFontSize = 14,
        notificationsSubtitleFontSize = 12,
        notificationsProgressBarScaleY = 1.0,
        notificationsHideDuringEvents = false,
        notificationsProgressBarDirection = 'left',

        -- Background/Border settings
        notificationsBackgroundTheme = 'Plain',
        notificationsBgScale = 1.0,
        notificationsBorderScale = 1.0,
        notificationsBgOpacity = 0.87,
        notificationsBorderOpacity = 1.0,

        -- Split Window Settings (allow each notification type to have its own window)
        notificationsSplitPartyInvite = false,
        notificationsSplitTradeInvite = false,
        notificationsSplitTreasurePool = false,
        notificationsSplitItemObtained = false,
        notificationsSplitKeyItemObtained = false,
        notificationsSplitGilObtained = false,

        -- Cast Cost settings (nested structure to match other modules)
        castCost = T{
            -- Display options
            showName = true,
            showMpCost = true,
            showRecast = false,
            showCooldown = true,

            -- Font sizes
            nameFontSize = 12,
            costFontSize = 12,
            timeFontSize = 10,
            recastFontSize = 10,

            -- Layout
            minWidth = 100,
            padding = 8,
            paddingY = 8,
            alignBottom = false,
            barScaleY = 1.0,

            -- Background/Border
            backgroundTheme = 'Window1',
            bgScale = 1.0,
            borderScale = 1.0,
            backgroundOpacity = 1.0,
            borderOpacity = 1.0,

            -- Window position (saved when user moves window)
            windowPosX = nil,
            windowPosY = nil,
        },

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
        enemyListDebuffOffsetX = 5,
        enemyListDebuffOffsetY = 0,
        showEnemyListDebuffs = true,
        enemyListDebuffsAnchor = 'right', -- 'left' or 'right' - which side of enemy entry to anchor debuffs
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
        -- Position options: 0=Above, 1=Below, 2=Left, 3=Right
        targetNamePosition = 0,
        targetDistancePosition = 0,
        targetHpPercentPosition = 0,
        showTargetBarBookends = false,
        showTargetBarLockOnBorder = true,
        showTargetBarCastBar = true,
        showEnemyId = false,
        showEnemyIdHex = true,
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
        showEnemyListBorders = true,
        showEnemyListBordersUseNameColor = false,
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
        -- Text position offsets (relative to default positions)
        expBarJobTextOffsetX = 0,
        expBarJobTextOffsetY = 0,
        expBarExpTextOffsetX = 0,
        expBarExpTextOffsetY = 0,
        expBarPercentTextOffsetX = 0,
        expBarPercentTextOffsetY = 0,

        gilTrackerScale = 1,
        gilTrackerFontSize = 12,
        gilTrackerRightAlign = false,
        gilTrackerIconRight = true,
        gilTrackerShowIcon = true,
        gilTrackerShowGilPerHour = true,
        gilTrackerDisplayMode = 1,  -- 1 = Session Net, 2 = Gil Per Hour
        gilTrackerTextOffsetX = 0,
        gilTrackerTextOffsetY = 0,
        gilTrackerGilPerHourOffsetX = 0,
        gilTrackerGilPerHourOffsetY = 0,

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
        partyA = factories.createPartyDefaults(),
        partyB = factories.createPartyDefaults({
            jobIconScale = 0.8,
            entrySpacing = 6,
            showTP = false,
            scaleX = 0.7,
            scaleY = 0.7,
        }),
        partyC = factories.createPartyDefaults({
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
        enablePartyListClickTarget = false,

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
            selectionBoxOffsetY = 0,
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
            selectionBoxOffsetY = 0,
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
        -- Window positions (saved when user moves window)
        petBarWindowPosX = nil,
        petBarWindowPosY = nil,
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
        -- BST Ready timer settings (base recast per charge in seconds)
        -- Default 30s (retail/LSB), Horizon uses 45s
        petBarReadyBaseRecast = 30,
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
        petBarAvatar = factories.createPetBarTypeDefaults(),
        petBarCharm = factories.createPetBarTypeDefaults({ iconsOffsetX = 94 }),
        petBarJug = factories.createPetBarTypeDefaults({ iconsOffsetX = 94 }),
        petBarAutomaton = factories.createPetBarTypeDefaults({ iconsOffsetX = 60 }),
        petBarWyvern = factories.createPetBarTypeDefaults({
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

        -- Color customization settings (populated from colors.lua)
        colorCustomization = colors.createColorCustomizationDefaults(),
    };
end

return M;
