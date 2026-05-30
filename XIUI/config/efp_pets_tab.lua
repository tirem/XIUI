--[[
* Edit Full Palette: Pets tab - pick a pet family, then a concrete pet key, for editing petpalette:* crossbar data.
* Lists are profile-wide (not tied to current main job): each family uses the class-appropriate key set.
* ASCII labels only (game font).
]]--

local imgui = require('imgui');
local components = require('config.components');
local petreg = require('modules.hotbar.petregistry');

local M = {};

local T_AVATARS = 1;
local T_ELEMENTALS = 2;
local T_BEASTS = 3;
local T_WYVERN = 4;
local T_PUPPET = 5;

M.state = {
    typeTab = T_AVATARS,
    subIdx = 1,
};

M._curList = {};

function M.resetState()
    M.state.typeTab = T_AVATARS;
    M.state.subIdx = 1;
    M._curList = {};
end

local excl = petreg.PETBAR_EXCLUDED_STORAGE_KEYS;

local function jobIdForFamilyTab(typeTab)
    if typeTab == T_AVATARS or typeTab == T_ELEMENTALS then
        return petreg.JOB_SMN;
    end
    if typeTab == T_BEASTS then
        return petreg.JOB_BST;
    end
    if typeTab == T_WYVERN then
        return petreg.JOB_DRG;
    end
    if typeTab == T_PUPPET then
        return petreg.JOB_PUP;
    end
    return petreg.JOB_SMN;
end

local function buildListForType(typeTab)
    local j = jobIdForFamilyTab(typeTab);
    local all = petreg.GetAvailablePetKeys(j) or {};
    local out = {};
    local function addKey(k, label)
        if not k then
            return;
        end
        if excl and excl[k] then
            return;
        end
        table.insert(out, { key = k, label = label or petreg.GetDisplayNameForKey(k) });
    end
    for _, k in ipairs(all) do
        if typeTab == T_AVATARS then
            if k:find('^avatar:') then
                addKey(k);
            end
        elseif typeTab == T_ELEMENTALS then
            if k:find('^spirit:') then
                addKey(k);
            end
        elseif typeTab == T_BEASTS then
            if k == 'jug' or k == 'charm' or k:find('^jug:') then
                addKey(k);
            end
        elseif typeTab == T_WYVERN then
            if k == 'wyvern' then
                addKey(k, 'Wyvern');
            end
        elseif typeTab == T_PUPPET then
            if k == 'automaton' then
                addKey(k, 'Automaton');
            end
        end
    end
    if typeTab == T_AVATARS or typeTab == T_ELEMENTALS then
        table.sort(out, function(a, b)
            return petreg.GetSmnPetKeyOrderWeight(a.key) < petreg.GetSmnPetKeyOrderWeight(b.key);
        end);
    else
        table.sort(out, function(a, b)
            return (a.label or '') < (b.label or '');
        end);
    end
    return out;
end

function M.rebuildListAndClamp()
    M._curList = buildListForType(M.state.typeTab);
    if #M._curList == 0 then
        M.state.subIdx = 1;
        return;
    end
    if M.state.subIdx > #M._curList then
        M.state.subIdx = #M._curList;
    end
    if M.state.subIdx < 1 then
        M.state.subIdx = 1;
    end
end

-- Full pet key suffix, e.g. "avatar:carbuncle" or "wyvern" (no "petpalette:" prefix).
function M.getPetKeyString()
    M.rebuildListAndClamp();
    if #M._curList == 0 then
        return 'wyvern';
    end
    return M._curList[M.state.subIdx].key;
end

local function efpTextWrapped(s, col)
    if not s then
        return;
    end
    if col and imgui.PushStyleColor and ImGuiCol_Text then
        imgui.PushStyleColor(ImGuiCol_Text, col);
    end
    if imgui.TextWrapped then
        imgui.TextWrapped(s);
    else
        imgui.Text(s);
    end
    if col and imgui.PopStyleColor then
        imgui.PopStyleColor(1);
    end
end

function M.draw(cross, disablePetTargetChange)
    M.rebuildListAndClamp();
    local jn = 'p';

    efpTextWrapped(
        'These layouts are stored per pet on this profile. When you have that pet out and a trigger row uses Pet Palette, your job crossbar uses these slots.',
        { 0.55, 0.53, 0.5, 1.0 }
    );
    imgui.Spacing();

    if disablePetTargetChange and imgui.BeginDisabled then
        imgui.BeginDisabled();
    end
    local tnames = { 'Avatars', 'Elementals', 'Beasts', 'Wyvern', 'Puppet' };
    imgui.TextColored({ 0.62, 0.6, 0.55, 1.0 }, 'Pet family:');
    imgui.SameLine(0, 8);
    for ti = 1, 5 do
        if ti > 1 then
            imgui.SameLine(0, 4);
        end
        local sel = (M.state.typeTab == ti);
        if components.DrawStyledTab(tnames[ti], 'efppty_' .. ti .. '_' .. jn, sel, nil, components.TAB_STYLE.smallHeight, components.TAB_STYLE.smallPadding, 'palette') then
            local prev = M.state.typeTab;
            M.state.typeTab = ti;
            if prev ~= ti then
                M.state.subIdx = 1;
            end
        end
    end
    M.rebuildListAndClamp();

    if #M._curList == 0 then
        efpTextWrapped('No pets in this family to edit (unexpected). Try another family tab.', { 0.85, 0.5, 0.45, 1.0 });
    else
        if M.state.subIdx < 1 or M.state.subIdx > #M._curList then
            M.state.subIdx = 1;
        end
        local cur = M._curList[M.state.subIdx];
        local preview = cur.label;
        do
            local aw, _ah = imgui.GetContentRegionAvail and imgui.GetContentRegionAvail() or 400, 0;
            local w = 280;
            if type(aw) == 'table' then
                w = math.max(200, (aw[1] or aw.x or w));
            elseif type(aw) == 'number' then
                w = math.max(200, aw);
            end
            imgui.SetNextItemWidth(math.min(w, 520));
        end
        if imgui.BeginCombo('Pet##efppcombo' .. jn, preview) then
            for i, row in ipairs(M._curList) do
                if imgui.Selectable(row.label, i == M.state.subIdx) then
                    M.state.subIdx = i;
                end
            end
            imgui.EndCombo();
        end
        efpTextWrapped(
            'Choose pet, then edit slots below. A few avatars are omitted where there is no pet bar to bind. Elementals (spirits) are separate from avatars in Pet Palette settings.',
            { 0.5, 0.5, 0.48, 1.0 }
        );
    end

    if cross then
        local n = 0;
        for _, m in ipairs({ 'L2', 'R2', 'L2x2', 'R2x2', 'L2R2', 'R2L2' }) do
            local s = cross.comboModeSettings and cross.comboModeSettings[m];
            if s and s.petAware == true then
                n = n + 1;
            end
        end
        efpTextWrapped(
            string.format('Pet Palette segments on in Slots: %d (turn on more there to see more rows in this list).', n),
            { 0.55, 0.53, 0.48, 1.0 }
        );
    end
    if disablePetTargetChange and imgui.EndDisabled then
        imgui.EndDisabled();
    end
    if disablePetTargetChange then
        efpTextWrapped('Apply or Undo to change which pet you are editing.', { 0.7, 0.55, 0.3, 1.0 });
    end
end

return M;
