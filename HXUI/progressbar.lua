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

	textures = {}
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

	for i, existingTexture in ipairs(progressbar.textures) do
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

	    table.insert(progressbar.textures, texture);
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
	local gradient = GetGradient(gradientStart, gradientEnd);

	imgui.GetWindowDrawList():AddImageRounded(gradient, startPosition, endPosition, {0, 0}, {1, 1}, IMGUI_COL_WHITE, rounding);
end

progressbar.ProgressBar = function(percent, dimensions, fgGradStart, fgGradEnd)
	local width = dimensions[1];

	if width < 0 then
		width = imgui.GetContentRegionAvail();
	end

	local height = dimensions[2];

	local positionStartX, positionStartY = imgui.GetCursorScreenPos();

	-- Draw the left bookend
	local bookendTexture = GetBookendTexture();

	local bookendWidth = height / 2;
	local bookendHeight = height;

	imgui.GetWindowDrawList():AddImage(bookendTexture, {positionStartX, positionStartY}, {positionStartX + bookendWidth, positionStartY + bookendHeight}, {0, 0}, {1, 1}, IMGUI_COL_WHITE);

	positionStartX = positionStartX + bookendWidth;

	-- Draw the background
	local positionEndX = positionStartX + width - (height / 2) - bookendWidth;
	local positionEndY = positionStartY + height;

	progressbar.DrawBar({positionStartX, positionStartY}, {positionEndX, positionEndY}, progressbar.backgroundGradientStartColor, progressbar.backgroundGradientEndColor, progressbar.backgroundRounding);

	-- Draw the foreground
	if (percent > 0) then
		local paddingHalf = progressbar.foregroundPadding / 2;

		local progressPositionStartX = positionStartX + paddingHalf;
		local progressPositionEndX = positionStartX + paddingHalf + ((width - progressbar.foregroundPadding - (bookendWidth * 2)) * percent);
		local progressPositionStartY = positionStartY + paddingHalf;
		local progressPositionEndY = positionEndY - paddingHalf;

		progressbar.DrawBar({progressPositionStartX, progressPositionStartY}, {progressPositionEndX, progressPositionEndY}, fgGradStart, fgGradEnd, progressbar.foregroundRounding);
	end

	-- Draw the right bookend
	imgui.GetWindowDrawList():AddImage(bookendTexture, {positionEndX, positionEndY}, {positionEndX + bookendWidth, positionEndY - bookendHeight}, {1, 1}, {0, 0}, IMGUI_COL_WHITE);

	imgui.Dummy({width, height});
end

return progressbar;