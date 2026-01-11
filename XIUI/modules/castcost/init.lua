--[[
* XIUI Cast Cost Module
* Displays information about the currently selected spell, ability, or mount
* in the game's selection menus (MP cost, cast time, recast, etc.)
]]--

require('common');
require('handlers.helpers');

local data = require('modules.castcost.data');
local display = require('modules.castcost.display');

local castcost = {};

-- ============================================
-- Module Lifecycle
-- ============================================

function castcost.Initialize(settings)
    display.Initialize(settings);
end

function castcost.UpdateVisuals(settings)
    display.UpdateVisuals(settings);
end

function castcost.SetHidden(hidden)
    display.SetHidden(hidden);
end

function castcost.Cleanup()
    display.Cleanup();
end

function castcost.ResetPositions()
    display.ResetPositions();
end

-- ============================================
-- Main Render
-- ============================================

function castcost.DrawWindow(settings)
    -- Check if player is valid
    local player = GetPlayerSafe();
    if player == nil then
        display.SetHidden(true);
        return;
    end

    if player.isZoning then
        display.SetHidden(true);
        return;
    end

    -- Get current selection from active menu
    local itemInfo, itemType = data.GetCurrentSelection();

    -- If no menu is open or no selection, hide
    if itemInfo == nil then
        display.SetHidden(true);
        return;
    end

    -- Get color settings
    local colors = gConfig.colorCustomization.castCost or {};

    -- Render the display
    display.Render(itemInfo, itemType, settings, colors);
end

return castcost;
