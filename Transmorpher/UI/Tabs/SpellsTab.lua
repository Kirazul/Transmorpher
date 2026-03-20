local addon, ns = ...

-- Helper for finding spell IDs in the spellbook
local function GetSpellBookSpellId(spellBookIndex)
    local bookType = BOOKTYPE_SPELL or "spell"
    if type(GetSpellBookItemInfo) == "function" then
        local spellType, spellId = GetSpellBookItemInfo(spellBookIndex, bookType)
        if spellType == "SPELL" and spellId then
            return tonumber(spellId)
        end
    end
    -- Fallbacks for different client builds/locales
    if type(GetSpellLink) == "function" then
        local link = GetSpellLink(spellBookIndex, bookType)
        if link then
            local spellId = tonumber(link:match("spell:(%d+)"))
            if spellId and spellId > 0 then return spellId end
        end
    end
    return nil
end

-- Builds a list of spells for the main list
local function BuildSpellPool(showAllRanks)
    local pool = {}
    local seen = {}
    local nameToBestId = {}

    local function AddSpell(spellId)
        if not spellId or seen[spellId] then return end
        local name, rank, icon = GetSpellInfo(spellId)
        if not name or name == "" then return end
        
        seen[spellId] = true
        local entry = {
            id = spellId,
            name = name,
            rank = rank,
            fullName = (rank and rank ~= "") and (name .. " " .. rank) or name,
            icon = icon or "Interface\\Icons\\Spell_Holy_MagicalSentry",
            nameLower = name:lower(),
        }

        if not showAllRanks then
            -- "Latest Rank" logic: Keep the highest ID for each unique name
            if not nameToBestId[entry.nameLower] or spellId > nameToBestId[entry.nameLower].id then
                nameToBestId[entry.nameLower] = entry
            end
        else
            table.insert(pool, entry)
        end
    end

    -- 1. Scan player spellbook
    local numTabs = GetNumSpellTabs() or 0
    for tab = 1, numTabs do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        if offset and numSpells then
            for i = 1, numSpells do
                local sId = GetSpellBookSpellId(offset + i)
                if sId then AddSpell(sId) end
            end
        end
    end

    -- 2. Include active morphs so they don't disappear from the list
    if TransmorpherCharacterState and TransmorpherCharacterState.SpellMorphs then
        for sourceId in pairs(TransmorpherCharacterState.SpellMorphs) do
            AddSpell(tonumber(sourceId))
        end
    end

    if not showAllRanks then
        for _, entry in pairs(nameToBestId) do
            table.insert(pool, entry)
        end
    end

    table.sort(pool, function(a, b)
        if a.nameLower ~= b.nameLower then return a.nameLower < b.nameLower end
        return a.id > b.id
    end)

    return pool
end

function ns.InitSpellsTab(parent)
    local spellPool = {}
    local filteredPool = {}
    local searchResults = {}
    local activeSourceSpellId = nil
    
    -- Main List Elements
    local scroll = CreateFrame("ScrollFrame", "$parentScroll", parent, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -50)
    scroll:SetPoint("BOTTOMRIGHT", -26, 10)
    
    -- Search UI Elements
    local selector = CreateFrame("Frame", "TransmorpherSpellSelector", parent)
    local searchBox -- Defined later
    local resultScroll -- Defined later

    local function UpdateFilteredPool(q)
        q = (q or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        filteredPool = {}
        if not spellPool or #spellPool == 0 then
            spellPool = BuildSpellPool(selector.showAllRanks)
        end
        if q == "" then
            filteredPool = spellPool
        else
            for _, entry in ipairs(spellPool) do
                if (entry.nameLower and entry.nameLower:find(q, 1, true)) or tostring(entry.id):find(q, 1, true) then
                    table.insert(filteredPool, entry)
                end
            end
        end
    end

    -- Forward Declare for use in rows
    local OpenSelector

    local function CreateSpellRow(p, i)
        local f = CreateFrame("Button", nil, p)
        f:SetSize(parent:GetWidth() > 0 and (parent:GetWidth() - 40) or 500, 44)
        f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        f:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        f:SetBackdropColor(0.06, 0.06, 0.06, 0.8)
        f:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.9)

        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetSize(32, 32)
        f.icon:SetPoint("LEFT", 6, 0)
        f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, -2)
        f.name:SetTextColor(0.96, 0.90, 0.72)

        f.subText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.subText:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -2)
        f.subText:SetTextColor(0.6, 0.6, 0.6)

        f.assign = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.assign:SetPoint("RIGHT", -110, 0)
        f.assign:SetTextColor(0.4, 1.0, 0.6)
        f.assign:SetJustifyH("RIGHT")

        f.actionBtn = ns.CreateGoldenButton(nil, f)
        f.actionBtn:SetSize(90, 22)
        f.actionBtn:SetPoint("RIGHT", -8, 0)

        f:SetScript("OnClick", function(self) if self.data then OpenSelector(self.data) end end)
        f.actionBtn:SetScript("OnClick", function(self) local p = self:GetParent(); if p.data then OpenSelector(p.data) end end)

        return f
    end

    local rows = {}
    local NUM_ROWS = math.floor((parent:GetHeight() - 60) / 46) 
    if NUM_ROWS < 1 then NUM_ROWS = 10 end
    local ROW_HEIGHT = 46

    local function UpdateScroll()
        FauxScrollFrame_Update(scroll, #filteredPool, NUM_ROWS, ROW_HEIGHT)
        local offset = FauxScrollFrame_GetOffset(scroll)
        for i = 1, NUM_ROWS do
            local idx = i + offset
            local row = rows[i]
            if not row then break end
            local data = filteredPool[idx]
            if data then
                row.data = data
                row.icon:SetTexture(data.icon)
                row.name:SetText(data.name)
                row.subText:SetText("ID " .. data.id .. (data.rank and data.rank ~= "" and (" · " .. data.rank) or ""))
                
                local targetId = ns.GetSpellMorph(data.id)
                if targetId then
                    local tName, _, tIcon = GetSpellInfo(targetId)
                    row.assign:SetText(tName or ("Spell " .. targetId))
                    row.assign:SetTextColor(0.3, 1.0, 0.5)
                    row.actionBtn:SetText("Change")
                else
                    row.assign:SetText("")
                    row.actionBtn:SetText("Select")
                end
                row:Show()
            else
                row:Hide()
            end
        end
    end

    -- Setup Scroll Logic
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, UpdateScroll)
    end)

    for i = 1, NUM_ROWS do
        rows[i] = CreateSpellRow(parent, i) -- Parent to main container for visibility
        rows[i]:SetPoint("TOPLEFT", 10, -50 - (i-1)*ROW_HEIGHT)
        rows[i]:Hide()
    end

    -- Build Header Filter
    local header = CreateFrame("Frame", nil, parent)
    header:SetPoint("TOPLEFT", 6, -6)
    header:SetPoint("TOPRIGHT", -26, -6)
    header:SetHeight(40)
    header:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    header:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    header:SetBackdropBorderColor(0.35, 0.30, 0.18, 0.9)

    local mainSearch = CreateFrame("EditBox", nil, header)
    mainSearch:SetSize(220, 22)
    mainSearch:SetPoint("RIGHT", -10, 0)
    mainSearch:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeSize=1 })
    mainSearch:SetBackdropColor(0,0,0,0.5)
    mainSearch:SetFontObject("ChatFontNormal")
    mainSearch:SetAutoFocus(false)
    mainSearch:SetTextInsets(8, 8, 0, 0)
    local mainSearchHint = mainSearch:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    mainSearchHint:SetPoint("LEFT", 8, 0)
    mainSearchHint:SetText("Filter spellbook...")
    
    mainSearch:SetScript("OnTextChanged", function(self)
        if self:GetText() == "" then mainSearchHint:Show() else mainSearchHint:Hide() end
        UpdateFilteredPool(self:GetText())
        UpdateScroll()
    end)

    -- === SELECTOR DIALOG ===
    selector:SetSize(460, 720)
    selector:SetPoint("CENTER", 0, 0)
    selector:SetFrameStrata("DIALOG")
    selector:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    selector:SetBackdropColor(0.03, 0.03, 0.03, 0.98)
    selector:SetBackdropBorderColor(0.60, 0.50, 0.20, 0.95)
    selector:EnableMouse(true)
    selector:SetMovable(true)
    selector:SetClampedToScreen(true)
    selector:Hide()

    local selTitle = selector:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    selTitle:SetPoint("TOPLEFT", 14, -14)
    selTitle:SetTextColor(1.0, 0.84, 0.35)

    local selStatus = selector:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    selStatus:SetPoint("TOPRIGHT", -40, -18)
    selStatus:SetTextColor(0.5, 0.5, 0.5)

    local selSubTitle = selector:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    selSubTitle:SetPoint("TOPLEFT", 16, -36)
    selSubTitle:SetTextColor(0.74, 0.74, 0.74)
    selSubTitle:SetText("Press TAB to toggle All Ranks")

    local selClose = CreateFrame("Button", nil, selector, "UIPanelCloseButton")
    selClose:SetPoint("TOPRIGHT", -4, -4)

    searchBox = CreateFrame("EditBox", nil, selector)
    searchBox:SetSize(432, 28)
    searchBox:SetPoint("TOPLEFT", 14, -54)
    searchBox:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    searchBox:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    searchBox:SetBackdropBorderColor(0.30, 0.30, 0.30, 1)
    searchBox:SetFontObject("ChatFontNormal")
    searchBox:SetAutoFocus(false)
    searchBox:SetTextInsets(10, 10, 0, 0)
    local searchHint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", 10, 0)
    searchHint:SetText("Search database (50,000+ spells)...")

    resultScroll = CreateFrame("ScrollFrame", "$parentResultScroll", selector, "FauxScrollFrameTemplate")
    resultScroll:SetPoint("TOPLEFT", 14, -90)
    resultScroll:SetPoint("BOTTOMRIGHT", -32, 44)
    local dummy = CreateFrame("Frame", nil, resultScroll)
    dummy:SetSize(1, 1)
    resultScroll:SetScrollChild(dummy)
    -- Create a static container for the results so they don't physically scroll
    local resultContainer = CreateFrame("Frame", nil, selector)
    resultContainer:SetPoint("TOPLEFT", 14, -90)
    resultContainer:SetPoint("BOTTOMRIGHT", -32, 44)

    local resultRows = {}
    local RESULT_ROWS = 28
    local RESULT_HEIGHT = 21

    local function UpdateResultScroll()
        FauxScrollFrame_Update(resultScroll, #searchResults, RESULT_ROWS, RESULT_HEIGHT)
        selStatus:SetText("Results: " .. #searchResults)
        local offset = FauxScrollFrame_GetOffset(resultScroll)
        for i = 1, RESULT_ROWS do
            local idx = i + offset
            local row = resultRows[i]
            if not row then break end
            local data = searchResults[idx]
            if data then
                row.spellId = data.id
                row.icon:SetTexture(data.icon)
                row.text:SetText(data.name)
                row.didText:SetText("ID " .. data.id)
                row:Show()
            else
                row:Hide()
            end
        end
    end

    for i = 1, RESULT_ROWS do
        local btn = CreateFrame("Button", nil, resultContainer)
        btn:SetSize(396, RESULT_HEIGHT - 1)
        btn:SetPoint("TOPLEFT", 0, -(i-1)*RESULT_HEIGHT)
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
        btn.icon:SetSize(16, 16)
        btn.icon:SetPoint("LEFT", 5, 0)
        btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.text:SetPoint("LEFT", btn.icon, "RIGHT", 8, 0)
        btn.text:SetJustifyH("LEFT")
        btn.didText = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        btn.didText:SetPoint("RIGHT", -8, 0)
        
        btn:SetScript("OnClick", function(self)
            if not activeSourceSpellId then return end
            ns.SetSpellMorph(activeSourceSpellId, self.spellId)
            ns.SendMorphCommand("SPELL_MORPH:" .. activeSourceSpellId .. ":" .. self.spellId)
            UpdateScroll()
            selector:Hide()
            PlaySound("gsTitleOptionOK")
        end)
        resultRows[i] = btn
    end

    resultScroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, RESULT_HEIGHT, UpdateResultScroll)
    end)

    local pollFrame = CreateFrame("Frame")
    local function PerformSearch(query)
        TRANSMORPHER_SEARCH_RESULTS = nil -- Clear previous
        ns.SendMorphCommand("SPELL_SEARCH:" .. (query or ""))
        
        -- Use OnUpdate-based polling for maximum compatibility with all 3.3.5a builds
        local pollStart = GetTime()
        pollFrame:SetScript("OnUpdate", function(self, elapsed)
            local res = TRANSMORPHER_SEARCH_RESULTS
            if res or (GetTime() - pollStart > 0.2) then
                self:SetScript("OnUpdate", nil)
                res = res or ""
                searchResults = {}
                for sId in res:gmatch("(%d+)|") do
                    local id = tonumber(sId)
                    if id then
                        local name, rank, icon = GetSpellInfo(id)
                        if name then
                            table.insert(searchResults, {
                                id = id,
                                name = (rank and rank ~= "") and (name .. " " .. rank) or name,
                                icon = icon or "Interface\\Icons\\Spell_Holy_MagicalSentry",
                            })
                        end
                    end
                end
                UpdateResultScroll()
            end
        end)
    end

    OpenSelector = function(data)
        activeSourceSpellId = data.id
        selTitle:SetText("Morph: " .. data.name)
        searchBox:SetText("")
        searchHint:Show()
        searchResults = {}
        PerformSearch("") -- Show default spells immediately
        selector:Show()
        searchBox:SetFocus()
    end

    searchBox:SetScript("OnTextChanged", function(self)
        local txt = self:GetText()
        if txt == "" then searchHint:Show() else searchHint:Hide() end
        PerformSearch(txt)
    end)

    searchBox:SetScript("OnTabPressed", function()
        selector.showAllRanks = not selector.showAllRanks
        spellPool = BuildSpellPool(selector.showAllRanks)
        UpdateFilteredPool(mainSearch:GetText())
        UpdateScroll()
        PlaySound("igMainMenuOptionCheckBoxOn")
    end)

    local btnClear = ns.CreateGoldenButton(nil, selector)
    btnClear:SetSize(120, 24)
    btnClear:SetPoint("BOTTOMLEFT", 14, 12)
    btnClear:SetText("Remove Morph")
    btnClear:SetScript("OnClick", function()
        if activeSourceSpellId then
            ns.SetSpellMorph(activeSourceSpellId, nil)
            ns.SendMorphCommand("SPELL_RESET:" .. activeSourceSpellId)
            UpdateScroll()
            selector:Hide()
            PlaySound("gsTitleOptionOK")
        end
    end)

    parent:SetScript("OnShow", function()
        spellPool = BuildSpellPool(selector.showAllRanks)
        UpdateFilteredPool(mainSearch:GetText())
        UpdateScroll()
        ns.SendMorphCommand("SPELL_DBC_STATUS")
    end)

    -- IMMEDIATE INITIALIZATION
    spellPool = BuildSpellPool(selector.showAllRanks)
    UpdateFilteredPool("")
    UpdateScroll()
    ns.SendMorphCommand("SPELL_DBC_STATUS")
    
    if #spellPool == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[Transmorpher]|r Scanning spellbook... (Please wait if just logged in)")
    end
end
