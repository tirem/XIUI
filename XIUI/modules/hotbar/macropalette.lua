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
};

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

-- Helper to ensure slotActions structure exists for a storage key (with key normalization)
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
local selectedPaletteJob = nil;

-- Cached spell/ability/weaponskill/item lists
local cachedSpells = nil;
local cachedAbilities = nil;
local cachedWeaponskills = nil;
local cachedItems = nil;
local cacheJobId = nil;

-- Search filter for dropdowns
local searchFilter = { '' };

-- Icon picker state
local iconPickerOpen = false;
local iconPickerFilter = { '' };
local iconPickerTab = 1;  -- 1 = Spells, 2 = Items
local iconPickerPage = { 1, 1 };  -- Current page for each tab [spells, items]
local iconPickerLastFilter = { '', '' };  -- Track filter changes to reset page

-- Icon picker grid constants
local ICON_GRID_COLUMNS = 12;
local ICON_GRID_SIZE = 36;
local ICON_GRID_GAP = 4;
local ICONS_PER_PAGE = 500;

-- Cached spell list for icon picker (all spells, not just player-known)
local allSpellsCache = nil;

-- Item icon loading state (for lazy loading)
local itemIconLoadState = {
    loaded = false,
    loading = false,
    items = {},
    seenNames = {},  -- Hash table for O(1) duplicate checking
    currentId = 0,
    maxId = 65535,
    batchSize = 500,  -- Load 500 items per frame (fast since we're just reading names)
};

-- ============================================
-- Spell/Ability/Weaponskill Retrieval
-- ============================================

-- Check if a spell name looks like a garbage/test entry (e.g., AAEV, AAGK)
local function IsGarbageSpellName(name)
    if not name or #name < 2 then return true; end
    -- Check if it's all uppercase letters with no spaces (garbage codes)
    if #name <= 5 and name:match('^[A-Z]+$') then
        return true;
    end
    return false;
end

-- Get player's known spells for current job (excludes trusts and garbage entries)
local function GetPlayerSpells()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then return {}; end

    local jobId = player:GetMainJob();
    local jobLevel = player:GetMainJobLevel();
    local resMgr = AshitaCore:GetResourceManager();

    local spells = {};
    for spellId = 1, 1024 do
        -- Skip trust spells (IDs 896+)
        if spellId >= 896 then
            break;
        end

        if player:HasSpell(spellId) then
            local spell = resMgr:GetSpellById(spellId);
            if spell and spell.Name and spell.Name[1] and spell.Name[1] ~= '' then
                local spellName = spell.Name[1];

                -- Skip garbage/test spell names
                if not IsGarbageSpellName(spellName) then
                    -- LevelRequired array is 0-indexed in C (0=None, 1=WAR, 2=MNK, 3=WHM...)
                    -- but Lua uses 1-indexing, so add 1 to jobId
                    local reqLevel = spell.LevelRequired[jobId + 1] or 0;
                    if reqLevel > 0 and reqLevel <= jobLevel then
                        table.insert(spells, {
                            id = spellId,
                            name = spellName,
                            level = reqLevel,
                        });
                    end
                end
            end
        end
    end

    table.sort(spells, function(a, b)
        if a.level == b.level then
            return a.name < b.name;
        end
        return a.level < b.level;
    end);

    return spells;
end

-- Get player's available job abilities
local function GetPlayerAbilities()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then return {}; end

    local resMgr = AshitaCore:GetResourceManager();
    local abilities = {};

    for abilityId = 1, 1024 do
        if player:HasAbility(abilityId) then
            local ability = resMgr:GetAbilityById(abilityId);
            if ability and ability.Name and ability.Name[1] and ability.Name[1] ~= '' then
                table.insert(abilities, {
                    id = abilityId,
                    name = ability.Name[1],
                });
            end
        end
    end

    table.sort(abilities, function(a, b)
        return a.name < b.name;
    end);

    return abilities;
end

-- Get player's available weaponskills
local function GetPlayerWeaponskills()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then return {}; end

    local resMgr = AshitaCore:GetResourceManager();
    local weaponskills = {};

    for wsId = 1, 255 do
        if player:HasWeaponSkill(wsId) then
            local ability = resMgr:GetAbilityById(wsId + 256);
            if ability and ability.Name and ability.Name[1] and ability.Name[1] ~= '' then
                table.insert(weaponskills, {
                    id = wsId,
                    name = ability.Name[1],
                });
            end
        end
    end

    table.sort(weaponskills, function(a, b)
        return a.name < b.name;
    end);

    return weaponskills;
end

-- Container definitions for item browsing
local CONTAINERS = {
    { id = 0, name = 'Inventory' },
    { id = 5, name = 'Satchel' },
    { id = 6, name = 'Sack' },
    { id = 7, name = 'Case' },
    { id = 1, name = 'Safe' },
    { id = 2, name = 'Storage' },
    { id = 4, name = 'Locker' },
    { id = 8, name = 'Wardrobe' },
    { id = 10, name = 'Wardrobe 2' },
    { id = 11, name = 'Wardrobe 3' },
    { id = 12, name = 'Wardrobe 4' },
    { id = 13, name = 'Wardrobe 5' },
    { id = 14, name = 'Wardrobe 6' },
    { id = 15, name = 'Wardrobe 7' },
    { id = 16, name = 'Wardrobe 8' },
};

-- Get items from all player storage containers
local function GetPlayerItems()
    local memMgr = AshitaCore:GetMemoryManager();
    if not memMgr then return {}; end

    local inventory = memMgr:GetInventory();
    if not inventory then return {}; end

    local resMgr = AshitaCore:GetResourceManager();
    local items = {};
    local seenItems = {};  -- Track unique items by name to avoid duplicates

    for _, container in ipairs(CONTAINERS) do
        local maxSlots = inventory:GetContainerCountMax(container.id);
        if maxSlots and maxSlots > 0 then
            for slotIndex = 1, maxSlots do
                local item = inventory:GetContainerItem(container.id, slotIndex);
                if item and item.Id and item.Id > 0 and item.Id ~= 65535 then
                    local itemRes = resMgr:GetItemById(item.Id);
                    if itemRes and itemRes.Name and itemRes.Name[1] and itemRes.Name[1] ~= '' then
                        local itemName = itemRes.Name[1];
                        -- Only add if we haven't seen this item name yet
                        if not seenItems[itemName] then
                            seenItems[itemName] = true;
                            table.insert(items, {
                                id = item.Id,
                                name = itemName,
                                container = container.name,
                                count = item.Count or 1,
                                slots = itemRes.Slots or 0,  -- Equipment slot bitmask
                            });
                        end
                    end
                end
            end
        end
    end

    table.sort(items, function(a, b)
        return a.name < b.name;
    end);

    return items;
end

-- Refresh cached lists if needed
local function RefreshCachedLists()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then return; end

    local currentJobId = player:GetMainJob();

    if cacheJobId ~= currentJobId or not cachedSpells then
        cachedSpells = GetPlayerSpells();
        cachedAbilities = GetPlayerAbilities();
        cachedWeaponskills = GetPlayerWeaponskills();
        cacheJobId = currentJobId;
    end

    -- Always refresh items (they don't depend on job)
    cachedItems = GetPlayerItems();
end

-- Build cache of ALL spells from horizonspells database (for icon picker)
local function GetAllSpells()
    if allSpellsCache then
        return allSpellsCache;
    end

    local horizonSpells = require('modules.hotbar.database.horizonspells');
    allSpellsCache = {};

    for _, spell in pairs(horizonSpells) do
        if spell.en and spell.en ~= '' and spell.id and not IsGarbageSpellName(spell.en) then
            table.insert(allSpellsCache, {
                id = spell.id,
                name = spell.en,
                icon_id = spell.icon_id,
                type = spell.type or 'Unknown',
            });
        end
    end

    -- Sort by name
    table.sort(allSpellsCache, function(a, b)
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
                table.insert(itemIconLoadState.items, {
                    id = itemId,
                    name = itemName,
                });
            end
        end
    end

    itemIconLoadState.currentId = endId;

    if itemIconLoadState.currentId >= itemIconLoadState.maxId then
        itemIconLoadState.loaded = true;
        itemIconLoadState.loading = false;
        -- Sort items by name after all loaded
        table.sort(itemIconLoadState.items, function(a, b)
            return a.name < b.name;
        end);
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
    itemIconLoadState.seenNames = {};
end

-- Get loading progress percentage
local function GetItemLoadProgress()
    if itemIconLoadState.loaded then
        return 100;
    end
    return math.floor((itemIconLoadState.currentId / itemIconLoadState.maxId) * 100);
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

                -- Highlight selected item with gold
                if isSelected then
                    imgui.PushStyleColor(ImGuiCol_Text, COLORS.gold);
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
                if imgui.Selectable(itemLabel .. '##item' .. (item.id or matchCount), isSelected) then
                    onSelect(item);
                    searchFilter[1] = '';
                    imgui.CloseCurrentPopup();
                end

                if isSelected then
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

-- Get current effective job for the palette (selected job or player's current job)
local function GetEffectivePaletteJob()
    if selectedPaletteJob and selectedPaletteJob > 0 then
        return selectedPaletteJob;
    end
    return data.jobId or 1;
end

-- Sync palette to current player job (call on job change)
function M.SyncToCurrentJob()
    selectedPaletteJob = data.jobId or 1;
    -- Clear spell cache so it rebuilds for new job
    cachedSpells = nil;
    cachedAbilities = nil;
    cachedWeaponskills = nil;
    cacheJobId = nil;
    -- Close editor window if open (spells/abilities are job-specific)
    if editingMacro then
        editingMacro = nil;
        isCreatingNew = false;
        searchFilter[1] = '';
        iconPickerOpen = false;
    end
    -- Clear macro selection (macros are per-job)
    selectedMacroIndex = nil;
    -- If palette is open, immediately refresh the caches
    if paletteOpen then
        RefreshCachedLists();
    end
end

-- Get the macro database for selected/current job
function M.GetMacroDatabase()
    local jobId = GetEffectivePaletteJob();

    if not gConfig.macroDB then
        gConfig.macroDB = {};
    end

    if not gConfig.macroDB[jobId] then
        gConfig.macroDB[jobId] = {};
    end

    return gConfig.macroDB[jobId], jobId;
end

-- Add a new macro to the database
function M.AddMacro(macroData)
    local db, jobId = M.GetMacroDatabase();

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
            return true;
        end
    end

    return false;
end

-- Clear all hotbar/crossbar slots that reference a specific macro ID
local function ClearSlotsReferencingMacro(macroId, jobId)
    local numericJobId = normalizeJobId(jobId);

    -- Clear from all hotbars (1-6)
    for barIndex = 1, 6 do
        local configKey = 'hotbarBar' .. barIndex;
        if gConfig[configKey] and gConfig[configKey].slotActions then
            local barSettings = gConfig[configKey];
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

    -- Clear from crossbar (all combo modes)
    if gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.slotActions then
        local crossbarSettings = gConfig.hotbarCrossbar;
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

-- Delete a macro from the database
function M.DeleteMacro(macroId)
    local db, jobId = M.GetMacroDatabase();

    for i, macro in ipairs(db) do
        if macro.id == macroId then
            table.remove(db, i);
            -- Clear any hotbar/crossbar slots referencing this macro
            ClearSlotsReferencingMacro(macroId, jobId);
            SaveSettingsToDisk();
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

    local jobId = normalizeJobId(data.jobId or 1);
    local configKey = 'hotbarBar' .. targetBarIndex;

    -- Ensure config structure exists (with key normalization)
    if not gConfig[configKey] then
        gConfig[configKey] = {};
    end
    -- Use storage key based on jobSpecific setting
    local storageKey = getStorageKey(gConfig[configKey], jobId);
    local jobSlotActions = ensureSlotActionsStructure(gConfig[configKey], storageKey);

    if payload.type == 'macro' then
        -- Dragging from palette to slot
        local macroData = payload.data;
        if macroData then
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
                macroRef = macroData.id,  -- Store reference to source macro for live updates
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
            };
        else
            -- Target slot is empty - mark as cleared
            targetData = { cleared = true };
        end

        -- Ensure source config structure exists (with key normalization)
        if not gConfig[sourceConfigKey] then
            gConfig[sourceConfigKey] = {};
        end
        -- Use storage key based on source bar's jobSpecific setting
        local sourceStorageKey = getStorageKey(gConfig[sourceConfigKey], jobId);
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
            };
            SaveSettingsToDisk();
        end
    end

    return true;
end

-- Clear a hotbar slot
function M.ClearSlot(barIndex, slotIndex)
    local jobId = normalizeJobId(data.jobId or 1);
    local configKey = 'hotbarBar' .. barIndex;

    -- Ensure config structure exists (with key normalization)
    if not gConfig[configKey] then
        gConfig[configKey] = {};
    end
    -- Use storage key based on jobSpecific setting
    local storageKey = getStorageKey(gConfig[configKey], jobId);
    local jobSlotActions = ensureSlotActionsStructure(gConfig[configKey], storageKey);

    -- Mark slot as cleared
    jobSlotActions[slotIndex] = { cleared = true };
    SaveSettingsToDisk();
end

-- ============================================
-- Palette Window
-- ============================================

function M.OpenPalette()
    paletteOpen = true;
    selectedMacroIndex = nil;
    editingMacro = nil;
    isCreatingNew = false;

    -- Sync to current player job when opening
    selectedPaletteJob = data.jobId or 1;

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

    -- Draw icon if available
    local icon = actions.GetBindIcon(macro);
    if icon and icon.image then
        local drawList = imgui.GetWindowDrawList();
        if drawList then
            local iconSize = size - 8;  -- Slightly smaller than tile
            local iconX = x + 4;
            local iconY = y + 4;
            local iconPtr = tonumber(ffi.cast("uint32_t", icon.image));
            if iconPtr then
                drawList:AddImage(
                    iconPtr,
                    {iconX, iconY},
                    {iconX + iconSize, iconY + iconSize}
                );
            end
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
        if macro.target then
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

    -- Initialize selectedPaletteJob to current job if not set
    if not selectedPaletteJob or selectedPaletteJob == 0 then
        selectedPaletteJob = data.jobId or 1;
    end

    local db, jobId = M.GetMacroDatabase();
    local jobName = jobs[jobId] or 'Unknown';
    local currentPlayerJob = data.jobId or 1;
    local isViewingCurrentJob = (jobId == currentPlayerJob);

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

        -- Job selector row
        imgui.TextColored(COLORS.textDim, 'Job:');
        imgui.SameLine();

        -- Style the combo popup
        PushComboStyle();
        imgui.PushItemWidth(100);

        -- Helper to get macro count for a job
        local function getMacroCount(jid)
            if gConfig.macroDB and gConfig.macroDB[jid] then
                return #gConfig.macroDB[jid];
            end
            return 0;
        end

        -- Build display label with macro count
        local macroCount = getMacroCount(jobId);
        local displayLabel = macroCount > 0 and string.format('%s (%d)', jobName, macroCount) or jobName;

        if imgui.BeginCombo('##JobSelect', displayLabel, ImGuiComboFlags_None) then
            for i, job in ipairs(JOB_LIST) do
                local isSelected = (job.id == jobId);
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
                    selectedPaletteJob = job.id;
                    selectedMacroIndex = nil;  -- Clear selection when switching jobs
                    currentPalettePage = 1;    -- Reset to page 1 when switching jobs
                    -- Clear spell cache when switching jobs
                    cachedSpells = nil;
                    cachedAbilities = nil;
                    cachedWeaponskills = nil;
                    cacheJobId = nil;
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
                target = 'me',
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

                            -- Draw icon on top of button
                            local icon = actions.GetBindIcon(macro);
                            if icon and icon.image then
                                local drawList = imgui.GetWindowDrawList();
                                if drawList then
                                    local iconSize = PALETTE_TILE_SIZE - 8;
                                    local iconX = buttonPos[1] + 4;
                                    local iconY = buttonPos[2] + 4;
                                    local iconPtr = tonumber(ffi.cast("uint32_t", icon.image));
                                    if iconPtr then
                                        drawList:AddImage(iconPtr, {iconX, iconY}, {iconX + iconSize, iconY + iconSize});
                                    end
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
                                if macro.target then
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
        -- No icon - show placeholder text
        imgui.SetCursorScreenPos({x + 8, y + size/2 - 6});
        imgui.TextColored(COLORS.textMuted, 'No Icon');
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
    local windowHeight = 450;

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
            iconPickerFilter[1] = '';
            iconPickerPage[1] = 1;  -- Reset page on tab switch
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
            iconPickerFilter[1] = '';
            iconPickerPage[2] = 1;  -- Reset page on tab switch
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

        -- Show item count / loading status for items tab
        if iconPickerTab == 2 then
            imgui.SameLine();
            if itemIconLoadState.loading then
                imgui.TextColored(COLORS.textMuted, string.format('Loading... %d%%', GetItemLoadProgress()));
            else
                imgui.TextColored(COLORS.textMuted, string.format('(%d items)', #itemIconLoadState.items));
            end
        elseif iconPickerTab == 1 then
            local allSpells = GetAllSpells();
            imgui.SameLine();
            imgui.TextColored(COLORS.textMuted, string.format('(%d spells)', #allSpells));
        end

        imgui.Spacing();

        local filter = iconPickerFilter[1]:lower();
        local currentPage = iconPickerPage[iconPickerTab];

        -- Reset page to 1 if filter changed
        if filter ~= iconPickerLastFilter[iconPickerTab] then
            iconPickerPage[iconPickerTab] = 1;
            currentPage = 1;
            iconPickerLastFilter[iconPickerTab] = filter;
        end

        -- Build filtered list to calculate total pages
        local filteredItems = {};
        if iconPickerTab == 1 then
            local allSpells = GetAllSpells();
            for _, spell in ipairs(allSpells) do
                local spellName = spell.name or '';
                if filter == '' or spellName:lower():find(filter, 1, true) then
                    table.insert(filteredItems, spell);
                end
            end
        elseif iconPickerTab == 2 then
            for _, item in ipairs(itemIconLoadState.items) do
                local itemName = item.name or '';
                if filter == '' or itemName:lower():find(filter, 1, true) then
                    table.insert(filteredItems, item);
                end
            end
        end

        local totalItems = #filteredItems;
        local totalPages = math.max(1, math.ceil(totalItems / ICONS_PER_PAGE));

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
                        local icon = textures:Get('spells' .. string.format('%05d', spell.id));
                        if icon and icon.image then
                            -- Handle grid layout
                            local col = displayedCount % ICON_GRID_COLUMNS;
                            if col > 0 then
                                imgui.SameLine(0, ICON_GRID_GAP);
                            end

                            local isSelected = editingMacro.customIconType == 'spell' and editingMacro.customIconId == spell.id;
                            if DrawIconButton('##spell' .. spell.id, icon, ICON_GRID_SIZE, isSelected, spell.name) then
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
            -- Item icons - render current page from filtered list
            if itemIconLoadState.loading and #itemIconLoadState.items == 0 then
                imgui.TextColored(COLORS.textMuted, 'Loading item database...');
            elseif totalItems == 0 then
                imgui.TextColored(COLORS.textMuted, 'No matching items found');
            else
                for i = startIdx, endIdx do
                    local item = filteredItems[i];
                    if item then
                        local icon = actions.GetBindIcon({ actionType = 'item', itemId = item.id });
                        if icon and icon.image then
                            -- Handle grid layout
                            local col = displayedCount % ICON_GRID_COLUMNS;
                            if col > 0 then
                                imgui.SameLine(0, ICON_GRID_GAP);
                            end

                            local isSelected = editingMacro.customIconType == 'item' and editingMacro.customIconId == item.id;
                            if DrawIconButton('##item' .. item.id, icon, ICON_GRID_SIZE, isSelected, item.name) then
                                editingMacro.customIconType = 'item';
                                editingMacro.customIconId = item.id;
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
        iconPickerPage = { 1, 1 };  -- Reset pages
        iconPickerLastFilter = { '', '' };
    end
end

function M.DrawMacroEditor()
    if not editingMacro then
        return;
    end

    -- Initialize editor fields from editing macro
    editorFields.actionType[1] = FindIndex(ACTION_TYPES, editingMacro.actionType or 'ma');
    editorFields.action[1] = editingMacro.action or '';
    editorFields.target[1] = FindIndex(TARGET_OPTIONS, editingMacro.target or 'me');
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
            if cachedSpells and #cachedSpells > 0 then
                DrawSearchableCombo('##spellCombo', cachedSpells, editingMacro.action or '', function(spell)
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
            if cachedAbilities and #cachedAbilities > 0 then
                DrawSearchableCombo('##abilityCombo', cachedAbilities, editingMacro.action or '', function(ability)
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
            if cachedWeaponskills and #cachedWeaponskills > 0 then
                DrawSearchableCombo('##wsCombo', cachedWeaponskills, editingMacro.action or '', function(ws)
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
            if cachedItems and #cachedItems > 0 then
                DrawSearchableCombo('##itemCombo', cachedItems, editingMacro.action or '', function(item)
                    editingMacro.action = item.name;
                    editingMacro.itemId = item.id;  -- Store item ID for fast icon lookup
                    editorFields.action[1] = item.name;
                    editingMacro.displayName = item.name;
                    editorFields.displayName[1] = item.name;
                end, true);  -- Show icons
                imgui.SameLine();
                imgui.TextColored(COLORS.textMuted, '(' .. #cachedItems .. ')');
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
            if cachedItems and #cachedItems > 0 then
                DrawSearchableCombo('##equipItemCombo', cachedItems, editingMacro.action or '', function(item)
                    editingMacro.action = item.name;
                    editingMacro.itemId = item.id;  -- Store item ID for fast icon lookup
                    editorFields.action[1] = item.name;
                    editingMacro.displayName = item.name;
                    editorFields.displayName[1] = item.name;
                end, true, selectedSlot);  -- Show icons, filter by selected slot
                imgui.SameLine();
                imgui.TextColored(COLORS.textMuted, '(' .. #cachedItems .. ')');
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
            -- Pet command input
            imgui.TextColored(COLORS.goldDim, 'Pet Command');
            imgui.SetNextItemWidth(240);
            if imgui.InputText('##petCommand', editorFields.action, INPUT_BUFFER_SIZE) then
                editingMacro.action = editorFields.action[1];
            end
            imgui.ShowHelp('Enter pet command name (e.g., "Assault", "Retreat")');

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
