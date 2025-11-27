require('common');
local imgui = require('imgui');
local fonts = require('fonts');
local ffi       = require('ffi');
local d3d       = require('d3d8');
local C         = ffi.C;
local d3d8dev   = d3d.get_device();
local statusHandler = require('statushandler');
local buffTable = require('bufftable');

debuffTable = T{};

-- Entity spawn flags constants
local SPAWN_FLAG_PLAYER = 0x0001;  -- Entity is a player character
local SPAWN_FLAG_NPC = 0x0002;     -- Entity is an NPC

-- Render flags constants
local RENDER_FLAG_VISIBLE = 0x200;  -- Entity is visible and rendered
local RENDER_FLAG_HIDDEN = 0x4000;  -- Entity is hidden (cutscene, menu, etc.)

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
	visible = true,
	locked = true,
	font_family = 'Consolas',
	font_height = 8,
	color = 0xFFFFFFFF,
	bold = true,
	italic = false;
	color_outline = 0xFF000000,
	draw_flags = 0x10,
	background = 
	T{
		visible = false,
	},
	right_justified = false;
};

function draw_rect(top_left, bot_right, color, radius, fill)
    local color = imgui.GetColorU32(color);
    local dimensions = {
        { top_left[1], top_left[2] },
        { bot_right[1], bot_right[2] }
    };
	if (fill == true) then
   		imgui.GetWindowDrawList():AddRectFilled(dimensions[1], dimensions[2], color, radius, ImDrawCornerFlags_All);
	else
		imgui.GetWindowDrawList():AddRect(dimensions[1], dimensions[2], color, radius, ImDrawCornerFlags_All, 1);
	end
end

function draw_rect_background(top_left, bot_right, color, radius, fill)
    local color = imgui.GetColorU32(color);
    local dimensions = {
        { top_left[1], top_left[2] },
        { bot_right[1], bot_right[2] }
    };
	if (fill == true) then
   		imgui.GetBackgroundDrawList():AddRectFilled(dimensions[1], dimensions[2], color, radius, ImDrawCornerFlags_All);
	else
		imgui.GetBackgroundDrawList():AddRect(dimensions[1], dimensions[2], color, radius, ImDrawCornerFlags_All, 1);
	end
end

function draw_circle(center, radius, color, segments, fill)
    local color = imgui.GetColorU32(color);

	if (fill == true) then
   		imgui.GetWindowDrawList():AddCircleFilled(center, radius, color, segments);
	else
		imgui.GetWindowDrawList():AddCircle(center, radius, color, segments, 1);
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
local function ARGBToRGBA(argb)
	local a = bit.band(bit.rshift(argb, 24), 0xFF) / 255.0;
	local r = bit.band(bit.rshift(argb, 16), 0xFF) / 255.0;
	local g = bit.band(bit.rshift(argb, 8), 0xFF) / 255.0;
	local b = bit.band(argb, 0xFF) / 255.0;
	return {r, g, b, a};
end

-- Helper to convert RGBA table {R, G, B, A} to ARGB (0xAARRGGBB)
local function RGBAToARGB(rgba)
	return bit.bor(
		bit.lshift(math.floor(rgba[4] * 255), 24), -- Alpha
		bit.lshift(math.floor(rgba[1] * 255), 16), -- Red
		bit.lshift(math.floor(rgba[2] * 255), 8),  -- Green
		math.floor(rgba[3] * 255)                   -- Blue
	);
end

function GetColorOfTargetRGBA(targetEntity, targetIndex)
    -- Obtain the entity spawn flags..

	-- Default to other player color
	local color = {1,1,1,1};
	if gConfig and gConfig.colorCustomization then
		color = ARGBToRGBA(gConfig.colorCustomization.targetBar.playerOtherTextColor);
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
		color = ARGBToRGBA(gConfig.colorCustomization.targetBar.playerOtherTextColor);
		-- Check if party/alliance member using cache
		if partyMemberIndicesDirty then
			UpdatePartyCache();
		end
		if (partyMemberIndices[targetIndex]) then
			color = ARGBToRGBA(gConfig.colorCustomization.targetBar.playerPartyTextColor);
		end
    elseif (bit.band(flag, SPAWN_FLAG_NPC) == SPAWN_FLAG_NPC) then --npc
        color = ARGBToRGBA(gConfig.colorCustomization.targetBar.npcTextColor);
    else --mob
		local entMgr = AshitaCore:GetMemoryManager():GetEntity();
		local claimStatus = entMgr:GetClaimStatus(targetIndex);
		local claimId = bit.band(claimStatus, 0xFFFF);
--		local isClaimed = (bit.band(claimStatus, 0xFFFF0000) ~= 0);

		if (claimId == 0) then
			-- Unclaimed mob
			color = ARGBToRGBA(gConfig.colorCustomization.targetBar.mobUnclaimedTextColor);
		else
			-- Claimed by someone
			color = ARGBToRGBA(gConfig.colorCustomization.targetBar.mobOtherClaimedTextColor);
			-- Check if claimed by party member using cache
			if partyMemberIndicesDirty then
				UpdatePartyCache();
			end
			if (partyMemberServerIds[claimId]) then
				-- Claimed by party member
				color = ARGBToRGBA(gConfig.colorCustomization.targetBar.mobPartyClaimedTextColor);
			end
		end
	end
	return color;
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

local function GetIndexFromId(id)
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
                imgui.Image(icon, { iconSize, iconSize }, { 0, 0 }, { 1, 1 });
                local textObjName = "debuffText" .. tostring(i)
                if buffTimes ~= nil then
                    local startX, startY = imgui.GetCursorScreenPos();
                    local textPosX = startX + (i-1)*iconSize + iconSize/2 + i - 1
                    local textPosY = startY
					
                    local textObj = debuffTable[textObjName]
                    if (textObj == nil) then
                        local font_settings = T{
                            visible = debuff_font_settings.visible,
                            locked = debuff_font_settings.locked,
                            font_family = gConfig.fontFamily,
                            font_height = debuff_font_settings.font_height,
                            color = debuff_font_settings.color,
                            bold = debuff_font_settings.bold,
                            italic = debuff_font_settings.italic,
                            color_outline = debuff_font_settings.color_outline,
                            draw_flags = debuff_font_settings.draw_flags,
                            background = debuff_font_settings.background,
                            right_justified = debuff_font_settings.right_justified,
                        };
                        textObj = fonts.new(font_settings)
                        debuffTable[textObjName] = textObj
                    end
                    textObj:SetFontHeight(debuff_font_settings.font_height + gConfig.targetBarIconFontOffset)
                    textObj:SetText('')
                    if buffTimes[i] ~= nil then
                        local timeString = tostring(buffTimes[i])
                        if (string.len(timeString) == 2) then
                            textObj:SetPositionX(textPosX + 2.5 - gConfig.targetBarIconFontOffset)
                            textObj:SetPositionY(textPosY)
                        elseif (string.len(timeString) == 1) then
                            textObj:SetPositionX(textPosX + 5 - gConfig.targetBarIconFontOffset)
                            textObj:SetPositionY(textPosY)
                        else
                            textObj:SetPositionX(textPosX - gConfig.targetBarIconFontOffset)
                            textObj:SetPositionY(textPosY)
                        end
                        textObj:SetText(tostring(buffTimes[i]))
                        textObj:SetVisible(true);
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
    debuffTable = T{};
end
