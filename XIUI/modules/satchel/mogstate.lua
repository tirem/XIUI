local mogstate = {}

function mogstate.create(ctx)
    local satchel = ctx.satchel

    local M = {}

    local function get_player_identity()
        local mm = AshitaCore:GetMemoryManager()
        if not mm then return nil, nil end

        local party = mm:GetParty()
        local entity = mm:GetEntity()
        if not party or not entity then return nil, nil end

        local index = party:GetMemberTargetIndex(0)
        if not index then return nil, nil end

        local name = entity:GetName(index)
        local server_id = tonumber(entity:GetServerId(index)) or 0
        if not name or #name == 0 or server_id <= 0 then
            return nil, nil
        end

        return name, server_id
    end

    local function get_mog_state_dir()
        local root = string.format('%s\\config\\addons\\%s\\', AshitaCore:GetInstallPath(), addon.name)
        local name, server_id = get_player_identity()

        if name and server_id then
            return string.format('%s%s_%d\\', root, name, server_id)
        end

        return root .. 'defaults\\'
    end

    local function get_mog_state_file()
        return get_mog_state_dir() .. 'satchel_mog_state.dat'
    end

    function M.read_mog_state()
        local f = io.open(get_mog_state_file(), 'r')
        if not f then return false end
        local v = f:read('*a')
        f:close()
        return v == '1'
    end

    local function write_mog_state(value)
        ashita.fs.create_dir(get_mog_state_dir())
        local f = io.open(get_mog_state_file(), 'w')
        if f then
            f:write(value and '1' or '0')
            f:close()
        end
    end

    function M.set_mog_house(value)
        satchel.in_mog_house = value == true
        write_mog_state(satchel.in_mog_house)
    end

    return M
end

return mogstate
