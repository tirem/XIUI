require('common');
local ffi = require('ffi');
local d3d8 = require('d3d8');
local imgui = require('imgui');
local gdi = require('gdifonts.include');
local primitives = require('primitives');
local statusHandler = require('statushandler');
local buffTable = require('bufftable');
local progressbar = require('progressbar');
local encoding = require('gdifonts.encoding');
local ashita_settings = require('settings');

local fullMenuWidth = {};
local fullMenuHeight = {};
local buffWindowX = {};
local debuffWindowX = {};

-- local backgroundPrim = {};
local partyWindowPrim = {};
partyWindowPrim[1] = {
    background = {},
}
partyWindowPrim[2] = {
    background = {},
}
partyWindowPrim[3] = {
    background = {},
}

local cursorTextures = T{}; -- Cache for cursor textures (like jobIcons)
local currentCursorName = nil; -- Track which cursor is loaded
local partyTargeted;
local partySubTargeted;
local memberText = {};
local partyTitlesTexture = nil; -- Texture atlas for party titles (Solo, Party, Party B, Party C)
local partyMaxSize = 6;
local memberTextCount = partyMaxSize * 3;

-- Reference text heights for baseline alignment (prevents text jumping)
-- Stored per font size since different text types may have different sizes
local referenceTextHeights = {};

-- UV coordinates for partylist titles atlas (4 titles stacked vertically)
local titleUVs = {
    solo = {0, 0, 1, 0.25},      -- Solo (top 25% of texture)
    party = {0, 0.25, 1, 0.5},    -- Party (second 25%)
    partyB = {0, 0.5, 1, 0.75},   -- Party B (third 25%)
    partyC = {0, 0.75, 1, 1.0},   -- Party C (bottom 25%)
}


-- Cache last set colors to avoid expensive SetColor() calls every frame
local memberTextColorCache = {};

-- HP interpolation tracking for each party member (indexed by absolute member index 0-17)
local memberInterpolation = {};

-- Cache converted border color to avoid redundant U32 conversion every frame
local cachedBorderColorU32 = nil;
local cachedBorderColorARGB = nil;

-- Cache last used font sizes to avoid unnecessary font recreation
local cachedFontSizes = {12, 12, 12};

-- Cache last used font family, flags, and outline width to detect changes
local cachedFontFamily = '';
local cachedFontFlags = 0;
local cachedOutlineWidth = 2;

local borderConfig = {1, '#243e58'};

local bgImageKeys = { 'bg', 'tl', 'tr', 'br', 'bl' };
local loadedBg = nil;

-- ============================================
-- PERFORMANCE: Frame-level caches
-- These are populated once per frame in DrawWindow and reused by all members
-- ============================================

-- Cached game state (set once per frame in DrawWindow)
local frameCache = {
    party = nil,           -- GetPartySafe() result
    player = nil,          -- GetPlayerSafe() result
    entity = nil,          -- GetEntitySafe() result
    playerTarget = nil,    -- GetTargetSafe() result
    -- Target info (same for all members)
    t1 = nil,              -- Primary target index
    t2 = nil,              -- Secondary target index
    subTargetActive = false,
    stPartyIndex = nil,    -- STPC party member index
    -- Active member tracking per party
    activeMemberCount = {0, 0, 0},
    activeMemberList = {{}, {}, {}},  -- Which members are active per party
};

-- Cached per-party configuration (updated when config changes)
local partyConfigCache = {
    [1] = { scale = nil, fontSizes = nil, barScales = nil, showTP = nil },
    [2] = { scale = nil, fontSizes = nil, barScales = nil, showTP = nil },
    [3] = { scale = nil, fontSizes = nil, barScales = nil, showTP = nil },
};
local partyConfigCacheValid = false;

-- Pre-calculated reference heights per party (computed in UpdateVisuals)
-- Keys: hpRefHeight, mpRefHeight, tpRefHeight, nameRefHeight
local partyRefHeights = {
    [1] = { hpRefHeight = 0, mpRefHeight = 0, tpRefHeight = 0, nameRefHeight = 0 },
    [2] = { hpRefHeight = 0, mpRefHeight = 0, tpRefHeight = 0, nameRefHeight = 0 },
    [3] = { hpRefHeight = 0, mpRefHeight = 0, tpRefHeight = 0, nameRefHeight = 0 },
};
local partyRefHeightsValid = false;

-- Reusable tables for buff/debuff separation (avoid allocations)
local reusableBuffs = {};
local reusableDebuffs = {};

-- Debounce settings save
local lastSettingsSaveTime = 0;
local pendingSettingsSave = false;
local SETTINGS_SAVE_DEBOUNCE = 0.5;  -- 500ms debounce

local partyList = {
	partyCasts = {} -- Track party member casting: [serverId] = {spellName, castTime, startTime, timestamp}
};


-- PERFORMANCE: Update party config cache (called once per frame or when config changes)
local function updatePartyConfigCache()
    if partyConfigCacheValid then return; end

    local currentLayout = (gConfig.partyListLayout == 1) and gConfig.partyListLayout2 or gConfig.partyListLayout1;
    local layout = gConfig.partyListLayout or 0;

    -- Update cache for each party
    for partyIndex = 1, 3 do
        local cache = partyConfigCache[partyIndex];

        -- Scale
        if cache.scale == nil then cache.scale = {}; end
        if partyIndex == 3 then
            cache.scale.x = currentLayout.partyList3ScaleX;
            cache.scale.y = currentLayout.partyList3ScaleY;
            cache.scale.icon = currentLayout.partyList3JobIconScale;
        elseif partyIndex == 2 then
            cache.scale.x = currentLayout.partyList2ScaleX;
            cache.scale.y = currentLayout.partyList2ScaleY;
            cache.scale.icon = currentLayout.partyList2JobIconScale;
        else
            cache.scale.x = currentLayout.partyListScaleX;
            cache.scale.y = currentLayout.partyListScaleY;
            cache.scale.icon = currentLayout.partyListJobIconScale;
        end

        -- ShowTP
        if partyIndex == 3 then
            cache.showTP = currentLayout.partyList3TP;
        elseif partyIndex == 2 then
            cache.showTP = currentLayout.partyList2TP;
        else
            cache.showTP = currentLayout.partyListTP;
        end

        -- FontSizes
        if cache.fontSizes == nil then cache.fontSizes = {}; end
        if layout == 1 then
            if partyIndex == 3 then
                cache.fontSizes.name = currentLayout.partyList3NameFontSize or currentLayout.partyList3FontSize;
                cache.fontSizes.hp = currentLayout.partyList3HpFontSize or currentLayout.partyList3FontSize;
                cache.fontSizes.mp = currentLayout.partyList3MpFontSize or currentLayout.partyList3FontSize;
                cache.fontSizes.tp = currentLayout.partyListTpFontSize or currentLayout.partyListFontSize;
            elseif partyIndex == 2 then
                cache.fontSizes.name = currentLayout.partyList2NameFontSize or currentLayout.partyList2FontSize;
                cache.fontSizes.hp = currentLayout.partyList2HpFontSize or currentLayout.partyList2FontSize;
                cache.fontSizes.mp = currentLayout.partyList2MpFontSize or currentLayout.partyList2FontSize;
                cache.fontSizes.tp = currentLayout.partyListTpFontSize or currentLayout.partyListFontSize;
            else
                cache.fontSizes.name = currentLayout.partyListNameFontSize or currentLayout.partyListFontSize;
                cache.fontSizes.hp = currentLayout.partyListHpFontSize or currentLayout.partyListFontSize;
                cache.fontSizes.mp = currentLayout.partyListMpFontSize or currentLayout.partyListFontSize;
                cache.fontSizes.tp = currentLayout.partyListTpFontSize or currentLayout.partyListFontSize;
            end
        else
            local fontSizeKey = (partyIndex == 3) and 'partyList3FontSize'
                                or (partyIndex == 2) and 'partyList2FontSize'
                                or 'partyListFontSize';
            local fontSize = currentLayout[fontSizeKey];
            cache.fontSizes.name = fontSize;
            cache.fontSizes.hp = fontSize;
            cache.fontSizes.mp = fontSize;
            cache.fontSizes.tp = fontSize;
        end

        -- BarScales
        if layout == 1 then
            if cache.barScales == nil then cache.barScales = {}; end
            if partyIndex == 3 then
                cache.barScales.hpBarScaleX = currentLayout.partyList3HpBarScaleX or currentLayout.hpBarScaleX;
                cache.barScales.mpBarScaleX = currentLayout.partyList3MpBarScaleX or currentLayout.mpBarScaleX;
                cache.barScales.hpBarScaleY = currentLayout.partyList3HpBarScaleY or currentLayout.hpBarScaleY;
                cache.barScales.mpBarScaleY = currentLayout.partyList3MpBarScaleY or currentLayout.mpBarScaleY;
            elseif partyIndex == 2 then
                cache.barScales.hpBarScaleX = currentLayout.partyList2HpBarScaleX or currentLayout.hpBarScaleX;
                cache.barScales.mpBarScaleX = currentLayout.partyList2MpBarScaleX or currentLayout.mpBarScaleX;
                cache.barScales.hpBarScaleY = currentLayout.partyList2HpBarScaleY or currentLayout.hpBarScaleY;
                cache.barScales.mpBarScaleY = currentLayout.partyList2MpBarScaleY or currentLayout.mpBarScaleY;
            else
                cache.barScales.hpBarScaleX = currentLayout.hpBarScaleX;
                cache.barScales.mpBarScaleX = currentLayout.mpBarScaleX;
                cache.barScales.hpBarScaleY = currentLayout.hpBarScaleY;
                cache.barScales.mpBarScaleY = currentLayout.mpBarScaleY;
            end
        else
            cache.barScales = nil;
        end
    end

    partyConfigCacheValid = true;
end

-- PERFORMANCE: Cached getters that return pre-calculated values
local function getScale(partyIndex)
    return partyConfigCache[partyIndex].scale;
end

local function showPartyTP(partyIndex)
    return partyConfigCache[partyIndex].showTP;
end

local function getFontSizes(partyIndex)
    return partyConfigCache[partyIndex].fontSizes;
end

local function getBarScales(partyIndex)
    return partyConfigCache[partyIndex].barScales;
end

local function getBarBackgroundOverride()
    -- Check if party list has a bar background override enabled
    if gConfig and gConfig.colorCustomization and gConfig.colorCustomization.partyList then
        local override = gConfig.colorCustomization.partyList.barBackgroundOverride;
        if override and override.active then
            -- If gradient enabled, use start to stop; otherwise use start for both (static color)
            local endColor = override.enabled and override.stop or override.start;
            return {override.start, endColor};
        end
    end
    return nil;
end

local function getBarBorderOverride()
    -- Check if party list has a bar border override enabled
    if gConfig and gConfig.colorCustomization and gConfig.colorCustomization.partyList then
        local override = gConfig.colorCustomization.partyList.barBorderOverride;
        if override and override.active then
            return override.color;
        end
    end
    return nil;
end

local function UpdateTextVisibilityByMember(memIdx, visible)

    memberText[memIdx].hp:set_visible(visible);
    memberText[memIdx].mp:set_visible(visible);
    memberText[memIdx].tp:set_visible(visible);
    memberText[memIdx].name:set_visible(visible);
    memberText[memIdx].distance:set_visible(visible);
    memberText[memIdx].zone:set_visible(visible);
    memberText[memIdx].job:set_visible(visible);
end

local function UpdateTextVisibility(visible, partyIndex)
    if partyIndex == nil then
        for i = 0, memberTextCount - 1 do
            UpdateTextVisibilityByMember(i, visible);
        end
    else
        local firstPlayerIndex = (partyIndex - 1) * partyMaxSize;
        local lastPlayerIndex = firstPlayerIndex + partyMaxSize - 1;
        for i = firstPlayerIndex, lastPlayerIndex do
            UpdateTextVisibilityByMember(i, visible);
        end
    end

    for i = 1, 3 do
        if (partyIndex == nil or i == partyIndex) then
            -- Title is now rendered via ImGui image, no visibility management needed
            local backgroundPrim = partyWindowPrim[i].background;
            for _, k in ipairs(bgImageKeys) do
                backgroundPrim[k].visible = visible and backgroundPrim[k].exists;
            end
        end
    end
end

local function GetMemberInformation(memIdx)

    if (showConfig[1] and gConfig.partyListPreview) then
        local memInfo = {};
        memInfo.hpp = memIdx == 4 and 0.1 or memIdx == 2 and 0.5 or memIdx == 0 and 0.75 or 1;
        memInfo.maxhp = 1250;
        memInfo.hp = math.floor(memInfo.maxhp * memInfo.hpp);
        memInfo.mpp = memIdx == 1 and 0.1 or 0.75;
        memInfo.maxmp = 1000;
        memInfo.mp = math.floor(memInfo.maxmp * memInfo.mpp);
        memInfo.tp = 1500;
        memInfo.job = memIdx + 1;
        memInfo.level = 99;
        memInfo.subjob = ((memIdx + 3) % 22) + 1;  -- Vary subjobs for preview
        memInfo.subjoblevel = 49;
        memInfo.targeted = memIdx == 4;
        memInfo.serverid = -memIdx - 1;  -- Unique negative IDs for preview members
        memInfo.buffs = nil;
        memInfo.sync = false;
        memInfo.subTargeted = false;
        memInfo.zone = 100;
        memInfo.inzone = memIdx % 4 ~= 0;
        memInfo.name = 'Player ' .. (memIdx + 1);
        memInfo.leader = memIdx == 0 or memIdx == 6 or memIdx == 12;
        -- Varying preview distances for demonstration
        memInfo.previewDistance = memIdx == 0 and 0 or memIdx == 1 and 5.2 or memIdx == 2 and 12.8 or memIdx == 3 and 21.5 or memIdx == 4 and 35.0 or 18.3;

        -- Add a preview cast bar for Player 2 (memIdx 1) with looping animation
        if (memIdx == 1) then
            local castDuration = 5.0;  -- 5 second cast time for preview
            local loopTime = os.clock() % castDuration;  -- Loop every 5 seconds
            partyList.partyCasts[-2] = T{
                spellName = 'Cure IV',
                castTime = castDuration,
                startTime = os.clock() - loopTime,  -- Simulate progress through the cast
                timestamp = os.time()
            };
        end

        return memInfo
    end

    -- PERFORMANCE: Use cached party/player from frame cache
    local party = frameCache.party;
    local player = frameCache.player;
    if (player == nil or party == nil or party:GetMemberIsActive(memIdx) == 0) then
        return nil;
    end

    local partyIndex = math.ceil((memIdx + 1) / partyMaxSize);
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
    memberInfo.leader = partyLeaderId == party:GetMemberServerId(memIdx);

    if (memberInfo.inzone == true) then
        memberInfo.hp = party:GetMemberHP(memIdx);
        memberInfo.hpp = party:GetMemberHPPercent(memIdx) / 100;
        memberInfo.maxhp = memberInfo.hp / memberInfo.hpp;
        memberInfo.mp = party:GetMemberMP(memIdx);
        memberInfo.mpp = party:GetMemberMPPercent(memIdx) / 100;
        memberInfo.maxmp = memberInfo.mp / memberInfo.mpp;
        memberInfo.tp = party:GetMemberTP(memIdx);
        memberInfo.job = party:GetMemberMainJob(memIdx);
        memberInfo.level = party:GetMemberMainJobLevel(memIdx);
        memberInfo.subjob = party:GetMemberSubJob(memIdx);
        memberInfo.subjoblevel = party:GetMemberSubJobLevel(memIdx);
        memberInfo.serverid = party:GetMemberServerId(memIdx);
        memberInfo.index = party:GetMemberTargetIndex(memIdx);
        -- PERFORMANCE: Use cached target info from frame cache
        if (frameCache.playerTarget ~= nil) then
            local thisIdx = memberInfo.index;
            local t1 = frameCache.t1;
            local t2 = frameCache.t2;
            local sActive = frameCache.subTargetActive;
            local stPartyIdx = frameCache.stPartyIndex;
            memberInfo.targeted = (t1 == thisIdx and not sActive) or (t2 == thisIdx and sActive);
            -- Check both target index matching AND direct STPC party index matching
            -- The latter handles the case when a party member is already selected
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

local function DrawMember(memIdx, settings, isLastVisibleMember)

    local memInfo = GetMemberInformation(memIdx);
    if (memInfo == nil) then
        -- dummy data to render an empty space
        memInfo = {};
        memInfo.hp = 0;
        memInfo.hpp = 0;
        memInfo.maxhp = 0;
        memInfo.mp = 0;
        memInfo.mpp = 0;
        memInfo.maxmp = 0;
        memInfo.tp = 0;
        memInfo.job = '';
        memInfo.level = '';
        memInfo.subjob = '';
        memInfo.subjoblevel = '';
        memInfo.targeted = false;
        memInfo.serverid = 0;
        memInfo.buffs = nil;
        memInfo.sync = false;
        memInfo.subTargeted = false;
        memInfo.zone = '';
        memInfo.inzone = false;
        memInfo.name = '';
        memInfo.leader = false;
    end

    local partyIndex = math.ceil((memIdx + 1) / partyMaxSize);
    local scale = getScale(partyIndex);
    local showTP = showPartyTP(partyIndex);

    local subTargetActive = GetSubTargetActive();

    -- Get the hp color for bars and text
    local hpNameColor, hpGradient = GetCustomHpColors(memInfo.hpp, gConfig.colorCustomization.partyList);

    -- Detect current layout early for dimension calculations
    local layout = gConfig.partyListLayout or 0;

    -- Get party-specific bar scales for Layout 2
    local barScales = getBarScales(partyIndex);

    -- Apply bar scales - Layout 2 uses individual HP/MP scales, Layout 1 uses uniform scales
    local hpBarWidth, mpBarWidth, tpBarWidth, hpBarHeight, mpBarHeight;
    if layout == 1 and barScales then
        -- Layout 2: Use party-specific HP and MP bar X/Y scales
        hpBarWidth = settings.hpBarWidth * scale.x * barScales.hpBarScaleX;
        mpBarWidth = settings.mpBarWidth * scale.x * barScales.mpBarScaleX;
        hpBarHeight = settings.barHeight * scale.y * barScales.hpBarScaleY;
        mpBarHeight = settings.barHeight * scale.y * barScales.mpBarScaleY;
        tpBarWidth = settings.tpBarWidth * scale.x;  -- No TP bar in Layout 2
    else
        -- Layout 1: Use uniform scale.x and scale.y for all bars
        hpBarWidth = settings.hpBarWidth * scale.x;
        mpBarWidth = settings.mpBarWidth * scale.x;
        tpBarWidth = settings.tpBarWidth * scale.x;
        hpBarHeight = settings.barHeight * scale.y;
        mpBarHeight = settings.barHeight * scale.y;
    end
    local barHeight = settings.barHeight * scale.y;

    local hpStartX, hpStartY = imgui.GetCursorScreenPos();

    -- PRE-CALCULATE dimensions needed for selection box BEFORE drawing anything
    local partyIndex = math.ceil((memIdx + 1) / partyMaxSize);
    local fontSizes = getFontSizes(partyIndex);

    -- Set ALL font heights FIRST to ensure accurate text measurements
    memberText[memIdx].hp:set_font_height(fontSizes.hp);
    memberText[memIdx].mp:set_font_height(fontSizes.mp);
    memberText[memIdx].name:set_font_height(fontSizes.name);
    memberText[memIdx].tp:set_font_height(fontSizes.tp);
    memberText[memIdx].distance:set_font_height(fontSizes.name);

    -- PERFORMANCE: Use pre-calculated reference heights from UpdateVisuals
    local refHeights = partyRefHeights[partyIndex];
    local hpRefHeight = refHeights.hpRefHeight;
    local mpRefHeight = refHeights.mpRefHeight;
    local tpRefHeight = refHeights.tpRefHeight;
    local nameRefHeight = refHeights.nameRefHeight;

    -- Calculate text sizes
    memberText[memIdx].name:set_text(tostring(memInfo.name));
    local nameWidth, nameHeight = memberText[memIdx].name:get_text_size();
    memberText[memIdx].hp:set_text(tostring(memInfo.hp));
    local hpTextWidth, hpHeight = memberText[memIdx].hp:get_text_size();
    memberText[memIdx].mp:set_text(tostring(memInfo.mp));
    local mpTextWidth, mpHeight = memberText[memIdx].mp:get_text_size();
    memberText[memIdx].tp:set_text(tostring(memInfo.tp));
    local tpTextWidth, tpHeight = memberText[memIdx].tp:get_text_size();

    -- Calculate max TP text width for Layout 2 (to prevent MP bar shifting)
    local maxTpTextWidth = tpTextWidth;
    if layout == 1 then
        memberText[memIdx].tp:set_text("3000");
        maxTpTextWidth, _ = memberText[memIdx].tp:get_text_size();
        memberText[memIdx].tp:set_text(tostring(memInfo.tp));
    end

    -- Calculate allBarsLengths based on layout
    local allBarsLengths;
    if layout == 1 then
        -- Layout 2: Vertical stacking
        -- Row 1: HP bar only (HP text is positioned absolutely, right-aligned to bar)
        local row1Width = hpBarWidth;
        -- Row 2: TP text + MP bar + MP text (with spacing)
        local row2Width = 4 + maxTpTextWidth + 4 + mpBarWidth + 4 + mpTextWidth;
        -- Use the larger of the two rows
        allBarsLengths = math.max(row1Width, row2Width);
    else
        -- Layout 1: Horizontal layout
        allBarsLengths = hpBarWidth + mpBarWidth + imgui.GetStyle().FramePadding.x + imgui.GetStyle().ItemSpacing.x;
        if (showTP) then
            allBarsLengths = allBarsLengths + tpBarWidth + imgui.GetStyle().FramePadding.x + imgui.GetStyle().ItemSpacing.x;
        end
    end

    -- Calculate layout dimensions
    -- Use reference heights for consistent layout (prevents shifting when text content changes)
    local jobIconSize = gConfig.showPartyJobIcon and (settings.baseIconSize * 1.1 * scale.icon) or 0;  -- Use baseIconSize (not affected by status icon scale)
    local offsetSize = nameRefHeight > settings.baseIconSize and nameRefHeight or settings.baseIconSize;

    -- Calculate the actual topmost point of the member (where name/icon are drawn)
    local nameIconAreaHeight = math.max(jobIconSize, nameRefHeight);

    -- Calculate entrySize based on layout
    -- Use reference heights (not actual heights) to prevent layout shifting when text changes
    local entrySize;
    if layout == 1 then
        -- Layout 2: Vertical layout
        -- Entry includes: name text row + HP bar + 1px gap + MP bar
        entrySize = nameRefHeight + settings.nameTextOffsetY + hpBarHeight + 1 + mpBarHeight;
    else
        -- Layout 1: Horizontal layout
        -- entrySize includes the full member entry: name text + bars + hp text (plus offsets between them)
        entrySize = nameRefHeight + settings.nameTextOffsetY + hpBarHeight + settings.hpTextOffsetY + hpRefHeight;
    end

    -- DRAW SELECTION BOX using GetBackgroundDrawList (renders behind everything with rounded corners)
    if (memInfo.targeted == true) then
        local drawList = imgui.GetBackgroundDrawList();

        local selectionWidth = allBarsLengths + settings.cursorPaddingX1 + settings.cursorPaddingX2;
        local currentLayout = (gConfig.partyListLayout == 1) and gConfig.partyListLayout2 or gConfig.partyListLayout1;
        local selectionScaleY = currentLayout.selectionBoxScaleY or 1;
        local unscaledHeight = entrySize + settings.cursorPaddingY1 + settings.cursorPaddingY2;
        local selectionHeight = unscaledHeight * selectionScaleY;
        -- Anchor selection box to the top of name text (excludes job icon) - use reference height for consistency
        local topOfMember = hpStartY - nameRefHeight - settings.nameTextOffsetY;
        -- Offset top position to center the scaling (expand equally from center)
        local centerOffsetY = (selectionHeight - unscaledHeight) / 2;
        local selectionTL = {hpStartX - settings.cursorPaddingX1, topOfMember - settings.cursorPaddingY1 - centerOffsetY};
        local selectionBR = {selectionTL[1] + selectionWidth, selectionTL[2] + selectionHeight};

        -- Get selection gradient colors from config using helper
        local selectionGradient = GetCustomGradient(gConfig.colorCustomization.partyList, 'selectionGradient') or {'#4da5d9', '#78c0ed'};
        local startColor = HexToImGui(selectionGradient[1]);
        local endColor = HexToImGui(selectionGradient[2]);

        -- Draw gradient effect with multiple rectangles (top to bottom fade)
        local gradientSteps = 8;
        local stepHeight = selectionHeight / gradientSteps;
        for i = 1, gradientSteps do
            -- Calculate interpolation factor (0 at top, 1 at bottom)
            local t = (i - 1) / (gradientSteps - 1);

            -- Interpolate between start and end colors (RGBA float table)
            local r = startColor[1] + (endColor[1] - startColor[1]) * t;
            local g = startColor[2] + (endColor[2] - startColor[2]) * t;
            local b = startColor[3] + (endColor[3] - startColor[3]) * t;

            -- Fade alpha from more opaque at top to more transparent at bottom
            local alpha = 0.35 - t * 0.25; -- 0.35 to 0.10

            local stepColor = imgui.GetColorU32({r, g, b, alpha});

            local stepTL_y = selectionTL[2] + (i - 1) * stepHeight;
            local stepBR_y = stepTL_y + stepHeight;

            -- AddRectFilled with rounded corners (params: min{x,y}, max{x,y}, color, rounding, flags)
            if i == 1 then
                drawList:AddRectFilled({selectionTL[1], stepTL_y}, {selectionBR[1], stepBR_y}, stepColor, 6, 3); -- 6px radius, top corners only
            elseif i == gradientSteps then
                drawList:AddRectFilled({selectionTL[1], stepTL_y}, {selectionBR[1], stepBR_y}, stepColor, 6, 12); -- 6px radius, bottom corners only
            else
                drawList:AddRectFilled({selectionTL[1], stepTL_y}, {selectionBR[1], stepBR_y}, stepColor, 0);
            end
        end

        -- Draw border outline with rounded corners (convert ARGB to ImGui format for real-time updates)
        -- Cache the U32 conversion to avoid redundant bit operations every frame
        local borderColorARGB = gConfig.colorCustomization.partyList.selectionBorderColor;
        if cachedBorderColorARGB ~= borderColorARGB then
            cachedBorderColorARGB = borderColorARGB;
            cachedBorderColorU32 = imgui.GetColorU32(ARGBToImGui(borderColorARGB));
        end
        local borderColor = cachedBorderColorU32;
        drawList:AddRect({selectionTL[1], selectionTL[2]}, {selectionBR[1], selectionBR[2]}, borderColor, 6, 15, 2); -- 6px radius, all corners, 2px thick

        partyTargeted = true;
    end

    -- NOW draw all member content (will appear on top of selection box)

    -- Draw the job icon (if enabled)
    local namePosX = hpStartX;
    if gConfig.showPartyJobIcon then
        local offsetStartY = hpStartY - jobIconSize - settings.nameTextOffsetY;
        imgui.SetCursorScreenPos({namePosX, offsetStartY});
        local jobIcon = statusHandler.GetJobIcon(memInfo.job);
        if (jobIcon ~= nil) then
            namePosX = namePosX + jobIconSize + settings.nameTextOffsetX;
            imgui.Image(jobIcon, {jobIconSize, jobIconSize});
        end
        imgui.SetCursorScreenPos({hpStartX, hpStartY});
    end

    -- Update the hp text (text already set earlier for measurement)
    if not memberTextColorCache[memIdx] then memberTextColorCache[memIdx] = {}; end
    if (memberTextColorCache[memIdx].hp ~= gConfig.colorCustomization.partyList.hpTextColor) then
        memberText[memIdx].hp:set_font_color(gConfig.colorCustomization.partyList.hpTextColor);
        memberTextColorCache[memIdx].hp = gConfig.colorCustomization.partyList.hpTextColor;
    end

    -- Detect current layout
    local layout = gConfig.partyListLayout or 0;

    -- HP Interpolation logic (damage visualization)
    local currentTime = os.clock();
    local hppPercent = memInfo.hpp * 100; -- Convert to 0-100 range

    -- Initialize interpolation for this member if not set
    if not memberInterpolation[memIdx] then
        memberInterpolation[memIdx] = {
            currentHpp = hppPercent,
            interpolationDamagePercent = 0,
            interpolationHealPercent = 0
        };
    end

    local interp = memberInterpolation[memIdx];  -- PERFORMANCE: Local reference to avoid repeated table lookups

    -- If the member takes damage
    if hppPercent < interp.currentHpp then
        local previousInterpolationDamagePercent = interp.interpolationDamagePercent;
        local damageAmount = interp.currentHpp - hppPercent;

        interp.interpolationDamagePercent = interp.interpolationDamagePercent + damageAmount;

        if previousInterpolationDamagePercent > 0 and interp.lastHitAmount and damageAmount > interp.lastHitAmount then
            interp.lastHitTime = currentTime;
            interp.lastHitAmount = damageAmount;
        elseif previousInterpolationDamagePercent == 0 then
            interp.lastHitTime = currentTime;
            interp.lastHitAmount = damageAmount;
        end

        if not interp.lastHitTime or currentTime > interp.lastHitTime + (settings.hitFlashDuration * 0.25) then
            interp.lastHitTime = currentTime;
            interp.lastHitAmount = damageAmount;
        end

        -- If we previously were interpolating with an empty bar, reset the hit delay effect
        if previousInterpolationDamagePercent == 0 then
            interp.hitDelayStartTime = currentTime;
        end

        -- Clear healing interpolation when taking damage
        interp.interpolationHealPercent = 0;
        interp.healDelayStartTime = nil;
    elseif hppPercent > interp.currentHpp then
        -- If the member heals
        local previousInterpolationHealPercent = interp.interpolationHealPercent;
        local healAmount = hppPercent - interp.currentHpp;

        interp.interpolationHealPercent = interp.interpolationHealPercent + healAmount;

        if previousInterpolationHealPercent > 0 and interp.lastHealAmount and healAmount > interp.lastHealAmount then
            interp.lastHealTime = currentTime;
            interp.lastHealAmount = healAmount;
        elseif previousInterpolationHealPercent == 0 then
            interp.lastHealTime = currentTime;
            interp.lastHealAmount = healAmount;
        end

        if not interp.lastHealTime or currentTime > interp.lastHealTime + (settings.hitFlashDuration * 0.25) then
            interp.lastHealTime = currentTime;
            interp.lastHealAmount = healAmount;
        end

        -- If we previously were interpolating with an empty bar, reset the heal delay effect
        if previousInterpolationHealPercent == 0 then
            interp.healDelayStartTime = currentTime;
        end

        -- Clear damage interpolation when healing
        interp.interpolationDamagePercent = 0;
        interp.hitDelayStartTime = nil;
    end

    interp.currentHpp = hppPercent;

    -- PERFORMANCE: Initialize flash alphas - only calculate if there's active interpolation
    local interpolationOverlayAlpha = 0;
    local healInterpolationOverlayAlpha = 0;

    -- PERFORMANCE: Early exit if no interpolation is active
    local hasDamageInterp = interp.interpolationDamagePercent > 0;
    local hasHealInterp = interp.interpolationHealPercent > 0;
    local hasActiveFlash = gConfig.healthBarFlashEnabled and (
        (interp.lastHitTime and currentTime < interp.lastHitTime + settings.hitFlashDuration) or
        (interp.lastHealTime and currentTime < interp.lastHealTime + settings.hitFlashDuration)
    );

    if hasDamageInterp or hasHealInterp or hasActiveFlash then
        -- Reduce the damage HP amount to display based on the time passed since last frame
        if hasDamageInterp and interp.hitDelayStartTime and currentTime > interp.hitDelayStartTime + settings.hitDelayDuration then
            if interp.lastFrameTime then
                local deltaTime = currentTime - interp.lastFrameTime;
                local animSpeed = 0.1 + (0.9 * (interp.interpolationDamagePercent / 100));
                interp.interpolationDamagePercent = math.max(0, interp.interpolationDamagePercent - (settings.hitInterpolationDecayPercentPerSecond * deltaTime * animSpeed));
            end
        end

        -- Reduce the healing HP amount to display based on the time passed since last frame
        if hasHealInterp and interp.healDelayStartTime and currentTime > interp.healDelayStartTime + settings.hitDelayDuration then
            if interp.lastFrameTime then
                local deltaTime = currentTime - interp.lastFrameTime;
                local animSpeed = 0.1 + (0.9 * (interp.interpolationHealPercent / 100));
                interp.interpolationHealPercent = math.max(0, interp.interpolationHealPercent - (settings.hitInterpolationDecayPercentPerSecond * deltaTime * animSpeed));
            end
        end

        -- Calculate damage flash overlay alpha
        if gConfig.healthBarFlashEnabled and interp.lastHitTime and currentTime < interp.lastHitTime + settings.hitFlashDuration then
            local hitFlashTime = currentTime - interp.lastHitTime;
            local hitFlashTimePercent = hitFlashTime / settings.hitFlashDuration;
            local maxAlphaHitPercent = 20;
            local maxAlpha = math.min(interp.lastHitAmount, maxAlphaHitPercent) / maxAlphaHitPercent;
            maxAlpha = math.max(maxAlpha * 0.6, 0.4);
            interpolationOverlayAlpha = math.pow(1 - hitFlashTimePercent, 2) * maxAlpha;
        end

        -- Calculate healing flash overlay alpha
        if gConfig.healthBarFlashEnabled and interp.lastHealTime and currentTime < interp.lastHealTime + settings.hitFlashDuration then
            local healFlashTime = currentTime - interp.lastHealTime;
            local healFlashTimePercent = healFlashTime / settings.hitFlashDuration;
            local maxAlphaHealPercent = 20;
            local maxAlpha = math.min(interp.lastHealAmount, maxAlphaHealPercent) / maxAlphaHealPercent;
            maxAlpha = math.max(maxAlpha * 0.6, 0.4);
            healInterpolationOverlayAlpha = math.pow(1 - healFlashTimePercent, 2) * maxAlpha;
        end
    end

    interp.lastFrameTime = currentTime;

    -- Build HP bar data with interpolation
    -- Calculate base HP for display (subtract healing to show old HP during heal animation)
    local baseHpp = memInfo.hpp;
    if interp.interpolationHealPercent and interp.interpolationHealPercent > 0 then
        -- Convert from 0-1 range to 0-100, subtract heal, clamp, convert back
        local hppInPercent = memInfo.hpp * 100;
        hppInPercent = hppInPercent - interp.interpolationHealPercent;
        hppInPercent = math.max(0, hppInPercent);
        baseHpp = hppInPercent / 100;
    end

    local hpPercentData = {{baseHpp, hpGradient}};

    -- Get configurable interpolation colors
    local interpColors = GetHpInterpolationColors();

    -- Add interpolation bar for damage taken
    if interp.interpolationDamagePercent and interp.interpolationDamagePercent > 0 then
        local interpolationOverlay;

        if gConfig.healthBarFlashEnabled and interpolationOverlayAlpha > 0 then
            interpolationOverlay = {
                interpColors.damageFlashColor,
                interpolationOverlayAlpha
            };
        end

        table.insert(
            hpPercentData,
            {
                interp.interpolationDamagePercent / 100,
                interpColors.damageGradient,
                interpolationOverlay
            }
        );
    end

    -- Add interpolation bar for healing received
    if interp.interpolationHealPercent and interp.interpolationHealPercent > 0 then
        local healInterpolationOverlay;

        if gConfig.healthBarFlashEnabled and healInterpolationOverlayAlpha > 0 then
            healInterpolationOverlay = {
                interpColors.healFlashColor,
                healInterpolationOverlayAlpha
            };
        end

        table.insert(
            hpPercentData,
            {
                interp.interpolationHealPercent / 100,
                interpColors.healGradient,
                healInterpolationOverlay
            }
        );
    end

    -- Draw the HP bar (or zone bar for out-of-zone members)
    if (memInfo.inzone) then
        -- Use individual HP bar height in Layout 2
        local currentHpBarHeight = (layout == 1) and hpBarHeight or barHeight;
        progressbar.ProgressBar(hpPercentData, {hpBarWidth, currentHpBarHeight}, {borderConfig=borderConfig, decorate = gConfig.showPartyListBookends, backgroundGradientOverride = getBarBackgroundOverride(), borderColorOverride = getBarBorderOverride()});
        -- Hide zone text when in zone
        memberText[memIdx].zone:set_visible(false);
    elseif (memInfo.zone == '' or memInfo.zone == nil) then
        -- Calculate zone bar dimensions based on layout
        local zoneBarWidth, zoneBarHeight;
        if layout == 1 then
            -- Layout 2 (vertical): zone bar width is just HP bar width, height spans HP bar + gap + MP bar
            zoneBarWidth = hpBarWidth;
            zoneBarHeight = hpBarHeight + 1 + mpBarHeight;
        else
            -- Layout 1 (horizontal): zone bar width spans HP + MP + TP bars, height is single bar height
            zoneBarWidth = hpBarWidth + mpBarWidth;
            if showTP then
                zoneBarWidth = zoneBarWidth + tpBarWidth;
            end
            zoneBarHeight = barHeight;
        end
        imgui.Dummy({zoneBarWidth, zoneBarHeight});
        -- Hide zone text when no zone info
        memberText[memIdx].zone:set_visible(false);
    else
        -- Calculate zone bar dimensions based on layout
        local zoneBarWidth, zoneBarHeight;
        if layout == 1 then
            -- Layout 2 (vertical): zone bar width is just HP bar width, height spans HP bar + gap + MP bar
            zoneBarWidth = hpBarWidth;
            zoneBarHeight = hpBarHeight + 1 + mpBarHeight;
        else
            -- Layout 1 (horizontal): zone bar width spans HP + MP + TP bars, height is single bar height
            zoneBarWidth = hpBarWidth + mpBarWidth;
            if showTP then
                zoneBarWidth = zoneBarWidth + tpBarWidth;
            end
            zoneBarHeight = barHeight;
        end

        -- Draw zone bar with outline only
        local zoneBarStartX, zoneBarStartY = imgui.GetCursorScreenPos();
        imgui.Dummy({zoneBarWidth, zoneBarHeight});

        -- Draw outline for zone bar
        local drawList = imgui.GetWindowDrawList();
        drawList:AddRect(
            {zoneBarStartX, zoneBarStartY},
            {zoneBarStartX + zoneBarWidth, zoneBarStartY + zoneBarHeight},
            imgui.GetColorU32({0.5, 0.5, 0.5, 1.0}),  -- Gray outline
            0,
            ImDrawCornerFlags_None,
            1  -- 1px border thickness
        );

        -- Show zone text centered on the bar
        local zoneName = encoding:ShiftJIS_To_UTF8(AshitaCore:GetResourceManager():GetString("zones.names", memInfo.zone), true);
        memberText[memIdx].zone:set_text(zoneName);
        local zoneTextWidth, zoneTextHeight = memberText[memIdx].zone:get_text_size();
        memberText[memIdx].zone:set_position_x(zoneBarStartX + (zoneBarWidth - zoneTextWidth) / 2);  -- Center horizontally
        memberText[memIdx].zone:set_position_y(zoneBarStartY + (zoneBarHeight - zoneTextHeight) / 2);  -- Center vertically
        memberText[memIdx].zone:set_visible(true);
    end

    -- Position HP text based on layout
    -- Calculate baseline offset to keep text baseline consistent
    local hpBaselineOffset = hpRefHeight - hpHeight;
    local nameBaselineOffset = nameRefHeight - nameHeight;
    if layout == 1 then
        -- Layout 2: HP text on same row as name, right-aligned to bar
        memberText[memIdx].hp:set_position_x(hpStartX + hpBarWidth + 4);  -- 4px to the right of bar
        memberText[memIdx].hp:set_position_y(hpStartY - nameRefHeight - settings.nameTextOffsetY + hpBaselineOffset);  -- Same row as name
    else
        -- Layout 1: HP text below bar with standard offset
        memberText[memIdx].hp:set_position_x(hpStartX + hpBarWidth + settings.hpTextOffsetX);
        memberText[memIdx].hp:set_position_y(hpStartY + barHeight + settings.hpTextOffsetY + hpBaselineOffset);
    end

    -- Draw the leader icon
    if (memInfo.leader) then
        draw_circle({hpStartX + settings.dotRadius/2, hpStartY + settings.dotRadius/2}, settings.dotRadius, {1, 1, .5, 1}, settings.dotRadius * 3, true);
    end

    local desiredNameColor = gConfig.colorCustomization.partyList.nameTextColor;
    -- Only call set_color if the color has changed
    if (memberTextColorCache[memIdx].name ~= desiredNameColor) then
        memberText[memIdx].name:set_font_color(desiredNameColor);
        memberTextColorCache[memIdx].name = desiredNameColor;
    end
    memberText[memIdx].name:set_position_x(namePosX);
    memberText[memIdx].name:set_position_y(hpStartY - nameRefHeight - settings.nameTextOffsetY + nameBaselineOffset);

    -- Check if member is casting and show cast bar if so (only if cast bars are enabled)
    local castData = nil;
    local isCasting = false;
    if (gConfig.partyListCastBars and memInfo.inzone and memInfo.serverid ~= nil) then
        castData = partyList.partyCasts[memInfo.serverid];
        if (castData ~= nil and castData.spellName ~= nil and castData.castTime ~= nil and castData.startTime ~= nil) then
            isCasting = true;

            -- Replace name text with spell name
            memberText[memIdx].name:set_text(castData.spellName);
            local spellNameWidth, _ = memberText[memIdx].name:get_text_size();

            -- Calculate cast progress
            local elapsed = os.clock() - castData.startTime;
            local progress = math.min(elapsed / castData.castTime, 1.0);

            -- Draw cast bar to the right of spell name
            local castBarWidth = hpBarWidth * 0.6; -- 60% of HP bar width
            local castBarHeight = math.max(6, nameRefHeight * 0.8 * gConfig.partyListCastBarScaleY); -- 80% of reference name height, scaled by user setting (min 6px for progress bar padding)
            local castBarX = namePosX + spellNameWidth + 4; -- 4px spacing after spell name
            local castBarY = hpStartY - nameRefHeight - settings.nameTextOffsetY + (nameRefHeight - castBarHeight) / 2; -- Vertically center with text area

            -- Get cast bar gradient from config
            local castGradient = GetCustomGradient(gConfig.colorCustomization.partyList, 'castBarGradient') or {'#ffaa00', '#ffcc44'};

            -- Draw cast bar with absolute positioning
            progressbar.ProgressBar(
                {{progress, castGradient}},
                {castBarWidth, castBarHeight},
                {
                    decorate = false,
                    absolutePosition = {castBarX, castBarY},
                    borderColorOverride = getBarBorderOverride()
                }
            );
        end
    end

    -- Update the distance text (separate from name) - hide when casting
    local showDistance = false;
    local highlightDistance = false;
    if (not isCasting) then
        -- Restore original name text when not casting
        memberText[memIdx].name:set_text(tostring(memInfo.name));
    end
    if (not isCasting and gConfig.showPartyListDistance and memInfo.inzone) then
        local distance = nil;
        -- Use preview distance if available, otherwise calculate from entity
        if memInfo.previewDistance then
            distance = memInfo.previewDistance;
        elseif memInfo.index then
            -- PERFORMANCE: Use cached entity from frame cache
            local entity = frameCache.entity;
            if entity ~= nil then
                distance = math.sqrt(entity:GetDistance(memInfo.index))
            end
        end
        if (distance ~= nil and distance > 0 and distance <= 50) then
            local distanceText = ('%.1f'):fmt(distance);
            memberText[memIdx].distance:set_text('- ' .. distanceText);

            local distancePosX = namePosX + nameWidth + 4;  -- Add spacing after name
            memberText[memIdx].distance:set_position_x(distancePosX);
            memberText[memIdx].distance:set_position_y(hpStartY - nameRefHeight - settings.nameTextOffsetY + nameBaselineOffset);

            showDistance = true;

            if (gConfig.partyListDistanceHighlight > 0 and distance <= gConfig.partyListDistanceHighlight) then
                highlightDistance = true;
            end
        end
    end

    -- Update distance visibility and color
    memberText[memIdx].distance:set_visible(showDistance);
    if showDistance then
        local desiredDistanceColor = highlightDistance and 0xFF00FFFF or gConfig.colorCustomization.partyList.nameTextColor;
        if (memberTextColorCache[memIdx].distance ~= desiredDistanceColor) then
            memberText[memIdx].distance:set_font_color(desiredDistanceColor);
            memberTextColorCache[memIdx].distance = desiredDistanceColor;
        end
    end

    -- Job/Subjob text (Layout 1 only, far right of name line)
    local showJobText = false;
    if gConfig.showPartyListJob and layout == 0 and memInfo.inzone and memInfo.job ~= '' and memInfo.job ~= nil and memInfo.job > 0 then
        -- Build job string (e.g., "WAR99/NIN49")
        local mainJobAbbr = AshitaCore:GetResourceManager():GetString('jobs.names_abbr', memInfo.job) or '';
        local jobStr = mainJobAbbr .. tostring(memInfo.level);

        if memInfo.subjob ~= nil and memInfo.subjob ~= '' and memInfo.subjob > 0 then
            local subJobAbbr = AshitaCore:GetResourceManager():GetString('jobs.names_abbr', memInfo.subjob) or '';
            jobStr = jobStr .. '/' .. subJobAbbr .. tostring(memInfo.subjoblevel);
        end

        memberText[memIdx].job:set_text(jobStr);
        memberText[memIdx].job:set_font_height(fontSizes.name);
        local jobTextWidth, jobTextHeight = memberText[memIdx].job:get_text_size();

        -- Position at far right of name row (right-aligned to allBarsLengths)
        local jobPosX = hpStartX + allBarsLengths - jobTextWidth;
        memberText[memIdx].job:set_position_x(jobPosX);
        memberText[memIdx].job:set_position_y(hpStartY - nameRefHeight - settings.nameTextOffsetY + nameBaselineOffset);

        -- Set color (same as name text color)
        local desiredJobColor = gConfig.colorCustomization.partyList.nameTextColor;
        if (memberTextColorCache[memIdx].job ~= desiredJobColor) then
            memberText[memIdx].job:set_font_color(desiredJobColor);
            memberTextColorCache[memIdx].job = desiredJobColor;
        end

        showJobText = true;
    end
    memberText[memIdx].job:set_visible(showJobText);

    -- Variables for MP bar positioning (used by status icons later)
    local mpStartX, mpStartY;

    if (memInfo.inzone) then
        if layout == 1 then
            -- ========== LAYOUT 2: Compact Vertical ==========
            -- Add 1px gap below HP bar
            imgui.Dummy({0, 1});

            -- Store the row start position
            local rowStartX, rowStartY = imgui.GetCursorScreenPos();

            -- === TP TEXT (LEFT OF MP BAR) ===
            -- Set TP text color
            local desiredTpColor = (memInfo.tp >= 1000) and gConfig.colorCustomization.partyList.tpFullTextColor or gConfig.colorCustomization.partyList.tpEmptyTextColor;
            if (memberTextColorCache[memIdx].tp ~= desiredTpColor) then
                memberText[memIdx].tp:set_font_color(desiredTpColor);
                memberTextColorCache[memIdx].tp = desiredTpColor;
            end

            -- Position TP text at row start + 4px offset (LEFT of MP bar)
            -- Calculate baseline offset to keep text baseline consistent
            local tpBaselineOffset = tpRefHeight - tpHeight;
            memberText[memIdx].tp:set_position_x(rowStartX + 4);
            memberText[memIdx].tp:set_position_y(rowStartY + tpBaselineOffset);

            -- === MP BAR ===
            -- Position MP bar at a fixed offset based on max TP text width to prevent shifting
            -- maxTpTextWidth was calculated earlier in the function
            local mpBarStartX = rowStartX + 4 + maxTpTextWidth + 4;  -- 4px padding + max TP width + 4px gap
            mpStartX = mpBarStartX;
            mpStartY = rowStartY;
            imgui.SetCursorScreenPos({mpStartX, mpStartY});

            -- Draw MP bar
            local mpGradient = GetCustomGradient(gConfig.colorCustomization.partyList, 'mpGradient') or {'#9abb5a', '#bfe07d'};
            progressbar.ProgressBar({{memInfo.mpp, mpGradient}}, {mpBarWidth, mpBarHeight}, {borderConfig=borderConfig, decorate = gConfig.showPartyListBookends, backgroundGradientOverride = getBarBackgroundOverride(), borderColorOverride = getBarBorderOverride()});

            -- === MP TEXT (RIGHT OF MP BAR) ===
            -- Prepare MP text
            if (memberTextColorCache[memIdx].mp ~= gConfig.colorCustomization.partyList.mpTextColor) then
                memberText[memIdx].mp:set_font_color(gConfig.colorCustomization.partyList.mpTextColor);
                memberTextColorCache[memIdx].mp = gConfig.colorCustomization.partyList.mpTextColor;
            end
            memberText[memIdx].mp:set_text(tostring(memInfo.mp));

            -- Position MP text (RIGHT of MP bar, vertically centered with bar)
            -- Use reference height for centering to prevent layout shifting, then apply baseline offset
            local mpBaselineOffset = mpRefHeight - mpHeight;
            memberText[memIdx].mp:set_position_x(mpStartX + mpBarWidth + 4);  -- 4px spacing after MP bar
            memberText[memIdx].mp:set_position_y(mpStartY + (mpBarHeight - mpRefHeight) / 2 + mpBaselineOffset);

        else
            -- ========== LAYOUT 1: Horizontal ==========
            imgui.SameLine();

            -- Draw the MP bar
            imgui.SetCursorPosX(imgui.GetCursorPosX());
            mpStartX, mpStartY = imgui.GetCursorScreenPos();
            local mpGradient = GetCustomGradient(gConfig.colorCustomization.partyList, 'mpGradient') or {'#9abb5a', '#bfe07d'};
            progressbar.ProgressBar({{memInfo.mpp, mpGradient}}, {mpBarWidth, mpBarHeight}, {borderConfig=borderConfig, decorate = gConfig.showPartyListBookends, backgroundGradientOverride = getBarBackgroundOverride(), borderColorOverride = getBarBorderOverride()});

            -- Update the mp text
            -- Only call set_color if the color has changed
            if (memberTextColorCache[memIdx].mp ~= gConfig.colorCustomization.partyList.mpTextColor) then
                memberText[memIdx].mp:set_font_color(gConfig.colorCustomization.partyList.mpTextColor);
                memberTextColorCache[memIdx].mp = gConfig.colorCustomization.partyList.mpTextColor;
            end
            memberText[memIdx].mp:set_text(tostring(memInfo.mp));
            -- MP font is left-aligned, so position RIGHT edge by subtracting text width
            -- Calculate baseline offset to keep text baseline consistent
            local mpBaselineOffset = mpRefHeight - mpHeight;
            memberText[memIdx].mp:set_position_x(mpStartX + mpBarWidth - mpTextWidth);
            memberText[memIdx].mp:set_position_y(mpStartY + mpBarHeight + settings.mpTextOffsetY + mpBaselineOffset);

            -- Draw the TP bar
            if (showTP) then
                imgui.SameLine();
                local tpStartX, tpStartY;
                imgui.SetCursorPosX(imgui.GetCursorPosX());
                tpStartX, tpStartY = imgui.GetCursorScreenPos();

                local tpGradient = GetCustomGradient(gConfig.colorCustomization.partyList, 'tpGradient') or {'#3898ce', '#78c4ee'};
                local tpOverlayGradient = {'#0078CC', '#0078CC'};
                local mainPercent;
                local tpOverlay;

                if (memInfo.tp >= 1000) then
                    mainPercent = (memInfo.tp - 1000) / 2000;
                    if (gConfig.partyListFlashTP) then
                        tpOverlay = {{1, tpOverlayGradient}, math.ceil(barHeight * 5/7), 0, { '#3ECE00', 1 }};
                    else
                        tpOverlay = {{1, tpOverlayGradient}, math.ceil(barHeight * 2/7), 1};
                    end
                else
                    mainPercent = memInfo.tp / 1000;
                end

                progressbar.ProgressBar({{mainPercent, tpGradient}}, {tpBarWidth, barHeight}, {overlayBar=tpOverlay, borderConfig=borderConfig, decorate = gConfig.showPartyListBookends, backgroundGradientOverride = getBarBackgroundOverride(), borderColorOverride = getBarBorderOverride()});

                -- Update the tp text
                local desiredTpColor = (memInfo.tp >= 1000) and gConfig.colorCustomization.partyList.tpFullTextColor or gConfig.colorCustomization.partyList.tpEmptyTextColor;
                -- Only call set_color if the color has changed
                if (memberTextColorCache[memIdx].tp ~= desiredTpColor) then
                    memberText[memIdx].tp:set_font_color(desiredTpColor);
                    memberTextColorCache[memIdx].tp = desiredTpColor;
                end
                memberText[memIdx].tp:set_text(tostring(memInfo.tp));
                -- TP font is left-aligned, so position RIGHT edge by subtracting text width
                -- Calculate baseline offset to keep text baseline consistent
                local tpBaselineOffset = tpRefHeight - tpHeight;
                memberText[memIdx].tp:set_position_x(tpStartX + tpBarWidth - tpTextWidth);
                memberText[memIdx].tp:set_position_y(tpStartY + barHeight + settings.tpTextOffsetY + tpBaselineOffset);
            end
        end

        -- Draw cursor using ImGui (like job icons)
        if ((memInfo.targeted == true and not subTargetActive) or memInfo.subTargeted) then
            local cursorTexture = cursorTextures[gConfig.partyListCursor];
            if (cursorTexture ~= nil) then
                local cursorImage = tonumber(ffi.cast("uint32_t", cursorTexture.image));

                -- Calculate cursor size based on settings.arrowSize
                local cursorWidth = cursorTexture.width * settings.arrowSize;
                local cursorHeight = cursorTexture.height * settings.arrowSize;

                -- Calculate position aligned with selection container box
                -- Recalculate selection box coordinates to match the selection box drawing logic
                local currentLayout = (gConfig.partyListLayout == 1) and gConfig.partyListLayout2 or gConfig.partyListLayout1;
                local selectionScaleY = currentLayout.selectionBoxScaleY or 1;
                local unscaledHeight = entrySize + settings.cursorPaddingY1 + settings.cursorPaddingY2;
                local selectionHeight = unscaledHeight * selectionScaleY;
                local topOfMember = hpStartY - nameRefHeight - settings.nameTextOffsetY;
                local centerOffsetY = (selectionHeight - unscaledHeight) / 2;
                local selectionTL_X = hpStartX - settings.cursorPaddingX1;
                local selectionTL_Y = topOfMember - settings.cursorPaddingY1 - centerOffsetY;

                -- Position cursor to the left of the selection box, vertically centered
                local cursorX = selectionTL_X - cursorWidth;
                local cursorY = selectionTL_Y + (selectionHeight / 2) - (cursorHeight / 2);

                -- Determine tint color
                local tintColor;
                if (subTargetActive) then
                    tintColor = imgui.GetColorU32(settings.subtargetArrowTint);
                else
                    tintColor = IM_COL32_WHITE;
                end

                -- Draw using UI draw list
                local draw_list = GetUIDrawList();
                draw_list:AddImage(
                    cursorImage,
                    {cursorX, cursorY},
                    {cursorX + cursorWidth, cursorY + cursorHeight},
                    {0, 0}, {1, 1},
                    tintColor
                );

                partySubTargeted = true;
            end
        end

        -- Draw the different party list buff / debuff themes
        if (partyIndex == 1 and memInfo.buffs ~= nil and #memInfo.buffs > 0) then
            if (gConfig.partyListStatusTheme == 0 or gConfig.partyListStatusTheme == 1) then
                -- PERFORMANCE: Reuse buff/debuff tables instead of allocating new ones
                -- Clear the tables (faster than creating new)
                for k in pairs(reusableBuffs) do reusableBuffs[k] = nil; end
                for k in pairs(reusableDebuffs) do reusableDebuffs[k] = nil; end

                local buffCount = 0;
                local debuffCount = 0;
                for i = 0, #memInfo.buffs do
                    if (buffTable.IsBuff(memInfo.buffs[i])) then
                        buffCount = buffCount + 1;
                        reusableBuffs[buffCount] = memInfo.buffs[i];
                    else
                        debuffCount = debuffCount + 1;
                        reusableDebuffs[debuffCount] = memInfo.buffs[i];
                    end
                end

                if (buffCount > 0) then
                    if (gConfig.partyListStatusTheme == 0 and buffWindowX[memIdx] ~= nil) then
                        imgui.SetNextWindowPos({hpStartX - buffWindowX[memIdx] - settings.buffOffset , hpStartY - settings.iconSize*1.2});
                    elseif (gConfig.partyListStatusTheme == 1 and fullMenuWidth[partyIndex] ~= nil) then
                        local thisPosX, _ = imgui.GetWindowPos();
                        imgui.SetNextWindowPos({ thisPosX + fullMenuWidth[partyIndex], hpStartY - settings.iconSize * 1.2 });
                    end
                    if (imgui.Begin('PlayerBuffs'..memIdx, true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoSavedSettings))) then
                        imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {3, 1});
                        DrawStatusIcons(reusableBuffs, settings.iconSize, 32, 1, true);
                        imgui.PopStyleVar(1);
                    end
                    local buffWindowSizeX, _ = imgui.GetWindowSize();
                    buffWindowX[memIdx] = buffWindowSizeX;

                    imgui.End();
                end

                if (debuffCount > 0) then
                    if (gConfig.partyListStatusTheme == 0 and debuffWindowX[memIdx] ~= nil) then
                        imgui.SetNextWindowPos({hpStartX - debuffWindowX[memIdx] - settings.buffOffset , hpStartY});
                    elseif (gConfig.partyListStatusTheme == 1 and fullMenuWidth[partyIndex] ~= nil) then
                        local thisPosX, _ = imgui.GetWindowPos();
                        imgui.SetNextWindowPos({ thisPosX + fullMenuWidth[partyIndex], hpStartY });
                    end
                    if (imgui.Begin('PlayerDebuffs'..memIdx, true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoSavedSettings))) then
                        imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {3, 1});
                        DrawStatusIcons(reusableDebuffs, settings.iconSize, 32, 1, true);
                        imgui.PopStyleVar(1);
                    end
                    local buffWindowSizeX, buffWindowSizeY = imgui.GetWindowSize();
                    debuffWindowX[memIdx] = buffWindowSizeX;
                    imgui.End();
                end
            elseif (gConfig.partyListStatusTheme == 2) then
                -- Draw FFXIV theme
                local resetX, resetY = imgui.GetCursorScreenPos();
                imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {0, 0} );
                imgui.SetNextWindowPos({mpStartX, mpStartY - settings.iconSize - settings.xivBuffOffsetY})
                if (imgui.Begin('XIVStatus'..memIdx, true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoSavedSettings))) then
                    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {0, 0});
                    DrawStatusIcons(memInfo.buffs, settings.iconSize, 32, 1);
                    imgui.PopStyleVar(1);
                end
                imgui.PopStyleVar(1);
                imgui.End();
                imgui.SetCursorScreenPos({resetX, resetY});
            elseif (gConfig.partyListStatusTheme == 3) then
                if (buffWindowX[memIdx] ~= nil) then
                    imgui.SetNextWindowPos({hpStartX - buffWindowX[memIdx] - settings.buffOffset , memberText[memIdx].name.settings.position_y - settings.iconSize/2});
                end
                if (imgui.Begin('PlayerBuffs'..memIdx, true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoSavedSettings))) then
                    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {0, 3});
                    DrawStatusIcons(memInfo.buffs, settings.iconSize, 7, 3);
                    imgui.PopStyleVar(1);
                end
                local buffWindowSizeX, _ = imgui.GetWindowSize();
                buffWindowX[memIdx] = buffWindowSizeX;

                imgui.End();
            end
        end
    end

    if (memInfo.sync) then
        draw_circle({hpStartX + settings.dotRadius/2, hpStartY + barHeight}, settings.dotRadius, {.5, .5, 1, 1}, settings.dotRadius * 3, true);
    end

    memberText[memIdx].hp:set_visible(memInfo.inzone);
    memberText[memIdx].mp:set_visible(memInfo.inzone);
    -- In Layout 2, TP is shown for party 1 only (alliance parties don't have TP data)
    -- In Layout 1, TP visibility depends on showTP flag
    local partyIndex = math.floor(memIdx / 6) + 1;
    if layout == 1 then
        -- Layout 2: show TP text only for party 1, hide for parties 2 and 3
        memberText[memIdx].tp:set_visible(memInfo.inzone and partyIndex == 1);
    else
        memberText[memIdx].tp:set_visible(memInfo.inzone and showTP);  -- Layout 1: show if showTP is true
    end

    -- Reserve space in ImGui layout for the text/bars (which use absolute positioning)
    -- For Layout 2, reserve horizontal space based on the larger of the two rows
    if layout == 1 and memInfo.inzone then
        -- Row 1: HP bar only
        local row1Width = hpBarWidth;
        -- Row 2: TP text + MP bar + MP text (with spacing)
        local row2Width = 4 + maxTpTextWidth + 4 + mpBarWidth + 4 + mpTextWidth;
        -- Use the larger of the two rows
        local fullWidth = math.max(row1Width, row2Width);
        imgui.Dummy({fullWidth, 0});
    end

    local bottomSpacing;
    if layout == 1 then
        -- Layout 2: TP text and MP bar are on same row (text is beside bar, not below)
        -- Only reserve space if TP text extends below the MP bar bottom
        bottomSpacing = math.max(0, tpRefHeight - mpBarHeight);
    else
        -- Layout 1: HP text is below the horizontal bars (use reference height for consistent layout)
        bottomSpacing = settings.hpTextOffsetY + hpRefHeight;
    end
    imgui.Dummy({0, bottomSpacing});

    -- Add spacing between members: fixed base spacing + user-customizable entrySpacing (if not last visible member)
    if (not isLastVisibleMember) then
        local BASE_MEMBER_SPACING = 6; -- Fixed 6px spacing between members
        imgui.Dummy({0, BASE_MEMBER_SPACING + settings.entrySpacing[partyIndex]});
    end
end

partyList.DrawWindow = function(settings)

    -- ============================================
    -- PERFORMANCE: Populate frame cache once at start
    -- ============================================

    -- Invalidate config cache every frame (will be rebuilt on first access if needed)
    -- This ensures config changes are picked up immediately
    partyConfigCacheValid = false;
    updatePartyConfigCache();

    -- Cache game state references (used by all members this frame)
    frameCache.party = GetPartySafe();
    frameCache.player = GetPlayerSafe();
    frameCache.entity = GetEntitySafe();
    frameCache.playerTarget = GetTargetSafe();

    local party = frameCache.party;
    local player = frameCache.player;

    if (party == nil or player == nil or player.isZoning or player:GetMainJob() == 0) then
        UpdateTextVisibility(false);
        return;
    end

    -- Cache target info once (same for all members)
    if frameCache.playerTarget ~= nil then
        frameCache.t1, frameCache.t2 = GetTargets();
        frameCache.stPartyIndex = GetStPartyIndex();
        frameCache.subTargetActive = GetSubTargetActive();
    else
        frameCache.t1 = nil;
        frameCache.t2 = nil;
        frameCache.stPartyIndex = nil;
        frameCache.subTargetActive = false;
    end

    -- Pre-calculate active member counts for each party (avoids redundant GetMemberIsActive calls)
    for partyIndex = 1, 3 do
        local firstIdx = (partyIndex - 1) * partyMaxSize;
        local count = 0;
        frameCache.activeMemberList[partyIndex] = {};

        if showConfig[1] and gConfig.partyListPreview then
            count = partyMaxSize;
            for i = 0, partyMaxSize - 1 do
                frameCache.activeMemberList[partyIndex][i] = true;
            end
        else
            for i = 0, partyMaxSize - 1 do
                local memIdx = firstIdx + i;
                if party:GetMemberIsActive(memIdx) ~= 0 then
                    count = count + 1;
                    frameCache.activeMemberList[partyIndex][i] = true;
                else
                    break;  -- Members are contiguous
                end
            end
        end
        frameCache.activeMemberCount[partyIndex] = count;
    end

    -- Handle debounced settings save
    if pendingSettingsSave then
        local now = os.clock();
        if now - lastSettingsSaveTime >= SETTINGS_SAVE_DEBOUNCE then
            ashita_settings.save();
            pendingSettingsSave = false;
        end
    end

    partyTargeted = false;
    partySubTargeted = false;

    -- Main party window
    partyList.DrawPartyWindow(settings, party, 1);

    -- Alliance party windows
    if (gConfig.partyListAlliance) then
        partyList.DrawPartyWindow(settings, party, 2);
        partyList.DrawPartyWindow(settings, party, 3);
    else
        UpdateTextVisibility(false, 2);
        UpdateTextVisibility(false, 3);
    end

    -- Cursor is now drawn directly in DrawMember using ImGui, no visibility flag needed
end

partyList.DrawPartyWindow = function(settings, party, partyIndex)
    local firstPlayerIndex = (partyIndex - 1) * partyMaxSize;
    local lastPlayerIndex = firstPlayerIndex + partyMaxSize - 1;

    -- PERFORMANCE: Use pre-calculated active member count from frame cache
    local partyMemberCount = frameCache.activeMemberCount[partyIndex];

    if (partyIndex == 1 and not gConfig.showPartyListWhenSolo and partyMemberCount <= 1) then
		UpdateTextVisibility(false);
        return;
	end

    if(partyIndex > 1 and partyMemberCount == 0) then
        UpdateTextVisibility(false, partyIndex);
        return;
    end

    local backgroundPrim = partyWindowPrim[partyIndex].background;

    -- Determine which title texture to use based on party index and member count
    local titleUV;
    if (partyIndex == 1) then
        titleUV = partyMemberCount == 1 and titleUVs.solo or titleUVs.party;
    elseif (partyIndex == 2) then
        titleUV = titleUVs.partyB;
    else
        titleUV = titleUVs.partyC;
    end

    local imguiPosX, imguiPosY;

    local windowFlags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoBringToFrontOnFocus);
    if (gConfig.lockPositions) then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
    end

    local windowName = 'PartyList';
    if (partyIndex > 1) then
        windowName = windowName .. partyIndex
    end

    local scale = getScale(partyIndex);
    local iconSize = 0; --settings.iconSize * scale.icon;

    -- Remove all padding and start our window
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {0,0});
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { settings.barSpacing * scale.x, 0 });
    if (imgui.Begin(windowName, true, windowFlags)) then
        imguiPosX, imguiPosY = imgui.GetWindowPos();

        -- PERFORMANCE: Use pre-calculated reference heights from UpdateVisuals
        local nameRefHeight = partyRefHeights[partyIndex].nameRefHeight;
        local offsetSize = nameRefHeight > iconSize and nameRefHeight or iconSize;
        imgui.Dummy({0, settings.nameTextOffsetY + offsetSize});

        UpdateTextVisibility(true, partyIndex);

        -- Calculate which is the last member that will be drawn
        local lastVisibleMemberIdx = firstPlayerIndex;
        for i = firstPlayerIndex, lastPlayerIndex do
            local relIndex = i - firstPlayerIndex
            if ((partyIndex == 1 and settings.expandHeight) or relIndex < partyMemberCount or relIndex < settings.minRows) then
                lastVisibleMemberIdx = i;
            end
        end

        -- Draw all members
        for i = firstPlayerIndex, lastPlayerIndex do
            local relIndex = i - firstPlayerIndex
            if ((partyIndex == 1 and settings.expandHeight) or relIndex < partyMemberCount or relIndex < settings.minRows) then
                DrawMember(i, settings, i == lastVisibleMemberIdx);
            else
                UpdateTextVisibilityByMember(i, false);
            end
        end
    end

    local menuWidth, menuHeight = imgui.GetWindowSize();

    fullMenuWidth[partyIndex] = menuWidth;
    fullMenuHeight[partyIndex] = menuHeight;

    -- if (fullMenuWidth[partyIndex] ~= nil and fullMenuHeight[partyIndex] ~= nil) then
        local bgWidth = fullMenuWidth[partyIndex] + (settings.bgPadding * 2);
        local bgHeight = fullMenuHeight[partyIndex] + (settings.bgPaddingY * 2);

        -- Apply colors from colorCustomization every frame (for real-time updates)
        local bgColor = gConfig.colorCustomization.partyList.bgColor;
        local borderColor = gConfig.colorCustomization.partyList.borderColor;

        backgroundPrim.bg.visible = backgroundPrim.bg.exists;
        backgroundPrim.bg.position_x = imguiPosX - settings.bgPadding;
        backgroundPrim.bg.position_y = imguiPosY - settings.bgPaddingY;
        backgroundPrim.bg.width = bgWidth / gConfig.partyListBgScale;
        backgroundPrim.bg.height = bgHeight / gConfig.partyListBgScale;
        backgroundPrim.bg.color = bgColor;

        backgroundPrim.br.visible = backgroundPrim.br.exists;
        backgroundPrim.br.position_x = backgroundPrim.bg.position_x + bgWidth - settings.borderSize + settings.bgOffset;
        backgroundPrim.br.position_y = backgroundPrim.bg.position_y + bgHeight - settings.borderSize + settings.bgOffset;
        backgroundPrim.br.width = settings.borderSize;
        backgroundPrim.br.height = settings.borderSize;
        backgroundPrim.br.color = borderColor;

        backgroundPrim.tr.visible = backgroundPrim.tr.exists;
        backgroundPrim.tr.position_x = backgroundPrim.br.position_x;
        backgroundPrim.tr.position_y = backgroundPrim.bg.position_y - settings.bgOffset;
        backgroundPrim.tr.width = settings.borderSize;
        backgroundPrim.tr.height = backgroundPrim.br.position_y - backgroundPrim.tr.position_y;
        backgroundPrim.tr.color = borderColor;

        backgroundPrim.tl.visible = backgroundPrim.tl.exists;
        backgroundPrim.tl.position_x = backgroundPrim.bg.position_x - settings.bgOffset;
        backgroundPrim.tl.position_y = backgroundPrim.bg.position_y - settings.bgOffset;
        backgroundPrim.tl.width = backgroundPrim.tr.position_x - backgroundPrim.tl.position_x;
        backgroundPrim.tl.height = backgroundPrim.br.position_y - backgroundPrim.tl.position_y;
        backgroundPrim.tl.color = borderColor;

        backgroundPrim.bl.visible = backgroundPrim.bl.exists;
        backgroundPrim.bl.position_x = backgroundPrim.tl.position_x;
        backgroundPrim.bl.position_y = backgroundPrim.bg.position_y + bgHeight - settings.borderSize + settings.bgOffset;
        backgroundPrim.bl.width = backgroundPrim.br.position_x - backgroundPrim.bl.position_x;
        backgroundPrim.bl.height = settings.borderSize;
        backgroundPrim.bl.color = borderColor;

        -- Draw title image centered above the window
        if (gConfig.showPartyListTitle and partyTitlesTexture ~= nil) then
            local titleImage = tonumber(ffi.cast("uint32_t", partyTitlesTexture.image));

            -- Calculate title dimensions from texture
            -- Each title is 1/4 of the total texture height (4 titles stacked vertically)
            local titleWidth = partyTitlesTexture.width;
            local titleHeight = partyTitlesTexture.height / 4;

            titleWidth = titleWidth * .8;
            titleHeight = titleHeight * .8;

            -- Center the title above the window
            local titlePosX = imguiPosX + math.floor((bgWidth / 2) - (titleWidth / 2));
            local titlePosY = imguiPosY - titleHeight + 6;
            
            -- Draw using foreground draw list (always use screen coordinates)
            local draw_list = imgui.GetForegroundDrawList();
            draw_list:AddImage(
                titleImage,
                {titlePosX, titlePosY},
                {titlePosX + titleWidth, titlePosY + titleHeight},
                {titleUV[1], titleUV[2]}, {titleUV[3], titleUV[4]},
                IM_COL32_WHITE
            );
        end
    -- end

	imgui.End();
    imgui.PopStyleVar(2);

    if (settings.alignBottom and imguiPosX ~= nil) then
        -- Migrate old settings
        if (partyIndex == 1 and gConfig.partyListState ~= nil and gConfig.partyListState.x ~= nil) then
            local oldValues = gConfig.partyListState;
            gConfig.partyListState = {};
            gConfig.partyListState[partyIndex] = oldValues;
            ashita_settings.save();
        end

        if (gConfig.partyListState == nil) then
            gConfig.partyListState = {};
        end

        local partyListState = gConfig.partyListState[partyIndex];

        if (partyListState ~= nil) then
            -- Move window if size changed
            if (menuHeight ~= partyListState.height) then
                local newPosY = partyListState.y + partyListState.height - menuHeight;
                imguiPosY = newPosY; --imguiPosY + (partyListState.height - menuHeight]);
                imgui.SetWindowPos(windowName, { imguiPosX, imguiPosY });
            end
        end

        -- Update if the state changed
        if (partyListState == nil or
                imguiPosX ~= partyListState.x or imguiPosY ~= partyListState.y or
                menuWidth ~= partyListState.width or menuHeight ~= partyListState.height) then
            gConfig.partyListState[partyIndex] = {
                x = imguiPosX,
                y = imguiPosY,
                width = menuWidth,
                height = menuHeight,
            };
            -- PERFORMANCE: Debounce settings save to avoid I/O blocking during window drag
            lastSettingsSaveTime = os.clock();
            pendingSettingsSave = true;
        end
    end
end

partyList.Initialize = function(settings)
    -- PERFORMANCE: Initialize config cache before any getFontSizes calls
    partyConfigCacheValid = false;
    updatePartyConfigCache();

    -- Cache the initial font sizes
    cachedFontSizes = {
		settings.fontSizes[1],
		settings.fontSizes[2],
		settings.fontSizes[3],
	};

	-- Cache the initial font family, flags, and outline width
	cachedFontFamily = settings.name_font_settings.font_family or '';
	cachedFontFlags = settings.name_font_settings.font_flags or 0;
	cachedOutlineWidth = settings.name_font_settings.outline_width or 2;

    -- Initialize all our font objects we need
    for i = 0, memberTextCount-1 do
        local partyIndex = math.ceil((i + 1) / partyMaxSize);
		local fontSizes = getFontSizes(partyIndex);

        local name_font_settings = deep_copy_table(settings.name_font_settings);
        local hp_font_settings = deep_copy_table(settings.hp_font_settings);
        local mp_font_settings = deep_copy_table(settings.mp_font_settings);
        local tp_font_settings = deep_copy_table(settings.tp_font_settings);
        local distance_font_settings = deep_copy_table(settings.name_font_settings);
        local zone_font_settings = deep_copy_table(settings.name_font_settings);

        name_font_settings.font_height = math.max(fontSizes.name, 6);
        hp_font_settings.font_height = math.max(fontSizes.hp, 6);
        mp_font_settings.font_height = math.max(fontSizes.mp, 6);
        tp_font_settings.font_height = math.max(fontSizes.tp, 6);
        distance_font_settings.font_height = math.max(fontSizes.name, 6);
        zone_font_settings.font_height = 10;  -- Fixed 10px for zone text

        memberText[i] = {};
        -- Use FontManager for cleaner font creation
        memberText[i].name = FontManager.create(name_font_settings);
        memberText[i].hp = FontManager.create(hp_font_settings);
        memberText[i].mp = FontManager.create(mp_font_settings);
        memberText[i].tp = FontManager.create(tp_font_settings);
        memberText[i].distance = FontManager.create(distance_font_settings);
        memberText[i].zone = FontManager.create(zone_font_settings);
        memberText[i].job = FontManager.create(name_font_settings);
    end

    -- Load party titles texture atlas
    partyTitlesTexture = LoadTexture('PartyList-Titles');
    if (partyTitlesTexture ~= nil) then
        -- Query actual texture dimensions using d3d8 library's interface
        local texture_ptr = ffi.cast('IDirect3DTexture8*', partyTitlesTexture.image);
        local res, desc = texture_ptr:GetLevelDesc(0);

        if (desc ~= nil) then
            partyTitlesTexture.width = desc.Width;
            partyTitlesTexture.height = desc.Height;
        else
            -- Fallback to reasonable default if query fails
            partyTitlesTexture.width = 64;
            partyTitlesTexture.height = 64;
            print('[XIUI] Warning: Failed to query party titles texture dimensions, using default 64x64');
        end
    end

    -- Initialize images
    loadedBg = nil;

    for i = 1, 3 do
        local backgroundPrim = {};

        for _, k in ipairs(bgImageKeys) do
            backgroundPrim[k] = primitives:new(settings.prim_data);
            backgroundPrim[k].visible = false;
            backgroundPrim[k].can_focus = false;
            backgroundPrim[k].exists = false;
        end

        partyWindowPrim[i].background = backgroundPrim;
    end

    -- PERFORMANCE: Force initial reference height calculation now that fonts exist
    -- This must happen before UpdateVisuals since it won't detect "changes" on first load
    for partyIndex = 1, 3 do
        local firstMemberIdx = (partyIndex - 1) * partyMaxSize;
        if memberText[firstMemberIdx] ~= nil then
            local refHeights = partyRefHeights[partyIndex];

            -- Calculate numeric reference height (for HP/MP/TP)
            local numericRefString = "0123456789";
            memberText[firstMemberIdx].hp:set_text(numericRefString);
            local _, hpRefH = memberText[firstMemberIdx].hp:get_text_size();
            refHeights.hpRefHeight = hpRefH;
            memberText[firstMemberIdx].hp:set_text('');

            memberText[firstMemberIdx].mp:set_text(numericRefString);
            local _, mpRefH = memberText[firstMemberIdx].mp:get_text_size();
            refHeights.mpRefHeight = mpRefH;
            memberText[firstMemberIdx].mp:set_text('');

            memberText[firstMemberIdx].tp:set_text(numericRefString);
            local _, tpRefH = memberText[firstMemberIdx].tp:get_text_size();
            refHeights.tpRefHeight = tpRefH;
            memberText[firstMemberIdx].tp:set_text('');

            -- Calculate text reference height (for names)
            local textRefString = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
            memberText[firstMemberIdx].name:set_text(textRefString);
            local _, nameRefH = memberText[firstMemberIdx].name:get_text_size();
            refHeights.nameRefHeight = nameRefH;
            memberText[firstMemberIdx].name:set_text('');
        end
    end
    partyRefHeightsValid = true;

    -- Load cursor textures (handled in UpdateVisuals)
    partyList.UpdateVisuals(settings);
end

partyList.UpdateVisuals = function(settings)
    -- PERFORMANCE: Refresh config cache (needed for getFontSizes calls below)
    partyConfigCacheValid = false;
    updatePartyConfigCache();

    -- Check if font family, flags (weight), or outline width changed - if so, recreate ALL fonts
    local fontFamilyChanged = false;
    local fontFlagsChanged = false;
    local outlineWidthChanged = false;

    if settings.name_font_settings.font_family ~= cachedFontFamily then
        fontFamilyChanged = true;
        cachedFontFamily = settings.name_font_settings.font_family;
    end

    if settings.name_font_settings.font_flags ~= cachedFontFlags then
        fontFlagsChanged = true;
        cachedFontFlags = settings.name_font_settings.font_flags;
    end

    if settings.name_font_settings.outline_width ~= cachedOutlineWidth then
        outlineWidthChanged = true;
        cachedOutlineWidth = settings.name_font_settings.outline_width;
    end

    -- Check which party font sizes changed
    local sizesChanged = {false, false, false};
    for partyIndex = 1, 3 do
        if settings.fontSizes[partyIndex] ~= cachedFontSizes[partyIndex] then
            sizesChanged[partyIndex] = true;
            cachedFontSizes[partyIndex] = settings.fontSizes[partyIndex];
        end
    end

    -- If font family, weight, or outline width changed, mark all parties as needing recreation
    if fontFamilyChanged or fontFlagsChanged or outlineWidthChanged then
        sizesChanged = {true, true, true};
    end

    -- Only recreate fonts for members of parties whose size changed
    for i = 0, memberTextCount-1 do
        local partyIndex = math.ceil((i + 1) / partyMaxSize);

        -- Skip if this party's size didn't change
        if not sizesChanged[partyIndex] then
            goto continue
        end

		local fontSizes = getFontSizes(partyIndex);

        -- Create font settings with proper height
        local name_font_settings = deep_copy_table(settings.name_font_settings);
        local hp_font_settings = deep_copy_table(settings.hp_font_settings);
        local mp_font_settings = deep_copy_table(settings.mp_font_settings);
        local tp_font_settings = deep_copy_table(settings.tp_font_settings);
        local distance_font_settings = deep_copy_table(settings.name_font_settings);
        local zone_font_settings = deep_copy_table(settings.name_font_settings);

        name_font_settings.font_height = math.max(fontSizes.name, 6);
        hp_font_settings.font_height = math.max(fontSizes.hp, 6);
        mp_font_settings.font_height = math.max(fontSizes.mp, 6);
        tp_font_settings.font_height = math.max(fontSizes.tp, 6);
        distance_font_settings.font_height = math.max(fontSizes.name, 6);
        zone_font_settings.font_height = 10;  -- Fixed 10px for zone text

        -- Use FontManager for cleaner font recreation
        if (memberText[i] ~= nil) then
            memberText[i].name = FontManager.recreate(memberText[i].name, name_font_settings);
            memberText[i].hp = FontManager.recreate(memberText[i].hp, hp_font_settings);
            memberText[i].mp = FontManager.recreate(memberText[i].mp, mp_font_settings);
            memberText[i].tp = FontManager.recreate(memberText[i].tp, tp_font_settings);
            memberText[i].distance = FontManager.recreate(memberText[i].distance, distance_font_settings);
            memberText[i].zone = FontManager.recreate(memberText[i].zone, zone_font_settings);
            memberText[i].job = FontManager.recreate(memberText[i].job, name_font_settings);
        end

        ::continue::
    end

    -- PERFORMANCE: Pre-calculate reference heights when fonts change
    -- This avoids expensive set_text/get_text_size calls during drawing
    if fontFamilyChanged or fontFlagsChanged or outlineWidthChanged or sizesChanged[1] or sizesChanged[2] or sizesChanged[3] then
        referenceTextHeights = {};
        partyRefHeightsValid = false;

        -- Pre-calculate reference heights for each party
        for partyIndex = 1, 3 do
            if sizesChanged[partyIndex] or fontFamilyChanged or fontFlagsChanged or outlineWidthChanged then
                local firstMemberIdx = (partyIndex - 1) * partyMaxSize;

                -- Only calculate if we have font objects for this party
                if memberText[firstMemberIdx] ~= nil then
                    local refHeights = partyRefHeights[partyIndex];

                    -- Calculate numeric reference height (for HP/MP/TP)
                    local numericRefString = "0123456789";
                    local originalText = memberText[firstMemberIdx].hp.settings.text;
                    memberText[firstMemberIdx].hp:set_text(numericRefString);
                    local _, hpRefH = memberText[firstMemberIdx].hp:get_text_size();
                    refHeights.hpRefHeight = hpRefH;
                    memberText[firstMemberIdx].hp:set_text(originalText or '');

                    originalText = memberText[firstMemberIdx].mp.settings.text;
                    memberText[firstMemberIdx].mp:set_text(numericRefString);
                    local _, mpRefH = memberText[firstMemberIdx].mp:get_text_size();
                    refHeights.mpRefHeight = mpRefH;
                    memberText[firstMemberIdx].mp:set_text(originalText or '');

                    originalText = memberText[firstMemberIdx].tp.settings.text;
                    memberText[firstMemberIdx].tp:set_text(numericRefString);
                    local _, tpRefH = memberText[firstMemberIdx].tp:get_text_size();
                    refHeights.tpRefHeight = tpRefH;
                    memberText[firstMemberIdx].tp:set_text(originalText or '');

                    -- Calculate text reference height (for names)
                    local textRefString = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
                    originalText = memberText[firstMemberIdx].name.settings.text;
                    memberText[firstMemberIdx].name:set_text(textRefString);
                    local _, nameRefH = memberText[firstMemberIdx].name:get_text_size();
                    refHeights.nameRefHeight = nameRefH;
                    memberText[firstMemberIdx].name:set_text(originalText or '');
                end
            end
        end

        partyRefHeightsValid = true;
    end

    -- Reset cached colors for parties that changed
    for partyIndex = 1, 3 do
        if sizesChanged[partyIndex] then
            for i = (partyIndex - 1) * partyMaxSize, (partyIndex * partyMaxSize) - 1 do
                memberTextColorCache[i] = nil;
            end
        end
    end

    -- Update images
    local bgChanged = gConfig.partyListBackgroundName ~= loadedBg;
    loadedBg = gConfig.partyListBackgroundName;

    for i = 1, 3 do
        local backgroundPrim = partyWindowPrim[i].background;

        for _, k in ipairs(bgImageKeys) do
            local file_name = string.format('%s-%s.png', gConfig.partyListBackgroundName, k);
            -- Note: colors are now applied every frame in DrawPartyWindow for real-time updates
            if (bgChanged) then
                -- Keep width/height to prevent flicker when switching to new texture
                local width, height = backgroundPrim[k].width, backgroundPrim[k].height;
                local filepath = string.format('%s/assets/backgrounds/%s', addon.path, file_name);
                backgroundPrim[k].texture = filepath;
                backgroundPrim[k].width, backgroundPrim[k].height = width, height;

                backgroundPrim[k].exists = ashita.fs.exists(filepath);
            end
            -- Only scale the main background, not the borders
            if k == 'bg' then
                backgroundPrim[k].scale_x = gConfig.partyListBgScale;
                backgroundPrim[k].scale_y = gConfig.partyListBgScale;
            else
                backgroundPrim[k].scale_x = 1.0;
                backgroundPrim[k].scale_y = 1.0;
            end
        end
    end

    -- Load cursor texture (like job icons)
    if (gConfig.partyListCursor ~= currentCursorName) then
        -- Cursor changed, clear cache and load new texture
        cursorTextures = T{};
        currentCursorName = gConfig.partyListCursor;

        if (gConfig.partyListCursor ~= nil and gConfig.partyListCursor ~= '') then
            local cursorTexture = LoadTexture(string.format('cursors/%s', gConfig.partyListCursor:gsub('%.png$', '')));
            if (cursorTexture ~= nil) then
                -- Query actual texture dimensions using d3d8 library's interface
                local texture_ptr = ffi.cast('IDirect3DTexture8*', cursorTexture.image);
                local res, desc = texture_ptr:GetLevelDesc(0);

                if (desc ~= nil) then
                    cursorTexture.width = desc.Width;
                    cursorTexture.height = desc.Height;
                else
                    -- Fallback to reasonable default if query fails
                    cursorTexture.width = 32;
                    cursorTexture.height = 32;
                    print(string.format('[XIUI] Warning: Failed to query cursor texture dimensions for %s, using default 32x32', gConfig.partyListCursor));
                end

                cursorTextures[gConfig.partyListCursor] = cursorTexture;
            end
        end
    end
end

partyList.SetHidden = function(hidden)
	if (hidden == true) then
        UpdateTextVisibility(false);
        -- Cursor is now drawn directly in DrawMember, no visibility flag needed
	end
end

partyList.HandleZonePacket = function(e)
    statusHandler.clear_cache();
    -- Clear all party casts when zoning
    partyList.partyCasts = {};
end

partyList.Cleanup = function()
	-- Use FontManager for cleaner font destruction
	for i = 0, memberTextCount - 1 do
		if (memberText[i] ~= nil) then
			memberText[i].name = FontManager.destroy(memberText[i].name);
			memberText[i].hp = FontManager.destroy(memberText[i].hp);
			memberText[i].mp = FontManager.destroy(memberText[i].mp);
			memberText[i].tp = FontManager.destroy(memberText[i].tp);
			memberText[i].distance = FontManager.destroy(memberText[i].distance);
			memberText[i].zone = FontManager.destroy(memberText[i].zone);
			memberText[i].job = FontManager.destroy(memberText[i].job);
		end
	end

	-- Clear party titles texture (GC'd automatically via gc_safe_release)
	partyTitlesTexture = nil;

	-- Clear cursor texture cache (textures are GC'd automatically via gc_safe_release)
	cursorTextures = T{};
	currentCursorName = nil;

	-- Destroy party window primitives
	for i = 1, 3 do
		if (partyWindowPrim[i] ~= nil) then
			if (partyWindowPrim[i].background ~= nil) then
				for _, k in ipairs(bgImageKeys) do
					if (partyWindowPrim[i].background[k] ~= nil) then
						partyWindowPrim[i].background[k]:destroy();
					end
				end
			end
		end
	end

	-- Clear tables
	memberText = {};
	partyWindowPrim = {{background = {}}, {background = {}}, {background = {}}};
end

partyList.HandleActionPacket = function(actionPacket)
	if (actionPacket == nil or actionPacket.UserId == nil) then
		return;
	end

	-- Type 8 = Magic (Start) - Party member begins casting
	if (actionPacket.Type == 8) then
		-- Get the spell ID from the action
		if (actionPacket.Targets and #actionPacket.Targets > 0 and
		    actionPacket.Targets[1].Actions and #actionPacket.Targets[1].Actions > 0) then
			local spellId = actionPacket.Targets[1].Actions[1].Param;
			local existingCast = partyList.partyCasts[actionPacket.UserId];

			-- According to XiPackets: interrupted casts send ANOTHER Type 8 with "sp" prefix (vs "ca" for normal start)
			-- If we already have an active cast for THE SAME spell, this is likely the interruption packet
			if (existingCast ~= nil and existingCast.spellId == spellId) then
				-- Second Type 8 for same spell = interruption signal, clear the cast
				partyList.partyCasts[actionPacket.UserId] = nil;
				return; -- Don't create new cast data
			end

			-- If we have a cast for a DIFFERENT spell, clear it (new cast started)
			if (existingCast ~= nil and existingCast.spellId ~= spellId) then
				partyList.partyCasts[actionPacket.UserId] = nil;
			end

			-- Create new cast data (first Type 8 for this spell)
			local spell = AshitaCore:GetResourceManager():GetSpellById(spellId);
			if (spell ~= nil and spell.Name[1] ~= nil) then
				local spellName = encoding:ShiftJIS_To_UTF8(spell.Name[1], true);
				-- Cast time is in quarter seconds (e.g., 40 = 10 seconds)
				local castTime = spell.CastTime / 4.0;

				partyList.partyCasts[actionPacket.UserId] = T{
					spellName = spellName,
					spellId = spellId,
					castTime = castTime,
					startTime = os.clock(),  -- High precision timestamp
					timestamp = os.time()    -- For cleanup
				};
			end
		end
	-- Type 4 = Magic (Finish) - Cast completed
	-- Type 11 = Monster Skill (Finish) - Some abilities
	elseif (actionPacket.Type == 4 or actionPacket.Type == 11) then
		-- Clear the cast for this party member
		partyList.partyCasts[actionPacket.UserId] = nil;
	end

	-- Cleanup stale casts (older than 30 seconds)
	local now = os.time();
	for serverId, data in pairs(partyList.partyCasts) do
		if (data.timestamp + 30 < now) then
			partyList.partyCasts[serverId] = nil;
		end
	end
end

return partyList;