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

local buttonOrder = { 'L2', 'R2', 'CROSS', 'CIRCLE', 'SQUARE', 'TRIANGLE' };
local buttonPrompts = {
    L2 = 'Press your LEFT TRIGGER (L2/LT/ZL)',
    R2 = 'Press your RIGHT TRIGGER (R2/RT/ZR)',
    CROSS = 'Press your BOTTOM face button (X/A/B)',
    CIRCLE = 'Press your RIGHT face button (O/B/A)',
    SQUARE = 'Press your LEFT face button (Square/X/Y)',
    TRIANGLE = 'Press your TOP face button (Triangle/Y/X)',
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
