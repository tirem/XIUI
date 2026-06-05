--[[
* XIUI Config Menu - Vana'Dial Settings
]]--

require('common');
local imgui      = require('imgui');
local components = require('config.components');

local M = {};

local SIDE_LABELS  = {'Right', 'Left', 'Above', 'Below'};
local SIDE_VALUES  = {'right', 'left', 'above', 'below'};
local ALIGN_LABELS = {'Left', 'Right'};
local ALIGN_VALUES = {'left', 'right'};
local TT_DIR_LABELS = {'Above', 'Below'};
local TT_DIR_VALUES = {'above', 'below'};

function M.DrawSettings()
    -- Reset per-frame preview flags for weather icon size sliders.
    _G.XIUI_weatherElementalPreview = false;
    _G.XIUI_weatherBasePreview      = false;

    local colorCfg = gConfig.colorCustomization and gConfig.colorCustomization.vanaDial;

    components.DrawCheckbox('Enabled', 'showVanaDial', CheckVisibility);
    components.DrawCheckbox('Hide When Menu Open', 'vanaDialHideOnMenuFocus');
    imgui.ShowHelp('Hide this module when a game menu is open (equipment, map, etc.).');
    components.DrawCheckbox('Display Settings Button', 'vanaDialShowSettingsBtn');
    imgui.ShowHelp("Show a gear icon on the Vana'Dial module that opens these settings directly.");

    -- ── Scaling & Layout ──────────────────────────────────────────────────────
    if components.CollapsingSection('Scaling & Layout##vt', true) then
        components.DrawSlider('Scale##vt', 'vanaDialScale', 0.5, 2.0, '%.2f', nil, 1.0);
        imgui.ShowHelp("Global scale for the entire Vana'Dial window.  Double right-click to reset.");

        components.DrawSlider('Font Size##vt', 'vanaDialFontSize', 8, 24, '%d', nil, 12);
        imgui.ShowHelp('Font size for clock and moon phase text (scaled by Scale above).  Double right-click to reset.');

        components.DrawSlider('Icon Size##vt', 'vanaDialIconSize', 16, 64, '%d', nil, 28);
        imgui.ShowHelp('Size of the element day icons in pixels (scaled by Scale above).  Double right-click to reset.');
    end

    -- ── Display Options ───────────────────────────────────────────────────────
    if components.CollapsingSection('Display Options##vt', true) then
        components.DrawCheckbox("VT Time matches Element Color", 'vanaDialVTElementColor');
        imgui.ShowHelp("When enabled, the Vana'diel Time text is tinted with the current day's element color.\nWhen disabled, it uses XIUI Gold (Dark).");

        components.DrawCheckbox('Show Local Time (LT)', 'vanaDialShowLocalTime');
        imgui.SameLine(0, 16);
        components.DrawCheckbox('Show Moon Phase %', 'vanaDialShowMoonPercent');
        imgui.ShowHelp('Show moon phase percentage and waxing/waning arrow under each day icon.');

        components.DrawCheckbox('Show Past / Future Days', 'vanaDialShowPastFuture');
        imgui.ShowHelp('Show yesterday and tomorrow columns at reduced opacity on either side of today.');
        if gConfig.vanaDialShowPastFuture ~= false then
            imgui.Indent(16);
            components.DrawSlider('Past / Future Opacity', 'vanaDialPastFutureOpacity', 0.0, 1.0, '%.2f', nil, 0.35);
            imgui.ShowHelp('Opacity of past and future day columns (0 = invisible, 1 = fully opaque).  Double right-click to reset.');
            imgui.Unindent(16);
        end

        components.DrawCheckbox('Disable Elemental Icons On Days', 'vanaDialPlainDayIcons');
        imgui.ShowHelp('Replace the elemental icon on each day column with a solid fill of the element\'s color.');

        components.DrawCheckbox('Show Weakness Badge', 'vanaDialShowWeaknessBadge');
        imgui.ShowHelp('Show the elemental weakness icon as a small badge in the corner of each day column icon.');
    end

    -- ── Time of Day Tab ───────────────────────────────────────────────────────
    if components.CollapsingSection('Time of Day Tab##vt', true) then
        components.DrawCheckbox('Enable Time of Day Tab', 'vanaDialTodPopup');
        imgui.ShowHelp('Show the time-of-day icon (Day / Night / Dead of Night) in its own floating tab.');
        if gConfig.vanaDialTodPopup then
            imgui.Indent(16);
            imgui.Text('Side');
            imgui.SameLine(0, 8);
            components.Combo('##vanaDialTodSide', gConfig, 'vanaDialTodSide',
                SIDE_LABELS, SIDE_VALUES, 'left', nil, 90);
            local todSide = gConfig.vanaDialTodSide or 'left';
            if todSide == 'above' or todSide == 'below' then
                imgui.SameLine(0, 4);
                components.Combo('##vanaDialTodAlign', gConfig, 'vanaDialTodAlign',
                    ALIGN_LABELS, ALIGN_VALUES, 'left', nil, 72);
                imgui.ShowHelp('Horizontal alignment of the TOD tab when placed above or below.');
            end
            components.DrawCheckbox('Individual Scaling##tod', 'vanaDialTodCustomScale');
            imgui.ShowHelp('Use a separate icon size for the TOD tab instead of matching the main Icon Size.');
            if gConfig.vanaDialTodCustomScale then
                imgui.Indent(16);
                components.DrawSlider('Icon Size##todIcon', 'vanaDialTodIconSize', 16, 64, '%d', nil, 28);
                imgui.ShowHelp('Size of the TOD icon in pixels.  Double right-click to reset to 28.');
                imgui.Unindent(16);
            end
            components.DrawCheckbox('Show Timer', 'vanaDialTodShowTimer');
            imgui.ShowHelp('Display a countdown below the icon showing time until the next Day / Night / Dead of Night transition.');
            if gConfig.vanaDialTodShowTimer then
                imgui.Indent(16);
                if colorCfg and colorCfg.todTimerColor == nil then colorCfg.todTimerColor = 0xFFFFFFFF; end
                components.DrawTextColorPicker('Timer Color##tod', colorCfg, 'todTimerColor',
                    'Color of the countdown text.');
                imgui.Unindent(16);
            end
            imgui.Unindent(16);
        end
    end

    -- ── Weather Tab ───────────────────────────────────────────────────────────
    if components.CollapsingSection('Weather Tab##vt', true) then
        local hideNonElem = gConfig.vanaDialWeatherHideNonElemental == true;
        components.DrawCheckbox('Enable Weather Tab', 'vanaDialShowWeather');
        imgui.ShowHelp('Show a floating tab with the current zone weather icon.');
        if hideNonElem and gConfig.vanaDialShowWeather ~= false then
            imgui.SameLine(0, 8);
            if imgui.Button('Test Placement##wx') then
                _G.XIUI_weatherTestExpiry = os.clock() + 30;
            end
            imgui.ShowHelp('Temporarily shows a blinking weather icon for 30s so you can\nposition the tab without waiting for elemental weather.');
        end
        if gConfig.vanaDialShowWeather ~= false then
            imgui.Indent(16);
            imgui.Text('Side');
            imgui.SameLine(0, 8);
            components.Combo('##vanaDialWeatherSide', gConfig, 'vanaDialWeatherSide',
                SIDE_LABELS, SIDE_VALUES, 'right', nil, 90);
            local weatherSide = gConfig.vanaDialWeatherSide or 'right';
            if weatherSide == 'above' or weatherSide == 'below' then
                imgui.SameLine(0, 4);
                components.Combo('##vanaDialWeatherAlign', gConfig, 'vanaDialWeatherAlign',
                    ALIGN_LABELS, ALIGN_VALUES, 'left', nil, 72);
                imgui.ShowHelp('Horizontal alignment when placed above or below.\nIf TOD Tab is on the same side, they are placed side by side.');
            end
            components.DrawCheckbox('Hide Non-Elemental Weather##weather', 'vanaDialWeatherHideNonElemental');
            imgui.ShowHelp('When enabled, the Weather tab is hidden during Clear, Sunny, Cloudy, and Fog weather.');
            -- Adjust Size and Non-Elemental slider are redundant when all weather shown is elemental.
            if not hideNonElem then
                components.DrawCheckbox('Adjust Size for Elemental Weather##weather', 'vanaDialWeatherAdjustElemental');
                imgui.ShowHelp('Elemental weather icons (Fire, Ice, Thunder, etc.) display larger than basic weather.\n\nIndividual Scaling off: auto 50% larger (capped at 64px).\nIndividual Scaling on: use the separate Elemental Icon Size slider.');
            end
            components.DrawCheckbox('Individual Scaling##weather', 'vanaDialWeatherCustomScale');
            imgui.ShowHelp('Use a separate icon size for the Weather tab instead of matching the main Icon Size.');
            if gConfig.vanaDialWeatherCustomScale then
                imgui.Indent(16);
                if not hideNonElem then
                    local baseLbl = gConfig.vanaDialWeatherAdjustElemental
                        and 'Non-Elemental Icon Size##weatherIcon'
                        or  'Icon Size##weatherIcon';
                    components.DrawSlider(baseLbl, 'vanaDialWeatherIconSize', 16, 64, '%d', nil, 28);
                    if imgui.IsItemActive() then
                        _G.XIUI_weatherBasePreview = true;
                    end
                    imgui.ShowHelp('Size of non-elemental weather icons in pixels.  Double right-click to reset to 28.\nPreviews live while dragging.');
                end
                if not hideNonElem and gConfig.vanaDialWeatherAdjustElemental then
                    components.DrawSlider('Elemental Icon Size##weatherElem', 'vanaDialWeatherElementalIconSize', 16, 64, '%d', nil, 42);
                    if imgui.IsItemActive() then
                        _G.XIUI_weatherElementalPreview = true;
                    end
                    imgui.ShowHelp('Size for elemental weather icons.  Double right-click to reset to 42.\nPreviews live while dragging.');
                elseif hideNonElem then
                    -- Only elemental weather ever shows; one size slider is enough.
                    components.DrawSlider('Icon Size##weatherElemOnly', 'vanaDialWeatherElementalIconSize', 16, 64, '%d', nil, 42);
                    if imgui.IsItemActive() then
                        _G.XIUI_weatherElementalPreview = true;
                    end
                    imgui.ShowHelp('Size of the weather icon in pixels.  Double right-click to reset to 42.\nPreviews live while dragging.');
                end
                imgui.Unindent(16);
            end
            imgui.Unindent(16);
        end
    end

    -- ── Tooltips ──────────────────────────────────────────────────────────────
    if components.CollapsingSection('Tooltips##vt', true) then
        components.DrawCheckbox('Enable Tooltips', 'vanaDialEnableTooltips');
        imgui.ShowHelp("Master toggle for all hover tooltips in the Vana'Dial module.");
        if gConfig.vanaDialEnableTooltips ~= false then
            imgui.Indent(16);
            components.DrawCheckbox('VT##tipvt',      'vanaDialTipVT');
            imgui.SameLine(0, 8);
            components.DrawCheckbox('LT##tiplt',      'vanaDialTipLT');
            imgui.SameLine(0, 8);
            components.DrawCheckbox('TOD##tiptod',    'vanaDialTipTod');
            imgui.SameLine(0, 8);
            components.DrawCheckbox('Weather##tipwx', 'vanaDialTipWeather');
            imgui.Spacing();
            components.DrawCheckbox('Day Columns##tipday', 'vanaDialShowTooltip');
            imgui.ShowHelp('Show weekday name and moon phase when hovering a day icon.');
            components.DrawCheckbox('Fenrir Details##vt', 'vanaDialTooltipFenrir');
            imgui.ShowHelp('Show Lunar Cry, Ecliptic Howl, and Ecliptic Growl values when hovering a day column.');
            imgui.SameLine(0, 8);
            components.DrawCheckbox("Selene's Bow##vt", 'vanaDialTooltipSeleneBow');
            imgui.ShowHelp("Show Selene's Bow Ranged Accuracy / Ranged Attack values when hovering a day column.");
            if gConfig.vanaDialShowTooltip ~= false
                or gConfig.vanaDialTooltipFenrir
                or gConfig.vanaDialTooltipSeleneBow then
                imgui.Indent(16);
                components.Combo('Day Column Direction##vt', gConfig, 'vanaDialTooltipDirection',
                    TT_DIR_LABELS, TT_DIR_VALUES, 'above');
                imgui.ShowHelp("Whether the day column tooltip appears above or below the Vana'Dial window.");
                imgui.Unindent(16);
            end
            imgui.Unindent(16);
        end
    end

    -- ── Timers ────────────────────────────────────────────────────────────────
    if components.CollapsingSection('Timers##vt', true) then
        components.DrawCheckbox('Enable Timers', 'vanaDialShowTimers');
        imgui.ShowHelp('Show a clock icon in the VT row that opens a transport and RSE timer panel.');
        if gConfig.vanaDialShowTimers ~= false then
            imgui.Indent(16);
            components.Combo('Timers Side##vt', gConfig, 'vanaDialTimerSide',
                TT_DIR_LABELS, TT_DIR_VALUES, 'above');
            imgui.ShowHelp("Whether the timer panel appears above or below the Vana'Dial window.");
            components.DrawSlider('Timers Font Size##vt', 'vanaDialTimersFontSize', 8, 24, '%d', nil, 12);
            imgui.ShowHelp('Font size of text inside the timers panel.  Double right-click to reset.');
            imgui.Spacing();
            components.DrawCheckbox('Auto-Close on Outside Click', 'vanaDialTimersAutoCloseClick');
            imgui.ShowHelp('Automatically close the Timers panel when you click anywhere outside of it.');
            components.DrawCheckbox('Auto-Close on Inactivity', 'vanaDialTimersAutoCloseIdle');
            imgui.ShowHelp('Automatically close the Timers panel after a period of no interaction.');
            if gConfig.vanaDialTimersAutoCloseIdle then
                imgui.Indent(16);
                components.DrawSlider('Idle Seconds##vt_timers', 'vanaDialTimersAutoCloseIdleSec', 1, 60, '%d', nil, 5);
                imgui.ShowHelp('Seconds of inactivity before the Timers panel closes.  Double right-click to reset.');
                imgui.Unindent(16);
            end
            imgui.Unindent(16);
        end
    end

    -- ── Background ────────────────────────────────────────────────────────────
    if components.CollapsingSection('Background##vt', false) then
        imgui.Spacing();

        components.DrawSlider('Background Scale##vt', 'vanaDialBgScale', 0.1, 3.0, '%.2f', nil, 1.0);
        imgui.ShowHelp('Scale of the background texture (Window themes only).  Double right-click to reset.');

        components.DrawSlider('Background Opacity##vt', 'vanaDialBackgroundOpacity', 0.0, 1.0, '%.2f', nil, 0.85);
        imgui.ShowHelp('Center opacity of the gradient (Plain) or texture opacity (Window themes).  Double right-click to reset.');

        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();

        components.DrawSlider('Border Scale##vt', 'vanaDialBorderScale', 0.1, 3.0, '%.2f', nil, 1.0);
        imgui.ShowHelp('Scale of window border pieces (Window themes only).  Double right-click to reset.');

        components.DrawSlider('Border Opacity##vt', 'vanaDialBorderOpacity', 0.0, 1.0, '%.2f', nil, 1.0);
        imgui.ShowHelp('Opacity of window borders.  Double right-click to reset.');
    end
end

function M.DrawColorSettings()
    local colorCfg = gConfig.colorCustomization and gConfig.colorCustomization.vanaDial;
    if not colorCfg then
        imgui.TextDisabled('Color config not available.');
        return;
    end

    if components.CollapsingSection('Background Colors##vt', true) then
        components.DrawTextColorPicker('Background Tint##vt', colorCfg, 'bgColor',
            'Tint color for the window background. Use black at low opacity for a dark transparent look.');
        components.DrawTextColorPicker('Border Color##vt', colorCfg, 'borderColor',
            'Color of window borders (Window themes only).');
    end

    if components.CollapsingSection('Text Colors##vt', true) then
        components.DrawTextColorPicker('General Text / LT Clock##vt', colorCfg, 'textColor',
            'Color for local time clock and other non-element text.');
    end

    if components.CollapsingSection('Element Colors##vt', false) then
        imgui.TextDisabled('These color the VT clock text and day column pill backgrounds.');
        imgui.TextDisabled('Light group (Fire/Wind/Lightning/Light): black outline + white pill.');
        imgui.TextDisabled('Dark group (Ice/Water/Earth/Dark): white outline + dark pill.');
        imgui.Spacing();
        components.DrawTextColorPicker('Fire (Firesday)##vt',           colorCfg, 'elementFire');
        components.DrawTextColorPicker('Earth (Earthsday)##vt',         colorCfg, 'elementEarth');
        components.DrawTextColorPicker('Water (Watersday)##vt',         colorCfg, 'elementWater');
        components.DrawTextColorPicker('Wind (Windsday)##vt',           colorCfg, 'elementWind');
        components.DrawTextColorPicker('Ice (Iceday)##vt',              colorCfg, 'elementIce');
        components.DrawTextColorPicker('Lightning (Lightningday)##vt',  colorCfg, 'elementLightning');
        components.DrawTextColorPicker('Light (Lightsday)##vt',         colorCfg, 'elementLight');
        components.DrawTextColorPicker('Dark (Darksday)##vt',           colorCfg, 'elementDark');
    end

    if components.CollapsingSection('Moon Glow##vt', false) then
        imgui.TextDisabled('Tint shown behind the moon% text on Full / New Moon.');
        imgui.Spacing();
        components.DrawTextColorPicker('Full Moon Glow##vt',  colorCfg, 'moonFullColor',
            'Golden glow shown behind moon percent on a Full Moon.');
        components.DrawTextColorPicker('New Moon Glow##vt',   colorCfg, 'moonNewColor',
            'Dark red glow shown behind moon percent on a New Moon.');
    end
end

return M;
