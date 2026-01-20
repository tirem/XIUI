--[[
* XIUI Hotbar - Actions Module
]]--

require('common');
local ffi = require('ffi');
local d3d8 = require('d3d8');
local data = require('modules.hotbar.data');
local horizonSpells = require('modules.hotbar.database.horizonspells');
local textures = require('modules.hotbar.textures');
local macrosLib = require('libs.ffxi.macros');
local palette = require('modules.hotbar.palette');

-- Debug logging (controlled via /xiui debug hotbar)
local DEBUG_ENABLED = false;

local function DebugLog(msg)
    if DEBUG_ENABLED then
        print('[XIUI Hotbar] ' .. msg);
    end
end

--- Set debug mode for actions module
--- @param enabled boolean
local function SetDebugEnabled(enabled)
    DEBUG_ENABLED = enabled;
end

-- ============================================
-- Native Macro Blocking
-- ============================================
-- When "Disable XI Macros" is enabled, we block native macro keys (Ctrl/Alt + number keys)
-- by setting event.blocked = true. This prevents the game from seeing the input.
-- Per atom0s: "Long as you are handling the keys/controller buttons to stop it from
-- popping up it shouldn't need to be patched."

-- Native FFXI macro number keys (0-9 are VK codes 48-57)
local NATIVE_MACRO_NUMBER_KEYS = {
    [48] = true, [49] = true, [50] = true, [51] = true, [52] = true,  -- 0-4
    [53] = true, [54] = true, [55] = true, [56] = true, [57] = true,  -- 5-9
};

-- Arrow keys for macro set switching
local VK_UP = 0x26;
local VK_DOWN = 0x28;

--- Check if a key press would trigger native FFXI macros
--- Native macros are: Ctrl+0-9, Alt+0-9, Ctrl/Alt+Up/Down
--- @param keyCode number Virtual key code
--- @param ctrl boolean Ctrl modifier held
--- @param alt boolean Alt modifier held
--- @return boolean True if this key combo triggers native macros
local function IsNativeMacroKey(keyCode, ctrl, alt)
    -- Must have Ctrl OR Alt (not both, not neither)
    local hasModifier = (ctrl and not alt) or (alt and not ctrl);
    if not hasModifier then
        return false;
    end

    -- Number keys 0-9 trigger macros
    if NATIVE_MACRO_NUMBER_KEYS[keyCode] then
        return true;
    end

    -- Up/Down arrows change macro sets
    if keyCode == VK_UP or keyCode == VK_DOWN then
        return true;
    end

    return false;
end

-- Macro block logging - controlled via /xiui debug macroblock
local function MacroBlockLog(msg)
    if macrosLib.is_debug_enabled() then
        print('[Macro Block] ' .. msg);
    end
end

local M = {};

-- ============================================
-- Modifier Key State (Direct Query)
-- ============================================
-- Queries actual key state from OS instead of tracking events.
-- This prevents "stuck" modifier keys when alt-tabbing.
-- Works on Windows natively and Linux/Mac via Wine's Win32 implementation.

-- Virtual key codes for modifiers
local VK_SHIFT = 0x10;
local VK_CONTROL = 0x11;
local VK_MENU = 0x12;  -- Alt key

-- Try to declare GetAsyncKeyState FFI binding
local getAsyncKeyStateAvailable = false;
local ffiInitOk, ffiInitErr = pcall(function()
    ffi.cdef[[
        short __stdcall GetAsyncKeyState(int vKey);
    ]];
    getAsyncKeyStateAvailable = true;
end);

-- If cdef failed (already defined), try to use it anyway
if not ffiInitOk then
    -- Might already be defined by another addon, try to use it
    local testOk = pcall(function()
        ffi.C.GetAsyncKeyState(VK_CONTROL);
    end);
    getAsyncKeyStateAvailable = testOk;
end

if getAsyncKeyStateAvailable then
    DebugLog('GetAsyncKeyState available for modifier detection');
else
    print('[XIUI] Warning: GetAsyncKeyState not available, modifier keys may get stuck on alt-tab');
end

--- Check if a key is currently held down
--- Queries the actual OS key state - no event tracking needed
--- @param vk number Virtual key code
--- @return boolean True if key is currently pressed
local function IsKeyDown(vk)
    if not getAsyncKeyStateAvailable then
        return false;
    end

    local ok, state = pcall(function()
        return ffi.C.GetAsyncKeyState(vk);
    end);

    if ok and state then
        -- High bit (0x8000) indicates key is currently down
        return bit.band(state, 0x8000) ~= 0;
    end
    return false;
end

--- Get current modifier states by querying actual OS key state
--- This avoids stuck keys from missed release events (e.g., alt-tab)
local function GetModifierStates()
    local ctrl = IsKeyDown(VK_CONTROL);
    local alt = IsKeyDown(VK_MENU);
    local shift = IsKeyDown(VK_SHIFT);

    -- Debug: log when any modifier is detected
    if ctrl or alt or shift then
        DebugLog(string.format('Modifiers: Ctrl=%s Alt=%s Shift=%s',
            tostring(ctrl), tostring(alt), tostring(shift)));
    end

    return ctrl, alt, shift;
end

--- No-op for backwards compatibility
function M.ResetModifierStates()
    -- Not needed - we query actual state directly
end

--- Check if the palette cycling modifier key is currently held
--- Returns: true if the configured palette modifier is active
function M.IsPaletteModifierHeld()
    local globalSettings = gConfig and gConfig.hotbarGlobal;
    if not globalSettings or not globalSettings.paletteCycleEnabled then
        return false;
    end

    local modifier = globalSettings.paletteCycleModifier or 'ctrl';
    local ctrl, alt, shift = GetModifierStates();

    if modifier == 'ctrl' and ctrl and not alt and not shift then
        return true;
    elseif modifier == 'alt' and alt and not ctrl and not shift then
        return true;
    elseif modifier == 'shift' and shift and not ctrl and not alt then
        return true;
    end

    return false;
end

-- Cache for custom icons loaded from disk
local customIconCache = {};

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

--- Check if an action is currently available to use
--- Takes into account job, level, subjob, and level sync
---@param bind table The keybind data with actionType and action fields
---@return boolean isAvailable True if the action can be used
---@return string|nil reason Reason if not available (e.g., "Level 50 required", "Wrong job")
function M.IsActionAvailable(bind)
    if not bind then return true, nil; end

    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then return true, nil; end

    local mainJobId = player:GetMainJob();
    local mainJobLevel = player:GetMainJobLevel();
    local subJobId = player:GetSubJob();
    local subJobLevel = player:GetSubJobLevel();

    -- Guard: If job data is invalid (e.g., during zoning), assume available
    -- Don't cache this result - return nil as reason to signal "don't cache"
    if mainJobId == 0 or mainJobLevel == 0 then
        return true, "pending";  -- "pending" signals not to cache this result
    end

    -- Handle magic spells
    if bind.actionType == 'ma' then
        local spell = GetSpellByName(bind.action);
        if not spell then return true, nil; end  -- Unknown spell, assume available

        local levels = spell.levels;
        if not levels then return true, nil; end  -- No level requirements

        -- Check if main job can cast this spell
        local mainReqLevel = levels[mainJobId];
        local subReqLevel = subJobId and levels[subJobId] or nil;

        -- Check main job first
        if mainReqLevel then
            if mainJobLevel >= mainReqLevel then
                return true, nil;  -- Can cast with main job
            end
        end

        -- Check subjob
        if subReqLevel then
            if subJobLevel >= subReqLevel then
                return true, nil;  -- Can cast with subjob
            end
        end

        -- Spell exists but can't be cast
        if mainReqLevel then
            -- Has the job but not the level
            return false, string.format("Lv%d", mainReqLevel);
        elseif subReqLevel then
            -- Subjob has it but not the level
            return false, string.format("Lv%d", subReqLevel);
        else
            -- Job can't cast this spell at all
            return false, "Job";
        end

    -- Handle job abilities
    elseif bind.actionType == 'ja' then
        -- Check if player has this ability
        local hasAbility = false;
        local resMgr = AshitaCore:GetResourceManager();
        if resMgr then
            for abilityId = 1, 1024 do
                if player:HasAbility(abilityId) then
                    local ability = resMgr:GetAbilityById(abilityId);
                    if ability and ability.Name and ability.Name[1] == bind.action then
                        hasAbility = true;
                        break;
                    end
                end
            end
        end
        if not hasAbility then
            return false, "N/A";
        end

    -- Handle weapon skills
    elseif bind.actionType == 'ws' then
        -- Check if player has this weapon skill
        local hasWS = false;
        local resMgr = AshitaCore:GetResourceManager();
        if resMgr then
            for abilityId = 1, 1024 do
                if player:HasAbility(abilityId) then
                    local ability = resMgr:GetAbilityById(abilityId);
                    if ability and ability.Name and ability.Name[1] == bind.action then
                        -- Verify it's a weapon skill (Type 3)
                        local abilityType = ability.Type and bit.band(ability.Type, 7) or 0;
                        if abilityType == 3 then
                            hasWS = true;
                            break;
                        end
                    end
                end
            end
        end
        if not hasWS then
            return false, "N/A";
        end
    end

    return true, nil;
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
-- CRITICAL: Must cache BOTH found items AND "not found" results to avoid 65535-iteration search every frame
local itemNameToIdCache = {};
local ITEM_NOT_FOUND = -1;  -- Marker for "searched but not found"

--- Load item icon from game resources by item name (slower, uses name lookup)
---@param itemName string The item name to look up
---@return table|nil texture The icon texture
local function LoadItemIconByName(itemName)
    if not itemName or itemName == '' then
        return nil;
    end

    -- Check name->id cache first (includes negative cache for "not found")
    local cachedId = itemNameToIdCache[itemName];
    if cachedId then
        if cachedId == ITEM_NOT_FOUND then
            return nil;  -- Previously searched, item doesn't exist
        end
        return LoadItemIconById(cachedId);
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

    -- CRITICAL: Cache negative result to avoid searching 65535 items every frame!
    itemNameToIdCache[itemName] = ITEM_NOT_FOUND;
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
                    if macro.customIconType then
                        if macro.customIconType == 'spell' and macro.customIconId then
                            icon = textures:Get('spells' .. string.format('%05d', macro.customIconId));
                            iconId = macro.customIconId;
                            if icon then return icon, iconId; end
                        elseif macro.customIconType == 'item' and macro.customIconId then
                            icon = LoadItemIconById(macro.customIconId);
                            iconId = macro.customIconId;
                            if icon then return icon, iconId; end
                        elseif macro.customIconType == 'custom' and macro.customIconPath then
                            -- Check cache first
                            if customIconCache[macro.customIconPath] then
                                return customIconCache[macro.customIconPath], nil;
                            end
                            local customDir = string.format('%saddons\\XIUI\\assets\\hotbar\\custom\\', AshitaCore:GetInstallPath());
                            icon = textures:LoadTextureFromPath(customDir .. macro.customIconPath);
                            if icon then
                                customIconCache[macro.customIconPath] = icon;
                                return icon, nil;
                            end
                        end
                    end
                    break;
                end
            end
        end
    end

    -- Check for custom icon override on the bind itself
    if bind.customIconType then
        if bind.customIconType == 'spell' and bind.customIconId then
            icon = textures:Get('spells' .. string.format('%05d', bind.customIconId));
            iconId = bind.customIconId;
            if icon then return icon, iconId; end
        elseif bind.customIconType == 'item' and bind.customIconId then
            icon = LoadItemIconById(bind.customIconId);
            iconId = bind.customIconId;
            if icon then return icon, iconId; end
        elseif bind.customIconType == 'custom' and bind.customIconPath then
            -- Check cache first
            if customIconCache[bind.customIconPath] then
                return customIconCache[bind.customIconPath], nil;
            end
            -- Load custom icon from assets/hotbar/custom/ directory
            local customDir = string.format('%saddons\\XIUI\\assets\\hotbar\\custom\\', AshitaCore:GetInstallPath());
            icon = textures:LoadTextureFromPath(customDir .. bind.customIconPath);
            if icon then
                customIconCache[bind.customIconPath] = icon;
                return icon, nil;
            end
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
-- Helper to format target for commands (strips existing brackets, adds fresh ones)
-- Handles: "me", "<me>", "<<me>>", "t", "<t>", etc.
local function FormatTargetForCommand(target)
    if not target or target == '' then return '<t>'; end
    -- Strip any existing < > brackets to get clean target name
    local cleaned = target:gsub('[<>]', '');
    if cleaned == '' then return '<t>'; end
    return '<' .. cleaned .. '>';
end

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

    -- Format target consistently (handles both "me" and "<me>" formats)
    local target = FormatTargetForCommand(bind.target);

    -- Build command based on action type
    if bind.actionType == 'ma' then
        -- Magic spell
        command = '/ma "' .. bind.action .. '" ' .. target;
    elseif bind.actionType == 'ja' then
        -- Job ability
        command = '/ja "' .. bind.action .. '" ' .. target;
    elseif bind.actionType == 'ws' then
        -- Weapon skill
        command = '/ws "' .. bind.action .. '" ' .. target;
    elseif bind.actionType == 'item' then
        -- Use item
        command = '/item "' .. bind.action .. '" ' .. target;
    elseif bind.actionType == 'equip' then
        -- Equip item to slot
        local slot = bind.equipSlot or 'main';
        command = '/equip ' .. slot .. ' "' .. bind.action .. '"';
    elseif bind.actionType == 'pet' then
        -- Pet command
        command = '/pet "' .. bind.action .. '" ' .. target;
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

--- Execute a command string (handles multi-line macros with /wait support)
--- Splits by newlines and executes each non-empty line in sequence
--- Properly handles /wait, /pause, /sleep by using Ashita's task scheduler
--- @param commandText string The command text (may contain newlines)
--- @return boolean success Whether any command was executed
function M.ExecuteCommandString(commandText)
    if not commandText or commandText == '' then
        return false;
    end

    -- Collect all lines first
    local lines = {};
    for line in commandText:gmatch('[^\r\n]+') do
        -- Trim whitespace
        line = line:match('^%s*(.-)%s*$');
        if line and line ~= '' then
            table.insert(lines, line);
        end
    end

    if #lines == 0 then
        return false;
    end

    -- Recursive function to execute lines with proper /wait handling
    -- This chains tasks instead of scheduling them all at once
    local function executeNextLine(index)
        if index > #lines then
            return;
        end

        local line = lines[index]:match('^%s*(.-)%s*$');  -- Trim whitespace
        if line == '' then
            ashita.tasks.once(0, function()
                executeNextLine(index + 1);
            end);
            return;
        end

        -- Check for wait/pause/sleep commands
        local waitMatch = line:match('^/wait%s*(%d*%.?%d*)') or
                          line:match('^/pause%s*(%d*%.?%d*)') or
                          line:match('^/sleep%s*(%d*%.?%d*)');

        if waitMatch then
            -- It's a wait command - schedule the next line after the delay
            local delay = tonumber(waitMatch) or 1;
            ashita.tasks.once(delay, function()
                executeNextLine(index + 1);
            end);
        else
            -- PROTECTED command execution
            local ok, err = pcall(function()
                local chatManager = AshitaCore:GetChatManager();
                if chatManager then
                    chatManager:QueueCommand(-1, line);
                end
            end);

            if not ok then
                print('[XIUI] Command execution error: ' .. tostring(err));
            end

            -- Defer next line to avoid blocking
            if index < #lines then
                ashita.tasks.once(0, function()
                    executeNextLine(index + 1);
                end);
            end
        end
    end

    -- Start executing from the first line
    executeNextLine(1);
    return true;
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
    return M.ExecuteCommandString(command);
end

-- Find hotbar and slot that matches the pressed key + modifiers
local function FindMatchingKeybind(keyCode, ctrl, alt, shift)
    -- Defensive: ensure gConfig is a table
    if not gConfig or type(gConfig) ~= 'table' then
        return nil, nil;
    end

    -- Search through all bars for a matching keybind
    for barIndex = 1, 6 do
        local configKey = 'hotbarBar' .. barIndex;
        local barSettings = gConfig[configKey];
        -- Validate barSettings and keyBindings are tables before iterating
        if barSettings and type(barSettings) == 'table'
           and barSettings.enabled
           and barSettings.keyBindings and type(barSettings.keyBindings) == 'table' then
            for slotIndex, binding in pairs(barSettings.keyBindings) do
                if binding and type(binding) == 'table' and binding.key == keyCode then
                    -- Check modifiers match
                    local ctrlMatch = (binding.ctrl or false) == (ctrl or false);
                    local altMatch = (binding.alt or false) == (alt or false);
                    local shiftMatch = (binding.shift or false) == (shift or false);
                    if ctrlMatch and altMatch and shiftMatch then
                        -- Normalize slotIndex to number (JSON may store keys as strings)
                        local normalizedSlot = tonumber(slotIndex) or slotIndex;
                        return barIndex, normalizedSlot;
                    end
                end
            end
        end
    end
    return nil, nil;
end

-- Debug: Always log Ctrl+Arrow presses to diagnose palette cycling issues
-- Set to true via /xiui debug palette
local PALETTE_DEBUG_KEYS = false;

function M.HandleKey(event)
   -- https://learn.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes
   local isRelease = parseKeyEventFlags(event)
   local keyCode = event.wparam;

   -- Get current modifier states (queries actual OS key state)
   local controlPressed, altPressed, shiftPressed = GetModifierStates();

   DebugLog(string.format('HandleKey: keyCode=%d (0x%02X) %s | Ctrl=%s Alt=%s Shift=%s',
       keyCode, keyCode,
       isRelease and 'RELEASE' or 'PRESS',
       tostring(controlPressed), tostring(altPressed), tostring(shiftPressed)));

   -- Debug logging for palette cycling keys (VK_UP=38, VK_DOWN=40)
   if PALETTE_DEBUG_KEYS and (keyCode == 38 or keyCode == 40) and not isRelease then
       local gs = gConfig and gConfig.hotbarGlobal;
       local enabled = gs and gs.paletteCycleEnabled ~= false;
       local mod = gs and gs.paletteCycleModifier or 'ctrl';
       local modMatch = (mod == 'ctrl' and controlPressed and not altPressed and not shiftPressed)
                     or (mod == 'alt' and altPressed and not controlPressed and not shiftPressed)
                     or (mod == 'shift' and shiftPressed and not controlPressed and not altPressed)
                     or (mod == 'none' and not controlPressed and not altPressed and not shiftPressed);
       print(string.format('[XIUI Palette Debug] Key=%d Ctrl=%s Alt=%s Shift=%s | enabled=%s mod=%s modMatch=%s',
           keyCode, tostring(controlPressed), tostring(altPressed), tostring(shiftPressed),
           tostring(enabled), mod, tostring(modMatch)));
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

   -- Check for palette cycling keybind (Ctrl+Up/Down or Alt+Up/Down by default)
   local globalSettings = gConfig and gConfig.hotbarGlobal;
   if globalSettings and globalSettings.paletteCycleEnabled ~= false and not isRelease then
       local prevKey = globalSettings.paletteCyclePrevKey or 38;  -- VK_UP
       local nextKey = globalSettings.paletteCycleNextKey or 40;  -- VK_DOWN
       local modifier = globalSettings.paletteCycleModifier or 'ctrl';

       -- Debug: Log when up/down arrow is pressed with any modifier
       if keyCode == prevKey or keyCode == nextKey then
           DebugLog(string.format('Arrow key detected: keyCode=%d modifier=%s ctrl=%s alt=%s shift=%s',
               keyCode, modifier, tostring(controlPressed), tostring(altPressed), tostring(shiftPressed)));
       end

       -- Check if modifier matches
       local modifierMatch = false;
       if modifier == 'ctrl' and controlPressed and not altPressed and not shiftPressed then
           modifierMatch = true;
       elseif modifier == 'alt' and altPressed and not controlPressed and not shiftPressed then
           modifierMatch = true;
       elseif modifier == 'shift' and shiftPressed and not controlPressed and not altPressed then
           modifierMatch = true;
       elseif modifier == 'none' and not controlPressed and not altPressed and not shiftPressed then
           modifierMatch = true;
       end

       if modifierMatch and (keyCode == prevKey or keyCode == nextKey) then
           if PALETTE_DEBUG_KEYS then
               print('[XIUI Palette Debug] Cycling palettes...');
           end
           -- DOWN = next (+1), UP = previous (-1) to match tHotBar/in-game macro convention
           local direction = (keyCode == nextKey) and 1 or -1;
           local jobId = data.jobId or 1;
           local subjobId = data.subjobId or 0;

           -- Cycle GLOBAL palette (affects all hotbars at once)
           -- NOTE: palette.CyclePalette is now global - barIndex param is ignored
           local result = palette.CyclePalette(1, direction, jobId, subjobId);
           if PALETTE_DEBUG_KEYS then
               print(string.format('[XIUI Palette Debug] Result=%s', tostring(result)));
           end

           if result then
               local logPaletteName = gConfig.hotbarGlobal and gConfig.hotbarGlobal.logPaletteName;
               if logPaletteName == nil then logPaletteName = true; end  -- Default to true
               if logPaletteName then
                   print('[XIUI] Palette: ' .. result);
               end
           else
               if PALETTE_DEBUG_KEYS then
                   print('[XIUI Palette Debug] No palettes to cycle');
               end
           end

           event.blocked = true;
           return;
       end
   end

   -- Check if native macro blocking is enabled
   local blockNativeMacros = gConfig and gConfig.hotbarGlobal and gConfig.hotbarGlobal.disableMacroBars;

   -- Log modifier key presses when macro blocking is enabled (for debugging)
   if blockNativeMacros and not isRelease then
       if keyCode == VK_CONTROL then
           MacroBlockLog('Ctrl pressed - macro bar UI hidden via memory patch');
       elseif keyCode == VK_MENU then
           MacroBlockLog('Alt pressed - macro bar UI hidden via memory patch');
       end
   end

   -- Check if this is a native macro key combo (Ctrl/Alt + number or arrow)
   local isNativeMacroKeyPress = IsNativeMacroKey(keyCode, controlPressed, altPressed);

   -- Stop macro execution when native macro key is pressed
   -- Note: Macro bar UI hiding is handled via memory patch in macrosLib.hide_macro_bar()
   if blockNativeMacros and isNativeMacroKeyPress and not isRelease then
       MacroBlockLog(string.format('Native macro key %d (0x%02X) Ctrl=%s Alt=%s - stopping macro',
           keyCode, keyCode, tostring(controlPressed), tostring(altPressed)));

       -- Stop macro execution via direct memory write
       macrosLib.stop();

       -- Also schedule stops for next few frames to catch delayed execution
       ashita.tasks.once(0, function() macrosLib.stop(); end);
       ashita.tasks.once(0.01, function() macrosLib.stop(); end);
       ashita.tasks.once(0.02, function() macrosLib.stop(); end);
   end

   -- Check if this key is in the blocked game keys list
   local blockedKeys = gConfig and gConfig.hotbarGlobal and gConfig.hotbarGlobal.blockedGameKeys;
   if blockedKeys then
       local ctrlVal = controlPressed or false;
       local altVal = altPressed or false;
       local shiftVal = shiftPressed or false;

       for _, blocked in ipairs(blockedKeys) do
           if blocked.key == keyCode and
              (blocked.ctrl or false) == ctrlVal and
              (blocked.alt or false) == altVal and
              (blocked.shift or false) == shiftVal then
               event.blocked = true;
               DebugLog(string.format('Blocked game key: %d (0x%02X) Ctrl=%s Alt=%s Shift=%s',
                   keyCode, keyCode, tostring(ctrlVal), tostring(altVal), tostring(shiftVal)));
               break;
           end
       end
   end

   -- Find matching keybind from custom key assignments
   local hotbar, slot = FindMatchingKeybind(keyCode, controlPressed, altPressed, shiftPressed);
   DebugLog(string.format('FindMatchingKeybind result: hotbar=%s slot=%s', tostring(hotbar), tostring(slot)));

   if hotbar and slot then
       if isRelease then
           -- Clear pressed state on release (only if it matches what was pressed)
           if currentPressedHotbar == hotbar and currentPressedSlot == slot then
               DebugLog('Key released: hotbar=' .. tostring(hotbar) .. ', slot=' .. tostring(slot));
               currentPressedHotbar = nil;
               currentPressedSlot = nil;
           end
       else
           -- Check if this is a key repeat (same hotbar/slot already pressed)
           if currentPressedHotbar == hotbar and currentPressedSlot == slot then
               return; -- Key repeat - don't re-execute
           end

           DebugLog('Key pressed: hotbar=' .. tostring(hotbar) .. ', slot=' .. tostring(slot));

           -- Set pressed state and execute the keybind
           currentPressedHotbar = hotbar;
           currentPressedSlot = slot;
           M.HandleKeybind(hotbar, slot);
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

    -- Build and execute command (handles multi-line macros)
    local command, _ = M.BuildCommand(slotAction);
    return M.ExecuteCommandString(command);
end

-- Clear the custom icon cache (call when icons may have changed)
function M.ClearCustomIconCache()
    customIconCache = {};
end

--- Set debug mode (called via /xiui debug hotbar)
function M.SetDebugEnabled(enabled)
    SetDebugEnabled(enabled);
end

--- Get debug mode state
function M.IsDebugEnabled()
    return DEBUG_ENABLED;
end

--- Set palette debug mode (called via /xiui debug palette)
function M.SetPaletteDebugEnabled(enabled)
    PALETTE_DEBUG_KEYS = enabled;
    print('[XIUI] Palette key debug: ' .. (enabled and 'ON' or 'OFF'));
    if enabled then
        print('[XIUI] Press Ctrl+Up or Ctrl+Down to see key events');
    end
end

--- Get palette debug mode state
function M.IsPaletteDebugEnabled()
    return PALETTE_DEBUG_KEYS;
end

--- Get item icon for browsing (memory only, no PNG file creation)
--- Use this in the icon picker to avoid creating PNG files for every browsed item
---@param itemId number The item ID to get icon for
---@return table|nil icon The icon texture (with .image but no .path)
function M.GetItemIconForBrowsing(itemId)
    if not itemId or itemId == 0 or itemId == 65535 then
        return nil;
    end

    -- Check cache first (may have been loaded for slot rendering)
    if itemIconCache[itemId] then
        return itemIconCache[itemId];
    end

    -- Load from memory only (no PNG creation)
    -- Note: We don't cache this to avoid memory bloat from browsing
    -- The page-level cache in macropalette.lua handles per-page caching
    return textures:LoadItemIconFromMemory(itemId);
end

return M