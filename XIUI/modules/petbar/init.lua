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
local abilityRecast = require('libs.abilityrecast');
local TextureManager = require('libs.texturemanager');

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

    -- BST timer fonts (jug countdown, charm elapsed)
    data.bstTimerText = FontManager.create(settings.vitals_font_settings);

    -- Full display mode fonts (recast name + timer for each slot)
    data.recastNameFonts = {};
    data.recastTimerFonts = {};
    for i = 1, data.MAX_RECAST_SLOTS do
        data.recastNameFonts[i] = FontManager.create(settings.vitals_font_settings);
        data.recastTimerFonts[i] = FontManager.create(settings.vitals_font_settings);
    end

    data.allFonts = {data.nameText, data.distanceText, data.hpText, data.mpText, data.tpText, data.bstTimerText};
    -- Add recast fonts to allFonts for batch visibility control
    for i = 1, data.MAX_RECAST_SLOTS do
        table.insert(data.allFonts, data.recastNameFonts[i]);
        table.insert(data.allFonts, data.recastTimerFonts[i]);
    end

    -- Load jug icon texture (via TextureManager)
    data.jugIconTexture = TextureManager.getFileTexture('pets/jug');

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
    for _, petName in ipairs(data.allPetsWithImages) do
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
            -- Try to get actual texture dimensions and store texture for ImGui (via TextureManager)
            if prim.exists then
                local texture = TextureManager.getFileTexture(string.format('pets/%s', data.petImageMap[petName]:gsub('%.png$', '')));
                if texture and texture.image then
                    prim.baseWidth, prim.baseHeight = GetTextureDimensions(texture, 256, 256);
                    -- Store full texture object for ImGui rendering (keeps reference alive)
                    data.petImageTextures[key] = texture;
                end
            end
            data.petImagePrims[key] = prim;
        end
    end

    -- 3. Create border primitives (render on top of middle layer)
    local borderHandle = windowBg.createBorders(prim_data, backgroundName, settings.borderScale);
    data.backgroundPrim['tl'] = borderHandle.tl;
    data.backgroundPrim['tr'] = borderHandle.tr;
    data.backgroundPrim['bl'] = borderHandle.bl;
    data.backgroundPrim['br'] = borderHandle.br;

    -- 4. Create pet image primitives for TOP layer (render on top of borders - for unclipped mode)
    data.petImagePrimsTop = {};
    for _, petName in ipairs(data.allPetsWithImages) do
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
            -- Copy base dimensions from middle layer prim
            local middlePrim = data.petImagePrims[key];
            if middlePrim then
                prim.baseWidth = middlePrim.baseWidth;
                prim.baseHeight = middlePrim.baseHeight;
            else
                prim.baseWidth = 256;
                prim.baseHeight = 256;
            end
            data.petImagePrimsTop[key] = prim;
        end
    end

    -- Initialize pet target module
    pettarget.Initialize(settings);

    -- ============================================
    -- Packet Handler: Charm Duration Tracking
    -- ============================================
    -- Intercepts Charm ability usage and /check packets to calculate charm duration
    -- based on mob level and player stats
    ashita.events.register('packet_out', 'petbar_packet_out', function (e)
        -- Modify outgoing /check packet to target the charmed mob
        if (e.id == data.PacketID.OUT_CHECK) then
            if (data.charmState == data.CharmState.SENDING_PACKET) then
                local pktdata = e.data:totable();
                local pckt = struct.pack("BBBBHBBHBBBBBB", 
                    pktdata[1], pktdata[2], pktdata[3], pktdata[4],
                    data.charmTarget, pktdata[7], pktdata[8], data.charmTargetIdx,
                    pktdata[11], pktdata[12], pktdata[13], pktdata[14],
                    pktdata[15], pktdata[16]);
                e.data_modified = pckt;
                data.charmState = data.CharmState.CHECK_PACKET;
            end
        end

        -- Detect Charm ability usage and queue /check command
        if (e.id == data.PacketID.OUT_ACTION) then
            local category = struct.unpack('H', e.data, 0x0A + 0x01);
            local actionId = struct.unpack('H', e.data, 0x0C + 0x01);

            if (category == 0x09 and actionId == data.ActionID.CHARM) then
                -- Validate: Player must not have a pet
                if (data.petType ~= nil) then return; end

                -- Force reset state and start fresh tracking
                data.charmState = data.CharmState.SENDING_PACKET;
                data.charmTarget = struct.unpack('H', e.data, 0x04 + 0x01);
                data.charmTargetIdx = struct.unpack('H', e.data, 0x08 + 0x01);
                AshitaCore:GetChatManager():QueueCommand(1, "/check");
            end
        end
    end);
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

    -- BST timer fonts
    data.bstTimerText = FontManager.recreate(data.bstTimerText, settings.vitals_font_settings);

    -- Full display mode fonts
    for i = 1, data.MAX_RECAST_SLOTS do
        data.recastNameFonts[i] = FontManager.recreate(data.recastNameFonts[i], settings.vitals_font_settings);
        data.recastTimerFonts[i] = FontManager.recreate(data.recastTimerFonts[i], settings.vitals_font_settings);
    end

    data.allFonts = {data.nameText, data.distanceText, data.hpText, data.mpText, data.tpText, data.bstTimerText};
    for i = 1, data.MAX_RECAST_SLOTS do
        table.insert(data.allFonts, data.recastNameFonts[i]);
        table.insert(data.allFonts, data.recastTimerFonts[i]);
    end

    -- Clear cached colors
    data.ClearColorCache();

    -- Background theme changes are now handled dynamically in data.UpdateBackground()
    -- based on per-pet-type settings

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
    data.bstTimerText = FontManager.destroy(data.bstTimerText);

    -- Cleanup full display mode fonts
    if data.recastNameFonts then
        for i = 1, data.MAX_RECAST_SLOTS do
            data.recastNameFonts[i] = FontManager.destroy(data.recastNameFonts[i]);
        end
        data.recastNameFonts = nil;
    end
    if data.recastTimerFonts then
        for i = 1, data.MAX_RECAST_SLOTS do
            data.recastTimerFonts[i] = FontManager.destroy(data.recastTimerFonts[i]);
        end
        data.recastTimerFonts = nil;
    end

    data.allFonts = nil;
    data.jugIconTexture = nil;

    -- Cleanup background and border primitives using windowbackground library
    windowBg.destroy(data.backgroundPrim);
    data.backgroundPrim = {};

    -- Cleanup pet image primitives (petbar specific) - both layers
    if data.petImagePrims then
        for _, prim in pairs(data.petImagePrims) do
            if prim then
                prim:destroy();
            end
        end
        data.petImagePrims = nil;
    end
    if data.petImagePrimsTop then
        for _, prim in pairs(data.petImagePrimsTop) do
            if prim then
                prim:destroy();
            end
        end
        data.petImagePrimsTop = nil;
    end

    -- Clear pet image textures (D3D handles cleanup via gc_safe_release)
    data.petImageTextures = {};

    -- Cleanup pet target module
    pettarget.Cleanup();

    -- Reset data state
    data.Reset();

    ashita.events.unregister('packet_out', 'petbar_packet_out');
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

    -- Process incoming /check response to extract mob level for charm duration
    -- Note: Only /check packets initiated by Charm are suppressed. Other /check output
    -- (from checker addon, manual /check commands, etc.) will display normally.
    if (e.id == data.PacketID.IN_CHECK) then
        if (data.charmState == data.CharmState.CHECK_PACKET) then
            local param1 = struct.unpack('l', e.data, 0x0C + 0x01);
            local param2 = struct.unpack('L', e.data, 0x10 + 0x01);
            local msg    = struct.unpack('H', e.data, 0x18 + 0x01);

            -- Validate message type indicates check parameters
            if ( ((msg >= 0xAA) and (msg <= 0xB2)) or ((param2 >= 0x40) and (param2 <= 0x47))) then
                e.blocked = true; -- Suppress chat output

                -- Calculate charm duration from mob level
                data.charmExpireTime = data.calculateCharmTime(param1);
                data.charmStartTime = os.time();

                -- Persist to config
                if gConfig then
                    gConfig.petBarCharmExpireTime = data.charmExpireTime;
                end
            end
            data.charmState = data.CharmState.NONE;
        end
        return;
    end
end

return petbar;
