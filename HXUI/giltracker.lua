require('common');
local imgui = require('imgui');
local gdi = require('gdifonts.include');
local ffi = require("ffi");

local gilTexture;
local gilText;

-- Cached color to avoid expensive set_font_color calls every frame
local lastGilTextColor;

local giltracker = {};

local function UpdateTextVisibility(visible)
	gilText:set_visible(visible);
end

--[[
* event: d3d_present
* desc : Event called when the Direct3D device is presenting a scene.
--]]
giltracker.DrawWindow = function(settings)
    -- Obtain the player entity..
    local player = GetPlayerSafe();
    local playerEnt = GetPlayerEntity();

	if (player == nil or playerEnt == nil) then
		UpdateTextVisibility(false);
		return;
	end

    if (player.isZoning) then
		UpdateTextVisibility(false);
        return;
	end

	local gilAmount
	local inventory = GetInventorySafe();
	if (inventory ~= nil) then
		gilAmount = inventory:GetContainerItem(0, 0);
		if (gilAmount == nil) then
			UpdateTextVisibility(false);
			return;
		end
	else
		UpdateTextVisibility(false);
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
        local posOffsetX = (settings.font_settings.font_alignment == gdi.Alignment.Right) and settings.offsetX or settings.offsetX + settings.iconScale;
		gilText:set_position_x(cursorX + posOffsetX);
		gilText:set_position_y(cursorY + (settings.iconScale/2) + settings.offsetY);
		-- Only call set_font_color if the color has changed (expensive operation for GDI fonts)
		if (lastGilTextColor ~= gConfig.colorCustomization.gilTracker.textColor) then
			gilText:set_font_color(gConfig.colorCustomization.gilTracker.textColor);
			lastGilTextColor = gConfig.colorCustomization.gilTracker.textColor;
		end

		UpdateTextVisibility(true);
    end
	imgui.End();
end

giltracker.Initialize = function(settings)
    gilText = gdi:create_object(settings.font_settings);
	gilTexture = LoadTexture("gil");
end

giltracker.UpdateFonts = function(settings)
	-- Destroy old font object
	if (gilText ~= nil) then gdi:destroy_object(gilText); end

	-- Recreate font object with new settings
    gilText = gdi:create_object(settings.font_settings);

	-- Reset cached color when font is recreated
	lastGilTextColor = nil;
end

giltracker.SetHidden = function(hidden)
	if (hidden == true) then
		UpdateTextVisibility(false);
	end
end

giltracker.Cleanup = function()
	-- Destroy all font objects on unload
	if (gilText ~= nil) then gdi:destroy_object(gilText); gilText = nil; end
end

return giltracker;