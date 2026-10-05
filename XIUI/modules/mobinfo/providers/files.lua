-- Generated Lua snapshots keep upstream parsing out of the game client.
local files = {};

files.LoadZone = function(provider, zoneId)
    local path = string.format('%s/data/mobs/%s/%d.lua', addon.path, provider, zoneId);
    local file = io.open(path, 'r');
    if not file then return nil; end
    file:close();

    local chunk, err = loadfile(path);
    if not chunk then
        print('[XIUI] Error loading mob data: ' .. tostring(err));
        return nil;
    end
    local success, result = pcall(chunk);
    if not success or type(result) ~= 'table' or type(result.Names) ~= 'table' or type(result.Indices) ~= 'table' then
        print('[XIUI] Invalid mob data for ' .. provider .. ' zone ' .. tostring(zoneId));
        return nil;
    end
    return result;
end

return files;
