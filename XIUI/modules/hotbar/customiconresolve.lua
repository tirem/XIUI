--[[
 * Resolve assets/hotbar/custom/*.png paths by action name — same rules as the macro editor
 * icon picker (recursive scan + name match). Used when textures:GetIconBySpellName misses
 * (e.g. Ashita fs patterns differ) so /ja badges and binds still find FFXIV-style icons.
]]--

require('common');
local iconmatch = require('modules.hotbar.iconmatch');

local M = {};

local customIconsDir = nil;
local iconListCache = nil;

local function getCustomIconsDir()
    if not customIconsDir then
        customIconsDir = string.format('%saddons\\XIUI\\assets\\hotbar\\custom\\', AshitaCore:GetInstallPath());
    end
    return customIconsDir;
end

-- Recursively collect PNGs (same approach as macropalette LoadCustomIcons).
local function scanDirectoryForPngs(dir, relativePath, results, topLevelCategory)
    relativePath = relativePath or '';
    results = results or {};

    if not ashita.fs or not ashita.fs.get_directory then
        return results;
    end

    local contents = ashita.fs.get_directory(dir, '.*');
    if not contents then
        return results;
    end

    for _, entry in pairs(contents) do
        local relPath = relativePath ~= '' and (relativePath .. '\\' .. entry) or entry;

        if entry:lower():match('%.png$') then
            local category = topLevelCategory or 'root';
            table.insert(results, {
                name = entry:gsub('%.png$', ''),
                path = relPath,
                category = category,
            });
        elseif not entry:match('%.') then
            local categoryForNested = topLevelCategory or entry;
            scanDirectoryForPngs(dir .. entry .. '\\', relPath, results, categoryForNested);
        end
    end

    return results;
end

local function ensureIconList()
    if iconListCache then
        return iconListCache;
    end
    iconListCache = scanDirectoryForPngs(getCustomIconsDir());
    table.sort(iconListCache, function(a, b)
        return a.name:lower() < b.name:lower();
    end);
    return iconListCache;
end

local function paletteNormalizeIconMatchText(s)
    if not s then
        return '';
    end
    s = tostring(s):lower();
    s = s:gsub('^%s+', ''):gsub('%s+$', '');
    s = s:gsub('[\r\n\t]', ' ');
    s = s:gsub('[%p%c%s]', '');
    return s;
end

local function paletteBuildIconMatchNeedles(actionName)
    actionName = tostring(actionName or '');
    if actionName == '' then
        return {};
    end

    local needles = {};
    local function add(n)
        n = paletteNormalizeIconMatchText(n);
        if n ~= '' then
            needles[n] = true;
        end
    end

    local fullNorm = paletteNormalizeIconMatchText(actionName);
    add(actionName);
    local rhs = actionName:match(':%s*(.+)$');
    if rhs then
        add(rhs);
    end
    local paren = actionName:match('%(([^)]+)%)');
    if paren then
        add(paren);
    end
    local lastWord = actionName:match('([^%s]+)%s*$');
    if lastWord then
        local lwNorm = paletteNormalizeIconMatchText(lastWord);
        if lwNorm ~= '' and lwNorm ~= fullNorm then
            local weakTail = (#lwNorm < 9 and #fullNorm > #lwNorm + 4 and fullNorm:sub(-#lwNorm) == lwNorm);
            if not weakTail then
                add(lastWord);
            end
        end
    end

    local arr = {};
    for n, _ in pairs(needles) do
        table.insert(arr, n);
    end
    table.sort(arr, function(a, b)
        return #a > #b;
    end);
    return arr;
end

--- @param categoryFilter string|nil 'all' or top-level folder name (e.g. 'ffxiv'); default 'all'
--- @return string|nil Relative path under assets/hotbar/custom/ (uses \), or nil
function M.FindRelPathForActionName(actionName, categoryFilter)
    actionName = tostring(actionName or '');
    if actionName == '' then
        return nil;
    end

    local list = ensureIconList();
    if not list or #list == 0 then
        return nil;
    end

    categoryFilter = categoryFilter or 'all';
    local filtered = list;
    if categoryFilter ~= 'all' then
        filtered = {};
        for _, icon in ipairs(list) do
            if icon.category == categoryFilter then
                table.insert(filtered, icon);
            end
        end
        if #filtered == 0 then
            filtered = list;
        end
    end

    local needles = paletteBuildIconMatchNeedles(actionName);
    if #needles == 0 then
        return nil;
    end

    for _, icon in ipairs(filtered) do
        if icon and icon.name and icon.path then
            local iconNorm = paletteNormalizeIconMatchText(icon.name);
            for _, needle in ipairs(needles) do
                if iconNorm == needle then
                    return icon.path;
                end
            end
        end
    end

    local fuzzy = {};
    for _, icon in ipairs(filtered) do
        if icon and icon.name and icon.path and iconmatch.IsDecentIconNameMatch(actionName, icon.name) then
            table.insert(fuzzy, icon);
        end
    end
    if #fuzzy == 1 then
        return fuzzy[1].path;
    end
    if #fuzzy > 1 then
        table.sort(fuzzy, function(x, y)
            local sx = iconmatch.MatchQualityScore(actionName, x.name);
            local sy = iconmatch.MatchQualityScore(actionName, y.name);
            if sx ~= sy then
                return sx > sy;
            end
            return #iconmatch.NormalizeIconKey(x.name) > #iconmatch.NormalizeIconKey(y.name);
        end);
        return fuzzy[1].path;
    end

    return nil;
end

--- Call after adding/removing PNGs under hotbar/custom (or reload) so the next lookup rescans disk.
function M.InvalidateScanCache()
    iconListCache = nil;
end

return M;
