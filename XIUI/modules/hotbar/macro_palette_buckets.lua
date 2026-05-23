--[[
* Shared macro palette bucket keys (Global / Items / Equipment / XIUI / custom:*).
* Kept in a tiny module so migrations and JSON import do not load macropalette.lua.
]]--

local M = {};

M.GLOBAL = 'global';
M.ITEMS = 'items';
M.EQUIPMENT = 'equipment';
M.XIUI = 'xiui';
M.CUSTOM_PREFIX = 'custom:';

function M.isCustomCategoryKey(k)
    return type(k) == 'string' and k:sub(1, #M.CUSTOM_PREFIX) == M.CUSTOM_PREFIX;
end

function M.isReservedStringBucket(k)
    if k == M.GLOBAL or k == M.ITEMS or k == M.EQUIPMENT or k == M.XIUI then
        return true;
    end
    return M.isCustomCategoryKey(k);
end

return M;
