--[[
* XIUI Hotbar - Macro Palette Module
* Provides a visual grid of user-created macros that can be dragged to hotbar slots
]]--

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local ffi = require('ffi');
local data = require('modules.hotbar.data');
local actions = require('modules.hotbar.actions');
local textures = require('modules.hotbar.textures');
local jobs = require('libs.jobs');
local components = require('config.components');
local dragdrop = require('libs.dragdrop');
local petpalette = require('modules.hotbar.petpalette');
local petregistry = require('modules.hotbar.petregistry');
local playerdata = require('modules.hotbar.playerdata');
-- display and crossbar are loaded lazily to avoid circular dependencies
local display = nil;
local crossbar = nil;

local M = {};

-- ============================================
-- Constants
-- ============================================

local INPUT_BUFFER_SIZE = 64;
local MACRO_BUFFER_SIZE = 512;  -- 8 lines * ~60 chars each
local PALETTE_COLUMNS = 6;
local PALETTE_ROWS = 6;
local PALETTE_MACROS_PER_PAGE = PALETTE_COLUMNS * PALETTE_ROWS;  -- 36 macros per page
local PALETTE_TILE_SIZE = 48;
local PALETTE_TILE_GAP = 4;
local PALETTE_PADDING = 8;

-- XIUI Color Scheme (from components.TAB_STYLE)
local COLORS = {
    gold = components.TAB_STYLE.gold,
    goldDim = {0.957 * 0.7, 0.855 * 0.7, 0.592 * 0.7, 1.0},
    goldDark = {0.765, 0.684, 0.474, 1.0},       -- #C3AE79 - Darker gold for hover
    goldDarker = {0.573, 0.512, 0.355, 1.0},     -- #92835B - Even darker gold
    bgMedium = components.TAB_STYLE.bgMedium,
    bgLight = components.TAB_STYLE.bgLight,
    bgLighter = components.TAB_STYLE.bgLighter,
    bgDark = {0.067, 0.063, 0.055, 0.95},
    text = {0.9, 0.9, 0.9, 1.0},
    textDim = {0.6, 0.6, 0.6, 1.0},
    textMuted = {0.4, 0.4, 0.4, 1.0},
    border = {0.3, 0.28, 0.24, 0.8},
    success = {0.4, 0.7, 0.4, 1.0},
    danger = {0.8, 0.3, 0.3, 1.0},
    dangerDim = {0.6, 0.25, 0.25, 1.0},
    usable = {0.5, 0.7, 1.0, 1.0},  -- Blue tint for usable items
};

-- Helper to generate abbreviated text from action name (max 4 chars)
-- If preferAction is true, prioritize action name over displayName (for previews)
local function GetActionAbbreviation(macro, preferAction)
    local name;
    if preferAction then
        name = macro.action or macro.displayName or '';
    else
        name = macro.displayName or macro.action or '';
    end
    if name == '' then return '?'; end

    -- Remove common prefixes/suffixes
    name = name:gsub('^%s+', ''):gsub('%s+$', '');  -- Trim whitespace

    -- If short enough, just use it
    if #name <= 4 then
        return name:upper();
    end

    -- Check for multi-word names (take first letter of each word)
    local words = {};
    for word in name:gmatch('%S+') do
        table.insert(words, word);
    end

    if #words >= 2 then
        -- Multi-word: take first letter of each word (up to 4)
        local abbr = '';
        for i = 1, math.min(#words, 4) do
            abbr = abbr .. words[i]:sub(1, 1):upper();
        end
        return abbr;
    end

    -- Single word: take first 4 chars
    return name:sub(1, 4):upper();
end

-- Helper to clear all hotbar/crossbar icon caches
local function ClearAllIconCaches()
    -- Lazy-load display to avoid circular dependency
    if display == nil then
        local success, mod = pcall(require, 'modules.hotbar.display');
        if success then display = mod; end
    end
    if display and display.ClearIconCache then
        display.ClearIconCache();
    end
    -- Lazy-load crossbar to avoid circular dependency
    if crossbar == nil then
        local success, mod = pcall(require, 'modules.hotbar.crossbar');
        if success then crossbar = mod; end
    end
    if crossbar and crossbar.ClearIconCache then
        crossbar.ClearIconCache();
    end
end

-- Action type constants (needed by DrawMacroTile and DrawMacroEditor)
local ACTION_TYPES = { 'ma', 'ja', 'ws', 'item', 'equip', 'macro', 'pet' };
local ACTION_TYPE_LABELS = {
    ma = 'Spell (ma)',
    ja = 'Ability (ja)',
    ws = 'Weaponskill (ws)',
    item = 'Item',
    equip = 'Equip',
    macro = 'Macro',
    pet = 'Pet Command',
};

-- FFXI equipment slot bitmasks (for filtering items by equip slot)
local EQUIP_SLOT_MASKS = {
    main = 0x0001,
    sub = 0x0002,
    range = 0x0004,
    ammo = 0x0008,
    head = 0x0010,
    body = 0x0020,
    hands = 0x0040,
    legs = 0x0080,
    feet = 0x0100,
    neck = 0x0200,
    waist = 0x0400,
    ear1 = 0x0800,
    ear2 = 0x1000,
    ring1 = 0x2000,
    ring2 = 0x4000,
    back = 0x8000,
};

-- ============================================
-- Helper Functions for Job ID Key Normalization
-- ============================================

-- Special key for global (non-job-specific) slot storage
local GLOBAL_SLOT_KEY = 'global';

-- Special key for global macros (shared across all jobs)
local GLOBAL_MACRO_KEY = 'global';

-- Helper to normalize job ID to number (handles string keys from JSON)
local function normalizeJobId(jobId)
    if type(jobId) == 'string' then
        return tonumber(jobId) or 1;
    end
    return jobId or 1;
end

-- Helper to get the storage key based on jobSpecific setting
local function getStorageKey(barSettings, jobId)
    if barSettings.jobSpecific == false then
        return GLOBAL_SLOT_KEY;
    end
    return normalizeJobId(jobId);
end

-- Check if a storage key is a pet-aware composite key (e.g., "15:avatar:ifrit")
local function isPetCompositeKey(key)
    if type(key) ~= 'string' then return false; end
    return key:find(':') ~= nil;
end

-- Helper to ensure slotActions structure exists for a storage key
-- Handles: 'global', numeric job IDs, and pet-aware composite keys
local function ensureSlotActionsStructure(barSettings, storageKey)
    if not barSettings.slotActions then
        barSettings.slotActions = {};
    end
    -- Handle 'global' key specially
    if storageKey == GLOBAL_SLOT_KEY then
        if not barSettings.slotActions[GLOBAL_SLOT_KEY] then
            barSettings.slotActions[GLOBAL_SLOT_KEY] = {};
        end
        return barSettings.slotActions[GLOBAL_SLOT_KEY];
    end
    -- Handle pet-aware composite keys (stored as strings, e.g., "15:avatar:ifrit")
    if isPetCompositeKey(storageKey) then
        if not barSettings.slotActions[storageKey] then
            barSettings.slotActions[storageKey] = {};
        end
        return barSettings.slotActions[storageKey];
    end
    -- Handle regular job ID keys
    local numericKey = normalizeJobId(storageKey);
    if not barSettings.slotActions[numericKey] then
        -- Also check for string key and migrate if found
        local stringKey = tostring(numericKey);
        if barSettings.slotActions[stringKey] then
            barSettings.slotActions[numericKey] = barSettings.slotActions[stringKey];
            barSettings.slotActions[stringKey] = nil;
        else
            barSettings.slotActions[numericKey] = {};
        end
    end
    return barSettings.slotActions[numericKey];
end

-- ============================================
-- State
-- ============================================

local paletteOpen = false;
local selectedMacroIndex = nil;
local editingMacro = nil;
local isCreatingNew = false;
local currentPalettePage = 1;  -- Current page in macro palette (1-indexed)

-- Selected job for viewing/editing macros (nil = use current player job)
local selectedPaletteType = nil;  -- Can be GLOBAL_MACRO_KEY or a job ID
local selectedAvatarPalette = nil;  -- For SMN: nil = base, or avatar name like 'Ifrit'

-- Cached pet commands (managed locally, not in shared module)
local cachedPetCommands = nil;
local petAvatarFilter = 1;  -- 1 = All, 2+ = specific avatar index

-- Search filter for dropdowns
local searchFilter = { '' };

-- Icon picker state
local iconPickerOpen = false;
local iconPickerFilter = { '' };
local iconPickerTab = 1;  -- 1 = Spells, 2 = Items, 3 = Custom
local iconPickerPage = { 1, 1, 1 };  -- Current page for each tab [spells, items, custom]
local iconPickerLastFilter = { '', '', '' };  -- Track filter changes to reset page
local iconPickerSpellType = 'All';  -- Current spell type filter

-- Spell type display names and order
local SPELL_TYPE_ORDER = {
    'All', 'WhiteMagic', 'BlackMagic', 'BlueMagic', 'BardSong',
    'Ninjutsu', 'SummonerPact', 'Trust'
};
local SPELL_TYPE_LABELS = {
    ['All'] = 'All Spells',
    ['WhiteMagic'] = 'White Magic',
    ['BlackMagic'] = 'Black Magic',
    ['BlueMagic'] = 'Blue Magic',
    ['BardSong'] = 'Bard Songs',
    ['Ninjutsu'] = 'Ninjutsu',
    ['SummonerPact'] = 'Summoning',
    ['Trust'] = 'Trusts',
};
-- Job icon file names for spell type filters (from assets/jobs/FFXIV)
local SPELL_TYPE_JOB_ICONS = {
    ['All'] = 'infinite',   -- Infinite symbol for "All"
    ['WhiteMagic'] = 'whm',
    ['BlackMagic'] = 'blm',
    ['BlueMagic'] = 'blu',
    ['BardSong'] = 'brd',
    ['Ninjutsu'] = 'nin',
    ['SummonerPact'] = 'smn',
    ['Trust'] = nil,        -- Use custom trust icon instead
};

-- Cache for filter icons
local filterIconCache = {};

-- Load a filter icon (job icon or trust icon)
local function GetFilterIcon(spellType)
    -- Check cache first
    if filterIconCache[spellType] then
        return filterIconCache[spellType];
    end

    local icon = nil;

    if spellType == 'Trust' then
        -- Load custom trust icon (Shantotto)
        local path = string.format('%saddons\\XIUI\\assets\\hotbar\\custom\\trusts\\trust-shantotto.png', AshitaCore:GetInstallPath());
        icon = textures:LoadTextureFromPath(path);
    else
        -- Load job icon from FFXIV theme
        local jobAbbr = SPELL_TYPE_JOB_ICONS[spellType];
        if jobAbbr then
            local path = string.format('%saddons\\XIUI\\assets\\jobs\\FFXIV\\%s.png', AshitaCore:GetInstallPath(), jobAbbr);
            icon = textures:LoadTextureFromPath(path);
        end
    end

    filterIconCache[spellType] = icon;
    return icon;
end

-- Item type constants from FFXI (item.Type field)
-- Note: Only include types that have significant item counts
local ITEM_TYPE_ORDER = {
    0,   -- All
    4,   -- Weapon
    5,   -- Armor
    7,   -- Usable (food, medicine, etc.)
    1,   -- General
    8,   -- Crystal
    10,  -- Furnishing
};
local ITEM_TYPE_LABELS = {
    [0] = 'All Items',
    [1] = 'General',
    [4] = 'Weapons',
    [5] = 'Armor',
    [7] = 'Usable',
    [8] = 'Crystals',
    [10] = 'Furniture',
};
-- Representative item IDs for each type
local ITEM_TYPE_ICONS = {
    [0] = 6378,   -- All - Beist's Coffer (chest icon)
    [4] = 16535,  -- Bronze Sword
    [5] = 12505,  -- Bronze Cap
    [7] = 4112,   -- Potion
    [1] = 880,    -- Flint Stone
    [8] = 4096,   -- Fire Crystal
    [10] = 6232,  -- Furnishing item
};
local iconPickerItemType = 0;  -- 0 = All

-- Custom icon categories (subdirectories in assets/hotbar/custom/)
local CUSTOM_ICON_CATEGORIES = {};  -- Populated by scanning directory
local CUSTOM_ICON_LABELS = {
    ['all'] = 'All',
};
local customIconCategory = 'all';  -- 'all' or a folder name

-- Custom icon cache
local customIconsCache = nil;  -- All custom icons
local customIconsByCategoryCache = {};  -- Pre-filtered by category
local customIconsCacheKey = nil;

-- Custom icons directory path
local customIconsDir = nil;

-- New folder creation state
local newFolderName = { '' };

-- Delete folder confirmation state
local deleteFolderTarget = nil;  -- Category name to delete

-- Cached filtered results for icon picker (avoid recalculating every frame)
local filteredSpellsCache = nil;
local filteredSpellsCacheKey = nil;  -- "filter:type" key for cache invalidation
local filteredItemsCache = nil;
local filteredItemsCacheKey = nil;  -- "filter" key for cache invalidation

-- Icon picker grid constants
local ICON_GRID_COLUMNS = 12;
local ICON_GRID_SIZE = 36;
local ICON_GRID_GAP = 4;
local ICONS_PER_PAGE = 120;  -- 10 rows of 12 icons - loads in ~1 second

-- Progressive icon loading state (to prevent game freeze)
local iconLoadState = {
    currentPage = -1,        -- Track which page we're loading
    currentTab = -1,         -- Track which tab
    currentCacheKey = '',    -- Track filter/type changes
    loadedCount = 0,         -- How many icons loaded on current page
    iconsPerFrame = 3,       -- Load only 3 icons per frame (very smooth)
    frameSkip = 0,           -- Skip frames between loads for extra smoothness
    frameCounter = 0,        -- Current frame counter
    pageIconCache = {},      -- Cache of loaded icons for current page: [index] = icon
};

-- Reset progressive icon loading (call when page/filter/type changes)
local function ResetIconLoading()
    iconLoadState.currentPage = -1;
    iconLoadState.currentTab = -1;
    iconLoadState.currentCacheKey = '';
    iconLoadState.loadedCount = 0;
    iconLoadState.frameCounter = 0;
    iconLoadState.pageIconCache = {};
end

-- Cached spell list for icon picker (all spells, not just player-known)
local allSpellsCache = nil;

-- Item icon loading state (for lazy loading)
local itemIconLoadState = {
    loaded = false,
    loading = false,
    items = {},
    itemsByType = {},  -- Pre-filtered lists by type for instant filtering
    seenNames = {},  -- Hash table for O(1) duplicate checking
    currentId = 0,
    maxId = 65535,
    batchSize = 500,  -- Load 500 items per frame (fast since we're just reading names)
};

-- ============================================
-- Spell/Ability/Weaponskill Retrieval (via shared playerdata module)
-- ============================================

-- Refresh cached lists if needed (delegates to shared playerdata module)
local function RefreshCachedLists()
    -- Pass data module for pending job change detection
    playerdata.RefreshCachedLists(data);
    -- Clear local pet commands cache when job changes
    if playerdata.GetCacheJobId() ~= data.jobId then
        cachedPetCommands = nil;
    end
end

-- Convenience accessors for cached data
local function GetCachedSpells()
    return playerdata.GetCachedSpells();
end

local function GetCachedAbilities()
    return playerdata.GetCachedAbilities();
end

local function GetCachedWeaponskills()
    return playerdata.GetCachedWeaponskills();
end

local function GetCachedItems()
    return playerdata.GetCachedItems();
end

-- Get pet commands for the current job
local function GetPetCommandsForJob(jobId, avatarName, activePetName)
    return petregistry.GetPetCommandsForJob(jobId, avatarName, activePetName);
end

-- Spell type sort order lookup for grouping
local SPELL_TYPE_SORT_ORDER = {};
for i, spellType in ipairs(SPELL_TYPE_ORDER) do
    SPELL_TYPE_SORT_ORDER[spellType] = i;
end

-- Build cache of ALL spells from horizonspells database (for icon picker)
local function GetAllSpells()
    if allSpellsCache then
        return allSpellsCache;
    end

    local horizonSpells = require('modules.hotbar.database.horizonspells');
    allSpellsCache = {};

    for _, spell in pairs(horizonSpells) do
        if spell.en and spell.en ~= '' and spell.id and not playerdata.IsGarbageSpellName(spell.en) then
            table.insert(allSpellsCache, {
                id = spell.id,
                name = spell.en,
                icon_id = spell.icon_id,
                type = spell.type or 'Unknown',
            });
        end
    end

    -- Sort by type (grouped) then by name within each type
    table.sort(allSpellsCache, function(a, b)
        local aOrder = SPELL_TYPE_SORT_ORDER[a.type] or 999;
        local bOrder = SPELL_TYPE_SORT_ORDER[b.type] or 999;
        if aOrder ~= bOrder then
            return aOrder < bOrder;
        end
        return a.name < b.name;
    end);

    return allSpellsCache;
end

-- Load a batch of item icons (for lazy loading)
local function LoadItemIconBatch()
    if itemIconLoadState.loaded or not itemIconLoadState.loading then
        return;
    end

    local resMgr = AshitaCore:GetResourceManager();
    if not resMgr then return; end

    local endId = math.min(itemIconLoadState.currentId + itemIconLoadState.batchSize, itemIconLoadState.maxId);

    for itemId = itemIconLoadState.currentId + 1, endId do
        local item = resMgr:GetItemById(itemId);
        if item and item.Name and item.Name[1] and item.Name[1] ~= '' then
            local itemName = item.Name[1];
            -- Skip duplicate names using hash table (O(1) lookup)
            if not itemIconLoadState.seenNames[itemName] then
                itemIconLoadState.seenNames[itemName] = true;
                -- Capture item type for filtering (Type field from FFXI item data)
                local itemType = item.Type or 1;
                table.insert(itemIconLoadState.items, {
                    id = itemId,
                    name = itemName,
                    itemType = itemType,
                });
            end
        end
    end

    itemIconLoadState.currentId = endId;

    if itemIconLoadState.currentId >= itemIconLoadState.maxId then
        itemIconLoadState.loaded = true;
        itemIconLoadState.loading = false;

        -- Sort items alphabetically (simple sort for All view)
        table.sort(itemIconLoadState.items, function(a, b)
            return a.name < b.name;
        end);

        -- Build pre-filtered lists by type for instant filtering
        itemIconLoadState.itemsByType = {};
        for _, item in ipairs(itemIconLoadState.items) do
            local itemType = item.itemType or 1;
            if not itemIconLoadState.itemsByType[itemType] then
                itemIconLoadState.itemsByType[itemType] = {};
            end
            table.insert(itemIconLoadState.itemsByType[itemType], item);
        end
    end
end

-- Start loading all item icons
local function StartItemIconLoading()
    if itemIconLoadState.loaded or itemIconLoadState.loading then
        return;
    end
    itemIconLoadState.loading = true;
    itemIconLoadState.currentId = 0;
    itemIconLoadState.items = {};
    itemIconLoadState.itemsByType = {};
    itemIconLoadState.seenNames = {};
end

-- Get loading progress percentage
local function GetItemLoadProgress()
    if itemIconLoadState.loaded then
        return 100;
    end
    return math.floor((itemIconLoadState.currentId / itemIconLoadState.maxId) * 100);
end

-- ============================================
-- Custom Icons Loading
-- ============================================

-- Get the custom icons directory path
local function GetCustomIconsDir()
    if not customIconsDir then
        customIconsDir = string.format('%saddons\\XIUI\\assets\\hotbar\\custom\\', AshitaCore:GetInstallPath());
    end
    return customIconsDir;
end

-- Recursively scan a directory for PNG files
-- topLevelCategory: the immediate subdirectory name (for nested files)
local function ScanDirectoryForPngs(dir, relativePath, results, topLevelCategory)
    relativePath = relativePath or '';
    results = results or {};
    
    local contents = ashita.fs.get_directory(dir, '.*');
    if not contents then return results; end
    
    for _, entry in pairs(contents) do
        local fullPath = dir .. entry;
        local relPath = relativePath ~= '' and (relativePath .. '\\' .. entry) or entry;
        
        -- Check if it's a PNG file
        if entry:lower():match('%.png$') then
            -- Category is: root (if at root level), or the top-level folder name
            local category = topLevelCategory or 'root';
            table.insert(results, {
                name = entry:gsub('%.png$', ''),  -- Remove .png extension for display
                path = relPath,  -- Relative path from custom/ directory
                category = category,
            });
        -- Check if it's a directory (no extension, not a file)
        elseif not entry:match('%.') then
            -- Determine the category for nested items
            -- If we're at root level, this entry IS the top-level category
            -- If we're already in a subdirectory, keep the original top-level category
            local categoryForNested = topLevelCategory or entry;
            -- Recursively scan subdirectory
            ScanDirectoryForPngs(fullPath .. '\\', relPath, results, categoryForNested);
        end
    end
    
    return results;
end

-- Scan and cache all custom icons
local function LoadCustomIcons()
    if customIconsCache then
        return customIconsCache;
    end
    
    local baseDir = GetCustomIconsDir();
    customIconsCache = ScanDirectoryForPngs(baseDir);
    
    -- Sort alphabetically by name
    table.sort(customIconsCache, function(a, b)
        return a.name:lower() < b.name:lower();
    end);
    
    -- Build category list from folders only
    CUSTOM_ICON_CATEGORIES = { 'all' };  -- 'all' is always first
    customIconsByCategoryCache = { ['all'] = customIconsCache };
    customCategoryIconCache = {};  -- Clear category icon cache
    
    local seenCategories = { ['all'] = true };
    
    -- First, scan for all immediate subdirectories (including empty ones)
    local contents = ashita.fs.get_directory(baseDir, '.*');
    if contents then
        for _, entry in pairs(contents) do
            -- Check if it's a directory (no file extension)
            if not entry:match('%.') then
                if not seenCategories[entry] then
                    seenCategories[entry] = true;
                    table.insert(CUSTOM_ICON_CATEGORIES, entry);
                    customIconsByCategoryCache[entry] = {};
                    -- Generate label from directory name
                    local label = entry:gsub('^%l', string.upper):gsub('_', ' ');
                    CUSTOM_ICON_LABELS[entry] = label;
                end
            end
        end
    end
    
    -- Then populate categories from found icons
    for _, icon in ipairs(customIconsCache) do
        -- Only add to categories for folders (not root-level files)
        if icon.category ~= 'root' then
            -- Add category if somehow not seen yet
            if not seenCategories[icon.category] then
                seenCategories[icon.category] = true;
                table.insert(CUSTOM_ICON_CATEGORIES, icon.category);
                customIconsByCategoryCache[icon.category] = {};
                local label = icon.category:gsub('^%l', string.upper):gsub('_', ' ');
                CUSTOM_ICON_LABELS[icon.category] = label;
            end
            -- Add to category-specific list
            table.insert(customIconsByCategoryCache[icon.category], icon);
        end
        -- Root files are only in 'all', no separate category
    end
    
    -- Sort categories alphanumerically (but keep 'all' first)
    table.sort(CUSTOM_ICON_CATEGORIES, function(a, b)
        if a == 'all' then return true; end
        if b == 'all' then return false; end
        return a:lower() < b:lower();
    end);
    
    return customIconsCache;
end

-- Get custom icons filtered by category
local function GetCustomIconsFiltered(category, filter)
    LoadCustomIcons();  -- Ensure loaded
    
    local sourceList;
    if category == 'all' then
        sourceList = customIconsCache;
    else
        sourceList = customIconsByCategoryCache[category] or {};
    end
    
    -- Apply text filter if any
    if filter and filter ~= '' then
        local filtered = {};
        filter = filter:lower();
        for _, icon in ipairs(sourceList) do
            if icon.name:lower():find(filter, 1, true) then
                table.insert(filtered, icon);
            end
        end
        return filtered;
    end
    
    return sourceList;
end

-- Load a custom icon texture by relative path
local function LoadCustomIconTexture(relativePath)
    local fullPath = GetCustomIconsDir() .. relativePath;
    return textures:LoadTextureFromPath(fullPath);
end

-- Create a new custom icon folder
local function CreateCustomFolder(folderName)
    if not folderName or folderName == '' then return false; end
    
    -- Sanitize folder name (remove invalid characters)
    local sanitized = folderName:gsub('[<>:"/\\|?*]', ''):gsub('^%s+', ''):gsub('%s+$', '');
    if sanitized == '' then return false; end
    
    local folderPath = GetCustomIconsDir() .. sanitized;
    
    -- Create the directory
    ashita.fs.create_directory(folderPath);
    
    -- Clear caches to force rescan
    customIconsCache = nil;
    customIconsByCategoryCache = {};
    customCategoryIconCache = {};
    customIconsCacheKey = nil;
    
    -- Set the new folder as current category
    customIconCategory = sanitized;
    
    return true;
end

-- Cache for category filter icons
local customCategoryIconCache = {};

-- Track which categories are empty (for showing letter instead of icon)
local function IsCategoryEmpty(category)
    if category == 'all' then return false; end
    local categoryIcons = customIconsByCategoryCache[category];
    return not categoryIcons or #categoryIcons == 0;
end

-- Get a representative icon for a category (for filter buttons)
-- Returns icon, isEmptyFolder
local function GetCustomCategoryIcon(category)
    -- Check cache first (but not for empty folders - they might get icons added)
    if customCategoryIconCache[category] and not IsCategoryEmpty(category) then
        return customCategoryIconCache[category], false;
    end
    
    -- For 'all', use a special infinite symbol icon if available
    if category == 'all' then
        -- Try to use the 'infinite' icon from jobs folder
        local infiniteIcon = textures:Get('infinite');
        if infiniteIcon then
            customCategoryIconCache[category] = infiniteIcon;
            return infiniteIcon, false;
        end
        -- Fallback: use first icon from all icons
        if customIconsCache and #customIconsCache > 0 then
            local icon = LoadCustomIconTexture(customIconsCache[1].path);
            customCategoryIconCache[category] = icon;
            return icon, false;
        end
        return nil, false;
    end
    
    -- Get the first icon from this category (folder)
    local categoryIcons = customIconsByCategoryCache[category];
    if categoryIcons and #categoryIcons > 0 then
        local icon = LoadCustomIconTexture(categoryIcons[1].path);
        customCategoryIconCache[category] = icon;
        return icon, false;
    end
    
    -- Empty folder - return nil to signal we need to draw a letter
    return nil, true;
end

-- Open a custom icon folder in Windows Explorer
local function OpenCustomFolder(category)
    local folderPath;
    if category == 'all' or not category then
        folderPath = GetCustomIconsDir();
    else
        folderPath = GetCustomIconsDir() .. category;
    end
    ashita.misc.execute(folderPath, '');
end

-- Delete a custom icon folder and all its contents
local function DeleteCustomFolder(category)
    if not category or category == 'all' then return false; end
    
    local folderPath = GetCustomIconsDir() .. category;
    
    -- Delete all files in the folder first
    local contents = ashita.fs.get_directory(folderPath, '.*');
    if contents then
        for _, file in pairs(contents) do
            local filePath = folderPath .. '\\' .. file;
            os.remove(filePath);
        end
    end
    
    -- Delete the empty folder using Windows rmdir command
    os.execute('rmdir "' .. folderPath .. '"');
    
    -- Clear caches to force rescan
    customIconsCache = nil;
    customIconsByCategoryCache = {};
    customCategoryIconCache = {};
    customIconsCacheKey = nil;
    -- Also clear the action module's custom icon cache
    actions.ClearCustomIconCache();
    
    -- Reset to 'all' category
    customIconCategory = 'all';
    
    return true;
end

-- Push XIUI styling for combo popups
local function PushComboStyle()
    imgui.PushStyleColor(ImGuiCol_PopupBg, COLORS.bgDark);
    imgui.PushStyleColor(ImGuiCol_ChildBg, COLORS.bgDark);
    imgui.PushStyleColor(ImGuiCol_Border, COLORS.border);
    imgui.PushStyleColor(ImGuiCol_FrameBg, COLORS.bgMedium);
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, COLORS.bgLight);
    imgui.PushStyleColor(ImGuiCol_Header, COLORS.bgLight);
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, COLORS.bgLighter);
    imgui.PushStyleColor(ImGuiCol_ScrollbarBg, COLORS.bgDark);
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrab, COLORS.bgLight);
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabHovered, COLORS.bgLighter);
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabActive, COLORS.gold);
end

local function PopComboStyle()
    imgui.PopStyleColor(11);
end

-- Draw a searchable dropdown combo box with XIUI styling
-- showIcons: if true, will attempt to load and display item icons
-- equipSlotFilter: if provided, only show items that can be equipped in this slot (e.g., 'main', 'head')
local function DrawSearchableCombo(label, items, currentValue, onSelect, showIcons, equipSlotFilter)
    local displayText = currentValue ~= '' and currentValue or 'Select...';

    -- Get the slot mask for filtering if provided
    local slotMask = equipSlotFilter and EQUIP_SLOT_MASKS[equipSlotFilter] or nil;

    -- Apply XIUI styling to combo popup
    PushComboStyle();

    imgui.SetNextItemWidth(220);
    -- Use HeightLargest so popup fits our child window without its own scrollbar
    if imgui.BeginCombo(label, displayText, ImGuiComboFlags_HeightLargest) then
        -- Search input at top (fixed, not scrollable)
        imgui.SetNextItemWidth(200);
        imgui.PushStyleColor(ImGuiCol_Text, COLORS.text);
        imgui.InputText('##search' .. label, searchFilter, INPUT_BUFFER_SIZE);
        imgui.PopStyleColor();

        if searchFilter[1] == '' then
            -- Show placeholder hint
            local inputPos = {imgui.GetItemRectMin()};
            imgui.SetCursorScreenPos({inputPos[1] + 6, inputPos[2] + 3});
            imgui.TextColored(COLORS.textMuted, 'Type to search...');
        end

        imgui.Separator();

        -- Scrollable child region for items only
        local childHeight = 200;
        imgui.BeginChild('##comboScroll' .. label, {0, childHeight}, false);

        local filter = searchFilter[1]:lower();
        local matchCount = 0;
        local iconSize = 16;

        for _, item in ipairs(items) do
            local itemName = item.name or '';

            -- Check if item passes equipment slot filter
            local passesSlotFilter = true;
            if slotMask and item.slots then
                passesSlotFilter = bit.band(item.slots, slotMask) ~= 0;
            end

            if passesSlotFilter and (filter == '' or itemName:lower():find(filter, 1, true)) then
                matchCount = matchCount + 1;
                local isSelected = currentValue == itemName;

                -- Determine text color: gold if selected, blue if usable, default otherwise
                local textColor = nil;
                if isSelected then
                    textColor = COLORS.gold;
                elseif item.usable then
                    textColor = COLORS.usable;
                end

                if textColor then
                    imgui.PushStyleColor(ImGuiCol_Text, textColor);
                end

                -- Show icon if enabled and item has an id
                if showIcons and item.id then
                    local icon = actions.GetBindIcon({ actionType = 'item', action = item.name, itemId = item.id });
                    if icon and icon.image then
                        local iconPtr = tonumber(ffi.cast("uint32_t", icon.image));
                        if iconPtr then
                            imgui.Image(iconPtr, {iconSize, iconSize});
                            imgui.SameLine();
                        end
                    end
                end

                local itemLabel = item.level and string.format('[%d] %s', item.level, itemName) or itemName;
                -- Add quantity for items with count > 1
                if item.count and item.count > 1 then
                    itemLabel = itemLabel .. ' x' .. item.count;
                end
                if imgui.Selectable(itemLabel .. '##item' .. (item.id or matchCount), isSelected) then
                    onSelect(item);
                    searchFilter[1] = '';
                    imgui.CloseCurrentPopup();
                end

                if textColor then
                    imgui.PopStyleColor();
                end
            end
        end

        if matchCount == 0 then
            imgui.TextColored(COLORS.textMuted, 'No matches');
        end

        imgui.EndChild();

        imgui.EndCombo();
    end

    PopComboStyle();
end


-- ============================================
-- Macro Database Functions
-- ============================================

-- Get current effective type for the palette (selected type or player's current job)
-- Returns GLOBAL_MACRO_KEY for global macros, a job ID, or a composite key like "15:avatar:ifrit"
local function GetEffectivePaletteType()
    if selectedPaletteType then
        -- If Global is selected, return the global key
        if selectedPaletteType == GLOBAL_MACRO_KEY then
            return GLOBAL_MACRO_KEY;
        end
        -- If a valid job ID is selected
        if type(selectedPaletteType) == 'number' and selectedPaletteType > 0 then
            -- Check for SMN avatar-specific palette
            if selectedPaletteType == petregistry.JOB_SMN and selectedAvatarPalette then
                local avatarKey = petregistry.avatars[selectedAvatarPalette];
                if avatarKey then
                    return string.format('%d:avatar:%s', selectedPaletteType, avatarKey);
                end
            end
            return selectedPaletteType;
        end
    end
    -- Default to current player job
    return data.jobId or 1;
end

-- Get display name for a palette type key
local function GetPaletteDisplayName(typeKey)
    if typeKey == GLOBAL_MACRO_KEY then
        return 'Global';
    end
    if type(typeKey) == 'number' then
        return jobs[typeKey] or 'Unknown';
    end
    -- Composite key like "15:avatar:ifrit"
    if type(typeKey) == 'string' then
        local jobId, petType, petId = typeKey:match('^(%d+):([^:]+):(.+)$');
        if jobId and petType == 'avatar' and petId then
            -- Find avatar display name
            for name, key in pairs(petregistry.avatars) do
                if key == petId then
                    return string.format('%s (%s)', jobs[tonumber(jobId)] or 'SMN', name);
                end
            end
        end
    end
    return tostring(typeKey);
end

-- Sync palette to current player job (call on job change)
function M.SyncToCurrentJob()
    -- Only sync if not viewing Global - preserve Global selection across job changes
    if selectedPaletteType ~= GLOBAL_MACRO_KEY then
        selectedPaletteType = data.jobId or 1;
    end
    -- Clear spell/ability/item caches so they rebuild for new job
    playerdata.ClearCache();
    cachedPetCommands = nil;
    petAvatarFilter = 1;
    selectedAvatarPalette = nil;
    -- Close editor window if open (spells/abilities are job-specific)
    if editingMacro then
        editingMacro = nil;
        isCreatingNew = false;
        searchFilter[1] = '';
        iconPickerOpen = false;
    end
    -- Clear macro selection (macros are per-type)
    selectedMacroIndex = nil;
    -- If palette is open, immediately refresh the caches
    if paletteOpen then
        RefreshCachedLists();
    end
end

-- Clear pet commands cache (call on pet change for BST)
function M.ClearPetCommandsCache()
    cachedPetCommands = nil;
end

-- Get the macro database for selected type (Global or job-specific)
function M.GetMacroDatabase()
    local typeKey = GetEffectivePaletteType();

    if not gConfig.macroDB then
        gConfig.macroDB = {};
    end

    if not gConfig.macroDB[typeKey] then
        gConfig.macroDB[typeKey] = {};
    end

    return gConfig.macroDB[typeKey], typeKey;
end

-- Add a new macro to the database
function M.AddMacro(macroData)
    local db, _ = M.GetMacroDatabase();

    -- Generate unique ID
    local maxId = 0;
    for _, macro in ipairs(db) do
        if macro.id and macro.id > maxId then
            maxId = macro.id;
        end
    end

    macroData.id = maxId + 1;
    table.insert(db, macroData);
    SaveSettingsToDisk();

    return macroData.id;
end

-- Update an existing macro
function M.UpdateMacro(macroId, macroData)
    local db = M.GetMacroDatabase();

    for i, macro in ipairs(db) do
        if macro.id == macroId then
            macroData.id = macroId;  -- Preserve ID
            db[i] = macroData;
            SaveSettingsToDisk();
            -- Clear icon cache so hotbar slots referencing this macro update
            ClearAllIconCaches();
            return true;
        end
    end

    return false;
end

-- Clear all hotbar/crossbar slots that reference a specific macro ID
-- For Global macros, clears from ALL jobs' slot actions
local function ClearSlotsReferencingMacro(macroId, typeKey)
    local isGlobalMacro = (typeKey == GLOBAL_MACRO_KEY);

    -- Clear from all hotbars (1-6)
    for barIndex = 1, 6 do
        local configKey = 'hotbarBar' .. barIndex;
        if gConfig[configKey] and gConfig[configKey].slotActions then
            local barSettings = gConfig[configKey];

            if isGlobalMacro then
                -- For Global macros, clear from ALL storage keys
                for storageKey, jobSlotActions in pairs(barSettings.slotActions) do
                    if jobSlotActions then
                        for slotIndex, slotAction in pairs(jobSlotActions) do
                            if slotAction and slotAction.macroRef == macroId then
                                jobSlotActions[slotIndex] = { cleared = true };
                            end
                        end
                    end
                end
            else
                -- For job-specific macros, only clear from that job's storage
                local numericJobId = normalizeJobId(typeKey);
                local storageKey = getStorageKey(barSettings, numericJobId);
                local jobSlotActions = barSettings.slotActions[storageKey];

                if jobSlotActions then
                    for slotIndex, slotAction in pairs(jobSlotActions) do
                        if slotAction and slotAction.macroRef == macroId then
                            jobSlotActions[slotIndex] = { cleared = true };
                        end
                    end
                end
            end
        end
    end

    -- Clear from crossbar (all combo modes)
    if gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.slotActions then
        local crossbarSettings = gConfig.hotbarCrossbar;

        if isGlobalMacro then
            -- For Global macros, clear from ALL storage keys
            for storageKey, jobSlotActions in pairs(crossbarSettings.slotActions) do
                if jobSlotActions then
                    local comboModes = { 'L2', 'R2', 'L2R2', 'R2L2', 'L2x2', 'R2x2' };
                    for _, comboMode in ipairs(comboModes) do
                        local comboSlots = jobSlotActions[comboMode];
                        if comboSlots then
                            for slotIndex, slotAction in pairs(comboSlots) do
                                if slotAction and slotAction.macroRef == macroId then
                                    comboSlots[slotIndex] = nil;
                                end
                            end
                        end
                    end
                end
            end
        else
            -- For job-specific macros, only clear from that job's storage
            local numericJobId = normalizeJobId(typeKey);
            local storageKey;
            if crossbarSettings.jobSpecific == false then
                storageKey = GLOBAL_SLOT_KEY;
            else
                storageKey = numericJobId;
            end

            local jobSlotActions = crossbarSettings.slotActions[storageKey];
            if jobSlotActions then
                local comboModes = { 'L2', 'R2', 'L2R2', 'R2L2', 'L2x2', 'R2x2' };
                for _, comboMode in ipairs(comboModes) do
                    local comboSlots = jobSlotActions[comboMode];
                    if comboSlots then
                        for slotIndex, slotAction in pairs(comboSlots) do
                            if slotAction and slotAction.macroRef == macroId then
                                comboSlots[slotIndex] = nil;
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Delete a macro from the database
function M.DeleteMacro(macroId)
    local db, typeKey = M.GetMacroDatabase();

    for i, macro in ipairs(db) do
        if macro.id == macroId then
            table.remove(db, i);
            -- Clear any hotbar/crossbar slots referencing this macro
            ClearSlotsReferencingMacro(macroId, typeKey);
            SaveSettingsToDisk();
            -- Clear icon cache so hotbar slots update immediately
            ClearAllIconCaches();
            return true;
        end
    end

    return false;
end

-- Get a macro by ID
function M.GetMacroById(macroId)
    local db = M.GetMacroDatabase();

    for _, macro in ipairs(db) do
        if macro.id == macroId then
            return macro;
        end
    end

    return nil;
end

-- ============================================
-- Drag & Drop Functions (using dragdrop library)
-- ============================================

-- Start dragging a macro from the palette
function M.StartDragMacro(macroIndex, macroData)
    -- Get icon for this macro
    local icon = actions.GetBindIcon(macroData);

    dragdrop.StartDrag('macro', {
        data = macroData,
        macroIndex = macroIndex,
        label = macroData.displayName or macroData.action or 'Macro',
        icon = icon,
    });
end

-- Start dragging from a hotbar slot
function M.StartDragSlot(barIndex, slotIndex, slotData)
    -- Get icon for this slot
    local icon = actions.GetBindIcon(slotData);

    dragdrop.StartDrag('slot', {
        data = slotData,
        barIndex = barIndex,
        slotIndex = slotIndex,
        label = slotData.displayName or slotData.action or 'Slot',
        icon = icon,
    });
end

-- Clear drag state
function M.ClearDrag()
    dragdrop.CancelDrag();
end

-- Get current drag state (compatibility wrapper)
function M.GetDragState()
    local payload = dragdrop.GetPayload();
    if payload then
        return {
            isDragging = dragdrop.IsDragging(),
            sourceType = payload.type,
            macroIndex = payload.macroIndex,
            barIndex = payload.barIndex,
            slotIndex = payload.slotIndex,
            macroData = payload.data,
        };
    end
    return {
        isDragging = false,
        sourceType = nil,
        macroIndex = nil,
        barIndex = nil,
        slotIndex = nil,
        macroData = nil,
    };
end

-- Check if currently dragging
function M.IsDragging()
    return dragdrop.IsDragging();
end

-- Handle drop on a hotbar slot (called by dragdrop.DropZone onDrop callback)
function M.HandleDropOnSlot(payload, targetBarIndex, targetSlotIndex)
    if not payload then
        return false;
    end

    local configKey = 'hotbarBar' .. targetBarIndex;

    -- Ensure config structure exists
    if not gConfig[configKey] then
        gConfig[configKey] = {};
    end
    -- Use pet-aware storage key (handles global, job-specific, and pet palettes)
    local storageKey = data.GetStorageKeyForBar(targetBarIndex);
    local jobSlotActions = ensureSlotActionsStructure(gConfig[configKey], storageKey);

    if payload.type == 'macro' then
        -- Dragging from palette to slot
        local macroData = payload.data;
        if macroData then
            -- Get the current macro palette key to store with the reference
            local macroPaletteKey = GetEffectivePaletteType();
            jobSlotActions[targetSlotIndex] = {
                actionType = macroData.actionType,
                action = macroData.action,
                target = macroData.target,
                displayName = macroData.displayName,
                equipSlot = macroData.equipSlot,
                macroText = macroData.macroText,
                itemId = macroData.itemId,  -- Store item ID for fast icon lookup
                customIconType = macroData.customIconType,  -- Custom icon override
                customIconId = macroData.customIconId,
                customIconPath = macroData.customIconPath,  -- Custom icon path for 'custom' type
                macroRef = macroData.id,  -- Store reference to source macro for live updates
                macroPaletteKey = macroPaletteKey,  -- Store which palette the macro came from
            };
            SaveSettingsToDisk();
        end

    elseif payload.type == 'slot' then
        -- Dragging from slot to slot (swap or move)
        local sourceBarIndex = payload.barIndex;
        local sourceSlotIndex = payload.slotIndex;
        local sourceConfigKey = 'hotbarBar' .. sourceBarIndex;

        -- Use the source data from payload (already contains the action info)
        local sourceBindData = payload.data;
        local sourceData = nil;
        if sourceBindData then
            sourceData = {
                actionType = sourceBindData.actionType,
                action = sourceBindData.action,
                target = sourceBindData.target,
                displayName = sourceBindData.displayName or sourceBindData.action,
                equipSlot = sourceBindData.equipSlot,
                macroText = sourceBindData.macroText,
                itemId = sourceBindData.itemId,  -- Preserve item ID for icon lookup
                customIconType = sourceBindData.customIconType,  -- Preserve custom icon
                customIconId = sourceBindData.customIconId,
                customIconPath = sourceBindData.customIconPath,  -- Preserve custom icon path
                macroRef = sourceBindData.macroRef,  -- Preserve macro reference
                macroPaletteKey = sourceBindData.macroPaletteKey,  -- Preserve palette key
            };
        end

        -- Get target slot data
        local targetBind = data.GetKeybindForSlot(targetBarIndex, targetSlotIndex);
        local targetData = nil;
        if targetBind then
            targetData = {
                actionType = targetBind.actionType,
                action = targetBind.action,
                target = targetBind.target,
                displayName = targetBind.displayName or targetBind.action,
                equipSlot = targetBind.equipSlot,
                macroText = targetBind.macroText,
                itemId = targetBind.itemId,  -- Preserve item ID for icon lookup
                customIconType = targetBind.customIconType,  -- Preserve custom icon
                customIconId = targetBind.customIconId,
                customIconPath = targetBind.customIconPath,  -- Preserve custom icon path
                macroRef = targetBind.macroRef,  -- Preserve macro reference
                macroPaletteKey = targetBind.macroPaletteKey,  -- Preserve palette key
            };
        else
            -- Target slot is empty - mark as cleared
            targetData = { cleared = true };
        end

        -- Ensure source config structure exists
        if not gConfig[sourceConfigKey] then
            gConfig[sourceConfigKey] = {};
        end
        -- Use pet-aware storage key for source bar
        local sourceStorageKey = data.GetStorageKeyForBar(sourceBarIndex);
        local sourceJobSlotActions = ensureSlotActionsStructure(gConfig[sourceConfigKey], sourceStorageKey);

        -- Swap the slots
        jobSlotActions[targetSlotIndex] = sourceData;
        sourceJobSlotActions[sourceSlotIndex] = targetData;

        SaveSettingsToDisk();

    elseif payload.type == 'crossbar_slot' then
        -- Dragging from crossbar to hotbar (one-way copy, doesn't clear source)
        local sourceBindData = payload.data;
        if sourceBindData then
            jobSlotActions[targetSlotIndex] = {
                actionType = sourceBindData.actionType,
                action = sourceBindData.action,
                target = sourceBindData.target,
                displayName = sourceBindData.displayName or sourceBindData.action,
                equipSlot = sourceBindData.equipSlot,
                macroText = sourceBindData.macroText,
                itemId = sourceBindData.itemId,
                customIconType = sourceBindData.customIconType,
                customIconId = sourceBindData.customIconId,
                customIconPath = sourceBindData.customIconPath,  -- Preserve custom icon path
                macroRef = sourceBindData.macroRef,  -- Preserve macro reference
                macroPaletteKey = sourceBindData.macroPaletteKey,  -- Preserve palette key
            };
            SaveSettingsToDisk();
        end
    end

    -- Clear icon cache so slots update immediately after drag/drop
    ClearAllIconCaches();
    return true;
end

-- Clear a hotbar slot
function M.ClearSlot(barIndex, slotIndex)
    -- Use the pet-aware clear function from data.lua
    data.ClearSlotData(barIndex, slotIndex);
    -- Clear icon cache so the slot updates immediately
    ClearAllIconCaches();
end

-- ============================================
-- Palette Window
-- ============================================

function M.OpenPalette()
    paletteOpen = true;
    selectedMacroIndex = nil;
    editingMacro = nil;
    isCreatingNew = false;

    -- Sync to current player job when opening (unless Global was selected)
    if selectedPaletteType ~= GLOBAL_MACRO_KEY then
        selectedPaletteType = data.jobId or 1;
    end

    -- Refresh spell/ability/weaponskill caches
    RefreshCachedLists();
end

function M.ClosePalette()
    paletteOpen = false;
    selectedMacroIndex = nil;
    editingMacro = nil;
    isCreatingNew = false;
    currentPalettePage = 1;  -- Reset to page 1
end

function M.IsPaletteOpen()
    return paletteOpen;
end

function M.TogglePalette()
    if paletteOpen then
        M.ClosePalette();
    else
        M.OpenPalette();
    end
end

-- Draw a single macro tile (used in palette)
local function DrawMacroTile(macro, index, x, y, size)
    local isSelected = selectedMacroIndex == index;
    local isHovered = false;

    -- Set cursor position
    imgui.SetCursorScreenPos({x, y});

    -- Draw button with XIUI styling
    if isSelected then
        -- Selected state: gold tinted
        imgui.PushStyleColor(ImGuiCol_Button, {0.15, 0.13, 0.08, 0.95});
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0.2, 0.17, 0.1, 0.95});
        imgui.PushStyleColor(ImGuiCol_ButtonActive, COLORS.bgLighter);
    else
        -- Normal state: dark with subtle highlight
        imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgDark);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.bgMedium);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, COLORS.bgLight);
    end

    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 4);
    imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 1);
    imgui.PushStyleColor(ImGuiCol_Border, isSelected and COLORS.gold or COLORS.border);

    local buttonId = string.format('##macrotile%d', index);
    if imgui.Button(buttonId, {size, size}) then
        selectedMacroIndex = index;
    end

    imgui.PopStyleColor(4);
    imgui.PopStyleVar(2);

    isHovered = imgui.IsItemHovered();

    -- Draw icon if available, otherwise show abbreviated text
    local icon = actions.GetBindIcon(macro);
    local iconRendered = false;

    if icon and icon.image then
        local drawList = imgui.GetWindowDrawList();
        if drawList then
            local iconSize = size - 8;  -- Slightly smaller than tile
            local iconX = x + 4;
            local iconY = y + 4;
            local iconPtr = tonumber(ffi.cast("uint32_t", icon.image));
            if iconPtr and iconPtr ~= 0 then
                drawList:AddImage(
                    iconPtr,
                    {iconX, iconY},
                    {iconX + iconSize, iconY + iconSize}
                );
                iconRendered = true;
            end
        end
    end

    -- No icon rendered - show abbreviated action name
    if not iconRendered then
        local drawList = imgui.GetForegroundDrawList();
        if drawList then
            local abbr = GetActionAbbreviation(macro);
            local textSize = imgui.CalcTextSize(abbr);
            local textX = x + (size - textSize) / 2;
            local textY = y + (size - 14) / 2;
            local textColor = imgui.GetColorU32(COLORS.gold);
            drawList:AddText({textX, textY}, textColor, abbr);
        end
    end

    -- Handle drag source - use custom dragdrop library
    if imgui.IsItemActive() and imgui.IsMouseDragging(0, 3) then
        if not dragdrop.IsDragging() and not dragdrop.IsDragPending() then
            M.StartDragMacro(index, macro);
        end
    end

    -- Tooltip with full info
    if isHovered then
        imgui.PushStyleColor(ImGuiCol_PopupBg, COLORS.bgDark);
        imgui.PushStyleColor(ImGuiCol_Border, COLORS.border);
        imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {8, 6});
        imgui.BeginTooltip();
        imgui.TextColored(COLORS.gold, macro.displayName or macro.action or 'Unknown');
        imgui.Spacing();
        imgui.TextColored(COLORS.textDim, 'Type: ' .. (ACTION_TYPE_LABELS[macro.actionType] or macro.actionType or '?'));
        if macro.actionType ~= 'macro' and macro.target then
            imgui.TextColored(COLORS.textDim, 'Target: <' .. macro.target .. '>');
        end
        imgui.Spacing();
        imgui.TextColored(COLORS.textMuted, 'Drag to hotbar slot');
        imgui.EndTooltip();
        imgui.PopStyleVar();
        imgui.PopStyleColor(2);
    end

    return isHovered;
end

-- Apply XIUI window styling
local function PushWindowStyle()
    imgui.PushStyleColor(ImGuiCol_WindowBg, COLORS.bgDark);
    imgui.PushStyleColor(ImGuiCol_TitleBg, COLORS.bgMedium);
    imgui.PushStyleColor(ImGuiCol_TitleBgActive, COLORS.bgLight);
    imgui.PushStyleColor(ImGuiCol_Border, COLORS.border);
    imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgMedium);
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.bgLight);
    imgui.PushStyleColor(ImGuiCol_ButtonActive, COLORS.bgLighter);
    imgui.PushStyleColor(ImGuiCol_FrameBg, COLORS.bgDark);
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, COLORS.bgMedium);
    imgui.PushStyleColor(ImGuiCol_FrameBgActive, COLORS.bgLight);
    imgui.PushStyleColor(ImGuiCol_Header, COLORS.bgMedium);
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, COLORS.bgLight);
    imgui.PushStyleColor(ImGuiCol_HeaderActive, COLORS.bgLighter);
    imgui.PushStyleColor(ImGuiCol_Separator, COLORS.border);
    imgui.PushStyleColor(ImGuiCol_Text, COLORS.text);
    -- Scrollbar colors
    imgui.PushStyleColor(ImGuiCol_ScrollbarBg, COLORS.bgDark);
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrab, COLORS.bgLight);
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabHovered, COLORS.bgLighter);
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabActive, COLORS.gold);
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 4);
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 3);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {10, 10});
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {6, 4});
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {8, 6});
end

local function PopWindowStyle()
    imgui.PopStyleVar(5);
    imgui.PopStyleColor(19);  -- 15 base + 4 scrollbar colors
end

-- Build job list for dropdown
local JOB_LIST = {};
local JOB_ID_MAP = {};
for jobId, jobName in pairs(jobs) do
    table.insert(JOB_LIST, { id = jobId, name = jobName });
end
table.sort(JOB_LIST, function(a, b) return a.id < b.id; end);
for i, job in ipairs(JOB_LIST) do
    JOB_ID_MAP[job.id] = i;
end

-- Draw the palette window
function M.DrawPalette()
    if not paletteOpen then
        return;
    end

    -- Continuously check for job changes while palette is open
    -- This catches cases where job changed but cache wasn't refreshed properly
    RefreshCachedLists();

    -- Initialize selectedPaletteType to current job if not set
    if not selectedPaletteType then
        selectedPaletteType = data.jobId or 1;
    end

    local db, typeKey = M.GetMacroDatabase();
    local isGlobal = (typeKey == GLOBAL_MACRO_KEY);
    local typeName = GetPaletteDisplayName(typeKey);
    local currentPlayerJob = data.jobId or 1;
    -- For SMN with avatar selected, check base job ID
    local baseJobId = type(typeKey) == 'number' and typeKey or tonumber(tostring(typeKey):match('^(%d+)'));
    local isViewingCurrentJob = (not isGlobal and baseJobId == currentPlayerJob);

    -- Calculate pagination
    local totalMacros = #db;
    local totalPages = math.max(1, math.ceil(totalMacros / PALETTE_MACROS_PER_PAGE));

    -- Clamp current page to valid range
    if currentPalettePage > totalPages then
        currentPalettePage = totalPages;
    end
    if currentPalettePage < 1 then
        currentPalettePage = 1;
    end

    -- Calculate how many macros/rows on this page
    local startIdx = (currentPalettePage - 1) * PALETTE_MACROS_PER_PAGE + 1;
    local endIdx = math.min(startIdx + PALETTE_MACROS_PER_PAGE - 1, totalMacros);
    local macrosOnPage = math.max(0, endIdx - startIdx + 1);
    local rowsOnPage = math.max(1, math.ceil(macrosOnPage / PALETTE_COLUMNS));

    -- Calculate grid dimensions
    local gridWidth = PALETTE_COLUMNS * PALETTE_TILE_SIZE + (PALETTE_COLUMNS - 1) * PALETTE_TILE_GAP;
    local gridHeight = rowsOnPage * PALETTE_TILE_SIZE + (rowsOnPage - 1) * PALETTE_TILE_GAP;

    local windowFlags = bit.bor(
        ImGuiWindowFlags_NoCollapse,
        ImGuiWindowFlags_AlwaysAutoResize,
        ImGuiWindowFlags_NoScrollbar
    );

    local isOpen = { true };

    -- Apply XIUI styling
    PushWindowStyle();

    if imgui.Begin('Macro Palette###MacroPalette', isOpen, windowFlags) then
        -- Header with gold accent
        imgui.TextColored(COLORS.gold, 'Drag macros to your hotbar slots');
        imgui.Spacing();

        -- Type selector row
        imgui.TextColored(COLORS.textDim, 'Type:');
        imgui.SameLine();

        -- Style the combo popup
        PushComboStyle();
        imgui.PushItemWidth(100);

        -- Helper to get macro count for a type (Global or job ID)
        local function getMacroCount(key)
            if gConfig.macroDB and gConfig.macroDB[key] then
                return #gConfig.macroDB[key];
            end
            return 0;
        end

        -- Build display label with macro count
        local macroCount = getMacroCount(typeKey);
        local displayLabel = macroCount > 0 and string.format('%s (%d)', typeName, macroCount) or typeName;

        if imgui.BeginCombo('##TypeSelect', displayLabel, ImGuiComboFlags_None) then
            -- Global option first
            local globalSelected = isGlobal;
            local globalMacroCount = getMacroCount(GLOBAL_MACRO_KEY);
            local globalLabel = 'Global';
            if globalMacroCount > 0 then
                globalLabel = string.format('Global (%d)', globalMacroCount);
            end

            -- Highlight Global if it has macros
            if globalMacroCount > 0 and not globalSelected then
                imgui.PushStyleColor(ImGuiCol_Text, COLORS.text);
            elseif globalSelected then
                imgui.PushStyleColor(ImGuiCol_Text, COLORS.gold);
            else
                imgui.PushStyleColor(ImGuiCol_Text, COLORS.textDim);
            end

            if imgui.Selectable(globalLabel, globalSelected) then
                selectedPaletteType = GLOBAL_MACRO_KEY;
                selectedAvatarPalette = nil;
                selectedMacroIndex = nil;
                currentPalettePage = 1;
                -- Clear caches to force refresh
                playerdata.ClearCache();
                cachedPetCommands = nil;
                petAvatarFilter = 1;
            end
            imgui.PopStyleColor();

            if globalSelected then
                imgui.SetItemDefaultFocus();
            end

            -- Separator between Global and jobs
            imgui.Separator();

            -- Job options
            for i, job in ipairs(JOB_LIST) do
                local isSelected = (not isGlobal and job.id == typeKey);
                local jobMacroCount = getMacroCount(job.id);

                -- Build label with indicators
                local label = job.name;

                -- Add macro count if > 0
                if jobMacroCount > 0 then
                    label = string.format('%s (%d)', label, jobMacroCount);
                end

                -- Add main job indicator
                if job.id == currentPlayerJob then
                    label = label .. '  *';
                end

                -- Add subjob indicator
                if job.id == data.subjobId then
                    label = label .. '  /sub';
                end

                -- Highlight jobs with macros
                if jobMacroCount > 0 and not isSelected then
                    imgui.PushStyleColor(ImGuiCol_Text, COLORS.text);
                elseif isSelected then
                    imgui.PushStyleColor(ImGuiCol_Text, COLORS.gold);
                else
                    imgui.PushStyleColor(ImGuiCol_Text, COLORS.textDim);
                end

                if imgui.Selectable(label, isSelected) then
                    selectedPaletteType = job.id;
                    selectedAvatarPalette = nil;  -- Clear avatar selection when switching jobs
                    selectedMacroIndex = nil;  -- Clear selection when switching types
                    currentPalettePage = 1;    -- Reset to page 1 when switching types
                    -- Clear caches to force refresh
                    playerdata.ClearCache();
                    cachedPetCommands = nil;
                    petAvatarFilter = 1;
                end

                imgui.PopStyleColor();

                if isSelected then
                    imgui.SetItemDefaultFocus();
                end
            end
            imgui.EndCombo();
        end
        imgui.PopItemWidth();
        PopComboStyle();

        -- Avatar sub-palette dropdown (only for SMN)
        -- Use selectedPaletteType (the job ID) not typeKey (which may be composite like "15:avatar:ifrit")
        if not isGlobal and selectedPaletteType == petregistry.JOB_SMN then
            imgui.SameLine();
            local avatarList = petregistry.GetAvatarList();
            local avatarLabel = selectedAvatarPalette or 'Base SMN';

            -- Count macros for current avatar selection
            local avatarMacroCount = 0;
            local currentAvatarKey = GetEffectivePaletteType();
            if gConfig.macroDB and gConfig.macroDB[currentAvatarKey] then
                avatarMacroCount = #gConfig.macroDB[currentAvatarKey];
            end
            if avatarMacroCount > 0 then
                avatarLabel = string.format('%s (%d)', avatarLabel, avatarMacroCount);
            end

            PushComboStyle();
            imgui.SetNextItemWidth(140);
            if imgui.BeginCombo('##AvatarPalette', avatarLabel, ImGuiComboFlags_None) then
                -- Base SMN option
                local isBaseSelected = selectedAvatarPalette == nil;
                local baseMacroCount = 0;
                if gConfig.macroDB and gConfig.macroDB[petregistry.JOB_SMN] then
                    baseMacroCount = #gConfig.macroDB[petregistry.JOB_SMN];
                end
                local baseLabel = baseMacroCount > 0 and string.format('Base SMN (%d)', baseMacroCount) or 'Base SMN';

                if isBaseSelected then
                    imgui.PushStyleColor(ImGuiCol_Text, COLORS.gold);
                elseif baseMacroCount > 0 then
                    imgui.PushStyleColor(ImGuiCol_Text, COLORS.text);
                else
                    imgui.PushStyleColor(ImGuiCol_Text, COLORS.textDim);
                end

                if imgui.Selectable(baseLabel, isBaseSelected) then
                    selectedAvatarPalette = nil;
                    selectedMacroIndex = nil;
                    currentPalettePage = 1;
                    cachedPetCommands = nil;  -- Refresh pet commands for new avatar
                end
                imgui.PopStyleColor();

                if isBaseSelected then
                    imgui.SetItemDefaultFocus();
                end

                imgui.Separator();

                -- Avatar options
                for _, avatar in ipairs(avatarList) do
                    local isSelected = selectedAvatarPalette == avatar;
                    local avatarKey = petregistry.avatars[avatar];
                    local fullKey = string.format('%d:avatar:%s', petregistry.JOB_SMN, avatarKey);
                    local macroCount = 0;
                    if gConfig.macroDB and gConfig.macroDB[fullKey] then
                        macroCount = #gConfig.macroDB[fullKey];
                    end
                    local label = macroCount > 0 and string.format('%s (%d)', avatar, macroCount) or avatar;

                    if isSelected then
                        imgui.PushStyleColor(ImGuiCol_Text, COLORS.gold);
                    elseif macroCount > 0 then
                        imgui.PushStyleColor(ImGuiCol_Text, COLORS.text);
                    else
                        imgui.PushStyleColor(ImGuiCol_Text, COLORS.textDim);
                    end

                    if imgui.Selectable(label, isSelected) then
                        selectedAvatarPalette = avatar;
                        selectedMacroIndex = nil;
                        currentPalettePage = 1;
                        cachedPetCommands = nil;  -- Refresh pet commands for new avatar
                    end
                    imgui.PopStyleColor();

                    if isSelected then
                        imgui.SetItemDefaultFocus();
                    end
                end
                imgui.EndCombo();
            end
            PopComboStyle();
        end

        -- Pet Palette section (only show if selected palette type is a pet job AND any bar has petAware enabled)
        local isPetJob = false;
        if selectedPaletteType and type(selectedPaletteType) == 'number' then
            isPetJob = petregistry.IsPetJob(selectedPaletteType);
        end

        local hasPetAwareBar = false;
        if isPetJob then
            for barIndex = 1, data.NUM_BARS do
                local barSettings = data.GetBarSettings(barIndex);
                if barSettings and barSettings.petAware then
                    hasPetAwareBar = true;
                    break;
                end
            end
        end

        if hasPetAwareBar then
            imgui.Spacing();
            imgui.Separator();
            imgui.Spacing();

            -- Show current pet detection
            local currentPetKey = petpalette.GetCurrentPetKey();
            local petDisplayName = currentPetKey and petregistry.GetDisplayNameForKey(currentPetKey) or 'No Pet';

            imgui.TextColored(COLORS.textDim, 'Active Pet:');
            imgui.SameLine();
            if currentPetKey then
                imgui.TextColored({0.5, 1.0, 0.8, 1.0}, petDisplayName);
            else
                imgui.TextColored(COLORS.textMuted, petDisplayName);
            end

            -- Show per-bar palette status with dropdown
            imgui.Spacing();
            local allSummons = petregistry.GetAllSummonsList();

            for barIndex = 1, data.NUM_BARS do
                local barSettings = data.GetBarSettings(barIndex);
                if barSettings and barSettings.petAware and barSettings.enabled then
                    local paletteName = petpalette.GetPaletteDisplayName(barIndex, data.jobId);
                    local hasOverride = petpalette.HasManualOverride(barIndex);

                    imgui.TextColored(COLORS.textDim, string.format('Bar %d:', barIndex));
                    imgui.SameLine();

                    -- Dropdown for palette selection
                    local currentLabel = hasOverride and paletteName or 'Automatic';

                    PushComboStyle();
                    imgui.SetNextItemWidth(130);
                    if imgui.BeginCombo('##petPalette' .. barIndex, currentLabel, ImGuiComboFlags_None) then
                        -- Automatic option (first)
                        local isAutoSelected = not hasOverride;
                        if isAutoSelected then
                            imgui.PushStyleColor(ImGuiCol_Text, COLORS.gold);
                        else
                            imgui.PushStyleColor(ImGuiCol_Text, COLORS.text);
                        end

                        if imgui.Selectable('Automatic', isAutoSelected) then
                            petpalette.SetPalette(barIndex, nil);
                            local slotrenderer = require('modules.hotbar.slotrenderer');
                            slotrenderer.ClearAllCache();
                            ClearAllIconCaches();
                        end
                        imgui.PopStyleColor();

                        if isAutoSelected then
                            imgui.SetItemDefaultFocus();
                        end

                        imgui.Separator();

                        -- Avatars section
                        imgui.TextColored(COLORS.textDim, 'Avatars');
                        for _, summon in ipairs(allSummons) do
                            if summon.category == 'avatar' then
                                local petKey = petregistry.GetPetKeyForSummon(summon.name);
                                local isSelected = hasOverride and petpalette.GetPaletteDisplayName(barIndex, data.jobId) == summon.name;

                                if isSelected then
                                    imgui.PushStyleColor(ImGuiCol_Text, COLORS.gold);
                                else
                                    imgui.PushStyleColor(ImGuiCol_Text, COLORS.text);
                                end

                                if imgui.Selectable('  ' .. summon.name, isSelected) then
                                    petpalette.SetPalette(barIndex, petKey);
                                    local slotrenderer = require('modules.hotbar.slotrenderer');
                                    slotrenderer.ClearAllCache();
                                    ClearAllIconCaches();
                                end
                                imgui.PopStyleColor();

                                if isSelected then
                                    imgui.SetItemDefaultFocus();
                                end
                            end
                        end

                        imgui.Separator();

                        -- Spirits section
                        imgui.TextColored(COLORS.textDim, 'Spirits');
                        for _, summon in ipairs(allSummons) do
                            if summon.category == 'spirit' then
                                local petKey = petregistry.GetPetKeyForSummon(summon.name);
                                local isSelected = hasOverride and petpalette.GetPaletteDisplayName(barIndex, data.jobId) == summon.name;

                                if isSelected then
                                    imgui.PushStyleColor(ImGuiCol_Text, COLORS.gold);
                                else
                                    imgui.PushStyleColor(ImGuiCol_Text, COLORS.text);
                                end

                                if imgui.Selectable('  ' .. summon.name, isSelected) then
                                    petpalette.SetPalette(barIndex, petKey);
                                    local slotrenderer = require('modules.hotbar.slotrenderer');
                                    slotrenderer.ClearAllCache();
                                    ClearAllIconCaches();
                                end
                                imgui.PopStyleColor();

                                if isSelected then
                                    imgui.SetItemDefaultFocus();
                                end
                            end
                        end

                        imgui.EndCombo();
                    end
                    PopComboStyle();
                end
            end
        end

        imgui.Spacing();

        -- Button row with XIUI button styling
        imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgLight);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.bgLighter);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, {0.2, 0.18, 0.15, 1.0});
        imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 1);
        imgui.PushStyleColor(ImGuiCol_Border, COLORS.gold);
        imgui.PushStyleColor(ImGuiCol_Text, COLORS.gold);

        if imgui.Button('+ New Macro', {115, 26}) then
            isCreatingNew = true;
            editingMacro = {
                actionType = 'ma',
                action = '',
                target = 't',
                displayName = '',
            };
            selectedMacroIndex = nil;
        end

        imgui.PopStyleColor(5);
        imgui.PopStyleVar();

        imgui.SameLine();

        -- Edit/Delete buttons (always visible, disabled when no selection)
        local hasSelection = selectedMacroIndex and db[selectedMacroIndex];

        if not hasSelection then
            imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.4);
        end

        if imgui.Button('Edit', {60, 26}) and hasSelection then
            editingMacro = deep_copy_table(db[selectedMacroIndex]);
            isCreatingNew = false;
        end

        imgui.SameLine();

        -- Delete button with danger styling (or dimmed when disabled)
        if hasSelection then
            imgui.PushStyleColor(ImGuiCol_Button, COLORS.dangerDim);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.danger);
            imgui.PushStyleColor(ImGuiCol_ButtonActive, {0.9, 0.35, 0.35, 1.0});
        end

        if imgui.Button('Delete', {60, 26}) and hasSelection then
            M.DeleteMacro(db[selectedMacroIndex].id);
            selectedMacroIndex = nil;
        end

        if hasSelection then
            imgui.PopStyleColor(3);
        end

        if not hasSelection then
            imgui.PopStyleVar();
        end

        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();

        -- Macro grid
        if #db == 0 then
            imgui.TextColored(COLORS.textDim, 'No macros yet.');
            imgui.TextColored(COLORS.textMuted, 'Click "+ New Macro" to create one.');
        else
            -- Draw grid row by row using standard ImGui layout
            for row = 0, rowsOnPage - 1 do
                for col = 0, PALETTE_COLUMNS - 1 do
                    local idx = startIdx + row * PALETTE_COLUMNS + col;
                    if idx <= endIdx then
                        local macro = db[idx];
                        if macro then
                            if col > 0 then
                                imgui.SameLine(0, PALETTE_TILE_GAP);
                            end

                            -- Draw the tile inline
                            local isSelected = selectedMacroIndex == idx;

                            if isSelected then
                                imgui.PushStyleColor(ImGuiCol_Button, {0.15, 0.13, 0.08, 0.95});
                                imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0.2, 0.17, 0.1, 0.95});
                                imgui.PushStyleColor(ImGuiCol_ButtonActive, COLORS.bgLighter);
                            else
                                imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgDark);
                                imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.bgMedium);
                                imgui.PushStyleColor(ImGuiCol_ButtonActive, COLORS.bgLight);
                            end

                            imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 4);
                            imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 1);
                            imgui.PushStyleColor(ImGuiCol_Border, isSelected and COLORS.gold or COLORS.border);

                            local buttonId = string.format('##macrotile%d', idx);
                            local buttonPos = {imgui.GetCursorScreenPos()};

                            if imgui.Button(buttonId, {PALETTE_TILE_SIZE, PALETTE_TILE_SIZE}) then
                                selectedMacroIndex = idx;
                            end

                            imgui.PopStyleColor(4);
                            imgui.PopStyleVar(2);

                            -- Draw icon on top of button, or abbreviation if no icon
                            local icon = actions.GetBindIcon(macro);
                            local iconRendered = false;
                            if icon and icon.image then
                                local drawList = imgui.GetWindowDrawList();
                                if drawList then
                                    local iconSize = PALETTE_TILE_SIZE - 8;
                                    local iconX = buttonPos[1] + 4;
                                    local iconY = buttonPos[2] + 4;
                                    local iconPtr = tonumber(ffi.cast("uint32_t", icon.image));
                                    if iconPtr and iconPtr ~= 0 then
                                        drawList:AddImage(iconPtr, {iconX, iconY}, {iconX + iconSize, iconY + iconSize});
                                        iconRendered = true;
                                    end
                                end
                            end

                            -- No icon - show abbreviated action name
                            if not iconRendered then
                                local drawList = imgui.GetWindowDrawList();
                                if drawList then
                                    local abbr = GetActionAbbreviation(macro);
                                    local textSize = imgui.CalcTextSize(abbr);
                                    local textX = buttonPos[1] + (PALETTE_TILE_SIZE - textSize) / 2;
                                    local textY = buttonPos[2] + (PALETTE_TILE_SIZE - 14) / 2;
                                    local textColor = imgui.GetColorU32(COLORS.gold);
                                    drawList:AddText({textX, textY}, textColor, abbr);
                                end
                            end

                            -- Handle drag
                            if imgui.IsItemActive() and imgui.IsMouseDragging(0, 3) then
                                if not dragdrop.IsDragging() and not dragdrop.IsDragPending() then
                                    M.StartDragMacro(idx, macro);
                                end
                            end

                            -- Tooltip
                            if imgui.IsItemHovered() then
                                imgui.PushStyleColor(ImGuiCol_PopupBg, COLORS.bgDark);
                                imgui.PushStyleColor(ImGuiCol_Border, COLORS.border);
                                imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {8, 6});
                                imgui.BeginTooltip();
                                imgui.TextColored(COLORS.gold, macro.displayName or macro.action or 'Unknown');
                                imgui.Spacing();
                                imgui.TextColored(COLORS.textDim, 'Type: ' .. (ACTION_TYPE_LABELS[macro.actionType] or macro.actionType or '?'));
                                if macro.actionType ~= 'macro' and macro.target then
                                    imgui.TextColored(COLORS.textDim, 'Target: <' .. macro.target .. '>');
                                end
                                imgui.Spacing();
                                imgui.TextColored(COLORS.textMuted, 'Drag to hotbar slot');
                                imgui.EndTooltip();
                                imgui.PopStyleVar();
                                imgui.PopStyleColor(2);
                            end
                        end
                    end
                end
            end

            -- Reserve remaining space to always have full 6x6 grid height
            if rowsOnPage < PALETTE_ROWS then
                local remainingRows = PALETTE_ROWS - rowsOnPage;
                local remainingHeight = remainingRows * (PALETTE_TILE_SIZE + PALETTE_TILE_GAP);
                imgui.Dummy({gridWidth, remainingHeight});
            end
        end

        -- Pagination controls (always visible, arrows disabled at boundaries)
        imgui.Spacing();

        -- Center the pagination controls
        local paginationWidth = 200;
        local winWidth = imgui.GetWindowWidth();
        local paginationStartX = (winWidth - paginationWidth) / 2;
        imgui.SetCursorPosX(paginationStartX);

        -- Previous button (disabled when on first page)
        local canGoPrev = currentPalettePage > 1;
        if not canGoPrev then
            imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.3);
        end
        if imgui.Button('<##PrevPage', {30, 22}) and canGoPrev then
            currentPalettePage = currentPalettePage - 1;
            selectedMacroIndex = nil;
        end
        if not canGoPrev then
            imgui.PopStyleVar();
        end

        imgui.SameLine();

        -- Page indicator
        local pageText = string.format('Page %d / %d', currentPalettePage, totalPages);
        local textWidth = imgui.CalcTextSize(pageText);
        imgui.SetCursorPosX(paginationStartX + (paginationWidth - textWidth) / 2);
        imgui.TextColored(COLORS.textDim, pageText);

        imgui.SameLine();
        imgui.SetCursorPosX(paginationStartX + paginationWidth - 30);

        -- Next button (disabled when on last page)
        local canGoNext = currentPalettePage < totalPages;
        if not canGoNext then
            imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.3);
        end
        if imgui.Button('>##NextPage', {30, 22}) and canGoNext then
            currentPalettePage = currentPalettePage + 1;
            selectedMacroIndex = nil;
        end
        if not canGoNext then
            imgui.PopStyleVar();
        end
    end

    imgui.End();
    PopWindowStyle();

    -- Handle window close
    if not isOpen[1] then
        M.ClosePalette();
    end

    -- Draw macro editor popup if needed
    if editingMacro then
        M.DrawMacroEditor();
    end
end

-- ============================================
-- Macro Editor Popup
-- ============================================

-- Editor state
local editorFields = {
    actionType = { 1 },
    action = { '' },
    target = { 1 },
    displayName = { '' },
    equipSlot = { 1 },
    macroText = { '' },
};

local TARGET_OPTIONS = { 'me', 't', 'stpc', 'stnpc', 'st', 'bt', 'lastst', 'stal', 'stpt', 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' };
local TARGET_LABELS = {
    me = '<me> (Self)',
    t = '<t> (Current Target)',
    stpc = '<stpc> (Select Player)',
    stnpc = '<stnpc> (Select NPC/Enemy)',
    st = '<st> (Sub Target)',
    bt = '<bt> (Battle Target)',
    lastst = '<lastst> (Last Sub Target)',
    stal = '<stal> (Select Alliance)',
    stpt = '<stpt> (Select Party)',
    p0 = '<p0> (Party Member 1)',
    p1 = '<p1> (Party Member 2)',
    p2 = '<p2> (Party Member 3)',
    p3 = '<p3> (Party Member 4)',
    p4 = '<p4> (Party Member 5)',
    p5 = '<p5> (Party Member 6)',
};

local EQUIP_SLOTS = { 'main', 'sub', 'range', 'ammo', 'head', 'body', 'hands', 'legs', 'feet', 'neck', 'waist', 'ear1', 'ear2', 'ring1', 'ring2', 'back' };
local EQUIP_SLOT_LABELS = {
    main = 'Main Hand',
    sub = 'Sub/Shield',
    range = 'Range',
    ammo = 'Ammo',
    head = 'Head',
    body = 'Body',
    hands = 'Hands',
    legs = 'Legs',
    feet = 'Feet',
    neck = 'Neck',
    waist = 'Waist',
    ear1 = 'Ear 1',
    ear2 = 'Ear 2',
    ring1 = 'Ring 1',
    ring2 = 'Ring 2',
    back = 'Back',
};

local function FindIndex(array, value)
    for i, v in ipairs(array) do
        if v == value then return i; end
    end
    return 1;
end

-- Draw icon preview box with current icon
local function DrawIconPreview(macro, x, y, size)
    local drawList = imgui.GetWindowDrawList();
    if not drawList then return; end

    -- Draw background box
    local bgColor = imgui.GetColorU32({0.1, 0.09, 0.08, 0.95});
    local borderColor = imgui.GetColorU32(COLORS.border);
    drawList:AddRectFilled({x, y}, {x + size, y + size}, bgColor, 4);
    drawList:AddRect({x, y}, {x + size, y + size}, borderColor, 4, 0, 1);

    -- Draw icon if available
    local icon = actions.GetBindIcon(macro);
    if icon and icon.image then
        local iconPtr = tonumber(ffi.cast("uint32_t", icon.image));
        if iconPtr then
            local padding = 4;
            drawList:AddImage(
                iconPtr,
                {x + padding, y + padding},
                {x + size - padding, y + size - padding}
            );
        end
    else
        -- No icon - show abbreviated action name (prefer action for preview)
        local abbr = GetActionAbbreviation(macro, true);
        local textSize = imgui.CalcTextSize(abbr);
        local textX = x + (size - textSize) / 2;
        local textY = y + (size - 14) / 2;
        local textColor = imgui.GetColorU32(COLORS.gold);
        drawList:AddText({textX, textY}, textColor, abbr);
    end
end

-- Helper to draw an icon button (works around ImageButton signature issues)
local function DrawIconButton(id, icon, size, isSelected, tooltipText)
    local clicked = false;
    local drawList = imgui.GetWindowDrawList();

    -- Style for selection
    if isSelected then
        imgui.PushStyleColor(ImGuiCol_Button, {0.2, 0.18, 0.1, 1.0});
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0.25, 0.22, 0.12, 1.0});
        imgui.PushStyleColor(ImGuiCol_Border, COLORS.gold);
        imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 2);
    else
        imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgDark);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.bgMedium);
        imgui.PushStyleColor(ImGuiCol_Border, COLORS.border);
        imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 1);
    end

    -- Get position before button
    local cursorPos = {imgui.GetCursorScreenPos()};

    -- Draw invisible button for click detection
    if imgui.Button(id, {size, size}) then
        clicked = true;
    end

    imgui.PopStyleVar();
    imgui.PopStyleColor(3);

    -- Draw icon on top
    if icon and icon.image and drawList then
        local iconPtr = tonumber(ffi.cast("uint32_t", icon.image));
        if iconPtr then
            local padding = 4;
            drawList:AddImage(
                iconPtr,
                {cursorPos[1] + padding, cursorPos[2] + padding},
                {cursorPos[1] + size - padding, cursorPos[2] + size - padding}
            );
        end
    end

    -- Tooltip
    if imgui.IsItemHovered() and tooltipText then
        imgui.BeginTooltip();
        imgui.Text(tooltipText);
        imgui.EndTooltip();
    end

    return clicked;
end

-- Draw the icon picker popup
local function DrawIconPicker()
    if not iconPickerOpen or not editingMacro then
        return;
    end

    -- Start item loading when items tab is selected
    if iconPickerTab == 2 then
        StartItemIconLoading();
        LoadItemIconBatch();  -- Load a batch each frame
    end

    local isOpen = { true };

    -- Calculate window size for 12 icons per row
    -- Grid: 12 icons * 36px + 11 gaps * 4px = 432 + 44 = 476px
    -- Add padding (16px) + scrollbar (~16px) + child border (4px) = 512px
    local gridContentWidth = (ICON_GRID_SIZE * ICON_GRID_COLUMNS) + (ICON_GRID_GAP * (ICON_GRID_COLUMNS - 1));
    local windowWidth = gridContentWidth + 40;  -- padding + scrollbar + borders
    local windowHeight = 500;  -- Extra height for spell type filter buttons

    imgui.SetNextWindowSize({windowWidth, windowHeight}, ImGuiCond_FirstUseEver);

    PushWindowStyle();

    if imgui.Begin('Select Icon###IconPicker', isOpen, ImGuiWindowFlags_NoCollapse) then
        -- Tab buttons
        imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 1);

        local tabWidth = 70;

        -- Spells tab
        if iconPickerTab == 1 then
            imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgLight);
            imgui.PushStyleColor(ImGuiCol_Border, COLORS.gold);
        else
            imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgDark);
            imgui.PushStyleColor(ImGuiCol_Border, COLORS.border);
        end
        if imgui.Button('Spells', {tabWidth, 24}) then
            iconPickerTab = 1;
            -- Keep filter text, don't reset - reduces lag from cache rebuilds
        end
        imgui.PopStyleColor(2);

        imgui.SameLine();

        -- Items tab
        if iconPickerTab == 2 then
            imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgLight);
            imgui.PushStyleColor(ImGuiCol_Border, COLORS.gold);
        else
            imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgDark);
            imgui.PushStyleColor(ImGuiCol_Border, COLORS.border);
        end
        if imgui.Button('Items', {tabWidth, 24}) then
            iconPickerTab = 2;
            -- Keep filter text, don't reset - reduces lag from cache rebuilds
        end
        imgui.PopStyleColor(2);

        imgui.SameLine();

        -- Custom tab
        if iconPickerTab == 3 then
            imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgLight);
            imgui.PushStyleColor(ImGuiCol_Border, COLORS.gold);
        else
            imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgDark);
            imgui.PushStyleColor(ImGuiCol_Border, COLORS.border);
        end
        if imgui.Button('Custom', {tabWidth, 24}) then
            iconPickerTab = 3;
            -- Keep filter text, don't reset - reduces lag from cache rebuilds
        end
        imgui.PopStyleColor(2);

        imgui.SameLine();

        -- Clear icon button
        imgui.PushStyleColor(ImGuiCol_Button, COLORS.dangerDim);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.danger);
        imgui.PushStyleColor(ImGuiCol_Border, COLORS.danger);
        if imgui.Button('Clear', {50, 24}) then
            editingMacro.customIconType = nil;
            editingMacro.customIconId = nil;
            editingMacro.customIconPath = nil;
            iconPickerOpen = false;
        end
        imgui.PopStyleColor(3);

        imgui.PopStyleVar();

        imgui.Spacing();

        -- Search filter
        imgui.TextColored(COLORS.goldDim, 'Search:');
        imgui.SameLine();
        imgui.SetNextItemWidth(200);
        imgui.InputText('##iconSearch', iconPickerFilter, INPUT_BUFFER_SIZE);

        -- Show loading status for items tab (count shown near page navigation)
        if iconPickerTab == 2 and itemIconLoadState.loading then
            imgui.SameLine();
            imgui.TextColored(COLORS.textMuted, string.format('Loading... %d%%', GetItemLoadProgress()));
        end

        imgui.Spacing();

        -- Spell type filter buttons with icons (only for spells tab)
        if iconPickerTab == 1 then
            local filterIconSize = 24;
            imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 2);
            imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {3, 3});
            imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {2, 2});

            for i, spellType in ipairs(SPELL_TYPE_ORDER) do
                local tooltip = SPELL_TYPE_LABELS[spellType] or spellType;
                local isSelected = iconPickerSpellType == spellType;

                if isSelected then
                    imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgLight);
                    imgui.PushStyleColor(ImGuiCol_Border, COLORS.gold);
                else
                    imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgDark);
                    imgui.PushStyleColor(ImGuiCol_Border, COLORS.border);
                end

                -- Get job/trust icon
                local icon = GetFilterIcon(spellType);

                imgui.PopStyleColor(2);

                -- Use DrawIconButton which works on all Ashita versions
                if DrawIconButton('##spellFilter' .. i, icon, filterIconSize, isSelected, tooltip) then
                    iconPickerSpellType = spellType;
                    iconPickerPage[1] = 1;
                end

                if i < #SPELL_TYPE_ORDER then
                    imgui.SameLine();
                end
            end

            imgui.PopStyleVar(3);
            imgui.Spacing();
        end

        -- Item type filter buttons with icons (only for items tab)
        if iconPickerTab == 2 then
            local filterIconSize = 24;
            imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 2);
            imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {3, 3});
            imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {2, 2});

            for i, itemType in ipairs(ITEM_TYPE_ORDER) do
                local tooltip = ITEM_TYPE_LABELS[itemType] or tostring(itemType);
                local isSelected = iconPickerItemType == itemType;
                local itemId = ITEM_TYPE_ICONS[itemType];

                -- Get item icon texture
                local icon = actions.GetBindIcon({ actionType = 'item', itemId = itemId });

                -- Use DrawIconButton which works on all Ashita versions
                if DrawIconButton('##itemFilter' .. i, icon, filterIconSize, isSelected, tooltip) then
                    iconPickerItemType = itemType;
                    iconPickerPage[2] = 1;
                end

                if i < #ITEM_TYPE_ORDER then
                    imgui.SameLine();
                end
            end

            imgui.PopStyleVar(3);
            imgui.Spacing();
        end

        -- Custom icon category filter buttons (only for custom tab)
        if iconPickerTab == 3 then
            -- Load categories if not loaded
            LoadCustomIcons();
            
            local filterIconSize = 24;
            imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 2);
            imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {3, 3});
            imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {2, 2});
            
            local buttonsPerRow = 10;  -- Wrap after this many buttons
            local buttonCount = 0;
            local totalButtons = #CUSTOM_ICON_CATEGORIES + 1;  -- +1 for the "+" button
            
            for i, category in ipairs(CUSTOM_ICON_CATEGORIES) do
                local tooltip = CUSTOM_ICON_LABELS[category] or category;
                local isSelected = customIconCategory == category;
                
                -- Get a representative icon from this category
                local categoryIcon, isEmpty = GetCustomCategoryIcon(category);
                
                if isEmpty then
                    -- Empty folder - draw a button with first letter
                    local letter = category:sub(1, 1):upper();
                    if isSelected then
                        imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgLight);
                        imgui.PushStyleColor(ImGuiCol_Border, COLORS.gold);
                    else
                        imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgDark);
                        imgui.PushStyleColor(ImGuiCol_Border, COLORS.border);
                    end
                    imgui.PushStyleColor(ImGuiCol_Text, COLORS.goldDim);
                    if imgui.Button(letter .. '##customFilter' .. i, {filterIconSize, filterIconSize}) then
                        customIconCategory = category;
                        iconPickerPage[3] = 1;
                        customIconsCacheKey = nil;
                    end
                    imgui.PopStyleColor(3);
                    if imgui.IsItemHovered() then
                        imgui.BeginTooltip();
                        imgui.Text(tooltip .. ' (empty)');
                        imgui.EndTooltip();
                    end
                else
                    -- Use DrawIconButton for categories with icons
                    if DrawIconButton('##customFilter' .. i, categoryIcon, filterIconSize, isSelected, tooltip) then
                        customIconCategory = category;
                        iconPickerPage[3] = 1;
                        customIconsCacheKey = nil;  -- Invalidate cache
                    end
                end
                
                buttonCount = buttonCount + 1;
                
                -- Handle row wrapping
                if buttonCount < totalButtons then
                    if buttonCount % buttonsPerRow == 0 then
                        -- Start new row
                    else
                        imgui.SameLine();
                    end
                end
            end
            
            -- "+" button to create new folder
            imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgDark);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.bgLight);
            imgui.PushStyleColor(ImGuiCol_Border, COLORS.border);
            imgui.PushStyleColor(ImGuiCol_Text, COLORS.gold);
            if imgui.Button('+##newCustomFolder', {filterIconSize, filterIconSize}) then
                newFolderName[1] = '';
                imgui.OpenPopup('Create Custom Folder##newFolderPopup');
            end
            imgui.PopStyleColor(4);
            if imgui.IsItemHovered() then
                imgui.BeginTooltip();
                imgui.Text('Create new folder');
                imgui.EndTooltip();
            end
            
            imgui.PopStyleVar(3);
            imgui.Spacing();
            
            -- Apply XIUI styling to popup
            imgui.PushStyleColor(ImGuiCol_PopupBg, COLORS.bgDark);
            imgui.PushStyleColor(ImGuiCol_Border, COLORS.border);
            imgui.PushStyleColor(ImGuiCol_TitleBg, COLORS.bgMedium);
            imgui.PushStyleColor(ImGuiCol_TitleBgActive, COLORS.bgMedium);
            imgui.PushStyleColor(ImGuiCol_FrameBg, COLORS.bgMedium);
            imgui.PushStyleColor(ImGuiCol_FrameBgHovered, COLORS.bgLight);
            imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgMedium);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.bgLight);
            imgui.PushStyleColor(ImGuiCol_Text, COLORS.text);
            
            if imgui.BeginPopupModal('Create Custom Folder##newFolderPopup', nil, ImGuiWindowFlags_AlwaysAutoResize) then
                imgui.TextColored(COLORS.goldDim, 'Folder name:');
                imgui.SetNextItemWidth(250);
                imgui.InputText('##newFolderInput', newFolderName, 64);
                
                imgui.Spacing();
                
                -- Create button
                imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgLight);
                if imgui.Button('Create', {120, 24}) then
                    if CreateCustomFolder(newFolderName[1]) then
                        imgui.CloseCurrentPopup();
                    end
                end
                imgui.PopStyleColor();
                imgui.SameLine();
                -- Cancel button
                if imgui.Button('Cancel', {120, 24}) then
                    imgui.CloseCurrentPopup();
                end
                
                imgui.EndPopup();
            end
            
            imgui.PopStyleColor(9);
        end

        local filter = iconPickerFilter[1]:lower();
        local currentPage = iconPickerPage[iconPickerTab];

        -- Build cache key for filtered results
        local cacheKey;
        if iconPickerTab == 1 then
            cacheKey = filter .. ':spell:' .. iconPickerSpellType;
        elseif iconPickerTab == 2 then
            cacheKey = filter .. ':item:' .. tostring(iconPickerItemType);
        elseif iconPickerTab == 3 then
            cacheKey = filter .. ':custom:' .. customIconCategory;
        end

        -- Reset page and invalidate cache if filter/type changed
        if iconPickerTab == 1 then
            if cacheKey ~= filteredSpellsCacheKey then
                iconPickerPage[1] = 1;
                currentPage = 1;
                filteredSpellsCache = nil;
                filteredSpellsCacheKey = cacheKey;
            end
        elseif iconPickerTab == 2 then
            if cacheKey ~= filteredItemsCacheKey then
                iconPickerPage[2] = 1;
                currentPage = 1;
                filteredItemsCache = nil;
                filteredItemsCacheKey = cacheKey;
            end
        elseif iconPickerTab == 3 then
            if cacheKey ~= customIconsCacheKey then
                iconPickerPage[3] = 1;
                currentPage = 1;
                customIconsCacheKey = cacheKey;
            end
        end

        -- Build filtered list (with caching to avoid rebuilding every frame)
        local filteredItems = {};
        if iconPickerTab == 1 then
            if filteredSpellsCache then
                filteredItems = filteredSpellsCache;
            else
                local allSpells = GetAllSpells();
                for _, spell in ipairs(allSpells) do
                    local spellName = spell.name or '';
                    local matchesFilter = (filter == '' or spellName:lower():find(filter, 1, true));
                    local matchesType = (iconPickerSpellType == 'All' or spell.type == iconPickerSpellType);
                    if matchesFilter and matchesType then
                        table.insert(filteredItems, spell);
                    end
                end
                filteredSpellsCache = filteredItems;
            end
        elseif iconPickerTab == 2 then
            -- Only use cache if: cache exists, not loading, and cache has items (or items DB is empty)
            local cacheValid = filteredItemsCache
                and not itemIconLoadState.loading
                and (#filteredItemsCache > 0 or #itemIconLoadState.items == 0);

            if cacheValid then
                filteredItems = filteredItemsCache;
            else
                -- Use pre-filtered type list if available and a specific type is selected
                local sourceItems;
                if iconPickerItemType ~= 0 and itemIconLoadState.itemsByType[iconPickerItemType] then
                    sourceItems = itemIconLoadState.itemsByType[iconPickerItemType];
                else
                    sourceItems = itemIconLoadState.items;
                end

                -- Only filter by text search (type already filtered by source list)
                if sourceItems and #sourceItems > 0 then
                    if filter == '' then
                        -- No text filter - use source directly
                        filteredItems = sourceItems;
                    else
                        -- Apply text filter
                        for _, item in ipairs(sourceItems) do
                            local itemName = item.name or '';
                            if itemName:lower():find(filter, 1, true) then
                                table.insert(filteredItems, item);
                            end
                        end
                    end
                end

                -- Only cache if loading is complete and we have results (or filter should return empty)
                if not itemIconLoadState.loading and (#filteredItems > 0 or filter ~= '') then
                    filteredItemsCache = filteredItems;
                end
            end
        elseif iconPickerTab == 3 then
            -- Custom icons - use pre-filtered category list
            filteredItems = GetCustomIconsFiltered(customIconCategory, filter);
        end

        local totalItems = #filteredItems;
        local totalPages = math.max(1, math.ceil(totalItems / ICONS_PER_PAGE));

        -- Show filtered count for spells and custom (items count shown near page navigation only)
        if iconPickerTab == 1 then
            local allSpells = GetAllSpells();
            local countText = string.format('%d of %d spells', totalItems, #allSpells);
            if iconPickerSpellType ~= 'All' then
                countText = countText .. ' (' .. (SPELL_TYPE_LABELS[iconPickerSpellType] or iconPickerSpellType) .. ')';
            end
            imgui.TextColored(COLORS.textMuted, countText);
        elseif iconPickerTab == 3 then
            local allCustom = LoadCustomIcons();
            local countText = string.format('%d of %d custom icons', totalItems, #allCustom);
            if customIconCategory ~= 'all' then
                countText = countText .. ' (' .. (CUSTOM_ICON_LABELS[customIconCategory] or customIconCategory) .. ')';
            end
            imgui.TextColored(COLORS.textMuted, countText);
            
            -- Delete folder button (only for specific categories, not 'all')
            if customIconCategory ~= 'all' then
                imgui.SameLine(imgui.GetWindowWidth() - 145);
                imgui.PushStyleColor(ImGuiCol_Button, COLORS.dangerDim);
                imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.danger);
                imgui.PushStyleColor(ImGuiCol_Text, COLORS.text);
                if imgui.Button('Delete##deleteFolder', {55, 18}) then
                    deleteFolderTarget = customIconCategory;
                    imgui.OpenPopup('Delete Folder##deleteFolderPopup');
                end
                imgui.PopStyleColor(3);
            end
            
            -- Refresh button on the right
            imgui.SameLine(imgui.GetWindowWidth() - 80);
            imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgDark);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.bgLight);
            imgui.PushStyleColor(ImGuiCol_Text, COLORS.goldDim);
            if imgui.Button('Refresh##refreshCustom', {60, 18}) then
                -- Clear all caches to force rescan
                customIconsCache = nil;
                customIconsByCategoryCache = {};
                customCategoryIconCache = {};
                customIconsCacheKey = nil;
                -- Also clear the action module's custom icon cache
                actions.ClearCustomIconCache();
            end
            imgui.PopStyleColor(3);
            
            -- Delete folder confirmation popup
            imgui.PushStyleColor(ImGuiCol_PopupBg, COLORS.bgDark);
            imgui.PushStyleColor(ImGuiCol_Border, COLORS.danger);
            imgui.PushStyleColor(ImGuiCol_TitleBg, COLORS.dangerDim);
            imgui.PushStyleColor(ImGuiCol_TitleBgActive, COLORS.dangerDim);
            imgui.PushStyleColor(ImGuiCol_Text, COLORS.text);
            imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgMedium);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.bgLight);
            
            if imgui.BeginPopupModal('Delete Folder##deleteFolderPopup', nil, ImGuiWindowFlags_AlwaysAutoResize) then
                local categoryLabel = CUSTOM_ICON_LABELS[deleteFolderTarget] or deleteFolderTarget or '';
                local iconCount = customIconsByCategoryCache[deleteFolderTarget] and #customIconsByCategoryCache[deleteFolderTarget] or 0;
                
                imgui.TextColored(COLORS.danger, 'Delete folder "' .. categoryLabel .. '"?');
                imgui.Spacing();
                
                if iconCount > 0 then
                    imgui.TextColored(COLORS.text, 'This will permanently delete ' .. iconCount .. ' icon(s).');
                else
                    imgui.TextColored(COLORS.textMuted, 'This folder is empty.');
                end
                imgui.TextColored(COLORS.textMuted, 'This action cannot be undone.');
                
                imgui.Spacing();
                imgui.Spacing();
                
                -- Delete button
                imgui.PushStyleColor(ImGuiCol_Button, COLORS.danger);
                imgui.PushStyleColor(ImGuiCol_ButtonHovered, {1.0, 0.4, 0.4, 1.0});
                if imgui.Button('Delete', {100, 24}) then
                    DeleteCustomFolder(deleteFolderTarget);
                    deleteFolderTarget = nil;
                    imgui.CloseCurrentPopup();
                end
                imgui.PopStyleColor(2);
                
                imgui.SameLine();
                
                -- Cancel button
                if imgui.Button('Cancel', {100, 24}) then
                    deleteFolderTarget = nil;
                    imgui.CloseCurrentPopup();
                end
                
                imgui.EndPopup();
            end
            
            imgui.PopStyleColor(7);
        end

        -- Clamp current page
        if currentPage > totalPages then
            currentPage = totalPages;
            iconPickerPage[iconPickerTab] = currentPage;
        end

        -- Page navigation UI
        if totalPages > 1 then
            imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 1);
            imgui.PushStyleColor(ImGuiCol_Border, COLORS.border);

            -- Previous button
            local canGoPrev = currentPage > 1;
            if not canGoPrev then
                imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgDark);
                imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.bgDark);
                imgui.PushStyleColor(ImGuiCol_Text, COLORS.textMuted);
            end
            if imgui.Button('<##prevPage', {30, 22}) and canGoPrev then
                iconPickerPage[iconPickerTab] = currentPage - 1;
            end
            if not canGoPrev then
                imgui.PopStyleColor(3);
            end

            imgui.SameLine();

            -- Page info
            imgui.TextColored(COLORS.text, string.format('Page %d / %d', currentPage, totalPages));

            imgui.SameLine();

            -- Next button
            local canGoNext = currentPage < totalPages;
            if not canGoNext then
                imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgDark);
                imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.bgDark);
                imgui.PushStyleColor(ImGuiCol_Text, COLORS.textMuted);
            end
            if imgui.Button('>##nextPage', {30, 22}) and canGoNext then
                iconPickerPage[iconPickerTab] = currentPage + 1;
            end
            if not canGoNext then
                imgui.PopStyleColor(3);
            end

            imgui.SameLine();
            imgui.TextColored(COLORS.textMuted, string.format('(%d total)', totalItems));

            imgui.PopStyleColor();
            imgui.PopStyleVar();

            imgui.Spacing();
        end

        imgui.Separator();
        imgui.Spacing();

        -- Calculate page range
        local startIdx = (currentPage - 1) * ICONS_PER_PAGE + 1;
        local endIdx = math.min(currentPage * ICONS_PER_PAGE, totalItems);

        -- Icon grid with scrollbar - use child window with border for scrolling
        local childFlags = ImGuiWindowFlags_AlwaysVerticalScrollbar;
        imgui.PushStyleColor(ImGuiCol_ChildBg, COLORS.bgDark);
        imgui.PushStyleColor(ImGuiCol_Border, COLORS.border);
        imgui.BeginChild('IconGrid', {0, 0}, true, childFlags);

        local displayedCount = 0;

        if iconPickerTab == 1 then
            -- Spell icons - render current page from filtered list
            if totalItems == 0 then
                imgui.TextColored(COLORS.textMuted, 'No matching spells found');
            else
                for i = startIdx, endIdx do
                    local spell = filteredItems[i];
                    if spell then
                        local icon = nil;

                        -- For Trusts, Summons, and Blue Magic, try to get custom icons first
                        if spell.type == 'Trust' or spell.type == 'SummonerPact' or spell.type == 'BlueMagic' then
                            icon = actions.GetBindIcon({ actionType = 'ma', action = spell.name });
                        end

                        -- Fall back to spell icon from game resources
                        if not icon or not icon.image then
                            icon = textures:Get('spells' .. string.format('%05d', spell.id));
                        end

                        if icon and icon.image then
                            -- Handle grid layout
                            local col = displayedCount % ICON_GRID_COLUMNS;
                            if col > 0 then
                                imgui.SameLine(0, ICON_GRID_GAP);
                            end

                            -- Show spell type in tooltip for trusts
                            local tooltipText = spell.name;
                            if spell.type and spell.type ~= 'Unknown' then
                                tooltipText = spell.name .. ' (' .. (SPELL_TYPE_LABELS[spell.type] or spell.type) .. ')';
                            end

                            local isSelected = editingMacro.customIconType == 'spell' and editingMacro.customIconId == spell.id;
                            if DrawIconButton('##spell' .. spell.id, icon, ICON_GRID_SIZE, isSelected, tooltipText) then
                                editingMacro.customIconType = 'spell';
                                editingMacro.customIconId = spell.id;
                                iconPickerOpen = false;
                            end

                            displayedCount = displayedCount + 1;
                        end
                    end
                end
            end

        elseif iconPickerTab == 2 then
            -- Item icons - render current page from filtered list with progressive loading
            if itemIconLoadState.loading and #itemIconLoadState.items == 0 then
                imgui.TextColored(COLORS.textMuted, 'Loading item database...');
            elseif totalItems == 0 then
                imgui.TextColored(COLORS.textMuted, 'No matching items found');
            else
                -- Check if page/tab/filter changed - reset icon cache
                local loadCacheKey = cacheKey .. ':' .. tostring(currentPage);
                if iconLoadState.currentCacheKey ~= loadCacheKey then
                    iconLoadState.currentPage = currentPage;
                    iconLoadState.currentTab = iconPickerTab;
                    iconLoadState.currentCacheKey = loadCacheKey;
                    iconLoadState.loadedCount = 0;
                    iconLoadState.pageIconCache = {};
                end

                local pageItemCount = endIdx - startIdx + 1;

                -- Progressive loading: load only a few icons per frame to prevent lag
                -- Frame skip allows even more breathing room for the game
                iconLoadState.frameCounter = iconLoadState.frameCounter + 1;
                local shouldLoadThisFrame = (iconLoadState.frameCounter > iconLoadState.frameSkip);

                if shouldLoadThisFrame and iconLoadState.loadedCount < pageItemCount then
                    iconLoadState.frameCounter = 0;  -- Reset frame counter

                    local iconsToLoad = math.min(iconLoadState.iconsPerFrame, pageItemCount - iconLoadState.loadedCount);

                    for _ = 1, iconsToLoad do
                        local cacheIdx = iconLoadState.loadedCount + 1;
                        local itemIdx = startIdx + iconLoadState.loadedCount;
                        local item = filteredItems[itemIdx];

                        if item then
                            local icon = actions.GetBindIcon({ actionType = 'item', itemId = item.id });
                            iconLoadState.pageIconCache[cacheIdx] = icon;
                        end

                        iconLoadState.loadedCount = iconLoadState.loadedCount + 1;
                    end
                end

                -- Show loading progress if still loading
                local isStillLoading = iconLoadState.loadedCount < pageItemCount;
                if isStillLoading then
                    local pct = math.floor((iconLoadState.loadedCount / pageItemCount) * 100);
                    imgui.TextColored(COLORS.gold, string.format('Loading icons... %d%%', pct));
                    imgui.Spacing();
                end

                -- Render loaded icons
                for cacheIdx = 1, iconLoadState.loadedCount do
                    local itemIdx = startIdx + cacheIdx - 1;
                    local item = filteredItems[itemIdx];
                    local icon = iconLoadState.pageIconCache[cacheIdx];

                    if item and icon and icon.image then
                        -- Handle grid layout
                        local col = displayedCount % ICON_GRID_COLUMNS;
                        if col > 0 then
                            imgui.SameLine(0, ICON_GRID_GAP);
                        end

                        -- Show item type in tooltip
                        local tooltipText = item.name;
                        local typeLabel = ITEM_TYPE_LABELS[item.itemType];
                        if typeLabel and typeLabel ~= 'All' then
                            tooltipText = item.name .. ' (' .. typeLabel .. ')';
                        end

                        local isSelected = editingMacro.customIconType == 'item' and editingMacro.customIconId == item.id;
                        if DrawIconButton('##item' .. item.id, icon, ICON_GRID_SIZE, isSelected, tooltipText) then
                            editingMacro.customIconType = 'item';
                            editingMacro.customIconId = item.id;
                            iconPickerOpen = false;
                        end

                        displayedCount = displayedCount + 1;
                    end
                end
            end
        
        elseif iconPickerTab == 3 then
            -- Custom icons - render from custom directory
            if totalItems == 0 then
                if customIconCategory ~= 'all' then
                    -- Empty category folder
                    local categoryLabel = CUSTOM_ICON_LABELS[customIconCategory] or customIconCategory;
                    imgui.TextColored(COLORS.textMuted, 'No icons in "' .. categoryLabel .. '"');
                    imgui.Spacing();
                    imgui.TextColored(COLORS.textMuted, 'Add PNG images to this folder:');
                    imgui.Spacing();
                    
                    -- Open Folder button
                    imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgLight);
                    imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.bgLighter);
                    imgui.PushStyleColor(ImGuiCol_Text, COLORS.gold);
                    if imgui.Button('Open Folder##openCustomFolder', {120, 26}) then
                        OpenCustomFolder(customIconCategory);
                    end
                    imgui.PopStyleColor(3);
                else
                    -- No custom icons at all
                    imgui.TextColored(COLORS.textMuted, 'No custom icons found');
                    imgui.Spacing();
                    imgui.TextColored(COLORS.textMuted, 'Add PNG images to:');
                    imgui.TextColored(COLORS.goldDim, 'addons/XIUI/assets/hotbar/custom/');
                    imgui.Spacing();
                    imgui.Spacing();
                    
                    -- Open Folder button
                    imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgLight);
                    imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.bgLighter);
                    imgui.PushStyleColor(ImGuiCol_Text, COLORS.gold);
                    if imgui.Button('Open Folder##openCustomFolder', {120, 26}) then
                        OpenCustomFolder('all');
                    end
                    imgui.PopStyleColor(3);
                end
            else
                for i = startIdx, endIdx do
                    local customIcon = filteredItems[i];
                    if customIcon then
                        -- Load icon texture
                        local icon = LoadCustomIconTexture(customIcon.path);
                        
                        if icon and icon.image then
                            -- Handle grid layout
                            local col = displayedCount % ICON_GRID_COLUMNS;
                            if col > 0 then
                                imgui.SameLine(0, ICON_GRID_GAP);
                            end
                            
                            -- Show category in tooltip
                            local tooltipText = customIcon.name;
                            if customIcon.category ~= 'root' then
                                local categoryLabel = CUSTOM_ICON_LABELS[customIcon.category] or customIcon.category;
                                tooltipText = customIcon.name .. ' (' .. categoryLabel .. ')';
                            end
                            
                            local isSelected = editingMacro.customIconType == 'custom' and editingMacro.customIconPath == customIcon.path;
                            if DrawIconButton('##custom' .. i, icon, ICON_GRID_SIZE, isSelected, tooltipText) then
                                editingMacro.customIconType = 'custom';
                                editingMacro.customIconPath = customIcon.path;
                                editingMacro.customIconId = nil;  -- Clear spell/item ID
                                iconPickerOpen = false;
                            end
                            
                            displayedCount = displayedCount + 1;
                        end
                    end
                end
            end
        end

        imgui.EndChild();
        imgui.PopStyleColor(2);  -- ChildBg, Border
    end

    imgui.End();
    PopWindowStyle();

    if not isOpen[1] then
        iconPickerOpen = false;
        iconPickerFilter[1] = '';
        iconPickerPage = { 1, 1, 1 };  -- Reset pages
        iconPickerLastFilter = { '', '', '' };
        iconPickerSpellType = 'All';  -- Reset spell type filter
        iconPickerItemType = 0;  -- Reset item type filter (0 = All)
        customIconCategory = 'all';  -- Reset custom category filter
        -- Clear filter caches when picker closes
        filteredSpellsCache = nil;
        filteredSpellsCacheKey = nil;
        filteredItemsCache = nil;
        filteredItemsCacheKey = nil;
        customIconsCacheKey = nil;
        -- Reset progressive icon loading
        ResetIconLoading();
    end
end

function M.DrawMacroEditor()
    if not editingMacro then
        return;
    end

    -- Initialize editor fields from editing macro
    editorFields.actionType[1] = FindIndex(ACTION_TYPES, editingMacro.actionType or 'ma');
    editorFields.action[1] = editingMacro.action or '';
    editorFields.target[1] = FindIndex(TARGET_OPTIONS, editingMacro.target or 't');
    editorFields.displayName[1] = editingMacro.displayName or '';
    editorFields.equipSlot[1] = FindIndex(EQUIP_SLOTS, editingMacro.equipSlot or 'main');
    editorFields.macroText[1] = editingMacro.macroText or '';

    local title = isCreatingNew and 'Create Macro###MacroEditor' or 'Edit Macro###MacroEditor';
    local isOpen = { true };

    imgui.SetNextWindowSize({420, 420}, ImGuiCond_FirstUseEver);

    -- Apply XIUI styling
    PushWindowStyle();

    if imgui.Begin(title, isOpen, ImGuiWindowFlags_NoCollapse) then
        -- Get window position for icon preview placement
        local windowPos = {imgui.GetWindowPos()};
        local windowWidth = imgui.GetWindowWidth();
        local iconPreviewSize = 64;
        local iconPreviewX = windowPos[1] + windowWidth - iconPreviewSize - 20;
        local iconPreviewY = windowPos[2] + 35;

        -- Draw icon preview on right side
        DrawIconPreview(editingMacro, iconPreviewX, iconPreviewY, iconPreviewSize);

        -- Change Icon button below preview
        imgui.SetCursorScreenPos({iconPreviewX - 10, iconPreviewY + iconPreviewSize + 8});
        imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 1);
        imgui.PushStyleColor(ImGuiCol_Border, COLORS.gold);
        if imgui.Button('Change', {iconPreviewSize + 20, 22}) then
            iconPickerOpen = true;
            iconPickerFilter[1] = '';
        end
        imgui.PopStyleColor();
        imgui.PopStyleVar();

        -- Reset cursor for main content
        imgui.SetCursorScreenPos({windowPos[1] + 10, windowPos[2] + 35});

        -- Action Type dropdown with label
        imgui.TextColored(COLORS.goldDim, 'Action Type');
        PushComboStyle();
        imgui.SetNextItemWidth(240);
        local currentType = ACTION_TYPES[editorFields.actionType[1]];
        if imgui.BeginCombo('##actionType', ACTION_TYPE_LABELS[currentType] or 'Select...') then
            for i, actionType in ipairs(ACTION_TYPES) do
                local isSelected = editorFields.actionType[1] == i;
                if isSelected then
                    imgui.PushStyleColor(ImGuiCol_Text, COLORS.gold);
                end
                if imgui.Selectable(ACTION_TYPE_LABELS[actionType], isSelected) then
                    editorFields.actionType[1] = i;
                    editingMacro.actionType = actionType;
                    -- Clear action when type changes
                    editingMacro.action = '';
                    editorFields.action[1] = '';
                    searchFilter[1] = '';
                end
                if isSelected then
                    imgui.PopStyleColor();
                end
            end
            imgui.EndCombo();
        end
        PopComboStyle();

        imgui.Spacing();
        imgui.Spacing();

        -- Dynamic fields based on action type
        currentType = ACTION_TYPES[editorFields.actionType[1]];

        if currentType == 'ma' then
            -- Spell: Show searchable dropdown
            imgui.TextColored(COLORS.goldDim, 'Spell');
            local spells = GetCachedSpells();
            if spells and #spells > 0 then
                DrawSearchableCombo('##spellCombo', spells, editingMacro.action or '', function(spell)
                    editingMacro.action = spell.name;
                    editorFields.action[1] = spell.name;
                    if (editingMacro.displayName or '') == '' then
                        editingMacro.displayName = spell.name;
                        editorFields.displayName[1] = spell.name;
                    end
                end);
            else
                imgui.TextColored(COLORS.textMuted, 'No spells available for this job');
            end

            -- Target dropdown
            imgui.Spacing();
            imgui.TextColored(COLORS.goldDim, 'Target');
            PushComboStyle();
            imgui.SetNextItemWidth(240);
            if imgui.BeginCombo('##targetType', TARGET_LABELS[TARGET_OPTIONS[editorFields.target[1]]] or 'Select...') then
                for i, target in ipairs(TARGET_OPTIONS) do
                    local isSelected = editorFields.target[1] == i;
                    if isSelected then imgui.PushStyleColor(ImGuiCol_Text, COLORS.gold); end
                    if imgui.Selectable(TARGET_LABELS[target], isSelected) then
                        editorFields.target[1] = i;
                        editingMacro.target = target;
                    end
                    if isSelected then imgui.PopStyleColor(); end
                end
                imgui.EndCombo();
            end
            PopComboStyle();

        elseif currentType == 'ja' then
            -- Ability: Show searchable dropdown
            imgui.TextColored(COLORS.goldDim, 'Ability');
            local abilities = GetCachedAbilities();
            if abilities and #abilities > 0 then
                DrawSearchableCombo('##abilityCombo', abilities, editingMacro.action or '', function(ability)
                    editingMacro.action = ability.name;
                    editorFields.action[1] = ability.name;
                    if (editingMacro.displayName or '') == '' then
                        editingMacro.displayName = ability.name;
                        editorFields.displayName[1] = ability.name;
                    end
                end);
            else
                imgui.TextColored(COLORS.textMuted, 'No abilities available');
            end

            -- Target dropdown
            imgui.Spacing();
            imgui.TextColored(COLORS.goldDim, 'Target');
            PushComboStyle();
            imgui.SetNextItemWidth(240);
            if imgui.BeginCombo('##targetType', TARGET_LABELS[TARGET_OPTIONS[editorFields.target[1]]] or 'Select...') then
                for i, target in ipairs(TARGET_OPTIONS) do
                    local isSelected = editorFields.target[1] == i;
                    if isSelected then imgui.PushStyleColor(ImGuiCol_Text, COLORS.gold); end
                    if imgui.Selectable(TARGET_LABELS[target], isSelected) then
                        editorFields.target[1] = i;
                        editingMacro.target = target;
                    end
                    if isSelected then imgui.PopStyleColor(); end
                end
                imgui.EndCombo();
            end
            PopComboStyle();

        elseif currentType == 'ws' then
            -- Weaponskill: Show searchable dropdown
            imgui.TextColored(COLORS.goldDim, 'Weaponskill');
            local weaponskills = GetCachedWeaponskills();
            if weaponskills and #weaponskills > 0 then
                DrawSearchableCombo('##wsCombo', weaponskills, editingMacro.action or '', function(ws)
                    editingMacro.action = ws.name;
                    editorFields.action[1] = ws.name;
                    if (editingMacro.displayName or '') == '' then
                        editingMacro.displayName = ws.name;
                        editorFields.displayName[1] = ws.name;
                    end
                end);
            else
                imgui.TextColored(COLORS.textMuted, 'No weaponskills available');
            end

            -- Target dropdown (default to <t>)
            imgui.Spacing();
            imgui.TextColored(COLORS.goldDim, 'Target');
            PushComboStyle();
            imgui.SetNextItemWidth(240);
            if imgui.BeginCombo('##targetType', TARGET_LABELS[TARGET_OPTIONS[editorFields.target[1]]] or 'Select...') then
                for i, target in ipairs(TARGET_OPTIONS) do
                    local isSelected = editorFields.target[1] == i;
                    if isSelected then imgui.PushStyleColor(ImGuiCol_Text, COLORS.gold); end
                    if imgui.Selectable(TARGET_LABELS[target], isSelected) then
                        editorFields.target[1] = i;
                        editingMacro.target = target;
                    end
                    if isSelected then imgui.PopStyleColor(); end
                end
                imgui.EndCombo();
            end
            PopComboStyle();

        elseif currentType == 'item' then
            -- Item: Searchable dropdown or manual input
            imgui.TextColored(COLORS.goldDim, 'Item');
            local items = GetCachedItems();
            if items and #items > 0 then
                DrawSearchableCombo('##itemCombo', items, editingMacro.action or '', function(item)
                    editingMacro.action = item.name;
                    editingMacro.itemId = item.id;  -- Store item ID for fast icon lookup
                    editorFields.action[1] = item.name;
                    editingMacro.displayName = item.name;
                    editorFields.displayName[1] = item.name;
                end, true);  -- Show icons
                imgui.SameLine();
                imgui.TextColored(COLORS.textMuted, '(' .. #items .. ')');
            else
                imgui.TextColored(COLORS.textMuted, 'No items found in storage');
            end

            -- Manual input fallback
            imgui.Spacing();
            imgui.TextColored(COLORS.goldDim, 'Or type item name:');
            imgui.SetNextItemWidth(220);
            if imgui.InputText('##itemName', editorFields.action, INPUT_BUFFER_SIZE) then
                editingMacro.action = editorFields.action[1];
            end

            -- Target dropdown
            imgui.Spacing();
            imgui.TextColored(COLORS.goldDim, 'Target');
            PushComboStyle();
            imgui.SetNextItemWidth(240);
            if imgui.BeginCombo('##targetType', TARGET_LABELS[TARGET_OPTIONS[editorFields.target[1]]] or 'Select...') then
                for i, target in ipairs(TARGET_OPTIONS) do
                    local isSelected = editorFields.target[1] == i;
                    if isSelected then imgui.PushStyleColor(ImGuiCol_Text, COLORS.gold); end
                    if imgui.Selectable(TARGET_LABELS[target], isSelected) then
                        editorFields.target[1] = i;
                        editingMacro.target = target;
                    end
                    if isSelected then imgui.PopStyleColor(); end
                end
                imgui.EndCombo();
            end
            PopComboStyle();

        elseif currentType == 'equip' then
            -- Equipment slot dropdown
            imgui.TextColored(COLORS.goldDim, 'Equipment Slot');
            PushComboStyle();
            imgui.SetNextItemWidth(240);
            if imgui.BeginCombo('##equipSlot', EQUIP_SLOT_LABELS[EQUIP_SLOTS[editorFields.equipSlot[1]]] or 'Select...') then
                for i, slot in ipairs(EQUIP_SLOTS) do
                    local isSelected = editorFields.equipSlot[1] == i;
                    if isSelected then imgui.PushStyleColor(ImGuiCol_Text, COLORS.gold); end
                    if imgui.Selectable(EQUIP_SLOT_LABELS[slot], isSelected) then
                        editorFields.equipSlot[1] = i;
                        editingMacro.equipSlot = slot;
                        -- Clear item selection when slot changes (old item may not fit new slot)
                        editingMacro.action = '';
                        editingMacro.itemId = nil;
                        editingMacro.displayName = '';
                        editorFields.action[1] = '';
                        editorFields.displayName[1] = '';
                    end
                    if isSelected then imgui.PopStyleColor(); end
                end
                imgui.EndCombo();
            end
            PopComboStyle();

            -- Item: Searchable dropdown or manual input (filtered by selected equipment slot)
            imgui.Spacing();
            local selectedSlot = EQUIP_SLOTS[editorFields.equipSlot[1]];
            imgui.TextColored(COLORS.goldDim, 'Item (' .. EQUIP_SLOT_LABELS[selectedSlot] .. ')');
            local equipItems = GetCachedItems();
            if equipItems and #equipItems > 0 then
                DrawSearchableCombo('##equipItemCombo', equipItems, editingMacro.action or '', function(item)
                    editingMacro.action = item.name;
                    editingMacro.itemId = item.id;  -- Store item ID for fast icon lookup
                    editorFields.action[1] = item.name;
                    editingMacro.displayName = item.name;
                    editorFields.displayName[1] = item.name;
                end, true, selectedSlot);  -- Show icons, filter by selected slot
                imgui.SameLine();
                imgui.TextColored(COLORS.textMuted, '(' .. #equipItems .. ')');
            else
                imgui.TextColored(COLORS.textMuted, 'No items found in storage');
            end

            -- Manual input fallback
            imgui.Spacing();
            imgui.TextColored(COLORS.goldDim, 'Or type item name:');
            imgui.SetNextItemWidth(220);
            if imgui.InputText('##equipItemName', editorFields.action, INPUT_BUFFER_SIZE) then
                editingMacro.action = editorFields.action[1];
            end

        elseif currentType == 'macro' then
            -- Raw macro command (8 lines like native FFXI macro editor)
            imgui.TextColored(COLORS.goldDim, 'Macro Commands (8 lines)');

            -- Style the multiline input
            imgui.PushStyleColor(ImGuiCol_FrameBg, COLORS.bgMedium);
            imgui.PushStyleColor(ImGuiCol_FrameBgHovered, COLORS.bgLight);
            imgui.PushStyleColor(ImGuiCol_FrameBgActive, COLORS.bgLight);

            -- 8 rows * ~16px line height + padding
            local lineHeight = imgui.GetTextLineHeight();
            local inputHeight = (lineHeight * 8) + 8;

            if imgui.InputTextMultiline('##macroText', editorFields.macroText, MACRO_BUFFER_SIZE, {280, inputHeight}) then
                editingMacro.macroText = editorFields.macroText[1];
                editingMacro.action = editorFields.macroText[1];
            end

            imgui.PopStyleColor(3);
            imgui.ShowHelp('Enter commands, one per line (e.g., /ma "Cure" <stpc>)');

        elseif currentType == 'pet' then
            -- For SMN, show avatar filter dropdown
            -- Use the VIEWED palette's job, not necessarily the player's current job
            local viewedJobId = selectedPaletteType;
            if type(viewedJobId) ~= 'number' then
                viewedJobId = playerdata.GetCacheJobId() or 0;
            end
            local avatarList = petregistry.GetAvatarList();

            if viewedJobId == petregistry.JOB_SMN then
                imgui.TextColored(COLORS.goldDim, 'Avatar Filter');
                PushComboStyle();
                imgui.SetNextItemWidth(240);
                local filterLabel = petAvatarFilter == 1 and 'All Avatars' or avatarList[petAvatarFilter - 1];
                if imgui.BeginCombo('##avatarFilter', filterLabel) then
                    -- "All" option
                    local isAllSelected = petAvatarFilter == 1;
                    if isAllSelected then imgui.PushStyleColor(ImGuiCol_Text, COLORS.gold); end
                    if imgui.Selectable('All Avatars', isAllSelected) then
                        petAvatarFilter = 1;
                        cachedPetCommands = nil;  -- Clear cache to rebuild
                    end
                    if isAllSelected then imgui.PopStyleColor(); end

                    imgui.Separator();

                    -- Individual avatars
                    for i, avatar in ipairs(avatarList) do
                        local isSelected = petAvatarFilter == i + 1;
                        if isSelected then imgui.PushStyleColor(ImGuiCol_Text, COLORS.gold); end
                        if imgui.Selectable(avatar, isSelected) then
                            petAvatarFilter = i + 1;
                            cachedPetCommands = nil;  -- Clear cache to rebuild
                        end
                        if isSelected then imgui.PopStyleColor(); end
                    end
                    imgui.EndCombo();
                end
                PopComboStyle();
                imgui.Spacing();
            end

            -- Build pet commands cache if needed
            if not cachedPetCommands then
                local avatarName = nil;
                local activePetName = nil;
                if viewedJobId == petregistry.JOB_SMN then
                    -- Prefer the macro palette's avatar selection, then the filter
                    if selectedAvatarPalette then
                        avatarName = selectedAvatarPalette;
                    elseif petAvatarFilter > 1 then
                        avatarName = avatarList[petAvatarFilter - 1];
                    end
                elseif viewedJobId == petregistry.JOB_BST then
                    -- Get the active pet's entity name for BST ready moves
                    activePetName = petpalette.GetCurrentPetEntityName();
                end
                cachedPetCommands = GetPetCommandsForJob(viewedJobId, avatarName, activePetName);
            end

            -- Pet command dropdown
            imgui.TextColored(COLORS.goldDim, 'Pet Command');
            if cachedPetCommands and #cachedPetCommands > 0 then
                DrawSearchableCombo('##petCommandCombo', cachedPetCommands, editingMacro.action or '', function(cmd)
                    editingMacro.action = cmd.name;
                    editorFields.action[1] = cmd.name;
                    if (editingMacro.displayName or '') == '' then
                        editingMacro.displayName = cmd.name;
                        editorFields.displayName[1] = cmd.name;
                    end
                end);
            else
                imgui.TextColored(COLORS.textMuted, 'No pet commands available for this job');
            end

            -- Manual input fallback
            imgui.Spacing();
            imgui.TextColored(COLORS.goldDim, 'Or type command:');
            imgui.SetNextItemWidth(220);
            if imgui.InputText('##petCommandManual', editorFields.action, INPUT_BUFFER_SIZE) then
                editingMacro.action = editorFields.action[1];
            end

            -- Target dropdown
            imgui.Spacing();
            imgui.TextColored(COLORS.goldDim, 'Target');
            PushComboStyle();
            imgui.SetNextItemWidth(240);
            if imgui.BeginCombo('##targetType', TARGET_LABELS[TARGET_OPTIONS[editorFields.target[1]]] or 'Select...') then
                for i, target in ipairs(TARGET_OPTIONS) do
                    local isSelected = editorFields.target[1] == i;
                    if isSelected then imgui.PushStyleColor(ImGuiCol_Text, COLORS.gold); end
                    if imgui.Selectable(TARGET_LABELS[target], isSelected) then
                        editorFields.target[1] = i;
                        editingMacro.target = target;
                    end
                    if isSelected then imgui.PopStyleColor(); end
                end
                imgui.EndCombo();
            end
            PopComboStyle();
        end

        -- Slot Label input (for all types)
        imgui.Spacing();
        imgui.Spacing();
        imgui.TextColored(COLORS.goldDim, 'Slot Label');
        imgui.SetNextItemWidth(240);
        if imgui.InputText('##displayName', editorFields.displayName, 32) then
            editingMacro.displayName = editorFields.displayName[1];
        end
        if currentType ~= 'macro' then
            imgui.ShowHelp('Short label shown on the slot (e.g., "Cure3"). Leave empty to use action name.');
        else
            imgui.ShowHelp('Label shown on the slot for this macro.');
        end

        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();

        -- Save button with success styling
        imgui.PushStyleColor(ImGuiCol_Button, COLORS.success);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0.5, 0.8, 0.5, 1.0});
        imgui.PushStyleColor(ImGuiCol_ButtonActive, {0.6, 0.9, 0.6, 1.0});
        imgui.PushStyleColor(ImGuiCol_Text, {0.1, 0.1, 0.1, 1.0});

        if imgui.Button('Save', {90, 28}) then
            -- Validate before saving
            local canSave = false;

            if currentType == 'macro' then
                canSave = (editingMacro.macroText or '') ~= '';
                if canSave and (editingMacro.displayName or '') == '' then
                    editingMacro.displayName = 'Macro';
                end
                -- Clear target for macro type (targets are embedded in macro text)
                editingMacro.target = nil;
            else
                canSave = (editingMacro.action or '') ~= '';
                if canSave and (editingMacro.displayName or '') == '' then
                    editingMacro.displayName = editingMacro.action;
                end
            end

            if canSave then
                if isCreatingNew then
                    M.AddMacro(editingMacro);
                    -- Navigate to last page to show the new macro
                    local db = M.GetMacroDatabase();
                    currentPalettePage = math.max(1, math.ceil(#db / PALETTE_MACROS_PER_PAGE));
                else
                    M.UpdateMacro(editingMacro.id, editingMacro);
                end
                editingMacro = nil;
                isCreatingNew = false;
                searchFilter[1] = '';
                iconPickerOpen = false;
                iconPickerFilter[1] = '';
            end
        end

        imgui.PopStyleColor(4);

        imgui.SameLine();

        -- Cancel button
        if imgui.Button('Cancel', {90, 28}) then
            editingMacro = nil;
            isCreatingNew = false;
            searchFilter[1] = '';
            iconPickerOpen = false;
            iconPickerFilter[1] = '';
        end
    end

    imgui.End();
    PopWindowStyle();

    if not isOpen[1] then
        editingMacro = nil;
        isCreatingNew = false;
        searchFilter[1] = '';
        iconPickerOpen = false;
        iconPickerFilter[1] = '';
    end

    -- Draw icon picker if open
    DrawIconPicker();
end

-- ============================================
-- Dragdrop Library Accessors (for display.lua)
-- ============================================

-- Get the dragdrop library reference
function M.GetDragDropLib()
    return dragdrop;
end

-- Update drag state (call every frame)
function M.UpdateDrag()
    dragdrop.Update();
end

-- Render drag preview (call at end of frame)
function M.RenderDragPreview()
    dragdrop.Render();
end

return M;
