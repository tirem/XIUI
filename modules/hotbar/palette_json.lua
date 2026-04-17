--[[
* XIUI — JSON export/import for hotbar and crossbar palettes (macro buckets included).
* Format: xiuiExportVersion 1, kind xiui_crossbar_palette | xiui_hotbar_palette.
]]--

require('common');

local json = require('libs.json');
local palette = require('modules.hotbar.palette');
local data = require('modules.hotbar.data');

local M = {};

local EXPORT_VERSION = 1;
M.KIND_CROSSBAR = 'xiui_crossbar_palette';
M.KIND_HOTBAR = 'xiui_hotbar_palette';

--- What to include in JSON (see export functions).
M.EXPORT_PART_FULL = 'full';
M.EXPORT_PART_SLOTS_ONLY = 'slots_only';
M.EXPORT_PART_MACROS_ONLY = 'macros_only';

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
    if type(k) == 'number' then
        return tostring(k);
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

--- Encode slot index keys as JSON strings (rxi json requires non-sparse arrays / string object keys).
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

local function walkCrossbarComboSlots(slotRoot, fn)
    if type(slotRoot) ~= 'table' then
        return;
    end
    for comboMode, modeData in pairs(slotRoot) do
        if type(modeData) == 'table' then
            for slotIdx, slot in pairs(modeData) do
                if type(slot) == 'table' then
                    fn(comboMode, slotIdx, slot);
                end
            end
        end
    end
end

--- Count slots (all bars + crossbar) referencing this macro id in this macroDB bucket.
local function globalMacroRefCount(macroPaletteKey, macroId)
    if not gConfig or not macroId then
        return 0;
    end
    local target = macroKeyToString(macroPaletteKey);
    if target == '' then
        return 0;
    end
    local n = 0;
    for bar = 1, 6 do
        local cfg = gConfig['hotbarBar' .. bar];
        if cfg and cfg.slotActions then
            for sk, smap in pairs(cfg.slotActions) do
                local defMk = macroKeyFromStorageKey(sk);
                for _, slot in pairs(smap or {}) do
                    if type(slot) == 'table' and slot.macroRef == macroId then
                        local pk = slot.macroPaletteKey or defMk;
                        if macroKeyToString(pk) == target then
                            n = n + 1;
                        end
                    end
                end
            end
        end
    end
    local hc = gConfig.hotbarCrossbar;
    if hc and hc.slotActions then
        for sk, root in pairs(hc.slotActions) do
            local defMk = macroKeyFromStorageKey(sk);
            walkCrossbarComboSlots(root, function(_, _, slot)
                if type(slot) == 'table' and slot.macroRef == macroId then
                    local pk = slot.macroPaletteKey or defMk;
                    if macroKeyToString(pk) == target then
                        n = n + 1;
                    end
                end
            end);
        end
    end
    return n;
end

--- Count references only under this palette storage key (crossbar tree or all six hotbar bars).
local function macroRefsFromStorageKeyForPair(storageKey, kind, macroPaletteKey, macroId)
    if not gConfig or not macroId then
        return 0;
    end
    local target = macroKeyToString(macroPaletteKey);
    if target == '' then
        return 0;
    end
    local n = 0;
    local defMk = macroKeyFromStorageKey(storageKey);
    if kind == 'crossbar' then
        local hc = gConfig.hotbarCrossbar;
        local root = hc and hc.slotActions and hc.slotActions[storageKey];
        walkCrossbarComboSlots(root, function(_, _, slot)
            if type(slot) == 'table' and slot.macroRef == macroId then
                local pk = slot.macroPaletteKey or defMk;
                if macroKeyToString(pk) == target then
                    n = n + 1;
                end
            end
        end);
    else
        for bar = 1, 6 do
            local cfg = gConfig['hotbarBar' .. bar];
            local smap = cfg and cfg.slotActions and cfg.slotActions[storageKey];
            for _, slot in pairs(smap or {}) do
                if type(slot) == 'table' and slot.macroRef == macroId then
                    local pk = slot.macroPaletteKey or defMk;
                    if macroKeyToString(pk) == target then
                        n = n + 1;
                    end
                end
            end
        end
    end
    return n;
end

local function collectUniqueMacroPairsForStorage(storageKey, kind)
    local out = {};
    local seen = {};
    local function add(mpk, id)
        if not id then
            return;
        end
        local k = macroKeyToString(mpk) .. '\0' .. tostring(id);
        if not seen[k] then
            seen[k] = true;
            table.insert(out, { mpk = mpk, id = id });
        end
    end
    local defMk = macroKeyFromStorageKey(storageKey);
    if kind == 'crossbar' then
        local root = gConfig.hotbarCrossbar and gConfig.hotbarCrossbar.slotActions and gConfig.hotbarCrossbar.slotActions[storageKey];
        walkCrossbarComboSlots(root, function(_, _, slot)
            if type(slot) == 'table' and slot.macroRef then
                add(slot.macroPaletteKey or defMk, slot.macroRef);
            end
        end);
    else
        for bar = 1, 6 do
            local cfg = gConfig['hotbarBar' .. bar];
            local smap = cfg and cfg.slotActions and cfg.slotActions[storageKey];
            for _, slot in pairs(smap or {}) do
                if type(slot) == 'table' and slot.macroRef then
                    add(slot.macroPaletteKey or defMk, slot.macroRef);
                end
            end
        end
    end
    return out;
end

local function macroExistsInBucket(macroPaletteKey, macroId)
    if not gConfig or not gConfig.macroDB or not macroId then
        return false;
    end
    local db = gConfig.macroDB[macroPaletteKey];
    if type(db) ~= 'table' then
        return false;
    end
    for _, m in ipairs(db) do
        if m and m.id == macroId then
            return true;
        end
    end
    return false;
end

--- Slots-only import: every macroRef must already exist in the destination profile.
local function validateSlotMacroRefsCrossbar(slotRoot, destStorageKey)
    local defMk = macroKeyFromStorageKey(destStorageKey);
    local ok, errMsg = true, nil;
    walkCrossbarComboSlots(slotRoot, function(_, _, slot)
        if ok and type(slot) == 'table' and slot.macroRef then
            local mpk = slot.macroPaletteKey or defMk;
            if not macroExistsInBucket(mpk, slot.macroRef) then
                ok = false;
                errMsg = string.format(
                    'Destination is missing macro id %s (bucket %s). Import macros first or use a full export.',
                    tostring(slot.macroRef),
                    macroKeyToString(mpk)
                );
            end
        end
    end);
    return ok, errMsg;
end

local function validateSlotMacroRefsHotbar(decodedHotbarBars, destStorageKey)
    local defMk = macroKeyFromStorageKey(destStorageKey);
    local ok, errMsg = true, nil;
    if type(decodedHotbarBars) ~= 'table' then
        return true;
    end
    for barIdx = 1, 6 do
        local enc = decodedHotbarBars[tostring(barIdx)];
        local slotMap = decodeSlotMap(enc or {});
        for _, slot in pairs(slotMap) do
            if ok and type(slot) == 'table' and slot.macroRef then
                local mpk = slot.macroPaletteKey or defMk;
                if not macroExistsInBucket(mpk, slot.macroRef) then
                    ok = false;
                    errMsg = string.format(
                        'Destination is missing macro id %s (bucket %s). Import macros first or use a full export.',
                        tostring(slot.macroRef),
                        macroKeyToString(mpk)
                    );
                end
            end
        end
    end
    return ok, errMsg;
end

local function removeMacroRowFromBucket(macroPaletteKey, macroId)
    if not gConfig or not gConfig.macroDB then
        return false;
    end
    local db = gConfig.macroDB[macroPaletteKey];
    if type(db) ~= 'table' then
        return false;
    end
    for i = #db, 1, -1 do
        local m = db[i];
        if m and m.id == macroId then
            table.remove(db, i);
            return true;
        end
    end
    return false;
end

--- Delete macro rows referenced only by this palette (no other hotbar/crossbar slot uses them).
local function purgeExclusiveMacrosForStorageKey(storageKey, kind)
    local pairsList = collectUniqueMacroPairsForStorage(storageKey, kind);
    for _, p in ipairs(pairsList) do
        local g = globalMacroRefCount(p.mpk, p.id);
        local s = macroRefsFromStorageKeyForPair(storageKey, kind, p.mpk, p.id);
        if g == s and s > 0 then
            removeMacroRowFromBucket(p.mpk, p.id);
        end
    end
end

local function collectMacroRefsFromCrossbar(slotRoot, defaultMacroKey)
    local want = {}; -- [keyStr][id] = true
    walkCrossbarComboSlots(slotRoot, function(_, _, slot)
        if slot.macroRef then
            local mk = slot.macroPaletteKey or defaultMacroKey;
            local ks = macroKeyToString(mk);
            if ks ~= '' then
                want[ks] = want[ks] or {};
                want[ks][slot.macroRef] = true;
            end
        end
    end);
    return want;
end

local function buildMacroExportBuckets(want)
    local macros = {};
    if not gConfig or not gConfig.macroDB then
        return macros;
    end
    for ks, ids in pairs(want) do
        local mk = macroKeyFromString(ks);
        local db = gConfig.macroDB[mk];
        if type(db) == 'table' then
            local list = {};
            for _, m in ipairs(db) do
                if m and m.id and ids[m.id] then
                    table.insert(list, deepCopy(m));
                end
            end
            if #list > 0 then
                macros[ks] = list;
            end
        end
    end
    return macros;
end

local function resolveCrossbarJobStorageKey(jobId, subjobTier, paletteName)
    local j = jobId or 1;
    local st = subjobTier or 0;
    local pk = palette.BuildPaletteStorageKey(j, st, paletteName);
    local hc = gConfig and gConfig.hotbarCrossbar;
    if hc and hc.slotActions and hc.slotActions[pk] then
        return pk;
    end
    if st ~= 0 then
        local p0 = palette.BuildPaletteStorageKey(j, 0, paletteName);
        if hc and hc.slotActions and hc.slotActions[p0] then
            return p0;
        end
    end
    return nil;
end

--- Which crossbar storage key exists for a Manage-Palettes row (subjob tier or shared fallback).
M.ResolveCrossbarJobStorageKey = resolveCrossbarJobStorageKey;

--- Export Job [J] / Subjob-tier crossbar palette (selected Manage Palettes row).
--- exportPart: M.EXPORT_PART_FULL | SLOTS_ONLY | MACROS_ONLY
function M.ExportCrossbarJobPalette(jobId, subjobTier, paletteName, exportPart)
    if not gConfig then
        return nil, 'No config';
    end
    exportPart = exportPart or M.EXPORT_PART_FULL;
    if not paletteName or paletteName == '' then
        return nil, 'No palette name';
    end
    local storageKey = resolveCrossbarJobStorageKey(jobId, subjobTier, paletteName);
    if not storageKey then
        return nil, 'Crossbar palette not found';
    end
    local hc = gConfig and gConfig.hotbarCrossbar;
    if not hc or not hc.slotActions then
        return nil, 'Crossbar settings not found';
    end
    local slotRoot = hc.slotActions[storageKey];
    if not slotRoot then
        return nil, 'No slot data';
    end
    local defaultMacroKey = macroKeyFromStorageKey(storageKey);
    local want = collectMacroRefsFromCrossbar(slotRoot, defaultMacroKey);
    local macros = buildMacroExportBuckets(want);

    local encoded = {};
    for comboMode, modeData in pairs(slotRoot) do
        if type(modeData) == 'table' then
            encoded[comboMode] = encodeSlotMap(modeData);
        end
    end

    local payload = {
        xiuiExportVersion = EXPORT_VERSION,
        kind = M.KIND_CROSSBAR,
        scope = 'job',
        paletteName = paletteName,
        jobId = jobId or 1,
        subjobTier = subjobTier or 0,
        storageKey = storageKey,
        defaultMacroKey = macroKeyToString(defaultMacroKey),
        exportPart = exportPart,
    };
    if exportPart ~= M.EXPORT_PART_MACROS_ONLY then
        payload.slotActions = encoded;
    end
    if exportPart ~= M.EXPORT_PART_SLOTS_ONLY then
        payload.macros = macros;
    else
        payload.macros = {};
    end
    local ok, result = pcall(json.encode, payload);
    if not ok then
        return nil, tostring(result);
    end
    return result;
end

--- Export Global [G] crossbar palette.
function M.ExportCrossbarUniversalPalette(paletteName, exportPart)
    if not gConfig then
        return nil, 'No config';
    end
    exportPart = exportPart or M.EXPORT_PART_FULL;
    if not paletteName or paletteName == '' then
        return nil, 'No palette name';
    end
    local storageKey = palette.BuildUniversalCrossbarStorageKey(paletteName);
    local hc = gConfig and gConfig.hotbarCrossbar;
    if not hc or not hc.slotActions or not hc.slotActions[storageKey] then
        return nil, 'Universal crossbar palette not found';
    end
    local slotRoot = hc.slotActions[storageKey];
    local defaultMacroKey = macroKeyFromStorageKey(storageKey);
    local want = collectMacroRefsFromCrossbar(slotRoot, defaultMacroKey);
    local macros = buildMacroExportBuckets(want);

    local encoded = {};
    for comboMode, modeData in pairs(slotRoot) do
        if type(modeData) == 'table' then
            encoded[comboMode] = encodeSlotMap(modeData);
        end
    end

    local payload = {
        xiuiExportVersion = EXPORT_VERSION,
        kind = M.KIND_CROSSBAR,
        scope = 'universal',
        paletteName = paletteName,
        storageKey = storageKey,
        defaultMacroKey = macroKeyToString(defaultMacroKey),
        exportPart = exportPart,
    };
    if exportPart ~= M.EXPORT_PART_MACROS_ONLY then
        payload.slotActions = encoded;
    end
    if exportPart ~= M.EXPORT_PART_SLOTS_ONLY then
        payload.macros = macros;
    else
        payload.macros = {};
    end
    local ok, result = pcall(json.encode, payload);
    if not ok then
        return nil, tostring(result);
    end
    return result;
end

local function collectMacroRefsFromHotbarBar(slotMap, defaultMacroKey, want)
    if type(slotMap) ~= 'table' then
        return;
    end
    for _, slot in pairs(slotMap) do
        if type(slot) == 'table' and slot.macroRef then
            local mk = slot.macroPaletteKey or defaultMacroKey;
            local ks = macroKeyToString(mk);
            if ks ~= '' then
                want[ks] = want[ks] or {};
                want[ks][slot.macroRef] = true;
            end
        end
    end
end

--- Export keyboard hotbar palettes (all six bars) for one storage key.
function M.ExportHotbarPalette(jobId, subjobId, paletteName, exportPart)
    if not gConfig then
        return nil, 'No config';
    end
    exportPart = exportPart or M.EXPORT_PART_FULL;
    if not paletteName or paletteName == '' then
        return nil, 'No palette name';
    end
    local storageKey = palette.BuildPaletteStorageKey(jobId or 1, subjobId or 0, paletteName);
    local defaultMacroKey = macroKeyFromStorageKey(storageKey);
    local want = {};

    local bars = {};
    for barIdx = 1, 6 do
        local cfg = gConfig and gConfig['hotbarBar' .. barIdx];
        local slotMap = cfg and cfg.slotActions and cfg.slotActions[storageKey];
        bars[tostring(barIdx)] = encodeSlotMap(slotMap or {});
        collectMacroRefsFromHotbarBar(slotMap, defaultMacroKey, want);
    end

    local macros = buildMacroExportBuckets(want);
    local payload = {
        xiuiExportVersion = EXPORT_VERSION,
        kind = M.KIND_HOTBAR,
        paletteName = paletteName,
        jobId = jobId or 1,
        subjobId = subjobId or 0,
        storageKey = storageKey,
        defaultMacroKey = macroKeyToString(defaultMacroKey),
        exportPart = exportPart,
    };
    if exportPart ~= M.EXPORT_PART_MACROS_ONLY then
        payload.hotbarBars = bars;
    end
    if exportPart ~= M.EXPORT_PART_SLOTS_ONLY then
        payload.macros = macros;
    else
        payload.macros = {};
    end
    local ok, result = pcall(json.encode, payload);
    if not ok then
        return nil, tostring(result);
    end
    return result;
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

local function importMacrosRemap(destMacroKey, macrosObj)
    if not gConfig then
        return nil, 'No config';
    end
    if not gConfig.macroDB then
        gConfig.macroDB = {};
    end
    local destBucket = gConfig.macroDB[destMacroKey];
    if not destBucket then
        gConfig.macroDB[destMacroKey] = {};
        destBucket = gConfig.macroDB[destMacroKey];
    end
    local maxId = nextMacroIdInBucket(destBucket);
    local idMaps = {}; -- [srcKs][oldId] = newId

    for srcKs, macroList in pairs(macrosObj or {}) do
        if type(macroList) == 'table' then
            idMaps[srcKs] = idMaps[srcKs] or {};
            for _, m in ipairs(macroList) do
                if type(m) == 'table' and m.id then
                    local oldId = m.id;
                    maxId = maxId + 1;
                    local copy = deepCopy(m);
                    copy.id = maxId;
                    table.insert(destBucket, copy);
                    idMaps[srcKs][oldId] = maxId;
                end
            end
        end
    end
    return idMaps;
end

local function validateMacroCoverageFromSlots(walkFn, slotRoot, macrosObj, defaultMacroKeyStr)
    local defKs = defaultMacroKeyStr or '';
    local need = {};
    walkFn(slotRoot, function(_, _, slot)
        if type(slot) == 'table' and slot.macroRef then
            local srcKs = macroKeyToString(slot.macroPaletteKey);
            if srcKs == '' then
                srcKs = defKs;
            end
            need[srcKs] = need[srcKs] or {};
            need[srcKs][slot.macroRef] = true;
        end
    end);
    for ks, ids in pairs(need) do
        local macroList = macrosObj and macrosObj[ks];
        if type(macroList) ~= 'table' then
            return false, 'Export is missing macro bucket: ' .. ks;
        end
        local found = {};
        for _, m in ipairs(macroList) do
            if m and m.id then
                found[m.id] = true;
            end
        end
        for id, _ in pairs(ids) do
            if not found[id] then
                return false, string.format('Export is missing macro id %s in bucket %s', tostring(id), ks);
            end
        end
    end
    return true;
end

local function walkHotbarAllBars(hotbarBarsDecoded, fn)
    if type(hotbarBarsDecoded) ~= 'table' then
        return;
    end
    for barIdx = 1, 6 do
        local enc = hotbarBarsDecoded[tostring(barIdx)];
        local slotMap = decodeSlotMap(enc or {});
        for slotIdx, slot in pairs(slotMap) do
            if type(slot) == 'table' then
                fn(barIdx, slotIdx, slot);
            end
        end
    end
end

local function remapCrossbarMacroRefs(slotRoot, destMacroKey, defaultMacroKeyStr, idMaps)
    local defKs = defaultMacroKeyStr or '';
    walkCrossbarComboSlots(slotRoot, function(_, _, slot)
        if slot.macroRef then
            local srcKs = macroKeyToString(slot.macroPaletteKey);
            if srcKs == '' then
                srcKs = defKs;
            end
            local map = idMaps[srcKs];
            if map and map[slot.macroRef] then
                slot.macroRef = map[slot.macroRef];
                slot.macroPaletteKey = destMacroKey;
            end
        end
    end);
end

local function remapHotbarMacroRefs(barSlotMap, destMacroKey, defaultMacroKeyStr, idMaps)
    if type(barSlotMap) ~= 'table' then
        return;
    end
    for _, slot in pairs(barSlotMap) do
        if type(slot) == 'table' and slot.macroRef then
            local srcKs = macroKeyToString(slot.macroPaletteKey);
            if srcKs == '' then
                srcKs = defaultMacroKeyStr or '';
            end
            local map = idMaps[srcKs];
            if map and map[slot.macroRef] then
                slot.macroRef = map[slot.macroRef];
                slot.macroPaletteKey = destMacroKey;
            end
        end
    end
end

local function hasMacroPayload(decoded)
    return decoded.macros and type(decoded.macros) == 'table' and next(decoded.macros) ~= nil;
end

--- Write decoded hotbar bars (by index 1..6) into gConfig for the destination palette.
--- If idMaps is given, remap macro refs while copying.
local function applyDecodedHotbarBars(decodedHotbarBars, destStorageKey, destMacroKey, defaultMacroKeyStr, idMaps)
    for barIdx = 1, 6 do
        local cfgKey = 'hotbarBar' .. barIdx;
        local cfg = gConfig and gConfig[cfgKey];
        if not cfg then
            gConfig[cfgKey] = {};
            cfg = gConfig[cfgKey];
        end
        if not cfg.slotActions then
            cfg.slotActions = {};
        end
        local enc = decodedHotbarBars and decodedHotbarBars[tostring(barIdx)];
        local slotMap = decodeSlotMap(enc or {});
        if idMaps then
            remapHotbarMacroRefs(slotMap, destMacroKey, defaultMacroKeyStr, idMaps);
        end
        cfg.slotActions[destStorageKey] = slotMap;
    end
end

local function hasCrossbarSlotPayload(decoded)
    return decoded.slotActions ~= nil;
end

local function hasHotbarSlotPayload(decoded)
    return decoded.hotbarBars ~= nil;
end

--- Import crossbar palette JSON into an existing destination palette.
--- opts.importSlots (default true), opts.importMacros (default true), opts.purgeExclusiveMacrosFirst
function M.ImportCrossbarPalette(jsonStr, opts)
    opts = opts or {};
    local importSlots = opts.importSlots ~= false;
    local importMacros = opts.importMacros ~= false;
    if not importSlots and not importMacros then
        return false, 'Select at least one: slot bindings or macros.';
    end
    if not gConfig then
        return false, 'No config';
    end
    local ok, res = pcall(json.decode, jsonStr);
    if not ok then
        return false, 'Invalid JSON: ' .. tostring(res);
    end
    local decoded = res;
    if decoded.xiuiExportVersion ~= EXPORT_VERSION or decoded.kind ~= M.KIND_CROSSBAR then
        return false, 'Not a XIUI crossbar palette export (wrong version or kind).';
    end

    local destStorageKey = opts.destStorageKey;
    if not destStorageKey or destStorageKey == '' then
        return false, 'No destination storage key';
    end
    local hc = gConfig and gConfig.hotbarCrossbar;
    if not hc then
        return false, 'Crossbar settings missing';
    end
    if not hc.slotActions or not hc.slotActions[destStorageKey] then
        return false, 'Destination palette does not exist. Create it first.';
    end

    local hasSlots = hasCrossbarSlotPayload(decoded);
    local hasMacros = hasMacroPayload(decoded);
    if importSlots and not hasSlots then
        return false, 'JSON has no crossbar slot data. Uncheck Import slot bindings or use a file that includes slots.';
    end
    if importMacros and not hasMacros and not importSlots then
        return false, 'JSON has no macro data. Uncheck Import macros or use a file that includes macros.';
    end
    --- File has no macro payload: nothing to append. Fall through to slots-only logic,
    --- which validates any macroRefs against the destination's macroDB.
    if importSlots and importMacros and not hasMacros then
        importMacros = false;
    end

    if opts.purgeExclusiveMacrosFirst and importSlots then
        purgeExclusiveMacrosForStorageKey(destStorageKey, 'crossbar');
    end

    local destMacroKey = macroKeyFromStorageKey(destStorageKey);
    local defaultMacroKeyStr = decoded.defaultMacroKey or macroKeyToString(macroKeyFromStorageKey(decoded.storageKey or ''));

    local slotRoot = {};
    if hasSlots then
        for comboMode, modeData in pairs(decoded.slotActions or {}) do
            if type(modeData) == 'table' then
                slotRoot[comboMode] = decodeSlotMap(modeData);
            end
        end
    end

    if importSlots and importMacros then
        local okCov, errCov = validateMacroCoverageFromSlots(walkCrossbarComboSlots, slotRoot, decoded.macros, defaultMacroKeyStr);
        if not okCov then
            return false, errCov or 'Macro coverage check failed';
        end
        local idMaps, ierr = importMacrosRemap(destMacroKey, decoded.macros);
        if not idMaps then
            return false, ierr or 'Macro import failed';
        end
        remapCrossbarMacroRefs(slotRoot, destMacroKey, defaultMacroKeyStr, idMaps);
        hc.slotActions[destStorageKey] = slotRoot;
    elseif importSlots and not importMacros then
        local okV, errV = validateSlotMacroRefsCrossbar(slotRoot, destStorageKey);
        if not okV then
            return false, errV;
        end
        hc.slotActions[destStorageKey] = slotRoot;
    elseif importMacros and not importSlots then
        local idMaps, ierr = importMacrosRemap(destMacroKey, decoded.macros);
        if not idMaps then
            return false, ierr or 'Macro import failed';
        end
    end

    data.MarkMacroLookupDirty();
    palette.InvalidateCachesAfterExternalSlotMutation();
    if SaveSettingsToDisk then
        SaveSettingsToDisk();
    end
    return true;
end

--- Import hotbar palette JSON (all six bars) into an existing destination palette.
function M.ImportHotbarPalette(jsonStr, opts)
    opts = opts or {};
    local importSlots = opts.importSlots ~= false;
    local importMacros = opts.importMacros ~= false;
    if not importSlots and not importMacros then
        return false, 'Select at least one: slot bindings or macros.';
    end
    if not gConfig then
        return false, 'No config';
    end
    local ok, res = pcall(json.decode, jsonStr);
    if not ok then
        return false, 'Invalid JSON: ' .. tostring(res);
    end
    local decoded = res;
    if decoded.xiuiExportVersion ~= EXPORT_VERSION or decoded.kind ~= M.KIND_HOTBAR then
        return false, 'Not a XIUI hotbar palette export (wrong version or kind).';
    end

    local destStorageKey = opts.destStorageKey;
    if not destStorageKey or destStorageKey == '' then
        return false, 'No destination storage key';
    end

    local hb1 = gConfig.hotbarBar1;
    if not hb1 or not hb1.slotActions or not hb1.slotActions[destStorageKey] then
        return false, 'Destination hotbar palette does not exist. Create it first.';
    end

    local hasSlots = hasHotbarSlotPayload(decoded);
    local hasMacros = hasMacroPayload(decoded);
    if importSlots and not hasSlots then
        return false, 'JSON has no hotbar slot data. Uncheck Import slot bindings or use a file that includes slots.';
    end
    if importMacros and not hasMacros and not importSlots then
        return false, 'JSON has no macro data. Uncheck Import macros or use a file that includes macros.';
    end
    --- File has no macro payload: nothing to append. Fall through to slots-only logic,
    --- which validates any macroRefs against the destination's macroDB.
    if importSlots and importMacros and not hasMacros then
        importMacros = false;
    end

    if opts.purgeExclusiveMacrosFirst and importSlots then
        purgeExclusiveMacrosForStorageKey(destStorageKey, 'hotbar');
    end

    local destMacroKey = macroKeyFromStorageKey(destStorageKey);
    local defaultMacroKeyStr = decoded.defaultMacroKey or macroKeyToString(macroKeyFromStorageKey(decoded.storageKey or ''));

    if importSlots and importMacros then
        local okCov, errCov = validateMacroCoverageFromSlots(
            walkHotbarAllBars, decoded.hotbarBars or {}, decoded.macros, defaultMacroKeyStr);
        if not okCov then
            return false, errCov or 'Macro coverage check failed';
        end
        local idMaps, ierr = importMacrosRemap(destMacroKey, decoded.macros);
        if not idMaps then
            return false, ierr or 'Macro import failed';
        end
        applyDecodedHotbarBars(decoded.hotbarBars, destStorageKey, destMacroKey, defaultMacroKeyStr, idMaps);
    elseif importSlots and not importMacros then
        local okV, errV = validateSlotMacroRefsHotbar(decoded.hotbarBars, destStorageKey);
        if not okV then
            return false, errV;
        end
        applyDecodedHotbarBars(decoded.hotbarBars, destStorageKey, destMacroKey, defaultMacroKeyStr, nil);
    elseif importMacros and not importSlots then
        local idMaps, ierr = importMacrosRemap(destMacroKey, decoded.macros);
        if not idMaps then
            return false, ierr or 'Macro import failed';
        end
    end

    data.MarkMacroLookupDirty();
    palette.InvalidateCachesAfterExternalSlotMutation();
    if SaveSettingsToDisk then
        SaveSettingsToDisk();
    end
    return true;
end

--- Write UTF-8 text under Ashita config/addons/xiui/exports/ (creates folder).
function M.SaveTextFile(baseName, text)
    local dir = AshitaCore:GetInstallPath() .. 'config\\addons\\xiui\\exports\\';
    if ashita.fs and not ashita.fs.exists(dir) then
        ashita.fs.create_directory(dir);
    end
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
