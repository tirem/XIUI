--[[
* XIUI Hotbar Module
* Main entry point - manages lifecycle for 6 independent hotbar windows
]]--

-- This module copies concepts and content from the Windower XIVHotbar addon, https://github.com/Technyze/XIVHotbar2
-- Here is their original license for reference:
--[[    BSD License Disclaimer
        Copyright © 2020, SirEdeonX, Akirane, Technyze
        All rights reserved.

        Redistribution and use in source and binary forms, with or without
        modification, are permitted provided that the following conditions are met:

            * Redistributions of source code must retain the above copyright
              notice, this list of conditions and the following disclaimer.
            * Redistributions in binary form must reproduce the above copyright
              notice, this list of conditions and the following disclaimer in the
              documentation and/or other materials provided with the distribution.
            * Neither the name of ui.xivhotbar/xivhotbar2 nor the
              names of its contributors may be used to endorse or promote products
              derived from this software without specific prior written permission.

        THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
        ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
        WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
        DISCLAIMED. IN NO EVENT SHALL SirEdeonX OR Akirane BE LIABLE FOR ANY
        DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
        (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
        LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
        ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
        (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
        SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

require('common');
require('handlers.helpers');
local gdi = require('submodules.gdifonts.include');
local primitives = require('primitives');
local windowBg = require('libs.windowbackground');
local dragdrop = require('libs.dragdrop');

local data = require('modules.hotbar.data');
local display = require('modules.hotbar.display');
local actions = require('modules.hotbar.actions');
local macropalette = require('modules.hotbar.macropalette');
local crossbar = require('modules.hotbar.crossbar');
local controller = require('modules.hotbar.controller');
local textures = require('modules.hotbar.textures');
local hotbarConfig = require('config.hotbar');

local M = {};

-- ============================================
-- State
-- ============================================

local texturesInitialized = false;

-- ============================================
-- Crossbar State
-- ============================================

local crossbarInitialized = false;

-- ============================================
-- Module State
-- ============================================

M.initialized = false;
M.visible = true;

-- ============================================
-- Module Lifecycle
-- ============================================

-- Initialize the hotbar module
function M.Initialize(settings)
    if _XIUI_DEV_ALPHA_HOTBAR == false then return; end
    if M.initialized then return; end

    -- Ensure global settings have defaults
    if gConfig then
        gConfig.hotbarPreview = false;
        if gConfig.hotbarEnabled == nil then gConfig.hotbarEnabled = true; end

        -- Per-bar position defaults
        if gConfig.hotbarBarPositions == nil then
            gConfig.hotbarBarPositions = {};
        end
    end

    -- Initialize keybinds
    data.InitializeKeybinds();

    -- Validate font settings
    local fontSettings = settings and settings.font_settings;
    local keybindFontSettings = settings and settings.keybind_font_settings;
    local labelFontSettings = settings and settings.label_font_settings;

    if not fontSettings then
        print('[XIUI hotbar] Warning: Invalid font settings, using defaults');
        fontSettings = {
            font_family = 'Consolas',
            font_height = 10,
            font_color = 0xFFFFFFFF,
            font_flags = 0,
            outline_color = 0xFF000000,
            outline_width = 2,
        };
    end

    -- Use keybind/label specific settings or fall back to base font settings
    keybindFontSettings = keybindFontSettings or fontSettings;
    labelFontSettings = labelFontSettings or fontSettings;

    -- Primitive base data
    local primData = {
        visible = false,
        can_focus = false,
        locked = true,
        width = 100,
        height = 100,
    };

    -- Create resources for each bar
    data.allFonts = {};

    for barIndex = 1, data.NUM_BARS do
        -- Get per-bar settings
        local barSettings = data.GetBarSettings(barIndex);
        local bgTheme = barSettings.backgroundTheme or 'Plain';
        local bgScale = barSettings.bgScale or 1.0;
        local borderScale = barSettings.borderScale or 1.0;
        local slotCount = data.GetBarSlotCount(barIndex);

        -- 1. Create background primitive (renders at bottom)
        data.bgHandles[barIndex] = windowBg.create(primData, bgTheme, bgScale, borderScale);

        -- 2. Create slot primitives (render above background) - up to MAX_SLOTS_PER_BAR
        data.slotPrims[barIndex] = {};
        for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
            local prim = primitives.new(primData);
            prim.visible = false;
            prim.can_focus = false;
            data.slotPrims[barIndex][slotIndex] = prim;
        end

        -- 3. Create icon primitives (render above slot backgrounds)
        data.iconPrims[barIndex] = {};
        for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
            local prim = primitives.new(primData);
            prim.visible = false;
            prim.can_focus = false;
            data.iconPrims[barIndex][slotIndex] = prim;
        end

        -- 4. Create cooldown overlay primitives (render above icons)
        data.cooldownPrims[barIndex] = {};
        for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
            local prim = primitives.new(primData);
            prim.visible = false;
            prim.can_focus = false;
            data.cooldownPrims[barIndex][slotIndex] = prim;
        end

        -- Get per-bar font sizes
        local kbFontSize = barSettings.keybindFontSize or 8;
        local lblFontSize = barSettings.labelFontSize or 10;

        -- 5. Create keybind fonts for each slot - up to MAX_SLOTS_PER_BAR
        data.keybindFonts[barIndex] = {};
        for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
            local kbSettings = deep_copy_table(keybindFontSettings);
            kbSettings.font_height = kbFontSize;
            local font = FontManager.create(kbSettings);
            font:set_visible(false);
            data.keybindFonts[barIndex][slotIndex] = font;
            table.insert(data.allFonts, font);
        end

        -- 6. Create label fonts for each slot (centered alignment for labels below slots)
        data.labelFonts[barIndex] = {};
        for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
            local lblSettings = deep_copy_table(labelFontSettings);
            lblSettings.font_height = lblFontSize;
            lblSettings.font_alignment = gdi.Alignment.Center;
            local font = FontManager.create(lblSettings);
            font:set_visible(false);
            data.labelFonts[barIndex][slotIndex] = font;
            table.insert(data.allFonts, font);
        end

        -- 7. Create cooldown timer fonts (centered over slot)
        data.timerFonts[barIndex] = {};
        for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
            local timerSettings = deep_copy_table(fontSettings);
            timerSettings.font_height = 11;
            timerSettings.font_alignment = gdi.Alignment.Center;
            timerSettings.font_color = 0xFFFFFFFF;
            timerSettings.outline_color = 0xFF000000;
            timerSettings.outline_width = 2;
            local font = FontManager.create(timerSettings);
            font:set_visible(false);
            data.timerFonts[barIndex][slotIndex] = font;
            table.insert(data.allFonts, font);
        end

        -- 8. Create hotbar number font
        local numSettings = deep_copy_table(fontSettings);
        numSettings.font_height = 12;
        data.hotbarNumberFonts[barIndex] = FontManager.create(numSettings);
        data.hotbarNumberFonts[barIndex]:set_visible(false);
        table.insert(data.allFonts, data.hotbarNumberFonts[barIndex]);
    end

    -- Initialize display layer
    display.Initialize(settings);

    -- Initialize crossbar if mode includes crossbar
    local crossbarMode = gConfig and gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.mode or 'hotbar';
    local crossbarNeeded = crossbarMode == 'crossbar' or crossbarMode == 'both';
    if crossbarNeeded then
        crossbar.Initialize(gConfig.hotbarCrossbar, gAdjustedSettings.crossbarSettings);
        controller.Initialize({
            triggerThreshold = gConfig.hotbarCrossbar.triggerThreshold or 30,
            doubleTapEnabled = gConfig.hotbarCrossbar.enableDoubleTap or false,
            doubleTapWindow = gConfig.hotbarCrossbar.doubleTapWindow or 0.3,
        });
        controller.SetSlotActivateCallback(function(comboMode, slotIndex)
            crossbar.ActivateSlot(comboMode, slotIndex);
        end);
        crossbarInitialized = true;
    end

    M.initialized = true;
end

-- Update visual elements when settings change
function M.UpdateVisuals(settings)
    if not M.initialized then return; end

    local fontSettings = settings and settings.font_settings;
    local keybindFontSettings = settings and settings.keybind_font_settings or fontSettings;
    local labelFontSettings = settings and settings.label_font_settings or fontSettings;

    if not fontSettings then return; end

    -- Recreate fonts for each bar
    for barIndex = 1, data.NUM_BARS do
        -- Get per-bar font sizes
        local barSettings = data.GetBarSettings(barIndex);
        local kbFontSize = barSettings.keybindFontSize or 8;
        local lblFontSize = barSettings.labelFontSize or 10;

        -- Keybind fonts
        if data.keybindFonts[barIndex] then
            for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
                if data.keybindFonts[barIndex][slotIndex] then
                    local kbSettings = deep_copy_table(keybindFontSettings);
                    kbSettings.font_height = kbFontSize;
                    data.keybindFonts[barIndex][slotIndex] = FontManager.recreate(
                        data.keybindFonts[barIndex][slotIndex], kbSettings
                    );
                end
            end
        end

        -- Label fonts
        if data.labelFonts[barIndex] then
            for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
                if data.labelFonts[barIndex][slotIndex] then
                    local lblSettings = deep_copy_table(labelFontSettings);
                    lblSettings.font_height = lblFontSize;
                    lblSettings.font_alignment = gdi.Alignment.Center;
                    data.labelFonts[barIndex][slotIndex] = FontManager.recreate(
                        data.labelFonts[barIndex][slotIndex], lblSettings
                    );
                end
            end
        end

        -- Hotbar number font
        if data.hotbarNumberFonts[barIndex] then
            local numSettings = deep_copy_table(fontSettings);
            numSettings.font_height = 12;
            data.hotbarNumberFonts[barIndex] = FontManager.recreate(
                data.hotbarNumberFonts[barIndex], numSettings
            );
        end
    end

    -- Update display layer (handles theme changes)
    display.UpdateVisuals(settings);

    -- Handle crossbar enable/disable based on mode
    local crossbarMode = gConfig and gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.mode or 'hotbar';
    local crossbarNeeded = crossbarMode == 'crossbar' or crossbarMode == 'both';

    if crossbarNeeded and not crossbarInitialized then
        -- Initialize crossbar when newly needed
        crossbar.Initialize(gConfig.hotbarCrossbar, gAdjustedSettings.crossbarSettings);
        controller.Initialize({
            triggerThreshold = gConfig.hotbarCrossbar.triggerThreshold or 30,
            doubleTapEnabled = gConfig.hotbarCrossbar.enableDoubleTap or false,
            doubleTapWindow = gConfig.hotbarCrossbar.doubleTapWindow or 0.3,
        });
        controller.SetSlotActivateCallback(function(comboMode, slotIndex)
            crossbar.ActivateSlot(comboMode, slotIndex);
        end);
        crossbarInitialized = true;
    elseif not crossbarNeeded and crossbarInitialized then
        -- Cleanup crossbar when no longer needed
        crossbar.Cleanup();
        controller.Cleanup();
        crossbarInitialized = false;
    elseif crossbarInitialized then
        -- Update crossbar visuals if already initialized
        crossbar.UpdateVisuals(gConfig.hotbarCrossbar, gAdjustedSettings.crossbarSettings);
        -- Update controller settings
        controller.SetTriggerThreshold(gConfig.hotbarCrossbar.triggerThreshold or 30);
        controller.SetDoubleTapEnabled(gConfig.hotbarCrossbar.enableDoubleTap or false);
        controller.SetDoubleTapWindow(gConfig.hotbarCrossbar.doubleTapWindow or 0.3);
    end
end

-- Main render function - called every frame
function M.DrawWindow(settings)
    if not M.initialized then return; end
    if not M.visible then return; end

    -- Update drag/drop state (must be called every frame, before drop zones)
    dragdrop.Update();

    -- Initialize textures on first draw (needed for icons in both modes)
    if not texturesInitialized then
        textures:Initialize();
        texturesInitialized = true;
    end

    if gConfig and gConfig.hotbarEnabled == false then
        display.HideWindow();
        if crossbarInitialized then
            crossbar.SetHidden(true);
        end
        return;
    end

    -- Determine what to draw based on mode
    local crossbarMode = gConfig and gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.mode or 'hotbar';
    local showHotbar = crossbarMode == 'hotbar' or crossbarMode == 'both';
    local showCrossbar = crossbarMode == 'crossbar' or crossbarMode == 'both';

    -- Draw hotbar if mode includes it
    if showHotbar then
        display.DrawWindow(settings);
    else
        display.HideWindow();
    end

    -- Draw crossbar if mode includes it
    if showCrossbar and crossbarInitialized then
        crossbar.DrawWindow(gConfig.hotbarCrossbar, gAdjustedSettings.crossbarSettings);
    elseif crossbarInitialized then
        crossbar.SetHidden(true);
    end

    -- Always draw macro palette and keybind modal (regardless of mode)
    macropalette.DrawPalette();
    hotbarConfig.DrawKeybindModal();

    -- Render drag preview (must be called at end of frame, after all drop zones)
    dragdrop.Render();

    -- Handle slot dragged outside (remove the action)
    if dragdrop.WasDroppedOutside() then
        local lastPayload = dragdrop.GetLastPayload();
        if lastPayload then
            if lastPayload.type == 'slot' then
                -- Standard hotbar slot was dragged outside - clear it
                macropalette.ClearSlot(lastPayload.barIndex, lastPayload.slotIndex);
            elseif lastPayload.type == 'crossbar_slot' then
                -- Crossbar slot was dragged outside - clear it
                data.ClearCrossbarSlotData(lastPayload.comboMode, lastPayload.slotIndex);
            end
        end
    end
end

-- Set module visibility
function M.SetHidden(hidden)
    M.visible = not hidden;
    if hidden then
        data.SetAllFontsVisible(false);
        for barIndex = 1, data.NUM_BARS do
            if data.bgHandles[barIndex] then
                windowBg.hide(data.bgHandles[barIndex]);
            end
        end
    end
    display.SetHidden(hidden);
    if crossbarInitialized then
        crossbar.SetHidden(hidden);
    end
end

-- Cleanup on addon unload
function M.Cleanup()
    if not M.initialized then return; end

    -- Destroy fonts for each bar
    for barIndex = 1, data.NUM_BARS do
        -- Keybind fonts
        if data.keybindFonts[barIndex] then
            for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
                if data.keybindFonts[barIndex][slotIndex] then
                    FontManager.destroy(data.keybindFonts[barIndex][slotIndex]);
                end
            end
        end

        -- Label fonts
        if data.labelFonts[barIndex] then
            for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
                if data.labelFonts[barIndex][slotIndex] then
                    FontManager.destroy(data.labelFonts[barIndex][slotIndex]);
                end
            end
        end

        -- Timer fonts
        if data.timerFonts[barIndex] then
            for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
                if data.timerFonts[barIndex][slotIndex] then
                    FontManager.destroy(data.timerFonts[barIndex][slotIndex]);
                end
            end
        end

        -- Hotbar number font
        if data.hotbarNumberFonts[barIndex] then
            FontManager.destroy(data.hotbarNumberFonts[barIndex]);
        end

        -- Destroy background
        if data.bgHandles[barIndex] then
            windowBg.destroy(data.bgHandles[barIndex]);
        end

        -- Destroy slot primitives
        if data.slotPrims[barIndex] then
            for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
                if data.slotPrims[barIndex][slotIndex] then
                    data.slotPrims[barIndex][slotIndex]:destroy();
                end
            end
        end

        -- Destroy icon primitives
        if data.iconPrims[barIndex] then
            for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
                if data.iconPrims[barIndex][slotIndex] then
                    data.iconPrims[barIndex][slotIndex]:destroy();
                end
            end
        end

        -- Destroy cooldown primitives
        if data.cooldownPrims[barIndex] then
            for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
                if data.cooldownPrims[barIndex][slotIndex] then
                    data.cooldownPrims[barIndex][slotIndex]:destroy();
                end
            end
        end
    end

    -- Cleanup display and data layers
    display.Cleanup();
    data.Cleanup();

    -- Cleanup crossbar if initialized
    if crossbarInitialized then
        crossbar.Cleanup();
        controller.Cleanup();
        crossbarInitialized = false;
    end

    M.initialized = false;
end

-- ============================================
-- Event Handlers
-- ============================================

function M.HandleZonePacket()
    data.Clear();
end

function M.HandleJobChangePacket(e)
    ashita.tasks.once(0.5, function()
        data.SetPlayerJob();
        macropalette.SyncToCurrentJob();
    end);
end

function M.HandleKey(event)
    if gConfig and gConfig.hotbarEnabled == false then
        return;
    end
    return actions.HandleKey(event);
end

function M.HandleXInputState(e)
    if not crossbarInitialized then return; end
    if gConfig and gConfig.hotbarEnabled == false then return; end
    local crossbarMode = gConfig and gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.mode or 'hotbar';
    if crossbarMode ~= 'crossbar' and crossbarMode ~= 'both' then return; end
    controller.HandleXInputState(e);
end

-- ============================================
-- Preview Mode
-- ============================================

function M.SetPreview(enabled)
    data.SetPreview(enabled);
end

function M.ClearPreview()
    data.ClearPreview();
end

return M;
