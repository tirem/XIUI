--[[
    Satchel module color helpers — reads gConfig.colorCustomization.satchelModule
    with XIUI theme-aligned defaults (config.lua gold / warm dark palette).
]]--

local M = {}

local DEFAULTS = {
    dragDropHighlightColor = 0x40F4DA97,
    dragDropHighlightHoverColor = 0xFFC3AE79,
    dragDropInvalidHighlightColor = 0x40B56C72,
    dragDropInvalidHighlightHoverColor = 0xFF8F5358,
    emptySlotBorderColor = 0xCC4C473D,
    lockedSlotBorderColor = 0xBF615C51,
    bazaarBorderColor = 0xFFF25252,
    equipmentBorderColor = 0xFF59A1F2,
    usableBorderColor = 0xFF94DB80,
    itemBorderColor = 0xFFB89959,
}

local function get_table()
    if gConfig and gConfig.colorCustomization and gConfig.colorCustomization.satchelModule then
        return gConfig.colorCustomization.satchelModule
    end
    return nil
end

local function get_argb(key)
    local colors = get_table()
    if colors and colors[key] then
        return colors[key]
    end
    return DEFAULTS[key]
end

function M.get_rgba(key)
    return ARGBToImGui(get_argb(key))
end

function M.get_drag_drop_highlight()
    return M.get_rgba('dragDropHighlightColor')
end

function M.get_drag_drop_highlight_hover()
    return M.get_rgba('dragDropHighlightHoverColor')
end

function M.get_drag_drop_invalid_highlight()
    return M.get_rgba('dragDropInvalidHighlightColor')
end

function M.get_drag_drop_invalid_highlight_hover()
    return M.get_rgba('dragDropInvalidHighlightHoverColor')
end

function M.get_empty_slot_border()
    return M.get_rgba('emptySlotBorderColor')
end

function M.get_locked_slot_border()
    return M.get_rgba('lockedSlotBorderColor')
end

function M.get_bazaar_border()
    return M.get_rgba('bazaarBorderColor')
end

function M.get_equipment_border()
    return M.get_rgba('equipmentBorderColor')
end

function M.get_usable_border()
    return M.get_rgba('usableBorderColor')
end

function M.get_item_border()
    return M.get_rgba('itemBorderColor')
end

function M.get_defaults()
    return DEFAULTS
end

return M
