--[[
* XIUI Crossbar - Button Detection Wizard
* Helps users configure DirectInput button IDs for non-standard controllers
]]--

local M = {};

local detectState = {
    active = false,
    currentButton = nil,
    callback = nil,
    detectedButtons = {},
    currentIndex = 1,
};

local buttonOrder = { 'L2', 'R2', 'FACE_BUTTON_TOP', 'FACE_BUTTON_RIGHT', 'FACE_BUTTON_BOTTOM', 'FACE_BUTTON_LEFT', 'L1', 'R1' };
local buttonPrompts = {
    L2 = 'Press your LEFT TRIGGER (L2/LT/ZL)',
    R2 = 'Press your RIGHT TRIGGER (R2/RT/ZR)',
    FACE_BUTTON_TOP = 'Press your TOP face button (Triangle/Y/X)',
    FACE_BUTTON_RIGHT = 'Press your RIGHT face button (Circle/B/A)',
    FACE_BUTTON_BOTTOM = 'Press your BOTTOM face button (Cross/A/B)',
    FACE_BUTTON_LEFT = 'Press your LEFT face button (Square/X/Y)',
    L1 = 'Press your LEFT SHOULDER button (L1/LB)',
    R1 = 'Press your RIGHT SHOULDER button (R1/RB)',
};

function M.StartDetection(callback)
    detectState.active = true;
    detectState.detectedButtons = {};
    detectState.callback = callback;
    detectState.currentIndex = 1;
    detectState.currentButton = buttonOrder[1];
end

function M.GetCurrentPrompt()
    if not detectState.active then return nil; end
    return buttonPrompts[detectState.currentButton];
end

function M.GetCurrentButtonName()
    return detectState.currentButton;
end

function M.IsActive()
    return detectState.active;
end

function M.HandleButtonPress(buttonId)
    if not detectState.active then return false; end

    detectState.detectedButtons[detectState.currentButton] = buttonId;
    detectState.currentIndex = detectState.currentIndex + 1;

    if detectState.currentIndex > #buttonOrder then
        local results = detectState.detectedButtons;
        detectState.active = false;
        detectState.currentButton = nil;

        if detectState.callback then
            detectState.callback(results);
        end
    else
        detectState.currentButton = buttonOrder[detectState.currentIndex];
    end

    return true;  -- Consume the button press
end

function M.Cancel()
    detectState.active = false;
    detectState.currentButton = nil;
    detectState.detectedButtons = {};
    detectState.currentIndex = 1;
end

function M.GetProgress()
    if not detectState.active then return 0, #buttonOrder; end
    return detectState.currentIndex - 1, #buttonOrder;
end

return M;
