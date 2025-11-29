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
		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Party List');
		imgui.BulletText('Improved rendering performance (moved to DrawList)');
		imgui.BulletText('Enhanced readability with better spacing and layout');
		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Enemy List');
		imgui.BulletText('Updated spacing and layout for better readability');
		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'General Improvements');
		imgui.BulletText('Fixed texture color mixing and rendering issues');
		imgui.BulletText('Updated config menu styling and organization');
    end
	imgui.PopStyleVar(1);
	imgui.PopStyleColor(4);
	imgui.End();
end

return patchNotes;