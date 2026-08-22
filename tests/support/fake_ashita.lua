local M = {};
local AVAILABLE_SIGNATURE_ADDRESS = 0x1000;

local table_methods = {};

function table_methods:all(predicate)
    for _, value in pairs(self) do
        if not predicate(value) then
            return false;
        end
    end
    return true;
end

local function table_wrapper(value)
    return setmetatable(value or {}, { __index = table_methods });
end

local function no_op()
end

local function zero()
    return 0;
end

local function callable_table(default_return)
    return setmetatable({}, {
        __index = function(self, key)
            local value = default_return or no_op;
            rawset(self, key, value);
            return value;
        end,
    });
end

local function install_external_modules()
    package.preload['common'] = function()
        _G.T = table_wrapper;
        _G.V = table_wrapper;
        _G.bit = require('bit');
        _G.struct = {
            pack = function()
                return { totable = function() return {}; end };
            end,
        };
        _G.ARGB = zero;
        _G.ARGBToImGui = function() return { 0, 0, 0, 0 }; end;
        _G.ImGuiToARGB = zero;
        return true;
    end;

    package.preload['chat'] = function()
        local message = {};
        function message:append()
            return self;
        end
        return {
            header = function() return message; end,
            message = function(value) return value; end,
            error = function(value) return value; end,
        };
    end;

    package.preload['settings'] = function()
        return {
            load = function(defaults) return defaults; end,
            register = no_op,
            save = no_op,
        };
    end;

    package.preload['imgui'] = function()
        return callable_table(no_op);
    end;

    package.preload['d3d8'] = function()
        return callable_table(no_op);
    end;

    package.preload['bitreader'] = function()
        return { new = function() return {}; end };
    end;

    package.preload['struct'] = function()
        return _G.struct;
    end;

    package.preload['win32types'] = function()
        return true;
    end;

    package.loaded['ffi'] = {
        C = callable_table(zero),
        cdef = no_op,
        cast = zero,
        load = function() return callable_table(zero); end,
        new = function() return {}; end,
        sizeof = zero,
        string = function() return ''; end,
    };
end

function M.install()
    install_external_modules();

    _G.addon = {
        name = 'XIUI',
        path = './XIUI/',
    };

    _G.ashita = {
        bits = callable_table(zero),
        events = { register = no_op },
        fs = {
            exists = function() return false; end,
            get_dir = function() return {}; end,
            get_directory = function() return {}; end,
        },
        memory = {
            find = function() return AVAILABLE_SIGNATURE_ADDRESS; end,
            read_string = function() return ''; end,
            read_uint8 = zero,
            read_uint32 = zero,
            write_uint8 = no_op,
            write_uint32 = no_op,
        },
        misc = { play_sound = no_op },
    };

    _G.AshitaCore = callable_table(function() return callable_table(zero); end);

    setmetatable(_G, {
        __index = function(_, key)
            if type(key) == 'string' and key:match('^ImGui') then
                return 0;
            end
            return nil;
        end,
    });
end

return M;
