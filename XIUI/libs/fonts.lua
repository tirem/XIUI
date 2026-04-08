--[[
* XIUI Font Utilities
* Provides font weight flag conversion for settings
]]--

local fontconst = require('libs.fontconst');

local M = {};

-- ========================================
-- Font Weight Helper
-- ========================================
-- Converts fontWeight string setting to font flags
function M.GetFontWeightFlags(fontWeight)
    if fontWeight == 'Bold' then
        return fontconst.FLAG_BOLD;
    else
        return fontconst.FLAG_NONE;
    end
end

return M;
