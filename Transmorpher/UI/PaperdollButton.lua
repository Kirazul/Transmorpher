local addon, ns = ...

local anchor = _G["CharacterFrame"] or _G["PaperDollFrame"]
if not anchor then return end

local btn = CreateFrame("Button", "TransmorpherPaperDollButton", anchor)
btn:SetSize(32, 32) -- Sleek 32x32 size
btn:SetFrameStrata("HIGH")
btn:SetFrameLevel(anchor:GetFrameLevel() + 20)
btn:RegisterForClicks("LeftButtonUp")
btn:SetMovable(true); btn:SetClampedToScreen(true); btn:RegisterForDrag("RightButton")

-- Load/Save Position
local function SavePosition(self)
    if not TransmorpherCharacterState then TransmorpherCharacterState = {} end
    local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
    TransmorpherCharacterState.PaperdollButtonPos = { point, nil, relativePoint, xOfs, yOfs }
end

local function LoadPosition(self)
    local pos = TransmorpherCharacterState and TransmorpherCharacterState.PaperdollButtonPos
    if pos then
        self:ClearAllPoints()
        self:SetPoint(pos[1], anchor, pos[3], pos[4], pos[5])
    else
        -- Anchor externally to the right of the CharacterFrame
        self:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, -30)
    end
end

-- Textures
local normalTex = btn:CreateTexture(nil, "BACKGROUND")
normalTex:SetTexture("Interface\\Icons\\INV_Chest_Cloth_17")
normalTex:SetAllPoints()
btn:SetNormalTexture(normalTex)

local highlightTex = btn:CreateTexture(nil, "HIGHLIGHT")
highlightTex:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
highlightTex:SetAllPoints()
highlightTex:SetBlendMode("ADD")
btn:SetHighlightTexture(highlightTex)

local pushedTex = btn:CreateTexture(nil, "ARTWORK")
pushedTex:SetTexture("Interface\\Icons\\INV_Chest_Cloth_17")
pushedTex:SetAllPoints()
-- Remove desaturation, instead we'll use a color tint or just the default look
pushedTex:SetVertexColor(0.8, 0.8, 0.8) 
btn:SetPushedTexture(pushedTex)

-- Add a square border
local border = btn:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
border:SetBlendMode("ADD")
border:SetSize(58, 58)
border:SetPoint("CENTER", 0, 0)
border:SetVertexColor(1, 0.82, 0, 0.8)
btn.border = border

-- Add a glow effect on hover
local glow = btn:CreateTexture(nil, "OVERLAY")
glow:SetTexture("Interface\\SpellLabels\\GLOW")
glow:SetSize(66, 66)
glow:SetPoint("CENTER")
glow:SetVertexColor(1, 0.82, 0)
glow:SetAlpha(0)
btn.glow = glow

local isDragging = false

btn:SetScript("OnDragStart", function(self) isDragging = true; self:StartMoving() end)
btn:SetScript("OnDragStop", function(self) 
    self:StopMovingOrSizing()
    isDragging = false
    SavePosition(self)
end)

local function UpdateState()
    local mainFrame = ns.mainFrame
    if mainFrame and mainFrame:IsShown() then
        btn.border:Show()
        btn.glow:SetAlpha(1)
        btn:SetScript("OnUpdate", function(self, elapsed)
            if not self.colorTimer then self.colorTimer = 0 end
            self.colorTimer = self.colorTimer + elapsed
            
            -- Cycle every 0.7s per transition (total cycle ~3.5s for 5 colors)
            local duration = 0.7
            local t = (self.colorTimer % (duration * 5)) / duration
            local index = math.floor(t) + 1
            local pct = t % 1
            
            local colors = {
                {1.0, 0.82, 0.0}, -- Gold
                {0.7, 0.3, 1.0}, -- Purple
                {0.2, 0.6, 1.0}, -- Blue
                {0.2, 1.0, 0.2}, -- Green
                {1.0, 0.2, 0.2}, -- Red
            }
            
            local c1 = colors[index]
            local c2 = colors[index % 5 + 1]
            
            local r = c1[1] + (c2[1] - c1[1]) * pct
            local g = c1[2] + (c2[2] - c1[2]) * pct
            local b = c1[3] + (c2[3] - c1[3]) * pct
            
            self.glow:SetVertexColor(r, g, b)
            self.border:SetVertexColor(r, g, b, 0.8)
        end)
    else
        btn.border:Hide()
        btn.glow:SetAlpha(0)
        btn:SetScript("OnUpdate", nil)
    end
end

btn:SetScript("OnEnter", function(self)
    self.glow:SetAlpha(0.6)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:AddLine("|cffFFD100Transmorpher|r")
    GameTooltip:AddLine("Open the transmogrification window", 1, 1, 1, true)
    GameTooltip:AddLine(" ", 1, 1, 1, true)
    GameTooltip:AddLine("|cff888888Left-click:|r Toggle Window", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cff888888Right-click drag:|r Move Button", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", function(self) 
    GameTooltip:Hide() 
    UpdateState()
end)
btn:SetScript("OnClick", function()
    local mainFrame = ns.mainFrame
    if not mainFrame then return end
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
    end
    PlaySound("igCharacterInfoTab")
    UpdateState()
end)

local function UpdateVisibility()
    local settings = ns.GetSettings()
    if settings.hidePaperdollButton then
        btn:Hide()
    else
        btn:Show()
    end
end
ns.UpdatePaperdollButtonVisibility = UpdateVisibility

if ns.mainFrame then ns.mainFrame:HookScript("OnShow", UpdateState); ns.mainFrame:HookScript("OnHide", UpdateState) end

-- Initialize
UpdateVisibility()
LoadPosition(btn)

DEFAULT_CHAT_FRAME:AddMessage("|cffF5C842⚔ Transmorpher|r v"..ns.VERSION.." loaded — |cff00ff00/morph|r or click the button on your character model.")
