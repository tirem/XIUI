--[[
* One-time seed of default /xiui slash macros into the "xiui" macro bucket.
]]--

local buckets = require('modules.hotbar.macro_palette_buckets');

local DEFAULT_ROWS = {
    { displayName = 'Toggle XIUI Menu', macroText = '/xiui', action = '/xiui' },
    { displayName = 'Open Macros', macroText = '/xiui macro', action = '/xiui macro' },
    { displayName = 'Hotbar Palette Manager', macroText = '/xiui pal', action = '/xiui pal' },
    { displayName = 'Crossbar Palette Manager', macroText = '/xiui cpal', action = '/xiui cpal' },
    { displayName = 'Edit Current Palette', macroText = '/xiui cpaledit', action = '/xiui cpaledit' },
    { displayName = 'Toggle Party List', macroText = '/xiui partylist', action = '/xiui partylist' },
    { displayName = 'Pass All Treasure', macroText = '/xiui pass', action = '/xiui pass' },
    { displayName = 'Toggle Treasure Pool', macroText = '/xiui tp', action = '/xiui tp' },
    { displayName = 'Reset Gil Tracking', macroText = '/xiui gil reset', action = '/xiui gil reset' },
};

local function maxMacroId(db)
    local maxId = 0;
    for _, macro in ipairs(db) do
        if macro.id and macro.id > maxId then
            maxId = macro.id;
        end
    end
    return maxId;
end

local M = {};

--- True when there are no macro rows in any bucket (or macroDB is missing/empty).
function M.IsMacroDatabaseEffectivelyEmpty(mdb)
    if not mdb or type(mdb) ~= 'table' or next(mdb) == nil then
        return true;
    end
    for _, list in pairs(mdb) do
        if type(list) == 'table' and #list > 0 then
            return false;
        end
    end
    return true;
end

--- opts.force: seed the xiui bucket even if macroXiuiDefaultsSeeded is true (e.g. new empty Shared library).
--- Returns true if new default rows were added.
function M.SeedIfNeeded(gConfig, opts)
    if not gConfig then
        return false;
    end
    opts = (type(opts) == 'table') and opts or {};
    if not gConfig.macroDB then
        gConfig.macroDB = {};
    end
    local db = gConfig.macroDB[buckets.XIUI];
    if type(db) ~= 'table' then
        db = {};
        gConfig.macroDB[buckets.XIUI] = db;
    end
    if #db > 0 then
        gConfig.macroXiuiDefaultsSeeded = true;
        return false;
    end
    if (not opts.force) and gConfig.macroXiuiDefaultsSeeded then
        return false;
    end

    local nextId = maxMacroId(db);
    if (gConfig.macroStorageScope or 'profile') == 'shared' then
        local ok, sms = pcall(require, 'core.shared_macro_store');
        if ok and sms and sms.GetMaxMacroIdInFrozenProfileBucket then
            local fmax = sms.GetMaxMacroIdInFrozenProfileBucket(buckets.XIUI);
            if fmax > nextId then
                nextId = fmax;
            end
        end
    end
    for _, row in ipairs(DEFAULT_ROWS) do
        nextId = nextId + 1;
        table.insert(db, {
            id = nextId,
            actionType = 'macro',
            action = row.action,
            target = row.target,
            displayName = row.displayName,
            macroText = row.macroText,
        });
    end
    gConfig.macroXiuiDefaultsSeeded = true;
    return true;
end

return M;
