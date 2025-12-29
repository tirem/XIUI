--[[
* XIUI hotbar - Display Module
]]--

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local ffi = require('ffi');
local d3d8 = require('d3d8');
local windowBg = require('libs.windowbackground');
local progressbar = require('libs.progressbar');
local button = require('libs.button');
local data = require('modules.hotbar.data');
local actions = require('modules.hotbar.actions');
local textures = require('modules.hotbar.textures');
local horizonSpells = require('modules.hotbar.database.horizonspells');

local M = {};

-- ============================================
-- Constants
-- ============================================

local ICON_SIZE = 24;
local ROW_HEIGHT = 32;  -- Icon (24) + top offset (2) + gap (4) + bar (3) - 1
local PADDING = 8;
local ICON_TEXT_GAP = 6;
local ROW_SPACING = 4;
local BAR_HEIGHT = 3;

-- Keybind text positioning
local KEYBIND_OFFSET = 0.04;  -- relative to button size

local HORIZONTAL_COLUMNS = 12; -- buttons per row
local HORIZONTAL_ROWS = 4; -- number of HORIZONTAL_ROWS

local VERTICAL_HOTBAR_COLUMNS = 2;
local VERTICAL_HOTBAR_ROWS = 6;
local VERTICAL_HOTBARS_COUNT = 2;
local VERTICAL_HOTBAR_SPACING = 20; -- spacing between vertical hotbars

-- Hotbar number label spacing
local HORIZONTAL_HOTBAR_NUMBER_OFFSET = 12; -- horizontal offset for left-side hotbar numbers
local HORIZONTAL_HOTBAR_NUMBER_POSITION = -2; -- x position of hotbar number text
local VERTICAL_HOTBAR_NUMBER_SPACING = 16; -- vertical spacing below vertical hotbars for number
local VERTICAL_HOTBAR_NUMBER_POSITION = 0; -- y position of hotbar number text below
local VERTICAL_HOTBAR_NUMBER_OFFSET =  4; -- horizontal offset for vertical hotbar numbers
-- Keybind constants for hotbar HORIZONTAL_ROWS
local KEYBIND_SHIFT = 12;
local KEYBIND_CTRL = 24;
local KEYBIND_ALT = 36;
local KEYBIND_BASE = 48;


-- ============================================
-- State
-- ============================================

-- Background primitive handles (one for horizontal, one for vertical)
local bgPrimHandleHorizontal = nil;
local bgPrimHandleVertical = nil;

-- Theme tracking (for detecting changes like petbar)
local loadedBgTheme = nil;

-- Item icon cache (itemId -> texture table with .image)
local iconCache = {};

-- Textures initialized flag
local texturesInitialized = false;

-- Tab state: 1 = Pool view, 2 = History view
local selectedTab = 1;

-- ============================================
-- Item Icon Loading
-- ============================================

-- ============================================
-- Helper Functions
-- ============================================

--- Find a spell by English name in horizonspells
---@param spellName string The English name of the spell
---@return table|nil The spell data table with en, icon_id, prefix, and id fields
local function GetSpellByName(spellName)
    for _, spell in pairs(horizonSpells) do
        if spell.en == spellName then
            return spell;
        end
    end
    return nil;
end

--- Draws a single hotbar button with textures, keybind, and label
--- Shared function for both horizontal and vertical bars. Handles layered rendering
--- with slot background, button with icon, and frame overlay. Displays keybind text
--- and label, and executes commands on click.
---@param params table The parameters table
---@param params.id string Unique identifier for the button
---@param params.btnX number X position of the button (in pixels)
---@param params.btnY number Y position of the button (in pixels)
---@param params.buttonSize number Size of the button (in pixels)
---@param params.labelText string Text label to display below the button
---@param params.spellIcon table|nil Spell icon texture object (optional)
---@param params.command string|nil Command to execute when button is clicked (optional)
---@param params.drawList table ImGui draw list for rendering
---@param params.keybindDisplay string Keybind text to display in top-left corner
---@param params.labelGap number Gap between button and label text (optional, default 4)
---@return boolean clicked Whether the button was clicked this frame
---@return boolean hovered Whether the button is hovered
local function DrawHotbarButton(params)
    local id = params.id;
    local btnX = params.btnX;
    local btnY = params.btnY;
    local buttonSize = params.buttonSize;
    local labelText = params.labelText;
    local spellIcon = params.spellIcon;
    local command = params.command;
    local drawList = params.drawList;
    local keybindDisplay = params.keybindDisplay;
    
    local noCommand = not command or command == ''

    if noCommand then
       return false, false;
    end

    -- Get slot background and frame textures
    local slotBgTexture = textures:Get('slot');
    local frameTexture = textures:Get('frame');
    
    -- Draw layered button: slot background -> button (with icon) -> frame overlay
    
    -- Draw button with spell icon using button library (with transparent background)
    
    -- Convert textures to pointers for ImGui
    local slotBgPtr = slotBgTexture and tonumber(ffi.cast("uint32_t", slotBgTexture.image));
    local framePtr = frameTexture and tonumber(ffi.cast("uint32_t", frameTexture.image));

        -- Draw slot background first (behind everything)
    if slotBgPtr then
        drawList:AddImage(slotBgPtr, {btnX, btnY}, {btnX + buttonSize, btnY + buttonSize});
    end

    local clicked, hovered = button.Draw(id, btnX, btnY, buttonSize, buttonSize, {
        colors = {
            normal = 0x00000000,   -- Fully transparent
            hovered = 0x22FFFFFF,  -- Slight white tint on hover
            pressed = 0x44FFFFFF,  -- Brighter tint when pressed
            border = 0x00000000,   -- No border
        },
        rounding = 0,
        borderThickness = 0,
        tooltip = labelText,
        image = spellIcon,
        imageSize = {buttonSize * 0.75, buttonSize * 0.75},
        drawList = drawList,
    });
    
    -- Draw label beneath each button
    local labelX = btnX;
    local labelY = btnY + buttonSize + (params.labelGap or 4);
    drawList:AddText({labelX, labelY}, imgui.GetColorU32({0.9, 0.9, 0.9, 1.0}), labelText);

        -- Draw frame overlay on top
    if framePtr then
        drawList:AddImage(framePtr, {btnX, btnY}, {btnX + buttonSize, btnY + buttonSize});
    end

    -- Draw keybind in top-left corner of button
    local keybindX = btnX + buttonSize * KEYBIND_OFFSET;
    local keybindY = btnY + buttonSize * KEYBIND_OFFSET;
    drawList:AddText({keybindX, keybindY}, imgui.GetColorU32({0.7, 0.7, 0.7, 1.0}), keybindDisplay);
   
    -- Execute command when button is clicked
    if clicked and command then
        AshitaCore:GetChatManager():QueueCommand(-1, command);
    end
    
    return clicked, hovered;
end

-- ============================================
-- History View Constants
-- ============================================

-- Helper to build a comma-separated list of names

local drawing = require('libs.drawing');

function M.DrawWindow(settings)
    -- Render a themed hotbar with two HORIZONTAL_ROWS of buttons (10 per row, 20 total) using an imgui window

    -- Initialize textures on first draw
    if not texturesInitialized then
        textures:Initialize();
        texturesInitialized = true;
    end

    -- Validate primitives
    if not bgPrimHandleHorizontal or not bgPrimHandleVertical then
        return;
    end

    -- Scales from config
    local scaleX = gConfig.hotbarScaleX or 1.0;
    local scaleY = gConfig.hotbarScaleY or 1.0;

    -- Dimensions
    local iconSize = math.floor(ICON_SIZE * scaleY);
    local padding = PADDING;

    -- Button layout
    local buttonGap = 12; -- increased horizontal spacing between buttons

    -- Determine button size to fit text ("Button Text") plus padding, then apply configured button scale
    local sampleLabel = 'a-sample';
    local labelPadding = 12; -- horizontal padding to give breathing room for text
    local baseButtonSize = 100
    local button_scale = gConfig.hotbarButtonScale or 0.56; -- final scale (default ~56%)
    local buttonSize = math.max(8, math.floor(baseButtonSize * button_scale));

    -- Label spacing and heights
    local labelGap = 4;
    local textHeight = imgui.GetTextLineHeight();
    local rowGap = 6; -- vertical gap between HORIZONTAL_ROWS

    -- Compute content size for main hotbar
    local mainHotbarWidth = (buttonSize * HORIZONTAL_COLUMNS) + (buttonGap * (HORIZONTAL_COLUMNS - 1)) + HORIZONTAL_HOTBAR_NUMBER_OFFSET;
    local mainHotbarHeight = (buttonSize + labelGap + textHeight) * HORIZONTAL_ROWS + (rowGap * (HORIZONTAL_ROWS - 1));
    
    -- Compute content size for side hotbars (5, 6, 7)
    local verticalHotbarWidth = (buttonSize * VERTICAL_HOTBAR_COLUMNS) + (buttonGap * (VERTICAL_HOTBAR_COLUMNS - 1));
    local verticalHotbarHeight = VERTICAL_HOTBAR_NUMBER_SPACING + (buttonSize + labelGap + textHeight) * VERTICAL_HOTBAR_ROWS + (rowGap * (VERTICAL_HOTBAR_ROWS - 1));
    
    -- Compute total content size (main hotbar + gap + vertical hotbars)
    local verticalMargin = 50; -- margin between horizontal and vertical hotbars
    local verticalHotbarsExtraMargin = (VERTICAL_HOTBARS_COUNT - 1) * VERTICAL_HOTBAR_SPACING; -- accumulated margin from loop
    local contentWidth = (padding * 2) + mainHotbarWidth + verticalMargin + (verticalHotbarWidth * VERTICAL_HOTBARS_COUNT) + (buttonGap * (VERTICAL_HOTBARS_COUNT - 1)) + verticalHotbarsExtraMargin;
    local horizontalContentHeight = padding + mainHotbarHeight + (padding / 2);
    local verticalContentHeight = padding + verticalHotbarHeight + (padding / 2);

    -- Background options (use theme settings like partylist)
    local bgTheme = gConfig.hotbarBackgroundTheme or 'Plain';
    local bgScale = gConfig.hotbarBgScale or 1.0;
    local borderScale = gConfig.hotbarBorderScale or 1.0;
    local bgOpacity = gConfig.hotbarBackgroundOpacity or 0.87;
    local borderOpacity = gConfig.hotbarBorderOpacity or 1.0;

    -- Apply theme change safely
    if loadedBgTheme ~= bgTheme and bgPrimHandleHorizontal and bgPrimHandleVertical then
        loadedBgTheme = bgTheme;
        pcall(function()
            windowBg.setTheme(bgPrimHandleHorizontal, bgTheme, bgScale, borderScale);
            windowBg.setTheme(bgPrimHandleVertical, bgTheme, bgScale, borderScale);
        end);
    end

    -- Determine colors: prefer user color customization for hotbar, else fall back to theme sensible defaults
    local hotbarColors = gConfig and gConfig.colorCustomization and gConfig.colorCustomization.hotbar;
    local bgColor = hotbarColors and hotbarColors.bgColor or nil;
    local borderColor = hotbarColors and hotbarColors.borderColor or nil;

    if not bgColor then
        if bgTheme == 'Plain' then
            bgColor = 0xFF1A1A1A; -- dark tint for plain
        else
            bgColor = 0xFFFFFFFF; -- white (no tint) for themed textures
        end
    end
    if not borderColor then
        borderColor = 0xFFFFFFFF;
    end

    -- Use saved state if present (for drag-to-move later)
    local savedX = (gConfig.hotbarState and gConfig.hotbarState.x) or 1000;
    local savedY = (gConfig.hotbarState and gConfig.hotbarState.y) or 1000;
    local savedVerticalX = (gConfig.hotbarVerticalState and gConfig.hotbarVerticalState.x) or 1200;
    local savedVerticalY = (gConfig.hotbarVerticalState and gConfig.hotbarVerticalState.y) or 1000;

    local bgOptions = {
        theme = bgTheme,
        padding = padding,
        paddingY = padding,
        bgScale = bgScale,
        borderScale = borderScale,
        bgOpacity = bgOpacity,
        borderOpacity = borderOpacity,
        bgColor = bgColor,
        borderColor = borderColor,
    };

    -- Use an imgui window (no decoration / no background) to get a consistent position/size like PartyWindow
    local windowFlags = GetBaseWindowFlags(gConfig.lockPositions);

    -- Get draw list once for all windows
    local drawList = drawing.GetUIDrawList();

    -- ============================================
    -- HORIZONTAL HOTBAR WINDOW
    -- ============================================
    local windowName = 'Hotbar';

    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {0,0});
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { buttonGap, 0 });
    -- Only set position on first use, then let ImGui track dragging
    imgui.SetNextWindowPos({savedX, savedY}, ImGuiCond_FirstUseEver);

    local imguiPosX, imguiPosY;
    if (imgui.Begin(windowName, true, windowFlags)) then
        imguiPosX, imguiPosY = imgui.GetWindowPos();

        -- Reserve window space IMMEDIATELY after Begin()
        -- This tells imgui about the window bounds before any button drawing
        imgui.Dummy({mainHotbarWidth + (padding * 2), horizontalContentHeight});

        -- Draw main hotbar (4 rows x 10 columns)
        local idx = 1;
        for row = 1, HORIZONTAL_ROWS do
            local btnX = imguiPosX + padding + HORIZONTAL_HOTBAR_NUMBER_OFFSET;
            local btnY = imguiPosY + padding + (row - 1) * (buttonSize + labelGap + textHeight + rowGap);
            
            -- Invert hotbar number for display (row 1 = hotbar 4, row 4 = hotbar 1)
            local hotbarNumber = HORIZONTAL_ROWS - row + 1;
            local hotbarNumX = imguiPosX + padding + HORIZONTAL_HOTBAR_NUMBER_POSITION;
            local hotbarNumY = btnY + (buttonSize - imgui.GetTextLineHeight()) / 2; -- center vertically
            -- Use GDI font for hotbar number (following party list pattern)
            if data.hotbarNumberFonts[hotbarNumber] then
                data.hotbarNumberFonts[hotbarNumber]:set_text(tostring(hotbarNumber));
                data.hotbarNumberFonts[hotbarNumber]:set_position_x(hotbarNumX);
                data.hotbarNumberFonts[hotbarNumber]:set_position_y(hotbarNumY);
                data.hotbarNumberFonts[hotbarNumber]:set_visible(true);
            end
            
            for column = 1, HORIZONTAL_COLUMNS do
                local id = 'hotbar_btn_' .. idx;
                local labelText = sampleLabel;
                local spellIcon = nil;
                local command = nil;
                
                -- Load keybind from data (using inverted hotbar number)
                local keybinds = data.GetKeybinds('Base');
                if keybinds then
                    for _, bind in ipairs(keybinds) do
                        if bind.hotbar == hotbarNumber and bind.slot == column then
                            labelText = bind.displayName or bind.action;
                            -- Use centralized command builder
                            command, spellIcon = actions.BuildCommand(bind);
                            break;
                        end
                    end
                end
                
                -- Compute keybind display based on hotbar number
                local keybindDisplay = '';
                local keybindKey = tostring(column);
                if(keybindKey == '11') then
                    keybindKey = '-';
                end
                if(keybindKey == '12') then
                    keybindKey = '+';
                end
                if(hotbarNumber == 4) then
                    keybindDisplay = 'S' .. keybindKey;
                elseif(hotbarNumber == 3) then
                    keybindDisplay = 'A' .. keybindKey;                    
                elseif(hotbarNumber == 2) then
                    keybindDisplay = 'C' .. keybindKey;
                else
                    keybindDisplay = keybindKey;
                end

                -- Draw button using shared function
                DrawHotbarButton({
                    id = id,
                    btnX = btnX,
                    btnY = btnY,
                    buttonSize = buttonSize,
                    labelText = labelText,
                    spellIcon = spellIcon,
                    command = command,
                    drawList = drawList,
                    keybindDisplay = keybindDisplay,
                    labelGap = labelGap,
                });

                btnX = btnX + buttonSize + buttonGap;
                idx = idx + 1;
            end
        end

        -- Update background primitive using imgui window position
        pcall(function()
            windowBg.update(bgPrimHandleHorizontal, imguiPosX, imguiPosY, mainHotbarWidth + (padding * 2), horizontalContentHeight, bgOptions);
        end);

        imgui.End();
    end

    imgui.PopStyleVar(2);

    -- Save horizontal window position
    if imguiPosX ~= nil then
        if gConfig.hotbarState == nil then
            gConfig.hotbarState = {};
        end
        if gConfig.hotbarState.x ~= imguiPosX or gConfig.hotbarState.y ~= imguiPosY then
            gConfig.hotbarState.x = imguiPosX;
            gConfig.hotbarState.y = imguiPosY;
        end
    end

    -- ============================================
    -- VERTICAL HOTBAR WINDOW
    -- ============================================
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {0,0});
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { buttonGap, 0 });
    imgui.SetNextWindowPos({savedVerticalX, savedVerticalY}, ImGuiCond_FirstUseEver);

    local imguiVerticalPosX, imguiVerticalPosY;
    if (imgui.Begin('HotbarVertical', true, windowFlags)) then
        imguiVerticalPosX, imguiVerticalPosY = imgui.GetWindowPos();

        -- Calculate vertical hotbar total width
        local verticalHotbarsExtraMargin = (VERTICAL_HOTBARS_COUNT - 1) * VERTICAL_HOTBAR_SPACING;
        local totalVerticalWidth = (verticalHotbarWidth * VERTICAL_HOTBARS_COUNT) + (buttonGap * (VERTICAL_HOTBARS_COUNT - 1)) + verticalHotbarsExtraMargin + (padding * 2);

        imgui.Dummy({totalVerticalWidth, verticalContentHeight});

        -- Draw vertical hotbars (5, 6, 7) - each with 4 rows x 2 columns
        local verticalStartX = imguiVerticalPosX + padding;
        local hotbarMargin = 0;
        for hotbarNum = 1, VERTICAL_HOTBARS_COUNT do
            local hotbarOffsetX = verticalStartX + (hotbarNum - 1) * (verticalHotbarWidth + buttonGap) + hotbarMargin;
            
            -- Draw hotbar number above vertical hotbar
            local hotbarNumber = 4 + hotbarNum;
            local hotbarNumberStr = tostring(hotbarNumber);
            local hotbarNumX = hotbarOffsetX + (verticalHotbarWidth / 2) - (imgui.CalcTextSize(hotbarNumberStr) / 2) + VERTICAL_HOTBAR_NUMBER_OFFSET;
            local hotbarNumY = imguiVerticalPosY + VERTICAL_HOTBAR_NUMBER_POSITION;
            -- Use GDI font for hotbar number (following party list pattern)
            if data.hotbarNumberFonts[hotbarNumber] then
                data.hotbarNumberFonts[hotbarNumber]:set_text(hotbarNumberStr);
                data.hotbarNumberFonts[hotbarNumber]:set_position_x(hotbarNumX);
                data.hotbarNumberFonts[hotbarNumber]:set_position_y(hotbarNumY);
                data.hotbarNumberFonts[hotbarNumber]:set_visible(true);
            end
            
            local verticalIdx = 1;
            for row = 1, VERTICAL_HOTBAR_ROWS do
                local btnX = hotbarOffsetX;
                local btnY = imguiVerticalPosY + padding + VERTICAL_HOTBAR_NUMBER_SPACING + (row - 1) * (buttonSize + labelGap + textHeight + rowGap);
                for column = 1, VERTICAL_HOTBAR_COLUMNS do
                    local buttonIndex = (hotbarNum - 1) * (VERTICAL_HOTBAR_ROWS * VERTICAL_HOTBAR_COLUMNS) + verticalIdx;
                    local id = 'hotbar_vertical_btn_' .. buttonIndex;
                    local labelText = sampleLabel
                    local spellIcon = nil;
                    local command = nil;

                    -- Load keybind from data (using hotbarNumber 5 or 6)
                    local hotbarNumberVertical = 4 + hotbarNum; -- 5 or 6
                    local keybinds = data.GetKeybinds('Base');
                    if keybinds then
                        for _, bind in ipairs(keybinds) do
                            if bind.hotbar == hotbarNumberVertical and bind.slot == verticalIdx then
                                labelText = bind.displayName or bind.action;
                                -- Use centralized command builder
                                command, spellIcon = actions.BuildCommand(bind);
                                break;
                            end
                        end
                    end

                    -- Compute keybind display for vertical bars
                    local keybindDisplay = '';
                    local keybindKey = tostring(verticalIdx);
                    if(keybindKey == '11') then
                        keybindKey = '-';
                    end
                    if(keybindKey == '12') then
                        keybindKey = '+';
                    end
                    if hotbarNum == 1 then
                        keybindDisplay = 'CS' .. keybindKey;
                    else 
                        keybindDisplay = 'CA' .. keybindKey;                    
                    end

                    -- Draw button using shared function
                    DrawHotbarButton({
                        id = id,
                        btnX = btnX,
                        btnY = btnY,
                        buttonSize = buttonSize,
                        labelText = labelText,
                        spellIcon = spellIcon,
                        command = command,
                        drawList = drawList,
                        keybindDisplay = keybindDisplay,
                        labelGap = labelGap,
                    });

                    btnX = btnX + buttonSize + buttonGap;
                    verticalIdx = verticalIdx + 1;
                end
            end
            
            hotbarMargin = hotbarMargin + VERTICAL_HOTBAR_SPACING;
        end

        -- Update vertical background primitive
        local verticalHotbarsExtraMargin = (VERTICAL_HOTBARS_COUNT - 1) * VERTICAL_HOTBAR_SPACING;
        local totalVerticalWidth = (verticalHotbarWidth * VERTICAL_HOTBARS_COUNT) + (buttonGap * (VERTICAL_HOTBARS_COUNT - 1)) + verticalHotbarsExtraMargin + (padding * 2);
        pcall(function()
            windowBg.update(bgPrimHandleVertical, imguiVerticalPosX, imguiVerticalPosY, totalVerticalWidth, verticalContentHeight, bgOptions);
        end);

        imgui.End();
    end

    imgui.PopStyleVar(2);

    -- Save vertical window position
    if imguiVerticalPosX ~= nil then
        if gConfig.hotbarVerticalState == nil then
            gConfig.hotbarVerticalState = {};
        end
        if gConfig.hotbarVerticalState.x ~= imguiVerticalPosX or gConfig.hotbarVerticalState.y ~= imguiVerticalPosY then
            gConfig.hotbarVerticalState.x = imguiVerticalPosX;
            gConfig.hotbarVerticalState.y = imguiVerticalPosY;
        end
    end
end

function M.HideWindow()
    if bgPrimHandleHorizontal then
        windowBg.hide(bgPrimHandleHorizontal);
    end
    if bgPrimHandleVertical then
        windowBg.hide(bgPrimHandleVertical);
    end

    -- Hide hotbar number fonts
    for i = 1, 6 do
        if data.hotbarNumberFonts[i] then
            data.hotbarNumberFonts[i]:set_visible(false);
        end
    end

    -- Hide main hotbar buttons
    for i = 1, HORIZONTAL_ROWS * HORIZONTAL_COLUMNS do
        button.HidePrim('hotbar_btn_' .. i);
    end
    
    -- Hide side hotbar buttons
    for i = 1, VERTICAL_HOTBARS_COUNT * VERTICAL_HOTBAR_ROWS * VERTICAL_HOTBAR_COLUMNS do
        button.HidePrim('hotbar_vertical_btn_' .. i);
    end
end

-- ============================================
-- Lifecycle
-- ============================================

function M.Initialize(settings)
    -- Get background theme and scales from config (with defaults)
    local bgTheme = gConfig.hotbarBackgroundTheme or 'Plain';
    local bgScale = gConfig.hotbarBgScale or 1.0;
    local borderScale = gConfig.hotbarBorderScale or 1.0;
    loadedBgTheme = bgTheme;

    -- Create background primitives (fonts created by init.lua)
    local primData = {
        visible = false,
        can_focus = false,
        locked = true,
        width = 100,
        height = 100,
    };
    bgPrimHandleHorizontal = windowBg.create(primData, bgTheme, bgScale, borderScale);
    bgPrimHandleVertical = windowBg.create(primData, bgTheme, bgScale, borderScale);
end

function M.UpdateVisuals(settings)
    -- Check if theme changed
    local bgTheme = gConfig.hotbarBackgroundTheme or 'Plain';
    local bgScale = gConfig.hotbarBgScale or 1.0;
    local borderScale = gConfig.hotbarBorderScale or 1.0;
    if loadedBgTheme ~= bgTheme and bgPrimHandleHorizontal and bgPrimHandleVertical then
        loadedBgTheme = bgTheme;
        windowBg.setTheme(bgPrimHandleHorizontal, bgTheme, bgScale, borderScale);
        windowBg.setTheme(bgPrimHandleVertical, bgTheme, bgScale, borderScale);
    end
end

function M.SetHidden(hidden)
    if hidden then
        M.HideWindow();
    end
end

function M.Cleanup()
    if bgPrimHandleHorizontal then
        windowBg.destroy(bgPrimHandleHorizontal);
        bgPrimHandleHorizontal = nil;
    end
    if bgPrimHandleVertical then
        windowBg.destroy(bgPrimHandleVertical);
        bgPrimHandleVertical = nil;
    end

    -- Destroy main hotbar buttons
    for i = 1, HORIZONTAL_ROWS * HORIZONTAL_COLUMNS do
        button.DestroyPrim('hotbar_btn_' .. i);
    end
    
    -- Destroy side hotbar buttons
    for i = 1, VERTICAL_HOTBARS_COUNT * VERTICAL_HOTBAR_ROWS * VERTICAL_HOTBAR_COLUMNS do
        button.DestroyPrim('hotbar_vertical_btn_' .. i);
    end
end

return M;
