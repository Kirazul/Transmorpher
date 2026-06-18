local addon, ns = ...

-- ============================================================
-- TRANSMORPHER THEME SYSTEM  (Phase 1 UI overhaul)
-- ============================================================
-- Shared presentation factories. Every visual value lives in
-- ns.Colors / ns.Spacing / ns.Heights / ns.Theme / ns.Assets (see
-- Core\Constants.lua); this module only ASSEMBS frames from those tokens.
--
-- Contract:
--   * ADDITIVE only — every export is a new ns.* function. Nothing here
--     renames, replaces, or deletes existing helpers (ns.CreateGoldenButton,
--     ns.CreatePanel, ns.CreateSearchBar, ns.CreateSectionHeader ...).
--   * All frames/textures are parented to a caller-supplied parent. No frame
--     is ever created with UIParent here, so there are no orphaned frames and
--     nothing leaks when a parent tab is hidden/destroyed.
--   * 3.3.5a API only: CreateFrame, SetBackdrop, CreateTexture, SetPoint,
--     SetVertexColor, SetAlpha, SetFont, SetHighlightTexture. No C_Timer,
--     no Mixin, no retail backdrop templates.
--   * The smooth-color animation (ns.SmoothBackdropTo) lives in
--     UI\BottomButtons.lua and loads before this file in the TOC. We guard
--     every call so the theme still works if it isn't present yet.
-- ============================================================

local C = ns.Colors
local S = ns.Spacing
local H = ns.Heights
local T = ns.Theme
local A = ns.Assets

-- Safe unpack for the 4-tuple color tables used throughout this module.
local function rgba(t)
    return t[1], t[2], t[3], t[4] or 1
end

-- Apply a backdrop + a 1px top sheen + 1px bottom shadow to a frame, giving a
-- flat block the beveled "card" depth used across the UI. Optional.
local function applyCardDepth(frame, topSheen, bottomShadow)
    if topSheen == nil then topSheen = true end
    if bottomShadow == nil then bottomShadow = true end
    if topSheen then
        local top = frame:CreateTexture(nil, "OVERLAY")
        top:SetTexture(A.white)
        top:SetHeight(1)
        top:SetPoint("TOPLEFT", 1, -1)
        top:SetPoint("TOPRIGHT", -1, -1)
        top:SetVertexColor(rgba(C.textHighlight))
        top:SetAlpha(0.22)
        frame._themeTopSheen = top
    end
    if bottomShadow then
        local btm = frame:CreateTexture(nil, "OVERLAY")
        btm:SetTexture(A.white)
        btm:SetHeight(1)
        btm:SetPoint("BOTTOMLEFT", 1, 1)
        btm:SetPoint("BOTTOMRIGHT", -1, 1)
        btm:SetVertexColor(0, 0, 0, 0.70)
        frame._themeBottomShadow = btm
    end
end

-- ============================================================
-- FRAME STYLERS
-- Apply the theme to an EXISTING frame without re-creating it. Used to
-- modernize frames that other files own (MainFrame, dressing room, etc.).
-- ============================================================

-- Standard dark panel card: hairline gold border, mid-tone fill, subtle depth.
function ns.StylePanel(frame, opts)
    opts = opts or {}
    frame:SetBackdrop(T.panel)
    frame:SetBackdropColor(rgba(opts.fill or C.surfaceCard))
    frame:SetBackdropBorderColor(rgba(opts.border or C.borderHair))
    if opts.depth ~= false then applyCardDepth(frame, true, true) end
    return frame
end

-- Inset list well: darker fill, hairline gold border, no top sheen.
function ns.StyleWell(frame, opts)
    opts = opts or {}
    frame:SetBackdrop(T.well)
    frame:SetBackdropColor(rgba(opts.fill or C.surfaceWell))
    frame:SetBackdropBorderColor(rgba(opts.border or C.borderHair))
    return frame
end

-- Status / header bar: thin, slightly lighter, with a top sheen only.
function ns.StyleHeaderBar(frame, opts)
    opts = opts or {}
    frame:SetBackdrop(T.panel)
    frame:SetBackdropColor(rgba(opts.fill or C.surfaceInset))
    frame:SetBackdropBorderColor(rgba(opts.border or C.borderHair))
    applyCardDepth(frame, true, false)
    return frame
end

-- ============================================================
-- SECTION CARD
-- A titled panel card for scrollform panels (Morph/Color/Settings).
-- Replaces the hand-rolled "label + manual separator texture" pattern with a
-- single consistent component. Returns the card frame; children anchor to it.
--
--   local card = ns.CreateSection(scrollChild, "Character Morph", height)
--   someChild:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -38)
-- ============================================================
function ns.CreateSection(parent, titleText, height)
    local card = CreateFrame("Frame", nil, parent)
    card:SetHeight(height or 80)
    ns.StylePanel(card, { depth = true })

    -- Title sits in the top-left, with a hairline divider under it.
    local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", S.xl, -S.xl)
    title:SetText(titleText or "")
    title:SetTextColor(rgba(C.textAccent))
    title:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")

    local divider = card:CreateTexture(nil, "OVERLAY")
    divider:SetTexture(A.white)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", S.xl, -32)
    divider:SetPoint("TOPRIGHT", -S.xl, -32)
    divider:SetVertexColor(rgba(C.borderLine))
    divider:SetAlpha(0.65)

    card.title = title
    card.divider = divider
    return card
end

-- ============================================================
-- SEARCH FIELD
-- One consistent search field (icon + edit box + placeholder + clear button).
-- Replaces the four hand-rolled copies in Preview/Morph/Mounts/Spells tabs.
--
-- Hooks the caller can use (all optional):
--   field.onTextChanged  = function(text) ... end   -- fires on every keystroke
--   field.onEnterPressed = function(text) ... end
--   field.onClear        = function() ... end
-- ============================================================
function ns.CreateSearchField(parent, placeholder, width, height)
    width  = width or 220
    height = height or H.search

    local field = CreateFrame("Frame", nil, parent)
    field:SetSize(width, height)
    ns.StyleWell(field, { fill = C.inputRest, border = C.borderHair })

    -- Search glyph.
    local icon = field:CreateTexture(nil, "OVERLAY")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", S.lg, 0)
    icon:SetTexture(A.searchIcon)
    icon:SetVertexColor(rgba(C.goldOrange))

    -- Edit box fills the space between icon and clear button.
    local edit = CreateFrame("EditBox", nil, field)
    edit:SetPoint("LEFT", icon, "RIGHT", S.md, 0)
    edit:SetPoint("RIGHT", -22, 0)
    edit:SetHeight(18)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(60)
    edit:SetFont("Fonts\\FRIZQT__.TTF", 11)
    edit:SetTextColor(rgba(C.textPrimary))
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local hint = edit:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", S.xs, 0)
    hint:SetText(placeholder or "Search...")

    -- Clear (x) button.
    local clear = CreateFrame("Button", nil, field)
    clear:SetSize(14, 14)
    clear:SetPoint("RIGHT", -S.md, 0)
    clear:SetNormalTexture(A.searchClear)
    clear:SetAlpha(0.55)
    clear:Hide()

    -- Focus ring: border brightens while the edit box has focus.
    edit:SetScript("OnEditFocusGained", function()
        hint:Hide()
        if ns.SmoothBackdropTo then
            ns.SmoothBackdropTo(field, C.inputFocus, C.borderAccent)
        else
            field:SetBackdropBorderColor(rgba(C.borderAccent))
        end
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then hint:Show() end
        if ns.SmoothBackdropTo then
            ns.SmoothBackdropTo(field, C.inputRest, C.borderHair)
        else
            field:SetBackdropBorderColor(rgba(C.borderHair))
        end
    end)

    edit:SetScript("OnTextChanged", function(self, userInput)
        local text = self:GetText()
        if text == "" then hint:Show(); clear:Hide() else hint:Hide(); clear:Show() end
        if field.onTextChanged then field.onTextChanged(text, userInput) end
    end)
    edit:SetScript("OnEnterPressed", function(self)
        if field.onEnterPressed then field.onEnterPressed(self:GetText()) end
        self:ClearFocus()
    end)

    clear:SetScript("OnClick", function()
        edit:SetText("")
        edit:ClearFocus()
        hint:Show()
        clear:Hide()
        if field.onClear then field.onClear() end
    end)
    clear:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    clear:SetScript("OnLeave", function(self) self:SetAlpha(0.55) end)

    field.editBox   = edit
    field.icon      = icon
    field.clearBtn  = clear
    field.placeholder = hint

    -- Convenience pass-throughs so callers can treat the field like an EditBox.
    field.GetText  = function() return edit:GetText() end
    field.SetText  = function(_, t) edit:SetText(t) end
    field.SetFocus = function() edit:SetFocus() end
    field.ClearFocus = function() edit:ClearFocus() end

    return field
end

-- ============================================================
-- LIST ROW
-- A reusable, recyclable list row with optional icon, name, meta text, and a
-- trailing action slot. Built-in hover & selected states match the palette.
-- The caller provides data via row:SetData(data) and keeps its own OnClick;
-- this factory ONLY paints the row and manages highlight textures.
--
-- opts: { icon=14, actionW=90, nameW=240 } (all optional)
-- After creation:
--   row.icon  -> Texture (call row.icon:SetTexture(path))
--   row.name  -> FontString (left-aligned, gold)
--   row.meta  -> FontString (right-aligned, muted)  -- e.g. display ID
--   row.tag   -> FontString (after name, for type tags)
--   row.actionAnchor -> point ("RIGHT", -S.lg, 0) to attach a custom button
--   row:SetData(data) -> paints icon/name/meta/tag from a table with those keys
--   row:SetState("rest"|"hover"|"selected") -> manages the bg texture
-- ============================================================
function ns.CreateListRow(parent, opts)
    opts = opts or {}
    local iconSize = opts.icon or 24
    local nameW   = opts.nameW or 240
    local actionW = opts.actionW or 90
    local rowH    = opts.height or H.row

    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(rowH)

    -- Background swatch: the single texture whose vertex color encodes state.
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(A.white)
    bg:SetAllPoints()
    bg:SetVertexColor(rgba(C.rowRest))
    row.bg = bg

    -- Icon with a subtle slot border (client texture, looks like an action slot).
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("LEFT", S.lg, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local iconBorder = row:CreateTexture(nil, "OVERLAY")
    iconBorder:SetSize(iconSize + 2, iconSize + 2)
    iconBorder:SetPoint("CENTER", icon)
    iconBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    iconBorder:SetTexCoord(0.2, 0.8, 0.2, 0.8)
    iconBorder:SetAlpha(0.55)

    -- Name (gold, left aligned, fixed width so tags/ids line up in columns).
    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("LEFT", icon, "RIGHT", S.lg, 0)
    name:SetWidth(nameW)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetTextColor(rgba(C.textPrimary))

    -- Tag slot (e.g. [Fly]/[Gnd]); sits right after the name column.
    local tag = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tag:SetPoint("LEFT", name, "RIGHT", S.lg, 0)
    tag:SetJustifyH("LEFT")

    -- Meta (right-aligned muted text, e.g. display ID).
    local meta = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    meta:SetPoint("RIGHT", -actionW - S.lg, 0)
    meta:SetJustifyH("RIGHT")
    meta:SetTextColor(rgba(C.textMutedGold))

    -- Anchor point for a caller-attached action button (right edge).
    row.actionAnchor = { "RIGHT", -S.lg, 0 }

    row.icon = icon
    row.name = name
    row.tag  = tag
    row.meta = meta

    -- State machine. Tracks whether the caller has marked this row selected so
    -- hover doesn't clobber the selected highlight.
    row._selected = false

    function row:SetState(state)
        if state == "selected" then
            bg:SetVertexColor(rgba(C.rowSelected))
            self._selected = true
        elseif state == "hover" then
            bg:SetVertexColor(rgba(C.rowHover))
        else -- rest
            bg:SetVertexColor(rgba(self._stripe and C.rowStripe or C.rowRest))
        end
    end

    function row:SetStripe(on)
        self._stripe = on and true or false
        if not self._selected then bg:SetVertexColor(rgba(on and C.rowStripe or C.rowRest)) end
    end

    function row:SetSelected(on)
        self._selected = on and true or false
        self:SetState(on and "selected" or "rest")
    end

    -- Paint from a data table. Missing keys are ignored.
    function row:SetData(data)
        if not data then return end
        if data.icon     then icon:SetTexture(data.icon) end
        if data.name     then name:SetText(data.name) end
        if data.tag      then tag:SetText(data.tag) end
        if data.meta     then meta:SetText(data.meta) end
    end

    -- Default hover behavior. Callers with custom OnEnter/OnLeave should call
    -- row:SetState manually, but this default covers the common case.
    row:SetScript("OnEnter", function()
        if not row._selected then row:SetState("hover") end
    end)
    row:SetScript("OnLeave", function()
        if not row._selected then row:SetState("rest") end
    end)

    return row
end

-- ============================================================
-- FILTER CHIP
-- A compact toggle button for filter rows (All / Gnd / Fly, etc.).
-- Managed state via chip:SetActive(bool).
-- ============================================================
function ns.CreateChip(parent, text, onClick)
    local chip = CreateFrame("Button", nil, parent)
    chip:SetHeight(H.chip)

    local bg = chip:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(A.white)
    bg:SetAllPoints()
    bg:SetVertexColor(1, 1, 1, 0.05)

    local label = chip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText(text)
    label:SetTextColor(rgba(C.textMutedGold))

    chip.bg    = bg
    chip.label = label

    function chip:SetActive(active)
        self._active = active and true or false
        if active then
            bg:SetVertexColor(rgba(C.goldOrange))
            bg:SetAlpha(0.30)
            label:SetTextColor(rgba(C.textHighlight))
        else
            bg:SetVertexColor(1, 1, 1, 0.05)
            bg:SetAlpha(1)
            label:SetTextColor(rgba(C.textMutedGold))
        end
    end

    chip:SetScript("OnEnter", function()
        if not chip._active then
            bg:SetVertexColor(rgba(C.goldOrange))
            bg:SetAlpha(0.12)
        end
    end)
    chip:SetScript("OnLeave", function()
        if not chip._active then chip:SetActive(false) end
    end)
    chip:SetScript("OnClick", function()
        if onClick then onClick(chip) end
    end)

    return chip
end

-- ============================================================
-- ICON BUTTON
-- A square icon button (minimap-style toggle, eye, sheathe, etc.) with hover.
-- ============================================================
function ns.CreateIconButton(parent, size)
    size = size or 22
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size - 4, size - 4)
    icon:SetPoint("CENTER")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture(A.highlightBand)
    highlight:SetAllPoints()
    highlight:SetVertexColor(rgba(C.goldOrange))
    highlight:SetAlpha(0.30)

    btn.icon = icon
    btn:SetHighlightTexture(highlight)
    return btn
end

-- ============================================================
-- ITEM TILE STYLING  (retail-wardrobe feel for the preview grid)
-- Styles an EXISTING DressingRoom tile frame with the three item_bg textures
-- as background states + a gold selection border. This is the single biggest
-- visual upgrade for browsing tabs (Preview/Spells/Mounts/Pets/CPets).
--
--   ns.StyleItemTile(dressingRoomFrame)
--   dressingRoomFrame:SetTileState("normal"|"hover"|"selected")
--
-- The frame keeps whatever backdrop/border it already had; we layer the tile
-- textures UNDER the model so the DressUpModel still renders on top.
-- ============================================================
function ns.StyleItemTile(frame)
    if frame._themeTileStyled then return frame end
    frame._themeTileStyled = true

    -- Normal tile sits at the bottom of the BACKGROUND layer.
    local normal = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    normal:SetTexture(A.tileNormal)
    normal:SetAllPoints()
    normal:SetVertexColor(1, 1, 1, 1)

    local hover = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
    hover:SetTexture(A.tileHover)
    hover:SetAllPoints()
    hover:Hide()

    local selected = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
    selected:SetTexture(A.tileSelected)
    selected:SetAllPoints()
    selected:Hide()

    -- Gold selection hairline, drawn ABOVE the tile but below the model. Using
    -- a border texture rather than the backdrop edge lets us toggle it without
    -- disturbing the frame's existing backdrop.
    local selBorder = frame:CreateTexture(nil, "BORDER", nil, -5)
    selBorder:SetTexture(A.white)
    selBorder:SetAllPoints()
    selBorder:SetVertexColor(rgba(C.borderGlow))
    selBorder:Hide()

    frame._tileNormal   = normal
    frame._tileHover    = hover
    frame._tileSelected = selected
    frame._tileBorder   = selBorder

    function frame:SetTileState(state)
        if state == "selected" then
            normal:Hide(); hover:Hide(); selected:Show(); selBorder:Show()
        elseif state == "hover" then
            normal:Hide(); hover:Show(); selected:Hide(); selBorder:Hide()
        else -- normal
            normal:Show(); hover:Hide(); selected:Hide(); selBorder:Hide()
        end
    end

    return frame
end

-- ============================================================
-- SCROLLBAR STYLING
-- Tints a UIPanelScrollFrameTemplate / FauxScrollFrameTemplate scrollbar to
-- the gold theme. Best-effort: silently no-ops if the child buttons aren't
-- found (some templates name them differently).
-- ============================================================
function ns.StyleScrollBar(scrollFrame)
    if not scrollFrame then return end

    -- UIPanelScrollFrameTemplate exposes $parentScrollUpButton etc. as globals.
    local name = scrollFrame:GetName()
    local function tintButton(btnName, isThumb)
        if not btnName then return end
        local btn = _G[btnName]
        if not btn then return end
        local tex = btn.GetNormalTexture and btn:GetNormalTexture(btn)
        if tex and tex.SetVertexColor then
            tex:SetVertexColor(rgba(C.goldOrange))
        end
        if isThumb then return end
        local hi = btn.GetHighlightTexture and btn:GetHighlightTexture(btn)
        if hi and hi.SetVertexColor then
            hi:SetVertexColor(rgba(C.goldLight))
        end
    end

    if name then
        tintButton(name.."ScrollUpButton")
        tintButton(name.."ScrollDownButton")
        tintButton(name.."ThumbTexture", true)
    end
    return scrollFrame
end

-- ============================================================
-- DIVIDER
-- A 1px hairline used between sections inside scrollforms.
-- ============================================================
function ns.CreateDivider(parent)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(A.white)
    line:SetHeight(1)
    line:SetVertexColor(rgba(C.borderLine))
    line:SetAlpha(0.65)
    return line
end
