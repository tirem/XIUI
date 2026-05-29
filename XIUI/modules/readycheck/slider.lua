--[[
* Integer slider with optional visual tick marks and release snap checkpoints.
* Checkpoint sliders use custom draw + InvisibleButton input.
]]--

local imgui = require('imgui');

local M = {};

local dragPrev = {};

local GRAB_PADDING     = 2.0;
local TICK_ALIGN_SHIFT = 4;
local SNAP_TOLERANCE   = 4;

local function clamp_int(value, minVal, maxVal)
    value = math.floor(value + (value >= 0 and 0.5 or -0.5));
    if value < minVal then return minVal; end
    if value > maxVal then return maxVal; end
    return value;
end

local function clamp01(t)
    if t < 0 then return 0; end
    if t > 1 then return 1; end
    return t;
end

local function get_visible_label(label)
    return label:match('^(.-)##') or '';
end

local function get_format_text_width(format, minVal, maxVal)
    local style = imgui.GetStyle();
    local wMin = imgui.CalcTextSize(string.format(format, minVal));
    local wMax = imgui.CalcTextSize(string.format(format, maxVal));
    return math.max(wMin, wMax) + style.ItemInnerSpacing.x;
end

local function get_slider_track_bounds(minX, maxX, minY, maxY, minVal, maxVal, format)
    local style = imgui.GetStyle();
    local framePadX = style.FramePadding.x or 8;

    local frameMinX = minX + framePadX;
    local frameMaxX = maxX - framePadX - get_format_text_width(format, minVal, maxVal);
    local trackY = (minY + maxY) * 0.5;

    local sliderSz = (frameMaxX - frameMinX) - GRAB_PADDING * 2;
    if sliderSz < 1 then
        local grabMinSize = style.GrabMinSize or 12;
        return frameMinX, frameMaxX, trackY, grabMinSize;
    end

    local vRange = maxVal - minVal;
    local grabMinSize = style.GrabMinSize or 12;
    local grabSz = math.max(sliderSz / (vRange + 1), grabMinSize);
    grabSz = math.min(grabSz, sliderSz);

    local usableMin = frameMinX + GRAB_PADDING + grabSz * 0.5;
    local usableMax = frameMaxX - GRAB_PADDING - grabSz * 0.5;

    if usableMax <= usableMin then
        return frameMinX + GRAB_PADDING, frameMaxX - GRAB_PADDING, trackY, grabSz;
    end

    return usableMin, usableMax, trackY, grabSz;
end

local function align_track_bounds(trackMinX, trackMaxX, minVal, maxVal)
    local vRange = maxVal - minVal;
    if vRange <= 0 then return trackMinX, trackMaxX; end

    local span = trackMaxX - trackMinX;
    local pxShift = (TICK_ALIGN_SHIFT / vRange) * span;
    return trackMinX - pxShift, trackMaxX - pxShift;
end

local function value_to_track_x(value, trackMinX, trackMaxX, minVal, maxVal)
    local span = maxVal - minVal;
    if span <= 0 then return trackMinX; end

    local t = (value - minVal) / span;
    return trackMinX + t * (trackMaxX - trackMinX);
end

local function mouse_to_value(mouseX, trackMinX, trackMaxX, minVal, maxVal)
    if trackMaxX <= trackMinX then
        return minVal;
    end

    local t = clamp01((mouseX - trackMinX) / (trackMaxX - trackMinX));
    return minVal + t * (maxVal - minVal);
end

local function snap_near_detents(value, detents)
    local best = value;
    local bestDist = SNAP_TOLERANCE + 1;

    for _, detent in ipairs(detents) do
        local dist = math.abs(value - detent);
        if dist <= SNAP_TOLERANCE and dist < bestDist then
            best = detent;
            bestDist = dist;
        end
    end

    return best;
end

local function draw_custom_slider(minX, minY, maxY, value, minVal, maxVal, format, isHovered, isActive, trackMinX, trackMaxX, grabSz)
    if not imgui.GetWindowDrawList then return; end

    local style = imgui.GetStyle();
    local drawList = imgui.GetWindowDrawList();
    local rounding = style.FrameRounding or 0;

    local frameCol = ImGuiCol_FrameBg;
    if isActive then
        frameCol = ImGuiCol_FrameBgActive;
    elseif isHovered then
        frameCol = ImGuiCol_FrameBgHovered;
    end

    local alignedMinX, alignedMaxX = align_track_bounds(trackMinX, trackMaxX, minVal, maxVal);
    local grabX = value_to_track_x(value, alignedMinX, alignedMaxX, minVal, maxVal);
    local grabHalf = grabSz * 0.5;
    local trackEndX = alignedMaxX + grabHalf;
    local innerMinX = minX + GRAB_PADDING;

    drawList:AddRectFilled({ minX, minY }, { trackEndX, maxY }, imgui.GetColorU32(frameCol), rounding);

    local fillMaxX = math.max(innerMinX, grabX + grabHalf);
    if fillMaxX > innerMinX then
        drawList:AddRectFilled(
            { innerMinX, minY + GRAB_PADDING },
            { fillMaxX, maxY - GRAB_PADDING },
            imgui.GetColorU32(ImGuiCol_SliderGrabActive),
            rounding
        );
    end

    local grabCol = isActive and ImGuiCol_SliderGrabActive or ImGuiCol_SliderGrab;
    drawList:AddRectFilled(
        { grabX - grabHalf, minY + GRAB_PADDING },
        { grabX + grabHalf, maxY - GRAB_PADDING },
        imgui.GetColorU32(grabCol),
        style.GrabRounding or rounding
    );

    local text = string.format(format, clamp_int(value, minVal, maxVal));
    drawList:AddText(
        { trackEndX + style.ItemInnerSpacing.x, minY + style.FramePadding.y },
        imgui.GetColorU32(ImGuiCol_Text),
        text
    );
end

local function draw_tick_marks(minVal, maxVal, detents, trackMinX, trackMaxX, trackY)
    if not imgui.GetWindowDrawList then return; end

    local alignedMinX, alignedMaxX = align_track_bounds(trackMinX, trackMaxX, minVal, maxVal);
    local drawList = imgui.GetWindowDrawList();
    local tickColor = imgui.GetColorU32({ 0.75, 0.68, 0.47, 0.95 });
    for _, detent in ipairs(detents) do
        local x = value_to_track_x(detent, alignedMinX, alignedMaxX, minVal, maxVal);
        drawList:AddLine({ x, trackY - 5 }, { x, trackY + 5 }, tickColor, 1.5);
    end
end

local function draw_checkpoint_slider(label, valueRef, minVal, maxVal, format, detents, width, onCommit)
    local stateId = label;
    local visibleLabel = get_visible_label(label);

    if visibleLabel ~= '' then
        imgui.AlignTextToFramePadding();
        imgui.Text(visibleLabel);
        imgui.SameLine();
    end

    if width then
        imgui.SetNextItemWidth(width);
    end

    local sliderW = width or imgui.CalcItemWidth();
    local sliderH = imgui.GetFrameHeight();
    imgui.InvisibleButton('##rc_slider_' .. stateId, { sliderW, sliderH });

    local isHovered = imgui.IsItemHovered();
    local isActive = imgui.IsItemActive();
    local minX, minY = imgui.GetItemRectMin();
    local maxX, maxY = imgui.GetItemRectMax();

    local trackMinX, trackMaxX, trackY, grabSz = get_slider_track_bounds(
        minX, maxX, minY, maxY, minVal, maxVal, format
    );
    local alignedMinX, alignedMaxX = align_track_bounds(trackMinX, trackMaxX, minVal, maxVal);

    if isActive and imgui.IsMouseDown(0) then
        local mouseX = imgui.GetMousePos();
        local target = mouse_to_value(mouseX, alignedMinX, alignedMaxX, minVal, maxVal);
        dragPrev[stateId] = target;
        valueRef[1] = clamp_int(target, minVal, maxVal);
    elseif not imgui.IsMouseDown(0) then
        if dragPrev[stateId] ~= nil then
            valueRef[1] = snap_near_detents(valueRef[1], detents);
            if onCommit then onCommit(valueRef[1]); end
        end
        dragPrev[stateId] = nil;
    end

    local visualValue = dragPrev[stateId] or (valueRef[1] + 0.0);
    draw_custom_slider(minX, minY, maxY, visualValue, minVal, maxVal, format, isHovered, isActive, trackMinX, trackMaxX, grabSz);
    draw_tick_marks(minVal, maxVal, detents, trackMinX, trackMaxX, trackY);
end

--- Draw an integer slider with optional tick marks and snap checkpoints at detent values.
function M.DrawInt(label, valueRef, minVal, maxVal, format, detents, width, onCommit)
    draw_checkpoint_slider(label, valueRef, minVal, maxVal, format or '%d', detents or {}, width, onCommit);
end

return M;
