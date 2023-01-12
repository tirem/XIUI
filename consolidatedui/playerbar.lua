require('common');
local imgui = require('imgui');
local fonts = require('fonts');

local interpolatedHP = 0;
local lastHP = 0;
local lastHitTime = os.clock();

local hpText;
local mpText;
local tpText;
local resetPosNextFrame = false;

local playerbar = {};

local function UpdateTextVisibility(visible)
	hpText:SetVisible(visible);
	mpText:SetVisible(visible);
	tpText:SetVisible(visible);
end

local function UpdateHealthValue(settings)
	local party     = AshitaCore:GetMemoryManager():GetParty();
    local player    = AshitaCore:GetMemoryManager():GetPlayer();
	
	if (party == nil or player == nil) then
		return;
	end
	
	local SelfHP = party:GetMemberHP(0);
	local SelfHPMax = player:GetHPMax();
	
	if (SelfHP > lastHP) then
		-- if our HP went up just show it immediately
		targetHP = SelfHP;
		lastHP = SelfHP;
	elseif (SelfHP < lastHP) then
		-- if our HP went down make it a new interpolation target
		interpolatedHP = lastHP;
		lastHP = SelfHP;
		lastHitTime = os.clock();
	end
	
	if (interpolatedHP > SelfHP and os.clock() > lastHitTime + settings.hitDelayLength) then
		interpolatedHP = interpolatedHP - (settings.hitAnimSpeed * (SelfHPMax / 100));
	end
end

playerbar.DrawWindow = function(settings, userSettings)
    -- Obtain the player entity..
    local party = AshitaCore:GetMemoryManager():GetParty();
    local player = AshitaCore:GetMemoryManager():GetPlayer();
	
	if (party == nil or player == nil) then
		UpdateTextVisibility(false);
		return;
	end
	local currJob = player:GetMainJob();
    if (player.isZoning or currJob == 0) then
		UpdateTextVisibility(false);	
        return;
	end

	UpdateHealthValue(settings);

	-- Draw the player window
	if (resetPosNextFrame) then
		imgui.SetNextWindowPos({0,0});
		resetPosNextFrame = false;
	end
	
    imgui.SetNextWindowSize({ settings.barWidth + settings.barSpacing * 2, -1, }, ImGuiCond_Always);
		
    if (imgui.Begin('PlayerBar', true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground))) then

		local SelfHP = party:GetMemberHP(0);
		local SelfHPMax = player:GetHPMax();
		local SelfHPPercent = math.clamp(SelfHP / SelfHPMax, 0, 1);
		local interpHP = math.clamp(interpolatedHP / SelfHPMax, 0, 1);
		local SelfMP = party:GetMemberMP(0);
		local SelfMPMax = player:GetMPMax();
		local SelfMPPercent = math.clamp(SelfMP / SelfMPMax, 0, 1);
		local SelfTP = party:GetMemberTP(0);

		local hpNameColor;
		local hpBarColor;
		if (SelfHPPercent < .25) then 
			hpNameColor = 0xFFFF0000;
			hpBarColor = { 1, 0, 0, 1};
		elseif (SelfHPPercent < .50) then;
			hpNameColor = 0xFFFFA500;
			hpBarColor = { 1, 0.65, 0, 1};
		elseif (SelfHPPercent < .75) then
			hpNameColor = 0xFFFFFF00;
			hpBarColor = { 1, 1, 0, 1};
		else
			hpNameColor = 0xFFFFFFFF;
			hpBarColor = { 1, 0.5, 0.5, 1};
		end

		-- Draw HP Bar (two bars to fake animation
		local hpX = imgui.GetCursorPosX();
		local barSize = (settings.barWidth / 3) - settings.barSpacing;
		imgui.PushStyleColor(ImGuiCol_PlotHistogram, {1,0,0,1});
		imgui.ProgressBar(interpHP, { barSize, settings.barHeight }, '');
		imgui.PopStyleColor(1);
		imgui.SameLine();
		local hpEndX = imgui.GetCursorPosX();
		local hpLocX, hpLocY = imgui.GetCursorScreenPos();	
		if (SelfHPPercent > 0) then
			imgui.SetCursorPosX(hpX);
			imgui.PushStyleColor(ImGuiCol_PlotHistogram, hpBarColor);
			imgui.ProgressBar(1, { barSize * SelfHPPercent, settings.barHeight }, '');
			imgui.PopStyleColor(1);
			imgui.SameLine();
		end
		
		-- Draw MP Bar
		imgui.SetCursorPosX(hpEndX + settings.barSpacing);
		imgui.PushStyleColor(ImGuiCol_PlotHistogram, { 0.9, 1.0, 0.5, 1.0});
		imgui.ProgressBar(SelfMPPercent, { barSize, settings.barHeight }, '');
		imgui.PopStyleColor(1);
		imgui.SameLine();
		local mpLocX, mpLocY  = imgui.GetCursorScreenPos()
		
		-- Draw TP Bars
		local tpX = imgui.GetCursorPosX();
		imgui.SetCursorPosX(imgui.GetCursorPosX() + settings.barSpacing);
		if (SelfTP > 1000) then
			imgui.PushStyleColor(ImGuiCol_PlotHistogram, { 0.2, 0.4, 1.0, 1.0});
		else
			imgui.PushStyleColor(ImGuiCol_PlotHistogram, { 0.3, 0.7, 1.0, 1.0});
		end
		imgui.ProgressBar(SelfTP / 1000, { barSize, settings.barHeight }, '');
		imgui.PopStyleColor(1);
		if (SelfTP > 1000) then
			imgui.SameLine();
			imgui.SetCursorPosX(tpX + settings.barSpacing);
			imgui.PushStyleColor(ImGuiCol_PlotHistogram, { 0.3, 0.7, 1.0, 1.0});
			imgui.ProgressBar((SelfTP - 1000) / 2000, { barSize, settings.barHeight * 3/5 }, '');
			imgui.PopStyleColor(1);
		end
		imgui.SameLine();
		local tpLocX, tpLocY  = imgui.GetCursorScreenPos();
		
		-- Update our HP Text
		hpText:SetPositionX(hpLocX - settings.barSpacing);
		hpText:SetPositionY(hpLocY + settings.barHeight + settings.textYOffset);
		hpText:SetText(tostring(SelfHP));
		hpText:SetColor(hpNameColor);
		
		-- Update our MP Text
		mpText:SetPositionX(mpLocX - settings.barSpacing);
		mpText:SetPositionY(mpLocY + settings.barHeight + settings.textYOffset);
		mpText:SetText(tostring(SelfMP));
		if (SelfMPPercent >= 1) then 
			mpText:SetColor(0xFFCFFBCF);
		else
			mpText:SetColor(0xFFFFFFFF);
	    end
		
		-- Update our TP Text
		tpText:SetPositionX(tpLocX - settings.barSpacing);
		tpText:SetPositionY(tpLocY + settings.barHeight + settings.textYOffset);
		tpText:SetText(tostring(SelfTP));
		if (SelfTP > 1000) then 
			tpText:SetColor(0xFF5b97cf);
		else
			tpText:SetColor(0xFFD1EDF2);
	    end	

		UpdateTextVisibility(true);	
	
    end
	imgui.End();
end


playerbar.Initialize = function(settings)
    hpText = fonts.new(settings.font_settings);
	mpText = fonts.new(settings.font_settings);
	tpText = fonts.new(settings.font_settings);
end

playerbar.UpdateFonts = function(settings)
    hpText:SetFontHeight(settings.font_settings.font_height);
	mpText:SetFontHeight(settings.font_settings.font_height);
	tpText:SetFontHeight(settings.font_settings.font_height);
end

playerbar.SetHidden = function(hidden)
	if (hidden == true) then
		UpdateTextVisibility(false);
	end
end

return playerbar;