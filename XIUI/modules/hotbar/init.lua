--[[
* XIUI Hotbar Module
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

--[[
-- Big thanks to:
-- - Akaden & Rubenator: For the inspiration to the moving icons/hotbars part
-- - Maverickdfz:        Inspiration to the mouse actions
--]]

require('common');
require('handlers.helpers');
local gdi = require('submodules.gdifonts.include');
local windowBg = require('libs.windowbackground');

local data = require('modules.hotbar.data');
local display = require('modules.hotbar.display');
local actions = require('modules.hotbar.actions');

local M = {};

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

    print('[XIUI hotbar] Initialising...');

    -- Ensure treasure pool settings have defaults BEFORE creating fonts
    if gConfig then
        -- Clear any stale preview state
        gConfig.hotbarPreview = false;

        -- Set defaults for new settings
        if gConfig.hotbarEnabled == nil then gConfig.hotbarEnabled = true; end
        if gConfig.hotbarFontSize == nil or gConfig.hotbarFontSize < 8 then
            gConfig.hotbarFontSize = 10;
        end
        if gConfig.hotbarScaleX == nil or gConfig.hotbarScaleX < 0.5 then
            gConfig.hotbarScaleX = 1.0;
        end
        if gConfig.hotbarScaleY == nil or gConfig.hotbarScaleY < 0.5 then
            gConfig.hotbarScaleY = 1.0;
        end
        -- Split background/border settings (like petbar)
        if gConfig.hotbarBgScale == nil or gConfig.hotbarBgScale < 0.1 then
            gConfig.hotbarBgScale = 1.0;
        end
        if gConfig.hotbarBorderScale == nil or gConfig.hotbarBorderScale < 0.1 then
            gConfig.hotbarBorderScale = 1.0;
        end
        -- Migrate old hotbarOpacity to new split settings
        if gConfig.hotbarBackgroundOpacity == nil then
            if gConfig.hotbarOpacity ~= nil then
                gConfig.hotbarBackgroundOpacity = gConfig.hotbarOpacity;
                gConfig.hotbarOpacity = nil;  -- Clean up old setting
            else
                gConfig.hotbarBackgroundOpacity = 0.87;
            end
        end
        if gConfig.hotbarBorderOpacity == nil then gConfig.hotbarBorderOpacity = 1.0; end
        if gConfig.hotbarBackgroundTheme == nil then gConfig.hotbarBackgroundTheme = 'Plain'; end
    end

    -- Initialize data layer first
    data.Initialize();

    -- Create fonts using settings from gAdjustedSettings.hotbarSettings
    -- (passed in as 'settings' parameter by module registry)
    -- Settings include global font family/weight applied via updater.lua
    local fontSettings = settings and settings.font_settings;
    local titleFontSettings = settings and settings.title_font_settings;

    -- Validate font settings exist before creating fonts
    if not fontSettings or not titleFontSettings then
        print('[XIUI hotbar] Warning: Invalid font settings, skipping font creation');
        M.initialized = true;
        return;
    end

     --//@TODO: 
    -- -- Use pcall for safety during font creation
    -- local function safeCreateFont(settings)
    --     local success, result = pcall(function()
    --         return FontManager.create(settings);
    --     end);
    --     if success then
    --         return result;
    --     end
    --     print('[XIUI hotbar] Warning: Font creation failed');
    --     return nil;
    -- end


    --//@TODO: 
    --data.SetAllFontsVisible(false);

    -- Initialize display layer (creates background primitive)
    display.Initialize(settings);

    print('[XIUI hotbar] Initialized');
    M.initialized = true;
    
end

--//@TODO:
-- Update visual elements (fonts, themes) when settings change
function M.UpdateVisuals(settings)
    if not M.initialized then return; end

    -- Validate settings
    if not settings or not settings.font_settings or not settings.title_font_settings then
        return;
    end

   
    -- Clear color cache
    data.ClearColorCache();

    -- Update display layer
    display.UpdateVisuals(settings);
end

-- Main render function - called every frame
function M.DrawWindow(settings)
    if not M.initialized then return; end
    if not M.visible then return; end

    display.DrawWindow(settings);

    --//@TODO:
    -- -- Read pool state from memory (skip in preview mode)
    -- if not data.IsPreviewActive() then
    --     data.ReadFromMemory();
    -- end

    -- -- Check for real items (from memory, not preview)
    -- local hasRealItems = data.HasRealItems();

    -- -- Draw treasure pool if enabled and (has real items OR preview is on)
    -- local enabled = gConfig.hotbarEnabled;
    -- local showWindow = (hasRealItems or data.previewEnabled) and enabled;
    -- if showWindow then
    --     display.DrawWindow(settings);
    -- else
    --     display.HideWindow();
    -- end
end

-- Set module visibility
function M.SetHidden(hidden)
    M.visible = not hidden;
    --//@TODO: 
    -- if hidden then
    --     data.SetAllFontsVisible(false);
    -- end
    display.SetHidden(hidden);
end

-- Cleanup on addon unload
function M.Cleanup()
    if not M.initialized then return; end

    --//@TODO:
    -- -- Destroy header and button fonts
    -- data.headerFont = FontManager.destroy(data.headerFont);
    -- data.lotAllFont = FontManager.destroy(data.lotAllFont);
    -- data.passAllFont = FontManager.destroy(data.passAllFont);
    -- data.toggleFont = FontManager.destroy(data.toggleFont);

    -- -- Destroy tab fonts
    -- data.tabPoolFont = FontManager.destroy(data.tabPoolFont);
    -- data.tabHistoryFont = FontManager.destroy(data.tabHistoryFont);

    -- -- Destroy history fonts
    -- for i = 0, data.MAX_HISTORY_ITEMS - 1 do
    --     if data.historyItemFonts[i] then
    --         data.historyItemFonts[i] = FontManager.destroy(data.historyItemFonts[i]);
    --     end
    --     if data.historyWinnerFonts[i] then
    --         data.historyWinnerFonts[i] = FontManager.destroy(data.historyWinnerFonts[i]);
    --     end
    -- end

    -- -- Destroy per-slot fonts
    -- for slot = 0, data.MAX_POOL_SLOTS - 1 do
    --     if data.itemNameFonts[slot] then
    --         data.itemNameFonts[slot] = FontManager.destroy(data.itemNameFonts[slot]);
    --     end
    --     if data.timerFonts[slot] then
    --         data.timerFonts[slot] = FontManager.destroy(data.timerFonts[slot]);
    --     end
    --     if data.lotFonts[slot] then
    --         data.lotFonts[slot] = FontManager.destroy(data.lotFonts[slot]);
    --     end
    --     -- Expanded view fonts
    --     if data.lottersFonts[slot] then
    --         data.lottersFonts[slot] = FontManager.destroy(data.lottersFonts[slot]);
    --     end
    --     if data.passersFonts[slot] then
    --         data.passersFonts[slot] = FontManager.destroy(data.passersFonts[slot]);
    --     end
    --     if data.pendingFonts[slot] then
    --         data.pendingFonts[slot] = FontManager.destroy(data.pendingFonts[slot]);
    --     end
    --     if data.lotItemFonts[slot] then
    --         data.lotItemFonts[slot] = FontManager.destroy(data.lotItemFonts[slot]);
    --     end
    --     if data.passItemFonts[slot] then
    --         data.passItemFonts[slot] = FontManager.destroy(data.passItemFonts[slot]);
    --     end
    --     -- Member fonts
    --     if data.memberFonts[slot] then
    --         for memberIdx = 0, data.MAX_MEMBERS_PER_ITEM - 1 do
    --             if data.memberFonts[slot][memberIdx] then
    --                 data.memberFonts[slot][memberIdx] = FontManager.destroy(data.memberFonts[slot][memberIdx]);
    --             end
    --         end
    --     end
    -- end

    -- -- Clear font tables
    -- data.allFonts = nil;
    -- data.itemNameFonts = {};
    -- data.timerFonts = {};
    -- data.lotFonts = {};
    -- data.lottersFonts = {};
    -- data.passersFonts = {};
    -- data.pendingFonts = {};
    -- data.lotItemFonts = {};
    -- data.passItemFonts = {};
    -- data.memberFonts = {};
    -- data.historyItemFonts = {};
    -- data.historyWinnerFonts = {};

    -- Cleanup display and data layers
    display.Cleanup();
    data.Cleanup();

    M.initialized = false;
end

-- ============================================
-- Zone Change Handler
-- ============================================

function M.HandleZonePacket()
    data.Clear();
end

-- ============================================
-- Key Handler
-- ============================================
function M.HandleKey(event)
    return actions.HandleKey(event);
end

-- ============================================
-- Command Interface
-- ============================================

--//@TODO:
-- function M.LotAll()
--     return actions.LotAll();
-- end

-- function M.PassAll()
--     return actions.PassAll();
-- end

-- function M.LotItem(slot)
--     return actions.LotItem(slot);
-- end

-- function M.PassItem(slot)
--     return actions.PassItem(slot);
-- end

-- ============================================
-- Query Interface
-- ============================================

--//@TODO:
-- function M.GetPoolCount()
--     return data.GetPoolCount();
-- end

-- function M.HasItems()
--     return data.HasItems();
-- end

-- function M.GetPoolItems()
--     return data.GetPoolItems();
-- end

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
