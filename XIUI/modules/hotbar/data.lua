--[[
* XIUI hotbar - Data Module
* Reads hotbar state from Ashita memory API
* Memory is single source of truth - no packet handling for pool state
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

-- ============================================
-- Helper Functions
-- ============================================


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

-- Initialize data module
function M.Initialize()

end

-- Clear all state (call on zone change)
function M.Clear()

end

-- Cleanup (call on addon unload)
function M.Cleanup()
    M.Clear();
end

return M;
