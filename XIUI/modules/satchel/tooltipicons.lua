--[[
    Satchel tooltip inline icons (elements, Rare, Ex, etc.).
    PNG assets live under addon.path\assets\satchel\elements\ and tags\.

    Uses TextureManager + ImDrawList:AddImage instead of imgui.Image. Ashita
    4.16 is sensitive to unsafe texture draws during tooltips.
]]--

local imgui = require('imgui')
local TextureManager = require('libs.texturemanager')
local tooltipfonts = require('modules.satchel.tooltipfonts')
local fontcore = require('modules.satchel.satchelfontcore')

local tooltipicons = {}

local preload_state = {
    attempted = false,
    complete = false,
}

local catalog_mode = false

local ELEMENT_ICON_SIZE = 14
local TAG_ICON_SIZE = 14

local function get_icon_sizes()
    local metrics = tooltipfonts.get_metrics()
    return metrics.icon_size or ELEMENT_ICON_SIZE, metrics.icon_size or TAG_ICON_SIZE
end

local function calc_width(text, pixel_size)
    if pixel_size then
        local metrics = tooltipfonts.get_metrics()
        return fontcore.calc_text_width(text, metrics.family, pixel_size)
    end
    return tonumber(imgui.CalcTextSize(text)) or 0
end

tooltipicons.ELEMENT_ICON_SIZE = ELEMENT_ICON_SIZE
tooltipicons.TAG_ICON_SIZE = TAG_ICON_SIZE

tooltipicons.ELEMENTS = {
    { byte = 0x1F, id = 1, name = 'Fire', file = 'fire.png' },
    { byte = 0x20, id = 2, name = 'Ice', file = 'ice.png' },
    { byte = 0x21, id = 3, name = 'Wind', file = 'wind.png' },
    { byte = 0x22, id = 4, name = 'Earth', file = 'earth.png' },
    { byte = 0x23, id = 5, name = 'Lightning', file = 'lightning.png' },
    { byte = 0x24, id = 6, name = 'Water', file = 'water.png' },
    { byte = 0x25, id = 7, name = 'Light', file = 'light.png' },
    { byte = 0x26, id = 8, name = 'Dark', file = 'dark.png' },
}

tooltipicons.ELEMENT_BY_BYTE = {}
tooltipicons.ELEMENT_COLORS = {}
for _, entry in ipairs(tooltipicons.ELEMENTS) do
    tooltipicons.ELEMENT_BY_BYTE[entry.byte] = entry
end

tooltipicons.STATUS_TAGS = {
    rare = { label = 'Rare', file = 'Rare.png', color = { 0.95, 0.88, 0.35, 1.0 } },
    ex = { label = 'Ex', file = 'Ex.png', color = { 0.28, 0.78, 0.38, 1.0 } },
    alt = { label = 'Alt', file = 'Alt.png', color = { 0.35, 0.55, 0.95, 1.0 } },
    tmp = { label = 'Tmp', file = 'Tmp.png', color = { 0.55, 0.65, 0.78, 1.0 } },
    aug = { label = 'Aug', file = 'Aug.png', color = { 0.85, 0.28, 0.28, 1.0 } },
}

function tooltipicons.set_catalog_mode(enabled)
    catalog_mode = enabled == true
end

function tooltipicons.icons_as_words()
    if catalog_mode then
        return true
    end

    return gConfig and gConfig.satchelTooltipIconsAsWords == true
end

local function strip_png_extension(file_name)
    if type(file_name) ~= 'string' then
        return ''
    end
    return file_name:gsub('%.png$', '')
end

local function try_load_file_texture(paths)
    for _, path in ipairs(paths or {}) do
        if type(path) == 'string' and path ~= '' then
            local tex = TextureManager.getFileTexture(path)
            if tex and TextureManager.getTexturePtr(tex) then
                return tex
            end
        end
    end
    return nil
end

function tooltipicons.load_element_icon(_satchel, _addon_path, element_entry)
    local root = 'satchel/elements/' .. strip_png_extension(element_entry.file)
    return try_load_file_texture({
        root,
        ('satchel/upscaled/%d'):format(element_entry.id),
    })
end

function tooltipicons.load_status_icon(_satchel, _addon_path, tag_key)
    local tag = tooltipicons.STATUS_TAGS[tag_key]
    if not tag then
        return nil
    end

    return try_load_file_texture({
        'satchel/tags/' .. strip_png_extension(tag.file),
    })
end

function tooltipicons.preload_assets(_satchel, _addon_path)
    if preload_state.complete then
        return true
    end

    if preload_state.attempted then
        return false
    end

    preload_state.attempted = true

    for _, entry in ipairs(tooltipicons.ELEMENTS) do
        tooltipicons.load_element_icon(nil, nil, entry)
    end

    for tag_key in pairs(tooltipicons.STATUS_TAGS) do
        tooltipicons.load_status_icon(nil, nil, tag_key)
    end

    preload_state.complete = true
    return true
end

function tooltipicons.get_asset_root(addon_path)
    return (addon_path or '') .. '\\assets\\satchel\\'
end

function tooltipicons.get_status_color(tag_key)
    local tag = tooltipicons.STATUS_TAGS[tag_key]
    return tag and tag.color or { 1.0, 1.0, 1.0, 1.0 }
end

function tooltipicons.get_status_label(tag_key)
    local tag = tooltipicons.STATUS_TAGS[tag_key]
    return tag and tag.label or tag_key
end

function tooltipicons.get_element_color(name)
    return tooltipicons.ELEMENT_COLORS[name] or { 0.88, 0.88, 0.88, 1.0 }
end

function tooltipicons.set_element_colors(color_table)
    tooltipicons.ELEMENT_COLORS = color_table or {}
end

local function render_tooltip_icon_image(texture, size)
    local ptr = texture and TextureManager.getTexturePtr(texture) or nil
    if not ptr or ptr == 0 then
        return false
    end

    local draw_list = imgui.GetWindowDrawList()
    if not draw_list then
        return false
    end

    local x, y = imgui.GetCursorScreenPos()
    draw_list:AddImage(
        ptr,
        { x, y },
        { x + size, y + size },
        { 0, 0 },
        { 1, 1 }
    )
    imgui.Dummy({ size, size })
    return true
end

function tooltipicons.measure_status_tag_width(satchel, addon_path, tag_key, as_words)
    if as_words then
        return calc_width(tooltipicons.get_status_label(tag_key))
    end

    local _, tag_size = get_icon_sizes()
    local tex = tooltipicons.load_status_icon(satchel, addon_path, tag_key)
    if tex then
        return tag_size
    end

    return calc_width(tooltipicons.get_status_label(tag_key))
end

function tooltipicons.measure_status_tags_width(satchel, addon_path, tags, as_words)
    local total = 0
    for _, tag_key in ipairs(tags or {}) do
        total = total + tooltipicons.measure_status_tag_width(satchel, addon_path, tag_key, as_words)
    end
    return total
end

function tooltipicons.render_status_tag(satchel, addon_path, tag_key, as_words)
    if as_words then
        imgui.TextColored(tooltipicons.get_status_color(tag_key), tooltipicons.get_status_label(tag_key))
        return
    end

    local _, tag_size = get_icon_sizes()
    local tex = tooltipicons.load_status_icon(satchel, addon_path, tag_key)
    if tex and render_tooltip_icon_image(tex, tag_size) then
        return
    end

    imgui.TextColored(tooltipicons.get_status_color(tag_key), tooltipicons.get_status_label(tag_key))
end

function tooltipicons.render_element_token(satchel, addon_path, element_entry, as_words)
    if as_words then
        imgui.TextColored(tooltipicons.get_element_color(element_entry.name), element_entry.name)
        return
    end

    local element_size = get_icon_sizes()
    local tex = tooltipicons.load_element_icon(satchel, addon_path, element_entry)
    if tex and render_tooltip_icon_image(tex, element_size) then
        return
    end

    imgui.TextColored(tooltipicons.get_element_color(element_entry.name), element_entry.name)
end

local function get_element_entry_by_index(element_index)
    for _, entry in ipairs(tooltipicons.ELEMENTS) do
        if entry.id == element_index then
            return entry
        end
    end
    return nil
end

function tooltipicons.measure_elemental_footer_entry_width(entry, as_words, pixel_size)
    if type(entry) ~= 'table' then
        return 0
    end

    local slot_text = ('[%d]'):format(tonumber(entry.slot) or 0)
    local triangle = entry.positive == false and '△' or '▲'
    local value_text = tostring(tonumber(entry.value) or 0)
    local width = calc_width(slot_text, pixel_size)
    width = width + calc_width(' ', pixel_size)

    local element_entry = get_element_entry_by_index(entry.element_index)
    if as_words then
        width = width + calc_width(element_entry and element_entry.name or '?', pixel_size)
    elseif element_entry then
        local element_size = get_icon_sizes()
        width = width + element_size
    else
        width = width + calc_width('?', pixel_size)
    end

    width = width + calc_width(triangle .. value_text, pixel_size)
    return width
end

function tooltipicons.measure_elemental_footer_width(satchel, addon_path, entries, as_words, pixel_size)
    pixel_size = pixel_size or tooltipfonts.get_metrics().pixel_size
    local total = calc_width('<', pixel_size) + calc_width('>', pixel_size)
    for index, entry in ipairs(entries or {}) do
        if index > 1 then
            total = total + calc_width(' ', pixel_size)
        end
        total = total + tooltipicons.measure_elemental_footer_entry_width(entry, as_words, pixel_size)
    end
    return total
end

function tooltipicons.render_elemental_footer_entry(satchel, addon_path, entry, as_words, color)
    if type(entry) ~= 'table' then
        return
    end

    color = color or { 0.92, 0.92, 0.92, 1.0 }
    local gap = as_words and 0 or 4

    imgui.TextColored(color, ('[%d]'):format(tonumber(entry.slot) or 0))
    imgui.SameLine(0, gap)

    local element_entry = get_element_entry_by_index(entry.element_index)
    if element_entry then
        tooltipicons.render_element_token(satchel, addon_path, element_entry, as_words)
        imgui.SameLine(0, as_words and 0 or 2)
    end

    local triangle = entry.positive == false and '△' or '▲'
    imgui.TextColored(color, triangle .. tostring(tonumber(entry.value) or 0))
end

function tooltipicons.render_elemental_footer_right(satchel, addon_path, entries, color, as_words)
    entries = entries or {}
    if #entries == 0 then
        return
    end

    color = color or { 0.92, 0.92, 0.92, 1.0 }
    as_words = as_words == true

    local metrics = tooltipfonts.get_metrics()
    local avail_w = math.max(0, (tonumber(imgui.GetWindowWidth()) or 0) - 10)
    local pixel_size = metrics.pixel_size
    local width = tooltipicons.measure_elemental_footer_width(satchel, addon_path, entries, as_words, pixel_size)

    if as_words and width > avail_w and metrics.footer_min_px < pixel_size then
        for shrink_px = pixel_size - 1, metrics.footer_min_px, -1 do
            local shrunk_w = tooltipicons.measure_elemental_footer_width(satchel, addon_path, entries, as_words, shrink_px)
            if shrunk_w <= avail_w then
                pixel_size = shrink_px
                width = shrunk_w
                break
            end
        end
    end

    if as_words and pixel_size ~= metrics.pixel_size then
        fontcore.push_font(metrics.family, pixel_size)
    end

    local right_x = math.max(0, avail_w - width)
    imgui.SetCursorPosX(right_x)
    imgui.TextColored(color, '<')
    imgui.SameLine(0, 0)

    for index, entry in ipairs(entries) do
        if index > 1 then
            imgui.SameLine(0, 4)
        end
        tooltipicons.render_elemental_footer_entry(satchel, addon_path, entry, as_words, color)
    end

    imgui.SameLine(0, 0)
    imgui.TextColored(color, '>')

    if as_words and pixel_size ~= metrics.pixel_size then
        fontcore.pop_font()
    end
end

return tooltipicons
