--[[
  Seed default Global macros (same spirit as macro_xiui_defaults.lua for XIUI Commands).
]]--

local buckets = require('modules.hotbar.macro_palette_buckets');
local universalTwoHour = require('modules.hotbar.universal_two_hour');
local data = require('modules.hotbar.data');

local M = {};

--- Relative to addons/XIUI/ on disk (icons bundled with the addon).
M.UNIVERSAL_TWO_HOUR_ICON_PATH = 'assets/status/HD/228.png';

function M.IsUniversalTwoHourMacro(macro)
    return macro and macro.actionType == 'ja' and macro.action == universalTwoHour.ACTION_SENTINEL;
end

local function maxMacroIdInBucket(db)
    local maxId = 0;
    if type(db) ~= 'table' then
        return maxId;
    end
    for _, macro in ipairs(db) do
        if macro.id and macro.id > maxId then
            maxId = macro.id;
        end
    end
    return maxId;
end

local function maxMacroIdAll(mdb)
    local maxId = 0;
    if not mdb or type(mdb) ~= 'table' then
        return maxId;
    end
    for _, list in pairs(mdb) do
        if type(list) == 'table' then
            for _, macro in ipairs(list) do
                if macro.id and macro.id > maxId then
                    maxId = macro.id;
                end
            end
        end
    end
    return maxId;
end

local function findUniversalTwoHourIndex(db)
    if type(db) ~= 'table' then
        return nil;
    end
    for i, macro in ipairs(db) do
        if M.IsUniversalTwoHourMacro(macro) then
            return i;
        end
    end
    return nil;
end

--- opts.persist: when false, skip SaveSettingsToDisk (caller batches save).
--- Returns true if macroDB was mutated.
function M.SyncUniversalTwoHourGlobalRow(gConfig, opts)
    if not gConfig then
        return false;
    end
    opts = (type(opts) == 'table') and opts or {};
    local persist = opts.persist ~= false;
    if not gConfig.macroDB then
        return false;
    end
    local db = gConfig.macroDB[buckets.GLOBAL];
    if type(db) ~= 'table' then
        return false;
    end
    local idx = findUniversalTwoHourIndex(db);
    if not idx then
        return false;
    end

    local macro = db[idx];
    local abilityName = universalTwoHour.GetTwoHourAbilityNameForMainJob() or 'Two Hour';
    local tgt = universalTwoHour.GetTwoHourTargetTokenForMainJob();
    local changed = false;

    if (macro.displayName or '') ~= abilityName then
        macro.displayName = abilityName;
        changed = true;
    end
    if (macro.target or '') ~= tgt then
        macro.target = tgt;
        changed = true;
    end
    if macro.customIconType ~= 'xiui_asset' or (macro.customIconPath or '') ~= M.UNIVERSAL_TWO_HOUR_ICON_PATH then
        macro.customIconType = 'xiui_asset';
        macro.customIconPath = M.UNIVERSAL_TWO_HOUR_ICON_PATH;
        changed = true;
    end

    if idx ~= 1 then
        table.remove(db, idx);
        table.insert(db, 1, macro);
        changed = true;
    end

    if changed then
        data.MarkMacroLookupDirty();
        if persist and SaveSettingsToDisk then
            SaveSettingsToDisk();
        end
    end

    return changed;
end

local function globalBucketHasUniversalTwoHour(db)
    return findUniversalTwoHourIndex(db) ~= nil;
end

--- opts.force: seed even if macroGlobalUniversalTwoHourSeeded is true (empty shared library path).
--- Returns true if a macro row was added.
function M.SeedUniversalTwoHourIfNeeded(gConfig, opts)
    if not gConfig then
        return false;
    end
    opts = (type(opts) == 'table') and opts or {};
    if not gConfig.macroDB then
        gConfig.macroDB = {};
    end
    local db = gConfig.macroDB[buckets.GLOBAL];
    if type(db) ~= 'table' then
        db = {};
        gConfig.macroDB[buckets.GLOBAL] = db;
    end
    if globalBucketHasUniversalTwoHour(db) then
        gConfig.macroGlobalUniversalTwoHourSeeded = true;
        M.SyncUniversalTwoHourGlobalRow(gConfig, { persist = opts.persist ~= false });
        return false;
    end
    if (not opts.force) and gConfig.macroGlobalUniversalTwoHourSeeded then
        return false;
    end

    local nextId = math.max(maxMacroIdAll(gConfig.macroDB), maxMacroIdInBucket(db));
    if (gConfig.macroStorageScope or 'profile') == 'shared' then
        local ok, sms = pcall(require, 'core.shared_macro_store');
        if ok and sms and sms.GetMaxMacroIdInFrozenProfileBucket then
            local fmax = sms.GetMaxMacroIdInFrozenProfileBucket(buckets.GLOBAL);
            if fmax > nextId then
                nextId = fmax;
            end
        end
    end

    nextId = nextId + 1;
    table.insert(db, 1, {
        id = nextId,
        actionType = 'ja',
        action = universalTwoHour.ACTION_SENTINEL,
        target = universalTwoHour.GetTwoHourTargetTokenForMainJob(),
        displayName = universalTwoHour.GetTwoHourAbilityNameForMainJob() or 'Two Hour',
        customIconType = 'xiui_asset',
        customIconPath = M.UNIVERSAL_TWO_HOUR_ICON_PATH,
    });
    gConfig.macroGlobalUniversalTwoHourSeeded = true;
    M.SyncUniversalTwoHourGlobalRow(gConfig, { persist = false });
    data.MarkMacroLookupDirty();
    if opts.persist ~= false and SaveSettingsToDisk then
        SaveSettingsToDisk();
    end
    return true;
end

return M;
