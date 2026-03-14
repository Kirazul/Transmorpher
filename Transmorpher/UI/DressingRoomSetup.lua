local addon, ns = ...

-- ============================================================
-- DRESSING ROOM SETUP
-- Creates and configures the main dressing room on the mainFrame
-- ============================================================

local mainFrame = ns.mainFrame
local _, raceFileName = UnitRace("player")
local _, classFileName = UnitClass("player")

local dressingRoomBorderBackdrop = ns.Backdrops.dressingRoom

mainFrame.dressingRoom = ns.CreateDressingRoom(nil, mainFrame)

do
    local dr = mainFrame.dressingRoom
    dr:SetPoint("TOPLEFT", 10, -74)
    dr:SetSize(400, 400)

    -- Outer glow (faint gold bloom behind the border)
    local outerGlow = CreateFrame("Frame", nil, dr)
    outerGlow:SetPoint("TOPLEFT", -5, 5)
    outerGlow:SetPoint("BOTTOMRIGHT", 5, -5)
    outerGlow:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 0, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    outerGlow:SetBackdropColor(0, 0, 0, 0)
    outerGlow:SetBackdropBorderColor(0.85, 0.65, 0.10, 0.25)

    local border = CreateFrame("Frame", nil, dr)
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetBackdrop(dressingRoomBorderBackdrop)
    border:SetBackdropColor(0, 0, 0, 0)
    border:SetBackdropBorderColor(0.85, 0.70, 0.25, 0.90)

    -- Inner shadow (1px dark line inside for beveled depth)
    local innerShadow = dr:CreateTexture(nil, "OVERLAY", nil, 7)
    innerShadow:SetTexture("Interface\\Buttons\\WHITE8x8")
    innerShadow:SetPoint("TOPLEFT", 0, 0)
    innerShadow:SetPoint("BOTTOMRIGHT", 0, 0)
    innerShadow:SetVertexColor(0, 0, 0, 0.30)

    local innerTop = dr:CreateTexture(nil, "OVERLAY", nil, 6)
    innerTop:SetTexture("Interface\\Buttons\\WHITE8x8")
    innerTop:SetHeight(1)
    innerTop:SetPoint("TOPLEFT", 1, -1)
    innerTop:SetPoint("TOPRIGHT", -1, -1)
    innerTop:SetVertexColor(0, 0, 0, 0.35)

    local innerBottom = dr:CreateTexture(nil, "OVERLAY", nil, 6)
    innerBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
    innerBottom:SetHeight(1)
    innerBottom:SetPoint("BOTTOMLEFT", 1, 1)
    innerBottom:SetPoint("BOTTOMRIGHT", -1, 1)
    innerBottom:SetVertexColor(0, 0, 0, 0.25)

    local innerLeft = dr:CreateTexture(nil, "OVERLAY", nil, 6)
    innerLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
    innerLeft:SetWidth(1)
    innerLeft:SetPoint("TOPLEFT", 1, -1)
    innerLeft:SetPoint("BOTTOMLEFT", 1, 1)
    innerLeft:SetVertexColor(0, 0, 0, 0.30)

    local innerRight = dr:CreateTexture(nil, "OVERLAY", nil, 6)
    innerRight:SetTexture("Interface\\Buttons\\WHITE8x8")
    innerRight:SetWidth(1)
    innerRight:SetPoint("TOPRIGHT", -1, -1)
    innerRight:SetPoint("BOTTOMRIGHT", -1, 1)
    innerRight:SetVertexColor(0, 0, 0, 0.30)

    -- hide the full inner shadow fill, keep only the edge lines
    innerShadow:Hide()

    -- Outer edge highlights (beveled light/shadow)
    local edgeTop = border:CreateTexture(nil, "OVERLAY")
    edgeTop:SetTexture("Interface\\Buttons\\WHITE8x8")
    edgeTop:SetHeight(1)
    edgeTop:SetPoint("TOPLEFT", 2, -2)
    edgeTop:SetPoint("TOPRIGHT", -2, -2)
    edgeTop:SetVertexColor(1, 0.96, 0.80, 0.45)

    local edgeBottom = border:CreateTexture(nil, "OVERLAY")
    edgeBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
    edgeBottom:SetHeight(1)
    edgeBottom:SetPoint("BOTTOMLEFT", 2, 2)
    edgeBottom:SetPoint("BOTTOMRIGHT", -2, 2)
    edgeBottom:SetVertexColor(0.06, 0.05, 0.03, 0.95)

    local edgeLeft = border:CreateTexture(nil, "OVERLAY")
    edgeLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
    edgeLeft:SetWidth(1)
    edgeLeft:SetPoint("TOPLEFT", 2, -2)
    edgeLeft:SetPoint("BOTTOMLEFT", 2, 2)
    edgeLeft:SetVertexColor(0.90, 0.78, 0.35, 0.28)

    local edgeRight = border:CreateTexture(nil, "OVERLAY")
    edgeRight:SetTexture("Interface\\Buttons\\WHITE8x8")
    edgeRight:SetWidth(1)
    edgeRight:SetPoint("TOPRIGHT", -2, -2)
    edgeRight:SetPoint("BOTTOMRIGHT", -2, 2)
    edgeRight:SetVertexColor(0.90, 0.78, 0.35, 0.28)

    -- Race-specific background textures
    dr.backgroundTextures = {}
    local bgKeys = "human,nightelf,dwarf,gnome,draenei,orc,scourge,tauren,troll,bloodelf,deathknight,highelf"
    for s in bgKeys:gmatch("%w+") do
        dr.backgroundTextures[s] = dr:CreateTexture(nil, "BACKGROUND")
        dr.backgroundTextures[s]:SetTexture("Interface\\AddOns\\Transmorpher\\images\\"..s)
        dr.backgroundTextures[s]:SetAllPoints()
        dr.backgroundTextures[s]:Hide()
    end
    dr.backgroundTextures["color"] = dr:CreateTexture(nil, "BACKGROUND")
    dr.backgroundTextures["color"]:SetAllPoints()
    dr.backgroundTextures["color"]:SetTexture(1, 1, 1)
    dr.backgroundTextures["color"]:Hide()

    local raceToBgKey = {
        Human="human", NightElf="nightelf", Dwarf="dwarf", Gnome="gnome",
        Draenei="draenei", Orc="orc", Scourge="scourge", Tauren="tauren",
        Troll="troll", BloodElf="bloodelf",
    }

    function dr:ShowRaceBackground()
        for _, tex in pairs(self.backgroundTextures) do tex:Hide() end
        local settings = ns.GetSettings()
        local realmData = settings.dressingRoomBackgroundTexture[GetRealmName()]
        local bgKey = realmData and realmData[UnitName("player")]
        if bgKey == "DEATHKNIGHT" then
            bgKey = "deathknight"
        else
            bgKey = raceToBgKey[bgKey] or raceToBgKey[raceFileName] or "human"
        end
        if self.backgroundTextures[bgKey] then
            self.backgroundTextures[bgKey]:Show()
            self.backgroundTextures[bgKey]:SetAlpha(0.8)
        end
    end

    dr:HookScript("OnShow", function(self) self:ShowRaceBackground() end)

    local tip = dr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tip:SetPoint("BOTTOM", dr, "TOP", 0, 6)
    tip:SetWidth(dr:GetWidth())
    tip:SetJustifyH("CENTER"); tip:SetJustifyV("BOTTOM")
    tip:SetText("\124cffC8AA6ELeft Mouse:\124r rotate  |  \124cffC8AA6ERight Mouse:\124r pan\124n\124cffC8AA6EWheel\124r or \124cffC8AA6EAlt + Right Mouse:\124r zoom")
    tip:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    tip:SetTextColor(0.65, 0.60, 0.50, 0.85)
    tip:SetShadowColor(0, 0, 0, 1)
    tip:SetShadowOffset(1, -1)

    local defaultLight = {1, 0, 0, 1, 0, 1, 0.7, 0.7, 0.7, 1, 0.8, 0.8, 0.64}
    local shadowformLight = {1, 0, 0, 1, 0, 1, 0.16, 0, 0.23, 0}
    dr.shadowformEnabled = false

    dr.EnableShadowform = function(self)
        self:SetLight(unpack(shadowformLight))
        self:SetModelAlpha(0.75)
        self.shadowformEnabled = true
    end

    dr.DisableShadowform = function(self)
        self:SetLight(unpack(defaultLight))
        self:SetModelAlpha(1)
        self.shadowformEnabled = false
    end
end
