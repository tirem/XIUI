--[[
    Inventory Tracker Modules for XIUI
    Provides trackers for various storage containers
]]

local BaseTracker = require('modules.inventory.base');
local inventory = {};

-- Load inventory tracker modules
inventory.inventory = require('modules.inventory.inventory');
inventory.satchel = require('modules.inventory.satchel');
inventory.locker = require('modules.inventory.locker');
inventory.safe = require('modules.inventory.safe');
inventory.storage = require('modules.inventory.storage');
inventory.wardrobe = require('modules.inventory.wardrobe');

-- Export ResetPositions from base tracker (shared by all containers)
inventory.ResetPositions = function()
    BaseTracker.ResetPositions();
end

return inventory;
