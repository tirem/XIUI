local fake_ashita = require('support.fake_ashita');
local fake_clock = require('support.fake_clock');
local fake_common = require('support.fake_common');
local fake_d3d8 = require('support.fake_d3d8');
local fake_filesystem = require('support.fake_filesystem');
local fake_imgui = require('support.fake_imgui');
local fake_packets = require('support.fake_packets');
local native_ffi = require('ffi');

local M = {};

local function copy_table(values)
    local copy = {};
    for key, value in pairs(values) do
        copy[key] = value;
    end
    return copy;
end

local function deep_copy(value)
    if type(value) ~= 'table' then
        return value;
    end

    local copy = {};
    for key, item in pairs(value) do
        copy[deep_copy(key)] = deep_copy(item);
    end
    return copy;
end

local function restore_table(target, snapshot)
    for key in pairs(target) do
        target[key] = nil;
    end
    for key, value in pairs(snapshot) do
        target[key] = value;
    end
end

local function restore_globals(snapshot)
    for key, value in pairs(snapshot) do
        _G[key] = value;
    end
    for key in pairs(_G) do
        if snapshot[key] == nil then
            _G[key] = nil;
        end
    end
end

local function chat_value(value)
    local result = { tostring(value or '') };
    return setmetatable(result, {
        __index = {
            append = function(self, appended)
                self[#self + 1] = tostring(appended);
                return self;
            end,
        },
        __tostring = function(self)
            return table.concat(self);
        end,
    });
end

local function new_chat()
    return {
        error = chat_value,
        header = chat_value,
        message = chat_value,
        success = chat_value,
    };
end

local function new_settings(logs)
    return {
        load = function(defaults)
            local loaded = deep_copy(defaults or {});
            loaded.currentProfile = 'Default';
            return loaded;
        end,
        register = function(name, key)
            logs.host_calls[#logs.host_calls + 1] = {
                operation = 'settings.register',
                arguments = { name, key },
            };
        end,
        save = function()
            logs.settings_saves[#logs.settings_saves + 1] = {};
            return true;
        end,
    };
end

local function new_struct()
    return {
        pack = function()
            return {
                totable = function()
                    return {};
                end,
            };
        end,
        unpack = function()
            return 0;
        end,
    };
end

function M.with_environment(options, run)
    options = options or {};
    local package_path = package.path;
    local loaded_snapshot = copy_table(package.loaded);
    local preload_snapshot = copy_table(package.preload);
    local global_snapshot = copy_table(_G);
    local restores = {};
    local initializer_restores = {};

    local logs = {
        events = {},
        filesystem_mutations = {},
        host_calls = {},
        initializer_calls = {},
        invoked_events = {},
        memory_scans = {},
        packets = {},
        settings_saves = {},
        winmm_loads = {},
    };

    local function install_restore(restore)
        restores[#restores + 1] = restore;
    end

    local common_restore = fake_common.install();
    install_restore(common_restore);
    install_restore(fake_clock.install(1724371200, 10));

    local filesystem = fake_filesystem.new(logs.filesystem_mutations);
    install_restore(filesystem.restore);

    local imgui, imgui_restore = fake_imgui.install();
    install_restore(imgui_restore);

    local packets = fake_packets.new(logs.packets);
    local callbacks, ashita_restore, ashita_controls = fake_ashita.install(options, logs, filesystem, packets);
    install_restore(ashita_restore);

    local struct = new_struct();
    _G.addon = { path = 'XIUI\\', name = 'XIUI' };
    _G.struct = struct;

    package.preload.common = function()
        return true;
    end;
    package.preload.chat = function()
        return new_chat();
    end;
    package.preload.settings = function()
        return new_settings(logs);
    end;
    package.preload.imgui = function()
        return imgui;
    end;
    package.preload.d3d8 = function()
        return fake_d3d8.new();
    end;
    package.preload.struct = function()
        return struct;
    end;
    package.preload.bitreader = function()
        return {};
    end;
    package.preload.win32types = function()
        require('ffi').cdef('typedef struct IDirect3DTexture8 IDirect3DTexture8;');
        return true;
    end;

    local ffi = {};
    for key, value in pairs(native_ffi) do
        ffi[key] = value;
    end
    ffi.load = function(name, ...)
        if tostring(name):lower() == 'winmm' then
            logs.winmm_loads[#logs.winmm_loads + 1] = name;
            if not options.winmm_available then
                error('winmm unavailable', 2);
            end
        end
        return native_ffi.load(name, ...);
    end;
    package.loaded.ffi = nil;
    package.preload.ffi = function()
        return ffi;
    end;

    local environment = { logs = logs };

    function environment.load_addon()
        assert(loadfile('XIUI/XIUI.lua'))();
        ashita_controls.disable_macro_import_signatures();
    end

    function environment.get_event(event_name, callback_key)
        local event_callbacks = callbacks[event_name];
        return event_callbacks and event_callbacks[callback_key] or nil;
    end

    function environment.observe_initializers()
        local registry = assert(package.loaded['core.moduleregistry']);
        local expected = {};

        for name, entry in pairs(registry.GetAll()) do
            if type(entry.module.Initialize) == 'function' then
                local initializer_name = name;
                local module = entry.module;
                local original = module.Initialize;
                expected[#expected + 1] = initializer_name;
                initializer_restores[#initializer_restores + 1] = function()
                    module.Initialize = original;
                end;
                module.Initialize = function(...)
                    logs.initializer_calls[#logs.initializer_calls + 1] = initializer_name;
                    return original(...);
                end;
            end
        end

        table.sort(expected);
        return expected;
    end

    function environment.invoke_event(event_name, callback_key, event)
        local callback = assert(
            environment.get_event(event_name, callback_key),
            string.format('event not registered: %s/%s', event_name, callback_key)
        );
        logs.invoked_events[#logs.invoked_events + 1] = {
            event = event_name,
            key = callback_key,
        };
        local result = callback(event or {});
        if event_name == 'load' then
            table.sort(logs.initializer_calls);
        end
        return result;
    end

    local ok, result = xpcall(function()
        return run(environment);
    end, debug.traceback);

    for index = #initializer_restores, 1, -1 do
        initializer_restores[index]();
    end
    for index = #restores, 1, -1 do
        restores[index]();
    end
    package.path = package_path;
    restore_table(package.preload, preload_snapshot);
    restore_table(package.loaded, loaded_snapshot);
    restore_globals(global_snapshot);

    if not ok then
        error(result, 0);
    end
    return result;
end

return M;
