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
-- TextureManager.DeferRelease holds Lua refs alive for one frame so wiping the
-- texturePtrCache mid-frame (e.g. palette delete fires InvalidateAllVisualCachesAfter
-- PaletteListMutation) doesn't race the current frame's queued AddImage calls.
local TextureManager = require('libs.texturemanager');
-- libs/color.lua has ARGB <-> ImGui U32 + HSV<->RGB helpers we use for UTH effects.
-- Audit pass deduped a local ArgbToImguiU32 and a local UthHsvToRgb that had identical math.
local colorlib = require('libs.color');
-- universal_two_hour is a Ferris addition that tracks the universal-2hr armed-slot state
-- so the rainbow ring glow knows which slot to decorate. Loaded with pcall so 1.7.5-era
-- forks without the module still render normal slots without crashing.
local universalTwoHour = nil;
do
    local ok, mod = pcall(require, 'modules.hotbar.universal_two_hour');
    if ok then universalTwoHour = mod; end
end

-- Deferred tooltip: stored during render, drawn after all windows to ensure z-order
local pendingTooltipBind = nil;
local tooltipFontSettings = nil;

-- Manual double-click tracking. Using `imgui.IsMouseDoubleClicked` here is unreliable
-- because the drag/drop system swallows the first click on slots that participate in
-- drag (the first MouseDown starts a deferred-drag candidate which suppresses the click).
-- We instead track the last click target and its timestamp ourselves and decide on
-- MouseReleased(0) — that's the same point WasDragAttempted resolves, so double-click
-- semantics stay consistent with single-click semantics.
local lastClickButtonId = nil;
local lastClickTime = 0;
local DOUBLE_CLICK_INTERVAL = 0.35;

-- Tooltip constants (ARGB for text colors used with imtext, ABGR/U32 for rect colors)
local TOOLTIP_FONT_SIZE = 12;
local TOOLTIP_COL_GOLD   = 0xF2F4DA97;
local TOOLTIP_COL_DIM    = 0xFF999999;
local TOOLTIP_COL_RED    = 0xFFFF4D4D;
local TOOLTIP_COL_BG     = 0xF2110F0E;
local TOOLTIP_COL_BORDER = 0xCC3E4748;

local ACTION_TYPE_LABELS = {
    ma = 'Spell (ma)', ja = 'Ability (ja)', ws = 'Weaponskill (ws)',
    item = 'Item', equip = 'Equip', macro = 'Macro', pet = 'Pet Command',
};

-- Cache for MP cost lookups (keyed by action key string)
local mpCostCache = {};
local mpCostCacheSize = 0;
local MP_COST_CACHE_MAX = 4096;

-- Cache for action availability checks (keyed by action key string).
-- Structure: { isAvailable = bool, reason = string|nil }
-- The cache key embeds (main job, sub job, main level, sub level, party-member main/sub level)
-- so Level Sync transitions invalidate previously-cached availabilities (a spell that was
-- available at L75 may stop being available at synced L40). Without this the cache returns
-- stale results across sync changes. Size-bounded by AVAILABILITY_CACHE_MAX — when exceeded
-- the cache is reset wholesale (cheaper than LRU eviction for a frequently-rebuilt cache).
local availabilityCache = {};
local availabilityCacheSize = 0;
local AVAILABILITY_CACHE_MAX = 8192;

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

-- Per-frame snapshot of (player, party, job ids, effective levels). Reset at BeginFrame
-- and read lazily from the availability path so we only walk the MemoryManager once per
-- frame instead of once per (slot * frame). At ~16 main-bar slots + 16 preview slots + N
-- keyboard bars this drops the per-frame FFI walk from N*7 getters to a constant ~7. The
-- snapshot is intentionally lazy (first slot that needs it warms it) so frames without
-- any availability checks pay zero cost.
--
-- IMPORTANT: keep this declared BEFORE M.DrawSlot — Lua local-function forward references
-- only work if the symbol is visible at the call site. Putting it after caused a
-- "attempt to call global 'GetFrameAvailability' (a nil value)" load error.
local frameAvail = { ready = false };

local function GetFrameAvailability()
    if frameAvail.ready then return frameAvail; end
    local memMgr = AshitaCore:GetMemoryManager();
    local player = memMgr and memMgr:GetPlayer();
    if not player then
        frameAvail.ready = true;
        frameAvail.jobId = 0; frameAvail.subjobId = 0;
        frameAvail.mainLevel = 0; frameAvail.subLevel = 0;
        frameAvail.partyMain = 0; frameAvail.partySub = 0;
        return frameAvail;
    end
    frameAvail.jobId     = player:GetMainJob() or 0;
    frameAvail.subjobId  = player:GetSubJob() or 0;
    frameAvail.mainLevel = player:GetMainJobLevel() or 0;
    frameAvail.subLevel  = player:GetSubJobLevel() or 0;
    local partyMain, partySub = 0, 0;
    local party = memMgr and memMgr:GetParty();
    if party then
        partyMain = party:GetMemberMainJobLevel(0) or 0;
        partySub  = party:GetMemberSubJobLevel(0) or 0;
    end
    frameAvail.partyMain = partyMain;
    frameAvail.partySub  = partySub;
    frameAvail.ready     = true;
    return frameAvail;
end

-- Cache for item quantity lookups (keyed by itemId or itemName)
-- Structure: { quantity = number, timestamp = number }
-- CRITICAL: Without this cache, item quantity lookups scan ALL inventory slots EVERY FRAME
-- which causes massive performance issues (especially for items without itemId that require name matching)
local itemQuantityCache = {};
local ITEM_QUANTITY_CACHE_TTL = 2.0;  -- Cache for 2 seconds (inventory doesn't change that often)

-- Cache for item stack size lookups (keyed by itemId).
-- Stack size is static resource data, so cache forever for the session.
-- Stored value: number (StackSize) or false (lookup failed / not stackable).
local stackSizeCache = {};

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
--
-- Allocation-free single-pass scan: avoids the per-call words = {} + table.insert
-- pattern that previously ran per slot per frame on abbreviation-rendering slots.
local function GetActionAbbreviation(bind)
    if not bind then return '?'; end
    local name = bind.displayName or bind.action or '';
    if name == '' then return '?'; end

    -- Short enough -> just upper-case it
    if #name <= 4 then
        return name:upper();
    end

    -- Walk the string once, grabbing the first letter of up to 4 whitespace-separated
    -- words. If only one word is found, fall through to the prefix path.
    local letters = '';
    local wordCount = 0;
    local inWord = false;
    for i = 1, #name do
        local c = name:sub(i, i);
        if c == ' ' or c == '\t' then
            inWord = false;
        else
            if not inWord then
                wordCount = wordCount + 1;
                if wordCount > 4 then break; end
                letters = letters .. c:upper();
                inWord = true;
            end
        end
    end

    if wordCount > 1 then
        return letters;
    end
    -- Single word: take first 4 characters
    return name:sub(1, 4):upper();
end

-- Exposed helper: compute abbreviation + its measured width for a bind.
-- Display/crossbar call this once per bind change and stash the result on
-- their icon-cache entry so DrawSlot doesn't recompute or re-measure per frame.
-- Caller must have already configured imtext (font_settings) for this frame.
function M.ComputeAbbreviation(bind)
    local abbr = GetActionAbbreviation(bind);
    local w = imtext.Measure(abbr, 12);
    return abbr, w;
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

-- Get the stack size of an item (max items per stack).
-- Returns nil if the item isn't stackable (StackSize <= 1) or can't be resolved.
function M.GetItemStackSize(itemId)
    if not itemId then return nil; end
    local cached = stackSizeCache[itemId];
    if cached ~= nil then
        return cached or nil;  -- false sentinel -> nil
    end

    local resMgr = AshitaCore:GetResourceManager();
    if not resMgr then return nil; end
    local itemRes = resMgr:GetItemById(itemId);
    local stackSize = itemRes and itemRes.StackSize;
    if stackSize and stackSize > 1 then
        stackSizeCache[itemId] = stackSize;
        return stackSize;
    end
    stackSizeCache[itemId] = false;
    return nil;
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
-- (Creating tables per-slot per-frame causes ~7200 allocations/sec)
-- Reusable result table for M.DrawSlot. `command` is the resolved command string for the
-- slot's bind (so callers can dispatch on click without re-calling actions.BuildCommandString
-- per click); nil for empty / unbindable slots.
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

-- Clear all cached state
function M.ClearAllCache()
    availabilityCache = {};
    availabilityCacheSize = 0;
    mpCostCache = {};
    mpCostCacheSize = 0;
    equipmentCheckCache = {};
    ninjutsuCache = {};
    itemQuantityCache = {};
    stackSizeCache = {};
    ammoStatusCache = {};
    -- texturePtrCache holds the SOLE Lua ref to D3D textures loaded via LoadTextureFromPath
    -- (the underlying entries have a d3d8.gc_safe_release finalizer). Dropping the table
    -- mid-frame would let Lua GC release the COM texture while AddImage calls for it are
    -- still queued in this frame's draw list — that's the same EXCEPTION_ACCESS_VIOLATION
    -- pattern that TextureManager.deferRelease guards against. Hand the table off to
    -- TextureManager.DeferRelease so it stays alive until FlushPendingReleases runs at the
    -- top of next d3d_present.
    TextureManager.DeferRelease(texturePtrCache);
    texturePtrCache = {};
end

-- Clear slot texture pointer cache
-- Does NOT clear availability, MP cost, or item quantity caches
-- OPTIMIZED: Use this for palette changes to avoid unnecessary recalculation cascade
function M.ClearSlotRenderingCache()
    -- See M.ClearAllCache for rationale; same mid-frame texture-release race applies here.
    TextureManager.DeferRelease(texturePtrCache);
    texturePtrCache = {};
end

-- Clear availability cache (call on job change, level sync, etc.)
function M.ClearAvailabilityCache()
    availabilityCache = {};
    availabilityCacheSize = 0;
end

-- Clear MP cost cache (call when a slot's action/spell may have changed, e.g. macro edits).
-- Without this, edited macros keep showing the old action's MP cost / no-MP indicator
-- until the addon reloads.
function M.ClearMPCostCache()
    mpCostCache = {};
    mpCostCacheSize = 0;
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

local cachedSlotTexPath = nil;
local function GetSlotTexPath()
    if not cachedSlotTexPath then
        cachedSlotTexPath = GetAssetsPath() .. 'slot.png';
    end
    return cachedSlotTexPath;
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

-- ============================================
-- ARGB color helpers (XIUI palette uses 0xAARRGGBB; ImGui AddText/AddRect take GetColorU32{r,g,b,a}).
-- ScaleArgbOpacity / DimArgbColor / LerpArgbTowardWhite are slotrenderer-specific tone-mapping
-- ops and live here; the basic ARGB<->ImGui U32 conversion is delegated to libs/color.lua.
-- ============================================

local ArgbToImguiU32 = colorlib.ARGBToU32;

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

-- ============================================
-- Universal Two-Hour (UTH) visual effects: rainbow marching border + subtarget ring glow.
-- Triggered when an action is the "armed" universal 2hr ability awaiting <stpc>/<stnpc> confirmation.
-- All pure ImGui drawList ops; no font or persistent-primitive dependencies.
-- ============================================

-- HSV (h in [0,1)) -> RGB used by the rainbow color cycling for UTH.
-- Thin wrapper over libs/color.lua's shared hsvToRgb so the UTH animation always
-- stays in sync with whatever color math the rest of the addon uses.
local function UthHsvToRgb(h, s, v)
    h = math.fmod(h, 1.0);
    if h < 0 then h = h + 1.0; end
    return colorlib.hsvToRgb(h, s, v);
end

-- Skillchain-style marching dashed rect; rainbow hue shifts with animation offset + time.
local function DrawUniversalTwoHourRainbowMarchingBorder(drawList, x1, y1, x2, y2, opacityMul)
    if not drawList or opacityMul <= 0.01 then return; end
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

-- Rainbow rotating rings while Universal 2 Hour waits on <stpc>/<stnpc> confirmation.
-- Ring radii breathe (collapse / expand); dashed border stays on the slot edge.
-- Opacity uses animOpacity * dimFactor * armFadeScale.
local function DrawUniversalTwoHourSubtargetGlow(drawList, x, y, size, animOpacity, dimFactor, armFadeScale)
    if not drawList or animOpacity <= 0.01 then return; end
    armFadeScale = armFadeScale or 1.0;
    if armFadeScale <= 0.01 then return; end
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

-- Draw skillchain highlight on a slot (animated dashed border + icon)
-- @param drawList: ImGui draw list (foreground recommended)
-- @param x, y: Top-left corner of slot
-- @param size: Slot size in pixels
-- @param scName: Skillchain name (e.g., 'Light', 'Darkness', 'Fusion')
-- @param color: Highlight color (ARGB)
-- @param opacity: Overall opacity (0-1)
-- @param iconScaleOverride, iconOxOverride, iconOyOverride: optional per-call overrides
--        (used by the macro palette editor to push the skillchain icon out of the corner
--        when it would otherwise overlap an action-label or BST-Ready badge).
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

    -- Draw skillchain icon in top-right corner. Per-call overrides take precedence over the
    -- global config (used by the macro palette editor to relocate the icon out of corners
    -- that the editor uses for action labels or BST-Ready badges).
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

-- Draw a Magic Burst highlight on a spell slot. Mirrors DrawSkillchainHighlight (dashed
-- border + SC-name icon corner badge) so the two highlights read as a visual family, with
-- two intentional differences:
--   * Color is sourced from `color` (cyan-blue default), distinct from the gold skillchain
--     border, so a glance tells the player which window is open.
--   * Icon is placed in the BOTTOM-LEFT corner instead of top-right. Spells almost never
--     have a charges-quantity badge to collide with there, and it keeps the corner-budget
--     separate from MP cost (top-left), skillchain icon (top-right), and stack quantity
--     (bottom-right). On the rare slot where MB and skillchain are both eligible (a /ws
--     macro that also matches a /ma element via macroparse picking the wrong primary,
--     etc.), both icons remain visible.
-- @param drawList   ImGui draw list (window or foreground)
-- @param x, y       Top-left of slot
-- @param size       Slot size in pixels
-- @param scName     Skillchain name driving the icon (e.g. 'Fusion', 'Light') — same asset
--                   pool as DrawSkillchainHighlight (assets/hotbar/skillchain/<name>.png).
-- @param color      Border color in ARGB (0xAARRGGBB)
-- @param opacity    Render opacity (0-1)
-- @param iconScaleOverride, iconOxOverride, iconOyOverride: optional per-call overrides
--                   (mirrors DrawSkillchainHighlight's editor-corner-pushing hooks).
local function DrawMagicBurstHighlight(drawList, x, y, size, scName, color, opacity, iconScaleOverride, iconOxOverride, iconOyOverride)
    if not drawList or not scName or opacity <= 0.01 then return; end

    local animOffset = skillchain.GetAnimationOffset();

    -- Decompose ARGB. Same shape as DrawSkillchainHighlight so any future migration to a
    -- shared helper is a single refactor (not duplicated unpack logic).
    local a = math.floor(bit.rshift(bit.band(color, 0xFF000000), 24) * opacity);
    local r = bit.rshift(bit.band(color, 0x00FF0000), 16) / 255;
    local g = bit.rshift(bit.band(color, 0x0000FF00), 8) / 255;
    local b = bit.band(color, 0x000000FF) / 255;
    local lineColor = imgui.GetColorU32({ r, g, b, a / 255 });

    local dashLen = 4;
    local gapLen = 4;
    local thickness = 2;

    -- Phase-shift the marching ants by half a dash so the MB pattern doesn't look identical
    -- to the skillchain pattern when (in some future build) both fire on the same slot.
    local mbAnimOffset = (animOffset + (dashLen + gapLen) * 0.5) % (dashLen + gapLen);

    DrawDashedLine(drawList, x, y, x + size, y, lineColor, thickness, dashLen, gapLen, mbAnimOffset);
    DrawDashedLine(drawList, x + size, y, x + size, y + size, lineColor, thickness, dashLen, gapLen, mbAnimOffset);
    DrawDashedLine(drawList, x + size, y + size, x, y + size, lineColor, thickness, dashLen, gapLen, mbAnimOffset);
    DrawDashedLine(drawList, x, y + size, x, y, lineColor, thickness, dashLen, gapLen, mbAnimOffset);

    -- Bottom-left icon corner. Reuses the skillchainIcon{Scale|OffsetX|OffsetY} global settings
    -- so users who already tuned their SC icon size don't have to redo it; the offsets are
    -- applied relative to the BOTTOM-LEFT anchor (not top-right) so positive Y still means
    -- "shift down" and positive X still means "shift right" intuitively from the corner.
    local scale = iconScaleOverride or gConfig.hotbarGlobal.skillchainIconScale or 1.0;
    local iconSize = math.floor(size * 0.35 * scale);
    local offsetX = iconOxOverride or gConfig.hotbarGlobal.skillchainIconOffsetX or 0;
    local offsetY = iconOyOverride or gConfig.hotbarGlobal.skillchainIconOffsetY or 0;
    local iconX = x + 2 + offsetX;
    local iconY = y + size - iconSize - 2 + offsetY;

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
                { iconX, iconY },
                { iconX + iconSize, iconY + iconSize },
                { 0, 0 }, { 1, 1 },
                iconTint
            );
        end
    end
end

-- Helper: determine if movement/drag-drop is locked for this slot
-- Shift key overrides the lock to allow dragging while locked.
-- Hotbar slots use hotbarLockMovement; crossbar slots use crossbarLockMovement;
-- palette editor slots ('paled*' drop zones) are never locked so users can edit them.
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

-- ============================================
-- Editor label helpers (Ferris's "Edit Full Palette" view).
-- Crossbar editor passes `labelForeground = true` + `editorMinimalView = true` so the action
-- name renders on the slot via ImGui drawList (not via the GDI labelFont). When the editor
-- view is OFF but `labelForeground` is on, labels render above/below the slot with a soft wrap.
-- ============================================

local function SplitNewlinesEditor(s)
    if not s or s == '' then return {}; end
    local t = {};
    local startPos = 1;
    local len = #s;
    while startPos <= len do
        local nl = s:find('\n', startPos, true);
        if not nl then
            t[#t + 1] = s:sub(startPos);
            break;
        end
        t[#t + 1] = s:sub(startPos, nl - 1);
        startPos = nl + 1;
    end
    return t;
end

-- Idle abbreviation for Edit Full Palette: first 4 non-whitespace chars of the trimmed name.
-- Full text is shown when the user hovers the slot; the abbreviation lets even cramped 32px
-- slots show *something* recognisable while editing the palette.
local function EditorIdleAbbrev4(fullName)
    if not fullName or fullName == '' then return ''; end
    local t = fullName:gsub('^%s+', ''):gsub('%s+$', '');
    if t == '' then return ''; end
    if #t <= 4 then return t; end
    return t:sub(1, 4);
end

-- Wrap rule for editor labels: at most one newline, with the line closest to the slot holding
-- a single word so the slot stays visually attached to its label.
-- labelAboveSlot=true  → "A B C D" -> "A B C\nD"  (last word lands beside the slot)
-- labelAboveSlot=false → "A B C D" -> "A\nB C D"  (first word lands beside the slot)
local function EditorLabelWrapNearSlot(text, labelAboveSlot)
    if not text or text == '' then return text; end
    local t = text:gsub('^%s+', ''):gsub('%s+$', '');
    if not t:find('%s') then return t; end
    local words = {};
    for w in t:gmatch('%S+') do words[#words + 1] = w; end
    if #words < 2 then return t; end
    if labelAboveSlot then
        local last = table.remove(words);
        return table.concat(words, ' ') .. '\n' .. last;
    end
    local first = table.remove(words, 1);
    return first .. '\n' .. table.concat(words, ' ');
end

-- Pixel-snap centre X so adjacent slots' labels line up vertically (fonts at fractional X
-- jitter visibly when neighbours sit at integer positions).
local function EditorLabelCenterX(cx, line, fontSize)
    local w = imtext.Measure(line, fontSize);
    return math.floor(cx - w * 0.5 + 0.5);
end

-- Multi-line outlined label centred on slot (editorMinimalView). One imtext.Draw call per line
-- (which already includes the 4-cardinal outline) — matches Ferris's "thin outline only, no
-- scrim or halo" style so wrapped lines don't stack thick shadows on each other.
local function DrawEditorMultilineCenteredOnSlot(drawList, slotX, slotY, slotSize, argbColor, multilineText, fontSize)
    if not drawList or not multilineText or multilineText == '' or not slotSize or slotSize <= 0 then return; end
    local raw = SplitNewlinesEditor(multilineText);
    local lines = {};
    for i = 1, #raw do
        if raw[i] ~= '' then lines[#lines + 1] = raw[i]; end
    end
    if #lines == 0 then return; end
    local _, lineH = imtext.Measure('Mg', fontSize);
    local lineStep = (lineH and lineH > 0) and (lineH + 1) or (fontSize + 2);
    local cx = slotX + slotSize * 0.5;
    local cy = slotY + slotSize * 0.5;
    local totalH = #lines * lineStep;
    local topY = math.floor(cy - totalH * 0.5 + 0.5);
    for i = 1, #lines do
        local px = EditorLabelCenterX(cx, lines[i], fontSize);
        imtext.Draw(drawList, lines[i], px, topY, argbColor, fontSize);
        topY = topY + lineStep;
    end
end

-- Multi-line outlined label centred above/below the slot (non-minimal editor view).
local function DrawEditorMultilineCenteredAtY(drawList, cx, topY, argbColor, multilineText, fontSize)
    if not drawList or not multilineText or multilineText == '' then return; end
    local lines = SplitNewlinesEditor(multilineText);
    local _, lineH = imtext.Measure('Mg', fontSize);
    local lineStep = (lineH and lineH > 0) and (lineH + 1) or (fontSize + 2);
    local py = math.floor(topY + 0.5);
    for i = 1, #lines do
        local line = lines[i];
        if line ~= '' then
            local px = EditorLabelCenterX(cx, line, fontSize);
            imtext.Draw(drawList, line, px, py, argbColor, fontSize);
        end
        py = py + lineStep;
    end
end

--[[
    Render a slot with all components and handle all interactions.
    All rendering uses ImGui draw lists (AddImage for textures, imtext for text).
    MUST be called inside an ImGui window context for interactions to work.

    @param params: Rendering and interaction parameters (position, bind, icon, visual settings, callbacks)
        Edit Full Palette extras (set by crossbar editor only):
        - editorClipRect: { minX, minY, maxX, maxY } — slot is hidden when fully outside the rect.
        - editorStrictContain: bool — when true, ALL of the slot (incl. label) must be inside the rect.
        - labelForeground: bool — draw the action name via ImGui drawList instead of any GDI font path.
        - editorMinimalView: bool — draw the label centred on the slot (idle abbreviation, full on hover).
        - labelAboveSlot: bool — place label above the slot rather than below.
    @return table: { isHovered, command } (reused - read values immediately, do NOT cache)
]]--
function M.DrawSlot(params)
    local x = params.x;
    local y = params.y;
    local size = params.size;
    local bind = params.bind;
    local icon = params.icon;
    local slotBgColor = params.slotBgColor or 0xFFFFFFFF;
    local dimFactor = params.dimFactor or 1.0;
    local animOpacity = params.animOpacity or 1.0;
    local isPressed = params.isPressed or false;

    -- Crossbar: use the current window draw list so MP/timer/hover overlays stack with other
    -- ImGui windows (GetForegroundDrawList always paints above every window, which can cover
    -- modal dialogs). Hotbar and editors keep the shared UI draw list. The selector returns
    -- the appropriate drawList for overlays drawn on top of the slot icon.
    local function slotOverlayDrawList()
        if params.windowName == 'Crossbar' then
            local wdl = imgui.GetWindowDrawList();
            if wdl then return wdl; end
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
        return result;
    end

    -- Editor clip rect culling: when the crossbar's Edit Full Palette window scrolls, slots
    -- can land outside the visible region. With all rendering on ImGui draw lists the parent
    -- window's clip rect already culls drawing, but the slot still pays for per-frame state
    -- checks (recast, MP, availability, hover, drag) and emits ImGui draw commands that get
    -- discarded later. Short-circuiting here turns ~120 slots * (full pipeline) into a single
    -- 4-comparison reject for off-screen rows.
    local minimalEditorView = params.editorMinimalView == true;
    do
        local clip = params.editorClipRect;
        if clip and clip[1] and clip[2] and clip[3] and clip[4] then
            local fs = params.labelFontSize or 10;
            local padTop, padBot = 4, 4;
            if params.showLabel and params.labelText and params.labelText ~= '' then
                if not minimalEditorView then
                    local extraLinePad = 0;
                    if params.labelText:find('%s') then
                        extraLinePad = math.floor(fs * 1.05 + 0.5);
                    end
                    if params.labelAboveSlot then
                        padTop = fs + 14 + extraLinePad;
                    else
                        padBot = fs + 14 + extraLinePad;
                    end
                end
                -- editorMinimalView labels render on the slot itself, no extra pad needed.
            end
            local sx1 = x;
            local sy1 = y - padTop;
            local sx2 = x + size;
            local sy2 = y + size + padBot;
            if params.editorStrictContain then
                if sx1 < clip[1] or sy1 < clip[2] or sx2 > clip[3] or sy2 > clip[4] then
                    return result;
                end
            else
                if sx2 < clip[1] or sx1 > clip[3] or sy2 < clip[2] or sy1 > clip[4] then
                    return result;
                end
            end
        end
    end

    -- Check hover state
    local mouseX, mouseY = imgui.GetMousePos();
    local isHovered = mouseX >= x and mouseX <= x + size and
                      mouseY >= y and mouseY <= y + size;
    result.isHovered = isHovered;

    -- ========================================
    -- 1. Slot Background (ImGui AddImage)
    -- ========================================
    -- For Crossbar windows we draw to the window draw list so all of the slot's
    -- visual layers (background -> icon -> text -> hover) stack within the window's
    -- z-order; the shared UI draw list lands ABOVE every ImGui window which can
    -- cover modals and tooltips.
    local drawList = slotOverlayDrawList();
    do
        local slotTexPtr = GetCachedTexturePtr(GetSlotTexPath());
        if slotTexPtr and drawList then
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

            -- Apply slot opacity setting (before animation opacity)
            local slotOpacity = params.slotOpacity or 1.0;
            if slotOpacity < 1.0 then
                local a = math.floor(bit.rshift(bit.band(finalColor, 0xFF000000), 24) * slotOpacity);
                finalColor = bit.bor(bit.lshift(a, 24), bit.band(finalColor, 0x00FFFFFF));
            end

            -- Apply animation opacity to alpha channel
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

    -- Check if player has enough MP for spells (also includes macros whose
    -- recast source is a spell — they show the source spell's MP cost).
    local notEnoughMp = false;
    local bindKey = bind and ((bind.actionType or '') .. ':' .. (bind.action or '')) or '';
    local hasMpCost = bind and (
        bind.actionType == 'ma'
        or (bind.actionType == 'macro' and bind.recastSourceType == 'ma' and bind.recastSourceAction)
    );
    if hasMpCost then
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

    -- Check if action is available (job/level requirements). Allowlist covers magic ('ma'),
    -- job abilities ('ja'), weapon skills ('ws'), pet pacts ('pet'), and macros — macros are
    -- validated against their resolved primary line (and optional /ja badge) so a macro that
    -- /pet's a not-yet-learned blood pact reads as unavailable too.
    local isUnavailable = false;
    local unavailableReason = nil;
    local unavailDisplayText = nil;  -- pre-parsed 'Lv65' / 'X' string (computed at insert time)
    if bind and (
            bind.actionType == 'ma'
            or bind.actionType == 'ja'
            or bind.actionType == 'ws'
            or bind.actionType == 'pet'
            or bind.actionType == 'macro') then
        local fa = GetFrameAvailability();
        local availKey = bindKey .. ':' .. fa.jobId .. ':' .. fa.subjobId .. ':'
            .. fa.mainLevel .. ':' .. fa.subLevel .. ':' .. fa.partyMain .. ':' .. fa.partySub;

        local cached = availabilityCache[availKey];
        if cached == nil then
            local available, reason = actions.IsActionAvailable(bind);
            -- Don't cache if reason is "pending" (player state invalid, e.g., during zoning)
            if reason ~= "pending" then
                -- Pre-parse the display text once at insert time so the MP-cost render path
                -- doesn't call string.match every frame for every unavailable slot.
                local dispText = 'X';
                if reason then
                    local lv = reason:match('^Lv(%d+)$');
                    if lv then
                        dispText = 'Lv' .. lv;
                    else
                        local legacyLvl = reason:match('^Lvl%.(%d+)$');
                        if legacyLvl then
                            dispText = 'Lv' .. legacyLvl;
                        end
                    end
                end
                local entry = { isAvailable = available, reason = reason, displayText = dispText };
                PutAvailabilityCache(availKey, entry);
                cached = entry;
            else
                -- Use temp result but don't cache
                cached = { isAvailable = available, reason = nil, displayText = 'X' };
            end
        end
        isUnavailable = not cached.isAvailable;
        unavailableReason = cached.reason;
        unavailDisplayText = cached.displayText;
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

            -- Calculate scale to fit icon within slot with padding
            local scale = targetIconSize / math.max(texWidth, texHeight);
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
                applyGreyTint = true;  -- Apply grey/desaturated tint
            elseif isOnCooldown then
                colorMult = 0.4;
            elseif notEnoughMp then
                colorMult = 0.6;  -- Slightly dimmed when not enough MP
            end
            colorMult = colorMult * dimFactor;

            -- Calculate RGB values
            local r, g, b;
            -- Grey tint for unavailable actions (desaturated)
            if applyGreyTint then
                local grey = math.floor(180 * colorMult);  -- Lighter grey base
                r, g, b = grey, grey, grey;
            else
                local rgb = math.floor(255 * colorMult);
                r, g, b = rgb, rgb, rgb;
            end

            local alpha = math.floor(255 * animOpacity * (isUnavailable and 0.7 or 1.0));  -- Lower opacity when unavailable
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
        -- Use precomputed values from the caller's icon cache when provided
        -- (avoids GetActionAbbreviation table walk and imtext.Measure per slot per frame).
        -- Fall back to computing on demand for callers that don't pre-cache.
        local abbr = params.cachedAbbr;
        local abbrW = params.cachedAbbrW;
        if not abbr then
            abbr = GetActionAbbreviation(bind);
            abbrW = imtext.Measure(abbr, 12);
        end

        local colorMult = 1.0;
        if isUnavailable then colorMult = 0.35;
        elseif notEnoughMp then colorMult = 0.6; end
        colorMult = colorMult * dimFactor;
        -- Gold base: R=244, G=218, B=151 (0xF4DA97)
        local r = math.floor(244 * colorMult);
        local g = math.floor(218 * colorMult);
        local b = math.floor(151 * colorMult);
        local a = math.floor(animOpacity * 255);
        local abbrColor = bit.bor(bit.lshift(a, 24), bit.lshift(r, 16), bit.lshift(g, 8), b);
        -- Center position
        local abbrX = x + (size - abbrW) / 2;
        local abbrY = y + size / 2 - 6;
        imtext.DrawShadow(drawList, abbr, abbrX, abbrY, abbrColor, 12);
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
        imtext.DrawShadow(drawList, recastText, timerX, timerY, timerColor, timerFontSize);
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
        imtext.Draw(drawList, params.keybindText, kbX, kbY, kbColor, kbFontSize);
    end

    -- ========================================
    -- 9. Label Text (action name)
    -- Three modes:
    --   (a) Standard hotbar/crossbar: single line below the slot (default).
    --   (b) labelForeground + editorMinimalView: multi-line centred ON the slot
    --       (Edit Full Palette idle view — 4-char abbrev, full text shown via hover tooltip).
    --   (c) labelForeground (non-minimal): multi-line centred above/below the slot
    --       with EditorLabelWrapNearSlot soft-wrap putting one word beside the slot.
    -- ========================================
    if params.showLabel and params.labelText and params.labelText ~= '' and animOpacity > 0.5 and drawList then
        local lblFontSize = params.labelFontSize or 10;
        local labelColor = params.labelFontColor or 0xFFFFFFFF;
        -- Priority: Unavailable (grey) > Cooldown (grey) > Not enough MP (red) > Normal
        if isUnavailable then
            labelColor = 0xFF888888;
        elseif isOnCooldown then
            labelColor = params.labelCooldownColor or 0xFF888888;
        elseif notEnoughMp then
            labelColor = params.labelNoMpColor or 0xFFFF4444;
        end

        -- Apply animation opacity into the label color (label paths below don't otherwise modulate alpha).
        if animOpacity < 1.0 then
            local a = math.floor(bit.rshift(bit.band(labelColor, 0xFF000000), 24) * animOpacity);
            if a < 0 then a = 0; elseif a > 255 then a = 255; end
            labelColor = bit.bor(bit.lshift(a, 24), bit.band(labelColor, 0x00FFFFFF));
        end

        if params.labelForeground then
            if minimalEditorView then
                -- (b) On-slot view: 4-char abbrev when idle, full name on hover. Multi-line if hover label wraps.
                local textForDraw = isHovered and params.labelText or EditorIdleAbbrev4(params.labelText);
                if textForDraw and textForDraw ~= '' then
                    DrawEditorMultilineCenteredOnSlot(drawList, x, y, size, labelColor, textForDraw, lblFontSize);
                end
            else
                -- (c) Above/below-slot view with soft wrap so one word lands beside the slot.
                local wrapped = EditorLabelWrapNearSlot(params.labelText, params.labelAboveSlot);
                local cx = x + size * 0.5 + (params.labelOffsetX or 0);
                local lineCount = 1;
                if wrapped and wrapped:find('\n') then lineCount = 2; end
                local _, lineH = imtext.Measure('Mg', lblFontSize);
                local lineStep = (lineH and lineH > 0) and (lineH + 1) or (lblFontSize + 2);
                local topY;
                if params.labelAboveSlot then
                    topY = y - 2 - lineStep * lineCount + (params.labelOffsetY or 0);
                else
                    topY = y + size + 2 + (params.labelOffsetY or 0);
                end
                DrawEditorMultilineCenteredAtY(drawList, cx, topY, labelColor, wrapped, lblFontSize);
            end
        else
            -- (a) Default single-line render. Honors params.labelAboveSlot so the crossbar's
            -- top diamond slot can flip its label above (otherwise the bottom slot's MP/qty
            -- text overlaps the top slot's label). Keyboard hotbars always pass false → below.
            local lblW = imtext.Measure(params.labelText, lblFontSize);
            local labelX = x + (size - lblW) / 2 + (params.labelOffsetX or 0);
            local labelY;
            if params.labelAboveSlot then
                local _, lblH = imtext.Measure('Mg', lblFontSize);
                local h = (lblH and lblH > 0) and lblH or lblFontSize;
                labelY = y - 2 - h + (params.labelOffsetY or 0);
            else
                labelY = y + size + 2 + (params.labelOffsetY or 0);
            end
            imtext.Draw(drawList, params.labelText, labelX, labelY, labelColor, lblFontSize);
        end
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

            -- If action is unavailable, render either a level requirement ("Lv65") when
            -- IsActionAvailable returned an Lv-style reason, or a plain "X" for non-level
            -- failures (e.g. weaponskills not learned, wrong job, missing scroll). The
            -- display text was pre-parsed by the availability cache insert above, so this
            -- hot-path branch just reads the field — no per-frame string.match here.
            if isUnavailable then
                local unavailText = unavailDisplayText or 'X';
                local xColor = 0xFFFF4444;
                if mpAnchor == 'topRight' or mpAnchor == 'bottomRight' then
                    local w = imtext.Measure(unavailText, mpFontSize);
                    mpX = mpX - w;
                end
                imtext.Draw(drawList, unavailText, mpX, mpY, xColor, mpFontSize);
            else
                local mpCost = mpCostCache[bindKey];
                if mpCost == nil then
                    mpCost = actions.GetMPCost(bind) or false;
                    PutMpCostCache(bindKey, mpCost);
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
                    imtext.Draw(drawList, mpText, mpX, mpY, mpCostColor, mpFontSize);
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
                -- Skip quantity display for equipment items (armor, weapons, accessories)
                local isEquipment = bind.itemId and IsEquipmentItem(bind.itemId) or nil;
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

        if shouldShowQty and quantity ~= nil and drawList then
            local qtyText = 'x' .. tostring(quantity);
            local qtyFontSize = params.quantityFontSize or 10;
            local qtyColor = quantity == 0 and 0xFFFF4444 or (params.quantityFontColor or 0xFFFFFFFF);
            local qtyAnchor = params.quantityAnchor or 'bottomRight';
            local isRight = (qtyAnchor == 'topRight' or qtyAnchor == 'bottomRight');
            local isTop = (qtyAnchor == 'topLeft' or qtyAnchor == 'topRight');
            local qtyX, qtyY = GetAnchoredPosition(x, y, size, qtyAnchor, params.quantityOffsetX, params.quantityOffsetY);
            local qtyW = imtext.Measure(qtyText, qtyFontSize);
            if isRight then qtyX = qtyX - qtyW; end
            imtext.Draw(drawList, qtyText, qtyX, qtyY, qtyColor, qtyFontSize);

            -- Optional: full-stack count, drawn just above (or below for top
            -- anchors) the quantity text. Only shown for stackable items
            -- with at least one full stack; ninjutsu tools are excluded.
            if params.showStackQuantity and bind.actionType == 'item' and bind.itemId then
                local stackSize = M.GetItemStackSize(bind.itemId);
                local stacks = stackSize and math.floor(quantity / stackSize) or 0;
                if stacks > 0 then
                    local stackText = '(' .. stacks .. ')';
                    local stackY = isTop and (qtyY + qtyFontSize + 1) or (qtyY - qtyFontSize - 1);
                    local stackX = isRight
                        and (qtyX + qtyW - imtext.Measure(stackText, qtyFontSize))
                        or qtyX;
                    imtext.Draw(drawList, stackText, stackX, stackY, qtyColor, qtyFontSize);
                end
            end
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
        -- Pressed effect - red if on cooldown, white otherwise
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
        -- Hover effect (mouse)
        elseif isHovered and not dragdrop.IsDragging() then
            local hoverTintColor = imgui.GetColorU32({1.0, 1.0, 1.0, 0.15 * animOpacity});
            local hoverBorderColor = imgui.GetColorU32({1.0, 1.0, 1.0, 0.10 * animOpacity});
            drawList:AddRectFilled({x, y}, {x + size, y + size}, hoverTintColor, 2);
            drawList:AddRect({x, y}, {x + size, y + size}, hoverBorderColor, 2, 0, 1);
        end

        -- Skillchain highlight (animated dotted border + icon)
        if params.skillchainName then
            local scColor = params.skillchainColor or 0xFFD4AA44;
            -- Per-call icon scale/offset overrides used by the macro palette editor
            -- to push the skillchain icon out of corner badges. Falls back to
            -- gConfig.hotbarGlobal.skillchainIcon* when not provided.
            DrawSkillchainHighlight(drawList, x, y, size, params.skillchainName, scColor, animOpacity,
                params.skillchainIconScale, params.skillchainIconOffsetX, params.skillchainIconOffsetY);
        end

        -- Magic Burst highlight (animated dotted border + SC-name icon in BOTTOM-LEFT corner).
        -- Renders independently from the skillchain highlight: a slot can legitimately have
        -- ONE of them active at a time (WS slots → skillchain prediction, spell slots → MB).
        -- Drawing this AFTER the skillchain pass means if both ever fire on the same slot
        -- (rare — primary-parse path would have to disagree), the MB border ends up on top.
        if params.magicBurstName then
            local mbColor = params.magicBurstColor or 0xFF44D4FF;
            DrawMagicBurstHighlight(drawList, x, y, size, params.magicBurstName, mbColor, animOpacity,
                params.skillchainIconScale, params.skillchainIconOffsetX, params.skillchainIconOffsetY);
        end

        -- Universal Two-Hour: rainbow rotating rings + marching border while the user is
        -- confirming <stpc>/<stnpc> (or briefly after click during the arming-shimmer
        -- fade window). universal_two_hour module decides whether this slot is the armed
        -- ability; if the module isn't loaded (1.7.5 fork) the check is a silent no-op.
        if bind and not isOnCooldown and universalTwoHour and universalTwoHour.ShouldGlowUniversalTwoHourSlot
            and universalTwoHour.ShouldGlowUniversalTwoHourSlot(bind) then
            local armScale = universalTwoHour.GetArmingShimmerOpacityScale
                and universalTwoHour.GetArmingShimmerOpacityScale() or 1.0;
            DrawUniversalTwoHourSubtargetGlow(drawList, x, y, size, animOpacity, dimFactor, armScale);
        end
    end

    -- ========================================
    -- 14. Drop Zone Registration
    -- ========================================
    if params.dropZoneId and params.onDrop and not IsMovementLockedForDropZone(params.dropZoneId) then
        dragdrop.DropZone(params.dropZoneId, x, y, size, size, {
            accepts = params.dropAccepts or {'macro'},
            highlightColor = params.dropHighlightColor or 0xA8FFFFFF,
            -- dropPriority is the tie-break for overlapping zones (e.g. Edit Full Palette preview
            -- overlay on top of a live crossbar slot); the higher number wins via FlushDeferredDrops.
            -- Default is nil so the existing first-registered-wins behavior is preserved.
            dropPriority = params.dropPriority,
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

        -- Left click / double-click. Edit Full Palette slots set `suppressActionOnClick`:
        -- a single click on those is meaningless (no live action to fire — the slot is a
        -- draft preview), but we still need to track the click to detect double-click and
        -- open the macro editor. `params.suppressActionOnClick` also tells us to ignore a
        -- cancelled-micro-drag attempt (without this, even a tiny mouse jitter between
        -- press and release blocks the double-click pipeline).
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
                    -- Treat as the first half of a potential double-click and do nothing
                    -- else. Editor slots intentionally don't fire any action on single click.
                    lastClickButtonId = params.buttonId;
                    lastClickTime = now;
                elseif params.onClick then
                    params.onClick();
                elseif bind then
                    local cmd = actions.BuildCommand(bind);
                    if cmd then
                        actions.ExecuteCommandString(cmd, bind.actionType == 'macro');
                    end
                end
            end
        end

        -- Right click (disabled when the slot's Lock Movement is enabled). Uses the same
        -- per-zone lock policy as drop zones so the Hotbar lock doesn't accidentally disable
        -- right-click-to-clear on crossbar slots (and vice versa).
        if isItemHovered and imgui.IsMouseClicked(1) and bind then
            if params.onRightClick and not IsMovementLockedForDropZone(params.dropZoneId) then
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

    -- Helper to format target (strips existing brackets, adds fresh ones)
    local function formatTarget(target)
        if not target then return nil; end
        local cleaned = target:gsub('[<>]', '');
        if cleaned == '' then return nil; end
        return '<' .. cleaned .. '>';
    end

    -- Check if action is unavailable for current job/subjob (cached lookup). Cache key
    -- shape MUST match the one DrawSlot uses or we'd get spurious cache misses every time
    -- the tooltip checks: same (action key, jobs, levels, party-effective levels). Routes
    -- through the same per-frame snapshot used by DrawSlot so we don't re-walk MM here.
    local isUnavailable = false;
    if bind.actionType == 'ma'
        or bind.actionType == 'ja'
        or bind.actionType == 'ws'
        or bind.actionType == 'pet'
        or bind.actionType == 'macro' then
        local bindKey = (bind.actionType or '') .. ':' .. (bind.action or '');
        local fa = GetFrameAvailability();
        local availKey = bindKey .. ':' .. fa.jobId .. ':' .. fa.subjobId .. ':'
            .. fa.mainLevel .. ':' .. fa.subLevel .. ':' .. fa.partyMain .. ':' .. fa.partySub;
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

    -- Ensure custom font is configured for measuring/drawing
    if tooltipFontSettings then
        imtext.SetConfigFromSettings(tooltipFontSettings);
    end

    local lines = {};
    local displayName = bind.displayName or bind.action or 'Unknown';
    lines[#lines+1] = { displayName, TOOLTIP_COL_GOLD };

    local typeLabel = ACTION_TYPE_LABELS[bind.actionType] or bind.actionType or '?';
    lines[#lines+1] = { 'Type: ' .. typeLabel, TOOLTIP_COL_DIM };

    if bind.actionType ~= 'macro' and bind.target and bind.target ~= '' then
        local ft = formatTarget(bind.target);
        if ft then lines[#lines+1] = { 'Target: ' .. ft, TOOLTIP_COL_DIM }; end
    end

    if bind.actionType == 'macro' and bind.macroText then
        lines[#lines+1] = { bind.macroText, TOOLTIP_COL_DIM };
    end

    if isUnavailable then
        lines[#lines+1] = { 'Action not available', TOOLTIP_COL_RED };
    end

    local padX, padY = 8, 6;
    local _, sampleH = imtext.Measure("Ag", TOOLTIP_FONT_SIZE);
    local lineH = sampleH + 2;
    local maxW = 0;
    for _, line in ipairs(lines) do
        local w = imtext.Measure(line[1], TOOLTIP_FONT_SIZE);
        if w > maxW then maxW = w; end
    end

    local tooltipW = maxW + padX * 2;
    local tooltipH = #lines * lineH + padY * 2;

    local mx, my = imgui.GetMousePos();
    local tx = mx + 16;
    local ty = my + 8;

    local fgList = imgui.GetForegroundDrawList();
    fgList:AddRectFilled({tx, ty}, {tx + tooltipW, ty + tooltipH}, TOOLTIP_COL_BG, 4);
    fgList:AddRect({tx, ty}, {tx + tooltipW, ty + tooltipH}, TOOLTIP_COL_BORDER, 4, 0, 1);

    local textY = ty + padY;
    for _, line in ipairs(lines) do
        imtext.DrawSimple(fgList, line[1], tx + padX, textY, line[2], TOOLTIP_FONT_SIZE);
        textY = textY + lineH;
    end
end


-- Call at the start of each frame to reset deferred tooltip state
function M.BeginFrame(fontSettings)
    pendingTooltipBind = nil;
    tooltipFontSettings = fontSettings;
    frameAvail.ready = false;
end

-- Size of the abbreviation "pick-up" tile that follows the cursor on icon-less drags.
-- Matches dragdrop's default icon size so the two drag visuals have the same weight.
local DRAG_ABBR_TILE_SIZE = 32;

-- Call after all hotbar/crossbar windows are done to render the tooltip on top.
-- Also renders the drag tooltip and (for drags with no icon) a mini "abbreviation
-- tile" at the cursor so the user has something to carry. Everything lands on the
-- foreground draw list, above the hotbar windows.
function M.FlushTooltip()
    if pendingTooltipBind then
        M.DrawTooltip(pendingTooltipBind);
        pendingTooltipBind = nil;
        return;
    end

    -- Hover tooltip is suppressed during drag (see DrawSlot's showTooltip gate),
    -- so we never render both in the same frame.
    if not dragdrop.IsDragging() then return; end

    local payload = dragdrop.GetPayload();
    if not (payload and payload.data and payload.data.actionType) then return; end

    -- When the drag payload has no icon, draw a slot-shaped tile with the
    -- abbreviation centered on it at the cursor. Mirrors the hotbar's own
    -- abbreviation slot look so it reads as "you picked up this slot."
    if not (payload.icon and payload.icon.image) then
        local fgList = imgui.GetForegroundDrawList();
        if fgList then
            local mx, my = imgui.GetMousePos();
            local tileX = mx - 4;
            local tileY = my - 4;

            local slotPtr = GetCachedTexturePtr(GetSlotTexPath());
            if slotPtr then
                imgP1[1] = tileX;                       imgP1[2] = tileY;
                imgP2[1] = tileX + DRAG_ABBR_TILE_SIZE; imgP2[2] = tileY + DRAG_ABBR_TILE_SIZE;
                fgList:AddImage(slotPtr, imgP1, imgP2, UV0, UV1, 0xFFFFFFFF);
            end

            local abbr = GetActionAbbreviation(payload.data);
            local abbrW = imtext.Measure(abbr, 12);
            local abbrX = tileX + (DRAG_ABBR_TILE_SIZE - abbrW) / 2;
            local abbrY = tileY + DRAG_ABBR_TILE_SIZE / 2 - 6;
            -- Gold matches the in-slot abbreviation color (R=244, G=218, B=151)
            imtext.Draw(fgList, abbr, abbrX, abbrY, 0xFFF4DA97, 12);
        end
    end

    M.DrawTooltip(payload.data);
end

return M;

