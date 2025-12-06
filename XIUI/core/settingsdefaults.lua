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
        -- Job display options
        showJobIcon = true,
        jobIconScale = 1,
        showJob = false,
        showMainJob = true,
        showMainJobLevel = true,
        showSubJob = true,
        showSubJobLevel = true,
        showCastBars = true,
        castBarScaleY = 0.6,
        showBookends = true,
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
    };
    if overrides then
        for k, v in pairs(overrides) do
            defaults[k] = v;
        end
    end
    return defaults;
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
        hpTextColor = 0xFFFFFFFF,
        mpTextColor = 0xFFFFFFFF,
        tpEmptyTextColor = 0xFF9acce8,
        tpFullTextColor = 0xFF2fa9ff,
        tpFlashColor = 0xFF3ECE00,
        bgColor = 0xFFFFFFFF,
        borderColor = 0xFFFFFFFF,
        selectionGradient = T{ enabled = true, start = '#4da5d9', stop = '#78c0ed' },
        selectionBorderColor = 0xFF78C0ED,
        subtargetGradient = T{ enabled = true, start = '#d9a54d', stop = '#edcf78' },
        subtargetBorderColor = 0xFFfdd017,
    };
    if includeTP then
        colors.tpGradient = T{ enabled = true, start = '#3898ce', stop = '#78c4ee' };
        colors.castBarGradient = T{ enabled = true, start = '#ffaa00', stop = '#ffcc44' };
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
    enemyListDebuffOffsetX = 0,
    enemyListDebuffOffsetY = 0,
    showEnemyListDebuffs = true,
    enemyListDebuffsRightAlign = false,
    showEnemyListTargets = false,
    enableEnemyListClickTarget = true,

    playerBarScaleX = 1,
    playerBarScaleY = 1,
    playerBarFontSize = 12,
    showPlayerBarBookends = true,
    alwaysShowMpBar = true,
    playerBarTpFlashEnabled = true,
    playerBarHideDuringEvents = true,
    playerBarHpDisplayMode = 'number', -- 'number', 'percent', 'both', 'both_percent_first'
    playerBarMpDisplayMode = 'number', -- 'number', 'percent', 'both', 'both_percent_first'

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
    targetBarPercentFontSize = 12,
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
    showTargetBarBookends = true,
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
    enemyListNameFontSize = 12,
    enemyListDistanceFontSize = 12,
    enemyListPercentFontSize = 12,
    enemyListIconScale = 1,
    showEnemyDistance = false,
    showEnemyHPPText = true,
    showEnemyListBookends = true,

    expBarScaleX = 1,
    expBarScaleY = 1,
    showExpBarBookends = true,
    expBarFontSize = 12,
    expBarShowText = true,
    expBarShowPercent = true,
    expBarInlineMode = false,
    expBarLimitPointsMode = false,

    gilTrackerScale = 1,
    gilTrackerFontSize = 12,
    gilTrackerRightAlign = false,

    inventoryTrackerScale = 1,
    inventoryTrackerFontSize = 12,
    inventoryTrackerOpacity = 1.0,
    inventoryTrackerColumnCount = 5,
    inventoryTrackerRowCount = 6,
    inventoryTrackerColorThreshold1 = 15,
    inventoryTrackerColorThreshold2 = 29,
    inventoryShowCount = true,

    showSatchelTracker = false,
    satchelTrackerScale = 1,
    satchelTrackerFontSize = 12,
    satchelTrackerColumnCount = 5,
    satchelTrackerRowCount = 6,
    satchelTrackerColorThreshold1 = 15,
    satchelTrackerColorThreshold2 = 29,
    satchelShowCount = true,

    -- Mob Info settings
    showMobInfo = true,
    mobInfoShowLevel = true,
    mobInfoShowDetection = true,
    mobInfoShowLink = true,
    mobInfoShowResistances = true,
    mobInfoShowWeaknesses = true,
    mobInfoShowImmunities = true,
    mobInfoIconScale = 1.0,
    mobInfoShowNoData = false,
    mobInfoFontSize = 12,
    mobInfoSingleRow = false, -- false = stacked layout, true = single row layout

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
    showPartyListBookends = true,
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
    showCastBarBookends = true,
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

    -- Bar Settings (global progress bar configuration)
    showBookends = true,            -- Global bookend visibility (overrides individual bookend settings)
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
            hpTextColor = 0xFFFFFFFF,
            mpTextColor = 0xFFdef2db,
            tpEmptyTextColor = 0xFF9acce8,  -- TP < 1000
            tpFullTextColor = 0xFF2fa9ff,   -- TP >= 1000
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
            -- Note: Entity name colors are in shared section
        },

        -- Party List (per-party color settings)
        partyListA = createPartyColorDefaults(true),  -- Include TP colors
        partyListB = createPartyColorDefaults(false), -- No TP colors
        partyListC = createPartyColorDefaults(false), -- No TP colors

        -- Exp Bar
        expBar = T{
            barGradient = T{ enabled = true, start = '#c39040', stop = '#e9c466' },
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

        -- Cast Bar
        castBar = T{
            barGradient = T{ enabled = true, start = '#3798ce', stop = '#78c5ee' },
            spellTextColor = 0xFFFFFFFF,
            percentTextColor = 0xFFFFFFFF,
        },

        -- Mob Info
        mobInfo = T{
            levelTextColor = 0xFFFFFFFF,
            resistanceColor = 0xFFFF6666,   -- Red tint for resistances
            weaknessColor = 0xFF66FF66,     -- Green tint for weaknesses
            immunityColor = 0xFFFFFF66,     -- Yellow tint for immunities
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
            font_height = 11,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        distance_font_settings = T{
            font_alignment = gdi.Alignment.Left,
            font_family = 'Consolas',
            font_height = 9,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        },
        percent_font_settings = T{
            font_alignment = gdi.Alignment.Right,
            font_family = 'Consolas',
            font_height = 9,
            font_color = 0xFFFFFFFF,
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
};

return M;
