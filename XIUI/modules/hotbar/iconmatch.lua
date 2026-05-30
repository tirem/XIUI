--[[
 * Shared heuristics for matching a user action name to an icon label / filename.
 * Avoids loose substring hits (e.g. unrelated abilities) while allowing spaces/case variants.
]]--

local M = {};

local function normalizeKey(s)
    if not s then return ''; end
    return tostring(s):lower():gsub('[^a-z0-9]', '');
end

--- True if action name and candidate icon name are the "same" or a strong alias (prefix / contained).
---@param userActionName string What the user typed (/ma, /pet, custom icon filename stem, etc.)
---@param candidateIconName string Display name of a custom icon entry
---@return boolean
function M.IsDecentIconNameMatch(userActionName, candidateIconName)
    local a = normalizeKey(userActionName);
    local b = normalizeKey(candidateIconName);
    if a == '' or b == '' then
        return false;
    end
    if a == b then
        return true;
    end

    local short, long = a, b;
    local iconNameIsShorter = false;
    if #a > #b then
        short, long = b, a;
        iconNameIsShorter = true;  -- short = icon key, long = user action
    end

    -- Containment: only when the shared token is long enough (avoids "arm", "ing", etc.)
    if #short >= 6 and long:find(short, 1, true) then
        -- Reject weak tail-of-compound matches: e.g. icon "Attack" vs ability "Sneak Attack"
        -- ("attack" is a suffix of "sneakattack" but is not a good match for the full name).
        if iconNameIsShorter then
            local pos = long:find(short, 1, true);
            if pos and pos > 1 and pos + #short - 1 == #long then
                if #short < 9 and #long > #short + 4 then
                    return false;
                end
            end
        end
        return (#short / #long) >= 0.35;
    end

    -- Prefix (one string starts with the other), min 5 chars on the shorter side
    if #short >= 5 then
        if long:sub(1, #short) == short then
            return (#short / #long) >= 0.45;
        end
        if short:sub(1, #long) == long then
            return (#long / #short) >= 0.45;
        end
    end

    return false;
end

function M.NormalizeIconKey(s)
    return normalizeKey(s);
end

--- Higher score = better match for ranking fuzzy icon lists (exact > full embed > other).
function M.MatchQualityScore(userActionName, candidateIconName)
    local a = normalizeKey(userActionName);
    local b = normalizeKey(candidateIconName);
    if a == '' or b == '' then
        return 0;
    end
    if a == b then
        return 1000000;
    end
    -- Icon filename contains the full normalized action (e.g. sneakattack in sneakattack_icon_ffxiv)
    if #a >= 6 and b:find(a, 1, true) then
        return 500000 + #a * 1000 + #b;
    end
    -- User action contains full icon stem (short icon name, longer filenames)
    if #b >= 6 and a:find(b, 1, true) then
        return 300000 + #b * 1000 + #a;
    end
    return 10000;
end

return M;
