--[[
* XIUI Macro Bar Patch Module
* Disables native macro bar display when Ctrl/Alt keys are held
* Based on nomacrobars addon by jquick (https://github.com/jquick/ashita-nomacrobars)
]]--

require('common');

local M = {};

-- State
local patchedLocations = {};
local isPatched = false;

-- Memory patterns for Ctrl and Alt timer display in FFXiMain.dll
local patterns = {
    { name = 'Ctrl Timer', pattern = '2B46103BC3????????????68????????B9', off = 0x03, patch = { 0xF9, 0x90 } },
    { name = 'Alt Timer', pattern = '2B46103BC3????68????????B9', off = 0x03, patch = { 0xF9, 0x90 } },
};

-- Apply patches to disable macro bar display
function M.Apply()
    if isPatched then return true; end

    local patched = 0;

    for _, p in ipairs(patterns) do
        local scan_ptr = ashita.memory.find('FFXiMain.dll', 0, p.pattern, 0, 0);

        if scan_ptr ~= 0 then
            local patch_addr = scan_ptr + p.off;

            -- Backup original bytes before patching
            local backup = ashita.memory.read_array(patch_addr, #p.patch);
            ashita.memory.write_array(patch_addr, p.patch);

            table.insert(patchedLocations, { addr = patch_addr, backup = backup });
            patched = patched + 1;
        end
    end

    if patched > 0 then
        isPatched = true;
        return true;
    end

    return false;
end

-- Remove patches and restore original bytes
function M.Remove()
    if not isPatched then return; end

    for _, v in ipairs(patchedLocations) do
        if v.backup ~= nil and #v.backup > 0 then
            ashita.memory.write_array(v.addr, v.backup);
        end
    end

    patchedLocations = {};
    isPatched = false;
end

-- Check if patches are currently applied
function M.IsPatched()
    return isPatched;
end

-- Update patch state based on setting
function M.Update(enabled)
    if enabled and not isPatched then
        M.Apply();
    elseif not enabled and isPatched then
        M.Remove();
    end
end

return M;
