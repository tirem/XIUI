require('common');
require('helpers');
local imgui = require('imgui');
local debuffHandler = require('debuffhandler');
local statusHandler = require('statushandler');

-- TODO: Calculate these instead of manually setting them
local bgAlpha = 0.4;
local bgRadius = 3;
local allClaimedTargets = {};
local enemylist = {};

local function GetIsValidMob(mobIdx)
	-- Check if we are valid, are above 0 hp, and are rendered

    local renderflags = AshitaCore:GetMemoryManager():GetEntity():GetRenderFlags0(mobIdx);
    if bit.band(renderflags, 0x200) ~= 0x200 or bit.band(renderflags, 0x4000) ~= 0 then
        return false;
    end
	return true;
end

local function GetPartyMemberIds()
	local partyMemberIds = {};
	local party = AshitaCore:GetMemoryManager():GetParty();
	for i = 0, 17 do
		if (party:GetMemberIsActive(i) == 1) then
			table.insert(partyMemberIds, party:GetMemberServerId(i));
		end
	end
	return partyMemberIds;
end

enemylist.DrawWindow = function(settings, userSettings)

	imgui.SetNextWindowSize({ settings.barWidth, -1, }, ImGuiCond_Always);
	-- Draw the main target window
	if (imgui.Begin('EnemyList', true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground))) then
		imgui.SetWindowFontScale(settings.textScale);
		local winStartX, winStartY = imgui.GetWindowPos();
		local playerTarget = AshitaCore:GetMemoryManager():GetTarget();
		local targetIndex;
		local subTargetIndex;
		local subTargetActive = false;
		if (playerTarget ~= nil) then
			subTargetActive = playerTarget:GetIsSubTargetActive() > 0;
			if (subTargetActive) then
				targetIndex = playerTarget:GetTargetIndex(1);
				subTargetIndex = playerTarget:GetTargetIndex(0);
			else
				targetIndex = playerTarget:GetTargetIndex(0);
			end
		end
		
		local numTargets = 0;
		for k,v in pairs(allClaimedTargets) do
			local ent = GetEntity(k);
			if (v ~= nil and ent ~= nil and GetIsValidMob(k)) then
				-- Obtain and prepare target information..
				local targetNameText = ent.Name;
				if (targetNameText ~= nil) then

					local color = GetColorOfTarget(ent, k);
					local y, _  = imgui.CalcTextSize(targetNameText);

					imgui.Dummy({0,settings.entrySpacing});
					local rectLength = imgui.GetColumnWidth() + imgui.GetStyle().FramePadding.x;
					
					-- draw background to entry
					local winX, winY  = imgui.GetCursorScreenPos();

					-- Figure out sizing on the background
					local cornerOffset = settings.bgTopPadding;
					local xDist, yDist = imgui.CalcTextSize(targetNameText);
					if (yDist > settings.barHeight) then
						yDist = yDist + yDist;
					else
						yDist = yDist + settings.barHeight;
					end

					draw_rect({winX + cornerOffset , winY + cornerOffset}, {winX + rectLength, winY + yDist + settings.bgPadding}, {0,0,0,bgAlpha}, bgRadius, true);

					-- Draw outlines for our target and subtarget
					if (subTargetIndex ~= nil and k == subTargetIndex) then
						draw_rect({winX + cornerOffset, winY + cornerOffset}, {winX + rectLength - 1, winY + yDist + settings.bgPadding}, {.5,.5,1,1}, bgRadius, false);
					elseif (targetIndex ~= nil and k == targetIndex) then
						draw_rect({winX + cornerOffset, winY + cornerOffset}, {winX + rectLength - 1, winY + yDist + settings.bgPadding}, {1,1,1,1}, bgRadius, false);
					end

					-- Display the targets information..
					imgui.TextColored(color, targetNameText);
					local percentText  = ('%.f'):fmt(ent.HPPercent);
					local x, _  = imgui.CalcTextSize(percentText);
					local fauxX, _  = imgui.CalcTextSize('100');

					-- Draw buffs and debuffs
					local buffIds = debuffHandler.GetActiveDebuffs(AshitaCore:GetMemoryManager():GetEntity():GetServerId(k));
					if (buffIds ~= nil and #buffIds > 0) then
						imgui.SetNextWindowPos({winStartX + settings.barWidth + settings.debuffOffsetX, winY + settings.debuffOffsetY});
						if (imgui.Begin('EnemyDebuffs'..k, true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground))) then
							imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {1, 1});
							DrawStatusIcons(buffIds, settings.iconSize, settings.maxIcons, 1);
							imgui.PopStyleVar(1);
						end 
						imgui.End();
					end

					imgui.SetCursorPosX(imgui.GetCursorPosX() + fauxX - x);
					imgui.Text(percentText);
					imgui.SameLine();
					imgui.SetCursorPosX(imgui.GetCursorPosX() - 3);
					imgui.ProgressBar(ent.HPPercent / 100, { -1, settings.barHeight}, '');
					imgui.SameLine();

					imgui.Separator();

					numTargets = numTargets + 1;
					if (numTargets >= userSettings.maxEnemyListEntries) then
						break;
					end
				end
			else
				allClaimedTargets[k] = nil;
			end
		end
	end
	imgui.End();
end

-- If a mob performns an action on us or a party member add it to the list
enemylist.HandleActionPacket = function(e)
	if (GetIsMobByIndex(e.UserIndex) and GetIsValidMob(e.UserIndex)) then
		local partyMemberIds = GetPartyMemberIds();
		for i = 0, #e.Targets do
			if (e.Targets[i] ~= nil and has_value(partyMemberIds, e.Targets[i].Id)) then
				allClaimedTargets[e.UserIndex] = 1;
			end
		end
	end
end

-- if a mob updates its claimid to be us or a party member add it to the list
enemylist.HandleMobUpdatePacket = function(e)
	if (e.newClaimId ~= nil and GetIsValidMob(e.monsterIndex)) then	
		local partyMemberIds = GetPartyMemberIds();
		if (has_value(partyMemberIds, e.newClaimId)) then
			allClaimedTargets[e.monsterIndex] = 1;
		end
	end
end

enemylist.HandleZonePacket = function(e)
	-- Empty all our claimed targets on zone
	allClaimedTargets = T{};
end

return enemylist;