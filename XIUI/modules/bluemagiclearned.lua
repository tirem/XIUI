--[[
* Blue Magic learned banner for XIUI
*
* Shows a celebration banner when the local player learns a Blue Magic spell
* (incoming message 419 on 0x0029). Animation matches the ActionLearned banner
* timing/phases; sizing fits the art into a screen-relative box so it tracks
* any monitor resolution without stretching.
]]--

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local TextureManager = require('libs.texturemanager');
local defaultPositions = require('libs.defaultpositions');

local bluemagiclearned = {};

local WINDOW_NAME = 'BlueMagicLearned';
local TEXTURE_PATH = 'notifications/blue_magic_learned';
local SOUND_PATH = string.format('%s/assets/notifications/blue_magic_learned.wav', addon.path);

-- Message 419: "Player learns <spell>!" (Blue Magic).
local LEARNED_MESSAGE_ID = 419;

-- Animation timing (seconds). Hold duration is user-configurable.
local SLIDE_DURATION = 0.70;
local PULSE_DURATION = 0.30;
local FADE_DURATION = 0.50;
local SLIDE_ALPHA = 150 / 255;
local PULSE_MAX_SCALE = 1.18;

-- Fallback size if the PNG has not loaded yet (matches the design box).
local FALLBACK_W = 720;
local FALLBACK_H = 200;

local hidden = false;
local animStart = 0;
local animMode = nil; -- 'event' | 'preview' | nil
local tintRGBA = { 1.0, 1.0, 1.0, 1.0 };

local function Clamp(value, minValue, maxValue)
    if value < minValue then return minValue; end
    if value > maxValue then return maxValue; end
    return value;
end

local function EaseOutCubic(t)
    local inv = 1 - t;
    return 1 - (inv * inv * inv);
end

local function Lerp(a, b, t)
    return a + (b - a) * t;
end

local function IsEnabled()
    return gConfig ~= nil and gConfig.blueMagicLearnedEnabled ~= false;
end

local function GetHoldSeconds()
    return Clamp(gConfig and gConfig.blueMagicLearnedDuration or 3, 1, 10);
end

local function GetEffectiveScale()
    local scale = gConfig and gConfig.blueMagicLearnedScale or 1.0;
    local globalScale = gConfig and gConfig.globalScale or 1.0;
    return scale * globalScale;
end

-- Fit the texture into the screen-scaled 720x200-style box (letterbox, no stretch).
local function GetFittedSize(texture)
    local texW, texH = TextureManager.getTextureDimensions(texture, FALLBACK_W, FALLBACK_H);
    local drawW, drawH = defaultPositions.FitBlueMagicLearned(texW, texH, GetEffectiveScale());
    return drawW, drawH;
end

local function EnsureDefaultPosition()
    if not gConfig then return; end
    if not gConfig.windowPositions then
        gConfig.windowPositions = {};
    end
    if not gConfig.windowPositions[WINDOW_NAME] then
        local x, y = defaultPositions.GetBlueMagicLearnedPosition();
        gConfig.windowPositions[WINDOW_NAME] = { x = x, y = y };
    end
end

local function ClearAnimation()
    animStart = 0;
    animMode = nil;
end

local function StartAnimation(mode)
    animMode = mode;
    animStart = os.clock();
end

-- Preview only while the config window is open; lockPositions still applies.
local function IsLivePreviewActive()
    return IsEnabled()
        and gConfig.blueMagicLearnedPreview == true
        and showConfig
        and showConfig[1] == true;
end

-- Returns nil once the sequence (slide -> pulse -> hold -> fade) is finished.
local function GetAnimationState(elapsed, holdSeconds)
    local slideEnd = SLIDE_DURATION;
    local pulseEnd = slideEnd + PULSE_DURATION;
    local holdEnd = pulseEnd + holdSeconds;
    local totalDuration = holdEnd + FADE_DURATION;

    if elapsed >= totalDuration then
        return nil;
    end

    local alpha = 1.0;
    local scaleMult = 1.0;
    local slideT = 1.0;
    local phase = 'hold';

    if elapsed < slideEnd then
        phase = 'slide';
        slideT = EaseOutCubic(elapsed / SLIDE_DURATION);
    elseif elapsed < pulseEnd then
        phase = 'pulse';
        local t = (elapsed - slideEnd) / PULSE_DURATION;
        local pulseWave = math.sin(math.pi * Clamp(t, 0, 1));
        scaleMult = 1 + (PULSE_MAX_SCALE - 1) * pulseWave;
    elseif elapsed >= holdEnd then
        phase = 'fade';
        local t = (elapsed - holdEnd) / FADE_DURATION;
        alpha = 1.0 - Clamp(t, 0, 1);
    end

    return phase, alpha, scaleMult, slideT;
end

local function DrawImage(drawList, texturePtr, x, y, w, h, alpha)
    tintRGBA[4] = alpha;
    drawList:AddImage(
        texturePtr,
        { x, y },
        { x + w, y + h },
        { 0, 0 }, { 1, 1 },
        imgui.GetColorU32(tintRGBA)
    );
end

local function DrawAnimatedBanner(texturePtr, drawW, drawH, elapsed, holdSeconds)
    local phase, alpha, scaleMult, slideT = GetAnimationState(elapsed, holdSeconds);
    if not phase then
        return false;
    end

    -- Window stays at resting size so position saves stay stable while pulse grows.
    imgui.SetNextWindowSize({ drawW, drawH }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });

    EnsureDefaultPosition();
    ApplyWindowPosition(WINDOW_NAME);
    if imgui.Begin(WINDOW_NAME, true, GetBaseWindowFlags(gConfig.lockPositions)) then
        SaveWindowPosition(WINDOW_NAME);

        local originX, originY = imgui.GetCursorScreenPos();
        imgui.Dummy({ drawW, drawH });

        local drawList = GetUIDrawList();
        -- Pulse can grow past the window; clip to the display, not the window.
        local io = imgui.GetIO();
        drawList:PushClipRect({ 0, 0 }, { io.DisplaySize.x, io.DisplaySize.y }, false);

        if phase == 'slide' then
            local leftX = Lerp(originX - drawW, originX, slideT);
            local rightX = Lerp(originX + drawW, originX, slideT);
            DrawImage(drawList, texturePtr, leftX, originY, drawW, drawH, SLIDE_ALPHA);
            DrawImage(drawList, texturePtr, rightX, originY, drawW, drawH, SLIDE_ALPHA);
        else
            local scaledW = drawW * scaleMult;
            local scaledH = drawH * scaleMult;
            DrawImage(
                drawList, texturePtr,
                originX + (drawW - scaledW) * 0.5,
                originY + (drawH - scaledH) * 0.5,
                scaledW, scaledH, alpha);
        end

        drawList:PopClipRect();
    end
    imgui.End();
    imgui.PopStyleVar();
    return true;
end

bluemagiclearned.Trigger = function()
    if not IsEnabled() then
        return;
    end
    ashita.misc.play_sound(SOUND_PATH);
    StartAnimation('event');
end

bluemagiclearned.HandleMessagePacket = function(messagePacket)
    if messagePacket and messagePacket.message == LEARNED_MESSAGE_ID then
        bluemagiclearned.Trigger();
    end
end

bluemagiclearned.DrawWindow = function(settings)
    if hidden or not IsEnabled() then
        ClearAnimation();
        return;
    end

    local previewWanted = IsLivePreviewActive();
    if animMode == 'preview' and not previewWanted then
        ClearAnimation();
    end

    local texture = TextureManager.getFileTexture(TEXTURE_PATH);
    local texturePtr = texture and TextureManager.getTexturePtr(texture);
    if not texturePtr then
        return;
    end

    if animStart <= 0 then
        if not previewWanted then
            return;
        end
        StartAnimation('preview');
    end

    local holdSeconds = GetHoldSeconds();
    local drawW, drawH = GetFittedSize(texture);
    local stillPlaying = DrawAnimatedBanner(
        texturePtr, drawW, drawH, os.clock() - animStart, holdSeconds);

    -- Event finished: stop, or restart the preview loop if config still wants it.
    if not stillPlaying then
        ClearAnimation();
        if previewWanted then
            StartAnimation('preview');
            DrawAnimatedBanner(texturePtr, drawW, drawH, 0, holdSeconds);
        end
    end
end

bluemagiclearned.Initialize = function(settings)
    hidden = false;
    ClearAnimation();
    EnsureDefaultPosition();
end

bluemagiclearned.UpdateVisuals = function(settings)
end

bluemagiclearned.SetHidden = function(isHidden)
    hidden = isHidden == true;
    if hidden then
        ClearAnimation();
    end
end

bluemagiclearned.Cleanup = function()
    hidden = false;
    ClearAnimation();
end

bluemagiclearned.ResetPositions = function()
    local x, y = defaultPositions.GetBlueMagicLearnedPosition();
    if gConfig and gConfig.windowPositions then
        gConfig.windowPositions[WINDOW_NAME] = { x = x, y = y };
        if gConfig.appliedPositions then
            gConfig.appliedPositions[WINDOW_NAME] = nil;
        end
    end
end

return bluemagiclearned;
