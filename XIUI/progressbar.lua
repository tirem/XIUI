require('common');
require('libs/bitmap');
require('libs/color');
local imgui = require('imgui');
local ffi = require('ffi');
local d3d = require('d3d8');
local d3d8dev = d3d.get_device();

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

	gradientTextures = {}
};

-- Helper function to extract RGBA from hex string (supports #RRGGBB or #RRGGBBAA)
local function hex2rgba(hex)
	local hex = hex:gsub("#", "");
	local r = tonumber("0x"..hex:sub(1,2));
	local g = tonumber("0x"..hex:sub(3,4));
	local b = tonumber("0x"..hex:sub(5,6));
	local a = 255;
	if #hex == 8 then
		a = tonumber("0x"..hex:sub(7,8));
	end
	return r, g, b, a;
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
	local texture;

	for i, existingTexture in ipairs(progressbar.gradientTextures) do
		if (existingTexture.startColor == startColor and existingTexture.endColor == endColor and existingTexture.midColor == nil) then
			texture = existingTexture;
			break;
		end
	end

	if not texture then
		local image = MakeGradientBitmap(startColor, endColor);

		local texture_ptr = ffi.new('IDirect3DTexture8*[1]');

		local res = ffi.C.D3DXCreateTextureFromFileInMemory(d3d8dev, image:binary(), #image:binary(), texture_ptr);

		if (res ~= ffi.C.S_OK) then
			return nil;
		end

		texture = {
			startColor = startColor,
			endColor = endColor,
			midColor = nil,
			texture = ffi.new('IDirect3DTexture8*', texture_ptr[0])
		}

		d3d.gc_safe_release(texture.texture);

		table.insert(progressbar.gradientTextures, texture);
	end

	if texture == nil or texture.texture == nil then
		return nil;
	end

	return tonumber(ffi.cast("uint32_t", texture.texture));
end

function GetThreeStepGradient(startColor, midColor, endColor)
	local texture;

	for i, existingTexture in ipairs(progressbar.gradientTextures) do
		if (existingTexture.startColor == startColor and existingTexture.midColor == midColor and existingTexture.endColor == endColor) then
			texture = existingTexture;
			break;
		end
	end

	if not texture then
		local image = MakeThreeStepGradientBitmap(startColor, midColor, endColor);

		local texture_ptr = ffi.new('IDirect3DTexture8*[1]');

		local res = ffi.C.D3DXCreateTextureFromFileInMemory(d3d8dev, image:binary(), #image:binary(), texture_ptr);

		if (res ~= ffi.C.S_OK) then
			return nil;
		end

		texture = {
			startColor = startColor,
			midColor = midColor,
			endColor = endColor,
			texture = ffi.new('IDirect3DTexture8*', texture_ptr[0])
		}

		d3d.gc_safe_release(texture.texture);

		table.insert(progressbar.gradientTextures, texture);
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

progressbar.DrawBar = function(startPosition, endPosition, gradientStart, gradientEnd, rounding, cornerFlags)
	if not rounding then
		rounding = 0;
	end

	local gradient = GetGradient(gradientStart, gradientEnd);
	if gradient == nil then
		return;
	end

	imgui.GetWindowDrawList():AddImageRounded(gradient, startPosition, endPosition, {0, 0}, {1, 1}, IM_COL32_WHITE, rounding, cornerFlags);
end

progressbar.DrawColoredBar = function(startPosition, endPosition, color, rounding, cornerFlags)
	if not rounding then
		rounding = 0;
	end

	imgui.GetWindowDrawList():AddRectFilled(startPosition, endPosition, color, rounding, cornerFlags);
end

progressbar.DrawBookends = function(positionStartX, positionStartY, width, height)
	-- Bookend width is user-controlled, radius is half the height for proper curves
	local bookendWidth = gConfig and gConfig.bookendSize or 10;
	local radius = height / 2;
	local draw_list = imgui.GetWindowDrawList();

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
	draw_list:AddImageRounded(
		gradientTexture,
		{positionStartX, positionStartY},
		{positionStartX + bookendWidth, positionStartY + height},
		{0, 0}, {1, 1},
		IM_COL32_WHITE,
		radius,
		ImDrawCornerFlags_Left
	);

	-- Draw right bookend (rounded rectangle on right side)
	draw_list:AddImageRounded(
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

	-- Decorate by default
	if options.decorate == nil then
		options.decorate = true;
	end

	-- Apply global showBookends setting (master switch)
	if gConfig and gConfig.showBookends == false then
		options.decorate = false;
	end

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
		-- Bookend width must match DrawBookends calculation
		local bookendWidth = gConfig and gConfig.bookendSize or 10;

		contentWidth = width - (bookendWidth * 2);
		contentPositionStartX = contentPositionStartX + bookendWidth;

		progressbar.DrawBookends(positionStartX, positionStartY, width, height);
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
	progressbar.DrawBar({contentPositionStartX, contentPositionStartY}, {contentPositionStartX + contentWidth, contentPositionStartY + height}, bgGradientStart, bgGradientEnd, rounding);
	
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
			progressbar.DrawBar({progressPositionStartX + progressOffset, progressPositionStartY}, {progressPositionStartX + progressOffset + progressWidth, progressPositionStartY + progressHeight}, startColor, endColor, rounding, cornerFlags);

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
				progressbar.DrawColoredBar({progressPositionStartX + progressOffset, progressPositionStartY}, {progressPositionStartX + progressOffset + overlayWidth, progressPositionStartY + progressHeight}, overlayBarColor, rounding, cornerFlags);
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
		progressbar.DrawBar({progressPositionStartX, progressPositionStartY + progressHeight - overlayHeight}, {progressPositionStartX + overlayWidth, progressPositionStartY + progressHeight}, progressbar.backgroundGradientStartColor, progressbar.backgroundGradientEndColor, rounding);

		-- Draw the overlay progress bar
		local overlayProgressWidth = overlayWidth * overlayPercent;

		rounding = options.decorate and progressbar.foregroundRounding or gConfig.noBookendRounding;
		progressbar.DrawBar({progressPositionStartX, progressPositionStartY + progressHeight - overlayHeight + overlayTopPadding}, {progressPositionStartX + overlayProgressWidth, progressPositionStartY + progressHeight}, overlayGradientStart, overlayGradientEnd, rounding);

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
			progressbar.DrawColoredBar({progressPositionStartX, progressPositionStartY + progressHeight - overlayHeight + overlayTopPadding}, {progressPositionStartX + overlayProgressWidth, progressPositionStartY + progressHeight}, pulseBarColor, rounding);
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
	local bgR, bgG, bgB, bgA = hex2rgba(borderColor);
	local bgColorU32 = imgui.GetColorU32({bgR / 255, bgG / 255, bgB / 255, bgA / 255});

	local draw_list = GetUIDrawList();

	-- Draw enhanced border if specified (middle and outer layers)
	if options.enhancedBorder then
		local accentColor = options.enhancedBorder; -- ARGB color
		local accentColorU32 = imgui.GetColorU32(ARGBToImGui(accentColor));

		-- Border thickness values
		local innerBorderThickness = gConfig.barBorderThickness or 2;
		local middleBorderThickness = 2;
		local outerBorderThickness = 1;

		-- Calculate offsets
		local innerOffset = innerBorderThickness / 2;
		local middleOffset = innerOffset + innerBorderThickness;
		local outerOffset = middleOffset + middleBorderThickness / 2;

		-- Draw outermost background border (1px)
		draw_list:AddRect(
			{positionStartX - outerOffset, positionStartY - outerOffset},
			{positionStartX + width + outerOffset, positionStartY + height + outerOffset},
			bgColorU32,
			baseRounding + outerOffset,
			15, -- all corners
			outerBorderThickness
		);

		-- Draw middle accent color border (2px)
		draw_list:AddRect(
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
		draw_list:AddRect(
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
		imgui.Dummy({width, height});
	end
end

return progressbar;