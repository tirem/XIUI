--[[
* XIUI HP Utilities
* HP interpolation manager and HP color functions
*
* Note: GetCustomHpColors() uses GetGradientTextColor which is exported globally by helpers.lua
* This module should be loaded via helpers.lua to ensure globals are available
]]--

local M = {};

-- ========================================
-- HP Interpolation Manager
-- ========================================
-- Manages HP bar damage/healing animations with smooth transitions
-- Used by targetbar, partylist, and other HP bar modules
M.HpInterpolation = {
    -- Storage for interpolation states, keyed by a unique identifier
    states = {},

    -- Create or get an interpolation state for a given key
    getState = function(key)
        if not M.HpInterpolation.states[key] then
            M.HpInterpolation.states[key] = {
                currentTargetId = nil,
                currentHpp = 100,
                interpolationDamagePercent = 0,
                interpolationHealPercent = 0,
                lastHitTime = nil,
                lastHitAmount = nil,
                hitDelayStartTime = nil,
                lastHealTime = nil,
                lastHealAmount = nil,
                healDelayStartTime = nil,
                overlayAlpha = 0,
                healOverlayAlpha = 0,
                lastFrameTime = nil,
            };
        end
        return M.HpInterpolation.states[key];
    end,

    -- Reset a specific interpolation state
    reset = function(key)
        M.HpInterpolation.states[key] = nil;
    end,

    -- Clear all interpolation states
    clearAll = function()
        M.HpInterpolation.states = {};
    end,

    -- Update interpolation and return hpPercentData ready for progressbar.ProgressBar
    -- Parameters:
    --   key: unique identifier for this HP bar (e.g., "target", "tot", "party_0", etc.)
    --   hppPercent: current HP percentage (0-100)
    --   targetId: entity target index (used to detect target changes)
    --   settings: table with hitFlashDuration, hitDelayDuration, hitInterpolationDecayPercentPerSecond
    --   currentTime: os.clock() value
    --   gradient: {startColor, endColor} for the HP bar
    -- Returns: hpPercentData array for progressbar.ProgressBar
    update = function(key, hppPercent, targetId, settings, currentTime, gradient)
        local state = M.HpInterpolation.getState(key);

        -- If we change targets, reset the interpolation
        if state.currentTargetId ~= targetId then
            state.currentTargetId = targetId;
            state.currentHpp = hppPercent;
            state.interpolationDamagePercent = 0;
            state.interpolationHealPercent = 0;
            state.hitDelayStartTime = nil;
            state.healDelayStartTime = nil;
            state.lastHitTime = nil;
            state.lastHealTime = nil;
        end

        -- If the target takes damage
        if hppPercent < state.currentHpp then
            local previousInterpolationDamagePercent = state.interpolationDamagePercent;
            local damageAmount = state.currentHpp - hppPercent;

            state.interpolationDamagePercent = state.interpolationDamagePercent + damageAmount;

            if previousInterpolationDamagePercent > 0 and state.lastHitAmount and damageAmount > state.lastHitAmount then
                state.lastHitTime = currentTime;
                state.lastHitAmount = damageAmount;
            elseif previousInterpolationDamagePercent == 0 then
                state.lastHitTime = currentTime;
                state.lastHitAmount = damageAmount;
            end

            if not state.lastHitTime or currentTime > state.lastHitTime + (settings.hitFlashDuration * 0.25) then
                state.lastHitTime = currentTime;
                state.lastHitAmount = damageAmount;
            end

            if previousInterpolationDamagePercent == 0 then
                state.hitDelayStartTime = currentTime;
            end

            -- Clear healing interpolation when taking damage
            state.interpolationHealPercent = 0;
            state.healDelayStartTime = nil;
        elseif hppPercent > state.currentHpp then
            -- If the target heals
            local previousInterpolationHealPercent = state.interpolationHealPercent;
            local healAmount = hppPercent - state.currentHpp;

            state.interpolationHealPercent = state.interpolationHealPercent + healAmount;

            if previousInterpolationHealPercent > 0 and state.lastHealAmount and healAmount > state.lastHealAmount then
                state.lastHealTime = currentTime;
                state.lastHealAmount = healAmount;
            elseif previousInterpolationHealPercent == 0 then
                state.lastHealTime = currentTime;
                state.lastHealAmount = healAmount;
            end

            if not state.lastHealTime or currentTime > state.lastHealTime + (settings.hitFlashDuration * 0.25) then
                state.lastHealTime = currentTime;
                state.lastHealAmount = healAmount;
            end

            if previousInterpolationHealPercent == 0 then
                state.healDelayStartTime = currentTime;
            end

            -- Clear damage interpolation when healing
            state.interpolationDamagePercent = 0;
            state.hitDelayStartTime = nil;
        end

        state.currentHpp = hppPercent;

        -- Reduce the damage HP amount to display based on time passed
        if state.interpolationDamagePercent > 0 and state.hitDelayStartTime and currentTime > state.hitDelayStartTime + settings.hitDelayDuration then
            if state.lastFrameTime then
                local deltaTime = currentTime - state.lastFrameTime;
                local animSpeed = 0.1 + (0.9 * (state.interpolationDamagePercent / 100));
                state.interpolationDamagePercent = state.interpolationDamagePercent - (settings.hitInterpolationDecayPercentPerSecond * deltaTime * animSpeed);
                state.interpolationDamagePercent = math.max(0, state.interpolationDamagePercent);
            end
        end

        -- Reduce the healing HP amount to display based on time passed
        if state.interpolationHealPercent > 0 and state.healDelayStartTime and currentTime > state.healDelayStartTime + settings.hitDelayDuration then
            if state.lastFrameTime then
                local deltaTime = currentTime - state.lastFrameTime;
                local animSpeed = 0.1 + (0.9 * (state.interpolationHealPercent / 100));
                state.interpolationHealPercent = state.interpolationHealPercent - (settings.hitInterpolationDecayPercentPerSecond * deltaTime * animSpeed);
                state.interpolationHealPercent = math.max(0, state.interpolationHealPercent);
            end
        end

        -- Calculate damage flash overlay alpha
        state.overlayAlpha = 0;
        if gConfig.healthBarFlashEnabled then
            if state.lastHitTime and currentTime < state.lastHitTime + settings.hitFlashDuration then
                local hitFlashTime = currentTime - state.lastHitTime;
                local hitFlashTimePercent = hitFlashTime / settings.hitFlashDuration;
                local maxAlphaHitPercent = 20;
                local maxAlpha = math.min(state.lastHitAmount, maxAlphaHitPercent) / maxAlphaHitPercent;
                maxAlpha = math.max(maxAlpha * 0.6, 0.4);
                state.overlayAlpha = math.pow(1 - hitFlashTimePercent, 2) * maxAlpha;
            end
        end

        -- Calculate healing flash overlay alpha
        state.healOverlayAlpha = 0;
        if gConfig.healthBarFlashEnabled then
            if state.lastHealTime and currentTime < state.lastHealTime + settings.hitFlashDuration then
                local healFlashTime = currentTime - state.lastHealTime;
                local healFlashTimePercent = healFlashTime / settings.hitFlashDuration;
                local maxAlphaHealPercent = 20;
                local maxAlpha = math.min(state.lastHealAmount, maxAlphaHealPercent) / maxAlphaHealPercent;
                maxAlpha = math.max(maxAlpha * 0.6, 0.4);
                state.healOverlayAlpha = math.pow(1 - healFlashTimePercent, 2) * maxAlpha;
            end
        end

        state.lastFrameTime = currentTime;

        -- Build HP percent data with interpolation
        local baseHpPercent = hppPercent;
        if state.interpolationHealPercent and state.interpolationHealPercent > 0 then
            baseHpPercent = hppPercent - state.interpolationHealPercent;
            baseHpPercent = math.max(0, baseHpPercent);
        end

        local hpPercentData = {{baseHpPercent / 100, gradient}};

        -- Get configurable colors for damage/healing effects
        local interpColors = M.GetHpInterpolationColors();
        local damageGradient = interpColors.damageGradient;
        local damageFlashColor = interpColors.damageFlashColor;
        local healGradient = interpColors.healGradient;
        local healFlashColor = interpColors.healFlashColor;

        -- Add damage interpolation bar
        if state.interpolationDamagePercent > 0 then
            local interpolationOverlay;
            if gConfig.healthBarFlashEnabled and state.overlayAlpha > 0 then
                interpolationOverlay = {
                    damageFlashColor,
                    state.overlayAlpha
                };
            end
            table.insert(hpPercentData, {
                state.interpolationDamagePercent / 100,
                damageGradient,
                interpolationOverlay
            });
        end

        -- Add healing interpolation bar
        if state.interpolationHealPercent and state.interpolationHealPercent > 0 then
            local healInterpolationOverlay;
            if gConfig.healthBarFlashEnabled and state.healOverlayAlpha > 0 then
                healInterpolationOverlay = {
                    healFlashColor,
                    state.healOverlayAlpha
                };
            end
            table.insert(hpPercentData, {
                state.interpolationHealPercent / 100,
                healGradient,
                healInterpolationOverlay
            });
        end

        return hpPercentData;
    end,
};

-- ========================================
-- HP Interpolation Colors
-- ========================================

-- Get HP interpolation effect colors from shared config
-- Returns table with damageGradient, damageFlashColor, healGradient, healFlashColor
function M.GetHpInterpolationColors()
    local colors = {
        damageGradient = {'#cf3437', '#c54d4d'},
        damageFlashColor = '#ffacae',
        healGradient = {'#4ade80', '#86efac'},
        healFlashColor = '#c8ffc8',
    };

    if gConfig and gConfig.colorCustomization and gConfig.colorCustomization.shared then
        local shared = gConfig.colorCustomization.shared;
        if shared.hpDamageGradient then
            if shared.hpDamageGradient.enabled then
                colors.damageGradient = {shared.hpDamageGradient.start, shared.hpDamageGradient.stop};
            else
                colors.damageGradient = {shared.hpDamageGradient.start, shared.hpDamageGradient.start};
            end
        end
        if shared.hpDamageFlashColor then
            colors.damageFlashColor = shared.hpDamageFlashColor;
        end
        if shared.hpHealGradient then
            if shared.hpHealGradient.enabled then
                colors.healGradient = {shared.hpHealGradient.start, shared.hpHealGradient.stop};
            else
                colors.healGradient = {shared.hpHealGradient.start, shared.hpHealGradient.start};
            end
        end
        if shared.hpHealFlashColor then
            colors.healFlashColor = shared.hpHealFlashColor;
        end
    end

    return colors;
end

-- ========================================
-- HP Color Functions
-- ========================================

function M.GetHpColors(hpPercent)
    local hpNameColor;
    local hpGradient;
    if (hpPercent < .25) then
        hpNameColor = 0xFFFF0000;
        hpGradient = {"#ec3232", "#f16161"};
    elseif (hpPercent < .50) then;
        hpNameColor = 0xFFFFA500;
        hpGradient = {"#ee9c06", "#ecb44e"};
    elseif (hpPercent < .75) then
        hpNameColor = 0xFFFFFF00;
        hpGradient = {"#ffff0c", "#ffff97"};
    else
        hpNameColor = 0xFFFFFFFF;
        hpGradient = {"#e26c6c", "#fa9c9c"};
    end

    return hpNameColor, hpGradient;
end

-- Get HP gradient based on HP percent and custom colors
function M.GetCustomHpColors(hppPercent, moduleColorSettings)
    local hpNameColor, hpGradient;

    if not gConfig or not gConfig.colorCustomization or not moduleColorSettings then
        return M.GetHpColors(hppPercent);
    end

    local hpSettings = moduleColorSettings.hpGradient;

    if not hpSettings then
        return M.GetHpColors(hppPercent);
    end

    local selectedSettings;
    if hppPercent < 0.25 then
        selectedSettings = hpSettings.low;
    elseif hppPercent < 0.5 then
        selectedSettings = hpSettings.medLow;
    elseif hppPercent < 0.75 then
        selectedSettings = hpSettings.medHigh;
    else
        selectedSettings = hpSettings.high;
    end

    -- Check if gradient is enabled, otherwise use static color
    if selectedSettings.enabled then
        hpGradient = {selectedSettings.start, selectedSettings.stop};
    else
        hpGradient = {selectedSettings.start, selectedSettings.start};
    end

    -- Convert first gradient color to ARGB for text
    hpNameColor = GetGradientTextColor(hpGradient[1]);

    return hpNameColor, hpGradient;
end

-- Get gradient colors from settings with fallback to defaults
function M.GetCustomGradient(moduleSettings, gradientName)
    if not gConfig or not gConfig.colorCustomization or not moduleSettings then
        return nil;
    end

    local gradient = moduleSettings[gradientName];
    if not gradient then
        return nil;
    end

    if gradient.enabled then
        return {gradient.start, gradient.stop};
    else
        return {gradient.start, gradient.start};
    end
end

-- ========================================
-- Easing Functions
-- ========================================
-- Reference: https://easings.net/

function M.easeOutPercent(percent)
    -- Ease out exponential
    if percent < 1 then
        return 1 - math.pow(2, -10 * percent);
    else
        return percent;
    end
end

return M;
