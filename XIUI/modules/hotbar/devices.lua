--[[
* XIUI Crossbar - Device Mapping System
*
* Controller input handling for XInput and DirectInput devices.
*
* Acknowledgments:
*   - atom0s for XInput/DirectInput API guidance
*   - Thorny (tCrossBar author) for DirectInput button ID reference
*     https://github.com/ThornyFFXI/tCrossBar
]]--

local M = {};

-- ============================================
-- XInput Device Mapping (Microsoft standardized)
-- ============================================
-- XInput button IDs are bit positions, standardized across all XInput controllers.
-- No configuration needed - Xbox, most modern Windows controllers use this.

local xinput = {
    XInput = true,
    DirectInput = false,
    Name = 'XInput (Xbox)',

    -- XInput button IDs (bit positions in xinput_button event)
    Buttons = {
        DPAD_UP = 0, DPAD_DOWN = 1, DPAD_LEFT = 2, DPAD_RIGHT = 3,
        START = 4, BACK = 5,
        LEFT_THUMB = 6, RIGHT_THUMB = 7,
        LEFT_SHOULDER = 8, RIGHT_SHOULDER = 9,
        A = 12, B = 13, X = 14, Y = 15,
    },

    -- Button bitmasks for xinput_state
    ButtonMasks = {
        DPAD_UP = 0x0001, DPAD_DOWN = 0x0002, DPAD_LEFT = 0x0004, DPAD_RIGHT = 0x0008,
        START = 0x0010, BACK = 0x0020,
        LEFT_THUMB = 0x0040, RIGHT_THUMB = 0x0080,
        LEFT_SHOULDER = 0x0100, RIGHT_SHOULDER = 0x0200,
        A = 0x1000, B = 0x2000, X = 0x4000, Y = 0x8000,
    },
};

-- Button to slot mapping for XInput
xinput.ButtonToSlot = {
    [xinput.Buttons.DPAD_UP] = 1,
    [xinput.Buttons.DPAD_RIGHT] = 2,
    [xinput.Buttons.DPAD_DOWN] = 3,
    [xinput.Buttons.DPAD_LEFT] = 4,
    [xinput.Buttons.Y] = 5,
    [xinput.Buttons.B] = 6,
    [xinput.Buttons.A] = 7,
    [xinput.Buttons.X] = 8,
};

xinput.CrossbarButtons = {
    [xinput.Buttons.DPAD_UP] = true, [xinput.Buttons.DPAD_DOWN] = true,
    [xinput.Buttons.DPAD_LEFT] = true, [xinput.Buttons.DPAD_RIGHT] = true,
    [xinput.Buttons.A] = true, [xinput.Buttons.B] = true,
    [xinput.Buttons.X] = true, [xinput.Buttons.Y] = true,
};

xinput.CrossbarButtonsMask = bit.bor(
    xinput.ButtonMasks.DPAD_UP, xinput.ButtonMasks.DPAD_DOWN,
    xinput.ButtonMasks.DPAD_LEFT, xinput.ButtonMasks.DPAD_RIGHT,
    xinput.ButtonMasks.A, xinput.ButtonMasks.B,
    xinput.ButtonMasks.X, xinput.ButtonMasks.Y
);

function xinput.GetSlotFromButton(buttonId)
    return xinput.ButtonToSlot[buttonId];
end

function xinput.IsCrossbarButton(buttonId)
    return xinput.CrossbarButtons[buttonId] == true;
end

function xinput.GetSlotFromButtonMask(buttons)
    if bit.band(buttons, xinput.ButtonMasks.DPAD_UP) ~= 0 then return 1; end
    if bit.band(buttons, xinput.ButtonMasks.DPAD_RIGHT) ~= 0 then return 2; end
    if bit.band(buttons, xinput.ButtonMasks.DPAD_DOWN) ~= 0 then return 3; end
    if bit.band(buttons, xinput.ButtonMasks.DPAD_LEFT) ~= 0 then return 4; end
    if bit.band(buttons, xinput.ButtonMasks.Y) ~= 0 then return 5; end
    if bit.band(buttons, xinput.ButtonMasks.B) ~= 0 then return 6; end
    if bit.band(buttons, xinput.ButtonMasks.A) ~= 0 then return 7; end
    if bit.band(buttons, xinput.ButtonMasks.X) ~= 0 then return 8; end
    return nil;
end

-- ============================================
-- DirectInput Device Factory
-- ============================================
-- DirectInput button IDs vary by controller manufacturer.
-- Defaults from tCrossBar (PlayStation layout, most common for DirectInput).
-- Users can override any button ID via userConfig.

-- Default DirectInput button IDs (from tCrossBar)
-- These work for most PlayStation controllers (DualShock, DualSense)
local DINPUT_DEFAULTS = {
    SQUARE = 48,
    CROSS = 49,
    CIRCLE = 50,
    TRIANGLE = 51,
    L1 = 52,
    R1 = 53,
    L2 = 54,
    R2 = 55,
    L3 = 58,
    R3 = 59,
};

-- D-pad angles (POV hat) - standard across all DirectInput controllers
local DPAD_ANGLES = {
    UP = 0,
    RIGHT = 9000,
    DOWN = 18000,
    LEFT = 27000,
};

-- Factory function to create a DirectInput device with configurable button IDs
local function CreateDInputDevice(userConfig)
    userConfig = userConfig or {};

    -- Merge user config with defaults
    local buttons = {
        SQUARE = userConfig.SQUARE or DINPUT_DEFAULTS.SQUARE,
        CROSS = userConfig.CROSS or DINPUT_DEFAULTS.CROSS,
        CIRCLE = userConfig.CIRCLE or DINPUT_DEFAULTS.CIRCLE,
        TRIANGLE = userConfig.TRIANGLE or DINPUT_DEFAULTS.TRIANGLE,
        L1 = userConfig.L1 or DINPUT_DEFAULTS.L1,
        R1 = userConfig.R1 or DINPUT_DEFAULTS.R1,
        L2 = userConfig.L2 or DINPUT_DEFAULTS.L2,
        R2 = userConfig.R2 or DINPUT_DEFAULTS.R2,
        L3 = userConfig.L3 or DINPUT_DEFAULTS.L3,
        R3 = userConfig.R3 or DINPUT_DEFAULTS.R3,
    };

    local device = {
        XInput = false,
        DirectInput = true,
        Name = 'DirectInput',
        Buttons = buttons,

        -- D-pad angle to slot mapping (POV hat)
        DPadAngleToSlot = {
            [DPAD_ANGLES.UP] = 1,
            [DPAD_ANGLES.RIGHT] = 2,
            [DPAD_ANGLES.DOWN] = 3,
            [DPAD_ANGLES.LEFT] = 4,
        },
    };

    -- Face button to slot mapping
    device.ButtonToSlot = {
        [buttons.TRIANGLE] = 5,
        [buttons.CIRCLE] = 6,
        [buttons.CROSS] = 7,
        [buttons.SQUARE] = 8,
    };

    -- Crossbar buttons (face buttons only, D-pad uses POV)
    device.CrossbarButtons = {
        [buttons.TRIANGLE] = true,
        [buttons.CIRCLE] = true,
        [buttons.CROSS] = true,
        [buttons.SQUARE] = true,
    };

    -- Methods
    function device.GetSlotFromButton(buttonId)
        return device.ButtonToSlot[buttonId];
    end

    function device.GetSlotFromDPad(angle)
        if angle == nil or angle == -1 then return nil; end
        return device.DPadAngleToSlot[angle];
    end

    function device.IsCrossbarButton(buttonId)
        return device.CrossbarButtons[buttonId] == true;
    end

    function device.IsTriggerButton(buttonId)
        return buttonId == buttons.L2 or buttonId == buttons.R2;
    end

    function device.IsL2Button(buttonId)
        return buttonId == buttons.L2;
    end

    function device.IsR2Button(buttonId)
        return buttonId == buttons.R2;
    end

    return device;
end

-- ============================================
-- Public API
-- ============================================

-- Scheme names
local SCHEME_NAMES = { 'xinput', 'dinput' };

-- Display names for UI
local SCHEME_DISPLAY_NAMES = {
    xinput = 'XInput (Xbox)',
    dinput = 'DirectInput (PlayStation/Other)',
};

-- Get a device by scheme name
-- @param schemeName: 'xinput', 'dinput', 'xbox', 'dualsense', 'switchpro'
-- @param userConfig: (optional) for dinput, table of button ID overrides
-- @return device table with all required methods
function M.GetDevice(schemeName, userConfig)
    -- Normalize scheme name
    local normalizedScheme = schemeName;
    if schemeName == 'xbox' then normalizedScheme = 'xinput'; end
    if schemeName == 'dualsense' or schemeName == 'switchpro' then normalizedScheme = 'dinput'; end

    if normalizedScheme == 'xinput' then
        return xinput;
    elseif normalizedScheme == 'dinput' then
        return CreateDInputDevice(userConfig);
    else
        -- Default to xinput
        return xinput;
    end
end

-- Get list of scheme names
function M.GetSchemeNames()
    return SCHEME_NAMES;
end

-- Legacy alias for backwards compatibility
function M.GetDeviceNames()
    return M.GetSchemeNames();
end

-- Get display names for UI
function M.GetSchemeDisplayNames()
    return SCHEME_DISPLAY_NAMES;
end

-- Legacy alias for backwards compatibility
function M.GetDeviceDisplayNames()
    return M.GetSchemeDisplayNames();
end

-- Normalize scheme name to canonical form ('xinput' or 'dinput')
function M.NormalizeScheme(schemeName)
    if schemeName == 'xbox' or schemeName == 'xinput' then
        return 'xinput';
    elseif schemeName == 'dualsense' or schemeName == 'switchpro' or schemeName == 'dinput' then
        return 'dinput';
    end
    return 'xinput';  -- Default
end

-- Check if a scheme uses XInput
function M.UsesXInput(schemeName)
    return M.NormalizeScheme(schemeName) == 'xinput';
end

-- Check if a scheme uses DirectInput
function M.UsesDirectInput(schemeName)
    return M.NormalizeScheme(schemeName) == 'dinput';
end

-- Get default DirectInput button IDs (for config UI)
function M.GetDInputDefaults()
    return DINPUT_DEFAULTS;
end

-- Get D-pad angles (for reference)
function M.GetDPadAngles()
    return DPAD_ANGLES;
end

return M;
