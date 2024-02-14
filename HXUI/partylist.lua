require('common');
local imgui = require('imgui');
local fonts = require('fonts');
local primitives = require('primitives');
local statusHandler = require('statushandler');
local buffTable = require('bufftable');
local progressbar = require('progressbar');
local encoding = require('gdifonts.encoding');
local ashita_settings = require('settings');

local fullMenuSizeX;
local fullMenuSizeY;
local buffWindowX = {};
local debuffWindowX = {};
local backgroundPrim = {};
local bgTitlePrim;
local selectionPrim;
local arrowPrim;
local partyTargeted;
local partySubTargeted;
local memberText = {};

local borderConfig = {1, '#243e58'};

local bgImageKeys = { 'bg', 'tl', 'tr', 'br', 'bl' };
local bgTitleAtlasItemCount = 4;
local bgTitleItemHeight;
local loadedBg = nil;

local partyList = {};

local function UpdateTextVisibilityByMember(memIdx, visible)

    memberText[memIdx].hp:SetVisible(visible);
    memberText[memIdx].mp:SetVisible(visible);
    memberText[memIdx].tp:SetVisible(visible);
    memberText[memIdx].name:SetVisible(visible);
end

local function UpdateTextVisibility(visible)

    for i = 0, 5 do
        UpdateTextVisibilityByMember(i, visible);
    end
    selectionPrim.visible = visible;
    arrowPrim.visible = visible;
    bgTitlePrim.visible = visible and gConfig.showPartyListTitle;

    for _, k in ipairs(bgImageKeys) do
        backgroundPrim[k].visible = visible and backgroundPrim[k].exists;
    end
end

local function GetMemberInformation(memIdx)

    if (showConfig[1] and gConfig.partyListPreview) then
        local memInfo = {};
        memInfo.hpp = memIdx == 4 and 0.1 or memIdx == 2 and 0.5 or memIdx == 0 and 0.75 or 1;
        memInfo.maxhp = 1000;
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
        memInfo.inzone = memIdx ~= 3;
        memInfo.name = memIdx == 1 and 'Partyleader' or 'Player' .. (memIdx + 1);
        memInfo.leader = memIdx == 1;
        return memInfo
    end

    local party = AshitaCore:GetMemoryManager():GetParty();
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if (player == nil or party == nil or party:GetMemberIsActive(memIdx) == 0) then
        return nil;
    end

    local playerTarget = AshitaCore:GetMemoryManager():GetTarget();

    local memberInfo = {};
    memberInfo.zone = party:GetMemberZone(memIdx);
    memberInfo.inzone = memberInfo.zone == party:GetMemberZone(0);
    memberInfo.name = party:GetMemberName(memIdx);
    memberInfo.leader = party:GetAlliancePartyLeaderServerId1() == party:GetMemberServerId(memIdx);

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
    end

    return memberInfo;
end

local function DrawMember(memIdx, partyMemberCount, settings)

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

    local subTargetActive = GetSubTargetActive();
    local nameSize = SIZE.new();
    local hpSize = SIZE.new();
    memberText[memIdx].name:GetTextSize(nameSize);
    memberText[memIdx].hp:GetTextSize(hpSize);

    -- Get the hp color for bars and text
    local hpNameColor, hpGradient = GetHpColors(memInfo.hpp);

    local bgGradientOverride = {'#000813', '#000813'};

    local allBarsLengths = settings.hpBarWidth + settings.mpBarWidth + settings.tpBarWidth + (imgui.GetStyle().FramePadding.x * 2) + (imgui.GetStyle().ItemSpacing.x * 2);


    local hpStartX, hpStartY = imgui.GetCursorScreenPos();

    -- Draw the job icon in the FFXIV theme before we draw anything else
    local namePosX = hpStartX;
    local jobIconSize = settings.iconSize * 1.1;
    local offsetStartY = hpStartY - jobIconSize - settings.nameTextOffsetY;
    imgui.SetCursorScreenPos({namePosX, offsetStartY});
    local jobIcon = statusHandler.GetJobIcon(memInfo.job);
    if (jobIcon ~= nil) then
        namePosX = namePosX + jobIconSize + settings.nameTextOffsetX;
        imgui.Image(jobIcon, {jobIconSize, jobIconSize});
    end
    imgui.SetCursorScreenPos({hpStartX, hpStartY});

    -- Update the hp text
    memberText[memIdx].hp:SetColor(hpNameColor);
    memberText[memIdx].hp:SetPositionX(hpStartX + settings.hpBarWidth + settings.hpTextOffsetX);
    memberText[memIdx].hp:SetPositionY(hpStartY + settings.barHeight + settings.hpTextOffsetY);
    memberText[memIdx].hp:SetText(tostring(memInfo.hp));

    -- Draw the HP bar
    if (memInfo.inzone) then
        progressbar.ProgressBar({{memInfo.hpp, hpGradient}}, {settings.hpBarWidth, settings.barHeight}, {borderConfig=borderConfig, backgroundGradientOverride=bgGradientOverride, decorate = gConfig.showPartyListBookends});
    elseif (memInfo.zone == '') then
        imgui.Dummy({allBarsLengths, settings.barHeight + hpSize.cy + settings.hpTextOffsetY});
    else
        imgui.ProgressBar(0, {allBarsLengths, settings.barHeight + hpSize.cy + settings.hpTextOffsetY}, encoding:ShiftJIS_To_UTF8(AshitaCore:GetResourceManager():GetString("zones.names", memInfo.zone), true));
    end

    -- Draw the leader icon
    if (memInfo.leader) then
        draw_circle({hpStartX + settings.dotRadius/2, hpStartY + settings.dotRadius/2}, settings.dotRadius, {1, 1, .5, 1}, settings.dotRadius * 3, true);
    end

    -- Update the name text
    memberText[memIdx].name:SetColor(0xFFFFFFFF);
    memberText[memIdx].name:SetPositionX(namePosX);
    memberText[memIdx].name:SetPositionY(hpStartY - nameSize.cy - settings.nameTextOffsetY);
    memberText[memIdx].name:SetText(tostring(memInfo.name));

    local nameSize = SIZE.new();
    memberText[0].name:GetTextSize(nameSize);
    local offsetSize = nameSize.cy > settings.iconSize and nameSize.cy or settings.iconSize;

    -- Draw the MP bar
    if (memInfo.inzone) then
        imgui.SameLine();
        local mpStartX, mpStartY; 
        imgui.SetCursorPosX(imgui.GetCursorPosX());
        mpStartX, mpStartY = imgui.GetCursorScreenPos();
        progressbar.ProgressBar({{memInfo.mpp, {'#9abb5a', '#bfe07d'}}}, {settings.mpBarWidth, settings.barHeight}, {borderConfig=borderConfig, backgroundGradientOverride=bgGradientOverride, decorate = gConfig.showPartyListBookends});
        imgui.SameLine();

        -- Draw the TP bar
        local tpStartX, tpStartY;
        imgui.SetCursorPosX(imgui.GetCursorPosX());
        tpStartX, tpStartY = imgui.GetCursorScreenPos();

		local tpGradient = {'#3898ce', '#78c4ee'};
		local tpOverlayGradient = {'#0078CC', '#0078CC'};
		local mainPercent;
		local tpOverlay;
		
		if (memInfo.tp >= 1000) then
			mainPercent = (memInfo.tp - 1000) / 2000;
			tpOverlay = {{1, tpOverlayGradient}, math.ceil(settings.barHeight * 2/7), 1};
		else
			mainPercent = memInfo.tp / 1000;
		end
		
		progressbar.ProgressBar({{mainPercent, tpGradient}}, {settings.tpBarWidth, settings.barHeight}, {overlayBar=tpOverlay, borderConfig=borderConfig, backgroundGradientOverride=bgGradientOverride, decorate = gConfig.showPartyListBookends});

        -- Update the mp text
        memberText[memIdx].mp:SetColor(gAdjustedSettings.mpColor);
        memberText[memIdx].mp:SetPositionX(mpStartX + settings.mpBarWidth + settings.mpTextOffsetX);
        memberText[memIdx].mp:SetPositionY(mpStartY + settings.barHeight + settings.mpTextOffsetY);
        memberText[memIdx].mp:SetText(tostring(memInfo.mp));

        -- Update the tp text
        if (memInfo.tp >= 1000) then 
            memberText[memIdx].tp:SetColor(gAdjustedSettings.tpFullColor);
        else
            memberText[memIdx].tp:SetColor(gAdjustedSettings.tpEmptyColor);
        end	
        memberText[memIdx].tp:SetPositionX(tpStartX + settings.tpBarWidth + settings.tpTextOffsetX);
        memberText[memIdx].tp:SetPositionY(tpStartY + settings.barHeight + settings.tpTextOffsetY);
        memberText[memIdx].tp:SetText(tostring(memInfo.tp));

        -- Draw targeted
        local entrySize = hpSize.cy + offsetSize + settings.hpTextOffsetY + settings.barHeight + settings.cursorPaddingY1 + settings.cursorPaddingY2;
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
        if (memInfo.buffs ~= nil and #memInfo.buffs > 0) then
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
                    elseif (gConfig.partyListStatusTheme == 1 and fullMenuSizeX ~= nil) then
                        local thisPosX, _ = imgui.GetWindowPos();
                        imgui.SetNextWindowPos({thisPosX + fullMenuSizeX, hpStartY - settings.iconSize*1.2});
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
                    elseif (gConfig.partyListStatusTheme == 1 and fullMenuSizeX ~= nil) then
                        local thisPosX, _ = imgui.GetWindowPos();
                        imgui.SetNextWindowPos({thisPosX + fullMenuSizeX , hpStartY});
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
        draw_circle({hpStartX + settings.dotRadius/2, hpStartY + settings.barHeight}, settings.dotRadius, {.5, .5, 1, 1}, settings.dotRadius * 3, true);
    end

    memberText[memIdx].hp:SetVisible(memInfo.inzone);
    memberText[memIdx].mp:SetVisible(memInfo.inzone);
    memberText[memIdx].tp:SetVisible(memInfo.inzone);

    if (memInfo.inzone) then
        imgui.Dummy({0, settings.entrySpacing + hpSize.cy + settings.hpTextOffsetY + settings.nameTextOffsetY});
    else
        imgui.Dummy({0, settings.entrySpacing + settings.nameTextOffsetY});
    end

    if (memIdx + 1 < partyMemberCount) then
        imgui.Dummy({0, offsetSize});
    end
end

partyList.DrawWindow = function(settings)

    -- Obtain the player entity..
    local party = AshitaCore:GetMemoryManager():GetParty();
    local player = AshitaCore:GetMemoryManager():GetPlayer();
	
	if (party == nil or player == nil) then
		UpdateTextVisibility(false);
		return;
	end
	local currJob = player:GetMainJob();
    local partyMemberCount = 1;
    if (showConfig[1] and gConfig.partyListPreview) then
        partyMemberCount = 6;
    else
        for i = 1, 5 do
            if (party:GetMemberIsActive(i) ~= 0) then
                partyMemberCount = partyMemberCount + 1
            else
                break
            end
        end
    end
    if (player.isZoning or currJob == 0 or (not gConfig.showPartyListWhenSolo and partyMemberCount == 1)) then
		UpdateTextVisibility(false);
        return;
	end

    -- TODO: bgTitleItemHeight*2 or bgTitleItemHeight*3 for Party B and Party C in Alliance
    bgTitlePrim.texture_offset_y = partyMemberCount == 1 and 0 or bgTitleItemHeight;

    local imguiPosX, imguiPosY;

    local windowFlags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoBringToFrontOnFocus);
    if (gConfig.lockPositions) then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
    end
    -- Remove all padding and start our window
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {0,0});
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {settings.barSpacing,0});
    if (imgui.Begin('PartyList', true, windowFlags)) then
        imguiPosX, imguiPosY = imgui.GetWindowPos();
        local nameSize = SIZE.new();
        memberText[0].name:GetTextSize(nameSize);
        local offsetSize = nameSize.cy > settings.iconSize and nameSize.cy or settings.iconSize;
        imgui.Dummy({0, settings.nameTextOffsetY + offsetSize});
        if (fullMenuSizeX ~= nil and fullMenuSizeY ~= nil) then
            local bgWidth = fullMenuSizeX + (settings.bgPadding * 2);
            local bgHeight = fullMenuSizeY + (settings.bgPadding * 2);

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
        end
        partyTargeted = false;
        partySubTargeted = false;
        UpdateTextVisibility(true);
        for i = 0, 5 do
            if (settings.expandHeight or i < partyMemberCount or i < settings.minRows) then
                DrawMember(i, partyMemberCount, settings);
            else
                UpdateTextVisibilityByMember(i, false);
            end
        end
        if (partyTargeted == false) then
            selectionPrim.visible = false;
        end
        if (partySubTargeted == false) then
            arrowPrim.visible = false;
        end
    end

    fullMenuSizeX, fullMenuSizeY = imgui.GetWindowSize();
	imgui.End();
    imgui.PopStyleVar(2);

    if (settings.alignBottom and imguiPosX ~= nil) then
        if (gConfig.partyListState ~= nil) then
            -- Move window if size changed
            if (fullMenuSizeY ~= gConfig.partyListState.height) then
                imguiPosY = imguiPosY + (gConfig.partyListState.height - fullMenuSizeY);
                imgui.SetWindowPos('PartyList', {imguiPosX, imguiPosY});
            end
        end

        -- Update if the state changed
        if (gConfig.partyListState == nil or 
            imguiPosX ~= gConfig.partyListState.x or imguiPosY ~= gConfig.partyListState.y or 
            fullMenuSizeX ~= gConfig.partyListState.width or fullMenuSizeY ~= gConfig.partyListState.height) then
            gConfig.partyListState = {
                x = imguiPosX,
                y = imguiPosY,
                width = fullMenuSizeX,
                height = fullMenuSizeY,
            };
            ashita_settings.save();
        end
    end
end

partyList.Initialize = function(settings)
    -- Initialize all our font objects we need
    for i = 0, 5 do
        memberText[i] = {};
        memberText[i].name = fonts.new(settings.name_font_settings);
        memberText[i].hp = fonts.new(settings.hp_font_settings);
        memberText[i].mp = fonts.new(settings.mp_font_settings);
        memberText[i].tp = fonts.new(settings.tp_font_settings);
    end

    -- Initialize images
    loadedBg = nil;
    for _, k in ipairs(bgImageKeys) do
        backgroundPrim[k] = primitives:new(settings.prim_data);
        backgroundPrim[k].visible = false;
        backgroundPrim[k].can_focus = false;
        backgroundPrim[k].exists = false;
    end

    bgTitlePrim = primitives.new(settings.prim_data);
    bgTitlePrim.color = 0xFFC5CFDC;
    bgTitlePrim.texture = string.format('%s/assets/PartyList-Titles.png', addon.path);
    bgTitlePrim.visible = false;
    bgTitlePrim.can_focus = false;
    bgTitleItemHeight = bgTitlePrim.height / bgTitleAtlasItemCount;
    bgTitlePrim.height = bgTitleItemHeight;

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
    -- Update fonts
    for i = 0, 5 do
        memberText[i].name:SetFontHeight(settings.name_font_settings.font_height);
        memberText[i].hp:SetFontHeight(settings.hp_font_settings.font_height);
        memberText[i].mp:SetFontHeight(settings.mp_font_settings.font_height);
        memberText[i].tp:SetFontHeight(settings.tp_font_settings.font_height);
    end

    -- Update images
    local bgChanged = gConfig.partyListBackgroundName ~= loadedBg;
    loadedBg = gConfig.partyListBackgroundName;

    local bgColor = tonumber(string.format('%02x%02x%02x%02x', gConfig.partyListBgColor[4], gConfig.partyListBgColor[1], gConfig.partyListBgColor[2], gConfig.partyListBgColor[3]), 16);
    local borderColor = tonumber(string.format('%02x%02x%02x%02x', gConfig.partyListBorderColor[4], gConfig.partyListBorderColor[1], gConfig.partyListBorderColor[2], gConfig.partyListBorderColor[3]), 16);
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

    bgTitlePrim.scale_x = gConfig.partyListBgScale / 2.30;
    bgTitlePrim.scale_y = gConfig.partyListBgScale / 2.30;

    arrowPrim.texture = string.format('%s/assets/cursors/%s', addon.path, gConfig.partyListCursor);
end

partyList.SetHidden = function(hidden)
	if (hidden == true) then
        UpdateTextVisibility(false);
	end
end

partyList.HandleZonePacket = function(e)
    statusHandler.clear_cache();
end

return partyList;