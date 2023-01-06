require('common');
require('helpers');
local imgui = require('imgui');

-- TODO: Calculate these instead of manually setting them
local cornerOffset = -3;
local backgroundY = 35;

local bgAlpha = 0.4;
local bgRadius = 8;
local allClaimedTargets = {};
local frameSkip = 20;
local currentFrame = frameSkip;

local enemylist = {};

local function GetIsClaimed(targetIndex, partyMemberIds)

	local entMgr = AshitaCore:GetMemoryManager():GetEntity();
	local claimStatus = entMgr:GetClaimStatus(targetIndex);
	local claimId = bit.band(claimStatus, 0xFFFF);

	if (claimId == 0) then
		return false;
	else
		for i = 0, #partyMemberIds do
			if (partyMemberIds[i] == claimId) then
				return true;
			end;
		end
	end
	return false;
end

local function UpdatedClaimedTargets(maxEntries)

	-- get all active party member server ids
	local partyMemberIds = {};
	local party = AshitaCore:GetMemoryManager():GetParty();
	for i = 0, 17 do
		if (party:GetMemberIsActive(i) == 1) then
			table.insert(partyMemberIds, party:GetMemberServerId(i));
		end
	end

	-- get entites with a claimid from our party
	local newClaimedTargets = {};
	for x = 0, 2303 do
		if (#allClaimedTargets > maxEntries) then
			break;
		end
        if (GetIsClaimed(x, partyMemberIds)) then
            allClaimedTargets[x] = 1;
        end
    end

end

enemylist.DrawWindow = function(settings)

	-- Throttle our entity check
	if (currentFrame >= frameSkip) then
		UpdatedClaimedTargets(settings.maxEntries);
		currentFrame = 0;
	end
	currentFrame = currentFrame + 1;

	imgui.SetNextWindowSize({ settings.barWidth, -1, }, ImGuiCond_Always);
		-- Draw the main target window
		if (imgui.Begin('EnemyList', true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground))) then
			imgui.SetWindowFontScale(settings.textScale);

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
			

			for k,v in pairs(allClaimedTargets) do

				local ent = GetEntity(k);
				if (v ~= nil and ent ~= nil and ent.HPPercent > 0) then

					-- Obtain and prepare target information..
					local targetNameText = ent.Name;
					if (targetNameText ~= nil) then
						local color = GetColorOfTarget(ent, k);
						local y, _  = imgui.CalcTextSize(targetNameText);

						imgui.Dummy({0,settings.entrySpacing});
						local rectLength = imgui.GetColumnWidth() + imgui.GetStyle().FramePadding.x;
						
						-- draw background to entry
						local winX, winY  = imgui.GetCursorScreenPos();
						draw_rect({winX + cornerOffset , winY + cornerOffset}, {winX + rectLength, winY + backgroundY}, {0,0,0,bgAlpha}, bgRadius, true);

						-- Draw outlines for our target and subtarget
						if (subTargetIndex ~= nil and k == subTargetIndex) then
							draw_rect({winX + cornerOffset, winY + cornerOffset}, {winX + rectLength - 1, winY + backgroundY}, {.5,.5,1,1}, bgRadius, false);
						elseif (targetIndex ~= nil and k == targetIndex) then
							draw_rect({winX + cornerOffset, winY + cornerOffset}, {winX + rectLength - 1, winY + backgroundY}, {1,1,1,1}, bgRadius, false);
						end

						-- Display the targets information..
						imgui.TextColored(color, targetNameText);
						local percentText  = ('%.f'):fmt(ent.HPPercent);
						local x, _  = imgui.CalcTextSize(percentText);
						local fauxX, _  = imgui.CalcTextSize('100');
						imgui.SetCursorPosX(imgui.GetCursorPosX() + fauxX - x);
						imgui.Text(percentText);
						imgui.SameLine();
						imgui.SetCursorPosX(imgui.GetCursorPosX() - 3);
						imgui.ProgressBar(ent.HPPercent / 100, { -1, settings.barHeight}, '');
						imgui.SameLine();


						imgui.Separator();
					end
				else
					allClaimedTargets[k] = nil;
				end
			end
		end
		imgui.End();
end

return enemylist;