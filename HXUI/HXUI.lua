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
addon.author    = 'Tirem (Programmer) & Shuu (Designer) & Extrasupervery (Programmer)';
addon.version   = '0.1.1';
addon.desc      = 'Multiple UI elements with manager';
addon.link      = 'https://github.com/tirem/HXUI'

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
local castBar = require('castbar');
local configMenu = require('configmenu');
local debuffHandler = require('debuffhandler');

local user_settings = 
T{
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
	showTargetBarPercent = true,

	playerBarScaleX = 1,
	playerBarScaleY = 1,
	playerBarFontOffset = 0,

	targetBarScaleX = 1,
	targetBarScaleY = 1,
	targetBarFontScale = 1,
	targetBarIconScale = 1,

	enemyListScaleX = 1,
	enemyListScaleY = 1,
	enemyListFontScale = 1,
	enemyListIconScale = 1,

	expBarScaleX = 1,
	expBarScaleY = 1,
	expBarFontOffset = 0,

	gilTrackerScale = 1,
	gilTrackerFontOffset = 0,

	inventoryTrackerScale= 1,
	inventoryTrackerFontOffset = 0,

	partyListScaleX = 1,
	partyListScaleY = 1,
	partyListBuffScale = 1,
	partyListFontOffset = 0,
	partyListStatusTheme = 0,
	partyListTheme = 0, -- 0: HorizonXI, 1: XIV1.0, 2: XIV

	castBarScaleX = 1,
	castBarScaleY = 1,
	castBarFontOffset = 0,
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
		iconSize = 22,
		maxIconColumns = 12,
	};

	-- settings for the playerbar
	playerBarSettings =
	T{
		hitAnimSpeed = 2,
		hitDelayLength = .5,
		barWidth = 500,
		barSpacing = 10,
		barHeight = 20,
		textYOffset = -3,
		showMpBar = true,
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
		barHeight = 12;
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
		barSpacing = 0,
		entrySpacing = 0,

		nameTextOffsetX = 0,
		nameTextOffsetY = 5,
		hpTextOffsetX = -2,
		hpTextOffsetY = -3,
		mpTextOffsetX = -2,
		mpTextOffsetY = -3,
		tpTextOffsetX = -2,
		tpTextOffsetY = -3,

		backgroundPaddingX1 = 0,
		backgroundPaddingX2 = 0,
		backgroundPaddingY1 = 0,
		backgroundPaddingY2 = 0,

		cursorPaddingX1 = 3,
		cursorPaddingX2 = 3,
		cursorPaddingY1 = 3,
		cursorPaddingY2 = 3,
		dotRadius = 3,

		arrowSize = 1;

		iconSize = 20,
		maxIconColumns = 6,
		buffOffset = 10,
		xivBuffOffsetY = 5;

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
		primData = {
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
		spellOffsetY = 0,
		spellOffsetY = 0,
		percentOffsetY = 2,
		percentOffsetX = -10,
		spell_font_settings = 
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
		percent_font_settings = 
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
	};
};

local adjustedSettings = deep_copy_table(default_settings);
local defaultUserSettings = deep_copy_table(user_settings);

local config = settings.load(user_settings_container);
gConfig = config.userSettings;

showConfig = { false };

function ResetSettings()
	gConfig = deep_copy_table(defaultUserSettings);
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
end

local function ForceHide()

	playerBar.SetHidden(true);
	expBar.SetHidden(true);
	gilTracker.SetHidden(true);
	inventoryTracker.SetHidden(true);
	partyList.SetHidden(true);
	castBar.SetHidden(true);
end

local function UpdateFonts()
	playerBar.UpdateFonts(adjustedSettings.playerBarSettings);
	expBar.UpdateFonts(adjustedSettings.expBarSettings);
	gilTracker.UpdateFonts(adjustedSettings.gilTrackerSettings);
	inventoryTracker.UpdateFonts(adjustedSettings.inventoryTrackerSettings);
	partyList.UpdateFonts(adjustedSettings.partyListSettings);
	castBar.UpdateFonts(adjustedSettings.castBarSettings);
end

local function UpdateUserSettings()
    local ns = default_settings;
	local us = gConfig;

	-- Target Bar
	adjustedSettings.targetBarSettings.barWidth = ns.targetBarSettings.barWidth * us.targetBarScaleX;
	adjustedSettings.targetBarSettings.barHeight = ns.targetBarSettings.barHeight * us.targetBarScaleY;
	adjustedSettings.targetBarSettings.totBarHeight = ns.targetBarSettings.totBarHeight * us.targetBarScaleY;
	adjustedSettings.targetBarSettings.textScale = ns.targetBarSettings.textScale * us.targetBarFontScale;
	adjustedSettings.targetBarSettings.iconSize = ns.targetBarSettings.iconSize * us.targetBarIconScale;

	-- Party List
    adjustedSettings.partyListSettings.hpBarWidth = ns.partyListSettings.hpBarWidth * us.partyListScaleX;
    adjustedSettings.partyListSettings.barHeight = ns.partyListSettings.barHeight * us.partyListScaleY;
    adjustedSettings.partyListSettings.tpBarWidth = ns.partyListSettings.tpBarWidth * us.partyListScaleX;
	adjustedSettings.partyListSettings.mpBarWidth = ns.partyListSettings.mpBarWidth * us.partyListScaleX;
    adjustedSettings.partyListSettings.entrySpacing = ns.partyListSettings.entrySpacing * us.partyListScaleY;
    adjustedSettings.partyListSettings.hp_font_settings.font_height = math.max(ns.partyListSettings.hp_font_settings.font_height + us.partyListFontOffset, 1);
    adjustedSettings.partyListSettings.mp_font_settings.font_height = math.max(ns.partyListSettings.mp_font_settings.font_height + us.partyListFontOffset, 1);
	adjustedSettings.partyListSettings.tp_font_settings.font_height = math.max(ns.partyListSettings.tp_font_settings.font_height + us.partyListFontOffset, 1);
    adjustedSettings.partyListSettings.name_font_settings.font_height = math.max(ns.partyListSettings.name_font_settings.font_height + us.partyListFontOffset, 1);
	adjustedSettings.partyListSettings.backgroundPaddingX1 = ns.partyListSettings.backgroundPaddingX1 * us.partyListScaleX;
	adjustedSettings.partyListSettings.backgroundPaddingX2 = ns.partyListSettings.backgroundPaddingX2 * us.partyListScaleX;
	adjustedSettings.partyListSettings.backgroundPaddingY1 = ns.partyListSettings.backgroundPaddingY1 * us.partyListScaleY;
	adjustedSettings.partyListSettings.backgroundPaddingY2 = ns.partyListSettings.backgroundPaddingY2 * us.partyListScaleY;
	adjustedSettings.partyListSettings.cursorPaddingX1 = ns.partyListSettings.cursorPaddingX1 * us.partyListScaleX;
	adjustedSettings.partyListSettings.cursorPaddingX2 = ns.partyListSettings.cursorPaddingX2 * us.partyListScaleX;
	adjustedSettings.partyListSettings.cursorPaddingY1 = ns.partyListSettings.cursorPaddingY1 * us.partyListScaleY;
	adjustedSettings.partyListSettings.cursorPaddingY2 = ns.partyListSettings.cursorPaddingY2 * us.partyListScaleY;
	adjustedSettings.partyListSettings.iconSize = ns.partyListSettings.iconSize * us.partyListBuffScale;

	-- Player Bar
	adjustedSettings.playerBarSettings.showMpBar = us.showPlayerMpBar;
	adjustedSettings.playerBarSettings.barWidth = ns.playerBarSettings.barWidth * us.playerBarScaleX;
	adjustedSettings.playerBarSettings.barSpacing = ns.playerBarSettings.barSpacing * us.playerBarScaleX;
	adjustedSettings.playerBarSettings.barHeight = ns.playerBarSettings.barHeight * us.playerBarScaleY;
	adjustedSettings.playerBarSettings.font_settings.font_height = math.max(ns.playerBarSettings.font_settings.font_height + us.playerBarFontOffset, 1);

	-- Exp Bar
	adjustedSettings.expBarSettings.barWidth = ns.expBarSettings.barWidth * us.expBarScaleX;
	adjustedSettings.expBarSettings.barHeight = ns.expBarSettings.barHeight * us.expBarScaleY;
	adjustedSettings.expBarSettings.job_font_settings.font_height = math.max(ns.expBarSettings.job_font_settings.font_height + us.expBarFontOffset, 1);
	adjustedSettings.expBarSettings.exp_font_settings.font_height = math.max(ns.expBarSettings.exp_font_settings.font_height + us.expBarFontOffset, 1);
	adjustedSettings.expBarSettings.percent_font_settings.font_height = math.max(ns.expBarSettings.percent_font_settings.font_height + us.expBarFontOffset, 1);

	-- Gil Tracker
	adjustedSettings.gilTrackerSettings.iconScale = ns.gilTrackerSettings.iconScale * us.gilTrackerScale;
	adjustedSettings.gilTrackerSettings.font_settings.font_height = math.max(ns.gilTrackerSettings.font_settings.font_height + us.gilTrackerFontOffset, 1);
	
	-- Inventory Tracker
	adjustedSettings.inventoryTrackerSettings.dotRadius = ns.inventoryTrackerSettings.dotRadius * us.inventoryTrackerScale;
	adjustedSettings.inventoryTrackerSettings.dotSpacing = ns.inventoryTrackerSettings.dotSpacing * us.inventoryTrackerScale;
	adjustedSettings.inventoryTrackerSettings.groupSpacing = ns.inventoryTrackerSettings.groupSpacing * us.inventoryTrackerScale;
	adjustedSettings.inventoryTrackerSettings.font_settings.font_height = math.max(ns.inventoryTrackerSettings.font_settings.font_height + us.inventoryTrackerFontOffset, 1);

	-- Enemy List
	adjustedSettings.enemyListSettings.barWidth = ns.enemyListSettings.barWidth * us.enemyListScaleX;
	adjustedSettings.enemyListSettings.barHeight = ns.enemyListSettings.barHeight * us.enemyListScaleY;
	adjustedSettings.enemyListSettings.textScale = ns.enemyListSettings.textScale * us.enemyListFontScale;
	adjustedSettings.enemyListSettings.iconSize = ns.enemyListSettings.iconSize * us.enemyListIconScale;

	-- Cast Bar
	adjustedSettings.castBarSettings.barWidth = ns.castBarSettings.barWidth * us.castBarScaleX;
	adjustedSettings.castBarSettings.barHeight = ns.castBarSettings.barHeight * us.castBarScaleY;
	adjustedSettings.castBarSettings.spell_font_settings.font_height = math.max(ns.castBarSettings.spell_font_settings.font_height + us.castBarFontOffset, 1);
	adjustedSettings.castBarSettings.percent_font_settings.font_height = math.max(ns.castBarSettings.percent_font_settings.font_height + us.castBarFontOffset, 1);
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

	if (GetEventSystemActive()) then
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

	if (GetHidden() == false) then
		if (gConfig.showPlayerBar) then
			playerBar.DrawWindow(adjustedSettings.playerBarSettings);
		end
		if (gConfig.showTargetBar) then
			targetBar.DrawWindow(adjustedSettings.targetBarSettings);
		end
		if (gConfig.showEnemyList) then
			enemyList.DrawWindow(adjustedSettings.enemyListSettings);
		end
		if (gConfig.showExpBar) then
			expBar.DrawWindow(adjustedSettings.expBarSettings);
		end
		if (gConfig.showGilTracker) then
			gilTracker.DrawWindow(adjustedSettings.gilTrackerSettings);
		end
		if (gConfig.showInventoryTracker) then
			inventoryTracker.DrawWindow(adjustedSettings.inventoryTrackerSettings);
		end
		if (gConfig.showPartyList) then
			partyList.DrawWindow(adjustedSettings.partyListSettings);
		end
		if (gConfig.showCastBar) then
			castBar.DrawWindow(adjustedSettings.castBarSettings);
		end

		configMenu.DrawWindow();
	else
		ForceHide();
	end
end);

ashita.events.register('load', 'load_cb', function ()

	UpdateUserSettings();
    playerBar.Initialize(adjustedSettings.playerBarSettings);
	expBar.Initialize(adjustedSettings.expBarSettings);
	gilTracker.Initialize(adjustedSettings.gilTrackerSettings);
	inventoryTracker.Initialize(adjustedSettings.inventoryTrackerSettings);
	partyList.Initialize(adjustedSettings.partyListSettings);
	castBar.Initialize(adjustedSettings.castBarSettings);
end);

ashita.events.register('command', 'command_cb', function (e)
   
	-- Parse the command arguments
	local command_args = e.command:lower():args()
    if table.contains({'/horizonui', '/hui', '/hxui', '/horizonxiui'}, command_args[1]) then
		-- Toggle the config menu
		showConfig[1] = not showConfig[1];
		e.blocked = true;
	end

end);

-- Track our packets
ashita.events.register('packet_in', 'packet_in_cb', function (e)
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
	end
end);