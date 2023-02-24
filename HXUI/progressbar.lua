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

function MakeGradientBitmap(startColor, endColor)
	local height = 100;

	local image = bitmap:new(1, height);

	startColor = table.pack(hex2rgb(startColor));
	endColor = table.pack(hex2rgb(endColor));

	for pixel = 1, height  do
		local red = startColor[1] + (endColor[1] - startColor[1]) * (pixel / height);
		local green = startColor[2] + (endColor[2] - startColor[2]) * (pixel / height);
		local blue = startColor[3] + (endColor[3] - startColor[3]) * (pixel / height);

		image:setPixelColor(1, (height - pixel) + 1, {red, green, blue, 255});
	end

	return image;
end

function GetGradient(startColor, endColor)
	local texture;

	for i, existingTexture in ipairs(progressbar.gradientTextures) do
		if (existingTexture.startColor == startColor and existingTexture.endColor == endColor) then
			texture = existingTexture;
			break;
		end
	end

	if not texture then
		local image = MakeGradientBitmap(startColor, endColor);

    local texture_ptr = ffi.new('IDirect3DTexture8*[1]');

    local res = ffi.C.D3DXCreateTextureFromFileInMemory(d3d8dev, image:binary(), #image:binary(), texture_ptr);

    if (res ~= ffi.C.S_OK) then
        error(('%08X (%s)'):fmt(res, d3d.get_error(res)));
    end

    texture = {
    	startColor = startColor,
    	endColor = endColor,
    	texture = ffi.new('IDirect3DTexture8*', texture_ptr[0])
    }

    d3d.gc_safe_release(texture.texture);

    table.insert(progressbar.gradientTextures, texture);
	end

	return tonumber(ffi.cast("uint32_t", texture.texture));
end

function GetBookendTexture()
	if not progressbar.bookendTexture then
		progressbar.bookendTexture = LoadTexture(progressbar.bookendFilename).image;
	end

	return tonumber(ffi.cast("uint32_t", progressbar.bookendTexture));
end

progressbar.DrawBar = function(startPosition, endPosition, gradientStart, gradientEnd, rounding, cornerFlags)
	if not rounding then
		rounding = 0;
	end

	local gradient = GetGradient(gradientStart, gradientEnd);

	imgui.GetWindowDrawList():AddImageRounded(gradient, startPosition, endPosition, {0, 0}, {1, 1}, IM_COL32_WHITE, rounding, cornerFlags);
end

progressbar.DrawColoredBar = function(startPosition, endPosition, color, rounding, cornerFlags)
	if not rounding then
		rounding = 0;
	end

	imgui.GetWindowDrawList():AddRectFilled(startPosition, endPosition, color, rounding, cornerFlags);
end

progressbar.DrawBookends = function(positionStartX, positionStartY, width, height)
	local bookendTexture = GetBookendTexture();
	
	local bookendWidth = height / 2;
	
	-- Draw the left bookend
	imgui.GetWindowDrawList():AddImage(bookendTexture, {positionStartX, positionStartY}, {positionStartX + bookendWidth, positionStartY + height}, {0, 0}, {1, 1}, IM_COL32_WHITE);
	
	-- Draw the right bookend
	imgui.GetWindowDrawList():AddImage(bookendTexture, {positionStartX + width - bookendWidth, positionStartY}, {positionStartX + width, positionStartY + height}, {1, 1}, {0, 0}, IM_COL32_WHITE);
end

progressbar.ProgressBar  = function(percentList, dimensions, options)
	if options == nil then
		options = {};
	end

	-- Decorate by default
	if options.decorate == nil then
		options.decorate = true;
	end
	
	local positionStartX, positionStartY = imgui.GetCursorScreenPos();
	
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
		local bookendWidth = height / 2;
		
		contentWidth = width - (bookendWidth * 2);
		contentPositionStartX = contentPositionStartX + bookendWidth;
		
		progressbar.DrawBookends(positionStartX, positionStartY, width, height);
	end
	
	-- Draw the background
	local bgGradientStart = progressbar.backgroundGradientStartColor;
	local bgGradientEnd = progressbar.backgroundGradientEndColor;

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

	if options.borderConfig then
		local borderWidth = options.borderConfig[1];
		local borderColorRed, borderColorGreen, borderColorBlue = hex2rgb(options.borderConfig[2]);
		rounding = options.decorate and height/2 or gConfig.noBookendRounding;
		imgui.GetWindowDrawList():AddRect({positionStartX - (borderWidth / 2), positionStartY - (borderWidth / 2)}, {positionStartX + width + (borderWidth / 2), positionStartY + height + (borderWidth / 2)}, imgui.GetColorU32({borderColorRed / 255, borderColorGreen / 255, borderColorBlue / 255, 1}), rounding, ImDrawCornerFlags_All, borderWidth);
	end
	
	imgui.Dummy({width, height});
end

return progressbar;