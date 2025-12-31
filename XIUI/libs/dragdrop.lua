--[[
* XIUI Drag and Drop Library
* Custom drag-drop system for Lua/ImGui when native payloads fail
*
* Usage:
*   local dragdrop = require('libs.dragdrop');
*
*   -- Start drag from a source
*   dragdrop.StartDrag('macro', {
*       type = 'macro',
*       data = macroData,
*       label = 'Cure IV',
*   });
*
*   -- Register a drop zone (call each frame)
*   local dropped = dragdrop.DropZone('hotbarslot_1_5', x, y, w, h, {
*       accepts = {'macro', 'slot'},
*       onDrop = function(payload, zoneId) ... end,
*   });
*
*   -- Render drag preview (call at end of frame)
*   dragdrop.Render();
]]--

require('common');
local imgui = require('imgui');
local ffi = require('ffi');

local dragdrop = {};

-- ============================================
-- State
-- ============================================

local state = {
    -- Drag state
    isDragging = false,
    payload = nil,
    startPos = { x = 0, y = 0 },
    dragThreshold = 3,
    dragActivated = false,  -- True once threshold exceeded

    -- Track if drag was attempted this frame (for click suppression)
    dragEndedThisFrame = false,

    -- Track if drop was handled this frame (vs dropped outside)
    dropHandledThisFrame = false,
    lastPayload = nil,  -- Preserved after drag ends for outside drop handling

    -- Drop zone registry
    zones = {},
    activeZoneId = nil,
    previousZoneId = nil,

    -- Preview configuration
    preview = {
        offset = { x = 15, y = 15 },
        iconSize = 32,
        showLabel = true,
        backgroundColor = 0xEE111111,
        borderColor = 0xFFF4DAA7,  -- Gold
        labelColor = 0xFFE6E6E6,
        rounding = 4,
        padding = 6,
    },

    -- Custom renderer
    customRenderer = nil,
};

-- ============================================
-- Helper Functions
-- ============================================

local function PointInRect(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h;
end

local function ARGBToImGuiColor(argb)
    local a = bit.band(bit.rshift(argb, 24), 0xFF) / 255;
    local r = bit.band(bit.rshift(argb, 16), 0xFF) / 255;
    local g = bit.band(bit.rshift(argb, 8), 0xFF) / 255;
    local b = bit.band(argb, 0xFF) / 255;
    return { r, g, b, a };
end

-- ============================================
-- Drag Source Functions
-- ============================================

---Start a drag operation
---@param sourceType string Type identifier (e.g., 'macro', 'slot')
---@param payload table Data to transfer on drop
function dragdrop.StartDrag(sourceType, payload)
    local mouseX, mouseY = imgui.GetMousePos();

    state.isDragging = true;
    state.payload = payload or {};
    state.payload.type = sourceType;
    state.startPos.x = mouseX;
    state.startPos.y = mouseY;
    state.dragActivated = false;
    state.activeZoneId = nil;
end

---Cancel current drag without triggering drop
function dragdrop.CancelDrag()
    state.isDragging = false;
    state.payload = nil;
    state.dragActivated = false;
    state.activeZoneId = nil;
    state.previousZoneId = nil;
    state.dragEndedThisFrame = true;
end

---Force end drag (internal, called on mouse release)
local function EndDrag()
    -- Preserve payload for outside drop detection
    state.lastPayload = state.payload;
    state.isDragging = false;
    state.payload = nil;
    state.dragActivated = false;
    state.previousZoneId = state.activeZoneId;
    state.activeZoneId = nil;
    state.dragEndedThisFrame = true;
end

-- ============================================
-- Drag State Query Functions
-- ============================================

---Check if currently dragging
---@return boolean
function dragdrop.IsDragging()
    return state.isDragging and state.dragActivated;
end

---Check if drag is starting (before threshold)
---@return boolean
function dragdrop.IsDragPending()
    return state.isDragging and not state.dragActivated;
end

---Check if drag is of specific type
---@param dragType string Type to check
---@return boolean
function dragdrop.IsDraggingType(dragType)
    return state.isDragging and state.dragActivated and
           state.payload and state.payload.type == dragType;
end

---Get current drag payload (or nil if not dragging)
---@return table|nil
function dragdrop.GetPayload()
    if state.isDragging then
        return state.payload;
    end
    return nil;
end

---Get drag start position
---@return number, number x, y
function dragdrop.GetDragStartPos()
    return state.startPos.x, state.startPos.y;
end

---Check if a drag ended this frame (for click suppression)
---@return boolean
function dragdrop.WasDragAttempted()
    return state.dragEndedThisFrame;
end

---Check if a drag ended this frame without being dropped on a valid zone
---@return boolean
function dragdrop.WasDroppedOutside()
    return state.dragEndedThisFrame and not state.dropHandledThisFrame;
end

---Get the payload from the last completed drag (for outside drop handling)
---@return table|nil
function dragdrop.GetLastPayload()
    return state.lastPayload;
end

-- ============================================
-- Drop Zone Functions
-- ============================================

---Register and check a drop zone for this frame
---@param id string Unique zone identifier
---@param x number Zone X position
---@param y number Zone Y position
---@param width number Zone width
---@param height number Zone height
---@param options table Zone configuration
---@return boolean True if drop occurred this frame
---@return boolean True if currently hovered and valid
function dragdrop.DropZone(id, x, y, width, height, options)
    options = options or {};

    -- Store zone info
    state.zones[id] = {
        x = x,
        y = y,
        width = width,
        height = height,
        options = options,
    };

    -- Not dragging or not activated yet
    if not state.isDragging or not state.dragActivated then
        return false, false;
    end

    -- Check if zone accepts this drag type
    local accepts = options.accepts or {};
    if type(accepts) == 'string' then
        accepts = { accepts };
    end

    local canAccept = false;
    for _, acceptType in ipairs(accepts) do
        if acceptType == state.payload.type or acceptType == '*' then
            canAccept = true;
            break;
        end
    end

    -- Check if enabled
    if options.enabled == false then
        canAccept = false;
    end

    -- Hit test
    local mouseX, mouseY = imgui.GetMousePos();
    local isHovered = PointInRect(mouseX, mouseY, x, y, width, height);

    -- Visual feedback
    if isHovered then
        local drawList = imgui.GetForegroundDrawList();
        if drawList then
            local highlightColor;

            if canAccept then
                highlightColor = options.highlightColor or 0xCC55DD55;  -- Green
                state.activeZoneId = id;

                -- Call hover callback
                if options.onHover then
                    options.onHover(state.payload, id);
                end
            else
                highlightColor = options.invalidColor or 0xCCDD5555;  -- Red
            end

            local colorU32 = imgui.GetColorU32(ARGBToImGuiColor(highlightColor));
            drawList:AddRect(
                {x, y},
                {x + width, y + height},
                colorU32,
                2,
                0,
                3
            );
        end
    elseif state.activeZoneId == id then
        state.activeZoneId = nil;
    end

    -- Check for drop (mouse released while hovering valid zone)
    local dropped = false;
    if isHovered and canAccept and imgui.IsMouseReleased(0) then
        dropped = true;
        state.dropHandledThisFrame = true;  -- Mark that drop was handled
        if options.onDrop then
            options.onDrop(state.payload, id);
        end
    end

    return dropped, isHovered and canAccept;
end

-- ============================================
-- Preview Rendering
-- ============================================

---Set custom preview renderer
---@param renderer function|nil
function dragdrop.SetPreviewRenderer(renderer)
    state.customRenderer = renderer;
end

---Configure default preview appearance
---@param config table
function dragdrop.ConfigurePreview(config)
    if config.offset then state.preview.offset = config.offset; end
    if config.iconSize then state.preview.iconSize = config.iconSize; end
    if config.showLabel ~= nil then state.preview.showLabel = config.showLabel; end
    if config.backgroundColor then state.preview.backgroundColor = config.backgroundColor; end
    if config.borderColor then state.preview.borderColor = config.borderColor; end
    if config.labelColor then state.preview.labelColor = config.labelColor; end
    if config.rounding then state.preview.rounding = config.rounding; end
    if config.padding then state.preview.padding = config.padding; end
end

---Render the drag preview (call at end of frame, AFTER all drop zones processed)
function dragdrop.Render()
    if not state.isDragging or not state.dragActivated then
        return;
    end

    local mouseX, mouseY = imgui.GetMousePos();
    local payload = state.payload;

    -- Use custom renderer if set
    if state.customRenderer then
        local handled = state.customRenderer(payload, mouseX, mouseY);
        if handled then
            -- Still need to check for mouse release even with custom renderer
            if imgui.IsMouseReleased(0) then
                EndDrag();
            end
            return;
        end
    end

    -- Default preview rendering
    local drawList = imgui.GetForegroundDrawList();
    if drawList then
        local cfg = state.preview;
        local iconSize = cfg.iconSize;

        -- Check if we have an icon to display
        local hasIcon = payload.icon and payload.icon.image;

        if hasIcon then
            -- Draw icon centered on cursor (slightly offset so cursor is at top-left)
            local iconX = mouseX - 4;
            local iconY = mouseY - 4;

            -- Draw the icon
            local iconPtr = tonumber(ffi.cast("uint32_t", payload.icon.image));
            if iconPtr then
                drawList:AddImage(
                    iconPtr,
                    {iconX, iconY},
                    {iconX + iconSize, iconY + iconSize}
                );
            end

            -- Draw native ImGui tooltip (same style as slot hover tooltip)
            local data = payload.data;
            if data then
                -- Style the tooltip to match slot tooltips
                imgui.PushStyleColor(ImGuiCol_PopupBg, {0.067, 0.063, 0.055, 0.95});
                imgui.PushStyleColor(ImGuiCol_Border, {0.3, 0.28, 0.24, 0.8});
                imgui.PushStyleColor(ImGuiCol_Text, {0.9, 0.9, 0.9, 1.0});
                imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {8, 6});
                imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 4);

                imgui.BeginTooltip();

                -- Action name (yellow/gold)
                local displayName = data.displayName or data.action or payload.label or 'Unknown';
                imgui.TextColored({1.0, 0.84, 0.0, 1.0}, displayName);

                -- Action type (gray)
                local typeNames = {
                    ma = 'Magic',
                    ja = 'Ability',
                    ws = 'Weapon Skill',
                    item = 'Item',
                    equip = 'Equipment',
                    pet = 'Pet Command',
                    macro = 'Macro',
                };
                local typeName = typeNames[data.actionType] or data.actionType or '';
                if typeName ~= '' then
                    imgui.TextColored({0.7, 0.7, 0.7, 1.0}, typeName);
                end

                -- Target (blue)
                if data.target and data.target ~= '' then
                    imgui.TextColored({0.6, 0.8, 1.0, 1.0}, '<' .. data.target .. '>');
                end

                imgui.EndTooltip();

                imgui.PopStyleVar(2);
                imgui.PopStyleColor(3);
            end
        else
            -- No icon - fall back to text label at cursor
            local label = payload.label or payload.type or 'Drag';
            local textWidth = imgui.CalcTextSize(label) or 50;

            local previewX = mouseX + 8;
            local previewY = mouseY + 8;
            local previewWidth = textWidth + cfg.padding * 2;
            local previewHeight = 20 + cfg.padding;

            local bgColorU32 = imgui.GetColorU32(ARGBToImGuiColor(cfg.backgroundColor));
            local borderColorU32 = imgui.GetColorU32(ARGBToImGuiColor(cfg.borderColor));
            local labelColorU32 = imgui.GetColorU32(ARGBToImGuiColor(cfg.labelColor));

            drawList:AddRectFilled(
                {previewX, previewY},
                {previewX + previewWidth, previewY + previewHeight},
                bgColorU32,
                cfg.rounding
            );
            drawList:AddRect(
                {previewX, previewY},
                {previewX + previewWidth, previewY + previewHeight},
                borderColorU32,
                cfg.rounding,
                0,
                2
            );

            drawList:AddText({previewX + cfg.padding, previewY + cfg.padding - 2}, labelColorU32, label);
        end
    end

    -- End drag on mouse release (AFTER drop zones have had a chance to process)
    if imgui.IsMouseReleased(0) then
        EndDrag();
    end
end

-- ============================================
-- Lifecycle Functions
-- ============================================

---Update drag state (call every frame, BEFORE processing drop zones)
function dragdrop.Update()
    -- Reset per-frame state
    state.dragEndedThisFrame = false;
    state.dropHandledThisFrame = false;
    state.lastPayload = nil;

    -- Clear zones from previous frame
    state.zones = {};

    if not state.isDragging then
        return;
    end

    -- Check for escape to cancel
    if imgui.IsKeyPressed(27) then  -- Escape key
        dragdrop.CancelDrag();
        return;
    end

    -- Check drag threshold
    if not state.dragActivated then
        local mouseX, mouseY = imgui.GetMousePos();
        local dx = mouseX - state.startPos.x;
        local dy = mouseY - state.startPos.y;
        local distance = math.sqrt(dx * dx + dy * dy);

        if distance >= state.dragThreshold then
            state.dragActivated = true;
        end

        -- If mouse released before threshold, cancel
        if imgui.IsMouseReleased(0) then
            dragdrop.CancelDrag();
            return;
        end
    end

    -- NOTE: Don't end drag here on mouse release!
    -- DropZone() needs to process the drop first, then Render() will end the drag.
end

---Reset all state
function dragdrop.Reset()
    state.isDragging = false;
    state.payload = nil;
    state.dragActivated = false;
    state.zones = {};
    state.activeZoneId = nil;
    state.previousZoneId = nil;
end

return dragdrop;
