local function create_footer_logic(ctx)
    local satchel = ctx.satchel
    local icons = ctx.icons
    local gil_icon_path = ctx.gil_icon_path

    local M = {
        gil_cache = {
            value = nil,
            stamp = 0,
            ttl = 0.5,
        },
    }

    function M.get_player_gil_amount()
        local now = os.clock()
        if M.gil_cache.value ~= nil and (now - M.gil_cache.stamp) < M.gil_cache.ttl then
            return M.gil_cache.value
        end

        local inv = AshitaCore:GetMemoryManager():GetInventory()
        if not inv then
            return M.gil_cache.value
        end

        local ok, gil_item = pcall(function()
            return inv:GetContainerItem(0, 0)
        end)
        if not ok or not gil_item then
            return M.gil_cache.value
        end

        M.gil_cache.value = tonumber(gil_item.Count) or 0
        M.gil_cache.stamp = now
        return M.gil_cache.value
    end

    function M.format_gil_text(n)
        local s = tostring(math.floor(tonumber(n) or 0))
        local sign, num = s:match('^([%-]?)(%d+)$')
        if not num then
            return s
        end

        local parts = {}
        while #num > 3 do
            table.insert(parts, 1, num:sub(-3))
            num = num:sub(1, -4)
        end
        if #num > 0 then
            table.insert(parts, 1, num)
        end

        return (sign or '') .. table.concat(parts, ',')
    end

    function M.load_gil_icon()
        return icons.load_file_icon(satchel, 'gil', gil_icon_path)
    end

    return M
end

return {
    create = create_footer_logic,
}
