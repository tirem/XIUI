local M = {};

local INSTALL_PATH = 'C:\\Ashita\\';
local CONFIG_PATH = INSTALL_PATH .. 'config\\addons\\xiui\\';
local PROFILES_PATH = CONFIG_PATH .. 'profiles\\';
local BACKUPS_PATH = CONFIG_PATH .. 'backups\\';
local PROFILE_LIST_PATH = PROFILES_PATH .. 'profilelist.lua';
local DEFAULT_PROFILE_PATH = PROFILES_PATH .. 'Default.lua';
local SOURCE_ROOT = 'XIUI/';
local UNKNOWN_READ_ERROR = 'path is outside the startup test filesystem';

local initial_files = {
    [PROFILE_LIST_PATH] = {
        value = { version = '1.8.4', names = { 'Default' }, order = { 'Default' } },
    },
    [DEFAULT_PROFILE_PATH] = { value = {} },
};

local function deep_copy(value)
    if type(value) ~= 'table' then
        return value;
    end

    local result = {};
    for key, item in pairs(value) do
        result[deep_copy(key)] = deep_copy(item);
    end
    return result;
end

local function fake_writer()
    return {
        close = function()
            return true;
        end,
        flush = function()
            return true;
        end,
        write = function(self)
            return self;
        end,
    };
end

function M.new(mutation_log)
    local original_dofile = dofile;
    local original_loadfile = loadfile;
    local original_io_open = io.open;
    local original_remove = os.remove;
    local original_rename = os.rename;

    local existing_paths = {
        [CONFIG_PATH] = true,
        [PROFILES_PATH] = true,
        [BACKUPS_PATH] = true,
        [PROFILE_LIST_PATH] = true,
        [DEFAULT_PROFILE_PATH] = true,
    };

    local function get_directory(path)
        if path == PROFILES_PATH then
            return { 'profilelist.lua', 'Default.lua' };
        end
        return {};
    end

    local ashita_fs = {
        exists = function(path)
            return existing_paths[path] == true;
        end,
        get_directory = get_directory,
        get_dir = get_directory,
        create_directory = function(path)
            mutation_log[#mutation_log + 1] = { operation = 'mkdir', path = path };
            return true;
        end,
        create_dir = function(path)
            mutation_log[#mutation_log + 1] = { operation = 'mkdir', path = path };
            return true;
        end,
    };

    local function is_source_path(path)
        local normalized = tostring(path):gsub('\\', '/');
        if normalized:sub(1, #SOURCE_ROOT) ~= SOURCE_ROOT or normalized:sub(-4) ~= '.lua' then
            return false;
        end
        for segment in normalized:gmatch('[^/]+') do
            if segment == '.' or segment == '..' then
                return false;
            end
        end
        return true;
    end

    _G.loadfile = function(path, ...)
        local file = initial_files[path];
        if file ~= nil then
            return function()
                return deep_copy(file.value);
            end;
        end
        if is_source_path(path) then
            return original_loadfile(path, ...);
        end
        return nil, UNKNOWN_READ_ERROR;
    end;

    _G.dofile = function(path)
        local chunk, err = loadfile(path);
        if chunk == nil then
            error(err, 2);
        end
        return chunk();
    end;

    io.open = function(path, mode)
        local requested_mode = mode or 'r';
        if requested_mode:find('[wa+]') ~= nil then
            mutation_log[#mutation_log + 1] = {
                operation = 'open',
                path = path,
                mode = requested_mode,
            };
            return fake_writer();
        end
        return nil, UNKNOWN_READ_ERROR;
    end;

    os.remove = function(path)
        mutation_log[#mutation_log + 1] = { operation = 'remove', path = path };
        return true;
    end;

    os.rename = function(source, destination)
        mutation_log[#mutation_log + 1] = {
            operation = 'rename',
            source = source,
            destination = destination,
        };
        return true;
    end;

    return {
        install_path = INSTALL_PATH,
        ashita_fs = ashita_fs,
        restore = function()
            _G.dofile = original_dofile;
            _G.loadfile = original_loadfile;
            io.open = original_io_open;
            os.remove = original_remove;
            os.rename = original_rename;
        end,
    };
end

return M;
