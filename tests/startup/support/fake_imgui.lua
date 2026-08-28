local M = {};

local DEFAULT_FONT_SIZE = 13;

local constant_values = {
    ImGuiChildFlags_None = 0,
    ImGuiCol_Border = 5,
    ImGuiCol_Button = 21,
    ImGuiCol_ButtonActive = 23,
    ImGuiCol_ButtonHovered = 22,
    ImGuiCol_Header = 24,
    ImGuiCol_HeaderHovered = 25,
    ImGuiCol_HeaderActive = 26,
    ImGuiCol_ResizeGrip = 30,
    ImGuiCol_ResizeGripActive = 32,
    ImGuiCol_ResizeGripHovered = 31,
    ImGuiCol_ScrollbarGrab = 15,
    ImGuiCol_ScrollbarGrabActive = 17,
    ImGuiCol_Separator = 27,
    ImGuiCol_Text = 0,
    ImGuiCol_TextDisabled = 1,
    ImGuiCol_TitleBg = 10,
    ImGuiCol_TitleBgActive = 11,
    ImGuiCol_WindowBg = 2,
    ImGuiStyleVar_Alpha = 0,
    ImGuiStyleVar_FramePadding = 11,
    ImGuiStyleVar_FrameRounding = 12,
    ImGuiStyleVar_ItemSpacing = 14,
    ImGuiStyleVar_WindowBorderSize = 4,
    ImGuiStyleVar_WindowPadding = 2,
    ImGuiStyleVar_WindowRounding = 3,
    ImGuiStyleVar_WindowTitleAlign = 6,
    ImGuiWindowFlags_AlwaysAutoResize = 64,
    ImGuiWindowFlags_NoCollapse = 32,
    ImGuiWindowFlags_NoResize = 2,
    ImGuiWindowFlags_NoSavedSettings = 256,
    ImGuiWindowFlags_NoScrollbar = 8,
    ImDrawCornerFlags_None = 0,
    ImDrawCornerFlags_TopLeft = 1,
    ImDrawCornerFlags_TopRight = 2,
    ImDrawCornerFlags_BotLeft = 4,
    ImDrawCornerFlags_BotRight = 8,
    ImDrawCornerFlags_Top = 3,
    ImDrawCornerFlags_Bot = 12,
    ImDrawCornerFlags_Left = 5,
    ImDrawCornerFlags_Right = 10,
    ImDrawCornerFlags_All = 15,
};

function M.install()
    local previous = {};
    for name, value in pairs(constant_values) do
        previous[name] = rawget(_G, name);
        _G[name] = value;
    end
    previous.ImGuiChildFlags_Borders = rawget(_G, 'ImGuiChildFlags_Borders');
    _G.ImGuiChildFlags_Borders = nil;

    local imgui = {
        AddFontFromFileTTF = function()
            return nil;
        end,
        BeginChild = function()
            return true;
        end,
        BeginDisabled = function()
        end,
        EndDisabled = function()
        end,
        GetColorU32 = function()
            return 0;
        end,
        GetFont = function()
            return { FontSize = DEFAULT_FONT_SIZE };
        end,
        GetIO = function()
            return {
                DisplaySize = { x = 1920, y = 1080 },
                FontGlobalScale = 1,
            };
        end,
        GetStyle = function()
            return { Alpha = 1 };
        end,
        GetTextLineHeight = function()
            return DEFAULT_FONT_SIZE;
        end,
        PopStyleVar = function()
        end,
        PushStyleVar = function()
        end,
    };

    return imgui, function()
        for name in pairs(constant_values) do
            _G[name] = previous[name];
        end
        _G.ImGuiChildFlags_Borders = previous.ImGuiChildFlags_Borders;
    end;
end

return M;
