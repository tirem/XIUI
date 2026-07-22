--[[
    Satchel item search helpers — abbreviation aliases and word-start blob matching.
]]--

local M = {}

M.TWO_HAND_SKILLS = {
    [1] = true,  -- Hand-to-Hand
    [4] = true,  -- Great Sword
    [6] = true,  -- Great Axe
    [7] = true,  -- Scythe
    [8] = true,  -- Polearm
    [10] = true, -- Great Katana
    [12] = true, -- Staff
}

M.ONE_HAND_SKILLS = {
    [2] = true,  -- Dagger
    [3] = true,  -- Sword
    [5] = true,  -- Axe
    [9] = true,  -- Katana
    [11] = true, -- Club
}

M.WEAPON_ALIAS_SKILLS = {
    gaxe = { 6 },
    ga = { 6 },
    gsword = { 4 },
    gs = { 4 },
    gk = { 10 },
    pole = { 8 },
    spear = { 8 },
    staff = { 12 },
    staves = { 12 },
    mm = { 26 },
    archery = { 25 },
    throw = { 27 },
    throwing = { 27 },
    h2h = { 1 },
    hth = { 1 },
    hh = { 1 },
}

M.WEAPON_ALIAS_BLOB_TERMS = {
    pole = { 'polearm' },
    spear = { 'polearm', 'spear' },
    staves = { 'staff' },
    staff = { 'staff' },
    throw = { 'throwing' },
    throwing = { 'throwing' },
    h2h = { 'hand-to-hand', 'hand to hand' },
    hth = { 'hand-to-hand', 'hand to hand' },
    hh = { 'hand-to-hand', 'hand to hand' },
    gaxe = { 'great axe' },
    ga = { 'great axe' },
    gsword = { 'great sword' },
    gs = { 'great sword' },
    gk = { 'great katana' },
    mm = { 'marksmanship' },
    archery = { 'archery' },
}

-- Equip-slot search uses query_is('range') in itemlogic. Skip generic blob word-start
-- for "range" so it does not match "ranger" or "ranged attack".
M.BLOB_SKIP_QUERIES = {
    range = true,
}

-- Each group lists equivalent abbreviations and full names for the same stat/property.
local STAT_ALIAS_GROUPS = {
    { 'str', 'strength' },
    { 'dex', 'dexterity' },
    { 'vit', 'vitality' },
    { 'agi', 'agility' },
    { 'int', 'intelligence' },
    { 'mnd', 'mind' },
    { 'chr', 'charisma' },
    { 'hp' },
    { 'mp' },
    { 'att', 'atk', 'attack' },
    { 'def', 'defense', 'defence' },
    { 'acc', 'accuracy' },
    { 'eva', 'evasion' },
    { 'ratt', 'ratk', 'ranged attack' },
    { 'racc', 'ranged accuracy' },
    { 'macc', 'magic accuracy' },
    { 'mab', 'magic attack bonus' },
    { 'mdef', 'magic defense', 'magic defence' },
    { 'mdb', 'magic defense bonus', 'magic defence bonus' },
    { 'mdt', 'magic damage taken' },
    { 'pdt', 'physical damage taken' },
    { 'parry', 'parrying' },
    { 'guard', 'guarding' },
    { 'haste' },
    { 'refresh' },
    { 'regen' },
    { 'regain' },
    { 'stp', 'store tp' },
    { 'subtle blow' },
    { 'fast cast' },
    { 'crit', 'critical hit rate' },
    { 'critical hit damage' },
    { 'double attack' },
    { 'triple attack' },
    { 'wsd', 'weaponskill damage' },
    { 'enmity' },
    { 'snapshot' },
    { 'rapid shot' },
    { 'dual wield' },
    { 'martial arts' },
    { 'kick attacks' },
    { 'shield mastery' },
    { 'cure cast time', 'cure spellcasting time' },
    { 'enh. mag. eff. dur.', 'enhancing magic duration', 'enhancing mag. eff. dur.' },
}

M.STAT_ALIASES = {}
for _, group in ipairs(STAT_ALIAS_GROUPS) do
    for _, term in ipairs(group) do
        M.STAT_ALIASES[term] = group
    end
end

local function escape_pattern(text)
    return (text:gsub('[%%^$().%[%]*+%?-]', '%%%1'))
end

local function split_query_words(query)
    local words = {}
    for word in (query or ''):lower():gmatch('[%w%+%-]+') do
        words[#words + 1] = word
    end
    return words
end

local function collect_search_tokens(blob)
    local tokens = {}
    if type(blob) ~= 'string' or blob == '' then
        return tokens
    end

    local stripped = blob:lower()

    for quoted in stripped:gmatch('"([^"]-)"') do
        for word in quoted:gmatch('[%w%+%-]+') do
            tokens[#tokens + 1] = word
        end
    end

    stripped = stripped:gsub('"[^"]-"', ' ')

    for token in stripped:gmatch('[%w%+%-:%%.]+') do
        tokens[#tokens + 1] = token
    end

    return tokens
end

local function token_starts_with(token, prefix)
    if type(token) ~= 'string' or type(prefix) ~= 'string' or prefix == '' then
        return false
    end

    return token:find('^' .. escape_pattern(prefix:lower()), 1) ~= nil
end

local function tokens_have_word_start_sequence(tokens, words)
    if #words == 0 then
        return false
    end

    local word_index = 1
    for _, token in ipairs(tokens) do
        if token_starts_with(token, words[word_index]) then
            word_index = word_index + 1
            if word_index > #words then
                return true
            end
        end
    end

    return false
end

function M.blob_has_word_start(blob, query)
    if type(blob) ~= 'string' or blob == '' or type(query) ~= 'string' or query == '' then
        return false
    end

    local words = split_query_words(query)
    if #words == 0 then
        return false
    end

    local tokens = collect_search_tokens(blob)
    if #words == 1 then
        for _, token in ipairs(tokens) do
            if token_starts_with(token, words[1]) then
                return true
            end
        end
        return false
    end

    return tokens_have_word_start_sequence(tokens, words)
end

function M.collect_equivalent_queries(normalized, compact)
    local queries = {}
    local seen = {}

    local function add(query)
        if type(query) ~= 'string' then
            return
        end

        query = query:lower()
        if query == '' or seen[query] then
            return
        end

        seen[query] = true
        queries[#queries + 1] = query
    end

    local function add_group_for(key)
        local group = M.STAT_ALIASES[key]
        if not group then
            return
        end

        for _, term in ipairs(group) do
            add(term)
        end
    end

    add(normalized)
    if compact ~= normalized then
        add(compact)
    end

    add_group_for(normalized)
    add_group_for(compact)

    return queries
end

function M.get_weapon_skill(item, read_number_field)
    if not item then
        return nil
    end

    if read_number_field then
        local skill = read_number_field(item, 'Skill')
        if skill then
            return skill
        end
    end

    return tonumber(item.Skill)
end

function M.matches_weapon_alias(item, normalized, compact, read_number_field)
    local skill = M.get_weapon_skill(item, read_number_field)
    if not skill then
        return false
    end

    if normalized == '2h' or compact == '2h' then
        return M.TWO_HAND_SKILLS[skill] == true
    end

    if normalized == '1h' or compact == '1h' then
        return M.ONE_HAND_SKILLS[skill] == true
    end

    local alias_skills = M.WEAPON_ALIAS_SKILLS[normalized] or M.WEAPON_ALIAS_SKILLS[compact]
    if alias_skills then
        for _, alias_skill in ipairs(alias_skills) do
            if skill == alias_skill then
                return true
            end
        end
    end

    return false
end

function M.blob_matches_query(blob, normalized, compact)
    if type(blob) ~= 'string' or blob == '' then
        return false
    end

    local skip_generic_blob = M.BLOB_SKIP_QUERIES[normalized]
        or M.BLOB_SKIP_QUERIES[compact]

    if not skip_generic_blob then
        for _, query in ipairs(M.collect_equivalent_queries(normalized, compact)) do
            if M.blob_has_word_start(blob, query) then
                return true
            end
        end
    end

    local weapon_terms = M.WEAPON_ALIAS_BLOB_TERMS[normalized] or M.WEAPON_ALIAS_BLOB_TERMS[compact]
    if weapon_terms then
        for _, term in ipairs(weapon_terms) do
            if M.blob_has_word_start(blob, term) then
                return true
            end
        end
    end

    return false
end

-- Search match highlight (single AddRect per region — no animated dashes).
local imgui = require('imgui')

local SEARCH_HIGHLIGHT_COLOR = 0xFFD4AA44
local SEARCH_BORDER_THICKNESS = 2

local cached_border_u32 = nil
local cached_border_opacity = nil
local cached_inner_dim_u32 = nil
local cached_inner_dim_coverage = nil

function M.get_match_border_color_u32(opacity)
    opacity = opacity or 1
    if cached_border_u32 ~= nil and cached_border_opacity == opacity then
        return cached_border_u32
    end

    local color = SEARCH_HIGHLIGHT_COLOR
    local alpha = math.floor(bit.rshift(bit.band(color, 0xFF000000), 24) * opacity)
    local r = bit.rshift(bit.band(color, 0x00FF0000), 16) / 255
    local g = bit.rshift(bit.band(color, 0x0000FF00), 8) / 255
    local b = bit.band(color, 0x000000FF) / 255
    cached_border_u32 = imgui.GetColorU32({ r, g, b, alpha / 255 })
    cached_border_opacity = opacity
    return cached_border_u32
end

function M.get_match_inner_dim_u32(coverage)
    coverage = coverage or 0.7
    if cached_inner_dim_u32 ~= nil and cached_inner_dim_coverage == coverage then
        return cached_inner_dim_u32
    end

    cached_inner_dim_u32 = imgui.GetColorU32({ 0, 0, 0, 1.0 - coverage })
    cached_inner_dim_coverage = coverage
    return cached_inner_dim_u32
end

function M.draw_match_border_rect(draw_list, x, y, w, h, opacity)
    if not draw_list or not w or not h or w <= 0 or h <= 0 or (opacity or 1) <= 0.01 then
        return
    end

    local thickness = SEARCH_BORDER_THICKNESS
    local inset = thickness * 0.5
    x = x + inset
    y = y + inset
    w = w - thickness
    h = h - thickness
    if w <= 0 or h <= 0 then
        return
    end

    draw_list:AddRect(
        { x, y },
        { x + w, y + h },
        M.get_match_border_color_u32(opacity),
        0,
        0,
        thickness
    )
end

-- Profile search (lua / xml gear profiles).
local name_index = nil
local name_index_ready = false
local name_index_requested = false
local name_index_cursor = 0
local NAME_INDEX_MAX_ID = 65535
local profile_cache = {} -- path -> { size, ids }
local query_cache = {} -- cache_key -> { resolved, path, size, ids }

local function install_path()
    if not AshitaCore or not AshitaCore.GetInstallPath then
        return nil
    end
    return AshitaCore:GetInstallPath():gsub('[/\\]+$', '') .. '\\'
end

local function trim(text)
    if type(text) ~= 'string' then
        return ''
    end
    return text:match('^%s*(.-)%s*$') or ''
end

local function lower(text)
    return trim(text):lower()
end

-- Strip trailing dots from partial filenames (e.g. "drg." -> "drg").
local function normalize_profile_arg(arg)
    if type(arg) ~= 'string' then
        return nil
    end
    arg = trim(arg)
    if arg == '' then
        return nil
    end
    arg = arg:gsub('%.+$', '')
    if arg == '' then
        return nil
    end
    return arg
end

local function get_player_context()
    local mm = AshitaCore and AshitaCore:GetMemoryManager()
    if not mm then
        return nil
    end

    local party = mm:GetParty()
    local player = mm:GetPlayer()
    local entity = mm:GetEntity()
    local rm = AshitaCore:GetResourceManager()
    if not party or not player or not entity or not rm then
        return nil
    end

    local index = party:GetMemberTargetIndex(0)
    if not index then
        return nil
    end

    -- Same identity key as layoutstate (entity server id, not party API).
    local name = entity:GetName(index) or party:GetMemberName(0)
    local server_id = tonumber(entity:GetServerId(index)) or 0
    if type(name) ~= 'string' or name == '' or server_id <= 0 then
        return nil
    end

    local job_id = tonumber(player:GetMainJob()) or 0
    local job_abbr = ''
    local ok, job_str = pcall(function()
        return rm:GetString('jobs.names_abbr', job_id)
    end)
    if ok and type(job_str) == 'string' then
        job_abbr = job_str:gsub('%z', ''):gsub('%s+', '')
    end
    if job_abbr == '' then
        return nil
    end

    return {
        name = name,
        server_id = server_id,
        job_abbr = job_abbr,
        char_dir = ('%s_%d'):format(name, server_id),
    }
end

function M.is_profile_query(query)
    local q = lower(query)
    if q == '' then
        return false
    end
    local mode = q:match('^(%S+)')
    return mode == 'lua' or mode == 'xml'
end

function M.parse_query(query)
    local q = trim(query or '')
    local mode, rest = q:match('^(%S+)%s*(.-)%s*$')
    if not mode then
        return nil, nil
    end
    mode = mode:lower()
    if mode ~= 'lua' and mode ~= 'xml' then
        return nil, nil
    end
    rest = normalize_profile_arg(rest)
    return mode, rest
end

local function list_dirs(path)
    local entries = ashita.fs.get_directory(path)
    if type(entries) ~= 'table' then
        return {}
    end
    return entries
end

local function file_exists(path)
    return type(path) == 'string' and path ~= '' and ashita.fs.exists(path) == true
end

local function file_size(path)
    local f = io.open(path, 'rb')
    if not f then
        return nil
    end
    local size = f:seek('end')
    f:close()
    return size
end

local function read_file(path)
    local f = io.open(path, 'rb')
    if not f then
        return nil
    end
    local data = f:read('*a')
    f:close()
    return data
end

local function append_ext(name, ext)
    if type(name) ~= 'string' or name == '' then
        return name
    end
    local lower_name = name:lower()
    if lower_name:sub(-#ext) == ext:lower() then
        return name
    end
    return name .. ext
end

local function find_file_ci(dir, filename)
    if not file_exists(dir) then
        return nil
    end

    local want = lower(filename)
    local direct = dir .. filename
    if file_exists(direct) then
        return direct
    end

    local entries = list_dirs(dir)
    local prefix_match = nil
    local prefix_len = math.huge
    local allow_prefix = want:find('%.', 1, true) ~= nil

    for _, entry in ipairs(entries) do
        local entry_l = lower(entry)
        local path = dir .. entry
        if file_exists(path) then
            if entry_l == want then
                return path
            end
            if allow_prefix and entry_l:sub(1, #want) == want and #entry_l < prefix_len then
                prefix_match = path
                prefix_len = #entry_l
            end
        end
    end

    return prefix_match
end

local function prefer_candidate(candidates)
    if #candidates == 0 then
        return nil
    end
    if #candidates == 1 then
        return candidates[1]
    end

    local best = candidates[1]
    local best_size = file_size(best) or 0
    for i = 2, #candidates do
        local size = file_size(candidates[i]) or 0
        if size >= best_size then
            best = candidates[i]
            best_size = size
        end
    end
    return best
end

local function resolve_lua_path(player, arg)
    local root = install_path()
    if not root or not player then
        return nil
    end

    local filename = arg and append_ext(arg, '.lua') or (player.job_abbr .. '.lua')
    local addons_root = root .. 'config\\addons\\'
    local want_char = lower(player.char_dir)
    local candidates = {}

    for _, addon_folder in ipairs(list_dirs(addons_root)) do
        local addon_path = addons_root .. addon_folder .. '\\'
        -- Match {Name}_{Id}\ case-insensitively among direct children only.
        for _, child in ipairs(list_dirs(addon_path)) do
            if lower(child) == want_char then
                local char_dir = addon_path .. child .. '\\'
                local path = find_file_ci(char_dir, filename)
                if path then
                    candidates[#candidates + 1] = path
                end
            end
        end
    end

    return prefer_candidate(candidates)
end

local function resolve_xml_path(player, arg)
    local root = install_path()
    if not root or not player then
        return nil
    end

    local filename
    if not arg then
        filename = ('%s_%s.xml'):format(player.name, player.job_abbr)
    elseif not arg:find('_', 1, true) then
        filename = ('%s_%s.xml'):format(player.name, arg)
    else
        filename = append_ext(arg, '.xml')
    end

    local config_root = root .. 'config\\'
    local candidates = {}

    for _, folder in ipairs(list_dirs(config_root)) do
        local dir = config_root .. folder .. '\\'
        local path = find_file_ci(dir, filename)
        if path then
            candidates[#candidates + 1] = path
        end
    end

    return prefer_candidate(candidates)
end

local function strip_lua_comments(text)
    text = text:gsub('%-%-%[%[.-%]%]', ' ')
    text = text:gsub('%-%-[^\r\n]*', ' ')
    return text
end

local function unescape_lua_string(text)
    return (text:gsub('\\(.)', '%1'))
end

-- Extract quoted Lua strings, honoring \' and \".
local function each_lua_string(text, callback)
    local i = 1
    local n = #text
    while i <= n do
        local c = text:sub(i, i)
        if c == "'" or c == '"' then
            local quote = c
            local j = i + 1
            local buf = {}
            while j <= n do
                local ch = text:sub(j, j)
                if ch == '\\' and j < n then
                    buf[#buf + 1] = text:sub(j, j + 1)
                    j = j + 2
                elseif ch == quote then
                    callback(unescape_lua_string(table.concat(buf)))
                    i = j + 1
                    break
                else
                    buf[#buf + 1] = ch
                    j = j + 1
                end
            end
            if j > n then
                break
            end
        else
            i = i + 1
        end
    end
end

local function collect_lua_names(text)
    local names = {}
    local seen = {}

    local function add_name(name)
        name = trim(name)
        if name == '' or name:sub(1, 1) == '$' then
            return
        end
        -- Skip obvious non-items (paths, requires).
        if name:find('[/\\]') or name:find('%.lua$') or name:find('^lib/') then
            return
        end
        local key = lower(name)
        if seen[key] then
            return
        end
        seen[key] = true
        names[#names + 1] = name
    end

    -- All quoted strings, including escaped apostrophes (Terra\'s Staff).
    each_lua_string(text, function(name)
        add_name(name)
    end)

    return names
end

local XML_EQUIP_TAGS = {
    main = true, sub = true, range = true, ammo = true,
    head = true, body = true, hands = true, legs = true, feet = true,
    neck = true, waist = true, ear1 = true, ear2 = true,
    ring1 = true, ring2 = true, rring = true, lring = true, back = true,
}

local function looks_like_item_name(text)
    text = trim(text)
    if text == '' or text:sub(1, 1) == '$' then
        return false
    end
    if text:find('[<>]') then
        return false
    end
    if #text < 2 or #text > 64 then
        return false
    end
    -- Reject pure numbers / booleans / short codes.
    if text:match('^[%d%.]+$') then
        return false
    end
    if text == 'true' or text == 'false' then
        return false
    end
    return true
end

local function collect_xml_names(text)
    local names = {}
    local seen = {}

    local function add_name(name)
        name = trim(name)
        if not looks_like_item_name(name) then
            return
        end
        local key = lower(name)
        if seen[key] then
            return
        end
        seen[key] = true
        names[#names + 1] = name
    end

    for tag, value in text:gmatch('<([%w_]+)>([^<]*)</[%w_]+>') do
        local tag_l = tag:lower()
        if XML_EQUIP_TAGS[tag_l] then
            add_name(value)
        elseif tag_l == 'var' and looks_like_item_name(value) then
            -- Staff/obi style tables often use <var>Item Name</var>.
            if value:find('%s') or value:find('%+') or value:match('^[A-Z]') then
                add_name(value)
            end
        end
    end

    return names
end

local function coerce_name(raw_name, item)
    if type(raw_name) ~= 'string' or raw_name == '' then
        return nil
    end

    local encoding = _G.encoding
    local text = raw_name
    if encoding and encoding.ShiftJIS_To_UTF8 then
        local ok, converted = pcall(encoding.ShiftJIS_To_UTF8, encoding, text, true)
        if ok and type(converted) == 'string' and converted ~= '' then
            text = converted
        end
    end
    text = text:gsub('%s+', ' ')
    text = trim(text)
    if text == '' then
        return nil
    end
    return text
end

-- Index a single id into name_index. Kept tiny so the incremental builder and
-- any synchronous fallback share one code path.
local function index_item_name(rm, item_id)
    local ok, item = pcall(rm.GetItemById, rm, item_id)
    if not (ok and item) then
        return
    end

    local fields = {}
    if item.Name and item.Name[1] then
        fields[#fields + 1] = item.Name[1]
    end
    if item.LogNameSingular and item.LogNameSingular[1] then
        fields[#fields + 1] = item.LogNameSingular[1]
    end
    if item.LogNamePlural and item.LogNamePlural[1] then
        fields[#fields + 1] = item.LogNamePlural[1]
    end

    for _, field in ipairs(fields) do
        local name = coerce_name(field, item)
        if name then
            local key = lower(name)
            if not name_index[key] then
                name_index[key] = item_id
            end
        end
    end
end

-- Returns the (possibly partial) name index and flags it as needed so the
-- incremental builder starts running from tick_name_index.
local function ensure_name_index()
    name_index_requested = true
    if not name_index then
        name_index = {}
    end
    return name_index
end

-- Build the item-name index in chunks so the first gear-profile search never
-- stalls the render thread. Returns true only on the frame the build completes,
-- so the caller can invalidate any partial search results that were cached.
function M.tick_name_index(budget)
    if name_index_ready or not name_index_requested then
        return false
    end

    local rm = AshitaCore and AshitaCore:GetResourceManager()
    if not rm then
        return false
    end

    if not name_index then
        name_index = {}
    end

    local stop = math.min(name_index_cursor + (budget or 3000), NAME_INDEX_MAX_ID)
    for item_id = name_index_cursor + 1, stop do
        index_item_name(rm, item_id)
    end
    name_index_cursor = stop

    if name_index_cursor >= NAME_INDEX_MAX_ID then
        name_index_ready = true
        return true
    end
    return false
end

local function resolve_names_to_ids(names)
    local index = ensure_name_index()
    local ids = {}
    for _, name in ipairs(names or {}) do
        local id = index[lower(name)]
        if id then
            ids[id] = true
        end
    end
    return ids
end

local function load_profile_ids(path, allow_cache)
    if not path then
        return {}
    end

    local size = file_size(path)
    if not size then
        return {}
    end

    if allow_cache then
        local cached = profile_cache[path]
        if cached and cached.size == size and cached.ids then
            return cached.ids
        end
    end

    local data = read_file(path)
    if not data then
        return {}
    end

    local names
    if path:lower():sub(-4) == '.lua' then
        names = collect_lua_names(strip_lua_comments(data))
    else
        names = collect_xml_names(data)
    end

    local ids = resolve_names_to_ids(names)
    if allow_cache then
        profile_cache[path] = { size = size, ids = ids }
    end
    return ids
end

local function lookup_query_cache(cache_key)
    local cached = query_cache[cache_key]
    if not cached or not cached.resolved then
        return nil
    end
    if not cached.path then
        return cached.ids or {}
    end
    if file_size(cached.path) == cached.size then
        return cached.ids
    end
    return nil
end

local function store_query_cache(cache_key, path, ids)
    query_cache[cache_key] = {
        resolved = true,
        path = path,
        size = path and file_size(path) or 0,
        ids = ids,
    }
end

function M.get_match_ids(query)
    local mode, arg = M.parse_query(query)
    if not mode then
        return {}
    end

    local player = get_player_context()
    if not player then
        return {}
    end

    -- Profile resolution needs the full item-name index. Kick off the (chunked)
    -- build and, while it is still running, resolve against the partial index but
    -- skip caching so results refresh once the build completes.
    ensure_name_index()
    local allow_cache = name_index_ready

    local cache_key = table.concat({
        mode,
        arg or '',
        player.name,
        tostring(player.server_id),
        player.job_abbr,
    }, '\0')

    if allow_cache then
        local cached_ids = lookup_query_cache(cache_key)
        if cached_ids then
            return cached_ids
        end
    end

    local path
    if mode == 'lua' then
        path = resolve_lua_path(player, arg)
    else
        path = resolve_xml_path(player, arg)
    end

    local ids = load_profile_ids(path, allow_cache)
    if allow_cache then
        store_query_cache(cache_key, path, ids)
    end
    return ids
end

function M.matches_item_id(item_id, query)
    item_id = tonumber(item_id)
    if not item_id or item_id <= 0 then
        return false
    end
    local ids = M.get_match_ids(query)
    return ids[item_id] == true
end

return M

