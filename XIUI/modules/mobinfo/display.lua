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
local imtext = require('libs.imtext');
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

        -- Aggressive: use HQ icon for NMs, NQ for normal mobs
    if mobInfo.Aggro then
        local aggroTexture = isNM and textures.detection.aggroHQ or textures.detection.aggroNQ;
        table.insert(detectionIcons, {
            texture = aggroTexture,
            tooltip = isNM and 'Aggressive (NM)' or 'Aggressive'
        });
        -- Passive: use HQ icon for NMs, NQ for normal mobs
    else
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
        -- When grouping: show percent only if this is the last icon OR the next icon has a different percentage
        -- When not grouping: always show percent for each icon
        local percent = math.floor((item.modifier - 1) * 100);
        local showPercent = true;
        if groupModifiers then
            local nextItem = allWeaknesses[i + 1];
            showPercent = (nextItem == nil) or (math.floor((nextItem.modifier - 1) * 100) ~= percent);
        end

            -- Use %% to escape % for imgui.SetTooltip (printf-style function)
        table.insert(weaknessIcons, {
            texture = item.texture,
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
        -- When grouping: show percent only if this is the last icon OR the next icon has a different percentage
        -- When not grouping: always show percent for each icon
        local percent = math.floor((1 - item.modifier) * 100);
        local showPercent = true;
        if groupModifiers then
            local nextItem = allResistances[i + 1];
            showPercent = (nextItem == nil) or (math.floor((1 - nextItem.modifier) * 100) ~= percent);
        end

            -- Use %% to escape % for imgui.SetTooltip (printf-style function)
        table.insert(resistanceIcons, {
            texture = item.texture,
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

-- No-op: imtext is stateless, no fonts to hide
local function HideAllFonts()
end

-- Calculate width of icons with modifiers (for positioning)
local function CalculateIconsWidth(icons, iconSize, spacing, fontHeight)
    local totalWidth = 0;

    for i, iconData in ipairs(icons) do
        if i > 1 then
            totalWidth = totalWidth + spacing;
        end
        totalWidth = totalWidth + iconSize;

        if iconData.modifierText and gConfig.mobInfoShowModifierText and iconData.showPercent then
            local textW, _ = imtext.Measure(iconData.modifierText, fontHeight);
            totalWidth = totalWidth + 2 + textW;
        end
    end

    return totalWidth;
end

-- Draw icons with optional modifier text
-- Returns the total width consumed
local function DrawIconsWithModifiers(drawList, icons, iconSize, spacing, fontHeight, textColor, baseX, baseY)
    local offsetX = 0;

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
            local textW, textH = imtext.Measure(iconData.modifierText, fontHeight);
            local textX = baseX + offsetX + 2;
            local textY = baseY + (iconSize - textH) / 2;

            imgui.SameLine(0, 2);
            offsetX = offsetX + 2;

            imtext.Draw(drawList, iconData.modifierText, textX, textY, textColor, fontHeight);

            imgui.Dummy({textW, iconSize});
            offsetX = offsetX + textW;
        end
    end

    return offsetX;
end

-- Draw a separator at absolute position
-- Returns the total width consumed (including padding)
local function DrawSeparator(drawList, fontHeight, textColor, posX, posY, iconSize)
    local separatorStyle = gConfig.mobInfoSeparatorStyle or 'space';
    -- Space separator: just return spacing, don't draw anything

    if separatorStyle == 'space' then
        return 8;
    end
    -- Determine separator character

    local sepChar = '|';
    if separatorStyle == 'dot' then
        sepChar = string.char(194, 183); -- UTF-8 middle dot
    end

    local textW, textH = imtext.Measure(sepChar, fontHeight);
    local textY = posY + (iconSize - textH) / 2;

    imtext.Draw(drawList, sepChar, posX + 4, textY, textColor, fontHeight);

    return textW + 8;
end

-- Draw icons without modifiers (detection, immunity)
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
        return;
    end

    -- Obtain the player entity
    local player = GetPlayerSafe();
    local playerEnt = GetPlayerEntity();

    if player == nil or playerEnt == nil then
        return;
    end

    if player.isZoning then
        return;
    end

    -- Hide when engaged if setting is enabled
    if gConfig.mobInfoHideWhenEngaged then
        local entityMgr = AshitaCore:GetMemoryManager():GetEntity();
        local partyMgr = AshitaCore:GetMemoryManager():GetParty();
        if entityMgr and partyMgr then
            local playerIndex = partyMgr:GetMemberTargetIndex(0);
            local playerStatus = entityMgr:GetStatus(playerIndex);
            if playerStatus == 1 then -- Status 1 = Engaged in combat
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
        return;
    end

    -- Only show for mobs
    local isMonster = GetIsMob(targetEntity);
    if not isMonster then
        return;
    end

    -- Get mob info from database (pass index for spawn-specific job data)
    local mobInfo = mobdata.GetMobInfo(targetEntity.Name, targetIndex);

    -- If no data and we don't want to show "no data" window, hide
    if mobInfo == nil and not gConfig.mobInfoShowNoData then
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

    ApplyWindowPosition('MobInfo');
    if imgui.Begin('MobInfo', true, windowFlags) then
        SaveWindowPosition('MobInfo');
        local drawList = GetUIDrawList();
        imtext.SetConfigFromSettings(settings.level_font_settings);

        -- If no data, show a simple message
        if mobInfo == nil then
            local startX, startY = imgui.GetCursorScreenPos();
            local textW, textH = imtext.Measure('No mob data', fontHeight);
            imtext.Draw(drawList, 'No mob data', startX, startY, textColor, fontHeight);
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

            -- Single row layout: Job Level | Detection | Weaknesses | Resistances | Immunities | ServerId
            if singleRow then
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

                -- Render header text if we have any
                if headerText ~= '' then
                    local textW, textH = imtext.Measure(headerText, fontHeight);
                    local textY = startY + (iconSize - textH) / 2;
                    imtext.Draw(drawList, headerText, currentX, textY, textColor, fontHeight);

                    imgui.Dummy({textW, iconSize});
                    currentX = currentX + textW;
                    hasContent = true;
                end

                -- Detection icons
                if #detectionIcons > 0 then
                    if hasContent then
                        local sepW = DrawSeparator(drawList, fontHeight, textColor, currentX, startY, iconSize);
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
                        local sepW = DrawSeparator(drawList, fontHeight, textColor, currentX, startY, iconSize);
                        imgui.SameLine(0, 0);
                        imgui.Dummy({sepW, iconSize});
                        currentX = currentX + sepW;
                    end

                    imgui.SameLine(0, 0);
                    local iconsWidth = DrawIconsWithModifiers(drawList, weaknessIcons, iconSize, spacing, fontHeight, textColor, currentX, startY);
                    currentX = currentX + iconsWidth;
                    hasContent = true;
                end

                -- Resistance icons with modifiers
                if #resistanceIcons > 0 then
                    if hasContent then
                        local sepW = DrawSeparator(drawList, fontHeight, textColor, currentX, startY, iconSize);
                        imgui.SameLine(0, 0);
                        imgui.Dummy({sepW, iconSize});
                        currentX = currentX + sepW;
                    end

                    imgui.SameLine(0, 0);
                    local iconsWidth = DrawIconsWithModifiers(drawList, resistanceIcons, iconSize, spacing, fontHeight, textColor, currentX, startY);
                    currentX = currentX + iconsWidth;
                    hasContent = true;
                end

                -- Immunity icons
                if #immunityIcons > 0 then
                    if hasContent then
                        local sepW = DrawSeparator(drawList, fontHeight, textColor, currentX, startY, iconSize);
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
                        local sepW = DrawSeparator(drawList, fontHeight, textColor, currentX, startY, iconSize);
                        imgui.SameLine(0, 0);
                        imgui.Dummy({sepW, iconSize});
                        currentX = currentX + sepW;
                    end

                    local textW, textH = imtext.Measure(serverIdString, fontHeight);
                    local textY = startY + (iconSize - textH) / 2;
                    imtext.Draw(drawList, serverIdString, currentX, textY, textColor, fontHeight);

                    imgui.SameLine(0, 0);
                    imgui.Dummy({textW, iconSize});
                    currentX = currentX + textW;
                    hasContent = true;
                end
            else
                -- Stacked layout
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

                    local textW, textH = imtext.Measure(displayText, fontHeight);
                    imtext.Draw(drawList, displayText, startX, startY, textColor, fontHeight);

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
                    DrawIconsWithModifiers(drawList, weaknessIcons, iconSize, spacing, fontHeight, textColor, cursorX, cursorY);
                    hasContent = true;
                end
                -- Resistances row with modifiers

                if #resistanceIcons > 0 then
                    if hasContent then
                        imgui.Spacing();
                    end
                    cursorX, cursorY = imgui.GetCursorScreenPos();
                    DrawIconsWithModifiers(drawList, resistanceIcons, iconSize, spacing, fontHeight, textColor, cursorX, cursorY);
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

                    local textW, textH = imtext.Measure(serverIdString, fontHeight);
                    imtext.Draw(drawList, serverIdString, cursorX, cursorY, textColor, fontHeight);

                    imgui.Dummy({textW, textH});
                    hasContent = true;
                end
            end
        end
    end
    imgui.End();
    -- Pop window padding style if we pushed it for snap mode

    if snapToTargetBar then
        imgui.PopStyleVar(1);
    end
end

    -- Load detection icons (HQ for NMs, NQ for normal mobs)
mobinfo.Initialize = function(settings)
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
    imtext.Reset();
end

mobinfo.SetHidden = function(hidden)
end

    -- Textures are managed by D3D, no explicit cleanup needed
mobinfo.Cleanup = function()
    textures = {
        detection = {},
        elements = {},
        physical = {},
        immunities = {},
    };
end

return mobinfo; -- end
