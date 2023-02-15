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
    if (gShowPatchNotes[1] and imgui.Begin('HXUI PatchNotes', gShowPatchNotes, bit.bor(ImGuiWindowFlags_NoSavedSettings))) then
		imgui.Image(tonumber(ffi.cast("uint32_t", HXUITexture.image)), { 83, 53});
		imgui.SameLine()
		imgui.Image(tonumber(ffi.cast("uint32_t", PatchVerTexture.image)), { 130, 21});
		imgui.NewLine();
		imgui.Image(tonumber(ffi.cast("uint32_t", NewTexture.image)), { 30, 13});
		imgui.NewLine();
		imgui.BulletText('Cast Bar: Cast spells and move the bar around!');
		imgui.NewLine();
		imgui.BulletText('Added more customization options! (/hxui)');
		imgui.NewLine();
		imgui.BulletText('All menus now hide when appropriate');
		imgui.NewLine();
		imgui.BulletText('Additional icon themes for job icons');
		imgui.NewLine();
		imgui.BulletText('Additional icon themes for buffs & debuffs');
		imgui.NewLine();
		imgui.BulletText('Themed bars across all widgets');
		imgui.NewLine();
		imgui.BulletText('Damage taken visuals for hp bars');
		imgui.NewLine();
		imgui.BulletText('Updated multiple elements visuals');
		imgui.NewLine();
		imgui.BulletText('Better tracking for buffs/debuffs (includes more bard songs!)');
		imgui.NewLine();
    end
	imgui.PopStyleColor(4);
	imgui.End();
end

return patchNotes;