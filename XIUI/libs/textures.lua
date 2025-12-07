--[[
* XIUI Texture Utilities
* Texture loading via D3D8
]]--

require('common');
local ffi = require('ffi');
local d3d = require('d3d8');
local C = ffi.C;

-- Import memory module for D3D device access
local memoryLib = require('libs.memory');

local M = {};

-- ========================================
-- Texture Loading
-- ========================================

function M.LoadTexture(textureName)
    -- Get D3D device lazily for Linux/Wine compatibility
    local device = memoryLib.GetD3D8Device();
    if (device == nil) then return nil; end

    local textures = T{}
    -- Load the texture for usage
    local texture_ptr = ffi.new('IDirect3DTexture8*[1]');
    local res = C.D3DXCreateTextureFromFileA(device, string.format('%s/assets/%s.png', addon.path, textureName), texture_ptr);
    if (res ~= C.S_OK) then
        return nil;
    end;
    textures.image = ffi.new('IDirect3DTexture8*', texture_ptr[0]);
    d3d.gc_safe_release(textures.image);

    return textures;
end

-- Load texture with custom extension (for jpg, bmp, etc.)
function M.LoadTextureWithExt(textureName, ext)
    -- Get D3D device lazily for Linux/Wine compatibility
    local device = memoryLib.GetD3D8Device();
    if (device == nil) then return nil; end

    local textures = T{}
    -- Load the texture for usage
    local texture_ptr = ffi.new('IDirect3DTexture8*[1]');
    local res = C.D3DXCreateTextureFromFileA(device, string.format('%s/assets/%s.%s', addon.path, textureName, ext), texture_ptr);
    if (res ~= C.S_OK) then
        return nil;
    end;
    textures.image = ffi.new('IDirect3DTexture8*', texture_ptr[0]);
    d3d.gc_safe_release(textures.image);

    return textures;
end

return M;
