require('common');
require('handlers.helpers');
local imgui = require('imgui');
local imtext = require('libs.imtext');
local primitives = require('primitives');
local debuffHandler = require('handlers.debuffhandler');
local statusHandler = require('handlers.statushandler');
local actionTracker = require('handlers.actiontracker');
local progressbar = require('libs.progressbar');
local defaultPositions = require('libs.defaultpositions');

-- Position save/restore state
local hasAppliedSavedPosition = false;
local forcePositionReset = false;
local lastSavedPosX, lastSavedPosY = nil, nil;

-- Note: RENDER_FLAG_VISIBLE and RENDER_FLAG_HIDDEN are now imported from helpers.lua

-- Background rendering constants
local bgRadius = 3;

-- Apply opacity to an ARGB color by replacing its alpha byte
local function ApplyOpacityToColor(color, opacity)
	local alphaByte = math.floor((opacity or 1.0) * 255);
	local rgb = bit.band(color or 0xFFFFFFFF, 0x00FFFFFF);
	return bit.bor(bit.lshift(alphaByte, 24), rgb);
end

-- Layout constants
local windowMargin = 6;  -- Extra margin around window content to prevent clipping

-- Enemy tracking
local allClaimedTargets = {};
local enemylist = {};

-- Preview mode mock data
local previewEnemies = {
    [9001] = { Name = 'Test Enemy 1', HPPercent = 100, Distance = 72.25 },    -- 8.5y
    [9002] = { Name = 'Goblin Smithy', HPPercent = 75, Distance = 234.09 },   -- 15.3y
    [9003] = { Name = 'Yagudo Templar', HPPercent = 50, Distance = 488.41 },  -- 22.1y
    [9004] = { Name = 'Orcish Warlord', HPPercent = 25, Distance = 900 },     -- 30y
    [9005] = { Name = 'Quadav Veteran', HPPercent = 10, Distance = 100 },     -- 10y
    [9006] = { Name = 'Crab', HPPercent = 85, Distance = 156.25 },            -- 12.5y
    [9007] = { Name = 'Very Long Enemy Name That Should Truncate', HPPercent = 60, Distance = 289 }, -- 17y
    [9008] = { Name = 'Skeleton', HPPercent = 33, Distance = 625 },           -- 25y
};
-- Preview debuff data (different sets per enemy)
-- Common debuff IDs: 2=Sleep, 3=Poison, 4=Paralysis, 5=Blind, 6=Silence, 10=Stun, 11=Bind, 12=Weight, 13=Slow
local previewDebuffs = {
    [9001] = {3, 13},           -- Poison, Slow
    [9002] = {5, 6, 13},        -- Blind, Silence, Slow
    [9003] = {11, 12},          -- Bind, Weight
    [9004] = {3, 4, 5},         -- Poison, Paralyze, Blind
    [9005] = {2},               -- Sleep
    [9006] = {13},              -- Slow
    [9007] = {3, 5, 6, 11, 13}, -- Many debuffs
    [9008] = {},                -- No debuffs
};
-- Preview target data (who each enemy is targeting)
local previewTargets = {
    [9001] = 'Playername',
    [9002] = 'Whitemage',
    [9003] = nil,               -- No target
    [9004] = 'Warrior',
    [9005] = 'Blackmage',
    [9006] = nil,               -- No target
    [9007] = 'Longtargetname',
    [9008] = 'Redmage',
};

-- Track which enemy indices are currently active (for background visibility management)
local activeEnemyIndices = {};

-- Background primitive objects (keyed by numeric enemy index)
local enemyBackgrounds = {};  -- Background rectangles for each enemy entry
local enemyTargetBackgrounds = {};  -- Background rectangles for target containers

-- Cache for truncated names to avoid expensive binary search every frame
-- Key: enemy index, Value: {name = original_name, maxWidth = width, fontHeight = height, truncated = result}
local truncatedNameCache = {};
local truncatedTargetNameCache = {};

-- Check if mob is valid and rendered (accepts optional cached entity manager)
local function GetIsValidMob(mobIdx, cachedEntityMgr)
	-- Use cached entity manager if provided, otherwise fetch it
	local entity = cachedEntityMgr or GetEntitySafe();
	if entity == nil then
		return false;
	end

	local renderflags = entity:GetRenderFlags0(mobIdx);
	if bit.band(renderflags, RENDER_FLAG_VISIBLE) ~= RENDER_FLAG_VISIBLE or bit.band(renderflags, RENDER_FLAG_HIDDEN) ~= 0 then
		return false;
	end
	return true;
end

-- Note: GetPartyMemberIds removed - now using IsPartyMemberByServerId from helpers.lua
-- which uses cached party data for O(1) lookups instead of rebuilding a table each call

-- Truncates text to fit within maxWidth using binary search for optimal performance
local function TruncateTextToFit(text, maxWidth, fontSize)
	-- First check if text fits without truncation
	local width, _ = imtext.Measure(text, fontSize);
	if width <= maxWidth then return text; end
	-- Text is too long, use binary search to find optimal truncation point
	local ellipsis = "...";
	-- Binary search for the longest substring that fits with ellipsis
	local left, right = 1, #text;
	local bestLength = 0;
	while left <= right do
		local mid = math.floor((left + right) / 2);
		local truncated = text:sub(1, mid) .. ellipsis;
		width, _ = imtext.Measure(truncated, fontSize);
		if width <= maxWidth then
			-- This length fits, try a longer one
			bestLength = mid;
			left = mid + 1;
		else
			-- This length is too long, try a shorter one
			right = mid - 1;
		end
	end
	if bestLength > 0 then return text:sub(1, bestLength) .. ellipsis; end
	-- Fallback: just ellipsis
	return ellipsis;
end

enemylist.DrawWindow = function(settings)

	-- Multi-column layout settings
	local rowsPerColumn = gConfig.enemyListRowsPerColumn or 8;
	local maxColumns = gConfig.enemyListMaxColumns or 1;
	local maxTotalEntries = rowsPerColumn * maxColumns;
	local rowSpacing = gConfig.enemyListRowSpacing or 5;
	local columnSpacing = gConfig.enemyListColumnSpacing or 10;

	-- Add margins to window width to prevent border/content clipping
	-- Width: left margin + (columns * barWidth) + ((columns-1) * columnSpacing) + right margin
	local singleColumnWidth = settings.barWidth;
	local windowWidth = (windowMargin * 2) + (singleColumnWidth * maxColumns) + (columnSpacing * (maxColumns - 1));
	imgui.SetNextWindowSize({ windowWidth, -1, }, ImGuiCond_Always);

	-- Handle position reset or restore
	if forcePositionReset then
		local defX, defY = defaultPositions.GetEnemyListPosition();
		imgui.SetNextWindowPos({defX, defY}, ImGuiCond_Always);
		forcePositionReset = false;
		hasAppliedSavedPosition = true;
		lastSavedPosX, lastSavedPosY = defX, defY;
	elseif not hasAppliedSavedPosition and gConfig.enemyListWindowPosX ~= nil then
		imgui.SetNextWindowPos({gConfig.enemyListWindowPosX, gConfig.enemyListWindowPosY}, ImGuiCond_Once);
		hasAppliedSavedPosition = true;
		lastSavedPosX = gConfig.enemyListWindowPosX;
		lastSavedPosY = gConfig.enemyListWindowPosY;
	end

	-- Draw the main target window
	local windowFlags = GetBaseWindowFlags(gConfig.lockPositions);

	-- Remove all ImGui padding so we have full control over layout
	imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {0, 0});
	imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {0, 0});
	imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {0, 0});

    ApplyWindowPosition('EnemyList');
	if (imgui.Begin('EnemyList', true, windowFlags)) then
		SaveWindowPosition('EnemyList');
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
			-- Swap to highlight the subtarget cursor (what you'll act on) instead of original target
			if (subTargetActive) then
				local tempTarget = targetIndex;
				targetIndex = subTargetIndex;
				subTargetIndex = tempTarget;
			end
		end

		-- Cache entity manager once per frame (avoid repeated GetEntitySafe() calls)
		local entityMgr = GetEntitySafe();

		-- Track previous active indices and reset for this frame
		local previousActiveIndices = activeEnemyIndices;
		activeEnemyIndices = {};

		-- Get draw list and configure imtext for this frame
		local drawList = GetUIDrawList();
		imtext.SetConfigFromSettings(settings.name_font_settings);

		-- Multi-column layout tracking
		local numTargets = 0;
		local currentColumn = 0;
		local currentRowInColumn = 0;
		local columnBaseX = winStartX;  -- Base X position for first column
		local columnBaseY = winStartY + windowMargin;  -- Base Y position (after top margin)
		local maxColumnHeight = 0;  -- Track tallest column for window sizing
		local currentColumnHeight = 0;

		-- Determine which data source to use (preview mode vs real enemies)
		local isPreviewMode = showConfig[1] and gConfig.enemyListPreview;
		local enemySource = isPreviewMode and previewEnemies or allClaimedTargets;

		for k,v in pairs(enemySource) do
			local ent;
			local isValid;
			if isPreviewMode then
				-- In preview mode, use mock entity data directly
				ent = v;
				isValid = true;
			else
				-- Normal mode: get real entity and validate
				ent = GetEntity(k);
				isValid = v ~= nil and ent ~= nil and GetIsValidMob(k, entityMgr) and ent.HPPercent > 0 and ent.Name ~= nil;
			end
			if isValid then
				-- Check if we need to start a new column
				if (currentRowInColumn >= rowsPerColumn and currentColumn < maxColumns - 1) then
					-- Move to next column
					currentColumn = currentColumn + 1;
					currentRowInColumn = 0;
					-- Track max height for window sizing
					if (currentColumnHeight > maxColumnHeight) then
						maxColumnHeight = currentColumnHeight;
					end
					currentColumnHeight = 0;
				end

				-- Add spacing between entries (but not before the first in each column)
				local entrySpacingY = 0;
				if (currentRowInColumn > 0) then
					entrySpacingY = rowSpacing;
				end

				-- ===== LAYOUT CALCULATION =====
				-- Calculate position based on current column and row
				-- Each column offset: (column index) * (barWidth + columnSpacing)
				local columnOffsetX = currentColumn * (singleColumnWidth + columnSpacing);
				local entryStartX = columnBaseX + windowMargin + columnOffsetX;
				local entryStartY = columnBaseY + currentColumnHeight + entrySpacingY;

				-- Set ImGui cursor for this entry
				imgui.SetCursorScreenPos({entryStartX - windowMargin, entryStartY});

				-- Entry width is the content area (barWidth), not including window margins
				local entryWidth = settings.barWidth;
				-- Scale padding and gaps based on bar dimensions to prevent negative sizes at low scales
				-- Base values at scale 1.0: padding=10, nameToBarGap=10, barToInfoGap=5
				local scaleX = entryWidth / 125;  -- 125 is the default barWidth
				local scaleY = settings.barHeight / 10;  -- 10 is the default barHeight
				local padding = math.max(10 * math.min(scaleX, scaleY), 2);  -- Minimum 2px padding
				local borderThickness = 2;

				-- Calculate entry dimensions
				-- Row 1: Name text (uses name_font_settings.font_height)
				-- Row 2: HP bar (full width, uses barHeight)
				-- Row 3: Distance (left) and HP% (right) - only if enabled
				local nameHeight = settings.name_font_settings.font_height;
				local barHeight = settings.barHeight;
				local nameToBarGap = math.max(10 * scaleY, 1);  -- Vertical spacing between name and HP bar
				local barToInfoGap = math.max(5 * scaleY, 1);  -- Vertical spacing between HP bar and info row

				-- Calculate info row height based only on enabled features
				local infoRowHeight = 0;
				if (gConfig.showEnemyDistance and gConfig.showEnemyHPPText) then
					-- Both enabled - use the max of both
					infoRowHeight = math.max(settings.distance_font_settings.font_height, settings.percent_font_settings.font_height);
				elseif (gConfig.showEnemyDistance) then
					-- Only distance enabled
					infoRowHeight = settings.distance_font_settings.font_height;
				elseif (gConfig.showEnemyHPPText) then
					-- Only HP% enabled
					infoRowHeight = settings.percent_font_settings.font_height;
				end

				-- Calculate total height based on which rows are visible
				local totalContentHeight = nameHeight + nameToBarGap + barHeight;
				if (infoRowHeight > 0) then
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

				-- HP bar is full width (ensure minimum of 1px to prevent negative/zero width)
				local barWidth = math.max(entryWidth - (padding * 2), 1);

				-- ===== BACKGROUND & BORDER RENDERING =====
				-- We need to draw these BEFORE the ImGui content so they appear behind progress bars

				-- Get entity name color based on type and claim status (ARGB format)
				local nameColor;
				if isPreviewMode then
					-- Use claimed enemy color for preview mode
					nameColor = gConfig.colorCustomization.shared.claimedColor or 0xFFE1A0FF;
				else
					nameColor = GetEntityNameColor(ent, k, gConfig.colorCustomization.shared);
				end

				if (gConfig.showEnemyListBorders) then
					local borderColor;
					if (subTargetIndex ~= nil and k == subTargetIndex) then
						-- Subtarget border - use configured color
						borderColor = imgui.GetColorU32(ARGBToRGBA(gConfig.colorCustomization.enemyList.subtargetBorderColor));
					elseif (targetIndex ~= nil and k == targetIndex) then
						-- Main target border - use configured color
						borderColor = imgui.GetColorU32(ARGBToRGBA(gConfig.colorCustomization.enemyList.targetBorderColor));
					elseif (gConfig.showEnemyListBordersUseNameColor) then
						borderColor = imgui.GetColorU32(ARGBToRGBA(nameColor));
					else
						borderColor = imgui.GetColorU32(ARGBToRGBA(gConfig.colorCustomization.enemyList.borderColor or 0xFF000000));
					end

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
				-- Primitives render in the correct layer (behind ImGui draw list)
				if (enemyBackgrounds[k] == nil and settings.prim_data) then
					enemyBackgrounds[k] = primitives.new(settings.prim_data);
					enemyBackgrounds[k].can_focus = false;
					enemyBackgrounds[k].locked = true;
				end

				if (enemyBackgrounds[k] ~= nil) then
					local bg = enemyBackgrounds[k];
					-- Set background position and size
					bg.position_x = entryStartX;
					bg.position_y = entryStartY;
					bg.width = entryWidth;
					bg.height = entryHeight;
					local bgColor = gConfig.colorCustomization.enemyList.backgroundColor;
					local bgOpacity = gConfig.enemyListBackgroundOpacity;
					if (bgOpacity ~= nil and bgOpacity < 1.0) then
						bgColor = ApplyOpacityToColor(bgColor, bgOpacity);
					end
					bg.color = bgColor;
					bg.visible = true;
				end

				-- ===== CONTENT RENDERING =====
				-- ROW 1: Enemy Name (colored based on entity type and claim status)
				local nameX = entryStartX + padding;
				local nameY = entryStartY + padding;

				-- Mark this enemy index as active for background visibility management
				activeEnemyIndices[k] = true;

				-- Truncate name to fit within available width (use cache to avoid per-frame binary search)
				local maxNameWidth = entryWidth - (padding * 2);
				local fontHeight = settings.name_font_settings.font_height;
				local nameCache = truncatedNameCache[k];
				local displayName;
				if nameCache and nameCache.name == ent.Name and nameCache.maxWidth == maxNameWidth and nameCache.fontHeight == fontHeight then
					-- Cache hit - reuse truncated name
					displayName = nameCache.truncated;
				else
					-- Cache miss - compute and store (font height affects text width measurement)
					displayName = TruncateTextToFit(ent.Name, maxNameWidth, fontHeight);
					truncatedNameCache[k] = {name = ent.Name, maxWidth = maxNameWidth, fontHeight = fontHeight, truncated = displayName};
				end

				imtext.Draw(drawList, displayName, nameX, nameY, nameColor, fontHeight);

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
						local distanceColor = gConfig.colorCustomization.enemyList.distanceTextColor;
						imtext.Draw(drawList, distanceText, entryStartX + padding, row3Y, distanceColor, settings.distance_font_settings.font_height);
					end

					-- HP% text (right-aligned): measure width first, then position from right edge
					if (gConfig.showEnemyHPPText) then
						local hpColor = gConfig.colorCustomization.enemyList.percentTextColor;
						local hpWidth, _ = imtext.Measure(hpText, settings.percent_font_settings.font_height);
						imtext.Draw(drawList, hpText, entryStartX + entryWidth - padding - hpWidth, row3Y, hpColor, settings.percent_font_settings.font_height);
					end
				end

				-- ===== DEBUFF ICONS =====
				-- Positioned at left or right of entry based on anchor setting (offset by user settings)
				if (gConfig.showEnemyListDebuffs) then
					local buffIds = nil;
					if isPreviewMode then
						-- Use preview debuff data
						buffIds = previewDebuffs[k];
					elseif entityMgr ~= nil then
						-- Use cached entity manager (avoid repeated GetEntitySafe() calls)
						buffIds = debuffHandler.GetActiveDebuffs(entityMgr:GetServerId(k));
					end
					if (buffIds ~= nil and #buffIds > 0) then
						local debuffX;
						local debuffY = entryStartY + settings.debuffOffsetY;
						local anchor = gConfig.enemyListDebuffsAnchor or 'right';

						if (anchor == 'right') then
							-- Right anchor: position to the right of the entry
							debuffX = entryStartX + entryWidth + settings.debuffOffsetX;
						else
							-- Left anchor: calculate width of debuff icons and position to the left of entry
							local numIcons = math.min(#buffIds, settings.maxIcons);
							local iconSpacing = 1; -- matches ImGuiStyleVar_ItemSpacing
							local debuffWidth = (numIcons * settings.iconSize) + ((numIcons - 1) * iconSpacing);
							debuffX = entryStartX - debuffWidth - settings.debuffOffsetX;
						end

						imgui.SetNextWindowPos({debuffX, debuffY});
						if (imgui.Begin('EnemyDebuffs'..k, true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoDocking))) then
							imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {1, 1});
							DrawStatusIcons(buffIds, settings.iconSize, settings.maxIcons, 1);
							imgui.PopStyleVar(1);
						end
						imgui.End();
					end
				end

				-- ===== ENEMY TARGET CONTAINER =====
				-- Show target's name in a separate container to the right
				if (gConfig.showEnemyListTargets) then
					local hasValidTarget = false;
					local targetName = nil;

					if isPreviewMode then
						-- Use preview target data
						targetName = previewTargets[k];
						hasValidTarget = targetName ~= nil;
					else
						-- Normal mode: get real target from action tracker
						local targetIdx = actionTracker.GetLastTarget(ent.ServerId);
						if (targetIdx ~= nil) then
							local targetEntity = GetEntity(targetIdx);
							if (targetEntity ~= nil and targetEntity.Name ~= nil) then
								targetName = targetEntity.Name;
								hasValidTarget = true;
							end
						end
					end

					if (hasValidTarget and targetName) then
						-- Position target container using configurable offsets
						local targetOffsetX = gConfig.enemyListTargetOffsetX or 10;
						local targetOffsetY = gConfig.enemyListTargetOffsetY or 0;
						local targetContainerX = entryStartX + entryWidth + targetOffsetX;
						local targetContainerY = entryStartY + targetOffsetY;

						-- Target container dimensions (configurable width)
						local targetWidth = gConfig.enemyListTargetWidth or 100;
						local targetPadding = 6;
						local targetNameHeight = settings.target_font_settings.font_height;
						local targetTotalHeight = (targetPadding * 2) + targetNameHeight;

						-- ===== PRIMITIVE BACKGROUND RENDERING =====
						-- Create/get background primitive for this target container
						if (enemyTargetBackgrounds[k] == nil and settings.prim_data) then
							enemyTargetBackgrounds[k] = primitives.new(settings.prim_data);
							enemyTargetBackgrounds[k].can_focus = false;
							enemyTargetBackgrounds[k].locked = true;
						end

						if (enemyTargetBackgrounds[k] ~= nil) then
							local targetBg = enemyTargetBackgrounds[k];
							targetBg.position_x = targetContainerX;
							targetBg.position_y = targetContainerY;
							targetBg.width = targetWidth;
							targetBg.height = targetTotalHeight;
							local targetBgColor = gConfig.colorCustomization.enemyList.targetBackgroundColor or gConfig.colorCustomization.enemyList.backgroundColor;
							local targetBgOpacity = gConfig.enemyListTargetBackgroundOpacity;
							if (targetBgOpacity ~= nil and targetBgOpacity < 1.0) then
								targetBgColor = ApplyOpacityToColor(targetBgColor, targetBgOpacity);
							end
							targetBg.color = targetBgColor;
							targetBg.visible = true;
						end

						-- Target name text
						local targetTextColor = gConfig.colorCustomization.enemyList.targetNameTextColor or 0xFFFFAA00;
						-- Truncate name to fit (use cache to avoid per-frame binary search)
						local maxTargetNameWidth = targetWidth - (targetPadding * 2);
						local targetFontHeight = settings.target_font_settings.font_height;
						local targetNameCache = truncatedTargetNameCache[k];
						local displayTargetName;
						if targetNameCache and targetNameCache.name == targetName and targetNameCache.maxWidth == maxTargetNameWidth and targetNameCache.fontHeight == targetFontHeight then
							-- Cache hit - reuse truncated name
							displayTargetName = targetNameCache.truncated;
						else
							-- Cache miss - compute and store (font height affects text width measurement)
							displayTargetName = TruncateTextToFit(targetName, maxTargetNameWidth, targetFontHeight);
							truncatedTargetNameCache[k] = {name = targetName, maxWidth = maxTargetNameWidth, fontHeight = targetFontHeight, truncated = displayTargetName};
						end

						imtext.Draw(drawList, displayTargetName, targetContainerX + targetPadding, targetContainerY + targetPadding, targetTextColor, targetFontHeight);
					else
						-- Hide target background if enemy has no valid target (prevents stale overlays)
						if (enemyTargetBackgrounds[k] ~= nil) then
							enemyTargetBackgrounds[k].visible = false;
						end
					end
				end

				-- Add a click target over the entire entry to /target that mob (disabled in limited mode, preview mode, config open, or by config)
				if (not HzLimitedMode and not isPreviewMode and not showConfig[1] and gConfig.enableEnemyListClickTarget) then
					imgui.SetCursorScreenPos({entryStartX, entryStartY});
					if imgui.InvisibleButton('EnemyEntry' .. k, {entryWidth, entryHeight}) then
						local clickEntityMgr = AshitaCore:GetMemoryManager():GetEntity();
						if clickEntityMgr ~= nil then
							local serverId = clickEntityMgr:GetServerId(k);
							if serverId ~= nil and serverId > 0 then
								AshitaCore:GetChatManager():QueueCommand(-1, '/target ' .. serverId);
							end
						end
					end
				end

				-- Update column height tracking (include spacing for next entry)
				currentColumnHeight = currentColumnHeight + entryHeight + entrySpacingY;
				currentRowInColumn = currentRowInColumn + 1;
				numTargets = numTargets + 1;

				-- Check if we've hit the max total entries
				if (numTargets >= maxTotalEntries) then
					break;
				end
			else
				-- Only remove invalid entries in normal mode (not preview mode)
				if not isPreviewMode then
					allClaimedTargets[k] = nil;
				end
			end
		end

		-- Hide backgrounds for enemies that were active last frame but not this frame
		-- Only iterate over previously active indices (avoids iterating all backgrounds)
		for enemyIndex in pairs(previousActiveIndices) do
			if not activeEnemyIndices[enemyIndex] then
				-- This enemy was visible last frame but not this frame - hide its backgrounds
				if enemyBackgrounds[enemyIndex] then
					enemyBackgrounds[enemyIndex].visible = false;
				end
				if enemyTargetBackgrounds[enemyIndex] then
					enemyTargetBackgrounds[enemyIndex].visible = false;
				end
			end
		end

		-- Hide target backgrounds for active enemies when showEnemyListTargets is disabled
		if not gConfig.showEnemyListTargets then
			for enemyIndex in pairs(activeEnemyIndices) do
				if enemyTargetBackgrounds[enemyIndex] then
					enemyTargetBackgrounds[enemyIndex].visible = false;
				end
			end
		end

		-- Update max height from last column
		if (currentColumnHeight > maxColumnHeight) then
			maxColumnHeight = currentColumnHeight;
		end

		-- Set cursor to ensure window encompasses all content (prevents clipping)
		-- Position at bottom-right of content area to force proper window sizing
		if (numTargets > 0) then
			imgui.SetCursorScreenPos({winStartX, columnBaseY + maxColumnHeight + windowMargin});
			imgui.Dummy({windowWidth, 0});
		end

		-- Save position if moved (with change detection to avoid spam)
		local winPosX, winPosY = imgui.GetWindowPos();
		if not gConfig.lockPositions then
			if lastSavedPosX == nil or
			   math.abs(winPosX - lastSavedPosX) > 1 or
			   math.abs(winPosY - lastSavedPosY) > 1 then
				gConfig.enemyListWindowPosX = winPosX;
				gConfig.enemyListWindowPosY = winPosY;
				lastSavedPosX = winPosX;
				lastSavedPosY = winPosY;
			end
		end
	end

	-- Restore ImGui style variables (must be before End() to avoid affecting other windows)
	imgui.PopStyleVar(3);
	imgui.End();
end

-- If a mob performs an action on us or a party member add it to the list
enemylist.HandleActionPacket = function(e)
	if (e == nil) then
		return;
	end
	if (GetIsMobByIndex(e.UserIndex) and GetIsValidMob(e.UserIndex)) then
		-- Use cached party lookup (O(1)) instead of rebuilding party list each packet
		for i = 0, #e.Targets do
			if (e.Targets[i] ~= nil and IsPartyMemberByServerId(e.Targets[i].Id)) then
				allClaimedTargets[e.UserIndex] = 1;
				break;  -- Found a party member target, no need to check more
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
		-- Use cached party lookup (O(1)) instead of rebuilding party list each packet
		if IsPartyMemberByServerId(e.newClaimId) then
			allClaimedTargets[e.monsterIndex] = 1;
		end
	end
end

enemylist.HandleZonePacket = function(e)
	-- Empty all our claimed targets on zone
	allClaimedTargets = T{};

	-- Clear background primitives on zone
	for k, v in pairs(enemyBackgrounds) do
		if (v ~= nil) then v:destroy(); end
	end
	enemyBackgrounds = {};
	for k, v in pairs(enemyTargetBackgrounds) do
		if (v ~= nil) then v:destroy(); end
	end
	enemyTargetBackgrounds = {};

	-- Reset active indices and name caches
	activeEnemyIndices = {};
	truncatedNameCache = {};
	truncatedTargetNameCache = {};
end

enemylist.Initialize = function(settings)
	-- Initialization is handled dynamically in DrawWindow
end

enemylist.UpdateVisuals = function(settings)
	imtext.Reset();
	truncatedNameCache = {};
	truncatedTargetNameCache = {};
end

enemylist.SetHidden = function(hidden)
	if hidden then
		-- Hide all background primitives
		for _, bgObj in pairs(enemyBackgrounds) do
			bgObj.visible = false;
		end
		for _, bgObj in pairs(enemyTargetBackgrounds) do
			bgObj.visible = false;
		end
		-- Clear active indices so next DrawWindow starts fresh
		activeEnemyIndices = {};
	end
end

enemylist.Cleanup = function()
	-- Destroy all background primitives
	for k, v in pairs(enemyBackgrounds) do
		if (v ~= nil) then v:destroy(); end
	end
	for k, v in pairs(enemyTargetBackgrounds) do
		if (v ~= nil) then v:destroy(); end
	end

	-- Clear all tables
	enemyBackgrounds = {};
	enemyTargetBackgrounds = {};
	activeEnemyIndices = {};
	truncatedNameCache = {};
	truncatedTargetNameCache = {};
end

enemylist.ResetPositions = function()
	forcePositionReset = true;
	hasAppliedSavedPosition = false;
end

return enemylist;
