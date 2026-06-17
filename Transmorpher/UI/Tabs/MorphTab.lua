local addon, ns = ...

-- ============================================================
-- MORPH TAB — Race morph, custom Display ID search, scale, favorites
-- ============================================================

local mainFrame = ns.mainFrame

-- UpdatePreviewModel: refresh dressing room after morph change
do
    local f = CreateFrame("Frame")
    f:Hide()
    f.timer = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        self.timer = self.timer - elapsed
        if self.timer > 0 then return end
        self:Hide()
        self.timer = 0
        if mainFrame and mainFrame.dressingRoom and ns.ScheduleDressingRoomSync then
            ns.ScheduleDressingRoomSync(0.01)
        elseif mainFrame and mainFrame.dressingRoom then
            mainFrame.dressingRoom:SetUnit("player")
            if mainFrame.dressingRoom.ShowLive then mainFrame.dressingRoom:ShowLive() end
        end
    end)
    ns.UpdatePreviewModel = function()
        f.timer = 0.08
        f:Show()
    end
end
-- Alias for internal usage
local UpdatePreviewModel = ns.UpdatePreviewModel

do
    local actualMorphTab = mainFrame.tabs.morph
    local LayoutMorphDynamic
    local scrollFrame = CreateFrame("ScrollFrame", "$parentScrollFrame", actualMorphTab, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, -4); scrollFrame:SetPoint("BOTTOMRIGHT", -28, 4)

    local morphTab = CreateFrame("Frame", "$parentContent", scrollFrame)
    morphTab:SetSize(1, 1320)
    scrollFrame:SetScrollChild(morphTab)
    scrollFrame:SetScript("OnSizeChanged", function(self, w)
        morphTab:SetWidth(math.max(1, (w or 0) - 4))
        if LayoutMorphDynamic then LayoutMorphDynamic() end
    end)

    local yOff = -16

    -- Title
    local titleText = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", 12, yOff); titleText:SetText("|cffF5C842Character Morph|r"); yOff = yOff - 24
    local subtitleText = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("TOPLEFT", 12, yOff); subtitleText:SetText("|cff998866Change your character model. Client-side only.|r"); yOff = yOff - 24

    -- ============================================================
    -- QUICK ACTIONS & VIEW (Enhancements feature pack)
    -- ============================================================
    local function MakeTip(btn, title, body)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(title, 1, 0.82, 0)
            if body then GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true) end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local qaLabel = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    qaLabel:SetPoint("TOPLEFT", 10, yOff); qaLabel:SetText("|cffF5C842Quick Actions|r"); yOff = yOff - 20

    local btnRandom = ns.CreateGoldenButton("$parentBtnRandomMorph", morphTab)
    btnRandom:SetSize(108, 22); btnRandom:SetPoint("TOPLEFT", 12, yOff); btnRandom:SetText("|cffF5C842Random|r")
    btnRandom:SetScript("OnClick", function() if ns.Enh_RandomMorph then ns.Enh_RandomMorph() end end)
    MakeTip(btnRandom, "Random Morph", "Morph into a random creature display.")

    local btnTarget = ns.CreateGoldenButton("$parentBtnMorphTarget", morphTab)
    btnTarget:SetSize(108, 22); btnTarget:SetPoint("LEFT", btnRandom, "RIGHT", 6, 0); btnTarget:SetText("|cffF5C842Copy Target|r")
    btnTarget:SetScript("OnClick", function() if ns.Enh_MorphTarget then ns.Enh_MorphTarget("target") end end)
    MakeTip(btnTarget, "Copy Target", "Morph into your current target's appearance.")

    local btnUndo = ns.CreateGoldenButton("$parentBtnUndoMorph", morphTab)
    btnUndo:SetSize(108, 22); btnUndo:SetPoint("LEFT", btnTarget, "RIGHT", 6, 0); btnUndo:SetText("|cffF5C842Undo|r")
    btnUndo:SetScript("OnClick", function() if ns.Enh_Undo then ns.Enh_Undo() end end)
    MakeTip(btnUndo, "Undo", "Revert to the previous character morph.")
    yOff = yOff - 30

    -- ("Appearance & View" row — Toggle Helm/Cloak/Screenshot — and the Camera FOV
    -- slider were removed from here. FOV now lives in Misc > Atmosphere. Helm/Cloak
    -- toggles are available via the per-slot eye buttons; screenshot via the game key.)

    local qaSep = morphTab:CreateTexture(nil, "ARTWORK")
    qaSep:SetHeight(1); qaSep:SetPoint("TOPLEFT", 12, yOff); qaSep:SetPoint("TOPRIGHT", -20, yOff); qaSep:SetTexture(1, 1, 1, 0.08)
    yOff = yOff - 10

    -- Race Display IDs (from Constants.lua)
    local raceDisplayIds = ns.raceDisplayIds
    local raceOrder = ns.raceOrder

    -- Race Morph section
    local raceLabel = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    raceLabel:SetPoint("TOPLEFT", 10, yOff); raceLabel:SetText("|cffF5C842Race Morph|r"); yOff = yOff - 20

    local btnWidth, btnHeight = 120, 22
    local col = 0

    for i, raceName in ipairs(raceOrder) do
        local ids = raceDisplayIds[raceName]
        local safe = raceName:gsub("%s+", "")
        for _, gender in ipairs({2, 3}) do
            local gLabel = gender == 2 and " M" or " F"
            local btn = ns.CreateGoldenButton("$parentRace"..safe..(gender==2 and "M" or "F"), morphTab)
            btn:SetSize(btnWidth, btnHeight)
            local xPos = 10 + col * (btnWidth + 5)
            btn:SetPoint("TOPLEFT", xPos, yOff - (math.ceil(i/2) - 1) * (btnHeight + 3))
            btn:SetText(raceName..gLabel)
            btn:SetScript("OnClick", function()
                if ns.IsMorpherReady() then
                    local id = ids[gender]
                    ns.SendMorphCommand("MORPH:"..id)
                    if TransmorpherCharacterState then TransmorpherCharacterState.Morph = id end
                    UpdatePreviewModel(); ns.UpdateSpecialSlots()
                    SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Morphed to "..raceName..gLabel.." ("..id..")")
                end; PlaySound("gsTitleOptionOK")
            end)
            btn:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(raceName..gLabel); GameTooltip:AddLine("Display ID: "..ids[gender],1,1,1); GameTooltip:Show() end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            if gender == 2 then col = col + 1 end
        end
        if i % 2 == 0 then col = 0 else col = 2 end
    end

    yOff = yOff - math.ceil(#raceOrder / 2) * (btnHeight + 3) - 20

    -- Separator
    local sep1 = morphTab:CreateTexture(nil, "ARTWORK")
    sep1:SetTexture("Interface\\ChatFrame\\ChatFrameBackground"); sep1:SetTexCoord(0,1,0,1)
    sep1:SetPoint("TOPLEFT", 10, yOff); sep1:SetPoint("RIGHT", -10, 0); sep1:SetHeight(1)
    sep1:SetVertexColor(0.2, 0.2, 0.2, 1); yOff = yOff - 14

    -- Custom Display ID search
    local customLabel = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    customLabel:SetPoint("TOPLEFT", 10, yOff); customLabel:SetText("|cffF5C842Custom Display ID|r"); yOff = yOff - 18
    local customDesc = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    customDesc:SetPoint("TOPLEFT", 10, yOff); customDesc:SetText("|cff998866Search by creature name or enter a display ID directly:|r"); yOff = yOff - 22

    local searchContainer = CreateFrame("Frame", nil, morphTab)
    searchContainer:SetPoint("TOPLEFT", 10, yOff)
    searchContainer:SetPoint("TOPRIGHT", -120, yOff)
    searchContainer:SetHeight(28)
    searchContainer:SetBackdrop({
        bgFile="Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile="Interface\\Buttons\\WHITE8X8",
        tile=false, tileSize=0, edgeSize=1,
        insets={left=1,right=1,top=1,bottom=1}
    })
    searchContainer:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    searchContainer:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local searchIcon = searchContainer:CreateTexture(nil, "OVERLAY")
    searchIcon:SetSize(14,14); searchIcon:SetPoint("LEFT", 6, 0)
    searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon"); searchIcon:SetVertexColor(0.80, 0.65, 0.22)

    local editBox = CreateFrame("EditBox", "$parentMorphIdInput", searchContainer)
    editBox:SetPoint("LEFT", searchIcon, "RIGHT", 4, 0)
    editBox:SetPoint("RIGHT", -24, 0)
    editBox:SetHeight(18)
    editBox:SetAutoFocus(false); editBox:SetMaxLetters(40)
    editBox:SetFont("Fonts\\FRIZQT__.TTF", 11); editBox:SetTextColor(0.95, 0.88, 0.65)

    local editHint = editBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    editHint:SetPoint("LEFT", 2, 0); editHint:SetText("Name or display ID...")

    local editClear = CreateFrame("Button", nil, searchContainer)
    editClear:SetSize(14,14); editClear:SetPoint("RIGHT", -4, 0)
    editClear:SetNormalTexture("Interface\\FriendsFrame\\ClearBroadcastIcon"); editClear:SetAlpha(0.5); editClear:Hide()
    editClear:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    editClear:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)

    local selectedSearchID, selectedSearchName = nil, nil

    -- Search results dropdown
    local searchDropBg = CreateFrame("Frame", "$parentMorphSearchDrop", actualMorphTab)
    searchDropBg:SetPoint("TOPLEFT", searchContainer, "BOTTOMLEFT", 0, 2)
    searchDropBg:SetPoint("TOPRIGHT", searchContainer, "BOTTOMRIGHT", 0, 2)
    searchDropBg:SetHeight(1)
    searchDropBg:SetBackdrop({
        bgFile="Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile="Interface\\Buttons\\WHITE8X8",
        tile=false, tileSize=0, edgeSize=1,
        insets={left=1,right=1,top=1,bottom=1}
    })
    searchDropBg:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
    searchDropBg:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    searchDropBg:SetFrameStrata("DIALOG"); searchDropBg:Hide()

    editBox:SetScript("OnEscapePressed", function(self) searchDropBg:Hide(); self:ClearFocus() end)
    editBox:SetScript("OnEditFocusGained", function() editHint:Hide() end)
    local editFocusTimer = CreateFrame("Frame"); editFocusTimer:Hide()
    editBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then editHint:Show(); editClear:Hide() end
        editFocusTimer.elapsed = 0
        editFocusTimer:SetScript("OnUpdate", function(f, dt) f.elapsed = (f.elapsed or 0) + dt
            if f.elapsed >= 0.2 then f:Hide(); if not editBox:HasFocus() then searchDropBg:Hide() end end
        end)
        editFocusTimer:Show()
    end)
    editClear:SetScript("OnClick", function()
        editBox:SetText(""); editBox:ClearFocus(); editHint:Show(); editClear:Hide()
        searchDropBg:Hide(); selectedSearchID = nil; selectedSearchName = nil
    end)

    local btnApplyCustom = ns.CreateGoldenButton("$parentBtnApplyCustom", morphTab)
    btnApplyCustom:SetSize(90, 22); btnApplyCustom:SetPoint("LEFT", searchContainer, "RIGHT", 8, 0)
    btnApplyCustom:SetText("|cffF5C842Apply|r")

    local searchDropScroll = CreateFrame("ScrollFrame", "$parentMorphSearchDropScroll", searchDropBg, "UIPanelScrollFrameTemplate")
    searchDropScroll:SetPoint("TOPLEFT", 4, -4); searchDropScroll:SetPoint("BOTTOMRIGHT", -22, 4)
    local searchDropContent = CreateFrame("Frame", "$parentMorphSearchDropContent", searchDropScroll)
    searchDropContent:SetSize(searchDropScroll:GetWidth(), 1); searchDropScroll:SetScrollChild(searchDropContent)
    searchDropScroll:SetScript("OnSizeChanged", function(self, w)
        searchDropContent:SetWidth(math.max(1, (w or 0) - 4))
    end)

    local SEARCH_ROW_H, MAX_SEARCH_ROWS = 20, 10
    local searchResultButtons = {}

    -- Sorted creature list for search
    local morphCreatureSorted = nil
    local function GetMorphCreatureSorted()
        if morphCreatureSorted then return morphCreatureSorted end
        morphCreatureSorted = {}
        local db = ns.creatureDisplayDB
        if not db then return morphCreatureSorted end
        for did, name in pairs(db) do table.insert(morphCreatureSorted, {did=did, name=name, nameLower=name:lower()}) end
        table.sort(morphCreatureSorted, function(a,b) return a.name < b.name end)
        return morphCreatureSorted
    end

    local function ShowSearchResults(query)
        for _, b in ipairs(searchResultButtons) do b:Hide() end
        searchResultButtons = {}; selectedSearchID = nil; selectedSearchName = nil
        if not query or #query < 2 then searchDropBg:Hide(); return end
        local q = query:lower(); local results = {}
        local sorted = GetMorphCreatureSorted(); local count = 0
        local isNum = tonumber(query) ~= nil
        for _, entry in ipairs(sorted) do
            local match = isNum and tostring(entry.did):find(q,1,true) or (not isNum and entry.nameLower:find(q,1,true))
            if match then table.insert(results, entry); count = count + 1; if count >= MAX_SEARCH_ROWS * 5 then break end end
        end
        if #results == 0 then searchDropBg:Hide(); return end
        searchDropBg:SetHeight(math.min(#results, MAX_SEARCH_ROWS) * (SEARCH_ROW_H+1) + 10); searchDropBg:Show()
        local bY = 0
        for idx, entry in ipairs(results) do
            local row = CreateFrame("Button", nil, searchDropContent)
            row:SetSize(searchDropContent:GetWidth()-4, SEARCH_ROW_H); row:SetPoint("TOPLEFT", 2, -bY)
            local rowBg = row:CreateTexture(nil, "BACKGROUND"); rowBg:SetAllPoints()
            rowBg:SetTexture(idx%2==0 and 1 or 0, idx%2==0 and 1 or 0, idx%2==0 and 1 or 0, idx%2==0 and 0.03 or 0)
            local ns_ = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            ns_:SetPoint("LEFT", 6, 0); ns_:SetText("|cffffd700"..entry.name.."|r"); ns_:SetWidth(230); ns_:SetJustifyH("LEFT")
            local is = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            is:SetPoint("RIGHT", -6, 0); is:SetText("|cff888888"..entry.did.."|r")
            row:SetScript("OnClick", function()
                selectedSearchID = entry.did; selectedSearchName = entry.name
                editBox:SetText(entry.name.." ("..entry.did..")"); editBox:SetCursorPosition(0)
                searchDropBg:Hide(); editBox:ClearFocus()
            end)
            row:SetScript("OnEnter", function() rowBg:SetTexture(0.6,0.48,0.15,0.25) end)
            row:SetScript("OnLeave", function() rowBg:SetTexture(idx%2==0 and 1 or 0, idx%2==0 and 1 or 0, idx%2==0 and 1 or 0, idx%2==0 and 0.03 or 0) end)
            table.insert(searchResultButtons, row); bY = bY + SEARCH_ROW_H + 1
        end
        searchDropContent:SetHeight(math.max(1, bY))
    end

    local morphSearchTimer = CreateFrame("Frame"); morphSearchTimer:Hide(); morphSearchTimer.elapsed = 0
    morphSearchTimer:SetScript("OnUpdate", function(self, dt) self.elapsed = self.elapsed + dt
        if self.elapsed >= 0.3 then self:Hide(); local t = editBox:GetText(); if not t:find("%(", 1, true) then ShowSearchResults(t) end end
    end)
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then selectedSearchID = nil; selectedSearchName = nil; morphSearchTimer.elapsed = 0; morphSearchTimer:Show()
            if self:GetText() ~= "" then editClear:Show() else editClear:Hide() end end
    end)

    -- Apply morph (from search result or numeric ID)
    local function ApplyMorphFromInput()
        if selectedSearchID then
            if ns.IsMorpherReady() then
                ns.SendMorphCommand("MORPH:"..selectedSearchID)
                if TransmorpherCharacterState then TransmorpherCharacterState.Morph = selectedSearchID end
                UpdatePreviewModel(); ns.UpdateSpecialSlots()
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Morphed to "..(selectedSearchName or "creature").." ("..selectedSearchID..")")
                PlaySound("gsTitleOptionOK")
            end
        else
            local text = editBox:GetText()
            local id = tonumber(text:match("%((%d+)%)")) or tonumber(text)
            if id and id > 0 and ns.IsMorpherReady() then
                ns.SendMorphCommand("MORPH:"..id)
                if TransmorpherCharacterState then TransmorpherCharacterState.Morph = id end
                UpdatePreviewModel(); ns.UpdateSpecialSlots()
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Morphed to display ID "..id)
                PlaySound("gsTitleOptionOK")
            end
        end
        searchDropBg:Hide()
    end

    editBox:SetScript("OnEnterPressed", function(self) ApplyMorphFromInput(); self:ClearFocus() end)
    btnApplyCustom:SetScript("OnClick", ApplyMorphFromInput)

    yOff = yOff - 30

    -- Scale section
    local sizeLabel = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sizeLabel:SetPoint("TOPLEFT", 10, yOff); sizeLabel:SetText("|cffF5C842Character Size|r"); yOff = yOff - 20

    local sizeEditBox = CreateFrame("EditBox", "$parentMorphSizeInput", morphTab, "InputBoxTemplate")
    sizeEditBox:SetSize(60, 20); sizeEditBox:SetPoint("TOPLEFT", 15, yOff)
    sizeEditBox:SetAutoFocus(false); sizeEditBox:SetMaxLetters(4); sizeEditBox:SetText("1.0")
    sizeEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local btnApplySize = ns.CreateGoldenButton("$parentBtnApplySize", morphTab)
    btnApplySize:SetSize(90, 22); btnApplySize:SetPoint("LEFT", sizeEditBox, "RIGHT", 10, 0)
    btnApplySize:SetText("|cffF5C842Apply Size|r")
    btnApplySize:SetScript("OnClick", function()
        local scale = tonumber(sizeEditBox:GetText())
        if scale and scale > 0.1 and scale < 10.0 and ns.IsMorpherReady() then
            ns.SendMorphCommand("SCALE:"..scale)
            if TransmorpherCharacterState then TransmorpherCharacterState.MorphScale = scale end
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Scaled character to "..scale)
            PlaySound("gsTitleOptionOK")
        end
    end)
    yOff = yOff - 40

    -- Separator
    local favSep = morphTab:CreateTexture(nil, "ARTWORK")
    favSep:SetTexture("Interface\\ChatFrame\\ChatFrameBackground"); favSep:SetTexCoord(0,1,0,1)
    favSep:SetPoint("TOPLEFT", 10, yOff); favSep:SetPoint("RIGHT", -10, 0); favSep:SetHeight(1)
    favSep:SetVertexColor(0.2, 0.2, 0.2, 1); yOff = yOff - 14

    -- Saved Morphs (Favorites)
    local favLabel = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    favLabel:SetPoint("TOPLEFT", 10, yOff); favLabel:SetText("|cffF5C842Saved Morphs|r"); yOff = yOff - 18
    local favDesc = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    favDesc:SetPoint("TOPLEFT", 10, yOff); favDesc:SetText("|cff998866Save display IDs with a name for quick access.|r"); yOff = yOff - 18

    local favNameInput = CreateFrame("EditBox", "$parentFavNameInput", morphTab, "InputBoxTemplate")
    favNameInput:SetSize(130, 20); favNameInput:SetPoint("TOPLEFT", 15, yOff)
    favNameInput:SetAutoFocus(false); favNameInput:SetMaxLetters(24)
    favNameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local favNameHint = favNameInput:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    favNameHint:SetPoint("LEFT", 4, 0); favNameHint:SetText("Name")
    favNameInput:SetScript("OnEditFocusGained", function() favNameHint:Hide() end)
    favNameInput:SetScript("OnEditFocusLost", function(self) if self:GetText() == "" then favNameHint:Show() end end)

    local favIdInput = CreateFrame("EditBox", "$parentFavIdInput", morphTab, "InputBoxTemplate")
    favIdInput:SetSize(70, 20); favIdInput:SetPoint("LEFT", favNameInput, "RIGHT", 8, 0)
    favIdInput:SetAutoFocus(false); favIdInput:SetNumeric(true); favIdInput:SetMaxLetters(6)
    favIdInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local favIdHint = favIdInput:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    favIdHint:SetPoint("LEFT", 4, 0); favIdHint:SetText("ID")
    favIdInput:SetScript("OnEditFocusGained", function() favIdHint:Hide() end)
    favIdInput:SetScript("OnEditFocusLost", function(self) if self:GetText() == "" then favIdHint:Show() end end)

    local btnFavSave = ns.CreateGoldenButton("$parentBtnFavSave", morphTab)
    btnFavSave:SetSize(60, 20); btnFavSave:SetPoint("LEFT", favIdInput, "RIGHT", 8, 0); btnFavSave:SetText("|cffF5C842Save|r")
    local btnFavRemove = ns.CreateGoldenButton("$parentBtnFavRemove", morphTab)
    btnFavRemove:SetSize(70, 20); btnFavRemove:SetPoint("LEFT", btnFavSave, "RIGHT", 4, 0); btnFavRemove:SetText("Remove"); btnFavRemove:Disable()
    yOff = yOff - 26

    local favListBg = CreateFrame("Frame", "$parentFavListBg", morphTab)
    favListBg:SetPoint("TOPLEFT", 10, yOff)
    favListBg:SetPoint("TOPRIGHT", -10, yOff)
    favListBg:SetHeight(100)
    favListBg:SetBackdrop({
        bgFile="Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile="Interface\\Buttons\\WHITE8X8",
        tile=false, tileSize=0, edgeSize=1,
        insets={left=1,right=1,top=1,bottom=1}
    })
    favListBg:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    favListBg:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

    local favScroll = CreateFrame("ScrollFrame", "$parentFavScroll", favListBg, "UIPanelScrollFrameTemplate")
    favScroll:SetPoint("TOPLEFT", 4, -4); favScroll:SetPoint("BOTTOMRIGHT", -22, 4)
    local favContent = CreateFrame("Frame", "$parentFavContent", favScroll)
    favContent:SetSize(favScroll:GetWidth(), 1); favScroll:SetScrollChild(favContent)
    favScroll:SetScript("OnSizeChanged", function(self, w)
        favContent:SetWidth(math.max(1, (w or 0) - 4))
    end)

    local favButtons, favSelectedIdx = {}, nil

    local function BuildFavButtons()
        for _, b in ipairs(favButtons) do b:Hide() end
        favButtons = {}; favSelectedIdx = nil; btnFavRemove:Disable()
        if not _G["TransmorpherMorphFavorites"] then _G["TransmorpherMorphFavorites"] = {} end
        local bY = 0
        for idx, fav in ipairs(_G["TransmorpherMorphFavorites"]) do
            local row = CreateFrame("Button", nil, favContent)
            row:SetSize(favContent:GetWidth()-4, 20); row:SetPoint("TOPLEFT", 2, -bY)
            local rowBg = row:CreateTexture(nil, "BACKGROUND"); rowBg:SetAllPoints(); rowBg:SetTexture(0,0,0,0)
            local nStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nStr:SetPoint("LEFT", 4, 0); nStr:SetText("|cffffd700"..fav.name.."|r"); nStr:SetWidth(200); nStr:SetJustifyH("LEFT")
            local iStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            iStr:SetPoint("LEFT", nStr, "RIGHT", 8, 0); iStr:SetText("|cff8a7d6aID: "..fav.id.."|r")
            local useBtn = ns.CreateGoldenButton("TransmorpherFavUseBtn"..idx, row)
            useBtn:SetSize(50, 18); useBtn:SetPoint("RIGHT", -2, 0); useBtn:SetText("|cffF5C842Use|r")
            useBtn:SetScript("OnClick", function()
                if ns.IsMorpherReady() then
                    local id = fav.id
                    ns.SendMorphCommand("MORPH:"..id)
                    if TransmorpherCharacterState then TransmorpherCharacterState.Morph = id end
                    UpdatePreviewModel(); ns.UpdateSpecialSlots()
                    SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Morphed to "..fav.name.." ("..id..")")
                end; PlaySound("gsTitleOptionOK")
            end)
            row:SetScript("OnClick", function()
                if favSelectedIdx and favButtons[favSelectedIdx] then favButtons[favSelectedIdx].bg:SetTexture(0,0,0,0) end
                favSelectedIdx = idx; rowBg:SetTexture(0.6, 0.48, 0.15, 0.3); btnFavRemove:Enable()
            end)
            row:SetScript("OnEnter", function() if favSelectedIdx ~= idx then rowBg:SetTexture(1,1,1,0.05) end end)
            row:SetScript("OnLeave", function() if favSelectedIdx ~= idx then rowBg:SetTexture(0,0,0,0) end end)
            row.bg = rowBg; table.insert(favButtons, row); bY = bY + 21
        end
        favContent:SetHeight(math.max(1, bY))
    end

    btnFavSave:SetScript("OnClick", function()
        local name = favNameInput:GetText(); local id = tonumber(favIdInput:GetText())
        if not name or name == "" then return end; if not id or id <= 0 then return end
        if not _G["TransmorpherMorphFavorites"] then _G["TransmorpherMorphFavorites"] = {} end
        table.insert(_G["TransmorpherMorphFavorites"], {name=name, id=id})
        favNameInput:SetText(""); favIdInput:SetText(""); favNameHint:Show(); favIdHint:Show()
        BuildFavButtons()
        SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Saved morph '"..name.."' (ID: "..id..")")
        PlaySound("gsTitleOptionOK")
    end)
    btnFavRemove:SetScript("OnClick", function()
        if favSelectedIdx and _G["TransmorpherMorphFavorites"] then
            local fav = _G["TransmorpherMorphFavorites"][favSelectedIdx]
            if fav then table.remove(_G["TransmorpherMorphFavorites"], favSelectedIdx)
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Removed '"..fav.name.."'") end
            BuildFavButtons(); PlaySound("gsTitleOptionOK")
        end
    end)

    morphTab:HookScript("OnShow", function() BuildFavButtons() end)
    yOff = yOff - 110

    -- Separator + Popular Creatures
    local sep2 = morphTab:CreateTexture(nil, "ARTWORK")
    sep2:SetTexture("Interface\\ChatFrame\\ChatFrameBackground"); sep2:SetTexCoord(0,1,0,1)
    sep2:SetPoint("TOPLEFT", 10, yOff); sep2:SetPoint("RIGHT", -10, 0); sep2:SetHeight(1)
    sep2:SetVertexColor(0.2, 0.2, 0.2, 1); yOff = yOff - 14

    local infoLabel = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoLabel:SetPoint("TOPLEFT", 10, yOff); yOff = yOff - 16

    local creaturesLabel = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    creaturesLabel:SetPoint("TOPLEFT", 10, yOff); creaturesLabel:SetText("|cffF5C842Popular Creatures|r"); yOff = yOff - 20

    local popularCreatures = ns.popularCreatures

    local popularStartY = yOff
    local popularButtons = {}
    col = 0; local creatureRow = 0
    for i, creature in ipairs(popularCreatures) do
        local btn = ns.CreateGoldenButton("$parentCreature"..i, morphTab)
        btn:SetSize(btnWidth, btnHeight)
        btn:SetPoint("TOPLEFT", 10 + col * (btnWidth+5), yOff - creatureRow * (btnHeight+3))
        btn:SetText(creature.name)
        btn:SetScript("OnClick", function()
            if ns.IsMorpherReady() then
                local id = creature.id
                ns.SendMorphCommand("MORPH:"..id)
                if TransmorpherCharacterState then TransmorpherCharacterState.Morph = id end
                UpdatePreviewModel(); ns.UpdateSpecialSlots()
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Morphed to "..creature.name.." ("..id..")")
            end; PlaySound("gsTitleOptionOK")
        end)
        btn:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(creature.name); GameTooltip:AddLine("Display ID: "..creature.id,1,1,1); GameTooltip:Show() end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        popularButtons[i] = btn
        col = col + 1; if col >= 4 then col = 0; creatureRow = creatureRow + 1 end
    end
    yOff = yOff - math.ceil(#popularCreatures / 4) * (btnHeight+3) - 10

    -- Reset Model button
    local btnResetMorph = ns.CreateGoldenButton("$parentBtnResetModel", morphTab)
    btnResetMorph:SetSize(200, 28); btnResetMorph:SetPoint("TOPLEFT", 10, yOff)
    btnResetMorph:SetText("|cffF5C842Reset Character Model|r")
    btnResetMorph:SetScript("OnClick", function()
        if ns.IsMorpherReady() then
            ns.SendMorphCommand("MORPH:0|SCALE:0")
            if ns.Skin_ResetAll then ns.Skin_ResetAll(true) end
            if ns.Barber_Reset then ns.Barber_Reset(true) end  -- also wipe barber look + colors
            if TransmorpherCharacterState then
                TransmorpherCharacterState.Sheathe = {}
            end
            ns.SendRawMorphCommand("SHEATHE:0:-1|SHEATHE:1:-1")
            if TransmorpherCharacterState then TransmorpherCharacterState.Morph = nil; TransmorpherCharacterState.MorphScale = nil; TransmorpherCharacterState.Scale = nil end
            UpdatePreviewModel(); ns.UpdateSpecialSlots()

            if ns.BroadcastMorphState then ns.BroadcastMorphState(true) end

            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Character morph reset!")
        end; PlaySound("gsTitleOptionOK")
    end)

    morphTab:SetScript("OnShow", function() infoLabel:SetText("|cff8a7d6aDisplay info not available in stealth mode.|r") end)

    LayoutMorphDynamic = function()
        local width = morphTab:GetWidth() or 520
        local cols = math.floor((width - 20 + 5) / (btnWidth + 5))
        if cols < 4 then cols = 4 end
        if cols > 7 then cols = 7 end
        for i, btn in ipairs(popularButtons) do
            local idx = i - 1
            local r = math.floor(idx / cols)
            local c = idx - r * cols
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", 10 + c * (btnWidth + 5), popularStartY - r * (btnHeight + 3))
        end
        local rows = math.ceil(#popularButtons / cols)
        local resetY = popularStartY - rows * (btnHeight + 3) - 10
        btnResetMorph:ClearAllPoints()
        btnResetMorph:SetPoint("TOPLEFT", 10, resetY)
        morphTab:SetHeight(math.max((scrollFrame:GetHeight() or 1) + 8, -resetY + 54))
    end
    LayoutMorphDynamic()
end
