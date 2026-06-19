local contextmenu = {}

function contextmenu.create(ctx)
    local satchel = ctx.satchel
    local imgui = ctx.imgui
    local items = ctx.items
    local packets = ctx.packets

    local M = {}

    local function open_pending_popup(dialog, popup_name)
        if dialog.pending_open then
            dialog.pending_open = false
            imgui.OpenPopup(popup_name)
        end
    end

    local function clear_slot_dialog(dialog)
        dialog.slot = nil
    end

    local function clear_bazaar_dialog()
        clear_slot_dialog(satchel.bazaar_dialog)
        satchel.bazaar_dialog.is_modify = false
    end

    local function menu_item_disabled(label)
        imgui.PushStyleColor(ImGuiCol_Text, { 0.45, 0.45, 0.45, 1.0 })
        if imgui.BeginDisabled then imgui.BeginDisabled() end
        imgui.MenuItem(label)
        if imgui.EndDisabled then imgui.EndDisabled() end
        imgui.PopStyleColor(1)
    end

    function M.render()
        open_pending_popup(satchel.context_menu, '##satchel_ctx')
        open_pending_popup(satchel.split_dialog, '##satchel_split')
        open_pending_popup(satchel.bazaar_dialog, '##satchel_bazaar')
        open_pending_popup(satchel.drop_dialog, '##satchel_drop')

        local slot = satchel.context_menu.slot
        if imgui.BeginPopup('##satchel_ctx') then
            if slot and slot.id and slot.id > 0 then
                imgui.TextColored({ 1.0, 0.9, 0.55, 1.0 }, items.get_item_name(slot.id))
                imgui.Separator()

                local actions = items.get_context_menu_actions(slot)
                if actions then
                    for _, action in ipairs(actions) do
                        if action.separator then
                            imgui.Separator()
                        elseif action.enabled then
                            if imgui.MenuItem(action.label) then
                                if action.command then
                                    local cm = AshitaCore:GetChatManager()
                                    if cm then cm:QueueCommand(1, action.command) end
                                elseif action.kind == 'split' then
                                    local max_qty = math.max(1, (slot.count or 2) - 1)
                                    satchel.split_dialog.slot = slot
                                    satchel.split_dialog.quantity = { math.max(1, math.floor(max_qty / 2)) }
                                    satchel.split_dialog.pending_open = true
                                elseif action.kind == 'drop' then
                                    satchel.drop_dialog.slot = slot
                                    satchel.drop_dialog.pending_open = true
                                elseif action.kind == 'bazaar_list' then
                                    packets.send_bazaar_close()
                                    satchel.bazaar_dialog.slot = slot
                                    satchel.bazaar_dialog.price = { action.bazaar_price or 0 }
                                    satchel.bazaar_dialog.is_modify = (action.bazaar_price or 0) > 0
                                    satchel.bazaar_dialog.pending_open = true
                                end
                                imgui.CloseCurrentPopup()
                            end
                        else
                            menu_item_disabled(action.label)
                            if action.tooltip and imgui.IsItemHovered() then
                                imgui.SetTooltip(action.tooltip)
                            end
                        end
                    end
                end
            end
            imgui.EndPopup()
        end

        if imgui.BeginPopupModal('##satchel_bazaar', nil, ImGuiWindowFlags_AlwaysAutoResize or 0) then
            local bd = satchel.bazaar_dialog
            if bd.slot and bd.slot.id and bd.slot.id > 0 then
                local name = items.get_item_name(bd.slot.id) or '?'
                local header = bd.is_modify
                    and ('Modify/Unlist Bazaar: "%s"'):format(name)
                    or  ('List in Bazaar: "%s"'):format(name)
                imgui.Text(header)
                imgui.Separator()
                imgui.Text('Price (gil):')
                imgui.InputInt('##bazaar_price', bd.price)
                if bd.price[1] < 0 then bd.price[1] = 0 end
                if bd.is_modify then
                    imgui.TextColored({ 0.6, 0.6, 0.6, 1.0 }, 'Set price to 0 to unlist.')
                end
                imgui.Separator()
                if imgui.Button('OK', { 80, 0 }) then
                    packets.send_bazaar_set_and_open(bd.slot.property_index, bd.price[1])
                    imgui.CloseCurrentPopup()
                    clear_bazaar_dialog()
                end
                imgui.SameLine(0, 8)
                if imgui.Button('Cancel', { 80, 0 }) then
                    packets.send_bazaar_open()
                    imgui.CloseCurrentPopup()
                    clear_bazaar_dialog()
                end
            else
                imgui.CloseCurrentPopup()
                clear_bazaar_dialog()
            end
            imgui.EndPopup()
        end

        if imgui.BeginPopupModal('##satchel_drop', nil, ImGuiWindowFlags_AlwaysAutoResize or 0) then
            local dd = satchel.drop_dialog
            if dd.slot and dd.slot.id and dd.slot.id > 0 then
                local name = items.get_item_name(dd.slot.id) or '?'
                local count = math.max(1, math.floor(tonumber(dd.slot.count) or 1))
                imgui.Text('Confirm Item Drop')
                imgui.Separator()
                imgui.Text(('Drop "%s"?'):format(name))
                if count > 1 then
                    imgui.Text(('This will drop the full stack of %d.'):format(count))
                end
                imgui.Separator()
                if imgui.Button('Drop', { 80, 0 }) then
                    packets.send_drop_packet(dd.slot)
                    imgui.CloseCurrentPopup()
                    clear_slot_dialog(satchel.drop_dialog)
                end
                imgui.SameLine(0, 8)
                if imgui.Button('Cancel', { 80, 0 }) then
                    imgui.CloseCurrentPopup()
                    clear_slot_dialog(satchel.drop_dialog)
                end
            else
                imgui.CloseCurrentPopup()
                clear_slot_dialog(satchel.drop_dialog)
            end
            imgui.EndPopup()
        end

        if imgui.BeginPopupModal('##satchel_split', nil, ImGuiWindowFlags_AlwaysAutoResize or 0) then
            local sd = satchel.split_dialog
            if sd.slot and sd.slot.id and sd.slot.id > 0 then
                local name = items.get_item_name(sd.slot.id) or '?'
                local stack_size = tonumber(sd.slot.count) or 1
                local max_qty = math.max(1, stack_size - 1)
                imgui.Text(('Split "%s"  (stack of %d)'):format(name, stack_size))
                imgui.Separator()
                imgui.Text('Quantity to split off:')
                imgui.SliderInt('##split_qty', sd.quantity, 1, max_qty)
                imgui.Separator()
                if imgui.Button('Split', { 80, 0 }) then
                    packets.queue_split_command(sd.slot, sd.quantity[1])
                    imgui.CloseCurrentPopup()
                    clear_slot_dialog(satchel.split_dialog)
                end
                imgui.SameLine(0, 8)
                if imgui.Button('Cancel', { 80, 0 }) then
                    imgui.CloseCurrentPopup()
                    clear_slot_dialog(satchel.split_dialog)
                end
            else
                imgui.CloseCurrentPopup()
                clear_slot_dialog(satchel.split_dialog)
            end
            imgui.EndPopup()
        end
    end

    return M
end

return contextmenu
