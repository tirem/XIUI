--[[
* XIUI Hotbar - Shared Slot Renderer
* Renders action slots with icons, cooldowns, timer text, and handles ALL interactions
* Used by both hotbar display and crossbar
*
* MUST be called inside an ImGui window context for interactions to work
]]--

require('common');
local ffi = require('ffi');
local imgui = require('imgui');
local recast = require('modules.hotbar.recast');
local actions = require('modules.hotbar.actions');
local dragdrop = require('libs.dragdrop');
local textures = require('modules.hotbar.textures');

local M = {};

-- Cached asset path
local assetsPath = nil;

local function GetAssetsPath()
    if not assetsPath then
        assetsPath = string.format('%saddons\\XIUI\\assets\\hotbar\\', AshitaCore:GetInstallPath());
    end
    return assetsPath;
end

--[[
    Render a slot with all components and handle all interactions.
    MUST be called inside an ImGui window context.

    @param resources: Table containing primitives and fonts for this slot
        - slotPrim: Slot background primitive
        - iconPrim: Action icon primitive
        - timerFont: GDI font for cooldown timer
        - keybindFont: (optional) GDI font for keybind label
        - labelFont: (optional) GDI font for action name

    @param params: Table containing rendering and interaction parameters
        Position/Size:
        - x, y: Position in screen coordinates
        - size: Slot size in pixels

        Action Data:
        - bind: Action data table (with actionType, action, target, etc.) or nil
        - icon: Icon texture data (with .image and .path) or nil

        Visual Settings:
        - slotBgColor: Slot background color (default 0xFFFFFFFF)
        - keybindText: (optional) Keybind display text (e.g., "1", "C2")
        - keybindFontSize: (optional) Keybind font size
        - keybindFontColor: (optional) Keybind font color
        - showLabel: (optional) Whether to show action label below slot
        - labelText: (optional) Action label text
        - labelOffsetX/Y: (optional) Label position offsets
        - showFrame: (optional) Whether to show decorative frame overlay

        State Modifiers:
        - dimFactor: Dim multiplier for inactive states (default 1.0)
        - animOpacity: Animation opacity 0-1 (default 1.0)
        - isPressed: Whether slot is currently pressed (controller button)

        Interaction Config:
        - buttonId: Unique ID for ImGui button (required for interactions)
        - dropZoneId: ID for drop zone registration
        - dropAccepts: Array of accepted drag types (default {'macro'})
        - onDrop: Callback(payload) when something is dropped on slot
        - dragType: Type string for drag operations (e.g., 'macro', 'crossbar_slot')
        - getDragData: Callback() that returns drag payload data
        - onClick: Callback() when slot is clicked (executes action)
        - onRightClick: Callback() when slot is right-clicked (clear slot)
        - showTooltip: Whether to show tooltip on hover (default true)

    @return table: { isHovered, command }
]]--
function M.DrawSlot(resources, params)
    local x = params.x;
    local y = params.y;
    local size = params.size;
    local bind = params.bind;
    local icon = params.icon;
    local slotBgColor = params.slotBgColor or 0xFFFFFFFF;
    local dimFactor = params.dimFactor or 1.0;
    local animOpacity = params.animOpacity or 1.0;
    local isPressed = params.isPressed or false;

    -- Result
    local result = { isHovered = false, command = nil };

    -- Skip rendering if fully transparent
    if animOpacity <= 0.01 then
        M.HideSlot(resources);
        return result;
    end

    -- Build command for this action (used for click execution)
    local command = nil;
    if bind then
        command = actions.BuildCommand(bind);
        result.command = command;
    end

    -- Check hover state
    local mouseX, mouseY = imgui.GetMousePos();
    local isHovered = mouseX >= x and mouseX <= x + size and
                      mouseY >= y and mouseY <= y + size;
    result.isHovered = isHovered;

    -- ========================================
    -- 1. Slot Background Primitive
    -- ========================================
    if resources.slotPrim then
        local texturePath = GetAssetsPath() .. 'slot.png';
        resources.slotPrim.texture = texturePath;
        resources.slotPrim.position_x = x;
        resources.slotPrim.position_y = y;

        -- Scale slot texture (40x40 base)
        local scale = size / 40;
        resources.slotPrim.scale_x = scale;
        resources.slotPrim.scale_y = scale;

        -- Calculate final color with hover darkening and dim factor
        local finalColor = slotBgColor;
        local hoverDim = (isHovered and not dragdrop.IsDragging()) and 0.8 or 1.0;
        local totalDim = dimFactor * hoverDim;

        if totalDim < 1.0 then
            local a = bit.rshift(bit.band(slotBgColor, 0xFF000000), 24);
            local r = math.floor(bit.rshift(bit.band(slotBgColor, 0x00FF0000), 16) * totalDim);
            local g = math.floor(bit.rshift(bit.band(slotBgColor, 0x0000FF00), 8) * totalDim);
            local b = math.floor(bit.band(slotBgColor, 0x000000FF) * totalDim);
            finalColor = bit.bor(bit.lshift(a, 24), bit.lshift(r, 16), bit.lshift(g, 8), b);
        end

        -- Apply animation opacity to alpha channel
        if animOpacity < 1.0 then
            local a = math.floor(bit.rshift(bit.band(finalColor, 0xFF000000), 24) * animOpacity);
            finalColor = bit.bor(bit.lshift(a, 24), bit.band(finalColor, 0x00FFFFFF));
        end

        resources.slotPrim.color = finalColor;
        resources.slotPrim.visible = true;
    end

    -- ========================================
    -- 2. Icon Positioning
    -- ========================================
    local iconPadding = 4;
    local targetIconSize = size - (iconPadding * 2);

    -- ========================================
    -- 3. Cooldown Info
    -- ========================================
    local cooldown = recast.GetCooldownInfo(bind);
    local isOnCooldown = cooldown.isOnCooldown;
    local recastText = cooldown.recastText;

    -- ========================================
    -- 4. Icon Rendering (Primitive for file-based, ImGui for memory-based)
    -- ========================================
    local iconRendered = false;

    -- Try primitive rendering first (for icons with file paths like spell icons)
    if resources.iconPrim then
        if icon and icon.path then
            -- Set texture first so we can read actual dimensions
            resources.iconPrim.texture = icon.path;

            -- Read ACTUAL texture dimensions from primitive (not hardcoded values)
            -- Ashita primitives expose width/height after texture is set
            local texWidth = resources.iconPrim.width;
            local texHeight = resources.iconPrim.height;

            -- Fallback if dimensions not available
            if not texWidth or texWidth <= 0 then texWidth = 40; end
            if not texHeight or texHeight <= 0 then texHeight = 40; end

            -- Calculate scale to fit icon within slot with padding
            -- Use the larger dimension to ensure the icon fits
            local scale = targetIconSize / math.max(texWidth, texHeight);

            -- Calculate actual rendered size after scaling
            local renderedWidth = texWidth * scale;
            local renderedHeight = texHeight * scale;

            -- Center the icon within the slot
            local iconX = x + (size - renderedWidth) / 2;
            local iconY = y + (size - renderedHeight) / 2;

            resources.iconPrim.position_x = iconX;
            resources.iconPrim.position_y = iconY;
            resources.iconPrim.scale_x = scale;
            resources.iconPrim.scale_y = scale;

            -- Calculate color: cooldown darkening + dim factor + animation opacity
            local colorMult = isOnCooldown and 0.4 or 1.0;
            colorMult = colorMult * dimFactor;
            local rgb = math.floor(255 * colorMult);
            local alpha = math.floor(255 * animOpacity);
            resources.iconPrim.color = bit.bor(
                bit.lshift(alpha, 24),
                bit.lshift(rgb, 16),
                bit.lshift(rgb, 8),
                rgb
            );
            resources.iconPrim.visible = true;
            iconRendered = true;
        else
            resources.iconPrim.visible = false;
        end
    end

    -- Fallback to ImGui rendering for icons without paths (item icons loaded from game memory)
    if not iconRendered and icon and icon.image then
        local drawList = imgui.GetWindowDrawList();
        if drawList then
            local iconPtr = tonumber(ffi.cast("uint32_t", icon.image));
            if iconPtr then
                -- Get icon dimensions (item icons are typically 32x32)
                local texWidth = icon.width or 32;
                local texHeight = icon.height or 32;

                -- Calculate scale to fit icon within slot with padding
                local scale = targetIconSize / math.max(texWidth, texHeight);

                -- Calculate actual rendered size after scaling
                local renderedWidth = texWidth * scale;
                local renderedHeight = texHeight * scale;

                -- Center the icon within the slot
                local iconX = x + (size - renderedWidth) / 2;
                local iconY = y + (size - renderedHeight) / 2;

                -- Calculate color: cooldown darkening + dim factor + animation opacity
                local colorMult = isOnCooldown and 0.4 or 1.0;
                colorMult = colorMult * dimFactor;
                local rgb = math.floor(255 * colorMult);
                local alpha = math.floor(255 * animOpacity);
                local tintColor = bit.bor(
                    bit.lshift(alpha, 24),
                    bit.lshift(rgb, 16),
                    bit.lshift(rgb, 8),
                    rgb
                );

                drawList:AddImage(
                    iconPtr,
                    {iconX, iconY},
                    {iconX + renderedWidth, iconY + renderedHeight},
                    {0, 0}, {1, 1},
                    tintColor
                );
                iconRendered = true;
            end
        end
    end

    -- ========================================
    -- 5. Timer Font (GDI - cooldown text)
    -- ========================================
    if resources.timerFont then
        if recastText and animOpacity > 0.5 then
            resources.timerFont:set_text(recastText);
            resources.timerFont:set_position_x(x + size / 2);
            resources.timerFont:set_position_y(y + size / 2 - 6);
            resources.timerFont:set_visible(true);
        else
            resources.timerFont:set_visible(false);
        end
    end

    -- ========================================
    -- 6. Keybind Font (GDI)
    -- ========================================
    if resources.keybindFont then
        if params.keybindText and params.keybindText ~= '' then
            resources.keybindFont:set_text(params.keybindText);
            resources.keybindFont:set_position_x(x + 2);
            resources.keybindFont:set_position_y(y + 1);
            -- Apply font settings if provided
            if params.keybindFontSize then
                resources.keybindFont:set_font_height(params.keybindFontSize);
            end
            if params.keybindFontColor then
                resources.keybindFont:set_font_color(params.keybindFontColor);
            end
            resources.keybindFont:set_visible(animOpacity > 0.5);
        else
            resources.keybindFont:set_visible(false);
        end
    end

    -- ========================================
    -- 7. Label Font (GDI - action name below slot)
    -- ========================================
    if resources.labelFont then
        if params.showLabel and params.labelText and params.labelText ~= '' then
            resources.labelFont:set_text(params.labelText);
            resources.labelFont:set_position_x(x + size / 2 + (params.labelOffsetX or 0));
            resources.labelFont:set_position_y(y + size + 2 + (params.labelOffsetY or 0));
            resources.labelFont:set_visible(animOpacity > 0.5);
        else
            resources.labelFont:set_visible(false);
        end
    end

    -- ========================================
    -- 8. ImGui: Frame Overlay
    -- ========================================
    local drawList = imgui.GetWindowDrawList();
    if drawList and params.showFrame then
        local frameTexture = textures:Get('frame');
        if frameTexture and frameTexture.image then
            local framePtr = tonumber(ffi.cast("uint32_t", frameTexture.image));
            if framePtr then
                local frameAlpha = math.floor(255 * animOpacity);
                local frameColor = bit.bor(bit.lshift(frameAlpha, 24), 0x00FFFFFF);
                drawList:AddImage(framePtr, {x, y}, {x + size, y + size}, {0,0}, {1,1}, frameColor);
            end
        end
    end

    -- ========================================
    -- 9. ImGui: Hover/Pressed Visual Effects
    -- ========================================
    if drawList and animOpacity > 0.5 then
        if isPressed then
            -- Pressed effect - red if on cooldown, white otherwise
            local pressedTintColor, pressedBorderColor;
            if isOnCooldown then
                pressedTintColor = imgui.GetColorU32({1.0, 0.2, 0.2, 0.35 * animOpacity});
                pressedBorderColor = imgui.GetColorU32({1.0, 0.3, 0.3, 0.6 * animOpacity});
            else
                pressedTintColor = imgui.GetColorU32({1.0, 1.0, 1.0, 0.25 * animOpacity});
                pressedBorderColor = imgui.GetColorU32({1.0, 1.0, 1.0, 0.5 * animOpacity});
            end
            drawList:AddRectFilled({x, y}, {x + size, y + size}, pressedTintColor, 4);
            drawList:AddRect({x, y}, {x + size, y + size}, pressedBorderColor, 4, 0, 2);
        elseif isHovered and not dragdrop.IsDragging() then
            -- Hover effect (mouse)
            local hoverTintColor = imgui.GetColorU32({1.0, 1.0, 1.0, 0.15 * animOpacity});
            local hoverBorderColor = imgui.GetColorU32({1.0, 1.0, 1.0, 0.10 * animOpacity});
            drawList:AddRectFilled({x, y}, {x + size, y + size}, hoverTintColor, 2);
            drawList:AddRect({x, y}, {x + size, y + size}, hoverBorderColor, 2, 0, 1);
        end
    end

    -- ========================================
    -- 10. Drop Zone Registration
    -- ========================================
    if params.dropZoneId and params.onDrop then
        dragdrop.DropZone(params.dropZoneId, x, y, size, size, {
            accepts = params.dropAccepts or {'macro'},
            highlightColor = params.dropHighlightColor or 0xA8FFFFFF,
            onDrop = params.onDrop,
        });
    end

    -- ========================================
    -- 11. ImGui Interaction Button
    -- ========================================
    if params.buttonId then
        imgui.SetCursorScreenPos({x, y});
        imgui.InvisibleButton(params.buttonId, {size, size});

        local isItemHovered = imgui.IsItemHovered();
        local isItemActive = imgui.IsItemActive();

        -- Drag source
        if bind and params.dragType and params.getDragData then
            if isItemActive and imgui.IsMouseDragging(0, 3) then
                if not dragdrop.IsDragging() and not dragdrop.IsDragPending() then
                    local dragData = params.getDragData();
                    if dragData then
                        dragdrop.StartDrag(params.dragType, dragData);
                    end
                end
            end
        end

        -- Left click to execute
        if isItemHovered and imgui.IsMouseReleased(0) then
            if not dragdrop.IsDragging() and not dragdrop.WasDragAttempted() then
                if params.onClick then
                    params.onClick();
                elseif command then
                    -- Default: execute the command
                    AshitaCore:GetChatManager():QueueCommand(-1, command);
                end
            end
        end

        -- Right click
        if isItemHovered and imgui.IsMouseClicked(1) and bind then
            if params.onRightClick then
                params.onRightClick();
            end
        end
    end

    -- ========================================
    -- 12. Tooltip
    -- ========================================
    local showTooltip = params.showTooltip ~= false;
    if showTooltip and isHovered and bind and not dragdrop.IsDragging() and animOpacity > 0.5 then
        M.DrawTooltip(bind);
    end

    return result;
end

--[[
    Draw tooltip for an action.
    Should be called inside ImGui context.
]]--
function M.DrawTooltip(bind)
    if not bind then return; end

    -- Style the tooltip
    imgui.PushStyleColor(ImGuiCol_PopupBg, {0.067, 0.063, 0.055, 0.95});
    imgui.PushStyleColor(ImGuiCol_Border, {0.3, 0.28, 0.24, 0.8});
    imgui.PushStyleColor(ImGuiCol_Text, {0.9, 0.9, 0.9, 1.0});
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {8, 6});
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 4);

    imgui.BeginTooltip();

    -- Action name (yellow/gold)
    local displayName = bind.displayName or bind.action or 'Unknown';
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
    local typeName = typeNames[bind.actionType] or bind.actionType or '';
    if typeName ~= '' then
        imgui.TextColored({0.7, 0.7, 0.7, 1.0}, typeName);
    end

    -- Target (blue)
    if bind.target and bind.target ~= '' then
        imgui.TextColored({0.6, 0.8, 1.0, 1.0}, '<' .. bind.target .. '>');
    end

    -- Macro text preview (if macro type)
    if bind.actionType == 'macro' and bind.macroText then
        imgui.Separator();
        imgui.TextColored({0.6, 0.6, 0.6, 1.0}, bind.macroText);
    end

    imgui.EndTooltip();

    imgui.PopStyleVar(2);
    imgui.PopStyleColor(3);
end

--[[
    Hide all resources for a slot.
    Use when slot should not be visible (animation, disabled bar, etc.)
]]--
function M.HideSlot(resources)
    if not resources then return; end
    if resources.slotPrim then resources.slotPrim.visible = false; end
    if resources.iconPrim then resources.iconPrim.visible = false; end
    if resources.timerFont then resources.timerFont:set_visible(false); end
    if resources.keybindFont then resources.keybindFont:set_visible(false); end
    if resources.labelFont then resources.labelFont:set_visible(false); end
end

return M;
