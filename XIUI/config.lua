--[[
* XIUI Config Menu - Main Window
* Entry point for the config menu, handles window rendering and dispatches to module files
]]--

require("common");
require('handlers.helpers');
local statusHandler = require('handlers.statushandler');
local imgui = require("imgui");
local ffi = require("ffi");

-- Import modules (each has DrawSettings + DrawColorSettings)
local globalModule = require('config.global');
local playerbarModule = require('config.playerbar');
local targetbarModule = require('config.targetbar');
local enemylistModule = require('config.enemylist');
local partylistModule = require('config.partylist');
local expbarModule = require('config.expbar');
local giltrackerModule = require('config.giltracker');
local inventoryModule = require('config.inventory');
local castbarModule = require('config.castbar');

local config = {};

-- State for confirmation dialogs
local showRestoreDefaultsConfirm = false;
local showRestoreColorsConfirm = false;

-- Social icon textures
local discordTexture = nil;
local githubTexture = nil;
local heartTexture = nil;

-- Credits popup state
local showCreditsPopup = false;

-- Navigation state
local selectedCategory = 1;  -- 1-indexed category selection
local selectedTab = 1;       -- 1 = settings, 2 = color settings
local selectedPartyTab = 1;  -- 1 = Party A, 2 = Party B, 3 = Party C
local selectedPartyColorTab = 1;  -- 1 = Party A, 2 = Party B, 3 = Party C (for color settings)
local selectedInventoryTab = 1;  -- 1 = Inventory, 2 = Satchel
local selectedInventoryColorTab = 1;  -- 1 = Inventory, 2 = Satchel (for color settings)
local selectedTargetBarTab = 1;  -- 1 = Target Bar, 2 = Mob Info
local selectedTargetBarColorTab = 1;  -- 1 = Target Bar, 2 = Mob Info (for color settings)

-- Category definitions
local categories = {
    { name = 'global', label = 'Global' },
    { name = 'playerBar', label = 'Player Bar' },
    { name = 'targetBar', label = 'Target Bar' },
    { name = 'enemyList', label = 'Enemy List' },
    { name = 'partyList', label = 'Party List' },
    { name = 'expBar', label = 'Exp Bar' },
    { name = 'gilTracker', label = 'Gil Tracker' },
    { name = 'inventory', label = 'Inventory' },
    { name = 'castBar', label = 'Cast Bar' },
};

-- Build state object for modules that need tab state
local function buildState()
    return {
        selectedPartyTab = selectedPartyTab,
        selectedPartyColorTab = selectedPartyColorTab,
        selectedInventoryTab = selectedInventoryTab,
        selectedInventoryColorTab = selectedInventoryColorTab,
        selectedTargetBarTab = selectedTargetBarTab,
        selectedTargetBarColorTab = selectedTargetBarColorTab,
        githubTexture = githubTexture,
    };
end

-- Apply returned state from modules
local function applySettingsState(newState)
    if newState then
        if newState.selectedPartyTab then selectedPartyTab = newState.selectedPartyTab; end
        if newState.selectedInventoryTab then selectedInventoryTab = newState.selectedInventoryTab; end
        if newState.selectedTargetBarTab then selectedTargetBarTab = newState.selectedTargetBarTab; end
    end
end

local function applyColorState(newState)
    if newState then
        if newState.selectedPartyColorTab then selectedPartyColorTab = newState.selectedPartyColorTab; end
        if newState.selectedInventoryColorTab then selectedInventoryColorTab = newState.selectedInventoryColorTab; end
        if newState.selectedTargetBarColorTab then selectedTargetBarColorTab = newState.selectedTargetBarColorTab; end
    end
end

-- Settings draw functions with state handling
local function DrawGlobalSettings()
    globalModule.DrawSettings();
end

local function DrawPlayerBarSettings()
    playerbarModule.DrawSettings();
end

local function DrawTargetBarSettings()
    local newState = targetbarModule.DrawSettings(buildState());
    applySettingsState(newState);
end

local function DrawEnemyListSettings()
    enemylistModule.DrawSettings();
end

local function DrawPartyListSettings()
    local newState = partylistModule.DrawSettings(buildState());
    applySettingsState(newState);
end

local function DrawExpBarSettings()
    expbarModule.DrawSettings();
end

local function DrawGilTrackerSettings()
    giltrackerModule.DrawSettings();
end

local function DrawInventorySettings()
    local newState = inventoryModule.DrawSettings(buildState());
    applySettingsState(newState);
end

local function DrawCastBarSettings()
    castbarModule.DrawSettings();
end

-- Color settings draw functions with state handling
local function DrawGlobalColorSettings()
    globalModule.DrawColorSettings();
end

local function DrawPlayerBarColorSettings()
    playerbarModule.DrawColorSettings();
end

local function DrawTargetBarColorSettings()
    local newState = targetbarModule.DrawColorSettings(buildState());
    applyColorState(newState);
end

local function DrawEnemyListColorSettings()
    enemylistModule.DrawColorSettings();
end

local function DrawPartyListColorSettings()
    local newState = partylistModule.DrawColorSettings(buildState());
    applyColorState(newState);
end

local function DrawExpBarColorSettings()
    expbarModule.DrawColorSettings();
end

local function DrawGilTrackerColorSettings()
    giltrackerModule.DrawColorSettings();
end

local function DrawInventoryColorSettings()
    local newState = inventoryModule.DrawColorSettings(buildState());
    applyColorState(newState);
end

local function DrawCastBarColorSettings()
    castbarModule.DrawColorSettings();
end

-- Dispatch tables for settings and color settings
local settingsDrawFunctions = {
    DrawGlobalSettings,
    DrawPlayerBarSettings,
    DrawTargetBarSettings,
    DrawEnemyListSettings,
    DrawPartyListSettings,
    DrawExpBarSettings,
    DrawGilTrackerSettings,
    DrawInventorySettings,
    DrawCastBarSettings,
};

local colorSettingsDrawFunctions = {
    DrawGlobalColorSettings,
    DrawPlayerBarColorSettings,
    DrawTargetBarColorSettings,
    DrawEnemyListColorSettings,
    DrawPartyListColorSettings,
    DrawExpBarColorSettings,
    DrawGilTrackerColorSettings,
    DrawInventoryColorSettings,
    DrawCastBarColorSettings,
};

config.DrawWindow = function(us)
    -- Early exit if config window isn't shown (atom0s recommendation)
    -- This prevents unnecessary style pushes and imgui.End() calls when window is hidden
    if (not showConfig[1]) then return; end

    -- XIUI Theme Colors (dark + gold accent)
    -- Base colors from XIUI branding
    local gold = {0.957, 0.855, 0.592, 1.0};           -- #F4DA97 - Primary gold accent
    local goldDark = {0.765, 0.684, 0.474, 1.0};       -- #C3AE79 - Darker gold for hover
    local goldDarker = {0.573, 0.512, 0.355, 1.0};     -- #92835B - Even darker gold
    local bgDark = {0.051, 0.051, 0.051, 0.95};        -- #0D0D0D - Deep black background
    local bgMedium = {0.098, 0.090, 0.075, 1.0};       -- #191713 - Slightly warm dark
    local bgLight = {0.137, 0.125, 0.106, 1.0};        -- #23201B - Lighter warm dark
    local bgLighter = {0.176, 0.161, 0.137, 1.0};      -- #2D2923 - Highlight dark
    local textLight = {0.878, 0.855, 0.812, 1.0};      -- #E0DACF - Warm off-white text
    local textMuted = {0.6, 0.58, 0.54, 1.0};          -- #999388 - Muted text
    local borderDark = {0.3, 0.275, 0.235, 1.0};       -- #4D463C - Warm dark border

    -- Mapped colors for UI elements
    local bgColor = bgDark;
    local buttonColor = bgMedium;
    local buttonHoverColor = bgLight;
    local buttonActiveColor = bgLighter;
    local selectedButtonColor = {gold[1], gold[2], gold[3], 0.25};  -- Gold tinted selection
    local tabColor = bgMedium;
    local tabHoverColor = bgLight;
    local tabActiveColor = {gold[1], gold[2], gold[3], 0.3};  -- Gold tinted for selected tab
    local tabSelectedColor = {gold[1], gold[2], gold[3], 0.25};  -- Gold tinted for selected settings/color tab buttons
    local borderColor = borderDark;
    local textColor = textLight;

    imgui.PushStyleColor(ImGuiCol_WindowBg, bgColor);
    imgui.PushStyleColor(ImGuiCol_ChildBg, {0, 0, 0, 0});
    imgui.PushStyleColor(ImGuiCol_TitleBg, bgMedium);
    imgui.PushStyleColor(ImGuiCol_TitleBgActive, bgLight);
    imgui.PushStyleColor(ImGuiCol_TitleBgCollapsed, bgDark);
    imgui.PushStyleColor(ImGuiCol_FrameBg, bgMedium);
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, bgLight);
    imgui.PushStyleColor(ImGuiCol_FrameBgActive, bgLighter);
    imgui.PushStyleColor(ImGuiCol_Header, bgLight);
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, bgLighter);
    imgui.PushStyleColor(ImGuiCol_HeaderActive, {gold[1], gold[2], gold[3], 0.3});
    imgui.PushStyleColor(ImGuiCol_Border, borderColor);
    imgui.PushStyleColor(ImGuiCol_Text, textColor);
    imgui.PushStyleColor(ImGuiCol_TextDisabled, goldDark);  -- Dropdown arrows
    imgui.PushStyleColor(ImGuiCol_Button, buttonColor);
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, buttonHoverColor);
    imgui.PushStyleColor(ImGuiCol_ButtonActive, buttonActiveColor);
    imgui.PushStyleColor(ImGuiCol_CheckMark, gold);
    imgui.PushStyleColor(ImGuiCol_SliderGrab, goldDark);
    imgui.PushStyleColor(ImGuiCol_SliderGrabActive, gold);
    imgui.PushStyleColor(ImGuiCol_ScrollbarBg, bgMedium);
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrab, bgLighter);
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabHovered, borderDark);
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabActive, goldDark);
    imgui.PushStyleColor(ImGuiCol_Separator, borderDark);
    imgui.PushStyleColor(ImGuiCol_PopupBg, bgMedium);
    imgui.PushStyleColor(ImGuiCol_Tab, tabColor);
    imgui.PushStyleColor(ImGuiCol_TabHovered, tabHoverColor);
    imgui.PushStyleColor(ImGuiCol_TabActive, tabActiveColor);
    imgui.PushStyleColor(ImGuiCol_TabUnfocused, bgDark);
    imgui.PushStyleColor(ImGuiCol_TabUnfocusedActive, bgMedium);
    imgui.PushStyleColor(ImGuiCol_ResizeGrip, goldDarker);
    imgui.PushStyleColor(ImGuiCol_ResizeGripHovered, goldDark);
    imgui.PushStyleColor(ImGuiCol_ResizeGripActive, gold);

    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {12, 12});
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {6, 4});
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {8, 6});
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 4.0);
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 6.0);
    imgui.PushStyleVar(ImGuiStyleVar_ChildRounding, 4.0);
    imgui.PushStyleVar(ImGuiStyleVar_PopupRounding, 4.0);
    imgui.PushStyleVar(ImGuiStyleVar_ScrollbarRounding, 4.0);
    imgui.PushStyleVar(ImGuiStyleVar_GrabRounding, 4.0);

    imgui.SetNextWindowSize({ 900, 650 }, ImGuiCond_FirstUseEver);
    if(imgui.Begin("XIUI Config - v" .. addon.version, showConfig, bit.bor(ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoDocking))) then
        local windowWidth = imgui.GetContentRegionAvail();
        local sidebarWidth = 180;
        local contentWidth = windowWidth - sidebarWidth - 20;

        -- Top bar with reset buttons and social links
        if(imgui.Button("Reset Settings")) then
            showRestoreDefaultsConfirm = true;
        end
        imgui.SameLine();
        if(imgui.Button("Reset Colors")) then
            showRestoreColorsConfirm = true;
        end
        -- Load social icon textures if not loaded
        if discordTexture == nil then
            discordTexture = LoadTexture("socials/discord");
        end
        if githubTexture == nil then
            githubTexture = LoadTexture("socials/github");
        end
        if heartTexture == nil then
            heartTexture = LoadTexture("socials/heart");
        end

        -- Social icon buttons with square background boxes
        local boxSize = 26;
        local boxSpacing = 4;
        local iconSize = 18;
        local iconPad = (boxSize - iconSize) / 2;
        local outlineColor = imgui.GetColorU32(borderDark);

        imgui.SameLine();
        imgui.SetCursorPosX(windowWidth - (boxSize * 3) - (boxSpacing * 2));

        -- Discord button
        if discordTexture ~= nil and discordTexture.image ~= nil then
            local screenPosX, screenPosY = imgui.GetCursorScreenPos();
            local isHovered = imgui.IsMouseHoveringRect({screenPosX, screenPosY}, {screenPosX + boxSize, screenPosY + boxSize});

            -- Draw box background and outline
            local draw_list = imgui.GetWindowDrawList();
            local boxColor = isHovered and imgui.GetColorU32(bgLighter) or imgui.GetColorU32(bgLight);
            draw_list:AddRectFilled(
                {screenPosX, screenPosY},
                {screenPosX + boxSize, screenPosY + boxSize},
                boxColor,
                4.0
            );
            draw_list:AddRect(
                {screenPosX, screenPosY},
                {screenPosX + boxSize, screenPosY + boxSize},
                outlineColor,
                4.0
            );

            -- Draw image centered in box
            draw_list:AddImage(
                tonumber(ffi.cast("uint32_t", discordTexture.image)),
                {screenPosX + iconPad, screenPosY + iconPad},
                {screenPosX + iconPad + iconSize, screenPosY + iconPad + iconSize},
                {0, 0}, {1, 1},
                IM_COL32_WHITE
            );

            -- Invisible button for interaction
            imgui.InvisibleButton("discord_btn", { boxSize, boxSize });
            if imgui.IsItemHovered() then
                imgui.SetMouseCursor(ImGuiMouseCursor_Hand);
            end
            if imgui.IsItemClicked() then
                ashita.misc.open_url("https://discord.gg/PDFJebrwN4");
            end
        end

        imgui.SameLine(0, boxSpacing);

        -- GitHub button
        if githubTexture ~= nil and githubTexture.image ~= nil then
            local screenPosX, screenPosY = imgui.GetCursorScreenPos();
            local isHovered = imgui.IsMouseHoveringRect({screenPosX, screenPosY}, {screenPosX + boxSize, screenPosY + boxSize});

            -- Draw box background and outline
            local draw_list = imgui.GetWindowDrawList();
            local boxColor = isHovered and imgui.GetColorU32(bgLighter) or imgui.GetColorU32(bgLight);
            draw_list:AddRectFilled(
                {screenPosX, screenPosY},
                {screenPosX + boxSize, screenPosY + boxSize},
                boxColor,
                4.0
            );
            draw_list:AddRect(
                {screenPosX, screenPosY},
                {screenPosX + boxSize, screenPosY + boxSize},
                outlineColor,
                4.0
            );

            -- Draw image centered in box
            draw_list:AddImage(
                tonumber(ffi.cast("uint32_t", githubTexture.image)),
                {screenPosX + iconPad, screenPosY + iconPad},
                {screenPosX + iconPad + iconSize, screenPosY + iconPad + iconSize},
                {0, 0}, {1, 1},
                IM_COL32_WHITE
            );

            -- Invisible button for interaction
            imgui.InvisibleButton("github_btn", { boxSize, boxSize });
            if imgui.IsItemHovered() then
                imgui.SetMouseCursor(ImGuiMouseCursor_Hand);
            end
            if imgui.IsItemClicked() then
                ashita.misc.open_url("https://github.com/tirem/xiui");
            end
        end

        imgui.SameLine(0, boxSpacing);

        -- Credits button (heart)
        if heartTexture ~= nil and heartTexture.image ~= nil then
            local screenPosX, screenPosY = imgui.GetCursorScreenPos();
            local isHovered = imgui.IsMouseHoveringRect({screenPosX, screenPosY}, {screenPosX + boxSize, screenPosY + boxSize});

            -- Draw box background and outline
            local draw_list = imgui.GetWindowDrawList();
            local boxColor = isHovered and imgui.GetColorU32(bgLighter) or imgui.GetColorU32(bgLight);
            draw_list:AddRectFilled(
                {screenPosX, screenPosY},
                {screenPosX + boxSize, screenPosY + boxSize},
                boxColor,
                4.0
            );
            draw_list:AddRect(
                {screenPosX, screenPosY},
                {screenPosX + boxSize, screenPosY + boxSize},
                outlineColor,
                4.0
            );

            -- Draw image centered in box
            draw_list:AddImage(
                tonumber(ffi.cast("uint32_t", heartTexture.image)),
                {screenPosX + iconPad, screenPosY + iconPad},
                {screenPosX + iconPad + iconSize, screenPosY + iconPad + iconSize},
                {0, 0}, {1, 1},
                IM_COL32_WHITE
            );

            -- Invisible button for interaction
            imgui.InvisibleButton("credits_btn", { boxSize, boxSize });
            if imgui.IsItemHovered() then
                imgui.SetMouseCursor(ImGuiMouseCursor_Hand);
            end
            if imgui.IsItemClicked() then
                showCreditsPopup = true;
            end
        end

        -- Credits popup
        if showCreditsPopup then
            imgui.OpenPopup("Attributions");
            showCreditsPopup = false;
        end

        if imgui.BeginPopupModal("Attributions", true, ImGuiWindowFlags_AlwaysAutoResize) then
            imgui.Text("XIUI - A UI Addon for Final Fantasy XI");
            imgui.Separator();

            imgui.TextColored({1.0, 0.84, 0.0, 1.0}, "Special Thanks");
            imgui.BulletText("atom0s - Ashita framework, and additional support");
            imgui.BulletText("Thorny - GdiFonts library & MobDB, and additional support");
            imgui.NewLine();

            imgui.Separator();
            if imgui.Button("Close", { 120, 0 }) then
                imgui.CloseCurrentPopup();
            end

            imgui.EndPopup();
        end

        -- Reset Settings confirmation popup
        if (showRestoreDefaultsConfirm) then
            imgui.OpenPopup("Confirm Reset Settings");
            showRestoreDefaultsConfirm = false;
        end

        if (imgui.BeginPopupModal("Confirm Reset Settings", true, ImGuiWindowFlags_AlwaysAutoResize)) then
            imgui.Text("Are you sure you want to reset all settings to defaults?");
            imgui.Text("This will reset all your customizations including:");
            imgui.BulletText("UI positions, scales, and visibility");
            imgui.BulletText("Font settings");
            imgui.NewLine();

            if (imgui.Button("Confirm", { 120, 0 })) then
                ResetSettings();
                UpdateSettings();
                imgui.CloseCurrentPopup();
            end
            imgui.SameLine();
            if (imgui.Button("Cancel", { 120, 0 })) then
                imgui.CloseCurrentPopup();
            end

            imgui.EndPopup();
        end

        -- Reset Colors confirmation popup
        if (showRestoreColorsConfirm) then
            imgui.OpenPopup("Confirm Reset Colors");
            showRestoreColorsConfirm = false;
        end

        if (imgui.BeginPopupModal("Confirm Reset Colors", true, ImGuiWindowFlags_AlwaysAutoResize)) then
            imgui.Text("Are you sure you want to restore all colors to defaults?");
            imgui.Text("This will reset all your custom colors.");
            imgui.NewLine();

            if (imgui.Button("Confirm", { 120, 0 })) then
                gConfig.colorCustomization = deep_copy_table(defaultUserSettings.colorCustomization);
                UpdateSettings();
                imgui.CloseCurrentPopup();
            end
            imgui.SameLine();
            if (imgui.Button("Cancel", { 120, 0 })) then
                imgui.CloseCurrentPopup();
            end

            imgui.EndPopup();
        end

        imgui.Spacing();

        -- Main layout: sidebar + content area
        -- Left sidebar with category buttons
        imgui.BeginChild("Sidebar", { sidebarWidth, 0 }, ImGuiChildFlags_None);

        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {10, 8});

        for i, category in ipairs(categories) do
            -- Style the button differently if selected
            if i == selectedCategory then
                imgui.PushStyleColor(ImGuiCol_Button, selectedButtonColor);
                imgui.PushStyleColor(ImGuiCol_ButtonHovered, selectedButtonColor);
                imgui.PushStyleColor(ImGuiCol_ButtonActive, selectedButtonColor);
            else
                imgui.PushStyleColor(ImGuiCol_Button, {0, 0, 0, 0});
                imgui.PushStyleColor(ImGuiCol_ButtonHovered, buttonHoverColor);
                imgui.PushStyleColor(ImGuiCol_ButtonActive, buttonActiveColor);
            end

            -- Get position before drawing button for accent bar
            local btnPosX, btnPosY = imgui.GetCursorScreenPos();

            if (imgui.Button(category.label, { sidebarWidth - 16, 32 })) then
                selectedCategory = i;
            end

            -- Draw gold accent bar on the left edge for selected category
            if i == selectedCategory then
                local draw_list = imgui.GetWindowDrawList();
                draw_list:AddRectFilled(
                    {btnPosX, btnPosY + 4},
                    {btnPosX + 3, btnPosY + 28},
                    imgui.GetColorU32(gold),
                    1.5
                );
            end

            imgui.PopStyleColor(3);
        end

        imgui.PopStyleVar();
        imgui.EndChild();

        imgui.SameLine();

        -- Right content area
        imgui.BeginChild("ContentArea", { 0, 0 }, ImGuiChildFlags_None);

        -- Tab bar at top of content area
        local tabWidth = 140;
        local tabHeight = 28;

        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {12, 6});

        -- Settings tab
        local tabPosX, tabPosY = imgui.GetCursorScreenPos();
        if selectedTab == 1 then
            imgui.PushStyleColor(ImGuiCol_Button, tabSelectedColor);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, tabSelectedColor);
            imgui.PushStyleColor(ImGuiCol_ButtonActive, tabSelectedColor);
        else
            imgui.PushStyleColor(ImGuiCol_Button, tabColor);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, tabHoverColor);
            imgui.PushStyleColor(ImGuiCol_ButtonActive, tabActiveColor);
        end
        if (imgui.Button("settings", { tabWidth, tabHeight })) then
            selectedTab = 1;
        end
        -- Draw gold underline for selected tab
        if selectedTab == 1 then
            local draw_list = imgui.GetWindowDrawList();
            draw_list:AddRectFilled(
                {tabPosX + 4, tabPosY + tabHeight - 3},
                {tabPosX + tabWidth - 4, tabPosY + tabHeight},
                imgui.GetColorU32(gold),
                1.0
            );
        end
        imgui.PopStyleColor(3);

        imgui.SameLine();

        -- Color settings tab
        local tabPos2X, tabPos2Y = imgui.GetCursorScreenPos();
        if selectedTab == 2 then
            imgui.PushStyleColor(ImGuiCol_Button, tabSelectedColor);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, tabSelectedColor);
            imgui.PushStyleColor(ImGuiCol_ButtonActive, tabSelectedColor);
        else
            imgui.PushStyleColor(ImGuiCol_Button, tabColor);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, tabHoverColor);
            imgui.PushStyleColor(ImGuiCol_ButtonActive, tabActiveColor);
        end
        if (imgui.Button("color settings", { tabWidth, tabHeight })) then
            selectedTab = 2;
        end
        -- Draw gold underline for selected tab
        if selectedTab == 2 then
            local draw_list = imgui.GetWindowDrawList();
            draw_list:AddRectFilled(
                {tabPos2X + 4, tabPos2Y + tabHeight - 3},
                {tabPos2X + tabWidth - 4, tabPos2Y + tabHeight},
                imgui.GetColorU32(gold),
                1.0
            );
        end
        imgui.PopStyleColor(3);

        imgui.PopStyleVar();

        -- Divider between tabs and content
        imgui.Spacing();
        imgui.PushStyleColor(ImGuiCol_Separator, borderDark);
        imgui.Separator();
        imgui.PopStyleColor();
        imgui.Spacing();

        -- Content panel with border
        imgui.BeginChild("SettingsContent", { 0, 0 }, ImGuiChildFlags_None);

        -- Draw the appropriate settings based on selected category and tab
        if selectedTab == 1 then
            if settingsDrawFunctions[selectedCategory] then
                settingsDrawFunctions[selectedCategory]();
            end
        else
            if colorSettingsDrawFunctions[selectedCategory] then
                colorSettingsDrawFunctions[selectedCategory]();
            end
        end

        imgui.EndChild();

        imgui.EndChild();
    end

    imgui.End();
    imgui.PopStyleVar(9);
    imgui.PopStyleColor(34);  -- 26 base + 5 tab colors + 3 resize grip colors
end

return config;
