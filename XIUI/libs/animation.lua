--[[
* XIUI Animation Library
* Reusable animation system for smooth transitions and effects
*
* Provides easing functions, animator state machine, tweening, and pulse helpers
* Reference: https://easings.net/
]]--

local M = {};

-- ========================================
-- Easing Functions
-- ========================================
-- All easing functions take normalized time t (0-1) and return normalized value (0-1)
-- Reference: https://easings.net/

function M.linear(t)
    return t;
end

function M.easeOutQuad(t)
    return 1 - math.pow(1 - t, 2);
end

function M.easeOutCubic(t)
    return 1 - math.pow(1 - t, 3);
end

function M.easeInOutQuad(t)
    if t < 0.5 then
        return 2 * t * t;
    else
        return 1 - math.pow(-2 * t + 2, 2) / 2;
    end
end

function M.easeInQuad(t)
    return t * t;
end

function M.easeInCubic(t)
    return t * t * t;
end

function M.easeOutBack(t)
    local c1 = 1.70158;
    local c3 = c1 + 1;
    return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2);
end

function M.easeOutElastic(t)
    local c4 = (2 * math.pi) / 3;
    if t == 0 then
        return 0;
    elseif t == 1 then
        return 1;
    else
        return math.pow(2, -10 * t) * math.sin((t * 10 - 0.75) * c4) + 1;
    end
end

function M.easeInOutCubic(t)
    if t < 0.5 then
        return 4 * t * t * t;
    else
        return 1 - math.pow(-2 * t + 2, 3) / 2;
    end
end

function M.easeOutExpo(t)
    -- Ease out exponential (from hp.lua for compatibility)
    if t < 1 then
        return 1 - math.pow(2, -10 * t);
    else
        return t;
    end
end

-- ========================================
-- Animator State Machine
-- ========================================
-- Manages animation state with start time, duration, and callbacks

-- Create a new animation
-- Parameters:
--   duration: animation duration in seconds
--   easing: easing function (e.g., M.easeOutQuad)
--   onUpdate: callback function(progress) where progress is 0-1
--   onComplete: optional callback when animation completes
-- Returns: animation state table
function M.create(duration, easing, onUpdate, onComplete)
    return {
        duration = duration,
        easing = easing or M.linear,
        onUpdate = onUpdate,
        onComplete = onComplete,
        startTime = nil,
        completed = false,
    };
end

-- Update an animation with current time
-- Parameters:
--   anim: animation state from create()
--   currentTime: os.clock() value
-- Returns: false if animation is complete, true otherwise
function M.update(anim, currentTime)
    if anim.completed then
        return false;
    end

    -- Start the animation if not started
    if not anim.startTime then
        anim.startTime = currentTime;
    end

    local elapsed = currentTime - anim.startTime;
    local progress = math.min(elapsed / anim.duration, 1.0);
    local easedProgress = anim.easing(progress);

    if anim.onUpdate then
        anim.onUpdate(easedProgress);
    end

    if progress >= 1.0 then
        anim.completed = true;
        if anim.onComplete then
            anim.onComplete();
        end
        return false;
    end

    return true;
end

-- Reset an animation to replay from the beginning
-- Parameters:
--   anim: animation state from create()
function M.reset(anim)
    anim.startTime = nil;
    anim.completed = false;
end

-- ========================================
-- Tween Helper
-- ========================================
-- Simplified animation for interpolating a single value

-- Create and manage a tween animation
-- Parameters:
--   target: table to modify
--   property: key in target table to animate
--   startValue: initial value
--   endValue: target value
--   duration: animation duration in seconds
--   easing: easing function (optional, defaults to linear)
-- Returns: animation state (pass to M.update to advance)
function M.tween(target, property, startValue, endValue, duration, easing)
    local range = endValue - startValue;
    return M.create(duration, easing, function(progress)
        target[property] = startValue + (range * progress);
    end);
end

-- ========================================
-- Pulse Helper
-- ========================================
-- Triangle wave oscillation for pulsing effects

-- Calculate a pulsing value based on current time
-- Parameters:
--   period: full cycle duration in seconds
--   minValue: minimum value
--   maxValue: maximum value
--   currentTime: os.clock() value (optional, uses os.clock() if not provided)
-- Returns: oscillating value between minValue and maxValue
function M.pulse(period, minValue, maxValue, currentTime)
    currentTime = currentTime or os.clock();
    local range = maxValue - minValue;
    local halfPeriod = period / 2;
    local phase = currentTime % period;

    -- Triangle wave: ramp up for half period, ramp down for second half
    local normalized;
    if phase < halfPeriod then
        normalized = phase / halfPeriod;
    else
        normalized = 1 - ((phase - halfPeriod) / halfPeriod);
    end

    return minValue + (range * normalized);
end

-- ========================================
-- Animation Pool
-- ========================================
-- Manage multiple named animations

M.AnimationPool = {
    -- Storage for active animations
    animations = {},

    -- Add or replace an animation in the pool
    set = function(key, animation)
        M.AnimationPool.animations[key] = animation;
    end,

    -- Get an animation from the pool
    get = function(key)
        return M.AnimationPool.animations[key];
    end,

    -- Remove an animation from the pool
    remove = function(key)
        M.AnimationPool.animations[key] = nil;
    end,

    -- Update all animations in the pool
    -- Automatically removes completed animations
    -- Parameters:
    --   currentTime: os.clock() value
    updateAll = function(currentTime)
        for key, anim in pairs(M.AnimationPool.animations) do
            local active = M.update(anim, currentTime);
            if not active then
                M.AnimationPool.animations[key] = nil;
            end
        end
    end,

    -- Clear all animations from the pool
    clearAll = function()
        M.AnimationPool.animations = {};
    end,
};

return M;
