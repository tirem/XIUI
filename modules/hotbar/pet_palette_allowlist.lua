--[[
 * Pet palette allowlist: petPalettePetKeys = array of type tokens, or nil = all types use pet storage.
 * Crossbar stores the filter on hotbarCrossbar.petPalettePetKeys (character-wide, not per palette).
 * Stored tokens (strings): 'avatars' | 'elementals' | 'beasts' | 'wyvern' | 'puppet'
 *   avatars     → SMN avatars (runtime keys avatar:*)
 *   elementals  → SMN elementals (runtime keys spirit:*)
 *   beasts      → jug + charm
 *   wyvern      → wyvern
 *   puppet      → automaton
 * Legacy token 'summons' (old saves): treated as avatars+elementals for matching; editor upgrades to avatars+elementals.
 * nil / absent = all types (default).
 * Legacy saves may list individual pet keys; they are normalized to type tokens when the editor opens.
]]--

require('common');
local imgui = require('imgui');

local M = {};

local TYPE_AVATARS = 'avatars';
local TYPE_ELEMENTALS = 'elementals';
local TYPE_BEASTS = 'beasts';
local TYPE_WYVERN = 'wyvern';
local TYPE_PUPPET = 'puppet';
-- Legacy: previously meant both avatars and elementals; still honored in Allows() and migrated in the editor.
local TYPE_LEGACY_SUMMONS = 'summons';

local ALL_TYPES = { TYPE_AVATARS, TYPE_ELEMENTALS, TYPE_BEASTS, TYPE_WYVERN, TYPE_PUPPET };

local TYPE_ROWS = {
    { token = TYPE_AVATARS, label = 'Avatars' },
    { token = TYPE_ELEMENTALS, label = 'Elementals' },
    { token = TYPE_BEASTS, label = 'Beasts' },
    { token = TYPE_WYVERN, label = 'Wyvern' },
    { token = TYPE_PUPPET, label = 'Puppet' },
};

local function isKnownTypeToken(s)
    return s == TYPE_AVATARS
        or s == TYPE_ELEMENTALS
        or s == TYPE_BEASTS
        or s == TYPE_WYVERN
        or s == TYPE_PUPPET
        or s == TYPE_LEGACY_SUMMONS;
end

--- True if list contains any legacy per-pet entry (not only type tokens).
local function isLegacyAllowlist(list)
    if not list or type(list) ~= 'table' then
        return false;
    end
    for i = 1, #list do
        if not isKnownTypeToken(list[i]) then
            return true;
        end
    end
    return false;
end

local function legacyEntryImpliedType(entry)
    if type(entry) ~= 'string' then
        return nil;
    end
    if
        entry == TYPE_AVATARS
        or entry == TYPE_ELEMENTALS
        or entry == TYPE_BEASTS
        or entry == TYPE_WYVERN
        or entry == TYPE_PUPPET
    then
        return entry;
    end
    if entry == TYPE_LEGACY_SUMMONS then
        return nil;
    end
    if entry:match('^avatar:') then
        return TYPE_AVATARS;
    end
    if entry:match('^spirit:') then
        return TYPE_ELEMENTALS;
    end
    if entry == 'jug' or entry == 'charm' then
        return TYPE_BEASTS;
    end
    if entry == 'wyvern' then
        return TYPE_WYVERN;
    end
    if entry == 'automaton' then
        return TYPE_PUPPET;
    end
    return nil;
end

--- Collapse legacy per-pet keys into type tokens (lossy; intentional).
function M.NormalizeAllowlistToTypes(list)
    if not list or type(list) ~= 'table' or #list == 0 then
        return {};
    end
    local seen = {
        [TYPE_AVATARS] = false,
        [TYPE_ELEMENTALS] = false,
        [TYPE_BEASTS] = false,
        [TYPE_WYVERN] = false,
        [TYPE_PUPPET] = false,
    };
    for i = 1, #list do
        local e = list[i];
        if e == TYPE_LEGACY_SUMMONS then
            seen[TYPE_AVATARS] = true;
            seen[TYPE_ELEMENTALS] = true;
        else
            local t = legacyEntryImpliedType(e);
            if t then
                seen[t] = true;
            end
        end
    end
    local out = {};
    for _, tok in ipairs(ALL_TYPES) do
        if seen[tok] then
            table.insert(out, tok);
        end
    end
    return out;
end

local function typeTokenMatchesPetKey(token, petKey)
    if not petKey or type(petKey) ~= 'string' then
        return false;
    end
    if token == TYPE_AVATARS then
        return petKey:match('^avatar:') ~= nil;
    end
    if token == TYPE_ELEMENTALS then
        return petKey:match('^spirit:') ~= nil;
    end
    if token == TYPE_LEGACY_SUMMONS then
        return petKey:match('^avatar:') ~= nil or petKey:match('^spirit:') ~= nil;
    end
    if token == TYPE_BEASTS then
        return petKey == 'jug' or petKey == 'charm';
    end
    if token == TYPE_WYVERN then
        return petKey == 'wyvern';
    end
    if token == TYPE_PUPPET then
        return petKey == 'automaton';
    end
    return false;
end

function M.Allows(settings, petKey)
    if not petKey then
        return false;
    end
    local list = settings and settings.petPalettePetKeys;
    if list == nil then
        return true;
    end
    if type(list) ~= 'table' then
        return true;
    end
    for i = 1, #list do
        local e = list[i];
        if e == petKey then
            return true;
        end
        if isKnownTypeToken(e) and typeTokenMatchesPetKey(e, petKey) then
            return true;
        end
    end
    return false;
end

local function listContains(arr, key)
    for j = 1, #arr do
        if arr[j] == key then
            return true;
        end
    end
    return false;
end

local function listRemoveToken(arr, token)
    local out = {};
    for j = 1, #arr do
        if arr[j] ~= token then
            table.insert(out, arr[j]);
        end
    end
    return out;
end

local function listAddToken(arr, token)
    if listContains(arr, token) then
        return arr;
    end
    local out = {};
    for j = 1, #arr do
        out[j] = arr[j];
    end
    table.insert(out, token);
    return out;
end

--- Replace legacy 'summons' with 'avatars'+'elementals' (same practical coverage).
function M.UpgradeSummonsTokenInPlace(list)
    if not list or type(list) ~= 'table' or not listContains(list, TYPE_LEGACY_SUMMONS) then
        return list, false;
    end
    local newList = {};
    for j = 1, #list do
        if list[j] ~= TYPE_LEGACY_SUMMONS then
            table.insert(newList, list[j]);
        end
    end
    newList = listAddToken(newList, TYPE_AVATARS);
    newList = listAddToken(newList, TYPE_ELEMENTALS);
    return newList, true;
end

function M.CopyAllTypes()
    local out = {};
    for i = 1, #ALL_TYPES do
        out[i] = ALL_TYPES[i];
    end
    return out;
end

--- For crossbar popup init: copy effective list, normalizing legacy shapes to type tokens.
-- nil = all types (UI shows all checkboxes on).
function M.CopyAllowlistForEditor(effList)
    if effList == nil then
        return M.CopyAllTypes();
    end
    if isLegacyAllowlist(effList) then
        return M.NormalizeAllowlistToTypes(effList);
    end
    local out = {};
    for i = 1, #effList do
        out[i] = effList[i];
    end
    out = select(1, M.UpgradeSummonsTokenInPlace(out)) or out;
    return out;
end

--- True if list means "all pet families" (nil or all five type tokens, or legacy equivalent).
-- Empty table = no types.
function M.IsEffectivelyAllTypes(list)
    if list == nil then
        return true;
    end
    if type(list) ~= 'table' or #list == 0 then
        return false;
    end
    if isLegacyAllowlist(list) then
        return #M.NormalizeAllowlistToTypes(list) == 5;
    end
    -- Legacy four-token "all" was summons+beasts+wyvern+puppet; summons covers avatars+elementals.
    local hasA = listContains(list, TYPE_AVATARS) or listContains(list, TYPE_LEGACY_SUMMONS);
    local hasE = listContains(list, TYPE_ELEMENTALS) or listContains(list, TYPE_LEGACY_SUMMONS);
    if not hasA or not hasE then
        return false;
    end
    for _, t in ipairs({ TYPE_BEASTS, TYPE_WYVERN, TYPE_PUPPET }) do
        if not listContains(list, t) then
            return false;
        end
    end
    return true;
end

--- Draw allowlist checkboxes (Select all / Clear all + type toggles). Call from BeginPopup, hotbar pet popup, etc.
function M.DrawEditorPanel(settingsWritable, _jobId, saveFn, invalidateFn, afterMutate)
    if not settingsWritable then
        return;
    end

    if settingsWritable.petPalettePetKeys and isLegacyAllowlist(settingsWritable.petPalettePetKeys) then
        settingsWritable.petPalettePetKeys = M.NormalizeAllowlistToTypes(settingsWritable.petPalettePetKeys);
        if afterMutate then
            afterMutate(settingsWritable);
        end
        if saveFn then
            saveFn();
        end
        if invalidateFn then
            invalidateFn();
        end
    end

    do
        local newL, ch = M.UpgradeSummonsTokenInPlace(settingsWritable.petPalettePetKeys);
        if ch then
            settingsWritable.petPalettePetKeys = newL;
            if afterMutate then
                afterMutate(settingsWritable);
            end
            if saveFn then
                saveFn();
            end
            if invalidateFn then
                invalidateFn();
            end
        end
    end

    if imgui.Button('Select all##petallow') then
        -- nil = all types (storable default)
        settingsWritable.petPalettePetKeys = nil;
        if afterMutate then
            afterMutate(settingsWritable);
        end
        if saveFn then
            saveFn();
        end
        if invalidateFn then
            invalidateFn();
        end
    end
    imgui.SameLine();
    if imgui.Button('Clear all##petallow') then
        settingsWritable.petPalettePetKeys = {};
        if afterMutate then
            afterMutate(settingsWritable);
        end
        if saveFn then
            saveFn();
        end
        if invalidateFn then
            invalidateFn();
        end
    end

    imgui.Spacing();
    local list = settingsWritable.petPalettePetKeys;
    for _, row in ipairs(TYPE_ROWS) do
        local on;
        if list == nil then
            on = true;
        else
            on = listContains(list, row.token);
        end
        local b = { on };
        if imgui.Checkbox(row.label .. '##pt_' .. row.token, b) then
            if b[1] then
                if list == nil then
                    list = M.CopyAllTypes();
                end
                settingsWritable.petPalettePetKeys = listAddToken(list, row.token);
            else
                if list == nil then
                    list = M.CopyAllTypes();
                end
                settingsWritable.petPalettePetKeys = listRemoveToken(list, row.token);
            end
            if afterMutate then
                afterMutate(settingsWritable);
            end
            if saveFn then
                saveFn();
            end
            if invalidateFn then
                invalidateFn();
            end
        end
    end
end

--- Backwards compatible name: draw inside an open ImGui popup.
function M.DrawEditorInPopup(settingsWritable, jobId, saveFn, invalidateFn, afterMutate)
    M.DrawEditorPanel(settingsWritable, jobId, saveFn, invalidateFn, afterMutate);
end

return M;
