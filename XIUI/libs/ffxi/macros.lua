--[[
* Addons - Copyright (c) 2025 Ashita Development Team
* Contact: https://www.ashitaxi.com/
* Contact: https://discord.gg/Ashita
*
* This file is part of Ashita.
*
* Ashita is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* Ashita is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with Ashita.  If not, see <https://www.gnu.org/licenses/>.
--]]

require 'common';
require 'win32types';

local chat  = require 'chat';
local ffi   = require 'ffi';

ffi.cdef[[
    typedef bool        (__thiscall*    FsMacroController_canUseMacro_f)(uint32_t);
    typedef bool        (__thiscall*    FsMacroContainer_clearMacro_f)(uint32_t, uint32_t);
    typedef const char* (__thiscall*    FsMacroContainer_getName_f)(uint32_t, uint32_t);
    typedef const char* (__thiscall*    FsMacroContainer_getLine_f)(uint32_t, uint32_t, uint32_t);
    typedef void        (__thiscall*    FsMacroContainer_runMacro_f)(uint32_t, uint8_t, uint8_t);
    typedef int32_t     (__thiscall*    FsMacroContainer_setBook_f)(uint32_t, uint32_t);
    typedef int32_t     (__thiscall*    FsMacroContainer_setPage_f)(uint32_t, uint32_t);
    typedef void        (__cdecl*       FsMacroContainer_setMacro_f)(uint32_t, const char*, const char*);
    // stopMacro only takes 'this' pointer in ecx, no stack parameters (uses plain retn)
    // Use __fastcall to explicitly put obj in ecx without stack manipulation
    typedef void        (__fastcall*    FsMacroContainer_stopMacro_f)(uint32_t);
]];

-- Ashita version compatibility wrapper for memory.find
-- Ashita 4.0: ashita.memory.find('FFXiMain.dll', 0, pattern, offset, scan)
-- Ashita 4.3: ashita.memory.find(0, 0, pattern, offset, scan)
local function memory_find_compat(pattern, offset, scan)
    -- Try 4.0 style first (with module name)
    local result = ashita.memory.find('FFXiMain.dll', 0, pattern, offset, scan);
    if result ~= nil and result ~= 0 then
        return result;
    end
    -- Try 4.3 style (without module name)
    return ashita.memory.find(0, 0, pattern, offset, scan);
end

-- Debug logging (controlled via /xiui debug macroblock)
local DEBUG_ENABLED = false;

local function MacroBlockLog(msg)
    if DEBUG_ENABLED then
        print('[Macro Block] ' .. msg);
    end
end

local macrolib = T{
    ptrs = T{
        -- Macro Objects
        macro       = memory_find_compat('8B0D????????E8????????8B4424105EC38B15????????68', 2, 0),  -- g_pFsMacro
        controller  = memory_find_compat('A3????????EB??891D????????6A50E8', 1, 0),                  -- g_pFsMacroController

        -- Macro Functions
        can_use     = memory_find_compat('66A1????????5633F66685C074??0FBFC08B3485????????8B0D', 0, 0),                                      -- FsMacroController::canUseMacro
        clear       = memory_find_compat('8B44240485C07C??83F8147D??8D1440C1E2052BD08D4C9104E8????????B001', 0, 0),                          -- FsMacroContainer::clearMacro
        get_name    = memory_find_compat('8B44240485C07C??83F8147D??8D1440C1E2052BD08D4C9104E8????????85C0', 0, 0),                          -- FsMacroContainer::getName
        get_line    = memory_find_compat('8B44240485C07C??83F8147D??8B542408528D1440C1E2052BD08D4C9104E8????????C2080033C0C20800', 0, 0),    -- FsMacroContainer::getLine
        run         = memory_find_compat('8A44240453563C018BF175??8A5C24108B4E040FBEC350E8', 0, 0),                                          -- FsMacroContainer::runMacro
        set_book    = memory_find_compat('8B442404568BF18B8EC01D00003BC875??8BC15EC20400', 0, 0),                                            -- FsMacroContainer::setBook
        set_page    = memory_find_compat('568BF1578B7C240C8B86C01D00008D04', 0, 0),                                                          -- FsMacroContainer::setPage
        set         = memory_find_compat('8B442408538B5C24085657508BCBE8????????85C07C??8B', 0, 0),                                          -- FsMacroContainer::setMacro
        stop        = memory_find_compat('C781????????FFFFFFFFC3', 0, 0),                                                                    -- FsMacroContainer::stopMacro
    },
};

if (not macrolib.ptrs:all(function (v) return v ~= nil and v ~= 0; end)) then
    error(chat.header(addon.name):append(chat.error('[lib.macros] Error: Failed to locate required pointer(s).')));
    return;
end

--[[
* Returns the current g_pFsMacro object.
*
* @return {number} The current g_pFsMacro object.
--]]
macrolib.get_fsmacro = function ()
    local addr = ashita.memory.read_uint32(macrolib.ptrs.macro);
    if (addr == 0) then return 0; end
    return ashita.memory.read_uint32(addr);
end

--[[
* Returns the current g_pFsMacroController object.
*
* @return {number} The current g_pFsMacroController object.
--]]
macrolib.get_fscontroller = function ()
    local addr = ashita.memory.read_uint32(macrolib.ptrs.controller);
    if (addr == 0) then return 0; end
    return ashita.memory.read_uint32(addr);
end

--[[
* Returns if a macro can currently be used.
*
* @return {boolean} True if a macro can run, false otherwise.
--]]
macrolib.can_use = function ()
    local obj = macrolib.get_fscontroller();
    if (obj == nil or obj == 0) then return false; end

    return ffi.cast('FsMacroController_canUseMacro_f', macrolib.ptrs.can_use)(obj);
end

--[[
* Clears a macro, removing its name and lines.
*
* @param {number} idx - The index of the macro to clear.
* @return {boolean} True if the macro is cleared, false otherwise.
--]]
macrolib.clear = function (idx)
    local obj = macrolib.get_fsmacro();
    if (obj == nil or obj == 0) then return false; end

    if (idx >= 20) then
        return false;
    end

    return ffi.cast('FsMacroContainer_clearMacro_f', macrolib.ptrs.clear)(obj, idx);
end

--[[
* Returns the name of a macro.
*
* @param {number} idx - The index of the macro.
* @return {string} The name of the macro.
--]]
macrolib.get_name = function (idx)
    local obj = macrolib.get_fsmacro();
    if (obj == nil or obj == 0) then return ''; end

    if (idx >= 20) then
        return '';
    end

    local str = ffi.cast('FsMacroContainer_getName_f', macrolib.ptrs.get_name)(obj, idx);
    if (str == nil) then
        return '';
    end
    str = ffi.string(str);
    if (str == nil) then
        return '';
    end

    return str;
end

--[[
* Returns the requested line of a macro.
*
* @param {number} idx - The index of the macro.
* @param {number} line - The index of the macro line.
* @return {string} The macro line.
--]]
macrolib.get_line = function (idx, line)
    local obj = macrolib.get_fsmacro();
    if (obj == nil or obj == 0) then return ''; end

    if (idx >= 20 or line >= 6) then
        return '';
    end

    local str = ffi.cast('FsMacroContainer_getLine_f', macrolib.ptrs.get_line)(obj, idx, line);
    if (str == nil) then
        return '';
    end
    str = ffi.string(str);
    if (str == nil) then
        return '';
    end

    return str;
end

--[[
* Returns if a macro is currently running.
*
* @return {boolean} True if running, false otherwise.
--]]
macrolib.is_running = function ()
    local obj = macrolib.get_fsmacro();
    if (obj == nil or obj == 0) then return false; end

    return ashita.memory.read_uint32(obj + ashita.memory.read_uint32(macrolib.ptrs.stop + 2)) ~= 0xFFFFFFFF;
end

--[[
* Runs a macro.
*
* @param {number} mod - The modifier key state of the macro. (1 = Control, 2 = Alt)
* @param {number} idx - The index of the macro.
--]]
macrolib.run = function (mod, idx)
    local obj = macrolib.get_fscontroller();
    if (obj == nil or obj == 0) then return; end

    if ((mod ~= 1 and mod ~= 2) or idx >= 20) then
        return;
    end

    ffi.cast('FsMacroContainer_runMacro_f', macrolib.ptrs.run)(obj, mod, idx);
end

--[[
* Sets the current macro book.
*
* @param {number} idx - The index of the macro book to set.
* @return {number} Unused return value.
--]]
macrolib.set_book = function (idx)
    local obj = macrolib.get_fsmacro();
    if (obj == nil or obj == 0) then return 0; end

    if (idx >= 40) then
        return 0;
    end

    return ffi.cast('FsMacroContainer_setBook_f', macrolib.ptrs.set_book)(obj, idx);
end

--[[
* Sets the current macro page.
*
* @param {number} idx - The index of the macro page to set.
* @return {number} Unused return value.
--]]
macrolib.set_page = function (idx)
    local obj = macrolib.get_fsmacro();
    if (obj == nil or obj == 0) then return 0; end

    if (idx >= 10) then
        return 0;
    end

    return ffi.cast('FsMacroContainer_setPage_f', macrolib.ptrs.set_page)(obj, 2 * (idx + 1) - 2);
end

--[[
* Sets a macro.
*
* @param {number} idx - The index of the macro to set.
* @param {string} title - The new title of the macro.
* @param {table} lines - The new lines of the macro.
--]]
macrolib.set = function (idx, title, lines)
    local obj = macrolib.get_fsmacro();
    if (obj == nil or obj == 0) then return; end

    if (idx >= 20) then
        return;
    end
    if (title == nil or type(title) ~= 'string' or title:len() > 8) then
        return;
    end
    if (lines == nil or type(lines) ~= 'table' or lines:len() > 6) then
        return;
    end

    --[[
    Note:   The lines that make up the macro are stored in a single block, separated by null characters. Each line
            is 61 characters long and needs to be padded out in order to function properly. The macro system does
            not clear empty lines or previous lines stored in a macro either, thus the macro needs to be cleared
            first in order to be properly set.
    --]]

    macrolib.clear(idx);

    local str = '';
    lines:each(function (v)
        if (v:len() > 60) then
            str = str .. v:sub(1, 59) .. '\0';
        else
            str = str .. v .. ('\0'):rep(61 - v:len());
        end
    end);

    ffi.cast('FsMacroContainer_setMacro_f', macrolib.ptrs.set)(obj + 380 * idx + 4, title, str);
end

--[[
* Stops the current running macro via direct memory write.
* This is safer than the FFI call which had calling convention issues.
* The stop function writes 0xFFFFFFFF to a specific offset to mark macro as not running.
* @param source Optional string indicating what triggered the stop (e.g., 'controller', 'keyboard')
--]]
macrolib.stop = function (source)
    local obj = macrolib.get_fsmacro();
    if (obj == nil or obj == 0) then
        MacroBlockLog('stop: fsmacro object not available');
        return;
    end

    -- Get the offset from the stop function's pattern (C7 81 [offset] FFFFFFFF C3)
    -- The offset is at ptrs.stop + 2
    local offset = ashita.memory.read_uint32(macrolib.ptrs.stop + 2);
    if offset == nil or offset == 0 then
        MacroBlockLog('stop: could not read offset');
        return;
    end

    -- Check if a macro is actually running before stopping
    local currentValue = ashita.memory.read_uint32(obj + offset);
    local wasRunning = currentValue ~= 0xFFFFFFFF;

    -- Write 0xFFFFFFFF to mark macro as not running (same as what the native function does)
    ashita.memory.write_uint32(obj + offset, 0xFFFFFFFF);

    if wasRunning then
        local sourceInfo = source and (' [' .. source .. ']') or '';
        MacroBlockLog(string.format('stop: halted macro execution%s (was 0x%08X)', sourceInfo, currentValue));
    end
end

-- ============================================
-- Macro Bar Patching System
-- ============================================
--
-- Two modes (always one or the other is active):
--   1. "macrofix" mode (default): Removes macro bar delay, shows instantly
--   2. "hide" mode: Completely hides macro bar UI
--
-- Flow:
--   - On addon load: backup original bytes, apply macrofix (default)
--   - Checkbox OFF: macrofix mode (fast built-in macros)
--   - Checkbox ON: hide mode (macro bar hidden, use stop() to block commands)
--   - On addon unload: restore original bytes
-- ============================================

-- Macrofix patch data - NOPs out the macro bar delay timer
-- These are the core patches that make built-in macros instant (same pattern as hide, different offset)
-- NOTE: Unlike hide patches, macrofix original bytes vary by game version (wildcards in pattern)
-- We cache original bytes on first successful read and store in settings for future restores
local macrofixData = {
    { name = 'macrofix_ctrl', pattern = '2B46103BC3????????????68????????B9', altPattern = '2B4610F990????????????68????????B9', offset = 0x05, count = 0, patch = { 0x90, 0x90, 0x90, 0x90, 0x90, 0x90 }, original = nil, addr = 0, backup = {} },
    { name = 'macrofix_alt', pattern = '2B46103BC3????68????????B9', altPattern = '2B4610F990????68????????B9', offset = 0x05, count = 0, patch = { 0x90, 0x90 }, original = nil, addr = 0, backup = {} },
};

-- Cached original bytes (loaded from/saved to settings)
-- Format: { macrofix_ctrl = {byte1, byte2, ...}, macrofix_alt = {byte1, byte2, ...} }
local cachedOriginalBytes = nil;

-- Hide patch data (nomacrobars) - addresses and backups stored here
-- Also includes alternative patterns for when hide patches are already applied (F990 instead of 3BC3)
local hideData = {
    { name = 'hide_ctrl', pattern = '2B46103BC3????????????68????????B9', altPattern = '2B4610F990????????????68????????B9', offset = 0x03, count = 0, patch = { 0xF9, 0x90 }, original = { 0x3B, 0xC3 }, addr = 0, backup = {} },
    { name = 'hide_alt', pattern = '2B46103BC3????68????????B9', altPattern = '2B4610F990????68????????B9', offset = 0x03, count = 0, patch = { 0xF9, 0x90 }, original = { 0x3B, 0xC3 }, addr = 0, backup = {} },
};

-- Controller hide patch data (from macrofix addon by atom0s)
-- These patches target controller L2/R2 trigger code paths that are separate from keyboard Ctrl/Alt
local hideDataController = {
    -- Pattern [1] - handles controller L2 trigger: change JZ (0x74) to JMP (0xEB)
    { name = 'hide_controller_1', pattern = '83C41084C074??8BCEE8????????84C074??8A460CB9????????3AC3', offset = 0x05, count = 0, patch = { 0xEB }, original = { 0x74 }, addr = 0, backup = {} },

    -- Pattern [2] - handles controller R2 trigger: change JZ (0x74) to JMP (0xEB)
    { name = 'hide_controller_2', pattern = '83C41084C074??8BCEE8????????84C074??807E0C02', offset = 0x05, count = 0, patch = { 0xEB }, original = { 0x74 }, addr = 0, backup = {} },

    -- Pattern [5] - complex jump patch (first instance): JMP +0x9B to skip macro bar activation
    { name = 'hide_controller_5', pattern = '83C41084C0????8BCEE8????????84C0????8A460C84C0????8B461485C0', offset = 0x07, count = 0, patch = { 0xE9, 0x9B, 0x00, 0x00, 0x00, 0xCC, 0xCC }, original = nil, addr = 0, backup = {} },

    -- Pattern [6] - complex jump patch (second instance): JMP +0xCD to skip macro bar activation
    { name = 'hide_controller_6', pattern = '83C41084C0????8BCEE8????????84C0????8A460C84C0????8B461485C0', offset = 0x07, count = 1, patch = { 0xE9, 0xCD, 0x00, 0x00, 0x00, 0xCC, 0xCC }, original = nil, addr = 0, backup = {} },
};

-- Current state
local currentMode = nil;  -- 'macrofix' or 'hide'
local initialized = false;
local macrofixConflictDetected = false;  -- True if NOPs detected but no cache (macrofix addon loaded first)

-- Find a pattern and return the address (0 if not found)
local function findPattern(pattern, offset, count)
    local ptr = ashita.memory.find('FFXiMain.dll', 0, pattern, offset, count);
    if ptr == nil then ptr = 0; end
    return ptr;
end

-- Try to find pattern, with fallback to alternate pattern if provided
local function findPatternWithFallback(pattern, altPattern, offset, count)
    local ptr = findPattern(pattern, offset, count);
    if ptr == 0 and altPattern then
        ptr = findPattern(altPattern, offset, count);
        if ptr ~= 0 then
            MacroBlockLog(string.format('  (found via alt pattern - leftover patch detected)'));
        end
    end
    return ptr;
end

-- Check if all bytes in a table are NOPs (0x90)
local function areAllNops(bytes)
    if not bytes or #bytes == 0 then return false; end
    for _, b in ipairs(bytes) do
        if b ~= 0x90 then return false; end
    end
    return true;
end

-- Load cached original bytes from gConfig
local function loadCachedOriginalBytes()
    if cachedOriginalBytes then return; end
    if gConfig and gConfig.macrofixOriginalBytes then
        cachedOriginalBytes = gConfig.macrofixOriginalBytes;
        MacroBlockLog('  Loaded cached original bytes from settings');
    else
        cachedOriginalBytes = {};
    end
end

-- Save cached original bytes to gConfig and persist to disk
local function saveCachedOriginalBytes()
    if not gConfig then return; end
    gConfig.macrofixOriginalBytes = cachedOriginalBytes;

    -- Persist to disk via settings module
    local settings = require('settings');
    settings.save();
    MacroBlockLog('  Saved original bytes to settings cache (persisted to disk)');
end

-- Initialize: find all patterns and backup original bytes
local function initializePatches()
    if initialized then return; end

    MacroBlockLog('initializePatches: starting...');

    -- First, find hide patterns and check for leftover patches from previous session
    local leftoverHideDetected = false;
    for _, p in ipairs(hideData) do
        p.addr = findPatternWithFallback(p.pattern, p.altPattern, p.offset, p.count);
        if p.addr ~= 0 then
            local byte1 = ashita.memory.read_uint8(p.addr);
            local byte2 = ashita.memory.read_uint8(p.addr + 1);
            local alreadyPatched = (byte1 == p.patch[1] and byte2 == p.patch[2]);

            -- Always use known original bytes for hide patches (we know what they should be)
            p.backup = { p.original[1], p.original[2] };

            if alreadyPatched then
                leftoverHideDetected = true;
                MacroBlockLog(string.format('  %s: found at 0x%08X (LEFTOVER HIDE PATCH DETECTED)', p.name, p.addr));
                -- Restore to original immediately
                ashita.memory.write_uint8(p.addr, p.original[1]);
                ashita.memory.write_uint8(p.addr + 1, p.original[2]);
                MacroBlockLog(string.format('  %s: restored to original bytes', p.name));
            else
                MacroBlockLog(string.format('  %s: found at 0x%08X, bytes: 0x%02X 0x%02X', p.name, p.addr, byte1, byte2));
            end
        else
            MacroBlockLog(string.format('  %s: pattern not found', p.name));
        end
    end

    if leftoverHideDetected then
        MacroBlockLog('  Leftover hide patches cleaned up - searching patterns again...');
    end

    -- Load cached original bytes from settings (for macrofix patches)
    loadCachedOriginalBytes();

    -- Now find macrofix patterns (should work better if we cleaned up hide patches)
    local needCacheSave = false;
    for _, p in ipairs(macrofixData) do
        -- Try primary pattern first, then alt
        p.addr = findPatternWithFallback(p.pattern, p.altPattern, p.offset, p.count);
        if p.addr ~= 0 then
            -- Read current bytes at this address
            local currentBytes = {};
            for i = 1, #p.patch do
                currentBytes[i] = ashita.memory.read_uint8(p.addr + i - 1);
            end

            -- Check if current bytes are all NOPs (leftover from macrofix addon)
            if areAllNops(currentBytes) then
                -- Memory is already patched with NOPs - check cache for original
                if cachedOriginalBytes[p.name] and #cachedOriginalBytes[p.name] == #p.patch then
                    -- Use cached original bytes
                    p.backup = cachedOriginalBytes[p.name];
                    p.original = cachedOriginalBytes[p.name];
                    MacroBlockLog(string.format('  %s: found at 0x%08X, NOPS detected - using cached original: [%s]', p.name, p.addr, table.concat(p.backup, ',')));

                    -- Restore original bytes immediately (so we start from clean state)
                    for i = 1, #p.backup do
                        ashita.memory.write_uint8(p.addr + i - 1, p.backup[i]);
                    end
                    MacroBlockLog(string.format('  %s: restored to original from cache', p.name));
                else
                    -- No cache available - we can't know original bytes
                    p.backup = currentBytes;
                    macrofixConflictDetected = true;
                    MacroBlockLog(string.format('  %s: found at 0x%08X, NOPS detected but NO CACHE available', p.name, p.addr));
                    MacroBlockLog(string.format('    WARNING: Cannot restore to original - macrofix addon may have patched before XIUI'));
                end
            else
                -- Current bytes are NOT NOPs - these are original game bytes
                p.backup = currentBytes;
                p.original = currentBytes;

                -- Cache them for future use
                if not cachedOriginalBytes[p.name] or not areAllNops(currentBytes) then
                    cachedOriginalBytes[p.name] = {};
                    for i = 1, #currentBytes do
                        cachedOriginalBytes[p.name][i] = currentBytes[i];
                    end
                    needCacheSave = true;
                    MacroBlockLog(string.format('  %s: found at 0x%08X, caching original: [%s]', p.name, p.addr, table.concat(p.backup, ',')));
                else
                    MacroBlockLog(string.format('  %s: found at 0x%08X, backup: [%s]', p.name, p.addr, table.concat(p.backup, ',')));
                end
            end
        else
            MacroBlockLog(string.format('  %s: pattern not found', p.name));
        end
    end

    -- Save cache if we found new original bytes
    if needCacheSave then
        saveCachedOriginalBytes();
    end

    -- Warn user if conflict detected
    if macrofixConflictDetected then
        print('[XIUI] WARNING: Macrofix addon conflict detected!');
        print('[XIUI] The macrofix addon was loaded before XIUI and altered memory.');
        print('[XIUI] To fix: 1) /addon unload macrofix  2) Restart game  3) Load XIUI first');
        print('[XIUI] Note: XIUI includes macrofix functionality - you don\'t need both.');
    end

    -- Find controller hide patterns (from macrofix addon - targets L2/R2 code paths)
    MacroBlockLog('  Searching for controller hide patterns in FFXiMain.dll...');
    local controllerPatternsFound = 0;
    for _, p in ipairs(hideDataController) do
        -- Use ashita.memory.find directly with FFXiMain.dll
        local ptr = ashita.memory.find('FFXiMain.dll', 0, p.pattern, p.offset, p.count);
        p.addr = ptr or 0;
        if p.addr ~= 0 then
            -- Backup current bytes
            p.backup = {};
            for i = 1, #p.patch do
                p.backup[i] = ashita.memory.read_uint8(p.addr + i - 1);
            end
            controllerPatternsFound = controllerPatternsFound + 1;
            MacroBlockLog(string.format('  %s: found at 0x%08X, backup: %s', p.name, p.addr, table.concat(p.backup, ',')));
        else
            MacroBlockLog(string.format('  %s: pattern not found (pattern may not exist in this game version)', p.name));
        end
    end
    if controllerPatternsFound == 0 then
        print('[XIUI] Warning: Controller macro patches not found - controller trigger blocking may not work');
        print('[XIUI] This may be normal if game version differs from when patterns were created');
    else
        MacroBlockLog(string.format('  Found %d/%d controller patterns', controllerPatternsFound, #hideDataController));
    end

    initialized = true;
    MacroBlockLog('initializePatches: done');
end

-- Apply macrofix patches (NOPs out delay timer)
local function applyMacrofix()
    local count = 0;
    for _, p in ipairs(macrofixData) do
        if p.addr ~= 0 then
            for i = 1, #p.patch do
                ashita.memory.write_uint8(p.addr + i - 1, p.patch[i]);
            end
            count = count + 1;
            MacroBlockLog(string.format('  %s: applied', p.name));
        end
    end
    return count;
end

-- Apply hide patches
local function applyHide()
    local count = 0;
    for _, p in ipairs(hideData) do
        if p.addr ~= 0 then
            for i = 1, #p.patch do
                ashita.memory.write_uint8(p.addr + i - 1, p.patch[i]);
            end
            count = count + 1;
        end
    end
    return count;
end

-- Restore macrofix locations to original bytes
local function restoreMacrofix()
    for _, p in ipairs(macrofixData) do
        if p.addr ~= 0 and #p.backup > 0 then
            for i = 1, #p.backup do
                ashita.memory.write_uint8(p.addr + i - 1, p.backup[i]);
            end
            MacroBlockLog(string.format('    %s: restored to [%s]', p.name, table.concat(p.backup, ',')));
        else
            MacroBlockLog(string.format('    %s: skipped (addr=0x%08X, backup=%d bytes)', p.name, p.addr, #p.backup));
        end
    end
end

-- Restore hide locations to original bytes (use known original, not backup)
local function restoreHide()
    for _, p in ipairs(hideData) do
        if p.addr ~= 0 and p.original then
            for i = 1, #p.original do
                ashita.memory.write_uint8(p.addr + i - 1, p.original[i]);
            end
        end
    end
end

-- Apply controller hide patches (from macrofix addon - targets L2/R2)
local function applyHideController()
    local count = 0;
    for _, p in ipairs(hideDataController) do
        if p.addr ~= 0 and #p.backup > 0 then
            for i = 1, #p.patch do
                ashita.memory.write_uint8(p.addr + i - 1, p.patch[i]);
            end
            count = count + 1;
            MacroBlockLog(string.format('  %s: applied', p.name));
        end
    end
    return count;
end

-- Restore controller hide patches to original bytes
local function restoreHideController()
    for _, p in ipairs(hideDataController) do
        if p.addr ~= 0 then
            -- Use original if known, otherwise use backup
            local restoreBytes = p.original or p.backup;
            if restoreBytes and #restoreBytes > 0 then
                for i = 1, #restoreBytes do
                    ashita.memory.write_uint8(p.addr + i - 1, restoreBytes[i]);
                end
                MacroBlockLog(string.format('  %s: restored', p.name));
            end
        end
    end
end

--[[
* Initialize the patching system and apply macrofix (default mode).
--]]
macrolib.initialize_patches = function()
    if initialized then return; end
    print('[XIUI] Macro patch system initializing...');
    initializePatches();
    -- Apply macrofix as default
    local count = applyMacrofix();
    if count > 0 then
        currentMode = 'macrofix';
        print(string.format('[XIUI] Macrofix mode active (%d/%d patches applied)', count, #macrofixData));
    else
        print('[XIUI] Warning: No macrofix patches could be applied');
    end
end

--[[
* Sets the macro bar mode.
* @param {string} mode - 'hide' or 'macrofix'
--]]
macrolib.set_macro_bar_mode = function(mode)
    if not initialized then
        initializePatches();
    end

    if mode ~= 'hide' and mode ~= 'macrofix' then
        return false;
    end

    if currentMode == mode then
        MacroBlockLog(string.format('set_macro_bar_mode: already in %s mode, skipping', mode));
        return true;
    end

    MacroBlockLog(string.format('set_macro_bar_mode: switching from %s to %s', tostring(currentMode), mode));

    -- Restore current mode to original
    if currentMode == 'hide' then
        MacroBlockLog('  Restoring hide patches...');
        restoreHide();
        restoreHideController();
    elseif currentMode == 'macrofix' then
        MacroBlockLog('  Restoring macrofix patches...');
        restoreMacrofix();
    end

    -- Apply new mode
    local count = 0;
    local controllerCount = 0;
    if mode == 'hide' then
        MacroBlockLog('  Applying hide patches...');
        count = applyHide();
        controllerCount = applyHideController();
    else
        MacroBlockLog('  Applying macrofix patches...');
        count = applyMacrofix();
    end

    if count > 0 or controllerCount > 0 then
        currentMode = mode;
        MacroBlockLog(string.format('set_macro_bar_mode: switched to %s (%d keyboard + %d controller patches)', mode, count, controllerCount));
        return true;
    end
    return false;
end

macrolib.hide_macro_bar = function()
    return macrolib.set_macro_bar_mode('hide');
end

macrolib.show_macro_bar = function()
    return macrolib.set_macro_bar_mode('macrofix');
end

macrolib.restore_default = function()
    if not initialized then return true; end
    if currentMode == 'hide' then
        restoreHide();
        restoreHideController();  -- Also restore controller patches
    elseif currentMode == 'macrofix' then
        restoreMacrofix();
    end
    currentMode = nil;
    MacroBlockLog('restore_default: restored original game state');
    return true;
end

macrolib.is_macro_bar_hidden = function()
    return currentMode == 'hide';
end

macrolib.get_macro_bar_mode = function()
    return currentMode;
end

macrolib.set_debug_enabled = function(enabled)
    DEBUG_ENABLED = enabled;
    print('[XIUI] Macro block debug mode: ' .. (enabled and 'ON' or 'OFF'));
end

macrolib.is_debug_enabled = function()
    return DEBUG_ENABLED;
end

macrolib.get_diagnostics = function()
    local diag = {
        mode = currentMode,
        hidePatches = {},
        hidePatchesController = {},
        macrofixPatches = {},
        macrofixConflict = macrofixConflictDetected,  -- True if macrofix addon was loaded first
    };

    for _, p in ipairs(hideData) do
        local status = 'not found';
        if p.addr ~= 0 then
            -- Check if patch bytes are currently applied
            local isActive = true;
            for i = 1, #p.patch do
                if ashita.memory.read_uint8(p.addr + i - 1) ~= p.patch[i] then
                    isActive = false;
                    break;
                end
            end
            status = isActive and 'active' or 'ready';
        end
        table.insert(diag.hidePatches, { name = p.name, status = status });
    end

    -- Controller hide patches
    for _, p in ipairs(hideDataController) do
        local status = 'not found';
        if p.addr ~= 0 then
            local isActive = true;
            for i = 1, #p.patch do
                if ashita.memory.read_uint8(p.addr + i - 1) ~= p.patch[i] then
                    isActive = false;
                    break;
                end
            end
            status = isActive and 'active' or 'ready';
        end
        table.insert(diag.hidePatchesController, { name = p.name, status = status });
    end

    for _, p in ipairs(macrofixData) do
        local status = 'not found';
        if p.addr ~= 0 then
            local isActive = true;
            for i = 1, #p.patch do
                if ashita.memory.read_uint8(p.addr + i - 1) ~= p.patch[i] then
                    isActive = false;
                    break;
                end
            end
            status = isActive and 'active' or 'ready';
        end
        table.insert(diag.macrofixPatches, { name = p.name, status = status });
    end

    return diag;
end

return macrolib;