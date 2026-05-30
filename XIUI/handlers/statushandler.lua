-- Pulled from statustimers - Copyright (c) 2022 Heals

-------------------------------------------------------------------------------
-- imports
-------------------------------------------------------------------------------
local ffi = require('ffi');
local imgui = require('imgui');
local encoding = require('libs.encoding');
local TextureManager = require('libs.texturemanager');
local imtext = require('libs.imtext');

-- Party buffs table, populated by packet 0x076 via ReadPartyBuffsFromPacket()
local partyBuffs = {};

local LEVEL_SYNC_BUFF_ID = 269;

local function partyBuffListHas(buffList, statusId)
    if not buffList then return false; end
    for i = 1, #buffList do
        if buffList[i] == statusId then
            return true;
        end
    end
    return false;
end

-------------------------------------------------------------------------------
-- exported functions
-------------------------------------------------------------------------------
local statusHandler = {};

-- return a list of all sub directories
---@return table theme_paths
statusHandler.get_job_theme_paths = function()
    local path = ('%s\\addons\\%s\\assets\\jobs\\'):fmt(AshitaCore:GetInstallPath(), 'XIUI');
    local directories = ashita.fs.get_directory(path);
    if (directories ~= nil) then
        directories[#directories+1] = '-None-';
        return directories;
    end
    return T{'-None-'};
end

-- render the tooltip for a specific status id
---@param status number the status id
---@param is_target boolean if true, don't show '(right click to cancel)' hint
statusHandler.render_tooltip = function(status)
    if (status == nil or status < 1 or status > 0x3FF or status == 255) then
        return;
    end

    local resMan = AshitaCore:GetResourceManager();
    local info = resMan:GetStatusIconByIndex(status);
    local name = resMan:GetString('buffs.names', status);
    if (name == nil or info == nil) then return; end

    local nameStr = encoding:ShiftJIS_To_UTF8(name, true);
    local descStr = (info.Description[1] ~= nil) and encoding:ShiftJIS_To_UTF8(info.Description[1], true) or nil;

    -- Draw directly on the foreground draw list.  This draw list is always
    -- composited after every ImGui window (it is literally the "top layer"),
    -- so the tooltip cannot be occluded by the party-list window even though
    -- that window uses ImGuiWindowFlags_NoBringToFrontOnFocus.
    local dl = imgui.GetForegroundDrawList();
    if not dl then return; end

    local fontSize    = 13;
    local maxWrapPx   = 260;
    local pad         = 8;
    local lineSpacing = fontSize + 4;

    -- configure imtext for measurement + drawing (Tahoma, no bold, outline width 1)
    imtext.SetConfig('Tahoma', false, 1);

    -- name header
    local nameLabel = string.format('%s (#%d)', nameStr, status);
    local nameW = imtext.Measure(nameLabel, fontSize);

    -- word-wrap description into lines
    local descLines = {};
    if descStr and #descStr > 0 then
        local words = {};
        for w in descStr:gmatch('[^%s]+') do words[#words + 1] = w; end
        local cur = '';
        for _, word in ipairs(words) do
            local candidate = (cur == '') and word or (cur .. ' ' .. word);
            local tw = imtext.Measure(candidate, fontSize);
            if tw > maxWrapPx and cur ~= '' then
                descLines[#descLines + 1] = cur;
                cur = word;
            else
                cur = candidate;
            end
        end
        if cur ~= '' then descLines[#descLines + 1] = cur; end
    end

    -- measure widest line
    local contentW = nameW;
    for _, l in ipairs(descLines) do
        local lw = imtext.Measure(l, fontSize);
        if lw > contentW then contentW = lw; end
    end

    local separatorH = (#descLines > 0) and (pad * 0.5) or 0;
    local boxH = pad + lineSpacing + separatorH + #descLines * lineSpacing + pad;
    local boxW = contentW + pad * 2;

    -- position near cursor; standard tooltip offset (right + slightly down)
    local mx, my = imgui.GetMousePos();
    local ox = mx + 14;
    local oy = my + 4;

    -- background + border
    local bgCol     = imgui.GetColorU32({0.06, 0.06, 0.07, 0.92});
    local borderCol = imgui.GetColorU32({0.45, 0.45, 0.45, 1.0});
    dl:AddRectFilled({ox, oy}, {ox + boxW, oy + boxH}, bgCol, 4);
    dl:AddRect({ox, oy}, {ox + boxW, oy + boxH}, borderCol, 4, nil, 1.0);

    -- name line (white)
    imtext.Draw(dl, nameLabel, ox + pad, oy + pad, 0xFFFFFFFF, fontSize);

    -- description lines (light grey)
    if #descLines > 0 then
        local textY = oy + pad + lineSpacing + separatorH;
        for _, l in ipairs(descLines) do
            imtext.Draw(dl, l, ox + pad, textY, 0xFFCCCCCC, fontSize);
            textY = textY + lineSpacing;
        end
    end
end

-- return a list of all sub directories
---@return table theme_paths
statusHandler.get_status_theme_paths = function()
    local path = ('%s\\addons\\%s\\assets\\status\\'):fmt(AshitaCore:GetInstallPath(), 'XIUI');
    local directories = ashita.fs.get_directory(path);
    if (directories ~= nil) then
        directories[#directories+1] = '-Default-';
        return directories;
    end
    return T{'-Default-'};
end 

-- return a list of all sub directories
---@return table theme_paths
statusHandler.get_background_paths = function()
    local path = ('%s\\addons\\%s\\assets\\backgrounds\\'):fmt(AshitaCore:GetInstallPath(), 'XIUI');
    local directories = ashita.fs.get_dir(path, '.*.png', true);
    if (directories ~= nil) then
        local backgrounds = { '-None-' };
        for _, filename in ipairs(directories) do
            local bg_name = filename:match('(.+)%-bg.png');
            if bg_name ~= nil then
                table.insert(backgrounds, bg_name);
            end
        end
        return backgrounds;
    end
    return T{};
end 

-- return a list of all sub directories
---@return table theme_paths
statusHandler.get_cursor_paths = function()
    local path = ('%s\\addons\\%s\\assets\\cursors\\'):fmt(AshitaCore:GetInstallPath(), 'XIUI');
    local directories = ashita.fs.get_dir(path, '.*.png', true);
    if (directories ~= nil) then
        return directories;
    end
    return T{};
end 

-- return an image pointer for a status_id for use with imgui.Image
---@param status_id number the status id number of the requested icon
---@return number texture_ptr_id a number representing the texture_ptr or nil
statusHandler.get_icon_image = function(status_id)
    local texture = TextureManager.getStatusIcon(status_id, nil);
    return TextureManager.getTexturePtr(texture);
end

-- return an image pointer for a status_id for use with imgui.Image
---@param theme string the name of the theme directory
---@param status_id number the status id number of the requested icon
---@return number texture_ptr_id a number representing the texture_ptr or nil
statusHandler.get_icon_from_theme = function(theme, status_id)
    local texture = TextureManager.getStatusIcon(status_id, theme);
    return TextureManager.getTexturePtr(texture);
end

-- reset the icon cache and release all resources
-- Note: Cache is now managed centrally by TextureManager
statusHandler.clear_cache = function()
    -- Status icon cache is managed by TextureManager
    -- This function is kept for backwards compatibility
    -- TextureManager.clearCategory('status_icons') can be called if needed
end;

-- Clear status icon cache on zone change to prevent unbounded accumulation
-- Preserves job icons since those are reused across zones
-- Preserves buff/debuff background icons as they're constant
statusHandler.clear_zone_cache = function()
    icon_cache = T{};
end;

-- return a table of status ids for a party member based on server id.
---@param server_id number the party memer or target server id to check
---@return table status_ids a list of the targets status ids or nil
statusHandler.get_member_status = function(server_id)
    return partyBuffs[server_id];
end

statusHandler.GetBackground = function(isBuff)
    local textureName = isBuff and "BuffIcon" or "DebuffIcon";
    local texture = TextureManager.getFileTexture(textureName);
    return TextureManager.getTexturePtr(texture);
end

statusHandler.GetJobIcon = function(jobIdx)
    if (jobIdx == nil or jobIdx == 0 or jobIdx == -1) then
        return nil;
    end
    local theme = gConfig.jobIconTheme or 'Classic';
    local texture = TextureManager.getJobIcon(jobIdx, theme);
    return TextureManager.getTexturePtr(texture);
end

--Call with incoming packet 0x076
statusHandler.ReadPartyBuffsFromPacket = function(e)
    local partyBuffTable = {};
    for i = 0,4 do
        local memberOffset = 0x04 + (0x30 * i) + 1;
        local memberId = struct.unpack('L', e.data, memberOffset);
        if memberId > 0 then
            local buffs = {};
            local empty = false;
            for j = 0,31 do
                if empty then
                    buffs[j + 1] = -1;
                else
                    --This is at offset 8 from member start.. memberoffset is using +1 for the lua struct.unpacks
                    local highBits = bit.lshift(ashita.bits.unpack_be(e.data_raw, memberOffset + 7, j * 2, 2), 8);
                    local lowBits = struct.unpack('B', e.data, memberOffset + 0x10 + j);
                    local buff = highBits + lowBits;
                    if (buff == 255) then
                        buffs[j + 1] = -1;
                        empty = true;
                    else
                        buffs[j + 1] = buff;
                    end
                end
            end
            partyBuffTable[memberId] = buffs;
        end
    end

    local hadLevelSync = false;
    local hasLevelSync = false;
    local memMgr = AshitaCore:GetMemoryManager();
    local party = memMgr and memMgr:GetParty();
    if party and party:GetMemberIsActive(0) == 1 then
        local sid = party:GetMemberServerId(0);
        if sid and sid > 0 then
            hadLevelSync = partyBuffListHas(partyBuffs[sid], LEVEL_SYNC_BUFF_ID);
            hasLevelSync = partyBuffListHas(partyBuffTable[sid], LEVEL_SYNC_BUFF_ID);
        end
    end

    partyBuffs = partyBuffTable;

    if hadLevelSync ~= hasLevelSync then
        pcall(function()
            local playerdata = require('modules.hotbar.playerdata');
            if playerdata.ClearCache then
                playerdata.ClearCache();
            end
        end);
        pcall(function()
            local slotrenderer = require('modules.hotbar.slotrenderer');
            if slotrenderer.ClearAvailabilityCache then
                slotrenderer.ClearAvailabilityCache();
            end
        end);
    end

    -- Pre-warm status icon textures for all buff IDs seen in this packet.
    -- This runs on the packet handler, not the render thread, so disk I/O here
    -- doesn't stall d3d_present. Without this, each uncached icon fires a
    -- synchronous D3DXCreateTextureFromFile on the first render frame after a
    -- party member joins, which is the main cause of the one-frame stutter.
    pcall(function()
        local theme = gConfig and gConfig.partyA and gConfig.partyA.statusTheme;
        -- statusTheme 0/1 both show icons; non-zero means a named theme folder.
        local themeName = (theme and theme ~= 0 and theme ~= '') and theme or nil;
        for _, buffList in pairs(partyBuffTable) do
            for _, sid in ipairs(buffList) do
                if sid and sid > 0 and sid ~= 255 and sid ~= -1 then
                    TextureManager.getStatusIcon(sid, themeName);
                end
            end
        end
    end);
end

return statusHandler;
