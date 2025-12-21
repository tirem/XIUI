--[[
* XIUI Color Customization Defaults
* All color-related user settings (gradients, text colors, etc.)
]]--

local factories = require('core.settings.factories');

local M = {};

-- Create the color customization defaults table
-- This is used as gConfig.colorCustomization
function M.createColorCustomizationDefaults()
    return T{
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
            backgroundColor = 0x66000000,        -- Semi-transparent black - Alpha is the first byte: 0.4 * 255 = 102 = 0x66
            borderColor = 0x00000000,            -- transparent black - default border
            targetBorderColor = 0xFFFFFFFF,      -- white - border for main target
            subtargetBorderColor = 0xFF8080FF,   -- blue - border for subtarget
            targetNameTextColor = 0xFFFFAA00,    -- orange - enemy's target name
            -- Note: Entity name colors are in shared section
        },

        -- Party List (per-party color settings)
        partyListA = factories.createPartyColorDefaults(true),  -- Include TP colors
        partyListB = factories.createPartyColorDefaults(false), -- No TP colors
        partyListC = factories.createPartyColorDefaults(false), -- No TP colors

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
            positiveColor = 0xFF00FF00,  -- Green for positive gil/hr
            negativeColor = 0xFFFF4444,  -- Red for negative gil/hr
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

        -- Notifications
        notifications = T{
            bgColor = 0xDD1a1a1a,
            borderColor = 0xFF444444,
            partyInviteColor = 0xFF4CAF50,
            tradeInviteColor = 0xFFFF9800,
            treasurePoolColor = 0xFF2196F3,
            itemObtainedColor = 0xFFFFFFFF,
            keyItemColor = 0xFFFFEB3B,
            gilColor = 0xFFFFD700,
            textColor = 0xFFFFFFFF,
            subtitleColor = 0xFFAAAAAA,
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
        petBarAvatar = factories.createPetBarTypeColorDefaults(),
        petBarCharm = factories.createPetBarTypeColorDefaults(),
        petBarJug = factories.createPetBarTypeColorDefaults(),
        petBarAutomaton = factories.createPetBarTypeColorDefaults(),
        petBarWyvern = factories.createPetBarTypeColorDefaults(),

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
    };
end

return M;
