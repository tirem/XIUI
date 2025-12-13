--[[
    Mob Info Display Module for XIUI
    Displays mob detection methods, level, resistances, weaknesses, and immunities
    as icons with tooltips in a separate movable window.

    Uses icons from MobDB (ThornyFFXI/mobdb) - MIT License
    https://github.com/ThornyFFXI/mobdb
]]

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local gdi = require('submodules.gdifonts.include');
local ffi = require("ffi");
local mobdata = require('modules.mobinfo.data');
local targetbar = require('modules.targetbar');

local mobinfo = {};

-- Texture cache for icons
local textures = {
    -- Detection method icons
    detection = {},
    -- Element icons (for resistances/weaknesses)
    elements = {},
    -- Physical damage type icons
    physical = {},
    -- Immunity icons
    immunities = {},
};

-- Font objects
local fonts = {
    header = nil,       -- Job + Level text
    separator = {},     -- Pool of separator fonts (|)
    modifier = {},      -- Pool of modifier fonts (+25%, -50%)
    serverId = nil,     -- Server ID text
};
local allFonts = {};

-- Maximum pool sizes for dynamic text elements
local MAX_SEPARATORS = 6;   -- Max separators in single-row mode
local MAX_MODIFIERS = 16;   -- Max modifier texts (weaknesses + resistances)

-- Cached colors
local lastTextColor;

-- Detection method definitions with display info
local detectionMethods = {
    { key = 'sight', name = 'Sight', tooltip = 'Detects by sight (affected by Invisible)' },
    { key = 'truesight', name = 'True Sight', tooltip = 'Detects through Invisible' },
    { key = 'sound', name = 'Sound', tooltip = 'Detects by sound (affected by Sneak)' },
    { key = 'scent', name = 'Scent', tooltip = 'Detects low HP targets' },
    { key = 'magic', name = 'Magic', tooltip = 'Detects magic casting' },
    { key = 'ja', name = 'Job Abilities', tooltip = 'Detects job ability usage' },
    { key = 'blood', name = 'Blood', tooltip = 'Detects by blood (undead)' },
};

-- Element definitions with display info
local elements = {
    { key = 'Fire', name = 'Fire', color = 0xFFFF4444 },
    { key = 'Ice', name = 'Ice', color = 0xFF44AAFF },
    { key = 'Wind', name = 'Wind', color = 0xFF44FF44 },
    { key = 'Earth', name = 'Earth', color = 0xFFBB8844 },
    { key = 'Lightning', name = 'Lightning', color = 0xFFFFFF44 },
    { key = 'Water', name = 'Water', color = 0xFF4488FF },
    { key = 'Light', name = 'Light', color = 0xFFFFFFFF },
    { key = 'Dark', name = 'Dark', color = 0xFF8844BB },
};

-- Physical damage type definitions
local physicalTypes = {
    { key = 'Slashing', name = 'Slashing' },
    { key = 'Piercing', name = 'Piercing' },
    { key = 'H2H', name = 'Hand-to-Hand' },
    { key = 'Impact', name = 'Impact/Blunt' },
};

-- Immunity definitions
local immunityTypes = {
    { key = 'Sleep', name = 'Sleep' },
    { key = 'Gravity', name = 'Gravity' },
    { key = 'Bind', name = 'Bind' },
    { key = 'Stun', name = 'Stun' },
    { key = 'Silence', name = 'Silence' },
    { key = 'Paralyze', name = 'Paralyze' },
    { key = 'Blind', name = 'Blind' },
    { key = 'Slow', name = 'Slow' },
    { key = 'Poison', name = 'Poison' },
    { key = 'Elegy', name = 'Elegy' },
    { key = 'Requiem', name = 'Requiem' },
    { key = 'Petrify', name = 'Petrify' },
    { key = 'DarkSleep', name = 'Dark Sleep' },
    { key = 'LightSleep', name = 'Light Sleep' },
};

-- Helper to load a texture from mobinfo assets
local function LoadMobInfoTexture(name)
    local texture_ptr = ffi.new('IDirect3DTexture8*[1]');
    local device = GetD3D8Device();
    if device == nil then
        return nil;
    end

    local path = string.format('%s/submodules/mobdb/addons/mobdb/icons/%s.png', addon.path, name);
    local res = ffi.C.D3DXCreateTextureFromFileA(device, path, texture_ptr);

    if res ~= 0 then
        -- Texture failed to load - this is expected if file doesn't exist
        return nil;
    end

    return { image = texture_ptr[0] };
end

-- Helper to update font color if changed
local function UpdateFontColor(font, color)
    if lastTextColor ~= color then
        font:set_font_color(color);
    end
end

-- Draw a single icon with tooltip, returns width
local function DrawIconWithTooltip(texture, size, tooltipText)
    local posX, posY = imgui.GetCursorScreenPos();

    if texture == nil or texture.image == nil then
        -- Draw a placeholder square if texture is missing
        local draw_list = imgui.GetWindowDrawList();
        draw_list:AddRectFilled(
            {posX, posY},
            {posX + size, posY + size},
            0xFF888888, -- Gray placeholder
            2.0
        );
    else
        -- Draw icon with no tint (white = original colors)
        local draw_list = imgui.GetWindowDrawList();
        draw_list:AddImage(
            tonumber(ffi.cast("uint32_t", texture.image)),
            {posX, posY},
            {posX + size, posY + size},
            {0, 0}, {1, 1},
            0xFFFFFFFF -- White (no tint)
        );
    end

    -- Always use Dummy to advance cursor and enable hover detection
    imgui.Dummy({size, size});

    if tooltipText and imgui.IsItemHovered() then
        imgui.SetTooltip(tooltipText);
    end

    return size;
end

-- Build detection icons array
local function BuildDetectionIcons(mobInfo)
    local detectionIcons = {};
    local methods = mobdata.GetDetectionMethods(mobInfo);
    local isNM = mobInfo.Notorious;

    -- Aggro/Passive indicator first (always show one or the other)
    if mobInfo.Aggro then
        -- Aggressive: use HQ icon for NMs, NQ for normal mobs
        local aggroTexture = isNM and textures.detection.aggroHQ or textures.detection.aggroNQ;
        table.insert(detectionIcons, {
            texture = aggroTexture,
            tooltip = isNM and 'Aggressive (NM)' or 'Aggressive'
        });
    else
        -- Passive: use HQ icon for NMs, NQ for normal mobs
        local passiveTexture = isNM and textures.detection.passiveHQ or textures.detection.passiveNQ;
        table.insert(detectionIcons, {
            texture = passiveTexture,
            tooltip = isNM and 'Passive (NM)' or 'Passive'
        });
    end

    -- Link indicator
    if gConfig.mobInfoShowLink and mobInfo.Link then
        table.insert(detectionIcons, {
            texture = textures.detection.link,
            tooltip = 'Links with nearby mobs'
        });
    end

    -- Detection methods
    for _, method in ipairs(detectionMethods) do
        if methods[method.key] then
            table.insert(detectionIcons, {
                texture = textures.detection[method.key],
                tooltip = method.name .. ': ' .. method.tooltip
            });
        end
    end

    return detectionIcons;
end

-- Build weakness icons array (sorted by percentage, grouped for display)
local function BuildWeaknessIcons(mobInfo)
    local weaknessIcons = {};
    local weaknesses = mobdata.GetWeaknesses(mobInfo);

    -- Collect all weaknesses with their raw modifier value
    local allWeaknesses = {};

    -- Elements
    for _, elem in ipairs(elements) do
        if weaknesses[elem.key] then
            local modifier = weaknesses[elem.key];
            table.insert(allWeaknesses, {
                texture = textures.elements[string.lower(elem.key)],
                name = elem.name,
                modifier = modifier
            });
        end
    end

    -- Physical types
    for _, phys in ipairs(physicalTypes) do
        if weaknesses[phys.key] then
            local modifier = weaknesses[phys.key];
            table.insert(allWeaknesses, {
                texture = textures.physical[string.lower(phys.key)],
                name = phys.name,
                modifier = modifier
            });
        end
    end

    -- Sort by modifier value (highest weakness first, like MobDB)
    table.sort(allWeaknesses, function(a, b)
        return a.modifier > b.modifier;
    end);

    -- Build final icon list with showPercent flag
    local groupModifiers = gConfig.mobInfoGroupModifiers;
    for i, item in ipairs(allWeaknesses) do
        local percent = math.floor((item.modifier - 1) * 100);
        -- When grouping: show percent only if this is the last icon OR the next icon has a different percentage
        -- When not grouping: always show percent for each icon
        local showPercent = true;
        if groupModifiers then
            local nextItem = allWeaknesses[i + 1];
            showPercent = (nextItem == nil) or (math.floor((nextItem.modifier - 1) * 100) ~= percent);
        end

        table.insert(weaknessIcons, {
            texture = item.texture,
            -- Use %% to escape % for imgui.SetTooltip (printf-style function)
            tooltip = item.name .. ' Weakness (+' .. tostring(percent) .. '%% damage)',
            modifierText = '+' .. percent .. '%',
            showPercent = showPercent
        });
    end

    return weaknessIcons;
end

-- Build resistance icons array (sorted by percentage, grouped for display)
local function BuildResistanceIcons(mobInfo)
    local resistanceIcons = {};
    local resistances = mobdata.GetResistances(mobInfo);

    -- Collect all resistances with their raw modifier value
    local allResistances = {};

    -- Elements
    for _, elem in ipairs(elements) do
        if resistances[elem.key] then
            local modifier = resistances[elem.key];
            table.insert(allResistances, {
                texture = textures.elements[string.lower(elem.key)],
                name = elem.name,
                modifier = modifier
            });
        end
    end

    -- Physical types
    for _, phys in ipairs(physicalTypes) do
        if resistances[phys.key] then
            local modifier = resistances[phys.key];
            table.insert(allResistances, {
                texture = textures.physical[string.lower(phys.key)],
                name = phys.name,
                modifier = modifier
            });
        end
    end

    -- Sort by modifier value (lowest/strongest resistance first, like MobDB)
    table.sort(allResistances, function(a, b)
        return a.modifier < b.modifier;
    end);

    -- Build final icon list with showPercent flag
    local groupModifiers = gConfig.mobInfoGroupModifiers;
    for i, item in ipairs(allResistances) do
        local percent = math.floor((1 - item.modifier) * 100);
        -- When grouping: show percent only if this is the last icon OR the next icon has a different percentage
        -- When not grouping: always show percent for each icon
        local showPercent = true;
        if groupModifiers then
            local nextItem = allResistances[i + 1];
            showPercent = (nextItem == nil) or (math.floor((1 - nextItem.modifier) * 100) ~= percent);
        end

        table.insert(resistanceIcons, {
            texture = item.texture,
            -- Use %% to escape % for imgui.SetTooltip (printf-style function)
            tooltip = item.name .. ' Resistance (-' .. tostring(percent) .. '%% damage)',
            modifierText = '-' .. percent .. '%',
            showPercent = showPercent
        });
    end

    return resistanceIcons;
end

-- Build immunity icons array
local function BuildImmunityIcons(mobInfo)
    local immunityIcons = {};
    local immunities = mobdata.GetImmunities(mobInfo);

    for _, imm in ipairs(immunityTypes) do
        if immunities[imm.key] then
            table.insert(immunityIcons, {
                texture = textures.immunities[string.lower(imm.key)],
                tooltip = 'Immune to ' .. imm.name
            });
        end
    end

    return immunityIcons;
end

-- Hide all fonts
local function HideAllFonts()
    SetFontsVisible(allFonts, false);
end

-- Calculate width of icons with modifiers (for positioning)
-- Only counts modifier text width for icons where showPercent is true (grouped display)
local function CalculateIconsWidth(icons, iconSize, spacing, fontHeight, modifierFontPool, modifierIndex)
    local totalWidth = 0;
    local usedModifiers = modifierIndex;

    for i, iconData in ipairs(icons) do
        if i > 1 then
            totalWidth = totalWidth + spacing;
        end
        totalWidth = totalWidth + iconSize;

        -- Add modifier text width if enabled and this is the last icon in a percentage group
        if iconData.modifierText and gConfig.mobInfoShowModifierText and iconData.showPercent then
            local modFont = modifierFontPool[usedModifiers];
            if modFont then
                modFont:set_font_height(fontHeight);
                modFont:set_text(iconData.modifierText);
                local textW, _ = modFont:get_text_size();
                totalWidth = totalWidth + 2 + textW; -- 2px gap + text
                usedModifiers = usedModifiers + 1;
            end
        end
    end

    return totalWidth, usedModifiers;
end

-- Draw icons with optional modifier text using GDI fonts
-- baseX is the absolute X position where this section starts
-- Returns the total width consumed and new modifier index
-- Icons are grouped by percentage - only shows % after last icon in each group (when showPercent is true)
local function DrawIconsWithModifiers(icons, iconSize, spacing, fontHeight, textColor, modifierFontPool, modifierIndex, baseX, baseY)
    local offsetX = 0;
    local usedModifiers = modifierIndex;

    for i, iconData in ipairs(icons) do
        if i > 1 then
            imgui.SameLine(0, spacing);
            offsetX = offsetX + spacing;
        end

        DrawIconWithTooltip(iconData.texture, iconSize, iconData.tooltip);
        offsetX = offsetX + iconSize;

        -- Draw modifier text if enabled, available, and this is the last icon in the percentage group
        -- showPercent is set during icon building to group same-percentage modifiers
        if iconData.modifierText and gConfig.mobInfoShowModifierText and iconData.showPercent then
            local modFont = modifierFontPool[usedModifiers];
            if modFont then
                modFont:set_font_height(fontHeight);
                modFont:set_text(iconData.modifierText);
                UpdateFontColor(modFont, textColor);

                local textW, textH = modFont:get_text_size();
                local textX = baseX + offsetX + 2;
                local textY = baseY + (iconSize - textH) / 2; -- Vertically center

                imgui.SameLine(0, 2);
                offsetX = offsetX + 2;

                modFont:set_position_x(textX);
                modFont:set_position_y(textY);
                modFont:set_visible(true);

                imgui.Dummy({textW, iconSize});
                offsetX = offsetX + textW;

                usedModifiers = usedModifiers + 1;
            end
        end
    end

    return offsetX, usedModifiers;
end

-- Draw a separator using GDI font at absolute position
-- Returns the total width consumed (including padding) and the next separator index
-- Separator style is controlled by gConfig.mobInfoSeparatorStyle: 'space', 'pipe', 'dot'
local function DrawGdiSeparator(separatorPool, sepIndex, fontHeight, textColor, posX, posY, iconSize)
    local separatorStyle = gConfig.mobInfoSeparatorStyle or 'space';

    -- Space separator: just return spacing, don't draw anything
    if separatorStyle == 'space' then
        return 8, sepIndex; -- 8px spacing between sections
    end

    local sepFont = separatorPool[sepIndex];
    if not sepFont then
        return 0, sepIndex;
    end

    -- Determine separator character
    local sepChar = '|';
    if separatorStyle == 'dot' then
        sepChar = '\194\183'; -- UTF-8 encoding of middle dot (·)
    end

    sepFont:set_font_height(fontHeight);
    sepFont:set_text(sepChar);
    UpdateFontColor(sepFont, textColor);

    local textW, textH = sepFont:get_text_size();
    local textY = posY + (iconSize - textH) / 2; -- Vertically center

    -- Position: 4px padding, then separator, then 4px padding
    sepFont:set_position_x(posX + 4);
    sepFont:set_position_y(textY);
    sepFont:set_visible(true);

    return textW + 8, sepIndex + 1; -- 4px padding on each side
end

-- Draw icons without modifiers (detection, immunity)
-- Returns total width consumed
local function DrawIconsSimple(icons, iconSize, spacing)
    local totalWidth = 0;
    for i, iconData in ipairs(icons) do
        if i > 1 then
            imgui.SameLine(0, spacing);
            totalWidth = totalWidth + spacing;
        end
        DrawIconWithTooltip(iconData.texture, iconSize, iconData.tooltip);
        totalWidth = totalWidth + iconSize;
    end
    return totalWidth;
end

--[[
* event: d3d_present
* desc : Event called when the Direct3D device is presenting a scene.
--]]
mobinfo.DrawWindow = function(settings)
    -- Check if enabled
    if not gConfig.showMobInfo then
        HideAllFonts();
        return;
    end

    -- Obtain the player entity
    local player = GetPlayerSafe();
    local playerEnt = GetPlayerEntity();

    if player == nil or playerEnt == nil then
        HideAllFonts();
        return;
    end

    if player.isZoning then
        HideAllFonts();
        return;
    end

    -- Hide when engaged if setting is enabled
    if gConfig.mobInfoHideWhenEngaged then
        local entityMgr = AshitaCore:GetMemoryManager():GetEntity();
        local partyMgr = AshitaCore:GetMemoryManager():GetParty();
        if entityMgr and partyMgr then
            local playerIndex = partyMgr:GetMemberTargetIndex(0);
            local playerStatus = entityMgr:GetStatus(playerIndex);
            -- Status 1 = Engaged in combat
            if playerStatus == 1 then
                HideAllFonts();
                return;
            end
        end
    end

    -- Obtain the player target entity
    local playerTarget = GetTargetSafe();
    local targetIndex;
    local targetEntity;
    if playerTarget ~= nil then
        targetIndex, _ = GetTargets();
        targetEntity = GetEntity(targetIndex);
    end

    if targetEntity == nil or targetEntity.Name == nil then
        HideAllFonts();
        return;
    end

    -- Only show for mobs
    local isMonster = GetIsMob(targetEntity);
    if not isMonster then
        HideAllFonts();
        return;
    end

    -- Get mob info from database (pass index for spawn-specific job data)
    local mobInfo = mobdata.GetMobInfo(targetEntity.Name, targetIndex);

    -- If no data and we don't want to show "no data" window, hide
    if mobInfo == nil and not gConfig.mobInfoShowNoData then
        HideAllFonts();
        return;
    end

    -- Calculate icon size with scale
    local iconSize = settings.iconSize * gConfig.mobInfoIconScale;
    local spacing = settings.iconSpacing;
    local singleRow = gConfig.mobInfoSingleRow;
    local fontHeight = settings.level_font_settings.font_height;
    local textColor = gConfig.colorCustomization.mobInfo.levelTextColor;

    -- Check if we should snap to target bar
    local snapToTargetBar = gConfig.mobInfoSnapToTargetBar and targetbar.nameTextInfo.visible;

    -- Setup window
    imgui.SetNextWindowSize({-1, -1}, ImGuiCond_Always);

    -- If snapping to target bar, position the window at the target name end position
    if snapToTargetBar then
        -- Calculate Y offset: mob info text is vertically centered within iconSize,
        -- so we need to offset to align text baselines with target name
        local textCenterOffset = (iconSize - fontHeight) / 2;
        local snapY = targetbar.nameTextInfo.y - textCenterOffset;
        imgui.SetNextWindowPos({targetbar.nameTextInfo.x, snapY}, ImGuiCond_Always);
        -- Remove window padding to align precisely with target name
        imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {0, 0});
    end

    local windowFlags = bit.bor(
        ImGuiWindowFlags_NoDecoration,
        ImGuiWindowFlags_AlwaysAutoResize,
        ImGuiWindowFlags_NoFocusOnAppearing,
        ImGuiWindowFlags_NoNav,
        ImGuiWindowFlags_NoBackground,
        ImGuiWindowFlags_NoBringToFrontOnFocus,
        ImGuiWindowFlags_NoDocking
    );
    -- Lock position if global lock is on OR if snapping to target bar
    if gConfig.lockPositions or snapToTargetBar then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
    end

    -- Hide all fonts initially - we'll show only what we need
    HideAllFonts();

    if imgui.Begin('MobInfo', true, windowFlags) then
        -- If no data, show a simple message
        if mobInfo == nil then
            fonts.header:set_text('No mob data');
            fonts.header:set_font_height(fontHeight);
            UpdateFontColor(fonts.header, textColor);
            local startX, startY = imgui.GetCursorScreenPos();
            fonts.header:set_position_x(startX);
            fonts.header:set_position_y(startY);
            fonts.header:set_visible(true);
            local textW, textH = fonts.header:get_text_size();
            imgui.Dummy({textW, textH});
        else
            local startX, startY = imgui.GetCursorScreenPos();
            local cursorX, cursorY = startX, startY;
            local hasContent = false;

            -- Build all icon arrays
            local detectionIcons = gConfig.mobInfoShowDetection and BuildDetectionIcons(mobInfo) or {};
            local weaknessIcons = gConfig.mobInfoShowWeaknesses and BuildWeaknessIcons(mobInfo) or {};
            local resistanceIcons = gConfig.mobInfoShowResistances and BuildResistanceIcons(mobInfo) or {};
            local immunityIcons = gConfig.mobInfoShowImmunities and BuildImmunityIcons(mobInfo) or {};

            -- Get job string
            local jobString = gConfig.mobInfoShowJob and mobdata.GetJobString(mobInfo) or nil;

            -- Get level string
            local levelString = gConfig.mobInfoShowLevel and mobdata.GetLevelString(mobInfo) or '';

            -- Get server ID if enabled
            local serverIdString = nil;
            if gConfig.mobInfoShowServerId and targetEntity.ServerId then
                if gConfig.mobInfoServerIdHex then
                    serverIdString = string.format('[0x%X]', targetEntity.ServerId);
                else
                    serverIdString = string.format('[%d]', targetEntity.ServerId);
                end
            end

            -- Track separator and modifier font usage
            local separatorIndex = 1;
            local modifierIndex = 1;

            if singleRow then
                -- Single row layout: Job Level | Detection | Weaknesses | Resistances | Immunities | ServerId
                -- Track absolute X position for GDI font positioning
                local currentX = startX;

                -- Build the header text (job + level)
                local headerParts = {};
                if jobString then
                    table.insert(headerParts, jobString);
                end
                if levelString ~= '' then
                    table.insert(headerParts, levelString);
                end
                local headerText = table.concat(headerParts, ' ');

                -- Render header text with GDI font if we have any
                if headerText ~= '' then
                    fonts.header:set_font_height(fontHeight);
                    fonts.header:set_text(headerText);
                    UpdateFontColor(fonts.header, textColor);

                    local textW, textH = fonts.header:get_text_size();
                    local textY = startY + (iconSize - textH) / 2;
                    fonts.header:set_position_x(currentX);
                    fonts.header:set_position_y(textY);
                    fonts.header:set_visible(true);

                    imgui.Dummy({textW, iconSize});
                    currentX = currentX + textW;
                    hasContent = true;
                end

                -- Detection icons
                if #detectionIcons > 0 then
                    if hasContent then
                        local sepW;
                        sepW, separatorIndex = DrawGdiSeparator(fonts.separator, separatorIndex, fontHeight, textColor, currentX, startY, iconSize);
                        imgui.SameLine(0, 0);
                        imgui.Dummy({sepW, iconSize});
                        currentX = currentX + sepW;
                    end

                    imgui.SameLine(0, 0);
                    local iconsWidth = DrawIconsSimple(detectionIcons, iconSize, spacing);
                    currentX = currentX + iconsWidth;
                    hasContent = true;
                end

                -- Weakness icons with modifiers
                if #weaknessIcons > 0 then
                    if hasContent then
                        local sepW;
                        sepW, separatorIndex = DrawGdiSeparator(fonts.separator, separatorIndex, fontHeight, textColor, currentX, startY, iconSize);
                        imgui.SameLine(0, 0);
                        imgui.Dummy({sepW, iconSize});
                        currentX = currentX + sepW;
                    end

                    imgui.SameLine(0, 0);
                    local iconsWidth, newModIdx = DrawIconsWithModifiers(weaknessIcons, iconSize, spacing, fontHeight, textColor, fonts.modifier, modifierIndex, currentX, startY);
                    modifierIndex = newModIdx;
                    currentX = currentX + iconsWidth;
                    hasContent = true;
                end

                -- Resistance icons with modifiers
                if #resistanceIcons > 0 then
                    if hasContent then
                        local sepW;
                        sepW, separatorIndex = DrawGdiSeparator(fonts.separator, separatorIndex, fontHeight, textColor, currentX, startY, iconSize);
                        imgui.SameLine(0, 0);
                        imgui.Dummy({sepW, iconSize});
                        currentX = currentX + sepW;
                    end

                    imgui.SameLine(0, 0);
                    local iconsWidth, newModIdx = DrawIconsWithModifiers(resistanceIcons, iconSize, spacing, fontHeight, textColor, fonts.modifier, modifierIndex, currentX, startY);
                    modifierIndex = newModIdx;
                    currentX = currentX + iconsWidth;
                    hasContent = true;
                end

                -- Immunity icons
                if #immunityIcons > 0 then
                    if hasContent then
                        local sepW;
                        sepW, separatorIndex = DrawGdiSeparator(fonts.separator, separatorIndex, fontHeight, textColor, currentX, startY, iconSize);
                        imgui.SameLine(0, 0);
                        imgui.Dummy({sepW, iconSize});
                        currentX = currentX + sepW;
                    end

                    imgui.SameLine(0, 0);
                    local iconsWidth = DrawIconsSimple(immunityIcons, iconSize, spacing);
                    currentX = currentX + iconsWidth;
                    hasContent = true;
                end

                -- Server ID
                if serverIdString then
                    if hasContent then
                        local sepW;
                        sepW, separatorIndex = DrawGdiSeparator(fonts.separator, separatorIndex, fontHeight, textColor, currentX, startY, iconSize);
                        imgui.SameLine(0, 0);
                        imgui.Dummy({sepW, iconSize});
                        currentX = currentX + sepW;
                    end

                    fonts.serverId:set_font_height(fontHeight);
                    fonts.serverId:set_text(serverIdString);
                    UpdateFontColor(fonts.serverId, textColor);

                    local textW, textH = fonts.serverId:get_text_size();
                    local textY = startY + (iconSize - textH) / 2;
                    fonts.serverId:set_position_x(currentX);
                    fonts.serverId:set_position_y(textY);
                    fonts.serverId:set_visible(true);

                    imgui.SameLine(0, 0);
                    imgui.Dummy({textW, iconSize});
                    currentX = currentX + textW;
                    hasContent = true;
                end
            else
                -- Stacked layout (original behavior with new features)

                -- Job + Level display
                local showLevel = gConfig.mobInfoShowLevel and levelString ~= '';
                if jobString or showLevel then
                    local displayText = '';
                    if jobString then
                        displayText = jobString .. ' ';
                    end
                    if showLevel then
                        displayText = displayText .. 'Lv.' .. levelString;
                    end

                    fonts.header:set_font_height(fontHeight);
                    fonts.header:set_text(displayText);
                    UpdateFontColor(fonts.header, textColor);

                    local textW, textH = fonts.header:get_text_size();
                    fonts.header:set_position_x(startX);
                    fonts.header:set_position_y(startY);
                    fonts.header:set_visible(true);

                    imgui.Dummy({textW, textH});
                    hasContent = true;
                end

                -- Detection methods row
                if #detectionIcons > 0 then
                    if hasContent then
                        imgui.Spacing();
                    end
                    for i, iconData in ipairs(detectionIcons) do
                        if i > 1 then
                            imgui.SameLine(0, spacing);
                        end
                        DrawIconWithTooltip(iconData.texture, iconSize, iconData.tooltip);
                    end
                    hasContent = true;
                end

                -- Weaknesses row with modifiers
                if #weaknessIcons > 0 then
                    if hasContent then
                        imgui.Spacing();
                    end
                    cursorX, cursorY = imgui.GetCursorScreenPos();
                    local _, newModIdx = DrawIconsWithModifiers(weaknessIcons, iconSize, spacing, fontHeight, textColor, fonts.modifier, modifierIndex, cursorX, cursorY);
                    modifierIndex = newModIdx;
                    hasContent = true;
                end

                -- Resistances row with modifiers
                if #resistanceIcons > 0 then
                    if hasContent then
                        imgui.Spacing();
                    end
                    cursorX, cursorY = imgui.GetCursorScreenPos();
                    local _, newModIdx = DrawIconsWithModifiers(resistanceIcons, iconSize, spacing, fontHeight, textColor, fonts.modifier, modifierIndex, cursorX, cursorY);
                    modifierIndex = newModIdx;
                    hasContent = true;
                end

                -- Immunities row
                if #immunityIcons > 0 then
                    if hasContent then
                        imgui.Spacing();
                    end
                    for i, iconData in ipairs(immunityIcons) do
                        if i > 1 then
                            imgui.SameLine(0, spacing);
                        end
                        DrawIconWithTooltip(iconData.texture, iconSize, iconData.tooltip);
                    end
                    hasContent = true;
                end

                -- Server ID row
                if serverIdString then
                    if hasContent then
                        imgui.Spacing();
                    end
                    cursorX, cursorY = imgui.GetCursorScreenPos();

                    fonts.serverId:set_font_height(fontHeight);
                    fonts.serverId:set_text(serverIdString);
                    UpdateFontColor(fonts.serverId, textColor);

                    local textW, textH = fonts.serverId:get_text_size();
                    fonts.serverId:set_position_x(cursorX);
                    fonts.serverId:set_position_y(cursorY);
                    fonts.serverId:set_visible(true);

                    imgui.Dummy({textW, textH});
                    hasContent = true;
                end
            end

            -- Update cached color
            lastTextColor = textColor;
        end
    end
    imgui.End();

    -- Pop window padding style if we pushed it for snap mode
    if snapToTargetBar then
        imgui.PopStyleVar(1);
    end
end

mobinfo.Initialize = function(settings)
    -- Create font objects
    fonts.header = FontManager.create(settings.level_font_settings);
    fonts.serverId = FontManager.create(settings.level_font_settings);

    -- Create separator font pool
    fonts.separator = {};
    for i = 1, MAX_SEPARATORS do
        fonts.separator[i] = FontManager.create(settings.level_font_settings);
    end

    -- Create modifier font pool
    fonts.modifier = {};
    for i = 1, MAX_MODIFIERS do
        fonts.modifier[i] = FontManager.create(settings.level_font_settings);
    end

    -- Build allFonts array for batch operations
    allFonts = {fonts.header, fonts.serverId};
    for _, font in ipairs(fonts.separator) do
        table.insert(allFonts, font);
    end
    for _, font in ipairs(fonts.modifier) do
        table.insert(allFonts, font);
    end

    -- Load detection icons (HQ for NMs, NQ for normal mobs)
    textures.detection.aggroHQ = LoadMobInfoTexture('AggroHQ');
    textures.detection.aggroNQ = LoadMobInfoTexture('AggroNQ');
    textures.detection.passiveHQ = LoadMobInfoTexture('PassiveHQ');
    textures.detection.passiveNQ = LoadMobInfoTexture('PassiveNQ');
    textures.detection.link = LoadMobInfoTexture('Link');
    textures.detection.sight = LoadMobInfoTexture('Sight');
    textures.detection.truesight = LoadMobInfoTexture('TrueSight');
    textures.detection.sound = LoadMobInfoTexture('Sound');
    textures.detection.scent = LoadMobInfoTexture('Scent');
    textures.detection.magic = LoadMobInfoTexture('Magic');
    textures.detection.ja = LoadMobInfoTexture('JA');
    textures.detection.blood = LoadMobInfoTexture('Blood');

    -- Load element icons
    textures.elements.fire = LoadMobInfoTexture('Fire');
    textures.elements.ice = LoadMobInfoTexture('Ice');
    textures.elements.wind = LoadMobInfoTexture('Wind');
    textures.elements.earth = LoadMobInfoTexture('Earth');
    textures.elements.lightning = LoadMobInfoTexture('Lightning');
    textures.elements.water = LoadMobInfoTexture('Water');
    textures.elements.light = LoadMobInfoTexture('Light');
    textures.elements.dark = LoadMobInfoTexture('Dark');

    -- Load physical damage type icons
    textures.physical.slashing = LoadMobInfoTexture('Slashing');
    textures.physical.piercing = LoadMobInfoTexture('Piercing');
    textures.physical.h2h = LoadMobInfoTexture('H2H');
    textures.physical.impact = LoadMobInfoTexture('Impact');

    -- Load immunity icons
    textures.immunities.sleep = LoadMobInfoTexture('ImmuneSleep');
    textures.immunities.gravity = LoadMobInfoTexture('ImmuneGravity');
    textures.immunities.bind = LoadMobInfoTexture('ImmuneBind');
    textures.immunities.stun = LoadMobInfoTexture('ImmuneStun');
    textures.immunities.silence = LoadMobInfoTexture('ImmuneSilence');
    textures.immunities.paralyze = LoadMobInfoTexture('ImmuneParalyze');
    textures.immunities.blind = LoadMobInfoTexture('ImmuneBlind');
    textures.immunities.slow = LoadMobInfoTexture('ImmuneSlow');
    textures.immunities.poison = LoadMobInfoTexture('ImmunePoison');
    textures.immunities.elegy = LoadMobInfoTexture('ImmuneElegy');
    textures.immunities.requiem = LoadMobInfoTexture('ImmuneRequiem');
    textures.immunities.petrify = LoadMobInfoTexture('ImmunePetrify');
    textures.immunities.darksleep = LoadMobInfoTexture('ImmuneDarkSleep');
    textures.immunities.lightsleep = LoadMobInfoTexture('ImmuneLightSleep');
end

mobinfo.UpdateVisuals = function(settings)
    -- Recreate all fonts
    fonts.header = FontManager.recreate(fonts.header, settings.level_font_settings);
    fonts.serverId = FontManager.recreate(fonts.serverId, settings.level_font_settings);

    for i = 1, MAX_SEPARATORS do
        fonts.separator[i] = FontManager.recreate(fonts.separator[i], settings.level_font_settings);
    end

    for i = 1, MAX_MODIFIERS do
        fonts.modifier[i] = FontManager.recreate(fonts.modifier[i], settings.level_font_settings);
    end

    -- Rebuild allFonts array
    allFonts = {fonts.header, fonts.serverId};
    for _, font in ipairs(fonts.separator) do
        table.insert(allFonts, font);
    end
    for _, font in ipairs(fonts.modifier) do
        table.insert(allFonts, font);
    end

    -- Reset cached colors
    lastTextColor = nil;
end

mobinfo.SetHidden = function(hidden)
    if hidden == true then
        HideAllFonts();
    end
end

mobinfo.Cleanup = function()
    -- Destroy all fonts
    fonts.header = FontManager.destroy(fonts.header);
    fonts.serverId = FontManager.destroy(fonts.serverId);

    for i = 1, MAX_SEPARATORS do
        fonts.separator[i] = FontManager.destroy(fonts.separator[i]);
    end

    for i = 1, MAX_MODIFIERS do
        fonts.modifier[i] = FontManager.destroy(fonts.modifier[i]);
    end

    fonts = {
        header = nil,
        separator = {},
        modifier = {},
        serverId = nil,
    };
    allFonts = {};

    -- Textures are managed by D3D, no explicit cleanup needed
    textures = {
        detection = {},
        elements = {},
        physical = {},
        immunities = {},
    };
end

return mobinfo;
