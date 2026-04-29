--[[
* XIUI hotbar - Data Module
* Handles state, font storage, and primitive handles
]]--

require('common');

local gameState = require('core.gamestate');
local petregistry = require('modules.hotbar.petregistry');
local petAllowlist = require('modules.hotbar.pet_palette_allowlist');

local M = {};

-- While the Crossbar "Edit Full Palette" window is open, crossbar.lua uses this key with
-- draft functions so edits don't go live until the user confirms.
local crossbarPaletteEditStorageKey = nil;
local draftForStorageKey = nil;   -- persists across Begin/End cycles to guard draft re-init
-- Multi-key draft: segment overrides read/write alternate storage keys (jobsegment:…, global:palette:…)
local draftByKey = nil;            -- [storageKey] = { L2 = { [slot]=... }, ... }
local draftEditJobId = nil;       -- job context for Edit Full Palette (nil = universal editor)
local draftTouchedKeys = nil;     -- { [storageKey] = true } keys modified this session
local draftDirty = false;
local draftUndoStack = {};
local draftUndoGroupActive = false;
local DRAFT_MAX_UNDO = 30;
-- Draft slot cell == this string means "explicitly cleared in draft". String survives deepCopyTable (undo); a table
-- sentinel would clone to a fresh {} and break equality. Missing slot index still means "inherit live" for overlay reads.
local DRAFT_CROSSBAR_SLOT_EMPTY = '__XIUI_DRAFT_SLOT_EMPTY__';

-- Draft CRUD functions are defined after helpers (deepCopyTable, buildSlotRecord, etc.)
-- to satisfy Lua local scoping. See "Draft Layer" section below line 1112.

function M.GetCrossbarPaletteEditSessionKey()
    return crossbarPaletteEditStorageKey;
end

--- True while crossbar draft buffers exist (Edit Full Palette session). Palette rows use draft when drawing with
--- palSk; the gameplay HUD keeps live binds until Apply. Swap reads use GetCrossbarSlotRawForSwapOverlay when draft is open.
function M.IsCrossbarDraftLayerOpen()
    return draftForStorageKey ~= nil and draftByKey ~= nil;
end

-- Pet-aware slot layouts are shared across job:subjob pairs; keyed only by pet subtype
local PETPALETTE_STORAGE_PREFIX = 'petpalette:';

-- Callback for slot data changes (used by macropalette for debounced saves)
local onSlotDataChanged = nil;

function M.SetSlotDataChangedCallback(callback)
    onSlotDataChanged = callback;
end

local function NotifySlotDataChanged()
    if onSlotDataChanged then
        onSlotDataChanged();
    end
end

-- Lazy-loaded to avoid circular dependencies
local petpalette = nil;
local function getPetPalette()
    if not petpalette then
        petpalette = require('modules.hotbar.petpalette');
    end
    return petpalette;
end

local palette = nil;
local function getPalette()
    if not palette then
        palette = require('modules.hotbar.palette');
    end
    return palette;
end

-- ============================================
-- Macro palette DB: many buckets, one profile (gConfig.macroDB)
-- ============================================
-- Each key is a separate palette: global, items, equipment, xiui, custom:*, job id
-- (4 = BLM), SMN composite "15:avatar:ifrit", etc. Rows in different buckets are
-- independent: same displayName, same numeric id, or same macro text in two jobs
-- are all valid. Hotbar/crossbar slots disambiguate with macroRef + macroPaletteKey.
--
-- Coherence (EnsureMacroDatabaseCoherence) only: (1) merge accidental duplicate
-- *job* storage keys "4" and 4 for the *same* job, never other key shapes; (2) fix
-- duplicate macro.id *within* one bucket. It does not merge distinct palettes.

-- ============================================
-- Performance: Macro ID Lookup Cache
-- ============================================
-- O(1) lookup instead of O(n) linear search per GetMacroById call
-- With 197 macros and 72 slots, this reduces from ~14,184 iterations/frame to 72 lookups
-- macroIdLookup[paletteKey] is a separate id map per bucket (see design note above)

local macroIdLookup = {};  -- macroIdLookup[paletteKey][macroId] = macro
local macroIdLookupDirty = true;

-- Per gConfig in-memory: avoid re-running and avoid persisting a sentinel in profile files
local macroDbCoherenceIdentity = nil;

-- One-time (per gConfig object) repair for macroDB (see "Macro palette DB" note above):
-- - Coalesce string job keys (JSON "4") with numeric (4) so buckets are not split.
-- - Deduplicate macro.id within each bucket (first row keeps id) so GetMacroById matches palette grid order.
function M.EnsureMacroDatabaseCoherence(cfg)
    local c = cfg or gConfig;
    if not c or macroDbCoherenceIdentity == c then
        return;
    end
    macroDbCoherenceIdentity = c;
    if not c.macroDB or type(c.macroDB) ~= 'table' then
        return;
    end
    local mdb = c.macroDB;
    -- Collect first: do not modify mdb while iterating with pairs().

    -- 1) Merge "4" and 4 (pure numeric string keys only; not composite "15:avatar:ifrit")
    local stringNumberKeys = {};
    for k, v in pairs(mdb) do
        if type(k) == 'string' and k:match('^%d+$') and not k:find(':') and type(v) == 'table' then
            stringNumberKeys[k] = v;
        end
    end
    for k, v in pairs(stringNumberKeys) do
        local n = tonumber(k);
        if n and n > 0 then
            if mdb[n] and type(mdb[n]) == 'table' then
                for _, m in ipairs(v) do
                    table.insert(mdb[n], m);
                end
            else
                mdb[n] = v;
            end
            mdb[k] = nil;
        end
    end
    -- 2) Deduplicate ids per bucket (stable: first row wins, later duplicates renumbered)
    for _, macros in pairs(mdb) do
        if type(macros) == 'table' then
            local seen = {};
            local maxId = 0;
            for _, m in ipairs(macros) do
                if m and m.id and type(m.id) == 'number' and m.id > maxId then
                    maxId = m.id;
                end
            end
            for _, m in ipairs(macros) do
                if m then
                    if not m.id or type(m.id) ~= 'number' then
                        maxId = maxId + 1;
                        m.id = maxId;
                        seen[m.id] = true;
                    elseif seen[m.id] then
                        repeat
                            maxId = maxId + 1;
                        until not seen[maxId];
                        m.id = maxId;
                        seen[m.id] = true;
                    else
                        seen[m.id] = true;
                    end
                end
            end
        end
    end
end

local function RebuildMacroLookup()
    if gConfig then
        M.EnsureMacroDatabaseCoherence(gConfig);
    end
    macroIdLookup = {};
    if gConfig and gConfig.macroDB then
        for paletteKey, macros in pairs(gConfig.macroDB) do
            macroIdLookup[paletteKey] = {};
            if type(macros) == 'table' then
                for _, macro in ipairs(macros) do
                    if macro and macro.id then
                        -- First wins: matches ipairs order in macropalette M.GetMacroById
                        if not macroIdLookup[paletteKey][macro.id] then
                            macroIdLookup[paletteKey][macro.id] = macro;
                        end
                    end
                end
            end
        end
    end
    macroIdLookupDirty = false;
end

local function GetMacroFromLookup(macroId, paletteKey)
    if macroIdLookupDirty then
        RebuildMacroLookup();
    end
    local function try(pk)
        local t = macroIdLookup[pk];
        if t then
            return t[macroId];
        end
        return nil;
    end
    local m = try(paletteKey);
    if m then
        return m;
    end
    if type(paletteKey) == 'number' and paletteKey > 0 then
        m = try(tostring(paletteKey));
        if m then
            return m;
        end
    end
    if type(paletteKey) == 'string' and paletteKey:match('^%d+$') then
        local n = tonumber(paletteKey);
        if n and n > 0 then
            m = try(n);
            if m then
                return m;
            end
        end
    end
    return nil;
end

-- ============================================
-- Performance: Storage Key Cache
-- ============================================
-- Eliminates 72+ string allocations per frame from GetStorageKeyForBar

local storageKeyCache = {};  -- storageKeyCache[barIndex] = storageKey
local storageKeyCacheDirty = true;

-- ============================================
-- Constants
-- ============================================

M.NUM_BARS = 6;                    -- Total number of hotbars
M.SLOTS_PER_BAR = 12;              -- Default slots per hotbar
M.MAX_SLOTS_PER_BAR = 12;          -- Maximum slots per hotbar

-- Layout constants
M.PADDING = 4;
M.BUTTON_GAP = 8;
M.LABEL_GAP = -8;  -- Default label position offset (was 4, moved up by 12px)
M.ROW_GAP = 6;

-- ============================================
-- Per-Bar State
-- ============================================

-- Background primitive handles (one per bar)
M.bgHandles = {};

-- Button slot primitives (per bar, per slot)
-- M.slotPrims[barIndex][slotIndex] = primitive
M.slotPrims = {};

-- Fonts for keybind labels (per bar, per slot)
-- M.keybindFonts[barIndex][slotIndex] = font
M.keybindFonts = {};

-- Fonts for action labels (per bar, per slot)
-- M.labelFonts[barIndex][slotIndex] = font
M.labelFonts = {};

-- Icon primitives (per bar, per slot)
-- Renders action icons as primitives instead of ImGui
M.iconPrims = {};

-- Cooldown overlay primitives (per bar, per slot)
-- Dark overlay shown when action is on cooldown
M.cooldownPrims = {};

-- Frame overlay primitives (per bar, per slot)
-- Decorative frame rendered above icons
M.framePrims = {};

-- Cooldown timer fonts (per bar, per slot)
-- Shows remaining recast time (e.g., "2:30", "45s")
M.timerFonts = {};

-- MP cost fonts (per bar, per slot)
-- Shows MP cost for magic spells
M.mpCostFonts = {};

-- Item quantity fonts (per bar, per slot)
-- Shows quantity of usable items (e.g., "x5")
M.quantityFonts = {};

-- Abbreviation fonts (per bar, per slot)
-- Shows text abbreviation when action has no icon
M.abbreviationFonts = {};

-- Fonts for hotbar numbers (1-6)
M.hotbarNumberFonts = {};

-- All fonts for batch operations
M.allFonts = nil;

-- ============================================
-- Job State
-- ============================================

M.jobId = nil;
M.subjobId = nil;

-- ============================================
-- Helper Functions
-- ============================================

-- Special key for global (non-job-specific) slot storage
local GLOBAL_SLOT_KEY = 'global';

-- Helper to normalize job ID to number (handles string keys from JSON)
local function normalizeJobId(jobId)
    if type(jobId) == 'string' then
        return tonumber(jobId) or 1;
    end
    return jobId or 1;
end

-- Shared helper: resolve a storage key from settings that have a jobSpecific flag.
-- Used by both hotbar bars and crossbar.
local function resolveStorageKey(settings, jobId, subjobId)
    if settings.jobSpecific == false then
        return GLOBAL_SLOT_KEY;
    end
    local normalizedJobId = normalizeJobId(jobId);
    local normalizedSubjobId = normalizeJobId(subjobId or 0);
    return string.format('%d:%d', normalizedJobId, normalizedSubjobId);
end

-- Shared helper: look up a slotActions bucket by storage key with subjob-0 fallback.
-- Works for both hotbar (flat per-slot) and crossbar (per-combo-mode nesting) since
-- this only resolves the top-level key; callers index into the result as needed.
local function getSlotActionsForKey(slotActions, storageKey)
    if not slotActions then return nil; end
    if storageKey == GLOBAL_SLOT_KEY then
        return slotActions[GLOBAL_SLOT_KEY];
    end
    local result = slotActions[storageKey];
    if result then
        return result;
    end
    local jobId, subjobId, suffix = storageKey:match('^(%d+):(%d+)(.*)$');
    if jobId and subjobId ~= '0' then
        local fallbackKey = jobId .. ':0' .. (suffix or '');
        if fallbackKey ~= storageKey then
            return slotActions[fallbackKey];
        end
    end
    return nil;
end

-- Helper to deep copy a table (for migrating slot data)
local function deepCopyTable(tbl)
    if type(tbl) ~= 'table' then return tbl; end
    local copy = {};
    for k, v in pairs(tbl) do
        copy[k] = deepCopyTable(v);
    end
    return copy;
end

M.CopyTable = deepCopyTable;

-- Shared helper: copy the canonical set of fields from one slot data table to another.
-- Avoids repeating the field list in every Get/Set path.
local SLOT_DATA_FIELDS = {
    'actionType', 'action', 'target', 'displayName', 'equipSlot',
    'macroText', 'itemId', 'customIconType', 'customIconId', 'customIconPath',
    'recastSourceType', 'recastSourceAction', 'recastSourceItemId',
    'showJaBadgeOnMacro',
    'macroRef', 'macroPaletteKey', 'macroSourceStore',
};
-- Dual library placement: per-slot profile vs shared binding (independent of which macro file is "live").
M.MACRO_BIND_PROFILE_KEY = 'macroBindProfile';
M.MACRO_BIND_SHARED_KEY = 'macroBindShared';
local K_BIND_P = M.MACRO_BIND_PROFILE_KEY;
local K_BIND_S = M.MACRO_BIND_SHARED_KEY;
local function copySlotFields(src)
    local out = {};
    for _, k in ipairs(SLOT_DATA_FIELDS) do
        out[k] = src[k];
    end
    return out;
end


--- true when slot uses per-library macroBindProfile / macroBindShared (post-migration).
local function isDualMacroSlotTable(slotAction)
    return slotAction and type(slotAction) == 'table'
        and (slotAction[K_BIND_P] ~= nil or slotAction[K_BIND_S] ~= nil);
end

--- The active library's subtable for a macro row (or legacy flat macro slot). Returns: arm, isMacro.
local function getActiveMacroBindingFromSlot(slotAction)
    if not slotAction or type(slotAction) ~= 'table' or slotAction.cleared then
        return nil, false;
    end
    if isDualMacroSlotTable(slotAction) then
        local sh = gConfig and (gConfig.macroStorageScope or 'profile') == 'shared';
        if sh then
            return slotAction[K_BIND_S], true;
        end
        return slotAction[K_BIND_P], true;
    end
    if slotAction.macroRef and slotAction.actionType == 'macro' then
        return slotAction, true;
    end
    if slotAction.macroRef then
        return slotAction, true;
    end
    return nil, false;
end

M._GetActiveMacroBindingFromSlot = getActiveMacroBindingFromSlot;
M.IsMacroSlotDualLayout = isDualMacroSlotTable;

-- Shared helper: build a write-ready slot table from incoming slotData (Set operations).
-- Adds macroRef, macroPaletteKey, macroSourceStore on top of the canonical fields.
local function buildSlotRecord(slotData)
    local rec = copySlotFields(slotData);
    rec.macroRef = slotData.macroRef or slotData.id;
    rec.macroPaletteKey = slotData.macroPaletteKey;
    rec.macroSourceStore = slotData.macroSourceStore;
    return rec;
end

--- Build a parent macro slot with one arm set from a palette drop, preserving the other arm from existing.
function M.BuildMacroSlotAfterDrop(armData, sourceStore, existingParentSlot)
    -- sourceStore: 'profile' | 'shared' (GetMacroSourceTagForDrops)
    local sh = (sourceStore or 'profile') == 'shared';
    local arm = buildSlotRecord(armData);
    if not sh and arm.macroSourceStore == nil then
        arm.macroSourceStore = 'profile';
    end
    if sh and arm.macroSourceStore == nil then
        arm.macroSourceStore = 'shared';
    end
    local out = { actionType = 'macro' };
    if existingParentSlot and isDualMacroSlotTable(existingParentSlot) then
        out[K_BIND_P] = existingParentSlot[K_BIND_P] and deepCopyTable(existingParentSlot[K_BIND_P]);
        out[K_BIND_S] = existingParentSlot[K_BIND_S] and deepCopyTable(existingParentSlot[K_BIND_S]);
    elseif existingParentSlot and existingParentSlot.macroRef and not isDualMacroSlotTable(existingParentSlot) then
        -- migrate-on-write: one legacy binding → the appropriate arm
        local leg = buildSlotRecord(existingParentSlot);
        if (existingParentSlot.macroSourceStore or 'profile') == 'shared' then
            out[K_BIND_S] = leg;
        else
            out[K_BIND_P] = leg;
        end
    else
        out[K_BIND_P] = nil;
        out[K_BIND_S] = nil;
    end
    if sh then
        out[K_BIND_S] = arm;
    else
        out[K_BIND_P] = arm;
    end
    if out[K_BIND_P] and out[K_BIND_S] and out[K_BIND_P] == out[K_BIND_S] then
        out[K_BIND_S] = deepCopyTable(out[K_BIND_S]);
    end
    return out;
end

-- Shared helper: resolve a slot's macroRef to live macro data if available.
-- Returns a fresh table with canonical fields, the original non-macro slotAction, or nil if the
-- slot should not display (e.g. Shared scope with no match in the shared library).
-- macroSourceStore disambiguates profile vs global shared; in Shared scope, profile-tagged keys do not show.
local function resolveSlotMacro(slotAction)
    if not slotAction then
        return nil;
    end
    if slotAction.cleared then
        return nil;
    end

    local arm, isMacro = getActiveMacroBindingFromSlot(slotAction);
    if not isMacro then
        return slotAction;
    end
    if not arm or not arm.macroRef then
        if isDualMacroSlotTable(slotAction) then
            return nil;
        end
        return slotAction;
    end

    local paletteKey = arm.macroPaletteKey or (M.jobId or 1);
    local gcfg = gConfig;
    local scopeShared = gcfg and (gcfg.macroStorageScope or 'profile') == 'shared';
    local mss = arm.macroSourceStore;
    if not mss and isDualMacroSlotTable(slotAction) then
        if scopeShared and arm == slotAction[K_BIND_S] then
            mss = 'shared';
        elseif not scopeShared and arm == slotAction[K_BIND_P] then
            mss = 'profile';
        end
    end
    if not mss and arm == slotAction then
        -- Unscoped legacy hotbar/crossbar macro slots behave as profile library binds; hidden in shared scope.
        mss = slotAction.macroSourceStore or 'profile';
    end
    local liveMacro;
    if mss == 'shared' and not scopeShared then
        local ok, sms = pcall(require, 'core.shared_macro_store');
        if ok and sms and sms.LookupInDiskSharedFile then
            liveMacro = sms.LookupInDiskSharedFile(arm.macroRef, paletteKey);
        end
    elseif mss == 'profile' and scopeShared then
        -- Shared mode: do not show profile library binding — empty until re-drag from shared.
        liveMacro = nil;
    else
        liveMacro = M.GetMacroById and M.GetMacroById(arm.macroRef, paletteKey);
    end
    if not liveMacro then
        if scopeShared then
            return nil;
        end
        return slotAction;
    end
    local out = copySlotFields(liveMacro);
    out.macroRef = arm.macroRef;
    out.macroPaletteKey = arm.macroPaletteKey;
    out.macroSourceStore = mss;
    return out;
end

--- Raw crossbar blobs still hold inactive macro arms (profile vs shared) while the HUD shows empty for the other library.
--- Swap/drag reads use raw tables — align them with what resolveSlotMacro would display so "blank" slots behave empty.
function M.NormalizeCrossbarSlotRawForSwap(raw)
    if raw == nil then return nil; end
    if type(raw) ~= 'table' or raw.cleared then return nil; end
    if resolveSlotMacro(raw) == nil then
        return nil;
    end
    return raw;
end

--- In-place: legacy single macro binding -> macroBindProfile or macroBindShared.
local function migrateOneSlotToDualMacroBindings(slot)
    if not slot or type(slot) ~= 'table' or slot.cleared then
        return false;
    end
    if isDualMacroSlotTable(slot) then
        return false;
    end
    if not slot.macroRef then
        return false;
    end
    if slot.actionType and slot.actionType ~= 'macro' then
        return false;
    end
    local arm = copySlotFields(slot);
    arm.macroRef = slot.macroRef or slot.id;
    arm.macroPaletteKey = slot.macroPaletteKey;
    arm.macroSourceStore = slot.macroSourceStore;
    for _, k in ipairs(SLOT_DATA_FIELDS) do
        slot[k] = nil;
    end
    slot.actionType = 'macro';
    if (arm.macroSourceStore or 'profile') == 'shared' then
        slot[K_BIND_S] = arm;
        slot[K_BIND_P] = nil;
    else
        slot[K_BIND_P] = arm;
        slot[K_BIND_S] = nil;
    end
    return true;
end

local function migrateHotbarSlotActionsTable(slotActions)
    if not slotActions or type(slotActions) ~= 'table' then
        return;
    end
    for _, jobSlotActions in pairs(slotActions) do
        if type(jobSlotActions) == 'table' then
            for _, slot in pairs(jobSlotActions) do
                if type(slot) == 'table' then
                    migrateOneSlotToDualMacroBindings(slot);
                end
            end
        end
    end
end

local function migrateCrossbarSlotActionsTable(slotActions)
    if not slotActions or type(slotActions) ~= 'table' then
        return;
    end
    local comboModes = { 'L2', 'R2', 'L2R2', 'R2L2', 'L2x2', 'R2x2' };
    for _, jobSlotActions in pairs(slotActions) do
        if type(jobSlotActions) == 'table' then
            for _, comboMode in ipairs(comboModes) do
                local comboSlots = jobSlotActions[comboMode];
                if type(comboSlots) == 'table' then
                    for _, slot in pairs(comboSlots) do
                        if type(slot) == 'table' then
                            migrateOneSlotToDualMacroBindings(slot);
                        end
                    end
                end
            end
        end
    end
end

--- One-time per-load migration: split macro hotbar/crossbar refs into profile vs shared arms.
function M.MigrateSlotDualMacroBindings(gConfig)
    if not gConfig then
        return;
    end
    for bar = 1, 6 do
        local configKey = 'hotbarBar' .. bar;
        local barSettings = gConfig[configKey];
        if barSettings and barSettings.slotActions then
            migrateHotbarSlotActionsTable(barSettings.slotActions);
        end
    end
    if gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.slotActions then
        migrateCrossbarSlotActionsTable(gConfig.hotbarCrossbar.slotActions);
    end
end

--- Unresolved slot as stored in config (for dual-arm swap / drop merge).
function M.GetRawHotbarSlotAction(barIndex, slotIndex)
    if not gConfig then
        return nil;
    end
    local configKey = 'hotbarBar' .. barIndex;
    local barSettings = gConfig[configKey];
    if not barSettings or not barSettings.slotActions then
        return nil;
    end
    local storageKey = M.GetStorageKeyForBar(barIndex);
    local jobSlotActions = getSlotActionsForKey(barSettings.slotActions, storageKey);
    if not jobSlotActions then
        return nil;
    end
    local n = tonumber(slotIndex) or slotIndex;
    return jobSlotActions[n] or jobSlotActions[tostring(n)];
end

function M.GetRawCrossbarSlotAction(comboMode, slotIndex)
    if not gConfig or not gConfig.hotbarCrossbar or not gConfig.hotbarCrossbar.slotActions then
        return nil;
    end
    -- M.*: local GetEffectiveComboModeForStorage is defined later; bare name would read as a nil global here.
    local effectiveComboMode = M.GetEffectiveComboModeForStorage(comboMode);
    local storageKey = M.GetCrossbarStorageKeyForCombo(effectiveComboMode);
    local jobSlotActions = getSlotActionsForKey(gConfig.hotbarCrossbar.slotActions, storageKey);
    if not jobSlotActions or not jobSlotActions[effectiveComboMode] then
        return nil;
    end
    return jobSlotActions[effectiveComboMode][slotIndex];
end

--- Convert legacy layout to dual for swap / merge logic. nil or cleared => empty macro slot (no arms yet).
function M.DualizeRawMacroSlotForMerge(raw)
    if not raw or type(raw) ~= 'table' or raw.cleared then
        return { actionType = 'macro' };
    end
    if isDualMacroSlotTable(raw) then
        return deepCopyTable(raw);
    end
    if not raw.macroRef then
        return deepCopyTable(raw);
    end
    if raw.actionType and raw.actionType ~= 'macro' then
        return deepCopyTable(raw);
    end
    local arm = copySlotFields(raw);
    arm.macroRef = raw.macroRef or raw.id;
    arm.macroPaletteKey = raw.macroPaletteKey;
    arm.macroSourceStore = raw.macroSourceStore;
    local out = { actionType = 'macro' };
    if (raw.macroSourceStore or 'profile') == 'shared' then
        out[K_BIND_S] = arm;
    else
        out[K_BIND_P] = arm;
    end
    return out;
end

function M.FinalizeHotbarRawSlotForStorage(s)
    if s == nil then
        return { cleared = true };
    end
    if type(s) ~= 'table' then
        return s;
    end
    if s.cleared then
        return s;
    end
    if s.actionType == 'macro' and not s[K_BIND_P] and not s[K_BIND_S] and not s.macroRef then
        return { cleared = true };
    end
    return s;
end

-- Crossbar empty slots are nil (not { cleared = true }).
function M.FinalizeCrossbarRawSlotForStorage(s)
    if not s or type(s) ~= 'table' then
        return s;
    end
    if s.cleared then
        return nil;
    end
    if s.actionType == 'macro' and not s[K_BIND_P] and not s[K_BIND_S] and not s.macroRef then
        return nil;
    end
    return s;
end

local function macroPaletteKeysEqualData(a, b)
    if a == b then
        return true;
    end
    if a == nil or b == nil then
        return false;
    end
    local na, nb = tonumber(a), tonumber(b);
    if na ~= nil and nb ~= nil then
        return na == nb;
    end
    return false;
end

local function macroArmMatchesDelete(arm, macroId, deletedTypeKey, onlyBucketForThisId, deleteKind)
    if not arm or type(arm) ~= 'table' or arm.macroRef ~= macroId then
        return false;
    end
    deleteKind = deleteKind or 'profile';
    local mss = arm.macroSourceStore;
    if deleteKind == 'shared' then
        if mss == 'profile' then
            return false;
        end
    else
        if mss == 'shared' then
            return false;
        end
    end
    local spk = arm.macroPaletteKey;
    if spk ~= nil then
        return macroPaletteKeysEqualData(spk, deletedTypeKey);
    end
    return onlyBucketForThisId;
end

-- Clear macro arms that refer to a deleted macro row. emptyWhenGone: hotbar { cleared = true } or crossbar nil.
function M.ApplyMacroDeleteToSlotAction(slotAction, macroId, deletedTypeKey, onlyBucketForThisId, deleteKind, emptyWhenGone)
    if not slotAction or type(slotAction) ~= 'table' or slotAction.cleared then
        return nil, false;
    end
    if isDualMacroSlotTable(slotAction) then
        local out = deepCopyTable(slotAction);
        local chg = false;
        if macroArmMatchesDelete(out[K_BIND_P], macroId, deletedTypeKey, onlyBucketForThisId, deleteKind) then
            out[K_BIND_P] = nil;
            chg = true;
        end
        if macroArmMatchesDelete(out[K_BIND_S], macroId, deletedTypeKey, onlyBucketForThisId, deleteKind) then
            out[K_BIND_S] = nil;
            chg = true;
        end
        if not chg then
            return nil, false;
        end
        if not out[K_BIND_P] and not out[K_BIND_S] then
            return emptyWhenGone, true;
        end
        out.actionType = 'macro';
        return out, true;
    end
    if not slotAction.macroRef or slotAction.macroRef ~= macroId then
        return nil, false;
    end
    if not macroArmMatchesDelete(slotAction, macroId, deletedTypeKey, onlyBucketForThisId, deleteKind) then
        return nil, false;
    end
    return emptyWhenGone, true;
end

--- True when a macro arm should be cleared because its entire palette bucket was removed.
local function macroArmMatchesBucketRemove(arm, removedBucketKey, deleteKind)
    if not arm or type(arm) ~= 'table' or not arm.macroRef then
        return false;
    end
    deleteKind = deleteKind or 'profile';
    local mss = arm.macroSourceStore;
    if deleteKind == 'shared' then
        if mss == 'profile' then
            return false;
        end
    else
        if mss == 'shared' then
            return false;
        end
    end
    if arm.macroPaletteKey == nil then
        return false;
    end
    return macroPaletteKeysEqualData(arm.macroPaletteKey, removedBucketKey);
end

-- After removing an entire custom:* (or any) macro palette bucket: clear all bindings to that key.
-- deleteKind: 'profile' = profile-library arms, 'shared' = shared-library arms. emptyWhenGone: hotbar {cleared} / cross nil.
function M.ApplyMacroPaletteBucketRemovedToSlotAction(slotAction, removedBucketKey, deleteKind, emptyWhenGone)
    if not slotAction or type(slotAction) ~= 'table' or slotAction.cleared then
        return nil, false;
    end
    if isDualMacroSlotTable(slotAction) then
        local out = deepCopyTable(slotAction);
        local chg = false;
        if macroArmMatchesBucketRemove(out[K_BIND_P], removedBucketKey, deleteKind) then
            out[K_BIND_P] = nil;
            chg = true;
        end
        if macroArmMatchesBucketRemove(out[K_BIND_S], removedBucketKey, deleteKind) then
            out[K_BIND_S] = nil;
            chg = true;
        end
        if not chg then
            return nil, false;
        end
        if not out[K_BIND_P] and not out[K_BIND_S] then
            return emptyWhenGone, true;
        end
        out.actionType = 'macro';
        return out, true;
    end
    if not slotAction.macroRef then
        return nil, false;
    end
    if not macroArmMatchesBucketRemove(slotAction, removedBucketKey, deleteKind) then
        return nil, false;
    end
    return emptyWhenGone, true;
end

local function isLibraryMacroSlotForSwap(s)
    if not s or type(s) ~= 'table' or s.cleared then
        return false;
    end
    if s[K_BIND_P] ~= nil or s[K_BIND_S] ~= nil then
        return true;
    end
    if s.macroRef and (not s.actionType or s.actionType == 'macro') then
        return true;
    end
    return false;
end

-- If profile and shared arm tables are the same reference (data corruption or legacy bug), the active-arm
-- swap can move a profile binding into the wrong key or "clone" the same row — split into two tables.
local function disambiguateDualMacroArms(t)
    if not t or type(t) ~= 'table' then
        return;
    end
    if t[K_BIND_P] ~= nil and t[K_BIND_S] ~= nil and t[K_BIND_P] == t[K_BIND_S] then
        t[K_BIND_S] = deepCopyTable(t[K_BIND_S]);
    end
end

--- Exchange only the active library's arm when both slots are palette macro bindings; else swap whole slot tables.
-- rawA = source slot (dragged from), rawB = target slot (dropped onto).
-- Returns (value for target index, value for source index) for callers that assign:
--   job[target] = first; job[source] = second
function M.SwapActiveMacroArmsInPlace(rawA, rawB)
    if isLibraryMacroSlotForSwap(rawA) and isLibraryMacroSlotForSwap(rawB) then
        local a = M.DualizeRawMacroSlotForMerge(rawA);
        local b = M.DualizeRawMacroSlotForMerge(rawB);
        disambiguateDualMacroArms(a);
        disambiguateDualMacroArms(b);
        local sh = (gConfig and (gConfig.macroStorageScope or 'profile') == 'shared');
        local k = sh and K_BIND_S or K_BIND_P;
        local t = a[k];
        a[k] = b[k];
        b[k] = t;
        -- Deep copy so we never return tables that still alias nested refs from the other cell or from gConfig.
        return deepCopyTable(b), deepCopyTable(a);
    end
    return deepCopyTable(rawA), deepCopyTable(rawB);
end

-- Merge slot maps when migrating legacy job:subjob:petKey -> petpalette:petKey (fill empty slots only)
local function mergeHotbarSlotActions(dst, src)
    if type(dst) ~= 'table' or type(src) ~= 'table' then
        return;
    end
    for si, action in pairs(src) do
        if dst[si] == nil then
            dst[si] = deepCopyTable(action);
        elseif type(dst[si]) == 'table' and dst[si].cleared
            and type(action) == 'table' and not action.cleared then
            dst[si] = deepCopyTable(action);
        end
    end
end

local function mergeCrossbarComboSlotActions(dst, src)
    if type(dst) ~= 'table' or type(src) ~= 'table' then
        return;
    end
    for comboMode, slots in pairs(src) do
        if type(slots) == 'table' then
            if not dst[comboMode] then
                dst[comboMode] = {};
            end
            mergeHotbarSlotActions(dst[comboMode], slots);
        end
    end
end

-- One-time migration: legacy '{job}:{sub}:{petKey}' -> 'petpalette:{petKey}' for pet-aware storage
function M.MigratePetAwareSlotStorageKeys()
    if not gConfig then
        return false;
    end
    local changed = false;
    local palPrefix = 'palette:';

    local function shouldMigrateKey(remainder)
        if not remainder or remainder == '' then
            return false;
        end
        if remainder:sub(1, #palPrefix) == palPrefix then
            return false;
        end
        if remainder:sub(1, #PETPALETTE_STORAGE_PREFIX) == PETPALETTE_STORAGE_PREFIX then
            return false;
        end
        return petregistry.IsValidPetKey(remainder);
    end

    local function migrateFlatSlotActions(slotActions)
        if not slotActions or type(slotActions) ~= 'table' then
            return;
        end
        local moves = {};
        for key, payload in pairs(slotActions) do
            if type(key) == 'string' and type(payload) == 'table' then
                local jid, sjid, remainder = key:match('^(%d+):(%d+):(.+)$');
                if jid and sjid and shouldMigrateKey(remainder) then
                    local newKey = PETPALETTE_STORAGE_PREFIX .. remainder;
                    moves[key] = newKey;
                end
            end
        end
        for oldKey, newKey in pairs(moves) do
            local oldData = slotActions[oldKey];
            slotActions[oldKey] = nil;
            changed = true;
            if not slotActions[newKey] then
                slotActions[newKey] = deepCopyTable(oldData);
            else
                mergeHotbarSlotActions(slotActions[newKey], oldData);
            end
        end
    end

    local function migrateCrossbarSlotActions(slotActions)
        if not slotActions or type(slotActions) ~= 'table' then
            return;
        end
        local moves = {};
        for key, payload in pairs(slotActions) do
            if type(key) == 'string' and type(payload) == 'table' then
                local jid, sjid, remainder = key:match('^(%d+):(%d+):(.+)$');
                if jid and sjid and shouldMigrateKey(remainder) then
                    local newKey = PETPALETTE_STORAGE_PREFIX .. remainder;
                    moves[key] = newKey;
                end
            end
        end
        for oldKey, newKey in pairs(moves) do
            local oldData = slotActions[oldKey];
            slotActions[oldKey] = nil;
            changed = true;
            if not slotActions[newKey] then
                slotActions[newKey] = deepCopyTable(oldData);
            else
                mergeCrossbarComboSlotActions(slotActions[newKey], oldData);
            end
        end
    end

    for barIndex = 1, M.NUM_BARS do
        local configKey = 'hotbarBar' .. barIndex;
        local barSettings = gConfig[configKey];
        if barSettings and barSettings.slotActions then
            migrateFlatSlotActions(barSettings.slotActions);
        end
    end
    if gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.slotActions then
        migrateCrossbarSlotActions(gConfig.hotbarCrossbar.slotActions);
    end
    if changed then
        NotifySlotDataChanged();
    end
    return changed;
end

-- Shared helper: ensure slotActions structure exists for a storage key.
-- When comboMode is provided (crossbar), also ensures the combo-mode sub-table and returns it.
-- When comboMode is nil (hotbar), returns the top-level bucket for the key.
-- Copies from subjob-0 fallback when creating a new key to preserve data across subjob changes.
local function ensureSlotActionsStructure(settings, storageKey, comboMode)
    if not settings.slotActions then
        settings.slotActions = {};
    end
    if storageKey == GLOBAL_SLOT_KEY then
        if not settings.slotActions[GLOBAL_SLOT_KEY] then
            settings.slotActions[GLOBAL_SLOT_KEY] = {};
        end
        local bucket = settings.slotActions[GLOBAL_SLOT_KEY];
        if comboMode then
            if not bucket[comboMode] then bucket[comboMode] = {}; end
            return bucket[comboMode];
        end
        return bucket;
    end
    if not settings.slotActions[storageKey] then
        local jobId, subjobId, suffix = storageKey:match('^(%d+):(%d+)(.*)$');
        if jobId and subjobId ~= '0' then
            local fallbackKey = jobId .. ':0' .. (suffix or '');
            local fallbackData = settings.slotActions[fallbackKey];
            if fallbackData then
                settings.slotActions[storageKey] = deepCopyTable(fallbackData);
            else
                settings.slotActions[storageKey] = {};
            end
        else
            settings.slotActions[storageKey] = {};
        end
    end
    local bucket = settings.slotActions[storageKey];
    if comboMode then
        if not bucket[comboMode] then bucket[comboMode] = {}; end
        return bucket[comboMode];
    end
    return bucket;
end

-- Keys that are always per-bar (never pulled from global)
local PER_BAR_ONLY_KEYS = {
    enabled = true,
    rows = true,
    columns = true,
    slots = true,
    useGlobalSettings = true,
    keyBindings = true,
    slotActions = true,
    jobSpecific = true,
    petAware = true,
    showPetIndicator = true,
    petPalettePetKeys = true,
};

-- ============================================
-- Job/Subjob Storage Key Resolution
-- ============================================

-- Build full storage key for a bar, considering job, subjob, pet awareness, and general palettes
-- Returns: 'global', '{jobId}:{subjobId}' (base), 'petpalette:{petKey}' (pet), or '{jobId}:{subjobId}:palette:{name}' (palette)
-- Priority: global > pet-aware > general palette > base
-- NOTE: Palettes can be subjob-specific or shared (subjob 0), with fallback to shared if no subjob-specific exist
-- OPTIMIZED: Results are cached to avoid 72+ string allocations per frame
function M.GetStorageKeyForBar(barIndex)
    -- Check cache first (major optimization for runtime rendering)
    if not storageKeyCacheDirty and storageKeyCache[barIndex] then
        return storageKeyCache[barIndex];
    end

    local configKey = 'hotbarBar' .. barIndex;
    local barSettings = gConfig and gConfig[configKey];
    local jobId = M.jobId or 1;
    local subjobId = M.subjobId or 0;
    local normalizedJobId = normalizeJobId(jobId);
    local normalizedSubjobId = normalizeJobId(subjobId);

    -- Build base job:subjob key (used for base slots - subjob-specific)
    local baseKey = string.format('%d:%d', normalizedJobId, normalizedSubjobId);

    if not barSettings then
        storageKeyCache[barIndex] = baseKey;
        return baseKey;
    end

    local result;

    -- Global mode (non-job-specific)
    if barSettings.jobSpecific == false then
        result = GLOBAL_SLOT_KEY;
    else
        -- Check if pet-aware mode is enabled for this bar
        local petKey = nil;
        if barSettings.petAware then
            -- Get pet palette module (lazy load)
            local pp = getPetPalette();
            if pp then
                -- Check for manual override or auto-detected pet
                petKey = pp.GetEffectivePetKey(barIndex);
                if petKey and not petAllowlist.Allows(barSettings, petKey) then
                    petKey = nil;
                end
            end
        end

        if petKey then
            result = PETPALETTE_STORAGE_PREFIX .. petKey;
        else
            -- Check for general palette (user-defined named palettes)
            -- Palettes use subjob-aware keys with fallback to shared (subjob 0) if no subjob-specific exist
            local p = getPalette();
            local paletteSuffix = p and p.GetEffectivePaletteKeySuffix(barIndex);
            if paletteSuffix then
                -- Determine which subjobId to use: check if using fallback to shared palettes
                local effectiveSubjobId = normalizedSubjobId;
                if p.IsUsingFallbackPalettes and p.IsUsingFallbackPalettes(normalizedJobId, normalizedSubjobId) then
                    effectiveSubjobId = 0;  -- Use shared palette key
                end
                -- NEW FORMAT: '{jobId}:{subjobId}:palette:{name}'
                result = string.format('%d:%d:%s', normalizedJobId, effectiveSubjobId, paletteSuffix);
            else
                -- No pet or palette - fall back to base job:subjob key
                result = baseKey;
            end
        end
    end

    -- Cache the result
    storageKeyCache[barIndex] = result;

    -- If we've cached all bars, mark cache as clean
    local allCached = true;
    for i = 1, M.NUM_BARS do
        if not storageKeyCache[i] then
            allCached = false;
            break;
        end
    end
    if allCached then
        storageKeyCacheDirty = false;
    end

    return result;
end

-- Get available storage keys (palettes) for a bar
-- Used for cycling and display
-- Returns combined list of pet palettes (if petAware) and general palettes
function M.GetAvailablePalettes(barIndex)
    local configKey = 'hotbarBar' .. barIndex;
    local barSettings = gConfig and gConfig[configKey];
    local jobId = M.jobId or 1;
    local subjobId = M.subjobId or 0;

    local palettes = {};

    -- Add pet palettes if pet-aware mode is enabled
    if barSettings and barSettings.petAware then
        local pp = getPetPalette();
        if pp then
            local petPalettes = pp.GetAvailablePalettes(barIndex, jobId, subjobId);
            for _, p in ipairs(petPalettes) do
                if p.key == nil or petAllowlist.Allows(barSettings, p.key) then
                    table.insert(palettes, p);
                end
            end
        end
    end

    -- Add general palettes (if any exist)
    local p = getPalette();
    if p then
        local generalPalettes = p.GetAvailablePalettes(barIndex, jobId, subjobId);
        for _, name in ipairs(generalPalettes) do
            -- Convert general palette name to the same format as pet palettes
            table.insert(palettes, {
                key = p.PALETTE_KEY_PREFIX .. name,
                displayName = name,
                isPetPalette = false,
            });
        end
    end

    return palettes;
end

-- Get the current palette display name for a bar
-- Returns: nil (no palette), pet name (e.g., 'Ifrit'), or general palette name (e.g., 'Stuns')
function M.GetCurrentPaletteDisplayName(barIndex)
    local configKey = 'hotbarBar' .. barIndex;
    local barSettings = gConfig and gConfig[configKey];
    local jobId = M.jobId or 1;

    -- Check pet palette first (if pet-aware)
    if barSettings and barSettings.petAware then
        local pp = getPetPalette();
        if pp then
            local ek = pp.GetEffectivePetKey(barIndex);
            if ek and petAllowlist.Allows(barSettings, ek) then
                local petDisplayName = pp.GetPaletteDisplayName(barIndex, jobId);
                if petDisplayName and petDisplayName ~= 'Base' then
                    return petDisplayName;
                end
            end
        end
    end

    -- Check general palette
    local p = getPalette();
    if p then
        return p.GetActivePaletteDisplayName(barIndex);
    end

    return nil;
end

-- Get the palette module for direct access
function M.GetPaletteModule()
    return getPalette();
end

-- Get the pet palette module for direct access
function M.GetPetPaletteModule()
    return getPetPalette();
end

-- ============================================
-- Shared Expanded Bar Helper
-- ============================================

-- Map combo mode to effective storage mode (handles shared L2+R2/R2+L2 bar)
-- When useSharedExpandedBar is enabled, L2R2 and R2L2 both map to 'Shared'
-- This allows both combos to access the same bar while keeping separate bars when disabled
local function GetEffectiveComboModeForStorage(comboMode)
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if crossbarSettings and crossbarSettings.useSharedExpandedBar then
        if comboMode == 'L2R2' or comboMode == 'R2L2' then
            return 'Shared';
        end
    end
    return comboMode;
end

-- Expose for external use (e.g., crossbar icon caching)
M.GetEffectiveComboModeForStorage = GetEffectiveComboModeForStorage;

-- Job-wide shared segment storage (Edit Full Palette: Job-Shared override). effectiveComboMode = GetEffectiveComboModeForStorage(mode).
function M.BuildJobSegmentSharedStorageKey(jobId, effectiveComboMode)
    local j = normalizeJobId(jobId);
    local m = effectiveComboMode or 'L2x2';
    return string.format('jobsegment:%d:%s', j, m);
end

-- FFXI main jobs 1..22 — segment override rows are keyed per job; Global [G] redirects must resolve for the *current* job id in-game.
local SEGMENT_OVERRIDE_FALLBACK_JOB_MAX = 22;

local function GetSegmentOverrideEntry(jobId, comboMode)
    local cross = gConfig and gConfig.hotbarCrossbar;
    if not cross or not cross.segmentOverrides then
        return nil;
    end
    local eff = GetEffectiveComboModeForStorage(comboMode);
    if eff == 'L2' or eff == 'R2' then
        return nil;
    end
    local jidStr = tostring(normalizeJobId(jobId));
    local modes = cross.segmentOverrides[jidStr];
    local seg = modes and modes[eff];
    if seg and seg.scope == 'jobShared' then
        return seg, eff;
    end
    if seg and seg.scope == 'global' and type(seg.globalPalette) == 'string' and seg.globalPalette ~= '' then
        return seg, eff;
    end
    -- Legacy / partial saves: Global was only stored on the job row open in Edit Full Palette; other job ids had no entry.
    if not seg or not seg.scope then
        local anyJobShared = false;
        local globalPaletteName;
        for j = 1, SEGMENT_OVERRIDE_FALLBACK_JOB_MAX do
            local candidate = cross.segmentOverrides[tostring(j)] and cross.segmentOverrides[tostring(j)][eff];
            if candidate and candidate.scope == 'jobShared' then
                anyJobShared = true;
            elseif candidate and candidate.scope == 'global' and type(candidate.globalPalette) == 'string' and candidate.globalPalette ~= '' then
                globalPaletteName = candidate.globalPalette;
            end
        end
        if not anyJobShared and globalPaletteName then
            return { scope = 'global', globalPalette = globalPaletteName }, eff;
        end
    end
    return nil;
end

-- Resolved slotActions key when a Job-Shared / Global segment override is active (nil if none).
function M.GetSegmentOverrideResolvedStorageKey(jobId, comboMode)
    local seg, eff = GetSegmentOverrideEntry(jobId, comboMode);
    if not seg or not seg.scope then
        return nil;
    end
    if seg.scope == 'jobShared' then
        return M.BuildJobSegmentSharedStorageKey(jobId, eff);
    end
    if seg.scope == 'global' and type(seg.globalPalette) == 'string' and seg.globalPalette ~= '' then
        return getPalette().BuildUniversalCrossbarStorageKey(seg.globalPalette);
    end
    return nil;
end

-- For Edit Full Palette warnings: { scope, globalPalette?, effectiveMode } or nil
function M.GetSegmentOverrideDescriptorForJob(jobId, comboMode)
    local seg, eff = GetSegmentOverrideEntry(jobId, comboMode);
    if not seg or not seg.scope then
        return nil;
    end
    return {
        scope = seg.scope,
        globalPalette = seg.globalPalette,
        effectiveMode = eff,
    };
end

-- ============================================
-- Crossbar Storage Key Resolution (GLOBAL Palette)
-- ============================================

-- Per combo *segment* (L2, R2, …) pet type filter: comboModeSettings[mode].petPalettePetKeys, or fallback
-- hotbarCrossbar.petPalettePetKeys, or nil = all. Not per named [J] palette.
local function getCrossbarPetTypeKeysForMode(crossbarSettings, mode)
    if not crossbarSettings or not mode then
        return nil;
    end
    local cm = crossbarSettings.comboModeSettings and crossbarSettings.comboModeSettings[mode];
    if cm and cm.petPalettePetKeys ~= nil then
        return cm.petPalettePetKeys;
    end
    if crossbarSettings.petPalettePetKeys ~= nil then
        return crossbarSettings.petPalettePetKeys;
    end
    return nil;
end

-- Merge Crossbar defaults with optional per-named-palette overrides (Job [J] scope only)
local function GetMergedCrossbarComboModeSettings(comboMode)
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    local base = crossbarSettings and crossbarSettings.comboModeSettings and crossbarSettings.comboModeSettings[comboMode];
    if not base then
        base = { petAware = false, universalOverridePalette = nil };
    end
    local merged = {
        petAware = base.petAware == true,
        universalOverridePalette = base.universalOverridePalette,
        petPalettePetKeys = getCrossbarPetTypeKeysForMode(crossbarSettings, comboMode),
    };
    local p = getPalette();
    if not crossbarSettings or not p or not crossbarSettings.namedPaletteComboModeSettings then
        return merged;
    end
    if crossbarSettings.enableUniversalCrossbarPalettes and p.GetCrossbarPaletteScope() == 'universal' then
        return merged;
    end
    local jobId = M.jobId or 1;
    local subjobId = M.subjobId or 0;
    local palName = p.GetActivePaletteForCombo('L2');
    if not palName or palName == '' then
        return merged;
    end
    local tier = subjobId;
    if subjobId ~= 0 and p.GetCrossbarActivePaletteStorageSubjobForResolution then
        tier = p.GetCrossbarActivePaletteStorageSubjobForResolution(jobId, subjobId);
    end
    local storageKey = p.BuildPaletteStorageKey(jobId, tier, palName);
    local byPal = crossbarSettings.namedPaletteComboModeSettings[storageKey];
    local ovr = byPal and byPal[comboMode];
    if not ovr then
        return merged;
    end
    -- Pet palette on/off and pet-type allowlist are job-wide, not per named palette.
    if ovr.universalOverridePalette ~= nil then
        local u = ovr.universalOverridePalette;
        merged.universalOverridePalette = (type(u) == 'string' and u ~= '') and u or nil;
    end
    return merged;
end

-- Build full storage key for a crossbar combo mode, considering job, subjob, pet awareness, and palettes
-- Returns: 'global', 'global:palette:{name}', '{jobId}:{subjobId}', 'petpalette:{petKey}',
--   or '{jobId}:{subjobId}:palette:{name}'
function M.GetCrossbarStorageKeyForCombo(comboMode)
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    if not crossbarSettings then
        return string.format('%d:%d', M.jobId or 1, M.subjobId or 0);
    end

    local jobId = M.jobId or 1;
    local subjobId = M.subjobId or 0;
    local normalizedJobId = normalizeJobId(jobId);
    local normalizedSubjobId = normalizeJobId(subjobId);

    -- Global mode (non-job-specific single flat slot map)
    if crossbarSettings.jobSpecific == false then
        return GLOBAL_SLOT_KEY;
    end

    local baseKey = string.format('%d:%d', normalizedJobId, normalizedSubjobId);
    local modeSettings = GetMergedCrossbarComboModeSettings(comboMode);
    local p = getPalette();

    -- [G] L1+R1 scope: all combos use all-jobs storage keys; pet never applies (including per-combo [G] attach)
    if crossbarSettings.enableUniversalCrossbarPalettes and p and p.GetCrossbarPaletteScope() == 'universal' then
        if modeSettings and type(modeSettings.universalOverridePalette) == 'string' and modeSettings.universalOverridePalette ~= '' then
            return p.BuildUniversalCrossbarStorageKey(modeSettings.universalOverridePalette);
        end
        local uName = p.GetActiveUniversalCrossbarPalette();
        if uName and uName ~= '' then
            return p.BuildUniversalCrossbarStorageKey(uName);
        end
        return baseKey;
    end

    -- [J] scope: pet can override job-tier storage, including when a combo uses an attached [G] palette name
    if modeSettings and modeSettings.petAware then
        local pp = getPetPalette();
        if pp then
            local effectivePetKey = pp.GetEffectivePetKeyForCombo(comboMode);
            if effectivePetKey and petAllowlist.Allows(modeSettings, effectivePetKey) then
                return PETPALETTE_STORAGE_PREFIX .. effectivePetKey;
            end
        end
    end

    -- Per-job segment override (Edit Full Palette): Job-Shared bucket or Global [G] palette source — supersedes legacy per-palette [G] attach below
    local segOvrKey = M.GetSegmentOverrideResolvedStorageKey(normalizedJobId, comboMode);
    if segOvrKey then
        return segOvrKey;
    end

    if p and modeSettings and type(modeSettings.universalOverridePalette) == 'string' and modeSettings.universalOverridePalette ~= '' then
        return p.BuildUniversalCrossbarStorageKey(modeSettings.universalOverridePalette);
    end

    -- Named job / job+subjob crossbar palettes
    if p then
        local paletteSuffix = p.GetEffectivePaletteKeySuffixForCombo(comboMode);
        if paletteSuffix then
            local tierSubjob = normalizedSubjobId;
            if normalizedSubjobId ~= 0 and p.GetCrossbarActivePaletteStorageSubjobForResolution then
                tierSubjob = p.GetCrossbarActivePaletteStorageSubjobForResolution(normalizedJobId, normalizedSubjobId);
            end
            return string.format('%d:%d:%s', normalizedJobId, tierSubjob, paletteSuffix);
        end
    end

    return baseKey;
end

-- Get the current palette display name for a crossbar combo mode
-- Returns: 'Base', pet name (e.g., 'Ifrit'), or general palette name (e.g., 'Stuns')
-- NOTE: Now uses GLOBAL crossbar palette instead of per-combo-mode
function M.GetCrossbarPaletteDisplayName(comboMode)
    local crossbarSettings = gConfig and gConfig.hotbarCrossbar;
    local modeSettings = GetMergedCrossbarComboModeSettings(comboMode);
    local jobId = M.jobId or 1;
    local p = getPalette();

    -- [G] scope: universal keys only (no pet)
    if crossbarSettings and crossbarSettings.enableUniversalCrossbarPalettes and p and p.GetCrossbarPaletteScope() == 'universal' then
        if modeSettings and type(modeSettings.universalOverridePalette) == 'string' and modeSettings.universalOverridePalette ~= '' then
            return modeSettings.universalOverridePalette;
        end
        local u = p.GetActiveUniversalCrossbarPalette();
        if u and u ~= '' then
            return u;
        end
    end

    -- [J] scope: pet wins over attached [G] palette name and job palette
    if modeSettings and modeSettings.petAware then
        local pp = getPetPalette();
        if pp then
            local ek = pp.GetEffectivePetKeyForCombo(comboMode);
            if ek and petAllowlist.Allows(modeSettings, ek) then
                local petDisplayName = pp.GetCrossbarPaletteDisplayName(comboMode, jobId);
                if petDisplayName and petDisplayName ~= 'Base' then
                    return petDisplayName;
                end
            end
        end
    end

    local segDesc = M.GetSegmentOverrideDescriptorForJob(jobId, comboMode);
    if segDesc then
        if segDesc.scope == 'global' and type(segDesc.globalPalette) == 'string' and segDesc.globalPalette ~= '' then
            return segDesc.globalPalette;
        end
        if segDesc.scope == 'jobShared' then
            local n = p and p.GetActivePaletteForCombo('L2');
            if n and n ~= '' then
                return n .. ' (job-shared)';
            end
            return 'Job-shared';
        end
    end

    if modeSettings and type(modeSettings.universalOverridePalette) == 'string' and modeSettings.universalOverridePalette ~= '' then
        return modeSettings.universalOverridePalette;
    end

    if p then
        local paletteName = p.GetActivePaletteForCombo(comboMode);
        if paletteName then
            return paletteName;
        end
    end

    return 'Base';
end

-- Get per-bar settings from gConfig, merging with global if useGlobalSettings is true
function M.GetBarSettings(barIndex)
    local configKey = 'hotbarBar' .. barIndex;
    local barConfig = gConfig and gConfig[configKey];

    if not barConfig then
        -- Return fallback defaults
        return {
            enabled = true,
            useGlobalSettings = true,
            rows = 1,
            columns = 12,
            slots = 12,
            slotSize = 48,
            bgScale = 1.0,
            borderScale = 1.0,
            backgroundOpacity = 0.87,
            borderOpacity = 1.0,
            backgroundTheme = '-None-',
            showHotbarNumber = true,
            showSlotFrame = false,
            customFramePath = '',
            showActionLabels = false,
            actionLabelOffsetX = 0,
            actionLabelOffsetY = 0,
            slotXPadding = 8,
            slotYPadding = 6,
            slotBackgroundColor = 0x55000000,
            bgColor = 0xFFFFFFFF,
            borderColor = 0xFFFFFFFF,
            showKeybinds = true,
            keybindFontSize = 10,
            keybindFontColor = 0xFFFFFFFF,
            labelFontSize = 10,
            labelFontColor = 0xFFFFFFFF,
            labelCooldownColor = 0xFF888888,
            labelNoMpColor = 0xFFFF4444,
            showMpCost = true,
            mpCostFontSize = 10,
            mpCostFontColor = 0xFFD4FF97,
            showQuantity = true,
            quantityFontSize = 10,
            quantityFontColor = 0xFFFFFFFF,
        };
    end

    -- If useGlobalSettings is true, merge global visual settings
    if barConfig.useGlobalSettings and gConfig.hotbarGlobal then
        local merged = {};
        -- Start with global settings
        for k, v in pairs(gConfig.hotbarGlobal) do
            merged[k] = v;
        end
        -- Override with per-bar settings (layout and per-bar-only keys)
        for k, v in pairs(barConfig) do
            if PER_BAR_ONLY_KEYS[k] then
                merged[k] = v;
            end
        end
        return merged;
    end

    return barConfig;
end

-- Get bar layout info (reads from per-bar settings)
function M.GetBarLayout(barIndex)
    local barSettings = M.GetBarSettings(barIndex);
    local rows = barSettings.rows or 1;
    local columns = barSettings.columns or 12;

    -- Always calculate slots from rows * columns (ignore stored slots value)
    local slots = rows * columns;

    -- Ensure slots doesn't exceed max
    slots = math.min(slots, M.MAX_SLOTS_PER_BAR);

    return {
        isVertical = rows > 1,
        columns = columns,
        rows = rows,
        slots = slots,
    };
end

-- Get number of slots for a bar
function M.GetBarSlotCount(barIndex)
    local layout = M.GetBarLayout(barIndex);
    return layout.slots;
end

-- Virtual key code to short display string mapping
local VK_SHORT_NAMES = {
    [8] = 'Bksp', [9] = 'Tab', [13] = 'Ent', [27] = 'Esc', [32] = 'Spc',
    [33] = 'PgU', [34] = 'PgD', [35] = 'End', [36] = 'Hom',
    [37] = 'L', [38] = 'U', [39] = 'R', [40] = 'D',
    [45] = 'Ins', [46] = 'Del',
    [96] = 'N0', [97] = 'N1', [98] = 'N2', [99] = 'N3', [100] = 'N4',
    [101] = 'N5', [102] = 'N6', [103] = 'N7', [104] = 'N8', [105] = 'N9',
    [106] = 'N*', [107] = 'N+', [109] = 'N-', [110] = 'N.', [111] = 'N/',
    [112] = 'F1', [113] = 'F2', [114] = 'F3', [115] = 'F4', [116] = 'F5', [117] = 'F6',
    [118] = 'F7', [119] = 'F8', [120] = 'F9', [121] = 'F10', [122] = 'F11', [123] = 'F12',
    [186] = ';', [187] = '=', [188] = ',', [189] = '-', [190] = '.', [191] = '/',
    [192] = '`', [219] = '[', [220] = '\\', [221] = ']', [222] = "'",
};

-- Convert virtual key code to short display string
local function VKToShortString(vk)
    if VK_SHORT_NAMES[vk] then return VK_SHORT_NAMES[vk]; end
    if vk >= 48 and vk <= 57 then return tostring(vk - 48); end  -- 0-9
    if vk >= 65 and vk <= 90 then return string.char(vk); end    -- A-Z
    return '?';
end

-- Format a keybind for short display (e.g., "C1" for Ctrl+1)
local function FormatKeybindShort(binding)
    if not binding or not binding.key then return ''; end
    local prefix = '';
    if binding.ctrl then prefix = prefix .. 'C'; end
    if binding.alt then prefix = prefix .. 'A'; end
    if binding.shift then prefix = prefix .. 'S'; end
    local keyStr = VKToShortString(binding.key);
    return prefix .. keyStr;
end

-- Get keybind display string for a slot
function M.GetKeybindDisplay(barIndex, slotIndex)
    -- Check for custom keybind first
    local configKey = 'hotbarBar' .. barIndex;
    local barSettings = gConfig and gConfig[configKey];
    if barSettings and barSettings.keyBindings then
        -- Handle both numeric and string keys (JSON serialization converts numeric keys to strings)
        local binding = barSettings.keyBindings[slotIndex] or barSettings.keyBindings[tostring(slotIndex)];
        if binding and binding.cleared then
            return '';
        end
        if binding and binding.key then
            return FormatKeybindShort(binding);
        end
    end

    -- No custom keybind - return empty or slot number
    return '';
end

-- Look up a macro row: macroId is unique only within the given paletteKey bucket
-- (not across jobs or global). paletteKey: job id, global/items/equipment/xiui/custom:*, or
-- composite (e.g. "15:avatar:ifrit"). OPTIMIZED: O(1) via lookup + string/number key alias.
local function GetMacroById(macroId, paletteKey)
    if not gConfig or not gConfig.macroDB then return nil; end

    -- Try the specific palette key first using O(1) lookup
    local macro = GetMacroFromLookup(macroId, paletteKey);
    if macro then
        return macro;
    end

    -- If paletteKey is a composite key and macro not found, try base job palette
    if type(paletteKey) == 'string' then
        local baseJobId = tonumber(paletteKey:match('^(%d+)'));
        if baseJobId then
            macro = GetMacroFromLookup(macroId, baseJobId);
            if macro then
                return macro;
            end
        end
    end

    return nil;
end

-- O(1) macro row lookup (paletteKey = job id, global key, or composite pet key)
M.GetMacroById = GetMacroById;

-- Get action assignment for a specific bar and slot
function M.GetKeybindForSlot(barIndex, slotIndex)
    -- First check for custom slot actions in per-bar settings
    local configKey = 'hotbarBar' .. barIndex;
    if gConfig and gConfig[configKey] then
        local barSettings = gConfig[configKey];
        -- Use pet-aware storage key (handles global, job-specific, and pet palettes)
        local storageKey = M.GetStorageKeyForBar(barIndex);
        local jobSlotActions = getSlotActionsForKey(barSettings.slotActions, storageKey);

        -- NOTE: Do NOT fall back to base job when pet palette is active
        -- If user has a pet out and petAware enabled, show the pet-specific palette (even if empty)
        -- This prevents the base job summon macros from showing when an avatar is summoned
        if jobSlotActions then
            local numericSlot = tonumber(slotIndex) or slotIndex;
            local slotAction = jobSlotActions[numericSlot] or jobSlotActions[tostring(numericSlot)];
            if slotAction then
                if slotAction.cleared then
                    return nil;
                end

                local resolved = resolveSlotMacro(slotAction);
                if not resolved then
                    return nil;
                end
                local out = copySlotFields(resolved);
                out.context = 'battle';
                out.hotbar = barIndex;
                out.slot = slotIndex;
                out.displayName = out.displayName or resolved.action;
                return out;
            end
        end
    end

    return nil;
end

-- ============================================
-- Crossbar Slot Data Helpers
-- ============================================

-- (Crossbar uses the same shared helpers: resolveStorageKey, getSlotActionsForKey, ensureSlotActionsStructure with comboMode)

-- Get slot data for a crossbar slot
-- comboMode: 'L2', 'R2', 'L2R2', 'R2L2', 'L2x2', 'R2x2', or 'Shared'
-- slotIndex: 1-8
-- Returns nil if no data exists
function M.GetCrossbarSlotData(comboMode, slotIndex)
    local jobId = M.jobId or 1;

    if not gConfig.hotbarCrossbar then return nil; end

    -- Map L2R2/R2L2 to Shared when shared expanded bar is enabled
    local effectiveComboMode = GetEffectiveComboModeForStorage(comboMode);

    -- Use per-combo-mode storage key (considers pet-aware and palette settings per combo)
    local storageKey = M.GetCrossbarStorageKeyForCombo(effectiveComboMode);
    local jobSlotActions = getSlotActionsForKey(gConfig.hotbarCrossbar.slotActions, storageKey);
    if not jobSlotActions then return nil; end
    if not jobSlotActions[effectiveComboMode] then return nil; end

    local slotAction = jobSlotActions[effectiveComboMode][slotIndex];
    return resolveSlotMacro(slotAction);
end

-- Set slot data for a crossbar slot
-- comboMode: 'L2', 'R2', 'L2R2', 'R2L2', 'L2x2', 'R2x2', or 'Shared'
-- slotIndex: 1-8
-- slotData: { actionType, action, target, displayName, equipSlot, macroText, itemId, customIconType, customIconId, customIconPath }
--           or nil to clear the slot
function M.SetCrossbarSlotData(comboMode, slotIndex, slotData)
    -- If slotData is nil, clear the slot instead
    if not slotData then
        M.ClearCrossbarSlotData(comboMode, slotIndex);
        return;
    end

    -- Ensure config structure exists using helper (handles key normalization)
    if not gConfig.hotbarCrossbar then
        gConfig.hotbarCrossbar = {};
    end

    -- Map L2R2/R2L2 to Shared when shared expanded bar is enabled
    local effectiveComboMode = GetEffectiveComboModeForStorage(comboMode);

    local storageKey = M.GetCrossbarStorageKeyForCombo(effectiveComboMode);
    local comboSlots = ensureSlotActionsStructure(gConfig.hotbarCrossbar, storageKey, effectiveComboMode);

    if isDualMacroSlotTable(slotData) then
        comboSlots[slotIndex] = slotData;
    else
        comboSlots[slotIndex] = buildSlotRecord(slotData);
    end
    M.SyncDraftSlotFromLive(comboMode, slotIndex);
    NotifySlotDataChanged();
end

-- Clear a crossbar slot (sets to nil)
-- comboMode: 'L2', 'R2', 'L2R2', 'R2L2', 'L2x2', 'R2x2', or 'Shared'
-- slotIndex: 1-8
function M.ClearCrossbarSlotData(comboMode, slotIndex)
    -- Early return if structure doesn't exist
    if not gConfig.hotbarCrossbar then return; end

    -- Map L2R2/R2L2 to Shared when shared expanded bar is enabled
    local effectiveComboMode = GetEffectiveComboModeForStorage(comboMode);

    local storageKey = M.GetCrossbarStorageKeyForCombo(effectiveComboMode);
    local jobSlotActions = getSlotActionsForKey(gConfig.hotbarCrossbar.slotActions, storageKey);
    if not jobSlotActions then return; end
    if not jobSlotActions[effectiveComboMode] then return; end

    local raw = jobSlotActions[effectiveComboMode][slotIndex];
    if isDualMacroSlotTable(raw) then
        local sh = (gConfig.macroStorageScope or 'profile') == 'shared';
        if sh then
            raw[K_BIND_S] = nil;
        else
            raw[K_BIND_P] = nil;
        end
        if not raw[K_BIND_P] and not raw[K_BIND_S] then
            jobSlotActions[effectiveComboMode][slotIndex] = nil;
        else
            raw.actionType = 'macro';
        end
    else
        jobSlotActions[effectiveComboMode][slotIndex] = nil;
    end
    M.SyncDraftSlotFromLive(comboMode, slotIndex);
    NotifySlotDataChanged();
end

-- Direct read/write for a fixed storage key (palette editor / Edit Full Palette). Does not call GetCrossbarStorageKeyForCombo.
function M.GetCrossbarSlotDataForStorageKey(storageKey, comboMode, slotIndex)
    if not gConfig or not gConfig.hotbarCrossbar or not storageKey then
        return nil;
    end
    local effectiveComboMode = GetEffectiveComboModeForStorage(comboMode);
    local jobSlotActions = getSlotActionsForKey(gConfig.hotbarCrossbar.slotActions, storageKey);
    if not jobSlotActions or not jobSlotActions[effectiveComboMode] then
        return nil;
    end
    return resolveSlotMacro(jobSlotActions[effectiveComboMode][slotIndex]);
end

function M.SetCrossbarSlotDataForStorageKey(storageKey, comboMode, slotIndex, slotData)
    if not storageKey then return; end
    if not slotData then
        M.ClearCrossbarSlotDataForStorageKey(storageKey, comboMode, slotIndex);
        return;
    end
    if not gConfig.hotbarCrossbar then
        gConfig.hotbarCrossbar = {};
    end
    local effectiveComboMode = GetEffectiveComboModeForStorage(comboMode);
    local comboSlots = ensureSlotActionsStructure(gConfig.hotbarCrossbar, storageKey, effectiveComboMode);
    if isDualMacroSlotTable(slotData) then
        comboSlots[slotIndex] = slotData;
    else
        comboSlots[slotIndex] = buildSlotRecord(slotData);
    end
    NotifySlotDataChanged();
end

function M.ClearCrossbarSlotDataForStorageKey(storageKey, comboMode, slotIndex)
    if not gConfig.hotbarCrossbar or not storageKey then return; end
    local effectiveComboMode = GetEffectiveComboModeForStorage(comboMode);
    local jobSlotActions = getSlotActionsForKey(gConfig.hotbarCrossbar.slotActions, storageKey);
    if not jobSlotActions or not jobSlotActions[effectiveComboMode] then return; end
    jobSlotActions[effectiveComboMode][slotIndex] = nil;
    NotifySlotDataChanged();
end

-- ============================================
-- Draft Layer (Edit Full Palette)
-- ============================================
-- Edits stay in a draft buffer until the user clicks Apply. deepCopyTable, buildSlotRecord,
-- resolveSlotMacro, and GetEffectiveComboModeForStorage are all defined above by this point.
-- draftByKey can hold multiple storage keys when Job-Shared / Global segment overrides redirect combo modes.

local function resolveDraftStorageKeyForCombo(comboMode)
    if not draftForStorageKey or not draftByKey then
        return nil;
    end
    if draftEditJobId then
        local sk = M.GetSegmentOverrideResolvedStorageKey(draftEditJobId, comboMode);
        if sk then
            return sk;
        end
    end
    return draftForStorageKey;
end

local function ensureDraftBucket(resolvedKey)
    if not resolvedKey or not draftByKey then
        return nil;
    end
    if not draftByKey[resolvedKey] then
        if gConfig and gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.slotActions then
            draftByKey[resolvedKey] = deepCopyTable(gConfig.hotbarCrossbar.slotActions[resolvedKey]) or {};
        else
            draftByKey[resolvedKey] = {};
        end
    end
    return draftByKey[resolvedKey];
end

--- After live `gConfig` crossbar mutations while Edit Full Palette draft is open, copy the affected slot into the draft
--- blob so the palette row matches HUD (HUD stays authoritative for gameplay binds during the session).
function M.SyncDraftSlotFromLive(comboMode, slotIndex)
    if not draftForStorageKey or not draftByKey then
        return;
    end
    local rk = resolveDraftStorageKeyForCombo(comboMode);
    if not rk then
        return;
    end
    local bucket = ensureDraftBucket(rk);
    if not bucket then
        return;
    end
    local effectiveComboMode = GetEffectiveComboModeForStorage(comboMode);
    if not bucket[effectiveComboMode] then
        bucket[effectiveComboMode] = {};
    end
    draftTouchedKeys[rk] = true;
    local liveRaw = M.GetRawCrossbarSlotAction(comboMode, slotIndex);
    if liveRaw == nil then
        bucket[effectiveComboMode][slotIndex] = DRAFT_CROSSBAR_SLOT_EMPTY;
    else
        bucket[effectiveComboMode][slotIndex] = deepCopyTable(liveRaw);
    end
    draftDirty = true;
end

--- Dual macro slots: clearing only the active arm can leave the inactive arm in the bucket while resolveSlotMacro shows empty.
--- Only dual-layout blobs need this — never run on freshly written single-arm macros (profile vs shared visibility differs).
local function scrubDraftBucketSlotIfInvisible(bucket, rk, effectiveComboMode, slotIndex)
    if not bucket or not bucket[effectiveComboMode] then
        return false;
    end
    local raw = bucket[effectiveComboMode][slotIndex];
    if raw == nil or not isDualMacroSlotTable(raw) then
        return false;
    end
    if resolveSlotMacro(raw) ~= nil then
        return false;
    end
    bucket[effectiveComboMode][slotIndex] = DRAFT_CROSSBAR_SLOT_EMPTY;
    draftTouchedKeys[rk] = true;
    return true;
end

local function pushDraftUndo()
    if draftUndoGroupActive then return; end
    if not draftByKey then return; end
    local touchedCopy = {};
    if draftTouchedKeys then
        for k, v in pairs(draftTouchedKeys) do
            touchedCopy[k] = v;
        end
    end
    table.insert(draftUndoStack, {
        blob = deepCopyTable(draftByKey),
        touched = touchedCopy,
    });
    if #draftUndoStack > DRAFT_MAX_UNDO then
        table.remove(draftUndoStack, 1);
    end
end

function M.BeginDraftUndoGroup()
    pushDraftUndo();
    draftUndoGroupActive = true;
end

function M.EndDraftUndoGroup()
    draftUndoGroupActive = false;
end

function M.BeginCrossbarPaletteEditSession(storageKey, editJobId)
    crossbarPaletteEditStorageKey = storageKey;
    local ej = editJobId;
    if draftForStorageKey == storageKey and draftByKey and draftEditJobId == ej then
        return;
    end
    draftForStorageKey = storageKey;
    draftEditJobId = ej;
    draftDirty = false;
    draftUndoStack = {};
    draftTouchedKeys = {};
    draftByKey = {};
    if gConfig and gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.slotActions and storageKey then
        draftByKey[storageKey] = deepCopyTable(gConfig.hotbarCrossbar.slotActions[storageKey]) or {};
    elseif storageKey then
        draftByKey[storageKey] = {};
    end
end

-- Segment override toggles used to clear draftForStorageKey here; that breaks GetDraftSlotData for the
-- rest of the frame and forces a full draft re-init next frame (scroll jumps, wrong row heights, data risk).
-- Resolved storage keys already update via GetSegmentOverrideResolvedStorageKey + ensureDraftBucket.
function M.InvalidateCrossbarDraftLayout()
end

function M.EndCrossbarPaletteEditSession()
    crossbarPaletteEditStorageKey = nil;
end

function M.FullyClosePaletteEditSession()
    crossbarPaletteEditStorageKey = nil;
    draftForStorageKey = nil;
    draftEditJobId = nil;
    draftByKey = nil;
    draftTouchedKeys = nil;
    draftDirty = false;
    draftUndoStack = {};
end

function M.GetDraftSlotData(comboMode, slotIndex)
    if not draftByKey then return nil; end
    local rk = resolveDraftStorageKeyForCombo(comboMode);
    if not rk then return nil; end
    local bucket = ensureDraftBucket(rk);
    if not bucket then return nil; end
    local effectiveComboMode = GetEffectiveComboModeForStorage(comboMode);
    if not bucket[effectiveComboMode] then return nil; end
    local cell = bucket[effectiveComboMode][slotIndex];
    if cell == DRAFT_CROSSBAR_SLOT_EMPTY then
        return nil;
    end
    return resolveSlotMacro(cell);
end

function M.GetDraftRawSlotData(comboMode, slotIndex)
    if not draftByKey then return nil; end
    local rk = resolveDraftStorageKeyForCombo(comboMode);
    if not rk then return nil; end
    local bucket = ensureDraftBucket(rk);
    if not bucket then return nil; end
    local effectiveComboMode = GetEffectiveComboModeForStorage(comboMode);
    if not bucket[effectiveComboMode] then return nil; end
    local v = bucket[effectiveComboMode][slotIndex];
    if v == DRAFT_CROSSBAR_SLOT_EMPTY then
        return nil;
    end
    return v;
end

--- Swap/drag reads: draft cell wins when present; explicit draft empty beats live; missing cell inherits live.
function M.GetCrossbarSlotRawForSwapOverlay(comboMode, slotIndex)
    if not draftForStorageKey or not draftByKey then
        return M.GetRawCrossbarSlotAction(comboMode, slotIndex);
    end
    local rk = resolveDraftStorageKeyForCombo(comboMode);
    if not rk then
        return M.GetRawCrossbarSlotAction(comboMode, slotIndex);
    end
    local blob = draftByKey[rk];
    if not blob then
        return M.GetRawCrossbarSlotAction(comboMode, slotIndex);
    end
    local eff = GetEffectiveComboModeForStorage(comboMode);
    local row = blob[eff];
    if not row then
        return M.GetRawCrossbarSlotAction(comboMode, slotIndex);
    end
    local v = row[slotIndex];
    if v == DRAFT_CROSSBAR_SLOT_EMPTY then
        return nil;
    end
    if v ~= nil then
        return v;
    end
    return M.GetRawCrossbarSlotAction(comboMode, slotIndex);
end

function M.SetDraftSlotData(comboMode, slotIndex, slotData)
    if not draftByKey then return; end
    if not slotData then
        M.ClearDraftSlotData(comboMode, slotIndex);
        return;
    end
    pushDraftUndo();
    local rk = resolveDraftStorageKeyForCombo(comboMode);
    if not rk then return; end
    local bucket = ensureDraftBucket(rk);
    if not bucket then return; end
    draftTouchedKeys[rk] = true;
    local effectiveComboMode = GetEffectiveComboModeForStorage(comboMode);
    if not bucket[effectiveComboMode] then
        bucket[effectiveComboMode] = {};
    end
    if isDualMacroSlotTable(slotData) then
        bucket[effectiveComboMode][slotIndex] = slotData;
    else
        bucket[effectiveComboMode][slotIndex] = buildSlotRecord(slotData);
    end
    draftDirty = true;
end

function M.ClearDraftSlotData(comboMode, slotIndex)
    if not draftByKey then return; end
    pushDraftUndo();
    local rk = resolveDraftStorageKeyForCombo(comboMode);
    if not rk then return; end
    local bucket = ensureDraftBucket(rk);
    if not bucket then return; end
    draftTouchedKeys[rk] = true;
    local effectiveComboMode = GetEffectiveComboModeForStorage(comboMode);
    if not bucket[effectiveComboMode] then return; end
    local raw = bucket[effectiveComboMode][slotIndex];
    if isDualMacroSlotTable(raw) then
        local sh = gConfig and (gConfig.macroStorageScope or 'profile') == 'shared';
        if sh then
            raw[K_BIND_S] = nil;
        else
            raw[K_BIND_P] = nil;
        end
        if not raw[K_BIND_P] and not raw[K_BIND_S] then
            bucket[effectiveComboMode][slotIndex] = DRAFT_CROSSBAR_SLOT_EMPTY;
        else
            raw.actionType = 'macro';
        end
    else
        bucket[effectiveComboMode][slotIndex] = DRAFT_CROSSBAR_SLOT_EMPTY;
    end
    scrubDraftBucketSlotIfInvisible(bucket, rk, effectiveComboMode, slotIndex);
    draftDirty = true;
end

function M.UndoDraft()
    if #draftUndoStack == 0 then return false; end
    local prev = table.remove(draftUndoStack);
    draftByKey = prev.blob;
    draftTouchedKeys = prev.touched or {};
    draftDirty = #draftUndoStack > 0;
    return true;
end

function M.CanUndoDraft()
    return #draftUndoStack > 0;
end

local function prepareDraftBlobForApply(blob)
    local out = {};
    for comboMode, row in pairs(blob) do
        out[comboMode] = {};
        for slotIndex, cell in pairs(row) do
            if cell ~= DRAFT_CROSSBAR_SLOT_EMPTY then
                out[comboMode][slotIndex] = deepCopyTable(cell);
            end
        end
    end
    return out;
end

function M.ApplyDraft()
    if not draftForStorageKey or not draftByKey then return; end
    if not gConfig.hotbarCrossbar then gConfig.hotbarCrossbar = {}; end
    if not gConfig.hotbarCrossbar.slotActions then gConfig.hotbarCrossbar.slotActions = {}; end
    for key, _ in pairs(draftTouchedKeys or {}) do
        local blob = draftByKey[key];
        if blob then
            gConfig.hotbarCrossbar.slotActions[key] = prepareDraftBlobForApply(blob);
        end
    end
    draftDirty = false;
    draftUndoStack = {};
    draftTouchedKeys = {};
    M.InvalidateStorageKeyCache();
    NotifySlotDataChanged();
end

function M.DiscardDraft()
    local key = crossbarPaletteEditStorageKey or draftForStorageKey;
    if not key then return; end
    draftByKey = {};
    draftTouchedKeys = {};
    if gConfig and gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.slotActions then
        draftByKey[key] = deepCopyTable(gConfig.hotbarCrossbar.slotActions[key]) or {};
    else
        draftByKey[key] = {};
    end
    draftDirty = false;
    draftUndoStack = {};
end

function M.IsDraftDirty()
    return draftDirty;
end

local pendingPaletteSlotEdit = nil;

function M.SetPendingPaletteSlotEdit(slotData, comboMode, slotIndex)
    pendingPaletteSlotEdit = { slotData = slotData, comboMode = comboMode, slotIndex = slotIndex };
end

function M.ConsumePendingPaletteSlotEdit()
    local edit = pendingPaletteSlotEdit;
    pendingPaletteSlotEdit = nil;
    return edit;
end

-- Clear all slot actions for a hotbar (used when switching between job-specific and global modes)
function M.ClearAllBarSlotActions(barIndex)
    local configKey = 'hotbarBar' .. barIndex;
    if gConfig and gConfig[configKey] then
        gConfig[configKey].slotActions = {};
        SaveSettingsToDisk();
    end
end

-- Clear all slot actions for the crossbar (used when switching between job-specific and global modes)
function M.ClearAllCrossbarSlotActions()
    if gConfig.hotbarCrossbar then
        gConfig.hotbarCrossbar.slotActions = {};
        SaveSettingsToDisk();
    end
end

-- ============================================
-- Pet-Aware Slot Data Functions
-- ============================================

-- Set slot data for a hotbar slot (pet-aware)
-- Uses current storage key (which considers pet-aware mode)
function M.SetSlotData(barIndex, slotIndex, slotData)
    local configKey = 'hotbarBar' .. barIndex;
    if not gConfig or not gConfig[configKey] then return; end

    local barSettings = gConfig[configKey];
    local storageKey = M.GetStorageKeyForBar(barIndex);
    local jobSlotActions = ensureSlotActionsStructure(barSettings, storageKey);

    if slotData then
        if isDualMacroSlotTable(slotData) then
            jobSlotActions[slotIndex] = slotData;
        else
            jobSlotActions[slotIndex] = buildSlotRecord(slotData);
        end
    else
        jobSlotActions[slotIndex] = { cleared = true };
    end

    NotifySlotDataChanged();
end

-- Clear slot data for a hotbar slot (pet-aware)
function M.ClearSlotData(barIndex, slotIndex)
    local configKey = 'hotbarBar' .. barIndex;
    if not gConfig or not gConfig[configKey] then return; end

    local barSettings = gConfig[configKey];
    local storageKey = M.GetStorageKeyForBar(barIndex);
    local jobSlotActions = getSlotActionsForKey(barSettings.slotActions, storageKey);

    if jobSlotActions then
        local num = tonumber(slotIndex) or slotIndex;
        local raw = jobSlotActions[num] or jobSlotActions[tostring(num)];
        if isDualMacroSlotTable(raw) then
            local sh = (gConfig.macroStorageScope or 'profile') == 'shared';
            if sh then
                raw[K_BIND_S] = nil;
            else
                raw[K_BIND_P] = nil;
            end
            if not raw[K_BIND_P] and not raw[K_BIND_S] then
                jobSlotActions[num] = { cleared = true };
                if jobSlotActions[tostring(num)] then
                    jobSlotActions[tostring(num)] = { cleared = true };
                end
            else
                raw.actionType = 'macro';
                jobSlotActions[num] = raw;
            end
        else
            jobSlotActions[num] = { cleared = true };
            if jobSlotActions[tostring(num)] then
                jobSlotActions[tostring(num)] = { cleared = true };
            end
        end
        NotifySlotDataChanged();
    end
end

-- Get the current storage key for external use (e.g., macropalette)
function M.GetCurrentStorageKey(barIndex)
    return M.GetStorageKeyForBar(barIndex);
end

-- ============================================
-- Cache Invalidation Functions
-- ============================================

-- Mark macro lookup cache as dirty (call when macroDB changes)
function M.MarkMacroLookupDirty()
    macroIdLookupDirty = true;
end

-- Invalidate storage key cache (call on palette/pet/job changes)
function M.InvalidateStorageKeyCache()
    storageKeyCacheDirty = true;
    storageKeyCache = {};
end

-- Call whenever the global gConfig table is replaced (profile switch, settings reload, reset).
-- macroIdLookup holds references into gConfig.macroDB; if gConfig is swapped without invalidating,
-- lookups can return macro rows from the previous profile in memory (wrong name/icon for macroRef).
function M.InvalidateConfigDerivedCaches()
    macroIdLookupDirty = true;
    macroDbCoherenceIdentity = nil;
    M.InvalidateStorageKeyCache();
end

-- ============================================
-- Font Visibility Helpers
-- ============================================

-- Rebuild the flattened all-fonts list used for batch operations.
-- IMPORTANT: When fonts are recreated (FontManager.recreate), references change, so we must refresh this list
-- or SetAllFontsVisible() will toggle stale/destroyed objects and leave the new fonts visible.
function M.RebuildAllFonts()
    local all = {};

    for barIndex = 1, M.NUM_BARS do
        -- Per-slot fonts
        for slotIndex = 1, M.MAX_SLOTS_PER_BAR do
            local f;

            f = M.keybindFonts[barIndex] and M.keybindFonts[barIndex][slotIndex];
            if f then table.insert(all, f); end

            f = M.labelFonts[barIndex] and M.labelFonts[barIndex][slotIndex];
            if f then table.insert(all, f); end

            f = M.timerFonts[barIndex] and M.timerFonts[barIndex][slotIndex];
            if f then table.insert(all, f); end

            f = M.mpCostFonts[barIndex] and M.mpCostFonts[barIndex][slotIndex];
            if f then table.insert(all, f); end

            f = M.quantityFonts[barIndex] and M.quantityFonts[barIndex][slotIndex];
            if f then table.insert(all, f); end

            f = M.abbreviationFonts[barIndex] and M.abbreviationFonts[barIndex][slotIndex];
            if f then table.insert(all, f); end
        end

        -- Per-bar fonts
        if M.hotbarNumberFonts[barIndex] then
            table.insert(all, M.hotbarNumberFonts[barIndex]);
        end
    end

    M.allFonts = all;
end

function M.SetAllFontsVisible(visible)
    if M.allFonts then
        SetFontsVisible(M.allFonts, visible);
    end
end

function M.SetBarFontsVisible(barIndex, visible)
    -- Hotbar number font
    if M.hotbarNumberFonts[barIndex] then
        M.hotbarNumberFonts[barIndex]:set_visible(visible);
    end

    -- Keybind fonts for this bar
    if M.keybindFonts[barIndex] then
        for _, font in pairs(M.keybindFonts[barIndex]) do
            if font then
                font:set_visible(visible);
            end
        end
    end

    -- Label fonts for this bar
    if M.labelFonts[barIndex] then
        for _, font in pairs(M.labelFonts[barIndex]) do
            if font then
                font:set_visible(visible);
            end
        end
    end

    -- Timer fonts for this bar
    if M.timerFonts[barIndex] then
        for _, font in pairs(M.timerFonts[barIndex]) do
            if font then
                font:set_visible(visible);
            end
        end
    end

    -- MP cost fonts for this bar
    if M.mpCostFonts[barIndex] then
        for _, font in pairs(M.mpCostFonts[barIndex]) do
            if font then
                font:set_visible(visible);
            end
        end
    end

    -- Item quantity fonts for this bar
    if M.quantityFonts[barIndex] then
        for _, font in pairs(M.quantityFonts[barIndex]) do
            if font then
                font:set_visible(visible);
            end
        end
    end

    -- Abbreviation fonts for this bar
    if M.abbreviationFonts[barIndex] then
        for _, font in pairs(M.abbreviationFonts[barIndex]) do
            if font then
                font:set_visible(visible);
            end
        end
    end
end

-- ============================================
-- Preview Mode (stub for compatibility)
-- ============================================

function M.SetPreview(enabled)
end

function M.ClearPreview()
end

function M.ClearError()
end

-- ============================================
-- Profile duplicate (no macro library): strip bar binds to palette macros
-- ============================================

-- Clears actionType == 'macro' slots in settings (in-memory copy) so a duplicated profile
-- that dropped the macro library does not show ghost bindings to missing macroRef rows.
function M.StripPaletteMacroBindsFromSettings(settings)
    if not settings or type(settings) ~= 'table' then
        return;
    end
    local function isPaletteMacro(slot)
        if not slot or type(slot) ~= 'table' or slot.cleared then
            return false;
        end
        if isDualMacroSlotTable(slot) then
            return slot.actionType == 'macro' or slot[K_BIND_P] ~= nil or slot[K_BIND_S] ~= nil;
        end
        return slot.actionType == 'macro';
    end
    for bar = 1, 6 do
        local configKey = 'hotbarBar' .. bar;
        local barSettings = settings[configKey];
        if barSettings and type(barSettings.slotActions) == 'table' then
            for _, jobSlotActions in pairs(barSettings.slotActions) do
                if type(jobSlotActions) == 'table' then
                    for si, slot in pairs(jobSlotActions) do
                        if isPaletteMacro(slot) then
                            jobSlotActions[si] = { cleared = true };
                        end
                    end
                end
            end
        end
    end
    if settings.hotbarCrossbar and type(settings.hotbarCrossbar.slotActions) == 'table' then
        for _, jobSlotActions in pairs(settings.hotbarCrossbar.slotActions) do
            if type(jobSlotActions) == 'table' then
                for _, comboSlots in pairs(jobSlotActions) do
                    if type(comboSlots) == 'table' then
                        for si, slot in pairs(comboSlots) do
                            if isPaletteMacro(slot) then
                                comboSlots[si] = nil;
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ============================================
-- Lifecycle
-- ============================================

-- Initialize (called from init.lua)
function M.Initialize()
    M.SetPlayerJob();
end

function M.SetPlayerJob()
    -- Gate on login state - memory only reliable when player entity is visible
    if not gameState.CheckLoggedIn() then
        return false;
    end

    local player = AshitaCore:GetMemoryManager():GetPlayer()
    local currentJobId = player:GetMainJob();
    if currentJobId == 0 then
        return false;
    end
    local currentSubjobId = player:GetSubJob();

    -- Invalidate caches if job changed
    if M.jobId ~= currentJobId or M.subjobId ~= currentSubjobId then
        M.InvalidateStorageKeyCache();
    end

    M.jobId = currentJobId;
    M.subjobId = currentSubjobId;
    return true;
end

-- Clear all state (call on zone change)
function M.Clear()
end

-- Cleanup (call on addon unload)
function M.Cleanup()
    M.Clear();
    M.bgHandles = {};
    M.slotPrims = {};
    M.iconPrims = {};
    M.cooldownPrims = {};
    M.framePrims = {};
    M.keybindFonts = {};
    M.labelFonts = {};
    M.timerFonts = {};
    M.mpCostFonts = {};
    M.quantityFonts = {};
    M.abbreviationFonts = {};
    M.hotbarNumberFonts = {};
    M.allFonts = nil;
end

return M;
