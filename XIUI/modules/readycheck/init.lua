--[[
* ReadyCheck module for XIUI.
* Adapted from the standalone ReadyCheck addon by Lydya.
*
* Usage (via XIUI command handler):
*   /readycheck              - Sends a ready check to party chat.
*   /readycheck sound <file> - Sets the sound file.
*   /readycheck volume <number>   - Sets the sound volume (0-150).
*
* Assets (sound/) live in modules/readycheck/ inside the XIUI folder.
]]--

local bit = require('bit')
local ui  = require('modules.readycheck.ui')
local soundPlayer = require('modules.readycheck.sound')

local M = {}

-- Path to this module's assets folder (sound/)
local MODULE_PATH = addon.path .. 'modules\\readycheck\\'

-- ── Marker strings ────────────────────────────────────────────────────────────
local TRIGGER_MSG = 'Ready Check!'
local YES_MSG     = 'Yes'
local NO_MSG      = 'No'

local DEFAULT_SOUND_FILE = 'ffxiv-notification.wav'

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

    prompt_center_next  = false,
    tracker_center_next = false,
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

local function is_exact_response(text, word)
    local _, body = parse_sender(strip_color_codes(text))
    local normalized = (body or strip_color_codes(text)):match('^%s*(.-)%s*$')
    return normalized:lower() == word:lower()
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

local function sound_path_from_filename(filename)
    if filename == nil or filename == '' then
        filename = DEFAULT_SOUND_FILE
    end
    if filename:find('[/\\]') then
        return filename
    end
    return MODULE_PATH .. 'sound\\' .. filename
end

local function filename_from_sound_path(path)
    if path == nil or path == '' then return DEFAULT_SOUND_FILE end
    return path:match('[^\\/]+$') or DEFAULT_SOUND_FILE
end

local function get_sound_path()
    if gConfig == nil then
        return sound_path_from_filename(DEFAULT_SOUND_FILE)
    end
    return sound_path_from_filename(gConfig.readyCheckSoundFile)
end

local function get_sound_volume()
    if gConfig == nil then return 50 end
    return math.max(0, math.min(150, gConfig.readyCheckSoundVolume or 50))
end

local function clamp_volume(volume)
    return math.max(0, math.min(150, math.floor(volume + (volume >= 0 and 0.5 or -0.5))))
end

local function sound_enabled_for_checker()
    return gConfig == nil or gConfig.readyCheckSoundOnChecker ~= false
end

local function sound_enabled_for_prompt()
    return gConfig == nil or gConfig.readyCheckSoundOnPrompt ~= false
end

local function play_readycheck_sound()
    soundPlayer.Play(get_sound_path(), get_sound_volume())
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
    state.tracker_center_next  = true
    state.checker_deadline     = os.clock() + 30
    state.checker_summary_sent = false
    local my_name = get_player_name()
    if my_name then
        update_member_status(my_name, 'ready')
    end
    if sound_enabled_for_checker() then play_readycheck_sound() end
    send_party(TRIGGER_MSG .. ' Are you ready? Answer Yes, No, or /')
end

-- ── Handlers table (allocated once) ──────────────────────────────────────────
local handlers = {
    answer_yes    = answer_yes,
    answer_no     = answer_no,
    close_checker = close_checker,
}

-- ── Public module API ─────────────────────────────────────────────────────────

function M.SetHidden(_hidden)
end

function M.DrawWindow(_settings)
    local now = os.clock()

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

    if state.prompt_open[1] and not state.prompt_answered
            and state.prompt_deadline ~= nil and now >= state.prompt_deadline then
        state.prompt_open[1]  = false
        state.prompt_deadline = nil
    end

    if state.checker_open[1] and not state.checker_summary_sent then
        if state.checker_deadline ~= nil and now >= state.checker_deadline then
            announce_ready_check_summary(true)
        elseif state.pending_count == 0 then
            state.checker_deadline = nil
            announce_ready_check_summary(false)
        end
    end

    ui.render(state, handlers)
    soundPlayer.Tick()

    if not state.checker_open[1] then
        close_checker()
    end
end

--@cmd /readycheck : Send a ready check to your party
--@cmd /readycheck sound <file> : Set the ready check sound file
--@cmd /readycheck volume <0-150> : Set the ready check sound volume
function M.HandleCommand(e)
    local args = e.command:args()
    if #args == 0 or args[1] ~= '/readycheck' then return false end

    if gConfig.showReadyCheck == false then
        print('[XIUI] Ready Check module is disabled. Enable it in the XIUI config menu.');
        return true;
    end

    if #args >= 2 and args[2]:lower() == 'volume' then
        if #args >= 3 then
            local volume = tonumber(args[3])
            if volume == nil then
                print('[XIUI] Ready Check Invalid volume. Usage: /readycheck volume <0-150>')
                return true
            end
            volume = clamp_volume(volume)
            if gConfig then
                gConfig.readyCheckSoundVolume = volume
                SaveSettingsOnly()
            end
            print(('[XIUI] Ready Check sound volume set to: %d%%'):format(volume))
        else
            print(('[XIUI] Ready Check current sound volume: %d%%'):format(get_sound_volume()))
            print('[XIUI] Ready Check usage: /readycheck volume <0-150>')
        end
        return true
    end

    if #args >= 2 and args[2]:lower() == 'sound' then
        if #args >= 3 then
            local path = table.concat(args, ' ', 3)
            if not path:find('[/\\]') then
                path = MODULE_PATH .. 'sound\\' .. path
            end
            if gConfig then
                gConfig.readyCheckSoundFile = filename_from_sound_path(path)
                SaveSettingsOnly()
            end
            print('[XIUI] Ready Check sound file set to: ' .. get_sound_path())
        else
            print('[XIUI] Ready Check current sound file: ' .. get_sound_path())
            print('[XIUI] Ready Check usage: /readycheck sound <filename or full path>')
        end
        return true
    end

    start_ready_check()
    return true
end

function M.HandleTextIn(e)
    if gConfig.showReadyCheck == false then return end

    local mode = bit.band(e.mode_modified or e.mode or 0, 0x000000FF)
    local raw   = e.message_modified or e.message or ''
    local clean      = strip_color_codes(raw)
    local is_trigger = clean:find(TRIGGER_MSG, 1, true) ~= nil
    -- "Yes"/"No" are plain words: only treat them as ready-check markers while a
    -- check is active, or a normal "yes" in party chat would be blocked.
    local rc_active  = state.checker_open[1] or state.prompt_open[1]
    local is_yes     = rc_active and not is_trigger and is_exact_response(raw, YES_MSG)
    local is_no      = rc_active and not is_trigger and not is_yes and is_exact_response(raw, NO_MSG)
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
            state.prompt_center_next = true
            state.prompt_deadline = os.clock() + 30
            state.prompt_sender   = resolve_sender_from_live_party(e.message or raw)
                                  or parse_sender(e.message or '')
                                  or parse_sender(raw)
            if sound_enabled_for_prompt() then play_readycheck_sound() end
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

function M.TestSound()
    soundPlayer.Play(get_sound_path(), get_sound_volume())
end

return M
