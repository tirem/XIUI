--[[
* XIUI Hotbar - Actions Module
]]--

require('common');
local ffi = require('ffi');
local d3d8 = require('d3d8');
local data = require('modules.hotbar.data');
local horizonSpells = require('modules.hotbar.database.horizonspells');
local textures = require('modules.hotbar.textures');

local M = {};

-- Mapping from summoning spell names to texture cache keys
-- Spell names (as they appear in-game) -> texture key (as loaded in textures.lua)
local summonSpellToIconKey = {
    -- Avatars
    ['Carbuncle'] = 'summon_Carbuncle',
    ['Ifrit'] = 'summon_Ifrit',
    ['Shiva'] = 'summon_Shiva',
    ['Garuda'] = 'summon_Garuda',
    ['Titan'] = 'summon_Titan',
    ['Ramuh'] = 'summon_Ramuh',
    ['Leviathan'] = 'summon_Leviathan',
    ['Fenrir'] = 'summon_Fenrir',
    ['Diabolos'] = 'summon_Diabolos',
    ['Cait Sith'] = 'summon_CaitSith',
    ['Alexander'] = 'summon_Alexander',
    ['Odin'] = 'summon_Odin',
    ['Atomos'] = 'summon_Atomos',
    ['Siren'] = 'summon_Siren',
    -- Spirits
    ['Fire Spirit'] = 'summon_FireSpirit',
    ['Ice Spirit'] = 'summon_IceSpirit',
    ['Air Spirit'] = 'summon_AirSpirit',
    ['Earth Spirit'] = 'summon_EarthSpirit',
    ['Thunder Spirit'] = 'summon_ThunderSpirit',
    ['Water Spirit'] = 'summon_WaterSpirit',
    ['Light Spirit'] = 'summon_LightSpirit',
    ['Dark Spirit'] = 'summon_DarkSpirit',
};

-- Mapping from pet command names to texture cache keys
local petCommandToIconKey = {
    ['Assault'] = 'ability_Assault',
    ['Release'] = 'ability_Release',
    ['Retreat'] = 'ability_Retreat',
};

-- Mapping from SMN job ability names to texture cache keys
local smnAbilityToIconKey = {
    ['Apogee'] = 'ability_Apogee',
    ['Astral Conduit'] = 'ability_AstralConduit',
    ['Astral Flow'] = 'ability_AstralFlow',
    ["Avatar's Favor"] = 'ability_AvatarsFavor',
    ['Elemental Siphon'] = 'ability_ElementalSiphon',
    ['Mana Cede'] = 'ability_ManaCede',
};

-- Mapping from Trust names to texture cache keys
local trustToIconKey = {
    ['Ajido-Marujido'] = 'trust_ajido-marujido',
    ['Amchuchu'] = 'trust_amchuchu',
    ['Ayame'] = 'trust_ayame',
    ['Cid'] = 'trust_cid',
    ['Curilla'] = 'trust_curilla',
    ['Darrcuiln'] = 'trust_darrcuiln',
    ['Excenmille'] = 'trust_excenmille',
    ['Halver'] = 'trust_halver',
    ['Iron Eater'] = 'trust_iron-eater',
    ['Joachim'] = 'trust_joachim',
    ['King of Hearts'] = 'trust_king-of-hearts',
    ['Koru-Moru'] = 'trust_koru-moru',
    ['Kupipi'] = 'trust_kupipi',
    ['Kuyin Hathdenna'] = 'trust_kuyin-hathdenna',
    ['Lion'] = 'trust_lion',
    ['Makki-Chebukki'] = 'trust_makki-chebukki',
    ['Mildaurion'] = 'trust_mildaurion',
    ['Mnejing'] = 'trust_mnejing',
    ['Morimar'] = 'trust_morimar',
    ['Naja Salaheem'] = 'trust_naja',
    ['Naji'] = 'trust_naji',
    ['Nanaa Mihgo'] = 'trust_nanaa-mihgo',
    ['Ovjang'] = 'trust_ovjang',
    ['Prishe'] = 'trust_prishe',
    ['Qultada'] = 'trust_qultada',
    ['Rahal'] = 'trust_rahal',
    ['Rongelouts'] = 'trust_rongelouts',
    ['Rughadjeen'] = 'trust_rughadjeen',
    ['Sakura'] = 'trust_sakura',
    ['Semih Lafihna'] = 'trust_semih-lafihna',
    ['Shantotto'] = 'trust_shantotto',
    ['Shantotto II'] = 'trust_shantotto-II',
    ['Star Sibyl'] = 'trust_star-sibyl',
    ['Tenzen'] = 'trust_tenzen',
    ['Trion'] = 'trust_trion',
    ['Valaineral'] = 'trust_valaineral',
    ['Volker'] = 'trust_volker',
    ['Yoran-Oran'] = 'trust_yoran-oran',
    ['Zazarg'] = 'trust_zazarg',
    ['Zeid'] = 'trust_zeid',
    ['Zeid II'] = 'trust_zeid-II',
};

-- Mapping from Blue Magic spell names to texture cache keys
local blueMagicToIconKey = {
    ['Battle Dance'] = 'blue_battle_dance',
    ['Blank Gaze'] = 'blue_blank_gaze',
    ['Cocoon'] = 'blue_cocoon',
    ['Foot Kick'] = 'blue_foot_kick',
    ['Grand Slam'] = 'blue_grand_slam',
    ['Head Butt'] = 'blue_headbutt',
    ['Healing Breeze'] = 'blue_healing_breeze',
    ['Jet Stream'] = 'blue_jet_stream',
    ['Light of Penance'] = 'blue_light_of_penance',
    ['Magic Fruit'] = 'blue_magic_fruit',
    ['Metallic Body'] = 'blue_metallic_body',
    ['Power Attack'] = 'blue_power_attack',
    ['Sheep Song'] = 'blue_sheep_song',
    ['Terror Touch'] = 'blue_terror_touch',
    ['Uppercut'] = 'blue_uppercut',
    ['Wild Oats'] = 'blue_wild_oats',
    ['Zephyr Mantle'] = 'blue_zephyr_mantle',
};

-- Mapping from Mount names to texture cache keys
local mountToIconKey = {
    ['Beetle'] = 'mount_beetle',
    ['Bomb'] = 'mount_bomb',
    ['Chocobo'] = 'mount_chocobo',
    ['Crab'] = 'mount_crab',
    ['Crawler'] = 'mount_crawler',
    ['Fenrir'] = 'mount_fenrir',
    ['Magic Pot'] = 'mount_magic_pot',
    ['Moogle'] = 'mount_moogle',
    ['Morbol'] = 'mount_morbol',
    ['Raptor'] = 'mount_raptor',
    ['Red Crab'] = 'mount_red_crab',
    ['Sheep'] = 'mount_sheep',
    ['Tiger'] = 'mount_tiger',
    ['Tulfaire'] = 'mount_tulfaire',
    ['Warmachine'] = 'mount_warmachine',
};

-- Mapping from Rune Fencer abilities to texture cache keys
local runAbilityToIconKey = {
    -- Runes
    ['Ignis'] = 'rune_ignis',
    ['Gelus'] = 'rune_gelus',
    ['Flabra'] = 'rune_flabra',
    ['Tellus'] = 'rune_tellus',
    ['Sulpor'] = 'rune_sulpor',
    ['Unda'] = 'rune_unda',
    ['Lux'] = 'rune_lux',
    ['Tenebrae'] = 'rune_tenebrae',
    -- Abilities
    ['Battuta'] = 'ability_battuta',
    ['Gambit'] = 'ability_gambit',
    ['Liement'] = 'ability_liement',
    ['Pflug'] = 'ability_pflug',
    ['Rayke'] = 'ability_pulse',
    ['Foil'] = 'ability_foil',
};

-- Mapping from other job abilities to texture cache keys
local otherAbilityToIconKey = {
    -- DRG
    ['Jump'] = 'ability_jump',
    ['High Jump'] = 'ability_jump',
    ['Super Jump'] = 'ability_jump',
    -- RDM
    ['Chainspell'] = 'ability_chainspell',
    ['Stymie'] = 'ability_stymie',
    ['Convert'] = 'ability_2hr',
    -- BLM
    ['Elemental Seal'] = 'ability_2hr',
};

local controlPressed = false;
local altPressed = false;
local shiftPressed = false;

-- Track currently pressed hotbar/slot for visual feedback
local currentPressedHotbar = nil;
local currentPressedSlot = nil;

-- Icon cache for items (keyed by item name since we look up by name)
local itemIconCache = {};

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

--- Get MP cost for an action (only applicable to magic spells)
---@param bind table The keybind data with actionType and action fields
---@return number|nil mpCost The MP cost, or nil if not applicable
function M.GetMPCost(bind)
    if not bind then return nil; end
    if bind.actionType ~= 'ma' then return nil; end

    local spell = GetSpellByName(bind.action);
    if spell and spell.mp_cost and spell.mp_cost > 0 then
        return spell.mp_cost;
    end
    return nil;
end

--- Load item icon from game resources by item ID
--- Uses file cache for primitive rendering compatibility
---@param itemId number The item ID
---@return table|nil texture The icon texture with path field for primitive rendering
local function LoadItemIconById(itemId)
    if not itemId or itemId == 0 or itemId == 65535 then
        return nil;
    end

    -- Check cache first - only use if it has a path (for primitive rendering)
    -- If cached without path, try to reload in case PNG is now available
    if itemIconCache[itemId] and itemIconCache[itemId].path then
        return itemIconCache[itemId];
    end

    -- Try to load via file cache (enables primitive rendering)
    local texture = textures:LoadItemIcon(itemId);
    if texture then
        itemIconCache[itemId] = texture;
        return texture;
    end

    -- Fallback to memory loading (no path field, uses ImGui rendering)
    local success, result = pcall(function()
        local device = GetD3D8Device();
        if device == nil then return nil; end

        local resMgr = AshitaCore:GetResourceManager();
        if not resMgr then return nil; end

        local item = resMgr:GetItemById(itemId);
        if item == nil then return nil; end

        if item.Bitmap == nil or item.ImageSize == nil or item.ImageSize <= 0 then
            return nil;
        end

        local dx_texture_ptr = ffi.new('IDirect3DTexture8*[1]');
        if ffi.C.D3DXCreateTextureFromFileInMemoryEx(
            device, item.Bitmap, item.ImageSize,
            0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
            ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED,
            ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT,
            0xFF000000, nil, nil, dx_texture_ptr
        ) == ffi.C.S_OK then
            return {
                image = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', dx_texture_ptr[0])),
                width = 32,  -- FFXI item icons are 32x32
                height = 32,
                -- Note: No 'path' field, will use ImGui fallback in slotrenderer
            };
        end
        return nil;
    end);

    if success and result then
        itemIconCache[itemId] = result;
    end

    return itemIconCache[itemId];
end

-- Cache for item name -> id lookups (populated lazily)
local itemNameToIdCache = {};

--- Load item icon from game resources by item name (slower, uses name lookup)
---@param itemName string The item name to look up
---@return table|nil texture The icon texture
local function LoadItemIconByName(itemName)
    if not itemName or itemName == '' then
        return nil;
    end

    -- Check name->id cache first
    if itemNameToIdCache[itemName] then
        return LoadItemIconById(itemNameToIdCache[itemName]);
    end

    -- Search for item by name (slow, but cached after first find)
    local resMgr = AshitaCore:GetResourceManager();
    if not resMgr then return nil; end

    for itemId = 1, 65535 do
        local item = resMgr:GetItemById(itemId);
        if item and item.Name and item.Name[1] == itemName then
            itemNameToIdCache[itemName] = itemId;
            return LoadItemIconById(itemId);
        end
    end

    return nil;
end

--- Get icon for a bind (separate from command building for use in drag preview)
---@param bind table The keybind data
---@return any|nil icon The icon texture (if available)
---@return number|nil iconId The icon ID (for reference)
function M.GetBindIcon(bind)
    if not bind then
        return nil, nil;
    end

    local icon = nil;
    local iconId = nil;

    -- Check if this slot references a macro - if so, get the macro's current icon
    -- This enables live updates when macro icons are changed in the palette
    if bind.macroRef and gConfig and gConfig.macroDB then
        -- Use stored palette key if available, otherwise fall back to job ID
        local paletteKey = bind.macroPaletteKey or data.jobId or 1;
        local macroDB = gConfig.macroDB[paletteKey];
        if macroDB then
            for _, macro in ipairs(macroDB) do
                if macro.id == bind.macroRef then
                    -- Found the source macro - use its current custom icon if set
                    if macro.customIconType and macro.customIconId then
                        if macro.customIconType == 'spell' then
                            icon = textures:Get('spells' .. string.format('%05d', macro.customIconId));
                            iconId = macro.customIconId;
                            if icon then return icon, iconId; end
                        elseif macro.customIconType == 'item' then
                            icon = LoadItemIconById(macro.customIconId);
                            iconId = macro.customIconId;
                            if icon then return icon, iconId; end
                        end
                    end
                    break;
                end
            end
        end
    end

    -- Check for custom icon override on the bind itself
    if bind.customIconType and bind.customIconId then
        if bind.customIconType == 'spell' then
            icon = textures:Get('spells' .. string.format('%05d', bind.customIconId));
            iconId = bind.customIconId;
            if icon then return icon, iconId; end
        elseif bind.customIconType == 'item' then
            icon = LoadItemIconById(bind.customIconId);
            iconId = bind.customIconId;
            if icon then return icon, iconId; end
        end
    end

    if bind.actionType == 'ma' then
        -- Check for summoning magic first (custom icons)
        local summonIconKey = summonSpellToIconKey[bind.action];
        if summonIconKey then
            icon = textures:Get(summonIconKey);
            if icon then
                local spell = GetSpellByName(bind.action);
                if spell then iconId = spell.id; end
                return icon, iconId;
            end
        end
        -- Check for Trust icons
        local trustIconKey = trustToIconKey[bind.action];
        if trustIconKey then
            icon = textures:Get(trustIconKey);
            if icon then
                local spell = GetSpellByName(bind.action);
                if spell then iconId = spell.id; end
                return icon, iconId;
            end
        end
        -- Check for Blue Magic icons
        local blueIconKey = blueMagicToIconKey[bind.action];
        if blueIconKey then
            icon = textures:Get(blueIconKey);
            if icon then
                local spell = GetSpellByName(bind.action);
                if spell then iconId = spell.id; end
                return icon, iconId;
            end
        end
        -- Magic spell - look up in horizonspells database
        local spell = GetSpellByName(bind.action);
        if spell then
            iconId = spell.id;
            icon = textures:Get('spells' .. string.format('%05d', spell.id));
        end
    elseif bind.actionType == 'ja' then
        -- Check for SMN ability icons first
        local smnIconKey = smnAbilityToIconKey[bind.action];
        if smnIconKey then
            icon = textures:Get(smnIconKey);
            if icon then return icon, iconId; end
        end
        -- Check for RUN ability icons
        local runIconKey = runAbilityToIconKey[bind.action];
        if runIconKey then
            icon = textures:Get(runIconKey);
            if icon then return icon, iconId; end
        end
        -- Check for other job ability icons
        local otherIconKey = otherAbilityToIconKey[bind.action];
        if otherIconKey then
            icon = textures:Get(otherIconKey);
            if icon then return icon, iconId; end
        end
        -- Job ability - try to get from game resources
        local resMgr = AshitaCore:GetResourceManager();
        if resMgr then
            for abilityId = 1, 1024 do
                local ability = resMgr:GetAbilityById(abilityId);
                if ability and ability.Name and ability.Name[1] == bind.action then
                    iconId = abilityId;
                    break;
                end
            end
        end
    elseif bind.actionType == 'pet' then
        -- Check for pet command icons first
        local petIconKey = petCommandToIconKey[bind.action];
        if petIconKey then
            icon = textures:Get(petIconKey);
            if icon then
                return icon, iconId;
            end
        end
    elseif bind.actionType == 'ws' then
        -- Weaponskill - try to get from game resources
        local resMgr = AshitaCore:GetResourceManager();
        if resMgr then
            for wsId = 1, 255 do
                local ability = resMgr:GetAbilityById(wsId + 256);
                if ability and ability.Name and ability.Name[1] == bind.action then
                    iconId = wsId;
                    break;
                end
            end
        end
    elseif bind.actionType == 'item' or bind.actionType == 'equip' then
        -- Item or Equipment - load icon from game resources
        -- Use itemId if available (faster), otherwise fall back to name lookup
        if bind.itemId then
            icon = LoadItemIconById(bind.itemId);
        else
            icon = LoadItemIconByName(bind.action);
        end
    end

    return icon, iconId;
end

--- Build command and icon from keybind data
--- Centralized function to avoid code duplication between display and key handling
---@param bind table The keybind data with actionType, action, and target fields
---@return string|nil command The command to execute
---@return any|nil icon The icon texture (if applicable)
function M.BuildCommand(bind)
    local command = nil;

    if not bind then
        return nil, nil;
    end

    -- Get icon using the helper function
    local icon = M.GetBindIcon(bind);

    -- Build command based on action type
    if bind.actionType == 'ma' then
        -- Magic spell
        command = '/ma "' .. bind.action .. '" <' .. bind.target .. '>';
    elseif bind.actionType == 'ja' then
        -- Job ability
        command = '/ja "' .. bind.action .. '" <' .. bind.target .. '>';
    elseif bind.actionType == 'ws' then
        -- Weapon skill
        command = '/ws "' .. bind.action .. '" <' .. bind.target .. '>';
    elseif bind.actionType == 'item' then
        -- Use item
        command = '/item "' .. bind.action .. '" <' .. bind.target .. '>';
    elseif bind.actionType == 'equip' then
        -- Equip item to slot
        local slot = bind.equipSlot or 'main';
        command = '/equip ' .. slot .. ' "' .. bind.action .. '"';
    elseif bind.actionType == 'pet' then
        -- Pet command
        command = '/pet "' .. bind.action .. '" <' .. bind.target .. '>';
    elseif bind.actionType == 'macro' then
        -- Macro command (raw command or use macroText)
        command = bind.macroText or bind.action;
    end

    return command, icon;
end



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
    -- Use GetKeybindForSlot which checks both user slot actions AND default keybinds
    local bind = data.GetKeybindForSlot(hotbar, slot);
    if not bind then
        return false;
    end

    -- Build and execute command
    local command, _ = M.BuildCommand(bind);
    if command then
        AshitaCore:GetChatManager():QueueCommand(-1, command);
        return true;
    end

    return false;
end

-- Find hotbar and slot that matches the pressed key + modifiers
local function FindMatchingKeybind(keyCode, ctrl, alt, shift)
    -- Search through all bars for a matching keybind
    for barIndex = 1, 6 do
        local configKey = 'hotbarBar' .. barIndex;
        local barSettings = gConfig and gConfig[configKey];
        if barSettings and barSettings.enabled and barSettings.keyBindings then
            for slotIndex, binding in pairs(barSettings.keyBindings) do
                if binding and binding.key == keyCode then
                    -- Check modifiers match
                    local ctrlMatch = (binding.ctrl or false) == (ctrl or false);
                    local altMatch = (binding.alt or false) == (alt or false);
                    local shiftMatch = (binding.shift or false) == (shift or false);
                    if ctrlMatch and altMatch and shiftMatch then
                        return barIndex, slotIndex;
                    end
                end
            end
        end
    end
    return nil, nil;
end

function M.HandleKey(event)
   --print("Key pressed wparam: " .. tostring(event.wparam) .. " lparam: " .. tostring(event.lparam));
   --https://learn.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes

   local isRelease = parseKeyEventFlags(event)
   local keyCode = event.wparam;

   -- Update modifier key states
   if (keyCode == 17 or keyCode == 162 or keyCode == 163) then -- Ctrl keys
       controlPressed = not isRelease
   elseif (keyCode == 18 or keyCode == 164 or keyCode == 165) then -- Alt keys
       altPressed = not isRelease
   elseif (keyCode == 16 or keyCode == 160 or keyCode == 161) then -- Shift keys
       shiftPressed = not isRelease
   end

   -- Check if keybind editor is capturing input
   local hotbarConfig = require('config.hotbar');
   if hotbarConfig.IsCapturingKeybind() then
       if not isRelease then
           if hotbarConfig.HandleKeybindCapture(keyCode, controlPressed, altPressed, shiftPressed) then
               event.blocked = true;
           end
       end
       return;
   end

   -- Find matching keybind from custom key assignments
   local hotbar, slot = FindMatchingKeybind(keyCode, controlPressed, altPressed, shiftPressed);

   if hotbar and slot then
       if isRelease then
           -- Clear pressed state on release (only if it matches what was pressed)
           if currentPressedHotbar == hotbar and currentPressedSlot == slot then
               currentPressedHotbar = nil;
               currentPressedSlot = nil;
           end
       else
           -- Set pressed state and try to execute the keybind
           currentPressedHotbar = hotbar;
           currentPressedSlot = slot;
           if M.HandleKeybind(hotbar, slot) then
               event.blocked = true;
           end
       end
   elseif isRelease then
       -- Clear pressed state on any release when no match
       currentPressedHotbar = nil;
       currentPressedSlot = nil;
   end
end

-- Get currently pressed hotbar index (1-6) or nil
function M.GetPressedHotbar()
    return currentPressedHotbar;
end

-- Get currently pressed slot index (1-12) or nil
function M.GetPressedSlot()
    return currentPressedSlot;
end

--- Execute an action directly from slot data
--- Used by crossbar for controller input
---@param slotAction table The slot action with actionType, action, target, etc.
---@return boolean success Whether the action was executed
function M.ExecuteAction(slotAction)
    if not slotAction then return false; end
    if not slotAction.actionType or not slotAction.action then return false; end

    -- Build and execute command
    local command, _ = M.BuildCommand(slotAction);
    if command then
        AshitaCore:GetChatManager():QueueCommand(-1, command);
        return true;
    end

    return false;
end

return M