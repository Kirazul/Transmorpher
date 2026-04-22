local addon, ns = ...

-- ============================================================
-- SPELLSWAP BY AURA TAB
-- Configure rules like:
-- "When aura X is active, swap spell A visual into spell B"
-- ============================================================

function ns.InitAuraSwapTab(parent)
    local rules = {}
    local selectedRuleUID = nil
    local editMode = false

    local function UpdateEmptyState()
        if not parent.emptyText then return end
        if #rules == 0 then
            parent.emptyText:Show()
        else
            parent.emptyText:Hide()
        end
    end

    local function RefreshRuleList()
        rules = {}
        local savedRules = ns.GetAuraSpellSwapRules()
        for uid, rule in pairs(savedRules) do
            table.insert(rules, { uid = uid, rule = rule })
        end
        table.sort(rules, function(a, b)
            local nameA = GetSpellInfo(a.rule.auraSpellId or 0) or ""
            local nameB = GetSpellInfo(b.rule.auraSpellId or 0) or ""
            if nameA ~= nameB then
                return nameA < nameB
            end
            return tostring(a.uid) < tostring(b.uid)
        end)
        UpdateEmptyState()
    end

    local listFrame = CreateFrame("Frame", nil, parent)
    listFrame:SetPoint("TOPLEFT", 0, -6)
    listFrame:SetPoint("BOTTOMLEFT", 0, 6)
    listFrame:SetWidth(240)

    local listTitle = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    listTitle:SetPoint("TOPLEFT", 10, -4)
    listTitle:SetText("|cffF5C842Spellswap by Aura|r")
    listTitle:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")

    local listDesc = listFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    listDesc:SetPoint("TOPLEFT", 10, -22)
    listDesc:SetPoint("TOPRIGHT", -6, -22)
    listDesc:SetJustifyH("LEFT")
    listDesc:SetTextColor(0.6, 0.6, 0.6)
    listDesc:SetText("Apply world-class spell visual swaps automatically while selected auras are active.")

    local listScroll = CreateFrame("ScrollFrame", "$parentAuraSwapScroll", listFrame, "FauxScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 4, -42)
    listScroll:SetPoint("BOTTOMRIGHT", -22, 32)

    local NUM_LIST_ROWS = 8
    local LIST_ROW_HEIGHT = 42
    local listRows = {}

    local function CreateRuleRow()
        local row = CreateFrame("Button", nil, listFrame)
        row:SetSize(210, LIST_ROW_HEIGHT - 2)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        row:SetBackdropColor(0.06, 0.06, 0.06, 0.8)
        row:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.9)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(28, 28)
        row.icon:SetPoint("LEFT", 6, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
        row.name:SetPoint("RIGHT", -30, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetTextColor(0.96, 0.90, 0.72)

        row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
        row.sub:SetTextColor(0.5, 0.5, 0.5)

        row.activeGlow = row:CreateTexture(nil, "OVERLAY")
        row.activeGlow:SetSize(8, 8)
        row.activeGlow:SetPoint("RIGHT", -8, 0)
        row.activeGlow:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        row.activeGlow:Hide()

        return row
    end

    for i = 1, NUM_LIST_ROWS do
        listRows[i] = CreateRuleRow()
        listRows[i]:SetPoint("TOPLEFT", 6, -42 - (i - 1) * LIST_ROW_HEIGHT)
        listRows[i]:Hide()
    end

    local btnAdd = ns.CreateGoldenButton(nil, listFrame)
    btnAdd:SetSize(110, 22)
    btnAdd:SetPoint("BOTTOMLEFT", 6, 6)
    btnAdd:SetText("+ Add Rule")

    local editor = CreateFrame("Frame", nil, parent)
    editor:SetPoint("TOPLEFT", listFrame, "TOPRIGHT", 4, 0)
    editor:SetPoint("BOTTOMRIGHT", 0, 0)
    editor:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    editor:SetBackdropColor(0.04, 0.04, 0.04, 0.95)
    editor:SetBackdropBorderColor(0.35, 0.30, 0.18, 0.9)
    editor:Hide()

    local editorTitle = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    editorTitle:SetPoint("TOPLEFT", 12, -10)
    editorTitle:SetTextColor(1.0, 0.84, 0.35)
    editorTitle:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")

    local editorSub = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    editorSub:SetPoint("TOPLEFT", editorTitle, "BOTTOMLEFT", 0, -4)
    editorSub:SetPoint("RIGHT", -12, 0)
    editorSub:SetJustifyH("LEFT")
    editorSub:SetTextColor(0.55, 0.55, 0.55)
    editorSub:SetText("Aura-active rules override direct spell morphs for matching source spells and restore cleanly when the aura fades.")

    local auraLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    auraLabel:SetPoint("TOPLEFT", 12, -56)
    auraLabel:SetText("Trigger Aura:")
    auraLabel:SetTextColor(0.95, 0.88, 0.65)

    local auraBox = CreateFrame("EditBox", nil, editor)
    auraBox:SetSize(200, 24)
    auraBox:SetPoint("TOPLEFT", 12, -72)
    auraBox:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    auraBox:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    auraBox:SetBackdropBorderColor(0.30, 0.30, 0.30, 1)
    auraBox:SetFontObject("ChatFontNormal")
    auraBox:SetAutoFocus(false)
    auraBox:SetTextInsets(8, 8, 0, 0)
    auraBox:SetMaxLetters(40)

    local auraHint = auraBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    auraHint:SetPoint("LEFT", 8, 0)
    auraHint:SetText("Enter aura name or spell ID...")

    local auraPreview = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    auraPreview:SetPoint("TOPLEFT", auraBox, "TOPRIGHT", 8, -4)
    auraPreview:SetTextColor(0.4, 1.0, 0.6)

    local auraIcon = editor:CreateTexture(nil, "ARTWORK")
    auraIcon:SetSize(20, 20)
    auraIcon:SetPoint("LEFT", auraPreview, "RIGHT", 4, 0)
    auraIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    auraIcon:Hide()

    local resolvedAuraId = nil
    local pickerResults = {}
    local pickerCallback = nil
    local pickerIsDBCMode = false
    local editSwaps = {}
    local swapRows = {}

    local function ResolveAura(text)
        if not text or text == "" then
            resolvedAuraId = nil
            auraPreview:SetText("")
            auraIcon:Hide()
            return
        end

        local numId = tonumber(text)
        if numId and numId > 0 then
            local name, _, icon = GetSpellInfo(numId)
            if name then
                resolvedAuraId = numId
                auraPreview:SetText(name)
                auraIcon:SetTexture(icon)
                auraIcon:Show()
                return
            end
        end

        local lowerText = text:lower()
        for i = 1, 40 do
            local name, _, icon, _, _, _, _, _, _, _, spellID = UnitAura("player", i, "HELPFUL")
            if not name then break end
            if name:lower():find(lowerText, 1, true) then
                resolvedAuraId = spellID
                auraPreview:SetText(name .. " (ID " .. spellID .. ")")
                auraIcon:SetTexture(icon)
                auraIcon:Show()
                return
            end
        end

        for i = 1, 40 do
            local name, _, icon, _, _, _, _, _, _, _, spellID = UnitAura("player", i, "HARMFUL")
            if not name then break end
            if name:lower():find(lowerText, 1, true) then
                resolvedAuraId = spellID
                auraPreview:SetText(name .. " (ID " .. spellID .. ")")
                auraIcon:SetTexture(icon)
                auraIcon:Show()
                return
            end
        end

        local name = GetSpellInfo(text)
        if name then
            auraPreview:SetText("|cffff8800Type the exact spell ID for best results|r")
            auraIcon:Hide()
            resolvedAuraId = nil
        else
            resolvedAuraId = nil
            auraPreview:SetText("|cffff4444Not found|r")
            auraIcon:Hide()
        end
    end

    auraBox:SetScript("OnTextChanged", function(self)
        local txt = self:GetText()
        if txt == "" then auraHint:Show() else auraHint:Hide() end
        ResolveAura(txt)
    end)

    local swapsLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    swapsLabel:SetPoint("TOPLEFT", 12, -106)
    swapsLabel:SetText("Swap Pairs while aura is active:")
    swapsLabel:SetTextColor(0.95, 0.88, 0.65)

    local swapsHelp = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    swapsHelp:SetPoint("TOPLEFT", swapsLabel, "BOTTOMLEFT", 0, -3)
    swapsHelp:SetPoint("RIGHT", -12, 0)
    swapsHelp:SetJustifyH("LEFT")
    swapsHelp:SetTextColor(0.5, 0.5, 0.5)
    swapsHelp:SetText("Source must come from your spellbook. Target can be any spell found in the DLL database.")

    local swapPairsFrame = CreateFrame("Frame", nil, editor)
    swapPairsFrame:SetPoint("TOPLEFT", 12, -142)
    swapPairsFrame:SetPoint("TOPRIGHT", -12, -142)
    swapPairsFrame:SetHeight(200)

    local MAX_SWAP_ROWS = 6
    local SWAP_ROW_H = 30

    local function CreateSwapRow(idx)
        local yOff = -(idx - 1) * SWAP_ROW_H

        local sourceBtn = CreateFrame("Button", "TransmorpherAuraSwapSrc" .. idx, swapPairsFrame)
        sourceBtn:SetSize(150, 24)
        sourceBtn:SetPoint("TOPLEFT", 0, yOff)
        sourceBtn:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        sourceBtn:SetBackdropColor(0.08, 0.06, 0.03, 0.95)
        sourceBtn:SetBackdropBorderColor(0.30, 0.30, 0.30, 1)
        sourceBtn:RegisterForClicks("LeftButtonUp")
        sourceBtn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        local sourceIcon = sourceBtn:CreateTexture(nil, "ARTWORK")
        sourceIcon:SetSize(18, 18)
        sourceIcon:SetPoint("LEFT", 4, 0)
        sourceIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local sourceText = sourceBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sourceText:SetPoint("LEFT", sourceIcon, "RIGHT", 4, 0)
        sourceText:SetPoint("RIGHT", -4, 0)
        sourceText:SetJustifyH("LEFT")
        sourceText:SetText("Select Source...")
        sourceText:SetTextColor(0.5, 0.5, 0.5)

        local arrow = swapPairsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        arrow:SetPoint("LEFT", sourceBtn, "RIGHT", 6, 0)
        arrow:SetText("|cffF5C842->|r")

        local targetBtn = CreateFrame("Button", "TransmorpherAuraSwapTgt" .. idx, swapPairsFrame)
        targetBtn:SetSize(150, 24)
        targetBtn:SetPoint("LEFT", arrow, "RIGHT", 6, 0)
        targetBtn:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        targetBtn:SetBackdropColor(0.08, 0.06, 0.03, 0.95)
        targetBtn:SetBackdropBorderColor(0.30, 0.30, 0.30, 1)
        targetBtn:RegisterForClicks("LeftButtonUp")
        targetBtn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        local targetIcon = targetBtn:CreateTexture(nil, "ARTWORK")
        targetIcon:SetSize(18, 18)
        targetIcon:SetPoint("LEFT", 4, 0)
        targetIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local targetText = targetBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        targetText:SetPoint("LEFT", targetIcon, "RIGHT", 4, 0)
        targetText:SetPoint("RIGHT", -4, 0)
        targetText:SetJustifyH("LEFT")
        targetText:SetText("Select Target...")
        targetText:SetTextColor(0.5, 0.5, 0.5)

        local removeBtn = CreateFrame("Button", "TransmorpherAuraSwapDel" .. idx, swapPairsFrame)
        removeBtn:SetSize(18, 18)
        removeBtn:SetPoint("LEFT", targetBtn, "RIGHT", 4, 0)
        removeBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        removeBtn:GetNormalTexture():SetVertexColor(0.8, 0.3, 0.3)
        removeBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
        removeBtn:RegisterForClicks("LeftButtonUp")

        local row = {
            sourceBtn = sourceBtn,
            sourceIcon = sourceIcon,
            sourceText = sourceText,
            targetBtn = targetBtn,
            targetIcon = targetIcon,
            targetText = targetText,
            removeBtn = removeBtn,
            arrow = arrow,
        }

        row.Show = function(self)
            self.sourceBtn:Show()
            self.targetBtn:Show()
            self.removeBtn:Show()
            self.arrow:Show()
        end

        row.Hide = function(self)
            self.sourceBtn:Hide()
            self.targetBtn:Hide()
            self.removeBtn:Hide()
            self.arrow:Hide()
        end

        row:Hide()
        return row
    end

    for i = 1, MAX_SWAP_ROWS do
        swapRows[i] = CreateSwapRow(i)
    end

    local btnAddSwap = CreateFrame("Button", nil, editor)
    btnAddSwap:SetSize(90, 20)
    btnAddSwap:SetPoint("TOPLEFT", swapPairsFrame, "BOTTOMLEFT", 0, -4)
    btnAddSwap:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    local addSwapText = btnAddSwap:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    addSwapText:SetPoint("LEFT", 4, 0)
    addSwapText:SetText("|cff88cc88+ Add Pair|r")

    local picker = CreateFrame("Frame", "TransmorpherAuraSpellPicker", UIParent)
    picker:SetSize(340, 500)
    picker:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    picker:SetFrameStrata("FULLSCREEN_DIALOG")
    picker:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    picker:SetBackdropColor(0.03, 0.03, 0.03, 0.98)
    picker:SetBackdropBorderColor(0.60, 0.50, 0.20, 0.95)
    picker:EnableMouse(true)
    picker:SetMovable(true)
    picker:SetClampedToScreen(true)
    picker:RegisterForDrag("LeftButton")
    picker:SetScript("OnDragStart", picker.StartMoving)
    picker:SetScript("OnDragStop", picker.StopMovingOrSizing)
    picker:Hide()

    local pickerTitle = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pickerTitle:SetPoint("TOPLEFT", 14, -14)
    pickerTitle:SetTextColor(1.0, 0.84, 0.35)

    local pickerClose = CreateFrame("Button", nil, picker, "UIPanelCloseButton")
    pickerClose:SetPoint("TOPRIGHT", -4, -4)

    local pickerSearch = CreateFrame("EditBox", nil, picker)
    pickerSearch:SetSize(310, 26)
    pickerSearch:SetPoint("TOPLEFT", 14, -40)
    pickerSearch:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    pickerSearch:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    pickerSearch:SetBackdropBorderColor(0.30, 0.30, 0.30, 1)
    pickerSearch:SetFontObject("ChatFontNormal")
    pickerSearch:SetAutoFocus(false)
    pickerSearch:SetTextInsets(8, 8, 0, 0)

    local pickerSearchHint = pickerSearch:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pickerSearchHint:SetPoint("LEFT", 8, 0)
    pickerSearchHint:SetText("Search spells or enter spell ID...")

    local pickerScroll = CreateFrame("ScrollFrame", "$parentPickerScroll", picker, "FauxScrollFrameTemplate")
    pickerScroll:SetPoint("TOPLEFT", 14, -74)
    pickerScroll:SetPoint("BOTTOMRIGHT", -32, 14)

    local pickerContainer = CreateFrame("Frame", nil, picker)
    pickerContainer:SetPoint("TOPLEFT", 14, -74)
    pickerContainer:SetPoint("BOTTOMRIGHT", -32, 14)

    local PICKER_ROWS = 18
    local PICKER_ROW_H = 22
    local pickerRows = {}

    local function UpdatePickerScroll()
        FauxScrollFrame_Update(pickerScroll, #pickerResults, PICKER_ROWS, PICKER_ROW_H)
        local offset = FauxScrollFrame_GetOffset(pickerScroll)
        for i = 1, PICKER_ROWS do
            local idx = i + offset
            local row = pickerRows[i]
            local data = pickerResults[idx]
            if data then
                row.spellId = data.id
                row.icon:SetTexture(data.icon)
                row.text:SetText(data.name)
                row.idText:SetText("ID " .. data.id)
                row:Show()
            else
                row:Hide()
            end
        end
    end

    for i = 1, PICKER_ROWS do
        local btn = CreateFrame("Button", nil, pickerContainer)
        btn:SetSize(280, PICKER_ROW_H - 1)
        btn:SetPoint("TOPLEFT", 0, -(i - 1) * PICKER_ROW_H)
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
        btn.text:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
        btn.text:SetJustifyH("LEFT")

        btn.idText = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        btn.idText:SetPoint("RIGHT", -8, 0)

        btn:SetScript("OnClick", function(self)
            if pickerCallback and self.spellId then
                pickerCallback(self.spellId)
                picker:Hide()
                PlaySound("gsTitleOptionOK")
            end
        end)

        pickerRows[i] = btn
    end

    pickerScroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, PICKER_ROW_H, UpdatePickerScroll)
    end)

    local pickerPollFrame = CreateFrame("Frame")

    local function PerformPickerSearch(query)
        pickerResults = {}

        local function GetSpellBookSpellId(spellBookIndex)
            local bookType = BOOKTYPE_SPELL or "spell"
            if type(GetSpellBookItemInfo) == "function" then
                local spellType, spellId = GetSpellBookItemInfo(spellBookIndex, bookType)
                if spellType == "SPELL" and spellId then
                    return tonumber(spellId)
                end
            end
            if type(GetSpellLink) == "function" then
                local link = GetSpellLink(spellBookIndex, bookType)
                if link then
                    local spellId = tonumber(link:match("spell:(%d+)"))
                    if spellId and spellId > 0 then return spellId end
                end
            end
            return nil
        end

        local seen = {}
        local lowerQ = (query or ""):lower()
        local numericQ = tonumber(query)
        local numTabs = GetNumSpellTabs() or 0
        for tab = 1, numTabs do
            local _, _, tabOffset, numSpells = GetSpellTabInfo(tab)
            if tabOffset and numSpells then
                for j = 1, numSpells do
                    local spellId = GetSpellBookSpellId(tabOffset + j)
                    if spellId and not seen[spellId] then
                        seen[spellId] = true
                        local name, rank, icon = GetSpellInfo(spellId)
                        if name then
                            local fullName = (rank and rank ~= "") and (name .. " " .. rank) or name
                            if lowerQ == "" or fullName:lower():find(lowerQ, 1, true) or (numericQ and spellId == numericQ) or tostring(spellId):find(lowerQ, 1, true) then
                                table.insert(pickerResults, {
                                    id = spellId,
                                    name = fullName,
                                    icon = icon or "Interface\\Icons\\Spell_Holy_MagicalSentry",
                                })
                            end
                        end
                    end
                end
            end
        end

        if pickerIsDBCMode and query and query ~= "" then
            TRANSMORPHER_SEARCH_RESULTS = nil
            ns.SendRawMorphCommand("SPELL_SEARCH:" .. query)

            local pollStart = GetTime()
            pickerPollFrame:SetScript("OnUpdate", function(self)
                local res = TRANSMORPHER_SEARCH_RESULTS
                if res or (GetTime() - pollStart > 0.2) then
                    self:SetScript("OnUpdate", nil)
                    res = res or ""
                    for sId in res:gmatch("(%d+)|") do
                        local id = tonumber(sId)
                        if id and not seen[id] then
                            seen[id] = true
                            local name, rank, icon = GetSpellInfo(id)
                            if name then
                                table.insert(pickerResults, {
                                    id = id,
                                    name = (rank and rank ~= "") and (name .. " " .. rank) or name,
                                    icon = icon or "Interface\\Icons\\Spell_Holy_MagicalSentry",
                                })
                            end
                        end
                    end
                    table.sort(pickerResults, function(a, b)
                        if a.name ~= b.name then return a.name < b.name end
                        return a.id < b.id
                    end)
                    UpdatePickerScroll()
                end
            end)
        end

        table.sort(pickerResults, function(a, b)
            if a.name ~= b.name then return a.name < b.name end
            return a.id < b.id
        end)
        UpdatePickerScroll()
    end

    pickerSearch:SetScript("OnTextChanged", function(self)
        local txt = self:GetText()
        if txt == "" then pickerSearchHint:Show() else pickerSearchHint:Hide() end
        PerformPickerSearch(txt)
    end)

    local function OpenPicker(title, isDBCSearch, callback)
        pickerTitle:SetText(title)
        pickerIsDBCMode = isDBCSearch
        pickerCallback = callback
        pickerSearch:SetText("")
        pickerSearchHint:Show()
        pickerResults = {}
        PerformPickerSearch("")
        picker:Show()
        pickerSearch:SetFocus()
    end

    local function UpdateSwapRowDisplay()
        for i = 1, MAX_SWAP_ROWS do
            local row = swapRows[i]
            local swap = editSwaps[i]
            if swap then
                if swap.source and swap.source > 0 then
                    local name, rank, icon = GetSpellInfo(swap.source)
                    row.sourceText:SetText((rank and rank ~= "") and (name .. " " .. rank) or name or ("Spell " .. swap.source))
                    row.sourceText:SetTextColor(0.96, 0.90, 0.72)
                    row.sourceIcon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    row.sourceIcon:Show()
                else
                    row.sourceText:SetText("Select Source...")
                    row.sourceText:SetTextColor(0.5, 0.5, 0.5)
                    row.sourceIcon:Hide()
                end

                if swap.target and swap.target > 0 then
                    local name, rank, icon = GetSpellInfo(swap.target)
                    row.targetText:SetText((rank and rank ~= "") and (name .. " " .. rank) or name or ("Spell " .. swap.target))
                    row.targetText:SetTextColor(0.3, 1.0, 0.5)
                    row.targetIcon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    row.targetIcon:Show()
                else
                    row.targetText:SetText("Select Target...")
                    row.targetText:SetTextColor(0.5, 0.5, 0.5)
                    row.targetIcon:Hide()
                end

                row:Show()
            else
                row:Hide()
            end
        end
    end

    for i = 1, MAX_SWAP_ROWS do
        local idx = i
        swapRows[i].sourceBtn:SetScript("OnClick", function()
            OpenPicker("Select Source Spell (Your Spellbook)", false, function(spellId)
                if editSwaps[idx] then
                    editSwaps[idx].source = spellId
                    UpdateSwapRowDisplay()
                end
            end)
        end)

        swapRows[i].targetBtn:SetScript("OnClick", function()
            OpenPicker("Select Target Spell (All Spells)", true, function(spellId)
                if editSwaps[idx] then
                    editSwaps[idx].target = spellId
                    UpdateSwapRowDisplay()
                end
            end)
        end)

        swapRows[i].removeBtn:SetScript("OnClick", function()
            table.remove(editSwaps, idx)
            if #editSwaps == 0 then
                table.insert(editSwaps, { source = nil, target = nil })
            end
            UpdateSwapRowDisplay()
            PlaySound("gsTitleOptionOK")
        end)
    end

    btnAddSwap:SetScript("OnClick", function()
        if #editSwaps < MAX_SWAP_ROWS then
            table.insert(editSwaps, { source = nil, target = nil })
            UpdateSwapRowDisplay()
            PlaySound("igMainMenuOptionCheckBoxOn")
        end
    end)

    local btnSave = ns.CreateGoldenButton(nil, editor)
    btnSave:SetSize(80, 24)
    btnSave:SetPoint("BOTTOMLEFT", 12, 10)
    btnSave:SetText("Save")

    local btnDelete = ns.CreateGoldenButton(nil, editor)
    btnDelete:SetSize(80, 24)
    btnDelete:SetPoint("LEFT", btnSave, "RIGHT", 8, 0)
    btnDelete:SetText("Delete")

    local btnToggle = ns.CreateGoldenButton(nil, editor)
    btnToggle:SetSize(100, 24)
    btnToggle:SetPoint("LEFT", btnDelete, "RIGHT", 8, 0)
    btnToggle:SetText("Enable")

    local function UpdateListScroll()
        FauxScrollFrame_Update(listScroll, #rules, NUM_LIST_ROWS, LIST_ROW_HEIGHT)
        local offset = FauxScrollFrame_GetOffset(listScroll)
        for i = 1, NUM_LIST_ROWS do
            local idx = i + offset
            local row = listRows[i]
            local entry = rules[idx]
            if entry then
                local rule = entry.rule
                local auraName, _, auraIconTex = GetSpellInfo(rule.auraSpellId or 0)
                row.icon:SetTexture(auraIconTex or "Interface\\Icons\\INV_Misc_QuestionMark")
                row.name:SetText(auraName or ("Aura ID " .. (rule.auraSpellId or "?")))
                local swapCount = rule.swaps and #rule.swaps or 0
                local statusColor = rule.enabled and "|cff44ff44" or "|cff888888"
                local statusText = rule.enabled and "Enabled" or "Disabled"
                row.sub:SetText(swapCount .. " pair(s) · " .. statusColor .. statusText .. "|r")

                if ns.activeAuraSwapRules[entry.uid] then
                    row.activeGlow:SetVertexColor(0.3, 1.0, 0.3, 1)
                    row.activeGlow:Show()
                elseif rule.enabled then
                    row.activeGlow:SetVertexColor(0.5, 0.5, 0.5, 0.6)
                    row.activeGlow:Show()
                else
                    row.activeGlow:Hide()
                end

                if entry.uid == selectedRuleUID then
                    row:SetBackdropBorderColor(0.60, 0.50, 0.20, 1)
                else
                    row:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.9)
                end

                row.uid = entry.uid
                row:SetScript("OnClick", function()
                    selectedRuleUID = entry.uid
                    if parent.OpenEditor then
                        parent:OpenEditor(entry.uid)
                    end
                    RefreshRuleList()
                    UpdateListScroll()
                end)
                row:Show()
            else
                row:Hide()
            end
        end
        UpdateEmptyState()
    end

    listScroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, LIST_ROW_HEIGHT, UpdateListScroll)
    end)

    function parent:OpenEditor(uid)
        selectedRuleUID = uid
        editMode = true
        editor:Show()

        if uid then
            local savedRules = ns.GetAuraSpellSwapRules()
            local rule = savedRules[uid]
            if rule then
                editorTitle:SetText("Edit Aura Rule")
                auraBox:SetText(tostring(rule.auraSpellId or ""))
                ResolveAura(tostring(rule.auraSpellId or ""))
                editSwaps = {}
                if rule.swaps then
                    for _, swap in ipairs(rule.swaps) do
                        table.insert(editSwaps, { source = swap.source, target = swap.target })
                    end
                end
                if #editSwaps == 0 then
                    table.insert(editSwaps, { source = nil, target = nil })
                end
                btnToggle:SetText(rule.enabled and "Disable" or "Enable")
                btnDelete:Show()
            end
        else
            editorTitle:SetText("New Aura Rule")
            auraBox:SetText("")
            resolvedAuraId = nil
            auraPreview:SetText("")
            auraIcon:Hide()
            editSwaps = { { source = nil, target = nil } }
            btnToggle:SetText("Enable")
            btnDelete:Hide()
        end

        UpdateSwapRowDisplay()
        UpdateEmptyState()
    end

    function parent:CloseEditor()
        editMode = false
        selectedRuleUID = nil
        editor:Hide()
        picker:Hide()
        RefreshRuleList()
        UpdateListScroll()
    end

    btnAdd:SetScript("OnClick", function()
        parent:OpenEditor(nil)
        RefreshRuleList()
        UpdateListScroll()
        PlaySound("igMainMenuOptionCheckBoxOn")
    end)

    btnSave:SetScript("OnClick", function()
        if not resolvedAuraId then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[Transmorpher]|r Please enter a valid aura spell ID.")
            return
        end

        local validSwaps = {}
        local seenSource = {}
        for _, swap in ipairs(editSwaps) do
            local source = tonumber(swap.source)
            local target = tonumber(swap.target)
            if source and source > 0 and target and target > 0 and source ~= target then
                if not seenSource[source] then
                    seenSource[source] = true
                    table.insert(validSwaps, { source = source, target = target })
                end
            end
        end

        if #validSwaps == 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[Transmorpher]|r Please add at least one valid spell swap pair.")
            return
        end

        local uid = selectedRuleUID or ns.GenerateRuleUID()
        local isNew = (selectedRuleUID == nil)
        local existingRule = ns.GetAuraSpellSwapRules()[uid]
        local wasEnabled = existingRule and existingRule.enabled or false

        if ns.activeAuraSwapRules[uid] then
            ns.RevertAuraSwapRule(uid)
        end

        local rule = {
            auraSpellId = resolvedAuraId,
            swaps = validSwaps,
            enabled = isNew and true or wasEnabled,
        }

        ns.SaveAuraSpellSwapRule(uid, rule)
        selectedRuleUID = uid
        if ns.CheckAuraSpellSwaps then
            ns.CheckAuraSpellSwaps()
        end

        RefreshRuleList()
        UpdateListScroll()
        parent:OpenEditor(uid)

        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[Transmorpher]|r Spellswap by Aura rule saved.")
        PlaySound("gsTitleOptionOK")
    end)

    btnDelete:SetScript("OnClick", function()
        if selectedRuleUID then
            ns.DeleteAuraSpellSwapRule(selectedRuleUID)
            parent:CloseEditor()
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[Transmorpher]|r Spellswap by Aura rule deleted.")
            PlaySound("gsTitleOptionOK")
        end
    end)

    btnToggle:SetScript("OnClick", function()
        if not selectedRuleUID then return end
        local savedRules = ns.GetAuraSpellSwapRules()
        local rule = savedRules[selectedRuleUID]
        if not rule then return end

        if rule.enabled then
            if ns.activeAuraSwapRules[selectedRuleUID] then
                ns.RevertAuraSwapRule(selectedRuleUID)
            end
            rule.enabled = false
            btnToggle:SetText("Enable")
        else
            rule.enabled = true
            btnToggle:SetText("Disable")
            if ns.CheckAuraSpellSwaps then
                ns.CheckAuraSpellSwaps()
            end
        end

        RefreshRuleList()
        UpdateListScroll()
        PlaySound("gsTitleOptionOK")
    end)

    parent.emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    parent.emptyText:SetPoint("CENTER")
    parent.emptyText:SetTextColor(0.5, 0.5, 0.5)
    parent.emptyText:SetText("No aura spell rules configured.\nClick '+ Add Rule' to build one.\n\nExample:\nWhen |cff00ff00Eclipse (Lunar)|r is active,\nswap |cffF5C842Wrath|r -> |cff00ccffStarfire|r visual.")

    parent.RefreshRuleList = function()
        RefreshRuleList()
        UpdateListScroll()
    end

    ns.NotifyAuraSpellSwapStateChanged = function()
        if parent:IsShown() then
            RefreshRuleList()
            UpdateListScroll()
        end
    end

    parent:SetScript("OnShow", function()
        RefreshRuleList()
        UpdateListScroll()
    end)

    local glowTimer = CreateFrame("Frame", nil, parent)
    glowTimer.elapsed = 0
    glowTimer:SetScript("OnUpdate", function(self, dt)
        if not parent:IsShown() then return end
        self.elapsed = self.elapsed + dt
        if self.elapsed >= 0.75 then
            self.elapsed = 0
            UpdateListScroll()
        end
    end)

    RefreshRuleList()
    UpdateListScroll()
end