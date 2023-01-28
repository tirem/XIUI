-- Pulled from statustimers - Copyright (c) 2022 Heals

-------------------------------------------------------------------------------
-- imports
-------------------------------------------------------------------------------
local d3d8 = require('d3d8');
local ffi = require('ffi');
-------------------------------------------------------------------------------
-- local state
-------------------------------------------------------------------------------
local d3d8_device = d3d8.get_device();
-------------------------------------------------------------------------------
-- local constants
-------------------------------------------------------------------------------
local icon_cache = T{
};

local buffIcon = nil;
local debuffIcon = nil;

local jobIcons = T{};

-- this table implements overrides for certain icons to handle
-- local buffs_table = nil;
local id_overrides = T{
};
-------------------------------------------------------------------------------
-- local functions
-------------------------------------------------------------------------------

-- load a dummy icon placeholder for a missing status and return a texture pointer
---@return ffi.cdata* texture_ptr the loaded texture object or nil on error
local function load_dummy_icon()
    local icon_path = ('%s\\addons\\%s\\ladybug.png'):fmt(AshitaCore:GetInstallPath(), 'statustimers');
    local dx_texture_ptr = ffi.new('IDirect3DTexture8*[1]');

    if (ffi.C.D3DXCreateTextureFromFileA(d3d8_device, icon_path, dx_texture_ptr) == ffi.C.S_OK) then
        return d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', dx_texture_ptr[0]));
    end

    return nil;
end

-- load a status icon from the games own resources and return a texture pointer
---@param status_id number the status id to load the icon for
---@return ffi.cdata* texture_ptr the loaded texture object or nil on error
local function load_status_icon_from_resource(status_id)
    if (status_id == nil or status_id < 0 or status_id > 0x3FF) then
        return nil;
    end

    local id_key = ("_%d"):fmt(status_id);
    if (id_overrides:haskey(id_key)) then
        status_id = id_overrides[id_key];
    end

    local icon = AshitaCore:GetResourceManager():GetStatusIconByIndex(status_id);
    if (icon ~= nil) then
        local dx_texture_ptr = ffi.new('IDirect3DTexture8*[1]');
        if (ffi.C.D3DXCreateTextureFromFileInMemoryEx(d3d8_device, icon.Bitmap, icon.ImageSize, 0xFFFFFFFF, 0xFFFFFFFF, 1, 0, ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED, ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT, 0xFF000000, nil, nil, dx_texture_ptr) == ffi.C.S_OK) then
            return d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', dx_texture_ptr[0]));
        end
    end
    return load_dummy_icon();
end

-- load a status icon from a theme pack and return a texture pointer
---@param theme string path to the theme's root directory
---@param status_id number the status id to load the icon for
---@return ffi.cdata* texture_ptr the loaded texture object or nil on error
local function load_status_icon_from_theme(theme, status_id)
    if (status_id == nil or status_id < 0 or status_id > 0x3FF) then
        return nil;
    end

    local icon_path = nil;
    local supports_alpha = false;
    T{'.png', '.jpg', '.jpeg', '.bmp'}:forieach(function(ext, _)
        if (icon_path ~= nil) then
            return;
        end

        supports_alpha = ext == '.png';
        icon_path = ('%s\\assets\\%s\\%d'):append(ext):fmt(addon.path, theme, status_id);
        local handle = io.open(icon_path, 'r');
        if (handle ~= nil) then
            handle.close();
        else
            icon_path = nil;
        end
    end);

    if (icon_path == nil) then
        -- fallback to internal icon resources
        return load_status_icon_from_resource(status_id);
    end

    local dx_texture_ptr = ffi.new('IDirect3DTexture8*[1]');
    if (supports_alpha) then
        -- use the native transaparency
        if (ffi.C.D3DXCreateTextureFromFileA(d3d8_device, icon_path, dx_texture_ptr) == ffi.C.S_OK) then
            return d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', dx_texture_ptr[0]));
        end
    else
        -- use black as colour-key for transparency
        if (ffi.C.D3DXCreateTextureFromFileExA(d3d8_device, icon_path, 0xFFFFFFFF, 0xFFFFFFFF, 1, 0, ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED, ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT, 0xFF000000, nil, nil, dx_texture_ptr) == ffi.C.S_OK) then
            return d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', dx_texture_ptr[0]));
        end
    end

    return load_dummy_icon();
end

-------------------------------------------------------------------------------
-- exported functions
-------------------------------------------------------------------------------
local statusHandler = {};

-- return an image pointer for a status_id for use with imgui.Image
---@param status_id number the status id number of the requested icon
---@return number texture_ptr_id a number representing the texture_ptr or nil
statusHandler.get_icon_image = function(status_id)
    if (not icon_cache:haskey(status_id)) then
        local tex_ptr = load_status_icon_from_resource(status_id);
        if (tex_ptr == nil) then
            return nil;
        end
        icon_cache[status_id] = tex_ptr;
    end
    return tonumber(ffi.cast("uint32_t", icon_cache[status_id]));
end

-- return an image pointer for a status_id for use with imgui.Image
---@param theme string the name of the theme directory
---@param status_id number the status id number of the requested icon
---@return number texture_ptr_id a number representing the texture_ptr or nil
statusHandler.get_icon_from_theme = function(theme, status_id)
    if (not icon_cache:haskey(status_id)) then
        local tex_ptr = load_status_icon_from_theme(theme, status_id);
        if (tex_ptr == nil) then
            return nil;
        end
        icon_cache[status_id] = tex_ptr;
    end
    return tonumber(ffi.cast("uint32_t", icon_cache[status_id]));
end

-- return index of the currently active theme in module.get_theme_paths()
---@return number theme_index
statusHandler.get_theme_index = function(theme)
    local paths = module.get_theme_paths();
    for i = 1,#paths,1 do
        if (paths[i] == theme) then
            return i;
        end
    end
    return nil;
end

-- reset the icon cache and release all resources
statusHandler.clear_cache = function()
    icon_cache = T{};
    buffIcon = nil;
    debuffIcon = nil;
    jobIcons = T{};
end;


statusHandler.get_status_name = function(status_id)
    return AshitaCore:GetResourceManager():GetString(compat.buffs_table(), status_id);
end

-- return a table of status ids for a party member based on server id.
---@param server_id number the party memer or target server id to check
---@return table status_ids a list of the targets status ids or nil
statusHandler.get_member_status = function(server_id)
    local party = AshitaCore:GetMemoryManager():GetParty();
    if (party == nil or not valid_server_id(server_id)) then
        return nil;
    end

    -- try and find a party member with a matching server id
    for i = 0,4,1 do
        if (party:GetStatusIconsServerId(i) == server_id) then
            local icons_lo = party:GetStatusIcons(i);
            local icons_hi = party:GetStatusIconsBitMask(i);
            local status_ids = T{};

            for j = 0,31,1 do
                --[[ FIXME: lua doesn't handle 64bit return values properly..
                --   FIXME: the next lines are a workaround by Thorny that cover most but not all cases..
                --   FIXME: .. to try and retrieve the high bits of the buff id.
                --   TODO:  revesit this once atom0s adjusted the API.
                --]]
                local high_bits;
                if j < 16 then
                    high_bits = bit.lshift(bit.band(bit.rshift(icons_hi, 2* j), 3), 8);
                else
                    local buffer = math.floor(icons_hi / 0xffffffff);
                    high_bits = bit.lshift(bit.band(bit.rshift(buffer, 2 * (j - 16)), 3), 8);
                end
                local buff_id = icons_lo[j+1] + high_bits;
                if (buff_id ~= 255) then
                    status_ids[#status_ids + 1] = buff_id;
                end
            end

            if (next(status_ids)) then
                return status_ids;
            end
            break;
        end
    end
    return nil;
end

statusHandler.GetBackground = function(isBuff)
    if (isBuff) then
        if (buffIcon == nil) then
            buffIcon = LoadTexture("BuffIcon")
        end
        return tonumber(ffi.cast("uint32_t", buffIcon.image));
    else
        if (debuffIcon == nil) then
            debuffIcon = LoadTexture("DebuffIcon")
        end
        return tonumber(ffi.cast("uint32_t", debuffIcon.image));
    end
end


statusHandler.GetJobIcon = function(jobIdx)

    if (jobIdx == nil or jobIdx == 0 or jobIdx == -1) then
        return nil;
    end

    local jobStr = AshitaCore:GetResourceManager():GetString("jobs.names_abbr", jobIdx);

    if (jobIcons[jobStr] == nil) then
        jobIcons[jobStr] = LoadTexture(string.format('%s/%s', 'jobs', jobStr))
    end

    return tonumber(ffi.cast("uint32_t", jobIcons[jobStr].image));
end

return statusHandler;
