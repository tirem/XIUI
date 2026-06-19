local ffi = require('ffi')
local d3d8 = require('d3d8')

local d3d8dev = d3d8.get_device()
local C = ffi.C

local icons = {}

function icons.tex_ptr(tex)
    return tonumber(ffi.cast('uint32_t', tex))
end

function icons.load_item_icon(satchel, item_id)
    if not item_id or item_id <= 0 then
        return nil
    end

    local cached = satchel.icons[item_id]
    if cached ~= nil then
        return cached or nil
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
        d3d8dev,
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

    satchel.file_icons = satchel.file_icons or {}
    local cached = satchel.file_icons[key]
    if cached ~= nil then
        return cached or nil
    end

    local texture_ptr = ffi.new('IDirect3DTexture8*[1]')
    local result = C.D3DXCreateTextureFromFileA(d3d8dev, path, texture_ptr)
    if result ~= C.S_OK then
        satchel.file_icons[key] = false
        return nil
    end

    local tex = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', texture_ptr[0]))
    satchel.file_icons[key] = tex
    return tex
end

return icons
