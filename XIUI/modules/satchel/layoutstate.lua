local containerlogic = require('modules.satchel.containerlogic')
local sortstate = require('modules.satchel.sortstate')

local layoutstate = {}

local DISPLAY_SLOTS = containerlogic.DISPLAY_SLOTS
local last_identity_key = nil

local function get_player_identity_key()
    local mm = AshitaCore:GetMemoryManager()
    if not mm then
        return nil
    end

    local party = mm:GetParty()
    local entity = mm:GetEntity()
    if not party or not entity then
        return nil
    end

    local index = party:GetMemberTargetIndex(0)
    if not index then
        return nil
    end

    local name = entity:GetName(index)
    local server_id = tonumber(entity:GetServerId(index)) or 0
    if not name or #name == 0 or server_id <= 0 then
        return nil
    end

    return ('%s_%d'):format(name, server_id)
end

local function copy_slot_entry(slot, display_index)
    return {
        container_id = slot.container_id,
        slot_index = slot.slot_index,
        property_index = slot.property_index,
        id = slot.id,
        count = slot.count,
        locked = slot.locked,
        display_index = display_index,
    }
end

local function build_identity_map(slot_count)
    local map = {}
    for display_index = 0, slot_count - 1 do
        map[display_index + 1] = display_index
    end
    return map
end

local function slot_has_item(slot)
    return slot and slot.id and slot.id > 0
end

local function slot_is_empty_accessible(slot)
    return slot and not slot.locked and not slot_has_item(slot)
end

local function persist_layout_maps(runtime_maps)
    if not config then
        return
    end

    config.satchelDisplayLayouts = config.satchelDisplayLayouts or {}

    for container_id, display_map in pairs(runtime_maps) do
        local saved = {}
        for display_index = 1, #display_map do
            saved[display_index] = tonumber(display_map[display_index]) or (display_index - 1)
        end
        config.satchelDisplayLayouts[tostring(container_id)] = saved
    end

    if SaveCharacterSettingsInternal then
        SaveCharacterSettingsInternal()
    end
end

function layoutstate.find_first_empty_memory_index(raw_slots)
    for _, slot in ipairs(raw_slots or {}) do
        if slot_is_empty_accessible(slot) then
            return tonumber(slot.slot_index)
        end
    end
    return nil
end

function layoutstate.find_first_empty_display_index(container_id, raw_slots, runtime_maps)
    local visual_slots = layoutstate.build_display_slots(container_id, raw_slots, runtime_maps)
    for _, slot in ipairs(visual_slots) do
        if slot_is_empty_accessible(slot) then
            return tonumber(slot.display_index)
        end
    end
    return nil
end

function layoutstate.place_memory_at_display(container_id, raw_slots, runtime_maps, memory_index, dst_display)
    container_id = tonumber(container_id)
    memory_index = tonumber(memory_index)
    dst_display = tonumber(dst_display)
    if container_id == nil or memory_index == nil or dst_display == nil then
        return false
    end

    local display_map = layoutstate.get_display_map(container_id, raw_slots, runtime_maps)
    if not display_map then
        return false
    end

    local src_display = nil
    for display_index = 1, #display_map do
        if tonumber(display_map[display_index]) == memory_index then
            src_display = display_index - 1
            break
        end
    end

    if src_display == nil then
        return false
    end

    if src_display ~= dst_display then
        local dst_mem = tonumber(display_map[dst_display + 1])
        display_map[src_display + 1] = dst_mem
        display_map[dst_display + 1] = memory_index
    end

    persist_layout_maps(runtime_maps)
    return true
end

function layoutstate.ensure_loaded(runtime_maps)
    local identity_key = get_player_identity_key()
    if identity_key == nil then
        return
    end

    if identity_key == last_identity_key then
        return
    end

    last_identity_key = identity_key
    layoutstate.reload_from_config(runtime_maps)
end

function layoutstate.reload_from_config(runtime_maps)
    for key in pairs(runtime_maps) do
        runtime_maps[key] = nil
    end

    if not config or type(config.satchelDisplayLayouts) ~= 'table' then
        return
    end

    for container_key, saved in pairs(config.satchelDisplayLayouts) do
        local container_id = tonumber(container_key)
        if container_id ~= nil and type(saved) == 'table' then
            local display_map = {}
            for display_index = 1, DISPLAY_SLOTS do
                local memory_index = tonumber(saved[display_index])
                if memory_index == nil then
                    memory_index = display_index - 1
                end
                display_map[display_index] = memory_index
            end
            runtime_maps[container_id] = display_map
        end
    end
end

function layoutstate.get_display_map(container_id, raw_slots, runtime_maps)
    container_id = tonumber(container_id)
    if container_id == nil then
        return nil
    end

    layoutstate.ensure_loaded(runtime_maps)

    local slot_count = #(raw_slots or {})
    if slot_count <= 0 then
        slot_count = DISPLAY_SLOTS
    end

    local display_map = runtime_maps[container_id]
    if not display_map or #display_map ~= slot_count then
        display_map = build_identity_map(slot_count)
        runtime_maps[container_id] = display_map
    end

    return display_map
end

function layoutstate.build_display_slots(container_id, raw_slots, runtime_maps)
    local display_map = layoutstate.get_display_map(container_id, raw_slots, runtime_maps)
    if not display_map then
        return raw_slots or {}
    end

    local by_memory = {}
    for _, slot in ipairs(raw_slots or {}) do
        by_memory[tonumber(slot.slot_index) or -1] = slot
    end

    local result = {}
    for display_index = 0, #display_map - 1 do
        local memory_index = tonumber(display_map[display_index + 1]) or display_index
        local slot = by_memory[memory_index]
        if slot then
            result[#result + 1] = copy_slot_entry(slot, display_index)
        end
    end

    return result
end

function layoutstate.reset_container_layout(container_id, raw_slots, runtime_maps)
    container_id = tonumber(container_id)
    if container_id == nil then
        return
    end

    local slot_count = #(raw_slots or {})
    if slot_count <= 0 then
        slot_count = DISPLAY_SLOTS
    end

    runtime_maps[container_id] = build_identity_map(slot_count)

    if config and config.satchelDisplayLayouts then
        config.satchelDisplayLayouts[tostring(container_id)] = nil
        if SaveCharacterSettingsInternal then
            SaveCharacterSettingsInternal()
        end
    end
end

function layoutstate.apply_display_move(container_id, raw_slots, runtime_maps, src_display, dst_display)
    container_id = tonumber(container_id)
    src_display = tonumber(src_display)
    dst_display = tonumber(dst_display)
    if container_id == nil or src_display == nil or dst_display == nil or src_display == dst_display then
        return false
    end

    local display_map = layoutstate.get_display_map(container_id, raw_slots, runtime_maps)
    if not display_map then
        return false
    end

    local by_memory = {}
    for _, slot in ipairs(raw_slots or {}) do
        by_memory[tonumber(slot.slot_index) or -1] = slot
    end

    local src_mem = tonumber(display_map[src_display + 1])
    local dst_mem = tonumber(display_map[dst_display + 1])
    if src_mem == nil or dst_mem == nil then
        return false
    end

    local dst_slot = by_memory[dst_mem]
    local dst_occupied = slot_has_item(dst_slot)

    if not dst_occupied then
        display_map[src_display + 1] = dst_mem
        display_map[dst_display + 1] = src_mem
    elseif math.abs(src_display - dst_display) == 1 then
        display_map[src_display + 1] = dst_mem
        display_map[dst_display + 1] = src_mem
    elseif src_display < dst_display then
        local moving_mem = src_mem
        for display_index = src_display, dst_display - 1 do
            display_map[display_index + 1] = display_map[display_index + 2]
        end
        display_map[dst_display + 1] = moving_mem
    else
        local moving_mem = src_mem
        for display_index = src_display, dst_display + 1, -1 do
            display_map[display_index + 1] = display_map[display_index]
        end
        display_map[dst_display + 1] = moving_mem
    end

    persist_layout_maps(runtime_maps)
    return true
end

function layoutstate.has_custom_layout(container_id, raw_slots, runtime_maps)
    container_id = tonumber(container_id)
    if container_id == nil then
        return false
    end

    layoutstate.ensure_loaded(runtime_maps)

    local display_map = runtime_maps[container_id]
    if not display_map then
        return false
    end

    local slot_count = #(raw_slots or {})
    if slot_count <= 0 then
        slot_count = #display_map
    end

    for display_index = 1, slot_count do
        local memory_index = tonumber(display_map[display_index])
        if memory_index == nil then
            memory_index = display_index - 1
        end
        if memory_index ~= (display_index - 1) then
            return true
        end
    end

    return false
end

function layoutstate.sync_map_from_visual_slots(container_id, visual_slots, runtime_maps)
    container_id = tonumber(container_id)
    if container_id == nil or type(visual_slots) ~= 'table' then
        return
    end

    local display_map = {}
    for display_index, slot in ipairs(visual_slots) do
        display_map[display_index] = tonumber(slot.slot_index) or (display_index - 1)
    end

    runtime_maps[container_id] = display_map
    persist_layout_maps(runtime_maps)
end

function layoutstate.uses_manual_layout(container_id, runtime_sorted)
    if sortstate.is_auto_sort_enabled() then
        return false
    end

    if sortstate.should_visually_sort(container_id, runtime_sorted) then
        return false
    end

    return true
end

return layoutstate
