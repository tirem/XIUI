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

castbar.DrawWindow = function(settings, userSettings)
	local percent = AshitaCore:GetMemoryManager():GetCastBar():GetPercent();

	if ((percent < 1 and percent ~= castbar.previousPercent) or showConfig[1]) then
		imgui.SetNextWindowSize({settings.barWidth, -1});

		if (imgui.Begin('CastBar', true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground))) then
			local startX, startY = imgui.GetCursorScreenPos();

			-- Create progress bar
			--[[
			imgui.PushStyleColor(ImGuiCol_PlotHistogram, {0.2, 0.75, 1, 1});

			imgui.ProgressBar(showConfig[1] and 0.5 or percent, {-1, settings.barHeight}, '');

			imgui.PopStyleColor(1);
			]]--

			progressbar.ProgressBar(showConfig[1] and 0.5 or percent, {-1, settings.barHeight}, '#3798ce', '#78c5ee');

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

-- TODO: Expand ParseActionPacket to support the param field which, for casts, determines
-- whether or not the cast is starting or was interrupted.
castbar.HandleActionPacket = function(e)
	if (e.id == 0x28) then
		local localPlayerId = AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0);

		local actorId = struct.unpack('L', e.data, 0x05 + 1);
    	local actionType = ashita.bits.unpack_be(e.data_raw, 10, 2, 4);
    	local isStarting = ashita.bits.unpack_be(e.data_raw, 10, 6, 16) == 24931;
    	local spellOrItemId = ashita.bits.unpack_be(e.data_raw, 0, 213, 17);

    	if (actorId == localPlayerId and isStarting) then
    		castbar.currentSpellId = nil;
    		castbar.currentItemId = nil;

    		if (actionType == 8) then
    			castbar.currentSpellId = spellOrItemId;
    		else
    			castbar.currentItemId = spellOrItemId;
    		end
    	end
	end
end

return castbar;