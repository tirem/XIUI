# Item Icon Loading Research for XIUI

## Executive Summary

**Can we display item icons in XIUI?**

**Yes, and it's simple!** Ashita's ResourceManager provides direct access to item icons from the game's resources via `GetItemById()`. This is the same proven pattern already used for status icons in the codebase.

---

## Solution: Game Resources (Recommended)

Ashita provides built-in access to item data including icons:

```lua
local item = AshitaCore:GetResourceManager():GetItemById(itemId);
if (item ~= nil) then
    -- item.Bitmap     - Holds the bitmap data
    -- item.ImageSize  - Size of the bitmap array
end
```

This is identical to how status icons work with `GetStatusIconByIndex()`.

---

## Implementation

### Basic Item Icon Loader

```lua
local ffi = require('ffi');
local d3d8 = require('d3d8');

-- Cache for loaded item icons
local itemIconCache = T{};

-- Load an item icon from game resources
---@param item_id number the item id to load the icon for
---@return ffi.cdata* texture_ptr the loaded texture object or nil on error
local function load_item_icon(item_id)
    if (item_id == nil or item_id < 0) then
        return nil;
    end

    -- Check cache first
    if (itemIconCache[item_id] ~= nil) then
        return itemIconCache[item_id];
    end

    local device = GetD3D8Device();
    if (device == nil) then return nil; end

    local item = AshitaCore:GetResourceManager():GetItemById(item_id);
    if (item ~= nil and item.Bitmap ~= nil and item.ImageSize > 0) then
        local dx_texture_ptr = ffi.new('IDirect3DTexture8*[1]');
        if (ffi.C.D3DXCreateTextureFromFileInMemoryEx(
            device,
            item.Bitmap,
            item.ImageSize,
            0xFFFFFFFF,         -- Width (default)
            0xFFFFFFFF,         -- Height (default)
            1,                  -- MipLevels
            0,                  -- Usage
            ffi.C.D3DFMT_A8R8G8B8,
            ffi.C.D3DPOOL_MANAGED,
            ffi.C.D3DX_DEFAULT, -- Filter
            ffi.C.D3DX_DEFAULT, -- MipFilter
            0xFF000000,         -- ColorKey (black = transparent)
            nil,                -- pSrcInfo
            nil,                -- pPalette
            dx_texture_ptr
        ) == ffi.C.S_OK) then
            local texture = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', dx_texture_ptr[0]));
            itemIconCache[item_id] = texture;
            return texture;
        end
    end

    return nil;
end

-- Get item icon, returns cached texture or loads it
---@param item_id number the item id
---@return number|nil texture pointer as number for ImGui, or nil
local function get_item_icon(item_id)
    local texture = load_item_icon(item_id);
    if (texture ~= nil) then
        return tonumber(ffi.cast("uint32_t", texture));
    end
    return nil;
end

-- Clear the icon cache (call on unload)
local function clear_item_icon_cache()
    itemIconCache:clear();
end
```

### Usage Example

```lua
-- In your render function
local itemId = 21573;  -- Example: some item
local iconTexture = get_item_icon(itemId);

if (iconTexture ~= nil) then
    local iconSize = 32;
    imgui.Image(iconTexture, { iconSize, iconSize });
end
```

### With Tooltip

```lua
local function render_item_icon_with_tooltip(item_id, size)
    local iconTexture = get_item_icon(item_id);

    if (iconTexture ~= nil) then
        imgui.Image(iconTexture, { size, size });

        if (imgui.IsItemHovered()) then
            local item = AshitaCore:GetResourceManager():GetItemById(item_id);
            if (item ~= nil) then
                imgui.BeginTooltip();
                imgui.Text(item.Name[1] or 'Unknown');  -- English name
                -- item.Description[1] for description
                imgui.EndTooltip();
            end
        end
    end
end
```

---

## Integration with Existing Code

This follows the exact same pattern as `statushandler.lua`. You could add item icon functions to that file or create a new `itemhandler.lua`:

### Option A: Add to statushandler.lua

```lua
-- Add to statushandler.lua

local itemIconCache = T{};

local function load_item_icon_from_resource(item_id)
    if (item_id == nil or item_id < 0) then
        return nil;
    end

    local device = GetD3D8Device();
    if (device == nil) then return nil; end

    local item = AshitaCore:GetResourceManager():GetItemById(item_id);
    if (item ~= nil and item.Bitmap ~= nil) then
        local dx_texture_ptr = ffi.new('IDirect3DTexture8*[1]');
        if (ffi.C.D3DXCreateTextureFromFileInMemoryEx(device, item.Bitmap, item.ImageSize, 0xFFFFFFFF, 0xFFFFFFFF, 1, 0, ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED, ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT, 0xFF000000, nil, nil, dx_texture_ptr) == ffi.C.S_OK) then
            return d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', dx_texture_ptr[0]));
        end
    end
    return nil;
end

-- Public function
function statusHandler.get_item_icon(item_id)
    if (itemIconCache[item_id] == nil) then
        itemIconCache[item_id] = load_item_icon_from_resource(item_id);
    end

    local texture = itemIconCache[item_id];
    if (texture ~= nil) then
        return tonumber(ffi.cast("uint32_t", texture));
    end
    return nil;
end

-- Add to clear_cache()
function statusHandler.clear_cache()
    -- existing cache clearing...
    itemIconCache:clear();
end
```

### Option B: New itemhandler.lua module

Create `handlers/itemhandler.lua` following the same structure as statushandler.

---

## Why This is Better Than FFXIAH

| Game Resources | FFXIAH (Remote) |
|----------------|-----------------|
| Instant loading | Network latency |
| No dependencies | Needs HTTP library |
| Works offline | Requires internet |
| No rate limits | Could get blocked |
| Cross-platform | Platform-specific code |
| All items available | May miss some |
| Proven pattern in codebase | New implementation |

---

## Item Resource Data Available

The `GetItemById()` function returns an item object with:

| Property | Description |
|----------|-------------|
| `Bitmap` | Raw bitmap data for the icon |
| `ImageSize` | Size of the bitmap in bytes |
| `Name[0-2]` | Item names (0=JP, 1=EN, 2=DE/FR) |
| `Description[0-2]` | Item descriptions |
| `Id` | Item ID |
| `Flags` | Item flags |
| `StackSize` | Max stack size |
| `Type` | Item type |
| `Targets` | Valid targets |
| `Level` | Required level |
| `Slots` | Equipment slots |
| `Jobs` | Jobs that can use |
| ... | And more |

---

## Use Cases

This enables several features:

1. **Item Obtained Notifications** - Show icon when items drop
2. **Equipment Viewer** - Display currently equipped gear
3. **Inventory Display** - Show bag contents with icons
4. **Loot List** - Visual treasure pool
5. **Crafting Helper** - Recipe ingredient icons

---

## Performance Notes

- Icons are ~32x32 pixels (small memory footprint)
- Cache textures to avoid reloading
- Clear cache on addon unload to free VRAM
- Game resources are memory-mapped, so access is fast

---

## Sources

- Existing implementation: `handlers/statushandler.lua:50-71`
- [Ashita IResourceManager](https://wiki.ashitaxi.com/doku.php?id=addons:adk:iresourcemanager)
- [D3DXCreateTextureFromFileInMemoryEx](https://learn.microsoft.com/en-us/windows/win32/direct3d9/d3dxcreatetexturefromfileinmemoryex)
