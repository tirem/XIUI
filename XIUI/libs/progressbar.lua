require('common');
require('libs/bitmap');
local colorLib = require('libs.color');
local memory = require('libs.memory');
local imgui = require('imgui');
local ffi = require('ffi');
local d3d = require('d3d8');

local progressbar = {
	-- Bookend
	bookendFilename = 'bookend',

	-- Background
	backgroundGradientStartColor = '#01122b',
	backgroundGradientEndColor = '#061c39',
	backgroundRounding = 0,

	-- Foreground
	foregroundRounding = 3,
	foregroundPadding = 5,

	-- Gradient texture cache (hash table for O(1) lookup)
	gradientTexturesByKey = {},
	-- Legacy array for cleanup (maintains references)
	gradientTextures = {},

	-- Cached U32 colors to avoid per-frame conversions
	colorU32Cache = {},

	-- Cache management settings
	MAX_GRADIENT_CACHE_SIZE = 50,  -- Maximum number of gradient textures before eviction
	EVICTION_COUNT = 10,           -- Number of oldest entries to remove when cache is full

	-- Cache statistics for debugging
	stats = {
		hits = 0,
		misses = 0,
		evictions = 0,
		totalCreated = 0,
	},
};

-- Use shared hex2rgba from color library
local hex2rgba = colorLib.hex2rgba;
local hex2rgb = colorLib.hex2rgb;

-- Cached hex to U32 conversion (avoids per-frame table allocation)
local function GetCachedColorU32(hexColor)
	local cached = progressbar.colorU32Cache[hexColor];
	if cached then
		return cached;
	end
	local r, g, b, a = hex2rgba(hexColor);
	cached = imgui.GetColorU32({r / 255, g / 255, b / 255, a / 255});
	progressbar.colorU32Cache[hexColor] = cached;
	return cached;
end

-- Pre-allocated tables for ImGui calls (avoids per-frame allocations)
local reusablePos1 = {0, 0};
local reusablePos2 = {0, 0};
local reusableUV1 = {0, 0};
local reusableUV2 = {1, 1};

-- Helper to set position table values (avoids creating new tables)
local function setPos(tbl, x, y)
	tbl[1] = x;
	tbl[2] = y;
	return tbl;
end

-- Evict oldest entries when cache exceeds size limit
-- Uses lastUsed timestamp for LRU-style eviction
local function EvictOldestEntries()
	local count = #progressbar.gradientTextures;
	if count <= progressbar.MAX_GRADIENT_CACHE_SIZE then
		return;  -- No eviction needed
	end

	-- Sort by lastUsed timestamp (oldest first)
	table.sort(progressbar.gradientTextures, function(a, b)
		return (a.lastUsed or 0) < (b.lastUsed or 0);
	end);

	-- Remove oldest entries
	local toRemove = math.min(progressbar.EVICTION_COUNT, count - progressbar.MAX_GRADIENT_CACHE_SIZE + progressbar.EVICTION_COUNT);
	for i = 1, toRemove do
		local entry = progressbar.gradientTextures[1];
		if entry then
			-- Remove from hash table
			local key = entry.cacheKey;
			if key then
				progressbar.gradientTexturesByKey[key] = nil;
			end
			-- Remove from array (shift remaining entries)
			table.remove(progressbar.gradientTextures, 1);
			progressbar.stats.evictions = progressbar.stats.evictions + 1;
		end
	end
end

function MakeGradientBitmap(startColor, endColor)
	local height = 100;

	local image = bitmap:new(1, height);

	local sr, sg, sb, sa = hex2rgba(startColor);
	local er, eg, eb, ea = hex2rgba(endColor);

	for pixel = 1, height  do
		local red = sr + (er - sr) * (pixel / height);
		local green = sg + (eg - sg) * (pixel / height);
		local blue = sb + (eb - sb) * (pixel / height);
		local alpha = sa + (ea - sa) * (pixel / height);

		image:setPixelColor(1, (height - pixel) + 1, {red, green, blue, alpha});
	end

	return image;
end

function MakeThreeStepGradientBitmap(startColor, midColor, endColor)
	local height = 100;

	local image = bitmap:new(1, height);

	local sr, sg, sb, sa = hex2rgba(startColor);
	local mr, mg, mb, ma = hex2rgba(midColor);
	local er, eg, eb, ea = hex2rgba(endColor);

	for pixel = 1, height do
		local red, green, blue, alpha;
		local progress = pixel / height;

		if progress <= 0.5 then
			-- First half: interpolate from start to mid
			local t = progress * 2; -- 0 to 1
			red = sr + (mr - sr) * t;
			green = sg + (mg - sg) * t;
			blue = sb + (mb - sb) * t;
			alpha = sa + (ma - sa) * t;
		else
			-- Second half: interpolate from mid to end
			local t = (progress - 0.5) * 2; -- 0 to 1
			red = mr + (er - mr) * t;
			green = mg + (eg - mg) * t;
			blue = mb + (eb - mb) * t;
			alpha = ma + (ea - ma) * t;
		end

		image:setPixelColor(1, (height - pixel) + 1, {red, green, blue, alpha});
	end

	return image;
end

function GetGradient(startColor, endColor)
	-- O(1) hash lookup instead of O(n) linear search
	local cacheKey = startColor .. '|' .. endColor;
	local texture = progressbar.gradientTexturesByKey[cacheKey];

	if texture then
		-- Cache hit - update last used timestamp
		texture.lastUsed = os.clock();
		progressbar.stats.hits = progressbar.stats.hits + 1;
	else
		-- Cache miss - create new texture
		progressbar.stats.misses = progressbar.stats.misses + 1;

		local device = memory.GetD3D8Device();
		if (device == nil) then return nil; end

		local image = MakeGradientBitmap(startColor, endColor);

		local texture_ptr = ffi.new('IDirect3DTexture8*[1]');

		local res = ffi.C.D3DXCreateTextureFromFileInMemory(device, image:binary(), #image:binary(), texture_ptr);

		if (res ~= ffi.C.S_OK) then
			return nil;
		end

		texture = {
			startColor = startColor,
			endColor = endColor,
			midColor = nil,
			texture = ffi.new('IDirect3DTexture8*', texture_ptr[0]),
			cacheKey = cacheKey,
			lastUsed = os.clock(),
		}

		d3d.gc_safe_release(texture.texture);

		-- Store in both hash table (for lookup) and array (for cleanup)
		progressbar.gradientTexturesByKey[cacheKey] = texture;
		table.insert(progressbar.gradientTextures, texture);
		progressbar.stats.totalCreated = progressbar.stats.totalCreated + 1;

		-- Check if we need to evict old entries
		EvictOldestEntries();
	end

	if texture == nil or texture.texture == nil then
		return nil;
	end

	return tonumber(ffi.cast("uint32_t", texture.texture));
end

function GetThreeStepGradient(startColor, midColor, endColor)
	-- O(1) hash lookup instead of O(n) linear search
	local cacheKey = startColor .. '|' .. midColor .. '|' .. endColor;
	local texture = progressbar.gradientTexturesByKey[cacheKey];

	if texture then
		-- Cache hit - update last used timestamp
		texture.lastUsed = os.clock();
		progressbar.stats.hits = progressbar.stats.hits + 1;
	else
		-- Cache miss - create new texture
		progressbar.stats.misses = progressbar.stats.misses + 1;

		local device = memory.GetD3D8Device();
		if (device == nil) then return nil; end

		local image = MakeThreeStepGradientBitmap(startColor, midColor, endColor);

		local texture_ptr = ffi.new('IDirect3DTexture8*[1]');

		local res = ffi.C.D3DXCreateTextureFromFileInMemory(device, image:binary(), #image:binary(), texture_ptr);

		if (res ~= ffi.C.S_OK) then
			return nil;
		end

		texture = {
			startColor = startColor,
			midColor = midColor,
			endColor = endColor,
			texture = ffi.new('IDirect3DTexture8*', texture_ptr[0]),
			cacheKey = cacheKey,
			lastUsed = os.clock(),
		}

		d3d.gc_safe_release(texture.texture);

		-- Store in both hash table (for lookup) and array (for cleanup)
		progressbar.gradientTexturesByKey[cacheKey] = texture;
		table.insert(progressbar.gradientTextures, texture);
		progressbar.stats.totalCreated = progressbar.stats.totalCreated + 1;

		-- Check if we need to evict old entries
		EvictOldestEntries();
	end

	if texture == nil or texture.texture == nil then
		return nil;
	end

	return tonumber(ffi.cast("uint32_t", texture.texture));
end

function GetBookendTexture()
	if not progressbar.bookendTexture then
		local loaded = LoadTexture(progressbar.bookendFilename);
		if loaded == nil or loaded.image == nil then
			return nil;
		end
		progressbar.bookendTexture = loaded.image;
	end

	if progressbar.bookendTexture == nil then
		return nil;
	end

	return tonumber(ffi.cast("uint32_t", progressbar.bookendTexture));
end

progressbar.DrawBar = function(startPosition, endPosition, gradientStart, gradientEnd, rounding, cornerFlags, drawList)
	if not rounding then
		rounding = 0;
	end

	local gradient = GetGradient(gradientStart, gradientEnd);
	if gradient == nil then
		return;
	end

	drawList = drawList or imgui.GetWindowDrawList();
	drawList:AddImageRounded(gradient, startPosition, endPosition, {0, 0}, {1, 1}, IM_COL32_WHITE, rounding, cornerFlags);
end

progressbar.DrawColoredBar = function(startPosition, endPosition, color, rounding, cornerFlags, drawList)
	if not rounding then
		rounding = 0;
	end

	drawList = drawList or imgui.GetWindowDrawList();
	drawList:AddRectFilled(startPosition, endPosition, color, rounding, cornerFlags);
end

progressbar.DrawBookends = function(positionStartX, positionStartY, width, height, drawList)
	-- Bookend width needs to be at least half the height for proper semicircular caps
	-- User setting is a base/minimum, but we scale up if bar height requires it
	local baseBookendWidth = gConfig and gConfig.bookendSize or 10;
	local radius = height / 2;
	-- Bookend width must accommodate the full radius for proper rounded caps
	local bookendWidth = math.max(baseBookendWidth, radius);
	drawList = drawList or imgui.GetWindowDrawList();

	-- Get bookend gradient colors (default: dark blue gradient)
	local gradientStart = '#1a2a4a';
	local gradientMid = '#2d4a7c';
	local gradientEnd = '#1a2a4a';

	-- Apply custom colors if available from global config
	if gConfig and gConfig.colorCustomization and gConfig.colorCustomization.shared and gConfig.colorCustomization.shared.bookendGradient then
		local bookendSettings = gConfig.colorCustomization.shared.bookendGradient;
		gradientStart = bookendSettings.start or gradientStart;
		gradientMid = bookendSettings.mid or gradientMid;
		gradientEnd = bookendSettings.stop or gradientEnd;
	end

	-- Get the 3-step gradient texture
	local gradientTexture = GetThreeStepGradient(gradientStart, gradientMid, gradientEnd);
	if gradientTexture == nil then
		return;
	end

	-- Draw left bookend (rounded rectangle on left side)
	-- Note: The main progress bar border encompasses the bookends, so no separate outline is needed
	drawList:AddImageRounded(
		gradientTexture,
		{positionStartX, positionStartY},
		{positionStartX + bookendWidth, positionStartY + height},
		{0, 0}, {1, 1},
		IM_COL32_WHITE,
		radius,
		ImDrawCornerFlags_Left
	);

	-- Draw right bookend (rounded rectangle on right side)
	drawList:AddImageRounded(
		gradientTexture,
		{positionStartX + width - bookendWidth, positionStartY},
		{positionStartX + width, positionStartY + height},
		{0, 0}, {1, 1},
		IM_COL32_WHITE,
		radius,
		ImDrawCornerFlags_Right
	);
end

progressbar.ProgressBar  = function(percentList, dimensions, options)
	if options == nil then
		options = {};
	end

	-- Default to false if not specified
	if options.decorate == nil then
		options.decorate = false;
	end

	-- Get custom draw list if provided, otherwise use window draw list
	local drawList = options.drawList or imgui.GetWindowDrawList();

	-- Get position from options or cursor
	local positionStartX, positionStartY;
	if options.absolutePosition then
		positionStartX = options.absolutePosition[1];
		positionStartY = options.absolutePosition[2];
	else
		positionStartX, positionStartY = imgui.GetCursorScreenPos();
	end

	local width = dimensions[1];
	local height = dimensions[2];

	-- If our width is 0 or less, we instead get the content region's available space
	-- which allows us to stretch the progress bar to fit the content region.
	if width <= 0 then
		width = imgui.GetContentRegionAvail();
	end

	local contentWidth = width;
	local contentPositionStartX = positionStartX;
	local contentPositionStartY = positionStartY;
	local rounding;

	-- Draw the bookends!
	if options.decorate then
		-- Bookend width must match DrawBookends calculation (scales with bar height)
		local baseBookendWidth = gConfig and gConfig.bookendSize or 10;
		local bookendWidth = math.max(baseBookendWidth, height / 2);

		contentWidth = width - (bookendWidth * 2);
		contentPositionStartX = contentPositionStartX + bookendWidth;

		progressbar.DrawBookends(positionStartX, positionStartY, width, height, drawList);
	end
	
	-- Draw the background
	local bgGradientStart = progressbar.backgroundGradientStartColor;
	local bgGradientEnd = progressbar.backgroundGradientEndColor;

	-- Apply custom background gradient if available
	if gConfig and gConfig.colorCustomization and gConfig.colorCustomization.shared.backgroundGradient then
		local bgSettings = gConfig.colorCustomization.shared.backgroundGradient;
		bgGradientStart = bgSettings.start;
		-- If gradient disabled, use same color for both (static color)
		bgGradientEnd = bgSettings.enabled and bgSettings.stop or bgSettings.start;
	end

	if options.backgroundGradientOverride then
		bgGradientStart = options.backgroundGradientOverride[1];
		bgGradientEnd = options.backgroundGradientOverride[2];
	end

	rounding = options.decorate and progressbar.backgroundRounding or gConfig.noBookendRounding;
	progressbar.DrawBar({contentPositionStartX, contentPositionStartY}, {contentPositionStartX + contentWidth, contentPositionStartY + height}, bgGradientStart, bgGradientEnd, rounding, nil, drawList);
	
	-- Compute the actual progress bar's width and height
	local paddingHalf = progressbar.foregroundPadding / 2;
	
	local progressPositionStartX = contentPositionStartX + paddingHalf;
	local progressPositionStartY = contentPositionStartY + paddingHalf;
	
	local progressTotalWidth = contentWidth - progressbar.foregroundPadding;
	local progressHeight = height - progressbar.foregroundPadding;
	
	-- Draw the progress bar(s)
	local progressOffset = 0;
	
	for i, percentData in ipairs(percentList) do
		local percent = math.clamp(percentData[1], 0, 1);

		local cornerFlags = ImDrawCornerFlags_All;

		if #percentList > 1 then
			if i == 1 then
				cornerFlags = ImDrawCornerFlags_Left;
			elseif i == #percentList then
				cornerFlags = ImDrawCornerFlags_Right;
			else
				cornerFlags = ImDrawCornerFlags_None;
			end
		end
		
		if percent > 0 then
			local startColor = percentData[2][1];
			local endColor = percentData[2][2];
			local overlayConfiguration = percentData[3];
			
			local progressWidth = progressTotalWidth * percent;
			
			rounding = options.decorate and progressbar.foregroundRounding or gConfig.noBookendRounding;
			progressbar.DrawBar({progressPositionStartX + progressOffset, progressPositionStartY}, {progressPositionStartX + progressOffset + progressWidth, progressPositionStartY + progressHeight}, startColor, endColor, rounding, cornerFlags, drawList);

			if overlayConfiguration then
				local overlayColor = overlayConfiguration[1];
				local overlayAlpha = overlayConfiguration[2];
				-- local overlayPercent = overlayConfiguration[3];

				local overlayWidth = progressWidth;
				local overlayCornerFlags = cornerFlags;

				--[[
				if overlayPercent then
					overlayWidth = progressTotalWidth * overlayPercent;
					overlayCornerFlags = ImDrawCornerFlags_None;
				end
				]]--

				local red, green, blue = hex2rgb(overlayColor);

				local overlayBarColor = imgui.GetColorU32({red / 255, green / 255, blue / 255, overlayAlpha});

				rounding = options.decorate and progressbar.foregroundRounding or gConfig.noBookendRounding;
				progressbar.DrawColoredBar({progressPositionStartX + progressOffset, progressPositionStartY}, {progressPositionStartX + progressOffset + overlayWidth, progressPositionStartY + progressHeight}, overlayBarColor, rounding, cornerFlags, drawList);
			end

			progressOffset = progressOffset + progressWidth;
		end
	end

	-- Draw the optional overlay bar (used for TP)
	if options.overlayBar then
		local overlayPercent = options.overlayBar[1][1];
		local overlayGradientStart = options.overlayBar[1][2][1];
		local overlayGradientEnd = options.overlayBar[1][2][2];
		local overlayHeight = options.overlayBar[2];
		local overlayTopPadding = options.overlayBar[3];

		local overlayWidth = progressTotalWidth;

		-- Draw the overlay background
		rounding = options.decorate and progressbar.backgroundRounding or gConfig.noBookendRounding;
		progressbar.DrawBar({progressPositionStartX, progressPositionStartY + progressHeight - overlayHeight}, {progressPositionStartX + overlayWidth, progressPositionStartY + progressHeight}, progressbar.backgroundGradientStartColor, progressbar.backgroundGradientEndColor, rounding, nil, drawList);

		-- Draw the overlay progress bar
		local overlayProgressWidth = overlayWidth * overlayPercent;

		rounding = options.decorate and progressbar.foregroundRounding or gConfig.noBookendRounding;
		progressbar.DrawBar({progressPositionStartX, progressPositionStartY + progressHeight - overlayHeight + overlayTopPadding}, {progressPositionStartX + overlayProgressWidth, progressPositionStartY + progressHeight}, overlayGradientStart, overlayGradientEnd, rounding, nil, drawList);

		-- Allow optional pulsing of overlay bars
		local pulseConfiguration = options.overlayBar[4];

		if pulseConfiguration then
			local currentTime = os.clock();
			local timePerPulse = pulseConfiguration[2];
			local phase = currentTime % timePerPulse;
			local pulseAlpha = (2 / timePerPulse) * phase;

			if pulseAlpha > 1 then
				pulseAlpha = 2 - pulseAlpha;
			end

			local pulseColor = pulseConfiguration[1];
			local red, green, blue = hex2rgb(pulseColor);

			local pulseBarColor = imgui.GetColorU32({red / 255, green / 255, blue / 255, pulseAlpha});

			rounding = options.decorate and progressbar.foregroundRounding or gConfig.noBookendRounding;
			progressbar.DrawColoredBar({progressPositionStartX, progressPositionStartY + progressHeight - overlayHeight + overlayTopPadding}, {progressPositionStartX + overlayProgressWidth, progressPositionStartY + progressHeight}, pulseBarColor, rounding, nil, drawList);
		end
	end

	-- Draw default border and optional enhanced border
	-- All progress bars get a 2px background-colored border by default
	-- Enhanced border adds a middle colored layer and outer background layer (for lock-on, etc.)
	local baseRounding = options.decorate and (height / 2) or (gConfig.noBookendRounding or 0);

	-- Get border color: use override if provided, otherwise fall back to background color
	local borderColor = progressbar.backgroundGradientStartColor;
	if options.borderColorOverride then
		borderColor = options.borderColorOverride;
	elseif gConfig and gConfig.colorCustomization and gConfig.colorCustomization.shared and gConfig.colorCustomization.shared.backgroundGradient then
		borderColor = gConfig.colorCustomization.shared.backgroundGradient.start;
	end
	local bgColorU32 = GetCachedColorU32(borderColor);

	-- Draw enhanced border if specified (middle and outer layers)
	if options.enhancedBorder then
		local accentColor = options.enhancedBorder; -- ARGB color
		local accentColorU32 = ARGBToU32(accentColor);

		-- Border thickness values
		local innerBorderThickness = gConfig.barBorderThickness or 2;
		local middleBorderThickness = 2;
		local outerBorderThickness = 1;

		-- Calculate offsets
		local innerOffset = innerBorderThickness / 2;
		local middleOffset = innerOffset + innerBorderThickness;
		local outerOffset = middleOffset + middleBorderThickness / 2;

		-- Draw outermost background border (1px)
		drawList:AddRect(
			{positionStartX - outerOffset, positionStartY - outerOffset},
			{positionStartX + width + outerOffset, positionStartY + height + outerOffset},
			bgColorU32,
			baseRounding + outerOffset,
			15, -- all corners
			outerBorderThickness
		);

		-- Draw middle accent color border (2px)
		drawList:AddRect(
			{positionStartX - middleOffset, positionStartY - middleOffset},
			{positionStartX + width + middleOffset, positionStartY + height + middleOffset},
			accentColorU32,
			baseRounding + middleOffset,
			15, -- all corners
			middleBorderThickness
		);
	end

	-- Draw default inner background border - always drawn for all bars (unless thickness is 0)
	local innerBorderThickness = gConfig.barBorderThickness or 2;
	if innerBorderThickness > 0 then
		local innerOffset = innerBorderThickness / 2;
		drawList:AddRect(
			{positionStartX - innerOffset, positionStartY - innerOffset},
			{positionStartX + width + innerOffset, positionStartY + height + innerOffset},
			bgColorU32,
			baseRounding + innerOffset,
			15, -- all corners
			innerBorderThickness
		);
	end

	-- Only call Dummy if we're using cursor positioning (affects layout)
	-- Skip Dummy when using absolute positioning (doesn't affect layout)
	if not options.absolutePosition then
		-- Calculate border extent to prevent clipping
		-- Borders extend outward from bar edges by this amount
		local borderExtent = 0;
		if options.enhancedBorder then
			-- Enhanced border has multiple layers extending outward
			local middleBorderThickness = 2;
			local innerOffset = innerBorderThickness / 2;
			local middleOffset = innerOffset + innerBorderThickness;
			borderExtent = middleOffset + middleBorderThickness / 2;
		elseif innerBorderThickness > 0 then
			borderExtent = innerBorderThickness / 2;
		end
		-- Add border extent to width/height to prevent right/bottom clipping
		imgui.Dummy({width + borderExtent, height + borderExtent});
	end
end

-- ============================================
-- Cache Management Functions
-- ============================================

-- Cleanup all cached textures (call on addon unload)
function progressbar.Cleanup()
	-- Clear gradient caches
	progressbar.gradientTexturesByKey = {};
	progressbar.gradientTextures = {};

	-- Clear color cache
	progressbar.colorU32Cache = {};

	-- Clear bookend texture
	progressbar.bookendTexture = nil;

	-- Reset stats
	progressbar.stats = {
		hits = 0,
		misses = 0,
		evictions = 0,
		totalCreated = 0,
	};

	-- Force garbage collection to release D3D textures
	collectgarbage('collect');
end

-- Get cache statistics for debugging
function progressbar.GetCacheStats()
	local cacheSize = #progressbar.gradientTextures;
	local hitRate = 0;
	local totalRequests = progressbar.stats.hits + progressbar.stats.misses;
	if totalRequests > 0 then
		hitRate = (progressbar.stats.hits / totalRequests) * 100;
	end

	return {
		cacheSize = cacheSize,
		maxSize = progressbar.MAX_GRADIENT_CACHE_SIZE,
		hits = progressbar.stats.hits,
		misses = progressbar.stats.misses,
		evictions = progressbar.stats.evictions,
		totalCreated = progressbar.stats.totalCreated,
		hitRate = hitRate,
		colorCacheSize = 0,  -- Count color cache entries
	};
end

-- Print cache statistics to chat
function progressbar.PrintCacheStats()
	local stats = progressbar.GetCacheStats();

	-- Count color cache entries
	local colorCount = 0;
	for _ in pairs(progressbar.colorU32Cache) do
		colorCount = colorCount + 1;
	end

	print('[XIUI] Progressbar Cache Stats:');
	print(string.format('  Gradient Textures: %d / %d (max)', stats.cacheSize, stats.maxSize));
	print(string.format('  Color Cache: %d entries', colorCount));
	print(string.format('  Total Created: %d', stats.totalCreated));
	print(string.format('  Evictions: %d', stats.evictions));
	print(string.format('  Hits: %d, Misses: %d (%.1f%% hit rate)', stats.hits, stats.misses, stats.hitRate));
end

-- Stress test: create N random gradient textures to test cache limits
-- Usage: /xiui stresscache 100
function progressbar.StressTestCache(count)
	count = count or 100;
	print(string.format('[XIUI] Stress testing gradient cache with %d random gradients...', count));

	local startStats = progressbar.GetCacheStats();
	local startTime = os.clock();

	-- Generate random hex colors
	local function randomHex()
		return string.format('#%02x%02x%02x',
			math.random(0, 255),
			math.random(0, 255),
			math.random(0, 255)
		);
	end

	-- Create random gradients
	for i = 1, count do
		local color1 = randomHex();
		local color2 = randomHex();
		GetGradient(color1, color2);
	end

	local endTime = os.clock();
	local endStats = progressbar.GetCacheStats();

	print(string.format('[XIUI] Stress test complete in %.3f seconds', endTime - startTime));
	print(string.format('  Created: %d new textures', endStats.totalCreated - startStats.totalCreated));
	print(string.format('  Evicted: %d textures', endStats.evictions - startStats.evictions));
	print(string.format('  Final cache size: %d / %d', endStats.cacheSize, endStats.maxSize));
end

-- Force clear cache (for testing)
function progressbar.ForceClearCache()
	local beforeSize = #progressbar.gradientTextures;
	progressbar.Cleanup();
	print(string.format('[XIUI] Cleared %d gradient textures from cache', beforeSize));
end

return progressbar;