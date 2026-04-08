local ffi = require('ffi');
ffi.cdef[[
    int MultiByteToWideChar(uint32_t CodePage, uint32_t dwFlags, char* lpMultiByteStr, int cbMultiByte, wchar_t* lpMultiByteStr, int32_t cchWideChar);
    int WideCharToMultiByte(uint32_t CodePage, uint32_t dwFlags, wchar_t* lpWideCharStr, int32_t cchWideChar, char* lpMultiByteStr, int32_t cbMultiByte, const char* lpDefaultChar, bool* lpUsedDefaultChar);
]]

local exports = T{};

local code_page = {
    utf8 = 65001,
    shiftjis = 932,
};

local converted_str_cache = {};

local function Convert_String(input, codepage_from, codepage_to, cache)
    input = tostring(input or '');
    local source_length = string.len(input);
    if source_length == 0 then
        return input
    end

    -- Check cache
    local cache_key = input .. '|' .. codepage_from .. '>' .. codepage_to;
    if cache == true then
        local cached_str = converted_str_cache[cache_key];
        if cached_str ~= nil then
            return cached_str;
        end
    end

    -- lua string > char[]
    local cbuffer = ffi.new('char[?]', source_length + 1);
    ffi.copy(cbuffer, input);

    -- char[] > wchar_t[]
    local wchar_length = ffi.C.MultiByteToWideChar(codepage_from, 0, cbuffer, -1, nil, 0);
    local wbuffer = ffi.new('wchar_t[?]', wchar_length);
    ffi.C.MultiByteToWideChar(codepage_from, 0, cbuffer, -1, wbuffer, wchar_length);

    -- wchar_t[] > char[]
    local char_length = ffi.C.WideCharToMultiByte(codepage_to, 0, wbuffer, -1, nil, 0, nil, nil);
    cbuffer = ffi.new('char[?]', char_length);
    ffi.C.WideCharToMultiByte(codepage_to, 0, wbuffer, -1, cbuffer, char_length, nil, nil);

    -- Back to lua string
    local new_str = ffi.string(cbuffer);

    -- Add to cache
    if cache == true then
        converted_str_cache[cache_key] = new_str;
    end

    return new_str;
end

function exports:ShiftJIS_To_UTF8(input, cache)
    return Convert_String(input, code_page.shiftjis, code_page.utf8, cache);
end

function exports:UTF8_To_ShiftJIS(input, cache)
    return Convert_String(input, code_page.utf8, code_page.shiftjis, cache);
end

function exports:Clear_String_Cache()
    converted_str_cache = {};
end

return exports;