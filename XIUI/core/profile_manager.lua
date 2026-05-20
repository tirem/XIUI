local profileManager = {};
local chat = require('chat');
local addonName = 'xiui';
local configPath = AshitaCore:GetInstallPath() .. 'config\\addons\\' .. addonName .. '\\';
local profilesPath = configPath .. 'profiles\\';
local backupsPath = configPath .. 'backups\\';

-- Ensure directories exist
if (not ashita.fs.exists(configPath)) then
    ashita.fs.create_directory(configPath);
end
if (not ashita.fs.exists(profilesPath)) then
    ashita.fs.create_directory(profilesPath);
end
if (not ashita.fs.exists(backupsPath)) then
    ashita.fs.create_directory(backupsPath);
end

-- Backup directories
profileManager.LegacyHxuiBackupPath = backupsPath .. 'legacy\\hxui\\';
profileManager.LegacyXiuiBackupPath = backupsPath .. 'legacy\\xiui\\';
profileManager.ProfilesBackupPath = backupsPath .. 'profiles\\';

-- Helper to copy a file
function profileManager.CopyFile(src, dest)
    local inp = io.open(src, "rb");
    if not inp then return false; end
    local outp = io.open(dest, "wb");
    if not outp then 
        inp:close(); 
        return false; 
    end
    
    local content = inp:read("*all");
    outp:write(content);
    
    inp:close();
    outp:close();
    return true;
end

-- Helper to ensure backup directory structure
function profileManager.EnsureBackupDirectory(path)
    if not ashita.fs.exists(path) then
        -- Handle nested paths for legacy backups
        if path:find("legacy") then
             if not ashita.fs.exists(backupsPath .. 'legacy\\') then
                 ashita.fs.create_directory(backupsPath .. 'legacy\\');
             end
             
             if path:find("xiui") and not ashita.fs.exists(profileManager.LegacyXiuiBackupPath) then
                 ashita.fs.create_directory(profileManager.LegacyXiuiBackupPath);
             end
             
             if path:find("hxui") and not ashita.fs.exists(profileManager.LegacyHxuiBackupPath) then
                 ashita.fs.create_directory(profileManager.LegacyHxuiBackupPath);
             end
        end
        
        -- Handle profiles backup folder
        if path:find("profiles") and not ashita.fs.exists(profileManager.ProfilesBackupPath) then
             ashita.fs.create_directory(profileManager.ProfilesBackupPath);
        end
        
        ashita.fs.create_directory(path);
    end
end

-- Backup all current profiles to backups/profiles/ (flat)
function profileManager.BackupCurrentProfiles(currentVersion)
    -- Copy all .lua files from profilesPath to backupsPath/profiles/
    -- Copy imgui.ini from Ashita config to backupsPath/profiles/
    
    local destPath = profileManager.ProfilesBackupPath;
    profileManager.EnsureBackupDirectory(destPath);
    
    -- 1. Backup Profiles
    local profiles = profileManager.GetGlobalProfiles();
    
    -- Also backup profilelist.lua itself
    profileManager.CopyFile(profilesPath .. 'profilelist.lua', destPath .. 'profilelist.lua');
    
    if profiles and profiles.names then
        for _, name in ipairs(profiles.names) do
            local filename = name .. '.lua';
            profileManager.CopyFile(profilesPath .. filename, destPath .. filename);
        end
    end
    
    -- 2. Backup ImGui
    local imguiPath = AshitaCore:GetInstallPath() .. 'config\\imgui.ini';
    if ashita.fs.exists(imguiPath) then
        profileManager.CopyFile(imguiPath, destPath .. 'imgui.ini');
    end

    -- 3. Update version in profilelist.lua
    if currentVersion then
        profiles.version = currentVersion;
        profileManager.SaveGlobalProfiles(profiles);
    end
    
    return true;
end


-- Serialize table to legacy format (flat assignments)
local function SerializeLegacy(tbl, prefix, lines)
    lines = lines or {}
    
    -- Sort keys for deterministic output
    local keys = {}
    for k in pairs(tbl) do table.insert(keys, k) end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return tostring(ta) < tostring(tb) end
        if ta == 'number' then return a < b end
        if ta == 'string' then return a < b end
        return tostring(a) < tostring(b)
    end)

    for _, k in ipairs(keys) do
        local v = tbl[k]
        local keyStr
        if type(k) == "string" then
             keyStr = string.format("[%q]", k)
        elseif type(k) == "number" then
             keyStr = string.format("[%d]", k)
        elseif type(k) == "boolean" then
             keyStr = string.format("[%s]", tostring(k))
        end
        
        if keyStr then
            local currentPath = prefix .. keyStr
            if type(v) == "table" then
                table.insert(lines, currentPath .. " = {};")
                SerializeLegacy(v, currentPath, lines)
            elseif type(v) == "string" then
                table.insert(lines, currentPath .. " = " .. string.format("%q", v) .. ";")
            elseif type(v) == "number" or type(v) == "boolean" then
                table.insert(lines, currentPath .. " = " .. tostring(v) .. ";")
            end
        end
    end
    
    return table.concat(lines, "\n")
end

-- Atomic write: write to <path>.tmp, validate, rotate <path> -> <path>.bak,
-- then rename .tmp -> <path>. If the game crashes mid-write, the primary file
-- is never observed in a half-written state and .bak preserves the last good
-- copy. Recovery happens in LoadTable.
function profileManager.SaveTable(path, t)
    local tmpPath = path .. '.tmp';
    local bakPath = path .. '.bak';

    -- Clear any stale tmp from a prior interrupted save
    if (ashita.fs.exists(tmpPath)) then
        pcall(os.remove, tmpPath);
    end

    local f, openErr = io.open(tmpPath, "w");
    if (not f) then
        print(chat.header(addon.name):append(chat.message('Failed to open profile temp file: ')):append(chat.error(tostring(openErr))));
        return false;
    end

    -- Lua 5.1 file:write returns the handle on success, nil+err on failure
    -- (e.g., disk full). Check each call instead of validating by reload — a
    -- loadfile+execute validation materializes the entire profile table mid-
    -- frame, which can trigger GC mid-d3d_present and crash the renderer
    -- (see lessons.md: "Texture cache evictions/clears must defer COM release").
    local body = SerializeLegacy(t, "settings", {});
    local w1 = f:write("local settings = {};\n");
    local w2 = w1 and f:write(body);
    local w3 = w2 and f:write("\nreturn settings;");
    local closeOk, closeErr = f:close();

    if (not w1) or (not w2) or (not w3) or (not closeOk) then
        pcall(os.remove, tmpPath);
        print(chat.header(addon.name):append(chat.message('Profile write failed, save aborted: ')):append(chat.error(tostring(closeErr or 'write error'))));
        return false;
    end

    -- Rotate the current primary into .bak (Windows os.rename fails if target exists)
    if (ashita.fs.exists(path)) then
        pcall(os.remove, bakPath);
        local rotated, rotateErr = os.rename(path, bakPath);
        if (not rotated) then
            -- Couldn't move the primary aside; try to remove it directly so the
            -- promotion below can proceed. If that also fails, bail without
            -- touching anything more.
            local removed = os.remove(path);
            if (not removed) then
                pcall(os.remove, tmpPath);
                print(chat.header(addon.name):append(chat.message('Could not rotate profile file, save aborted: ')):append(chat.error(tostring(rotateErr))));
                return false;
            end
        end
    end

    -- Promote tmp to primary
    local promoted, promoteErr = os.rename(tmpPath, path);
    if (not promoted) then
        print(chat.header(addon.name):append(chat.message('Could not promote profile temp file: ')):append(chat.error(tostring(promoteErr))));
        -- Try to restore .bak so the user isn't left with no profile
        if (ashita.fs.exists(bakPath)) then
            pcall(os.rename, bakPath, path);
        end
        return false;
    end

    return true;
end

function profileManager.LoadTable(path)
    local bakPath = path .. '.bak';

    -- Try the primary file first
    if (ashita.fs.exists(path)) then
        local func, err = loadfile(path);
        if (func) then
            local success, result = pcall(func);
            if (success and result ~= nil) then
                return result;
            end
            print(chat.header(addon.name):append(chat.message('Error executing profile: ')):append(chat.error(tostring(result))));
        else
            print(chat.header(addon.name):append(chat.message('Error loading profile: ')):append(chat.error(tostring(err))));
        end
        print(chat.header(addon.name):append(chat.message('Profile corrupt, attempting backup recovery: ')):append(chat.error(path)));
    end

    -- Fall back to .bak (written by atomic SaveTable)
    if (ashita.fs.exists(bakPath)) then
        local func, err = loadfile(bakPath);
        if (func) then
            local success, result = pcall(func);
            if (success and result ~= nil) then
                print(chat.header(addon.name):append(chat.message('Restored profile from backup: ')):append(chat.success(bakPath)));
                -- Promote backup to primary so future loads use it directly
                pcall(profileManager.CopyFile, bakPath, path);
                return result;
            end
        end
        print(chat.header(addon.name):append(chat.message('Profile backup also unloadable: ')):append(chat.error(bakPath)));
    end

    return nil;
end



function profileManager.GetGlobalProfiles()
    local path = profilesPath .. 'profilelist.lua';

    local profiles = profileManager.LoadTable(path);
    if (profiles == nil) then
        profiles = {
            names = { 'Default' },
            order = { 'Default' }
        };
        profileManager.SaveTable(path, profiles);
    end
    return profiles;
end

function profileManager.SaveGlobalProfiles(profiles)
    local path = profilesPath .. 'profilelist.lua';
    return profileManager.SaveTable(path, profiles);
end

function profileManager.SyncProfilesWithDisk()
    local profiles = profileManager.GetGlobalProfiles();
    local diskFiles = ashita.fs.get_directory(profilesPath, '.*\\.lua$');
    local changed = false;
    
    if (diskFiles) then
        -- Helper to check if list contains value
        local function contains(t, val)
            for _, v in ipairs(t) do
                if v == val then return true; end
            end
            return false;
        end
        
        for _, filename in ipairs(diskFiles) do
            if (filename ~= 'profilelist.lua') then
                local profileName = filename:match('(.+)%.lua$');

                if (profileName and not contains(profiles.names, profileName)) then
                    table.insert(profiles.names, profileName);
                    table.insert(profiles.order, profileName);
                    changed = true;
                    print(chat.header(addon.name):append(chat.message('Found new profile on disk: ')):append(chat.success(profileName)));
                end
            end
        end

        -- Remove profiles from list if file no longer exists
        local i = 1;
        while i <= #profiles.names do
            local name = profiles.names[i];
            if name ~= 'Default' and not profileManager.ProfileExists(name) then
                table.remove(profiles.names, i);
                for j, n in ipairs(profiles.order) do
                    if n == name then
                        table.remove(profiles.order, j);
                        break;
                    end
                end
                changed = true;
                print(chat.header(addon.name):append(chat.message('Removed missing profile: ')):append(chat.error(name)));
            else
                i = i + 1;
            end
        end

        -- Sort names for consistent display, but preserve order (user's custom arrangement)
        local oldNames = table.concat(profiles.names, ",");
        table.sort(profiles.names);
        local newNames = table.concat(profiles.names, ",");

        if (oldNames ~= newNames) then
            changed = true;
        end
        
        if (changed) then
            profileManager.SaveGlobalProfiles(profiles);
        end
    end
end

function profileManager.GetProfileSettings(name)
    local path = profilesPath .. name .. '.lua';
    local t = profileManager.LoadTable(path);
    if (t and t.userSettings) then
        return t.userSettings;
    end
    return t;
end

function profileManager.SaveProfileSettings(name, settings)
    -- NOTE: Window positions are now captured live in gConfig.windowPositions by SaveWindowPosition()
    -- We no longer parse imgui.ini here because it may be stale (ImGui flushes to disk lazily).
    -- The passed 'settings' object (which is gConfig) already contains the up-to-date positions.

    local path = profilesPath .. name .. '.lua';
    -- Wrap settings in userSettings to maintain compatibility and use the generic SaveTable
    local wrapper = { userSettings = settings };
    return profileManager.SaveTable(path, wrapper);
end

function profileManager.ProfileExists(name)
    local path = profilesPath .. name .. '.lua';
    return ashita.fs.exists(path);
end

function profileManager.DeleteProfile(name)
    local path = profilesPath .. name .. '.lua';
    if (ashita.fs.exists(path)) then
        os.remove(path);
        return true;
    end
    return false;
end

-- Helper to parse imgui.ini for window positions
-- Only used during legacy migration
local function ParseImguiIni()
    local iniPath = AshitaCore:GetInstallPath() .. 'config\\imgui.ini';
    if (not ashita.fs.exists(iniPath)) then return nil; end

    local f = io.open(iniPath, 'r');
    if (not f) then return nil; end

    local positions = {};
    local currentWindow = nil;
    
    -- Known XIUI window names to look for
    local knownWindows = {
        ["PlayerBar"] = true,
        ["TargetBar"] = true,
        ["ExpBar"] = true,
        ["CastBar"] = true,
        ["EnemyList"] = true,
        ["GilTracker"] = true,
        ["InventoryTracker"] = true,
        ["MobInfo"] = true,
        ["PetBar"] = true,
        ["PetBarTarget"] = true,
        ["Notifications"] = true,
        ["TreasurePool"] = true,
        ["CastCost"] = true,
        ["PartyList"] = true,
        ["PartyList2"] = true,
        ["PartyList3"] = true,
        ["mobdb_infobar"] = true,
        ["MobDB_Detail_View"] = true,
        ["SimpleLog - v0.1.1"] = true,
        ["SimpleLog - v0.1.2"] = true,
        ["xitools.treas"] = true,
        ["xitools.tracker"] = true,
        ["xitools.inv"] = true,
        ["xitools.cast"] = true,
        ["xitools.week"] = true,
        ["xitools.crafty"] = true,
        ["xitools.fishe"] = true,
        ["st_ui"] = true,
        ["st_flags_starget"] = true,
        ["st_flags_mtarget"] = true,
        ["trials"] = true,
        ["PointsBar_Nerf"] = true,
        ["hticks"] = true,
    };

    for line in f:lines() do
        -- Check for section header [Window][WindowName]
        local section = line:match("^%[Window%](%[.*%])$");
        if (section) then
            -- Remove brackets to get name
            currentWindow = section:match("^%[(.*)%]$");
            -- Check if it's one of our windows
            if (currentWindow and not knownWindows[currentWindow]) then
                currentWindow = nil;
            end
        elseif (currentWindow) then
            -- Parse Pos=x,y
            local x, y = line:match("^Pos=(%-?%d+),(%-?%d+)$");
            if (x and y) then
                positions[currentWindow] = { x = tonumber(x), y = tonumber(y) };
                currentWindow = nil; -- We found the pos, move on
            end
        end
    end
    
    f:close();
    return positions;
end

function profileManager.GetImguiPositions()
    return ParseImguiIni();
end

return profileManager;
