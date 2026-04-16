require('common');
require('handlers.helpers');
local imgui = require('imgui');
local imtext = require('libs.imtext');
local progressbar = require('libs.progressbar');
local encoding = require('libs.encoding');
local defaultPositions = require('libs.defaultpositions');

-- Position save/restore state
local hasAppliedSavedPosition = false;
local forcePositionReset = false;
local lastSavedPosX, lastSavedPosY = nil, nil;

local castbar = {
	previousPercent = 0,
	currentSpellId = nil,
	currentItemId = nil,
	-- Cached spell data (set once at cast start, avoids per-frame resource lookups)
	currentSpellType = nil,
	currentSpellName = nil,
};

-- CureSpells moved to helpers.lua as CURE_SPELLS (shared global)

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

	-- Use shared fast cast calculation
	local player = GetPlayerSafe();
	if player ~= nil then
		local fastCast = CalculateFastCast(
			player:GetMainJob(),
			player:GetSubJob(),
			castbar.currentSpellType,
			castbar.currentSpellName,
			player:GetMainJobLevel(),
			player:GetSubJobLevel()
		);
		if fastCast > 0 then
			-- The 0.75 factor corrects for how GetCastBarSafe():GetPercent() reports progress
			totalCast = (1 - fastCast) * 0.75;
		end
	end

	percent = percent / totalCast

	if ((percent < 1 and percent ~= castbar.previousPercent) or showConfig[1]) then
		imgui.SetNextWindowSize({settings.barWidth, -1});

		-- Handle position reset or restore
		if forcePositionReset then
			local defX, defY = defaultPositions.GetCastBarPosition();
			imgui.SetNextWindowPos({defX, defY}, ImGuiCond_Always);
			forcePositionReset = false;
			hasAppliedSavedPosition = true;
			lastSavedPosX, lastSavedPosY = defX, defY;
		elseif not hasAppliedSavedPosition and gConfig.castBarWindowPosX ~= nil then
			imgui.SetNextWindowPos({gConfig.castBarWindowPosX, gConfig.castBarWindowPosY}, ImGuiCond_Once);
			hasAppliedSavedPosition = true;
			lastSavedPosX = gConfig.castBarWindowPosX;
			lastSavedPosY = gConfig.castBarWindowPosY;
		end

		local windowFlags = GetBaseWindowFlags(gConfig.lockPositions);
		ApplyWindowPosition('CastBar');
		if (imgui.Begin('CastBar', true, windowFlags)) then
			SaveWindowPosition('CastBar');
			local drawList = GetUIDrawList();
			imtext.SetConfigFromSettings(settings.spell_font_settings);

			local startX, startY = imgui.GetCursorScreenPos();

			-- Calculate bookend width and text padding (same as exp bar)
			local bookendWidth = gConfig.showCastBarBookends and (settings.barHeight / 2) or 0;
			local textPadding = 8;

			-- Create progress bar
			local castGradient = GetCustomGradient(gConfig.colorCustomization.castBar, 'barGradient') or {'#3798ce', '#78c5ee'};
			progressbar.ProgressBar({{showConfig[1] and 0.5 or percent, castGradient}}, {-1, settings.barHeight}, {decorate = gConfig.showCastBarBookends});

			-- Draw Spell/Item name
			imgui.SameLine();

			-- Left-aligned text position (spell name) - 8px from left edge (after bookend)
			local leftTextX = startX + bookendWidth + textPadding;
			local spellTextStr = showConfig[1] and 'Configuration Mode' or castbar.GetLabelText();
			imtext.Draw(drawList, spellTextStr, leftTextX, startY + settings.barHeight + settings.spellOffsetY, gConfig.colorCustomization.castBar.spellTextColor, settings.spell_font_settings.font_height);

			-- Right-aligned text position (percent) - 8px from right edge (before bookend)
			local progressBarWidth = settings.barWidth - imgui.GetStyle().FramePadding.x * 2;
			local rightTextX = startX + progressBarWidth - bookendWidth - textPadding;
			local percentTextStr = showConfig[1] and '50%' or math.floor(percent * 100) .. '%';
			imtext.SetConfigFromSettings(settings.percent_font_settings);
			local percentWidth = imtext.Measure(percentTextStr, settings.percent_font_settings.font_height);
			imtext.Draw(drawList, percentTextStr, rightTextX - percentWidth, startY + settings.barHeight + settings.percentOffsetY, gConfig.colorCustomization.castBar.percentTextColor, settings.percent_font_settings.font_height);

			-- Save position if moved (with change detection to avoid spam)
			local winPosX, winPosY = imgui.GetWindowPos();
			if not gConfig.lockPositions then
				if lastSavedPosX == nil or
				   math.abs(winPosX - lastSavedPosX) > 1 or
				   math.abs(winPosY - lastSavedPosY) > 1 then
					gConfig.castBarWindowPosX = winPosX;
					gConfig.castBarWindowPosY = winPosY;
					lastSavedPosX = winPosX;
					lastSavedPosY = winPosY;
				end
			end
		end

		imgui.End();
	end

	castbar.previousPercent = percent;
end

castbar.UpdateVisuals = function(settings)
	imtext.Reset();
end

castbar.SetHidden = function(hidden)
end

castbar.Initialize = function(settings)
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
		castbar.currentSpellType = nil;
		castbar.currentSpellName = nil;

		if (actionPacket.Type == 8) then
			castbar.currentSpellId = actionPacket.Targets[1].Actions[1].Param;
			-- Cache spell type and name at cast start (avoids per-frame resource lookups)
			castbar.currentSpellType = castbar.GetSpellType(castbar.currentSpellId);
			castbar.currentSpellName = castbar.GetSpellName(castbar.currentSpellId);
		else
			castbar.currentItemId = actionPacket.Targets[1].Actions[1].Param;
		end
	end
end

castbar.Cleanup = function()
end

castbar.ResetPositions = function()
	forcePositionReset = true;
	hasAppliedSavedPosition = false;
end

return castbar;
