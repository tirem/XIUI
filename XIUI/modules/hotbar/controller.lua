--[[
* XIUI Crossbar - Controller Input Module
* Handles both XInput and DirectInput controller input for crossbar slot activation
* Supports L2, R2, L2+R2, R2+L2 combo modes
* Device mappings: xbox (XInput), dualsense, switchpro, stadia (DirectInput)
]]--

local ffi = require('ffi');
local devices = require('modules.hotbar.devices');
local buttondetect = require('modules.hotbar.buttondetect');
local actions = require('modules.hotbar.actions');
local macrosLib = require('libs.ffxi.macros');

-- Define XINPUT structures for FFI access (only used for XInput devices)
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

-- Default trigger threshold (0-255 for XInput analog triggers)
local DEFAULT_TRIGGER_THRESHOLD = 30;

-- Default double-tap window (in seconds)
local DEFAULT_DOUBLE_TAP_WINDOW = 0.3;  -- 300ms

-- Debug logging (controlled via /xiui debug hotbar)
local DEBUG_ENABLED = false;
-- Verbose logging for raw input events (very spammy, use for troubleshooting only)
local DEBUG_VERBOSE = false;
-- Macro block specific debug (controlled via /xiui debug macroblock)
local DEBUG_MACROBLOCK = false;

--- Set debug mode for controller module
--- @param enabled boolean
--- @param verbose boolean|nil Optional verbose mode for raw input logging
local function SetDebugEnabled(enabled, verbose)
    DEBUG_ENABLED = enabled;
    if verbose ~= nil then
        DEBUG_VERBOSE = verbose;
    end
end

--- Set macro block debug mode for controller
--- @param enabled boolean
local function SetMacroBlockDebugEnabled(enabled)
    DEBUG_MACROBLOCK = enabled;
    -- Only print state summary if controller is already initialized
    if enabled and state and state.initialized then
        print(string.format('[Controller MacroBlock] Current state: blockingEnabled=%s, activeCombo=%s, L2=%s, R2=%s',
            tostring(blockingEnabled),
            tostring(state.activeCombo),
            tostring(state.leftTriggerHeld),
            tostring(state.rightTriggerHeld)));
        print(string.format('[Controller MacroBlock] Device: %s (XInput=%s, DirectInput=%s)',
            state.deviceName or 'not set',
            tostring(state.device and state.device.XInput),
            tostring(state.device and state.device.DirectInput)));
    end
    -- No message if not initialized - it will show state when controller events occur
end

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

-- Log macro blocking events (uses macroblock debug flag)
local function MacroBlockLog(msg)
    if DEBUG_MACROBLOCK then
        print('[Controller MacroBlock] ' .. msg);
    end
end

-- Get current time in seconds
local function GetTime()
    return os.clock();
end

-- Trigger hysteresis function - prevents jitter at threshold boundary
local function IsTriggerHeld(triggerValue, wasHeld, pressThreshold, releaseThreshold)
    if wasHeld then
        return triggerValue >= releaseThreshold;
    else
        return triggerValue >= pressThreshold;
    end
end

-- Auto-detect game's expected controller type from padmode000 registry setting
local function DetectGameControllerMode()
    local ok, result = pcall(function()
        local configMgr = AshitaCore:GetConfigurationManager();
        if not configMgr then return nil; end

        local padmodeStr = configMgr:GetString('boot', 'ffxi.registry', 'padmode000');
        if padmodeStr and padmodeStr ~= '' then
            local parts = {};
            for part in padmodeStr:gmatch('[^,]+') do
                table.insert(parts, part);
            end
            -- 6th value = XInput enabled (1) or DirectInput (0)
            if parts[6] == '1' then
                return 'xinput';
            else
                return 'dinput';
            end
        end
        return nil;
    end);
    return ok and result or nil;
end

-- Module state
local state = {
    initialized = false,
    enabled = false,
    triggerThreshold = DEFAULT_TRIGGER_THRESHOLD,
    triggerPressThreshold = DEFAULT_TRIGGER_THRESHOLD,  -- Threshold for press detection (hysteresis)
    triggerReleaseThreshold = 15,  -- Lower threshold for release detection (hysteresis)

    -- Device mapping (current controller scheme)
    deviceName = 'xbox',
    device = nil,  -- Will be set to device mapping table

    -- Trigger state tracking
    leftTriggerHeld = false,
    rightTriggerHeld = false,
    activeCombo = COMBO_MODES.NONE,
    comboFirstTrigger = nil,
    comboStartTime = nil,  -- Track when combo started

    -- Expanded crossbar (L2+R2, R2+L2)
    expandedCrossbarEnabled = true,

    -- Double-tap detection
    doubleTapEnabled = false,
    doubleTapWindow = DEFAULT_DOUBLE_TAP_WINDOW,
    leftTriggerLastRelease = 0,
    rightTriggerLastRelease = 0,
    isLeftDoubleTap = false,
    isRightDoubleTap = false,

    -- Button state tracking (to detect press events, not held state)
    previousButtons = 0,
    currentButtons = 0,
    currentPressedSlot = nil,
    lastPressedSlot = nil,
    pressedSlotTime = 0,
    heldButtons = {},

    -- DirectInput D-pad state tracking
    previousDPadAngle = -1,
    dpadHeldSlot = nil,

    -- Callback for slot activation
    onSlotActivate = nil,

    -- Debug: track if we've received any events
    receivedFirstEvent = false,
    receivedFirstDInputEvent = false,
};

-- Track whether game macro blocking is enabled
local blockingEnabled = true;

-- Initialize the controller module
function Controller.Initialize(settings)
    state.initialized = true;
    state.enabled = true;

    -- Load device mapping
    if settings and settings.controllerScheme then
        state.deviceName = settings.controllerScheme;
    end
    state.device = devices.GetDevice(state.deviceName);

    if settings then
        if settings.expandedCrossbarEnabled ~= nil then
            state.expandedCrossbarEnabled = settings.expandedCrossbarEnabled;
        end
        if settings.doubleTapEnabled ~= nil then
            state.doubleTapEnabled = settings.doubleTapEnabled;
        end
        if settings.doubleTapWindow then
            state.doubleTapWindow = settings.doubleTapWindow;
        end
    end

    DebugLog(string.format('Controller initialized (device: %s, XInput: %s, DirectInput: %s, threshold: %d, doubleTap: %s)',
        state.deviceName,
        tostring(state.device.XInput),
        tostring(state.device.DirectInput),
        state.triggerThreshold,
        tostring(state.doubleTapEnabled)));
end

-- Set the callback for slot activation
function Controller.SetSlotActivateCallback(callback)
    state.onSlotActivate = callback;
    DebugLog('Slot activation callback registered');
end

-- Set enabled state
function Controller.SetEnabled(enabled)
    state.enabled = enabled;
end

-- Update double-tap settings
function Controller.SetDoubleTapEnabled(enabled)
    state.doubleTapEnabled = enabled;
    DebugLog('Double-tap ' .. (enabled and 'enabled' or 'disabled'));
end

function Controller.SetDoubleTapWindow(window)
    state.doubleTapWindow = window or DEFAULT_DOUBLE_TAP_WINDOW;
end

-- Update expanded crossbar setting
function Controller.SetExpandedCrossbarEnabled(enabled)
    state.expandedCrossbarEnabled = enabled;
    DebugLog('Expanded crossbar ' .. (enabled and 'enabled' or 'disabled'));
end

-- Set controller scheme (device mapping)
function Controller.SetControllerScheme(schemeName)
    state.deviceName = schemeName or 'xbox';
    state.device = devices.GetDevice(state.deviceName);
    DebugLog(string.format('Controller scheme set to: %s (XInput: %s, DirectInput: %s)',
        state.deviceName, tostring(state.device.XInput), tostring(state.device.DirectInput)));
end

-- Get current controller scheme name
function Controller.GetControllerScheme()
    return state.deviceName;
end

-- Check if current device uses XInput
function Controller.UsesXInput()
    return state.device and state.device.XInput == true;
end

-- Check if current device uses DirectInput
function Controller.UsesDirectInput()
    return state.device and state.device.DirectInput == true;
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

-- Minimum time to show pressed visual (in seconds)
local PRESSED_VISUAL_MIN_DURATION = 0.15;

-- Get currently pressed slot index (1-8) or nil if no slot button is pressed
function Controller.GetPressedSlot()
    if state.currentPressedSlot then
        return state.currentPressedSlot;
    end
    if state.lastPressedSlot and state.pressedSlotTime > 0 then
        local elapsed = GetTime() - state.pressedSlotTime;
        if elapsed < PRESSED_VISUAL_MIN_DURATION then
            return state.lastPressedSlot;
        end
    end
    return nil;
end

-- Update combo state based on trigger held states
local function UpdateComboState(leftHeld, rightHeld)
    local wasLeftHeld = state.leftTriggerHeld;
    local wasRightHeld = state.rightTriggerHeld;
    local oldCombo = state.activeCombo;
    local currentTime = GetTime();

    -- Track trigger transitions
    local leftJustPressed = leftHeld and not wasLeftHeld;
    local rightJustPressed = rightHeld and not wasRightHeld;

    -- Track trigger releases for double-tap detection
    if wasLeftHeld and not leftHeld then
        state.leftTriggerLastRelease = currentTime;
        state.isLeftDoubleTap = false;
        DebugLog('L2 released');
    end
    if wasRightHeld and not rightHeld then
        state.rightTriggerLastRelease = currentTime;
        state.isRightDoubleTap = false;
        DebugLog('R2 released');
    end

    -- Handle combo state based on trigger combinations
    if leftHeld and rightHeld then
        -- Both triggers held - determine which expanded crossbar (only if enabled)
        if state.expandedCrossbarEnabled then
            if leftJustPressed and state.activeCombo == COMBO_MODES.R2 then
                -- R2 was held, now L2 added -> R2+L2
                DebugLog('L2 pressed (R2 held) -> R2+L2');
                state.activeCombo = COMBO_MODES.R2_THEN_L2;
            elseif rightJustPressed and state.activeCombo == COMBO_MODES.L2 then
                -- L2 was held, now R2 added -> L2+R2
                DebugLog('R2 pressed (L2 held) -> L2+R2');
                state.activeCombo = COMBO_MODES.L2_THEN_R2;
            elseif leftJustPressed and rightJustPressed then
                -- Both pressed at same time (rare) - default to L2+R2
                DebugLog('Both triggers pressed simultaneously');
                state.activeCombo = COMBO_MODES.L2_THEN_R2;
            end
            -- If already in an expanded combo, stay in it
        end
    elseif leftHeld and not rightHeld then
        -- Only L2 held
        if leftJustPressed then
            -- Check for double-tap
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
            else
                DebugLog('L2 pressed');
                state.activeCombo = COMBO_MODES.L2;
                state.comboFirstTrigger = 'L2';
            end
            -- Note: Native macro blocking is handled by zeroing trigger values in state_modified
        elseif state.activeCombo ~= COMBO_MODES.L2 and state.activeCombo ~= COMBO_MODES.L2_DOUBLE then
            -- Returning to L2 from expanded combo
            DebugLog('Returning to L2 (R2 released from expanded)');
            state.activeCombo = COMBO_MODES.L2;
            state.comboFirstTrigger = 'L2';
        end
    elseif rightHeld and not leftHeld then
        -- Only R2 held
        if rightJustPressed then
            -- Check for double-tap
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
            else
                DebugLog('R2 pressed');
                state.activeCombo = COMBO_MODES.R2;
                state.comboFirstTrigger = 'R2';
            end
            -- Note: Native macro blocking is handled by zeroing trigger values in state_modified
        elseif state.activeCombo ~= COMBO_MODES.R2 and state.activeCombo ~= COMBO_MODES.R2_DOUBLE then
            -- Returning to R2 from expanded combo
            DebugLog('Returning to R2 (L2 released from expanded)');
            state.activeCombo = COMBO_MODES.R2;
            state.comboFirstTrigger = 'R2';
        end
    else
        -- Both triggers released
        if state.activeCombo ~= COMBO_MODES.NONE then
            DebugLog('Triggers released');
        end
        state.activeCombo = COMBO_MODES.NONE;
        state.comboFirstTrigger = nil;
        state.comboStartTime = nil;
        state.isLeftDoubleTap = false;
        state.isRightDoubleTap = false;
        state.currentPressedSlot = nil;
        state.lastPressedSlot = nil;
        state.pressedSlotTime = 0;
        state.heldButtons = {};
        state.dpadHeldSlot = nil;
    end

    if state.activeCombo ~= oldCombo then
        DebugLog('Combo mode: ' .. tostring(state.activeCombo));
    end

    state.leftTriggerHeld = leftHeld;
    state.rightTriggerHeld = rightHeld;
end

-- Activate a slot (called when button pressed while trigger held)
local function ActivateSlot(slotIndex)
    if not slotIndex then return; end
    if state.activeCombo == COMBO_MODES.NONE then return; end

    -- Update visual state immediately
    state.currentPressedSlot = slotIndex;
    state.lastPressedSlot = slotIndex;
    state.pressedSlotTime = GetTime();

    DebugLog(string.format('Activating slot: %s[%d]', state.activeCombo, slotIndex));

    -- Defer actual action to next frame (avoids event handler context issues)
    local comboAtPress = state.activeCombo;
    ashita.tasks.once(0, function()
        if state.onSlotActivate then
            state.onSlotActivate(comboAtPress, slotIndex);
        end
    end);
end

-- ============================================
-- XInput Handlers (for xbox scheme)
-- ============================================

-- Get Xbox device mapping (for XInput button constants)
local xboxDevice = devices.GetDevice('xbox');

-- Handle XInput state event
function Controller.HandleXInputState(e)
    if not state.initialized or not state.enabled then
        DebugLogVerbose('Controller not initialized or not enabled');
        return;
    end

    -- Only process if using XInput device
    if not Controller.UsesXInput() then
        return;
    end

    if not state.receivedFirstEvent then
        DebugLog('Received first xinput_state event!');
        state.receivedFirstEvent = true;
    end

    if not e.state then
        DebugLogVerbose('No state in xinput_state event');
        return;
    end

    -- Wrap FFI operations in pcall for safety
    local ok, xinputState = pcall(function()
        return ffi.cast('XINPUT_STATE*', e.state);
    end);
    if not ok or not xinputState then
        DebugLogVerbose('Failed to cast xinput state');
        return;
    end

    -- Safely access gamepad data
    local gamepad;
    ok, gamepad = pcall(function()
        return xinputState.Gamepad;
    end);
    if not ok or not gamepad then
        DebugLogVerbose('Failed to access gamepad');
        return;
    end

    -- Get trigger values (0-255)
    local leftTrigger, rightTrigger, currentButtons;
    ok = pcall(function()
        leftTrigger = gamepad.bLeftTrigger;
        rightTrigger = gamepad.bRightTrigger;
        currentButtons = gamepad.wButtons;
    end);
    if not ok then
        DebugLogVerbose('Failed to read gamepad values');
        return;
    end

    if leftTrigger > 0 or rightTrigger > 0 or currentButtons ~= 0 then
        DebugLogVerbose(string.format('Raw input: L2=%d R2=%d buttons=0x%04X', leftTrigger, rightTrigger, currentButtons));
    end

    -- Determine if triggers are "pressed" using hysteresis to prevent jitter
    local pressThreshold = state.triggerPressThreshold or 30;
    local releaseThreshold = state.triggerReleaseThreshold or 15;

    local leftHeld = IsTriggerHeld(leftTrigger, state.leftTriggerHeld, pressThreshold, releaseThreshold);
    local rightHeld = IsTriggerHeld(rightTrigger, state.rightTriggerHeld, pressThreshold, releaseThreshold);

    -- Update combo state based on trigger changes
    UpdateComboState(leftHeld, rightHeld);

    -- Check for slot activation from state poll (button press detection)
    local newPresses = bit.band(currentButtons, bit.bnot(state.previousButtons));
    local slotIndex = xboxDevice.GetSlotFromButtonMask(newPresses);
    if slotIndex and state.activeCombo ~= COMBO_MODES.NONE then
        ActivateSlot(slotIndex);
    end

    state.currentButtons = currentButtons;
    state.previousButtons = currentButtons;

    -- Block when crossbar is active OR triggers are being used
    local shouldBlock = blockingEnabled and (
        state.activeCombo ~= COMBO_MODES.NONE or
        state.leftTriggerHeld or state.rightTriggerHeld or
        leftHeld or rightHeld
    );

    if shouldBlock then
        local triggerInfo = string.format('L2=%d R2=%d', leftTrigger, rightTrigger);
        local comboInfo = state.activeCombo ~= COMBO_MODES.NONE and state.activeCombo or 'trigger_only';
        MacroBlockLog(string.format('[XInput] BLOCKING native macro UI - combo=%s, %s', comboInfo, triggerInfo));

        DebugLog(string.format('Blocking triggers: blockingEnabled=%s, state_modified=%s, L2=%d, R2=%d',
            tostring(blockingEnabled), tostring(e.state_modified ~= nil), leftTrigger, rightTrigger));

        -- Stop any native macro execution
        macrosLib.stop('xinput_state');
        MacroBlockLog('[XInput] Called macrosLib.stop() to halt native macro');

        if e.state_modified then
            -- Wrap FFI modification in pcall for safety
            local modOk = pcall(function()
                local modifiedState = ffi.cast('XINPUT_STATE*', e.state_modified);
                if modifiedState then
                    local modifiedGamepad = modifiedState.Gamepad;
                    modifiedGamepad.bLeftTrigger = 0;
                    modifiedGamepad.bRightTrigger = 0;
                    local buttonsToKeep = bit.band(modifiedGamepad.wButtons, bit.bnot(xboxDevice.CrossbarButtonsMask));
                    modifiedGamepad.wButtons = buttonsToKeep;
                end
            end);
            if modOk then
                MacroBlockLog('[XInput] Zeroed trigger values in state_modified (blocked R2/L2 to game)');
                DebugLog('Zeroed trigger values in state_modified');
            else
                MacroBlockLog('[XInput] WARNING: Failed to modify state_modified');
                DebugLog('WARNING: Failed to modify state_modified');
            end
        else
            MacroBlockLog('[XInput] WARNING: e.state_modified is nil - cannot block triggers from game!');
            DebugLog('WARNING: e.state_modified is nil - cannot block triggers!');
        end
    elseif (leftHeld or rightHeld) and not blockingEnabled then
        MacroBlockLog(string.format('[XInput] Trigger pressed but blocking DISABLED (L2=%d R2=%d)', leftTrigger, rightTrigger));
    end
end

-- Handle XInput button event for blocking
function Controller.HandleXInputButton(e)
    if not state.initialized or not state.enabled then
        return false;
    end

    if not blockingEnabled then
        -- Log when button pressed but blocking disabled
        if e.state == 1 and state.activeCombo ~= COMBO_MODES.NONE then
            local slotIndex = xboxDevice.GetSlotFromButton(e.button);
            if slotIndex then
                MacroBlockLog(string.format('[XInput] Button %d pressed (slot %d) but blocking DISABLED - native macro will fire!',
                    e.button, slotIndex));
            end
        end
        return false;
    end

    -- Only process if using XInput device
    if not Controller.UsesXInput() then
        return false;
    end

    if state.activeCombo == COMBO_MODES.NONE then
        return false;
    end

    -- On button release
    if e.state == 0 then
        local buttonId = e.button;
        local slotIndex = xboxDevice.GetSlotFromButton(buttonId);
        if slotIndex and state.heldButtons then
            state.heldButtons[slotIndex] = nil;
            local anyHeld = false;
            for _, held in pairs(state.heldButtons) do
                if held then anyHeld = true; break; end
            end
            if not anyHeld then
                state.currentPressedSlot = nil;
            end
        end
        return false;
    end

    -- Check if this is a crossbar button
    local buttonId = e.button;
    local slotIndex = xboxDevice.GetSlotFromButton(buttonId);

    if slotIndex then
        state.heldButtons[slotIndex] = true;
        state.currentPressedSlot = slotIndex;
        state.lastPressedSlot = slotIndex;
        state.pressedSlotTime = GetTime();

        MacroBlockLog(string.format('[XInput] BLOCKING button %d -> slot %d (combo: %s) - native macro blocked, XIUI slot activated',
            buttonId, slotIndex, state.activeCombo));
        DebugLog(string.format('XInput Button PRESS: button=%d -> slot=%d (combo: %s)',
            buttonId, slotIndex, state.activeCombo));

        ActivateSlot(slotIndex);
        return true; -- Block the button
    end

    return false;
end

-- ============================================
-- DirectInput Handlers (for dualsense, switchpro, stadia)
-- ============================================

-- Handle DirectInput button event
function Controller.HandleDInputButton(e)
    if not state.initialized or not state.enabled then
        return false;
    end

    -- Check if button detection wizard is active first
    if buttondetect.IsActive() then
        if e.state == 1 then  -- Button pressed
            buttondetect.HandleButtonPress(e.button);
        end
        return true;  -- Block button during detection
    end

    -- Only process if using DirectInput device
    if not Controller.UsesDirectInput() then
        return false;
    end

    local device = state.device;
    local buttonId = e.button;
    local isPressed = e.state == 1;

    if not state.receivedFirstDInputEvent then
        DebugLog('Received first dinput_button event!');
        state.receivedFirstDInputEvent = true;
    end

    DebugLogVerbose(string.format('DInput button: id=%d state=%d', buttonId, e.state));

    -- Handle trigger buttons (L2/R2 on DirectInput are discrete buttons, not analog)
    if device.IsTriggerButton and device.IsTriggerButton(buttonId) then
        local isL2 = device.IsL2Button(buttonId);
        local isR2 = device.IsR2Button(buttonId);
        local triggerName = isL2 and 'L2' or (isR2 and 'R2' or 'unknown');

        if isL2 then
            UpdateComboState(isPressed, state.rightTriggerHeld);
        elseif isR2 then
            UpdateComboState(state.leftTriggerHeld, isPressed);
        end

        -- Block trigger buttons from game when crossbar is active
        if blockingEnabled and state.activeCombo ~= COMBO_MODES.NONE then
            MacroBlockLog(string.format('[DInput] BLOCKING %s trigger (button %d) - combo=%s, stopping native macro',
                triggerName, buttonId, state.activeCombo));
            macrosLib.stop('dinput_trigger');  -- Stop any native macro execution
            return true;
        elseif isPressed and not blockingEnabled then
            MacroBlockLog(string.format('[DInput] %s trigger pressed but blocking DISABLED (button %d)',
                triggerName, buttonId));
        end
        return false;
    end

    -- Handle face buttons
    if device.IsCrossbarButton and device.IsCrossbarButton(buttonId) then
        if not isPressed then
            -- Button released
            local slotIndex = device.GetSlotFromButton(buttonId);
            if slotIndex and state.heldButtons then
                state.heldButtons[slotIndex] = nil;
                local anyHeld = false;
                for _, held in pairs(state.heldButtons) do
                    if held then anyHeld = true; break; end
                end
                if not anyHeld and not state.dpadHeldSlot then
                    state.currentPressedSlot = nil;
                end
            end
            return false;
        end

        -- Button pressed
        if state.activeCombo == COMBO_MODES.NONE then
            return false;
        end

        local slotIndex = device.GetSlotFromButton(buttonId);
        if slotIndex then
            state.heldButtons[slotIndex] = true;
            state.currentPressedSlot = slotIndex;
            state.lastPressedSlot = slotIndex;
            state.pressedSlotTime = GetTime();

            DebugLog(string.format('DInput Button PRESS: button=%d -> slot=%d (combo: %s)',
                buttonId, slotIndex, state.activeCombo));

            if blockingEnabled then
                MacroBlockLog(string.format('[DInput] BLOCKING button %d -> slot %d (combo: %s) - native macro blocked, XIUI slot activated',
                    buttonId, slotIndex, state.activeCombo));
            else
                MacroBlockLog(string.format('[DInput] Button %d -> slot %d but blocking DISABLED - native macro will fire!',
                    buttonId, slotIndex));
            end

            ActivateSlot(slotIndex);

            if blockingEnabled then
                return true;
            end
        end
    end

    return false;
end

-- Handle DirectInput state event (for D-pad POV)
function Controller.HandleDInputState(e)
    if not state.initialized or not state.enabled then
        return;
    end

    -- Only process if using DirectInput device
    if not Controller.UsesDirectInput() then
        return;
    end

    local device = state.device;

    -- Handle D-pad (POV hat)
    -- DirectInput reports POV as an angle value, or -1 when centered
    if e.pov ~= nil then
        local povAngle = e.pov;
        local previousAngle = state.previousDPadAngle;

        DebugLogVerbose(string.format('DInput POV: %d (prev: %d)', povAngle, previousAngle));

        -- Check for new D-pad press (transition from centered or different direction)
        if povAngle ~= previousAngle then
            -- Release previous D-pad slot if any
            if state.dpadHeldSlot then
                state.heldButtons[state.dpadHeldSlot] = nil;
                state.dpadHeldSlot = nil;
            end

            -- Get new slot from current angle
            local slotIndex = device.GetSlotFromDPad and device.GetSlotFromDPad(povAngle);

            if slotIndex and state.activeCombo ~= COMBO_MODES.NONE then
                state.heldButtons[slotIndex] = true;
                state.dpadHeldSlot = slotIndex;
                state.currentPressedSlot = slotIndex;
                state.lastPressedSlot = slotIndex;
                state.pressedSlotTime = GetTime();

                DebugLog(string.format('DInput D-Pad PRESS: angle=%d -> slot=%d (combo: %s)',
                    povAngle, slotIndex, state.activeCombo));

                if blockingEnabled then
                    MacroBlockLog(string.format('[DInput] D-Pad angle=%d -> slot %d (combo: %s) - XIUI slot activated',
                        povAngle, slotIndex, state.activeCombo));
                else
                    MacroBlockLog(string.format('[DInput] D-Pad angle=%d -> slot %d but blocking DISABLED',
                        povAngle, slotIndex));
                end

                ActivateSlot(slotIndex);
            end

            -- Update if D-pad released (centered)
            if povAngle == -1 or povAngle == 65535 then
                local anyHeld = false;
                for _, held in pairs(state.heldButtons) do
                    if held then anyHeld = true; break; end
                end
                if not anyHeld then
                    state.currentPressedSlot = nil;
                end
            end
        end

        state.previousDPadAngle = povAngle;
    end
end

-- ============================================
-- Reset and Cleanup
-- ============================================

function Controller.Reset()
    state.leftTriggerHeld = false;
    state.rightTriggerHeld = false;
    state.activeCombo = COMBO_MODES.NONE;
    state.comboFirstTrigger = nil;
    state.previousButtons = 0;
    state.currentButtons = 0;
    state.currentPressedSlot = nil;
    state.lastPressedSlot = nil;
    state.pressedSlotTime = 0;
    state.heldButtons = {};
    state.leftTriggerLastRelease = 0;
    state.rightTriggerLastRelease = 0;
    state.isLeftDoubleTap = false;
    state.isRightDoubleTap = false;
    state.previousDPadAngle = -1;
    state.dpadHeldSlot = nil;
end

function Controller.Cleanup()
    state.initialized = false;
    state.enabled = false;
    state.onSlotActivate = nil;
    Controller.Reset();
end

-- ============================================
-- Game Macro Blocking
-- ============================================

function Controller.SetBlockingEnabled(enabled)
    local wasEnabled = blockingEnabled;
    blockingEnabled = enabled;
    DebugLog('Game macro blocking ' .. (enabled and 'enabled' or 'disabled'));
    if wasEnabled ~= enabled then
        MacroBlockLog(string.format('[Controller] Macro blocking state changed: %s -> %s',
            wasEnabled and 'ENABLED' or 'DISABLED',
            enabled and 'ENABLED' or 'DISABLED'));
    end
end

function Controller.IsBlockingEnabled()
    return blockingEnabled;
end

-- ============================================
-- Controller Detection
-- ============================================

-- Get detected controller info for display
-- Returns: { detected = bool, deviceType = string, name = string, inputReceived = bool }
function Controller.GetDetectedDeviceInfo()
    local info = {
        detected = false,
        deviceType = 'unknown',
        name = 'No controller detected',
        inputReceived = false,
        gameMode = nil,  -- 'xinput' or 'dinput' from game settings
    };

    -- Check game's controller mode setting
    info.gameMode = DetectGameControllerMode();

    -- Check if we've received any input events
    if state.receivedFirstEvent then
        info.detected = true;
        info.inputReceived = true;
        info.deviceType = 'xinput';
        info.name = 'XInput Controller (active)';
    elseif state.receivedFirstDInputEvent then
        info.detected = true;
        info.inputReceived = true;
        info.deviceType = 'dinput';
        info.name = 'DirectInput Controller (active)';
    elseif info.gameMode then
        -- Haven't received input yet, but game is configured for a mode
        info.detected = false;
        info.deviceType = info.gameMode;
        if info.gameMode == 'xinput' then
            info.name = 'XInput mode (no input yet)';
        else
            info.name = 'DirectInput mode (no input yet)';
        end
    end

    return info;
end

-- ============================================
-- Exports
-- ============================================

Controller.COMBO_MODES = COMBO_MODES;
Controller.DetectGameControllerMode = DetectGameControllerMode;

--- Set debug mode (called via /xiui debug hotbar)
function Controller.SetDebugEnabled(enabled, verbose)
    SetDebugEnabled(enabled, verbose);
end

--- Get debug mode state
function Controller.IsDebugEnabled()
    return DEBUG_ENABLED;
end

--- Set macro block debug mode (called via /xiui debug macroblock)
function Controller.SetMacroBlockDebugEnabled(enabled)
    SetMacroBlockDebugEnabled(enabled);
    print('[XIUI] Controller macro block debug: ' .. (enabled and 'ON' or 'OFF'));
end

--- Get macro block debug state
function Controller.IsMacroBlockDebugEnabled()
    return DEBUG_MACROBLOCK;
end

return Controller;
