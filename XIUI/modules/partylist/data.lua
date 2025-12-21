--[[
    Party List Data Module
    Handles state, caches, configuration, and member information
]]

require('common');
local ffi = require('ffi');
local statusHandler = require('handlers.statushandler');
local windowBg = require('libs.windowbackground');

local data = {};

-- ============================================
-- Constants
-- ============================================
data.partyMaxSize = 6;
data.memberTextCount = data.partyMaxSize * 3;

-- UV coordinates for partylist titles atlas (4 titles stacked vertically)
data.titleUVs = {
    solo = {0, 0, 1, 0.25},
    party = {0, 0.25, 1, 0.5},
    partyB = {0, 0.5, 1, 0.75},
    partyC = {0, 0.75, 1, 1.0},
};

data.bgImageKeys = { 'bg', 'tl', 'tr', 'br', 'bl' };

-- ============================================
-- State Variables
-- ============================================
data.fullMenuWidth = {};
data.fullMenuHeight = {};
data.buffWindowX = {};
data.debuffWindowX = {};

data.partyWindowPrim = {
    [1] = { background = {} },
    [2] = { background = {} },
    [3] = { background = {} },
};

data.cursorTextures = T{};
data.currentCursorName = nil;
data.partyTargeted = false;
data.partySubTargeted = false;
data.memberText = {};
data.partyTitlesTexture = nil;

-- Reference text heights for baseline alignment
data.referenceTextHeights = {};

-- Cache last set colors to avoid expensive SetColor() calls every frame
data.memberTextColorCache = {};

-- Cache last set text to avoid expensive texture regeneration every frame
data.memberTextCache = {};

-- Cached max TP text width per party (for layout 1 "3000" calculation)
-- This never changes so we calculate once per party
data.maxTpTextWidthCache = {
    [1] = nil,
    [2] = nil,
    [3] = nil,
};

-- HP interpolation tracking for each party member (indexed by absolute member index 0-17)
data.memberInterpolation = {};

-- Cache converted border colors
data.cachedBorderColorU32 = nil;
data.cachedBorderColorARGB = nil;
data.cachedSubtargetBorderColorU32 = nil;
data.cachedSubtargetBorderColorARGB = nil;

-- Cache last used font sizes/family/flags
data.cachedFontSizes = {12, 12, 12};
data.cachedFontFamily = '';
data.cachedFontFlags = 0;
data.cachedOutlineWidth = 2;

-- Track loaded backgrounds per party
data.loadedBg = {};

-- Debounce settings save
data.lastSettingsSaveTime = 0;
data.pendingSettingsSave = false;
data.SETTINGS_SAVE_DEBOUNCE = 0.5;

-- Party cast tracking
data.partyCasts = {};

-- Reusable tables for buff/debuff separation (avoid allocations)
data.reusableBuffs = {};
data.reusableDebuffs = {};

-- ============================================
-- Frame-level Cache
-- ============================================
data.frameCache = {
    party = nil,
    player = nil,
    entity = nil,
    playerTarget = nil,
    t1 = nil,
    t2 = nil,
    subTargetActive = false,
    stPartyIndex = nil,
    activeMemberCount = {0, 0, 0},
    activeMemberList = {{}, {}, {}},
};

-- ============================================
-- Party Config Cache
-- ============================================
data.partyConfigCache = {
    [1] = { scale = nil, fontSizes = nil, barScales = nil, showTP = nil },
    [2] = { scale = nil, fontSizes = nil, barScales = nil, showTP = nil },
    [3] = { scale = nil, fontSizes = nil, barScales = nil, showTP = nil },
};
data.partyConfigCacheValid = false;
data.partyConfigCacheVersion = -1; -- Tracks which gConfigVersion we built from

-- Pre-calculated reference heights per party
data.partyRefHeights = {
    [1] = { hpRefHeight = 0, mpRefHeight = 0, tpRefHeight = 0, nameRefHeight = 0 },
    [2] = { hpRefHeight = 0, mpRefHeight = 0, tpRefHeight = 0, nameRefHeight = 0 },
    [3] = { hpRefHeight = 0, mpRefHeight = 0, tpRefHeight = 0, nameRefHeight = 0 },
};
data.partyRefHeightsValid = false;

-- ============================================
-- Config Helper Functions
-- ============================================

-- Helper to get party settings table (partyA, partyB, partyC)
function data.getPartySettings(partyIndex)
    if partyIndex == 3 then return gConfig.partyC;
    elseif partyIndex == 2 then return gConfig.partyB;
    else return gConfig.partyA;
    end
end

-- Helper to get layout template for a party
function data.getLayoutTemplate(partyIndex)
    local party = data.getPartySettings(partyIndex);
    if party.layout == 1 then
        return gConfig.layoutCompact;
    else
        return gConfig.layoutHorizontal;
    end
end

-- Update party config cache
function data.updatePartyConfigCache()
    if data.partyConfigCacheValid then return; end

    for partyIndex = 1, 3 do
        local cache = data.partyConfigCache[partyIndex];
        local party = data.getPartySettings(partyIndex);
        local layout = party.layout or 0;

        -- Scale
        if cache.scale == nil then cache.scale = {}; end
        cache.scale.x = party.scaleX or 1;
        cache.scale.y = party.scaleY or 1;
        cache.scale.icon = party.jobIconScale or 1;

        -- ShowTP
        cache.showTP = party.showTP;

        -- Layout mode
        cache.layout = layout;

        -- Party-specific settings
        cache.showDistance = party.showDistance;
        cache.distanceHighlight = party.distanceHighlight or 0;
        cache.showJobIcon = party.showJobIcon;
        cache.showJob = party.showJob;
        cache.showMainJob = party.showMainJob ~= false;
        cache.showMainJobLevel = party.showMainJobLevel ~= false;
        cache.showSubJob = party.showSubJob ~= false;
        cache.showSubJobLevel = party.showSubJobLevel ~= false;
        cache.showCastBars = party.showCastBars;
        cache.castBarScaleX = party.castBarScaleX or 1.0;
        cache.castBarScaleY = party.castBarScaleY or 0.6;
        cache.castBarOffsetX = party.castBarOffsetX or 0;
        cache.castBarOffsetY = party.castBarOffsetY or 0;
        cache.castBarStyle = party.castBarStyle or 'name';
        cache.showBookends = party.showBookends;
        cache.showTitle = party.showTitle;
        cache.flashTP = party.flashTP;
        cache.backgroundName = party.backgroundName;
        cache.bgScale = party.bgScale or 1;
        cache.borderScale = party.borderScale or 1;
        cache.backgroundOpacity = party.backgroundOpacity or 1;
        cache.borderOpacity = party.borderOpacity or 1;
        cache.cursor = party.cursor;
        cache.subtargetArrowTint = party.subtargetArrowTint or 0xFFfdd017;
        cache.targetArrowTint = party.targetArrowTint or 0xFFFFFFFF;
        cache.statusTheme = party.statusTheme or 0;
        cache.statusSide = party.statusSide or 0;
        cache.buffScale = party.buffScale or 1;
        cache.statusOffsetX = party.statusOffsetX or 0;
        cache.statusOffsetY = party.statusOffsetY or 0;
        cache.expandHeight = party.expandHeight;
        cache.alignBottom = party.alignBottom;
        cache.minRows = party.minRows or 1;
        cache.entrySpacing = party.entrySpacing or 0;
        cache.selectionBoxScaleY = party.selectionBoxScaleY or 1;
        cache.selectionBoxOffsetY = party.selectionBoxOffsetY or 0;

        -- HP/MP display modes
        cache.hpDisplayMode = party.hpDisplayMode or 'number';
        cache.mpDisplayMode = party.mpDisplayMode or 'number';
        cache.alwaysShowMpBar = party.alwaysShowMpBar ~= false; -- Default true

        -- FontSizes
        if cache.fontSizes == nil then cache.fontSizes = {}; end
        if party.splitFontSizes then
            cache.fontSizes.name = party.nameFontSize or party.fontSize or 12;
            cache.fontSizes.hp = party.hpFontSize or party.fontSize or 12;
            cache.fontSizes.mp = party.mpFontSize or party.fontSize or 12;
            cache.fontSizes.tp = party.tpFontSize or party.fontSize or 12;
            cache.fontSizes.distance = party.distanceFontSize or party.fontSize or 12;
            cache.fontSizes.job = party.jobFontSize or party.fontSize or 12;
            cache.fontSizes.zone = party.zoneFontSize or 10;
        else
            local fontSize = party.fontSize or 12;
            cache.fontSizes.name = fontSize;
            cache.fontSizes.hp = fontSize;
            cache.fontSizes.mp = fontSize;
            cache.fontSizes.tp = fontSize;
            cache.fontSizes.distance = fontSize;
            cache.fontSizes.job = fontSize;
            cache.fontSizes.zone = fontSize;
        end

        -- BarScales
        if cache.barScales == nil then cache.barScales = {}; end
        cache.barScales.hpBarScaleX = party.hpBarScaleX or 1;
        cache.barScales.mpBarScaleX = party.mpBarScaleX or 1;
        cache.barScales.tpBarScaleX = party.tpBarScaleX or 1;
        cache.barScales.hpBarScaleY = party.hpBarScaleY or 1;
        cache.barScales.mpBarScaleY = party.mpBarScaleY or 1;
        cache.barScales.tpBarScaleY = party.tpBarScaleY or 1;

        -- Text position offsets (per-party)
        if cache.textOffsets == nil then cache.textOffsets = {}; end
        cache.textOffsets.nameX = party.nameTextOffsetX or 0;
        cache.textOffsets.nameY = party.nameTextOffsetY or 0;
        cache.textOffsets.hpX = party.hpTextOffsetX or 0;
        cache.textOffsets.hpY = party.hpTextOffsetY or 0;
        cache.textOffsets.mpX = party.mpTextOffsetX or 0;
        cache.textOffsets.mpY = party.mpTextOffsetY or 0;
        cache.textOffsets.tpX = party.tpTextOffsetX or 0;
        cache.textOffsets.tpY = party.tpTextOffsetY or 0;
        cache.textOffsets.distanceX = party.distanceTextOffsetX or 0;
        cache.textOffsets.distanceY = party.distanceTextOffsetY or 0;
        cache.textOffsets.jobX = party.jobTextOffsetX or 0;
        cache.textOffsets.jobY = party.jobTextOffsetY or 0;

        -- Color settings reference
        if partyIndex == 1 then
            cache.colors = gConfig.colorCustomization.partyListA;
        elseif partyIndex == 2 then
            cache.colors = gConfig.colorCustomization.partyListB;
        else
            cache.colors = gConfig.colorCustomization.partyListC;
        end
    end

    data.partyConfigCacheValid = true;
    data.partyConfigCacheVersion = gConfigVersion or 0;
end

-- Check if config cache needs updating (compares version instead of rebuilding every frame)
function data.checkAndUpdateConfigCache()
    local currentVersion = gConfigVersion or 0;
    if data.partyConfigCacheVersion ~= currentVersion or not data.partyConfigCacheValid then
        data.partyConfigCacheValid = false;
        data.updatePartyConfigCache();
    end
end

-- Cached getters
function data.getScale(partyIndex)
    return data.partyConfigCache[partyIndex].scale;
end

function data.showPartyTP(partyIndex)
    return data.partyConfigCache[partyIndex].showTP;
end

function data.getFontSizes(partyIndex)
    return data.partyConfigCache[partyIndex].fontSizes;
end

function data.getBarScales(partyIndex)
    return data.partyConfigCache[partyIndex].barScales;
end

function data.getTextOffsets(partyIndex)
    return data.partyConfigCache[partyIndex].textOffsets;
end

function data.getBarBackgroundOverride(partyIndex)
    local colors = data.partyConfigCache[partyIndex] and data.partyConfigCache[partyIndex].colors;
    if colors then
        local override = colors.barBackgroundOverride;
        if override and override.active then
            local endColor = override.enabled and override.stop or override.start;
            return {override.start, endColor};
        end
    end
    return nil;
end

function data.getBarBorderOverride(partyIndex)
    local colors = data.partyConfigCache[partyIndex] and data.partyConfigCache[partyIndex].colors;
    if colors then
        local override = colors.barBorderOverride;
        if override and override.active then
            return override.color;
        end
    end
    return nil;
end

-- ============================================
-- Member Information
-- ============================================

function data.GetMemberInformation(memIdx)
    if (showConfig[1] and gConfig.partyListPreview) then
        local memInfo = {};
        memInfo.hpp = memIdx == 4 and 0.1 or memIdx == 2 and 0.5 or memIdx == 0 and 0.75 or 1;
        memInfo.maxhp = 1250;
        memInfo.hp = math.floor(memInfo.maxhp * memInfo.hpp);
        memInfo.tp = 1500;

        -- Preview jobs: mix of MP jobs (WHM, BLM, RDM, BRD) and no-MP jobs (WAR, NIN)
        -- Job IDs: 1=WAR, 3=WHM, 4=BLM, 5=RDM, 10=BRD, 13=NIN
        local previewJobs = {
            [0] = 3,   -- WHM (has MP)
            [1] = 13,  -- NIN (no MP - will show cast bar when casting)
            [2] = 4,   -- BLM (has MP)
            [3] = 1,   -- WAR (no MP)
            [4] = 5,   -- RDM (has MP)
            [5] = 10,  -- BRD (has MP)
        };
        local previewSubJobs = {
            [0] = 5,   -- /RDM
            [1] = 1,   -- /WAR
            [2] = 5,   -- /RDM
            [3] = 13,  -- /NIN
            [4] = 3,   -- /WHM
            [5] = 3,   -- /WHM
        };
        memInfo.job = previewJobs[memIdx % 6];
        memInfo.level = 99;
        memInfo.subjob = previewSubJobs[memIdx % 6];
        memInfo.subjoblevel = 49;

        -- Set MP based on whether job has MP
        if JobHasMP(memInfo.job, memInfo.subjob) then
            memInfo.mpp = memIdx == 1 and 0.1 or 0.75;
            memInfo.maxmp = 1000;
            memInfo.mp = math.floor(memInfo.maxmp * memInfo.mpp);
        else
            -- Jobs without MP show 0
            memInfo.mpp = 0;
            memInfo.maxmp = 0;
            memInfo.mp = 0;
        end
        memInfo.targeted = memIdx == 4 or memIdx == 10 or memIdx == 16;
        memInfo.serverid = -memIdx - 1;
        -- Preview buffs/debuffs - different combinations per member
        -- Common buff IDs: 1=KO, 2=Sleep, 3=Poison, 4=Paralysis, 5=Blindness, 6=Silence, 7=Petrification
        -- 10=Stun, 11=Bind, 12=Weight, 13=Slow, 33=Haste, 40=Blink, 43=Stoneskin, 94=Reraise
        -- 116=Phalanx, 180=Multi Strikes, 187=Enmity Boost, 604=Ionis
        local previewBuffs = {
            [0] = {33, 43, 116, 40, 94},           -- Haste, Stoneskin, Phalanx, Blink, Reraise
            [1] = {3, 13, 33, 43},                  -- Poison, Slow, Haste, Stoneskin
            [2] = {2, 5, 6},                        -- Sleep, Blindness, Silence
            [3] = {33, 94, 604, 180},               -- Haste, Reraise, Ionis, Multi Strikes
            [4] = {4, 11, 12},                      -- Paralysis, Bind, Weight
            [5] = {33, 40, 43, 116, 94, 187},       -- Lots of buffs
        };
        memInfo.buffs = previewBuffs[memIdx % 6];
        memInfo.sync = false;
        memInfo.subTargeted = memIdx == 2 or memIdx == 8 or memIdx == 14;
        memInfo.zone = 100;
        memInfo.inzone = memIdx % 4 ~= 0;
        memInfo.name = (memIdx % 6 == 1) and 'Thisisaverylongname' or ('Player ' .. (memIdx + 1));
        memInfo.leader = memIdx == 0 or memIdx == 6 or memIdx == 12;
        memInfo.previewDistance = memIdx == 0 and 0 or memIdx == 1 and 5.2 or memIdx == 2 and 12.8 or memIdx == 3 and 21.5 or memIdx == 4 and 35.0 or 18.3;

        -- Preview cast bars
        -- memIdx 1: NIN casting Utsusemi (no-MP job with cast bar)
        -- memIdx 2: BLM casting (MP job with cast bar)
        if memIdx == 1 then
            -- NIN casting Utsusemi - demonstrates cast bar for no-MP job
            local castDuration = 4.0;
            local loopTime = os.clock() % castDuration;
            data.partyCasts[memInfo.serverid] = T{
                spellName = 'Utsusemi: Ni',
                spellId = 339,
                spellType = 36,  -- Ninjutsu
                castTime = castDuration,
                startTime = os.clock() - loopTime,
                timestamp = os.time(),
                job = 13,
                subjob = 1,
                jobLevel = 75,
                subjobLevel = 37
            };
        elseif memIdx == 2 or memIdx == 7 or memIdx == 13 then
            -- WHM/BLM casting - demonstrates cast bar for MP job
            local castDuration = 5.0;
            local loopTime = os.clock() % castDuration;
            data.partyCasts[memInfo.serverid] = T{
                spellName = 'Cure IV',
                spellId = 3,
                spellType = 33,
                castTime = castDuration,
                startTime = os.clock() - loopTime,
                timestamp = os.time(),
                job = 3,
                subjob = 5,
                jobLevel = 75,
                subjobLevel = 37
            };
        end

        return memInfo
    end

    local party = data.frameCache.party;
    local player = data.frameCache.player;
    if (player == nil or party == nil or party:GetMemberIsActive(memIdx) == 0) then
        return nil;
    end

    local partyIndex = math.ceil((memIdx + 1) / data.partyMaxSize);
    local partyLeaderId = nil
    if (partyIndex == 3) then
        partyLeaderId = party:GetAlliancePartyLeaderServerId3();
    elseif (partyIndex == 2) then
        partyLeaderId = party:GetAlliancePartyLeaderServerId2();
    else
        partyLeaderId = party:GetAlliancePartyLeaderServerId1();
    end

    local memberInfo = {};
    memberInfo.zone = party:GetMemberZone(memIdx);
    memberInfo.inzone = memberInfo.zone == party:GetMemberZone(0);
    memberInfo.name = party:GetMemberName(memIdx);

    local memberServerId = party:GetMemberServerId(memIdx);
    local partyMemberCount = data.frameCache.activeMemberCount[partyIndex] or 0;
    if (partyLeaderId ~= nil and partyLeaderId ~= 0) then
        -- Party leader ID is set - we're in a party (even if alone), use it to determine leader
        memberInfo.leader = partyLeaderId == memberServerId;
    elseif (partyMemberCount > 1) then
        -- No leader ID but multiple members - fallback to first member as leader
        local firstMemberOfParty = (partyIndex - 1) * data.partyMaxSize;
        memberInfo.leader = memIdx == firstMemberOfParty;
    else
        -- Truly solo (no party leader ID and alone) - no leader indicator
        memberInfo.leader = false;
    end

    if (memberInfo.inzone == true) then
        memberInfo.hp = party:GetMemberHP(memIdx);
        memberInfo.hpp = party:GetMemberHPPercent(memIdx) / 100;
        memberInfo.mp = party:GetMemberMP(memIdx);
        memberInfo.mpp = party:GetMemberMPPercent(memIdx) / 100;

        -- For the player (memIdx == 0), use actual max values from player object
        -- For other party members, calculate from percentage (may be slightly inaccurate)
        if memIdx == 0 then
            memberInfo.maxhp = player:GetHPMax();
            memberInfo.maxmp = player:GetMPMax();
        else
            -- Calculate max from current and percentage, with safeguards
            if memberInfo.hpp > 0 then
                memberInfo.maxhp = math.floor(memberInfo.hp / memberInfo.hpp + 0.5);
            else
                memberInfo.maxhp = 0;
            end
            if memberInfo.mpp > 0 then
                memberInfo.maxmp = math.floor(memberInfo.mp / memberInfo.mpp + 0.5);
            else
                memberInfo.maxmp = 0;
            end
        end
        memberInfo.tp = party:GetMemberTP(memIdx);
        memberInfo.job = party:GetMemberMainJob(memIdx);
        memberInfo.level = party:GetMemberMainJobLevel(memIdx);
        memberInfo.subjob = party:GetMemberSubJob(memIdx);
        memberInfo.subjoblevel = party:GetMemberSubJobLevel(memIdx);
        memberInfo.serverid = party:GetMemberServerId(memIdx);
        memberInfo.index = party:GetMemberTargetIndex(memIdx);

        if (data.frameCache.playerTarget ~= nil) then
            local thisIdx = memberInfo.index;
            local t1 = data.frameCache.t1;
            local t2 = data.frameCache.t2;
            local sActive = data.frameCache.subTargetActive;
            local stPartyIdx = data.frameCache.stPartyIndex;
            memberInfo.targeted = (t1 == thisIdx and not sActive) or (t2 == thisIdx and sActive);
            memberInfo.subTargeted = (t1 == thisIdx and sActive) or (stPartyIdx ~= nil and stPartyIdx == memIdx);
        else
            memberInfo.targeted = false;
            memberInfo.subTargeted = false;
        end

        if (memIdx == 0) then
            memberInfo.buffs = player:GetBuffs();
        else
            memberInfo.buffs = statusHandler.get_member_status(memberInfo.serverid);
        end
        memberInfo.sync = bit.band(party:GetMemberFlagMask(memIdx), 0x100) == 0x100;
    else
        memberInfo.hp = 0;
        memberInfo.hpp = 0;
        memberInfo.maxhp = 0;
        memberInfo.mp = 0;
        memberInfo.mpp = 0;
        memberInfo.maxmp = 0;
        memberInfo.tp = 0;
        memberInfo.job = '';
        memberInfo.level = '';
        memberInfo.subjob = '';
        memberInfo.subjoblevel = '';
        memberInfo.targeted = false;
        memberInfo.serverid = 0;
        memberInfo.buffs = nil;
        memberInfo.sync = false;
        memberInfo.subTargeted = false;
        memberInfo.index = nil;
    end

    return memberInfo;
end

-- ============================================
-- Text Visibility Helpers
-- ============================================

function data.UpdateTextVisibilityByMember(memIdx, visible)
    local mt = data.memberText[memIdx];
    if mt then
        mt.hp:set_visible(visible);
        mt.mp:set_visible(visible);
        mt.tp:set_visible(visible);
        mt.name:set_visible(visible);
        mt.distance:set_visible(visible);
        mt.zone:set_visible(visible);
        mt.job:set_visible(visible);
    end
end

function data.UpdateTextVisibility(visible, partyIndex)
    if partyIndex == nil then
        for i = 0, data.memberTextCount - 1 do
            data.UpdateTextVisibilityByMember(i, visible);
        end
    else
        local firstPlayerIndex = (partyIndex - 1) * data.partyMaxSize;
        local lastPlayerIndex = firstPlayerIndex + data.partyMaxSize - 1;
        for i = firstPlayerIndex, lastPlayerIndex do
            data.UpdateTextVisibilityByMember(i, visible);
        end
    end

    -- Handle background visibility using windowbackground library
    -- When visible=false, hide backgrounds; when visible=true, backgrounds
    -- will be shown on next windowBg.update() call in DrawPartyWindow
    if not visible then
        for i = 1, 3 do
            if (partyIndex == nil or i == partyIndex) then
                local backgroundPrim = data.partyWindowPrim[i].background;
                if backgroundPrim then
                    windowBg.hide(backgroundPrim);
                end
            end
        end
    end
end

-- ============================================
-- Reference Height Calculation
-- ============================================

function data.calculateRefHeights(partyIndex)
    local firstMemberIdx = (partyIndex - 1) * data.partyMaxSize;
    if data.memberText[firstMemberIdx] == nil then return; end

    local refHeights = data.partyRefHeights[partyIndex];

    -- Include all characters used in display modes: numbers, percent, parentheses, slash, space
    local numericRefString = "0123456789%() /";
    data.memberText[firstMemberIdx].hp:set_text(numericRefString);
    local _, hpRefH = data.memberText[firstMemberIdx].hp:get_text_size();
    refHeights.hpRefHeight = hpRefH;
    data.memberText[firstMemberIdx].hp:set_text('');

    data.memberText[firstMemberIdx].mp:set_text(numericRefString);
    local _, mpRefH = data.memberText[firstMemberIdx].mp:get_text_size();
    refHeights.mpRefHeight = mpRefH;
    data.memberText[firstMemberIdx].mp:set_text('');

    data.memberText[firstMemberIdx].tp:set_text(numericRefString);
    local _, tpRefH = data.memberText[firstMemberIdx].tp:get_text_size();
    refHeights.tpRefHeight = tpRefH;
    data.memberText[firstMemberIdx].tp:set_text('');

    local textRefString = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
    data.memberText[firstMemberIdx].name:set_text(textRefString);
    local _, nameRefH = data.memberText[firstMemberIdx].name:get_text_size();
    refHeights.nameRefHeight = nameRefH;
    data.memberText[firstMemberIdx].name:set_text('');
end

-- ============================================
-- State Reset
-- ============================================

function data.Reset()
    data.memberText = {};
    data.partyWindowPrim = {
        {background = {}},
        {background = {}},
        {background = {}}
    };
    data.memberTextColorCache = {};
    data.memberTextCache = {};
    data.maxTpTextWidthCache = { [1] = nil, [2] = nil, [3] = nil };
    data.memberInterpolation = {};
    data.partyCasts = {};
    data.loadedBg = {};
    data.partyConfigCacheValid = false;
    data.partyConfigCacheVersion = -1;
    data.partyRefHeightsValid = false;
end

return data;
