require('common');
require('helpers');
local imgui = require('imgui');
local gdi = require('gdifonts.include');
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
	local windowFlags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoBringToFrontOnFocus);
	if (gConfig.lockPositions) then
		windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
	end
    if (imgui.Begin('GilTracker', true, windowFlags)) then
		local cursorX, cursorY  = imgui.GetCursorScreenPos();
		imgui.Image(tonumber(ffi.cast("uint32_t", gilTexture.image)), { settings.iconScale, settings.iconScale });

		-- Dynamically set font height based on settings (avoids expensive font recreation)
		gilText:set_font_height(settings.font_settings.font_height);

		gilText:set_text(FormatInt(gilAmount.Count));

		-- Clean positioning logic:
		-- rightAlign = true: text positioned to the RIGHT of the icon (left-aligned text)
		-- rightAlign = false: text positioned to the LEFT of the icon (right-aligned text)
		local textPadding = 5; -- Standard spacing between icon and text
		if (settings.rightAlign) then
			-- Text on RIGHT side of icon
			gilText:set_position_x(cursorX + settings.iconScale + textPadding);
		else
			-- Text on LEFT side of icon
			gilText:set_position_x(cursorX - textPadding);
		end
		-- Vertically center the text with the icon (offset upward to account for font baseline)
		gilText:set_position_y(cursorY + (settings.iconScale / 2) - (settings.font_settings.font_height / 2));

		-- Only call set_font_color if the color has changed (expensive operation for GDI fonts)
		if (lastGilTextColor ~= gConfig.colorCustomization.gilTracker.textColor) then
			gilText:set_font_color(gConfig.colorCustomization.gilTracker.textColor);
			lastGilTextColor = gConfig.colorCustomization.gilTracker.textColor;
		end

		SetFontsVisible(allFonts,true);
    end
	imgui.End();
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