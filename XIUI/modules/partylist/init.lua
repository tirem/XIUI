--[[
    Party List Module for XIUI
    Main entry point that provides access to data and display modules
]]

require('common');
require('handlers.helpers');
local ffi = require('ffi');
local gdi = require('submodules.gdifonts.include');
local windowBg = require('libs.windowbackground');
local encoding = require('submodules.gdifonts.encoding');
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

    -- Initialize font objects
    for i = 0, data.memberTextCount - 1 do
        local partyIndex = math.ceil((i + 1) / data.partyMaxSize);
        local fontSizes = data.getFontSizes(partyIndex);

        local name_font_settings = deep_copy_table(settings.name_font_settings);
        local hp_font_settings = deep_copy_table(settings.hp_font_settings);
        local mp_font_settings = deep_copy_table(settings.mp_font_settings);
        local tp_font_settings = deep_copy_table(settings.tp_font_settings);
        local distance_font_settings = deep_copy_table(settings.name_font_settings);
        local zone_font_settings = deep_copy_table(settings.name_font_settings);
        local job_font_settings = deep_copy_table(settings.name_font_settings);

        name_font_settings.font_height = math.max(fontSizes.name, 6);
        hp_font_settings.font_height = math.max(fontSizes.hp, 6);
        mp_font_settings.font_height = math.max(fontSizes.mp, 6);
        tp_font_settings.font_height = math.max(fontSizes.tp, 6);
        distance_font_settings.font_height = math.max(fontSizes.distance, 6);
        distance_font_settings.font_alignment = 2; -- Right-align so text doesn't shift as distance changes
        zone_font_settings.font_height = math.max(fontSizes.zone, 6);
        job_font_settings.font_height = math.max(fontSizes.job, 6);

        data.memberText[i] = {};
        data.memberText[i].name = FontManager.create(name_font_settings);
        data.memberText[i].hp = FontManager.create(hp_font_settings);
        data.memberText[i].mp = FontManager.create(mp_font_settings);
        data.memberText[i].tp = FontManager.create(tp_font_settings);
        data.memberText[i].distance = FontManager.create(distance_font_settings);
        data.memberText[i].zone = FontManager.create(zone_font_settings);
        data.memberText[i].job = FontManager.create(job_font_settings);
    end

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

    -- Calculate initial reference heights
    for partyIndex = 1, 3 do
        data.calculateRefHeights(partyIndex);
    end
    data.partyRefHeightsValid = true;

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

    -- Clear text caches since font settings may have changed
    data.memberTextCache = {};
    data.maxTpTextWidthCache = { [1] = nil, [2] = nil, [3] = nil };

    -- Check if font settings changed
    local fontFamilyChanged = false;
    local fontFlagsChanged = false;
    local outlineWidthChanged = false;

    if settings.name_font_settings.font_family ~= data.cachedFontFamily then
        fontFamilyChanged = true;
        data.cachedFontFamily = settings.name_font_settings.font_family;
    end

    if settings.name_font_settings.font_flags ~= data.cachedFontFlags then
        fontFlagsChanged = true;
        data.cachedFontFlags = settings.name_font_settings.font_flags;
    end

    if settings.name_font_settings.outline_width ~= data.cachedOutlineWidth then
        outlineWidthChanged = true;
        data.cachedOutlineWidth = settings.name_font_settings.outline_width;
    end

    -- Check which party font sizes changed
    local sizesChanged = {false, false, false};
    for partyIndex = 1, 3 do
        if settings.fontSizes[partyIndex] ~= data.cachedFontSizes[partyIndex] then
            sizesChanged[partyIndex] = true;
            data.cachedFontSizes[partyIndex] = settings.fontSizes[partyIndex];
        end
    end

    if fontFamilyChanged or fontFlagsChanged or outlineWidthChanged then
        sizesChanged = {true, true, true};
    end

    -- Recreate fonts for affected parties
    for partyIndex = 1, 3 do
        if sizesChanged[partyIndex] then
            local firstMemberIdx = (partyIndex - 1) * data.partyMaxSize;
            local lastMemberIdx = firstMemberIdx + data.partyMaxSize - 1;
            local fontSizes = data.getFontSizes(partyIndex);

            for i = firstMemberIdx, lastMemberIdx do
                if data.memberText[i] then
                    local name_font_settings = deep_copy_table(settings.name_font_settings);
                    local hp_font_settings = deep_copy_table(settings.hp_font_settings);
                    local mp_font_settings = deep_copy_table(settings.mp_font_settings);
                    local tp_font_settings = deep_copy_table(settings.tp_font_settings);
                    local distance_font_settings = deep_copy_table(settings.name_font_settings);
                    local zone_font_settings = deep_copy_table(settings.name_font_settings);
                    local job_font_settings = deep_copy_table(settings.name_font_settings);

                    name_font_settings.font_height = math.max(fontSizes.name, 6);
                    hp_font_settings.font_height = math.max(fontSizes.hp, 6);
                    mp_font_settings.font_height = math.max(fontSizes.mp, 6);
                    tp_font_settings.font_height = math.max(fontSizes.tp, 6);
                    distance_font_settings.font_height = math.max(fontSizes.distance, 6);
                    distance_font_settings.font_alignment = 2; -- Right-align so text doesn't shift as distance changes
                    zone_font_settings.font_height = math.max(fontSizes.zone, 6);
                    job_font_settings.font_height = math.max(fontSizes.job, 6);

                    data.memberText[i].name = FontManager.recreate(data.memberText[i].name, name_font_settings);
                    data.memberText[i].hp = FontManager.recreate(data.memberText[i].hp, hp_font_settings);
                    data.memberText[i].mp = FontManager.recreate(data.memberText[i].mp, mp_font_settings);
                    data.memberText[i].tp = FontManager.recreate(data.memberText[i].tp, tp_font_settings);
                    data.memberText[i].distance = FontManager.recreate(data.memberText[i].distance, distance_font_settings);
                    data.memberText[i].zone = FontManager.recreate(data.memberText[i].zone, zone_font_settings);
                    data.memberText[i].job = FontManager.recreate(data.memberText[i].job, job_font_settings);

                    -- Invalidate color cache for this member (forces color to be reapplied)
                    data.memberTextColorCache[i] = nil;
                end
            end

            -- Recalculate reference heights for this party
            data.calculateRefHeights(partyIndex);
        end
    end

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
    -- Destroy fonts
    for i = 0, data.memberTextCount - 1 do
        if data.memberText[i] then
            FontManager.destroy(data.memberText[i].name);
            FontManager.destroy(data.memberText[i].hp);
            FontManager.destroy(data.memberText[i].mp);
            FontManager.destroy(data.memberText[i].tp);
            FontManager.destroy(data.memberText[i].distance);
            FontManager.destroy(data.memberText[i].zone);
            FontManager.destroy(data.memberText[i].job);
        end
    end

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
