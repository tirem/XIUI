--[[
    Party List Display Module
    Handles rendering of party members and windows
]]

require('common');
require('handlers.helpers');
local ffi = require('ffi');
local imgui = require('imgui');
local statusHandler = require('handlers.statushandler');
local buffTable = require('libs.bufftable');
local statusIcons = require('libs.statusicons');
local progressbar = require('libs.progressbar');
local windowBg = require('libs.windowbackground');
local encoding = require('submodules.gdifonts.encoding');
local ashita_settings = require('settings');
local castcostShared = require('modules.castcost.shared');
local defaultPositions = require('libs.defaultpositions');

local data = require('modules.partylist.data');

local display = {};

-- Position save/restore state (per-party)
local hasAppliedSavedPosition = { false, false, false };
local forcePositionReset = { false, false, false };
local lastSavedPosX = { nil, nil, nil };
local lastSavedPosY = { nil, nil, nil };

-- Helper: Set font text only if changed (avoids texture regeneration)
local function setCachedText(memIdx, fontKey, font, text)
    if not data.memberTextCache[memIdx] then
        data.memberTextCache[memIdx] = {};
    end
    if data.memberTextCache[memIdx][fontKey] ~= text then
        font:set_text(text);
        data.memberTextCache[memIdx][fontKey] = text;
    end
end

-- ============================================
-- DrawMember - Render a single party member
-- ============================================
function display.DrawMember(memIdx, settings, isLastVisibleMember)
    local memInfo = data.GetMemberInformation(memIdx);
    if (memInfo == nil) then
        memInfo = {
            hp = 0, hpp = 0, maxhp = 0,
            mp = 0, mpp = 0, maxmp = 0,
            tp = 0, job = '', level = '',
            subjob = '', subjoblevel = '',
            targeted = false, serverid = 0,
            buffs = nil, sync = false,
            subTargeted = false, zone = '',
            inzone = false, name = '', leader = false
        };
    end

    local partyIndex = math.ceil((memIdx + 1) / data.partyMaxSize);
    local cache = data.partyConfigCache[partyIndex];
    local scale = data.getScale(partyIndex);
    local showTP = data.showPartyTP(partyIndex);

    -- Check if this job has MP (considers main job and sub job)
    local jobHasMP = JobHasMP(memInfo.job, memInfo.subjob);

    local subTargetActive = GetSubTargetActive();

    -- Get HP colors
    local hpNameColor, hpGradient = GetCustomHpColors(memInfo.hpp, cache.colors);

    local layout = cache.layout or 0;
    local barScales = data.getBarScales(partyIndex);
    local layoutTemplate = data.getLayoutTemplate(partyIndex);
    local textOffsets = data.getTextOffsets(partyIndex);

    -- Get base bar dimensions
    local baseHpBarWidth = layoutTemplate.hpBarWidth or settings.hpBarWidth or 150;
    local baseMpBarWidth = layoutTemplate.mpBarWidth or settings.mpBarWidth or 100;
    local baseTpBarWidth = layoutTemplate.tpBarWidth or settings.tpBarWidth or 100;
    local baseBarHeight = layoutTemplate.barHeight or settings.barHeight or 20;

    -- Apply bar scales
    local hpBarWidth, mpBarWidth, tpBarWidth, hpBarHeight, mpBarHeight, tpBarHeight;
    if barScales then
        hpBarWidth = baseHpBarWidth * scale.x * barScales.hpBarScaleX;
        mpBarWidth = baseMpBarWidth * scale.x * barScales.mpBarScaleX;
        tpBarWidth = baseTpBarWidth * scale.x * barScales.tpBarScaleX;
        hpBarHeight = baseBarHeight * scale.y * barScales.hpBarScaleY;
        mpBarHeight = baseBarHeight * scale.y * barScales.mpBarScaleY;
        tpBarHeight = baseBarHeight * scale.y * barScales.tpBarScaleY;
    else
        hpBarWidth = baseHpBarWidth * scale.x;
        mpBarWidth = baseMpBarWidth * scale.x;
        tpBarWidth = baseTpBarWidth * scale.x;
        hpBarHeight = baseBarHeight * scale.y;
        mpBarHeight = baseBarHeight * scale.y;
        tpBarHeight = baseBarHeight * scale.y;
    end
    local barHeight = baseBarHeight * scale.y;

    local hpStartX, hpStartY = imgui.GetCursorScreenPos();

    local fontSizes = data.getFontSizes(partyIndex);

    -- Set font heights
    data.memberText[memIdx].hp:set_font_height(fontSizes.hp);
    data.memberText[memIdx].mp:set_font_height(fontSizes.mp);
    data.memberText[memIdx].name:set_font_height(fontSizes.name);
    data.memberText[memIdx].tp:set_font_height(fontSizes.tp);
    data.memberText[memIdx].distance:set_font_height(fontSizes.distance);
    data.memberText[memIdx].zone:set_font_height(fontSizes.zone);

    -- Get reference heights
    local refHeights = data.partyRefHeights[partyIndex];
    local hpRefHeight = refHeights.hpRefHeight;
    local mpRefHeight = refHeights.mpRefHeight;
    local tpRefHeight = refHeights.tpRefHeight;
    local nameRefHeight = refHeights.nameRefHeight;

    -- Calculate text sizes (use cached text to avoid texture regeneration)
    local nameText = tostring(memInfo.name);
    setCachedText(memIdx, 'name', data.memberText[memIdx].name, nameText);
    local nameWidth, nameHeight = data.memberText[memIdx].name:get_text_size();

    -- Format HP text based on display mode
    local hpDisplayText;
    local hpDisplayMode = cache.hpDisplayMode or 'number';
    local hpPercent = math.floor(memInfo.hpp * 100);
    if hpDisplayMode == 'percent' then
        hpDisplayText = tostring(hpPercent) .. '%';
    elseif hpDisplayMode == 'both' then
        hpDisplayText = tostring(memInfo.hp) .. ' (' .. tostring(hpPercent) .. '%)';
    elseif hpDisplayMode == 'both_percent_first' then
        hpDisplayText = tostring(hpPercent) .. '% (' .. tostring(memInfo.hp) .. ')';
    elseif hpDisplayMode == 'current_max' then
        hpDisplayText = tostring(memInfo.hp) .. '/' .. tostring(memInfo.maxhp);
    else
        hpDisplayText = tostring(memInfo.hp);
    end
    setCachedText(memIdx, 'hp', data.memberText[memIdx].hp, hpDisplayText);
    local hpTextWidth, hpHeight = data.memberText[memIdx].hp:get_text_size();

    -- Format MP text based on display mode
    local mpDisplayText;
    local mpDisplayMode = cache.mpDisplayMode or 'number';
    local mpPercent = math.floor(memInfo.mpp * 100);
    if mpDisplayMode == 'percent' then
        mpDisplayText = tostring(mpPercent) .. '%';
    elseif mpDisplayMode == 'both' then
        mpDisplayText = tostring(memInfo.mp) .. ' (' .. tostring(mpPercent) .. '%)';
    elseif mpDisplayMode == 'both_percent_first' then
        mpDisplayText = tostring(mpPercent) .. '% (' .. tostring(memInfo.mp) .. ')';
    elseif mpDisplayMode == 'current_max' then
        mpDisplayText = tostring(memInfo.mp) .. '/' .. tostring(memInfo.maxmp);
    else
        mpDisplayText = tostring(memInfo.mp);
    end
    setCachedText(memIdx, 'mp', data.memberText[memIdx].mp, mpDisplayText);
    local mpTextWidth, mpHeight = data.memberText[memIdx].mp:get_text_size();

    local tpText = tostring(memInfo.tp);
    setCachedText(memIdx, 'tp', data.memberText[memIdx].tp, tpText);
    local tpTextWidth, tpHeight = data.memberText[memIdx].tp:get_text_size();

    -- Calculate max TP text width for Layout 1 (cached per party to avoid per-frame texture regen)
    local maxTpTextWidth = tpTextWidth;
    if layout == 1 then
        if not data.maxTpTextWidthCache[partyIndex] then
            -- Calculate once: temporarily set to "3000", get width, restore
            data.memberText[memIdx].tp:set_text("3000");
            data.maxTpTextWidthCache[partyIndex], _ = data.memberText[memIdx].tp:get_text_size();
            data.memberText[memIdx].tp:set_text(tpText);
        end
        maxTpTextWidth = data.maxTpTextWidthCache[partyIndex];
    end

    -- Calculate allBarsLengths based on layout
    -- This should be consistent across all party members for uniform zone bar/selection width
    local allBarsLengths;
    if layout == 1 then
        local row1Width = hpBarWidth;
        local row2Width = 4 + maxTpTextWidth + 4 + mpBarWidth + 4 + mpTextWidth;
        allBarsLengths = math.max(row1Width, row2Width);
    else
        -- Always include HP + MP + TP space for consistent width across all members
        allBarsLengths = hpBarWidth + mpBarWidth + imgui.GetStyle().FramePadding.x + imgui.GetStyle().ItemSpacing.x;
        if (showTP) then
            allBarsLengths = allBarsLengths + tpBarWidth + imgui.GetStyle().FramePadding.x + imgui.GetStyle().ItemSpacing.x;
        end
    end

    -- Calculate layout dimensions
    local jobIconSize = cache.showJobIcon and (settings.baseIconSize * 1.1 * scale.icon) or 0;
    local offsetSize = nameRefHeight > settings.baseIconSize and nameRefHeight or settings.baseIconSize;
    local nameIconAreaHeight = math.max(jobIconSize, nameRefHeight);

    -- Calculate entryHeight based on layout
    local entryHeight;
    if layout == 1 then
        entryHeight = nameRefHeight + settings.nameTextOffsetY + hpBarHeight + 1 + mpBarHeight;
    else
        entryHeight = nameRefHeight + settings.nameTextOffsetY + hpBarHeight + settings.hpTextOffsetY + hpRefHeight;
    end

    -- Draw selection box
    if (memInfo.targeted == true or memInfo.subTargeted) then
        local drawList = imgui.GetBackgroundDrawList();

        local selectionWidth = allBarsLengths + settings.cursorPaddingX1 + settings.cursorPaddingX2;
        local selectionScaleY = cache.selectionBoxScaleY or 1;
        local selectionOffsetY = cache.selectionBoxOffsetY or 0;
        local unscaledHeight = entryHeight + settings.cursorPaddingY1 + settings.cursorPaddingY2;
        local selectionHeight = unscaledHeight * selectionScaleY;
        local topOfMember = hpStartY - nameRefHeight - settings.nameTextOffsetY;
        local centerOffsetY = (selectionHeight - unscaledHeight) / 2;
        local selectionTL = {hpStartX - settings.cursorPaddingX1, topOfMember - settings.cursorPaddingY1 - centerOffsetY + selectionOffsetY};
        local selectionBR = {selectionTL[1] + selectionWidth, selectionTL[2] + selectionHeight};

        local selectionGradient;
        local borderColorARGB;
        if memInfo.subTargeted then
            selectionGradient = GetCustomGradient(cache.colors, 'subtargetGradient') or {'#d9a54d', '#edcf78'};
            borderColorARGB = cache.colors.subtargetBorderColor or 0xFFfdd017;
        else
            selectionGradient = GetCustomGradient(cache.colors, 'selectionGradient') or {'#4da5d9', '#78c0ed'};
            borderColorARGB = cache.colors.selectionBorderColor;
        end
        local startColor = HexToImGui(selectionGradient[1]);
        local endColor = HexToImGui(selectionGradient[2]);

        -- Draw selection box (gradient + border) if enabled
        if cache.showSelectionBox then
            -- Draw gradient effect (4 steps for performance, reuse tables)
            local gradientSteps = 4;
            local stepHeight = selectionHeight / gradientSteps;
            local selX1 = selectionTL[1];
            local selX2 = selectionBR[1];
            local selY1 = selectionTL[2];
            for i = 1, gradientSteps do
                local t = (i - 1) / (gradientSteps - 1);
                local r = startColor[1] + (endColor[1] - startColor[1]) * t;
                local g = startColor[2] + (endColor[2] - startColor[2]) * t;
                local b = startColor[3] + (endColor[3] - startColor[3]) * t;
                local alpha = 0.35 - t * 0.25;

                local stepColor = imgui.GetColorU32({r, g, b, alpha});
                local stepTL_y = selY1 + (i - 1) * stepHeight;
                local stepBR_y = stepTL_y + stepHeight;

                if i == 1 then
                    drawList:AddRectFilled({selX1, stepTL_y}, {selX2, stepBR_y}, stepColor, 6, 3);
                elseif i == gradientSteps then
                    drawList:AddRectFilled({selX1, stepTL_y}, {selX2, stepBR_y}, stepColor, 6, 12);
                else
                    drawList:AddRectFilled({selX1, stepTL_y}, {selX2, stepBR_y}, stepColor, 0);
                end
            end

            -- Draw border
            local borderColor;
            if memInfo.subTargeted then
                if data.cachedSubtargetBorderColorARGB ~= borderColorARGB then
                    data.cachedSubtargetBorderColorARGB = borderColorARGB;
                    data.cachedSubtargetBorderColorU32 = ARGBToU32(borderColorARGB);
                end
                borderColor = data.cachedSubtargetBorderColorU32;
            else
                if data.cachedBorderColorARGB ~= borderColorARGB then
                    data.cachedBorderColorARGB = borderColorARGB;
                    data.cachedBorderColorU32 = ARGBToU32(borderColorARGB);
                end
                borderColor = data.cachedBorderColorU32;
            end
            drawList:AddRect({selectionTL[1], selectionTL[2]}, {selectionBR[1], selectionBR[2]}, borderColor, 6, 15, 2);
        end

        data.partyTargeted = true;
    end

    -- Draw job icon
    local namePosX = hpStartX;
    local distanceBaseX = hpStartX; -- Base X for distance text (independent of name offsets)
    if cache.showJobIcon then
        local offsetStartY = hpStartY - jobIconSize - settings.nameTextOffsetY;
        local jobIcon = statusHandler.GetJobIcon(memInfo.job);
        if (jobIcon ~= nil) then
            namePosX = namePosX + jobIconSize + settings.nameTextOffsetX;
            distanceBaseX = distanceBaseX + jobIconSize; -- Only add job icon width, not name offset
            -- Use background draw list to render outside window clipping
            local jobIconPtr = tonumber(ffi.cast("uint32_t", jobIcon));
            local draw_list = imgui.GetBackgroundDrawList();
            draw_list:AddImage(
                jobIconPtr,
                {hpStartX, offsetStartY},
                {hpStartX + jobIconSize, offsetStartY + jobIconSize},
                {0, 0}, {1, 1},
                IM_COL32_WHITE
            );
        end
    end

    -- Update HP text color
    if not data.memberTextColorCache[memIdx] then data.memberTextColorCache[memIdx] = {}; end
    if (data.memberTextColorCache[memIdx].hp ~= cache.colors.hpTextColor) then
        data.memberText[memIdx].hp:set_font_color(cache.colors.hpTextColor);
        data.memberTextColorCache[memIdx].hp = cache.colors.hpTextColor;
    end

    -- HP Interpolation logic
    local currentTime = os.clock();
    local hppPercent = memInfo.hpp * 100;

    if not data.memberInterpolation[memIdx] then
        data.memberInterpolation[memIdx] = {
            currentHpp = hppPercent,
            interpolationDamagePercent = 0,
            interpolationHealPercent = 0
        };
    end

    local interp = data.memberInterpolation[memIdx];

    -- Handle damage
    if hppPercent < interp.currentHpp then
        local previousInterpolationDamagePercent = interp.interpolationDamagePercent;
        local damageAmount = interp.currentHpp - hppPercent;

        interp.interpolationDamagePercent = interp.interpolationDamagePercent + damageAmount;

        if previousInterpolationDamagePercent > 0 and interp.lastHitAmount and damageAmount > interp.lastHitAmount then
            interp.lastHitTime = currentTime;
            interp.lastHitAmount = damageAmount;
        elseif previousInterpolationDamagePercent == 0 then
            interp.lastHitTime = currentTime;
            interp.lastHitAmount = damageAmount;
        end

        if not interp.lastHitTime or currentTime > interp.lastHitTime + (settings.hitFlashDuration * 0.25) then
            interp.lastHitTime = currentTime;
            interp.lastHitAmount = damageAmount;
        end

        if previousInterpolationDamagePercent == 0 then
            interp.hitDelayStartTime = currentTime;
        end

        interp.interpolationHealPercent = 0;
        interp.healDelayStartTime = nil;
    elseif hppPercent > interp.currentHpp then
        -- Handle healing
        local previousInterpolationHealPercent = interp.interpolationHealPercent;
        local healAmount = hppPercent - interp.currentHpp;

        interp.interpolationHealPercent = interp.interpolationHealPercent + healAmount;

        if previousInterpolationHealPercent > 0 and interp.lastHealAmount and healAmount > interp.lastHealAmount then
            interp.lastHealTime = currentTime;
            interp.lastHealAmount = healAmount;
        elseif previousInterpolationHealPercent == 0 then
            interp.lastHealTime = currentTime;
            interp.lastHealAmount = healAmount;
        end

        if not interp.lastHealTime or currentTime > interp.lastHealTime + (settings.hitFlashDuration * 0.25) then
            interp.lastHealTime = currentTime;
            interp.lastHealAmount = healAmount;
        end

        if previousInterpolationHealPercent == 0 then
            interp.healDelayStartTime = currentTime;
        end

        interp.interpolationDamagePercent = 0;
        interp.hitDelayStartTime = nil;
    end

    interp.currentHpp = hppPercent;

    local interpolationOverlayAlpha = 0;
    local healInterpolationOverlayAlpha = 0;

    local hasDamageInterp = interp.interpolationDamagePercent > 0;
    local hasHealInterp = interp.interpolationHealPercent > 0;
    local hasActiveFlash = gConfig.healthBarFlashEnabled and (
        (interp.lastHitTime and currentTime < interp.lastHitTime + settings.hitFlashDuration) or
        (interp.lastHealTime and currentTime < interp.lastHealTime + settings.hitFlashDuration)
    );

    if hasDamageInterp or hasHealInterp or hasActiveFlash then
        if hasDamageInterp and interp.hitDelayStartTime and currentTime > interp.hitDelayStartTime + settings.hitDelayDuration then
            if interp.lastFrameTime then
                local deltaTime = currentTime - interp.lastFrameTime;
                local animSpeed = 0.1 + (0.9 * (interp.interpolationDamagePercent / 100));
                interp.interpolationDamagePercent = math.max(0, interp.interpolationDamagePercent - (settings.hitInterpolationDecayPercentPerSecond * deltaTime * animSpeed));
            end
        end

        if hasHealInterp and interp.healDelayStartTime and currentTime > interp.healDelayStartTime + settings.hitDelayDuration then
            if interp.lastFrameTime then
                local deltaTime = currentTime - interp.lastFrameTime;
                local animSpeed = 0.1 + (0.9 * (interp.interpolationHealPercent / 100));
                interp.interpolationHealPercent = math.max(0, interp.interpolationHealPercent - (settings.hitInterpolationDecayPercentPerSecond * deltaTime * animSpeed));
            end
        end

        if gConfig.healthBarFlashEnabled and interp.lastHitTime and currentTime < interp.lastHitTime + settings.hitFlashDuration then
            local hitFlashTime = currentTime - interp.lastHitTime;
            local hitFlashTimePercent = hitFlashTime / settings.hitFlashDuration;
            local maxAlphaHitPercent = 20;
            local maxAlpha = math.min(interp.lastHitAmount, maxAlphaHitPercent) / maxAlphaHitPercent;
            maxAlpha = math.max(maxAlpha * 0.6, 0.4);
            interpolationOverlayAlpha = math.pow(1 - hitFlashTimePercent, 2) * maxAlpha;
        end

        if gConfig.healthBarFlashEnabled and interp.lastHealTime and currentTime < interp.lastHealTime + settings.hitFlashDuration then
            local healFlashTime = currentTime - interp.lastHealTime;
            local healFlashTimePercent = healFlashTime / settings.hitFlashDuration;
            local maxAlphaHealPercent = 20;
            local maxAlpha = math.min(interp.lastHealAmount, maxAlphaHealPercent) / maxAlphaHealPercent;
            maxAlpha = math.max(maxAlpha * 0.6, 0.4);
            healInterpolationOverlayAlpha = math.pow(1 - healFlashTimePercent, 2) * maxAlpha;
        end
    end

    interp.lastFrameTime = currentTime;

    -- Build HP bar data
    local baseHpp = memInfo.hpp;
    if interp.interpolationHealPercent and interp.interpolationHealPercent > 0 then
        local hppInPercent = memInfo.hpp * 100;
        hppInPercent = hppInPercent - interp.interpolationHealPercent;
        hppInPercent = math.max(0, hppInPercent);
        baseHpp = hppInPercent / 100;
    end

    local hpPercentData = {{baseHpp, hpGradient}};
    local interpColors = GetHpInterpolationColors();

    if interp.interpolationDamagePercent and interp.interpolationDamagePercent > 0 then
        local interpolationOverlay;
        if gConfig.healthBarFlashEnabled and interpolationOverlayAlpha > 0 then
            interpolationOverlay = {
                interpColors.damageFlashColor,
                interpolationOverlayAlpha
            };
        end
        table.insert(hpPercentData, {
            interp.interpolationDamagePercent / 100,
            interpColors.damageGradient,
            interpolationOverlay
        });
    end

    if interp.interpolationHealPercent and interp.interpolationHealPercent > 0 then
        local healInterpolationOverlay;
        if gConfig.healthBarFlashEnabled and healInterpolationOverlayAlpha > 0 then
            healInterpolationOverlay = {
                interpColors.healFlashColor,
                healInterpolationOverlayAlpha
            };
        end
        table.insert(hpPercentData, {
            interp.interpolationHealPercent / 100,
            interpColors.healGradient,
            healInterpolationOverlay
        });
    end

    -- Draw HP bar
    if (memInfo.inzone) then
        progressbar.ProgressBar(hpPercentData, {hpBarWidth, hpBarHeight}, {decorate = cache.showBookends, backgroundGradientOverride = data.getBarBackgroundOverride(partyIndex), borderColorOverride = data.getBarBorderOverride(partyIndex)});
        data.memberText[memIdx].zone:set_visible(false);
    elseif (memInfo.zone == '' or memInfo.zone == nil) then
        local zoneBarWidth = allBarsLengths;
        local zoneBarHeight;
        if layout == 1 then
            zoneBarHeight = hpBarHeight + 1 + mpBarHeight;
        else
            zoneBarHeight = hpBarHeight;
        end
        imgui.Dummy({zoneBarWidth, zoneBarHeight});
        data.memberText[memIdx].zone:set_visible(false);
    else
        local zoneBarWidth = allBarsLengths;
        local zoneBarHeight;
        if layout == 1 then
            zoneBarHeight = hpBarHeight + 1 + mpBarHeight;
        else
            zoneBarHeight = hpBarHeight;
        end

        local zoneBarStartX, zoneBarStartY = imgui.GetCursorScreenPos();
        imgui.Dummy({zoneBarWidth, zoneBarHeight});

        local drawList = imgui.GetWindowDrawList();
        drawList:AddRect(
            {zoneBarStartX, zoneBarStartY},
            {zoneBarStartX + zoneBarWidth, zoneBarStartY + zoneBarHeight},
            imgui.GetColorU32({0.5, 0.5, 0.5, 1.0}),
            0, ImDrawCornerFlags_None, 1
        );

        local zoneName = encoding:ShiftJIS_To_UTF8(AshitaCore:GetResourceManager():GetString("zones.names", memInfo.zone), true);
        setCachedText(memIdx, 'zone', data.memberText[memIdx].zone, zoneName);
        local zoneTextWidth, zoneTextHeight = data.memberText[memIdx].zone:get_text_size();
        data.memberText[memIdx].zone:set_position_x(zoneBarStartX + (zoneBarWidth - zoneTextWidth) / 2);
        data.memberText[memIdx].zone:set_position_y(zoneBarStartY + (zoneBarHeight - zoneTextHeight) / 2);
        data.memberText[memIdx].zone:set_visible(true);
    end

    -- Position HP text
    local hpBaselineOffset = hpRefHeight - hpHeight;
    local nameBaselineOffset = nameRefHeight - nameHeight;
    if layout == 1 then
        data.memberText[memIdx].hp:set_position_x(hpStartX + hpBarWidth + 4 + textOffsets.hpX);
        data.memberText[memIdx].hp:set_position_y(hpStartY - nameRefHeight - settings.nameTextOffsetY + hpBaselineOffset + textOffsets.hpY);
    else
        data.memberText[memIdx].hp:set_position_x(hpStartX + hpBarWidth + settings.hpTextOffsetX + textOffsets.hpX);
        data.memberText[memIdx].hp:set_position_y(hpStartY + hpBarHeight + settings.hpTextOffsetY + hpBaselineOffset + textOffsets.hpY);
    end

    -- Draw leader icon
    if (memInfo.leader) then
        local dotColorARGB;
        if memInfo.allianceLeader then
            dotColorARGB = cache.colors.allianceLeaderDotColor or 0xFF00FFFF;
        else
            dotColorARGB = cache.colors.partyLeaderDotColor or 0xFFFFFF80;
        end
        local dotColor = ARGBToImGui(dotColorARGB);
        draw_circle({hpStartX + settings.dotRadius/2, hpStartY + settings.dotRadius/2}, settings.dotRadius, dotColor, settings.dotRadius * 3, true, nil, GetUIDrawList());
    end

    -- Position name text
    local desiredNameColor = cache.colors.nameTextColor;
    if (data.memberTextColorCache[memIdx].name ~= desiredNameColor) then
        data.memberText[memIdx].name:set_font_color(desiredNameColor);
        data.memberTextColorCache[memIdx].name = desiredNameColor;
    end
    data.memberText[memIdx].name:set_position_x(namePosX + textOffsets.nameX);
    data.memberText[memIdx].name:set_position_y(hpStartY - nameRefHeight - settings.nameTextOffsetY + nameBaselineOffset + textOffsets.nameY);

    -- Handle cast bars - determine if casting and calculate progress
    local castData = nil;
    local isCasting = false;
    local castProgress = 0;
    local castBarStyle = cache.castBarStyle or 'name';
    if (cache.showCastBars and memInfo.inzone and memInfo.serverid ~= nil) then
        castData = data.partyCasts[memInfo.serverid];
        if (castData ~= nil and castData.spellName ~= nil and castData.castTime ~= nil and castData.startTime ~= nil) then
            isCasting = true;

            -- Calculate cast progress
            if (memIdx == 0) then
                local castBar = GetCastBarSafe();
                if (castBar ~= nil) then
                    local percent = castBar:GetPercent();
                    local fastCast = CalculateFastCast(
                        castData.job, castData.subjob, castData.spellType,
                        castData.spellName, castData.jobLevel, castData.subjobLevel
                    );
                    if fastCast > 0 then
                        local totalCast = (1 - fastCast) * 0.75;
                        castProgress = math.min(percent / totalCast, 1.0);
                    else
                        castProgress = percent;
                    end
                end
            else
                local elapsed = os.clock() - castData.startTime;
                local effectiveCastTime = castData.castTime;
                local fastCast = CalculateFastCast(
                    castData.job, castData.subjob, castData.spellType,
                    castData.spellName, castData.jobLevel, castData.subjobLevel
                );
                if fastCast > 0 then
                    effectiveCastTime = castData.castTime * (1 - fastCast);
                end
                castProgress = math.min(elapsed / effectiveCastTime, 1.0);
            end

            -- Check if cast is complete (for player only)
            if (memIdx == 0 and castProgress >= 1.0) then
                data.partyCasts[memInfo.serverid] = nil;
                isCasting = false;
            end

            -- Handle 'name' style cast bar rendering
            if isCasting and castBarStyle == 'name' then
                setCachedText(memIdx, 'name', data.memberText[memIdx].name, castData.spellName);
                -- Set name text to cast text color
                local castTextColor = cache.colors.castTextColor or 0xFFFFCC44;
                if (data.memberTextColorCache[memIdx].name ~= castTextColor) then
                    data.memberText[memIdx].name:set_font_color(castTextColor);
                    data.memberTextColorCache[memIdx].name = castTextColor;
                end
                local spellNameWidth, _ = data.memberText[memIdx].name:get_text_size();

                local castBarWidth = hpBarWidth * 0.6 * cache.castBarScaleX;
                local castBarHeight = math.max(6, nameRefHeight * 0.8 * cache.castBarScaleY);
                local castBarOffsetX = cache.castBarOffsetX or 0;
                local castBarOffsetY = cache.castBarOffsetY or 0;
                local castBarX = namePosX + spellNameWidth + 4 + castBarOffsetX;
                local castBarY = hpStartY - nameRefHeight - settings.nameTextOffsetY + (nameRefHeight - castBarHeight) / 2 + castBarOffsetY;
                local castGradient = GetCustomGradient(cache.colors, 'castBarGradient') or {'#ffaa00', '#ffcc44'};
                progressbar.ProgressBar(
                    {{castProgress, castGradient}},
                    {castBarWidth, castBarHeight},
                    {
                        decorate = false,
                        absolutePosition = {castBarX, castBarY},
                        borderColorOverride = data.getBarBorderOverride(partyIndex)
                    }
                );
            end
        end
    end

    -- Distance text
    local showDistance = false;
    local highlightDistance = false;
    -- Only hide name/distance when casting with 'name' style (which replaces name with spell)
    -- When using 'mp' or 'tp' bar styles, name and distance should remain visible
    local hidingNameForCast = isCasting and castBarStyle == 'name';
    if (not hidingNameForCast) then
        setCachedText(memIdx, 'name', data.memberText[memIdx].name, nameText);
    end
    if (not hidingNameForCast and cache.showDistance and memInfo.inzone) then
        local distance = nil;
        if memInfo.previewDistance then
            distance = memInfo.previewDistance;
        elseif memInfo.index then
            local entity = data.frameCache.entity;
            if entity ~= nil then
                distance = math.sqrt(entity:GetDistance(memInfo.index))
            end
        end
        if (distance ~= nil and distance > 0 and distance <= 50) then
            local distanceText = ('%.1f'):fmt(distance);
            setCachedText(memIdx, 'distance', data.memberText[memIdx].distance, distanceText);
            -- Position distance relative to HP bar right edge (stable anchor)
            -- Distance uses right alignment - position is the fixed right edge anchor
            local distancePosX = hpStartX + hpBarWidth;
            data.memberText[memIdx].distance:set_position_x(distancePosX + textOffsets.distanceX);
            data.memberText[memIdx].distance:set_position_y(hpStartY - nameRefHeight + nameBaselineOffset + textOffsets.distanceY);
            showDistance = true;
            if (cache.distanceHighlight > 0 and distance <= cache.distanceHighlight) then
                highlightDistance = true;
            end
        end
    end

    data.memberText[memIdx].distance:set_visible(showDistance);
    if showDistance then
        local desiredDistanceColor = highlightDistance and 0xFF00FFFF or cache.colors.nameTextColor;
        if (data.memberTextColorCache[memIdx].distance ~= desiredDistanceColor) then
            data.memberText[memIdx].distance:set_font_color(desiredDistanceColor);
            data.memberTextColorCache[memIdx].distance = desiredDistanceColor;
        end
    end

    -- Job text (Layout 1 only)
    local showJobText = false;
    if cache.showJob and layout == 0 and memInfo.inzone and memInfo.job ~= '' and memInfo.job ~= nil and memInfo.job > 0 then
        local jobStr = '';
        if cache.showMainJob then
            local mainJobAbbr = AshitaCore:GetResourceManager():GetString('jobs.names_abbr', memInfo.job) or '';
            jobStr = mainJobAbbr;
            if cache.showMainJobLevel then
                jobStr = jobStr .. tostring(memInfo.level);
            end
        end
        if cache.showSubJob and memInfo.subjob ~= nil and memInfo.subjob ~= '' and memInfo.subjob > 0 then
            local subJobAbbr = AshitaCore:GetResourceManager():GetString('jobs.names_abbr', memInfo.subjob) or '';
            jobStr = jobStr .. '/' .. subJobAbbr;
            if cache.showSubJobLevel then
                jobStr = jobStr .. tostring(memInfo.subjoblevel);
            end
        end
        if jobStr ~= '' then
            setCachedText(memIdx, 'job', data.memberText[memIdx].job, jobStr);
            data.memberText[memIdx].job:set_font_height(fontSizes.job);
            local jobTextWidth, jobTextHeight = data.memberText[memIdx].job:get_text_size();
            local jobPosX = hpStartX + allBarsLengths - jobTextWidth;
            data.memberText[memIdx].job:set_position_x(jobPosX + textOffsets.jobX);
            data.memberText[memIdx].job:set_position_y(hpStartY - nameRefHeight - settings.nameTextOffsetY + nameBaselineOffset + textOffsets.jobY);
            local desiredJobColor = cache.colors.nameTextColor;
            if (data.memberTextColorCache[memIdx].job ~= desiredJobColor) then
                data.memberText[memIdx].job:set_font_color(desiredJobColor);
                data.memberTextColorCache[memIdx].job = desiredJobColor;
            end
            showJobText = true;
        end
    end
    data.memberText[memIdx].job:set_visible(showJobText);

    -- MP/TP bars
    -- Calculate where MP bar would be positioned (after HP bar) for consistent status icon placement
    local mpStartX = hpStartX + hpBarWidth + imgui.GetStyle().FramePadding.x + imgui.GetStyle().ItemSpacing.x;
    local mpStartY = hpStartY;
    local tpStartX, tpStartY; -- Track TP bar position

    -- Determine if we should show the MP bar slot
    -- Show if: alwaysShowMpBar is enabled, OR job has MP, OR we're casting and cast bar style is 'mp'
    local showingCastInMpSlot = isCasting and castBarStyle == 'mp' and castData;
    local showMpBar = cache.alwaysShowMpBar or jobHasMP or showingCastInMpSlot;

    -- Determine if we should show the cast bar in the TP slot
    local showingCastInTpSlot = isCasting and castBarStyle == 'tp' and castData;

    if (memInfo.inzone) then
        if layout == 1 then
            -- Layout 2: Vertical layout
            imgui.Dummy({0, 1});
            local rowStartX, rowStartY = imgui.GetCursorScreenPos();

            -- TP text (or spell name if casting with 'tp' style)
            if showingCastInTpSlot then
                -- Show spell name instead of TP when casting with 'tp' style
                setCachedText(memIdx, 'tp', data.memberText[memIdx].tp, castData.spellName);
                local castTextColor = cache.colors.castTextColor or 0xFFFFCC44;
                if (data.memberTextColorCache[memIdx].tp ~= castTextColor) then
                    data.memberText[memIdx].tp:set_font_color(castTextColor);
                    data.memberTextColorCache[memIdx].tp = castTextColor;
                end
            else
                -- Normal TP text color with optional flashing
                local desiredTpColor;
                if memInfo.tp >= 1000 and cache.flashTP then
                    local flashTime = os.clock();
                    local timePerPulse = 1;
                    local phase = flashTime % timePerPulse;
                    local pulseAlpha = (2 / timePerPulse) * phase;
                    if pulseAlpha > 1 then pulseAlpha = 2 - pulseAlpha; end
                    local baseColor = cache.colors.tpFullTextColor or 0xFFFFFFFF;
                    local flashColor = cache.colors.tpFlashColor or 0xFF3ECE00;
                    local baseA = bit.band(bit.rshift(baseColor, 24), 0xFF);
                    local baseR = bit.band(bit.rshift(baseColor, 16), 0xFF);
                    local baseG = bit.band(bit.rshift(baseColor, 8), 0xFF);
                    local baseB = bit.band(baseColor, 0xFF);
                    local flashA = bit.band(bit.rshift(flashColor, 24), 0xFF);
                    local flashR = bit.band(bit.rshift(flashColor, 16), 0xFF);
                    local flashG = bit.band(bit.rshift(flashColor, 8), 0xFF);
                    local flashB = bit.band(flashColor, 0xFF);
                    local interpA = math.floor(baseA + (flashA - baseA) * pulseAlpha);
                    local interpR = math.floor(baseR + (flashR - baseR) * pulseAlpha);
                    local interpG = math.floor(baseG + (flashG - baseG) * pulseAlpha);
                    local interpB = math.floor(baseB + (flashB - baseB) * pulseAlpha);
                    desiredTpColor = bit.bor(bit.lshift(interpA, 24), bit.lshift(interpR, 16), bit.lshift(interpG, 8), interpB);
                    if (data.memberTextColorCache[memIdx].tp ~= desiredTpColor) then
                        data.memberText[memIdx].tp:set_font_color(desiredTpColor);
                        data.memberTextColorCache[memIdx].tp = desiredTpColor;
                    end
                else
                    desiredTpColor = (memInfo.tp >= 1000) and cache.colors.tpFullTextColor or cache.colors.tpEmptyTextColor;
                    if (data.memberTextColorCache[memIdx].tp ~= desiredTpColor) then
                        data.memberText[memIdx].tp:set_font_color(desiredTpColor);
                        data.memberTextColorCache[memIdx].tp = desiredTpColor;
                    end
                end
            end

            local tpBaselineOffset = tpRefHeight - tpHeight;
            data.memberText[memIdx].tp:set_position_x(rowStartX + 4 + textOffsets.tpX);
            data.memberText[memIdx].tp:set_position_y(rowStartY + tpBaselineOffset + textOffsets.tpY);

            local mpBarStartX = rowStartX + 4 + maxTpTextWidth + 4;
            mpStartX = mpBarStartX;
            mpStartY = rowStartY;
            imgui.SetCursorScreenPos({mpStartX, mpStartY});

            -- Render cast bar or MP bar based on style and job type
            if showMpBar then
                if showingCastInMpSlot then
                    local castGradient = GetCustomGradient(cache.colors, 'castBarGradient') or {'#ffaa00', '#ffcc44'};
                    progressbar.ProgressBar({{castProgress, castGradient}}, {mpBarWidth, mpBarHeight}, {decorate = cache.showBookends, backgroundGradientOverride = data.getBarBackgroundOverride(partyIndex), borderColorOverride = data.getBarBorderOverride(partyIndex)});
                    -- Set MP text to spell name with cast text color
                    setCachedText(memIdx, 'mp', data.memberText[memIdx].mp, castData.spellName);
                    local castTextColor = cache.colors.castTextColor or 0xFFFFCC44;
                    if (data.memberTextColorCache[memIdx].mp ~= castTextColor) then
                        data.memberText[memIdx].mp:set_font_color(castTextColor);
                        data.memberTextColorCache[memIdx].mp = castTextColor;
                    end
                else
                    local mpGradient = GetCustomGradient(cache.colors, 'mpGradient') or {'#9abb5a', '#bfe07d'};

                    -- Check for spell cost preview (only for player - memIdx 0)
                    local mpPercentData;
                    if memIdx == 0 and gConfig.showMpCostPreview ~= false then
                        local spellMpCost, hasEnoughMp, isSpellActive = castcostShared.GetMpCost();
                        if isSpellActive and spellMpCost > 0 and memInfo.maxmp > 0 then
                            local costPercent = spellMpCost / memInfo.maxmp;
                            local remainingMpPercent = math.max(0, memInfo.mpp - costPercent);

                            -- Get cost preview colors from castCost settings
                            local castCostColors = gConfig.colorCustomization.castCost;
                            local costGradient;
                            local costColorSetting = castCostColors and castCostColors.mpCostPreviewGradient;
                            if costColorSetting then
                                if costColorSetting.enabled and costColorSetting.start and costColorSetting.stop then
                                    costGradient = {costColorSetting.start, costColorSetting.stop};
                                elseif costColorSetting.start then
                                    costGradient = {costColorSetting.start, costColorSetting.start};
                                else
                                    costGradient = {'#9abb5a', '#bfe07d'};
                                end
                            else
                                costGradient = {'#9abb5a', '#bfe07d'};
                            end

                            -- Calculate pulsing overlay for cost preview
                            local costOverlay = nil;
                            local flashColor = castCostColors and castCostColors.mpCostPreviewFlashColor or '#FFFFFF';
                            local pulseSpeed = castCostColors and castCostColors.mpCostPreviewPulseSpeed or 1.0;
                            if pulseSpeed > 0 then
                                local pulseTime = os.clock();
                                local phase = pulseTime % pulseSpeed;
                                local pulseAlpha = (2 / pulseSpeed) * phase;
                                if pulseAlpha > 1 then
                                    pulseAlpha = 2 - pulseAlpha;
                                end
                                pulseAlpha = pulseAlpha * 0.6;
                                costOverlay = {flashColor, pulseAlpha};
                            end

                            mpPercentData = {
                                {remainingMpPercent, mpGradient},
                                {costPercent, costGradient, costOverlay},
                            };
                        else
                            mpPercentData = {{memInfo.mpp, mpGradient}};
                        end
                    else
                        mpPercentData = {{memInfo.mpp, mpGradient}};
                    end

                    progressbar.ProgressBar(mpPercentData, {mpBarWidth, mpBarHeight}, {decorate = cache.showBookends, backgroundGradientOverride = data.getBarBackgroundOverride(partyIndex), borderColorOverride = data.getBarBorderOverride(partyIndex)});
                    if (data.memberTextColorCache[memIdx].mp ~= cache.colors.mpTextColor) then
                        data.memberText[memIdx].mp:set_font_color(cache.colors.mpTextColor);
                        data.memberTextColorCache[memIdx].mp = cache.colors.mpTextColor;
                    end
                end

                local mpBaselineOffset = mpRefHeight - mpHeight;
                data.memberText[memIdx].mp:set_position_x(mpStartX + mpBarWidth + 4 + textOffsets.mpX);
                data.memberText[memIdx].mp:set_position_y(mpStartY + (mpBarHeight - mpRefHeight) / 2 + mpBaselineOffset + textOffsets.mpY);
            end
        else
            -- Layout 0: Horizontal layout
            -- Render MP bar/cast bar if job has MP or is casting with 'mp' style
            if showMpBar then
                imgui.SameLine();
                imgui.SetCursorPosX(imgui.GetCursorPosX());
                mpStartX, mpStartY = imgui.GetCursorScreenPos();

                -- Render cast bar or MP bar based on style and job type
                if showingCastInMpSlot then
                    local castGradient = GetCustomGradient(cache.colors, 'castBarGradient') or {'#ffaa00', '#ffcc44'};
                    progressbar.ProgressBar({{castProgress, castGradient}}, {mpBarWidth, mpBarHeight}, {decorate = cache.showBookends, backgroundGradientOverride = data.getBarBackgroundOverride(partyIndex), borderColorOverride = data.getBarBorderOverride(partyIndex)});
                    -- Set MP text to spell name with cast text color
                    setCachedText(memIdx, 'mp', data.memberText[memIdx].mp, castData.spellName);
                    local castTextColor = cache.colors.castTextColor or 0xFFFFCC44;
                    if (data.memberTextColorCache[memIdx].mp ~= castTextColor) then
                        data.memberText[memIdx].mp:set_font_color(castTextColor);
                        data.memberTextColorCache[memIdx].mp = castTextColor;
                    end
                else
                    local mpGradient = GetCustomGradient(cache.colors, 'mpGradient') or {'#9abb5a', '#bfe07d'};

                    -- Check for spell cost preview (only for player - memIdx 0)
                    local mpPercentData;
                    if memIdx == 0 and gConfig.showMpCostPreview ~= false then
                        local spellMpCost, hasEnoughMp, isSpellActive = castcostShared.GetMpCost();
                        if isSpellActive and spellMpCost > 0 and memInfo.maxmp > 0 then
                            local costPercent = spellMpCost / memInfo.maxmp;
                            local remainingMpPercent = math.max(0, memInfo.mpp - costPercent);

                            -- Get cost preview colors from castCost settings
                            local castCostColors = gConfig.colorCustomization.castCost;
                            local costGradient;
                            local costColorSetting = castCostColors and castCostColors.mpCostPreviewGradient;
                            if costColorSetting then
                                if costColorSetting.enabled and costColorSetting.start and costColorSetting.stop then
                                    costGradient = {costColorSetting.start, costColorSetting.stop};
                                elseif costColorSetting.start then
                                    costGradient = {costColorSetting.start, costColorSetting.start};
                                else
                                    costGradient = {'#9abb5a', '#bfe07d'};
                                end
                            else
                                costGradient = {'#9abb5a', '#bfe07d'};
                            end

                            -- Calculate pulsing overlay for cost preview
                            local costOverlay = nil;
                            local flashColor = castCostColors and castCostColors.mpCostPreviewFlashColor or '#FFFFFF';
                            local pulseSpeed = castCostColors and castCostColors.mpCostPreviewPulseSpeed or 1.0;
                            if pulseSpeed > 0 then
                                local pulseTime = os.clock();
                                local phase = pulseTime % pulseSpeed;
                                local pulseAlpha = (2 / pulseSpeed) * phase;
                                if pulseAlpha > 1 then
                                    pulseAlpha = 2 - pulseAlpha;
                                end
                                pulseAlpha = pulseAlpha * 0.6;
                                costOverlay = {flashColor, pulseAlpha};
                            end

                            mpPercentData = {
                                {remainingMpPercent, mpGradient},
                                {costPercent, costGradient, costOverlay},
                            };
                        else
                            mpPercentData = {{memInfo.mpp, mpGradient}};
                        end
                    else
                        mpPercentData = {{memInfo.mpp, mpGradient}};
                    end

                    progressbar.ProgressBar(mpPercentData, {mpBarWidth, mpBarHeight}, {decorate = cache.showBookends, backgroundGradientOverride = data.getBarBackgroundOverride(partyIndex), borderColorOverride = data.getBarBorderOverride(partyIndex)});
                    if (data.memberTextColorCache[memIdx].mp ~= cache.colors.mpTextColor) then
                        data.memberText[memIdx].mp:set_font_color(cache.colors.mpTextColor);
                        data.memberTextColorCache[memIdx].mp = cache.colors.mpTextColor;
                    end
                end

                -- Recalculate mp text width in case it changed to spell name
                local currentMpTextWidth, _ = data.memberText[memIdx].mp:get_text_size();
                local mpBaselineOffset = mpRefHeight - mpHeight;
                data.memberText[memIdx].mp:set_position_x(mpStartX + mpBarWidth - currentMpTextWidth + textOffsets.mpX);
                data.memberText[memIdx].mp:set_position_y(mpStartY + mpBarHeight + settings.mpTextOffsetY + mpBaselineOffset + textOffsets.mpY);
            end

            -- TP bar (or cast bar if castBarStyle == 'tp')
            if (showTP or showingCastInTpSlot) then
                imgui.SameLine();
                imgui.SetCursorPosX(imgui.GetCursorPosX());
                tpStartX, tpStartY = imgui.GetCursorScreenPos();

                if showingCastInTpSlot then
                    -- Render cast bar in TP slot
                    local castGradient = GetCustomGradient(cache.colors, 'castBarGradient') or {'#ffaa00', '#ffcc44'};
                    progressbar.ProgressBar({{castProgress, castGradient}}, {tpBarWidth, tpBarHeight}, {decorate = cache.showBookends, backgroundGradientOverride = data.getBarBackgroundOverride(partyIndex), borderColorOverride = data.getBarBorderOverride(partyIndex)});
                    -- Set TP text to spell name with cast text color
                    setCachedText(memIdx, 'tp', data.memberText[memIdx].tp, castData.spellName);
                    local castTextColor = cache.colors.castTextColor or 0xFFFFCC44;
                    if (data.memberTextColorCache[memIdx].tp ~= castTextColor) then
                        data.memberText[memIdx].tp:set_font_color(castTextColor);
                        data.memberTextColorCache[memIdx].tp = castTextColor;
                    end
                else
                    -- Render normal TP bar
                    local tpGradient = GetCustomGradient(cache.colors, 'tpGradient') or {'#3898ce', '#78c4ee'};
                    local tpOverlayGradient = {'#0078CC', '#0078CC'};
                    local mainPercent;
                    local tpOverlay;

                    if (memInfo.tp >= 1000) then
                        mainPercent = (memInfo.tp - 1000) / 2000;
                        if (cache.flashTP) then
                            local flashARGB = cache.colors.tpFlashColor or 0xFF3ECE00;
                            local flashHex = string.format('#%06X', bit.band(flashARGB, 0xFFFFFF));
                            tpOverlay = {{1, tpOverlayGradient}, math.ceil(tpBarHeight * 5/7), 0, { flashHex, 1 }};
                        else
                            tpOverlay = {{1, tpOverlayGradient}, math.ceil(tpBarHeight * 2/7), 1};
                        end
                    else
                        mainPercent = memInfo.tp / 1000;
                    end

                    progressbar.ProgressBar({{mainPercent, tpGradient}}, {tpBarWidth, tpBarHeight}, {overlayBar=tpOverlay, decorate = cache.showBookends, backgroundGradientOverride = data.getBarBackgroundOverride(partyIndex), borderColorOverride = data.getBarBorderOverride(partyIndex)});

                    local desiredTpColor = (memInfo.tp >= 1000) and cache.colors.tpFullTextColor or cache.colors.tpEmptyTextColor;
                    if (data.memberTextColorCache[memIdx].tp ~= desiredTpColor) then
                        data.memberText[memIdx].tp:set_font_color(desiredTpColor);
                        data.memberTextColorCache[memIdx].tp = desiredTpColor;
                    end
                    setCachedText(memIdx, 'tp', data.memberText[memIdx].tp, tpText);
                end

                -- Recalculate tp text width in case it changed to spell name
                local currentTpTextWidth, _ = data.memberText[memIdx].tp:get_text_size();
                local tpBaselineOffset = tpRefHeight - tpHeight;
                data.memberText[memIdx].tp:set_position_x(tpStartX + tpBarWidth - currentTpTextWidth + textOffsets.tpX);
                data.memberText[memIdx].tp:set_position_y(tpStartY + tpBarHeight + settings.tpTextOffsetY + tpBaselineOffset + textOffsets.tpY);
            end
        end

        -- Draw cursor
        if ((memInfo.targeted == true and not subTargetActive) or memInfo.subTargeted) then
            local cursorTexture = data.cursorTextures[cache.cursor];
            if (cursorTexture ~= nil) then
                local cursorImage = tonumber(ffi.cast("uint32_t", cursorTexture.image));
                local cursorWidth = cursorTexture.width * settings.arrowSize;
                local cursorHeight = cursorTexture.height * settings.arrowSize;

                local selectionScaleY = cache.selectionBoxScaleY or 1;
                local selectionOffsetY = cache.selectionBoxOffsetY or 0;
                local unscaledHeight = entryHeight + settings.cursorPaddingY1 + settings.cursorPaddingY2;
                local selectionHeight = unscaledHeight * selectionScaleY;
                local topOfMember = hpStartY - nameRefHeight - settings.nameTextOffsetY;
                local centerOffsetY = (selectionHeight - unscaledHeight) / 2;
                local selectionTL_X = hpStartX - settings.cursorPaddingX1;
                local selectionTL_Y = topOfMember - settings.cursorPaddingY1 - centerOffsetY + selectionOffsetY;

                local cursorX = selectionTL_X - cursorWidth;
                local cursorY = selectionTL_Y + (selectionHeight / 2) - (cursorHeight / 2);

                local tintColor;
                if (memInfo.subTargeted) then
                    tintColor = ARGBToABGR(cache.subtargetArrowTint);
                else
                    tintColor = ARGBToABGR(cache.targetArrowTint);
                end

                local draw_list = GetUIDrawList();
                draw_list:AddImage(
                    cursorImage,
                    {cursorX, cursorY},
                    {cursorX + cursorWidth, cursorY + cursorHeight},
                    {0, 0}, {1, 1},
                    tintColor
                );

                data.partySubTargeted = true;
            end
        end

        -- Draw buffs/debuffs
        if (partyIndex == 1 and memInfo.buffs ~= nil and #memInfo.buffs > 0) then
            if (cache.statusTheme == 0 or cache.statusTheme == 1) then
                for k in pairs(data.reusableBuffs) do data.reusableBuffs[k] = nil; end
                for k in pairs(data.reusableDebuffs) do data.reusableDebuffs[k] = nil; end

                local buffCount = 0;
                local debuffCount = 0;
                for i = 0, #memInfo.buffs do
                    if (buffTable.IsBuff(memInfo.buffs[i])) then
                        buffCount = buffCount + 1;
                        data.reusableBuffs[buffCount] = memInfo.buffs[i];
                    else
                        debuffCount = debuffCount + 1;
                        data.reusableDebuffs[debuffCount] = memInfo.buffs[i];
                    end
                end

                -- Debuffs row (closest to party frame, at HP bar level)
                local statusOffsetX = cache.statusOffsetX or 0;
                local statusOffsetY = cache.statusOffsetY or 0;
                if (debuffCount > 0) then
                    if cache.statusSide == 0 then
                        if data.debuffWindowX[memIdx] ~= nil then
                            imgui.SetNextWindowPos({hpStartX - data.debuffWindowX[memIdx] - settings.buffOffset + statusOffsetX, hpStartY + statusOffsetY});
                        end
                    else
                        if data.fullMenuWidth[partyIndex] ~= nil then
                            local thisPosX, _ = imgui.GetWindowPos();
                            imgui.SetNextWindowPos({ thisPosX + data.fullMenuWidth[partyIndex] + statusOffsetX, hpStartY + statusOffsetY });
                        end
                    end
                    if (imgui.Begin('PlayerDebuffs'..memIdx, true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoDocking))) then
                        imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {3, 1});
                        DrawStatusIcons(data.reusableDebuffs, settings.iconSize, 32, 1, true);
                        imgui.PopStyleVar(1);
                    end
                    local debuffWindowSizeX, _ = imgui.GetWindowSize();
                    data.debuffWindowX[memIdx] = debuffWindowSizeX;
                    imgui.End();
                end

                -- Buffs row (above debuffs, further from party frame)
                if (buffCount > 0) then
                    if cache.statusSide == 0 then
                        if data.buffWindowX[memIdx] ~= nil then
                            imgui.SetNextWindowPos({hpStartX - data.buffWindowX[memIdx] - settings.buffOffset + statusOffsetX, hpStartY - settings.iconSize*1.2 + statusOffsetY});
                        end
                    else
                        if data.fullMenuWidth[partyIndex] ~= nil then
                            local thisPosX, _ = imgui.GetWindowPos();
                            imgui.SetNextWindowPos({ thisPosX + data.fullMenuWidth[partyIndex] + statusOffsetX, hpStartY - settings.iconSize * 1.2 + statusOffsetY });
                        end
                    end
                    if (imgui.Begin('PlayerBuffs'..memIdx, true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoDocking))) then
                        imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {3, 1});
                        DrawStatusIcons(data.reusableBuffs, settings.iconSize, 32, 1, true);
                        imgui.PopStyleVar(1);
                    end
                    local buffWindowSizeX, _ = imgui.GetWindowSize();
                    data.buffWindowX[memIdx] = buffWindowSizeX;
                    imgui.End();
                end
            elseif (cache.statusTheme == 2) then
                local statusOffsetX = cache.statusOffsetX or 0;
                local statusOffsetY = cache.statusOffsetY or 0;
                local resetX, resetY = imgui.GetCursorScreenPos();
                imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {0, 0});
                imgui.SetNextWindowPos({mpStartX + statusOffsetX, mpStartY - settings.iconSize - settings.xivBuffOffsetY + statusOffsetY})
                if (imgui.Begin('XIVStatus'..memIdx, true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoDocking))) then
                    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {0, 0});
                    DrawStatusIcons(statusIcons.ReorderForStatusSide(memInfo.buffs, buffTable, cache.statusSide), settings.iconSize, 32, 1);
                    imgui.PopStyleVar(1);
                end
                imgui.PopStyleVar(1);
                imgui.End();
                imgui.SetCursorScreenPos({resetX, resetY});
            elseif (cache.statusTheme == 3) then
                local statusOffsetX = cache.statusOffsetX or 0;
                local statusOffsetY = cache.statusOffsetY or 0;
                if cache.statusSide == 0 then
                    if data.buffWindowX[memIdx] ~= nil then
                        imgui.SetNextWindowPos({hpStartX - data.buffWindowX[memIdx] - settings.buffOffset + statusOffsetX, data.memberText[memIdx].name.settings.position_y - settings.iconSize/2 + statusOffsetY});
                    end
                else
                    if data.fullMenuWidth[partyIndex] ~= nil then
                        local thisPosX, _ = imgui.GetWindowPos();
                        imgui.SetNextWindowPos({ thisPosX + data.fullMenuWidth[partyIndex] + statusOffsetX, data.memberText[memIdx].name.settings.position_y - settings.iconSize/2 + statusOffsetY });
                    end
                end
                if (imgui.Begin('PlayerBuffs'..memIdx, true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoDocking))) then
                    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {0, 3});
                    DrawStatusIcons(statusIcons.ReorderBuffsClosest(memInfo.buffs, buffTable, cache.statusSide), settings.iconSize, 7, 3);
                    imgui.PopStyleVar(1);
                end
                local buffWindowSizeX, _ = imgui.GetWindowSize();
                data.buffWindowX[memIdx] = buffWindowSizeX;
                imgui.End();
            end
        end
    end

    -- Sync indicator
    if (memInfo.sync) then
        draw_circle({hpStartX + settings.dotRadius/2, hpStartY + barHeight}, settings.dotRadius, {.5, .5, 1, 1}, settings.dotRadius * 3, true, nil, GetUIDrawList());
    end

    -- Set text visibility
    data.memberText[memIdx].hp:set_visible(memInfo.inzone);
    data.memberText[memIdx].mp:set_visible(memInfo.inzone and showMpBar);
    data.memberText[memIdx].tp:set_visible(memInfo.inzone and showTP);

    -- Reserve space for layout
    if layout == 1 and memInfo.inzone then
        local row1Width = hpBarWidth;
        local row2Width = 4 + maxTpTextWidth + 4 + mpBarWidth + 4 + mpTextWidth;
        local fullWidth = math.max(row1Width, row2Width);
        imgui.Dummy({fullWidth, 0});
    end

    local bottomSpacing;
    if layout == 1 then
        bottomSpacing = math.max(0, tpRefHeight - mpBarHeight);
    else
        bottomSpacing = settings.hpTextOffsetY + hpRefHeight;
    end
    imgui.Dummy({0, bottomSpacing});

    if (not isLastVisibleMember) then
        local BASE_MEMBER_SPACING = 6;
        imgui.Dummy({0, BASE_MEMBER_SPACING + settings.entrySpacing[partyIndex]});
    end

    -- Add a click target over party member entry if in zone and enabled
    if (memInfo.inzone and not isPreviewMode and not showConfig[1] and gConfig.enablePartyListClickTarget) then
        --Save off current cursor position
        local currentCursorPositionX, currentCursorPositionY = imgui.GetCursorScreenPos();
        
        --Create button overlapping member
        local entryStartX = hpStartX;
        local entryStartY = hpStartY - nameRefHeight - settings.nameTextOffsetY;

        imgui.SetCursorScreenPos({entryStartX, entryStartY});
        if imgui.InvisibleButton('PartyMemberEntry' .. memIdx, {allBarsLengths, entryHeight}) then
            AshitaCore:GetChatManager():QueueCommand(-1, '/target ' .. memInfo.serverid);
        end

        --Uncomment to visualize button boundaries
        --local drawList = imgui.GetBackgroundDrawList();
        --drawList:AddRect(
        --    {entryStartX, entryStartY},
        --    {entryStartX + allBarsLengths, entryStartY + entryHeight},
        --    imgui.GetColorU32(0xFFFFFFFF),
        --    4.0
        --);

        --Return cursor position to previously saved location
        imgui.SetCursorScreenPos({currentCursorPositionX, currentCursorPositionY});
    end

end

-- ============================================
-- DrawPartyWindow - Render a single party window
-- ============================================
function display.DrawPartyWindow(settings, party, partyIndex)
    local firstPlayerIndex = (partyIndex - 1) * data.partyMaxSize;
    local lastPlayerIndex = firstPlayerIndex + data.partyMaxSize - 1;

    local cache = data.partyConfigCache[partyIndex];
    local partyMemberCount = data.frameCache.activeMemberCount[partyIndex];

    if (partyIndex == 1 and not gConfig.showPartyListWhenSolo and partyMemberCount <= 1) then
        data.UpdateTextVisibility(false);
        return;
    end

    if(partyIndex > 1 and partyMemberCount == 0) then
        data.UpdateTextVisibility(false, partyIndex);
        return;
    end

    local backgroundPrim = data.partyWindowPrim[partyIndex].background;

    local titleUV;
    if (partyIndex == 1) then
        titleUV = partyMemberCount == 1 and data.titleUVs.solo or data.titleUVs.party;
    elseif (partyIndex == 2) then
        titleUV = data.titleUVs.partyB;
    else
        titleUV = data.titleUVs.partyC;
    end

    local imguiPosX, imguiPosY;

    local windowFlags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoBringToFrontOnFocus, ImGuiWindowFlags_NoDocking);
    if (gConfig.lockPositions) then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
    end

    local windowName = 'PartyList';
    if (partyIndex > 1) then
        windowName = windowName .. partyIndex
    end

    local scale = data.getScale(partyIndex);
    local iconSize = 0;

    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {0,0});
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { settings.barSpacing * scale.x, 0 });
    
    ApplyWindowPosition(windowName);
    
    if (imgui.Begin(windowName, true, windowFlags)) then
        SaveWindowPosition(windowName);
        imguiPosX, imguiPosY = imgui.GetWindowPos();

        local nameRefHeight = data.partyRefHeights[partyIndex].nameRefHeight;
        local offsetSize = nameRefHeight > iconSize and nameRefHeight or iconSize;
        imgui.Dummy({0, settings.nameTextOffsetY + offsetSize});

        data.UpdateTextVisibility(true, partyIndex);

        -- Expand height if expandHeight is always on, OR if expandHeightInAlliance is on and we're in an alliance
        local shouldExpandHeight = settings.expandHeight or (settings.expandHeightInAlliance and data.isInAlliance());

        local lastVisibleMemberIdx = firstPlayerIndex;
        for i = firstPlayerIndex, lastPlayerIndex do
            local relIndex = i - firstPlayerIndex
            if ((partyIndex == 1 and shouldExpandHeight) or relIndex < partyMemberCount or relIndex < settings.minRows) then
                lastVisibleMemberIdx = i;
            end
        end

        for i = firstPlayerIndex, lastPlayerIndex do
            local relIndex = i - firstPlayerIndex
            if ((partyIndex == 1 and shouldExpandHeight) or relIndex < partyMemberCount or relIndex < settings.minRows) then
                display.DrawMember(i, settings, i == lastVisibleMemberIdx);
            else
                data.UpdateTextVisibilityByMember(i, false);
            end
        end
    end

    local menuWidth, menuHeight = imgui.GetWindowSize();

    local layout = cache.layout or 0;
    if layout == 0 then
        local barScales = data.getBarScales(partyIndex);
        local layoutTemplate = data.getLayoutTemplate(partyIndex);
        local showTP = data.showPartyTP(partyIndex);
        local hpScaleX = barScales and barScales.hpBarScaleX or 1;
        local mpScaleX = barScales and barScales.mpBarScaleX or 1;
        local tpScaleX = barScales and barScales.tpBarScaleX or 1;
        local baseHpWidth = layoutTemplate.hpBarWidth or 150;
        local baseMpWidth = layoutTemplate.mpBarWidth or 100;
        local baseTpWidth = layoutTemplate.tpBarWidth or 100;
        local baseBarSpacing = layoutTemplate.barSpacing or 8;
        local minWidth = baseHpWidth * scale.x * hpScaleX;
        -- Only include MP bar width if alwaysShowMpBar is enabled
        if cache.alwaysShowMpBar then
            minWidth = minWidth + baseBarSpacing * scale.x + baseMpWidth * scale.x * mpScaleX;
        end
        if showTP then
            minWidth = minWidth + baseBarSpacing * scale.x + baseTpWidth * scale.x * tpScaleX;
        end
        menuWidth = math.max(menuWidth, minWidth);
    end

    data.fullMenuWidth[partyIndex] = menuWidth;
    data.fullMenuHeight[partyIndex] = menuHeight;

    -- Calculate background dimensions (needed for title positioning)
    local bgWidth = data.fullMenuWidth[partyIndex] + (settings.bgPadding * 2);

    -- Update background and borders using windowbackground library
    local bgOptions = {
        theme = cache.backgroundName,
        padding = settings.bgPadding,
        paddingY = settings.bgPaddingY,
        bgScale = cache.bgScale,
        borderScale = cache.borderScale,
        bgOpacity = cache.backgroundOpacity,
        bgColor = cache.colors.bgColor,
        borderSize = settings.borderSize,
        bgOffset = settings.bgOffset,
        borderOpacity = cache.borderOpacity,
        borderColor = cache.colors.borderColor,
    };
    windowBg.update(backgroundPrim, imguiPosX, imguiPosY, data.fullMenuWidth[partyIndex], data.fullMenuHeight[partyIndex], bgOptions);

    -- Draw title (skip foreground rendering when modal is open to respect dim overlay)
    if (cache.showTitle and data.partyTitlesTexture ~= nil and not _XIUI_MODAL_OPEN) then
        local titleImage = tonumber(ffi.cast("uint32_t", data.partyTitlesTexture.image));
        local titleWidth = data.partyTitlesTexture.width;
        local titleHeight = data.partyTitlesTexture.height / 4;
        titleWidth = titleWidth * .8;
        titleHeight = titleHeight * .8;
        local titlePosX = imguiPosX + math.floor((bgWidth / 2) - (titleWidth / 2));
        local titlePosY = imguiPosY - titleHeight + 6;
        local draw_list = GetUIDrawList();
        draw_list:AddImage(
            titleImage,
            {titlePosX, titlePosY},
            {titlePosX + titleWidth, titlePosY + titleHeight},
            {titleUV[1], titleUV[2]}, {titleUV[3], titleUV[4]},
            IM_COL32_WHITE
        );
    end

    -- Save position if moved (with change detection to avoid spam) - all party windows
    local winPosX, winPosY = imgui.GetWindowPos();
    if not gConfig.lockPositions then
        if lastSavedPosX[partyIndex] == nil or
           math.abs(winPosX - lastSavedPosX[partyIndex]) > 1 or
           math.abs(winPosY - lastSavedPosY[partyIndex]) > 1 then
            if partyIndex == 1 then
                gConfig.partyListWindowPosX = winPosX;
                gConfig.partyListWindowPosY = winPosY;
            elseif partyIndex == 2 then
                gConfig.partyList2WindowPosX = winPosX;
                gConfig.partyList2WindowPosY = winPosY;
            else
                gConfig.partyList3WindowPosX = winPosX;
                gConfig.partyList3WindowPosY = winPosY;
            end
            lastSavedPosX[partyIndex] = winPosX;
            lastSavedPosY[partyIndex] = winPosY;
            -- Position will be persisted on addon unload
        end
    end

    imgui.End();
    imgui.PopStyleVar(2);

    -- Handle bottom alignment
    if (settings.alignBottom and imguiPosX ~= nil) then
        if (partyIndex == 1 and gConfig.partyListState ~= nil and gConfig.partyListState.x ~= nil) then
            local oldValues = gConfig.partyListState;
            gConfig.partyListState = {};
            gConfig.partyListState[partyIndex] = oldValues;
            ashita_settings.save();
        end

        if (gConfig.partyListState == nil) then
            gConfig.partyListState = {};
        end

        local partyListState = gConfig.partyListState[partyIndex];

        if (partyListState ~= nil) then
            if (menuHeight ~= partyListState.height) then
                local newPosY = partyListState.y + partyListState.height - menuHeight;
                imguiPosY = newPosY;
                imgui.SetWindowPos(windowName, { imguiPosX, imguiPosY });
            end
        end

        if (partyListState == nil or
                imguiPosX ~= partyListState.x or imguiPosY ~= partyListState.y or
                menuWidth ~= partyListState.width or menuHeight ~= partyListState.height) then
            gConfig.partyListState[partyIndex] = {
                x = imguiPosX,
                y = imguiPosY,
                width = menuWidth,
                height = menuHeight,
            };
            data.lastSettingsSaveTime = os.clock();
            data.pendingSettingsSave = true;
        end
    end
end

-- ============================================
-- DrawWindow - Main entry point for rendering
-- ============================================
function display.DrawWindow(settings)
    -- Rebuild config cache if settings version changed
    -- This is more efficient than rebuilding every frame but still catches config UI changes
    data.checkAndUpdateConfigCache();

    -- Cache game state
    data.frameCache.party = GetPartySafe();
    data.frameCache.player = GetPlayerSafe();
    data.frameCache.entity = GetEntitySafe();
    data.frameCache.playerTarget = GetTargetSafe();

    local party = data.frameCache.party;
    local player = data.frameCache.player;

    if (party == nil or player == nil or player.isZoning or player:GetMainJob() == 0) then
        data.UpdateTextVisibility(false);
        return;
    end

    -- Cache target info
    if data.frameCache.playerTarget ~= nil then
        data.frameCache.t1, data.frameCache.t2 = GetTargets();
        data.frameCache.stPartyIndex = GetStPartyIndex();
        data.frameCache.subTargetActive = GetSubTargetActive();
    else
        data.frameCache.t1 = nil;
        data.frameCache.t2 = nil;
        data.frameCache.stPartyIndex = nil;
        data.frameCache.subTargetActive = false;
    end

    -- Pre-calculate active member counts
    for partyIndex = 1, 3 do
        local firstIdx = (partyIndex - 1) * data.partyMaxSize;
        local count = 0;
        data.frameCache.activeMemberList[partyIndex] = {};

        if showConfig[1] and gConfig.partyListPreview then
            count = data.partyMaxSize;
            for i = 0, data.partyMaxSize - 1 do
                data.frameCache.activeMemberList[partyIndex][i] = true;
            end
        else
            for i = 0, data.partyMaxSize - 1 do
                local memIdx = firstIdx + i;
                if party:GetMemberIsActive(memIdx) ~= 0 then
                    count = count + 1;
                    data.frameCache.activeMemberList[partyIndex][i] = true;
                else
                    break;
                end
            end
        end
        data.frameCache.activeMemberCount[partyIndex] = count;
    end

    -- Handle debounced settings save
    if data.pendingSettingsSave then
        local now = os.clock();
        if now - data.lastSettingsSaveTime >= data.SETTINGS_SAVE_DEBOUNCE then
            ashita_settings.save();
            data.pendingSettingsSave = false;
        end
    end

    data.partyTargeted = false;
    data.partySubTargeted = false;

    -- Main party window
    display.DrawPartyWindow(settings, party, 1);

    -- Alliance party windows
    if (gConfig.partyListAlliance) then
        display.DrawPartyWindow(settings, party, 2);
        display.DrawPartyWindow(settings, party, 3);
    else
        data.UpdateTextVisibility(false, 2);
        data.UpdateTextVisibility(false, 3);
    end
end

display.ResetPositions = function()
    for i = 1, 3 do
        forcePositionReset[i] = true;
        hasAppliedSavedPosition[i] = false;
    end
end

return display;
