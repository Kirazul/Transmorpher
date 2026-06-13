local addon, ns = ...

-- ============================================================
-- SHEATHE TOGGLE  —  per-weapon sheath position (Main Hand / Off-hand)
--
--   Adds a small button to the Main Hand and Off-hand slots (next to the hide
--   "eye" button). Clicking it opens a flyout: Back / Hip / Hidden / Default.
--   The choice is sent to the DLL (SHEATHE:<slot>:<value>) which hooks the
--   client's GetSheatheType so the chosen weapon (morphed OR original) rests in
--   that position when sheathed. Persists per character + re-applies on login.
--
--   Verified RE (3.3.5a): GetSheatheType @0x758F50 -> itemcache(+0x198) -> attach
--   jump table @0x4EB128. value 1 = Back (attach 27), 3 = Hip (attach 33),
--   7 = Hidden (no attachment), -1 = natural.
-- ============================================================

local mainFrame = ns.mainFrame
local TOGGLE_SIZE = 15
local TEX_SHEATHE = "Interface\\AddOns\\Transmorpher\\assets\\Transmog-Overlay-Hide"

-- slotName -> DLL slot index (0 = main hand, 1 = off hand)
local WEAPON_SLOTS = { ["Main Hand"] = 0, ["Off-hand"] = 1 }

-- The 3 positions + natural. value = the sheathe code the DLL forces.
local OPTIONS = {
    { key = "back",    label = "Back",    value = 1,  icon = "Interface\\Icons\\INV_Sword_27" },
    { key = "hip",     label = "Hip",     value = 3,  icon = "Interface\\Icons\\INV_Weapon_ShortBlade_05" },
    { key = "hidden",  label = "Hidden",  value = 7,  icon = "Interface\\Icons\\Spell_Magic_LesserInvisibilty" },
    { key = "default", label = "Default", value = -1, icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
}

local function Send(cmd)
    if ns.IsMorpherReady and ns.IsMorpherReady() then
        if ns.SendRawMorphCommand then ns.SendRawMorphCommand(cmd); return true
        elseif ns.SendMorphCommand then ns.SendMorphCommand(cmd); return true end
    end
    return false
end

-- ----- saved state -----
local function SheatheState()
    if not TransmorpherCharacterState then TransmorpherCharacterState = { Items = {} } end
    TransmorpherCharacterState.Sheathe = TransmorpherCharacterState.Sheathe or {}
    return TransmorpherCharacterState.Sheathe
end
local function GetSheatheValue(slotIdx)
    local v = SheatheState()[slotIdx]
    if v == nil then return -1 end
    return v
end
local function SetSheatheValue(slotIdx, value)
    if value == -1 then SheatheState()[slotIdx] = nil
    else SheatheState()[slotIdx] = value end
end

-- Push the saved sheath positions to the DLL (login / DLL-ready / zone-in). The
-- DLL forgets overrides on relog, so we re-assert from saved state.
function ns.Sheathe_ApplyAll()
    local st = SheatheState()
    for _, idx in ipairs({ 0, 1 }) do
        local v = st[idx]
        if v ~= nil and v ~= -1 then Send("SHEATHE:" .. idx .. ":" .. v) end
    end
end

-- ============================================================
-- Shared flyout menu (one frame, repositioned under whichever button opened it)
-- ============================================================
local flyout
local function BuildFlyout()
    local f = CreateFrame("Frame", "TM_SheatheFlyout", UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetSize(120, 8 + #OPTIONS * 22 + 20)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0.05, 0.055, 0.07, 0.97)
    f:SetBackdropBorderColor(0.56, 0.47, 0.20, 0.95)
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", 0, -6); title:SetTextColor(0.96, 0.78, 0.26)
    f.title = title

    f.rows = {}
    for i, opt in ipairs(OPTIONS) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(108, 20); b:SetPoint("TOP", 0, -20 - (i - 1) * 22)
        local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(0.12, 0.10, 0.07, 1); b.bg = bg
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetTexture(0.96, 0.78, 0.26, 0.20)
        local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetSize(16, 16); ic:SetPoint("LEFT", 4, 0)
        ic:SetTexture(opt.icon); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", ic, "RIGHT", 6, 0); fs:SetText(opt.label); fs:SetTextColor(0.96, 0.90, 0.72); b.fs = fs
        -- selected indicator: a real check texture (a font glyph rendered as a stray "?")
        local chk = b:CreateTexture(nil, "OVERLAY"); chk:SetSize(16, 16); chk:SetPoint("RIGHT", -4, 0)
        chk:SetTexture("Interface\\Buttons\\UI-CheckBox-Check"); chk:Hide(); b.chk = chk
        b.opt = opt
        b:SetScript("OnClick", function(self)
            local idx = f.slotIdx
            SetSheatheValue(idx, self.opt.value)
            Send("SHEATHE:" .. idx .. ":" .. self.opt.value)
            PlaySound("gsTitleOptionOK")
            f:Hide()
            if f.ownerBtn and f.ownerBtn.UpdateVisuals then f.ownerBtn:UpdateVisuals() end
        end)
        f.rows[i] = b
    end
    return f
end

local function OpenFlyout(ownerBtn, slotName, slotIdx)
    if not flyout then flyout = BuildFlyout() end
    if flyout:IsShown() and flyout.ownerBtn == ownerBtn then flyout:Hide(); return end
    flyout.slotIdx = slotIdx
    flyout.ownerBtn = ownerBtn
    flyout.title:SetText(slotName)
    local cur = GetSheatheValue(slotIdx)
    for _, b in ipairs(flyout.rows) do
        if b.opt.value == cur then b.chk:Show(); b.bg:SetTexture(0.20, 0.16, 0.06, 1)
        else b.chk:Hide(); b.bg:SetTexture(0.12, 0.10, 0.07, 1) end
    end
    flyout:ClearAllPoints()
    flyout:SetPoint("TOPLEFT", ownerBtn, "BOTTOMLEFT", 0, -2)
    flyout:Show()
end

-- ============================================================
-- The per-slot sheath button
-- ============================================================
local function CreateSheatheButton(slot, slotIdx)
    local btn = CreateFrame("Button", nil, slot)
    btn:SetSize(TOGGLE_SIZE, TOGGLE_SIZE)
    btn:SetFrameLevel(slot:GetFrameLevel() + 6)
    btn:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", -2, -2)
    btn:RegisterForClicks("AnyUp")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    icon:SetTexture(TEX_SHEATHE)
    btn.icon = icon

    local glow = btn:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("TOPLEFT", icon, "TOPLEFT", -4, 4)
    glow:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 4, -4)
    glow:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(0.10, 0.65, 1.00, 0.95)
    glow:Hide()
    btn.glow = glow

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(icon)
    hl:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    hl:SetBlendMode("ADD")
    hl:SetVertexColor(0.20, 0.70, 1.00, 1)
    hl:SetAlpha(0.85)

    btn.slotName = slot.slotName
    btn.slotIdx = slotIdx

    btn.UpdateVisuals = function(self)
        local cur = GetSheatheValue(self.slotIdx)
        self.icon:SetTexture(TEX_SHEATHE)
        if cur ~= -1 then
            self.icon:SetVertexColor(0.18, 0.78, 1.00, 1)
            self.glow:Show()
        else
            self.icon:SetVertexColor(0.32, 0.56, 0.92, 0.92)
            self.glow:Hide()
        end
        self:SetAlpha(1)
    end

    btn:SetScript("OnClick", function(self)
        if not ns.IsMorpherReady() then
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: |cffff0000DLL not loaded!|r"); return
        end
        OpenFlyout(self, self.slotName, self.slotIdx)
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local cur = GetSheatheValue(self.slotIdx)
        local name = "Default"
        for _, o in ipairs(OPTIONS) do if o.value == cur then name = o.label end end
        GameTooltip:SetText("Sheath position: |cffF5C842" .. name .. "|r")
        GameTooltip:AddLine(self.slotName .. " \226\128\148 click for Back / Hip / Hidden", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self.icon:SetPoint("TOPLEFT", self, "TOPLEFT", 1, -1)
            self.icon:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 1, -1)
        end
    end)
    btn:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            self.icon:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
            self.icon:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
        end
    end)

    btn:UpdateVisuals()
    slot.sheatheButton = btn
    return btn
end

-- Build the buttons on the weapon slots.
for slotName, slotIdx in pairs(WEAPON_SLOTS) do
    local slot = mainFrame.slots and mainFrame.slots[slotName]
    if slot then CreateSheatheButton(slot, slotIdx) end
end

-- Re-apply saved sheath positions shortly after entering the world (DLL resets on relog).
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function()
    if ns.RunAfter then ns.RunAfter(1.0, function() ns.Sheathe_ApplyAll() end)
    else ns.Sheathe_ApplyAll() end
end)
