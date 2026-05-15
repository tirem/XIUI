require('common');
require('handlers.helpers');
local imgui = require('imgui');
local statusHandler = require('handlers.statushandler');
local debuffHandler = require('handlers.debuffhandler');
local actionTracker = require('handlers.actiontracker');
local progressbar = require('libs.progressbar');
local statusIcons = require('libs.statusicons');
local buffTable = require('libs.bufftable');
local imtext = require('libs.imtext');
local encoding = require('libs.encoding');
local ffi = require("ffi");
local defaultPositions = require('libs.defaultpositions');
local TextureManager = require('libs.texturemanager');
local mobdata = require('modules.mobinfo.data');

-- Position save/restore state
local hasAppliedSavedPosition = false;
local forcePositionReset = false;
local lastSavedPosX, lastSavedPosY = nil, nil;

-- TODO: Calculate these instead of manually setting them

local bgAlpha = 0.4;
local bgRadius = 3;

local arrowTexture;
local lockTexture;
local targetbar = {
	interpolation = {},
	enemyCasts = {}, -- Track enemy casting: [serverId] = {spellName, timestamp}
	-- Exported name text position for mob info snap feature
	nameTextInfo = {
		x = 0,        -- X position after name text ends
		y = 0,        -- Y position of name text
		visible = false, -- Whether target bar is currently visible
	},
};

-- Position constants
local POS_ABOVE = 0;
local POS_BELOW = 1;
local POS_LEFT = 2;
local POS_RIGHT = 3;

-- Check if target is player's pet
local function IsPet(idx, pEnt)
	return pEnt and pEnt.PetTargetIndex and pEnt.PetTargetIndex ~= 0 and idx == pEnt.PetTargetIndex;
end

-- Get HP gradient key based on entity type (for per-type HP bar coloring)
local function GetEntityHpGradientKey(entity, index)
	if entity == nil then return 'hpGradientMob'; end
	local flag = entity.SpawnFlags;
	if bit.band(flag, SPAWN_FLAG_PLAYER) == SPAWN_FLAG_PLAYER then
		if IsMemberOfParty(index) then
			return 'hpGradientPartyPlayer';
		end
		return 'hpGradientOtherPlayer';
	elseif bit.band(flag, SPAWN_FLAG_NPC) == SPAWN_FLAG_NPC then
		return 'hpGradientNpc';
	end
	return 'hpGradientMob';
end

local _XIUI_DEV_DEBUG_INTERPOLATION = false;
local _XIUI_DEV_DEBUG_INTERPOLATION_DELAY = 1;
local _XIUI_DEV_DEBUG_HP_PERCENT_PERSISTENT = 100;
local _XIUI_DEV_DAMAGE_SET_TIMES = {};

targetbar.DrawWindow = function(settings)
    -- Obtain the player entity..
    local playerEnt = GetPlayerEntity();
	local player = GetPlayerSafe();
    if (playerEnt == nil or player == nil) then
		targetbar.nameTextInfo.visible = false;
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
		targetbar.nameTextInfo.visible = false;
		targetbar.interpolation.interpolationDamagePercent = 0;

        return;
    end

	local currentTime = os.clock();
	local drawList = GetUIDrawList();

	local hppPercent = targetEntity.HPPercent;

	-- Mimic damage taken
	if _XIUI_DEV_DEBUG_INTERPOLATION then
		if _XIUI_DEV_DAMAGE_SET_TIMES[1] and currentTime > _XIUI_DEV_DAMAGE_SET_TIMES[1][1] then
			_XIUI_DEV_DEBUG_HP_PERCENT_PERSISTENT = _XIUI_DEV_DAMAGE_SET_TIMES[1][2];

			table.remove(_XIUI_DEV_DAMAGE_SET_TIMES, 1);
		end

		if #_XIUI_DEV_DAMAGE_SET_TIMES == 0 then
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
					previousHitTime = previousHitTime + _XIUI_DEV_DEBUG_INTERPOLATION_DELAY;
				end

				_XIUI_DEV_DAMAGE_SET_TIMES[i] = {previousHitTime, previousHp};
			end
		end

		hppPercent = _XIUI_DEV_DEBUG_HP_PERCENT_PERSISTENT;
	end

	-- If we change targets, reset the interpolation
	if targetbar.interpolation.currentTargetId ~= targetIndex then
		targetbar.interpolation.currentTargetId = targetIndex;
		targetbar.interpolation.currentHpp = hppPercent;
		targetbar.interpolation.interpolationDamagePercent = 0;
		targetbar.interpolation.interpolationHealPercent = 0;
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

		-- Clear healing interpolation when taking damage
		targetbar.interpolation.interpolationHealPercent = 0;
		targetbar.interpolation.healDelayStartTime = nil;
	elseif hppPercent > targetbar.interpolation.currentHpp then
		-- If the target heals
		local previousInterpolationHealPercent = targetbar.interpolation.interpolationHealPercent;

		local healAmount = hppPercent - targetbar.interpolation.currentHpp;

		targetbar.interpolation.interpolationHealPercent = targetbar.interpolation.interpolationHealPercent + healAmount;

		if previousInterpolationHealPercent > 0 and targetbar.interpolation.lastHealAmount and healAmount > targetbar.interpolation.lastHealAmount then
			targetbar.interpolation.lastHealTime = currentTime;
			targetbar.interpolation.lastHealAmount = healAmount;
		elseif previousInterpolationHealPercent == 0 then
			targetbar.interpolation.lastHealTime = currentTime;
			targetbar.interpolation.lastHealAmount = healAmount;
		end

		if not targetbar.interpolation.lastHealTime or currentTime > targetbar.interpolation.lastHealTime + (settings.hitFlashDuration * 0.25) then
			targetbar.interpolation.lastHealTime = currentTime;
			targetbar.interpolation.lastHealAmount = healAmount;
		end

		-- If we previously were interpolating with an empty bar, reset the heal delay effect
		if previousInterpolationHealPercent == 0 then
			targetbar.interpolation.healDelayStartTime = currentTime;
		end

		-- Clear damage interpolation when healing
		targetbar.interpolation.interpolationDamagePercent = 0;
		targetbar.interpolation.hitDelayStartTime = nil;
	end

	targetbar.interpolation.currentHpp = hppPercent;

	-- Reduce the damage HP amount to display based on the time passed since last frame
	if targetbar.interpolation.interpolationDamagePercent > 0 and targetbar.interpolation.hitDelayStartTime and currentTime > targetbar.interpolation.hitDelayStartTime + settings.hitDelayDuration then
		if targetbar.interpolation.lastFrameTime then
			local deltaTime = currentTime - targetbar.interpolation.lastFrameTime;

			local animSpeed = 0.1 + (0.9 * (targetbar.interpolation.interpolationDamagePercent / 100));

			targetbar.interpolation.interpolationDamagePercent = targetbar.interpolation.interpolationDamagePercent - (settings.hitInterpolationDecayPercentPerSecond * deltaTime * animSpeed);

			-- Clamp our percent to 0
			targetbar.interpolation.interpolationDamagePercent = math.max(0, targetbar.interpolation.interpolationDamagePercent);
		end
	end

	-- Reduce the healing HP amount to display based on the time passed since last frame
	if targetbar.interpolation.interpolationHealPercent > 0 and targetbar.interpolation.healDelayStartTime and currentTime > targetbar.interpolation.healDelayStartTime + settings.hitDelayDuration then
		if targetbar.interpolation.lastFrameTime then
			local deltaTime = currentTime - targetbar.interpolation.lastFrameTime;

			local animSpeed = 0.1 + (0.9 * (targetbar.interpolation.interpolationHealPercent / 100));

			targetbar.interpolation.interpolationHealPercent = targetbar.interpolation.interpolationHealPercent - (settings.hitInterpolationDecayPercentPerSecond * deltaTime * animSpeed);

			-- Clamp our percent to 0
			targetbar.interpolation.interpolationHealPercent = math.max(0, targetbar.interpolation.interpolationHealPercent);
		end
	end

	-- Calculate damage flash overlay
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

	-- Calculate healing flash overlay
	targetbar.interpolation.healOverlayAlpha = 0;
	if gConfig.healthBarFlashEnabled then
		if targetbar.interpolation.lastHealTime and currentTime < targetbar.interpolation.lastHealTime + settings.hitFlashDuration then
			local healFlashTime = currentTime - targetbar.interpolation.lastHealTime;
			local healFlashTimePercent = healFlashTime / settings.hitFlashDuration;

			local maxAlphaHealPercent = 20;
			local maxAlpha = math.min(targetbar.interpolation.lastHealAmount, maxAlphaHealPercent) / maxAlphaHealPercent;

			maxAlpha = math.max(maxAlpha * 0.6, 0.4);

			targetbar.interpolation.healOverlayAlpha = math.pow(1 - healFlashTimePercent, 2) * maxAlpha;
		end
	end

	targetbar.interpolation.lastFrameTime = currentTime;

	local color = GetColorOfTarget(targetEntity, targetIndex);
	local isMonster = GetIsMob(targetEntity);

	-- Draw the main target window
	-- Handle position reset or restore
	if forcePositionReset then
		local defX, defY = defaultPositions.GetTargetBarPosition();
		imgui.SetNextWindowPos({defX, defY}, ImGuiCond_Always);
		forcePositionReset = false;
		hasAppliedSavedPosition = true;
		lastSavedPosX, lastSavedPosY = defX, defY;
	elseif not hasAppliedSavedPosition and gConfig.targetBarWindowPosX ~= nil then
		imgui.SetNextWindowPos({gConfig.targetBarWindowPosX, gConfig.targetBarWindowPosY}, ImGuiCond_Once);
		hasAppliedSavedPosition = true;
		lastSavedPosX = gConfig.targetBarWindowPosX;
		lastSavedPosY = gConfig.targetBarWindowPosY;
	end

	local windowFlags = GetBaseWindowFlags(gConfig.lockPositions);
    ApplyWindowPosition('TargetBar');
    if (imgui.Begin('TargetBar', true, windowFlags)) then
        SaveWindowPosition('TargetBar');
        imtext.SetConfigFromSettings(settings.name_font_settings);

		-- Obtain and prepare target information..
		local dist  = ('%.1f'):fmt(math.sqrt(targetEntity.Distance));
		local targetNameText = targetEntity.Name;
		local targetHpPercent = targetEntity.HPPercent..'%';

		if (gConfig.showEnemyId and isMonster) then
			local entity = GetEntitySafe();
			if entity ~= nil then
				local targetServerId = entity:GetServerId(targetIndex);
				if (gConfig.showEnemyIdHex) then
					targetServerId = string.format('0x%X', targetServerId);
				end
				targetNameText = targetNameText .. " [".. string.sub(targetServerId, -3) .."]";
			end
		end

		-- Select HP gradient: per-type if enabled, otherwise single gradient
		local gradientKey = 'hpGradient';
		if gConfig.targetBarHpColorByType then
			gradientKey = GetEntityHpGradientKey(targetEntity, targetIndex);
		end
		local targetGradient = GetCustomGradient(gConfig.colorCustomization.targetBar, gradientKey) or {'#e26c6c', '#fb9494'};
		local hpGradientStart = targetGradient[1];
		local hpGradientEnd = targetGradient[2];

		-- Calculate base HP for display (subtract healing to show old HP during heal animation)
		local baseHpPercent = targetEntity.HPPercent;
		if targetbar.interpolation.interpolationHealPercent and targetbar.interpolation.interpolationHealPercent > 0 then
			baseHpPercent = targetEntity.HPPercent - targetbar.interpolation.interpolationHealPercent;
			baseHpPercent = math.max(0, baseHpPercent); -- Clamp to 0
		end

		local hpPercentData = {{baseHpPercent / 100, {hpGradientStart, hpGradientEnd}}};

		if _XIUI_DEV_DEBUG_INTERPOLATION then
			hpPercentData[1][1] = targetbar.interpolation.currentHpp / 100;
		end

		-- Get configurable interpolation colors
		local interpColors = GetHpInterpolationColors();

		if targetbar.interpolation.interpolationDamagePercent > 0 then
			local interpolationOverlay;

			if gConfig.healthBarFlashEnabled then
				interpolationOverlay = {
					interpColors.damageFlashColor,
					targetbar.interpolation.overlayAlpha
				};
			end

			table.insert(
				hpPercentData,
				{
					targetbar.interpolation.interpolationDamagePercent / 100,
					interpColors.damageGradient,
					interpolationOverlay
				}
			);
		end

		-- Add healing interpolation bar
		if targetbar.interpolation.interpolationHealPercent and targetbar.interpolation.interpolationHealPercent > 0 then
			local healInterpolationOverlay;

			if gConfig.healthBarFlashEnabled and targetbar.interpolation.healOverlayAlpha > 0 then
				healInterpolationOverlay = {
					interpColors.healFlashColor,
					targetbar.interpolation.healOverlayAlpha
				};
			end

			table.insert(
				hpPercentData,
				{
					targetbar.interpolation.interpolationHealPercent / 100,
					interpColors.healGradient,
					healInterpolationOverlay
				}
			);
		end

		-- Check if target is locked on (needed for both border and icon)
		local isLockedOn = GetIsTargetLockedOn();

		-- Reserve space above the bar for text/icons by expanding window content area upward
		-- This prevents clipping when drawing above the progress bar
		local lockIconSize = (lockTexture ~= nil) and lockTexture.height or 16;
		local topReserveHeight = settings.topTextYOffset + settings.name_font_settings.font_height + lockIconSize;
		imgui.Dummy({0, topReserveHeight});
		imgui.SetCursorPosY(imgui.GetCursorPosY() - topReserveHeight);

		local startX, startY = imgui.GetCursorScreenPos();

		-- Calculate bookend width and text padding (same as exp bar)
		local bookendWidth = gConfig.showTargetBarBookends and (settings.barHeight / 2) or 0;
		local textPadding = 8;

		-- Build progress bar options with optional enhanced border for lock-on
		local progressBarOptions = {decorate = gConfig.showTargetBarBookends};
		if (isLockedOn and gConfig.showTargetBarLockOnBorder) then
			progressBarOptions.enhancedBorder = color; -- Pass target color for enhanced border
		end

		progressbar.ProgressBar(hpPercentData, {settings.barWidth, settings.barHeight}, progressBarOptions);

		-- Draw lock icon if locked on (using draw list to avoid affecting cursor position)
		local lockIconOffset = 0;
		if (isLockedOn and gConfig.showTargetBarLockOnBorder and lockTexture ~= nil) then
			local lockWidth = lockTexture.width / 2;
			local lockHeight = lockTexture.height / 2;
			local lockX = startX + bookendWidth + textPadding;
			local lockY = startY - settings.topTextYOffset - lockHeight + 2;

			-- Draw using UI draw list (doesn't affect ImGui cursor)
			drawList:AddImage(
				tonumber(ffi.cast("uint32_t", lockTexture.image)),
				{lockX, lockY},
				{lockX + lockWidth, lockY + lockHeight},
				{0, 0}, {1, 1},
				IM_COL32_WHITE
			);
			lockIconOffset = lockWidth + 4;  -- Icon width + 4px spacing
		end

		-- Common positioning values
		local leftTextX = startX + bookendWidth + textPadding + lockIconOffset;
		local rightTextX = startX + settings.barWidth - bookendWidth - textPadding;
		local topTextY = startY - settings.topTextYOffset;
		local bottomTextY = startY + settings.barHeight + textPadding;
		local sideTextY = startY + (settings.barHeight / 2); -- Vertically centered

		-- Distance and HP% visibility flags
		local showDistance = gConfig.showTargetDistance;
		local showHpPercent = gConfig.showTargetHpPercent and (isMonster or gConfig.showTargetHpPercentAllTargets);

		-- Get position settings
		local namePos = gConfig.targetNamePosition or POS_ABOVE;
		local distPos = gConfig.targetDistancePosition or POS_ABOVE;
		local hpPos = gConfig.targetHpPercentPosition or POS_ABOVE;

		-- === POSITION NAME TEXT ===
		local nameFontSize = settings.name_font_settings.font_height;
		local nameWidth, nameHeight = imtext.Measure(targetNameText, nameFontSize);

		local nameX, nameY;
		if namePos == POS_ABOVE then
			nameX = leftTextX;
			nameY = topTextY - nameFontSize;
		elseif namePos == POS_BELOW then
			nameX = leftTextX;
			nameY = bottomTextY;
		elseif namePos == POS_LEFT then
			-- Right-align: position is right edge minus text width so text grows left
			nameX = startX - textPadding - nameWidth;
			nameY = sideTextY - (nameHeight / 2);
		else -- POS_RIGHT
			nameX = startX + settings.barWidth + textPadding + lockIconOffset;
			nameY = sideTextY - (nameHeight / 2);
		end

		if gConfig.showTargetName then
			imtext.Draw(drawList, targetNameText, nameX, nameY, color, nameFontSize);
		end

		-- Export name text position for mob info snap feature
		targetbar.nameTextInfo.x = nameX + nameWidth + 8;
		targetbar.nameTextInfo.y = nameY;
		targetbar.nameTextInfo.visible = true;

		-- === POSITION HP% TEXT ===
		if (showHpPercent) then
			imtext.SetConfigFromSettings(settings.percent_font_settings);
			local percentFontSize = settings.percent_font_settings.font_height;
			local percentWidth, percentHeight = imtext.Measure(targetHpPercent, percentFontSize);
			local percentOffsetX = settings.percentOffsetX or 0;
			local percentOffsetY = settings.percentOffsetY or 0;

			local percentX, percentY;
			if hpPos == POS_ABOVE then
				percentX = rightTextX + percentOffsetX - percentWidth;
				percentY = topTextY - percentFontSize + percentOffsetY;
			elseif hpPos == POS_BELOW then
				percentX = rightTextX + percentOffsetX - percentWidth;
				percentY = bottomTextY + percentOffsetY;
			elseif hpPos == POS_LEFT then
				-- Right-align: position is right edge minus text width so text grows left
				percentX = startX - textPadding - percentWidth + percentOffsetX;
				percentY = sideTextY - (percentHeight / 2) + percentOffsetY;
			else -- POS_RIGHT
				percentX = startX + settings.barWidth + textPadding + percentOffsetX;
				percentY = sideTextY - (percentHeight / 2) + percentOffsetY;
			end

			local desiredPercentColor, _ = GetHpColors(targetEntity.HPPercent / 100);
			imtext.Draw(drawList, targetHpPercent, percentX, percentY, desiredPercentColor, percentFontSize);
		end

		-- === POSITION DISTANCE TEXT ===
		if (showDistance) then
			imtext.SetConfigFromSettings(settings.distance_font_settings);
			local distFontSize = settings.distance_font_settings.font_height;
			local distString = tostring(dist);
			local distWidth, distHeight = imtext.Measure(distString, distFontSize);
			local distanceOffsetX = settings.distanceOffsetX or 0;
			local distanceOffsetY = settings.distanceOffsetY or 0;

			local distX, distY;
			if distPos == POS_ABOVE then
				-- When above, stack to the left of HP% if both are above
				local stackOffset = 0;
				if showHpPercent and hpPos == POS_ABOVE then
					imtext.SetConfigFromSettings(settings.percent_font_settings);
					local percentWidth, _ = imtext.Measure(targetHpPercent, settings.percent_font_settings.font_height);
					stackOffset = percentWidth + 8;
				end
				distX = rightTextX - stackOffset + distanceOffsetX - distWidth;
				distY = topTextY - distFontSize + distanceOffsetY;
			elseif distPos == POS_BELOW then
				-- When below, stack to the left of HP% if both are below
				local stackOffset = 0;
				if showHpPercent and hpPos == POS_BELOW then
					imtext.SetConfigFromSettings(settings.percent_font_settings);
					local percentWidth, _ = imtext.Measure(targetHpPercent, settings.percent_font_settings.font_height);
					stackOffset = percentWidth + 8;
				end
				distX = rightTextX - stackOffset + distanceOffsetX - distWidth;
				distY = bottomTextY + distanceOffsetY;
			elseif distPos == POS_LEFT then
				-- Right-align: position is right edge minus text width so text grows left
				-- When left, stack above HP% if both are left
				local stackOffset = 0;
				if showHpPercent and hpPos == POS_LEFT then
					imtext.SetConfigFromSettings(settings.percent_font_settings);
					local _, percentHeight = imtext.Measure(targetHpPercent, settings.percent_font_settings.font_height);
					stackOffset = percentHeight + 2;
				end
				distX = startX - textPadding - distWidth + distanceOffsetX;
				distY = sideTextY - (distHeight / 2) - stackOffset + distanceOffsetY;
			else -- POS_RIGHT
				-- When right, stack above HP% if both are right
				local stackOffset = 0;
				if showHpPercent and hpPos == POS_RIGHT then
					imtext.SetConfigFromSettings(settings.percent_font_settings);
					local _, percentHeight = imtext.Measure(targetHpPercent, settings.percent_font_settings.font_height);
					stackOffset = percentHeight + 2;
				end
				distX = startX + settings.barWidth + textPadding + distanceOffsetX;
				distY = sideTextY - (distHeight / 2) - stackOffset + distanceOffsetY;
			end

			imtext.SetConfigFromSettings(settings.distance_font_settings);
			local desiredDistColor = gConfig.colorCustomization.targetBar.distanceTextColor;
			imtext.Draw(drawList, distString, distX, distY, desiredDistColor, distFontSize);
		end

		-- Draw enemy cast bar and text if casting (or in config mode) and if enabled
		local castData = targetbar.enemyCasts[targetEntity.ServerId];

		-- Create test cast data for config mode
		if (inConfigMode and castData == nil) then
			castData = T{
				spellName = "Fire III",
				castTime = 5.0,  -- 5 second cast
				startTime = os.clock() - ((os.clock() % 5.0)),  -- Loops every 5 seconds
			};
		end

		if (gConfig.showTargetBarCastBar and (not HzLimitedMode) and castData ~= nil and castData.spellName ~= nil and castData.castTime ~= nil and castData.startTime ~= nil) then
			-- Calculate cast progress
			local elapsed = os.clock() - castData.startTime;
			local progress = math.min(elapsed / castData.castTime, 1.0);

			-- Draw cast bar under HP bar using user-configurable offsets and scaling
			local castBarY = startY + settings.barHeight + settings.castBarOffsetY;
			-- Right-align the cast bar with the HP bar (accounting for bookends and 12px padding)
			local castBarX = startX + settings.barWidth - bookendWidth - settings.castBarWidth - 12 + settings.castBarOffsetX;

			-- Cast bar settings (using adjusted settings)
			local castBarHeight = settings.castBarHeight;
			local castBarWidth = settings.castBarWidth;
			local castGradient = GetCustomGradient(gConfig.colorCustomization.targetBar, 'castBarGradient') or {'#ffaa00', '#ffcc44'};

			-- Draw cast bar with absolute positioning (doesn't affect ImGui layout)
			progressbar.ProgressBar(
				{{progress, castGradient}},
				{castBarWidth, castBarHeight},
				{
					decorate = gConfig.showTargetBarBookends,
					absolutePosition = {castBarX, castBarY}
				}
			);

			-- Draw cast text below the cast bar (centered on cast bar)
			imtext.SetConfigFromSettings(settings.cast_font_settings);
			local castFontSize = settings.cast_font_settings.font_height;
			local castDisplayText = inConfigMode and "Fire III (Demo)" or castData.spellName;
			local castWidth, _ = imtext.Measure(castDisplayText, castFontSize);
			local centerX = castBarX + (castBarWidth / 2);
			local castColor = gConfig.colorCustomization.targetBar.castTextColor;
			imtext.Draw(drawList, castDisplayText, centerX - castWidth / 2, castBarY + castBarHeight + 2, castColor, castFontSize);
		end

		-- Draw buffs and debuffs
		imgui.SameLine();
		local preBuffX, preBuffY = imgui.GetCursorScreenPos();
		local buffIds;
        local buffTimes = nil;
		if (targetEntity == playerEnt) then
			buffIds = player:GetBuffs();
		elseif (IsMemberOfParty(targetIndex)) then
			-- Use targetEntity.ServerId instead of playerTarget:GetServerId(0)
			-- because targetIndex may have been swapped by GetTargets() for subtargets
			buffIds = statusHandler.get_member_status(targetEntity.ServerId);
		elseif (isMonster) then
			buffIds, buffTimes = debuffHandler.GetActiveDebuffs(targetEntity.ServerId);
		end
		-- Preview: inject dummy debuffs with timers when config is open
		if showConfig[1] then
			buffIds = {2, 3, 4, 5, 6};
			buffTimes = {45, 120, 8, 210, 30};
		end
		imgui.NewLine();
		-- Apply buffs offset Y
		if settings.buffsOffsetY ~= 0 then
			imgui.SetCursorPosY(imgui.GetCursorPosY() + settings.buffsOffsetY);
		end
		imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {1, 3});
		-- Reorder to show debuffs first for easier identification
		-- Pass buffTimes so they get reordered in tandem with buffIds
		local reorderedBuffs, reorderedTimes = statusIcons.ReorderDebuffsFirst(buffIds, buffTable, buffTimes);
		DrawStatusIcons(reorderedBuffs, settings.iconSize, settings.maxIconColumns, 3, false, settings.barHeight/2, reorderedTimes, nil);
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

				-- Get interpolated HP data for ToT bar using shared helper
				local totGradientKey = 'hpGradient';
				if gConfig.targetBarHpColorByType then
					totGradientKey = GetEntityHpGradientKey(totEntity, totIndex);
				end
				local totGradient = GetCustomGradient(gConfig.colorCustomization.totBar, totGradientKey) or {'#e16c6c', '#fb9494'};
				local totHpPercentData = HpInterpolation.update('tot', totEntity.HPPercent, totIndex, settings, currentTime, totGradient);
				progressbar.ProgressBar(totHpPercentData, {settings.barWidth / 3, settings.totBarHeight}, {decorate = gConfig.showTargetBarBookends});
				-- Submit a dummy item to properly extend window bounds after SetCursorScreenPos
				imgui.Dummy({1, 1});

				-- Left-aligned text position (ToT name) - 8px from left edge (after bookend)
				local totLeftTextX = totStartX + totBookendWidth + totTextPadding;
				imtext.SetConfigFromSettings(settings.totName_font_settings);
				local totFontSize = settings.totName_font_settings.font_height;
				local totName = IsPet(totIndex, playerEnt) and (totEntity.Name .. ' (Pet)') or totEntity.Name;
				imtext.Draw(drawList, totName, totLeftTextX, totStartY - totFontSize - 4, totColor, totFontSize);
			end
		end

		-- Reserve space for cast bar at bottom of window to prevent clipping
		-- Calculate total height needed: offset Y + bar height + text spacing + text height
		if (gConfig.showTargetBarCastBar and (not HzLimitedMode) and castData ~= nil and castData.spellName ~= nil) then
			local castTextHeight = settings.cast_font_settings.font_height;
			local totalCastBarSpace = settings.castBarOffsetY + settings.castBarHeight + 2 + castTextHeight;
			imgui.Dummy({0, totalCastBarSpace});
		end
		-- Save position if moved (with change detection to avoid spam)
		local winPosX, winPosY = imgui.GetWindowPos();
		if not gConfig.lockPositions then
			if lastSavedPosX == nil or
			   math.abs(winPosX - lastSavedPosX) > 1 or
			   math.abs(winPosY - lastSavedPosY) > 1 then
				gConfig.targetBarWindowPosX = winPosX;
				gConfig.targetBarWindowPosY = winPosY;
				lastSavedPosX = winPosX;
				lastSavedPosY = winPosY;
			end
		end
    end
    imgui.End();

	-- Draw Subtarget Bar (shows subtarget cursor selection while subtargeting)
	if (gConfig.showSubtargetBar) then
		local subTargetActive = GetSubTargetActive();
		local _, secondaryTargetIndex = GetTargets();
		-- After GetTargets() swap: secondaryTargetIndex = subtarget cursor (what you're selecting)

		if (subTargetActive and secondaryTargetIndex ~= nil and secondaryTargetIndex ~= 0) then
			local subtargetEntity = GetEntity(secondaryTargetIndex);

			if (subtargetEntity ~= nil and subtargetEntity.Name ~= nil) then
				local subtargetWindowFlags = GetBaseWindowFlags(gConfig.lockPositions);

				if (imgui.Begin('SubtargetBar', true, subtargetWindowFlags)) then
					-- Reserve space above bar for text
					local topReserveHeight = settings.topTextYOffset + settings.subtargetName_font_settings.font_height;
					imgui.Dummy({0, topReserveHeight});
					imgui.SetCursorPosY(imgui.GetCursorPosY() - topReserveHeight);

					local stStartX, stStartY = imgui.GetCursorScreenPos();
					local subtargetColor = GetColorOfTarget(subtargetEntity, secondaryTargetIndex);
					local stIsMonster = GetIsMob(subtargetEntity);

					-- Calculate bookend width and text padding
					local stShowBookends = gConfig.subtargetBarShowBookends;
					local stBookendWidth = stShowBookends and (settings.subtargetBarHeight / 2) or 0;
					local stTextPadding = 8;

					-- Get HP gradient for subtarget bar
					local stHpGradient = GetCustomGradient(gConfig.colorCustomization.subtargetBar, 'hpGradient') or {'#e26c6c', '#fb9494'};
					local stHpPercentData = {{subtargetEntity.HPPercent / 100, stHpGradient}};

					-- Draw progress bar
					progressbar.ProgressBar(stHpPercentData, {settings.subtargetBarWidth, settings.subtargetBarHeight}, {decorate = stShowBookends});

					-- Build name text with mob level if applicable
					local stNameDisplay = subtargetEntity.Name;
					if stIsMonster and gConfig.subtargetBarShowMobLevel then
						local mobInfo = mobdata.GetMobInfo(subtargetEntity.Name, secondaryTargetIndex);
						if mobInfo then
							local levelStr = mobdata.GetLevelString(mobInfo);
							if levelStr and levelStr ~= '' then
								stNameDisplay = stNameDisplay .. ' ' .. levelStr;
							end
						end
					end

					-- Draw name text above bar (left-aligned, X = left edge)
					imtext.SetConfigFromSettings(settings.subtargetName_font_settings);
					local stNameFontSize = settings.subtargetName_font_settings.font_height;
					imtext.Draw(drawList, stNameDisplay, stStartX + stBookendWidth + stTextPadding, stStartY - stNameFontSize - 4, subtargetColor, stNameFontSize);

					-- Calculate right-side text positions (distance and HP%)
					local stRightEdge = stStartX + settings.subtargetBarWidth - stBookendWidth - stTextPadding;
					imtext.SetConfigFromSettings(settings.subtargetPercent_font_settings);
					local stPercentFontSize = settings.subtargetPercent_font_settings.font_height;
					local stTextY = stStartY - stPercentFontSize - 4;

					-- Draw HP% text if enabled (rightmost, left-aligned font with manual positioning)
					local stShowHpPercent = gConfig.subtargetBarShowHpPercent;
					local stPercentWidth = 0;
					if (stShowHpPercent) then
						local stHpText = subtargetEntity.HPPercent .. '%';
						stPercentWidth, _ = imtext.Measure(stHpText, stPercentFontSize);
						local stPercentColor, _ = GetHpColors(subtargetEntity.HPPercent / 100);
						-- Right-align: position is right edge minus text width
						imtext.Draw(drawList, stHpText, stRightEdge - stPercentWidth, stTextY, stPercentColor, stPercentFontSize);
					end

					-- Draw distance text if enabled (to the left of HP%)
					if (gConfig.subtargetBarShowDistance) then
						local stDist = ('%.1f'):fmt(math.sqrt(subtargetEntity.Distance));
						local stDistWidth, _ = imtext.Measure(stDist, stPercentFontSize);
						local stDistX;
						if stShowHpPercent then
							-- Position to the left of HP% with 8px gap
							stDistX = stRightEdge - stPercentWidth - 8 - stDistWidth;
						else
							stDistX = stRightEdge - stDistWidth;
						end
						local stDistColor = (gConfig.colorCustomization.subtargetBar and gConfig.colorCustomization.subtargetBar.distanceTextColor) or 0xFFFFFFFF;
						imtext.Draw(drawList, stDist, stDistX, stTextY, stDistColor, stPercentFontSize);
					end
				end
				imgui.End();
			end
		end
	end

	-- Draw separate Target of Target window if split is enabled
	if (gConfig.splitTargetOfTarget) then
		-- Obtain the player entity
		local playerEnt = GetPlayerEntity();
		local player = GetPlayerSafe();
		if (playerEnt == nil or player == nil) then
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
			local windowFlags = GetBaseWindowFlags(gConfig.lockPositions);

			if (imgui.Begin('TargetOfTargetBar', true, windowFlags)) then
				local totColor = GetColorOfTarget(totEntity, totIndex);
				local totStartX, totStartY = imgui.GetCursorScreenPos();

				-- Calculate bookend width and text padding for split ToT bar
				local totBookendWidthSplit = gConfig.showTargetBarBookends and (settings.totBarHeightSplit / 2) or 0;
				local totTextPaddingSplit = 8;

				-- Get interpolated HP data for split ToT bar using shared helper
				local totGradientKeySplit = 'hpGradient';
				if gConfig.targetBarHpColorByType then
					totGradientKeySplit = GetEntityHpGradientKey(totEntity, totIndex);
				end
				local totGradientSplit = GetCustomGradient(gConfig.colorCustomization.totBar, totGradientKeySplit) or {'#e16c6c', '#fb9494'};
				local totHpPercentDataSplit = HpInterpolation.update('tot', totEntity.HPPercent, totIndex, settings, currentTime, totGradientSplit);
				progressbar.ProgressBar(totHpPercentDataSplit, {settings.totBarWidth, settings.totBarHeightSplit}, {decorate = gConfig.showTargetBarBookends});

				-- Left-aligned text position (ToT name) - 8px from left edge (after bookend)
				local totLeftTextXSplit = totStartX + totBookendWidthSplit + totTextPaddingSplit;
				imtext.SetConfigFromSettings(settings.totName_font_settings_split);
				local totFontSizeSplit = settings.totName_font_settings_split.font_height;
				local pEnt = GetPlayerEntity();
				local totName = IsPet(totIndex, pEnt) and (totEntity.Name .. ' (Pet)') or totEntity.Name;
				imtext.Draw(drawList, totName, totLeftTextXSplit, totStartY - totFontSizeSplit - 4, totColor, totFontSizeSplit);
			end
			imgui.End();
		end
	end
end

targetbar.Initialize = function(settings)
	arrowTexture = TextureManager.getFileTexture("arrow");
	lockTexture = TextureManager.getFileTexture("lock");

	-- Query lock texture dimensions
	if (lockTexture ~= nil) then
		local texture_ptr = ffi.cast('IDirect3DTexture8*', lockTexture.image);
		local res, desc = texture_ptr:GetLevelDesc(0);
		if (desc ~= nil) then
			lockTexture.width = desc.Width;
			lockTexture.height = desc.Height;
		else
			lockTexture.width = 16;
			lockTexture.height = 16;
		end
	end
end

targetbar.UpdateVisuals = function(settings)
	imtext.Reset();
end

targetbar.SetHidden = function(hidden)
end

targetbar.Cleanup = function()
end

targetbar.ResetPositions = function()
	forcePositionReset = true;
	hasAppliedSavedPosition = false;
end

targetbar.HandleActionPacket = function(actionPacket)
	if (actionPacket == nil or actionPacket.UserId == nil) then
		return;
	end

	-- Type 8 = Magic (Start) - Enemy begins casting
	if (actionPacket.Type == 8) then
		-- According to XiPackets: interrupted casts send ANOTHER Type 8 with "sp" prefix (vs "ca" for normal start)
		-- We can't parse the prefix directly, but if we get Type 8 for the SAME spell that's already active,
		-- it's likely the interruption packet - clear the cast instead of restarting it

		-- Get the spell ID from the action
		if (actionPacket.Targets and #actionPacket.Targets > 0 and
		    actionPacket.Targets[1].Actions and #actionPacket.Targets[1].Actions > 0) then
			local spellId = actionPacket.Targets[1].Actions[1].Param;
			local existingCast = targetbar.enemyCasts[actionPacket.UserId];

			-- If we already have an active cast for THE SAME spell, this is likely the interruption packet
			if (existingCast ~= nil and existingCast.spellId == spellId) then
				-- Second Type 8 for same spell = interruption signal, clear the cast
				targetbar.enemyCasts[actionPacket.UserId] = nil;
				return; -- Don't create new cast data
			end

			-- If we have a cast for a DIFFERENT spell, clear it (new cast started)
			if (existingCast ~= nil and existingCast.spellId ~= spellId) then
				targetbar.enemyCasts[actionPacket.UserId] = nil;
			end

			-- Create new cast data (first Type 8 for this spell)
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
