require('common');
local imgui = require('imgui');
local fonts = require('fonts');
local progressbar = require('progressbar');

local jobText;
local expText;
local percentText;

local expbar = {
    limitPoints = {},
    meritPoints = {},
    capacityPoints = {},
    jobPoints = {},
};

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
    local player = AshitaCore:GetMemoryManager():GetPlayer();

	if (player == nil) then
		UpdateTextVisibility(false);
		return;
	end

	local mainJob = player:GetMainJob();

    if (player.isZoning or mainJob == 0) then
		UpdateTextVisibility(false);
        return;
	end

    local jobLevel = player:GetMainJobLevel();
    local subJob = player:GetSubJob();
    local subJobLevel = player:GetSubJobLevel();
    local expPoints = { player:GetExpCurrent(), player:GetExpNeeded() };
    local expPointsProgress = expPoints[1] / expPoints[2];

    local limitPoints = expbar.limitPoints;
    local limitPointsProgress = limitPoints[1] / limitPoints[2];
    local meritPoints = expbar.meritPoints;

    -- expbar.capacityPoints[1] = player:GetCapacityPoints(mainJob);
    -- expbar.jobPoints[1] = player:GetJobPoints(mainJob);
    local capPoints = expbar.capacityPoints;
    local capPointsProgress = expbar.capacityPoints[1] / expbar.capacityPoints[2];
    local jobPoints = expbar.jobPoints;

    local meritMode = gConfig.expBarLimitPointsMode and (expPoints[1] == 55999 or ((player:GetIsLimitModeEnabled() or player:GetIsExperiencePointsLocked()) and jobLevel >= 75));
    -- If player is a max level then only enable meritMode in the xp bar if limit mode is specifically enabled
    -- this is so we display capacity points by default
    -- TODO: Tapping on Exp bar switches between merit mode and capacity points
    if jobLevel >= 99 and not player:GetIsLimitModeEnabled() then
        meritMode = false
    end
    local progressBarProgress = 0
    if meritMode then
        progressBarProgress = limitPointsProgress;
    elseif jobLevel >= 99 then
        progressBarProgress = capPointsProgress;
    else
        progressBarProgress = expPointsProgress
    end

    local inlineMode = gConfig.expBarInlineMode;
    local windowSize = inlineMode and settings.barWidth + settings.textWidth or math.max(settings.barWidth, settings.textWidth);

    imgui.SetNextWindowSize({ windowSize, -1 }, ImGuiCond_Always);
	local windowFlags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoBringToFrontOnFocus);
	if (gConfig.lockPositions) then
		windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
	end
    if (imgui.Begin('ExpBar', true, windowFlags)) then

		-- Draw HP Bar
		local startX, startY = imgui.GetCursorScreenPos();
        local col2X = startX + settings.textWidth - imgui.GetStyle().FramePadding.x * 2;

        local progressBarWidth = settings.barWidth - imgui.GetStyle().FramePadding.x * 2;
        if inlineMode then
            imgui.SetCursorScreenPos({col2X, startY});
        end
		progressbar.ProgressBar({{progressBarProgress, {'#c39040', '#e9c466'}}}, {progressBarWidth, settings.barHeight}, {decorate = gConfig.showExpBarBookends});

		imgui.SameLine();

        local textY = inlineMode and startY or startY + settings.barHeight + settings.textOffsetY;
        local textXRightAlign = startX + settings.textWidth - imgui.GetStyle().FramePadding.x * 4;

		-- Update our text objects

        if gConfig.expBarShowText then
            -- Job Text
            local mainJobString = AshitaCore:GetResourceManager():GetString('jobs.names_abbr', mainJob);
            local subJobString = AshitaCore:GetResourceManager():GetString('jobs.names_abbr', subJob);
            local jobString = mainJobString .. ' ' .. jobLevel .. ' / ' .. subJobString .. ' ' .. subJobLevel;
            jobText:SetText(jobString);
            local textW, textH = jobText:get_text_size();
            jobText:SetPositionX(startX);
            jobText:SetPositionY(inlineMode and textY + (settings.barHeight - textH) / 2 - 1 or textY); -- - jobText:GetFontHeight() / 2.5);

            -- Exp Text
            if meritMode then
                if jobLevel >= 99 then
                    local expString = 'JP (' .. jobPoints[1] .. ' / ' .. jobPoints[2] .. ')' .. ' MP (' .. meritPoints[1] .. ' / ' .. meritPoints[2] .. ')' .. ' LP (' .. limitPoints[1] .. ' / ' .. limitPoints[2] .. ')';
                    expText:SetText(expString);
                else
                    local expString = 'MP (' .. meritPoints[1] .. ' / ' .. meritPoints[2] .. ')' .. ' LP (' .. limitPoints[1] .. ' / ' .. limitPoints[2] .. ')';
                    expText:SetText(expString);
                end
            elseif jobLevel >= 99 then
                local expString = 'JP (' .. jobPoints[1] .. ' / ' .. jobPoints[2] .. ')' .. ' MP (' .. meritPoints[1] .. ' / ' .. meritPoints[2] .. ')' .. ' CP (' .. capPoints[1] .. ' / ' .. capPoints[2] .. ')';
                expText:SetText(expString);
            else
                local expString = 'EXP (' .. expPoints[1] .. ' / ' .. expPoints[2] .. ')';
                expText:SetText(expString);
            end
            local textW, textH = expText:get_text_size();
            expText:SetPositionX(textXRightAlign);
            expText:SetPositionY(inlineMode and textY + (settings.barHeight - textH) / 2 - 1 or textY); -- - expText:GetFontHeight() / 2.5);

            jobText:SetVisible(true);
            expText:SetVisible(true);
        else
            jobText:SetText('');
            jobText:SetVisible(false);
            expText:SetText('');
            expText:SetVisible(false);
        end

        -- Percent Text
        if gConfig.expBarShowPercent then
            local expPercentString = ('%.f'):fmt(progressBarProgress * 100);
            local percentString = expPercentString .. '%';
            percentText:SetText(percentString); 
            local textW, textH = percentText:get_text_size();
            local percentTextX = inlineMode and startX + windowSize or textXRightAlign;
            local percentTextY = inlineMode and textY + (settings.barHeight - textH) / 2 - 1 or startY - settings.textOffsetY;
            percentText:SetAnchor(inlineMode and 0 or 2);
            percentText:SetPositionX(percentTextX + settings.percentOffsetX);
            percentText:SetPositionY(percentTextY);
            percentText:SetRightJustified(settings.percent_font_settings.right_justified and not inlineMode);

            percentText:SetVisible(true);
        else
            percentText:SetText('');
            percentText:SetVisible(false);
        end

    end
	imgui.End();
end


expbar.Initialize = function(settings)
    jobText = fonts.new(settings.job_font_settings);
	expText = fonts.new(settings.exp_font_settings);
	percentText = fonts.new(settings.percent_font_settings);

    local player = AshitaCore:GetMemoryManager():GetPlayer();
    expbar.limitPoints = { player:GetLimitPoints(), 10000 };
    expbar.meritPoints = { player:GetMeritPoints(), player:GetMeritPointsMax() };
    local currJob = player:GetMainJob();
    expbar.capacityPoints = { player:GetCapacityPoints(currJob), 30000 };
    expbar.jobPoints = { player:GetJobPoints(currJob), 500 };
    -- expbar.mastery = { player:GetMasteryExp(), player:GetMasteryExpNeeded() };
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

expbar.HandlePacket = function(e)
    -- Kill Message
    if e.id == 0x02D then
        local pId = struct.unpack('I', e.data_modified, 0x04 + 1);
        if pId == GetPlayerEntity().ServerId then
            local val = struct.unpack('I', e.data_modified, 0x10 + 1);
            -- local val2 = struct.unpack('I', e.data_modified, 0x14 + 1);
            local msgId = struct.unpack('H', e.data_modified, 0x18 + 1) % 1024;

            if msgId == 371 or msgId == 372 then
                expbar.limitPoints[1] = expbar.limitPoints[1] + val;
                if (expbar.limitPoints[1] > expbar.limitPoints[2]) then
                    expbar.limitPoints[1] = expbar.limitPoints[1] - expbar.limitPoints[2];
                end
                -- print('Limit points A: ' .. expbar.limitPoints[1] .. ' / ' .. expbar.limitPoints[2] .. ' #' .. msgId);
            elseif msgId == 718 or msgId == 735 then
                expbar.capacityPoints[1] = expbar.capacityPoints[1] + val;
                if (expbar.capacityPoints[1] > expbar.capacityPoints[2]) then
                    expbar.capacityPoints[1] = expbar.capacityPoints[1] - expbar.capacityPoints[2];
                end
            elseif msgId == 50 or msgId == 368 then
                expbar.meritPoints[1] = val;
                -- print('Merit points: ' .. expbar.meritPoints[1] .. ' / ' .. expbar.meritPoints[2] .. ' #' .. msgId);
            elseif msgId == 719 then
                expbar.jobPoints[1] = val;
            end
        end
    elseif e.id == 0x063 then
        if e.data_modified:byte(5) == 2 then
            expbar.limitPoints[1] = struct.unpack('H', e.data_modified, 0x08 + 1);
            expbar.meritPoints[1] = e.data_modified:byte(0x0A + 1) % 128;
            expbar.meritPoints[2] = e.data_modified:byte(0x0C + 1) % 128;
            -- print('Limit points B: ' .. expbar.limitPoints[1] .. ' / ' .. expbar.limitPoints[2]);
        elseif e.data_modified:byte(5) == 5 then
            local player = AshitaCore:GetMemoryManager():GetPlayer();
            local jobOffset = player:GetMainJob() * 6 + 13;
            expbar.capacityPoints[1] = struct.unpack('H', e.data_modified, jobOffset);
            expbar.jobPoints[1] = struct.unpack('H', e.data_modified, jobOffset + 2);
        end
    end
end

return expbar;