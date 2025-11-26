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
		imgui.BulletText(' UPDATE 1.3.8 ');
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
		imgui.TextColored({0.8, 0.8, 0.8, 1.0}, 'Special thanks to ');
		imgui.SameLine();
		imgui.TextColored({0.4, 0.6, 1.0, 1.0}, 'Rag');
		if imgui.IsItemHovered() then
			imgui.SetMouseCursor(ImGuiMouseCursor_Hand);
			if imgui.IsItemClicked() then
				os.execute('start https://github.com/yzyii');
			end
		end
		imgui.SameLine();
		imgui.TextColored({0.8, 0.8, 0.8, 1.0}, ' for this update!');
		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Cast Bar');
		imgui.BulletText('Added WHM Cure Speed support (Cure Clogs, Minstrel\'s Ring, etc.)');
		imgui.BulletText('Added BRD Sing Speed support (Minstrel\'s Ring, etc.)');
		imgui.BulletText('Cure Speed and Sing Speed work independently from Fast Cast calculations');
    end
	imgui.PopStyleVar(1);
	imgui.PopStyleColor(4);
	imgui.End();
end

return patchNotes;