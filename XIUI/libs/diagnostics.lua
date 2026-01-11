--[[
* XIUI Diagnostics Module
* Provides resource tracking and debugging utilities
*
* Usage:
*   local diag = require('libs.diagnostics');
*   diag.Enable();  -- Enable tracking
*   diag.PrintStats();  -- Print current resource counts
*   diag.Disable();  -- Disable tracking
]]--

local M = {};

-- ============================================
-- Configuration
-- ============================================
M.enabled = false;
M.logToChat = false;  -- If true, logs to game chat; if false, logs to console

-- ============================================
-- Counters
-- ============================================
M.primitiveCount = 0;
M.primitiveCreated = 0;
M.primitiveDestroyed = 0;
M.textureCount = 0;
M.fontCount = 0;

-- Peak values for debugging
M.peakPrimitiveCount = 0;

-- ============================================
-- Logging
-- ============================================
local function Log(message)
    if not M.enabled then return; end

    local formatted = '[XIUI Diag] ' .. message;
    if M.logToChat and AshitaCore and AshitaCore.GetChatManager then
        AshitaCore:GetChatManager():QueueCommand(-1, '/echo ' .. formatted);
    else
        print(formatted);
    end
end

-- ============================================
-- Primitive Tracking
-- ============================================
local originalPrimitivesNew = nil;
local originalPrimitivesDestroy = nil;

function M.OnPrimitiveCreated()
    M.primitiveCreated = M.primitiveCreated + 1;
    M.primitiveCount = M.primitiveCount + 1;
    if M.primitiveCount > M.peakPrimitiveCount then
        M.peakPrimitiveCount = M.primitiveCount;
    end
    Log('Primitive created. Count: ' .. M.primitiveCount .. ' (Peak: ' .. M.peakPrimitiveCount .. ')');
end

function M.OnPrimitiveDestroyed()
    M.primitiveDestroyed = M.primitiveDestroyed + 1;
    M.primitiveCount = math.max(0, M.primitiveCount - 1);
    Log('Primitive destroyed. Count: ' .. M.primitiveCount);
end

-- ============================================
-- Statistics
-- ============================================
function M.GetStats()
    return {
        primitiveCount = M.primitiveCount,
        primitiveCreated = M.primitiveCreated,
        primitiveDestroyed = M.primitiveDestroyed,
        peakPrimitiveCount = M.peakPrimitiveCount,
        textureCount = M.textureCount,
        fontCount = M.fontCount,
    };
end

function M.PrintStats()
    local stats = M.GetStats();
    print('=== XIUI Diagnostics ===');
    print('Primitives: ' .. stats.primitiveCount .. ' (Peak: ' .. stats.peakPrimitiveCount .. ')');
    print('  Created: ' .. stats.primitiveCreated .. ', Destroyed: ' .. stats.primitiveDestroyed);
    print('Textures: ' .. stats.textureCount);
    print('Fonts: ' .. stats.fontCount);
    print('========================');
end

function M.ResetStats()
    M.primitiveCount = 0;
    M.primitiveCreated = 0;
    M.primitiveDestroyed = 0;
    M.peakPrimitiveCount = 0;
    M.textureCount = 0;
    M.fontCount = 0;
end

-- ============================================
-- Enable/Disable
-- ============================================
function M.Enable()
    M.enabled = true;
    Log('Diagnostics enabled');
end

function M.Disable()
    M.enabled = false;
    print('[XIUI Diag] Diagnostics disabled');
end

function M.IsEnabled()
    return M.enabled;
end

-- ============================================
-- Manual increment/decrement for modules
-- that create resources without wrapping
-- ============================================
function M.TrackPrimitiveCreate()
    if M.enabled then
        M.OnPrimitiveCreated();
    end
end

function M.TrackPrimitiveDestroy()
    if M.enabled then
        M.OnPrimitiveDestroyed();
    end
end

function M.TrackTextureCreate()
    if M.enabled then
        M.textureCount = M.textureCount + 1;
    end
end

function M.TrackTextureDestroy()
    if M.enabled then
        M.textureCount = math.max(0, M.textureCount - 1);
    end
end

function M.TrackFontCreate()
    if M.enabled then
        M.fontCount = M.fontCount + 1;
    end
end

function M.TrackFontDestroy()
    if M.enabled then
        M.fontCount = math.max(0, M.fontCount - 1);
    end
end

return M;
