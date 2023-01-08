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

	playerBarScaleX = 1,
	playerBarScaleY = 1,
	playerBarFontScale = 1,

	targetBarScaleX = 1,
	targetBarScaleY = 1,
	targetBarFontScale = 1,

	enemyListScaleX = 1,
	enemyListScaleY = 1,
	enemyListFontScale = 1,

	expBarScaleX = 1,
	expBarScaleY = 1,
	expBarFontScale = 1,

	gilTrackerScale = 1,
	gilTrackerFontScale = 1,

	inventoryTrackerScaleX= 1,
	inventoryTrackerFontScale = 1,

	partyListScaleX = 1,
	partyListScaleY = 1,
	partyListFontScale = 1,
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
		showBarPercent = true;
	};

	-- settings for the playerbar
	playerBarSettings =
	T{
		hitAnimSpeed = 2;
		hitDelayLength = .5;
		barWidth = 500;
		barSpacing = 10;
		barHeight = 20;
		textYOffset = -4;
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
		maxEntries = 8;
		entrySpacing = 1;
	};

	-- settings for the exp bar
	expBarSettings =
	T{
		barWidth = 550;
		barHeight = 10;
		jobOffsetY = 0;
		expOffsetY = 0;
		percentOffsetY = -2;
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
		iconScale = 1;
		offsetX = -5;
		offsetY = 5;
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
		textOffsetY = -7;
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
		tpBarWidth = 75,
		tpBarHeight = 10,
		entrySpacing = 10,
		hpTextOffsetX = -10,
		hpTextOffsetY = -3,
		mpTextOffsetY = -3,
		nameSpacing = 100;
		tpBarOffsetY = 8;
		hpBarOffsetY = 1;
		showWhenSolo = false,
		backgroundPaddingX1 = 30,
		backgroundPaddingX2 = 200,
		backgroundPaddingY1 = 20,
		backgroundPaddingY2 = 10,
		cursorPaddingX1 = 7,
		cursorPaddingX2 = 7,
		cursorPaddingY1 = 2,
		cursorPaddingY2 = 10,
		leaderDotRadius = 4,
		hp_font_settings = 
		T{
			visible = true,
			locked = true,
			font_family = 'Consolas',
			font_height = 14,
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
		name_font_settings = 
		T{
			visible = true,
			locked = true,
			font_family = 'Consolas',
			font_height = 15,
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

function UpdateSettings()
    -- Save the current settings..
    settings.save();

	CheckVisibility();
end;

settings.register('settings', 'settings_update', UpdateSettings);

--[[
* event: d3d_present
* desc : Event called when the Direct3D device is presenting a scene.
--]]
ashita.events.register('d3d_present', 'present_cb', function ()

	if (config.userSettings.showPlayerBar) then
		playerBar.DrawWindow(default_settings.playerBarSettings, config.userSettings);
	end
	if (config.userSettings.showTargetBar) then
		targetBar.DrawWindow(default_settings.targetBarSettings, config.userSettings);
	end
	if (config.userSettings.showEnemyList) then
		enemyList.DrawWindow(default_settings.enemyListSettings, config.userSettings);
	end
	if (config.userSettings.showExpBar) then
		expBar.DrawWindow(default_settings.expBarSettings, config.userSettings);
	end
	if (config.userSettings.showGilTracker) then
		gilTracker.DrawWindow(default_settings.gilTrackerSettings, config.userSettings);
	end
	if (config.userSettings.showInventoryTracker) then
		inventoryTracker.DrawWindow(default_settings.inventoryTrackerSettings, config.userSettings);
	end
	if (config.userSettings.showPartyList) then
		partyList.DrawWindow(default_settings.partyListSettings, config.userSettings);
	end
end);

ashita.events.register('load', 'load_cb', function ()

    playerBar.Initialize(default_settings.playerBarSettings);
	expBar.Initialize(default_settings.expBarSettings);
	gilTracker.Initialize(default_settings.gilTrackerSettings);
	inventoryTracker.Initialize(default_settings.inventoryTrackerSettings);
	partyList.Initialize(default_settings.partyListSettings);
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