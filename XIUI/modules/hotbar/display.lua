--[[
* XIUI hotbar - Display Module
* Renders 6 independent hotbar windows with primitives and imtext
]]--

require('common');
require('handlers.helpers');
local ffi = require('ffi');
local imgui = require('imgui');
local windowBg = require('libs.windowbackground');
local drawing = require('libs.drawing');

local data = require('modules.hotbar.data');
local playerdata = require('modules.hotbar.playerdata');
local actions = require('modules.hotbar.actions');
local textures = require('modules.hotbar.textures');
local macropalette = require('modules.hotbar.macropalette');
local dragdrop = require('libs.dragdrop');
local recast = require('modules.hotbar.recast');
local slotrenderer = require('modules.hotbar.slotrenderer');
local hotbarConfig = require('config.hotbar');
local petpalette = require('modules.hotbar.petpalette');
local palette = require('modules.hotbar.palette');
local skillchain = require('modules.hotbar.skillchain');
local macroparse = require('modules.hotbar.macroparse');
local targetLib = require('libs.target');
local imtext = require('libs.imtext');
-- TextureManager.DeferRelease keeps a Lua ref to wiped iconCache entries alive
-- for one frame so palette-delete / job-change paths don't release a D3D texture
-- that's still queued in this frame's draw list (CTD on Ashita 4.16).
local TextureManager = require('libs.texturemanager');

local M = {};

-- ============================================
-- Constants
-- ============================================

local KEYBIND_OFFSET_X = 2;
local KEYBIND_OFFSET_Y = 2;

-- ============================================
-- State
-- ============================================

-- Textures initialized flag
local texturesInitialized = false;

-- Force position reset flag (set by ResetPositions, cleared after applying)
local forcePositionReset = false;

-- Icon cache per slot: iconCache[barIndex][slotIndex] = { bind = lastBind, icon = cachedIcon }
-- We compare the bind reference to detect changes
local iconCache = {};

-- ============================================
-- Palette Change Animation
-- ============================================

-- Animation state per bar
local paletteAnimation = {
    -- [barIndex] = { active, startTime, duration, phase }
};

local PALETTE_ANIM_DURATION = 0.25;  -- Total animation duration in seconds
local PALETTE_ANIM_FADE_OUT = 0.12;  -- Fade out phase duration

-- Easing function (ease out cubic)
local function EaseOutCubic(t)
    return 1 - math.pow(1 - t, 3);
end

-- Start palette change animation for a bar
local function StartPaletteAnimation(barIndex)
    paletteAnimation[barIndex] = {
        active = true,
        startTime = os.clock(),
        duration = PALETTE_ANIM_DURATION,
    };
end

-- Get animation opacity for a bar (1.0 = fully visible)
local function GetPaletteAnimationOpacity(barIndex)
    local anim = paletteAnimation[barIndex];
    if not anim or not anim.active then
        return 1.0;
    end

    local elapsed = os.clock() - anim.startTime;
    if elapsed >= anim.duration then
        anim.active = false;
        return 1.0;
    end

    -- Two-phase animation: fade out then fade in
    if elapsed < PALETTE_ANIM_FADE_OUT then
        -- Fade out phase
        local progress = elapsed / PALETTE_ANIM_FADE_OUT;
        return 1.0 - EaseOutCubic(progress) * 0.7;  -- Fade to 30% opacity
    else
        -- Fade in phase
        local fadeInElapsed = elapsed - PALETTE_ANIM_FADE_OUT;
        local fadeInDuration = anim.duration - PALETTE_ANIM_FADE_OUT;
        local progress = fadeInElapsed / fadeInDuration;
        return 0.3 + EaseOutCubic(progress) * 0.7;  -- Fade from 30% to 100%
    end
end

-- Callback registered with palette system
local function OnPaletteChanged(barIndex, oldPalette, newPalette)
    StartPaletteAnimation(barIndex);
end

-- Build a cache key that includes all fields that affect the icon
local function BuildBindKey(bind)
    if not bind then return 'nil'; end
    -- Include customIconType, customIconId, and customIconPath so icon changes invalidate the cache
    local iconPart = '';
    if bind.customIconType or bind.customIconId or bind.customIconPath then
        iconPart = ':icon:' .. (bind.customIconType or '') .. ':' .. tostring(bind.customIconId or '') .. ':' .. (bind.customIconPath or '');
    end
    -- Macros render a /ja badge overlay; its icon (whether resolved from a job-ability
    -- name in macroText or from a macro.jaBadgeCustom* override) must invalidate the
    -- cache when changed. Defensive guard: function lives in actions.lua (Phase 2.4).
    if bind.actionType == 'macro' and actions.GetMacroJaBadgeIconCacheSuffix then
        iconPart = iconPart .. (actions.GetMacroJaBadgeIconCacheSuffix(bind) or '');
    end
    return (bind.actionType or '') .. ':' .. (bind.action or '') .. ':' .. (bind.target or '') .. iconPart;
end

-- Get cached icon (and precomputed abbreviation) for a slot, recompute only if bind changed.
-- Returns: icon, abbr, abbrW. When the slot has an icon, abbr/abbrW are nil.
-- When the slot has no icon, abbr/abbrW are precomputed so DrawSlot doesn't have to
-- run GetActionAbbreviation + imtext.Measure per frame.
local function GetCachedIcon(barIndex, slotIndex, bind)
    if not iconCache[barIndex] then
        iconCache[barIndex] = {};
    end

    local cached = iconCache[barIndex][slotIndex];

    -- Check if we have a valid cache entry for this bind
    if cached then
        local bindKey = BuildBindKey(bind);
        if cached.bindKey == bindKey then
            -- Cache hit - return cached values (icon may be nil; that's a valid "no icon" memo)
            return cached.icon, cached.abbr, cached.abbrW;
        end
    end

    -- Cache miss - resolve icon only (BuildCommand also builds command strings; per-frame
    -- draw paths don't need the command, so we use GetBindIcon when available to skip that work).
    local icon = nil;
    if bind then
        if actions.GetBindIcon then
            icon = actions.GetBindIcon(bind);
        else
            _, icon = actions.BuildCommand(bind);
        end
    end

    local abbr, abbrW = nil, nil;
    if not icon and bind then
        abbr, abbrW = slotrenderer.ComputeAbbreviation(bind);
    end

    -- Store in cache
    local bindKey = BuildBindKey(bind);
    iconCache[barIndex][slotIndex] = {
        bindKey = bindKey,
        icon = icon,
        abbr = abbr,
        abbrW = abbrW,
    };

    return icon, abbr, abbrW;
end

-- Clear icon cache (call when slots change)
local function ClearIconCache()
    -- iconCache rows hold the only Lua ref to D3D textures loaded by actions.GetBindIcon
    -- (LoadTextureFromPath wires a gc_safe_release finalizer); dropping the table mid-frame
    -- lets Lua GC release the COM texture while AddImage queued earlier this frame still
    -- references its pointer. Hold the old table alive until next d3d_present flushes it.
    TextureManager.DeferRelease(iconCache);
    iconCache = {};
    -- Mirror the wipe to actions.lua's negative-result cache; otherwise a "no icon" decision
    -- pinned from a previous job/palette/macro state survives across cache invalidations.
    if actions.ClearNoIconCache then
        actions.ClearNoIconCache();
    end
end

-- Clear icon cache for a specific slot (call on targeted slot updates)
local function ClearIconCacheForSlot(barIndex, slotIndex)
    if iconCache[barIndex] then
        -- Per-slot wipes (drag/drop, single rebuild) need the same deferred-release
        -- guard as ClearIconCache so the slot's queued AddImage from earlier this frame
        -- doesn't end up dereferencing a freed COM texture.
        local oldRow = iconCache[barIndex][slotIndex];
        if oldRow ~= nil then
            TextureManager.DeferRelease(oldRow);
        end
        iconCache[barIndex][slotIndex] = nil;
    end
end

-- ============================================
-- Helper Functions
-- ============================================

-- Get default position for a bar
local function GetDefaultBarPosition(barIndex)
    local screenWidth = imgui.GetIO().DisplaySize.x or 1920;
    local screenHeight = imgui.GetIO().DisplaySize.y or 1080;

    -- Use per-bar settings for accurate dimensions
    local barSettings = data.GetBarSettings(barIndex);
    local slotSize = barSettings.slotSize or 32;
    local slotGap = barSettings.slotXPadding or data.BUTTON_GAP;
    local padding = data.PADDING;
    local layout = data.GetBarLayout(barIndex);

    -- All bars: stack vertically, centered horizontally
    -- Bar 1 at the bottom, bar 2 above it, etc.
    local barWidth = (slotSize * layout.columns) + (slotGap * (layout.columns - 1)) + (padding * 2);
    local barHeight = slotSize + (padding * 2);
    local x = (screenWidth - barWidth) / 2;
    local y = screenHeight - 120 - ((barIndex - 1) * (barHeight + 4));
    return x, y;
end

-- Calculate bar dimensions using per-bar settings
local function GetBarDimensions(barIndex)
    local barSettings = data.GetBarSettings(barIndex);
    local gs = (gConfig and gConfig.globalScale) or 1.0;
    local slotSize = (barSettings.slotSize or 32) * gs;
    -- Use per-bar slot padding settings
    local slotGap = (barSettings.slotXPadding or data.BUTTON_GAP) * gs;
    local padding = data.PADDING * gs;
    local rowGap = (barSettings.slotYPadding or data.ROW_GAP) * gs;

    local layout = data.GetBarLayout(barIndex);

    -- Calculate dimensions based on rows and columns
    local width = (slotSize * layout.columns) + (slotGap * (layout.columns - 1)) + (padding * 2);
    local height = (slotSize * layout.rows) + (rowGap * (layout.rows - 1)) + (padding * 2);

    return width, height, slotSize, slotGap, rowGap, layout;
end

-- Cached asset path
local assetsPath = nil;

local function GetAssetsPath()
    if not assetsPath then
        assetsPath = string.format('%saddons\\XIUI\\assets\\hotbar\\', AshitaCore:GetInstallPath());
    end
    return assetsPath;
end

-- Pre-allocated reusable table for DrawSlot
local slotParams = {};
local HOTBAR_DROP_ACCEPTS = {'macro', 'slot', 'crossbar_slot'};

-- Pre-created closures and string IDs per slot (avoids ~288 closure + 72 array allocations per frame)
local slotInteraction = {};

local function GetSlotInteraction(barIndex, slotIndex)
    if not slotInteraction[barIndex] then
        slotInteraction[barIndex] = {};
    end
    if not slotInteraction[barIndex][slotIndex] then
        slotInteraction[barIndex][slotIndex] = {
            buttonId = string.format('##hotbarslot_%d_%d', barIndex, slotIndex),
            dropZoneId = string.format('hotbar_%d_%d', barIndex, slotIndex),
            onDrop = function(payload)
                macropalette.HandleDropOnSlot(payload, barIndex, slotIndex);
            end,
            getDragData = function()
                local b = data.GetKeybindForSlot(barIndex, slotIndex);
                macropalette.StartDragSlot(barIndex, slotIndex, b);
                return nil;  -- StartDragSlot handles the drag itself
            end,
            onRightClick = function()
                macropalette.ClearSlot(barIndex, slotIndex);
            end,
        };
    end
    return slotInteraction[barIndex][slotIndex];
end

-- Draw a single hotbar slot using shared renderer
local function DrawSlot(barIndex, slotIndex, x, y, buttonSize, bind, barSettings, animOpacity, skillchainName, magicBurstName)
    -- Get icon (and pre-resolved abbreviation, if no icon) for this slot.
    -- All three are cached together; recomputed only when bind changes.
    local icon, cachedAbbr, cachedAbbrW = GetCachedIcon(barIndex, slotIndex, bind);

    -- Check if this slot is currently pressed (keyboard)
    local pressedHotbar = actions.GetPressedHotbar();
    local pressedSlot = actions.GetPressedSlot();

    -- Get pre-created interaction closures and IDs
    local interaction = GetSlotInteraction(barIndex, slotIndex);

    -- Global UI scale (applied to font sizes and pixel offsets that aren't
    -- already pre-scaled via GetBarDimensions). Position/size args (x, y,
    -- buttonSize) come in already scaled by the caller.
    local gs = (gConfig and gConfig.globalScale) or 1.0;

    -- Update reusable params table in-place
    local p = slotParams;
    -- Position/Size
    p.x = x;
    p.y = y;
    p.size = buttonSize;
    -- Action Data
    p.bind = bind;
    p.icon = icon;
    p.cachedAbbr = cachedAbbr;
    p.cachedAbbrW = cachedAbbrW;
    -- Visual Settings
    p.slotBgColor = barSettings and barSettings.slotBackgroundColor or 0xFFFFFFFF;
    p.slotOpacity = barSettings and barSettings.slotOpacity or 1.0;
    p.keybindText = (barSettings and barSettings.showKeybinds ~= false) and data.GetKeybindDisplay(barIndex, slotIndex) or nil;
    p.keybindFontSize = (barSettings and barSettings.keybindFontSize or 10) * gs;
    p.keybindFontColor = barSettings and barSettings.keybindFontColor or 0xFFFFFFFF;
    p.keybindAnchor = barSettings and barSettings.keybindAnchor or 'topLeft';
    p.keybindOffsetX = (barSettings and barSettings.keybindOffsetX or 0) * gs;
    p.keybindOffsetY = (barSettings and barSettings.keybindOffsetY or 0) * gs;
    p.showLabel = barSettings and barSettings.showActionLabels or false;
    p.labelText = bind and (bind.displayName or bind.action or '') or '';
    p.labelOffsetX = (barSettings and barSettings.actionLabelOffsetX or 0) * gs;
    p.labelOffsetY = ((barSettings and barSettings.actionLabelOffsetY or 0) + data.LABEL_GAP) * gs;
    p.labelFontSize = (barSettings and barSettings.labelFontSize or 10) * gs;
    p.recastTimerFontSize = (barSettings and barSettings.recastTimerFontSize or 11) * gs;
    p.recastTimerFontColor = barSettings and barSettings.recastTimerFontColor or 0xFFFFFFFF;
    p.flashCooldownUnder5 = barSettings and barSettings.flashCooldownUnder5 or false;
    p.useHHMMCooldownFormat = barSettings and barSettings.useHHMMCooldownFormat or false;
    p.labelFontColor = barSettings and barSettings.labelFontColor or 0xFFFFFFFF;
    p.labelCooldownColor = barSettings and barSettings.labelCooldownColor or 0xFF888888;
    p.labelNoMpColor = barSettings and barSettings.labelNoMpColor or 0xFFFF4444;
    p.showFrame = barSettings and barSettings.showSlotFrame or false;
    p.customFramePath = barSettings and barSettings.customFramePath or '';
    p.isPressed = (pressedHotbar == barIndex and pressedSlot == slotIndex);
    p.showMpCost = barSettings and barSettings.showMpCost ~= false;
    p.mpCostFontSize = (barSettings and barSettings.mpCostFontSize or 10) * gs;
    p.mpCostFontColor = barSettings and barSettings.mpCostFontColor or 0xFFD4FF97;
    p.mpCostNoMpColor = barSettings and barSettings.labelNoMpColor or 0xFFFF4444;
    p.mpCostAnchor = barSettings and barSettings.mpCostAnchor or 'topLeft';
    p.mpCostOffsetX = (barSettings and barSettings.mpCostOffsetX or 0) * gs;
    p.mpCostOffsetY = (barSettings and barSettings.mpCostOffsetY or 0) * gs;
    p.showQuantity = barSettings and barSettings.showQuantity ~= false;
    p.showStackQuantity = barSettings and barSettings.showStackQuantity == true;
    p.quantityFontSize = (barSettings and barSettings.quantityFontSize or 10) * gs;
    p.quantityFontColor = barSettings and barSettings.quantityFontColor or 0xFFFFFFFF;
    p.quantityAnchor = barSettings and barSettings.quantityAnchor or 'bottomRight';
    p.quantityOffsetX = (barSettings and barSettings.quantityOffsetX or 0) * gs;
    p.quantityOffsetY = (barSettings and barSettings.quantityOffsetY or 0) * gs;
    -- Interaction Config
    p.buttonId = interaction.buttonId;
    p.dropZoneId = interaction.dropZoneId;
    p.dropAccepts = HOTBAR_DROP_ACCEPTS;
    p.onDrop = interaction.onDrop;
    p.dragType = 'slot';
    p.getDragData = interaction.getDragData;
    p.onRightClick = interaction.onRightClick;
    p.showTooltip = true;
    -- Animation
    p.animOpacity = animOpacity or 1.0;
    -- Skillchain highlight
    p.skillchainName = skillchainName;
    p.skillchainColor = gConfig.hotbarGlobal.skillchainHighlightColor or 0xFFD4AA44;
    -- Magic Burst highlight (separate from skillchain — different SC->element predictor,
    -- different color, different corner icon). Resolved upstream in the per-slot loop so
    -- this just plumbs the name/color through to slotrenderer.
    p.magicBurstName = magicBurstName;
    p.magicBurstColor = gConfig.hotbarGlobal.magicBurstHighlightColor or 0xFF44D4FF;

    -- Render slot using shared renderer (handles ALL rendering and interactions)
    local result = slotrenderer.DrawSlot(p);
    return result.isHovered;
end

-- Draw a single hotbar window
local function DrawBarWindow(barIndex, settings)
    -- Get per-bar settings
    local barSettings = data.GetBarSettings(barIndex);

    -- Check if bar is enabled
    if not barSettings.enabled then
        return;
    end

    -- Get default position for fallback
    local defaultX, defaultY = GetDefaultBarPosition(barIndex);
    local windowName = string.format('Hotbar%d', barIndex);

    -- Apply saved position if exists (using helper for profile support), otherwise set default
    local hasSaved = gConfig.windowPositions and gConfig.windowPositions[windowName];

    if hasSaved then
        ApplyWindowPosition(windowName);
    else
        imgui.SetNextWindowPos({defaultX, defaultY}, ImGuiCond_FirstUseEver);
    end

    -- Get dimensions (now includes layout)
    local barWidth, barHeight, buttonSize, buttonGap, rowGap, layout = GetBarDimensions(barIndex);

    local slotCount = layout.slots;

    -- Window flags (dummy window for positioning)
    local windowFlags = GetBaseWindowFlags(gConfig.lockPositions);

    -- Check if anchor is currently being dragged or positions are being reset - if so, force position
    local anchorDragging = drawing.IsAnchorDragging(windowName);
    
    if anchorDragging or forcePositionReset then
        -- Force position update during drag
        local saved = gConfig.windowPositions and gConfig.windowPositions[windowName];
        local targetX = saved and saved.x or defaultX;
        local targetY = saved and saved.y or defaultY;
        imgui.SetNextWindowPos({targetX, targetY}, ImGuiCond_Always);
    end

    imgui.SetNextWindowSize({barWidth, barHeight}, ImGuiCond_Always);

    local windowPosX, windowPosY;

    if imgui.Begin(windowName, true, windowFlags) then
        -- Save position if moved
        SaveWindowPosition(windowName);
        windowPosX, windowPosY = imgui.GetWindowPos();

        -- Reserve space
        imgui.Dummy({barWidth, barHeight});

        -- Update background using per-bar settings
        local bgTheme = barSettings.backgroundTheme or '-None-';
        local bgScale = barSettings.bgScale or 1.0;
        local borderScale = barSettings.borderScale or 1.0;
        local bgOpacity = barSettings.backgroundOpacity or 0.87;
        local borderOpacity = barSettings.borderOpacity or 1.0;

        -- Use per-bar color settings
        local bgColor = barSettings.bgColor or 0xFFFFFFFF;
        local borderColor = barSettings.borderColor or 0xFFFFFFFF;

        local bgOptions = {
            theme = bgTheme,
            padding = 0,  -- Padding already included in barWidth/barHeight
            paddingY = 0,
            bgScale = bgScale,
            borderScale = borderScale,
            bgOpacity = bgOpacity,
            borderOpacity = borderOpacity,
            bgColor = bgColor,
            borderColor = borderColor,
        };

        windowBg.Draw(GetUIDrawList(), windowPosX, windowPosY, barWidth, barHeight, bgOptions);

        -- Draw hotbar number to the LEFT of the bar (outside container)
        local showNumber = barSettings.showHotbarNumber;
        if showNumber == nil then showNumber = true; end
        if showNumber then
            -- Position to the left of the bar with optional offsets
            local hbnOffsetX = barSettings.hotbarNumberOffsetX or 0;
            local hbnOffsetY = barSettings.hotbarNumberOffsetY or 0;
            local hbnText = tostring(barIndex);
            local hbnX = windowPosX - 16 + hbnOffsetX;
            local hbnY = windowPosY + (barHeight / 2) - 6 + hbnOffsetY;
            local hbnDrawList = GetUIDrawList();
            if hbnDrawList then
                imtext.Draw(hbnDrawList, hbnText, hbnX, hbnY, 0xFFFFFFFF, 12);
            end
        end

        -- Draw slots based on layout (rows x columns)
        local gs = (gConfig and gConfig.globalScale) or 1.0;
        local padding = data.PADDING * gs;
        local slotCount = layout.slots;
        local slotIndex = 1;

        -- Get palette change animation opacity
        local animOpacity = GetPaletteAnimationOpacity(barIndex);

        -- Check if we should hide empty slots
        local hideEmptySlots = barSettings.hideEmptySlots or false;
        local paletteOpen = macropalette.IsPaletteOpen();
        local keybindEditorOpen = hotbarConfig.IsKeybindModalOpen();
        -- Use both IsDragging and IsDragPending to show empty slots during entire drag process
        -- IsDragging only returns true after drag threshold is met, but we need to show
        -- drop zones earlier so they're registered when the drag activates
        local isDragging = dragdrop.IsDragging() or dragdrop.IsDragPending();

        -- Get target server ID for skillchain / magic burst prediction (cached for all slots).
        -- Both features key off the same target so we resolve once per frame here and reuse
        -- the cached server ID inside the per-slot loop. Either feature being disabled is
        -- fine: the resolver still returns the ID, and the per-slot path early-exits below.
        local targetServerId = nil;
        local skillchainEnabled = gConfig.hotbarGlobal.skillchainHighlightEnabled ~= false;
        local magicBurstEnabled = gConfig.hotbarGlobal.magicBurstHighlightEnabled ~= false;
        if skillchainEnabled or magicBurstEnabled then
            local mainTargetIdx = targetLib.GetTargets();
            if mainTargetIdx and mainTargetIdx ~= 0 then
                local targetEntity = GetEntity(mainTargetIdx);
                if targetEntity then
                    targetServerId = targetEntity.ServerId;
                end
            end
        end

        for row = 1, layout.rows do
            for col = 1, layout.columns do
                if slotIndex <= slotCount then
                    local slotX = windowPosX + padding + (col - 1) * (buttonSize + buttonGap);
                    local slotY = windowPosY + padding + (row - 1) * (buttonSize + rowGap);

                    local bind = data.GetKeybindForSlot(barIndex, slotIndex);

                    -- Hide empty slots if setting enabled and not editing/dragging
                    if hideEmptySlots and not paletteOpen and not keybindEditorOpen and not isDragging and not bind then
                        -- Empty slot: skip rendering (ImGui draws are stateless, nothing to hide)
                    else
                        -- Skillchain prediction: WS slots, Blood Pact slots, and macros whose
                        -- primary line is /ws or /pet (parsed via macroparse).
                        local slotSkillchainName = nil;
                        if skillchainEnabled and bind then
                            if bind.actionType == 'ws' and bind.action then
                                slotSkillchainName = skillchain.GetSkillchainForSlot(targetServerId, bind.action);
                            elseif bind.actionType == 'pet' and bind.action then
                                slotSkillchainName = skillchain.GetSkillchainForBloodPact(targetServerId, bind.action);
                            elseif bind.actionType == 'macro' and bind.macroText then
                                local primaryType, primaryName = macroparse.GetMacroPrimaryAndJaBadge(bind.macroText);
                                if primaryType == 'ws' and primaryName then
                                    slotSkillchainName = skillchain.GetSkillchainForSlot(targetServerId, primaryName);
                                elseif primaryType == 'pet' and primaryName then
                                    slotSkillchainName = skillchain.GetSkillchainForBloodPact(targetServerId, primaryName);
                                end
                            end
                        end
                        -- Magic Burst prediction: spells (/ma), magical pact rages (/pet curated
                        -- map), and /ma|/pet-primary macros. Routes via skillchain.GetMagicBurstForSlot
                        -- so the dispatch matches the skillchain pass above; the lookup is a single
                        -- table read after the lazy element-by-name cache is warmed.
                        local slotMagicBurstName = nil;
                        if magicBurstEnabled and bind then
                            slotMagicBurstName = skillchain.GetMagicBurstForSlot(targetServerId, bind);
                        end
                        DrawSlot(barIndex, slotIndex, slotX, slotY, buttonSize, bind, barSettings, animOpacity, slotSkillchainName, slotMagicBurstName);
                    end
                end
                slotIndex = slotIndex + 1;
            end
        end


        imgui.End();
    end

    -- Draw pet palette indicator dot OUTSIDE window bounds (above bar number)
    -- Must be after End() and use ForegroundDrawList to avoid clipping
    -- Only shows for pet-aware bars (gold indicator)
    local hasPetIndicator = barSettings.petAware and barSettings.showPetIndicator ~= false;

    if windowPosX and hasPetIndicator then
        local dotX = windowPosX - 12;  -- Centered above bar number
        local dotY = windowPosY + (barHeight / 2) - 20;  -- Above the number
        local dotRadius = 5;
        local fgDrawList = GetUIDrawList();

        local indicatorColor = {1.0, 0.8, 0.2, 1.0};  -- Gold

        fgDrawList:AddCircleFilled({dotX, dotY}, dotRadius, imgui.GetColorU32(indicatorColor), 12);
        fgDrawList:AddCircle({dotX, dotY}, dotRadius, imgui.GetColorU32({0.0, 0.0, 0.0, 1.0}), 12, 1.0);

        -- Check hover for tooltip
        local mouseX, mouseY = imgui.GetMousePos();
        local dx = mouseX - dotX;
        local dy = mouseY - dotY;
        local hoverRadius = dotRadius + 3;
        if (dx * dx + dy * dy) <= (hoverRadius * hoverRadius) then
            imgui.BeginTooltip();

            imgui.TextColored({1.0, 0.8, 0.2, 1.0}, 'Pet Palette Bar ' .. barIndex);
            imgui.Separator();

            -- Current pet info
            local currentPet = petpalette.GetCurrentPetDisplayName();
            if currentPet then
                imgui.Text('Current Pet: ' .. currentPet);
            else
                imgui.TextColored({0.6, 0.6, 0.6, 1.0}, 'No pet summoned');
            end

            -- Palette mode
            local hasOverride = petpalette.HasManualOverride(barIndex);
            if hasOverride then
                local overrideName = petpalette.GetPaletteDisplayName(barIndex, data.jobId);
                imgui.Text('Palette: ' .. overrideName .. ' (Manual)');
            else
                imgui.Text('Palette: Auto');
            end

            imgui.EndTooltip();
        end
    end

    -- Draw move anchor (only visible when config is open)
    -- Must be called after we have window position
    if windowPosX ~= nil then
        -- Only show anchor when movement is NOT locked (global setting)
        local globalLocked = gConfig and gConfig.hotbarLockMovement;
        if not globalLocked then
            -- Use same window name as ImGui window so positions are shared
            local anchorName = string.format('Hotbar%d', barIndex);
            local anchorNewX, anchorNewY = drawing.DrawMoveAnchor(anchorName, windowPosX, windowPosY);
            if anchorNewX ~= nil then
                windowPosX = anchorNewX;
                windowPosY = anchorNewY;
                
                -- Update config immediately so next frame's positioning logic picks it up
                if not gConfig.windowPositions then gConfig.windowPositions = {}; end
                gConfig.windowPositions[anchorName] = { x = anchorNewX, y = anchorNewY };
            end
        end
    end
end

-- ============================================
-- Public Functions
-- ============================================

function M.DrawWindow(settings)
    -- Note: dragdrop.Update() is called from init.lua before this

    -- Refresh per-frame cached spell/ability/WS/item lists used by macropalette filters
    -- and by GetBindIcon resolution for macro lines.
    playerdata.RefreshCachedLists(data);

    -- Initialize textures on first draw
    if not texturesInitialized then
        textures:Initialize();
        texturesInitialized = true;
    end

    -- Draw each bar as its own window (per-bar themes handled in DrawBarWindow)
    for barIndex = 1, data.NUM_BARS do
        DrawBarWindow(barIndex, settings);
    end

    -- Clear force position reset flag after all bars have been drawn
    if forcePositionReset then
        forcePositionReset = false;
    end

    -- Note: Macro palette, dragdrop.Render(), and outside drop handling are in init.lua
end

function M.HideWindow()
end

-- ============================================
-- Lifecycle
-- ============================================

function M.Initialize(settings)
    -- Register palette change callback for animation
    palette.OnPaletteChanged(OnPaletteChanged);
end

function M.UpdateVisuals(settings)
    -- Font/visual settings can change the measured width of cached abbreviations.
    -- Drop the per-slot cache so abbreviation strings and widths get recomputed
    -- against the new font on the next frame.
    ClearIconCache();
end

function M.SetHidden(hidden)
    if hidden then
        M.HideWindow();
    end
end

function M.Cleanup()
    texturesInitialized = false;
    -- Clear icon cache
    ClearIconCache();
    -- Clear pre-created closures so they're recreated on reinit
    slotInteraction = {};
    -- Clear slotrenderer cache
    slotrenderer.ClearAllCache();
end

-- Expose cache clear for external callers (e.g., when slot actions change)
function M.ClearIconCache()
    ClearIconCache();
end

-- Expose targeted cache clear for single slot updates (e.g., drag/drop)
function M.ClearIconCacheForSlot(barIndex, slotIndex)
    ClearIconCacheForSlot(barIndex, slotIndex);
end

-- Reset all bar positions to defaults (called when settings are reset)
-- Note: Hotbar uses forcePositionReset + nil positions instead of explicit defaults
-- because it has its own position pipeline with per-bar default calculation at render time.
function M.ResetPositions()
    forcePositionReset = true;
    if gConfig.windowPositions and gConfig.appliedPositions then
        for barIndex = 1, data.NUM_BARS do
            local windowName = string.format('Hotbar%d', barIndex);
            gConfig.windowPositions[windowName] = nil;
            gConfig.appliedPositions[windowName] = nil;
        end
    end
end

return M;
