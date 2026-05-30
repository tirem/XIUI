--[[
 * Parse multi-line FFXI macros for icon/badge logic.
 * Primary icon priority (first matching line in macro, first 8 lines only):
 *   (1) /ws /ma /pet  — first among these, document order
 *   (2) /ja
 *   (3) /item /equip
 *   (4) any other /command with a payload (e.g. /wait 1) — "misc"
 * When primary is ws/ma/pet and any /ja line exists, the last /ja name is the corner badge (job ability).
]]

local M = {};

local function trim(s)
    if not s then return nil; end
    s = tostring(s):gsub('^%s+', ''):gsub('%s+$', '');
    return (s ~= '' and s) or nil;
end

--- Extract spell/ability name after leading /command (case-insensitive on the command).
local function extractNameAfterCommand(line, rawCmd)
    if not line or not rawCmd then return nil; end
    line = trim(line);
    if not line then return nil; end
    local cmd = line:match('^(/%S+)');
    if not cmd or cmd:lower() ~= rawCmd:lower() then return nil; end
    local tail = trim(line:sub(#cmd + 1));
    if not tail or tail == '' then return nil; end
    local quoted = tail:match('^"([^"]+)"');
    if quoted then return trim(quoted); end
    local unquoted = tail:match('^([^<\r\n]+)');
    if unquoted then
        return trim(unquoted:gsub('%s+$', ''));
    end
    return nil;
end

local function normalizeCmd(raw)
    if not raw then return nil; end
    local c = raw:lower();
    if c == '/weaponskill' then return '/ws'; end
    if c == '/magic' then return '/ma'; end
    return c;
end

-- Known action types; unknown /commands become 'misc' when a name/tail exists.
local function actionTypeForCmd(cmdLower)
    if not cmdLower then return nil; end
    if cmdLower == '/ws' then return 'ws'; end
    if cmdLower == '/ma' then return 'ma'; end
    if cmdLower == '/pet' then return 'pet'; end
    if cmdLower == '/ja' then return 'ja'; end
    if cmdLower == '/item' then return 'item'; end
    if cmdLower == '/equip' then return 'equip'; end
    return nil;
end

--- @return string|nil primaryType  ws ma pet ja item equip misc
--- @return string|nil primaryName
--- @return string|nil jaBadgeName  last /ja in macro when primary is ws, ma, or pet
function M.GetMacroPrimaryAndJaBadge(macroText)
    macroText = trim(macroText);
    if not macroText then
        return nil, nil, nil;
    end

    local entries = {};
    local jaNames = {};
    local lineIdx = 0;

    for line in macroText:gmatch('[^\r\n]+') do
        lineIdx = lineIdx + 1;
        if lineIdx > 8 then break; end

        local l = trim(line);
        if l and l:sub(1, 1) == '/' then
            local rawCmd = l:match('^(/%S+)');
            if rawCmd then
                local ncmd = normalizeCmd(rawCmd);
                local name = extractNameAfterCommand(l, rawCmd);
                if name and name ~= '' then
                    local atype = actionTypeForCmd(ncmd);
                    if not atype then
                        atype = 'misc';
                    end
                    table.insert(entries, {
                        line = lineIdx,
                        atype = atype,
                        name = name,
                    });
                    if atype == 'ja' then
                        table.insert(jaNames, name);
                    end
                end
            end
        end
    end

    if #entries == 0 then
        return nil, nil, nil;
    end

    -- Primary: /ws /ma /pet > /ja > /item /equip > misc (first line in each group wins).
    local function firstWhere(pred)
        for i = 1, #entries do
            local e = entries[i];
            if pred(e) then return e; end
        end
        return nil;
    end

    local best = firstWhere(function(e)
        return e.atype == 'ws' or e.atype == 'ma' or e.atype == 'pet';
    end);
    if not best then
        best = firstWhere(function(e) return e.atype == 'ja'; end);
    end
    if not best then
        best = firstWhere(function(e)
            return e.atype == 'item' or e.atype == 'equip';
        end);
    end
    if not best then
        best = firstWhere(function(e) return e.atype == 'misc'; end);
    end
    if not best then
        best = entries[1];
    end

    local jaBadge = nil;
    if best.atype == 'ws' or best.atype == 'ma' or best.atype == 'pet' then
        if #jaNames > 0 then
            jaBadge = jaNames[#jaNames];
            if jaBadge == best.name then
                -- Rare duplicate name; use previous /ja if any
                jaBadge = #jaNames > 1 and jaNames[#jaNames - 1] or nil;
            end
        end
    end

    return best.atype, best.name, jaBadge;
end

--- True when the macro has a bottom-right /ja badge (primary is /ws, /ma, or /pet and a /ja line exists).
function M.MacroHasJaBadgePair(macroText)
    local pType, _, jaBadge = M.GetMacroPrimaryAndJaBadge(macroText);
    if not jaBadge or jaBadge == '' then
        return false;
    end
    if pType == 'ws' or pType == 'ma' or pType == 'pet' then
        return true;
    end
    return false;
end

return M;
