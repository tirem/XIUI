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
	-- Early exit if patch notes window isn't shown
	if (not gShowPatchNotes[1]) then
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
	if (imgui.Begin('XIUI PatchNotes', gShowPatchNotes, bit.bor(ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoDocking))) then
		-- Save starting Y position for button alignment
		local startY = imgui.GetCursorPosY();

		-- Draw logo and version text
		imgui.Image(tonumber(ffi.cast("uint32_t", XIUITexture.image)), { 83, 53});
		imgui.SameLine();
		imgui.BulletText('UPDATE 1.5.0');
		imgui.SameLine();
		imgui.BulletText('');

		local buttonWidth = 120;
		local buttonHeight = 30;
		local imageHeight = 53;
		-- Use GetContentRegionAvail + GetCursorPosX to calculate max X position
		local contentAvail = imgui.GetContentRegionAvail();
		local cursorX = imgui.GetCursorPosX();
		local buttonX = cursorX + contentAvail - buttonWidth;
		local buttonY = startY + (imageHeight - buttonHeight) / 2;

		imgui.SetCursorPos({ buttonX, buttonY });
		if(imgui.Button("Open Config", { buttonWidth, buttonHeight })) then
			showConfig[1] = true;
			gShowPatchNotes[1] = false;
		end

		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Ashita 4.3 Compatibility');
		imgui.BulletText('Added compatibility layer for upcoming Ashita 4.3 update');
		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Party List');
		imgui.BulletText('TP bars now available for alliance parties (B and C)');
		imgui.BulletText('TP text flashing in compact mode when at 1000+ TP');
		imgui.BulletText('Subtarget highlighting with customizable colors');
		imgui.BulletText('Status icons can now display on left or right side');
		imgui.BulletText('Individual bar scaling for HP, MP, and TP bars in both modes');
		imgui.BulletText('Copy settings between parties feature');
		imgui.BulletText('Zone font size setting');
		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Player Bar');
		imgui.BulletText('TP flash effects now have customizable overlay and flash colors');
		imgui.BulletText('TP flash toggle moved to player bar settings (from global)');
		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Enemy Debuff Tracking');
		imgui.BulletText('Weaponskill debuffs now tracked (Def Down, Att Down, etc.)');
		imgui.BulletText('Supports Shell Crusher, Armor Break, Full Break, and more');
		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'UI Improvements');
		imgui.BulletText('Horizontal color picker layout for HP bar colors');
		imgui.BulletText('Improved config menu party tab styling');
		imgui.BulletText('Fixed bookend scaling with tall bar heights');
		imgui.BulletText('Bookend size setting added to global settings');
	end
	imgui.End();
	imgui.PopStyleVar(1);
	imgui.PopStyleColor(4);
end

return patchNotes;