--[[
* ReadyCheck module for XIUI.
* Adapted from the standalone ReadyCheck addon by Lydya.
*
* Usage (via XIUI command handler):
*   /readycheck              - Sends a ready check to party chat.
*   /readycheck config       - Opens the configuration UI (sound settings).
*   /readycheck sound <file> - Sets the sound file.
*
* Assets (icons/ and sound/) live in modules/readycheck/ inside the XIUI folder.
]]--

local bit = require('bit')
local ui  = require('modules.readycheck.ui')

local M = {}

-- Path to this module's assets folder (icons/, sound/, settings.txt)
local MODULE_PATH = addon.path .. 'modules\\readycheck\\'

-- ── Marker strings ────────────────────────────────────────────────────────────
local RC_PREFIX   = '[RC]'
local TRIGGER_MSG = RC_PREFIX .. 'check'
local YES_MSG     = RC_PREFIX .. 'yes'
local NO_MSG      = RC_PREFIX .. 'no'

-- ── Sound settings ────────────────────────────────────────────────────────────
local SOUND_FILE       = MODULE_PATH .. 'sound\\wow-readycheck.wav'
local SOUND_ON_CHECKER = true
local SOUND_ON_PROMPT  = true
local SETTINGS_FILE    = MODULE_PATH .. 'settings.txt'

-- Chat modes that carry party / alliance messages
local PARTY_MODES = { [13] = true, [215] = true }

-- ── Runtime state ─────────────────────────────────────────────────────────────
local state = {
    checker_open         = { false },
    checker_deadline     = nil,
    checker_summary_sent = false,
    party_members        = {},
    is_checker           = false,
    pending_count        = 0,

    prompt_open     = { false },
    prompt_answered = false,
    prompt_deadline = nil,
    prompt_sender   = nil,

    config_open = { false },
    cfg = {
        sound_files      = {},
        sound_sel_idx    = { 1 },
        sound_on_checker = { false },
        sound_on_prompt  = { false },
    },
}

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function get_player_name()
    local party = AshitaCore:GetMemoryManager():GetParty()
    if party == nil then return nil end
    local name = party:GetMemberName(0)
    if name == nil or name == '' then return nil end
    return name
end

local function collect_party_members()
    local members = {}
    local party = AshitaCore:GetMemoryManager():GetParty()
    if party == nil then return members end
    for i = 0, 17 do
        if party:GetMemberIsActive(i) == 1 then
            local name = party:GetMemberName(i)
            if name ~= nil and name ~= '' then
                table.insert(members, {
                    name       = name,
                    name_lower = name:lower(),
                    status     = nil,
                    job        = party:GetMemberMainJob(i),
                    slot       = i,
                    party      = math.floor(i / 6) + 1,
                })
            end
        end
    end
    return members
end

local function strip_color_codes(text)
    return (text:gsub('\x1E.', ''):gsub('\x1F.', ''))
end

local function parse_sender(text)
    local clean = strip_color_codes(text)
    clean = clean:gsub('^%s*|%d+|%s*', '')
    clean = clean:gsub('^%s*%[%d%d:%d%d:?%d?%d?%]%s*', '')

    local sender, body = clean:match('^<([%a][%w_%-]+)>%s*(.+)$')
    if sender then return sender, body end

    sender, body = clean:match('^%(([%a][%w_%-]+)%)%s*(.+)$')
    if sender then return sender, body end

    sender, body = clean:match('^([%a][%w_%-]+)%s*:%s*(.+)$')
    if sender then return sender, body end

    return nil, clean
end

local function clean_message(text)
    local s = strip_color_codes(text):lower()
    return s:gsub('^%s*|%d+|%s*', ''):gsub('^%s*%[%d%d:%d%d:?%d?%d?%]%s*', '')
end

local function update_member_status(name, status)
    local lower = name:lower()
    for _, member in ipairs(state.party_members) do
        if member.name_lower == lower then
            if member.status == nil then
                state.pending_count = state.pending_count - 1
            end
            member.status = status
            return
        end
    end
end

local function escape_lua_pattern(s)
    return (s:gsub('([%^%$%(%)%%%.%[%]%*%+%-%?])', '%%%1'))
end

local function resolve_sender_from_party(text)
    local clean = clean_message(text)
    for _, member in ipairs(state.party_members) do
        if clean:find('%f[%w]' .. escape_lua_pattern(member.name_lower) .. '%f[%W]') then
            return member.name
        end
    end
    return nil
end

local function resolve_sender_from_live_party(text)
    local clean = clean_message(text)
    local party = AshitaCore:GetMemoryManager():GetParty()
    if party == nil then return nil end
    for i = 0, 17 do
        if party:GetMemberIsActive(i) == 1 then
            local name = party:GetMemberName(i)
            if name and name ~= '' then
                if clean:find('%f[%w]' .. escape_lua_pattern(name:lower()) .. '%f[%W]') then
                    return name
                end
            end
        end
    end
    return nil
end

local function infer_single_pending_member()
    local my_lower = get_player_name()
    my_lower = my_lower and my_lower:lower() or nil
    local found, count = nil, 0
    for _, member in ipairs(state.party_members) do
        if member.status == nil and (my_lower == nil or member.name_lower ~= my_lower) then
            found  = member.name
            count  = count + 1
            if count > 1 then return nil end
        end
    end
    return found
end

local function send_party(msg)
    AshitaCore:GetChatManager():QueueCommand(-1, '/p ' .. msg)
end

local function load_settings()
    local f = io.open(SETTINGS_FILE, 'r')
    if f then
        for line in f:lines() do
            if line ~= '' then
                local key, val = line:match('^([%a][%w_]*)=(.-)$')
                if key == 'sound_file' and val then
                    SOUND_FILE = val
                elseif key == 'sound_on_checker' and val then
                    SOUND_ON_CHECKER = (val == 'true')
                elseif key == 'sound_on_prompt' and val then
                    SOUND_ON_PROMPT = (val == 'true')
                elseif not key then
                    SOUND_FILE = line
                end
            end
        end
        f:close()
    end
    state.cfg.sound_on_checker[1] = SOUND_ON_CHECKER
    state.cfg.sound_on_prompt[1]  = SOUND_ON_PROMPT
end

local function save_settings()
    local f = io.open(SETTINGS_FILE, 'w')
    if f then
        f:write('sound_file='       .. SOUND_FILE .. '\n')
        f:write('sound_on_checker=' .. tostring(SOUND_ON_CHECKER) .. '\n')
        f:write('sound_on_prompt='  .. tostring(SOUND_ON_PROMPT)  .. '\n')
        f:close()
    end
end

local function play_readycheck_sound()
    ashita.misc.play_sound(SOUND_FILE)
end

local function scan_sound_files()
    local sound_dir = MODULE_PATH .. 'sound\\'
    local files = ashita.fs.get_directory(sound_dir, '.*\\.wav$') or {}
    state.cfg.sound_files = files
    local current_name = SOUND_FILE:match('[^\\/]+$') or ''
    state.cfg.sound_sel_idx[1] = 1
    for i, fname in ipairs(files) do
        if fname:lower() == current_name:lower() then
            state.cfg.sound_sel_idx[1] = i
            break
        end
    end
end

local function get_selected_sound_path()
    local files = state.cfg.sound_files
    local idx   = state.cfg.sound_sel_idx[1]
    if files and files[idx] then
        return MODULE_PATH .. 'sound\\' .. files[idx]
    end
    return SOUND_FILE
end

local function open_config()
    state.cfg.sound_on_checker[1] = SOUND_ON_CHECKER
    state.cfg.sound_on_prompt[1]  = SOUND_ON_PROMPT
    scan_sound_files()
    state.config_open[1] = true
end

local function save_config()
    SOUND_FILE       = get_selected_sound_path()
    SOUND_ON_CHECKER = state.cfg.sound_on_checker[1]
    SOUND_ON_PROMPT  = state.cfg.sound_on_prompt[1]
    save_settings()
    print('[ReadyCheck] Settings saved.')
end

local function test_config_sound()
    ashita.misc.play_sound(get_selected_sound_path())
end

local function everyone_answered()
    return state.pending_count == 0
end

local function announce_ready_check_summary(mark_unanswered)
    if state.checker_summary_sent then return end
    local names = {}
    for _, member in ipairs(state.party_members) do
        if mark_unanswered and member.status == nil then
            member.status = 'not_ready'
        end
        if member.status ~= 'ready' then
            names[#names + 1] = member.name
        end
    end
    if #names == 0 then
        send_party('Players not ready: none')
    else
        send_party('Players not ready: ' .. table.concat(names, ', '))
    end
    state.checker_summary_sent = true
end

local function close_checker()
    state.checker_open[1]      = false
    state.is_checker           = false
    state.party_members        = {}
    state.checker_deadline     = nil
    state.checker_summary_sent = false
    state.pending_count        = 0
end

local function answer_yes()
    state.prompt_answered = true
    state.prompt_open[1]  = false
    state.prompt_deadline = nil
    send_party(YES_MSG)
end

local function answer_no()
    state.prompt_answered = true
    state.prompt_open[1]  = false
    state.prompt_deadline = nil
    send_party(NO_MSG)
end

local function start_ready_check()
    state.is_checker           = true
    state.party_members        = collect_party_members()
    state.pending_count        = #state.party_members
    state.checker_open[1]      = true
    state.checker_deadline     = os.clock() + 30
    state.checker_summary_sent = false
    local my_name = get_player_name()
    if my_name then
        update_member_status(my_name, 'ready')
    end
    if SOUND_ON_CHECKER then play_readycheck_sound() end
    send_party(TRIGGER_MSG .. ' Are you ready? Answer Yes, No or /')
end

-- ── Handlers table (allocated once) ──────────────────────────────────────────
local handlers = {
    answer_yes        = answer_yes,
    answer_no         = answer_no,
    close_checker     = close_checker,
    open_config       = open_config,
    save_config       = save_config,
    test_config_sound = test_config_sound,
    scan_sound_files  = scan_sound_files,
}

-- ── Public module API ─────────────────────────────────────────────────────────

--- Called by the module registry to show/hide this module.
--- ReadyCheck has no persistent fonts, so nothing needs to be hidden here.
function M.SetHidden(hidden)
end

--- Called once after XIUI settings are loaded.
function M.Initialize()
    load_settings()
end

--- Called every frame by the XIUI module registry (via RenderModule).
--- Handles timeout logic and delegates rendering to ui.lua.
function M.DrawWindow(_settings)
    local now = os.clock()

    -- Refresh job indices for members whose job was 0 at snapshot time.
    if state.checker_open[1] then
        local party = AshitaCore:GetMemoryManager():GetParty()
        if party then
            for i = 1, #state.party_members do
                local m = state.party_members[i]
                if (m.job == nil or m.job == 0) and m.slot then
                    local j = party:GetMemberMainJob(m.slot)
                    if j and j > 0 then m.job = j end
                end
            end
        end
    end

    -- Auto-close prompt on timeout.
    if state.prompt_open[1] and not state.prompt_answered
            and state.prompt_deadline ~= nil and now >= state.prompt_deadline then
        state.prompt_open[1]  = false
        state.prompt_deadline = nil
    end

    -- Checker timeout / all-answered summary.
    if state.checker_open[1] and not state.checker_summary_sent then
        if state.checker_deadline ~= nil and now >= state.checker_deadline then
            announce_ready_check_summary(true)
        elseif everyone_answered() then
            state.checker_deadline = nil
            announce_ready_check_summary(false)
        end
    end

    ui.render(state, handlers)

    if not state.checker_open[1] then
        close_checker()
    end
end

--- Called by XIUI's command event handler.
--- Returns true if the command was consumed (so the caller can set e.blocked).
function M.HandleCommand(e)
    local args = e.command:args()
    if #args == 0 or args[1] ~= '/readycheck' then return false end

    if gConfig.showReadyCheck == false then
        print('[XIUI] Ready Check module is disabled. Enable it in the XIUI config menu.');
        return true;
    end

    if #args >= 2 and args[2]:lower() == 'sound' then
        if #args >= 3 then
            local path = table.concat(args, ' ', 3)
            if not path:find('[/\\]') then
                path = MODULE_PATH .. 'sound\\' .. path
            end
            SOUND_FILE = path
            save_settings()
            print('[ReadyCheck] Sound file set to: ' .. SOUND_FILE)
        else
            print('[ReadyCheck] Current sound file: ' .. SOUND_FILE)
            print('[ReadyCheck] Usage: /readycheck sound <filename or full path>')
        end
        return true
    end

    start_ready_check()
    return true
end

--- Called by XIUI's text_in event handler.
function M.HandleTextIn(e)
    -- When the module is disabled, let all messages through unblocked.
    if gConfig.showReadyCheck == false then return end

    local mode = bit.band(e.mode_modified or e.mode or 0, 0x000000FF)
    local raw   = e.message_modified or e.message or ''
    local clean      = strip_color_codes(raw)
    local is_trigger = clean:find(TRIGGER_MSG, 1, true) ~= nil
    local is_yes     = not is_trigger and clean:find(YES_MSG, 1, true) ~= nil
    local is_no      = not is_trigger and not is_yes and clean:find(NO_MSG, 1, true) ~= nil
    local is_marker  = is_trigger or is_yes or is_no

    local is_manual_yes = false
    local is_manual_no  = false
    if not is_marker and PARTY_MODES[mode] and state.checker_open[1] then
        local normalized = clean_message(raw):match('^%s*(.-)%s*$')
        if normalized:match('yes%s*$') or normalized:match('^yes%s*$') then
            is_manual_yes = true
        elseif normalized:match('no%s*$') or normalized:match('^no%s*$') then
            is_manual_no = true
        elseif normalized:match('[/\\]%s*$') then
            is_manual_yes = true
        end
    end

    if not PARTY_MODES[mode] and not is_marker then return end

    if is_marker then e.blocked = true end

    if is_trigger then
        if not state.is_checker then
            state.prompt_answered = false
            state.prompt_open[1]  = true
            state.prompt_deadline = os.clock() + 30
            state.prompt_sender   = resolve_sender_from_live_party(e.message or raw)
                                  or parse_sender(e.message or '')
                                  or parse_sender(raw)
            if SOUND_ON_PROMPT then play_readycheck_sound() end
        end
        return
    end

    if not state.checker_open[1] then return end

    if is_yes or is_no or is_manual_yes or is_manual_no then
        local sender = parse_sender(raw) or resolve_sender_from_party(raw) or resolve_sender_from_live_party(raw)
        if (is_manual_yes or is_manual_no) and not sender then
            if e.sender_index and type(e.sender_index) == 'number' then
                local party = AshitaCore:GetMemoryManager():GetParty()
                if party and party:GetMemberIsActive(e.sender_index) == 1 then
                    local name = party:GetMemberName(e.sender_index)
                    if name and name ~= '' then sender = name end
                end
            end
        end
        if (is_manual_yes or is_manual_no) and not sender then
            sender = infer_single_pending_member()
        end
        if sender then
            update_member_status(sender, (is_yes or is_manual_yes) and 'ready' or 'not_ready')
        end
    end
end

-- ── Config UI accessors (used by config/readycheck.lua) ───────────────────────

--- Returns the sound file list and the current selection index table {[1]=idx}.
function M.GetSoundFileList()
    if #state.cfg.sound_files == 0 then
        scan_sound_files()
    end
    return state.cfg.sound_files, state.cfg.sound_sel_idx
end

--- Returns the ImGui bool-table for the "sound on checker" checkbox.
function M.GetSoundOnCheckerFlag()
    return state.cfg.sound_on_checker
end

--- Returns the ImGui bool-table for the "sound on prompt" checkbox.
function M.GetSoundOnPromptFlag()
    return state.cfg.sound_on_prompt
end

--- Sync and persist the current config UI state to disk.
function M.SaveSettings()
    save_config()
end

--- Re-scan the sound folder (e.g. after the user added a file).
function M.ScanSoundFiles()
    scan_sound_files()
end

--- Play a preview of the currently selected sound file.
function M.TestSound()
    test_config_sound()
end

return M
