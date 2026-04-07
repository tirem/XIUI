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
local statusHandler = require('handlers.statushandler');
local imtext = require('libs.imtext');

-- Deferred tooltip: stored during render, drawn after all windows to ensure z-order
local pendingTooltipBind = nil;

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

-- Ninja spell to tool mapping (using item IDs for reliable lookups)
-- Maps spell name prefixes to required tool item IDs
-- IDs verified from https://www.ffxiah.com/browse/49/ninja-tools
local NINJA_TOOL_MAPPING = {
    -- Elemental Ninjutsu (Inoshishinofuda - 2971)
    ['Katon'] = { 1161, 2971 },     -- Uchitake (Fire)
    ['Hyoton'] = { 1164, 2971 },    -- Tsurara (Ice)
    ['Huton'] = { 1167, 2971 },     -- Kawahori-Ogi (Wind)
    ['Doton'] = { 1170, 2971 },     -- Makibishi (Earth)
    ['Raiton'] = { 1173, 2971 },    -- Hiraishin (Lightning)
    ['Suiton'] = { 1176, 2971 },    -- Mizu-Deppo (Water)
    -- Buffing Ninjutsu (Shikanofuda - 2972)
    ['Utsusemi'] = { 1179, 2972 },   -- Shihei (Shadows)
    ['Tonko'] = { 1194, 2972 },      -- Shinobi-Tabi (Invisible)
    ['Monomi'] = { 2553, 2972 },     -- Sanjaku-Tenugui (Sneak)
    ['Migawari'] = { 2970, 2972 },   -- Mokujin (One-shot immunity)
    ['Myoshu'] = { 2642, 2972 },     -- Kabenro (Subtle blow)
    ['Gekka'] = { 8803, 2972 },      -- Ranka (Enmity increase)
    ['Yain'] = { 8804, 2972 },       -- Furusumi (Enmity decrease)
    ['Kakka'] = { 2644, 2972 },      -- Ryuno (Store TP)
    -- Debuffing Ninjutsu (Chonofuda - 2973)
    ['Kurayami'] = { 1188, 2973 },   -- Sairui-ran (Blind)
    ['Hojo'] = { 1185, 2973 },       -- Kaginawa (Slow)
    ['Jubaku'] = { 1182, 2973 },     -- Jusatsu (Paralyze)
    ['Dokumori'] = { 1191, 2973 },   -- Kodoku (Poison)
    ['Aisha'] = { 2555, 2973 },      -- Soshi (Attack down)
    ['Yurin'] = { 2643, 2973 },      -- Jinko (Reduces enemy TP gain)
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

-- Ammo slot mask - items that ONLY equip to this slot are consumables (bolts, bullets, arrows)
local AMMO_SLOT_MASK = 0x0008;

-- Maps ammo item names to the status effect ID they apply
-- Status IDs: 2=Sleep, 3=Poison, 4=Paralysis, 5=Blind, 6=Silence, 10=Stun, 147=Attack Down, 149=Defense Down
local AMMO_STATUS_EFFECTS_BY_NAME = {
    -- Bolts
    ['Acid Bolt']     = 149,  -- Defense Down
    ['Sleep Bolt']    = 2,    -- Sleep
    ['Blind Bolt']    = 5,    -- Blindness
    ['Venom Bolt']    = 3,    -- Poison
    ['Bloody Bolt']   = 700,  -- Drain (custom icon)
    -- Arrows
    ['Sleep Arrow']     = 2,    -- Sleep
    ['Poison Arrow']    = 3,    -- Poison
    ['Kabura Arrow']    = 6,    -- Silence
    ['Paralysis Arrow'] = 4,    -- Paralysis
    ['Demon Arrow']     = 147,  -- Attack Down
    -- Bullets
    ['Spartan Bullet']  = 10,   -- Stun
};

-- Runtime cache: itemId -> statusId (populated on first lookup)
local ammoStatusCache = {};

-- Get status effect ID for ammo item (if any)
-- Uses item name lookup with caching for performance
local function GetAmmoStatusEffect(itemId)
    if not itemId or itemId <= 0 then return nil; end

    -- Check cache first
    if ammoStatusCache[itemId] ~= nil then
        return ammoStatusCache[itemId] or nil;  -- false means "checked, no effect"
    end

    -- Look up item name
    local resMgr = AshitaCore:GetResourceManager();
    if not resMgr then return nil; end

    local item = resMgr:GetItemById(itemId);
    if item and item.Name and item.Name[1] then
        local statusId = AMMO_STATUS_EFFECTS_BY_NAME[item.Name[1]];
        ammoStatusCache[itemId] = statusId or false;  -- Cache misses too
        return statusId;
    end

    ammoStatusCache[itemId] = false;
    return nil;
end

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
        -- 1. Ammo-only items (bolts, bullets, arrows) are consumables, not equipment
        --    Must check FIRST since ammo has Type=4 (Weapon) but should show counts
        if item.Slots and item.Slots == AMMO_SLOT_MASK then
            isEquip = false;
        -- 2. Type field (4=Weapon, 5=Armor) - most reliable for retail
        elseif item.Type and EQUIPMENT_TYPES[item.Type] then
            isEquip = true;
        -- 3. Other equippable slots = equipment
        elseif item.Slots and item.Slots > 0 then
            isEquip = true;
        -- 4. Jobs field (non-zero = job-restricted, implies equipment)
        elseif item.Jobs and item.Jobs > 0 then
            isEquip = true;
        -- 5. Level field (non-zero = has level requirement, implies equipment)
        elseif item.Level and item.Level > 0 then
            isEquip = true;
        -- 6. StackSize=1 and not Usable type (Type 7) - catches Horizon augmented gear
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

-- Get the ninja tool ID required for a ninjutsu spell
-- @param spellName: The spell name (e.g., "Utsusemi: Ni", "Katon: San")
-- @return: Tool item ID or nil if not a ninjutsu spell
local function GetNinjutsuToolIds(spellName)
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

    local toolIds = NINJA_TOOL_MAPPING[baseName];
    ninjutsuCache[spellName] = toolIds or false; -- Cache nil as false to distinguish from uncached
    return toolIds;
end

-- Get the quantity of ninja tools for a ninjutsu spell
-- @param spellName: The spell name (e.g., "Utsusemi: Ni")
-- @return: Tool quantity (0+) if ninjutsu spell with tool, nil if not a ninjutsu spell
function M.GetNinjutsuToolQuantity(spellName)
    local toolIds = GetNinjutsuToolIds(spellName);
    if not toolIds then return nil; end
    -- Return 0 if no tools found (instead of nil) so we can show "x0" in red
    local total = 0;
    for _, itemId in ipairs(toolIds) do
        total = total + (M.GetItemQuantity(itemId, nil) or 0);
    end
    return total;
end

-- Cached asset path
local assetsPath = nil;

-- Reusable result table for DrawSlot to avoid GC pressure
local drawSlotResult = { isHovered = false, command = nil };

-- Reusable position/UV tables for AddImage (avoids per-call table allocations)
local imgP1 = {0, 0};
local imgP2 = {0, 0};
local UV0 = {0, 0};
local UV1 = {1, 1};

-- Texture cache: keeps texture tables alive (prevents GC release of D3D textures)
-- and stores the derived uint32 pointer for fast AddImage calls.
-- Entry: { tex = textureTable, ptr = uint32Number } or false (load failed)
local texturePtrCache = {};

local function GetCachedTexturePtr(filePath)
    if not filePath then return nil; end
    local cached = texturePtrCache[filePath];
    if cached then return cached.ptr; end
    if cached == false then return nil; end
    local tex = textures:LoadTextureFromPath(filePath);
    if tex and tex.image then
        local ptr = tonumber(ffi.cast("uint32_t", tex.image));
        if ptr and ptr ~= 0 then
            texturePtrCache[filePath] = { tex = tex, ptr = ptr };
            return ptr;
        end
    end
    texturePtrCache[filePath] = false;
    return nil;
end

-- No-op: slot invalidation was used for D3D primitive caching, ImGui draws are stateless
function M.InvalidateSlotByKey(key) end

function M.ClearAllCache()
    availabilityCache = {};
    mpCostCache = {};
    equipmentCheckCache = {};
    ninjutsuCache = {};
    itemQuantityCache = {};
    ammoStatusCache = {};
    texturePtrCache = {};
end

function M.ClearSlotRenderingCache()
    texturePtrCache = {};
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
    local scale = gConfig.hotbarGlobal.skillchainIconScale or 1.0;
    local iconSize = math.floor(size * 0.35 * scale);
    local offsetX = gConfig.hotbarGlobal.skillchainIconOffsetX or 0;
    local offsetY = gConfig.hotbarGlobal.skillchainIconOffsetY or 0;
    local iconX = x + size - iconSize - 2 + offsetX;
    local iconY = y + 2 + offsetY;

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

-- Helper: determine if movement/drag-drop is locked for this slot
-- Shift key overrides the lock to allow dragging while locked
local function IsMovementLockedForDropZone(dropZoneId)
    if not dropZoneId then return false; end
    if imgui.GetIO().KeyShift then
        return false;
    end
    if gConfig and gConfig.hotbarLockMovement then
        return true;
    end
    return false;
end

--[[
    Render a slot with all components and handle all interactions.
    All rendering uses ImGui draw lists (AddImage for textures, imtext for text).
    MUST be called inside an ImGui window context for interactions to work.

    @param resources: Unused (kept for API compatibility)
    @param params: Rendering and interaction parameters (position, bind, icon, visual settings, callbacks)
    @return table: { isHovered, command } (reused - read values immediately, do NOT cache)
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
        return result;
    end

    -- Check hover state
    local mouseX, mouseY = imgui.GetMousePos();
    local isHovered = mouseX >= x and mouseX <= x + size and
                      mouseY >= y and mouseY <= y + size;
    result.isHovered = isHovered;

    -- ========================================
    -- 1. Slot Background (ImGui AddImage)
    -- ========================================
    local drawList = GetUIDrawList();
    do
        local slotTexPtr = GetCachedTexturePtr(GetAssetsPath() .. 'slot.png');
        if slotTexPtr and drawList then
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

            local slotOpacity = params.slotOpacity or 1.0;
            if slotOpacity < 1.0 then
                local a = math.floor(bit.rshift(bit.band(finalColor, 0xFF000000), 24) * slotOpacity);
                finalColor = bit.bor(bit.lshift(a, 24), bit.band(finalColor, 0x00FFFFFF));
            end

            if animOpacity < 1.0 then
                local a = math.floor(bit.rshift(bit.band(finalColor, 0xFF000000), 24) * animOpacity);
                finalColor = bit.bor(bit.lshift(a, 24), bit.band(finalColor, 0x00FFFFFF));
            end

            imgP1[1] = x; imgP1[2] = y;
            imgP2[1] = x + size; imgP2[2] = y + size;
            drawList:AddImage(slotTexPtr, imgP1, imgP2, UV0, UV1, finalColor);
        end
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
    recast.SetHHMMFormat(params.useHHMMCooldownFormat or false);
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
    -- 4. Icon Rendering (unified ImGui AddImage path)
    -- ========================================
    local iconRendered = false;

    if icon and icon.image and drawList then
        local iconPtr = tonumber(ffi.cast("uint32_t", icon.image));
        if iconPtr then
            local texWidth = icon.width or 40;
            local texHeight = icon.height or 40;

            local scale = targetIconSize / math.max(texWidth, texHeight);
            local renderedWidth = texWidth * scale;
            local renderedHeight = texHeight * scale;

            local iconX = x + (size - renderedWidth) / 2;
            local iconY = y + (size - renderedHeight) / 2;

            local colorMult = 1.0;
            local applyGreyTint = false;
            if isUnavailable then
                colorMult = 0.35;
                applyGreyTint = true;
            elseif isOnCooldown then
                colorMult = 0.4;
            elseif notEnoughMp then
                colorMult = 0.6;
            end
            colorMult = colorMult * dimFactor;

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

            imgP1[1] = iconX; imgP1[2] = iconY;
            imgP2[1] = iconX + renderedWidth; imgP2[2] = iconY + renderedHeight;
            drawList:AddImage(iconPtr, imgP1, imgP2, UV0, UV1, tintColor);
            iconRendered = true;
        end
    end

    -- ========================================
    -- 5. Frame Overlay (rendered above icon, below text)
    -- ========================================
    if params.showFrame and animOpacity > 0.01 and drawList then
        local framePath = nil;
        if params.customFramePath and params.customFramePath ~= '' then
            framePath = GetAssetsPath() .. params.customFramePath;
        else
            framePath = textures:GetPath('frame');
        end

        if framePath then
            local frameTexPtr = GetCachedTexturePtr(framePath);
            if frameTexPtr then
                local frameAlpha = math.floor(255 * animOpacity);
                local frameColor = bit.bor(bit.lshift(frameAlpha, 24), 0x00FFFFFF);

                imgP1[1] = x; imgP1[2] = y;
                imgP2[1] = x + size; imgP2[2] = y + size;
                drawList:AddImage(frameTexPtr, imgP1, imgP2, UV0, UV1, frameColor);
            end
        end
    end

    -- ========================================
    -- 6. Abbreviation Text Fallback (when no icon available)
    -- ========================================
    if not iconRendered and bind and animOpacity > 0.5 and not recastText and drawList then
        local abbr = GetActionAbbreviation(bind);
        local colorMult = 1.0;
        if isUnavailable then colorMult = 0.35;
        elseif notEnoughMp then colorMult = 0.6; end
        colorMult = colorMult * dimFactor;
        local r = math.floor(244 * colorMult);
        local g = math.floor(218 * colorMult);
        local b = math.floor(151 * colorMult);
        local a = math.floor(animOpacity * 255);
        local abbrColor = bit.bor(bit.lshift(a, 24), bit.lshift(r, 16), bit.lshift(g, 8), b);
        local abbrW = imtext.Measure(abbr, 12);
        local abbrX = x + (size - abbrW) / 2;
        local abbrY = y + size / 2 - 6;
        imtext.Draw(drawList, abbr, abbrX, abbrY, abbrColor, 12);
    end

    -- ========================================
    -- 7. Timer Text (cooldown)
    -- ========================================
    if recastText and animOpacity > 0.5 and drawList then
        local timerFontSize = params.recastTimerFontSize or 11;
        local timerColor = params.recastTimerFontColor or 0xFFFFFFFF;
        local remaining = cooldown.remaining or 0;
        if params.flashCooldownUnder5 and remaining > 0 and remaining < 5 then
            local pulseAlpha = 0.5 + 0.5 * math.sin(os.clock() * 8);
            local alpha = math.floor(pulseAlpha * 255);
            local cr = bit.rshift(bit.band(timerColor, 0x00FF0000), 16);
            local cg = bit.rshift(bit.band(timerColor, 0x0000FF00), 8);
            local cb = bit.band(timerColor, 0x000000FF);
            timerColor = bit.bor(bit.lshift(alpha, 24), bit.lshift(cr, 16), bit.lshift(cg, 8), cb);
        end
        local timerW = imtext.Measure(recastText, timerFontSize);
        local timerX = x + (size - timerW) / 2;
        local timerY = y + size / 2 - 6;
        imtext.Draw(drawList, recastText, timerX, timerY, timerColor, timerFontSize);
    end

    -- ========================================
    -- 8. Keybind Text
    -- ========================================
    if params.keybindText and params.keybindText ~= '' and animOpacity > 0.5 and drawList then
        local kbFontSize = params.keybindFontSize or 10;
        local kbColor = params.keybindFontColor or 0xFFFFFFFF;
        local kbAnchor = params.keybindAnchor or 'topLeft';
        local kbX, kbY = GetAnchoredPosition(x, y, size, kbAnchor, params.keybindOffsetX, params.keybindOffsetY);
        if kbAnchor == 'topRight' or kbAnchor == 'bottomRight' then
            local kbW = imtext.Measure(params.keybindText, kbFontSize);
            kbX = kbX - kbW;
        end
        imtext.DrawSimple(drawList, params.keybindText, kbX, kbY, kbColor, kbFontSize);
    end

    -- ========================================
    -- 9. Label Text (action name below slot)
    -- ========================================
    if params.showLabel and params.labelText and params.labelText ~= '' and animOpacity > 0.5 and drawList then
        local lblFontSize = params.labelFontSize or 10;
        local labelColor = params.labelFontColor or 0xFFFFFFFF;
        if isUnavailable then
            labelColor = 0xFF888888;
        elseif isOnCooldown then
            labelColor = params.labelCooldownColor or 0xFF888888;
        elseif notEnoughMp then
            labelColor = params.labelNoMpColor or 0xFFFF4444;
        end
        local lblW = imtext.Measure(params.labelText, lblFontSize);
        local labelX = x + (size - lblW) / 2 + (params.labelOffsetX or 0);
        local labelY = y + size + 2 + (params.labelOffsetY or 0);
        imtext.Draw(drawList, params.labelText, labelX, labelY, labelColor, lblFontSize);
    end

    -- ========================================
    -- 10. MP Cost Text (anchored position)
    -- Shows "X" when action is unavailable, otherwise shows MP cost
    -- ========================================
    do
        local showMpCost = params.showMpCost ~= false;
        if showMpCost and bind and animOpacity > 0.5 and drawList then
            local mpAnchor = params.mpCostAnchor or 'topRight';
            local mpFontSize = params.mpCostFontSize or 10;
            local mpX, mpY = GetAnchoredPosition(x, y, size, mpAnchor, params.mpCostOffsetX, params.mpCostOffsetY);

            if isUnavailable then
                local xText = "X";
                local xColor = 0xFFFF4444;
                if mpAnchor == 'topRight' or mpAnchor == 'bottomRight' then
                    local w = imtext.Measure(xText, mpFontSize);
                    mpX = mpX - w;
                end
                imtext.DrawSimple(drawList, xText, mpX, mpY, xColor, mpFontSize);
            else
                local mpCost = mpCostCache[bindKey];
                if mpCost == nil then
                    mpCost = actions.GetMPCost(bind) or false;
                    mpCostCache[bindKey] = mpCost;
                end
                if mpCost and mpCost ~= false then
                    local mpText = tostring(mpCost);
                    local mpCostColor = params.mpCostFontColor or 0xFFD4FF97;
                    if notEnoughMp then
                        mpCostColor = params.mpCostNoMpColor or 0xFFFF4444;
                    end
                    if mpAnchor == 'topRight' or mpAnchor == 'bottomRight' then
                        local w = imtext.Measure(mpText, mpFontSize);
                        mpX = mpX - w;
                    end
                    imtext.DrawSimple(drawList, mpText, mpX, mpY, mpCostColor, mpFontSize);
                end
            end
        end
    end

    -- ========================================
    -- 11. Item/Tool Quantity Text (anchored position)
    -- Shows quantity for: consumable items, ninjutsu tools
    -- ========================================
    do
        local showQuantity = params.showQuantity ~= false;
        local quantity = nil;
        local shouldShowQty = false;

        if showQuantity and bind and animOpacity > 0.5 then
            if bind.actionType == 'item' then
                local isEquipment = bind.itemId and IsEquipmentItem(bind.itemId) or nil;
                if isEquipment ~= true then
                    quantity = M.GetItemQuantity(bind.itemId, bind.action) or 0;
                    shouldShowQty = true;
                end
            elseif bind.actionType == 'ma' then
                local toolQty = M.GetNinjutsuToolQuantity(bind.action);
                if toolQty ~= nil then
                    quantity = toolQty;
                    shouldShowQty = true;
                end
            end
        end

        if shouldShowQty and quantity ~= nil and drawList then
            local qtyText = 'x' .. tostring(quantity);
            local qtyFontSize = params.quantityFontSize or 10;
            local qtyColor = quantity == 0 and 0xFFFF4444 or (params.quantityFontColor or 0xFFFFFFFF);
            local qtyAnchor = params.quantityAnchor or 'bottomRight';
            local qtyX, qtyY = GetAnchoredPosition(x, y, size, qtyAnchor, params.quantityOffsetX, params.quantityOffsetY);
            if qtyAnchor == 'topRight' or qtyAnchor == 'bottomRight' then
                local w = imtext.Measure(qtyText, qtyFontSize);
                qtyX = qtyX - w;
            end
            imtext.DrawSimple(drawList, qtyText, qtyX, qtyY, qtyColor, qtyFontSize);
        end
    end

    -- ========================================
    -- 12. Ammo Status Effect Icon (top-right corner)
    -- Shows status effect icon for ammo that applies debuffs
    -- ========================================
    if bind and bind.actionType == 'item' and bind.itemId and animOpacity > 0.5 then
        local statusId = GetAmmoStatusEffect(bind.itemId);
        if statusId then
            local statusIconPtr = statusHandler.get_icon_from_theme(gConfig.statusIconTheme, statusId);
            if statusIconPtr and drawList then
                local iconSize = size * 0.35;
                local padding = 2;
                local iconX = x + size - iconSize - padding;
                local iconY = y + padding;

                local iconAlpha = math.floor(255 * animOpacity);
                local iconTint = bit.bor(bit.lshift(iconAlpha, 24), 0x00FFFFFF);

                imgP1[1] = iconX; imgP1[2] = iconY;
                imgP2[1] = iconX + iconSize; imgP2[2] = iconY + iconSize;
                drawList:AddImage(statusIconPtr, imgP1, imgP2, UV0, UV1, iconTint);
            end
        end
    end

    -- ========================================
    -- 13. Hover/Pressed Visual Effects
    -- ========================================
    if drawList and animOpacity > 0.5 then
        if isPressed then
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
            local hoverTintColor = imgui.GetColorU32({1.0, 1.0, 1.0, 0.15 * animOpacity});
            local hoverBorderColor = imgui.GetColorU32({1.0, 1.0, 1.0, 0.10 * animOpacity});
            drawList:AddRectFilled({x, y}, {x + size, y + size}, hoverTintColor, 2);
            drawList:AddRect({x, y}, {x + size, y + size}, hoverBorderColor, 2, 0, 1);
        end

        if params.skillchainName then
            local scColor = params.skillchainColor or 0xFFD4AA44;
            DrawSkillchainHighlight(drawList, x, y, size, params.skillchainName, scColor, animOpacity);
        end
    end

    -- ========================================
    -- 14. Drop Zone Registration
    -- ========================================
    if params.dropZoneId and params.onDrop and not IsMovementLockedForDropZone(params.dropZoneId) then
        dragdrop.DropZone(params.dropZoneId, x, y, size, size, {
            accepts = params.dropAccepts or {'macro'},
            highlightColor = params.dropHighlightColor or 0xA8FFFFFF,
            onDrop = params.onDrop,
        });
    end

    -- ========================================
    -- 15. Interaction Button
    -- ========================================
    if params.buttonId then
        imgui.SetCursorScreenPos({x, y});
        imgui.InvisibleButton(params.buttonId, {size, size});

        local isItemHovered = imgui.IsItemHovered();
        local isItemActive = imgui.IsItemActive();

        -- Drag source
        if bind and params.dragType and params.getDragData then
            if isItemActive and imgui.IsMouseDragging(0, 3) then
                -- Prevent starting drags when movement is locked for this slot
                local movementLocked = params.dropZoneId and IsMovementLockedForDropZone(params.dropZoneId) or false;

                if not movementLocked then
                    if not dragdrop.IsDragging() and not dragdrop.IsDragPending() then
                        local dragData = params.getDragData();
                        if dragData then
                            dragdrop.StartDrag(params.dragType, dragData);
                        end
                    end
                end
            end
        end

        -- Left click to execute (BuildCommand deferred to click time to avoid per-frame cost)
        if isItemHovered and imgui.IsMouseReleased(0) then
            if not dragdrop.IsDragging() and not dragdrop.WasDragAttempted() then
                if params.onClick then
                    params.onClick();
                elseif bind then
                    local cmd = actions.BuildCommand(bind);
                    if cmd then
                        actions.ExecuteCommandString(cmd, bind.actionType == 'macro');
                    end
                end
            end
        end

        -- Right click (disabled when Lock Movement is enabled)
        if isItemHovered and imgui.IsMouseClicked(1) and bind then
            if params.onRightClick and not gConfig.hotbarLockMovement then
                params.onRightClick();
            end
        end
    end

    -- ========================================
    -- 16. Tooltip (deferred to render after all windows for correct z-order)
    -- ========================================
    local showTooltip = params.showTooltip ~= false;
    if showTooltip and isHovered and bind and not dragdrop.IsDragging() and animOpacity > 0.5 then
        pendingTooltipBind = bind;
    end

    return result;
end

--[[
    Draw tooltip for an action on the foreground draw list.
    Renders on top of all ImGui windows and draw list content.
]]--
function M.DrawTooltip(bind)
    if not bind then return; end

    local ACTION_TYPE_LABELS = {
        ma = 'Spell (ma)', ja = 'Ability (ja)', ws = 'Weaponskill (ws)',
        item = 'Item', equip = 'Equip', macro = 'Macro', pet = 'Pet Command',
    };

    local function formatTarget(target)
        if not target then return nil; end
        local cleaned = target:gsub('[<>]', '');
        if cleaned == '' then return nil; end
        return '<' .. cleaned .. '>';
    end

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
            local available, reason = actions.IsActionAvailable(bind);
            if reason ~= 'pending' then
                isUnavailable = not available;
            end
        end
    end

    -- ABGR colors for foreground draw list
    local COL_GOLD   = 0xF297DAF4;
    local COL_DIM    = 0xFF999999;
    local COL_RED    = 0xFF4D4DFF;
    local COL_BG     = 0xF2110F0E;
    local COL_BORDER = 0xCC3E4748;

    local lines = {};
    local displayName = bind.displayName or bind.action or 'Unknown';
    lines[#lines+1] = { displayName, COL_GOLD };

    local typeLabel = ACTION_TYPE_LABELS[bind.actionType] or bind.actionType or '?';
    lines[#lines+1] = { 'Type: ' .. typeLabel, COL_DIM };

    if bind.actionType ~= 'macro' and bind.target and bind.target ~= '' then
        local ft = formatTarget(bind.target);
        if ft then lines[#lines+1] = { 'Target: ' .. ft, COL_DIM }; end
    end

    if bind.actionType == 'macro' and bind.macroText then
        lines[#lines+1] = { bind.macroText, COL_DIM };
    end

    if isUnavailable then
        lines[#lines+1] = { 'Action not available', COL_RED };
    end

    local padX, padY = 8, 6;
    local lineH = imgui.GetTextLineHeightWithSpacing();
    local maxW = 0;
    for _, line in ipairs(lines) do
        local w = imgui.CalcTextSize(line[1]);
        if w > maxW then maxW = w; end
    end

    local tooltipW = maxW + padX * 2;
    local tooltipH = #lines * lineH + padY * 2;

    local mx, my = imgui.GetMousePos();
    local tx = mx + 16;
    local ty = my + 8;

    local fgList = imgui.GetForegroundDrawList();
    fgList:AddRectFilled({tx, ty}, {tx + tooltipW, ty + tooltipH}, COL_BG, 4);
    fgList:AddRect({tx, ty}, {tx + tooltipW, ty + tooltipH}, COL_BORDER, 4, 0, 1);

    local textY = ty + padY;
    for _, line in ipairs(lines) do
        fgList:AddText({tx + padX, textY}, line[2], line[1]);
        textY = textY + lineH;
    end
end


-- Call at the start of each frame to reset deferred tooltip state
function M.BeginFrame()
    pendingTooltipBind = nil;
end

-- Call after all hotbar/crossbar windows are done to render the tooltip on top
function M.FlushTooltip()
    if pendingTooltipBind then
        M.DrawTooltip(pendingTooltipBind);
        pendingTooltipBind = nil;
    end
end

return M;
