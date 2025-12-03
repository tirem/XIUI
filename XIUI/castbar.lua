require('common');
require('helpers');
local imgui = require('imgui');
local fonts = require('fonts');
local progressbar = require('progressbar');
local gdi = require('gdifonts.include');
local encoding = require('gdifonts.encoding');

local spellText;
local percentText;
local allFonts; -- Table for batch visibility operations

local castbar = {
	previousPercent = 0,
	currentSpellId = nil,
	currentItemId = nil,
};

local CureSpells = T{ 'Cure','Cure II','Cure III','Cure IV','Cure V','Cure VI','Full Cure','Curaga','Curaga II','Curaga III','Curaga IV','Curaga V' }

castbar.GetSpellName = function(spellId)
	return AshitaCore:GetResourceManager():GetSpellById(spellId).Name[1];
end

castbar.GetSpellType = function(spellId)
	return AshitaCore:GetResourceManager():GetSpellById(spellId).Skill;
end

castbar.GetItemName = function(itemId)
	return AshitaCore:GetResourceManager():GetItemById(itemId).Name[1];
end

castbar.GetLabelText = function()
	if (castbar.currentSpellId) then
		return encoding:ShiftJIS_To_UTF8(castbar.GetSpellName(castbar.currentSpellId), true);
	elseif (castbar.currentItemId) then
		return encoding:ShiftJIS_To_UTF8(castbar.GetItemName(castbar.currentItemId), true);
	else
		return '';
	end
end

castbar.DrawWindow = function(settings)
	local castBar = GetCastBarSafe();
	if castBar == nil then
		return;
	end
	local percent = castBar:GetPercent();

	local totalCast = 1

	if (gConfig.castBarFastCastEnabled) then
		local player = GetPlayerSafe();
		if player == nil then
			return;
		end
		local MID = player:GetMainJob()
		local SID = player:GetSubJob()

		local fastCast = 0
		if (gConfig.castBarFastCast[MID]) then
			fastCast = fastCast + tonumber(string.format("%.2f", gConfig.castBarFastCast[MID]))
		end

		if (castbar.currentSpellId) then
			if (MID == 3 and castbar.GetSpellType(castbar.currentSpellId) == 33) then -- if WHM MJ and Healing Magic
				if (CureSpells:contains(castbar.GetSpellName(castbar.currentSpellId))) then
					fastCast = fastCast + tonumber(string.format("%.2f", gConfig.castBarFastCastWHMCureSpeed))
				end
			elseif (MID == 10 and castbar.GetSpellType(castbar.currentSpellId) == 40) then -- if BRD MJ and Singing
				fastCast = fastCast + tonumber(string.format("%.2f", gConfig.castBarFastCastBRDSingSpeed))
			end
		end

		if (SID == 5 and gConfig.castBarFastCastRDMSJ) then -- if RDM SJ
			fastCast = fastCast + tonumber(string.format("%.2f", gConfig.castBarFastCastRDMSJ))
		end

		totalCast = (1 - fastCast) * 0.75
	end

	percent = percent / totalCast

	if ((percent < 1 and percent ~= castbar.previousPercent) or showConfig[1]) then
		imgui.SetNextWindowSize({settings.barWidth, -1});

		local windowFlags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoBringToFrontOnFocus);
		if (gConfig.lockPositions) then
			windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
		end
		if (imgui.Begin('CastBar', true, windowFlags)) then
			local startX, startY = imgui.GetCursorScreenPos();

			-- Calculate bookend width and text padding (same as exp bar)
			local bookendWidth = gConfig.showCastBarBookends and (settings.barHeight / 2) or 0;
			local textPadding = 8;

			-- Create progress bar
			--[[
			imgui.PushStyleColor(ImGuiCol_PlotHistogram, {0.2, 0.75, 1, 1});

			imgui.ProgressBar(showConfig[1] and 0.5 or percent, {-1, settings.barHeight}, '');

			imgui.PopStyleColor(1);
			]]--

			local castGradient = GetCustomGradient(gConfig.colorCustomization.castBar, 'barGradient') or {'#3798ce', '#78c5ee'};
			progressbar.ProgressBar({{showConfig[1] and 0.5 or percent, castGradient}}, {-1, settings.barHeight}, {decorate = gConfig.showCastBarBookends});

			-- Draw Spell/Item name
			imgui.SameLine();

			-- Dynamically set font heights based on settings (avoids expensive font recreation)
			spellText:set_font_height(settings.spell_font_settings.font_height);
			percentText:set_font_height(settings.percent_font_settings.font_height);

			-- Left-aligned text position (spell name) - 8px from left edge (after bookend)
			local leftTextX = startX + bookendWidth + textPadding;
			spellText:set_position_x(leftTextX);
			spellText:set_position_y(startY + settings.barHeight + settings.spellOffsetY);
			spellText:set_text(showConfig[1] and 'Configuration Mode' or castbar.GetLabelText());

			-- Right-aligned text position (percent) - 8px from right edge (before bookend)
			local progressBarWidth = settings.barWidth - imgui.GetStyle().FramePadding.x * 2;
			local rightTextX = startX + progressBarWidth - bookendWidth - textPadding;
			percentText:set_position_x(rightTextX);
			percentText:set_position_y(startY + settings.barHeight + settings.percentOffsetY);
			percentText:set_text(showConfig[1] and '50%' or math.floor(percent * 100) .. '%');

			SetFontsVisible(allFonts,true);
		end

		imgui.End();
	else
		SetFontsVisible(allFonts,false);
	end

	castbar.previousPercent = percent;
end

castbar.UpdateVisuals = function(settings)
	-- Use FontManager for cleaner font recreation
	spellText = FontManager.recreate(spellText, settings.spell_font_settings);
	percentText = FontManager.recreate(percentText, settings.percent_font_settings);
	allFonts = {spellText, percentText};
end

castbar.SetHidden = function(hidden)
	if (hidden == true) then
		SetFontsVisible(allFonts, false);
	end
end

castbar.Initialize = function(settings)
	-- Use FontManager for cleaner font creation
	spellText = FontManager.create(settings.spell_font_settings);
	percentText = FontManager.create(settings.percent_font_settings);
	allFonts = {spellText, percentText};
end

castbar.HandleActionPacket = function(actionPacket)
	local party = GetPartySafe();
	if party == nil then
		return;
	end
	local localPlayerId = party:GetMemberServerId(0);

	-- We only care about:
	-- - Actions originating from the player
	-- - Actions that are spell or item casts
	-- - The aforementioned action is starting
	if (actionPacket.UserId == localPlayerId and (actionPacket.Type == 8 or actionPacket.Type == 9) and actionPacket.Param == 0x6163) then
		castbar.currentSpellId = nil;
		castbar.currentItemId = nil;

		if (actionPacket.Type == 8) then
			castbar.currentSpellId = actionPacket.Targets[1].Actions[1].Param;
		else
			castbar.currentItemId = actionPacket.Targets[1].Actions[1].Param;
		end
	end
end

castbar.Cleanup = function()
	-- Use FontManager for cleaner font destruction
	spellText = FontManager.destroy(spellText);
	percentText = FontManager.destroy(percentText);
	allFonts = nil;
end

return castbar;