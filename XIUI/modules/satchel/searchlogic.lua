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

return M
