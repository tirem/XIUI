require('common');
require('helpers');
local imgui = require('imgui');

-- TODO: Calculate these instead of manually setting them
local cornerOffset = 5;
local nameXOffset = 12;
local nameYOffset = 26;

local bgAlpha = 0.4;
local bgRadius = 6;

local targetbar = {};

targetbar.DrawWindow = function(settings, userSettings)
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
		targetIndex = playerTarget:GetTargetIndex(0);
		targetEntity = GetEntity(targetIndex);
	end
    if (targetEntity == nil or targetEntity.Name == nil) then
        return;
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
			targetNameText = targetNameText.." ["..targetIndex.."]";
		end
		local y, _  = imgui.CalcTextSize(targetNameText);

		local winX, winY = imgui.GetWindowPos();
		draw_rect({winX + cornerOffset , winY + cornerOffset}, {winX + y + nameXOffset, winY + nameYOffset}, {0,0,0,bgAlpha}, bgRadius, true);

        -- Display the targets information..
        imgui.TextColored(color, targetNameText);
        imgui.SameLine();
        imgui.SetCursorPosX(imgui.GetCursorPosX() + imgui.GetColumnWidth() - x - imgui.GetStyle().FramePadding.x);
        imgui.Text(dist);

		if (settings.showBarPercent == true) then
			imgui.ProgressBar(targetEntity.HPPercent / 100, { -1, settings.barHeight});
		else
			imgui.ProgressBar(targetEntity.HPPercent / 100, { -1, settings.barHeight}, '');
		end
		
    end
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
	
	if (imgui.Begin('TargetOfTargetBar', true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground))) then
        -- Obtain and prepare target information.
		imgui.SetWindowFontScale(settings.textScale);
		
		local w, _  = imgui.CalcTextSize(targetNameText);

		local totwinX, totwinY = imgui.GetWindowPos();
		draw_rect({totwinX + cornerOffset, totwinY + cornerOffset}, {totwinX + w + nameXOffset, totwinY + nameYOffset}, {0,0,0,bgAlpha}, bgRadius, true);

		-- Display the targets information..
		imgui.TextColored(totColor, targetNameText);
		imgui.ProgressBar(totEntity.HPPercent / 100, { -1, settings.totBarHeight }, '');
    end
    imgui.End();
end

return targetbar;