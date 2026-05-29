--[[
* XIUI Config Menu - Ready Check Settings
]]--

require('common');
local imgui      = require('imgui');
local components = require('config.components');
local rcSlider   = require('modules.readycheck.slider');
local readycheck = require('modules.readycheck.init');

local M = {};

local SOUND_DIR          = addon.path .. 'modules\\readycheck\\sound\\';
local DEFAULT_SOUND_FILE = 'ffxiv-notification.wav';
local VOLUME_DETENTS     = { 50, 100 };

local function ensureDefaults()
    if gConfig.readyCheckSoundFile == nil or gConfig.readyCheckSoundFile == '' then
        gConfig.readyCheckSoundFile = DEFAULT_SOUND_FILE;
    end
    gConfig.readyCheckSoundVolume = math.max(0, math.min(150, gConfig.readyCheckSoundVolume or 50));
end

local function getSoundFiles()
    return ashita.fs.get_directory(SOUND_DIR, '.*\\.wav$') or {};
end

local function drawSoundFileRow()
    imgui.Text('Sound file:');
    local files = getSoundFiles();
    if #files > 0 then
        imgui.SetNextItemWidth(280);
        components.Combo('##rc_cfg', gConfig, 'readyCheckSoundFile', files, nil, DEFAULT_SOUND_FILE);
    else
        imgui.TextDisabled('No .wav files found in sound\\ folder.');
    end

    imgui.SameLine();
    if imgui.Button('Test Sound##rc_cfg') then
        readycheck.TestSound();
    end
end

function M.DrawSettings()
    ensureDefaults();

    components.DrawCheckbox('Enabled', 'showReadyCheck', CheckVisibility);
    components.DrawCheckbox('Play sound when sending a ready check', 'readyCheckSoundOnChecker');
    components.DrawCheckbox('Play sound when receiving a ready check', 'readyCheckSoundOnPrompt');

    imgui.Spacing();
    drawSoundFileRow();

    imgui.Spacing();
    local volume = { gConfig.readyCheckSoundVolume };
    rcSlider.DrawInt('Volume:##rc_cfg', volume, 0, 150, '%d%%', VOLUME_DETENTS, 280, SaveSettingsToDisk);
    gConfig.readyCheckSoundVolume = volume[1];
end

function M.DrawColorSettings()
    imgui.TextDisabled('No color settings for Ready Check.');
end

return M;
