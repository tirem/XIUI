require('common');
local ffi = require('ffi');
local d3d8 = require('d3d8');
local imgui = require('imgui');
local gdi = require('gdifonts.include');
local primitives = require('primitives');
local statusHandler = require('statushandler');
local buffTable = require('bufftable');
local progressbar = require('progressbar');
local encoding = require('gdifonts.encoding');
local ashita_settings = require('settings');

local fullMenuWidth = {};
local fullMenuHeight = {};
local buffWindowX = {};
local debuffWindowX = {};

-- local backgroundPrim = {};
local partyWindowPrim = {};
partyWindowPrim[1] = {
    background = {},
}
partyWindowPrim[2] = {
    background = {},
}
partyWindowPrim[3] = {
    background = {},
}

local cursorTextures = T{}; -- Cache for cursor textures (like jobIcons)
local currentCursorName = nil; -- Track which cursor is loaded
local partyTargeted;
local partySubTargeted;
local memberText = {};
local titleText = {}; -- GDI font objects for party titles
local partyMaxSize = 6;
local memberTextCount = partyMaxSize * 3;


-- Cache last set colors to avoid expensive SetColor() calls every frame
local memberTextColorCache = {};

-- Cache converted border color to avoid redundant U32 conversion every frame
local cachedBorderColorU32 = nil;
local cachedBorderColorARGB = nil;

-- Cache last used font sizes to avoid unnecessary font recreation
local cachedFontSizes = {12, 12, 12};

-- Cache last used font family, flags, and outline width to detect changes
local cachedFontFamily = '';
local cachedFontFlags = 0;
local cachedOutlineWidth = 2;

local borderConfig = {1, '#243e58'};

local bgImageKeys = { 'bg', 'tl', 'tr', 'br', 'bl' };
local loadedBg = nil;

local partyList = {};


local function getScale(partyIndex)
    if (partyIndex == 3) then
        return {
            x = gConfig.partyList3ScaleX,
            y = gConfig.partyList3ScaleY,
            icon = gConfig.partyList3JobIconScale,
        }
    elseif (partyIndex == 2) then
        return {
            x = gConfig.partyList2ScaleX,
            y = gConfig.partyList2ScaleY,
            icon = gConfig.partyList2JobIconScale,
        }
    else
        return {
            x = gConfig.partyListScaleX,
            y = gConfig.partyListScaleY,
            icon = gConfig.partyListJobIconScale,
        }
    end
end

local function showPartyTP(partyIndex)
    if (partyIndex == 3) then
        return gConfig.partyList3TP
    elseif (partyIndex == 2) then
        return gConfig.partyList2TP
    else
        return gConfig.partyListTP
    end
end

local function UpdateTextVisibilityByMember(memIdx, visible)

    memberText[memIdx].hp:set_visible(visible);
    memberText[memIdx].mp:set_visible(visible);
    memberText[memIdx].tp:set_visible(visible);
    memberText[memIdx].name:set_visible(visible);
    memberText[memIdx].distance:set_visible(visible);
end

local function UpdateTextVisibility(visible, partyIndex)
    if partyIndex == nil then
        for i = 0, memberTextCount - 1 do
            UpdateTextVisibilityByMember(i, visible);
        end
    else
        local firstPlayerIndex = (partyIndex - 1) * partyMaxSize;
        local lastPlayerIndex = firstPlayerIndex + partyMaxSize - 1;
        for i = firstPlayerIndex, lastPlayerIndex do
            UpdateTextVisibilityByMember(i, visible);
        end
    end

    for i = 1, 3 do
        if (partyIndex == nil or i == partyIndex) then
            -- Update title text visibility
            if (titleText[i] ~= nil) then
                titleText[i]:set_visible(visible and gConfig.showPartyListTitle);
            end
            local backgroundPrim = partyWindowPrim[i].background;
            for _, k in ipairs(bgImageKeys) do
                backgroundPrim[k].visible = visible and backgroundPrim[k].exists;
            end
        end
    end
end

local function GetMemberInformation(memIdx)

    if (showConfig[1] and gConfig.partyListPreview) then
        local memInfo = {};
        memInfo.hpp = memIdx == 4 and 0.1 or memIdx == 2 and 0.5 or memIdx == 0 and 0.75 or 1;
        memInfo.maxhp = 1250;
        memInfo.hp = math.floor(memInfo.maxhp * memInfo.hpp);
        memInfo.mpp = memIdx == 1 and 0.1 or 0.75;
        memInfo.maxmp = 1000;
        memInfo.mp = math.floor(memInfo.maxmp * memInfo.mpp);
        memInfo.tp = 1500;
        memInfo.job = memIdx + 1;
        memInfo.level = 99;
        memInfo.targeted = memIdx == 4;
        memInfo.serverid = 0;
        memInfo.buffs = nil;
        memInfo.sync = false;
        memInfo.subTargeted = false;
        memInfo.zone = 100;
        memInfo.inzone = memIdx % 4 ~= 0;
        memInfo.name = 'Player ' .. (memIdx + 1);
        memInfo.leader = memIdx == 0 or memIdx == 6 or memIdx == 12;
        return memInfo
    end

    local party = GetPartySafe();
    local player = GetPlayerSafe();
    if (player == nil or party == nil or party:GetMemberIsActive(memIdx) == 0) then
        return nil;
    end

    local playerTarget = GetTargetSafe();

    local partyIndex = math.ceil((memIdx + 1) / partyMaxSize);
    local partyLeaderId = nil
    if (partyIndex == 3) then
        partyLeaderId = party:GetAlliancePartyLeaderServerId3();
    elseif (partyIndex == 2) then
        partyLeaderId = party:GetAlliancePartyLeaderServerId2();
    else
        partyLeaderId = party:GetAlliancePartyLeaderServerId1();
    end

    local memberInfo = {};
    memberInfo.zone = party:GetMemberZone(memIdx);
    memberInfo.inzone = memberInfo.zone == party:GetMemberZone(0);
    memberInfo.name = party:GetMemberName(memIdx);
    memberInfo.leader = partyLeaderId == party:GetMemberServerId(memIdx);

    if (memberInfo.inzone == true) then
        memberInfo.hp = party:GetMemberHP(memIdx);
        memberInfo.hpp = party:GetMemberHPPercent(memIdx) / 100;
        memberInfo.maxhp = memberInfo.hp / memberInfo.hpp;
        memberInfo.mp = party:GetMemberMP(memIdx);
        memberInfo.mpp = party:GetMemberMPPercent(memIdx) / 100;
        memberInfo.maxmp = memberInfo.mp / memberInfo.mpp;
        memberInfo.tp = party:GetMemberTP(memIdx);
        memberInfo.job = party:GetMemberMainJob(memIdx);
        memberInfo.level = party:GetMemberMainJobLevel(memIdx);
        memberInfo.serverid = party:GetMemberServerId(memIdx);
        memberInfo.index = party:GetMemberTargetIndex(memIdx);
        if (playerTarget ~= nil) then
            local t1, t2 = GetTargets();
            local sActive = GetSubTargetActive();
            local thisIdx = party:GetMemberTargetIndex(memIdx);
            memberInfo.targeted = (t1 == thisIdx and not sActive) or (t2 == thisIdx and sActive);
            memberInfo.subTargeted = (t1 == thisIdx and sActive);
        else
            memberInfo.targeted = false;
            memberInfo.subTargeted = false;
        end
        if (memIdx == 0) then
            memberInfo.buffs = player:GetBuffs();
        else
            memberInfo.buffs = statusHandler.get_member_status(memberInfo.serverid);
        end
        memberInfo.sync = bit.band(party:GetMemberFlagMask(memIdx), 0x100) == 0x100;

    else
        memberInfo.hp = 0;
        memberInfo.hpp = 0;
        memberInfo.maxhp = 0;
        memberInfo.mp = 0;
        memberInfo.mpp = 0;
        memberInfo.maxmp = 0;
        memberInfo.tp = 0;
        memberInfo.job = '';
        memberInfo.level = '';
        memberInfo.targeted = false;
        memberInfo.serverid = 0;
        memberInfo.buffs = nil;
        memberInfo.sync = false;
        memberInfo.subTargeted = false;
        memberInfo.index = nil;
    end

    return memberInfo;
end

local function DrawMember(memIdx, settings, isLastVisibleMember)

    local memInfo = GetMemberInformation(memIdx);
    if (memInfo == nil) then
        -- dummy data to render an empty space
        memInfo = {};
        memInfo.hp = 0;
        memInfo.hpp = 0;
        memInfo.maxhp = 0;
        memInfo.mp = 0;
        memInfo.mpp = 0;
        memInfo.maxmp = 0;
        memInfo.tp = 0;
        memInfo.job = '';
        memInfo.level = '';
        memInfo.targeted = false;
        memInfo.serverid = 0;
        memInfo.buffs = nil;
        memInfo.sync = false;
        memInfo.subTargeted = false;
        memInfo.zone = '';
        memInfo.inzone = false;
        memInfo.name = '';
        memInfo.leader = false;
    end

    local partyIndex = math.ceil((memIdx + 1) / partyMaxSize);
    local scale = getScale(partyIndex);
    local showTP = showPartyTP(partyIndex);

    local subTargetActive = GetSubTargetActive();

    -- Get the hp color for bars and text
    local hpNameColor, hpGradient = GetCustomHpColors(memInfo.hpp, gConfig.colorCustomization.partyList);

    local hpBarWidth = settings.hpBarWidth * scale.x;
    local mpBarWidth = settings.mpBarWidth * scale.x;
    local tpBarWidth = settings.tpBarWidth * scale.x;
    local barHeight = settings.barHeight * scale.y;

    local allBarsLengths = hpBarWidth + mpBarWidth + imgui.GetStyle().FramePadding.x + imgui.GetStyle().ItemSpacing.x;
    if (showTP) then
        allBarsLengths = allBarsLengths + tpBarWidth + imgui.GetStyle().FramePadding.x + imgui.GetStyle().ItemSpacing.x;
    end

    local hpStartX, hpStartY = imgui.GetCursorScreenPos();

    -- PRE-CALCULATE dimensions needed for selection box BEFORE drawing anything
    local partyIndex = math.ceil((memIdx + 1) / partyMaxSize);
    local fontSize = settings.fontSizes[partyIndex];

    -- Set font heights to get accurate text measurements
    memberText[memIdx].hp:set_font_height(fontSize);
    memberText[memIdx].name:set_font_height(fontSize);

    -- Calculate text sizes
    memberText[memIdx].name:set_text(tostring(memInfo.name));
    local nameWidth, nameHeight = memberText[memIdx].name:get_text_size();
    memberText[memIdx].hp:set_text(tostring(memInfo.hp));
    local _, hpHeight = memberText[memIdx].hp:get_text_size();

    -- Calculate layout dimensions
    local jobIconSize = settings.iconSize * 1.1 * scale.icon;
    local offsetSize = nameHeight > settings.iconSize and nameHeight or settings.iconSize;

    -- Calculate the actual topmost point of the member (where name/icon are drawn)
    local nameIconAreaHeight = math.max(jobIconSize, nameHeight);

    -- entrySize includes the full member entry: name text + bars + hp text (plus offsets between them)
    -- Note: entrySpacing is spacing BETWEEN members, not part of a single member's height
    local entrySize = nameHeight + settings.nameTextOffsetY + barHeight + settings.hpTextOffsetY + hpHeight;

    -- DRAW SELECTION BOX using GetBackgroundDrawList (renders behind everything with rounded corners)
    if (memInfo.targeted == true) then
        local drawList = imgui.GetBackgroundDrawList();

        local selectionWidth = allBarsLengths + settings.cursorPaddingX1 + settings.cursorPaddingX2;
        local selectionHeight = entrySize + settings.cursorPaddingY1 + settings.cursorPaddingY2;
        -- Anchor selection box to the topmost point: top of name/icon minus padding
        local topOfMember = hpStartY - nameIconAreaHeight - settings.nameTextOffsetY;
        local selectionTL = {hpStartX - settings.cursorPaddingX1, topOfMember - settings.cursorPaddingY1};
        local selectionBR = {selectionTL[1] + selectionWidth, selectionTL[2] + selectionHeight};

        -- Get selection gradient colors from config using helper
        local selectionGradient = GetCustomGradient(gConfig.colorCustomization.partyList, 'selectionGradient') or {'#4da5d9', '#78c0ed'};
        local startColor = HexToImGui(selectionGradient[1]);
        local endColor = HexToImGui(selectionGradient[2]);

        -- Draw gradient effect with multiple rectangles (top to bottom fade)
        local gradientSteps = 8;
        local stepHeight = selectionHeight / gradientSteps;
        for i = 1, gradientSteps do
            -- Calculate interpolation factor (0 at top, 1 at bottom)
            local t = (i - 1) / (gradientSteps - 1);

            -- Interpolate between start and end colors (RGBA float table)
            local r = startColor[1] + (endColor[1] - startColor[1]) * t;
            local g = startColor[2] + (endColor[2] - startColor[2]) * t;
            local b = startColor[3] + (endColor[3] - startColor[3]) * t;

            -- Fade alpha from more opaque at top to more transparent at bottom
            local alpha = 0.35 - t * 0.25; -- 0.35 to 0.10

            local stepColor = imgui.GetColorU32({r, g, b, alpha});

            local stepTL_y = selectionTL[2] + (i - 1) * stepHeight;
            local stepBR_y = stepTL_y + stepHeight;

            -- AddRectFilled with rounded corners (params: min{x,y}, max{x,y}, color, rounding, flags)
            if i == 1 then
                drawList:AddRectFilled({selectionTL[1], stepTL_y}, {selectionBR[1], stepBR_y}, stepColor, 6, 3); -- 6px radius, top corners only
            elseif i == gradientSteps then
                drawList:AddRectFilled({selectionTL[1], stepTL_y}, {selectionBR[1], stepBR_y}, stepColor, 6, 12); -- 6px radius, bottom corners only
            else
                drawList:AddRectFilled({selectionTL[1], stepTL_y}, {selectionBR[1], stepBR_y}, stepColor, 0);
            end
        end

        -- Draw border outline with rounded corners (convert ARGB to ImGui format for real-time updates)
        -- Cache the U32 conversion to avoid redundant bit operations every frame
        local borderColorARGB = gConfig.colorCustomization.partyList.selectionBorderColor;
        if cachedBorderColorARGB ~= borderColorARGB then
            cachedBorderColorARGB = borderColorARGB;
            cachedBorderColorU32 = imgui.GetColorU32(ARGBToImGui(borderColorARGB));
        end
        local borderColor = cachedBorderColorU32;
        drawList:AddRect({selectionTL[1], selectionTL[2]}, {selectionBR[1], selectionBR[2]}, borderColor, 6, 15, 2); -- 6px radius, all corners, 2px thick

        partyTargeted = true;
    end

    -- NOW draw all member content (will appear on top of selection box)

    -- Draw the job icon
    local namePosX = hpStartX;
    local offsetStartY = hpStartY - jobIconSize - settings.nameTextOffsetY;
    imgui.SetCursorScreenPos({namePosX, offsetStartY});
    local jobIcon = statusHandler.GetJobIcon(memInfo.job);
    if (jobIcon ~= nil) then
        namePosX = namePosX + jobIconSize + settings.nameTextOffsetX;
        imgui.Image(jobIcon, {jobIconSize, jobIconSize});
    end
    imgui.SetCursorScreenPos({hpStartX, hpStartY});

    -- Set remaining font heights
    memberText[memIdx].mp:set_font_height(fontSize);
    memberText[memIdx].tp:set_font_height(fontSize);
    memberText[memIdx].distance:set_font_height(fontSize);

    -- Update the hp text (text already set earlier for measurement)
    if not memberTextColorCache[memIdx] then memberTextColorCache[memIdx] = {}; end
    if (memberTextColorCache[memIdx].hp ~= gConfig.colorCustomization.partyList.hpTextColor) then
        memberText[memIdx].hp:set_font_color(gConfig.colorCustomization.partyList.hpTextColor);
        memberTextColorCache[memIdx].hp = gConfig.colorCustomization.partyList.hpTextColor;
    end
    memberText[memIdx].hp:set_position_x(hpStartX + hpBarWidth + settings.hpTextOffsetX);
    memberText[memIdx].hp:set_position_y(hpStartY + barHeight + settings.hpTextOffsetY);

    -- Draw the HP bar
    if (memInfo.inzone) then
        progressbar.ProgressBar({{memInfo.hpp, hpGradient}}, {hpBarWidth, barHeight}, {borderConfig=borderConfig, decorate = gConfig.showPartyListBookends});
    elseif (memInfo.zone == '' or memInfo.zone == nil) then
        imgui.Dummy({allBarsLengths, barHeight});
    else
        imgui.ProgressBar(0, {allBarsLengths, barHeight}, encoding:ShiftJIS_To_UTF8(AshitaCore:GetResourceManager():GetString("zones.names", memInfo.zone), true));
    end

    -- Draw the leader icon
    if (memInfo.leader) then
        draw_circle({hpStartX + settings.dotRadius/2, hpStartY + settings.dotRadius/2}, settings.dotRadius, {1, 1, .5, 1}, settings.dotRadius * 3, true);
    end

    local desiredNameColor = gConfig.colorCustomization.partyList.nameTextColor;
    -- Only call set_color if the color has changed
    if (memberTextColorCache[memIdx].name ~= desiredNameColor) then
        memberText[memIdx].name:set_font_color(desiredNameColor);
        memberTextColorCache[memIdx].name = desiredNameColor;
    end
    memberText[memIdx].name:set_position_x(namePosX);
    memberText[memIdx].name:set_position_y(hpStartY - nameHeight - settings.nameTextOffsetY);

    -- Update the distance text (separate from name)
    local showDistance = false;
    local highlightDistance = false;
    if (gConfig.showPartyListDistance and memInfo.inzone and memInfo.index) then
        local entity = GetEntitySafe()
        if entity ~= nil then
            local distance = math.sqrt(entity:GetDistance(memInfo.index))
            if (distance > 0 and distance <= 50) then
                local distanceText = ('%.1f'):fmt(distance);
                memberText[memIdx].distance:set_text(' - ' .. distanceText);

                local distancePosX = namePosX + nameWidth;
                memberText[memIdx].distance:set_position_x(distancePosX);
                memberText[memIdx].distance:set_position_y(hpStartY - nameHeight - settings.nameTextOffsetY);

                showDistance = true;

                if (gConfig.partyListDistanceHighlight > 0 and distance <= gConfig.partyListDistanceHighlight) then
                    highlightDistance = true;
                end
            end
        end
    end

    -- Update distance visibility and color
    memberText[memIdx].distance:set_visible(showDistance);
    if showDistance then
        local desiredDistanceColor = highlightDistance and 0xFF00FFFF or gConfig.colorCustomization.partyList.nameTextColor;
        if (memberTextColorCache[memIdx].distance ~= desiredDistanceColor) then
            memberText[memIdx].distance:set_font_color(desiredDistanceColor);
            memberTextColorCache[memIdx].distance = desiredDistanceColor;
        end
    end

    if (memInfo.inzone) then
        imgui.SameLine();

        -- Draw the MP bar
        local mpStartX, mpStartY;
        imgui.SetCursorPosX(imgui.GetCursorPosX());
        mpStartX, mpStartY = imgui.GetCursorScreenPos();
        local mpGradient = GetCustomGradient(gConfig.colorCustomization.partyList, 'mpGradient') or {'#9abb5a', '#bfe07d'};
        progressbar.ProgressBar({{memInfo.mpp, mpGradient}}, {mpBarWidth, barHeight}, {borderConfig=borderConfig, decorate = gConfig.showPartyListBookends});

        -- Update the mp text
        -- Only call set_color if the color has changed
        if (memberTextColorCache[memIdx].mp ~= gConfig.colorCustomization.partyList.mpTextColor) then
            memberText[memIdx].mp:set_font_color(gConfig.colorCustomization.partyList.mpTextColor);
            memberTextColorCache[memIdx].mp = gConfig.colorCustomization.partyList.mpTextColor;
        end
        memberText[memIdx].mp:set_position_x(mpStartX + mpBarWidth + settings.mpTextOffsetX);
        memberText[memIdx].mp:set_position_y(mpStartY + barHeight + settings.mpTextOffsetY);
        memberText[memIdx].mp:set_text(tostring(memInfo.mp));

        -- Draw the TP bar
        if (showTP) then
            imgui.SameLine();
            local tpStartX, tpStartY;
            imgui.SetCursorPosX(imgui.GetCursorPosX());
            tpStartX, tpStartY = imgui.GetCursorScreenPos();

            local tpGradient = GetCustomGradient(gConfig.colorCustomization.partyList, 'tpGradient') or {'#3898ce', '#78c4ee'};
            local tpOverlayGradient = {'#0078CC', '#0078CC'};
            local mainPercent;
            local tpOverlay;
            
            if (memInfo.tp >= 1000) then
                mainPercent = (memInfo.tp - 1000) / 2000;
                if (gConfig.partyListFlashTP) then
                    tpOverlay = {{1, tpOverlayGradient}, math.ceil(barHeight * 5/7), 0, { '#3ECE00', 1 }};
                else
                    tpOverlay = {{1, tpOverlayGradient}, math.ceil(barHeight * 2/7), 1};
                end
            else
                mainPercent = memInfo.tp / 1000;
            end
            
            progressbar.ProgressBar({{mainPercent, tpGradient}}, {tpBarWidth, barHeight}, {overlayBar=tpOverlay, borderConfig=borderConfig, decorate = gConfig.showPartyListBookends});

            -- Update the tp text
            local desiredTpColor = (memInfo.tp >= 1000) and gConfig.colorCustomization.partyList.tpFullTextColor or gConfig.colorCustomization.partyList.tpEmptyTextColor;
            -- Only call set_color if the color has changed
            if (memberTextColorCache[memIdx].tp ~= desiredTpColor) then
                memberText[memIdx].tp:set_font_color(desiredTpColor);
                memberTextColorCache[memIdx].tp = desiredTpColor;
            end
            memberText[memIdx].tp:set_position_x(tpStartX + tpBarWidth + settings.tpTextOffsetX);
            memberText[memIdx].tp:set_position_y(tpStartY + barHeight + settings.tpTextOffsetY);
            memberText[memIdx].tp:set_text(tostring(memInfo.tp));
        end

        -- Draw cursor using ImGui (like job icons)
        if ((memInfo.targeted == true and not subTargetActive) or memInfo.subTargeted) then
            local cursorTexture = cursorTextures[gConfig.partyListCursor];
            if (cursorTexture ~= nil) then
                local cursorImage = tonumber(ffi.cast("uint32_t", cursorTexture.image));

                -- Calculate cursor size based on settings.arrowSize
                local cursorWidth = cursorTexture.width * settings.arrowSize;
                local cursorHeight = cursorTexture.height * settings.arrowSize;

                -- Calculate position (left of name text, centered vertically)
                local cursorX = memberText[memIdx].name.settings.position_x - cursorWidth;
                if (jobIcon ~= nil) then
                    cursorX = cursorX - jobIconSize;
                end
                local cursorY = (hpStartY - offsetSize - settings.cursorPaddingY1) + (entrySize/2) - cursorHeight/2;

                -- Determine tint color
                local tintColor;
                if (subTargetActive) then
                    tintColor = imgui.GetColorU32(settings.subtargetArrowTint);
                else
                    tintColor = IM_COL32_WHITE;
                end

                -- Draw using foreground draw list
                local draw_list = imgui.GetForegroundDrawList();
                draw_list:AddImage(
                    cursorImage,
                    {cursorX, cursorY},
                    {cursorX + cursorWidth, cursorY + cursorHeight},
                    {0, 0}, {1, 1},
                    tintColor
                );

                partySubTargeted = true;
            end
        end

        -- Draw the different party list buff / debuff themes
        if (partyIndex == 1 and memInfo.buffs ~= nil and #memInfo.buffs > 0) then
            if (gConfig.partyListStatusTheme == 0 or gConfig.partyListStatusTheme == 1) then
                local buffs = {};
                local debuffs = {};
                for i = 0, #memInfo.buffs do
                    if (buffTable.IsBuff(memInfo.buffs[i])) then
                        table.insert(buffs, memInfo.buffs[i]);
                    else
                        table.insert(debuffs, memInfo.buffs[i]);
                    end
                end

                if (buffs ~= nil and #buffs > 0) then
                    if (gConfig.partyListStatusTheme == 0 and buffWindowX[memIdx] ~= nil) then
                        imgui.SetNextWindowPos({hpStartX - buffWindowX[memIdx] - settings.buffOffset , hpStartY - settings.iconSize*1.2});
                    elseif (gConfig.partyListStatusTheme == 1 and fullMenuWidth[partyIndex] ~= nil) then
                        local thisPosX, _ = imgui.GetWindowPos();
                        imgui.SetNextWindowPos({ thisPosX + fullMenuWidth[partyIndex], hpStartY - settings.iconSize * 1.2 });
                    end
                    if (imgui.Begin('PlayerBuffs'..memIdx, true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoSavedSettings))) then
                        imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {3, 1});
                        DrawStatusIcons(buffs, settings.iconSize, 32, 1, true);
                        imgui.PopStyleVar(1);
                    end
                    local buffWindowSizeX, _ = imgui.GetWindowSize();
                    buffWindowX[memIdx] = buffWindowSizeX;
    
                    imgui.End();
                end

                if (debuffs ~= nil and #debuffs > 0) then
                    if (gConfig.partyListStatusTheme == 0 and debuffWindowX[memIdx] ~= nil) then
                        imgui.SetNextWindowPos({hpStartX - debuffWindowX[memIdx] - settings.buffOffset , hpStartY});
                    elseif (gConfig.partyListStatusTheme == 1 and fullMenuWidth[partyIndex] ~= nil) then
                        local thisPosX, _ = imgui.GetWindowPos();
                        imgui.SetNextWindowPos({ thisPosX + fullMenuWidth[partyIndex], hpStartY });
                    end
                    if (imgui.Begin('PlayerDebuffs'..memIdx, true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoSavedSettings))) then
                        imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {3, 1});
                        DrawStatusIcons(debuffs, settings.iconSize, 32, 1, true);
                        imgui.PopStyleVar(1);
                    end
                    local buffWindowSizeX, buffWindowSizeY = imgui.GetWindowSize();
                    debuffWindowX[memIdx] = buffWindowSizeX;
                    imgui.End();
                end
            elseif (gConfig.partyListStatusTheme == 2) then
                -- Draw FFXIV theme
                local resetX, resetY = imgui.GetCursorScreenPos();
                imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {0, 0} );
                imgui.SetNextWindowPos({mpStartX, mpStartY - settings.iconSize - settings.xivBuffOffsetY})
                if (imgui.Begin('XIVStatus'..memIdx, true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoSavedSettings))) then
                    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {0, 0});
                    DrawStatusIcons(memInfo.buffs, settings.iconSize, 32, 1);
                    imgui.PopStyleVar(1);
                end
                imgui.PopStyleVar(1);
                imgui.End();
                imgui.SetCursorScreenPos({resetX, resetY});
            elseif (gConfig.partyListStatusTheme == 3) then
                if (buffWindowX[memIdx] ~= nil) then
                    imgui.SetNextWindowPos({hpStartX - buffWindowX[memIdx] - settings.buffOffset , memberText[memIdx].name.settings.position_y - settings.iconSize/2});
                end
                if (imgui.Begin('PlayerBuffs'..memIdx, true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoSavedSettings))) then
                    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {0, 3});
                    DrawStatusIcons(memInfo.buffs, settings.iconSize, 7, 3);
                    imgui.PopStyleVar(1);
                end
                local buffWindowSizeX, _ = imgui.GetWindowSize();
                buffWindowX[memIdx] = buffWindowSizeX;

                imgui.End();
            end
        end
    end

    if (memInfo.sync) then
        draw_circle({hpStartX + settings.dotRadius/2, hpStartY + barHeight}, settings.dotRadius, {.5, .5, 1, 1}, settings.dotRadius * 3, true);
    end

    memberText[memIdx].hp:set_visible(memInfo.inzone);
    memberText[memIdx].mp:set_visible(memInfo.inzone);
    memberText[memIdx].tp:set_visible(memInfo.inzone and showTP);

    -- Reserve space in ImGui layout for the text below bars (which is rendered with absolute positioning)
    -- Match the selection box calculation: hpTextOffsetY + hpHeight (no entrySpacing since selection box subtracts it)
    -- Don't include cursorPadding here - that's only for the selection box visual padding
    local bottomSpacing = settings.hpTextOffsetY + hpHeight;
    imgui.Dummy({0, bottomSpacing});

    -- Add spacing between members: fixed base spacing + user-customizable entrySpacing (if not last visible member)
    if (not isLastVisibleMember) then
        local BASE_MEMBER_SPACING = 6; -- Fixed 6px spacing between members
        imgui.Dummy({0, BASE_MEMBER_SPACING + settings.entrySpacing[partyIndex]});
    end
end

partyList.DrawWindow = function(settings)

    -- Obtain the player entity..
    local party = GetPartySafe();
    local player = GetPlayerSafe();

	if (party == nil or player == nil or player.isZoning or player:GetMainJob() == 0) then
		UpdateTextVisibility(false);
		return;
	end

    partyTargeted = false;
    partySubTargeted = false;

    -- Main party window
    partyList.DrawPartyWindow(settings, party, 1);

    -- Alliance party windows
    if (gConfig.partyListAlliance) then
        partyList.DrawPartyWindow(settings, party, 2);
        partyList.DrawPartyWindow(settings, party, 3);
    else
        UpdateTextVisibility(false, 2);
        UpdateTextVisibility(false, 3);
    end

    -- Cursor is now drawn directly in DrawMember using ImGui, no visibility flag needed
end

partyList.DrawPartyWindow = function(settings, party, partyIndex)
    local firstPlayerIndex = (partyIndex - 1) * partyMaxSize;
    local lastPlayerIndex = firstPlayerIndex + partyMaxSize - 1;

    -- Get the party size by checking active members
    local partyMemberCount = 0;
    if (showConfig[1] and gConfig.partyListPreview) then
        partyMemberCount = partyMaxSize;
    else
        for i = firstPlayerIndex, lastPlayerIndex do
            if (party:GetMemberIsActive(i) ~= 0) then
                partyMemberCount = partyMemberCount + 1
            else
                break
            end
        end
    end

    if (partyIndex == 1 and not gConfig.showPartyListWhenSolo and partyMemberCount <= 1) then
		UpdateTextVisibility(false);
        return;
	end

    if(partyIndex > 1 and partyMemberCount == 0) then
        UpdateTextVisibility(false, partyIndex);
        return;
    end

    local backgroundPrim = partyWindowPrim[partyIndex].background;

    -- Determine title text based on party index and member count
    local titleString;
    if (partyIndex == 1) then
        titleString = partyMemberCount == 1 and "Solo" or "Party A";
    elseif (partyIndex == 2) then
        titleString = "Party B";
    else
        titleString = "Party C";
    end

    -- Update title text
    if (titleText[partyIndex] ~= nil) then
        titleText[partyIndex]:set_text(titleString);
    end

    local imguiPosX, imguiPosY;

    local windowFlags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoBringToFrontOnFocus);
    if (gConfig.lockPositions) then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
    end

    local windowName = 'PartyList';
    if (partyIndex > 1) then
        windowName = windowName .. partyIndex
    end

    local scale = getScale(partyIndex);
    local iconSize = 0; --settings.iconSize * scale.icon;

    -- Remove all padding and start our window
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {0,0});
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { settings.barSpacing * scale.x, 0 });
    if (imgui.Begin(windowName, true, windowFlags)) then
        imguiPosX, imguiPosY = imgui.GetWindowPos();

        local nameWidth, nameHeight = memberText[(partyIndex - 1) * 6].name:get_text_size();
        local offsetSize = nameHeight > iconSize and nameHeight or iconSize;
        imgui.Dummy({0, settings.nameTextOffsetY + offsetSize});

        UpdateTextVisibility(true, partyIndex);

        -- Calculate which is the last member that will be drawn
        local lastVisibleMemberIdx = firstPlayerIndex;
        for i = firstPlayerIndex, lastPlayerIndex do
            local relIndex = i - firstPlayerIndex
            if ((partyIndex == 1 and settings.expandHeight) or relIndex < partyMemberCount or relIndex < settings.minRows) then
                lastVisibleMemberIdx = i;
            end
        end

        -- Draw all members
        for i = firstPlayerIndex, lastPlayerIndex do
            local relIndex = i - firstPlayerIndex
            if ((partyIndex == 1 and settings.expandHeight) or relIndex < partyMemberCount or relIndex < settings.minRows) then
                DrawMember(i, settings, i == lastVisibleMemberIdx);
            else
                UpdateTextVisibilityByMember(i, false);
            end
        end
    end

    local menuWidth, menuHeight = imgui.GetWindowSize();

    fullMenuWidth[partyIndex] = menuWidth;
    fullMenuHeight[partyIndex] = menuHeight;

    -- if (fullMenuWidth[partyIndex] ~= nil and fullMenuHeight[partyIndex] ~= nil) then
        local bgWidth = fullMenuWidth[partyIndex] + (settings.bgPadding * 2);
        local bgHeight = fullMenuHeight[partyIndex] + (settings.bgPaddingY * 2);

        -- Apply colors from colorCustomization every frame (for real-time updates)
        local bgColor = gConfig.colorCustomization.partyList.bgColor;
        local borderColor = gConfig.colorCustomization.partyList.borderColor;

        backgroundPrim.bg.visible = backgroundPrim.bg.exists;
        backgroundPrim.bg.position_x = imguiPosX - settings.bgPadding;
        backgroundPrim.bg.position_y = imguiPosY - settings.bgPaddingY;
        backgroundPrim.bg.width = bgWidth / gConfig.partyListBgScale;
        backgroundPrim.bg.height = bgHeight / gConfig.partyListBgScale;
        backgroundPrim.bg.color = bgColor;

        backgroundPrim.br.visible = backgroundPrim.br.exists;
        backgroundPrim.br.position_x = backgroundPrim.bg.position_x + bgWidth - settings.borderSize + settings.bgOffset;
        backgroundPrim.br.position_y = backgroundPrim.bg.position_y + bgHeight - settings.borderSize + settings.bgOffset;
        backgroundPrim.br.width = settings.borderSize;
        backgroundPrim.br.height = settings.borderSize;
        backgroundPrim.br.color = borderColor;

        backgroundPrim.tr.visible = backgroundPrim.tr.exists;
        backgroundPrim.tr.position_x = backgroundPrim.br.position_x;
        backgroundPrim.tr.position_y = backgroundPrim.bg.position_y - settings.bgOffset;
        backgroundPrim.tr.width = settings.borderSize;
        backgroundPrim.tr.height = backgroundPrim.br.position_y - backgroundPrim.tr.position_y;
        backgroundPrim.tr.color = borderColor;

        backgroundPrim.tl.visible = backgroundPrim.tl.exists;
        backgroundPrim.tl.position_x = backgroundPrim.bg.position_x - settings.bgOffset;
        backgroundPrim.tl.position_y = backgroundPrim.bg.position_y - settings.bgOffset;
        backgroundPrim.tl.width = backgroundPrim.tr.position_x - backgroundPrim.tl.position_x;
        backgroundPrim.tl.height = backgroundPrim.br.position_y - backgroundPrim.tl.position_y;
        backgroundPrim.tl.color = borderColor;

        backgroundPrim.bl.visible = backgroundPrim.bl.exists;
        backgroundPrim.bl.position_x = backgroundPrim.tl.position_x;
        backgroundPrim.bl.position_y = backgroundPrim.bg.position_y + bgHeight - settings.borderSize + settings.bgOffset;
        backgroundPrim.bl.width = backgroundPrim.br.position_x - backgroundPrim.bl.position_x;
        backgroundPrim.bl.height = settings.borderSize;
        backgroundPrim.bl.color = borderColor;

        -- Position title text centered above the window
        if (titleText[partyIndex] ~= nil) then
            titleText[partyIndex]:set_visible(gConfig.showPartyListTitle);
            local titleWidth, titleHeight = titleText[partyIndex]:get_text_size();
            local titlePosX = imguiPosX + math.floor((bgWidth / 2) - (titleWidth / 2));
            local titlePosY = imguiPosY - math.floor(titleHeight);
            titleText[partyIndex]:set_position_x(titlePosX);
            titleText[partyIndex]:set_position_y(titlePosY);
        end
    -- end

	imgui.End();
    imgui.PopStyleVar(2);

    if (settings.alignBottom and imguiPosX ~= nil) then
        -- Migrate old settings
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
            -- Move window if size changed
            if (menuHeight ~= partyListState.height) then
                local newPosY = partyListState.y + partyListState.height - menuHeight;
                imguiPosY = newPosY; --imguiPosY + (partyListState.height - menuHeight]);
                imgui.SetWindowPos(windowName, { imguiPosX, imguiPosY });
            end
        end

        -- Update if the state changed
        if (partyListState == nil or
                imguiPosX ~= partyListState.x or imguiPosY ~= partyListState.y or
                menuWidth ~= partyListState.width or menuHeight ~= partyListState.height) then
            gConfig.partyListState[partyIndex] = {
                x = imguiPosX,
                y = imguiPosY,
                width = menuWidth,
                height = menuHeight,
            };
            ashita_settings.save();
        end
    end
end

partyList.Initialize = function(settings)
    -- Cache the initial font sizes
    cachedFontSizes = {
		settings.fontSizes[1],
		settings.fontSizes[2],
		settings.fontSizes[3],
	};

	-- Cache the initial font family, flags, and outline width
	cachedFontFamily = settings.name_font_settings.font_family or '';
	cachedFontFlags = settings.name_font_settings.font_flags or 0;
	cachedOutlineWidth = settings.name_font_settings.outline_width or 2;

    -- Initialize all our font objects we need
    for i = 0, memberTextCount-1 do
        local partyIndex = math.ceil((i + 1) / partyMaxSize);
		local fontSize = settings.fontSizes[partyIndex];

        local name_font_settings = deep_copy_table(settings.name_font_settings);
        local hp_font_settings = deep_copy_table(settings.hp_font_settings);
        local mp_font_settings = deep_copy_table(settings.mp_font_settings);
        local tp_font_settings = deep_copy_table(settings.tp_font_settings);
        local distance_font_settings = deep_copy_table(settings.name_font_settings);

        name_font_settings.font_height = math.max(fontSize, 6);
        hp_font_settings.font_height = math.max(fontSize, 6);
        mp_font_settings.font_height = math.max(fontSize, 6);
        tp_font_settings.font_height = math.max(fontSize, 6);
        distance_font_settings.font_height = math.max(fontSize, 6);

        memberText[i] = {};
        -- Use FontManager for cleaner font creation
        memberText[i].name = FontManager.create(name_font_settings);
        memberText[i].hp = FontManager.create(hp_font_settings);
        memberText[i].mp = FontManager.create(mp_font_settings);
        memberText[i].tp = FontManager.create(tp_font_settings);
        memberText[i].distance = FontManager.create(distance_font_settings);
    end

    -- Initialize title fonts for each party (3 parties)
    for i = 1, 3 do
        local title_font_settings = deep_copy_table(settings.title_font_settings);
        -- Font height is already set in the settings, no need to override
        -- Use FontManager for cleaner font creation
        titleText[i] = FontManager.create(title_font_settings);
    end

    -- Initialize images
    loadedBg = nil;

    for i = 1, 3 do
        local backgroundPrim = {};

        for _, k in ipairs(bgImageKeys) do
            backgroundPrim[k] = primitives:new(settings.prim_data);
            backgroundPrim[k].visible = false;
            backgroundPrim[k].can_focus = false;
            backgroundPrim[k].exists = false;
        end

        partyWindowPrim[i].background = backgroundPrim;
    end

    -- Load cursor textures (handled in UpdateVisuals)
    partyList.UpdateVisuals(settings);
end

partyList.UpdateVisuals = function(settings)
    -- Check if font family, flags (weight), or outline width changed - if so, recreate ALL fonts
    local fontFamilyChanged = false;
    local fontFlagsChanged = false;
    local outlineWidthChanged = false;

    if settings.name_font_settings.font_family ~= cachedFontFamily then
        fontFamilyChanged = true;
        cachedFontFamily = settings.name_font_settings.font_family;
    end

    if settings.name_font_settings.font_flags ~= cachedFontFlags then
        fontFlagsChanged = true;
        cachedFontFlags = settings.name_font_settings.font_flags;
    end

    if settings.name_font_settings.outline_width ~= cachedOutlineWidth then
        outlineWidthChanged = true;
        cachedOutlineWidth = settings.name_font_settings.outline_width;
    end

    -- Check which party font sizes changed
    local sizesChanged = {false, false, false};
    for partyIndex = 1, 3 do
        if settings.fontSizes[partyIndex] ~= cachedFontSizes[partyIndex] then
            sizesChanged[partyIndex] = true;
            cachedFontSizes[partyIndex] = settings.fontSizes[partyIndex];
        end
    end

    -- If font family, weight, or outline width changed, mark all parties as needing recreation
    if fontFamilyChanged or fontFlagsChanged or outlineWidthChanged then
        sizesChanged = {true, true, true};
    end

    -- Only recreate fonts for members of parties whose size changed
    for i = 0, memberTextCount-1 do
        local partyIndex = math.ceil((i + 1) / partyMaxSize);

        -- Skip if this party's size didn't change
        if not sizesChanged[partyIndex] then
            goto continue
        end

		local fontSize = settings.fontSizes[partyIndex];

        -- Create font settings with proper height
        local name_font_settings = deep_copy_table(settings.name_font_settings);
        local hp_font_settings = deep_copy_table(settings.hp_font_settings);
        local mp_font_settings = deep_copy_table(settings.mp_font_settings);
        local tp_font_settings = deep_copy_table(settings.tp_font_settings);
        local distance_font_settings = deep_copy_table(settings.name_font_settings);

        name_font_settings.font_height = math.max(fontSize, 6);
        hp_font_settings.font_height = math.max(fontSize, 6);
        mp_font_settings.font_height = math.max(fontSize, 6);
        tp_font_settings.font_height = math.max(fontSize, 6);
        distance_font_settings.font_height = math.max(fontSize, 6);

        -- Use FontManager for cleaner font recreation
        if (memberText[i] ~= nil) then
            memberText[i].name = FontManager.recreate(memberText[i].name, name_font_settings);
            memberText[i].hp = FontManager.recreate(memberText[i].hp, hp_font_settings);
            memberText[i].mp = FontManager.recreate(memberText[i].mp, mp_font_settings);
            memberText[i].tp = FontManager.recreate(memberText[i].tp, tp_font_settings);
            memberText[i].distance = FontManager.recreate(memberText[i].distance, distance_font_settings);
        end

        ::continue::
    end

    -- Reset cached colors for parties that changed
    for partyIndex = 1, 3 do
        if sizesChanged[partyIndex] then
            for i = (partyIndex - 1) * partyMaxSize, (partyIndex * partyMaxSize) - 1 do
                memberTextColorCache[i] = nil;
            end
        end
    end

    -- Update images
    local bgChanged = gConfig.partyListBackgroundName ~= loadedBg;
    loadedBg = gConfig.partyListBackgroundName;

    for i = 1, 3 do
        local backgroundPrim = partyWindowPrim[i].background;

        for _, k in ipairs(bgImageKeys) do
            local file_name = string.format('%s-%s.png', gConfig.partyListBackgroundName, k);
            -- Note: colors are now applied every frame in DrawPartyWindow for real-time updates
            if (bgChanged) then
                -- Keep width/height to prevent flicker when switching to new texture
                local width, height = backgroundPrim[k].width, backgroundPrim[k].height;
                local filepath = string.format('%s/assets/backgrounds/%s', addon.path, file_name);
                backgroundPrim[k].texture = filepath;
                backgroundPrim[k].width, backgroundPrim[k].height = width, height;

                backgroundPrim[k].exists = ashita.fs.exists(filepath);
            end
            -- Only scale the main background, not the borders
            if k == 'bg' then
                backgroundPrim[k].scale_x = gConfig.partyListBgScale;
                backgroundPrim[k].scale_y = gConfig.partyListBgScale;
            else
                backgroundPrim[k].scale_x = 1.0;
                backgroundPrim[k].scale_y = 1.0;
            end
        end
    end

    -- Load cursor texture (like job icons)
    if (gConfig.partyListCursor ~= currentCursorName) then
        -- Cursor changed, clear cache and load new texture
        cursorTextures = T{};
        currentCursorName = gConfig.partyListCursor;

        if (gConfig.partyListCursor ~= nil and gConfig.partyListCursor ~= '') then
            local cursorTexture = LoadTexture(string.format('cursors/%s', gConfig.partyListCursor:gsub('%.png$', '')));
            if (cursorTexture ~= nil) then
                -- Query actual texture dimensions using d3d8 library's interface
                local texture_ptr = ffi.cast('IDirect3DTexture8*', cursorTexture.image);
                local res, desc = texture_ptr:GetLevelDesc(0);

                if (desc ~= nil) then
                    cursorTexture.width = desc.Width;
                    cursorTexture.height = desc.Height;
                else
                    -- Fallback to reasonable default if query fails
                    cursorTexture.width = 32;
                    cursorTexture.height = 32;
                    print(string.format('[HXUI] Warning: Failed to query cursor texture dimensions for %s, using default 32x32', gConfig.partyListCursor));
                end

                cursorTextures[gConfig.partyListCursor] = cursorTexture;
            end
        end
    end
end

partyList.SetHidden = function(hidden)
	if (hidden == true) then
        UpdateTextVisibility(false);
        -- Cursor is now drawn directly in DrawMember, no visibility flag needed
	end
end

partyList.HandleZonePacket = function(e)
    statusHandler.clear_cache();
end

partyList.Cleanup = function()
	-- Use FontManager for cleaner font destruction
	for i = 0, memberTextCount - 1 do
		if (memberText[i] ~= nil) then
			memberText[i].name = FontManager.destroy(memberText[i].name);
			memberText[i].hp = FontManager.destroy(memberText[i].hp);
			memberText[i].mp = FontManager.destroy(memberText[i].mp);
			memberText[i].tp = FontManager.destroy(memberText[i].tp);
			memberText[i].distance = FontManager.destroy(memberText[i].distance);
		end
	end

	-- Destroy title text font objects
	for i = 1, 3 do
		titleText[i] = FontManager.destroy(titleText[i]);
	end

	-- Clear cursor texture cache (textures are GC'd automatically via gc_safe_release)
	cursorTextures = T{};
	currentCursorName = nil;

	-- Destroy party window primitives
	for i = 1, 3 do
		if (partyWindowPrim[i] ~= nil) then
			if (partyWindowPrim[i].background ~= nil) then
				for _, k in ipairs(bgImageKeys) do
					if (partyWindowPrim[i].background[k] ~= nil) then
						partyWindowPrim[i].background[k]:destroy();
					end
				end
			end
		end
	end

	-- Clear tables
	memberText = {};
	titleText = {};
	partyWindowPrim = {{background = {}}, {background = {}}, {background = {}}};
end

return partyList;