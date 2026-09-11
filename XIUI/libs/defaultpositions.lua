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
-- Magic Burst: upper middle, clear of the target bar and chat
function M.GetMagicBurstPosition()
    local sw, sh = M.GetScreenSize();
    local x = (sw / 2) - 100;
    local y = sh * 0.22;
    return x, y;
end

-- Phantom Roll: above the pet bar, left of the player bar
function M.GetPhantomRollPosition()
    local px, py = M.GetPlayerBarPosition();
    local x = px - 250;
    local y = py - 230;
    return x, y;
end

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

function M.GetSatchelPosition()
    local ix, iy = M.GetInventoryPosition();
    return ix + 40, iy - 40;
end

-- Notifications: center right
function M.GetNotificationsPosition()
    local sw, sh = M.GetScreenSize();
    local x = (sw / 2) + 240;
    local y = (sh / 2) - 150;
    return x, y;
end

-- Blue Magic learned banner: original ActionLearned box, designed at 1920x1080.
-- PNG native size is only used to seed the default window at the letterboxed
-- origin before the texture has loaded.
local BLU_REF_W, BLU_REF_H = 1920, 1080;
local BLU_BOX_W, BLU_BOX_H = 720, 200;
local BLU_BOX_X = (BLU_REF_W - BLU_BOX_W) / 2;
local BLU_BOX_Y = 200;
local BLU_ART_W, BLU_ART_H = 1800, 900;

local function GetBlueMagicLearnedBox(userScale)
    userScale = userScale or 1;
    local sw, sh = M.GetScreenSize();
    local boxW = BLU_BOX_W * (sw / BLU_REF_W) * userScale;
    local boxH = BLU_BOX_H * (sh / BLU_REF_H) * userScale;
    local boxX = BLU_BOX_X * (sw / BLU_REF_W);
    local boxY = BLU_BOX_Y * (sh / BLU_REF_H);
    return boxX, boxY, boxW, boxH;
end

-- Letterbox texW x texH into the design box. Returns draw size, then the
-- top-left that centers that size in the box (used as the default window pos).
function M.FitBlueMagicLearned(texW, texH, userScale)
    local boxX, boxY, boxW, boxH = GetBlueMagicLearnedBox(userScale);
    if not texW or texW <= 0 or not texH or texH <= 0 then
        return boxW, boxH, boxX, boxY;
    end

    local fit = math.min(boxW / texW, boxH / texH);
    local drawW = texW * fit;
    local drawH = texH * fit;
    return drawW, drawH, boxX + (boxW - drawW) / 2, boxY + (boxH - drawH) / 2;
end

function M.GetBlueMagicLearnedPosition()
    local _, _, x, y = M.FitBlueMagicLearned(BLU_ART_W, BLU_ART_H, 1);
    return x, y;
end

-- Treasure Pool: below notifications
function M.GetTreasurePoolPosition()
    local nx, ny = M.GetNotificationsPosition();
    return nx, ny + 200;
end

return M;
