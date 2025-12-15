require('common');
require('handlers.helpers');
local imgui = require('imgui');
local gdi = require('submodules.gdifonts.include');
local ffi = require("ffi");

local gilTexture;
local gilText;
local allFonts; -- Table for batch visibility operations

-- Cached color to avoid expensive set_font_color calls every frame
local lastGilTextColor;

local giltracker = {};

--[[
* event: d3d_present
* desc : Event called when the Direct3D device is presenting a scene.
--]]
giltracker.DrawWindow = function(settings)
    -- Obtain the player entity..
    local player = GetPlayerSafe();
    local playerEnt = GetPlayerEntity();

	if (player == nil or playerEnt == nil) then
		SetFontsVisible(allFonts,false);
		return;
	end

    if (player.isZoning) then
		SetFontsVisible(allFonts,false);
        return;
	end

	local gilAmount
	local inventory = GetInventorySafe();
	if (inventory ~= nil) then
		gilAmount = inventory:GetContainerItem(0, 0);
		if (gilAmount == nil) then
			SetFontsVisible(allFonts,false);
			return;
		end
	else
		SetFontsVisible(allFonts,false);
		return;
	end

    imgui.SetNextWindowSize({ -1, -1, }, ImGuiCond_Always);
	local windowFlags = GetBaseWindowFlags(gConfig.lockPositions);

	local showIcon = settings.showIcon;

	-- For text-only mode, remove window padding so draggable area matches text exactly
	if not showIcon then
		imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
	end

    if (imgui.Begin('GilTracker', true, windowFlags)) then
		local cursorX, cursorY = imgui.GetCursorScreenPos();

		-- Dynamically set font height based on settings (avoids expensive font recreation)
		gilText:set_font_height(settings.font_settings.font_height);
		gilText:set_text(FormatInt(gilAmount.Count));

		-- Get text dimensions for positioning and draggable area
		local textWidth, textHeight = gilText:get_text_size();
		local textPadding = 5; -- Standard spacing between icon and text

		-- DEBUG: Set to true to visualize draggable areas
		local DEBUG_DRAW = false;

		if showIcon then
			-- Icon + text mode: create combined draggable area
			local iconSize = settings.iconScale;
			local iconRight = settings.iconRight;
			local rightAlign = settings.rightAlign;

			if iconRight then
				-- Icon on right: [text][icon]
				local totalWidth = textWidth + textPadding + iconSize;
				local totalHeight = math.max(iconSize, textHeight);
				imgui.Dummy({totalWidth, totalHeight});

				-- DEBUG: Draw red rectangle around draggable area
				if DEBUG_DRAW then
					local draw_list = imgui.GetWindowDrawList();
					draw_list:AddRect({cursorX, cursorY}, {cursorX + totalWidth, cursorY + totalHeight}, 0xFF0000FF, 0, 0, 2);
				end

				-- Draw icon at end of dummy area
				local draw_list = imgui.GetWindowDrawList();
				local iconX = cursorX + textWidth + textPadding;
				local iconY = cursorY + (totalHeight - iconSize) / 2;
				draw_list:AddImage(tonumber(ffi.cast("uint32_t", gilTexture.image)),
					{iconX, iconY},
					{iconX + iconSize, iconY + iconSize});

				-- Position text based on alignment
				if rightAlign then
					-- Right-aligned: position_x is right edge of text (anchored next to icon)
					gilText:set_position_x(cursorX + textWidth);
				else
					-- Left-aligned: position_x is left edge of text
					gilText:set_position_x(cursorX);
				end
				gilText:set_position_y(cursorY + (totalHeight - textHeight) / 2);
			else
				-- Icon on left: [icon][text]
				local totalWidth = iconSize + textPadding + textWidth;
				local totalHeight = math.max(iconSize, textHeight);
				imgui.Dummy({totalWidth, totalHeight});

				-- DEBUG: Draw red rectangle around draggable area
				if DEBUG_DRAW then
					local draw_list = imgui.GetWindowDrawList();
					draw_list:AddRect({cursorX, cursorY}, {cursorX + totalWidth, cursorY + totalHeight}, 0xFF0000FF, 0, 0, 2);
				end

				-- Draw icon at start of dummy area
				local draw_list = imgui.GetWindowDrawList();
				local iconY = cursorY + (totalHeight - iconSize) / 2;
				draw_list:AddImage(tonumber(ffi.cast("uint32_t", gilTexture.image)),
					{cursorX, iconY},
					{cursorX + iconSize, iconY + iconSize});

				-- Position text based on alignment
				if rightAlign then
					-- Right-aligned: position_x is right edge of text
					gilText:set_position_x(cursorX + iconSize + textPadding + textWidth);
				else
					-- Left-aligned: position_x is left edge of text
					gilText:set_position_x(cursorX + iconSize + textPadding);
				end
				gilText:set_position_y(cursorY + (totalHeight - textHeight) / 2);
			end
		else
			-- Text-only mode: create dummy for dragging that matches text size
			imgui.Dummy({textWidth, textHeight});

			-- DEBUG: Draw red rectangle around draggable area
			if DEBUG_DRAW then
				local draw_list = imgui.GetWindowDrawList();
				draw_list:AddRect({cursorX, cursorY}, {cursorX + textWidth, cursorY + textHeight}, 0xFF0000FF, 0, 0, 2);
			end

			-- Position text over the dummy area based on alignment
			if settings.rightAlign then
				-- Right-aligned: position_x is the RIGHT edge of text
				gilText:set_position_x(cursorX + textWidth);
			else
				-- Left-aligned: position_x is the LEFT edge of text
				gilText:set_position_x(cursorX);
			end
			gilText:set_position_y(cursorY);
		end

		-- Only call set_font_color if the color has changed (expensive operation for GDI fonts)
		if (lastGilTextColor ~= gConfig.colorCustomization.gilTracker.textColor) then
			gilText:set_font_color(gConfig.colorCustomization.gilTracker.textColor);
			lastGilTextColor = gConfig.colorCustomization.gilTracker.textColor;
		end

		SetFontsVisible(allFonts,true);
    end
	imgui.End();

	-- Pop style var if we pushed it for text-only mode
	if not showIcon then
		imgui.PopStyleVar(1);
	end
end

giltracker.Initialize = function(settings)
	-- Use FontManager for cleaner font creation
    gilText = FontManager.create(settings.font_settings);
	allFonts = {gilText};
	gilTexture = LoadTexture("gil");
end

giltracker.UpdateVisuals = function(settings)
	-- Use FontManager for cleaner font recreation
	gilText = FontManager.recreate(gilText, settings.font_settings);
	allFonts = {gilText};

	-- Reset cached color when font is recreated
	lastGilTextColor = nil;
end

giltracker.SetHidden = function(hidden)
	if (hidden == true) then
		SetFontsVisible(allFonts, false);
	end
end

giltracker.Cleanup = function()
	-- Use FontManager for cleaner font destruction
	gilText = FontManager.destroy(gilText);
	allFonts = nil;
end

return giltracker;
