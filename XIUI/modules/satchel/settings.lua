local chat = require('chat')

local settingslogic = {}

settingslogic.default_settings = T{
    visible = false,
    columns = 10,
    rows = 10,
    slot_size = 40,
    show_empty_slots = true,
    include_containers = T{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 },
}

function settingslogic.create(ctx)
    local satchel = ctx.satchel
    local containerlogic = ctx.containerlogic
    local default_settings = settingslogic.default_settings

    local M = {}

    function M.is_module_enabled()
        return gConfig == nil or gConfig.showSatchelModule ~= false
    end

    -- The satchel window only owns its visibility. Columns/rows/size/empty-slots/
    -- containers are owned by the config UI (written to gConfig directly); persisting
    -- them from this stale cache would clobber config changes on open/close.
    function M.persist_settings()
        if not gConfig then
            return
        end

        gConfig.satchelVisible = satchel.settings.visible == true
    end

    function M.read_settings()
        local visible_setting = nil
        if gConfig then
            visible_setting = gConfig.satchelVisible
            if visible_setting == nil then
                visible_setting = false
            end
        end

        satchel.settings = T{
            visible = visible_setting ~= nil and (visible_setting == true) or default_settings.visible,
            columns = gConfig and gConfig.satchelColumns or default_settings.columns,
            rows = gConfig and gConfig.satchelRows or default_settings.rows,
            slot_size = gConfig and gConfig.satchelSlotSize or default_settings.slot_size,
            -- Default true; only false when explicitly unchecked (avoid the and/or-false trap).
            show_empty_slots = not (gConfig and gConfig.satchelShowEmptySlots == false),
            include_containers = T{},
        }

        local include = gConfig and gConfig.satchelIncludeContainers or default_settings.include_containers
        satchel.settings.include_containers = containerlogic.normalize_include_containers(include)
        satchel.settings.columns = math.max(4, math.min(18, tonumber(satchel.settings.columns) or default_settings.columns))
        satchel.settings.rows = math.max(4, math.min(16, tonumber(satchel.settings.rows) or default_settings.rows))
        satchel.settings.slot_size = math.max(24, math.min(96, tonumber(satchel.settings.slot_size) or default_settings.slot_size))

        satchel.visible[1] = satchel.settings.visible == true
        satchel.last_visible = satchel.visible[1]
    end

    -- Re-sync config-owned display fields (not visibility) from gConfig when config
    -- changes. gConfigVersion bumps on every edit, so this is a cheap per-frame check.
    -- Returns true when a re-sync happened so the caller can invalidate the slot cache.
    local last_cfg_version = nil
    function M.sync_display_settings()
        if not gConfig or not satchel.settings then
            return false
        end

        local version = gConfigVersion or 0
        if last_cfg_version == version then
            return false
        end
        last_cfg_version = version

        satchel.settings.columns = math.max(4, math.min(18, tonumber(gConfig.satchelColumns) or default_settings.columns))
        satchel.settings.rows = math.max(4, math.min(16, tonumber(gConfig.satchelRows) or default_settings.rows))
        satchel.settings.slot_size = math.max(24, math.min(96, tonumber(gConfig.satchelSlotSize) or default_settings.slot_size))
        satchel.settings.show_empty_slots = not (gConfig.satchelShowEmptySlots == false)
        satchel.settings.include_containers =
            containerlogic.normalize_include_containers(gConfig.satchelIncludeContainers or default_settings.include_containers)
        return true
    end

    function M.toggle_visible()
        satchel.visible[1] = not satchel.visible[1]
        satchel.settings.visible = satchel.visible[1]
        M.persist_settings()
    end

    function M.open_xiui_satchel_config()
        if showConfig then
            showConfig[1] = true
        end
    end

    function M.show_help(is_error)
        if is_error then
            print(chat.header('XIUI'):append(chat.error('Invalid satchel command syntax.')))
        end
        print(chat.header('XIUI'):append(chat.message('Satchel commands:')))
        print(chat.header('XIUI'):append(chat.message('/satchel - Toggle satchel window')))
        print(chat.header('XIUI'):append(chat.message('/xiui satchel - Toggle satchel window')))
        print(chat.header('XIUI'):append(chat.message('/xiui satchel config - Open XIUI satchel settings')))
    end

    function M.print_disabled_message()
        print(chat.header('XIUI'):append(chat.message('Satchel module is disabled. Use /xiui satchel config to enable it.')))
    end

    return M
end

return settingslogic
