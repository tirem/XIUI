--[[
* Phantom Roll module for XIUI.
]]--

local tracker = require('modules.phantomroll.tracker');
local display = require('modules.phantomroll.display');

local M = {};

local hidden = false;
local previewActive = false;

-- Demo dice only when config is open and no real rolls are up.
local function UpdatePreview()
    local configOpen = showConfig ~= nil and showConfig[1];

    if configOpen and not previewActive and not tracker.HasAny() then
        tracker.Demo();
        previewActive = true;
    elseif not configOpen and previewActive then
        tracker.Clear();
        previewActive = false;
    end

    return previewActive;
end

M.Initialize = function(settings)
    hidden = false;
    previewActive = false;
end

M.DrawWindow = function(settings)
    if hidden or settings == nil then return; end

    if not UpdatePreview() then
        -- No seats: packets create them; 0x63 corrects/clears.
        if not tracker.HasAny() then return; end
        tracker.Sync();
        if not tracker.HasAny() then return; end
    end

    display.DrawWindow(settings);
end

M.HandleActionPacket = function(actionPacket)
    tracker.HandleActionPacket(actionPacket);
end

M.HandleBuffPacket = function(packet)
    tracker.HandleBuffPacket(packet);
end

M.HandleZonePacket = function()
    tracker.Clear();
    previewActive = false;
end

M.SetHidden = function(isHidden)
    hidden = isHidden == true;
end

M.Cleanup = function()
    hidden = false;
    previewActive = false;
    tracker.Clear();
end

M.ResetPositions = display.ResetPositions;

return M;
