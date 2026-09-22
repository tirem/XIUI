local M = {};

function M.new(log)
    return {
        AddOutgoingPacket = function(_, id, data)
            log[#log + 1] = { direction = 'out', id = id, data = data };
            return true;
        end,
        AddIncomingPacket = function(_, id, data)
            log[#log + 1] = { direction = 'in', id = id, data = data };
            return true;
        end,
    };
end

return M;
