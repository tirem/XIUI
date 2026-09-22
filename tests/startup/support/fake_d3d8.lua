local M = {};

function M.new()
    return {
        device = nil,
        texture = { image = nil },
        get_device = function()
            return nil;
        end,
        gc_safe_release = function(value)
            return value;
        end,
    };
end

return M;
