--[[
* XIUI Notifications - Display Module
* Handles all rendering for notification system
* Uses primitives for backgrounds, GDI fonts for text (following petbar pattern)
]]--

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local ffi = require('ffi');
local d3d8 = require('d3d8');
local notificationData = require('modules.notifications.data');
local progressbar = require('libs.progressbar');
local textures = require('libs.textures');
local windowBg = require('libs.windowbackground');

local M = {};

-- Global slot counter for notification rendering
-- Reset at start of DrawWindow, incremented for each notification drawn
local currentSlot = 0;

-- ============================================
-- Icon Cache
-- ============================================

local iconCache = {};  -- itemId -> texture
local typeIcons = {};  -- notification type -> texture

-- ============================================
-- Text Truncation Cache
-- ============================================

-- Cache for truncated text to avoid expensive binary search every frame
-- Key: notification.id .. "_title" or notification.id .. "_subtitle"
-- Value: {text = original_text, maxWidth = width, fontHeight = height, truncated = result}
local truncatedTextCache = {};

-- Truncates text to fit within maxWidth using binary search for optimal performance
local function TruncateTextToFit(fontObj, text, maxWidth)
    -- First check if text fits without truncation
    fontObj:set_text(text);
    local width, height = fontObj:get_text_size();

    if (width <= maxWidth) then
        return text;
    end

    -- Text is too long, use binary search to find optimal truncation point
    local ellipsis = "...";
    local maxLength = #text;

    -- Binary search for the longest substring that fits with ellipsis
    local left, right = 1, maxLength;
    local bestLength = 0;

    while left <= right do
        local mid = math.floor((left + right) / 2);
        local truncated = text:sub(1, mid) .. ellipsis;
        fontObj:set_text(truncated);
        width, height = fontObj:get_text_size();

        if width <= maxWidth then
            -- This length fits, try a longer one
            bestLength = mid;
            left = mid + 1;
        else
            -- This length is too long, try a shorter one
            right = mid - 1;
        end
    end

    if bestLength > 0 then
        return text:sub(1, bestLength) .. ellipsis;
    end

    -- Fallback: just ellipsis
    return ellipsis;
end

-- Get truncated text with caching
local function GetTruncatedText(fontObj, text, maxWidth, fontHeight, cacheKey)
    local cached = truncatedTextCache[cacheKey];
    if cached and cached.text == text and cached.maxWidth == maxWidth and cached.fontHeight == fontHeight then
        -- Cache hit - reuse truncated text
        return cached.truncated;
    end

    -- Cache miss - compute and store
    local truncated = TruncateTextToFit(fontObj, text, maxWidth);
    truncatedTextCache[cacheKey] = {
        text = text,
        maxWidth = maxWidth,
        fontHeight = fontHeight,
        truncated = truncated
    };
    return truncated;
end

-- Load item icon from game resources
local function loadItemIcon(itemId)
    -- Validate item ID (following atom0s pattern)
    if itemId == nil or itemId == 0 or itemId == -1 or itemId == 65535 then
        return nil;
    end

    -- Check cache first
    if iconCache[itemId] then
        return iconCache[itemId];
    end

    -- Wrap texture loading in pcall to prevent crashes
    local success, result = pcall(function()
        local device = GetD3D8Device();
        if device == nil then
            return nil;
        end

        local item = AshitaCore:GetResourceManager():GetItemById(itemId);
        if item == nil then
            return nil;
        end

        -- Check bitmap is valid
        if item.Bitmap == nil or item.ImageSize == nil or item.ImageSize <= 0 then
            return nil;
        end

        local dx_texture_ptr = ffi.new('IDirect3DTexture8*[1]');
        if ffi.C.D3DXCreateTextureFromFileInMemoryEx(
            device, item.Bitmap, item.ImageSize,
            0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
            ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED,
            ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT,
            0xFF000000, nil, nil, dx_texture_ptr
        ) == ffi.C.S_OK then
            -- Wrap in table with .image to match LoadTexture() format
            return {
                image = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', dx_texture_ptr[0]))
            };
        end
        return nil;
    end);

    if success and result then
        iconCache[itemId] = result;
    end

    return iconCache[itemId];
end

-- Load type-specific icon textures
local function loadTypeIcons()
    -- Load icons from assets/notifications folder
    typeIcons.invite = textures.LoadTexture("notifications/invite_icon");
    typeIcons.trade = textures.LoadTexture("notifications/trade_icon");
    typeIcons.keyitem = textures.LoadTexture("notifications/bazaar_icon");
    typeIcons.gil = textures.LoadTexture("gil");

    -- Map notification types to their icons
    typeIcons[notificationData.NOTIFICATION_TYPE.PARTY_INVITE] = typeIcons.invite;
    typeIcons[notificationData.NOTIFICATION_TYPE.TRADE_INVITE] = typeIcons.trade;
    typeIcons[notificationData.NOTIFICATION_TYPE.TREASURE_POOL] = nil;  -- Uses item icon
    typeIcons[notificationData.NOTIFICATION_TYPE.TREASURE_LOT] = nil;   -- Uses item icon
    typeIcons[notificationData.NOTIFICATION_TYPE.ITEM_OBTAINED] = nil;  -- Uses item icon
    typeIcons[notificationData.NOTIFICATION_TYPE.KEY_ITEM_OBTAINED] = typeIcons.keyitem;
    typeIcons[notificationData.NOTIFICATION_TYPE.GIL_OBTAINED] = typeIcons.gil;
end

-- ============================================
-- Notification Content Helpers
-- ============================================

-- Get notification icon texture
local function getNotificationIcon(notification)
    local nType = notification.type;

    -- Item notifications use item icons
    if nType == notificationData.NOTIFICATION_TYPE.ITEM_OBTAINED
        or nType == notificationData.NOTIFICATION_TYPE.TREASURE_POOL
        or nType == notificationData.NOTIFICATION_TYPE.TREASURE_LOT then

        local itemId = notification.data.itemId;
        if itemId then
            return loadItemIcon(itemId);
        end
    end

    -- Use type icons for other notifications
    return typeIcons[nType];
end

-- Get notification title text
local function getNotificationTitle(notification)
    local nType = notification.type;

    if nType == notificationData.NOTIFICATION_TYPE.PARTY_INVITE then
        return 'Party Invite';
    elseif nType == notificationData.NOTIFICATION_TYPE.TRADE_INVITE then
        return 'Trade Invite';
    elseif nType == notificationData.NOTIFICATION_TYPE.TREASURE_POOL then
        return 'Treasure Pool';
    elseif nType == notificationData.NOTIFICATION_TYPE.TREASURE_LOT then
        return 'Lot Cast';
    elseif nType == notificationData.NOTIFICATION_TYPE.ITEM_OBTAINED then
        return 'Item Obtained';
    elseif nType == notificationData.NOTIFICATION_TYPE.KEY_ITEM_OBTAINED then
        return 'Key Item Obtained';
    elseif nType == notificationData.NOTIFICATION_TYPE.GIL_OBTAINED then
        return 'Gil Obtained';
    end

    return 'Notification';
end

-- Get notification subtitle text
local function getNotificationSubtitle(notification)
    local nType = notification.type;
    local data = notification.data;

    if nType == notificationData.NOTIFICATION_TYPE.PARTY_INVITE then
        return data.playerName or 'Unknown Player';
    elseif nType == notificationData.NOTIFICATION_TYPE.TRADE_INVITE then
        return data.playerName or 'Unknown Player';
    elseif nType == notificationData.NOTIFICATION_TYPE.TREASURE_POOL then
        return data.itemName or 'Unknown Item';
    elseif nType == notificationData.NOTIFICATION_TYPE.TREASURE_LOT then
        return data.itemName or 'Unknown Item';
    elseif nType == notificationData.NOTIFICATION_TYPE.ITEM_OBTAINED then
        local itemName = data.itemName or 'Unknown Item';
        local quantity = data.quantity or 1;
        if quantity > 1 then
            return string.format('%s x%d', itemName, quantity);
        end
        return itemName;
    elseif nType == notificationData.NOTIFICATION_TYPE.KEY_ITEM_OBTAINED then
        return data.itemName or 'Unknown Key Item';
    elseif nType == notificationData.NOTIFICATION_TYPE.GIL_OBTAINED then
        local amount = data.amount or 0;
        return FormatInt(amount) .. ' Gil';
    end

    return '';
end

-- ============================================
-- Notification Rendering
-- ============================================

-- Draw a single notification using primitives, GDI fonts, and progress bar
local function drawNotification(slot, notification, x, y, width, height, settings, drawList)
    -- Get primitive and fonts for this slot
    local bgPrim = notificationData.bgPrims[slot];
    local titleFont = notificationData.titleFonts[slot];
    local subtitleFont = notificationData.subtitleFonts[slot];

    if not bgPrim or not titleFont or not subtitleFont then
        return;
    end

    -- Apply animation state
    local alpha = notification.alpha or 1;
    local containerOffsetX = notification.containerOffsetX or 0;
    local iconOffsetX = notification.iconOffsetX or 0;
    local textOffsetY = notification.textOffsetY or 0;

    -- Apply container offset (slides right on exit)
    x = x + containerOffsetX;

    -- Use full dimensions (no scale animation)
    local scaledWidth = width;
    local scaledHeight = height;

    -- Update background using windowbackground library
    -- Convert alpha (0-1) to opacity (0xDD = 221/255 ≈ 0.87)
    local bgOpacity = alpha * 0.87;

    windowBg.update(bgPrim, x, y, scaledWidth, scaledHeight, {
        theme = 'Plain',
        padding = 0,
        bgOpacity = bgOpacity,
        bgColor = 0xFF1A1A1A,
    });

    -- Draw pulsing dot for party/trade invites
    local nType = notification.type;
    if drawList and (nType == notificationData.NOTIFICATION_TYPE.PARTY_INVITE or
                     nType == notificationData.NOTIFICATION_TYPE.TRADE_INVITE) then
        -- Calculate pulse (sine wave, 0.3-1.0 range)
        local pulseSpeed = 0.8;  -- Pulses per second
        local pulseAlpha = 0.3 + 0.7 * math.abs(math.sin(os.clock() * pulseSpeed * math.pi));

        -- Apply notification alpha to pulse
        local finalPulseAlpha = pulseAlpha * alpha;

        -- Choose color based on type (using ImGui color table format)
        local dotColorTable;
        if nType == notificationData.NOTIFICATION_TYPE.PARTY_INVITE then
            -- Green dot for party invite
            dotColorTable = {0.31, 0.78, 0.47, finalPulseAlpha};  -- #50C878
        else
            -- Orange dot for trade invite
            dotColorTable = {1.0, 0.65, 0.0, finalPulseAlpha};  -- #FFA500
        end

        -- Draw pulsing dot on right side
        local dotRadius = 4;
        local dotX = x + scaledWidth - 10;
        local dotY = y + (scaledHeight / 2);
        local dotU32 = imgui.GetColorU32(dotColorTable);
        drawList:AddCircleFilled({dotX, dotY}, dotRadius, dotU32, 12);
    end

    -- Check if notification is minified or minifying
    local isMinified = notificationData.IsMinified(notification);
    local isMinifying = notificationData.IsMinifying(notification);
    local minifyProgress = notificationData.GetMinifyProgress(notification);

    -- Content padding from config (countdown bar excluded)
    local contentPadding = gConfig.notificationsPadding or 8;

    -- Interpolate icon size (32px -> 16px) during minify
    local normalIconSize = 32;
    local minifiedIconSize = 16;

    local iconSize;
    if isMinifying then
        -- Interpolate during animation
        iconSize = math.floor(normalIconSize - (minifyProgress * (normalIconSize - minifiedIconSize)));
    else
        iconSize = isMinified and minifiedIconSize or normalIconSize;
    end

    -- Icon position with animation offset (slides in from left)
    -- Vertically center icon in content area
    -- Normal mode: exclude 4px progress bar; Minified mode: no progress bar
    local iconX = x + contentPadding + iconOffsetX;
    local contentHeight = isMinified and scaledHeight or (scaledHeight - 4);
    local iconY = y + math.floor((contentHeight - iconSize) / 2);

    -- Get icon for this notification
    local icon = getNotificationIcon(notification);

    -- Get font sizes from config (user-adjustable) with fallback to settings
    -- No scaling - fonts fade in/out with opacity instead
    local titleFontHeight = gConfig.notificationsTitleFontSize or (settings.title_font_settings and settings.title_font_settings.font_height) or 14;
    local subtitleFontHeight = gConfig.notificationsSubtitleFontSize or (settings.font_settings and settings.font_settings.font_height) or 12;

    -- Calculate text position (shifts right if icon exists)
    local iconTextGap = 6;  -- Gap between icon and text
    local textX = x + contentPadding;
    if icon then
        textX = x + contentPadding + iconSize + iconTextGap;  -- Shift right past icon (use base x, not iconX with offset)
    end
    -- Text Y position with animation offset (slides up into position)
    -- Vertically center text block in content area (excluding progress bar)
    local baseTextY;
    if isMinified then
        -- Minified: center single line of text (subtract 1px for visual alignment)
        baseTextY = y + math.floor((contentHeight - subtitleFontHeight) / 2) - 1;
    else
        -- Normal: center text block (title + 2px gap + subtitle)
        local textBlockHeight = titleFontHeight + 2 + subtitleFontHeight;
        baseTextY = y + math.floor((contentHeight - textBlockHeight) / 2);
    end
    local textY = baseTextY + textOffsetY;

    -- Draw icon if we have one and have a draw list
    if icon and icon.image and drawList then
        -- Convert alpha to icon color with alpha
        local iconAlphaByte = math.floor(alpha * 255);
        local iconColor = bit.bor(bit.lshift(iconAlphaByte, 24), 0x00FFFFFF);  -- White with alpha

        pcall(function()
            drawList:AddImage(
                tonumber(ffi.cast("uint32_t", icon.image)),
                {iconX, iconY},
                {iconX + iconSize, iconY + iconSize},
                {0, 0},  -- UV min
                {1, 1},  -- UV max
                iconColor
            );
        end);
    end

    -- Calculate max text width for truncation (from textX to right edge with padding)
    local maxTextWidth = (x + scaledWidth - contentPadding) - textX;

    -- Pre-calculate alpha byte for font/outline fading
    local alphaByte = math.floor(alpha * 255);

    -- Get base colors from settings
    local baseTitleColor = settings.title_font_settings and settings.title_font_settings.font_color or 0xFFFFFFFF;
    local baseSubtitleColor = settings.font_settings and settings.font_settings.font_color or 0xFFFFFFFF;
    local baseTitleOutline = settings.title_font_settings and settings.title_font_settings.outline_color or 0xFF000000;
    local baseSubtitleOutline = settings.font_settings and settings.font_settings.outline_color or 0xFF000000;

    -- Calculate faded colors (both text and outline need to fade together)
    local fadedTitleColor = bit.bor(bit.lshift(alphaByte, 24), bit.band(baseTitleColor, 0x00FFFFFF));
    local fadedSubtitleColor = bit.bor(bit.lshift(alphaByte, 24), bit.band(baseSubtitleColor, 0x00FFFFFF));
    local fadedTitleOutline = bit.bor(bit.lshift(alphaByte, 24), bit.band(baseTitleOutline, 0x00FFFFFF));
    local fadedSubtitleOutline = bit.bor(bit.lshift(alphaByte, 24), bit.band(baseSubtitleOutline, 0x00FFFFFF));

    if isMinified then
        -- Minified mode: only show player name (no title)
        titleFont:set_visible(false);

        -- For minified invites, show only player name
        local playerName = notification.data.playerName or 'Unknown';

        subtitleFont:set_font_height(subtitleFontHeight);
        subtitleFont:set_position_x(textX);
        subtitleFont:set_position_y(textY);
        subtitleFont:set_font_color(fadedSubtitleColor);
        subtitleFont:set_outline_color(fadedSubtitleOutline);
        -- Truncate if needed
        local subtitleCacheKey = notification.id .. "_minified";
        local displayName = GetTruncatedText(subtitleFont, playerName, maxTextWidth, subtitleFontHeight, subtitleCacheKey);
        subtitleFont:set_text(displayName);
        subtitleFont:set_visible(alpha > 0.01);
    elseif isMinifying then
        -- Minifying animation: fade out title, move subtitle up
        local title = getNotificationTitle(notification);
        local playerName = notification.data.playerName or 'Unknown';

        -- Title fades out during minify (separate alpha from base animation)
        local titleAlpha = 1.0 - minifyProgress;
        local titleAlphaByte = math.floor(titleAlpha * 255);
        local minifyTitleColor = bit.bor(bit.lshift(titleAlphaByte, 24), bit.band(baseTitleColor, 0x00FFFFFF));
        local minifyTitleOutline = bit.bor(bit.lshift(titleAlphaByte, 24), bit.band(baseTitleOutline, 0x00FFFFFF));

        titleFont:set_font_height(titleFontHeight);
        titleFont:set_position_x(textX);
        titleFont:set_position_y(textY);
        titleFont:set_font_color(minifyTitleColor);
        titleFont:set_outline_color(minifyTitleOutline);
        local titleCacheKey = notification.id .. "_title";
        local displayTitle = GetTruncatedText(titleFont, title, maxTextWidth, titleFontHeight, titleCacheKey);
        titleFont:set_text(displayTitle);
        titleFont:set_visible(titleAlpha > 0.01);

        -- Subtitle moves from normal position to centered position
        local normalSubtitleY = textY + titleFontHeight + 2;  -- Small gap between title and subtitle
        local minifiedSubtitleY = y + math.floor((scaledHeight - subtitleFontHeight) / 2);
        local interpolatedSubtitleY = normalSubtitleY + (minifyProgress * (minifiedSubtitleY - normalSubtitleY));

        -- Subtitle stays fully visible during minify (alpha = 1.0)
        subtitleFont:set_font_height(subtitleFontHeight);
        subtitleFont:set_position_x(textX);
        subtitleFont:set_position_y(interpolatedSubtitleY);
        subtitleFont:set_font_color(baseSubtitleColor);
        subtitleFont:set_outline_color(baseSubtitleOutline);
        -- Use player name during minify animation
        local subtitleCacheKey = notification.id .. "_minifying";
        local displayName = GetTruncatedText(subtitleFont, playerName, maxTextWidth, subtitleFontHeight, subtitleCacheKey);
        subtitleFont:set_text(displayName);
        subtitleFont:set_visible(true);
    else
        -- Normal mode: show title and subtitle
        local title = getNotificationTitle(notification);
        local subtitle = getNotificationSubtitle(notification);

        -- Update title font (using pre-calculated faded colors)
        titleFont:set_font_height(titleFontHeight);
        titleFont:set_position_x(textX);
        titleFont:set_position_y(textY);
        titleFont:set_font_color(fadedTitleColor);
        titleFont:set_outline_color(fadedTitleOutline);
        -- Truncate title if needed (use notification id for cache key)
        local titleCacheKey = notification.id .. "_title";
        local displayTitle = GetTruncatedText(titleFont, title, maxTextWidth, titleFontHeight, titleCacheKey);
        titleFont:set_text(displayTitle);
        titleFont:set_visible(alpha > 0.01);

        -- Update subtitle font (using pre-calculated faded colors)
        subtitleFont:set_font_height(subtitleFontHeight);
        subtitleFont:set_position_x(textX);
        subtitleFont:set_position_y(textY + titleFontHeight + 2);  -- Small gap between title and subtitle
        subtitleFont:set_font_color(fadedSubtitleColor);
        subtitleFont:set_outline_color(fadedSubtitleOutline);
        -- Truncate subtitle if needed (use notification id for cache key)
        local subtitleCacheKey = notification.id .. "_subtitle";
        local displaySubtitle = GetTruncatedText(subtitleFont, subtitle, maxTextWidth, subtitleFontHeight, subtitleCacheKey);
        subtitleFont:set_text(displaySubtitle);
        subtitleFont:set_visible(alpha > 0.01);
    end

    -- Draw duration progress bar at bottom
    -- Show for all types except when minified/minifying
    local showProgressBar = drawList and not isMinified and not isMinifying;
    if showProgressBar then
        -- Calculate time remaining progress
        local progress = 1.0;
        local currentTime = os.clock();
        local isPersistent = notificationData.IsPersistentType(notification.type);

        if notification.state == notificationData.STATE.VISIBLE then
            local elapsed = currentTime - notification.stateStartTime;
            if isPersistent then
                -- Persistent types (party/trade invites): count down to minify timeout
                local minifyTimeout = gConfig.notificationsInviteMinifyTimeout or 10.0;
                progress = math.max(0, 1.0 - (elapsed / minifyTimeout));
            else
                -- Normal types: count down to exit
                local duration = notification.displayDuration or 3.0;
                progress = math.max(0, 1.0 - (elapsed / duration));
            end
        elseif notification.state == notificationData.STATE.ENTERING then
            -- Full bar during enter animation
            progress = 1.0;
        elseif notification.state == notificationData.STATE.EXITING then
            -- Empty bar during exit
            progress = 0;
        end

        -- Progress bar settings
        -- Use direct coordinates (not bgPrim.bg) to avoid any offset from windowbackground library
        local barScaleY = gConfig.notificationsProgressBarScaleY or 1.0;
        local barHeight = math.floor(4 * barScaleY);
        local barX = x;
        local barWidth = scaledWidth;
        local barY = y + scaledHeight - barHeight;

        -- Get color based on notification type
        local barGradient = {'#4a90d9', '#6bb3f0'};  -- Default blue

        local nType = notification.type;
        if nType == notificationData.NOTIFICATION_TYPE.ITEM_OBTAINED then
            barGradient = {'#9abb5a', '#bfe07d'};  -- Green
        elseif nType == notificationData.NOTIFICATION_TYPE.KEY_ITEM_OBTAINED then
            barGradient = {'#d4af37', '#f0d060'};  -- Gold
        elseif nType == notificationData.NOTIFICATION_TYPE.GIL_OBTAINED then
            barGradient = {'#d4af37', '#f0d060'};  -- Gold
        elseif nType == notificationData.NOTIFICATION_TYPE.TREASURE_POOL or
               nType == notificationData.NOTIFICATION_TYPE.TREASURE_LOT then
            barGradient = {'#9966cc', '#bb99dd'};  -- Purple
        elseif nType == notificationData.NOTIFICATION_TYPE.PARTY_INVITE then
            barGradient = {'#4CAF50', '#81C784'};  -- Green for party
        elseif nType == notificationData.NOTIFICATION_TYPE.TRADE_INVITE then
            barGradient = {'#FF9800', '#FFB74D'};  -- Orange for trade
        end

        -- Draw progress bar using imgui draw list directly (more reliable than progressbar with absolutePosition)
        local barColor1 = HexToU32(barGradient[1]);
        local barColor2 = HexToU32(barGradient[2]);
        local filledWidth = barWidth * progress;

        -- Draw filled portion with gradient
        if filledWidth > 0 then
            drawList:AddRectFilledMultiColor(
                {barX, barY},
                {barX + filledWidth, barY + barHeight},
                barColor1, barColor2, barColor2, barColor1
            );
        end
    end
end

-- ============================================
-- Split Window Helpers
-- ============================================

-- Human-readable names for split window types
local SPLIT_WINDOW_TITLES = {
    PartyInvite = 'Party Invites',
    TradeInvite = 'Trade Requests',
    TreasurePool = 'Treasure Pool',
    ItemObtained = 'Items Obtained',
    KeyItemObtained = 'Key Items',
    GilObtained = 'Gil Obtained',
};

-- Placeholder text for split windows
local SPLIT_WINDOW_PLACEHOLDERS = {
    PartyInvite = 'Party invites appear here',
    TradeInvite = 'Trade requests appear here',
    TreasurePool = 'Treasure pool items appear here',
    ItemObtained = 'Items appear here',
    KeyItemObtained = 'Key items appear here',
    GilObtained = 'Gil obtained appears here',
};

-- Get notifications for a split window key
local function getNotificationsForSplitKey(splitKey)
    local notifications = {};
    local types = notificationData.GetTypesForSplitKey(splitKey);
    for _, notifType in ipairs(types) do
        local typeNotifs = notificationData.GetNotificationsByType(notifType);
        for _, notif in ipairs(typeNotifs) do
            table.insert(notifications, notif);
        end
    end
    return notifications;
end

-- ============================================
-- Generic Notification Window Drawing
-- ============================================

-- Draw a notification window (used for main and split windows)
-- splitKey: nil for main window, or the split key (e.g., 'PartyInvite') for split windows
-- Returns true if window was drawn
local function drawNotificationWindow(windowName, notifications, settings, splitKey, placeholderTitle, placeholderSubtitle)
    local configOpen = showConfig and showConfig[1];
    local hasNotifications = notifications and #notifications > 0;

    -- Early return if nothing to draw
    if not hasNotifications and not configOpen then
        return false;
    end

    -- Build window flags
    local windowFlags = notificationData.getBaseWindowFlags();
    if gConfig.lockPositions and not configOpen then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
    end

    -- Calculate notification dimensions using separate X/Y scale
    local scaleX = gConfig.notificationsScaleX or 1.0;
    local scaleY = gConfig.notificationsScaleY or 1.0;
    local contentPadding = gConfig.notificationsPadding or 8;
    local notificationWidth = math.floor((settings.width or 280) * scaleX);
    -- Normal height: padding + icon(32) + padding + progress bar(4)
    local normalHeight = math.floor((contentPadding * 2 + 32 + 4) * scaleY);
    -- Minified height: padding + minified icon(16) + padding (no progress bar)
    local minifiedHeight = math.floor((contentPadding * 2 + 16) * scaleY);
    local spacing = gConfig.notificationsSpacing or 8;

    -- Calculate total content height
    local totalHeight = 0;
    if hasNotifications then
        for i, notification in ipairs(notifications) do
            if i > notificationData.MAX_ACTIVE_NOTIFICATIONS then break; end
            local isMinified = notificationData.IsMinified(notification);
            local isMinifying = notificationData.IsMinifying(notification);
            local minifyProgress = notificationData.GetMinifyProgress(notification);

            local height;
            if isMinifying then
                height = normalHeight - (minifyProgress * (normalHeight - minifiedHeight));
            else
                height = isMinified and minifiedHeight or normalHeight;
            end

            if i > 1 then
                totalHeight = totalHeight + spacing;
            end
            totalHeight = totalHeight + height;
        end
    else
        totalHeight = normalHeight;  -- Placeholder height
    end

    -- Create ImGui window
    if imgui.Begin(windowName, true, windowFlags) then
        local windowPosX, windowPosY = imgui.GetWindowPos();
        local drawList = imgui.GetWindowDrawList();

        -- Set window size
        imgui.Dummy({notificationWidth, totalHeight});

        if hasNotifications then
            local currentY = windowPosY;
            for i, notification in ipairs(notifications) do
                -- Use global slot counter instead of local index
                currentSlot = currentSlot + 1;
                if currentSlot > notificationData.MAX_ACTIVE_NOTIFICATIONS then break; end

                -- Calculate height based on minified/minifying state
                local isMinified = notificationData.IsMinified(notification);
                local isMinifying = notificationData.IsMinifying(notification);
                local minifyProgress = notificationData.GetMinifyProgress(notification);

                local notificationHeight;
                if isMinifying then
                    notificationHeight = normalHeight - (minifyProgress * (normalHeight - minifiedHeight));
                else
                    notificationHeight = isMinified and minifiedHeight or normalHeight;
                end

                local x = windowPosX;
                local y = currentY;

                drawNotification(currentSlot, notification, x, y, notificationWidth, notificationHeight, settings, drawList);

                currentY = currentY + notificationHeight + spacing;
            end
        elseif configOpen then
            -- Show placeholder when config is open
            local placeholderPadding = gConfig.notificationsPadding or 8;
            local titleHeight = gConfig.notificationsTitleFontSize or 14;
            local subtitleHeight = gConfig.notificationsSubtitleFontSize or 12;

            -- Get fonts and primitives based on window type
            local bgPrim, titleFont, subtitleFont;
            if splitKey == nil then
                -- Main window: use slot 1 primitives/fonts
                -- Only show if no other notifications are using slot 1 (currentSlot == 0)
                if currentSlot > 0 then
                    -- Skip placeholder - slot 1 is in use by split window notifications
                    imgui.End();
                    return true;
                end
                bgPrim = notificationData.bgPrims[1];
                titleFont = notificationData.titleFonts[1];
                subtitleFont = notificationData.subtitleFonts[1];
            else
                -- Split window: use dedicated split window primitives/fonts
                bgPrim = notificationData.splitBgPrims[splitKey];
                titleFont = notificationData.splitTitleFonts[splitKey];
                subtitleFont = notificationData.splitSubtitleFonts[splitKey];
            end

            -- Draw background using windowbackground library
            if bgPrim then
                windowBg.update(bgPrim, windowPosX, windowPosY, notificationWidth, normalHeight, {
                    theme = 'Plain',
                    padding = 0,
                    bgOpacity = 0.27,  -- 0x44 = 68/255 ≈ 0.27
                    bgColor = 0xFF1A1A1A,
                });
            end

            -- Draw title font
            if titleFont then
                titleFont:set_font_height(titleHeight);
                titleFont:set_position_x(windowPosX + placeholderPadding);
                titleFont:set_position_y(windowPosY + placeholderPadding);
                titleFont:set_text(placeholderTitle or 'Notification Area');
                titleFont:set_font_color(0xFFFFFFFF);  -- Reset to full opacity
                titleFont:set_outline_color(0xFF000000);
                titleFont:set_visible(true);
            end

            -- Draw subtitle font
            if subtitleFont then
                subtitleFont:set_font_height(subtitleHeight);
                subtitleFont:set_position_x(windowPosX + placeholderPadding);
                subtitleFont:set_position_y(windowPosY + placeholderPadding + titleHeight + 2);
                subtitleFont:set_text(placeholderSubtitle or 'Drag to reposition');
                subtitleFont:set_font_color(0xFFCCCCCC);  -- Reset to full opacity (slightly dimmer)
                subtitleFont:set_outline_color(0xFF000000);
                subtitleFont:set_visible(true);
            end
        end
    end
    imgui.End();

    return true;
end

-- Draw a split window for a specific notification type
local function drawSplitWindow(splitKey, settings)
    local windowName = 'Notifications_' .. splitKey;
    local notifications = getNotificationsForSplitKey(splitKey);
    local title = SPLIT_WINDOW_TITLES[splitKey] or splitKey;
    local placeholder = SPLIT_WINDOW_PLACEHOLDERS[splitKey] or 'Drag to reposition';

    -- Pass splitKey for split windows (uses dedicated GDI fonts/primitives)
    drawNotificationWindow(windowName, notifications, settings, splitKey, title, placeholder);
end

-- ============================================
-- Treasure Pool Window
-- ============================================

-- Draw dedicated treasure pool window (shows all items with timers and lots)
local function drawTreasurePoolWindow(settings)
    -- Wrap entire function in pcall to prevent crashes
    local success, err = pcall(function()
        -- Hide all pool fonts and backgrounds initially (will show ones we use)
        notificationData.HidePoolFonts();
        notificationData.HidePoolBackgrounds();

        -- Get treasure pool items
        local poolItems = notificationData.GetSortedTreasurePool();
        if #poolItems == 0 then
            return;
        end

    -- Build window flags
    local windowFlags = notificationData.getBaseWindowFlags();
    local configOpen = showConfig and showConfig[1];
    if gConfig.lockPositions and not configOpen then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
    end

    -- Dimensions
    local scaleX = gConfig.notificationsTreasurePoolScaleX or 1.0;
    local scaleY = gConfig.notificationsTreasurePoolScaleY or 1.0;
    local padding = gConfig.notificationsPadding or 8;
    local itemWidth = math.floor(280 * scaleX);
    -- Item height: padding + icon(16) + padding + timer bar(4)
    local itemHeight = math.floor((padding * 2 + 16 + 4) * scaleY);
    local iconSize = math.floor(16 * scaleY);
    local spacing = 4;

    -- Font size from config (single size for all treasure pool text)
    local poolFontSize = gConfig.notificationsTreasurePoolFontSize or 10;

    -- Header height (font size + padding below) - only if title is shown
    local showTitle = gConfig.notificationsTreasurePoolShowTitle ~= false;
    local headerHeight = showTitle and (poolFontSize + 4) or 0;

    -- Calculate total height (header + items)
    local totalHeight = headerHeight + (#poolItems * itemHeight) + ((#poolItems - 1) * spacing);

    if imgui.Begin('TreasurePool', true, windowFlags) then
        local windowPosX, windowPosY = imgui.GetWindowPos();
        local drawList = imgui.GetWindowDrawList();

        imgui.Dummy({itemWidth, totalHeight});

        -- Draw header "Treasure Pool" if enabled
        local headerFont = notificationData.poolHeaderFont;
        if headerFont then
            if showTitle then
                headerFont:set_font_height(poolFontSize);
                headerFont:set_position_x(windowPosX);
                headerFont:set_position_y(windowPosY);
                headerFont:set_text('Treasure Pool');
                headerFont:set_visible(true);
            else
                headerFont:set_visible(false);
            end
        end

        -- Start items below header (or at top if no header)
        local currentY = windowPosY + headerHeight;

        for idx, item in ipairs(poolItems) do
            local slot = item.slot;  -- Use actual slot for font lookup

            -- Bounds check - skip if slot is out of range
            if slot ~= nil and slot >= 0 and slot < notificationData.TREASURE_POOL_MAX_SLOTS then

            local x = windowPosX;
            local y = currentY;

            -- Background (renders under GDI fonts)
            local bgHandle = notificationData.poolBgPrims[slot];
            if bgHandle then
                windowBg.update(bgHandle, x, y, itemWidth, itemHeight, {
                    theme = 'Plain',
                    padding = 0,
                    bgOpacity = 0.87,  -- 0xDD = 221/255 ≈ 0.87
                    bgColor = 0xFF1A1A1A,
                });
            end

            -- Item icon (rendered via ImGui on top of fonts)
            local icon = loadItemIcon(item.itemId);
            if icon and icon.image then
                pcall(function()
                    drawList:AddImage(
                        tonumber(ffi.cast("uint32_t", icon.image)),
                        {x + padding, y + padding},
                        {x + padding + iconSize, y + padding + iconSize},
                        {0, 0}, {1, 1},
                        0xFFFFFFFF
                    );
                end);
            end

            -- Text positions
            local textX = x + padding + iconSize + 6;
            local textY = y + padding;

            -- Draw item name using GDI font
            local itemNameFont = notificationData.poolItemNameFonts[slot];
            if itemNameFont then
                itemNameFont:set_font_height(poolFontSize);
                itemNameFont:set_position_x(textX);
                itemNameFont:set_position_y(textY);
                itemNameFont:set_text(item.itemName or 'Unknown Item');
                itemNameFont:set_visible(true);
            end

            -- Draw timer using GDI font
            local remaining = notificationData.GetTreasurePoolTimeRemaining(slot);
            local timerText = notificationData.FormatPoolTimer(remaining);

            -- Timer color (yellow when > 1 min, orange when < 1 min, red when < 30 sec)
            local timerColor;
            if remaining > 60 then
                timerColor = 0xFFFFFF4D;  -- Yellow
            elseif remaining > 30 then
                timerColor = 0xFFFF9933;  -- Orange
            else
                timerColor = 0xFFFF4D4D;  -- Red
            end

            -- Calculate fixed timer area width (for "M:SS" format, ~5 chars)
            -- This prevents shifting when timer changes digits
            local timerFont = notificationData.poolTimerFonts[slot];
            local fixedTimerWidth = 0;
            if timerFont then
                timerFont:set_font_height(poolFontSize);
                timerFont:set_text("5:00");  -- Reference width
                fixedTimerWidth, _ = timerFont:get_text_size();
            end

            -- Fixed right edge for timer area
            local timerRightX = x + itemWidth - padding;
            local timerAreaLeftX = timerRightX - fixedTimerWidth;

            if timerFont and gConfig.notificationsTreasurePoolShowTimerText then
                timerFont:set_text(timerText);
                -- Right-align timer within fixed area
                local actualTimerWidth, _ = timerFont:get_text_size();
                timerFont:set_position_x(timerRightX - actualTimerWidth);
                timerFont:set_position_y(textY);
                timerFont:set_font_color(timerColor);
                timerFont:set_visible(true);
            elseif timerFont then
                timerFont:set_visible(false);
            end

            -- Draw lots using GDI font (if showing lots is enabled)
            -- Displayed inline on the right side, to the left of the fixed timer area
            if gConfig.notificationsTreasurePoolShowLots then
                local lotFont = notificationData.poolLotFonts[slot];

                if lotFont and item.highestLot and item.highestLot > 0 then
                    -- Format: "Name: 734" - compact display on the right
                    local lotterName = item.highestLotterName or "";
                    -- Truncate long names to keep it compact
                    if #lotterName > 8 then
                        lotterName = lotterName:sub(1, 7) .. ".";
                    end
                    local lotText = string.format('%s: %d', lotterName, item.highestLot);
                    local lotColor = 0xFF4DFF4D;  -- Green for lot

                    lotFont:set_font_height(poolFontSize);
                    lotFont:set_text(lotText);
                    -- Right-align lot text to the left of the fixed timer area
                    local lotWidth, _ = lotFont:get_text_size();
                    local lotX = timerAreaLeftX - 8 - lotWidth;
                    lotFont:set_position_x(lotX);
                    lotFont:set_position_y(textY);
                    lotFont:set_font_color(lotColor);
                    lotFont:set_visible(true);
                end
            end

            -- Draw timer progress bar at bottom
            if gConfig.notificationsTreasurePoolShowTimerBar then
                local barHeight = 3;
                local barY = y + itemHeight - barHeight - 1;
                local progress = remaining / notificationData.TREASURE_POOL_TIMEOUT;

                -- Purple gradient for treasure pool
                local barColor = HexToU32('#9966cc');
                local filledWidth = (itemWidth - 2) * progress;

                if filledWidth > 0 then
                    drawList:AddRectFilled(
                        {x + 1, barY},
                        {x + 1 + filledWidth, barY + barHeight},
                        barColor,
                        1
                    );
                end
            end

            end -- End bounds check if

            currentY = currentY + itemHeight + spacing;
        end
    end
    imgui.End();
    end); -- End pcall wrapper

    if not success and err then
        print('[XIUI Notifications] Treasure pool render error: ' .. tostring(err));
    end
end

-- ============================================
-- Module Functions
-- ============================================

-- Initialize display module (called after fonts/prims created in init.lua)
function M.Initialize(settings)
    -- Load type icons
    loadTypeIcons();
end

-- Update visuals (called after fonts recreated in init.lua)
function M.UpdateVisuals(settings)
    -- Nothing to do here - fonts are managed by init.lua
end

-- Main draw function
function M.DrawWindow(settings, activeNotifications, pinnedNotifications)
    -- Safety check - ensure fonts are initialized
    if not notificationData.titleFonts or not notificationData.subtitleFonts then
        return;
    end

    -- Hide all fonts and primitives initially (including treasure pool)
    notificationData.SetAllFontsVisible(false);
    notificationData.HideAllBackgrounds();
    notificationData.HideSplitFonts();
    notificationData.HidePoolFonts();
    notificationData.HidePoolBackgrounds();

    -- Reset global slot counter for this frame
    currentSlot = 0;

    -- Check if player exists and is not zoning
    local player = GetPlayerSafe();
    if not player or player.isZoning then
        return;
    end

    -- Update treasure pool state (handles expiration, animations)
    notificationData.UpdateTreasurePool(os.clock());

    -- Draw treasure pool window if enabled and has items
    if gConfig.notificationsTreasurePoolWindow and gConfig.notificationsShowTreasure then
        drawTreasurePoolWindow(settings);
    end

    local configOpen = showConfig and showConfig[1];

    -- Draw split windows for each enabled split type
    local enabledSplitKeys = notificationData.GetEnabledSplitKeys();
    for _, splitKey in ipairs(enabledSplitKeys) do
        drawSplitWindow(splitKey, settings);
    end

    -- Get notifications for main window (non-split types only)
    local mainWindowNotifications = notificationData.GetNonSplitNotifications();
    local hasMainNotifications = #mainWindowNotifications > 0;

    -- Early return if no notifications for main window (unless config is open)
    if not hasMainNotifications and not configOpen then
        return;
    end

    -- Draw main notification window (nil splitKey = main window)
    drawNotificationWindow('Notifications', mainWindowNotifications, settings, nil, 'Notification Area', 'Drag to reposition');

    -- Hide unused slots (after all windows drawn)
    -- currentSlot now holds the total count of notifications rendered across all windows
    local usedSlots = currentSlot;
    -- If config is open and no notifications, slot 1 may be used for main window placeholder
    if usedSlots == 0 and configOpen then
        usedSlots = 1;
    end
    for i = usedSlots + 1, notificationData.MAX_ACTIVE_NOTIFICATIONS do
        if notificationData.bgPrims[i] then
            windowBg.hide(notificationData.bgPrims[i]);
        end
        if notificationData.titleFonts[i] then
            notificationData.titleFonts[i]:set_visible(false);
        end
        if notificationData.subtitleFonts[i] then
            notificationData.subtitleFonts[i]:set_visible(false);
        end
    end
end

-- Set visibility
function M.SetHidden(hidden)
    if hidden then
        notificationData.SetAllFontsVisible(false);
        notificationData.HideAllBackgrounds();
        notificationData.HideSplitFonts();
        notificationData.HidePoolFonts();
        notificationData.HidePoolBackgrounds();
    end
end

-- Cleanup
function M.Cleanup()
    -- Clear icon cache (textures are managed by gc_safe_release)
    iconCache = {};

    -- Clear text truncation cache
    truncatedTextCache = {};

    -- Clear type icons
    typeIcons = {};
end

return M;
