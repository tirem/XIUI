--[[
* XIUI Font Utilities
* FontManager, ColorCachedFont, and font helper functions
]]--

local gdi = require('submodules.gdifonts.include');

local M = {};

-- ========================================
-- Font Registry (for lightweight property updates)
-- ========================================
-- Tracks all created fonts to enable batch property updates without recreation
local fontRegistry = {};
local nextFontId = 1;

-- Register a font and return its ID
local function registerFont(fontObj)
    local id = nextFontId;
    nextFontId = nextFontId + 1;
    fontRegistry[id] = fontObj;
    return id;
end

-- Unregister a font by ID
local function unregisterFont(fontId)
    if fontId then
        fontRegistry[fontId] = nil;
    end
end

-- Update outline width on all registered fonts (lightweight, no recreation)
function M.UpdateAllOutlineWidths(width)
    for _, fontObj in pairs(fontRegistry) do
        if fontObj and fontObj.set_outline_width then
            fontObj:set_outline_width(width);
        end
    end
end

-- ========================================
-- Font Weight Helper
-- ========================================
-- Converts fontWeight string setting to GDI font flags
function M.GetFontWeightFlags(fontWeight)
    if fontWeight == 'Bold' then
        return gdi.FontFlags.Bold;
    else
        return gdi.FontFlags.None;
    end
end

-- ========================================
-- FontManager
-- ========================================
-- Provides a centralized API for font lifecycle management
-- Eliminates code duplication across modules
-- All fonts are registered for lightweight property updates
M.FontManager = {
    -- Create a single font object (registered for batch updates)
    create = function(settings)
        local fontObj = gdi:create_object(settings);
        if fontObj then
            fontObj._registryId = registerFont(fontObj);
        end
        return fontObj;
    end,

    -- Destroy a font object safely (unregisters from registry)
    destroy = function(fontObj)
        if fontObj ~= nil then
            unregisterFont(fontObj._registryId);
            gdi:destroy_object(fontObj);
        end
        return nil;
    end,

    -- Recreate a font with new settings (re-registers in registry)
    recreate = function(fontObj, settings)
        if fontObj ~= nil then
            unregisterFont(fontObj._registryId);
            gdi:destroy_object(fontObj);
        end
        local newFont = gdi:create_object(settings);
        if newFont then
            newFont._registryId = registerFont(newFont);
        end
        return newFont;
    end,

    -- Batch create multiple fonts from settings table
    createBatch = function(fontSettingsTable)
        local fonts = {};
        for key, settings in pairs(fontSettingsTable) do
            local fontObj = gdi:create_object(settings);
            if fontObj then
                fontObj._registryId = registerFont(fontObj);
            end
            fonts[key] = fontObj;
        end
        return fonts;
    end,

    -- Batch destroy multiple fonts
    destroyBatch = function(fontsTable)
        for key, fontObj in pairs(fontsTable) do
            if fontObj ~= nil then
                unregisterFont(fontObj._registryId);
                gdi:destroy_object(fontObj);
            end
        end
    end
};

-- ========================================
-- ColorCachedFont Wrapper
-- ========================================
-- Wraps a GDI font with automatic color caching for performance
-- Eliminates redundant set_font_color calls
M.ColorCachedFont = {
    new = function(fontObj)
        return {
            font = fontObj,
            lastColor = nil,

            -- Set color with automatic caching
            setColor = function(self, color)
                if self.lastColor ~= color then
                    self.font:set_font_color(color);
                    self.lastColor = color;
                end
            end,

            -- Proxy methods to underlying font
            set_text = function(self, text) self.font:set_text(text); end,
            set_visible = function(self, visible) self.font:set_visible(visible); end,
            set_position_x = function(self, x) self.font:set_position_x(x); end,
            set_position_y = function(self, y) self.font:set_position_y(y); end,
            set_font_height = function(self, height) self.font:set_font_height(height); end,
            get_text_size = function(self) return self.font:get_text_size(); end,
        }
    end
};

-- ========================================
-- Font Visibility Helper
-- ========================================
-- Set visibility for multiple fonts at once
function M.SetFontsVisible(fontTable, visible)
    for _, fontObj in pairs(fontTable) do
        if fontObj ~= nil then
            -- Support both regular GDI fonts and ColorCachedFont wrappers
            if fontObj.set_visible then
                fontObj:set_visible(visible);
            elseif fontObj.font and fontObj.font.set_visible then
                fontObj.font:set_visible(visible);
            end
        end
    end
end

return M;
