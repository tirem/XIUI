require('common');
require('helpers');
local imgui = require('imgui');
local statusHandler = require('statushandler');
local debuffHandler = require('debuffhandler');
local progressbar = require('progressbar');

-- TODO: Calculate these instead of manually setting them

local bgAlpha = 0.4;
local bgRadius = 3;

local targetbar = {};

targetbar.DrawWindow = function(settings)
    -- Obtain the player entity..
    local playerEnt = GetPlayerEntity();
	local player = AshitaCore:GetMemoryManager():GetPlayer();
    if (playerEnt == nil or player == nil) then
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

    local interpolationPercent;

    if targetbar.currentHPP < targetbar.previousHPP then
    	local hppDelta = targetbar.previousHPP - targetbar.currentHPP;

    	if currentTime > targetbar.lastHitTime + settings.hitDelayLength then
    		local interpolationTimeTotal = settings.hitInterpolationMaxTime * (hppDelta / 100);
    		local interpolationTimeElapsed = currentTime - targetbar.lastHitTime - settings.hitDelayLength;

    		if interpolationTimeElapsed <= interpolationTimeTotal then
    			local interpolationTimeElapsedPercent = interpolationTimeElapsed / interpolationTimeTotal;

    			interpolationPercent = hppDelta * (1 - interpolationTimeElapsedPercent);
    		end
    	elseif currentTime - targetbar.lastHitTime <= settings.hitDelayLength then
    		interpolationPercent = hppDelta;
    	end
    end

	local color = GetColorOfTarget(targetEntity, targetIndex);
	local showTargetId = GetIsMob(targetEntity);

    imgui.SetNextWindowSize({ settings.barWidth, -1, }, ImGuiCond_Always);
	
	-- Draw the main target window
    if (imgui.Begin('TargetBar', true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground))) then
		imgui.SetWindowFontScale(settings.textScale);
        -- Obtain and prepare target information..
        local dist  = ('%.1f'):fmt(math.sqrt(targetEntity.Distance));
        local x, _  = imgui.CalcTextSize(dist);
		local targetNameText = targetEntity.Name;
		if (showTargetId) then
			local targetServerId = AshitaCore:GetMemoryManager():GetEntity():GetServerId(targetIndex);
			local targetServerIdHex = string.format('0x%X', targetServerId);

			targetNameText = targetNameText .. " [ID: ".. string.sub(targetServerIdHex, -3) .."]";
		end
		local nameX, nameY = imgui.CalcTextSize(targetNameText);

		local winX, winY = imgui.GetWindowPos();
		draw_rect({winX + settings.cornerOffset , winY + settings.cornerOffset}, {winX + nameX + settings.nameXOffset, winY + nameY + settings.nameYOffset}, {0,0,0,bgAlpha}, bgRadius, true);

        -- Display the targets information..
        imgui.TextColored(color, targetNameText);
        imgui.SameLine();
        imgui.SetCursorPosX(imgui.GetCursorPosX() + imgui.GetColumnWidth() - x - imgui.GetStyle().FramePadding.x);
        imgui.Text(dist);

        --[[
		if (userSettings.showTargetBarPercent == true) then
			imgui.ProgressBar(targetEntity.HPPercent / 100, { -1, settings.barHeight});
		else
			imgui.ProgressBar(targetEntity.HPPercent / 100, { -1, settings.barHeight}, '');
		end
		]]--

		local hpGradientStart = '#e16c6c';
		local hpGradientEnd = '#fb9494';

		local hpPercentData = {{targetEntity.HPPercent / 100, {hpGradientStart, hpGradientEnd}}};

		if interpolationPercent then
			table.insert(hpPercentData, {interpolationPercent / 100, {'#cf3437', '#c54d4d'}});
		end
		
		progressbar.ProgressBar(hpPercentData, {-1, settings.barHeight});
    end

	-- Draw buffs and debuffs
	local buffIds;
	if (targetEntity == playerEnt) then
		buffIds = player:GetBuffs();
	elseif (IsMemberOfParty(targetIndex)) then
		buffIds = statusHandler.get_member_status(playerTarget:GetServerId(0));
	else
		buffIds = debuffHandler.GetActiveDebuffs(playerTarget:GetServerId(0));
	end
	imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {1, 3});
	DrawStatusIcons(buffIds, settings.iconSize, settings.maxIconColumns, 3);
	imgui.PopStyleVar(1);

	-- End our main bar
	local winPosX, winPosY = imgui.GetWindowPos();
    imgui.End();
	
	
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
	if (totEntity == nil) then
		return;
	end;
	local targetNameText = totEntity.Name;
	if (targetNameText == nil) then
		return;
	end;
	
	local totColor = GetColorOfTarget(totEntity, totIndex);
	imgui.SetNextWindowPos({winPosX + settings.barWidth, winPosY + settings.totBarOffset});
    imgui.SetNextWindowSize({ settings.barWidth / 3, -1, }, ImGuiCond_Always);
	
	if (imgui.Begin('TargetOfTargetBar', true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoSavedSettings))) then
        -- Obtain and prepare target information.
		imgui.SetWindowFontScale(settings.textScale);
		
		local totNameX, totNameY = imgui.CalcTextSize(targetNameText);

		local totwinX, totwinY = imgui.GetWindowPos();
		draw_rect({totwinX + settings.cornerOffset, totwinY + settings.cornerOffset}, {totwinX + totNameX + settings.nameXOffset, totwinY + totNameY + settings.nameYOffset}, {0,0,0,bgAlpha}, bgRadius, true);

		-- Display the targets information..
		imgui.TextColored(totColor, targetNameText);
		--imgui.ProgressBar(totEntity.HPPercent / 100, { -1, settings.totBarHeight }, '');
		progressbar.ProgressBar({{totEntity.HPPercent / 100, {'#e16c6c', '#fb9494'}}}, {-1, settings.totBarHeight});
    end
    imgui.End();
end


return targetbar;