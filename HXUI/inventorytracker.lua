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
inventoryTracker.DrawWindow = function(settings, userSettings)
    -- Obtain the player entity..

    local player = AshitaCore:GetMemoryManager():GetPlayer();
	if (player == nil) then
		UpdateTextVisibility(false);
		return;
	end

	local mainJob = player:GetMainJob();
    if (player.isZoning or mainJob == 0) then
		UpdateTextVisibility(false);	
        return;
	end

	local inventory = AshitaCore:GetMemoryManager():GetInventory();
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
	local winSizeX = (groupOffsetX * totalGroups);

	--Get max Y size
	local winSizeY = groupOffsetY;

    imgui.SetNextWindowSize({-1, -1}, ImGuiCond_Always);
		
    if (imgui.Begin('InventoryTracker', true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground))) then

		imgui.Dummy({winSizeX,winSizeY});
		local locX, locY = imgui.GetWindowPos();
		local invSlot = 0;

		for i = 1, maxBagSlots do
			local groupNum = math.ceil(i / numPerGroup);
			local offsetFromGroup = i - ((groupNum - 1) * numPerGroup);

			local rowNum = math.ceil(offsetFromGroup / settings.columnCount);
			local columnNum = offsetFromGroup - ((rowNum - 1) * settings.columnCount);
			local x, y = GetDotOffset(rowNum, columnNum, settings);
			x = x + ((groupNum - 1) * groupOffsetX);

			if (i > usedBagSlots) then
				draw_circle({x + locX + imgui.GetStyle().FramePadding.x, y + locY}, settings.dotRadius, {0, 0, 0, 1}, settings.dotRadius * 3, true)
			else
				draw_circle({x + locX + imgui.GetStyle().FramePadding.x, y + locY}, settings.dotRadius, {.1, 0.9, 1, 1}, settings.dotRadius * 3, true)
				draw_circle({x + locX + imgui.GetStyle().FramePadding.x, y + locY}, settings.dotRadius, {0, 0, 0, 1}, settings.dotRadius * 3, false)
			end
		end

		inventoryText:SetText(usedBagSlots.. '/'..maxBagSlots);
		inventoryText:SetPositionX(locX + winSizeX);
		inventoryText:SetPositionY(locY + settings.textOffsetY - inventoryText:GetFontHeight());

		UpdateTextVisibility(true);	
    end
	imgui.End();
end


inventoryTracker.Initialize = function(settings)
    inventoryText = fonts.new(settings.font_settings);
end

inventoryTracker.UpdateFonts = function(settings)
    inventoryText:SetFontHeight(settings.font_settings.font_height);
end


inventoryTracker.SetHidden = function(hidden)
	if (hidden == true) then
		UpdateTextVisibility(false);
	end
end


return inventoryTracker;