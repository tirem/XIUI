-- Pulled from statustimers - Copyright (c) 2022 Heals

-------------------------------------------------------------------------------
-- imports
-------------------------------------------------------------------------------
local ffi = require('ffi');
local imgui = require('imgui');
local encoding = require('submodules.gdifonts.encoding');
local TextureManager = require('libs.texturemanager');

-- Party buffs table, populated by packet 0x076 via ReadPartyBuffsFromPacket()
local partyBuffs = {};

-------------------------------------------------------------------------------
-- exported functions
-------------------------------------------------------------------------------
local statusHandler = {};

-- return a list of all sub directories
---@return table theme_paths
statusHandler.get_job_theme_paths = function()
    local path = ('%s\\addons\\%s\\assets\\jobs\\'):fmt(AshitaCore:GetInstallPath(), 'XIUI');
    local directories = ashita.fs.get_directory(path);
    if (directories ~= nil) then
        directories[#directories+1] = '-None-';
        return directories;
    end
    return T{'-None-'};
end

-- render the tooltip for a specific status id
---@param status number the status id
---@param is_target boolean if true, don't show '(right click to cancel)' hint
statusHandler.render_tooltip = function(status)
    if (status == nil or status < 1 or status > 0x3FF or status == 255) then
        return;
    end

    local resMan = AshitaCore:GetResourceManager();
    local info = resMan:GetStatusIconByIndex(status);
    local name = resMan:GetString('buffs.names', status);
    if (name ~= nil and info ~= nil) then
        imgui.BeginTooltip();
            imgui.Text(('%s (#%d)'):fmt(encoding:ShiftJIS_To_UTF8(name, true), status));
            if (info.Description[1] ~= nil) then
                imgui.Text(encoding:ShiftJIS_To_UTF8(info.Description[1], true));
            end
        imgui.EndTooltip();
    end
end

-- return a list of all sub directories
---@return table theme_paths
statusHandler.get_status_theme_paths = function()
    local path = ('%s\\addons\\%s\\assets\\status\\'):fmt(AshitaCore:GetInstallPath(), 'XIUI');
    local directories = ashita.fs.get_directory(path);
    if (directories ~= nil) then
        directories[#directories+1] = '-Default-';
        return directories;
    end
    return T{'-Default-'};
end 

-- return a list of all sub directories
---@return table theme_paths
statusHandler.get_background_paths = function()
    local path = ('%s\\addons\\%s\\assets\\backgrounds\\'):fmt(AshitaCore:GetInstallPath(), 'XIUI');
    local directories = ashita.fs.get_dir(path, '.*.png', true);
    if (directories ~= nil) then
        local backgrounds = { '-None-' };
        for _, filename in ipairs(directories) do
            local bg_name = filename:match('(.+)%-bg.png');
            if bg_name ~= nil then
                table.insert(backgrounds, bg_name);
            end
        end
        return backgrounds;
    end
    return T{};
end 

-- return a list of all sub directories
---@return table theme_paths
statusHandler.get_cursor_paths = function()
    local path = ('%s\\addons\\%s\\assets\\cursors\\'):fmt(AshitaCore:GetInstallPath(), 'XIUI');
    local directories = ashita.fs.get_dir(path, '.*.png', true);
    if (directories ~= nil) then
        return directories;
    end
    return T{};
end 

-- return an image pointer for a status_id for use with imgui.Image
---@param status_id number the status id number of the requested icon
---@return number texture_ptr_id a number representing the texture_ptr or nil
statusHandler.get_icon_image = function(status_id)
    local texture = TextureManager.getStatusIcon(status_id, nil);
    return TextureManager.getTexturePtr(texture);
end

-- return an image pointer for a status_id for use with imgui.Image
---@param theme string the name of the theme directory
---@param status_id number the status id number of the requested icon
---@return number texture_ptr_id a number representing the texture_ptr or nil
statusHandler.get_icon_from_theme = function(theme, status_id)
    local texture = TextureManager.getStatusIcon(status_id, theme);
    return TextureManager.getTexturePtr(texture);
end

-- reset the icon cache and release all resources
-- Note: Cache is now managed centrally by TextureManager
statusHandler.clear_cache = function()
    -- Status icon cache is managed by TextureManager
    -- This function is kept for backwards compatibility
    -- TextureManager.clearCategory('status_icons') can be called if needed
end;

-- Clear status icon cache on zone change to prevent unbounded accumulation
-- Preserves job icons since those are reused across zones
-- Preserves buff/debuff background icons as they're constant
statusHandler.clear_zone_cache = function()
    icon_cache = T{};
end;

-- return a table of status ids for a party member based on server id.
---@param server_id number the party memer or target server id to check
---@return table status_ids a list of the targets status ids or nil
statusHandler.get_member_status = function(server_id)
    return partyBuffs[server_id];
end

statusHandler.GetBackground = function(isBuff)
    local textureName = isBuff and "BuffIcon" or "DebuffIcon";
    local texture = TextureManager.getFileTexture(textureName);
    return TextureManager.getTexturePtr(texture);
end

statusHandler.GetJobIcon = function(jobIdx)
    if (jobIdx == nil or jobIdx == 0 or jobIdx == -1) then
        return nil;
    end
    local theme = gConfig.jobIconTheme or 'Classic';
    local texture = TextureManager.getJobIcon(jobIdx, theme);
    return TextureManager.getTexturePtr(texture);
end

--Call with incoming packet 0x076
statusHandler.ReadPartyBuffsFromPacket = function(e)
    local partyBuffTable = {};
    for i = 0,4 do
        local memberOffset = 0x04 + (0x30 * i) + 1;
        local memberId = struct.unpack('L', e.data, memberOffset);
        if memberId > 0 then
            local buffs = {};
            local empty = false;
            for j = 0,31 do
                if empty then
                    buffs[j + 1] = -1;
                else
                    --This is at offset 8 from member start.. memberoffset is using +1 for the lua struct.unpacks
                    local highBits = bit.lshift(ashita.bits.unpack_be(e.data_raw, memberOffset + 7, j * 2, 2), 8);
                    local lowBits = struct.unpack('B', e.data, memberOffset + 0x10 + j);
                    local buff = highBits + lowBits;
                    if (buff == 255) then
                        buffs[j + 1] = -1;
                        empty = true;
                    else
                        buffs[j + 1] = buff;
                    end
                end
            end
            partyBuffTable[memberId] = buffs;
        end
    end
    partyBuffs =  partyBuffTable;
end

return statusHandler;
