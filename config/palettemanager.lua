--[[
* XIUI Config - Palette Manager
* Floating "Palette Manager" window (hotbar + crossbar list) and shared create/rename/copy modals.
* Crossbar-only embed (Manage Palettes strip under XIUI Config) also lives here so modals stay one place;
* the Crossbar *settings* shell is config/crossbar_settings.lua — that file calls into this module.
* Keyboard hotbar palettes: Hotbar category. Controller crossbar palettes: Crossbar category — separate edit paths.
]]--

require('common');
require('handlers.helpers');
local ffi = require('ffi');
local imgui = require('imgui');
local jobs = require('libs.jobs');
local TextureManager = require('libs.texturemanager');
local palette = require('modules.hotbar.palette');
local data = require('modules.hotbar.data');
local json = require('libs.json');
local paletteJson = require('modules.hotbar.palette_json');
local crossbar = require('modules.hotbar.crossbar');
local macropalette = require('modules.hotbar.macropalette');
local dragdrop = require('libs.dragdrop');
local components = require('config.components');

local M = {};

-- Window state
local windowState = {
    isOpen = false,
    selectedJobId = nil,
    selectedSubjobId = nil,  -- 0 = shared
    selectedPaletteType = 'hotbar',  -- 'hotbar' or 'crossbar'
    selectedPaletteName = nil,
    -- Crossbar floating list: which storage tier (0 = Job [J], N = Subjob [SJ]) is selected
    selectedCrossbarStorageSubjob = nil,
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
    -- Crossbar embedded Manage: storage tier for rename/delete/move (merged Shared + subjob view)
    crossbarOperationSubjob = nil,
    crossbarCopyFromSubjob = nil,
    -- Copy: overwrite existing destination palette (same name resolution as palette.lua)
    copyOverwriteExisting = false,
    copyDestExistingIndex = 1,
    -- Crossbar Copy To: destination is Job [J]/Subjob storage vs Global [G] (universal)
    copyDestScope = 'job', -- 'job' | 'universal'
};

-- Embedded Crossbar Palette Manager (Manage Palettes & Crossbar tab — no floating window)
local embedCrossbarJobContext = {
    selectedPaletteName = nil,
    selectedStorageSubjob = nil,
};

local embedCrossbarUniversalContext = {
    selectedPaletteName = nil,
};

-- "Edit Full Palette": large floating window (same idea as Palette Manager, not a dimming modal)
-- ctx: { kind = 'job'|'universal', name, jobId?, subjobId?, st? } (legacy: missing kind => job)
local embedCrossbarComboCtx = nil;
local embedCrossbarComboWinOpen = { false };
-- After "Edit Full Palette" click: avoid clearing ctx on the first frame before Begin() succeeds (some ImGui builds).
local embedCrossbarComboWinGraceFrames = 0;
local embedCrossbarComboHasDrawn = false;
-- Stable height for ##xbFullPalScroll: recomputing GetContentRegionAvail() every frame can jitter 1px and reset scroll.
local editFullPaletteScrollHCached = nil;
local EDIT_FULL_PALETTE_WINDOW_KEY = 'EditFullPalette';
-- Default / clamp width for the embedded Edit Full Palette window (was 680; wider helps L2/R2 footer columns)
local EDIT_FULL_PALETTE_WIN_W = 700;
-- When true, horizontal size is fixed to EDIT_FULL_PALETTE_WIN_W (constraints min/max width equal); height still obeys limits below.
local EDIT_FULL_PALETTE_WIN_LOCK_WIDTH = false;
local EDIT_FULL_PALETTE_WIN_W_MIN = 700;
local EDIT_FULL_PALETTE_WIN_W_MAX = 1400;
-- Default height: inner area scrolls; do not drive window height from content (that caused scroll “jumping”).
local EDIT_FULL_PALETTE_WIN_H_DEFAULT = 760;
-- Resizable height range (constraints). When LOCK_HEIGHT is true, min/max height both use H_DEFAULT (fixed height).
local EDIT_FULL_PALETTE_WIN_H_MIN = 400;
local EDIT_FULL_PALETTE_WIN_H_MAX = 1150;
local EDIT_FULL_PALETTE_WIN_LOCK_HEIGHT = false;
-- Vertical slice reserved for the gap after the scroll child + Undo/Apply/Close row (must stay fixed frame-to-frame).
local EDIT_FULL_PALETTE_FOOTER_BLOCK_H = 44;

-- Palette JSON export/import (file + paste)
local palJsonWinOpen = { false };
local palJsonMode = 'export'; -- 'export' | 'import'
local palJsonBuf = { '' };
local palJsonErr = nil;
local palJsonLastPath = nil;
--- Import: delete macro rows referenced only by this palette before applying JSON (optional).
local palJsonPurgeFirst = { false };
local palJsonQueueDestructiveConfirm = false;
local palJsonExportPart = { 'full' }; -- 'full' | 'slots_only' | 'macros_only' (see paletteJson.EXPORT_PART_*)
local palJsonImportSlots = { true };
local palJsonImportMacros = { true };
--- target: crossbar_job | crossbar_univ | hotbar
local palJsonCtx = {
    target = 'crossbar_job',
    jobId = nil,
    subjobId = nil,
    storageSubjob = nil,
    paletteName = nil,
};

-- User closed XIUI Config while Edit Full Palette was open: show confirm on next palette draw.
local openCloseConfigConfirmPopup = false;
local openUnsavedChangesPopup = false;
-- Pending palette switch: when the user picks a different palette from the dropdown but has unsaved changes.
local pendingPaletteSwitchName = nil;

-- Embedded Palette Manager (Crossbar tab): fixed list viewport = column headers + N rows, then scroll.
local EMBED_CROSSBAR_PAL_LIST_VISIBLE_ROWS = 3;

local function GetItemSpacingY()
    local st = imgui.GetStyle and imgui.GetStyle();
    if not st or not st.ItemSpacing then
        return 8;
    end
    local is = st.ItemSpacing;
    if type(is) == 'table' then
        return math.floor((is[2] or is.y or 8) + 0.5);
    end
    return math.floor((tonumber(is) or 8) + 0.5);
end

local function GetContentRegionAvailHeight()
    if not imgui.GetContentRegionAvail then
        return 200;
    end
    local a, b = imgui.GetContentRegionAvail();
    local h = 200;
    if type(a) == 'table' then
        h = a[2] or a.y or 200;
    elseif type(b) == 'number' then
        h = b;
    end
    -- Whole pixels: sub-pixel avail jitter changes BeginChild height and fights scroll at the bottom.
    return math.floor(h + 0.5);
end

-- Three button rows + spacing (New/Rename/…, Move/Enable/Edit, Export/Import JSON).
local function GetEmbedCrossbarPalMgrActionBlockH()
    local lineH = imgui.GetTextLineHeightWithSpacing();
    local frameH = (imgui.GetFrameHeight and imgui.GetFrameHeight()) or (lineH * 1.45);
    local gap = GetItemSpacingY();
    return math.ceil(frameH * 3 + gap * 2);
end

local function ForceCloseEditFullPaletteWindow()
    embedCrossbarComboWinOpen[1] = false;
    embedCrossbarComboCtx = nil;
    embedCrossbarComboWinGraceFrames = 0;
    embedCrossbarComboHasDrawn = false;
    editFullPaletteScrollHCached = nil;
    data.FullyClosePaletteEditSession();
    crossbar.HidePaletteEditorPrimitives();
end

-- Called from config.lua when the user dismisses the main XIUI Config window.
function M.DeferConfigCloseIfEditFullPaletteOpen()
    -- Only block when the Edit Full Palette *window* is still open (not just grace-held ctx after close).
    if not embedCrossbarComboWinOpen[1] then
        return false;
    end
    -- No unsaved crossbar draft: close the editor and allow config to close without a modal.
    if not data.IsDraftDirty() then
        ForceCloseEditFullPaletteWindow();
        return false;
    end
    openCloseConfigConfirmPopup = true;
    return true;
end

local function BuildEditFullPaletteViewSettings(cross)
    local v = {};
    -- Copy all non-visual properties (palette data, mode toggles, overrides, etc.)
    for k, val in pairs(cross or {}) do
        v[k] = val;
    end
    -- Fixed visual constants — not derived from the user's crossbar display config.
    -- Every user sees an identical editor layout regardless of their gameplay crossbar settings.
    v.slotSize            = 38;
    v.buttonIconSize      = 20;
    v.labelFontSize       = 13;
    v.recastTimerFontSize = 9;
    v.mpCostFontSize      = 9;
    v.quantityFontSize    = 9;
    v.slotGapV            = 6;
    v.slotGapH            = 6;
    v.diamondSpacing      = 20;
    v.groupSpacing        = 40;
    return v;
end

-- Storage tier for named job palettes (0 = Job [J] shared tier, N = that subjob's tier).
-- Must match data.GetCrossbarStorageKeyForCombo / palette.GetCrossbarActivePaletteStorageSubjobForResolution,
-- not raw live subjob id — otherwise "shared" palettes used while /SJ is equipped resolve to an empty bucket.
local function GetEmbedJobPaletteStorageTier(jobId, liveSubjobId)
    local lj = liveSubjobId or 0;
    if lj == 0 then
        return 0;
    end
    if palette.GetCrossbarActivePaletteStorageSubjobForResolution then
        return palette.GetCrossbarActivePaletteStorageSubjobForResolution(jobId, lj) or 0;
    end
    return 0;
end

function M.ToggleEditFullPaletteForCurrent()
    if embedCrossbarComboWinOpen[1] and embedCrossbarComboCtx then
        ForceCloseEditFullPaletteWindow();
        return false;
    end
    local activeName = palette.GetActivePaletteForCombo and palette.GetActivePaletteForCombo('L2') or nil;
    if not activeName or activeName == '' then
        return nil;
    end
    local scope = palette.GetCrossbarPaletteScope and palette.GetCrossbarPaletteScope() or 'job';
    if scope == 'universal' then
        embedCrossbarComboCtx = { kind = 'universal', name = activeName };
    else
        local jid = data.jobId or 1;
        local sj = data.subjobId or 0;
        embedCrossbarComboCtx = {
            kind = 'job',
            jobId = jid,
            subjobId = sj,
            name = activeName,
            st = GetEmbedJobPaletteStorageTier(jid, sj),
        };
    end
    embedCrossbarComboWinOpen[1] = true;
    embedCrossbarComboWinGraceFrames = 0;
    embedCrossbarComboHasDrawn = false;
    return true;
end

local function GetEmbedFullPaletteStorageKey(ctx)
    local kind = ctx.kind or 'job';
    if kind == 'universal' then
        return palette.BuildUniversalCrossbarStorageKey(ctx.name);
    end
    local jobId = ctx.jobId or 1;
    local tier = tonumber(ctx.st) or 0;
    return palette.BuildPaletteStorageKey(jobId, tier, ctx.name);
end

local function JobNameShort(jobId)
    if jobId == nil or jobId == 0 then
        return 'Shared';
    end
    return jobs[jobId] or ('Job ' .. tostring(jobId));
end

local function BuildEmbedFullPaletteScopeLine(ctx, kind)
    if kind == 'universal' then
        return 'Global [G] - "' .. (ctx.name or '?') .. '"';
    end
    local jid = ctx.jobId or 1;
    local st = tonumber(ctx.st) or 0;
    local tier = (st == 0) and 'Shared (J)' or string.format('%s (SJ)', JobNameShort(st));
    if st == 0 then
        return string.format('%s - %s - "%s"', JobNameShort(jid), tier, ctx.name or '?');
    else
        local tabSj = ctx.subjobId or 0;
        return string.format(
            '%s/%s - %s - "%s"',
            JobNameShort(jid),
            (tabSj == 0) and 'Shared' or JobNameShort(tabSj),
            tier,
            ctx.name or '?'
        );
    end
end

-- Screen-space AABB of the current window's content region (for clipping embedded D3D / GDI crossbar draws).
local function GetCurrentWindowContentScreenRect()
    if not imgui.GetWindowPos or not imgui.GetWindowContentRegionMin or not imgui.GetWindowContentRegionMax then
        return nil;
    end
    local wx, wy = imgui.GetWindowPos();
    local cminX, cminY = imgui.GetWindowContentRegionMin();
    local cmaxX, cmaxY = imgui.GetWindowContentRegionMax();
    if wx == nil or cminX == nil or cmaxX == nil then
        return nil;
    end
    return wx + cminX, wy + cminY, wx + cmaxX, wy + cmaxY;
end

local function GetCurrentWindowScreenRect()
    if not imgui.GetWindowPos or not imgui.GetWindowSize then
        return nil;
    end
    local wx, wy = imgui.GetWindowPos();
    local ww, wh = imgui.GetWindowSize();
    if wx == nil or ww == nil then
        return nil;
    end
    return wx, wy, wx + ww, wy + wh;
end

local function IntersectRect(ax1, ay1, ax2, ay2, bx1, by1, bx2, by2)
    if not ax1 or not bx1 then
        return nil;
    end
    local x1 = math.max(ax1, bx1);
    local y1 = math.max(ay1, by1);
    local x2 = math.min(ax2, bx2);
    local y2 = math.min(ay2, by2);
    if x1 >= x2 or y1 >= y2 then
        return nil;
    end
    return x1, y1, x2, y2;
end

-- Pet Palette toggle per combo-mode segment (Edit Full Palette). Optional gold label (opts.showGoldLabel = false to omit).
local function DrawJobSegmentPetGlobalControls(storageKey, mode, label, cross, named, opts)
    opts = opts or {};
    local showGoldLabel = opts.showGoldLabel ~= false;
    local base = cross.comboModeSettings and cross.comboModeSettings[mode];
    if not base then
        base = { petAware = false, universalOverridePalette = nil };
    end
    if not named[storageKey] then
        named[storageKey] = {};
    end
    local ovr = named[storageKey][mode];

    local effPet = base.petAware == true;
    if ovr and ovr.petAware ~= nil then
        effPet = ovr.petAware == true;
    end

    if showGoldLabel and label and label ~= '' then
        imgui.TextColored(components.TAB_STYLE.gold, label);
    end
    local petBuf = { effPet };
    if imgui.Checkbox('Pet Palette##petxb_' .. mode, petBuf) then
        local newV = not effPet;
        if newV == (base.petAware == true) then
            if named[storageKey][mode] then
                named[storageKey][mode].petAware = nil;
            end
        else
            if not named[storageKey][mode] then named[storageKey][mode] = {}; end
            named[storageKey][mode].petAware = newV;
        end
        if SaveSettingsOnly then SaveSettingsOnly(); end
        if DeferredUpdateVisuals then DeferredUpdateVisuals(); end
    end
    imgui.ShowHelp('When enabled, this 8-slot group uses pet/avatar storage while a pet is active.');
end

-- Job [J] Edit Full Palette: segment override (Job-shared storage or Global [G] source). Primary L2/R2 omit via caller.
local SEGMENT_OVERRIDE_COMBO_W = 220;
-- Segment overrides are keyed per job in settings, but gameplay resolves using the *current* job id.
-- Global [G] redirects must therefore exist for every job id, or only the row you edited would work in-game.
local SEGMENT_OVERRIDE_JOB_MAX = 22;

local function ClearSegmentOverrideModeForAllJobs(cross, eff)
    if not cross or not cross.segmentOverrides or not eff then
        return;
    end
    for jid = 1, SEGMENT_OVERRIDE_JOB_MAX do
        local jks = tostring(jid);
        local modes = cross.segmentOverrides[jks];
        if modes and modes[eff] then
            modes[eff] = nil;
            if next(modes) == nil then
                cross.segmentOverrides[jks] = nil;
            end
        end
    end
    if cross.segmentOverrides and next(cross.segmentOverrides) == nil then
        cross.segmentOverrides = nil;
    end
end

-- One shared table for all jobs so palette name edits stay in sync in the UI.
local function ReplicateGlobalSegmentOverrideToAllJobs(cross, eff, globalPaletteName)
    if not cross then
        return;
    end
    if not cross.segmentOverrides then
        cross.segmentOverrides = {};
    end
    local gp = (type(globalPaletteName) == 'string' and globalPaletteName ~= '') and globalPaletteName or nil;
    local ent = { scope = 'global', globalPalette = gp };
    for jid = 1, SEGMENT_OVERRIDE_JOB_MAX do
        local jks = tostring(jid);
        if not cross.segmentOverrides[jks] then
            cross.segmentOverrides[jks] = {};
        end
        cross.segmentOverrides[jks][eff] = ent;
    end
end

-- Switching one job from Global to Job-shared must not mutate the shared global table (same ref on all jobs).
local function SplitGlobalSegmentToJobSharedForOneJob(cross, eff, editedJkStr, globalPaletteName)
    if not cross then
        return;
    end
    if not cross.segmentOverrides then
        cross.segmentOverrides = {};
    end
    local gp = (type(globalPaletteName) == 'string' and globalPaletteName ~= '') and globalPaletteName or nil;
    for jid = 1, SEGMENT_OVERRIDE_JOB_MAX do
        local jks = tostring(jid);
        if not cross.segmentOverrides[jks] then
            cross.segmentOverrides[jks] = {};
        end
        if jks == editedJkStr then
            cross.segmentOverrides[jks][eff] = { scope = 'jobShared' };
        else
            cross.segmentOverrides[jks][eff] = { scope = 'global', globalPalette = gp };
        end
    end
end

-- Persist full job rows for legacy configs that only stored Global on one job id.
-- Do not run when any job uses Job-shared for this segment (valid per-job mix with others on Global).
local function ReconcileGlobalSegmentOverrideRows(cross, eff)
    if not cross or not eff then
        return;
    end
    if not cross.segmentOverrides then
        return;
    end
    local gp;
    local anyJobShared = false;
    for jid = 1, SEGMENT_OVERRIDE_JOB_MAX do
        local s = cross.segmentOverrides[tostring(jid)] and cross.segmentOverrides[tostring(jid)][eff];
        if s and s.scope == 'jobShared' then
            anyJobShared = true;
        elseif s and s.scope == 'global' and type(s.globalPalette) == 'string' and s.globalPalette ~= '' then
            gp = s.globalPalette;
        end
    end
    if anyJobShared or not gp then
        return;
    end
    for jid = 1, SEGMENT_OVERRIDE_JOB_MAX do
        local s = cross.segmentOverrides[tostring(jid)] and cross.segmentOverrides[tostring(jid)][eff];
        if not s or s.scope ~= 'global' or s.globalPalette ~= gp then
            ReplicateGlobalSegmentOverrideToAllJobs(cross, eff, gp);
            if SaveSettingsOnly then
                SaveSettingsOnly();
            end
            return;
        end
    end
end

local function DrawJobSegmentOverrideCheckboxRow(jobId, comboMode, cross, idSuffix, _columnMaxW)
    if not jobId or not cross then
        return;
    end
    local eff = data.GetEffectiveComboModeForStorage(comboMode);
    if eff == 'L2' or eff == 'R2' then
        return;
    end
    if not cross.segmentOverrides then
        cross.segmentOverrides = {};
    end
    local jk = tostring(jobId);
    if not cross.segmentOverrides[jk] then
        cross.segmentOverrides[jk] = {};
    end
    local ent = cross.segmentOverrides[jk][eff];
    local enabled = ent ~= nil and ent.scope ~= nil;

    imgui.PushID('segov_' .. (idSuffix or 'm') .. '_' .. eff);
    local ovBuf = { enabled };
    if imgui.Checkbox('Override##ovren', ovBuf) then
        if ovBuf[1] then
            cross.segmentOverrides[jk][eff] = { scope = 'jobShared' };
        else
            if ent and ent.scope == 'global' then
                ClearSegmentOverrideModeForAllJobs(cross, eff);
            else
                cross.segmentOverrides[jk][eff] = nil;
                if next(cross.segmentOverrides[jk]) == nil then
                    cross.segmentOverrides[jk] = nil;
                end
                if next(cross.segmentOverrides) == nil then
                    cross.segmentOverrides = nil;
                end
            end
        end
        if SaveSettingsOnly then
            SaveSettingsOnly();
        end
        data.InvalidateCrossbarDraftLayout();
        if DeferredUpdateVisuals then
            DeferredUpdateVisuals();
        end
    end
    imgui.SameLine();
    imgui.ShowHelp(
        'Override: use one shared bar for this trigger segment across palettes (job-wide), or bind to a Global [G] palette so the same slots appear on every job. Global [G] applies to all jobs in-game (same redirect for every job id). Does not duplicate palette data; it redirects where slots load and save.'
    );
    imgui.PopID();
end

local function DrawJobSegmentOverrideDetailBlock(jobId, comboMode, cross, idSuffix, columnMaxW)
    if not jobId or not cross then
        return;
    end
    local comboW = SEGMENT_OVERRIDE_COMBO_W;
    if columnMaxW and columnMaxW > 40 then
        comboW = math.min(SEGMENT_OVERRIDE_COMBO_W, columnMaxW - 8);
    end
    local eff = data.GetEffectiveComboModeForStorage(comboMode);
    if eff == 'L2' or eff == 'R2' then
        return;
    end
    local jk = tostring(jobId);
    local ent = cross.segmentOverrides and cross.segmentOverrides[jk] and cross.segmentOverrides[jk][eff];
    if not ent or not ent.scope then
        return;
    end

    imgui.PushID('segdet_' .. (idSuffix or 'm') .. '_' .. eff);
    imgui.Dummy({ 0, 2 });
    if imgui.RadioButton('Job-shared##rj_' .. eff, ent.scope == 'jobShared') then
        if ent.scope == 'global' then
            local gp = (type(ent.globalPalette) == 'string' and ent.globalPalette ~= '') and ent.globalPalette or nil;
            local names = palette.GetUniversalCrossbarPaletteNamesOrdered and palette.GetUniversalCrossbarPaletteNamesOrdered() or {};
            if (not gp or gp == '') and names[1] then
                gp = names[1];
            end
            SplitGlobalSegmentToJobSharedForOneJob(cross, eff, jk, gp);
        else
            ent.scope = 'jobShared';
            ent.globalPalette = nil;
        end
        if SaveSettingsOnly then
            SaveSettingsOnly();
        end
        data.InvalidateCrossbarDraftLayout();
        if DeferredUpdateVisuals then
            DeferredUpdateVisuals();
        end
    end
    imgui.SameLine(0, 12);
    if imgui.RadioButton('Global [G]##rg_' .. eff, ent.scope == 'global') then
        local names = palette.GetUniversalCrossbarPaletteNamesOrdered and palette.GetUniversalCrossbarPaletteNamesOrdered() or {};
        local gp = (type(ent.globalPalette) == 'string' and ent.globalPalette ~= '') and ent.globalPalette or nil;
        if (not gp or gp == '') and names[1] then
            gp = names[1];
        end
        ReplicateGlobalSegmentOverrideToAllJobs(cross, eff, gp);
        if SaveSettingsOnly then
            SaveSettingsOnly();
        end
        data.InvalidateCrossbarDraftLayout();
        if DeferredUpdateVisuals then
            DeferredUpdateVisuals();
        end
    end

    if ent.scope == 'global' then
        imgui.Dummy({ 0, 4 });
        imgui.PushItemWidth(comboW);
        local names = palette.GetUniversalCrossbarPaletteNamesOrdered and palette.GetUniversalCrossbarPaletteNamesOrdered() or {};
        local preview = (type(ent.globalPalette) == 'string' and ent.globalPalette ~= '') and ent.globalPalette or '(select)';
        if imgui.BeginCombo('Palette##gp_' .. eff, preview, 0) then
            for _, nm in ipairs(names) do
                if imgui.Selectable(nm, nm == ent.globalPalette) then
                    ReplicateGlobalSegmentOverrideToAllJobs(cross, eff, nm);
                    if SaveSettingsOnly then
                        SaveSettingsOnly();
                    end
                    data.InvalidateCrossbarDraftLayout();
                    if DeferredUpdateVisuals then
                        DeferredUpdateVisuals();
                    end
                end
            end
            imgui.EndCombo();
        end
        imgui.PopItemWidth();
        imgui.SameLine(0, 8);
        imgui.TextColored({ 0.7, 0.68, 0.6, 1.0 }, 'Palette');
    end

    imgui.Dummy({ 0, 4 });
    -- Job-shared: short manual lines only. Even with \n, a long first line still *soft-wraps* in narrow
    -- double-tap columns; when L2x2 and R2x2 both show this, line count could flicker and bounce scroll.
    if ent.scope == 'jobShared' then
        imgui.TextColored(
            { 0.92, 0.32, 0.32, 1.0 },
            'Job-shared crossbar:\nEdits apply to all\nnamed palettes\nfor this job on\nthis segment.'
        );
    elseif ent.scope == 'global' and type(ent.globalPalette) == 'string' and ent.globalPalette ~= '' then
        local wrapPushed = false;
        if columnMaxW and columnMaxW > 40 and imgui.PushTextWrapPos and imgui.GetCursorPosX then
            local cx = math.floor(imgui.GetCursorPosX() + 0.5);
            local w = math.floor(columnMaxW + 0.5) - 6;
            if w > 40 then
                imgui.PushTextWrapPos(cx + w);
                wrapPushed = true;
            end
        end
        imgui.PushStyleColor(ImGuiCol_Text, { 0.92, 0.32, 0.32, 1.0 });
        if imgui.TextWrapped then
            imgui.TextWrapped(
                'Global palette "'
                    .. ent.globalPalette
                    .. '": edits change that [G] set for everyone using it (including Universal crossbar when active).'
            );
        else
            imgui.TextColored(
                { 0.92, 0.32, 0.32, 1.0 },
                'Global palette "'
                    .. ent.globalPalette
                    .. '": edits change that [G] palette for everyone using it (including Universal crossbar when this set is active).'
            );
        end
        imgui.PopStyleColor(1);
        if wrapPushed and imgui.PopTextWrapPos then
            imgui.PopTextWrapPos();
        end
    end
    imgui.PopID();
end

-- Override + Pet on one row; when Override is on, Job/Global on the next row; Global adds palette row + warnings below.
-- maxWidth = that column’s usable width (keeps text/combo from spilling into the other half).
local function DrawJobSegmentFooterOverrideAndPet(storageKey, mode, cross, named, jobId, showOverride, idTag, maxWidth)
    maxWidth = maxWidth or 400;
    if not showOverride or not jobId then
        DrawJobSegmentPetGlobalControls(storageKey, mode, '', cross, named, { showGoldLabel = false });
        return;
    end

    imgui.PushID('ovpetblk_' .. idTag);
    if showOverride and jobId then
        local eff = data.GetEffectiveComboModeForStorage(mode);
        if eff ~= 'L2' and eff ~= 'R2' then
            ReconcileGlobalSegmentOverrideRows(cross, eff);
        end
    end
    -- Override | Pet on one row. Do not use imgui.Columns here (breaks the outer L2/R2 pair Columns).
    -- Height must NOT be 0: in ImGui, BeginChild(..., { w, 0 }) uses remaining vertical space and stretches
    -- the row to the bottom of the parent, leaving a huge empty band before Job/Global below.
    local gap = 6;
    local half = math.max(96, math.floor(((maxWidth - gap) * 0.5) + 0.5));
    local wRight = math.max(80, maxWidth - half - gap);
    local fh = (imgui.GetFrameHeightWithSpacing and imgui.GetFrameHeightWithSpacing())
        or ((imgui.GetFrameHeight and imgui.GetFrameHeight()) + GetItemSpacingY())
        or 26;
    local row1H = math.ceil(math.max(44, fh + 6));

    imgui.BeginChild('##ovpetL_' .. idTag, { half, row1H }, false);
    DrawJobSegmentOverrideCheckboxRow(jobId, mode, cross, idTag, half);
    imgui.EndChild();
    imgui.SameLine(0, gap);
    imgui.BeginChild('##ovpetR_' .. idTag, { wRight, row1H }, false);
    DrawJobSegmentPetGlobalControls(storageKey, mode, '', cross, named, { showGoldLabel = false });
    imgui.EndChild();

    DrawJobSegmentOverrideDetailBlock(jobId, mode, cross, idTag, maxWidth);

    imgui.PopID();
end

-- Full crossbar row using the same DrawSlot / slotrenderer path as the in-game crossbar (requires data.BeginCrossbarPaletteEditSession).
-- Clip rect is taken *inside* each row BeginChild only. Do not intersect with a scroll snapshot from before layout:
-- ContentRegionMax at the top of an empty scroll pane is wrong and would drop every row after the first.
local function DrawFullPaletteCrossbarPair(storageKey, modeLeft, modeRight, idFix, cs, parentClipX1, parentClipY1, parentClipX2, parentClipY2, drawPetFooters, cross, named, segmentOverrideJobId)
    local w, h, gw, ghgt = crossbar.GetEditorCrossbarRowDimensions(cs);
    local gs = w - 2 * gw;
    -- Action names render on top of slot icons (not above/below the grid); keep row padding compact.
    local rowPadTop = 14;
    local rowPadBottom = 14;
    local rowPadH = (cs.labelFontSize or 10) + 22;
    local rowPadLeft = rowPadH;
    local rowPadRight = rowPadH + 16;
    local rowHeight = ghgt + rowPadTop + rowPadBottom;
    local rowWidth = w + rowPadLeft + rowPadRight;
    local flags = 0;
    if ImGuiWindowFlags_NoScrollbar ~= nil then
        flags = ImGuiWindowFlags_NoScrollbar;
    end
    imgui.PushStyleColor(ImGuiCol_ChildBg, { 0.176, 0.161, 0.137, 0.95 });
    imgui.BeginChild('##xbpair_' .. idFix, { rowWidth, rowHeight }, true, flags);
    do
        local dlBg = imgui.GetWindowDrawList and imgui.GetWindowDrawList();
        local wx, wy = imgui.GetWindowPos();
        local ww, wh = imgui.GetWindowSize();
        if dlBg and wx and ww then
            dlBg:AddRectFilled({ wx, wy }, { wx + ww, wy + wh }, imgui.GetColorU32({ 0.176, 0.161, 0.137, 0.95 }), 4);
            dlBg:AddRect({ wx, wy }, { wx + ww, wy + wh }, imgui.GetColorU32(components.TAB_STYLE.gold), 4, 0, 1.5);
        end
    end
    local rowX1, rowY1, rowX2, rowY2 = GetCurrentWindowContentScreenRect();
    local dl = imgui.GetWindowDrawList and imgui.GetWindowDrawList();
    local pushedClip = false;
    local cx1, cy1, cx2, cy2 = rowX1, rowY1, rowX2, rowY2;
    if parentClipX1 then
        cx1, cy1, cx2, cy2 = IntersectRect(rowX1, rowY1, rowX2, rowY2, parentClipX1, parentClipY1, parentClipX2, parentClipY2);
    end
    if cx1 and dl and dl.PushClipRect then
        dl:PushClipRect({ cx1, cy1 }, { cx2, cy2 }, true);
        pushedClip = true;
    end
    local slotGridLeftScreenX = nil;
    local slotGridRightScreenX = nil;
    if cx1 then
        local px, py = imgui.GetCursorScreenPos();
        local drawOriginX = px + rowPadLeft;
        slotGridLeftScreenX = drawOriginX;
        slotGridRightScreenX = drawOriginX + gw + gs;
        local drawOriginY = py + rowPadTop;
        local dividerX = drawOriginX + (w / 2);
        if dl and dl.AddLine then
            dl:AddLine(
                { dividerX, drawOriginY + 10 },
                { dividerX, drawOriginY + ghgt - 10 },
                imgui.GetColorU32({ 1, 1, 1, 0.3 }),
                2
            );
        end
        local glyphMode = (idFix == 'dbl') and 'doubleTap' or (idFix == 'chord') and 'chordCombo' or 'primary';
        crossbar.DrawPaletteEditorL2R2TriggerGlyphs(drawOriginX, drawOriginY, cs, glyphMode);
        crossbar.DrawPaletteEditorL2R2Row(drawOriginX, drawOriginY, cs, modeLeft, modeRight, cx1, cy1, cx2, cy2);
    end
    if pushedClip and dl and dl.PopClipRect then
        dl:PopClipRect();
    end
    imgui.EndChild();
    imgui.PopStyleColor(1);
    if drawPetFooters and cross and named and slotGridLeftScreenX then
        imgui.Dummy({ 0, 6 });
        imgui.PushID('petfoot_' .. idFix);
        -- Match slot row width so L2/R2 footers align with the diamonds; ImGui columns draw the vertical separator between them
        local leftColW = rowPadLeft + (w / 2);
        local rightColW = rowWidth - leftColW;
        local cellPad = 10;
        local leftInner = math.max(120, leftColW - cellPad);
        local rightInner = math.max(120, rightColW - cellPad);

        -- Avoid nested BeginChild(..., height 0) inside the main scroll: auto-height stacking bugs / huge gaps on some ImGui builds.
        imgui.Columns(2, '##pairFootCols_' .. idFix, true);
        imgui.SetColumnWidth(0, leftColW);
        imgui.SetColumnWidth(1, rightColW);

        DrawJobSegmentFooterOverrideAndPet(
            storageKey,
            modeLeft,
            cross,
            named,
            segmentOverrideJobId,
            drawPetFooters and segmentOverrideJobId and idFix ~= 'pri',
            'L_' .. idFix,
            leftInner
        );
        imgui.NextColumn();
        DrawJobSegmentFooterOverrideAndPet(
            storageKey,
            modeRight,
            cross,
            named,
            segmentOverrideJobId,
            drawPetFooters and segmentOverrideJobId and idFix ~= 'pri',
            'R_' .. idFix,
            rightInner
        );
        imgui.Columns(1);

        imgui.Dummy({ 0, 10 });
        imgui.PopID();
    end
end

-- Single 8-slot group (shared chord bar): one double-diamond wide
local function DrawFullPaletteSingleCrossbarGroup(storageKey, comboMode, idFix, cs, parentClipX1, parentClipY1, parentClipX2, parentClipY2, drawPetFooters, cross, named, segmentOverrideJobId)
    local w, h, gw, ghgt = crossbar.GetEditorCrossbarRowDimensions(cs);
    local rowPadTop = 14;
    local rowPadBottom = 14;
    local rowPadH = (cs.labelFontSize or 10) + 22;
    local rowPadLeft = rowPadH;
    local rowPadRight = rowPadH + 16;
    local rowHeight = ghgt + rowPadTop + rowPadBottom;
    local rowWidth = gw + rowPadLeft + rowPadRight;
    local flags = 0;
    if ImGuiWindowFlags_NoScrollbar ~= nil then
        flags = ImGuiWindowFlags_NoScrollbar;
    end
    imgui.PushStyleColor(ImGuiCol_ChildBg, { 0.176, 0.161, 0.137, 0.95 });
    imgui.BeginChild('##xbone_' .. idFix, { rowWidth, rowHeight }, true, flags);
    do
        local dlBg = imgui.GetWindowDrawList and imgui.GetWindowDrawList();
        local wx, wy = imgui.GetWindowPos();
        local ww, wh = imgui.GetWindowSize();
        if dlBg and wx and ww then
            dlBg:AddRectFilled({ wx, wy }, { wx + ww, wy + wh }, imgui.GetColorU32({ 0.176, 0.161, 0.137, 0.95 }), 4);
            dlBg:AddRect({ wx, wy }, { wx + ww, wy + wh }, imgui.GetColorU32(components.TAB_STYLE.gold), 4, 0, 1.5);
        end
    end
    local rowX1, rowY1, rowX2, rowY2 = GetCurrentWindowContentScreenRect();
    local dl = imgui.GetWindowDrawList and imgui.GetWindowDrawList();
    local pushedClip = false;
    local cx1, cy1, cx2, cy2 = rowX1, rowY1, rowX2, rowY2;
    if parentClipX1 then
        cx1, cy1, cx2, cy2 = IntersectRect(rowX1, rowY1, rowX2, rowY2, parentClipX1, parentClipY1, parentClipX2, parentClipY2);
    end
    if cx1 and dl and dl.PushClipRect then
        dl:PushClipRect({ cx1, cy1 }, { cx2, cy2 }, true);
        pushedClip = true;
    end
    local slotGridLeftScreenX = nil;
    if cx1 then
        local px, py = imgui.GetCursorScreenPos();
        local drawOriginX = px + rowPadLeft;
        slotGridLeftScreenX = drawOriginX;
        local drawOriginY = py + rowPadTop;
        crossbar.DrawPaletteEditorSharedChordTriggerGlyphs(drawOriginX, drawOriginY, cs);
        crossbar.DrawPaletteEditorSingleRow(drawOriginX, drawOriginY, cs, comboMode, cx1, cy1, cx2, cy2);
    end
    if pushedClip and dl and dl.PopClipRect then
        dl:PopClipRect();
    end
    imgui.EndChild();
    imgui.PopStyleColor(1);
    if drawPetFooters and cross and named and slotGridLeftScreenX then
        imgui.Dummy({ 0, 6 });
        imgui.PushID('petfoot_' .. idFix);
        DrawJobSegmentFooterOverrideAndPet(
            storageKey,
            comboMode,
            cross,
            named,
            segmentOverrideJobId,
            drawPetFooters and segmentOverrideJobId,
            'S_' .. idFix,
            math.max(160, rowWidth - 16)
        );
        imgui.Dummy({ 0, 10 });
        imgui.PopID();
    end
end

local function DrawEmbeddedCrossbarComboModesPopup()
    if not embedCrossbarComboCtx then
        embedCrossbarComboWinOpen[1] = false;
        embedCrossbarComboWinGraceFrames = 0;
        embedCrossbarComboHasDrawn = false;
        editFullPaletteScrollHCached = nil;
        return;
    end

    local ctx = embedCrossbarComboCtx;
    local cross = gConfig and gConfig.hotbarCrossbar;
    if not cross then
        embedCrossbarComboCtx = nil;
        embedCrossbarComboWinOpen[1] = false;
        embedCrossbarComboWinGraceFrames = 0;
        embedCrossbarComboHasDrawn = false;
        editFullPaletteScrollHCached = nil;
        return;
    end

    embedCrossbarComboWinGraceFrames = embedCrossbarComboWinGraceFrames + 1;

    -- Min/max every frame. Position + size only on the *first draw* of an open window (grace == 1).
    -- Re-applying SetNextWindowSize/Pos every frame with Appearing fights layout and resets the inner scroll.
    local wMin = EDIT_FULL_PALETTE_WIN_W_MIN;
    local wMax = EDIT_FULL_PALETTE_WIN_W_MAX;
    if EDIT_FULL_PALETTE_WIN_LOCK_WIDTH then
        wMin = EDIT_FULL_PALETTE_WIN_W;
        wMax = EDIT_FULL_PALETTE_WIN_W;
    end
    local hMin = EDIT_FULL_PALETTE_WIN_H_MIN;
    local hMax = EDIT_FULL_PALETTE_WIN_H_MAX;
    if EDIT_FULL_PALETTE_WIN_LOCK_HEIGHT then
        hMin = EDIT_FULL_PALETTE_WIN_H_DEFAULT;
        hMax = EDIT_FULL_PALETTE_WIN_H_DEFAULT;
    end
    imgui.SetNextWindowSizeConstraints({ wMin, hMin }, { wMax, hMax });

    do
        local applySavedGeom = (embedCrossbarComboWinGraceFrames == 1);
        if applySavedGeom then
            local saved = gConfig and gConfig.windowPositions and gConfig.windowPositions[EDIT_FULL_PALETTE_WINDOW_KEY];
            local geomOnce = ImGuiCond_Always;
            if saved and saved.x and saved.y then
                imgui.SetNextWindowPos({ saved.x, saved.y }, geomOnce);
            else
                local g = rawget(_G, '_XIUI_CONFIG_LAST_GEOM');
                if type(g) == 'table' and g[1] and g[2] then
                    imgui.SetNextWindowPos({ g[1] + 36, g[2] + 36 }, geomOnce);
                end
            end

            local sw = EDIT_FULL_PALETTE_WIN_W;
            local sh = EDIT_FULL_PALETTE_WIN_H_DEFAULT;
            if saved and type(saved.w) == 'number' and saved.w > 0 then
                sw = math.max(wMin, math.min(wMax, saved.w));
            end
            if saved and type(saved.h) == 'number' and saved.h > 0 then
                sh = math.max(hMin, math.min(hMax, saved.h));
            end
            imgui.SetNextWindowSize({ sw, sh }, geomOnce);
        end
    end
    local winFlags = ImGuiWindowFlags_None;
    if ImGuiWindowFlags_NoSavedSettings ~= nil and bit and bit.bor then
        winFlags = bit.bor(winFlags, ImGuiWindowFlags_NoSavedSettings);
    end
    if ImGuiWindowFlags_NoDocking ~= nil and bit and bit.bor then
        winFlags = bit.bor(winFlags, ImGuiWindowFlags_NoDocking);
    end
    -- Only the inner ##xbFullPalScroll should scroll; outer window scrollbar fights it and feels like “jumping”.
    if ImGuiWindowFlags_NoScrollbar ~= nil and bit and bit.bor then
        winFlags = bit.bor(winFlags, ImGuiWindowFlags_NoScrollbar);
    end

    local kind = ctx.kind or 'job';
    local scopeLine = BuildEmbedFullPaletteScopeLine(ctx, kind);
    local winTitle = 'Edit Full Palette - ' .. scopeLine .. '###xbEmbCombWin';

    if imgui.Begin(winTitle, embedCrossbarComboWinOpen, winFlags) then
    embedCrossbarComboHasDrawn = true;
    do
        local wx, wy = imgui.GetWindowPos();
        local ww, wh = imgui.GetWindowSize();
        if wx and wy and ww and wh then
            if not gConfig.windowPositions then gConfig.windowPositions = {}; end
            gConfig.windowPositions[EDIT_FULL_PALETTE_WINDOW_KEY] = { x = wx, y = wy, w = ww, h = wh };
        end
    end
    local storageKey = GetEmbedFullPaletteStorageKey(ctx);
    local editJobId = (kind == 'job') and (ctx.jobId or data.jobId) or nil;
    data.BeginCrossbarPaletteEditSession(storageKey, editJobId);
    if not embedCrossbarComboWinOpen[1] and data.IsDraftDirty() then
        embedCrossbarComboWinOpen[1] = true;
        openUnsavedChangesPopup = true;
    end
    local editCross = BuildEditFullPaletteViewSettings(cross);

    if not cross.namedPaletteComboModeSettings then
        cross.namedPaletteComboModeSettings = {};
    end
    local named = cross.namedPaletteComboModeSettings;
    local segmentOverrideJobId = (kind == 'job') and (ctx.jobId or 1) or nil;

    -- Header row 1: Macro Manager button + description
    components.PushMacroManagerButtonStyle();
    if imgui.Button('Macro Manager##xbEmbCombMacro') then
        macropalette.OpenPalette();
    end
    components.PopMacroManagerButtonStyle();
    imgui.SameLine();
    imgui.TextColored({ 0.62, 0.6, 0.55, 1.0 }, 'Right-click a slot to clear; drag macros or slots to rearrange. Double-click to edit.');

    -- Header row 2: Job/scope label + "not in use" warning
    do
        local jobLabel;
        if kind == 'universal' then
            jobLabel = 'Global [G]';
        else
            local jid = ctx.jobId or 1;
            jobLabel = jobs[jid] or ('Job ' .. tostring(jid));
        end
        imgui.TextColored(components.TAB_STYLE.gold, jobLabel);
        imgui.SameLine(0, 12);
        imgui.TextColored({ 0.62, 0.6, 0.55, 1.0 }, 'Palette:');
        imgui.SameLine(0, 4);
        imgui.TextColored({ 0.85, 0.82, 0.72, 1.0 }, '"' .. (ctx.name or '?') .. '"');

        local activeScope = palette.GetCrossbarPaletteScope and palette.GetCrossbarPaletteScope() or 'job';
        local activeName = palette.GetActivePaletteForCombo and palette.GetActivePaletteForCombo('L2') or nil;
        local isActive = false;
        if kind == 'universal' and activeScope == 'universal' then
            isActive = (activeName == ctx.name);
        elseif kind == 'job' and activeScope == 'job' then
            isActive = (activeName == ctx.name);
        end
        if not isActive then
            imgui.SameLine(0, 16);
            imgui.TextColored({ 0.95, 0.78, 0.25, 1.0 }, 'This palette is not currently in use.');
        end
    end

    -- Header row 3: Quick palette switcher (selection only)
    do
        local paletteNames;
        if kind == 'universal' then
            paletteNames = palette.GetUniversalCrossbarPaletteNamesOrdered and palette.GetUniversalCrossbarPaletteNamesOrdered() or {};
        else
            paletteNames = palette.GetCrossbarPaletteNamesForOrderTier and palette.GetCrossbarPaletteNamesForOrderTier(ctx.jobId or 1, tonumber(ctx.st) or 0) or {};
        end
        if #paletteNames > 1 then
            imgui.TextColored({ 0.62, 0.6, 0.55, 1.0 }, 'Switch Palette:');
            imgui.SameLine(0, 6);
            imgui.PushStyleColor(ImGuiCol_FrameBg, { 0.10, 0.09, 0.07, 1.0 });
            imgui.PushStyleColor(ImGuiCol_FrameBgHovered, { 0.14, 0.13, 0.11, 1.0 });
            imgui.PushStyleColor(ImGuiCol_FrameBgActive, { 0.14, 0.13, 0.11, 1.0 });
            imgui.SetNextItemWidth(200);
            if imgui.BeginCombo('##xbEditPalSwitch', ctx.name or '?') then
                for _, pName in ipairs(paletteNames) do
                    local isSel = (pName == ctx.name);
                    if isSel then
                        imgui.PushStyleColor(ImGuiCol_Text, components.TAB_STYLE.gold);
                    end
                    if imgui.Selectable(pName, isSel) then
                        if pName ~= ctx.name then
                            if data.IsDraftDirty() then
                                pendingPaletteSwitchName = pName;
                                openUnsavedChangesPopup = true;
                            else
                                data.FullyClosePaletteEditSession();
                                crossbar.HidePaletteEditorPrimitives();
                                ctx.name = pName;
                                editFullPaletteScrollHCached = nil;
                                embedCrossbarComboWinGraceFrames = 0;
                            end
                        end
                    end
                    if isSel then
                        imgui.PopStyleColor();
                        imgui.SetItemDefaultFocus();
                    end
                end
                imgui.EndCombo();
            end
            imgui.PopStyleColor(3);
        end
    end
    imgui.Spacing();

    -- Scroll region height: cache + quantized avail (see GetContentRegionAvailHeight). Refresh when the user
    -- resizes the outer window enough; avoids 1px jitter resetting scroll.
    do
        local regionBelowHeaderH = GetContentRegionAvailHeight();
        local computed = math.max(120, math.floor(regionBelowHeaderH - EDIT_FULL_PALETTE_FOOTER_BLOCK_H + 0.5));
        if embedCrossbarComboWinGraceFrames == 1 or editFullPaletteScrollHCached == nil then
            editFullPaletteScrollHCached = computed;
        elseif math.abs(computed - editFullPaletteScrollHCached) >= 8 then
            editFullPaletteScrollHCached = computed;
        end
    end
    -- Always reserve the scrollbar gutter: when optional override rows appear/disappear, content height crosses
    -- the "needs scroll" threshold and the bar popping in/out reflows text width and bounces scroll to top.
    local xbScrollFlags = 0;
    if ImGuiWindowFlags_AlwaysVerticalScrollbar ~= nil then
        xbScrollFlags = ImGuiWindowFlags_AlwaysVerticalScrollbar;
    end
    imgui.BeginChild('##xbFullPalScroll', { 0, editFullPaletteScrollHCached or 200 }, true, xbScrollFlags);
    local scrollX1, scrollY1, scrollX2, scrollY2 = GetCurrentWindowScreenRect();

    local function sectionHeader(text)
        imgui.Spacing();
        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();
        imgui.TextColored(components.TAB_STYLE.gold, text);
    end

    sectionHeader('Primary (hold L2 / R2)');
    DrawFullPaletteCrossbarPair(storageKey, 'L2', 'R2', 'pri', editCross, scrollX1, scrollY1, scrollX2, scrollY2, kind == 'job', cross, named, segmentOverrideJobId);

    sectionHeader('Double-tap (L2x2 / R2x2)');
    if not cross.enableDoubleTap then
        imgui.BeginDisabled();
        imgui.TextColored({ 0.55, 0.55, 0.55, 1.0 }, 'Enable Double-Tap in Controller Settings to use these bars.');
        imgui.EndDisabled();
    else
        DrawFullPaletteCrossbarPair(storageKey, 'L2x2', 'R2x2', 'dbl', editCross, scrollX1, scrollY1, scrollX2, scrollY2, kind == 'job', cross, named, segmentOverrideJobId);
    end

    sectionHeader('Chord (L2+R2 / R2+L2)');
    if not cross.enableExpandedCrossbar then
        imgui.BeginDisabled();
        imgui.TextColored({ 0.55, 0.55, 0.55, 1.0 }, 'Enable L2+R2 / R2+L2 in Controller Settings to use these bars.');
        imgui.EndDisabled();
    elseif cross.useSharedExpandedBar then
        imgui.TextColored({ 0.7, 0.68, 0.6, 1.0 }, 'Shared expanded bar: L2+R2 and R2+L2 use the same 8 slots.');
        DrawFullPaletteSingleCrossbarGroup(storageKey, 'L2R2', 'chsh', editCross, scrollX1, scrollY1, scrollX2, scrollY2, kind == 'job', cross, named, segmentOverrideJobId);
    else
        DrawFullPaletteCrossbarPair(storageKey, 'L2R2', 'R2L2', 'chord', editCross, scrollX1, scrollY1, scrollX2, scrollY2, kind == 'job', cross, named, segmentOverrideJobId);
    end

    -- Minimal tail for clip clearance (large Dummy = empty scroll band + jumpy thumb at max scroll).
    imgui.Dummy({ 0, 10 });
    imgui.EndChild();

    -- After slots draw: open macro editor from double-click (same frame as SetPending)
    local pendingEdit = data.ConsumePendingPaletteSlotEdit();
    if pendingEdit then
        macropalette.OpenEditorForSlotData(pendingEdit.slotData);
        -- hotbar.DrawPalette runs before paletteManager; draw editor here so it appears same frame.
        if macropalette.DrawMacroEditor then
            macropalette.DrawMacroEditor();
        end
    end

    -- Footer: Undo + Apply + Close
    local isDirty = data.IsDraftDirty();
    local canUndo = data.CanUndoDraft();
    if not canUndo then
        imgui.PushStyleColor(ImGuiCol_Button, { 0.20, 0.20, 0.20, 1.0 });
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.20, 0.20, 0.20, 1.0 });
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.20, 0.20, 0.20, 1.0 });
    else
        imgui.PushStyleColor(ImGuiCol_Button, { 0.35, 0.30, 0.18, 1.0 });
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.45, 0.38, 0.22, 1.0 });
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.28, 0.24, 0.14, 1.0 });
    end
    if imgui.Button('Undo##xbEmbUndo', { 70, 0 }) and canUndo then
        data.UndoDraft();
    end
    imgui.PopStyleColor(3);
    imgui.SameLine();
    if isDirty then
        imgui.PushStyleColor(ImGuiCol_Button, { 0.22, 0.55, 0.22, 1.0 });
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.28, 0.65, 0.28, 1.0 });
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.16, 0.44, 0.16, 1.0 });
    else
        imgui.PushStyleColor(ImGuiCol_Button, { 0.20, 0.20, 0.20, 1.0 });
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.20, 0.20, 0.20, 1.0 });
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.20, 0.20, 0.20, 1.0 });
    end
    if imgui.Button('Apply Changes##xbEmbApply', { 140, 0 }) then
        if isDirty then
            data.ApplyDraft();
        end
    end
    imgui.PopStyleColor(3);
    imgui.SameLine();
    if imgui.Button('Close##xbEmbCombClose', { 80, 0 }) then
        if isDirty then
            openUnsavedChangesPopup = true;
        else
            embedCrossbarComboWinOpen[1] = false;
        end
    end
    if isDirty then
        imgui.SameLine();
        imgui.TextColored({ 0.9, 0.75, 0.3, 1.0 }, 'Unsaved changes');
    end

    -- Unsaved changes modal
    if openUnsavedChangesPopup then
        imgui.OpenPopup('Unsaved Changes##xbUnsavedModal');
        openUnsavedChangesPopup = false;
    end
    imgui.SetNextWindowSize({ 420, 0 }, ImGuiCond_Appearing);
    if imgui.BeginPopupModal('Unsaved Changes##xbUnsavedModal', nil, ImGuiWindowFlags_AlwaysAutoResize) then
        local isSwitching = (pendingPaletteSwitchName ~= nil);
        if isSwitching then
            imgui.TextWrapped('You have unsaved changes. Apply before switching palettes?');
        else
            imgui.TextWrapped('You have unsaved changes. Apply changes before closing?');
        end
        imgui.Spacing();
        local applyLabel = isSwitching and 'Apply & Switch' or 'Apply & Close';
        if imgui.Button(applyLabel .. '##xbUnsavedApply', { 130, 0 }) then
            data.ApplyDraft();
            if isSwitching then
                data.FullyClosePaletteEditSession();
                crossbar.HidePaletteEditorPrimitives();
                ctx.name = pendingPaletteSwitchName;
                editFullPaletteScrollHCached = nil;
                embedCrossbarComboWinGraceFrames = 0;
                pendingPaletteSwitchName = nil;
            else
                embedCrossbarComboWinOpen[1] = false;
            end
            imgui.CloseCurrentPopup();
        end
        imgui.SameLine();
        if imgui.Button('Discard##xbUnsavedDiscard', { 100, 0 }) then
            data.DiscardDraft();
            if isSwitching then
                data.FullyClosePaletteEditSession();
                crossbar.HidePaletteEditorPrimitives();
                ctx.name = pendingPaletteSwitchName;
                editFullPaletteScrollHCached = nil;
                embedCrossbarComboWinGraceFrames = 0;
                pendingPaletteSwitchName = nil;
            else
                embedCrossbarComboWinOpen[1] = false;
            end
            imgui.CloseCurrentPopup();
        end
        imgui.SameLine();
        if imgui.Button('Cancel##xbUnsavedCancel', { 100, 0 }) then
            pendingPaletteSwitchName = nil;
            imgui.CloseCurrentPopup();
        end
        imgui.EndPopup();
    end

    data.EndCrossbarPaletteEditSession();
    imgui.End();
    else
        data.EndCrossbarPaletteEditSession();
        crossbar.HidePaletteEditorPrimitives();
    end

    if not embedCrossbarComboWinOpen[1] then
        if embedCrossbarComboHasDrawn or embedCrossbarComboWinGraceFrames > 8 then
            embedCrossbarComboCtx = nil;
            embedCrossbarComboWinGraceFrames = 0;
            embedCrossbarComboHasDrawn = false;
            editFullPaletteScrollHCached = nil;
            data.FullyClosePaletteEditSession();
            crossbar.HidePaletteEditorPrimitives();
        end
    end
end

local function GetCrossbarModalStorageSubjob()
    if windowState.selectedPaletteType == 'crossbar' and modalState.crossbarOperationSubjob ~= nil then
        return modalState.crossbarOperationSubjob;
    end
    return windowState.selectedSubjobId;
end

local function ClearCrossbarEmbedModalFields()
    modalState.crossbarOperationSubjob = nil;
    modalState.crossbarCopyFromSubjob = nil;
    modalState.embedCrossbarUniversal = false;
    modalState.embedCrossbarUniversalCopy = false;
    modalState.copyDestScope = 'job';
end

-- ImGui Selectable uses Header colors; push muted gold for unselected rows so hover is visible (font lacks em dash glyph; use ASCII in UI strings).
local function PushPaletteRowStyle(isSelected)
    local gold = components.TAB_STYLE.gold;
    if isSelected then
        imgui.PushStyleColor(ImGuiCol_Header, { gold[1], gold[2], gold[3], 0.4 });
        imgui.PushStyleColor(ImGuiCol_HeaderHovered, { gold[1], gold[2], gold[3], 0.5 });
        imgui.PushStyleColor(ImGuiCol_HeaderActive, { gold[1], gold[2], gold[3], 0.6 });
    else
        imgui.PushStyleColor(ImGuiCol_Header, { gold[1], gold[2], gold[3], 0.08 });
        imgui.PushStyleColor(ImGuiCol_HeaderHovered, { gold[1], gold[2], gold[3], 0.22 });
        imgui.PushStyleColor(ImGuiCol_HeaderActive, { gold[1], gold[2], gold[3], 0.32 });
    end
end

local function PopPaletteRowStyle()
    imgui.PopStyleColor(3);
end

-- Same palette as config.lua DrawWindow so the floating manager matches XIUI when drawn from d3d_present
local function PushXiuiFloatingWindowTheme()
    local gold = components.TAB_STYLE.gold;
    local goldDark = {0.765, 0.684, 0.474, 1.0};
    local goldDarker = {0.573, 0.512, 0.355, 1.0};
    local bgDark = {0.051, 0.051, 0.051, 0.95};
    local bgMedium = components.TAB_STYLE.bgMedium;
    local bgLight = components.TAB_STYLE.bgLight;
    local bgLighter = components.TAB_STYLE.bgLighter;
    local textLight = {0.878, 0.855, 0.812, 1.0};
    local borderDark = {0.3, 0.275, 0.235, 1.0};
    local bgColor = bgDark;
    local buttonColor = bgMedium;
    local buttonHoverColor = bgLight;
    local buttonActiveColor = bgLighter;
    local tabColor = bgMedium;
    local tabHoverColor = bgLight;
    local tabActiveColor = {gold[1], gold[2], gold[3], 0.3};
    local borderColor = borderDark;
    local textColor = textLight;

    imgui.PushStyleColor(ImGuiCol_WindowBg, bgColor);
    imgui.PushStyleColor(ImGuiCol_ChildBg, {0, 0, 0, 0});
    imgui.PushStyleColor(ImGuiCol_TitleBg, bgMedium);
    imgui.PushStyleColor(ImGuiCol_TitleBgActive, bgLight);
    imgui.PushStyleColor(ImGuiCol_TitleBgCollapsed, bgDark);
    imgui.PushStyleColor(ImGuiCol_FrameBg, bgMedium);
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, bgLight);
    imgui.PushStyleColor(ImGuiCol_FrameBgActive, bgLighter);
    imgui.PushStyleColor(ImGuiCol_Header, bgLight);
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, bgLighter);
    imgui.PushStyleColor(ImGuiCol_HeaderActive, {gold[1], gold[2], gold[3], 0.3});
    imgui.PushStyleColor(ImGuiCol_Border, borderColor);
    imgui.PushStyleColor(ImGuiCol_Text, textColor);
    imgui.PushStyleColor(ImGuiCol_TextDisabled, goldDark);
    imgui.PushStyleColor(ImGuiCol_Button, buttonColor);
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, buttonHoverColor);
    imgui.PushStyleColor(ImGuiCol_ButtonActive, buttonActiveColor);
    imgui.PushStyleColor(ImGuiCol_CheckMark, gold);
    imgui.PushStyleColor(ImGuiCol_SliderGrab, goldDark);
    imgui.PushStyleColor(ImGuiCol_SliderGrabActive, gold);
    imgui.PushStyleColor(ImGuiCol_ScrollbarBg, bgMedium);
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrab, bgLighter);
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabHovered, borderDark);
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabActive, goldDark);
    imgui.PushStyleColor(ImGuiCol_Separator, borderDark);
    imgui.PushStyleColor(ImGuiCol_PopupBg, bgMedium);
    imgui.PushStyleColor(ImGuiCol_Tab, tabColor);
    imgui.PushStyleColor(ImGuiCol_TabHovered, tabHoverColor);
    imgui.PushStyleColor(ImGuiCol_TabActive, tabActiveColor);
    imgui.PushStyleColor(ImGuiCol_TabUnfocused, bgDark);
    imgui.PushStyleColor(ImGuiCol_TabUnfocusedActive, bgMedium);
    imgui.PushStyleColor(ImGuiCol_ResizeGrip, goldDarker);
    imgui.PushStyleColor(ImGuiCol_ResizeGripHovered, goldDark);
    imgui.PushStyleColor(ImGuiCol_ResizeGripActive, gold);

    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {12, 12});
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {6, 4});
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {8, 6});
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 4.0);
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 6.0);
    imgui.PushStyleVar(ImGuiStyleVar_ChildRounding, 4.0);
    imgui.PushStyleVar(ImGuiStyleVar_PopupRounding, 4.0);
    imgui.PushStyleVar(ImGuiStyleVar_ScrollbarRounding, 4.0);
    imgui.PushStyleVar(ImGuiStyleVar_GrabRounding, 4.0);
end

local function PopXiuiFloatingWindowTheme()
    imgui.PopStyleVar(9);
    imgui.PopStyleColor(34);
end

local function GetCopyDestinationNamesForModal()
    local j = modalState.copyTargetJobId or 1;
    local s = modalState.copyTargetSubjobId or 0;
    if windowState.selectedPaletteType == 'hotbar' then
        return palette.GetAvailablePalettes(1, j, s);
    end
    if modalState.copyDestScope == 'universal' then
        return palette.GetUniversalCrossbarPaletteNamesOrdered();
    end
    return palette.GetCrossbarPaletteNamesForOrderTier(j, s);
end

-- Get job name from ID (uses libs/jobs.lua)
local function GetJobName(jobId)
    if jobId == 0 then return 'Shared'; end
    return jobs[jobId] or ('Job ' .. jobId);
end

local function GetCrossbarPaletteJobIconTheme()
    local c = gConfig and gConfig.hotbarCrossbar;
    local t = c and c.paletteJobIconTheme;
    if t == 'Classic' or t == 'FFXI' or t == 'FFXIV-1' or t == 'ClassicFFXIV' then
        return t;
    end
    return 'Classic';
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

local function DrawStatusMessage()
    if not windowState.statusMessage then return; end
    if os.clock() - windowState.statusMessageTime < 3 then
        imgui.Spacing();
        imgui.TextColored({ 1.0, 0.6, 0.3, 1.0 }, windowState.statusMessage);
    else
        windowState.statusMessage = nil;
    end
end

local function SnapshotPalJsonCtx(target, jobId, subjobId, storageSubjob, paletteName)
    palJsonCtx.target = target;
    palJsonCtx.jobId = jobId;
    palJsonCtx.subjobId = subjobId;
    palJsonCtx.storageSubjob = storageSubjob;
    palJsonCtx.paletteName = paletteName;
end

local function ComputePalJsonDestStorageKey()
    local c = palJsonCtx;
    if c.target == 'crossbar_job' then
        return paletteJson.ResolveCrossbarJobStorageKey(c.jobId, c.storageSubjob, c.paletteName);
    elseif c.target == 'crossbar_univ' then
        return palette.BuildUniversalCrossbarStorageKey(c.paletteName);
    end
    return palette.BuildPaletteStorageKey(c.jobId or 1, c.subjobId or 0, c.paletteName);
end

local function RunPaletteJsonExport()
    local text, err;
    local c = palJsonCtx;
    local part = palJsonExportPart[1] or paletteJson.EXPORT_PART_FULL;
    if c.target == 'crossbar_job' then
        text, err = paletteJson.ExportCrossbarJobPalette(c.jobId, c.storageSubjob, c.paletteName, part);
    elseif c.target == 'crossbar_univ' then
        text, err = paletteJson.ExportCrossbarUniversalPalette(c.paletteName, part);
    else
        text, err = paletteJson.ExportHotbarPalette(c.jobId, c.subjobId, c.paletteName, part);
    end
    if err then
        SetStatusMessage(err);
        return;
    end
    palJsonBuf[1] = text or '';
    palJsonErr = nil;
    palJsonLastPath = nil;
    palJsonMode = 'export';
    palJsonWinOpen[1] = true;
end

local function OpenPaletteJsonImport()
    palJsonBuf[1] = '';
    palJsonErr = nil;
    palJsonLastPath = nil;
    palJsonPurgeFirst[1] = false;
    palJsonImportSlots[1] = true;
    palJsonImportMacros[1] = true;
    palJsonMode = 'import';
    palJsonWinOpen[1] = true;
end

--- Returns true if import succeeded (caller may close the window).
local function ExecutePaletteJsonImport(purgeExclusiveMacrosFirst)
    palJsonErr = nil;
    palJsonLastPath = nil;
    local destKey = ComputePalJsonDestStorageKey();
    if not destKey then
        palJsonErr = 'Could not resolve destination storage key';
        return false;
    end
    local okDec, dec = pcall(json.decode, palJsonBuf[1]);
    if not okDec then
        palJsonErr = 'Invalid JSON';
        return false;
    end
    local okImp, errImp;
    if dec.kind == paletteJson.KIND_HOTBAR then
        okImp, errImp = paletteJson.ImportHotbarPalette(palJsonBuf[1], {
            destStorageKey = destKey,
            purgeExclusiveMacrosFirst = purgeExclusiveMacrosFirst == true,
            importSlots = palJsonImportSlots[1],
            importMacros = palJsonImportMacros[1],
        });
    else
        okImp, errImp = paletteJson.ImportCrossbarPalette(palJsonBuf[1], {
            destStorageKey = destKey,
            purgeExclusiveMacrosFirst = purgeExclusiveMacrosFirst == true,
            importSlots = palJsonImportSlots[1],
            importMacros = palJsonImportMacros[1],
        });
    end
    if okImp then
        SetStatusMessage('Import applied');
        return true;
    end
    palJsonErr = errImp or 'Import failed';
    return false;
end

local function DrawPaletteJsonModal()
    if not palJsonWinOpen[1] then
        return;
    end
    imgui.SetNextWindowSize({ 720, palJsonMode == 'import' and 600 or 520 }, ImGuiCond_FirstUseEver);
    if imgui.Begin('Palette JSON##xiuiPalJson', palJsonWinOpen) then
        imgui.TextWrapped(
            'Export or import palette data for the selected palette. Create the destination palette before importing. Choose what to include on export and what to apply on import.'
        );
        if palJsonErr then
            imgui.TextColored({ 1.0, 0.3, 0.3, 1.0 }, palJsonErr);
        end
        if palJsonLastPath then
            imgui.TextColored({ 0.65, 0.65, 0.7, 1.0 }, palJsonLastPath);
        end
        imgui.Separator();

        if palJsonMode == 'export' then
            imgui.Text('Include in file:');
            imgui.SameLine();
            if imgui.RadioButton('Full (slots + macros)##pjExFull', palJsonExportPart[1] == paletteJson.EXPORT_PART_FULL) then
                palJsonExportPart[1] = paletteJson.EXPORT_PART_FULL;
            end
            imgui.SameLine();
            if imgui.RadioButton('Slot bindings only##pjExSlots', palJsonExportPart[1] == paletteJson.EXPORT_PART_SLOTS_ONLY) then
                palJsonExportPart[1] = paletteJson.EXPORT_PART_SLOTS_ONLY;
            end
            imgui.SameLine();
            if imgui.RadioButton('Macros only##pjExMacros', palJsonExportPart[1] == paletteJson.EXPORT_PART_MACROS_ONLY) then
                palJsonExportPart[1] = paletteJson.EXPORT_PART_MACROS_ONLY;
            end
            imgui.ShowHelp(
                'Full: bindings and macro rows used by this palette. Slots only: smaller file; import needs matching macros already in this profile. Macros only: macro library rows without changing slot layout.'
            );
            if imgui.Button('Regenerate##pjRegen') then
                RunPaletteJsonExport();
            end
            imgui.SameLine();
            imgui.TextColored({ 0.6, 0.6, 0.65, 1.0 }, 'Refresh JSON after changing options above.');
            imgui.Spacing();
        end

        if palJsonMode == 'import' then
            if imgui.Checkbox('Import slot bindings (crossbar combos / hotbar bars)##pjImpSlots', palJsonImportSlots) then
            end
            imgui.SameLine();
            imgui.ShowHelp('Replace stored actions for this palette. Uncheck to only merge macro rows from the file.');
            if imgui.Checkbox('Import macros##pjImpMacros', palJsonImportMacros) then
            end
            imgui.SameLine();
            imgui.ShowHelp(
                'Append macro definitions to the destination macro bucket and remap IDs when combined with slot import. Uncheck for slots-only import: the file must reference macros that already exist here.'
            );
            if not palJsonImportSlots[1] then
                imgui.BeginDisabled();
            end
            if imgui.Checkbox('Remove macros only used by this palette before slot import##pjPurge', palJsonPurgeFirst) then
            end
            if not palJsonImportSlots[1] then
                imgui.EndDisabled();
            end
            imgui.ShowHelp(
                'Only applies when importing slot bindings. Deletes macro database rows referenced only by this palette. Shared macros are kept.'
            );
            if palJsonPurgeFirst[1] and palJsonImportSlots[1] then
                imgui.Spacing();
                imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 0.22, 0.22, 1.0 });
                if imgui.TextWrapped then
                    imgui.TextWrapped(
                        'WARNING: This cannot be undone. Macros used exclusively by this palette will be permanently removed before slot import. Macros shared with other palettes are kept.'
                    );
                else
                    imgui.Text(
                        'WARNING: This cannot be undone. Exclusive macros will be removed before slot import.'
                    );
                end
                imgui.PopStyleColor();
            end
            imgui.Spacing();
        end

        imgui.InputTextMultiline('##palJsonBuf', palJsonBuf, 8000, { -1, palJsonMode == 'import' and 180 or 220 });
        if palJsonMode == 'export' then
            if imgui.Button('Save to file##pjSave') then
                local ok, path = paletteJson.SaveTextFile(palJsonCtx.paletteName or 'palette', palJsonBuf[1]);
                if ok then
                    palJsonLastPath = path;
                    SetStatusMessage('Saved JSON file');
                else
                    palJsonErr = tostring(path);
                end
            end
        else
            if imgui.Button('Apply import##pjApply') then
                if not palJsonImportSlots[1] and not palJsonImportMacros[1] then
                    palJsonErr = 'Select at least one: Import slot bindings or Import macros.';
                elseif palJsonPurgeFirst[1] and palJsonImportSlots[1] then
                    palJsonQueueDestructiveConfirm = true;
                else
                    if ExecutePaletteJsonImport(false) then
                        palJsonWinOpen[1] = false;
                    end
                end
            end
        end

        if palJsonQueueDestructiveConfirm then
            imgui.OpenPopup('Confirm destructive palette import##xiuiPalJsonDest');
            palJsonQueueDestructiveConfirm = false;
        end
        imgui.SetNextWindowSize({ 460, 0 }, ImGuiCond_Appearing);
        if imgui.BeginPopupModal('Confirm destructive palette import##xiuiPalJsonDest', nil, ImGuiWindowFlags_AlwaysAutoResize) then
            imgui.TextColored({ 1.0, 0.2, 0.2, 1.0 }, 'This cannot be undone.');
            imgui.Spacing();
            if imgui.TextWrapped then
                imgui.TextWrapped(
                    'Macros referenced only by this palette will be permanently deleted, then the import will run. Macros shared with other palettes are not removed. Continue?'
                );
            else
                imgui.Text('Macros referenced only by this palette will be deleted, then import runs.');
            end
            imgui.Spacing();
            if imgui.Button('Cancel##pjDestCancel', { 120, 0 }) then
                imgui.CloseCurrentPopup();
            end
            imgui.SameLine();
            if imgui.Button('Delete exclusive macros and import##pjDestOk', { 260, 0 }) then
                if ExecutePaletteJsonImport(true) then
                    imgui.CloseCurrentPopup();
                    palJsonWinOpen[1] = false;
                end
            end
            imgui.EndPopup();
        end
    end
    imgui.End();
end

-- Open the floating Palette Manager (keyboard hotbar palettes only; crossbar uses config /xiui cpalette)
function M.Open()
    windowState.isOpen = true;
    windowState.selectedPaletteType = 'hotbar';
    windowState.selectedPaletteName = nil;
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

-- Toggle floating Palette Manager (/xiui pal)
function M.ToggleHotbarPaletteManager()
    if windowState.isOpen then
        M.Close();
        return false;
    end
    M.Open();
    return true;
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

-- Helper: Draw palette list (floating window: keyboard hotbar only)
local function DrawPaletteList()
    palette.EnsureDefaultPaletteExists(windowState.selectedJobId, 0);
    local palettes = palette.GetAvailablePalettes(1, windowState.selectedJobId, windowState.selectedSubjobId);

    local headerText;
    if windowState.selectedSubjobId == 0 then
        headerText = string.format('Shared Library (%s)', GetJobName(windowState.selectedJobId));
    else
        headerText = string.format('%s/%s', GetJobName(windowState.selectedJobId), GetJobName(windowState.selectedSubjobId));
    end
    imgui.Text(headerText);
    imgui.Separator();

    local listHeight = 150;
    imgui.BeginChild('##paletteList', { 0, listHeight }, true);

    if #palettes == 0 then
        imgui.TextColored({0.5, 0.5, 0.5, 1.0}, 'No palettes defined');
    else
        imgui.Columns(2, '##hbPalCols', true);
        imgui.SetColumnWidth(0, 220);
        imgui.Text('Palette');
        imgui.NextColumn();
        imgui.Text('Status');
        imgui.NextColumn();
        imgui.Separator();
        for i, paletteName in ipairs(palettes) do
            local isSelected = windowState.selectedPaletteName == paletteName;

            imgui.PushID('hbp' .. i);
            PushPaletteRowStyle(isSelected);
            if imgui.Selectable(paletteName .. '##palette', isSelected) then
                windowState.selectedPaletteName = paletteName;
            end
            PopPaletteRowStyle();

            if imgui.BeginPopupContextItem('##paletteContext') then
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
                    modalState.copyOverwriteExisting = false;
                    modalState.copyDestExistingIndex = 1;
                    modalState.crossbarCopyFromSubjob = nil;
                    modalState.copyTargetJobId = windowState.selectedJobId;
                    modalState.copyTargetSubjobId = windowState.selectedSubjobId;
                    modalState.copyDestScope = 'job';
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

            imgui.NextColumn();
            local inRb = palette.IsHotbarPaletteInRbCycle(windowState.selectedJobId, windowState.selectedSubjobId, paletteName);
            imgui.Text(inRb and 'Active' or 'Inactive');
            imgui.NextColumn();
            imgui.PopID();
        end
        imgui.Columns(1);
    end

    imgui.EndChild();

    return palettes;
end

-- Helper: Draw action buttons (floating window: keyboard hotbar only)
local function DrawActionButtons(palettes)
    if imgui.Button('+ New') then
        modalState.mode = 'create';
        modalState.inputBuffer[1] = '';
        modalState.errorMessage = nil;
        modalState.isOpen = true;
    end

    imgui.SameLine();

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

    if not hasSelection then imgui.BeginDisabled(); end
    if imgui.Button('Copy To...') then
        modalState.mode = 'copy';
        modalState.inputBuffer[1] = windowState.selectedPaletteName;
        modalState.errorMessage = nil;
        modalState.copyOverwriteExisting = false;
        modalState.copyDestExistingIndex = 1;
        modalState.copyTargetJobId = windowState.selectedJobId;
        modalState.copyTargetSubjobId = windowState.selectedSubjobId;
        modalState.crossbarCopyFromSubjob = nil;
        modalState.copyDestScope = 'job';
        modalState.isOpen = true;
    end
    if not hasSelection then imgui.EndDisabled(); end

    imgui.Spacing();

    local canMoveUp = false;
    local canMoveDown = false;
    if hasSelection and palettes and #palettes > 0 then
        local ix;
        for i, n in ipairs(palettes) do
            if n == windowState.selectedPaletteName then
                ix = i;
                break;
            end
        end
        canMoveUp = ix ~= nil and ix > 1;
        canMoveDown = ix ~= nil and ix < #palettes;
    end

    if not canMoveUp then imgui.BeginDisabled(); end
    if imgui.Button('Move Up') then
        local success, err = palette.MovePalette(1, windowState.selectedPaletteName, -1, windowState.selectedJobId, windowState.selectedSubjobId);
        if not success and err then
            SetStatusMessage(err);
        end
    end
    if not canMoveUp then imgui.EndDisabled(); end
    imgui.SameLine();
    if not canMoveDown then imgui.BeginDisabled(); end
    if imgui.Button('Move Down') then
        local success, err = palette.MovePalette(1, windowState.selectedPaletteName, 1, windowState.selectedJobId, windowState.selectedSubjobId);
        if not success and err then
            SetStatusMessage(err);
        end
    end
    if not canMoveDown then imgui.EndDisabled(); end
    imgui.SameLine();
    if not hasSelection then imgui.BeginDisabled(); end
    local inRbCycle = hasSelection and palette.IsHotbarPaletteInRbCycle(windowState.selectedJobId, windowState.selectedSubjobId, windowState.selectedPaletteName);
    if imgui.Button((inRbCycle and 'Disable' or 'Enable') .. '##palRbTgl') then
        palette.SetHotbarPaletteInRbCycle(windowState.selectedJobId, windowState.selectedSubjobId, windowState.selectedPaletteName, not inRbCycle);
    end
    if not hasSelection then imgui.EndDisabled(); end

    imgui.Spacing();
    if not hasSelection then imgui.BeginDisabled(); end
    if imgui.Button('Export JSON##hbPalJsonEx') and hasSelection then
        SnapshotPalJsonCtx('hotbar', windowState.selectedJobId, windowState.selectedSubjobId, nil, windowState.selectedPaletteName);
        RunPaletteJsonExport();
    end
    imgui.SameLine();
    if imgui.Button('Import JSON##hbPalJsonIm') and hasSelection then
        SnapshotPalJsonCtx('hotbar', windowState.selectedJobId, windowState.selectedSubjobId, nil, windowState.selectedPaletteName);
        OpenPaletteJsonImport();
    end
    if not hasSelection then imgui.EndDisabled(); end
    imgui.SameLine();
    imgui.ShowHelp('Export or import keyboard hotbar palettes (all six bars) as JSON, including macros referenced by slots.');

    DrawStatusMessage();
end

-- Helper: Draw create/rename modal
local function DrawCreateRenameModal()
    if not modalState.isOpen or (modalState.mode ~= 'create' and modalState.mode ~= 'rename') then
        return;
    end

    local title = modalState.mode == 'create' and 'Create New Palette' or 'Rename Palette';
    imgui.OpenPopup(title .. '##paletteModal');

    if imgui.BeginPopupModal(title .. '##paletteModal', nil, ImGuiWindowFlags_AlwaysAutoResize) then
        components.PushPaletteManagerButtonStyle();
        local embedU = modalState.embedCrossbarUniversal == true;
        if modalState.mode == 'create' and not embedU and windowState.selectedSubjobId ~= 0 and windowState.selectedPaletteType == 'hotbar' then
            local usingFallback = IsUsingFallback(windowState.selectedJobId, windowState.selectedSubjobId, windowState.selectedPaletteType);
            if usingFallback then
                imgui.TextColored({1.0, 0.7, 0.3, 1.0}, 'Warning: Creating this palette will stop');
                imgui.TextColored({1.0, 0.7, 0.3, 1.0}, 'using shared palettes for ' .. GetJobName(windowState.selectedJobId) .. '/' .. GetJobName(windowState.selectedSubjobId) .. '.');
                imgui.Spacing();
            end
        end

        -- Main job profile for this palette (Shared vs SJ tier does not change the icon)
        if not embedU then
            do
                local jid = windowState.selectedJobId or 1;
                local jtex = TextureManager.getJobIcon(jid, GetCrossbarPaletteJobIconTheme());
                if jtex and jtex.image then
                    local p = tonumber(ffi.cast('uint32_t', jtex.image));
                    if p then
                        imgui.AlignTextToFramePadding();
                        imgui.Image(p, { 18, 18 });
                        imgui.SameLine(0, 6);
                    end
                end
            end
        else
            imgui.TextColored({ 0.85, 0.85, 0.5, 1.0 }, 'Global [G]');
            imgui.SameLine(0, 8);
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
                if embedU then
                    if modalState.mode == 'create' then
                        success, err = palette.CreateUniversalCrossbarPalette(newName);
                    else
                        success, err = palette.RenameUniversalCrossbarPalette(windowState.selectedPaletteName, newName);
                    end
                elseif modalState.mode == 'create' then
                    if windowState.selectedPaletteType == 'hotbar' then
                        success, err = palette.CreatePalette(1, newName, windowState.selectedJobId, windowState.selectedSubjobId);
                    else
                        success, err = palette.CreateCrossbarPalette(newName, windowState.selectedJobId, windowState.selectedSubjobId);
                    end
                else  -- rename
                    if windowState.selectedPaletteType == 'hotbar' then
                        success, err = palette.RenamePalette(1, windowState.selectedPaletteName, newName, windowState.selectedJobId, windowState.selectedSubjobId);
                    else
                        local opSub = GetCrossbarModalStorageSubjob();
                        success, err = palette.RenameCrossbarPalette(windowState.selectedPaletteName, newName, windowState.selectedJobId, opSub);
                    end
                end

                if success then
                    windowState.selectedPaletteName = newName;
                    if embedU then
                        embedCrossbarUniversalContext.selectedPaletteName = newName;
                    elseif modalState.mode == 'rename' and windowState.selectedPaletteType == 'crossbar' then
                        embedCrossbarJobContext.selectedPaletteName = newName;
                    end
                    ClearCrossbarEmbedModalFields();

                    -- Activate the newly created palette if viewing current job's palettes
                    if modalState.mode == 'create' then
                        if embedU then
                            palette.SetActiveUniversalCrossbarPalette(newName);
                        else
                            local currentJobId = data.jobId;
                            local currentSubjobId = data.subjobId or 0;
                            local viewingShared = (windowState.selectedSubjobId == 0);
                            local viewingCurrentJob = (windowState.selectedJobId == currentJobId);
                            local viewingCurrentSubjob = (windowState.selectedSubjobId == currentSubjobId);

                            if viewingCurrentJob and (viewingShared or viewingCurrentSubjob) then
                                if windowState.selectedPaletteType == 'hotbar' then
                                    palette.SetActivePalette(1, newName, currentJobId, currentSubjobId);
                                else
                                    local st = windowState.selectedSubjobId == 0 and 0 or windowState.selectedSubjobId;
                                    palette.SetActivePaletteForCombo('L2', newName, st);
                                end
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
            ClearCrossbarEmbedModalFields();
            imgui.CloseCurrentPopup();
        end

        components.PopPaletteManagerButtonStyle();
        imgui.EndPopup();
    end
end

-- Helper: Draw copy modal
local function DrawCopyModal()
    if not modalState.isOpen or modalState.mode ~= 'copy' then
        return;
    end

    imgui.OpenPopup('Copy Palette##copyModal');

    -- Non-modal popup: no fullscreen dim layer (BeginPopupModal dims; Ashita may not expose
    -- ImGuiCol_ModalWindowDimBg for PushStyleColor, and FFXI + dim can hide the hardware cursor).
    if imgui.BeginPopup('Copy Palette##copyModal') then
        components.PushPaletteManagerButtonStyle();
        local embedUcopy = modalState.embedCrossbarUniversalCopy == true;
        local copySourceName = windowState.selectedPaletteName;
        local isCrossbar = windowState.selectedPaletteType == 'crossbar';

        if embedUcopy and modalState.copyDestScope == 'universal' then
            imgui.Text('Copy "' .. (copySourceName or '') .. '" to another Global [G] palette:');
        elseif embedUcopy and modalState.copyDestScope == 'job' then
            imgui.Text('Copy "' .. (copySourceName or '') .. '" to a Job [J] palette:');
        elseif not embedUcopy and isCrossbar and modalState.copyDestScope == 'universal' then
            imgui.Text('Copy "' .. (copySourceName or '') .. '" to a Global [G] palette:');
        else
            imgui.Text('Copy "' .. (copySourceName or '') .. '" to:');
        end
        imgui.Spacing();

        if isCrossbar then
            imgui.Text('Destination storage:');
            local scopeJob = modalState.copyDestScope == 'job';
            if imgui.RadioButton('Job / Subjob [J]##palCopyDestJob', scopeJob) then
                modalState.copyDestScope = 'job';
            end
            imgui.SameLine();
            if imgui.RadioButton('Global [G]##palCopyDestG', not scopeJob) then
                modalState.copyDestScope = 'universal';
            end
            imgui.ShowHelp('Job [J] copies into per-job crossbar storage (shared tier or subjob tier). Global [G] copies into all-jobs universal crossbar palettes.');
            imgui.Spacing();
        end

        local showJobDestControls = (windowState.selectedPaletteType == 'hotbar')
            or (isCrossbar and modalState.copyDestScope == 'job');

        if showJobDestControls then
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
                local sharedSelected = (modalState.copyTargetSubjobId == 0);
                if imgui.Selectable('Shared', sharedSelected) then
                    modalState.copyTargetSubjobId = 0;
                end
                if sharedSelected then
                    imgui.SetItemDefaultFocus();
                end
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

            if modalState.copyTargetSubjobId ~= 0 then
                local targetUsingFallback = IsUsingFallback(modalState.copyTargetJobId, modalState.copyTargetSubjobId, windowState.selectedPaletteType);
                if targetUsingFallback then
                    imgui.TextColored({1.0, 0.7, 0.3, 1.0}, 'Warning: This will stop using shared palettes for');
                    imgui.TextColored({1.0, 0.7, 0.3, 1.0}, GetJobName(modalState.copyTargetJobId) .. '/' .. GetJobName(modalState.copyTargetSubjobId) .. '.');
                    imgui.Spacing();
                end
            end
        end

        local destNames = GetCopyDestinationNamesForModal();
        if #destNames == 0 then
            modalState.copyDestExistingIndex = 1;
        elseif modalState.copyDestExistingIndex > #destNames then
            modalState.copyDestExistingIndex = #destNames;
        elseif modalState.copyDestExistingIndex < 1 then
            modalState.copyDestExistingIndex = 1;
        end

        local copyOwBuf = { modalState.copyOverwriteExisting == true };
        imgui.Checkbox('Overwrite an existing palette##copyPalOw', copyOwBuf);
        modalState.copyOverwriteExisting = copyOwBuf[1];

        if modalState.copyOverwriteExisting then
            imgui.TextColored({1.0, 0.65, 0.35, 1.0}, 'Warning: All slot actions on the destination palette will be replaced.');
            imgui.Spacing();
            if #destNames == 0 then
                imgui.TextColored({0.75, 0.75, 0.75, 1.0}, 'No palettes exist at this destination yet.');
            else
                imgui.Text('Destination palette:');
                imgui.PushItemWidth(220);
                local comboLabel = destNames[modalState.copyDestExistingIndex] or destNames[1];
                if imgui.BeginCombo('##copyDestExisting', comboLabel) then
                    for di, pname in ipairs(destNames) do
                        if imgui.Selectable(pname .. '##copyDest' .. di, di == modalState.copyDestExistingIndex) then
                            modalState.copyDestExistingIndex = di;
                        end
                        if di == modalState.copyDestExistingIndex then
                            imgui.SetItemDefaultFocus();
                        end
                    end
                    imgui.EndCombo();
                end
                imgui.PopItemWidth();
            end
        else
            imgui.Text('New name (leave blank to keep the same):');
            imgui.PushItemWidth(200);
            imgui.InputText('##copyNewName', modalState.inputBuffer, 32);
            imgui.PopItemWidth();
        end

        -- Show error if any
        if modalState.errorMessage then
            imgui.TextColored({1.0, 0.3, 0.3, 1.0}, modalState.errorMessage);
        end

        imgui.Spacing();

        local newName = modalState.inputBuffer[1];
        if newName == '' then newName = nil; end

        local overwrite = modalState.copyOverwriteExisting == true;
        local destArg;
        if overwrite then
            destArg = destNames[modalState.copyDestExistingIndex];
        else
            destArg = newName;
        end

        local effectiveName;
        if overwrite then
            effectiveName = destArg;
        else
            effectiveName = newName or windowState.selectedPaletteName;
        end

        local copyFromSubjob = windowState.selectedSubjobId;
        if windowState.selectedPaletteType == 'crossbar' and modalState.crossbarCopyFromSubjob ~= nil then
            copyFromSubjob = modalState.crossbarCopyFromSubjob;
        end

        local isCopyNoOp;
        if embedUcopy then
            if modalState.copyDestScope == 'universal' then
                if overwrite then
                    isCopyNoOp = not destArg or destArg == '' or destArg == copySourceName;
                else
                    isCopyNoOp = (not newName or newName == '') or (newName == copySourceName);
                end
            else
                isCopyNoOp = false;
            end
        elseif isCrossbar and modalState.copyDestScope == 'universal' then
            isCopyNoOp = false;
        else
            isCopyNoOp = modalState.copyTargetJobId == windowState.selectedJobId and
                modalState.copyTargetSubjobId == copyFromSubjob and
                effectiveName == windowState.selectedPaletteName;
        end

        local canCopy;
        if embedUcopy then
            if modalState.copyDestScope == 'universal' then
                if overwrite then
                    canCopy = not isCopyNoOp and destArg ~= nil and destArg ~= '' and #destNames > 0;
                else
                    canCopy = not isCopyNoOp and newName and newName ~= '';
                end
            else
                canCopy = not isCopyNoOp and (not overwrite or (destArg ~= nil and destArg ~= '' and #destNames > 0));
            end
        else
            canCopy = not isCopyNoOp and (not overwrite or (destArg ~= nil and destArg ~= '' and #destNames > 0));
        end

        -- Buttons
        if not canCopy then imgui.BeginDisabled(); end
        if imgui.Button('Copy', { 80, 0 }) then
            local success, err;
            if windowState.selectedPaletteType == 'hotbar' then
                success, err = palette.CopyPalette(
                    windowState.selectedPaletteName,
                    windowState.selectedJobId,
                    windowState.selectedSubjobId,
                    modalState.copyTargetJobId,
                    modalState.copyTargetSubjobId,
                    destArg,
                    overwrite
                );
            elseif embedUcopy then
                if modalState.copyDestScope == 'universal' then
                    local destFinal = overwrite and destArg or newName;
                    success, err = palette.CopyUniversalCrossbarPalette(copySourceName, destFinal, overwrite);
                else
                    local destFinal = overwrite and destArg or (newName or copySourceName);
                    success, err = palette.CopyUniversalCrossbarPaletteToJob(
                        copySourceName,
                        destFinal,
                        modalState.copyTargetJobId,
                        modalState.copyTargetSubjobId,
                        overwrite
                    );
                end
            elseif isCrossbar and modalState.copyDestScope == 'universal' then
                local destFinal = overwrite and destArg or (newName or windowState.selectedPaletteName);
                success, err = palette.CopyCrossbarPaletteToUniversal(
                    windowState.selectedPaletteName,
                    windowState.selectedJobId,
                    copyFromSubjob,
                    destFinal,
                    overwrite
                );
            else
                success, err = palette.CopyCrossbarPalette(
                    windowState.selectedPaletteName,
                    windowState.selectedJobId,
                    copyFromSubjob,
                    modalState.copyTargetJobId,
                    modalState.copyTargetSubjobId,
                    destArg,
                    overwrite
                );
            end

            if success then
                modalState.isOpen = false;
                ClearCrossbarEmbedModalFields();
                imgui.CloseCurrentPopup();
            else
                modalState.errorMessage = err or 'Copy failed';
            end
        end
        if not canCopy then imgui.EndDisabled(); end

        imgui.SameLine();

        if imgui.Button('Cancel', { 80, 0 }) then
            modalState.isOpen = false;
            ClearCrossbarEmbedModalFields();
            imgui.CloseCurrentPopup();
        end

        components.PopPaletteManagerButtonStyle();
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
        components.PushPaletteManagerButtonStyle();
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
            if modalState.embedCrossbarUniversal == true then
                success, err = palette.DeleteUniversalCrossbarPalette(modalState.deletePaletteName);
            elseif windowState.selectedPaletteType == 'hotbar' then
                success, err = palette.DeletePalette(1, modalState.deletePaletteName, windowState.selectedJobId, windowState.selectedSubjobId);
            else
                local opSub = GetCrossbarModalStorageSubjob();
                success, err = palette.DeleteCrossbarPalette(modalState.deletePaletteName, windowState.selectedJobId, opSub);
            end
            if success then
                windowState.selectedPaletteName = nil;
                embedCrossbarJobContext.selectedPaletteName = nil;
                embedCrossbarJobContext.selectedStorageSubjob = nil;
                embedCrossbarUniversalContext.selectedPaletteName = nil;
                modalState.isOpen = false;
                ClearCrossbarEmbedModalFields();
                imgui.CloseCurrentPopup();
            else
                modalState.errorMessage = err or 'Delete failed';
            end
        end

        imgui.SameLine();

        if imgui.Button('Cancel', { 80, 0 }) then
            modalState.isOpen = false;
            ClearCrossbarEmbedModalFields();
            imgui.CloseCurrentPopup();
        end

        components.PopPaletteManagerButtonStyle();
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
        components.PushPaletteManagerButtonStyle();
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
        components.PopPaletteManagerButtonStyle();
        imgui.EndPopup();
    end
end

-- Embedded Global [G] crossbar palette manager (same interaction model as Job/J+SJ embed, no job binding)
function M.DrawEmbeddedCrossbarManageUniversal()
    windowState.selectedPaletteType = 'crossbar';

    palette.EnsureUniversalCrossbarDefaultExists();
    local names = palette.GetUniversalCrossbarPaletteNamesOrdered();

    if #names > 0 then
        local sn = embedCrossbarUniversalContext.selectedPaletteName;
        local needPick = sn == nil;
        if not needPick then
            local found = false;
            for _, n in ipairs(names) do
                if n == sn then
                    found = true;
                    break;
                end
            end
            if not found then
                needPick = true;
            end
        end
        if needPick then
            embedCrossbarUniversalContext.selectedPaletteName = names[1];
            windowState.selectedPaletteName = names[1];
        end
    end

    local avail = imgui.GetContentRegionAvail();
    local availW = type(avail) == 'table' and avail[1] or avail or 400;
    -- Wider than 50%: config tab has room; avoids cramped Palette / Status columns
    local shellW = math.max(300, math.min(availW * 0.62, 720));

    -- List: column headers + separator + fixed visible rows; extra palettes scroll inside the child.
    local lineH = imgui.GetTextLineHeightWithSpacing();
    local nNames = #names;
    local headerChromeH = math.floor(lineH * 2 + 6);
    local listH;
    if nNames == 0 then
        listH = math.floor(lineH * 3 + 12);
    else
        listH = headerChromeH + EMBED_CROSSBAR_PAL_LIST_VISIBLE_ROWS * lineH + 2;
    end
    local headerBlockH = math.floor(lineH * 3 + 8);
    local listToButtonsPad = 4;
    local actionBlockH = GetEmbedCrossbarPalMgrActionBlockH();
    local shellH = headerBlockH + listH + listToButtonsPad + actionBlockH;

    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 12, 6 });
    imgui.PushStyleColor(ImGuiCol_ChildBg, components.TAB_STYLE.bgMedium);
    imgui.PushStyleColor(ImGuiCol_Border, { 0.42, 0.36, 0.26, 0.85 });
    imgui.BeginChild('##xbEmbedUniversalPalMgrShell', { shellW, shellH }, true, 0);

    imgui.TextColored(components.MANAGER_BUTTON_STYLE.palette.headerText, 'Palette Manager');
    imgui.Spacing();
    imgui.TextColored({ 0.85, 0.82, 0.7, 1.0 }, 'Palettes - Global [G]');
    imgui.Separator();

    imgui.PushStyleColor(ImGuiCol_ChildBg, components.TAB_STYLE.bgLighter);
    -- Scrollbar only when content exceeds listH (not AlwaysVerticalScrollbar — avoids permanent gutter + squeeze)
    imgui.BeginChild('##xbEmbedUniversalPalList', { 0, listH }, true, 0);

    if #names == 0 then
        imgui.TextColored({ 0.5, 0.5, 0.5, 1.0 }, 'No palettes');
    else
        imgui.Columns(2, '##xbEmbUCols', true);
        imgui.SetColumnWidth(0, math.max(160, shellW - 64));
        imgui.Text('Palette');
        imgui.NextColumn();
        imgui.Text('Status');
        imgui.NextColumn();
        imgui.Separator();
        for i, name in ipairs(names) do
            local isSel = embedCrossbarUniversalContext.selectedPaletteName == name;
            imgui.PushID('xbemu' .. i .. '_' .. name);
            local label = name .. ' (G)';
            PushPaletteRowStyle(isSel);
            if imgui.Selectable(label .. '##sel', isSel) then
                embedCrossbarUniversalContext.selectedPaletteName = name;
                windowState.selectedPaletteName = name;
            end
            PopPaletteRowStyle();
            if imgui.BeginPopupContextItem('##ctxu') then
                if imgui.MenuItem('Rename##xbemu') then
                    modalState.mode = 'rename';
                    modalState.inputBuffer[1] = name;
                    modalState.errorMessage = nil;
                    modalState.isOpen = true;
                    modalState.embedCrossbarUniversal = true;
                    embedCrossbarUniversalContext.selectedPaletteName = name;
                    windowState.selectedPaletteName = name;
                end
                if imgui.MenuItem('Copy To...##xbemu') then
                    modalState.mode = 'copy';
                    modalState.inputBuffer[1] = name;
                    modalState.errorMessage = nil;
                    modalState.copyOverwriteExisting = false;
                    modalState.copyDestExistingIndex = 1;
                    modalState.embedCrossbarUniversalCopy = true;
                    modalState.copyDestScope = 'universal';
                    modalState.copyTargetJobId = data.jobId or 1;
                    modalState.copyTargetSubjobId = data.subjobId or 0;
                    embedCrossbarUniversalContext.selectedPaletteName = name;
                    windowState.selectedPaletteName = name;
                    modalState.isOpen = true;
                end
                if #names > 1 then
                    imgui.Separator();
                    if imgui.MenuItem('Delete##xbemu') then
                        modalState.mode = 'delete';
                        modalState.deletePaletteName = name;
                        modalState.errorMessage = nil;
                        modalState.embedCrossbarUniversal = true;
                        modalState.isOpen = true;
                        windowState.selectedPaletteName = name;
                    end
                end
                imgui.EndPopup();
            end
            imgui.NextColumn();
            local inCyc = palette.GetUniversalPaletteIncludeInCycle(name);
            imgui.Text(inCyc and 'Active' or 'Inactive');
            imgui.NextColumn();
            imgui.PopID();
        end
        imgui.Columns(1);
    end

    imgui.EndChild();
    imgui.PopStyleColor();
    imgui.Dummy({ 0, listToButtonsPad });

    local selName = embedCrossbarUniversalContext.selectedPaletteName;
    local hasSel = selName ~= nil;

    components.PushPaletteManagerButtonStyle();
    if imgui.Button('+ New##xbemuNew') then
        modalState.mode = 'create';
        modalState.inputBuffer[1] = '';
        modalState.errorMessage = nil;
        modalState.isOpen = true;
        modalState.embedCrossbarUniversal = true;
    end

    imgui.SameLine();
    if not hasSel then
        imgui.BeginDisabled();
    end
    if imgui.Button('Rename##xbemuRen') then
        modalState.mode = 'rename';
        modalState.inputBuffer[1] = selName;
        modalState.errorMessage = nil;
        modalState.embedCrossbarUniversal = true;
        modalState.isOpen = true;
        windowState.selectedPaletteName = selName;
    end
    if not hasSel then
        imgui.EndDisabled();
    end

    imgui.SameLine();
    local canDel = hasSel and #names > 1;
    if not canDel then
        imgui.BeginDisabled();
    end
    if imgui.Button('Delete##xbemuDel') then
        modalState.mode = 'delete';
        modalState.deletePaletteName = selName;
        modalState.errorMessage = nil;
        modalState.embedCrossbarUniversal = true;
        modalState.isOpen = true;
        windowState.selectedPaletteName = selName;
    end
    if not canDel then
        imgui.EndDisabled();
    end

    imgui.SameLine();
    if not hasSel then
        imgui.BeginDisabled();
    end
    if imgui.Button('Copy To...##xbemuCp') then
        modalState.mode = 'copy';
        modalState.inputBuffer[1] = selName;
        modalState.errorMessage = nil;
        modalState.copyOverwriteExisting = false;
        modalState.copyDestExistingIndex = 1;
        modalState.embedCrossbarUniversalCopy = true;
        modalState.copyDestScope = 'universal';
        modalState.copyTargetJobId = data.jobId or 1;
        modalState.copyTargetSubjobId = data.subjobId or 0;
        modalState.embedCrossbarUniversal = true;
        windowState.selectedPaletteName = selName;
        modalState.isOpen = true;
    end
    if not hasSel then
        imgui.EndDisabled();
    end

    imgui.Spacing();

    local idxInList = nil;
    if hasSel then
        for ti, n in ipairs(names) do
            if n == selName then
                idxInList = ti;
                break;
            end
        end
    end
    local canUp = hasSel and idxInList ~= nil and idxInList > 1;
    local canDown = hasSel and idxInList ~= nil and idxInList < #names;

    if not canUp then
        imgui.BeginDisabled();
    end
    if imgui.Button('Move Up##xbemuUp') and canUp then
        local success, err = palette.MoveUniversalCrossbarPalette(selName, -1);
        if not success and err then
            SetStatusMessage(err);
        end
    end
    if not canUp then
        imgui.EndDisabled();
    end

    imgui.SameLine();
    if not canDown then
        imgui.BeginDisabled();
    end
    if imgui.Button('Move Down##xbemuDn') and canDown then
        local success, err = palette.MoveUniversalCrossbarPalette(selName, 1);
        if not success and err then
            SetStatusMessage(err);
        end
    end
    if not canDown then
        imgui.EndDisabled();
    end

    imgui.SameLine();
    local inRbSel = hasSel and palette.GetUniversalPaletteIncludeInCycle(selName);
    if not hasSel then
        imgui.BeginDisabled();
    end
    if imgui.Button((inRbSel and 'Disable' or 'Enable') .. '##xbemuRbTgl') then
        palette.SetUniversalPaletteIncludeInCycle(selName, not inRbSel);
    end
    if not hasSel then
        imgui.EndDisabled();
    end

    imgui.SameLine();
    if not hasSel then
        imgui.BeginDisabled();
    end
    if imgui.Button('Edit Full Palette##xbemuFullPal') and hasSel then
        embedCrossbarComboCtx = {
            kind = 'universal',
            name = selName,
        };
        embedCrossbarComboWinOpen[1] = true;
        embedCrossbarComboWinGraceFrames = 0;
        embedCrossbarComboHasDrawn = false;
    end
    if not hasSel then
        imgui.EndDisabled();
    end
    imgui.SameLine();
    imgui.ShowHelp(
        'Tip: put /xiui cpaledit in a macro to toggle this editor for your currently active crossbar palette (same as this button).'
    );

    imgui.Spacing();
    if not hasSel then
        imgui.BeginDisabled();
    end
    if imgui.Button('Export JSON##xbemuJsonEx') and hasSel then
        SnapshotPalJsonCtx('crossbar_univ', nil, nil, nil, selName);
        RunPaletteJsonExport();
    end
    imgui.SameLine();
    if imgui.Button('Import JSON##xbemuJsonIm') and hasSel then
        SnapshotPalJsonCtx('crossbar_univ', nil, nil, nil, selName);
        OpenPaletteJsonImport();
    end
    if not hasSel then
        imgui.EndDisabled();
    end
    imgui.SameLine();
    imgui.ShowHelp('Export or import this Global [G] palette as JSON (bindings and referenced macros).');

    components.PopPaletteManagerButtonStyle();
    DrawStatusMessage();

    imgui.EndChild();
    imgui.PopStyleColor(2);
    imgui.PopStyleVar();
end

-- Embedded job/subjob crossbar palette manager (Manage Palettes & Crossbar — no separate window)
function M.DrawEmbeddedCrossbarManage(jobId, subjobId)
    windowState.selectedPaletteType = 'crossbar';
    windowState.selectedJobId = jobId;
    windowState.selectedSubjobId = subjobId;

    palette.EnsureCrossbarDefaultPaletteExists(jobId, subjobId);

    local rows = palette.GetCrossbarManagePaletteRows(jobId, subjobId);

    local function tierKeyEq(a, b)
        return (tonumber(a) or 0) == (tonumber(b) or 0);
    end

    -- Ensure a valid selection so Move Up/Down can resolve index (storage tier must match row data).
    if #rows > 0 then
        local sn = embedCrossbarJobContext.selectedPaletteName;
        local ss = embedCrossbarJobContext.selectedStorageSubjob;
        local needPick = sn == nil or ss == nil;
        if not needPick then
            local found = false;
            for _, r in ipairs(rows) do
                if r.name == sn and tierKeyEq(r.storageSubjob, ss) then
                    found = true;
                    break;
                end
            end
            if not found then
                needPick = true;
            end
        end
        if needPick then
            local r0 = rows[1];
            embedCrossbarJobContext.selectedPaletteName = r0.name;
            embedCrossbarJobContext.selectedStorageSubjob = r0.storageSubjob;
            windowState.selectedPaletteName = r0.name;
            windowState.selectedCrossbarStorageSubjob = r0.storageSubjob;
        end
    end

    local avail = imgui.GetContentRegionAvail();
    local availW = type(avail) == 'table' and avail[1] or avail or 400;
    local shellW = math.max(300, math.min(availW * 0.62, 720));

    local lineH = imgui.GetTextLineHeightWithSpacing();
    local nRows = #rows;
    local headerChromeH = math.floor(lineH * 2 + 6);
    local listH;
    if nRows == 0 then
        listH = math.floor(lineH * 3 + 12);
    else
        listH = headerChromeH + EMBED_CROSSBAR_PAL_LIST_VISIBLE_ROWS * lineH + 2;
    end
    local headerBlockH = math.floor(lineH * 3 + 8);
    local listToButtonsPad = 4;
    local actionBlockH = GetEmbedCrossbarPalMgrActionBlockH();
    local shellH = headerBlockH + listH + listToButtonsPad + actionBlockH;

    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 12, 6 });
    imgui.PushStyleColor(ImGuiCol_ChildBg, components.TAB_STYLE.bgMedium);
    imgui.PushStyleColor(ImGuiCol_Border, { 0.42, 0.36, 0.26, 0.85 });
    imgui.BeginChild('##xbEmbedPalMgrShell', { shellW, shellH }, true, 0);

    imgui.TextColored(components.MANAGER_BUTTON_STYLE.palette.headerText, 'Palette Manager');
    imgui.Spacing();
    if subjobId == 0 then
        imgui.TextColored({0.85, 0.82, 0.7, 1.0}, string.format('Palettes - Job (J) %s + Shared', GetJobName(jobId)));
    else
        imgui.TextColored({0.85, 0.82, 0.7, 1.0}, string.format('Palettes - Job (J) %s + Subjob (SJ) %s', GetJobName(jobId), GetJobName(subjobId)));
    end
    imgui.Separator();

    imgui.PushStyleColor(ImGuiCol_ChildBg, components.TAB_STYLE.bgLighter);
    imgui.BeginChild('##xbEmbedPalList', { 0, listH }, true, 0);

    if #rows == 0 then
        imgui.TextColored({0.5, 0.5, 0.5, 1.0}, 'No palettes');
    else
        imgui.Columns(2, '##xbEmbCols', true);
        imgui.SetColumnWidth(0, math.max(160, shellW - 64));
        imgui.Text('Palette');
        imgui.NextColumn();
        imgui.Text('Status');
        imgui.NextColumn();
        imgui.Separator();
        for i, row in ipairs(rows) do
            local label = row.name .. palette.FormatCrossbarTierSuffixLabel(row.storageSubjob, subjobId);
            local isSel = embedCrossbarJobContext.selectedPaletteName == row.name
                and tierKeyEq(embedCrossbarJobContext.selectedStorageSubjob, row.storageSubjob);
            imgui.PushID('xbem' .. i .. '_' .. row.storageSubjob .. '_' .. row.name);
            PushPaletteRowStyle(isSel);
            if imgui.Selectable(label .. '##sel', isSel) then
                embedCrossbarJobContext.selectedPaletteName = row.name;
                embedCrossbarJobContext.selectedStorageSubjob = row.storageSubjob;
                windowState.selectedPaletteName = row.name;
                windowState.selectedCrossbarStorageSubjob = row.storageSubjob;
            end
            PopPaletteRowStyle();
            if imgui.BeginPopupContextItem('##ctx') then
                if imgui.MenuItem('Rename##xbem') then
                    modalState.mode = 'rename';
                    modalState.inputBuffer[1] = row.name;
                    modalState.errorMessage = nil;
                    modalState.isOpen = true;
                    modalState.crossbarOperationSubjob = row.storageSubjob;
                    embedCrossbarJobContext.selectedPaletteName = row.name;
                    embedCrossbarJobContext.selectedStorageSubjob = row.storageSubjob;
                    windowState.selectedPaletteName = row.name;
                end
                if imgui.MenuItem('Copy To...##xbem') then
                    modalState.mode = 'copy';
                    modalState.inputBuffer[1] = row.name;
                    modalState.errorMessage = nil;
                    modalState.copyOverwriteExisting = false;
                    modalState.copyDestExistingIndex = 1;
                    modalState.copyDestScope = 'job';
                    modalState.copyTargetJobId = jobId;
                    modalState.copyTargetSubjobId = subjobId;
                    modalState.crossbarCopyFromSubjob = row.storageSubjob;
                    embedCrossbarJobContext.selectedPaletteName = row.name;
                    embedCrossbarJobContext.selectedStorageSubjob = row.storageSubjob;
                    windowState.selectedPaletteName = row.name;
                    windowState.selectedCrossbarStorageSubjob = row.storageSubjob;
                    modalState.isOpen = true;
                end
                if #rows > 1 then
                    imgui.Separator();
                    if imgui.MenuItem('Delete##xbem') then
                        modalState.mode = 'delete';
                        modalState.deletePaletteName = row.name;
                        modalState.errorMessage = nil;
                        modalState.crossbarOperationSubjob = row.storageSubjob;
                        modalState.isOpen = true;
                        windowState.selectedPaletteName = row.name;
                    end
                end
                imgui.EndPopup();
            end
            imgui.NextColumn();
            local inRbEmb = palette.IsCrossbarPaletteInRbCycle(jobId, row.storageSubjob, row.name);
            imgui.Text(inRbEmb and 'Active' or 'Inactive');
            imgui.NextColumn();
            imgui.PopID();
        end
        imgui.Columns(1);
    end

    imgui.EndChild();
    imgui.PopStyleColor();
    imgui.Dummy({ 0, listToButtonsPad });

    local selName = embedCrossbarJobContext.selectedPaletteName;
    local selSt = embedCrossbarJobContext.selectedStorageSubjob;
    local hasSel = selName ~= nil and selSt ~= nil;

    components.PushPaletteManagerButtonStyle();
    if imgui.Button('+ New##xbemNew') then
        modalState.mode = 'create';
        modalState.inputBuffer[1] = '';
        modalState.errorMessage = nil;
        modalState.isOpen = true;
        ClearCrossbarEmbedModalFields();
    end

    imgui.SameLine();
    if not hasSel then imgui.BeginDisabled(); end
    if imgui.Button('Rename##xbemRen') then
        modalState.mode = 'rename';
        modalState.inputBuffer[1] = selName;
        modalState.errorMessage = nil;
        modalState.isOpen = true;
        modalState.crossbarOperationSubjob = selSt;
        windowState.selectedPaletteName = selName;
    end
    if not hasSel then imgui.EndDisabled(); end

    imgui.SameLine();
    local canDel = hasSel and #rows > 1;
    if not canDel then imgui.BeginDisabled(); end
    if imgui.Button('Delete##xbemDel') then
        modalState.mode = 'delete';
        modalState.deletePaletteName = selName;
        modalState.errorMessage = nil;
        modalState.isOpen = true;
        modalState.crossbarOperationSubjob = selSt;
        windowState.selectedPaletteName = selName;
    end
    if not canDel then imgui.EndDisabled(); end

    imgui.SameLine();
    if not hasSel then imgui.BeginDisabled(); end
    if imgui.Button('Copy To...##xbemCp') then
        modalState.mode = 'copy';
        modalState.inputBuffer[1] = selName;
        modalState.errorMessage = nil;
        modalState.copyOverwriteExisting = false;
        modalState.copyDestExistingIndex = 1;
        modalState.copyDestScope = 'job';
        modalState.copyTargetJobId = jobId;
        modalState.copyTargetSubjobId = subjobId;
        modalState.crossbarCopyFromSubjob = selSt;
        windowState.selectedPaletteName = selName;
        windowState.selectedCrossbarStorageSubjob = selSt;
        modalState.isOpen = true;
    end
    if not hasSel then imgui.EndDisabled(); end

    imgui.Spacing();

    -- Same ordered name list as MoveCrossbarPalette (per storage tier), so index matches swap logic
    local tierNames = {};
    local idxInTier = nil;
    if hasSel then
        tierNames = palette.GetCrossbarPaletteNamesForOrderTier(jobId, tonumber(selSt) or 0);
        for ti, n in ipairs(tierNames) do
            if n == selName then
                idxInTier = ti;
                break;
            end
        end
    end
    local canUp = hasSel and idxInTier ~= nil and idxInTier > 1;
    local canDown = hasSel and idxInTier ~= nil and idxInTier < #tierNames;

    if not canUp then imgui.BeginDisabled(); end
    if imgui.Button('Move Up##xbemUp') and canUp then
        local success, err = palette.MoveCrossbarPalette(selName, -1, jobId, selSt);
        if not success and err then
            SetStatusMessage(err);
        end
    end
    if not canUp then imgui.EndDisabled(); end

    imgui.SameLine();
    if not canDown then imgui.BeginDisabled(); end
    if imgui.Button('Move Down##xbemDn') and canDown then
        local success, err = palette.MoveCrossbarPalette(selName, 1, jobId, selSt);
        if not success and err then
            SetStatusMessage(err);
        end
    end
    if not canDown then imgui.EndDisabled(); end

    imgui.SameLine();
    local inRbEmbSel = false;
    if hasSel then
        inRbEmbSel = palette.IsCrossbarPaletteInRbCycle(jobId, selSt or 0, selName);
    end
    if not hasSel then imgui.BeginDisabled(); end
    if imgui.Button((inRbEmbSel and 'Disable' or 'Enable') .. '##xbemRbTgl') then
        palette.SetCrossbarPaletteInRbCycle(jobId, selSt or 0, selName, not inRbEmbSel);
    end
    if not hasSel then imgui.EndDisabled(); end

    imgui.SameLine();
    if not hasSel then imgui.BeginDisabled(); end
    if imgui.Button('Edit Full Palette##xbemMpal') and hasSel then
        embedCrossbarComboCtx = {
            kind = 'job',
            jobId = jobId,
            subjobId = subjobId,
            name = selName,
            st = selSt,
        };
        embedCrossbarComboWinOpen[1] = true;
        embedCrossbarComboWinGraceFrames = 0;
        embedCrossbarComboHasDrawn = false;
    end
    if not hasSel then imgui.EndDisabled(); end
    imgui.SameLine();
    imgui.ShowHelp(
        'Tip: put /xiui cpaledit in a macro to toggle this editor for your currently active crossbar palette (same as this button).'
    );

    imgui.Spacing();
    if not hasSel then imgui.BeginDisabled(); end
    if imgui.Button('Export JSON##xbemJsonEx') and hasSel then
        SnapshotPalJsonCtx('crossbar_job', jobId, subjobId, selSt, selName);
        RunPaletteJsonExport();
    end
    imgui.SameLine();
    if imgui.Button('Import JSON##xbemJsonIm') and hasSel then
        SnapshotPalJsonCtx('crossbar_job', jobId, subjobId, selSt, selName);
        OpenPaletteJsonImport();
    end
    if not hasSel then imgui.EndDisabled(); end
    imgui.SameLine();
    imgui.ShowHelp('Export or import this palette as JSON (bindings and referenced macros).');

    components.PopPaletteManagerButtonStyle();
    DrawStatusMessage();

    imgui.EndChild();
    imgui.PopStyleColor(2);
    imgui.PopStyleVar();
end

-- Confirm closing XIUI Config while Edit Full Palette has unsaved draft changes (see DeferConfigCloseIfEditFullPaletteOpen).
local function DrawCloseConfigWhileEditPaletteModal()
    if openCloseConfigConfirmPopup then
        imgui.OpenPopup('Unsaved Edit Full Palette##xiuiCloseCfgEditPalModal');
        openCloseConfigConfirmPopup = false;
    end
    imgui.SetNextWindowSize({ 460, 0 }, ImGuiCond_Appearing);
    if imgui.BeginPopupModal('Unsaved Edit Full Palette##xiuiCloseCfgEditPalModal', nil, ImGuiWindowFlags_AlwaysAutoResize) then
        if imgui.PushTextWrapPos then
            imgui.PushTextWrapPos(430);
        end
        imgui.TextWrapped('You have unsaved changes in Edit Full Palette. What would you like to do?');
        if imgui.PopTextWrapPos then
            imgui.PopTextWrapPos();
        end
        imgui.Spacing();
        local cfg = require('config');
        if imgui.Button('Save and Close##xiuiCfgClosePalSave', { 140, 0 }) then
            data.ApplyDraft();
            if SaveSettingsToDisk then
                SaveSettingsToDisk();
            end
            ForceCloseEditFullPaletteWindow();
            if cfg.SetWindowOpen then
                cfg.SetWindowOpen(false);
            end
            imgui.CloseCurrentPopup();
        end
        imgui.SameLine();
        if imgui.Button('Revert and Close##xiuiCfgClosePalRevert', { 140, 0 }) then
            data.DiscardDraft();
            ForceCloseEditFullPaletteWindow();
            if cfg.SetWindowOpen then
                cfg.SetWindowOpen(false);
            end
            imgui.CloseCurrentPopup();
        end
        imgui.SameLine();
        if imgui.Button('Cancel##xiuiCfgClosePalCancel', { 100, 0 }) then
            imgui.CloseCurrentPopup();
        end
        imgui.EndPopup();
    end
end

-- Modals + embedded Crossbar "Edit Full Palette" window run even when the floating Palette Manager is closed.
local function DrawPaletteManagerModals()
    DrawCloseConfigWhileEditPaletteModal();
    DrawCreateRenameModal();
    DrawCopyModal();
    DrawDeleteConfirmModal();
    DrawUseSharedModal();
    DrawEmbeddedCrossbarComboModesPopup();
    DrawPaletteJsonModal();
end

-- Draw the main palette manager window
function M.Draw()
    -- Theme applies to the floating window, modals, and the large Crossbar "Edit Full Palette" window
    local applyTheme = windowState.isOpen or modalState.isOpen or (embedCrossbarComboCtx ~= nil) or palJsonWinOpen[1];
    if applyTheme then
        PushXiuiFloatingWindowTheme();
    end

    if windowState.isOpen then
        imgui.SetNextWindowSize({ 350, 400 }, ImGuiCond_FirstUseEver);

        local windowFlags = ImGuiWindowFlags_None;
        local isOpen = { windowState.isOpen };

        if imgui.Begin('Palette Manager##paletteManager', isOpen, windowFlags) then
            components.PushPaletteManagerButtonStyle();
            DrawJobSelector();
            DrawSubjobSelector();
            imgui.Spacing();

            local palettes = DrawPaletteList();
            imgui.Spacing();

            DrawActionButtons(palettes);
            components.PopPaletteManagerButtonStyle();
        end
        imgui.End();

        windowState.isOpen = isOpen[1];
    end

    DrawPaletteManagerModals();

    if applyTheme then
        PopXiuiFloatingWindowTheme();
    end
end

return M;
