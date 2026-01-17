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
local slotrenderer = require('modules.hotbar.slotrenderer');
local petpalette = require('modules.hotbar.petpalette');
local palette = require('modules.hotbar.palette');
local macrosLib = require('libs.ffxi.macros');

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

-- Track hotbar enable/disable state for transitions
local wasHotbarEnabled = nil;

-- ============================================
-- Module Lifecycle
-- ============================================

-- Initialize the hotbar module
function M.Initialize(settings)
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

    -- Initialize data module (sets player job)
    data.Initialize();

    -- Validate palettes on reload (not just on job change packets)
    if data.jobId then
        palette.ValidatePalettesForJob(data.jobId, data.subjobId);
    else
        -- Job not ready yet, retry after short delay
        ashita.tasks.once(0.3, function()
            data.SetPlayerJob();
            if data.jobId then
                palette.ValidatePalettesForJob(data.jobId, data.subjobId);
                macropalette.SyncToCurrentJob();
                display.ClearIconCache();
                slotrenderer.ClearAllCache();
                if crossbarInitialized then
                    crossbar.ClearIconCache();
                end
            end
        end);
    end

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
        local bgTheme = barSettings.backgroundTheme or '-None-';
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

        -- 5. Create frame overlay primitives (render above cooldown overlays)
        data.framePrims[barIndex] = {};
        for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
            local prim = primitives.new(primData);
            prim.visible = false;
            prim.can_focus = false;
            data.framePrims[barIndex][slotIndex] = prim;
        end

        -- Get per-bar font sizes
        local kbFontSize = barSettings.keybindFontSize or 10;
        local lblFontSize = barSettings.labelFontSize or 10;

        -- 5. Create keybind fonts for each slot - up to MAX_SLOTS_PER_BAR
        data.keybindFonts[barIndex] = {};
        for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
            local kbSettings = deep_copy_table(keybindFontSettings);
            kbSettings.font_height = kbFontSize;
            local font = FontManager.create(kbSettings);
            font:set_visible(false);
            data.keybindFonts[barIndex][slotIndex] = font;
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
        end

        -- 8. Create MP cost fonts (right-aligned at top-right corner)
        local mpCostFontSize = barSettings.mpCostFontSize or 10;
        local mpCostFontColor = barSettings.mpCostFontColor or 0xFFD4FF97;
        data.mpCostFonts[barIndex] = {};
        for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
            local mpSettings = deep_copy_table(fontSettings);
            mpSettings.font_height = mpCostFontSize;
            mpSettings.font_alignment = gdi.Alignment.Right;
            mpSettings.font_color = mpCostFontColor;
            mpSettings.outline_color = 0xFF000000;
            mpSettings.outline_width = 2;
            local font = FontManager.create(mpSettings);
            font:set_visible(false);
            data.mpCostFonts[barIndex][slotIndex] = font;
        end

        -- 9. Create item quantity fonts (right-aligned at bottom-right corner)
        local quantityFontSize = barSettings.quantityFontSize or 10;
        local quantityFontColor = barSettings.quantityFontColor or 0xFFFFFFFF;
        data.quantityFonts[barIndex] = {};
        for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
            local qtySettings = deep_copy_table(fontSettings);
            qtySettings.font_height = quantityFontSize;
            qtySettings.font_alignment = gdi.Alignment.Right;
            qtySettings.font_color = quantityFontColor;
            qtySettings.outline_color = 0xFF000000;
            qtySettings.outline_width = 2;
            local font = FontManager.create(qtySettings);
            font:set_visible(false);
            data.quantityFonts[barIndex][slotIndex] = font;
        end

        -- 10. Create hotbar number font
        local numSettings = deep_copy_table(fontSettings);
        numSettings.font_height = 12;
        data.hotbarNumberFonts[barIndex] = FontManager.create(numSettings);
        data.hotbarNumberFonts[barIndex]:set_visible(false);
    end

    -- Build the flattened font list for batch visibility operations.
    -- (Must be rebuilt after any recreate() calls, too.)
    data.RebuildAllFonts();

    -- Initialize display layer
    display.Initialize(settings);

    -- Register pet change callback to clear slot caches
    petpalette.OnPetChanged(function(oldPetKey, newPetKey)
        -- Clear ALL caches when pet changes to force full refresh
        slotrenderer.ClearAllCache();
        display.ClearIconCache();
        if crossbarInitialized then
            crossbar.ClearIconCache();
        end
        -- Clear macro palette's pet commands cache (for BST ready moves)
        macropalette.ClearPetCommandsCache();
    end);

    -- Register palette change callback to clear crossbar icon cache
    palette.OnPaletteChanged(function(barIdentifier, oldPaletteName, newPaletteName)
        -- Clear crossbar icon cache when any palette changes (hotbar or crossbar)
        if crossbarInitialized then
            crossbar.ClearIconCache();
        end
        -- Clear slot renderer cache for hotbar
        slotrenderer.ClearAllCache();
    end);

    -- Initialize macro patching system (backups original bytes, applies macrofix by default)
    macrosLib.initialize_patches();

    -- Apply correct mode based on setting
    local disableMacroBars = gConfig and gConfig.hotbarGlobal and gConfig.hotbarGlobal.disableMacroBars or false;
    if disableMacroBars then
        macrosLib.hide_macro_bar();  -- Switch to hide mode
    end
    -- If checkbox is OFF, macrofix is already applied by initialize_patches()

    -- Initialize crossbar if mode includes crossbar
    -- Defensive: validate gConfig.hotbarCrossbar is a table before accessing
    local crossbarConfig = gConfig and type(gConfig.hotbarCrossbar) == 'table' and gConfig.hotbarCrossbar or nil;
    local crossbarMode = crossbarConfig and crossbarConfig.mode or 'hotbar';
    local crossbarNeeded = crossbarMode == 'crossbar' or crossbarMode == 'both';
    if crossbarNeeded and crossbarConfig then
        crossbar.Initialize(crossbarConfig, gAdjustedSettings.crossbarSettings);
        controller.Initialize({
            expandedCrossbarEnabled = crossbarConfig.enableExpandedCrossbar ~= false,
            doubleTapEnabled = crossbarConfig.enableDoubleTap or false,
            doubleTapWindow = crossbarConfig.doubleTapWindow or 0.3,
            controllerScheme = crossbarConfig.controllerScheme,
        });
        controller.SetSlotActivateCallback(function(comboMode, slotIndex)
            crossbar.ActivateSlot(comboMode, slotIndex);
        end);
        -- Set controller blocking enabled state (crossbar-specific)
        controller.SetBlockingEnabled(disableMacroBars);
        crossbarInitialized = true;
    end

    -- Check pet state on initialization (detects existing pet after reload)
    ashita.tasks.once(0.1, function()
        petpalette.CheckPetState();
    end);

    -- Initialize state tracking
    wasHotbarEnabled = (gConfig.hotbarEnabled ~= false);

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
        local kbFontSize = barSettings.keybindFontSize or 10;
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

    -- IMPORTANT: recreate() changes object references; rebuild the batch list so hiding works reliably.
    data.RebuildAllFonts();

    -- Clear slot cache since fonts were recreated (cache tracks font text state)
    slotrenderer.ClearAllCache();

    -- Update display layer (handles theme changes)
    display.UpdateVisuals(settings);

    -- Apply correct macro bar mode based on setting
    local disableMacroBars = gConfig and gConfig.hotbarGlobal and gConfig.hotbarGlobal.disableMacroBars or false;
    if disableMacroBars then
        macrosLib.hide_macro_bar();  -- Hide mode: macro bar hidden
    else
        macrosLib.show_macro_bar();  -- Macrofix mode: fast built-in macros
    end

    -- Handle crossbar enable/disable based on mode
    local crossbarMode = gConfig and gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.mode or 'hotbar';
    local crossbarNeeded = crossbarMode == 'crossbar' or crossbarMode == 'both';

    if crossbarNeeded and not crossbarInitialized then
        -- Initialize crossbar when newly needed
        crossbar.Initialize(gConfig.hotbarCrossbar, gAdjustedSettings.crossbarSettings);
        controller.Initialize({
            expandedCrossbarEnabled = gConfig.hotbarCrossbar.enableExpandedCrossbar ~= false,
            doubleTapEnabled = gConfig.hotbarCrossbar.enableDoubleTap or false,
            doubleTapWindow = gConfig.hotbarCrossbar.doubleTapWindow or 0.3,
            controllerScheme = gConfig.hotbarCrossbar.controllerScheme,
        });
        controller.SetSlotActivateCallback(function(comboMode, slotIndex)
            crossbar.ActivateSlot(comboMode, slotIndex);
        end);
        -- Set controller blocking enabled state (crossbar-specific)
        controller.SetBlockingEnabled(disableMacroBars);
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
        controller.SetExpandedCrossbarEnabled(gConfig.hotbarCrossbar.enableExpandedCrossbar ~= false);
        controller.SetDoubleTapEnabled(gConfig.hotbarCrossbar.enableDoubleTap or false);
        controller.SetDoubleTapWindow(gConfig.hotbarCrossbar.doubleTapWindow or 0.3);
        controller.SetControllerScheme(gConfig.hotbarCrossbar.controllerScheme);
        -- Update controller blocking state (crossbar-specific)
        controller.SetBlockingEnabled(disableMacroBars);
    end

    -- Update state tracking for hotbar enable/disable
    wasHotbarEnabled = (gConfig and gConfig.hotbarEnabled ~= false);
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
                -- Clear icon cache so slot updates immediately
                if crossbarInitialized then
                    crossbar.ClearIconCache();
                end
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

        -- MP cost fonts
        if data.mpCostFonts[barIndex] then
            for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
                if data.mpCostFonts[barIndex][slotIndex] then
                    FontManager.destroy(data.mpCostFonts[barIndex][slotIndex]);
                end
            end
        end

        -- Item quantity fonts
        if data.quantityFonts[barIndex] then
            for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
                if data.quantityFonts[barIndex][slotIndex] then
                    FontManager.destroy(data.quantityFonts[barIndex][slotIndex]);
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

        -- Destroy frame primitives
        if data.framePrims[barIndex] then
            for slotIndex = 1, data.MAX_SLOTS_PER_BAR do
                if data.framePrims[barIndex][slotIndex] then
                    data.framePrims[barIndex][slotIndex]:destroy();
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

    -- Reset pet palette state
    petpalette.Reset();

    -- Restore native macro bar UI to original game state (undo all memory patches)
    macrosLib.restore_default();

    M.initialized = false;
end

-- ============================================
-- Event Handlers
-- ============================================

function M.HandleZonePacket()
    data.Clear();
    petpalette.ClearPetState();
    -- Clear availability cache since player state is invalid during zone
    slotrenderer.ClearAvailabilityCache();
end

function M.HandleJobChangePacket(e)
    ashita.tasks.once(0.5, function()
        data.SetPlayerJob();
        macropalette.SyncToCurrentJob();
        -- Validate palettes for new job (clears if palette doesn't exist for this job)
        palette.ValidatePalettesForJob(data.jobId, data.subjobId);
        -- Clear icon caches to force refresh for new job's actions
        display.ClearIconCache();
        if crossbarInitialized then
            crossbar.ClearIconCache();
        end
        -- Check pet state after job change
        petpalette.CheckPetState();
    end);
end

-- Handle pet sync packet (0x0068)
-- Called from main XIUI.lua packet handler
function M.HandlePetSyncPacket()
    -- Use delayed check to ensure entity is available
    ashita.tasks.once(0.3, function()
        petpalette.CheckPetState();
    end);
end

-- Cycle pet palette for a bar
-- direction: 1 for next, -1 for previous
function M.CyclePetPalette(barIndex, direction)
    if not barIndex then barIndex = 1; end
    direction = direction or 1;
    local result = petpalette.CyclePalette(barIndex, direction, data.jobId);
    if result then
        -- Clear slot cache to force refresh
        slotrenderer.ClearAllCache();
    end
    return result;
end

-- Return bar to auto pet palette mode
function M.SetPetPaletteAuto(barIndex)
    if not barIndex then barIndex = 1; end
    petpalette.ClearManualOverride(barIndex);
    -- Clear slot cache to force refresh
    slotrenderer.ClearAllCache();
end

-- Get current pet palette display name for a bar
function M.GetPetPaletteDisplayName(barIndex)
    return petpalette.GetPaletteDisplayName(barIndex, data.jobId);
end

-- Check if bar has pet-aware mode enabled
function M.IsPetAwareBar(barIndex)
    local barSettings = data.GetBarSettings(barIndex);
    return barSettings and barSettings.petAware == true;
end

-- Check if bar has manual palette override
function M.HasPetPaletteOverride(barIndex)
    return petpalette.HasManualOverride(barIndex);
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

-- Handle xinput_button event for blocking game macros
-- Returns true if the button should be blocked
function M.HandleXInputButton(e)
    if not crossbarInitialized then return false; end
    if gConfig and gConfig.hotbarEnabled == false then return false; end
    local crossbarMode = gConfig and gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.mode or 'hotbar';
    if crossbarMode ~= 'crossbar' and crossbarMode ~= 'both' then return false; end
    return controller.HandleXInputButton(e);
end

-- Handle DirectInput button event for blocking game macros
-- Returns true if the button should be blocked
function M.HandleDInputButton(e)
    if not crossbarInitialized then return false; end
    if gConfig and gConfig.hotbarEnabled == false then return false; end
    local crossbarMode = gConfig and gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.mode or 'hotbar';
    if crossbarMode ~= 'crossbar' and crossbarMode ~= 'both' then return false; end
    return controller.HandleDInputButton(e);
end

-- Handle DirectInput state event (for D-pad POV)
function M.HandleDInputState(e)
    if not crossbarInitialized then return; end
    if gConfig and gConfig.hotbarEnabled == false then return; end
    local crossbarMode = gConfig and gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.mode or 'hotbar';
    if crossbarMode ~= 'crossbar' and crossbarMode ~= 'both' then return; end
    controller.HandleDInputState(e);
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

-- Reset all hotbar and crossbar positions to defaults (called when settings are reset)
function M.ResetPositions()
    display.ResetPositions();
    crossbar.ResetPositions();
end

-- Toggle debug mode for hotbar module (actions + controller)
-- Usage: /xiui debug hotbar
function M.SetDebugEnabled(enabled)
    actions.SetDebugEnabled(enabled);
    controller.SetDebugEnabled(enabled);
    local state = enabled and 'ON' or 'OFF';
    print('[XIUI] Hotbar debug mode: ' .. state);
end

-- Check if debug is enabled
function M.IsDebugEnabled()
    return actions.IsDebugEnabled() or controller.IsDebugEnabled();
end

-- Toggle palette key debug mode
-- Usage: /xiui debug palette
function M.SetPaletteDebugEnabled(enabled)
    actions.SetPaletteDebugEnabled(enabled);
end

-- Check if palette debug is enabled
function M.IsPaletteDebugEnabled()
    return actions.IsPaletteDebugEnabled();
end

return M;
