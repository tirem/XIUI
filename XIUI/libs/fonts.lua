--[[
* XIUI Font Utilities
* Provides font weight flag conversion for settings
]]--

local M = {};

-- ========================================
-- Font Weight Helper
-- ========================================
-- Converts fontWeight string setting to font flags
function M.GetFontWeightFlags(fontWeight)
    if fontWeight == 'Bold' then
        return 1; -- Bold flag
    else
        return 0; -- None
    end
end

return M;
