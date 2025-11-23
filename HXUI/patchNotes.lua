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
		imgui.BulletText(' UPDATE 1.3.5 ');
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
		imgui.TextColored({0.4, 0.6, 1.0, 1.0}, 'onimitch');
		if imgui.IsItemHovered() then
			imgui.SetMouseCursor(ImGuiMouseCursor_Hand);
			if imgui.IsItemClicked() then
				os.execute('start https://github.com/onimitch');
			end
		end
		imgui.SameLine();
		imgui.TextColored({0.8, 0.8, 0.8, 1.0}, ' and ');
		imgui.SameLine();
		imgui.TextColored({0.4, 0.6, 1.0, 1.0}, 'Rag');
		if imgui.IsItemHovered() then
			imgui.SetMouseCursor(ImGuiMouseCursor_Hand);
			if imgui.IsItemClicked() then
				os.execute('start https://github.com/yzyii');
			end
		end
		imgui.SameLine();
		imgui.TextColored({0.8, 0.8, 0.8, 1.0}, ' for this massive update!');
		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Party List');
		imgui.BulletText('New tiled backgrounds: 8 window themes (Windows 1-8) plus Plain background');
		imgui.BulletText('Party list titles with option to toggle them on/off');
		imgui.BulletText('Preview dummy party data when config is open');
		imgui.BulletText('Added Min Rows, Expand Height, and Align Bottom options');
		imgui.BulletText('Command support: /hxui partylist to toggle party window visibility');
		imgui.BulletText('Added ability to display distance to party members');
		imgui.BulletText('Added ability to highlight party member names when within a set distance');
		imgui.BulletText('Added ability to flash TP when above 100%% (1000 TP)');
		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'ExpBar');
		imgui.BulletText('Added Limit Points mode to track limit points instead of experience');
		imgui.BulletText('Added inline mode for compact display');
		imgui.BulletText('Added options to show/hide text and percentage');
		imgui.BulletText('Improved text positioning');
		imgui.BulletText('Fixed ExpBar not updating immediately after kills in limit mode');
		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Target Bar');
		imgui.BulletText('Added ability to hide distance display');
		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Cast Bar');
		imgui.BulletText('Added fast cast calculations so casts finish at 100%% instead of 75%% or lower');
		imgui.BulletText('Default values provided based on BiS for 75-era and can be adjusted');
		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Debuff Handling');
		imgui.BulletText('Fixed timers for multiple debuffs for 75-era');
		imgui.BulletText('Fixed dispels not removing buff icons correctly');
		imgui.BulletText('Fixed Sleep II not removing Sleep I icon');
		imgui.BulletText('Fixed Diabolos Nightmare tracking');
		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Japanese Text Support');
		imgui.BulletText('Cast bar now uses Thorny gdifonts to properly render Japanese text');
		imgui.BulletText('Fixed Japanese Spell and Ability names appearing as garbled characters');
		imgui.BulletText('Fixed Japanese text rendering in status icon tooltips');
		imgui.NewLine();
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Other Improvements');
		imgui.BulletText('Hide during events option for global, player bar, target bar, and party list');
		imgui.BulletText('Gil Tracker: Added Position Offset and Right Align options');
		imgui.BulletText('Inventory Tracker: Added Rows, Columns, Opacity, and Show Count Text options');
		imgui.BulletText('Enemy List: Enemies now hidden from list once HP reaches 0');
		imgui.BulletText('Enemy List: Added ability to display distance to enemies');
		imgui.BulletText('Status Handler: Added Tooltip scale config');
		imgui.BulletText('Fixed addon error when alignBottom is enabled on first load');
    end
	imgui.PopStyleVar(1);
	imgui.PopStyleColor(4);
	imgui.End();
end

return patchNotes;