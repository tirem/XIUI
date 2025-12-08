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
local windowBg = require('libs.windowbackground');

local data = require('modules.petbar.data');
local display = require('modules.petbar.display');
local pettarget = require('modules.petbar.pettarget');

local petbar = {};

-- ============================================
-- Initialize
-- ============================================
petbar.Initialize = function(settings)
    -- Restore timers from config (session persistence)
    data.RestoreTimersFromConfig();

    -- Create fonts
    data.nameText = FontManager.create(settings.name_font_settings);
    data.distanceText = FontManager.create(settings.distance_font_settings);

    data.hpText = FontManager.create(settings.vitals_font_settings);
    data.hpText:set_font_alignment(gdi.Alignment.Right);
    data.mpText = FontManager.create(settings.vitals_font_settings);
    data.mpText:set_font_alignment(gdi.Alignment.Right);
    data.tpText = FontManager.create(settings.vitals_font_settings);
    data.tpText:set_font_alignment(gdi.Alignment.Right);

    data.allFonts = {data.nameText, data.distanceText, data.hpText, data.mpText, data.tpText};

    -- Initialize primitives - creation order determines render order
    -- Order: background -> pet images -> borders
    local prim_data = settings.prim_data or {
        visible = false,
        can_focus = false,
        locked = true,
        width = 100,
        height = 100,
    };

    local backgroundName = gConfig.petBarBackgroundTheme or 'Window1';
    data.loadedBgName = backgroundName;

    -- 1. Create background primitive first (renders at bottom)
    local bgHandle = windowBg.createBackground(prim_data, backgroundName, settings.bgScale);
    data.backgroundPrim['bg'] = bgHandle.bg;

    -- 2. Create pet image primitives (render in middle - petbar specific)
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

    -- 3. Create border primitives last (render on top)
    local borderHandle = windowBg.createBorders(prim_data, backgroundName);
    data.backgroundPrim['tl'] = borderHandle.tl;
    data.backgroundPrim['tr'] = borderHandle.tr;
    data.backgroundPrim['bl'] = borderHandle.bl;
    data.backgroundPrim['br'] = borderHandle.br;

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
        -- Update using windowbackground library
        windowBg.setBackgroundTheme(data.backgroundPrim, backgroundName, settings.bgScale);
        windowBg.setBordersTheme(data.backgroundPrim, backgroundName);
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

    -- Cleanup background and border primitives using windowbackground library
    windowBg.destroy(data.backgroundPrim);
    data.backgroundPrim = {};

    -- Cleanup pet image primitives (petbar specific)
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
