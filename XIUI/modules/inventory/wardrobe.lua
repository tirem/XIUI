--[[
    Wardrobe Tracker Module
    Tracks all 8 Wardrobes (container IDs 8, 10-16)
]]

local BaseTracker = require('modules.inventory.base');

-- Container IDs for all Wardrobes in FFXI
local CONTAINER_WARDROBE = 8;
local CONTAINER_WARDROBE2 = 10;
local CONTAINER_WARDROBE3 = 11;
local CONTAINER_WARDROBE4 = 12;
local CONTAINER_WARDROBE5 = 13;
local CONTAINER_WARDROBE6 = 14;
local CONTAINER_WARDROBE7 = 15;
local CONTAINER_WARDROBE8 = 16;

return BaseTracker.Create({
    windowName = 'WardrobeTracker',
    containers = {
        CONTAINER_WARDROBE,
        CONTAINER_WARDROBE2,
        CONTAINER_WARDROBE3,
        CONTAINER_WARDROBE4,
        CONTAINER_WARDROBE5,
        CONTAINER_WARDROBE6,
        CONTAINER_WARDROBE7,
        CONTAINER_WARDROBE8,
    },
    containerLabels = { 'W1', 'W2', 'W3', 'W4', 'W5', 'W6', 'W7', 'W8' },
    -- gConfig.wardrobeEnabled[i] toggles each wardrobe (default all true)
    enabledContainersKey = 'wardrobeEnabled',
    configPrefix = 'wardrobeTracker',
    colorKey = 'wardrobeTracker',
});
