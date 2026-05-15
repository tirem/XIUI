--[[
* XIUI Pet Bar Module
* Main entry point that provides access to data, display, and pettarget modules
* Displays pet information for SMN, BST, DRG, and PUP
]]--

require('common');
require('handlers.helpers');
local imtext = require('libs.imtext');
local ffi = require('ffi');
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

    -- Load jug icon texture (via TextureManager)
    data.jugIconTexture = TextureManager.getFileTexture('pets/jug');

    -- Load pet image textures + base dimensions (rendered via drawList:AddImage in data.UpdateBackground)
    data.petImageTextures = {};
    data.petImageMeta = {};
    for _, petName in ipairs(data.allPetsWithImages) do
        local key = data.GetPetSettingsKey(petName);
        local imageFile = data.petImageMap[petName];
        if imageFile then
            local texture = TextureManager.getFileTexture(string.format('pets/%s', imageFile:gsub('%.png$', '')));
            if texture and texture.image then
                local baseWidth, baseHeight = GetTextureDimensions(texture, 256, 256);
                data.petImageTextures[key] = texture;
                data.petImageMeta[key] = { baseWidth = baseWidth, baseHeight = baseHeight, exists = true };
            else
                data.petImageMeta[key] = { baseWidth = 256, baseHeight = 256, exists = false };
            end
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
    imtext.Reset();


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
        data.HideBackground();
        pettarget.SetHidden(true);
    end
end

-- ============================================
-- Cleanup
-- ============================================
petbar.Cleanup = function()
    data.jugIconTexture = nil;

    -- Clear pet image textures - gc_safe_release handles D3D Release() via FFI finalizers
    if data.petImageTextures then
        for key, _ in pairs(data.petImageTextures) do
            data.petImageTextures[key] = nil;
        end
        data.petImageTextures = {};
    end
    data.petImageMeta = {};

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
        local actorId = struct.unpack('I', e.data_modified, 0x05 + 0x01);
        local rawActionInfo = struct.unpack('H', e.data_modified, 0x0A + 0x01);
        if playerEntity == nil then return; end

        -- Check for Familiar usage (0x618) on self
        if (actorId == playerEntity.ServerId and rawActionInfo == 0x618) then
             if (data.petType == 'charm') then
                 data.ExtendCharmDuration(1500);
             end
        end

        if playerEntity.PetTargetIndex == 0 then
            return;
        end

        local pet = GetEntity(playerEntity.PetTargetIndex);
        if pet == nil then
            return;
        end

        -- Check if the actor is our pet
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
                    gConfig.petBarCharmLevel = param1;
                    gConfig.petBarCharmExpireTime = data.charmExpireTime;
                end
            end
            data.charmState = data.CharmState.NONE;
        end
        return;
    end
end

petbar.ResetPositions = function()
    display.ResetPositions();
end

return petbar;
