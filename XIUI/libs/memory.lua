--[[
* XIUI Memory Utilities
* Safe memory accessors for game objects
* Provides consistent error handling when accessing game state
]]--

local ffi = require('ffi');
local d3d = require('d3d8');

local M = {};

-- ========================================
-- D3D Device Access
-- ========================================
-- Deferred D3D device access for Linux/Wine compatibility
-- Device may not be ready at module load time under Wine/Proton
local d3d8dev = nil;

function M.GetD3D8Device()
    if d3d8dev == nil then
        d3d8dev = d3d.get_device();
    end
    return d3d8dev;
end

-- ========================================
-- Safe Memory Access Functions
-- ========================================
-- These functions provide consistent error handling when accessing game objects

-- Safe accessor for memory manager
local function GetMemoryManager()
    if AshitaCore == nil then return nil end
    return AshitaCore:GetMemoryManager();
end

-- Safe accessor for player object
function M.GetPlayerSafe()
    local memMgr = GetMemoryManager();
    if memMgr == nil then return nil end
    return memMgr:GetPlayer();
end

-- Safe accessor for party object
function M.GetPartySafe()
    local memMgr = GetMemoryManager();
    if memMgr == nil then return nil end
    return memMgr:GetParty();
end

-- Safe accessor for entity object
function M.GetEntitySafe()
    local memMgr = GetMemoryManager();
    if memMgr == nil then return nil end
    return memMgr:GetEntity();
end

-- Safe accessor for target object
function M.GetTargetSafe()
    local memMgr = GetMemoryManager();
    if memMgr == nil then return nil end
    return memMgr:GetTarget();
end

-- Safe accessor for inventory object
function M.GetInventorySafe()
    local memMgr = GetMemoryManager();
    if memMgr == nil then return nil end
    return memMgr:GetInventory();
end

-- Safe accessor for castbar object
function M.GetCastBarSafe()
    local memMgr = GetMemoryManager();
    if memMgr == nil then return nil end
    return memMgr:GetCastBar();
end

-- Safe accessor for recast object
function M.GetRecastSafe()
    local memMgr = GetMemoryManager();
    if memMgr == nil then return nil end
    return memMgr:GetRecast();
end

-- Safe accessor for pet entity
-- Returns the player's pet entity if one exists, nil otherwise
function M.GetPetSafe()
    local playerEntity = GetPlayerEntity();
    if playerEntity == nil or playerEntity.PetTargetIndex == 0 then
        return nil;
    end
    return GetEntity(playerEntity.PetTargetIndex);
end

return M;
