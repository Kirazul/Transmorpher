local addon, ns = ...

-- ============================================================
-- FORMS SUB-TAB — Card-based form loadout system
-- Uses ns.orderedFormGroups + ns.formGroupDB from State.lua
-- Creature selector dialog with search, scoring, icons
-- ============================================================

function ns.InitFormsTab(parent)
    local scroll = CreateFrame("ScrollFrame", "$parentScroll", parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -10)
    scroll:SetPoint("BOTTOMRIGHT", -26, 10)

    local content = CreateFrame("Frame", "$parentContent", scroll)
    local contentWidth = math.max(560, parent:GetWidth() - 36)
    content:SetSize(contentWidth, 1)
    scroll:SetScrollChild(content)

    -- Header bar
    local header = CreateFrame("Frame", nil, content)
    header:SetPoint("TOPLEFT", 6, -6)
    header:SetPoint("TOPRIGHT", -6, -6)
    header:SetHeight(40)
    header:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    header:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    header:SetBackdropBorderColor(0.35, 0.30, 0.18, 0.9)

    local headerTitle = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerTitle:SetPoint("LEFT", 12, 0)
    headerTitle:SetTextColor(1.0, 0.84, 0.40)
    headerTitle:SetText("Form Loadouts")

    local headerDesc = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    headerDesc:SetPoint("RIGHT", -12, 0)
    headerDesc:SetTextColor(0.78, 0.78, 0.78)
    headerDesc:SetText("Assign a model to each form group")

    local slotCards = {}
    local activeGroupID = nil
    local activeCard = nil

    -- ============================================================
    -- CREATURE SELECTOR DIALOG
    -- ============================================================
    local selector = CreateFrame("Frame", "TransmorpherFormSelector", parent)
    selector:SetSize(460, 500)
    selector:SetPoint("CENTER", 0, 0)
    selector:SetFrameStrata("DIALOG")
    selector:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    selector:SetBackdropColor(0.03, 0.03, 0.03, 0.97)
    selector:SetBackdropBorderColor(0.60, 0.50, 0.20, 0.95)
    selector:EnableMouse(true)
    selector:SetMovable(true)
    selector:SetClampedToScreen(true)
    selector:Hide()

    local dragBar = CreateFrame("Frame", nil, selector)
    dragBar:SetPoint("TOPLEFT", 4, -4)
    dragBar:SetPoint("TOPRIGHT", -24, -4)
    dragBar:SetHeight(22)
    dragBar:EnableMouse(true)
    dragBar:RegisterForDrag("LeftButton")
    dragBar:SetScript("OnDragStart", function() selector:StartMoving() end)
    dragBar:SetScript("OnDragStop", function() selector:StopMovingOrSizing() end)

    local selTitle = selector:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    selTitle:SetPoint("TOPLEFT", 14, -14)
    selTitle:SetTextColor(1.0, 0.84, 0.35)
    selTitle:SetText("Select Creature")

    local selSubTitle = selector:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    selSubTitle:SetPoint("TOPLEFT", 16, -36)
    selSubTitle:SetTextColor(0.74, 0.74, 0.74)
    selSubTitle:SetText("Type a name or display ID")

    local selClose = CreateFrame("Button", nil, selector, "UIPanelCloseButton")
    selClose:SetPoint("TOPRIGHT", -4, -4)

    -- Search bar
    local searchFrame = CreateFrame("Frame", nil, selector)
    searchFrame:SetPoint("TOPLEFT", 14, -54)
    searchFrame:SetPoint("TOPRIGHT", -14, -54)
    searchFrame:SetHeight(28)
    searchFrame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    searchFrame:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    searchFrame:SetBackdropBorderColor(0.30, 0.30, 0.30, 1)

    local searchIcon = searchFrame:CreateTexture(nil, "ARTWORK")
    searchIcon:SetSize(14, 14)
    searchIcon:SetPoint("LEFT", 8, 0)
    searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    searchIcon:SetVertexColor(0.86, 0.72, 0.26)

    local searchBox = CreateFrame("EditBox", "$parentSearch", searchFrame)
    searchBox:SetPoint("TOPLEFT", searchIcon, "TOPRIGHT", 6, 2)
    searchBox:SetPoint("BOTTOMRIGHT", -26, -2)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("ChatFontNormal")
    searchBox:SetTextColor(1, 1, 1)

    local searchHint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", 2, 0)
    searchHint:SetText("Search by creature name or display ID...")

    local searchClear = CreateFrame("Button", nil, searchFrame)
    searchClear:SetSize(14, 14)
    searchClear:SetPoint("RIGHT", -6, 0)
    searchClear:SetNormalTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
    searchClear:SetAlpha(0.55)
    searchClear:Hide()

    -- Results scroll
    local resultScroll = CreateFrame("ScrollFrame", "$parentResults", selector, "UIPanelScrollFrameTemplate")
    resultScroll:SetPoint("TOPLEFT", 14, -90)
    resultScroll:SetPoint("BOTTOMRIGHT", -32, 44)

    local resultList = CreateFrame("Frame", nil, resultScroll)
    resultList:SetSize(396, 1)
    resultScroll:SetScrollChild(resultList)

    -- Bottom buttons
    local btnReset = ns.CreateGoldenButton("$parentReset", selector)
    btnReset:SetSize(120, 24)
    btnReset:SetPoint("BOTTOMLEFT", 14, 12)
    btnReset:SetText("Clear Slot")

    local btnCancel = ns.CreateGoldenButton("$parentCancel", selector)
    btnCancel:SetSize(120, 24)
    btnCancel:SetPoint("BOTTOMRIGHT", -14, 12)
    btnCancel:SetText("Close")
    btnCancel:SetScript("OnClick", function() selector:Hide() end)

    local resultButtons = {}
    local noResultsText = resultList:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    noResultsText:SetPoint("TOPLEFT", 8, -10)
    noResultsText:SetText("No creatures found")
    noResultsText:Hide()

    -- ============================================================
    -- SEARCH & RESULTS
    -- ============================================================
    local function BuildSearchToken(name, id)
        local token = (name and name:lower() or "") .. " " .. tostring(id or "")
        token = token:gsub("[%p_]+", " ")
        token = token:gsub("%s+", " ")
        return token
    end

    local function GetResultIconByName(name)
        if not name then return "Interface\\Icons\\Spell_Shadow_Charm" end
        local ln = name:lower()
        if ln:find("dragon",1,true) or ln:find("drake",1,true) then return "Interface\\Icons\\INV_Misc_Head_Dragon_01"
        elseif ln:find("demon",1,true) or ln:find("fel",1,true) then return "Interface\\Icons\\Spell_Shadow_SummonFelHunter"
        elseif ln:find("wolf",1,true) or ln:find("worg",1,true) then return "Interface\\Icons\\Ability_Hunter_Pet_Wolf"
        elseif ln:find("bear",1,true) then return "Interface\\Icons\\Ability_Racial_BearForm"
        elseif ln:find("cat",1,true) or ln:find("feline",1,true) then return "Interface\\Icons\\Ability_Druid_CatForm"
        elseif ln:find("tauren",1,true) or ln:find("taunka",1,true) then return "Interface\\Icons\\Achievement_Character_Tauren_Male"
        elseif ln:find("dwarf",1,true) then return "Interface\\Icons\\Achievement_Character_Dwarf_Male"
        elseif ln:find("vrykul",1,true) then return "Interface\\Icons\\INV_Helmet_92"
        elseif ln:find("undead",1,true) or ln:find("scourge",1,true) then return "Interface\\Icons\\Achievement_Character_Undead_Male"
        elseif ln:find("human",1,true) then return "Interface\\Icons\\Achievement_Character_Human_Male"
        elseif ln:find("orc",1,true) then return "Interface\\Icons\\Achievement_Character_Orc_Male"
        elseif ln:find("troll",1,true) then return "Interface\\Icons\\Achievement_Character_Troll_Male"
        elseif ln:find("blood elf",1,true) or ln:find("bloodelf",1,true) then return "Interface\\Icons\\Achievement_Character_Bloodelf_Male"
        end
        return "Interface\\Icons\\Spell_Shadow_Charm"
    end

    local function UpdateResults(query)
        for _, b in ipairs(resultButtons) do b:Hide() end
        local q = (query or ""):lower():gsub("^%s+",""):gsub("%s+$","")
        local qNum = tonumber(q)
        local rows = {}
        for id, name in pairs(ns.creatureDisplayDB or {}) do
            local token = BuildSearchToken(name, id)
            local score = nil
            if q == "" then
                score = 4
            elseif qNum and id == qNum then
                score = 0
            elseif name:lower() == q then
                score = 1
            elseif token:sub(1, #q) == q then
                score = 2
            elseif token:find(q, 1, true) or tostring(id):find(q, 1, true) then
                score = 3
            end
            if score then
                table.insert(rows, { id = id, name = name, score = score })
            end
        end
        table.sort(rows, function(a, b)
            if a.score ~= b.score then return a.score < b.score end
            if a.name ~= b.name then return a.name < b.name end
            return a.id < b.id
        end)

        local y = 0
        for i = 1, math.min(#rows, 120) do
            local row = rows[i]
            local btn = resultButtons[i]
            if not btn then
                btn = CreateFrame("Button", nil, resultList)
                btn:SetSize(396, 26)
                btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                btn:SetBackdrop({
                    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                    edgeFile = "Interface\\Buttons\\WHITE8X8",
                    tile = false, tileSize = 0, edgeSize = 1,
                    insets = { left = 1, right = 1, top = 1, bottom = 1 }
                })
                btn:SetBackdropColor(0.06, 0.06, 0.06, 0.8)
                btn:SetBackdropBorderColor(0.20, 0.20, 0.20, 0.9)
                btn.icon = btn:CreateTexture(nil, "ARTWORK")
                btn.icon:SetSize(18, 18)
                btn.icon:SetPoint("LEFT", 5, 0)
                btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                btn.text:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
                btn.text:SetPoint("RIGHT", -56, 0)
                btn.text:SetJustifyH("LEFT")
                btn.didText = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                btn.didText:SetPoint("RIGHT", -8, 0)
                btn.didText:SetJustifyH("RIGHT")
                btn:SetScript("OnClick", function(self)
                    if not activeGroupID then return end
                    ns.SetFormMorph(activeGroupID, self.did)
                    if activeCard then RefreshCard(activeCard) end
                    if ns.CheckFormMorphs then ns.CheckFormMorphs() end
                    selector:Hide()
                    PlaySound("gsTitleOptionOK")
                end)
                btn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(0.58, 0.45, 0.18, 1) end)
                btn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.20, 0.20, 0.20, 0.9) end)
                resultButtons[i] = btn
            end
            btn:SetPoint("TOPLEFT", 0, -y)
            btn.did = row.id
            btn.icon:SetTexture(GetResultIconByName(row.name))
            btn.text:SetText(row.name)
            btn.didText:SetText("ID " .. row.id)
            btn:Show()
            y = y + 28
        end
        noResultsText[#rows == 0 and "Show" or "Hide"](noResultsText)
        resultList:SetHeight(math.max(1, y))
        selSubTitle:SetText(#rows .. " result(s)")
    end

    -- Search event wiring
    searchBox:SetScript("OnEditFocusGained", function() searchHint:Hide() end)
    searchBox:SetScript("OnEditFocusLost", function(self) if self:GetText() == "" then searchHint:Show() end end)
    searchBox:SetScript("OnTextChanged", function(self)
        local txt = self:GetText()
        if txt == "" then searchHint:Show(); searchClear:Hide() else searchHint:Hide(); searchClear:Show() end
        UpdateResults(txt)
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); self:SetText("") end)
    searchClear:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    searchClear:SetScript("OnLeave", function(self) self:SetAlpha(0.55) end)
    searchClear:SetScript("OnClick", function() searchBox:SetText(""); searchBox:SetFocus() end)

    btnReset:SetScript("OnClick", function()
        if not activeGroupID then return end
        ns.SetFormMorph(activeGroupID, nil)
        if activeCard then RefreshCard(activeCard) end
        if ns.CheckFormMorphs then ns.CheckFormMorphs() end
        selector:Hide()
        PlaySound("gsTitleOptionOK")
    end)

    -- ============================================================
    -- CARD HELPERS
    -- ============================================================
    function RefreshCard(card)
        local mid = ns.GetFormMorph(card.groupID)
        if mid then
            local mName = ns.creatureDisplayDB and ns.creatureDisplayDB[mid] or ("Display ID " .. tostring(mid))
            card.assignText:SetText(mName)
            card.assignText:SetTextColor(0.95, 0.90, 0.62)
            card.stateText:SetText("Assigned \194\183 ID " .. tostring(mid))
            card.stateText:SetTextColor(0.35, 1.0, 0.55)
            card.actionBtn:SetText("Change")
            card.resetBtn:Show()
            card.glow:Show()
            if card.iconBorder then ns.ShowMorphGlow(card.iconBorder, "gold") end
            card:SetBackdropBorderColor(0.78, 0.62, 0.22, 0.9)
        else
            card.assignText:SetText("No creature assigned")
            card.assignText:SetTextColor(0.62, 0.62, 0.62)
            card.stateText:SetText("Empty")
            card.stateText:SetTextColor(0.68, 0.68, 0.68)
            card.actionBtn:SetText("Select")
            card.resetBtn:Hide()
            card.glow:Hide()
            if card.iconBorder then ns.HideMorphGlow(card.iconBorder) end
            card:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)
        end
    end

    local function RefreshAllCards()
        for _, card in ipairs(slotCards) do RefreshCard(card) end
    end

    local function OpenSelector(card)
        activeGroupID = card.groupID
        activeCard = card
        local data = ns.formGroupDB[card.groupID]
        selTitle:SetText(data and ("Select Creature - " .. data.name) or "Select Creature")
        selSubTitle:SetText("Type a name or display ID")
        searchBox:SetText("")
        searchHint:Show()
        selector:Show()
        selector:Raise()
    end

    -- ============================================================
    -- BUILD CARDS
    -- ============================================================
    -- Detect known form groups from shapeshift bar (classless-compatible)
    local _, playerClass = UnitClass("player")
    local classFormGroups = {}
    local knownGroups = {}
    local numForms = GetNumShapeshiftForms() or 0
    for i = 1, numForms do
        local _, formName = GetShapeshiftFormInfo(i)
        if formName then
            for sid, group in pairs(ns.spellToFormGroup) do
                local sName = GetSpellInfo(sid)
                if sName and sName == formName then
                    knownGroups[group] = true
                end
            end
        end
    end
    for _, groupID in ipairs(ns.orderedFormGroups) do
        local show = knownGroups[groupID]
        if not show then
            -- Class-based fallback for buff-based forms not on the shapeshift bar
            if groupID == "Bear" or groupID == "Cat" or groupID == "Moonkin" or groupID == "Tree"
               or groupID == "Travel" or groupID == "Aquatic" or groupID == "Flight" then
                show = (playerClass == "DRUID")
            elseif groupID == "GhostWolf" then
                show = (playerClass == "SHAMAN")
            elseif groupID == "Metamorphosis" then
                show = (playerClass == "WARLOCK")
            elseif groupID == "Shadowform" then
                show = (playerClass == "PRIEST")
            elseif groupID:find("^DBW_") then
                show = true -- Anyone can equip DBW
            end
        end
        if show and ns.formGroupDB[groupID] then
            table.insert(classFormGroups, groupID)
        end
    end

    local cols = contentWidth >= 740 and 3 or 2
    local gapX, gapY = 10, 10
    local cardWidth = math.floor((contentWidth - 12 - ((cols - 1) * gapX)) / cols)
    local cardHeight = 92
    local startY = -56
    local row, col = 0, 0

    for _, groupID in ipairs(classFormGroups) do
        local data = ns.formGroupDB[groupID]
        if data then
            local card = CreateFrame("Button", nil, content)
            card.groupID = groupID
            card:SetSize(cardWidth, cardHeight)
            card:SetPoint("TOPLEFT", 6 + col * (cardWidth + gapX), startY - row * (cardHeight + gapY))
            card:SetBackdrop({
                bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false, tileSize = 0, edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 }
            })
            card:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
            card:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)

            -- Subtle glow background for assigned cards
            local glow = card:CreateTexture(nil, "BACKGROUND")
            glow:SetPoint("TOPLEFT", 1, -1)
            glow:SetPoint("BOTTOMRIGHT", -1, 1)
            glow:SetTexture("Interface\\Buttons\\WHITE8X8")
            glow:SetVertexColor(0.50, 0.35, 0.08, 0.22)
            glow:Hide()
            card.glow = glow

            -- Icon with border frame
            local iconBorder = CreateFrame("Frame", nil, card)
            iconBorder:SetPoint("TOPLEFT", 10, -10)
            iconBorder:SetSize(44, 44)
            iconBorder:SetBackdrop({
                bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false, tileSize = 0, edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 }
            })
            iconBorder:SetBackdropColor(0.07, 0.07, 0.07, 1)
            iconBorder:SetBackdropBorderColor(0.35, 0.30, 0.18, 0.9)

            local icon = iconBorder:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT", 2, -2)
            icon:SetPoint("BOTTOMRIGHT", -2, 2)
            icon:SetTexture(data.icon)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            -- Text labels
            local nameText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameText:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 10, -2)
            nameText:SetPoint("RIGHT", card, "RIGHT", -90, 0)
            nameText:SetJustifyH("LEFT")
            nameText:SetWordWrap(false)
            nameText:SetTextColor(0.96, 0.90, 0.72)
            nameText:SetText(data.name)

            local stateText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            stateText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -3)
            stateText:SetPoint("RIGHT", nameText, "RIGHT", 0, 0)
            stateText:SetJustifyH("LEFT")
            stateText:SetWordWrap(false)
            card.stateText = stateText

            local assignText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            assignText:SetPoint("TOPLEFT", stateText, "BOTTOMLEFT", 0, -3)
            assignText:SetPoint("RIGHT", nameText, "RIGHT", 0, 0)
            assignText:SetJustifyH("LEFT")
            assignText:SetWordWrap(false)
            assignText:SetHeight(14)
            card.assignText = assignText

            -- Action button (Select / Change)
            local actionBtn = ns.CreateGoldenButton(nil, card)
            actionBtn:SetSize(74, 23)
            actionBtn:SetPoint("TOPRIGHT", -8, -9)
            card.actionBtn = actionBtn

            -- Reset button
            local resetBtn = CreateFrame("Button", nil, card)
            resetBtn:SetSize(74, 18)
            resetBtn:SetPoint("TOPRIGHT", -8, -36)
            resetBtn:SetBackdrop({
                bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false, tileSize = 0, edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 }
            })
            resetBtn:SetBackdropColor(0.16, 0.16, 0.16, 0.95)
            resetBtn:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.95)
            local resetBg = resetBtn:CreateTexture(nil, "BACKGROUND")
            resetBg:SetAllPoints()
            resetBg:SetTexture(0.14, 0.14, 0.14, 0.92)
            local resetLabel = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            resetLabel:SetPoint("CENTER")
            resetLabel:SetText("Reset")
            resetLabel:SetTextColor(0.86, 0.86, 0.86)
            card.resetBtn = resetBtn

            resetBtn:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(0.72, 0.72, 0.72, 1)
                resetBg:SetTexture(0.20, 0.20, 0.20, 0.95)
            end)
            resetBtn:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.95)
                resetBg:SetTexture(0.14, 0.14, 0.14, 0.92)
            end)

            -- Click handlers
            actionBtn:SetScript("OnClick", function()
                OpenSelector(card)
                UpdateResults("")
            end)
            resetBtn:SetScript("OnClick", function()
                ns.SetFormMorph(groupID, nil)
                RefreshCard(card)
                if ns.CheckFormMorphs then ns.CheckFormMorphs() end
                PlaySound("gsTitleOptionOK")
            end)
            card:SetScript("OnClick", function()
                OpenSelector(card)
                UpdateResults("")
            end)
            card:SetScript("OnEnter", function(self)
                if not self.glow:IsShown() then
                    self:SetBackdropBorderColor(0.40, 0.34, 0.20, 1)
                end
            end)
            card:SetScript("OnLeave", function(self)
                RefreshCard(self)
            end)

            table.insert(slotCards, card)
            card.iconBorder = iconBorder
            RefreshCard(card)

            col = col + 1
            if col >= cols then col = 0; row = row + 1 end
        end
    end

    local totalRows = row + (col > 0 and 1 or 0)
    content:SetHeight(56 + totalRows * (cardHeight + gapY) + 10)

    parent:SetScript("OnShow", function() RefreshAllCards() end)
end
