require('common');
require('helpers');
local imgui = require('imgui');
local fonts = require('fonts');
local progressbar = require('progressbar');
local buffTable = require('bufftable');

local hpText;
local mpText;
local tpText;
local resetPosNextFrame = false;

local playerbar = {};

local _HXUI_DEV_DEBUG_INTERPOLATION = false;
local _HXUI_DEV_DEBUG_INTERPOLATION_DELAY, _HXUI_DEV_DEBUG_INTERPOLATION_NEXT_TIME;

if _HXUI_DEV_DEBUG_INTERPOLATION then
	_HXUI_DEV_DEBUG_INTERPOLATION_DELAY = 2;
	_HXUI_DEV_DEBUG_INTERPOLATION_NEXT_TIME = os.time() + _HXUI_DEV_DEBUG_INTERPOLATION_DELAY;
end

local function UpdateTextVisibility(visible)
	hpText:SetVisible(visible);
	mpText:SetVisible(visible);
	tpText:SetVisible(visible);
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
	
	if (party == nil or player == nil) then
		return;
	end

	local SelfHP = party:GetMemberHP(0);
	local SelfHPMax = player:GetHPMax();
	local SelfHPPercent = math.clamp(party:GetMemberHPPercent(0), 0, 100);
	local SelfMP = party:GetMemberMP(0);
	local SelfMPMax = player:GetMPMax();
	local SelfMPPercent = math.clamp(party:GetMemberMPPercent(0), 0, 100);
	local SelfTP = party:GetMemberTP(0);

	local currentTime = os.clock();

    if playerbar.previousHPP then
    	if SelfHPPercent < playerbar.currentHPP then
    		playerbar.previousHPP = playerbar.currentHPP;
    		playerbar.currentHPP = SelfHPPercent;
    		playerbar.lastHitTime = currentTime;
    	end
    else
    	playerbar.currentHPP = SelfHPPercent;
    	playerbar.previousHPP = SelfHPPercent;
    end

    if _HXUI_DEV_DEBUG_INTERPOLATION then
	    if os.time() > _HXUI_DEV_DEBUG_INTERPOLATION_NEXT_TIME then
	    	playerbar.previousHPP = 75;
	    	playerbar.currentHPP = 50;
			playerbar.lastHitTime = currentTime;

			_HXUI_DEV_DEBUG_INTERPOLATION_NEXT_TIME = os.time() + 2;
	    end
	end

    local interpolationPercent;
    local interpolationOverlayAlpha = 0;

    if playerbar.currentHPP < playerbar.previousHPP then
    	local hppDelta = playerbar.previousHPP - playerbar.currentHPP;

    	if currentTime > playerbar.lastHitTime + settings.hitDelayLength then
    		-- local interpolationTimeTotal = settings.hitInterpolationMaxTime * (hppDelta / 100);
    		local interpolationTimeTotal = settings.hitInterpolationMaxTime;
    		local interpolationTimeElapsed = currentTime - playerbar.lastHitTime - settings.hitDelayLength;

    		if interpolationTimeElapsed <= interpolationTimeTotal then
    			local interpolationTimeElapsedPercent = easeOutPercent(interpolationTimeElapsed / interpolationTimeTotal);

    			interpolationPercent = hppDelta * (1 - interpolationTimeElapsedPercent);
    		end
    	elseif currentTime - playerbar.lastHitTime <= settings.hitDelayLength then
    		interpolationPercent = hppDelta;

    		local hitDelayTime = currentTime - playerbar.lastHitTime;
    		local hitDelayHalfDuration = settings.hitDelayLength / 2;

    		if hitDelayTime > hitDelayHalfDuration then
    			interpolationOverlayAlpha = 1 - ((hitDelayTime - hitDelayHalfDuration) / hitDelayHalfDuration);
    		else
    			interpolationOverlayAlpha = hitDelayTime / hitDelayHalfDuration;
    		end
    	end
    end

	-- Draw the player window
	if (resetPosNextFrame) then
		imgui.SetNextWindowPos({0,0});
		resetPosNextFrame = false;
	end
	
    imgui.SetNextWindowSize({ settings.barWidth + settings.barSpacing * 2, -1, }, ImGuiCond_Always);
		
    if (imgui.Begin('PlayerBar', true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground))) then

		local hpNameColor, hpGradient = GetHpColors(SelfHPPercent);

		local SelfJob = GetJobStr(party:GetMemberMainJob(0));
		local SelfSubJob = GetJobStr(party:GetMemberSubJob(0));
		local bShowMp = buffTable.IsSpellcaster(SelfJob) or buffTable.IsSpellcaster(SelfSubJob) or gConfig.alwaysShowMpBar;

		-- Draw HP Bar (two bars to fake animation
		local hpX = imgui.GetCursorPosX();
		local barSize = (settings.barWidth / 3) - settings.barSpacing;

		local hpPercentData = {{SelfHPPercent / 100, hpGradient}};

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

			imgui.SameLine();
		end

		local mpLocX
		local mpLocY;
		
		if (bShowMp) then
			-- Draw MP Bar
			imgui.SetCursorPosX(hpEndX + settings.barSpacing);
			progressbar.ProgressBar({{SelfMPPercent / 100, {'#9abb5a', '#bfe07d'}}}, {barSize, settings.barHeight});
			imgui.SameLine();
			mpLocX, mpLocY  = imgui.GetCursorScreenPos()
		end
		
		-- Draw TP Bars
		local tpX = imgui.GetCursorPosX();
		imgui.SetCursorPosX(imgui.GetCursorPosX() + settings.barSpacing);
		
		local tpGradient = {'#3898ce', '#78c4ee'};
		local mainPercent;
		local tpOverlay;
		
		if (SelfTP >= 1000) then
			mainPercent = (SelfTP - 1000) / 2000;

			local tpOverlayGradient = {'#0078CC', '#0078CC'};

			tpOverlay = {
				{
					1, -- overlay percent
					tpOverlayGradient -- overlay gradient
				},
				math.ceil(settings.barHeight * 2/7), -- overlay height
				1, -- overlay vertical padding
				{
					'#2fa9ff', -- overlay pulse color
					1 -- overlay pulse seconds
				}
			};
		else
			mainPercent = SelfTP / 1000;
		end
		
		progressbar.ProgressBar({{mainPercent, tpGradient}}, {barSize, settings.barHeight}, true, tpOverlay);
		
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
			mpText:SetColor(gAdjustedSettings.mpColor);
		end

		mpText:SetVisible(bShowMp);
			
		-- Update our TP Text
		tpText:SetPositionX(tpLocX - settings.barSpacing - settings.barHeight / 2);
		tpText:SetPositionY(tpLocY + settings.barHeight + settings.textYOffset);
		tpText:SetText(tostring(SelfTP));

		if (SelfTP >= 1000) then 
			tpText:SetColor(gAdjustedSettings.tpFullColor);
		else
			tpText:SetColor(gAdjustedSettings.tpEmptyColor);
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