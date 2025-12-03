-- HSV conversion logic taken from @EmmanuelOga
-- https://github.com/EmmanuelOga/columns/blob/master/utils/color.lua

--[[
 * Converts an RGB color value to HSV. Conversion formula
 * adapted from http://en.wikipedia.org/wiki/HSV_color_space.
 * Assumes r, g, and b are contained in the set [0, 255] and
 * returns h, s, and v in the set [0, 1].
 *
 * @param   Number  r       The red color value
 * @param   Number  g       The green color value
 * @param   Number  b       The blue color value
 * @return  Array           The HSV representation
]]
function rgbToHsv(r, g, b)
  local max, min = math.max(r, g, b), math.min(r, g, b)
  local h, s, v
  v = max

  local d = max - min
  if max == 0 then s = 0 else s = d / max end

  if max == min then
    h = 0 -- achromatic
  else
    if max == r then
    h = (g - b) / d
    if g < b then h = h + 6 end
    elseif max == g then h = (b - r) / d + 2
    elseif max == b then h = (r - g) / d + 4
    end
    h = h / 6
  end

  return h, s, v
end

--[[
 * Converts an HSV color value to RGB. Conversion formula
 * adapted from http://en.wikipedia.org/wiki/HSV_color_space.
 * Assumes h, s, and v are contained in the set [0, 1] and
 * returns r, g, and b in the set [0, 255].
 *
 * @param   Number  h       The hue
 * @param   Number  s       The saturation
 * @param   Number  v       The value
 * @return  Array           The RGB representation
]]
function hsvToRgb(h, s, v)
  local r, g, b

  local i = math.floor(h * 6);
  local f = h * 6 - i;
  local p = v * (1 - s);
  local q = v * (1 - f * s);
  local t = v * (1 - (1 - f) * s);

  i = i % 6

  if i == 0 then r, g, b = v, t, p
  elseif i == 1 then r, g, b = q, v, p
  elseif i == 2 then r, g, b = p, v, t
  elseif i == 3 then r, g, b = p, q, v
  elseif i == 4 then r, g, b = t, p, v
  elseif i == 5 then r, g, b = v, p, q
  end

  return r, g, b
end

function hex2rgb(hex)
  local hex = hex:gsub("#","")
  
  return tonumber("0x"..hex:sub(1,2)), tonumber("0x"..hex:sub(3,4)), tonumber("0x"..hex:sub(5,6))
end

function rgb2hex(red, green, blue)
  return string.format('#%02x%02x%02x', red, green, blue);
end

function shiftSaturationAndBrightness(hex, saturationPercent, brightnessPercent)
  local red, green, blue = hex2rgb(hex);

  local hue, saturation, brightness = rgbToHsv(red / 255, green / 255, blue / 255);

  saturation = math.min(1, saturation * (1 + saturationPercent));
  brightness = math.min(1, saturation * (1 + brightnessPercent));

  red, green, blue = hsvToRgb(hue, saturation, brightness);

  return rgb2hex(red * 255, green * 255, blue * 255);
end

function shiftGradient(gradientTable, saturationPercent, brightnessPercent)
  return {
    shiftSaturationAndBrightness(gradientTable[1], saturationPercent, brightnessPercent),
    shiftSaturationAndBrightness(gradientTable[2], saturationPercent, brightnessPercent)
  };
end