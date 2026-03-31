require('common');
require('handlers.helpers');
local imgui = require('imgui');
local imtext = require('libs.imtext');
local ffi = require("ffi");
local defaultPositions = require('libs.defaultpositions');
local TextureManager = require('libs.texturemanager');

-- Position save/restore state
local hasAppliedSavedPosition = false;
local forcePositionReset = false;
local lastSavedPosX, lastSavedPosY = nil, nil;

-- Gil texture (loaded via TextureManager)
local gilTexture;

-- Gil per hour tracking state
local trackingStartGil = nil;
local trackingStartTime = nil;
local lastKnownGil = nil;
local lastPlayerName = nil;

-- Stabilization state (prevents false spikes on login)
local stabilizationStartTime = nil;
local stabilizationGil = nil;
local STABILIZATION_DELAY = 3;

-- Gil/hr display throttling (avoid jittery updates every frame)
local cachedGilPerHour = 0;
local cachedGilPerHourStr = '+0/hr';
local lastGilPerHourCalcTime = 0;
local GIL_PER_HOUR_UPDATE_INTERVAL = 3;

local giltracker = {};
local pending_logout = false;

local function GetLoggedInPlayerName()
    local playerIndex = AshitaCore:GetMemoryManager():GetParty():GetMemberTargetIndex(0);
    if playerIndex == 0 then
        return nil;
    end
    local entity = AshitaCore:GetMemoryManager():GetEntity();
    local flags = entity:GetRenderFlags0(playerIndex);
    local isVisible = (bit.band(flags, RENDER_FLAG_VISIBLE) == RENDER_FLAG_VISIBLE)
                   and (bit.band(flags, RENDER_FLAG_HIDDEN) == 0);
    if not isVisible then
        return nil;
    end
    local namePtr = entity:GetName(playerIndex);
    if not namePtr or namePtr == '' then
        return nil;
    end
    return namePtr;
end

--[[
* event: d3d_present
* desc : Event called when the Direct3D device is presenting a scene.
--]]
-- Helper function to format gil per hour
local function FormatGilPerHour(gilPerHour)
	local absGil = math.abs(gilPerHour);
	local prefix = gilPerHour >= 0 and '+' or '-';

	local formatted = FormatInt(math.floor(absGil));
	return prefix .. formatted .. '/hr';
end

-- Helper function to format session net change
local function FormatSessionNet(gilChange)
	local absGil = math.abs(gilChange);
	local prefix = gilChange >= 0 and '+' or '-';

	local formatted = FormatInt(math.floor(absGil));
	return prefix .. formatted;
end

giltracker.DrawWindow = function(settings)
    local player = GetPlayerSafe();
    local playerEnt = GetPlayerEntity();

	if (player == nil or playerEnt == nil) then
		return;
	end

	local loggedInName = GetLoggedInPlayerName();

	if loggedInName == nil then
		return;
	end

	-- Reset tracking on character change (switching characters) or first login after addon load
	-- This is the ONLY place session tracking resets (besides manual reset command)
	if lastPlayerName == nil then
		lastPlayerName = loggedInName;
		giltracker.ResetTracking();
	elseif lastPlayerName ~= loggedInName then
		lastPlayerName = loggedInName;
		giltracker.ResetTracking();
	end

    if (player.isZoning) then
        return;
	end

	local gilAmount
	local inventory = GetInventorySafe();
	if (inventory ~= nil) then
		gilAmount = inventory:GetContainerItem(0, 0);
		if (gilAmount == nil) then
			return;
		end
	else
		return;
	end

	local currentGil = gilAmount.Count;

	if currentGil == 0 then
		return;
	end

	if lastKnownGil ~= nil and lastKnownGil > 0 then
		local frameDiff = math.abs(currentGil - lastKnownGil);
		if frameDiff > 10000000 then
			return;
		end
	end

	-- Initialize tracking with stabilization delay (prevents false spikes on login)
	if trackingStartGil == nil then
		local now = os.clock();
		if stabilizationStartTime == nil then
			stabilizationStartTime = now;
			stabilizationGil = currentGil;
		elseif now - stabilizationStartTime >= STABILIZATION_DELAY then
			trackingStartGil = currentGil;
			trackingStartTime = now;
			stabilizationStartTime = nil;
			stabilizationGil = nil;
		end
	end

	lastKnownGil = currentGil;

	-- Calculate tracking display (throttled to avoid jittery display)
	local showGilPerHour = gConfig.gilTrackerShowGilPerHour ~= false;
	local displayMode = gConfig.gilTrackerDisplayMode or 1;
	local gilChange = cachedGilPerHour;
	local trackingText_str = cachedGilPerHourStr;
	local now = os.clock();

	if showGilPerHour and trackingStartGil ~= nil and trackingStartTime ~= nil then
		if now - lastGilPerHourCalcTime >= GIL_PER_HOUR_UPDATE_INTERVAL then
			local elapsedSeconds = now - trackingStartTime;
			local netChange = currentGil - trackingStartGil;

			if displayMode == 2 then
				if elapsedSeconds > 0 then
					local elapsedHours = elapsedSeconds / 3600;
					gilChange = netChange / elapsedHours;
					trackingText_str = FormatGilPerHour(gilChange);
				else
					gilChange = 0;
					trackingText_str = '+0/hr';
				end
			else
				gilChange = netChange;
				trackingText_str = FormatSessionNet(gilChange);
			end

			cachedGilPerHour = gilChange;
			cachedGilPerHourStr = trackingText_str;
			lastGilPerHourCalcTime = now;
		end
	elseif showGilPerHour then
		gilChange = 0;
		trackingText_str = displayMode == 2 and '+0/hr' or '+0';
	end

	local gilPerHour = gilChange;
	local gilPerHourText_str = trackingText_str;

    imgui.SetNextWindowSize({ -1, -1, }, ImGuiCond_Always);
	local windowFlags = GetBaseWindowFlags(gConfig.lockPositions);

	if forcePositionReset then
		local defX, defY = defaultPositions.GetGilTrackerPosition();
		imgui.SetNextWindowPos({defX, defY}, ImGuiCond_Always);
		forcePositionReset = false;
		hasAppliedSavedPosition = true;
		lastSavedPosX, lastSavedPosY = defX, defY;
	elseif not hasAppliedSavedPosition and gConfig.gilTrackerWindowPosX ~= nil then
		imgui.SetNextWindowPos({gConfig.gilTrackerWindowPosX, gConfig.gilTrackerWindowPosY}, ImGuiCond_Once);
		hasAppliedSavedPosition = true;
		lastSavedPosX = gConfig.gilTrackerWindowPosX;
		lastSavedPosY = gConfig.gilTrackerWindowPosY;
	end

	local showIcon = settings.showIcon;

	if not showIcon and not showGilPerHour then
		imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
	end

    ApplyWindowPosition('GilTracker');
    if (imgui.Begin('GilTracker', true, windowFlags)) then
		SaveWindowPosition('GilTracker');
		local cursorX, cursorY = imgui.GetCursorScreenPos();
		local drawList = imgui.GetWindowDrawList();

		imtext.SetConfigFromSettings(settings.font_settings);
		local fontSize = settings.font_settings.font_height;

		local textOffsetX = settings.textOffsetX or 0;
		local textOffsetY = settings.textOffsetY or 0;
		local gphOffsetX = settings.gilPerHourOffsetX or 0;
		local gphOffsetY = settings.gilPerHourOffsetY or 0;

		local gilStr = FormatInt(currentGil);
		local textWidth, textHeight = imtext.Measure(gilStr, fontSize);
		local textPadding = 5;

		local gphWidth, gphHeight = 0, 0;
		if showGilPerHour then
			gphWidth, gphHeight = imtext.Measure(gilPerHourText_str, fontSize);
		end

		local DEBUG_DRAW = false;

		local textSpacing = 2;
		local combinedTextHeight = textHeight;
		if showGilPerHour then
			combinedTextHeight = textHeight + textSpacing + gphHeight;
		end

		-- Computed draw positions (set in each layout branch, drawn at the end)
		local gilDrawX, gilDrawY;
		local gphDrawX, gphDrawY;

		if showIcon then
			local iconSize = settings.iconScale;
			local iconRight = settings.iconRight;

			local totalHeight = math.max(iconSize, combinedTextHeight);
			local textBlockStartY = cursorY + (totalHeight - combinedTextHeight) / 2;

			if iconRight then
				-- Icon on right: [text][icon]
				local textBlockWidth = textWidth;
				local totalWidth = textBlockWidth + textPadding + iconSize;

				imgui.Dummy({totalWidth, totalHeight});

				if DEBUG_DRAW then
					drawList:AddRect({cursorX, cursorY}, {cursorX + totalWidth, cursorY + totalHeight}, 0xFF0000FF, 0, 0, 2);
				end

				local iconX = cursorX + textBlockWidth + textPadding;
				local iconY = cursorY + (totalHeight - iconSize) / 2;
				drawList:AddImage(tonumber(ffi.cast("uint32_t", gilTexture.image)),
					{iconX, iconY},
					{iconX + iconSize, iconY + iconSize});

				gilDrawX = cursorX + textOffsetX;
				gilDrawY = textBlockStartY + textOffsetY;

				if showGilPerHour then
					gphDrawX = cursorX + textWidth + gphOffsetX - gphWidth;
					gphDrawY = textBlockStartY + textHeight + textSpacing + gphOffsetY;
				end
			else
				-- Icon on left: [icon][text]
				local textBlockWidth = textWidth;
				local totalWidth = iconSize + textPadding + textBlockWidth;

				imgui.Dummy({totalWidth, totalHeight});

				if DEBUG_DRAW then
					drawList:AddRect({cursorX, cursorY}, {cursorX + totalWidth, cursorY + totalHeight}, 0xFF0000FF, 0, 0, 2);
				end

				local iconY = cursorY + (totalHeight - iconSize) / 2;
				drawList:AddImage(tonumber(ffi.cast("uint32_t", gilTexture.image)),
					{cursorX, iconY},
					{cursorX + iconSize, iconY + iconSize});

				gilDrawX = cursorX + iconSize + textPadding + textOffsetX;
				gilDrawY = textBlockStartY + textOffsetY;

				if showGilPerHour then
					gphDrawX = cursorX + iconSize + textPadding + textWidth + gphOffsetX - gphWidth;
					gphDrawY = textBlockStartY + textHeight + textSpacing + gphOffsetY;
				end
			end
		else
			-- Text-only mode: no icon
			local dummyWidth = textWidth;
			local dummyHeight = combinedTextHeight;
			imgui.Dummy({dummyWidth, dummyHeight});

			if DEBUG_DRAW then
				drawList:AddRect({cursorX, cursorY}, {cursorX + dummyWidth, cursorY + dummyHeight}, 0xFF0000FF, 0, 0, 2);
			end

			gilDrawX = cursorX + textOffsetX;
			gilDrawY = cursorY + textOffsetY;

			if showGilPerHour then
				gphDrawX = cursorX + textWidth + gphOffsetX - gphWidth;
				gphDrawY = cursorY + textHeight + textSpacing + gphOffsetY;
			end
		end

		-- Draw gil amount text
		local gilColor = gConfig.colorCustomization.gilTracker.textColor;
		imtext.Draw(drawList, gilStr, gilDrawX, gilDrawY, gilColor, fontSize);

		-- Draw gil/hr or session net text
		if showGilPerHour then
			local gphColor;
			if gilPerHour >= 0 then
				gphColor = gConfig.colorCustomization.gilTracker.positiveColor or 0xFF00FF00;
			else
				gphColor = gConfig.colorCustomization.gilTracker.negativeColor or 0xFFFF0000;
			end
			imtext.Draw(drawList, gilPerHourText_str, gphDrawX, gphDrawY, gphColor, fontSize);
		end

		-- Save position if moved (with change detection to avoid spam)
		local winPosX, winPosY = imgui.GetWindowPos();
		if not gConfig.lockPositions then
			if lastSavedPosX == nil or
			   math.abs(winPosX - lastSavedPosX) > 1 or
			   math.abs(winPosY - lastSavedPosY) > 1 then
				gConfig.gilTrackerWindowPosX = winPosX;
				gConfig.gilTrackerWindowPosY = winPosY;
				lastSavedPosX = winPosX;
				lastSavedPosY = winPosY;
			end
		end
    end
	imgui.End();

	if not showIcon and not showGilPerHour then
		imgui.PopStyleVar(1);
	end
end

giltracker.Initialize = function(settings)
	gilTexture = TextureManager.getFileTexture("gil");

	trackingStartGil = nil;
	trackingStartTime = nil;
	lastKnownGil = nil;
    lastPlayerName = nil;
	stabilizationStartTime = nil;
	stabilizationGil = nil;
	cachedGilPerHour = 0;
	cachedGilPerHourStr = '+0/hr';
	lastGilPerHourCalcTime = 0;
end

giltracker.UpdateVisuals = function(settings)
	imtext.Reset();
end

giltracker.SetHidden = function(hidden)
end

giltracker.Cleanup = function()
	trackingStartGil = nil;
	trackingStartTime = nil;
	lastKnownGil = nil;
    lastPlayerName = nil;
	stabilizationStartTime = nil;
	stabilizationGil = nil;
	cachedGilPerHour = 0;
	cachedGilPerHourStr = '+0/hr';
	lastGilPerHourCalcTime = 0;
end

-- Reset gil per hour tracking to start fresh
giltracker.ResetTracking = function()
	cachedGilPerHour = 0;
	cachedGilPerHourStr = '+0/hr';
	lastGilPerHourCalcTime = 0;

	local inventory = GetInventorySafe();
	if inventory then
		local gilAmount = inventory:GetContainerItem(0, 0);
		if gilAmount and gilAmount.Count > 0 then
			trackingStartGil = gilAmount.Count;
			trackingStartTime = os.clock();
			lastKnownGil = gilAmount.Count;
			stabilizationStartTime = nil;
			stabilizationGil = nil;
			return;
		end
	end
	trackingStartGil = nil;
	trackingStartTime = nil;
	lastKnownGil = nil;
	stabilizationStartTime = nil;
	stabilizationGil = nil;
end

giltracker.ResetPositions = function()
	forcePositionReset = true;
	hasAppliedSavedPosition = false;
end

giltracker.HandleZoneOutPacket = function(e)
	pending_logout = false;
	if not e or not e.data_modified then
		return;
	end
	local readSuccess, logoutFlag = pcall(string.byte, e.data_modified, 0x04 + 1)
	if readSuccess and logoutFlag == 1 then
		pending_logout = true;
	end
end

giltracker.HandleZoneInPacket = function(e)
	if pending_logout then
		giltracker.ResetTracking();
	end
	pending_logout = false;
end

giltracker.InvalidateCache = function()
	lastGilPerHourCalcTime = 0;
end

return giltracker;
