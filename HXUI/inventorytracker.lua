require('common');
local imgui = require('imgui');
local fonts = require('fonts');

local inventoryText;

local inventoryTracker = {};

local function UpdateTextVisibility(visible)
	inventoryText:SetVisible(visible);
end

local function GetDotOffset(row, column, settings)

	-- assumes we start at 0,0
	local x;
	local y;

	x = (column * settings.dotRadius * 2) + (settings.dotSpacing * (column - 1));
	y = (row * settings.dotRadius * 2) + (settings.dotSpacing * (row - 1));

	return x, y;
end

--[[
* event: d3d_present
* desc : Event called when the Direct3D device is presenting a scene.
--]]
inventoryTracker.DrawWindow = function(settings)
    -- Obtain the player entity..

    local player = GetPlayerSafe();
	if (player == nil) then
		UpdateTextVisibility(false);
		return;
	end

	local mainJob = player:GetMainJob();
    if (player.isZoning or mainJob == 0) then
		UpdateTextVisibility(false);
        return;
	end

	local inventory = GetInventorySafe();
	if (inventory == nil) then
		UpdateTextVisibility(false);
		return;
	end
	
	local usedBagSlots = inventory:GetContainerCount(0);
	local maxBagSlots = inventory:GetContainerCountMax(0);

	-- Get max X size
	local groupOffsetX, groupOffsetY = GetDotOffset(settings.rowCount, settings.columnCount, settings);
	groupOffsetX = groupOffsetX + settings.groupSpacing;
	local numPerGroup = settings.rowCount * settings.columnCount;
	local totalGroups = math.ceil(maxBagSlots / numPerGroup);

	-- Window size calculation:
	-- - groupOffsetX gives us spacing between groups (includes last dot center + group spacing)
	-- - Multiply by totalGroups and subtract extra groupSpacing to get last dot center
	-- - Add dotRadius to get to the edge of the last dot
	-- - Add FramePadding.x since we offset all dots by this amount when drawing
	-- - Add extra dotRadius to account for the first dot's offset (dots start at 2*dotRadius center, not 0)
	-- - Add 1 pixel for outline thickness (unfilled circles have 1px outline extending beyond radius)
	local style = imgui.GetStyle();
	local framePaddingX = style.FramePadding.x;
	local windowPaddingX = style.WindowPadding.x;
	local windowPaddingY = style.WindowPadding.y;
	local outlineThickness = 1; -- draw_circle uses thickness of 1 for outlines

	local winSizeX = (groupOffsetX * totalGroups) - settings.groupSpacing + settings.dotRadius + framePaddingX + windowPaddingX + outlineThickness;

	-- Get max Y size
	-- - groupOffsetY gives us the center of the last row dot
	-- - Add dotRadius to get to the bottom edge of the last dot
	-- - Add extra dotRadius to account for the first dot's offset
	-- - Add windowPaddingY to account for ImGui's internal window padding
	-- - Add 1 pixel for outline thickness (unfilled circles have 1px outline extending beyond radius)
	local winSizeY = groupOffsetY + settings.dotRadius + windowPaddingY + outlineThickness;

    imgui.SetNextWindowSize({-1, -1}, ImGuiCond_Always);
		
	local windowFlags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoBringToFrontOnFocus);
	if (gConfig.lockPositions) then
		windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
	end
    if (imgui.Begin('InventoryTracker', true, windowFlags)) then

		imgui.Dummy({winSizeX,winSizeY});
		local locX, locY = imgui.GetWindowPos();

		-- Get custom colors
		local emptyColor = gConfig.colorCustomization.inventoryTracker.emptySlotColor;
		local usedColor = gConfig.colorCustomization.inventoryTracker.usedSlotColor;
		local emptyColorWithOpacity = {emptyColor.r, emptyColor.g, emptyColor.b, emptyColor.a * settings.opacity};
		local usedColorWithOpacity = {usedColor.r, usedColor.g, usedColor.b, usedColor.a * settings.opacity};

		for i = 1, maxBagSlots do
			local groupNum = math.ceil(i / numPerGroup);
			local offsetFromGroup = i - ((groupNum - 1) * numPerGroup);

			local rowNum = math.ceil(offsetFromGroup / settings.columnCount);
			local columnNum = offsetFromGroup - ((rowNum - 1) * settings.columnCount);
			local x, y = GetDotOffset(rowNum, columnNum, settings);
			x = x + ((groupNum - 1) * groupOffsetX);

			if (i > usedBagSlots) then
				draw_circle({x + locX + imgui.GetStyle().FramePadding.x, y + locY}, settings.dotRadius, emptyColorWithOpacity, settings.dotRadius * 3, true)
			else
				draw_circle({x + locX + imgui.GetStyle().FramePadding.x, y + locY}, settings.dotRadius, usedColorWithOpacity, settings.dotRadius * 3, true)
				draw_circle({x + locX + imgui.GetStyle().FramePadding.x, y + locY}, settings.dotRadius, emptyColorWithOpacity, settings.dotRadius * 3, false)
			end
		end

        if (settings.showText) then
            inventoryText:SetText(usedBagSlots.. '/'..maxBagSlots);
            inventoryText:SetPositionX(locX + winSizeX);
		    inventoryText:SetPositionY(locY + settings.textOffsetY - inventoryText:GetFontHeight());
            UpdateTextVisibility(true);
        else
            UpdateTextVisibility(false);
        end
    end
	imgui.End();
end


inventoryTracker.Initialize = function(settings)
    inventoryText = fonts.new(settings.font_settings);
end

inventoryTracker.UpdateFonts = function(settings)
	-- Destroy old font object
	if (inventoryText ~= nil) then inventoryText:destroy(); end

	-- Recreate font object with new settings
    inventoryText = fonts.new(settings.font_settings);
end


inventoryTracker.SetHidden = function(hidden)
	if (hidden == true) then
		UpdateTextVisibility(false);
	end
end


return inventoryTracker;