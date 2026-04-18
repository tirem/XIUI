--[[
* XIUI — JSON export/import for an entire profile: palettes (keyboard hotbar + crossbar) and macro library.
* Format: xiuiExportVersion 1, kind xiui_profile.
* One file = one profile snapshot. Import options let you apply palettes, macros, or both.
]]--

require('common');

local json = require('libs.json');
local jobs = require('libs.jobs');
local palette = require('modules.hotbar.palette');
local data = require('modules.hotbar.data');

local M = {};

local EXPORT_VERSION = 1;
M.KIND_PROFILE = 'xiui_profile';

local UNIVERSAL_CROSSBAR_PREFIX = 'global:palette:';
local PALETTE_KEY_PREFIX = 'palette:';

local function jobAbbr(jobId)
    if not jobId or jobId == 0 then return 'NONE'; end
    return jobs[jobId] or ('Job' .. tostring(jobId));
end

--- parseHotbarStorageKey("1:2:palette:Foo") -> 1, 2, "Foo"
local function parseHotbarStorageKey(sk)
    local j, s, name = sk:match('^(%d+):(%d+):' .. PALETTE_KEY_PREFIX .. '(.+)$');
    if j then
        return tonumber(j), tonumber(s), name;
    end
    return nil, nil, nil;
end

--- parseCrossbarStorageKey(sk) -> scope ("global"|"job"|"other"), jobId, subjobId, name
local function parseCrossbarStorageKey(sk)
    if sk:sub(1, #UNIVERSAL_CROSSBAR_PREFIX) == UNIVERSAL_CROSSBAR_PREFIX then
        return 'global', nil, nil, sk:sub(#UNIVERSAL_CROSSBAR_PREFIX + 1);
    end
    local j, s, name = parseHotbarStorageKey(sk);
    if j then
        return 'job', j, s, name;
    end
    return 'other', nil, nil, nil;
end

local function formatHotbarPaletteLabel(sk)
    local j, s, name = parseHotbarStorageKey(sk);
    if j then
        return string.format('Keyboard hotbar palette — %s/%s — "%s"',
            jobAbbr(j), jobAbbr(s), name);
    end
    return 'Keyboard hotbar palette — ' .. sk;
end

local function formatCrossbarPaletteLabel(sk)
    local scope, j, s, name = parseCrossbarStorageKey(sk);
    if scope == 'global' then
        return string.format('Crossbar palette — Global [G] — "%s"', name or sk);
    elseif scope == 'job' then
        return string.format('Crossbar palette — Job [J] — %s/%s — "%s"',
            jobAbbr(j), jobAbbr(s), name);
    end
    return 'Crossbar palette — ' .. sk;
end

local function formatMacroBucketLabel(ks)
    if ks == 'global' then
        return 'Global macros (all jobs)';
    end
    if ks == 'items' then
        return 'Macros — Items (gear / consumables, all jobs)';
    end
    local n = tonumber(ks);
    if n then
        return string.format('Macros — %s (job id %d)', jobAbbr(n), n);
    end
    local j, kind, id = ks:match('^(%d+):([^:]+):(.+)$');
    if j and kind then
        return string.format('Macros — %s %s overlay "%s"', jobAbbr(tonumber(j)), kind, id);
    end
    return 'Macros — ' .. ks;
end

M.EXPORT_PART_ALL = 'all';
M.EXPORT_PART_PALETTES_ONLY = 'palettes_only';
M.EXPORT_PART_MACROS_ONLY = 'macros_only';

--- Import behavior: merge appends macros and merges palette lists; replace clears matching data first so the profile matches the file.
M.IMPORT_MODE_MERGE = 'merge';
M.IMPORT_MODE_REPLACE = 'replace';

--- Match handlers/tbar_migration.StorageKeyToMacroPaletteKey (macroDB bucket key).
local function macroKeyFromStorageKey(storageKey)
    if storageKey == 'global' then
        return 'global';
    end
    local jobIdPalette, _paletteName = storageKey:match('^(%d+):palette:(.+)$');
    if jobIdPalette then
        return tonumber(jobIdPalette);
    end
    local jobIdPet, petType, petKey = storageKey:match('^(%d+):%d+:([^:]+):(.+)$');
    if jobIdPet and (petType == 'avatar' or petType == 'spirit') then
        return string.format('%s:%s:%s', jobIdPet, petType, petKey);
    end
    local baseJobId = storageKey:match('^(%d+)');
    if baseJobId then
        return tonumber(baseJobId);
    end
    return 'global';
end

local function macroKeyToString(k)
    if k == nil then
        return '';
    end
    return tostring(k);
end

local function macroKeyFromString(s)
    if s == nil or s == '' then
        return nil;
    end
    if s == 'global' then
        return 'global';
    end
    if s == 'items' then
        return 'items';
    end
    local n = tonumber(s);
    if n then
        return n;
    end
    return s;
end

local function deepCopy(v)
    if type(v) ~= 'table' then
        return v;
    end
    local t = {};
    for k, x in pairs(v) do
        t[k] = deepCopy(x);
    end
    return t;
end

--- rxi json requires non-sparse arrays / string object keys.
local function encodeSlotMap(slotMap)
    if type(slotMap) ~= 'table' then
        return {};
    end
    local out = {};
    for slotIdx, slot in pairs(slotMap) do
        if type(slot) == 'table' then
            out[tostring(slotIdx)] = deepCopy(slot);
        end
    end
    return out;
end

local function decodeSlotMap(slotMap)
    if type(slotMap) ~= 'table' then
        return {};
    end
    local out = {};
    for slotIdx, slot in pairs(slotMap) do
        local nk = tonumber(slotIdx) or slotIdx;
        out[nk] = slot;
    end
    return out;
end

-- =============================================================================
-- Export profile
-- =============================================================================

--- Encode every hotbar palette into { storageKey -> { _label, _jobId, _subjobId, _paletteName, bars = { "1".."6" } } }.
local function encodeAllHotbarPalettes()
    local palettes = {};
    if not gConfig then return palettes; end
    local keys = {};
    for bar = 1, 6 do
        local cfg = gConfig['hotbarBar' .. bar];
        if cfg and cfg.slotActions then
            for sk, _ in pairs(cfg.slotActions) do
                keys[sk] = true;
            end
        end
    end
    for sk, _ in pairs(keys) do
        local bars = {};
        for bar = 1, 6 do
            local cfg = gConfig['hotbarBar' .. bar];
            local smap = cfg and cfg.slotActions and cfg.slotActions[sk];
            -- Only emit bars that actually have bound slots; importer tolerates missing bar keys and this keeps the file readable.
            if type(smap) == 'table' and next(smap) ~= nil then
                bars[tostring(bar)] = encodeSlotMap(smap);
            end
        end
        local j, s, name = parseHotbarStorageKey(sk);
        palettes[sk] = {
            _label = formatHotbarPaletteLabel(sk),
            _jobId = j,
            _jobName = j and jobAbbr(j) or nil,
            _subjobId = s,
            _subjobName = s and jobAbbr(s) or nil,
            _paletteName = name,
            bars = bars,
        };
    end
    return palettes;
end

--- Encode every crossbar palette into { storageKey -> { _label, _scope, ..., slotActions = { comboMode -> slotMap } } }.
local function encodeAllCrossbarPalettes()
    local palettes = {};
    local hc = gConfig and gConfig.hotbarCrossbar;
    if not hc or not hc.slotActions then
        return palettes;
    end
    for sk, root in pairs(hc.slotActions) do
        if type(root) == 'table' then
            local encodedRoot = {};
            for comboMode, modeData in pairs(root) do
                if type(modeData) == 'table' then
                    encodedRoot[comboMode] = encodeSlotMap(modeData);
                end
            end
            local scope, j, s, name = parseCrossbarStorageKey(sk);
            palettes[sk] = {
                _label = formatCrossbarPaletteLabel(sk),
                _scope = scope,
                _jobId = j,
                _jobName = j and jobAbbr(j) or nil,
                _subjobId = s,
                _subjobName = s and jobAbbr(s) or nil,
                _paletteName = name,
                slotActions = encodedRoot,
            };
        end
    end
    return palettes;
end

local function encodeAllMacros()
    local out = {};
    local labels = {};
    if not gConfig or not gConfig.macroDB then
        return out;
    end
    for mk, bucket in pairs(gConfig.macroDB) do
        if type(bucket) == 'table' then
            local ks = macroKeyToString(mk);
            if ks ~= '' then
                local list = {};
                for _, m in ipairs(bucket) do
                    if type(m) == 'table' then
                        table.insert(list, deepCopy(m));
                    end
                end
                out[ks] = list;
                labels[ks] = formatMacroBucketLabel(ks);
            end
        end
    end
    if next(labels) ~= nil then
        out._labels = labels;
        out._readme = 'Bucket keys: "global" = shared across jobs; "items" = item/gear macros (all jobs); a plain number = that job id (1=WAR, 2=MNK, ...); "<jobId>:avatar:<id>" or "<jobId>:spirit:<id>" = pet-specific overlays. See _labels for human-readable names. To remove a macro bucket from this import, delete its key (and the matching _labels entry).';
    end
    return out;
end

local function encodeHotbarPaletteOrder()
    local order = gConfig and gConfig.hotbar and gConfig.hotbar.paletteOrder;
    if type(order) ~= 'table' then return {}; end
    local out = {};
    for k, list in pairs(order) do
        if type(list) == 'table' then
            out[tostring(k)] = deepCopy(list);
        end
    end
    return out;
end

local function encodeCrossbarPaletteOrders()
    local hc = gConfig and gConfig.hotbarCrossbar;
    local jobOrder = {};
    if hc and type(hc.crossbarPaletteOrder) == 'table' then
        for k, list in pairs(hc.crossbarPaletteOrder) do
            if type(list) == 'table' then
                jobOrder[tostring(k)] = deepCopy(list);
            end
        end
    end
    local univ = {};
    if hc and type(hc.universalCrossbarPaletteOrder) == 'table' then
        for _, n in ipairs(hc.universalCrossbarPaletteOrder) do
            table.insert(univ, n);
        end
    end
    return jobOrder, univ;
end

-- =============================================================================
-- Pretty encoder
-- Emits human-readable, stable-ordered JSON so users can manually edit the file
-- (delete specific palette entries they do not want to import, etc.). Keys beginning
-- with "_" are annotations and come first inside every object; they are ignored by
-- ImportProfile. Numeric-looking keys sort numerically so slot indices line up.
-- =============================================================================

local function prettyEncode(v)
    local function recur(val, depth)
        local pad = string.rep('  ', depth);
        local padIn = string.rep('  ', depth + 1);
        if type(val) ~= 'table' then
            return json.encode(val);
        end
        if next(val) == nil then
            return '[]';
        end
        local isArr = rawget(val, 1) ~= nil;
        if isArr then
            local n = 0;
            for k in pairs(val) do
                if type(k) ~= 'number' then isArr = false; break; end
                n = n + 1;
            end
            if isArr and n ~= #val then isArr = false; end
        end
        if isArr then
            local parts = {};
            for _, x in ipairs(val) do
                table.insert(parts, padIn .. recur(x, depth + 1));
            end
            return '[\n' .. table.concat(parts, ',\n') .. '\n' .. pad .. ']';
        end
        local keys = {};
        for k in pairs(val) do table.insert(keys, k); end
        table.sort(keys, function(a, b)
            local sa, sb = tostring(a), tostring(b);
            local ua = sa:sub(1, 1) == '_';
            local ub = sb:sub(1, 1) == '_';
            if ua ~= ub then return ua; end
            local na, nb = tonumber(sa), tonumber(sb);
            if na and nb then return na < nb; end
            return sa < sb;
        end);
        local parts = {};
        for _, k in ipairs(keys) do
            local kk = json.encode(tostring(k));
            table.insert(parts, padIn .. kk .. ': ' .. recur(val[k], depth + 1));
        end
        return '{\n' .. table.concat(parts, ',\n') .. '\n' .. pad .. '}';
    end
    return recur(v, 0);
end

local function currentTimestamp()
    if os and os.date then
        return os.date('%Y-%m-%d %H:%M:%S');
    end
    return '';
end

local function partHuman(part)
    if part == M.EXPORT_PART_PALETTES_ONLY then
        return 'all palettes only';
    elseif part == M.EXPORT_PART_MACROS_ONLY then
        return 'all macros only';
    end
    return 'all palettes + macros';
end

--- Export the whole profile. exportPart:
---   EXPORT_PART_ALL           -> palettes + macros
---   EXPORT_PART_PALETTES_ONLY -> palettes (hotbar + crossbar) only
---   EXPORT_PART_MACROS_ONLY   -> macros only
---
--- Output is pretty-printed JSON with _label/_readme annotations so users can
--- manually edit the file (e.g. delete palettes or macro buckets they do not
--- want to import into a new character). Keys starting with "_" are ignored on
--- import; delete them or leave them alone either way.
function M.ExportProfile(exportPart)
    if not gConfig then
        return nil, 'No config';
    end
    exportPart = exportPart or M.EXPORT_PART_ALL;

    local profileName;
    if GetCurrentProfileName then
        local okN, n = pcall(GetCurrentProfileName);
        if okN and type(n) == 'string' then profileName = n; end
    end

    local payload = {
        _readme = 'XIUI profile export. You can edit this file before importing: delete entries from "hotbarPalettes.bars", "crossbarPalettes.slotActions", or "macros" to leave them out, then import as usual. Every "_" key (including _label, _readme, _exportedAt, _jobId, _jobName, etc.) is purely for humans and is ignored by the importer. Keep the canonical fields (xiuiExportVersion, kind, exportPart, bars, slotActions, macros).',
        _exportedAt = currentTimestamp(),
        _exportPart = partHuman(exportPart),
        _profileName = profileName,
        xiuiExportVersion = EXPORT_VERSION,
        kind = M.KIND_PROFILE,
        exportPart = exportPart,
    };

    if exportPart ~= M.EXPORT_PART_MACROS_ONLY then
        local hotbarPalettes = encodeAllHotbarPalettes();
        local crossbarPalettes = encodeAllCrossbarPalettes();
        local hbOrder = encodeHotbarPaletteOrder();
        local xbJobOrder, xbUnivOrder = encodeCrossbarPaletteOrders();
        payload.hotbarPalettes = {
            _label = 'Keyboard hotbar palettes (six bars per palette; keys look like "<jobId>:<subjobId>:palette:<name>"). Delete a key under "bars" to skip that palette on import.',
            paletteOrder = hbOrder,
            bars = hotbarPalettes,
        };
        payload.crossbarPalettes = {
            _label = 'Controller crossbar palettes (L2/R2 combo grids). Keys are "global:palette:<name>" for Global [G] palettes shared across jobs, or "<jobId>:<subjobId>:palette:<name>" for Job [J] palettes. Delete a key under "slotActions" to skip that palette on import.',
            crossbarPaletteOrder = xbJobOrder,
            universalCrossbarPaletteOrder = xbUnivOrder,
            slotActions = crossbarPalettes,
        };
    end

    if exportPart ~= M.EXPORT_PART_PALETTES_ONLY then
        payload.macros = encodeAllMacros();
    end

    local ok, result = pcall(prettyEncode, payload);
    if not ok then
        return nil, tostring(result);
    end
    return result;
end

-- =============================================================================
-- Import profile
-- =============================================================================

--- Annotation keys (leading underscore) are written by ExportProfile so humans can
--- read / edit the file. They must never affect import.
local function isAnnotationKey(k)
    return type(k) == 'string' and k:sub(1, 1) == '_';
end

local function nextMacroIdInBucket(bucket)
    local maxId = 0;
    if type(bucket) == 'table' then
        for _, m in ipairs(bucket) do
            if m and m.id and m.id > maxId then
                maxId = m.id;
            end
        end
    end
    return maxId;
end

--- Append imported macro rows into destination buckets with fresh IDs.
--- Returns idMaps: idMaps[srcBucketKeyStr][oldId] = newId.
local function importMacrosAppend(macrosObj)
    if not gConfig then
        return nil, 'No config';
    end
    if not gConfig.macroDB then
        gConfig.macroDB = {};
    end
    local idMaps = {};
    for srcKs, list in pairs(macrosObj or {}) do
        if not isAnnotationKey(srcKs) and type(list) == 'table' then
            local destKey = macroKeyFromString(srcKs);
            if destKey ~= nil then
                local destBucket = gConfig.macroDB[destKey];
                if not destBucket then
                    gConfig.macroDB[destKey] = {};
                    destBucket = gConfig.macroDB[destKey];
                end
                local maxId = nextMacroIdInBucket(destBucket);
                idMaps[srcKs] = idMaps[srcKs] or {};
                for _, m in ipairs(list) do
                    if type(m) == 'table' and m.id then
                        maxId = maxId + 1;
                        local copy = deepCopy(m);
                        local oldId = copy.id;
                        copy.id = maxId;
                        table.insert(destBucket, copy);
                        idMaps[srcKs][oldId] = maxId;
                    end
                end
            end
        end
    end
    return idMaps;
end

--- Load macros from JSON into an empty macroDB, preserving macro ids from the file (no remapping).
--- Caller must clear gConfig.macroDB before calling when doing a full replace.
local function importMacrosReplace(macrosObj)
    if not gConfig then
        return;
    end
    if not gConfig.macroDB then
        gConfig.macroDB = {};
    end
    for srcKs, list in pairs(macrosObj or {}) do
        if not isAnnotationKey(srcKs) and type(list) == 'table' then
            local destKey = macroKeyFromString(srcKs);
            if destKey ~= nil then
                gConfig.macroDB[destKey] = {};
                local destBucket = gConfig.macroDB[destKey];
                for _, m in ipairs(list) do
                    if type(m) == 'table' then
                        table.insert(destBucket, deepCopy(m));
                    end
                end
            end
        end
    end
end

local function clearHotbarSlotLayoutsOnly()
    if not gConfig then return; end
    for bar = 1, 6 do
        local cfg = gConfig['hotbarBar' .. bar];
        if cfg then
            cfg.slotActions = {};
        end
    end
end

local function clearCrossbarSlotLayoutsOnly()
    if gConfig and gConfig.hotbarCrossbar then
        gConfig.hotbarCrossbar.slotActions = {};
    end
end

local function macroExistsInBucket(bucketKey, macroId)
    if not gConfig or not gConfig.macroDB or not macroId then
        return false;
    end
    local db = gConfig.macroDB[bucketKey];
    if type(db) ~= 'table' then return false; end
    for _, m in ipairs(db) do
        if m and m.id == macroId then return true; end
    end
    return false;
end

--- Validate that every macroRef in the imported palettes already resolves in the destination's macroDB.
--- Used when palette import is requested without macro import.
local function validatePaletteMacroRefs(hotbarPalettesTbl, crossbarPalettesTbl)
    local function check(slot, defMk, where)
        if type(slot) ~= 'table' or not slot.macroRef then return nil; end
        local mpk = slot.macroPaletteKey or defMk;
        if not macroExistsInBucket(mpk, slot.macroRef) then
            return string.format(
                'Destination is missing macro id %s (bucket %s) referenced by %s. Import macros too, or choose a full export.',
                tostring(slot.macroRef), macroKeyToString(mpk), where);
        end
        return nil;
    end

    if type(hotbarPalettesTbl) == 'table' then
        for sk, entry in pairs(hotbarPalettesTbl) do
            if not isAnnotationKey(sk) then
                local defMk = macroKeyFromStorageKey(sk);
                local bars = entry and entry.bars;
                if type(bars) == 'table' then
                    for barIdx = 1, 6 do
                        local smap = decodeSlotMap(bars[tostring(barIdx)] or {});
                        for _, slot in pairs(smap) do
                            local err = check(slot, defMk, string.format('hotbar bar %d of "%s"', barIdx, sk));
                            if err then return false, err; end
                        end
                    end
                end
            end
        end
    end

    if type(crossbarPalettesTbl) == 'table' then
        for sk, entry in pairs(crossbarPalettesTbl) do
            if not isAnnotationKey(sk) then
                local defMk = macroKeyFromStorageKey(sk);
                local root = entry and entry.slotActions;
                if type(root) == 'table' then
                    for comboMode, modeData in pairs(root) do
                        if not isAnnotationKey(comboMode) and type(modeData) == 'table' then
                            for _, slot in pairs(modeData) do
                                if type(slot) == 'table' then
                                    local err = check(slot, defMk, string.format('crossbar "%s"', sk));
                                    if err then return false, err; end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return true;
end

local function remapSlotMacroRefs(slot, defMk, idMaps)
    if type(slot) ~= 'table' or not slot.macroRef then return; end
    local srcKs = macroKeyToString(slot.macroPaletteKey);
    if srcKs == '' then
        srcKs = macroKeyToString(defMk);
    end
    local map = idMaps and idMaps[srcKs];
    if map and map[slot.macroRef] then
        slot.macroRef = map[slot.macroRef];
        slot.macroPaletteKey = defMk;
    end
end

--- Write imported hotbar palettes into gConfig.hotbarBar1..6.slotActions by storage key.
--- idMaps may be nil (no macro import).
local function applyHotbarPalettes(hotbarPalettesTbl, idMaps)
    if type(hotbarPalettesTbl) ~= 'table' then return; end
    for sk, entry in pairs(hotbarPalettesTbl) do
        if not isAnnotationKey(sk) then
            local defMk = macroKeyFromStorageKey(sk);
            local bars = entry and entry.bars;
            if type(bars) == 'table' then
                for barIdx = 1, 6 do
                    local cfgKey = 'hotbarBar' .. barIdx;
                    local cfg = gConfig[cfgKey];
                    if not cfg then
                        gConfig[cfgKey] = {};
                        cfg = gConfig[cfgKey];
                    end
                    if not cfg.slotActions then
                        cfg.slotActions = {};
                    end
                    local slotMap = decodeSlotMap(bars[tostring(barIdx)] or {});
                    if idMaps then
                        for _, slot in pairs(slotMap) do
                            remapSlotMacroRefs(slot, defMk, idMaps);
                        end
                    end
                    cfg.slotActions[sk] = slotMap;
                end
            end
        end
    end
end

--- Write imported crossbar palettes into gConfig.hotbarCrossbar.slotActions by storage key.
local function applyCrossbarPalettes(crossbarPalettesTbl, idMaps)
    if type(crossbarPalettesTbl) ~= 'table' then return; end
    local hc = gConfig.hotbarCrossbar;
    if not hc then
        gConfig.hotbarCrossbar = {};
        hc = gConfig.hotbarCrossbar;
    end
    if not hc.slotActions then
        hc.slotActions = {};
    end
    for sk, entry in pairs(crossbarPalettesTbl) do
        if not isAnnotationKey(sk) then
            local defMk = macroKeyFromStorageKey(sk);
            local root = entry and entry.slotActions;
            local newRoot = {};
            if type(root) == 'table' then
                for comboMode, modeData in pairs(root) do
                    if not isAnnotationKey(comboMode) and type(modeData) == 'table' then
                        local slotMap = decodeSlotMap(modeData);
                        if idMaps then
                            for _, slot in pairs(slotMap) do
                                remapSlotMacroRefs(slot, defMk, idMaps);
                            end
                        end
                        newRoot[comboMode] = slotMap;
                    end
                end
            end
            hc.slotActions[sk] = newRoot;
        end
    end
end

--- Merge a list of names into an existing order list, preserving existing entries first.
local function mergeOrderList(existing, incoming)
    existing = existing or {};
    local seen = {};
    for _, n in ipairs(existing) do seen[n] = true; end
    for _, n in ipairs(incoming or {}) do
        if not seen[n] then
            table.insert(existing, n);
            seen[n] = true;
        end
    end
    return existing;
end

--- Apply hotbar paletteOrder. replace=true overwrites the destination dict entirely; replace=false merges per key.
local function applyHotbarPaletteOrder(orderTbl, replace)
    if type(orderTbl) ~= 'table' then return; end
    if not gConfig.hotbar then gConfig.hotbar = {}; end
    if replace then
        local newOrder = {};
        for k, list in pairs(orderTbl) do
            if not isAnnotationKey(k) and type(list) == 'table' then
                newOrder[k] = deepCopy(list);
            end
        end
        gConfig.hotbar.paletteOrder = newOrder;
        return;
    end
    if not gConfig.hotbar.paletteOrder then gConfig.hotbar.paletteOrder = {}; end
    for k, list in pairs(orderTbl) do
        if not isAnnotationKey(k) and type(list) == 'table' then
            gConfig.hotbar.paletteOrder[k] = mergeOrderList(gConfig.hotbar.paletteOrder[k], list);
        end
    end
end

--- Apply crossbar palette order dicts. replace=true overwrites destination lists; replace=false merges.
local function applyCrossbarPaletteOrders(jobOrder, univOrder, replace)
    local hc = gConfig.hotbarCrossbar;
    if not hc then
        gConfig.hotbarCrossbar = {};
        hc = gConfig.hotbarCrossbar;
    end
    if type(jobOrder) == 'table' then
        if replace then
            local newJob = {};
            for k, list in pairs(jobOrder) do
                if not isAnnotationKey(k) and type(list) == 'table' then
                    newJob[k] = deepCopy(list);
                end
            end
            hc.crossbarPaletteOrder = newJob;
        else
            if not hc.crossbarPaletteOrder then hc.crossbarPaletteOrder = {}; end
            for k, list in pairs(jobOrder) do
                if not isAnnotationKey(k) and type(list) == 'table' then
                    hc.crossbarPaletteOrder[k] = mergeOrderList(hc.crossbarPaletteOrder[k], list);
                end
            end
        end
    end
    if type(univOrder) == 'table' then
        if replace then
            hc.universalCrossbarPaletteOrder = deepCopy(univOrder);
        else
            hc.universalCrossbarPaletteOrder = mergeOrderList(hc.universalCrossbarPaletteOrder, univOrder);
        end
    end
end

--- Return true if any non-annotation key is present in the table.
local function hasRealKey(tbl)
    if type(tbl) ~= 'table' then return false; end
    for k, _ in pairs(tbl) do
        if not isAnnotationKey(k) then return true; end
    end
    return false;
end

local function hasHotbarPalettes(decoded)
    local hp = decoded.hotbarPalettes;
    return hp and hasRealKey(hp.bars);
end

local function hasCrossbarPalettes(decoded)
    local cp = decoded.crossbarPalettes;
    return cp and hasRealKey(cp.slotActions);
end

local function hasMacroPayload(decoded)
    return hasRealKey(decoded.macros);
end

--- Import a whole-profile JSON.
--- opts.importPalettes (default true)
--- opts.importMacros   (default true)
--- opts.importMode     (default IMPORT_MODE_MERGE):
---   MERGE: append macros with new ids (remap palette refs); merge palette name lists; overlay slot data per key.
---   REPLACE: clear imported sides first — macros become exactly the file’s buckets (ids preserved); hotbar/crossbar
---            slot layouts for sides present in the file are cleared then filled; palette order lists for those
---            sides are replaced from the file (not merged).
--- When importing palettes without macros (merge or replace), the destination must already have every referenced macro id.
function M.ImportProfile(jsonStr, opts)
    opts = opts or {};
    local importPalettes = opts.importPalettes ~= false;
    local importMacros = opts.importMacros ~= false;
    local importMode = opts.importMode or M.IMPORT_MODE_MERGE;
    local replace = (importMode == M.IMPORT_MODE_REPLACE);
    if not importPalettes and not importMacros then
        return false, 'Select at least one: palettes or macros.';
    end
    if not gConfig then
        return false, 'No config';
    end

    local ok, res = pcall(json.decode, jsonStr);
    if not ok then
        return false, 'Invalid JSON: ' .. tostring(res);
    end
    local decoded = res;
    if decoded.xiuiExportVersion ~= EXPORT_VERSION or decoded.kind ~= M.KIND_PROFILE then
        return false,
            'Not an XIUI profile export (wrong version or kind). Re-export from a recent version.';
    end

    local hasHotbar = hasHotbarPalettes(decoded);
    local hasCrossbar = hasCrossbarPalettes(decoded);
    local hasPalettesAny = hasHotbar or hasCrossbar;
    local hasMacros = hasMacroPayload(decoded);

    if not hasPalettesAny and not hasMacros then
        return false, 'JSON has no palettes and no macros.';
    end
    -- If the user asked for both but the file only has one side, quietly drop the missing side instead of erroring.
    if importPalettes and not hasPalettesAny then
        if not importMacros then
            return false, 'JSON has no palettes. Choose a file that includes palettes, or check Import macros.';
        end
        importPalettes = false;
    end
    if importMacros and not hasMacros then
        if not importPalettes then
            return false, 'JSON has no macros. Choose a file that includes macros, or check Import palettes.';
        end
        importMacros = false;
    end

    local hotbarPalettesTbl = hasHotbar and decoded.hotbarPalettes.bars or nil;
    local crossbarPalettesTbl = hasCrossbar and decoded.crossbarPalettes.slotActions or nil;

    local idMaps;
    if importMacros then
        if replace then
            gConfig.macroDB = {};
            importMacrosReplace(decoded.macros or {});
        else
            local maps, ierr = importMacrosAppend(decoded.macros or {});
            if not maps then
                return false, ierr or 'Macro import failed';
            end
            idMaps = maps;
        end
    end

    if importPalettes then
        if replace then
            if hasHotbar then
                clearHotbarSlotLayoutsOnly();
            end
            if hasCrossbar then
                clearCrossbarSlotLayoutsOnly();
            end
        end
        if not importMacros then
            local okV, errV = validatePaletteMacroRefs(hotbarPalettesTbl, crossbarPalettesTbl);
            if not okV then
                return false, errV;
            end
        end
        applyHotbarPalettes(hotbarPalettesTbl, idMaps);
        applyCrossbarPalettes(crossbarPalettesTbl, idMaps);
        if hasHotbar then
            applyHotbarPaletteOrder(decoded.hotbarPalettes.paletteOrder, replace);
        end
        if hasCrossbar then
            applyCrossbarPaletteOrders(
                decoded.crossbarPalettes.crossbarPaletteOrder,
                decoded.crossbarPalettes.universalCrossbarPaletteOrder,
                replace
            );
        end
    end

    data.MarkMacroLookupDirty();
    palette.InvalidateCachesAfterExternalSlotMutation();
    if SaveSettingsToDisk then
        SaveSettingsToDisk();
    end
    return true;
end

-- =============================================================================
-- Disk helpers
-- =============================================================================

--- Absolute path of the exports directory (creates it on first access).
function M.GetExportsDir()
    local dir = AshitaCore:GetInstallPath() .. 'config\\addons\\xiui\\exports\\';
    if ashita.fs and not ashita.fs.exists(dir) then
        ashita.fs.create_directory(dir);
    end
    return dir;
end

--- Open the exports folder in Windows Explorer. Returns true on success.
function M.OpenExportsDir()
    local dir = M.GetExportsDir();
    os.execute('explorer "' .. dir .. '"');
    return true, dir;
end

--- Return a sorted list of *.json filenames in the exports folder.
--- Ashita filters use regex (see profile_manager / config.hotbar), not Lua patterns:
--- use '.*\\.json$' (literal dot before json), not '.*%.json$'.
function M.ListExportFiles()
    local dir = M.GetExportsDir();
    local files = {};
    local jsonPattern = '.*\\.json$';
    if ashita.fs then
        local found;
        -- Prefer get_directory — same API as SyncProfilesWithDisk / frame PNG scan.
        if ashita.fs.get_directory then
            found = ashita.fs.get_directory(dir, jsonPattern);
        end
        if found == nil and ashita.fs.get_dir then
            found = ashita.fs.get_dir(dir, jsonPattern, true);
        end
        if type(found) == 'table' then
            for _, name in ipairs(found) do
                table.insert(files, name);
            end
        end
    end
    table.sort(files);
    return files, dir;
end

--- Read the full contents of an export file (filename relative to the exports dir).
function M.ReadExportFile(filename)
    if not filename or filename == '' then
        return nil, 'No file';
    end
    local path = M.GetExportsDir() .. filename;
    local f = io.open(path, 'r');
    if not f then
        return nil, 'Could not open ' .. path;
    end
    local text = f:read('*a');
    f:close();
    return text, path;
end

--- Write UTF-8 text under Ashita config/addons/xiui/exports/ (creates folder).
function M.SaveTextFile(baseName, text)
    local dir = M.GetExportsDir();
    local safe = (baseName or 'xiui'):gsub('[^%w%-%_]', '_');
    local path = dir .. safe .. '_' .. os.time() .. '.json';
    local f = io.open(path, 'w');
    if not f then
        return false, path;
    end
    f:write(text or '');
    f:close();
    return true, path;
end

return M;
