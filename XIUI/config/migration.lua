--[[
* XIUI Config Menu - Migration Wizard
* Imports tHotBar/tCrossBar bindings to XIUI
]]--

require('common');
require('handlers.helpers');
local components = require('config.components');
local tbarMigration = require('handlers.tbar_migration');
local imgui = require('imgui');
local palette = require('modules.hotbar.palette');

local M = {};

-- ============================================
-- Wizard State
-- ============================================

local wizardState = {
    isOpen = false,
    currentStep = 1,
    -- Step 1: Detection results
    detectionData = nil,
    -- Step 2: User selections
    selectedCharacter = nil,
    importHotbar = true,
    importCrossbar = true,
    selectedJobs = {},  -- { ['WHM'] = true, ['BLM'] = true, ... }
    importGlobal = true,
    -- Step 2b: Palette selection per job (tHotBar has multiple palettes per job)
    -- Changed to multi-select: { ['WHM'] = { ['Base'] = true, ['Ifrit'] = true }, ... }
    selectedPalettes = {},
    availablePalettes = {},  -- { ['WHM'] = {'Base', 'Esuna', ...}, ... }
    -- Step 2c: Crossbar palette selection (tCrossBar also has palettes)
    selectedCrossbarPalettes = {},
    availableCrossbarPalettes = {},  -- { ['WHM'] = {'Base', ...}, ... }
    -- Step 3: Conflict data
    conflicts = {},
    conflictResolutions = {},  -- { [conflictKey] = 'keep' | 'replace' }
    -- Step 4: Import results
    importResults = nil,
};

-- Color constants (matching components.TAB_STYLE)
local COLORS = {
    gold = {0.957, 0.855, 0.592, 1.0},
    goldDark = {0.6, 0.5, 0.3, 1.0},
    bgDark = {0.059, 0.055, 0.047, 1.0},
    bgMedium = {0.098, 0.090, 0.075, 1.0},
    bgLight = {0.137, 0.125, 0.106, 1.0},
    bgLighter = {0.176, 0.161, 0.137, 1.0},
    borderDark = {0.2, 0.18, 0.15, 1.0},
    text = {0.9, 0.9, 0.9, 1.0},
    textDim = {0.6, 0.6, 0.6, 1.0},
    success = {0.3, 0.8, 0.3, 1.0},
    warning = {0.9, 0.7, 0.2, 1.0},
    error = {0.9, 0.3, 0.3, 1.0},
};

-- ============================================
-- Public API
-- ============================================

function M.Open()
    wizardState.isOpen = true;
    wizardState.currentStep = 1;
    wizardState.detectionData = nil;
    wizardState.selectedCharacter = nil;
    wizardState.importHotbar = true;
    wizardState.importCrossbar = true;
    wizardState.selectedJobs = {};
    wizardState.importGlobal = true;
    wizardState.selectedPalettes = {};
    wizardState.availablePalettes = {};
    wizardState.selectedCrossbarPalettes = {};
    wizardState.availableCrossbarPalettes = {};
    wizardState.conflicts = {};
    wizardState.conflictResolutions = {};
    wizardState.importResults = nil;

    -- Run detection immediately
    wizardState.detectionData = tbarMigration.DetectTBarAddons();
end

function M.Close()
    wizardState.isOpen = false;
end

function M.IsOpen()
    return wizardState.isOpen;
end

-- ============================================
-- Helper Functions
-- ============================================

local function GetAllJobs()
    local allJobs = {};
    if wizardState.detectionData then
        local charData = wizardState.selectedCharacter;
        if charData then
            for _, job in ipairs(charData.thotbarJobs or {}) do
                allJobs[job] = true;
            end
            for _, job in ipairs(charData.tcrossbarJobs or {}) do
                allJobs[job] = true;
            end
        end
    end

    local result = {};
    for job, _ in pairs(allJobs) do
        table.insert(result, job);
    end
    table.sort(result);
    return result;
end

local function GetSelectedCharData()
    if not wizardState.selectedCharacter then return nil; end
    return wizardState.selectedCharacter;
end

local function BuildConflictList()
    local conflicts = {};
    local charData = GetSelectedCharData();
    if not charData then return conflicts; end

    local jobList = {};
    if wizardState.importGlobal then
        table.insert(jobList, 'global');
    end
    for job, selected in pairs(wizardState.selectedJobs) do
        if selected then
            table.insert(jobList, job);
        end
    end

    -- Check hotbar conflicts (tHotBar uses palette-based structure)
    -- Now iterates through ALL selected palettes per job
    if wizardState.importHotbar and charData.thotbarPath then
        for _, jobKey in ipairs(jobList) do
            local fileName = (jobKey == 'global') and 'globals.lua' or (jobKey .. '.lua');
            local filePath = charData.thotbarPath .. '\\' .. fileName;
            local parsedData = tbarMigration.ParseHotBarBindings(filePath);

            if parsedData and parsedData.palettes then
                -- Iterate through all selected palettes for this job
                local jobSelectedPalettes = wizardState.selectedPalettes[jobKey] or {};
                for paletteName, isSelected in pairs(jobSelectedPalettes) do
                    if isSelected then
                        -- Get the correct storage key for this palette
                        local storageKey;
                        if jobKey == 'global' then
                            storageKey = 'global';
                        else
                            storageKey = tbarMigration.GetStorageKeyForPalette(jobKey, paletteName);
                        end

                        local paletteBindings = tbarMigration.GetPaletteBindings(parsedData, paletteName);

                        if paletteBindings then
                            -- paletteBindings is { [barIndex] = { [slotIndex] = binding } }
                            for barIndex, barSlots in pairs(paletteBindings) do
                                if barIndex >= 1 and barIndex <= 6 then
                                    for slotIndex, binding in pairs(barSlots) do
                                        if tbarMigration.HasExistingHotbarSlot(barIndex, slotIndex, storageKey) then
                                            local convertedAction = tbarMigration.ConvertBinding(binding);
                                            if convertedAction then
                                                local conflictKey = string.format('hotbar:%d:%d:%s', barIndex, slotIndex, storageKey);
                                                table.insert(conflicts, {
                                                    key = conflictKey,
                                                    type = 'hotbar',
                                                    barIndex = barIndex,
                                                    slotIndex = slotIndex,
                                                    storageKey = storageKey,
                                                    jobKey = jobKey,
                                                    paletteName = paletteName,
                                                    newAction = convertedAction,
                                                    newLabel = convertedAction.displayName or convertedAction.action or '?',
                                                });
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Check crossbar conflicts (now palette-based like hotbar)
    if wizardState.importCrossbar and charData.tcrossbarPath then
        for _, jobKey in ipairs(jobList) do
            local fileName = (jobKey == 'global') and 'globals.lua' or (jobKey .. '.lua');
            local filePath = charData.tcrossbarPath .. '\\' .. fileName;
            local parsedData = tbarMigration.ParseCrossBarBindings(filePath);

            if parsedData and parsedData.palettes then
                -- Iterate through selected palettes for this job
                local jobSelectedPalettes = wizardState.selectedCrossbarPalettes and wizardState.selectedCrossbarPalettes[jobKey] or {};
                for paletteName, isSelected in pairs(jobSelectedPalettes) do
                    if isSelected then
                        local storageKey;
                        if jobKey == 'global' then
                            storageKey = 'global';
                        else
                            storageKey = tbarMigration.GetStorageKeyForPalette(jobKey, paletteName);
                        end

                        local paletteBindings = tbarMigration.GetCrossbarPaletteBindings(parsedData, paletteName);
                        if paletteBindings then
                            for comboMode, slots in pairs(paletteBindings) do
                                for slotIndex, binding in pairs(slots) do
                                    if tbarMigration.HasExistingCrossbarSlot(comboMode, slotIndex, storageKey) then
                                        local convertedAction = tbarMigration.ConvertBinding(binding);
                                        if convertedAction then
                                            local conflictKey = string.format('crossbar:%s:%d:%s', comboMode, slotIndex, storageKey);
                                            table.insert(conflicts, {
                                                key = conflictKey,
                                                type = 'crossbar',
                                                comboMode = comboMode,
                                                slotIndex = slotIndex,
                                                storageKey = storageKey,
                                                jobKey = jobKey,
                                                paletteName = paletteName,
                                                newAction = convertedAction,
                                                newLabel = convertedAction.displayName or convertedAction.action or '?',
                                            });
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return conflicts;
end

local function ExecuteImport()
    local results = {
        hotbarImported = 0,
        crossbarImported = 0,
        skipped = 0,
        errors = {},
        paletteDetails = {},  -- Track what was imported per palette
    };

    local charData = GetSelectedCharData();
    if not charData then
        table.insert(results.errors, 'No character selected');
        return results;
    end

    local jobList = {};
    if wizardState.importGlobal then
        table.insert(jobList, 'global');
    end
    for job, selected in pairs(wizardState.selectedJobs) do
        if selected then
            table.insert(jobList, job);
        end
    end

    -- Track which bar/storageKey combinations to clear before importing
    -- We clear the ENTIRE palette for a bar/storageKey when ANY slot will be replaced
    -- This ensures a clean import without leftover old data
    local hotbarToClear = {};  -- { [barIndex] = { [storageKey] = true } }
    local crossbarToClear = {}; -- { [storageKey] = { [comboMode] = true } }

    -- First pass: determine which bars/palettes need to be cleared
    -- We clear if ANY slot has 'replace' resolution (or no conflict at all)
    if wizardState.importHotbar and charData.thotbarPath then
        for _, jobKey in ipairs(jobList) do
            local fileName = (jobKey == 'global') and 'globals.lua' or (jobKey .. '.lua');
            local filePath = charData.thotbarPath .. '\\' .. fileName;
            local parsedData = tbarMigration.ParseHotBarBindings(filePath);

            if parsedData and parsedData.palettes then
                local jobSelectedPalettes = wizardState.selectedPalettes[jobKey] or {};
                for paletteName, isSelected in pairs(jobSelectedPalettes) do
                    if isSelected then
                        local storageKey;
                        if jobKey == 'global' then
                            storageKey = 'global';
                        else
                            storageKey = tbarMigration.GetStorageKeyForPalette(jobKey, paletteName);
                        end

                        local paletteBindings = tbarMigration.GetPaletteBindings(parsedData, paletteName);
                        if paletteBindings then
                            for barIndex, barSlots in pairs(paletteBindings) do
                                if barIndex >= 1 and barIndex <= 6 then
                                    for slotIndex, binding in pairs(barSlots) do
                                        local convertedAction = tbarMigration.ConvertBinding(binding);
                                        if convertedAction then
                                            local conflictKey = string.format('hotbar:%d:%d:%s', barIndex, slotIndex, storageKey);
                                            local resolution = wizardState.conflictResolutions[conflictKey];
                                            -- If any slot will be replaced (not 'keep'), mark for clearing
                                            if resolution ~= 'keep' then
                                                if not hotbarToClear[barIndex] then
                                                    hotbarToClear[barIndex] = {};
                                                end
                                                hotbarToClear[barIndex][storageKey] = true;
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if wizardState.importCrossbar and charData.tcrossbarPath then
        for _, jobKey in ipairs(jobList) do
            local fileName = (jobKey == 'global') and 'globals.lua' or (jobKey .. '.lua');
            local filePath = charData.tcrossbarPath .. '\\' .. fileName;
            local parsedData = tbarMigration.ParseCrossBarBindings(filePath);

            if parsedData and parsedData.palettes then
                -- Iterate through selected palettes for this job
                local jobSelectedPalettes = wizardState.selectedCrossbarPalettes and wizardState.selectedCrossbarPalettes[jobKey] or {};
                for paletteName, isSelected in pairs(jobSelectedPalettes) do
                    if isSelected then
                        local storageKey;
                        if jobKey == 'global' then
                            storageKey = 'global';
                        else
                            storageKey = tbarMigration.GetStorageKeyForPalette(jobKey, paletteName);
                        end

                        local paletteBindings = tbarMigration.GetCrossbarPaletteBindings(parsedData, paletteName);
                        if paletteBindings then
                            for comboMode, slots in pairs(paletteBindings) do
                                for slotIndex, binding in pairs(slots) do
                                    local convertedAction = tbarMigration.ConvertBinding(binding);
                                    if convertedAction then
                                        local conflictKey = string.format('crossbar:%s:%d:%s', comboMode, slotIndex, storageKey);
                                        local resolution = wizardState.conflictResolutions[conflictKey];
                                        -- If any slot will be replaced (not 'keep'), mark for clearing
                                        if resolution ~= 'keep' then
                                            if not crossbarToClear[storageKey] then
                                                crossbarToClear[storageKey] = {};
                                            end
                                            crossbarToClear[storageKey][comboMode] = true;
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Clear marked hotbar palettes before importing
    for barIndex, storageKeys in pairs(hotbarToClear) do
        for storageKey, _ in pairs(storageKeys) do
            tbarMigration.ClearHotbarSlots(barIndex, storageKey);
        end
    end

    -- Clear marked crossbar combo modes before importing
    for storageKey, comboModes in pairs(crossbarToClear) do
        for comboMode, _ in pairs(comboModes) do
            tbarMigration.ClearCrossbarSlots(comboMode, storageKey);
        end
    end

    -- Import hotbar bindings (tHotBar uses palette-based structure)
    -- Now iterates through ALL selected palettes per job
    if wizardState.importHotbar and charData.thotbarPath then
        for _, jobKey in ipairs(jobList) do
            local fileName = (jobKey == 'global') and 'globals.lua' or (jobKey .. '.lua');
            local filePath = charData.thotbarPath .. '\\' .. fileName;
            local parsedData = tbarMigration.ParseHotBarBindings(filePath);

            if parsedData and parsedData.palettes then
                -- Iterate through all selected palettes for this job
                local jobSelectedPalettes = wizardState.selectedPalettes[jobKey] or {};
                for paletteName, isSelected in pairs(jobSelectedPalettes) do
                    if isSelected then
                        -- Get the correct storage key for this palette
                        local storageKey;
                        if jobKey == 'global' then
                            storageKey = 'global';
                        else
                            storageKey = tbarMigration.GetStorageKeyForPalette(jobKey, paletteName);
                        end

                        local paletteBindings = tbarMigration.GetPaletteBindings(parsedData, paletteName);

                        if paletteBindings then
                            local paletteCount = 0;
                            -- paletteBindings is { [barIndex] = { [slotIndex] = binding } }
                            for barIndex, barSlots in pairs(paletteBindings) do
                                if barIndex >= 1 and barIndex <= 6 then
                                    for slotIndex, binding in pairs(barSlots) do
                                        local convertedAction = tbarMigration.ConvertBinding(binding);
                                        if convertedAction then
                                            local conflictKey = string.format('hotbar:%d:%d:%s', barIndex, slotIndex, storageKey);
                                            local resolution = wizardState.conflictResolutions[conflictKey];

                                            -- Check if we should skip due to conflict resolution
                                            if resolution == 'keep' then
                                                results.skipped = results.skipped + 1;
                                            else
                                                -- Either no conflict or resolution is 'replace'
                                                -- (Slots already cleared above, just import)
                                                local success = tbarMigration.ImportHotbarBinding(barIndex, slotIndex, convertedAction, storageKey);
                                                if success then
                                                    results.hotbarImported = results.hotbarImported + 1;
                                                    paletteCount = paletteCount + 1;
                                                end
                                            end
                                        end
                                    end
                                end
                            end

                            -- Track what was imported
                            if paletteCount > 0 then
                                -- Register the palette with the palette system
                                local jobId = tbarMigration.GetJobId(jobKey);
                                if jobId then
                                    tbarMigration.RegisterImportedPalette(paletteName, jobId, false);
                                end

                                local isPetPalette = tbarMigration.IsPetPalette(paletteName);
                                local targetDesc = isPetPalette
                                    and string.format('%s pet palette', paletteName)
                                    or (paletteName == 'Base' and 'base palette' or string.format('"%s" palette', paletteName));
                                table.insert(results.paletteDetails, {
                                    job = jobKey,
                                    palette = paletteName,
                                    count = paletteCount,
                                    storageKey = storageKey,
                                    description = string.format('%s %s: %d bindings', jobKey, targetDesc, paletteCount),
                                });
                            end
                        else
                            table.insert(results.errors, 'Palette "' .. paletteName .. '" not found for ' .. jobKey);
                        end
                    end
                end
            end
        end
    end

    -- Import crossbar bindings (now palette-based like hotbar)
    if wizardState.importCrossbar and charData.tcrossbarPath then
        for _, jobKey in ipairs(jobList) do
            local fileName = (jobKey == 'global') and 'globals.lua' or (jobKey .. '.lua');
            local filePath = charData.tcrossbarPath .. '\\' .. fileName;
            local parsedData = tbarMigration.ParseCrossBarBindings(filePath);

            if parsedData and parsedData.palettes then
                -- Iterate through selected palettes for this job
                local jobSelectedPalettes = wizardState.selectedCrossbarPalettes and wizardState.selectedCrossbarPalettes[jobKey] or {};
                for paletteName, isSelected in pairs(jobSelectedPalettes) do
                    if isSelected then
                        local storageKey;
                        if jobKey == 'global' then
                            storageKey = 'global';
                        else
                            storageKey = tbarMigration.GetStorageKeyForPalette(jobKey, paletteName);
                        end

                        local paletteBindings = tbarMigration.GetCrossbarPaletteBindings(parsedData, paletteName);
                        if paletteBindings then
                            local paletteCount = 0;
                            for comboMode, slots in pairs(paletteBindings) do
                                for slotIndex, binding in pairs(slots) do
                                    local convertedAction = tbarMigration.ConvertBinding(binding);
                                    if convertedAction then
                                        local conflictKey = string.format('crossbar:%s:%d:%s', comboMode, slotIndex, storageKey);
                                        local resolution = wizardState.conflictResolutions[conflictKey];

                                        if resolution == 'keep' then
                                            results.skipped = results.skipped + 1;
                                        else
                                            -- (Slots already cleared above, just import)
                                            local success = tbarMigration.ImportCrossbarBinding(comboMode, slotIndex, convertedAction, storageKey);
                                            if success then
                                                results.crossbarImported = results.crossbarImported + 1;
                                                paletteCount = paletteCount + 1;
                                            end
                                        end
                                    end
                                end
                            end

                            -- Track what was imported for crossbar
                            if paletteCount > 0 then
                                -- Register the palette with the palette system
                                local jobId = tbarMigration.GetJobId(jobKey);
                                if jobId then
                                    tbarMigration.RegisterImportedPalette(paletteName, jobId, true);
                                end

                                local isPetPalette = tbarMigration.IsPetPalette(paletteName);
                                local targetDesc = isPetPalette
                                    and string.format('%s pet palette', paletteName)
                                    or (paletteName == 'Base' and 'crossbar base' or string.format('crossbar "%s"', paletteName));
                                table.insert(results.paletteDetails, {
                                    job = jobKey,
                                    palette = paletteName,
                                    count = paletteCount,
                                    storageKey = storageKey,
                                    isCrossbar = true,
                                    description = string.format('%s %s: %d bindings', jobKey, targetDesc, paletteCount),
                                });
                            end
                        else
                            table.insert(results.errors, 'Crossbar palette "' .. paletteName .. '" not found for ' .. jobKey);
                        end
                    end
                end
            end
        end
    end

    -- Save settings to disk
    if results.hotbarImported > 0 or results.crossbarImported > 0 then
        SaveSettingsToDisk();

        -- Activate imported palettes for the current job
        -- This ensures the imported bindings are immediately visible
        local player = AshitaCore:GetMemoryManager():GetPlayer();
        local currentJobId = player and player:GetMainJob() or 1;

        if results.crossbarImported > 0 then
            -- Activate the crossbar palette (Default for Base import)
            local crossbarPalettes = palette.GetCrossbarAvailablePalettes(currentJobId, 0);
            if #crossbarPalettes > 0 then
                -- Prefer 'Default' palette if it exists, otherwise use first available
                local paletteToActivate = nil;
                for _, name in ipairs(crossbarPalettes) do
                    if name == tbarMigration.DEFAULT_PALETTE_NAME then
                        paletteToActivate = name;
                        break;
                    end
                end
                paletteToActivate = paletteToActivate or crossbarPalettes[1];
                palette.SetActivePaletteForCombo('L2', paletteToActivate);
            end
        end

        if results.hotbarImported > 0 then
            -- Activate the hotbar palette
            local hotbarPalettes = palette.GetAvailablePalettes(1, currentJobId, 0);
            if #hotbarPalettes > 0 then
                -- Prefer 'Default' palette if it exists, otherwise use first available
                local paletteToActivate = nil;
                for _, name in ipairs(hotbarPalettes) do
                    if name == tbarMigration.DEFAULT_PALETTE_NAME then
                        paletteToActivate = name;
                        break;
                    end
                end
                paletteToActivate = paletteToActivate or hotbarPalettes[1];
                palette.SetActivePalette(1, paletteToActivate, currentJobId);
            end
        end
    end

    return results;
end

-- ============================================
-- Step Drawing Functions
-- ============================================

local function DrawStep1Detection()
    imgui.TextColored(COLORS.gold, 'Scanning for tHotBar/tCrossBar data...');
    imgui.Spacing();

    if not wizardState.detectionData then
        imgui.Text('No data found.');
        return false;  -- Can't proceed
    end

    local data = wizardState.detectionData;
    local hasData = false;

    -- Show tHotBar results
    if data.thotbar.available and #data.thotbar.characters > 0 then
        imgui.TextColored(COLORS.success, 'tHotBar');
        for _, char in ipairs(data.thotbar.characters) do
            imgui.BulletText(char.name);
            local jobStr = char.hasGlobal and 'globals' or '';
            if #char.jobs > 0 then
                if jobStr ~= '' then jobStr = jobStr .. ', '; end
                jobStr = jobStr .. table.concat(char.jobs, ', ');
            end
            if jobStr ~= '' then
                imgui.SameLine();
                imgui.TextColored(COLORS.textDim, '(' .. jobStr .. ')');
            end
        end
        hasData = true;
    else
        imgui.TextColored(COLORS.textDim, 'tHotBar - Not found');
    end

    imgui.Spacing();

    -- Show tCrossBar results
    if data.tcrossbar.available and #data.tcrossbar.characters > 0 then
        imgui.TextColored(COLORS.success, 'tCrossBar');
        for _, char in ipairs(data.tcrossbar.characters) do
            imgui.BulletText(char.name);
            local jobStr = char.hasGlobal and 'globals' or '';
            if #char.jobs > 0 then
                if jobStr ~= '' then jobStr = jobStr .. ', '; end
                jobStr = jobStr .. table.concat(char.jobs, ', ');
            end
            if jobStr ~= '' then
                imgui.SameLine();
                imgui.TextColored(COLORS.textDim, '(' .. jobStr .. ')');
            end
        end
        hasData = true;
    else
        imgui.TextColored(COLORS.textDim, 'tCrossBar - Not found');
    end

    if not hasData then
        imgui.Spacing();
        imgui.TextColored(COLORS.warning, 'No tHotBar or tCrossBar data found.');
        imgui.Text('Make sure you have used these addons before.');
    end

    return hasData;
end

-- Scan available palettes for a job when it's selected
-- Returns array of palette names and initializes selectedPalettes with all selected
local function ScanPalettesForJob(charData, job)
    if not charData or not charData.thotbarPath then return {}; end

    local fileName = (job == 'global') and 'globals.lua' or (job .. '.lua');
    local filePath = charData.thotbarPath .. '\\' .. fileName;
    local parsedData = tbarMigration.ParseHotBarBindings(filePath);

    if parsedData then
        local names = tbarMigration.GetPaletteNames(parsedData);
        -- Initialize selectedPalettes with all palettes selected by default
        if not wizardState.selectedPalettes[job] then
            wizardState.selectedPalettes[job] = {};
        end
        for _, name in ipairs(names) do
            if wizardState.selectedPalettes[job][name] == nil then
                wizardState.selectedPalettes[job][name] = true;  -- Default to selected
            end
        end
        return names;
    end
    return {};
end

-- Helper to count selected palettes for a job
local function CountSelectedPalettes(job)
    local count = 0;
    local palettes = wizardState.selectedPalettes[job] or {};
    for _, selected in pairs(palettes) do
        if selected then count = count + 1; end
    end
    return count;
end

-- Scan available crossbar palettes for a job when it's selected
-- Returns array of palette names and initializes selectedCrossbarPalettes with all selected
local function ScanCrossbarPalettesForJob(charData, job)
    if not charData or not charData.tcrossbarPath then return {}; end

    local fileName = (job == 'global') and 'globals.lua' or (job .. '.lua');
    local filePath = charData.tcrossbarPath .. '\\' .. fileName;
    local parsedData = tbarMigration.ParseCrossBarBindings(filePath);

    if parsedData then
        local names = tbarMigration.GetCrossbarPaletteNames(parsedData);
        -- Initialize selectedCrossbarPalettes with all palettes selected by default
        if not wizardState.selectedCrossbarPalettes[job] then
            wizardState.selectedCrossbarPalettes[job] = {};
        end
        for _, name in ipairs(names) do
            if wizardState.selectedCrossbarPalettes[job][name] == nil then
                wizardState.selectedCrossbarPalettes[job][name] = true;  -- Default to selected
            end
        end
        return names;
    end
    return {};
end

-- Helper to count selected crossbar palettes for a job
local function CountSelectedCrossbarPalettes(job)
    local count = 0;
    local palettes = wizardState.selectedCrossbarPalettes[job] or {};
    for _, selected in pairs(palettes) do
        if selected then count = count + 1; end
    end
    return count;
end

-- Helper to get palette display label (shows pet icon if applicable)
local function GetPaletteDisplayLabel(paletteName)
    if tbarMigration.IsPetPalette(paletteName) then
        return paletteName .. ' (pet)';
    end
    return paletteName;
end

local function DrawStep2Selection()
    local data = wizardState.detectionData;
    if not data then return false; end

    -- Build combined character list
    local characters = {};
    local charMap = {};

    for _, char in ipairs(data.thotbar.characters or {}) do
        if not charMap[char.name] then
            charMap[char.name] = {
                name = char.name,
                thotbarPath = char.path,
                thotbarJobs = char.jobs,
                thotbarHasGlobal = char.hasGlobal,
            };
        else
            charMap[char.name].thotbarPath = char.path;
            charMap[char.name].thotbarJobs = char.jobs;
            charMap[char.name].thotbarHasGlobal = char.hasGlobal;
        end
    end

    for _, char in ipairs(data.tcrossbar.characters or {}) do
        if not charMap[char.name] then
            charMap[char.name] = {
                name = char.name,
                tcrossbarPath = char.path,
                tcrossbarJobs = char.jobs,
                tcrossbarHasGlobal = char.hasGlobal,
            };
        else
            charMap[char.name].tcrossbarPath = char.path;
            charMap[char.name].tcrossbarJobs = char.jobs;
            charMap[char.name].tcrossbarHasGlobal = char.hasGlobal;
        end
    end

    for _, charData in pairs(charMap) do
        table.insert(characters, charData);
    end

    -- Character dropdown
    imgui.Text('Character:');
    imgui.SameLine();
    imgui.SetNextItemWidth(250);

    local currentName = wizardState.selectedCharacter and wizardState.selectedCharacter.name or 'Select...';
    if imgui.BeginCombo('##charSelect', currentName) then
        for _, charData in ipairs(characters) do
            local isSelected = wizardState.selectedCharacter and wizardState.selectedCharacter.name == charData.name;
            if imgui.Selectable(charData.name, isSelected) then
                wizardState.selectedCharacter = charData;
                -- Reset job and palette selections
                wizardState.selectedJobs = {};
                wizardState.selectedPalettes = {};
                wizardState.availablePalettes = {};
                wizardState.selectedCrossbarPalettes = {};
                wizardState.availableCrossbarPalettes = {};
                wizardState.importGlobal = charData.thotbarHasGlobal or charData.tcrossbarHasGlobal;

                -- Scan palettes for global if available (hotbar)
                if charData.thotbarHasGlobal then
                    local palettes = ScanPalettesForJob(charData, 'global');
                    wizardState.availablePalettes['global'] = palettes;
                    if #palettes > 0 then
                        wizardState.selectedPalettes['global'] = palettes[1];
                    end
                end

                -- Scan crossbar palettes for global if available
                if charData.tcrossbarHasGlobal then
                    local palettes = ScanCrossbarPalettesForJob(charData, 'global');
                    wizardState.availableCrossbarPalettes['global'] = palettes;
                end
            end
        end
        imgui.EndCombo();
    end

    if not wizardState.selectedCharacter then
        return false;
    end

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Import what
    imgui.Text('Import:');
    local charData = wizardState.selectedCharacter;

    if charData.thotbarPath then
        local hotbarVal = { wizardState.importHotbar };
        if imgui.Checkbox('Hotbar bindings (tHotBar)', hotbarVal) then
            wizardState.importHotbar = hotbarVal[1];
        end
    end

    if charData.tcrossbarPath then
        local crossbarVal = { wizardState.importCrossbar };
        if imgui.Checkbox('Crossbar bindings (tCrossBar)', crossbarVal) then
            wizardState.importCrossbar = crossbarVal[1];
        end
    end

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Job selection with palette dropdown
    imgui.Text('Jobs to import:');
    imgui.Spacing();

    -- Scrollable job list
    imgui.BeginChild('jobList', {0, 150}, true);

    local hasGlobal = charData.thotbarHasGlobal or charData.tcrossbarHasGlobal;
    if hasGlobal then
        local globalVal = { wizardState.importGlobal };
        if imgui.Checkbox('Global##jobGlobal', globalVal) then
            wizardState.importGlobal = globalVal[1];
        end

        -- Palette multi-select for global (collapsible)
        if wizardState.importGlobal and wizardState.availablePalettes['global'] and #wizardState.availablePalettes['global'] > 1 then
            imgui.SameLine();
            local selectedCount = CountSelectedPalettes('global');
            local totalCount = #wizardState.availablePalettes['global'];
            imgui.TextColored(COLORS.textDim, string.format('(%d/%d palettes)', selectedCount, totalCount));
        end
    end

    local allJobs = GetAllJobs();

    for _, job in ipairs(allJobs) do
        if wizardState.selectedJobs[job] == nil then
            wizardState.selectedJobs[job] = true;  -- Default selected

            -- Scan palettes for this job (this also initializes selectedPalettes)
            local palettes = ScanPalettesForJob(charData, job);
            wizardState.availablePalettes[job] = palettes;

            -- Also scan crossbar palettes for this job
            local crossbarPalettes = ScanCrossbarPalettesForJob(charData, job);
            wizardState.availableCrossbarPalettes[job] = crossbarPalettes;
        end

        local jobVal = { wizardState.selectedJobs[job] };
        if imgui.Checkbox(job .. '##job' .. job, jobVal) then
            wizardState.selectedJobs[job] = jobVal[1];
        end

        -- Show palette count for this job (hotbar + crossbar combined)
        if wizardState.selectedJobs[job] then
            local hbPalettes = wizardState.availablePalettes[job] or {};
            local cbPalettes = wizardState.availableCrossbarPalettes[job] or {};
            local hasMultiple = #hbPalettes > 1 or #cbPalettes > 1;
            if hasMultiple then
                imgui.SameLine();
                local hbCount = CountSelectedPalettes(job);
                local cbCount = CountSelectedCrossbarPalettes(job);
                imgui.TextColored(COLORS.textDim, string.format('(hb:%d/%d, cb:%d/%d)', hbCount, #hbPalettes, cbCount, #cbPalettes));
            end
        end
    end

    imgui.EndChild();

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Palette selection section (show details for jobs with multiple palettes)
    local hasMultiplePalettes = false;
    for _, job in ipairs(allJobs) do
        if wizardState.selectedJobs[job] and wizardState.availablePalettes[job] and #wizardState.availablePalettes[job] > 1 then
            hasMultiplePalettes = true;
            break;
        end
    end

    if hasMultiplePalettes then
        imgui.TextColored(COLORS.gold, 'Palette Selection:');
        imgui.TextColored(COLORS.textDim, 'Select which palettes to import for each job.');
        imgui.Spacing();

        -- Bulk actions
        if imgui.Button('Select All Palettes') then
            for job, palettes in pairs(wizardState.availablePalettes) do
                if wizardState.selectedJobs[job] or (job == 'global' and wizardState.importGlobal) then
                    for _, paletteName in ipairs(palettes) do
                        if not wizardState.selectedPalettes[job] then
                            wizardState.selectedPalettes[job] = {};
                        end
                        wizardState.selectedPalettes[job][paletteName] = true;
                    end
                end
            end
        end
        imgui.SameLine();
        if imgui.Button('Select Base Only') then
            for job, palettes in pairs(wizardState.availablePalettes) do
                if wizardState.selectedJobs[job] or (job == 'global' and wizardState.importGlobal) then
                    if not wizardState.selectedPalettes[job] then
                        wizardState.selectedPalettes[job] = {};
                    end
                    for _, paletteName in ipairs(palettes) do
                        wizardState.selectedPalettes[job][paletteName] = (paletteName == 'Base');
                    end
                end
            end
        end

        imgui.Spacing();

        -- Per-job palette checkboxes (in a scrollable child region)
        imgui.BeginChild('paletteList', {0, 150}, true);

        -- Global palettes
        if wizardState.importGlobal and wizardState.availablePalettes['global'] and #wizardState.availablePalettes['global'] > 1 then
            if imgui.TreeNode('Global##paletteTree') then
                for _, paletteName in ipairs(wizardState.availablePalettes['global']) do
                    local isSelected = wizardState.selectedPalettes['global'] and wizardState.selectedPalettes['global'][paletteName] or false;
                    local val = { isSelected };
                    if imgui.Checkbox(GetPaletteDisplayLabel(paletteName) .. '##globalPal' .. paletteName, val) then
                        if not wizardState.selectedPalettes['global'] then
                            wizardState.selectedPalettes['global'] = {};
                        end
                        wizardState.selectedPalettes['global'][paletteName] = val[1];
                    end
                end
                imgui.TreePop();
            end
        end

        -- Job palettes
        for _, job in ipairs(allJobs) do
            if wizardState.selectedJobs[job] and wizardState.availablePalettes[job] and #wizardState.availablePalettes[job] > 1 then
                local selectedCount = CountSelectedPalettes(job);
                local totalCount = #wizardState.availablePalettes[job];
                local treeLabel = string.format('%s (%d/%d)##paletteTree', job, selectedCount, totalCount);

                if imgui.TreeNode(treeLabel) then
                    for _, paletteName in ipairs(wizardState.availablePalettes[job]) do
                        local isSelected = wizardState.selectedPalettes[job] and wizardState.selectedPalettes[job][paletteName] or false;
                        local val = { isSelected };
                        if imgui.Checkbox(GetPaletteDisplayLabel(paletteName) .. '##' .. job .. 'Pal' .. paletteName, val) then
                            if not wizardState.selectedPalettes[job] then
                                wizardState.selectedPalettes[job] = {};
                            end
                            wizardState.selectedPalettes[job][paletteName] = val[1];
                        end
                    end
                    imgui.TreePop();
                end
            end
        end

        imgui.EndChild();
    end

    -- Check if anything is selected (both jobs AND at least one palette per job)
    local hasSelection = false;
    local hasPalettes = false;

    -- Check global
    if wizardState.importGlobal then
        hasSelection = true;
        -- Check if global has palettes selected (or only has one palette which is auto-selected)
        local globalPalettes = wizardState.availablePalettes['global'] or {};
        if #globalPalettes <= 1 then
            hasPalettes = true;  -- Single palette jobs are always considered selected
        else
            for _, isSelected in pairs(wizardState.selectedPalettes['global'] or {}) do
                if isSelected then hasPalettes = true; break; end
            end
        end
    end

    -- Check jobs
    for job, selected in pairs(wizardState.selectedJobs) do
        if selected then
            hasSelection = true;
            local jobPalettes = wizardState.availablePalettes[job] or {};
            if #jobPalettes <= 1 then
                hasPalettes = true;  -- Single palette jobs are always considered selected
            else
                for _, isSelected in pairs(wizardState.selectedPalettes[job] or {}) do
                    if isSelected then hasPalettes = true; break; end
                end
            end
        end
    end

    -- Also ensure at least one palette is selected for jobs with multiple palettes
    if hasSelection and not hasPalettes then
        imgui.Spacing();
        imgui.TextColored(COLORS.warning, 'Please select at least one palette to import.');
    end

    return hasSelection and hasPalettes and (wizardState.importHotbar or wizardState.importCrossbar);
end

local function DrawStep3Conflicts()
    -- Build conflict list if not already done
    if #wizardState.conflicts == 0 then
        wizardState.conflicts = BuildConflictList();

        -- Default all to 'replace'
        for _, conflict in ipairs(wizardState.conflicts) do
            if wizardState.conflictResolutions[conflict.key] == nil then
                wizardState.conflictResolutions[conflict.key] = 'replace';
            end
        end
    end

    if #wizardState.conflicts == 0 then
        imgui.TextColored(COLORS.success, 'No conflicts detected!');
        imgui.Text('All bindings can be imported without overwriting existing data.');
        return true;
    end

    imgui.TextColored(COLORS.warning, string.format('%d conflicts found', #wizardState.conflicts));
    imgui.Text('Choose how to handle each conflict:');
    imgui.Spacing();

    -- Bulk actions
    if imgui.Button('Keep All Existing') then
        for _, conflict in ipairs(wizardState.conflicts) do
            wizardState.conflictResolutions[conflict.key] = 'keep';
        end
    end
    imgui.SameLine();
    if imgui.Button('Replace All') then
        for _, conflict in ipairs(wizardState.conflicts) do
            wizardState.conflictResolutions[conflict.key] = 'replace';
        end
    end

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Scrollable conflict list
    imgui.BeginChild('conflictList', {0, 200}, true);

    for _, conflict in ipairs(wizardState.conflicts) do
        local resolution = wizardState.conflictResolutions[conflict.key] or 'replace';

        -- Conflict header
        local headerText;
        if conflict.type == 'hotbar' then
            headerText = string.format('Hotbar %d, Slot %d (%s)', conflict.barIndex, conflict.slotIndex, conflict.jobKey);
        else
            headerText = string.format('Crossbar %s, Slot %d (%s)', conflict.comboMode, conflict.slotIndex, conflict.jobKey);
        end

        imgui.Text(headerText);
        imgui.SameLine(250);
        imgui.TextColored(COLORS.gold, conflict.newLabel);

        -- Radio buttons
        imgui.SameLine(400);
        if imgui.RadioButton('Keep##' .. conflict.key, resolution == 'keep') then
            wizardState.conflictResolutions[conflict.key] = 'keep';
        end
        imgui.SameLine();
        if imgui.RadioButton('Replace##' .. conflict.key, resolution == 'replace') then
            wizardState.conflictResolutions[conflict.key] = 'replace';
        end
    end

    imgui.EndChild();

    return true;
end

local function DrawStep4Confirm()
    if wizardState.importResults then
        -- Show results
        imgui.TextColored(COLORS.success, 'Import Complete!');
        imgui.Spacing();

        local results = wizardState.importResults;
        imgui.BulletText(string.format('Hotbar bindings imported: %d', results.hotbarImported));
        imgui.BulletText(string.format('Crossbar bindings imported: %d', results.crossbarImported));
        if results.skipped > 0 then
            imgui.BulletText(string.format('Skipped (kept existing): %d', results.skipped));
        end

        -- Show palette details if any
        if results.paletteDetails and #results.paletteDetails > 0 then
            imgui.Spacing();
            imgui.TextColored(COLORS.gold, 'Palette Import Details:');
            imgui.BeginChild('paletteResults', {0, 100}, true);
            for _, detail in ipairs(results.paletteDetails) do
                imgui.BulletText(detail.description);
            end
            imgui.EndChild();
        end

        if #results.errors > 0 then
            imgui.Spacing();
            imgui.TextColored(COLORS.error, 'Errors:');
            for _, err in ipairs(results.errors) do
                imgui.BulletText(err);
            end
        end

        return true;
    end

    -- Show summary before import
    imgui.TextColored(COLORS.gold, 'Ready to Import');
    imgui.Spacing();

    local charData = GetSelectedCharData();
    if charData then
        imgui.BulletText('Character: ' .. charData.name);
    end

    if wizardState.importHotbar then
        imgui.BulletText('Hotbar bindings: Yes');
    end
    if wizardState.importCrossbar then
        imgui.BulletText('Crossbar bindings: Yes');
    end

    local jobList = {};
    if wizardState.importGlobal then
        table.insert(jobList, 'Global');
    end
    for job, selected in pairs(wizardState.selectedJobs) do
        if selected then
            table.insert(jobList, job);
        end
    end
    imgui.BulletText('Jobs: ' .. table.concat(jobList, ', '));

    -- Show palettes being imported
    imgui.Spacing();
    imgui.TextColored(COLORS.gold, 'Palettes to import:');

    local totalPalettes = 0;
    local petPalettes = 0;
    local generalPalettes = 0;

    for job, palettes in pairs(wizardState.selectedPalettes) do
        local isJobSelected = (job == 'global' and wizardState.importGlobal) or wizardState.selectedJobs[job];
        if isJobSelected then
            for paletteName, isSelected in pairs(palettes) do
                if isSelected then
                    totalPalettes = totalPalettes + 1;
                    if tbarMigration.IsPetPalette(paletteName) then
                        petPalettes = petPalettes + 1;
                    elseif paletteName ~= 'Base' then
                        generalPalettes = generalPalettes + 1;
                    end
                end
            end
        end
    end

    local paletteDesc = string.format('%d total', totalPalettes);
    if petPalettes > 0 then
        paletteDesc = paletteDesc .. string.format(' (%d pet palettes)', petPalettes);
    end
    if generalPalettes > 0 then
        paletteDesc = paletteDesc .. string.format(' (%d custom palettes)', generalPalettes);
    end
    imgui.BulletText(paletteDesc);

    local keepCount = 0;
    local replaceCount = 0;
    for _, resolution in pairs(wizardState.conflictResolutions) do
        if resolution == 'keep' then
            keepCount = keepCount + 1;
        else
            replaceCount = replaceCount + 1;
        end
    end

    if keepCount > 0 or replaceCount > 0 then
        imgui.Spacing();
        imgui.Text(string.format('Conflicts: %d keep existing, %d replace', keepCount, replaceCount));
    end

    return false;  -- Don't auto-proceed
end

-- ============================================
-- Main Draw Function
-- ============================================

function M.Draw()
    if not wizardState.isOpen then return; end

    -- Style setup
    imgui.PushStyleColor(ImGuiCol_WindowBg, COLORS.bgDark);
    imgui.PushStyleColor(ImGuiCol_TitleBg, COLORS.bgMedium);
    imgui.PushStyleColor(ImGuiCol_TitleBgActive, COLORS.bgMedium);
    imgui.PushStyleColor(ImGuiCol_Border, COLORS.borderDark);
    imgui.PushStyleColor(ImGuiCol_Button, COLORS.bgLight);
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, COLORS.bgLighter);
    imgui.PushStyleColor(ImGuiCol_ButtonActive, COLORS.goldDark);
    imgui.PushStyleColor(ImGuiCol_Header, COLORS.bgLight);
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, COLORS.bgLighter);
    imgui.PushStyleColor(ImGuiCol_FrameBg, COLORS.bgMedium);
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, COLORS.bgLight);
    imgui.PushStyleColor(ImGuiCol_CheckMark, COLORS.gold);

    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {16, 16});
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 6.0);
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {8, 4});
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {8, 6});

    local windowFlags = bit.bor(
        ImGuiWindowFlags_NoCollapse,
        ImGuiWindowFlags_AlwaysAutoResize
    );

    imgui.SetNextWindowSize({500, 0}, ImGuiCond_FirstUseEver);
    local isOpen = { true };

    if imgui.Begin('Import from tHotBar/tCrossBar###migrationWizard', isOpen, windowFlags) then
        -- Step indicator
        local steps = {'Detection', 'Selection', 'Conflicts', 'Import'};
        for i, stepName in ipairs(steps) do
            if i > 1 then
                imgui.SameLine();
                imgui.TextColored(COLORS.textDim, '>');
                imgui.SameLine();
            end

            if i == wizardState.currentStep then
                imgui.TextColored(COLORS.gold, stepName);
            elseif i < wizardState.currentStep then
                imgui.TextColored(COLORS.success, stepName);
            else
                imgui.TextColored(COLORS.textDim, stepName);
            end
        end

        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();

        -- Draw current step
        local canProceed = false;
        if wizardState.currentStep == 1 then
            canProceed = DrawStep1Detection();
        elseif wizardState.currentStep == 2 then
            canProceed = DrawStep2Selection();
        elseif wizardState.currentStep == 3 then
            canProceed = DrawStep3Conflicts();
        elseif wizardState.currentStep == 4 then
            canProceed = DrawStep4Confirm();
        end

        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();

        -- Navigation buttons
        if wizardState.currentStep > 1 and not wizardState.importResults then
            if imgui.Button('< Back', {80, 0}) then
                wizardState.currentStep = wizardState.currentStep - 1;
                if wizardState.currentStep == 2 then
                    -- Reset conflicts when going back to selection
                    wizardState.conflicts = {};
                end
            end
            imgui.SameLine();
        end

        -- Right-align next/import/close buttons
        local buttonWidth = 80;
        local windowWidth = imgui.GetWindowWidth();
        local buttonsWidth = buttonWidth + 8;

        if wizardState.importResults then
            -- Show close button after import
            imgui.SetCursorPosX(windowWidth - buttonWidth - 16);
            if imgui.Button('Close', {buttonWidth, 0}) then
                M.Close();
            end
        elseif wizardState.currentStep == 4 then
            imgui.SetCursorPosX(windowWidth - buttonWidth - 16);
            imgui.PushStyleColor(ImGuiCol_Button, {0.2, 0.5, 0.2, 1.0});
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0.3, 0.6, 0.3, 1.0});
            if imgui.Button('Import', {buttonWidth, 0}) then
                wizardState.importResults = ExecuteImport();
            end
            imgui.PopStyleColor(2);
        elseif canProceed then
            imgui.SetCursorPosX(windowWidth - buttonWidth - 16);
            if imgui.Button('Next >', {buttonWidth, 0}) then
                wizardState.currentStep = wizardState.currentStep + 1;
            end
        end
    end
    imgui.End();

    imgui.PopStyleVar(4);
    imgui.PopStyleColor(12);

    -- Handle window close
    if not isOpen[1] then
        M.Close();
    end
end

return M;
