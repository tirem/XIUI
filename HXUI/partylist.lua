require('common');
local imgui = require('imgui');
local fonts = require('fonts');
local primitives = require('primitives');
local statusHandler = require('statushandler');
local buffTable = require('bufftable');
local progressbar = require('progressbar');

local fullMenuSizeX;
local fullMenuSizeY;
local buffWindowX = {};
local debuffWindowX = {};
local backgroundPrim;
local selectionPrim;
local arrowPrim;
local partyTargeted;
local partySubTargeted;
local memberText = {};

local borderConfig = {1, '#243e58'};

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
    backgroundPrim.visible = visible;
    selectionPrim.visible = visible;
    arrowPrim.visible = visible;
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

local function DrawMember(memIdx, settings)

    local memInfo = GetMemberInformation(memIdx);
    local playerTarget = AshitaCore:GetMemoryManager():GetTarget();
    if (memInfo == nil or playerTarget == nil) then
        UpdateTextVisibilityByMember(memIdx, false);
        return;
    end

    local subTargetActive = GetSubTargetActive();
    local nameSize = SIZE.new();
    local hpSize = SIZE.new();
    memberText[memIdx].name:GetTextSize(nameSize);
    memberText[memIdx].hp:GetTextSize(hpSize);

    -- Get the hp color for bars and text
    local hpNameColor, hpGradient = GetHpColors(memInfo.hpp);

    local allBarsLengths = settings.hpBarWidth + settings.mpBarWidth + settings.tpBarWidth + (settings.barSpacing * 2) + (imgui.GetStyle().FramePadding.x * 4);


    local hpStartX, hpStartY = imgui.GetCursorScreenPos();

    -- Draw the job icon in the FFXIV theme before we draw anything else
    local namePosX = hpStartX + settings.nameTextOffsetX;
    if (memInfo.inzone) then
        imgui.SetCursorScreenPos({namePosX, hpStartY - settings.iconSize - settings.nameTextOffsetY});
        namePosX = namePosX + settings.iconSize;
        local jobIcon = statusHandler.GetJobIcon(memInfo.job);
        if (jobIcon ~= nil) then
            imgui.Image(jobIcon, {settings.iconSize, settings.iconSize});
        end
        imgui.SetCursorScreenPos({hpStartX, hpStartY});
    end

    -- Update the hp text
    memberText[memIdx].hp:SetColor(hpNameColor);
    memberText[memIdx].hp:SetPositionX(hpStartX + settings.hpBarWidth + settings.hpTextOffsetX);
    memberText[memIdx].hp:SetPositionY(hpStartY + settings.barHeight + settings.hpTextOffsetY);
    memberText[memIdx].hp:SetText(tostring(memInfo.hp));

    -- Draw the HP bar
    if (memInfo.inzone) then
        -- imgui.ProgressBar(memInfo.hpp, { settings.hpBarWidth, settings.barHeight }, '');
        progressbar.ProgressBar({{memInfo.hpp, hpGradient}}, {settings.hpBarWidth, settings.barHeight}, {borderConfig=borderConfig});
    else
--        imgui.PushStyleColor(ImGuiCol_PlotHistogram, hpBarColor);
        imgui.ProgressBar(0, { allBarsLengths, settings.barHeight + hpSize.cy + settings.hpTextOffsetY}, AshitaCore:GetResourceManager():GetString("zones.names", memInfo.zone));
--        imgui.PopStyleColor(1);
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

    -- Draw the MP bar
    if (memInfo.inzone) then
        imgui.SameLine();
        local mpStartX, mpStartY; 
        imgui.SetCursorPosX(imgui.GetCursorPosX() + settings.barSpacing);
        mpStartX, mpStartY = imgui.GetCursorScreenPos();
        -- imgui.PushStyleColor(ImGuiCol_PlotHistogram, { 0.9, 1.0, 0.5, 1.0});
        -- imgui.ProgressBar(memInfo.mpp, {  settings.mpBarWidth, settings.barHeight }, '');
        -- imgui.PopStyleColor(1);
        progressbar.ProgressBar({{memInfo.mpp, {'#9abb5a', '#bfe07d'}}}, {settings.mpBarWidth, settings.barHeight}, {borderConfig=borderConfig});
        imgui.SameLine();

        -- Draw the TP bar
        local tpStartX, tpStartY;
        imgui.SetCursorPosX(imgui.GetCursorPosX() + settings.barSpacing);
        tpStartX, tpStartY = imgui.GetCursorScreenPos();
        local tpX = imgui.GetCursorPosX();
        --[[
        if (memInfo.tp >= 1000) then
            imgui.PushStyleColor(ImGuiCol_PlotHistogram, { 0.2, 0.4, 1.0, 1.0});
        else
            imgui.PushStyleColor(ImGuiCol_PlotHistogram, { 0.3, 0.7, 1.0, 1.0});
        end
        imgui.ProgressBar(memInfo.tp / 1000, { settings.tpBarWidth, settings.barHeight }, '');
        imgui.PopStyleColor(1);
        if (memInfo.tp >= 1000) then
            imgui.SameLine();
            imgui.SetCursorPosX(tpX);
            imgui.PushStyleColor(ImGuiCol_PlotHistogram, { 0.3, 0.7, 1.0, 1.0});
            imgui.ProgressBar((memInfo.tp - 1000) / 2000, { settings.tpBarWidth, settings.barHeight * 3/5 }, '');
            imgui.PopStyleColor(1);
        end
        ]]--

		local tpGradient = {'#3898ce', '#78c4ee'};
		local tpOverlayGradient = {'#0078CC', '#0078CC'};
		local mainPercent;
		local tpOverlay;
		
		if (memInfo.tp >= 1000) then
			-- imgui.PushStyleColor(ImGuiCol_PlotHistogram, { 0.2, 0.4, 1.0, 1.0});
			-- tpGradient = {'#3898ce', '#78c4ee'};
			mainPercent = (memInfo.tp - 1000) / 2000;
			tpOverlay = {{1, tpOverlayGradient}, math.ceil(settings.barHeight * 2/7), 1};
		else
			mainPercent = memInfo.tp / 1000;
			-- imgui.PushStyleColor(ImGuiCol_PlotHistogram, { 0.3, 0.7, 1.0, 1.0});
			-- tpGradient = {'#4db2ff', '#4db2ff'};
		end
		
		-- imgui.ProgressBar(SelfTP / 1000, { barSize, settings.barHeight }, '');
		-- imgui.PopStyleColor(1);
		progressbar.ProgressBar({{mainPercent, tpGradient}}, {settings.tpBarWidth, settings.barHeight}, {overlayBar=tpOverlay, borderConfig=borderConfig});

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
        local entrySize = hpSize.cy + nameSize.cy + settings.hpTextOffsetY + settings.nameTextOffsetY + settings.barHeight + settings.cursorPaddingY1 + settings.cursorPaddingY2;
        if (memInfo.targeted == true) then
            selectionPrim.visible = true;
            selectionPrim.position_x = hpStartX - settings.cursorPaddingX1;
            selectionPrim.position_y = hpStartY - nameSize.cy - settings.nameTextOffsetY - settings.cursorPaddingY1;
            selectionPrim.scale_x = (allBarsLengths + settings.cursorPaddingX1 + settings.cursorPaddingX2) / 356;
            selectionPrim.scale_y = entrySize / 108;
            partyTargeted = true;
        end

        -- Draw subtargeted
        if ((memInfo.targeted == true and not subTargetActive) or memInfo.subTargeted) then
            arrowPrim.visible = true;
            local newArrowX =  memberText[memIdx].name:GetPositionX() - arrowPrim:GetWidth();
            newArrowX = newArrowX - settings.iconSize;
            arrowPrim.position_x = newArrowX;
            arrowPrim.position_y = (hpStartY - nameSize.cy - settings.nameTextOffsetY - settings.cursorPaddingY1) + (entrySize/2) - arrowPrim:GetHeight()/2;
            arrowPrim.scale_x = settings.arrowSize;
            arrowPrim.scale_y = settings.arrowSize;
            if (memInfo.targeted == false) then
                arrowPrim.color = settings.subtargetArrowTint;
            else
                arrowPrim.color = 0xFFFFFFFF;
            end
            partySubTargeted = true;
        end

        -- Draw the different party list buff / debuff themes
        if (memInfo.buffs ~= nil and #memInfo.buffs > 0) then
            if (gConfig.partyListStatusTheme == 0) then
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
                    if (buffWindowX[memIdx] ~= nil) then
                        imgui.SetNextWindowPos({hpStartX - buffWindowX[memIdx] - settings.buffOffset , memberText[memIdx].name:GetPositionY() - settings.iconSize/2});
                    end
                    if (imgui.Begin('PlayerBuffs'..memIdx, true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoSavedSettings))) then
                        imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {5, 1});
                        DrawStatusIcons(buffs, settings.iconSize, 32, 1, true);
                        imgui.PopStyleVar(1);
                    end
                    local buffWindowSizeX, buffWindowSizeY = imgui.GetWindowSize();
                    buffWindowX[memIdx] = buffWindowSizeX;
    
                    imgui.End();
                end

                if (debuffs ~= nil and #debuffs > 0) then
                    if (debuffWindowX[memIdx] ~= nil) then
                        imgui.SetNextWindowPos({hpStartX - debuffWindowX[memIdx] - settings.buffOffset , memberText[memIdx].name:GetPositionY() + settings.iconSize});
                    end
                    if (imgui.Begin('PlayerDebuffs'..memIdx, true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoSavedSettings))) then
                        imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {5, 1});
                        DrawStatusIcons(debuffs, settings.iconSize, 32, 1, true);
                        imgui.PopStyleVar(1);
                    end
                    local buffWindowSizeX, buffWindowSizeY = imgui.GetWindowSize();
                    debuffWindowX[memIdx] = buffWindowSizeX;
                    imgui.End();
                end
            elseif (gConfig.partyListStatusTheme == 1) then
                -- Draw FFXIV theme
                local resetX, resetY = imgui.GetCursorScreenPos();
                imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0} );
                imgui.SetNextWindowPos({mpStartX, mpStartY - settings.iconSize - settings.xivBuffOffsetY})
                if (imgui.Begin('XIVStatus'..memIdx, true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoSavedSettings))) then
                    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {1, 1});
                    DrawStatusIcons(memInfo.buffs, settings.iconSize, 32, 1);
                    imgui.PopStyleVar(1);
                end
                imgui.PopStyleVar(1);
                imgui.End();
                imgui.SetCursorScreenPos({resetX, resetY});
            else
                if (buffWindowX[memIdx] ~= nil) then
                    imgui.SetNextWindowPos({hpStartX - buffWindowX[memIdx] - settings.buffOffset , memberText[memIdx].name:GetPositionY() - settings.iconSize/2});
                end
                if (imgui.Begin('PlayerBuffs'..memIdx, true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoSavedSettings))) then
                    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {1, 3});
                    DrawStatusIcons(memInfo.buffs, settings.iconSize, 7, 3);
                    imgui.PopStyleVar(1);
                end
                local buffWindowSizeX, buffWindowSizeY = imgui.GetWindowSize();
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
        imgui.Dummy({0, settings.entrySpacing + hpSize.cy + settings.hpTextOffsetY + settings.nameTextOffsetY + nameSize.cy});
    else
        imgui.Dummy({0, settings.entrySpacing + settings.nameTextOffsetY + nameSize.cy});
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
    if (player.isZoning or currJob == 0 or (not gConfig.showPartyListWhenSolo and party:GetMemberIsActive(1) == 0)) then
		UpdateTextVisibility(false);
        return;
	end

    if (imgui.Begin('PartyList', true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground))) then
        local nameSize = SIZE.new();
        local hpSize = SIZE.new();
        memberText[0].name:GetTextSize(nameSize);
        memberText[0].hp:GetTextSize(hpSize);
        imgui.Dummy({0, settings.nameTextOffsetY + nameSize.cy});
        if (fullMenuSizeX ~= nil and fullMenuSizeY ~= nil) then
            backgroundPrim.visible = true;
            local imguiPosX, imguiPosY = imgui.GetWindowPos();
            backgroundPrim.position_x = imguiPosX - settings.backgroundPaddingX1;
            backgroundPrim.position_y = imguiPosY - settings.backgroundPaddingY1;
            backgroundPrim.scale_x = (fullMenuSizeX + settings.backgroundPaddingX1 + settings.backgroundPaddingX2) / 512;
            backgroundPrim.scale_y = (fullMenuSizeY - settings.entrySpacing + settings.backgroundPaddingY1 + settings.backgroundPaddingY2 - (settings.nameTextOffsetY + nameSize.cy)) / 512;
        end
        partyTargeted = false;
        partySubTargeted = false;
        UpdateTextVisibility(true);
        for i = 0, 5 do
            DrawMember(i, settings);
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
    
    backgroundPrim = primitives:new(settings.primData);
    backgroundPrim.color = tonumber(string.format('%02x%02x%02x%02x', gConfig.partyListBgOpacity, 255, 255, 255), 16);

    backgroundPrim.texture = string.format('%s/assets/backgrounds/'..gConfig.partyListBackground, addon.path);
    backgroundPrim.visible = false;

    selectionPrim = primitives.new(settings.primData);
    selectionPrim.color = 0xFFFFFFFF;
    selectionPrim.texture = string.format('%s/assets/Selector.png', addon.path);
    selectionPrim.visible = false;

    arrowPrim = primitives.new(settings.primData);
    arrowPrim.color = 0xFFFFFFFF;
    arrowPrim.texture = string.format('%s/assets/cursors/'..gConfig.partyListCursor, addon.path);
    arrowPrim.visible = false;
end

partyList.UpdateFonts = function(settings)
    -- Initialize all our font objects we need
    for i = 0, 5 do
        memberText[i].name:SetFontHeight(settings.name_font_settings.font_height);
        memberText[i].hp:SetFontHeight(settings.hp_font_settings.font_height);
        memberText[i].mp:SetFontHeight(settings.mp_font_settings.font_height);
        memberText[i].tp:SetFontHeight(settings.tp_font_settings.font_height);
    end
    backgroundPrim.color = tonumber(string.format('%02x%02x%02x%02x', gConfig.partyListBgOpacity, 255, 255, 255), 16);
    backgroundPrim.texture = string.format('%s/assets/backgrounds/'..gConfig.partyListBackground, addon.path);
    arrowPrim.texture = string.format('%s/assets/cursors/'..gConfig.partyListCursor, addon.path);
end

partyList.SetHidden = function(hidden)
	if (hidden == true) then
        UpdateTextVisibility(false);
        backgroundPrim.visible = false;
	end
end

partyList.HandleZonePacket = function(e)
    statusHandler.clear_cache();
end

return partyList;