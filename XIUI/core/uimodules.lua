--[[
* XIUI UI Module Registry
* Data-driven module management for initialization, rendering, cleanup, and visibility
]]--

local M = {};

-- Module registry - defines all UI modules and their configuration
-- Each entry contains:
--   module: the required module
--   settingsKey: key in gAdjustedSettings for this module's settings
--   configKey: key in gConfig for visibility (optional)
--   hideOnEvent: whether to hide during events (optional config key)
--   hasSetHidden: whether module has SetHidden function
local registry = {};

function M.Register(name, config)
    registry[name] = config;
end

function M.Get(name)
    return registry[name];
end

function M.GetAll()
    return registry;
end

-- Initialize all registered modules
function M.InitializeAll(gAdjustedSettings)
    for name, entry in pairs(registry) do
        if entry.module.Initialize then
            entry.module.Initialize(gAdjustedSettings[entry.settingsKey]);
        end
    end
end

-- Update visuals for all registered modules
function M.UpdateVisualsAll(gAdjustedSettings)
    for name, entry in pairs(registry) do
        if entry.module.UpdateVisuals then
            entry.module.UpdateVisuals(gAdjustedSettings[entry.settingsKey]);
        end
    end
end

-- Cleanup all registered modules
function M.CleanupAll()
    for name, entry in pairs(registry) do
        if entry.module.Cleanup then
            entry.module.Cleanup();
        end
    end
end

-- Hide all modules that support SetHidden
function M.HideAll()
    for name, entry in pairs(registry) do
        if entry.hasSetHidden and entry.module.SetHidden then
            entry.module.SetHidden(true);
        end
    end
end

-- Check visibility based on config and hide if needed
function M.CheckVisibility(gConfig)
    for name, entry in pairs(registry) do
        if entry.configKey and entry.hasSetHidden then
            if gConfig[entry.configKey] == false then
                entry.module.SetHidden(true);
            end
        end
    end
end

-- Render a single module
-- Returns true if rendered, false if hidden
function M.RenderModule(name, gConfig, gAdjustedSettings, eventSystemActive)
    local entry = registry[name];
    if not entry then return false; end

    -- Check if module should be shown
    local shouldShow = true;
    if entry.configKey then
        shouldShow = gConfig[entry.configKey] ~= false;
    end

    -- Check event hiding
    if shouldShow and entry.hideOnEventKey and eventSystemActive then
        shouldShow = not gConfig[entry.hideOnEventKey];
    end

    if shouldShow then
        if entry.module.DrawWindow then
            entry.module.DrawWindow(gAdjustedSettings[entry.settingsKey]);
        end
        return true;
    else
        if entry.hasSetHidden and entry.module.SetHidden then
            entry.module.SetHidden(true);
        end
        return false;
    end
end

-- Create a visual updater function for a specific module
function M.CreateVisualUpdater(name, saveSettingsFunc, gAdjustedSettings)
    local entry = registry[name];
    if not entry then return function() end; end

    return function()
        saveSettingsFunc();
        if entry.module.UpdateVisuals then
            entry.module.UpdateVisuals(gAdjustedSettings[entry.settingsKey]);
        end
    end
end

return M;
