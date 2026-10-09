--[[
* XIUI Crossbar - Shoulder/Trigger Button Names
* Brand names and icons for L1/R1/L2/R2, following the controller profile and
* the "Swap Palette Cycle and Trigger Buttons" option.
*
* Callers describe buttons by role using the default layout names:
*   'L2'/'R2' = the buttons that open the crossbar
*   'L1'/'R1' = the buttons that cycle palettes
]]--

local M = {};

-- folder: asset subfolder under assets/hotbar/controller holding these icons
M.BRANDS = {
    PlayStation = { folder = 'PlayStation', L1 = 'L1', R1 = 'R1', L2 = 'L2', R2 = 'R2' },
    Nintendo    = { folder = 'Nintendo',    L1 = 'L',  R1 = 'R',  L2 = 'ZL', R2 = 'ZR' },
    Xbox        = { folder = 'Shared',      L1 = 'LB', R1 = 'RB', L2 = 'LT', R2 = 'RT' },
};

local SCHEME_BRAND = {
    dualsense = 'PlayStation',
    switchpro = 'Nintendo',
};

local SWAPPED_ROLE = { L1 = 'L2', R1 = 'R2', L2 = 'L1', R2 = 'R1' };

local function GetCrossbarSettings()
    return gConfig and gConfig.hotbarCrossbar;
end

function M.GetBrand()
    local settings = GetCrossbarSettings();
    local scheme = settings and settings.controllerScheme;
    return M.BRANDS[SCHEME_BRAND[scheme] or 'Xbox'];
end

function M.IsSwapped()
    local settings = GetCrossbarSettings();
    return settings ~= nil and settings.swapShoulderTriggers == true;
end

-- Physical button ('L1', 'R1', 'L2', 'R2') that currently fills a role.
function M.GetPhysical(role)
    if M.IsSwapped() then
        return SWAPPED_ROLE[role] or role;
    end
    return role;
end

-- Brand name of the button that currently fills a role (e.g. 'L2' -> 'LB' when swapped on Xbox).
function M.GetName(role)
    return M.GetBrand()[M.GetPhysical(role)] or role;
end

-- Rewrite L1/R1/L2/R2 in text written for the default layout. Display text only:
-- storage keys like 'L2R2' must never be passed through this.
function M.Format(text)
    if type(text) ~= 'string' then return text; end
    local brand = M.GetBrand();
    local swapped = M.IsSwapped();
    return (text:gsub('%f[%w]([LR][12])', function(role)
        return brand[swapped and SWAPPED_ROLE[role] or role];
    end));
end

-- Texture cache name (passed to textures:GetControllerIcon) for the button filling a role.
function M.GetIconName(role)
    local brand = M.GetBrand();
    return brand.folder .. '_' .. brand[M.GetPhysical(role)];
end

return M;
