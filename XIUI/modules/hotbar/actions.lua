--[[
* XIUI Hotbar - Actions Module
]]--

require('common');
local ffi = require('ffi');
local d3d8 = require('d3d8');
local data = require('modules.hotbar.data');
local horizonSpells = require('modules.hotbar.database.horizonspells');
local petregistry = require('modules.hotbar.petregistry');
local textures = require('modules.hotbar.textures');
local customiconresolve = require('modules.hotbar.customiconresolve');
local macrosLib = require('libs.ffxi.macros');
local palette = require('modules.hotbar.palette');
local macroparse = require('modules.hotbar.macroparse');
local universalTwoHour = require('modules.hotbar.universal_two_hour');
-- Lazy session-cached name->id hashmaps for spells/abilities/items. Used to replace the
-- O(65535) item scan in LoadItemIconByName below (#17 in audit table). Both 1.8.0 and
-- Ferris kept this module but neither propagated it into actions.lua's item lookup.
local actiondb = require('modules.hotbar.actiondb');

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

-- Negative-result cache: keyed strings for which GetBindIcon already returned nil.
-- Skips the lookup work (hashmap probes, GetSpellByName, name->id scans) on subsequent
-- cache misses in display.iconCache. Invalidated whenever an upstream cache that affects
-- icon resolution is wiped (job/pet/palette change, macroDB edit).
local noIconCache = {};

-- Build a key for noIconCache from the fields GetBindIcon branches on.
-- Includes macroRef + recastSource* so macro-recast overrides (which can change icon
-- resolution per Ferris's macro-aware paths) invalidate the negative result.
local function buildNoIconKey(bind)
    if not bind then return nil; end
    local key = (bind.actionType or '') .. ':' .. (bind.action or '');
    if bind.customIconType or bind.customIconId or bind.customIconPath then
        key = key .. ':ci:' .. (bind.customIconType or '')
                  .. ':' .. tostring(bind.customIconId or '')
                  .. ':' .. (bind.customIconPath or '');
    end
    if bind.macroRef then
        key = key .. ':mr:' .. tostring(bind.macroRef);
    end
    if bind.recastSourceType or bind.recastSourceAction then
        key = key .. ':rs:' .. (bind.recastSourceType or '')
                  .. ':' .. (bind.recastSourceAction or '');
    end
    return key;
end

--- After LoadTextureFromPath: use in-memory D3D texture for hotbar (see slotrenderer icon branch).
--- File-path primitives can re-hit disk every frame; ImGui AddImage uses the loaded texture only.
local function finalizeCustomIconTextureForHotbar(icon)
    if not icon or not icon.image then
        return icon;
    end
    local texture_ptr = ffi.cast('IDirect3DTexture8*', icon.image);
    local _, desc = texture_ptr:GetLevelDesc(0);
    if desc ~= nil then
        icon.width = desc.Width;
        icon.height = desc.Height;
    else
        icon.width = icon.width or 40;
        icon.height = icon.height or 40;
    end
    icon.path = nil;
    return icon;
end

--- Icons bundled under addons/XIUI/ (not assets/hotbar/custom/). Path uses forward slashes; normalized for Windows load.
local xiuiBundledAssetIconCache = {};

local function loadXiuiBundledAssetIcon(relUnderXiui)
    if not relUnderXiui or relUnderXiui == '' then
        return nil;
    end
    local norm = relUnderXiui:gsub('/', '\\');
    if xiuiBundledAssetIconCache[norm] then
        return xiuiBundledAssetIconCache[norm];
    end
    local base = AshitaCore:GetInstallPath();
    local full = string.format('%saddons\\XIUI\\%s', base, norm);
    local icon = textures:LoadTextureFromPath(full);
    if not icon and relUnderXiui:find('/') then
        full = string.format('%saddons\\XIUI\\%s', base, relUnderXiui:gsub('/', '\\'));
        icon = textures:LoadTextureFromPath(full);
    end
    if icon then
        finalizeCustomIconTextureForHotbar(icon);
        xiuiBundledAssetIconCache[norm] = icon;
    end
    return icon;
end

--- Load a PNG under assets/hotbar/custom/ by relative path. Retries with / → \\ for D3DX on Windows.
--- Caches by the stored relPath string (as in config / picker).
local function loadCustomIconByRelativePath(relPath)
    if not relPath or relPath == '' then
        return nil;
    end
    if customIconCache[relPath] then
        return customIconCache[relPath];
    end
    local customDir = string.format('%saddons\\XIUI\\assets\\hotbar\\custom\\', AshitaCore:GetInstallPath());
    local full = customDir .. relPath;
    local icon = textures:LoadTextureFromPath(full);
    if not icon and relPath:find('/') then
        full = customDir .. relPath:gsub('/', '\\');
        icon = textures:LoadTextureFromPath(full);
    end
    if icon then
        finalizeCustomIconTextureForHotbar(icon);
        customIconCache[relPath] = icon;
    end
    return icon;
end

--- Shared D3D texture for a PNG under assets/hotbar/custom/ (picker + hotbar use one cache).
function M.GetCustomHotbarIconTexture(relPath)
    return loadCustomIconByRelativePath(relPath);
end

--- Load a PNG from assets/hotbar/custom/ using the same name→file rules as the macro icon picker.
local function TryLoadCustomHotbarIconByActionName(actionName)
    if not actionName or actionName == '' then
        return nil;
    end
    local rel = customiconresolve.FindRelPathForActionName(actionName, 'all');
    if not rel or rel == '' then
        return nil;
    end
    return loadCustomIconByRelativePath(rel);
end
-- Built-in type defaults under addons/XIUI/assets/icons/ (ma.png, ja.png, macro.png, refresh.png, …)
local xiuiDefaultIconCache = {};

local function LoadXiuiDefaultIcon(stem)
    if not stem or stem == '' then
        stem = 'refresh';
    end
    if xiuiDefaultIconCache[stem] then
        return xiuiDefaultIconCache[stem];
    end
    local path = string.format('%saddons\\XIUI\\assets\\icons\\%s.png', AshitaCore:GetInstallPath(), stem);
    local icon = textures:LoadTextureFromPath(path);
    if icon then
        xiuiDefaultIconCache[stem] = icon;
    end
    return icon;
end

--- Load a PNG from addons/XIUI/assets/icons/{stem}.png (same cache as xiui_default icons).
function M.LoadXiuiAssetIcon(stem)
    return LoadXiuiDefaultIcon(stem);
end

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

-- Only one macro flow runs at a time; starting a new one cancels the previous.
local activeMacroId = 0;

-- Icon cache for items (keyed by item name since we look up by name)
local itemIconCache = {};

-- ============================================
-- Helper Functions
-- ============================================

--- Case-insensitive compare for spell/ability/item display names from game data or user input.
local function NameEqualsI(a, b)
    if a == nil or b == nil then
        return false;
    end
    return string.lower(tostring(a)) == string.lower(tostring(b));
end

--- Look up in a string-keyed map: exact key first, then case-insensitive match on keys.
local function LookupStringKeyInsensitive(map, key)
    if not map or key == nil or key == '' then
        return nil;
    end
    local v = map[key];
    if v ~= nil then
        return v;
    end
    local needle = string.lower(tostring(key));
    for mk, val in pairs(map) do
        if type(mk) == 'string' and string.lower(mk) == needle then
            return val;
        end
    end
    return nil;
end

--- Find a spell by English name in horizonspells (exact match; used for MP cost, availability, etc.)
---@param spellName string The English name of the spell
---@return table|nil The spell data table with en, icon_id, prefix, and id fields
-- O(1) lookup from English spell name -> horizonSpells entry. Built lazily on first use.
-- NOTE: horizonSpells has duplicate entries for the same English name (different prefixes —
-- e.g. /ma vs /magic vs blood pact). Builders below preserve the FIRST match found; for
-- prefix/action-type-specific resolution use GetSpellByNameForIcon (case-insensitive) or
-- GetSpellIndexForMa (Horizon recast index).
local spellByNameLookup = nil;

local function buildSpellByNameLookup()
    spellByNameLookup = {};
    for _, spell in pairs(horizonSpells) do
        if spell.en and spellByNameLookup[spell.en] == nil then
            spellByNameLookup[spell.en] = spell;
        end
    end
end

local function GetSpellByName(spellName)
    if not spellName or spellName == '' then
        return nil;
    end
    if not spellByNameLookup then buildSpellByNameLookup(); end
    return spellByNameLookup[spellName];
end

--- Horizon spell rows that are "school magic" (/ma) — never use these for /pet command icons (blood pact shares names).
local function horizonTypeIsSchoolMagicSpellRow(t)
    t = t or '';
    return t == 'WhiteMagic' or t == 'BlackMagic' or t == 'BlueMagic';
end

--- Case-insensitive spell lookup for icons / palette. When several rows share `en`, pick by action context.
--- For `pet`, rows that are only WM/BM/BLU are ignored so /pet does not show the /ma icon (e.g. Ramuh vs spell "Thunder II").
---@param actionType string|nil 'ma'|'pet'|nil (nil treated like 'ma' for single-match rows)

-- Case-insensitive multimap: lowercase English name -> list of horizonSpells rows.
-- Built lazily on first GetSpellByNameForIcon call. Matches the 1.8.0 perf pattern used
-- for spellByNameLookup (case-sensitive single-match): both replace O(n) scans with O(1)
-- hashmap probes. Multiple entries per key are preserved because the caller filters by
-- actionType context (pet vs ma vs blood pact) below.
local spellsByLowerNameLookup = nil;

local function buildSpellsByLowerNameLookup()
    spellsByLowerNameLookup = {};
    for _, spell in pairs(horizonSpells) do
        if spell.en then
            local k = string.lower(spell.en);
            local list = spellsByLowerNameLookup[k];
            if not list then
                list = {};
                spellsByLowerNameLookup[k] = list;
            end
            list[#list + 1] = spell;
        end
    end
end

local function GetSpellByNameForIcon(spellName, actionType)
    if not spellName or spellName == '' then
        return nil;
    end
    if not spellsByLowerNameLookup then buildSpellsByLowerNameLookup(); end
    local needle = string.lower(spellName);
    local matches = spellsByLowerNameLookup[needle];
    if not matches then
        return nil;
    end
    -- Copy into a local working list so we can sort without mutating the cached one.
    local list = {};
    for i = 1, #matches do list[i] = matches[i]; end
    if #list == 0 then
        return nil;
    end

    local ctx = actionType or 'ma';

    if #list == 1 then
        local sp = list[1];
        if ctx == 'pet' and horizonTypeIsSchoolMagicSpellRow(sp.type) then
            return nil;
        end
        return sp;
    end

    -- Blood pact / avatar pact names: never bind to Scholar/BLU spell rows when resolving a /pet icon.
    if ctx == 'pet' and petregistry.GetBloodPactByName(spellName) then
        for _, sp in ipairs(list) do
            local t = sp.type or '';
            if t == 'SummonerPact' or t == 'BloodPact' or t == 'BloodPactRage' or t == 'BloodPactWard' then
                return sp;
            end
        end
        return nil;
    end

    table.sort(list, function(a, b)
        return (a.id or 0) < (b.id or 0);
    end);

    if ctx == 'ma' then
        for _, sp in ipairs(list) do
            local t = sp.type or '';
            if t == 'WhiteMagic' or t == 'BlackMagic' or t == 'BlueMagic' or t == 'SummonerPact' then
                return sp;
            end
        end
    end

    if ctx == 'pet' then
        for _, sp in ipairs(list) do
            if not horizonTypeIsSchoolMagicSpellRow(sp.type) then
                return sp;
            end
        end
        return nil;
    end

    return list[1];
end

--- Spell id from horizon DB by English name (icon / macro editor only; case-insensitive).
---@param actionType string|nil optional: 'ma' vs 'pet' when the same `en` exists for different spell kinds
function M.GetSpellIdByEnglishName(spellName, actionType)
    if not spellName or spellName == '' then
        return nil;
    end
    local spell = GetSpellByNameForIcon(spellName, actionType);
    if spell and spell.id then
        return spell.id;
    end
    return nil;
end

--- Full horizon spell row for icon resolution (same duplicate-name rules as GetSpellIdByEnglishName).
---@param actionType string|nil 'ma'|'pet'|nil
---@return table|nil
function M.GetHorizonSpellForIconResolution(spellName, actionType)
    if not spellName or spellName == '' then
        return nil;
    end
    return GetSpellByNameForIcon(spellName, actionType);
end

--- Get MP cost for an action (only applicable to magic spells)
---@param bind table The keybind data with actionType and action fields
---@return number|nil mpCost The MP cost, or nil if not applicable
function M.GetMPCost(bind)
    if not bind then return nil; end

    -- Helper: safe trimmed string
    local function trim(s)
        if not s then return nil; end
        s = tostring(s);
        s = s:gsub('^%s+', ''):gsub('%s+$', '');
        return (s ~= '' and s) or nil;
    end

    -- Helper: current player main job level (for formula MP costs)
    local function getPlayerLevel()
        local player = AshitaCore:GetMemoryManager():GetPlayer();
        return (player and player:GetMainJobLevel()) or 0;
    end

    -- Helper: extract a quoted or unquoted name from a macro line after a command token
    -- e.g. /ma "Fire II" <t>   -> "Fire II"
    --      /pet Fire II <me>   -> "Fire II"
    local function extractNameAfterCommand(line, commandToken)
        if not line or not commandToken then return nil; end
        -- Quoted form first
        local quoted = line:match('^' .. commandToken .. '%s+"([^"]+)"');
        if quoted then return trim(quoted); end
        -- Unquoted: capture until a target token or end-of-line
        local unquoted = line:match('^' .. commandToken .. '%s+([^<\r\n]+)');
        if unquoted then
            unquoted = unquoted:gsub('%s+<.*$', ''); -- strip trailing target if included
            return trim(unquoted);
        end
        return nil;
    end

    -- Helper: SMN level used for Blood Pact eligibility (main SMN, else sub SMN)
    local function getSmnLevelForPacts()
        local player = AshitaCore:GetMemoryManager():GetPlayer();
        if not player then return nil; end
        local JOB_SMN = petregistry.JOB_SMN or 15;
        if player:GetMainJob() == JOB_SMN then
            return player:GetMainJobLevel();
        elseif player:GetSubJob() == JOB_SMN then
            return player:GetSubJobLevel();
        end
        return nil;
    end

    -- Helper: resolve MP cost from pet registry for a pact name
    local function getBloodPactMpCost(pactName)
        pactName = trim(pactName);
        if not pactName then return nil; end

        local pact = petregistry.GetBloodPactByName and petregistry.GetBloodPactByName(pactName) or nil;
        if not pact then return nil; end

        -- Do not show MP when SMN level is below pact learn level (UI shows Lvn instead)
        if pact.level and pact.level > 0 then
            local smnLv = getSmnLevelForPacts();
            if not smnLv or smnLv < pact.level then
                return nil;
            end
        end

        local mp = pact.mp;
        if not mp or mp == 0 then return nil; end
        if mp == -1 then
            local lvl = getPlayerLevel();
            return (lvl > 0) and (lvl * 2) or nil;
        end
        return mp;
    end

    -- Helper: sniff an action from macro text.
    -- Returns: actionType ('ma'|'pet') and actionName, or nil.
    -- Rules:
    -- - If macro line uses /ma or /magic, treat as spell (ma).
    -- - If macro line uses /pet, treat as pet.
    -- - If macro line uses /ja, treat as pet ONLY if the name exists in the Blood Pact registry
    --   (prevents misclassifying normal job abilities).
    local function sniffActionFromMacroText(macroText)
        macroText = trim(macroText);
        if not macroText then return nil; end

        -- Only examine the first few lines (macros are tiny, but keep it bounded)
        local inspectedLines = 0;
        for line in macroText:gmatch('[^\r\n]+') do
            inspectedLines = inspectedLines + 1;
            if inspectedLines > 6 then break; end

            local l = trim(line);
            if l then
                -- Spells first: /ma or /magic
                local spellName = extractNameAfterCommand(l, '/ma') or extractNameAfterCommand(l, '/magic');
                if spellName then
                    return 'ma', spellName;
                end

                -- Pet commands: /pet
                local petName = extractNameAfterCommand(l, '/pet');
                if petName then
                    return 'pet', petName;
                end

                -- Pet pacts often appear as /ja "Name" <t> (especially when created via UI dropdowns)
                local jaName = extractNameAfterCommand(l, '/ja');
                if jaName then
                    -- Only treat /ja as a pact if it exists in the pact registry.
                    if petregistry.GetBloodPactByName and petregistry.GetBloodPactByName(jaName) then
                        return 'pet', jaName;
                    end
                end
            end
        end

        return nil;
    end

    -- Magic spells: use horizon spell DB
    if bind.actionType == 'ma' then
        local spell = GetSpellByName(bind.action);
        if spell and spell.mp_cost and spell.mp_cost > 0 then
            return spell.mp_cost;
        end
        return nil;
    end

    -- Pet commands: Blood Pacts and other pet abilities (only Blood Pacts have MP)
    if bind.actionType == 'pet' then
        return getBloodPactMpCost(bind.action);
    end

    -- Macro slots: optionally derive MP cost from recastSourceType, otherwise sniff /pet lines
    if bind.actionType == 'macro' then
        -- Prefer explicit recastSourceType if present (matches how cooldowns are overridden)
        if bind.recastSourceType == 'ma' and bind.recastSourceAction then
            return M.GetMPCost({ actionType = 'ma', action = bind.recastSourceAction });
        end
        if bind.recastSourceType == 'pet' and bind.recastSourceAction then
            return getBloodPactMpCost(bind.recastSourceAction);
        end

        -- Sniff macro text (supports /ma, /magic, /pet, and /ja pacts)
        local sniffType, sniffName = sniffActionFromMacroText(bind.macroText);
        if sniffType == 'ma' and sniffName then
            return M.GetMPCost({ actionType = 'ma', action = sniffName });
        elseif sniffType == 'pet' and sniffName then
            return getBloodPactMpCost(sniffName);
        end
        return nil;
    end

    return nil;
end

-- TP cost cache for weaponskills (static resource data)
local wsTpCostCache = {};

--- Whether this bind should be dimmed when the player lacks enough TP
---@param bind table
---@return boolean
function M.NeedsTpCheck(bind)
    if not bind then return false; end

    if bind.actionType == 'ws' then
        return true;
    end

    if bind.actionType == 'macro' then
        if bind.recastSourceType == 'ws' and bind.recastSourceAction then
            return true;
        end
        if bind.macroText and bind.macroText ~= '' then
            local primaryType = macroparse.GetMacroPrimaryAndJaBadge(bind.macroText);
            if primaryType == 'ws' then
                return true;
            end
        end
    end

    return false;
end

--- Get TP cost for a weaponskill (clamped to 1000-3000)
---@param wsName string
---@return number
function M.GetWeaponskillTpCost(wsName)
    if not wsName or wsName == '' then
        return 1000;
    end

    local cached = wsTpCostCache[wsName];
    if cached then
        return cached;
    end

    local tpCost = 1000;
    local abilityId = actiondb.GetAbilityId(wsName);
    if abilityId then
        local ability = AshitaCore:GetResourceManager():GetAbilityById(abilityId);
        if ability and ability.TP and ability.TP >= 1000 then
            tpCost = ability.TP;
        end
    end

    if tpCost > 3000 then
        tpCost = 3000;
    end

    wsTpCostCache[wsName] = tpCost;
    return tpCost;
end

--- Resolve weaponskill name from a hotbar bind (direct WS or /ws macro)
---@param bind table
---@return string|nil
local function ResolveWeaponskillNameForTpCheck(bind)
    if not bind then return nil; end

    if bind.actionType == 'ws' then
        return bind.action;
    end

    if bind.actionType == 'macro' then
        if bind.recastSourceType == 'ws' and bind.recastSourceAction then
            return bind.recastSourceAction;
        end
        if bind.macroText and bind.macroText ~= '' then
            local primaryType, primaryName = macroparse.GetMacroPrimaryAndJaBadge(bind.macroText);
            if primaryType == 'ws' and primaryName then
                return primaryName;
            end
        end
    end

    return nil;
end

--- Check if the player currently has enough TP for a weaponskill bind
---@param bind table
---@return boolean hasEnoughTp
function M.HasEnoughTpForBind(bind)
    if not M.NeedsTpCheck(bind) then
        return true;
    end

    local wsName = ResolveWeaponskillNameForTpCheck(bind);
    if not wsName then
        return true;
    end

    local tpCost = M.GetWeaponskillTpCost(wsName);
    local party = AshitaCore:GetMemoryManager():GetParty();
    local playerTp = party and party:GetMemberTP(0) or 0;
    return playerTp >= tpCost;
end

-- Resolve a Blood Pact record (Rage or Ward) for a bind.
-- Supports:
-- - actionType='pet' (direct pact name in bind.action)
-- - actionType='macro' (recastSource pet, /pet, or /ja lines)
-- Returns: pact table from petregistry (or nil)
function M.GetResolvedBloodPact(bind)
    if not bind or not petregistry or not petregistry.GetBloodPactByName then
        return nil;
    end

    local function trim(s)
        if not s then return nil; end
        s = tostring(s);
        s = s:gsub('^%s+', ''):gsub('%s+$', '');
        return (s ~= '' and s) or nil;
    end

    local function extractNameAfterCommand(line, commandToken)
        if not line or not commandToken then return nil; end
        -- Quoted
        local quoted = line:match('^' .. commandToken .. '%s+"([^"]+)"');
        if quoted then return trim(quoted); end
        -- Unquoted
        local unquoted = line:match('^' .. commandToken .. '%s+([^<\r\n]+)');
        if unquoted then
            unquoted = unquoted:gsub('%s+<.*$', '');
            return trim(unquoted);
        end
        return nil;
    end

    -- Direct pet bind
    if bind.actionType == 'pet' and bind.action then
        return petregistry.GetBloodPactByName(bind.action);
    end

    -- Macro bind: prefer explicit recast source if it's pet
    if bind.actionType == 'macro' then
        if bind.recastSourceType == 'pet' and bind.recastSourceAction then
            return petregistry.GetBloodPactByName(bind.recastSourceAction);
        end

        local macroText = trim(bind.macroText);
        if not macroText then return nil; end

        -- Scan up to 8 lines (max macro lines)
        local inspected = 0;
        for line in macroText:gmatch('[^\r\n]+') do
            inspected = inspected + 1;
            if inspected > 8 then break; end

            local l = trim(line);
            if l then
                local petName = extractNameAfterCommand(l, '/pet');
                if petName then
                    local pact = petregistry.GetBloodPactByName(petName);
                    if pact then return pact; end
                end

                local jaName = extractNameAfterCommand(l, '/ja');
                if jaName then
                    local pact = petregistry.GetBloodPactByName(jaName);
                    if pact then return pact; end
                end
            end
        end
    end

    return nil;
end

-- Optional bottom-left "status" badge PNG per blood pact (petregistry.statusCornerIcon), relative to addons/XIUI/
local bloodPactCornerIconCache = {};

local function loadTextureXiuiAddonRelative(relPath)
    if not relPath or relPath == '' then
        return nil;
    end
    if bloodPactCornerIconCache[relPath] ~= nil then
        local c = bloodPactCornerIconCache[relPath];
        return (c ~= false) and c or nil;
    end
    local full = string.format('%saddons\\XIUI\\%s', AshitaCore:GetInstallPath(), relPath:gsub('/', '\\'));
    local icon = textures:LoadTextureFromPath(full);
    if icon then
        finalizeCustomIconTextureForHotbar(icon);
        bloodPactCornerIconCache[relPath] = icon;
        return icon;
    end
    bloodPactCornerIconCache[relPath] = false;
    return nil;
end

--- Texture for bottom-left blood pact badge when petregistry sets statusCornerIcon (else slotrenderer uses theme + pact.status).
--- @param bind table|nil hotbar bind
--- @param pactOptional table|nil if already resolved via GetResolvedBloodPact (avoids double lookup)
--- @return table|nil icon table with .image for ImGui, or nil
function M.GetBloodPactStatusCornerIcon(bind, pactOptional)
    local pact = pactOptional or M.GetResolvedBloodPact(bind);
    if not pact or not pact.statusCornerIcon or pact.statusCornerIcon == '' then
        return nil;
    end
    return loadTextureXiuiAddonRelative(pact.statusCornerIcon);
end

--- Check if an action is currently available to use
--- Takes into account job, level, subjob, and level sync
---@param bind table The keybind data with actionType and action fields
---@return boolean isAvailable True if the action can be used
---@return string|nil reason Reason if not available (e.g., "Level 50 required", "Wrong job")
function M.IsActionAvailable(bind)
    if not bind then return true, nil; end

    local memMgr = AshitaCore:GetMemoryManager();
    local player = memMgr and memMgr:GetPlayer();
    if not player then return true, nil; end

    local mainJobId = player:GetMainJob();
    local subJobId = player:GetSubJob();

    -- IMPORTANT: Use EFFECTIVE (post-Level Sync) levels for spell/JA/pact gates. Party
    -- member 0 = the player; `GetMemberMainJobLevel(0)` reflects the synced-down value
    -- (e.g. 40 while synced) whereas `player:GetMainJobLevel()` returns the raw character
    -- level (e.g. 75). Without this, a synced player gets told a Lv50 spell is available
    -- when the game itself will reject the cast. Falls back to raw level if party packet
    -- hasn't populated yet (zone-in race). Effective levels are also embedded in the
    -- slotrenderer availability cache key, so transitions invalidate cleanly.
    local mainJobLevel = player:GetMainJobLevel() or 0;
    local subJobLevel = player:GetSubJobLevel() or 0;
    local party = memMgr and memMgr:GetParty();
    if party then
        local pMain = party:GetMemberMainJobLevel(0);
        local pSub = party:GetMemberSubJobLevel(0);
        if pMain and pMain > 0 then mainJobLevel = pMain; end
        if pSub and pSub > 0 then subJobLevel = pSub; end
    end

    -- Guard: If job data is invalid (e.g., during zoning), assume available
    -- Don't cache this result - return nil as reason to signal "don't cache"
    if mainJobId == 0 or mainJobLevel == 0 then
        return true, "pending";  -- "pending" signals not to cache this result
    end

    -- Helper: check if player currently has a given buff id
    local function HasBuffId(buffId)
        if not buffId then return false; end
        local buffs = player:GetBuffs();
        if not buffs then return false; end
        for i = 1, 32 do
            if buffs[i] == buffId then
                return true;
            end
        end
        return false;
    end

    -- Helper: extract pact name from /pet or /ja line (quoted or unquoted)
    local function ExtractNameAfterCommand(line, commandToken)
        if not line or not commandToken then return nil; end
        line = tostring(line);
        -- Quoted
        local quoted = line:match('^' .. commandToken .. '%s+"([^"]+)"');
        if quoted and quoted ~= '' then return quoted; end
        -- Unquoted (until target or EOL)
        local unquoted = line:match('^' .. commandToken .. '%s+([^<\r\n]+)');
        if unquoted and unquoted ~= '' then
            unquoted = unquoted:gsub('%s+<.*$', '');
            unquoted = unquoted:gsub('^%s+', ''):gsub('%s+$', '');
            return (unquoted ~= '' and unquoted) or nil;
        end
        return nil;
    end

    -- Helper: resolve a blood pact record by name (if any)
    local function GetBloodPactByName(name)
        if not name or name == '' then return nil; end
        if petregistry and petregistry.GetBloodPactByName then
            return petregistry.GetBloodPactByName(name);
        end
        return nil;
    end

    local JOB_SMN = petregistry.JOB_SMN or 15;

    -- Effective SMN level: main job SMN uses main level; otherwise sub SMN uses sub level
    local function GetSmnLevelForBloodPacts()
        if mainJobId == JOB_SMN then
            return mainJobLevel;
        elseif subJobId == JOB_SMN then
            return subJobLevel;
        end
        return nil;
    end

    -- Blood Pact level gate (Horizon/registry `level` field)
    local function CheckBloodPactLevelRequirement(pact)
        if not pact or not pact.level or pact.level <= 0 then
            return true, nil;
        end
        local smnLv = GetSmnLevelForBloodPacts();
        if smnLv == nil then
            return false, 'Job';
        end
        if smnLv < pact.level then
            return false, string.format('Lv%d', pact.level);
        end
        return true, nil;
    end

    -- Pet actions: Astral Flow + Blood Pact level
    if bind.actionType == 'pet' and bind.action then
        local pact = GetBloodPactByName(bind.action);
        if pact and pact.requiresFlow then
            -- Astral Flow buff id is 55 (see bufftable.lua mapping)
            if not HasBuffId(55) then
                -- Don't cache this: buff state changes frequently
                return false, "pending";
            end
        end
        if pact then
            local ok, lvlReason = CheckBloodPactLevelRequirement(pact);
            if not ok then
                return false, lvlReason;
            end
        end
        return true, nil;
    end

    -- Macro actions: if macro resolves to a blood pact requiring Astral Flow, mark unavailable when Flow is down
    if bind.actionType == 'macro' then
        local pactName = nil;

        -- Prefer explicit recast source override when set to pet
        if bind.recastSourceType == 'pet' and bind.recastSourceAction then
            pactName = bind.recastSourceAction;
        end

        -- Otherwise sniff first few lines for /pet or /ja pact names
        if not pactName and bind.macroText then
            local inspectedLines = 0;
            for line in tostring(bind.macroText):gmatch('[^\r\n]+') do
                inspectedLines = inspectedLines + 1;
                if inspectedLines > 6 then break; end

                local l = line:gsub('^%s+', ''):gsub('%s+$', '');
                if l ~= '' then
                    local petName = ExtractNameAfterCommand(l, '/pet');
                    if petName then
                        pactName = petName;
                        break;
                    end
                    local jaName = ExtractNameAfterCommand(l, '/ja');
                    if jaName and GetBloodPactByName(jaName) then
                        pactName = jaName;
                        break;
                    end
                end
            end
        end

        if pactName then
            local pact = GetBloodPactByName(pactName);
            if pact and pact.requiresFlow and not HasBuffId(55) then
                return false, "pending";
            end
            if pact then
                local ok, lvlReason = CheckBloodPactLevelRequirement(pact);
                if not ok then
                    return false, lvlReason;
                end
            end
        end
        -- Otherwise: fall through to existing checks below (or assume available)
    end

    -- Macro: validate primary /ws /ma /pet /ja line + optional /ja badge (otherwise macro slots always returned "available")
    if bind.actionType == 'macro' and bind.macroText and bind.macroText ~= '' then
        local pType, pName, jaBadge = macroparse.GetMacroPrimaryAndJaBadge(bind.macroText);
        local function validateActionPair(aType, aName)
            if not aType or not aName or aName == '' then
                return true, nil;
            end
            if aType == 'item' or aType == 'equip' or aType == 'misc' then
                return true, nil;
            end
            if aType ~= 'ws' and aType ~= 'ma' and aType ~= 'pet' and aType ~= 'ja' then
                return true, nil;
            end
            local syn = { actionType = aType, action = aName };
            return M.IsActionAvailable(syn);
        end
        local okP, rsP = validateActionPair(pType, pName);
        if not okP then
            return false, rsP;
        end
        if jaBadge and jaBadge ~= '' then
            local okB, rsB = validateActionPair('ja', jaBadge);
            if not okB then
                return false, rsB;
            end
        end
    end

    -- Handle magic spells
    if bind.actionType == 'ma' then
        local spell = GetSpellByName(bind.action);
        if not spell then return false, 'Unknown'; end

        local levels = spell.levels;
        if not levels then return true, nil; end

        local mainReqLevel = levels[mainJobId];
        local subReqLevel = subJobId and levels[subJobId] or nil;

        -- Level gate: check if main or sub job meets the requirement
        local mainCanLevel = mainReqLevel and mainJobLevel >= mainReqLevel;
        local subCanLevel = subReqLevel and subJobLevel >= subReqLevel;

        if not mainCanLevel and not subCanLevel then
            if mainReqLevel then
                return false, string.format("Lv%d", mainReqLevel);
            elseif subReqLevel then
                return false, string.format("Lv%d", subReqLevel);
            else
                return false, "Job";
            end
        end

        -- Scroll/quest gate: right job and level but spell not yet learned
        if spell.id and not player:HasSpell(spell.id) then
            local reqLv = mainCanLevel and mainReqLevel or subReqLevel;
            return false, string.format("Lv%d", reqLv);
        end

        return true, nil;

    -- Handle job abilities
    elseif bind.actionType == 'ja' then
        local jaName = universalTwoHour.ResolveJaActionName(bind.action);
        if not jaName then
            return false, 'N/A';
        end
        -- Use playerdata's cached abilities as single source of truth
        local playerdata = require('modules.hotbar.playerdata');
        if not playerdata.IsAbilityInCache(bind.action) then
            return false, 'N/A';
        end
        -- Blood pacts bound as /ja (e.g. /ja "Judgment Bolt") still follow pact rules: Astral Flow + SMN level
        local pactJa = GetBloodPactByName(jaName);
        if pactJa and pactJa.requiresFlow then
            if not HasBuffId(55) then
                return false, "pending";
            end
        end
        if pactJa then
            local okJa, lvlReasonJa = CheckBloodPactLevelRequirement(pactJa);
            if not okJa then
                return false, lvlReasonJa;
            end
        end

    -- Handle weapon skills
    elseif bind.actionType == 'ws' then
        -- Use playerdata's cached weaponskills as single source of truth
        local playerdata = require('modules.hotbar.playerdata');
        if not playerdata.IsWeaponskillInCache(bind.action) then
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

local function GetIconFromMacroStyleCustomFields(customIconType, customIconId, customIconPath)
    if not customIconType then
        return nil;
    end
    if customIconType == 'spell' and customIconId then
        return textures:Get('spells' .. string.format('%05d', customIconId));
    elseif customIconType == 'item' and customIconId then
        return LoadItemIconById(customIconId);
    elseif customIconType == 'custom' and customIconPath and customIconPath ~= '' then
        return loadCustomIconByRelativePath(customIconPath);
    elseif customIconType == 'xiui_asset' and customIconPath and customIconPath ~= '' then
        return loadXiuiBundledAssetIcon(customIconPath);
    elseif customIconType == 'xiui_default' and customIconPath then
        return LoadXiuiDefaultIcon(customIconPath);
    end
    return nil;
end

--- @param paletteKey number|string|nil macro palette key (job id or global key)
function M.FindMacroByIdAndPalette(macroId, paletteKey)
    if not macroId then
        return nil;
    end
    return data.GetMacroById(macroId, paletteKey or data.jobId or 1);
end

--- Resolve bottom-right /ja badge texture: optional macro.jaBadgeCustom* override, else same as GetBindIcon ja.
--- ctx: hotbar bind { actionType, macroText, macroRef?, macroPaletteKey? } or palette macro row { id, ... }.
function M.ResolveMacroJaBadgeIcon(ctx)
    if not ctx or ctx.actionType ~= 'macro' or not ctx.macroText or ctx.macroText == '' then
        return nil;
    end
    local macroForFlag = ctx;
    if ctx.macroRef and not ctx.id then
        local fromDb = M.FindMacroByIdAndPalette(ctx.macroRef, ctx.macroPaletteKey);
        if fromDb then
            macroForFlag = fromDb;
        end
    end
    if macroForFlag.showJaBadgeOnMacro == false then
        return nil;
    end
    local jaName = M.GetMacroJaBadgeAbilityName(ctx.macroText);
    if not jaName or jaName == '' then
        return nil;
    end
    local macro = ctx;
    if ctx.macroRef and not ctx.id then
        local fromDb = M.FindMacroByIdAndPalette(ctx.macroRef, ctx.macroPaletteKey);
        if fromDb then
            macro = fromDb;
        end
    end
    if macro and macro.jaBadgeCustomIconType then
        local ic = GetIconFromMacroStyleCustomFields(
            macro.jaBadgeCustomIconType,
            macro.jaBadgeCustomIconId,
            macro.jaBadgeCustomIconPath
        );
        if ic and ic.image then
            return ic;
        end
    end
    return M.GetBindIcon({ actionType = 'ja', action = jaName });
end

--- Cache-key fragment when a hotbar slot references a macro (invalidates when JA badge icon overrides change).
function M.GetMacroJaBadgeIconCacheSuffix(bind)
    if not bind or bind.actionType ~= 'macro' or not bind.macroRef then
        return '';
    end
    local m = M.FindMacroByIdAndPalette(bind.macroRef, bind.macroPaletteKey);
    if not m then
        return '';
    end
    return ':jb:' .. tostring(m.jaBadgeCustomIconType or '')
        .. ':' .. tostring(m.jaBadgeCustomIconId or '')
        .. ':' .. tostring(m.jaBadgeCustomIconPath or '')
        .. ':' .. tostring(m.showJaBadgeOnMacro ~= false);
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

    -- Check name->id cache first (includes negative cache for "not found"); key is lowercased
    local cacheKey = string.lower(tostring(itemName));
    local cachedId = itemNameToIdCache[cacheKey];
    if cachedId then
        if cachedId == ITEM_NOT_FOUND then
            return nil;  -- Previously searched, item doesn't exist
        end
        return LoadItemIconById(cachedId);
    end

    -- Audit win: O(1) name->id via actiondb (session-cached lazy hashmap built once on
    -- first call). Previously this did a per-call O(65535) scan that only avoided repeats
    -- via the local itemNameToIdCache. With actiondb the build cost is paid once across
    -- ALL callers and every subsequent name lookup is constant-time. The local cache is
    -- still kept so the LoadItemIconById step is also remembered per icon resolution.
    local itemId = actiondb.GetItemId(itemName);
    if itemId and itemId > 0 then
        itemNameToIdCache[cacheKey] = itemId;
        return LoadItemIconById(itemId);
    end

    -- Negative-result cache prevents future actiondb probes for misspelled / nonexistent items.
    itemNameToIdCache[cacheKey] = ITEM_NOT_FOUND;
    return nil;
end

--- When a macro row references a custom PNG that failed to load, fall back like an unset icon:
--- primary /ws /ma /pet /ja /item /equip → that type's default art; otherwise generic macro.png.
local function GetMacroFallbackIconAfterMissingCustomFile(bind)
    if not bind or bind.actionType ~= 'macro' then
        local def = LoadXiuiDefaultIcon('macro');
        if def then return def, nil; end
        return nil, nil;
    end
    local macroText = bind.macroText;
    if not macroText or macroText == '' then
        local def = LoadXiuiDefaultIcon('macro');
        if def then return def, nil; end
        return nil, nil;
    end
    local mp = require('modules.hotbar.macroparse');
    local pType, pName = mp.GetMacroPrimaryAndJaBadge(macroText);
    if pType and pName and pName ~= '' then
        if pType == 'ma' or pType == 'ja' or pType == 'ws' or pType == 'pet'
            or pType == 'item' or pType == 'equip' then
            return M.GetBindIcon({
                actionType = pType,
                action = pName,
                itemId = bind.itemId,
            });
        end
    end
    local def = LoadXiuiDefaultIcon('macro');
    if def then return def, nil; end
    return nil, nil;
end

--- Get icon for a bind (separate from command building for use in drag preview)
---@param bind table The keybind data
---@return any|nil icon The icon texture (if available)
---@return number|nil iconId The icon ID (for reference)
function M.GetBindIcon(bind)
    if not bind then
        return nil, nil;
    end

    -- Negative cache: if we've already determined this bind has no icon, skip the lookups.
    -- ClearNoIconCache() must be called by upstream paths whenever icon resolution could change
    -- (macroDB edit, job/pet/palette change, custom icon asset change).
    local noIconKey = buildNoIconKey(bind);
    if noIconKey and noIconCache[noIconKey] then
        return nil, nil;
    end

    local icon = nil;
    local iconId = nil;

    -- Inline custom icon on the bind first (merged hotbar slot, macro editor row). Avoids macroDB shadowing
    -- unsaved editor state when macroRef is present; also matches data.GetKeybindForSlot merge behavior.
    if bind.customIconType then
        if bind.customIconType == 'spell' and bind.customIconId then
            icon = textures:Get('spells' .. string.format('%05d', bind.customIconId));
            iconId = bind.customIconId;
            if icon then return icon, iconId; end
        elseif bind.customIconType == 'item' and bind.customIconId then
            icon = LoadItemIconById(bind.customIconId);
            iconId = bind.customIconId;
            if icon then return icon, iconId; end
        elseif bind.customIconType == 'custom' and bind.customIconPath and bind.customIconPath ~= '' then
            icon = loadCustomIconByRelativePath(bind.customIconPath);
            if icon and icon.image then
                return icon, nil;
            end
            return GetMacroFallbackIconAfterMissingCustomFile(bind);
        elseif bind.customIconType == 'xiui_asset' and bind.customIconPath and bind.customIconPath ~= '' then
            icon = loadXiuiBundledAssetIcon(bind.customIconPath);
            if icon and icon.image then
                return icon, nil;
            end
            return GetMacroFallbackIconAfterMissingCustomFile(bind);
        elseif bind.customIconType == 'xiui_default' and bind.customIconPath then
            icon = LoadXiuiDefaultIcon(bind.customIconPath);
            if icon then return icon, nil; end
        end
    end

    -- Slot references a saved macro row — use palette DB when bind has no inline icon (e.g. stale slot snapshot).
    if bind.macroRef and gConfig and gConfig.macroDB then
        local paletteKey = bind.macroPaletteKey or data.jobId or 1;
        local macro = data.GetMacroById(bind.macroRef, paletteKey);
        if macro and macro.customIconType then
            if macro.customIconType == 'spell' and macro.customIconId then
                icon = textures:Get('spells' .. string.format('%05d', macro.customIconId));
                iconId = macro.customIconId;
                if icon then return icon, iconId; end
            elseif macro.customIconType == 'item' and macro.customIconId then
                icon = LoadItemIconById(macro.customIconId);
                iconId = macro.customIconId;
                if icon then return icon, iconId; end
            elseif macro.customIconType == 'custom' and macro.customIconPath and macro.customIconPath ~= '' then
                icon = loadCustomIconByRelativePath(macro.customIconPath);
                if icon and icon.image then
                    return icon, nil;
                end
                return GetMacroFallbackIconAfterMissingCustomFile(bind);
            elseif macro.customIconType == 'xiui_asset' and macro.customIconPath and macro.customIconPath ~= '' then
                icon = loadXiuiBundledAssetIcon(macro.customIconPath);
                if icon and icon.image then
                    return icon, nil;
                end
                return GetMacroFallbackIconAfterMissingCustomFile(bind);
            elseif macro.customIconType == 'xiui_default' and macro.customIconPath then
                icon = LoadXiuiDefaultIcon(macro.customIconPath);
                if icon then return icon, nil; end
            end
        end
    end

    -- Macro (palette preview / hotbar): icon follows the same primary line as macroparse (no custom icon set).
    if bind.actionType == 'macro' then
        local macroText = bind.macroText;
        if macroText and macroText ~= '' then
            local mp = require('modules.hotbar.macroparse');
            local pType, pName = mp.GetMacroPrimaryAndJaBadge(macroText);
            if pType and pName and pName ~= '' then
                if pType == 'ma' or pType == 'ja' or pType == 'ws' or pType == 'pet'
                    or pType == 'item' or pType == 'equip' then
                    return M.GetBindIcon({
                        actionType = pType,
                        action = pName,
                        itemId = bind.itemId,
                    });
                end
            end
        end
        local def = LoadXiuiDefaultIcon('macro');
        if def then return def, nil; end
        return nil, nil;
    end

    if bind.actionType == 'ma' then
        -- Check for summoning magic first (custom icons)
        local summonIconKey = LookupStringKeyInsensitive(summonSpellToIconKey, bind.action);
        if summonIconKey then
            icon = textures:Get(summonIconKey);
            if icon then
                local spell = GetSpellByNameForIcon(bind.action, 'ma');
                if spell then iconId = spell.id; end
                return icon, iconId;
            end
        end
        -- Check for Trust icons
        local trustIconKey = LookupStringKeyInsensitive(trustToIconKey, bind.action);
        if trustIconKey then
            icon = textures:Get(trustIconKey);
            if icon then
                local spell = GetSpellByNameForIcon(bind.action, 'ma');
                if spell then iconId = spell.id; end
                return icon, iconId;
            end
        end
        -- Check for Blue Magic icons
        local blueIconKey = LookupStringKeyInsensitive(blueMagicToIconKey, bind.action);
        if blueIconKey then
            icon = textures:Get(blueIconKey);
            if icon then
                local spell = GetSpellByNameForIcon(bind.action, 'ma');
                if spell then iconId = spell.id; end
                return icon, iconId;
            end
        end
        -- Any PNG indexed by normalized spell name (SMN/Summons/Summoning, etc.) — matches "Fire Spirit" / fire spirit / file FireSpirit.png
        icon = textures:GetIconBySpellName(bind.action);
        if icon and icon.image then
            local spell = GetSpellByNameForIcon(bind.action, 'ma');
            if spell then iconId = spell.id; end
            return icon, iconId;
        end
        icon = TryLoadCustomHotbarIconByActionName(bind.action);
        if icon and icon.image then
            local spell = GetSpellByNameForIcon(bind.action, 'ma');
            if spell then iconId = spell.id; end
            return icon, iconId;
        end
        -- Magic spell - look up in horizonspells database
        local spell = GetSpellByNameForIcon(bind.action, 'ma');
        if spell then
            iconId = spell.id;
            icon = textures:Get('spells' .. string.format('%05d', spell.id));
        end
    elseif bind.actionType == 'ja' then
        local jaBindName = universalTwoHour.ResolveJaActionName(bind.action);
        if jaBindName then
        -- Check for SMN ability icons first
        local smnIconKey = LookupStringKeyInsensitive(smnAbilityToIconKey, jaBindName);
        if smnIconKey then
            icon = textures:Get(smnIconKey);
            if icon then return icon, iconId; end
        end
        -- Check for RUN ability icons
        local runIconKey = LookupStringKeyInsensitive(runAbilityToIconKey, jaBindName);
        if runIconKey then
            icon = textures:Get(runIconKey);
            if icon then return icon, iconId; end
        end
        -- Check for other job ability icons
        local otherIconKey = LookupStringKeyInsensitive(otherAbilityToIconKey, jaBindName);
        if otherIconKey then
            icon = textures:Get(otherIconKey);
            if icon then return icon, iconId; end
        end
        -- Indexed / Summoning / Summons PNGs before vanilla ability id (macro icons: custom first)
        icon = textures:GetIconBySpellName(jaBindName);
        if icon and icon.image then
            return icon, iconId;
        end
        icon = TryLoadCustomHotbarIconByActionName(jaBindName);
        if icon and icon.image then
            return icon, iconId;
        end
        -- Job ability - resolve id for overlays; texture may still come from default ja.png below
        local resMgr = AshitaCore:GetResourceManager();
        if resMgr then
            for abilityId = 1, 1024 do
                local ability = resMgr:GetAbilityById(abilityId);
                if ability and ability.Name and NameEqualsI(ability.Name[1], jaBindName) then
                    iconId = abilityId;
                    break;
                end
            end
        end
        end
    elseif bind.actionType == 'pet' then
        -- Check for pet command icons first
        local petIconKey = LookupStringKeyInsensitive(petCommandToIconKey, bind.action);
        if petIconKey then
            icon = textures:Get(petIconKey);
            if icon then
                return icon, iconId;
            end
        end
        -- Blood pacts / Ready: prefer indexed PNGs and horizon row only when it is a pact row (not Scholar/BLU dupes)
        icon = textures:GetIconBySpellName(bind.action);
        if icon and icon.image then
            local sp = GetSpellByNameForIcon(bind.action, 'pet');
            if sp and not horizonTypeIsSchoolMagicSpellRow(sp.type) then
                iconId = sp.id;
            end
            return icon, iconId;
        end
        icon = TryLoadCustomHotbarIconByActionName(bind.action);
        if icon and icon.image then
            local sp = GetSpellByNameForIcon(bind.action, 'pet');
            if sp and not horizonTypeIsSchoolMagicSpellRow(sp.type) then
                iconId = sp.id;
            end
            return icon, iconId;
        end
        local sp = GetSpellByNameForIcon(bind.action, 'pet');
        if sp and not horizonTypeIsSchoolMagicSpellRow(sp.type) then
            iconId = sp.id;
            icon = textures:Get('spells' .. string.format('%05d', sp.id));
        end
    elseif bind.actionType == 'ws' then
        -- Weaponskill - try to get from game resources
        local resMgr = AshitaCore:GetResourceManager();
        if resMgr then
            for wsId = 1, 255 do
                local ability = resMgr:GetAbilityById(wsId + 256);
                if ability and ability.Name and NameEqualsI(ability.Name[1], bind.action) then
                    iconId = wsId;
                    break;
                end
            end
        end
        icon = textures:GetIconBySpellName(bind.action);
        if icon and icon.image then
            return icon, iconId;
        end
        icon = TryLoadCustomHotbarIconByActionName(bind.action);
        if icon and icon.image then
            return icon, iconId;
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

    -- XIUI defaults (assets/icons/{ma,ja,ws,pet,item}.png) when no game/custom texture loaded.
    -- Spell rows can resolve in horizonspells while spells#####.png is still missing on disk; SMN
    -- summon PNGs can fail similarly — user still sees the type icon instead of a blank/abbreviation.
    if (not icon or not icon.image) and bind.actionType then
        local stem = ({
            ma = 'ma',
            ja = 'ja',
            ws = 'ws',
            pet = 'pet',
            item = 'item',
            equip = 'item',
        })[bind.actionType];
        if stem then
            local def = LoadXiuiDefaultIcon(stem);
            if def and def.image then
                icon = def;
            end
        end
    end

    -- Memoize negative results so future cache misses (after display.iconCache wipes)
    -- skip the lookup work for binds that have no resolvable icon.
    if not icon and noIconKey then
        noIconCache[noIconKey] = true;
    end

    return icon, iconId;
end

--- Last /ja ability name in a macro when the prioritized command is /ws, /ma, or /pet (for bottom-right badge).
---@param macroText string|nil
---@return string|nil
function M.GetMacroJaBadgeAbilityName(macroText)
    if not macroText or macroText == '' then
        return nil;
    end
    local mp = require('modules.hotbar.macroparse');
    local _, _, jaBadge = mp.GetMacroPrimaryAndJaBadge(macroText);
    return jaBadge;
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

--- Command string only (no GetBindIcon). Use from per-frame draw paths; icons are resolved separately and cached.
---@param bind table The keybind data with actionType, action, and target fields
---@return string|nil command The command to execute
function M.BuildCommandString(bind)
    if not bind then
        return nil;
    end

    local target = FormatTargetForCommand(bind.target);

    if bind.actionType == 'ma' then
        return '/ma "' .. bind.action .. '" ' .. target;
    elseif bind.actionType == 'ja' then
        local jaName = universalTwoHour.ResolveJaActionName(bind.action);
        if not jaName then
            return nil;
        end
        local rawTarget = universalTwoHour.ResolveJaBindTarget(bind) or bind.target;
        target = FormatTargetForCommand(rawTarget);
        return '/ja "' .. jaName .. '" ' .. target;
    elseif bind.actionType == 'ws' then
        return '/ws "' .. bind.action .. '" ' .. target;
    elseif bind.actionType == 'item' then
        return '/item "' .. bind.action .. '" ' .. target;
    elseif bind.actionType == 'equip' then
        local slot = bind.equipSlot or 'main';
        return '/equip ' .. slot .. ' "' .. bind.action .. '"';
    elseif bind.actionType == 'pet' then
        return '/pet "' .. bind.action .. '" ' .. target;
    elseif bind.actionType == 'macro' then
        return bind.macroText or bind.action;
    end

    -- Defensive fallback: if actionType is nil/unknown but macroText is present,
    -- covers legacy profile macros imported to shared without an actionType field.
    if bind.macroText and bind.macroText ~= '' then
        return bind.macroText;
    end

    return nil;
end

---@param bind table The keybind data with actionType, action, and target fields
---@return string|nil command The command to execute
---@return any|nil icon The icon texture (if applicable)
function M.BuildCommand(bind)
    if not bind then
        return nil, nil;
    end

    local icon = M.GetBindIcon(bind);
    local command = M.BuildCommandString(bind);
    return command, icon;
end



-- Parse lParam bits per Keystroke Message Flags:
-- bit 31 - transition state: 0 = key press, 1 = key release
local function parseKeyEventFlags(event)
   local lparam = tonumber(event.lparam) or 0
   local function getBit(val, idx) return math.floor(val / (2^idx)) % 2 end
   return (getBit(lparam, 31) == 1)
end

--- Parse inline <wait #> subcommand from end of a command line
--- @param line string The command line to parse
--- @return string strippedLine, number|nil waitTime
local function parseInlineWait(line)
    local stripped, waitStr = line:match('^(.-)%s*<wait%s*(%d*%.?%d*)>%s*$');
    if stripped then
        local waitTime = tonumber(waitStr);
        if not waitTime or waitTime <= 0 then
            waitTime = 1;
        end
        return stripped, waitTime;
    end
    return line, nil;
end

--- Check if any line in a macro contains a wait directive
--- @param lines table Array of command line strings
--- @return boolean hasWait True if any line has /wait, /pause, /sleep, or <wait N>
local function macroHasWait(lines)
    for _, line in ipairs(lines) do
        if line:match('^/wait%s') or line:match('^/wait$')
            or line:match('^/pause%s') or line:match('^/pause$')
            or line:match('^/sleep%s') or line:match('^/sleep$')
            or line:match('<wait%s*%d') then
            return true;
        end
    end
    return false;
end

--- Execute a command string (handles multi-line macros with /wait support)
--- Splits by newlines and executes each non-empty line in sequence
--- For macros WITHOUT waits: queues all lines synchronously using Macro mode (2)
--- so the game processes them as a native macro batch with fallthrough behavior.
--- For macros WITH waits: uses Ashita's task scheduler for proper delay handling.
--- Also handles inline <wait #> subcommands at end of command lines.
--- @param commandText string The command text (may contain newlines)
--- @param isMacro boolean|nil If true, enforces single-macro-at-a-time execution
--- @return boolean success Whether any command was executed
function M.ExecuteCommandString(commandText, isMacro)
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

    local myMacroId = nil;
    if isMacro then
        activeMacroId = activeMacroId + 1;
        myMacroId = activeMacroId;
    end

    -- SYNCHRONOUS FAST PATH: For macros without any wait directives, queue all
    -- lines in the same frame using mode 2 (Macro). This tells the game engine
    -- these commands come from the macro subsystem, enabling native fallthrough
    -- behavior where failed commands (e.g., wrong WS for equipped weapon) are
    -- skipped and the next line is tried automatically.
    -- NOTE: The game's macro command stack is LIFO, so we queue in reverse order.
    if isMacro and not macroHasWait(lines) then
        local ok, err = pcall(function()
            local chatManager = AshitaCore:GetChatManager();
            if chatManager then
                for i = #lines, 1, -1 do
                    local trimmed = lines[i]:match('^%s*(.-)%s*$');
                    if trimmed and trimmed ~= '' then
                        chatManager:QueueCommand(2, trimmed);
                    end
                end
            end
        end);
        if not ok then
            print('[XIUI] Command execution error: ' .. tostring(err));
        end
        return true;
    end

    -- ASYNC PATH: For macros with wait directives or non-macro commands.
    -- Recursive function to execute lines with proper /wait handling.
    -- This chains tasks instead of scheduling them all at once.
    local function executeNextLine(index)
        if index > #lines then
            return;
        end

        -- If this is a macro flow, bail out when a newer macro has started
        if myMacroId and myMacroId ~= activeMacroId then
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
            -- Parse inline <wait #> subcommand
            local commandToExecute, inlineWait = parseInlineWait(line);

            -- PROTECTED command execution
            -- Use mode 2 (Macro) for macro flows to get native fallthrough,
            -- mode -1 (AshitaParse) for non-macro single commands
            local cmdMode = isMacro and 2 or -1;
            local ok, err = pcall(function()
                local chatManager = AshitaCore:GetChatManager();
                if chatManager then
                    chatManager:QueueCommand(cmdMode, commandToExecute);
                end
            end);

            if not ok then
                print('[XIUI] Command execution error: ' .. tostring(err));
            end

            -- Schedule next line with inline wait delay if found
            if index < #lines then
                local delay = inlineWait or 0;
                ashita.tasks.once(delay, function()
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

    local command = M.BuildCommandString(bind);
    if not command or command == '' then
        return false;
    end
    M.NotifySlotExecutionEffects(bind);
    return M.ExecuteCommandString(command, bind.actionType == 'macro');
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
                if binding and type(binding) == 'table' and not binding.cleared and binding.key == keyCode then
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

--- Called immediately before QueueCommand for a hotbar/crossbar bind (click, key, controller).
function M.NotifySlotExecutionEffects(bind)
    if bind and bind.actionType == 'ja' and bind.action == universalTwoHour.ACTION_SENTINEL then
        local okR, recastMod = pcall(require, 'modules.hotbar.recast');
        if okR and recastMod and recastMod.GetCooldownInfo then
            local cd = recastMod.GetCooldownInfo(bind);
            if cd and cd.isOnCooldown then
                return;
            end
        end
        universalTwoHour.NotifyUniversalTwoHourExecuted();
    end
end

--- Execute an action directly from slot data
--- Used by crossbar for controller input
---@param slotAction table The slot action with actionType, action, target, etc.
---@return boolean success Whether the action was executed
function M.ExecuteAction(slotAction)
    if not slotAction then return false; end
    if not slotAction.actionType or not slotAction.action then return false; end

    local command = M.BuildCommandString(slotAction);
    if not command or command == '' then
        return false;
    end
    M.NotifySlotExecutionEffects(slotAction);
    return M.ExecuteCommandString(command, slotAction.actionType == 'macro');
end

-- Clear the custom icon cache (call when icons may have changed)
function M.ClearCustomIconCache()
    customIconCache = {};
    xiuiDefaultIconCache = {};
end

--- Clear the negative-result cache. Must be called whenever something upstream
--- could change icon resolution: macroDB edits, job/pet/palette changes, custom
--- icon asset changes. Failing to clear it pins stale "no icon" decisions.
function M.ClearNoIconCache()
    noIconCache = {};
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