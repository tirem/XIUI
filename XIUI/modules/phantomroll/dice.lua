--[[
* Procedural die: total numeral, flames on lucky/11, icicles on unlucky.
]]--

local imgui = require('imgui');
local imtext = require('libs.imtext');

local M = {};

local PALETTE = {
    shadow      = { 0.02, 0.03, 0.04, 0.22 },
    face        = { 0.949, 0.945, 0.925, 1.00 },
    faceLow     = { 0.808, 0.796, 0.769, 1.00 },
    faceHot     = { 1.000, 0.945, 0.855, 1.00 },
    faceHotLow  = { 0.898, 0.812, 0.671, 1.00 },
    faceCold    = { 0.878, 0.937, 0.988, 1.00 },
    faceColdLow = { 0.706, 0.804, 0.882, 1.00 },
    faceBust    = { 0.361, 0.114, 0.129, 0.95 },
    faceBustLow = { 0.239, 0.070, 0.082, 0.95 },
    edge        = { 0.290, 0.310, 0.330, 0.80 },
    edgeHot     = { 1.000, 0.620, 0.180, 0.95 },
    edgeCold    = { 0.451, 0.765, 0.976, 0.95 },
    glowHot     = { 1.000, 0.500, 0.120, 0.13 },
    glowCold    = { 0.300, 0.650, 1.000, 0.13 },
    flameOut    = { 0.980, 0.400, 0.075, 0.70 },
    flameIn     = { 1.000, 0.855, 0.330, 0.90 },
    iceOut      = { 0.451, 0.749, 0.949, 0.80 },
    iceIn       = { 0.898, 0.973, 1.000, 0.92 },
};

local NUMERAL = {
    normal = 0xFF143441,
    bust   = 0xFFFFC7C2,
};

local STYLES = {
    bust   = { face = 'faceBust',  shade = 'faceBustLow', numeral = 'bust',   edge = 'edge' },
    hot    = { face = 'faceHot',   shade = 'faceHotLow',  numeral = 'normal', edge = 'edgeHot',  glow = 'glowHot' },
    cold   = { face = 'faceCold',  shade = 'faceColdLow', numeral = 'normal', edge = 'edgeCold', glow = 'glowCold' },
    normal = { face = 'face',      shade = 'faceLow',     numeral = 'normal', edge = 'edge' },
};

M.Color = function(entry, alphaScale)
    return imgui.GetColorU32({ entry[1], entry[2], entry[3], entry[4] * (alphaScale or 1) });
end

M.CenteredText = function(drawList, text, centerX, centerY, size, argbColor)
    if text == nil or text == '' then return; end
    local width, height = imtext.Measure(text, size);
    imtext.Draw(drawList, text, centerX - width / 2, centerY - height / 2, argbColor, size);
end

-- Face already has contrast; global bold/outline turns the numeral into a blob.
local function DrawNumeral(drawList, text, boxX, boxY, boxSize, fontSize, argbColor, fontSettings)
    imtext.SetConfig(fontSettings.font_family or 'Tahoma', false, 0);

    local width, height = imtext.Measure(text, fontSize);
    imtext.DrawSimple(drawList, text,
        boxX + math.floor((boxSize - width) / 2 + 0.5),
        boxY + math.floor(boxSize * 0.45 - height / 2 + 0.5),
        argbColor, fontSize);

    imtext.SetConfigFromSettings(fontSettings);
end

local function FaceText(state)
    if state.total == nil then return '?', 0.50; end

    local text = tostring(state.total);
    return text, (#text > 1) and 0.47 or 0.58;
end

local function DrawGlow(drawList, x, y, size, colorKey, pulse)
    local centerX, centerY = x + size / 2, y + size / 2;
    for ring = 1, 4 do
        local radius = size * (0.62 + ring * 0.11) * (0.97 + pulse * 0.06);
        drawList:AddCircleFilled({ centerX, centerY }, radius, M.Color(PALETTE[colorKey], 1 - ring * 0.18), 24);
    end
end

local function DrawFlames(drawList, x, y, size, clock)
    local baseY = y + size * 0.10;
    for i = 1, 5 do
        local phase = clock * 5.5 + i * 1.9;
        local flicker = math.sin(phase);
        local flameX = x + size * (0.16 + 0.17 * (i - 1));
        local width = size * (0.11 + 0.02 * math.cos(phase * 1.3));
        local height = size * (0.28 + 0.10 * flicker);  -- keep tips under the roll name
        local tipX = flameX + flicker * width * 0.5;

        drawList:AddTriangleFilled(
            { flameX - width, baseY }, { flameX + width, baseY }, { tipX, baseY - height },
            M.Color(PALETTE.flameOut));
        drawList:AddTriangleFilled(
            { flameX - width * 0.5, baseY }, { flameX + width * 0.5, baseY }, { tipX, baseY - height * 0.55 },
            M.Color(PALETTE.flameIn));
    end
end

local function DrawIcicles(drawList, x, y, size, clock)
    local baseY = y + size * 0.93;
    local lengths = { 0.26, 0.17, 0.30, 0.15, 0.23 };

    for i = 1, 5 do
        local phase = clock * 1.5 + i * 2.3;
        local shimmer = math.sin(phase);
        local iceX = x + size * (0.17 + 0.165 * (i - 1));
        local width = size * (0.072 + 0.010 * math.cos(phase));
        local length = size * (lengths[i] + 0.02 * shimmer);

        drawList:AddTriangleFilled(
            { iceX - width, baseY }, { iceX + width, baseY }, { iceX, baseY + length },
            M.Color(PALETTE.iceOut));
        drawList:AddTriangleFilled(
            { iceX - width * 0.42, baseY }, { iceX + width * 0.42, baseY }, { iceX, baseY + length * 0.62 },
            M.Color(PALETTE.iceIn, 0.75 + shimmer * 0.2));
    end
end

local EFFECTS = { hot = DrawFlames, cold = DrawIcicles };

-- Stacked layers read as a soft drop; one hard offset looks like a smear.
local SHADOW_LAYERS = {
    { offset = 0.030, spread = 0.005, alpha = 0.90 },
    { offset = 0.055, spread = 0.018, alpha = 0.50 },
    { offset = 0.085, spread = 0.032, alpha = 0.24 },
};

local function DrawShadow(drawList, x, y, size, rounding)
    for _, layer in ipairs(SHADOW_LAYERS) do
        local drop, spread = size * layer.offset, size * layer.spread;
        drawList:AddRectFilled(
            { x - spread, y + drop - spread },
            { x + size + spread, y + size + drop + spread },
            M.Color(PALETTE.shadow, layer.alpha), rounding + spread);
    end
end

M.Draw = function(drawList, x, y, size, state, clock, fontSettings)
    -- Snap once; face, numeral, and effects all sit in this pixel box.
    x = math.floor(x + 0.5);
    y = math.floor(y + 0.5);
    size = math.floor(size + 0.5);
    local rounding = size * 0.18;
    local pulse = (math.sin(clock * 3.2) + 1) / 2;
    local styleKey = state.style or 'normal';
    local style = STYLES[styleKey] or STYLES.normal;

    if style.glow ~= nil then
        DrawGlow(drawList, x, y, size, style.glow, pulse);
    end

    DrawShadow(drawList, x, y, size, rounding);

    -- Shade full face, then inset lit face so the edge stays inside the rounding.
    drawList:AddRectFilled({ x, y }, { x + size, y + size },
        M.Color(PALETTE[style.shade]), rounding);
    drawList:AddRectFilled({ x, y }, { x + size, y + size * 0.88 },
        M.Color(PALETTE[style.face]), rounding);

    local edgeAlpha = (style.glow ~= nil) and (0.6 + pulse * 0.4) or 1;
    drawList:AddRect({ x, y }, { x + size, y + size },
        M.Color(PALETTE[style.edge], edgeAlpha), rounding, 0, size * 0.035);

    local text, textScale = FaceText(state);
    DrawNumeral(drawList, text, x, y, size, size * textScale,
        NUMERAL[style.numeral], fontSettings or {});

    local effect = EFFECTS[styleKey];
    if effect ~= nil then
        effect(drawList, x, y, size, clock);
    end
end

return M;
