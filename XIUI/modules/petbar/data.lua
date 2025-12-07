--[[
* XIUI Pet Bar - Data Module
* Handles state, caches, font objects, primitives, and helper functions
]]--

require('common');
require('handlers.helpers');

local data = {};

-- ============================================
-- Constants
-- ============================================
data.PADDING = 8;
data.JOB_SMN = 15;
data.JOB_BST = 9;
data.JOB_DRG = 14;
data.JOB_PUP = 18;

data.MAX_ABILITY_ICONS = 6;
data.ABILITY_ICON_SIZE = 24;

data.bgImageKeys = { 'bg', 'tl', 'tr', 'br', 'bl' };

-- Pet name to image file mapping
-- Maps in-game pet names to their image file paths
data.petImageMap = {
    -- Avatars
    ['Carbuncle'] = 'avatars/carbuncle.png',
    ['Ifrit'] = 'avatars/ifrit.png',
    ['Shiva'] = 'avatars/shiva.png',
    ['Garuda'] = 'avatars/garuda.png',
    ['Titan'] = 'avatars/titan.png',
    ['Ramuh'] = 'avatars/ramuh.png',
    ['Leviathan'] = 'avatars/leviathan.png',
    ['Fenrir'] = 'avatars/fenrir.png',
    ['Diabolos'] = 'avatars/diabolos.png',
    ['Atomos'] = 'avatars/atomos.png',
    ['Odin'] = 'avatars/odin.png',
    ['Alexander'] = 'avatars/alexander.png',
    ['Cait Sith'] = 'avatars/caitsith.png',
    ['Siren'] = 'avatars/siren.png',
    -- Spirits
    ['Fire Spirit'] = 'spirits/firespirit.png',
    ['Ice Spirit'] = 'spirits/icespirit.png',
    ['Air Spirit'] = 'spirits/windspirit.png',
    ['Earth Spirit'] = 'spirits/earthspirit.png',
    ['Thunder Spirit'] = 'spirits/thunderspirit.png',
    ['Water Spirit'] = 'spirits/waterspirit.png',
    ['Light Spirit'] = 'spirits/lightspirit.png',
    ['Dark Spirit'] = 'spirits/darkspirit.png',
};

-- Ordered list of avatars for config dropdown
data.avatarList = {
    'Carbuncle', 'Ifrit', 'Shiva', 'Garuda', 'Titan', 'Ramuh',
    'Leviathan', 'Fenrir', 'Diabolos', 'Atomos', 'Odin', 'Alexander',
    'Cait Sith', 'Siren',
    'Fire Spirit', 'Ice Spirit', 'Air Spirit', 'Earth Spirit',
    'Thunder Spirit', 'Water Spirit', 'Light Spirit', 'Dark Spirit',
};

-- Get settings key for a pet name (converts to lowercase, removes spaces)
function data.GetPetSettingsKey(petName)
    if petName == nil then return nil; end
    return petName:lower():gsub(' ', '');
end

-- Get the image path for a pet by name
function data.GetPetImagePath(petName)
    if petName == nil then return nil; end
    local imageFile = data.petImageMap[petName];
    if imageFile then
        return string.format('%s/assets/pets/%s', addon.path, imageFile);
    end
    return nil;
end

-- ============================================
-- State Variables
-- ============================================

-- Font objects
data.nameText = nil;
data.distanceText = nil;
data.hpText = nil;
data.mpText = nil;
data.tpText = nil;
data.allFonts = nil;

-- Cached colors
data.lastNameColor = nil;
data.lastDistColor = nil;
data.lastHpColor = nil;
data.lastMpColor = nil;
data.lastTpColor = nil;

-- Pet target tracking (from packet data)
data.petTargetServerId = nil;

-- Current pet name (for image loading)
data.currentPetName = nil;

-- Background primitives
data.backgroundPrim = {};
data.loadedBgName = nil;

-- Pet image primitive (overlay on background)
data.petImagePrim = nil;

-- Pet image textures for ImGui rendering (used when clip mode enabled)
data.petImageTextures = {};

-- Clipped pet image render info (set by UpdateBackground, rendered by display)
data.clippedPetImageInfo = nil;

-- Ability timer tracking
data.abilityMaxTimers = {};

-- Window positioning (shared with pet target)
data.lastMainWindowPosX = 0;
data.lastMainWindowBottom = 0;
data.lastTotalRowWidth = 150;
data.lastWindowFlags = nil;
data.lastColorConfig = nil;
data.lastSettings = nil;

-- Cached window flags
local baseWindowFlags = nil;

-- ============================================
-- Helper Functions
-- ============================================

-- Get cached base window flags
function data.getBaseWindowFlags()
    if baseWindowFlags == nil then
        baseWindowFlags = bit.bor(
            ImGuiWindowFlags_NoDecoration,
            ImGuiWindowFlags_AlwaysAutoResize,
            ImGuiWindowFlags_NoFocusOnAppearing,
            ImGuiWindowFlags_NoNav,
            ImGuiWindowFlags_NoBackground,
            ImGuiWindowFlags_NoBringToFrontOnFocus,
            ImGuiWindowFlags_NoDocking
        );
    end
    return baseWindowFlags;
end

-- Get pet entity from player's pet target index
function data.GetPetEntity()
    local playerEntity = GetPlayerEntity();
    if playerEntity == nil or playerEntity.PetTargetIndex == 0 then
        return nil;
    end
    return GetEntity(playerEntity.PetTargetIndex);
end

-- Get entity by server ID
function data.GetEntityByServerId(sid)
    if sid == nil or sid == 0 then return nil; end
    for x = 0, 2303 do
        local ent = GetEntity(x);
        if ent ~= nil and ent.ServerId == sid then
            return ent;
        end
    end
    return nil;
end

-- Get primary pet job (main takes precedence)
function data.GetPetJob()
    local player = GetPlayerSafe();
    if player == nil then return nil; end

    local mainJob = player:GetMainJob();
    local subJob = player:GetSubJob();

    if mainJob == data.JOB_SMN or mainJob == data.JOB_BST or mainJob == data.JOB_DRG or mainJob == data.JOB_PUP then
        return mainJob;
    elseif subJob == data.JOB_SMN or subJob == data.JOB_BST or subJob == data.JOB_DRG or subJob == data.JOB_PUP then
        return subJob;
    end
    return nil;
end

-- Format timer from frames to readable string
function data.FormatTimer(frames)
    if frames <= 0 then return 'Ready'; end
    local seconds = frames / 60;
    if seconds >= 60 then
        local mins = math.floor(seconds / 60);
        local secs = math.floor(seconds % 60);
        return string.format('%d:%02d', mins, secs);
    else
        return string.format('%ds', math.floor(seconds));
    end
end

-- Get ability recast timers relevant to current job
function data.GetPetAbilityTimers()
    local timers = {};
    local recast = GetRecastSafe();
    if recast == nil then return timers; end

    local resMgr = AshitaCore:GetResourceManager();
    local petJob = data.GetPetJob();

    -- Loop through ability timers
    for i = 0, 31 do
        local timerId = recast:GetAbilityTimerId(i);
        local timer = recast:GetAbilityTimer(i);

        if timerId ~= 0 or i == 0 then
            local ability = resMgr:GetAbilityByTimerId(timerId);
            if ability ~= nil then
                local name = ability.Name[1];

                -- Filter to pet-related abilities based on job
                local isPetAbility = false;

                if petJob == data.JOB_SMN then
                    if name and (name:find('Blood Pact') or name == 'Astral Flow' or name == 'Apogee' or name == 'Mana Cede') then
                        isPetAbility = true;
                    end
                elseif petJob == data.JOB_BST then
                    if name and (name == 'Ready' or name == 'Sic' or name == 'Reward'
                        or name == 'Call Beast' or name == 'Bestial Loyalty' or name == 'Familiar') then
                        isPetAbility = true;
                    end
                elseif petJob == data.JOB_DRG then
                    if name and (name == 'Call Wyvern' or name == 'Spirit Link'
                        or name == 'Deep Breathing' or name == 'Spirit Surge' or name == 'Steady Wing') then
                        isPetAbility = true;
                    end
                elseif petJob == data.JOB_PUP then
                    if name and (name == 'Activate' or name == 'Repair' or name == 'Deus Ex Automata'
                        or name == 'Deploy' or name == 'Deactivate' or name == 'Retrieve') then
                        isPetAbility = true;
                    end
                end

                if isPetAbility then
                    -- Track the max timer when cooldown starts
                    if timer > 0 then
                        if data.abilityMaxTimers[name] == nil or timer > data.abilityMaxTimers[name] then
                            data.abilityMaxTimers[name] = timer;
                        end
                    elseif timer <= 0 then
                        -- Clear max timer when ability is ready (so next use can recalculate)
                        data.abilityMaxTimers[name] = nil;
                    end

                    table.insert(timers, {
                        name = name,
                        timer = timer,
                        maxTimer = data.abilityMaxTimers[name] or timer,
                        formatted = data.FormatTimer(timer),
                        isReady = timer <= 0,
                    });
                end
            end
        end
    end

    return timers;
end

-- ============================================
-- Background Primitive Helpers
-- ============================================

-- Hide all background primitives
function data.HideBackground()
    for _, k in ipairs(data.bgImageKeys) do
        if data.backgroundPrim[k] then
            data.backgroundPrim[k].visible = false;
        end
    end
    -- Hide all pet image primitives
    if data.petImagePrims then
        for _, prim in pairs(data.petImagePrims) do
            if prim then
                prim.visible = false;
            end
        end
    end
end

-- Update background primitives position and visibility
function data.UpdateBackground(x, y, width, height, settings)
    local bgPadding = settings.bgPadding or data.PADDING;
    local bgPaddingY = settings.bgPaddingY or data.PADDING;
    local bgWidth = width + (bgPadding * 2);
    local bgHeight = height + (bgPaddingY * 2);
    local bgScale = settings.bgScale or 1.0;
    local bgTheme = gConfig.petBarBackgroundTheme or 'Window1';
    local borderSize = settings.borderSize or 21;
    local bgOffset = settings.bgOffset or 1;

    -- Check if this is a Window theme (has borders)
    local isWindowTheme = bgTheme:match('^Window%d+$') ~= nil;

    -- Handle background based on theme
    if bgTheme == '-None-' then
        -- No background at all
        data.backgroundPrim.bg.visible = false;
        data.backgroundPrim.br.visible = false;
        data.backgroundPrim.tr.visible = false;
        data.backgroundPrim.tl.visible = false;
        data.backgroundPrim.bl.visible = false;
    else
        -- Main background (works for both 'Plain' and Window themes)
        data.backgroundPrim.bg.visible = data.backgroundPrim.bg.exists;
        data.backgroundPrim.bg.position_x = x - bgPadding;
        data.backgroundPrim.bg.position_y = y - bgPaddingY;
        data.backgroundPrim.bg.width = bgWidth / bgScale;
        data.backgroundPrim.bg.height = bgHeight / bgScale;
        -- Apply background color/tint and opacity
        local bgOpacity = gConfig.petBarBackgroundOpacity or 1.0;
        local bgColor = gConfig.colorCustomization and gConfig.colorCustomization.petBar and gConfig.colorCustomization.petBar.bgColor or 0xFFFFFFFF;
        -- Extract RGB from bgColor (ARGB format) and apply opacity
        local bgAlphaByte = math.floor(bgOpacity * 255);
        local bgRGB = bit.band(bgColor, 0x00FFFFFF);
        data.backgroundPrim.bg.color = bit.bor(bit.lshift(bgAlphaByte, 24), bgRGB);

        -- Show borders for Window themes
        if isWindowTheme then
            local borderBaseColor = gConfig.colorCustomization and gConfig.colorCustomization.petBar and gConfig.colorCustomization.petBar.borderColor or 0xFFFFFFFF;
            local borderOpacity = gConfig.petBarBorderOpacity or 1.0;
            -- Apply opacity to border color
            local borderAlphaByte = math.floor(borderOpacity * 255);
            local borderRGB = bit.band(borderBaseColor, 0x00FFFFFF);
            local borderColor = bit.bor(bit.lshift(borderAlphaByte, 24), borderRGB);

            -- Bottom-right corner
            data.backgroundPrim.br.visible = data.backgroundPrim.br.exists;
            data.backgroundPrim.br.position_x = data.backgroundPrim.bg.position_x + bgWidth - borderSize + bgOffset;
            data.backgroundPrim.br.position_y = data.backgroundPrim.bg.position_y + bgHeight - borderSize + bgOffset;
            data.backgroundPrim.br.width = borderSize;
            data.backgroundPrim.br.height = borderSize;
            data.backgroundPrim.br.color = borderColor;

            -- Top-right edge (from top to br)
            data.backgroundPrim.tr.visible = data.backgroundPrim.tr.exists;
            data.backgroundPrim.tr.position_x = data.backgroundPrim.br.position_x;
            data.backgroundPrim.tr.position_y = data.backgroundPrim.bg.position_y - bgOffset;
            data.backgroundPrim.tr.width = borderSize;
            data.backgroundPrim.tr.height = data.backgroundPrim.br.position_y - data.backgroundPrim.tr.position_y;
            data.backgroundPrim.tr.color = borderColor;

            -- Top-left (L-shaped: top and left edges)
            data.backgroundPrim.tl.visible = data.backgroundPrim.tl.exists;
            data.backgroundPrim.tl.position_x = data.backgroundPrim.bg.position_x - bgOffset;
            data.backgroundPrim.tl.position_y = data.backgroundPrim.bg.position_y - bgOffset;
            data.backgroundPrim.tl.width = data.backgroundPrim.tr.position_x - data.backgroundPrim.tl.position_x;
            data.backgroundPrim.tl.height = data.backgroundPrim.br.position_y - data.backgroundPrim.tl.position_y;
            data.backgroundPrim.tl.color = borderColor;

            -- Bottom-left edge (from left to br)
            data.backgroundPrim.bl.visible = data.backgroundPrim.bl.exists;
            data.backgroundPrim.bl.position_x = data.backgroundPrim.tl.position_x;
            data.backgroundPrim.bl.position_y = data.backgroundPrim.bg.position_y + bgHeight - borderSize + bgOffset;
            data.backgroundPrim.bl.width = data.backgroundPrim.br.position_x - data.backgroundPrim.bl.position_x;
            data.backgroundPrim.bl.height = borderSize;
            data.backgroundPrim.bl.color = borderColor;
        else
            -- Hide borders for Plain theme
            data.backgroundPrim.br.visible = false;
            data.backgroundPrim.tr.visible = false;
            data.backgroundPrim.tl.visible = false;
            data.backgroundPrim.bl.visible = false;
        end
    end

    -- Pet image overlay (show correct avatar based on current pet)
    -- Clear clipped image info
    data.clippedPetImageInfo = nil;

    -- First hide all pet image primitives
    if data.petImagePrims then
        for _, prim in pairs(data.petImagePrims) do
            if prim then
                prim.visible = false;
            end
        end
    end

    -- Show current pet's image if we have one and setting is enabled
    if gConfig.petBarShowImage and data.currentPetName and data.petImagePrims then
        local petKey = data.GetPetSettingsKey(data.currentPetName);
        local prim = data.petImagePrims[petKey];
        if prim and prim.exists then
            -- Get per-avatar settings, fall back to legacy global settings
            local avatarSettings = gConfig.petBarAvatarSettings and gConfig.petBarAvatarSettings[petKey];
            local petImageScale, petImageOpacity, petImageOffsetX, petImageOffsetY, clipToBackground;

            if avatarSettings then
                petImageScale = avatarSettings.scale or 0.4;
                petImageOpacity = avatarSettings.opacity or 0.3;
                petImageOffsetX = avatarSettings.offsetX or 0;
                petImageOffsetY = avatarSettings.offsetY or 0;
                clipToBackground = avatarSettings.clipToBackground or false;
            else
                -- Fall back to legacy global settings
                petImageScale = gConfig.petBarImageScale or 0.4;
                petImageOpacity = gConfig.petBarImageOpacity or 0.3;
                petImageOffsetX = gConfig.petBarImageOffsetX or 0;
                petImageOffsetY = gConfig.petBarImageOffsetY or 0;
                clipToBackground = false;
            end

            -- Calculate base image position and dimensions
            local imgX = x + petImageOffsetX;
            local imgY = y + petImageOffsetY;
            local baseWidth = prim.baseWidth or 256;
            local baseHeight = prim.baseHeight or 256;
            local imgWidth = baseWidth * petImageScale;
            local imgHeight = baseHeight * petImageScale;

            -- Convert 0-1 opacity to alpha byte (0x00-0xFF), keep RGB as white
            local alphaByte = math.floor(petImageOpacity * 255);
            local color = bit.bor(bit.lshift(alphaByte, 24), 0x00FFFFFF);

            if clipToBackground then
                -- Calculate background bounds including border area
                -- Background extends PADDING outside window, borders extend further based on bgOffset
                local clipBgPadding = settings.bgPadding or data.PADDING;
                local clipBgPaddingY = settings.bgPaddingY or data.PADDING;
                local bgTheme = gConfig.petBarBackgroundTheme or 'Window1';
                local isWindowTheme = bgTheme:match('^Window%d+$') ~= nil;
                local clipBgOffset = isWindowTheme and (settings.bgOffset or 1) or 0;

                -- When borders are visible, extend clip bounds to include border area
                local bgLeft = x - clipBgPadding - clipBgOffset;
                local bgTop = y - clipBgPaddingY - clipBgOffset;
                local bgRight = x + width + clipBgPadding + clipBgOffset;
                local bgBottom = y + height + clipBgPaddingY + clipBgOffset;

                -- Calculate intersection of image bounds with background bounds
                local imgRight = imgX + imgWidth;
                local imgBottom = imgY + imgHeight;

                local clipLeft = math.max(imgX, bgLeft);
                local clipTop = math.max(imgY, bgTop);
                local clipRight = math.min(imgRight, bgRight);
                local clipBottom = math.min(imgBottom, bgBottom);

                -- Check if there's any visible area
                if clipLeft < clipRight and clipTop < clipBottom then
                    -- Calculate texture offset in pixels (how much of the texture to skip)
                    local texOffsetX = (clipLeft - imgX) / petImageScale;
                    local texOffsetY = (clipTop - imgY) / petImageScale;

                    -- Calculate visible dimensions in texture pixels
                    local visibleWidth = (clipRight - clipLeft) / petImageScale;
                    local visibleHeight = (clipBottom - clipTop) / petImageScale;

                    prim.visible = true;
                    prim.position_x = clipLeft;
                    prim.position_y = clipTop;
                    prim.texture_offset_x = texOffsetX;
                    prim.texture_offset_y = texOffsetY;
                    prim.width = visibleWidth;
                    prim.height = visibleHeight;
                    prim.scale_x = petImageScale;
                    prim.scale_y = petImageScale;
                    prim.color = color;
                else
                    -- Image is completely outside background bounds
                    prim.visible = false;
                end
            else
                -- No clipping - show full image via primitive
                prim.visible = true;
                prim.position_x = imgX;
                prim.position_y = imgY;
                prim.texture_offset_x = 0;
                prim.texture_offset_y = 0;
                prim.width = baseWidth;
                prim.height = baseHeight;
                prim.scale_x = petImageScale;
                prim.scale_y = petImageScale;
                prim.color = color;
            end
        end
    end
end

-- ============================================
-- Font Visibility Helper
-- ============================================

function data.SetAllFontsVisible(visible)
    if data.allFonts then
        SetFontsVisible(data.allFonts, visible);
    end
end

-- ============================================
-- Clear Cached Colors
-- ============================================

function data.ClearColorCache()
    data.lastNameColor = nil;
    data.lastDistColor = nil;
    data.lastHpColor = nil;
    data.lastMpColor = nil;
    data.lastTpColor = nil;
end

-- ============================================
-- State Reset
-- ============================================

function data.Reset()
    data.nameText = nil;
    data.distanceText = nil;
    data.hpText = nil;
    data.mpText = nil;
    data.tpText = nil;
    data.allFonts = nil;
    data.backgroundPrim = {};
    data.petImagePrim = nil;
    data.petImageTextures = {};
    data.clippedPetImageInfo = nil;
    data.petTargetServerId = nil;
    data.currentPetName = nil;
    data.abilityMaxTimers = {};
    data.loadedBgName = nil;
    data.ClearColorCache();
end

return data;
