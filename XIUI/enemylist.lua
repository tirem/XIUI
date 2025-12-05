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

-- Font objects for enemy list (keyed by numeric enemy index for O(1) lookup)
local enemyNameFonts = {};  -- Enemy name font objects
local enemyDistanceFonts = {};  -- Distance text font objects
local enemyHPFonts = {};  -- HP% text font objects
local enemyTargetFonts = {};  -- Target name font objects

-- Track which enemy indices are currently active (for efficient visibility management)
local activeEnemyIndices = {};  -- Set of currently rendered enemy indices

-- Cache last set colors to avoid expensive SetColor() calls every frame
local enemyNameColorCache = {};
local enemyDistanceColorCache = {};  -- Cache for distance font colors
local enemyHPColorCache = {};  -- Cache for HP font colors

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

	-- Draw the main target window
	local windowFlags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoBringToFrontOnFocus, ImGuiWindowFlags_NoDocking);
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

		-- Cache entity manager once per frame (avoid repeated GetEntitySafe() calls)
		local entityMgr = GetEntitySafe();

		-- Track previous active indices and reset for this frame
		local previousActiveIndices = activeEnemyIndices;
		activeEnemyIndices = {};

		-- Multi-column layout tracking
		local numTargets = 0;
		local currentColumn = 0;
		local currentRowInColumn = 0;
		local columnBaseX = winStartX;  -- Base X position for first column
		local columnBaseY = winStartY + windowMargin;  -- Base Y position (after top margin)
		local maxColumnHeight = 0;  -- Track tallest column for window sizing
		local currentColumnHeight = 0;

		for k,v in pairs(allClaimedTargets) do
			local ent = GetEntity(k);
			-- Pass cached entityMgr to GetIsValidMob to avoid redundant GetEntitySafe() call
			if (v ~= nil and ent ~= nil and GetIsValidMob(k, entityMgr) and ent.HPPercent > 0 and ent.Name ~= nil) then
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
				-- Use numeric key directly for O(1) lookup (no string concatenation)
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
					-- Set semi-transparent black color (ARGB format)
					-- Alpha is the first byte: 0.4 * 255 = 102 = 0x66
					bg.color = 0x66000000;  -- Semi-transparent black
					bg.visible = true;
				end

				-- ===== CONTENT RENDERING =====
				-- ROW 1: Enemy Name (colored based on entity type and claim status)
				local nameX = entryStartX + padding;
				local nameY = entryStartY + padding;

				-- Mark this enemy index as active for efficient visibility management
				activeEnemyIndices[k] = true;

				-- Use numeric key directly for O(1) lookup (no string concatenation)
				if (enemyNameFonts[k] == nil) then
					-- Use FontManager for cleaner font creation
					enemyNameFonts[k] = FontManager.create(settings.name_font_settings);
				end
				local nameFont = enemyNameFonts[k];
				-- Dynamically set font height based on settings (avoids expensive font recreation)
				nameFont:set_font_height(settings.name_font_settings.font_height);
				nameFont:set_position_x(nameX);
				nameFont:set_position_y(nameY);

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
					displayName = TruncateTextToFit(nameFont, ent.Name, maxNameWidth);
					truncatedNameCache[k] = {name = ent.Name, maxWidth = maxNameWidth, fontHeight = fontHeight, truncated = displayName};
				end
				nameFont:set_text(displayName);

				-- Only call set_font_color if the color has changed (expensive operation for GDI fonts)
				if (enemyNameColorCache[k] ~= nameColor) then
					nameFont:set_font_color(nameColor);
					enemyNameColorCache[k] = nameColor;
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
						-- Use numeric key directly for O(1) lookup (no string concatenation)
						if (enemyDistanceFonts[k] == nil) then
							-- Use FontManager for cleaner font creation
							enemyDistanceFonts[k] = FontManager.create(settings.distance_font_settings);
						end
						local distanceFont = enemyDistanceFonts[k];
						-- Dynamically set font height based on settings (avoids expensive font recreation)
						distanceFont:set_font_height(settings.distance_font_settings.font_height);
						-- Only call set_font_color if the color has changed (expensive operation for GDI fonts)
						local distanceColor = gConfig.colorCustomization.enemyList.distanceTextColor;
						if (enemyDistanceColorCache[k] ~= distanceColor) then
							distanceFont:set_font_color(distanceColor);
							enemyDistanceColorCache[k] = distanceColor;
						end
						distanceFont:set_position_x(entryStartX + padding);
						distanceFont:set_position_y(row3Y);
						distanceFont:set_text(distanceText);
						distanceFont:set_visible(true);
					end

					-- HP% text (right-aligned)
					if (gConfig.showEnemyHPPText) then
						-- Use numeric key directly for O(1) lookup (no string concatenation)
						if (enemyHPFonts[k] == nil) then
							-- Use FontManager for cleaner font creation
							enemyHPFonts[k] = FontManager.create(settings.percent_font_settings);
						end
						local hpFont = enemyHPFonts[k];
						-- Dynamically set font height based on settings (avoids expensive font recreation)
						hpFont:set_font_height(settings.percent_font_settings.font_height);
						-- Only call set_font_color if the color has changed (expensive operation for GDI fonts)
						local hpColor = gConfig.colorCustomization.enemyList.percentTextColor;
						if (enemyHPColorCache[k] ~= hpColor) then
							hpFont:set_font_color(hpColor);
							enemyHPColorCache[k] = hpColor;
						end
						hpFont:set_text(hpText);

						-- Right-align: set position to right edge, font alignment handles the rest
						hpFont:set_position_x(entryStartX + entryWidth - padding);
						hpFont:set_position_y(row3Y);
						hpFont:set_visible(true);
					end
				end

				-- ===== DEBUFF ICONS =====
				-- Positioned at top-left or top-right of entry (offset by user settings)
				if (gConfig.showEnemyListDebuffs) then
					local buffIds = nil;
					-- Use cached entity manager (avoid repeated GetEntitySafe() calls)
					if entityMgr ~= nil then
						buffIds = debuffHandler.GetActiveDebuffs(entityMgr:GetServerId(k));
					end
					if (buffIds ~= nil and #buffIds > 0) then
						local debuffX;
						local debuffY = entryStartY + settings.debuffOffsetY;

						if (gConfig.enemyListDebuffsRightAlign) then
							-- Right-aligned: calculate width of debuff icons and position from right edge
							local numIcons = math.min(#buffIds, settings.maxIcons);
							local iconSpacing = 1; -- matches ImGuiStyleVar_ItemSpacing
							local debuffWidth = (numIcons * settings.iconSize) + ((numIcons - 1) * iconSpacing);
							debuffX = entryStartX + entryWidth - debuffWidth - settings.debuffOffsetX;
						else
							-- Left-aligned: position from left edge
							debuffX = entryStartX + settings.debuffOffsetX;
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
							-- Use numeric key directly for O(1) lookup (no string concatenation)
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
								-- Semi-transparent black (0.4 alpha * 255 = 102 = 0x66)
								targetBg.color = 0x66000000;
								targetBg.visible = true;
							end

							-- Target name
							-- Use numeric key directly for O(1) lookup (no string concatenation)
							if (enemyTargetFonts[k] == nil) then
								local targetFontSettings = deep_copy_table(settings.name_font_settings);
								targetFontSettings.font_alignment = gdi.Alignment.Left;
								targetFontSettings.font_color = 0xFFFFAA00;
								enemyTargetFonts[k] = FontManager.create(targetFontSettings);
							end
							local targetFont = enemyTargetFonts[k];
							targetFont:set_font_height(settings.name_font_settings.font_height);
							targetFont:set_position_x(targetContainerX + targetPadding);
							targetFont:set_position_y(targetContainerY + targetPadding);
							-- Truncate name to fit (use cache to avoid per-frame binary search)
							local maxTargetNameWidth = targetWidth - (targetPadding * 2);
							local targetFontHeight = settings.name_font_settings.font_height;
							local targetNameCache = truncatedTargetNameCache[k];
							local displayTargetName;
							if targetNameCache and targetNameCache.name == targetEntity.Name and targetNameCache.maxWidth == maxTargetNameWidth and targetNameCache.fontHeight == targetFontHeight then
								-- Cache hit - reuse truncated name
								displayTargetName = targetNameCache.truncated;
							else
								-- Cache miss - compute and store (font height affects text width measurement)
								displayTargetName = TruncateTextToFit(targetFont, targetEntity.Name, maxTargetNameWidth);
								truncatedTargetNameCache[k] = {name = targetEntity.Name, maxWidth = maxTargetNameWidth, fontHeight = targetFontHeight, truncated = displayTargetName};
							end
							targetFont:set_text(displayTargetName);
							targetFont:set_visible(true);
						end
					end
				end

				-- Add a click target over the entire entry to /target that mob (disabled in limited mode or by config)
				if (not HzLimitedMode and gConfig.enableEnemyListClickTarget) then
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
				allClaimedTargets[k] = nil;
			end
		end

		-- Hide font objects and backgrounds for enemies that were active last frame but not this frame
		-- Only iterate over indices that were previously active (O(previous_count) instead of O(all_fonts))
		-- No regex parsing needed since we use numeric keys directly
		for enemyIndex in pairs(previousActiveIndices) do
			if not activeEnemyIndices[enemyIndex] then
				-- This enemy was visible last frame but not this frame - hide all its elements
				if enemyNameFonts[enemyIndex] then
					enemyNameFonts[enemyIndex]:set_visible(false);
				end
				if enemyDistanceFonts[enemyIndex] then
					enemyDistanceFonts[enemyIndex]:set_visible(false);
				end
				if enemyHPFonts[enemyIndex] then
					enemyHPFonts[enemyIndex]:set_visible(false);
				end
				if enemyBackgrounds[enemyIndex] then
					enemyBackgrounds[enemyIndex].visible = false;
				end
				if enemyTargetBackgrounds[enemyIndex] then
					enemyTargetBackgrounds[enemyIndex].visible = false;
				end
				if enemyTargetFonts[enemyIndex] then
					enemyTargetFonts[enemyIndex]:set_visible(false);
				end
			end
		end

		-- Hide optional elements for active enemies when their features are disabled
		for enemyIndex in pairs(activeEnemyIndices) do
			-- Hide distance fonts when showEnemyDistance is disabled
			if not gConfig.showEnemyDistance and enemyDistanceFonts[enemyIndex] then
				enemyDistanceFonts[enemyIndex]:set_visible(false);
			end
			-- Hide HP% fonts when showEnemyHPPText is disabled
			if not gConfig.showEnemyHPPText and enemyHPFonts[enemyIndex] then
				enemyHPFonts[enemyIndex]:set_visible(false);
			end
			-- Hide target elements when showEnemyListTargets is disabled
			if not gConfig.showEnemyListTargets then
				if enemyTargetBackgrounds[enemyIndex] then
					enemyTargetBackgrounds[enemyIndex].visible = false;
				end
				if enemyTargetFonts[enemyIndex] then
					enemyTargetFonts[enemyIndex]:set_visible(false);
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

	-- Reset color caches, name caches, and active indices tracking
	enemyNameColorCache = {};
	enemyDistanceColorCache = {};
	enemyHPColorCache = {};
	activeEnemyIndices = {};
	truncatedNameCache = {};
	truncatedTargetNameCache = {};
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
	enemyDistanceColorCache = {};
	enemyHPColorCache = {};

	-- Reset active indices and name caches
	activeEnemyIndices = {};
	truncatedNameCache = {};
	truncatedTargetNameCache = {};
end

enemylist.SetHidden = function(hidden)
	if hidden then
		-- Hide all font objects
		for _, fontObj in pairs(enemyNameFonts) do
			fontObj:set_visible(false);
		end
		for _, fontObj in pairs(enemyDistanceFonts) do
			fontObj:set_visible(false);
		end
		for _, fontObj in pairs(enemyHPFonts) do
			fontObj:set_visible(false);
		end
		for _, fontObj in pairs(enemyTargetFonts) do
			fontObj:set_visible(false);
		end
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
	enemyDistanceColorCache = {};
	enemyHPColorCache = {};
	activeEnemyIndices = {};
	truncatedNameCache = {};
	truncatedTargetNameCache = {};
end

return enemylist;
