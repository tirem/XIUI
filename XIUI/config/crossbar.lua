--[[
* XIUI Config Menu - Crossbar (sidebar entry)
* Delegates to config/crossbar_settings.lua for controller layout, palettes, and visuals.
* Keyboard hotbars are config/hotbar.lua only.
]]--

require('handlers.helpers');
local imgui = require('imgui');
local drawing = require('libs.drawing');
local components = require('config.components');
local hotbarConfig = require('config.hotbar');
local crossbarSettings = require('config.crossbar_settings');

local M = {};

function M.DrawSettings(state)
    local cross = gConfig.hotbarCrossbar;
    if not cross then
        imgui.TextColored({1.0, 0.5, 0.5, 1.0}, 'Crossbar settings not initialized.');
        return { selectedCrossbarTab = (state and state.selectedCrossbarTab) or 1 };
    end

    local en = { gConfig.crossbarEnabled ~= false };
    if imgui.Checkbox('Enable Crossbar##xbEnable', en) then
        gConfig.crossbarEnabled = en[1];
        cross.showCrossbar = en[1];
        SaveSettingsOnly();
        DeferredUpdateVisuals();
    end
    imgui.ShowHelp('When enabled, the L2/R2 controller crossbar loads and can be used in-game. When disabled, crossbar UI and controller handling for it stay off to save overhead. Independent from keyboard hotbars (Hotbar category).');

    local lock = { gConfig.crossbarLockMovement == true };
    if imgui.Checkbox('Lock Crossbar##xbLockMove', lock) then
        gConfig.crossbarLockMovement = lock[1];
        if gConfig.crossbarLockMovement then
            drawing.ResetAnchorState('Crossbar');
        end
        SaveSettingsOnly();
        DeferredUpdateVisuals();
    end
    imgui.ShowHelp('When enabled, prevents dragging the crossbar window and drag/drop or slot swaps on crossbar slots. Separate from Lock Movement on the Hotbar category.');

    imgui.Spacing();
    components.DrawPartyCheckbox(cross, 'Hide When Menu Open', 'crossbarHideOnMenuFocus', DeferredUpdateVisuals);
    imgui.ShowHelp('Hide the crossbar when a game menu is open (equipment, map, etc.). Separate from Hotbar → Hide When Menu Open (keyboard strips).');

    components.DrawPartyCheckbox(cross, 'Disable Crossbar While In Menu##xbDisableInMenu', 'crossbarDisableInMenu', DeferredUpdateVisuals);
    imgui.ShowHelp('This options temporarily disables the crossbars while keeping them visible while the main menu is open. This setting allows users to continue to use the games "Quick Jump" option in inventories when holding down either trigger and using Left/Right on the DPad');

    hotbarConfig.DrawSharedDisableXiMacrosControls('xb');
    hotbarConfig.DrawSharedSkillchainHighlightControls('xb');

    if gConfig.crossbarEnabled ~= false then
        imgui.Spacing();
        crossbarSettings.DrawControllerPaletteCycleGlobalOptions();
        imgui.Spacing();
        crossbarSettings.DrawLogPaletteNameCheckboxCrossbar('##xbLogPal');
    end

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    return crossbarSettings.DrawStandaloneCrossbarSettings(state);
end

function M.DrawColorSettings(state)
    return crossbarSettings.DrawStandaloneCrossbarColorSettings(state);
end

-- Used by config.lua (window open, /xiui cpalette) — single entry; no separate require of crossbar_settings
function M.OnConfigWindowOpened()
    return crossbarSettings.OnConfigWindowOpened();
end

function M.OpenCrossbarManagePalettesTab()
    return crossbarSettings.OpenCrossbarManagePalettesTab();
end

return M;
