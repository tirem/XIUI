return function(MP)
    return function()
    if not MP.editingMacro then
        return;
    end

    if not MP.editorIconPrefsHydrated then
        MP.HydrateMacroEditorIconPrefs();
        MP.ValidateEditorCustomIconCategoryAgainstScan();
        MP.editorIconPrefsHydrated = true;
    end

    -- Legacy: `action` was set to the full multiline buffer; normalize to the parsed primary name.
    if MP.editingMacro.actionType == 'macro' and MP.editingMacro.macroText and MP.editingMacro.macroText ~= '' then
        local a = tostring(MP.editingMacro.action or '');
        local looksLikeFullMacro = (a:find('\n') or a:find('\r') or a:match('^%s*/'));
        if looksLikeFullMacro or a == '' then
            local mp = require('modules.hotbar.macroparse');
            local _, pName = mp.GetMacroPrimaryAndJaBadge(MP.editingMacro.macroText);
            if pName and pName ~= '' then
                MP.editingMacro.action = pName;
            end
        end
    end

    -- Initialize editor fields from editing macro
    MP.editorFields.actionType[1] = MP.FindIndex(MP.ACTION_TYPES, MP.editingMacro.actionType or 'ma');
    MP.editorFields.action[1] = MP.editingMacro.action or '';
    MP.editorFields.target[1] = MP.FindIndex(MP.TARGET_OPTIONS, MP.editingMacro.target or 't');
    MP.editorFields.displayName[1] = MP.editingMacro.displayName or '';
    MP.editorFields.equipSlot[1] = MP.FindIndex(MP.EQUIP_SLOTS, MP.editingMacro.equipSlot or 'main');
    MP.editorFields.macroText[1] = MP.editingMacro.macroText or '';
    MP.editorFields.recastSourceType[1] = MP.FindIndex(MP.RECAST_SOURCE_TYPES, MP.editingMacro.recastSourceType or 'none');
    MP.editorFields.recastSourceAction[1] = MP.editingMacro.recastSourceAction or '';

    local saveDisplayName = MP.M.GetEditorSaveDisplayName and MP.M.GetEditorSaveDisplayName() or nil;
    local titlePrefix = MP.isCreatingNew and 'Create Macro' or 'Edit Macro';
    local title;
    if saveDisplayName and saveDisplayName ~= '' then
        title = titlePrefix .. ' - ' .. saveDisplayName .. '###MacroEditor';
    else
        title = titlePrefix .. '###MacroEditor';
    end
    local isOpen = { true };

    -- Track whether the Slot Label is currently "auto" (same as action). This lets new selections refresh it.
    do
        local dn = (MP.editingMacro.displayName or '');
        local act = (MP.editingMacro.action or '');
        if dn ~= '' and act ~= '' and dn == act then
            MP.editorAutoLabel = dn;
        end
    end

    local function AutoSetDisplayName(newLabel)
        if not newLabel or newLabel == '' then return; end
        local current = (MP.editingMacro.displayName or '');
        if current == '' or (MP.editorAutoLabel and current == MP.editorAutoLabel) then
            MP.editingMacro.displayName = newLabel;
            MP.editorFields.displayName[1] = newLabel;
            MP.editorAutoLabel = newLabel;
        end
    end

    -- Pet commands follow "Saving To" + Avatar Filter in the editor, not the separate Macro Palette avatar.
    local function GetEditorPetJobId()
        if MP.editorPaletteKey and MP.EditorSaveKeyToJobId then
            local jid = MP.EditorSaveKeyToJobId(MP.editorPaletteKey);
            if jid then
                return jid;
            end
        end
        local viewedJobId = MP.selectedPaletteType;
        if type(viewedJobId) == 'number' then
            return viewedJobId;
        end
        return MP.playerdata.GetCacheJobId() or 0;
    end

    local function SmnAvatarNameFromEditorFilter(avatarList)
        if MP.petAvatarFilter <= 1 then
            return nil;
        end
        return avatarList[MP.petAvatarFilter - 1];
    end

    local function GetCurrentActionNameForIcon()
        local t = tostring(MP.editingMacro.actionType or '');
        if t == '' then return nil; end
        if t == 'macro' then return nil; end
        local name = tostring(MP.editingMacro.action or '');
        if name == '' then return nil; end
        return name;
    end

    -- Implicit auto-pick (no force): only when no icon is stored yet, and not already synced to MP.editorAutoIconKey.
    -- Matching MP.editorAutoIconKey means "already applied"; re-pick only via Sync (force=true) or first-open block.
    local function ShouldAllowImplicitAutoIconPick()
        local t = MP.editingMacro.customIconType;
        local id = MP.editingMacro.customIconId;
        local p = MP.editingMacro.customIconPath;
        local curKey = tostring(t or '') .. ':' .. tostring(id or '') .. ':' .. tostring(p or '');
        if MP.editorAutoIconKey and curKey == MP.editorAutoIconKey then
            return false;
        end
        if t == nil and id == nil and (p == nil or p == '') then
            return true;
        end
        return false;
    end

    local function SetIconSpell(spellId)
        if not spellId then return; end
        MP.editingMacro.customIconType = 'spell';
        MP.editingMacro.customIconId = spellId;
        MP.editingMacro.customIconPath = nil;
        MP.editorAutoIconKey = 'spell:' .. tostring(spellId) .. ':';
    end

    local function SetIconItem(itemId)
        if not itemId then return; end
        MP.editingMacro.customIconType = 'item';
        MP.editingMacro.customIconId = itemId;
        MP.editingMacro.customIconPath = nil;
        MP.editorAutoIconKey = 'item:' .. tostring(itemId) .. ':';
    end

    local function SetIconCustom(customPath)
        if not customPath or customPath == '' then return; end
        MP.editingMacro.customIconType = 'custom';
        MP.editingMacro.customIconPath = customPath;
        MP.editingMacro.customIconId = nil;
        MP.editorAutoIconKey = 'custom::' .. tostring(customPath);
    end

    -- Fallback PNGs in addons/XIUI/assets/icons/ (ma.png, ja.png, macro.png, refresh.png, …)
    local function SetIconXiuiDefault(stem)
        if not stem or stem == '' then
            stem = 'refresh';
        end
        MP.editingMacro.customIconType = 'xiui_default';
        MP.editingMacro.customIconPath = stem;
        MP.editingMacro.customIconId = nil;
        MP.editorAutoIconKey = 'xiui_default::' .. stem;
    end

    local function DefaultIconStemForActionType(at)
        if at == 'ma' then return 'ma'; end
        if at == 'ja' then return 'ja'; end
        if at == 'ws' then return 'ws'; end
        if at == 'item' then return 'item'; end
        if at == 'equip' then return 'equip'; end
        if at == 'pet' then return 'pet'; end
        if at == 'macro' then return 'macro'; end
        return 'refresh';
    end

    local function TryAutoPickCustomIcon(actionName)
        local icon = MP.ResolveBestCustomIconMatchForActionName(actionName, MP.editorCustomIconCategory or 'all');
        if icon and icon.path then
            SetIconCustom(icon.path);
            return true;
        end
        return false;
    end

    -- Game spell icon: player's cache first, then horizon DB (context-aware for /ma vs /pet duplicates).
    local function TryAutoPickSpellIconByActionName(actionName, actionType)
        if not actionName or actionName == '' then
            return false;
        end
        if actionType ~= 'ma' and actionType ~= 'pet' then
            return false;
        end
        local spells = MP.GetCachedSpells();
        if spells then
            for _, s in ipairs(spells) do
                if s and s.name and s.id and string.lower(s.name) == string.lower(actionName) then
                    SetIconSpell(s.id);
                    return true;
                end
            end
        end
        local spellId = MP.actions.GetSpellIdByEnglishName(actionName, actionType);
        if spellId then
            SetIconSpell(spellId);
            return true;
        end
        return false;
    end

    -- Game item texture by item/equip action + itemId / name lookup.
    local function TryAutoPickItemIconByAction(actionName, actionType)
        if actionType ~= 'item' and actionType ~= 'equip' then
            return false;
        end
        local itemId = MP.editingMacro.itemId;
        if (not itemId or itemId == 0) and actionName and actionName ~= '' then
            itemId = MP.actiondb.GetItemId(actionName);
        end
        if itemId and itemId ~= 0 then
            SetIconItem(itemId);
            return true;
        end
        return false;
    end

    local function VirtualStemForParsedPrimary(pType)
        if pType == 'ma' then return 'ma'; end
        if pType == 'ja' then return 'ja'; end
        if pType == 'ws' then return 'ws'; end
        if pType == 'pet' then return 'pet'; end
        if pType == 'item' then return 'item'; end
        if pType == 'equip' then return 'equip'; end
        return 'macro';
    end

    -- Resolve icon from parsed macro lines (primary /ws /ma /pet …) using the same source rules as other types.
    local function PickIconForMacroParsedPrimary()
        local mp = require('modules.hotbar.macroparse');
        local pType, pName = mp.GetMacroPrimaryAndJaBadge(MP.editingMacro.macroText or '');
        if not pName or pName == '' then
            SetIconXiuiDefault('macro');
            return;
        end
        local src = MP.editorIconAutoSource;
        if src == 'all' then
            if pType == 'ma' and TryAutoPickSpellIconByActionName(pName, 'ma') then return; end
            -- /pet and /ja: custom assets (SMN folders, Summoning, etc.) before horizon "spell" ids — school magic ≠ blood pact
            if pType == 'pet' then
                if TryAutoPickCustomIcon(pName) then return; end
                if TryAutoPickSpellIconByActionName(pName, 'pet') then return; end
                SetIconXiuiDefault('pet');
                return;
            end
            if pType == 'ja' then
                if TryAutoPickCustomIcon(pName) then return; end
                SetIconXiuiDefault('ja');
                return;
            end
            if (pType == 'item' or pType == 'equip') and TryAutoPickItemIconByAction(pName, pType) then return; end
            if TryAutoPickCustomIcon(pName) then return; end
            SetIconXiuiDefault(VirtualStemForParsedPrimary(pType));
            return;
        end
        if src == 'spells' then
            if pType == 'ma' and TryAutoPickSpellIconByActionName(pName, 'ma') then return; end
            if pType == 'pet' then
                if TryAutoPickCustomIcon(pName) then return; end
                if TryAutoPickSpellIconByActionName(pName, 'pet') then return; end
                SetIconXiuiDefault('pet');
                return;
            end
            if pType == 'ja' then
                if TryAutoPickCustomIcon(pName) then return; end
                SetIconXiuiDefault('ja');
                return;
            end
            SetIconXiuiDefault(VirtualStemForParsedPrimary(pType));
            return;
        end
        if src == 'items' then
            if (pType == 'item' or pType == 'equip') and TryAutoPickItemIconByAction(pName, pType) then return; end
            SetIconXiuiDefault(VirtualStemForParsedPrimary(pType));
            return;
        end
        if src == 'custom' then
            if TryAutoPickCustomIcon(pName) then return; end
            SetIconXiuiDefault(VirtualStemForParsedPrimary(pType));
        end
    end

    local function SyncMacroSlotLabelFromParsedCommands()
        local mp = require('modules.hotbar.macroparse');
        local _, pName = mp.GetMacroPrimaryAndJaBadge(MP.editingMacro.macroText or '');
        if pName and pName ~= '' then
            MP.editingMacro.displayName = pName;
            MP.editorFields.displayName[1] = pName;
            MP.editorAutoLabel = pName;
        end
    end

    -- Clear JA badge overrides so the badge uses default resolution for the current /ja line (GetBindIcon ja).
    local function SyncJaBadgeIconFromMacro()
        MP.editorJaBadgeManuallySet = false;
        MP.editingMacro.jaBadgeCustomIconType = nil;
        MP.editingMacro.jaBadgeCustomIconId = nil;
        MP.editingMacro.jaBadgeCustomIconPath = nil;
        if MP.ClearPaletteJaBadgeIconCache then
            MP.ClearPaletteJaBadgeIconCache();
        end
    end

    local function AutoPickIconForSelection(force)
        if not MP.editingMacro then return; end
        if not force and not ShouldAllowImplicitAutoIconPick() then return; end

        local actionType = tostring(MP.editingMacro.actionType or '');
        if actionType == 'macro' then
            PickIconForMacroParsedPrimary();
            return;
        end

        local actionName = GetCurrentActionNameForIcon();
        if not actionName or actionName == '' then
            SetIconXiuiDefault(DefaultIconStemForActionType(actionType));
            return;
        end

        local src = MP.editorIconAutoSource;
        if src == 'all' then
            if actionType == 'ma' and TryAutoPickSpellIconByActionName(actionName, 'ma') then return; end
            if actionType == 'pet' then
                if TryAutoPickCustomIcon(actionName) then return; end
                if TryAutoPickSpellIconByActionName(actionName, 'pet') then return; end
                SetIconXiuiDefault('pet');
                return;
            end
            if actionType == 'ja' then
                if TryAutoPickCustomIcon(actionName) then return; end
                SetIconXiuiDefault('ja');
                return;
            end
            if TryAutoPickItemIconByAction(actionName, actionType) then return; end
            if TryAutoPickCustomIcon(actionName) then return; end
            SetIconXiuiDefault(DefaultIconStemForActionType(actionType));
            return;
        end

        if src == 'spells' then
            if actionType == 'ma' and TryAutoPickSpellIconByActionName(actionName, 'ma') then return; end
            if actionType == 'pet' then
                if TryAutoPickCustomIcon(actionName) then return; end
                if TryAutoPickSpellIconByActionName(actionName, 'pet') then return; end
                SetIconXiuiDefault('pet');
                return;
            end
            if actionType == 'ja' then
                if TryAutoPickCustomIcon(actionName) then return; end
                SetIconXiuiDefault('ja');
                return;
            end
            SetIconXiuiDefault(DefaultIconStemForActionType(actionType));
            return;
        end

        if src == 'items' then
            if TryAutoPickItemIconByAction(actionName, actionType) then return; end
            SetIconXiuiDefault(DefaultIconStemForActionType(actionType));
            return;
        end

        if src == 'custom' then
            if TryAutoPickCustomIcon(actionName) then return; end
            SetIconXiuiDefault(DefaultIconStemForActionType(actionType));
        end
    end

    local function RefreshEditorAutoIconKey()
        local t = MP.editingMacro.customIconType;
        local id = MP.editingMacro.customIconId;
        local p = MP.editingMacro.customIconPath;
        if t == nil and id == nil and (p == nil or p == '') then
            MP.editorAutoIconKey = nil;
        else
            MP.editorAutoIconKey = tostring(t or '') .. ':' .. tostring(id or '') .. ':' .. tostring(p or '');
        end
    end

    -- Dropdown picks = intentional action change: icon should follow; clear manual flag.
    local function SyncEditorIconAfterListPick()
        MP.editorIconManuallySet = false;
        AutoPickIconForSelection(true);
        RefreshEditorAutoIconKey();
    end

    -- One-time implicit auto-pick when typing (manual action / macro lines).
    -- Skipped when the user has manually chosen an icon via the Change button.
    local function TryFirstImplicitActionIconAuto()
        if MP.editorImplicitActionIconDone then
            return;
        end
        if MP.editorIconManuallySet then
            return;
        end
        -- Use force=false so saved/manual icons are not overwritten when macro text changes
        -- (AutoPickIconForSelection(true) bypasses ShouldAllowImplicitAutoIconPick).
        AutoPickIconForSelection(false);
        MP.editorImplicitActionIconDone = true;
        RefreshEditorAutoIconKey();
    end

    -- First editor frame: align MP.editorAutoIconKey with the saved macro (no automatic icon refresh on open).
    if not MP.editorDidInitialIconPick then
        MP.editorDidInitialIconPick = true;
        RefreshEditorAutoIconKey();
    end

    -- Manual resize: do NOT use AlwaysAutoResize — it fights the resize grip every frame.
    MP.imgui.SetNextWindowSize({520, 680}, ImGuiCond_FirstUseEver);
    MP.imgui.SetNextWindowSizeConstraints({480, 320}, {1000, 900});

    -- Apply XIUI styling
    MP.PushWindowStyle();

    if MP.imgui.Begin(title, isOpen, ImGuiWindowFlags_NoCollapse) then
        local avail = MP.imgui.GetContentRegionAvail();
        local contentWidth = (type(avail) == 'table' and avail[1]) or avail or 400;
        local miniToolBtn = 22;
        local uiIconRefresh = MP.actions.LoadXiuiAssetIcon('refresh');
        local uiIconSync = MP.actions.LoadXiuiAssetIcon('sync');
        local uiIconFolder = MP.actions.LoadXiuiAssetIcon('folder');

        -- ── Save-target toolbar (create mode) ──
        MP.M.DrawMacroEditorSaveToSection(MP.isCreatingNew, contentWidth);

        -- ── Layout metrics ──
        local iconPreviewSize = 56;
        local previewInset = 2;
        local hasJaBadge = false;
        do
            local mp = require('modules.hotbar.macroparse');
            hasJaBadge = MP.editingMacro.actionType == 'macro' and mp.MacroHasJaBadgePair(MP.editingMacro.macroText or '');
        end
        local iconPanelW = 198;
        local iconPanelPad = 10;
        -- Wider window → wider fields (icon column stays fixed width).
        local fieldW = math.max(120, math.min(contentWidth - iconPanelW - 24, 640));
        local changeBtnW = iconPreviewSize;
        local showFolder = (MP.editorIconAutoSource == 'custom');

        -- ── Action Type (left column, top) ──
        local topY = MP.imgui.GetCursorPosY();

        MP.imgui.TextColored(MP.COLORS.goldDim, 'Action Type');
        MP.PushComboStyle();
        MP.imgui.SetNextItemWidth(fieldW);
        local currentType = MP.ACTION_TYPES[MP.editorFields.actionType[1]];
        if MP.imgui.BeginCombo('##actionType', MP.ACTION_TYPE_LABELS[currentType] or 'Select...') then
            for i, actionType in ipairs(MP.ACTION_TYPES) do
                local isSelected = MP.editorFields.actionType[1] == i;
                if isSelected then
                    MP.imgui.PushStyleColor(ImGuiCol_Text, MP.COLORS.gold);
                end
                if MP.imgui.Selectable(MP.ACTION_TYPE_LABELS[actionType], isSelected) then
                    MP.editorFields.actionType[1] = i;
                    MP.editingMacro.actionType = actionType;
                    MP.editingMacro.action = '';
                    MP.editorFields.action[1] = '';
                    MP.searchFilter[1] = '';
                    if actionType ~= 'macro' then
                        MP.editingMacro.recastSourceType = nil;
                        MP.editingMacro.recastSourceAction = nil;
                        MP.editingMacro.recastSourceItemId = nil;
                        MP.editorFields.recastSourceType[1] = 1;
                        MP.editorFields.recastSourceAction[1] = '';
                        MP.editingMacro.showJaBadgeOnMacro = nil;
                    end
                    if actionType == 'pet' then
                        MP.SyncSaveSubTypeFromPetAvatarFilter();
                    end
                    MP.editorImplicitActionIconDone = false;
                end
                if isSelected then
                    MP.imgui.PopStyleColor();
                end
            end
            MP.imgui.EndCombo();
        end
        MP.PopComboStyle();

        -- Remember Y after action type so dynamic fields flow right below
        local yAfterActionType = MP.imgui.GetCursorPosY();

        -- Icon panel height: Custom + JA badge stacks the left column taller than the preview column;
        -- JA block must start below BOTH or labels overlap ("Folder" vs "JA badge").
        local function estimateIconPanelTotalH()
            local frameH = (MP.imgui.GetFrameHeight and MP.imgui.GetFrameHeight()) or 28;
            local tls = (MP.imgui.GetTextLineHeightWithSpacing and MP.imgui.GetTextLineHeightWithSpacing()) or 20;
            local tl = (MP.imgui.GetTextLineHeight and MP.imgui.GetTextLineHeight()) or 14;
            local iconRowH = math.max(miniToolBtn, tl + 2);
            local hLeft = iconPanelPad + iconRowH + tls + frameH + tls + frameH;
            if showFolder then
                hLeft = hLeft + tls + frameH + tls + tl + 6 + miniToolBtn;
            end
            local previewTop = iconPanelPad + previewInset;
            local hRight = previewTop + iconPreviewSize + 4 + 20;
            local core = math.max(hLeft, hRight);
            if hasJaBadge then
                -- Label + spacing + checkbox row + SameLine Change (needs extra slack; some ImGui builds clip low)
                core = core + 8 + tl + 8 + tls + frameH + 28;
                if showFolder then
                    core = core + 16;
                end
            end
            return core + iconPanelPad + 8;
        end

        -- ── Icon sub-container (float to top-right) ──
        local iconPanelX = contentWidth - iconPanelW;
        local iconPanelTotalH = estimateIconPanelTotalH();

        MP.imgui.SetCursorPos({iconPanelX, topY});
        MP.imgui.PushStyleColor(ImGuiCol_ChildBg, {0.18, 0.16, 0.11, 0.95});

        local iconPanelScreenPos = {MP.imgui.GetCursorScreenPos()};
        -- Optional vertical scrollbar when Macro + Custom (tall stack); avoids clipped buttons if estimate is short
        local iconChildFlags = 0;
        if hasJaBadge and showFolder and ImGuiWindowFlags_AlwaysVerticalScrollbar ~= nil then
            iconChildFlags = ImGuiWindowFlags_AlwaysVerticalScrollbar;
        end
        if MP.imgui.BeginChild('##iconPanel', {iconPanelW, iconPanelTotalH}, false, iconChildFlags) then
            local innerAvail = MP.imgui.GetContentRegionAvail();
            local innerW = (type(innerAvail) == 'table' and innerAvail[1]) or innerAvail or iconPanelW;

            -- Manual insets since WindowPadding isn't reliable in this ImGui
            MP.imgui.SetCursorPos({iconPanelPad, iconPanelPad});
            local usableW = innerW - iconPanelPad * 2;
            local previewGap = 22;

            -- Left column: source combo + optional folder
            local leftColW = usableW - iconPreviewSize - previewGap;

            -- Icon label + tool buttons (first row)
            MP.imgui.TextColored(MP.COLORS.goldDim, 'Icon');
            MP.imgui.SameLine(0, 4);
            if MP.DrawIconButton('##macroEditorIconReset', uiIconRefresh, miniToolBtn, false,
                    'Reset icon to type default') then
                SetIconXiuiDefault(DefaultIconStemForActionType(tostring(MP.editingMacro.actionType or '')));
            end
            MP.imgui.SameLine(0, 2);
            if MP.DrawIconButton('##macroEditorIconSync', uiIconSync, miniToolBtn, false,
                    'Sync main slot icon from current action or macro lines') then
                MP.editorIconManuallySet = false;
                AutoPickIconForSelection(true);
                RefreshEditorAutoIconKey();
            end
            MP.imgui.SameLine(0, 2);
            MP.imgui.ShowHelp('Choosing from the list syncs the main icon. For Macro type, text edits do not change the main icon after you use Change — press Sync to refresh, or Sync after typing.');

            -- Source combo
            MP.imgui.SetCursorPosX(iconPanelPad);
            MP.PushComboStyle();
            MP.imgui.SetNextItemWidth(leftColW);
            local srcLabel = MP.ICON_AUTO_SOURCE_LABELS[MP.editorIconAutoSource] or 'All';
            if MP.imgui.BeginCombo('##iconAutoSource', srcLabel, ImGuiComboFlags_None) then
                for _, src in ipairs(MP.ICON_AUTO_SOURCES) do
                    local isSel = (MP.editorIconAutoSource == src);
                    if MP.imgui.Selectable(MP.ICON_AUTO_SOURCE_LABELS[src] or src, isSel) then
                        MP.editorIconAutoSource = src;
                        MP.PersistMacroEditorIconPrefs();
                    end
                    if isSel then MP.imgui.SetItemDefaultFocus(); end
                end
                MP.imgui.EndCombo();
            end
            MP.PopComboStyle();

            -- Custom icon source: category combo then folder row (finish left column before preview / JA block)
            if showFolder then
                MP.LoadCustomIcons();

                -- Category sub-menu
                MP.imgui.SetCursorPosX(iconPanelPad);
                local categories = MP.CUSTOM_ICON_CATEGORIES or { 'all' };
                if not MP.editorCustomIconCategory then MP.editorCustomIconCategory = 'all'; end
                local catLabel = MP.CUSTOM_ICON_LABELS[MP.editorCustomIconCategory] or MP.editorCustomIconCategory or 'All';
                MP.PushComboStyle();
                MP.imgui.SetNextItemWidth(leftColW);
                if MP.imgui.BeginCombo('##iconCustomFolder', catLabel, ImGuiComboFlags_None) then
                    local isAll = (MP.editorCustomIconCategory == 'all');
                    if MP.imgui.Selectable(MP.CUSTOM_ICON_LABELS['all'] or 'All', isAll) then
                        MP.editorCustomIconCategory = 'all';
                        MP.PersistMacroEditorIconPrefs();
                    end
                    MP.imgui.Separator();
                    for _, cat in ipairs(categories) do
                        if cat ~= 'all' then
                            local isSel = (MP.editorCustomIconCategory == cat);
                            local catLbl = MP.CUSTOM_ICON_LABELS[cat] or cat;
                            if MP.imgui.Selectable(catLbl, isSel) then
                                MP.editorCustomIconCategory = cat;
                                MP.PersistMacroEditorIconPrefs();
                            end
                            if isSel then MP.imgui.SetItemDefaultFocus(); end
                        end
                    end
                    MP.imgui.EndCombo();
                end
                MP.PopComboStyle();

                -- Folder open button
                MP.imgui.SetCursorPosX(iconPanelPad);
                MP.imgui.TextColored(MP.COLORS.textDim, 'Folder');
                MP.imgui.SameLine(0, 4);
                if MP.DrawIconButton('##openXiuiAssetsFolder', uiIconFolder, miniToolBtn, false,
                        'Open assets folder in Explorer') then
                    local assetsRoot = string.format('%saddons\\XIUI\\assets\\', AshitaCore:GetInstallPath());
                    if ashita and ashita.fs and not ashita.fs.exists(assetsRoot) then
                        ashita.fs.create_directory(assetsRoot);
                    end
                    os.execute('explorer "' .. assetsRoot .. '"');
                end
            end

            local yLeftEnd = MP.imgui.GetCursorPosY();

            -- Preview + main Change (right column), top-aligned with icon row
            local previewX = innerW - iconPreviewSize - iconPanelPad - previewInset;
            local previewTopY = iconPanelPad + previewInset;
            MP.imgui.SetCursorPos({previewX, previewTopY});
            local screenPos = {MP.imgui.GetCursorScreenPos()};
            MP.DrawIconPreview(MP.editingMacro, screenPos[1], screenPos[2], iconPreviewSize);

            MP.imgui.SetCursorPos({previewX, previewTopY + iconPreviewSize + 4});
            MP.imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 1);
            MP.imgui.PushStyleColor(ImGuiCol_Border, MP.COLORS.gold);
            if MP.imgui.Button('Change##macroEditorIconChange', {changeBtnW, 20}) then
                MP.InvalidateCustomIconScanCaches();
                MP.iconPickerTargetIsJaBadge = false;
                MP.iconPickerOpen = true;
                MP.editorIconManuallySet = true;
                MP.M.ApplyIconPickerContextFromEditor(false);
            end
            MP.imgui.PopStyleColor();
            MP.imgui.PopStyleVar();

            local yRightEnd = previewTopY + iconPreviewSize + 4 + 20;

            -- JA badge block starts below the taller of the left stack or the preview column (no overlap with Folder row)
            if hasJaBadge then
                if MP.editingMacro.showJaBadgeOnMacro == nil then
                    MP.editingMacro.showJaBadgeOnMacro = true;
                end
                local jaY = math.max(yLeftEnd, yRightEnd) + 8;
                MP.imgui.SetCursorPos({iconPanelPad, jaY});
                MP.imgui.TextColored(MP.COLORS.textDim, 'JA badge');
                MP.imgui.SameLine(0, 4);
                if MP.DrawIconButton('##macroEditorJaBadgeSync', uiIconSync, miniToolBtn, false,
                        'Sync JA badge icon from the current /ja line (clears a manual badge icon)') then
                    SyncJaBadgeIconFromMacro();
                end
                MP.imgui.SameLine(0, 2);
                MP.imgui.ShowHelp('After you pick a badge icon with Change, it stays until you Sync here. Macro text edits do not override a manual badge icon.');
                MP.imgui.Spacing();
                MP.imgui.SetCursorPosX(iconPanelPad);
                local showJaBadgeBuf = { MP.editingMacro.showJaBadgeOnMacro ~= false };
                if MP.imgui.Checkbox('Use JA Badge##showJaBadgeMacro', showJaBadgeBuf) then
                    MP.editingMacro.showJaBadgeOnMacro = showJaBadgeBuf[1];
                end
                MP.imgui.SameLine(0, 8);
                MP.imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 1);
                MP.imgui.PushStyleColor(ImGuiCol_Border, MP.COLORS.gold);
                if MP.imgui.Button('Change##macroJaBadgeIconChange', {changeBtnW, 20}) then
                    MP.InvalidateCustomIconScanCaches();
                    MP.iconPickerOpen = true;
                    MP.editorJaBadgeManuallySet = true;
                    MP.M.ApplyIconPickerContextFromEditor(true);
                end
                MP.imgui.PopStyleColor();
                MP.imgui.PopStyleVar();
            end
        end
        MP.imgui.EndChild();
        MP.imgui.PopStyleColor();

        -- Draw gold border manually (child border style not reliable in this ImGui)
        local drawList = MP.imgui.GetWindowDrawList();
        if drawList then
            local bx = iconPanelScreenPos[1] or iconPanelScreenPos.x or 0;
            local by = iconPanelScreenPos[2] or iconPanelScreenPos.y or 0;
            local borderCol = MP.imgui.GetColorU32(MP.COLORS.gold);
            drawList:AddRect({bx, by}, {bx + iconPanelW, by + iconPanelTotalH}, borderCol, 4, 0, 1.5);
        end

        -- ── Continue left column below Action Type ──
        MP.imgui.SetCursorPos({8, yAfterActionType});
        MP.imgui.Spacing();

        -- Dynamic fields based on action type
        currentType = MP.ACTION_TYPES[MP.editorFields.actionType[1]];

        if currentType == 'ma' then
            -- Spell: Show searchable dropdown
            MP.imgui.TextColored(MP.COLORS.goldDim, 'Spell');
            MP.imgui.SameLine();
            local showAllSpells = { MP.showAllMode };
            if MP.imgui.Checkbox('Show All##showAllSpells', showAllSpells) then
                MP.showAllMode = showAllSpells[1];
                MP.playerdata.ClearExpandedCaches();
                if MP.showAllMode and MP.spellTypeFilter == 'All' then
                    local jobTypes = MP.playerdata.GetMagicTypesForJob();
                    if #jobTypes > 0 then
                        MP.spellTypeFilter = jobTypes[1].key;
                        MP.playerdata.ClearExpandedCaches();
                    end
                end
            end
            MP.imgui.SameLine(0, 2);
            MP.imgui.ShowHelp('Green = known, Yellow = learnable (right job/level), Red = unavailable');
            local spells;
            local useStatusColors = false;
            if MP.showAllMode then
                -- Magic Type filter dropdown
                local filterLabel = MP.playerdata.GetMagicTypeLabel(MP.spellTypeFilter);
                MP.PushComboStyle();
                MP.imgui.SetNextItemWidth(fieldW);
                if MP.imgui.BeginCombo('##spellTypeFilter', filterLabel) then
                    local allTypes = MP.playerdata.GetAllMagicTypes();
                    local jobTypes = MP.playerdata.GetMagicTypesForJob();
                    local jobSet = {};
                    for _, jt in ipairs(jobTypes) do jobSet[jt.key] = true; end

                    for _, mt in ipairs(allTypes) do
                        local isSel = (MP.spellTypeFilter == mt.key);
                        local label = mt.label;
                        if jobSet[mt.key] then label = label .. '  [Current]'; end
                        if isSel then MP.imgui.PushStyleColor(ImGuiCol_Text, MP.COLORS.gold); end
                        if MP.imgui.Selectable(label, isSel) then
                            MP.spellTypeFilter = mt.key;
                            MP.playerdata.ClearExpandedCaches();
                        end
                        if isSel then MP.imgui.PopStyleColor(); end
                    end
                    MP.imgui.EndCombo();
                end
                MP.PopComboStyle();

                spells = MP.playerdata.GetAllSpellsForCurrentJob(MP.spellTypeFilter);
                useStatusColors = true;
            else
                spells = MP.GetCachedSpells();
            end
            if spells and #spells > 0 then
                MP.DrawSearchableCombo('##spellCombo', spells, MP.editingMacro.action or '', function(spell)
                    MP.editingMacro.action = spell.name;
                    MP.editorFields.action[1] = spell.name;
                    AutoSetDisplayName(spell.name);
                    SyncEditorIconAfterListPick();
                end, nil, nil, fieldW, useStatusColors);
            else
                MP.imgui.TextColored(MP.COLORS.textMuted, 'No spells available for this job');
            end

            -- Target dropdown
            MP.imgui.Spacing();
            MP.imgui.TextColored(MP.COLORS.goldDim, 'Target');
            MP.PushComboStyle();
            MP.imgui.SetNextItemWidth(fieldW);
            if MP.imgui.BeginCombo('##targetType', MP.TARGET_LABELS[MP.TARGET_OPTIONS[MP.editorFields.target[1]]] or 'Select...') then
                for i, target in ipairs(MP.TARGET_OPTIONS) do
                    local isSelected = MP.editorFields.target[1] == i;
                    if isSelected then MP.imgui.PushStyleColor(ImGuiCol_Text, MP.COLORS.gold); end
                    if MP.imgui.Selectable(MP.TARGET_LABELS[target], isSelected) then
                        MP.editorFields.target[1] = i;
                        MP.editingMacro.target = target;
                    end
                    if isSelected then MP.imgui.PopStyleColor(); end
                end
                MP.imgui.EndCombo();
            end
            MP.PopComboStyle();

        elseif currentType == 'ja' then
            -- Ability: Show searchable dropdown
            MP.imgui.TextColored(MP.COLORS.goldDim, 'Ability');
            MP.imgui.SameLine();
            local showAllJA = { MP.showAllMode };
            if MP.imgui.Checkbox('Show All##showAllAbilities', showAllJA) then
                MP.showAllMode = showAllJA[1];
                MP.playerdata.ClearExpandedCaches();
            end
            MP.imgui.SameLine(0, 2);
            MP.imgui.ShowHelp('Green = known, Yellow = learnable (right job/level), Red = unavailable.\nUse the Job filter to browse abilities for any job.');
            local abilities;
            local useStatusColors = false;
            if MP.showAllMode then
                -- Job filter dropdown (only shown when Show All is on)
                local player = AshitaCore:GetMemoryManager():GetPlayer();
                local mainJobId = player and player:GetMainJob() or 0;
                local subJobId = player and player:GetSubJob() or 0;
                local mainJobAbbr = MP.jobs[mainJobId] or '???';
                local subJobAbbr = (subJobId and subJobId > 0) and MP.jobs[subJobId] or nil;

                local filterLabel;
                if MP.abilityJobFilter == 0 then
                    if subJobAbbr then
                        filterLabel = mainJobAbbr .. ' + ' .. subJobAbbr .. ' (Current)';
                    else
                        filterLabel = mainJobAbbr .. ' (Current)';
                    end
                else
                    filterLabel = MP.jobs[MP.abilityJobFilter] or '???';
                end

                MP.imgui.TextColored(MP.COLORS.goldDim, 'Job');
                MP.PushComboStyle();
                MP.imgui.SetNextItemWidth(fieldW);
                if MP.imgui.BeginCombo('##abilityJobFilter', filterLabel) then
                    -- "Current Jobs" option (main + sub)
                    local isAutoSelected = MP.abilityJobFilter == 0;
                    if isAutoSelected then MP.imgui.PushStyleColor(ImGuiCol_Text, MP.COLORS.gold); end
                    local autoLabel;
                    if subJobAbbr then
                        autoLabel = mainJobAbbr .. ' + ' .. subJobAbbr .. ' (Current)';
                    else
                        autoLabel = mainJobAbbr .. ' (Current)';
                    end
                    if MP.imgui.Selectable(autoLabel, isAutoSelected) then
                        if MP.abilityJobFilter ~= 0 then
                            MP.abilityJobFilter = 0;
                            MP.playerdata.ClearExpandedCaches();
                        end
                    end
                    if isAutoSelected then MP.imgui.PopStyleColor(); end

                    MP.imgui.Separator();

                    -- All 15 base jobs (HorizonXI cap)
                    for jid = 1, 15 do
                        local abbr = MP.jobs[jid] or '???';
                        local label = abbr;
                        if jid == mainJobId then
                            label = label .. '  [Main]';
                        elseif jid == subJobId then
                            label = label .. '  [Sub]';
                        end
                        local isSelected = MP.abilityJobFilter == jid;
                        if isSelected then MP.imgui.PushStyleColor(ImGuiCol_Text, MP.COLORS.gold); end
                        if MP.imgui.Selectable(label, isSelected) then
                            if MP.abilityJobFilter ~= jid then
                                MP.abilityJobFilter = jid;
                                MP.playerdata.ClearExpandedCaches();
                            end
                        end
                        if isSelected then MP.imgui.PopStyleColor(); end
                    end
                    MP.imgui.EndCombo();
                end
                MP.PopComboStyle();

                abilities = MP.playerdata.GetAllAbilitiesForCurrentJob(MP.abilityJobFilter);
                useStatusColors = true;
            else
                abilities = MP.GetCachedAbilities();
            end
            if abilities and #abilities > 0 then
                MP.DrawSearchableCombo('##abilityCombo', abilities, MP.editingMacro.action or '', function(ability)
                    MP.editingMacro.action = ability.name;
                    MP.editorFields.action[1] = ability.name;
                    AutoSetDisplayName(ability.name);
                    SyncEditorIconAfterListPick();
                end, nil, nil, fieldW, useStatusColors);
            else
                MP.imgui.TextColored(MP.COLORS.textMuted, 'No abilities available');
            end

            -- Target dropdown
            MP.imgui.Spacing();
            MP.imgui.TextColored(MP.COLORS.goldDim, 'Target');
            MP.PushComboStyle();
            MP.imgui.SetNextItemWidth(fieldW);
            if MP.imgui.BeginCombo('##targetType', MP.TARGET_LABELS[MP.TARGET_OPTIONS[MP.editorFields.target[1]]] or 'Select...') then
                for i, target in ipairs(MP.TARGET_OPTIONS) do
                    local isSelected = MP.editorFields.target[1] == i;
                    if isSelected then MP.imgui.PushStyleColor(ImGuiCol_Text, MP.COLORS.gold); end
                    if MP.imgui.Selectable(MP.TARGET_LABELS[target], isSelected) then
                        MP.editorFields.target[1] = i;
                        MP.editingMacro.target = target;
                    end
                    if isSelected then MP.imgui.PopStyleColor(); end
                end
                MP.imgui.EndCombo();
            end
            MP.PopComboStyle();

        elseif currentType == 'ws' then
            -- Weaponskill: Show searchable dropdown
            MP.imgui.TextColored(MP.COLORS.goldDim, 'Weaponskill');
            MP.imgui.SameLine();
            local showAllWS = { MP.showAllMode };
            if MP.imgui.Checkbox('Show All##showAllWS', showAllWS) then
                MP.showAllMode = showAllWS[1];
                MP.playerdata.ClearExpandedCaches();
                if MP.showAllMode then
                    -- Default filter to the weapon type matching current known WS
                    local currentWs = MP.GetCachedWeaponskills();
                    if currentWs and #currentWs > 0 then
                        local wsDb = require('modules.hotbar.database.ws_weapon_types');
                        for _, ws in ipairs(currentWs) do
                            local info = wsDb[ws.name];
                            if info then
                                MP.wsWeaponFilter = info.weapon;
                                break;
                            end
                        end
                    end
                end
            end
            MP.imgui.SameLine(0, 2);
            MP.imgui.ShowHelp('Green = known, Red = not yet learned. Filter by weapon type below.');
            local weaponskills;
            local useStatusColors = false;
            if MP.showAllMode then
                -- Weapon type filter dropdown
                MP.PushComboStyle();
                MP.imgui.SetNextItemWidth(fieldW);
                if MP.imgui.BeginCombo('##wsWeaponFilter', MP.wsWeaponFilter) then
                    if MP.imgui.Selectable('All', MP.wsWeaponFilter == 'All') then
                        MP.wsWeaponFilter = 'All';
                        MP.playerdata.ClearExpandedCaches();
                    end
                    local weaponTypes = MP.playerdata.GetWeaponTypes();
                    for _, wt in ipairs(weaponTypes) do
                        local isSel = (MP.wsWeaponFilter == wt);
                        if isSel then MP.imgui.PushStyleColor(ImGuiCol_Text, MP.COLORS.gold); end
                        if MP.imgui.Selectable(wt, isSel) then
                            MP.wsWeaponFilter = wt;
                            MP.playerdata.ClearExpandedCaches();
                        end
                        if isSel then MP.imgui.PopStyleColor(); end
                    end
                    MP.imgui.EndCombo();
                end
                MP.PopComboStyle();

                local allWs = MP.playerdata.GetAllWeaponskillsExpanded();
                if MP.wsWeaponFilter ~= 'All' then
                    local filtered = {};
                    for _, ws in ipairs(allWs) do
                        if ws.weapon == MP.wsWeaponFilter then
                            table.insert(filtered, ws);
                        end
                    end
                    weaponskills = filtered;
                else
                    weaponskills = allWs;
                end
                useStatusColors = true;
            else
                weaponskills = MP.GetCachedWeaponskills();
            end
            if weaponskills and #weaponskills > 0 then
                MP.DrawSearchableCombo('##wsCombo', weaponskills, MP.editingMacro.action or '', function(ws)
                    MP.editingMacro.action = ws.name;
                    MP.editorFields.action[1] = ws.name;
                    AutoSetDisplayName(ws.name);
                    SyncEditorIconAfterListPick();
                end, nil, nil, fieldW, useStatusColors);
            else
                MP.imgui.TextColored(MP.COLORS.textMuted, 'No weaponskills available');
            end

            -- Target dropdown (default to <t>)
            MP.imgui.Spacing();
            MP.imgui.TextColored(MP.COLORS.goldDim, 'Target');
            MP.PushComboStyle();
            MP.imgui.SetNextItemWidth(fieldW);
            if MP.imgui.BeginCombo('##targetType', MP.TARGET_LABELS[MP.TARGET_OPTIONS[MP.editorFields.target[1]]] or 'Select...') then
                for i, target in ipairs(MP.TARGET_OPTIONS) do
                    local isSelected = MP.editorFields.target[1] == i;
                    if isSelected then MP.imgui.PushStyleColor(ImGuiCol_Text, MP.COLORS.gold); end
                    if MP.imgui.Selectable(MP.TARGET_LABELS[target], isSelected) then
                        MP.editorFields.target[1] = i;
                        MP.editingMacro.target = target;
                    end
                    if isSelected then MP.imgui.PopStyleColor(); end
                end
                MP.imgui.EndCombo();
            end
            MP.PopComboStyle();

        elseif currentType == 'item' then
            -- Item: Searchable dropdown or manual input
            MP.imgui.TextColored(MP.COLORS.goldDim, 'Item');
            local items = MP.GetCachedItems();
            if items and #items > 0 then
                MP.DrawSearchableCombo('##itemCombo', items, MP.editingMacro.action or '', function(item)
                    MP.editingMacro.action = item.name;
                    MP.editingMacro.itemId = item.id;  -- Store item ID for fast icon lookup
                    MP.editorFields.action[1] = item.name;
                    AutoSetDisplayName(item.name);
                    SyncEditorIconAfterListPick();
                end, true, nil, fieldW);  -- Show icons
                MP.imgui.SameLine();
                MP.imgui.TextColored(MP.COLORS.textMuted, '(' .. #items .. ')');
            else
                MP.imgui.TextColored(MP.COLORS.textMuted, 'No items found in storage');
            end

            -- Manual input fallback
            MP.imgui.Spacing();
            MP.imgui.TextColored(MP.COLORS.goldDim, 'Or type item name:');
            MP.imgui.SetNextItemWidth(fieldW);
            if MP.imgui.InputText('##itemName', MP.editorFields.action, MP.INPUT_BUFFER_SIZE) then
                MP.editingMacro.action = MP.editorFields.action[1];
                AutoSetDisplayName(MP.editingMacro.action);
                if (MP.editingMacro.action or '') ~= '' then
                    TryFirstImplicitActionIconAuto();
                end
            end

            -- Target dropdown
            MP.imgui.Spacing();
            MP.imgui.TextColored(MP.COLORS.goldDim, 'Target');
            MP.PushComboStyle();
            MP.imgui.SetNextItemWidth(fieldW);
            if MP.imgui.BeginCombo('##targetType', MP.TARGET_LABELS[MP.TARGET_OPTIONS[MP.editorFields.target[1]]] or 'Select...') then
                for i, target in ipairs(MP.TARGET_OPTIONS) do
                    local isSelected = MP.editorFields.target[1] == i;
                    if isSelected then MP.imgui.PushStyleColor(ImGuiCol_Text, MP.COLORS.gold); end
                    if MP.imgui.Selectable(MP.TARGET_LABELS[target], isSelected) then
                        MP.editorFields.target[1] = i;
                        MP.editingMacro.target = target;
                    end
                    if isSelected then MP.imgui.PopStyleColor(); end
                end
                MP.imgui.EndCombo();
            end
            MP.PopComboStyle();

        elseif currentType == 'equip' then
            -- Equipment slot dropdown
            MP.imgui.TextColored(MP.COLORS.goldDim, 'Equipment Slot');
            MP.PushComboStyle();
            MP.imgui.SetNextItemWidth(fieldW);
            if MP.imgui.BeginCombo('##equipSlot', MP.EQUIP_SLOT_LABELS[MP.EQUIP_SLOTS[MP.editorFields.equipSlot[1]]] or 'Select...') then
                for i, slot in ipairs(MP.EQUIP_SLOTS) do
                    local isSelected = MP.editorFields.equipSlot[1] == i;
                    if isSelected then MP.imgui.PushStyleColor(ImGuiCol_Text, MP.COLORS.gold); end
                    if MP.imgui.Selectable(MP.EQUIP_SLOT_LABELS[slot], isSelected) then
                        MP.editorFields.equipSlot[1] = i;
                        MP.editingMacro.equipSlot = slot;
                        -- Clear item selection when slot changes (old item may not fit new slot)
                        MP.editingMacro.action = '';
                        MP.editingMacro.itemId = nil;
                        MP.editingMacro.displayName = '';
                        MP.editorFields.action[1] = '';
                        MP.editorFields.displayName[1] = '';
                        MP.editorImplicitActionIconDone = false;
                    end
                    if isSelected then MP.imgui.PopStyleColor(); end
                end
                MP.imgui.EndCombo();
            end
            MP.PopComboStyle();

            -- Item: Searchable dropdown or manual input (filtered by selected equipment slot)
            MP.imgui.Spacing();
            local selectedSlot = MP.EQUIP_SLOTS[MP.editorFields.equipSlot[1]];
            MP.imgui.TextColored(MP.COLORS.goldDim, 'Item (' .. MP.EQUIP_SLOT_LABELS[selectedSlot] .. ')');
            local equipItems = MP.GetCachedItems();
            if equipItems and #equipItems > 0 then
                MP.DrawSearchableCombo('##equipItemCombo', equipItems, MP.editingMacro.action or '', function(item)
                    MP.editingMacro.action = item.name;
                    MP.editingMacro.itemId = item.id;  -- Store item ID for fast icon lookup
                    MP.editorFields.action[1] = item.name;
                    AutoSetDisplayName(item.name);
                    SyncEditorIconAfterListPick();
                end, true, selectedSlot, fieldW);  -- Show icons, filter by selected slot
                MP.imgui.SameLine();
                MP.imgui.TextColored(MP.COLORS.textMuted, '(' .. #equipItems .. ')');
            else
                MP.imgui.TextColored(MP.COLORS.textMuted, 'No items found in storage');
            end

            -- Manual input fallback
            MP.imgui.Spacing();
            MP.imgui.TextColored(MP.COLORS.goldDim, 'Or type item name:');
            MP.imgui.SetNextItemWidth(fieldW);
            if MP.imgui.InputText('##equipItemName', MP.editorFields.action, MP.INPUT_BUFFER_SIZE) then
                MP.editingMacro.action = MP.editorFields.action[1];
                AutoSetDisplayName(MP.editingMacro.action);
                if (MP.editingMacro.action or '') ~= '' then
                    TryFirstImplicitActionIconAuto();
                end
            end

        elseif currentType == 'macro' then
            -- Raw macro command (8 lines like native FFXI macro editor)
            MP.imgui.TextColored(MP.COLORS.goldDim, 'Macro Commands (8 lines)');

            -- Style the multiline input
            MP.imgui.PushStyleColor(ImGuiCol_FrameBg, MP.COLORS.bgMedium);
            MP.imgui.PushStyleColor(ImGuiCol_FrameBgHovered, MP.COLORS.bgLight);
            MP.imgui.PushStyleColor(ImGuiCol_FrameBgActive, MP.COLORS.bgLight);

            -- 8 rows * ~16px line height + padding
            local lineHeight = MP.imgui.GetTextLineHeight();
            local inputHeight = (lineHeight * 8) + 8;

            if MP.imgui.InputTextMultiline('##macroText', MP.editorFields.macroText, MP.MACRO_BUFFER_SIZE, {math.max(120, fieldW), inputHeight}) then
                MP.editingMacro.macroText = MP.editorFields.macroText[1];
                local mp = require('modules.hotbar.macroparse');
                local _, pName = mp.GetMacroPrimaryAndJaBadge(MP.editingMacro.macroText or '');
                MP.editingMacro.action = (pName and pName ~= '') and pName or '';
                if pName and pName ~= '' then
                    TryFirstImplicitActionIconAuto();
                end
            end

            MP.imgui.PopStyleColor(3);
            MP.imgui.ShowHelp('Enter commands, one per line (e.g., /ma "Cure" <stpc>)');

            -- Recast Source section (optional)
            MP.imgui.Spacing();
            MP.imgui.Spacing();
            if MP.imgui.TreeNode('Recast Source (Optional)##recastSource') then
                MP.imgui.TextColored(MP.COLORS.textMuted, 'Show cooldown from a different action');
                MP.imgui.Spacing();

                -- Recast source type dropdown
                MP.imgui.TextColored(MP.COLORS.goldDim, 'Source Type');
                MP.PushComboStyle();
                MP.imgui.SetNextItemWidth(fieldW);
                local currentRecastType = MP.RECAST_SOURCE_TYPES[MP.editorFields.recastSourceType[1]] or 'none';
                if MP.imgui.BeginCombo('##recastSourceType', MP.RECAST_SOURCE_LABELS[currentRecastType] or 'None') then
                    for i, sourceType in ipairs(MP.RECAST_SOURCE_TYPES) do
                        local isSelected = MP.editorFields.recastSourceType[1] == i;
                        if isSelected then MP.imgui.PushStyleColor(ImGuiCol_Text, MP.COLORS.gold); end
                        if MP.imgui.Selectable(MP.RECAST_SOURCE_LABELS[sourceType], isSelected) then
                            MP.editorFields.recastSourceType[1] = i;
                            if sourceType == 'none' then
                                MP.editingMacro.recastSourceType = nil;
                                MP.editingMacro.recastSourceAction = nil;
                                MP.editingMacro.recastSourceItemId = nil;
                            else
                                MP.editingMacro.recastSourceType = sourceType;
                            end
                            -- Clear action when type changes
                            MP.editingMacro.recastSourceAction = nil;
                            MP.editingMacro.recastSourceItemId = nil;
                            MP.editorFields.recastSourceAction[1] = '';
                        end
                        if isSelected then MP.imgui.PopStyleColor(); end
                    end
                    MP.imgui.EndCombo();
                end
                MP.PopComboStyle();

                -- Show action selector based on recast source type
                currentRecastType = MP.RECAST_SOURCE_TYPES[MP.editorFields.recastSourceType[1]] or 'none';

                if currentRecastType == 'ma' then
                    MP.imgui.Spacing();
                    MP.imgui.TextColored(MP.COLORS.goldDim, 'Spell');
                    local spells = MP.GetCachedSpells();
                    if spells and #spells > 0 then
                        MP.DrawSearchableCombo('##recastSpellCombo', spells, MP.editingMacro.recastSourceAction or '', function(spell)
                            MP.editingMacro.recastSourceAction = spell.name;
                            MP.editorFields.recastSourceAction[1] = spell.name;
                        end, nil, nil, fieldW);
                    else
                        MP.imgui.TextColored(MP.COLORS.textMuted, 'No spells available');
                    end

                elseif currentRecastType == 'ja' then
                    MP.imgui.Spacing();
                    MP.imgui.TextColored(MP.COLORS.goldDim, 'Ability');
                    local abilities = MP.GetCachedAbilities();
                    if abilities and #abilities > 0 then
                        MP.DrawSearchableCombo('##recastAbilityCombo', abilities, MP.editingMacro.recastSourceAction or '', function(ability)
                            MP.editingMacro.recastSourceAction = ability.name;
                            MP.editorFields.recastSourceAction[1] = ability.name;
                        end, nil, nil, fieldW);
                    else
                        MP.imgui.TextColored(MP.COLORS.textMuted, 'No abilities available');
                    end

                elseif currentRecastType == 'item' then
                    MP.imgui.Spacing();
                    MP.imgui.TextColored(MP.COLORS.goldDim, 'Item');
                    local items = MP.GetCachedItems();
                    if items and #items > 0 then
                        MP.DrawSearchableCombo('##recastItemCombo', items, MP.editingMacro.recastSourceAction or '', function(item)
                            MP.editingMacro.recastSourceAction = item.name;
                            MP.editingMacro.recastSourceItemId = item.id;
                            MP.editorFields.recastSourceAction[1] = item.name;
                        end, true, nil, fieldW);  -- Show icons
                    else
                        MP.imgui.TextColored(MP.COLORS.textMuted, 'No items available');
                    end

                elseif currentRecastType == 'pet' then
                    MP.imgui.Spacing();
                    MP.imgui.TextColored(MP.COLORS.goldDim, 'Pet Command');
                    local viewedJobId = GetEditorPetJobId();
                    local avatarName = nil;
                    if viewedJobId == MP.petregistry.JOB_SMN then
                        avatarName = SmnAvatarNameFromEditorFilter(MP.petregistry.GetAvatarList());
                    end
                    local petCommands = MP.GetPetCommandsForJob(viewedJobId, avatarName, nil);
                    if petCommands and #petCommands > 0 then
                        MP.DrawSearchableCombo('##recastPetCombo', petCommands, MP.editingMacro.recastSourceAction or '', function(cmd)
                            MP.editingMacro.recastSourceAction = cmd.name;
                            MP.editorFields.recastSourceAction[1] = cmd.name;
                        end, nil, nil, fieldW);
                    else
                        MP.imgui.TextColored(MP.COLORS.textMuted, 'No pet commands available');
                    end
                end

                MP.imgui.TreePop();
            end

        elseif currentType == 'pet' then
            -- ── Pet Type selector ──────────────────────────────────
            local PET_TYPE_OPTIONS = {
                { id = MP.petregistry.JOB_SMN, label = 'Avatar (SMN)' },
                { id = MP.petregistry.JOB_BST, label = 'Beast (BST)' },
                { id = MP.petregistry.JOB_DRG, label = 'Wyvern (DRG)' },
                { id = MP.petregistry.JOB_PUP, label = 'Automaton (PUP)' },
            };

            -- Resolve default pet type from player's current job
            local defaultPetJobId = GetEditorPetJobId();
            if not MP.petregistry.IsPetJob(defaultPetJobId) then
                defaultPetJobId = MP.petregistry.JOB_SMN;
            end

            local viewedJobId;
            if MP.petTypeOverride > 0 then
                viewedJobId = MP.petTypeOverride;
            else
                viewedJobId = defaultPetJobId;
            end

            -- Find the label for the current selection
            local petTypeLabel = '???';
            for _, opt in ipairs(PET_TYPE_OPTIONS) do
                if opt.id == viewedJobId then
                    petTypeLabel = opt.label;
                    break;
                end
            end

            MP.imgui.TextColored(MP.COLORS.goldDim, 'Pet Type');
            MP.PushComboStyle();
            MP.imgui.SetNextItemWidth(fieldW);
            if MP.imgui.BeginCombo('##petTypeSelector', petTypeLabel) then
                for _, opt in ipairs(PET_TYPE_OPTIONS) do
                    local isSelected = viewedJobId == opt.id;
                    local label = opt.label;
                    if opt.id == defaultPetJobId then
                        label = label .. '  [Current]';
                    end
                    if isSelected then MP.imgui.PushStyleColor(ImGuiCol_Text, MP.COLORS.gold); end
                    if MP.imgui.Selectable(label, isSelected) then
                        if viewedJobId ~= opt.id then
                            MP.petTypeOverride = opt.id;
                            MP.cachedPetCommands = nil;
                            MP.showAllPetMode = false;
                            MP.petAvatarFilter = 1;
                        end
                    end
                    if isSelected then MP.imgui.PopStyleColor(); end
                end
                MP.imgui.EndCombo();
            end
            MP.PopComboStyle();
            MP.imgui.Spacing();

            -- ── Avatar Filter (SMN only) ───────────────────────────
            local avatarList = MP.petregistry.GetAvatarList();
            if viewedJobId == MP.petregistry.JOB_SMN then
                MP.imgui.TextColored(MP.COLORS.goldDim, 'Avatar');
                MP.PushComboStyle();
                MP.imgui.SetNextItemWidth(fieldW);
                local filterLabel = MP.petAvatarFilter == 1 and 'All Avatars' or avatarList[MP.petAvatarFilter - 1];
                if MP.imgui.BeginCombo('##avatarFilter', filterLabel) then
                    local isAllSelected = MP.petAvatarFilter == 1;
                    if isAllSelected then MP.imgui.PushStyleColor(ImGuiCol_Text, MP.COLORS.gold); end
                    if MP.imgui.Selectable('All Avatars', isAllSelected) then
                        MP.petAvatarFilter = 1;
                        MP.cachedPetCommands = nil;
                    end
                    if isAllSelected then MP.imgui.PopStyleColor(); end

                    MP.imgui.Separator();

                    for i, avatar in ipairs(avatarList) do
                        local isSelected = MP.petAvatarFilter == i + 1;
                        if isSelected then MP.imgui.PushStyleColor(ImGuiCol_Text, MP.COLORS.gold); end
                        if MP.imgui.Selectable(avatar, isSelected) then
                            MP.petAvatarFilter = i + 1;
                            MP.cachedPetCommands = nil;
                        end
                        if isSelected then MP.imgui.PopStyleColor(); end
                    end
                    MP.imgui.EndCombo();
                end
                MP.PopComboStyle();
                MP.imgui.Spacing();
            end

            -- ── Show All toggle (SMN/BST only) ────────────────────
            local supportShowAll = (viewedJobId == MP.petregistry.JOB_SMN or viewedJobId == MP.petregistry.JOB_BST);

            MP.imgui.TextColored(MP.COLORS.goldDim, 'Pet Command');
            if supportShowAll then
                MP.imgui.SameLine();
                local showAllPet = { MP.showAllPetMode };
                if MP.imgui.Checkbox('Show All##showAllPet', showAllPet) then
                    MP.showAllPetMode = showAllPet[1];
                    MP.cachedPetCommands = nil;
                end
                MP.imgui.SameLine(0, 2);
                if viewedJobId == MP.petregistry.JOB_BST then
                    MP.imgui.ShowHelp('Green = available at your level, Red = too high level');
                else
                    MP.imgui.ShowHelp('Green = available at your level, Red = too high level.\nBlood pacts shown with level requirements.');
                end
            end

            -- ── Resolve player level for the selected pet job ──────
            local player = AshitaCore:GetMemoryManager():GetPlayer();
            local mainJobId = player and player:GetMainJob() or 0;
            local mainJobLevel = player and player:GetMainJobLevel() or 0;
            local subJobId = player and player:GetSubJob() or 0;
            local subJobLevel = player and player:GetSubJobLevel() or 0;

            local petJobLevel = 0;
            if viewedJobId == mainJobId then
                petJobLevel = mainJobLevel;
            elseif viewedJobId == subJobId then
                petJobLevel = subJobLevel;
            end

            -- ── Build the command list ─────────────────────────────
            local petCommands;
            local useStatusColors = false;

            if supportShowAll then
                -- SMN/BST: always use expanded data so level-gating is applied
                local avatarName = nil;
                local activePetName = nil;
                if viewedJobId == MP.petregistry.JOB_SMN then
                    avatarName = SmnAvatarNameFromEditorFilter(avatarList);
                elseif viewedJobId == MP.petregistry.JOB_BST then
                    activePetName = MP.petpalette.GetCurrentPetEntityName();
                end

                local expandedList;
                if viewedJobId == MP.petregistry.JOB_BST then
                    expandedList = MP.petregistry.GetBstPetCommandsExpanded(petJobLevel, activePetName);
                else
                    expandedList = MP.petregistry.GetBloodPactsExpanded(avatarName, petJobLevel);
                end

                if MP.showAllPetMode then
                    petCommands = expandedList;
                    useStatusColors = true;
                else
                    petCommands = {};
                    for _, cmd in ipairs(expandedList) do
                        if cmd.status == MP.petregistry.STATUS_HAVE then
                            table.insert(petCommands, cmd);
                        end
                    end
                end
            else
                -- DRG/PUP: standard cached list
                if not MP.cachedPetCommands then
                    MP.cachedPetCommands = MP.GetPetCommandsForJob(viewedJobId, nil, nil);
                end
                petCommands = MP.cachedPetCommands;
            end

            -- ── Pet command selector dropdown ──────────────────────
            MP.imgui.SetNextItemWidth(fieldW);
            if petCommands and #petCommands > 0 then
                MP.DrawSearchableCombo('##petCommandCombo', petCommands, MP.editingMacro.action or '', function(cmd)
                    MP.editingMacro.action = cmd.name;
                    MP.editorFields.action[1] = cmd.name;
                    AutoSetDisplayName(cmd.name);
                    SyncEditorIconAfterListPick();
                end, nil, nil, fieldW, useStatusColors);
            else
                MP.imgui.TextColored(MP.COLORS.textMuted, 'No pet commands available');
            end

            MP.imgui.Spacing();
            MP.imgui.TextColored(MP.COLORS.goldDim, 'Or type manually:');
            MP.imgui.SetNextItemWidth(fieldW);
            if MP.imgui.InputText('##petCommandManual', MP.editorFields.action, MP.INPUT_BUFFER_SIZE) then
                MP.editingMacro.action = MP.editorFields.action[1];
                AutoSetDisplayName(MP.editingMacro.action);
                if (MP.editingMacro.action or '') ~= '' then
                    TryFirstImplicitActionIconAuto();
                end
            end

            -- Target dropdown
            MP.imgui.Spacing();
            MP.imgui.TextColored(MP.COLORS.goldDim, 'Target');
            MP.PushComboStyle();
            MP.imgui.SetNextItemWidth(fieldW);
            if MP.imgui.BeginCombo('##targetType', MP.TARGET_LABELS[MP.TARGET_OPTIONS[MP.editorFields.target[1]]] or 'Select...') then
                for i, target in ipairs(MP.TARGET_OPTIONS) do
                    local isSelected = MP.editorFields.target[1] == i;
                    if isSelected then MP.imgui.PushStyleColor(ImGuiCol_Text, MP.COLORS.gold); end
                    if MP.imgui.Selectable(MP.TARGET_LABELS[target], isSelected) then
                        MP.editorFields.target[1] = i;
                        MP.editingMacro.target = target;
                    end
                    if isSelected then MP.imgui.PopStyleColor(); end
                end
                MP.imgui.EndCombo();
            end
            MP.PopComboStyle();
        end

        -- Ensure we're past both left column and icon panel before continuing
        local yAfterFields = MP.imgui.GetCursorPosY();
        local yAfterIconPanel = topY + iconPanelTotalH + 4;
        if yAfterIconPanel > yAfterFields then
            MP.imgui.SetCursorPosY(yAfterIconPanel);
        end

        -- Slot Label input (for all types)
        MP.imgui.Spacing();
        MP.imgui.Separator();
        MP.imgui.Spacing();
        MP.imgui.TextColored(MP.COLORS.goldDim, 'Slot Label');
        MP.imgui.SameLine(0, 6);
        if MP.DrawIconButton('##macroEditorSlotLabelReset', uiIconRefresh, miniToolBtn, false,
                'Clear slot label (on save, uses action name, or "Macro" for macro type)') then
            MP.editingMacro.displayName = '';
            MP.editorFields.displayName[1] = '';
            MP.editorAutoLabel = nil;
        end
        if currentType == 'macro' then
            MP.imgui.SameLine(0, 4);
            if MP.DrawIconButton('##macroEditorSlotLabelSync', uiIconSync, miniToolBtn, false,
                    'Sync label from parsed macro (prioritized /ws > /ma > /pet > /ja )') then
                SyncMacroSlotLabelFromParsedCommands();
            end
        end
        MP.imgui.SameLine(0, 6);
        MP.imgui.SetNextItemWidth(math.max(80, contentWidth * 0.45));
        if MP.imgui.InputText('##displayName', MP.editorFields.displayName, 32) then
            MP.editingMacro.displayName = MP.editorFields.displayName[1];
            MP.editorAutoLabel = nil; -- User manually edited the label; don't auto-overwrite on future selections.
        end
        if currentType ~= 'macro' then
            MP.imgui.ShowHelp('Short label shown on the slot (e.g., "Cure3"). Leave empty to use action name.');
        else
            MP.imgui.ShowHelp('Label on the slot. Sync sets it from the prioritized command in macro text (same order as icon sync).');
        end

        MP.imgui.Spacing();
        MP.imgui.Separator();
        MP.imgui.Spacing();

        local function SaveMacro(shouldCloseEditor)
            -- Validate before saving
            local canSave = false;

            if currentType == 'macro' then
                canSave = (MP.editingMacro.macroText or '') ~= '';
                if canSave and (MP.editingMacro.displayName or '') == '' then
                    MP.editingMacro.displayName = 'Macro';
                end
                -- Clear target for macro type (targets are embedded in macro text)
                MP.editingMacro.target = nil;
            else
                canSave = (MP.editingMacro.action or '') ~= '';
                if canSave and (MP.editingMacro.displayName or '') == '' then
                    MP.editingMacro.displayName = MP.editingMacro.action;
                end
            end

            if not canSave then
                return;
            end

            -- Look up itemId for item/equip macros if not already set
            -- This handles cases where user typed item name manually instead of selecting from dropdown
            if (currentType == 'item' or currentType == 'equip') and not MP.editingMacro.itemId and MP.editingMacro.action then
                MP.editingMacro.itemId = MP.actiondb.GetItemId(MP.editingMacro.action);
            end

            if MP.isCreatingNew then
                -- AddMacro mutates macroData.id; keep editor selections by inserting a copy.
                local macroCopy = deep_copy_table(MP.editingMacro);
                macroCopy.id = nil;
                MP.M.AddMacro(macroCopy, MP.editorPaletteKey);
                -- Navigate to last page to show the new macro
                local db = MP.M.GetMacroDatabase();
                MP.currentPalettePage = math.max(1, math.ceil(#db / MP.PALETTE_MACROS_PER_PAGE));

                -- Ensure editor stays in "Create" mode (no id should be present)
                MP.editingMacro.id = nil;
            else
                MP.M.UpdateMacro(MP.editingMacro.id, MP.editingMacro, MP.editorPaletteKey);
            end

            MP.paletteMainIconCache = {};
            if MP.ClearPaletteJaBadgeIconCache then
                MP.ClearPaletteJaBadgeIconCache();
            end

            if shouldCloseEditor then
                MP.editingMacro = nil;
                MP.isCreatingNew = false;
                MP.searchFilter[1] = '';
                MP.iconPickerOpen = false;
                MP.iconPickerFilter[1] = '';
                MP.editorPaletteKey = nil;
                MP.editorDidInitialIconPick = false;
                MP.editorJaBadgeManuallySet = false;
                MP.ClearEditorPreviewIconCache();
            end
        end

        -- Save buttons
        MP.imgui.PushStyleColor(ImGuiCol_Button, MP.COLORS.success);
        MP.imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0.5, 0.8, 0.5, 1.0});
        MP.imgui.PushStyleColor(ImGuiCol_ButtonActive, {0.6, 0.9, 0.6, 1.0});
        MP.imgui.PushStyleColor(ImGuiCol_Text, {0.1, 0.1, 0.1, 1.0});

        if MP.imgui.Button('Save & Close', {110, 28}) then
            SaveMacro(true);
        end

        MP.imgui.SameLine(0, 8);

        if MP.imgui.Button('Save & Add Another', {150, 28}) then
            SaveMacro(false);
        end

        MP.imgui.PopStyleColor(4);

        MP.imgui.SameLine(0, 12);

        if MP.imgui.Button('Cancel', {80, 28}) then
            MP.editingMacro = nil;
            MP.isCreatingNew = false;
            MP.searchFilter[1] = '';
            MP.iconPickerOpen = false;
            MP.iconPickerFilter[1] = '';
            MP.editorPaletteKey = nil;
            MP.editorDidInitialIconPick = false;
            MP.editorJaBadgeManuallySet = false;
            MP.ClearEditorPreviewIconCache();
        end
    end

    MP.imgui.End();
    MP.PopWindowStyle();

    if not isOpen[1] then
        MP.editingMacro = nil;
        MP.isCreatingNew = false;
        MP.searchFilter[1] = '';
        MP.iconPickerOpen = false;
        MP.iconPickerFilter[1] = '';
        MP.editorPaletteKey = nil;
        MP.editorJaBadgeManuallySet = false;
        MP.ClearEditorPreviewIconCache();
    end

    -- Draw icon picker if open
    MP.DrawIconPicker();
    end
end
