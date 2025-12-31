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
    waitingForKey = false,       -- True when capturing key input
    lastCapturedKey = nil,       -- Last captured key info for display
};

-- Virtual key code to display string mapping
local VK_NAMES = {
    [8] = 'Backspace', [9] = 'Tab', [13] = 'Enter', [16] = 'Shift', [17] = 'Ctrl', [18] = 'Alt',
    [19] = 'Pause', [20] = 'CapsLock', [27] = 'Esc', [32] = 'Space',
    [33] = 'PgUp', [34] = 'PgDn', [35] = 'End', [36] = 'Home',
    [37] = 'Left', [38] = 'Up', [39] = 'Right', [40] = 'Down',
    [45] = 'Insert', [46] = 'Delete',
    [96] = 'Num0', [97] = 'Num1', [98] = 'Num2', [99] = 'Num3', [100] = 'Num4',
    [101] = 'Num5', [102] = 'Num6', [103] = 'Num7', [104] = 'Num8', [105] = 'Num9',
    [106] = 'Num*', [107] = 'Num+', [109] = 'Num-', [110] = 'Num.', [111] = 'Num/',
    [112] = 'F1', [113] = 'F2', [114] = 'F3', [115] = 'F4', [116] = 'F5', [117] = 'F6',
    [118] = 'F7', [119] = 'F8', [120] = 'F9', [121] = 'F10', [122] = 'F11', [123] = 'F12',
    [144] = 'NumLock', [145] = 'ScrollLock',
    [186] = ';', [187] = '=', [188] = ',', [189] = '-', [190] = '.', [191] = '/',
    [192] = '`', [219] = '[', [220] = '\\', [221] = ']', [222] = "'",
};

-- Convert virtual key code to display string
local function VKToString(vk)
    if VK_NAMES[vk] then return VK_NAMES[vk]; end
    if vk >= 48 and vk <= 57 then return tostring(vk - 48); end  -- 0-9
    if vk >= 65 and vk <= 90 then return string.char(vk); end    -- A-Z
    return string.format('Key%d', vk);
end

-- Format a keybind for display (e.g., "Ctrl+Shift+A")
local function FormatKeybind(binding)
    if not binding or not binding.key then return ''; end
    local parts = {};
    if binding.ctrl then table.insert(parts, 'Ctrl'); end
    if binding.alt then table.insert(parts, 'Alt'); end
    if binding.shift then table.insert(parts, 'Shift'); end
    table.insert(parts, VKToString(binding.key));
    return table.concat(parts, '+');
end

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

-- Open keybind modal for a bar
local function OpenKeybindModal(barIndex, configKey)
    keybindModal.isOpen = true;
    keybindModal.barIndex = barIndex;
    keybindModal.configKey = configKey;
    keybindModal.selectedSlot = nil;
    keybindModal.waitingForKey = false;
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

    -- Ensure keyBindings table exists
    if not barSettings.keyBindings then
        barSettings.keyBindings = {};
    end

    local windowFlags = bit.bor(
        ImGuiWindowFlags_NoCollapse,
        ImGuiWindowFlags_NoResize
    );

    local modalTitle = 'Keybind Editor###keybindModal';
    local isOpen = { true };

    -- XIUI Theme Colors (matching main config window)
    local gold = {0.957, 0.855, 0.592, 1.0};
    local goldDark = {0.765, 0.684, 0.474, 1.0};
    local goldDarker = {0.573, 0.512, 0.355, 1.0};
    local bgDark = {0.051, 0.051, 0.051, 0.95};
    local bgMedium = {0.098, 0.090, 0.075, 1.0};
    local bgLight = {0.137, 0.125, 0.106, 1.0};
    local bgLighter = {0.176, 0.161, 0.137, 1.0};
    local textLight = {0.878, 0.855, 0.812, 1.0};
    local borderDark = {0.3, 0.275, 0.235, 1.0};

    -- Push style colors
    imgui.PushStyleColor(ImGuiCol_WindowBg, bgDark);
    imgui.PushStyleColor(ImGuiCol_ChildBg, {0, 0, 0, 0});
    imgui.PushStyleColor(ImGuiCol_TitleBg, bgMedium);
    imgui.PushStyleColor(ImGuiCol_TitleBgActive, bgLight);
    imgui.PushStyleColor(ImGuiCol_TitleBgCollapsed, bgDark);
    imgui.PushStyleColor(ImGuiCol_FrameBg, bgMedium);
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, bgLight);
    imgui.PushStyleColor(ImGuiCol_FrameBgActive, bgLighter);
    imgui.PushStyleColor(ImGuiCol_Header, bgLight);
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, bgLighter);
    imgui.PushStyleColor(ImGuiCol_HeaderActive, {gold[1], gold[2], gold[3], 0.3});
    imgui.PushStyleColor(ImGuiCol_Border, borderDark);
    imgui.PushStyleColor(ImGuiCol_Text, textLight);
    imgui.PushStyleColor(ImGuiCol_TextDisabled, goldDark);
    imgui.PushStyleColor(ImGuiCol_Button, bgMedium);
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, bgLight);
    imgui.PushStyleColor(ImGuiCol_ButtonActive, bgLighter);
    imgui.PushStyleColor(ImGuiCol_CheckMark, gold);
    imgui.PushStyleColor(ImGuiCol_SliderGrab, goldDark);
    imgui.PushStyleColor(ImGuiCol_SliderGrabActive, gold);
    imgui.PushStyleColor(ImGuiCol_ScrollbarBg, bgMedium);
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrab, bgLighter);
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabHovered, borderDark);
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabActive, goldDark);
    imgui.PushStyleColor(ImGuiCol_Separator, borderDark);
    imgui.PushStyleColor(ImGuiCol_PopupBg, bgMedium);
    imgui.PushStyleColor(ImGuiCol_Tab, bgMedium);
    imgui.PushStyleColor(ImGuiCol_TabHovered, bgLight);
    imgui.PushStyleColor(ImGuiCol_TabActive, {gold[1], gold[2], gold[3], 0.3});
    imgui.PushStyleColor(ImGuiCol_TabUnfocused, bgDark);
    imgui.PushStyleColor(ImGuiCol_TabUnfocusedActive, bgMedium);
    imgui.PushStyleColor(ImGuiCol_ResizeGrip, goldDarker);
    imgui.PushStyleColor(ImGuiCol_ResizeGripHovered, goldDark);
    imgui.PushStyleColor(ImGuiCol_ResizeGripActive, gold);

    -- Push style vars
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {12, 12});
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {6, 4});
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {8, 6});
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 4.0);
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 6.0);
    imgui.PushStyleVar(ImGuiStyleVar_ChildRounding, 4.0);
    imgui.PushStyleVar(ImGuiStyleVar_PopupRounding, 4.0);
    imgui.PushStyleVar(ImGuiStyleVar_ScrollbarRounding, 4.0);
    imgui.PushStyleVar(ImGuiStyleVar_GrabRounding, 4.0);

    imgui.SetNextWindowSize({560, 215}, ImGuiCond_Always);

    if imgui.Begin(modalTitle, isOpen, windowFlags) then
        -- Bar selector using styled tabs (like the bar tabs in hotbar settings)
        for i = 1, 6 do
            local clicked, _ = components.DrawStyledTab(
                'Bar ' .. i,
                'keybindBar' .. i,
                barIndex == i,
                nil,
                components.TAB_STYLE.smallHeight,
                components.TAB_STYLE.smallPadding
            );
            if clicked and barIndex ~= i then
                keybindModal.barIndex = i;
                keybindModal.configKey = 'hotbarBar' .. i;
                keybindModal.selectedSlot = nil;
                keybindModal.waitingForKey = false;
            end
            if i < 6 then
                imgui.SameLine();
            end
        end

        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();

        -- Slot buttons across the top (all 12 visible) using styled tabs
        local slots = barSettings.slots or 12;
        local draw_list = imgui.GetWindowDrawList();

        for slotIndex = 1, slots do
            local binding = barSettings.keyBindings[slotIndex];
            local hasKeybind = binding and binding.key;
            local isSelected = keybindModal.selectedSlot == slotIndex;

            -- Get position before drawing button for indicator
            local btnPosX, btnPosY = imgui.GetCursorScreenPos();
            local slotWidth = 32;
            local slotHeight = components.TAB_STYLE.height;

            -- Use DrawStyledTab for consistent styling
            local clicked, _ = components.DrawStyledTab(
                tostring(slotIndex),
                'keybindSlot' .. slotIndex,
                isSelected,
                slotWidth,
                slotHeight,
                4
            );

            -- Draw indicator dot for slots with keybinds (below the button)
            if hasKeybind then
                local dotRadius = 3;
                local dotX = btnPosX + (slotWidth / 2);
                local dotY = btnPosY + slotHeight + 4;
                draw_list:AddCircleFilled(
                    {dotX, dotY},
                    dotRadius,
                    imgui.GetColorU32(gold),
                    8
                );
            end

            if clicked then
                keybindModal.selectedSlot = slotIndex;
                keybindModal.waitingForKey = false;
            end

            -- Tooltip with keybind info
            if imgui.IsItemHovered() then
                imgui.BeginTooltip();
                imgui.Text(string.format('Slot %d', slotIndex));
                if hasKeybind then
                    imgui.TextColored(components.TAB_STYLE.gold, FormatKeybind(binding));
                else
                    imgui.TextColored({0.5, 0.5, 0.5, 1.0}, 'No keybind');
                end
                imgui.EndTooltip();
            end

            if slotIndex < slots then
                imgui.SameLine();
            end
        end

        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();

        -- Key assignment section below
        if keybindModal.selectedSlot then
            local selectedSlot = keybindModal.selectedSlot;
            local currentBinding = barSettings.keyBindings[selectedSlot];

            -- Current keybind display inline
            imgui.Text(string.format('Slot %d:', selectedSlot));
            imgui.SameLine();
            if currentBinding and currentBinding.key then
                imgui.TextColored(components.TAB_STYLE.gold, FormatKeybind(currentBinding));
            else
                imgui.TextColored({0.5, 0.5, 0.5, 1.0}, 'No keybind assigned');
            end

            imgui.Spacing();

            -- Key capture button and clear button on same line
            if keybindModal.waitingForKey then
                imgui.TextColored(components.TAB_STYLE.gold, 'Press any key...');
                imgui.SameLine();
                imgui.TextColored({0.5, 0.5, 0.5, 1.0}, '(Escape to cancel)');
            else
                if imgui.Button('Set Keybind##set', {120, 0}) then
                    keybindModal.waitingForKey = true;
                end
                -- Clear button next to set button if keybind exists
                if currentBinding and currentBinding.key then
                    imgui.SameLine();
                    if imgui.Button('Clear##clear', {60, 0}) then
                        barSettings.keyBindings[selectedSlot] = nil;
                        SaveSettingsOnly();
                    end
                end
            end
        else
            imgui.TextColored({0.5, 0.5, 0.5, 1.0}, 'Select a slot above to assign a keyboard shortcut.');
        end
    end
    imgui.End();

    -- Pop style vars and colors (must match push count)
    imgui.PopStyleVar(9);
    imgui.PopStyleColor(34);

    -- Handle window close via X button
    if not isOpen[1] then
        CloseKeybindModal();
    end
end

-- Handle key capture for keybind editor (called from hotbar key handler)
function M.HandleKeybindCapture(keyCode, ctrl, alt, shift)
    if not keybindModal.isOpen or not keybindModal.waitingForKey then
        return false;
    end

    -- Escape cancels capture
    if keyCode == 27 then
        keybindModal.waitingForKey = false;
        return true;
    end

    -- Ignore standalone modifier keys
    if keyCode == 16 or keyCode == 17 or keyCode == 18 or
       keyCode == 160 or keyCode == 161 or keyCode == 162 or
       keyCode == 163 or keyCode == 164 or keyCode == 165 then
        return true;
    end

    local configKey = keybindModal.configKey;
    local selectedSlot = keybindModal.selectedSlot;

    if configKey and selectedSlot and gConfig[configKey] then
        local barSettings = gConfig[configKey];
        if not barSettings.keyBindings then
            barSettings.keyBindings = {};
        end

        -- Check for duplicate keybind across ALL bars and clear it
        local ctrlVal = ctrl or false;
        local altVal = alt or false;
        local shiftVal = shift or false;

        for barNum = 1, 6 do
            local checkConfigKey = 'hotbarBar' .. barNum;
            local checkBarSettings = gConfig[checkConfigKey];
            if checkBarSettings and checkBarSettings.keyBindings then
                for slotIndex, existingBinding in pairs(checkBarSettings.keyBindings) do
                    -- Skip the slot we're assigning to
                    local isSameSlot = (checkConfigKey == configKey and slotIndex == selectedSlot);
                    if not isSameSlot and existingBinding and existingBinding.key then
                        -- Check if this binding matches the new one
                        if existingBinding.key == keyCode and
                           (existingBinding.ctrl or false) == ctrlVal and
                           (existingBinding.alt or false) == altVal and
                           (existingBinding.shift or false) == shiftVal then
                            -- Clear the duplicate binding
                            checkBarSettings.keyBindings[slotIndex] = nil;
                        end
                    end
                end
            end
        end

        -- Store the keybind
        barSettings.keyBindings[selectedSlot] = {
            key = keyCode,
            ctrl = ctrlVal,
            alt = altVal,
            shift = shiftVal,
        };

        SaveSettingsOnly();
        keybindModal.waitingForKey = false;
    end

    return true;
end

-- Check if waiting for key capture
function M.IsCapturingKeybind()
    return keybindModal.isOpen and keybindModal.waitingForKey;
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

    -- Layout Mode dropdown
    imgui.Spacing();
    imgui.TextColored(components.TAB_STYLE.gold, 'Layout Mode');
    imgui.SameLine();

    local modeOptions = { 'Hotbar', 'Crossbar', 'Both' };
    local modeValues = { 'hotbar', 'crossbar', 'both' };
    local currentMode = gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.mode or 'hotbar';

    -- Find current mode index
    local currentModeIndex = 1;
    for i, v in ipairs(modeValues) do
        if v == currentMode then
            currentModeIndex = i;
            break;
        end
    end

    imgui.SetNextItemWidth(120);
    if imgui.BeginCombo('##layoutMode', modeOptions[currentModeIndex]) then
        for i, label in ipairs(modeOptions) do
            local isSelected = currentModeIndex == i;
            if imgui.Selectable(label, isSelected) then
                if gConfig.hotbarCrossbar then
                    gConfig.hotbarCrossbar.mode = modeValues[i];
                    SaveSettingsOnly();
                    DeferredUpdateVisuals();
                end
            end
            if isSelected then
                imgui.SetItemDefaultFocus();
            end
        end
        imgui.EndCombo();
    end
    imgui.ShowHelp('Hotbar: Standard keyboard hotbars (Bars 1-6)\nCrossbar: Controller layout with L2/R2 triggers\nBoth: Show both hotbar and crossbar');

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Determine what to show based on mode
    local showHotbar = currentMode == 'hotbar' or currentMode == 'both';
    local showCrossbar = currentMode == 'crossbar' or currentMode == 'both';

    -- Show crossbar settings if mode includes crossbar
    if showCrossbar then
        DrawCrossbarSettings();
        if not showHotbar then
            return { selectedHotbarTab = selectedBarTab };
        end
        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();
    end

    -- Show hotbar settings if mode includes hotbar
    if not showHotbar then
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

    -- Determine what to show based on mode
    local currentMode = gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.mode or 'hotbar';
    local showHotbar = currentMode == 'hotbar' or currentMode == 'both';
    local showCrossbar = currentMode == 'crossbar' or currentMode == 'both';

    -- Show crossbar color settings if mode includes crossbar
    if showCrossbar then
        DrawCrossbarColorSettings();
        if not showHotbar then
            return { selectedHotbarTab = selectedBarTab };
        end
        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();
    end

    -- Show hotbar color settings if mode includes hotbar
    if not showHotbar then
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
