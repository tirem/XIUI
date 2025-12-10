--[[
* XIUI Helpers
* Main helper module that re-exports all utility functions
* This file maintains backwards compatibility while utilities are modularized
*
* New code should prefer importing from libs/ directly:
*   local colorLib = require('libs.color');
*   local memoryLib = require('libs.memory');
*   etc.
]]--

require('common');

-- ========================================
-- Import Modular Libraries
-- ========================================
local memoryLib = require('libs.memory');
local entityLib = require('libs.entity');
local partyLib = require('libs.party');
local targetLib = require('libs.target');
local fontsLib = require('libs.fonts');
local drawingLib = require('libs.drawing');
local packetsLib = require('libs.packets');
local texturesLib = require('libs.textures');
local hpLib = require('libs.hp');
local fastcastLib = require('libs.fastcast');
local formatLib = require('libs.format');
local colorLib = require('libs.color');
local statusIconsLib = require('libs.statusicons');
local windowBackgroundLib = require('libs.windowbackground');

-- Handler imports (still in handlers/)
local statusHandler = require('handlers.statushandler');
local buffTable = require('libs.bufftable');

-- ========================================
-- Global Exports for Backwards Compatibility
-- ========================================
-- These expose functions globally so existing code continues to work

-- Entity Constants (from entity.lua)
SPAWN_FLAG_PLAYER = entityLib.SPAWN_FLAG_PLAYER;
SPAWN_FLAG_NPC = entityLib.SPAWN_FLAG_NPC;
RENDER_FLAG_VISIBLE = entityLib.RENDER_FLAG_VISIBLE;
RENDER_FLAG_HIDDEN = entityLib.RENDER_FLAG_HIDDEN;

-- Fast Cast Constants (from fastcast.lua)
CURE_SPELLS = fastcastLib.CURE_SPELLS;

-- Memory Accessors (from memory.lua)
GetD3D8Device = memoryLib.GetD3D8Device;
GetPlayerSafe = memoryLib.GetPlayerSafe;
GetPartySafe = memoryLib.GetPartySafe;
GetEntitySafe = memoryLib.GetEntitySafe;
GetTargetSafe = memoryLib.GetTargetSafe;
GetInventorySafe = memoryLib.GetInventorySafe;
GetCastBarSafe = memoryLib.GetCastBarSafe;
GetRecastSafe = memoryLib.GetRecastSafe;
GetPetSafe = memoryLib.GetPetSafe;

-- Entity Utilities (from entity.lua)
GetIsMob = entityLib.GetIsMob;
GetIsMobByIndex = entityLib.GetIsMobByIndex;
JobHasMP = entityLib.JobHasMP;
JOBS_WITH_MP = entityLib.JOBS_WITH_MP;

-- Wrappers for entity color functions that inject dependencies
function GetEntityNameColorRGBA(targetEntity, targetIndex, colorConfig)
    return entityLib.GetEntityNameColorRGBA(targetEntity, targetIndex, colorConfig, partyLib, colorLib);
end

function GetEntityNameColor(targetEntity, targetIndex, colorConfig)
    return entityLib.GetEntityNameColor(targetEntity, targetIndex, colorConfig, partyLib, colorLib);
end

-- Wrapper for backwards compatibility - uses shared entity colors
function GetColorOfTargetRGBA(targetEntity, targetIndex)
    if gConfig and gConfig.colorCustomization and gConfig.colorCustomization.shared then
        return GetEntityNameColorRGBA(targetEntity, targetIndex, gConfig.colorCustomization.shared);
    end
    return {1,1,1,1}; -- Default white RGBA
end

-- Wrapper function that returns ARGB format (for backwards compatibility)
function GetColorOfTarget(targetEntity, targetIndex)
    local rgba = GetColorOfTargetRGBA(targetEntity, targetIndex);
    return colorLib.RGBAToARGB(rgba);
end

-- Party Utilities (from party.lua)
MarkPartyCacheDirty = partyLib.MarkPartyCacheDirty;
IsMemberOfParty = partyLib.IsMemberOfParty;
IsPartyMemberByServerId = partyLib.IsPartyMemberByServerId;

-- Target Utilities (from target.lua)
GetStPartyIndex = targetLib.GetStPartyIndex;
GetSubTargetActive = targetLib.GetSubTargetActive;
GetTargets = targetLib.GetTargets;
GetIsTargetLockedOn = targetLib.GetIsTargetLockedOn;

-- Font Utilities (from fonts.lua)
GetFontWeightFlags = fontsLib.GetFontWeightFlags;
FontManager = fontsLib.FontManager;
ColorCachedFont = fontsLib.ColorCachedFont;
SetFontsVisible = fontsLib.SetFontsVisible;

-- Drawing Utilities (from drawing.lua)
draw_rect = drawingLib.draw_rect;
draw_rect_background = drawingLib.draw_rect_background;
draw_circle = drawingLib.draw_circle;
GetUIDrawList = drawingLib.GetUIDrawList;

-- Packet Utilities (from packets.lua)
GetIndexFromId = packetsLib.GetIndexFromId;
ParseActionPacket = packetsLib.ParseActionPacket;
ParseMobUpdatePacket = packetsLib.ParseMobUpdatePacket;
ParseMessagePacket = packetsLib.ParseMessagePacket;
valid_server_id = packetsLib.valid_server_id;

-- Texture Utilities (from textures.lua)
LoadTexture = texturesLib.LoadTexture;
LoadTextureWithExt = texturesLib.LoadTextureWithExt;

-- HP Utilities (from hp.lua)
HpInterpolation = hpLib.HpInterpolation;
GetHpInterpolationColors = hpLib.GetHpInterpolationColors;
GetHpColors = hpLib.GetHpColors;
GetCustomHpColors = hpLib.GetCustomHpColors;
GetCustomGradient = hpLib.GetCustomGradient;
easeOutPercent = hpLib.easeOutPercent;

-- Fast Cast Utilities (from fastcast.lua)
CalculateFastCast = fastcastLib.CalculateFastCast;

-- Format Utilities (from format.lua)
SeparateNumbers = formatLib.SeparateNumbers;
FormatInt = formatLib.FormatInt;
deep_copy_table = formatLib.deep_copy_table;
GetJobStr = formatLib.GetJobStr;

-- Color Utilities (from color.lua)
ARGBToRGBA = colorLib.ARGBToRGBA;
RGBAToARGB = colorLib.RGBAToARGB;
ARGBToImGui = colorLib.ARGBToImGui;
ImGuiToARGB = colorLib.ImGuiToARGB;
ARGBToABGR = colorLib.ARGBToABGR;
HexToImGui = colorLib.HexToImGui;
ImGuiToHex = colorLib.ImGuiToHex;
HexToARGB = colorLib.HexToARGB;
GetColorSetting = colorLib.GetColorSetting;
GetGradientSetting = colorLib.GetGradientSetting;

-- Legacy color functions (also from color.lua)
rgbToHsv = colorLib.rgbToHsv;
hsvToRgb = colorLib.hsvToRgb;
hex2rgb = colorLib.hex2rgb;
rgb2hex = colorLib.rgb2hex;
shiftSaturationAndBrightness = colorLib.shiftSaturationAndBrightness;
shiftGradient = colorLib.shiftGradient;

-- Status Icons (from statusicons.lua)
-- Wrapper that injects dependencies
function DrawStatusIcons(statusIds, iconSize, maxColumns, maxRows, drawBg, xOffset, buffTimes, settings)
    return statusIconsLib.DrawStatusIcons(statusIds, iconSize, maxColumns, maxRows, drawBg, xOffset, buffTimes, settings, statusHandler, buffTable);
end

ClearDebuffFontCache = statusIconsLib.ClearDebuffFontCache;

-- Legacy debuffTable global (for backwards compatibility)
debuffTable = statusIconsLib.GetDebuffTable();

-- Window Background Utilities (from windowbackground.lua)
WindowBackground = windowBackgroundLib;