require('common');
require('helpers');
local imgui = require('imgui');
local statusHandler = require('statushandler');
local debuffHandler = require('debuffhandler');
local actionTracker = require('actiontracker');
local progressbar = require('progressbar');
local gdi = require('gdifonts.include');
local encoding = require('gdifonts.encoding');
local ffi = require("ffi");

-- TODO: Calculate these instead of manually setting them

local bgAlpha = 0.4;
local bgRadius = 3;

local arrowTexture;
local percentText;
local nameText;
local totNameText;
local distText;
local castText;
local allFonts; -- Table for batch visibility operations
local targetbar = {
	interpolation = {},
	enemyCasts = {} -- Track enemy casting: [serverId] = {spellName, timestamp}
};

-- Cache last set colors to avoid expensive SetColor() calls every frame
local lastNameTextColor;
local lastPercentTextColor;
local lastTotNameTextColor;
local lastCastTextColor;

local _HXUI_DEV_DEBUG_INTERPOLATION = false;
local _HXUI_DEV_DEBUG_INTERPOLATION_DELAY = 1;
local _HXUI_DEV_DEBUG_HP_PERCENT_PERSISTENT = 100;
local _HXUI_DEV_DAMAGE_SET_TIMES = {};

targetbar.DrawWindow = function(settings)
    -- Obtain the player entity..
    local playerEnt = GetPlayerEntity();
	local player = GetPlayerSafe();
    if (playerEnt == nil or player == nil) then
		SetFontsVisible(allFonts, false);
        return;
    end

    -- Obtain the player target entity (account for subtarget)
	local playerTarget = GetTargetSafe();
	local targetIndex;
	local targetEntity;
	if (playerTarget ~= nil) then
		targetIndex, _ = GetTargets();
		targetEntity = GetEntity(targetIndex);
	end
    if (targetEntity == nil or targetEntity.Name == nil) then
		SetFontsVisible(allFonts, false);
        for i=1,32 do
            local textObjName = "debuffText" .. tostring(i)
            textObj = debuffTable[textObjName]
            if textObj then
                textObj:set_visible(false)
            end
        end
		targetbar.interpolation.interpolationDamagePercent = 0;

        return;
    end

	local currentTime = os.clock();

	local hppPercent = targetEntity.HPPercent;

	-- Mimic damage taken
	if _HXUI_DEV_DEBUG_INTERPOLATION then
		if _HXUI_DEV_DAMAGE_SET_TIMES[1] and currentTime > _HXUI_DEV_DAMAGE_SET_TIMES[1][1] then
			_HXUI_DEV_DEBUG_HP_PERCENT_PERSISTENT = _HXUI_DEV_DAMAGE_SET_TIMES[1][2];

			table.remove(_HXUI_DEV_DAMAGE_SET_TIMES, 1);
		end

		if #_HXUI_DEV_DAMAGE_SET_TIMES == 0 then
			local previousHitTime = currentTime + 1;
			local previousHp = 100;

			local totalDamageInstances = 10;

			for i = 1, totalDamageInstances do
				local hitDelay = math.random(0.25 * 100, 1.25 * 100) / 100;
				local damageAmount = math.random(1, 20);

				if i > 1 and i < totalDamageInstances then
					previousHp = math.max(previousHp - damageAmount, 0);
				end

				if i < totalDamageInstances then
					previousHitTime = previousHitTime + hitDelay;
				else
					previousHitTime = previousHitTime + _HXUI_DEV_DEBUG_INTERPOLATION_DELAY;
				end

				_HXUI_DEV_DAMAGE_SET_TIMES[i] = {previousHitTime, previousHp};
			end
		end

		hppPercent = _HXUI_DEV_DEBUG_HP_PERCENT_PERSISTENT;
	end

	-- If we change targets, reset the interpolation
	if targetbar.interpolation.currentTargetId ~= targetIndex then
		targetbar.interpolation.currentTargetId = targetIndex;
		targetbar.interpolation.currentHpp = hppPercent;
		targetbar.interpolation.interpolationDamagePercent = 0;
	end

	-- If the target takes damage
	if hppPercent < targetbar.interpolation.currentHpp then
		local previousInterpolationDamagePercent = targetbar.interpolation.interpolationDamagePercent;

		local damageAmount = targetbar.interpolation.currentHpp - hppPercent;

		targetbar.interpolation.interpolationDamagePercent = targetbar.interpolation.interpolationDamagePercent + damageAmount;

		if previousInterpolationDamagePercent > 0 and targetbar.interpolation.lastHitAmount and damageAmount > targetbar.interpolation.lastHitAmount then
			targetbar.interpolation.lastHitTime = currentTime;
			targetbar.interpolation.lastHitAmount = damageAmount;
		elseif previousInterpolationDamagePercent == 0 then
			targetbar.interpolation.lastHitTime = currentTime;
			targetbar.interpolation.lastHitAmount = damageAmount;
		end

		if not targetbar.interpolation.lastHitTime or currentTime > targetbar.interpolation.lastHitTime + (settings.hitFlashDuration * 0.25) then
			targetbar.interpolation.lastHitTime = currentTime;
			targetbar.interpolation.lastHitAmount = damageAmount;
		end

		-- If we previously were interpolating with an empty bar, reset the hit delay effect
		if previousInterpolationDamagePercent == 0 then
			targetbar.interpolation.hitDelayStartTime = currentTime;
		end
	elseif hppPercent > targetbar.interpolation.currentHpp then
		-- If the target heals
		targetbar.interpolation.interpolationDamagePercent = 0;
		targetbar.interpolation.hitDelayStartTime = nil;
	end

	targetbar.interpolation.currentHpp = hppPercent;

	-- Reduce the HP amount to display based on the time passed since last frame
	if targetbar.interpolation.interpolationDamagePercent > 0 and targetbar.interpolation.hitDelayStartTime and currentTime > targetbar.interpolation.hitDelayStartTime + settings.hitDelayDuration then
		if targetbar.interpolation.lastFrameTime then
			local deltaTime = currentTime - targetbar.interpolation.lastFrameTime;

			local animSpeed = 0.1 + (0.9 * (targetbar.interpolation.interpolationDamagePercent / 100));

			-- animSpeed = math.max(settings.hitDelayMinAnimSpeed, animSpeed);

			targetbar.interpolation.interpolationDamagePercent = targetbar.interpolation.interpolationDamagePercent - (settings.hitInterpolationDecayPercentPerSecond * deltaTime * animSpeed);

			-- Clamp our percent to 0
			targetbar.interpolation.interpolationDamagePercent = math.max(0, targetbar.interpolation.interpolationDamagePercent);
		end
	end

	if gConfig.healthBarFlashEnabled then
		if targetbar.interpolation.lastHitTime and currentTime < targetbar.interpolation.lastHitTime + settings.hitFlashDuration then
			local hitFlashTime = currentTime - targetbar.interpolation.lastHitTime;
			local hitFlashTimePercent = hitFlashTime / settings.hitFlashDuration;

			local maxAlphaHitPercent = 20;
			local maxAlpha = math.min(targetbar.interpolation.lastHitAmount, maxAlphaHitPercent) / maxAlphaHitPercent;

			maxAlpha = math.max(maxAlpha * 0.6, 0.4);

			targetbar.interpolation.overlayAlpha = math.pow(1 - hitFlashTimePercent, 2) * maxAlpha;
		end
	end

	targetbar.interpolation.lastFrameTime = currentTime;

	local color = GetColorOfTarget(targetEntity, targetIndex);
	local isMonster = GetIsMob(targetEntity);

	-- Draw the main target window
	local windowFlags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoBringToFrontOnFocus);
	if (gConfig.lockPositions) then
		windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
	end
    if (imgui.Begin('TargetBar', true, windowFlags)) then
        
		-- Obtain and prepare target information..
		local dist  = ('%.1f'):fmt(math.sqrt(targetEntity.Distance));
		local targetNameText = targetEntity.Name;
		local targetHpPercent = targetEntity.HPPercent..'%';

		if (gConfig.showEnemyId and isMonster) then
			local entity = GetEntitySafe();
			if entity ~= nil then
				local targetServerId = entity:GetServerId(targetIndex);
				local targetServerIdHex = string.format('0x%X', targetServerId);
				targetNameText = targetNameText .. " [".. string.sub(targetServerIdHex, -3) .."]";
			end
		end

		local targetGradient = GetCustomGradient(gConfig.colorCustomization.targetBar, 'hpGradient') or {'#e26c6c', '#fb9494'};
		local hpGradientStart = targetGradient[1];
		local hpGradientEnd = targetGradient[2];

		local hpPercentData = {{targetEntity.HPPercent / 100, {hpGradientStart, hpGradientEnd}}};

		if _HXUI_DEV_DEBUG_INTERPOLATION then
			hpPercentData[1][1] = targetbar.interpolation.currentHpp / 100;
		end

		if targetbar.interpolation.interpolationDamagePercent > 0 then
			local interpolationOverlay;

			if gConfig.healthBarFlashEnabled then
				interpolationOverlay = {
					'#FFFFFF', -- overlay color,
					targetbar.interpolation.overlayAlpha -- overlay alpha,
				};
			end

			table.insert(
				hpPercentData,
				{
					targetbar.interpolation.interpolationDamagePercent / 100, -- interpolation percent
					{'#cf3437', '#c54d4d'},
					interpolationOverlay
				}
			);
		end

		local startX, startY = imgui.GetCursorScreenPos();

		-- Calculate bookend width and text padding (same as exp bar)
		local bookendWidth = gConfig.showTargetBarBookends and (settings.barHeight / 2) or 0;
		local textPadding = 8;

		progressbar.ProgressBar(hpPercentData, {settings.barWidth, settings.barHeight}, {decorate = gConfig.showTargetBarBookends});

		-- Dynamically set font heights based on settings (avoids expensive font recreation)
		nameText:set_font_height(settings.name_font_settings.font_height);
		percentText:set_font_height(settings.percent_font_settings.font_height);
		distText:set_font_height(settings.distance_font_settings.font_height);

		-- Left-aligned text position (target name) - 8px from left edge (after bookend)
		local leftTextX = startX + bookendWidth + textPadding;
		local nameWidth, nameHeight = nameText:get_text_size();
		nameText:set_position_x(leftTextX);
		nameText:set_position_y(startY - settings.topTextYOffset - nameHeight);
		-- Only call set_font_color if the color has changed (expensive operation for GDI fonts)
		if (lastNameTextColor ~= color) then
			nameText:set_font_color(color);
			lastNameTextColor = color;
		end
		nameText:set_text(targetNameText);
		nameText:set_visible(true);

		-- Right-aligned text position - combine distance and HP% on same line
		local rightTextX = startX + settings.barWidth - bookendWidth - textPadding;
		local topTextY = startY - settings.topTextYOffset;

		-- Build combined text string: [distance] - [hp%]
		local showDistance = gConfig.showTargetDistance;
		local showHpPercent = isMonster or gConfig.alwaysShowHealthPercent;
		local combinedText = "";

		if (showDistance and showHpPercent) then
			combinedText = string.format("%s - %s", tostring(dist), tostring(targetHpPercent));
		elseif (showDistance) then
			combinedText = tostring(dist);
		elseif (showHpPercent) then
			combinedText = tostring(targetHpPercent);
		end

		if (combinedText ~= "") then
			distText:set_text(combinedText);
			local distWidth, distHeight = distText:get_text_size();
			distText:set_position_x(rightTextX);
			distText:set_position_y(topTextY - distHeight);

			-- Use HP color if showing HP%, otherwise white
			if (showHpPercent) then
				local hpColor, _ = GetHpColors(targetEntity.HPPercent / 100);
				if (lastPercentTextColor ~= hpColor) then
					distText:set_font_color(hpColor);
					lastPercentTextColor = hpColor;
				end
			else
				distText:set_font_color(0xFFFFFFFF);
			end

			distText:set_visible(true);
		else
			distText:set_visible(false);
		end

		-- Hide the separate percentText since we're combining them
		percentText:set_visible(false);

		-- Draw enemy cast bar and text if casting (or in config mode)
		local castData = targetbar.enemyCasts[targetEntity.ServerId];
		local inConfigMode = showConfig and showConfig[1];

		-- Create test cast data for config mode
		if (inConfigMode and castData == nil) then
			castData = T{
				spellName = "Fire III",
				castTime = 5.0,  -- 5 second cast
				startTime = os.clock() - ((os.clock() % 5.0)),  -- Loops every 5 seconds
			};
		end

		if (castData ~= nil and castData.spellName ~= nil and castData.castTime ~= nil and castData.startTime ~= nil) then
			-- Calculate cast progress
			local elapsed = os.clock() - castData.startTime;
			local progress = math.min(elapsed / castData.castTime, 1.0);

			-- Draw cast bar under HP bar
			local castBarY = startY + settings.barHeight + 2;
			imgui.SetCursorScreenPos({startX, castBarY});

			-- Cast bar settings
			local castBarHeight = 8;
			local castBarWidth = settings.barWidth;
			local castGradient = GetCustomGradient(gConfig.colorCustomization.targetBar, 'castBarGradient') or {'#ffaa00', '#ffcc44'};

			progressbar.ProgressBar({{progress, castGradient}}, {castBarWidth, castBarHeight}, {decorate = gConfig.showTargetBarBookends});

			-- Draw cast text below the cast bar
			castText:set_font_height(settings.cast_font_settings.font_height);
			local castWidth, castHeight = castText:get_text_size();
			local centerX = startX + (settings.barWidth / 2);
			castText:set_position_x(centerX);
			castText:set_position_y(castBarY + castBarHeight + 2);
			castText:set_text(inConfigMode and "Fire III (Demo)" or castData.spellName);
			-- Get custom cast text color
			local castColor = GetColorSetting('targetBar', 'castTextColor', 0xFFFFAA00);
			if (lastCastTextColor ~= castColor) then
				castText:set_font_color(castColor);
				lastCastTextColor = castColor;
			end
			castText:set_visible(true);
		else
			castText:set_visible(false);
		end

		-- Draw buffs and debuffs
		imgui.SameLine();
		local preBuffX, preBuffY = imgui.GetCursorScreenPos();
		local buffIds;
        local buffTimes = nil;
		if (targetEntity == playerEnt) then
			buffIds = player:GetBuffs();
		elseif (IsMemberOfParty(targetIndex)) then
			buffIds = statusHandler.get_member_status(playerTarget:GetServerId(0));
		elseif (isMonster) then
			buffIds, buffTimes = debuffHandler.GetActiveDebuffs(playerTarget:GetServerId(0));
		end
		imgui.NewLine();
		imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {1, 3});
        for i=1,32 do
            local textObjName = "debuffText" .. tostring(i)
            textObj = debuffTable[textObjName]
            if textObj then
                textObj:set_visible(false)
            end
        end
		DrawStatusIcons(buffIds, settings.iconSize, settings.maxIconColumns, 3, false, settings.barHeight/2, buffTimes, nil);
		imgui.PopStyleVar(1);

		-- Obtain our target of target using action-based tracking (more reliable)
		local totEntity;
		local totIndex
		if (targetEntity == playerEnt) then
			totIndex = targetIndex
			totEntity = targetEntity;
		end
		if (totEntity == nil) then
			-- Try action-based tracking first (more reliable)
			totIndex = actionTracker.GetLastTarget(targetEntity.ServerId);
			-- Fallback to TargetedIndex if no recent actions
			if (totIndex == nil) then
				totIndex = targetEntity.TargetedIndex;
			end
			if (totIndex ~= nil) then
				totEntity = GetEntity(totIndex);
			end
		end

		-- Draw Target of Target bar based on split setting
		if (not gConfig.splitTargetOfTarget) then
			-- Draw ToT in same window (original behavior)
			if (totEntity ~= nil and totEntity.Name ~= nil) then
				-- Reset font height to regular ToT settings when not split
				totNameText:set_font_height(settings.totName_font_settings.font_height);

				-- Use preBuffX for horizontal position, but startY for vertical alignment with HP bar
				local totColor = GetColorOfTarget(totEntity, totIndex);

				-- Calculate vertical center of the HP bar
				local hpBarCenterY = startY + (settings.barHeight / 2);

				-- Draw arrow vertically centered with HP bar
				local arrowY = hpBarCenterY - (settings.arrowSize / 2);
				imgui.SetCursorScreenPos({preBuffX, arrowY});
				imgui.Image(tonumber(ffi.cast("uint32_t", arrowTexture.image)), { settings.arrowSize, settings.arrowSize });
				imgui.SameLine();

				-- Draw ToT bar vertically centered with HP bar
				local totX, _ = imgui.GetCursorScreenPos();
				local totBarY = hpBarCenterY - (settings.totBarHeight / 2) + settings.totBarOffset;
				imgui.SetCursorScreenPos({totX, totBarY});

				local totStartX, totStartY = imgui.GetCursorScreenPos();

				-- Calculate bookend width and text padding for ToT bar
				local totBookendWidth = gConfig.showTargetBarBookends and (settings.totBarHeight / 2) or 0;
				local totTextPadding = 8;

				local totGradient = GetCustomGradient(gConfig.colorCustomization.totBar, 'hpGradient') or {'#e16c6c', '#fb9494'};
				progressbar.ProgressBar({{totEntity.HPPercent / 100, totGradient}}, {settings.barWidth / 3, settings.totBarHeight}, {decorate = gConfig.showTargetBarBookends});

				-- Dynamically set font height for ToT text
				totNameText:set_font_height(settings.totName_font_settings.font_height);

				local totNameWidth, totNameHeight = totNameText:get_text_size();

				-- Left-aligned text position (ToT name) - 8px from left edge (after bookend)
				local totLeftTextX = totStartX + totBookendWidth + totTextPadding;
				totNameText:set_position_x(totLeftTextX);
				totNameText:set_position_y(totStartY - totNameHeight);
				-- Only call set_font_color if the color has changed
				if (lastTotNameTextColor ~= totColor) then
					totNameText:set_font_color(totColor);
					lastTotNameTextColor = totColor;
				end
				totNameText:set_text(totEntity.Name);
				totNameText:set_visible(true);
			else
				totNameText:set_visible(false);
			end
		else
			-- When split is enabled, hide the totName text here (it will be shown in separate window)
			totNameText:set_visible(false);
		end
    end
	local winPosX, winPosY = imgui.GetWindowPos();
    imgui.End();

	-- Draw separate Target of Target window if split is enabled
	if (gConfig.splitTargetOfTarget) then
		-- Obtain the player entity
		local playerEnt = GetPlayerEntity();
		local player = GetPlayerSafe();
		if (playerEnt == nil or player == nil) then
			totNameText:set_visible(false);
			return;
		end

		-- Obtain the player target entity
		local playerTarget = GetTargetSafe();
		local targetIndex;
		local targetEntity;
		if (playerTarget ~= nil) then
			targetIndex, _ = GetTargets();
			targetEntity = GetEntity(targetIndex);
		end
		if (targetEntity == nil or targetEntity.Name == nil) then
			totNameText:set_visible(false);
			return;
		end

		-- Obtain target of target using action-based tracking (more reliable)
		local totEntity;
		local totIndex;
		if (targetEntity == playerEnt) then
			totIndex = targetIndex;
			totEntity = targetEntity;
		end
		if (totEntity == nil) then
			-- Try action-based tracking first (more reliable)
			totIndex = actionTracker.GetLastTarget(targetEntity.ServerId);
			-- Fallback to TargetedIndex if no recent actions
			if (totIndex == nil) then
				totIndex = targetEntity.TargetedIndex;
			end
			if (totIndex ~= nil) then
				totEntity = GetEntity(totIndex);
			end
		end

		if (totEntity ~= nil and totEntity.Name ~= nil) then
			local windowFlags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoBringToFrontOnFocus);
			if (gConfig.lockPositions) then
				windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
			end

			if (imgui.Begin('TargetOfTargetBar', true, windowFlags)) then
				local totColor = GetColorOfTarget(totEntity, totIndex);
				local totStartX, totStartY = imgui.GetCursorScreenPos();

				-- Calculate bookend width and text padding for split ToT bar
				local totBookendWidthSplit = gConfig.showTargetBarBookends and (settings.totBarHeightSplit / 2) or 0;
				local totTextPaddingSplit = 8;

				-- Use adjusted ToT settings for split bar
				local totGradientSplit = GetCustomGradient(gConfig.colorCustomization.totBar, 'hpGradient') or {'#e16c6c', '#fb9494'};
				progressbar.ProgressBar({{totEntity.HPPercent / 100, totGradientSplit}}, {settings.totBarWidth, settings.totBarHeightSplit}, {decorate = gConfig.showTargetBarBookends});

				-- Set font height for split ToT bar
				totNameText:set_font_height(settings.totName_font_settings_split.font_height);

				local totNameWidth, totNameHeight = totNameText:get_text_size();

				-- Left-aligned text position (ToT name) - 8px from left edge (after bookend)
				local totLeftTextXSplit = totStartX + totBookendWidthSplit + totTextPaddingSplit;
				totNameText:set_position_x(totLeftTextXSplit);
				totNameText:set_position_y(totStartY - totNameHeight);
				-- Only call set_font_color if the color has changed
				if (lastTotNameTextColor ~= totColor) then
					totNameText:set_font_color(totColor);
					lastTotNameTextColor = totColor;
				end
				totNameText:set_text(totEntity.Name);
				totNameText:set_visible(true);
			end
			imgui.End();
		else
			totNameText:set_visible(false);
		end
	end
end

targetbar.Initialize = function(settings)
	-- Use FontManager for cleaner font creation
    percentText = FontManager.create(settings.percent_font_settings);
	nameText = FontManager.create(settings.name_font_settings);
	totNameText = FontManager.create(settings.totName_font_settings);
	distText = FontManager.create(settings.distance_font_settings);
	castText = FontManager.create(settings.cast_font_settings);
	allFonts = {percentText, nameText, totNameText, distText, castText};
	arrowTexture = 	LoadTexture("arrow");
end

targetbar.UpdateVisuals = function(settings)
	-- Use FontManager for cleaner font recreation
	percentText = FontManager.recreate(percentText, settings.percent_font_settings);
	nameText = FontManager.recreate(nameText, settings.name_font_settings);
	totNameText = FontManager.recreate(totNameText, settings.totName_font_settings);
	distText = FontManager.recreate(distText, settings.distance_font_settings);
	castText = FontManager.recreate(castText, settings.cast_font_settings);
	allFonts = {percentText, nameText, totNameText, distText, castText};

	-- Reset cached colors when fonts are recreated
	lastNameTextColor = nil;
	lastPercentTextColor = nil;
	lastTotNameTextColor = nil;
	lastCastTextColor = nil;
end

targetbar.SetHidden = function(hidden)
	if (hidden == true) then
		SetFontsVisible(allFonts, false);
	end
end

targetbar.Cleanup = function()
	-- Use FontManager for cleaner font destruction
	percentText = FontManager.destroy(percentText);
	nameText = FontManager.destroy(nameText);
	totNameText = FontManager.destroy(totNameText);
	distText = FontManager.destroy(distText);
	castText = FontManager.destroy(castText);
	allFonts = nil;
end

targetbar.HandleActionPacket = function(actionPacket)
	if (actionPacket == nil or actionPacket.UserId == nil) then
		return;
	end

	-- Type 8 = Magic (Start) - Enemy begins casting
	if (actionPacket.Type == 8) then
		-- Get the spell ID from the action
		if (actionPacket.Targets and #actionPacket.Targets > 0 and
		    actionPacket.Targets[1].Actions and #actionPacket.Targets[1].Actions > 0) then
			local spellId = actionPacket.Targets[1].Actions[1].Param;
			local spell = AshitaCore:GetResourceManager():GetSpellById(spellId);
			if (spell ~= nil and spell.Name[1] ~= nil) then
				local spellName = encoding:ShiftJIS_To_UTF8(spell.Name[1], true);
				-- Cast time is in quarter seconds (e.g., 40 = 10 seconds)
				local castTime = spell.CastTime / 4.0;
				targetbar.enemyCasts[actionPacket.UserId] = T{
					spellName = spellName,
					spellId = spellId,
					castTime = castTime,
					startTime = os.clock(),  -- High precision timestamp
					timestamp = os.time()    -- For cleanup
				};
			end
		end
	-- Type 4 = Magic (Finish) - Cast completed
	-- Type 11 = Monster Skill (Finish) - Some abilities
	elseif (actionPacket.Type == 4 or actionPacket.Type == 11) then
		-- Clear the cast for this enemy
		targetbar.enemyCasts[actionPacket.UserId] = nil;
	end

	-- Cleanup stale casts (older than 30 seconds)
	local now = os.time();
	for serverId, data in pairs(targetbar.enemyCasts) do
		if (data.timestamp + 30 < now) then
			targetbar.enemyCasts[serverId] = nil;
		end
	end
end

return targetbar;
