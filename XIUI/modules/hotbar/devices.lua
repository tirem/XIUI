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
    Name = 'xbox',
    DisplayName = 'Xbox / XInput',

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
-- DirectInput Device Profiles
-- ============================================
-- DirectInput button IDs vary by controller manufacturer.
-- Each controller type has its own profile with correct button offsets.
-- Based on tCrossBar controller definitions.

-- D-pad angles - standard across all DirectInput controllers
-- D-Pad is reported at button offset 32 with angle values
local DPAD_ANGLES = {
    UP = 0,
    UP_RIGHT = 4500,
    RIGHT = 9000,
    DOWN_RIGHT = 13500,
    DOWN = 18000,
    DOWN_LEFT = 22500,
    LEFT = 27000,
    UP_LEFT = 31500,
    CENTERED = -1,  -- D-pad released
};

-- D-Pad button offset (same for all DirectInput controllers)
local DPAD_BUTTON_OFFSET = 32;

-- ============================================
-- DualSense / DualShock Profile (PlayStation)
-- ============================================
local function CreateDualSenseDevice()
    local buttons = {
        -- Face buttons
        SQUARE = 48,
        CROSS = 49,
        CIRCLE = 50,
        TRIANGLE = 51,
        -- Shoulder buttons
        L1 = 52,
        R1 = 53,
        -- Trigger buttons (press state)
        L2 = 54,
        R2 = 55,
        -- Other buttons
        CREATE = 56,
        OPTIONS = 57,
        L3 = 58,
        R3 = 59,
        PLAYSTATION = 60,
        TOUCHPAD = 61,
        MICROPHONE = 62,
        -- Analog trigger intensity offsets (for advanced use)
        L2_INTENSITY = 12,
        R2_INTENSITY = 16,
        -- D-Pad offset
        DPAD = DPAD_BUTTON_OFFSET,
    };

    local device = {
        XInput = false,
        DirectInput = true,
        Name = 'DualSense',
        DisplayName = 'PlayStation (DualSense/DualShock)',
        Buttons = buttons,
        -- Track analog trigger intensity
        HasAnalogTriggers = true,
        TriggerIntensityOffsets = {
            L2 = 12,
            R2 = 16,
        },
    };

    -- D-pad angle to slot mapping
    device.DPadAngleToSlot = {
        [DPAD_ANGLES.UP] = 1,
        [DPAD_ANGLES.RIGHT] = 2,
        [DPAD_ANGLES.DOWN] = 3,
        [DPAD_ANGLES.LEFT] = 4,
    };

    -- Face button to slot mapping (PlayStation layout: Triangle/Circle/Cross/Square)
    -- Slot 5 = Top button, Slot 6 = Right button, Slot 7 = Bottom button, Slot 8 = Left button
    device.ButtonToSlot = {
        [buttons.TRIANGLE] = 5,  -- Top (ID 51)
        [buttons.CIRCLE] = 6,    -- Right (ID 50)
        [buttons.CROSS] = 7,     -- Bottom (ID 49)
        [buttons.SQUARE] = 8,    -- Left (ID 48)
    };

    -- Crossbar buttons (face buttons - D-pad handled separately)
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
        if angle == nil or angle == -1 or angle == 65535 then return nil; end
        return device.DPadAngleToSlot[angle];
    end

    function device.GetSlotFromDPadButton(buttonId, buttonState)
        if buttonId ~= DPAD_BUTTON_OFFSET then return nil; end
        return device.GetSlotFromDPad(buttonState);
    end

    function device.IsCrossbarButton(buttonId)
        return device.CrossbarButtons[buttonId] == true;
    end

    function device.IsDPadButton(buttonId)
        return buttonId == DPAD_BUTTON_OFFSET;
    end

    function device.IsTriggerButton(buttonId)
        return buttonId == buttons.L2 or buttonId == buttons.R2;
    end

    function device.IsTriggerIntensity(buttonId)
        return buttonId == buttons.L2_INTENSITY or buttonId == buttons.R2_INTENSITY;
    end

    function device.IsL2Button(buttonId)
        return buttonId == buttons.L2 or buttonId == buttons.L2_INTENSITY;
    end

    function device.IsR2Button(buttonId)
        return buttonId == buttons.R2 or buttonId == buttons.R2_INTENSITY;
    end

    -- Shoulder button detection for palette cycling (R1/L1)
    function device.IsShoulderButton(buttonId)
        return buttonId == buttons.L1 or buttonId == buttons.R1;
    end

    function device.IsR1Button(buttonId)
        return buttonId == buttons.R1;
    end

    function device.IsL1Button(buttonId)
        return buttonId == buttons.L1;
    end

    return device;
end

-- ============================================
-- Switch Pro Profile (Nintendo)
-- ============================================
local function CreateSwitchProDevice()
    local buttons = {
        -- Face buttons (Nintendo layout - DirectInput button IDs)
        -- DirectInput ID -> Physical button position
        -- Note: Switch Pro sends these button IDs in this order via DirectInput:
        B = 48,      -- Bottom button (like Cross on PS, A on Xbox)
        A = 49,      -- Right button (like Circle on PS, B on Xbox)
        Y = 50,      -- Left button (like Square on PS, X on Xbox)
        X = 51,      -- Top button (like Triangle on PS, Y on Xbox)
        -- Shoulder buttons
        L = 52,
        R = 53,
        -- Trigger buttons
        ZL = 54,
        ZR = 55,
        -- Other buttons
        MINUS = 56,
        PLUS = 57,
        LSTICK_BUTTON = 58,
        RSTICK_BUTTON = 59,
        HOME = 60,
        CAPTURE = 61,
        -- D-Pad offset
        DPAD = DPAD_BUTTON_OFFSET,
    };

    local device = {
        XInput = false,
        DirectInput = true,
        Name = 'SwitchPro',
        DisplayName = 'Nintendo Switch Pro',
        Buttons = buttons,
        HasAnalogTriggers = false,  -- Switch Pro triggers are digital
    };

    -- D-pad angle to slot mapping
    device.DPadAngleToSlot = {
        [DPAD_ANGLES.UP] = 1,
        [DPAD_ANGLES.RIGHT] = 2,
        [DPAD_ANGLES.DOWN] = 3,
        [DPAD_ANGLES.LEFT] = 4,
    };

    -- Face button to slot mapping (Nintendo layout: X/A/B/Y mapped to slots 5/6/7/8)
    -- Slot 5 = Top button (X on Switch, Triangle on PS, Y on Xbox)
    -- Slot 6 = Right button (A on Switch, Circle on PS, B on Xbox)
    -- Slot 7 = Bottom button (B on Switch, Cross on PS, A on Xbox)
    -- Slot 8 = Left button (Y on Switch, Square on PS, X on Xbox)
    device.ButtonToSlot = {
        [buttons.X] = 5,  -- Top (ID 51)
        [buttons.A] = 6,  -- Right (ID 49)
        [buttons.B] = 7,  -- Bottom (ID 48)
        [buttons.Y] = 8,  -- Left (ID 50)
    };

    -- Crossbar buttons
    device.CrossbarButtons = {
        [buttons.X] = true,
        [buttons.A] = true,
        [buttons.B] = true,
        [buttons.Y] = true,
    };

    -- Methods
    function device.GetSlotFromButton(buttonId)
        return device.ButtonToSlot[buttonId];
    end

    function device.GetSlotFromDPad(angle)
        if angle == nil or angle == -1 or angle == 65535 then return nil; end
        return device.DPadAngleToSlot[angle];
    end

    function device.GetSlotFromDPadButton(buttonId, buttonState)
        if buttonId ~= DPAD_BUTTON_OFFSET then return nil; end
        return device.GetSlotFromDPad(buttonState);
    end

    function device.IsCrossbarButton(buttonId)
        return device.CrossbarButtons[buttonId] == true;
    end

    function device.IsDPadButton(buttonId)
        return buttonId == DPAD_BUTTON_OFFSET;
    end

    function device.IsTriggerButton(buttonId)
        return buttonId == buttons.ZL or buttonId == buttons.ZR;
    end

    function device.IsTriggerIntensity(buttonId)
        return false;  -- Switch Pro has no analog triggers
    end

    function device.IsL2Button(buttonId)
        return buttonId == buttons.ZL;
    end

    function device.IsR2Button(buttonId)
        return buttonId == buttons.ZR;
    end

    -- Shoulder button detection for palette cycling (R/L on Switch)
    function device.IsShoulderButton(buttonId)
        return buttonId == buttons.L or buttonId == buttons.R;
    end

    function device.IsR1Button(buttonId)
        return buttonId == buttons.R;
    end

    function device.IsL1Button(buttonId)
        return buttonId == buttons.L;
    end

    return device;
end

-- ============================================
-- Stadia Controller Profile
-- ============================================
local function CreateStadiaDevice()
    local buttons = {
        -- Face buttons (Xbox layout labels - DirectInput button IDs)
        A = 48,      -- Bottom button (like A on Xbox)
        B = 49,      -- Right button (like B on Xbox)
        X = 50,      -- Left button (like X on Xbox)
        Y = 51,      -- Top button (like Y on Xbox)
        -- Shoulder buttons
        L1 = 52,
        R1 = 53,
        -- Trigger buttons (digital - state 128 for pressed)
        L2 = 60,
        R2 = 59,
        -- Other buttons
        L3 = 54,
        R3 = 55,
        OPTIONS = 56,
        MENU = 57,
        STADIA = 58,
        ASSISTANT = 61,
        CAPTURE = 62,
        -- D-Pad offset
        DPAD = DPAD_BUTTON_OFFSET,
    };

    local device = {
        XInput = false,
        DirectInput = true,
        Name = 'Stadia',
        DisplayName = 'Stadia Controller',
        Buttons = buttons,
        HasAnalogTriggers = false,  -- Stadia triggers are digital
    };

    -- D-pad angle to slot mapping
    device.DPadAngleToSlot = {
        [DPAD_ANGLES.UP] = 1,
        [DPAD_ANGLES.RIGHT] = 2,
        [DPAD_ANGLES.DOWN] = 3,
        [DPAD_ANGLES.LEFT] = 4,
    };

    -- Face button to slot mapping (Xbox layout: Y/B/A/X mapped to slots 5/6/7/8)
    device.ButtonToSlot = {
        [buttons.Y] = 5,  -- Top (ID 51)
        [buttons.B] = 6,  -- Right (ID 49)
        [buttons.A] = 7,  -- Bottom (ID 48)
        [buttons.X] = 8,  -- Left (ID 50)
    };

    -- Crossbar buttons
    device.CrossbarButtons = {
        [buttons.Y] = true,
        [buttons.B] = true,
        [buttons.A] = true,
        [buttons.X] = true,
    };

    -- Methods
    function device.GetSlotFromButton(buttonId)
        return device.ButtonToSlot[buttonId];
    end

    function device.GetSlotFromDPad(angle)
        if angle == nil or angle == -1 or angle == 65535 then return nil; end
        return device.DPadAngleToSlot[angle];
    end

    function device.GetSlotFromDPadButton(buttonId, buttonState)
        if buttonId ~= DPAD_BUTTON_OFFSET then return nil; end
        return device.GetSlotFromDPad(buttonState);
    end

    function device.IsCrossbarButton(buttonId)
        return device.CrossbarButtons[buttonId] == true;
    end

    function device.IsDPadButton(buttonId)
        return buttonId == DPAD_BUTTON_OFFSET;
    end

    function device.IsTriggerButton(buttonId)
        return buttonId == buttons.L2 or buttonId == buttons.R2;
    end

    function device.IsTriggerIntensity(buttonId)
        return false;  -- Stadia has no analog triggers
    end

    function device.IsL2Button(buttonId)
        return buttonId == buttons.L2;
    end

    function device.IsR2Button(buttonId)
        return buttonId == buttons.R2;
    end

    -- Shoulder button detection for palette cycling (R1/L1)
    function device.IsShoulderButton(buttonId)
        return buttonId == buttons.L1 or buttonId == buttons.R1;
    end

    function device.IsR1Button(buttonId)
        return buttonId == buttons.R1;
    end

    function device.IsL1Button(buttonId)
        return buttonId == buttons.L1;
    end

    return device;
end

-- ============================================
-- Generic DirectInput Profile (Fallback)
-- ============================================
-- For controllers that don't match DualSense or Switch Pro
local function CreateGenericDInputDevice(userConfig)
    userConfig = userConfig or {};

    -- Default to DualSense-style offsets
    local buttons = {
        FACE_BUTTON_TOP = userConfig.FACE_BUTTON_TOP or 51,       -- TOP BUTTON (e.g. Triangle/X)
        FACE_BUTTON_RIGHT = userConfig.FACE_BUTTON_RIGHT or 50,   -- RIGHT BUTTON (e.g. Circle/A)
        FACE_BUTTON_BOTTOM = userConfig.FACE_BUTTON_BOTTOM or 49, -- BOTTOM BUTTON (e.g. Cross/B)
        FACE_BUTTON_LEFT = userConfig.FACE_BUTTON_LEFT or 48,     -- LEFT BUTTON (e.g. Square/Y)
        L1 = userConfig.L1 or 52,
        R1 = userConfig.R1 or 53,
        L2 = userConfig.L2 or 54,
        R2 = userConfig.R2 or 55,
        DPAD = DPAD_BUTTON_OFFSET,
    };

    local device = {
        XInput = false,
        DirectInput = true,
        Name = 'Generic',
        DisplayName = 'Generic DirectInput',
        Buttons = buttons,
        HasAnalogTriggers = false,
    };

    -- D-pad angle to slot mapping
    device.DPadAngleToSlot = {
        [DPAD_ANGLES.UP] = 1,
        [DPAD_ANGLES.RIGHT] = 2,
        [DPAD_ANGLES.DOWN] = 3,
        [DPAD_ANGLES.LEFT] = 4,
    };

    -- Face button to slot mapping
    device.ButtonToSlot = {
        [buttons.FACE_BUTTON_TOP] = 5,
        [buttons.FACE_BUTTON_RIGHT] = 6,
        [buttons.FACE_BUTTON_BOTTOM] = 7,
        [buttons.FACE_BUTTON_LEFT] = 8,
    };

    -- Crossbar buttons
    device.CrossbarButtons = {
        [buttons.FACE_BUTTON_TOP] = true,
        [buttons.FACE_BUTTON_RIGHT] = true,
        [buttons.FACE_BUTTON_BOTTOM] = true,
        [buttons.FACE_BUTTON_LEFT] = true,
    };

    -- Methods
    function device.GetSlotFromButton(buttonId)
        return device.ButtonToSlot[buttonId];
    end

    function device.GetSlotFromDPad(angle)
        if angle == nil or angle == -1 or angle == 65535 then return nil; end
        return device.DPadAngleToSlot[angle];
    end

    function device.GetSlotFromDPadButton(buttonId, buttonState)
        if buttonId ~= DPAD_BUTTON_OFFSET then return nil; end
        return device.GetSlotFromDPad(buttonState);
    end

    function device.IsCrossbarButton(buttonId)
        return device.CrossbarButtons[buttonId] == true;
    end

    function device.IsDPadButton(buttonId)
        return buttonId == DPAD_BUTTON_OFFSET;
    end

    function device.IsTriggerButton(buttonId)
        return buttonId == buttons.L2 or buttonId == buttons.R2;
    end

    function device.IsTriggerIntensity(buttonId)
        return false;
    end

    function device.IsL2Button(buttonId)
        return buttonId == buttons.L2;
    end

    function device.IsR2Button(buttonId)
        return buttonId == buttons.R2;
    end

    -- Shoulder button detection for palette cycling (R1/L1)
    function device.IsShoulderButton(buttonId)
        return buttonId == buttons.L1 or buttonId == buttons.R1;
    end

    function device.IsR1Button(buttonId)
        return buttonId == buttons.R1;
    end

    function device.IsL1Button(buttonId)
        return buttonId == buttons.L1;
    end

    return device;
end

-- ============================================
-- Public API
-- ============================================

-- Scheme names (ordered for UI display)
local SCHEME_NAMES = { 'xbox', 'dualsense', 'switchpro', 'stadia', 'dinput' };

-- Display names for UI
local SCHEME_DISPLAY_NAMES = {
    xbox = 'Xbox / XInput',
    dualsense = 'PlayStation (DualSense/DualShock)',
    switchpro = 'Nintendo Switch Pro',
    stadia = 'Stadia Controller',
    dinput = 'Generic DirectInput',
};

-- Get a device by scheme name
-- @param schemeName: 'xbox', 'xinput', 'dualsense', 'switchpro', 'dinput'
-- @param userConfig: (optional) for generic dinput, table of button ID overrides
-- @return device table with all required methods
function M.GetDevice(schemeName, userConfig)
    if schemeName == 'xbox' or schemeName == 'xinput' then
        return xinput;
    elseif schemeName == 'dualsense' or schemeName == 'playstation' then
        return CreateDualSenseDevice();
    elseif schemeName == 'switchpro' or schemeName == 'switch' then
        return CreateSwitchProDevice();
    elseif schemeName == 'stadia' then
        return CreateStadiaDevice();
    elseif schemeName == 'dinput' or schemeName == 'generic' then
        return CreateGenericDInputDevice(userConfig);
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

-- Get display name for a specific scheme
function M.GetDisplayName(schemeName)
    return SCHEME_DISPLAY_NAMES[schemeName] or schemeName;
end

-- Normalize scheme name to input type ('xinput' or 'dinput')
function M.NormalizeScheme(schemeName)
    if schemeName == 'xbox' or schemeName == 'xinput' then
        return 'xinput';
    elseif schemeName == 'dualsense' or schemeName == 'switchpro' or schemeName == 'stadia' or schemeName == 'dinput' or schemeName == 'generic' then
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

-- Get D-pad angles (for reference)
function M.GetDPadAngles()
    return DPAD_ANGLES;
end

-- Get D-pad button offset
function M.GetDPadButtonOffset()
    return DPAD_BUTTON_OFFSET;
end

return M;
