require('common');
local imgui = require('imgui');
local fonts = require('fonts');
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

local selectionPrim;
local arrowPrim;
local partyTargeted;
local partySubTargeted;
local memberText = {};
local partyMaxSize = 6;
local memberTextCount = partyMaxSize * 3;

-- Cache last set colors to avoid expensive SetColor() calls every frame
local memberTextColorCache = {};

local borderConfig = {1, '#243e58'};

local bgImageKeys = { 'bg', 'tl', 'tr', 'br', 'bl' };
local bgTitleAtlasItemCount = 4;
local bgTitleItemHeight;
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

    memberText[memIdx].hp:SetVisible(visible);
    memberText[memIdx].mp:SetVisible(visible);
    memberText[memIdx].tp:SetVisible(visible);
    memberText[memIdx].name:SetVisible(visible);
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
            partyWindowPrim[i].bgTitle.visible = visible and gConfig.showPartyListTitle;
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

    local party = AshitaCore:GetMemoryManager():GetParty();
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if (player == nil or party == nil or party:GetMemberIsActive(memIdx) == 0) then
        return nil;
    end

    local playerTarget = AshitaCore:GetMemoryManager():GetTarget();

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

local function DrawMember(memIdx, settings)

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
    local nameSize = SIZE.new();
    local hpSize = SIZE.new();
    memberText[memIdx].name:GetTextSize(nameSize);
    memberText[memIdx].hp:GetTextSize(hpSize);

    -- Get the hp color for bars and text
    local hpNameColor, hpGradient = GetCustomHpColors(memInfo.hpp, gConfig.colorCustomization.partyList);

    local bgGradientOverride = {'#000813', '#000813'};

    local hpBarWidth = settings.hpBarWidth * scale.x;
    local mpBarWidth = settings.mpBarWidth * scale.x;
    local tpBarWidth = settings.tpBarWidth * scale.x;
    local barHeight = settings.barHeight * scale.y;

    local allBarsLengths = hpBarWidth + mpBarWidth + imgui.GetStyle().FramePadding.x + imgui.GetStyle().ItemSpacing.x;
    if (showTP) then
        allBarsLengths = allBarsLengths + tpBarWidth + imgui.GetStyle().FramePadding.x + imgui.GetStyle().ItemSpacing.x;
    end

    local hpStartX, hpStartY = imgui.GetCursorScreenPos();

    -- Draw the job icon before we draw anything else
    local namePosX = hpStartX;
    local jobIconSize = settings.iconSize * 1.1 * scale.icon;
    local offsetStartY = hpStartY - jobIconSize - settings.nameTextOffsetY;
    imgui.SetCursorScreenPos({namePosX, offsetStartY});
    local jobIcon = statusHandler.GetJobIcon(memInfo.job);
    if (jobIcon ~= nil) then
        namePosX = namePosX + jobIconSize + settings.nameTextOffsetX;
        imgui.Image(jobIcon, {jobIconSize, jobIconSize});
    end
    imgui.SetCursorScreenPos({hpStartX, hpStartY});

    -- Update the hp text
    -- Only call SetColor if the color has changed (expensive operation for GDI fonts)
    if not memberTextColorCache[memIdx] then memberTextColorCache[memIdx] = {}; end
    if (memberTextColorCache[memIdx].hp ~= gConfig.colorCustomization.partyList.hpTextColor) then
        memberText[memIdx].hp:SetColor(gConfig.colorCustomization.partyList.hpTextColor);
        memberTextColorCache[memIdx].hp = gConfig.colorCustomization.partyList.hpTextColor;
    end
    memberText[memIdx].hp:SetPositionX(hpStartX + hpBarWidth + settings.hpTextOffsetX);
    memberText[memIdx].hp:SetPositionY(hpStartY + barHeight + settings.hpTextOffsetY);
    memberText[memIdx].hp:SetText(tostring(memInfo.hp));

    -- Draw the HP bar
    if (memInfo.inzone) then
        progressbar.ProgressBar({{memInfo.hpp, hpGradient}}, {hpBarWidth, barHeight}, {borderConfig=borderConfig, backgroundGradientOverride=bgGradientOverride, decorate = gConfig.showPartyListBookends});
    elseif (memInfo.zone == '' or memInfo.zone == nil) then
        imgui.Dummy({allBarsLengths, barHeight});
    else
        imgui.ProgressBar(0, {allBarsLengths, barHeight}, encoding:ShiftJIS_To_UTF8(AshitaCore:GetResourceManager():GetString("zones.names", memInfo.zone), true));
    end

    -- Draw the leader icon
    if (memInfo.leader) then
        draw_circle({hpStartX + settings.dotRadius/2, hpStartY + settings.dotRadius/2}, settings.dotRadius, {1, 1, .5, 1}, settings.dotRadius * 3, true);
    end

    -- Update the name text
    local distanceText = ''
    local highlightDistance = false
    if (gConfig.showPartyListDistance) then
        if (memInfo.inzone and memInfo.index) then
            local entity = AshitaCore:GetMemoryManager():GetEntity()
            local distance = math.sqrt(entity:GetDistance(memInfo.index))
            if (distance > 0 and distance <= 50) then
                local percentText  = ('%.1f'):fmt(distance);
                distanceText = ' - ' .. percentText

                if (gConfig.partyListDistanceHighlight > 0 and distance <= gConfig.partyListDistanceHighlight) then
                    highlightDistance = true
                end
            end
        end
    end

    local desiredNameColor = highlightDistance and 0xFF00FFFF or gConfig.colorCustomization.partyList.nameTextColor;
    -- Only call SetColor if the color has changed
    if (memberTextColorCache[memIdx].name ~= desiredNameColor) then
        memberText[memIdx].name:SetColor(desiredNameColor);
        memberTextColorCache[memIdx].name = desiredNameColor;
    end
    memberText[memIdx].name:SetPositionX(namePosX);
    memberText[memIdx].name:SetPositionY(hpStartY - nameSize.cy - settings.nameTextOffsetY);
    memberText[memIdx].name:SetText(tostring(memInfo.name) .. distanceText);

    local nameSize = SIZE.new();
    memberText[memIdx].name:GetTextSize(nameSize);
    local offsetSize = nameSize.cy > settings.iconSize and nameSize.cy or settings.iconSize;

    if (memInfo.inzone) then
        imgui.SameLine();

        -- Draw the MP bar
        local mpStartX, mpStartY;
        imgui.SetCursorPosX(imgui.GetCursorPosX());
        mpStartX, mpStartY = imgui.GetCursorScreenPos();
        local mpGradient = GetCustomGradient(gConfig.colorCustomization.partyList, 'mpGradient') or {'#9abb5a', '#bfe07d'};
        progressbar.ProgressBar({{memInfo.mpp, mpGradient}}, {mpBarWidth, barHeight}, {borderConfig=borderConfig, backgroundGradientOverride=bgGradientOverride, decorate = gConfig.showPartyListBookends});

        -- Update the mp text
        -- Only call SetColor if the color has changed
        if (memberTextColorCache[memIdx].mp ~= gConfig.colorCustomization.partyList.mpTextColor) then
            memberText[memIdx].mp:SetColor(gConfig.colorCustomization.partyList.mpTextColor);
            memberTextColorCache[memIdx].mp = gConfig.colorCustomization.partyList.mpTextColor;
        end
        memberText[memIdx].mp:SetPositionX(mpStartX + mpBarWidth + settings.mpTextOffsetX);
        memberText[memIdx].mp:SetPositionY(mpStartY + barHeight + settings.mpTextOffsetY);
        memberText[memIdx].mp:SetText(tostring(memInfo.mp));

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
            
            progressbar.ProgressBar({{mainPercent, tpGradient}}, {tpBarWidth, barHeight}, {overlayBar=tpOverlay, borderConfig=borderConfig, backgroundGradientOverride=bgGradientOverride, decorate = gConfig.showPartyListBookends});

            -- Update the tp text
            local desiredTpColor = (memInfo.tp >= 1000) and gConfig.colorCustomization.partyList.tpFullTextColor or gConfig.colorCustomization.partyList.tpEmptyTextColor;
            -- Only call SetColor if the color has changed
            if (memberTextColorCache[memIdx].tp ~= desiredTpColor) then
                memberText[memIdx].tp:SetColor(desiredTpColor);
                memberTextColorCache[memIdx].tp = desiredTpColor;
            end
            memberText[memIdx].tp:SetPositionX(tpStartX + tpBarWidth + settings.tpTextOffsetX);
            memberText[memIdx].tp:SetPositionY(tpStartY + barHeight + settings.tpTextOffsetY);
            memberText[memIdx].tp:SetText(tostring(memInfo.tp));
        end

        -- Draw targeted
        local entrySize = hpSize.cy + offsetSize + settings.hpTextOffsetY + barHeight + settings.cursorPaddingY1 + settings.cursorPaddingY2;
        if (memInfo.targeted == true) then
            selectionPrim.visible = true;
            selectionPrim.position_x = hpStartX - settings.cursorPaddingX1;
            selectionPrim.position_y = hpStartY - offsetSize - settings.cursorPaddingY1;
            selectionPrim.scale_x = (allBarsLengths + settings.cursorPaddingX1 + settings.cursorPaddingX2) / 346;
            selectionPrim.scale_y = entrySize / 108;
            partyTargeted = true;
        end

        -- Draw subtargeted
        if ((memInfo.targeted == true and not subTargetActive) or memInfo.subTargeted) then
            arrowPrim.visible = true;
            local newArrowX =  memberText[memIdx].name:GetPositionX() - arrowPrim:GetWidth();
            if (jobIcon ~= nil) then
                newArrowX = newArrowX - jobIconSize;
            end
            arrowPrim.position_x = newArrowX;
            arrowPrim.position_y = (hpStartY - offsetSize - settings.cursorPaddingY1) + (entrySize/2) - arrowPrim:GetHeight()/2;
            arrowPrim.scale_x = settings.arrowSize;
            arrowPrim.scale_y = settings.arrowSize;
            if (subTargetActive) then
                arrowPrim.color = settings.subtargetArrowTint;
            else
                arrowPrim.color = 0xFFFFFFFF;
            end
            partySubTargeted = true;
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
                    imgui.SetNextWindowPos({hpStartX - buffWindowX[memIdx] - settings.buffOffset , memberText[memIdx].name:GetPositionY() - settings.iconSize/2});
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

    memberText[memIdx].hp:SetVisible(memInfo.inzone);
    memberText[memIdx].mp:SetVisible(memInfo.inzone);
    memberText[memIdx].tp:SetVisible(memInfo.inzone and showTP);

    --if (memInfo.inzone) then
        imgui.Dummy({0, settings.entrySpacing[partyIndex] + hpSize.cy + settings.hpTextOffsetY + settings.nameTextOffsetY});
    --else
    --    imgui.Dummy({0, settings.entrySpacing[partyIndex] + settings.nameTextOffsetY});
    --end

    local lastPlayerIndex = (partyIndex * 6) - 1;
    if (memIdx + 1 <= lastPlayerIndex) then
        imgui.Dummy({0, offsetSize});
    end
end

partyList.DrawWindow = function(settings)

    -- Obtain the player entity..
    local party = AshitaCore:GetMemoryManager():GetParty();
    local player = AshitaCore:GetMemoryManager():GetPlayer();

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

    selectionPrim.visible = partyTargeted;
    arrowPrim.visible = partySubTargeted;
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

    local bgTitlePrim = partyWindowPrim[partyIndex].bgTitle;
    local backgroundPrim = partyWindowPrim[partyIndex].background;

    -- Graphic has multiple titles
    -- 0 = Solo
    -- bgTitleItemHeight = Party
    -- bgTitleItemHeight*2 = Party B
    -- bgTitleItemHeight*3 = Party C
    if (partyIndex == 1) then
        bgTitlePrim.texture_offset_y = partyMemberCount == 1 and 0 or bgTitleItemHeight;
    else
        bgTitlePrim.texture_offset_y = bgTitleItemHeight * partyIndex
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

        local nameSize = SIZE.new();
        memberText[(partyIndex - 1) * 6].name:GetTextSize(nameSize);
        local offsetSize = nameSize.cy > iconSize and nameSize.cy or iconSize;
        imgui.Dummy({0, settings.nameTextOffsetY + offsetSize});

        UpdateTextVisibility(true, partyIndex);

        for i = firstPlayerIndex, lastPlayerIndex do
            local relIndex = i - firstPlayerIndex
            if ((partyIndex == 1 and settings.expandHeight) or relIndex < partyMemberCount or relIndex < settings.minRows) then
                DrawMember(i, settings);
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
        local bgHeight = fullMenuHeight[partyIndex];
        if (partyIndex > 1) then
            bgHeight = bgHeight + (settings.bgPadding * 2)
        end

        backgroundPrim.bg.visible = backgroundPrim.bg.exists;
        backgroundPrim.bg.position_x = imguiPosX - settings.bgPadding;
        backgroundPrim.bg.position_y = imguiPosY - settings.bgPadding;
        backgroundPrim.bg.width = math.ceil(bgWidth / gConfig.partyListBgScale);
        backgroundPrim.bg.height = math.ceil(bgHeight / gConfig.partyListBgScale);

        backgroundPrim.br.visible = backgroundPrim.br.exists;
        backgroundPrim.br.position_x = backgroundPrim.bg.position_x + bgWidth - math.floor((settings.borderSize * gConfig.partyListBgScale) - (settings.bgOffset * gConfig.partyListBgScale));
        backgroundPrim.br.position_y = backgroundPrim.bg.position_y + bgHeight - math.floor((settings.borderSize * gConfig.partyListBgScale) - (settings.bgOffset * gConfig.partyListBgScale));
        backgroundPrim.br.width = settings.borderSize;
        backgroundPrim.br.height = settings.borderSize;

        backgroundPrim.tr.visible = backgroundPrim.tr.exists;
        backgroundPrim.tr.position_x = backgroundPrim.br.position_x;
        backgroundPrim.tr.position_y = backgroundPrim.bg.position_y - settings.bgOffset * gConfig.partyListBgScale;
        backgroundPrim.tr.width = backgroundPrim.br.width;
        backgroundPrim.tr.height = math.ceil((backgroundPrim.br.position_y - backgroundPrim.tr.position_y) / gConfig.partyListBgScale);

        backgroundPrim.tl.visible = backgroundPrim.tl.exists;
        backgroundPrim.tl.position_x = backgroundPrim.bg.position_x - settings.bgOffset * gConfig.partyListBgScale;
        backgroundPrim.tl.position_y = backgroundPrim.tr.position_y
        backgroundPrim.tl.width = math.ceil((backgroundPrim.tr.position_x - backgroundPrim.tl.position_x) / gConfig.partyListBgScale);
        backgroundPrim.tl.height = backgroundPrim.tr.height;

        backgroundPrim.bl.visible = backgroundPrim.bl.exists;
        backgroundPrim.bl.position_x = backgroundPrim.tl.position_x;
        backgroundPrim.bl.position_y = backgroundPrim.br.position_y;
        backgroundPrim.bl.width = backgroundPrim.tl.width;
        backgroundPrim.bl.height = backgroundPrim.br.height;

        bgTitlePrim.visible = gConfig.showPartyListTitle;
        bgTitlePrim.position_x = imguiPosX + math.floor((bgWidth / 2) - (bgTitlePrim.width * bgTitlePrim.scale_x / 2));
        bgTitlePrim.position_y = imguiPosY - math.floor((bgTitlePrim.height * bgTitlePrim.scale_y / 2) + (2 / bgTitlePrim.scale_y));
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
    -- Initialize all our font objects we need
    local name_font_settings = deep_copy_table(settings.name_font_settings);
    local hp_font_settings = deep_copy_table(settings.hp_font_settings);
    local mp_font_settings = deep_copy_table(settings.mp_font_settings);
    local tp_font_settings = deep_copy_table(settings.tp_font_settings);

    for i = 0, memberTextCount-1 do
        local partyIndex = math.ceil((i + 1) / partyMaxSize);

        local partyListFontOffset = gConfig.partyListFontOffset;
        if (partyIndex == 2) then
            partyListFontOffset = gConfig.partyList2FontOffset;
        elseif (partyIndex == 3) then
            partyListFontOffset = gConfig.partyList3FontOffset;
        end

        name_font_settings.font_height = math.max(settings.name_font_settings.font_height + partyListFontOffset, 1);
        hp_font_settings.font_height = math.max(settings.hp_font_settings.font_height + partyListFontOffset, 1);
        mp_font_settings.font_height = math.max(settings.mp_font_settings.font_height + partyListFontOffset, 1);
        tp_font_settings.font_height = math.max(settings.tp_font_settings.font_height + partyListFontOffset, 1);

        memberText[i] = {};
        memberText[i].name = fonts.new(name_font_settings);
        memberText[i].hp = fonts.new(hp_font_settings);
        memberText[i].mp = fonts.new(mp_font_settings);
        memberText[i].tp = fonts.new(tp_font_settings);
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

        local bgTitlePrim = primitives.new(settings.prim_data);
        bgTitlePrim.color = 0xFFC5CFDC;
        bgTitlePrim.texture = string.format('%s/assets/PartyList-Titles.png', addon.path);
        bgTitlePrim.visible = false;
        bgTitlePrim.can_focus = false;
        bgTitleItemHeight = bgTitlePrim.height / bgTitleAtlasItemCount;
        bgTitlePrim.height = bgTitleItemHeight;

        partyWindowPrim[i].bgTitle = bgTitlePrim;
    end

    selectionPrim = primitives.new(settings.prim_data);
    selectionPrim.color = 0xFFFFFFFF;
    selectionPrim.texture = string.format('%s/assets/Selector.png', addon.path);
    selectionPrim.visible = false;
    selectionPrim.can_focus = false;

    arrowPrim = primitives.new(settings.prim_data);
    arrowPrim.color = 0xFFFFFFFF;
    arrowPrim.visible = false;
    arrowPrim.can_focus = false;

    partyList.UpdateFonts(settings);
end

partyList.UpdateFonts = function(settings)
    -- Destroy and recreate fonts
    for i = 0, memberTextCount-1 do
        local partyIndex = math.ceil((i + 1) / partyMaxSize);

        local partyListFontOffset = gConfig.partyListFontOffset;
        if (partyIndex == 2) then
            partyListFontOffset = gConfig.partyList2FontOffset;
        elseif (partyIndex == 3) then
            partyListFontOffset = gConfig.partyList3FontOffset;
        end

        -- Create font settings with proper height offset
        local name_font_settings = {
            visible = settings.name_font_settings.visible,
            locked = settings.name_font_settings.locked,
            font_family = settings.name_font_settings.font_family,
            font_height = math.max(settings.name_font_settings.font_height + partyListFontOffset, 1),
            color = settings.name_font_settings.color,
            bold = settings.name_font_settings.bold,
            italic = settings.name_font_settings.italic,
            color_outline = settings.name_font_settings.color_outline,
            draw_flags = settings.name_font_settings.draw_flags,
            background = settings.name_font_settings.background,
            right_justified = settings.name_font_settings.right_justified,
        };
        local hp_font_settings = {
            visible = settings.hp_font_settings.visible,
            locked = settings.hp_font_settings.locked,
            font_family = settings.hp_font_settings.font_family,
            font_height = math.max(settings.hp_font_settings.font_height + partyListFontOffset, 1),
            color = settings.hp_font_settings.color,
            bold = settings.hp_font_settings.bold,
            italic = settings.hp_font_settings.italic,
            color_outline = settings.hp_font_settings.color_outline,
            draw_flags = settings.hp_font_settings.draw_flags,
            background = settings.hp_font_settings.background,
            right_justified = settings.hp_font_settings.right_justified,
        };
        local mp_font_settings = {
            visible = settings.mp_font_settings.visible,
            locked = settings.mp_font_settings.locked,
            font_family = settings.mp_font_settings.font_family,
            font_height = math.max(settings.mp_font_settings.font_height + partyListFontOffset, 1),
            color = settings.mp_font_settings.color,
            bold = settings.mp_font_settings.bold,
            italic = settings.mp_font_settings.italic,
            color_outline = settings.mp_font_settings.color_outline,
            draw_flags = settings.mp_font_settings.draw_flags,
            background = settings.mp_font_settings.background,
            right_justified = settings.mp_font_settings.right_justified,
        };
        local tp_font_settings = {
            visible = settings.tp_font_settings.visible,
            locked = settings.tp_font_settings.locked,
            font_family = settings.tp_font_settings.font_family,
            font_height = math.max(settings.tp_font_settings.font_height + partyListFontOffset, 1),
            color = settings.tp_font_settings.color,
            bold = settings.tp_font_settings.bold,
            italic = settings.tp_font_settings.italic,
            color_outline = settings.tp_font_settings.color_outline,
            draw_flags = settings.tp_font_settings.draw_flags,
            background = settings.tp_font_settings.background,
            right_justified = settings.tp_font_settings.right_justified,
        };

        -- Destroy old font objects
        if (memberText[i] ~= nil) then
            if (memberText[i].name ~= nil) then memberText[i].name:destroy(); end
            if (memberText[i].hp ~= nil) then memberText[i].hp:destroy(); end
            if (memberText[i].mp ~= nil) then memberText[i].mp:destroy(); end
            if (memberText[i].tp ~= nil) then memberText[i].tp:destroy(); end
        end

        -- Recreate font objects with new settings
        memberText[i].name = fonts.new(name_font_settings);
        memberText[i].hp = fonts.new(hp_font_settings);
        memberText[i].mp = fonts.new(mp_font_settings);
        memberText[i].tp = fonts.new(tp_font_settings);
        -- Note: All text colors are set dynamically in DrawWindow every frame
    end

    -- Reset cached colors when fonts are recreated
    memberTextColorCache = {};

    -- Update images
    local bgChanged = gConfig.partyListBackgroundName ~= loadedBg;
    loadedBg = gConfig.partyListBackgroundName;

    local bgColor = tonumber(string.format('%02x%02x%02x%02x', gConfig.partyListBgColor[4], gConfig.partyListBgColor[1], gConfig.partyListBgColor[2], gConfig.partyListBgColor[3]), 16);
    local borderColor = tonumber(string.format('%02x%02x%02x%02x', gConfig.partyListBorderColor[4], gConfig.partyListBorderColor[1], gConfig.partyListBorderColor[2], gConfig.partyListBorderColor[3]), 16);

    for i = 1, 3 do
        partyWindowPrim[i].bgTitle.scale_x = gConfig.partyListBgScale / 2.30;
        partyWindowPrim[i].bgTitle.scale_y = gConfig.partyListBgScale / 2.30;

        local backgroundPrim = partyWindowPrim[i].background;

        for _, k in ipairs(bgImageKeys) do
            local file_name = string.format('%s-%s.png', gConfig.partyListBackgroundName, k);
            backgroundPrim[k].color = k == 'bg' and bgColor or borderColor;
            if (bgChanged) then
                -- Keep width/height to prevent flicker when switching to new texture
                local width, height = backgroundPrim[k].width, backgroundPrim[k].height;
                local filepath = string.format('%s/assets/backgrounds/%s', addon.path, file_name);
                backgroundPrim[k].texture = filepath;
                backgroundPrim[k].width, backgroundPrim[k].height = width, height;

                backgroundPrim[k].exists = ashita.fs.exists(filepath);
            end
            backgroundPrim[k].scale_x = gConfig.partyListBgScale;
            backgroundPrim[k].scale_y = gConfig.partyListBgScale;
        end
    end

    arrowPrim.texture = string.format('%s/assets/cursors/%s', addon.path, gConfig.partyListCursor);
end

partyList.SetHidden = function(hidden)
	if (hidden == true) then
        UpdateTextVisibility(false);
        selectionPrim.visible = false;
        arrowPrim.visible = false;
	end
end

partyList.HandleZonePacket = function(e)
    statusHandler.clear_cache();
end

return partyList;