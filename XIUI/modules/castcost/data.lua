--[[
* XIUI Cast Cost Data Layer
* Handles menu detection and selected item retrieval via memory reading
*
* Special thanks to Atom0s for assistance with memory signatures and structures.
]]--

require('common');
local ffi = require('ffi');
local gamestate = require('core.gamestate');
local encoding = require('submodules.gdifonts.encoding');

local M = {};

-- Memory signatures for menu selection
local ptrs = T{
    ability_sel     = ashita.memory.find('FFXiMain.dll', 0, '81EC80000000568B35????????8BCE8B463050E8', 0x09, 0),
    magic_sel       = ashita.memory.find('FFXiMain.dll', 0, '81EC80000000568B35????????578BCE8B7E3057', 0x09, 0),
    mount_sel       = ashita.memory.find('FFXiMain.dll', 0, '8B4424048B0D????????50E8????????8B0D????????C7411402000000C3', 0x06, 0),
    getitem_ability = ashita.memory.find('FFXiMain.dll', 0, '8B44240485C07C??3B41447D??8B49208D04C185C075??83C8FFC204008B108B', 0, 0),
    getitem_spell   = ashita.memory.find('FFXiMain.dll', 0, '8B44240485C07C??3B41447D??8B49208D04C185C075??83C8FFC204008B108B', 0, 1),
    getitem         = ashita.memory.find('FFXiMain.dll', 0, '8B44240485C07C??3B41447D??8B49208D04C185C075??83C8FFC204008B00C20400', 0, 0),
};

-- FFI declaration for native listbox function (protected for addon reload)
pcall(function()
    ffi.cdef[[
        typedef int32_t (__thiscall* KaListBox_GetItem_f)(uint32_t, int32_t);
    ]];
end);

-- ============================================
-- Internal: Get KaMenu object pointers
-- ============================================

local function get_KaMenuAbilitySel()
    if ptrs.ability_sel == 0 then return 0; end
    local ptr = ashita.memory.read_uint32(ptrs.ability_sel);
    if (ptr == 0) then return 0; end
    ptr = ashita.memory.read_uint32(ptr);
    return ptr or 0;
end

local function get_KaMenuMagicSel()
    if ptrs.magic_sel == 0 then return 0; end
    local ptr = ashita.memory.read_uint32(ptrs.magic_sel);
    if (ptr == 0) then return 0; end
    ptr = ashita.memory.read_uint32(ptr);
    return ptr or 0;
end

local function get_KaMenuMountSel()
    if ptrs.mount_sel == 0 then return 0; end
    local ptr = ashita.memory.read_uint32(ptrs.mount_sel);
    if (ptr == 0) then return 0; end
    ptr = ashita.memory.read_uint32(ptr);
    return ptr or 0;
end

-- ============================================
-- Menu Detection
-- ============================================

-- Returns 'spell', 'ability', 'mount', or nil
function M.GetActiveMenu()
    local menuName = gamestate.GetMenuName();
    -- Check for magic/spell menu
    if menuName:find('magic') then return 'spell'; end
    -- Check for ability menu
    if menuName:find('ability') then return 'ability'; end
    -- Check for mount menu
    if menuName:find('mount') then return 'mount'; end
    return nil;
end

-- ============================================
-- Get Selected Item IDs
-- Returns -1 if no valid selection
-- ============================================

function M.GetSelectedAbilityId()
    if ptrs.getitem_ability == 0 then return -1; end
    local obj = get_KaMenuAbilitySel();
    if (obj == 0) then return -1; end
    if (ashita.memory.read_int32(obj + 0x40) <= 0) then return -1; end
    local idx = ashita.memory.read_int32(obj + 0x30);
    local func = ffi.cast('KaListBox_GetItem_f', ptrs.getitem_ability);
    return func(obj, idx);
end

function M.GetSelectedSpellId()
    -- Try getitem_spell first, fall back to getitem_ability (same function in some clients)
    local funcPtr = ptrs.getitem_spell;
    if funcPtr == 0 then
        funcPtr = ptrs.getitem_ability;
    end
    if funcPtr == 0 then return -1; end

    local obj = get_KaMenuMagicSel();
    if (obj == 0) then return -1; end
    if (ashita.memory.read_int32(obj + 0x40) <= 0) then return -1; end

    local idx = ashita.memory.read_int32(obj + 0x30);
    local func = ffi.cast('KaListBox_GetItem_f', funcPtr);
    return func(obj, idx);
end

function M.GetSelectedMountId()
    if ptrs.getitem == 0 then return -1; end
    local obj = get_KaMenuMountSel();
    if (obj == 0) then return -1; end
    if (ashita.memory.read_int32(obj + 0x40) <= 0) then return -1; end
    local idx = ashita.memory.read_int32(obj + 0x30);
    local func = ffi.cast('KaListBox_GetItem_f', ptrs.getitem);
    return func(obj, idx);
end

-- ============================================
-- Recast Timer Lookups
-- ============================================

-- Get current spell recast timer (returns remaining time in seconds, or 0 if ready)
function M.GetSpellRecast(spellId)
    if spellId == nil or spellId < 0 then return 0; end

    -- Use Ashita's recast interface
    local recast = GetRecastSafe();
    if recast == nil then return 0; end

    -- GetSpellTimer returns remaining recast in 1/60th of a second
    local timer = recast:GetSpellTimer(spellId);
    if timer == nil or timer <= 0 then return 0; end

    -- Convert from 1/60th seconds to seconds
    return timer / 60;
end

-- Get current ability recast timer (returns remaining time in seconds, or 0 if ready)
function M.GetAbilityRecast(abilityId)
    if abilityId == nil or abilityId < 0 then return 0; end

    local recast = GetRecastSafe();
    if recast == nil then return 0; end

    -- Abilities use a timer ID that maps to a recast slot (0-31)
    -- We need to find which slot this ability uses
    for i = 0, 31 do
        local timerId = recast:GetAbilityTimerId(i);
        if timerId == abilityId then
            local timer = recast:GetAbilityTimer(i);
            if timer ~= nil and timer > 0 then
                -- Convert from 1/60th seconds to seconds
                return timer / 60;
            end
            break;
        end
    end

    return 0;
end

-- ============================================
-- Resource Lookups
-- ============================================

function M.GetSpellInfo(spellId)
    if spellId == nil or spellId < 0 then return nil; end
    local spell = AshitaCore:GetResourceManager():GetSpellById(spellId);
    if spell == nil then return nil; end

    -- Get max recast time (in seconds, converted from 1/4 seconds)
    local maxRecast = (spell.RecastDelay or 0) / 4;
    -- Get current remaining recast time
    local currentRecast = M.GetSpellRecast(spellId);

    return {
        id = spellId,
        name = encoding:ShiftJIS_To_UTF8(spell.Name[1], true),
        mpCost = spell.ManaCost or 0,
        castTime = spell.CastTime or 0,
        recastDelay = spell.RecastDelay or 0,
        skill = spell.Skill or 0,
        maxRecast = maxRecast,
        currentRecast = currentRecast,
    };
end

function M.GetAbilityInfo(abilityId)
    if abilityId == nil or abilityId < 0 then return nil; end
    local ability = AshitaCore:GetResourceManager():GetAbilityById(abilityId);
    if ability == nil then return nil; end

    -- Get max recast time (in seconds, converted from 1/4 seconds)
    local maxRecast = (ability.RecastDelay or 0) / 4;
    -- Get current remaining recast time
    local currentRecast = M.GetAbilityRecast(abilityId);

    return {
        id = abilityId,
        name = encoding:ShiftJIS_To_UTF8(ability.Name[1], true),
        recastDelay = ability.RecastDelay or 0,
        maxRecast = maxRecast,
        currentRecast = currentRecast,
        -- Note: TP cost for weapon skills varies and may need special handling
    };
end

function M.GetMountInfo(mountId)
    if mountId == nil or mountId < 0 then return nil; end
    local mountName = AshitaCore:GetResourceManager():GetString('mounts.names', mountId);
    if mountName == nil then return nil; end

    return {
        id = mountId,
        name = encoding:ShiftJIS_To_UTF8(mountName, true),
    };
end

-- ============================================
-- Convenience: Get current selection based on active menu
-- ============================================

function M.GetCurrentSelection()
    local menuType = M.GetActiveMenu();
    if menuType == nil then return nil, nil; end

    if menuType == 'spell' then
        local spellId = M.GetSelectedSpellId();
        return M.GetSpellInfo(spellId), 'spell';
    elseif menuType == 'ability' then
        local abilityId = M.GetSelectedAbilityId();
        return M.GetAbilityInfo(abilityId), 'ability';
    elseif menuType == 'mount' then
        local mountId = M.GetSelectedMountId();
        return M.GetMountInfo(mountId), 'mount';
    end

    return nil, nil;
end

return M;
