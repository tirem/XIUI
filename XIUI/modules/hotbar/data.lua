--[[
* XIUI hotbar - Data Module
]]--

require('common');

local M = {};

-- ============================================
-- Constants
-- ============================================

-- M.MAX_POOL_SLOTS = 10;              -- Maximum hotbar slots (0-9)
-- M.POOL_TIMEOUT_SECONDS = 300;       -- 5 minutes pool timeout
-- M.MAX_HISTORY_ITEMS = 20;           -- Maximum items to keep in won history

-- ============================================
-- State
-- ============================================

-- -- Current pool state from memory (slot -> item data)
-- M.poolItems = {};

-- Keybinds cache (job -> keybind entries)
M.keybindsCache = {};

-- ============================================
-- Helper Functions
-- ============================================

-- Get keybinds for a specific job
function M.GetKeybinds(jobName)
    if not jobName then
        return nil;
    end
    return M.keybindsCache[jobName];
end

-- Get all cached keybinds
function M.GetAllKeybinds()
    return M.keybindsCache;
end

-- Check if keybinds are loaded
function M.HasKeybinds()
    return M.keybindsCache and next(M.keybindsCache) ~= nil;
end


-- ============================================
-- Font Storage (created by init.lua, used by display.lua)
-- ============================================

M.allFonts = nil;


-- Set preview mode
function M.SetPreview(enabled)
end

-- Clear all preview state (call when config closes)
function M.ClearPreview()
   
end


-- Clear error message
function M.ClearError()

end


-- ============================================
-- Lifecycle
-- ============================================

-- Parse a keybind entry from array format to object format
local function ParseKeybindEntry(entry)
    if type(entry) ~= 'table' or #entry < 2 then
        return nil;
    end
    
    -- Parse the first element: 'battle 1 1' -> context, hotbar, slot
    local battleStr = entry[1];
    local context, hotbar, slot = battleStr:match('(%w+)%s+(%d+)%s+(%d+)');
    
    local parsed = {
        context = context or 'battle',
        hotbar = tonumber(hotbar) or 1,
        slot = tonumber(slot) or 1,
        actionType = entry[2],           -- 'ma', 'ja', 'ws', 'macro', etc.
        action = entry[3],                -- Spell/ability/ws name
        target = entry[4],                -- 'stpc', 'stnpc', 'me', 't', etc.
        displayName = entry[5] or entry[3],  -- Display name (defaults to action if not provided)
        extraType = entry[6],             -- Optional: 'item', texture name, etc.
        raw = entry                       -- Keep original array for reference
    };
    
    return parsed;
end

-- Initialize data module
function M.Initialize()
    -- Clear any existing cache
    M.keybindsCache = {};
    
    -- Get the path to the keybinds file
    local addonPath = AshitaCore:GetInstallPath();
    local keybindsPath = string.format('%saddons\\XIUI\\modules\\hotbar\\keybinds\\whm.lua', addonPath);
    
    -- Load the keybinds file
    local success, result = pcall(function()
        -- Create a temporary global to capture the keybinds
        keybinds_job = {};
        
        -- Load and execute the file
        local chunk, err = loadfile(keybindsPath);
        if chunk then
            local keybinds = chunk();
            if keybinds then
                -- Store the returned keybinds
                keybinds_job = keybinds;
            end
        else
            print(string.format('[XIUI Hotbar] Error loading keybinds file: %s', err or 'unknown error'));
            return;
        end
        
        -- Parse the keybinds into structured objects
        for jobName, binds in pairs(keybinds_job) do
            if type(binds) == 'table' then
                local parsedBinds = {};
                for i, entry in ipairs(binds) do
                    local parsed = ParseKeybindEntry(entry);
                    if parsed then
                        table.insert(parsedBinds, parsed);
                    end
                end
                M.keybindsCache[jobName] = parsedBinds;
            end
        end
        
        -- Clean up the temporary global
        keybinds_job = nil;
    end);
    
    if not success then
        --print(string.format('[XIUI Hotbar] Failed to load keybinds: %s', result or 'unknown error'));
        M.keybindsCache = {};
    end
    
end

-- Clear all state (call on zone change)
function M.Clear()
    -- Note: We keep keybindsCache intact on zone change
    -- as keybinds don't need to be reloaded
end

-- Cleanup (call on addon unload)
function M.Cleanup()
    M.Clear();
end

return M;
