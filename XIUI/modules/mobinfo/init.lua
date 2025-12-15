--[[
    Mob Info Module for XIUI
    Main entry point that provides access to both data and display modules
]]

local mobinfo = {};

-- Load sub-modules
mobinfo.data = require('modules.mobinfo.data');
mobinfo.display = require('modules.mobinfo.display');

-- ============================================
-- Module Lifecycle Methods
-- ============================================

-- Initialize the module (called once on addon load)
mobinfo.Initialize = function(settings)
    mobinfo.display.Initialize(settings);
end

-- Update visuals when settings change (fonts, themes, etc.)
mobinfo.UpdateVisuals = function(settings)
    mobinfo.display.UpdateVisuals(settings);
end

-- Main render function (called every frame)
mobinfo.DrawWindow = function(settings)
    mobinfo.display.DrawWindow(settings);
end

-- Hide/show module elements
mobinfo.SetHidden = function(hidden)
    mobinfo.display.SetHidden(hidden);
end

-- Cleanup resources (called on addon unload)
mobinfo.Cleanup = function()
    mobinfo.display.Cleanup();
    mobinfo.data.Cleanup();
end

return mobinfo;
