--[[
* XIUI hotbar - Texture Loading Module
* Loads and caches spell/ability icons
]]--

require('handlers.helpers');
local ffi = require('ffi');
local d3d8 = require('d3d8');

-- Load texture from full file path
local function LoadTextureFromPath(filePath)
    local device = GetD3D8Device();
    if (device == nil) then return nil; end

    local textures = T{};
    local texture_ptr = ffi.new('IDirect3DTexture8*[1]');
    local res = ffi.C.D3DXCreateTextureFromFileA(device, filePath, texture_ptr);
    if (res ~= ffi.C.S_OK) then
        return nil;
    end
    textures.image = ffi.new('IDirect3DTexture8*', texture_ptr[0]);
    d3d8.gc_safe_release(textures.image);

    return textures;
end

local textures = {};

textures.Initialize = function(self)
    if self.Cache then
        return;
    end

    self.Cache = {};
    
    -- Load slot background and frame images
    local imagesDirectory = string.format('%saddons\\XIUI\\modules\\hotbar\\images\\', AshitaCore:GetInstallPath());
    
    -- Load slot background
    local slotBg = LoadTextureFromPath(imagesDirectory .. 'slot.png');
    if slotBg then
        self.Cache['slot'] = slotBg;
        print('[Hotbar] Loaded slot background texture');
    end
    
    -- Load frame overlay
    local frame = LoadTextureFromPath(imagesDirectory .. 'frame.png');
    if frame then
        self.Cache['frame'] = frame;
        print('[Hotbar] Loaded frame texture');
    end
    
    -- Load spell icons - use proper path separator for Windows
    local spellDirectory = string.format('%saddons\\XIUI\\modules\\hotbar\\images\\icons\\spells\\', AshitaCore:GetInstallPath());
    
    print(string.format('[Hotbar] Loading textures from: %s', spellDirectory));
    
    local spellContents = ashita.fs.get_directory(spellDirectory, '.*\\.png$');
    if spellContents then
        print(string.format('[Hotbar] Found %d PNG files', #spellContents));
        for _, file in pairs(spellContents) do
            local index = string.find(file, '%.');
            if index then
                local key = string.sub(file, 1, index - 1);
                local fullPath = spellDirectory .. file;
                local texture = LoadTextureFromPath(fullPath);
                if texture then
                    self.Cache[file] = texture;  -- Store by full filename (e.g., "00086.png")
                    self.Cache[key] = texture;   -- Also store by key (e.g., "00086")
                    print(string.format('[Hotbar] Loaded texture: %s (key: %s)', file, key));
                else
                    print(string.format('[Hotbar] Failed to load texture: %s', fullPath));
                end
            end
        end
    else
        print('[Hotbar] No PNG files found or directory does not exist');
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

return textures;
