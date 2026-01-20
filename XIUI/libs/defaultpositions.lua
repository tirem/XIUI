--[[
* XIUI Default Positions Library
* Computes default window positions based on screen size
* Used for settings reset to provide sensible starting positions
]]--

local imgui = require('imgui');

local M = {};

function M.GetScreenSize()
    local io = imgui.GetIO();
    local sw = io.DisplaySize.x or 1920;
    local sh = io.DisplaySize.y or 1080;
    return sw, sh;
end

-- Exp Bar: bottom center
function M.GetExpBarPosition()
    local sw, sh = M.GetScreenSize();
    local barWidth = 400;
    local x = (sw - barWidth) / 2;
    local y = sh - 45;
    return x, y;
end

-- Player Bar: center, above hotbars
function M.GetPlayerBarPosition()
    local sw, sh = M.GetScreenSize();
    local barWidth = 400;
    local x = (sw - barWidth) / 2;
    local y = sh - 290;
    return x, y;
end

-- Cast Bar: above player bar
function M.GetCastBarPosition()
    local px, py = M.GetPlayerBarPosition();
    return px, py - 70;
end

-- Target Bar: top center
function M.GetTargetBarPosition()
    local sw, sh = M.GetScreenSize();
    local barWidth = 350;
    local x = (sw - barWidth) / 2;
    local y = 50;
    return x, y;
end

-- Pet Bar: left of player bar
function M.GetPetBarPosition()
    local px, py = M.GetPlayerBarPosition();
    local x = px - 220;
    local y = py - 80;
    return x, y;
end

-- Cast Cost: left side
function M.GetCastCostPosition()
    local sw, sh = M.GetScreenSize();
    local x = 50;
    local y = sh / 2;
    return x, y;
end

-- Enemy List: top left
function M.GetEnemyListPosition()
    local x = 15;
    local y = 90;
    return x, y;
end

-- Party List (Party A): bottom right
function M.GetPartyListPosition()
    local sw, sh = M.GetScreenSize();
    local x = sw - 380;
    local y = sh - 340;
    return x, y;
end

-- Party List 2 (Party B): above Party A
function M.GetPartyList2Position()
    local sw, sh = M.GetScreenSize();
    local x = sw - 210;
    local y = sh - 710;
    return x, y;
end

-- Party List 3 (Party C): left of Party B
function M.GetPartyList3Position()
    local sw, sh = M.GetScreenSize();
    local x = sw - 380;
    local y = sh - 710;
    return x, y;
end

-- Gil Tracker: top right
function M.GetGilTrackerPosition()
    local sw, sh = M.GetScreenSize();
    local x = sw - 120;
    local y = 10;
    return x, y;
end

-- Inventory: right of player bar
function M.GetInventoryPosition()
    local sw, sh = M.GetScreenSize();
    local px, py = M.GetPlayerBarPosition();
    local x = px + 520;
    local y = py + 10;
    return x, y;
end

-- Notifications: center right
function M.GetNotificationsPosition()
    local sw, sh = M.GetScreenSize();
    local x = (sw / 2) + 240;
    local y = (sh / 2) - 150;
    return x, y;
end

-- Treasure Pool: below notifications
function M.GetTreasurePoolPosition()
    local nx, ny = M.GetNotificationsPosition();
    return nx, ny + 200;
end

return M;
