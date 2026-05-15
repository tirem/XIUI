--[[
    Party List Module for XIUI
    Main entry point that provides access to data and display modules
]]

require('common');
require('handlers.helpers');
local ffi = require('ffi');
local windowBg = require('libs.windowbackground');
local encoding = require('libs.encoding');
local TextureManager = require('libs.texturemanager');

local data = require('modules.partylist.data');
local display = require('modules.partylist.display');

local partyList = {};

-- Export partyCasts for external access (packet handlers)
partyList.partyCasts = data.partyCasts;

-- ============================================
-- Initialize
-- ============================================
partyList.Initialize = function(settings)
    -- Initialize config cache
    data.partyConfigCacheValid = false;
    data.updatePartyConfigCache();

    -- Cache initial font sizes
    data.cachedFontSizes = {
        settings.fontSizes[1],
        settings.fontSizes[2],
        settings.fontSizes[3],
    };

    -- Cache initial font settings
    data.cachedFontFamily = settings.name_font_settings.font_family or '';
    data.cachedFontFlags = settings.name_font_settings.font_flags or 0;
    data.cachedOutlineWidth = settings.name_font_settings.outline_width or 2;

    -- Load party titles texture (via TextureManager)
    data.partyTitlesTexture = TextureManager.getFileTexture('PartyList-Titles');
    if (data.partyTitlesTexture ~= nil) then
        data.partyTitlesTexture.width, data.partyTitlesTexture.height = GetTextureDimensions(data.partyTitlesTexture, 64, 64);
    end

    -- Initialize background primitives using windowbackground library
    data.loadedBg = {};

    for partyIndex = 1, 3 do
        local cache = data.partyConfigCache[partyIndex];
        data.loadedBg[partyIndex] = cache.backgroundName;

        -- Create combined background + borders using windowbackground library
        data.partyWindowPrim[partyIndex].background = windowBg.create(
            settings.prim_data,
            cache.backgroundName,
            cache.bgScale,
            cache.borderScale
        );
    end

    -- Load cursor textures (via TextureManager)
    for partyIndex = 1, 3 do
        local cache = data.partyConfigCache[partyIndex];
        local cursorName = cache.cursor;
        if cursorName and cursorName ~= '' and not data.cursorTextures[cursorName] then
            local cursorTexture = TextureManager.getFileTexture(string.format('cursors/%s', cursorName:gsub('%.png$', '')));
            if cursorTexture then
                cursorTexture.width, cursorTexture.height = GetTextureDimensions(cursorTexture, 32, 32);
                data.cursorTextures[cursorName] = cursorTexture;
            end
        end
    end
end

-- ============================================
-- UpdateVisuals
-- ============================================
partyList.UpdateVisuals = function(settings)
    -- Refresh config cache
    data.partyConfigCacheValid = false;
    data.updatePartyConfigCache();

    data.maxTpTextWidthCache = { [1] = nil, [2] = nil, [3] = nil };
    display.ResetFont();

    -- Update cached font sizes
    for partyIndex = 1, 3 do
        data.cachedFontSizes[partyIndex] = settings.fontSizes[partyIndex];
    end
    data.cachedFontFamily = settings.name_font_settings.font_family or '';
    data.cachedFontFlags = settings.name_font_settings.font_flags or 0;
    data.cachedOutlineWidth = settings.name_font_settings.outline_width or 2;

    -- Update cursor textures (via TextureManager)
    for partyIndex = 1, 3 do
        local cache = data.partyConfigCache[partyIndex];
        local cursorName = cache.cursor;
        if cursorName and cursorName ~= '' and not data.cursorTextures[cursorName] then
            local cursorTexture = TextureManager.getFileTexture(string.format('cursors/%s', cursorName:gsub('%.png$', '')));
            if cursorTexture then
                cursorTexture.width, cursorTexture.height = GetTextureDimensions(cursorTexture, 32, 32);
                data.cursorTextures[cursorName] = cursorTexture;
            end
        end
    end

    -- Update background primitives using windowbackground library
    for partyIndex = 1, 3 do
        local cache = data.partyConfigCache[partyIndex];
        local backgroundPrim = data.partyWindowPrim[partyIndex].background;

        -- Track loaded backgrounds per-party
        local bgChanged = cache.backgroundName ~= data.loadedBg[partyIndex];
        data.loadedBg[partyIndex] = cache.backgroundName;

        if bgChanged then
            windowBg.setTheme(backgroundPrim, cache.backgroundName, cache.bgScale, cache.borderScale);
        end
    end
end

-- ============================================
-- DrawWindow
-- ============================================
partyList.DrawWindow = function(settings)
    display.DrawWindow(settings);
end

-- ============================================
-- SetHidden
-- ============================================
partyList.SetHidden = function(hidden)
    data.UpdateTextVisibility(not hidden);
end

-- ============================================
-- Cleanup
-- ============================================
partyList.Cleanup = function()
    -- Destroy background primitives using windowbackground library
    for i = 1, 3 do
        local backgroundPrim = data.partyWindowPrim[i].background;
        if backgroundPrim then
            windowBg.destroy(backgroundPrim);
            data.partyWindowPrim[i].background = nil;
        end
    end

    -- Reset state
    data.Reset();
end

-- ============================================
-- Packet Handlers
-- ============================================
partyList.HandleZonePacket = function(e)
    -- Clear cast data on zone
    data.partyCasts = {};
    partyList.partyCasts = data.partyCasts;
end

-- ============================================
-- ResetPositions
-- ============================================
partyList.ResetPositions = function()
    display.ResetPositions();
end

partyList.HandleActionPacket = function(actionPacket)
    if (actionPacket == nil or actionPacket.UserId == nil) then
        return;
    end

    -- Type 8 = Magic (Start)
    if (actionPacket.Type == 8) then
        if (actionPacket.Targets and #actionPacket.Targets > 0 and
            actionPacket.Targets[1].Actions and #actionPacket.Targets[1].Actions > 0) then
            local spellId = actionPacket.Targets[1].Actions[1].Param;
            local existingCast = data.partyCasts[actionPacket.UserId];

            if (existingCast ~= nil and existingCast.spellId == spellId) then
                data.partyCasts[actionPacket.UserId] = nil;
                return;
            end

            if (existingCast ~= nil and existingCast.spellId ~= spellId) then
                data.partyCasts[actionPacket.UserId] = nil;
            end

            local spell = AshitaCore:GetResourceManager():GetSpellById(spellId);
            if (spell ~= nil and spell.Name[1] ~= nil) then
                local spellName = encoding:ShiftJIS_To_UTF8(spell.Name[1], true);
                local castTime = spell.CastTime / 4.0;
                local spellType = spell.Skill;

                local memberJob = nil;
                local memberSubjob = nil;
                local memberJobLevel = nil;
                local memberSubjobLevel = nil;
                local party = GetPartySafe();
                if (party) then
                    for i = 0, 17 do
                        if (party:GetMemberServerId(i) == actionPacket.UserId) then
                            memberJob = party:GetMemberMainJob(i);
                            memberSubjob = party:GetMemberSubJob(i);
                            memberJobLevel = party:GetMemberMainJobLevel(i);
                            memberSubjobLevel = party:GetMemberSubJobLevel(i);
                            break;
                        end
                    end
                end

                data.partyCasts[actionPacket.UserId] = T{
                    spellName = spellName,
                    spellId = spellId,
                    spellType = spellType,
                    castTime = castTime,
                    startTime = os.clock(),
                    timestamp = os.time(),
                    job = memberJob,
                    subjob = memberSubjob,
                    jobLevel = memberJobLevel,
                    subjobLevel = memberSubjobLevel
                };
            end
        end
    -- Type 4 = Magic (Finish), Type 11 = Monster Skill (Finish)
    elseif (actionPacket.Type == 4 or actionPacket.Type == 11) then
        local party = GetPartySafe();
        local localPlayerId = party and party:GetMemberServerId(0) or nil;
        if (actionPacket.UserId ~= localPlayerId) then
            data.partyCasts[actionPacket.UserId] = nil;
        end
    end

    -- Cleanup stale casts
    local now = os.time();
    for serverId, castData in pairs(data.partyCasts) do
        if (castData.timestamp + 30 < now) then
            data.partyCasts[serverId] = nil;
        end
    end

    -- Keep external reference in sync
    partyList.partyCasts = data.partyCasts;
end

return partyList;
