--[[
* XIUI Hotbar - Actions Module
]]--

require('common');
local data = require('modules.hotbar.data');

local M = {};

local controlPressed = false;
local altPressed = false;
local shiftPressed = false;

-- Parse lParam bits per Keystroke Message Flags:
-- bit 31 - transition state: 0 = key press, 1 = key release
local function parseKeyEventFlags(event)
   local lparam = tonumber(event.lparam) or 0
   local function getBit(val, idx) return math.floor(val / (2^idx)) % 2 end
   return (getBit(lparam, 31) == 1)
end

-- Convert virtual key code to string representation
local function keyCodeToString(keyCode)
   if keyCode >= 48 and keyCode <= 57 then
       return tostring(keyCode - 48) -- Keys 0-9
   elseif keyCode >= 65 and keyCode <= 90 then
       return string.char(keyCode) -- Keys A-Z
   end
   return tostring(keyCode)
end

-- Handle a keybind with the given modifier state
function M.HandleKeybind(keybind)
   if keybind.key and keybind.ctrl == controlPressed and keybind.alt == (altPressed or false) and keybind.shift == (shiftPressed or false) then
       -- Execute the keybind action here
       if keybind.action then
           AshitaCore:GetChatManager():QueueCommand(-1, keybind.action)
           return true
       end
   end
   return false
end

function M.HandleKey(event)
   --print("Key pressed wparam: " .. tostring(event.wparam) .. " lparam: " .. tostring(event.lparam)); 
   --https://learn.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes

   local isRelease = parseKeyEventFlags(event)

   -- Update modifier key states
   if (event.wparam == 17 or event.wparam == 162 or event.wparam == 163) then -- Ctrl keys
       controlPressed = not isRelease
   elseif (event.wparam == 18 or event.wparam == 164 or event.wparam == 165) then -- Alt keys
       altPressed = not isRelease
   elseif (event.wparam == 16 or event.wparam == 160 or event.wparam == 161) then -- Shift keys
       shiftPressed = not isRelease
   end

   if isRelease then
       return
   end

   local keyStr = keyCodeToString(event.wparam)

   -- Define keybinds
   local keybinds = {
       { key = "1", ctrl = true, alt = false, shift = false, action = '/ma "Cure II" <t>' },
       { key = "1", ctrl = false, alt = false, shift = false, action = '/ma "Cure" <t>' },
   }

   -- Check keybinds
   for _, keybind in ipairs(keybinds) do
       if keyStr == keybind.key and M.HandleKeybind(keybind) then
           event.blocked = true
           return
       end
   end
end



return M