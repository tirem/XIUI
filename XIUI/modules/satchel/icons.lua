local ffi = require('ffi')
local d3d8 = require('d3d8')

local C = ffi.C

local icons = {}

local d3d8dev = nil
local runtime_file_icons_allowed = false

local function get_device()
    if d3d8dev == nil then
        d3d8dev = d3d8.get_device()
    end
    return d3d8dev
end

icons.get_device = get_device

function icons.set_runtime_file_icons_allowed(allowed)
    runtime_file_icons_allowed = allowed == true
end

function icons.runtime_file_icons_allowed()
    return runtime_file_icons_allowed
end

function icons.tex_ptr(tex)
    if tex == nil or tex == false then
        return nil
    end

    local ok, ptr = pcall(function()
        return tonumber(ffi.cast('uint32_t', tex))
    end)
    if not ok or not ptr or ptr == 0 then
        return nil
    end

    return ptr
end

function icons.load_item_icon(satchel, item_id)
    if not item_id or item_id <= 0 then
        return nil
    end

    local cached = satchel.icons[item_id]
    if cached ~= nil then
        return cached or nil
    end

    local device = get_device()
    if device == nil then
        return nil
    end

    local ok, item = pcall(function()
        return AshitaCore:GetResourceManager():GetItemById(item_id)
    end)
    if not ok or not item or not item.Bitmap or item.ImageSize == 0 then
        satchel.icons[item_id] = false
        return nil
    end

    local texture_ptr = ffi.new('IDirect3DTexture8*[1]')
    local result = C.D3DXCreateTextureFromFileInMemoryEx(
        device,
        item.Bitmap,
        item.ImageSize,
        0xFFFFFFFF,
        0xFFFFFFFF,
        1,
        0,
        C.D3DFMT_A8R8G8B8,
        C.D3DPOOL_MANAGED,
        C.D3DX_DEFAULT,
        C.D3DX_DEFAULT,
        0xFF000000,
        nil,
        nil,
        texture_ptr
    )

    if result ~= C.S_OK then
        satchel.icons[item_id] = false
        return nil
    end

    local tex = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', texture_ptr[0]))
    satchel.icons[item_id] = tex
    return tex
end

function icons.load_file_icon(satchel, key, path)
    if not satchel or not key or not path or path == '' then
        return nil
    end

    local device = get_device()
    if device == nil then
        return nil
    end

    satchel.file_icons = satchel.file_icons or {}
    local cached = satchel.file_icons[key]
    if cached ~= nil then
        return cached or nil
    end

    if not runtime_file_icons_allowed then
        return nil
    end

    local texture_ptr = ffi.new('IDirect3DTexture8*[1]')
    local result = C.D3DXCreateTextureFromFileA(device, path, texture_ptr)
    if result ~= C.S_OK then
        satchel.file_icons[key] = false
        return nil
    end

    local tex = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', texture_ptr[0]))
    satchel.file_icons[key] = tex
    return tex
end

return icons
