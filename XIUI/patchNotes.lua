require('common');
local imgui = require('imgui');
local ffi = require('ffi');

local XIUITexture;
local PatchVerTexture;
local NewTexture;
gShowPatchNotes = { true };

local patchNotes = {};

local function InitializeTextures()
	if (XIUITexture == nil) then
		XIUITexture = LoadTexture("patchNotes/xiui");
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
		XIUITexture = nil;
		PatchVerTexture = nil;
		NewTexture = nil;
		gConfig.patchNotesVer = gAdjustedSettings.currentPatchVer;
		UpdateSettings();
		return;
	end

	if (XIUITexture == nil or PatchVerTexture == nil or NewTexture == nil) then
		InitializeTextures();
	end
	if (XIUITexture == nil or PatchVerTexture == nil or NewTexture == nil) then
		return;
	end

	imgui.PushStyleColor(ImGuiCol_WindowBg, {0,0.06,.16,.9});
	imgui.PushStyleColor(ImGuiCol_TitleBg, {0,0.06,.16, .7});
	imgui.PushStyleColor(ImGuiCol_TitleBgActive, {0,0.06,.16, .9});
	imgui.PushStyleColor(ImGuiCol_TitleBgCollapsed, {0,0.06,.16, .5});
	imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 8, 6 });
    if (gShowPatchNotes[1] and imgui.Begin('XIUI PatchNotes', gShowPatchNotes, bit.bor(ImGuiWindowFlags_NoSavedSettings))) then
		-- Save starting Y position for button alignment
		local startY = imgui.GetCursorPosY();

		-- Draw logo and version text
		imgui.Image(tonumber(ffi.cast("uint32_t", XIUITexture.image)), { 83, 53});
		imgui.SameLine();
		imgui.BulletText('UPDATE 1.4.2');
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
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'KNOWN ISSUES');
		imgui.BulletText('Enemy List may cause performance issues when showing large lists of enemies.\nDisable the enemy list if you encounter issues.');
		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'General Improvements');
		imgui.BulletText('Added migration from HXUI to XIUI');
		imgui.BulletText('Fixed targeting icon in party list position');
		imgui.BulletText('Fixed target lock issue');
		
    end
	imgui.PopStyleVar(1);
	imgui.PopStyleColor(4);
	imgui.End();
end

return patchNotes;