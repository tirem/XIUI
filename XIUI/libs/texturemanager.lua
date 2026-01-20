--[[
* XIUI TextureManager
* Centralized texture loading and caching with LRU eviction
* Follows FontManager pattern for consistent API design
*
* Categories:
*   - item_icons: Item icons from game resources (treasure pool, notifications)
*   - status_icons: Status effect icons (buffs/debuffs)
*   - job_icons: Job icons from theme folders
*   - assets: Static textures from assets/ folder (no eviction)
*
* Usage:
*   local TextureManager = require('libs.texturemanager');
*   local texture = TextureManager.getItemIcon(itemId);
*   local ptr = TextureManager.getTexturePtr(texture);
]]--

require('common');
local ffi = require('ffi');
local d3d8 = require('d3d8');
local memoryLib = require('libs.memory');

local M = {};

-- ============================================
-- Category Configuration
-- ============================================

local CATEGORY_CONFIG = {
    item_icons = {
        maxSize = 50,
        evictionCount = 10,
        clearOnZone = true,
    },
    status_icons = {
        maxSize = 100,
        evictionCount = 20,
        clearOnZone = false,
    },
    job_icons = {
        maxSize = 30,
        evictionCount = 0,
        clearOnZone = false,
    },
    custom_icons = {
        maxSize = 250,  -- ~2 pages of icons cached
        evictionCount = 50,
        clearOnZone = false,
    },
    assets = {
        maxSize = 0,  -- No limit
        evictionCount = 0,
        clearOnZone = false,
    },
};

-- ============================================
-- Internal State
-- ============================================

-- Hash table for O(1) lookup by key
local texturesByKey = {};

-- Per-category arrays for LRU eviction tracking
local categoryEntries = {
    item_icons = {},
    status_icons = {},
    job_icons = {},
    custom_icons = {},
    assets = {},
};

-- Statistics
local stats = {
    hits = 0,
    misses = 0,
    evictions = 0,
    totalCreated = 0,
    byCategory = {
        item_icons = { hits = 0, misses = 0, evictions = 0 },
        status_icons = { hits = 0, misses = 0, evictions = 0 },
        job_icons = { hits = 0, misses = 0, evictions = 0 },
        custom_icons = { hits = 0, misses = 0, evictions = 0 },
        assets = { hits = 0, misses = 0, evictions = 0 },
    },
};

-- Status icon ID overrides (from statushandler.lua)
-- Handles incorrectly mapped icons in game resources
local STATUS_ID_OVERRIDES = {
    [623] = 62,  -- Rampart shows BCNM icon, use Sentinel instead
};

-- ============================================
-- Internal Functions
-- ============================================

-- Evict oldest entries when category exceeds max size
local function evictIfNeeded(category)
    local config = CATEGORY_CONFIG[category];
    if config == nil or config.maxSize <= 0 then return; end

    local entries = categoryEntries[category];
    if entries == nil or #entries <= config.maxSize then return; end

    -- Sort by lastUsed (oldest first)
    table.sort(entries, function(a, b)
        return (a.lastUsed or 0) < (b.lastUsed or 0);
    end);

    -- Evict oldest entries
    local toEvict = math.min(
        config.evictionCount,
        #entries - config.maxSize + config.evictionCount
    );

    for i = 1, toEvict do
        local entry = entries[1];
        if entry then
            -- Remove from hash table
            texturesByKey[entry.key] = nil;
            table.remove(entries, 1);
            stats.evictions = stats.evictions + 1;
            if stats.byCategory[category] then
                stats.byCategory[category].evictions = (stats.byCategory[category].evictions or 0) + 1;
            end
        end
    end
end

-- Core get-or-create function
local function getOrCreate(key, loader, category)
    category = category or 'assets';

    -- O(1) lookup
    local entry = texturesByKey[key];
    if entry then
        entry.lastUsed = os.clock();
        stats.hits = stats.hits + 1;
        if stats.byCategory[category] then
            stats.byCategory[category].hits = stats.byCategory[category].hits + 1;
        end
        return entry.texture;
    end

    -- Cache miss - load texture
    stats.misses = stats.misses + 1;
    if stats.byCategory[category] then
        stats.byCategory[category].misses = stats.byCategory[category].misses + 1;
    end

    local success, texture = pcall(loader);
    if not success or texture == nil then
        return nil;
    end

    -- Create entry
    local newEntry = {
        key = key,
        category = category,
        texture = texture,
        lastUsed = os.clock(),
        createdAt = os.clock(),
    };

    -- Store in hash table
    texturesByKey[key] = newEntry;
    stats.totalCreated = stats.totalCreated + 1;

    -- Add to category array (for eviction tracking)
    local config = CATEGORY_CONFIG[category];
    if config and config.maxSize > 0 then
        table.insert(categoryEntries[category], newEntry);
        evictIfNeeded(category);
    elseif categoryEntries[category] then
        -- Still track for cleanup even if no eviction
        table.insert(categoryEntries[category], newEntry);
    end

    return texture;
end

-- ============================================
-- Texture Loading Helpers
-- ============================================

-- Load item icon from game resources (bitmap in memory)
local function loadItemIconFromResource(itemId)
    local device = memoryLib.GetD3D8Device();
    if device == nil then return nil; end

    local item = AshitaCore:GetResourceManager():GetItemById(itemId);
    if item == nil or item.Bitmap == nil or item.ImageSize == nil or item.ImageSize <= 0 then
        return nil;
    end

    local dx_texture_ptr = ffi.new('IDirect3DTexture8*[1]');
    local res = ffi.C.D3DXCreateTextureFromFileInMemoryEx(
        device, item.Bitmap, item.ImageSize,
        0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
        ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED,
        ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT,
        0xFF000000, nil, nil, dx_texture_ptr
    );

    if res ~= ffi.C.S_OK then return nil; end

    return {
        image = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', dx_texture_ptr[0]))
    };
end

-- Load status icon from game resources
local function loadStatusIconFromResource(statusId)
    local device = memoryLib.GetD3D8Device();
    if device == nil then return nil; end

    -- Apply ID overrides
    if STATUS_ID_OVERRIDES[statusId] then
        statusId = STATUS_ID_OVERRIDES[statusId];
    end

    local icon = AshitaCore:GetResourceManager():GetStatusIconByIndex(statusId);
    if icon == nil or icon.Bitmap == nil or icon.ImageSize == nil or icon.ImageSize <= 0 then
        return nil;
    end

    local dx_texture_ptr = ffi.new('IDirect3DTexture8*[1]');
    local res = ffi.C.D3DXCreateTextureFromFileInMemoryEx(
        device, icon.Bitmap, icon.ImageSize,
        0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
        ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED,
        ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT,
        0xFF000000, nil, nil, dx_texture_ptr
    );

    if res ~= ffi.C.S_OK then return nil; end

    return {
        image = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', dx_texture_ptr[0]))
    };
end

-- Load status icon from theme folder
local function loadStatusIconFromTheme(theme, statusId)
    local device = memoryLib.GetD3D8Device();
    if device == nil then return nil; end

    -- Apply ID overrides
    if STATUS_ID_OVERRIDES[statusId] then
        statusId = STATUS_ID_OVERRIDES[statusId];
    end

    -- Try different extensions
    local extensions = {'.png', '.jpg', '.jpeg', '.bmp'};
    local iconPath = nil;
    local supportsAlpha = false;

    for _, ext in ipairs(extensions) do
        local testPath = string.format('%s/assets/status/%s/%d%s', addon.path, theme, statusId, ext);
        if ashita.fs.exists(testPath) then
            iconPath = testPath;
            supportsAlpha = (ext == '.png');
            break;
        end
    end

    if iconPath == nil then
        -- Fallback to game resources
        return loadStatusIconFromResource(statusId);
    end

    local dx_texture_ptr = ffi.new('IDirect3DTexture8*[1]');
    local res;

    if supportsAlpha then
        res = ffi.C.D3DXCreateTextureFromFileA(device, iconPath, dx_texture_ptr);
    else
        res = ffi.C.D3DXCreateTextureFromFileExA(
            device, iconPath,
            0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
            ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED,
            ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT,
            0xFF000000, nil, nil, dx_texture_ptr
        );
    end

    if res ~= ffi.C.S_OK then
        return loadStatusIconFromResource(statusId);
    end

    return {
        image = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', dx_texture_ptr[0]))
    };
end

-- Load texture from file path
local function loadTextureFromFile(path)
    local device = memoryLib.GetD3D8Device();
    if device == nil then return nil; end

    local fullPath;
    if path:sub(1, 1) == '/' or path:sub(1, 1) == '\\' or path:match('^%a:') then
        -- Absolute path
        fullPath = path;
    else
        -- Relative to assets folder
        fullPath = string.format('%s/assets/%s', addon.path, path);
    end

    -- Add .png extension if no extension provided
    if not fullPath:match('%.[^/\\]+$') then
        fullPath = fullPath .. '.png';
    end

    local dx_texture_ptr = ffi.new('IDirect3DTexture8*[1]');
    local res = ffi.C.D3DXCreateTextureFromFileA(device, fullPath, dx_texture_ptr);

    if res ~= ffi.C.S_OK then return nil; end

    return {
        image = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', dx_texture_ptr[0]))
    };
end

-- ============================================
-- Public API
-- ============================================

-- Get item icon by item ID
-- @param itemId number - The item ID
-- @return table|nil - Texture table with .image field, or nil
function M.getItemIcon(itemId)
    if itemId == nil or itemId == 0 or itemId == -1 or itemId == 65535 then
        return nil;
    end

    local key = 'item_' .. tostring(itemId);
    return getOrCreate(key, function()
        return loadItemIconFromResource(itemId);
    end, 'item_icons');
end

-- Get status icon by status ID
-- @param statusId number - The status effect ID (0-1023)
-- @param theme string|nil - Theme name, or nil for default game resources
-- @return table|nil - Texture table with .image field, or nil
function M.getStatusIcon(statusId, theme)
    if statusId == nil or statusId < 0 or statusId > 0x3FF then
        return nil;
    end

    local themeKey = theme or 'default';
    local key = 'status_' .. tostring(statusId) .. '_' .. themeKey;

    return getOrCreate(key, function()
        if theme and theme ~= '-Default-' and theme ~= '' then
            return loadStatusIconFromTheme(theme, statusId);
        else
            return loadStatusIconFromResource(statusId);
        end
    end, 'status_icons');
end

-- Get job icon by job index
-- @param jobIdx number - The job index (1-22)
-- @param theme string - Theme folder name (e.g., "Classic", "FFXI", "FFXIV")
-- @return table|nil - Texture table with .image field, or nil
function M.getJobIcon(jobIdx, theme)
    if jobIdx == nil or type(jobIdx) ~= 'number' or jobIdx < 1 or jobIdx > 22 then
        return nil;
    end

    theme = theme or 'Classic';
    local jobAbbrs = {
        'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF',
        'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM',
        'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP',
        'DNC', 'SCH', 'GEO', 'RUN'
    };

    local jobStr = jobAbbrs[jobIdx];
    if jobStr == nil then return nil; end

    local key = 'job_' .. jobStr .. '_' .. theme;

    return getOrCreate(key, function()
        local path = string.format('jobs/%s/%s', theme, jobStr);
        return loadTextureFromFile(path);
    end, 'job_icons');
end

-- Get texture from file path (relative to assets/ or absolute)
-- @param path string - File path (with or without extension)
-- @return table|nil - Texture table with .image field, or nil
function M.getFileTexture(path)
    if path == nil or path == '' then
        return nil;
    end

    local key = 'file_' .. path;
    return getOrCreate(key, function()
        return loadTextureFromFile(path);
    end, 'assets');
end

-- Get custom icon from hotbar custom icons directory
-- @param relativePath string - Path relative to assets/hotbar/custom/
-- @return table|nil - Texture table with .image field, or nil
function M.getCustomIcon(relativePath)
    if relativePath == nil or relativePath == '' then
        return nil;
    end

    local key = 'custom_' .. relativePath;
    return getOrCreate(key, function()
        local fullPath = string.format('%s/assets/hotbar/custom/%s', addon.path, relativePath);
        return loadTextureFromFile(fullPath);
    end, 'custom_icons');
end

-- Generic get function with custom loader
-- @param key string - Unique cache key
-- @param loader function - Function that returns texture table
-- @param category string|nil - Category for cache limits (default: 'assets')
-- @return table|nil - Texture table with .image field, or nil
function M.get(key, loader, category)
    return getOrCreate(key, loader, category);
end

-- ============================================
-- Utility Functions
-- ============================================

-- Get texture pointer as number for ImGui
-- @param texture table - Texture table with .image field
-- @return number|nil - Pointer as number, or nil
function M.getTexturePtr(texture)
    if texture and texture.image then
        return tonumber(ffi.cast("uint32_t", texture.image));
    end
    return nil;
end

-- Get dimensions from a loaded texture
-- @param texture table - Texture table with .image field
-- @param defaultWidth number - Default width if unavailable
-- @param defaultHeight number - Default height if unavailable
-- @return number, number - Width and height
function M.getTextureDimensions(texture, defaultWidth, defaultHeight)
    if texture == nil or texture.image == nil then
        return defaultWidth or 64, defaultHeight or 64;
    end

    local texture_ptr = ffi.cast('IDirect3DTexture8*', texture.image);
    local res, desc = texture_ptr:GetLevelDesc(0);

    if desc ~= nil then
        return desc.Width, desc.Height;
    end

    return defaultWidth or 64, defaultHeight or 64;
end

-- ============================================
-- Cache Management
-- ============================================

-- Clear specific category
-- @param category string - Category name to clear
function M.clearCategory(category)
    local entries = categoryEntries[category];
    if entries then
        for _, entry in ipairs(entries) do
            texturesByKey[entry.key] = nil;
        end
        categoryEntries[category] = {};
    end

    -- Force garbage collection to release D3D resources
    collectgarbage('collect');
end

-- Clear categories that should be cleared on zone change
function M.clearOnZone()
    for category, config in pairs(CATEGORY_CONFIG) do
        if config.clearOnZone then
            M.clearCategory(category);
        end
    end
end

-- Clear all caches (call on addon unload)
function M.clear()
    -- Clear all tables
    texturesByKey = {};
    for category, _ in pairs(categoryEntries) do
        categoryEntries[category] = {};
    end

    -- Reset stats
    stats = {
        hits = 0,
        misses = 0,
        evictions = 0,
        totalCreated = 0,
        byCategory = {
            item_icons = { hits = 0, misses = 0, evictions = 0 },
            status_icons = { hits = 0, misses = 0, evictions = 0 },
            job_icons = { hits = 0, misses = 0, evictions = 0 },
            custom_icons = { hits = 0, misses = 0, evictions = 0 },
            assets = { hits = 0, misses = 0, evictions = 0 },
        },
    };

    -- Force garbage collection
    collectgarbage('collect');
end

-- ============================================
-- Statistics
-- ============================================

-- Get cache statistics
-- @return table - Statistics table
function M.getStats()
    local result = {
        totalHits = stats.hits,
        totalMisses = stats.misses,
        totalEvictions = stats.evictions,
        totalCreated = stats.totalCreated,
        hitRate = 0,
        categories = {},
    };

    local totalRequests = stats.hits + stats.misses;
    if totalRequests > 0 then
        result.hitRate = (stats.hits / totalRequests) * 100;
    end

    for category, config in pairs(CATEGORY_CONFIG) do
        local entries = categoryEntries[category] or {};
        local catStats = stats.byCategory[category] or {};
        result.categories[category] = {
            size = #entries,
            maxSize = config.maxSize,
            hits = catStats.hits or 0,
            misses = catStats.misses or 0,
            evictions = catStats.evictions or 0,
        };
    end

    return result;
end

-- Print cache statistics to chat
function M.printStats()
    local s = M.getStats();

    print('[XIUI] TextureManager Cache Stats:');
    print(string.format('  Total: %d hits, %d misses (%.1f%% hit rate)',
        s.totalHits, s.totalMisses, s.hitRate));
    print(string.format('  Created: %d, Evictions: %d', s.totalCreated, s.totalEvictions));

    for category, catStats in pairs(s.categories) do
        local maxStr = catStats.maxSize > 0 and tostring(catStats.maxSize) or 'unlimited';
        print(string.format('  [%s] %d/%s (hits: %d, misses: %d, evictions: %d)',
            category, catStats.size, maxStr, catStats.hits, catStats.misses, catStats.evictions));
    end
end

return M;
