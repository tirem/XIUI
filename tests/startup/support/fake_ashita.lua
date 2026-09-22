local M = {};
local MACRO_IMPORT_SOURCE = 'XIUI/libs/ffxi/macros.lua';

local function record(logs, operation, ...)
    logs.host_calls[#logs.host_calls + 1] = {
        operation = operation,
        arguments = { ... },
    };
end

function M.install(_, logs, filesystem, packets)
    local previous_ashita = rawget(_G, 'ashita');
    local previous_core = rawget(_G, 'AshitaCore');
    local previous_font_border_flags = rawget(_G, 'FontBorderFlags');
    local callbacks = {};
    local allow_macro_import_signatures = true;

    local events = {
        register = function(event_name, callback_key, callback)
            callbacks[event_name] = callbacks[event_name] or {};
            callbacks[event_name][callback_key] = callback;
            logs.events[#logs.events + 1] = { event = event_name, key = callback_key };
        end,
        unregister = function(event_name, callback_key)
            if callbacks[event_name] ~= nil then
                callbacks[event_name][callback_key] = nil;
            end
        end,
    };

    local party = {
        GetAllianceParty0Count = function()
            return 0;
        end,
        GetAllianceParty1Count = function()
            return 0;
        end,
        GetAllianceParty2Count = function()
            return 0;
        end,
        GetMemberActive = function()
            return false;
        end,
        GetMemberName = function()
            return '';
        end,
        GetMemberServerId = function()
            return 0;
        end,
        GetMemberTargetIndex = function()
            return 0;
        end,
        GetMemberZone = function()
            return 0;
        end,
    };

    local player = {
        GetCapacityPoints = function()
            return 0;
        end,
        GetJobPoints = function()
            return 0;
        end,
        GetLimitPoints = function()
            return 0;
        end,
        GetLoginStatus = function()
            return 0;
        end,
        GetMainJob = function()
            return 0;
        end,
        GetMasteryExp = function()
            return 0;
        end,
        GetMasteryExpNeeded = function()
            return 0;
        end,
        GetMeritPoints = function()
            return 0;
        end,
        GetMeritPointsMax = function()
            return 0;
        end,
        GetSubJob = function()
            return 0;
        end,
    };

    local memory_manager = {
        GetEntity = function()
            return nil;
        end,
        GetInventory = function()
            return nil;
        end,
        GetParty = function()
            return party;
        end,
        GetPlayer = function()
            return player;
        end,
        GetRecast = function()
            return nil;
        end,
        GetTarget = function()
            return nil;
        end,
    };

    local resource_manager = {
        GetAbilityById = function()
            return nil;
        end,
        GetItemById = function()
            return nil;
        end,
        GetKeyItemById = function()
            return nil;
        end,
        GetSpellById = function()
            return nil;
        end,
        GetStatusIconByIndex = function()
            return nil;
        end,
        GetString = function()
            return nil;
        end,
    };

    local chat_manager = {
        QueueCommand = function(_, ...)
            record(logs, 'chat.QueueCommand', ...);
            return true;
        end,
    };

    local font_manager = {
        Get = function()
            return nil;
        end,
    };

    local gui_manager = {
        GetMenuName = function()
            return '';
        end,
    };

    local addon_manager = {
        Get = function()
            return nil;
        end,
    };

    local core = {
        GetAddonManager = function()
            return addon_manager;
        end,
        GetChatManager = function()
            return chat_manager;
        end,
        GetFontManager = function()
            return font_manager;
        end,
        GetGuiManager = function()
            return gui_manager;
        end,
        GetInstallPath = function()
            return filesystem.install_path;
        end,
        GetMemoryManager = function()
            return memory_manager;
        end,
        GetPacketManager = function()
            return packets;
        end,
        GetPointerManager = function()
            return {
                Get = function()
                    return 0;
                end,
            };
        end,
        GetResourceManager = function()
            return resource_manager;
        end,
    };

    local function unexpected_memory_write()
        error('unexpected startup memory write', 2);
    end

    _G.ashita = {
        bits = {
            unpack_be = function()
                return 0;
            end,
        },
        events = events,
        fs = filesystem.ashita_fs,
        log = {
            error = function(...)
                record(logs, 'log.error', ...);
            end,
        },
        memory = {
            find = function(module, start, signature, offset, scan)
                local info = debug.getinfo(2, 'S');
                local source = tostring(info and info.source or ''):gsub('\\', '/');
                local is_macro_import = allow_macro_import_signatures
                    and source:sub(-#MACRO_IMPORT_SOURCE) == MACRO_IMPORT_SOURCE;
                logs.memory_scans[#logs.memory_scans + 1] = {
                    module = module,
                    start = start,
                    signature = signature,
                    offset = offset,
                    scan = scan,
                    source = source,
                    matched = is_macro_import,
                };
                return is_macro_import and 1 or 0;
            end,
            read_int16 = function()
                return 0;
            end,
            read_int32 = function()
                return 0;
            end,
            read_string = function()
                return '';
            end,
            read_uint8 = function()
                return 0;
            end,
            read_uint32 = function()
                return 0;
            end,
            write_uint8 = unexpected_memory_write,
            write_uint32 = unexpected_memory_write,
        },
        misc = {
            execute = function(...)
                record(logs, 'misc.execute', ...);
                return true;
            end,
            open_url = function(...)
                record(logs, 'misc.open_url', ...);
                return true;
            end,
            play_sound = function(...)
                record(logs, 'misc.play_sound', ...);
                return true;
            end,
        },
        tasks = {
            once = function(delay)
                record(logs, 'tasks.once', delay);
            end,
        },
    };
    _G.AshitaCore = core;
    _G.FontBorderFlags = { None = 0 };

    return callbacks, function()
        _G.ashita = previous_ashita;
        _G.AshitaCore = previous_core;
        _G.FontBorderFlags = previous_font_border_flags;
    end, {
        disable_macro_import_signatures = function()
            allow_macro_import_signatures = false;
        end,
    };
end

return M;
