local M = {};

function M.install(epoch, monotonic)
    local original_time = os.time;
    local original_clock = os.clock;

    os.time = function()
        return epoch;
    end;
    os.clock = function()
        return monotonic;
    end;

    return function()
        os.time = original_time;
        os.clock = original_clock;
    end;
end

return M;
