local profileManager = {};
local addonName = 'xiui';
local configPath = AshitaCore:GetInstallPath() .. '\\config\\addons\\' .. addonName .. '\\';
local profilesPath = configPath .. 'profiles\\';

-- Ensure directories exist
if (not ashita.fs.exists(configPath)) then
    ashita.fs.create_directory(configPath);
end
if (not ashita.fs.exists(profilesPath)) then
    ashita.fs.create_directory(profilesPath);
end

-- Robust serializer for Lua tables
local function Serialize(t)
    local function serialize_recursive(tbl, indent)
        local keys = {}
        for k in pairs(tbl) do table.insert(keys, k) end
        table.sort(keys, function(a, b)
            local ta, tb = type(a), type(b)
            if ta ~= tb then 
                -- Sort by type string representation
                return tostring(ta) < tostring(tb) 
            end
            if ta == 'number' then return a < b end
            if ta == 'string' then return a < b end
            return tostring(a) < tostring(b)
        end)

        local lines = {}
        local indentStr = string.rep("    ", indent)
        local nextIndentStr = string.rep("    ", indent + 1)

        lines[#lines + 1] = "{"
        
        for _, k in ipairs(keys) do
            local v = tbl[k]
            local keyStr
            if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                keyStr = k
            else
                -- Safe key serialization
                if type(k) == "string" then
                    keyStr = "[" .. string.format("%q", k) .. "]"
                elseif type(k) == "number" then
                    keyStr = "[" .. k .. "]"
                elseif type(k) == "boolean" then
                    keyStr = "[" .. tostring(k) .. "]"
                end
                -- Skip unsupported key types
            end

            if keyStr then
                local valStr
                if type(v) == "table" then
                    valStr = serialize_recursive(v, indent + 1)
                elseif type(v) == "string" then
                    valStr = string.format("%q", v)
                elseif type(v) == "number" then
                    valStr = tostring(v)
                elseif type(v) == "boolean" then
                    valStr = tostring(v)
                end
                -- Skip unsupported value types

                if valStr then
                    lines[#lines + 1] = nextIndentStr .. keyStr .. " = " .. valStr .. ","
                end
            end
        end
        
        lines[#lines + 1] = indentStr .. "}"
        return table.concat(lines, "\n")
    end

    return serialize_recursive(t, 0)
end

function profileManager.SaveTable(path, t)
    local f = io.open(path, "w");
    if (f) then
        f:write("return " .. Serialize(t) .. ";");
        f:close();
        return true;
    end
    return false;
end

function profileManager.LoadTable(path)
    if (not ashita.fs.exists(path)) then return nil; end
    local func, err = loadfile(path);
    if (func) then
        local success, result = pcall(func);
        if (success) then
            return result;
        else
            print(chat.header(addon.name):append(chat.message('Error executing profile: ')):append(chat.error(result)));
        end
    else
        print(chat.header(addon.name):append(chat.message('Error loading profile: ')):append(chat.error(err)));
    end
    return nil;
end



function profileManager.GetGlobalProfiles()
    local path = configPath .. 'profilelist.lua';
    local oldPath = configPath .. 'profiles.lua';
    
    -- Rename old profiles.lua if it exists and new one doesn't
    if (ashita.fs.exists(oldPath) and not ashita.fs.exists(path)) then
        local oldContent = profileManager.LoadTable(oldPath);
        if (oldContent) then
            profileManager.SaveTable(path, oldContent);
            os.remove(oldPath);
        end
    end

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
    local path = configPath .. 'profilelist.lua';
    return profileManager.SaveTable(path, profiles);
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
    local f = io.open(path, "w");
    if (f) then
        -- Wrap settings in userSettings to maintain compatibility
        local wrapper = { userSettings = settings };
        f:write("return " .. Serialize(wrapper) .. ";");
        f:close();
        return true;
    end
    return false;
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
    local iniPath = AshitaCore:GetInstallPath() .. '\\config\\imgui.ini';
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
