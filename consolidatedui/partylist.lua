require('common');
local imgui = require('imgui');
local fonts = require('fonts');
local primitives = require('primitives');

local mpOffsetPercentX = 2/3;
local mpOffsetPercentY = 2/3;

local fullMenuSizeX;
local fullMenuSizeY;
local backgroundPrim;
local selectionPrim;
local partyTargeted;
local memberText = {};

local partyList = {};

local function UpdateTextVisibilityByMember(memIdx, visible)

    memberText[memIdx].hp:SetVisible(visible);
    memberText[memIdx].mp:SetVisible(visible);
    memberText[memIdx].name:SetVisible(visible);
    if (memIdx == 0) then
        backgroundPrim.visible = false;
        selectionPrim.visible = false;
    end
end

local function UpdateTextVisibility(visible)

    for i = 0, 5 do
        UpdateTextVisibilityByMember(i, visible);
    end
    backgroundPrim.visible = false;
    selectionPrim.visible = false;
end

local function GetMemberInformation(memIdx)

    local party = AshitaCore:GetMemoryManager():GetParty();
    local player = AshitaCore:GetMemoryManager():GetPlayer();

	local playerTarget = AshitaCore:GetMemoryManager():GetTarget();
    if (player == nil or party == nil or party:GetMemberIsActive(memIdx) == 0) then
        return nil;
    end

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
        memberInfo.job = AshitaCore:GetResourceManager():GetString("jobs.names_abbr", party:GetMemberMainJob(memIdx));
        memberInfo.level = party:GetMemberMainJobLevel(memIdx);
        if (playerTarget ~= nil) then
            memberInfo.targeted = playerTarget:GetTargetIndex(0) == party:GetMemberTargetIndex(memIdx);
        else
            memberInfo.targeted = false;
        end
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
    end

    return memberInfo;
end

local function DrawMember(memIdx, settings)

    local memInfo = GetMemberInformation(memIdx);
    if (memInfo == nil) then
        UpdateTextVisibilityByMember(memIdx, false);
        return;
    end

    -- Leave some space for the hp text
    local startX, startY = imgui.GetCursorScreenPos();
    imgui.Dummy({settings.nameSpacing, settings.name_font_settings.font_height});

    -- Update the name text
    memberText[memIdx].name:SetColor(0xFF00FFFF);
    memberText[memIdx].name:SetPositionX(startX + (settings.nameSpacing / 2));
    memberText[memIdx].name:SetPositionY(startY);
    local nameText = memInfo.name;
    memberText[memIdx].name:SetText(LimitStringLength(memInfo.name, 10));
    memberText[memIdx].name:SetVisible(true);

    -- Draw the leader icon
    if (memInfo.leader == true) then
       draw_circle({startX + settings.leaderDotRadius/2, startY + settings.leaderDotRadius/2}, settings.leaderDotRadius, {1, 1, 0, 1}, settings.leaderDotRadius * 3, true);
    end

    -- Draw the HP bar
    imgui.SameLine();
    local hpStartX, hpStartY = imgui.GetCursorScreenPos();
    imgui.SetCursorScreenPos({hpStartX, hpStartY + settings.hpBarOffsetY});
    imgui.PushStyleColor(ImGuiCol_PlotHistogram, {1, .4, .4, 1});
    if (memInfo.inzone) then
        imgui.ProgressBar(memInfo.hpp, { settings.hpBarWidth, settings.hpBarHeight }, '');
    else
        imgui.ProgressBar(0, { settings.hpBarWidth, settings.hpBarHeight }, AshitaCore:GetResourceManager():GetString("zones.names", memInfo.zone));
    end
    imgui.PopStyleColor(1);
    imgui.SameLine();

    -- Draw the MP bar
    local mpBarWidth = settings.hpBarWidth * mpOffsetPercentX;
    imgui.SetCursorScreenPos({hpStartX + (settings.hpBarWidth * (1 - mpOffsetPercentX)), hpStartY + (settings.hpBarHeight * mpOffsetPercentY)});
    local mpStartX, mpStartY = imgui.GetCursorScreenPos();
    imgui.PushStyleColor(ImGuiCol_PlotHistogram, {.9, 1, .5, 1});
    imgui.ProgressBar(memInfo.mpp, {  mpBarWidth, settings.mpBarHeight }, '');
    imgui.PopStyleColor(1);
    imgui.SameLine();

    -- Draw the TP bar
    imgui.SetCursorScreenPos({startX + (settings.nameSpacing / 2) - (settings.tpBarWidth / 2), startY + settings.name_font_settings.font_height + settings.tpBarOffsetY});
    if (memInfo.tp > 1000) then
        imgui.PushStyleColor(ImGuiCol_PlotHistogram, {.2, .4, 1, 1});
    else
        imgui.PushStyleColor(ImGuiCol_PlotHistogram, {.3, .7, 1, 1});
    end
    imgui.ProgressBar(memInfo.tp / 1000, { settings.tpBarWidth, settings.tpBarHeight }, '');
    imgui.PopStyleColor(1);

    -- Update the HP text
    memberText[memIdx].hp:SetPositionX(mpStartX + settings.hpTextOffsetX);
    memberText[memIdx].hp:SetPositionY(hpStartY + (settings.hpBarHeight) + settings.hpTextOffsetY + settings.hpBarOffsetY);
    memberText[memIdx].hp:SetText(tostring(memInfo.hp));
    memberText[memIdx].hp:SetVisible(memInfo.inzone);
    if (memInfo.hpp < .25) then 
        memberText[memIdx].hp:SetColor(0xFFFF0000);
    elseif (memInfo.hpp < .50) then;
        memberText[memIdx].hp:SetColor(0xFFFFA500);
    elseif (memInfo.hpp < .75) then
        memberText[memIdx].hp:SetColor(0xFFFFFF00);
    else
        memberText[memIdx].hp:SetColor(0xFFFFFFFF);
    end

    -- Update the MP text
    memberText[memIdx].mp:SetPositionX(mpStartX + mpBarWidth);
    memberText[memIdx].mp:SetPositionY(mpStartY + settings.mpBarHeight + settings.mpTextOffsetY);
    memberText[memIdx].mp:SetText(tostring(memInfo.mp));
    memberText[memIdx].mp:SetVisible(memInfo.inzone);
    if (memInfo.mpp >= 1) then 
        memberText[memIdx].mp:SetColor(0xFFCFFBCF);
    else
        memberText[memIdx].mp:SetColor(0xFFFFFFFF);
    end

    if (memInfo.targeted == true) then
        selectionPrim.visible = true;
        selectionPrim.position_x = startX - settings.cursorPaddingX1;
        selectionPrim.position_y = startY - settings.cursorPaddingY1;
        selectionPrim.scale_x = (settings.nameSpacing + settings.cursorPaddingX1 + settings.cursorPaddingX2)/ 390;
        selectionPrim.scale_y = (memberText[memIdx].name.GetFontHeight() + settings.cursorPaddingY1 + settings.cursorPaddingY2) / 60;
        partyTargeted = true;
    end

    imgui.Dummy({0, settings.entrySpacing});
end

partyList.DrawWindow = function(settings, userSettings)

    -- Obtain the player entity..
    local party = AshitaCore:GetMemoryManager():GetParty();
    local player = AshitaCore:GetMemoryManager():GetPlayer();
	
	if (party == nil or player == nil) then
		UpdateTextVisibility(false);
		return;
	end
	local currJob = player:GetMainJob();
    if (player.isZoning or currJob == 0 or (not userSettings.showPartyListWhenSolo and party:GetMemberIsActive(1) == 0)) then
		UpdateTextVisibility(false);
        return;
	end

    if (imgui.Begin('PartyList', true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground))) then
        if (fullMenuSizeX ~= nil and fullMenuSizeY ~= nil) then
            backgroundPrim.visible = true;
            local imguiPosX, imguiPosY = imgui.GetWindowPos();
            backgroundPrim.position_x = imguiPosX - settings.backgroundPaddingX1;
            backgroundPrim.position_y = imguiPosY - settings.backgroundPaddingY1;
            backgroundPrim.scale_x = (fullMenuSizeX + settings.backgroundPaddingX1 + settings.backgroundPaddingX2)/ 1000;
            backgroundPrim.scale_y = (fullMenuSizeY - settings.entrySpacing + settings.backgroundPaddingY1 + settings.backgroundPaddingY2) / 1000;
        end
        partyTargeted = false;
        for i = 0, 5 do
            DrawMember(i, settings);
        end
        if (partyTargeted == false) then
            selectionPrim.visible = false;
        end
    end

    fullMenuSizeX, fullMenuSizeY = imgui.GetWindowSize();
	imgui.End();
end


partyList.Initialize = function(settings)
    -- Initialize all our font objects we need
    for i = 0, 5 do
        memberText[i] = {};
        memberText[i].name = fonts.new(settings.name_font_settings);
        memberText[i].hp = fonts.new(settings.hp_font_settings);
        memberText[i].mp = fonts.new(settings.mp_font_settings);
    end
    backgroundPrim = primitives:new(settings.primData);
    backgroundPrim.color = 0xC0FFFFFF;
    backgroundPrim.texture = string.format('%s/assets/partybg.png', addon.path);
    backgroundPrim.visible = false;

    selectionPrim = primitives.new(settings.primData);
    selectionPrim.color = 0xFFFFFFFF;
    selectionPrim.texture = string.format('%s/assets/cursor.png', addon.path);
    selectionPrim.visible = false;
end

partyList.SetHidden = function(hidden)
	if (hidden == true) then
        UpdateTextVisibility(false);
	end
end

return partyList;