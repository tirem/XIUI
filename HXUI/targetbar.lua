require('common');
require('helpers');
local imgui = require('imgui');
local statusHandler = require('statushandler');
local debuffHandler = require('debuffhandler');
local progressbar = require('progressbar');
local fonts = require('fonts');
local ffi = require("ffi");

-- TODO: Calculate these instead of manually setting them

local bgAlpha = 0.4;
local bgRadius = 3;

local arrowTexture;
local percentText;
local nameText;
local totNameText;
local distText;
local targetbar = {};

local function UpdateTextVisibility(visible)
	percentText:SetVisible(visible);
	nameText:SetVisible(visible);
	totNameText:SetVisible(visible);
	distText:SetVisible(visible);
end

local _HXUI_DEV_DEBUG_INTERPOLATION = false;
local _HXUI_DEV_DEBUG_INTERPOLATION_DELAY, _HXUI_DEV_DEBUG_INTERPOLATION_NEXT_TIME;

if _HXUI_DEV_DEBUG_INTERPOLATION then
	_HXUI_DEV_DEBUG_INTERPOLATION_DELAY = 2;
	_HXUI_DEV_DEBUG_INTERPOLATION_NEXT_TIME = os.time() + _HXUI_DEV_DEBUG_INTERPOLATION_DELAY;
end

targetbar.DrawWindow = function(settings)
    -- Obtain the player entity..
    local playerEnt = GetPlayerEntity();
	local player = AshitaCore:GetMemoryManager():GetPlayer();
    if (playerEnt == nil or player == nil) then
		UpdateTextVisibility(false);
        return;
    end

    -- Obtain the player target entity (account for subtarget)
	local playerTarget = AshitaCore:GetMemoryManager():GetTarget();
	local targetIndex;
	local targetEntity;
	if (playerTarget ~= nil) then
		targetIndex, _ = GetTargets();
		targetEntity = GetEntity(targetIndex);
	end
    if (targetEntity == nil or targetEntity.Name == nil) then
		UpdateTextVisibility(false);
        return;
    end

    local currentTime = os.clock();

    if targetbar.currentTargetId == targetIndex then
    	if targetEntity.HPPercent < targetbar.currentHPP then
    		targetbar.previousHPP = targetbar.currentHPP;
    		targetbar.currentHPP = targetEntity.HPPercent;
    		targetbar.lastHitTime = currentTime;
    	end
    else
    	targetbar.currentTargetId = targetIndex;
    	targetbar.currentHPP = targetEntity.HPPercent;
    	targetbar.previousHPP = targetEntity.HPPercent;
    end

    if _HXUI_DEV_DEBUG_INTERPOLATION then
	    if os.time() > _HXUI_DEV_DEBUG_INTERPOLATION_NEXT_TIME then
	    	targetbar.previousHPP = 75;
	    	targetbar.currentHPP = 50;
			targetbar.lastHitTime = currentTime;

			_HXUI_DEV_DEBUG_INTERPOLATION_NEXT_TIME = os.time() + 2;
	    end
	end

    local interpolationPercent;
    local interpolationOverlayAlpha = 0;

    if targetbar.currentHPP < targetbar.previousHPP then
    	local hppDelta = targetbar.previousHPP - targetbar.currentHPP;

    	if currentTime > targetbar.lastHitTime + settings.hitDelayLength then
    		-- local interpolationTimeTotal = settings.hitInterpolationMaxTime * (hppDelta / 100);
    		local interpolationTimeTotal = settings.hitInterpolationMaxTime;
    		local interpolationTimeElapsed = currentTime - targetbar.lastHitTime - settings.hitDelayLength;

    		if interpolationTimeElapsed <= interpolationTimeTotal then
    			local interpolationTimeElapsedPercent = easeOutPercent(interpolationTimeElapsed / interpolationTimeTotal);

    			interpolationPercent = hppDelta * (1 - interpolationTimeElapsedPercent);
    		end
    	elseif currentTime - targetbar.lastHitTime <= settings.hitDelayLength then
    		interpolationPercent = hppDelta;

    		local hitDelayTime = currentTime - targetbar.lastHitTime;
    		local hitDelayHalfDuration = settings.hitDelayLength / 2;

    		if hitDelayTime > hitDelayHalfDuration then
    			interpolationOverlayAlpha = 1 - ((hitDelayTime - hitDelayHalfDuration) / hitDelayHalfDuration);
    		else
    			interpolationOverlayAlpha = hitDelayTime / hitDelayHalfDuration;
    		end
    	end
    end

	local color = GetColorOfTarget(targetEntity, targetIndex);
	local isMonster = GetIsMob(targetEntity);

	-- Draw the main target window
    if (imgui.Begin('TargetBar', true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground))) then
        
		-- Obtain and prepare target information..
        local dist  = ('%.1f'):fmt(math.sqrt(targetEntity.Distance));
		local targetNameText = targetEntity.Name;
		local targetHpPercent = targetEntity.HPPercent..'%';

		if (gConfig.showEnemyId and isMonster) then
			local targetServerId = AshitaCore:GetMemoryManager():GetEntity():GetServerId(targetIndex);
			local targetServerIdHex = string.format('0x%X', targetServerId);

			targetNameText = targetNameText .. " [".. string.sub(targetServerIdHex, -3) .."]";
		end

		local hpGradientStart = '#e16c6c';
		local hpGradientEnd = '#fb9494';

		local hpPercentData = {{targetEntity.HPPercent / 100, {hpGradientStart, hpGradientEnd}}};

		if _HXUI_DEV_DEBUG_INTERPOLATION then
			hpPercentData[1][1] = 0.5;
		end

		if interpolationPercent then
			table.insert(
				hpPercentData,
				{
					interpolationPercent / 100, -- interpolation percent
					{'#cf3437', '#c54d4d'}, -- interpolation gradient
					{
						'#ffacae', -- overlay color,
						interpolationOverlayAlpha -- overlay alpha
					}
				}
			);
		end
		
		local startX, startY = imgui.GetCursorScreenPos();
		progressbar.ProgressBar(hpPercentData, {settings.barWidth, settings.barHeight});

		local nameSize = SIZE.new();
		nameText:GetTextSize(nameSize);

		nameText:SetPositionX(startX + settings.barHeight / 2 + settings.topTextXOffset);
		nameText:SetPositionY(startY - settings.topTextYOffset - nameSize.cy);
		nameText:SetColor(color);
		nameText:SetText(targetNameText);
		nameText:SetVisible(true);

		local distSize = SIZE.new();
		distText:GetTextSize(distSize);

		distText:SetPositionX(startX + settings.barWidth - settings.barHeight / 2 - settings.topTextXOffset);
		distText:SetPositionY(startY - settings.topTextYOffset - distSize.cy);
		distText:SetText(tostring(dist));
		distText:SetVisible(true);

		if (isMonster or gConfig.alwaysShowHealthPercent) then
			percentText:SetPositionX(startX + settings.barWidth - settings.barHeight / 2 - settings.bottomTextXOffset);
			percentText:SetPositionY(startY + settings.barHeight + settings.bottomTextYOffset);
			percentText:SetText(tostring(targetHpPercent));
			percentText:SetVisible(true);
			local hpColor, _ = GetHpColors(targetEntity.HPPercent / 100);
			percentText:SetColor(hpColor);
		else
			percentText:SetVisible(false);
		end

		-- Draw buffs and debuffs
		imgui.SameLine();
		local preBuffX, preBuffY = imgui.GetCursorScreenPos();
		local buffIds;
		if (targetEntity == playerEnt) then
			buffIds = player:GetBuffs();
		elseif (IsMemberOfParty(targetIndex)) then
			buffIds = statusHandler.get_member_status(playerTarget:GetServerId(0));
		else
			buffIds = debuffHandler.GetActiveDebuffs(playerTarget:GetServerId(0));
		end
		imgui.NewLine();
		imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {1, 3});
		DrawStatusIcons(buffIds, settings.iconSize, settings.maxIconColumns, 3, false, settings.barHeight/2);
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
		if (totEntity ~= nil and totEntity.Name ~= nil) then

			imgui.SetCursorScreenPos({preBuffX, preBuffY});
			local totX, totY = imgui.GetCursorScreenPos();
			local totColor = GetColorOfTarget(totEntity, totIndex);
			imgui.SetCursorScreenPos({totX, totY + settings.barHeight/2 - settings.arrowSize/2});
			imgui.Image(tonumber(ffi.cast("uint32_t", arrowTexture.image)), { settings.arrowSize, settings.arrowSize });
			imgui.SameLine();

			totX, _ = imgui.GetCursorScreenPos();
			imgui.SetCursorScreenPos({totX, totY - (settings.totBarHeight / 2) + (settings.barHeight/2) + settings.totBarOffset});

			local totStartX, totStartY = imgui.GetCursorScreenPos();
			progressbar.ProgressBar({{totEntity.HPPercent / 100, {'#e16c6c', '#fb9494'}}}, {settings.barWidth / 3, settings.totBarHeight});

			local totNameSize = SIZE.new();
			totNameText:GetTextSize(totNameSize);

			totNameText:SetPositionX(totStartX + settings.barHeight / 2);
			totNameText:SetPositionY(totStartY - totNameSize.cy);
			totNameText:SetColor(totColor);
			totNameText:SetText(totEntity.Name);
			totNameText:SetVisible(true);
		else
			totNameText:SetVisible(false);
		end
    end
	local winPosX, winPosY = imgui.GetWindowPos();
    imgui.End();
end

targetbar.Initialize = function(settings)
    percentText = fonts.new(settings.percent_font_settings);
	nameText = fonts.new(settings.name_font_settings);
	totNameText = fonts.new(settings.totName_font_settings);
	distText = fonts.new(settings.distance_font_settings);
	arrowTexture = 	LoadTexture("arrow");
end

targetbar.UpdateFonts = function(settings)
    percentText:SetFontHeight(settings.percent_font_settings.font_height);
	nameText:SetFontHeight(settings.name_font_settings.font_height);
	distText:SetFontHeight(settings.distance_font_settings.font_height);
	totNameText:SetFontHeight(settings.totName_font_settings.font_height);
end

targetbar.SetHidden = function(hidden)
	if (hidden == true) then
		UpdateTextVisibility(false);
	end
end



return targetbar;