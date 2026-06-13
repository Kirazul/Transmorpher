local addon, ns = ...

-- ============================================================
-- CHARACTER AURAS SUB-TAB (Preview ▸ Visuals)
-- Browser of the REAL persistent character spell-visuals the DLL enumerated by RE.
-- Names+icons resolve via a spell that uses each visual (GetSpellInfo).
--
-- PERSISTENCE MODEL (true seamless loop — RE_VISUALS_FINDINGS.md):
--   • Left-click a visual to WEAR it. The DLL attaches its looping state-kit ONCE and keeps the
--     SAME continuous emitter alive forever (it pins the emitter slot so the engine's 10s lifetime
--     never deactivates it). The original particle loop just keeps running — exactly like a real
--     buff aura — so there is NO respawn, NO pulse, NO flicker: a perfectly smooth loop.
--   • Left-click an active visual again to remove it (only that one; the rest are untouched).
--   • Active visuals survive morphs, forms, zoning and relogs when "Persist" is on (the DLL
--     re-attaches them after a whole-model rebuild).
-- Lazy, chunked loading keeps it smooth even with ~2000 visuals.
-- DLL: VIS_ENUM -> TRANSMORPHER_VISUALS ("visualId:spellId,..."), VIS_APPLY / VIS_REMOVE /
-- VIS_REAPPLY (model rebuild) / VIS_CLEAR / VIS_AUTOHEAL / VIS_MUTE.
-- ============================================================

local COLS         = 2
local ROW_H        = 44
local INITIAL_ROWS = 18            -- row-widget pool grows when the panel gets taller
-- The whole enum is browsable immediately (the FauxScrollFrame only ever builds the handful
-- of rows that are actually on screen, so "loading everything" costs nothing). Names/icons are
-- still resolved lazily in the background so opening the tab never blocks — ID search is instant
-- across the full list, and name matches stream in as the resolver catches up.
local RESOLVE_PER_FRAME = 6        -- idle GetSpellInfo batch (background name resolution)
local SEARCH_RESOLVE_PER_FRAME = 24 -- bigger batch while a name search is active
local RESOLVE_INTERVAL  = 0.04
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local entries  = {}    -- { {id=, spell=, name=, icon=, resolved=}, ... } (insertion order)
local entryById = {}
local view     = {}    -- filtered
local filterText = ""
local activeOnly = false
local loadedCount = 0  -- always == #entries: the full enum is browsable (kept for back-compat refs)
local visRows  = 12    -- live visible-row count (recomputed to fit the panel)
local panel                 -- the tab frame
local Refresh, RebuildView  -- fwd decls

-- ---- persistence helpers (file scope: work even if the tab was never opened) ----
local function S() return ns.GetSettings() end
local function ActiveSet() local s = S(); s.activeVisuals = s.activeVisuals or {}; return s.activeVisuals end
local function send(c) if ns.IsMorpherReady and ns.IsMorpherReady() then ns.SendMorphCommand(c) end end

function ns.Visuals_IsActive(id) return ActiveSet()[id] and true or false end

-- Tell the DLL whether its self-healing watchdog should re-assert visuals across model rebuilds.
function ns.Visuals_SyncAutoHeal() send("VIS_AUTOHEAL:" .. (S().visualsPersist ~= false and "1" or "0")) end
function ns.Visuals_Apply(id)
    ActiveSet()[id] = true
    ns.Visuals_SyncAutoHeal()
    send("VIS_APPLY:" .. id)
end
function ns.Visuals_Remove(id)
    ActiveSet()[id] = nil
    send("VIS_REMOVE:" .. id)
end
function ns.Visuals_Toggle(id)
    if ns.Visuals_IsActive(id) then ns.Visuals_Remove(id) else ns.Visuals_Apply(id) end
    return ns.Visuals_IsActive(id)
end
function ns.Visuals_Clear()
    local a = ActiveSet(); for k in pairs(a) do a[k] = nil end
    send("VIS_CLEAR")
end
-- Re-establish DLL state from the saved active set (used after a relog: the freshly injected
-- DLL has no idea what we were wearing).
function ns.Visuals_Reapply()
    for id in pairs(ActiveSet()) do send("VIS_APPLY:" .. id) end
end

-- login persistence: the heartbeat runs entirely in the DLL now (no Lua re-fire timer), so this
-- frame only re-establishes DLL state after login and after a whole-model rebuild.
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD"); f:RegisterEvent("UNIT_MODEL_CHANGED")
    local pending, accum = false, 0
    f:SetScript("OnEvent", function(_, ev, unit)
        if ev == "PLAYER_ENTERING_WORLD" then pending, accum = true, 0
        elseif ev == "UNIT_MODEL_CHANGED" and unit == "player" then
            -- A model rebuild drops every attached kit; the DLL re-attaches its active set.
            if S().visualsPersist ~= false and next(ActiveSet()) then send("VIS_REAPPLY") end
        end
    end)
    f:SetScript("OnUpdate", function(_, e)
        if not pending then return end
        accum = accum + (e or 0)
        if accum < 1.5 then return end
        pending = false
        -- After login settles, rebuild the freshly injected DLL's state from saved vars.
        if ns.IsMorpherReady and ns.IsMorpherReady() and next(ActiveSet()) then
            if S().visualsMuteSound then send("VIS_MUTE:1") end
            ns.Visuals_SyncAutoHeal()
            ns.Visuals_Reapply()
        end
    end)
end

-- ---- name / icon resolution (lazy) ----
local function Resolve(e)
    if e.resolved then return end
    e.resolved = true
    if e.spell and e.spell > 0 and GetSpellInfo then
        local n, _, icon = GetSpellInfo(e.spell)
        if n then e.name = n; e.icon = icon or DEFAULT_ICON; return end
    end
    e.name = "Visual " .. e.id
    e.icon = DEFAULT_ICON
end

local function DisplayName(e)
    return (e and e.name) or ("Visual " .. (e and e.id or "?"))
end

local function DisplayIcon(e)
    return (e and e.icon) or DEFAULT_ICON
end

local function ParseVisuals()
    entries = {}
    entryById = {}
    loadedCount = 0
    local s = TRANSMORPHER_VISUALS
    if type(s) ~= "string" or s == "" then return end
    for id, spell in string.gmatch(s, "(%d+):(%d+)") do
        local idx = #entries + 1
        local e = { id = tonumber(id), spell = tonumber(spell), index = idx }
        entries[idx] = e
        entryById[e.id] = e
    end
    loadedCount = #entries        -- everything is browsable straight away; no more paging
end

RebuildView = function()
    view = {}
    local f = filterText:lower()
    local limit = math.min(loadedCount, #entries)
    local seen = {}

    local function AddActiveId(id)
        local eid = tonumber(id) or id
        local e = entryById[eid] or { id = eid, spell = 0, name = "Visual " .. eid, icon = DEFAULT_ICON, resolved = true, index = 999999 }
        if not seen[e] then seen[e] = true; view[#view + 1] = e end
    end

    if f == "" and not activeOnly then
        for id in pairs(ActiveSet()) do AddActiveId(id) end
        table.sort(view, function(a, b) return (a.index or 0) < (b.index or 0) end)
        for i = 1, limit do
            local e = entries[i]
            if not seen[e] then view[#view + 1] = e end
        end
        return
    end

    local function AddIfMatch(e)
        if not e or seen[e] then return end
        if activeOnly and not ns.Visuals_IsActive(e.id) then return end
        if f ~= "" then
            local idMatch = tostring(e.id):find(f, 1, true)
            local nameMatch = e.resolved and e.name and e.name:lower():find(f, 1, true)
            if not idMatch and not nameMatch then return end
        end
        seen[e] = true
        view[#view + 1] = e
    end

    -- Name searches scan the full enum, but only against names already resolved by the
    -- background resolver. This keeps typing smooth while results stream in from all pages.
    local scanLimit = (f ~= "") and #entries or limit
    for i = 1, scanLimit do
        AddIfMatch(entries[i])
    end

    if activeOnly then
        for id in pairs(ActiveSet()) do AddIfMatch(entryById[tonumber(id) or id] or { id = tonumber(id) or id, spell = 0, name = "Visual " .. id, icon = DEFAULT_ICON, resolved = true, index = 999999 }) end
    end
    table.sort(view, function(a, b)
        local aa = ns.Visuals_IsActive(a.id)
        local bb = ns.Visuals_IsActive(b.id)
        if aa ~= bb then return aa end
        return (a.index or 0) < (b.index or 0)
    end)
end

-- Background chunked resolver: spreads GetSpellInfo work across frames so opening the
-- tab never blocks. Runs only while the tab is shown and stops when everything's done.
local resolver = CreateFrame("Frame")
resolver:Hide()
local resolveIdx = 1
local resolveDelay = 0
local scrollPause = 0
resolver:SetScript("OnUpdate", function(self, dt)
    dt = dt or 0
    if panel and not panel:IsShown() then self:Hide(); return end
    if scrollPause > 0 then scrollPause = math.max(0, scrollPause - dt); return end
    resolveDelay = resolveDelay - dt
    if resolveDelay > 0 then return end
    resolveDelay = RESOLVE_INTERVAL
    local target = (filterText ~= "") and #entries or loadedCount
    if #entries == 0 or target == 0 then self:Hide(); return end
    if resolveIdx > target then self:Hide(); return end
    local budget = (filterText ~= "") and SEARCH_RESOLVE_PER_FRAME or RESOLVE_PER_FRAME
    local done = 0
    while resolveIdx <= target and done < budget do
        local e = entries[resolveIdx]
        if e and not e.resolved then
            Resolve(e)
            done = done + 1
        end
        resolveIdx = resolveIdx + 1
    end
    while resolveIdx <= target and entries[resolveIdx] and entries[resolveIdx].resolved do
        resolveIdx = resolveIdx + 1
    end
    if resolveIdx > target then
        self:Hide()
    end
    if filterText ~= "" then RebuildView() end
    if Refresh then Refresh() end
end)
local function StartResolver(fromIndex)
    resolveDelay = RESOLVE_INTERVAL
    local target = (filterText ~= "") and #entries or loadedCount
    resolveIdx = math.max(1, tonumber(fromIndex) or 1)
    while resolveIdx <= target and entries[resolveIdx] and entries[resolveIdx].resolved do
        resolveIdx = resolveIdx + 1
    end
    if target > 0 and resolveIdx <= target then resolver:Show() else resolver:Hide() end
end

function ns.InitVisualsTab(parent)
    panel = parent

    local baseName = parent:GetName() or "TransmorpherVisuals"
    local RefreshAll
    local scroll

    local function MakeCard(p)
        local f = ns.CreatePanel and ns.CreatePanel(p) or CreateFrame("Frame", nil, p)
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            tile = true, tileSize = 8, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        f:SetBackdropColor(0.025, 0.027, 0.032, 0.88)
        f:SetBackdropBorderColor(0.38, 0.32, 0.13, 0.72)
        return f
    end

    local function CountActive()
        local n = 0
        for _ in pairs(ActiveSet()) do n = n + 1 end
        return n
    end

    local function ShortText(text, limit)
        text = text or ""
        if string.len(text) <= limit then return text end
        return string.sub(text, 1, limit - 2) .. ".."
    end

    local function ResetScroll()
        if not scroll then return end
        if FauxScrollFrame_SetOffset then FauxScrollFrame_SetOffset(scroll, 0) end
        scroll:SetVerticalScroll(0)
    end

    local function MakePill(p, width)
        local pill = CreateFrame("Frame", nil, p)
        pill:SetSize(width or 88, 20)
        pill:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            tile = true, tileSize = 8, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        pill:SetBackdropColor(0.045, 0.043, 0.038, 0.92)
        pill.dot = pill:CreateTexture(nil, "ARTWORK")
        pill.dot:SetSize(9, 9)
        pill.dot:SetPoint("LEFT", 7, 0)
        pill.dot:SetTexture("Interface\\Buttons\\WHITE8x8")
        pill.text = pill:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pill.text:SetPoint("LEFT", pill.dot, "RIGHT", 5, 0)
        pill.text:SetPoint("RIGHT", -5, 0)
        pill.text:SetJustifyH("LEFT")
        return pill
    end

    local function SetPill(pill, text, r, g, b)
        pill.text:SetText(text)
        pill.text:SetTextColor(0.92, 0.88, 0.72)
        pill.dot:SetVertexColor(r, g, b, 0.9)
        pill:SetBackdropBorderColor(r, g, b, 0.58)
    end

    local function BuildActiveList()
        local active = ActiveSet()
        local out = {}
        for id in pairs(active) do
            local eid = tonumber(id) or id
            out[#out + 1] = entryById[eid] or { id = eid, spell = 0, name = "Visual " .. eid, icon = DEFAULT_ICON, resolved = true, index = 999999 }
        end
        table.sort(out, function(a, b) return (a.index or 0) < (b.index or 0) end)
        return out
    end

    local function VisualTooltip(owner, id, name, spell)
        local active = ns.Visuals_IsActive(id)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:SetText(name or ("Visual " .. id), 1, 0.82, 0)
        GameTooltip:AddLine("Visual ID " .. id .. ((spell and spell > 0) and ("  |  Spell " .. spell) or ""), 0.7, 0.7, 0.7)
        GameTooltip:AddLine(active and "Status: |cff8fdc8fACTIVE|r" or "Status: |cff888888inactive|r", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(active and "Click to remove" or "Click to wear - it stays on seamlessly.", 0.55, 0.85, 0.55, true)
        GameTooltip:Show()
    end

    -- ---------------------------------------------------------------- header
    local headerCard = MakeCard(parent)
    headerCard:SetPoint("TOPLEFT", 12, -8)
    headerCard:SetPoint("TOPRIGHT", -12, -8)
    headerCard:SetHeight(66)

    local title = headerCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("|cffF5C842Character Auras|r")

    local countFs = headerCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countFs:SetPoint("LEFT", title, "RIGHT", 10, 0)
    countFs:SetTextColor(0.55, 0.55, 0.55)

    local activePill = MakePill(headerCard, 90)
    activePill:SetPoint("TOPRIGHT", -10, -9)

    local desc = headerCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -7)
    desc:SetPoint("RIGHT", headerCard, "RIGHT", -12, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("Real client spell visuals. |cff8fdc8fClick|r one to wear it - it stays on seamlessly. Click again to remove. Active auras are pinned, glowing, and listed below.")
    desc:SetTextColor(0.66, 0.66, 0.66)

    -- ----------------------------------------------------------- active strip
    local activeCard = MakeCard(parent)
    activeCard:SetPoint("TOPLEFT", headerCard, "BOTTOMLEFT", 0, -6)
    activeCard:SetPoint("TOPRIGHT", headerCard, "BOTTOMRIGHT", 0, -6)
    activeCard:SetHeight(56)

    local CHIP_X0 = 116          -- where the chip row begins (clear of the label column)
    local CHIP_STEP = 42

    local activeTitle = activeCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    activeTitle:SetPoint("TOPLEFT", 10, -7)
    activeTitle:SetText("|cffF5C842Active Now|r")

    local activeHint = activeCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    activeHint:SetPoint("TOPLEFT", activeTitle, "BOTTOMLEFT", 0, -5)
    activeHint:SetWidth(CHIP_X0 - 16)
    activeHint:SetJustifyH("LEFT")
    activeHint:SetText("Click a chip\nto remove")

    local activeNone = activeCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    activeNone:SetPoint("LEFT", activeCard, "LEFT", CHIP_X0, 0)
    activeNone:SetText("|cff777777No aura active - click a visual below.|r")

    local activeChips = {}
    local activeChipLimit = 8
    local function MakeActiveChip(i)
        local chip = CreateFrame("Button", nil, activeCard)
        chip:SetSize(38, 38)
        chip:SetPoint("LEFT", activeCard, "LEFT", CHIP_X0 + (i - 1) * CHIP_STEP, 0)
        chip:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            tile = true, tileSize = 8, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        chip:SetBackdropColor(0.08, 0.065, 0.035, 0.95)
        chip:SetBackdropBorderColor(0.95, 0.72, 0.22, 0.85)
        chip.glow = chip:CreateTexture(nil, "OVERLAY")
        chip.glow:SetPoint("TOPLEFT", -8, 8)
        chip.glow:SetPoint("BOTTOMRIGHT", 8, -8)
        chip.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        chip.glow:SetBlendMode("ADD")
        chip.glow:SetVertexColor(1, 0.76, 0.18, 0.75)
        chip.icon = chip:CreateTexture(nil, "ARTWORK")
        chip.icon:SetSize(28, 28)
        chip.icon:SetPoint("CENTER")
        chip.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        chip:SetScript("OnClick", function(self)
            if not self.id then return end
            ns.Visuals_Remove(self.id)
            PlaySound("gsTitleOptionCollapse")
            if RefreshAll then RefreshAll() end
        end)
        chip:SetScript("OnEnter", function(self)
            if self.id then VisualTooltip(self, self.id, self.cname, self.spell) end
        end)
        chip:SetScript("OnLeave", function() GameTooltip:Hide() end)
        chip:Hide()
        activeChips[i] = chip
    end
    for i = 1, 8 do MakeActiveChip(i) end

    local moreActive = activeCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    moreActive:SetPoint("LEFT", activeChips[#activeChips], "RIGHT", 6, 0)
    moreActive:SetTextColor(0.95, 0.78, 0.32)

    local function EnsureActiveChips(count)
        for i = #activeChips + 1, count do MakeActiveChip(i) end
    end

    local function LayoutActiveChips()
        local w = activeCard:GetWidth() or 0
        local count = math.floor((w - CHIP_X0 - 48) / CHIP_STEP)
        if count < 4 then count = 4 end
        if count > 24 then count = 24 end
        activeChipLimit = count
        EnsureActiveChips(count)
        for i, chip in ipairs(activeChips) do
            chip:ClearAllPoints()
            chip:SetPoint("LEFT", activeCard, "LEFT", CHIP_X0 + (i - 1) * CHIP_STEP, 0)
            if i > activeChipLimit then chip:Hide() end
        end
        moreActive:ClearAllPoints()
        moreActive:SetPoint("LEFT", activeChips[activeChipLimit], "RIGHT", 6, 0)
    end
    activeCard:SetScript("OnSizeChanged", function()
        LayoutActiveChips()
        if Refresh then Refresh() end
    end)
    LayoutActiveChips()

    -- --------------------------------------------------------------- toolbar
    local toolbar = MakeCard(parent)
    toolbar:SetPoint("TOPLEFT", activeCard, "BOTTOMLEFT", 0, -6)
    toolbar:SetPoint("TOPRIGHT", activeCard, "BOTTOMRIGHT", 0, -6)
    toolbar:SetHeight(38)

    local searchBar = ns.CreateSearchBar(toolbar, "Search all aura names or any ID...", 210, 26)
    searchBar:SetPoint("LEFT", 8, 0)
    searchBar.onTextChanged = function(text)
        filterText = text or ""
        ResetScroll()
        StartResolver(1)
        RebuildView()
        Refresh()
    end
    searchBar.editBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    local cbActiveOnly = ns.CreateCheckbox(toolbar, "Active only", "Show only visuals that are currently applied.")
    cbActiveOnly:SetPoint("LEFT", searchBar, "RIGHT", 10, 0)
    cbActiveOnly:SetScript("OnClick", function(self)
        activeOnly = self:GetChecked() and true or false
        ResetScroll()
        RebuildView()
        Refresh()
        PlaySound(activeOnly and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
    end)

    local btnClear = ns.CreateGoldenButton(nil, toolbar)
    btnClear:SetSize(84, 22)
    btnClear:SetPoint("RIGHT", -8, 0)
    btnClear:SetText("Remove All")
    btnClear:SetScript("OnClick", function()
        ns.Visuals_Clear()
        ResetScroll()
        RebuildView()
        Refresh()
        PlaySound("gsTitleOptionOK")
    end)

    -- ---------------------------------------------------------- behavior bar
    local behaviorBar = MakeCard(parent)
    behaviorBar:SetPoint("BOTTOMLEFT", 12, 8)
    behaviorBar:SetPoint("BOTTOMRIGHT", -12, 8)
    behaviorBar:SetHeight(38)

    local cbForever = ns.CreateCheckbox(behaviorBar, "|cffF5C842Persist across morphs/relogs|r",
        "Re-attach active auras after morphs, forms, zoning and relogs.")
    cbForever:SetPoint("LEFT", 10, 0)
    cbForever:SetScript("OnClick", function(self)
        S().visualsPersist = self:GetChecked() and true or false
        ns.Visuals_SyncAutoHeal()
        Refresh()
        PlaySound(self:GetChecked() and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
    end)

    local cbMute = ns.CreateCheckbox(behaviorBar, "Mute applied aura sounds",
        "Silence only the visuals applied from this tab; normal game sounds are untouched.")
    cbMute:SetPoint("LEFT", cbForever, "RIGHT", 230, 0)
    cbMute:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        S().visualsMuteSound = on
        send("VIS_MUTE:" .. (on and "1" or "0"))
        Refresh()
        PlaySound(on and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
    end)

    local loopHint = behaviorBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    loopHint:SetPoint("RIGHT", -12, 0)
    loopHint:SetJustifyH("RIGHT")
    loopHint:SetText("auras loop seamlessly - they never respawn")

    -- ------------------------------------------------------------- list card
    local listCard = MakeCard(parent)
    listCard:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -6)
    listCard:SetPoint("BOTTOMRIGHT", behaviorBar, "TOPRIGHT", 0, 6)

    local listFrame = CreateFrame("Frame", nil, listCard)
    listFrame:SetPoint("TOPLEFT", 6, -6)
    listFrame:SetPoint("BOTTOMRIGHT", -26, 6)
    scroll = CreateFrame("ScrollFrame", baseName .. "VisScroll", listFrame, "FauxScrollFrameTemplate")
    scroll:SetAllPoints()
    -- The FauxScrollFrame template ships chunky up/down arrow BUTTONS that float at the list's
    -- right edge and look like stray icons. Hide them and slim the scrollbar track; the list is
    -- driven by the mouse wheel (below) + the thin thumb, which is clean.
    local sbName = scroll:GetName() .. "ScrollBar"
    local scrollBar = _G[sbName]
    if scrollBar then
        local up, down = _G[sbName .. "ScrollUpButton"], _G[sbName .. "ScrollDownButton"]
        if up then up:SetAlpha(0); up:EnableMouse(false); up:SetWidth(1); up:SetHeight(1) end
        if down then down:SetAlpha(0); down:EnableMouse(false); down:SetWidth(1); down:SetHeight(1) end
        scrollBar:SetWidth(8)
    end
    -- Mouse wheel scrolls a page-row at a time across the whole list card.
    listFrame:EnableMouseWheel(true)
    listFrame:SetScript("OnMouseWheel", function(_, delta)
        local cur = FauxScrollFrame_GetOffset(scroll) or 0
        local totalRows = math.ceil(#view / COLS)
        local maxOff = math.max(0, totalRows - visRows)
        local nxt = math.min(maxOff, math.max(0, cur - delta))
        if nxt ~= cur then
            scrollPause = 0.30
            FauxScrollFrame_SetOffset(scroll, nxt)
            scroll:SetVerticalScroll(nxt * ROW_H)
            Refresh()
        end
    end)

    local emptyText = listCard:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("CENTER", listCard, "CENTER", 0, 0)
    emptyText:SetText("No visuals match this filter")

    local rows = {}
    local function MakeCell(rowFrame)
        local cell = CreateFrame("Button", nil, rowFrame)
        cell:SetHeight(ROW_H - 4)
        cell:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            tile = true, tileSize = 8, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        cell:SetBackdropColor(0.040, 0.042, 0.048, 0.88)
        cell:SetBackdropBorderColor(0.18, 0.18, 0.18, 0.9)
        cell:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        cell:GetHighlightTexture():SetVertexColor(0.85, 0.70, 0.25, 0.25)

        cell.activeGlow = cell:CreateTexture(nil, "BORDER")
        cell.activeGlow:SetPoint("TOPLEFT", 1, -1)
        cell.activeGlow:SetPoint("BOTTOMRIGHT", -1, 1)
        cell.activeGlow:SetTexture("Interface\\Buttons\\WHITE8x8")
        cell.activeGlow:SetBlendMode("ADD")
        cell.activeGlow:SetVertexColor(1, 0.72, 0.18, 0.18)
        cell.activeGlow:Hide()

        cell.edge = cell:CreateTexture(nil, "OVERLAY")
        cell.edge:SetWidth(3)
        cell.edge:SetPoint("TOPLEFT", 0, 0)
        cell.edge:SetPoint("BOTTOMLEFT", 0, 0)
        cell.edge:SetTexture("Interface\\Buttons\\WHITE8x8")
        cell.edge:SetVertexColor(1, 0.82, 0.20, 0.95)
        cell.edge:Hide()

        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetSize(32, 32)
        cell.icon:SetPoint("LEFT", 8, 0)
        cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        cell.iconBorder = cell:CreateTexture(nil, "BORDER")
        cell.iconBorder:SetPoint("TOPLEFT", cell.icon, -2, 2)
        cell.iconBorder:SetPoint("BOTTOMRIGHT", cell.icon, 2, -2)
        cell.iconBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        cell.iconBorder:SetVertexColor(0.45, 0.45, 0.45, 0.75)
        cell.iconGlow = cell:CreateTexture(nil, "OVERLAY")
        cell.iconGlow:SetPoint("TOPLEFT", cell.icon, -10, 10)
        cell.iconGlow:SetPoint("BOTTOMRIGHT", cell.icon, 10, -10)
        cell.iconGlow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        cell.iconGlow:SetBlendMode("ADD")
        cell.iconGlow:SetVertexColor(1, 0.74, 0.18, 0.85)
        cell.iconGlow:Hide()

        cell.name = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cell.name:SetPoint("TOPLEFT", cell.icon, "TOPRIGHT", 8, -1)
        cell.name:SetPoint("RIGHT", cell, "RIGHT", -72, 0)
        cell.name:SetJustifyH("LEFT")
        cell.name:SetWordWrap(false)

        cell.meta = cell:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        cell.meta:SetPoint("TOPLEFT", cell.name, "BOTTOMLEFT", 0, -3)
        cell.meta:SetPoint("RIGHT", cell.name, "RIGHT", 0, 0)
        cell.meta:SetJustifyH("LEFT")
        cell.meta:SetWordWrap(false)

        cell.status = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cell.status:SetPoint("RIGHT", -8, 0)
        cell.status:SetJustifyH("RIGHT")

        cell:SetScript("OnClick", function(self)
            if not self.id then return end
            local nowOn = ns.Visuals_Toggle(self.id)
            PlaySound(nowOn and "gsTitleOptionExpand" or "gsTitleOptionCollapse")
            if RefreshAll then RefreshAll() end
        end)
        cell:SetScript("OnEnter", function(self)
            if self.id then VisualTooltip(self, self.id, self.cname, self.spell) end
        end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return cell
    end

    local function EnsureRows(count)
        for r = #rows + 1, count do
            local rowFrame = CreateFrame("Frame", nil, listFrame)
            rowFrame:SetHeight(ROW_H)
            rowFrame:SetPoint("TOPLEFT", 0, -(r - 1) * ROW_H)
            rowFrame:SetPoint("RIGHT", 0, 0)
            local cells = {}
            rows[r] = { frame = rowFrame, cells = cells }
        end
        -- Top up cells for EVERY pooled row (not just 1..count): Refresh iterates the whole
        -- row pool against the current COLS, so a row created when COLS was smaller would
        -- otherwise be missing cells[c] and crash. Keeping all rows at COLS cells is cheap.
        for r = 1, #rows do
            local row = rows[r]
            for c = #row.cells + 1, COLS do
                row.cells[c] = MakeCell(row.frame)
            end
        end
    end
    EnsureRows(INITIAL_ROWS)

    local pulse = CreateFrame("Frame", nil, parent)
    pulse:Hide()
    pulse.t = 0
    pulse:SetScript("OnUpdate", function(self, elapsed)
        self.t = self.t + (elapsed or 0)
        local a = 0.12 + 0.11 * (0.5 + 0.5 * math.sin(self.t * 4.2))
        local halo = 0.48 + 0.28 * (0.5 + 0.5 * math.sin(self.t * 5.1))
        for _, row in ipairs(rows) do
            for _, cell in ipairs(row.cells) do
                if cell:IsShown() and cell.activeGlow:IsShown() then
                    cell.activeGlow:SetAlpha(a)
                    cell.iconGlow:SetAlpha(halo)
                end
            end
        end
        for _, chip in ipairs(activeChips) do
            if chip:IsShown() then chip.glow:SetAlpha(halo) end
        end
    end)

    local function UpdateActiveStrip()
        local activeList = BuildActiveList()
        if #activeList == 0 then activeNone:Show() else activeNone:Hide() end
        for i, chip in ipairs(activeChips) do
            local e = activeList[i]
            if e and i <= activeChipLimit then
                chip.id = e.id
                chip.spell = e.spell
                chip.cname = DisplayName(e)
                chip.icon:SetTexture(DisplayIcon(e))
                chip:Show()
            else
                chip.id = nil
                chip:Hide()
            end
        end
        if #activeList > activeChipLimit then
            moreActive:SetText("+" .. (#activeList - activeChipLimit) .. " more")
        else
            moreActive:SetText("")
        end
    end

    local function Layout()
        local h = listFrame:GetHeight() or 360
        local w = listFrame:GetWidth() or 560
        if h <= 0 then h = 360 end
        if w <= 0 then w = 560 end
        COLS = math.floor(w / 280)
        if COLS < 2 then COLS = 2 end
        if COLS > 4 then COLS = 4 end
        visRows = math.max(3, math.floor(h / ROW_H))
        EnsureRows(visRows)
        local cw = math.floor(w / COLS)
        for r = 1, #rows do
            local row = rows[r]
            if r <= visRows then row.frame:Show() else row.frame:Hide() end
            for c, cell in ipairs(row.cells) do
                if c <= COLS then
                    cell:ClearAllPoints()
                    cell:SetPoint("TOPLEFT", row.frame, "TOPLEFT", (c - 1) * cw + 2, -2)
                    cell:SetSize(cw - 6, ROW_H - 4)
                else
                    cell:Hide()
                end
            end
        end
    end

    Refresh = function()
        local activeCount = CountActive()
        if filterText ~= "" then
            countFs:SetText(string.format("|cff888888%d match%s|r", #view, #view == 1 and "" or "es"))
        else
            countFs:SetText(string.format("|cff888888%d visuals|r", #entries))
        end
        SetPill(activePill, activeCount .. " active", 0.45, activeCount > 0 and 1.00 or 0.45, 0.45)
        UpdateActiveStrip()
        emptyText:SetText((filterText ~= "" and resolver:IsShown()) and "Searching all auras..." or (filterText ~= "" and "No auras match this search" or "No visuals match this filter"))
        if #view == 0 then emptyText:Show() else emptyText:Hide() end
        if activeCount > 0 then pulse:Show() else pulse:Hide() end

        local offset = FauxScrollFrame_GetOffset(scroll) or 0
        local totalRows = math.ceil(#view / COLS)
        EnsureRows(visRows)
        for r = 1, #rows do
            for c = 1, COLS do
                local cell = rows[r].cells[c]
                local e = (r <= visRows) and view[(offset + r - 1) * COLS + c] or nil
                if not cell then
                    -- defensive: row pool/COLS mismatch should be impossible after EnsureRows,
                    -- but never let a missing cell crash the whole tab mid-resolve.
                elseif e then
                    local on = ns.Visuals_IsActive(e.id)
                    cell.id = e.id
                    cell.spell = e.spell
                    cell.cname = DisplayName(e)
                    cell.icon:SetTexture(DisplayIcon(e))
                    local nameLimit = math.floor(((cell:GetWidth() or 0) - 104) / 6)
                    if nameLimit < 28 then nameLimit = 28 end
                    cell.name:SetText(ShortText(cell.cname, nameLimit))
                    cell.meta:SetText("ID " .. e.id .. ((e.spell and e.spell > 0) and ("  |  Spell " .. e.spell) or ""))
                    if on then
                        cell.activeGlow:Show()
                        cell.edge:Show()
                        cell.iconGlow:Show()
                        cell:SetBackdropColor(0.105, 0.078, 0.030, 0.95)
                        cell:SetBackdropBorderColor(0.95, 0.72, 0.22, 0.95)
                        cell.iconBorder:SetVertexColor(1.0, 0.75, 0.22, 1)
                        cell.name:SetTextColor(1.0, 0.86, 0.34)
                        cell.meta:SetTextColor(0.74, 0.66, 0.46)
                        cell.status:SetText("|cff8fdc8fACTIVE|r")
                    else
                        cell.activeGlow:Hide()
                        cell.edge:Hide()
                        cell.iconGlow:Hide()
                        cell:SetBackdropColor(0.040, 0.042, 0.048, 0.88)
                        cell:SetBackdropBorderColor(0.18, 0.18, 0.18, 0.9)
                        cell.iconBorder:SetVertexColor(0.45, 0.45, 0.45, 0.75)
                        cell.name:SetTextColor(0.92, 0.90, 0.84)
                        cell.meta:SetTextColor(0.50, 0.50, 0.50)
                        cell.status:SetText("")
                    end
                    cell:Show()
                else
                    cell.id = nil
                    cell:Hide()
                end
            end
        end
        FauxScrollFrame_Update(scroll, totalRows, visRows, ROW_H)
    end
    RefreshAll = function()
        RebuildView()
        Refresh()
    end
    parent.RefreshVisuals = RefreshAll

    scroll:SetScript("OnVerticalScroll", function(self, off)
        scrollPause = 0.30
        FauxScrollFrame_OnVerticalScroll(self, off, ROW_H, Refresh)
    end)
    listFrame:SetScript("OnSizeChanged", function() Layout(); Refresh() end)

    function TransmorpherOnVisualsReady()
        ParseVisuals()
        ResetScroll()
        RebuildView()
        Layout()
        Refresh()
        StartResolver(1)
    end

    local function SyncControls()
        cbActiveOnly:SetChecked(activeOnly)
        cbForever:SetChecked(S().visualsPersist ~= false)
        cbMute:SetChecked(S().visualsMuteSound and true or false)
    end

    parent:SetScript("OnShow", function()
        SyncControls()
        Layout()
        if #entries == 0 then send("VIS_ENUM") else StartResolver() end
        RefreshAll()
    end)

    SyncControls()
    Layout()
    if #entries == 0 then send("VIS_ENUM") end
    RefreshAll()
end
