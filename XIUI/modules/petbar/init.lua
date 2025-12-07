--[[
* XIUI Pet Bar Module
* Main entry point that provides access to data, display, and pettarget modules
* Displays pet information for SMN, BST, DRG, and PUP
]]--

require('common');
require('handlers.helpers');
local gdi = require('submodules.gdifonts.include');
local primitives = require('primitives');
local ffi = require('ffi');

local data = require('modules.petbar.data');
local display = require('modules.petbar.display');
local pettarget = require('modules.petbar.pettarget');

local petbar = {};

-- ============================================
-- Initialize
-- ============================================
petbar.Initialize = function(settings)
    -- Create fonts
    data.nameText = FontManager.create(settings.name_font_settings);
    data.distanceText = FontManager.create(settings.distance_font_settings);
    data.distanceText:set_font_alignment(gdi.Alignment.Right);

    data.hpText = FontManager.create(settings.vitals_font_settings);
    data.hpText:set_font_alignment(gdi.Alignment.Right);
    data.mpText = FontManager.create(settings.vitals_font_settings);
    data.mpText:set_font_alignment(gdi.Alignment.Right);
    data.tpText = FontManager.create(settings.vitals_font_settings);
    data.tpText:set_font_alignment(gdi.Alignment.Right);

    data.allFonts = {data.nameText, data.distanceText, data.hpText, data.mpText, data.tpText};

    -- Initialize background primitives
    local prim_data = settings.prim_data or {
        visible = false,
        can_focus = false,
        locked = true,
        width = 100,
        height = 100,
    };

    for _, k in ipairs(data.bgImageKeys) do
        data.backgroundPrim[k] = primitives:new(prim_data);
        data.backgroundPrim[k].visible = false;
        data.backgroundPrim[k].can_focus = false;
        data.backgroundPrim[k].exists = false;
    end

    -- Load background textures
    local backgroundName = gConfig.petBarBackgroundTheme or 'Window1';
    data.loadedBgName = backgroundName;

    for _, k in ipairs(data.bgImageKeys) do
        local filepath;
        if backgroundName == '-None-' then
            -- No background - set exists to false
            data.backgroundPrim[k].exists = false;
        else
            local file_name = string.format('%s-%s.png', backgroundName, k);
            filepath = string.format('%s/assets/backgrounds/%s', addon.path, file_name);
            data.backgroundPrim[k].texture = filepath;
            data.backgroundPrim[k].exists = ashita.fs.exists(filepath);
        end
        if k == 'bg' then
            data.backgroundPrim[k].scale_x = settings.bgScale or 1.0;
            data.backgroundPrim[k].scale_y = settings.bgScale or 1.0;
        else
            data.backgroundPrim[k].scale_x = 1.0;
            data.backgroundPrim[k].scale_y = 1.0;
        end
    end

    -- Initialize pet image primitives (one per avatar for preloading)
    data.petImagePrims = {};
    data.petImageTextures = {};
    for _, petName in ipairs(data.avatarList) do
        local key = data.GetPetSettingsKey(petName);
        local imagePath = data.GetPetImagePath(petName);
        if imagePath then
            local prim = primitives:new(prim_data);
            prim.visible = false;
            prim.can_focus = false;
            prim.texture = imagePath;
            prim.exists = ashita.fs.exists(imagePath);
            prim.scale_x = 1.0;
            prim.scale_y = 1.0;
            -- Store base dimensions for clipping calculations
            prim.baseWidth = 256;
            prim.baseHeight = 256;
            -- Try to get actual texture dimensions and store texture for ImGui
            if prim.exists then
                local texture = LoadTextureWithExt(string.format('pets/%s', data.petImageMap[petName]:gsub('%.png$', '')), 'png');
                if texture and texture.image then
                    local texture_ptr = ffi.cast('IDirect3DTexture8*', texture.image);
                    local res, desc = texture_ptr:GetLevelDesc(0);
                    if desc then
                        prim.baseWidth = desc.Width;
                        prim.baseHeight = desc.Height;
                    end
                    -- Store full texture object for ImGui rendering (keeps reference alive)
                    data.petImageTextures[key] = texture;
                end
            end
            data.petImagePrims[key] = prim;
        end
    end

    -- Initialize pet target module
    pettarget.Initialize(settings);
end

-- ============================================
-- UpdateVisuals
-- ============================================
petbar.UpdateVisuals = function(settings)
    -- Recreate fonts
    data.nameText = FontManager.recreate(data.nameText, settings.name_font_settings);
    data.distanceText = FontManager.recreate(data.distanceText, settings.distance_font_settings);
    data.distanceText:set_font_alignment(gdi.Alignment.Right);

    data.hpText = FontManager.recreate(data.hpText, settings.vitals_font_settings);
    data.hpText:set_font_alignment(gdi.Alignment.Right);
    data.mpText = FontManager.recreate(data.mpText, settings.vitals_font_settings);
    data.mpText:set_font_alignment(gdi.Alignment.Right);
    data.tpText = FontManager.recreate(data.tpText, settings.vitals_font_settings);
    data.tpText:set_font_alignment(gdi.Alignment.Right);

    data.allFonts = {data.nameText, data.distanceText, data.hpText, data.mpText, data.tpText};

    -- Clear cached colors
    data.ClearColorCache();

    -- Update background textures if theme changed
    local backgroundName = gConfig.petBarBackgroundTheme or 'Window1';
    if data.loadedBgName ~= backgroundName then
        data.loadedBgName = backgroundName;
        for _, k in ipairs(data.bgImageKeys) do
            if backgroundName == '-None-' then
                data.backgroundPrim[k].exists = false;
            else
                local file_name = string.format('%s-%s.png', backgroundName, k);
                local filepath = string.format('%s/assets/backgrounds/%s', addon.path, file_name);
                data.backgroundPrim[k].texture = filepath;
                data.backgroundPrim[k].exists = ashita.fs.exists(filepath);
            end
        end
    end

    -- Update pet target module
    pettarget.UpdateVisuals(settings);
end

-- ============================================
-- DrawWindow
-- ============================================
petbar.DrawWindow = function(settings)
    -- Draw main pet bar, returns true if pet exists
    local hasPet = display.DrawWindow(settings);

    -- Draw pet target window (only if pet exists and has a target)
    if hasPet then
        pettarget.DrawWindow(settings);
    else
        pettarget.SetHidden(true);
    end
end

-- ============================================
-- SetHidden
-- ============================================
petbar.SetHidden = function(hidden)
    if hidden then
        data.SetAllFontsVisible(false);
        data.HideBackground();
        pettarget.SetHidden(true);
    end
end

-- ============================================
-- Cleanup
-- ============================================
petbar.Cleanup = function()
    data.nameText = FontManager.destroy(data.nameText);
    data.distanceText = FontManager.destroy(data.distanceText);
    data.hpText = FontManager.destroy(data.hpText);
    data.mpText = FontManager.destroy(data.mpText);
    data.tpText = FontManager.destroy(data.tpText);

    data.allFonts = nil;

    -- Cleanup background primitives
    for _, k in ipairs(data.bgImageKeys) do
        if data.backgroundPrim[k] then
            data.backgroundPrim[k]:destroy();
            data.backgroundPrim[k] = nil;
        end
    end

    -- Cleanup pet image primitives
    if data.petImagePrims then
        for _, prim in pairs(data.petImagePrims) do
            if prim then
                prim:destroy();
            end
        end
        data.petImagePrims = nil;
    end

    -- Clear pet image textures (D3D handles cleanup via gc_safe_release)
    data.petImageTextures = {};

    -- Cleanup pet target module
    pettarget.Cleanup();

    -- Reset data state
    data.Reset();
end

-- ============================================
-- Packet Handler
-- ============================================
petbar.HandlePacket = function(e)
    -- Packet: Action (0x0028)
    if e.id == 0x0028 then
        local playerEntity = GetPlayerEntity();
        if playerEntity == nil or playerEntity.PetTargetIndex == 0 then
            return;
        end

        local pet = GetEntity(playerEntity.PetTargetIndex);
        if pet == nil then
            return;
        end

        -- Check if the actor is our pet
        local actorId = struct.unpack('I', e.data_modified, 0x05 + 0x01);
        if actorId ~= 0 and actorId == pet.ServerId then
            local targetId = ashita.bits.unpack_be(e.data_modified:totable(), 0x96, 0x20);
            if targetId and targetId ~= 0 then
                data.petTargetServerId = targetId;
            end
        end
        return;
    end

    -- Packet: Pet Sync (0x0068)
    if e.id == 0x0068 then
        local playerEntity = GetPlayerEntity();
        if playerEntity == nil then
            return;
        end

        local owner = struct.unpack('I', e.data_modified, 0x08 + 0x01);
        if owner == playerEntity.ServerId then
            local targetId = struct.unpack('I', e.data_modified, 0x14 + 0x01);
            if targetId and targetId ~= 0 then
                data.petTargetServerId = targetId;
            end
        end
        return;
    end
end

return petbar;
