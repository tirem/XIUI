local M = {};

local function contains(values, wanted)
    for _, value in ipairs(values) do
        if value == wanted then
            return true;
        end
    end
    return false;
end

local function any(value, ...)
    for index = 1, select('#', ...) do
        if value == select(index, ...) then
            return true;
        end
    end
    return false;
end

local table_methods = {
    all = function(self, predicate)
        for _, value in pairs(self) do
            if not predicate(value) then
                return false;
            end
        end
        return true;
    end,
    append = function(self, value)
        self[#self + 1] = value;
        return self;
    end,
    contains = contains,
    each = function(self, callback)
        for key, value in pairs(self) do
            callback(value, key);
        end
        return self;
    end,
};

local table_metatable = { __index = table_methods };

local function T(value)
    return setmetatable(value or {}, table_metatable);
end

function M.install()
    local previous_T = rawget(_G, 'T');
    local previous_contains = table.contains;
    local string_index = getmetatable('').__index;
    local previous_any = string_index.any;

    table.contains = contains;
    string_index.any = any;
    _G.T = T;

    return function()
        _G.T = previous_T;
        table.contains = previous_contains;
        string_index.any = previous_any;
    end;
end

return M;
