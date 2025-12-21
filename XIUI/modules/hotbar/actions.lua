--[[
* XIUI Hotbar - Actions Module
]]--

require('common');
local data = require('modules.hotbar.data');

local M = {};


function M.HandleKey(event)
   print("Key pressed wparam: " .. tostring(event.wparam) .. " lparam: " .. tostring(event.lparam)); 
   --https://learn.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes
   if (event.wparam == 49) then -- Key '1' pressed. Should be configureble and mapped later
       event.blocked = true;
       AshitaCore:GetChatManager():QueueCommand(-1, '/ma Cure <t>')
   end
end