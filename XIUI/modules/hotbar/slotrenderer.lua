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
local skillchain = require('modules.hotbar.skillchain');

-- Cache for MP cost lookups (keyed by action key string)
local mpCostCache = {};

-- Cache for action availability checks (keyed by action key string)
-- Structure: { isAvailable = bool, reason = string|nil }
local availabilityCache = {};

-- Cache for item quantity lookups (keyed by itemId or itemName)
-- Structure: { quantity = number, timestamp = number }
-- CRITICAL: Without this cache, item quantity lookups scan ALL inventory slots EVERY FRAME
-- which causes massive performance issues (especially for items without itemId that require name matching)
local itemQuantityCache = {};
local ITEM_QUANTITY_CACHE_TTL = 2.0;  -- Cache for 2 seconds (inventory doesn't change that often)

-- Containers to search for item quantities
local ITEM_CONTAINERS = { 0, 8, 10, 11, 12, 13, 14, 15, 16 };  -- Inventory, wardrobes, satchel, etc.

-- Ninja spell to tool mapping
-- Maps spell name prefixes to required tool names
local NINJA_TOOL_MAPPING = {
    -- Elemental Ninjutsu (damage)
    ['Katon'] = 'Uchitake',       -- Fire
    ['Hyoton'] = 'Tsurara',       -- Ice
    ['Huton'] = 'Kawahori-Ogi',   -- Wind
    ['Doton'] = 'Makibishi',      -- Earth
    ['Suiton'] = 'Mizu-Deppo',    -- Water
    ['Raiton'] = 'Hiraishin',     -- Lightning
    -- Utility Ninjutsu
    ['Utsusemi'] = 'Shihei',      -- Shadows
    ['Tonko'] = 'Shinobi-Tabi',   -- Invisible
    ['Monomi'] = 'Sanjaku-Tenugui', -- Sneak
    -- Debuff Ninjutsu
    ['Kurayami'] = 'Soshi',       -- Blind
    ['Hojo'] = 'Kaginawa',        -- Slow
    ['Jubaku'] = 'Jusatsu',       -- Paralyze
    ['Dokumori'] = 'Kodoku',      -- Poison
    ['Aisha'] = 'Kodoku',         -- Gravity (same as Dokumori)
    -- High-level Ninjutsu
    ['Migawari'] = 'Mokujin',     -- Substitute
    ['Yurin'] = 'Ryuno',          -- Intimidate
    ['Myoshu'] = 'Kabenro',       -- Acc boost
    ['Gekka'] = 'Shikanofuda',    -- Store TP
    ['Yain'] = 'Jinko',           -- Subtle Blow
    ['Kakka'] = 'Shikanofuda',    -- Attack boost (same as Gekka)
};

-- Cache for ninjutsu spell type lookups
local ninjutsuCache = {};

local M = {};

-- Get abbreviated text for an action (used when no icon available)
-- @param bind: Action bind data with displayName or action field
-- @return: max 4 character abbreviation string
local function GetActionAbbreviation(bind)
    if not bind then return '?'; end
    local name = bind.displayName or bind.action or '';
    if name == '' then return '?'; end

    -- If short enough, just use it
    if #name <= 4 then
        return name:upper();
    end

    -- Check if multi-word (contains space)
    local words = {};
    for word in name:gmatch('%S+') do
        table.insert(words, word);
    end

    if #words > 1 then
        -- Multi-word: take first letter of each word (up to 4)
        local abbr = '';
        for i = 1, math.min(#words, 4) do
            abbr = abbr .. words[i]:sub(1, 1):upper();
        end
        return abbr;
    else
        -- Single word: take first 4 characters
        return name:sub(1, 4):upper();
    end
end

-- Cache for equipment checks (keyed by itemId)
local equipmentCheckCache = {};

-- Equipment item types in FFXI
-- Type 4 = Weapon, Type 5 = Armor (includes all armor, accessories, etc.)
local EQUIPMENT_TYPES = { [4] = true, [5] = true };

-- Check if an item is equipment (armor, weapons, accessories) by its item data
-- Requires itemId for reliable detection
-- @param itemId: Item ID to check (required for reliable detection)
-- @return: true if equipment, false if consumable, nil if unknown (no itemId)
local function IsEquipmentItem(itemId)
    -- Must have itemId for reliable detection
    if not itemId or itemId <= 0 or itemId == 65535 then
        return nil;  -- Unknown - can't determine without itemId
    end

    -- Check cache first
    if equipmentCheckCache[itemId] ~= nil then
        return equipmentCheckCache[itemId];
    end

    local resMgr = AshitaCore:GetResourceManager();
    if not resMgr then return nil; end

    local isEquip = false;
    local item = resMgr:GetItemById(itemId);
    if item then
        -- Multiple checks for equipment detection:
        -- 1. Type field (4=Weapon, 5=Armor) - most reliable for retail
        if item.Type and EQUIPMENT_TYPES[item.Type] then
            isEquip = true;
        -- 2. Slots field (non-zero = equippable to body slot)
        elseif item.Slots and item.Slots > 0 then
            isEquip = true;
        -- 3. Jobs field (non-zero = job-restricted, implies equipment)
        elseif item.Jobs and item.Jobs > 0 then
            isEquip = true;
        -- 4. Level field (non-zero = has level requirement, implies equipment)
        elseif item.Level and item.Level > 0 then
            isEquip = true;
        -- 5. StackSize=1 and not Usable type (Type 7) - catches Horizon augmented gear
        --    Augmented items on private servers often have Type=1 but StackSize=1
        --    Consumables that stack (potions, food) have StackSize > 1
        elseif item.StackSize and item.StackSize == 1 and item.Type ~= 7 then
            isEquip = true;
        end
    end

    equipmentCheckCache[itemId] = isEquip;
    return isEquip;
end

-- Get total quantity of an item across all containers
-- @param itemId: Item ID to look up
-- @param itemName: Item name (fallback for lookup)
-- @return: Total quantity or nil
function M.GetItemQuantity(itemId, itemName)
    -- Build cache key (prefer itemId, fall back to name)
    local cacheKey = itemId and ('id:' .. itemId) or (itemName and ('name:' .. itemName) or nil);
    if not cacheKey then return nil; end

    -- Check cache first (CRITICAL for performance - avoids full inventory scan every frame)
    local now = os.clock();
    local cached = itemQuantityCache[cacheKey];
    if cached and (now - cached.timestamp) < ITEM_QUANTITY_CACHE_TTL then
        return cached.quantity;
    end

    local memMgr = AshitaCore:GetMemoryManager();
    if not memMgr then return nil; end

    local inventory = memMgr:GetInventory();
    if not inventory then return nil; end

    local resMgr = AshitaCore:GetResourceManager();
    local totalCount = 0;

    for _, containerId in ipairs(ITEM_CONTAINERS) do
        local maxSlots = inventory:GetContainerCountMax(containerId);
        if maxSlots and maxSlots > 0 then
            for slotIndex = 1, maxSlots do
                local item = inventory:GetContainerItem(containerId, slotIndex);
                if item and item.Id and item.Id > 0 and item.Id ~= 65535 then
                    local match = false;
                    if itemId and item.Id == itemId then
                        match = true;
                    elseif itemName and resMgr then
                        local itemRes = resMgr:GetItemById(item.Id);
                        if itemRes and itemRes.Name and itemRes.Name[1] == itemName then
                            match = true;
                        end
                    end
                    if match then
                        totalCount = totalCount + (item.Count or 1);
                    end
                end
            end
        end
    end

    -- Cache the result
    local result = totalCount > 0 and totalCount or nil;
    itemQuantityCache[cacheKey] = { quantity = result, timestamp = now };

    return result;
end

-- Get the ninja tool name required for a ninjutsu spell
-- @param spellName: The spell name (e.g., "Utsusemi: Ni", "Katon: San")
-- @return: Tool name or nil if not a ninjutsu spell
local function GetNinjutsuToolName(spellName)
    if not spellName then return nil; end

    -- Check cache first
    if ninjutsuCache[spellName] ~= nil then
        return ninjutsuCache[spellName];
    end

    -- Extract the spell base name (before the colon, e.g., "Utsusemi" from "Utsusemi: Ni")
    local baseName = spellName:match('^([^:]+)');
    if baseName then
        baseName = baseName:gsub('%s+$', ''); -- Trim trailing whitespace
    end

    local toolName = NINJA_TOOL_MAPPING[baseName];
    ninjutsuCache[spellName] = toolName or false; -- Cache nil as false to distinguish from uncached
    return toolName;
end

-- Get the quantity of ninja tools for a ninjutsu spell
-- @param spellName: The spell name (e.g., "Utsusemi: Ni")
-- @return: Tool quantity (0+) if ninjutsu spell with tool, nil if not a ninjutsu spell
function M.GetNinjutsuToolQuantity(spellName)
    local toolName = GetNinjutsuToolName(spellName);
    if not toolName then return nil; end
    -- Return 0 if no tools found (instead of nil) so we can show "x0" in red
    return M.GetItemQuantity(nil, toolName) or 0;
end

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
    availabilityCache = {};
    mpCostCache = {};
    equipmentCheckCache = {};
    ninjutsuCache = {};
    itemQuantityCache = {};
end

-- Clear availability cache (call on job change, level sync, etc.)
function M.ClearAvailabilityCache()
    availabilityCache = {};
end

-- Clear item quantity cache (call on inventory changes)
function M.ClearItemQuantityCache()
    itemQuantityCache = {};
end

local function GetAssetsPath()
    if not assetsPath then
        assetsPath = string.format('%saddons\\XIUI\\assets\\hotbar\\', AshitaCore:GetInstallPath());
    end
    return assetsPath;
end

-- Calculate position based on anchor point within a slot
-- @param x, y: Top-left corner of the slot
-- @param size: Slot size in pixels
-- @param anchor: 'topLeft', 'topRight', 'bottomLeft', 'bottomRight'
-- @param offsetX, offsetY: Additional offset adjustments
-- @param padding: Padding from edge (default 2)
-- @return posX, posY
local function GetAnchoredPosition(x, y, size, anchor, offsetX, offsetY, padding)
    padding = padding or 2;
    offsetX = offsetX or 0;
    offsetY = offsetY or 0;
    
    local posX, posY;
    
    if anchor == 'topRight' then
        posX = x + size - padding;
        posY = y + padding;
    elseif anchor == 'bottomLeft' then
        posX = x + padding;
        posY = y + size - padding - 10;  -- Account for font height
    elseif anchor == 'bottomRight' then
        posX = x + size - padding;
        posY = y + size - padding - 10;  -- Account for font height
    else  -- Default: topLeft
        posX = x + padding;
        posY = y + padding;
    end
    
    return posX + offsetX, posY + offsetY;
end

-- ============================================
-- Skillchain Highlight Rendering
-- ============================================

-- Skillchain icon cache (loaded on first use)
local skillchainIconCache = {};
local skillchainIconsPath = nil;

local function GetSkillchainIconsPath()
    if not skillchainIconsPath then
        skillchainIconsPath = string.format('%saddons\\XIUI\\assets\\hotbar\\skillchain\\', AshitaCore:GetInstallPath());
    end
    return skillchainIconsPath;
end

-- Draw a single dashed line segment
-- @param drawList: ImGui draw list
-- @param x1, y1: Start point
-- @param x2, y2: End point
-- @param color: Line color (imgui color)
-- @param thickness: Line thickness
-- @param dashLen: Length of each dash
-- @param gapLen: Length of gap between dashes
-- @param offset: Animation offset for marching ants effect
local function DrawDashedLine(drawList, x1, y1, x2, y2, color, thickness, dashLen, gapLen, offset)
    local dx = x2 - x1;
    local dy = y2 - y1;
    local len = math.sqrt(dx * dx + dy * dy);
    if len == 0 then return; end

    -- Normalize direction
    local nx = dx / len;
    local ny = dy / len;

    -- Start position with offset for animation
    local totalLen = dashLen + gapLen;
    local startOffset = offset % totalLen;

    local pos = -startOffset;  -- Start slightly before to handle offset
    while pos < len do
        local dashStart = math.max(0, pos);
        local dashEnd = math.min(len, pos + dashLen);

        if dashEnd > dashStart then
            local sx = x1 + nx * dashStart;
            local sy = y1 + ny * dashStart;
            local ex = x1 + nx * dashEnd;
            local ey = y1 + ny * dashEnd;
            drawList:AddLine({sx, sy}, {ex, ey}, color, thickness);
        end

        pos = pos + totalLen;
    end
end

-- Draw skillchain highlight on a slot (animated dashed border + icon)
-- @param drawList: ImGui draw list (foreground recommended)
-- @param x, y: Top-left corner of slot
-- @param size: Slot size in pixels
-- @param scName: Skillchain name (e.g., 'Light', 'Darkness', 'Fusion')
-- @param color: Highlight color (ARGB)
-- @param opacity: Overall opacity (0-1)
local function DrawSkillchainHighlight(drawList, x, y, size, scName, color, opacity)
    if not drawList or not scName or opacity <= 0.01 then return; end

    -- Animation offset for marching ants effect
    local animOffset = skillchain.GetAnimationOffset();

    -- Extract color components and apply opacity
    local a = math.floor(bit.rshift(bit.band(color, 0xFF000000), 24) * opacity);
    local r = bit.rshift(bit.band(color, 0x00FF0000), 16) / 255;
    local g = bit.rshift(bit.band(color, 0x0000FF00), 8) / 255;
    local b = bit.band(color, 0x000000FF) / 255;
    local lineColor = imgui.GetColorU32({r, g, b, a / 255});

    -- Dashed line parameters
    local dashLen = 4;
    local gapLen = 4;
    local thickness = 2;

    -- Draw dashed border (4 sides)
    -- Top edge
    DrawDashedLine(drawList, x, y, x + size, y, lineColor, thickness, dashLen, gapLen, animOffset);
    -- Right edge
    DrawDashedLine(drawList, x + size, y, x + size, y + size, lineColor, thickness, dashLen, gapLen, animOffset);
    -- Bottom edge
    DrawDashedLine(drawList, x + size, y + size, x, y + size, lineColor, thickness, dashLen, gapLen, animOffset);
    -- Left edge
    DrawDashedLine(drawList, x, y + size, x, y, lineColor, thickness, dashLen, gapLen, animOffset);

    -- Draw skillchain icon in top-right corner
    local iconSize = math.floor(size * 0.35);
    local iconX = x + size - iconSize - 2;
    local iconY = y + 2;

    -- Get or load icon texture
    local iconPath = GetSkillchainIconsPath() .. scName .. '.png';
    if not skillchainIconCache[scName] then
        local tex = textures:LoadTextureFromPath(iconPath);
        skillchainIconCache[scName] = tex;
    end

    local iconTex = skillchainIconCache[scName];
    if iconTex and iconTex.image then
        local iconPtr = tonumber(ffi.cast("uint32_t", iconTex.image));
        if iconPtr then
            local iconAlpha = math.floor(255 * opacity);
            local iconTint = bit.bor(bit.lshift(iconAlpha, 24), 0x00FFFFFF);
            drawList:AddImage(
                iconPtr,
                {iconX, iconY},
                {iconX + iconSize, iconY + iconSize},
                {0, 0}, {1, 1},
                iconTint
            );
        end
    end
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

        Skillchain:
        - skillchainName: (optional) Skillchain name to show highlight for (e.g., 'Light')
        - skillchainColor: (optional) Highlight color ARGB (default 0xFFD4AA44 gold)

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
    local baseIconSize = size - (iconPadding * 2);
    local iconPressScale = params.iconPressScale or 1.0;
    local targetIconSize = baseIconSize * iconPressScale;

    -- ========================================
    -- 3. Cooldown Info, MP Check & Availability Check
    -- ========================================
    local cooldown = recast.GetCooldownInfo(bind);
    local isOnCooldown = cooldown.isOnCooldown;
    local recastText = cooldown.recastText;

    -- Check if player has enough MP for spells
    local notEnoughMp = false;
    local bindKey = bind and ((bind.actionType or '') .. ':' .. (bind.action or '')) or '';
    if bind and bind.actionType == 'ma' then
        local mpCost = mpCostCache[bindKey];
        if mpCost == nil then
            mpCost = actions.GetMPCost(bind) or false;
            mpCostCache[bindKey] = mpCost;
        end
        if mpCost and mpCost ~= false then
            local party = AshitaCore:GetMemoryManager():GetParty();
            local playerMp = party and party:GetMemberMP(0) or 0;
            notEnoughMp = playerMp < mpCost;
        end
    end

    -- Check if action is available (job/level requirements)
    local isUnavailable = false;
    local unavailableReason = nil;
    if bind and (bind.actionType == 'ma' or bind.actionType == 'ja' or bind.actionType == 'ws') then
        -- Include job/subjob in cache key so cache invalidates on job change
        local player = AshitaCore:GetMemoryManager():GetPlayer();
        local jobId = player and player:GetMainJob() or 0;
        local subjobId = player and player:GetSubJob() or 0;
        local availKey = bindKey .. ':' .. jobId .. ':' .. subjobId;

        local cached = availabilityCache[availKey];
        if cached == nil then
            local available, reason = actions.IsActionAvailable(bind);
            -- Don't cache if reason is "pending" (player state invalid, e.g., during zoning)
            if reason ~= "pending" then
                availabilityCache[availKey] = { isAvailable = available, reason = reason };
                cached = availabilityCache[availKey];
            else
                -- Use temp result but don't cache
                cached = { isAvailable = available, reason = nil };
            end
        end
        isUnavailable = not cached.isAvailable;
        unavailableReason = cached.reason;
    end

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

            -- Calculate color: unavailable/cooldown/noMP darkening + dim factor + animation opacity
            local colorMult = 1.0;
            local applyGreyTint = false;
            if isUnavailable then
                colorMult = 0.35;  -- Significantly dimmed when unavailable
                applyGreyTint = true;  -- Apply grey/desaturated tint
            elseif isOnCooldown then
                colorMult = 0.4;
            elseif notEnoughMp then
                colorMult = 0.6;  -- Slightly dimmed when not enough MP
            end
            colorMult = colorMult * dimFactor;

            -- Calculate RGB values
            local r, g, b;
            if applyGreyTint then
                -- Grey tint for unavailable actions (desaturated)
                local grey = math.floor(180 * colorMult);  -- Lighter grey base
                r, g, b = grey, grey, grey;
            else
                local rgb = math.floor(255 * colorMult);
                r, g, b = rgb, rgb, rgb;
            end

            local alpha = math.floor(255 * animOpacity * (isUnavailable and 0.7 or 1.0));  -- Lower opacity when unavailable
            local iconColor = bit.bor(
                bit.lshift(alpha, 24),
                bit.lshift(r, 16),
                bit.lshift(g, 8),
                b
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

                -- Calculate color: unavailable/cooldown/noMP darkening + dim factor + animation opacity
                local colorMult = 1.0;
                local applyGreyTint = false;
                if isUnavailable then
                    colorMult = 0.35;  -- Significantly dimmed when unavailable
                    applyGreyTint = true;
                elseif isOnCooldown then
                    colorMult = 0.4;
                elseif notEnoughMp then
                    colorMult = 0.6;  -- Slightly dimmed when not enough MP
                end
                colorMult = colorMult * dimFactor;

                -- Calculate RGB values
                local r, g, b;
                if applyGreyTint then
                    local grey = math.floor(180 * colorMult);
                    r, g, b = grey, grey, grey;
                else
                    local rgb = math.floor(255 * colorMult);
                    r, g, b = rgb, rgb, rgb;
                end

                local alpha = math.floor(255 * animOpacity * (isUnavailable and 0.7 or 1.0));
                local tintColor = bit.bor(
                    bit.lshift(alpha, 24),
                    bit.lshift(r, 16),
                    bit.lshift(g, 8),
                    b
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
    -- 4b. Abbreviation Text Fallback (when no icon available)
    -- ========================================
    -- Hide abbreviation when cooldown timer is showing (GDI renders before ImGui, so text would overlap)
    if not iconRendered and bind and animOpacity > 0.5 and not recastText then
        local drawList = imgui.GetWindowDrawList();
        if drawList then
            local abbr = GetActionAbbreviation(bind);
            local textSize = imgui.CalcTextSize(abbr);
            local textX = x + (size - textSize) / 2;
            local textY = y + (size - 14) / 2;  -- Approximate font height

            -- Gold color for abbreviation text (matching XIUI style)
            -- Apply dimming when unavailable/not enough MP
            local textColorMult = 1.0;
            if isUnavailable then
                textColorMult = 0.35;
            elseif notEnoughMp then
                textColorMult = 0.6;
            end
            textColorMult = textColorMult * dimFactor;

            local textColor = imgui.GetColorU32({
                0.957 * textColorMult,
                0.855 * textColorMult,
                0.592 * textColorMult,
                animOpacity
            });
            drawList:AddText({textX, textY}, textColor, abbr);
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
            -- Calculate position using anchor
            local kbX, kbY = GetAnchoredPosition(x, y, size, params.keybindAnchor, params.keybindOffsetX, params.keybindOffsetY);
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
            -- Only update font size if changed
            if params.labelFontSize and cache and cache.labelFontSize ~= params.labelFontSize then
                resources.labelFont:set_font_height(params.labelFontSize);
                cache.labelFontSize = params.labelFontSize;
            end
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

            -- Determine label color based on state
            -- Priority: Unavailable (grey) > Cooldown (grey) > Not enough MP (red) > Normal
            local labelColor = params.labelFontColor or 0xFFFFFFFF;

            if isUnavailable then
                -- Grey when action is unavailable (wrong job, under synced, etc)
                labelColor = 0xFF888888;
            elseif isOnCooldown then
                -- Grey when on cooldown
                labelColor = params.labelCooldownColor or 0xFF888888;
            elseif notEnoughMp then
                -- Red when not enough MP
                labelColor = params.labelNoMpColor or 0xFFFF4444;
            end

            -- Only update color if changed
            if cache and cache.labelFontColor ~= labelColor then
                resources.labelFont:set_font_color(labelColor);
                cache.labelFontColor = labelColor;
            end

            resources.labelFont:set_visible(animOpacity > 0.5);
        else
            resources.labelFont:set_visible(false);
        end
    end

    -- ========================================
    -- 8. MP Cost Font (GDI - anchored position)
    -- Shows "X" when action is unavailable, otherwise shows MP cost
    -- ========================================
    if resources.mpCostFont then
        local showMpCost = params.showMpCost ~= false;
        if showMpCost and bind and animOpacity > 0.5 then
            -- Calculate position using anchor
            local mpX, mpY = GetAnchoredPosition(x, y, size, params.mpCostAnchor, params.mpCostOffsetX, params.mpCostOffsetY);
            
            -- If action is unavailable, show "X" instead of MP cost
            if isUnavailable then
                local xText = "X";
                if cache and cache.mpCostText ~= xText then
                    resources.mpCostFont:set_text(xText);
                    cache.mpCostText = xText;
                end
                if cache and (cache.mpCostX ~= mpX or cache.mpCostY ~= mpY) then
                    resources.mpCostFont:set_position_x(mpX);
                    resources.mpCostFont:set_position_y(mpY);
                    cache.mpCostX = mpX;
                    cache.mpCostY = mpY;
                end
                if params.mpCostFontSize and cache and cache.mpCostFontSize ~= params.mpCostFontSize then
                    resources.mpCostFont:set_font_height(params.mpCostFontSize);
                    cache.mpCostFontSize = params.mpCostFontSize;
                end
                -- Red color for unavailable "X"
                local xColor = 0xFFFF4444;
                if cache and cache.mpCostFontColor ~= xColor then
                    resources.mpCostFont:set_font_color(xColor);
                    cache.mpCostFontColor = xColor;
                end
                resources.mpCostFont:set_visible(true);
            else
                -- Normal MP cost display
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

                    -- Determine MP cost color - red if not enough MP
                    local mpCostColor = params.mpCostFontColor or 0xFFD4FF97;
                    if notEnoughMp then
                        mpCostColor = params.mpCostNoMpColor or 0xFFFF4444;
                    end

                    if cache and cache.mpCostFontColor ~= mpCostColor then
                        resources.mpCostFont:set_font_color(mpCostColor);
                        cache.mpCostFontColor = mpCostColor;
                    end
                    resources.mpCostFont:set_visible(true);
                else
                    resources.mpCostFont:set_visible(false);
                end
            end
        else
            resources.mpCostFont:set_visible(false);
        end
    end

    -- ========================================
    -- 9. Item/Tool Quantity Font (GDI - anchored position)
    -- Shows quantity for: consumable items, ninjutsu tools
    -- ========================================
    if resources.quantityFont then
        local showQuantity = params.showQuantity ~= false;
        local quantity = nil;
        local shouldShowQty = false;

        if showQuantity and bind and animOpacity > 0.5 then
            if bind.actionType == 'item' then
                -- Skip quantity display for equipment items (armor, weapons, accessories)
                -- IsEquipmentItem returns: true = equipment, false = consumable, nil = unknown (no itemId)
                local isEquipment = nil;
                if bind.itemId then
                    -- Check cache first, but invalidate if itemId changed (slot was reassigned)
                    if cache and cache.isEquipment ~= nil and cache.equipmentCheckItemId == bind.itemId then
                        isEquipment = cache.isEquipment;
                    else
                        isEquipment = IsEquipmentItem(bind.itemId);
                        if cache then
                            cache.isEquipment = isEquipment;
                            cache.equipmentCheckItemId = bind.itemId;
                        end
                    end
                end
                -- Show quantity for consumables (isEquipment == false) or when we can't determine (isEquipment == nil)
                -- Hide quantity only when we're certain it's equipment (isEquipment == true)
                if isEquipment ~= true then
                    quantity = M.GetItemQuantity(bind.itemId, bind.action) or 0;
                    shouldShowQty = true;
                end
            elseif bind.actionType == 'ma' then
                -- Check if this is a ninjutsu spell that requires a tool
                local toolQty = M.GetNinjutsuToolQuantity(bind.action);
                if toolQty ~= nil then
                    quantity = toolQty;
                    shouldShowQty = true;
                end
            end
        end

        if shouldShowQty and quantity ~= nil then
            -- Format quantity text
            local qtyText = 'x' .. tostring(quantity);
            -- Only update text if changed
            if cache and cache.quantityText ~= qtyText then
                resources.quantityFont:set_text(qtyText);
                cache.quantityText = qtyText;
            end
            -- Calculate position using anchor
            local qtyX, qtyY = GetAnchoredPosition(x, y, size, params.quantityAnchor, params.quantityOffsetX, params.quantityOffsetY);
            if cache and (cache.quantityX ~= qtyX or cache.quantityY ~= qtyY) then
                resources.quantityFont:set_position_x(qtyX);
                resources.quantityFont:set_position_y(qtyY);
                cache.quantityX = qtyX;
                cache.quantityY = qtyY;
            end
            -- Only update font settings if changed
            if params.quantityFontSize and cache and cache.quantityFontSize ~= params.quantityFontSize then
                resources.quantityFont:set_font_height(params.quantityFontSize);
                cache.quantityFontSize = params.quantityFontSize;
            end
            -- Use red color for 0 quantity, normal color otherwise
            local qtyColor = quantity == 0 and 0xFFFF4444 or (params.quantityFontColor or 0xFFFFFFFF);
            if cache and cache.quantityFontColor ~= qtyColor then
                resources.quantityFont:set_font_color(qtyColor);
                cache.quantityFontColor = qtyColor;
            end
            resources.quantityFont:set_visible(true);
        else
            resources.quantityFont:set_visible(false);
        end
    end

    -- ========================================
    -- 10. Frame Overlay (Primitive)
    -- ========================================
    if resources.framePrim then
        if params.showFrame and animOpacity > 0.01 then
            -- Determine frame texture path: custom path or default
            local framePath = nil;
            if params.customFramePath and params.customFramePath ~= '' then
                -- Custom path: resolve relative to hotbar assets directory
                framePath = GetAssetsPath() .. params.customFramePath;
            else
                -- Default: use cached path from textures module
                framePath = textures:GetPath('frame');
            end

            if framePath then
                -- Only set texture if changed
                if cache and cache.frameTexturePath ~= framePath then
                    resources.framePrim.texture = framePath;
                    cache.frameTexturePath = framePath;
                end

                -- Position frame over slot
                if cache and (cache.frameX ~= x or cache.frameY ~= y) then
                    resources.framePrim.position_x = x;
                    resources.framePrim.position_y = y;
                    cache.frameX = x;
                    cache.frameY = y;
                end

                -- Scale frame to slot size (frame.png is 40x40 base)
                local frameScale = size / 40;
                if cache and cache.frameScale ~= frameScale then
                    resources.framePrim.scale_x = frameScale;
                    resources.framePrim.scale_y = frameScale;
                    cache.frameScale = frameScale;
                end

                -- Apply animation opacity to frame
                local frameAlpha = math.floor(255 * animOpacity);
                local frameColor = bit.bor(bit.lshift(frameAlpha, 24), 0x00FFFFFF);
                if cache and cache.frameColor ~= frameColor then
                    resources.framePrim.color = frameColor;
                    cache.frameColor = frameColor;
                end

                resources.framePrim.visible = true;
            else
                resources.framePrim.visible = false;
            end
        else
            resources.framePrim.visible = false;
        end
    end

    -- ========================================
    -- 11. ImGui: Hover/Pressed Visual Effects
    -- Use foreground draw list to avoid window clipping issues
    -- ========================================
    local fgDrawList = imgui.GetForegroundDrawList();
    if fgDrawList and animOpacity > 0.5 then
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
            fgDrawList:AddRectFilled({x, y}, {x + size, y + size}, pressedTintColor, 4);
            fgDrawList:AddRect({x, y}, {x + size, y + size}, pressedBorderColor, 4, 0, 2);
        elseif isHovered and not dragdrop.IsDragging() then
            -- Hover effect (mouse)
            local hoverTintColor = imgui.GetColorU32({1.0, 1.0, 1.0, 0.15 * animOpacity});
            local hoverBorderColor = imgui.GetColorU32({1.0, 1.0, 1.0, 0.10 * animOpacity});
            fgDrawList:AddRectFilled({x, y}, {x + size, y + size}, hoverTintColor, 2);
            fgDrawList:AddRect({x, y}, {x + size, y + size}, hoverBorderColor, 2, 0, 1);
        end

        -- Skillchain highlight (animated dotted border + icon)
        if params.skillchainName then
            local scColor = params.skillchainColor or 0xFFD4AA44;  -- Default gold
            DrawSkillchainHighlight(fgDrawList, x, y, size, params.skillchainName, scColor, animOpacity);
        end
    end

    -- ========================================
    -- 12. Drop Zone Registration
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
                    -- Default: execute the command (handles multi-line macros)
                    actions.ExecuteCommandString(command);
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
        red = {1.0, 0.3, 0.3, 1.0},
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

    -- Helper to format target (strips existing brackets, adds fresh ones)
    local function formatTarget(target)
        if not target then return nil; end
        local cleaned = target:gsub('[<>]', '');
        if cleaned == '' then return nil; end
        return '<' .. cleaned .. '>';
    end

    -- Check if action is unavailable for current job/subjob (cached lookup)
    local isUnavailable = false;
    if bind.actionType == 'ma' or bind.actionType == 'ja' or bind.actionType == 'ws' then
        local bindKey = (bind.actionType or '') .. ':' .. (bind.action or '');
        local player = AshitaCore:GetMemoryManager():GetPlayer();
        local jobId = player and player:GetMainJob() or 0;
        local subjobId = player and player:GetSubJob() or 0;
        local availKey = bindKey .. ':' .. jobId .. ':' .. subjobId;

        local cached = availabilityCache[availKey];
        if cached then
            isUnavailable = not cached.isAvailable;
        else
            -- Not cached yet, do a quick check
            local available, reason = actions.IsActionAvailable(bind);
            if reason ~= "pending" then
                isUnavailable = not available;
            end
        end
    end

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

    -- Target (not shown for macro type since targets are embedded in macro text)
    if bind.actionType ~= 'macro' and bind.target and bind.target ~= '' then
        local formattedTarget = formatTarget(bind.target);
        if formattedTarget then
            imgui.TextColored(COLORS.textDim, 'Target: ' .. formattedTarget);
        end
    end

    -- Macro text preview (if macro type)
    if bind.actionType == 'macro' and bind.macroText then
        imgui.Spacing();
        imgui.TextColored(COLORS.textDim, bind.macroText);
    end

    -- Unavailable warning (red text)
    if isUnavailable then
        imgui.Spacing();
        imgui.TextColored(COLORS.red, 'Action not available');
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
    if resources.framePrim then resources.framePrim.visible = false; end
    if resources.timerFont then resources.timerFont:set_visible(false); end
    if resources.keybindFont then resources.keybindFont:set_visible(false); end
    if resources.labelFont then resources.labelFont:set_visible(false); end
    if resources.mpCostFont then resources.mpCostFont:set_visible(false); end
    if resources.quantityFont then resources.quantityFont:set_visible(false); end
end

return M;
