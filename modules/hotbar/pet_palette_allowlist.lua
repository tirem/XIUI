--[[
 * Pet palette allowlist: when petPalettePetKeys is set, only selected *types* use pet storage.
 * Stored tokens (strings): 'summons' | 'beasts' | 'wyvern' | 'puppet'
 *   summons  → SMN avatars + spirits (runtime keys avatar:*, spirit:*)
 *   beasts   → jug + charm
 *   wyvern   → wyvern
 *   puppet   → automaton
 * nil / absent = all types (default).
 * Legacy saves may list individual pet keys; they are normalized to type tokens when the editor opens.
]]--

require('common');
local imgui = require('imgui');

local M = {};

local TYPE_SUMMONS = 'summons';
local TYPE_BEASTS = 'beasts';
local TYPE_WYVERN = 'wyvern';
local TYPE_PUPPET = 'puppet';

local ALL_TYPES = { TYPE_SUMMONS, TYPE_BEASTS, TYPE_WYVERN, TYPE_PUPPET };

local TYPE_ROWS = {
    { token = TYPE_SUMMONS, label = 'Summons' },
    { token = TYPE_BEASTS, label = 'Beasts' },
    { token = TYPE_WYVERN, label = 'Wyvern' },
    { token = TYPE_PUPPET, label = 'Puppet' },
};

local function isKnownTypeToken(s)
    return s == TYPE_SUMMONS or s == TYPE_BEASTS or s == TYPE_WYVERN or s == TYPE_PUPPET;
end

--- True if list contains any legacy per-pet entry (not only the four type tokens).
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
    if entry == TYPE_SUMMONS or entry == TYPE_BEASTS or entry == TYPE_WYVERN or entry == TYPE_PUPPET then
        return entry;
    end
    if entry:match('^avatar:') or entry:match('^spirit:') then
        return TYPE_SUMMONS;
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
        [TYPE_SUMMONS] = false,
        [TYPE_BEASTS] = false,
        [TYPE_WYVERN] = false,
        [TYPE_PUPPET] = false,
    };
    for i = 1, #list do
        local t = legacyEntryImpliedType(list[i]);
        if t then
            seen[t] = true;
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
    if token == TYPE_SUMMONS then
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

function M.CopyAllTypes()
    local out = {};
    for i = 1, #ALL_TYPES do
        out[i] = ALL_TYPES[i];
    end
    return out;
end

--- For crossbar popup init: copy effective list, normalizing legacy shapes to type tokens.
function M.CopyAllowlistForEditor(effList)
    if effList == nil then
        return nil;
    end
    if isLegacyAllowlist(effList) then
        return M.NormalizeAllowlistToTypes(effList);
    end
    local out = {};
    for i = 1, #effList do
        out[i] = effList[i];
    end
    return out;
end

--- Draw allowlist controls inside an open ImGui popup (caller owns BeginPopup/EndPopup).
function M.DrawEditorInPopup(settingsWritable, jobId, saveFn, invalidateFn, afterMutate)
    if not settingsWritable then
        return;
    end

    if settingsWritable.petPalettePetKeys and isLegacyAllowlist(settingsWritable.petPalettePetKeys) then
        settingsWritable.petPalettePetKeys = M.NormalizeAllowlistToTypes(settingsWritable.petPalettePetKeys);
        if afterMutate then afterMutate(settingsWritable); end
        if saveFn then saveFn(); end
        if invalidateFn then invalidateFn(); end
    end

    local custom = settingsWritable.petPalettePetKeys ~= nil;
    local customBuf = { custom };
    if imgui.Checkbox('Only selected pet types##petallow_custom', customBuf) then
        if customBuf[1] then
            settingsWritable.petPalettePetKeys = M.CopyAllTypes();
        else
            settingsWritable.petPalettePetKeys = nil;
        end
        if afterMutate then afterMutate(settingsWritable); end
        if saveFn then saveFn(); end
        if invalidateFn then invalidateFn(); end
    end
    imgui.ShowHelp(
        'When checked, only the types you enable below use separate pet layouts. '
            .. 'Others use your normal job bar. Uncheck for all types (default).'
    );

    if settingsWritable.petPalettePetKeys == nil then
        return;
    end

    if imgui.Button('Select all##petallow') then
        settingsWritable.petPalettePetKeys = M.CopyAllTypes();
        if afterMutate then afterMutate(settingsWritable); end
        if saveFn then saveFn(); end
        if invalidateFn then invalidateFn(); end
    end
    imgui.SameLine();
    if imgui.Button('Clear all##petallow') then
        settingsWritable.petPalettePetKeys = {};
        if afterMutate then afterMutate(settingsWritable); end
        if saveFn then saveFn(); end
        if invalidateFn then invalidateFn(); end
    end

    imgui.Spacing();
    local list = settingsWritable.petPalettePetKeys;
    local gold = { 0.92, 0.78, 0.45, 1.0 };
    for _, row in ipairs(TYPE_ROWS) do
        local on = listContains(list, row.token);
        local b = { on };
        if imgui.Checkbox(row.label .. '##pt_' .. row.token, b) then
            if b[1] then
                settingsWritable.petPalettePetKeys = listAddToken(list, row.token);
            else
                settingsWritable.petPalettePetKeys = listRemoveToken(list, row.token);
            end
            if afterMutate then afterMutate(settingsWritable); end
            if saveFn then saveFn(); end
            if invalidateFn then invalidateFn(); end
        end
    end
end

return M;
