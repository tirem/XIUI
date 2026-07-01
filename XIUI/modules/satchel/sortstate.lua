local sortstate = {}

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

function sortstate.is_auto_sort_enabled()
    return gConfig ~= nil and gConfig.satchelAutoSortBags == true
end

function sortstate.reload_from_config(runtime_sorted)
    runtime_sorted = runtime_sorted or {}
    for key in pairs(runtime_sorted) do
        runtime_sorted[key] = nil
    end

    if config and type(config.satchelSortedContainers) == 'table' then
        for container_key, enabled in pairs(config.satchelSortedContainers) do
            if enabled == true then
                local container_id = tonumber(container_key)
                if container_id ~= nil then
                    runtime_sorted[container_id] = true
                end
            end
        end
    end
end

function sortstate.ensure_loaded(runtime_sorted)
    local identity_key = get_player_identity_key()
    if identity_key == nil then
        return
    end

    if identity_key ~= last_identity_key then
        last_identity_key = identity_key
        sortstate.reload_from_config(runtime_sorted)
    end
end

function sortstate.should_visually_sort(container_id, runtime_sorted)
    if sortstate.is_auto_sort_enabled() then
        return true
    end

    container_id = tonumber(container_id)
    return container_id ~= nil and runtime_sorted[container_id] == true
end

function sortstate.mark_container_sorted(container_id, runtime_sorted)
    container_id = tonumber(container_id)
    if container_id == nil then
        return
    end

    runtime_sorted[container_id] = true

    if not config then
        return
    end

    if type(config.satchelSortedContainers) ~= 'table' then
        config.satchelSortedContainers = {}
    end

    config.satchelSortedContainers[tostring(container_id)] = true

    if SaveCharacterSettingsInternal then
        SaveCharacterSettingsInternal()
    end
end

function sortstate.clear_container_sorted(container_id, runtime_sorted)
    container_id = tonumber(container_id)
    if container_id == nil then
        return
    end

    runtime_sorted[container_id] = nil

    if not config or type(config.satchelSortedContainers) ~= 'table' then
        return
    end

    config.satchelSortedContainers[tostring(container_id)] = nil

    if SaveCharacterSettingsInternal then
        SaveCharacterSettingsInternal()
    end
end

return sortstate
