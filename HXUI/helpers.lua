require('common');
local imgui = require('imgui');
local fonts = require('fonts');
local ffi       = require('ffi');
local d3d       = require('d3d8');
local C         = ffi.C;
local d3d8dev   = d3d.get_device();
local statusHandler = require('statushandler');
local buffTable = require('bufftable');
local gdi = require('gdifonts.include');

debuffTable = T{};

-- ========================================
-- Font Weight Helper
-- ========================================
-- Converts fontWeight string setting to GDI font flags
function GetFontWeightFlags(fontWeight)
	if fontWeight == 'Bold' then
		return gdi.FontFlags.Bold;
	else
		return gdi.FontFlags.None;
	end
end

-- ========================================
-- Entity Spawn and Render Flag Constants
-- ========================================
-- Exported for use in other modules
SPAWN_FLAG_PLAYER = 0x0001;  -- Entity is a player character
SPAWN_FLAG_NPC = 0x0002;     -- Entity is an NPC
RENDER_FLAG_VISIBLE = 0x200;  -- Entity is visible and rendered
RENDER_FLAG_HIDDEN = 0x4000;  -- Entity is hidden (cutscene, menu, etc.)

-- ========================================
-- FontManager Helper
-- ========================================
-- Provides a centralized API for font lifecycle management
-- Eliminates code duplication across modules
FontManager = {
    -- Create a single font object
    create = function(settings)
        return gdi:create_object(settings);
    end,

    -- Destroy a font object safely
    destroy = function(fontObj)
        if fontObj ~= nil then
            gdi:destroy_object(fontObj);
        end
        return nil;
    end,

    -- Recreate a font with new settings
    recreate = function(fontObj, settings)
        if fontObj ~= nil then
            gdi:destroy_object(fontObj);
        end
        return gdi:create_object(settings);
    end,

    -- Batch create multiple fonts from settings table
    createBatch = function(fontSettingsTable)
        local fonts = {};
        for key, settings in pairs(fontSettingsTable) do
            fonts[key] = gdi:create_object(settings);
        end
        return fonts;
    end,

    -- Batch destroy multiple fonts
    destroyBatch = function(fontsTable)
        for key, fontObj in pairs(fontsTable) do
            if fontObj ~= nil then
                gdi:destroy_object(fontObj);
            end
        end
    end
};

-- ========================================
-- ColorCachedFont Wrapper
-- ========================================
-- Wraps a GDI font with automatic color caching for performance
-- Eliminates redundant set_font_color calls
ColorCachedFont = {
    new = function(fontObj)
        return {
            font = fontObj,
            lastColor = nil,

            -- Set color with automatic caching
            setColor = function(self, color)
                if self.lastColor ~= color then
                    self.font:set_font_color(color);
                    self.lastColor = color;
                end
            end,

            -- Proxy methods to underlying font
            set_text = function(self, text) self.font:set_text(text); end,
            set_visible = function(self, visible) self.font:set_visible(visible); end,
            set_position_x = function(self, x) self.font:set_position_x(x); end,
            set_position_y = function(self, y) self.font:set_position_y(y); end,
            set_font_height = function(self, height) self.font:set_font_height(height); end,
            get_text_size = function(self) return self.font:get_text_size(); end,
        }
    end
};

-- ========================================
-- Font Visibility Helper
-- ========================================
-- Set visibility for multiple fonts at once
function SetFontsVisible(fontTable, visible)
    for _, fontObj in pairs(fontTable) do
        if fontObj ~= nil then
            -- Support both regular GDI fonts and ColorCachedFont wrappers
            if fontObj.set_visible then
                fontObj:set_visible(visible);
            elseif fontObj.font and fontObj.font.set_visible then
                fontObj.font:set_visible(visible);
            end
        end
    end
end

-- ========================================
-- HP Interpolation Manager
-- ========================================
-- Manages HP bar damage/healing animations with smooth transitions
-- Used by targetbar, partylist, and other HP bar modules
HpInterpolation = {
    -- Storage for interpolation states, keyed by a unique identifier
    states = {},

    -- Create or get an interpolation state for a given key
    getState = function(key)
        if not HpInterpolation.states[key] then
            HpInterpolation.states[key] = {
                currentTargetId = nil,
                currentHpp = 100,
                interpolationDamagePercent = 0,
                interpolationHealPercent = 0,
                lastHitTime = nil,
                lastHitAmount = nil,
                hitDelayStartTime = nil,
                lastHealTime = nil,
                lastHealAmount = nil,
                healDelayStartTime = nil,
                overlayAlpha = 0,
                healOverlayAlpha = 0,
                lastFrameTime = nil,
            };
        end
        return HpInterpolation.states[key];
    end,

    -- Reset a specific interpolation state
    reset = function(key)
        HpInterpolation.states[key] = nil;
    end,

    -- Clear all interpolation states
    clearAll = function()
        HpInterpolation.states = {};
    end,

    -- Update interpolation and return hpPercentData ready for progressbar.ProgressBar
    -- Parameters:
    --   key: unique identifier for this HP bar (e.g., "target", "tot", "party_0", etc.)
    --   hppPercent: current HP percentage (0-100)
    --   targetId: entity target index (used to detect target changes)
    --   settings: table with hitFlashDuration, hitDelayDuration, hitInterpolationDecayPercentPerSecond
    --   currentTime: os.clock() value
    --   gradient: {startColor, endColor} for the HP bar
    -- Returns: hpPercentData array for progressbar.ProgressBar
    update = function(key, hppPercent, targetId, settings, currentTime, gradient)
        local state = HpInterpolation.getState(key);

        -- If we change targets, reset the interpolation
        if state.currentTargetId ~= targetId then
            state.currentTargetId = targetId;
            state.currentHpp = hppPercent;
            state.interpolationDamagePercent = 0;
            state.interpolationHealPercent = 0;
            state.hitDelayStartTime = nil;
            state.healDelayStartTime = nil;
            state.lastHitTime = nil;
            state.lastHealTime = nil;
        end

        -- If the target takes damage
        if hppPercent < state.currentHpp then
            local previousInterpolationDamagePercent = state.interpolationDamagePercent;
            local damageAmount = state.currentHpp - hppPercent;

            state.interpolationDamagePercent = state.interpolationDamagePercent + damageAmount;

            if previousInterpolationDamagePercent > 0 and state.lastHitAmount and damageAmount > state.lastHitAmount then
                state.lastHitTime = currentTime;
                state.lastHitAmount = damageAmount;
            elseif previousInterpolationDamagePercent == 0 then
                state.lastHitTime = currentTime;
                state.lastHitAmount = damageAmount;
            end

            if not state.lastHitTime or currentTime > state.lastHitTime + (settings.hitFlashDuration * 0.25) then
                state.lastHitTime = currentTime;
                state.lastHitAmount = damageAmount;
            end

            if previousInterpolationDamagePercent == 0 then
                state.hitDelayStartTime = currentTime;
            end

            -- Clear healing interpolation when taking damage
            state.interpolationHealPercent = 0;
            state.healDelayStartTime = nil;
        elseif hppPercent > state.currentHpp then
            -- If the target heals
            local previousInterpolationHealPercent = state.interpolationHealPercent;
            local healAmount = hppPercent - state.currentHpp;

            state.interpolationHealPercent = state.interpolationHealPercent + healAmount;

            if previousInterpolationHealPercent > 0 and state.lastHealAmount and healAmount > state.lastHealAmount then
                state.lastHealTime = currentTime;
                state.lastHealAmount = healAmount;
            elseif previousInterpolationHealPercent == 0 then
                state.lastHealTime = currentTime;
                state.lastHealAmount = healAmount;
            end

            if not state.lastHealTime or currentTime > state.lastHealTime + (settings.hitFlashDuration * 0.25) then
                state.lastHealTime = currentTime;
                state.lastHealAmount = healAmount;
            end

            if previousInterpolationHealPercent == 0 then
                state.healDelayStartTime = currentTime;
            end

            -- Clear damage interpolation when healing
            state.interpolationDamagePercent = 0;
            state.hitDelayStartTime = nil;
        end

        state.currentHpp = hppPercent;

        -- Reduce the damage HP amount to display based on time passed
        if state.interpolationDamagePercent > 0 and state.hitDelayStartTime and currentTime > state.hitDelayStartTime + settings.hitDelayDuration then
            if state.lastFrameTime then
                local deltaTime = currentTime - state.lastFrameTime;
                local animSpeed = 0.1 + (0.9 * (state.interpolationDamagePercent / 100));
                state.interpolationDamagePercent = state.interpolationDamagePercent - (settings.hitInterpolationDecayPercentPerSecond * deltaTime * animSpeed);
                state.interpolationDamagePercent = math.max(0, state.interpolationDamagePercent);
            end
        end

        -- Reduce the healing HP amount to display based on time passed
        if state.interpolationHealPercent > 0 and state.healDelayStartTime and currentTime > state.healDelayStartTime + settings.hitDelayDuration then
            if state.lastFrameTime then
                local deltaTime = currentTime - state.lastFrameTime;
                local animSpeed = 0.1 + (0.9 * (state.interpolationHealPercent / 100));
                state.interpolationHealPercent = state.interpolationHealPercent - (settings.hitInterpolationDecayPercentPerSecond * deltaTime * animSpeed);
                state.interpolationHealPercent = math.max(0, state.interpolationHealPercent);
            end
        end

        -- Calculate damage flash overlay alpha
        state.overlayAlpha = 0;
        if gConfig.healthBarFlashEnabled then
            if state.lastHitTime and currentTime < state.lastHitTime + settings.hitFlashDuration then
                local hitFlashTime = currentTime - state.lastHitTime;
                local hitFlashTimePercent = hitFlashTime / settings.hitFlashDuration;
                local maxAlphaHitPercent = 20;
                local maxAlpha = math.min(state.lastHitAmount, maxAlphaHitPercent) / maxAlphaHitPercent;
                maxAlpha = math.max(maxAlpha * 0.6, 0.4);
                state.overlayAlpha = math.pow(1 - hitFlashTimePercent, 2) * maxAlpha;
            end
        end

        -- Calculate healing flash overlay alpha
        state.healOverlayAlpha = 0;
        if gConfig.healthBarFlashEnabled then
            if state.lastHealTime and currentTime < state.lastHealTime + settings.hitFlashDuration then
                local healFlashTime = currentTime - state.lastHealTime;
                local healFlashTimePercent = healFlashTime / settings.hitFlashDuration;
                local maxAlphaHealPercent = 20;
                local maxAlpha = math.min(state.lastHealAmount, maxAlphaHealPercent) / maxAlphaHealPercent;
                maxAlpha = math.max(maxAlpha * 0.6, 0.4);
                state.healOverlayAlpha = math.pow(1 - healFlashTimePercent, 2) * maxAlpha;
            end
        end

        state.lastFrameTime = currentTime;

        -- Build HP percent data with interpolation
        local baseHpPercent = hppPercent;
        if state.interpolationHealPercent and state.interpolationHealPercent > 0 then
            baseHpPercent = hppPercent - state.interpolationHealPercent;
            baseHpPercent = math.max(0, baseHpPercent);
        end

        local hpPercentData = {{baseHpPercent / 100, gradient}};

        -- Add damage interpolation bar
        if state.interpolationDamagePercent > 0 then
            local interpolationOverlay;
            if gConfig.healthBarFlashEnabled and state.overlayAlpha > 0 then
                interpolationOverlay = {
                    '#ffacae',  -- overlay color (light red)
                    state.overlayAlpha
                };
            end
            table.insert(hpPercentData, {
                state.interpolationDamagePercent / 100,
                {'#cf3437', '#c54d4d'},  -- red gradient
                interpolationOverlay
            });
        end

        -- Add healing interpolation bar
        if state.interpolationHealPercent and state.interpolationHealPercent > 0 then
            local healInterpolationOverlay;
            if gConfig.healthBarFlashEnabled and state.healOverlayAlpha > 0 then
                healInterpolationOverlay = {
                    '#c8ffc8',  -- overlay color (light green)
                    state.healOverlayAlpha
                };
            end
            table.insert(hpPercentData, {
                state.interpolationHealPercent / 100,
                {'#4ade80', '#86efac'},  -- green gradient
                healInterpolationOverlay
            });
        end

        return hpPercentData;
    end,
};

-- ========================================
-- Settings Accessor Helpers
-- ========================================
-- Safe accessor for color settings with fallback
function GetColorSetting(module, setting, defaultValue)
    if gConfig and gConfig.colorCustomization and gConfig.colorCustomization[module] then
        return gConfig.colorCustomization[module][setting] or defaultValue;
    end
    return defaultValue;
end

-- Safe accessor for gradient settings with fallback
-- Returns {startColor, endColor} if gradient is enabled
-- Returns {startColor, startColor} if gradient is disabled (static color)
-- Returns defaultGradient if setting not found
function GetGradientSetting(module, setting, defaultGradient)
    if gConfig and gConfig.colorCustomization and gConfig.colorCustomization[module] then
        local gradient = gConfig.colorCustomization[module][setting];
        if gradient and gradient.enabled then
            return {gradient.start, gradient.stop};
        elseif gradient then
            return {gradient.start, gradient.start};  -- Static color
        end
    end
    return defaultGradient;
end

-- Party member cache for performance optimization
-- Caches party member target indices and server IDs to avoid O(n) lookups every frame
local partyMemberIndices = {};
local partyMemberServerIds = {};
local partyMemberIndicesDirty = true;

-- ========================================
-- Safe Memory Access Functions
-- ========================================
-- These functions provide consistent error handling when accessing game objects

-- Safe accessor for memory manager
local function GetMemoryManager()
    if AshitaCore == nil then return nil end
    return AshitaCore:GetMemoryManager();
end

-- Safe accessor for player object
function GetPlayerSafe()
    local memMgr = GetMemoryManager();
    if memMgr == nil then return nil end
    return memMgr:GetPlayer();
end

-- Safe accessor for party object
function GetPartySafe()
    local memMgr = GetMemoryManager();
    if memMgr == nil then return nil end
    return memMgr:GetParty();
end

-- Safe accessor for entity object
function GetEntitySafe()
    local memMgr = GetMemoryManager();
    if memMgr == nil then return nil end
    return memMgr:GetEntity();
end

-- Safe accessor for target object
function GetTargetSafe()
    local memMgr = GetMemoryManager();
    if memMgr == nil then return nil end
    return memMgr:GetTarget();
end

-- Safe accessor for inventory object
function GetInventorySafe()
    local memMgr = GetMemoryManager();
    if memMgr == nil then return nil end
    return memMgr:GetInventory();
end

-- Safe accessor for castbar object
function GetCastBarSafe()
    local memMgr = GetMemoryManager();
    if memMgr == nil then return nil end
    return memMgr:GetCastBar();
end

-- Safe accessor for recast object
function GetRecastSafe()
    local memMgr = GetMemoryManager();
    if memMgr == nil then return nil end
    return memMgr:GetRecast();
end

local debuff_font_settings = T{
	font_alignment = gdi.Alignment.Center,
	font_family = 'Consolas',
	font_height = 14,
	font_color = 0xFFFFFFFF,
	font_flags = gdi.FontFlags.Bold,
	outline_color = 0xFF000000,
	outline_width = 2,
};

-- ========================================
-- Drawing Primitive Helpers
-- ========================================
-- Internal implementation for rectangle drawing
-- Eliminates code duplication between draw_rect and draw_rect_background
local function draw_rect_impl(top_left, bot_right, color, radius, fill, shadowConfig, drawList)
    -- Draw shadow first if configured
    if shadowConfig then
        local shadowOffsetX = shadowConfig.offsetX or 2;
        local shadowOffsetY = shadowConfig.offsetY or 2;
        local shadowColor = shadowConfig.color or 0x80000000;

        -- Apply alpha override if specified
        if shadowConfig.alpha then
            local baseColor = bit.band(shadowColor, 0x00FFFFFF);
            local alpha = math.floor(math.clamp(shadowConfig.alpha, 0, 1) * 255);
            shadowColor = bit.bor(baseColor, bit.lshift(alpha, 24));
        end

        local shadow_top_left = {top_left[1] + shadowOffsetX, top_left[2] + shadowOffsetY};
        local shadow_bot_right = {bot_right[1] + shadowOffsetX, bot_right[2] + shadowOffsetY};
        local shadowColorU32 = imgui.GetColorU32(shadowColor);
        local shadowDimensions = {
            { shadow_top_left[1], shadow_top_left[2] },
            { shadow_bot_right[1], shadow_bot_right[2] }
        };

        if (fill == true) then
            drawList:AddRectFilled(shadowDimensions[1], shadowDimensions[2], shadowColorU32, radius, ImDrawCornerFlags_All);
        else
            drawList:AddRect(shadowDimensions[1], shadowDimensions[2], shadowColorU32, radius, ImDrawCornerFlags_All, 1);
        end
    end

    -- Draw main rectangle
    local color = imgui.GetColorU32(color);
    local dimensions = {
        { top_left[1], top_left[2] },
        { bot_right[1], bot_right[2] }
    };
	if (fill == true) then
   		drawList:AddRectFilled(dimensions[1], dimensions[2], color, radius, ImDrawCornerFlags_All);
	else
		drawList:AddRect(dimensions[1], dimensions[2], color, radius, ImDrawCornerFlags_All, 1);
	end
end

-- Public API: Draw rectangle using window draw list
function draw_rect(top_left, bot_right, color, radius, fill, shadowConfig)
    draw_rect_impl(top_left, bot_right, color, radius, fill, shadowConfig, imgui.GetWindowDrawList());
end

-- Public API: Draw rectangle using background draw list
function draw_rect_background(top_left, bot_right, color, radius, fill, shadowConfig)
    draw_rect_impl(top_left, bot_right, color, radius, fill, shadowConfig, imgui.GetBackgroundDrawList());
end

function draw_circle(center, radius, color, segments, fill, shadowConfig)
    -- Draw shadow first if configured
    if shadowConfig then
        local shadowOffsetX = shadowConfig.offsetX or 2;
        local shadowOffsetY = shadowConfig.offsetY or 2;
        local shadowColor = shadowConfig.color or 0x80000000;

        -- Apply alpha override if specified
        if shadowConfig.alpha then
            local baseColor = bit.band(shadowColor, 0x00FFFFFF);
            local alpha = math.floor(math.clamp(shadowConfig.alpha, 0, 1) * 255);
            shadowColor = bit.bor(baseColor, bit.lshift(alpha, 24));
        end

        local shadow_center = {center[1] + shadowOffsetX, center[2] + shadowOffsetY};
        local shadowColorU32 = imgui.GetColorU32(shadowColor);

        if (fill == true) then
            imgui.GetWindowDrawList():AddCircleFilled(shadow_center, radius, shadowColorU32, segments);
        else
            imgui.GetWindowDrawList():AddCircle(shadow_center, radius, shadowColorU32, segments, 1);
        end
    end

    -- Draw main circle
    local color = imgui.GetColorU32(color);

	if (fill == true) then
   		imgui.GetWindowDrawList():AddCircleFilled(center, radius, color, segments);
	else
		imgui.GetWindowDrawList():AddCircle(center, radius, color, segments, 1);
	end
end

-- Get the appropriate draw list for UI rendering
-- Returns WindowDrawList when config is open (so config stays on top)
-- Returns ForegroundDrawList otherwise (so UI elements render on top of game)
function GetUIDrawList()
	if showConfig and showConfig[1] then
		return imgui.GetWindowDrawList();
	else
		return imgui.GetForegroundDrawList();
	end
end

-- Party member cache functions for performance optimization
local function UpdatePartyCache()
	local party = AshitaCore:GetMemoryManager():GetParty();
	if party == nil then
		partyMemberIndices = {};
		partyMemberServerIds = {};
		partyMemberIndicesDirty = false;
		return;
	end

	partyMemberIndices = {};
	partyMemberServerIds = {};
	for i = 0, 17 do
		if (party:GetMemberIsActive(i) == 1) then
			local idx = party:GetMemberTargetIndex(i);
			local serverId = party:GetMemberServerId(i);
			if idx ~= 0 then
				partyMemberIndices[idx] = true;
			end
			if serverId ~= 0 then
				partyMemberServerIds[serverId] = true;
			end
		end
	end
	partyMemberIndicesDirty = false;
end

-- Mark party cache as dirty (to be called when party changes)
function MarkPartyCacheDirty()
	partyMemberIndicesDirty = true;
end

-- Helper to convert ARGB (0xAARRGGBB) to RGBA table {R, G, B, A}
-- Exported for use by all modules
function ARGBToRGBA(argb)
	local a = bit.band(bit.rshift(argb, 24), 0xFF) / 255.0;
	local r = bit.band(bit.rshift(argb, 16), 0xFF) / 255.0;
	local g = bit.band(bit.rshift(argb, 8), 0xFF) / 255.0;
	local b = bit.band(argb, 0xFF) / 255.0;
	return {r, g, b, a};
end

-- Helper to convert RGBA table {R, G, B, A} to ARGB (0xAARRGGBB)
-- Exported for use by all modules
function RGBAToARGB(rgba)
	return bit.bor(
		bit.lshift(math.floor(rgba[4] * 255), 24), -- Alpha
		bit.lshift(math.floor(rgba[1] * 255), 16), -- Red
		bit.lshift(math.floor(rgba[2] * 255), 8),  -- Green
		math.floor(rgba[3] * 255)                   -- Blue
	);
end

-- Generic function to get entity name color based on type and claim status
-- Takes a colorConfig table (e.g., gConfig.colorCustomization.targetBar or .enemyList)
-- Returns color in RGBA format
function GetEntityNameColorRGBA(targetEntity, targetIndex, colorConfig)
	-- Default to other player color
	local color = {1,1,1,1};
	if colorConfig then
		color = ARGBToRGBA(colorConfig.playerOtherTextColor);
	end

	-- Validate entity and index are not nil
	if (targetEntity == nil) then
		return color; -- Default white RGBA
	end
	if (targetIndex == nil) then
		return color;
	end

	local flag = targetEntity.SpawnFlags;

	-- Determine the entity type and apply the proper color
	if (bit.band(flag, SPAWN_FLAG_PLAYER) == SPAWN_FLAG_PLAYER) then --players
		-- Default: other player
		color = ARGBToRGBA(colorConfig.playerOtherTextColor);
		-- Check if party/alliance member using cache
		if partyMemberIndicesDirty then
			UpdatePartyCache();
		end
		if (partyMemberIndices[targetIndex]) then
			color = ARGBToRGBA(colorConfig.playerPartyTextColor);
		end
	elseif (bit.band(flag, SPAWN_FLAG_NPC) == SPAWN_FLAG_NPC) then --npc
		color = ARGBToRGBA(colorConfig.npcTextColor);
	else --mob
		local entMgr = AshitaCore:GetMemoryManager():GetEntity();
		local claimStatus = entMgr:GetClaimStatus(targetIndex);
		local claimId = bit.band(claimStatus, 0xFFFF);

		if (claimId == 0) then
			-- Unclaimed mob
			color = ARGBToRGBA(colorConfig.mobUnclaimedTextColor);
		else
			-- Claimed by someone
			color = ARGBToRGBA(colorConfig.mobOtherClaimedTextColor);
			-- Check if claimed by party member using cache
			if partyMemberIndicesDirty then
				UpdatePartyCache();
			end
			if (partyMemberServerIds[claimId]) then
				-- Claimed by party member
				color = ARGBToRGBA(colorConfig.mobPartyClaimedTextColor);
			end
		end
	end
	return color;
end

-- Returns ARGB format instead of RGBA
function GetEntityNameColor(targetEntity, targetIndex, colorConfig)
	local rgba = GetEntityNameColorRGBA(targetEntity, targetIndex, colorConfig);
	return RGBAToARGB(rgba);
end

-- Wrapper for backwards compatibility - uses shared entity colors
function GetColorOfTargetRGBA(targetEntity, targetIndex)
	if gConfig and gConfig.colorCustomization and gConfig.colorCustomization.shared then
		return GetEntityNameColorRGBA(targetEntity, targetIndex, gConfig.colorCustomization.shared);
	end
	return {1,1,1,1}; -- Default white RGBA
end

-- Wrapper function that returns ARGB format (for backwards compatibility)
function GetColorOfTarget(targetEntity, targetIndex)
	local rgba = GetColorOfTargetRGBA(targetEntity, targetIndex);
	return RGBAToARGB(rgba);
end

function GetIsMob(targetEntity)
	if (targetEntity == nil) then
		return false;
	end
    -- Obtain the entity spawn flags..
    local flag = targetEntity.SpawnFlags;
    -- Determine the entity type
	local isMob;
    if (bit.band(flag, SPAWN_FLAG_PLAYER) == SPAWN_FLAG_PLAYER or bit.band(flag, SPAWN_FLAG_NPC) == SPAWN_FLAG_NPC) then --players and npcs
        isMob = false;
    else --mob
		isMob = true;
    end
	return isMob;
end

function GetIsMobByIndex(index)
	return (bit.band(AshitaCore:GetMemoryManager():GetEntity():GetSpawnFlags(index), 0x10) ~= 0);
end

function SeparateNumbers(val, sep)
    local separated = string.gsub(val, "(%d)(%d%d%d)$", "%1" .. sep .. "%2", 1)
    local found = 0;
    while true do
        separated, found = string.gsub(separated, "(%d)(%d%d%d),", "%1" .. sep .. "%2,", 1)
        if found == 0 then break end
    end
    return separated;
end

function LoadTexture(textureName)
    if (theme == nil or theme == "") then
        theme = "default";
    end

    local textures = T{}
    -- Load the texture for usage..
    local texture_ptr = ffi.new('IDirect3DTexture8*[1]');
    local res = C.D3DXCreateTextureFromFileA(d3d8dev, string.format('%s/assets/%s.png', addon.path, textureName), texture_ptr);
    if (res ~= C.S_OK) then
--      error(('Failed to load image texture: %08X (%s)'):fmt(res, d3d.get_error(res)));
        return nil;
    end;
    textures.image = ffi.new('IDirect3DTexture8*', texture_ptr[0]);
    d3d.gc_safe_release(textures.image);

    return textures;
end

function FormatInt(number)

	local i, j, minus, int, fraction = tostring(number):find('([-]?)(%d+)([.]?%d*)')
  
	-- reverse the int-string and append a comma to all blocks of 3 digits
	int = int:reverse():gsub("(%d%d%d)", "%1,")
  
	-- reverse the int-string back remove an optional comma and put the 
	-- optional minus and fractional part back
	return minus .. int:reverse():gsub("^,", "") .. fraction
end

function GetIndexFromId(id)
    local entMgr = AshitaCore:GetMemoryManager():GetEntity();
    
    --Shortcut for monsters/static npcs..
    if (bit.band(id, 0x1000000) ~= 0) then
        local index = bit.band(id, 0xFFF);
        if (index >= 0x900) then
            index = index - 0x100;
        end

        if (index < 0x900) and (entMgr:GetServerId(index) == id) then
            return index;
        end
    end

    for i = 1,0x8FF do
        if entMgr:GetServerId(i) == id then
            return i;
        end
    end

    return 0;
end

function ParseActionPacket(e)
    local bitData;
    local bitOffset;
    local maxLength = e.size * 8;
    local function UnpackBits(length)
        if ((bitOffset + length) >= maxLength) then
            maxLength = 0; --Using this as a flag since any malformed fields mean the data is trash anyway.
            return 0;
        end
        local value = ashita.bits.unpack_be(bitData, 0, bitOffset, length);
        bitOffset = bitOffset + length;
        return value;
    end

    local actionPacket = T{};
    bitData = e.data_raw;
    bitOffset = 40;
    actionPacket.UserId = UnpackBits(32);
    actionPacket.UserIndex = GetIndexFromId(actionPacket.UserId); --Many implementations of this exist, or you can comment it out if not needed.  It can be costly.
    local targetCount = UnpackBits(6);
    --Unknown 4 bits
    bitOffset = bitOffset + 4;
    actionPacket.Type = UnpackBits(4);
    -- Bandaid fix until we have more flexible packet parsing
    if actionPacket.Type == 8 or actionPacket.Type == 9 then
        actionPacket.Param = UnpackBits(16);
        actionPacket.SpellGroup = UnpackBits(16);
    else
        -- Not every action packet has the same data at the same offsets so we just skip this for now
        actionPacket.Param = UnpackBits(32);
    end

    actionPacket.Recast = UnpackBits(32);

    actionPacket.Targets = T{};
    if (targetCount > 0) then
        for i = 1,targetCount do
            local target = T{};
            target.Id = UnpackBits(32);
            local actionCount = UnpackBits(4);
            target.Actions = T{};
            if (actionCount == 0) then
                break;
            else
                for j = 1,actionCount do
                    local action = {};
                    action.Reaction = UnpackBits(5);
                    action.Animation = UnpackBits(12);
                    action.SpecialEffect = UnpackBits(7);
                    action.Knockback = UnpackBits(3);
                    action.Param = UnpackBits(17);
                    action.Message = UnpackBits(10);
                    action.Flags = UnpackBits(31);

                    local hasAdditionalEffect = (UnpackBits(1) == 1);
                    if hasAdditionalEffect then
                        local additionalEffect = {};
                        additionalEffect.Damage = UnpackBits(10);
                        additionalEffect.Param = UnpackBits(17);
                        additionalEffect.Message = UnpackBits(10);
                        action.AdditionalEffect = additionalEffect;
                    end

                    local hasSpikesEffect = (UnpackBits(1) == 1);
                    if hasSpikesEffect then
                        local spikesEffect = {};
                        spikesEffect.Damage = UnpackBits(10);
                        spikesEffect.Param = UnpackBits(14);
                        spikesEffect.Message = UnpackBits(10);
                        action.SpikesEffect = spikesEffect;
                    end

                    target.Actions:append(action);
                end
            end
            actionPacket.Targets:append(target);
        end
    end

    if  (maxLength ~= 0) and (#actionPacket.Targets > 0) then
        return actionPacket;
    end
end

function ParseMobUpdatePacket(e)
	if (e.id == 0x00E) then
		local mobPacket = T{};
		mobPacket.monsterId = struct.unpack('L', e.data, 0x04 + 1);
		mobPacket.monsterIndex = struct.unpack('H', e.data, 0x08 + 1);
		mobPacket.updateFlags = struct.unpack('B', e.data, 0x0A + 1);
		if (bit.band(mobPacket.updateFlags, 0x02) == 0x02) then
			mobPacket.newClaimId = struct.unpack('L', e.data, 0x2C + 1);
		end
		return mobPacket;
	end
end

function deep_copy_table(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deep_copy_table(orig_key)] = deep_copy_table(orig_value)
        end
        setmetatable(copy, deep_copy_table(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function valid_server_id(server_id)
    return server_id > 0 and server_id < 0x4000000;
end

function ParseMessagePacket(e)
    local basic = {
        sender     = struct.unpack('i4', e, 0x04 + 1),
        target     = struct.unpack('i4', e, 0x08 + 1),
        param      = struct.unpack('i4', e, 0x0C + 1),
        value      = struct.unpack('i4', e, 0x10 + 1),
        sender_tgt = struct.unpack('i2', e, 0x14 + 1),
        target_tgt = struct.unpack('i2', e, 0x16 + 1),
        message    = struct.unpack('i2', e, 0x18 + 1),
    }
    return basic
end

function IsMemberOfParty(targetIndex)
	local party = AshitaCore:GetMemoryManager():GetParty();
	if (party == nil) then
		return false;
	end
	for i = 0, 17 do
		if (party:GetMemberTargetIndex(i) == targetIndex) then
			return true;
		end
	end
	return false;
end

function DrawStatusIcons(statusIds, iconSize, maxColumns, maxRows, drawBg, xOffset, buffTimes, settings)
	if (statusIds ~= nil and #statusIds > 0) then
		local currentRow = 1;
        local currentColumn = 0;
        if (xOffset ~= nil) then
            imgui.SetCursorPosX(imgui.GetCursorPosX() + xOffset);
        end
		for i = 0,#statusIds do
            -- Don't check anymore after -1, as it will be all -1's
            if (statusIds == -1) then
                break;
            end
            local icon = statusHandler.get_icon_from_theme(gConfig.statusIconTheme, statusIds[i]);
            if (icon ~= nil) then
                if (drawBg == true) then
                    local resetX, resetY = imgui.GetCursorScreenPos();
                    local bgIcon;
                    local isBuff = buffTable.IsBuff(statusIds[i]);
                    local bgSize = iconSize * 1.1;
                    local yOffset = bgSize * -0.1;
                    if (isBuff) then
                        yOffset = bgSize * -0.3;
                    end
                    imgui.SetCursorScreenPos({resetX - ((bgSize - iconSize) / 1.5), resetY + yOffset});
                    bgIcon = statusHandler.GetBackground(isBuff);
                    imgui.Image(bgIcon, { bgSize + 1, bgSize  / .75});
                    imgui.SameLine();
                    imgui.SetCursorScreenPos({resetX, resetY});
                end
                -- Capture position BEFORE drawing icon to get accurate position
                local iconPosX, iconPosY = imgui.GetCursorScreenPos();
                imgui.Image(icon, { iconSize, iconSize }, { 0, 0 }, { 1, 1 });
                local textObjName = "debuffText" .. tostring(i)
                if buffTimes ~= nil then
                    -- Calculate center of the icon for text positioning
                    local textPosX = iconPosX + iconSize / 2
                    local textPosY = iconPosY + iconSize  -- Move text below the icon
					
                    local textObj = debuffTable[textObjName]
                    -- Use passed settings if available, otherwise use default
                    local font_base = settings or debuff_font_settings;
                    if (textObj == nil) then
                        local font_settings = T{
                            font_alignment = font_base.font_alignment,
                            font_family = gConfig.fontFamily,
                            font_height = font_base.font_height,
                            font_color = font_base.font_color,
                            font_flags = font_base.font_flags,
                            outline_color = font_base.outline_color,
                            outline_width = font_base.outline_width,
                        };
                        textObj = gdi:create_object(font_settings)
                        debuffTable[textObjName] = textObj
                    end
                    local scaledFontHeight = gConfig.targetBarIconFontSize or font_base.font_height;
                    textObj:set_font_height(scaledFontHeight)
                    textObj:set_text('')
                    if buffTimes[i] ~= nil then
                        -- Text is center-aligned, so just use the calculated center position
                        textObj:set_position_x(textPosX)
                        textObj:set_position_y(textPosY)
                        textObj:set_text(tostring(buffTimes[i]))
                        textObj:set_visible(true);
                    end
                end
                if (imgui.IsItemHovered()) then
                    statusHandler.render_tooltip(statusIds[i]);
                end
                currentColumn = currentColumn + 1;
                -- Handle multiple rows
                if (currentColumn < maxColumns) then
                    imgui.SameLine();
                else
                    currentRow = currentRow + 1;
                    if (currentRow > maxRows) then
                        return;
                    end
                    if (xOffset ~= nil) then
                        imgui.SetCursorPosX(imgui.GetCursorPosX() + xOffset);
                    end
                    currentColumn = 0;
                end
            end
		end
	end
end

function GetStPartyIndex()
    local ptr = AshitaCore:GetPointerManager():Get('party');
    ptr = ashita.memory.read_uint32(ptr);
    ptr = ashita.memory.read_uint32(ptr);
    local isActive = (ashita.memory.read_uint32(ptr + 0x54) ~= 0);
    if isActive then
        return ashita.memory.read_uint8(ptr + 0x50);
    else
        return nil;
    end
end

function GetSubTargetActive()
    local playerTarget = AshitaCore:GetMemoryManager():GetTarget();
    if (playerTarget == nil) then
        return false;
    end
    return playerTarget:GetIsSubTargetActive() == 1 or (GetStPartyIndex() ~= nil and playerTarget:GetTargetIndex(0) ~= 0);
end

function GetTargets()
    local playerTarget = AshitaCore:GetMemoryManager():GetTarget();
    local party = AshitaCore:GetMemoryManager():GetParty();

    if (playerTarget == nil or party == nil) then
        return nil, nil;
    end

    local mainTarget = playerTarget:GetTargetIndex(0);
    local secondaryTarget = playerTarget:GetTargetIndex(1);
    local partyTarget = GetStPartyIndex();

    if (partyTarget ~= nil) then
        secondaryTarget = mainTarget;
        mainTarget = party:GetMemberTargetIndex(partyTarget);
    end

    return mainTarget, secondaryTarget;
end

function GetIsTargetLockedOn()
    local playerTarget = AshitaCore:GetMemoryManager():GetTarget();
    if (playerTarget == nil) then
        return false;
    end

    -- Check if the target window is locked on using GetLockedOnFlags
    if (playerTarget.GetLockedOnFlags ~= nil) then
        local flags = playerTarget:GetLockedOnFlags();
        -- Lock-on is indicated by flags value of 49
        return flags == 49;
    end

    -- Fallback: method not available
    return false;
end

function GetJobStr(jobIdx)
    if (jobIdx == nil or jobIdx == 0 or jobIdx == -1) then
        return '';
    end

    return AshitaCore:GetResourceManager():GetString("jobs.names_abbr", jobIdx);
end

-- Easing function for HP bar interpolation
-- Reference: https://easings.net/
function easeOutPercent(percent)
    -- Ease out exponential
    if percent < 1 then
        return 1 - math.pow(2, -10 * percent);
    else
        return percent;
    end

    -- Ease out quart
    -- return 1 - math.pow(1 - percent, 4);

    -- Ease out quint
    -- return 1 - math.pow(1 - percent, 5);
end

function GetHpColors(hpPercent)
    local hpNameColor;
    local hpGradient;
    if (hpPercent < .25) then
        hpNameColor = 0xFFFF0000;
        hpGradient = {"#ec3232", "#f16161"};
    elseif (hpPercent < .50) then;
        hpNameColor = 0xFFFFA500;
        hpGradient = {"#ee9c06", "#ecb44e"};
    elseif (hpPercent < .75) then
        hpNameColor = 0xFFFFFF00;
        hpGradient = {"#ffff0c", "#ffff97"};
    else
        hpNameColor = 0xFFFFFFFF;
        hpGradient = {"#e26c6c", "#fa9c9c"};
    end

    return hpNameColor, hpGradient;
end

-- =====================================
-- = Color Conversion Utility Functions =
-- =====================================

-- Convert ARGB integer (0xAARRGGBB) to ImGui RGBA float table {r, g, b, a}
function ARGBToImGui(argb)
    local a = bit.rshift(bit.band(argb, 0xFF000000), 24) / 255;
    local r = bit.rshift(bit.band(argb, 0x00FF0000), 16) / 255;
    local g = bit.rshift(bit.band(argb, 0x0000FF00), 8) / 255;
    local b = bit.band(argb, 0x000000FF) / 255;
    return {r, g, b, a};
end

-- Convert ImGui RGBA float table to ARGB integer
function ImGuiToARGB(rgba)
    local a = math.floor(rgba[4] * 255);
    local r = math.floor(rgba[1] * 255);
    local g = math.floor(rgba[2] * 255);
    local b = math.floor(rgba[3] * 255);
    return bit.bor(
        bit.lshift(a, 24),
        bit.lshift(r, 16),
        bit.lshift(g, 8),
        b
    );
end

-- Convert hex string (#RRGGBB or #RRGGBBAA) to ImGui RGBA float table
function HexToImGui(hex)
    hex = hex:gsub("#", "");
    local r = tonumber(hex:sub(1,2), 16) / 255;
    local g = tonumber(hex:sub(3,4), 16) / 255;
    local b = tonumber(hex:sub(5,6), 16) / 255;
    local a = 1.0;
    if #hex == 8 then
        a = tonumber(hex:sub(7,8), 16) / 255;
    end
    return {r, g, b, a};
end

-- Convert ImGui RGBA float table to hex string
function ImGuiToHex(rgba)
    local r = math.floor(rgba[1] * 255);
    local g = math.floor(rgba[2] * 255);
    local b = math.floor(rgba[3] * 255);
    if rgba[4] and rgba[4] < 1.0 then
        local a = math.floor(rgba[4] * 255);
        return string.format("#%02x%02x%02x%02x", r, g, b, a);
    end
    return string.format("#%02x%02x%02x", r, g, b);
end

-- Convert hex string to ARGB integer (for text colors)
function HexToARGB(hexString, alpha)
    hexString = hexString:gsub("#", "");
    local r = tonumber(hexString:sub(1,2), 16);
    local g = tonumber(hexString:sub(3,4), 16);
    local b = tonumber(hexString:sub(5,6), 16);
    local a = alpha or 0xFF;
    return bit.bor(
        bit.lshift(a, 24),
        bit.lshift(r, 16),
        bit.lshift(g, 8),
        b
    );
end

-- ======================================
-- = Custom Color Accessor Functions =
-- ======================================

-- Get HP gradient based on HP percent and custom colors
function GetCustomHpColors(hppPercent, moduleColorSettings)
    local hpNameColor, hpGradient;

    if not gConfig or not gConfig.colorCustomization or not moduleColorSettings then
        -- Fallback to original GetHpColors logic
        return GetHpColors(hppPercent);
    end

    local hpSettings = moduleColorSettings.hpGradient;

    if not hpSettings then
        return GetHpColors(hppPercent);
    end

    if hppPercent < 0.25 then
        hpGradient = {hpSettings.low.start, hpSettings.low.stop};
    elseif hppPercent < 0.5 then
        hpGradient = {hpSettings.medLow.start, hpSettings.medLow.stop};
    elseif hppPercent < 0.75 then
        hpGradient = {hpSettings.medHigh.start, hpSettings.medHigh.stop};
    else
        hpGradient = {hpSettings.high.start, hpSettings.high.stop};
    end

    -- Convert first gradient color to ARGB for text
    hpNameColor = HexToARGB(hpGradient[1], 0xFF);

    return hpNameColor, hpGradient;
end

-- Get gradient colors from settings with fallback to defaults
function GetCustomGradient(moduleSettings, gradientName)
    if not gConfig or not gConfig.colorCustomization or not moduleSettings then
        return nil; -- Fallback to hardcoded
    end

    local gradient = moduleSettings[gradientName];
    if not gradient then
        return nil;
    end

    if gradient.enabled then
        return {gradient.start, gradient.stop};
    else
        -- Static color (both same)
        return {gradient.start, gradient.start};
    end
end

function ClearDebuffFontCache()
    -- Destroy all gdi font objects before clearing
    for key, textObj in pairs(debuffTable) do
        if textObj ~= nil then
            gdi:destroy_object(textObj);
        end
    end
    debuffTable = T{};
end

-- ========================================
-- Drop Shadow Utility Functions
-- ========================================

--[[
    NOTE: gdifonts has NATIVE outline/shadow support built-in!

    Use the font settings properties to configure shadows:
        - outline_color: ARGB color for the outline/shadow (e.g., 0xFF000000 for black)
        - outline_width: Width in pixels (e.g., 2 for a nice shadow effect)

    Example:
        local font_settings = T{
            font_family = 'Arial',
            font_height = 12,
            font_color = 0xFFFFFFFF,
            outline_color = 0xFF000000,  -- Black shadow
            outline_width = 2,            -- 2px shadow
        };
        myFont = gdi:create_object(font_settings);

    The old ApplyFontShadow() function is deprecated and not needed with gdifonts.
]]--
