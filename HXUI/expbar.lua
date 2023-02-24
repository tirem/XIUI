require('common');
local imgui = require('imgui');
local fonts = require('fonts');
local progressbar = require('progressbar');

local jobText;
local expText;
local percentText;

local expbar = {};

local function UpdateTextVisibility(visible)
	jobText:SetVisible(visible);
	expText:SetVisible(visible);
	percentText:SetVisible(visible);
end

--[[
* event: d3d_present
* desc : Event called when the Direct3D device is presenting a scene.
--]]
expbar.DrawWindow = function(settings)
    -- Obtain the player entity..
    local player    = AshitaCore:GetMemoryManager():GetPlayer();

	if (player == nil) then
		UpdateTextVisibility(false);
		return;
	end

	local mainJob = player:GetMainJob();
	local jobLevel = player:GetMainJobLevel();
	local subJob = player:GetSubJob();
	local subJobLevel = player:GetSubJobLevel();
	local currentExp = player:GetExpCurrent();
	local totalExp = player:GetExpNeeded();

    if (player.isZoning or mainJob == 0) then
		UpdateTextVisibility(false);	
        return;
	end
	
    imgui.SetNextWindowSize({ settings.barWidth, -1, }, ImGuiCond_Always);
	local windowFlags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoBringToFrontOnFocus);
	if (gConfig.lockPositions) then
		windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
	end
    if (imgui.Begin('ExpBar', true, windowFlags)) then

		-- Draw HP Bar (two bars to fake animation
		local expPercent = currentExp / totalExp;
		local startX, startY = imgui.GetCursorScreenPos();
		-- imgui.PushStyleColor(ImGuiCol_PlotHistogram, {1, 1, .5, 1});
		-- imgui.ProgressBar(expPercent, { -1, settings.barHeight }, '');
		-- imgui.PopStyleColor(1);

		progressbar.ProgressBar({{expPercent, {'#c39040', '#e9c466'}}}, {-1, settings.barHeight}, {decorate = gConfig.showExpBarBookends});

		imgui.SameLine();
		
		-- Update our text objects
		local mainJobString = AshitaCore:GetResourceManager():GetString("jobs.names_abbr", mainJob);
		local SubJobString = AshitaCore:GetResourceManager():GetString("jobs.names_abbr", subJob);
		local jobString = mainJobString..' '..jobLevel..' / '..SubJobString..' '..subJobLevel;
		jobText:SetPositionX(startX);
		jobText:SetPositionY(startY + settings.barHeight + settings.jobOffsetY);
		jobText:SetText(jobString);	

		local expString = 'EXP ('..currentExp..' / '..totalExp..')';
		expText:SetPositionX(startX + settings.barWidth - imgui.GetStyle().FramePadding.x * 4);
		expText:SetPositionY(startY + settings.barHeight + settings.expOffsetY);
		expText:SetText(expString);	

		local expPercentString = ('%.f'):fmt(expPercent * 100);
		local percentString = 'EXP - '..expPercentString..'%';
		percentText:SetPositionX(startX + settings.barWidth - imgui.GetStyle().FramePadding.x * 4 + settings.percentOffsetX);
		percentText:SetPositionY(startY - (percentText:GetFontHeight()*2) + settings.percentOffsetY);
		percentText:SetText(percentString);	

		UpdateTextVisibility(true);	
	
    end
	imgui.End();
end


expbar.Initialize = function(settings)
    jobText = fonts.new(settings.job_font_settings);
	expText = fonts.new(settings.exp_font_settings);
	percentText = fonts.new(settings.percent_font_settings);
end

expbar.UpdateFonts = function(settings)
    jobText:SetFontHeight(settings.job_font_settings.font_height);
	expText:SetFontHeight(settings.exp_font_settings.font_height);
	percentText:SetFontHeight(settings.percent_font_settings.font_height);
end

expbar.SetHidden = function(hidden)
	if (hidden == true) then
		UpdateTextVisibility(false);
	end
end

return expbar;