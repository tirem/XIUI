package.path = './XIUI/?.lua;./XIUI/?/init.lua;' .. package.path;

package.preload['common'] = function()
    return true;
end

local treasureSlot = 4;
local outgoingPackets = {};

local inventory = {};

function inventory:GetTreasurePoolItem(slot)
    if slot == treasureSlot then
        return {
            ItemId = 1234,
            DropTime = 100,
            Lot = 0,
            WinningLot = 0,
            WinningEntityName = '',
        };
    end
    return nil;
end

function inventory:GetContainerCount()
    return 0;
end

function inventory:GetContainerCountMax()
    return 80;
end

function inventory:GetContainerItem()
    return nil;
end

local memoryManager = {};

function memoryManager:GetInventory()
    return inventory;
end

local packetManager = {};

function packetManager:AddOutgoingPacket(packetId, packet)
    outgoingPackets[#outgoingPackets + 1] = {
        packetId = packetId,
        packet = packet,
    };
end

local resourceManager = {};

function resourceManager:GetItemById()
    return {
        Name = { 'Test Item' },
        Flags = 0,
    };
end

AshitaCore = {};

function AshitaCore:GetMemoryManager()
    return memoryManager;
end

function AshitaCore:GetPacketManager()
    return packetManager;
end

function AshitaCore:GetResourceManager()
    return resourceManager;
end

struct = {};

function struct.pack(_, ...)
    local values = { ... };
    return {
        totable = function()
            return values;
        end,
    };
end

local function fail(message)
    error(message, 2);
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        fail(string.format('%s: expected %s, got %s', message, tostring(expected), tostring(actual)));
    end
end

local function resetPackets()
    outgoingPackets = {};
end

local function assertPacket(actual, expected, message)
    assertEqual(actual.packetId, expected[1], message .. ' packet id');
    assertEqual(#actual.packet, #expected, message .. ' packet length');
    for index, value in ipairs(expected) do
        assertEqual(actual.packet[index], value, string.format('%s byte %d', message, index));
    end
end

local data = require('modules.treasurepool.data');
local actions = require('modules.treasurepool.actions');

local function previewBlocksTreasureActions()
    data.Initialize();
    assertEqual(data.ReadFromMemory(), true, 'live treasure item should be available');
    data.SetPreview(true);

    local cases = {
        {
            name = 'LotItem',
            invoke = function()
                local success = actions.LotItem(treasureSlot);
                return success;
            end,
            expectedResult = false,
        },
        {
            name = 'PassItem',
            invoke = function()
                return actions.PassItem(treasureSlot);
            end,
            expectedResult = false,
        },
        {
            name = 'LotAll',
            invoke = actions.LotAll,
            expectedResult = 0,
        },
        {
            name = 'PassAll',
            invoke = actions.PassAll,
            expectedResult = 0,
        },
    };

    local issues = {};
    for _, case in ipairs(cases) do
        resetPackets();
        local result = case.invoke();
        if #outgoingPackets ~= 0 then
            issues[#issues + 1] = string.format('%s emitted %d packet(s)', case.name, #outgoingPackets);
        end
        if result ~= case.expectedResult then
            issues[#issues + 1] = string.format('%s returned %s instead of %s',
                case.name, tostring(result), tostring(case.expectedResult));
        end
    end

    if #issues > 0 then
        fail(table.concat(issues, '\n'));
    end
end

local function previewHistoryIsIsolatedFromLivePackets()
    local closeCases = {
        {
            name = 'SetPreview(false)',
            close = function()
                data.SetPreview(false);
            end,
        },
        {
            name = 'ClearPreview',
            close = data.ClearPreview,
        },
    };

    local issues = {};
    local function checkValue(actual, expected, message)
        if actual ~= expected then
            issues[#issues + 1] = string.format('%s: expected %s, got %s',
                message, tostring(expected), tostring(actual));
        end
    end

    for _, closeCase in ipairs(closeCases) do
        data.Initialize();
        data.HandleLotPacket(treasureSlot, 4001, 'LiveOne', 0, 300, 4001, 'LiveOne', 300, 0);

        data.SetPreview(true);
        checkValue(#data.GetLotters(treasureSlot), 0, closeCase.name .. ' Preview lotters before a live packet');

        data.HandleLotPacket(treasureSlot, 4002, 'LiveTwo', 0, 600, 4002, 'LiveTwo', 600, 0);
        checkValue(#data.GetLotters(treasureSlot), 0, closeCase.name .. ' Preview lotters after a live packet');

        closeCase.close();
        local liveLotters = data.GetLotters(treasureSlot);
        local highest = liveLotters[1] or {};
        local second = liveLotters[2] or {};
        checkValue(#liveLotters, 2, closeCase.name .. ' live lotters restored after Preview');
        checkValue(highest.serverId, 4002, closeCase.name .. ' highest live lotter server id');
        checkValue(highest.name, 'LiveTwo', closeCase.name .. ' highest live lotter name');
        checkValue(highest.lot, 600, closeCase.name .. ' highest live lotter value');
        checkValue(second.serverId, 4001, closeCase.name .. ' second live lotter server id');
        checkValue(second.name, 'LiveOne', closeCase.name .. ' second live lotter name');
        checkValue(second.lot, 300, closeCase.name .. ' second live lotter value');
    end

    if #issues > 0 then
        fail(table.concat(issues, '\n'));
    end
end

local function liveTreasureActionsStillSendPackets()
    data.Initialize();
    assertEqual(data.ReadFromMemory(), true, 'live treasure item should be available');

    local cases = {
        {
            name = 'LotItem',
            invoke = function()
                return actions.LotItem(treasureSlot);
            end,
            expectedResult = true,
            expectedPacket = { 0x41, 0x04, 0x00, 0x00, treasureSlot, 0x00, 0x00, 0x00 },
        },
        {
            name = 'PassItem',
            invoke = function()
                return actions.PassItem(treasureSlot);
            end,
            expectedResult = true,
            expectedPacket = { 0x42, 0x04, 0x00, 0x00, treasureSlot, 0x00, 0x00, 0x00 },
        },
        {
            name = 'LotAll',
            invoke = actions.LotAll,
            expectedResult = 1,
            expectedPacket = { 0x41, 0x04, 0x00, 0x00, treasureSlot, 0x00, 0x00, 0x00 },
        },
        {
            name = 'PassAll',
            invoke = actions.PassAll,
            expectedResult = 1,
            expectedPacket = { 0x42, 0x04, 0x00, 0x00, treasureSlot, 0x00, 0x00, 0x00 },
        },
    };

    for _, case in ipairs(cases) do
        resetPackets();
        local result = case.invoke();
        assertEqual(result, case.expectedResult, case.name .. ' live result');
        assertEqual(#outgoingPackets, 1, case.name .. ' live packet count');
        assertPacket(outgoingPackets[1], case.expectedPacket, case.name .. ' live packet');
    end
end

local function clearingTreasureStateEndsPreview()
    data.Initialize();
    data.SetPreview(true);
    assertEqual(data.IsPreviewActive(), true, 'Preview should start active');
    assertEqual(data.HasItems(), true, 'Preview should provide treasure items');

    data.Clear();

    assertEqual(data.IsPreviewActive(), false, 'Preview after treasure state is cleared');
    assertEqual(data.HasItems(), false, 'treasure items after state is cleared');
end

local function previewClearsLiveTreasureActionControls()
    local activeButtons = {};
    local drawList = setmetatable({}, {
        __index = function()
            return function()
            end;
        end,
    });

    package.preload['handlers.helpers'] = function()
        GetBaseWindowFlags = function()
            return 0;
        end;
        ApplyWindowPosition = function()
        end;
        SaveWindowPosition = function()
        end;
        GetUIDrawList = function()
            return drawList;
        end;
        return true;
    end;

    package.preload['imgui'] = function()
        return {
            Begin = function()
                return true;
            end,
            Dummy = function()
            end,
            End = function()
            end,
            GetColorU32 = function()
                return 0;
            end,
            GetCursorScreenPos = function()
                return 0, 0;
            end,
            GetIO = function()
                return { MouseWheel = 0 };
            end,
            GetMousePos = function()
                return 0, 0;
            end,
            IsWindowHovered = function()
                return false;
            end,
            SetNextWindowSize = function()
            end,
            SetTooltip = function()
            end,
        };
    end;

    package.preload['libs.windowbackground'] = function()
        return { Draw = function() end };
    end;
    package.preload['libs.progressbar'] = function()
        return { ProgressBar = function() end };
    end;
    package.preload['libs.button'] = function()
        return {
            COLORS_NEGATIVE = {},
            COLORS_NEUTRAL = {},
            COLORS_POSITIVE = {},
            DrawArrowPrim = function()
                return false;
            end,
            DrawMinimizePrim = function()
                return false;
            end,
            DrawPrim = function(id)
                activeButtons[id] = true;
                return false;
            end,
            HidePrim = function(id)
                activeButtons[id] = nil;
            end,
        };
    end;
    package.preload['libs.texturemanager'] = function()
        return {
            getItemIcon = function()
                return nil;
            end,
            getTexturePtr = function()
                return nil;
            end,
        };
    end;
    package.preload['libs.imtext'] = function()
        return {
            Draw = function()
            end,
            Measure = function(text, fontSize)
                return #text * fontSize / 2, fontSize;
            end,
            SetConfigFromSettings = function()
            end,
        };
    end;
    package.preload['libs.defaultpositions'] = function()
        return { GetTreasurePoolPosition = function() return 0, 0 end };
    end;

    ImGuiCond_Always = 0;
    ImDrawCornerFlags_All = 0;
    HzLimitedMode = false;
    SaveSettingsToDisk = function()
    end;
    gConfig = {
        globalScale = 1,
        lockPositions = false,
        treasurePoolBackgroundOpacity = 1,
        treasurePoolBackgroundTheme = 'Plain',
        treasurePoolBgScale = 1,
        treasurePoolBorderOpacity = 1,
        treasurePoolBorderScale = 1,
        treasurePoolExpanded = false,
        treasurePoolFontSize = 10,
        treasurePoolLootColors = false,
        treasurePoolMinimized = false,
        treasurePoolScaleX = 1,
        treasurePoolScaleY = 1,
        treasurePoolShowButtonsInCollapsed = true,
        treasurePoolShowLots = true,
        treasurePoolShowTimerBar = true,
        treasurePoolShowTimerText = true,
    };

    data.Initialize();
    assertEqual(data.ReadFromMemory(), true, 'live item for control transition');
    package.loaded['modules.treasurepool.display'] = nil;
    local display = require('modules.treasurepool.display');
    display.DrawWindow({ font_settings = {}, title_font_settings = {} });

    local function countActiveActionButtons()
        local count = 0;
        for id in pairs(activeButtons) do
            if id == 'tpLotAll' or id == 'tpPassAll' or
               id:match('^tpLotItem%d+$') or id:match('^tpPassItem%d+$') then
                count = count + 1;
            end
        end
        return count;
    end

    assertEqual(countActiveActionButtons(), 4, 'live treasure action controls');

    data.SetPreview(true);
    display.DrawWindow({ font_settings = {}, title_font_settings = {} });

    assertEqual(countActiveActionButtons(), 0, 'Treasure Preview action controls');
end

local tests = {
    { name = 'Preview blocks every treasure action', run = previewBlocksTreasureActions },
    { name = 'Preview history stays isolated from live packets', run = previewHistoryIsIsolatedFromLivePackets },
    { name = 'Live treasure actions still send exact packets', run = liveTreasureActionsStillSendPackets },
    { name = 'Clearing treasure state ends Preview', run = clearingTreasureStateEndsPreview },
    { name = 'Preview clears live treasure action controls', run = previewClearsLiveTreasureActionControls },
};

local failures = 0;
for _, test in ipairs(tests) do
    local ok, err = xpcall(test.run, debug.traceback);
    if ok then
        print('PASS ' .. test.name);
    else
        failures = failures + 1;
        io.stderr:write('FAIL ' .. test.name .. '\n');
        io.stderr:write(err .. '\n');
    end
end

if failures > 0 then
    os.exit(1);
end

print(string.format('%d Treasure Preview tests passed', #tests));
