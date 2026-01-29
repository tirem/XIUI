--[[
* XIUI Formatting Utilities
* Number and string formatting functions
]]--

local M = {};

-- ========================================
-- Number Formatting
-- ========================================

-- Separate numbers with a delimiter (e.g., 1000000 -> 1,000,000)
function M.SeparateNumbers(val, sep)
    local separated = string.gsub(val, "(%d)(%d%d%d)$", "%1" .. sep .. "%2", 1)
    local found = 0;
    while true do
        separated, found = string.gsub(separated, "(%d)(%d%d%d),", "%1" .. sep .. "%2,", 1)
        if found == 0 then break end
    end
    return separated;
end

-- Format integer with commas
function M.FormatInt(number)
    -- Handle nil or non-number inputs
    if number == nil then
        return '0';
    end

    local i, j, minus, int, fraction = tostring(number):find('([-]?)(%d+)([.]?%d*)')

    -- If pattern didn't match (e.g., "nil" or invalid string), return "0"
    if not int then
        return '0';
    end

    -- Reverse the int-string and append a comma to all blocks of 3 digits
    int = int:reverse():gsub("(%d%d%d)", "%1,")

    -- Reverse the int-string back, remove an optional comma and put the
    -- optional minus and fractional part back
    return minus .. int:reverse():gsub("^,", "") .. fraction
end

-- ========================================
-- String Utilities
-- ========================================

-- Split a string by separator
-- @param str The string to split
-- @param sep The separator (default ":")
-- @return Table of substrings
function M.split(str, sep)
    sep = sep or ":";
    local fields = {};
    local pattern = string.format("([^%s]+)", sep);
    str:gsub(pattern, function(c) fields[#fields + 1] = c end);
    return fields;
end

-- ========================================
-- Misc Utilities
-- ========================================

-- Deep copy a table
function M.deep_copy_table(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[M.deep_copy_table(orig_key)] = M.deep_copy_table(orig_value)
        end
        setmetatable(copy, M.deep_copy_table(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

-- Deep merge target with defaults, preserving existing values
-- Missing keys get defaults; existing values kept; nested tables recursed
function M.DeepMergeWithDefaults(target, defaults)
    if type(defaults) ~= 'table' then return target; end
    if type(target) ~= 'table' then return M.deep_copy_table(defaults); end

    for key, defaultValue in pairs(defaults) do
        local targetValue = target[key];

        if targetValue == nil then
            target[key] = M.deep_copy_table(defaultValue);
        elseif type(defaultValue) == 'table' and type(targetValue) == 'table' then
            M.DeepMergeWithDefaults(targetValue, defaultValue);
        end
    end

    return target;
end

-- Get job abbreviation string from job index
function M.GetJobStr(jobIdx)
    if (jobIdx == nil or jobIdx == 0 or jobIdx == -1) then
        return '';
    end
    return AshitaCore:GetResourceManager():GetString("jobs.names_abbr", jobIdx);
end

return M;
