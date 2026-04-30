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
local macroparse = require('modules.hotbar.macroparse');
local dragdrop = require('libs.dragdrop');
local textures = require('modules.hotbar.textures');
local skillchain = require('modules.hotbar.skillchain');
local universalTwoHour = require('modules.hotbar.universal_two_hour');
local statusHandler = require('handlers.statushandler');

-- Manual double-click tracking (more reliable than imgui.IsMouseDoubleClicked across drag systems)
local lastClickButtonId = nil;
local lastClickTime = 0;
local DOUBLE_CLICK_INTERVAL = 0.35;

-- Cache for MP cost lookups (keyed by action key string)
local mpCostCache = {};
local mpCostCacheSize = 0;
local MP_COST_CACHE_MAX = 4096;

-- Cache for action availability checks (keyed by action key string)
-- Structure: { isAvailable = bool, reason = string|nil }
local availabilityCache = {};
local availabilityCacheSize = 0;
local AVAILABILITY_CACHE_MAX = 8192;

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

local function PutMpCostCache(key, value)
    if mpCostCache[key] == nil then
        mpCostCacheSize = mpCostCacheSize + 1;
        if mpCostCacheSize > MP_COST_CACHE_MAX then
            mpCostCache = {};
            mpCostCacheSize = 0;
        end
    end
    mpCostCache[key] = value;
end

local function PutAvailabilityCache(key, value)
    if availabilityCache[key] == nil then
        availabilityCacheSize = availabilityCacheSize + 1;
        if availabilityCacheSize > AVAILABILITY_CACHE_MAX then
            availabilityCache = {};
            availabilityCacheSize = 0;
        end
    end
    availabilityCache[key] = value;
end

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

-- Common debuff IDs (used for overlay icons)
-- Matches existing conventions in XIUI (see modules/enemylist.lua and handlers/debuffhandler.lua).
local STATUS_ID_BY_LABEL = {
    ['Sleep'] = 2,
    ['Poison'] = 3,
    ['Paralyze'] = 4,
    ['Blind'] = 5,
    ['Silence'] = 6,
    ['Stun'] = 10,
    ['Bind'] = 11,
    ['Weight'] = 12,
    ['Slow'] = 13,
    ['Attack Down'] = 147,
    ['Accuracy Down'] = 146,
    ['Lower Def'] = 149,     -- Defense Down
    ['Defense Down'] = 149,
    ['Evasion Down'] = 148,
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

-- Per-slot cache to avoid redundant updates
-- Structure: slotCache[slotPrim] = { texturePath, iconPath, keybindText, keybindFontSize, keybindFontColor, timerText, ... }
local slotCache = {};

-- Reverse lookup: maps 'barIndex:slotIndex' or 'comboMode:slotIndex' to slotPrim
-- Used for targeted cache invalidation
local slotPrimLookup = {};

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

-- Register a slot prim with its identifier for targeted invalidation
-- key: 'barIndex:slotIndex' for hotbar, 'comboMode:slotIndex' for crossbar
function M.RegisterSlotPrim(key, slotPrim)
    if key and slotPrim then
        slotPrimLookup[key] = slotPrim;
    end
end

-- Invalidate cache for a slot by key (used for targeted updates)
-- key: 'barIndex:slotIndex' for hotbar, 'comboMode:slotIndex' for crossbar
function M.InvalidateSlotByKey(key)
    local slotPrim = slotPrimLookup[key];
    if slotPrim and slotCache[slotPrim] then
        slotCache[slotPrim] = nil;
    end
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
    slotPrimLookup = {};
    availabilityCache = {};
    mpCostCache = {};
    availabilityCacheSize = 0;
    mpCostCacheSize = 0;
    equipmentCheckCache = {};
    ninjutsuCache = {};
    itemQuantityCache = {};
    ammoStatusCache = {};
end

-- Clear only slot rendering cache (icons, positions, colors)
-- Does NOT clear availability, MP cost, or item quantity caches
-- OPTIMIZED: Use this for palette changes to avoid unnecessary recalculation cascade
function M.ClearSlotRenderingCache()
    slotCache = {};
    slotPrimLookup = {};
end

-- Clear availability cache (call on job change, level sync, etc.)
function M.ClearAvailabilityCache()
    availabilityCache = {};
    availabilityCacheSize = 0;
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
local function DrawSkillchainHighlight(drawList, x, y, size, scName, color, opacity, iconScaleOverride, iconOxOverride, iconOyOverride)
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
    local scale = iconScaleOverride or gConfig.hotbarGlobal.skillchainIconScale or 1.0;
    local iconSize = math.floor(size * 0.35 * scale);
    local offsetX = iconOxOverride or gConfig.hotbarGlobal.skillchainIconOffsetX or 0;
    local offsetY = iconOyOverride or gConfig.hotbarGlobal.skillchainIconOffsetY or 0;
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

-- HSV (h in [0,1)) -> RGB for rainbow Universal 2 Hour glow.
local function UthHsvToRgb(h, s, v)
    h = math.fmod(h, 1.0);
    if h < 0 then
        h = h + 1.0;
    end
    local i = math.floor(h * 6);
    local f = h * 6 - i;
    local p = v * (1 - s);
    local q = v * (1 - f * s);
    local tcol = v * (1 - (1 - f) * s);
    i = i % 6;
    local r, g, b;
    if i == 0 then
        r, g, b = v, tcol, p;
    elseif i == 1 then
        r, g, b = q, v, p;
    elseif i == 2 then
        r, g, b = p, v, tcol;
    elseif i == 3 then
        r, g, b = p, q, v;
    elseif i == 4 then
        r, g, b = tcol, p, v;
    else
        r, g, b = v, p, q;
    end
    return r, g, b;
end

-- Skillchain-style marching dashed rect; rainbow hue shifts with animation offset + time.
local function DrawUniversalTwoHourRainbowMarchingBorder(drawList, x1, y1, x2, y2, opacityMul)
    if not drawList or opacityMul <= 0.01 then
        return;
    end
    local animOffset = skillchain.GetAnimationOffset();
    local t = os.clock();
    local dashLen = 4;
    local gapLen = 4;
    local thickness = 2.5;
    local hueBase = math.fmod(animOffset * 0.0035 + t * 0.052, 1.0);
    local function edgeColor(edgeIdx)
        local h = math.fmod(hueBase + edgeIdx * 0.085, 1.0);
        local r, g, b = UthHsvToRgb(h, 0.74, 1.0);
        return imgui.GetColorU32({ r, g, b, 0.9 * opacityMul });
    end
    DrawDashedLine(drawList, x1, y1, x2, y1, edgeColor(0), thickness, dashLen, gapLen, animOffset);
    DrawDashedLine(drawList, x2, y1, x2, y2, edgeColor(1), thickness, dashLen, gapLen, animOffset);
    DrawDashedLine(drawList, x2, y2, x1, y2, edgeColor(2), thickness, dashLen, gapLen, animOffset);
    DrawDashedLine(drawList, x1, y2, x1, y1, edgeColor(3), thickness, dashLen, gapLen, animOffset);
end

--- Rainbow rotating rings while Universal 2 Hour waits on <stpc>/<stnpc> confirmation.
--- Ring radii breathe (collapse / expand); dashed border stays on the slot edge. Opacity uses animOpacity * dimFactor * armFadeScale.
local function DrawUniversalTwoHourSubtargetGlow(drawList, x, y, size, animOpacity, dimFactor, armFadeScale)
    if not drawList or animOpacity <= 0.01 then
        return;
    end
    armFadeScale = armFadeScale or 1.0;
    if armFadeScale <= 0.01 then
        return;
    end
    local cx = x + size * 0.5;
    local cy = y + size * 0.5;
    local t = os.clock();
    local op = math.min(1.0, animOpacity * dimFactor) * armFadeScale;

    -- Collapse toward center then expand (cosine ease per cycle) — line rings only, no filled wash over the icon.
    local breatheMin = 0.46;
    local breathe = breatheMin + (1.0 - breatheMin) * (0.5 + 0.5 * math.cos(t * 3.05));

    local function rainbowDashRing(spin, rad, thick, segs, hueSpin, lineAlpha, dashPred)
        rad = rad * breathe;
        for i = 0, segs - 1 do
            if dashPred(i) then
                local a0 = spin + (i / segs) * math.pi * 2;
                local a1 = spin + ((i + 1) / segs) * math.pi * 2;
                local mid = (a0 + a1) * 0.5;
                local hue = math.fmod(mid / (math.pi * 2) + hueSpin, 1.0);
                local r, g, b = UthHsvToRgb(hue, 0.82, 1.0);
                drawList:AddLine(
                    { cx + math.cos(a0) * rad, cy + math.sin(a0) * rad },
                    { cx + math.cos(a1) * rad, cy + math.sin(a1) * rad },
                    imgui.GetColorU32({ r, g, b, lineAlpha * op }),
                    thick
                );
            end
        end
    end

    local spinOuter = t * 4.2;
    local spinInner = -t * 3.1;
    local hueTravel = t * 0.14;

    rainbowDashRing(-spinOuter, size * 0.485, 2.5, 28, hueTravel + 0.08, 0.78,
        function(i) return i % 3 ~= 2; end);
    rainbowDashRing(spinOuter, size * 0.52, 3.2, 28, hueTravel, 0.85,
        function(i) return i % 3 ~= 0; end);
    rainbowDashRing(spinInner, size * 0.46, 2.2, 28, hueTravel + 0.17, 0.80,
        function(i) return i % 3 ~= 0; end);

    local ringPulse = 0.55 + 0.45 * math.sin(t * 5.1);
    local outerRad = (size * 0.58 + ringPulse * 1.5) * breathe;
    local outerThick = 2.2 + ringPulse * 0.35;
    local segsO = 48;
    for i = 0, segsO - 1 do
        local a0 = (i / segsO) * math.pi * 2;
        local a1 = ((i + 1) / segsO) * math.pi * 2;
        local mid = (a0 + a1) * 0.5;
        local hue = math.fmod(mid / (math.pi * 2) + hueTravel + 0.05, 1.0);
        local r, g, b = UthHsvToRgb(hue, 0.75, 1.0);
        drawList:AddLine(
            { cx + math.cos(a0) * outerRad, cy + math.sin(a0) * outerRad },
            { cx + math.cos(a1) * outerRad, cy + math.sin(a1) * outerRad },
            imgui.GetColorU32({ r, g, b, 0.88 * op }),
            outerThick
        );
    end

    DrawUniversalTwoHourRainbowMarchingBorder(drawList, x, y, x + size, y + size, op);
end

-- Helper: determine if movement/drag-drop is locked for this slot
-- Shift key overrides the lock to allow dragging while locked
-- Hotbar slots use hotbarLockMovement; crossbar slots use crossbarLockMovement
local function IsMovementLockedForDropZone(dropZoneId)
    if not dropZoneId then return false; end
    if imgui.GetIO().KeyShift then
        return false;
    end
    if not gConfig then return false; end
    if type(dropZoneId) == 'string' and dropZoneId:sub(1, 5) == 'paled' then
        return false;
    end
    if type(dropZoneId) == 'string' and dropZoneId:sub(1, 9) == 'crossbar_' then
        return gConfig.crossbarLockMovement == true;
    end
    return gConfig.hotbarLockMovement == true;
end

-- XIUI GDI fonts use 0xAARRGGBB; ImGui AddText expects GetColorU32({r,g,b,a}).
local function ArgbToImguiU32(argb)
    local a = bit.rshift(bit.band(argb, 0xFF000000), 24) / 255;
    local r = bit.rshift(bit.band(argb, 0x00FF0000), 16) / 255;
    local g = bit.rshift(bit.band(argb, 0x0000FF00), 8) / 255;
    local b = bit.band(argb, 0x000000FF) / 255;
    return imgui.GetColorU32({ r, g, b, a });
end

local function ScaleArgbOpacity(argb, opacity)
    if not opacity or opacity >= 0.999 then return argb; end
    local a = bit.rshift(bit.band(argb, 0xFF000000), 24);
    a = math.floor(a * opacity);
    if a < 0 then a = 0; elseif a > 255 then a = 255; end
    return bit.bor(bit.lshift(a, 24), bit.band(argb, 0x00FFFFFF));
end

local function DimArgbColor(argb, factor)
    if not factor or factor >= 0.999 then return argb; end
    local a = bit.band(bit.rshift(argb, 24), 0xFF);
    local r = math.floor(bit.band(bit.rshift(argb, 16), 0xFF) * factor);
    local g = math.floor(bit.band(bit.rshift(argb, 8), 0xFF) * factor);
    local b = math.floor(bit.band(argb, 0xFF) * factor);
    return bit.bor(bit.lshift(a, 24), bit.lshift(r, 16), bit.lshift(g, 8), b);
end

-- Rasterized GDI cooldown text ((recastTimerFontSize + 1) / outline) as a texture, drawn in ImGui foreground.
-- Restores the old large timer look; stays above D3D icon primitives (timerFont alone is drawn under them).
local function DrawGdiTimerCooldownForeground(topDl, timerFont, recastText, timerColor, x, y, size, animOpacity, params, cache)
    if not topDl or not timerFont or not recastText or recastText == '' then return false; end
    -- One step above the configured size for readability (setting still controls the baseline).
    local fs = (params.recastTimerFontSize or 11) + 1;
    if not cache or cache.recastTimerRasterSize ~= fs then
        timerFont:set_font_height(fs);
        if cache then cache.recastTimerRasterSize = fs; end
    end
    if not cache or cache.recastTimerFontColor ~= timerColor then
        timerFont:set_font_color(timerColor);
        if cache then cache.recastTimerFontColor = timerColor; end
    end
    if not cache or cache.cooldownOverlayText ~= recastText then
        timerFont:set_text(recastText);
        if cache then cache.cooldownOverlayText = recastText; end
    end
    timerFont:set_visible(false);
    local tex = select(1, timerFont:get_texture());
    if not tex then return false; end
    local tw, th = timerFont:get_text_size();
    if not tw or not th or tw <= 0 or th <= 0 then return false; end
    local cx = x + size / 2;
    local cy = y + size / 2;
    local px = cx - tw / 2;
    local py = cy - th / 2;
    local ptr = tonumber(ffi.cast('uint32_t', tex));
    if not ptr or ptr == 0 then return false; end
    local tint = ArgbToImguiU32(ScaleArgbOpacity(timerColor, animOpacity));
    topDl:AddImage(ptr, { px, py }, { px + tw, py + th }, { 0, 0 }, { 1, 1 }, tint);
    return true;
end

-- Foreground corner labels: scrim + drop shadow + outline + single fill (outline carries weight).
local OUTLINE_OFFSETS_1 = {
    { -1, -1 }, { 0, -1 }, { 1, -1 },
    { -1, 0 },             { 1, 0 },
    { -1, 1 }, { 0, 1 }, { 1, 1 },
};
-- ImGui CalcTextSize is ~3-4px narrower than AddText + ±1 outline + drop shadow; right-anchored corner
-- labels (x126) otherwise clip on the last glyph. Only used to push text LEFT so the right edge clears
-- the slot — the soft backdrop still hugs the real glyph box.
local FG_CORNER_POS_SLACK_PX = 4;

-- Brighten label text toward white (Edit Full Palette hover, matches slot highlight feel).
local function LerpArgbTowardWhite(argb, t)
    if not argb or t <= 0 then return argb; end
    if t > 1 then t = 1; end
    local a = bit.rshift(bit.band(argb, 0xFF000000), 24);
    local r = bit.rshift(bit.band(argb, 0x00FF0000), 16);
    local g = bit.rshift(bit.band(argb, 0x0000FF00), 8);
    local b = bit.band(argb, 0x000000FF);
    r = math.floor(r + (255 - r) * t);
    g = math.floor(g + (255 - g) * t);
    b = math.floor(b + (255 - b) * t);
    return bit.bor(bit.lshift(a, 24), bit.lshift(r, 16), bit.lshift(g, 8), b);
end

local function GetImGuiTextSize2D(str)
    local sz = imgui.CalcTextSize(str);
    if type(sz) == 'table' then
        local w = sz[1] or sz.x;
        local h = sz[2] or sz.y;
        if w and h then
            return w, h;
        end
        if w then
            return w, (imgui.GetTextLineHeight and imgui.GetTextLineHeight() or 13);
        end
    elseif type(sz) == 'number' then
        return sz, (imgui.GetTextLineHeight and imgui.GetTextLineHeight() or 13);
    end
    return 0, (imgui.GetTextLineHeight and imgui.GetTextLineHeight() or 13);
end

-- Editor labels: width must match drawList:AddText(font, size, ...) (same PushFont as render path).
local function CalcTextSizePushedNoWrap(text)
    local sz;
    local ok = pcall(function()
        -- Prefer explicit no-wrap so width matches one-line AddText (wrap width can skew X).
        sz = imgui.CalcTextSize(text, nil, false, -1);
    end);
    if not ok or not sz then
        return GetImGuiTextSize2D(text);
    end
    if type(sz) == 'table' then
        local w = sz[1] or sz.x;
        local h = sz[2] or sz.y;
        if w and h then return w, h; end
        if w then return w, (imgui.GetTextLineHeight and imgui.GetTextLineHeight() or 13); end
    elseif type(sz) == 'number' then
        return sz, (imgui.GetTextLineHeight and imgui.GetTextLineHeight() or 13);
    end
    return GetImGuiTextSize2D(text);
end

-- GDI corner fonts use anchor + alignment; ImGui AddText always draws from top-left. Compute (px,py)
-- so the string's bbox matches the intended corner inside the slot (fixes clipped / drifting Qty / MP text).
-- Must be defined after GetImGuiTextSize2D / CalcTextSizePushedNoWrap (Lua 5.1 local scoping).
-- `inset` reserves space for AddOutlinedForegroundText outline + shadow (CalcTextSize is fill-only).
-- `fontSizePx`: optional; ImGui CalcTextSize can be narrower than the draw-list glyph width for digit-heavy
-- strings (e.g. x126), which right-anchored text then clips on the right — use a min width from char count.
local function ImGuiTopLeftForForegroundCorner(x, y, size, anchor, offsetX, offsetY, text, fontSizePx)
    if not text or text == '' then
        return x, y;
    end
    local tw, th = GetImGuiTextSize2D(text);
    if (not tw or tw <= 0) or (not th or th <= 0) then
        tw, th = CalcTextSizePushedNoWrap(text);
    end
    if not tw or tw <= 0 then tw = 1; end
    if not th or th <= 0 then th = (imgui.GetTextLineHeight and imgui.GetTextLineHeight() or 13); end
    -- Positioning-only slack so outline + last glyph don't poke past the slot's right edge (right anchors).
    tw = tw + FG_CORNER_POS_SLACK_PX;
    anchor = anchor or 'topLeft';
    offsetX = offsetX or 0;
    offsetY = offsetY or 0;
    local padding = 2;
    -- Room for outline/shadow; keep small so corner text does not sit too far left vs GDI-era layout.
    local inset = 2;
    if anchor == 'topLeft' then
        return x + padding + inset + offsetX, y + padding + inset + offsetY;
    elseif anchor == 'topRight' then
        return x + size - padding - inset - tw + offsetX, y + padding + inset + offsetY;
    elseif anchor == 'bottomLeft' then
        return x + padding + inset + offsetX, y + size - padding - inset - th + offsetY;
    elseif anchor == 'bottomRight' then
        return x + size - padding - inset - tw + offsetX, y + size - padding - inset - th + offsetY;
    end
    return x + padding + inset + offsetX, y + padding + inset + offsetY;
end

local function MeasureEditorLabelTextSize(text, fnt, fontSizePx)
    if not text or text == '' then
        return 0, 0;
    end
    if fnt and fontSizePx and fontSizePx > 0 and imgui.PushFont and imgui.PopFont then
        local tw, th, ok = 0, 0, false;
        ok = pcall(function()
            imgui.PushFont(fnt, fontSizePx);
            tw, th = CalcTextSizePushedNoWrap(text);
            imgui.PopFont();
        end);
        if ok and tw and tw > 0 then
            return tw, th;
        end
    end
    return GetImGuiTextSize2D(text);
end

local function EditorLabelSnappedCenterX(cx, text, fnt, fontSizePx)
    local tw = MeasureEditorLabelTextSize(text, fnt, fontSizePx);
    if not tw or tw <= 0 then
        return math.floor(cx + 0.5);
    end
    return math.floor(cx - tw * 0.5 + 0.5);
end

-- Soft oval / radial falloff behind text (avoids sharp box edges)
local function FillEllipseConvex(drawList, cx, cy, rx, ry, colU32)
    if not drawList or rx <= 0 or ry <= 0 then return; end
    if drawList.PathClear and drawList.PathLineTo and drawList.PathFillConvex then
        drawList:PathClear();
        local nseg = 28;
        for i = 0, nseg do
            local ang = (i / nseg) * math.pi * 2;
            drawList:PathLineTo({ cx + math.cos(ang) * rx, cy + math.sin(ang) * ry });
        end
        drawList:PathFillConvex(colU32);
    else
        local r = (rx + ry) * 0.5;
        drawList:AddCircleFilled({ cx, cy }, r, colU32, 28);
    end
end

local function AddSoftEllipticalBackdrop(drawList, px, py, tw, th, aChannel)
    if tw <= 0 or th <= 0 then return; end
    -- Tight to the glyph box; corner MP/Qty scrim should read as a hint, not a large black dot.
    local padX, padY = 2, 2;
    local baseRx = (tw + padX * 2) * 0.5;
    local baseRy = (th + padY * 2) * 0.5;
    local cx = px + tw * 0.5;
    local cy = py + th * 0.5;
    local baseAlpha = 0.30 * (aChannel / 255);
    local layers = 4;
    for li = 1, layers do
        local p = (li - 1) / math.max(1, layers - 1);
        -- Large faint ring first → small dark core (smooth radial falloff)
        local scale = 1.26 - 0.26 * p;
        local rx = baseRx * scale;
        local ry = baseRy * scale;
        local alpha = baseAlpha * (0.12 + 0.88 * p * p);
        local col = imgui.GetColorU32({ 0, 0, 0, alpha });
        FillEllipseConvex(drawList, cx, cy, rx, ry, col);
    end
end

-- Edit Full Palette only — not used by the in-game crossbar HUD. Flatter, wider falloff (pill / cylinder feel)
-- and lighter than AddSoftEllipticalBackdrop (MP/Qty on live crossbar).
local function AddSoftEditorLabelBackdrop(drawList, px, py, tw, th, aChannel)
    if tw <= 0 or th <= 0 then return; end
    local padX, padY = 5, 2;
    local baseRx = (tw + padX * 2) * 0.5;
    local baseRy = (th + padY * 2) * 0.5;
    -- Stretch horizontally, compress vertically so the silhouette reads like a horizontal cylinder / capsule.
    baseRx = baseRx * 1.22;
    baseRy = baseRy * 0.76;
    local cx = px + tw * 0.5;
    local cy = py + th * 0.5;
    local baseAlpha = 0.28 * (aChannel / 255);
    local layers = 6;
    for li = 1, layers do
        local p = (li - 1) / math.max(1, layers - 1);
        local scale = 1.52 - 0.52 * p;
        local rx = baseRx * scale;
        local ry = baseRy * scale;
        local alpha = baseAlpha * (0.06 + 0.94 * p * p);
        local col = imgui.GetColorU32({ 0, 0, 0, alpha });
        FillEllipseConvex(drawList, cx, cy, rx, ry, col);
    end
end

local function AddOutlinedForegroundText(drawList, px, py, argbColor, text)
    if not drawList or not text or text == '' then return; end
    local mainU32 = ArgbToImguiU32(argbColor);
    local a = bit.rshift(bit.band(argbColor, 0xFF000000), 24);
    local tw, th = GetImGuiTextSize2D(text);
    if tw > 0 and th > 0 then
        AddSoftEllipticalBackdrop(drawList, px, py, tw, th, a);
    end
    -- Single soft shadow (multi-pass + ±2 halo bloated glyphs and stacked on wrapped editor lines)
    local shadowA = math.floor(a * 0.52);
    local shadowU32 = ArgbToImguiU32(bit.bor(bit.lshift(shadowA, 24), 0x000000));
    drawList:AddText({ px + 1, py + 1 }, shadowU32, text);
    local outlineArgb = bit.bor(bit.lshift(math.floor(a * 0.92), 24), 0x000000);
    local outlineU32 = ArgbToImguiU32(outlineArgb);
    for i = 1, #OUTLINE_OFFSETS_1 do
        local dx, dy = OUTLINE_OFFSETS_1[i][1], OUTLINE_OFFSETS_1[i][2];
        drawList:AddText({ px + dx, py + dy }, outlineU32, text);
    end
    drawList:AddText({ px, py }, mainU32, text);
end

local function AddSimpleOutlinedForegroundText(drawList, px, py, argbColor, text, font, fontSizePx)
    if not drawList or not text or text == '' then return; end
    local mainU32 = ArgbToImguiU32(argbColor);
    local a = bit.rshift(bit.band(argbColor, 0xFF000000), 24);
    local outlineU32 = ArgbToImguiU32(bit.bor(bit.lshift(math.floor(a * 0.88), 24), 0x000000));
    local function drawAt(x, y, col)
        if font and fontSizePx and fontSizePx > 0 then
            local ok = pcall(function()
                drawList:AddText(font, fontSizePx, { x, y }, col, text);
            end);
            if ok then return; end
        end
        drawList:AddText({ x, y }, col, text);
    end
    for i = 1, #OUTLINE_OFFSETS_1 do
        local dx, dy = OUTLINE_OFFSETS_1[i][1], OUTLINE_OFFSETS_1[i][2];
        drawAt(px + dx, py + dy, outlineU32);
    end
    drawAt(px, py, mainU32);
end

-- Edit Full Palette (idle): first four characters of the trimmed display name (paired with slot; full name on hover).
local function EditorIdleAbbrev4(fullName)
    if not fullName or fullName == '' then
        return '';
    end
    local t = fullName:gsub('^%s+', ''):gsub('%s+$', '');
    if t == '' then
        return '';
    end
    if #t <= 4 then
        return t;
    end
    return t:sub(1, 4);
end

-- Edit Full Palette: at most one line break, with the line nearest the slot holding a single word.
-- Top slots (label above button): "A B C … Z" → "A B … Y\nZ" (last word beside the button).
-- Bottom/side slots (label below button): "A B C …" → "A\nB C …" (first word beside the button).
local function EditorLabelWrapNearSlot(text, labelAboveSlot)
    if not text or text == '' then return text; end
    local t = text:gsub('^%s+', ''):gsub('%s+$', '');
    if not t:find('%s') then return t; end
    local words = {};
    for w in t:gmatch('%S+') do
        table.insert(words, w);
    end
    if #words < 2 then return t; end
    if labelAboveSlot then
        local last = table.remove(words);
        return table.concat(words, ' ') .. '\n' .. last;
    end
    local first = table.remove(words, 1);
    return first .. '\n' .. table.concat(words, ' ');
end

local function SplitNewlines(s)
    if not s or s == '' then return {}; end
    local t = {};
    local start = 1;
    local len = #s;
    while start <= len do
        local nl = s:find('\n', start, true);
        if not nl then
            table.insert(t, s:sub(start));
            break;
        end
        table.insert(t, s:sub(start, nl - 1));
        start = nl + 1;
    end
    return t;
end

-- labelForeground without editorMinimalView (rare). Edit Full Palette uses AddEditorMultilineCenteredOnSlotLikeCorner instead.
local function AddEditorMultilineCenteredOutlined(dl, cx, topY, argbColor, multilineText, font, fontSizePx)
    if not dl or not multilineText or multilineText == '' then return; end
    local lines = SplitNewlines(multilineText);
    local lineStep = fontSizePx + 2;
    if font and imgui.PushFont and imgui.PopFont then
        pcall(function()
            imgui.PushFont(font, fontSizePx);
            if imgui.GetTextLineHeight then
                lineStep = imgui.GetTextLineHeight() + 1;
            end
            imgui.PopFont();
        end);
    end
    local py = math.floor(topY + 0.5);
    for i = 1, #lines do
        local line = lines[i];
        if line ~= '' then
            local px = EditorLabelSnappedCenterX(cx, line, font, fontSizePx);
            AddSimpleOutlinedForegroundText(dl, px, py, argbColor, line, font, fontSizePx);
        end
        py = py + lineStep;
    end
end

-- Edit Full Palette only — in-game crossbar keeps GDI labels above/below slots. Centered on-slot; thin outline (no scrim) per line.
local function AddEditorMultilineCenteredOnSlotLikeCorner(dl, slotX, slotY, slotSize, argbColor, multilineText, font, fontSizePx)
    if not dl or not multilineText or multilineText == '' or not slotSize or slotSize <= 0 then return; end
    local raw = SplitNewlines(multilineText);
    local lines = {};
    for i = 1, #raw do
        if raw[i] ~= '' then
            table.insert(lines, raw[i]);
        end
    end
    if #lines == 0 then return; end
    local lineStep = fontSizePx + 2;
    if font and imgui.PushFont and imgui.PopFont then
        pcall(function()
            imgui.PushFont(font, fontSizePx);
            if imgui.GetTextLineHeight then
                lineStep = imgui.GetTextLineHeight() + 1;
            end
            imgui.PopFont();
        end);
    end
    local cx = slotX + slotSize * 0.5;
    local cy = slotY + slotSize * 0.5;
    local totalH = #lines * lineStep;
    local topY = math.floor(cy - totalH * 0.5 + 0.5);
    local py = topY;
    for i = 1, #lines do
        local line = lines[i];
        local px = EditorLabelSnappedCenterX(cx, line, font, fontSizePx);
        -- Edit palette on-slot names: use thin outline only (no scrim + multi-pass halo) so wrapped lines
        -- do not stack thick shadows on each other ("Utsusemi: Ichi" etc.).
        AddSimpleOutlinedForegroundText(dl, px, py, argbColor, line, font, fontSizePx);
        py = py + lineStep;
    end
end

-- Center cooldown digits: same layering as §11c (foreground, above D3D) but matches old GDI timer
-- look — fill + thin ±1 stroke only (no scrim, no drop shadow, no halo ring).
-- Optional fontSizePx: use ImDrawList:AddText(font, size, ...) when the binding supports it; otherwise
-- caller should wrap with imgui.PushFont so default AddText picks up recastTimerFontSize.
local function AddGdiLikeCooldownForegroundText(drawList, px, py, argbColor, text, font, fontSizePx)
    if not drawList or not text or text == '' then return; end
    local mainU32 = ArgbToImguiU32(argbColor);
    local a = bit.rshift(bit.band(argbColor, 0xFF000000), 24);
    local outlineArgb = bit.bor(bit.lshift(math.floor(a * 0.92), 24), 0x000000);
    local outlineU32 = ArgbToImguiU32(outlineArgb);
    local function drawAt(fx, fy, col)
        if font and fontSizePx and fontSizePx > 0 then
            local ok = pcall(function()
                drawList:AddText(font, fontSizePx, { fx, fy }, col, text);
            end);
            if ok then return; end
        end
        drawList:AddText({ fx, fy }, col, text);
    end
    for i = 1, #OUTLINE_OFFSETS_1 do
        local dx, dy = OUTLINE_OFFSETS_1[i][1], OUTLINE_OFFSETS_1[i][2];
        drawAt(px + dx, py + dy, outlineU32);
    end
    drawAt(px, py, mainU32);
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
        - onDoubleClick: Callback() when slot is double-clicked
        - showTooltip: Whether to show tooltip on hover (default true)
        - drawCornerTextForeground: If true, MP/Lv/Qty corner strings use ImGui overlay draw list (crossbar: window DL; else foreground) so they render above D3D icons
        - editorClipRect: Optional { minX, minY, maxX, maxY } screen-space rect; hides D3D/GDI when the slot (+labels) is outside (ImGui layers should use PushClipRect separately).
        - editorStrictContain: Optional bool. When true and editorClipRect is set, slot content must be fully inside clip rect (prevents edge leaking while scrolling).
        - performanceLiteChecks: Optional bool. When true, skip heavy recast/MP/availability checks (useful for edit-only views).
        - labelForeground: Optional bool. Crossbar sets this only for Edit Full Palette (draft edit session): draw the action name via ImGui instead of GDI labelFont.
        - editorMinimalView: Optional bool. Edit Full Palette: suppress MP/Qty/timer/corner overlays; use on-slot abbrev/hover labels. Normal gameplay crossbar does not set this.
        - editorEmptySlotBgRgb: Optional { r, g, b } in 0..1; panel behind empty slots (defaults to Edit Full Palette row fill in palettemanager.lua).
        - forceImGuiIcon: Optional bool. When true, bypass icon primitive path and render icon via ImGui draw list.
        - suppressActionOnClick: Optional bool. When true, left-click never runs onClick or executes the bound command (drag/drop still work).

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
    local useFgCornerText = params.drawCornerTextForeground == true;
    local useFgLabel = params.labelForeground == true;
    local minimalEditorView = params.editorMinimalView == true;
    local forceImGuiIcon = params.forceImGuiIcon == true;
    local fgCornerMp, fgCornerQty;
    local fgLabel;

    -- Crossbar: use the current window draw list so MP/timer/hover overlays stack with other ImGui windows
    -- (GetForegroundDrawList always paints above every window). Hotbar and editors keep GetUIDrawList behavior.
    local function slotOverlayDrawList()
        if params.windowName == 'Crossbar' then
            local wdl = imgui.GetWindowDrawList();
            if wdl then
                return wdl;
            end
        end
        return GetUIDrawList();
    end

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

    -- Edit Full Palette (and similar): D3D/GDI do not respect ImGui scroll clip — hide when off-screen.
    -- Expanded bounds cover labels above/below the slot when enabled.
    do
        local clip = params.editorClipRect;
        if clip and clip[1] and clip[2] and clip[3] and clip[4] then
            local fs = params.labelFontSize or 10;
            local padTop = 4;
            local padBot = 4;
            if params.showLabel and params.labelText and params.labelText ~= '' then
                if not minimalEditorView then
                    local extraLinePad = 0;
                    if params.labelText and params.labelText:find('%s') then
                        extraLinePad = math.floor(fs * 1.05 + 0.5);
                    end
                    if params.labelAboveSlot then
                        padTop = fs + 14 + extraLinePad;
                    else
                        padBot = fs + 14 + extraLinePad;
                    end
                else
                    -- Labels draw on the slot; bounds match the diamond cell.
                    padTop = 4;
                    padBot = 4;
                end
            end
            local sx1 = x;
            local sy1 = y - padTop;
            local sx2 = x + size;
            local sy2 = y + size + padBot;
            local strictContain = params.editorStrictContain == true;
            if strictContain then
                if sx1 < clip[1] or sy1 < clip[2] or sx2 > clip[3] or sy2 > clip[4] then
                    M.HideSlot(resources);
                    return result;
                end
            else
                if sx2 < clip[1] or sx1 > clip[3] or sy2 < clip[2] or sy1 > clip[4] then
                    M.HideSlot(resources);
                    return result;
                end
            end
        end
    end

    local ec = params.editorClipRect;
    local hasEditorClip = ec and ec[1] and ec[2] and ec[3] and ec[4];

    -- Command string for click execution (do not use BuildCommand: it calls GetBindIcon every frame)
    local command = nil;
    if bind then
        command = actions.BuildCommandString(bind);
        result.command = command;
    end

    -- Check hover state
    local mouseX, mouseY = imgui.GetMousePos();
    local isHovered = mouseX >= x and mouseX <= x + size and
                      mouseY >= y and mouseY <= y + size;
    result.isHovered = isHovered;

    -- Slot body tint (D3D slot.png or ImGui fill in Edit Full Palette when clipped — D3D ignores ImGui clip rects).
    local function computePaletteSlotBodyArgb()
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

        return finalColor;
    end

    -- ========================================
    -- 1. Slot Background Primitive
    -- ========================================
    local cache = GetSlotCache(resources.slotPrim);
    if resources.slotPrim then
        -- Edit Full Palette: empty uses ImGui chrome only; with editorClipRect, filled slots must too (D3D bleeds past clip on resize).
        if minimalEditorView and (not bind or hasEditorClip) then
            resources.slotPrim.visible = false;
        else
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

        local finalColor = computePaletteSlotBodyArgb();

        -- Only update color if changed
        if cache and cache.slotColor ~= finalColor then
            resources.slotPrim.color = finalColor;
            cache.slotColor = finalColor;
        end
        resources.slotPrim.visible = true;
        end
    end

    -- ========================================
    -- 1b. Edit Full Palette — slot chrome on ImGui window DL (same layer as icons; D3D slot is under panel BG)
    -- Empty: subtle fill (15% lighter than panel) + border (20% lighter).
    -- Filled + clip: slot body here (matches §1 tint) so resize/scroll never shows uncapped D3D slot.png past the window.
    -- Filled + no clip: border only (D3D body) — rare; same border for consistency.
    -- Default base matches palettemanager.lua row AddRectFilled ({ 0.13, 0.13, 0.16 }).
    -- ========================================
    if minimalEditorView and animOpacity > 0.5 then
        local dl = imgui.GetWindowDrawList();
        if dl then
            local eb = params.editorEmptySlotBgRgb;
            local br0, bg0, bb0 = 0.13, 0.13, 0.16;
            if type(eb) == 'table' and eb[1] and eb[2] and eb[3] then
                br0, bg0, bb0 = eb[1], eb[2], eb[3];
            end
            local function lightenRgb(r, g, b, t)
                return math.min(1, r + (1 - r) * t), math.min(1, g + (1 - g) * t), math.min(1, b + (1 - b) * t);
            end
            local fillLift = 0.15;
            local borderLift = 0.20;
            if isPressed then
                fillLift = 0.19;
                borderLift = 0.26;
            elseif isHovered and not dragdrop.IsDragging() then
                fillLift = 0.17;
                borderLift = 0.23;
            end
            local fr, fg, fb = lightenRgb(br0, bg0, bb0, fillLift);
            local ur, ug, ub = lightenRgb(br0, bg0, bb0, borderLift);
            -- Low alpha so empties read as a hint, not a second UI layer.
            local fillA = 0.34 * animOpacity;
            local borderA = 0.42 * animOpacity;
            local fillCol = imgui.GetColorU32({ fr, fg, fb, fillA });
            local borderCol = imgui.GetColorU32({ ur, ug, ub, borderA });
            local clip = params.editorClipRect;
            local pushed = false;
            if clip and clip[1] and clip[2] and clip[3] and clip[4] and dl.PushClipRect then
                dl:PushClipRect({ clip[1], clip[2] }, { clip[3], clip[4] }, true);
                pushed = true;
            end
            local cornerR = math.max(4, math.min(10, math.floor(size * 0.125 + 0.5)));
            if not bind then
                dl:AddRectFilled({ x, y }, { x + size, y + size }, fillCol, cornerR);
            elseif hasEditorClip then
                local fc = computePaletteSlotBodyArgb();
                local fa = bit.rshift(bit.band(fc, 0xFF000000), 24) / 255;
                local frr = bit.rshift(bit.band(fc, 0x00FF0000), 16) / 255;
                local fgg = bit.rshift(bit.band(fc, 0x0000FF00), 8) / 255;
                local fbb = bit.band(fc, 0x000000FF) / 255;
                local fillColBind = imgui.GetColorU32({ frr, fgg, fbb, fa });
                dl:AddRectFilled({ x, y }, { x + size, y + size }, fillColBind, cornerR);
            end
            dl:AddRect({ x, y }, { x + size, y + size }, borderCol, cornerR, 0, 1.0 );
            if pushed and dl.PopClipRect then
                dl:PopClipRect();
            end
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
    local isLiteChecks = params.performanceLiteChecks == true;
    local isOnCooldown = false;
    local recastText = nil;
    local recastRemaining = 0;
    if not isLiteChecks and not minimalEditorView then
        recast.SetHHMMFormat(params.useHHMMCooldownFormat or false);
        local cooldown = recast.GetCooldownInfo(bind);
        if cooldown then
            isOnCooldown = cooldown.isOnCooldown;
            recastText = cooldown.recastText;
            recastRemaining = cooldown.remaining or 0;
        end
    end

    -- Check if player has enough MP for actions with MP costs (spells + pet pacts via registry)
    local notEnoughMp = false;
    local bindKey = '';
    if bind then
        if bind.actionType == 'macro' then
            -- Macros can vary by text and recast override; include these to prevent incorrect cache reuse.
            -- Keep it string-only and bounded (macroText is small).
            bindKey = 'macro:' ..
                (bind.recastSourceType or '') .. ':' ..
                (bind.recastSourceAction or '') .. ':' ..
                (bind.recastSourceItemId or '') .. ':' ..
                (bind.action or '') .. ':' ..
                (bind.macroText or '');
        else
            bindKey = (bind.actionType or '') .. ':' .. (bind.action or '');
        end
    end

    -- Player + party slot 0 levels: under level sync the effective cap can change when the sync target
    -- levels up (buff 269 unchanged). Party levels may update before Player API; include both in key.
    local memForAvail = AshitaCore:GetMemoryManager();
    local playerForAvail = memForAvail and memForAvail:GetPlayer();
    local mainJobLevelForAvail = playerForAvail and playerForAvail:GetMainJobLevel() or 0;
    local subJobLevelForAvail = playerForAvail and playerForAvail:GetSubJobLevel() or 0;
    local partyMainLvAvail = 0;
    local partySubLvAvail = 0;
    local partyForAvail = memForAvail and memForAvail:GetParty();
    if partyForAvail and partyForAvail.GetMemberIsActive and partyForAvail:GetMemberIsActive(0) == 1 then
        partyMainLvAvail = partyForAvail:GetMemberMainJobLevel(0) or 0;
        partySubLvAvail = partyForAvail:GetMemberSubJobLevel(0) or 0;
    end

    if bind and not isLiteChecks then
        local mpCost = mpCostCache[bindKey];
        if mpCost == nil then
            mpCost = actions.GetMPCost(bind) or false;
            PutMpCostCache(bindKey, mpCost);
        end
        if mpCost and mpCost ~= false then
            local party = AshitaCore:GetMemoryManager():GetParty();
            local playerMp = party and party:GetMemberMP(0) or 0;
            notEnoughMp = playerMp < mpCost;
        end
    end

    -- Weapon skills (and macros whose primary line is /ws) need 1000 TP for UI grey state
    local notEnoughTp = false;
    if bind and not isLiteChecks then
        local needsWsTp = false;
        if bind.actionType == 'ws' then
            needsWsTp = true;
        elseif bind.actionType == 'macro' and bind.macroText then
            local primaryType = select(1, macroparse.GetMacroPrimaryAndJaBadge(bind.macroText));
            if primaryType == 'ws' then
                needsWsTp = true;
            end
        end
        if needsWsTp then
            local partyTp = AshitaCore:GetMemoryManager():GetParty();
            local playerTp = partyTp and partyTp:GetMemberTP(0) or 0;
            notEnoughTp = playerTp < 1000;
        end
    end

    -- Check if action is available (job/level requirements)
    local isUnavailable = false;
    local unavailableReason = nil;
    if not isLiteChecks and bind and (bind.actionType == 'ma' or bind.actionType == 'ja' or bind.actionType == 'ws' or bind.actionType == 'pet' or bind.actionType == 'macro') then
        -- Include job/subjob AND effective levels so cache invalidates on level sync
        local player = playerForAvail;
        local jobId = player and player:GetMainJob() or 0;
        local subjobId = player and player:GetSubJob() or 0;
        local availKey = bindKey .. ':' .. jobId .. ':' .. subjobId .. ':' .. mainJobLevelForAvail .. ':' .. subJobLevelForAvail
            .. ':' .. partyMainLvAvail .. ':' .. partySubLvAvail;

        local cached = availabilityCache[availKey];
        if cached == nil then
            local available, reason = actions.IsActionAvailable(bind);
            -- Don't cache if reason is "pending" (player state invalid, e.g., during zoning)
            if reason ~= "pending" then
                local cachedEntry = { isAvailable = available, reason = reason };
                PutAvailabilityCache(availKey, cachedEntry);
                cached = cachedEntry;
            else
                -- Use temp result but don't cache
                cached = { isAvailable = available, reason = nil };
            end
        end
        isUnavailable = not cached.isAvailable;
        unavailableReason = cached.reason;
    end

    -- Tint for ImGui corner overlays (ammo / pet status / macro /ja badge): same logic as main icon
    local overlayColorMult = 1.0;
    local overlayApplyGrey = false;
    if isUnavailable then
        overlayColorMult = 0.35;
        overlayApplyGrey = false;
    elseif isOnCooldown then
        overlayColorMult = 0.4;
    elseif notEnoughTp then
        overlayColorMult = 0.6;
    elseif notEnoughMp then
        overlayColorMult = 0.6;
    end
    overlayColorMult = overlayColorMult * dimFactor;
    local oR, oG, oB;
    if overlayApplyGrey then
        local grey = math.floor(180 * overlayColorMult);
        oR, oG, oB = grey, grey, grey;
    elseif isUnavailable then
        oR = math.floor(120 * overlayColorMult);
        oG = math.floor(25 * overlayColorMult);
        oB = math.floor(28 * overlayColorMult);
    else
        local rgb = math.floor(255 * overlayColorMult);
        oR, oG, oB = rgb, rgb, rgb;
    end
    local overlayAlpha = math.floor(255 * animOpacity * (isUnavailable and 0.7 or 1.0));
    local overlayTint = bit.bor(
        bit.lshift(overlayAlpha, 24),
        bit.lshift(oR, 16),
        bit.lshift(oG, 8),
        oB
    );

    -- ========================================
    -- 4. Icon Rendering (Primitive for file-based, ImGui for memory-based)
    -- ========================================
    local iconRendered = false;

    -- Try primitive rendering first (for icons with file paths like spell icons)
    if resources.iconPrim and not forceImGuiIcon then
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
                applyGreyTint = false;
            elseif isOnCooldown then
                colorMult = 0.4;
            elseif notEnoughTp then
                colorMult = 0.6;
            elseif notEnoughMp then
                colorMult = 0.6;  -- Slightly dimmed when not enough MP
            end
            colorMult = colorMult * dimFactor;

            -- Calculate RGB values
            local r, g, b;
            if isUnavailable then
                r = math.floor(120 * colorMult);
                g = math.floor(25 * colorMult);
                b = math.floor(28 * colorMult);
            elseif applyGreyTint then
                local grey = math.floor(180 * colorMult);
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
    elseif resources.iconPrim then
        resources.iconPrim.visible = false;
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
                    colorMult = 0.35;
                    applyGreyTint = false;
                elseif isOnCooldown then
                    colorMult = 0.4;
                elseif notEnoughTp then
                    colorMult = 0.6;
                elseif notEnoughMp then
                    colorMult = 0.6;  -- Slightly dimmed when not enough MP
                end
                colorMult = colorMult * dimFactor;

                -- Calculate RGB values
                local r, g, b;
                if isUnavailable then
                    r = math.floor(120 * colorMult);
                    g = math.floor(25 * colorMult);
                    b = math.floor(28 * colorMult);
                elseif applyGreyTint then
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
    -- 4c. Corner overlay icons (ImGui draw list) — MUST run before GDI text (MP/Lv/Qty/keybinds).
    -- If these come after GDI fonts, they composite on top and hide corner text.
    -- ========================================
    if bind and animOpacity > 0.5 then
        -- 4c-1. Ammo status effect icon (top-right)
        if bind.actionType == 'item' and bind.itemId then
            local statusId = GetAmmoStatusEffect(bind.itemId);
            if statusId then
                local statusIconPtr = statusHandler.get_icon_from_theme(gConfig.statusIconTheme, statusId);
                if statusIconPtr then
                    local drawList = imgui.GetWindowDrawList();
                    if drawList then
                        local cornerSz = size * 0.35;
                        local padding = 2;
                        local iconX = x + size - cornerSz - padding;
                        local iconY = y + padding;
                        drawList:AddImage(
                            statusIconPtr,
                            {iconX, iconY},
                            {iconX + cornerSz, iconY + cornerSz},
                            {0, 0}, {1, 1},
                            overlayTint
                        );
                    end
                end
            end
        end
        -- 4c-2. Pet pact status icon (bottom-left): optional per-pact PNG, else theme icon from pact.status label
        local pact = actions.GetResolvedBloodPact and actions.GetResolvedBloodPact(bind) or nil;
        local cornerTex = pact and actions.GetBloodPactStatusCornerIcon and actions.GetBloodPactStatusCornerIcon(bind, pact) or nil;
        local statusLabel = pact and pact.status or nil;
        local statusId = (not cornerTex) and statusLabel and STATUS_ID_BY_LABEL[statusLabel] or nil;
        local statusIconPtr = nil;
        if cornerTex and cornerTex.image then
            statusIconPtr = tonumber(ffi.cast('uint32_t', cornerTex.image));
        elseif statusId then
            statusIconPtr = statusHandler.get_icon_from_theme(gConfig.statusIconTheme, statusId);
        end
        if statusIconPtr then
            local drawList = imgui.GetWindowDrawList();
            if drawList then
                local cornerSz = size * 0.35;
                local padding = 2;
                local iconX = x + padding;
                local iconY = y + size - cornerSz - padding;
                drawList:AddImage(
                    statusIconPtr,
                    {iconX, iconY},
                    {iconX + cornerSz, iconY + cornerSz},
                    {0, 0}, {1, 1},
                    overlayTint
                );
            end
        end
        -- 4c-3. Macro /ja ability badge (bottom-right)
        if bind.actionType == 'macro' and bind.macroText and bind.showJaBadgeOnMacro ~= false then
            local jaName = actions.GetMacroJaBadgeAbilityName(bind.macroText);
            if jaName then
                local jaIcon = actions.ResolveMacroJaBadgeIcon(bind);
                if jaIcon and jaIcon.image then
                    local drawList = imgui.GetWindowDrawList();
                    if drawList then
                        local iconPtr = tonumber(ffi.cast('uint32_t', jaIcon.image));
                        if iconPtr and iconPtr ~= 0 then
                            local cornerSz = size * 0.35;
                            local padding = 2;
                            local iconX = x + size - cornerSz - padding;
                            local iconY = y + size - cornerSz - padding;
                            drawList:AddImage(
                                iconPtr,
                                {iconX, iconY},
                                {iconX + cornerSz, iconY + cornerSz},
                                {0, 0}, {1, 1},
                                overlayTint
                            );
                        end
                    end
                end
            end
        end
    end

    -- ========================================
    -- 4b. Abbreviation Text Fallback (when no icon available)
    -- Uses GdiFonts for cached text rendering (avoids per-frame ImGui overhead)
    -- ========================================
    if not iconRendered and bind and animOpacity > 0.5 and not recastText then
        if resources.abbreviationFont then
            local abbr = GetActionAbbreviation(bind);

            -- Only update text when changed
            if cache and cache.abbreviation ~= abbr then
                resources.abbreviationFont:set_text(abbr);
                cache.abbreviation = abbr;
            end

            -- Compute color with dimming (same priority as main icon)
            local colorMult = 1.0;
            if isUnavailable then colorMult = 0.35;
            elseif isOnCooldown then colorMult = 0.4;
            elseif notEnoughTp then colorMult = 0.6;
            elseif notEnoughMp then colorMult = 0.6; end
            colorMult = colorMult * dimFactor;

            -- Gold base: R=244, G=218, B=151 (0xF4DA97)
            local r = math.floor(244 * colorMult);
            local g = math.floor(218 * colorMult);
            local b = math.floor(151 * colorMult);
            local a = math.floor(animOpacity * 255);
            local abbrColor = bit.bor(bit.lshift(a, 24), bit.lshift(r, 16), bit.lshift(g, 8), b);

            if cache and cache.abbreviationColor ~= abbrColor then
                resources.abbreviationFont:set_font_color(abbrColor);
                cache.abbreviationColor = abbrColor;
            end

            -- Center position
            local abbrX = x + size / 2;
            local abbrY = y + size / 2 - 6;
            if cache and (cache.abbrX ~= abbrX or cache.abbrY ~= abbrY) then
                resources.abbreviationFont:set_position_x(abbrX);
                resources.abbreviationFont:set_position_y(abbrY);
                cache.abbrX = abbrX;
                cache.abbrY = abbrY;
            end

            resources.abbreviationFont:set_visible(true);
        end
    else
        if resources.abbreviationFont then
            resources.abbreviationFont:set_visible(false);
            if cache then cache.abbreviation = nil; end
        end
    end

    -- ========================================
    -- 5. Timer Font (GDI) — never composited via the GDI sprite path (icons would cover it).
    -- Cooldown digits are rasterized from this font in §11c (foreground AddImage).
    -- ========================================
    if resources.timerFont then
        resources.timerFont:set_visible(false);
        if (not recastText or recastText == '') and cache and cache.cooldownOverlayText then
            resources.timerFont:set_text('');
            cache.cooldownOverlayText = nil;
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
    -- 7. Label Font (GDI - action name)
    -- Default: below slot. Crossbar can request above-slot labels to avoid overlap.
    -- ========================================
    if resources.labelFont and not useFgLabel then
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

            local labelY;
            if params.labelAboveSlot then
                -- Place label above the slot (used by crossbar top slots to avoid overlapping lower slots).
                local fontH = params.labelFontSize or 10;
                local baseLabelY = y - fontH - 4;
                labelY = baseLabelY + (params.labelOffsetY or 0);
                -- Clamp so it can't drift down into the slot area.
                if labelY > baseLabelY then
                    labelY = baseLabelY;
                end
            else
                -- Default: below slot.
                -- Prevent label from being moved into the slot (which can overlap MP cost, keybinds, etc.)
                -- Users can still move it further down with positive offsets.
                local baseLabelY = y + size + 2;
                labelY = baseLabelY + (params.labelOffsetY or 0);
                if labelY < baseLabelY then
                    labelY = baseLabelY;
                end
            end
            if cache and (cache.labelX ~= labelX or cache.labelY ~= labelY) then
                resources.labelFont:set_position_x(labelX);
                resources.labelFont:set_position_y(labelY);
                cache.labelX = labelX;
                cache.labelY = labelY;
            end

            -- Determine label color based on state
            -- Priority: Unavailable (grey) > Cooldown (grey) > Low TP (grey) > Not enough MP (red) > Normal
            local labelColor = params.labelFontColor or 0xFFFFFFFF;

            if isUnavailable then
                labelColor = 0xFF888888;
            elseif isOnCooldown then
                labelColor = params.labelCooldownColor or 0xFF888888;
            elseif notEnoughTp then
                labelColor = params.labelCooldownColor or 0xFF888888;
            elseif notEnoughMp then
                labelColor = params.labelNoMpColor or 0xFFFF4444;
            end
            labelColor = DimArgbColor(labelColor, dimFactor);

            -- Only update color if changed
            if cache and cache.labelFontColor ~= labelColor then
                resources.labelFont:set_font_color(labelColor);
                cache.labelFontColor = labelColor;
            end

            resources.labelFont:set_visible(animOpacity > 0.5);
        else
            resources.labelFont:set_visible(false);
        end
    elseif resources.labelFont then
        resources.labelFont:set_visible(false);
    end

    if useFgLabel and params.showLabel and params.labelText and params.labelText ~= '' and animOpacity > 0.5 then
        local fullText = minimalEditorView and EditorLabelWrapNearSlot(params.labelText, params.labelAboveSlot) or params.labelText;
        local labelText = fullText;
        if minimalEditorView then
            if isHovered then
                labelText = fullText;
            else
                labelText = EditorIdleAbbrev4(params.labelText);
            end
        end
        if labelText and labelText ~= '' then
            local labelColor = params.labelFontColor or 0xFFFFFFFF;
            if isUnavailable then
                labelColor = 0xFF888888;
            elseif isOnCooldown then
                labelColor = params.labelCooldownColor or 0xFF888888;
            elseif notEnoughTp then
                labelColor = params.labelCooldownColor or 0xFF888888;
            elseif notEnoughMp then
                labelColor = params.labelNoMpColor or 0xFFFF4444;
            end
            labelColor = DimArgbColor(labelColor, dimFactor);
            if minimalEditorView and isHovered and not dragdrop.IsDragging() then
                labelColor = LerpArgbTowardWhite(labelColor, 0.38);
            end
            fgLabel = { text = labelText, color = labelColor };
        end
    end

    -- ========================================
    -- 8. MP Cost Font (GDI - anchored position)
    -- Shows level requirement (e.g. Lv65) when gated by level, else "X" for other unavailable, else MP cost,
    -- else x### for ninjutsu tools when the spell has no MP line (same corner as MP/Lv).
    -- When drawCornerTextForeground is set, GDI is hidden and the same strings are drawn in §11b (above D3D icons).
    -- ========================================
    if resources.mpCostFont and not minimalEditorView then
        fgCornerMp = nil;
        local showMpCost = params.showMpCost ~= false;
        local mpCostAnchor = params.mpCostAnchor or 'topLeft';
        if showMpCost and bind and animOpacity > 0.5 then
            -- Calculate position using anchor (GDI uses anchor + font alignment; matches hotbar defaults when unset)
            local mpX, mpY = GetAnchoredPosition(x, y, size, mpCostAnchor, params.mpCostOffsetX, params.mpCostOffsetY);
            
            -- If action is unavailable, show level text when IsActionAvailable returned Lvn (or legacy Lvl.n)
            if isUnavailable then
                local unavailText = 'X';
                if unavailableReason then
                    local legacyLvl = unavailableReason:match('^Lvl%.(%d+)$');
                    if legacyLvl then
                        unavailText = 'Lv' .. legacyLvl;
                    elseif unavailableReason:match('^Lv%d+$') then
                        unavailText = unavailableReason;
                    else
                        local legacyLv = unavailableReason:match('^Lv(%d+)$');
                        if legacyLv then
                            unavailText = 'Lv' .. legacyLv;
                        end
                    end
                end
                if cache and cache.mpCostText ~= unavailText then
                    resources.mpCostFont:set_text(unavailText);
                    cache.mpCostText = unavailText;
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
                local xColor = DimArgbColor(0xFFFF4444, dimFactor);
                if cache and cache.mpCostFontColor ~= xColor then
                    resources.mpCostFont:set_font_color(xColor);
                    cache.mpCostFontColor = xColor;
                end
                if useFgCornerText then
                    local imx, imy = ImGuiTopLeftForForegroundCorner(x, y, size, mpCostAnchor, params.mpCostOffsetX, params.mpCostOffsetY, unavailText, params.mpCostFontSize or 10);
                    fgCornerMp = { text = unavailText, color = xColor, x = imx, y = imy };
                end
                resources.mpCostFont:set_visible(not useFgCornerText);
            else
                -- Normal MP cost display (spells + pet pacts via registry + macro-derived)
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

                    -- Determine MP cost color - red if not enough MP; dim with inactive side
                    local mpCostColor = params.mpCostFontColor or 0xFFD4FF97;
                    if notEnoughMp then
                        mpCostColor = params.mpCostNoMpColor or 0xFFFF4444;
                    end
                    mpCostColor = DimArgbColor(mpCostColor, dimFactor);

                    if cache and cache.mpCostFontColor ~= mpCostColor then
                        resources.mpCostFont:set_font_color(mpCostColor);
                        cache.mpCostFontColor = mpCostColor;
                    end
                    if useFgCornerText then
                        local imx, imy = ImGuiTopLeftForForegroundCorner(x, y, size, mpCostAnchor, params.mpCostOffsetX, params.mpCostOffsetY, mpText, params.mpCostFontSize or 10);
                        fgCornerMp = { text = mpText, color = mpCostColor, x = imx, y = imy };
                    end
                    resources.mpCostFont:set_visible(not useFgCornerText);
                elseif bind.actionType == 'ma' then
                    -- Ninjutsu (and similar): no MP line in DB — show tool count in the same corner as MP/Lv (x###, same as item xN).
                    local toolQty = M.GetNinjutsuToolQuantity(bind.action);
                    if toolQty ~= nil then
                        local qtyText = 'x' .. tostring(toolQty);
                        if cache and cache.mpCostText ~= qtyText then
                            resources.mpCostFont:set_text(qtyText);
                            cache.mpCostText = qtyText;
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
                        local qtyCornerColor = (toolQty == 0) and (params.mpCostNoMpColor or 0xFFFF4444) or (params.mpCostFontColor or 0xFFD4FF97);
                        qtyCornerColor = DimArgbColor(qtyCornerColor, dimFactor);
                        if cache and cache.mpCostFontColor ~= qtyCornerColor then
                            resources.mpCostFont:set_font_color(qtyCornerColor);
                            cache.mpCostFontColor = qtyCornerColor;
                        end
                        if useFgCornerText then
                            local imx, imy = ImGuiTopLeftForForegroundCorner(x, y, size, mpCostAnchor, params.mpCostOffsetX, params.mpCostOffsetY, qtyText, params.mpCostFontSize or 10);
                            fgCornerMp = { text = qtyText, color = qtyCornerColor, x = imx, y = imy };
                        end
                        resources.mpCostFont:set_visible(not useFgCornerText);
                    else
                        resources.mpCostFont:set_visible(false);
                    end
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
    if resources.quantityFont and not minimalEditorView then
        fgCornerQty = nil;
        local showQuantity = params.showQuantity ~= false;
        local quantityAnchor = params.quantityAnchor or 'bottomRight';
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
                -- Ninjutsu tools: show xN on the quantity anchor when MP cost is also shown there; otherwise x### is drawn in the MP/Lv corner only.
                local toolQty = M.GetNinjutsuToolQuantity(bind.action);
                if toolQty ~= nil then
                    local mpCost = mpCostCache[bindKey];
                    if mpCost == nil then
                        mpCost = actions.GetMPCost(bind) or false;
                        mpCostCache[bindKey] = mpCost;
                    end
                    if mpCost and mpCost ~= false then
                        quantity = toolQty;
                        shouldShowQty = true;
                    end
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
            local qtyX, qtyY = GetAnchoredPosition(x, y, size, quantityAnchor, params.quantityOffsetX, params.quantityOffsetY);
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
            if useFgCornerText then
                local iqx, iqy = ImGuiTopLeftForForegroundCorner(x, y, size, quantityAnchor, params.quantityOffsetX, params.quantityOffsetY, qtyText, params.quantityFontSize or 10);
                fgCornerQty = { text = qtyText, color = qtyColor, x = iqx, y = iqy };
            end
            resources.quantityFont:set_visible(not useFgCornerText);
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
    -- Use appropriate draw list (behind config when open)
    -- ========================================
    local fgDrawList = slotOverlayDrawList();
    if fgDrawList and animOpacity > 0.5 then
        -- Foreground hover/press sits above ImGui; in Edit Full Palette it was the only thing making empty D3D slots visible.
        -- Editor uses window-DL chrome + labels; skip FG overlays here to avoid wrong stacking.
        if not minimalEditorView then
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
        end

        -- Skillchain highlight (animated dotted border + icon) — opacity follows slot dim state
        if params.skillchainName then
            local scColor = params.skillchainColor or 0xFFD4AA44;  -- Default gold
            local scHighlightOpacity = animOpacity * dimFactor;
            if isUnavailable then
                scHighlightOpacity = scHighlightOpacity * 0.35 * 0.7;
            elseif isOnCooldown then
                scHighlightOpacity = scHighlightOpacity * 0.4;
            elseif notEnoughTp then
                scHighlightOpacity = scHighlightOpacity * 0.6;
            elseif notEnoughMp then
                scHighlightOpacity = scHighlightOpacity * 0.6;
            end
            DrawSkillchainHighlight(fgDrawList, x, y, size, params.skillchainName, scColor, scHighlightOpacity,
                params.skillchainIconScale, params.skillchainIconOffsetX, params.skillchainIconOffsetY);
        end

        -- Universal two-hour: rainbow ring stack while confirming <stpc>/<stnpc> (or brief post-click arming shimmer).
        if bind and not isOnCooldown and universalTwoHour.ShouldGlowUniversalTwoHourSlot(bind) then
            DrawUniversalTwoHourSubtargetGlow(fgDrawList, x, y, size, animOpacity, dimFactor,
                universalTwoHour.GetArmingShimmerOpacityScale());
        end
    end

    -- ========================================
    -- 11b. Foreground corner strings (MP / Lv / x###) when drawCornerTextForeground is set
    -- Drawn after §11 so they sit above hover tint and, critically, above D3D icon primitives.
    -- ========================================
    if useFgCornerText and not minimalEditorView and animOpacity > 0.5 then
        local topDl = slotOverlayDrawList();
        if topDl then
            if fgCornerMp and fgCornerMp.text and fgCornerMp.text ~= '' then
                AddOutlinedForegroundText(topDl, fgCornerMp.x, fgCornerMp.y, fgCornerMp.color, fgCornerMp.text);
            end
            if fgCornerQty and fgCornerQty.text and fgCornerQty.text ~= '' then
                AddOutlinedForegroundText(topDl, fgCornerQty.x, fgCornerQty.y, fgCornerQty.color, fgCornerQty.text);
            end
        end
    end

    -- ========================================
    -- 11c. Foreground cooldown timer (center) — must be above D3D icon primitives + frame
    -- Prefer GDI timerFont rasterized to a texture (matches pre–foreground-text size & weight).
    -- ========================================
    if recastText and not minimalEditorView and animOpacity > 0.5 then
        local timerColor = params.recastTimerFontColor or 0xFFFFFFFF;
        local remaining = recastRemaining or 0;
        if params.flashCooldownUnder5 and remaining > 0 and remaining < 5 then
            local pulseAlpha = 0.5 + 0.5 * math.sin(os.clock() * 8);
            local alpha = math.floor(pulseAlpha * 255);
            local r = bit.rshift(bit.band(timerColor, 0x00FF0000), 16);
            local g = bit.rshift(bit.band(timerColor, 0x0000FF00), 8);
            local b = bit.band(timerColor, 0x000000FF);
            timerColor = bit.bor(bit.lshift(alpha, 24), bit.lshift(r, 16), bit.lshift(g, 8), b);
        end

        local topDl = slotOverlayDrawList();
        if topDl then
            local usedGdi = resources.timerFont and DrawGdiTimerCooldownForeground(
                topDl, resources.timerFont, recastText, timerColor, x, y, size, animOpacity, params, cache
            );
            if not usedGdi then
                local fs = (params.recastTimerFontSize or 11) + 1;
                local font = imgui.GetFont and imgui.GetFont();
                local pushedFont = false;
                local scaleRestore = false;
                if imgui.PushFont and font then
                    pushedFont = pcall(function()
                        imgui.PushFont(font, fs);
                    end);
                end
                if not pushedFont and imgui.SetWindowFontScale and imgui.GetFontSize then
                    local baseSz = imgui.GetFontSize();
                    if baseSz and baseSz > 0 then
                        imgui.SetWindowFontScale(fs / baseSz);
                        scaleRestore = true;
                    end
                end
                local tw, th = GetImGuiTextSize2D(recastText);
                local cx = x + size / 2;
                local cy = y + size / 2;
                local px = cx - tw * 0.5;
                local py = cy - th * 0.5;
                AddGdiLikeCooldownForegroundText(topDl, px, py, timerColor, recastText, font, fs);
                if pushedFont and imgui.PopFont then
                    pcall(imgui.PopFont);
                end
                if scaleRestore then
                    imgui.SetWindowFontScale(1.0);
                end
            end
        end
    end

    -- ========================================
    -- 11d. Edit Full Palette: hover / LMB press tint on window DL (mirrors §11 FG on live crossbar; FG skipped for editor)
    -- Applies to filled and empty slots (§1b draws empty chrome earlier; this layers the same highlight as gameplay).
    -- ========================================
    if minimalEditorView and animOpacity > 0.5 and isHovered and not dragdrop.IsDragging() then
        local dlHl = imgui.GetWindowDrawList();
        if dlHl then
            local editorLmb = false;
            if imgui.IsMouseDown then
                local ok, down = pcall(function() return imgui.IsMouseDown(0); end);
                if ok and down then
                    editorLmb = true;
                end
            end
            local clip = params.editorClipRect;
            local pushedHl = false;
            if clip and clip[1] and clip[2] and clip[3] and clip[4] and dlHl.PushClipRect then
                dlHl:PushClipRect({ clip[1], clip[2] }, { clip[3], clip[4] }, true);
                pushedHl = true;
            end
            if editorLmb then
                local fill = imgui.GetColorU32({ 1, 1, 1, 0.25 * animOpacity });
                local brd = imgui.GetColorU32({ 1, 1, 1, 0.5 * animOpacity });
                dlHl:AddRectFilled({ x, y }, { x + size, y + size }, fill, 4);
                dlHl:AddRect({ x, y }, { x + size, y + size }, brd, 4, 0, 2);
            else
                local fill = imgui.GetColorU32({ 1, 1, 1, 0.15 * animOpacity });
                local brd = imgui.GetColorU32({ 1, 1, 1, 0.10 * animOpacity });
                dlHl:AddRectFilled({ x, y }, { x + size, y + size }, fill, 2);
                dlHl:AddRect({ x, y }, { x + size, y + size }, brd, 2, 0, 1);
            end
            if pushedHl and dlHl.PopClipRect then
                dlHl:PopClipRect();
            end
        end
    end

    if fgLabel then
        -- Edit Full Palette (labelForeground): window draw list so labels stay under other ImGui windows and respect scroll clip.
        local dl = imgui.GetWindowDrawList();
        if dl then
            local clip = params.editorClipRect;
            local pushedClip = false;
            if clip and clip[1] and clip[2] and clip[3] and clip[4] and dl.PushClipRect then
                dl:PushClipRect({ clip[1], clip[2] }, { clip[3], clip[4] }, true);
                pushedClip = true;
            end
            local fs = (params.labelFontSize or 10);
            local fnt = imgui.GetFont and imgui.GetFont() or nil;
            if minimalEditorView then
                AddEditorMultilineCenteredOnSlotLikeCorner(dl, x, y, size, fgLabel.color, fgLabel.text, fnt, fs);
            else
                local labelX = x + size / 2 + (params.labelOffsetX or 0);
                local labelY;
                if params.labelAboveSlot then
                    local fontH = fs;
                    local baseLabelY = y - fontH - 4;
                    labelY = baseLabelY + (params.labelOffsetY or 0);
                    if labelY > baseLabelY then labelY = baseLabelY; end
                else
                    local baseLabelY = y + size + 2;
                    labelY = baseLabelY + (params.labelOffsetY or 0);
                    if labelY < baseLabelY then labelY = baseLabelY; end
                end
                AddEditorMultilineCenteredOutlined(dl, labelX, labelY, fgLabel.color, fgLabel.text, fnt, fs);
            end
            if pushedClip and dl.PopClipRect then
                dl:PopClipRect();
            end
        end
    end

    -- ========================================
    -- 12. Drop Zone Registration
    -- ========================================
    if params.dropZoneId and params.onDrop and not IsMovementLockedForDropZone(params.dropZoneId) then
        dragdrop.DropZone(params.dropZoneId, x, y, size, size, {
            accepts = params.dropAccepts or {'macro'},
            highlightColor = params.dropHighlightColor or 0xA8FFFFFF,
            dropPriority = params.dropPriority,
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

        -- Left click / double-click
        -- Edit Full Palette uses suppressActionOnClick: micro-drags still end with WasDragAttempted();
        -- we must not block click/double-click tracking for those slots or double-click never registers.
        if isItemHovered and imgui.IsMouseReleased(0) then
            local ignoreCancelledMicroDrag = params.suppressActionOnClick;
            if not dragdrop.IsDragging()
                and (ignoreCancelledMicroDrag or not dragdrop.WasDragAttempted()) then
                local now = os.clock();
                local isDoubleClick = (params.buttonId == lastClickButtonId)
                    and (now - lastClickTime) < DOUBLE_CLICK_INTERVAL;

                if isDoubleClick and params.onDoubleClick then
                    params.onDoubleClick();
                    lastClickButtonId = nil;
                    lastClickTime = 0;
                elseif params.suppressActionOnClick then
                    lastClickButtonId = params.buttonId;
                    lastClickTime = now;
                elseif params.onClick then
                    params.onClick();
                elseif command then
                    actions.NotifySlotExecutionEffects(bind);
                    actions.ExecuteCommandString(command, bind and bind.actionType == 'macro');
                end
            end
        end

        -- Right click (disabled when movement lock applies to this slot type)
        if isItemHovered and imgui.IsMouseClicked(1) and bind then
            local rcLocked;
            if params.dropZoneId then
                rcLocked = IsMovementLockedForDropZone(params.dropZoneId);
            else
                rcLocked = gConfig and gConfig.hotbarLockMovement;
            end
            if params.onRightClick and not rcLocked then
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

    -- Match DrawSlot: macros/pet/ma/ja/ws all use IsActionAvailable (including parsed macro lines)
    local isUnavailable = false;
    do
        local available, reason = actions.IsActionAvailable(bind);
        if reason ~= 'pending' then
            isUnavailable = not available;
        end
    end

    -- Style the tooltip
    imgui.PushStyleColor(ImGuiCol_PopupBg, COLORS.bgDark);
    imgui.PushStyleColor(ImGuiCol_Border, COLORS.border);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {8, 6});

    imgui.BeginTooltip();

    -- Action name (gold)
    local displayName = bind.displayName or bind.action or 'Unknown';
    if bind.actionType == 'ja' and bind.action == universalTwoHour.ACTION_SENTINEL then
        displayName = universalTwoHour.GetTwoHourAbilityNameForMainJob() or displayName;
    end
    imgui.TextColored(COLORS.gold, displayName);

    imgui.Spacing();

    -- Action type
    local typeLabel = ACTION_TYPE_LABELS[bind.actionType] or bind.actionType or '?';
    imgui.TextColored(COLORS.textDim, 'Type: ' .. typeLabel);

    -- Target (not shown for macro type since targets are embedded in macro text)
    local tgtForTip = bind.target;
    if bind.actionType == 'ja' and bind.action == universalTwoHour.ACTION_SENTINEL then
        tgtForTip = universalTwoHour.ResolveJaBindTarget(bind) or tgtForTip;
    end
    if bind.actionType ~= 'macro' and tgtForTip and tgtForTip ~= '' then
        local formattedTarget = formatTarget(tgtForTip);
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
    if resources.abbreviationFont then resources.abbreviationFont:set_visible(false); end
end

return M;
