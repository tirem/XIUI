require('common');
local imgui = require('imgui');
local fonts = require('fonts');
local ffi = require("ffi");

local gilTexture;
local gilText;

local giltracker = {};

local function UpdateTextVisibility(visible)
	gilText:SetVisible(visible);
end

--[[
* event: d3d_present
* desc : Event called when the Direct3D device is presenting a scene.
--]]
giltracker.DrawWindow = function(settings)
    -- Obtain the player entity..
    local player = AshitaCore:GetMemoryManager():GetPlayer();
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
	local inventory = AshitaCore:GetMemoryManager():GetInventory();
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

		gilText:SetText(FormatInt(gilAmount.Count));
        local posOffsetX = settings.font_settings.right_justified and settings.offsetX or settings.offsetX + settings.iconScale;
		gilText:SetPositionX(cursorX + posOffsetX);
		gilText:SetPositionY(cursorY + (settings.iconScale/2) + settings.offsetY);

		UpdateTextVisibility(true);
    end
	imgui.End();
end

giltracker.Initialize = function(settings)
    gilText = fonts.new(settings.font_settings);
	gilTexture = LoadTexture("gil");
end

giltracker.UpdateFonts = function(settings)
    gilText:SetFontHeight(settings.font_settings.font_height);
    gilText:SetRightJustified(settings.font_settings.right_justified);
end

giltracker.SetHidden = function(hidden)
	if (hidden == true) then
		UpdateTextVisibility(false);
	end
end

return giltracker;