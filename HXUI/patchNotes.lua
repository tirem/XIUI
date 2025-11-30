require('common');
local imgui = require('imgui');
local ffi = require('ffi');

local HXUITexture;
local PatchVerTexture;
local NewTexture;
gShowPatchNotes = { true };

local patchNotes = {};

local function InitializeTextures()
	if (HXUITexture == nil) then
		HXUITexture = LoadTexture("patchNotes/hxui");
	end
	if (PatchVerTexture == nil) then
		PatchVerTexture = LoadTexture("patchNotes/patch");
	end
	if (NewTexture == nil) then
		NewTexture = LoadTexture("patchNotes/new");
	end
end

--[[
* event: d3d_present
* desc : Event called when the Direct3D device is presenting a scene.
--]]
patchNotes.DrawWindow = function()
    -- Obtain the player entity..

	if (gShowPatchNotes[1] == false) then
		HXUITexture = nil;
		PatchVerTexture = nil;
		NewTexture = nil;
		gConfig.patchNotesVer = gAdjustedSettings.currentPatchVer;
		UpdateSettings();
		return;
	end

	if (HXUITexture == nil or PatchVerTexture == nil or NewTexture == nil) then
		InitializeTextures();
	end
	if (HXUITexture == nil or PatchVerTexture == nil or NewTexture == nil) then
		return;
	end

	imgui.PushStyleColor(ImGuiCol_WindowBg, {0,0.06,.16,.9});
	imgui.PushStyleColor(ImGuiCol_TitleBg, {0,0.06,.16, .7});
	imgui.PushStyleColor(ImGuiCol_TitleBgActive, {0,0.06,.16, .9});
	imgui.PushStyleColor(ImGuiCol_TitleBgCollapsed, {0,0.06,.16, .5});
	imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 8, 6 });
    if (gShowPatchNotes[1] and imgui.Begin('HXUI PatchNotes', gShowPatchNotes, bit.bor(ImGuiWindowFlags_NoSavedSettings))) then
		-- Save starting Y position for button alignment
		local startY = imgui.GetCursorPosY();

		-- Draw logo and version text
		imgui.Image(tonumber(ffi.cast("uint32_t", HXUITexture.image)), { 83, 53});
		imgui.SameLine();
		imgui.BulletText(' UPDATE 1.4.0-dev ');
		imgui.SameLine();
		imgui.BulletText('');

		local buttonWidth = 120;
		local buttonHeight = 30;
		local imageHeight = 53;
		local contentRegionMax = imgui.GetWindowContentRegionMax();
		local buttonX = contentRegionMax - buttonWidth;
		local buttonY = startY + (imageHeight - buttonHeight) / 2;

		imgui.SetCursorPos({ buttonX, buttonY });
		if(imgui.Button("Open Config", { buttonWidth, buttonHeight })) then
			showConfig[1] = true;
			gShowPatchNotes[1] = false;
		end

		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'New Feature: Color Customizer');
		imgui.BulletText('Use "/hxui color" (or colour..) to open the color customizer');
		imgui.BulletText('Added comprehensive color customization system');
		imgui.BulletText('Customize all text colors (HP, MP, TP, distance, etc.)');
		imgui.BulletText('Customize bar gradient colors or use solid colors');
		imgui.BulletText('Customize entity name colors by type (player/NPC/mob/claimed)');
		imgui.BulletText('Customize texture tint colors for all UI elements');
		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Font System Improvements');
		imgui.BulletText('Changed font sizing from scale to pixel-based for better control');
		imgui.BulletText('Added font weight options (Normal/Bold)');
		imgui.BulletText('Added outline thickness control (0-5 pixels)');
		imgui.BulletText('Individual font size controls for each UI element');
		imgui.BulletText('Migrated all modules to GDI fonts for consistency');
		imgui.BulletText('Fixed font positioning defaults for all modules');
		imgui.BulletText('New dedicated settings category in config menu for fonts');
		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'General Improvements');
		imgui.BulletText('Fixed texture color mixing and rendering issues');
		imgui.BulletText('Updated config menu styling and organization');
		imgui.BulletText('Fixed texture render path initialization');
		imgui.BulletText('Bookends now use gradient colors instead of separate textures');
		imgui.BulletText('Improved gradient rendering for all bar types');
		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Inventory Tracker');
		imgui.BulletText('Added color threshold system for inventory space warnings');
		imgui.BulletText('Improved text rendering and layout');
		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Experience Bar');
		imgui.BulletText('Fixed inline mode positioning logic');
		imgui.BulletText('Improved text position calculation and logic');
		imgui.BulletText('Improved inline mode positioning logic');
		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Party List');
		imgui.BulletText('Improved rendering performance for large parties');
		imgui.BulletText('Enhanced readability with better spacing and layout');
		imgui.BulletText('Fixed background rendering and scaler');
		imgui.BulletText('Added border rendering options');
		imgui.BulletText('Moved cursor indicators to simpler rendering system');
		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Enemy List');
		imgui.BulletText('Updated spacing and layout for better readability');
		imgui.BulletText('Separate font size controls for distance and HP percentage text');
		imgui.BulletText('Customizable border colors for target and subtarget selection');
		imgui.BulletText('Improved entity name colors based on type and claim status');
		imgui.BulletText('Enhanced border rendering options');
		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Target Bar');
		imgui.BulletText('NEW: Enemy cast bars - see when your target is casting!');
		imgui.BulletText('Cast bar shows progress with spell name displayed below');
		imgui.BulletText('Customizable cast bar gradient colors');
		imgui.BulletText('Separate font size control for cast text');
		imgui.BulletText('Improved target-of-target detection using action tracking');
		imgui.BulletText('More reliable combat targeting information');
		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Action Tracker System');
		imgui.BulletText('NEW: Advanced enemy action tracking system');
		imgui.BulletText('Tracks enemy combat actions for better target-of-target detection');
		imgui.BulletText('Monitors basic attacks, magic casts, and weapon skills');
		imgui.BulletText('30-second action history for improved accuracy');
    end
	imgui.PopStyleVar(1);
	imgui.PopStyleColor(4);
	imgui.End();
end

return patchNotes;