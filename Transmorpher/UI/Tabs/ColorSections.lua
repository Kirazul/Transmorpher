local addon, ns = ...

-- ============================================================
-- COLOR SECTIONS  (Colors tab > Creatures / Saved   +  Mounts tab "Color" button)
--
--   Recolor ANY creature/mount skin the client renders. Every BLP the engine loads
--   passes the DLL's 4 texture hooks, so the same engine that recolors worn gear
--   (Preview > Skin) recolors creatures and mounts too. Discovery of WHICH blp:
--     * Resolved from the DBC on demand (CREATURE_SKINS): CreatureDisplayInfo.
--       textureVariation + CreatureModelData directory, with a model-name fallback
--       for baked-skin creatures (e.g. special mounts like Invincible).
--     * Creatures are a full static list (~15k) with lazy 100-at-a-time loading,
--       search, and NPCs / Bosses / Normal filters (verifiable, via CREATURE_CATS).
--     * Mounts are colored straight from the existing Mounts tab (per-row "Color"
--       button -> ns.OpenColorAssetForCreature), not a separate sub-tab.
--     * Saved — every active recolor, persisted account-wide
--       (TransmorpherSettings.colorAssets) and re-applied on login & zone.
--
--   Each entry gets a Customize-Color popup (Solid / Gradient / Rainbow / Two-Tone
--   + intensity, glow, contrast, spread, brightness, saturation, hue) identical to
--   the Skin tab. Active entries glow; the Saved tab gathers them all.
-- ============================================================

if not (ns.mainFrame and ns.mainFrame.tabs and ns.mainFrame.tabs.color) then return end
if not ns.RegisterColorSection then return end

local function Send(cmd)
    if ns.IsMorpherReady and ns.IsMorpherReady() then
        if ns.SendRawMorphCommand then ns.SendRawMorphCommand(cmd); return true
        elseif ns.SendMorphCommand then ns.SendMorphCommand(cmd); return true end
    end
    return false
end

-- ----- account-wide persistence --------------------------------
-- TransmorpherSettings.colorAssets.records[recKey] = {
--   kind="creature"|"capture", section="mounts"|..., key, name,
--   paths = { "...blp", ... }, tint = {effect}, swap = { to=, toName= } }
local function CA()
    local s = ns.GetAccountSettings()
    if type(s.colorAssets) ~= "table" then s.colorAssets = {} end
    if type(s.colorAssets.records) ~= "table" then s.colorAssets.records = {} end
    return s.colorAssets
end
local function Records() return CA().records end

-- ----- tint model (mirrors Preview > Skin) ----------------------
local function NormalizeTint(t)
    t = t or {}
    if t.enabled    == nil then t.enabled    = false end
    if t.mode       == nil then t.mode       = 0  end
    if t.r          == nil then t.r          = 255 end
    if t.g          == nil then t.g          = 80  end
    if t.b          == nil then t.b          = 80  end
    if t.r2         == nil then t.r2         = 60  end
    if t.g2         == nil then t.g2         = 120 end
    if t.b2         == nil then t.b2         = 255 end
    if t.dir        == nil then t.dir        = 0   end
    if t.mult       == nil then t.mult       = 130 end
    if t.glowStr    == nil then t.glowStr    = 0   end
    if t.contrast   == nil then t.contrast   = 100 end
    if t.span       == nil then t.span       = 100 end
    if t.phase      == nil then t.phase      = 0   end
    if t.brightness == nil then t.brightness = 128 end
    if t.saturation == nil then t.saturation = 0   end
    if t.hueShift   == nil then t.hueShift   = 0   end
    return t
end

local function EncodeTint(t)
    t = NormalizeTint(t)
    local mult = math.max(0, math.min(400, math.floor(t.mult or 130)))
    return ("%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d"):format(
        t.mode or 0, t.r or 255, t.g or 255, t.b or 255,
        t.r2 or 0, t.g2 or 0, t.b2 or 0, t.dir or 0, mult,
        t.glowStr or 0, t.contrast or 100, t.span or 100, math.floor(t.phase or 0) % 256,
        math.max(0, math.min(255, math.floor(t.brightness or 128))),
        math.max(-100, math.min(100, math.floor(t.saturation or 0))),
        math.floor(t.hueShift or 0) % 256)
end

-- ----- apply / reset --------------------------------------------
-- Swap and Tint are mutually exclusive per path (both key on the same path in the
-- DLL): the active one wins, the other is cleared first so there is never a clash.
local function ApplyRec(rec)
    if not rec or not rec.paths then return end
    for _, p in ipairs(rec.paths) do
        if p and p ~= "" then
            Send("PATHTINT_DEL:" .. p)
            Send("TEXSWAP_DEL:" .. p)
            if rec.swap and rec.swap.to and rec.swap.to ~= "" then
                Send("TEXSWAP:" .. p .. "*" .. rec.swap.to)
            elseif rec.tint and rec.tint.enabled then
                Send("PATHTINT:" .. p .. "*" .. EncodeTint(rec.tint))
            end
        end
    end
end

local function RecActive(rec)
    return rec and ((rec.tint and rec.tint.enabled) or (rec.swap and rec.swap.to and rec.swap.to ~= "")) and true or false
end

local function ResetRec(recKey)
    local rec = Records()[recKey]
    if rec and rec.paths then
        for _, p in ipairs(rec.paths) do
            if p and p ~= "" then Send("PATHTINT_DEL:" .. p); Send("TEXSWAP_DEL:" .. p) end
        end
    end
    Records()[recKey] = nil
end

-- Re-push every saved asset recolor to the DLL (login / DLL-ready / zone change).
function ns.ColorAssets_ApplyAll()
    for _, rec in pairs(Records()) do
        if RecActive(rec) then ApplyRec(rec) end
    end
end

function ns.ColorAssets_ResetAll()
    Send("PATHTINT_CLEAR"); Send("TEXSWAP_CLEAR")
    local r = Records()
    for k in pairs(r) do r[k] = nil end
end

do  -- re-apply on entering the world (the engine drops its texture cache on zone/reload)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function() if ns.RunAfter then ns.RunAfter(0.6, ns.ColorAssets_ApplyAll) else ns.ColorAssets_ApplyAll() end end)
end

-- ----- creature/mount skin-path resolution (async via the DLL) --------------
local function ResolveCreaturePaths(displayId, cb)
    if not Send("CREATURE_SKINS:" .. displayId) then cb(nil); return end
    TRANSMORPHER_CREATURE_SKIN = nil
    local tries = 0
    local function check()
        local s = TRANSMORPHER_CREATURE_SKIN
        if type(s) == "table" and s.d == displayId and type(s.p) == "table" and #s.p > 0 then
            cb(s.p, s); return
        end
        tries = tries + 1
        if tries < 24 and ns.RunAfter then ns.RunAfter(0.05, check) else cb(nil) end
    end
    if ns.RunAfter then ns.RunAfter(0.05, check) else check() end
end

-- ============================================================
-- Shared Customize-Color popup (one instance, reused by every section)
-- ============================================================
local function OpenColorPicker(r, g, b, onChange)
    local function apply()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        onChange(math.floor(nr*255+0.5), math.floor(ng*255+0.5), math.floor(nb*255+0.5))
    end
    ColorPickerFrame.func = apply
    ColorPickerFrame.swatchFunc = apply
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.previousValues = { r = r/255, g = g/255, b = b/255 }
    ColorPickerFrame.cancelFunc = function(prev)
        if prev then onChange(math.floor(prev.r*255+0.5), math.floor(prev.g*255+0.5), math.floor(prev.b*255+0.5)) end
    end
    ColorPickerFrame:SetColorRGB(r/255, g/255, b/255)
    ColorPickerFrame:Hide(); ColorPickerFrame:Show()
    ColorPickerFrame:SetFrameStrata("TOOLTIP"); ColorPickerFrame:SetToplevel(true); ColorPickerFrame:Raise()
    if OpacitySliderFrame then OpacitySliderFrame:SetFrameStrata("TOOLTIP"); OpacitySliderFrame:Raise() end
end

local customizer
local function BuildCustomizer()
    local f = CreateFrame("Frame", "TM_ColorAsset_Customizer", UIParent)
    f:SetSize(372, 420); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true); f:Hide()
    f:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    f:SetBackdropColor(0.05, 0.05, 0.06, 0.98); f:SetBackdropBorderColor(0.8, 0.65, 0.3, 1)
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetPoint("CENTER")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); title:SetPoint("TOPLEFT", 14, -12); title:SetTextColor(1, 0.82, 0.2); f.title = title
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)

    local function T() return f.tint end
    local function Commit() if f.onChange then f.onChange() end; if f.Refresh then f.Refresh() end end

    local enableCb = CreateFrame("CheckButton", nil, f, "ChatConfigCheckButtonTemplate")
    enableCb:SetPoint("TOPLEFT", 12, -32); enableCb:SetSize(24, 24)
    if ns.NormalizeCheckboxHitRect then ns.NormalizeCheckboxHitRect(enableCb) end
    local enLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); enLbl:SetPoint("LEFT", enableCb, "RIGHT", 2, 0); enLbl:SetText("Enable color")
    enableCb:SetScript("OnClick", function() local t = T(); if not t then return end; t.enabled = enableCb:GetChecked() and true or false; Commit() end)
    f.enableCb = enableCb

    local modeNames = { [0] = "Solid", [1] = "Gradient", [2] = "Rainbow", [3] = "Two-Tone" }
    f.modeBtns = {}
    local mlabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); mlabel:SetPoint("TOPLEFT", 14, -62); mlabel:SetText("Effect")
    for i = 0, 3 do
        local mb = ns.CreateGoldenButton(nil, f); mb:SetSize(84, 22)
        mb:SetPoint("TOPLEFT", 14 + (i % 2) * 92, -76 - math.floor(i / 2) * 24)
        mb:SetText(modeNames[i])
        mb:SetScript("OnClick", function() local t = T(); if not t then return end; t.mode = i; t.enabled = true; Commit() end)
        f.modeBtns[i] = mb
    end

    local function MakeSwatch(label, x, y, getf, setf)
        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); lbl:SetPoint("TOPLEFT", x, y); lbl:SetText(label)
        local sw = CreateFrame("Button", nil, f); sw:SetSize(46, 18); sw:SetPoint("TOPLEFT", x, y - 14)
        sw:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }); sw:SetBackdropBorderColor(0.8, 0.7, 0.3, 1)
        sw:SetScript("OnClick", function() local t = T(); if not t then return end
            local r, g, b = getf(t); OpenColorPicker(r, g, b, function(nr, ng, nb) setf(t, nr, ng, nb); t.enabled = true; Commit() end) end)
        return sw, lbl
    end
    f.sw1 = MakeSwatch("Color", 212, -62, function(t) return t.r, t.g, t.b end, function(t, r, g, b) t.r, t.g, t.b = r, g, b end)
    f.sw2, f.sw2lbl = MakeSwatch("Color 2", 286, -62, function(t) return t.r2, t.g2, t.b2 end, function(t, r, g, b) t.r2, t.g2, t.b2 = r, g, b end)

    local dirNames = { [0] = "Vert", [1] = "Horiz", [2] = "Diag" }
    f.dirBtns = {}
    f.dlbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.dlbl:SetPoint("TOPLEFT", 14, -128); f.dlbl:SetText("Direction")
    for i = 0, 2 do
        local db = ns.CreateGoldenButton(nil, f); db:SetSize(66, 20); db:SetPoint("TOPLEFT", 14 + (i % 3) * 72, -144)
        db:SetText(dirNames[i]); db:SetScript("OnClick", function() local t = T(); if not t then return end; t.dir = i; t.enabled = true; Commit() end)
        f.dirBtns[i] = db
    end

    local function MakeSlider(field, lo, hi, fmt)
        local s = CreateFrame("Slider", "TM_ColorAsset_Sl_" .. field, f, "OptionsSliderTemplate")
        s:SetWidth(336); s:SetMinMaxValues(lo, hi); s:SetValueStep(1)
        _G[s:GetName() .. "Low"]:SetText(""); _G[s:GetName() .. "High"]:SetText("")
        local txt = _G[s:GetName() .. "Text"]
        s:SetScript("OnValueChanged", function(self, v)
            v = math.floor(v + 0.5); local t = T(); txt:SetText(fmt:format(v)); if not t then return end
            t[field] = v; if not self._silent then t.enabled = true; Commit() end
        end)
        s.txt = txt; return s
    end
    f.slMult     = MakeSlider("mult",      50, 250, "Intensity  %d%%")
    f.slGlow     = MakeSlider("glowStr",   0, 255,  "Glow  %d")
    f.slContrast = MakeSlider("contrast",  50, 300, "Contrast  %d%%")
    f.slSpan     = MakeSlider("span",      30, 400, "Rainbow spread  %d%%")
    f.slPhase    = MakeSlider("phase",     0, 255,  "Color shift  %d")
    f.slBrightness = MakeSlider("brightness", 0, 255, "Brightness  %d")
    f.slSaturation = MakeSlider("saturation", -100, 100, "Saturation  %d")
    f.slHueShift   = MakeSlider("hueShift",   0, 255, "Hue shift  %d")
    f._sliderRows = {
        { s = f.slMult }, { s = f.slGlow }, { s = f.slContrast },
        { s = f.slSpan,  vis = function(t) return t.mode == 2 end },
        { s = f.slPhase, vis = function(t) return t.mode ~= 0 end },
        { s = f.slBrightness }, { s = f.slSaturation }, { s = f.slHueShift },
    }

    local DEFAULTS = { mult = 130, glowStr = 0, contrast = 100, span = 100, phase = 0, brightness = 128, saturation = 0, hueShift = 0 }
    local rbDefaults = ns.CreateGoldenButton(nil, f); rbDefaults:SetSize(140, 24)
    rbDefaults:SetPoint("BOTTOMLEFT", 14, 12); rbDefaults:SetText("Restore Defaults")
    rbDefaults:SetScript("OnClick", function() local t = T(); if not t then return end
        for k, v in pairs(DEFAULTS) do t[k] = v end; t.enabled = true; Commit() end)

    local rb = ns.CreateGoldenButton(nil, f); rb:SetSize(190, 24)
    rb:SetPoint("BOTTOMRIGHT", -14, 12); rb:SetText("Turn Off Color")
    rb:SetScript("OnClick", function() local t = T(); if not t then return end; t.enabled = false; Commit() end)

    local function setSil(s, v) s._silent = true; s:SetValue(v); s._silent = false; s.txt:SetText(s.txt:GetText()) end
    function f.Refresh()
        local t = T(); if not t then return end
        f.title:SetText("Customize Color \226\128\148 " .. (f.label or ""))
        f.enableCb:SetChecked(t.enabled and true or false)
        f.sw1:SetBackdropColor(t.r / 255, t.g / 255, t.b / 255, 1)
        f.sw2:SetBackdropColor(t.r2 / 255, t.g2 / 255, t.b2 / 255, 1)
        local twoCol = (t.mode == 1 or t.mode == 3)
        if twoCol then f.sw2:Show(); f.sw2lbl:Show() else f.sw2:Hide(); f.sw2lbl:Hide() end
        local hasDir = (t.mode == 1 or t.mode == 2 or t.mode == 3)
        if hasDir then f.dlbl:Show(); for i = 0, 2 do f.dirBtns[i]:Show() end else f.dlbl:Hide(); for i = 0, 2 do f.dirBtns[i]:Hide() end end
        setSil(f.slMult, t.mult); setSil(f.slGlow, t.glowStr); setSil(f.slContrast, t.contrast)
        setSil(f.slSpan, t.span); setSil(f.slPhase, t.phase)
        setSil(f.slBrightness, t.brightness); setSil(f.slSaturation, t.saturation); setSil(f.slHueShift, t.hueShift)
        local PITCH = 32
        local y = hasDir and -188 or -140
        for _, row in ipairs(f._sliderRows) do
            if (not row.vis) or row.vis(t) then
                row.s:ClearAllPoints(); row.s:SetPoint("TOPLEFT", 18, y); row.s:Show(); y = y - PITCH
            else row.s:Hide() end
        end
        local lastBottom = (y + PITCH) - 18
        f:SetHeight(math.floor(-lastBottom + 14 + 24 + 14 + 0.5))
        for i = 0, 3 do local on = (i == t.mode)
            if f.modeBtns[i].SetBackdropBorderColor then f.modeBtns[i]:SetBackdropBorderColor(on and 1 or 0.45, on and 0.82 or 0.38, on and 0.2 or 0.12, 1) end end
        for i = 0, 2 do local on = (i == t.dir)
            if f.dirBtns[i].SetBackdropBorderColor then f.dirBtns[i]:SetBackdropBorderColor(on and 1 or 0.45, on and 0.82 or 0.38, on and 0.2 or 0.12, 1) end end
    end
    customizer = f
    return f
end

local function OpenCustomizer(tint, label, onChange)
    local f = customizer or BuildCustomizer()
    f.tint = NormalizeTint(tint); f.label = label; f.onChange = onChange
    f.Refresh(); f:Show(); f:Raise()
end

-- ============================================================
-- Sub-sub-tab strip (filters) — glowing pills under a section's header
-- ============================================================
local function BuildFilterStrip(parent, anchorBelow, items, onSelect)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetPoint("TOPLEFT", anchorBelow, "BOTTOMLEFT", 4, -4)
    strip:SetPoint("TOPRIGHT", anchorBelow, "BOTTOMRIGHT", -4, -4)
    strip:SetHeight(22)
    strip.btns = {}
    local function SetActive(idx)
        strip.active = idx
        for i, b in ipairs(strip.btns) do
            local on = (i == idx)
            b:SetBackdropColor(on and 0.20 or 0.07, on and 0.16 or 0.07, on and 0.05 or 0.07, on and 0.95 or 0.6)
            b:SetBackdropBorderColor(on and 0.95 or 0.30, on and 0.78 or 0.26, on and 0.26 or 0.14, on and 1 or 0.8)
            b.fs:SetTextColor(on and 1 or 0.62, on and 0.84 or 0.58, on and 0.40 or 0.38)
        end
    end
    local x = 0
    for i, it in ipairs(items) do
        local b = CreateFrame("Button", nil, strip)
        b:SetHeight(20)
        b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); fs:SetPoint("CENTER"); fs:SetText(it.name); b.fs = fs
        b:SetWidth(math.max(48, fs:GetStringWidth() + 18))
        b:SetPoint("LEFT", x, 0); x = x + b:GetWidth() + 3
        b:SetScript("OnClick", function() SetActive(i); onSelect(it) end)
        strip.btns[i] = b
    end
    strip.SetActive = SetActive
    return strip
end

-- ============================================================
-- Generic section builder — header + filter strip + search + row list.
-- cfg = {
--   title, desc, sectionKey, kind="creature"|"capture"|"saved",
--   getEntries = function() -> { {key, name, displayId?, path?, sub?, cat?} },
--   resolve    = function(entry, cb)  -- cb(paths[])  (saved skips: rec has paths)
--   filters    = { {name, match=function(entry) end}, ... }  -- optional sub-sub-tabs
--   capture    = bool   -- show Start/Stop scan controls
--   onInit     = function()  -- optional one-time setup (e.g. request CCAT)
-- }
-- ============================================================
local _sectionSerial = 0
local function BuildSection(container, cfg)
    _sectionSerial = _sectionSerial + 1
    local uid = "TM_ColorSec" .. _sectionSerial

    -- header
    local header = CreateFrame("Frame", nil, container)
    header:SetPoint("TOPLEFT", 6, -6); header:SetPoint("TOPRIGHT", -6, -6); header:SetHeight(44)
    header:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    header:SetBackdropColor(0.08, 0.08, 0.08, 0.95); header:SetBackdropBorderColor(0.35, 0.30, 0.18, 0.9)
    local hTitle = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hTitle:SetPoint("TOPLEFT", 12, -6); hTitle:SetTextColor(1.0, 0.84, 0.40); hTitle:SetText(cfg.title)
    local hDesc = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hDesc:SetPoint("TOPLEFT", hTitle, "BOTTOMLEFT", 0, -3); hDesc:SetPoint("RIGHT", header, "RIGHT", -220, 0)
    hDesc:SetJustifyH("LEFT"); hDesc:SetWordWrap(false); hDesc:SetTextColor(0.78, 0.78, 0.78); hDesc:SetText(cfg.desc or "")

    local resetAll = ns.CreateGoldenButton(nil, header); resetAll:SetSize(96, 22); resetAll:SetPoint("RIGHT", -10, 0); resetAll:SetText("Reset All")
    local scanBtn
    if cfg.capture then
        scanBtn = ns.CreateGoldenButton(nil, header); scanBtn:SetSize(108, 22)
        scanBtn:SetPoint("RIGHT", resetAll, "LEFT", -8, 0); scanBtn:SetText("Start Scan")
    end

    -- filter strip (sub-sub-tabs)
    local strip, currentFilter
    if cfg.filters and #cfg.filters > 0 then
        currentFilter = cfg.filters[1]
        strip = BuildFilterStrip(container, header, cfg.filters, function(it) currentFilter = it; if container._resetPage then container._resetPage() end; container._repopulate() end)
    end

    -- search
    local searchBox = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    searchBox:SetHeight(20)
    searchBox:SetPoint("TOPLEFT", (strip or header), "BOTTOMLEFT", (strip and 8 or 12), -6)
    searchBox:SetPoint("TOPRIGHT", (strip or header), "BOTTOMRIGHT", (strip and -4 or -10), -6)
    searchBox:SetAutoFocus(false); searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local searchHint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", 4, 0); searchHint:SetText("Search...")
    searchBox:SetScript("OnEditFocusGained", function() searchHint:Hide() end)
    searchBox:SetScript("OnEditFocusLost", function(self) if self:GetText() == "" then searchHint:Show() end end)

    -- list
    local scroll = CreateFrame("ScrollFrame", uid .. "Scroll", container, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -2, -8); scroll:SetPoint("BOTTOMRIGHT", -28, 10)
    local content = CreateFrame("Frame", nil, scroll); content:SetSize(10, 10); scroll:SetScrollChild(content)
    local rows = {}
    local ROW_H = 24
    local countLbl = container:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    countLbl:SetPoint("BOTTOMRIGHT", scroll, "TOPRIGHT", -2, 2); countLbl:SetJustifyH("RIGHT")

    local entries = {}
    local PAGE = 100              -- lazy loading: render this many at a time
    local renderLimit = PAGE
    local function RebuildEntries() entries = cfg.getEntries() or {} end

    local function CommitRec(rec, row)
        ApplyRec(rec)
        if row then row.refresh() end
    end

    -- Resolve (if needed) the BLP paths for an entry, then run fn(rec).
    local function WithRec(entry, fn)
        local recs = Records()
        local rec = recs[entry.key]
        if rec and rec.paths and #rec.paths > 0 then fn(rec); return end
        if entry.rec and entry.rec.paths then recs[entry.key] = entry.rec; fn(entry.rec); return end
        cfg.resolve(entry, function(paths)
            if not paths or #paths == 0 then
                if ns.EnhPrint then ns.EnhPrint("No colorable skin found for: " .. (entry.name or "?")) end
                return
            end
            rec = recs[entry.key] or { kind = cfg.kind, section = cfg.sectionKey, key = entry.key, name = entry.name }
            rec.paths = paths
            rec.tint = NormalizeTint(rec.tint)
            recs[entry.key] = rec
            fn(rec)
        end)
    end

    -- "Load more" button lives at the bottom of the content when results exceed the
    -- current render limit (lazy loading keeps even the ~15k creature list snappy).
    local loadMore = ns.CreateGoldenButton(nil, content)
    loadMore:SetSize(200, 22); loadMore:Hide()

    local function Populate()
        local ft = (searchBox:GetText() or ""):lower()
        for _, r in ipairs(rows) do r:Hide() end
        local shown, total = 0, 0
        for _, e in ipairs(entries) do
            local pass = (not currentFilter) or (not currentFilter.match) or currentFilter.match(e)
            if pass then
                local nm = (e.name or ""):lower()
                if ft == "" or nm:find(ft, 1, true) or tostring(e.displayId or ""):find(ft, 1, true) then
                    total = total + 1
                    if shown < renderLimit then
                        shown = shown + 1
                        local row = rows[shown]
                        if not row then
                            row = CreateFrame("Frame", nil, content); row:SetSize(560, ROW_H)
                            row:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
                            row:SetBackdropColor(0.05, 0.05, 0.05, 0.6); row:SetBackdropBorderColor(0.18, 0.18, 0.18, 1)
                            row.chip = row:CreateTexture(nil, "OVERLAY"); row.chip:SetSize(12, 12); row.chip:SetPoint("LEFT", 6, 0); row.chip:SetTexture("Interface\\Buttons\\WHITE8X8"); row.chip:Hide()
                            row.t = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); row.t:SetPoint("LEFT", 22, 0); row.t:SetJustifyH("LEFT"); row.t:SetWordWrap(false)
                            row.reset = ns.CreateGoldenButton(nil, row); row.reset:SetSize(48, 20); row.reset:SetPoint("RIGHT", -4, 0); row.reset:SetText("Reset")
                            row.color = ns.CreateGoldenButton(nil, row); row.color:SetSize(64, 20); row.color:SetPoint("RIGHT", row.reset, "LEFT", -4, 0); row.color:SetText("Color")
                            rows[shown] = row
                        end
                        row.entry = e
                        row.t:SetPoint("RIGHT", row.color, "LEFT", -6, 0)
                        function row.refresh()
                            local rec = Records()[e.key]
                            local active = RecActive(rec)
                            row.t:SetText((e.name or e.key) .. (e.sub and ("  |cff707070" .. e.sub .. "|r") or ""))
                            if active then
                                row:SetBackdropBorderColor(0.78, 0.62, 0.22, 0.9); row:SetBackdropColor(0.10, 0.09, 0.05, 0.7)
                                if rec.tint and rec.tint.enabled then
                                    row.chip:Show(); row.chip:SetVertexColor((rec.tint.r or 255)/255, (rec.tint.g or 80)/255, (rec.tint.b or 80)/255)
                                else row.chip:Hide() end
                                row.reset:Show()
                            else
                                row:SetBackdropBorderColor(0.18, 0.18, 0.18, 1); row:SetBackdropColor(0.05, 0.05, 0.05, 0.6); row.chip:Hide()
                                row.reset:Hide()
                            end
                        end
                        row.color:SetScript("OnClick", function()
                            WithRec(e, function(rec)
                                rec.tint = NormalizeTint(rec.tint)
                                OpenCustomizer(rec.tint, e.name or e.key, function() rec.swap = nil; CommitRec(rec, row) end)
                            end)
                        end)
                        row.reset:SetScript("OnClick", function() ResetRec(e.key); if cfg.kind == "saved" then RebuildEntries() end; container._repopulate() end)
                        row:SetPoint("TOPLEFT", 0, -((shown - 1) * (ROW_H + 3))); row:Show()
                        row.refresh()
                    end
                end
            end
        end
        content:SetWidth(math.max(1, scroll:GetWidth()))
        for _, r in ipairs(rows) do if r:IsShown() then r:SetWidth(content:GetWidth() - 2) end end
        local h = shown * (ROW_H + 3)
        if total > shown then
            loadMore:ClearAllPoints(); loadMore:SetPoint("TOP", content, "TOP", 0, -h)
            loadMore:SetText(("Load more (%d of %d)"):format(shown, total)); loadMore:Show()
            h = h + 28
        else loadMore:Hide() end
        content:SetHeight(math.max(1, h))
        countLbl:SetText(("|cff888888%d / %d|r"):format(shown, total))
    end
    container._repopulate = Populate
    loadMore:SetScript("OnClick", function() renderLimit = renderLimit + PAGE; Populate() end)
    -- reset the page size whenever the filter/search changes so each view starts fresh
    container._resetPage = function() renderLimit = PAGE end

    searchBox:SetScript("OnTextChanged", function() renderLimit = PAGE; Populate() end)
    scroll:SetScript("OnSizeChanged", function() Populate() end)
    resetAll:SetScript("OnClick", function()
        for _, e in ipairs(entries) do ResetRec(e.key) end
        if cfg.kind == "saved" then RebuildEntries() end
        Populate(); if ns.EnhPrint then ns.EnhPrint("Cleared " .. cfg.title .. " recolors.") end
    end)

    if scanBtn then
        scanBtn:SetScript("OnClick", function()
            if not container._scanning then
                container._scanning = true; scanBtn:SetText("Stop & List"); Send("TEXCAP:1")
                if ns.EnhPrint then ns.EnhPrint("Scanning \226\128\148 move the camera over what you want to color, then press Stop & List.") end
            else
                container._scanning = false; scanBtn:SetText("Start Scan")
                Send("TEXCAP:0"); Send("TEXCAP_LIST")
                if ns.RunAfter then ns.RunAfter(0.5, function() RebuildEntries(); Populate() end) end
            end
        end)
    end

    if cfg.onInit then cfg.onInit(container) end
    container.RebuildAndShow = function() RebuildEntries(); if strip and not strip.active then strip.SetActive(1) end; Populate() end
    if strip then strip.SetActive(1) end
    return container
end

-- ============================================================
-- Section registrations
-- ============================================================

-- ---- Public opener (used by the Mounts tab's per-row "Color" button) --------
-- Resolve a creature/mount display's skin and open the Customize-Color popup
-- directly. Persists into the same account-wide records as the Creatures tab, so
-- it shows up under Saved and re-applies on login.
function ns.OpenColorAssetForCreature(displayId, name, section)
    if not displayId or displayId <= 0 then return end
    section = section or "creatures"
    local key = (section == "mounts" and "m:" or "c:") .. displayId
    local recs = Records()
    local function openWith(rec)
        rec.tint = NormalizeTint(rec.tint)
        OpenCustomizer(rec.tint, name or key, function() rec.swap = nil; ApplyRec(rec) end)
    end
    local rec = recs[key]
    if rec and rec.paths and #rec.paths > 0 then openWith(rec); return end
    if ns.EnhPrint then ns.EnhPrint("Resolving skin for " .. (name or displayId) .. "...") end
    ResolveCreaturePaths(displayId, function(paths)
        if not paths or #paths == 0 then
            if ns.EnhPrint then ns.EnhPrint("No colorable skin found for " .. (name or displayId)) end
            return
        end
        rec = recs[key] or { kind = "creature", section = section, key = key, name = name }
        rec.paths = paths; rec.tint = NormalizeTint(rec.tint); recs[key] = rec
        openWith(rec)
    end)
end

-- ---- Creatures (All / NPCs / Bosses / Normal, via CREATURE_CATS) ----
local function CCat(displayId) local t = TRANSMORPHER_CCAT; return (type(t) == "table" and t[displayId]) or 0 end
ns.RegisterColorSection("Creatures",
    function(c)
        BuildSection(c, {
            title = "Creatures & Units", desc = "Every creature display (~15k). Search, then color or swap.",
            sectionKey = "creatures", kind = "creature",
            onInit = function(cont)
                Send("CREATURE_CATS")  -- classify NPCs/Bosses/Normal (one-time)
                if ns.RunAfter then ns.RunAfter(1.5, function() if cont._repopulate then cont._repopulate() end end) end
            end,
            filters = {
                { name = "All",    match = function() return true end },
                { name = "NPCs",   match = function(e) return CCat(e.displayId) == 1 end },
                { name = "Bosses", match = function(e) return CCat(e.displayId) == 2 end },
                { name = "Normal", match = function(e) return CCat(e.displayId) == 0 end },
            },
            getEntries = function()
                local out = {}
                if type(ns.creatureDisplayDB) == "table" then
                    for id, name in pairs(ns.creatureDisplayDB) do
                        out[#out + 1] = { key = "c:" .. id, name = name, displayId = id }
                    end
                    table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
                end
                return out
            end,
            resolve = function(entry, cb) ResolveCreaturePaths(entry.displayId, cb) end,
        })
    end,
    function(c) if c.RebuildAndShow then c.RebuildAndShow() end end)

-- ---- Saved (every active recolor, persisted account-wide) ----
local function KindLabel(rec)
    if rec.section == "mounts" then return "Mount"
    elseif rec.section == "creatures" then return "Creature"
    elseif rec.section == "scanner" then return "Texture"
    else return rec.kind or "Asset" end
end
ns.RegisterColorSection("Saved",
    function(c)
        BuildSection(c, {
            title = "Saved Recolors", desc = "Everything you've colored \226\128\148 kept on logout/login until you reset it.",
            sectionKey = "saved", kind = "saved",
            filters = {
                { name = "All",       match = function() return true end },
                { name = "Mounts",    match = function(e) return e.section == "mounts" end },
                { name = "Creatures", match = function(e) return e.section == "creatures" end },
                { name = "Textures",  match = function(e) return e.section == "scanner" end },
            },
            getEntries = function()
                local out = {}
                for key, rec in pairs(Records()) do
                    if RecActive(rec) then
                        out[#out + 1] = { key = key, name = rec.name or key, section = rec.section, rec = rec,
                                          sub = KindLabel(rec) }
                    end
                end
                table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
                return out
            end,
            resolve = function(entry, cb) cb(entry.rec and entry.rec.paths or nil) end,
        })
    end,
    function(c) if c.RebuildAndShow then c.RebuildAndShow() end end)
