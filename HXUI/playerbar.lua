require('common');
local imgui = require('imgui');
local fonts = require('fonts');
local progressbar = require('progressbar');
local buffTable = require('bufftable');

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

playerbar.DrawWindow = function(settings)
    -- Obtain the player entity..
    local party = AshitaCore:GetMemoryManager():GetParty();
    local player = AshitaCore:GetMemoryManager():GetPlayer();
	local playerEnt = GetPlayerEntity();
	
	if (party == nil or player == nil or playerEnt == nil) then
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
		local SelfHPPercent = math.clamp(party:GetMemberHPPercent(0) / 100, 0, 1);
		local interpHP = math.clamp(interpolatedHP / (SelfHP / SelfHPPercent), 0, 1);
		local SelfMP = party:GetMemberMP(0);
		local SelfMPMax = player:GetMPMax();
		local SelfMPPercent = math.clamp(party:GetMemberMPPercent(0) / 100, 0, 1);
		local SelfTP = party:GetMemberTP(0);

		local hpNameColor;
		local hpGradient;

		local SelfJob = GetJobStr(party:GetMemberMainJob(0));
		local SelfSubJob = GetJobStr(party:GetMemberSubJob(0));
		local bShowMp = buffTable.IsSpellcaster(SelfJob) or buffTable.IsSpellcaster(SelfSubJob) or gConfig.alwaysShowMpBar;

		if (SelfHPPercent == 0) then
			hpNameColor = 0xFFfdf4f4;
			hpGradient = {"#fdf4f4", "#fdf4f4"};
		elseif (SelfHPPercent < .25) then 
			hpNameColor = 0xFFFF0000;
			hpGradient = {"#ec3232", "#f16161"};
		elseif (SelfHPPercent < .50) then;
			hpNameColor = 0xFFFFA500;
			hpGradient = {"#ee9c06", "#ecb44e"};
		elseif (SelfHPPercent < .75) then
			hpNameColor = 0xFFFFFF00;
			hpGradient = {"#ffff0c", "#ffff97"};
		else
			hpNameColor = 0xFFFEBCBC;
			hpGradient = {"#eb7373", "#fa9c9c"};
		end

		-- Draw HP Bar (two bars to fake animation
		local hpX = imgui.GetCursorPosX();
		local barSize = (settings.barWidth / 3) - settings.barSpacing;
		-- imgui.PushStyleColor(ImGuiCol_PlotHistogram, {1,0,0,1});
		-- imgui.ProgressBar(interpHP, { barSize, settings.barHeight }, '');
		-- imgui.PopStyleColor(1);

		local hpPercentData = {{SelfHPPercent, hpGradient}};

		if interpHP > 0 then
			table.insert(hpPercentData, {interpHP - SelfHPPercent, {'#cf3437', '#c54d4d'}});
		end

		if (bShowMp == false) then
			imgui.Dummy({(barSize + settings.barSpacing) / 2, 0});
			imgui.SameLine();
		end
		
		progressbar.ProgressBar(hpPercentData, {barSize, settings.barHeight});
		
		imgui.SameLine();
		local hpEndX = imgui.GetCursorPosX();
		local hpLocX, hpLocY = imgui.GetCursorScreenPos();	
		if (SelfHPPercent > 0) then
			imgui.SetCursorPosX(hpX);
			-- imgui.PushStyleColor(ImGuiCol_PlotHistogram, hpBarColor);
			-- imgui.ProgressBar(1, { barSize * SelfHPPercent, settings.barHeight }, '');
			-- imgui.PopStyleColor(1);
			imgui.SameLine();
		end

		local mpLocX
		local mpLocY;
		
		if (bShowMp) then
			-- Draw MP Bar
			imgui.SetCursorPosX(hpEndX + settings.barSpacing);
			-- imgui.PushStyleColor(ImGuiCol_PlotHistogram, { 0.9, 1.0, 0.5, 1.0});
			-- imgui.ProgressBar(SelfMPPercent, { barSize, settings.barHeight }, '');
			progressbar.ProgressBar({{SelfMPPercent, {'#9abb5a', '#bfe07d'}}}, {barSize, settings.barHeight});
			-- imgui.PopStyleColor(1);
			imgui.SameLine();
			mpLocX, mpLocY  = imgui.GetCursorScreenPos()
		end
		
		-- Draw TP Bars
		local tpX = imgui.GetCursorPosX();
		imgui.SetCursorPosX(imgui.GetCursorPosX() + settings.barSpacing);
		
		local tpGradient = {'#3898ce', '#78c4ee'};
		local tpOverlayGradient = {'#0078CC', '#0078CC'};
		local mainPercent;
		local tpOverlay;
		
		if (SelfTP >= 1000) then
			-- imgui.PushStyleColor(ImGuiCol_PlotHistogram, { 0.2, 0.4, 1.0, 1.0});
			-- tpGradient = {'#3898ce', '#78c4ee'};
			mainPercent = (SelfTP - 1000) / 2000;
			tpOverlay = {{1, tpOverlayGradient}, math.ceil(settings.barHeight * 2/7), 1};
		else
			mainPercent = SelfTP / 1000;
			-- imgui.PushStyleColor(ImGuiCol_PlotHistogram, { 0.3, 0.7, 1.0, 1.0});
			-- tpGradient = {'#4db2ff', '#4db2ff'};
		end
		
		-- imgui.ProgressBar(SelfTP / 1000, { barSize, settings.barHeight }, '');
		-- imgui.PopStyleColor(1);
		progressbar.ProgressBar({{mainPercent, tpGradient}}, {barSize, settings.barHeight}, true, tpOverlay);
		
		--[[
		if (SelfTP >= 1000) then
			imgui.SameLine();
			imgui.SetCursorPosX(tpX + settings.barSpacing);
			imgui.PushStyleColor(ImGuiCol_PlotHistogram, { 0.3, 0.7, 1.0, 1.0});
			imgui.ProgressBar((SelfTP - 1000) / 2000, { barSize, settings.barHeight * 3/5 }, '');
			imgui.PopStyleColor(1);
		end
		]]--
		imgui.SameLine();
		local tpLocX, tpLocY  = imgui.GetCursorScreenPos();
		
		-- Update our HP Text
		hpText:SetPositionX(hpLocX - settings.barSpacing - settings.barHeight / 2);
		hpText:SetPositionY(hpLocY + settings.barHeight + settings.textYOffset);
		hpText:SetText(tostring(SelfHP));
		hpText:SetColor(hpNameColor);
		
		hpText:SetVisible(true);

		if (bShowMp) then
			-- Update our MP Text
			mpText:SetPositionX(mpLocX - settings.barSpacing - settings.barHeight / 2);
			mpText:SetPositionY(mpLocY + settings.barHeight + settings.textYOffset);
			mpText:SetText(tostring(SelfMP));

			if (SelfMPPercent >= 1 or SelfMPMax == 0) then 
				mpText:SetColor(0xFFCBDFA1);
			else
				mpText:SetColor(0xFFE8F1D7);
		    end
		end
		mpText:SetVisible(bShowMp);
			
		-- Update our TP Text
		tpText:SetPositionX(tpLocX - settings.barSpacing - settings.barHeight / 2);
		tpText:SetPositionY(tpLocY + settings.barHeight + settings.textYOffset);
		tpText:SetText(tostring(SelfTP));

--		tpText:SetColor(0xFF54abdb);
		if (SelfTP >= 1000) then 
			tpText:SetColor(0xFF0096ff);
		else
			tpText:SetColor(0xFF8FC7E6);
	    end
		tpText:SetVisible(true);


	
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