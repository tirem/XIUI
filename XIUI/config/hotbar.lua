--[[
* XIUI Config Menu - Hotbar Settings
* Contains settings and color settings for Hotbar with per-bar customization
]]--

require('common');
require('handlers.helpers');
local components = require('config.components');
local statusHandler = require('handlers.statushandler');
local imgui = require('imgui');
local data = require('modules.hotbar.data');
local jobs = require('libs.jobs');
local macropalette = require('modules.hotbar.macropalette');

local M = {};

-- Action type options
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

-- Equipment slot options for equip action type
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

-- Target options
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

-- Cached spell/ability/weaponskill lists (refreshed when modal opens)
local cachedSpells = nil;
local cachedAbilities = nil;
local cachedWeaponskills = nil;
local cacheJobId = nil;  -- Track which job the cache is for

-- Get player's known spells for current job
local function GetPlayerSpells()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then return {}; end

    local jobId = player:GetMainJob();
    local jobLevel = player:GetMainJobLevel();
    local resMgr = AshitaCore:GetResourceManager();

    local spells = {};
    -- Iterate through all possible spell IDs
    for spellId = 1, 1024 do
        if player:HasSpell(spellId) then
            local spell = resMgr:GetSpellById(spellId);
            if spell and spell.Name and spell.Name[1] and spell.Name[1] ~= '' then
                -- Check if this job can cast it at current level
                local reqLevel = spell.LevelRequired[jobId + 1] or 0;
                if reqLevel > 0 and reqLevel <= jobLevel then
                    table.insert(spells, {
                        id = spellId,
                        name = spell.Name[1],
                        level = reqLevel,
                    });
                end
            end
        end
    end

    -- Sort by level then name
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

    -- Iterate through ability IDs
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

    -- Sort by name
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

    -- Weaponskill IDs typically range from 1-255
    for wsId = 1, 255 do
        if player:HasWeaponSkill(wsId) then
            local ability = resMgr:GetAbilityById(wsId + 256);  -- WS abilities offset
            if ability and ability.Name and ability.Name[1] and ability.Name[1] ~= '' then
                table.insert(weaponskills, {
                    id = wsId,
                    name = ability.Name[1],
                });
            end
        end
    end

    -- Sort by name
    table.sort(weaponskills, function(a, b)
        return a.name < b.name;
    end);

    return weaponskills;
end

-- Refresh cached lists if needed
local function RefreshCachedLists()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then return; end

    local currentJobId = player:GetMainJob();

    -- Refresh if job changed or not cached
    if cacheJobId ~= currentJobId or not cachedSpells then
        cachedSpells = GetPlayerSpells();
        cachedAbilities = GetPlayerAbilities();
        cachedWeaponskills = GetPlayerWeaponskills();
        cacheJobId = currentJobId;
    end
end

-- Keybind editor modal state
local keybindModal = {
    isOpen = false,
    barIndex = nil,
    configKey = nil,
    selectedSlot = nil,
    -- Edit fields (as single-element arrays for ImGui)
    editActionType = { 1 },      -- Index into ACTION_TYPES
    editAction = { '' },         -- Action name string
    editTarget = { 1 },          -- Index into TARGET_OPTIONS
    editDisplayName = { '' },    -- Slot label string
    editEquipSlot = { 1 },       -- Index into EQUIP_SLOTS (for equip action type)
    editMacroText = { '' },      -- Full macro text (for macro action type)
    -- Search/filter state
    searchFilter = { '' },
};

-- Input buffer sizes
local INPUT_BUFFER_SIZE = 64;

-- Bar type definitions for sub-tabs (Global first, then per-bar)
local BAR_TYPES = {
    { key = 'Global', configKey = 'hotbarGlobal', label = 'Global', isGlobal = true },
    { key = 'Bar1', configKey = 'hotbarBar1', label = 'Bar 1' },
    { key = 'Bar2', configKey = 'hotbarBar2', label = 'Bar 2' },
    { key = 'Bar3', configKey = 'hotbarBar3', label = 'Bar 3' },
    { key = 'Bar4', configKey = 'hotbarBar4', label = 'Bar 4' },
    { key = 'Bar5', configKey = 'hotbarBar5', label = 'Bar 5' },
    { key = 'Bar6', configKey = 'hotbarBar6', label = 'Bar 6' },
};

-- Copy settings between bars
local function CopyBarSettings(sourceKey, targetKey)
    local source = gConfig[sourceKey];
    local target = gConfig[targetKey];
    if source and target and type(source) == 'table' and type(target) == 'table' then
        for k, v in pairs(source) do
            -- Don't copy keybinds (per-job data)
            if k ~= 'keybinds' then
                if type(v) == 'table' then
                    target[k] = deep_copy_table(v);
                else
                    target[k] = v;
                end
            end
        end
        SaveSettingsOnly();
        DeferredUpdateVisuals();
    end
end

-- Draw copy settings buttons
local function DrawBarCopyButtons(currentConfigKey, settingsType)
    if components.CollapsingSectionWarning('Copy Settings##' .. currentConfigKey .. settingsType) then
        imgui.TextColored({0.7, 0.7, 0.7, 1.0}, 'Copy ' .. settingsType .. ' from:');
        local first = true;
        for _, barType in ipairs(BAR_TYPES) do
            if barType.configKey ~= currentConfigKey then
                if not first then
                    imgui.SameLine();
                end
                first = false;
                if imgui.Button(barType.label .. '##copy' .. currentConfigKey .. settingsType) then
                    CopyBarSettings(barType.configKey, currentConfigKey);
                end
            end
        end
    end
end

-- ============================================
-- Keybind Editor Modal Functions
-- ============================================

-- Get slot actions for a bar and job
local function GetSlotActions(configKey, jobId)
    local barSettings = gConfig[configKey];
    if not barSettings then return nil; end
    if not barSettings.slotActions then return nil; end
    return barSettings.slotActions[jobId];
end

-- Save slot action for a slot
local function SaveSlotAction(configKey, jobId, slotIndex, actionData)
    local barSettings = gConfig[configKey];
    if not barSettings then return; end

    -- Initialize slotActions structure if needed
    if not barSettings.slotActions then
        barSettings.slotActions = {};
    end
    if not barSettings.slotActions[jobId] then
        barSettings.slotActions[jobId] = {};
    end

    barSettings.slotActions[jobId][slotIndex] = actionData;
    SaveSettingsOnly();

    -- Reload keybinds in data module
    data.currentKeybinds = nil;
end

-- Clear slot action for a slot
local function ClearSlotAction(configKey, jobId, slotIndex)
    local barSettings = gConfig[configKey];
    if not barSettings then return; end

    -- Initialize slotActions structure if needed
    if not barSettings.slotActions then
        barSettings.slotActions = {};
    end
    if not barSettings.slotActions[jobId] then
        barSettings.slotActions[jobId] = {};
    end

    -- Use "cleared" marker to override default keybinds from lua files
    barSettings.slotActions[jobId][slotIndex] = { cleared = true };
    SaveSettingsOnly();

    -- Reload keybinds in data module
    data.currentKeybinds = nil;
end

-- Get keybind display text for modal
local function GetKeybindDisplayText(barIndex, slotIndex)
    return data.GetKeybindDisplay(barIndex, slotIndex);
end

-- Find index of value in array
local function FindIndex(array, value)
    for i, v in ipairs(array) do
        if v == value then return i; end
    end
    return 1;
end

-- Load keybind data into edit fields
local function LoadKeybindToEditFields(bind)
    if bind then
        keybindModal.editActionType[1] = FindIndex(ACTION_TYPES, bind.actionType or 'ma');
        keybindModal.editAction[1] = bind.action or '';
        keybindModal.editTarget[1] = FindIndex(TARGET_OPTIONS, bind.target or 'me');
        keybindModal.editDisplayName[1] = bind.displayName or bind.action or '';
        keybindModal.editEquipSlot[1] = FindIndex(EQUIP_SLOTS, bind.equipSlot or 'main');
        keybindModal.editMacroText[1] = bind.macroText or '';
    else
        keybindModal.editActionType[1] = 1;
        keybindModal.editAction[1] = '';
        keybindModal.editTarget[1] = 1;
        keybindModal.editDisplayName[1] = '';
        keybindModal.editEquipSlot[1] = 1;
        keybindModal.editMacroText[1] = '';
    end
    keybindModal.searchFilter[1] = '';
end

-- Open keybind modal for a bar
local function OpenKeybindModal(barIndex, configKey)
    keybindModal.isOpen = true;
    keybindModal.barIndex = barIndex;
    keybindModal.configKey = configKey;
    keybindModal.selectedSlot = nil;
    LoadKeybindToEditFields(nil);

    -- Refresh spell/ability/weaponskill caches
    RefreshCachedLists();
end

-- Close keybind modal
local function CloseKeybindModal()
    keybindModal.isOpen = false;
    keybindModal.barIndex = nil;
    keybindModal.configKey = nil;
    keybindModal.selectedSlot = nil;
end

-- Check if keybind modal is open (exported for use in display.lua)
function M.IsKeybindModalOpen()
    return keybindModal.isOpen;
end

-- Draw slot grid for keybind editor
local function DrawSlotGrid(barIndex, barSettings)
    local slots = barSettings.slots or 12;
    local columns = barSettings.columns or 12;
    local rows = barSettings.rows or 1;

    local buttonSize = 40;
    local buttonPadding = 4;

    imgui.Text('Click a slot to edit:');
    imgui.Spacing();

    local slotIndex = 1;
    for row = 1, rows do
        for col = 1, columns do
            if slotIndex <= slots then
                local keybindText = GetKeybindDisplayText(barIndex, slotIndex);
                local bind = data.GetKeybindForSlot(barIndex, slotIndex);
                local hasAction = bind ~= nil;

                -- Style based on selection and action state
                local isSelected = keybindModal.selectedSlot == slotIndex;
                if isSelected then
                    imgui.PushStyleColor(ImGuiCol_Button, {0.3, 0.5, 0.8, 1.0});
                    imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0.4, 0.6, 0.9, 1.0});
                elseif hasAction then
                    imgui.PushStyleColor(ImGuiCol_Button, {0.2, 0.4, 0.3, 1.0});
                    imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0.3, 0.5, 0.4, 1.0});
                else
                    imgui.PushStyleColor(ImGuiCol_Button, {0.15, 0.15, 0.15, 1.0});
                    imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0.25, 0.25, 0.25, 1.0});
                end

                local buttonLabel = string.format('%s##slot%d', keybindText, slotIndex);
                if imgui.Button(buttonLabel, {buttonSize, buttonSize}) then
                    keybindModal.selectedSlot = slotIndex;
                    LoadKeybindToEditFields(bind);
                end

                imgui.PopStyleColor(2);

                -- Tooltip with action info
                if imgui.IsItemHovered() then
                    imgui.BeginTooltip();
                    imgui.Text(string.format('Slot %d (%s)', slotIndex, keybindText));
                    if bind then
                        imgui.Text(string.format('Action: %s', bind.action or 'None'));
                        imgui.Text(string.format('Type: %s', bind.actionType or ''));
                        imgui.Text(string.format('Target: <%s>', bind.target or ''));
                    else
                        imgui.TextColored({0.5, 0.5, 0.5, 1.0}, 'Empty');
                    end
                    imgui.EndTooltip();
                end

                if col < columns and slotIndex < slots then
                    imgui.SameLine(0, buttonPadding);
                end
            end
            slotIndex = slotIndex + 1;
        end
    end
end

-- Draw a searchable dropdown combo box
local function DrawSearchableCombo(label, items, searchFilter, onSelect, currentValue)
    local displayText = currentValue ~= '' and currentValue or 'Select...';

    imgui.SetNextItemWidth(250);
    if imgui.BeginCombo(label, displayText) then
        -- Search input at top of dropdown
        imgui.SetNextItemWidth(230);
        imgui.InputText('##search' .. label, searchFilter, INPUT_BUFFER_SIZE);

        imgui.Separator();

        local filter = searchFilter[1]:lower();
        local matchCount = 0;

        for _, item in ipairs(items) do
            local itemName = item.name or '';
            if filter == '' or itemName:lower():find(filter, 1, true) then
                matchCount = matchCount + 1;
                local itemLabel = item.level and string.format('[%d] %s', item.level, itemName) or itemName;
                local isSelected = currentValue == itemName;
                if imgui.Selectable(itemLabel .. '##item' .. (item.id or matchCount), isSelected) then
                    onSelect(item);
                    searchFilter[1] = '';  -- Clear search after selection
                end
            end
        end

        if matchCount == 0 then
            imgui.TextColored({0.5, 0.5, 0.5, 1.0}, 'No matches');
        end

        imgui.EndCombo();
    end
end

-- Draw slot editor panel
local function DrawSlotEditor(barIndex, slotIndex, configKey)
    local keybindText = GetKeybindDisplayText(barIndex, slotIndex);
    local jobId = data.jobId or 1;
    local jobName = jobs[jobId] or 'Unknown';

    imgui.Separator();
    imgui.Spacing();
    imgui.TextColored({0.9, 0.8, 0.4, 1.0}, string.format('Editing Slot %d (%s) - Job: %s', slotIndex, keybindText, jobName));
    imgui.Spacing();

    -- Action Type dropdown
    imgui.Text('Action Type:');
    imgui.SetNextItemWidth(200);
    local currentActionType = ACTION_TYPES[keybindModal.editActionType[1]];
    if imgui.BeginCombo('##actionType', ACTION_TYPE_LABELS[currentActionType] or 'Select...') then
        for i, actionType in ipairs(ACTION_TYPES) do
            local isSelected = keybindModal.editActionType[1] == i;
            if imgui.Selectable(ACTION_TYPE_LABELS[actionType], isSelected) then
                keybindModal.editActionType[1] = i;
                -- Clear action when type changes
                keybindModal.editAction[1] = '';
                keybindModal.searchFilter[1] = '';
            end
        end
        imgui.EndCombo();
    end

    imgui.Spacing();

    -- Show different fields based on action type
    if currentActionType == 'ma' then
        -- Spell: Show searchable dropdown
        imgui.Text('Spell:');
        if cachedSpells and #cachedSpells > 0 then
            DrawSearchableCombo('##spellCombo', cachedSpells, keybindModal.searchFilter, function(spell)
                keybindModal.editAction[1] = spell.name;
                if keybindModal.editDisplayName[1] == '' then
                    keybindModal.editDisplayName[1] = spell.name;
                end
            end, keybindModal.editAction[1]);
        else
            imgui.TextColored({0.5, 0.5, 0.5, 1.0}, 'No spells available for this job');
        end

        -- Target dropdown
        imgui.Spacing();
        imgui.Text('Target:');
        imgui.SetNextItemWidth(200);
        if imgui.BeginCombo('##targetType', TARGET_LABELS[TARGET_OPTIONS[keybindModal.editTarget[1]]] or 'Select...') then
            for i, target in ipairs(TARGET_OPTIONS) do
                local isSelected = keybindModal.editTarget[1] == i;
                if imgui.Selectable(TARGET_LABELS[target], isSelected) then
                    keybindModal.editTarget[1] = i;
                end
            end
            imgui.EndCombo();
        end

    elseif currentActionType == 'ja' then
        -- Ability: Show searchable dropdown
        imgui.Text('Ability:');
        if cachedAbilities and #cachedAbilities > 0 then
            DrawSearchableCombo('##abilityCombo', cachedAbilities, keybindModal.searchFilter, function(ability)
                keybindModal.editAction[1] = ability.name;
                if keybindModal.editDisplayName[1] == '' then
                    keybindModal.editDisplayName[1] = ability.name;
                end
            end, keybindModal.editAction[1]);
        else
            imgui.TextColored({0.5, 0.5, 0.5, 1.0}, 'No abilities available');
        end

        -- Target dropdown
        imgui.Spacing();
        imgui.Text('Target:');
        imgui.SetNextItemWidth(200);
        if imgui.BeginCombo('##targetType', TARGET_LABELS[TARGET_OPTIONS[keybindModal.editTarget[1]]] or 'Select...') then
            for i, target in ipairs(TARGET_OPTIONS) do
                local isSelected = keybindModal.editTarget[1] == i;
                if imgui.Selectable(TARGET_LABELS[target], isSelected) then
                    keybindModal.editTarget[1] = i;
                end
            end
            imgui.EndCombo();
        end

    elseif currentActionType == 'ws' then
        -- Weaponskill: Show searchable dropdown
        imgui.Text('Weaponskill:');
        if cachedWeaponskills and #cachedWeaponskills > 0 then
            DrawSearchableCombo('##wsCombo', cachedWeaponskills, keybindModal.searchFilter, function(ws)
                keybindModal.editAction[1] = ws.name;
                if keybindModal.editDisplayName[1] == '' then
                    keybindModal.editDisplayName[1] = ws.name;
                end
            end, keybindModal.editAction[1]);
        else
            imgui.TextColored({0.5, 0.5, 0.5, 1.0}, 'No weaponskills available');
        end

        -- Target dropdown (usually <t> for WS)
        imgui.Spacing();
        imgui.Text('Target:');
        imgui.SetNextItemWidth(200);
        if imgui.BeginCombo('##targetType', TARGET_LABELS[TARGET_OPTIONS[keybindModal.editTarget[1]]] or 'Select...') then
            for i, target in ipairs(TARGET_OPTIONS) do
                local isSelected = keybindModal.editTarget[1] == i;
                if imgui.Selectable(TARGET_LABELS[target], isSelected) then
                    keybindModal.editTarget[1] = i;
                end
            end
            imgui.EndCombo();
        end

    elseif currentActionType == 'item' then
        -- Item: Manual item name input
        imgui.Text('Item Name:');
        imgui.SetNextItemWidth(200);
        imgui.InputText('##itemName', keybindModal.editAction, INPUT_BUFFER_SIZE);
        imgui.ShowHelp('Enter the exact item name to use.');

        -- Target dropdown
        imgui.Spacing();
        imgui.Text('Target:');
        imgui.SetNextItemWidth(200);
        if imgui.BeginCombo('##targetType', TARGET_LABELS[TARGET_OPTIONS[keybindModal.editTarget[1]]] or 'Select...') then
            for i, target in ipairs(TARGET_OPTIONS) do
                local isSelected = keybindModal.editTarget[1] == i;
                if imgui.Selectable(TARGET_LABELS[target], isSelected) then
                    keybindModal.editTarget[1] = i;
                end
            end
            imgui.EndCombo();
        end

    elseif currentActionType == 'equip' then
        -- Equip: Slot dropdown + Item name input
        imgui.Text('Equipment Slot:');
        imgui.SetNextItemWidth(200);
        if imgui.BeginCombo('##equipSlot', EQUIP_SLOT_LABELS[EQUIP_SLOTS[keybindModal.editEquipSlot[1]]] or 'Select...') then
            for i, slot in ipairs(EQUIP_SLOTS) do
                local isSelected = keybindModal.editEquipSlot[1] == i;
                if imgui.Selectable(EQUIP_SLOT_LABELS[slot], isSelected) then
                    keybindModal.editEquipSlot[1] = i;
                end
            end
            imgui.EndCombo();
        end

        imgui.Spacing();
        imgui.Text('Item Name:');
        imgui.SetNextItemWidth(200);
        imgui.InputText('##equipItemName', keybindModal.editAction, INPUT_BUFFER_SIZE);
        imgui.ShowHelp('Enter the exact equipment name to equip.');

    elseif currentActionType == 'macro' then
        -- Macro: Full macro text input
        imgui.Text('Macro Command:');
        imgui.SetNextItemWidth(280);
        imgui.InputText('##macroText', keybindModal.editMacroText, 256);
        imgui.ShowHelp('Enter the full command (e.g., /ma "Cure" <stpc>)');

    elseif currentActionType == 'pet' then
        -- Pet: Pet command input
        imgui.Text('Pet Command:');
        imgui.SetNextItemWidth(200);
        imgui.InputText('##petCommand', keybindModal.editAction, INPUT_BUFFER_SIZE);
        imgui.ShowHelp('Enter pet command name (e.g., "Assault", "Retreat")');

        -- Target dropdown
        imgui.Spacing();
        imgui.Text('Target:');
        imgui.SetNextItemWidth(200);
        if imgui.BeginCombo('##targetType', TARGET_LABELS[TARGET_OPTIONS[keybindModal.editTarget[1]]] or 'Select...') then
            for i, target in ipairs(TARGET_OPTIONS) do
                local isSelected = keybindModal.editTarget[1] == i;
                if imgui.Selectable(TARGET_LABELS[target], isSelected) then
                    keybindModal.editTarget[1] = i;
                end
            end
            imgui.EndCombo();
        end
    end

    -- Slot label input (for all types except macro)
    if currentActionType ~= 'macro' then
        imgui.Spacing();
        imgui.Text('Slot Label:');
        imgui.SetNextItemWidth(200);
        imgui.InputText('##slotLabel', keybindModal.editDisplayName, INPUT_BUFFER_SIZE);
        imgui.ShowHelp('Short label shown on the slot (e.g., "Cure3"). Leave empty to use action name.');
    end

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Action buttons
    if imgui.Button('Save##keybindSave', {80, 0}) then
        local actionType = ACTION_TYPES[keybindModal.editActionType[1]];
        local action = keybindModal.editAction[1];
        local target = TARGET_OPTIONS[keybindModal.editTarget[1]];
        local displayName = keybindModal.editDisplayName[1];
        local equipSlot = EQUIP_SLOTS[keybindModal.editEquipSlot[1]];
        local macroText = keybindModal.editMacroText[1];

        local canSave = false;
        local keybindData = {
            actionType = actionType,
            target = target,
            displayName = displayName,
        };

        if actionType == 'macro' then
            if macroText ~= '' then
                keybindData.macroText = macroText;
                keybindData.action = macroText;
                keybindData.displayName = displayName ~= '' and displayName or 'Macro';
                canSave = true;
            end
        elseif actionType == 'equip' then
            if action ~= '' then
                keybindData.action = action;
                keybindData.equipSlot = equipSlot;
                keybindData.displayName = displayName ~= '' and displayName or action;
                canSave = true;
            end
        else
            if action ~= '' then
                keybindData.action = action;
                keybindData.displayName = displayName ~= '' and displayName or action;
                canSave = true;
            end
        end

        if canSave then
            SaveSlotAction(configKey, jobId, slotIndex, keybindData);
            print(string.format('[XIUI] Saved slot action: Slot %d = %s (%s)', slotIndex, keybindData.action or macroText, actionType));
        end
    end
    imgui.SameLine();

    if imgui.Button('Clear##keybindClear', {80, 0}) then
        ClearSlotAction(configKey, jobId, slotIndex);
        LoadKeybindToEditFields(nil);
        print(string.format('[XIUI] Cleared slot action for slot %d', slotIndex));
    end
end

-- Draw the keybind editor modal (exported for use in hotbar init)
function M.DrawKeybindModal()
    if not keybindModal.isOpen then return; end

    local barIndex = keybindModal.barIndex;
    local configKey = keybindModal.configKey;
    if not barIndex or not configKey then
        CloseKeybindModal();
        return;
    end

    local barSettings = gConfig[configKey];
    if not barSettings then
        CloseKeybindModal();
        return;
    end

    local windowFlags = bit.bor(
        ImGuiWindowFlags_NoCollapse,
        ImGuiWindowFlags_AlwaysAutoResize
    );

    local modalTitle = string.format('Keybind Editor - Bar %d###keybindModal', barIndex);
    local isOpen = { true };

    imgui.SetNextWindowSize({450, 500}, ImGuiCond_FirstUseEver);

    if imgui.Begin(modalTitle, isOpen, windowFlags) then
        -- Job info
        local jobId = data.jobId or 1;
        local jobName = jobs[jobId] or 'Unknown';
        local subjobId = data.subjobId or 0;
        local subjobName = subjobId > 0 and jobs[subjobId] or 'None';

        imgui.TextColored({0.9, 0.8, 0.4, 1.0}, string.format('Editing for: %s', jobName));
        imgui.TextColored({0.6, 0.6, 0.6, 1.0}, 'Actions assigned to slots are saved per-job.');
        imgui.Spacing();

        -- Slot grid
        DrawSlotGrid(barIndex, barSettings);

        -- Slot editor (if slot selected)
        if keybindModal.selectedSlot then
            DrawSlotEditor(barIndex, keybindModal.selectedSlot, configKey);
        else
            imgui.Separator();
            imgui.Spacing();
            imgui.TextColored({0.5, 0.5, 0.5, 1.0}, 'Select a slot above to edit its keybind.');
        end

        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();

        -- Close button
        if imgui.Button('Close##keybindClose', {100, 0}) then
            CloseKeybindModal();
        end
    end
    imgui.End();

    -- Handle window close via X button
    if not isOpen[1] then
        CloseKeybindModal();
    end
end

-- Helper: Draw visual settings (shared between global and per-bar when not using global)
local function DrawVisualSettingsContent(settings, configKey)
    if components.CollapsingSection('Background##' .. configKey, false) then
        local bgThemes = {'-None-', 'Plain', 'Window1', 'Window2', 'Window3', 'Window4', 'Window5', 'Window6', 'Window7', 'Window8'};
        components.DrawPartyComboBox(settings, 'Theme##bg' .. configKey, 'backgroundTheme', bgThemes, DeferredUpdateVisuals);
        imgui.ShowHelp('Select the background window theme.');

        components.DrawPartySlider(settings, 'Background Scale##' .. configKey, 'bgScale', 0.1, 3.0, '%.2f', nil, 1.0);
        imgui.ShowHelp('Scale of the background texture.');

        components.DrawPartySlider(settings, 'Border Scale##' .. configKey, 'borderScale', 0.1, 3.0, '%.2f', nil, 1.0);
        imgui.ShowHelp('Scale of the window borders (Window themes only).');

        components.DrawPartySlider(settings, 'Background Opacity##' .. configKey, 'backgroundOpacity', 0.0, 1.0, '%.2f');
        imgui.ShowHelp('Opacity of the background.');

        components.DrawPartySlider(settings, 'Border Opacity##' .. configKey, 'borderOpacity', 0.0, 1.0, '%.2f');
        imgui.ShowHelp('Opacity of the window borders (Window themes only).');
    end

    if components.CollapsingSection('Slot Settings##' .. configKey, false) then
        components.DrawPartySliderInt(settings, 'Slot Size (px)##' .. configKey, 'slotSize', 16, 64, '%d', nil, 48);
        imgui.ShowHelp('Size of each slot in pixels.');

        components.DrawPartySliderInt(settings, 'Slot X Padding##' .. configKey, 'slotXPadding', 0, 32, '%d', nil, 8);
        imgui.ShowHelp('Horizontal gap between slots.');

        components.DrawPartySliderInt(settings, 'Slot Y Padding##' .. configKey, 'slotYPadding', 0, 32, '%d', nil, 6);
        imgui.ShowHelp('Vertical gap between rows.');

        components.DrawPartyCheckbox(settings, 'Show Slot Frame##' .. configKey, 'showSlotFrame');
        imgui.ShowHelp('Show a frame overlay around each slot.');

        components.DrawPartyCheckbox(settings, 'Show Action Labels##' .. configKey, 'showActionLabels');
        imgui.ShowHelp('Show spell/ability names below slots (outside the bar).');

        if settings.showActionLabels then
            components.DrawPartySliderInt(settings, 'Label X Offset##' .. configKey, 'actionLabelOffsetX', -50, 50, '%d', nil, 0);
            imgui.ShowHelp('Horizontal offset for action labels.');

            components.DrawPartySliderInt(settings, 'Label Y Offset##' .. configKey, 'actionLabelOffsetY', -50, 50, '%d', nil, 0);
            imgui.ShowHelp('Vertical offset for action labels.');
        end

        components.DrawPartyCheckbox(settings, 'Show Hotbar Number##' .. configKey, 'showHotbarNumber');
        imgui.ShowHelp('Show the bar number (1-6) on the left side of the hotbar.');

        components.DrawPartyCheckbox(settings, 'Hide Empty Slots##' .. configKey, 'hideEmptySlots');
        imgui.ShowHelp('Hide slots that have no action assigned. Empty slots are shown when macro palette is open.');
    end

    if components.CollapsingSection('Text Settings##' .. configKey, false) then
        components.DrawPartySliderInt(settings, 'Keybind Font Size##' .. configKey, 'keybindFontSize', 6, 24, '%d', nil, 8);
        imgui.ShowHelp('Font size for keybind labels (e.g., "C1", "A2").');

        components.DrawPartySliderInt(settings, 'Label Font Size##' .. configKey, 'labelFontSize', 6, 24, '%d', nil, 10);
        imgui.ShowHelp('Font size for action labels below buttons.');
    end
end

-- Helper: Draw global visual settings
local function DrawGlobalVisualSettings()
    local globalSettings = gConfig.hotbarGlobal;
    if not globalSettings or type(globalSettings) ~= 'table' then
        imgui.TextColored({1.0, 0.5, 0.5, 1.0}, 'Global settings not initialized.');
        imgui.Text('Please reload the addon to initialize global settings.');
        return;
    end

    imgui.TextColored(components.TAB_STYLE.gold, 'Global Visual Settings');
    imgui.TextColored({0.7, 0.7, 0.7, 1.0}, 'These settings apply to all bars with "Use Global Settings" enabled.');
    imgui.Spacing();

    DrawVisualSettingsContent(globalSettings, 'hotbarGlobal');
end

-- Helper: Draw per-bar visual settings
local function DrawBarVisualSettings(configKey, barLabel)
    local barSettings = gConfig[configKey];
    if not barSettings or type(barSettings) ~= 'table' then
        imgui.TextColored({1.0, 0.5, 0.5, 1.0}, 'Settings not initialized for ' .. barLabel);
        imgui.Text('Please reload the addon to initialize per-bar settings.');
        return;
    end

    -- Enabled checkbox at top
    components.DrawPartyCheckbox(barSettings, 'Enabled##' .. configKey, 'enabled');
    imgui.ShowHelp('Enable or disable this hotbar.');

    -- Use Global Settings checkbox
    components.DrawPartyCheckbox(barSettings, 'Use Global Settings##' .. configKey, 'useGlobalSettings');
    imgui.ShowHelp('When enabled, this bar uses the Global tab settings for visuals. Disable to customize this bar independently.');

    imgui.Spacing();

    -- Layout section (always per-bar)
    if components.CollapsingSection('Layout##' .. configKey, true) then
        -- Rows slider
        local rows = { barSettings.rows or 1 };
        imgui.SetNextItemWidth(150);
        if imgui.SliderInt('Rows##' .. configKey, rows, 1, 12) then
            barSettings.rows = rows[1];
            UpdateUserSettings();
        end
        if imgui.IsItemDeactivatedAfterEdit() then
            SaveSettingsToDisk();
            DeferredUpdateVisuals();
        end
        imgui.ShowHelp('Number of rows (1-12).');

        -- Columns slider
        local columns = { barSettings.columns or 12 };
        imgui.SetNextItemWidth(150);
        if imgui.SliderInt('Columns##' .. configKey, columns, 1, 12) then
            barSettings.columns = columns[1];
            UpdateUserSettings();
        end
        if imgui.IsItemDeactivatedAfterEdit() then
            SaveSettingsToDisk();
            DeferredUpdateVisuals();
        end
        imgui.ShowHelp('Number of columns (1-12).');
    end

    -- Visual settings: Show message if using global, otherwise show per-bar settings
    if barSettings.useGlobalSettings then
        imgui.Spacing();
        imgui.TextColored({0.6, 0.8, 1.0, 1.0}, 'Visual settings are using Global tab settings.');
        imgui.TextColored({0.5, 0.5, 0.5, 1.0}, 'Disable "Use Global Settings" above to customize this bar independently.');
    else
        -- Show per-bar visual settings
        DrawVisualSettingsContent(barSettings, configKey);
    end
end

-- ============================================
-- Crossbar Settings Functions
-- ============================================

local function DrawCrossbarSettings()
    local crossbarSettings = gConfig.hotbarCrossbar;
    if not crossbarSettings then
        imgui.TextColored({1.0, 0.5, 0.5, 1.0}, 'Crossbar settings not initialized.');
        return;
    end

    imgui.TextColored(components.TAB_STYLE.gold, 'Crossbar Settings');
    imgui.TextColored({0.7, 0.7, 0.7, 1.0}, 'Controller-friendly layout with L2/R2 trigger groups.');
    imgui.Spacing();

    -- Layout section
    if components.CollapsingSection('Layout##crossbar', true) then
        components.DrawPartySliderInt(crossbarSettings, 'Slot Size (px)##crossbar', 'slotSize', 32, 64, '%d', nil, 48);
        imgui.ShowHelp('Size of each slot in pixels.');

        components.DrawPartySliderInt(crossbarSettings, 'Slot Gap (Vertical)##crossbar', 'slotGapV', 0, 128, '%d', nil, 4);
        imgui.ShowHelp('Vertical gap between top and bottom slots in each diamond.');

        components.DrawPartySliderInt(crossbarSettings, 'Slot Gap (Horizontal)##crossbar', 'slotGapH', 0, 128, '%d', nil, 4);
        imgui.ShowHelp('Horizontal gap between left and right slots in each diamond.');

        components.DrawPartySliderInt(crossbarSettings, 'Diamond Spacing##crossbar', 'diamondSpacing', 0, 128, '%d', nil, 20);
        imgui.ShowHelp('Horizontal space between D-pad and face button diamonds.');

        components.DrawPartySliderInt(crossbarSettings, 'Group Spacing##crossbar', 'groupSpacing', 0, 128, '%d', nil, 40);
        imgui.ShowHelp('Space between L2 and R2 groups.');

        components.DrawPartyCheckbox(crossbarSettings, 'Show Divider##crossbar', 'showDivider');
        imgui.ShowHelp('Show a divider line between L2 and R2 groups.');
    end

    -- Background section
    if components.CollapsingSection('Background##crossbar', false) then
        local bgThemes = {'-None-', 'Plain', 'Window1', 'Window2', 'Window3', 'Window4', 'Window5', 'Window6', 'Window7', 'Window8'};
        components.DrawPartyComboBox(crossbarSettings, 'Theme##bgcrossbar', 'backgroundTheme', bgThemes, DeferredUpdateVisuals);
        imgui.ShowHelp('Select the background window theme.');

        components.DrawPartySlider(crossbarSettings, 'Background Scale##crossbar', 'bgScale', 0.1, 3.0, '%.2f', nil, 1.0);
        imgui.ShowHelp('Scale of the background texture.');

        components.DrawPartySlider(crossbarSettings, 'Border Scale##crossbar', 'borderScale', 0.1, 3.0, '%.2f', nil, 1.0);
        imgui.ShowHelp('Scale of the window borders.');

        components.DrawPartySlider(crossbarSettings, 'Background Opacity##crossbar', 'backgroundOpacity', 0.0, 1.0, '%.2f');
        imgui.ShowHelp('Opacity of the background.');

        components.DrawPartySlider(crossbarSettings, 'Border Opacity##crossbar', 'borderOpacity', 0.0, 1.0, '%.2f');
        imgui.ShowHelp('Opacity of the window borders.');
    end

    -- Controller Icons section
    if components.CollapsingSection('Controller Icons##crossbar', false) then
        local controllerThemes = { 'PlayStation', 'Xbox', 'Nintendo' };
        components.DrawPartyComboBox(crossbarSettings, 'Controller Theme##crossbar', 'controllerTheme', controllerThemes);
        imgui.ShowHelp('Select controller button icon style. Nintendo layout: X top, A right, B bottom, Y left.');

        components.DrawPartyCheckbox(crossbarSettings, 'Show Button Icons##crossbar', 'showButtonIcons');
        imgui.ShowHelp('Show d-pad and face button icons on slots.');

        if crossbarSettings.showButtonIcons then
            components.DrawPartySliderInt(crossbarSettings, 'Button Icon Size##crossbar', 'buttonIconSize', 8, 32, '%d', nil, 16);
            imgui.ShowHelp('Size of controller button icons.');

            components.DrawPartySliderInt(crossbarSettings, 'Button Icon Gap (H)##crossbar', 'buttonIconGapH', 0, 24, '%d', nil, 2);
            imgui.ShowHelp('Horizontal spacing between center controller icons.');

            components.DrawPartySliderInt(crossbarSettings, 'Button Icon Gap (V)##crossbar', 'buttonIconGapV', 0, 24, '%d', nil, 2);
            imgui.ShowHelp('Vertical spacing between center controller icons.');
        end

        imgui.Separator();

        components.DrawPartyCheckbox(crossbarSettings, 'Show Trigger Icons##crossbar', 'showTriggerLabels');
        imgui.ShowHelp('Show L2/R2 trigger icons above the crossbar groups.');

        if crossbarSettings.showTriggerLabels then
            components.DrawPartySlider(crossbarSettings, 'Trigger Icon Scale##crossbar', 'triggerIconScale', 0.5, 2.0, '%.1f', nil, 1.0);
            imgui.ShowHelp('Scale for L2/R2 trigger icons above groups (base size 49x28).');
        end
    end

    -- Text section
    if components.CollapsingSection('Text Settings##crossbar', false) then
        components.DrawPartySliderInt(crossbarSettings, 'Keybind Font Size##crossbar', 'keybindFontSize', 6, 24, '%d', nil, 8);
        imgui.ShowHelp('Font size for keybind labels.');

        components.DrawPartySliderInt(crossbarSettings, 'Label Font Size##crossbar', 'labelFontSize', 6, 24, '%d', nil, 10);
        imgui.ShowHelp('Font size for action labels.');

        components.DrawPartySliderInt(crossbarSettings, 'Trigger Label Font Size##crossbar', 'triggerLabelFontSize', 8, 24, '%d', nil, 14);
        imgui.ShowHelp('Font size for combo mode labels (L2, R2, etc.).');
    end

    -- Controller Input section
    if components.CollapsingSection('Controller Input##crossbar', false) then
        components.DrawPartySliderInt(crossbarSettings, 'Trigger Threshold##crossbar', 'triggerThreshold', 10, 200, '%d', nil, 30);
        imgui.ShowHelp('Analog trigger threshold (0-255). Lower = more sensitive.');

        imgui.Spacing();
        imgui.TextColored({0.8, 0.8, 0.6, 1.0}, 'Expanded Crossbar');

        components.DrawPartyCheckbox(crossbarSettings, 'Enable L2+R2 / R2+L2##crossbar', 'enableExpandedCrossbar');
        imgui.ShowHelp('Enable L2+R2 and R2+L2 combo modes. Hold one trigger, then press the other to access expanded bars.');

        components.DrawPartyCheckbox(crossbarSettings, 'Enable Double-Tap##crossbar', 'enableDoubleTap', DeferredUpdateVisuals);
        imgui.ShowHelp('Enable L2x2 and R2x2 double-tap modes. Tap a trigger twice quickly (hold on second tap) to access double-tap bars.');

        if crossbarSettings.enableDoubleTap then
            components.DrawPartySlider(crossbarSettings, 'Double-Tap Window##crossbar', 'doubleTapWindow', 0.1, 0.6, '%.2f sec', DeferredUpdateVisuals, 0.3);
            imgui.ShowHelp('Time window to register a double-tap (in seconds). Tap twice within this time to trigger double-tap mode.');
        end
    end

    -- Visual Feedback section
    if components.CollapsingSection('Visual Feedback##crossbar', false) then
        components.DrawPartySlider(crossbarSettings, 'Inactive Dim##crossbar', 'inactiveSlotDim', 0.0, 1.0, '%.2f', nil, 0.5);
        imgui.ShowHelp('Dim factor for inactive trigger side (0 = black, 1 = full brightness).');

        imgui.Spacing();
        components.DrawPartyCheckbox(crossbarSettings, 'Show Combo Text##crossbar', 'showComboText');
        imgui.ShowHelp('Show current combo mode text in center (L2+R2, R2+L2, L2x2, R2x2).');

        if crossbarSettings.showComboText then
            components.DrawPartySlider(crossbarSettings, 'Combo Text Size##crossbar', 'comboTextFontSize', 8, 20, '%d', nil, 12);
            imgui.ShowHelp('Font size for combo text.');
        end
    end
end

local function DrawCrossbarColorSettings()
    local crossbarSettings = gConfig.hotbarCrossbar;
    if not crossbarSettings then
        imgui.TextColored({1.0, 0.5, 0.5, 1.0}, 'Crossbar settings not initialized.');
        return;
    end

    local colorFlags = bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaPreviewHalf, ImGuiColorEditFlags_AlphaBar);

    imgui.TextColored(components.TAB_STYLE.gold, 'Crossbar Color Settings');
    imgui.Spacing();

    if components.CollapsingSection('Window Colors##crossbarcolor', true) then
        local bgColor = crossbarSettings.bgColor or 0xFFFFFFFF;
        local bgColorTable = ARGBToImGui(bgColor);
        if imgui.ColorEdit4('Background Color##crossbar', bgColorTable, colorFlags) then
            crossbarSettings.bgColor = ImGuiToARGB(bgColorTable);
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Color tint for the window background.');

        local borderColor = crossbarSettings.borderColor or 0xFFFFFFFF;
        local borderColorTable = ARGBToImGui(borderColor);
        if imgui.ColorEdit4('Border Color##crossbar', borderColorTable, colorFlags) then
            crossbarSettings.borderColor = ImGuiToARGB(borderColorTable);
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Color tint for the window borders.');
    end

    if components.CollapsingSection('Slot Colors##crossbarcolor', true) then
        local slotBgColor = crossbarSettings.slotBackgroundColor or 0x55000000;
        local slotBgColorTable = ARGBToImGui(slotBgColor);
        if imgui.ColorEdit4('Slot Background##crossbar', slotBgColorTable, colorFlags) then
            crossbarSettings.slotBackgroundColor = ImGuiToARGB(slotBgColorTable);
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Color and transparency of slot backgrounds.');

        local highlightColor = crossbarSettings.activeSlotHighlight or 0x44FFFFFF;
        local highlightColorTable = ARGBToImGui(highlightColor);
        if imgui.ColorEdit4('Active Highlight##crossbar', highlightColorTable, colorFlags) then
            crossbarSettings.activeSlotHighlight = ImGuiToARGB(highlightColorTable);
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Highlight color for slots when trigger is held.');
    end

    if components.CollapsingSection('Text Colors##crossbarcolor', true) then
        local keybindColor = crossbarSettings.keybindFontColor or 0xFFFFFFFF;
        local keybindColorTable = ARGBToImGui(keybindColor);
        if imgui.ColorEdit4('Keybind Color##crossbar', keybindColorTable, colorFlags) then
            crossbarSettings.keybindFontColor = ImGuiToARGB(keybindColorTable);
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Color for keybind labels.');

        local triggerLabelColor = crossbarSettings.triggerLabelColor or 0xFFFFCC00;
        local triggerLabelColorTable = ARGBToImGui(triggerLabelColor);
        if imgui.ColorEdit4('Trigger Label Color##crossbar', triggerLabelColorTable, colorFlags) then
            crossbarSettings.triggerLabelColor = ImGuiToARGB(triggerLabelColorTable);
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Color for combo mode labels (L2, R2, etc.).');
    end
end

-- Section: Hotbar Settings
function M.DrawSettings(state)
    local selectedBarTab = state and state.selectedHotbarTab or 1;

    -- Global settings
    components.DrawCheckbox('Enabled', 'hotbarEnabled');
    imgui.ShowHelp('Enable or disable the hotbar module.');

    -- Macro Palette and Edit Keybinds buttons (always visible at top)
    imgui.Spacing();
    if imgui.Button('Open Macro Palette', {160, 24}) then
        macropalette.OpenPalette();
    end
    imgui.ShowHelp('Create macros (per-job) and drag them to hotbar slots. Drag slots to rearrange. Right-click to clear.');
    imgui.SameLine();
    local editBarIndex = selectedBarTab or 1;
    local editConfigKey = 'hotbarBar' .. editBarIndex;
    if imgui.Button('Edit Keybinds', {120, 24}) then
        OpenKeybindModal(editBarIndex, editConfigKey);
    end
    imgui.ShowHelp('Open keybind editor to configure slot actions for the selected hotbar.');

    -- Crossbar Mode Toggle
    imgui.Spacing();
    local crossbarEnabled = { gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.enabled or false };
    if imgui.Checkbox('Crossbar Mode (Controller Layout)', crossbarEnabled) then
        if gConfig.hotbarCrossbar then
            gConfig.hotbarCrossbar.enabled = crossbarEnabled[1];
            SaveSettingsOnly();
            DeferredUpdateVisuals();
        end
    end
    imgui.ShowHelp('Enable crossbar layout for controller play. Uses L2/R2 trigger groups with 32 slots total (4 combo modes x 8 slots).');

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Show crossbar settings OR standard hotbar settings based on mode
    if gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.enabled then
        DrawCrossbarSettings();
        return { selectedHotbarTab = selectedBarTab };
    end

    -- Standard hotbar settings below
    imgui.Spacing();

    -- Per-Bar Visual Settings header
    imgui.TextColored(components.TAB_STYLE.gold, 'Per-Bar Visual Settings');
    imgui.ShowHelp('Configure each hotbar independently. Each bar can have its own layout, theme, and button settings.');
    imgui.Spacing();

    -- Draw Bar 1-6 tabs
    for i, barType in ipairs(BAR_TYPES) do
        local clicked, tabWidth = components.DrawStyledTab(
            barType.label,
            'hotbarBarTab' .. i,
            selectedBarTab == i,
            nil,
            components.TAB_STYLE.smallHeight,
            components.TAB_STYLE.smallPadding
        );
        if clicked then
            selectedBarTab = i;
        end
        if i < #BAR_TYPES then
            imgui.SameLine();
        end
    end

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Draw settings for selected bar (Global tab vs per-bar tabs)
    local currentBar = BAR_TYPES[selectedBarTab];
    if currentBar then
        if currentBar.isGlobal then
            DrawGlobalVisualSettings();
        else
            DrawBarVisualSettings(currentBar.configKey, currentBar.label);
        end
    end

    return { selectedHotbarTab = selectedBarTab };
end

-- Helper: Draw color settings content (shared between global and per-bar)
local function DrawColorSettingsContent(settings, configKey)
    local colorFlags = bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaPreviewHalf, ImGuiColorEditFlags_AlphaBar);

    if components.CollapsingSection('Window Colors##' .. configKey .. 'color', true) then
        -- Background color (with alpha support)
        local bgColor = settings.bgColor or 0xFFFFFFFF;
        local bgColorTable = ARGBToImGui(bgColor);
        if imgui.ColorEdit4('Background Color##' .. configKey, bgColorTable, colorFlags) then
            settings.bgColor = ImGuiToARGB(bgColorTable);
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Color tint for the window background (includes alpha/transparency).');

        -- Border color (with alpha support)
        local borderColor = settings.borderColor or 0xFFFFFFFF;
        local borderColorTable = ARGBToImGui(borderColor);
        if imgui.ColorEdit4('Border Color##' .. configKey, borderColorTable, colorFlags) then
            settings.borderColor = ImGuiToARGB(borderColorTable);
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Color tint for the window borders.');
    end

    if components.CollapsingSection('Slot Colors##' .. configKey .. 'color', true) then
        -- Slot background color (with alpha support)
        local slotBgColor = settings.slotBackgroundColor or 0xFFFFFFFF;
        local slotBgColorTable = ARGBToImGui(slotBgColor);
        if imgui.ColorEdit4('Slot Background Color##' .. configKey, slotBgColorTable, colorFlags) then
            settings.slotBackgroundColor = ImGuiToARGB(slotBgColorTable);
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Color and transparency of slot backgrounds.');
    end

    if components.CollapsingSection('Text Colors##' .. configKey .. 'color', true) then
        -- Keybind font color
        local keybindColor = settings.keybindFontColor or 0xFFFFFFFF;
        local keybindColorTable = ARGBToImGui(keybindColor);
        if imgui.ColorEdit4('Keybind Color##' .. configKey, keybindColorTable, colorFlags) then
            settings.keybindFontColor = ImGuiToARGB(keybindColorTable);
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Color for keybind labels (e.g., "1", "C2", "A3").');
    end
end

-- Helper: Draw global color settings
local function DrawGlobalColorSettings()
    local globalSettings = gConfig.hotbarGlobal;
    if not globalSettings or type(globalSettings) ~= 'table' then
        imgui.TextColored({1.0, 0.5, 0.5, 1.0}, 'Global settings not initialized.');
        imgui.Text('Please reload the addon to initialize global settings.');
        return;
    end

    imgui.TextColored(components.TAB_STYLE.gold, 'Global Color Settings');
    imgui.TextColored({0.7, 0.7, 0.7, 1.0}, 'These colors apply to all bars with "Use Global Settings" enabled.');
    imgui.Spacing();

    DrawColorSettingsContent(globalSettings, 'hotbarGlobal');
end

-- Helper: Draw per-bar color settings
local function DrawBarColorSettings(configKey, barLabel)
    local barSettings = gConfig[configKey];
    if not barSettings or type(barSettings) ~= 'table' then
        imgui.TextColored({1.0, 0.5, 0.5, 1.0}, 'Settings not initialized for ' .. barLabel);
        return;
    end

    -- Check if using global settings
    if barSettings.useGlobalSettings then
        imgui.TextColored({0.6, 0.8, 1.0, 1.0}, 'Color settings are using Global tab settings.');
        imgui.TextColored({0.5, 0.5, 0.5, 1.0}, 'Disable "Use Global Settings" in the Settings tab to customize this bar independently.');
    else
        DrawColorSettingsContent(barSettings, configKey);
    end
end

-- Section: Hotbar Color Settings
function M.DrawColorSettings(state)
    local selectedBarTab = state and state.selectedHotbarTab or 1;

    -- Show crossbar color settings if crossbar is enabled
    if gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.enabled then
        DrawCrossbarColorSettings();
        return { selectedHotbarTab = selectedBarTab };
    end

    -- Per-Bar Color Settings header
    imgui.TextColored(components.TAB_STYLE.gold, 'Per-Bar Color Settings');
    imgui.Spacing();

    -- Draw Bar 1-6 tabs (same as visual settings)
    for i, barType in ipairs(BAR_TYPES) do
        local clicked, tabWidth = components.DrawStyledTab(
            barType.label,
            'hotbarColorTab' .. i,
            selectedBarTab == i,
            nil,
            components.TAB_STYLE.smallHeight,
            components.TAB_STYLE.smallPadding
        );
        if clicked then
            selectedBarTab = i;
        end
        if i < #BAR_TYPES then
            imgui.SameLine();
        end
    end

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Draw color settings for selected bar (Global tab vs per-bar tabs)
    local currentBar = BAR_TYPES[selectedBarTab];
    if currentBar then
        if currentBar.isGlobal then
            DrawGlobalColorSettings();
        else
            DrawBarColorSettings(currentBar.configKey, currentBar.label);
        end
    end

    return { selectedHotbarTab = selectedBarTab };
end

return M;
