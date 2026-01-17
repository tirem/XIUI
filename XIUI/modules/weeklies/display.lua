--[[
* XIUI Weeklies Module - Display
* Handles rendering of the weeklies window and floating alerts
]]--

require('common');
local imgui = require('imgui');
local gdi = require('submodules.gdifonts.include');
local data = require('modules.weeklies.data');
local windowBg = require('libs.windowbackground');
local ffi = require('ffi');

local M = {};

local isListening = false;
local isHidden = false;
local floatingAlertText = nil;
local floatingAlertExpireTime = 0;
local bgHandle = nil;

local rowFonts = {};
local headerFont = nil;
local zoneAlertFont = nil;
local allFonts = {};

local titleTexture = nil;
local titleWidth = 0;
local titleHeight = 0;

local Colors = {
    KeyMissing    = function() return gConfig.colorCustomization.weeklies.keyMissingColor or 0xFFCC3800; end,
    KeyObtained   = function() return gConfig.colorCustomization.weeklies.keyObtainedColor or 0xFF99CC33; end,
    TimerReady    = function() return gConfig.colorCustomization.weeklies.timerReadyColor or 0xFF3AAAE8; end,
    TimerNotReady = function() return gConfig.colorCustomization.weeklies.timerNotReadyColor or 0xFFFFFFFF; end,
    TimerUnknown  = function() return gConfig.colorCustomization.weeklies.timerUnknownColor or 0xFFF6F499; end,
};

local Icons = {
    Times = 'X',
    Check = '✓',
};

local function formatTimeRemaining(seconds)
    if seconds <= 0 then
        return 'Available';
    end

    local days = math.floor(seconds / 86400);
    seconds = seconds % 86400;
    local hours = math.floor(seconds / 3600);
    seconds = seconds % 3600;
    local minutes = math.floor(seconds / 60);

    if days > 0 then
        if hours > 0 then
            return string.format('%dd %dh', days, hours);
        else
            return string.format('%dd', days);
        end
    elseif hours > 0 then
        return string.format('%dh %dm', hours, minutes);
    else
        if minutes <= 0 then
            minutes = 1;
        end
        return string.format('%dm', minutes);
    end
end

local function ensureBackground()
    if bgHandle then
        return;
    end

    local theme = gConfig.weekliesBackgroundTheme or 'Window1';
    local bgScale = gConfig.weekliesBgScale or 1.0;
    local borderScale = gConfig.weekliesBorderScale or 1.0;

    local prim_data = {
        visible = false,
        can_focus = false,
        locked = true,
        width = 500,
        height = 300,
    };

    bgHandle = windowBg.create(prim_data, theme, bgScale, borderScale);
end

local function ensureTitleTexture()
    if titleTexture then
        return;
    end

    titleTexture = LoadTexture('weekly-objectives');
    if titleTexture then
        titleWidth, titleHeight = GetTextureDimensions(titleTexture, 128, 32);
    else
        titleWidth, titleHeight = 0, 0;
    end
end

local function hideBackground()
    if bgHandle then
        windowBg.hide(bgHandle);
    end
end

local function ensureFonts()
    local textSize = gConfig.weekliesTextSize or 12;
    local headerSize = gConfig.weekliesHeaderTextSize or 13;
    local alertSize = gConfig.weekliesZoneAlertTextSize or 14;

    if not headerFont then
        headerFont = FontManager.create({
            font_family = gConfig.fontFamily or 'Tahoma',
            font_height = headerSize,
            color = gConfig.colorCustomization.weeklies.timerUnknownColor or 0xFFF6F499,
            outline_color = 0xFF000000,
            outline_width = gConfig.fontOutlineWidth or 2,
        });
        table.insert(allFonts, headerFont);
    else
        headerFont:set_font_height(headerSize);
    end

    if not zoneAlertFont then
        zoneAlertFont = FontManager.create({
            font_family = gConfig.fontFamily or 'Tahoma',
            font_height = alertSize,
            color = gConfig.colorCustomization.weeklies.timerReadyColor or 0xFF3AAAE8,
            outline_color = 0xFF000000,
            outline_width = gConfig.fontOutlineWidth or 2,
        });
        table.insert(allFonts, zoneAlertFont);
    else
        zoneAlertFont:set_font_height(alertSize);
    end

    local count = #data.Objectives;
    for i = 1, count do
        if not rowFonts[i] then
            local activityFont = FontManager.create({
                font_family = gConfig.fontFamily or 'Tahoma',
                font_height = textSize,
                color = 0xFFFFFFFF,
                outline_color = 0xFF000000,
                outline_width = gConfig.fontOutlineWidth or 2,
            });
            local levelFont = FontManager.create({
                font_family = gConfig.fontFamily or 'Tahoma',
                font_height = textSize,
                color = 0xFFFFFFFF,
                outline_color = 0xFF000000,
                outline_width = gConfig.fontOutlineWidth or 2,
            });
            local keyItemFont = FontManager.create({
                font_family = gConfig.fontFamily or 'Tahoma',
                font_height = textSize,
                color = 0xFFFFFFFF,
                outline_color = 0xFF000000,
                outline_width = gConfig.fontOutlineWidth or 2,
            });
            local iconFont = FontManager.create({
                font_family = gConfig.fontFamily or 'Tahoma',
                font_height = textSize,
                color = 0xFFFFFFFF,
                outline_color = 0xFF000000,
                outline_width = gConfig.fontOutlineWidth or 2,
            });
            local timerFont = FontManager.create({
                font_family = gConfig.fontFamily or 'Tahoma',
                font_height = textSize,
                color = 0xFFFFFFFF,
                outline_color = 0xFF000000,
                outline_width = gConfig.fontOutlineWidth or 2,
            });

            rowFonts[i] = {
                activity = activityFont,
                level = levelFont,
                keyItem = keyItemFont,
                icon = iconFont,
                timer = timerFont,
            };

            table.insert(allFonts, activityFont);
            table.insert(allFonts, levelFont);
            table.insert(allFonts, keyItemFont);
            table.insert(allFonts, iconFont);
            table.insert(allFonts, timerFont);
        else
            if rowFonts[i].activity then
                rowFonts[i].activity:set_font_height(textSize);
            end
            if rowFonts[i].level then
                rowFonts[i].level:set_font_height(textSize);
            end
            if rowFonts[i].keyItem then
                rowFonts[i].keyItem:set_font_height(textSize);
            end
            if rowFonts[i].icon then
                rowFonts[i].icon:set_font_height(textSize);
            end
            if rowFonts[i].timer then
                rowFonts[i].timer:set_font_height(textSize);
            end
        end
    end
end

local function setAllFontsVisible(visible)
    for _, f in ipairs(allFonts) do
        f:set_visible(visible);
    end
end

function M.SetListening(listening)
    isListening = listening;
end

function M.SetHidden(hidden)
    isHidden = hidden and true or false;
    if isHidden or not gConfig.weekliesEnabled then
        hideBackground();
        setAllFontsVisible(false);
    end
end

function M.GetListening()
    return isListening;
end

function M.ShowAlert(text, durationSeconds)
    floatingAlertText = text;
    floatingAlertExpireTime = os.time() + (durationSeconds or 5);
end

function M.DrawWindow()
    if not gConfig.weekliesEnabled then
        hideBackground();
        setAllFontsVisible(false);
        return;
    end

    if isHidden then
        hideBackground();
        setAllFontsVisible(false);
        return;
    end

    ensureBackground();
    ensureFonts();
    ensureTitleTexture();

    setAllFontsVisible(false);

    local windowFlags = GetBaseWindowFlags(gConfig.lockPositions);

    imgui.SetNextWindowSize({ 480, 0 }, ImGuiCond_FirstUseEver);
    if imgui.Begin('Weeklies', gConfig.weekliesEnabled, windowFlags) then
        local player = GetPlayerSafe();
        local now = os.time();
        local timers = gConfig.weekliesTimers or {};
        local activityFilters = gConfig.weekliesActivityFilters or {};

        local windowPosX, windowPosY = imgui.GetWindowPos();
        local cursorX, cursorY = imgui.GetCursorScreenPos();

        local rowHeight = (gConfig.weekliesTextSize or 12) + 4;
        local headerHeight = (gConfig.weekliesHeaderTextSize or 13) + 6;

        -- Column offsets
        local colActivity = 5;
        local colLevel = 170; -- Increased width for Activity
        local colKeyItem = 215; -- Increased width for Key Item
        local colIcon = 470;
        local colTimer = 505;
        local totalContentWidth = 600; -- Increased total width for detailed timer

        -- Start content just below the top so the title can sit on the border
        local contentStartY = cursorY + 5;

        local visibleRows = 0;

        for index, activity in ipairs(data.Objectives) do
            local key = tostring(activity.KeyItem.Id);
            local fonts = rowFonts[index];

                    if activityFilters[key] ~= false then
                        visibleRows = visibleRows + 1;
                        if fonts and fonts.activity and fonts.level and fonts.keyItem and fonts.icon and fonts.timer then
                            local hasKey = player and player:HasKeyItem(activity.KeyItem.Id) or false;
                            local timerInfo = timers[key];
                            local timeText = '???';
                            local color = Colors.TimerUnknown();

                            if timerInfo and timerInfo.time then
                                local remaining = timerInfo.time - now;
                                if remaining <= 0 then
                                    timeText = 'Available';
                                    color = Colors.TimerReady();
                                else
                                    timeText = formatTimeRemaining(remaining);
                                    color = Colors.TimerNotReady();
                                end
                            end

                            local statusIcon = hasKey and Icons.Check or Icons.Times;
                            local statusColor = hasKey and Colors.KeyObtained() or Colors.KeyMissing();

                    -- Activity Name
                    fonts.activity:set_position_x(cursorX + colActivity);
                    fonts.activity:set_position_y(contentStartY);
                    fonts.activity:set_font_alignment(gdi.Alignment.Left);
                    fonts.activity:set_font_color(0xFFFFFFFF);
                    fonts.activity:set_text(activity.Name);
                    fonts.activity:set_visible(true);

                    -- Level
                    fonts.level:set_position_x(cursorX + colLevel);
                    fonts.level:set_position_y(contentStartY);
                    fonts.level:set_font_alignment(gdi.Alignment.Center); -- Center alignment
                    fonts.level:set_font_color(0xFFFFFFFF);
                    fonts.level:set_text(tostring(activity.Level));
                    fonts.level:set_visible(true);

                    -- Key Item
                    fonts.keyItem:set_position_x(cursorX + colKeyItem);
                    fonts.keyItem:set_position_y(contentStartY);
                    fonts.keyItem:set_font_alignment(gdi.Alignment.Left);
                    fonts.keyItem:set_font_color(0xFFFFFFFF);
                    fonts.keyItem:set_text(activity.KeyItem.Name);
                    fonts.keyItem:set_visible(true);

                    -- Icon
                    fonts.icon:set_position_x(cursorX + colIcon);
                    fonts.icon:set_position_y(contentStartY);
                    fonts.icon:set_font_alignment(gdi.Alignment.Left);
                    fonts.icon:set_font_color(statusColor);
                    fonts.icon:set_text(statusIcon);
                    fonts.icon:set_visible(true);

                    -- Timer
                    fonts.timer:set_position_x(cursorX + colTimer);
                    fonts.timer:set_position_y(contentStartY);
                    fonts.timer:set_font_alignment(gdi.Alignment.Left);
                    fonts.timer:set_font_color(color);
                    fonts.timer:set_text(timeText);
                    fonts.timer:set_visible(true);
                end

                contentStartY = contentStartY + rowHeight;
            else
                if fonts then
                    if fonts.activity then fonts.activity:set_visible(false); end
                    if fonts.level then fonts.level:set_visible(false); end
                    if fonts.keyItem then fonts.keyItem:set_visible(false); end
                    if fonts.icon then fonts.icon:set_visible(false); end
                    if fonts.timer then fonts.timer:set_visible(false); end
                end
            end
        end

        -- Force window size to encompass content (title is drawn separately on the border)
        local contentHeight = visibleRows * rowHeight + 5;
        imgui.Dummy({ totalContentWidth, contentHeight });

        local windowSizeX, windowSizeY = imgui.GetWindowSize();

        local theme = gConfig.weekliesBackgroundTheme or 'Window1';
        local bgScale = gConfig.weekliesBgScale or 1.0;
        local borderScale = gConfig.weekliesBorderScale or 1.0;
        local bgOpacity = gConfig.weekliesBackgroundOpacity or 0.87;
        local borderOpacity = gConfig.weekliesBorderOpacity or 1.0;

        windowBg.setTheme(bgHandle, theme, bgScale, borderScale);
        windowBg.update(bgHandle, windowPosX, windowPosY, windowSizeX, windowSizeY, {
            theme = theme,
            padding = 0,
            bgScale = bgScale,
            borderScale = borderScale,
            bgOpacity = bgOpacity,
            borderOpacity = borderOpacity,
            bgColor = 0xFFFFFFFF, -- Default to white for themed backgrounds
            borderColor = 0xFFFFFFFF,
        });
        if titleTexture and titleTexture.image and titleWidth > 0 and titleHeight > 0 then
            local draw_list = imgui.GetForegroundDrawList();
            local texPtr = tonumber(ffi.cast("uint32_t", titleTexture.image));

            local scale = 0.75;
            local drawWidth = titleWidth * scale;
            local drawHeight = titleHeight * scale;

            local titlePosX = windowPosX + math.floor((windowSizeX - drawWidth) / 2);
            local titlePosY = windowPosY - math.floor(drawHeight / 2) + 2;

            draw_list:AddImage(
                texPtr,
                { titlePosX, titlePosY },
                { titlePosX + drawWidth, titlePosY + drawHeight },
                { 0, 0 },
                { 1, 1 },
                IM_COL32_WHITE
            );
        end
    end
    imgui.End();

    if floatingAlertText and os.time() < floatingAlertExpireTime then
        local io = imgui.GetIO();
        local centerX = io.DisplaySize.x / 2;
        local centerY = io.DisplaySize.y / 3;

        imgui.SetNextWindowPos({ centerX, centerY }, ImGuiCond_Always, { 0.5, 0.5 });
        imgui.SetNextWindowBgAlpha(0.0);

        local flags = bit.bor(
            ImGuiWindowFlags_NoTitleBar,
            ImGuiWindowFlags_NoResize,
            ImGuiWindowFlags_NoMove,
            ImGuiWindowFlags_NoScrollbar,
            ImGuiWindowFlags_NoSavedSettings,
            ImGuiWindowFlags_NoInputs,
            ImGuiWindowFlags_AlwaysAutoResize
        );

        if imgui.Begin('WeekliesAlertOverlay', true, flags) then
            imgui.SetWindowFontScale(1.5);
            imgui.PushStyleColor(ImGuiCol_Text, Colors.TimerReady());
            imgui.Text(floatingAlertText);
            imgui.PopStyleColor();
            imgui.SetWindowFontScale(1.0);
        end
        imgui.End();
    elseif floatingAlertText and os.time() >= floatingAlertExpireTime then
        floatingAlertText = nil;
        floatingAlertExpireTime = 0;
    end
end

return M;
