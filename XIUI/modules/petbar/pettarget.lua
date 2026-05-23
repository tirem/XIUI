--[[
* XIUI Pet Bar - Pet Target Module
* Displays information about what the pet is targeting
* Separate window that can snap below or above the main pet bar (Snap to Pet Bar settings)
]]--

require('common');
require('handlers.helpers');
require('handlers.imgui_compat');
local imgui = require('imgui');
local imtext = require('libs.imtext');
local windowBg = require('libs.windowbackground');
local progressbar = require('libs.progressbar');

local data = require('modules.petbar.data');

local pettarget = {};

-- Previous-frame window size cache (used for bg layering below content on the draw list)
local cachedWindowSize = { width = nil, height = nil };

-- ============================================
-- Snap + Cluster Drag State Helpers
-- ============================================

local function clearPetTargetSpatialState()
    data.petBarTargetHitRect = nil;
    data.petBarClusterDragActive = false;
end

local function pointInPetTargetHitRect(px, py, r)
    return r and px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h;
end

local function anyImGuiItemHovered()
    local ok, v = pcall(function() return imgui.IsAnyItemHovered(); end);
    return ok and v;
end

-- While Pet Target is snapped + NoInputs (so it can't steal clicks from hotbars
-- stacked underneath), ImGui won't report hover/drag on this window. We instead
-- use the last-frame outer-rect (data.petBarTargetHitRect) + MouseDelta to drag
-- the whole pet bar cluster (PetBar) when the user click-drags within the rect.
local function maybeDragSnappedPetClusterFromTarget(snapEnabled)
    local canClusterMove = not gConfig.lockPositions or (showConfig and showConfig[1] and gConfig.petBarPreview);
    if not (snapEnabled and canClusterMove and data.petBarTargetHitRect) then
        if not snapEnabled then
            data.petBarClusterDragActive = false;
        end
        return;
    end

    local r = data.petBarTargetHitRect;
    local mx, my = imgui.GetMousePos();
    local inRect = pointInPetTargetHitRect(mx, my, r);

    if imgui.IsMouseClicked(0) then
        -- Begin cluster drag only when click lands in our rect AND no ImGui item
        -- claims the click (so e.g. an icon button doesn't get hijacked).
        if inRect and not anyImGuiItemHovered() then
            data.petBarClusterDragActive = true;
        else
            data.petBarClusterDragActive = false;
        end
    end
    if imgui.IsMouseReleased(0) then
        data.petBarClusterDragActive = false;
    end

    if data.petBarClusterDragActive and imgui.IsMouseDown(0) and imgui.IsMouseDragging(0) then
        local io = imgui.GetIO();
        local mdx, mdy = 0, 0;
        if io then
            if io.MouseDelta then
                mdx = tonumber(io.MouseDelta.x) or 0;
                mdy = tonumber(io.MouseDelta.y) or 0;
            end
            if mdx == 0 and mdy == 0 then
                mdx = tonumber(io.MouseDeltaX) or 0;
                mdy = tonumber(io.MouseDeltaY) or 0;
            end
        end
        if mdx ~= 0 or mdy ~= 0 then
            local bx = tonumber(data.lastMainWindowPosX) or 0;
            local by = tonumber(data.lastMainWindowTop) or 0;
            imgui.SetWindowPos('PetBar', { bx + mdx, by + mdy });
            data.petBarSyncResizeAnchorNextFrame = true;
            data.lastMainWindowPosX = math.floor(bx + mdx + 0.5);
            data.lastMainWindowTop = math.floor(by + mdy + 0.5);
            data.petBarSnapTopReferenceY = data.lastMainWindowTop - 8;
            local ph = tonumber(data.lastPetBarWindowHeight) or 0;
            data.lastMainWindowBottom = math.floor(data.lastMainWindowTop + ph + 0.5) + 4;
        end
    end
end

local function DrawBackground(drawList, x, y, width, height, settings)
    -- Get scale from active pet type settings (same pattern as petbar data.lua)
    local petTypeKey = data.GetPetTypeKey();
    local settingsKey = 'petBar' .. petTypeKey:gsub("^%l", string.upper);
    local typeSettings = gConfig[settingsKey] or {};
    -- Prefer pet target's own scale sliders; fall back to the parent pet type
    -- so existing users see no change until they touch the pet target sliders.
    local bgScale = gConfig.petTargetBgScale or typeSettings.bgScale or 1.0;
    local borderScale = gConfig.petTargetBorderScale or typeSettings.borderScale or 1.0;

    local bgTheme = gConfig.petTargetBackgroundTheme or gConfig.petBarBackgroundTheme or 'Window1';
    local bgOpacity = gConfig.petTargetBackgroundOpacity or gConfig.petBarBackgroundOpacity or 1.0;
    local bgColor = gConfig.colorCustomization and gConfig.colorCustomization.petTarget and gConfig.colorCustomization.petTarget.bgColor or 0xFFFFFFFF;
    local borderColor = gConfig.colorCustomization and gConfig.colorCustomization.petTarget and gConfig.colorCustomization.petTarget.borderColor or 0xFFFFFFFF;
    local borderOpacity = gConfig.petTargetBorderOpacity or gConfig.petBarBorderOpacity or 1.0;

    windowBg.Draw(drawList, x, y, width, height, {
        theme = bgTheme,
        padding = (settings and settings.bgPadding) or data.PADDING,
        paddingY = (settings and settings.bgPaddingY) or data.PADDING,
        bgScale = bgScale,
        borderScale = borderScale,
        bgOpacity = bgOpacity,
        bgColor = bgColor,
        borderSize = (settings and settings.borderSize) or 21,
        bgOffset = (settings and settings.bgOffset) or 1,
        borderOpacity = borderOpacity,
        borderColor = borderColor,
    });
end

-- ============================================
-- DrawWindow
-- ============================================
function pettarget.DrawWindow(settings)
    local isPreview = showConfig and showConfig[1] and gConfig.petBarPreview;

    -- Global UI scale multiplier; applied to raw gConfig.petTarget* / petBarTarget* fallbacks.
    local gs = gConfig.globalScale or 1.0;

    -- Only show if we have a valid pet (prevents showing when "Always Visible" is on but no pet)
    if data.GetPetData() == nil then
        clearPetTargetSpatialState();
        return;
    end

    local targetName, targetHp, targetDistance, targetIndex;

    if isPreview then
        targetName = 'Goblin Mugger';
        targetHp = 72;
        targetDistance = 6.3;
        targetIndex = 999;
    else
        -- Only show if pet target tracking is enabled and we have a target
        if gConfig.petBarShowTarget == false or data.petTargetServerId == nil then
            clearPetTargetSpatialState();
            return;
        end

        -- Check if pet is targeting itself (e.g., after self-buff like Aerial Armor)
        local petEntity = data.GetPetEntity();
        if petEntity and petEntity.ServerId and data.petTargetServerId == petEntity.ServerId then
            clearPetTargetSpatialState();
            return;
        end

        local targetEnt = data.GetEntityByServerId(data.petTargetServerId);
        if targetEnt == nil or targetEnt.ActorPointer == 0 or targetEnt.HPPercent <= 0 then
            data.petTargetServerId = nil;
            clearPetTargetSpatialState();
            return;
        end

        targetName = targetEnt.Name or 'Unknown';
        targetHp = targetEnt.HPPercent;
        targetDistance = math.sqrt(targetEnt.Distance or 0);
        targetIndex = targetEnt.TargetIndex or 0;
    end

    -- Use cached values from main pet bar
    local windowFlags = data.lastWindowFlags or data.getBaseWindowFlags();
    local petBarColorConfig = data.lastColorConfig or {};
    local totalRowWidth = data.lastTotalRowWidth or 150;

    -- Get pet target specific color config
    local colorConfig = gConfig.colorCustomization and gConfig.colorCustomization.petTarget or {};

    -- Snap-to-petbar positioning.
    -- Anchor semantics (pet bar uses AlwaysAutoResize; coordinates are ImGui outer rect, NoDecoration):
    --   bottom: PetBarTarget window TOP = pet bar bottom (+ small border fudge in lastMainWindowBottom) + offsetY (positive = down).
    --   top:    PetBarTarget window TOP = pet bar visual top - target height + offsetY - topGap (see petBarSnapTopReferenceY).
    -- Snap must win over ApplyWindowPosition (otherwise first-frame Always apply from disk overwrites the snapped position).
    local snapEnabled = gConfig.petTargetSnapToPetBar;
    local snapAnchor = gConfig.petTargetSnapAnchor or 'bottom';
    local snapOffsetX = (gConfig.petTargetSnapOffsetX or 0) * gs;
    local snapOffsetY = gConfig.petTargetSnapOffsetY;
    if snapOffsetY == nil then
        snapOffsetY = (snapAnchor == 'top') and -6 or 16;
    end
    -- Bottom-anchor uses positive Y below the bar; top-anchor uses non-positive Y. A leftover +16 from bottom mode would otherwise leave a visible gap.
    if snapAnchor == 'top' and snapOffsetY > 0 then
        snapOffsetY = 0;
    end
    snapOffsetY = snapOffsetY * gs;

    maybeDragSnappedPetClusterFromTarget(snapEnabled);

    if not snapEnabled then
        -- Only apply persisted position when we're not snapping; snap mode positions us ourselves.
        ApplyWindowPosition('PetBarTarget');
    end
    if snapEnabled and data.lastMainWindowPosX ~= nil then
        local snapX = math.floor(data.lastMainWindowPosX + snapOffsetX + 0.5);
        local snapY;
        if snapAnchor == 'top' then
            -- Height: prefer last-frame measurement, then profile cache (stable across loads), then a safe default.
            local th = tonumber(data.lastPetBarTargetWindowHeight)
                or tonumber(gConfig.petTargetSnapCachedHeight)
                or 52;
            th = math.floor(th + 0.5);
            -- petTargetSnapTopGap: buffer between target window bottom and pet bar top (nil = default 5).
            local topGap = tonumber(gConfig.petTargetSnapTopGap);
            if topGap == nil then
                topGap = 5;
            end
            if topGap < 0 then topGap = 0; end
            topGap = math.floor(topGap + 0.5);
            local barTopY = math.floor(tonumber(data.petBarSnapTopReferenceY) or tonumber(data.lastMainWindowTop) or 0);
            snapY = math.floor(barTopY - th + snapOffsetY - topGap + 0.5);
        else
            local bottomY = data.lastMainWindowBottom;
            if bottomY ~= nil then
                snapY = math.floor(bottomY + snapOffsetY + 0.5);
            end
        end
        if snapY ~= nil then
            imgui.SetNextWindowPos({ snapX, snapY }, ImGuiCond_Always);
        end
    end

    if (gConfig.lockPositions and not isPreview) or snapEnabled then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
    end

    -- When snapped, treat as part of the pet bar cluster: don't steal mouse from hotbars
    -- stacked underneath (NoInputs). Cluster drag is implemented via maybeDragSnappedPetClusterFromTarget.
    -- When unsnapped, omit NoInputs so user can move/drop normally.
    if snapEnabled then
        local noInputs = ImGuiWindowFlags_NoInputs;
        if noInputs == nil or noInputs == 0 then
            if ImGuiWindowFlags_NoMouseInputs and ImGuiWindowFlags_NoNavInputs then
                noInputs = bit.bor(ImGuiWindowFlags_NoMouseInputs, ImGuiWindowFlags_NoNavInputs);
            else
                noInputs = 1536; -- NoMouseInputs|NoNavInputs (Dear ImGui ~1.83); last resort if globals missing
            end
        end
        if noInputs ~= 0 then
            windowFlags = bit.bor(windowFlags, noInputs);
        end
    end
    if imgui.Begin('PetBarTarget', true, windowFlags) then
        SaveWindowPosition('PetBarTarget');
        local targetWinPosX, targetWinPosY = imgui.GetWindowPos();
        local targetStartX, targetStartY = imgui.GetCursorScreenPos();
        local drawList = GetUIDrawList();

        -- Draw background FIRST so it sits beneath text/bars on the draw list.
        -- Window size only known after content; use previous frame's cached size (updated below).
        if cachedWindowSize.width and cachedWindowSize.height then
            DrawBackground(drawList, targetWinPosX, targetWinPosY, cachedWindowSize.width, cachedWindowSize.height, settings);
        end

        imtext.SetConfigFromSettings(settings.vitals_font_settings);

        -- Font sizes: first two fallbacks are raw user values (gs-scaled); third is from adjusted settings (already scaled).
        local rawTargetNameFontSize = gConfig.petBarTargetNameFontSize or gConfig.petBarTargetFontSize;
        local targetNameFontSize = rawTargetNameFontSize and (rawTargetNameFontSize * gs) or settings.vitals_font_settings.font_height;
        local rawTargetHpFontSize = gConfig.petBarTargetHpFontSize or gConfig.petBarVitalsFontSize;
        local targetHpFontSize = rawTargetHpFontSize and (rawTargetHpFontSize * gs) or settings.vitals_font_settings.font_height;
        local rawTargetDistanceFontSize = gConfig.petBarTargetDistanceFontSize or gConfig.petBarDistanceFontSize;
        local targetDistanceFontSize = rawTargetDistanceFontSize and (rawTargetDistanceFontSize * gs) or settings.distance_font_settings.font_height;

        -- Bar dimensions with scale settings (settings.barWidth/Height come from updater, already gs-scaled)
        -- Use the un-HP-scaled base pet bar width so the target HP X slider is
        -- independent of the pet HP X slider.
        local barScaleX = gConfig.petTargetBarScaleX or 1.0;
        local barScaleY = gConfig.petTargetBarScaleY or 1.0;
        local barWidth = (settings.barWidth or 150) * barScaleX;
        local barHeight = (settings.barHeight or 12) * barScaleY;

        -- Get positioning settings (offsets scale with gs)
        local nameAbsolute = gConfig.petTargetNameAbsolute;
        local nameOffsetX = (gConfig.petTargetNameOffsetX or 0) * gs;
        local nameOffsetY = (gConfig.petTargetNameOffsetY or 0) * gs;
        local hpAbsolute = gConfig.petTargetHpAbsolute;
        local hpOffsetX = (gConfig.petTargetHpOffsetX or 0) * gs;
        local hpOffsetY = (gConfig.petTargetHpOffsetY or 0) * gs;
        local distanceAbsolute = gConfig.petTargetDistanceAbsolute;
        local distanceOffsetX = (gConfig.petTargetDistanceOffsetX or 0) * gs;
        local distanceOffsetY = (gConfig.petTargetDistanceOffsetY or 0) * gs;

        -- Row 1: Target Name (left-aligned)
        local targetColor = colorConfig.targetTextColor or petBarColorConfig.targetTextColor or 0xFFFFFFFF;
        local nameW, nameH = imtext.Measure(targetName, targetNameFontSize);
        local nameDrawX, nameDrawY;
        if nameAbsolute then
            -- Absolute positioning: relative to window top-left
            nameDrawX = targetWinPosX + nameOffsetX;
            nameDrawY = targetWinPosY + nameOffsetY;
        else
            -- Inline positioning: in layout flow with offsets
            nameDrawX = targetStartX + nameOffsetX;
            nameDrawY = targetStartY + nameOffsetY;
        end
        imtext.Draw(drawList, targetName, nameDrawX, nameDrawY, targetColor, targetNameFontSize);

        -- HP% text (right-aligned: subtract width to convert from right edge)
        local hpColor = colorConfig.hpTextColor or petBarColorConfig.hpTextColor or 0xFFFFA7A7;
        local hpStr = tostring(targetHp) .. '%';
        local hpW, hpH = imtext.Measure(hpStr, targetHpFontSize);
        local hpDrawX, hpDrawY;
        if hpAbsolute then
            -- Absolute positioning: relative to window top-left
            hpDrawX = targetWinPosX + hpOffsetX - hpW;
            hpDrawY = targetWinPosY + hpOffsetY;
        else
            -- Inline positioning: right side of bar row with offsets
            hpDrawX = targetStartX + barWidth + hpOffsetX - hpW;
            hpDrawY = targetStartY + (targetNameFontSize - targetHpFontSize) / 2 + hpOffsetY;
        end
        imtext.Draw(drawList, hpStr, hpDrawX, hpDrawY, hpColor, targetHpFontSize);

        -- Only add space for name row if name or HP are inline (not absolute)
        if not nameAbsolute or not hpAbsolute then
            imgui.Dummy({barWidth, targetNameFontSize + 4});
        end

        -- Row 2: HP Bar with interpolation
        local currentTime = os.clock();
        local hpGradient = GetCustomGradient(colorConfig, 'hpGradient') or {'#e26c6c', '#fb9494'};
        local hpPercentData = HpInterpolation.update('pettarget', targetHp, targetIndex, settings, currentTime, hpGradient);

        progressbar.ProgressBar(hpPercentData, {barWidth, barHeight}, {decorate = gConfig.petTargetShowBookends or gConfig.petBarShowBookends});

        -- Distance text (left-aligned)
        local distanceColor = colorConfig.distanceTextColor or petBarColorConfig.distanceTextColor or 0xFFFFFFFF;
        local distStr = string.format('%.1f', targetDistance);
        local distDrawX, distDrawY;
        if distanceAbsolute then
            -- Absolute positioning: relative to window top-left
            distDrawX = targetWinPosX + distanceOffsetX;
            distDrawY = targetWinPosY + distanceOffsetY;
        else
            -- Inline positioning: below HP bar in layout flow.
            -- Add the bar's border extent so the text clears the additive border.
            local borderThickness = gConfig.barBorderThickness or 1;
            local barBorderExtent = (borderThickness > 0) and (borderThickness / 2 + 0.5) or 0;
            local distanceY = targetStartY + targetNameFontSize + 4 + barHeight + barBorderExtent + 2;
            distDrawX = targetStartX + distanceOffsetX;
            distDrawY = distanceY + distanceOffsetY;
            -- Add dummy for inline layout
            imgui.Dummy({totalRowWidth, targetDistanceFontSize + 2});
        end
        imtext.Draw(drawList, distStr, distDrawX, distDrawY, distanceColor, targetDistanceFontSize);

        -- Cache window size for next frame's bg draw and for top-snap height math
        local targetWinWidth, targetWinHeight = imgui.GetWindowSize();
        cachedWindowSize.width, cachedWindowSize.height = targetWinWidth, targetWinHeight;

        -- Persist height for cluster math + next-session top-snap placement.
        local hRounded = math.floor(tonumber(targetWinHeight) + 0.5);
        data.lastPetBarTargetWindowHeight = hRounded;
        if snapEnabled and snapAnchor == 'top' then
            local prev = gConfig.petTargetSnapCachedHeight;
            if prev ~= hRounded then
                gConfig.petTargetSnapCachedHeight = hRounded;
            end
        end

        -- Outer rect used by maybeDragSnappedPetClusterFromTarget when NoInputs blocks hover detection.
        data.petBarTargetHitRect = {
            x = math.floor(targetWinPosX + 0.5),
            y = math.floor(targetWinPosY + 0.5),
            w = math.floor(tonumber(targetWinWidth) + 0.5),
            h = math.floor(tonumber(targetWinHeight) + 0.5),
        };
    end
    imgui.End();
end

function pettarget.Initialize(settings)
end

function pettarget.UpdateVisuals(settings)
    imtext.Reset();
end

function pettarget.SetHidden(hidden)
    if hidden then
        clearPetTargetSpatialState();
    end
end

function pettarget.Cleanup()
end

return pettarget;
