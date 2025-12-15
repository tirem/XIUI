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
local abilityRecast = require('libs.abilityrecast');

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
-- Uses shared abilityrecast library for direct memory reading
-- @param timerId: The ability's timer ID (e.g., 173 for Blood Pact: Rage, 174 for Blood Pact: Ward)
function M.GetAbilityRecast(timerId)
    if timerId == nil or timerId < 0 then return 0; end
    return abilityRecast.GetAbilityRecastSeconds(timerId);
end

-- ============================================
-- Ability Info Lookup Table (fallback for abilities where resource data may be wrong)
-- Contains timer IDs and max recast times from PetMe/petbar research
-- maxRecast values are in seconds
-- ============================================
local abilityLookup = {
    -- SMN pet commands
    ['Blood Pact: Rage'] = { timerId = 173, maxRecast = 60 },
    ['Blood Pact: Ward'] = { timerId = 174, maxRecast = 60 },
    ['Apogee'] = { timerId = 108, maxRecast = 60 },
    ['Mana Cede'] = { timerId = 71, maxRecast = 60 },
    -- BST pet commands
    ['Ready'] = { timerId = 102, maxRecast = 30 },
    ['Sic'] = { timerId = 102, maxRecast = 30 },  -- Shares timer with Ready
    ['Reward'] = { timerId = 103, maxRecast = 90 },
    ['Call Beast'] = { timerId = 104, maxRecast = 60 },
    ['Bestial Loyalty'] = { timerId = 104, maxRecast = 60 },  -- Shares timer with Call Beast
    -- DRG pet commands
    ['Call Wyvern'] = { timerId = 163, maxRecast = 1200 },  -- 20 minutes
    ['Spirit Link'] = { timerId = 162, maxRecast = 120 },
    ['Deep Breathing'] = { timerId = 164, maxRecast = 60 },
    ['Steady Wing'] = { timerId = 70, maxRecast = 120 },
    -- PUP pet commands
    ['Activate'] = { timerId = 205, maxRecast = 60 },
    ['Repair'] = { timerId = 206, maxRecast = 180 },
    ['Deploy'] = { timerId = 207, maxRecast = 60 },
    ['Deactivate'] = { timerId = 208, maxRecast = 60 },
    ['Retrieve'] = { timerId = 209, maxRecast = 60 },
    ['Deus Ex Automata'] = { timerId = 115, maxRecast = 60 },
};

-- Track max recast times seen for abilities (like petbar does)
-- This allows the progress bar to fill up correctly even when resource manager has no data
local trackedMaxRecasts = {};

-- Get ability recast info by scanning active recast slots
-- This approach works for all abilities without needing a lookup table
-- Returns: timerId, currentRecast (seconds), maxRecast (seconds)
local function GetAbilityRecastInfo(ability, abilityId)
    local name = encoding:ShiftJIS_To_UTF8(ability.Name[1], true);

    -- First check our lookup table (for known pet commands with specific timer IDs)
    local lookup = name and abilityLookup[name];
    if lookup then
        local currentRecast = abilityRecast.GetAbilityRecastSeconds(lookup.timerId);
        return lookup.timerId, currentRecast, lookup.maxRecast;
    end

    -- For other abilities, scan recast slots to find by ability ID
    local timerId, rawRecast = abilityRecast.FindAbilityRecast(abilityId);
    local currentRecast = (rawRecast > 0) and (rawRecast / 60) or 0;

    -- Get max recast from resource manager
    local maxRecast = (ability.RecastDelay or 0) / 4;  -- Convert from 1/4 seconds

    -- Track max recast times (like petbar does) for accurate progress bar
    if currentRecast > 0 then
        -- Update tracked max if current is higher (ability just used)
        if trackedMaxRecasts[name] == nil or currentRecast > trackedMaxRecasts[name] then
            trackedMaxRecasts[name] = currentRecast;
        end
        -- Use tracked max if resource manager value is missing/lower
        if maxRecast <= 0 or trackedMaxRecasts[name] > maxRecast then
            maxRecast = trackedMaxRecasts[name];
        end
    else
        -- Ability is ready - clear tracked max
        trackedMaxRecasts[name] = nil;
    end

    return timerId, currentRecast, maxRecast;
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

-- Weapon skills have ability IDs in range 1-255 (approximately)
-- Job abilities start at higher IDs (512+)
local function IsWeaponSkillById(abilityId)
    return abilityId >= 1 and abilityId <= 255;
end

function M.GetAbilityInfo(abilityId)
    if abilityId == nil or abilityId < 0 then return nil; end
    local ability = AshitaCore:GetResourceManager():GetAbilityById(abilityId);
    if ability == nil then return nil; end

    -- Get recast info (scans slots for job abilities, uses lookup for pet commands)
    local timerId, currentRecast, maxRecast = GetAbilityRecastInfo(ability, abilityId);

    -- Check if this is a weapon skill by ID range
    local isWeaponSkill = IsWeaponSkillById(abilityId);

    return {
        id = abilityId,
        timerId = timerId,
        name = encoding:ShiftJIS_To_UTF8(ability.Name[1], true),
        recastDelay = ability.RecastDelay or 0,
        maxRecast = maxRecast,
        currentRecast = currentRecast,
        isWeaponSkill = isWeaponSkill,
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
