--[[
* XIUI Hotbar - Actions Module
]]--

require('common');
local data = require('modules.hotbar.data');
local horizonSpells = require('modules.hotbar.database.horizonspells');
local textures = require('modules.hotbar.textures');

local M = {};

-- ============================================
-- Helper Functions
-- ============================================

--- Find a spell by English name in horizonspells
---@param spellName string The English name of the spell
---@return table|nil The spell data table with en, icon_id, prefix, and id fields
local function GetSpellByName(spellName)
    for _, spell in pairs(horizonSpells) do
        if spell.en == spellName then
            return spell;
        end
    end
    return nil;
end

--- Build command and spell icon from keybind data
--- Centralized function to avoid code duplication between display and key handling
---@param bind table The keybind data with actionType, action, and target fields
---@return string|nil command The command to execute
---@return any|nil spellIcon The spell icon texture (if applicable)
function M.BuildCommand(bind)
    local command = nil;
    local spellIcon = nil;
    
    if not bind then
        return nil, nil;
    end
    
    -- Build command based on action type
    if bind.actionType == 'ma' then
        -- Magic spell
        local spell = GetSpellByName(bind.action);
        if spell then
            spellIcon = textures:Get('spells' .. string.format('%05d', spell.id));
        end
        command = '/ma "' .. bind.action .. '" <' .. bind.target .. '>';
    elseif bind.actionType == 'ja' then
        -- Job ability
        command = '/ja "' .. bind.action .. '" <' .. bind.target .. '>';
    elseif bind.actionType == 'ws' then
        -- Weapon skill
        command = '/ws "' .. bind.action .. '" <' .. bind.target .. '>';
    elseif bind.actionType == 'macro' then
        -- Macro command
        command = bind.action;
    end
    
    return command, spellIcon;
end

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
   elseif keyCode == 189 then -- Minus key
       return '-'
   elseif keyCode == 187 then -- Plus/Equal key
       return '+'
   end
   return tostring(keyCode)
end

-- Determine which hotbar and slot based on modifier keys and key pressed
local function GetHotbarAndSlot(keyStr)
    -- Convert key string to slot number
    local slot = nil;
    if keyStr == '-' then
        slot = 11;
    elseif keyStr == '+' then
        slot = 12;
    else
        slot = tonumber(keyStr);
    end
    
    if not slot or slot < 1 or slot > 12 then
        return nil, nil;
    end
    
    -- Determine hotbar based on modifiers
    local hotbar = 1; -- default (no modifiers)
    if controlPressed and shiftPressed then
        hotbar = 5; -- CS prefix
    elseif controlPressed and altPressed then
        hotbar = 6; -- CA prefix
    elseif shiftPressed then
        hotbar = 4; -- S prefix
    elseif altPressed then
        hotbar = 3; -- A prefix
    elseif controlPressed then
        hotbar = 2; -- C prefix
    end
    
    return hotbar, slot;
end

-- Handle a keybind with the given modifier state
function M.HandleKeybind(hotbar, slot)
    -- Get keybinds for current job (or 'Base' for now)
    local keybinds = data.GetKeybinds('Base');
    if not keybinds then
        return false;
    end
    
    -- Find matching keybind
    for _, bind in ipairs(keybinds) do
        if bind.hotbar == hotbar and bind.slot == slot then
            -- Build and execute command
            local command, _ = M.BuildCommand(bind);
            if command then
                AshitaCore:GetChatManager():QueueCommand(-1, command);
                return true;
            end
        end
    end
    
    return false;
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

   -- Determine hotbar and slot from key and modifiers
   local hotbar, slot = GetHotbarAndSlot(keyStr);
   
   if hotbar and slot then
       -- Try to execute the keybind
       if M.HandleKeybind(hotbar, slot) then
           event.blocked = true;
       end
   end
end



return M