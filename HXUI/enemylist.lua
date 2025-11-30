require('common');
require('helpers');
local imgui = require('imgui');
local gdi = require('gdifonts.include');
local primitives = require('primitives');
local debuffHandler = require('debuffhandler');
local statusHandler = require('statushandler');
local actionTracker = require('actiontracker');
local progressbar = require('progressbar');

-- Note: RENDER_FLAG_VISIBLE and RENDER_FLAG_HIDDEN are now imported from helpers.lua

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
local enemyDistanceFonts = {};  -- Distance text font objects
local enemyHPFonts = {};  -- HP% text font objects
local enemyTargetFonts = {};  -- Target name font objects

-- Cache last set colors to avoid expensive SetColor() calls every frame
local enemyNameColorCache = {};

-- Background primitive objects (keyed by enemy index)
local enemyBackgrounds = {};  -- Background rectangles for each enemy entry
local enemyTargetBackgrounds = {};  -- Background rectangles for target containers

local function GetIsValidMob(mobIdx)
	-- Check if we are valid, are above 0 hp, and are rendered

    local entity = GetEntitySafe();
    if entity == nil then
        return false;
    end

    local renderflags = entity:GetRenderFlags0(mobIdx);
    if bit.band(renderflags, RENDER_FLAG_VISIBLE) ~= RENDER_FLAG_VISIBLE or bit.band(renderflags, RENDER_FLAG_HIDDEN) ~= 0 then
        return false;
    end
	return true;
end

local function GetPartyMemberIds()
	local partyMemberIds = T{};
	local party = GetPartySafe();
	if party == nil then
		return partyMemberIds;
	end
	for i = 0, 17 do
		if (party:GetMemberIsActive(i) == 1) then
			table.insert(partyMemberIds, party:GetMemberServerId(i));
		end
	end
	return partyMemberIds;
end

-- Truncates text to fit within maxWidth using binary search for optimal performance
local function TruncateTextToFit(fontObj, text, maxWidth)
	-- First check if text fits without truncation
	fontObj:set_text(text);
	local width, height = fontObj:get_text_size();

	if (width <= maxWidth) then
		return text;
	end

	-- Text is too long, use binary search to find optimal truncation point
	local ellipsis = "...";
	local maxLength = #text;

	-- Binary search for the longest substring that fits with ellipsis
	local left, right = 1, maxLength;
	local bestLength = 0;

	while left <= right do
		local mid = math.floor((left + right) / 2);
		local truncated = text:sub(1, mid) .. ellipsis;
		fontObj:set_text(truncated);
		width, height = fontObj:get_text_size();

		if width <= maxWidth then
			-- This length fits, try a longer one
			bestLength = mid;
			left = mid + 1;
		else
			-- This length is too long, try a shorter one
			right = mid - 1;
		end
	end

	if bestLength > 0 then
		return text:sub(1, bestLength) .. ellipsis;
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
		local playerTarget = GetTargetSafe();
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
				-- Row 2: HP bar (full width, uses barHeight)
				-- Row 3: Distance (left) and HP% (right) (uses distance/percent_font_settings.font_height)
				local nameHeight = settings.name_font_settings.font_height;
				local barHeight = settings.barHeight;
				-- Use the max height of distance and percent fonts for row spacing
				local infoRowHeight = math.max(settings.distance_font_settings.font_height, settings.percent_font_settings.font_height);
				local nameToBarGap = 10;  -- Vertical spacing between name and HP bar
				local barToInfoGap = 5;  -- Vertical spacing between HP bar and info row

				-- Calculate total height based on which rows are visible
				local totalContentHeight = nameHeight + nameToBarGap + barHeight;
				if (gConfig.showEnemyDistance or gConfig.showEnemyHPPText) then
					totalContentHeight = totalContentHeight + barToInfoGap + infoRowHeight;
				end
				local entryHeight = (padding * 2) + totalContentHeight;

				-- Prepare distance and HP% text separately
				local distanceText = '';
				local hpText = '';
				if (gConfig.showEnemyDistance) then
					distanceText = ('%.1f'):format(math.sqrt(ent.Distance));
				end
				if (gConfig.showEnemyHPPText) then
					hpText = ('%.0f%%'):format(ent.HPPercent);
				end

				-- HP bar is full width
				local barWidth = entryWidth - (padding * 2);

				-- ===== BACKGROUND & BORDER RENDERING =====
				-- We need to draw these BEFORE the ImGui content so they appear behind progress bars
				-- but fonts render in a separate Ashita layer, so they may still overlap

				-- Get entity name color based on type and claim status (ARGB format)
				local nameColor = GetEntityNameColor(ent, k, gConfig.colorCustomization.shared);

				-- Draw border first if this is the selected target
				local borderColor;
				if (subTargetIndex ~= nil and k == subTargetIndex) then
					-- Subtarget border - use configured color
					local rgba = ARGBToRGBA(gConfig.colorCustomization.enemyList.subtargetBorderColor);
					borderColor = imgui.GetColorU32(rgba);
				elseif (targetIndex ~= nil and k == targetIndex) then
					-- Main target border - use configured color
					local rgba = ARGBToRGBA(gConfig.colorCustomization.enemyList.targetBorderColor);
					borderColor = imgui.GetColorU32(rgba);
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
					-- Use FontManager for cleaner font creation
					enemyNameFonts[nameFontKey] = FontManager.create(settings.name_font_settings);
				end
				local nameFont = enemyNameFonts[nameFontKey];
				-- Dynamically set font height based on settings (avoids expensive font recreation)
				nameFont:set_font_height(settings.name_font_settings.font_height);
				nameFont:set_position_x(nameX);
				nameFont:set_position_y(nameY);

				-- Truncate name to fit within available width
				local maxNameWidth = entryWidth - (padding * 2);
				local displayName = TruncateTextToFit(nameFont, ent.Name, maxNameWidth);
				nameFont:set_text(displayName);

				-- Only call set_font_color if the color has changed (expensive operation for GDI fonts)
				if (enemyNameColorCache[nameFontKey] ~= nameColor) then
					nameFont:set_font_color(nameColor);
					enemyNameColorCache[nameFontKey] = nameColor;
				end
				nameFont:set_visible(true);

				-- ROW 2: HP Bar (full width)
				local row2Y = nameY + nameHeight + nameToBarGap;
				local barX = entryStartX + padding;
				imgui.SetCursorScreenPos({barX, row2Y});

				local enemyGradient = GetCustomGradient(gConfig.colorCustomization.enemyList, 'hpGradient') or {'#e16c6c', '#fb9494'};
				progressbar.ProgressBar(
					{{ent.HPPercent / 100, enemyGradient}},
					{barWidth, settings.barHeight},
					{decorate = gConfig.showEnemyListBookends}
				);

				-- ROW 3: Distance (left aligned) and HP% (right aligned)
				if (gConfig.showEnemyDistance or gConfig.showEnemyHPPText) then
					local row3Y = row2Y + barHeight + barToInfoGap;

					-- Distance text (left-aligned)
					if (gConfig.showEnemyDistance) then
						local distanceFontKey = 'distance_' .. k;
						if (enemyDistanceFonts[distanceFontKey] == nil) then
							-- Use FontManager for cleaner font creation
							enemyDistanceFonts[distanceFontKey] = FontManager.create(settings.distance_font_settings);
						end
						local distanceFont = enemyDistanceFonts[distanceFontKey];
						-- Dynamically set font height and color based on settings (avoids expensive font recreation)
						distanceFont:set_font_height(settings.distance_font_settings.font_height);
						distanceFont:set_font_color(settings.distance_font_settings.font_color);
						distanceFont:set_position_x(entryStartX + padding);
						distanceFont:set_position_y(row3Y);
						distanceFont:set_text(distanceText);
						distanceFont:set_visible(true);
					end

					-- HP% text (right-aligned)
					if (gConfig.showEnemyHPPText) then
						local hpFontKey = 'hp_' .. k;
						if (enemyHPFonts[hpFontKey] == nil) then
							-- Use FontManager for cleaner font creation
							enemyHPFonts[hpFontKey] = FontManager.create(settings.percent_font_settings);
						end
						local hpFont = enemyHPFonts[hpFontKey];
						-- Dynamically set font height and color based on settings (avoids expensive font recreation)
						hpFont:set_font_height(settings.percent_font_settings.font_height);
						hpFont:set_font_color(settings.percent_font_settings.font_color);
						hpFont:set_text(hpText);

						-- Right-align: set position to right edge, font alignment handles the rest
						hpFont:set_position_x(entryStartX + entryWidth - padding);
						hpFont:set_position_y(row3Y);
						hpFont:set_visible(true);
					end
				end

				-- ===== DEBUFF ICONS =====
				-- Positioned to the right of the entry in a separate window
				local buffIds = nil;
				local entity = GetEntitySafe();
				if entity ~= nil then
					buffIds = debuffHandler.GetActiveDebuffs(entity:GetServerId(k));
				end
				local debuffWidth = 0;
				if (buffIds ~= nil and #buffIds > 0) then
					-- Position debuffs to the right of the entry (accounting for window margin)
					local debuffX = entryStartX + entryWidth + settings.debuffOffsetX;
					imgui.SetNextWindowPos({debuffX, entryStartY + settings.debuffOffsetY});
					if (imgui.Begin('EnemyDebuffs'..k, true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoSavedSettings))) then
						imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {1, 1});
						DrawStatusIcons(buffIds, settings.iconSize, settings.maxIcons, 1);
						imgui.PopStyleVar(1);
						-- Calculate approximate debuff width for positioning target container
						debuffWidth = math.min(#buffIds, settings.maxIcons) * (settings.iconSize + 1) + 5;
					end
					imgui.End();
				end

				-- ===== ENEMY TARGET CONTAINER =====
				-- Show target's name and HP bar in a separate container to the right
				if (gConfig.showEnemyListTargets) then
					local targetIndex = actionTracker.GetLastTarget(ent.ServerId);
					if (targetIndex ~= nil) then
						local targetEntity = GetEntity(targetIndex);
						if (targetEntity ~= nil and targetEntity.Name ~= nil) then
							-- Position target container below the debuff row
							local targetContainerX = entryStartX + entryWidth + settings.debuffOffsetX + 10.;
							-- Position Y at the bottom of the enemy entry (bottom-right)
							local targetContainerY = entryStartY + entryHeight - ((settings.name_font_settings.font_height + 6) + 2);

							-- Target container dimensions
							local targetWidth = 100;
							local targetPadding = 6;
							local targetNameHeight = settings.name_font_settings.font_height;
							local targetTotalHeight = (targetPadding * 2) + targetNameHeight;

							-- ===== PRIMITIVE BACKGROUND RENDERING =====
							-- Create/get background primitive for this target container
							-- Primitives render in the correct layer (behind Ashita fonts)
							local targetBgKey = 'target_bg_' .. k;
							if (enemyTargetBackgrounds[targetBgKey] == nil and settings.prim_data) then
								enemyTargetBackgrounds[targetBgKey] = primitives.new(settings.prim_data);
								enemyTargetBackgrounds[targetBgKey].can_focus = false;
								enemyTargetBackgrounds[targetBgKey].locked = true;
							end

							if (enemyTargetBackgrounds[targetBgKey] ~= nil) then
								local targetBg = enemyTargetBackgrounds[targetBgKey];
								targetBg.position_x = targetContainerX;
								targetBg.position_y = targetContainerY;
								targetBg.width = targetWidth;
								targetBg.height = targetTotalHeight;
								-- Semi-transparent black (0.4 alpha * 255 = 102 = 0x66)
								targetBg.color = 0x66000000;
								targetBg.visible = true;
							end

							-- Target name
							local targetFontKey = 'target_' .. k;
							if (enemyTargetFonts[targetFontKey] == nil) then
								local targetFontSettings = deep_copy_table(settings.name_font_settings);
								targetFontSettings.font_alignment = gdi.Alignment.Left;
								targetFontSettings.font_color = 0xFFFFAA00;
								enemyTargetFonts[targetFontKey] = FontManager.create(targetFontSettings);
							end
							local targetFont = enemyTargetFonts[targetFontKey];
							targetFont:set_font_height(settings.name_font_settings.font_height);
							targetFont:set_font_color(0xFFFFAA00);
							targetFont:set_position_x(targetContainerX + targetPadding);
							targetFont:set_position_y(targetContainerY + targetPadding);
							-- Truncate name to fit
							local maxTargetNameWidth = targetWidth - (targetPadding * 2);
							local displayTargetName = TruncateTextToFit(targetFont, targetEntity.Name, maxTargetNameWidth);
							targetFont:set_text(displayTargetName);
							targetFont:set_visible(true);
						end
					end
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
				fontObj:set_visible(false);
			end
		end
		for fontKey, fontObj in pairs(enemyDistanceFonts) do
			local enemyIndex = tonumber(fontKey:match('distance_(%d+)'));
			if (enemyIndex == nil or allClaimedTargets[enemyIndex] == nil) then
				fontObj:set_visible(false);
			end
		end
		for fontKey, fontObj in pairs(enemyHPFonts) do
			local enemyIndex = tonumber(fontKey:match('hp_(%d+)'));
			if (enemyIndex == nil or allClaimedTargets[enemyIndex] == nil) then
				fontObj:set_visible(false);
			end
		end
		for bgKey, bgObj in pairs(enemyBackgrounds) do
			local enemyIndex = tonumber(bgKey:match('bg_(%d+)'));
			if (enemyIndex == nil or allClaimedTargets[enemyIndex] == nil) then
				bgObj.visible = false;
			end
		end
		for targetBgKey, targetBgObj in pairs(enemyTargetBackgrounds) do
			local enemyIndex = tonumber(targetBgKey:match('target_bg_(%d+)'));
			if (enemyIndex == nil or allClaimedTargets[enemyIndex] == nil or not gConfig.showEnemyListTargets) then
				targetBgObj.visible = false;
			end
		end
		for fontKey, fontObj in pairs(enemyTargetFonts) do
			local enemyIndex = tonumber(fontKey:match('target_(%d+)'));
			if (enemyIndex == nil or allClaimedTargets[enemyIndex] == nil or not gConfig.showEnemyListTargets) then
				fontObj:set_visible(false);
			end
		end

		-- Add bottom margin
		imgui.Dummy({0, windowMargin});
	end

	-- Restore ImGui style variables (must be before End() to avoid affecting other windows)
	imgui.PopStyleVar(3);
	imgui.End();
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
	-- Use FontManager for cleaner font destruction
	for k, v in pairs(enemyNameFonts) do
		enemyNameFonts[k] = FontManager.destroy(v);
	end
	for k, v in pairs(enemyDistanceFonts) do
		enemyDistanceFonts[k] = FontManager.destroy(v);
	end
	for k, v in pairs(enemyHPFonts) do
		enemyHPFonts[k] = FontManager.destroy(v);
	end
	enemyNameFonts = {};
	enemyDistanceFonts = {};
	enemyHPFonts = {};

	-- Clear background primitives on zone
	for k, v in pairs(enemyBackgrounds) do
		if (v ~= nil) then v:destroy(); end
	end
	enemyBackgrounds = {};
	for k, v in pairs(enemyTargetBackgrounds) do
		if (v ~= nil) then v:destroy(); end
	end
	enemyTargetBackgrounds = {};
end

enemylist.Initialize = function(settings)
	-- Initialization is handled dynamically in DrawWindow
	-- Font objects are created on-demand for each enemy
end

enemylist.UpdateVisuals = function(settings)
	-- Destroy all existing font objects
	-- Use FontManager for cleaner font destruction
	for k, v in pairs(enemyNameFonts) do
		enemyNameFonts[k] = FontManager.destroy(v);
	end
	for k, v in pairs(enemyDistanceFonts) do
		enemyDistanceFonts[k] = FontManager.destroy(v);
	end
	for k, v in pairs(enemyHPFonts) do
		enemyHPFonts[k] = FontManager.destroy(v);
	end
	for k, v in pairs(enemyTargetFonts) do
		enemyTargetFonts[k] = FontManager.destroy(v);
	end

	-- Clear the tables to force recreation with new settings
	enemyNameFonts = {};
	enemyDistanceFonts = {};
	enemyHPFonts = {};
	enemyTargetFonts = {};

	-- Reset cached colors when fonts are recreated
	enemyNameColorCache = {};
end

enemylist.Cleanup = function()
	-- Destroy all font objects
	-- Use FontManager for cleaner font destruction
	for k, v in pairs(enemyNameFonts) do
		enemyNameFonts[k] = FontManager.destroy(v);
	end
	for k, v in pairs(enemyDistanceFonts) do
		enemyDistanceFonts[k] = FontManager.destroy(v);
	end
	for k, v in pairs(enemyHPFonts) do
		enemyHPFonts[k] = FontManager.destroy(v);
	end
	for k, v in pairs(enemyTargetFonts) do
		enemyTargetFonts[k] = FontManager.destroy(v);
	end

	-- Destroy all background primitives
	for k, v in pairs(enemyBackgrounds) do
		if (v ~= nil) then v:destroy(); end
	end
	for k, v in pairs(enemyTargetBackgrounds) do
		if (v ~= nil) then v:destroy(); end
	end

	-- Clear all tables
	enemyNameFonts = {};
	enemyDistanceFonts = {};
	enemyHPFonts = {};
	enemyTargetFonts = {};
	enemyBackgrounds = {};
	enemyTargetBackgrounds = {};
	enemyNameColorCache = {};
end

return enemylist;