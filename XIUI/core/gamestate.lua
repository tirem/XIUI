--[[
* XIUI Game State Detection
* Handles detection of game menus, events, and interface visibility
* Note: Uses RENDER_FLAG_VISIBLE and RENDER_FLAG_HIDDEN globals from helpers.lua
]]--

local M = {};

-- Memory signatures (thanks to Velyn for these!)
local pGameMenu = ashita.memory.find('FFXiMain.dll', 0, "8B480C85C974??8B510885D274??3B05", 16, 0);
local pEventSystem = ashita.memory.find('FFXiMain.dll', 0, "A0????????84C0741AA1????????85C0741166A1????????663B05????????0F94C0C3", 0, 0);
local pInterfaceHidden = ashita.memory.find('FFXiMain.dll', 0, "8B4424046A016A0050B9????????E8????????F6D81BC040C3", 0, 0);

function M.GetMenuName()
    local subPointer = ashita.memory.read_uint32(pGameMenu);
    local subValue = ashita.memory.read_uint32(subPointer);
    if (subValue == 0) then
        return '';
    end
    local menuHeader = ashita.memory.read_uint32(subValue + 4);
    local menuName = ashita.memory.read_string(menuHeader + 0x46, 16);
    return string.gsub(menuName, '\x00', '');
end

function M.GetEventSystemActive()
    if (pEventSystem == 0) then
        return false;
    end
    local ptr = ashita.memory.read_uint32(pEventSystem + 1);
    if (ptr == 0) then
        return false;
    end
    return (ashita.memory.read_uint8(ptr) == 1);
end

function M.GetInterfaceHidden()
    if (pEventSystem == 0) then
        return false;
    end
    local ptr = ashita.memory.read_uint32(pInterfaceHidden + 10);
    if (ptr == 0) then
        return false;
    end
    return (ashita.memory.read_uint8(ptr + 0xB4) == 1);
end

function M.IsMapOpen()
    return string.match(M.GetMenuName(), 'map') ~= nil;
end

function M.CheckLoggedIn()
    local playerIndex = AshitaCore:GetMemoryManager():GetParty():GetMemberTargetIndex(0);
    if playerIndex == 0 then
        return false;
    end
    local entity = AshitaCore:GetMemoryManager():GetEntity();
    local flags = entity:GetRenderFlags0(playerIndex);
    -- Uses globals from helpers.lua
    return (bit.band(flags, RENDER_FLAG_VISIBLE) == RENDER_FLAG_VISIBLE)
       and (bit.band(flags, RENDER_FLAG_HIDDEN) == 0);
end

-- Check if UI should be hidden based on game state
-- @param hideDuringEvents: user setting for hiding during events
-- @param isLoggedIn: current login state
function M.ShouldHideUI(hideDuringEvents, isLoggedIn)
    if (hideDuringEvents and M.GetEventSystemActive()) then
        return true;
    end
    if M.IsMapOpen() then
        return true;
    end
    if M.GetInterfaceHidden() then
        return true;
    end
    if not isLoggedIn then
        return true;
    end
    return false;
end

return M;
