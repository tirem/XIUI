--[[
* XIUI Config - Palette Manager
* A separate modal window for managing palettes across job/subjob combinations
* Supports creating, renaming, deleting, reordering, and copying palettes
]]--

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local jobs = require('libs.jobs');
local palette = require('modules.hotbar.palette');
local data = require('modules.hotbar.data');
local components = require('config.components');

local M = {};

-- Window state
local windowState = {
    isOpen = false,
    selectedJobId = nil,
    selectedSubjobId = nil,  -- 0 = shared
    selectedPaletteType = 'hotbar',  -- 'hotbar' or 'crossbar'
    selectedPaletteName = nil,
    statusMessage = nil,  -- Brief status feedback for operations
    statusMessageTime = 0,  -- Time when status was set
};

-- Modal state for create/rename/copy/delete operations
local modalState = {
    isOpen = false,
    mode = nil,  -- 'create', 'rename', 'copy', 'delete'
    inputBuffer = { '' },
    errorMessage = nil,
    -- For copy operation
    copyTargetJobId = nil,
    copyTargetSubjobId = nil,
    -- For delete confirmation
    deletePaletteName = nil,
};

-- Get job name from ID (uses libs/jobs.lua)
local function GetJobName(jobId)
    if jobId == 0 then return 'Shared'; end
    return jobs[jobId] or ('Job ' .. jobId);
end

-- Check if using fallback (shared) palettes for the selected type
local function IsUsingFallback(jobId, subjobId, paletteType)
    return palette.IsUsingFallback(jobId, subjobId, paletteType);
end

-- Set a brief status message (auto-clears after a few seconds)
local function SetStatusMessage(message)
    windowState.statusMessage = message;
    windowState.statusMessageTime = os.clock();
end

-- Open the palette manager window
function M.Open()
    windowState.isOpen = true;
    -- Initialize with current job if not set
    if not windowState.selectedJobId then
        windowState.selectedJobId = data.jobId or 1;
    end
    if not windowState.selectedSubjobId then
        windowState.selectedSubjobId = data.subjobId or 0;
    end
end

-- Close the palette manager window
function M.Close()
    windowState.isOpen = false;
end

-- Check if window is open
function M.IsOpen()
    return windowState.isOpen;
end

-- Helper: Draw palette type selector (hotbar vs crossbar)
local function DrawPaletteTypeSelector()
    imgui.Text('Type:');
    imgui.SameLine();
    if imgui.RadioButton('Hotbar##paletteType', windowState.selectedPaletteType == 'hotbar') then
        windowState.selectedPaletteType = 'hotbar';
        windowState.selectedPaletteName = nil;
    end
    imgui.SameLine();
    if imgui.RadioButton('Crossbar##paletteType', windowState.selectedPaletteType == 'crossbar') then
        windowState.selectedPaletteType = 'crossbar';
        windowState.selectedPaletteName = nil;
    end
end

-- Helper: Draw job selector dropdown
local function DrawJobSelector()
    local changed = false;
    local currentLabel = GetJobName(windowState.selectedJobId);

    imgui.Text('Job:');
    imgui.SameLine();
    imgui.PushItemWidth(80);
    if imgui.BeginCombo('##jobSelector', currentLabel) then
        for jobId = 1, 22 do
            local isSelected = (jobId == windowState.selectedJobId);
            if imgui.Selectable(GetJobName(jobId), isSelected) then
                if jobId ~= windowState.selectedJobId then
                    windowState.selectedJobId = jobId;
                    windowState.selectedSubjobId = 0;  -- Reset to shared
                    windowState.selectedPaletteName = nil;
                    changed = true;
                end
            end
            if isSelected then
                imgui.SetItemDefaultFocus();
            end
        end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();

    return changed;
end

-- Helper: Draw subjob selector dropdown
local function DrawSubjobSelector()
    local changed = false;
    local currentLabel = windowState.selectedSubjobId == 0 and 'Shared' or GetJobName(windowState.selectedSubjobId);

    imgui.SameLine();
    imgui.Text('Subjob:');
    imgui.SameLine();
    imgui.PushItemWidth(80);
    if imgui.BeginCombo('##subjobSelector', currentLabel) then
        -- Shared option first
        local sharedSelected = (windowState.selectedSubjobId == 0);
        if imgui.Selectable('Shared', sharedSelected) then
            if windowState.selectedSubjobId ~= 0 then
                windowState.selectedSubjobId = 0;
                windowState.selectedPaletteName = nil;
                changed = true;
            end
        end
        if sharedSelected then
            imgui.SetItemDefaultFocus();
        end
        -- All jobs as subjob options
        for subjobId = 1, 22 do
            local isSelected = (subjobId == windowState.selectedSubjobId);
            if imgui.Selectable(GetJobName(subjobId), isSelected) then
                if subjobId ~= windowState.selectedSubjobId then
                    windowState.selectedSubjobId = subjobId;
                    windowState.selectedPaletteName = nil;
                    changed = true;
                end
            end
            if isSelected then
                imgui.SetItemDefaultFocus();
            end
        end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();

    return changed;
end

-- Helper: Draw palette list
local function DrawPaletteList()
    local palettes;

    -- Always ensure default shared palette exists for this job
    -- This handles both direct shared view and fallback scenarios
    if windowState.selectedPaletteType == 'hotbar' then
        palette.EnsureDefaultPaletteExists(windowState.selectedJobId, 0);
        palettes = palette.GetAvailablePalettes(1, windowState.selectedJobId, windowState.selectedSubjobId);
    else
        palette.EnsureCrossbarDefaultPaletteExists(windowState.selectedJobId, 0);
        palettes = palette.GetCrossbarAvailablePalettes(windowState.selectedJobId, windowState.selectedSubjobId);
    end

    -- Check fallback status using centralized function
    local usingFallback = IsUsingFallback(windowState.selectedJobId, windowState.selectedSubjobId, windowState.selectedPaletteType);

    -- Palette list header with clearer source indication
    local headerText;
    if windowState.selectedSubjobId == 0 then
        headerText = string.format('Shared Library (%s)', GetJobName(windowState.selectedJobId));
    else
        headerText = string.format('%s/%s', GetJobName(windowState.selectedJobId), GetJobName(windowState.selectedSubjobId));
    end
    imgui.Text(headerText);
    if usingFallback then
        imgui.SameLine();
        imgui.TextColored({0.4, 0.8, 1.0, 1.0}, '(Shared Library)');
    end
    imgui.Separator();

    -- List of palettes
    local listHeight = 150;
    imgui.BeginChild('##paletteList', { 0, listHeight }, true);

    if #palettes == 0 then
        imgui.TextColored({0.5, 0.5, 0.5, 1.0}, 'No palettes defined');
    else
        for i, paletteName in ipairs(palettes) do
            local isSelected = windowState.selectedPaletteName == paletteName;

            -- Custom selected state styling using XIUI colors
            if isSelected then
                local gold = components.TAB_STYLE.gold;
                imgui.PushStyleColor(ImGuiCol_Header, {gold[1], gold[2], gold[3], 0.4});
                imgui.PushStyleColor(ImGuiCol_HeaderHovered, {gold[1], gold[2], gold[3], 0.5});
                imgui.PushStyleColor(ImGuiCol_HeaderActive, {gold[1], gold[2], gold[3], 0.6});
            end

            if imgui.Selectable(paletteName .. '##palette' .. i, isSelected) then
                windowState.selectedPaletteName = paletteName;
            end

            if isSelected then
                imgui.PopStyleColor(3);
            end

            -- Context menu for right-click
            if imgui.BeginPopupContextItem('##paletteContext' .. i) then
                if imgui.MenuItem('Rename') then
                    modalState.mode = 'rename';
                    modalState.inputBuffer[1] = paletteName;
                    modalState.errorMessage = nil;
                    modalState.isOpen = true;
                    windowState.selectedPaletteName = paletteName;
                end
                if imgui.MenuItem('Copy To...') then
                    modalState.mode = 'copy';
                    modalState.inputBuffer[1] = paletteName;
                    modalState.errorMessage = nil;
                    modalState.copyTargetJobId = windowState.selectedJobId;
                    modalState.copyTargetSubjobId = windowState.selectedSubjobId;
                    modalState.isOpen = true;
                    windowState.selectedPaletteName = paletteName;
                end
                if #palettes > 1 then
                    imgui.Separator();
                    if imgui.MenuItem('Delete') then
                        modalState.mode = 'delete';
                        modalState.deletePaletteName = paletteName;
                        modalState.errorMessage = nil;
                        modalState.isOpen = true;
                        windowState.selectedPaletteName = paletteName;
                    end
                end
                imgui.EndPopup();
            end
        end
    end

    imgui.EndChild();

    return palettes;
end

-- Helper: Draw action buttons
local function DrawActionButtons(palettes)
    -- New palette button
    if imgui.Button('+ New') then
        modalState.mode = 'create';
        modalState.inputBuffer[1] = '';
        modalState.errorMessage = nil;
        modalState.isOpen = true;
    end

    imgui.SameLine();

    -- Rename button (enabled if palette selected)
    local hasSelection = windowState.selectedPaletteName ~= nil;
    if not hasSelection then imgui.BeginDisabled(); end
    if imgui.Button('Rename') then
        modalState.mode = 'rename';
        modalState.inputBuffer[1] = windowState.selectedPaletteName;
        modalState.errorMessage = nil;
        modalState.isOpen = true;
    end
    if not hasSelection then imgui.EndDisabled(); end

    imgui.SameLine();

    -- Delete button (enabled if palette selected and more than 1 palette)
    local canDelete = hasSelection and #palettes > 1;
    if not canDelete then imgui.BeginDisabled(); end
    if imgui.Button('Delete') then
        modalState.mode = 'delete';
        modalState.deletePaletteName = windowState.selectedPaletteName;
        modalState.errorMessage = nil;
        modalState.isOpen = true;
    end
    if not canDelete then imgui.EndDisabled(); end

    imgui.SameLine();

    -- Copy To button
    if not hasSelection then imgui.BeginDisabled(); end
    if imgui.Button('Copy To...') then
        modalState.mode = 'copy';
        modalState.inputBuffer[1] = windowState.selectedPaletteName;
        modalState.errorMessage = nil;
        modalState.copyTargetJobId = windowState.selectedJobId;
        modalState.copyTargetSubjobId = windowState.selectedSubjobId;
        modalState.isOpen = true;
    end
    if not hasSelection then imgui.EndDisabled(); end

    -- Reorder buttons on next line
    imgui.Spacing();

    if not hasSelection then imgui.BeginDisabled(); end
    if imgui.Button('Move Up') then
        local success, err;
        if windowState.selectedPaletteType == 'hotbar' then
            success, err = palette.MovePalette(1, windowState.selectedPaletteName, -1, windowState.selectedJobId, windowState.selectedSubjobId);
        else
            success, err = palette.MoveCrossbarPalette(windowState.selectedPaletteName, -1, windowState.selectedJobId, windowState.selectedSubjobId);
        end
        if not success and err then
            SetStatusMessage(err);
        end
    end
    imgui.SameLine();
    if imgui.Button('Move Down') then
        local success, err;
        if windowState.selectedPaletteType == 'hotbar' then
            success, err = palette.MovePalette(1, windowState.selectedPaletteName, 1, windowState.selectedJobId, windowState.selectedSubjobId);
        else
            success, err = palette.MoveCrossbarPalette(windowState.selectedPaletteName, 1, windowState.selectedJobId, windowState.selectedSubjobId);
        end
        if not success and err then
            SetStatusMessage(err);
        end
    end
    if not hasSelection then imgui.EndDisabled(); end

    -- Show status message (auto-clears after 3 seconds)
    if windowState.statusMessage then
        if os.clock() - windowState.statusMessageTime < 3 then
            imgui.TextColored({1.0, 0.6, 0.3, 1.0}, windowState.statusMessage);
        else
            windowState.statusMessage = nil;
        end
    end

    -- "Use Shared Library" button (only when viewing subjob-specific palettes)
    local usingFallback = IsUsingFallback(windowState.selectedJobId, windowState.selectedSubjobId, windowState.selectedPaletteType);
    if windowState.selectedSubjobId ~= 0 and not usingFallback then
        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();
        imgui.TextColored({0.6, 0.6, 0.6, 1.0}, 'Subjob-specific palettes override Shared Library.');
        if imgui.Button('Use Shared Library') then
            modalState.mode = 'use_shared';
            modalState.isOpen = true;
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Delete all subjob-specific palettes and use the Shared Library instead.');
        end
    end
end

-- Helper: Draw create/rename modal
local function DrawCreateRenameModal()
    if not modalState.isOpen or (modalState.mode ~= 'create' and modalState.mode ~= 'rename') then
        return;
    end

    local title = modalState.mode == 'create' and 'Create New Palette' or 'Rename Palette';
    imgui.OpenPopup(title .. '##paletteModal');

    if imgui.BeginPopupModal(title .. '##paletteModal', nil, ImGuiWindowFlags_AlwaysAutoResize) then
        -- Warning when creating will break away from shared palettes
        if modalState.mode == 'create' and windowState.selectedSubjobId ~= 0 then
            local usingFallback = IsUsingFallback(windowState.selectedJobId, windowState.selectedSubjobId, windowState.selectedPaletteType);
            if usingFallback then
                imgui.TextColored({1.0, 0.7, 0.3, 1.0}, 'Warning: Creating this palette will stop');
                imgui.TextColored({1.0, 0.7, 0.3, 1.0}, 'using shared palettes for ' .. GetJobName(windowState.selectedJobId) .. '/' .. GetJobName(windowState.selectedSubjobId) .. '.');
                imgui.Spacing();
            end
        end

        imgui.Text('Palette Name:');
        imgui.PushItemWidth(200);
        local enterPressed = imgui.InputText('##paletteName', modalState.inputBuffer, 32, ImGuiInputTextFlags_EnterReturnsTrue);
        imgui.PopItemWidth();

        -- Show error if any
        if modalState.errorMessage then
            imgui.TextColored({1.0, 0.3, 0.3, 1.0}, modalState.errorMessage);
        end

        imgui.Spacing();

        -- Buttons
        local newName = modalState.inputBuffer[1];
        local canSubmit = newName and newName ~= '';

        if imgui.Button('OK', { 80, 0 }) or enterPressed then
            if canSubmit then
                local success, err;
                if modalState.mode == 'create' then
                    if windowState.selectedPaletteType == 'hotbar' then
                        success, err = palette.CreatePalette(1, newName, windowState.selectedJobId, windowState.selectedSubjobId);
                    else
                        success, err = palette.CreateCrossbarPalette(newName, windowState.selectedJobId, windowState.selectedSubjobId);
                    end
                else  -- rename
                    if windowState.selectedPaletteType == 'hotbar' then
                        success, err = palette.RenamePalette(1, windowState.selectedPaletteName, newName, windowState.selectedJobId, windowState.selectedSubjobId);
                    else
                        success, err = palette.RenameCrossbarPalette(windowState.selectedPaletteName, newName, windowState.selectedJobId, windowState.selectedSubjobId);
                    end
                end

                if success then
                    windowState.selectedPaletteName = newName;

                    -- Activate the newly created palette if viewing current job's palettes
                    if modalState.mode == 'create' then
                        local currentJobId = data.jobId;
                        local currentSubjobId = data.subjobId or 0;
                        local viewingShared = (windowState.selectedSubjobId == 0);
                        local viewingCurrentJob = (windowState.selectedJobId == currentJobId);
                        local viewingCurrentSubjob = (windowState.selectedSubjobId == currentSubjobId);

                        -- Activate if: viewing this job's shared library OR viewing exact job/subjob match
                        if viewingCurrentJob and (viewingShared or viewingCurrentSubjob) then
                            if windowState.selectedPaletteType == 'hotbar' then
                                palette.SetActivePalette(1, newName, currentJobId, currentSubjobId);
                            else
                                palette.SetActivePaletteForCombo('L2', newName);
                            end
                        end
                    end

                    modalState.isOpen = false;
                    imgui.CloseCurrentPopup();
                else
                    modalState.errorMessage = err or 'Operation failed';
                end
            end
        end

        imgui.SameLine();

        if imgui.Button('Cancel', { 80, 0 }) then
            modalState.isOpen = false;
            imgui.CloseCurrentPopup();
        end

        imgui.EndPopup();
    end
end

-- Helper: Draw copy modal
local function DrawCopyModal()
    if not modalState.isOpen or modalState.mode ~= 'copy' then
        return;
    end

    imgui.OpenPopup('Copy Palette##copyModal');

    if imgui.BeginPopupModal('Copy Palette##copyModal', nil, ImGuiWindowFlags_AlwaysAutoResize) then
        imgui.Text('Copy "' .. windowState.selectedPaletteName .. '" to:');
        imgui.Spacing();

        -- Job selector
        imgui.Text('Job:');
        imgui.SameLine();
        imgui.PushItemWidth(100);
        if imgui.BeginCombo('##copyJobSelector', GetJobName(modalState.copyTargetJobId)) then
            for jobId = 1, 22 do
                local isSelected = (jobId == modalState.copyTargetJobId);
                if imgui.Selectable(GetJobName(jobId), isSelected) then
                    modalState.copyTargetJobId = jobId;
                end
                if isSelected then
                    imgui.SetItemDefaultFocus();
                end
            end
            imgui.EndCombo();
        end
        imgui.PopItemWidth();

        -- Subjob selector
        imgui.SameLine();
        imgui.Text('Subjob:');
        imgui.SameLine();
        imgui.PushItemWidth(100);
        local currentSubjobLabel = modalState.copyTargetSubjobId == 0 and 'Shared' or GetJobName(modalState.copyTargetSubjobId);
        if imgui.BeginCombo('##copySubjobSelector', currentSubjobLabel) then
            -- Shared option
            local sharedSelected = (modalState.copyTargetSubjobId == 0);
            if imgui.Selectable('Shared', sharedSelected) then
                modalState.copyTargetSubjobId = 0;
            end
            if sharedSelected then
                imgui.SetItemDefaultFocus();
            end
            -- Job options
            for subjobId = 1, 22 do
                local isSelected = (subjobId == modalState.copyTargetSubjobId);
                if imgui.Selectable(GetJobName(subjobId), isSelected) then
                    modalState.copyTargetSubjobId = subjobId;
                end
                if isSelected then
                    imgui.SetItemDefaultFocus();
                end
            end
            imgui.EndCombo();
        end
        imgui.PopItemWidth();

        imgui.Spacing();

        -- Warning when copying to a subjob-specific location that currently uses shared palettes
        if modalState.copyTargetSubjobId ~= 0 then
            local targetUsingFallback = IsUsingFallback(modalState.copyTargetJobId, modalState.copyTargetSubjobId, windowState.selectedPaletteType);
            if targetUsingFallback then
                imgui.TextColored({1.0, 0.7, 0.3, 1.0}, 'Warning: This will stop using shared palettes for');
                imgui.TextColored({1.0, 0.7, 0.3, 1.0}, GetJobName(modalState.copyTargetJobId) .. '/' .. GetJobName(modalState.copyTargetSubjobId) .. '.');
                imgui.Spacing();
            end
        end

        -- New name input
        imgui.Text('New Name (leave blank to keep same):');
        imgui.PushItemWidth(200);
        imgui.InputText('##copyNewName', modalState.inputBuffer, 32);
        imgui.PopItemWidth();

        -- Show error if any
        if modalState.errorMessage then
            imgui.TextColored({1.0, 0.3, 0.3, 1.0}, modalState.errorMessage);
        end

        imgui.Spacing();

        -- Check if copying to same location with same name
        local newName = modalState.inputBuffer[1];
        if newName == '' then newName = nil; end
        local effectiveName = newName or windowState.selectedPaletteName;
        local isSameLocation = modalState.copyTargetJobId == windowState.selectedJobId and
                               modalState.copyTargetSubjobId == windowState.selectedSubjobId and
                               effectiveName == windowState.selectedPaletteName;

        -- Buttons
        if isSameLocation then imgui.BeginDisabled(); end
        if imgui.Button('Copy', { 80, 0 }) then
            local success, err;
            if windowState.selectedPaletteType == 'hotbar' then
                success, err = palette.CopyPalette(
                    windowState.selectedPaletteName,
                    windowState.selectedJobId,
                    windowState.selectedSubjobId,
                    modalState.copyTargetJobId,
                    modalState.copyTargetSubjobId,
                    newName
                );
            else
                success, err = palette.CopyCrossbarPalette(
                    windowState.selectedPaletteName,
                    windowState.selectedJobId,
                    windowState.selectedSubjobId,
                    modalState.copyTargetJobId,
                    modalState.copyTargetSubjobId,
                    newName
                );
            end

            if success then
                modalState.isOpen = false;
                imgui.CloseCurrentPopup();
            else
                modalState.errorMessage = err or 'Copy failed';
            end
        end
        if isSameLocation then imgui.EndDisabled(); end

        imgui.SameLine();

        if imgui.Button('Cancel', { 80, 0 }) then
            modalState.isOpen = false;
            imgui.CloseCurrentPopup();
        end

        imgui.EndPopup();
    end
end

-- Helper: Draw delete confirmation modal
local function DrawDeleteConfirmModal()
    if not modalState.isOpen or modalState.mode ~= 'delete' then
        return;
    end

    imgui.OpenPopup('Delete Palette##deleteModal');

    if imgui.BeginPopupModal('Delete Palette##deleteModal', nil, ImGuiWindowFlags_AlwaysAutoResize) then
        imgui.Text('Are you sure you want to delete');
        imgui.Text('"' .. (modalState.deletePaletteName or '') .. '"?');
        imgui.Spacing();
        imgui.TextColored({0.7, 0.7, 0.7, 1.0}, 'This action cannot be undone.');
        imgui.Spacing();

        -- Show error if any
        if modalState.errorMessage then
            imgui.TextColored({1.0, 0.3, 0.3, 1.0}, modalState.errorMessage);
        end

        imgui.Spacing();

        -- Buttons
        if imgui.Button('Delete', { 80, 0 }) then
            local success, err;
            if windowState.selectedPaletteType == 'hotbar' then
                success, err = palette.DeletePalette(1, modalState.deletePaletteName, windowState.selectedJobId, windowState.selectedSubjobId);
            else
                success, err = palette.DeleteCrossbarPalette(modalState.deletePaletteName, windowState.selectedJobId, windowState.selectedSubjobId);
            end
            if success then
                windowState.selectedPaletteName = nil;
                modalState.isOpen = false;
                imgui.CloseCurrentPopup();
            else
                modalState.errorMessage = err or 'Delete failed';
            end
        end

        imgui.SameLine();

        if imgui.Button('Cancel', { 80, 0 }) then
            modalState.isOpen = false;
            imgui.CloseCurrentPopup();
        end

        imgui.EndPopup();
    end
end

-- Helper: Draw "Use Shared Library" confirmation modal
local function DrawUseSharedModal()
    if not modalState.isOpen or modalState.mode ~= 'use_shared' then
        return;
    end

    imgui.OpenPopup('Use Shared Library##useSharedModal');

    if imgui.BeginPopupModal('Use Shared Library##useSharedModal', nil, ImGuiWindowFlags_AlwaysAutoResize) then
        local jobName = GetJobName(windowState.selectedJobId);
        local subjobName = GetJobName(windowState.selectedSubjobId);

        imgui.TextColored({1.0, 0.7, 0.3, 1.0}, 'Warning: This will delete all subjob-specific palettes!');
        imgui.Spacing();
        imgui.Text(string.format('This will delete all %s palettes for %s/%s', windowState.selectedPaletteType, jobName, subjobName));
        imgui.Text('and revert to using the Shared Library.');
        imgui.Spacing();
        imgui.TextColored({0.5, 0.5, 0.5, 1.0}, 'This cannot be undone.');
        imgui.Spacing();

        -- Show error if any
        if modalState.errorMessage then
            imgui.TextColored({1.0, 0.3, 0.3, 1.0}, modalState.errorMessage);
        end

        if imgui.Button('Delete & Use Shared', {150, 0}) then
            local success;
            if windowState.selectedPaletteType == 'hotbar' then
                success = palette.DeleteAllSubjobPalettes(windowState.selectedJobId, windowState.selectedSubjobId);
            else
                success = palette.DeleteAllCrossbarSubjobPalettes(windowState.selectedJobId, windowState.selectedSubjobId);
            end
            if success then
                SetStatusMessage('Now using Shared Library');
                windowState.selectedPaletteName = nil;
                modalState.isOpen = false;
                imgui.CloseCurrentPopup();
            else
                modalState.errorMessage = 'Failed to delete palettes';
            end
        end
        imgui.SameLine();
        if imgui.Button('Cancel', {80, 0}) then
            modalState.isOpen = false;
            imgui.CloseCurrentPopup();
        end
        imgui.EndPopup();
    end
end

-- Draw the main palette manager window
function M.Draw()
    if not windowState.isOpen then
        return;
    end

    -- Window size
    imgui.SetNextWindowSize({ 350, 400 }, ImGuiCond_FirstUseEver);

    local windowFlags = ImGuiWindowFlags_None;
    local isOpen = { windowState.isOpen };

    if imgui.Begin('Palette Manager##paletteManager', isOpen, windowFlags) then
        -- Type selector
        DrawPaletteTypeSelector();
        imgui.Spacing();

        -- Job/Subjob selectors
        DrawJobSelector();
        DrawSubjobSelector();
        imgui.Spacing();

        -- Palette list
        local palettes = DrawPaletteList();
        imgui.Spacing();

        -- Action buttons
        DrawActionButtons(palettes);

        -- Draw modals
        DrawCreateRenameModal();
        DrawCopyModal();
        DrawDeleteConfirmModal();
        DrawUseSharedModal();
    end
    imgui.End();

    windowState.isOpen = isOpen[1];
end

return M;
