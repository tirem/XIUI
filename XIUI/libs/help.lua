--[[
* XIUI Command Help
*
* Renders a small ImGui window listing XIUI's slash commands. The list is built
* by scanning every .lua file under the addon (vendored submodules excluded) for
* opt-in markers, so it stays in sync automatically. Mark a command, anywhere,
* with a line whose first non-space content is:
*
*     --@cmd <usage> : <description>     (description optional)
*
* Omit the marker to keep a command (e.g. internal/debug ones) hidden.
]]--

local imgui = require('imgui');
local components = require('config.components');

local M = {};

local COLOR_CMD  = components.TAB_STYLE.gold;
local COLOR_DESC = { 0.62, 0.64, 0.68, 1.0 };

local isOpen = { false };
local commands = {};

-- Pull `--@cmd` markers out of a single file into the list.
local function scan_file(path, list)
    local f = io.open(path, 'r');
    if not f then return; end
    for line in f:lines() do
        local marker = line:match('^%s*%-%-@cmd%s+(.+)$');
        if marker then
            local usage, desc = marker:match('^(.-)%s*:%s*(.+)$');
            list[#list + 1] = { usage = usage or marker, desc = desc or '' };
        end
    end
    f:close();
end

-- Recursively scan a directory's .lua files (entries without an extension are
-- treated as subdirectories, mirroring how the rest of XIUI walks folders).
local function scan_dir(dir, list)
    for _, name in ipairs(ashita.fs.get_directory(dir, '.*') or {}) do
        if name:match('%.lua$') then
            scan_file(dir .. name, list);
        elseif name ~= 'submodules' and not name:match('%.') then
            scan_dir(dir .. name .. '\\', list);
        end
    end
end

-- Scan the whole addon for markers, returning a sorted { usage, desc } list.
-- Runs only when the window opens, so walking the tree is fine.
local function collect()
    local list = {};
    scan_dir(string.format('%saddons\\XIUI\\', AshitaCore:GetInstallPath()), list);
    table.sort(list, function(a, b) return a.usage < b.usage; end);
    return list;
end

-- Toggle the window; refresh the command list each time it opens.
function M.Toggle()
    isOpen[1] = not isOpen[1];
    if isOpen[1] then
        commands = collect();
    end
end

-- Per-frame render. Cheap no-op while closed.
function M.Draw()
    if not isOpen[1] then return; end

    imgui.SetNextWindowSize({ 440, 480 }, ImGuiCond_FirstUseEver);
    components.PushWindowStyle();
    if imgui.Begin('XIUI Commands##xiuiHelp', isOpen, ImGuiWindowFlags_None) then
        imgui.TextDisabled(string.format('%d commands', #commands));
        imgui.Separator();
        imgui.Spacing();

        for _, entry in ipairs(commands) do
            imgui.TextColored(COLOR_CMD, entry.usage);
            if entry.desc ~= '' then
                imgui.Indent(16);
                imgui.TextColored(COLOR_DESC, entry.desc);
                imgui.Unindent(16);
            end
            imgui.Spacing();
        end
    end
    imgui.End();
    components.PopWindowStyle();
end

return M;
