--[[
* XIUI - tHotBar/tCrossBar Migration Handler
* Detects, parses, and converts tHotBar/tCrossBar bindings to XIUI format
]]--

require('common');
local jobs = require('libs.jobs');
local petregistry = require('modules.hotbar.petregistry');

local M = {};

-- ============================================
-- Constants
-- ============================================

-- Job abbreviation to ID mapping (reverse of libs/jobs.lua)
local JOB_ABBR_TO_ID = {
    WAR = 1, MNK = 2, WHM = 3, BLM = 4, RDM = 5, THF = 6, PLD = 7, DRK = 8,
    BST = 9, BRD = 10, RNG = 11, SAM = 12, NIN = 13, DRG = 14, SMN = 15, BLU = 16,
    COR = 17, PUP = 18, DNC = 19, SCH = 20, GEO = 21, RUN = 22
};

-- Action type mapping: tHotBar/tCrossBar -> XIUI
local ACTION_TYPE_MAP = {
    Ability = 'ja',
    Spell = 'ma',
    Trust = 'ma',
    Weaponskill = 'ws',
    Item = 'item',
    Command = 'macro',
    -- Blood pact types (SMN) - these are pet commands (executed via /pet)
    -- The cooldown tracking uses timer IDs 173/174 which XIUI handles in recast.lua
    Rage = 'pet',
    Ward = 'pet',
    BloodPactRage = 'pet',
    BloodPactWard = 'pet',
    -- Pet abilities (BST, PUP, etc.)
    PetAbility = 'pet',
    PetCommand = 'pet',
    -- Empty and unknown types are skipped
};

-- Special action name overrides for cooldown-tracking-only buttons
-- Only used when there's no macro to extract an action name from
-- (e.g., a button that just shows the Blood Pact cooldown without executing anything)
local ACTION_NAME_OVERRIDES = {
    Rage = 'Blood Pact: Rage',
    Ward = 'Blood Pact: Ward',
    BloodPactRage = 'Blood Pact: Rage',
    BloodPactWard = 'Blood Pact: Ward',
};

-- Crossbar combo mode mapping: tCrossBar -> XIUI
local COMBO_MODE_MAP = {
    LeftTrigger = 'L2',
    RightTrigger = 'R2',
    BothTriggersLeft = 'L2R2',
    BothTriggersRight = 'R2L2',
    DoubleTapLeft = 'L2x2',
    DoubleTapRight = 'R2x2',
};

-- ============================================
-- File System Helpers
-- ============================================

-- Check if a directory exists
local function DirectoryExists(path)
    local ok, err, code = os.rename(path, path);
    if not ok then
        if code == 13 then
            -- Permission denied, but exists
            return true;
        end
    end
    return ok;
end

-- List subdirectories in a path (returns array of names)
local function ListDirectories(basePath)
    local dirs = {};

    -- Normalize path separators for Windows
    local normalizedPath = basePath:gsub('/', '\\');

    -- Use Ashita's file system if available, otherwise try io.popen
    local handle = io.popen('dir /b /ad "' .. normalizedPath .. '" 2>nul');
    if handle then
        for line in handle:lines() do
            if line and #line > 0 then
                table.insert(dirs, line);
            end
        end
        handle:close();
    end

    return dirs;
end

-- List files in a directory with optional extension filter
local function ListFiles(basePath, extension)
    local files = {};

    -- Normalize path separators for Windows
    local normalizedPath = basePath:gsub('/', '\\');
    local cmd;
    if extension then
        cmd = 'dir /b "' .. normalizedPath .. '\\*.' .. extension .. '" 2>nul';
    else
        cmd = 'dir /b "' .. normalizedPath .. '" 2>nul';
    end

    local handle = io.popen(cmd);
    if handle then
        for line in handle:lines() do
            if line and #line > 0 then
                table.insert(files, line);
            end
        end
        handle:close();
    end

    return files;
end

-- ============================================
-- Detection Functions
-- ============================================

-- Get the base Ashita config path
function M.GetConfigPath()
    return AshitaCore:GetInstallPath() .. 'config/addons/';
end

-- Check if tHotBar addon config exists
function M.HasTHotBar()
    local path = M.GetConfigPath() .. 'thotbar';
    return DirectoryExists(path);
end

-- Check if tCrossBar addon config exists
function M.HasTCrossBar()
    local path = M.GetConfigPath() .. 'tcrossbar';
    return DirectoryExists(path);
end

-- Detect available tHotBar/tCrossBar data
-- Returns: { thotbar = { characters = {...} }, tcrossbar = { characters = {...} } }
function M.DetectTBarAddons()
    local result = {
        thotbar = { available = false, characters = {} },
        tcrossbar = { available = false, characters = {} }
    };

    local configPath = M.GetConfigPath();

    -- Scan tHotBar
    if M.HasTHotBar() then
        result.thotbar.available = true;
        local thotbarPath = configPath .. 'thotbar';
        local charDirs = ListDirectories(thotbarPath);

        for _, charDir in ipairs(charDirs) do
            -- Character folders are in format: CharacterName_12345
            if charDir:match('_') then
                local bindingsPath = thotbarPath .. '\\' .. charDir .. '\\bindings';
                if DirectoryExists(bindingsPath) then
                    local bindingFiles = ListFiles(bindingsPath, 'lua');
                    local jobFiles = {};
                    local hasGlobal = false;

                    for _, file in ipairs(bindingFiles) do
                        local baseName = file:match('(.+)%.lua$');
                        if baseName then
                            if baseName:lower() == 'globals' then
                                hasGlobal = true;
                            else
                                -- Check if it's a job file
                                if JOB_ABBR_TO_ID[baseName:upper()] then
                                    table.insert(jobFiles, baseName:upper());
                                end
                            end
                        end
                    end

                    table.insert(result.thotbar.characters, {
                        name = charDir,
                        path = bindingsPath,
                        hasGlobal = hasGlobal,
                        jobs = jobFiles
                    });
                end
            end
        end
    end

    -- Scan tCrossBar
    if M.HasTCrossBar() then
        result.tcrossbar.available = true;
        local tcrossbarPath = configPath .. 'tcrossbar';
        local charDirs = ListDirectories(tcrossbarPath);

        for _, charDir in ipairs(charDirs) do
            if charDir:match('_') then
                local bindingsPath = tcrossbarPath .. '\\' .. charDir .. '\\bindings';
                if DirectoryExists(bindingsPath) then
                    local bindingFiles = ListFiles(bindingsPath, 'lua');
                    local jobFiles = {};
                    local hasGlobal = false;

                    for _, file in ipairs(bindingFiles) do
                        local baseName = file:match('(.+)%.lua$');
                        if baseName then
                            if baseName:lower() == 'globals' then
                                hasGlobal = true;
                            else
                                if JOB_ABBR_TO_ID[baseName:upper()] then
                                    table.insert(jobFiles, baseName:upper());
                                end
                            end
                        end
                    end

                    table.insert(result.tcrossbar.characters, {
                        name = charDir,
                        path = bindingsPath,
                        hasGlobal = hasGlobal,
                        jobs = jobFiles
                    });
                end
            end
        end
    end

    return result;
end

-- ============================================
-- Keybind String Parsing
-- ============================================

-- Keybind string to row/slot mapping
-- tHotBar uses: "1"-"0" for row 1, "^1"-"^0" for Ctrl (row 2), "!1"-"!0" for Alt (row 3)
-- Key "0" maps to slot 10
local function ParseKeybindString(keyStr)
    if not keyStr or type(keyStr) ~= 'string' then return nil; end

    local modifier = nil;
    local keyNum = nil;

    -- Check for modifiers
    if keyStr:sub(1, 1) == '^' then
        modifier = 'ctrl';
        keyNum = keyStr:sub(2);
    elseif keyStr:sub(1, 1) == '!' then
        modifier = 'alt';
        keyNum = keyStr:sub(2);
    else
        modifier = 'none';
        keyNum = keyStr;
    end

    -- Convert key to slot number (0 = slot 10, 1-9 = slots 1-9)
    local slot = tonumber(keyNum);
    if slot == nil then return nil; end
    if slot == 0 then slot = 10; end
    if slot < 1 or slot > 10 then return nil; end

    -- Map modifier to XIUI bar index
    -- none (1-0) = Bar 1, ctrl (^1-^0) = Bar 2, alt (!1-!0) = Bar 3
    local barIndex;
    if modifier == 'none' then
        barIndex = 1;
    elseif modifier == 'ctrl' then
        barIndex = 2;
    elseif modifier == 'alt' then
        barIndex = 3;
    end

    return {
        barIndex = barIndex,
        slotIndex = slot,
        modifier = modifier,
    };
end

-- ============================================
-- Parsing Functions
-- ============================================

-- Safely load a Lua binding file
-- Returns: table or nil, error message
function M.LoadBindingFile(path)
    local chunk, loadErr = loadfile(path);
    if not chunk then
        return nil, 'Failed to load file: ' .. tostring(loadErr);
    end

    local ok, result = pcall(chunk);
    if not ok then
        return nil, 'Failed to execute file: ' .. tostring(result);
    end

    return result;
end

-- Parse bindings from a tHotBar file
-- Returns table with palettes and their bindings mapped to bar/slot
-- Format: { palettes = { { name = "Base", bindings = { [barIndex] = { [slotIndex] = binding } } }, ... } }
function M.ParseHotBarBindings(filePath)
    local data, err = M.LoadBindingFile(filePath);
    if not data then
        return nil, err;
    end

    local result = {
        palettes = {},
    };

    -- tHotBar structure: { Default = {}, Palettes = { { Name = "...", Bindings = { ["key"] = {...} } }, ... } }
    if not data.Palettes then
        return nil, 'No Palettes found in file';
    end

    for _, palette in ipairs(data.Palettes) do
        local paletteName = palette.Name or 'Unknown';
        local paletteBindings = {
            name = paletteName,
            bindings = {},  -- [barIndex][slotIndex] = binding
        };

        if palette.Bindings then
            for keyStr, binding in pairs(palette.Bindings) do
                if type(binding) == 'table' and binding.ActionType then
                    local parsed = ParseKeybindString(keyStr);
                    if parsed then
                        -- Initialize bar table if needed
                        if not paletteBindings.bindings[parsed.barIndex] then
                            paletteBindings.bindings[parsed.barIndex] = {};
                        end
                        paletteBindings.bindings[parsed.barIndex][parsed.slotIndex] = binding;
                    end
                end
            end
        end

        table.insert(result.palettes, paletteBindings);
    end

    return result;
end

-- Parse bindings from a tCrossBar file
-- Returns table with combo modes as keys
function M.ParseCrossBarBindings(filePath)
    local data, err = M.LoadBindingFile(filePath);
    if not data then
        return nil, err;
    end

    local comboBindings = {};

    -- tCrossBar organizes by combo mode
    for comboMode, slots in pairs(data) do
        if type(slots) == 'table' then
            local xiuiComboMode = COMBO_MODE_MAP[comboMode];
            if xiuiComboMode then
                comboBindings[xiuiComboMode] = {};

                for key, binding in pairs(slots) do
                    if type(binding) == 'table' and binding.ActionType then
                        local slotIndex;
                        if type(key) == 'number' then
                            slotIndex = key;
                        elseif type(key) == 'string' then
                            local num = key:match('Macro(%d+)') or key:match('^(%d+)$');
                            slotIndex = tonumber(num);
                        end

                        if slotIndex and slotIndex >= 1 and slotIndex <= 8 then
                            comboBindings[xiuiComboMode][slotIndex] = binding;
                        end
                    end
                end
            end
        end
    end

    return comboBindings;
end

-- ============================================
-- Conversion Functions
-- ============================================

-- Helper to parse a single macro line and extract action info
-- Returns: actionName, target (without brackets), commandType or nil if not a recognized command
local function ParseMacroLine(line)
    if not line or type(line) ~= 'string' then return nil; end

    -- Trim whitespace
    line = line:match('^%s*(.-)%s*$');

    -- Parse /ma "Spell Name" <target> or /ma "Spell Name"
    local maMatch = line:match('^/ma%s+"([^"]+)"');
    if maMatch then
        local target = line:match('<([^>]+)>');
        return maMatch, target or 't', 'ma';
    end

    -- Parse /ja "Ability Name" <target>
    local jaMatch = line:match('^/ja%s+"([^"]+)"');
    if jaMatch then
        local target = line:match('<([^>]+)>');
        return jaMatch, target or 't', 'ja';
    end

    -- Parse /ws "Weaponskill Name" <target>
    local wsMatch = line:match('^/ws%s+"([^"]+)"');
    if wsMatch then
        local target = line:match('<([^>]+)>');
        return wsMatch, target or 't', 'ws';
    end

    -- Parse /item "Item Name" <target>
    local itemMatch = line:match('^/item%s+"([^"]+)"');
    if itemMatch then
        local target = line:match('<([^>]+)>');
        return itemMatch, target or 'me', 'item';
    end

    -- Parse /pet "Pet Ability" <target>
    local petMatch = line:match('^/pet%s+"([^"]+)"');
    if petMatch then
        local target = line:match('<([^>]+)>');
        return petMatch, target or 't', 'pet';
    end

    return nil;
end

-- Convert a single tHotBar/tCrossBar binding to XIUI format
-- Returns: XIUI slot action data or nil if cannot convert
function M.ConvertBinding(tbarBinding)
    if not tbarBinding then return nil; end

    local actionType = ACTION_TYPE_MAP[tbarBinding.ActionType];
    if not actionType then
        -- Unknown or Empty type - skip
        return nil;
    end

    local xiuiAction = {
        actionType = actionType,
    };

    -- Handle Label -> displayName
    if tbarBinding.Label and #tbarBinding.Label > 0 then
        xiuiAction.displayName = tbarBinding.Label;
    end

    -- Handle Macro array -> macroText
    if tbarBinding.Macro and type(tbarBinding.Macro) == 'table' then
        local macroLines = {};
        for _, line in ipairs(tbarBinding.Macro) do
            if type(line) == 'string' then
                table.insert(macroLines, line);
            end
        end

        if #macroLines > 0 then
            xiuiAction.macroText = table.concat(macroLines, '\n');

            -- Scan ALL lines to find the primary action command
            -- Priority: /ma, /ja, /ws, /item, /pet (first found wins)
            -- This handles multi-line macros that equip items before using them
            for _, line in ipairs(macroLines) do
                local actionName, target, cmdType = ParseMacroLine(line);
                if actionName then
                    xiuiAction.action = actionName;
                    -- Store target WITHOUT brackets (consistent format)
                    xiuiAction.target = target;
                    -- Override actionType if we found a specific command
                    -- (e.g., tHotBar might mark it as "Command" but we found /item)
                    if cmdType == 'ma' then
                        xiuiAction.actionType = 'ma';
                    elseif cmdType == 'ja' then
                        xiuiAction.actionType = 'ja';
                    elseif cmdType == 'ws' then
                        xiuiAction.actionType = 'ws';
                    elseif cmdType == 'item' then
                        xiuiAction.actionType = 'item';
                    elseif cmdType == 'pet' then
                        xiuiAction.actionType = 'pet';  -- Pet commands use pet type
                    end
                    break;  -- Use first action found
                end
            end
        end
    end

    -- Handle Image -> customIconPath
    if tbarBinding.Image and type(tbarBinding.Image) == 'string' and #tbarBinding.Image > 0 then
        -- Check if it's a path (contains / or \)
        if tbarBinding.Image:match('[/\\]') then
            xiuiAction.customIconPath = tbarBinding.Image;
            xiuiAction.customIconType = 'path';
        end
    end

    -- Check for special action name overrides (e.g., Rage -> "Blood Pact: Rage")
    -- Only apply if we didn't already extract an action from the macro
    -- (This handles cooldown-tracking-only buttons that don't have a real macro)
    if not xiuiAction.action then
        local actionOverride = ACTION_NAME_OVERRIDES[tbarBinding.ActionType];
        if not actionOverride and tbarBinding.Label then
            actionOverride = ACTION_NAME_OVERRIDES[tbarBinding.Label];
        end
        if actionOverride then
            xiuiAction.action = actionOverride;
            -- Keep the original label as displayName for visual consistency
            if not xiuiAction.displayName then
                xiuiAction.displayName = tbarBinding.Label or actionOverride;
            end
        end
    end

    -- Use Label as displayName if action wasn't extracted
    if not xiuiAction.action and xiuiAction.displayName then
        xiuiAction.action = xiuiAction.displayName;
    end

    -- Set default target if not extracted (WITHOUT brackets - display layer adds them)
    if not xiuiAction.target then
        if xiuiAction.actionType == 'ma' or xiuiAction.actionType == 'ja' or xiuiAction.actionType == 'ws' or xiuiAction.actionType == 'pet' then
            xiuiAction.target = 't';
        elseif xiuiAction.actionType == 'item' then
            xiuiAction.target = 'me';
        end
    end

    return xiuiAction;
end

-- ============================================
-- Import Functions
-- ============================================

-- Get job ID from abbreviation
function M.GetJobId(jobAbbr)
    return JOB_ABBR_TO_ID[jobAbbr:upper()];
end

-- Get storage key for a job (XIUI format: 'jobId:0')
function M.GetStorageKey(jobAbbr)
    local jobId = M.GetJobId(jobAbbr);
    if jobId then
        return string.format('%d:0', jobId);
    end
    return 'global';
end

-- Get storage key for a job+palette combination
-- Maps tHotBar palette names to XIUI storage keys:
--   "Base" -> base job key (jobId:0)
--   Avatar name (Ifrit, Shiva, etc.) -> pet palette key (jobId:0:avatar:ifrit)
--   Spirit name -> pet palette key (jobId:0:spirit:firespirit)
--   Other names -> general palette key (jobId:0:palette:PaletteName)
function M.GetStorageKeyForPalette(jobAbbr, paletteName)
    local baseKey = M.GetStorageKey(jobAbbr);
    if not paletteName or paletteName == 'Base' then
        return baseKey;
    end

    -- Check if it's an avatar name (SMN)
    if petregistry.avatars[paletteName] then
        local avatarKey = petregistry.avatars[paletteName];
        return string.format('%s:avatar:%s', baseKey, avatarKey);
    end

    -- Check if it's a spirit name (SMN)
    if petregistry.spirits[paletteName] then
        local spiritKey = petregistry.spirits[paletteName];
        return string.format('%s:spirit:%s', baseKey, spiritKey);
    end

    -- Not a recognized pet - use general palette key
    return string.format('%s:palette:%s', baseKey, paletteName);
end

-- Check if a palette name corresponds to a pet palette (avatar or spirit)
function M.IsPetPalette(paletteName)
    if not paletteName then return false; end
    return petregistry.avatars[paletteName] ~= nil or petregistry.spirits[paletteName] ~= nil;
end

-- ============================================
-- Macro Creation Helpers
-- ============================================

-- Convert a slot storage key to a macro palette key
-- Storage key format: 'jobId:subjobId' or 'jobId:subjobId:palette:name' or 'jobId:subjobId:avatar:name'
-- Macro palette key format: jobId (number) or 'jobId:avatar:name' (string) or 'global'
local function StorageKeyToMacroPaletteKey(storageKey)
    if storageKey == 'global' then
        return 'global';
    end

    -- Parse the storage key
    local jobId = storageKey:match('^(%d+)');
    if not jobId then
        return 'global';
    end

    -- Check for pet palette (avatar:name or spirit:name)
    local petType, petKey = storageKey:match(':([^:]+):([^:]+)$');
    if petType and (petType == 'avatar' or petType == 'spirit') then
        return string.format('%s:%s:%s', jobId, petType, petKey);
    end

    -- Base job key - return as number
    return tonumber(jobId);
end

-- Create a macro in the macro database for a specific palette
-- Returns the macro ID
local function CreateMacroInPalette(macroData, paletteKey)
    if not gConfig then return nil; end

    -- Ensure macroDB exists
    if not gConfig.macroDB then
        gConfig.macroDB = {};
    end
    if not gConfig.macroDB[paletteKey] then
        gConfig.macroDB[paletteKey] = {};
    end

    local db = gConfig.macroDB[paletteKey];

    -- Generate unique ID (find max ID and add 1)
    local maxId = 0;
    for _, macro in ipairs(db) do
        if macro.id and macro.id > maxId then
            maxId = macro.id;
        end
    end

    -- Create the macro
    local newMacro = {
        id = maxId + 1,
        actionType = macroData.actionType,
        action = macroData.action,
        target = macroData.target,
        displayName = macroData.displayName or macroData.action,
        macroText = macroData.macroText,
        itemId = macroData.itemId,
        customIconType = macroData.customIconType,
        customIconId = macroData.customIconId,
        customIconPath = macroData.customIconPath,
    };

    table.insert(db, newMacro);

    return newMacro.id;
end

-- Check if a similar macro already exists in the palette (to avoid duplicates)
-- Returns the existing macro ID if found, nil otherwise
local function FindExistingMacro(macroData, paletteKey)
    if not gConfig or not gConfig.macroDB or not gConfig.macroDB[paletteKey] then
        return nil;
    end

    local db = gConfig.macroDB[paletteKey];
    for _, macro in ipairs(db) do
        -- Match by actionType, action, and target
        if macro.actionType == macroData.actionType and
           macro.action == macroData.action and
           macro.target == macroData.target then
            return macro.id;
        end
    end

    return nil;
end

-- ============================================
-- Conflict Detection
-- ============================================

-- Check if a slot has existing data in XIUI
function M.HasExistingHotbarSlot(barIndex, slotIndex, storageKey)
    if not gConfig then return false; end

    local configKey = 'hotbarBar' .. barIndex;
    local barSettings = gConfig[configKey];
    if not barSettings or not barSettings.slotActions then return false; end

    local jobSlots = barSettings.slotActions[storageKey];
    if not jobSlots then return false; end

    local slot = jobSlots[slotIndex] or jobSlots[tostring(slotIndex)];
    return slot ~= nil and not slot.cleared;
end

-- Check if a crossbar slot has existing data
function M.HasExistingCrossbarSlot(comboMode, slotIndex, storageKey)
    if not gConfig or not gConfig.hotbarCrossbar then return false; end

    local slotActions = gConfig.hotbarCrossbar.slotActions;
    if not slotActions then return false; end

    local jobSlots = slotActions[storageKey];
    if not jobSlots or not jobSlots[comboMode] then return false; end

    local slot = jobSlots[comboMode][slotIndex];
    return slot ~= nil;
end

-- Clear all slots for a specific bar and storage key
-- Called before importing to wipe existing data (replace semantics)
function M.ClearHotbarSlots(barIndex, storageKey)
    if not gConfig then return; end

    local configKey = 'hotbarBar' .. barIndex;
    if not gConfig[configKey] then return; end
    if not gConfig[configKey].slotActions then return; end

    -- Clear the entire storage key (wipe all slots for this palette)
    gConfig[configKey].slotActions[storageKey] = {};
end

-- Clear all slots for a specific crossbar storage key and combo mode
-- Called before importing to wipe existing data (replace semantics)
function M.ClearCrossbarSlots(comboMode, storageKey)
    if not gConfig then return; end
    if not gConfig.hotbarCrossbar then return; end
    if not gConfig.hotbarCrossbar.slotActions then return; end
    if not gConfig.hotbarCrossbar.slotActions[storageKey] then return; end

    -- Clear the combo mode slots for this storage key
    gConfig.hotbarCrossbar.slotActions[storageKey][comboMode] = {};
end

-- Import a single binding to a hotbar slot
-- Creates a macro in the macro database and references it from the slot
-- Returns: true if imported, false if skipped
function M.ImportHotbarBinding(barIndex, slotIndex, xiuiAction, storageKey)
    if not gConfig then return false; end

    local configKey = 'hotbarBar' .. barIndex;

    -- Ensure structure exists
    if not gConfig[configKey] then
        gConfig[configKey] = {};
    end
    if not gConfig[configKey].slotActions then
        gConfig[configKey].slotActions = {};
    end
    if not gConfig[configKey].slotActions[storageKey] then
        gConfig[configKey].slotActions[storageKey] = {};
    end

    -- Determine the macro palette key from the storage key
    local macroPaletteKey = StorageKeyToMacroPaletteKey(storageKey);

    -- Check if a similar macro already exists (avoid duplicates)
    local macroId = FindExistingMacro(xiuiAction, macroPaletteKey);

    -- If no existing macro, create a new one
    if not macroId then
        macroId = CreateMacroInPalette(xiuiAction, macroPaletteKey);
    end

    -- Set the slot data with macro reference
    local slotData = {
        actionType = xiuiAction.actionType,
        action = xiuiAction.action,
        target = xiuiAction.target,
        displayName = xiuiAction.displayName or xiuiAction.action,
        macroText = xiuiAction.macroText,
        itemId = xiuiAction.itemId,
        customIconType = xiuiAction.customIconType,
        customIconId = xiuiAction.customIconId,
        customIconPath = xiuiAction.customIconPath,
        -- Reference the macro in the palette
        macroRef = macroId,
        macroPaletteKey = macroPaletteKey,
    };

    gConfig[configKey].slotActions[storageKey][slotIndex] = slotData;
    return true;
end

-- Import a single binding to a crossbar slot
-- Creates a macro in the macro database and references it from the slot
function M.ImportCrossbarBinding(comboMode, slotIndex, xiuiAction, storageKey)
    if not gConfig then return false; end

    -- Ensure structure exists
    if not gConfig.hotbarCrossbar then
        gConfig.hotbarCrossbar = {};
    end
    if not gConfig.hotbarCrossbar.slotActions then
        gConfig.hotbarCrossbar.slotActions = {};
    end
    if not gConfig.hotbarCrossbar.slotActions[storageKey] then
        gConfig.hotbarCrossbar.slotActions[storageKey] = {};
    end
    if not gConfig.hotbarCrossbar.slotActions[storageKey][comboMode] then
        gConfig.hotbarCrossbar.slotActions[storageKey][comboMode] = {};
    end

    -- Determine the macro palette key from the storage key
    local macroPaletteKey = StorageKeyToMacroPaletteKey(storageKey);

    -- Check if a similar macro already exists (avoid duplicates)
    local macroId = FindExistingMacro(xiuiAction, macroPaletteKey);

    -- If no existing macro, create a new one
    if not macroId then
        macroId = CreateMacroInPalette(xiuiAction, macroPaletteKey);
    end

    -- Set the slot data with macro reference
    local slotData = {
        actionType = xiuiAction.actionType,
        action = xiuiAction.action,
        target = xiuiAction.target,
        displayName = xiuiAction.displayName or xiuiAction.action,
        macroText = xiuiAction.macroText,
        itemId = xiuiAction.itemId,
        customIconType = xiuiAction.customIconType,
        customIconId = xiuiAction.customIconId,
        customIconPath = xiuiAction.customIconPath,
        -- Reference the macro in the palette
        macroRef = macroId,
        macroPaletteKey = macroPaletteKey,
    };

    gConfig.hotbarCrossbar.slotActions[storageKey][comboMode][slotIndex] = slotData;
    return true;
end

-- ============================================
-- Utility Functions
-- ============================================

-- Get count of non-empty bindings from tHotBar parsed data
-- Input: { palettes = { { name = "...", bindings = { [barIndex] = { [slotIndex] = binding } } }, ... } }
function M.CountHotbarBindings(parsedData)
    if not parsedData or not parsedData.palettes then return 0; end

    local count = 0;
    for _, palette in ipairs(parsedData.palettes) do
        if palette.bindings then
            for barIndex, barSlots in pairs(palette.bindings) do
                for slotIndex, binding in pairs(barSlots) do
                    if binding and binding.ActionType and binding.ActionType ~= 'Empty' then
                        count = count + 1;
                    end
                end
            end
        end
    end

    return count;
end

-- Get count of non-empty bindings from tCrossBar parsed data
function M.CountCrossbarBindings(parsedData)
    if not parsedData then return 0; end

    local count = 0;
    for comboMode, slots in pairs(parsedData) do
        if type(slots) == 'table' then
            for slotIndex, binding in pairs(slots) do
                if binding and binding.ActionType and binding.ActionType ~= 'Empty' then
                    count = count + 1;
                end
            end
        end
    end

    return count;
end

-- Get list of palette names from parsed tHotBar data
function M.GetPaletteNames(parsedData)
    if not parsedData or not parsedData.palettes then return {}; end

    local names = {};
    for _, palette in ipairs(parsedData.palettes) do
        table.insert(names, palette.name or 'Unknown');
    end
    return names;
end

-- Get bindings for a specific palette by name
function M.GetPaletteBindings(parsedData, paletteName)
    if not parsedData or not parsedData.palettes then return nil; end

    for _, palette in ipairs(parsedData.palettes) do
        if palette.name == paletteName then
            return palette.bindings;
        end
    end
    return nil;
end

return M;
