--[[
* XIUI Config - Crossbar settings (sidebar Crossbar category only)
* Sibling to keyboard hotbar settings in config/hotbar.lua - not mixed at edit time.
]]--

require('common');
require('handlers.helpers');
local ffi = require('ffi');
local TextureManager = require('libs.texturemanager');
local components = require('config.components');
local imgui = require('imgui');
local data = require('modules.hotbar.data');
local jobs = require('libs.jobs');
local macropalette = require('modules.hotbar.macropalette');
local palette = require('modules.hotbar.palette');
local paletteManager = require('config.palettemanager');
local controller = require('modules.hotbar.controller');

local hotbarConfig = require('config.hotbar');

local M = {};

local lastConfigCategorySeenForCrossbar = nil;

-- Crossbar config UI: default to Controller Settings (tab 1) each addon load until user picks another sub-tab this session
local crossbarConfigSubTabUserChosen = false;

-- Global Visual Settings (tab 3): collapse sections when switching to this tab unless the user expanded them this session
local CROSSBAR_GLOBAL_VIS_KEYS = { 'palCtrl', 'slot', 'bg', 'text', 'vfb' };
local crossbarGlobalVis_prevUit = nil;
local crossbarGlobalVis_openedSections = {};
local crossbarGlobalVis_sectionNonce = {};

local function CrossbarGlobalVisualCollapsingSection(sectionKey, label, defaultOpen)
    local nonce = crossbarGlobalVis_sectionNonce[sectionKey] or 0;
    local fullLabel = string.format('%s##xbGlobalVis_%s_%d', label, sectionKey, nonce);
    if defaultOpen == nil then defaultOpen = false; end
    imgui.Spacing();
    local flags = defaultOpen and ImGuiTreeNodeFlags_DefaultOpen or 0;
    local isOpen = imgui.CollapsingHeader(fullLabel, flags);
    if imgui.IsItemClicked() then
        crossbarGlobalVis_openedSections[sectionKey] = true;
    end
    if isOpen then
        imgui.Spacing();
    end
    return isOpen;
end

local function ResolveCrossbarPaletteJobIconTheme(cs)
    local t = cs and cs.paletteJobIconTheme;
    if t == 'Classic' or t == 'FFXI' or t == 'FFXIV-1' then
        return t;
    end
    return 'Classic';
end
local buttonDetectionState = {
    active = false,
    progress = 0,
};
-- ============================================
-- Crossbar Global Palettes UI Section
-- ============================================

-- Global crossbar palette error state
local crossbarGlobalPaletteErrorMessage = nil;

-- Enable Global crossbar sets + optional scope + default palette type (only when Global sets enabled)
local function DrawCrossbarUniversalTierOptions(crossbarSettings, opts)
    opts = opts or {};
    if opts.showEnableCheckbox ~= false then
        local uEn = { crossbarSettings.enableUniversalCrossbarPalettes == true };
        if imgui.Checkbox('Enable "Global" Crossbar Sets##xcuEn', uEn) then
            crossbarSettings.enableUniversalCrossbarPalettes = uEn[1];
            if uEn[1] then
                palette.EnsureUniversalCrossbarDefaultExists();
            end
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Crossbar palettes shared by every job, labeled [G] in lists. Hold L1 and tap R1 in-game to switch between Global [G] storage and Job/Subjob [J] storage for the crossbar.\nWhen Global sets are off, only [J] job/subjob palettes are used.');
    end

    if not crossbarSettings.enableUniversalCrossbarPalettes then
        return;
    end

    if opts.includeScopeLine ~= false then
        local scope = palette.GetCrossbarPaletteScope();
        imgui.TextColored({0.7, 0.75, 1.0, 1.0}, 'Scope: ' .. (scope == 'universal' and 'Global [G]' or 'Job / Subjob [J]'));
        imgui.Spacing();
    end

    if not crossbarSettings.defaultCrossbarPaletteScope then
        crossbarSettings.defaultCrossbarPaletteScope = 'job';
    end
    imgui.AlignTextToFramePadding();
    imgui.Text('Default Palette Type on Profile Load:');
    imgui.SameLine();
    imgui.SetNextItemWidth(160);
    local defLabel = crossbarSettings.defaultCrossbarPaletteScope == 'universal' and 'Global [G]' or 'Job / Subjob [J]';
    if imgui.BeginCombo('##xcuDefScope', defLabel) then
        if imgui.Selectable('Job / Subjob [J]', crossbarSettings.defaultCrossbarPaletteScope ~= 'universal') then
            crossbarSettings.defaultCrossbarPaletteScope = 'job';
            SaveSettingsOnly();
        end
        if imgui.Selectable('Global [G]', crossbarSettings.defaultCrossbarPaletteScope == 'universal') then
            crossbarSettings.defaultCrossbarPaletteScope = 'universal';
            SaveSettingsOnly();
        end
        imgui.EndCombo();
    end
    imgui.ShowHelp('Which Job vs Global [G] palette tier is applied when a profile is loaded or reloaded from disk. While playing, use L1+R1 to switch tier without changing this setting.');
end

-- Draw the global crossbar palettes management section
-- opts.showEnableCheckbox (default true): show Enable "Global" Crossbar Sets (also on Controller tab)
-- opts.skipUniversalTierOptions: when true, toggles were drawn elsewhere (e.g. Manage strip)
-- opts.jobId / opts.subjobId: which job/subjob to edit for [J] palettes (config preview)
local function DrawCrossbarGlobalPalettesSection(opts)
    opts = opts or {};
    local crossbarSettings = gConfig.hotbarCrossbar;
    if not crossbarSettings then
        return;
    end

    if opts.skipUniversalTierOptions ~= true then
        DrawCrossbarUniversalTierOptions(crossbarSettings, {
            showEnableCheckbox = opts.showEnableCheckbox,
            includeScopeLine = opts.includeScopeLine ~= false,
        });
    end

    if crossbarSettings.enableUniversalCrossbarPalettes then
        if opts.includeUniversalLists ~= false then
        imgui.Spacing();
        if opts.embedCrossbarUniversalPaletteManager then
            palette.EnsureUniversalCrossbarDefaultExists();
            paletteManager.DrawEmbeddedCrossbarManageUniversal();
            imgui.Dummy({ 0, 4 });
            imgui.AlignTextToFramePadding();
            imgui.TextColored(components.TAB_STYLE.gold, 'Active palette');
            imgui.SameLine();
            imgui.ShowHelp('Active Global [G] palette when in-game scope is Global (toggle with L1+R1).');
            local uList = palette.GetUniversalCrossbarPaletteNamesOrdered();
            local uActive = palette.GetActiveUniversalCrossbarPalette();
            local availU = imgui.GetContentRegionAvail();
            local comboWU = math.max(220, ((type(availU) == 'table' and availU[1]) or availU or 400) * 0.5);
            imgui.SetNextItemWidth(comboWU);
            local comboLabelU = uActive or (#uList > 0 and uList[1]) or '(none)';
            if imgui.BeginCombo('##xbManageActivePalUniversal', comboLabelU) then
                for _, un in ipairs(uList) do
                    local labelU = un .. ' (G)';
                    local isSelU = (uActive == un);
                    if imgui.Selectable(labelU .. '##xbActUni', isSelU) then
                        palette.SetActiveUniversalCrossbarPalette(un);
                    end
                    if isSelU then
                        imgui.SetItemDefaultFocus();
                    end
                end
                imgui.EndCombo();
            end
        else
            imgui.TextColored(components.TAB_STYLE.gold, 'Global [G] palette list');
            local uList = palette.GetUniversalCrossbarPaletteNamesOrdered();
            local lineH = imgui.GetTextLineHeightWithSpacing();
            local globalScrollH = opts.compactGlobalPaletteScroll and (lineH * 4) or nil;
            if globalScrollH then
                imgui.BeginChild('##xcuGlobalPalScroll', { 0, globalScrollH }, true);
            end
            for _, un in ipairs(uList) do
                imgui.PushID('xcuRow' .. un);
                local inc = palette.GetUniversalPaletteIncludeInCycle(un);
                local incBuf = { inc };
                if imgui.Checkbox('Cycle##xcuCyc', incBuf) then
                    palette.SetUniversalPaletteIncludeInCycle(un, incBuf[1]);
                end
                imgui.SameLine();
                imgui.TextColored({0.85, 0.85, 0.5, 1.0}, '[G]');
                imgui.SameLine();
                imgui.Text(un);
                imgui.PopID();
            end
            if globalScrollH then
                imgui.EndChild();
            end

            imgui.Spacing();
            imgui.PushStyleColor(ImGuiCol_Button, {0.15, 0.35, 0.2, 1.0});
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0.25, 0.45, 0.3, 1.0});
            if imgui.Button('New Global palette##xcuNew', {140, 0}) then
                hotbarConfig.OpenPaletteCreateModal('crossbar_universal');
            end
            imgui.PopStyleColor(2);

            local uActive = palette.GetActiveUniversalCrossbarPalette();
            if #uList > 0 then
                imgui.SameLine();
                imgui.SetNextItemWidth(180);
                local comboLabel = uActive or uList[1];
                if imgui.BeginCombo('##xcuActive', comboLabel) then
                    for _, un in ipairs(uList) do
                        if imgui.Selectable(un .. '##xcuSel' .. un, un == uActive) then
                            palette.SetActiveUniversalCrossbarPalette(un);
                        end
                    end
                    imgui.EndCombo();
                end
                imgui.ShowHelp('Active Global [G] palette when in-game scope is Global (toggle with L1+R1).');
            end
        end

        imgui.Separator();
        imgui.Spacing();
        end
    end

    if opts.includeJobPalettes == false then
        if crossbarGlobalPaletteErrorMessage then
            imgui.TextColored({1.0, 0.4, 0.4, 1.0}, crossbarGlobalPaletteErrorMessage);
        end
        imgui.Spacing();
        return;
    end

    local jobId = opts.jobId or data.jobId or 1;
    local subjobId = opts.subjobId ~= nil and opts.subjobId or (data.subjobId or 0);

    -- Embedded full Palette Manager (Manage tab): Job (J) + Subjob (SJ) tiers
    if opts.embedCrossbarJobPaletteManager then
        palette.EnsureCrossbarDefaultPaletteExists(jobId, subjobId);
        paletteManager.DrawEmbeddedCrossbarManage(jobId, subjobId);
        imgui.Dummy({ 0, 4 });
        imgui.AlignTextToFramePadding();
        imgui.TextColored(components.TAB_STYLE.gold, 'Active palette');
        imgui.SameLine();
        imgui.ShowHelp('Matches in-game crossbar scope: Global [G] shows universal palettes; Job [J]/[SJ] shows palettes for this job/subjob. (J) = job-wide; (SJ) = this job+subjob tier.');
        local mergedRows = palette.GetCrossbarManagePaletteRows(jobId, subjobId);
        local activeName = palette.GetActivePaletteForCombo('L2');
        local activeSt = palette.GetCrossbarActiveStorageSubjob();
        local scopeUniversal = palette.GetCrossbarPaletteScope() == 'universal';
        local comboLabel = '(none)';
        if scopeUniversal then
            local uName = palette.GetActiveUniversalCrossbarPalette() or activeName;
            if uName and uName ~= '' then
                comboLabel = uName .. ' (G)';
            end
        else
            for _, r in ipairs(mergedRows) do
                if r.name == activeName and (activeSt == nil or activeSt == r.storageSubjob) then
                    comboLabel = r.name .. palette.FormatCrossbarTierSuffixLabel(r.storageSubjob, subjobId);
                    break;
                end
            end
            if activeName and comboLabel == '(none)' then
                comboLabel = activeName;
            end
        end
        local avail = imgui.GetContentRegionAvail();
        local comboW = math.max(220, ((type(avail) == 'table' and avail[1]) or avail or 400) * 0.5);
        imgui.SetNextItemWidth(comboW);
        if imgui.BeginCombo('##xbManageActivePal', comboLabel) then
            if scopeUniversal then
                local uList = palette.GetUniversalCrossbarPaletteNamesOrdered();
                local uActive = palette.GetActiveUniversalCrossbarPalette();
                for _, un in ipairs(uList) do
                    local label = un .. ' (G)';
                    local isSel = (uActive == un);
                    if imgui.Selectable(label .. '##xbActU', isSel) then
                        palette.SetActiveUniversalCrossbarPalette(un);
                    end
                    if isSel then
                        imgui.SetItemDefaultFocus();
                    end
                end
            else
                for _, r in ipairs(mergedRows) do
                    local label = r.name .. palette.FormatCrossbarTierSuffixLabel(r.storageSubjob, subjobId);
                    local isSel = (r.name == activeName and (activeSt == nil or activeSt == r.storageSubjob));
                    if imgui.Selectable(label .. '##xbActPal', isSel) then
                        palette.SetActivePaletteForCombo('L2', r.name, r.storageSubjob);
                    end
                    if isSel then
                        imgui.SetItemDefaultFocus();
                    end
                end
            end
            imgui.EndCombo();
        end
        if crossbarGlobalPaletteErrorMessage then
            imgui.TextColored({1.0, 0.4, 0.4, 1.0}, crossbarGlobalPaletteErrorMessage);
        end
        imgui.Spacing();
        return;
    end

    -- Ensure at least one palette exists for this job
    palette.EnsureCrossbarDefaultPaletteExists(jobId, subjobId);
    local mergedRows = palette.GetCrossbarManagePaletteRows(jobId, subjobId);
    local cycleRows = palette.GetCrossbarManagePaletteRowsInRbCycle(jobId, subjobId);
    local currentPalette = palette.GetActivePaletteForCombo('L2');
    local currentStorage = palette.GetCrossbarActiveStorageSubjob();

    local paletteCount = #cycleRows;
    local currentPaletteIndex = nil;
    for i, r in ipairs(cycleRows) do
        if r.name == currentPalette and (currentStorage == nil or currentStorage == r.storageSubjob) then
            currentPaletteIndex = i;
            break;
        end
    end
    local totalMergedCount = #mergedRows;

    if #mergedRows > 0 and not currentPalette then
        local pick = cycleRows[1] or mergedRows[1];
        palette.SetActivePaletteForCombo('L2', pick.name, pick.storageSubjob);
        currentPalette = pick.name;
        currentStorage = pick.storageSubjob;
        currentPaletteIndex = 1;
    end

    imgui.TextColored(components.TAB_STYLE.gold, 'Job / subjob crossbar palettes  [J]');
    components.PushPaletteManagerButtonStyle();
    if imgui.SmallButton('Manage Palettes##crossbar') then
        local xiuiConfig = require('config');
        xiuiConfig.OpenCrossbarManagePalettes();
    end
    components.PopPaletteManagerButtonStyle();
    imgui.Spacing();

    -- Header with count
    imgui.TextColored({0.8, 0.8, 0.8, 1.0}, 'Palettes:');
    imgui.SameLine();
    imgui.TextColored({0.5, 1.0, 0.5, 1.0}, tostring(paletteCount) .. ' in cycle');
    imgui.ShowHelp('Create named palettes to quickly switch between crossbar configurations.\nPalettes are GLOBAL - switching changes all combo modes (L2, R2, L2+R2, etc.) at once.\n"Inactive" in Palette Manager is excluded from RB+D-pad cycling and from this count.');

    local currentDisplayName = currentPalette or 'Select palette';
    if currentPalette and currentPaletteIndex then
        local r = nil;
        for _, row in ipairs(cycleRows) do
            if row.name == currentPalette and (currentStorage == nil or currentStorage == row.storageSubjob) then
                r = row;
                break;
            end
        end
        local suf = r and palette.FormatCrossbarTierSuffixLabel(r.storageSubjob, subjobId) or '';
        currentDisplayName = currentPaletteIndex .. '. ' .. currentPalette .. suf;
    elseif currentPalette then
        local suf = '';
        for _, r in ipairs(mergedRows) do
            if r.name == currentPalette and (currentStorage == nil or currentStorage == r.storageSubjob) then
                suf = palette.FormatCrossbarTierSuffixLabel(r.storageSubjob, subjobId);
                break;
            end
        end
        currentDisplayName = currentPalette .. suf .. ' (inactive)';
    end

    imgui.SetNextItemWidth(150);
    if imgui.BeginCombo('##crossbarGlobalPalette', currentDisplayName) then
        local cycleIdxByKey = {};
        for i, r in ipairs(cycleRows) do
            cycleIdxByKey[r.name .. '\0' .. tostring(r.storageSubjob)] = i;
        end
        for i, r in ipairs(mergedRows) do
            local suf = palette.FormatCrossbarTierSuffixLabel(r.storageSubjob, subjobId);
            local isSelected = (r.name == currentPalette and (currentStorage == nil or currentStorage == r.storageSubjob));
            local cycIdx = cycleIdxByKey[r.name .. '\0' .. tostring(r.storageSubjob)];
            local displayName = (cycIdx and (cycIdx .. '. ') or '– ') .. r.name .. suf;
            if imgui.Selectable(displayName .. '##cbGlobalPal' .. i, isSelected) then
                palette.SetActivePaletteForCombo('L2', r.name, r.storageSubjob);
            end
            if isSelected then
                imgui.SetItemDefaultFocus();
            end
        end
        imgui.EndCombo();
    end

    -- Rename button (for any palette)
    if currentPalette then
        imgui.SameLine();
        if imgui.Button('Rename##cbGlobalPalette', {55, 0}) then
            hotbarConfig.OpenPaletteRenameModal('crossbar', currentPalette);
        end
    end

    -- New button (always visible, green)
    imgui.SameLine();
    imgui.PushStyleColor(ImGuiCol_Button, {0.2, 0.5, 0.2, 1.0});
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0.3, 0.6, 0.3, 1.0});
    if imgui.Button('New##cbGlobalPalette', {40, 0}) then
        hotbarConfig.OpenPaletteCreateModal('crossbar');
    end
    imgui.PopStyleColor(2);

    -- Delete button (only if more than 1 palette exists - can't delete the last one)
    if currentPalette and totalMergedCount > 1 then
        imgui.SameLine();
        imgui.PushStyleColor(ImGuiCol_Button, {0.6, 0.2, 0.2, 1.0});
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0.8, 0.3, 0.3, 1.0});
        if imgui.Button('Delete##cbGlobalPalette', {50, 0}) then
            local delTier = currentStorage or 0;
            local success, err = palette.DeleteCrossbarPalette(currentPalette, jobId, delTier);
            if not success then
                crossbarGlobalPaletteErrorMessage = err or 'Failed to delete palette';
            else
                crossbarGlobalPaletteErrorMessage = nil;
            end
        end
        imgui.PopStyleColor(2);
    end

    -- Reorder within the same storage tier (Job [J] vs Subjob [SJ])
    if currentPalette and totalMergedCount > 1 then
        imgui.SameLine();
        imgui.TextColored({0.5, 0.5, 0.5, 1.0}, '|');
        imgui.SameLine();

        local moveTier = currentStorage or 0;
        local tierNames = {};
        for _, r in ipairs(mergedRows) do
            if r.storageSubjob == moveTier then
                table.insert(tierNames, r.name);
            end
        end
        local idxInTier = nil;
        for ti, n in ipairs(tierNames) do
            if n == currentPalette then
                idxInTier = ti;
                break;
            end
        end
        local canMoveUp = idxInTier and idxInTier > 1;
        local canMoveDown = idxInTier and idxInTier < #tierNames;

        if not canMoveUp then
            imgui.PushStyleColor(ImGuiCol_Button, {0.2, 0.2, 0.2, 0.5});
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0.2, 0.2, 0.2, 0.5});
            imgui.PushStyleColor(ImGuiCol_Text, {0.4, 0.4, 0.4, 1.0});
        end
        if imgui.Button('^##cbGlobalPaletteUp', {20, 0}) and canMoveUp then
            palette.MoveCrossbarPalette(currentPalette, -1, jobId, moveTier);
        end
        if not canMoveUp then
            imgui.PopStyleColor(3);
        end

        imgui.SameLine();

        if not canMoveDown then
            imgui.PushStyleColor(ImGuiCol_Button, {0.2, 0.2, 0.2, 0.5});
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0.2, 0.2, 0.2, 0.5});
            imgui.PushStyleColor(ImGuiCol_Text, {0.4, 0.4, 0.4, 1.0});
        end
        if imgui.Button('v##cbGlobalPaletteDown', {20, 0}) and canMoveDown then
            palette.MoveCrossbarPalette(currentPalette, 1, jobId, moveTier);
        end
        if not canMoveDown then
            imgui.PopStyleColor(3);
        end
    end

    -- Show error message (for delete failures)
    if crossbarGlobalPaletteErrorMessage then
        imgui.TextColored({1.0, 0.4, 0.4, 1.0}, crossbarGlobalPaletteErrorMessage);
    end

    imgui.Spacing();
end

local function SyncCrossbarPaletteEditContextFromLiveJob(crossbarSettings)
    if not crossbarSettings or crossbarSettings.configFocus ~= 'job' then
        return;
    end
    data.SetPlayerJob();
    local j = data.jobId;
    if not j or j < 1 then
        return;
    end
    crossbarSettings.configEditJobId = j;
    crossbarSettings.configEditSubjobId = data.subjobId or 0;
    SaveSettingsOnly();
end

-- When entering the Crossbar sidebar category, align palette edit job/subjob with the live character
local function MaybeSyncCrossbarEditContextOnCategoryEnter(crossbarSettings, menuState)
    local crossIdx = menuState and menuState.crossbarCategoryIndex;
    if not crossIdx then
        return;
    end
    local cat = menuState.selectedCategory;
    if cat == crossIdx then
        if lastConfigCategorySeenForCrossbar ~= crossIdx then
            SyncCrossbarPaletteEditContextFromLiveJob(crossbarSettings);
        end
        lastConfigCategorySeenForCrossbar = crossIdx;
    else
        lastConfigCategorySeenForCrossbar = cat;
    end
end

local function GetSubjobMenuLabel(subjobId)
    if subjobId == nil or subjobId == 0 then
        return 'Shared';
    end
    return jobs[subjobId] or ('Job ' .. tostring(subjobId));
end

local function DrawCrossbarJobIconStrip(crossbarSettings, stripOpts)
    stripOpts = stripOpts or {};
    if not crossbarSettings.configFocus then
        crossbarSettings.configFocus = 'job';
    end
    data.SetPlayerJob();
    if crossbarSettings.configFocus == 'job' then
        if crossbarSettings.configEditJobId == nil then
            local j = data.jobId;
            if j and j > 0 then
                crossbarSettings.configEditJobId = j;
            else
                crossbarSettings.configEditJobId = 1;
            end
        end
        if crossbarSettings.configEditSubjobId == nil then
            crossbarSettings.configEditSubjobId = data.subjobId or 0;
        end
    end

    -- Global [G] requires "Enable Global Crossbar Sets"; otherwise fall back to job context
    if crossbarSettings.enableUniversalCrossbarPalettes ~= true and crossbarSettings.configFocus == 'universal' then
        crossbarSettings.configFocus = 'job';
        if crossbarSettings.configEditJobId == nil then
            local j = data.jobId;
            if j and j > 0 then
                crossbarSettings.configEditJobId = j;
            else
                crossbarSettings.configEditJobId = 1;
            end
        end
        if crossbarSettings.configEditSubjobId == nil then
            crossbarSettings.configEditSubjobId = data.subjobId or 0;
        end
        SaveSettingsOnly();
    end

    imgui.TextColored(components.TAB_STYLE.gold, 'Palette edit context');
    imgui.ShowHelp('Global [G] edits crossbar palettes shared by every job. A job icon selects that job’s [J] palettes here (separate from your live character; bindings follow your current job in-game).');
    imgui.Spacing();

    local iconSize = 34;
    local pad = 3;

    local function drawIconButton(id, tex, tip, selected, disabled, disabledTip)
        disabled = disabled == true;
        local showSel = selected and not disabled;
        local pos = { imgui.GetCursorScreenPos() };
        local clicked = false;
        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 0, 0 });
        if showSel then
            imgui.PushStyleColor(ImGuiCol_Button, {0.12, 0.11, 0.1, 1.0});
            imgui.PushStyleColor(ImGuiCol_Border, {1.0, 1.0, 1.0, 1.0});
            imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 2);
        elseif disabled then
            imgui.PushStyleColor(ImGuiCol_Button, {0.10, 0.09, 0.08, 0.72});
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0.11, 0.10, 0.09, 0.82});
            imgui.PushStyleColor(ImGuiCol_ButtonActive, {0.11, 0.10, 0.09, 0.82});
        else
            imgui.PushStyleColor(ImGuiCol_Button, {0.18, 0.16, 0.14, 1.0});
        end
        if imgui.Button(id, { iconSize, iconSize }) then
            if not disabled then
                clicked = true;
            end
        end
        if showSel then
            imgui.PopStyleVar(1);
            imgui.PopStyleColor(2);
        elseif disabled then
            imgui.PopStyleColor(3);
        else
            imgui.PopStyleColor(1);
        end
        imgui.PopStyleVar(1);
        local dl = imgui.GetWindowDrawList();
        if tex and tex.image and dl then
            local p = tonumber(ffi.cast('uint32_t', tex.image));
            if p then
                local imgTint = disabled
                    and imgui.GetColorU32({ 0.38, 0.10, 0.10, 0.88 })
                    or imgui.GetColorU32({ 1, 1, 1, 1 });
                dl:AddImage(
                    p,
                    { pos[1] + pad, pos[2] + pad },
                    { pos[1] + iconSize - pad, pos[2] + iconSize - pad },
                    { 0, 0 },
                    { 1, 1 },
                    imgTint
                );
            end
        end
        if showSel and dl then
            local rMin = { imgui.GetItemRectMin() };
            local rMax = { imgui.GetItemRectMax() };
            dl:AddRect(rMin, rMax, 0xFFFFFFFF, 0, 0, 2.0);
        end
        local hoverTip = disabled and disabledTip or tip;
        if hoverTip and imgui.IsItemHovered() then
            imgui.BeginTooltip();
            imgui.Text(hoverTip);
            imgui.EndTooltip();
        end
        return clicked;
    end

    local infTex = TextureManager.getFileTexture('jobs/FFXIV-1/infinite');
    if not infTex or not infTex.image then
        infTex = TextureManager.getFileTexture('jobs/Classic/infinite');
    end
    local globalSetsEnabled = crossbarSettings.enableUniversalCrossbarPalettes == true;
    local selG = crossbarSettings.configFocus == 'universal';
    imgui.BeginGroup();
    if drawIconButton(
        '##xbJobInf',
        infTex,
        'Global [G] crossbar sets',
        selG,
        not globalSetsEnabled,
        'Global Crossbar Sets must be enabled under Controller Settings.'
    ) then
        crossbarSettings.configFocus = 'universal';
        crossbarSettings.configEditJobId = nil;
        SaveSettingsOnly();
    end
    imgui.SameLine();
    local col = 0;
    local palJobIconTheme = ResolveCrossbarPaletteJobIconTheme(crossbarSettings);
    for ji = 1, 22 do
        local abbr = jobs[ji];
        if abbr then
            local jtex = TextureManager.getJobIcon(ji, palJobIconTheme);
            local sel = crossbarSettings.configFocus == 'job' and (crossbarSettings.configEditJobId == ji);
            if drawIconButton('##xbJobIcon' .. ji, jtex, abbr, sel) then
                crossbarSettings.configFocus = 'job';
                crossbarSettings.configEditJobId = ji;
                -- Subjob (SJ) tier cannot match main job; fall back to Shared
                if crossbarSettings.configEditSubjobId == ji then
                    crossbarSettings.configEditSubjobId = 0;
                end
                SaveSettingsOnly();
            end
            col = col + 1;
            if col < 11 then
                imgui.SameLine();
            else
                col = 0;
            end
        end
    end
    imgui.EndGroup();
    imgui.Spacing();

    if stripOpts.showGlobalOptionsRow then
        if crossbarSettings.configFocus == 'job' then
            imgui.AlignTextToFramePadding();
            imgui.Text('Subjob');
            imgui.SameLine();
            imgui.SetNextItemWidth(120);
            local sjCur = crossbarSettings.configEditSubjobId;
            if sjCur == nil then
                sjCur = data.subjobId or 0;
            end
            local mainJobForTier = crossbarSettings.configEditJobId or data.jobId or 1;
            if sjCur ~= 0 and sjCur == mainJobForTier then
                crossbarSettings.configEditSubjobId = 0;
                sjCur = 0;
                SaveSettingsOnly();
            end
            local sjLabel = GetSubjobMenuLabel(sjCur);
            if imgui.BeginCombo('##xbCfgSubjob', sjLabel) then
                if imgui.Selectable('Shared##xbsj0', sjCur == 0) then
                    crossbarSettings.configEditSubjobId = 0;
                    SaveSettingsOnly();
                end
                for sj = 1, 22 do
                    if sj ~= mainJobForTier then
                        local nm = jobs[sj];
                        if nm and imgui.Selectable(nm .. '##xbsj' .. sj, sjCur == sj) then
                            crossbarSettings.configEditSubjobId = sj;
                            SaveSettingsOnly();
                        end
                    end
                end
                imgui.EndCombo();
            end
            imgui.SameLine();
            components.PushMacroManagerButtonStyle();
            if imgui.Button('Macro Manager##xbMacro', {120, 0}) then
                macropalette.TogglePalette();
            end
            components.PopMacroManagerButtonStyle();
            imgui.ShowHelp('Palette storage tier for this job (Shared = job-wide library). Use Macro Manager for macro bar palettes.');
        else
            imgui.AlignTextToFramePadding();
            imgui.TextColored({0.65, 0.65, 0.7, 1.0}, 'Editing Global [G] crossbar sets');
            imgui.SameLine();
            components.PushMacroManagerButtonStyle();
            if imgui.Button('Macro Manager##xbMacroG', { 120, 0 }) then
                macropalette.TogglePalette();
            end
            components.PopMacroManagerButtonStyle();
            imgui.ShowHelp('Global [G] palettes are shared across all jobs. Use Macro Manager for macro bar palettes.');
        end
        imgui.Spacing();
    end
end

local function DrawCrossbarSettings(selectedCrossbarTab, menuState)
    local crossbarSettings = gConfig.hotbarCrossbar;
    if not crossbarSettings then
        imgui.TextColored({1.0, 0.5, 0.5, 1.0}, 'Crossbar settings not initialized.');
        return selectedCrossbarTab;
    end

    data.SetPlayerJob();
    MaybeSyncCrossbarEditContextOnCategoryEnter(crossbarSettings, menuState);

    selectedCrossbarTab = selectedCrossbarTab or 1;

    if not crossbarConfigSubTabUserChosen then
        crossbarSettings.configUiTab = 1;
    elseif not crossbarSettings.configUiTab or crossbarSettings.configUiTab < 1 or crossbarSettings.configUiTab > 3 then
        crossbarSettings.configUiTab = 1;
    end
    local uit = crossbarSettings.configUiTab;
    local function saveCrossbarConfigTab(i)
        crossbarSettings.configUiTab = i;
        if i ~= 1 then
            crossbarConfigSubTabUserChosen = true;
        end
        SaveSettingsOnly();
    end

    do
        local clicked1 = components.DrawStyledTab('Controller Settings', 'xbCfgTab1', uit == 1, nil, components.TAB_STYLE.height, components.TAB_STYLE.padding);
        if clicked1 then
            saveCrossbarConfigTab(1);
        end
        imgui.SameLine();
        local clicked2 = components.DrawStyledTab('Manage Palettes & Crossbar', 'xbCfgTab2', uit == 2, nil, components.TAB_STYLE.height, components.TAB_STYLE.padding, 'green');
        if clicked2 then
            saveCrossbarConfigTab(2);
        end
        imgui.SameLine();
        local clicked3 = components.DrawStyledTab('Global Visual Settings', 'xbCfgTab3', uit == 3, nil, components.TAB_STYLE.height, components.TAB_STYLE.padding);
        if clicked3 then
            saveCrossbarConfigTab(3);
        end
    end
    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    if uit == 1 then
    -- Controller Settings section
    imgui.TextColored(components.TAB_STYLE.gold, 'Controller Settings');
    imgui.Spacing();

    -- Controller Profile selection
    local devices = require('modules.hotbar.devices');
    local currentScheme = controller.GetControllerScheme();
    local deviceSchemes = devices.GetSchemeNames();
    local deviceDisplayNames = devices.GetSchemeDisplayNames();

    -- Find current selection index
    local currentIndex = 1;
    for i, scheme in ipairs(deviceSchemes) do
        if scheme == currentScheme then
            currentIndex = i;
            break;
        end
    end

    -- Map profile to matching theme
    local profileToTheme = {
        xbox = 'Xbox',
        dualsense = 'PlayStation',
        switchpro = 'Nintendo',
        dinput = 'Xbox',
    };

    imgui.AlignTextToFramePadding();
    imgui.Text('Controller Profile:');
    imgui.SameLine();
    imgui.SetNextItemWidth(150);
    if imgui.BeginCombo('##controllerSelect', deviceDisplayNames[currentScheme] or currentScheme, ImGuiComboFlags_None) then
        for i, scheme in ipairs(deviceSchemes) do
            local isSelected = (scheme == currentScheme);
            if imgui.Selectable(deviceDisplayNames[scheme], isSelected) then
                crossbarSettings.controllerScheme = scheme;
                -- If switching to dinput, apply custom mapping if it exists
                local customMapping = nil;
                if scheme == 'dinput' and crossbarSettings.customControllerMappings and crossbarSettings.customControllerMappings.dinput then
                    customMapping = crossbarSettings.customControllerMappings.dinput;
                end
                controller.SetControllerScheme(scheme, customMapping);
                -- Auto-adjust theme to match profile
                local matchingTheme = profileToTheme[scheme];
                if matchingTheme then
                    crossbarSettings.controllerTheme = matchingTheme;
                end
                SaveSettingsOnly();
            end
            if isSelected then
                imgui.SetItemDefaultFocus();
            end
        end
        imgui.EndCombo();
    end
    imgui.ShowHelp('Select which button mapping profile to use.\n\n- Xbox: For XInput controllers (Xbox, 8BitDo in X-mode)\n- PlayStation: For DualSense/DualShock via DirectInput\n- Switch Pro: For Nintendo Switch Pro controller\n- Generic DirectInput: For other DirectInput controllers\n\nChanging this will also update the button icon theme.');

    local hasAnalogTriggers = (currentScheme == 'xbox' or currentScheme == 'dualsense');

    -- Display Mode (directly under Controller Profile)
    do
        local displayModes = { 'normal', 'activeOnly' };
        local displayModeLabels = { 'Normal', 'Active Only' };
        local currentDisplayMode = crossbarSettings.displayMode or 'normal';
        local currentDisplayIndex = 1;
        for i, mode in ipairs(displayModes) do
            if mode == currentDisplayMode then
                currentDisplayIndex = i;
                break;
            end
        end

        imgui.Spacing();
        imgui.AlignTextToFramePadding();
        imgui.Text('Display Mode:');
        imgui.SameLine();
        imgui.SetNextItemWidth(150);
        if imgui.BeginCombo('##displayModeCrossbar', displayModeLabels[currentDisplayIndex]) then
            for i, label in ipairs(displayModeLabels) do
                local isSelected = (i == currentDisplayIndex);
                if imgui.Selectable(label, isSelected) then
                    crossbarSettings.displayMode = displayModes[i];
                    SaveSettingsOnly();
                end
                if isSelected then
                    imgui.SetItemDefaultFocus();
                end
            end
            imgui.EndCombo();
        end
        imgui.ShowHelp('Normal: Always show both sides (inactive side dimmed).\nActive Only: Show only when trigger is held, displaying only the active side.');
    end

    -- Analog Trigger Threshold Settings (Xbox and PlayStation only)
    if hasAnalogTriggers then
        imgui.Spacing();
        imgui.Text('Analog Trigger Settings');
        imgui.Separator();

        components.DrawPartySliderInt(crossbarSettings, 'Press Threshold##crossbar', 'triggerPressThreshold', 5, 250, '%d', function()
            controller.SetTriggerThresholds(crossbarSettings.triggerPressThreshold, crossbarSettings.triggerReleaseThreshold);
        end, 30);
        imgui.ShowHelp('Analog trigger value (0-255) required to register as pressed. Higher values require a deeper press. Default: 30');

        components.DrawPartySliderInt(crossbarSettings, 'Release Threshold##crossbar', 'triggerReleaseThreshold', 5, 250, '%d', function()
            controller.SetTriggerThresholds(crossbarSettings.triggerPressThreshold, crossbarSettings.triggerReleaseThreshold);
        end, 15);
        imgui.ShowHelp('Analog trigger value (0-255) below which the trigger is considered released. Provides hysteresis to prevent jitter. Default: 15');
    end

    imgui.Spacing();

    -- Custom DirectInput button mapping section (only for dinput scheme)
    if currentScheme == 'dinput' then
        imgui.Indent(20);

        local hasCustomMapping = crossbarSettings.customControllerMappings and 
                                  crossbarSettings.customControllerMappings.dinput;

        -- Configure button
        if imgui.Button('Configure Button Mapping##dinput', {0, 0}) then
            local buttondetect = require('modules.hotbar.buttondetect');
            buttonDetectionState.active = true;
            buttonDetectionState.progress = 0;
            buttondetect.StartDetection(function(results)
                if not crossbarSettings.customControllerMappings then
                    crossbarSettings.customControllerMappings = {};
                end
                crossbarSettings.customControllerMappings.dinput = results;
                buttonDetectionState.active = false;
                SaveSettingsOnly();
                -- Re-initialize controller with new mapping
                controller.SetControllerScheme('dinput', results);
            end);
        end
        imgui.SameLine();
        imgui.ShowHelp('Launch wizard to configure button layout for your controller. Custom mappings allow you to define your own button layout for DirectInput controllers.');

        -- Status indicator
        imgui.SameLine();
        if hasCustomMapping then
            imgui.TextColored({0, 1, 0, 1}, '(Using custom mapping)');
        else
            imgui.TextColored({0.7, 0.7, 0.7, 1}, '(Using default mapping)');
        end

        -- Clear custom mapping button (only show if custom mapping exists)
        if hasCustomMapping then
            imgui.SameLine();
            if imgui.Button('Clear Custom Mapping##dinput', {150, 0}) then
                crossbarSettings.customControllerMappings.dinput = nil;
                SaveSettingsOnly();
                -- Re-initialize controller without custom mapping
                controller.SetControllerScheme('dinput');
            end
            imgui.SameLine();
            imgui.ShowHelp('Remove custom mapping and revert to defaults.');
        end

        -- Show progress bar during detection
        if buttonDetectionState.active then
            local buttondetect = require('modules.hotbar.buttondetect');
            local progress, maxProgress = buttondetect.GetProgress();
            imgui.ProgressBar(progress / maxProgress, {-1, 20}, string.format('Button %d of %d', progress, maxProgress));
            imgui.TextWrapped('Detecting buttons... ' .. (buttondetect.GetCurrentPrompt() or ''));
            if imgui.Button('Cancel##buttondetect', {0, 0}) then
                buttondetect.Cancel();
                buttonDetectionState.active = false;
            end
        end

        imgui.Unindent(20);
    end

    imgui.Spacing();

    -- Enable "Global" Crossbar Sets (+ default palette tier when enabled); omit live Scope preview line here
    DrawCrossbarUniversalTierOptions(crossbarSettings, { includeScopeLine = false });

    imgui.Spacing();

    -- Double-Tap (window + minimum trigger hold under it when enabled)
    components.DrawPartyCheckbox(crossbarSettings, 'Enable Double-Tap##crossbar', 'enableDoubleTap', DeferredUpdateVisuals);
    imgui.ShowHelp('Enable L2x2 and R2x2 double-tap modes. Tap a trigger twice quickly (hold on second tap) to access double-tap bars.\nPer-trigger [G] attach and pet overrides are set in Edit Full Palette (Manage Palettes & Crossbar tab).');

    if crossbarSettings.enableDoubleTap then
        components.DrawPartySlider(crossbarSettings, 'Double-Tap Window##crossbar', 'doubleTapWindow', 0.1, 0.6, '%.2f sec', function()
            controller.SetDoubleTapWindow(crossbarSettings.doubleTapWindow);
        end, 0.3);
        imgui.ShowHelp('Time window to register a double-tap (in seconds).');

        if hasAnalogTriggers then
            components.DrawPartySlider(crossbarSettings, 'Minimum Trigger Hold##crossbar', 'minTriggerHold', 0.01, 0.15, '%.3f sec', function()
                controller.SetMinTriggerHold(crossbarSettings.minTriggerHold);
            end, 0.05);
            imgui.ShowHelp('Minimum time the trigger must be held before releasing for the release to count toward double-tap detection. Prevents false double-taps from analog jitter or accidental taps. Default: 0.050 sec (50ms)');
        end

        imgui.Spacing();
        components.DrawPartyCheckbox(crossbarSettings, 'Show Double-Tap Crossbars Preview##crossbar', 'showDoubleTapPreview', DeferredUpdateVisuals);
        imgui.ShowHelp('Show two small floating crossbar windows that always display your L2x2 and R2x2 double-tap bars,\nincluding cooldowns. While a double-tap is active, the preview swaps to show your base bar so you\ncan reference both at once. Drag anchors (visible when config is open) to reposition each preview.');

        if crossbarSettings.showDoubleTapPreview then
            imgui.Indent(20);
            components.DrawPartySlider(crossbarSettings, 'Preview Scale##crossbar', 'doubleTapPreviewScale', 0.30, 1.0, '%.2f', DeferredUpdateVisuals, 0.60);
            imgui.ShowHelp('Size of the preview windows relative to the main crossbar. 0.60 = 60% of full size.');
            components.DrawPartySlider(crossbarSettings, 'Preview Opacity##crossbar', 'doubleTapPreviewOpacity', 0.20, 1.0, '%.2f', DeferredUpdateVisuals, 1.0);
            imgui.ShowHelp('Base opacity of the preview windows. Follows trigger-dim behaviour: the inactive preview dims when\nthe opposite trigger is held, matching how the main crossbar dims its inactive side.');
            components.DrawPartyCheckbox(crossbarSettings, 'Lock Preview Positions##crossbar', 'doubleTapPreviewLocked', DeferredUpdateVisuals);
            imgui.ShowHelp('Lock the L2x2 and R2x2 preview windows in place so they cannot be dragged.\nIndependent of the main crossbar position lock.');
            components.DrawPartyCheckbox(crossbarSettings, 'Show Item Quantity##crossbar', 'doubleTapPreviewShowQty', DeferredUpdateVisuals);
            imgui.ShowHelp('Show item stack quantity on preview slots. Disable if you find the numbers clutter\nthe smaller preview windows.');
            imgui.Unindent(20);
        end
    end

    imgui.Spacing();

    -- Chords: L2+R2 / R2+L2 expanded bars (+ shared expanded bar when enabled)
    components.DrawPartyCheckbox(crossbarSettings, 'Enable Chords (L2+R2 / R2+L2)', 'enableExpandedCrossbar');
    imgui.ShowHelp('Enable L2+R2 and R2+L2 combo modes. Hold one trigger, then press the other to access expanded bars.\nOptional Global [G] palette attach per trigger group is set in Edit Full Palette when editing a Job palette; [G] sets are labeled in palette lists.');

    if crossbarSettings.enableExpandedCrossbar then
        imgui.Indent(20);
        components.DrawPartyCheckbox(crossbarSettings, 'Use Shared Expanded Bar##crossbar', 'useSharedExpandedBar', DeferredUpdateVisuals);
        imgui.ShowHelp('When enabled, L2+R2 and R2+L2 will access the same shared expanded bar instead of separate bars.\nThis shared bar is completely independent from the separate L2+R2 and R2+L2 bars.');
        imgui.Unindent(20);
    end

    imgui.Spacing();

    DrawCrossbarGlobalPalettesSection({
        skipUniversalTierOptions = true,
        includeUniversalLists = false,
        includeJobPalettes = false,
    });

    elseif uit == 2 then
        DrawCrossbarJobIconStrip(crossbarSettings, { showGlobalOptionsRow = true });
        if crossbarSettings.configFocus == 'universal' then
            DrawCrossbarGlobalPalettesSection({
                showEnableCheckbox = false,
                skipUniversalTierOptions = true,
                includeUniversalLists = true,
                includeJobPalettes = false,
                compactGlobalPaletteScroll = true,
                embedCrossbarUniversalPaletteManager = true,
            });
        else
            local effJob = crossbarSettings.configEditJobId or data.jobId or 1;
            local effSub = crossbarSettings.configEditSubjobId;
            if effSub == nil then
                effSub = data.subjobId or 0;
            end
            DrawCrossbarGlobalPalettesSection({
                showEnableCheckbox = false,
                skipUniversalTierOptions = true,
                includeUniversalLists = false,
                includeJobPalettes = true,
                jobId = effJob,
                subjobId = effSub,
                embedCrossbarJobPaletteManager = true,
            });
        end

        if crossbarSettings.configFocus == 'job' then
            imgui.Spacing();
            imgui.TextWrapped(
                'Per-trigger layout, Pet palette, and Global [G] overrides are edited in Edit Full Palette (button in the palette list above). ' ..
                'Visual slot styling remains under Global Visual Settings.'
            );
        end

    elseif uit == 3 then
        imgui.TextColored(components.TAB_STYLE.gold, 'Global Visual Settings');
        imgui.Spacing();

        if crossbarGlobalVis_prevUit ~= 3 then
            for _, sk in ipairs(CROSSBAR_GLOBAL_VIS_KEYS) do
                if not crossbarGlobalVis_openedSections[sk] then
                    crossbarGlobalVis_sectionNonce[sk] = (crossbarGlobalVis_sectionNonce[sk] or 0) + 1;
                end
            end
        end

        if crossbarSettings.paletteJobIconTheme == nil
            or crossbarSettings.paletteJobIconTheme == 'ClassicFFXIV' then
            crossbarSettings.paletteJobIconTheme = 'Classic';
        end

        if CrossbarGlobalVisualCollapsingSection('palCtrl', 'Palette & Controller Icons##crossbar', false) then
            imgui.TextColored({ 0.85, 0.82, 0.7, 1.0 }, 'Palette Icons');
            imgui.Spacing();
            local paletteIconThemes = { 'Classic', 'FFXI', 'FFXIV-1' };
            components.DrawPartyComboBox(crossbarSettings, 'Icon set##paletteJobIconTheme', 'paletteJobIconTheme', paletteIconThemes, DeferredUpdateVisuals);
            imgui.ShowHelp('Job icons for Manage Palettes (crossbar) and the in-game palette scope icon when using Job [J] storage. Folders: addons/XIUI/assets/jobs/Classic, FFXI, FFXIV-1.');

            components.DrawPartySlider(crossbarSettings, 'Icon Height##crossbarScopeLift', 'paletteScopeIconOffsetY', 0, 48, '%.0f', DeferredUpdateVisuals, 12);
            imgui.ShowHelp('Vertical lift for the job / Global palette icon above the center line (pixels). Increase if it overlaps the L2/R2 combo text.');

            components.DrawPartySliderInt(crossbarSettings, 'Icon Size (px)##crossbarScopeIconSize', 'paletteScopeIconSize', 8, 64, '%d', DeferredUpdateVisuals, 22);
            imgui.ShowHelp('Width and height of the job or Global palette scope icon drawn above the center divider (when the scope icon is enabled).');

            do
                local effScope = crossbarSettings.showPaletteScopeIcon;
                if effScope == nil then
                    effScope = crossbarSettings.showPaletteName;
                end
                if imgui.Checkbox('Show Palette Scope Icon##crossbarPaletteScopeIcon', { effScope }) then
                    crossbarSettings.showPaletteScopeIcon = not effScope;
                    SaveSettingsOnly();
                    UpdateUserSettings();
                    DeferredUpdateVisuals();
                end
            end
            imgui.ShowHelp('Infinity for Global [G] storage or main job icon for Job [J] storage, above the center line. Uncheck to hide only the icon; palette name is separate below.');

            components.DrawPartyCheckbox(crossbarSettings, 'Show Palette Name##crossbarPaletteName', 'showPaletteName');
            if crossbarSettings.showPaletteName then
                imgui.SameLine();
                components.DrawInlineOffsets(crossbarSettings, 'crossbarpalette', 'paletteNameOffsetX', 'paletteNameOffsetY', 35);
            end
            imgui.ShowHelp('Current palette name and index below the crossbar (e.g. "Stuns (2/5)"). X/Y adjust position.');

            imgui.Spacing();
            imgui.Separator();
            imgui.Spacing();

            local controllerThemes = { 'PlayStation', 'Xbox', 'Nintendo' };
            components.DrawPartyComboBox(crossbarSettings, 'Controller Theme##crossbar', 'controllerTheme', controllerThemes);
            imgui.ShowHelp('Select controller button icon style. Nintendo layout: X top, A right, B bottom, Y left.');

            components.DrawPartyCheckbox(crossbarSettings, 'Show Button Icons##crossbar', 'showButtonIcons');
            imgui.ShowHelp('Show d-pad and face button icons on slots.');

            if crossbarSettings.showButtonIcons then
                components.DrawPartySliderInt(crossbarSettings, 'Button Icon Size##crossbar', 'buttonIconSize', 8, 32, '%d', nil, 16);
                imgui.ShowHelp('Size of controller button icons.');

                components.DrawPartySliderInt(crossbarSettings, 'Button Icon Gap (H)##crossbar', 'buttonIconGapH', 0, 24, '%d', nil, 2);
                imgui.ShowHelp('Horizontal spacing between center controller icons.');

                components.DrawPartySliderInt(crossbarSettings, 'Button Icon Gap (V)##crossbar', 'buttonIconGapV', 0, 24, '%d', nil, 2);
                imgui.ShowHelp('Vertical spacing between center controller icons.');
            end

            imgui.Separator();

            components.DrawPartyCheckbox(crossbarSettings, 'Show Trigger Icons##crossbar', 'showTriggerLabels');
            imgui.ShowHelp('Show L2/R2 trigger icons above the crossbar groups.');

            if crossbarSettings.showTriggerLabels then
                components.DrawPartySlider(crossbarSettings, 'Trigger Icon Scale##crossbar', 'triggerIconScale', 0.5, 2.0, '%.1f', nil, 1.0);
                imgui.ShowHelp('Scale for L2/R2 trigger icons above groups (base size 49x28).');
            end
        end

        if CrossbarGlobalVisualCollapsingSection('slot', 'Slot Settings##crossbar', false) then
            components.DrawPartySliderInt(crossbarSettings, 'Slot Size (px)##crossbar', 'slotSize', 32, 64, '%d', nil, 48);
            imgui.ShowHelp('Size of each slot in pixels.');

            components.DrawPartySliderInt(crossbarSettings, 'Slot Gap (Vertical)##crossbar', 'slotGapV', 0, 128, '%d', nil, 4);
            imgui.ShowHelp('Vertical gap between top and bottom slots in each diamond.');

            components.DrawPartySliderInt(crossbarSettings, 'Slot Gap (Horizontal)##crossbar', 'slotGapH', 0, 128, '%d', nil, 4);
            imgui.ShowHelp('Horizontal gap between left and right slots in each diamond.');

            components.DrawPartySliderInt(crossbarSettings, 'Diamond Spacing##crossbar', 'diamondSpacing', 0, 128, '%d', nil, 20);
            imgui.ShowHelp('Horizontal space between D-pad and face button diamonds.');

            components.DrawPartySliderInt(crossbarSettings, 'Group Spacing##crossbar', 'groupSpacing', 0, 128, '%d', nil, 40);
            imgui.ShowHelp('Space between L2 and R2 groups.');

            components.DrawPartyCheckbox(crossbarSettings, 'Show Divider##crossbar', 'showDivider');
            imgui.ShowHelp('Show a divider line between L2 and R2 groups.');

            -- Show MP Cost with X/Y offsets
            components.DrawPartyCheckbox(crossbarSettings, 'Show MP Cost##crossbar', 'showMpCost');
            if crossbarSettings.showMpCost then
                imgui.SameLine();
                components.DrawInlineOffsets(crossbarSettings, 'crossbarmp', 'mpCostOffsetX', 'mpCostOffsetY', 35);
            end
            imgui.ShowHelp('Display MP cost on spell slots. X/Y offsets adjust position.');

            -- Show Item Quantity with X/Y offsets
            components.DrawPartyCheckbox(crossbarSettings, 'Show Item Quantity##crossbar', 'showQuantity');
            if crossbarSettings.showQuantity then
                imgui.SameLine();
                components.DrawInlineOffsets(crossbarSettings, 'crossbarqty', 'quantityOffsetX', 'quantityOffsetY', 35);
            end
            imgui.ShowHelp('Display item quantity on item slots. X/Y offsets adjust position.');

            -- 1.8.0 addition: full-stack count above the item quantity (only counts complete stacks)
            components.DrawPartyCheckbox(crossbarSettings, 'Show Stack Quantity##crossbar', 'showStackQuantity');
            imgui.ShowHelp('Show full-stack count next to the item quantity. Only complete stacks are counted (e.g. 25 of stack-12 items shows "(2)"). Shares position/font with Show Item Quantity.');

            -- Show Combo Text with X/Y offsets
            components.DrawPartyCheckbox(crossbarSettings, 'Show Combo Text##crossbar', 'showComboText');
            if crossbarSettings.showComboText then
                imgui.SameLine();
                components.DrawInlineOffsets(crossbarSettings, 'crossbarcombo', 'comboTextOffsetX', 'comboTextOffsetY', 35);
            end
            imgui.ShowHelp('Show current combo mode text in center (L2+R2, R2+L2, L2x2, R2x2). X/Y offsets adjust position.');

            -- Show Action Labels with X/Y offsets
            components.DrawPartyCheckbox(crossbarSettings, 'Show Action Labels##crossbar', 'showActionLabels');
            if crossbarSettings.showActionLabels then
                imgui.SameLine();
                components.DrawInlineOffsets(crossbarSettings, 'crossbarlbl', 'actionLabelOffsetX', 'actionLabelOffsetY', 35);
            end
            imgui.ShowHelp('Show spell/ability names below slots. X/Y offsets adjust position.');
        end

        if CrossbarGlobalVisualCollapsingSection('bg', 'Background##crossbar', false) then
            local bgThemes = {'-None-', 'Plain', 'Window1', 'Window2', 'Window3', 'Window4', 'Window5', 'Window6', 'Window7', 'Window8'};
            components.DrawPartyComboBox(crossbarSettings, 'Theme##bgcrossbar', 'backgroundTheme', bgThemes, DeferredUpdateVisuals);
            imgui.ShowHelp('Select the background window theme.');

            components.DrawPartySlider(crossbarSettings, 'Background Scale##crossbar', 'bgScale', 0.1, 3.0, '%.2f', nil, 1.0);
            imgui.ShowHelp('Scale of the background texture.');

            components.DrawPartySlider(crossbarSettings, 'Border Scale##crossbar', 'borderScale', 0.1, 3.0, '%.2f', nil, 1.0);
            imgui.ShowHelp('Scale of the window borders.');

            components.DrawPartySlider(crossbarSettings, 'Background Opacity##crossbar', 'backgroundOpacity', 0.0, 1.0, '%.2f');
            imgui.ShowHelp('Opacity of the background.');

            components.DrawPartySlider(crossbarSettings, 'Border Opacity##crossbar', 'borderOpacity', 0.0, 1.0, '%.2f');
            imgui.ShowHelp('Opacity of the window borders.');
        end

        -- Text section
        if CrossbarGlobalVisualCollapsingSection('text', 'Text Settings##crossbar', false) then
            components.DrawPartySliderInt(crossbarSettings, 'Keybind Text Size##crossbar', 'keybindFontSize', 6, 24, '%d', nil, 10);
            imgui.ShowHelp('Text size for keybind labels.');

            components.DrawPartySliderInt(crossbarSettings, 'Label Text Size##crossbar', 'labelFontSize', 6, 24, '%d', nil, 10);
            imgui.ShowHelp('Text size for action labels.');

            components.DrawPartySliderInt(crossbarSettings, 'Cooldown Text Size##crossbar', 'recastTimerFontSize', 6, 24, '%d', DeferredUpdateVisuals, 11);
            imgui.ShowHelp('Text size for cooldown timer display.');

            components.DrawPartyCheckbox(crossbarSettings, 'Flash Under 5 Seconds##crossbar', 'flashCooldownUnder5');
            imgui.ShowHelp('Flash the cooldown timer text when remaining time is under 5 seconds.');

            components.DrawPartyCheckbox(crossbarSettings, 'Use Hh:MM Cooldown Format##crossbar', 'useHHMMCooldownFormat');
            imgui.ShowHelp('Display cooldown timers as Hh:MM (e.g., "1h:49") instead of "1h 49m" for shorter text.');

            components.DrawPartySliderInt(crossbarSettings, 'Trigger Label Text Size##crossbar', 'triggerLabelFontSize', 6, 24, '%d', nil, 14);
            imgui.ShowHelp('Text size for combo mode labels (L2, R2, etc.).');

            components.DrawPartySliderInt(crossbarSettings, 'MP Cost Text Size##crossbar', 'mpCostFontSize', 6, 24, '%d', nil, 10);
            imgui.ShowHelp('Text size for MP cost display.');

            components.DrawPartySliderInt(crossbarSettings, 'Quantity Text Size##crossbar', 'quantityFontSize', 6, 24, '%d', nil, 10);
            imgui.ShowHelp('Text size for item quantity display.');

            components.DrawPartySliderInt(crossbarSettings, 'Combo Text Size##crossbar', 'comboTextFontSize', 8, 24, '%d', nil, 12);
            imgui.ShowHelp('Font size for combo mode text (L2+R2, R2+L2, etc.).');

            components.DrawPartySliderInt(crossbarSettings, 'Palette Name Text Size##crossbar', 'paletteNameFontSize', 8, 24, '%d', nil, 10);
            imgui.ShowHelp('Font size for palette name display.');
        end

        -- Visual Feedback section
        if CrossbarGlobalVisualCollapsingSection('vfb', 'Visual Feedback##crossbar', false) then
            components.DrawPartySlider(crossbarSettings, 'Inactive Dim##crossbar', 'inactiveSlotDim', 0.0, 1.0, '%.2f', nil, 0.5);
            imgui.ShowHelp('Dim factor for inactive trigger side (0 = black, 1 = full brightness).');

            components.DrawPartySlider(crossbarSettings, 'Inactive Dim (trigger held)##crossbar', 'inactiveSideWhileTriggerDim', 0.0, 1.0, '%.2f', nil, 0.15);
            imgui.ShowHelp('Brightness for the half of the bar you are not using while L2 or R2 is held. Lower hides those slots so the active set stands out.');

            -- Default to true if not set
            if crossbarSettings.enableTransitionAnimations == nil then
                crossbarSettings.enableTransitionAnimations = true;
            end
            local transAnimEnabled = { crossbarSettings.enableTransitionAnimations };
            if imgui.Checkbox('Enable Transition Animations##crossbar', transAnimEnabled) then
                crossbarSettings.enableTransitionAnimations = transAnimEnabled[1];
                SaveSettingsOnly();
            end
            imgui.ShowHelp('Enable smooth animations when switching between crossbar modes (L2, R2, combos). Disable for instant transitions.');

            -- Default to true if not set
            if crossbarSettings.enablePressScale == nil then
                crossbarSettings.enablePressScale = true;
            end
            local pressScaleEnabled = { crossbarSettings.enablePressScale };
            if imgui.Checkbox('Enable Press Scale##crossbar', pressScaleEnabled) then
                crossbarSettings.enablePressScale = pressScaleEnabled[1];
                SaveSettingsOnly();
            end
            imgui.ShowHelp('Enable icon scaling animation when pressing an action slot. Disable for no visual feedback on press.');
        end
    end

    crossbarGlobalVis_prevUit = uit;

    -- Draw confirmation popup for job-specific toggle
    hotbarConfig.DrawJobSpecificConfirmPopup();

    -- Draw palette modal (unified for both hotbar and crossbar; implementation in config/hotbar.lua)
    hotbarConfig.DrawPaletteModal();

    return selectedCrossbarTab;
end

local function DrawCrossbarColorSettings()
    local crossbarSettings = gConfig.hotbarCrossbar;
    if not crossbarSettings then
        imgui.TextColored({1.0, 0.5, 0.5, 1.0}, 'Crossbar settings not initialized.');
        return;
    end

    local colorFlags = bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaPreviewHalf, ImGuiColorEditFlags_AlphaBar);

    imgui.TextColored(components.TAB_STYLE.gold, 'Crossbar Color Settings');
    imgui.Spacing();

    if components.CollapsingSection('Window Colors##crossbarcolor', true) then
        local bgColor = crossbarSettings.bgColor or 0xFFFFFFFF;
        local bgColorTable = ARGBToImGui(bgColor);
        if imgui.ColorEdit4('Background Color##crossbar', bgColorTable, colorFlags) then
            crossbarSettings.bgColor = ImGuiToARGB(bgColorTable);
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Color tint for the window background.');

        local borderColor = crossbarSettings.borderColor or 0xFFFFFFFF;
        local borderColorTable = ARGBToImGui(borderColor);
        if imgui.ColorEdit4('Border Color##crossbar', borderColorTable, colorFlags) then
            crossbarSettings.borderColor = ImGuiToARGB(borderColorTable);
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Color tint for the window borders.');
    end

    if components.CollapsingSection('Slot Colors##crossbarcolor', true) then
        local slotBgColor = crossbarSettings.slotBackgroundColor or 0x55000000;
        local slotBgColorTable = ARGBToImGui(slotBgColor);
        if imgui.ColorEdit4('Slot Background##crossbar', slotBgColorTable, colorFlags) then
            crossbarSettings.slotBackgroundColor = ImGuiToARGB(slotBgColorTable);
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Color and transparency of slot backgrounds.');

        components.DrawPartySlider(crossbarSettings, 'Slot Opacity##crossbar', 'slotOpacity', 0.0, 1.0, '%.2f', nil, 1.0);
        imgui.ShowHelp('Opacity of the slot background texture.');

        local highlightColor = crossbarSettings.activeSlotHighlight or 0x44FFFFFF;
        local highlightColorTable = ARGBToImGui(highlightColor);
        if imgui.ColorEdit4('Active Highlight##crossbar', highlightColorTable, colorFlags) then
            crossbarSettings.activeSlotHighlight = ImGuiToARGB(highlightColorTable);
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Highlight color for slots when trigger is held.');
    end

    if components.CollapsingSection('Text Colors##crossbarcolor', true) then
        local keybindColor = crossbarSettings.keybindFontColor or 0xFFFFFFFF;
        local keybindColorTable = ARGBToImGui(keybindColor);
        if imgui.ColorEdit4('Keybind Color##crossbar', keybindColorTable, colorFlags) then
            crossbarSettings.keybindFontColor = ImGuiToARGB(keybindColorTable);
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Color for keybind labels.');

        local triggerLabelColor = crossbarSettings.triggerLabelColor or 0xFFFFCC00;
        local triggerLabelColorTable = ARGBToImGui(triggerLabelColor);
        if imgui.ColorEdit4('Trigger Label Color##crossbar', triggerLabelColorTable, colorFlags) then
            crossbarSettings.triggerLabelColor = ImGuiToARGB(triggerLabelColorTable);
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Color for combo mode labels (L2, R2, etc.).');

        local mpCostColor = crossbarSettings.mpCostFontColor or 0xFFD4FF97;
        local mpCostColorTable = ARGBToImGui(mpCostColor);
        if imgui.ColorEdit4('MP Cost Color##crossbar', mpCostColorTable, colorFlags) then
            crossbarSettings.mpCostFontColor = ImGuiToARGB(mpCostColorTable);
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Color for MP cost display on spell slots.');

        local quantityColor = crossbarSettings.quantityFontColor or 0xFFFFFFFF;
        local quantityColorTable = ARGBToImGui(quantityColor);
        if imgui.ColorEdit4('Quantity Color##crossbar', quantityColorTable, colorFlags) then
            crossbarSettings.quantityFontColor = ImGuiToARGB(quantityColorTable);
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Color for item quantity display. Note: Shows red when quantity is 0.');

        local labelColor = crossbarSettings.labelFontColor or 0xFFFFFFFF;
        local labelColorTable = ARGBToImGui(labelColor);
        if imgui.ColorEdit4('Label Color##crossbar', labelColorTable, colorFlags) then
            crossbarSettings.labelFontColor = ImGuiToARGB(labelColorTable);
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Color for action labels below slots.');

        local timerColor = crossbarSettings.recastTimerFontColor or 0xFFFFFFFF;
        local timerColorTable = ARGBToImGui(timerColor);
        if imgui.ColorEdit4('Cooldown Timer Color##crossbar', timerColorTable, colorFlags) then
            crossbarSettings.recastTimerFontColor = ImGuiToARGB(timerColorTable);
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Color for cooldown timer text displayed on slots.');
    end
end

-- Controller palette cycle (hotbarGlobal); top strip in config/crossbar.lua when crossbar is enabled
function M.DrawControllerPaletteCycleGlobalOptions()
    local ctrlOptions = { 'Disabled', 'Enabled' };
    local currentCtrlIndex = (gConfig.hotbarGlobal.paletteCycleControllerEnabled ~= false) and 2 or 1;

    imgui.AlignTextToFramePadding();
    imgui.Text('Palette Cycle:');
    imgui.SameLine();
    imgui.SetNextItemWidth(90);
    if imgui.BeginCombo('##ctrlPaletteCycle', ctrlOptions[currentCtrlIndex]) then
        for i, label in ipairs(ctrlOptions) do
            local isSelected = currentCtrlIndex == i;
            if imgui.Selectable(label, isSelected) then
                gConfig.hotbarGlobal.paletteCycleControllerEnabled = (i == 2);
                SaveSettingsOnly();
            end
            if isSelected then imgui.SetItemDefaultFocus(); end
        end
        imgui.EndCombo();
    end

    if gConfig.hotbarGlobal.paletteCycleControllerEnabled ~= false then
        imgui.SameLine();
        imgui.Text('Button:');
        imgui.SameLine();

        local buttonOptions = { 'R1', 'L1' };
        local currentButton = gConfig.hotbarGlobal.hotbarPaletteCycleButton or 'R1';
        local currentButtonIndex = 1;
        for i, btn in ipairs(buttonOptions) do
            if btn == currentButton then
                currentButtonIndex = i;
                break;
            end
        end

        imgui.SetNextItemWidth(60);
        if imgui.BeginCombo('##hotbarCycleBtn', currentButton) then
            for i, btn in ipairs(buttonOptions) do
                local isSelected = (i == currentButtonIndex);
                if imgui.Selectable(btn .. '##hbCycleBtn' .. i, isSelected) then
                    gConfig.hotbarGlobal.hotbarPaletteCycleButton = btn;
                    SaveSettingsOnly();
                end
                if isSelected then imgui.SetItemDefaultFocus(); end
            end
            imgui.EndCombo();
        end
    end
    imgui.ShowHelp('Controller shortcut to cycle palettes.\nHold the selected shoulder button + D-pad Up/Down to cycle keyboard hotbar palettes and the active crossbar palette.');
end

function M.DrawLogPaletteNameCheckboxCrossbar(idSuffix)
    idSuffix = idSuffix or '##logPalNameXb';
    local hg = gConfig.hotbarGlobal;
    if not hg then
        return;
    end
    local logPaletteName = hg.logPaletteNameCrossbar;
    if logPaletteName == nil then logPaletteName = true; end
    local logVal = { logPaletteName };
    if imgui.Checkbox('Log Palette Name (crossbar)' .. idSuffix, logVal) then
        hg.logPaletteNameCrossbar = logVal[1];
        SaveSettingsOnly();
    end
    imgui.ShowHelp('Log crossbar palette lines in chat for /xiui cpal and controller palette cycling.');
    if logVal[1] then
        imgui.Indent(18);
        local hintOn = hg.logPaletteNameCrossbarCycleHint;
        if hintOn == nil then hintOn = true; end
        local hintVal = { hintOn };
        if imgui.Checkbox('Include RB(R1)+Up/Down return hint (CLI preview)' .. idSuffix .. '_rbHint', hintVal) then
            hg.logPaletteNameCrossbarCycleHint = hintVal[1];
            SaveSettingsOnly();
        end
        imgui.ShowHelp('Extra line after /xiui cpal when previewing another job palette.');
        imgui.Unindent(18);
    end
end

-- Invoked from config/crossbar.lua only (Hotbar category uses config/hotbar.lua M.DrawSettings).
function M.DrawStandaloneCrossbarSettings(state)
    local selectedCrossbarTab = state and state.selectedCrossbarTab or 1;
    selectedCrossbarTab = DrawCrossbarSettings(selectedCrossbarTab, state);
    return { selectedCrossbarTab = selectedCrossbarTab };
end

function M.DrawStandaloneCrossbarColorSettings(_state)
    DrawCrossbarColorSettings();
end

-- Via config/crossbar.lua when the XIUI config window opens (resync Crossbar palette edit job from player)
function M.OnConfigWindowOpened()
    lastConfigCategorySeenForCrossbar = nil;
end

-- Select Crossbar → Manage Palettes & Crossbar (middle tab); used by /xiui cpalette
function M.OpenCrossbarManagePalettesTab()
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings then
        return false;
    end
    crossbarSettings.configUiTab = 2;
    crossbarConfigSubTabUserChosen = true;
    return true;
end

return M;
