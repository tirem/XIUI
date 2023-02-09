require('common');
require('libs/bitmap');
local imgui = require('imgui');
local ffi = require('ffi');
local d3d = require('d3d8');
local d3d8dev = d3d.get_device();

local IMGUI_COL_WHITE = imgui.GetColorU32({1, 1, 1, 1});
local IMGUI_COL_BLACK = imgui.GetColorU32({0, 0, 0, 1});

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

function hex2rgb(hex)
    local hex = hex:gsub("#","")

    if hex:len() == 3 then
      return {(tonumber("0x"..hex:sub(1,1))*17), (tonumber("0x"..hex:sub(2,2))*17), (tonumber("0x"..hex:sub(3,3))*17)}
    else
      return {tonumber("0x"..hex:sub(1,2)), tonumber("0x"..hex:sub(3,4)), tonumber("0x"..hex:sub(5,6))}
    end
end

function MakeGradientBitmap(startColor, endColor)
	local height = 100;

	local image = bitmap:new(1, height);

	startColor = hex2rgb(startColor);
	endColor = hex2rgb(endColor);

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

progressbar.DrawBar = function(startPosition, endPosition, gradientStart, gradientEnd, rounding)
	if not rounding then
		rounding = 0;
	end

	local gradient = GetGradient(gradientStart, gradientEnd);

	imgui.GetWindowDrawList():AddImageRounded(gradient, startPosition, endPosition, {0, 0}, {1, 1}, IMGUI_COL_WHITE, rounding);
end

progressbar.DrawBookends = function(positionStartX, positionStartY, width, height)
	local bookendTexture = GetBookendTexture();
	
	local bookendWidth = height / 2;
	
	-- Draw the left bookend
	imgui.GetWindowDrawList():AddImage(bookendTexture, {positionStartX, positionStartY}, {positionStartX + bookendWidth, positionStartY + height}, {0, 0}, {1, 1}, IMGUI_COL_WHITE);
	
	-- Draw the right bookend
	imgui.GetWindowDrawList():AddImage(bookendTexture, {positionStartX + width - bookendWidth, positionStartY}, {positionStartX + width, positionStartY + height}, {1, 1}, {0, 0}, IMGUI_COL_WHITE);
end

progressbar.ProgressBar  = function(percentList, dimensions, decorate, overlayBar)
	-- Decorate by default
	if decorate == nil then
		decorate = true;
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
	
	-- Draw the bookends!
	if decorate then
		local bookendWidth = height / 2;
		
		contentWidth = width - (bookendWidth * 2);
		contentPositionStartX = contentPositionStartX + bookendWidth;
		
		progressbar.DrawBookends(positionStartX, positionStartY, width, height);
	end
	
	-- Draw the background
	progressbar.DrawBar({contentPositionStartX, contentPositionStartY}, {contentPositionStartX + contentWidth, contentPositionStartY + height}, progressbar.backgroundGradientStartColor, progressbar.backgroundGradientEndColor, progressbar.backgroundRounding);
	
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
		
		if percent > 0 then
			local startColor = percentData[2][1];
			local endColor = percentData[2][2];
			
			local progressWidth = progressTotalWidth * percent;
			
			progressbar.DrawBar({progressPositionStartX + progressOffset, progressPositionStartY}, {progressPositionStartX + progressOffset + progressWidth, progressPositionStartY + progressHeight}, startColor, endColor, progressbar.foregroundRounding);
			
			progressOffset = progressOffset + progressWidth;
		end
	end

	-- Draw the optional overlay bar (used for TP)
	if overlayBar then
		local overlayPercent = overlayBar[1][1];
		local overlayGradientStart = overlayBar[1][2][1];
		local overlayGradientEnd = overlayBar[1][2][2];
		local overlayHeight = overlayBar[2];
		local overlayTopPadding = overlayBar[3];

		local overlayWidth = progressTotalWidth;

		-- Draw the overlay background
		progressbar.DrawBar({progressPositionStartX, progressPositionStartY + progressHeight - overlayHeight}, {progressPositionStartX + overlayWidth, progressPositionStartY + progressHeight}, progressbar.backgroundGradientStartColor, progressbar.backgroundGradientEndColor, progressbar.backgroundRounding);

		-- Draw the overlay progress bar
		local overlayProgressWidth = overlayWidth * overlayPercent;

		progressbar.DrawBar({progressPositionStartX, progressPositionStartY + progressHeight - overlayHeight + overlayTopPadding}, {progressPositionStartX + overlayProgressWidth, progressPositionStartY + progressHeight}, overlayGradientStart, overlayGradientEnd, progressbar.foregroundRounding);
	end
	
	imgui.Dummy({width, height});
end

return progressbar;