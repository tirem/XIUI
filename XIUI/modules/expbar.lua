require('common');
require('handlers.helpers');
local imgui = require('imgui');
local gdi = require('submodules.gdifonts.include');
local progressbar = require('libs.progressbar');
local drawing = require('libs.drawing');
local defaultPositions = require('libs.defaultpositions');

local jobText;
local expText;
local percentText;
local allFonts; -- Table for batch visibility operations

-- Thank you @onimitch for the help with tons of the EXPbar module!
-- Cached colors to avoid expensive set_font_color calls every frame
local lastJobTextColor;
local lastExpTextColor;
local lastPercentTextColor;

-- Position save/restore state
local hasAppliedSavedPosition = false;
local forcePositionReset = false;
local lastSavedPosX, lastSavedPosY = nil, nil;

local expbar = {
    limitPoints = {},
    meritPoints = {},
    capacityPoints = {},
    jobPoints = {},
};

-- Helper functions to generate text strings (eliminates duplication)
local function buildJobString(player, jobLevel, masteryEnabled, mlJobLevel)
    local mainJobString = AshitaCore:GetResourceManager():GetString('jobs.names_abbr', player:GetMainJob());
    local subJobString = AshitaCore:GetResourceManager():GetString('jobs.names_abbr', player:GetSubJob());

    local jobLevelString = tostring(jobLevel);
    if masteryEnabled then
        jobLevelString = 'ML' .. mlJobLevel;
    end

    return mainJobString .. ' ' .. jobLevelString .. ' / ' .. subJobString .. ' ' .. player:GetSubJobLevel();
end

local function buildExpString(separator, masteryEnabled, meritMode, jobLevel, jobPoints, meritPoints, limitPoints, capPoints, expPoints, mastery)
    if masteryEnabled then
        return separator .. 'JP (' .. jobPoints[1] .. ' / ' .. jobPoints[2] .. ')' .. '  MP (' .. meritPoints[1] .. ' / ' .. meritPoints[2] .. ')' .. '  EXP (' .. mastery[1] .. ' / ' .. mastery[2] .. ')';
    elseif meritMode then
        if jobLevel >= 99 then
            return separator .. 'JP (' .. jobPoints[1] .. '/' .. jobPoints[2] .. ') MP (' .. meritPoints[1] .. '/' .. meritPoints[2] .. ') LP (' .. limitPoints[1] .. '/' .. limitPoints[2] .. ')';
        else
            return separator .. 'MP (' .. meritPoints[1] .. '/' .. meritPoints[2] .. ') LP (' .. limitPoints[1] .. '/' .. limitPoints[2] .. ')';
        end
    elseif jobLevel >= 99 then
        return separator .. 'JP (' .. jobPoints[1] .. '/' .. jobPoints[2] .. ') MP (' .. meritPoints[1] .. '/' .. meritPoints[2] .. ') CP (' .. capPoints[1] .. '/' .. capPoints[2] .. ')';
    else
        return separator .. 'EXP (' .. expPoints[1] .. '/' .. expPoints[2] .. ')';
    end
end

local function buildPercentString(progressBarProgress, showText)
    local expPercentString = ('%.f'):fmt(progressBarProgress * 100);
    local percentSeparator = showText and ' ' or '';
    return percentSeparator .. expPercentString .. '%';
end

function GetKeyItemFromName(name)
    local findKI = AshitaCore:GetResourceManager():GetString('keyitems.names', name, 2);
    if (findKI ~= nil) then
        return findKI;
    end
    return -1;
end

--[[
* event: d3d_present
* desc : Event called when the Direct3D device is presenting a scene.
--]]
expbar.DrawWindow = function(settings)
    -- Obtain the player entity..
    local player = GetPlayerSafe();

	if (player == nil) then
		SetFontsVisible(allFonts, false);
		return;
	end

	local mainJob = player:GetMainJob();

    if (player.isZoning or mainJob == 0) then
		SetFontsVisible(allFonts, false);
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

    local mastered = player:GetJobPointsSpent(mainJob) == 2100;
    local masteryEnabled = jobLevel >= 99 and mastered and player:HasKeyItem(expbar.mlBreakerItemId);
    local masteryProgress = 0;
    local mlJobLevel = 0;
    if masteryEnabled then
        expbar.mastery = { player:GetMasteryExp(), player:GetMasteryExpNeeded() };
        if expbar.mastery[2] > 0 then
            masteryProgress = expbar.mastery[1] / expbar.mastery[2];
        end
        mlJobLevel = player:GetMasteryJobLevel();
    end

    local meritMode = gConfig.expBarLimitPointsMode and (expPoints[1] == 55999 or ((player:GetIsLimitModeEnabled() or player:GetIsExperiencePointsLocked()) and jobLevel >= 75));
    -- If player is a max level then only enable meritMode in the xp bar if limit mode is specifically enabled
    -- this is so we display capacity points by default
    -- TODO: Tapping on Exp bar switches between merit mode and capacity points
    if jobLevel >= 99 and not player:GetIsLimitModeEnabled() then
        meritMode = false
    end
    local progressBarProgress = 0
    if masteryEnabled then
        progressBarProgress = masteryProgress;
    elseif meritMode then
        progressBarProgress = limitPointsProgress;
    elseif jobLevel >= 99 then
        progressBarProgress = capPointsProgress;
    else
        progressBarProgress = expPointsProgress
    end

    local inlineMode = gConfig.expBarInlineMode;
    local expBarTextMargin = 10;

    -- Build text strings once, reuse for both measuring and rendering
    -- All text (including percent) requires expBarShowText to be enabled
    local expStringSeparator = '';
    local jobString = gConfig.expBarShowText and buildJobString(player, jobLevel, masteryEnabled, mlJobLevel) or nil;
    local expString = gConfig.expBarShowText and buildExpString(expStringSeparator, masteryEnabled, meritMode, jobLevel, jobPoints, meritPoints, limitPoints, capPoints, expPoints, expbar.mastery) or nil;
    local percentString = (gConfig.expBarShowText and gConfig.expBarShowPercent) and buildPercentString(progressBarProgress, true) or nil;

    -- Calculate text width for inline mode positioning
    local actualTextWidth = 0;
    if inlineMode then
        if jobString then
            jobText:set_text(jobString);
            local jobWidth = jobText:get_text_size();
            actualTextWidth = actualTextWidth + jobWidth;
        end

        if expString then
            expText:set_text(expString);
            local expWidth = expText:get_text_size();
            actualTextWidth = actualTextWidth + expWidth + expBarTextMargin;
        end

        if percentString then
            percentText:set_text(percentString);
            local percentWidth = percentText:get_text_size();
            -- Add spacing between exp text and percent text
            actualTextWidth = actualTextWidth + percentWidth + expBarTextMargin;
        end

        -- Add spacing between text and bar (only if there's text to space from)
        if actualTextWidth > 0 then
            actualTextWidth = actualTextWidth + 16;
        end
    end

    -- Let ImGui auto-size the window based on content (Dummy call in progressbar)
    -- Use {0, 0} to allow unlimited auto-sizing (not {-1, -1} which can cause clipping)
    imgui.SetNextWindowSize({ 0, 0 }, ImGuiCond_Always);

    -- Handle position reset or restore
    if forcePositionReset then
        local defX, defY = defaultPositions.GetExpBarPosition();
        imgui.SetNextWindowPos({defX, defY}, ImGuiCond_Always);
        forcePositionReset = false;
        hasAppliedSavedPosition = true;
        lastSavedPosX, lastSavedPosY = defX, defY;
    elseif not hasAppliedSavedPosition and gConfig.expBarWindowPosX ~= nil then
        imgui.SetNextWindowPos({gConfig.expBarWindowPosX, gConfig.expBarWindowPosY}, ImGuiCond_Once);
        hasAppliedSavedPosition = true;
        lastSavedPosX = gConfig.expBarWindowPosX;
        lastSavedPosY = gConfig.expBarWindowPosY;
    end

	local windowFlags = GetBaseWindowFlags(gConfig.lockPositions);
    if (imgui.Begin('ExpBar', true, windowFlags)) then

		-- Draw the progress bar
        local progressBarWidth = settings.barWidth;

		-- Get window origin for text positioning
		local startX, startY = imgui.GetCursorScreenPos();

		-- In inline mode, add invisible spacing for text area first
		if inlineMode then
			imgui.Dummy({actualTextWidth, settings.barHeight});
			imgui.SameLine(0, 0);
		end

		-- Get bar position (offset by text area in inline mode)
		local barStartX, barStartY = imgui.GetCursorScreenPos();

		local expGradient;
		if meritMode then
			expGradient = GetCustomGradient(gConfig.colorCustomization.expBar, 'meritBarGradient') or {'#3064c3', '#66a0e9'};
		else
			expGradient = GetCustomGradient(gConfig.colorCustomization.expBar, 'expBarGradient') or {'#c39040', '#e9c466'};
		end
		-- Let progressbar handle its own Dummy for sizing (includes border extent)
		-- Use GetUIDrawList: foreground when config closed (no clipping), window when config open (respects layering)
		progressbar.ProgressBar({{progressBarProgress, expGradient}}, {progressBarWidth, settings.barHeight}, {decorate = gConfig.showExpBarBookends, drawList = drawing.GetUIDrawList()});

        -- Calculate text padding
        local bookendWidth = gConfig.showExpBarBookends and (settings.barHeight / 2) or 0;
        local textPadding = 8;

        local textY = inlineMode and startY or startY + settings.barHeight + settings.textOffsetY;

        -- Left-aligned text position (job text)
        local leftTextX;
        if inlineMode then
            -- In inline mode, text is in the left column area, 8px from left edge
            leftTextX = startX + textPadding;
        else
            -- In non-inline mode, text is on the bar, 8px from left edge (after bookend)
            leftTextX = startX + bookendWidth + textPadding;
        end

        -- Right-aligned text position (exp text)
        local rightTextX;
        if inlineMode then
            -- In inline mode, text is in the left column area, 8px from right edge of text column
            rightTextX = barStartX - textPadding;
        else
            -- In non-inline mode, text is on the bar, 8px from right edge (before bookend)
            rightTextX = startX + progressBarWidth - bookendWidth - textPadding;
        end

        -- Pre-calculate percent text width for layout purposes (needed before expText positioning)
        local percentTextWidth = 0;
        if percentString then
            percentText:set_text(percentString);
            percentTextWidth = percentText:get_text_size();
        end

		-- Update our text objects

		-- Dynamically set font heights based on settings (avoids expensive font recreation)
		jobText:set_font_height(settings.job_font_settings.font_height);
		expText:set_font_height(settings.exp_font_settings.font_height);
		percentText:set_font_height(settings.percent_font_settings.font_height);

        -- Declare width variables in wider scope for use in percent text positioning
        local textWidth, textHeight = 0, 0;
        local expTextWidth, expTextHeight = 0, 0;

        -- Get user-defined text offsets
        local jobOffsetX = settings.jobTextOffsetX or 0;
        local jobOffsetY = settings.jobTextOffsetY or 0;
        local expOffsetX = settings.expTextOffsetX or 0;
        local expOffsetY = settings.expTextOffsetY or 0;
        local percentOffsetX = settings.percentTextOffsetX or 0;
        local percentOffsetY = settings.percentTextOffsetY or 0;

        if jobString then
            -- Job Text (string already built above)
            jobText:set_text(jobString);
            textWidth, textHeight = jobText:get_text_size();
            local jobBaseX = leftTextX;
            local jobBaseY = inlineMode and textY + (settings.barHeight - textHeight) / 2 - 1 or textY;
            jobText:set_position_x(jobBaseX + jobOffsetX);
            jobText:set_position_y(jobBaseY + jobOffsetY);
            -- Only call set_font_color if the color has changed (expensive operation for GDI fonts)
            if (lastJobTextColor ~= gConfig.colorCustomization.expBar.jobTextColor) then
                jobText:set_font_color(gConfig.colorCustomization.expBar.jobTextColor);
                lastJobTextColor = gConfig.colorCustomization.expBar.jobTextColor;
            end

            -- Exp Text (string already built above with correct separator)
            expText:set_text(expString);
            expTextWidth, expTextHeight = expText:get_text_size();

            -- Position exp text after job text in inline mode, or at right edge in non-inline mode
            local expBaseX;
            if inlineMode then
                -- Exp text is right-aligned, so X position is the RIGHT edge
                -- Position it so the right edge is at: leftTextX + jobWidth + expWidth
                expBaseX = leftTextX + textWidth + expTextWidth + expBarTextMargin;
            else
                -- In non-inline mode, if percent is shown, leave room for it on the right
                if gConfig.expBarShowPercent then
                    expBaseX = rightTextX - percentTextWidth;
                else
                    expBaseX = rightTextX;
                end
            end
            local expBaseY = inlineMode and textY + (settings.barHeight - expTextHeight) / 2 - 1 or textY;
            expText:set_position_x(expBaseX + expOffsetX);
            expText:set_position_y(expBaseY + expOffsetY);
            -- Only call set_font_color if the color has changed
            if (lastExpTextColor ~= gConfig.colorCustomization.expBar.expTextColor) then
                expText:set_font_color(gConfig.colorCustomization.expBar.expTextColor);
                lastExpTextColor = gConfig.colorCustomization.expBar.expTextColor;
            end

            jobText:set_visible(true);
            expText:set_visible(true);
        else
            jobText:set_visible(false);
            expText:set_visible(false);
        end

        -- Percent Text
        if percentString then
            -- percentString and percentTextWidth already calculated above for layout purposes
            local _, percentTextHeight = percentText:get_text_size();

            -- Position percent text
            local percentTextX, percentTextY;
            if inlineMode then
                -- In inline mode, position after exp text on the same line (with spacing)
                if gConfig.expBarShowText then
                    -- Percent text is right-aligned, so X position is the RIGHT edge
                    -- Add expBarTextMargin spacing between exp text and percent text
                    percentTextX = leftTextX + textWidth + expTextWidth + expBarTextMargin + percentTextWidth + expBarTextMargin;
                else
                    percentTextX = leftTextX + percentTextWidth;
                end
                percentTextY = textY + (settings.barHeight - percentTextHeight) / 2 - 1;
            else
                -- In non-inline mode
                if gConfig.expBarShowText then
                    -- Position on the same line as exp text (below bar), to the right
                    percentTextX = rightTextX;
                    percentTextY = textY;
                else
                    -- No text shown, position above the bar like before
                    percentTextX = barStartX + progressBarWidth - bookendWidth - textPadding;
                    percentTextY = startY - percentTextHeight - settings.textOffsetY;
                end
            end

            percentText:set_position_x(percentTextX + percentOffsetX);
            percentText:set_position_y(percentTextY + percentOffsetY);
            -- Only call set_font_color if the color has changed
            if (lastPercentTextColor ~= gConfig.colorCustomization.expBar.percentTextColor) then
                percentText:set_font_color(gConfig.colorCustomization.expBar.percentTextColor);
                lastPercentTextColor = gConfig.colorCustomization.expBar.percentTextColor;
            end

            percentText:set_visible(true);
        else
            percentText:set_visible(false);
        end

        -- Save position if moved (with change detection to avoid spam)
        local winPosX, winPosY = imgui.GetWindowPos();
        if not gConfig.lockPositions then
            if lastSavedPosX == nil or
               math.abs(winPosX - lastSavedPosX) > 1 or
               math.abs(winPosY - lastSavedPosY) > 1 then
                gConfig.expBarWindowPosX = winPosX;
                gConfig.expBarWindowPosY = winPosY;
                lastSavedPosX = winPosX;
                lastSavedPosY = winPosY;
            end
        end
    end
	imgui.End();
end


expbar.Initialize = function(settings)
	-- Use FontManager for cleaner font creation
    jobText = FontManager.create(settings.job_font_settings);
	expText = FontManager.create(settings.exp_font_settings);
	percentText = FontManager.create(settings.percent_font_settings);
	allFonts = {jobText, expText, percentText};

    local player = GetPlayerSafe();
    if player ~= nil then
        expbar.limitPoints = { player:GetLimitPoints(), 10000 };
        expbar.meritPoints = { player:GetMeritPoints(), player:GetMeritPointsMax() };
        local currJob = player:GetMainJob();
        expbar.capacityPoints = { player:GetCapacityPoints(currJob), 30000 };
        expbar.jobPoints = { player:GetJobPoints(currJob), 500 };
        expbar.mastery = { player:GetMasteryExp(), player:GetMasteryExpNeeded() };
        expbar.mlBreakerItemId = GetKeyItemFromName('master breaker')
    end
end

expbar.UpdateVisuals = function(settings)
	-- Use FontManager for cleaner font recreation
	jobText = FontManager.recreate(jobText, settings.job_font_settings);
	expText = FontManager.recreate(expText, settings.exp_font_settings);
	percentText = FontManager.recreate(percentText, settings.percent_font_settings);
	allFonts = {jobText, expText, percentText};

	-- Reset cached colors when fonts are recreated
	lastJobTextColor = nil;
	lastExpTextColor = nil;
	lastPercentTextColor = nil;
end

expbar.SetHidden = function(hidden)
	if (hidden == true) then
		SetFontsVisible(allFonts, false);
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
            elseif msgId == 809 or msgId == 810 then
                expbar.mastery[1] = expbar.mastery[1] + val;
            end
        end
    elseif e.id == 0x061 then
        expbar.mastery[1] = struct.unpack('I', e.data_modified, 0x69);
        expbar.mastery[2] = struct.unpack('I', e.data_modified, 0x6D);
    elseif e.id == 0x063 then
        if e.data_modified:byte(5) == 2 then
            expbar.limitPoints[1] = struct.unpack('H', e.data_modified, 0x08 + 1);
            expbar.meritPoints[1] = e.data_modified:byte(0x0A + 1) % 128;
            expbar.meritPoints[2] = e.data_modified:byte(0x0C + 1) % 128;
            -- print('Limit points B: ' .. expbar.limitPoints[1] .. ' / ' .. expbar.limitPoints[2]);
        elseif e.data_modified:byte(5) == 5 then
            local player = GetPlayerSafe();
            if player ~= nil then
                local jobOffset = player:GetMainJob() * 6 + 13;
                expbar.capacityPoints[1] = struct.unpack('H', e.data_modified, jobOffset);
                expbar.jobPoints[1] = struct.unpack('H', e.data_modified, jobOffset + 2);
            end
        end
    end
end

expbar.Cleanup = function()
	-- Use FontManager for cleaner font destruction
	jobText = FontManager.destroy(jobText);
	expText = FontManager.destroy(expText);
	percentText = FontManager.destroy(percentText);
	allFonts = nil;
end

expbar.ResetPositions = function()
	forcePositionReset = true;
	hasAppliedSavedPosition = false;
end

return expbar;