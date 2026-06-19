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

    function M.persist_settings()
        if not gConfig then
            return
        end

        gConfig.satchelVisible = satchel.settings.visible == true
        gConfig.satchelColumns = satchel.settings.columns
        gConfig.satchelRows = satchel.settings.rows
        gConfig.satchelSlotSize = satchel.settings.slot_size
        gConfig.satchelShowEmptySlots = satchel.settings.show_empty_slots == true

        local include = T{}
        for _, container_id in ipairs(satchel.settings.include_containers or T{}) do
            include:append(tonumber(container_id) or 0)
        end
        gConfig.satchelIncludeContainers = include

        if SaveSettingsOnly then
            SaveSettingsOnly()
        end
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
            show_empty_slots = gConfig and gConfig.satchelShowEmptySlots ~= false or default_settings.show_empty_slots,
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
