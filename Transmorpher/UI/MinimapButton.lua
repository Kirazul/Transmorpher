local addon, ns = ...

-- ============================================================
-- MINIMAP BUTTON
-- Standard radial minimap button with dragging and persistence
-- ============================================================

local function UpdateMinimapButton()
    local settings = ns.GetSettings()
    if settings.showMinimapButton then
        if not ns.MinimapButton then
            local btn = CreateFrame("Button", "TransmorpherMinimapButton", Minimap)
            ns.MinimapButton = btn
            btn:SetSize(31, 31)
            btn:SetFrameStrata("MEDIUM")
            btn:SetFrameLevel(8)
            btn:SetPoint("CENTER", -80, 20)
            btn:SetMovable(true)
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:RegisterForDrag("LeftButton")

            -- Background
            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
            bg:SetSize(52, 52)
            bg:SetPoint("TOPLEFT")

            -- Icon
            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetTexture("Interface\\Icons\\INV_Chest_Cloth_17")
            icon:SetSize(20, 20)
            icon:SetPoint("CENTER", -2, 2)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn.icon = icon

            -- Overlay (Gloss)
            local gloss = btn:CreateTexture(nil, "OVERLAY")
            gloss:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
            gloss:SetSize(52, 52)
            gloss:SetPoint("TOPLEFT")
            gloss:SetDesaturated(true)
            gloss:SetAlpha(0.3)

            -- Dragging Logic
            local function OnDragUpdate(self)
                local mx, my = Minimap:GetCenter()
                local px, py = GetCursorPosition()
                local scale = Minimap:GetEffectiveScale()
                px, py = px / scale, py / scale
                local angle = math.atan2(py - my, px - mx)
                local pos = math.deg(angle)
                
                settings.minimapPos = pos
                local radius = 80
                local x = math.cos(angle) * radius
                local y = math.sin(angle) * radius
                self:SetPoint("CENTER", Minimap, "CENTER", x, y)
            end

            btn:SetScript("OnDragStart", function(self)
                self:SetScript("OnUpdate", OnDragUpdate)
            end)
            btn:SetScript("OnDragStop", function(self)
                self:SetScript("OnUpdate", nil)
            end)

            btn:SetScript("OnClick", function(self, button)
                if button == "LeftButton" then
                    if ns.mainFrame:IsShown() then
                        ns.mainFrame:Hide()
                    else
                        ns.mainFrame:Show()
                    end
                end
            end)

            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:AddLine("|cffFFD100Transmorpher|r")
                GameTooltip:AddLine("Left-click: Toggle Window", 1, 1, 1)
                GameTooltip:AddLine("Left-click and Drag: Move", 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            -- Initial position
            if settings.minimapPos then
                local angle = math.rad(settings.minimapPos)
                local x = math.cos(angle) * 80
                local y = math.sin(angle) * 80
                btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
            end
        end
        ns.MinimapButton:Show()
    else
        if ns.MinimapButton then
            ns.MinimapButton:Hide()
        end
    end
end

ns.UpdateMinimapButton = UpdateMinimapButton

-- Initialize
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    UpdateMinimapButton()
end)
