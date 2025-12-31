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

-- Cache for MP cost lookups (keyed by action key string)
local mpCostCache = {};

local M = {};

-- Cached asset path
local assetsPath = nil;

-- Per-slot cache to avoid redundant updates
-- Structure: slotCache[slotPrim] = { texturePath, iconPath, keybindText, keybindFontSize, keybindFontColor, timerText, ... }
local slotCache = {};

-- Reusable result table for DrawSlot to avoid GC pressure
-- (Creating tables per-slot per-frame causes ~7200 allocations/sec)
local drawSlotResult = { isHovered = false, command = nil };

-- Get or create cache entry for a slot (keyed by slotPrim for uniqueness)
local function GetSlotCache(slotPrim)
    if not slotPrim then return nil; end
    if not slotCache[slotPrim] then
        slotCache[slotPrim] = {};
    end
    return slotCache[slotPrim];
end

-- Clear cache for a slot
function M.ClearSlotCache(slotPrim)
    if slotPrim then
        slotCache[slotPrim] = nil;
    end
end

-- Clear all cached state
function M.ClearAllCache()
    slotCache = {};
end

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
        - mpCostFont: (optional) GDI font for MP cost display

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
        - showMpCost: (optional) Whether to show MP cost for spells
        - mpCostFontSize: (optional) MP cost font size
        - mpCostFontColor: (optional) MP cost font color

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
    NOTE: Returns a reused table - do NOT cache the return value, read values immediately
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

    -- Reuse result table to avoid GC pressure
    -- NOTE: Caller must read values immediately, do not cache the return value
    drawSlotResult.isHovered = false;
    drawSlotResult.command = nil;
    local result = drawSlotResult;

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
    local cache = GetSlotCache(resources.slotPrim);
    if resources.slotPrim then
        -- Only set texture once (cached)
        local texturePath = GetAssetsPath() .. 'slot.png';
        if cache and cache.slotTexturePath ~= texturePath then
            resources.slotPrim.texture = texturePath;
            cache.slotTexturePath = texturePath;
        end

        -- Only update position if changed
        if cache and (cache.slotX ~= x or cache.slotY ~= y) then
            resources.slotPrim.position_x = x;
            resources.slotPrim.position_y = y;
            cache.slotX = x;
            cache.slotY = y;
        end

        -- Scale slot texture (40x40 base)
        local scale = size / 40;
        if cache and cache.slotScale ~= scale then
            resources.slotPrim.scale_x = scale;
            resources.slotPrim.scale_y = scale;
            cache.slotScale = scale;
        end

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

        -- Only update color if changed
        if cache and cache.slotColor ~= finalColor then
            resources.slotPrim.color = finalColor;
            cache.slotColor = finalColor;
        end
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
            -- Only set texture path if changed (expensive D3D operation)
            if cache and cache.iconPath ~= icon.path then
                resources.iconPrim.texture = icon.path;
                cache.iconPath = icon.path;
                -- Clear cached dimensions when texture changes
                cache.iconTexWidth = nil;
                cache.iconTexHeight = nil;
            end

            -- Read ACTUAL texture dimensions from primitive (cached after first read)
            local texWidth, texHeight;
            if cache and cache.iconTexWidth then
                texWidth = cache.iconTexWidth;
                texHeight = cache.iconTexHeight;
            else
                texWidth = resources.iconPrim.width;
                texHeight = resources.iconPrim.height;
                -- Fallback if dimensions not available
                if not texWidth or texWidth <= 0 then texWidth = 40; end
                if not texHeight or texHeight <= 0 then texHeight = 40; end
                if cache then
                    cache.iconTexWidth = texWidth;
                    cache.iconTexHeight = texHeight;
                end
            end

            -- Calculate scale to fit icon within slot with padding
            local scale = targetIconSize / math.max(texWidth, texHeight);

            -- Calculate actual rendered size after scaling
            local renderedWidth = texWidth * scale;
            local renderedHeight = texHeight * scale;

            -- Center the icon within the slot
            local iconX = x + (size - renderedWidth) / 2;
            local iconY = y + (size - renderedHeight) / 2;

            -- Only update position/scale if changed
            if cache and (cache.iconX ~= iconX or cache.iconY ~= iconY or cache.iconScale ~= scale) then
                resources.iconPrim.position_x = iconX;
                resources.iconPrim.position_y = iconY;
                resources.iconPrim.scale_x = scale;
                resources.iconPrim.scale_y = scale;
                cache.iconX = iconX;
                cache.iconY = iconY;
                cache.iconScale = scale;
            end

            -- Calculate color: cooldown darkening + dim factor + animation opacity
            local colorMult = isOnCooldown and 0.4 or 1.0;
            colorMult = colorMult * dimFactor;
            local rgb = math.floor(255 * colorMult);
            local alpha = math.floor(255 * animOpacity);
            local iconColor = bit.bor(
                bit.lshift(alpha, 24),
                bit.lshift(rgb, 16),
                bit.lshift(rgb, 8),
                rgb
            );

            -- Only update color if changed
            if cache and cache.iconColor ~= iconColor then
                resources.iconPrim.color = iconColor;
                cache.iconColor = iconColor;
            end
            resources.iconPrim.visible = true;
            iconRendered = true;
        else
            resources.iconPrim.visible = false;
            if cache then cache.iconPath = nil; end
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
            -- Only update text if changed
            if cache and cache.timerText ~= recastText then
                resources.timerFont:set_text(recastText);
                cache.timerText = recastText;
            end
            -- Only update position if changed
            local timerX = x + size / 2;
            local timerY = y + size / 2 - 6;
            if cache and (cache.timerX ~= timerX or cache.timerY ~= timerY) then
                resources.timerFont:set_position_x(timerX);
                resources.timerFont:set_position_y(timerY);
                cache.timerX = timerX;
                cache.timerY = timerY;
            end
            resources.timerFont:set_visible(true);
        else
            resources.timerFont:set_visible(false);
            if cache then cache.timerText = nil; end
        end
    end

    -- ========================================
    -- 6. Keybind Font (GDI)
    -- ========================================
    if resources.keybindFont then
        if params.keybindText and params.keybindText ~= '' then
            -- Only update text if changed
            if cache and cache.keybindText ~= params.keybindText then
                resources.keybindFont:set_text(params.keybindText);
                cache.keybindText = params.keybindText;
            end
            -- Only update position if changed
            local kbX = x + 2;
            local kbY = y + 1;
            if cache and (cache.keybindX ~= kbX or cache.keybindY ~= kbY) then
                resources.keybindFont:set_position_x(kbX);
                resources.keybindFont:set_position_y(kbY);
                cache.keybindX = kbX;
                cache.keybindY = kbY;
            end
            -- Only update font settings if changed
            if params.keybindFontSize and cache and cache.keybindFontSize ~= params.keybindFontSize then
                resources.keybindFont:set_font_height(params.keybindFontSize);
                cache.keybindFontSize = params.keybindFontSize;
            end
            if params.keybindFontColor and cache and cache.keybindFontColor ~= params.keybindFontColor then
                resources.keybindFont:set_font_color(params.keybindFontColor);
                cache.keybindFontColor = params.keybindFontColor;
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
            -- Only update text if changed
            if cache and cache.labelText ~= params.labelText then
                resources.labelFont:set_text(params.labelText);
                cache.labelText = params.labelText;
            end
            -- Only update position if changed
            local labelX = x + size / 2 + (params.labelOffsetX or 0);
            local labelY = y + size + 2 + (params.labelOffsetY or 0);
            if cache and (cache.labelX ~= labelX or cache.labelY ~= labelY) then
                resources.labelFont:set_position_x(labelX);
                resources.labelFont:set_position_y(labelY);
                cache.labelX = labelX;
                cache.labelY = labelY;
            end
            resources.labelFont:set_visible(animOpacity > 0.5);
        else
            resources.labelFont:set_visible(false);
        end
    end

    -- ========================================
    -- 8. MP Cost Font (GDI - bottom right corner)
    -- ========================================
    if resources.mpCostFont then
        local showMpCost = params.showMpCost ~= false;
        if showMpCost and bind and animOpacity > 0.5 then
            -- Get MP cost (cached per action)
            local bindKey = (bind.actionType or '') .. ':' .. (bind.action or '');
            local mpCost = mpCostCache[bindKey];
            if mpCost == nil then
                mpCost = actions.GetMPCost(bind) or false;  -- false = no MP cost
                mpCostCache[bindKey] = mpCost;
            end

            if mpCost and mpCost ~= false then
                local mpText = tostring(mpCost);
                -- Only update text if changed
                if cache and cache.mpCostText ~= mpText then
                    resources.mpCostFont:set_text(mpText);
                    cache.mpCostText = mpText;
                end
                -- Position at top-right corner with padding
                local mpX = x + size - 3;  -- Right-aligned with small padding
                local mpY = y + 1;         -- Top with small padding
                if cache and (cache.mpCostX ~= mpX or cache.mpCostY ~= mpY) then
                    resources.mpCostFont:set_position_x(mpX);
                    resources.mpCostFont:set_position_y(mpY);
                    cache.mpCostX = mpX;
                    cache.mpCostY = mpY;
                end
                -- Only update font settings if changed
                if params.mpCostFontSize and cache and cache.mpCostFontSize ~= params.mpCostFontSize then
                    resources.mpCostFont:set_font_height(params.mpCostFontSize);
                    cache.mpCostFontSize = params.mpCostFontSize;
                end
                if params.mpCostFontColor and cache and cache.mpCostFontColor ~= params.mpCostFontColor then
                    resources.mpCostFont:set_font_color(params.mpCostFontColor);
                    cache.mpCostFontColor = params.mpCostFontColor;
                end
                resources.mpCostFont:set_visible(true);
            else
                resources.mpCostFont:set_visible(false);
            end
        else
            resources.mpCostFont:set_visible(false);
        end
    end

    -- ========================================
    -- 9. ImGui: Frame Overlay
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
    Matches the XIUI macro palette tooltip style.
]]--
function M.DrawTooltip(bind)
    if not bind then return; end

    -- XIUI Color Scheme (matching macro palette)
    local COLORS = {
        gold = {0.957, 0.855, 0.592, 1.0},
        bgDark = {0.067, 0.063, 0.055, 0.95},
        border = {0.3, 0.28, 0.24, 0.8},
        textDim = {0.6, 0.6, 0.6, 1.0},
    };

    -- Action type labels (matching macro palette)
    local ACTION_TYPE_LABELS = {
        ma = 'Spell (ma)',
        ja = 'Ability (ja)',
        ws = 'Weaponskill (ws)',
        item = 'Item',
        equip = 'Equip',
        macro = 'Macro',
        pet = 'Pet Command',
    };

    -- Style the tooltip
    imgui.PushStyleColor(ImGuiCol_PopupBg, COLORS.bgDark);
    imgui.PushStyleColor(ImGuiCol_Border, COLORS.border);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {8, 6});

    imgui.BeginTooltip();

    -- Action name (gold)
    local displayName = bind.displayName or bind.action or 'Unknown';
    imgui.TextColored(COLORS.gold, displayName);

    imgui.Spacing();

    -- Action type
    local typeLabel = ACTION_TYPE_LABELS[bind.actionType] or bind.actionType or '?';
    imgui.TextColored(COLORS.textDim, 'Type: ' .. typeLabel);

    -- Target
    if bind.target and bind.target ~= '' then
        imgui.TextColored(COLORS.textDim, 'Target: <' .. bind.target .. '>');
    end

    -- Macro text preview (if macro type)
    if bind.actionType == 'macro' and bind.macroText then
        imgui.Spacing();
        imgui.TextColored(COLORS.textDim, bind.macroText);
    end

    imgui.EndTooltip();

    imgui.PopStyleVar();
    imgui.PopStyleColor(2);
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
    if resources.mpCostFont then resources.mpCostFont:set_visible(false); end
end

return M;
