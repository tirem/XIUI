require('common');
require('helpers');
local imgui = require('imgui');
local statusHandler = require('statushandler');
local debuffHandler = require('debuffhandler');
local progressbar = require('progressbar');
local gdi = require('gdifonts.include');
local ffi = require("ffi");

-- TODO: Calculate these instead of manually setting them

local bgAlpha = 0.4;
local bgRadius = 3;

local arrowTexture;
local percentText;
local nameText;
local totNameText;
local distText;
local targetbar = {
	interpolation = {}
};

-- Cache last set colors to avoid expensive SetColor() calls every frame
local lastNameTextColor;
local lastPercentTextColor;
local lastTotNameTextColor;

local function UpdateTextVisibility(visible)
	percentText:set_visible(visible);
	nameText:set_visible(visible);
	totNameText:set_visible(visible);
	distText:set_visible(visible);
end

local _HXUI_DEV_DEBUG_INTERPOLATION = false;
local _HXUI_DEV_DEBUG_INTERPOLATION_DELAY = 1;
local _HXUI_DEV_DEBUG_HP_PERCENT_PERSISTENT = 100;
local _HXUI_DEV_DAMAGE_SET_TIMES = {};

targetbar.DrawWindow = function(settings)
    -- Obtain the player entity..
    local playerEnt = GetPlayerEntity();
	local player = GetPlayerSafe();
    if (playerEnt == nil or player == nil) then
		UpdateTextVisibility(false);
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
		UpdateTextVisibility(false);
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
		progressbar.ProgressBar(hpPercentData, {settings.barWidth, settings.barHeight}, {decorate = gConfig.showTargetBarBookends});

		-- Dynamically set font heights based on settings (avoids expensive font recreation)
		nameText:set_font_height(settings.name_font_settings.font_height);
		percentText:set_font_height(settings.percent_font_settings.font_height);
		distText:set_font_height(settings.distance_font_settings.font_height);

		local nameWidth, nameHeight = nameText:get_text_size();

		nameText:set_position_x(startX + settings.barHeight / 2 + settings.topTextXOffset);
		nameText:set_position_y(startY - settings.topTextYOffset - nameHeight);
		-- Only call set_font_color if the color has changed (expensive operation for GDI fonts)
		if (lastNameTextColor ~= color) then
			nameText:set_font_color(color);
			lastNameTextColor = color;
		end
		nameText:set_text(targetNameText);
		nameText:set_visible(true);

		local distWidth, distHeight = distText:get_text_size();

		distText:set_position_x(startX + settings.barWidth - settings.barHeight / 2 - settings.topTextXOffset);
		distText:set_position_y(startY - settings.topTextYOffset - distHeight);
		distText:set_text(tostring(dist));
		if (gConfig.showTargetDistance) then
			distText:set_visible(true);
		else
			distText:set_visible(false);
		end

		if (isMonster or gConfig.alwaysShowHealthPercent) then
			percentText:set_position_x(startX + settings.barWidth - settings.barHeight / 2 - settings.bottomTextXOffset);
			percentText:set_position_y(startY + settings.barHeight + settings.bottomTextYOffset);
			percentText:set_text(tostring(targetHpPercent));
			percentText:set_visible(true);
			local hpColor, _ = GetHpColors(targetEntity.HPPercent / 100);
			-- Only call set_font_color if the color has changed
			if (lastPercentTextColor ~= hpColor) then
				percentText:set_font_color(hpColor);
				lastPercentTextColor = hpColor;
			end
		else
			percentText:set_visible(false);
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

		-- Obtain our target of target (not always accurate)
		local totEntity;
		local totIndex
		if (targetEntity == playerEnt) then
			totIndex = targetIndex
			totEntity = targetEntity;
		end
		if (totEntity == nil) then
			totIndex = targetEntity.TargetedIndex;
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

				imgui.SetCursorScreenPos({preBuffX, preBuffY});
				local totX, totY = imgui.GetCursorScreenPos();
				local totColor = GetColorOfTarget(totEntity, totIndex);
				imgui.SetCursorScreenPos({totX, totY + settings.barHeight/2 - settings.arrowSize/2});
				imgui.Image(tonumber(ffi.cast("uint32_t", arrowTexture.image)), { settings.arrowSize, settings.arrowSize });
				imgui.SameLine();

				totX, _ = imgui.GetCursorScreenPos();
				imgui.SetCursorScreenPos({totX, totY - (settings.totBarHeight / 2) + (settings.barHeight/2) + settings.totBarOffset});

				local totStartX, totStartY = imgui.GetCursorScreenPos();
				local totGradient = GetCustomGradient(gConfig.colorCustomization.totBar, 'hpGradient') or {'#e16c6c', '#fb9494'};
				progressbar.ProgressBar({{totEntity.HPPercent / 100, totGradient}}, {settings.barWidth / 3, settings.totBarHeight}, {decorate = gConfig.showTargetBarBookends});

				-- Dynamically set font height for ToT text
				totNameText:set_font_height(settings.totName_font_settings.font_height);

				local totNameWidth, totNameHeight = totNameText:get_text_size();

				totNameText:set_position_x(totStartX + settings.barHeight / 2);
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

		-- Obtain target of target
		local totEntity;
		local totIndex;
		if (targetEntity == playerEnt) then
			totIndex = targetIndex;
			totEntity = targetEntity;
		end
		if (totEntity == nil) then
			totIndex = targetEntity.TargetedIndex;
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

				-- Use adjusted ToT settings for split bar
				local totGradientSplit = GetCustomGradient(gConfig.colorCustomization.totBar, 'hpGradient') or {'#e16c6c', '#fb9494'};
				progressbar.ProgressBar({{totEntity.HPPercent / 100, totGradientSplit}}, {settings.totBarWidth, settings.totBarHeightSplit}, {decorate = gConfig.showTargetBarBookends});

				-- Set font height for split ToT bar
				totNameText:set_font_height(settings.totName_font_settings_split.font_height);

				local totNameWidth, totNameHeight = totNameText:get_text_size();

				totNameText:set_position_x(totStartX + settings.barHeight / 2);
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
    percentText = gdi:create_object(settings.percent_font_settings);
	nameText = gdi:create_object(settings.name_font_settings);
	totNameText = gdi:create_object(settings.totName_font_settings);
	distText = gdi:create_object(settings.distance_font_settings);
	arrowTexture = 	LoadTexture("arrow");
end

targetbar.UpdateFonts = function(settings)
	-- Destroy old font objects
	if (percentText ~= nil) then gdi:destroy_object(percentText); end
	if (nameText ~= nil) then gdi:destroy_object(nameText); end
	if (totNameText ~= nil) then gdi:destroy_object(totNameText); end
	if (distText ~= nil) then gdi:destroy_object(distText); end

	-- Recreate font objects with new settings
    percentText = gdi:create_object(settings.percent_font_settings);
	nameText = gdi:create_object(settings.name_font_settings);
	totNameText = gdi:create_object(settings.totName_font_settings);
	distText = gdi:create_object(settings.distance_font_settings);

	-- Reset cached colors when fonts are recreated
	lastNameTextColor = nil;
	lastPercentTextColor = nil;
	lastTotNameTextColor = nil;
end

targetbar.SetHidden = function(hidden)
	if (hidden == true) then
		UpdateTextVisibility(false);
	end
end

targetbar.Cleanup = function()
	-- Destroy all font objects on unload
	if (percentText ~= nil) then gdi:destroy_object(percentText); percentText = nil; end
	if (nameText ~= nil) then gdi:destroy_object(nameText); nameText = nil; end
	if (totNameText ~= nil) then gdi:destroy_object(totNameText); totNameText = nil; end
	if (distText ~= nil) then gdi:destroy_object(distText); distText = nil; end
end

return targetbar;
