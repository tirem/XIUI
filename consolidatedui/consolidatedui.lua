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

addon.name      = 'consolidatedui';
addon.author    = 'Tirem';
addon.version   = '0.3';
addon.desc      = 'Multiple UI elements with manager';
addon.link      = 'https://github.com/tirem/ConsolidatedUI'

require('common');
local imgui = require('imgui');
local settings = require('settings');
local playerBar = require('playerbar');
local targetBar = require('targetbar');
local enemyList = require('enemylist');
local expBar = require('expbar');
local gilTracker = require('giltracker');
local inventoryTracker = require('inventorytracker');
local partyList = require('partylist');

local user_settings = 
T{
	showPlayerBar = true,
	showTargetBar = true,
	showEnemyList = true,
	showExpBar = true,
	showGilTracker = true,
	showInventoryTracker = true,
	showPartyList = true,

	showPartyListWhenSolo = false;
	maxEnemyListEntries = 8;
	showTargetBarPercent = true;

	playerBarScaleX = 1,
	playerBarScaleY = 1,
	playerBarFontOffset = 0,

	targetBarScaleX = 1,
	targetBarScaleY = 1,
	targetBarFontScale = 1,

	enemyListScaleX = 1,
	enemyListScaleY = 1,
	enemyListFontScale = 1,

	expBarScaleX = 1,
	expBarScaleY = 1,
	expBarFontOffset = 0,

	gilTrackerScale = 1,
	gilTrackerFontOffset = 0,

	inventoryTrackerScale= 1,
	inventoryTrackerFontOffset = 0,

	partyListScaleX = 1,
	partyListScaleY = 1,
	partyListFontOffset = 0,
};

local user_settings_container = 
T{
	userSettings = user_settings;
};

local default_settings =
T{
	-- settings for the targetbar
	targetBarSettings =
	T{
		barWidth = 500,
		barHeight = 18,
		totBarHeight = 14,
		totBarOffset = 1,
		textScale = 1.2,
		cornerOffset = 5,
		nameXOffset = 12,
		nameYOffset = 9,
	};

	-- settings for the playerbar
	playerBarSettings =
	T{
		hitAnimSpeed = 2,
		hitDelayLength = .5,
		barWidth = 500,
		barSpacing = 10,
		barHeight = 20,
		textYOffset = -4,
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
	};

	-- settings for the exp bar
	expBarSettings =
	T{
		barWidth = 550;
		barHeight = 10;
		jobOffsetY = 0;
		expOffsetY = 0;
		percentOffsetY = 2;
		percentOffsetX = -10;
		job_font_settings = 
		T{
			visible = true,
			locked = true,
			font_family = 'Consolas',
			font_height = 11,
			color = 0xFFFFFFFF,
			bold = false,
			italic = true;
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
		dotSpacing = 2;
		groupSpacing = 10;
		textOffsetY = -10;
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
		hpBarWidth = 225,
		hpBarHeight = 20,
		mpBarHeight = 15,
		tpBarWidth = 50,
		tpBarHeight = 5,
		entrySpacing = 3,
		hpTextOffsetX = -10,
		hpTextOffsetY = -3,
		mpTextOffsetY = -3,
		nameSpacing = 75;
		tpBarOffsetY = 8;
		hpBarOffsetY = 1;
		backgroundPaddingX1 = 20,
		backgroundPaddingX2 = 150,
		backgroundPaddingY1 = 15,
		backgroundPaddingY2 = 10,
		cursorPaddingX1 = 5,
		cursorPaddingX2 = 5,
		cursorPaddingY1 = 2,
		cursorPaddingY2 = 10,
		leaderDotRadius = 3,
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
			font_height = 12,
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
			draw_flags = bit.bor(0x10, 0x2),
			background = 
			T{
				visible = false,
			},
			right_justified = false;
		};
		primData = {
			texture_offset_x= 0.0,
			texture_offset_y= 0.0,
			border_visible  = false,
			border_flags    = FontBorderFlags.None,
			border_sizes    = '0,0,0,0',
			visible         = true,
			position_x      = 0,
			position_y      = 0,
			can_focus       = true,
			locked          = false,
			lockedz         = true,
			scale_x         = 1.0,
			scale_y         = 1.0,
			width           = 0.0,
			height          = 0.0,
		};
	};
};

local adjustedSettings = default_settings;

local config = settings.load(user_settings_container);

local function CheckVisibility()
	if (config.userSettings.showPlayerBar == false) then
		playerBar.SetHidden(true);
	end
	if (config.userSettings.showExpBar == false) then
		expBar.SetHidden(true);
	end
	if (config.userSettings.showGilTracker == false) then
		gilTracker.SetHidden(true);
	end
	if (config.userSettings.showInventoryTracker == false) then
		inventoryTracker.SetHidden(true);
	end
	if (config.userSettings.showPartyList == false) then
		partyList.SetHidden(true);
	end
end

local function UpdateFonts()
	playerBar.UpdateFonts(adjustedSettings.playerBarSettings);
	expBar.UpdateFonts(adjustedSettings.expBarSettings);
	gilTracker.UpdateFonts(adjustedSettings.gilTrackerSettings);
	inventoryTracker.UpdateFonts(adjustedSettings.inventoryTrackerSettings);
	partyList.UpdateFonts(adjustedSettings.partyListSettings);
end

local function UpdateUserSettings()
    local ns = default_settings;
	local us = config.userSettings;

	-- Target Bar
	ns.targetBarSettings.barWidth = ns.targetBarSettings.barWidth * us.targetBarScaleX;
	ns.targetBarSettings.barHeight = ns.targetBarSettings.barHeight * us.targetBarScaleY;
	ns.targetBarSettings.totBarHeight = ns.targetBarSettings.totBarHeight * us.targetBarScaleY;
	ns.targetBarSettings.textScale = ns.targetBarSettings.textScale * us.targetBarFontScale;

	-- Party List
    ns.partyListSettings.hpBarWidth = ns.partyListSettings.hpBarWidth * us.partyListScaleX;
    ns.partyListSettings.hpBarHeight = ns.partyListSettings.hpBarHeight * us.partyListScaleY;
    ns.partyListSettings.mpBarHeight = ns.partyListSettings.mpBarHeight * us.partyListScaleY;
    ns.partyListSettings.tpBarWidth = ns.partyListSettings.tpBarWidth * us.partyListScaleX;
    ns.partyListSettings.tpBarHeight = ns.partyListSettings.tpBarHeight * us.partyListScaleY;
    ns.partyListSettings.entrySpacing = ns.partyListSettings.entrySpacing * us.partyListScaleY;
	ns.partyListSettings.nameSpacing = ns.partyListSettings.nameSpacing * us.partyListScaleY;
    ns.partyListSettings.hp_font_settings.font_height = ns.partyListSettings.hp_font_settings.font_height + us.partyListFontOffset;
    ns.partyListSettings.mp_font_settings.font_height = ns.partyListSettings.mp_font_settings.font_height + us.partyListFontOffset;
    ns.partyListSettings.name_font_settings.font_height = ns.partyListSettings.name_font_settings.font_height + us.partyListFontOffset;
	ns.partyListSettings.backgroundPaddingX1 = ns.partyListSettings.backgroundPaddingX1 * us.partyListScaleX;
	ns.partyListSettings.backgroundPaddingX2 = ns.partyListSettings.backgroundPaddingX2 * us.partyListScaleX;
	ns.partyListSettings.backgroundPaddingY1 = ns.partyListSettings.backgroundPaddingY1 * us.partyListScaleY;
	ns.partyListSettings.backgroundPaddingY2 = ns.partyListSettings.backgroundPaddingY2 * us.partyListScaleY;
	ns.partyListSettings.cursorPaddingX1 = ns.partyListSettings.cursorPaddingX1 * us.partyListScaleX;
	ns.partyListSettings.cursorPaddingX2 = ns.partyListSettings.cursorPaddingX2 * us.partyListScaleX;
	ns.partyListSettings.cursorPaddingY1 = ns.partyListSettings.cursorPaddingY1 * us.partyListScaleY;
	ns.partyListSettings.cursorPaddingY2 = ns.partyListSettings.cursorPaddingY2 * us.partyListScaleY;

	-- Player Bar
	ns.playerBarSettings.barWidth = ns.playerBarSettings.barWidth * us.playerBarScaleX;
	ns.playerBarSettings.barSpacing = ns.playerBarSettings.barSpacing * us.playerBarScaleX;
	ns.playerBarSettings.barHeight = ns.playerBarSettings.barHeight * us.playerBarScaleY;
	ns.playerBarSettings.font_settings.font_height = ns.playerBarSettings.font_settings.font_height + us.playerBarFontOffset;

	-- Exp Bar
	ns.expBarSettings.barWidth = ns.expBarSettings.barWidth * us.expBarScaleX;
	ns.expBarSettings.barHeight = ns.expBarSettings.barHeight * us.expBarScaleY;
	ns.expBarSettings.job_font_settings.font_height = ns.expBarSettings.job_font_settings.font_height + us.expBarFontOffset;
	ns.expBarSettings.exp_font_settings.font_height = ns.expBarSettings.exp_font_settings.font_height + us.expBarFontOffset;
	ns.expBarSettings.percent_font_settings.font_height = ns.expBarSettings.percent_font_settings.font_height + us.expBarFontOffset;

	-- Gil Tracker
	ns.gilTrackerSettings.iconScale = ns.gilTrackerSettings.iconScale * us.gilTrackerScale;
	ns.gilTrackerSettings.font_settings.font_height = ns.gilTrackerSettings.font_settings.font_height + us.gilTrackerFontOffset;
	
	-- Inventory Tracker
	ns.inventoryTrackerSettings.dotRadius = ns.inventoryTrackerSettings.dotRadius * us.inventoryTrackerScale;
	ns.inventoryTrackerSettings.dotSpacing = ns.inventoryTrackerSettings.dotSpacing * us.inventoryTrackerScale;
	ns.inventoryTrackerSettings.groupSpacing = ns.inventoryTrackerSettings.groupSpacing * us.inventoryTrackerScale;
	ns.inventoryTrackerSettings.font_settings.font_height = ns.inventoryTrackerSettings.font_settings.font_height + us.inventoryTrackerFontOffset;

	-- Enemy List
	ns.enemyListSettings.barWidth = ns.enemyListSettings.barWidth * us.enemyListScaleX;
	ns.enemyListSettings.barHeight = ns.enemyListSettings.barHeight * us.enemyListScaleY;
	ns.enemyListSettings.textScale = ns.enemyListSettings.textScale * us.enemyListFontScale;

    adjustedSettings = ns;
end

function UpdateSettings()
    -- Save the current settings..
    settings.save();

	UpdateUserSettings();
	CheckVisibility();
	UpdateFonts();
end;

settings.register('settings', 'settings_update', UpdateSettings);

--[[
* event: d3d_present
* desc : Event called when the Direct3D device is presenting a scene.
--]]
ashita.events.register('d3d_present', 'present_cb', function ()

	if (config.userSettings.showPlayerBar) then
		playerBar.DrawWindow(adjustedSettings.playerBarSettings, config.userSettings);
	end
	if (config.userSettings.showTargetBar) then
		targetBar.DrawWindow(adjustedSettings.targetBarSettings, config.userSettings);
	end
	if (config.userSettings.showEnemyList) then
		enemyList.DrawWindow(adjustedSettings.enemyListSettings, config.userSettings);
	end
	if (config.userSettings.showExpBar) then
		expBar.DrawWindow(adjustedSettings.expBarSettings, config.userSettings);
	end
	if (config.userSettings.showGilTracker) then
		gilTracker.DrawWindow(adjustedSettings.gilTrackerSettings, config.userSettings);
	end
	if (config.userSettings.showInventoryTracker) then
		inventoryTracker.DrawWindow(adjustedSettings.inventoryTrackerSettings, config.userSettings);
	end
	if (config.userSettings.showPartyList) then
		partyList.DrawWindow(adjustedSettings.partyListSettings, config.userSettings);
	end
end);

ashita.events.register('load', 'load_cb', function ()

	UpdateUserSettings();
    playerBar.Initialize(adjustedSettings.playerBarSettings);
	expBar.Initialize(adjustedSettings.expBarSettings);
	gilTracker.Initialize(adjustedSettings.gilTrackerSettings);
	inventoryTracker.Initialize(adjustedSettings.inventoryTrackerSettings);
	partyList.Initialize(adjustedSettings.partyListSettings);
end);

ashita.events.register('command', 'command_cb', function (e)
   
	-- Parse the command arguments
	local command_args = e.command:lower():args()
    if table.contains({'/consolidatedui', '/cui', '/horizonui', '/hui'}, command_args[1]) then
        if table.contains({'playerbar'}, command_args[2]) then
			config.userSettings.showPlayerBar = not config.userSettings.showPlayerBar;
			UpdateSettings();
			print('CONSOLIDATED UI: Toggled PlayerBar');
		elseif table.contains({'targetbar'}, command_args[2]) then
			config.userSettings.showTargetBar = not config.userSettings.showTargetBar;
			UpdateSettings();
			print('CONSOLIDATED UI: Toggled TargetBar');
        elseif table.contains({'enemylist'}, command_args[2]) then
			config.userSettings.showEnemyList = not config.userSettings.showEnemyList;
			UpdateSettings();
			print('CONSOLIDATED UI: Toggled EnemyList');
		elseif table.contains({'expbar'}, command_args[2]) then
			config.userSettings.showExpBar = not config.userSettings.showExpBar;
			UpdateSettings();
			print('CONSOLIDATED UI: Toggled ExpBar');
		elseif table.contains({'giltracker'}, command_args[2]) then
			config.userSettings.showGilTracker = not config.userSettings.showGilTracker;
			UpdateSettings();
			print('CONSOLIDATED UI: Toggled GilTracker');
		elseif table.contains({'inventorytracker'}, command_args[2]) then
			config.userSettings.showInventoryTracker = not config.userSettings.showInventoryTracker;
			UpdateSettings();
			print('CONSOLIDATED UI: Toggled InventoryTracker');
		elseif table.contains({'partylist'}, command_args[2]) then
			config.userSettings.showPartyList = not config.userSettings.showPartyList;
			UpdateSettings();
			print('CONSOLIDATED UI: Toggled PartyList');
		elseif table.contains({'reset'}, command_args[2]) then
			config.userSettings = user_settings;
			UpdateSettings();
			print('CONSOLIDATED UI: Configuration Reset');
		elseif table.contains({'solopartylist'}, command_args[2]) then
			config.userSettings.showPartyListWhenSolo = not config.userSettings.showPartyListWhenSolo;
			UpdateSettings();
			print('CONSOLIDATED UI: PartyList when solo toggled');
		else
			print('CONSOLIDATED UI: HELP /consolidatedui /cui');
			print('CONSOLIDATED UI: /cui reset - Reset all configs');
			print('CONSOLIDATED UI: /cui solopartylist - Show/Hide party list when solo');
			print('CONSOLIDATED UI: Toggle elements with the following commands');
			print('CONSOLIDATED UI: /cui playerbar');
			print('CONSOLIDATED UI: /cui targetbar');
			print('CONSOLIDATED UI: /cui enemylist');
			print('CONSOLIDATED UI: /cui expbar');
			print('CONSOLIDATED UI: /cui giltracker');
			print('CONSOLIDATED UI: /cui inventorytracker');
			print('CONSOLIDATED UI: /cui partylist');
		end
		
	e.blocked = true;
    end

end);

-- Track our packets
ashita.events.register('packet_in', 'packet_in_cb', function (e)
	if (e.id == 0x0028) then
		local actionPacket = ParseActionPacket(e);
		if (config.userSettings.showTargetBar) then
			targetBar.HandleActionPacket(actionPacket);
		end
		if (config.userSettings.showEnemyList) then
			enemyList.HandleActionPacket(actionPacket);
		end
	elseif (e.id == 0x00E) then
		local mobUpdatePacket = ParseMobUpdatePacket(e);
		if (config.userSettings.showEnemyList) then
			enemyList.HandleMobUpdatePacket(mobUpdatePacket);
		end
	end
end);