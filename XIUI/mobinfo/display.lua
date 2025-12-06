--[[
    Mob Info Display Module for XIUI
    Displays mob detection methods, level, resistances, weaknesses, and immunities
    as icons with tooltips in a separate movable window.

    Uses icons from MobDB (ThornyFFXI/mobdb) - MIT License
    https://github.com/ThornyFFXI/mobdb
]]

require('common');
require('helpers');
local imgui = require('imgui');
local gdi = require('gdifonts.include');
local ffi = require("ffi");
local mobdata = require('mobinfo.data');

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
local levelText;
local allFonts;

-- Cached colors
local lastLevelTextColor;

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

    local path = string.format('%s/mobdb/addons/mobdb/icons/%s.png', addon.path, name);
    local res = ffi.C.D3DXCreateTextureFromFileA(device, path, texture_ptr);

    if res ~= 0 then
        -- Texture failed to load - this is expected if file doesn't exist
        return nil;
    end

    return { image = texture_ptr[0] };
end

-- Draw a single icon with tooltip
local function DrawIconWithTooltip(texture, size, tooltipText, tintColor)
    if texture == nil or texture.image == nil then
        -- Draw a placeholder square if texture is missing
        local draw_list = imgui.GetWindowDrawList();
        local posX, posY = imgui.GetCursorScreenPos();
        draw_list:AddRectFilled(
            {posX, posY},
            {posX + size, posY + size},
            tintColor or 0xFF888888,
            2.0
        );
        imgui.Dummy({size, size});
    else
        if tintColor then
            imgui.Image(tonumber(ffi.cast("uint32_t", texture.image)), {size, size}, {0, 0}, {1, 1}, {
                bit.band(bit.rshift(tintColor, 16), 0xFF) / 255,
                bit.band(bit.rshift(tintColor, 8), 0xFF) / 255,
                bit.band(tintColor, 0xFF) / 255,
                bit.band(bit.rshift(tintColor, 24), 0xFF) / 255
            });
        else
            imgui.Image(tonumber(ffi.cast("uint32_t", texture.image)), {size, size});
        end
    end

    if tooltipText and imgui.IsItemHovered() then
        imgui.SetTooltip(tooltipText);
    end
end

-- Draw a row of icons with spacing
local function DrawIconRow(icons, iconSize, spacing, maxPerRow)
    local count = 0;
    for _, iconData in ipairs(icons) do
        if count > 0 then
            if maxPerRow and count >= maxPerRow then
                -- Start new row
                count = 0;
            else
                imgui.SameLine(0, spacing);
            end
        end

        DrawIconWithTooltip(iconData.texture, iconSize, iconData.tooltip, iconData.tint);
        count = count + 1;
    end
end

--[[
* event: d3d_present
* desc : Event called when the Direct3D device is presenting a scene.
--]]
mobinfo.DrawWindow = function(settings)
    -- Check if enabled
    if not gConfig.showMobInfo then
        SetFontsVisible(allFonts, false);
        return;
    end

    -- Obtain the player entity
    local player = GetPlayerSafe();
    local playerEnt = GetPlayerEntity();

    if player == nil or playerEnt == nil then
        SetFontsVisible(allFonts, false);
        return;
    end

    if player.isZoning then
        SetFontsVisible(allFonts, false);
        return;
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
        SetFontsVisible(allFonts, false);
        return;
    end

    -- Only show for mobs
    local isMonster = GetIsMob(targetEntity);
    if not isMonster then
        SetFontsVisible(allFonts, false);
        return;
    end

    -- Get mob info from database
    local mobInfo = mobdata.GetMobInfo(targetEntity.Name);

    -- If no data and we don't want to show "no data" window, hide
    if mobInfo == nil and not gConfig.mobInfoShowNoData then
        SetFontsVisible(allFonts, false);
        return;
    end

    -- Calculate icon size with scale
    local iconSize = settings.iconSize * gConfig.mobInfoIconScale;
    local spacing = settings.iconSpacing;

    -- Setup window
    imgui.SetNextWindowSize({-1, -1}, ImGuiCond_Always);
    local windowFlags = bit.bor(
        ImGuiWindowFlags_NoDecoration,
        ImGuiWindowFlags_AlwaysAutoResize,
        ImGuiWindowFlags_NoFocusOnAppearing,
        ImGuiWindowFlags_NoNav,
        ImGuiWindowFlags_NoBackground,
        ImGuiWindowFlags_NoBringToFrontOnFocus,
        ImGuiWindowFlags_NoDocking
    );
    if gConfig.lockPositions then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
    end

    if imgui.Begin('MobInfo', true, windowFlags) then
        -- If no data, show a simple message
        if mobInfo == nil then
            imgui.Text('No mob data');
            SetFontsVisible(allFonts, false);
        else
            local startX, startY = imgui.GetCursorScreenPos();
            local hasContent = false;

            -- Level display
            if gConfig.mobInfoShowLevel then
                local levelString = mobdata.GetLevelString(mobInfo);
                if levelString ~= '' then
                    levelText:set_font_height(settings.level_font_settings.font_height);
                    levelText:set_text('Lv.' .. levelString);

                    local textColor = gConfig.colorCustomization.mobInfo.levelTextColor;
                    if lastLevelTextColor ~= textColor then
                        levelText:set_font_color(textColor);
                        lastLevelTextColor = textColor;
                    end

                    local textW, textH = levelText:get_text_size();
                    levelText:set_position_x(startX);
                    levelText:set_position_y(startY);
                    levelText:set_visible(true);

                    imgui.Dummy({textW, textH});
                    hasContent = true;
                else
                    levelText:set_visible(false);
                end
            else
                levelText:set_visible(false);
            end

            -- Detection methods row
            if gConfig.mobInfoShowDetection then
                local detectionIcons = {};
                local methods = mobdata.GetDetectionMethods(mobInfo);

                -- Aggro indicator first
                if mobInfo.Aggro then
                    table.insert(detectionIcons, {
                        texture = textures.detection.aggro,
                        tooltip = 'Aggressive',
                        tint = 0xFFFF4444
                    });
                end

                -- Link indicator
                if gConfig.mobInfoShowLink and mobInfo.Link then
                    table.insert(detectionIcons, {
                        texture = textures.detection.link,
                        tooltip = 'Links with nearby mobs',
                        tint = 0xFFFFAA44
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

                if #detectionIcons > 0 then
                    if hasContent then
                        imgui.Spacing();
                    end
                    DrawIconRow(detectionIcons, iconSize, spacing, settings.maxIconsPerRow);
                    hasContent = true;
                end
            end

            -- Weaknesses row (green tinted)
            if gConfig.mobInfoShowWeaknesses then
                local weaknessIcons = {};
                local weaknesses = mobdata.GetWeaknesses(mobInfo);

                -- Elements
                for _, elem in ipairs(elements) do
                    if weaknesses[elem.key] then
                        local modifier = weaknesses[elem.key];
                        local percent = math.floor((modifier - 1) * 100);
                        table.insert(weaknessIcons, {
                            texture = textures.elements[string.lower(elem.key)],
                            tooltip = elem.name .. ' Weakness (+' .. percent .. '% damage)',
                            tint = gConfig.colorCustomization.mobInfo.weaknessColor
                        });
                    end
                end

                -- Physical types
                for _, phys in ipairs(physicalTypes) do
                    if weaknesses[phys.key] then
                        local modifier = weaknesses[phys.key];
                        local percent = math.floor((modifier - 1) * 100);
                        table.insert(weaknessIcons, {
                            texture = textures.physical[string.lower(phys.key)],
                            tooltip = phys.name .. ' Weakness (+' .. percent .. '% damage)',
                            tint = gConfig.colorCustomization.mobInfo.weaknessColor
                        });
                    end
                end

                if #weaknessIcons > 0 then
                    if hasContent then
                        imgui.Spacing();
                    end
                    DrawIconRow(weaknessIcons, iconSize, spacing, settings.maxIconsPerRow);
                    hasContent = true;
                end
            end

            -- Resistances row (red tinted)
            if gConfig.mobInfoShowResistances then
                local resistanceIcons = {};
                local resistances = mobdata.GetResistances(mobInfo);

                -- Elements
                for _, elem in ipairs(elements) do
                    if resistances[elem.key] then
                        local modifier = resistances[elem.key];
                        local percent = math.floor((1 - modifier) * 100);
                        table.insert(resistanceIcons, {
                            texture = textures.elements[string.lower(elem.key)],
                            tooltip = elem.name .. ' Resistance (-' .. percent .. '% damage)',
                            tint = gConfig.colorCustomization.mobInfo.resistanceColor
                        });
                    end
                end

                -- Physical types
                for _, phys in ipairs(physicalTypes) do
                    if resistances[phys.key] then
                        local modifier = resistances[phys.key];
                        local percent = math.floor((1 - modifier) * 100);
                        table.insert(resistanceIcons, {
                            texture = textures.physical[string.lower(phys.key)],
                            tooltip = phys.name .. ' Resistance (-' .. percent .. '% damage)',
                            tint = gConfig.colorCustomization.mobInfo.resistanceColor
                        });
                    end
                end

                if #resistanceIcons > 0 then
                    if hasContent then
                        imgui.Spacing();
                    end
                    DrawIconRow(resistanceIcons, iconSize, spacing, settings.maxIconsPerRow);
                    hasContent = true;
                end
            end

            -- Immunities row (yellow tinted)
            if gConfig.mobInfoShowImmunities then
                local immunityIcons = {};
                local immunities = mobdata.GetImmunities(mobInfo);

                for _, imm in ipairs(immunityTypes) do
                    if immunities[imm.key] then
                        table.insert(immunityIcons, {
                            texture = textures.immunities[string.lower(imm.key)],
                            tooltip = 'Immune to ' .. imm.name,
                            tint = gConfig.colorCustomization.mobInfo.immunityColor
                        });
                    end
                end

                if #immunityIcons > 0 then
                    if hasContent then
                        imgui.Spacing();
                    end
                    DrawIconRow(immunityIcons, iconSize, spacing, settings.maxIconsPerRow);
                    hasContent = true;
                end
            end

            -- If no content was drawn, show placeholder
            if not hasContent then
                levelText:set_visible(false);
            end
        end
    end
    imgui.End();
end

mobinfo.Initialize = function(settings)
    -- Create font objects
    levelText = FontManager.create(settings.level_font_settings);
    allFonts = {levelText};

    -- Load detection icons
    textures.detection.aggro = LoadMobInfoTexture('AggroHQ');
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
    -- Recreate fonts
    levelText = FontManager.recreate(levelText, settings.level_font_settings);
    allFonts = {levelText};

    -- Reset cached colors
    lastLevelTextColor = nil;
end

mobinfo.SetHidden = function(hidden)
    if hidden == true then
        SetFontsVisible(allFonts, false);
    end
end

mobinfo.Cleanup = function()
    -- Destroy fonts
    levelText = FontManager.destroy(levelText);
    allFonts = nil;

    -- Textures are managed by D3D, no explicit cleanup needed
    textures = {
        detection = {},
        elements = {},
        physical = {},
        immunities = {},
    };
end

return mobinfo;
