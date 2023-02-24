require('common');
local imgui = require('imgui');
local fonts = require('fonts');
local progressbar = require('progressbar');

local spellText;
local percentText;

local function UpdateTextVisibility(visible)
	spellText:SetVisible(visible);
	percentText:SetVisible(visible);
end

local castbar = {
	previousPercent = 0,
	currentSpellId = nil,
	currentItemId = nil,
};

castbar.GetSpellName = function(spellId)
	return AshitaCore:GetResourceManager():GetSpellById(spellId).Name[1];
end

castbar.GetItemName = function(itemId)
	return AshitaCore:GetResourceManager():GetItemById(itemId).Name[1];
end

castbar.GetLabelText = function()
	if (castbar.currentSpellId) then
		return castbar.GetSpellName(castbar.currentSpellId);
	elseif (castbar.currentItemId) then
		return castbar.GetItemName(castbar.currentItemId)
	else
		return '';
	end
end

castbar.DrawWindow = function(settings)
	local percent = AshitaCore:GetMemoryManager():GetCastBar():GetPercent();

	if ((percent < 1 and percent ~= castbar.previousPercent) or showConfig[1]) then
		imgui.SetNextWindowSize({settings.barWidth, -1});

		local windowFlags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoBringToFrontOnFocus);
		if (gConfig.lockPositions) then
			windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
		end
		if (imgui.Begin('CastBar', true, windowFlags)) then
			local startX, startY = imgui.GetCursorScreenPos();

			-- Create progress bar
			--[[
			imgui.PushStyleColor(ImGuiCol_PlotHistogram, {0.2, 0.75, 1, 1});

			imgui.ProgressBar(showConfig[1] and 0.5 or percent, {-1, settings.barHeight}, '');

			imgui.PopStyleColor(1);
			]]--
			
			progressbar.ProgressBar({{showConfig[1] and 0.5 or percent, {'#3798ce', '#78c5ee'}}}, {-1, settings.barHeight}, {decorate = gConfig.showCastBarBookends});

			-- Draw Spell/Item name
			imgui.SameLine();

			spellText:SetPositionX(startX);
			spellText:SetPositionY(startY + settings.barHeight + settings.spellOffsetY);
			spellText:SetText(showConfig[1] and 'Configuration Mode' or castbar.GetLabelText());

			percentText:SetPositionX(startX + settings.barWidth - imgui.GetStyle().FramePadding.x * 4);
			percentText:SetPositionY(startY + settings.barHeight + settings.percentOffsetY);
			percentText:SetText(showConfig[1] and '50%' or math.floor(percent * 100) .. '%');

			UpdateTextVisibility(true);
		end

		imgui.End();
	else
		UpdateTextVisibility(false);
	end

	castbar.previousPercent = percent;
end

castbar.UpdateFonts = function(settings)
	spellText:SetFontHeight(settings.spell_font_settings.font_height);
	percentText:SetFontHeight(settings.percent_font_settings.font_height);
end

castbar.SetHidden = function(hidden)
	if (hidden == true) then
		UpdateTextVisibility(false);
	end
end

castbar.Initialize = function(settings)
	spellText = fonts.new(settings.spell_font_settings);
	percentText = fonts.new(settings.percent_font_settings);
end

castbar.HandleActionPacket = function(actionPacket)
	local localPlayerId = AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0);

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

return castbar;