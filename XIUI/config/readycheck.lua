--[[
* XIUI Config Menu - Ready Check Settings
]]--

require('common');
local imgui      = require('imgui');
local components = require('config.components');
local readycheck = require('modules.readycheck.init');

local M = {};

function M.DrawSettings()
    components.DrawCheckbox('Enabled', 'showReadyCheck', CheckVisibility);
    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    -- Sound toggles
    local sound_on_checker = readycheck.GetSoundOnCheckerFlag();
    imgui.Checkbox('Play sound when sending a ready check##rc_cfg',   sound_on_checker);

    local sound_on_prompt  = readycheck.GetSoundOnPromptFlag();
    imgui.Checkbox('Play sound when receiving a ready check##rc_cfg', sound_on_prompt);

    imgui.Spacing();

    -- Sound file dropdown
    imgui.Text('Sound file:');
    local files, sel_idx = readycheck.GetSoundFileList();
    if files and #files > 0 then
        local preview = files[sel_idx[1]] or '';
        imgui.SetNextItemWidth(280);
        if imgui.BeginCombo('##rc_cfg_sound', preview, ImGuiComboFlags_None) then
            for i, fname in ipairs(files) do
                local selected = (i == sel_idx[1]);
                if imgui.Selectable(fname, selected) then
                    sel_idx[1] = i;
                end
                if selected then imgui.SetItemDefaultFocus(); end
            end
            imgui.EndCombo();
        end
        imgui.SameLine();
        if imgui.Button('Refresh##rc_cfg') then
            readycheck.ScanSoundFiles();
        end
    else
        imgui.TextDisabled('No .wav files found in sound\\ folder.');
        imgui.SameLine();
        if imgui.Button('Refresh##rc_cfg') then
            readycheck.ScanSoundFiles();
        end
    end

    imgui.Spacing();

    if imgui.Button('Test Sound##rc_cfg') then
        readycheck.TestSound();
    end
    imgui.SameLine();
    if imgui.Button('Save##rc_cfg') then
        readycheck.SaveSettings();
    end
end

function M.DrawColorSettings()
    imgui.TextDisabled('No color settings for Ready Check.');
end

return M;
