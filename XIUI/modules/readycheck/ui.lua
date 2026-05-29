--[[
* ReadyCheck UI renderer for XIUI.
* Adapted from the standalone ReadyCheck addon by Lydya.
*
* Job icons are sourced from XIUI's existing assets via statusHandler.GetJobIcon,
* respecting the user's selected job icon theme.
]]--

local imgui        = require('imgui')
local bit          = require('bit')
local statusHandler = require('handlers.statushandler')

local ui = {}

-- SetWindowFontScale is missing on some older Ashita builds and is being
-- obsoleted upstream. Resolve once and fall back to a no-op so a nil lookup
-- can't abort a render mid-window (which would leave Begin/PushStyle*
-- unmatched and surface as "missing End()" / "missing popStyleColor()").
local SetWindowFontScale = imgui.SetWindowFontScale or function() end

-- Styles used by the prompt/tracker windows (text, buttons, separators, title bar).
local WINDOW_COLORS = {
    { ImGuiCol_WindowBg,          { 0.051, 0.051, 0.051, 0.95 } },
    { ImGuiCol_TitleBg,           { 0.098, 0.090, 0.075, 1.00 } },
    { ImGuiCol_TitleBgActive,     { 0.137, 0.125, 0.106, 1.00 } },
    { ImGuiCol_TitleBgCollapsed,  { 0.051, 0.051, 0.051, 0.95 } },
    { ImGuiCol_Border,            { 0.300, 0.275, 0.235, 1.00 } },
    { ImGuiCol_Text,              { 0.878, 0.855, 0.812, 1.00 } },
    { ImGuiCol_TextDisabled,      { 0.765, 0.684, 0.474, 1.00 } },
    { ImGuiCol_Button,            { 0.098, 0.090, 0.075, 1.00 } },
    { ImGuiCol_ButtonHovered,     { 0.137, 0.125, 0.106, 1.00 } },
    { ImGuiCol_ButtonActive,      { 0.176, 0.161, 0.137, 1.00 } },
    { ImGuiCol_Separator,         { 0.300, 0.275, 0.235, 1.00 } },
    { ImGuiCol_ResizeGrip,        { 0.573, 0.512, 0.355, 1.00 } },
    { ImGuiCol_ResizeGripHovered, { 0.765, 0.684, 0.474, 1.00 } },
    { ImGuiCol_ResizeGripActive,  { 0.957, 0.855, 0.592, 1.00 } },
}

local WINDOW_VARS = {
    { ImGuiStyleVar_WindowPadding,    { 12, 12 } },
    { ImGuiStyleVar_FramePadding,     { 6,  4  } },
    { ImGuiStyleVar_ItemSpacing,      { 8,  6  } },
    { ImGuiStyleVar_FrameRounding,    4.0        },
    { ImGuiStyleVar_WindowRounding,   6.0        },
    { ImGuiStyleVar_WindowBorderSize, 1.0        },
    { ImGuiStyleVar_WindowTitleAlign, { 0.5, 0.5 } },
}

local WINDOW_COLOR_COUNT = #WINDOW_COLORS
local WINDOW_VAR_COUNT   = #WINDOW_VARS

local WINDOW_FLAGS = bit.bor(
    ImGuiWindowFlags_NoCollapse,
    ImGuiWindowFlags_AlwaysAutoResize,
    ImGuiWindowFlags_NoScrollbar,
    ImGuiWindowFlags_NoSavedSettings
)
local PROMPT_FLAGS = bit.bor(WINDOW_FLAGS, ImGuiWindowFlags_NoResize)

-- Pre-allocated per-frame constants (zero GC per frame)
local COLOR_READY     = { 0.20, 1.00, 0.20, 1.0 }
local COLOR_NOT_READY = { 1.00, 0.25, 0.25, 1.0 }
local COLOR_PENDING   = { 1.00, 1.00, 1.00, 1.0 }
local ICON_SIZE       = { 20, 20 }
local ICON_UV0        = { 0, 0 }
local ICON_UV1        = { 1, 1 }
local ICON_TINT       = { 1, 1, 1, 1 }
local ICON_BORDER     = { 0, 0, 0, 0 }
local PIVOT_CENTER    = { 0.5, 0.5 }
local BTN_CLOSE       = { -1, 24 }
local FONT_SCALE      = 1.2
local BTN_PROMPT      = { 120, 36 }
local BTN_YES_COL        = { 0.45, 0.12, 0.10, 1.0 }
local BTN_YES_COL_HOVER  = { 0.60, 0.18, 0.14, 1.0 }
local BTN_YES_COL_ACTIVE = { 0.30, 0.08, 0.06, 1.0 }
local BTN_NO_COL         = { 0.38, 0.10, 0.08, 1.0 }
local BTN_NO_COL_HOVER   = { 0.55, 0.16, 0.12, 1.0 }
local BTN_NO_COL_ACTIVE  = { 0.25, 0.06, 0.05, 1.0 }
local COLOR_GOLD_BRIGHT  = { 0.957, 0.855, 0.592, 1.0 }
local MIN_PARTY_COL_W    = 125
local WIN_CENTER         = { 0, 0 }

local function push_window_styles()
    for i = 1, WINDOW_COLOR_COUNT do
        local e = WINDOW_COLORS[i]
        imgui.PushStyleColor(e[1], e[2])
    end
    for i = 1, WINDOW_VAR_COUNT do
        local e = WINDOW_VARS[i]
        imgui.PushStyleVar(e[1], e[2])
    end
end

local function member_status_color(status)
    if status == 'ready' then return COLOR_READY end
    if status == 'not_ready' then return COLOR_NOT_READY end
    return COLOR_PENDING
end

local function draw_member_row(member)
    imgui.PushStyleColor(ImGuiCol_Text, member_status_color(member.status))
    local icon_ptr = statusHandler.GetJobIcon(member.job)
    if icon_ptr then
        imgui.Image(icon_ptr, ICON_SIZE, ICON_UV0, ICON_UV1, ICON_TINT, ICON_BORDER)
    else
        imgui.Dummy(ICON_SIZE)
    end
    imgui.SameLine()
    imgui.Text(member.name)
    imgui.PopStyleColor(1)
end

local function render_prompt(state, handlers)
    if not state.prompt_open[1] then return end

    if state.prompt_center_next then
        imgui.SetNextWindowPos(WIN_CENTER, ImGuiCond_Always, PIVOT_CENTER)
        state.prompt_center_next = false
    end
    imgui.SetNextWindowBgAlpha(0.95)

    if imgui.Begin('Ready Check##prompt', state.prompt_open, PROMPT_FLAGS) then
        SetWindowFontScale(FONT_SCALE)
        local sender = state.prompt_sender or 'Someone'
        imgui.Spacing()
        imgui.PushStyleColor(ImGuiCol_Text, COLOR_GOLD_BRIGHT)
        local header = sender .. ' has initiated a ready check.'
        local win_w  = imgui.GetContentRegionAvail()
        local text_w = imgui.CalcTextSize(header)
        imgui.SetCursorPosX((win_w - text_w) * 0.5 + imgui.GetCursorPosX())
        imgui.Text(header)
        imgui.PopStyleColor(1)

        local subtitle = 'Are you ready?'
        local sub_w    = imgui.CalcTextSize(subtitle)
        imgui.SetCursorPosX((win_w - sub_w) * 0.5 + imgui.GetCursorPosX())
        imgui.Text(subtitle)
        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        local remaining = state.prompt_deadline
            and math.max(0, math.ceil(state.prompt_deadline - os.clock())) or 0
        local cd_str = ('Auto-close in %ds'):format(remaining)
        local cd_w   = imgui.CalcTextSize(cd_str)
        imgui.SetCursorPosX((win_w - cd_w) * 0.5 + imgui.GetCursorPosX())
        imgui.TextDisabled(cd_str)
        imgui.Spacing()

        local spacing   = imgui.GetStyle().ItemSpacing
        local total_btn = BTN_PROMPT[1] * 2 + spacing.x
        imgui.SetCursorPosX((win_w - total_btn) * 0.5 + imgui.GetCursorPosX())

        imgui.PushStyleColor(ImGuiCol_Button,        BTN_YES_COL)
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, BTN_YES_COL_HOVER)
        imgui.PushStyleColor(ImGuiCol_ButtonActive,  BTN_YES_COL_ACTIVE)
        if imgui.Button('Ready', BTN_PROMPT) and not state.prompt_answered then
            handlers.answer_yes()
        end
        imgui.PopStyleColor(3)

        imgui.SameLine()

        imgui.PushStyleColor(ImGuiCol_Button,        BTN_NO_COL)
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, BTN_NO_COL_HOVER)
        imgui.PushStyleColor(ImGuiCol_ButtonActive,  BTN_NO_COL_ACTIVE)
        if imgui.Button('Not Ready', BTN_PROMPT) and not state.prompt_answered then
            handlers.answer_no()
        end
        imgui.PopStyleColor(3)
        imgui.Spacing()
    end

    imgui.End()
end

local function render_tracker(state, handlers)
    if not state.checker_open[1] then return end

    if state.tracker_center_next then
        imgui.SetNextWindowPos(WIN_CENTER, ImGuiCond_Always, PIVOT_CENTER)
        state.tracker_center_next = false
    end
    imgui.SetNextWindowBgAlpha(0.90)

    if imgui.Begin('Ready Check##tracker', state.checker_open, WINDOW_FLAGS) then
        SetWindowFontScale(FONT_SCALE)
        imgui.Text('Party / Alliance Status')
        imgui.SameLine()
        local secs_left = state.checker_deadline
            and math.max(0, math.ceil(state.checker_deadline - os.clock())) or 0
        imgui.TextDisabled(('  (%ds)'):format(secs_left))
        imgui.Separator()
        imgui.Spacing()

        local members = state.party_members
        if #members == 0 then
            imgui.TextDisabled('No party members found.')
        else
            local parties = { {}, {}, {} }
            for i = 1, #members do
                local m = members[i]
                table.insert(parties[m.party or 1], m)
            end

            local num_cols = 1
            for p = 3, 1, -1 do
                if #parties[p] > 0 then num_cols = p; break end
            end

            if num_cols > 1 then
                local content_w = imgui.GetContentRegionAvail()
                local col_w = math.max(MIN_PARTY_COL_W, math.floor(content_w / num_cols))
                imgui.Columns(num_cols, 'rc_party_cols', true)
                if imgui.SetColumnWidth then
                    for col = 0, num_cols - 1 do
                        imgui.SetColumnWidth(col, col_w)
                    end
                end

                for col = 1, num_cols do
                    local header = 'Party ' .. col
                    local text_w = imgui.CalcTextSize(header)
                    if imgui.GetColumnWidth and text_w then
                        local cur_x  = imgui.GetCursorPosX()
                        local this_w = imgui.GetColumnWidth()
                        if this_w > text_w then
                            imgui.SetCursorPosX(cur_x + (this_w - text_w) * 0.5)
                        end
                    end
                    imgui.TextDisabled(header)
                    imgui.NextColumn()
                end
                for col = 1, num_cols do
                    imgui.Separator()
                    imgui.NextColumn()
                end

                local max_rows = math.max(#parties[1], #parties[2], #parties[3])
                for row = 1, max_rows do
                    for col = 1, num_cols do
                        local member = parties[col][row]
                        if member then
                            draw_member_row(member)
                        else
                            imgui.Dummy({ 1, ICON_SIZE[2] })
                        end
                        imgui.NextColumn()
                    end
                end

                imgui.Columns(1)
            else
                local grp = parties[1]
                for i = 1, #grp do
                    draw_member_row(grp[i])
                end
            end
        end

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        if imgui.Button('Close', BTN_CLOSE) then
            handlers.close_checker()
        end
    end

    imgui.End()
end

function ui.render(state, handlers)
    if not (state.prompt_open[1] or state.checker_open[1]) then return end

    local display = imgui.GetIO().DisplaySize
    WIN_CENTER[1] = display.x * 0.5
    WIN_CENTER[2] = display.y * 0.5

    push_window_styles()
    render_prompt(state, handlers)
    render_tracker(state, handlers)
    imgui.PopStyleVar(WINDOW_VAR_COUNT)
    imgui.PopStyleColor(WINDOW_COLOR_COUNT)
end

return ui
