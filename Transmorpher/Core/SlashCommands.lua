local addon, ns = ...

-- ============================================================
-- SLASH COMMANDS — /morph, /vm, /Transmorpher
-- ============================================================

local mainFrame = ns.mainFrame

SLASH_Transmorpher1 = "/morph"
SLASH_Transmorpher2 = "/vm"
SLASH_Transmorpher3 = "/Transmorpher"

local function PrintHelp()
    local lines = {
        "|cffF5C842--- Transmorpher Commands ---|r",
        "|cffffff00/morph|r - Toggle the Transmorpher window",
        "|cffffff00/morph reset|r - Reset all morphs",
        "|cffffff00/morph status|r - Show DLL and morph status",
        "|cffffff00/morph morph <displayID>|r - Morph race to display ID",
        "|cffffff00/morph scale <value>|r - Set character scale (0.1-10)",
        "|cffffff00/morph mount <displayID>|r - Morph mount to display ID",
        "|cffffff00/morph pet <displayID>|r - Morph pet to display ID",
        "|cffffff00/morph hpet <displayID>|r - Morph combat pet to display ID",
        "|cffffff00/morph enchant <mh|oh> <enchantID>|r - Apply enchant visual",
        "|cffffff00/morph title <titleID>|r - Apply title",
        "|cffffff00/morph sync|r - Force broadcast state to peers",
        "|cffffff00/morph help|r - Show this help",
    }
    for _, line in ipairs(lines) do
        SELECTED_CHAT_FRAME:AddMessage(line)
    end
end

local function PrintStatus()
    local dllStatus = TRANSMORPHER_DLL_LOADED == "TRUE" and "|cff00ff00LOADED|r" or "|cffff0000NOT LOADED|r"
    local hookStatus = "Unknown"
    if TRANSMORPHER_DLL_STATUS then
        hookStatus = TRANSMORPHER_DLL_STATUS.hooks and "|cff00ff00OK|r" or "|cffff6600NO HOOKS|r"
    end

    SELECTED_CHAT_FRAME:AddMessage("|cffF5C842--- Transmorpher Status ---|r")
    SELECTED_CHAT_FRAME:AddMessage("  DLL: " .. dllStatus)
    SELECTED_CHAT_FRAME:AddMessage("  Hooks: " .. hookStatus)

    -- Current morph state
    if TransmorpherCharacterState then
        local s = TransmorpherCharacterState
        local morphCount = 0
        if s.Items then for _ in pairs(s.Items) do morphCount = morphCount + 1 end end

        SELECTED_CHAT_FRAME:AddMessage("  Race Morph: " .. (s.Morph and ("|cff00ff00" .. s.Morph .. "|r") or "|cff888888None|r"))
        SELECTED_CHAT_FRAME:AddMessage("  Scale: " .. (s.Scale and ("|cff00ff00" .. s.Scale .. "|r") or "|cff8888881.0|r"))
        SELECTED_CHAT_FRAME:AddMessage("  Item Morphs: |cff00ff00" .. morphCount .. "|r slots")
        SELECTED_CHAT_FRAME:AddMessage("  Mount: " .. (s.MountDisplay and ("|cff00ff00" .. s.MountDisplay .. "|r") or "|cff888888None|r")
            .. (s.MountHidden and " |cffd676ff(Hidden)|r" or ""))
        SELECTED_CHAT_FRAME:AddMessage("  Pet: " .. (s.PetDisplay and ("|cff00ff00" .. s.PetDisplay .. "|r") or "|cff888888None|r"))
        SELECTED_CHAT_FRAME:AddMessage("  Combat Pet: " .. (s.HunterPetDisplay and ("|cff00ff00" .. s.HunterPetDisplay .. "|r") or "|cff888888None|r")
            .. (s.HunterPetScale and s.HunterPetScale ~= 1.0 and (" scale:" .. s.HunterPetScale) or ""))
        SELECTED_CHAT_FRAME:AddMessage("  Enchants: MH=" .. (s.EnchantMH or "none") .. " OH=" .. (s.EnchantOH or "none"))
        SELECTED_CHAT_FRAME:AddMessage("  Title: " .. (s.TitleID and ("|cff00ff00" .. s.TitleID .. "|r") or "|cff888888None|r"))
    else
        SELECTED_CHAT_FRAME:AddMessage("  No morph state saved")
    end

    -- Peer count
    local peerCount = ns.P2PGetPeerCount and ns.P2PGetPeerCount() or 0
    SELECTED_CHAT_FRAME:AddMessage("  Synced Peers: |cff00ff00" .. peerCount .. "|r")
end

SlashCmdList["Transmorpher"] = function(msg)
    msg = msg:trim()
    local cmd, rest = msg:match("^(%S+)%s*(.*)")
    if cmd then cmd = cmd:lower() else cmd = msg:lower() end

    if cmd == "reset" then
        if ns.IsMorpherReady() then
            ns.SendMorphCommand("RESET:ALL|MOUNT_RESET|HPET_RESET|PET_RESET|TITLE_RESET|ENCHANT_RESET")
            if TransmorpherCharacterState then
                if TransmorpherCharacterState.Items then wipe(TransmorpherCharacterState.Items) end
                if TransmorpherCharacterState.HiddenItems then wipe(TransmorpherCharacterState.HiddenItems) end
                if TransmorpherCharacterState.Mounts then wipe(TransmorpherCharacterState.Mounts) end
                if TransmorpherCharacterState.WeaponSets then wipe(TransmorpherCharacterState.WeaponSets) end
                TransmorpherCharacterState.Morph = nil
                TransmorpherCharacterState.Scale = nil
                TransmorpherCharacterState.PetDisplay = nil
                TransmorpherCharacterState.HunterPetDisplay = nil
                TransmorpherCharacterState.HunterPetScale = nil
                TransmorpherCharacterState.EnchantMH = nil
                TransmorpherCharacterState.EnchantOH = nil
                TransmorpherCharacterState.TitleID = nil
                TransmorpherCharacterState.GroundMountDisplay = nil
                TransmorpherCharacterState.GroundMountName = nil
                TransmorpherCharacterState.FlyingMountDisplay = nil
                TransmorpherCharacterState.FlyingMountName = nil
                TransmorpherCharacterState.MountDisplay = nil
                TransmorpherCharacterState.MountHidden = false
            end
            if mainFrame.slots then
                for _, slotName in pairs(ns.slotOrder) do
                    local slot = mainFrame.slots[slotName]
                    if slot then
                        slot.isMorphed = false; slot.morphedItemId = nil; slot.isHiddenSlot = false
                        ns.HideMorphGlow(slot)
                        if slot.eyeButton then
                            slot.eyeButton.isHidden = false
                            if slot.eyeButton.UpdateVisuals then
                                slot.eyeButton:UpdateVisuals()
                            end
                        end
                        if slotName == ns.rangedSlot and ("DRUIDSHAMANPALADINDEATHKNIGHT"):find(ns.playerClass) then
                            slot:RemoveItem()
                        else
                            local equippedId = ns.GetEquippedItemForSlot(slotName)
                            if equippedId then slot:SetItem(equippedId)
                            else slot:RemoveItem() end
                        end
                    end
                end
            end
            if mainFrame.specialSlots then
                for _, s in pairs(mainFrame.specialSlots) do
                    s.displayID = nil
                    s.name = nil
                    if s.icon then s.icon:Hide() end
                    ns.HideMorphGlow(s)
                end
            end
            if mainFrame.enchantSlots then
                for _, es in pairs(mainFrame.enchantSlots) do
                    es.isMorphed = false; es:RemoveEnchant(); ns.HideMorphGlow(es)
                end
            end
            ns.SyncDressingRoom()
            if ns.UpdateMorphStatusBar then ns.UpdateMorphStatusBar() end

            if ns.BroadcastMorphState then
                ns.BroadcastMorphState(true)
            end

            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: All morphs hard reset!")
        else
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: |cffff0000DLL not loaded!|r Place dinput8.dll in your WoW folder.")
        end

    elseif cmd == "status" then
        PrintStatus()

    elseif cmd == "help" then
        PrintHelp()

    elseif cmd == "morph" then
        local id = tonumber(rest)
        if id and id > 0 then
            if ns.IsMorpherReady() then
                ns.SendMorphCommand("MORPH:" .. id)
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Race morphed to display ID " .. id)
            else
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: |cffff0000DLL not loaded!|r")
            end
        else
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Usage: /morph morph <displayID>")
        end

    elseif cmd == "scale" then
        local val = tonumber(rest)
        if val and val >= 0.1 and val <= 10.0 then
            if ns.IsMorpherReady() then
                ns.SendMorphCommand("SCALE:" .. val)
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Scale set to " .. val)
            else
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: |cffff0000DLL not loaded!|r")
            end
        else
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Usage: /morph scale <0.1-10.0>")
        end

    elseif cmd == "mount" then
        local id = tonumber(rest)
        if id and id > 0 then
            if ns.IsMorpherReady() then
                ns.SendMorphCommand("MOUNT_MORPH:" .. id)
                if ns.UpdateSpecialSlots then ns.UpdateSpecialSlots() end
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Mount morphed to display ID " .. id)
            else
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: |cffff0000DLL not loaded!|r")
            end
        else
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Usage: /morph mount <displayID>")
        end

    elseif cmd == "pet" then
        local id = tonumber(rest)
        if id and id > 0 then
            if ns.IsMorpherReady() then
                ns.SendMorphCommand("PET_MORPH:" .. id)
                if ns.UpdateSpecialSlots then ns.UpdateSpecialSlots() end
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Pet morphed to display ID " .. id)
            else
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: |cffff0000DLL not loaded!|r")
            end
        else
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Usage: /morph pet <displayID>")
        end

    elseif cmd == "hpet" then
        local id = tonumber(rest)
        if id and id > 0 then
            if ns.IsMorpherReady() then
                ns.SendMorphCommand("HPET_MORPH:" .. id)
                ns.SendMorphCommand("HPET_SCALE:1.0")
                if TransmorpherCharacterState then TransmorpherCharacterState.HunterPetScale = 1.0 end
                if ns.UpdateSpecialSlots then ns.UpdateSpecialSlots() end
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Combat pet morphed to display ID " .. id)
            else
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: |cffff0000DLL not loaded!|r")
            end
        else
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Usage: /morph hpet <displayID>")
        end

    elseif cmd == "enchant" then
        local slot, id = rest:match("^(%S+)%s+(%d+)")
        id = tonumber(id)
        if slot and id and id > 0 then
            slot = slot:lower()
            if slot == "mh" then
                if ns.IsMorpherReady() then
                    ns.SendMorphCommand("ENCHANT_MH:" .. id)
                    if ns.ScheduleDressingRoomSync then ns.ScheduleDressingRoomSync(0.05) end
                    SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Main-hand enchant set to " .. id)
                end
            elseif slot == "oh" then
                if ns.IsMorpherReady() then
                    ns.SendMorphCommand("ENCHANT_OH:" .. id)
                    if ns.ScheduleDressingRoomSync then ns.ScheduleDressingRoomSync(0.05) end
                    SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Off-hand enchant set to " .. id)
                end
            else
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Usage: /morph enchant <mh|oh> <enchantID>")
            end
        else
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Usage: /morph enchant <mh|oh> <enchantID>")
        end

    elseif cmd == "title" then
        local id = tonumber(rest)
        if id and id > 0 then
            if ns.IsMorpherReady() then
                ns.SendMorphCommand("TITLE:" .. id)
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Title set to ID " .. id)
            else
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: |cffff0000DLL not loaded!|r")
            end
        else
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Usage: /morph title <titleID>")
        end

    elseif cmd == "sync" then
        if ns.BroadcastMorphState then
            ns.BroadcastMorphState()
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: State broadcasted to peers")
        else
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: P2P sync not available")
        end

    else
        if mainFrame:IsShown() then mainFrame:Hide() else mainFrame:Show() end
    end
end
