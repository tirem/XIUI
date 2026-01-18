--[[
* XIUI hotbar - Texture Loading Module
* Loads and caches spell/ability icons and item icons
]]--

require('handlers.helpers');
local ffi = require('ffi');
local d3d8 = require('d3d8');
local pngencoder = require('libs.pngencoder');

-- Item icon cache directory (initialized lazily)
local itemCacheDir = nil;

-- Load texture from full file path with high quality (no filtering)
-- Returns: { image = IDirect3DTexture8*, path = filePath, width, height }
local function LoadTextureFromPath(filePath)
    local device = GetD3D8Device();
    if (device == nil) then return nil; end

    local textureData = T{};
    local texture_ptr = ffi.new('IDirect3DTexture8*[1]');

    -- Use D3DXCreateTextureFromFileExA with D3DX_FILTER_NONE for best quality
    local res = ffi.C.D3DXCreateTextureFromFileExA(
        device, filePath,
        0xFFFFFFFF, 0xFFFFFFFF,  -- D3DX_DEFAULT size
        1,                        -- MipLevels
        0,                        -- Usage
        ffi.C.D3DFMT_A8R8G8B8,   -- Format with alpha
        ffi.C.D3DPOOL_MANAGED,   -- Pool
        1,                        -- D3DX_FILTER_NONE
        1,                        -- D3DX_FILTER_NONE for mips
        0,                        -- No color key
        nil, nil,
        texture_ptr
    );

    if (res ~= ffi.C.S_OK) then
        return nil;
    end
    textureData.image = ffi.new('IDirect3DTexture8*', texture_ptr[0]);
    d3d8.gc_safe_release(textureData.image);

    -- Store path for primitive rendering
    textureData.path = filePath;

    -- Default size (spell icons are typically 40x40)
    textureData.width = 40;
    textureData.height = 40;

    return textureData;
end

local textures = {};

textures.Initialize = function(self)
    if self.Cache then
        return;
    end

    self.Cache = {};
    
    -- Load slot background and frame images from assets
    local assetsDirectory = string.format('%saddons\\XIUI\\assets\\hotbar\\', AshitaCore:GetInstallPath());
    
    -- Load slot background
    local slotBg = LoadTextureFromPath(assetsDirectory .. 'slot.png');
    if slotBg then
        self.Cache['slot'] = slotBg;
    end
    
    -- Load frame overlay
    local frame = LoadTextureFromPath(assetsDirectory .. 'frame.png');
    if frame then
        self.Cache['frame'] = frame;
    end
    
    -- Load spell icons - use proper path separator for Windows
    local spellDirectory = string.format(assetsDirectory .. '\\spells\\', AshitaCore:GetInstallPath());

    local spellContents = ashita.fs.get_directory(spellDirectory, '.*\\.png$');
    if spellContents then
        for _, file in pairs(spellContents) do
            local index = string.find(file, '%.');
            if index then
                local key = 'spells'.. string.sub(file, 1, index - 1);
                local fullPath = spellDirectory .. file;
                local texture = LoadTextureFromPath(fullPath);
                if texture then
                    self.Cache[file] = texture;  -- Store by full filename (e.g., "00086.png")
                    self.Cache[key] = texture;   -- Also store by key (e.g., "00086")
                    --print(string.format('[Hotbar] Loaded texture: %s (key: %s)', file, key));
                else
                    print(string.format('[Hotbar] Failed to load texture: %s', fullPath));
                end
            end
        end
    else
        print('[Hotbar] No PNG files found or directory does not exist');
    end

    -- Load controller button icons for crossbar (from subdirectories)
    local controllerDirectory = assetsDirectory .. 'controller\\';

    -- D-pad and triggers are in Shared folder
    local sharedIcons = { 'UP', 'DOWN', 'LEFT', 'RIGHT', 'L1', 'L2', 'R1', 'R2' };
    for _, iconName in ipairs(sharedIcons) do
        local fullPath = controllerDirectory .. 'Shared\\' .. iconName .. '.png';
        local texture = LoadTextureFromPath(fullPath);
        if texture then
            self.Cache['controller_' .. iconName] = texture;
        end
    end

    -- PlayStation face buttons
    local playstationIcons = { 'X', 'Square', 'Triangle', 'Circle' };
    for _, iconName in ipairs(playstationIcons) do
        local fullPath = controllerDirectory .. 'PlayStation\\' .. iconName .. '.png';
        local texture = LoadTextureFromPath(fullPath);
        if texture then
            self.Cache['controller_' .. iconName] = texture;
        end
    end

    -- Xbox face buttons (alternative naming)
    local xboxIcons = { { name = 'A', key = 'A' }, { name = 'B', key = 'B' }, { name = 'X', key = 'Xbox_X' }, { name = 'Y', key = 'Y' } };
    for _, icon in ipairs(xboxIcons) do
        local fullPath = controllerDirectory .. 'Xbox\\' .. icon.name .. '.png';
        local texture = LoadTextureFromPath(fullPath);
        if texture then
            self.Cache['controller_' .. icon.key] = texture;
        end
    end

    -- Load SMN icons (summons, abilities, pet commands) from hotbar/SMN directory
    local smnDirectory = string.format('%saddons\\XIUI\\assets\\hotbar\\SMN\\', AshitaCore:GetInstallPath());
    local smnIcons = {
        -- Summoning magic (avatars)
        { file = 'Carbuncle', key = 'summon_Carbuncle' },
        { file = 'Ifrit', key = 'summon_Ifrit' },
        { file = 'Shiva', key = 'summon_Shiva' },
        { file = 'Garuda', key = 'summon_Garuda' },
        { file = 'Titan', key = 'summon_Titan' },
        { file = 'Ramuh', key = 'summon_Ramuh' },
        { file = 'Leviathan', key = 'summon_Leviathan' },
        { file = 'Fenrir', key = 'summon_Fenrir' },
        { file = 'Diabolos', key = 'summon_Diabolos' },
        { file = 'CaitSith', key = 'summon_CaitSith' },
        { file = 'Alexander', key = 'summon_Alexander' },
        { file = 'Odin', key = 'summon_Odin' },
        { file = 'Atomos', key = 'summon_Atomos' },
        { file = 'Siren', key = 'summon_Siren' },
        -- Summoning magic (spirits)
        { file = 'FireSpirit', key = 'summon_FireSpirit' },
        { file = 'IceSpirit', key = 'summon_IceSpirit' },
        { file = 'AirSpirit', key = 'summon_AirSpirit' },
        { file = 'EarthSpirit', key = 'summon_EarthSpirit' },
        { file = 'ThunderSpirit', key = 'summon_ThunderSpirit' },
        { file = 'WaterSpirit', key = 'summon_WaterSpirit' },
        { file = 'LightSpirit', key = 'summon_LightSpirit' },
        { file = 'DarkSpirit', key = 'summon_DarkSpirit' },
        -- Pet commands
        { file = 'Assault', key = 'ability_Assault' },
        { file = 'Release', key = 'ability_Release' },
        { file = 'Retreat', key = 'ability_Retreat' },
        -- SMN job abilities
        { file = 'Apogee', key = 'ability_Apogee' },
        { file = 'AstralConduit1', key = 'ability_AstralConduit' },
        { file = 'AstralFlow', key = 'ability_AstralFlow' },
        { file = 'AvatarsFavor', key = 'ability_AvatarsFavor' },
        { file = 'ElementalSiphon', key = 'ability_ElementalSiphon' },
        { file = 'ManaCede', key = 'ability_ManaCede' },
    };
    for _, icon in ipairs(smnIcons) do
        local fullPath = smnDirectory .. icon.file .. '.png';
        local texture = LoadTextureFromPath(fullPath);
        if texture then
            self.Cache[icon.key] = texture;
        end
    end

    -- Load custom icons from hotbar/custom directory
    local customDirectory = string.format('%saddons\\XIUI\\assets\\hotbar\\custom\\', AshitaCore:GetInstallPath());

    -- Trust icons
    local trustIcons = {
        'ajido-marujido', 'amchuchu', 'ayame', 'cid', 'curilla', 'darrcuiln',
        'excenmille', 'halver', 'iron-eater', 'joachim', 'king-of-hearts',
        'koru-moru', 'kupipi', 'kuyin-hathdenna', 'lion', 'makki-chebukki',
        'mildaurion', 'mnejing', 'morimar', 'naja', 'naji', 'nanaa-mihgo',
        'ovjang', 'prishe', 'qultada', 'rahal', 'rongelouts', 'rughadjeen',
        'sakura', 'semih-lafihna', 'shantotto', 'shantotto-II', 'star-sibyl',
        'tenzen', 'trion', 'valaineral', 'volker', 'yoran-oran', 'zazarg',
        'zeid', 'zeid-II',
    };
    for _, name in ipairs(trustIcons) do
        local fullPath = customDirectory .. 'trusts\\trust-' .. name .. '.png';
        local texture = LoadTextureFromPath(fullPath);
        if texture then
            self.Cache['trust_' .. name] = texture;
        end
    end

    -- Blue magic icons
    local blueIcons = {
        'battle-dance', 'blank-gaze', 'cocoon', 'foot-kick', 'grand-slam',
        'headbutt', 'healing-breeze', 'jet-stream', 'light-of-penance',
        'magic-fruit', 'metallic-body', 'power-attack', 'sheep-song',
        'terror-touch', 'uppercut', 'wild-oats', 'zephyr-mantle',
    };
    for _, name in ipairs(blueIcons) do
        local fullPath = customDirectory .. 'blue\\blue-' .. name .. '.png';
        local texture = LoadTextureFromPath(fullPath);
        if texture then
            self.Cache['blue_' .. name:gsub('-', '_')] = texture;
        end
    end

    -- Mount icons
    local mountIcons = {
        'beetle', 'bomb', 'chocobo', 'crab', 'crawler', 'fenrir',
        'magic-pot', 'moogle', 'morbol', 'raptor', 'red-crab',
        'sheep', 'tiger', 'tulfaire', 'warmachine',
    };
    for _, name in ipairs(mountIcons) do
        local fullPath = customDirectory .. 'mounts\\mount-' .. name .. '.png';
        local texture = LoadTextureFromPath(fullPath);
        if texture then
            self.Cache['mount_' .. name:gsub('-', '_')] = texture;
        end
    end

    -- Rune Fencer rune icons (from custom root)
    local runeIcons = {
        { file = 'ignis-icon', key = 'rune_ignis' },
        { file = 'gelus-icon', key = 'rune_gelus' },
        { file = 'flabra-icon', key = 'rune_flabra' },
        { file = 'tellus-icon', key = 'rune_tellus' },
        { file = 'sulpor-icon', key = 'rune_sulpor' },
        { file = 'unda-icon', key = 'rune_unda' },
        { file = 'lux-icon', key = 'rune_lux' },
        { file = 'tenebrae-icon', key = 'rune_tenebrae' },
        -- RUN abilities
        { file = 'battuta-icon', key = 'ability_battuta' },
        { file = 'gambit-icon', key = 'ability_gambit' },
        { file = 'liement-icon', key = 'ability_liement' },
        { file = 'pflug-icon', key = 'ability_pflug' },
        { file = 'pulse-icon', key = 'ability_pulse' },
        { file = 'foil-icon', key = 'ability_foil' },
    };
    for _, icon in ipairs(runeIcons) do
        local fullPath = customDirectory .. icon.file .. '.png';
        local texture = LoadTextureFromPath(fullPath);
        if texture then
            self.Cache[icon.key] = texture;
        end
    end

    -- Misc utility icons
    local utilityIcons = {
        { file = 'attack', key = 'cmd_attack' },
        { file = 'disengage', key = 'cmd_disengage' },
        { file = 'fish', key = 'cmd_fish' },
        { file = 'fish2', key = 'cmd_fish2' },
        { file = 'dig', key = 'cmd_dig' },
        { file = 'mining', key = 'cmd_mining' },
        { file = 'harvest', key = 'cmd_harvest' },
        { file = 'mount', key = 'cmd_mount' },
        { file = 'dismount', key = 'cmd_dismount' },
        { file = 'check', key = 'cmd_check' },
        { file = 'claim', key = 'cmd_claim' },
        { file = 'heal', key = 'cmd_heal' },
        { file = 'synth', key = 'cmd_synth' },
        { file = 'return-trust', key = 'cmd_returntrust' },
        { file = 'macro', key = 'cmd_macro' },
        { file = 'gear', key = 'cmd_gear' },
        { file = 'gear2', key = 'cmd_gear2' },
        { file = 'gear3', key = 'cmd_gear3' },
        { file = 'gobbie', key = 'cmd_gobbie' },
        { file = 'jump', key = 'ability_jump' },
        { file = 'chainspell', key = 'ability_chainspell' },
        { file = 'stymie', key = 'ability_stymie' },
        { file = '2hr', key = 'ability_2hr' },
    };
    for _, icon in ipairs(utilityIcons) do
        local fullPath = customDirectory .. icon.file .. '.png';
        local texture = LoadTextureFromPath(fullPath);
        if texture then
            self.Cache[icon.key] = texture;
        end
    end

    -- UI indicator icons from assets/icons
    local iconsDirectory = string.format('%saddons\\XIUI\\assets\\icons\\', AshitaCore:GetInstallPath());
    local uiIcons = {
        { file = 'refresh', key = 'ui_refresh' },
    };
    for _, icon in ipairs(uiIcons) do
        local fullPath = iconsDirectory .. icon.file .. '.png';
        local texture = LoadTextureFromPath(fullPath);
        if texture then
            self.Cache[icon.key] = texture;
        end
    end

    -- Skillchain icons for WS slot highlighting
    local skillchainDirectory = string.format('%saddons\\XIUI\\assets\\hotbar\\skillchain\\', AshitaCore:GetInstallPath());
    local skillchainNames = {
        'Compression', 'Darkness', 'Detonation', 'Distortion',
        'Fragmentation', 'Fusion', 'Gravitation', 'Impaction',
        'Induration', 'Light', 'Liquefaction', 'Reverberation',
        'Scission', 'Transfixion',
    };
    for _, name in ipairs(skillchainNames) do
        local fullPath = skillchainDirectory .. name .. '.png';
        local texture = LoadTextureFromPath(fullPath);
        if texture then
            self.Cache['skillchain_' .. name] = texture;
        end
    end

end

textures.Release = function(self)
    if self.Cache then
        self.Cache = nil;
    end
end

-- Get texture by filename or key
textures.Get = function(self, key)
    if not self.Cache then
        return nil;
    end
    return self.Cache[key];
end

-- Get texture path by key (for primitive rendering)
textures.GetPath = function(self, key)
    if not self.Cache then return nil; end
    local entry = self.Cache[key];
    if entry and entry.path then
        return entry.path;
    end
    return nil;
end

-- Get controller button icon by name
-- iconName: 'X', 'Square', 'Triangle', 'Circle', 'L1', 'L2', 'R1', 'R2', 'UP', 'DOWN', 'LEFT', 'RIGHT'
textures.GetControllerIcon = function(self, iconName)
    if not self.Cache then
        return nil;
    end
    return self.Cache['controller_' .. iconName];
end

-- Map crossbar slot index to controller button name
-- Slots 1-4 are d-pad (UP, RIGHT, DOWN, LEFT in diamond order)
-- Slots 5-8 are face buttons (Triangle, Circle, X, Square in diamond order)
textures.GetButtonNameForSlot = function(self, slotIndex)
    local buttonMap = {
        [1] = 'UP',
        [2] = 'RIGHT',
        [3] = 'DOWN',
        [4] = 'LEFT',
        [5] = 'Triangle',
        [6] = 'Circle',
        [7] = 'X',
        [8] = 'Square',
    };
    return buttonMap[slotIndex];
end

-- ============================================
-- Item Icon File Cache System
-- Saves item bitmaps to disk for primitive rendering
-- ============================================

-- Get the item icon cache directory (creates if needed)
local function GetItemCacheDir()
    if not itemCacheDir then
        itemCacheDir = string.format('%saddons\\XIUI\\assets\\hotbar\\items\\', AshitaCore:GetInstallPath());
        -- Create directory if it doesn't exist
        ashita.fs.create_directory(itemCacheDir);
    end
    return itemCacheDir;
end

-- Get cached item icon path, creating cache file if needed
-- Loads texture with color key, extracts pixels, saves as PNG with alpha
-- @param itemId: The item ID to get icon for
-- @return: File path string if successfully cached, nil otherwise
textures.GetItemIconPath = function(self, itemId)
    if not itemId or itemId == 0 or itemId == 65535 then
        return nil;
    end

    local cacheDir = GetItemCacheDir();
    local fileName = string.format('%05d.png', itemId);
    local filePath = cacheDir .. fileName;

    -- Check if already cached on disk
    if ashita.fs.exists(filePath) then
        return filePath;
    end

    -- Get device
    local device = GetD3D8Device();
    if not device then return nil; end

    -- Get item bitmap from game resources
    local resMgr = AshitaCore:GetResourceManager();
    if not resMgr then return nil; end

    local item = resMgr:GetItemById(itemId);
    if not item then return nil; end
    if not item.Bitmap or not item.ImageSize or item.ImageSize <= 0 then
        return nil;
    end

    -- Load texture from memory with color key (black = transparent)
    -- D3DPOOL_SCRATCH (2) is lockable for pixel extraction
    local dx_texture_ptr = ffi.new('IDirect3DTexture8*[1]');
    local loadRes = ffi.C.D3DXCreateTextureFromFileInMemoryEx(
        device, item.Bitmap, item.ImageSize,
        0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
        ffi.C.D3DFMT_A8R8G8B8,
        2,  -- D3DPOOL_SCRATCH
        1, 1,  -- D3DX_FILTER_NONE
        0xFF000000,  -- Color key: black = transparent
        nil, nil, dx_texture_ptr
    );

    if loadRes ~= ffi.C.S_OK or dx_texture_ptr[0] == nil then
        return nil;
    end

    local texture = dx_texture_ptr[0];

    -- Get texture dimensions
    local descRes, desc = texture:GetLevelDesc(0);
    if descRes ~= ffi.C.S_OK or desc == nil then
        texture:Release();
        return nil;
    end
    local texWidth = desc.Width;
    local texHeight = desc.Height;

    -- Lock texture to read pixels
    local lockRes, lockedRect = texture:LockRect(0, nil, 0);
    if lockRes ~= ffi.C.S_OK or lockedRect == nil then
        texture:Release();
        return nil;
    end

    -- Upscale to 40x40 (matching spell icon size) with bilinear interpolation
    -- This improves quality because primitives use point sampling when scaling
    local targetSize = 40;
    local success, err = pngencoder.SavePNGFromLockedRectUpscaled(
        filePath,
        texWidth,
        texHeight,
        lockedRect.pBits,
        lockedRect.Pitch,
        targetSize,
        targetSize
    );

    texture:UnlockRect(0);
    texture:Release();

    if success and ashita.fs.exists(filePath) then
        return filePath;
    end

    return nil;
end

-- Load item icon with file path for primitive rendering
-- @param itemId: The item ID to load icon for
-- @return: Texture table { image, path, width, height } or nil
textures.LoadItemIcon = function(self, itemId)
    -- Get or create cached file path
    local iconPath = self:GetItemIconPath(itemId);
    if not iconPath then
        return nil;
    end

    -- Load PNG file (alpha already baked in, no color key needed)
    return LoadTextureFromPath(iconPath);
end

-- Load item icon from memory only (no PNG file creation)
-- For use in icon picker browsing - returns texture with NO path field
-- @param itemId: The item ID to load icon for
-- @return: Texture table { image, width, height } or nil (no path field)
textures.LoadItemIconFromMemory = function(self, itemId)
    if not itemId or itemId == 0 or itemId == 65535 then
        return nil;
    end

    local device = GetD3D8Device();
    if not device then return nil; end

    local resMgr = AshitaCore:GetResourceManager();
    if not resMgr then return nil; end

    local item = resMgr:GetItemById(itemId);
    if not item or not item.Bitmap or not item.ImageSize or item.ImageSize <= 0 then
        return nil;
    end

    -- Load texture from memory with color key (black = transparent)
    local dx_texture_ptr = ffi.new('IDirect3DTexture8*[1]');
    local loadRes = ffi.C.D3DXCreateTextureFromFileInMemoryEx(
        device, item.Bitmap, item.ImageSize,
        0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
        ffi.C.D3DFMT_A8R8G8B8,
        ffi.C.D3DPOOL_MANAGED,
        ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT,
        0xFF000000,  -- Color key: black = transparent
        nil, nil, dx_texture_ptr
    );

    if loadRes ~= ffi.C.S_OK or dx_texture_ptr[0] == nil then
        return nil;
    end

    -- Return texture WITHOUT path field (will use ImGui fallback in slotrenderer)
    return {
        image = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', dx_texture_ptr[0])),
        width = 32,  -- FFXI item icons are 32x32
        height = 32,
        -- Note: No 'path' field - this tells renderers to use ImGui fallback
    };
end

-- Expose LoadTextureFromPath for external use
textures.LoadTextureFromPath = function(self, filePath)
    return LoadTextureFromPath(filePath);
end

return textures;
