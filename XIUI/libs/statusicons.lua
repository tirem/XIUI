--[[
* XIUI Status Icons Utilities
* Drawing status/buff/debuff icons
]]--

require('common');
local imgui = require('imgui');
local gdi = require('submodules.gdifonts.include');

local M = {};

-- ========================================
-- Status Reordering (debuffs closest to party frame)
-- ========================================

-- Reusable tables to avoid allocations every frame
local reorderedStatuses = {};
local reorderedTimes = {};

-- Reorder status IDs so debuffs are closest to the party frame
-- @param statusIds: array of status IDs
-- @param buffTableLib: the bufftable module with IsBuff function
-- @param statusSide: 0 = Left (debuffs on right), 1 = Right (debuffs on left)
-- @param statusTimes: optional array of status times (parallel to statusIds)
-- @return: reordered array with debuffs positioned closest to party frame, and optionally reordered times
function M.ReorderForStatusSide(statusIds, buffTableLib, statusSide, statusTimes)
    if statusIds == nil or #statusIds == 0 then
        return statusIds, statusTimes;
    end

    -- Clear reusable tables
    for k in pairs(reorderedStatuses) do reorderedStatuses[k] = nil; end
    if statusTimes then
        for k in pairs(reorderedTimes) do reorderedTimes[k] = nil; end
    end

    local debuffIdx = 1;
    local buffIdx = 1;
    local debuffs = {};
    local buffs = {};
    local debuffTimes = {};
    local buffTimes = {};

    -- Separate debuffs and buffs (and their times if provided)
    for i = 1, #statusIds do
        local id = statusIds[i];
        if id == -1 or id == 255 then
            break;
        end
        if buffTableLib.IsBuff(id) then
            buffs[buffIdx] = id;
            if statusTimes then
                buffTimes[buffIdx] = statusTimes[i];
            end
            buffIdx = buffIdx + 1;
        else
            debuffs[debuffIdx] = id;
            if statusTimes then
                debuffTimes[debuffIdx] = statusTimes[i];
            end
            debuffIdx = debuffIdx + 1;
        end
    end

    -- Order based on statusSide so debuffs are always closest to party frame
    -- statusSide 0 (Left): icons to left of party frame, debuffs should be rightmost (last)
    --                      Also reverse debuff order so first debuff is rightmost
    -- statusSide 1 (Right): icons to right of party frame, debuffs should be leftmost (first)
    local idx = 1;
    if statusSide == 0 then
        -- Left side: buffs first (left), debuffs last in reverse order (right, closer to party frame)
        -- Reverse buffs so first buff is closest to debuffs
        for i = #buffs, 1, -1 do
            reorderedStatuses[idx] = buffs[i];
            if statusTimes then
                reorderedTimes[idx] = buffTimes[i];
            end
            idx = idx + 1;
        end
        -- Reverse debuffs so first debuff (e.g. poison) is rightmost (closest to party frame)
        for i = #debuffs, 1, -1 do
            reorderedStatuses[idx] = debuffs[i];
            if statusTimes then
                reorderedTimes[idx] = debuffTimes[i];
            end
            idx = idx + 1;
        end
    else
        -- Right side: debuffs first (left, closer to party frame), buffs last (right)
        for i = 1, #debuffs do
            reorderedStatuses[idx] = debuffs[i];
            if statusTimes then
                reorderedTimes[idx] = debuffTimes[i];
            end
            idx = idx + 1;
        end
        for i = 1, #buffs do
            reorderedStatuses[idx] = buffs[i];
            if statusTimes then
                reorderedTimes[idx] = buffTimes[i];
            end
            idx = idx + 1;
        end
    end

    if statusTimes then
        return reorderedStatuses, reorderedTimes;
    end
    return reorderedStatuses;
end

-- Convenience wrapper for debuffs-first ordering (for target bar, etc.)
function M.ReorderDebuffsFirst(statusIds, buffTableLib, statusTimes)
    return M.ReorderForStatusSide(statusIds, buffTableLib, 1, statusTimes);
end

-- Reusable tables for buffs-closest ordering
local reorderedStatusesBuffs = {};
local reorderedTimesBuffs = {};

-- Reorder status IDs so buffs are closest to the party frame (opposite of ReorderForStatusSide)
-- @param statusIds: array of status IDs
-- @param buffTableLib: the bufftable module with IsBuff function
-- @param statusSide: 0 = Left (buffs on right), 1 = Right (buffs on left)
-- @param statusTimes: optional array of status times (parallel to statusIds)
-- @return: reordered array with buffs positioned closest to party frame, and optionally reordered times
function M.ReorderBuffsClosest(statusIds, buffTableLib, statusSide, statusTimes)
    if statusIds == nil or #statusIds == 0 then
        return statusIds, statusTimes;
    end

    -- Clear reusable tables
    for k in pairs(reorderedStatusesBuffs) do reorderedStatusesBuffs[k] = nil; end
    if statusTimes then
        for k in pairs(reorderedTimesBuffs) do reorderedTimesBuffs[k] = nil; end
    end

    local debuffIdx = 1;
    local buffIdx = 1;
    local debuffs = {};
    local buffs = {};
    local debuffTimes = {};
    local buffTimes = {};

    -- Separate debuffs and buffs (and their times if provided)
    for i = 1, #statusIds do
        local id = statusIds[i];
        if id == -1 or id == 255 then
            break;
        end
        if buffTableLib.IsBuff(id) then
            buffs[buffIdx] = id;
            if statusTimes then
                buffTimes[buffIdx] = statusTimes[i];
            end
            buffIdx = buffIdx + 1;
        else
            debuffs[debuffIdx] = id;
            if statusTimes then
                debuffTimes[debuffIdx] = statusTimes[i];
            end
            debuffIdx = debuffIdx + 1;
        end
    end

    -- Order based on statusSide so buffs are always closest to party frame
    -- statusSide 0 (Left): icons to left of party frame, buffs should be rightmost (last)
    -- statusSide 1 (Right): icons to right of party frame, buffs should be leftmost (first)
    local idx = 1;
    if statusSide == 0 then
        -- Left side: debuffs first (left, far), buffs last in reverse order (right, closer to party frame)
        for i = #debuffs, 1, -1 do
            reorderedStatusesBuffs[idx] = debuffs[i];
            if statusTimes then
                reorderedTimesBuffs[idx] = debuffTimes[i];
            end
            idx = idx + 1;
        end
        -- Reverse buffs so first buff is rightmost (closest to party frame)
        for i = #buffs, 1, -1 do
            reorderedStatusesBuffs[idx] = buffs[i];
            if statusTimes then
                reorderedTimesBuffs[idx] = buffTimes[i];
            end
            idx = idx + 1;
        end
    else
        -- Right side: buffs first (left, closer to party frame), debuffs last (right)
        for i = 1, #buffs do
            reorderedStatusesBuffs[idx] = buffs[i];
            if statusTimes then
                reorderedTimesBuffs[idx] = buffTimes[i];
            end
            idx = idx + 1;
        end
        for i = 1, #debuffs do
            reorderedStatusesBuffs[idx] = debuffs[i];
            if statusTimes then
                reorderedTimesBuffs[idx] = debuffTimes[i];
            end
            idx = idx + 1;
        end
    end

    if statusTimes then
        return reorderedStatusesBuffs, reorderedTimesBuffs;
    end
    return reorderedStatusesBuffs;
end

-- ========================================
-- Debuff Font Cache
-- ========================================
local debuffTable = T{};

local debuff_font_settings = T{
    font_alignment = gdi.Alignment.Center,
    font_family = 'Consolas',
    font_height = 14,
    font_color = 0xFFFFFFFF,
    font_flags = gdi.FontFlags.Bold,
    outline_color = 0xFF000000,
    outline_width = 2,
};

-- ========================================
-- Status Icon Drawing
-- ========================================

-- Draw status icons with optional backgrounds and timers
-- @param statusIds: array of status IDs to draw
-- @param iconSize: size of each icon in pixels
-- @param maxColumns: max icons per row
-- @param maxRows: max rows to display
-- @param drawBg: whether to draw background behind icons
-- @param xOffset: horizontal offset for positioning
-- @param buffTimes: optional array of remaining buff times
-- @param settings: optional font settings override
-- @param statusHandler: the statushandler module
-- @param buffTable: the bufftable module
function M.DrawStatusIcons(statusIds, iconSize, maxColumns, maxRows, drawBg, xOffset, buffTimes, settings, statusHandler, buffTableLib)
    if (statusIds ~= nil and #statusIds > 0) then
        local currentRow = 1;
        local currentColumn = 0;
        if (xOffset ~= nil) then
            imgui.SetCursorPosX(imgui.GetCursorPosX() + xOffset);
        end
        for i = 1, #statusIds do
            -- Don't check anymore after -1, as it will be all -1's
            if (statusIds[i] == -1) then
                break;
            end
            local icon = statusHandler.get_icon_from_theme(gConfig.statusIconTheme, statusIds[i]);
            if (icon ~= nil) then
                if (drawBg == true) then
                    local resetX, resetY = imgui.GetCursorScreenPos();
                    local bgIcon;
                    local isBuff = buffTableLib.IsBuff(statusIds[i]);
                    local bgSize = iconSize * 1.1;
                    local yOffset = bgSize * -0.1;
                    if (isBuff) then
                        yOffset = bgSize * -0.3;
                    end
                    imgui.SetCursorScreenPos({resetX - ((bgSize - iconSize) / 1.5), resetY + yOffset});
                    bgIcon = statusHandler.GetBackground(isBuff);
                    imgui.Image(bgIcon, { bgSize + 1, bgSize  / .75});
                    imgui.SetCursorScreenPos({resetX, resetY});
                end
                -- Capture position BEFORE drawing icon to get accurate position
                local iconPosX, iconPosY = imgui.GetCursorScreenPos();
                imgui.Image(icon, { iconSize, iconSize }, { 0, 0 }, { 1, 1 });
                local textObjName = "debuffText" .. tostring(i)
                if buffTimes ~= nil then
                    -- Calculate center of the icon for text positioning
                    local textPosX = iconPosX + iconSize / 2
                    local textPosY = iconPosY + iconSize  -- Move text below the icon

                    local textObj = debuffTable[textObjName]
                    -- Use passed settings if available, otherwise use default
                    local font_base = settings or debuff_font_settings;
                    if (textObj == nil) then
                        local font_settings = T{
                            font_alignment = font_base.font_alignment,
                            font_family = gConfig.fontFamily,
                            font_height = font_base.font_height,
                            font_color = font_base.font_color,
                            font_flags = font_base.font_flags,
                            outline_color = font_base.outline_color,
                            outline_width = font_base.outline_width,
                        };
                        textObj = gdi:create_object(font_settings)
                        debuffTable[textObjName] = textObj
                    end
                    local scaledFontHeight = gConfig.targetBarIconFontSize or font_base.font_height;
                    textObj:set_font_height(scaledFontHeight)
                    textObj:set_text('')
                    if buffTimes[i] ~= nil then
                        -- Text is center-aligned, so just use the calculated center position
                        textObj:set_position_x(textPosX)
                        textObj:set_position_y(textPosY)
                        textObj:set_text(tostring(buffTimes[i]))
                        textObj:set_visible(true);
                    end
                end
                if (imgui.IsItemHovered()) then
                    statusHandler.render_tooltip(statusIds[i]);
                end
                currentColumn = currentColumn + 1;
                -- Handle multiple rows
                if (currentColumn < maxColumns) then
                    imgui.SameLine();
                else
                    currentRow = currentRow + 1;
                    if (currentRow > maxRows) then
                        return;
                    end
                    if (xOffset ~= nil) then
                        imgui.SetCursorPosX(imgui.GetCursorPosX() + xOffset);
                    end
                    currentColumn = 0;
                end
            end
        end
    end
end

-- ========================================
-- Font Cache Management
-- ========================================

function M.ClearDebuffFontCache()
    -- Destroy all gdi font objects and clear entries
    -- Important: Clear entries in-place instead of reassigning the table
    -- to preserve the reference held by handlers/helpers.lua global export
    for key, textObj in pairs(debuffTable) do
        if textObj ~= nil then
            gdi:destroy_object(textObj);
        end
        debuffTable[key] = nil;
    end
end

-- Get the debuff table (for external access if needed)
function M.GetDebuffTable()
    return debuffTable;
end

return M;
