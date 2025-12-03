require('common');
require('helpers');
local imgui = require('imgui');
local gdi = require('gdifonts.include');
local progressbar = require('progressbar');
local buffTable = require('bufftable');

local hpText;
local mpText;
local tpText;
local allFonts; -- Table for batch visibility operations
local resetPosNextFrame = false;

-- Cache last set colors to avoid expensive SetColor() calls every frame
local lastHpTextColor;
local lastMpTextColor;
local lastTpTextColor;

-- Reference text height for baseline alignment (prevents text jumping)
local referenceTextHeight = 0;

local playerbar = {
	interpolation = {}
};

local _XIUI_DEV_DEBUG_INTERPOLATION = false;
local _XIUI_DEV_DEBUG_INTERPOLATION_DELAY, _XIUI_DEV_DEBUG_INTERPOLATION_NEXT_TIME;

if _XIUI_DEV_DEBUG_INTERPOLATION then
	_XIUI_DEV_DEBUG_INTERPOLATION_DELAY = 2;
	_XIUI_DEV_DEBUG_INTERPOLATION_NEXT_TIME = os.time() + _XIUI_DEV_DEBUG_INTERPOLATION_DELAY;
end

playerbar.DrawWindow = function(settings)
    -- Obtain the player entity..
    local party = GetPartySafe();
    local player = GetPlayerSafe();
	local playerEnt = GetPlayerEntity();

	if (party == nil or player == nil or playerEnt == nil) then
		SetFontsVisible(allFonts, false);
		return;
	end

	local currJob = player:GetMainJob();

    if (player.isZoning or currJob == 0) then
		SetFontsVisible(allFonts, false);
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

	-- Initialize interpolation if not set
	if not playerbar.interpolation.currentHpp then
		playerbar.interpolation.currentHpp = SelfHPPercent;
		playerbar.interpolation.interpolationDamagePercent = 0;
		playerbar.interpolation.interpolationHealPercent = 0;
	end

	-- If the player takes damage
	if SelfHPPercent < playerbar.interpolation.currentHpp then
		local previousInterpolationDamagePercent = playerbar.interpolation.interpolationDamagePercent;

		local damageAmount = playerbar.interpolation.currentHpp - SelfHPPercent;

		playerbar.interpolation.interpolationDamagePercent = playerbar.interpolation.interpolationDamagePercent + damageAmount;

		if previousInterpolationDamagePercent > 0 and playerbar.interpolation.lastHitAmount and damageAmount > playerbar.interpolation.lastHitAmount then
			playerbar.interpolation.lastHitTime = currentTime;
			playerbar.interpolation.lastHitAmount = damageAmount;
		elseif previousInterpolationDamagePercent == 0 then
			playerbar.interpolation.lastHitTime = currentTime;
			playerbar.interpolation.lastHitAmount = damageAmount;
		end

		if not playerbar.interpolation.lastHitTime or currentTime > playerbar.interpolation.lastHitTime + (settings.hitFlashDuration * 0.25) then
			playerbar.interpolation.lastHitTime = currentTime;
			playerbar.interpolation.lastHitAmount = damageAmount;
		end

		-- If we previously were interpolating with an empty bar, reset the hit delay effect
		if previousInterpolationDamagePercent == 0 then
			playerbar.interpolation.hitDelayStartTime = currentTime;
		end

		-- Clear healing interpolation when taking damage
		playerbar.interpolation.interpolationHealPercent = 0;
		playerbar.interpolation.healDelayStartTime = nil;
	elseif SelfHPPercent > playerbar.interpolation.currentHpp then
		-- If the player heals
		local previousInterpolationHealPercent = playerbar.interpolation.interpolationHealPercent;

		local healAmount = SelfHPPercent - playerbar.interpolation.currentHpp;

		playerbar.interpolation.interpolationHealPercent = playerbar.interpolation.interpolationHealPercent + healAmount;

		if previousInterpolationHealPercent > 0 and playerbar.interpolation.lastHealAmount and healAmount > playerbar.interpolation.lastHealAmount then
			playerbar.interpolation.lastHealTime = currentTime;
			playerbar.interpolation.lastHealAmount = healAmount;
		elseif previousInterpolationHealPercent == 0 then
			playerbar.interpolation.lastHealTime = currentTime;
			playerbar.interpolation.lastHealAmount = healAmount;
		end

		if not playerbar.interpolation.lastHealTime or currentTime > playerbar.interpolation.lastHealTime + (settings.hitFlashDuration * 0.25) then
			playerbar.interpolation.lastHealTime = currentTime;
			playerbar.interpolation.lastHealAmount = healAmount;
		end

		-- If we previously were interpolating with an empty bar, reset the heal delay effect
		if previousInterpolationHealPercent == 0 then
			playerbar.interpolation.healDelayStartTime = currentTime;
		end

		-- Clear damage interpolation when healing
		playerbar.interpolation.interpolationDamagePercent = 0;
		playerbar.interpolation.hitDelayStartTime = nil;
	end

	playerbar.interpolation.currentHpp = SelfHPPercent;

	-- Reduce the damage HP amount to display based on the time passed since last frame
	if playerbar.interpolation.interpolationDamagePercent > 0 and playerbar.interpolation.hitDelayStartTime and currentTime > playerbar.interpolation.hitDelayStartTime + settings.hitDelayDuration then
		if playerbar.interpolation.lastFrameTime then
			local deltaTime = currentTime - playerbar.interpolation.lastFrameTime;

			local animSpeed = 0.1 + (0.9 * (playerbar.interpolation.interpolationDamagePercent / 100));

			playerbar.interpolation.interpolationDamagePercent = playerbar.interpolation.interpolationDamagePercent - (settings.hitInterpolationDecayPercentPerSecond * deltaTime * animSpeed);

			-- Clamp our percent to 0
			playerbar.interpolation.interpolationDamagePercent = math.max(0, playerbar.interpolation.interpolationDamagePercent);
		end
	end

	-- Reduce the healing HP amount to display based on the time passed since last frame
	if playerbar.interpolation.interpolationHealPercent > 0 and playerbar.interpolation.healDelayStartTime and currentTime > playerbar.interpolation.healDelayStartTime + settings.hitDelayDuration then
		if playerbar.interpolation.lastFrameTime then
			local deltaTime = currentTime - playerbar.interpolation.lastFrameTime;

			local animSpeed = 0.1 + (0.9 * (playerbar.interpolation.interpolationHealPercent / 100));

			playerbar.interpolation.interpolationHealPercent = playerbar.interpolation.interpolationHealPercent - (settings.hitInterpolationDecayPercentPerSecond * deltaTime * animSpeed);

			-- Clamp our percent to 0
			playerbar.interpolation.interpolationHealPercent = math.max(0, playerbar.interpolation.interpolationHealPercent);
		end
	end

	-- Calculate damage flash overlay alpha
	local interpolationOverlayAlpha = 0;
	if gConfig.healthBarFlashEnabled then
		if playerbar.interpolation.lastHitTime and currentTime < playerbar.interpolation.lastHitTime + settings.hitFlashDuration then
			local hitFlashTime = currentTime - playerbar.interpolation.lastHitTime;
			local hitFlashTimePercent = hitFlashTime / settings.hitFlashDuration;

			local maxAlphaHitPercent = 20;
			local maxAlpha = math.min(playerbar.interpolation.lastHitAmount, maxAlphaHitPercent) / maxAlphaHitPercent;

			maxAlpha = math.max(maxAlpha * 0.6, 0.4);

			interpolationOverlayAlpha = math.pow(1 - hitFlashTimePercent, 2) * maxAlpha;
		end
	end

	-- Calculate healing flash overlay alpha
	local healInterpolationOverlayAlpha = 0;
	if gConfig.healthBarFlashEnabled then
		if playerbar.interpolation.lastHealTime and currentTime < playerbar.interpolation.lastHealTime + settings.hitFlashDuration then
			local healFlashTime = currentTime - playerbar.interpolation.lastHealTime;
			local healFlashTimePercent = healFlashTime / settings.hitFlashDuration;

			local maxAlphaHealPercent = 20;
			local maxAlpha = math.min(playerbar.interpolation.lastHealAmount, maxAlphaHealPercent) / maxAlphaHealPercent;

			maxAlpha = math.max(maxAlpha * 0.6, 0.4);

			healInterpolationOverlayAlpha = math.pow(1 - healFlashTimePercent, 2) * maxAlpha;
		end
	end

	playerbar.interpolation.lastFrameTime = currentTime;

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

		-- Calculate bookend width and text padding (same as exp bar)
		local bookendWidth = gConfig.showPlayerBarBookends and (settings.barHeight / 2) or 0;
		local textPadding = 8;

		-- Calculate base HP for display (subtract healing to show old HP during heal animation)
		local baseHpPercent = SelfHPPercent;
		if playerbar.interpolation.interpolationHealPercent and playerbar.interpolation.interpolationHealPercent > 0 then
			baseHpPercent = SelfHPPercent - playerbar.interpolation.interpolationHealPercent;
			baseHpPercent = math.max(0, baseHpPercent); -- Clamp to 0
		end

		local hpPercentData = {{baseHpPercent / 100, hpGradient}};

		-- Add interpolation bar for damage taken
		if playerbar.interpolation.interpolationDamagePercent and playerbar.interpolation.interpolationDamagePercent > 0 then
			local interpolationOverlay;

			if gConfig.healthBarFlashEnabled and interpolationOverlayAlpha > 0 then
				interpolationOverlay = {
					'#ffacae', -- overlay color,
					interpolationOverlayAlpha -- overlay alpha
				};
			end

			table.insert(
				hpPercentData,
				{
					playerbar.interpolation.interpolationDamagePercent / 100, -- interpolation percent
					{'#cf3437', '#c54d4d'}, -- interpolation gradient (red)
					interpolationOverlay
				}
			);
		end

		-- Add interpolation bar for healing received
		if playerbar.interpolation.interpolationHealPercent and playerbar.interpolation.interpolationHealPercent > 0 then
			local healInterpolationOverlay;

			if gConfig.healthBarFlashEnabled and healInterpolationOverlayAlpha > 0 then
				healInterpolationOverlay = {
					'#c8ffc8', -- overlay color (light green),
					healInterpolationOverlayAlpha -- overlay alpha
				};
			end

			table.insert(
				hpPercentData,
				{
					playerbar.interpolation.interpolationHealPercent / 100, -- interpolation percent
					{'#4ade80', '#86efac'}, -- interpolation gradient (green)
					healInterpolationOverlay
				}
			);
		end

		if (bShowMp == false) then
			imgui.Dummy({(barSize + settings.barSpacing) / 2, 0});

			imgui.SameLine();
		end

		-- Capture HP bar start position
		local hpBarStartX, hpBarStartY = imgui.GetCursorScreenPos();
		progressbar.ProgressBar(hpPercentData, {barSize, settings.barHeight}, {decorate = gConfig.showPlayerBarBookends});

		imgui.SameLine();
		local hpEndX = imgui.GetCursorPosX();	
		if (SelfHPPercent > 0) then
			imgui.SetCursorPosX(hpX);

			imgui.SameLine();
		end

		local mpBarStartX, mpBarStartY;

		if (bShowMp) then
			-- Draw MP Bar
			imgui.SetCursorPosX(hpEndX + settings.barSpacing);
			-- Capture MP bar start position
			mpBarStartX, mpBarStartY = imgui.GetCursorScreenPos();
			local mpGradient = GetCustomGradient(gConfig.colorCustomization.playerBar, 'mpGradient') or {'#9abb5a', '#bfe07d'};
			progressbar.ProgressBar({{SelfMPPercent / 100, mpGradient}}, {barSize, settings.barHeight}, {decorate = gConfig.showPlayerBarBookends});
			imgui.SameLine();
		end

		-- Draw TP Bars
		imgui.SetCursorPosX(imgui.GetCursorPosX() + settings.barSpacing);

		-- Capture TP bar start position
		local tpBarStartX, tpBarStartY = imgui.GetCursorScreenPos();

		local tpGradient = GetCustomGradient(gConfig.colorCustomization.playerBar, 'tpGradient') or {'#3898ce', '#78c4ee'};
		local mainPercent;
		local tpOverlay;

		if (SelfTP >= 1000) then
			mainPercent = (SelfTP - 1000) / 2000;

			local tpOverlayGradient = {'#0078CC', '#0078CC'};

		local tpPulseConfig = nil;
		if gConfig.tpBarFlashEnabled then
			tpPulseConfig = {
				'#2fa9ff', -- overlay pulse color
				1 -- overlay pulse seconds
			};
		end

			tpOverlay = {
				{
					1, -- overlay percent
					tpOverlayGradient -- overlay gradient
				},
				math.ceil(settings.barHeight * 2/7), -- overlay height
				1, -- overlay vertical padding
			tpPulseConfig
			};
		else
			mainPercent = SelfTP / 1000;
		end

		progressbar.ProgressBar({{mainPercent, tpGradient}}, {barSize, settings.barHeight}, {overlayBar=tpOverlay, decorate = gConfig.showPlayerBarBookends});

		imgui.SameLine();

		-- Dynamically set font heights based on settings (avoids expensive font recreation)
		hpText:set_font_height(settings.font_settings.font_height);
		mpText:set_font_height(settings.font_settings.font_height);
		tpText:set_font_height(settings.font_settings.font_height);

		-- Calculate reference height for baseline alignment (only once per font height change)
		if referenceTextHeight == 0 or referenceTextHeight ~= settings.font_settings.font_height then
			hpText:set_text("0123456789");
			local _, refHeight = hpText:get_text_size();
			referenceTextHeight = refHeight;
		end

		-- Update our HP Text (using proper padding like exp bar)
		local hpTextX = hpBarStartX + barSize - bookendWidth - textPadding;
		local hpTextY = hpBarStartY + settings.barHeight + settings.textYOffset;
		hpText:set_text(tostring(SelfHP));
		-- Apply baseline offset to keep text baseline consistent
		local _, hpTextHeight = hpText:get_text_size();
		local hpBaselineOffset = referenceTextHeight - hpTextHeight;
		hpText:set_position_x(hpTextX);
		hpText:set_position_y(hpTextY + hpBaselineOffset);
		-- Only call set_font_color if the color has changed (expensive operation for GDI fonts)
		if (lastHpTextColor ~= gConfig.colorCustomization.playerBar.hpTextColor) then
			hpText:set_font_color(gConfig.colorCustomization.playerBar.hpTextColor);
			lastHpTextColor = gConfig.colorCustomization.playerBar.hpTextColor;
		end

		hpText:set_visible(true);

		if (bShowMp) then
			-- Update our MP Text (using proper padding like exp bar)
			local mpTextX = mpBarStartX + barSize - bookendWidth - textPadding;
			local mpTextY = mpBarStartY + settings.barHeight + settings.textYOffset;
			mpText:set_text(tostring(SelfMP));
			-- Apply baseline offset to keep text baseline consistent
			local _, mpTextHeight = mpText:get_text_size();
			local mpBaselineOffset = referenceTextHeight - mpTextHeight;
			mpText:set_position_x(mpTextX);
			mpText:set_position_y(mpTextY + mpBaselineOffset);
			-- Only call set_font_color if the color has changed
			if (lastMpTextColor ~= gConfig.colorCustomization.playerBar.mpTextColor) then
				mpText:set_font_color(gConfig.colorCustomization.playerBar.mpTextColor);
				lastMpTextColor = gConfig.colorCustomization.playerBar.mpTextColor;
			end
		end

		mpText:set_visible(bShowMp);

		-- Update our TP Text (using proper padding like exp bar)
		local tpTextX = tpBarStartX + barSize - bookendWidth - textPadding;
		local tpTextY = tpBarStartY + settings.barHeight + settings.textYOffset;
		tpText:set_text(tostring(SelfTP));
		-- Apply baseline offset to keep text baseline consistent
		local _, tpTextHeight = tpText:get_text_size();
		local tpBaselineOffset = referenceTextHeight - tpTextHeight;
		tpText:set_position_x(tpTextX);
		tpText:set_position_y(tpTextY + tpBaselineOffset);
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
	-- Use FontManager for cleaner font creation
    hpText = FontManager.create(settings.font_settings);
	mpText = FontManager.create(settings.font_settings);
	tpText = FontManager.create(settings.font_settings);
	allFonts = {hpText, mpText, tpText};
end

playerbar.UpdateVisuals = function(settings)
	-- Use FontManager for cleaner font recreation
	hpText = FontManager.recreate(hpText, settings.font_settings);
	mpText = FontManager.recreate(mpText, settings.font_settings);
	tpText = FontManager.recreate(tpText, settings.font_settings);
	allFonts = {hpText, mpText, tpText};

	-- Reset cached colors when fonts are recreated
	lastHpTextColor = nil;
	lastMpTextColor = nil;
	lastTpTextColor = nil;

	-- Reset reference height so it gets recalculated with new font
	referenceTextHeight = 0;
end

playerbar.SetHidden = function(hidden)
	if (hidden == true) then
		SetFontsVisible(allFonts, false);
	end
end

playerbar.Cleanup = function()
	-- Use FontManager for cleaner font destruction
	hpText = FontManager.destroy(hpText);
	mpText = FontManager.destroy(mpText);
	tpText = FontManager.destroy(tpText);
	allFonts = nil;
end

return playerbar;