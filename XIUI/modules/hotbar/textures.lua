--[[
* XIUI hotbar - Texture Loading Module
* Loads and caches spell/ability icons
]]--

require('handlers.helpers');
local ffi = require('ffi');
local d3d8 = require('d3d8');

-- Load texture from full file path
-- Returns: { image = IDirect3DTexture8*, path = filePath, width = 40, height = 40 }
local function LoadTextureFromPath(filePath)
    local device = GetD3D8Device();
    if (device == nil) then return nil; end

    local textureData = T{};
    local texture_ptr = ffi.new('IDirect3DTexture8*[1]');
    local res = ffi.C.D3DXCreateTextureFromFileA(device, filePath, texture_ptr);
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

return textures;
