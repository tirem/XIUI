--[[
* MIT License
* 
* Copyright (c) 2023 tirem [github.com/tirem]
* 
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
* 
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
* 
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
]]--

addon.name      = 'HXUI';
addon.author    = 'Team HXUI';
addon.version   = '1.3.8';
addon.desc      = 'Multiple UI elements with manager';
addon.link      = 'https://github.com/tirem/HXUI'

require('common');
local settings = require('settings');
local playerBar = require('playerbar');
local targetBar = require('targetbar');
local enemyList = require('enemylist');
local expBar = require('expbar');
local gilTracker = require('giltracker');
local inventoryTracker = require('inventorytracker');
local partyList = require('partylist');
local castBar = require('castbar');
local configMenu = require('configmenu');
local colorCustom = require('colorcustom');
local debuffHandler = require('debuffhandler');
local patchNotes = require('patchNotes');
local statusHandler = require('statushandler');
local gdi = require('gdifonts.include');

-- Render flags constants
local RENDER_FLAG_VISIBLE = 0x200;  -- Entity is visible and rendered
local RENDER_FLAG_HIDDEN = 0x4000;  -- Entity is hidden (cutscene, menu, etc.)

-- =================
-- = HXUI DEV ONLY =
-- =================
-- Hot reloading of development files functionality
local _HXUI_DEV_HOT_RELOADING_ENABLED = true;
local _HXUI_DEV_HOT_RELOAD_POLL_TIME_SECONDS = 1;
local _HXUI_DEV_HOT_RELOAD_LAST_RELOAD_TIME;
local _HXUI_DEV_HOT_RELOAD_FILES = {};

function string:split(sep)
   local sep, fields = sep or ":", {}
   local pattern = string.format("([^%s]+)", sep)
   self:gsub(pattern, function(c) fields[#fields+1] = c end)
   return fields
end

function _check_hot_reload()
	local path = string.gsub(addon.path, '\\\\', '\\');

	local result = io.popen("forfiles /P " .. path .. ' /M *.lua /C "cmd /c echo @file @fdate @ftime"');

	local needsReload = false;

	for line in result:lines() do
		if #line > 0 then
			local splitLine = line:split(" ");
			local filename = splitLine[1];
			local dateModified = splitLine[2];
			local timeModified = splitLine[3];

			filename = string.gsub(filename, '"', '');

			local fileTable = {dateModified, timeModified};

			if _HXUI_DEV_HOT_RELOAD_FILES[filename] ~= nil then
				if table.concat(_HXUI_DEV_HOT_RELOAD_FILES[filename]) ~= table.concat(fileTable) then
					needsReload = true;
					print("[HXUI] Development file " .. filename .. " changed, reloading HXUI.")
				end
			end

			_HXUI_DEV_HOT_RELOAD_FILES[filename] = fileTable;
		end
	end

	result:close();

	if needsReload then
		AshitaCore:GetChatManager():QueueCommand(-1, '/addon reload hxui', channelCommand);
	end
end
-- ==================
-- = /HXUI DEV ONLY =
-- ==================

local user_settings =
T{
	patchNotesVer = -1,

	noBookendRounding = 4,
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

	statusIconTheme = 'XIView';
	jobIconTheme = 'FFXI',
	fontFamily = 'Consolas',
	fontWeight = 'Normal', -- Options: 'Normal', 'Bold'

	showPartyListWhenSolo = false,
	maxEnemyListEntries = 8,

	playerBarScaleX = 1,
	playerBarScaleY = 1,
	playerBarFontSize = 12,
	showPlayerBarBookends = true,
	alwaysShowMpBar = true,
    playerBarHideDuringEvents = true,

	targetBarScaleX = 1,
	targetBarScaleY = 1,
	targetBarNameFontSize = 12,
	targetBarDistanceFontSize = 12,
	targetBarPercentFontSize = 12,
	targetBarIconScale = 1,
	targetBarIconFontSize = 14,
	showTargetDistance = true,
	showTargetBarBookends = true,
	showEnemyId = false;
	alwaysShowHealthPercent = false,
    targetBarHideDuringEvents = true,
	splitTargetOfTarget = false,
	totBarScaleX = 1,
	totBarScaleY = 1,
	totBarFontSize = 12,

	enemyListScaleX = 1,
	enemyListScaleY = 1,
	enemyListFontSize = 12,
	enemyListIconScale = 1,
	showEnemyDistance = false,
	showEnemyHPPText = true,
	showEnemyListBookends = true,

    expBarTextScaleX = 1,
	expBarScaleX = 1,
	expBarScaleY = 1,
	showExpBarBookends = true,
	expBarFontSize = 12,
    expBarShowText = true,
    expBarShowPercent = true,
    expBarInlineMode = false,
    expBarLimitPointsMode = true,

	gilTrackerScale = 1,
	gilTrackerFontSize = 12,
    gilTrackerPosOffset = { 0, -7 },
    gilTrackerRightAlign = true,

	inventoryTrackerScale = 1,
	inventoryTrackerFontSize = 12,
    inventoryTrackerOpacity = 1.0,
    inventoryTrackerColumnCount = 5,
    inventoryTrackerRowCount = 6,
    inventoryShowCount = true,

	partyListDistanceHighlight = 0,
	partyListScaleX = 1,
	partyListScaleY = 1,
    partyListFontSize = 12,
    partyListJobIconScale = 1,
    partyListEntrySpacing = 0,
    partyListTP = true,

    partyList2ScaleX = 0.7,
    partyList2ScaleY = 0.7,
    partyList2FontSize = 12,
    partyList2JobIconScale = 0.8,
    partyList2EntrySpacing = -20,
    partyList2TP = false,

    partyList3ScaleX = 0.7,
    partyList3ScaleY = 0.7,
    partyList3FontSize = 12,
    partyList3JobIconScale = 0.8,
    partyList3EntrySpacing = -20,
    partyList3TP = false,

	partyListBuffScale = 1,
	partyListStatusTheme = 0, -- 0: HorizonXI-L, 1: HorizonXI-R 2: XIV1.0, 3: XIV, 4: Disabled
	partyListTheme = 0, 
	partyListFlashTP = false,
	showPartyListBookends = true,
    showPartyListTitle = true,
	showPartyListDistance = false,
	partyListCursor = 'GreyArrow.png',
	partyListBackgroundName = 'Window1',

    partyListHideDuringEvents = true,
    partyListExpandHeight = false,
    partyListAlignBottom = false,
    partyListMinRows = 1,
    partyListBgScale = 1.8,
    partyListBgColor = { 255, 255, 255, 255 },
    partyListBorderColor = { 255, 255, 255, 255 },
    partyListPreview = true,
    partyListAlliance = true,

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

	healthBarFlashEnabled = true,

	-- Color customization settings
	colorCustomization = T{
		-- Player Bar
		playerBar = T{
			hpGradient = T{
				enabled = true,
				low = T{ start = '#ec3232', stop = '#f16161' },      -- 0-25%
				medLow = T{ start = '#ee9c06', stop = '#ecb44e' },   -- 25-50%
				medHigh = T{ start = '#ffff0c', stop = '#ffff97' },  -- 50-75%
				high = T{ start = '#e26c6c', stop = '#fa9c9c' },     -- 75-100%
			},
			mpGradient = T{ enabled = true, start = '#9abb5a', stop = '#bfe07d' },
			tpGradient = T{ enabled = true, start = '#3898ce', stop = '#78c4ee' },
			hpTextColor = 0xFFFFFFFF,
			mpTextColor = 0xFFdef2db,
			tpEmptyTextColor = 0xFF9acce8,  -- TP < 1000
			tpFullTextColor = 0xFF2fa9ff,   -- TP >= 1000
		},

		-- Target Bar
		targetBar = T{
			hpGradient = T{ enabled = true, start = '#e26c6c', stop = '#fb9494' },
			-- Target name colors by entity type
			playerPartyTextColor = 0xFF00FFFF,     -- cyan - party/alliance members
			playerOtherTextColor = 0xFFFFFFFF,     -- white - other players
			npcTextColor = 0xFF66FF66,             -- green - NPCs
			mobUnclaimedTextColor = 0xFFFFFF66,    -- yellow - unclaimed mobs
			mobPartyClaimedTextColor = 0xFFFF6666, -- red - mobs claimed by party
			mobOtherClaimedTextColor = 0xFFFF66FF, -- magenta - mobs claimed by others
			distanceTextColor = 0xFFFFFFFF,
			-- Note: HP percent text color is set dynamically based on HP amount
		},

		-- Target of Target Bar
		totBar = T{
			hpGradient = T{ enabled = true, start = '#e16c6c', stop = '#fb9494' },
			nameTextColor = 0xFFFFFFFF,
		},

		-- Enemy List
		enemyList = T{
			hpGradient = T{ enabled = true, start = '#e16c6c', stop = '#fb9494' },
		},

		-- Party List
		partyList = T{
			hpGradient = T{
				enabled = true,
				low = T{ start = '#ec3232', stop = '#f16161' },
				medLow = T{ start = '#ee9c06', stop = '#ecb44e' },
				medHigh = T{ start = '#ffff0c', stop = '#ffff97' },
				high = T{ start = '#e26c6c', stop = '#fa9c9c' },
			},
			mpGradient = T{ enabled = true, start = '#9abb5a', stop = '#bfe07d' },
			tpGradient = T{ enabled = true, start = '#3898ce', stop = '#78c4ee' },
			nameTextColor = 0xFFFFFFFF,
			hpTextColor = 0xFFFFFFFF,
			mpTextColor = 0xFFFFFFFF,
			tpEmptyTextColor = 0xFF9acce8,  -- TP < 1000
			tpFullTextColor = 0xFF2fa9ff,   -- TP >= 1000
		},

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
			usedSlotColor = T{ r = 0.37, g = 0.7, b = 0.88, a = 1 },
		},

		-- Cast Bar
		castBar = T{
			barGradient = T{ enabled = true, start = '#3798ce', stop = '#78c5ee' },
			spellTextColor = 0xFFFFFFFF,
			percentTextColor = 0xFFFFFFFF,
		},

		-- Global/Shared
		shared = T{
			backgroundGradient = T{ enabled = true, start = '#01122b', stop = '#061c39' },
		},
	},
};

local user_settings_container =
T{
	userSettings = user_settings;
};

local default_settings =
T{
	-- global settings
	currentPatchVer = 2,
	tpEmptyColor = 0xFF9acce8,
	tpFullColor = 0xFF2fa9ff,
	mpColor = 0xFFdef2db,

	-- settings for the targetbar
	targetBarSettings =
	T{
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
		topTextYOffset = 0,
		topTextXOffset = 5,
		bottomTextYOffset = -3,
		bottomTextXOffset = 15,
		name_font_settings =
		T{
			font_alignment = gdi.Alignment.Left,
			font_family = 'Consolas',
			font_height = 13,
			font_color = 0xFFFFFFFF,
			font_flags = gdi.FontFlags.None,
			outline_color = 0xFF000000,
			outline_width = 2,
		};
		totName_font_settings =
		T{
			font_alignment = gdi.Alignment.Left,
			font_family = 'Consolas',
			font_height = 12,
			font_color = 0xFFFFFFFF,
			font_flags = gdi.FontFlags.None,
			outline_color = 0xFF000000,
			outline_width = 2,
		};
		distance_font_settings =
		T{
			font_alignment = gdi.Alignment.Right,
			font_family = 'Consolas',
			font_height = 11,
			font_color = 0xFFFFFFFF,
			font_flags = gdi.FontFlags.None,
			outline_color = 0xFF000000,
			outline_width = 2,
		};
		percent_font_settings =
		T{
			font_alignment = gdi.Alignment.Right,
			font_family = 'Consolas',
			font_height = 11,
			font_color = 0xFFFFFFFF,
			font_flags = gdi.FontFlags.None,
			outline_color = 0xFF000000,
			outline_width = 2,
		};
	};

	-- settings for the playerbar
	playerBarSettings =
	T{
		hitInterpolationMaxTime = 0.5,
		hitDelayLength = 0.5,
		barWidth = 500,
		barSpacing = 10,
		barHeight = 20,
		textYOffset = -3,
		font_settings =
		T{
			font_alignment = gdi.Alignment.Center,
			font_family = 'Consolas',
			font_height = 15,
			font_color = 0xFFFFFFFF,
			font_flags = gdi.FontFlags.None,
			outline_color = 0xFF000000,
			outline_width = 2,
		};
	};

	-- settings for enemy list
	enemyListSettings =
	T{
		barWidth = 125;
		barHeight = 10;
		textScale = 1;
		entrySpacing = 1;
		bgPadding = 7;
		bgTopPadding = -3;
		maxIcons = 5;
		iconSize = 18;
		debuffOffsetX = -10;
		debuffOffsetY = 0;
		name_font_settings =
		T{
			font_alignment = gdi.Alignment.Left,
			font_family = 'Consolas',
			font_height = 11,
			font_color = 0xFFFFFFFF,
			font_flags = gdi.FontFlags.None,
			outline_color = 0xFF000000,
			outline_width = 2,
		};
		info_font_settings =
		T{
			font_alignment = gdi.Alignment.Left,
			font_family = 'Consolas',
			font_height = 9,
			font_color = 0xFFFFFFFF,
			font_flags = gdi.FontFlags.None,
			outline_color = 0xFF000000,
			outline_width = 2,
		};
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
		};
	};

	-- settings for the exp bar
	expBarSettings =
	T{
		barWidth = 550;
        textWidth = 550;
		barHeight = 12;
		textOffsetY = 5;
		percentOffsetX = -5;
		job_font_settings =
		T{
			font_alignment = gdi.Alignment.Left,
			font_family = 'Consolas',
			font_height = 11,
			font_color = 0xFFFFFFFF,
			font_flags = gdi.FontFlags.None,
			outline_color = 0xFF000000,
			outline_width = 2,
		};
		exp_font_settings =
		T{
			font_alignment = gdi.Alignment.Right,
			font_family = 'Consolas',
			font_height = 11,
			font_color = 0xFFFFFFFF,
			font_flags = gdi.FontFlags.None,
			outline_color = 0xFF000000,
			outline_width = 2,
		};
		percent_font_settings =
		T{
			font_alignment = gdi.Alignment.Right,
			font_family = 'Consolas',
			font_height = 8,
			font_color = 0xFFFFFF00,
			font_flags = gdi.FontFlags.None,
			outline_color = 0xFF000000,
			outline_width = 2,
		};
	};

	-- settings for gil tracker
	gilTrackerSettings = 
	T{
		iconScale = 30;
		offsetX = -5;
		offsetY = -7;
		font_settings =
		T{
			font_alignment = gdi.Alignment.Right,
			font_family = 'Consolas',
			font_height = 13,
			font_color = 0xFFFFFFFF,
			font_flags = gdi.FontFlags.None,
			outline_color = 0xFF000000,
			outline_width = 2,
		};
	};

	inventoryTrackerSettings = 
	T{
		columnCount = 5;
		rowCount = 6;
		dotRadius = 5;
		dotSpacing = 1;
		groupSpacing = 8;
		textOffsetY = -3;
		font_settings =
		T{
			font_alignment = gdi.Alignment.Right,
			font_family = 'Consolas',
			font_height = 13,
			font_color = 0xFFFFFFFF,
			font_flags = gdi.FontFlags.None,
			outline_color = 0xFF000000,
			outline_width = 2,
		};
	};

	partyListSettings = 
	T{
		hpBarWidth = 150,
		tpBarWidth = 100,
		mpBarWidth = 100,
		barHeight = 20,
		barSpacing = 8,

		nameTextOffsetX = 1,
		nameTextOffsetY = 0,
		hpTextOffsetX = -2,
		hpTextOffsetY = -3,
		mpTextOffsetX = -2,
		mpTextOffsetY = -3,
		tpTextOffsetX = -2,
		tpTextOffsetY = -3,

		borderSize = 21,
        bgPadding = 5,
        bgOffset = 1,

		cursorPaddingX1 = 5,
		cursorPaddingX2 = 5,
		cursorPaddingY1 = 4,
		cursorPaddingY2 = 4,
		dotRadius = 3,

		arrowSize = 1;

		subtargetArrowTint = 0xFFfdd017,

		iconSize = 22,
		maxIconColumns = 6,
		buffOffset = 10,
		xivBuffOffsetY = 1,
		entrySpacing = 8,
        expandHeight = false,
        alignBottom = false,
        minRows = 1,

		hp_font_settings =
		T{
			font_alignment = gdi.Alignment.Right,
			font_family = 'Consolas',
			font_height = 13,
			font_color = 0xFFFFFFFF,
			font_flags = gdi.FontFlags.None,
			outline_color = 0xFF000000,
			outline_width = 2,
		};
		mp_font_settings =
		T{
			font_alignment = gdi.Alignment.Right,
			font_family = 'Consolas',
			font_height = 13,
			font_color = 0xFFFFFFFF,
			font_flags = gdi.FontFlags.None,
			outline_color = 0xFF000000,
			outline_width = 2,
		};
		tp_font_settings =
		T{
			font_alignment = gdi.Alignment.Right,
			font_family = 'Consolas',
			font_height = 13,
			font_color = 0xFFFFFFFF,
			font_flags = gdi.FontFlags.None,
			outline_color = 0xFF000000,
			outline_width = 2,
		};
		name_font_settings =
		T{
			font_alignment = gdi.Alignment.Left,
			font_family = 'Consolas',
			font_height = 13,
			font_color = 0xFFFFFFFF,
			font_flags = gdi.FontFlags.None,
			outline_color = 0xFF000000,
			outline_width = 2,
		};
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
		};
	};

	castBarSettings =
	T{
		barWidth = 500,
		barHeight = 20,
		spellOffsetY = 2,
		percentOffsetY = 2,
		percentOffsetX = -10,
		spell_font_settings =
		T{
            font_alignment = gdi.Alignment.Left,
			font_family = 'Consolas',
			font_height = 15,
			font_color = 0xFFFFFFFF,
			font_flags = gdi.FontFlags.None,
			outline_color = 0xFF000000,
            outline_width = 2,
		};
		percent_font_settings =
		T{
            font_alignment = gdi.Alignment.Right,
			font_family = 'Consolas',
			font_height = 15,
			font_color = 0xFFFFFFFF,
			font_flags = gdi.FontFlags.None,
			outline_color = 0xFF000000,
            outline_width = 2,
		};
	};
};

gAdjustedSettings = deep_copy_table(default_settings);
defaultUserSettings = deep_copy_table(user_settings);

local config = settings.load(user_settings_container);
gConfig = config.userSettings;

showConfig = { false };

function ResetSettings()
	local patchNotesVer = gConfig.patchNotesVer;
	gConfig = deep_copy_table(defaultUserSettings);
	gConfig.patchNotesVer = patchNotesVer;
	UpdateSettings();
end

function CheckVisibility()
	if (gConfig.showPlayerBar == false) then
		playerBar.SetHidden(true);
	end
	if (gConfig.showExpBar == false) then
		expBar.SetHidden(true);
	end
	if (gConfig.showGilTracker == false) then
		gilTracker.SetHidden(true);
	end
	if (gConfig.showInventoryTracker == false) then
		inventoryTracker.SetHidden(true);
	end
	if (gConfig.showPartyList == false) then
		partyList.SetHidden(true);
	end
	if (gConfig.showCastBar == false) then
		castBar.SetHidden(true);
	end
	if (gConfig.showTargetBar == false) then
		targetBar.SetHidden(true);
	end
end

local function ForceHide()

	playerBar.SetHidden(true);
	targetBar.SetHidden(true);
	expBar.SetHidden(true);
	gilTracker.SetHidden(true);
	inventoryTracker.SetHidden(true);
	partyList.SetHidden(true);
	castBar.SetHidden(true);
end

local function UpdateFonts()
	playerBar.UpdateFonts(gAdjustedSettings.playerBarSettings);
	targetBar.UpdateFonts(gAdjustedSettings.targetBarSettings);
	expBar.UpdateFonts(gAdjustedSettings.expBarSettings);
	gilTracker.UpdateFonts(gAdjustedSettings.gilTrackerSettings);
	inventoryTracker.UpdateFonts(gAdjustedSettings.inventoryTrackerSettings);
	partyList.UpdateFonts(gAdjustedSettings.partyListSettings);
	castBar.UpdateFonts(gAdjustedSettings.castBarSettings);
	enemyList.UpdateFonts(gAdjustedSettings.enemyListSettings);
end

function UpdateUserSettings()
    local ds = default_settings;
	local us = gConfig;

	-- Apply global font family and weight to all font settings
	local fontWeightFlags = GetFontWeightFlags(us.fontWeight);

	gAdjustedSettings.targetBarSettings.name_font_settings.font_family = us.fontFamily;
	gAdjustedSettings.targetBarSettings.name_font_settings.font_flags = fontWeightFlags;
	gAdjustedSettings.targetBarSettings.totName_font_settings.font_family = us.fontFamily;
	gAdjustedSettings.targetBarSettings.totName_font_settings.font_flags = fontWeightFlags;
	gAdjustedSettings.targetBarSettings.distance_font_settings.font_family = us.fontFamily;
	gAdjustedSettings.targetBarSettings.distance_font_settings.font_flags = fontWeightFlags;
	gAdjustedSettings.targetBarSettings.percent_font_settings.font_family = us.fontFamily;
	gAdjustedSettings.targetBarSettings.percent_font_settings.font_flags = fontWeightFlags;

	gAdjustedSettings.playerBarSettings.font_settings.font_family = us.fontFamily;
	gAdjustedSettings.playerBarSettings.font_settings.font_flags = fontWeightFlags;

	gAdjustedSettings.expBarSettings.job_font_settings.font_family = us.fontFamily;
	gAdjustedSettings.expBarSettings.job_font_settings.font_flags = fontWeightFlags;
	gAdjustedSettings.expBarSettings.exp_font_settings.font_family = us.fontFamily;
	gAdjustedSettings.expBarSettings.exp_font_settings.font_flags = fontWeightFlags;
	gAdjustedSettings.expBarSettings.percent_font_settings.font_family = us.fontFamily;
	gAdjustedSettings.expBarSettings.percent_font_settings.font_flags = fontWeightFlags;

	gAdjustedSettings.gilTrackerSettings.font_settings.font_family = us.fontFamily;
	gAdjustedSettings.gilTrackerSettings.font_settings.font_flags = fontWeightFlags;

	gAdjustedSettings.inventoryTrackerSettings.font_settings.font_family = us.fontFamily;
	gAdjustedSettings.inventoryTrackerSettings.font_settings.font_flags = fontWeightFlags;

	gAdjustedSettings.partyListSettings.hp_font_settings.font_family = us.fontFamily;
	gAdjustedSettings.partyListSettings.hp_font_settings.font_flags = fontWeightFlags;
	gAdjustedSettings.partyListSettings.mp_font_settings.font_family = us.fontFamily;
	gAdjustedSettings.partyListSettings.mp_font_settings.font_flags = fontWeightFlags;
	gAdjustedSettings.partyListSettings.tp_font_settings.font_family = us.fontFamily;
	gAdjustedSettings.partyListSettings.tp_font_settings.font_flags = fontWeightFlags;
	gAdjustedSettings.partyListSettings.name_font_settings.font_family = us.fontFamily;
	gAdjustedSettings.partyListSettings.name_font_settings.font_flags = fontWeightFlags;

	gAdjustedSettings.castBarSettings.spell_font_settings.font_family = us.fontFamily;
	gAdjustedSettings.castBarSettings.spell_font_settings.font_flags = fontWeightFlags;
	gAdjustedSettings.castBarSettings.percent_font_settings.font_family = us.fontFamily;
	gAdjustedSettings.castBarSettings.percent_font_settings.font_flags = fontWeightFlags;

	gAdjustedSettings.enemyListSettings.name_font_settings.font_family = us.fontFamily;
	gAdjustedSettings.enemyListSettings.name_font_settings.font_flags = fontWeightFlags;
	gAdjustedSettings.enemyListSettings.info_font_settings.font_family = us.fontFamily;
	gAdjustedSettings.enemyListSettings.info_font_settings.font_flags = fontWeightFlags;

	-- Target Bar
	gAdjustedSettings.targetBarSettings.barWidth = ds.targetBarSettings.barWidth * us.targetBarScaleX;
	gAdjustedSettings.targetBarSettings.barHeight = ds.targetBarSettings.barHeight * us.targetBarScaleY;
	gAdjustedSettings.targetBarSettings.totBarHeight = ds.targetBarSettings.totBarHeight * us.targetBarScaleY;
	gAdjustedSettings.targetBarSettings.name_font_settings.font_height = math.max(us.targetBarNameFontSize, 6);
	-- Note: name_font_settings.color is set dynamically by GetColorOfTarget() based on entity type
    gAdjustedSettings.targetBarSettings.totName_font_settings.font_height = math.max(us.targetBarNameFontSize, 6);
	gAdjustedSettings.targetBarSettings.distance_font_settings.font_height = math.max(us.targetBarDistanceFontSize, 6);
    gAdjustedSettings.targetBarSettings.percent_font_settings.font_height = math.max(us.targetBarPercentFontSize, 6);
	-- Note: percent_font_settings.color is set dynamically in targetbar.DrawWindow based on HP amount
	gAdjustedSettings.targetBarSettings.iconSize = ds.targetBarSettings.iconSize * us.targetBarIconScale;
	gAdjustedSettings.targetBarSettings.arrowSize = ds.targetBarSettings.arrowSize * us.targetBarScaleY;

	-- Target of Target Bar (separate scaling when split is enabled)
	gAdjustedSettings.targetBarSettings.totBarWidth = (ds.targetBarSettings.barWidth / 3) * us.totBarScaleX;
	gAdjustedSettings.targetBarSettings.totBarHeightSplit = ds.targetBarSettings.totBarHeight * us.totBarScaleY;
	gAdjustedSettings.targetBarSettings.totName_font_settings_split = {
		visible = ds.targetBarSettings.totName_font_settings.visible,
		locked = ds.targetBarSettings.totName_font_settings.locked,
		font_family = us.fontFamily,
		font_height = math.max(us.totBarFontSize, 6),
		color = us.colorCustomization.totBar.nameTextColor,
		bold = ds.targetBarSettings.totName_font_settings.bold,
		color_outline = ds.targetBarSettings.totName_font_settings.color_outline,
		draw_flags = ds.targetBarSettings.totName_font_settings.draw_flags,
		background = ds.targetBarSettings.totName_font_settings.background,
		right_justified = ds.targetBarSettings.totName_font_settings.right_justified,
	};

	-- Party List
    gAdjustedSettings.partyListSettings.iconSize = ds.partyListSettings.iconSize * us.partyListBuffScale;
    gAdjustedSettings.partyListSettings.expandHeight = us.partyListExpandHeight;
    gAdjustedSettings.partyListSettings.alignBottom = us.partyListAlignBottom;
    gAdjustedSettings.partyListSettings.minRows = us.partyListMinRows;

	-- Apply font sizes for each party (stored as arrays indexed by party)
	gAdjustedSettings.partyListSettings.fontSizes = {
		us.partyListFontSize,   -- Party 1
		us.partyList2FontSize,  -- Party 2
		us.partyList3FontSize,  -- Party 3
	};

	gAdjustedSettings.partyListSettings.entrySpacing = {
        ds.partyListSettings.entrySpacing + us.partyListEntrySpacing,
        ds.partyListSettings.entrySpacing + us.partyList2EntrySpacing,
        ds.partyListSettings.entrySpacing + us.partyList3EntrySpacing,
    };
	-- Note: All party list text colors are set dynamically in partylist.DrawWindow every frame

	-- Player Bar
	gAdjustedSettings.playerBarSettings.barWidth = ds.playerBarSettings.barWidth * us.playerBarScaleX;
	gAdjustedSettings.playerBarSettings.barSpacing = ds.playerBarSettings.barSpacing * us.playerBarScaleX;
	gAdjustedSettings.playerBarSettings.barHeight = ds.playerBarSettings.barHeight * us.playerBarScaleY;
	gAdjustedSettings.playerBarSettings.font_settings.font_height = math.max(us.playerBarFontSize, 6);
	-- Note: HP, MP, TP text colors are set dynamically in playerbar.DrawWindow

	-- Exp Bar
    gAdjustedSettings.expBarSettings.textWidth = ds.expBarSettings.textWidth * us.expBarTextScaleX;
	gAdjustedSettings.expBarSettings.barWidth = ds.expBarSettings.barWidth * us.expBarScaleX;
	gAdjustedSettings.expBarSettings.barHeight = ds.expBarSettings.barHeight * us.expBarScaleY;
	gAdjustedSettings.expBarSettings.job_font_settings.font_height = math.max(us.expBarFontSize, 6);
	gAdjustedSettings.expBarSettings.exp_font_settings.font_height = math.max(us.expBarFontSize, 6);
	gAdjustedSettings.expBarSettings.percent_font_settings.font_height = math.max(us.expBarFontSize, 6);

	-- Gil Tracker
	gAdjustedSettings.gilTrackerSettings.iconScale = ds.gilTrackerSettings.iconScale * us.gilTrackerScale;
	gAdjustedSettings.gilTrackerSettings.font_settings.font_height = math.max(us.gilTrackerFontSize, 6);
    gAdjustedSettings.gilTrackerSettings.font_settings.right_justified = us.gilTrackerRightAlign;
    if (us.gilTrackerRightAlign) then
        gAdjustedSettings.gilTrackerSettings.offsetX = ds.gilTrackerSettings.offsetX + us.gilTrackerPosOffset[1];
    else
        gAdjustedSettings.gilTrackerSettings.offsetX = (ds.gilTrackerSettings.offsetX + us.gilTrackerPosOffset[1]) * -1;
    end
    gAdjustedSettings.gilTrackerSettings.offsetY = us.gilTrackerPosOffset[2];
	
	-- Inventory Tracker
	gAdjustedSettings.inventoryTrackerSettings.dotRadius = ds.inventoryTrackerSettings.dotRadius * us.inventoryTrackerScale;
	gAdjustedSettings.inventoryTrackerSettings.dotSpacing = ds.inventoryTrackerSettings.dotSpacing * us.inventoryTrackerScale;
	gAdjustedSettings.inventoryTrackerSettings.groupSpacing = ds.inventoryTrackerSettings.groupSpacing * us.inventoryTrackerScale;
	gAdjustedSettings.inventoryTrackerSettings.font_settings.font_height = math.max(us.inventoryTrackerFontSize, 6);
    gAdjustedSettings.inventoryTrackerSettings.columnCount = us.inventoryTrackerColumnCount;
    gAdjustedSettings.inventoryTrackerSettings.rowCount = us.inventoryTrackerRowCount;
    gAdjustedSettings.inventoryTrackerSettings.opacity = us.inventoryTrackerOpacity;
    gAdjustedSettings.inventoryTrackerSettings.showText = us.inventoryShowCount;

	-- Enemy List
	gAdjustedSettings.enemyListSettings.barWidth = ds.enemyListSettings.barWidth * us.enemyListScaleX;
	gAdjustedSettings.enemyListSettings.barHeight = ds.enemyListSettings.barHeight * us.enemyListScaleY;
	gAdjustedSettings.enemyListSettings.textScale = ds.enemyListSettings.textScale * us.enemyListFontSize;
	gAdjustedSettings.enemyListSettings.iconSize = ds.enemyListSettings.iconSize * us.enemyListIconScale;
	gAdjustedSettings.enemyListSettings.name_font_settings.font_height = math.max(us.enemyListFontSize, 6);
	gAdjustedSettings.enemyListSettings.info_font_settings.font_height = math.max(us.enemyListFontSize, 6);

	-- Cast Bar
	gAdjustedSettings.castBarSettings.barWidth = ds.castBarSettings.barWidth * us.castBarScaleX;
	gAdjustedSettings.castBarSettings.barHeight = ds.castBarSettings.barHeight * us.castBarScaleY;
	gAdjustedSettings.castBarSettings.spell_font_settings.font_height = math.max(us.castBarFontSize, 6);
	gAdjustedSettings.castBarSettings.spell_font_settings.font_color = us.colorCustomization.castBar.spellTextColor;
	gAdjustedSettings.castBarSettings.percent_font_settings.font_height = math.max(us.castBarFontSize, 6);
	gAdjustedSettings.castBarSettings.percent_font_settings.font_color = us.colorCustomization.castBar.percentTextColor;
end

-- Just save settings to disk (no updates)
function SaveSettingsToDisk()
    -- Ensure colorCustomization exists with defaults for existing users
    if gConfig.colorCustomization == nil then
        gConfig.colorCustomization = deep_copy_table(defaultUserSettings.colorCustomization);
    end
    settings.save();
end

-- Lightweight settings save that doesn't recreate fonts (for color changes, etc.)
function SaveSettingsOnly()
    -- Ensure colorCustomization exists with defaults for existing users
    if gConfig.colorCustomization == nil then
        gConfig.colorCustomization = deep_copy_table(defaultUserSettings.colorCustomization);
    end

    -- Save the current settings to disk
    settings.save();

    -- Update adjusted settings (scales, offsets, etc.)
    UpdateUserSettings();
end

-- Module-specific font updates (only recreate fonts for one module)
function UpdatePlayerBarFonts()
	SaveSettingsOnly();
	playerBar.UpdateFonts(gAdjustedSettings.playerBarSettings);
end

function UpdateTargetBarFonts()
	SaveSettingsOnly();
	targetBar.UpdateFonts(gAdjustedSettings.targetBarSettings);
end

function UpdatePartyListFonts()
	SaveSettingsOnly();
	partyList.UpdateFonts(gAdjustedSettings.partyListSettings);
end

function UpdateEnemyListFonts()
	SaveSettingsOnly();
	enemyList.UpdateFonts(gAdjustedSettings.enemyListSettings);
end

function UpdateExpBarFonts()
	SaveSettingsOnly();
	expBar.UpdateFonts(gAdjustedSettings.expBarSettings);
end

function UpdateGilTrackerFonts()
	SaveSettingsOnly();
	gilTracker.UpdateFonts(gAdjustedSettings.gilTrackerSettings);
end

function UpdateInventoryTrackerFonts()
	SaveSettingsOnly();
	inventoryTracker.UpdateFonts(gAdjustedSettings.inventoryTrackerSettings);
end

function UpdateCastBarFonts()
	SaveSettingsOnly();
	castBar.UpdateFonts(gAdjustedSettings.castBarSettings);
end

-- Full settings update including font recreation (for font changes, visibility, etc.)
function UpdateSettings()
    SaveSettingsOnly();
	CheckVisibility();
	UpdateFonts();
end;

settings.register('settings', 'settings_update', function (s)
    if (s ~= nil) then
        config = s;
		gConfig = config.userSettings;
		UpdateSettings();
    end
end);

-- Get if we are logged in right when the addon loads
bLoggedIn = false;
local playerIndex = AshitaCore:GetMemoryManager():GetParty():GetMemberTargetIndex(0);
if playerIndex ~= 0 then
    local entity = AshitaCore:GetMemoryManager():GetEntity();
    local flags = entity:GetRenderFlags0(playerIndex);
    if (bit.band(flags, RENDER_FLAG_VISIBLE) == RENDER_FLAG_VISIBLE) and (bit.band(flags, RENDER_FLAG_HIDDEN) == 0) then
        bLoggedIn = true;
	end
end

-- Track initialization state to prevent rendering before font objects are created
local bInitialized = false;

--Thanks to Velyn for the event system and interface hidden signatures!
local pGameMenu = ashita.memory.find('FFXiMain.dll', 0, "8B480C85C974??8B510885D274??3B05", 16, 0);
local pEventSystem = ashita.memory.find('FFXiMain.dll', 0, "A0????????84C0741AA1????????85C0741166A1????????663B05????????0F94C0C3", 0, 0);
local pInterfaceHidden = ashita.memory.find('FFXiMain.dll', 0, "8B4424046A016A0050B9????????E8????????F6D81BC040C3", 0, 0);

local function GetMenuName()
    local subPointer = ashita.memory.read_uint32(pGameMenu);
    local subValue = ashita.memory.read_uint32(subPointer);
    if (subValue == 0) then
        return '';
    end
    local menuHeader = ashita.memory.read_uint32(subValue + 4);
    local menuName = ashita.memory.read_string(menuHeader + 0x46, 16);
    return string.gsub(menuName, '\x00', '');
end

local function GetEventSystemActive()
    if (pEventSystem == 0) then
        return false;
    end
    local ptr = ashita.memory.read_uint32(pEventSystem + 1);
    if (ptr == 0) then
        return false;
    end

    return (ashita.memory.read_uint8(ptr) == 1);

end

local function GetInterfaceHidden()
    if (pEventSystem == 0) then
        return false;
    end
    local ptr = ashita.memory.read_uint32(pInterfaceHidden + 10);
    if (ptr == 0) then
        return false;
    end

    return (ashita.memory.read_uint8(ptr + 0xB4) == 1);
end

function GetHidden()

	if (gConfig.hideDuringEvents and GetEventSystemActive()) then
    	return true;
    end

	if (string.match(GetMenuName(), 'map')) then
		return true;
	end

    if (GetInterfaceHidden()) then
        return true;
    end

	if (bLoggedIn == false) then
		return true;
	end
    
    return false;
end

--[[
* event: d3d_present
* desc : Event called when the Direct3D device is presenting a scene.
--]]
ashita.events.register('d3d_present', 'present_cb', function ()
	-- Prevent rendering before initialization completes
	if not bInitialized then
		return;
	end

    local eventSystemActive = GetEventSystemActive();

	if (GetHidden() == false) then
		if (not gConfig.showPlayerBar or (gConfig.playerBarHideDuringEvents and eventSystemActive)) then
            playerBar.SetHidden(true);
        else
			playerBar.DrawWindow(gAdjustedSettings.playerBarSettings);
		end
        if (not gConfig.showTargetBar or (gConfig.targetBarHideDuringEvents and eventSystemActive)) then
            targetBar.SetHidden(true);
        else
			targetBar.DrawWindow(gAdjustedSettings.targetBarSettings);
		end
		if (gConfig.showEnemyList) then
			enemyList.DrawWindow(gAdjustedSettings.enemyListSettings);
		end
		if (gConfig.showExpBar) then
			expBar.DrawWindow(gAdjustedSettings.expBarSettings);
		end
		if (gConfig.showGilTracker) then
			gilTracker.DrawWindow(gAdjustedSettings.gilTrackerSettings);
		end
		if (gConfig.showInventoryTracker) then
			inventoryTracker.DrawWindow(gAdjustedSettings.inventoryTrackerSettings);
		end
        if (not gConfig.showPartyList or (gConfig.partyListHideDuringEvents and eventSystemActive)) then
            partyList.SetHidden(true);
        else
			partyList.DrawWindow(gAdjustedSettings.partyListSettings);
		end
		if (gConfig.showCastBar) then
			castBar.DrawWindow(gAdjustedSettings.castBarSettings);
		end

		configMenu.DrawWindow();
		colorCustom.DrawWindow();

		if (gConfig.patchNotesVer < gAdjustedSettings.currentPatchVer) then
			patchNotes.DrawWindow();
		end
	else
		ForceHide();
	end

	-- HXUI DEV ONLY
	if _HXUI_DEV_HOT_RELOADING_ENABLED then
		local currentTime = os.time();

		if not _HXUI_DEV_HOT_RELOAD_LAST_RELOAD_TIME then
			_HXUI_DEV_HOT_RELOAD_LAST_RELOAD_TIME = currentTime;
		end

		if _HXUI_DEV_HOT_RELOAD_LAST_RELOAD_TIME and currentTime - _HXUI_DEV_HOT_RELOAD_LAST_RELOAD_TIME > _HXUI_DEV_HOT_RELOAD_POLL_TIME_SECONDS then
			_check_hot_reload();

			_HXUI_DEV_HOT_RELOAD_LAST_RELOAD_TIME = currentTime;
		end
	end
end);

ashita.events.register('load', 'load_cb', function ()

	UpdateUserSettings();
    playerBar.Initialize(gAdjustedSettings.playerBarSettings);
	targetBar.Initialize(gAdjustedSettings.targetBarSettings);
	expBar.Initialize(gAdjustedSettings.expBarSettings);
	gilTracker.Initialize(gAdjustedSettings.gilTrackerSettings);
	inventoryTracker.Initialize(gAdjustedSettings.inventoryTrackerSettings);
	partyList.Initialize(gAdjustedSettings.partyListSettings);
	castBar.Initialize(gAdjustedSettings.castBarSettings);
	enemyList.Initialize(gAdjustedSettings.enemyListSettings);

	-- Mark initialization as complete to allow rendering
	bInitialized = true;
end);

ashita.events.register('unload', 'unload_cb', function ()
    -- Unregister all events
    ashita.events.unregister('d3d_present', 'present_cb');
    ashita.events.unregister('packet_in', 'packet_in_cb');
    ashita.events.unregister('command', 'command_cb');

    -- Cleanup module caches
    statusHandler.clear_cache();

    -- Cleanup debuff font cache if function exists
    if ClearDebuffFontCache then
        ClearDebuffFontCache();
    end

    -- Cleanup module font objects and primitives
    if playerBar and playerBar.Cleanup then
        playerBar.Cleanup();
    end
    if targetBar and targetBar.Cleanup then
        targetBar.Cleanup();
    end
    if partyList and partyList.Cleanup then
        partyList.Cleanup();
    end
    if enemyList and enemyList.Cleanup then
        enemyList.Cleanup();
    end
    if castBar and castBar.Cleanup then
        castBar.Cleanup();
    end
    if expBar and expBar.Cleanup then
        expBar.Cleanup();
    end
    if gilTracker and gilTracker.Cleanup then
        gilTracker.Cleanup();
    end
    if inventoryTracker and inventoryTracker.Cleanup then
        inventoryTracker.Cleanup();
    end

    -- Cleanup GDI interface last
    gdi:destroy_interface();
end);

ashita.events.register('command', 'command_cb', function (e)
   
	-- Parse the command arguments
	local command_args = e.command:lower():args()
    if table.contains({'/horizonui', '/hui', '/hxui', '/horizonxiui'}, command_args[1]) then
		e.blocked = true;

        -- Toggle the config menu
        if (#command_args == 1) then
            showConfig[1] = not showConfig[1];
            return;
        end

        -- Toggle the party list
        if (#command_args == 2 and command_args[2]:any('partylist')) then
            gConfig.showPartyList = not gConfig.showPartyList;
            CheckVisibility();
            return;
        end

        -- Toggle the color customization window
        if (#command_args == 2 and command_args[2]:any('colors', 'colour', 'color')) then
            gShowColorCustom[1] = not gShowColorCustom[1];
            return;
        end
	end

end);

-- Track our packets
ashita.events.register('packet_in', 'packet_in_cb', function (e)
    expBar.HandlePacket(e)

	if (e.id == 0x0028) then
		local actionPacket = ParseActionPacket(e);
		
		if actionPacket then
			if (gConfig.showEnemyList) then
				enemyList.HandleActionPacket(actionPacket);
			end
	
			if (gConfig.showCastBar) then
				castBar.HandleActionPacket(actionPacket);
			end

			debuffHandler.HandleActionPacket(actionPacket);
		end
	elseif (e.id == 0x00E) then
		local mobUpdatePacket = ParseMobUpdatePacket(e);
		if (gConfig.showEnemyList) then
			enemyList.HandleMobUpdatePacket(mobUpdatePacket);
		end
	elseif (e.id == 0x00A) then
		enemyList.HandleZonePacket(e);
		partyList.HandleZonePacket(e);
		debuffHandler.HandleZonePacket(e);
		MarkPartyCacheDirty(); -- Invalidate party cache on zone
		bLoggedIn = true;
	elseif (e.id == 0x0029) then
		local messagePacket = ParseMessagePacket(e.data);
		if (messagePacket) then
			debuffHandler.HandleMessagePacket(messagePacket);
		end
	elseif (e.id == 0x00B) then
		bLoggedIn = false;
	elseif (e.id == 0x076) then
		statusHandler.ReadPartyBuffsFromPacket(e);
	elseif (e.id == 0x0DD) then
		-- Party member update packet - invalidate party cache
		MarkPartyCacheDirty();
	end
end);
