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
local castcostModule = require('config.castcost');
local petbarModule = require('config.petbar');
local notificationsModule = require('config.notifications');
local treasurepoolModule = require('config.treasurepool');
local hotbarModule = require('config.hotbar');

local treasurePool = require('modules.treasurepool.init');

local config = {};

-- Track previous config state to detect when config closes
local wasConfigOpen = false;

-- Global modal state (accessible by other modules to know when to dim foreground elements)
_XIUI_MODAL_OPEN = false;

-- Helper function to render a social icon button with box background
local function RenderSocialButton(texture, buttonId, onClickCallback, bgLight, bgLighter, borderDark, boxSize, iconSize)
    if texture == nil or texture.image == nil then
        return;
    end

    local iconPad = (boxSize - iconSize) / 2;
    local screenPosX, screenPosY = imgui.GetCursorScreenPos();
    local isHovered = imgui.IsMouseHoveringRect({screenPosX, screenPosY}, {screenPosX + boxSize, screenPosY + boxSize});

    -- Draw box background and outline
    local draw_list = imgui.GetWindowDrawList();
    local boxColor = isHovered and imgui.GetColorU32(bgLighter) or imgui.GetColorU32(bgLight);
    local outlineColor = imgui.GetColorU32(borderDark);
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
        tonumber(ffi.cast("uint32_t", texture.image)),
        {screenPosX + iconPad, screenPosY + iconPad},
        {screenPosX + iconPad + iconSize, screenPosY + iconPad + iconSize},
        {0, 0}, {1, 1},
        IM_COL32_WHITE
    );

    -- Invisible button for interaction
    imgui.InvisibleButton(buttonId, { boxSize, boxSize });
    if imgui.IsItemHovered() then
        imgui.SetMouseCursor(ImGuiMouseCursor_Hand);
    end
    if imgui.IsItemClicked() then
        onClickCallback();
    end
end

-- State for confirmation dialogs
local showRestoreDefaultsConfirm = false;

-- Social icon textures
local discordTexture = nil;
local githubTexture = nil;
local heartTexture = nil;
local refreshTexture = nil;

-- Credits popup state
local creditsWindowOpen = { false };

-- Profile management state
local showProfilesWindow = { false };
local newProfileName = { "" };
local renameProfileName = { "" };
local profileToDelete = nil;
local showDeleteProfileConfirm = false;
local showRenameProfilePopup = false;
local showNewProfilePopup = false;

-- Triggers for external commands
local triggerNewProfilePopup = false;
local triggerDeleteProfilePopup = false;
local triggerRenameProfilePopup = false;

-- XIUI Theme Colors (dark + gold accent)
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

local function PushThemeStyles()
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
end

local function PopThemeStyles()
    imgui.PopStyleVar(9);
    imgui.PopStyleColor(34);
end

local function DrawProfilesWindow()
    if (not showProfilesWindow[1]) then return; end

    PushThemeStyles();

    imgui.SetNextWindowSize({ 330, 135 }, ImGuiCond_Always);
    -- Using + for flags as they are typically integers
    if (imgui.Begin("Profiles", showProfilesWindow, ImGuiWindowFlags_NoCollapse + ImGuiWindowFlags_NoResize)) then


        local currentProfile = GetCurrentProfileName();
        local profiles = GetProfileNames();

        -- Profile List Dropdown
        imgui.Text("Active Profile:");
        imgui.SetNextItemWidth(-1);
        if (imgui.BeginCombo("##ProfileSelect", currentProfile)) then
            for _, name in ipairs(profiles) do
                local isSelected = (name == currentProfile);
                if (imgui.Selectable(name, isSelected)) then
                    RequestProfileChange(name);
                end
                if (isSelected) then
                    imgui.SetItemDefaultFocus();
                end
            end
            imgui.EndCombo();
        end

        imgui.Spacing();
        imgui.Spacing();

        -- Calculate button widths and positions for centering
        -- Using fixed estimates or CalcTextSize if possible.
        -- To be safe and consistent, we'll try to calculate.
        
        local style = imgui.GetStyle();
        local spacing = style.ItemSpacing.x;
        local padding = style.FramePadding.x * 2;
        
        -- Helper to get width
        local function getBtnWidth(text)
            return imgui.CalcTextSize(text) + padding;
        end
        
        local wNew = math.max(getBtnWidth("New"), 50);
        local wDup = math.max(getBtnWidth("Duplicate"), 50);
        local wRen = math.max(getBtnWidth("Rename"), 50);
        local wDel = math.max(getBtnWidth("Delete"), 50);
        
        local totalWidth = wNew + wDup + wRen + wDel + (spacing * 3);
        local avail = imgui.GetContentRegionAvail();
        local startX = (avail - totalWidth) * 0.5;
        if (startX < 0) then startX = 0; end
        
        imgui.SetCursorPosX(startX);

        -- Compact Profile Actions
        if (imgui.Button("New", { wNew, 0 })) then
            newProfileName[1] = "";
            showNewProfilePopup = true;
            triggerNewProfilePopup = true;
        end

        imgui.SameLine();
        
        -- Duplicate Button (Disabled if Default? Maybe allowed for Default to copy it)
        -- We'll allow duplicating Default.
        if (imgui.Button("Duplicate", { wDup, 0 })) then
            DuplicateProfile(currentProfile);
        end

        imgui.SameLine();

        -- Rename Button (Disabled if Default)
        if (currentProfile == "Default") then
            imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.5);
            imgui.Button("Rename", { wRen, 0 });
            imgui.PopStyleVar();
        else
            if (imgui.Button("Rename", { wRen, 0 })) then
                renameProfileName[1] = currentProfile;
                showRenameProfilePopup = true;
                triggerRenameProfilePopup = true;
            end
        end

        imgui.SameLine();

        -- Delete Button (Disabled if Default)
        if (currentProfile == "Default") then
            imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.5);
            imgui.Button("Delete", { wDel, 0 });
            imgui.PopStyleVar();
        else
            if (imgui.Button("Delete", { wDel, 0 })) then
                profileToDelete = currentProfile;
                showDeleteProfileConfirm = true;
                triggerDeleteProfilePopup = true;
            end
        end



        imgui.End();
    end

    PopThemeStyles();
end

-- Navigation state
local selectedCategory = 1;  -- 1-indexed category selection
local selectedTab = 1;       -- 1 = settings, 2 = color settings
local selectedPartyTab = 1;  -- 1 = Party A, 2 = Party B, 3 = Party C
local selectedPartyColorTab = 1;  -- 1 = Party A, 2 = Party B, 3 = Party C (for color settings)
local selectedInventoryTab = 1;  -- 1 = Inventory, 2 = Satchel
local selectedInventoryColorTab = 1;  -- 1 = Inventory, 2 = Satchel (for color settings)
local selectedTargetBarTab = 1;  -- 1 = Target Bar, 2 = Mob Info
local selectedTargetBarColorTab = 1;  -- 1 = Target Bar, 2 = Mob Info (for color settings)
local selectedPetBarTab = 1;  -- 1 = Pet Bar, 2 = Pet Target
local selectedPetTypeTab = 1;  -- 1 = Avatar, 2 = Charm, 3 = Jug, 4 = Automaton, 5 = Wyvern
local selectedPetTypeColorTab = 1;  -- Pet type color sub-tab
local selectedPetBarColorTab = 1;  -- 1 = Pet Bar, 2 = Pet Target (for color settings)
local selectedHotbarTab = 1;  -- 1 = Bar 1, 2 = Bar 2, etc. (for hotbar settings)
local selectedModeTab = 'hotbar';  -- 'hotbar' or 'crossbar' (for hotbar/crossbar toggle in 'both' mode)
local selectedCrossbarTab = 1;  -- 1=L2, 2=R2, 3=L2R2, 4=R2L2, 5=L2x2, 6=R2x2

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
    { name = 'castCost', label = 'Cast Cost' },
    { name = 'petBar', label = 'Pet Bar' },
    { name = 'notifications', label = 'Notifications' },
    { name = 'treasurePool', label = 'Treasure Pool' },
    { name = 'hotbar', label = 'Hotbar' },
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
        selectedPetBarTab = selectedPetBarTab,
        selectedPetBarColorTab = selectedPetBarColorTab,
        selectedPetTypeTab = selectedPetTypeTab,
        selectedPetTypeColorTab = selectedPetTypeColorTab,
        selectedHotbarTab = selectedHotbarTab,
        selectedModeTab = selectedModeTab,
        selectedCrossbarTab = selectedCrossbarTab,
        githubTexture = githubTexture,
    };
end

-- Apply returned state from modules
local function applySettingsState(newState)
    if newState then
        if newState.selectedPartyTab then selectedPartyTab = newState.selectedPartyTab; end
        if newState.selectedInventoryTab then selectedInventoryTab = newState.selectedInventoryTab; end
        if newState.selectedTargetBarTab then selectedTargetBarTab = newState.selectedTargetBarTab; end
        if newState.selectedPetBarTab then selectedPetBarTab = newState.selectedPetBarTab; end
        if newState.selectedPetTypeTab then selectedPetTypeTab = newState.selectedPetTypeTab; end
        if newState.selectedHotbarTab then selectedHotbarTab = newState.selectedHotbarTab; end
        if newState.selectedModeTab then selectedModeTab = newState.selectedModeTab; end
        if newState.selectedCrossbarTab then selectedCrossbarTab = newState.selectedCrossbarTab; end
    end
end

local function applyColorState(newState)
    if newState then
        if newState.selectedPartyColorTab then selectedPartyColorTab = newState.selectedPartyColorTab; end
        if newState.selectedInventoryColorTab then selectedInventoryColorTab = newState.selectedInventoryColorTab; end
        if newState.selectedTargetBarColorTab then selectedTargetBarColorTab = newState.selectedTargetBarColorTab; end
        if newState.selectedPetBarColorTab then selectedPetBarColorTab = newState.selectedPetBarColorTab; end
        if newState.selectedPetTypeColorTab then selectedPetTypeColorTab = newState.selectedPetTypeColorTab; end
        if newState.selectedHotbarTab then selectedHotbarTab = newState.selectedHotbarTab; end
        if newState.selectedModeTab then selectedModeTab = newState.selectedModeTab; end
        if newState.selectedCrossbarTab then selectedCrossbarTab = newState.selectedCrossbarTab; end
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

local function DrawCastCostSettings()
    castcostModule.DrawSettings();
end

local function DrawPetBarSettings()
    local newState = petbarModule.DrawSettings(buildState());
    applySettingsState(newState);
end

local function DrawNotificationsSettings()
    notificationsModule.DrawSettings();
end

local function DrawTreasurePoolSettings()
    treasurepoolModule.DrawSettings();
end

local function DrawHotbarSettings()
    local newState = hotbarModule.DrawSettings(buildState());
    applySettingsState(newState);
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

local function DrawCastCostColorSettings()
    castcostModule.DrawColorSettings();
end

local function DrawPetBarColorSettings()
    local newState = petbarModule.DrawColorSettings(buildState());
    applyColorState(newState);
end

local function DrawNotificationsColorSettings()
    notificationsModule.DrawColorSettings();
end

local function DrawTreasurePoolColorSettings()
    treasurepoolModule.DrawColorSettings();
end

local function DrawHotbarColorSettings()
    local newState = hotbarModule.DrawColorSettings(buildState());
    applyColorState(newState);
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
    DrawCastCostSettings,
    DrawPetBarSettings,
    DrawNotificationsSettings,
    DrawTreasurePoolSettings,
    DrawHotbarSettings,
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
    DrawCastCostColorSettings,
    DrawPetBarColorSettings,
    DrawNotificationsColorSettings,
    DrawTreasurePoolColorSettings,
    DrawHotbarColorSettings,
};

local function DrawProfilePopups()
    local isModalOpen = false;

    -- Triggers
    if (triggerNewProfilePopup) then
        imgui.OpenPopup("New Profile");
        triggerNewProfilePopup = false;
    end
    if (triggerRenameProfilePopup) then
        imgui.OpenPopup("Rename Profile");
        triggerRenameProfilePopup = false;
    end
    if (triggerDeleteProfilePopup) then
        imgui.OpenPopup("Delete Profile");
        triggerDeleteProfilePopup = false;
    end

    -- New Profile Popup
    if (imgui.BeginPopupModal("New Profile", true, ImGuiWindowFlags_AlwaysAutoResize)) then
        isModalOpen = true;
        imgui.Text("Create New Profile:");
        imgui.InputText("##NewProfileName", newProfileName, 32);
        
        imgui.NewLine();
        if (imgui.Button("Create", { 120, 0 })) then
            local name = newProfileName[1];
            if (name ~= "" and name ~= "Default") then
                if (CreateProfile(name)) then
                    newProfileName[1] = ""; -- Clear input
                    imgui.CloseCurrentPopup();
                end
            end
        end
        imgui.SameLine();
        if (imgui.Button("Cancel", { 120, 0 })) then
            imgui.CloseCurrentPopup();
        end
        imgui.EndPopup();
    end

    -- Rename Popup
    if (imgui.BeginPopupModal("Rename Profile", true, ImGuiWindowFlags_AlwaysAutoResize)) then
        isModalOpen = true;
        imgui.Text("Rename '" .. GetCurrentProfileName() .. "' to:");
        imgui.InputText("##RenameInput", renameProfileName, 32);
        
        imgui.NewLine();
        if (imgui.Button("Rename", { 120, 0 })) then
            local newName = renameProfileName[1];
            if (newName ~= "" and newName ~= "Default") then
                if (RenameProfile(GetCurrentProfileName(), newName)) then
                    imgui.CloseCurrentPopup();
                end
            end
        end
        imgui.SameLine();
        if (imgui.Button("Cancel", { 120, 0 })) then
            imgui.CloseCurrentPopup();
        end
        imgui.EndPopup();
    end

    -- Delete Confirmation Popup
    if (imgui.BeginPopupModal("Delete Profile", true, ImGuiWindowFlags_AlwaysAutoResize)) then
        isModalOpen = true;
        imgui.Text("Are you sure you want to delete profile:");
        imgui.TextColored({1.0, 0.3, 0.3, 1.0}, profileToDelete);
        imgui.Text("This action cannot be undone!");
        
        imgui.NewLine();
        if (imgui.Button("Yes, Delete", { 120, 0 })) then
            if (DeleteProfile(profileToDelete)) then
                imgui.CloseCurrentPopup();
            end
        end
        imgui.SameLine();
        if (imgui.Button("Cancel", { 120, 0 })) then
            imgui.CloseCurrentPopup();
        end
        imgui.EndPopup();
    end
    
    return isModalOpen;
end

config.DrawWindow = function(us)
    DrawProfilesWindow();

    -- Detect when config closes and clear treasure pool preview
    local isConfigOpen = showConfig[1];
    if wasConfigOpen and not isConfigOpen then
        -- Config just closed - clear preview state and reset settings
        treasurePool.ClearPreview();
        gConfig.treasurePoolMiniPreview = false;
        gConfig.treasurePoolFullPreview = false;
    end
    wasConfigOpen = isConfigOpen;

    -- Early exit if config window isn't shown (atom0s recommendation)
    -- This prevents unnecessary style pushes and imgui.End() calls when window is hidden
    if (not showConfig[1]) then return; end

    -- XIUI Theme Colors (dark + gold accent)
    PushThemeStyles();

    imgui.SetNextWindowSize({ 900, 650 }, ImGuiCond_FirstUseEver);
    if(imgui.Begin("XIUI Config - v" .. addon.version, showConfig, bit.bor(ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoDocking))) then
        local windowWidth = imgui.GetContentRegionAvail();
        local sidebarWidth = 180;
        local contentWidth = windowWidth - sidebarWidth - 20;

        -- Top bar with reset buttons and social links
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
        if refreshTexture == nil then
            refreshTexture = LoadTexture('icons/refresh.png');
        end

        -- Social icon buttons with square background boxes
        local boxSize = 26;
        local boxSpacing = 4;
        local iconSize = 18;

        -- Adjust padding to match social button height (26px)
        -- Standard font is typically 13-14px. 26 - 13 = 13. 13/2 = 6.5.
        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {8, 6});

        -- Profiles Button
        imgui.PushStyleColor(ImGuiCol_Button, bgLight);
        if (imgui.Button("Profiles", { 0, 26 })) then
            showProfilesWindow[1] = true;
        end
        imgui.PopStyleColor();
        
        imgui.SameLine();
        imgui.PushItemWidth(300); -- Increased width for profile select
        local currentProfile = GetCurrentProfileName();
        local profiles = GetProfileNames();
        
        if (imgui.BeginCombo("##QuickProfileSelect", currentProfile)) then
            for _, name in ipairs(profiles) do
                local isSelected = (name == currentProfile);
                if (imgui.Selectable(name, isSelected)) then
                    if (name ~= currentProfile) then
                        RequestProfileChange(name);
                    end
                end
                if (isSelected) then
                    imgui.SetItemDefaultFocus();
                end
            end
            imgui.EndCombo();
        end

        imgui.PopItemWidth();
        imgui.PopStyleVar(); -- Restore padding

        imgui.SameLine();

        -- Refresh/Reset Button (Using RenderSocialButton for consistent look)
        RenderSocialButton(refreshTexture, "refresh_btn", function()
            showRestoreDefaultsConfirm = true;
        end, bgLight, bgLighter, borderDark, boxSize, iconSize);

        imgui.SameLine();
        imgui.ShowHelp('Reset current profile settings.');

        imgui.SameLine();
        imgui.SetCursorPosX(windowWidth - (boxSize * 3) - (boxSpacing * 2));

        -- Discord button
        RenderSocialButton(discordTexture, "discord_btn", function()
            ashita.misc.open_url("https://discord.gg/PDFJebrwN4");
        end, bgLight, bgLighter, borderDark, boxSize, iconSize);

        imgui.SameLine(0, boxSpacing);

        -- GitHub button
        RenderSocialButton(githubTexture, "github_btn", function()
            ashita.misc.open_url("https://github.com/tirem/xiui");
        end, bgLight, bgLighter, borderDark, boxSize, iconSize);

        imgui.SameLine(0, boxSpacing);

        -- Credits button (heart)
        RenderSocialButton(heartTexture, "credits_btn", function()
            creditsWindowOpen[1] = not creditsWindowOpen[1];
        end, bgLight, bgLighter, borderDark, boxSize, iconSize);

        -- Track modal state for foreground elements dimming
        local anyModalOpen = false;

        -- Credits window (simple floating popup)
        if creditsWindowOpen[1] then
            local creditsFlags = bit.bor(
                ImGuiWindowFlags_AlwaysAutoResize,
                ImGuiWindowFlags_NoCollapse,
                ImGuiWindowFlags_NoSavedSettings
            );
            imgui.PushStyleColor(ImGuiCol_WindowBg, bgDark);
            imgui.PushStyleColor(ImGuiCol_TitleBg, bgMedium);
            imgui.PushStyleColor(ImGuiCol_TitleBgActive, bgLight);
            imgui.PushStyleColor(ImGuiCol_Border, borderDark);
            imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 6.0);
            imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {12, 12});

            if imgui.Begin("Attributions###CreditsWindow", creditsWindowOpen, creditsFlags) then
                imgui.Text("XIUI - A UI Addon for Final Fantasy XI");
                imgui.Separator();

                imgui.TextColored({1.0, 0.84, 0.0, 1.0}, "Special Thanks");
                imgui.BulletText("atom0s - Ashita framework, and additional support");
                imgui.BulletText("Thorny - GdiFonts library & MobDB, and additional support");
            end
            imgui.End();

            imgui.PopStyleVar(2);
            imgui.PopStyleColor(4);
        end

        -- Reset Settings confirmation popup
        if (showRestoreDefaultsConfirm) then
            imgui.OpenPopup("Confirm Reset Settings");
            showRestoreDefaultsConfirm = false;
        end

        if (imgui.BeginPopupModal("Confirm Reset Settings", true, ImGuiWindowFlags_AlwaysAutoResize)) then
            anyModalOpen = true;
            imgui.Text("Are you sure you want to reset all settings to defaults?");
            imgui.Text("This will reset all your customizations including:");
            imgui.BulletText("UI positions, scales, and visibility");
            imgui.BulletText("Color settings and themes");
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



        -- Update global modal state for other modules
        if (DrawProfilePopups()) then
            anyModalOpen = true;
        end

        _XIUI_MODAL_OPEN = anyModalOpen;

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

    -- Draw migration wizard if open (after main window so it overlays)
    if hotbarModule.migrationWizard then
        hotbarModule.migrationWizard.Draw();
    end

    PopThemeStyles();
end

function config.OpenNewProfilePopup()
    showConfig[1] = true;
    triggerNewProfilePopup = true;
    if newProfileName[1] then newProfileName[1] = ""; end
end

function config.OpenDeleteProfilePopup(name)
    showConfig[1] = true;
    triggerDeleteProfilePopup = true;
    profileToDelete = name;
end

function config.OpenRenameProfilePopup(name)
    showConfig[1] = true;
    triggerRenameProfilePopup = true;
    renameProfileName[1] = name;
end

function config.OpenResetSettingsPopup()
    showConfig[1] = true;
    showRestoreDefaultsConfirm = true;
end

return config;
