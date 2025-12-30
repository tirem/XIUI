--[[
* XIUI Crossbar - Controller Input Module
* Handles XInput controller input for crossbar slot activation
* Supports L2, R2, L2+R2, R2+L2 combo modes
]]--

local ffi = require('ffi');

-- Define XINPUT structures for FFI access
ffi.cdef[[
    typedef struct {
        uint16_t wButtons;
        uint8_t  bLeftTrigger;
        uint8_t  bRightTrigger;
        int16_t  sThumbLX;
        int16_t  sThumbLY;
        int16_t  sThumbRX;
        int16_t  sThumbRY;
    } XINPUT_GAMEPAD;

    typedef struct {
        uint32_t       dwPacketNumber;
        XINPUT_GAMEPAD Gamepad;
    } XINPUT_STATE;
]];

local Controller = {};

-- XInput button constants (standard Windows values)
local XINPUT = {
    -- D-Pad
    DPAD_UP         = 0x0001,
    DPAD_DOWN       = 0x0002,
    DPAD_LEFT       = 0x0004,
    DPAD_RIGHT      = 0x0008,
    -- System
    START           = 0x0010,
    BACK            = 0x0020,
    -- Thumbsticks (click)
    LEFT_THUMB      = 0x0040,
    RIGHT_THUMB     = 0x0080,
    -- Shoulder buttons (L1/R1)
    LEFT_SHOULDER   = 0x0100,  -- L1/LB
    RIGHT_SHOULDER  = 0x0200,  -- R1/RB
    -- Face buttons
    A               = 0x1000,  -- X on PlayStation
    B               = 0x2000,  -- Circle on PlayStation
    X               = 0x4000,  -- Square on PlayStation
    Y               = 0x8000,  -- Triangle on PlayStation
};

-- Combo modes
local COMBO_MODES = {
    NONE = 'none',
    L2 = 'L2',
    R2 = 'R2',
    L2_THEN_R2 = 'L2R2',  -- Expanded crossbar: L2 first, then R2
    R2_THEN_L2 = 'R2L2',  -- Expanded crossbar: R2 first, then L2
    L2_DOUBLE = 'L2x2',   -- Double-tap L2
    R2_DOUBLE = 'R2x2',   -- Double-tap R2
};

-- Default trigger threshold (0-255)
local DEFAULT_TRIGGER_THRESHOLD = 30;

-- Default double-tap window (in seconds)
local DEFAULT_DOUBLE_TAP_WINDOW = 0.3;  -- 300ms

-- Debug logging (set to true to enable)
local DEBUG_ENABLED = true;
-- Verbose logging for raw input events (very spammy, use for troubleshooting only)
local DEBUG_VERBOSE = false;

local function DebugLog(msg)
    if DEBUG_ENABLED then
        print('[Crossbar Controller] ' .. msg);
    end
end

local function DebugLogVerbose(msg)
    if DEBUG_VERBOSE then
        print('[Crossbar Controller] ' .. msg);
    end
end

-- Get current time in seconds
local function GetTime()
    return os.clock();
end

-- Module state
local state = {
    initialized = false,
    enabled = false,
    triggerThreshold = DEFAULT_TRIGGER_THRESHOLD,

    -- Trigger state tracking
    leftTriggerHeld = false,
    rightTriggerHeld = false,
    activeCombo = COMBO_MODES.NONE,
    comboFirstTrigger = nil,

    -- Double-tap detection
    doubleTapEnabled = false,          -- Must be enabled in settings
    doubleTapWindow = DEFAULT_DOUBLE_TAP_WINDOW,
    leftTriggerLastRelease = 0,        -- Timestamp when L2 was last released
    rightTriggerLastRelease = 0,       -- Timestamp when R2 was last released
    isLeftDoubleTap = false,           -- True if current L2 press is a double-tap
    isRightDoubleTap = false,          -- True if current R2 press is a double-tap

    -- Button state tracking (to detect press events, not held state)
    previousButtons = 0,
    currentButtons = 0,         -- Currently held buttons (for pressed visual state)
    currentPressedSlot = nil,   -- Currently pressed slot index (1-8) or nil

    -- Callback for slot activation
    onSlotActivate = nil,

    -- Debug: track if we've received any events
    receivedFirstEvent = false,
};

-- Initialize the controller module
function Controller.Initialize(settings)
    state.initialized = true;
    state.enabled = true;
    if settings then
        if settings.triggerThreshold then
            state.triggerThreshold = settings.triggerThreshold;
        end
        if settings.doubleTapEnabled ~= nil then
            state.doubleTapEnabled = settings.doubleTapEnabled;
        end
        if settings.doubleTapWindow then
            state.doubleTapWindow = settings.doubleTapWindow;
        end
    end
    DebugLog(string.format('Controller initialized (threshold: %d, doubleTap: %s)',
        state.triggerThreshold, tostring(state.doubleTapEnabled)));
end

-- Set the callback for slot activation
-- callback(comboMode, slotIndex) where comboMode is 'L2', 'R2', 'L2R2', or 'R2L2' and slotIndex is 1-8
function Controller.SetSlotActivateCallback(callback)
    state.onSlotActivate = callback;
    DebugLog('Slot activation callback registered');
end

-- Set enabled state
function Controller.SetEnabled(enabled)
    state.enabled = enabled;
end

-- Update trigger threshold
function Controller.SetTriggerThreshold(threshold)
    state.triggerThreshold = threshold or DEFAULT_TRIGGER_THRESHOLD;
end

-- Update double-tap settings
function Controller.SetDoubleTapEnabled(enabled)
    state.doubleTapEnabled = enabled;
    DebugLog('Double-tap ' .. (enabled and 'enabled' or 'disabled'));
end

function Controller.SetDoubleTapWindow(window)
    state.doubleTapWindow = window or DEFAULT_DOUBLE_TAP_WINDOW;
end

-- Check if double-tap is enabled
function Controller.IsDoubleTapEnabled()
    return state.doubleTapEnabled;
end

-- Get the current active combo mode
function Controller.GetActiveCombo()
    return state.activeCombo;
end

-- Check if any trigger is held
function Controller.IsAnyTriggerHeld()
    return state.leftTriggerHeld or state.rightTriggerHeld;
end

-- Check if L2 is held
function Controller.IsL2Held()
    return state.leftTriggerHeld;
end

-- Check if R2 is held
function Controller.IsR2Held()
    return state.rightTriggerHeld;
end

-- Get currently pressed slot index (1-8) or nil if no slot button is pressed
function Controller.GetPressedSlot()
    return state.currentPressedSlot;
end

-- Update combo state based on trigger held states
local function UpdateComboState(leftHeld, rightHeld)
    local wasLeftHeld = state.leftTriggerHeld;
    local wasRightHeld = state.rightTriggerHeld;
    local oldCombo = state.activeCombo;
    local currentTime = GetTime();

    -- Track trigger releases for double-tap detection
    if wasLeftHeld and not leftHeld then
        state.leftTriggerLastRelease = currentTime;
        state.isLeftDoubleTap = false;  -- Reset double-tap flag on release
        DebugLog('L2 released');
    end
    if wasRightHeld and not rightHeld then
        state.rightTriggerLastRelease = currentTime;
        state.isRightDoubleTap = false;  -- Reset double-tap flag on release
        DebugLog('R2 released');
    end

    -- Detect L2 press (transition from not held to held)
    if leftHeld and not wasLeftHeld then
        -- Check for double-tap (only valid when coming from NONE state - a clean double-tap)
        local timeSinceRelease = currentTime - state.leftTriggerLastRelease;
        local isDoubleTap = state.doubleTapEnabled
            and oldCombo == COMBO_MODES.NONE
            and timeSinceRelease <= state.doubleTapWindow
            and state.leftTriggerLastRelease > 0;
        DebugLog(string.format('L2 press - doubleTapEnabled=%s, oldCombo=%s, timeSinceRelease=%.3f, window=%.3f',
            tostring(state.doubleTapEnabled), tostring(oldCombo), timeSinceRelease, state.doubleTapWindow));

        if isDoubleTap then
            DebugLog('L2 double-tap detected');
            state.isLeftDoubleTap = true;
            state.activeCombo = COMBO_MODES.L2_DOUBLE;
            state.comboFirstTrigger = 'L2x2';
        elseif state.rightTriggerHeld then
            -- R2 was already held, now L2 pressed = R2→L2 combo
            DebugLog('L2 pressed (R2 held)');
            state.activeCombo = COMBO_MODES.R2_THEN_L2;
        else
            -- L2 pressed alone
            DebugLog('L2 pressed');
            state.activeCombo = COMBO_MODES.L2;
            state.comboFirstTrigger = 'L2';
        end
    -- Detect R2 press (transition from not held to held)
    elseif rightHeld and not wasRightHeld then
        -- Check for double-tap (only valid when coming from NONE state - a clean double-tap)
        local timeSinceRelease = currentTime - state.rightTriggerLastRelease;
        local isDoubleTap = state.doubleTapEnabled
            and oldCombo == COMBO_MODES.NONE
            and timeSinceRelease <= state.doubleTapWindow
            and state.rightTriggerLastRelease > 0;
        DebugLog(string.format('R2 press - doubleTapEnabled=%s, oldCombo=%s, timeSinceRelease=%.3f, window=%.3f',
            tostring(state.doubleTapEnabled), tostring(oldCombo), timeSinceRelease, state.doubleTapWindow));

        if isDoubleTap then
            DebugLog('R2 double-tap detected');
            state.isRightDoubleTap = true;
            state.activeCombo = COMBO_MODES.R2_DOUBLE;
            state.comboFirstTrigger = 'R2x2';
        elseif state.leftTriggerHeld then
            -- L2 was already held, now R2 pressed = L2→R2 combo
            DebugLog('R2 pressed (L2 held)');
            state.activeCombo = COMBO_MODES.L2_THEN_R2;
        else
            -- R2 pressed alone
            DebugLog('R2 pressed');
            state.activeCombo = COMBO_MODES.R2;
            state.comboFirstTrigger = 'R2';
        end
    -- Handle partial release from expanded combos (one trigger released, other still held)
    elseif wasLeftHeld and wasRightHeld then
        -- Was in expanded combo (both triggers held), now one is released
        if leftHeld and not rightHeld then
            -- R2 released, L2 still held → return to L2 combo
            DebugLog('R2 released from expanded combo, returning to L2');
            state.activeCombo = COMBO_MODES.L2;
            state.comboFirstTrigger = 'L2';
        elseif rightHeld and not leftHeld then
            -- L2 released, R2 still held → return to R2 combo
            DebugLog('L2 released from expanded combo, returning to R2');
            state.activeCombo = COMBO_MODES.R2;
            state.comboFirstTrigger = 'R2';
        end
    -- Both triggers released
    elseif not leftHeld and not rightHeld then
        if state.activeCombo ~= COMBO_MODES.NONE then
            DebugLog('Triggers released');
        end
        state.activeCombo = COMBO_MODES.NONE;
        state.comboFirstTrigger = nil;
        state.isLeftDoubleTap = false;
        state.isRightDoubleTap = false;
    end

    -- Log combo mode change
    if state.activeCombo ~= oldCombo then
        DebugLog('Combo mode: ' .. tostring(state.activeCombo));
    end

    -- Update held states
    state.leftTriggerHeld = leftHeld;
    state.rightTriggerHeld = rightHeld;
end

-- Button name lookup for debug logging
local BUTTON_NAMES = {
    [1] = 'D-Pad Up',
    [2] = 'D-Pad Right',
    [3] = 'D-Pad Down',
    [4] = 'D-Pad Left',
    [5] = 'Y/Triangle',
    [6] = 'B/Circle',
    [7] = 'A/X',
    [8] = 'X/Square',
};

-- Map button press to slot index (1-8)
-- Returns nil if no relevant button is pressed
local function GetSlotIndexFromButtons(buttons)
    -- D-pad buttons map to slots 1-4
    if bit.band(buttons, XINPUT.DPAD_UP) ~= 0 then return 1; end
    if bit.band(buttons, XINPUT.DPAD_RIGHT) ~= 0 then return 2; end
    if bit.band(buttons, XINPUT.DPAD_DOWN) ~= 0 then return 3; end
    if bit.band(buttons, XINPUT.DPAD_LEFT) ~= 0 then return 4; end

    -- Face buttons map to slots 5-8
    if bit.band(buttons, XINPUT.Y) ~= 0 then return 5; end       -- Triangle
    if bit.band(buttons, XINPUT.B) ~= 0 then return 6; end       -- Circle
    if bit.band(buttons, XINPUT.A) ~= 0 then return 7; end       -- X
    if bit.band(buttons, XINPUT.X) ~= 0 then return 8; end       -- Square

    return nil;
end

-- Check for slot activation (button pressed while trigger held)
local function CheckSlotActivation(currentButtons)
    -- Only check if a trigger is held and we have a valid combo mode
    if state.activeCombo == COMBO_MODES.NONE then
        return;
    end

    -- Detect button press (transition from not pressed to pressed)
    -- by comparing with previous button state
    local newPresses = bit.band(currentButtons, bit.bnot(state.previousButtons));

    local slotIndex = GetSlotIndexFromButtons(newPresses);
    if slotIndex then
        local buttonName = BUTTON_NAMES[slotIndex] or tostring(slotIndex);
        DebugLog(string.format('Button pressed: %s (slot %d) while %s held', buttonName, slotIndex, state.activeCombo));
        if state.onSlotActivate then
            DebugLog(string.format('Activating slot: %s[%d]', state.activeCombo, slotIndex));
            state.onSlotActivate(state.activeCombo, slotIndex);
        else
            DebugLog('Warning: No slot activation callback registered');
        end
    end
end

-- Handle XInput state event
-- Call this from the xinput_state event handler
function Controller.HandleXInputState(e)
    if not state.initialized or not state.enabled then
        DebugLogVerbose('Controller not initialized or not enabled');
        return;
    end

    -- Log that we received an event (only once to avoid spam)
    if not state.receivedFirstEvent then
        DebugLog('Received first xinput_state event!');
        state.receivedFirstEvent = true;
    end

    -- Cast the userdata to XINPUT_STATE pointer using FFI
    if not e.state then
        DebugLogVerbose('No state in xinput_state event');
        return;
    end

    local xinputState = ffi.cast('XINPUT_STATE*', e.state);
    if not xinputState then
        DebugLogVerbose('Failed to cast xinput state');
        return;
    end

    local gamepad = xinputState.Gamepad;

    -- Get trigger values (0-255)
    local leftTrigger = gamepad.bLeftTrigger;
    local rightTrigger = gamepad.bRightTrigger;
    local currentButtons = gamepad.wButtons;

    -- Verbose logging of raw input (very spammy)
    if leftTrigger > 0 or rightTrigger > 0 or currentButtons ~= 0 then
        DebugLogVerbose(string.format('Raw input: L2=%d R2=%d buttons=0x%04X', leftTrigger, rightTrigger, currentButtons));
    end

    -- Determine if triggers are "pressed" based on threshold
    local leftHeld = leftTrigger >= state.triggerThreshold;
    local rightHeld = rightTrigger >= state.triggerThreshold;

    -- Update combo state based on trigger changes
    UpdateComboState(leftHeld, rightHeld);

    -- Check for slot activation (button + trigger combo)
    CheckSlotActivation(currentButtons);

    -- Track currently held buttons and pressed slot for visual feedback
    state.currentButtons = currentButtons;
    if state.activeCombo ~= COMBO_MODES.NONE then
        state.currentPressedSlot = GetSlotIndexFromButtons(currentButtons);
    else
        state.currentPressedSlot = nil;
    end

    -- Store current button state for next frame comparison
    state.previousButtons = currentButtons;
end

-- Reset controller state (call on zone change, etc.)
function Controller.Reset()
    state.leftTriggerHeld = false;
    state.rightTriggerHeld = false;
    state.activeCombo = COMBO_MODES.NONE;
    state.comboFirstTrigger = nil;
    state.previousButtons = 0;
    state.currentButtons = 0;
    state.currentPressedSlot = nil;
    -- Reset double-tap state
    state.leftTriggerLastRelease = 0;
    state.rightTriggerLastRelease = 0;
    state.isLeftDoubleTap = false;
    state.isRightDoubleTap = false;
    -- Don't reset receivedFirstEvent so we only log once per session
end

-- Cleanup
function Controller.Cleanup()
    state.initialized = false;
    state.enabled = false;
    state.onSlotActivate = nil;
    Controller.Reset();
end

-- Export constants for external use
Controller.COMBO_MODES = COMBO_MODES;
Controller.XINPUT = XINPUT;

return Controller;
