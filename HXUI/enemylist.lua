require('common');
require('helpers');
local imgui = require('imgui');
local fonts = require('fonts');
local primitives = require('primitives');
local debuffHandler = require('debuffhandler');
local statusHandler = require('statushandler');
local progressbar = require('progressbar');

-- Background rendering constants
local bgAlpha = 0.4;
local bgRadius = 3;

-- Layout constants
local windowMargin = 6;  -- Extra margin around window content to prevent clipping

-- Enemy tracking
local allClaimedTargets = {};
local enemylist = {};

-- Font objects for enemy list (keyed by enemy index)
local enemyNameFonts = {};  -- Enemy name font objects
local enemyInfoFonts = {};  -- Enemy info text font objects

-- Cache last set colors to avoid expensive SetColor() calls every frame
local enemyNameColorCache = {};

-- Background primitive objects (keyed by enemy index)
local enemyBackgrounds = {};  -- Background rectangles for each enemy entry

local function GetIsValidMob(mobIdx)
	-- Check if we are valid, are above 0 hp, and are rendered

    local renderflags = AshitaCore:GetMemoryManager():GetEntity():GetRenderFlags0(mobIdx);
    if bit.band(renderflags, 0x200) ~= 0x200 or bit.band(renderflags, 0x4000) ~= 0 then
        return false;
    end
	return true;
end

local function GetPartyMemberIds()
	local partyMemberIds = T{};
	local party = AshitaCore:GetMemoryManager():GetParty();
	for i = 0, 17 do
		if (party:GetMemberIsActive(i) == 1) then
			table.insert(partyMemberIds, party:GetMemberServerId(i));
		end
	end
	return partyMemberIds;
end

-- Truncates text to fit within maxWidth by progressively shortening and adding "..."
local function TruncateTextToFit(fontObj, text, maxWidth)
	-- First check if text fits without truncation
	fontObj:SetText(text);
	local size = SIZE.new();
	fontObj:GetTextSize(size);

	if (size.cx <= maxWidth) then
		return text;
	end

	-- Text is too long, progressively truncate until it fits
	local ellipsis = "...";
	local maxLength = #text;

	-- Binary search for optimal length would be faster, but linear is simpler and sufficient
	for len = maxLength - 1, 1, -1 do
		local truncated = text:sub(1, len) .. ellipsis;
		fontObj:SetText(truncated);
		fontObj:GetTextSize(size);

		if (size.cx <= maxWidth) then
			return truncated;
		end
	end

	-- Fallback: just ellipsis
	return ellipsis;
end

enemylist.DrawWindow = function(settings)

	-- Add margins to window width to prevent border/content clipping
	local windowWidth = settings.barWidth + (windowMargin * 2);
	imgui.SetNextWindowSize({ windowWidth, -1, }, ImGuiCond_Always);

	-- Draw the main target window
	local windowFlags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoBringToFrontOnFocus);
	if (gConfig.lockPositions) then
		windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
	end

	-- Remove all ImGui padding so we have full control over layout
	imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {0, 0});
	imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {0, 0});
	imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {0, 0});

	if (imgui.Begin('EnemyList', true, windowFlags)) then
		-- Add top margin
		imgui.Dummy({0, windowMargin});
		local winStartX, winStartY = imgui.GetWindowPos();
		local playerTarget = AshitaCore:GetMemoryManager():GetTarget();
		local targetIndex;
		local subTargetIndex;
		local subTargetActive = false;
		if (playerTarget ~= nil) then
			subTargetActive = GetSubTargetActive();
			targetIndex, subTargetIndex = GetTargets();
			if (subTargetActive) then
				local tempTarget = targetIndex;
				targetIndex = subTargetIndex;
				subTargetIndex = tempTarget;
			end
		end
		
		local numTargets = 0;
		for k,v in pairs(allClaimedTargets) do
			local ent = GetEntity(k);
            if (v ~= nil and ent ~= nil and GetIsValidMob(k) and ent.HPPercent > 0 and ent.Name ~= nil) then
				-- Add spacing between entries (but not before the first)
				if (numTargets > 0) then
					imgui.Dummy({0, settings.entrySpacing});
				end

				-- ===== LAYOUT CALCULATION =====
				-- Capture starting position for this enemy entry
				local cursorX, entryStartY = imgui.GetCursorScreenPos();

				-- Apply left margin to position content away from window edge
				local entryStartX = cursorX + windowMargin;

				-- Entry width is the content area (barWidth), not including window margins
				local entryWidth = settings.barWidth;
				local padding = 10;  -- Internal padding within entry (uniform 10px on all sides)
				local borderThickness = 2;

				-- Calculate entry dimensions
				-- Row 1: Name text (uses name_font_settings.font_height)
				-- Row 2: Info text + HP bar side-by-side (height = max of info font height or bar height)
				local nameHeight = settings.name_font_settings.font_height;
				local barRowHeight = math.max(settings.info_font_settings.font_height, settings.barHeight);
				local nameToBarGap = 10;  -- Vertical spacing between enemy name and HP bar row (increased for better readability)
				local totalContentHeight = nameHeight + nameToBarGap + barRowHeight;
				local entryHeight = (padding * 2) + totalContentHeight;

				-- Prepare info text
				local infoText = '';
				if (gConfig.showEnemyDistance and gConfig.showEnemyHPPText) then
					infoText = ('D:%.1f  %%:%.0f'):format(math.sqrt(ent.Distance), ent.HPPercent);
				elseif (gConfig.showEnemyDistance) then
					infoText = ('D:%.1f'):format(math.sqrt(ent.Distance));
				elseif (gConfig.showEnemyHPPText) then
					infoText = ('%.0f%%'):format(ent.HPPercent);
				end

				-- Create/get info font early so we can calculate text width correctly
				local infoFontKey = 'info_' .. k;
				if (enemyInfoFonts[infoFontKey] == nil) then
					enemyInfoFonts[infoFontKey] = fonts.new(settings.info_font_settings);
				end
				local infoFont = enemyInfoFonts[infoFontKey];
				infoFont:SetText(infoText);

				-- Calculate info text width using actual font metrics
				local infoSize = SIZE.new();
				infoFont:GetTextSize(infoSize);
				local infoTextWidth = infoSize.cx or 0;

				local barStartX = entryStartX + padding + infoTextWidth + 5;  -- 5px gap after text
				local barWidth = entryWidth - padding - (barStartX - entryStartX);

				-- ===== BACKGROUND & BORDER RENDERING =====
				-- We need to draw these BEFORE the ImGui content so they appear behind progress bars
				-- but fonts render in a separate Ashita layer, so they may still overlap
				local color = GetColorOfTargetRGBA(ent, k);

				-- Draw border first if this is the selected target
				local borderColor;
				if (subTargetIndex ~= nil and k == subTargetIndex) then
					borderColor = imgui.GetColorU32({0.5, 0.5, 1, 1}); -- Blue for subtarget
				elseif (targetIndex ~= nil and k == targetIndex) then
					borderColor = imgui.GetColorU32({1, 1, 1, 1}); -- White for target
				end

				if (borderColor) then
					-- Draw border rectangle around the entire entry
					-- Window margins ensure this won't be clipped
					imgui.GetWindowDrawList():AddRect(
						{entryStartX, entryStartY},
						{entryStartX + entryWidth, entryStartY + entryHeight},
						borderColor,
						bgRadius,
						ImDrawCornerFlags_All,
						borderThickness
					);
				end

				-- ===== PRIMITIVE BACKGROUND RENDERING =====
				-- Create/get background primitive for this enemy
				-- Primitives render in the correct layer (behind Ashita fonts)
				local bgKey = 'bg_' .. k;
				if (enemyBackgrounds[bgKey] == nil and settings.prim_data) then
					enemyBackgrounds[bgKey] = primitives.new(settings.prim_data);
					enemyBackgrounds[bgKey].can_focus = false;
					enemyBackgrounds[bgKey].locked = true;
				end

				if (enemyBackgrounds[bgKey] ~= nil) then
					local bg = enemyBackgrounds[bgKey];
					-- Set background position and size
					bg.position_x = entryStartX;
					bg.position_y = entryStartY;
					bg.width = entryWidth;
					bg.height = entryHeight;
					-- Set semi-transparent black color (ARGB format)
					-- Alpha is the first byte: 0.4 * 255 = 102 = 0x66
					bg.color = 0x66000000;  -- Semi-transparent black
					bg.visible = true;
				end

				-- ===== CONTENT RENDERING =====
				-- ROW 1: Enemy Name (colored based on entity type and claim status)
				local nameX = entryStartX + padding;
				local nameY = entryStartY + padding;

				local nameFontKey = 'name_' .. k;
				if (enemyNameFonts[nameFontKey] == nil) then
					enemyNameFonts[nameFontKey] = fonts.new(settings.name_font_settings);
				end
				local nameFont = enemyNameFonts[nameFontKey];
				nameFont:SetPositionX(nameX);
				nameFont:SetPositionY(nameY);

				-- Truncate name to fit within available width
				local maxNameWidth = entryWidth - (padding * 2);
				local displayName = TruncateTextToFit(nameFont, ent.Name, maxNameWidth);
				nameFont:SetText(displayName);

				-- Only call SetColor if the color has changed (expensive operation for GDI fonts)
				local desiredColor = bit.bor(
					bit.lshift(color[4] * 255, 24),
					bit.lshift(color[3] * 255, 16),
					bit.lshift(color[2] * 255, 8),
					color[1] * 255
				);
				if (enemyNameColorCache[nameFontKey] ~= desiredColor) then
					nameFont:SetColor(desiredColor);
					enemyNameColorCache[nameFontKey] = desiredColor;
				end
				nameFont:SetVisible(true);

				-- ROW 2: Info Text (left) and HP Bar (right) on same line
				local row2Y = nameY + nameHeight + nameToBarGap;

				-- Position info text at row2Y
				local infoX = entryStartX + padding;
				local infoY = row2Y;
				infoFont:SetPositionX(infoX);
				infoFont:SetPositionY(infoY);
				infoFont:SetVisible(true);

				-- Position HP bar slightly below to align with text center
				-- fontHeight=9px, barHeight=10px, so offset bar down by 1px to center with text
				local barY = row2Y + 2;  -- Push bar down 1px to align with text
				imgui.SetCursorScreenPos({barStartX, barY});

				local enemyGradient = GetCustomGradient(gConfig.colorCustomization.enemyList, 'hpGradient') or {'#e16c6c', '#fb9494'};
				progressbar.ProgressBar(
					{{ent.HPPercent / 100, enemyGradient}},
					{barWidth, settings.barHeight},
					{decorate = gConfig.showEnemyListBookends}
				);

				-- ===== DEBUFF ICONS =====
				-- Positioned to the right of the entry in a separate window
				local buffIds = debuffHandler.GetActiveDebuffs(AshitaCore:GetMemoryManager():GetEntity():GetServerId(k));
				if (buffIds ~= nil and #buffIds > 0) then
					-- Position debuffs to the right of the entry (accounting for window margin)
					local debuffX = entryStartX + entryWidth + settings.debuffOffsetX;
					imgui.SetNextWindowPos({debuffX, entryStartY + settings.debuffOffsetY});
					if (imgui.Begin('EnemyDebuffs'..k, true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoSavedSettings))) then
						imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {1, 1});
						DrawStatusIcons(buffIds, settings.iconSize, settings.maxIcons, 1);
						imgui.PopStyleVar(1);
					end
					imgui.End();
				end

				-- Move cursor to next entry position (back to left edge before margin)
				imgui.SetCursorScreenPos({cursorX, entryStartY + entryHeight});

				numTargets = numTargets + 1;
				if (numTargets >= gConfig.maxEnemyListEntries) then
					break;
				end
			else
				allClaimedTargets[k] = nil;
			end
		end

		-- Hide font objects and backgrounds for enemies not currently in the list
		for fontKey, fontObj in pairs(enemyNameFonts) do
			local enemyIndex = tonumber(fontKey:match('name_(%d+)'));
			if (enemyIndex == nil or allClaimedTargets[enemyIndex] == nil) then
				fontObj:SetVisible(false);
			end
		end
		for fontKey, fontObj in pairs(enemyInfoFonts) do
			local enemyIndex = tonumber(fontKey:match('info_(%d+)'));
			if (enemyIndex == nil or allClaimedTargets[enemyIndex] == nil) then
				fontObj:SetVisible(false);
			end
		end
		for bgKey, bgObj in pairs(enemyBackgrounds) do
			local enemyIndex = tonumber(bgKey:match('bg_(%d+)'));
			if (enemyIndex == nil or allClaimedTargets[enemyIndex] == nil) then
				bgObj.visible = false;
			end
		end

		-- Add bottom margin
		imgui.Dummy({0, windowMargin});
	end
	imgui.End();

	-- Restore ImGui style variables
	imgui.PopStyleVar(3);
end

-- If a mob performns an action on us or a party member add it to the list
enemylist.HandleActionPacket = function(e)
	if (e == nil) then 
		return; 
	end
	if (GetIsMobByIndex(e.UserIndex) and GetIsValidMob(e.UserIndex)) then
		local partyMemberIds = GetPartyMemberIds();
		for i = 0, #e.Targets do
			if (e.Targets[i] ~= nil and (partyMemberIds:contains(e.Targets[i].Id))) then
				allClaimedTargets[e.UserIndex] = 1;
			end
		end
	end
end

-- if a mob updates its claimid to be us or a party member add it to the list
enemylist.HandleMobUpdatePacket = function(e)
	if (e == nil) then 
		return; 
	end
	if (e.newClaimId ~= nil and GetIsValidMob(e.monsterIndex)) then	
		local partyMemberIds = GetPartyMemberIds();
		if ((partyMemberIds:contains(e.newClaimId))) then
			allClaimedTargets[e.monsterIndex] = 1;
		end
	end
end

enemylist.HandleZonePacket = function(e)
	-- Empty all our claimed targets on zone
	allClaimedTargets = T{};

	-- Clear font caches on zone
	for k, v in pairs(enemyNameFonts) do
		if (v ~= nil) then v:destroy(); end
	end
	for k, v in pairs(enemyInfoFonts) do
		if (v ~= nil) then v:destroy(); end
	end
	enemyNameFonts = {};
	enemyInfoFonts = {};

	-- Clear background primitives on zone
	for k, v in pairs(enemyBackgrounds) do
		if (v ~= nil) then v:destroy(); end
	end
	enemyBackgrounds = {};
end

enemylist.Initialize = function(settings)
	-- Initialization is handled dynamically in DrawWindow
	-- Font objects are created on-demand for each enemy
end

enemylist.UpdateFonts = function(settings)
	-- Destroy all existing font objects
	for k, v in pairs(enemyNameFonts) do
		if (v ~= nil) then v:destroy(); end
	end
	for k, v in pairs(enemyInfoFonts) do
		if (v ~= nil) then v:destroy(); end
	end

	-- Clear the tables to force recreation with new settings
	enemyNameFonts = {};
	enemyInfoFonts = {};

	-- Reset cached colors when fonts are recreated
	enemyNameColorCache = {};
end

return enemylist;