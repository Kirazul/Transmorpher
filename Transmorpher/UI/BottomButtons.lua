local addon, ns = ...

-- ============================================================
-- BOTTOM BUTTONS — Apply All, Reset Morph, Reset Preview, Undress
-- ============================================================

local mainFrame = ns.mainFrame
local ACTION_GAP = 6
local ACTION_WIDTH = math.floor(((mainFrame.dressingRoom:GetWidth() or 400) - ACTION_GAP * 3) / 4)
local ACTION_REST_BG = { 0.125, 0.085, 0.025, 0.99 }
local ACTION_REST_BD = { 0.92, 0.70, 0.20, 0.98 }
local ACTION_HOVER_BG = { 0.205, 0.145, 0.042, 1.00 }
local ACTION_HOVER_BD = { 1.00, 0.86, 0.34, 1.00 }
local ACTION_TEXT = "|cffF5C842%s|r"

-- ============================================================
-- SMOOTH HOVER ANIMATION SYSTEM
-- ============================================================
local hoverAnimFrame = CreateFrame("Frame")
hoverAnimFrame:Hide()
local hoverTargets = {}
local btnRestStates = {}

hoverAnimFrame:SetScript("OnUpdate", function(self, dt)
    local t = math.min(dt * 10, 1)
    local anyActive = false
    for btn, info in pairs(hoverTargets) do
        local done = true
        for i = 1, 4 do
            local diff = info.tBg[i] - info.cBg[i]
            if math.abs(diff) > 0.002 then
                info.cBg[i] = info.cBg[i] + diff * t
                done = false
            else
                info.cBg[i] = info.tBg[i]
            end
        end
        for i = 1, 4 do
            local diff = info.tBd[i] - info.cBd[i]
            if math.abs(diff) > 0.002 then
                info.cBd[i] = info.cBd[i] + diff * t
                done = false
            else
                info.cBd[i] = info.tBd[i]
            end
        end
        btn:SetBackdropColor(info.cBg[1], info.cBg[2], info.cBg[3], info.cBg[4])
        btn:SetBackdropBorderColor(info.cBd[1], info.cBd[2], info.cBd[3], info.cBd[4])
        if done then
            hoverTargets[btn] = nil
        else
            anyActive = true
        end
    end
    if not anyActive then self:Hide() end
end)

function ns.RegisterSmoothHover(btn, restBg, restBd)
    btnRestStates[btn] = { bg = {restBg[1], restBg[2], restBg[3], restBg[4]}, bd = {restBd[1], restBd[2], restBd[3], restBd[4]} }
end

function ns.SmoothBackdropTo(btn, targetBg, targetBd)
    local info = hoverTargets[btn]
    if not info then
        local rest = btnRestStates[btn]
        local sBg = rest and rest.bg or {targetBg[1], targetBg[2], targetBg[3], targetBg[4]}
        local sBd = rest and rest.bd or {targetBd[1], targetBd[2], targetBd[3], targetBd[4]}
        info = { cBg = {sBg[1], sBg[2], sBg[3], sBg[4]}, cBd = {sBd[1], sBd[2], sBd[3], sBd[4]} }
        hoverTargets[btn] = info
    end
    info.tBg = targetBg
    info.tBd = targetBd
    hoverAnimFrame:Show()
end

local actionButtonBackdrop = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    tile = true,
    tileSize = 8,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

-- Polished look for the four action buttons: a crisp 1px accent line in the button's
-- theme colour along the top, a soft vertical sheen, and a 1px shadow along the bottom.
-- Turns the flat coloured blocks into a clean, retail-style segmented button row.
local function StyleActionButton(btn)
    local sheen = btn:CreateTexture(nil, "ARTWORK")
    sheen:SetTexture("Interface\\Buttons\\WHITE8x8")
    sheen:SetPoint("TOPLEFT", 2, -2)
    sheen:SetPoint("TOPRIGHT", -2, -2)
    sheen:SetHeight(13)
    sheen:SetGradientAlpha("VERTICAL", 1.00, 0.84, 0.30, 0.22, 0.46, 0.30, 0.08, 0.05)

    local accent = btn:CreateTexture(nil, "OVERLAY")
    accent:SetTexture("Interface\\Buttons\\WHITE8x8")
    accent:SetHeight(2)
    accent:SetPoint("TOPLEFT", 2, -2)
    accent:SetPoint("TOPRIGHT", -2, -2)
    accent:SetVertexColor(1.00, 0.84, 0.30, 0.95)
    btn.accent = accent

    local shadow = btn:CreateTexture(nil, "BACKGROUND")
    shadow:SetTexture("Interface\\Buttons\\WHITE8x8")
    shadow:SetHeight(2)
    shadow:SetPoint("BOTTOMLEFT", 2, 1)
    shadow:SetPoint("BOTTOMRIGHT", -2, 1)
    shadow:SetVertexColor(0, 0, 0, 0.45)
end

local function ApplyGoldenActionButton(btn, text)
    btn:SetText(ACTION_TEXT:format(text))
    local fontString = btn:GetFontString()
    if fontString then
        fontString:ClearAllPoints()
        fontString:SetPoint("CENTER", btn, "CENTER", 0, 0)
        fontString:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    end
    btn:SetBackdrop(actionButtonBackdrop)
    btn:SetBackdropColor(ACTION_REST_BG[1], ACTION_REST_BG[2], ACTION_REST_BG[3], ACTION_REST_BG[4])
    btn:SetBackdropBorderColor(ACTION_REST_BD[1], ACTION_REST_BD[2], ACTION_REST_BD[3], ACTION_REST_BD[4])
    ns.RegisterSmoothHover(btn, ACTION_REST_BG, ACTION_REST_BD)
    StyleActionButton(btn)
end

local function LayoutActionButtons()
    local applyAll = mainFrame.buttons.applyAll
    local resetMorph = mainFrame.buttons.resetMorph
    local reset = mainFrame.buttons.reset
    local undress = mainFrame.buttons.undress
    if not (applyAll and resetMorph and reset and undress and mainFrame.dressingRoom) then return end

    local rowWidth = mainFrame.dressingRoom:GetWidth() or 400
    local buttonWidth = math.floor((rowWidth - ACTION_GAP * 3) / 4)
    local buttons = { applyAll, resetMorph, reset, undress }

    for i, button in ipairs(buttons) do
        button:ClearAllPoints()
        button:SetHeight(38)
        if i == 1 then
            button:SetPoint("TOPLEFT", mainFrame.dressingRoom, "BOTTOMLEFT", 0, -6)
        else
            button:SetPoint("TOPLEFT", buttons[i - 1], "TOPRIGHT", ACTION_GAP, 0)
        end
        if i < #buttons then
            button:SetWidth(buttonWidth)
        else
            button:SetPoint("TOPRIGHT", mainFrame.dressingRoom, "BOTTOMRIGHT", 0, -6)
        end
    end
end

local function HoverGoldenActionButton(btn)
    ns.SmoothBackdropTo(btn, ACTION_HOVER_BG, ACTION_HOVER_BD)
end

local function LeaveGoldenActionButton(btn)
    ns.SmoothBackdropTo(btn, ACTION_REST_BG, ACTION_REST_BD)
end

-- Apply All
mainFrame.buttons.applyAll = ns.CreateGoldenButton("$parentButtonApplyAll", mainFrame)
do
    local btn = mainFrame.buttons.applyAll
    btn:SetPoint("TOPLEFT", mainFrame.dressingRoom, "BOTTOMLEFT", 0, -6)
    btn:SetPoint("BOTTOM", mainFrame.stats, "BOTTOM", 0, 1)
    btn:SetWidth(ACTION_WIDTH)
    ApplyGoldenActionButton(btn, "Apply All")

    btn:SetScript("OnClick", function()
        if not ns.IsMorpherReady() then return end
        -- NO busy-lock / Disable() here. The old lock + btn:Disable() could get
        -- stuck (its timer-based unlock never firing) and leave Apply All PERMANENTLY
        -- disabled = "nothing applies until relog". Apply All is idempotent (the DLL
        -- dedups commands), so just run it every click — robust and simple.
        local didChange = false
        local cmdQueue = {}
        local state = TransmorpherCharacterState or {}
        local stateItems = state.Items or {}
        local stateHidden = state.HiddenItems or {}
        for _, slotName in ipairs(ns.slotOrder) do
            local slot = mainFrame.slots[slotName]
            if slot.itemId and ns.slotToEquipSlotId[slotName] then
                local slotId = ns.slotToEquipSlotId[slotName]
                local trackedItem = stateItems[slotId]
                local trackedHidden = stateHidden[slotId]
                if slot.isHiddenSlot then
                    if not trackedHidden then
                        table.insert(cmdQueue, "ITEM:"..slotId..":-1")
                        local keepItemId = (trackedItem and trackedItem > 0) and trackedItem or ((slot.morphedItemId and slot.morphedItemId > 0) and slot.morphedItemId or slot.itemId)
                        slot.isMorphed = true; slot.morphedItemId = keepItemId
                        ns.FlashMorphSlot(slot)
                        didChange = true
                    end
                else
                    local equippedId = ns.GetEquippedItemForSlot(slotName)
                    if equippedId and equippedId == slot.itemId then
                        slot.isMorphed = false; slot.morphedItemId = nil
                        ns.HideMorphGlow(slot)
                    elseif trackedItem and trackedItem == slot.itemId and not trackedHidden then
                    else
                        table.insert(cmdQueue, "ITEM:"..slotId..":"..slot.itemId)
                        slot.isMorphed = true; slot.morphedItemId = slot.itemId
                        ns.FlashMorphSlot(slot)
                        didChange = true
                    end
                end
            end
        end
        if mainFrame.enchantSlots then
            local mh = mainFrame.enchantSlots["Enchant MH"]
            if mh then
                if mh.enchantId then
                    if state.EnchantMH ~= mh.enchantId then
                        table.insert(cmdQueue, "ENCHANT_MH:"..mh.enchantId)
                        didChange = true
                        mh.isMorphed = true
                        ns.FlashMorphSlot(mh, "orange")
                    end
                else
                    if mh.isMorphed then
                        table.insert(cmdQueue, "ENCHANT_RESET_MH")
                        didChange = true
                        ns.FlashMorphSlot(mh, "orange")
                    end
                    mh.isMorphed = false
                    ns.HideMorphGlow(mh)
                end
            end
            local oh = mainFrame.enchantSlots["Enchant OH"]
            if oh then
                if oh.enchantId then
                    if state.EnchantOH ~= oh.enchantId then
                        table.insert(cmdQueue, "ENCHANT_OH:"..oh.enchantId)
                        didChange = true
                        oh.isMorphed = true
                        ns.FlashMorphSlot(oh, "orange")
                    end
                else
                    if oh.isMorphed then
                        table.insert(cmdQueue, "ENCHANT_RESET_OH")
                        didChange = true
                        ns.FlashMorphSlot(oh, "orange")
                    end
                    oh.isMorphed = false
                    ns.HideMorphGlow(oh)
                end
            end
        end
        -- Do not force a REFRESH here. The DLL applies descriptor changes during
        -- the batch and component-refreshes only when something actually changed;
        -- a no-op refresh was causing the visible delayed blink.
        if didChange and #cmdQueue > 0 then
            ns.SendMorphCommand(table.concat(cmdQueue, "|"))
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: All slots morphed!")
        else
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: No changes to apply.")
        end
        if mainFrame.dressingRoom then
            mainFrame.dressingRoom:SetModelAlpha(1)
            mainFrame.dressingRoom.suppressSyncUntil = nil
        end
        PlaySound("gsTitleOptionOK")
    end)
    btn:HookScript("OnEnter", function(self)
        HoverGoldenActionButton(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT"); GameTooltip:ClearLines()
        GameTooltip:AddLine("|cffF5C842Apply All|r", 1, 1, 1)
        GameTooltip:AddLine("Apply all previewed items as morph to your character.", 0.7, 0.9, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function(self)
        LeaveGoldenActionButton(self)
        GameTooltip:Hide()
    end)
end

-- Reset Morph
mainFrame.buttons.resetMorph = ns.CreateGoldenButton("$parentButtonResetMorph", mainFrame)
do
    local btn = mainFrame.buttons.resetMorph
    btn:SetPoint("TOPLEFT", mainFrame.buttons.applyAll, "TOPRIGHT", ACTION_GAP, 0)
    btn:SetPoint("BOTTOM", mainFrame.buttons.applyAll, "BOTTOM")
    btn:SetWidth(ACTION_WIDTH)
    ApplyGoldenActionButton(btn, "Reset Morph")

    btn:SetScript("OnClick", function()
        if ns.IsMorpherReady() then
            ns.SendMorphCommand("RESET:ALL")
            if ns.Skin_ResetAll then ns.Skin_ResetAll(true) end
            -- Reset Morph also clears any active character Visuals (restores original state).
            if ns.Visuals_Clear then ns.Visuals_Clear() end
            -- Also clear the Barber look + colors (discrete skin/face/hair AND the free-RGB
            -- recolor tints). Barber_Reset sends BARBER_OFF + BARBER_TINT_CLEAR, which the DLL
            -- persists (restores the real look, deletes the colour sidecar) so Reset Morph
            -- wipes the barber too — no leftover tint surviving the reset.
            if ns.Barber_Reset then ns.Barber_Reset(true) end
            -- Clear mount morphs
            if TransmorpherCharacterState then
                TransmorpherCharacterState.GroundMountDisplay = nil
                TransmorpherCharacterState.GroundMountName = nil
                TransmorpherCharacterState.FlyingMountDisplay = nil
                TransmorpherCharacterState.FlyingMountName = nil
                TransmorpherCharacterState.MountDisplay = nil
                TransmorpherCharacterState.MountHidden = false
                if TransmorpherCharacterState.Mounts then
                    wipe(TransmorpherCharacterState.Mounts)
                end
            end
            ns.SendRawMorphCommand("MOUNT_RESET")
            if TransmorpherCharacterState then
                TransmorpherCharacterState.Sheathe = {}
            end
            ns.SendRawMorphCommand("SHEATHE:0:-1|SHEATHE:1:-1")
            for _, slotName in pairs(ns.slotOrder) do
                local slot = mainFrame.slots[slotName]
                slot.isMorphed = false; slot.morphedItemId = nil; slot.isHiddenSlot = false
                ns.HideMorphGlow(slot)
                if slot.sheatheButton and slot.sheatheButton.UpdateVisuals then
                    slot.sheatheButton:UpdateVisuals()
                end
                if slot.eyeButton then
                    slot.eyeButton.isHidden = false
                    if slot.eyeButton.UpdateVisuals then
                        slot.eyeButton:UpdateVisuals()
                    end
                end
                if slotName == ns.rangedSlot and ("DRUIDSHAMANPALADINDEATHKNIGHT"):find(ns.playerClass) then
                    -- skip
                else
                    local equippedId = ns.GetEquippedItemForSlot(slotName)
                    if equippedId then slot:SetItem(equippedId)
                    else slot.itemId = nil; slot.textures.empty:Show(); slot.textures.item:Hide() end
                end
            end
            if mainFrame.enchantSlots then
                for _, es in pairs(mainFrame.enchantSlots) do
                    es.isMorphed = false; es:RemoveEnchant(); ns.HideMorphGlow(es)
                end
            end
            if mainFrame.dressingRoom then mainFrame.dressingRoom.forceLiveAfterSync = true end
            if mainFrame.dressingRoom then mainFrame.dressingRoom.suppressSyncUntil = nil end
            ns.SyncDressingRoom()
            if ns.BroadcastMorphState then
                ns.BroadcastMorphState(true)
            end
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: All morphs reset!")
        end
        PlaySound("gsTitleOptionOK")
    end)
    btn:HookScript("OnEnter", function(self)
        HoverGoldenActionButton(self)
    end)
    btn:HookScript("OnLeave", function(self)
        LeaveGoldenActionButton(self)
    end)
end

-- Reset Preview
mainFrame.buttons.reset = ns.CreateGoldenButton("$parentButtonReset", mainFrame)
do
    local btn = mainFrame.buttons.reset
    btn:SetPoint("TOPLEFT", mainFrame.buttons.resetMorph, "TOPRIGHT", ACTION_GAP, 0)
    btn:SetPoint("BOTTOM", mainFrame.buttons.applyAll, "BOTTOM")
    btn:SetWidth(ACTION_WIDTH)
    ApplyGoldenActionButton(btn, "Reset Preview")
    btn:SetScript("OnClick", function()
        -- "Reset Preview" should discard transient try-ons and show the model as it
        -- ACTUALLY is right now (current morph + the gear in the slots) — not dump it
        -- to a bare real-race player. frame:Reset() only re-points the camera/unit, so
        -- follow it with a full SyncDressingRoom rebuild from the live slot state.
        if mainFrame.dressingRoom and mainFrame.dressingRoom.Reset then
            mainFrame.dressingRoom.suppressSyncUntil = nil
            mainFrame.dressingRoom:Reset()
        end
        if mainFrame.dressingRoom and mainFrame.dressingRoom.ShowLive then
            mainFrame.dressingRoom:ShowLive()
        end
        PlaySound("gsTitleOptionOK")
    end)
    btn:HookScript("OnEnter", HoverGoldenActionButton)
    btn:HookScript("OnLeave", LeaveGoldenActionButton)
end

-- Undress
mainFrame.buttons.undress = ns.CreateGoldenButton("$parentButtonUndress", mainFrame)
do
    local btn = mainFrame.buttons.undress
    btn:SetPoint("TOPLEFT", mainFrame.buttons.reset, "TOPRIGHT", ACTION_GAP, 0)
    btn:SetPoint("TOPRIGHT", mainFrame.dressingRoom, "BOTTOMRIGHT", 0, -6)
    btn:SetPoint("BOTTOM", mainFrame.buttons.applyAll, "BOTTOM")
    ApplyGoldenActionButton(btn, "Undress")
    btn:SetScript("OnClick", function()
        mainFrame.dressingRoom:Undress(); PlaySound("gsTitleOptionOK")
    end)
    btn:HookScript("OnEnter", HoverGoldenActionButton)
    btn:HookScript("OnLeave", LeaveGoldenActionButton)
end

LayoutActionButtons()
mainFrame:HookScript("OnSizeChanged", LayoutActionButtons)
