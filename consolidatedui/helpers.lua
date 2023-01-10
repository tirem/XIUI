require('common');
local imgui = require('imgui');
local ffi       = require('ffi');
local d3d       = require('d3d8');
local C         = ffi.C;
local d3d8dev   = d3d.get_device();

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

function draw_circle(center, radius, color, segments, fill)
    local color = imgui.GetColorU32(color);

	if (fill == true) then
   		imgui.GetWindowDrawList():AddCircleFilled(center, radius, color, segments);
	else
		imgui.GetWindowDrawList():AddCircle(center, radius, color, segments, 1);
	end
end

function GetColorOfTarget(targetEntity, targetIndex)
    -- Obtain the entity spawn flags..

	local color = {1,1,1,1};
	if (targetIndex == nil) then
		return color;
	end
    local flag = targetEntity.SpawnFlags;

    -- Determine the entity type and apply the proper color
    if (bit.band(flag, 0x0001) == 0x0001) then --players
		local party = AshitaCore:GetMemoryManager():GetParty();
		for i = 0, 17 do
			if (party:GetMemberIsActive(i) == 1) then
				if (party:GetMemberTargetIndex(i) == targetIndex) then
					color = {0,1,1,1};
					break;
				end
			end
		end
    elseif (bit.band(flag, 0x0002) == 0x0002) then --npc
        color = {.4,1,.4,1};
    else --mob
		local entMgr = AshitaCore:GetMemoryManager():GetEntity();
		local claimStatus = entMgr:GetClaimStatus(targetIndex);
		local claimId = bit.band(claimStatus, 0xFFFF);
--		local isClaimed = (bit.band(claimStatus, 0xFFFF0000) ~= 0);

		if (claimId == 0) then
			color = {1,1,.4,1};
		else
			color = {1,.4,1,1};
			local party = AshitaCore:GetMemoryManager():GetParty();
			for i = 0, 17 do
				if (party:GetMemberIsActive(i) == 1) then
					if (party:GetMemberServerId(i) == claimId) then
						color = {1,.4,.4,1};
						break;
					end;
				end
			end
		end
	end
	return color;
end

function GetIsMob(targetEntity)
	if (targetEntity == nil) then
		return false;
	end
    -- Obtain the entity spawn flags..
    local flag = targetEntity.SpawnFlags;
    -- Determine the entity type
	local isMob;
    if (bit.band(flag, 0x0001) == 0x0001 or bit.band(flag, 0x0002) == 0x0002) then --players and npcs
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
        error(('Failed to load image texture: %08X (%s)'):fmt(res, d3d.get_error(res)));
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

function LimitStringLength(string, length)
	local output = '';
	for i = 1, #string do
		output = output..string[i];
		if (#output >= length) then
			break;
		end
	end
	return output;
end

local bitData;
local bitOffset;
local function UnpackBits(length)
    local value = ashita.bits.unpack_be(bitData, 0, bitOffset, length);
    bitOffset = bitOffset + length;
    return value;
end

function ParseActionPacket(e)
    if (e.id == 0x0028) then
		local actionPacket = T{};
		bitData = e.data_raw;
		bitOffset = 40;
		actionPacket.UserId = UnpackBits(32);
		actionPacket.UserIndex = GetIndexFromId(actionPacket.UserId);
		local targetCount = UnpackBits(6);
		--Unknown 4 bits
		bitOffset = bitOffset + 4;
		actionPacket.Type = UnpackBits(4);
		actionPacket.Id = UnpackBits(32);
		--Unknown 32 bits
		bitOffset = bitOffset + 32;

		actionPacket.Targets = T{};
		for i = 1,targetCount do
			local target = T{};
			target.Id = UnpackBits(32);
			local actionCount = UnpackBits(4);
			target.Actions = T{};
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
			actionPacket.Targets:append(target);
		end
		
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

function GetIndexFromId(serverId)
    local index = bit.band(serverId, 0x7FF);
    local entMgr = AshitaCore:GetMemoryManager():GetEntity();
    if (entMgr:GetServerId(index) == serverId) then
        return index;
    end
    for i = 1,2303 do
        if entMgr:GetServerId(i) == serverId then
            return i;
        end
    end
    return 0;
end

function has_value (tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end