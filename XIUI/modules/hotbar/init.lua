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
local gameState = require('core.gamestate');
local dragdrop = require('libs.dragdrop');
local imtext = require('libs.imtext');

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

-- Crossbar controller "Disable XI Macros" is shared with Hotbar -> Disable XI Macros (hotbarGlobal.disableMacroBars).
-- Wrapper exists so the call sites read as crossbar-specific intent.
local function GetCrossbarDisableXiMacrosEffective()
    local hg = gConfig and gConfig.hotbarGlobal;
    return hg and hg.disableMacroBars == true;
end

-- Palette change dedup: SetActivePalette / SetActivePaletteForCombo fire one callback per bar (1-6)
-- or per combo mode (6x). Without deduping, display/slot cache clears run 6x per logical palette change.
local lastPaletteVisualRefreshSig = nil;

-- True if any hotbar bar or crossbar combo-mode has petAware enabled.
-- Used to short-circuit the pet-change callback's cache wipes when no
-- bar would actually rebind its slots in response.
local function AnyBarIsPetAware()
    for barIndex = 1, data.NUM_BARS do
        local barSettings = data.GetBarSettings(barIndex);
        if barSettings and barSettings.petAware then
            return true;
        end
    end
    local crossbarConfig = gConfig and gConfig.hotbarCrossbar;
    local modeSettings = crossbarConfig and crossbarConfig.comboModeSettings;
    if modeSettings then
        for _, mode in pairs(modeSettings) do
            if mode and mode.petAware then
                return true;
            end
        end
    end
    return false;
end

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
    end

    -- Initialize data module (sets player job)
    data.Initialize();
    -- Migrate any legacy non-pet-aware storage keys + invalidate cache after migration.
    if data.MigratePetAwareSlotStorageKeys then
        data.MigratePetAwareSlotStorageKeys();
    end
    data.InvalidateStorageKeyCache();

    -- Validate palettes on reload (not just on job change packets)
    -- Helper function to validate palettes once job is ready
    local function ValidatePalettesWhenReady(attempt)
        attempt = attempt or 1;
        local maxAttempts = 20;

        if data.SetPlayerJob() then
            -- Honor pending "profile loaded before job was readable" (char select / logout)
            -- so the default crossbar palette scope applies on first job-ready frame.
            local pending = palette.ConsumePendingApplyDefaultCrossbarScopeFromProfile
                and palette.ConsumePendingApplyDefaultCrossbarScopeFromProfile()
                or nil;
            palette.ValidatePalettesForJob(data.jobId, data.subjobId, {
                applyDefaultCrossbarScope = pending,
            });
            macropalette.SyncToCurrentJob();
            display.ClearIconCache();
            slotrenderer.ClearAllCache();
            actions.ClearNoIconCache();
            if crossbarInitialized then
                crossbar.ClearIconCache();
            end
        elseif attempt < maxAttempts then
            local delay = math.min(0.5, 0.2 + (attempt * 0.05));
            ashita.tasks.once(delay, function()
                ValidatePalettesWhenReady(attempt + 1);
            end);
        end
    end

    if data.jobId then
        local pending = palette.ConsumePendingApplyDefaultCrossbarScopeFromProfile
            and palette.ConsumePendingApplyDefaultCrossbarScopeFromProfile()
            or nil;
        palette.ValidatePalettesForJob(data.jobId, data.subjobId, {
            applyDefaultCrossbarScope = pending,
        });
    else
        -- Job not ready yet, start retry loop
        ashita.tasks.once(0.3, function()
            ValidatePalettesWhenReady(1);
        end);
    end

    -- Initialize display layer
    display.Initialize(settings);

    -- Register pet change callback to clear slot caches.
    --
    -- The wipes here are global (every hotbar slot, every crossbar slot,
    -- macro palette pet commands). They're only meaningful for bars that
    -- actually swap content on pet change — i.e. bars with petAware set.
    -- If nothing on screen consumes pet state, summoning/releasing a pet
    -- has no visible effect, and rebuilding every cache afterwards is pure
    -- waste. The cost shows up most when another addon is also reacting
    -- to combat traffic and the frame budget is tight.
    petpalette.OnPetChanged(function(oldPetKey, newPetKey)
        -- Storage key cache is cheap to flip and is the only invalidation
        -- whose absence could leave a bar showing pet-keyed slots after the
        -- user toggled petAware off mid-pet. Always run it.
        data.InvalidateStorageKeyCache();

        if not AnyBarIsPetAware() then return; end

        -- Clear ALL caches when pet changes to force full refresh
        slotrenderer.ClearAllCache();
        display.ClearIconCache();
        actions.ClearNoIconCache();
        if crossbarInitialized then
            crossbar.ClearIconCache();
        end
        -- Clear macro palette's pet commands cache (for BST ready moves)
        macropalette.ClearPetCommandsCache();
    end);

    -- Register palette change callback to clear caches.
    -- Dedupe identical logical palette switches: SetActivePalette / SetActivePaletteForCombo
    -- fire one callback per bar (1-6) or per combo mode (6x), so a single user palette change
    -- triggers 6+ identical cache flushes if unguarded.
    -- For no-op refreshes (same name -> same name, e.g. JSON import) include barIdentifier so
    -- every bar/combo still runs; otherwise only the first callback fires and the UI stays blank.
    palette.OnPaletteChanged(function(barIdentifier, oldPaletteName, newPaletteName)
        local sig;
        if oldPaletteName == newPaletteName then
            sig = tostring(barIdentifier) .. '\0' .. tostring(oldPaletteName) .. '\0' .. tostring(newPaletteName);
        else
            sig = tostring(oldPaletteName) .. '\0' .. tostring(newPaletteName);
        end
        if sig == lastPaletteVisualRefreshSig then
            return;
        end
        lastPaletteVisualRefreshSig = sig;
        data.InvalidateStorageKeyCache();
        display.ClearIconCache();
        if crossbarInitialized then
            crossbar.ClearIconCache();
        end
        slotrenderer.ClearSlotRenderingCache();
    end);

    -- Initialize macro patching system (backups original bytes, applies macrofix by default)
    macrosLib.initialize_patches();

    -- Apply correct mode based on setting
    local disableMacroBars = gConfig and gConfig.hotbarGlobal and gConfig.hotbarGlobal.disableMacroBars or false;
    if disableMacroBars then
        macrosLib.hide_macro_bar();  -- Switch to hide mode
    else
        -- Apply controller hold-to-show setting (only relevant when macros are not fully disabled)
        local holdToShow = gConfig.hotbarGlobal.controllerHoldToShow ~= false;  -- default true
        macrosLib.set_controller_hold_to_show(holdToShow);
    end
    -- If checkbox is OFF, macrofix is already applied by initialize_patches()

    -- Initialize crossbar when enabled (independent flag, not mode-based).
    -- Defensive: validate gConfig.hotbarCrossbar is a table before accessing.
    local crossbarConfig = gConfig and type(gConfig.hotbarCrossbar) == 'table' and gConfig.hotbarCrossbar or nil;
    local crossbarNeeded = gConfig and gConfig.crossbarEnabled ~= false;
    if crossbarNeeded and crossbarConfig then
        crossbar.Initialize(crossbarConfig, gAdjustedSettings.crossbarSettings);
        
        -- Get custom button mapping if Generic DirectInput is selected
        local customButtonMapping = nil;
        if crossbarConfig.controllerScheme == 'dinput' and crossbarConfig.customControllerMappings and crossbarConfig.customControllerMappings.dinput then
            customButtonMapping = crossbarConfig.customControllerMappings.dinput;
        end
        
        controller.Initialize({
            expandedCrossbarEnabled = crossbarConfig.enableExpandedCrossbar ~= false,
            doubleTapEnabled = crossbarConfig.enableDoubleTap or false,
            doubleTapWindow = crossbarConfig.doubleTapWindow or 0.3,
            controllerScheme = crossbarConfig.controllerScheme,
            triggerPressThreshold = crossbarConfig.triggerPressThreshold or 30,
            triggerReleaseThreshold = crossbarConfig.triggerReleaseThreshold or 15,
            minTriggerHold = crossbarConfig.minTriggerHold or 0.05,
            customButtonMapping = customButtonMapping,
        });
        controller.SetSlotActivateCallback(function(comboMode, slotIndex)
            crossbar.ActivateSlot(comboMode, slotIndex);
        end);
        -- Set controller blocking enabled state (crossbar-specific; shares the hotbar flag).
        controller.SetBlockingEnabled(GetCrossbarDisableXiMacrosEffective());
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

    -- Clear slot cache since settings changed
    slotrenderer.ClearAllCache();

    -- Update display layer (handles theme changes)
    display.UpdateVisuals(settings);

    -- Reset imtext font cache so new settings take effect
    imtext.Reset();

    -- Apply correct macro bar mode based on setting
    local disableMacroBars = gConfig and gConfig.hotbarGlobal and gConfig.hotbarGlobal.disableMacroBars or false;
    if disableMacroBars then
        macrosLib.hide_macro_bar();  -- Hide mode: macro bar hidden
    else
        macrosLib.show_macro_bar();  -- Macrofix mode: fast built-in macros
        -- Apply controller hold-to-show setting (only relevant when macros are not fully disabled)
        local holdToShow = gConfig.hotbarGlobal.controllerHoldToShow ~= false;  -- default true
        macrosLib.set_controller_hold_to_show(holdToShow);
    end

    -- Handle crossbar enable/disable (independent flag, not mode-based)
    local crossbarNeeded = gConfig and gConfig.crossbarEnabled ~= false;

    if crossbarNeeded and not crossbarInitialized then
        -- Initialize crossbar when newly needed
        crossbar.Initialize(gConfig.hotbarCrossbar, gAdjustedSettings.crossbarSettings);
        controller.Initialize({
            expandedCrossbarEnabled = gConfig.hotbarCrossbar.enableExpandedCrossbar ~= false,
            doubleTapEnabled = gConfig.hotbarCrossbar.enableDoubleTap or false,
            doubleTapWindow = gConfig.hotbarCrossbar.doubleTapWindow or 0.3,
            controllerScheme = gConfig.hotbarCrossbar.controllerScheme,
            triggerPressThreshold = gConfig.hotbarCrossbar.triggerPressThreshold or 30,
            triggerReleaseThreshold = gConfig.hotbarCrossbar.triggerReleaseThreshold or 15,
            minTriggerHold = gConfig.hotbarCrossbar.minTriggerHold or 0.05,
        });
        controller.SetSlotActivateCallback(function(comboMode, slotIndex)
            crossbar.ActivateSlot(comboMode, slotIndex);
        end);
        -- Set controller blocking enabled state (crossbar-specific; shares the hotbar flag).
        controller.SetBlockingEnabled(GetCrossbarDisableXiMacrosEffective());
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
        
        -- Update controller scheme with custom mapping if applicable
        local customMapping = nil;
        if gConfig.hotbarCrossbar.controllerScheme == 'dinput' and gConfig.hotbarCrossbar.customControllerMappings and gConfig.hotbarCrossbar.customControllerMappings.dinput then
            customMapping = gConfig.hotbarCrossbar.customControllerMappings.dinput;
        end
        controller.SetControllerScheme(gConfig.hotbarCrossbar.controllerScheme, customMapping);
        -- Update controller blocking state (crossbar-specific; shares the hotbar flag).
        controller.SetBlockingEnabled(GetCrossbarDisableXiMacrosEffective());
    end

    -- Update state tracking for hotbar enable/disable
    wasHotbarEnabled = (gConfig and gConfig.hotbarEnabled ~= false);
end

-- Main render function - called every frame
function M.DrawWindow(settings)
    if not M.initialized then return; end
    if not M.visible then return; end

    imtext.SetConfigFromSettings(settings and settings.font_settings);

    -- Reset deferred tooltip state for this frame
    slotrenderer.BeginFrame(settings and settings.font_settings);

    -- Update drag/drop state (must be called every frame, before drop zones)
    dragdrop.Update();

    -- Initialize textures on first draw (needed for icons in both modes)
    if not texturesInitialized then
        textures:Initialize();
        texturesInitialized = true;
    end

    -- Hotbar and crossbar are independent; either, both, or neither can be on. Menu-hide
    -- is evaluated here per-system so keyboard hotbars and the crossbar can have different
    -- hideOnMenuFocus behaviors (they previously shared `hotbarHideOnMenuFocus`).
    local menuOpen = gameState.IsMenuOpen();
    local hideKbOnMenu = gConfig.hotbarHideOnMenuFocus == true;
    local hideXbOnMenu = gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.crossbarHideOnMenuFocus == true;
    local showHotbar = gConfig
        and gConfig.hotbarEnabled ~= false
        and not (menuOpen and hideKbOnMenu);
    local showCrossbar = gConfig
        and gConfig.crossbarEnabled ~= false
        and not (menuOpen and hideXbOnMenu);

    -- Draw keyboard hotbars when enabled
    if showHotbar then
        display.DrawWindow(settings);
    else
        display.HideWindow();
    end

    -- Draw crossbar when enabled
    if showCrossbar and crossbarInitialized then
        crossbar.DrawWindow(gConfig.hotbarCrossbar, gAdjustedSettings.crossbarSettings);
    elseif crossbarInitialized then
        crossbar.SetHidden(true);
    end

    -- Always draw macro palette and keybind modal (regardless of enabled state)
    macropalette.DrawPalette();
    hotbarConfig.DrawKeybindModal();

    -- Drop previews / deferred overlaps happen in M.FinalizeFrame() — XIUI.lua calls it
    -- after palettemanager.Draw so the floating palette can win when its DropZone overlaps
    -- the HUD crossbar / Edit Full Palette preview.
end

-- Called by XIUI.lua at the very end of d3d_present, after palettemanager.Draw().
-- Resolves overlapping DropZone hits via FlushDeferredDrops (highest dropPriority wins)
-- and then renders the drag preview overlay.
function M.FinalizeFrame()
    if not M.initialized then return; end

    -- Resolve overlapping DropZones (HUD crossbar vs. Edit Full Palette preview, etc.)
    dragdrop.FlushDeferredDrops();
    dragdrop.Render();

    -- Handle slot dragged outside (remove the action)
    if dragdrop.WasDroppedOutside() then
        local lastPayload = dragdrop.GetLastPayload();
        if lastPayload then
            if lastPayload.type == 'slot' then
                -- Standard hotbar slot was dragged outside - clear it
                macropalette.ClearSlot(lastPayload.barIndex, lastPayload.slotIndex);
            elseif lastPayload.type == 'crossbar_slot' then
                -- Crossbar slot dragged outside: distinguish a draft slot (Edit Full Palette
                -- editing buffer) from a live HUD slot so we don't blow away the wrong store.
                if lastPayload.paletteEditStorageKey and data.ClearDraftSlotData then
                    data.ClearDraftSlotData(lastPayload.comboMode, lastPayload.slotIndex);
                else
                    data.ClearCrossbarSlotData(lastPayload.comboMode, lastPayload.slotIndex);
                end
                if crossbarInitialized then
                    crossbar.ClearIconCacheForSlot(lastPayload.comboMode, lastPayload.slotIndex);
                end
            end
        end
    end
end

-- Set module visibility
function M.SetHidden(hidden)
    M.visible = not hidden;
    display.SetHidden(hidden);
    if crossbarInitialized then
        crossbar.SetHidden(hidden);
    end
end

-- Cleanup on addon unload
function M.Cleanup()
    if not M.initialized then return; end

    -- Flush any pending slot saves before cleanup
    macropalette.FlushPendingSave();

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
    -- Universal 2hr glow state can hold a stale subtarget arm across zones.
    -- Defensive require: module may not be merged yet in intermediate states.
    local okU, uth = pcall(require, 'modules.hotbar.universal_two_hour');
    if okU and uth and uth.ResetUniversalTwoHourSubtargetGlowArm then
        uth.ResetUniversalTwoHourSubtargetGlowArm();
    end
end

function M.HandleJobChangePacket(e)
    local function TrySetJob(attempt)
        attempt = attempt or 1;
        local maxAttempts = 20;

        if data.SetPlayerJob() then
            -- Job successfully read - proceed with refresh.
            -- Reset universal 2hr subtarget glow arm; it can carry stale state across job change.
            local okU, uth = pcall(require, 'modules.hotbar.universal_two_hour');
            if okU and uth and uth.ResetUniversalTwoHourSubtargetGlowArm then
                uth.ResetUniversalTwoHourSubtargetGlowArm();
            end
            macropalette.SyncToCurrentJob();
            -- Universal 2hr global row mirrors the current job's 2hr ability; resync after job change.
            local okMg, macroGlobalDefaults = pcall(require, 'modules.hotbar.macro_global_defaults');
            if okMg and macroGlobalDefaults and macroGlobalDefaults.SyncUniversalTwoHourGlobalRow and gConfig then
                macroGlobalDefaults.SyncUniversalTwoHourGlobalRow(gConfig);
            end
            -- Honor pending "profile loaded before job was readable" (char select / logout) so
            -- Default Palette Type on Profile Load applies on first job-ready frame.
            local pending = palette.ConsumePendingApplyDefaultCrossbarScopeFromProfile
                and palette.ConsumePendingApplyDefaultCrossbarScopeFromProfile()
                or nil;
            palette.ValidatePalettesForJob(data.jobId, data.subjobId, {
                applyDefaultCrossbarScope = pending,
            });
            display.ClearIconCache();
            actions.ClearNoIconCache();
            if crossbarInitialized then
                crossbar.ClearIconCache();
            end
            slotrenderer.ClearAvailabilityCache();
            petpalette.CheckPetState();
        elseif attempt < maxAttempts then
            -- Not logged in yet or job not ready - retry
            local delay = math.min(0.5, 0.2 + (attempt * 0.05));
            ashita.tasks.once(delay, function()
                TrySetJob(attempt + 1);
            end);
        end
    end

    -- Initial delay to allow zone transition to complete
    ashita.tasks.once(0.5, function()
        TrySetJob(1);
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
    -- Controller events go through crossbar regardless of keyboard hotbar enable state.
    if not crossbarInitialized then return; end
    controller.HandleXInputState(e);
end

-- Handle xinput_button event for blocking game macros
-- Returns true if the button should be blocked
function M.HandleXInputButton(e)
    if not crossbarInitialized then return false; end
    return controller.HandleXInputButton(e);
end

-- Handle DirectInput button event for blocking game macros
-- Returns true if the button should be blocked
function M.HandleDInputButton(e)
    if not crossbarInitialized then return false; end
    return controller.HandleDInputButton(e);
end

-- Handle DirectInput state event (for D-pad POV)
function M.HandleDInputState(e)
    if not crossbarInitialized then return; end
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
