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
addon.author    = 'Team HXUI (Tirem, Shuu, colorglut, RheaCloud)';
addon.version   = '1.1.1';
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
local debuffHandler = require('debuffhandler');
local patchNotes = require('patchNotes');
local statusHandler = require('statushandler');
local gdi = require('gdifonts.include');

-- =================
-- = HXUI DEV ONLY =
-- =================
-- Hot reloading of development files functionality
local _HXUI_DEV_HOT_RELOADING_ENABLED = false;
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

	showPartyListWhenSolo = false,
	maxEnemyListEntries = 8,

	playerBarScaleX = 1,
	playerBarScaleY = 1,
	playerBarFontOffset = 0,
	showPlayerBarBookends = true,
	alwaysShowMpBar = true,
    playerBarHideDuringEvents = true,

	targetBarScaleX = 1,
	targetBarScaleY = 1,
	targetBarFontOffset = 0,
	targetBarIconScale = 1,
	showTargetBarBookends = true,
	showEnemyId = false;
	alwaysShowHealthPercent = false,
    targetBarHideDuringEvents = true,

	enemyListScaleX = 1,
	enemyListScaleY = 1,
	enemyListFontScale = 1,
	enemyListIconScale = 1,
	showEnemyListBookends = true,

    expBarTextScaleX = 1,
	expBarScaleX = 1,
	expBarScaleY = 1,
	showExpBarBookends = true,
	expBarFontOffset = 0,
    expBarShowText = true,
    expBarShowPercent = true,
    expBarInlineMode = false,
    expBarLimitPointsMode = true,

	gilTrackerScale = 1,
	gilTrackerFontOffset = 0,
    gilTrackerPosOffset = { 0, -7 },
    gilTrackerRightAlign = true,

	inventoryTrackerScale = 1,
	inventoryTrackerFontOffset = 0,
    inventoryTrackerOpacity = 1.0,
    inventoryTrackerColumnCount = 5,
    inventoryTrackerRowCount = 6,
    inventoryShowCount = true,

	partyListScaleX = 1,
	partyListScaleY = 1,
	partyListBuffScale = 1,
	partyListFontOffset = 0,
	partyListStatusTheme = 0, -- 0: HorizonXI-L, 1: HorizonXI-R 2: XIV1.0, 3: XIV, 4: Disabled
	partyListTheme = 0, 
	showPartyListBookends = true,
    showPartyListTitle = true,
	partyListCursor = 'GreyArrow.png',
	partyListBackgroundName = 'Window1',
	partyListEntrySpacing = 0,
    partyListHideDuringEvents = true,
    partyListExpandHeight = false,
    partyListAlignBottom = false,
    partyListMinRows = 1,
    partyListBgScale = 1.8,
    partyListBgColor = { 255, 255, 255, 255 },
    partyListBorderColor = { 255, 255, 255, 255 },
    partyListPreview = true,

	castBarScaleX = 1,
	castBarScaleY = 1,
	showCastBarBookends = true,
	castBarFontOffset = 0,

	healthBarFlashEnabled = true,
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
			visible = true,
			locked = true,
			font_family = 'Consolas',
			font_height = 13,
			color = 0xFFFFFFFF,
			bold = true,
			color_outline = 0xFF000000,
			draw_flags = 0x10,
			background = 
			T{
				visible = false,
			},
			right_justified = false;
		};
		totName_font_settings = 
		T{
			visible = true,
			locked = true,
			font_family = 'Consolas',
			font_height = 12,
			color = 0xFFFFFFFF,
			bold = true,
			color_outline = 0xFF000000,
			draw_flags = 0x10,
			background = 
			T{
				visible = false,
			},
			right_justified = false;
		};
		distance_font_settings = 
		T{
			visible = true,
			locked = true,
			font_family = 'Consolas',
			font_height = 11,
			color = 0xFFFFFFFF,
			bold = true,
			color_outline = 0xFF000000,
			draw_flags = 0x10,
			background = 
			T{
				visible = false,
			},
			right_justified = true;
		};
		percent_font_settings = 
		T{
			visible = true,
			locked = true,
			font_family = 'Consolas',
			font_height = 11,
			color = 0xFFFFFFFF,
			bold = true,
			italic = true;
			color_outline = 0xFF000000,
			draw_flags = 0x10,
			background = 
			T{
				visible = false,
			},
			right_justified = true;
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
			visible = true,
			locked = true,
			font_family = 'Consolas',
			font_height = 15,
			color = 0xFFFFFFFF,
			bold = true,
			color_outline = 0xFF000000,
			draw_flags = 0x10,
			background = 
			T{
				visible = false,
			},
			right_justified = true;
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
			visible = true,
			locked = true,
			font_family = 'Consolas',
			font_height = 11,
			color = 0xFFFFFFFF,
			bold = true,
			italic = false;
			color_outline = 0xFF000000,
			draw_flags = 0x10,
			background = 
			T{
				visible = false,
			},
			right_justified = false;
		};
		exp_font_settings = 
		T{
			visible = true,
			locked = true,
			font_family = 'Consolas',
			font_height = 11,
			color = 0xFFFFFFFF,
			bold = true,
			italic = false;
			color_outline = 0xFF000000,
			draw_flags = 0x10,
			background = 
			T{
				visible = false,
			},
			right_justified = true;
		};
		percent_font_settings = 
		T{
			visible = true,
			locked = true,
			font_family = 'Consolas',
			font_height = 8,
			color = 0xFFFFFF00,
			bold = false,
			italic = true;
			color_outline = 0xFF000000,
			draw_flags = 0x10,
			background = 
			T{
				visible = false,
			},
			right_justified = true;
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
			visible = true,
			locked = true,
			font_family = 'Consolas',
			font_height = 13,
			color = 0xFFFFFFFF,
			bold = true,
			italic = false;
			color_outline = 0xFF000000,
			draw_flags = 0x10,
			background = 
			T{
				visible = false,
			},
			right_justified = true;
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
			visible = true,
			locked = true,
			font_family = 'Consolas',
			font_height = 13,
			color = 0xFFFFFFFF,
			bold = true,
			italic = false;
			color_outline = 0xFF000000,
			draw_flags = 0x10,
			background = 
			T{
				visible = false,
			},
			right_justified = true;
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
			visible = true,
			locked = true,
			font_family = 'Consolas',
			font_height = 13,
			color = 0xFFFFFFFF,
			bold = true,
			italic = false;
			color_outline = 0xFF000000,
			draw_flags = 0x10,
			background = 
			T{
				visible = false,
			},
			right_justified = true;
		};
		mp_font_settings = 
		T{
			visible = true,
			locked = true,
			font_family = 'Consolas',
			font_height = 13,
			color = 0xFFFFFFFF,
			bold = true,
			italic = false;
			color_outline = 0xFF000000,
			draw_flags = 0x10,
			background = 
			T{
				visible = false,
			},
			right_justified = true;
		};
		tp_font_settings = 
		T{
			visible = true,
			locked = true,
			font_family = 'Consolas',
			font_height = 13,
			color = 0xFFFFFFFF,
			bold = true,
			italic = false;
			color_outline = 0xFF000000,
			draw_flags = 0x10,
			background = 
			T{
				visible = false,
			},
			right_justified = true;
		};
		name_font_settings = 
		T{
			visible = true,
			locked = true,
			font_family = 'Consolas',
			font_height = 13,
			color = 0xFFFFFFFF,
			bold = true,
			italic = false;
			color_outline = 0xFF000000,
			draw_flags = 0x10,
			background = 
			T{
				visible = false,
			},
			right_justified = false;
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
			font_flags = gdi.FontFlags.Italic,
			outline_color = 0xFF000000,
            outline_width = 2,
		};
		percent_font_settings =
		T{
            font_alignment = gdi.Alignment.Right,
			font_family = 'Consolas',
			font_height = 15,
			font_color = 0xFFFFFFFF,
			font_flags = gdi.FontFlags.Italic,
			outline_color = 0xFF000000,
            outline_width = 2,
		};
	};
};

gAdjustedSettings = deep_copy_table(default_settings);
local defaultUserSettings = deep_copy_table(user_settings);

local config = settings.load(user_settings_container);
gConfig = config.userSettings;

showConfig = { false };

function ResetSettings()
	local patchNotesVer = gConfig.patchNotesVer;
	gConfig = deep_copy_table(defaultUserSettings);
	gConfig.patchNotesVer = patchNotesVer;
	UpdateSettings();
end

local function CheckVisibility()
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
end

local function UpdateUserSettings()
    local ns = default_settings;
	local us = gConfig;

	-- Target Bar
	gAdjustedSettings.targetBarSettings.barWidth = ns.targetBarSettings.barWidth * us.targetBarScaleX;
	gAdjustedSettings.targetBarSettings.barHeight = ns.targetBarSettings.barHeight * us.targetBarScaleY;
	gAdjustedSettings.targetBarSettings.totBarHeight = ns.targetBarSettings.totBarHeight * us.targetBarScaleY;
	gAdjustedSettings.targetBarSettings.name_font_settings.font_height = math.max(ns.targetBarSettings.name_font_settings.font_height + us.targetBarFontOffset, 1);
    gAdjustedSettings.targetBarSettings.totName_font_settings.font_height = math.max(ns.targetBarSettings.totName_font_settings.font_height + us.targetBarFontOffset, 1);
	gAdjustedSettings.targetBarSettings.distance_font_settings.font_height = math.max(ns.targetBarSettings.distance_font_settings.font_height + us.targetBarFontOffset, 1);
    gAdjustedSettings.targetBarSettings.percent_font_settings.font_height = math.max(ns.targetBarSettings.percent_font_settings.font_height + us.targetBarFontOffset, 1);
	gAdjustedSettings.targetBarSettings.iconSize = ns.targetBarSettings.iconSize * us.targetBarIconScale;
	gAdjustedSettings.targetBarSettings.arrowSize = ns.targetBarSettings.arrowSize * us.targetBarScaleY;

	-- Party List
    gAdjustedSettings.partyListSettings.hpBarWidth = ns.partyListSettings.hpBarWidth * us.partyListScaleX;
    gAdjustedSettings.partyListSettings.barHeight = ns.partyListSettings.barHeight * us.partyListScaleY;
    gAdjustedSettings.partyListSettings.tpBarWidth = ns.partyListSettings.tpBarWidth * us.partyListScaleX;
	gAdjustedSettings.partyListSettings.mpBarWidth = ns.partyListSettings.mpBarWidth * us.partyListScaleX;
	gAdjustedSettings.partyListSettings.barSpacing = ns.partyListSettings.barSpacing * us.partyListScaleX;
    gAdjustedSettings.partyListSettings.hp_font_settings.font_height = math.max(ns.partyListSettings.hp_font_settings.font_height + us.partyListFontOffset, 1);
    gAdjustedSettings.partyListSettings.mp_font_settings.font_height = math.max(ns.partyListSettings.mp_font_settings.font_height + us.partyListFontOffset, 1);
	gAdjustedSettings.partyListSettings.tp_font_settings.font_height = math.max(ns.partyListSettings.tp_font_settings.font_height + us.partyListFontOffset, 1);
    gAdjustedSettings.partyListSettings.name_font_settings.font_height = math.max(ns.partyListSettings.name_font_settings.font_height + us.partyListFontOffset, 1);
	gAdjustedSettings.partyListSettings.iconSize = ns.partyListSettings.iconSize * us.partyListBuffScale;
	gAdjustedSettings.partyListSettings.entrySpacing = ns.partyListSettings.entrySpacing + us.partyListEntrySpacing;
    gAdjustedSettings.partyListSettings.expandHeight = us.partyListExpandHeight;
    gAdjustedSettings.partyListSettings.alignBottom = us.partyListAlignBottom;
    gAdjustedSettings.partyListSettings.minRows = us.partyListMinRows;

	-- Player Bar
	gAdjustedSettings.playerBarSettings.barWidth = ns.playerBarSettings.barWidth * us.playerBarScaleX;
	gAdjustedSettings.playerBarSettings.barSpacing = ns.playerBarSettings.barSpacing * us.playerBarScaleX;
	gAdjustedSettings.playerBarSettings.barHeight = ns.playerBarSettings.barHeight * us.playerBarScaleY;
	gAdjustedSettings.playerBarSettings.font_settings.font_height = math.max(ns.playerBarSettings.font_settings.font_height + us.playerBarFontOffset, 1);

	-- Exp Bar
    gAdjustedSettings.expBarSettings.textWidth = ns.expBarSettings.textWidth * us.expBarTextScaleX;
	gAdjustedSettings.expBarSettings.barWidth = ns.expBarSettings.barWidth * us.expBarScaleX;
	gAdjustedSettings.expBarSettings.barHeight = ns.expBarSettings.barHeight * us.expBarScaleY;
	gAdjustedSettings.expBarSettings.job_font_settings.font_height = math.max(ns.expBarSettings.job_font_settings.font_height + us.expBarFontOffset, 1);
	gAdjustedSettings.expBarSettings.exp_font_settings.font_height = math.max(ns.expBarSettings.exp_font_settings.font_height + us.expBarFontOffset, 1);
	gAdjustedSettings.expBarSettings.percent_font_settings.font_height = math.max(ns.expBarSettings.percent_font_settings.font_height + us.expBarFontOffset, 1);

	-- Gil Tracker
	gAdjustedSettings.gilTrackerSettings.iconScale = ns.gilTrackerSettings.iconScale * us.gilTrackerScale;
	gAdjustedSettings.gilTrackerSettings.font_settings.font_height = math.max(ns.gilTrackerSettings.font_settings.font_height + us.gilTrackerFontOffset, 1);
    gAdjustedSettings.gilTrackerSettings.font_settings.right_justified = us.gilTrackerRightAlign;
    if (us.gilTrackerRightAlign) then
        gAdjustedSettings.gilTrackerSettings.offsetX = ns.gilTrackerSettings.offsetX + us.gilTrackerPosOffset[1];
    else
        gAdjustedSettings.gilTrackerSettings.offsetX = (ns.gilTrackerSettings.offsetX + us.gilTrackerPosOffset[1]) * -1;
    end
    gAdjustedSettings.gilTrackerSettings.offsetY = us.gilTrackerPosOffset[2];
	
	-- Inventory Tracker
	gAdjustedSettings.inventoryTrackerSettings.dotRadius = ns.inventoryTrackerSettings.dotRadius * us.inventoryTrackerScale;
	gAdjustedSettings.inventoryTrackerSettings.dotSpacing = ns.inventoryTrackerSettings.dotSpacing * us.inventoryTrackerScale;
	gAdjustedSettings.inventoryTrackerSettings.groupSpacing = ns.inventoryTrackerSettings.groupSpacing * us.inventoryTrackerScale;
	gAdjustedSettings.inventoryTrackerSettings.font_settings.font_height = math.max(ns.inventoryTrackerSettings.font_settings.font_height + us.inventoryTrackerFontOffset, 1);
    gAdjustedSettings.inventoryTrackerSettings.columnCount = us.inventoryTrackerColumnCount;
    gAdjustedSettings.inventoryTrackerSettings.rowCount = us.inventoryTrackerRowCount;
    gAdjustedSettings.inventoryTrackerSettings.opacity = us.inventoryTrackerOpacity;
    gAdjustedSettings.inventoryTrackerSettings.showText = us.inventoryShowCount;

	-- Enemy List
	gAdjustedSettings.enemyListSettings.barWidth = ns.enemyListSettings.barWidth * us.enemyListScaleX;
	gAdjustedSettings.enemyListSettings.barHeight = ns.enemyListSettings.barHeight * us.enemyListScaleY;
	gAdjustedSettings.enemyListSettings.textScale = ns.enemyListSettings.textScale * us.enemyListFontScale;
	gAdjustedSettings.enemyListSettings.iconSize = ns.enemyListSettings.iconSize * us.enemyListIconScale;

	-- Cast Bar
	gAdjustedSettings.castBarSettings.barWidth = ns.castBarSettings.barWidth * us.castBarScaleX;
	gAdjustedSettings.castBarSettings.barHeight = ns.castBarSettings.barHeight * us.castBarScaleY;
	gAdjustedSettings.castBarSettings.spell_font_settings.font_height = math.max(ns.castBarSettings.spell_font_settings.font_height + us.castBarFontOffset, 1);
	gAdjustedSettings.castBarSettings.percent_font_settings.font_height = math.max(ns.castBarSettings.percent_font_settings.font_height + us.castBarFontOffset, 1);
end

function UpdateSettings()
    -- Save the current settings..
    settings.save();

	UpdateUserSettings();
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
    if (bit.band(flags, 0x200) == 0x200) and (bit.band(flags, 0x4000) == 0) then
        bLoggedIn = true;
	end
end

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
end);

ashita.events.register('unload', 'unload_cb', function ()
    gdi:destroy_interface()
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
	end
end);
