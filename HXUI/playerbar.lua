require('common');
require('helpers');
local imgui = require('imgui');
local gdi = require('gdifonts.include');
local progressbar = require('progressbar');
local buffTable = require('bufftable');

local hpText;
local mpText;
local tpText;
local resetPosNextFrame = false;

-- Cache last set colors to avoid expensive SetColor() calls every frame
local lastHpTextColor;
local lastMpTextColor;
local lastTpTextColor;

local playerbar = {};

local _HXUI_DEV_DEBUG_INTERPOLATION = false;
local _HXUI_DEV_DEBUG_INTERPOLATION_DELAY, _HXUI_DEV_DEBUG_INTERPOLATION_NEXT_TIME;

if _HXUI_DEV_DEBUG_INTERPOLATION then
	_HXUI_DEV_DEBUG_INTERPOLATION_DELAY = 2;
	_HXUI_DEV_DEBUG_INTERPOLATION_NEXT_TIME = os.time() + _HXUI_DEV_DEBUG_INTERPOLATION_DELAY;
end

local function UpdateTextVisibility(visible)
	hpText:set_visible(visible);
	mpText:set_visible(visible);
	tpText:set_visible(visible);
end

playerbar.DrawWindow = function(settings)
    -- Obtain the player entity..
    local party = GetPartySafe();
    local player = GetPlayerSafe();
	local playerEnt = GetPlayerEntity();

	if (party == nil or player == nil or playerEnt == nil) then
		UpdateTextVisibility(false);
		return;
	end

	local currJob = player:GetMainJob();

    if (player.isZoning or currJob == 0) then
		UpdateTextVisibility(false);	
        return;
	end
	
	if (party == nil or player == nil) then
		return;
	end

	local SelfHP = party:GetMemberHP(0);
	local SelfHPMax = player:GetHPMax();
	local SelfHPPercent = math.clamp(party:GetMemberHPPercent(0), 0, 100);
	local SelfMP = party:GetMemberMP(0);
	local SelfMPMax = player:GetMPMax();
	local SelfMPPercent = math.clamp(party:GetMemberMPPercent(0), 0, 100);
	local SelfTP = party:GetMemberTP(0);

	local currentTime = os.clock();

    if playerbar.previousHPP then
    	if SelfHPPercent < playerbar.currentHPP then
    		playerbar.previousHPP = playerbar.currentHPP;
    		playerbar.currentHPP = SelfHPPercent;
    		playerbar.lastHitTime = currentTime;
    	end
    else
    	playerbar.currentHPP = SelfHPPercent;
    	playerbar.previousHPP = SelfHPPercent;
    end

    if _HXUI_DEV_DEBUG_INTERPOLATION then
	    if os.time() > _HXUI_DEV_DEBUG_INTERPOLATION_NEXT_TIME then
	    	playerbar.previousHPP = 75;
	    	playerbar.currentHPP = 50;
			playerbar.lastHitTime = currentTime;

			_HXUI_DEV_DEBUG_INTERPOLATION_NEXT_TIME = os.time() + 2;
	    end
	end

    local interpolationPercent;
    local interpolationOverlayAlpha = 0;

    if playerbar.currentHPP < playerbar.previousHPP then
    	local hppDelta = playerbar.previousHPP - playerbar.currentHPP;

    	if currentTime > playerbar.lastHitTime + settings.hitDelayLength then
    		-- local interpolationTimeTotal = settings.hitInterpolationMaxTime * (hppDelta / 100);
    		local interpolationTimeTotal = settings.hitInterpolationMaxTime;
    		local interpolationTimeElapsed = currentTime - playerbar.lastHitTime - settings.hitDelayLength;

    		if interpolationTimeElapsed <= interpolationTimeTotal then
    			local interpolationTimeElapsedPercent = easeOutPercent(interpolationTimeElapsed / interpolationTimeTotal);

    			interpolationPercent = hppDelta * (1 - interpolationTimeElapsedPercent);
    		end
    	elseif currentTime - playerbar.lastHitTime <= settings.hitDelayLength then
    		interpolationPercent = hppDelta;

			if gConfig.healthBarFlashEnabled then
				local hitDelayTime = currentTime - playerbar.lastHitTime;
				local hitDelayHalfDuration = settings.hitDelayLength / 2;

				if hitDelayTime > hitDelayHalfDuration then
					interpolationOverlayAlpha = 1 - ((hitDelayTime - hitDelayHalfDuration) / hitDelayHalfDuration);
				else
					interpolationOverlayAlpha = hitDelayTime / hitDelayHalfDuration;
				end
			end
    	end
    end

	-- Draw the player window
	if (resetPosNextFrame) then
		imgui.SetNextWindowPos({0,0});
		resetPosNextFrame = false;
	end
	
		
	local windowFlags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoBringToFrontOnFocus);
	if (gConfig.lockPositions) then
		windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
	end
    if (imgui.Begin('PlayerBar', true, windowFlags)) then

		local hpNameColor, hpGradient = GetCustomHpColors(SelfHPPercent/100, gConfig.colorCustomization.playerBar);

		local SelfJob = GetJobStr(party:GetMemberMainJob(0));
		local SelfSubJob = GetJobStr(party:GetMemberSubJob(0));
		local bShowMp = buffTable.IsSpellcaster(SelfJob) or buffTable.IsSpellcaster(SelfSubJob) or gConfig.alwaysShowMpBar;

		-- Draw HP Bar (two bars to fake animation
		local hpX = imgui.GetCursorPosX();
		local barSize = (settings.barWidth / 3) - settings.barSpacing;

		local hpPercentData = {{SelfHPPercent / 100, hpGradient}};

		if _HXUI_DEV_DEBUG_INTERPOLATION then
			hpPercentData[1][1] = 0.5;
		end

		if interpolationPercent then
			local interpolationOverlay;

			if gConfig.healthBarFlashEnabled then
				interpolationOverlay = {
					'#ffacae', -- overlay color,
					interpolationOverlayAlpha -- overlay alpha
				};
			end

			table.insert(
				hpPercentData,
				{
					interpolationPercent / 100, -- interpolation percent
					{'#cf3437', '#c54d4d'}, -- interpolation gradient
					interpolationOverlay
				}
			);
		end

		if (bShowMp == false) then
			imgui.Dummy({(barSize + settings.barSpacing) / 2, 0});

			imgui.SameLine();
		end
		
		progressbar.ProgressBar(hpPercentData, {barSize, settings.barHeight}, {decorate = gConfig.showPlayerBarBookends});
		
		imgui.SameLine();
		local hpEndX = imgui.GetCursorPosX();
		local hpLocX, hpLocY = imgui.GetCursorScreenPos();	
		if (SelfHPPercent > 0) then
			imgui.SetCursorPosX(hpX);

			imgui.SameLine();
		end

		local mpLocX
		local mpLocY;
		
		if (bShowMp) then
			-- Draw MP Bar
			imgui.SetCursorPosX(hpEndX + settings.barSpacing);
			local mpGradient = GetCustomGradient(gConfig.colorCustomization.playerBar, 'mpGradient') or {'#9abb5a', '#bfe07d'};
			progressbar.ProgressBar({{SelfMPPercent / 100, mpGradient}}, {barSize, settings.barHeight}, {decorate = gConfig.showPlayerBarBookends});
			imgui.SameLine();
			mpLocX, mpLocY  = imgui.GetCursorScreenPos()
		end

		-- Draw TP Bars
		imgui.SetCursorPosX(imgui.GetCursorPosX() + settings.barSpacing);

		local tpGradient = GetCustomGradient(gConfig.colorCustomization.playerBar, 'tpGradient') or {'#3898ce', '#78c4ee'};
		local mainPercent;
		local tpOverlay;
		
		if (SelfTP >= 1000) then
			mainPercent = (SelfTP - 1000) / 2000;

			local tpOverlayGradient = {'#0078CC', '#0078CC'};

			tpOverlay = {
				{
					1, -- overlay percent
					tpOverlayGradient -- overlay gradient
				},
				math.ceil(settings.barHeight * 2/7), -- overlay height
				1, -- overlay vertical padding
				{
					'#2fa9ff', -- overlay pulse color
					1 -- overlay pulse seconds
				}
			};
		else
			mainPercent = SelfTP / 1000;
		end
		
		progressbar.ProgressBar({{mainPercent, tpGradient}}, {barSize, settings.barHeight}, {overlayBar=tpOverlay, decorate = gConfig.showPlayerBarBookends});
		
		imgui.SameLine();

		local tpLocX, tpLocY  = imgui.GetCursorScreenPos();

		-- Dynamically set font heights based on settings (avoids expensive font recreation)
		hpText:set_font_height(settings.font_settings.font_height);
		mpText:set_font_height(settings.font_settings.font_height);
		tpText:set_font_height(settings.font_settings.font_height);

		-- Update our HP Text
		hpText:set_position_x(hpLocX - settings.barSpacing - settings.barHeight / 2);
		hpText:set_position_y(hpLocY + settings.barHeight + settings.textYOffset);
		hpText:set_text(tostring(SelfHP));
		-- Only call set_font_color if the color has changed (expensive operation for GDI fonts)
		if (lastHpTextColor ~= gConfig.colorCustomization.playerBar.hpTextColor) then
			hpText:set_font_color(gConfig.colorCustomization.playerBar.hpTextColor);
			lastHpTextColor = gConfig.colorCustomization.playerBar.hpTextColor;
		end

		hpText:set_visible(true);

		if (bShowMp) then
			-- Update our MP Text
			mpText:set_position_x(mpLocX - settings.barSpacing - settings.barHeight / 2);
			mpText:set_position_y(mpLocY + settings.barHeight + settings.textYOffset);
			mpText:set_text(tostring(SelfMP));
			-- Only call set_font_color if the color has changed
			if (lastMpTextColor ~= gConfig.colorCustomization.playerBar.mpTextColor) then
				mpText:set_font_color(gConfig.colorCustomization.playerBar.mpTextColor);
				lastMpTextColor = gConfig.colorCustomization.playerBar.mpTextColor;
			end
		end

		mpText:set_visible(bShowMp);

		-- Update our TP Text
		tpText:set_position_x(tpLocX - settings.barSpacing - settings.barHeight / 2);
		tpText:set_position_y(tpLocY + settings.barHeight + settings.textYOffset);
		tpText:set_text(tostring(SelfTP));
		local desiredTpColor = (SelfTP >= 1000) and gConfig.colorCustomization.playerBar.tpFullTextColor or gConfig.colorCustomization.playerBar.tpEmptyTextColor;
		-- Only call set_font_color if the color has changed
		if (lastTpTextColor ~= desiredTpColor) then
			tpText:set_font_color(desiredTpColor);
			lastTpTextColor = desiredTpColor;
		end

		tpText:set_visible(true);
    end
	imgui.End();
end


playerbar.Initialize = function(settings)
    hpText = gdi:create_object(settings.font_settings);
	mpText = gdi:create_object(settings.font_settings);
	tpText = gdi:create_object(settings.font_settings);
end

playerbar.UpdateFonts = function(settings)
	-- Destroy old font objects
	if (hpText ~= nil) then gdi:destroy_object(hpText); end
	if (mpText ~= nil) then gdi:destroy_object(mpText); end
	if (tpText ~= nil) then gdi:destroy_object(tpText); end

	-- Recreate font objects with new settings
    hpText = gdi:create_object(settings.font_settings);
	mpText = gdi:create_object(settings.font_settings);
	tpText = gdi:create_object(settings.font_settings);

	-- Reset cached colors when fonts are recreated
	lastHpTextColor = nil;
	lastMpTextColor = nil;
	lastTpTextColor = nil;
end

playerbar.SetHidden = function(hidden)
	if (hidden == true) then
		UpdateTextVisibility(false);
	end
end

playerbar.Cleanup = function()
	-- Destroy all font objects on unload
	if (hpText ~= nil) then gdi:destroy_object(hpText); hpText = nil; end
	if (mpText ~= nil) then gdi:destroy_object(mpText); mpText = nil; end
	if (tpText ~= nil) then gdi:destroy_object(tpText); tpText = nil; end
end

return playerbar;