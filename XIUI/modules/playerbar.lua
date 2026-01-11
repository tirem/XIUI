require('common');
require('handlers.helpers');
local imgui = require('imgui');
local gdi = require('submodules.gdifonts.include');
local progressbar = require('libs.progressbar');
local buffTable = require('libs.bufftable');
local castcostShared = require('modules.castcost.shared');
local defaultPositions = require('libs.defaultpositions');

local hpText;
local mpText;
local tpText;
local allFonts; -- Table for batch visibility operations
local resetPosNextFrame = false;

-- Position save/restore state
local hasAppliedSavedPosition = false;
local forcePositionReset = false;
local lastSavedPosX, lastSavedPosY = nil, nil;

-- Cache last set colors to avoid expensive SetColor() calls every frame
local lastHpTextColor;
local lastMpTextColor;
local lastTpTextColor;

-- Reference text height for baseline alignment (prevents text jumping)
local referenceTextHeight = 0;

-- Cached interpolation colors (updated when config changes)
local cachedInterpColors = nil;
local lastInterpColorConfig = nil;

-- Cached window flags (constant, computed once)
local baseWindowFlags = nil;

local playerbar = {
	interpolation = {}
};

-- Get cached interpolation colors, only recompute when config changes
local function getCachedInterpColors()
	local currentConfig = gConfig.colorCustomization and gConfig.colorCustomization.shared;
	if cachedInterpColors == nil or lastInterpColorConfig ~= currentConfig then
		cachedInterpColors = GetHpInterpolationColors();
		lastInterpColorConfig = currentConfig;
	end
	return cachedInterpColors;
end

-- Note: getBaseWindowFlags moved to handlers/helpers.lua as GetBaseWindowFlags()
-- This local caching is no longer needed but kept for backwards compatibility
local function getBaseWindowFlags()
	return GetBaseWindowFlags(false);
end

local _XIUI_DEV_DEBUG_INTERPOLATION = false;
local _XIUI_DEV_DEBUG_INTERPOLATION_DELAY, _XIUI_DEV_DEBUG_INTERPOLATION_NEXT_TIME;

if _XIUI_DEV_DEBUG_INTERPOLATION then
	_XIUI_DEV_DEBUG_INTERPOLATION_DELAY = 2;
	_XIUI_DEV_DEBUG_INTERPOLATION_NEXT_TIME = os.time() + _XIUI_DEV_DEBUG_INTERPOLATION_DELAY;
end

playerbar.DrawWindow = function(settings)
    -- Obtain game state (single call each, cached for this frame)
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

	-- Hide player bar when in party/alliance if setting is enabled
	if gConfig.playerBarHideWhenInParty then
		-- Check if any other party/alliance members are active (slots 1-17)
		local inParty = false;
		for i = 1, 17 do
			if party:GetMemberIsActive(i) == 1 then
				inParty = true;
				break;
			end
		end
		if inParty then
			SetFontsVisible(allFonts, false);
			return;
		end
	end

	local SelfHP = party:GetMemberHP(0);
	local SelfHPMax = player:GetHPMax();
	-- Calculate percentage from actual values to avoid stale party API data (issue #92)
	local SelfHPPercent = (SelfHPMax > 0) and math.clamp((SelfHP / SelfHPMax) * 100, 0, 100) or 0;
	local SelfMP = party:GetMemberMP(0);
	local SelfMPMax = player:GetMPMax();
	local SelfMPPercent = (SelfMPMax > 0) and math.clamp((SelfMP / SelfMPMax) * 100, 0, 100) or 0;
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
	-- Handle position reset or restore
	if forcePositionReset then
		local defX, defY = defaultPositions.GetPlayerBarPosition();
		imgui.SetNextWindowPos({defX, defY}, ImGuiCond_Always);
		forcePositionReset = false;
		hasAppliedSavedPosition = true;
		lastSavedPosX, lastSavedPosY = defX, defY;
	elseif not hasAppliedSavedPosition and gConfig.playerBarWindowPosX ~= nil then
		imgui.SetNextWindowPos({gConfig.playerBarWindowPosX, gConfig.playerBarWindowPosY}, ImGuiCond_Once);
		hasAppliedSavedPosition = true;
		lastSavedPosX = gConfig.playerBarWindowPosX;
		lastSavedPosY = gConfig.playerBarWindowPosY;
	end

	-- Get base window flags with NoMove dynamically added if positions are locked
	local windowFlags = GetBaseWindowFlags(gConfig.lockPositions);
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

		-- Get cached interpolation colors (only recomputed when config changes)
		local interpColors = getCachedInterpColors();

		-- Add interpolation bar for damage taken
		if playerbar.interpolation.interpolationDamagePercent and playerbar.interpolation.interpolationDamagePercent > 0 then
			local interpolationOverlay;

			if gConfig.healthBarFlashEnabled and interpolationOverlayAlpha > 0 then
				interpolationOverlay = {
					interpColors.damageFlashColor,
					interpolationOverlayAlpha
				};
			end

			table.insert(
				hpPercentData,
				{
					playerbar.interpolation.interpolationDamagePercent / 100,
					interpColors.damageGradient,
					interpolationOverlay
				}
			);
		end

		-- Add interpolation bar for healing received
		if playerbar.interpolation.interpolationHealPercent and playerbar.interpolation.interpolationHealPercent > 0 then
			local healInterpolationOverlay;

			if gConfig.healthBarFlashEnabled and healInterpolationOverlayAlpha > 0 then
				healInterpolationOverlay = {
					interpColors.healFlashColor,
					healInterpolationOverlayAlpha
				};
			end

			table.insert(
				hpPercentData,
				{
					playerbar.interpolation.interpolationHealPercent / 100,
					interpColors.healGradient,
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

			-- Check for spell cost preview from castcost module
			local mpPercentData;
			local spellMpCost, hasEnoughMp, isSpellActive = castcostShared.GetMpCost();
			if isSpellActive and spellMpCost > 0 and SelfMPMax > 0 and gConfig.showMpCostPreview ~= false then
				-- Calculate the cost as a percentage of max MP
				local costPercent = spellMpCost / SelfMPMax;
				-- Calculate remaining MP after cast
				local remainingMpPercent = math.max(0, (SelfMPPercent / 100) - costPercent);

				-- Get cost preview colors from castCost settings
				local castCostColors = gConfig.colorCustomization.castCost;
				local costGradient;
				local costColorSetting = castCostColors and castCostColors.mpCostPreviewGradient;
				if costColorSetting then
					if costColorSetting.enabled and costColorSetting.start and costColorSetting.stop then
						costGradient = {costColorSetting.start, costColorSetting.stop};
					elseif costColorSetting.start then
						costGradient = {costColorSetting.start, costColorSetting.start};
					else
						costGradient = {'#9abb5a', '#bfe07d'};
					end
				else
					costGradient = {'#9abb5a', '#bfe07d'};
				end

				-- Calculate pulsing overlay for cost preview
				local costOverlay = nil;
				local flashColor = castCostColors and castCostColors.mpCostPreviewFlashColor or '#FFFFFF';
				local pulseSpeed = castCostColors and castCostColors.mpCostPreviewPulseSpeed or 1.0;
				if pulseSpeed > 0 then
					local pulseTime = os.clock();
					local phase = pulseTime % pulseSpeed;
					local pulseAlpha = (2 / pulseSpeed) * phase;
					if pulseAlpha > 1 then
						pulseAlpha = 2 - pulseAlpha;
					end
					-- Scale alpha to be subtle (max 0.6)
					pulseAlpha = pulseAlpha * 0.6;
					costOverlay = {flashColor, pulseAlpha};
				end

				-- Build MP bar with cost preview: [remaining MP][cost segment with pulse]
				mpPercentData = {
					{remainingMpPercent, mpGradient},
					{costPercent, costGradient, costOverlay},
				};
			else
				-- Normal MP bar without cost preview
				mpPercentData = {{SelfMPPercent / 100, mpGradient}};
			end

			progressbar.ProgressBar(mpPercentData, {barSize, settings.barHeight}, {decorate = gConfig.showPlayerBarBookends});
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

			-- Get TP overlay gradient from settings
			local overlaySettings = gConfig.colorCustomization.playerBar.tpOverlayGradient;
			local tpOverlayGradient;
			if overlaySettings and overlaySettings.enabled then
				tpOverlayGradient = {overlaySettings.start, overlaySettings.stop};
			else
				tpOverlayGradient = {overlaySettings and overlaySettings.start or '#0078CC', overlaySettings and overlaySettings.start or '#0078CC'};
			end

		local tpPulseConfig = nil;
		if gConfig.playerBarTpFlashEnabled then
			-- Get flash color from settings (ARGB) and convert to hex string
			local flashColor = gConfig.colorCustomization.playerBar.tpFlashColor or 0xFF2fa9ff;
			local r = bit.band(bit.rshift(flashColor, 16), 0xFF);
			local g = bit.band(bit.rshift(flashColor, 8), 0xFF);
			local b = bit.band(flashColor, 0xFF);
			local flashHex = string.format('#%02x%02x%02x', r, g, b);
			tpPulseConfig = {
				flashHex, -- overlay pulse color
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
		-- Include all characters used in display modes: numbers, percent, parentheses, slash, space
		if referenceTextHeight == 0 or referenceTextHeight ~= settings.font_settings.font_height then
			hpText:set_text("0123456789%() /");
			local _, refHeight = hpText:get_text_size();
			referenceTextHeight = refHeight;
		end

		-- Update our HP Text (using proper padding like exp bar)
		-- Format HP text based on display mode setting
		local hpDisplayMode = gConfig.playerBarHpDisplayMode or 'number';
		local hpDisplayText;
		if hpDisplayMode == 'percent' then
			hpDisplayText = string.format("%.0f", SelfHPPercent) .. '%';
		elseif hpDisplayMode == 'both' then
			hpDisplayText = tostring(SelfHP) .. ' (' .. string.format("%.0f", SelfHPPercent) .. '%)';
		elseif hpDisplayMode == 'both_percent_first' then
			hpDisplayText = string.format("%.0f", SelfHPPercent) .. '% (' .. tostring(SelfHP) .. ')';
		elseif hpDisplayMode == 'current_max' then
			hpDisplayText = tostring(SelfHP) .. '/' .. tostring(SelfHPMax);
		else
			hpDisplayText = tostring(SelfHP);
		end
		hpText:set_text(hpDisplayText);
		-- Apply baseline offset to keep text baseline consistent
		local _, hpTextHeight = hpText:get_text_size();
		local hpBaselineOffset = referenceTextHeight - hpTextHeight;
		-- Calculate position based on alignment
		local hpTextX;
		local hpAlignment = gConfig.playerBarHpTextAlignment or 'right';
		if hpAlignment == 'left' then
			hpTextX = hpBarStartX + bookendWidth + textPadding;
			hpText:set_font_alignment(gdi.Alignment.Left);
		elseif hpAlignment == 'center' then
			hpTextX = hpBarStartX + (barSize / 2);
			hpText:set_font_alignment(gdi.Alignment.Center);
		else -- right alignment (default)
			hpTextX = hpBarStartX + barSize - bookendWidth - textPadding;
			hpText:set_font_alignment(gdi.Alignment.Right);
		end
		-- Apply user offset
		hpTextX = hpTextX + (gConfig.playerBarHpTextOffsetX or 0);
		local hpTextY = hpBarStartY + settings.barHeight + settings.textYOffset + (gConfig.playerBarHpTextOffsetY or 0);
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
			-- Format MP text based on display mode setting
			local mpDisplayMode = gConfig.playerBarMpDisplayMode or 'number';
			local mpDisplayText;
			if mpDisplayMode == 'percent' then
				mpDisplayText = string.format("%.0f", SelfMPPercent) .. '%';
			elseif mpDisplayMode == 'both' then
				mpDisplayText = tostring(SelfMP) .. ' (' .. string.format("%.0f", SelfMPPercent) .. '%)';
			elseif mpDisplayMode == 'both_percent_first' then
				mpDisplayText = string.format("%.0f", SelfMPPercent) .. '% (' .. tostring(SelfMP) .. ')';
			elseif mpDisplayMode == 'current_max' then
				mpDisplayText = tostring(SelfMP) .. '/' .. tostring(SelfMPMax);
			else
				mpDisplayText = tostring(SelfMP);
			end
			mpText:set_text(mpDisplayText);
			-- Apply baseline offset to keep text baseline consistent
			local _, mpTextHeight = mpText:get_text_size();
			local mpBaselineOffset = referenceTextHeight - mpTextHeight;
			-- Calculate position based on alignment
			local mpTextX;
			local mpAlignment = gConfig.playerBarMpTextAlignment or 'right';
			if mpAlignment == 'left' then
				mpTextX = mpBarStartX + bookendWidth + textPadding;
				mpText:set_font_alignment(gdi.Alignment.Left);
			elseif mpAlignment == 'center' then
				mpTextX = mpBarStartX + (barSize / 2);
				mpText:set_font_alignment(gdi.Alignment.Center);
			else -- right alignment (default)
				mpTextX = mpBarStartX + barSize - bookendWidth - textPadding;
				mpText:set_font_alignment(gdi.Alignment.Right);
			end
			-- Apply user offset
			mpTextX = mpTextX + (gConfig.playerBarMpTextOffsetX or 0);
			local mpTextY = mpBarStartY + settings.barHeight + settings.textYOffset + (gConfig.playerBarMpTextOffsetY or 0);
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
		tpText:set_text(tostring(SelfTP));
		-- Apply baseline offset to keep text baseline consistent
		local _, tpTextHeight = tpText:get_text_size();
		local tpBaselineOffset = referenceTextHeight - tpTextHeight;
		-- Calculate position based on alignment
		local tpTextX;
		local tpAlignment = gConfig.playerBarTpTextAlignment or 'right';
		if tpAlignment == 'left' then
			tpTextX = tpBarStartX + bookendWidth + textPadding;
			tpText:set_font_alignment(gdi.Alignment.Left);
		elseif tpAlignment == 'center' then
			tpTextX = tpBarStartX + (barSize / 2);
			tpText:set_font_alignment(gdi.Alignment.Center);
		else -- right alignment (default)
			tpTextX = tpBarStartX + barSize - bookendWidth - textPadding;
			tpText:set_font_alignment(gdi.Alignment.Right);
		end
		-- Apply user offset
		tpTextX = tpTextX + (gConfig.playerBarTpTextOffsetX or 0);
		local tpTextY = tpBarStartY + settings.barHeight + settings.textYOffset + (gConfig.playerBarTpTextOffsetY or 0);
		tpText:set_position_x(tpTextX);
		tpText:set_position_y(tpTextY + tpBaselineOffset);
		local desiredTpColor = (SelfTP >= 1000) and gConfig.colorCustomization.playerBar.tpFullTextColor or gConfig.colorCustomization.playerBar.tpEmptyTextColor;
		-- Only call set_font_color if the color has changed
		if (lastTpTextColor ~= desiredTpColor) then
			tpText:set_font_color(desiredTpColor);
			lastTpTextColor = desiredTpColor;
		end

		tpText:set_visible(true);

		-- Save position if moved (with change detection to avoid spam)
		local winX, winY = imgui.GetWindowPos();
		if not gConfig.lockPositions then
			if lastSavedPosX == nil or
			   math.abs(winX - lastSavedPosX) > 1 or
			   math.abs(winY - lastSavedPosY) > 1 then
				gConfig.playerBarWindowPosX = winX;
				gConfig.playerBarWindowPosY = winY;
				lastSavedPosX = winX;
				lastSavedPosY = winY;
			end
		end
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

	-- Invalidate interpolation color cache (config may have changed)
	cachedInterpColors = nil;
	lastInterpColorConfig = nil;
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

playerbar.ResetPositions = function()
	forcePositionReset = true;
	hasAppliedSavedPosition = false;
end

return playerbar;