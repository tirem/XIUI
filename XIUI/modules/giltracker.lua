require('common');
require('handlers.helpers');
local imgui = require('imgui');
local gdi = require('submodules.gdifonts.include');
local ffi = require("ffi");

local gilTexture;
local gilText;
local gilPerHourText;
local allFonts; -- Table for batch visibility operations

-- Cached color to avoid expensive set_font_color calls every frame
local lastGilTextColor;
local lastGilPerHourColor;

-- Gil per hour tracking state
local trackingStartGil = nil;      -- Gil amount when tracking started
local trackingStartTime = nil;     -- os.clock() when tracking started
local lastKnownGil = nil;          -- Last known gil (to detect login/character change)

local giltracker = {};

--[[
* event: d3d_present
* desc : Event called when the Direct3D device is presenting a scene.
--]]
-- Helper function to format gil per hour
local function FormatGilPerHour(gilPerHour)
	local absGil = math.abs(gilPerHour);
	local prefix = gilPerHour >= 0 and '+' or '-';

	-- Format with thousand separators
	local formatted = FormatInt(math.floor(absGil));
	return prefix .. formatted .. '/hr';
end

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

	local currentGil = gilAmount.Count;

	-- Initialize tracking on first valid read (login reset)
	if trackingStartGil == nil then
		trackingStartGil = currentGil;
		trackingStartTime = os.clock();
		lastKnownGil = currentGil;
	end

	-- Calculate gil per hour
	local showGilPerHour = gConfig.gilTrackerShowGilPerHour ~= false;
	local gilPerHour = 0;
	local gilPerHourText_str = '';

	if showGilPerHour then
		local elapsedSeconds = os.clock() - trackingStartTime;
		local gilChange = currentGil - trackingStartGil;

		if elapsedSeconds > 0 then
			local elapsedHours = elapsedSeconds / 3600;
			gilPerHour = gilChange / elapsedHours;
			gilPerHourText_str = FormatGilPerHour(gilPerHour);
		else
			gilPerHourText_str = '+0/hr';
		end
	end

    imgui.SetNextWindowSize({ -1, -1, }, ImGuiCond_Always);
	local windowFlags = GetBaseWindowFlags(gConfig.lockPositions);

	local showIcon = settings.showIcon;

	-- For text-only mode, remove window padding so draggable area matches text exactly
	if not showIcon and not showGilPerHour then
		imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
	end

    if (imgui.Begin('GilTracker', true, windowFlags)) then
		local cursorX, cursorY = imgui.GetCursorScreenPos();

		-- Get offset settings from adjusted settings (same pattern as targetbar)
		local textOffsetX = settings.textOffsetX or 0;
		local textOffsetY = settings.textOffsetY or 0;
		local gphOffsetX = settings.gilPerHourOffsetX or 0;
		local gphOffsetY = settings.gilPerHourOffsetY or 0;

		-- Dynamically set font height based on settings (avoids expensive font recreation)
		gilText:set_font_height(settings.font_settings.font_height);
		gilText:set_text(FormatInt(currentGil));

		-- Get text dimensions for positioning and draggable area
		local textWidth, textHeight = gilText:get_text_size();
		local textPadding = 5; -- Standard spacing between icon and text

		-- Prepare gil per hour text dimensions if enabled
		local gphWidth, gphHeight = 0, 0;
		if showGilPerHour then
			gilPerHourText:set_font_height(settings.font_settings.font_height);
			gilPerHourText:set_text(gilPerHourText_str);
			gphWidth, gphHeight = gilPerHourText:get_text_size();
		end

		-- DEBUG: Set to true to visualize draggable areas
		local DEBUG_DRAW = false;

		-- Calculate combined text height when showing gil/hr (for proper icon centering)
		local textSpacing = 2; -- Spacing between gil amount and gil/hr
		local combinedTextHeight = textHeight;
		if showGilPerHour then
			combinedTextHeight = textHeight + textSpacing + gphHeight;
		end

		if showIcon then
			-- Icon + text mode: create combined draggable area
			local iconSize = settings.iconScale;
			local iconRight = settings.iconRight;
			local rightAlign = settings.rightAlign;

			-- Total height is max of icon and combined text height
			local totalHeight = math.max(iconSize, combinedTextHeight);

			-- Calculate where text block starts (centered within totalHeight)
			local textBlockStartY = cursorY + (totalHeight - combinedTextHeight) / 2;

			if iconRight then
				-- Icon on right: [text][icon]
				-- Use textWidth only (not max with gphWidth) so icon position stays stable
				local textBlockWidth = textWidth;
				local totalWidth = textBlockWidth + textPadding + iconSize;

				imgui.Dummy({totalWidth, totalHeight});

				-- DEBUG: Draw red rectangle around draggable area
				if DEBUG_DRAW then
					local draw_list = imgui.GetWindowDrawList();
					draw_list:AddRect({cursorX, cursorY}, {cursorX + totalWidth, cursorY + totalHeight}, 0xFF0000FF, 0, 0, 2);
				end

				-- Draw icon centered vertically, positioned after text block
				local draw_list = imgui.GetWindowDrawList();
				local iconX = cursorX + textBlockWidth + textPadding;
				local iconY = cursorY + (totalHeight - iconSize) / 2;
				draw_list:AddImage(tonumber(ffi.cast("uint32_t", gilTexture.image)),
					{iconX, iconY},
					{iconX + iconSize, iconY + iconSize});

				-- Position gil amount text
				local gilTextX, gilTextY;
				if rightAlign then
					gilTextX = cursorX + textWidth + textOffsetX;
				else
					gilTextX = cursorX + textOffsetX;
				end
				gilTextY = textBlockStartY + textOffsetY;
				gilText:set_position_x(gilTextX);
				gilText:set_position_y(gilTextY);

				-- Position gil/hr text below gil amount (right-aligned to match gil text's right edge)
				if showGilPerHour then
					-- gilPerHourText is right-aligned, so position_x is the RIGHT edge
					-- Align to gil amount's right edge: cursorX + textWidth
					local gphX = cursorX + textWidth + gphOffsetX;
					local gphY = textBlockStartY + textHeight + textSpacing + gphOffsetY;
					gilPerHourText:set_position_x(gphX);
					gilPerHourText:set_position_y(gphY);
				end
			else
				-- Icon on left: [icon][text]
				-- Use textWidth only (not max with gphWidth) so icon position stays stable
				local textBlockWidth = textWidth;
				local totalWidth = iconSize + textPadding + textBlockWidth;

				imgui.Dummy({totalWidth, totalHeight});

				-- DEBUG: Draw red rectangle around draggable area
				if DEBUG_DRAW then
					local draw_list = imgui.GetWindowDrawList();
					draw_list:AddRect({cursorX, cursorY}, {cursorX + totalWidth, cursorY + totalHeight}, 0xFF0000FF, 0, 0, 2);
				end

				-- Draw icon centered vertically, at start
				local draw_list = imgui.GetWindowDrawList();
				local iconY = cursorY + (totalHeight - iconSize) / 2;
				draw_list:AddImage(tonumber(ffi.cast("uint32_t", gilTexture.image)),
					{cursorX, iconY},
					{cursorX + iconSize, iconY + iconSize});

				-- Position gil amount text after icon
				local gilTextX, gilTextY;
				if rightAlign then
					gilTextX = cursorX + iconSize + textPadding + textWidth + textOffsetX;
				else
					gilTextX = cursorX + iconSize + textPadding + textOffsetX;
				end
				gilTextY = textBlockStartY + textOffsetY;
				gilText:set_position_x(gilTextX);
				gilText:set_position_y(gilTextY);

				-- Position gil/hr text below gil amount (right-aligned to match gil text's right edge)
				if showGilPerHour then
					-- gilPerHourText is right-aligned, so position_x is the RIGHT edge
					-- Align to gil amount's right edge: cursorX + iconSize + textPadding + textWidth
					local gphX = cursorX + iconSize + textPadding + textWidth + gphOffsetX;
					local gphY = textBlockStartY + textHeight + textSpacing + gphOffsetY;
					gilPerHourText:set_position_x(gphX);
					gilPerHourText:set_position_y(gphY);
				end
			end
		else
			-- Text-only mode: no icon
			-- Use textWidth only for dummy so position stays stable
			local dummyWidth = textWidth;
			local dummyHeight = combinedTextHeight;
			imgui.Dummy({dummyWidth, dummyHeight});

			-- DEBUG: Draw red rectangle around draggable area
			if DEBUG_DRAW then
				local draw_list = imgui.GetWindowDrawList();
				draw_list:AddRect({cursorX, cursorY}, {cursorX + dummyWidth, cursorY + dummyHeight}, 0xFF0000FF, 0, 0, 2);
			end

			-- Position gil amount text at top
			local gilTextX, gilTextY;
			if settings.rightAlign then
				gilTextX = cursorX + textWidth + textOffsetX;
			else
				gilTextX = cursorX + textOffsetX;
			end
			gilTextY = cursorY + textOffsetY;
			gilText:set_position_x(gilTextX);
			gilText:set_position_y(gilTextY);

			-- Position gil/hr text below gil amount (right-aligned to match gil text's right edge)
			if showGilPerHour then
				-- gilPerHourText is right-aligned, so position_x is the RIGHT edge
				-- Align to gil amount's right edge: cursorX + textWidth
				local gphX = cursorX + textWidth + gphOffsetX;
				local gphY = cursorY + textHeight + textSpacing + gphOffsetY;
				gilPerHourText:set_position_x(gphX);
				gilPerHourText:set_position_y(gphY);
			end
		end

		-- Only call set_font_color if the color has changed (expensive operation for GDI fonts)
		if (lastGilTextColor ~= gConfig.colorCustomization.gilTracker.textColor) then
			gilText:set_font_color(gConfig.colorCustomization.gilTracker.textColor);
			lastGilTextColor = gConfig.colorCustomization.gilTracker.textColor;
		end

		-- Set gil/hr visibility and color
		if showGilPerHour then

			-- Set color based on positive/negative (green for positive, red for negative)
			local gphColor;
			if gilPerHour >= 0 then
				gphColor = gConfig.colorCustomization.gilTracker.positiveColor or 0xFF00FF00; -- Green
			else
				gphColor = gConfig.colorCustomization.gilTracker.negativeColor or 0xFFFF0000; -- Red
			end

			if lastGilPerHourColor ~= gphColor then
				gilPerHourText:set_font_color(gphColor);
				lastGilPerHourColor = gphColor;
			end

			gilPerHourText:set_visible(true);
		else
			if gilPerHourText then
				gilPerHourText:set_visible(false);
			end
		end

		gilText:set_visible(true);
    end
	imgui.End();

	-- Pop style var if we pushed it for text-only mode
	if not showIcon and not showGilPerHour then
		imgui.PopStyleVar(1);
	end
end

giltracker.Initialize = function(settings)
	-- Use FontManager for cleaner font creation
    gilText = FontManager.create(settings.font_settings);

	-- Create font for gil per hour with RIGHT alignment (so it grows left, not pushing icon)
	local gphFontSettings = deep_copy_table(settings.font_settings);
	gphFontSettings.font_alignment = gdi.Alignment.Right;
	gilPerHourText = FontManager.create(gphFontSettings);

	allFonts = {gilText, gilPerHourText};
	gilTexture = LoadTexture("gil");

	-- Reset tracking state on initialize (fresh login)
	trackingStartGil = nil;
	trackingStartTime = nil;
	lastKnownGil = nil;
end

giltracker.UpdateVisuals = function(settings)
	-- Use FontManager for cleaner font recreation
	gilText = FontManager.recreate(gilText, settings.font_settings);

	-- Recreate gil per hour font with RIGHT alignment
	local gphFontSettings = deep_copy_table(settings.font_settings);
	gphFontSettings.font_alignment = gdi.Alignment.Right;
	gilPerHourText = FontManager.recreate(gilPerHourText, gphFontSettings);

	allFonts = {gilText, gilPerHourText};

	-- Reset cached colors when fonts are recreated
	lastGilTextColor = nil;
	lastGilPerHourColor = nil;
end

giltracker.SetHidden = function(hidden)
	if (hidden == true) then
		SetFontsVisible(allFonts, false);
	end
end

giltracker.Cleanup = function()
	-- Use FontManager for cleaner font destruction
	gilText = FontManager.destroy(gilText);
	gilPerHourText = FontManager.destroy(gilPerHourText);
	allFonts = nil;

	-- Clear tracking state
	trackingStartGil = nil;
	trackingStartTime = nil;
	lastKnownGil = nil;
end

-- Reset gil per hour tracking to start fresh
giltracker.ResetTracking = function()
	-- Get current gil amount
	local inventory = GetInventorySafe();
	if inventory then
		local gilAmount = inventory:GetContainerItem(0, 0);
		if gilAmount then
			trackingStartGil = gilAmount.Count;
			trackingStartTime = os.clock();
			lastKnownGil = gilAmount.Count;
			print('[XIUI] Gil per hour tracking reset.');
			return;
		end
	end
	-- If we can't get current gil, just reset the tracking state
	-- It will reinitialize on next DrawWindow call
	trackingStartGil = nil;
	trackingStartTime = nil;
	lastKnownGil = nil;
	print('[XIUI] Gil per hour tracking reset (will reinitialize).');
end

return giltracker;
