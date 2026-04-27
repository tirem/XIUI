--[[
* Shared vs Profile macro storage: one global SharedMacros.lua vs per-profile gConfig.macroDB.
* When scope is "shared", gConfig.macroDB is the working copy of SharedMacros.lua only; the profile file
* stores a frozen macroDB snapshot for when this profile is in shared mode (or last profile mode),
* so switching back to Profile restores that library. We never copy the profile into the shared library
* when the shared file is missing or empty — that is a different library; use the file or {}.
]]--

local profileManager = require('core.profile_manager');

local M = {};

local SHARED_FILENAME = 'SharedMacros.lua';

local function deepCopyTable(tbl)
    if type(tbl) ~= 'table' then
        return tbl;
    end
    local copy = {};
    for k, v in pairs(tbl) do
        copy[k] = deepCopyTable(v);
    end
    return copy;
end

local function lookupInMacroDb(mdb, macroId, paletteKey)
    if not mdb or not macroId then
        return nil;
    end
    local pk = paletteKey or 1;
    local function one(bk)
        if bk == nil then
            return nil;
        end
        local macros = mdb[bk];
        if type(macros) ~= 'table' then
            return nil;
        end
        for _, m in ipairs(macros) do
            if m and m.id == macroId then
                return m;
            end
        end
        return nil;
    end
    local m = one(pk);
    if m then
        return m;
    end
    if type(pk) == 'number' and pk > 0 then
        m = one(tostring(pk));
    end
    if m then
        return m;
    end
    if type(pk) == 'string' and pk:match('^%d+$') then
        m = one(tonumber(pk));
    end
    if m then
        return m;
    end
    if type(pk) == 'string' then
        local baseJobId = tonumber(pk:match('^(%d+)'));
        if baseJobId then
            m = one(baseJobId) or one(tostring(baseJobId));
        end
    end
    return m;
end

local function pcallEnsureMacroCoherence(gConfig)
    local ok, mod = pcall(require, 'modules.hotbar.data');
    if ok and mod and mod.EnsureMacroDatabaseCoherence then
        mod.EnsureMacroDatabaseCoherence(gConfig);
    end
end

-- New / empty Shared library: add only the xiui slash-command bucket (same as fresh profile migration).
local function pcallMaybeSeedXiuiForEmptySharedLibrary(gConfig)
    if not M.IsSharedScope(gConfig) or not gConfig then
        return;
    end
    if not gConfig.macroDB then
        gConfig.macroDB = {};
    end
    local ok, mxd = pcall(require, 'modules.hotbar.macro_xiui_defaults');
    if not ok or not mxd or not mxd.IsMacroDatabaseEffectivelyEmpty or not mxd.SeedIfNeeded then
        return;
    end
    if not mxd.IsMacroDatabaseEffectivelyEmpty(gConfig.macroDB) then
        return;
    end
    if mxd.SeedIfNeeded(gConfig, { force = true }) then
        M.MarkSharedLibraryDirty();
        local ok2, dat = pcall(require, 'modules.hotbar.data');
        if ok2 and dat and dat.MarkMacroLookupDirty then
            dat.MarkMacroLookupDirty();
        end
    end
    pcallEnsureMacroCoherence(gConfig);
end

-- Frozen profile macroDB (per profile file) used while in shared scope; never replaced by shared edits.
local frozenProfileMacroDb = nil;

-- Cached on-disk shared file for resolving bar slots with macroSourceStore == "shared" while in profile mode.
local diskSharedMacroDbCache = nil;
local diskSharedMacroDbPathIdentity = nil;

-- Only write SharedMacros.lua when the global library actually changed (not on every UI/settings save).
local sharedLibraryDirty = false;

function M._ProfilesDir()
    return AshitaCore:GetInstallPath() .. 'config\\addons\\xiui\\profiles\\';
end

function M.GetSharedFilePath()
    return M._ProfilesDir() .. SHARED_FILENAME;
end

local function sharedMacroFileExists()
    local path = M.GetSharedFilePath();
    if (ashita and ashita.fs and ashita.fs.exists) and ashita.fs.exists(path) then
        return true;
    end
    local f = io.open(path, 'rb');
    if f then
        f:close();
        return true;
    end
    return false;
end

--- If Shared mode is on but SharedMacros.lua is not on disk yet, write it once (e.g. empty macroDB).
--- Otherwise the file only appears after MarkSharedLibraryDirty + save, which never ran on a fresh switch.
function M.EnsureSharedMacroFileOnDisk(gConfig)
    if not M.IsSharedScope(gConfig) or sharedMacroFileExists() then
        return;
    end
    M.SaveSharedMacroFile(gConfig.macroDB or {});
end

function M.InvalidateDiskSharedCache()
    diskSharedMacroDbCache = nil;
    diskSharedMacroDbPathIdentity = nil;
end

-- Load { macroDB = ... } from SharedMacros.lua (same wrapper shape as profile files).
function M.LoadSharedMacroFile()
    local path = M.GetSharedFilePath();
    local t = profileManager.LoadTable(path);
    if not t then
        return nil;
    end
    if t.userSettings and t.userSettings.macroDB then
        return t.userSettings.macroDB;
    end
    if t.macroDB then
        return t.macroDB;
    end
    return nil;
end

function M.SaveSharedMacroFile(macroDB)
    if not macroDB then
        return false;
    end
    local path = M.GetSharedFilePath();
    local wrapper = { userSettings = { macroDB = macroDB } };
    local ok = profileManager.SaveTable(path, wrapper);
    if ok then
        sharedLibraryDirty = false;
        M.InvalidateDiskSharedCache();
    end
    return ok;
end

--- Call when gConfig.macroDB (the live shared library) is mutated: add/update/delete macro, import macros, custom category add/remove, etc.
function M.MarkSharedLibraryDirty()
    sharedLibraryDirty = true;
end

function M.IsSharedScope(gcfg)
    if not gcfg then
        return false;
    end
    return (gcfg.macroStorageScope or 'profile') == 'shared';
end

-- Deep copy (stable for macroDB)
local function copyMacroDb(mdb)
    if type(mdb) ~= 'table' then
        return {};
    end
    return deepCopyTable(mdb);
end

function M.GetDiskSharedMacroDbForExternalLookup()
    local path = M.GetSharedFilePath();
    if diskSharedMacroDbCache and diskSharedMacroDbPathIdentity == path then
        return diskSharedMacroDbCache;
    end
    local mdb = M.LoadSharedMacroFile();
    if not mdb or type(mdb) ~= 'table' then
        mdb = {};
    end
    diskSharedMacroDbCache = mdb;
    diskSharedMacroDbPathIdentity = path;
    return mdb;
end

function M.GetFrozenProfileMacroDb()
    return frozenProfileMacroDb;
end

--- Max numeric macro id in one bucket of the frozen profile snapshot (while in Shared scope).
--- New macros in Shared must use ids above this per bucket so hotbar macroRef values that still
--- point at the profile library (same palette key) do not resolve to a different row in the shared library.
function M.GetMaxMacroIdInFrozenProfileBucket(bucketKey)
    if not frozenProfileMacroDb or bucketKey == nil then
        return 0;
    end
    local list = frozenProfileMacroDb[bucketKey];
    if not list and type(bucketKey) == 'number' then
        list = frozenProfileMacroDb[tostring(bucketKey)];
    end
    if not list and type(bucketKey) == 'string' and bucketKey:match('^%d+$') then
        list = frozenProfileMacroDb[tonumber(bucketKey)];
    end
    if type(list) ~= 'table' then
        return 0;
    end
    local maxId = 0;
    for _, m in ipairs(list) do
        if m and type(m.id) == 'number' and m.id > maxId then
            maxId = m.id;
        end
    end
    return maxId;
end

-- Look up a macro when the slot is tagged for the "other" universe.
function M.LookupInFrozenProfile(macroId, paletteKey)
    if not frozenProfileMacroDb then
        return nil;
    end
    return lookupInMacroDb(frozenProfileMacroDb, macroId, paletteKey);
end

function M.LookupInDiskSharedFile(macroId, paletteKey)
    local mdb = M.GetDiskSharedMacroDbForExternalLookup();
    if not mdb then
        return nil;
    end
    return lookupInMacroDb(mdb, macroId, paletteKey);
end

--- After profile load and migrations. Chooses in-memory gConfig.macroDB based on scope.
function M.ApplyAfterProfileLoad(gConfig)
    if not gConfig then
        return;
    end
    M.InvalidateDiskSharedCache();
    sharedLibraryDirty = false;

    local scope = gConfig.macroStorageScope or 'profile';
    if scope == 'shared' then
        frozenProfileMacroDb = copyMacroDb(gConfig.macroDB);
        local fromDisk = M.LoadSharedMacroFile();
        -- In shared scope, the live list is *only* what is in SharedMacros.lua (including {}).
        -- Do not seed from the profile: that is a separate store (frozen in the profile file while here).
        if type(fromDisk) == 'table' then
            gConfig.macroDB = copyMacroDb(fromDisk);
        else
            gConfig.macroDB = {};
        end
        pcallEnsureMacroCoherence(gConfig);
        pcallMaybeSeedXiuiForEmptySharedLibrary(gConfig);
        M.EnsureSharedMacroFileOnDisk(gConfig);
    else
        frozenProfileMacroDb = nil;
    end
end

-- Called before writing the active profile to disk. When in shared mode, the profile file's macroDB
-- must stay the frozen snapshot, not the live global library.
function M.GetProfileMacroDbForSave(gConfig)
    if M.IsSharedScope(gConfig) then
        if frozenProfileMacroDb then
            return copyMacroDb(frozenProfileMacroDb);
        end
        -- Do not write the in-memory global library into the profile file
        return copyMacroDb({});
    end
    if not gConfig.macroDB then
        gConfig.macroDB = {};
    end
    return gConfig.macroDB;
end

-- Persist the global shared file from current gConfig.macroDB (shared scope only, and when dirty; always create the file if missing).
function M.PersistSharedLibraryIfNeeded(gConfig)
    if not M.IsSharedScope(gConfig) then
        return;
    end
    M.EnsureSharedMacroFileOnDisk(gConfig);
    if not sharedLibraryDirty then
        return;
    end
    M.SaveSharedMacroFile(gConfig.macroDB);
end

-- Switching scope from UI: profile -> shared
function M.ApplySwitchToShared(gConfig)
    if not gConfig then
        return;
    end
    frozenProfileMacroDb = copyMacroDb(gConfig.macroDB);
    gConfig.macroStorageScope = 'shared';
    local fromDisk = M.LoadSharedMacroFile();
    if type(fromDisk) == 'table' then
        gConfig.macroDB = copyMacroDb(fromDisk);
    else
        gConfig.macroDB = {};
    end
    pcallEnsureMacroCoherence(gConfig);
    M.InvalidateDiskSharedCache();
    sharedLibraryDirty = false;
    pcallMaybeSeedXiuiForEmptySharedLibrary(gConfig);
    M.EnsureSharedMacroFileOnDisk(gConfig);
end

-- Switching scope from UI: shared -> profile
function M.ApplySwitchToProfile(gConfig)
    if not gConfig then
        return;
    end
    sharedLibraryDirty = false;
    gConfig.macroStorageScope = 'profile';
    if frozenProfileMacroDb then
        gConfig.macroDB = copyMacroDb(frozenProfileMacroDb);
    else
        gConfig.macroDB = gConfig.macroDB or {};
    end
    frozenProfileMacroDb = nil;
    pcallEnsureMacroCoherence(gConfig);
end

return M;
