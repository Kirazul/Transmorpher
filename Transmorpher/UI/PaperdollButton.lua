local addon, ns = ...

-- ============================================================
-- CHARACTER-INFO SIDE TAB
--   A sleek vertical tab embedded flush against the RIGHT edge of the Character
--   frame (it "tucks into" the frame, bookmark-style). Opens / closes the
--   Transmorpher window, slides up & down along the edge (right-button drag) and
--   remembers its position per character. Respects "Hide Character Info Button".
-- ============================================================

local anchor = _G["CharacterFrame"] or _G["PaperDollFrame"]
if not anchor then return end

-- A SQUARE chip tucked flush against the Character frame's right edge. The frame's
-- texture carries ~30px of transparent padding past its visible border, so we pull the
-- chip left by EDGE_OVERLAP to sit pixel-flush on the gold border (a touch of overlap
-- reads as "embedded"). Square so it matches the slot chips, not a tall tab.
local TAB_W, TAB_H = 34, 34
local EDGE_OVERLAP = 30     -- pull left across the frame's transparent padding -> flush
local DEFAULT_YOFS = -38    -- resting offset from the frame's top-right
local ICON         = "Interface\\Icons\\INV_Chest_Cloth_17"

local btn = CreateFrame("Button", "TransmorpherPaperDollButton", anchor)
btn:SetSize(TAB_W, TAB_H)
btn:SetFrameStrata("HIGH")
btn:SetFrameLevel(anchor:GetFrameLevel() + 6)
btn:RegisterForClicks("LeftButtonUp")
btn:SetMovable(true)
btn:RegisterForDrag("RightButton")

-- ---- visuals: rounded vertical tab, dark gradient body, gold seam, icon, glow ----
btn:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
})
btn:SetBackdropColor(0.06, 0.06, 0.075, 0.96)
btn:SetBackdropBorderColor(0.62, 0.50, 0.20, 0.95)

local sheen = btn:CreateTexture(nil, "BORDER")
sheen:SetPoint("TOPLEFT", 1, -1); sheen:SetPoint("BOTTOMRIGHT", -1, 1)
sheen:SetTexture("Interface\\Buttons\\WHITE8x8")
sheen:SetGradientAlpha("VERTICAL", 0.10, 0.09, 0.05, 0.55, 0.30, 0.24, 0.10, 0.95)

-- Gold seam on the LEFT edge (the side tucked against the frame) — the embedded look.
local seam = btn:CreateTexture(nil, "ARTWORK")
seam:SetPoint("TOPLEFT", 1, -1); seam:SetPoint("BOTTOMLEFT", 1, 1); seam:SetWidth(2)
seam:SetTexture("Interface\\Buttons\\WHITE8x8"); seam:SetVertexColor(1.0, 0.82, 0.25, 0.9)

local icon = btn:CreateTexture(nil, "ARTWORK")
icon:SetSize(20, 20); icon:SetPoint("CENTER", 1, 0)
icon:SetTexture(ICON); icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
btn.icon = icon

local glow = btn:CreateTexture(nil, "OVERLAY")
glow:SetPoint("CENTER", 1, 0); glow:SetSize(48, 48)
glow:SetTexture("Interface\\SpellLabels\\GLOW")
glow:SetVertexColor(1, 0.82, 0.25); glow:SetAlpha(0)
btn.glow = glow

-- ---- position: vertical slide along the right edge, persisted per character ----
local function ClampY(y)
    local h = anchor:GetHeight()
    if not h or h < TAB_H then return y end
    local top, bottom = -6, -(h - TAB_H - 6)
    if y > top then y = top end
    if y < bottom then y = bottom end
    return y
end

local function AnchorAt(y)
    btn._yOfs = y
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", anchor, "TOPRIGHT", -EDGE_OVERLAP, y)
end

local function SavePosition()
    if not TransmorpherCharacterState then TransmorpherCharacterState = {} end
    TransmorpherCharacterState.PaperdollButtonY = btn._yOfs
end

local function LoadPosition()
    local y = TransmorpherCharacterState and TransmorpherCharacterState.PaperdollButtonY
    AnchorAt(ClampY(y or DEFAULT_YOFS))
end

local function OnDragUpdate()
    local top = anchor:GetTop()
    if not top then return end
    local scale = anchor:GetEffectiveScale()
    local _, cy = GetCursorPosition()
    AnchorAt(ClampY((cy / scale - top) - TAB_H / 2))
end

btn:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil); SavePosition() end)

-- ---- active-state pulse (window open) ----
local function UpdateState()
    local open = ns.mainFrame and ns.mainFrame:IsShown()
    if open then
        btn.pulse = 0
        btn:SetScript("OnUpdate", function(self, e)
            self.pulse = (self.pulse or 0) + e
            local a = 0.55 + 0.45 * math.abs(math.sin(self.pulse * 2.2))
            seam:SetVertexColor(1.0, 0.84, 0.30, a)
            if not self._hover then self.glow:SetAlpha(0.16 + 0.18 * a) end
            self.icon:SetVertexColor(1, 0.96, 0.82, 1)
        end)
    else
        btn:SetScript("OnUpdate", nil)
        seam:SetVertexColor(1.0, 0.82, 0.25, 0.9)
        btn.icon:SetVertexColor(1, 1, 1, 1)
        btn.glow:SetAlpha(btn._hover and 0.5 or 0)
    end
end

-- ---- interaction ----
btn:SetScript("OnEnter", function(self)
    self._hover = true
    if not (ns.mainFrame and ns.mainFrame:IsShown()) then self.glow:SetAlpha(0.5) end
    self:SetBackdropBorderColor(1.0, 0.86, 0.40, 1)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cffFFD100Transmorpher|r")
    GameTooltip:AddLine("Open the transmogrification window", 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cff888888Left-click:|r toggle window", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cff888888Right-drag:|r slide along the edge", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", function(self)
    self._hover = false
    self:SetBackdropBorderColor(0.62, 0.50, 0.20, 0.95)
    GameTooltip:Hide()
    if not (ns.mainFrame and ns.mainFrame:IsShown()) then self.glow:SetAlpha(0) end
end)
btn:SetScript("OnMouseDown", function(self) self.icon:SetPoint("CENTER", 1, -1) end)
btn:SetScript("OnMouseUp", function(self) self.icon:SetPoint("CENTER", 1, 0) end)
btn:SetScript("OnClick", function()
    if not ns.mainFrame then return end
    if ns.mainFrame:IsShown() then ns.mainFrame:Hide() else ns.mainFrame:Show() end
    PlaySound("igCharacterInfoTab")
    UpdateState()
end)

-- ---- visibility (the "Hide Character Info Button" setting) ----
local userHidden = false

local function ApplyVisibility()
    if userHidden or not anchor:IsShown() then
        btn:Hide()
    else
        btn:Show()
    end
end

function ns.UpdatePaperdollButtonVisibility()
    userHidden = ns.GetSettings().hidePaperdollButton and true or false
    ApplyVisibility()
    if not userHidden and anchor:IsShown() then LoadPosition(); UpdateState() end
end

anchor:HookScript("OnShow", function() ApplyVisibility(); if not userHidden then LoadPosition(); UpdateState() end end)
anchor:HookScript("OnHide", function() btn:Hide() end)

if ns.mainFrame then
    ns.mainFrame:HookScript("OnShow", UpdateState)
    ns.mainFrame:HookScript("OnHide", UpdateState)
end

-- Initialize
ns.UpdatePaperdollButtonVisibility()
LoadPosition()
UpdateState()

DEFAULT_CHAT_FRAME:AddMessage("|cffF5C842\226\154\148 Transmorpher|r v"..ns.VERSION.." loaded \226\128\148 |cff00ff00/morph|r or click the tab on your character frame.")
