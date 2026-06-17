local addon, ns = ...

-- ============================================================
-- BARBER SUB-TAB  (Preview > Barber)
--   Re-style the player's OWN base model: skin tone, face, hair style, hair
--   color and facial hair (the in-game barbershop options, free + instant) PLUS
--   a free-RGB "Color" recolor of each region's actual BLP texture, with the same
--   effect set as the Skin tab (Solid / Gradient / Rainbow / Two-Tone, glow,
--   contrast, brightness, saturation, hue).
--
--   Discrete options -> BARBER:skin:face:hair:haircolor:facial (PLAYER_BYTES).
--   Colour           -> BARBER_TINT:region:... ; the DLL reads the player's REAL
--   texture filenames from CharSections and tints those exact BLPs. Ranges come
--   from the DBCs (TransmorpherBarberMaxes), nothing is guessed. Persists per
--   character and re-applies on login + the character-select doll.
-- ============================================================

local mainFrame = ns.mainFrame
local BARBER_ICON_FALLBACK = "Interface\Icons\INV_Misc_QuestionMark"

-- ChrRaces.dbc IDs (universal client constants) — only used to tell the DLL which
-- race to read counts/textures for; the data itself comes from the DBCs.
local RACE_ID = {
    Human = 1, Orc = 2, Dwarf = 3, NightElf = 4, Scourge = 5, Tauren = 6,
    Gnome = 7, Troll = 8, BloodElf = 10, Draenei = 11,
}
local _, raceFile = UnitRace("player")
local myRace = RACE_ID[raceFile] or 0
local mySex  = (UnitSex("player") or 2) - 2   -- 2 male -> 0, 3 female -> 1

-- Categories. Every card has a discrete option slider. A "Customize Color" free-RGB
-- recolor lives ONLY on the two cards that own a colour, and each drives a GROUP of
-- texture regions so related skin parts always stay in sync:
--   * Skin Tone  -> recolors body skin/skin overlay (region 0) + face (region 1)
--                   together. Colouring the face on its own made no sense and clashed,
--                   so they are merged.
--   * Hair Color -> recolors hair (region 2) + facial hair / beard (region 3) together,
--                   so the beard always matches the hair.
-- Hair Style and Facial Hair are geoset-only: a hairstyle is just a shape, and the
-- beard is already tinted by Hair Color — neither needs a colour of its own.
-- `region` is the primary texture region (used for the index-preview chip); `colorRegions`
-- (when present) is the full set the Color button tints. `fb` is a fallback range used
-- only until the DLL reports the real DBC count. `color` marks the palette chip + glow.
local CATS = {
    { key = "skin",      label = "Skin Tone",   fb = 9,  region = 0, colorRegions = { 0, 1 }, color = true,  glow = "blue",   icon = "Interface\Icons\INV_Misc_Head_Human_01",
      desc = "Body skin tone + overlay + free recolor of skin & face." },
    { key = "face",      label = "Face",        fb = 9,  region = 1, color = false, glow = "gold", icon = "Interface\Icons\Ability_Rogue_Disguise",
      desc = "Facial features (recolored with Skin Tone)." },
    { key = "hair",      label = "Hair Style",  fb = 11, region = 2, color = false, glow = "gold", icon = "Interface\Icons\INV_Helmet_08",
      desc = "Hairstyle geoset (recolored by Hair Color)." },
    { key = "haircolor", label = "Hair Color",  fb = 9,  region = 2, colorRegions = { 2, 3 }, color = true,  glow = "purple", icon = "Interface\Icons\INV_Misc_Gem_Amethyst_02",
      desc = "Hair colour + free recolor of hair & beard." },
    { key = "facial",    label = "Facial Hair", fb = 7,  region = 3, color = false, glow = "gold", icon = "Interface\Icons\INV_Misc_Head_Dwarf_01",
      desc = "Beard / sideburns (recolored by Hair Color)." },
}

-- primary tint region -> ordered list of texture regions the colour group drives.
local TINT_GROUPS = {}
for _, c in ipairs(CATS) do
    if c.colorRegions then TINT_GROUPS[c.colorRegions[1]] = c.colorRegions end
end
local function PrimaryRegionFor(cat) return cat.colorRegions and cat.colorRegions[1] or cat.region end

local function HSVtoRGB(h, s, v)
    local i = math.floor(h * 6); local f = h * 6 - i
    local p = v * (1 - s); local q = v * (1 - f * s); local t = v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return v, t, p elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v else return v, p, q end
end

-- ----- settings + backend bridge --------------------------------
local function S()
    local s = ns.GetSettings()
    s.barber = s.barber or {}
    local b = s.barber
    if b.active    == nil then b.active    = false end
    if b.skin      == nil then b.skin      = 0 end
    if b.face      == nil then b.face      = 0 end
    if b.hair      == nil then b.hair      = 0 end
    if b.haircolor == nil then b.haircolor = 0 end
    if b.facial    == nil then b.facial    = 0 end
    b.base = b.base or {}   -- real (server) look, from the DLL
    b.max  = b.max  or {}   -- real per-category max INDEX, reported by the DLL
    b.values = b.values or {} -- exact valid descriptor indices, reported by the DLL
    b.tint = b.tint or {}   -- [primaryRegion] = effect record (free-RGB recolor group)
    -- Legacy cleanup: Face (region 1) and Facial Hair (region 3) no longer own a colour
    -- of their own — the Skin Tone and Hair Color groups drive them now. Drop any stale
    -- standalone records saved by older versions so they can't linger unused.
    b.tint[1] = nil
    b.tint[3] = nil
    return b
end

local function NormalizeTint(rec, defaults)
    rec = rec or {}
    defaults = defaults or {}
    if rec.enabled    == nil then rec.enabled    = false end
    if rec.mode       == nil then rec.mode       = 0 end
    if rec.r          == nil then rec.r          = defaults.r  or 255 end
    if rec.g          == nil then rec.g          = defaults.g  or 80  end
    if rec.b          == nil then rec.b          = defaults.b  or 80  end
    if rec.r2         == nil then rec.r2         = defaults.r2 or 60  end
    if rec.g2         == nil then rec.g2         = defaults.g2 or 120 end
    if rec.b2         == nil then rec.b2         = defaults.b2 or 255 end
    if rec.dir        == nil then rec.dir        = 0   end
    if rec.mult       == nil then rec.mult       = 130 end
    if rec.glowStr    == nil then rec.glowStr    = 0   end
    if rec.contrast   == nil then rec.contrast   = 100 end
    if rec.span       == nil then rec.span       = 100 end
    if rec.phase      == nil then rec.phase      = 0   end
    if rec.brightness == nil then rec.brightness = 128 end
    if rec.saturation == nil then rec.saturation = 0   end
    if rec.hueShift   == nil then rec.hueShift   = 0   end
    return rec
end

local function Send(cmd)
    if ns.IsMorpherReady and ns.IsMorpherReady() then
        if ns.SendRawMorphCommand then ns.SendRawMorphCommand(cmd); return true
        elseif ns.SendMorphCommand then ns.SendMorphCommand(cmd); return true end
    end
    return false
end

local function QueryMaxes() Send(("BARBER_GET:%d:%d"):format(myRace, mySex)) end

local function PushBarber()
    local b = S()
    return Send(("BARBER:%d:%d:%d:%d:%d"):format(b.skin, b.face, b.hair, b.haircolor, b.facial))
end

-- Send (or clear) ONE texture region using an explicit record. Always sends the
-- CURRENT discrete indices so the DLL binds the tint to the texture the region is
-- actually showing.
local function SendOneRegion(region, t)
    local b = S()
    if not (t and t.enabled) then Send("BARBER_TINT_OFF:" .. region); return end
    t = NormalizeTint(t)
    Send(("BARBER_TINT:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d"):format(
        region, myRace, mySex, b.skin, b.face, b.hair, b.haircolor, b.facial,
        t.mode, t.r, t.g, t.b, t.r2, t.g2, t.b2, t.dir, t.mult, t.glowStr,
        t.contrast, t.span, t.phase, t.brightness, t.saturation, t.hueShift))
end

-- Push the colour stored at `primary` to every region in its group (or clear them all).
local function SendTintGroup(primary)
    local regions = TINT_GROUPS[primary]
    if not regions then return end
    local t = S().tint[primary]
    for _, region in ipairs(regions) do SendOneRegion(region, t) end
end

-- Re-send every active colour group (after a discrete change re-binds the texture).
local function ResendActiveRegionTints()
    local b = S()
    for primary in pairs(TINT_GROUPS) do
        local t = b.tint[primary]
        if t and t.enabled then SendTintGroup(primary) end
    end
end

-- Re-send the saved barber look on login / DLL-ready.
function ns.Barber_ApplyAll()
    local b = S()
    if b.active then PushBarber() end
    for primary in pairs(TINT_GROUPS) do
        local t = b.tint[primary]
        if t and t.enabled then SendTintGroup(primary) end
    end
end

local function BarberTabFrame()
    return mainFrame.tabs and mainFrame.tabs.preview and mainFrame.tabs.preview.barberSubTab
end

function ns.Barber_Reset(silent)
    local b = S()
    b.active = false
    b.skin      = b.base.skin      or b.skin      or 0
    b.face      = b.base.face      or b.face      or 0
    b.hair      = b.base.hair      or b.hair      or 0
    b.haircolor = b.base.haircolor or b.haircolor or 0
    b.facial    = b.base.facial    or b.facial    or 0
    b.tint = {}
    Send("BARBER_OFF")
    Send("BARBER_TINT_CLEAR")
    QueryMaxes()
    if ns.NotifyDressingRoomChanged then ns.NotifyDressingRoomChanged("barber", 0.20) end
    local t = BarberTabFrame()
    if t and t.RefreshBarber then t.RefreshBarber() end
    if not silent and ns.EnhPrint then ns.EnhPrint("Restored your original appearance.") end
end

function ns.Barber_ClosePopups()
    local t = BarberTabFrame()
    if t and t.customizer and t.customizer.Hide then t.customizer:Hide() end
    if ColorPickerFrame and ColorPickerFrame.Hide then ColorPickerFrame:Hide() end
end

function TransmorpherBarberReport(skin, face, hair, haircolor, facial, active)
    local b = S()
    local sk = tonumber(skin)      or 0
    local fc = tonumber(face)      or 0
    local hr = tonumber(hair)      or 0
    local hc = tonumber(haircolor) or 0
    local fh = tonumber(facial)    or 0
    local dllActive = (tonumber(active) or 0) ~= 0

    if dllActive then
        -- BARBER_GET reports the live modified descriptor while the DLL has an active
        -- barber look. Keep the user's original base values instead of replacing them
        -- with the modified look, or Reset would restore to the changed appearance.
        b.active = true
        b.skin, b.face, b.hair = sk, fc, hr
        b.haircolor, b.facial = hc, fh
    else
        b.base.skin, b.base.face, b.base.hair = sk, fc, hr
        b.base.haircolor, b.base.facial = hc, fh
        if not b.active then
            b.skin, b.face, b.hair = sk, fc, hr
            b.haircolor, b.facial = hc, fh
        end
    end
    local t = BarberTabFrame()
    if t and t.RefreshBarber then t.RefreshBarber() end
end

function TransmorpherBarberMaxes(skin, face, hair, haircolor, facial)
    local b = S()
    local function setMax(key, count)
        count = tonumber(count) or 0
        if count >= 1 then b.max[key] = count - 1 end
    end
    setMax("skin", skin); setMax("face", face); setMax("hair", hair)
    setMax("haircolor", haircolor); setMax("facial", facial)
    local t = BarberTabFrame()
    if t and t.ApplyMaxes then t.ApplyMaxes() end
end

local function ParseValueList(csv)
    local out = {}
    csv = tostring(csv or "")
    for token in string.gmatch(csv, "[^,]+") do
        local v = tonumber(token)
        if v then out[#out + 1] = v end
    end
    return (#out > 0) and out or nil
end

function TransmorpherBarberValues(skin, face, hair, haircolor, facial)
    local b = S()
    b.values.skin      = ParseValueList(skin)
    b.values.face      = ParseValueList(face)
    b.values.hair      = ParseValueList(hair)
    b.values.haircolor = ParseValueList(haircolor)
    b.values.facial    = ParseValueList(facial)
    local t = BarberTabFrame()
    if t and t.ApplyMaxes then t.ApplyMaxes() end
end

-- ----- shared color picker (raised above the modal) -------------
local function OpenColorPicker(r, g, b, onChange)
    local function apply()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        onChange(math.floor(nr * 255 + 0.5), math.floor(ng * 255 + 0.5), math.floor(nb * 255 + 0.5))
    end
    ColorPickerFrame.func = apply; ColorPickerFrame.swatchFunc = apply; ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.previousValues = { r = r / 255, g = g / 255, b = b / 255 }
    ColorPickerFrame.cancelFunc = function(prev)
        if prev then onChange(math.floor(prev.r * 255 + 0.5), math.floor(prev.g * 255 + 0.5), math.floor(prev.b * 255 + 0.5)) end
    end
    ColorPickerFrame:SetColorRGB(r / 255, g / 255, b / 255)
    ColorPickerFrame:Hide(); ColorPickerFrame:Show()
    ColorPickerFrame:SetFrameStrata("TOOLTIP"); ColorPickerFrame:SetToplevel(true); ColorPickerFrame:Raise()
    if OpacitySliderFrame then OpacitySliderFrame:SetFrameStrata("TOOLTIP"); OpacitySliderFrame:Raise() end
end

-- ============================================================
-- Init (called once, lazily, by PreviewTab when the Barber sub-tab opens)
-- ============================================================
function ns.InitBarberTab(parent)
    local b = S()
    local cards = {}
    local cols = 2
    local gapX, gapY = 10, 12
    local cardHeight = 132

    local RefreshCard, RefreshAll, SetVal, ApplyMaxes, OpenCustomizer

    local function Val(key) return b[key] or 0 end
    local function BaseVal(key) return (b.base and b.base[key]) or 0 end
    local function ValuesFor(cat)
        local vals = b.values and b.values[cat.key]
        if vals and #vals > 0 then return vals end
        return nil
    end
    local function SpanMaxFor(cat)
        local m = b.max[cat.key]
        if m and m >= 1 then return m end
        return cat.fb
    end
    local function SliderMaxFor(cat)
        local vals = ValuesFor(cat)
        if vals then return math.max(0, #vals - 1) end
        return SpanMaxFor(cat)
    end
    local function OptionCountFor(cat)
        local vals = ValuesFor(cat)
        if vals then return #vals end
        return SpanMaxFor(cat) + 1
    end
    local function ValueForPos(cat, pos)
        pos = math.floor((tonumber(pos) or 0) + 0.5)
        local vals = ValuesFor(cat)
        if vals then
            pos = math.max(0, math.min(#vals - 1, pos))
            return vals[pos + 1]
        end
        return math.max(0, math.min(SpanMaxFor(cat), pos))
    end
    local function PosForValue(cat, value)
        value = tonumber(value) or 0
        local vals = ValuesFor(cat)
        if not vals then return math.max(0, math.min(SpanMaxFor(cat), value)) end
        local best, bestDist = 1, math.huge
        for i, v in ipairs(vals) do
            local d = math.abs(v - value)
            if d < bestDist then best, bestDist = i, d end
        end
        return best - 1
    end
    local function ClampValue(cat, value)
        return ValueForPos(cat, PosForValue(cat, value))
    end
    local function NextValue(cat, delta)
        return ValueForPos(cat, PosForValue(cat, Val(cat.key)) + delta)
    end
    local function RandomValue(cat)
        local vals = ValuesFor(cat)
        if vals then return vals[math.random(1, #vals)] end
        return math.random(0, SpanMaxFor(cat))
    end
    local function Rgb255(r, g, bl)
        return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(bl * 255 + 0.5)
    end
    local function Clamp(v, lo, hi)
        if v < lo then return lo elseif v > hi then return hi end
        return v
    end
    local function Hsv255(h, s, v)
        s = Clamp(s, 0, 1); v = Clamp(v, 0, 1)
        return Rgb255(HSVtoRGB(h % 1, s, v))
    end
    local function ColorLuma(r, g, bl)
        return (r * 299 + g * 587 + bl * 114) / 255000
    end
    local function HarmonyColor(h, s, v, minLuma)
        local r, g, bl = Hsv255(h, s, v)
        local lum = ColorLuma(r, g, bl)
        minLuma = minLuma or 0.52
        if lum < minLuma then
            local mix = Clamp((minLuma - lum) / math.max(0.001, 1 - lum), 0, 0.70)
            r = math.floor(r + (255 - r) * mix + 0.5)
            g = math.floor(g + (255 - g) * mix + 0.5)
            bl = math.floor(bl + (255 - bl) * mix + 0.5)
        end
        return Clamp(r, 0, 255), Clamp(g, 0, 255), Clamp(bl, 0, 255)
    end
    local function IndexColorFor(cat, hueOffset)
        local h = ((PosForValue(cat, Val(cat.key)) / math.max(1, OptionCountFor(cat))) + (hueOffset or 0)) % 1
        return Rgb255(HSVtoRGB(h, 0.55, 0.95))
    end
    local function TintDefaultsFor(cat)
        local r, g, bl = IndexColorFor(cat, 0)
        local r2, g2, b2 = IndexColorFor(cat, 0.34)
        return { r = r, g = g, b = bl, r2 = r2, g2 = g2, b2 = b2 }
    end
    local function BuildBarberPalette()
        local h = math.random()
        local schemes = {
            { 0.055, 0.13 },
            { 0.50,  0.58 },
            { 0.42,  0.58 },
            { 0.333, 0.666 },
            { 0.035, 0.095 },
        }
        local scheme = schemes[math.random(1, #schemes)]
        local mode = math.random(0, 3)
        return {
            primaryHue = h,
            secondaryHue = (h + scheme[1]) % 1,
            accentHue = (h + scheme[2]) % 1,
            mode = mode,
            dir = math.random(0, 2),
            phase = (mode == 2) and math.floor(h * 255 + 0.5) or math.random(0, 80),
            span = (mode == 2) and math.random(22, 52) or math.random(80, 130),
            skinSat = 0.38 + math.random() * 0.18,
            hairSat = 0.48 + math.random() * 0.22,
            skinVal = 0.80 + math.random() * 0.14,
            hairVal = 0.76 + math.random() * 0.16,
            minLuma = 0.54 + math.random() * 0.10,
            mult = math.random(112, 134),
            contrast = math.random(98, 116),
            brightness = math.random(126, 140),
            saturation = math.random(0, 16),
        }
    end
    local function RandomTintFor(cat, palette)
        local hair = cat and cat.key == "haircolor"
        local h1 = hair and palette.accentHue or palette.primaryHue
        local h2 = hair and palette.primaryHue or palette.secondaryHue
        local sat = hair and palette.hairSat or palette.skinSat
        local val = hair and palette.hairVal or palette.skinVal
        local r, g, bl = HarmonyColor(h1, sat + (hair and 0.06 or 0), val + (hair and 0.03 or 0), palette.minLuma)
        local r2, g2, b2 = HarmonyColor(h2, sat * 0.92, val * 0.96, palette.minLuma - 0.02)
        return NormalizeTint({
            enabled = true,
            mode = palette.mode,
            r = r, g = g, b = bl,
            r2 = r2, g2 = g2, b2 = b2,
            dir = palette.dir,
            mult = Clamp(palette.mult + (hair and math.random(8, 18) or math.random(-4, 6)), 90, 175),
            glowStr = hair and math.random(0, 24) or math.random(0, 8),
            contrast = palette.contrast,
            span = palette.span,
            phase = palette.phase,
            brightness = Clamp(palette.brightness + (hair and 4 or 0), 96, 180),
            saturation = Clamp(palette.saturation + (hair and 6 or 0), -30, 45),
            hueShift = 0,
        })
    end
    local function RegionRec(region, cat)
        local defaults = cat and TintDefaultsFor(cat) or nil
        local t = NormalizeTint(b.tint[region], defaults)
        if defaults and not t.enabled then
            t.r, t.g, t.b = defaults.r, defaults.g, defaults.b
            t.r2, t.g2, t.b2 = defaults.r2, defaults.g2, defaults.b2
        end
        b.tint[region] = t
        return t
    end

    -- ---- header bar ----
    local header = CreateFrame("Frame", nil, parent)
    header:SetPoint("TOPLEFT", 6, -6); header:SetPoint("TOPRIGHT", -6, -6); header:SetHeight(40)
    header:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    header:SetBackdropColor(0.08, 0.08, 0.08, 0.95); header:SetBackdropBorderColor(0.35, 0.30, 0.18, 0.9)
    local headerTitle = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerTitle:SetPoint("LEFT", 12, 0); headerTitle:SetTextColor(1.0, 0.84, 0.40); headerTitle:SetText("Character Barber")
    local resetBtn = ns.CreateGoldenButton(nil, header)
    resetBtn:SetSize(96, 24); resetBtn:SetPoint("RIGHT", -10, 0); resetBtn:SetText("Reset All")
    local randomBtn = ns.CreateGoldenButton(nil, header)
    randomBtn:SetSize(96, 24); randomBtn:SetPoint("RIGHT", resetBtn, "LEFT", -8, 0); randomBtn:SetText("Randomize")
    local headerDesc = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    headerDesc:SetPoint("RIGHT", randomBtn, "LEFT", -12, 0); headerDesc:SetTextColor(0.78, 0.78, 0.78)
    headerDesc:SetText("Restyle + recolor skin, face & hair")

    -- ---- scroll grid ----
    local scroll = CreateFrame("ScrollFrame", "TM_Barber_Scroll", parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6); scroll:SetPoint("BOTTOMRIGHT", -26, 10)
    local content = CreateFrame("Frame", nil, scroll); content:SetSize(10, 10); scroll:SetScrollChild(content)

    local function ApplyChange(card)
        b.active = true
        PushBarber()
        QueryMaxes()              -- refresh context-sensitive valid DBC values
        ResendActiveRegionTints()   -- texture changed -> re-bind any region tints
        if ns.NotifyDressingRoomChanged then ns.NotifyDressingRoomChanged("barber", 0.20) end
        if card then RefreshCard(card) end
        PlaySound("gsTitleOptionOK")
    end

    RefreshCard = function(card)
        local cat = card.cat
        local v = Val(cat.key)
        local optionCount = OptionCountFor(cat)
        local changed = b.active and (v ~= BaseVal(cat.key))
        local hasColor = cat.colorRegions ~= nil
        local tint = hasColor and b.tint[PrimaryRegionFor(cat)] or nil
        local tintOn = tint and tint.enabled
        card.valueText:SetText(("%d"):format(v))
        card.baseText:SetText(("base %d  /  %d options"):format(BaseVal(cat.key), optionCount))

        if card.slider then
            card.slider._silent = true
            card.slider:SetMinMaxValues(0, SliderMaxFor(cat))
            card.slider:SetValue(PosForValue(cat, v))
            card.slider._silent = false
        end

        if cat.color then
            card.chip:Show()
            local h = (PosForValue(cat, v) / math.max(1, optionCount)) % 1
            local cr, cg, cb = HSVtoRGB(h, 0.55, 0.95)
            card.chip:SetVertexColor(cr, cg, cb)
        else
            card.chip:Hide()
        end

        -- Color button label + tint chip (only on cards that own a colour group)
        if card.colorBtn then
            if tintOn then
                local modeName = ({ [0] = "Solid", [1] = "Gradient", [2] = "Rainbow", [3] = "Two-Tone" })[tint.mode or 0] or "Solid"
                card.colorBtn:SetText("Color: " .. modeName)
                card.tintChip:Show(); card.tintChip:SetVertexColor((tint.r or 255) / 255, (tint.g or 80) / 255, (tint.b or 80) / 255)
            else
                card.colorBtn:SetText("Customize Color")
                card.tintChip:Hide()
            end
        end

        if changed or tintOn then
            if card.iconBorder then ns.ShowMorphGlow(card.iconBorder, cat.glow) end
            card:SetBackdropBorderColor(0.78, 0.62, 0.22, 0.9)
            card.cardResetBtn:Show()
        else
            if card.iconBorder then ns.HideMorphGlow(card.iconBorder) end
            card:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)
            card.cardResetBtn:Hide()
        end
    end

    RefreshAll = function() for _, card in ipairs(cards) do RefreshCard(card) end end
    ApplyMaxes = function()
        for _, cat in ipairs(CATS) do
            b[cat.key] = ClampValue(cat, b[cat.key] or 0)
        end
        RefreshAll()
    end
    parent.RefreshBarber = RefreshAll
    parent.ApplyMaxes = ApplyMaxes

    SetVal = function(cat, newV, card)
        newV = ClampValue(cat, newV)
        if b[cat.key] == newV and b.active then return end
        b[cat.key] = newV
        ApplyChange(card)
    end

    local function Relayout()
        local w = scroll:GetWidth()
        if not w or w < 50 then return end
        cols = math.floor((w - 4 + gapX) / (260 + gapX))
        if cols < 2 then cols = 2 end
        if cols > 4 then cols = 4 end
        content:SetWidth(w)
        local cardWidth = math.floor((w - 4 - ((cols - 1) * gapX)) / cols)
        local row, col = 0, 0
        for _, card in ipairs(cards) do
            card:SetWidth(cardWidth)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", 2 + col * (cardWidth + gapX), -(row * (cardHeight + gapY)))
            col = col + 1
            if col >= cols then col = 0; row = row + 1 end
        end
        local totalRows = row + (col > 0 and 1 or 0)
        content:SetHeight(math.max(scroll:GetHeight() or 1, totalRows * (cardHeight + gapY)))
    end

    local function BuildCard(cat)
        local card = CreateFrame("Frame", nil, content)
        card.cat = cat
        card:SetHeight(cardHeight)
        card:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        card:SetBackdropColor(0.05, 0.05, 0.05, 0.9); card:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)

        local iconBorder = CreateFrame("Frame", nil, card)
        iconBorder:SetPoint("TOPLEFT", 10, -10); iconBorder:SetSize(40, 40)
        iconBorder:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        iconBorder:SetBackdropColor(0.07, 0.07, 0.07, 1); iconBorder:SetBackdropBorderColor(0.35, 0.30, 0.18, 0.9)
        card.iconBorder = iconBorder
        local chip = iconBorder:CreateTexture(nil, "BACKGROUND")
        chip:SetPoint("TOPLEFT", 2, -2); chip:SetPoint("BOTTOMRIGHT", -2, 2)
        chip:SetTexture("Interface\\Buttons\\WHITE8X8"); chip:SetVertexColor(0.4, 0.4, 0.4); chip:Hide()
        card.chip = chip
        local valueText = iconBorder:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        valueText:SetPoint("CENTER"); valueText:SetTextColor(1.0, 0.84, 0.40); card.valueText = valueText

        local nameText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 10, -1)
        nameText:SetPoint("TOPRIGHT", card, "TOPRIGHT", -68, -1)
        nameText:SetJustifyH("LEFT"); nameText:SetWordWrap(false)
        nameText:SetTextColor(0.96, 0.90, 0.72); nameText:SetText(cat.label)
        local baseText = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        baseText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2)
        baseText:SetJustifyH("LEFT"); baseText:SetWordWrap(false); card.baseText = baseText
        local descText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        descText:SetPoint("TOPLEFT", baseText, "BOTTOMLEFT", 0, -2)
        descText:SetPoint("RIGHT", card, "RIGHT", -10, 0)
        descText:SetJustifyH("LEFT"); descText:SetWordWrap(false)
        descText:SetTextColor(0.62, 0.62, 0.62); descText:SetText(cat.desc)

        -- − / slider / + (index)
        local minus = ns.CreateGoldenButton(nil, card)
        minus:SetSize(26, 22); minus:SetPoint("TOPLEFT", 10, -(cardHeight - 60)); minus:SetText("-")
        local plus = ns.CreateGoldenButton(nil, card)
        plus:SetSize(26, 22); plus:SetPoint("TOPRIGHT", -10, -(cardHeight - 60)); plus:SetText("+")
        local slider = CreateFrame("Slider", "TM_Barber_Sl_" .. cat.key, card, "OptionsSliderTemplate")
        slider:SetPoint("LEFT", minus, "RIGHT", 8, 0); slider:SetPoint("RIGHT", plus, "LEFT", -8, 0)
        slider:SetMinMaxValues(0, SliderMaxFor(cat)); slider:SetValueStep(1)
        _G[slider:GetName() .. "Low"]:SetText(""); _G[slider:GetName() .. "High"]:SetText("")
        _G[slider:GetName() .. "Text"]:SetText("")
        slider:SetScript("OnValueChanged", function(self, v)
            if self._silent then return end
            SetVal(cat, ValueForPos(cat, v), card)
        end)
        card.slider = slider

        -- Color (free-RGB recolor) button + tint chip — only on cards that own a colour
        -- group (Skin Tone, Hair Color). Hair Style / Facial Hair are geoset-only.
        if cat.colorRegions then
            local colorBtn = ns.CreateGoldenButton(nil, card)
            colorBtn:SetSize(150, 22); colorBtn:SetPoint("BOTTOMLEFT", 10, 10); colorBtn:SetText("Customize Color")
            card.colorBtn = colorBtn
            local tintChip = card:CreateTexture(nil, "OVERLAY")
            tintChip:SetSize(14, 14); tintChip:SetPoint("LEFT", colorBtn, "RIGHT", 6, 0)
            tintChip:SetTexture("Interface\\Buttons\\WHITE8X8"); tintChip:Hide()
            card.tintChip = tintChip
            colorBtn:SetScript("OnClick", function() OpenCustomizer(cat, card) end)
        end

        local cardResetBtn = ns.CreateGoldenButton(nil, card)
        cardResetBtn:SetSize(64, 22); cardResetBtn:SetPoint("BOTTOMRIGHT", -10, 10); cardResetBtn:SetText("Reset")
        cardResetBtn:Hide(); card.cardResetBtn = cardResetBtn
        cardResetBtn:SetScript("OnClick", function()
            b[cat.key] = BaseVal(cat.key)
            if cat.colorRegions then
                local primary = PrimaryRegionFor(cat)
                b.tint[primary] = nil
                SendTintGroup(primary)   -- sends BARBER_TINT_OFF to every region in the group
            end
            local anyChanged = false
            for _, c in ipairs(CATS) do if Val(c.key) ~= BaseVal(c.key) then anyChanged = true; break end end
            local anyTint = false
            for _, t in pairs(b.tint) do if t and t.enabled then anyTint = true; break end end
            if anyChanged or anyTint then ApplyChange(card) else ns.Barber_Reset(true) end
            RefreshAll(); PlaySound("gsTitleOptionOK")
        end)

        minus:SetScript("OnClick", function() SetVal(cat, NextValue(cat, -1), card) end)
        plus:SetScript("OnClick",  function() SetVal(cat, NextValue(cat, 1), card) end)
        return card
    end

    for _, cat in ipairs(CATS) do cards[#cards + 1] = BuildCard(cat) end
    scroll:SetScript("OnSizeChanged", Relayout)

    -- ===== Customize Color popup (region BLP recolor) =====
    local function BuildCustomizer()
        local f = CreateFrame("Frame", "TM_Barber_Customizer", UIParent)
        f:SetSize(372, 400); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true); f:Hide()
        f:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        f:SetBackdropColor(0.05, 0.05, 0.06, 0.98); f:SetBackdropBorderColor(0.8, 0.65, 0.3, 1)
        f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing); f:SetPoint("CENTER")
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); title:SetPoint("TOPLEFT", 14, -12); title:SetTextColor(1, 0.82, 0.2); f.title = title
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
        close:SetScript("OnClick", function() f:Hide() end)

        local function T() return f.region and RegionRec(f.region, f.cat) or nil end
        local function Commit()
            if not f.region then return end
            SendTintGroup(f.region)   -- f.region is the group's primary; pushes to all its regions
            if ns.NotifyDressingRoomChanged then ns.NotifyDressingRoomChanged("barber", 0.20) end
            if f.card then RefreshCard(f.card) end
            if f.Refresh then f.Refresh() end
        end

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
                local r, g, bl = getf(t); OpenColorPicker(r, g, bl, function(nr, ng, nb) setf(t, nr, ng, nb); t.enabled = true; Commit() end) end)
            return sw, lbl
        end
        f.sw1 = MakeSwatch("Color", 212, -62, function(t) return t.r, t.g, t.b end, function(t, r, g, bl) t.r, t.g, t.b = r, g, bl end)
        f.sw2, f.sw2lbl = MakeSwatch("Color 2", 286, -62, function(t) return t.r2, t.g2, t.b2 end, function(t, r, g, bl) t.r2, t.g2, t.b2 = r, g, bl end)

        local dirNames = { [0] = "Vert", [1] = "Horiz", [2] = "Diag" }
        f.dirBtns = {}
        f.dlbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.dlbl:SetPoint("TOPLEFT", 14, -128); f.dlbl:SetText("Direction")
        for i = 0, 2 do
            local db = ns.CreateGoldenButton(nil, f); db:SetSize(66, 20); db:SetPoint("TOPLEFT", 14 + (i % 3) * 72, -144)
            db:SetText(dirNames[i]); db:SetScript("OnClick", function() local t = T(); if not t then return end; t.dir = i; t.enabled = true; Commit() end)
            f.dirBtns[i] = db
        end

        local function MakeSlider(field, fmt, lo, hi)
            local s = CreateFrame("Slider", "TM_Barber_Cl_" .. field, f, "OptionsSliderTemplate")
            s:SetWidth(336); s:SetMinMaxValues(lo, hi); s:SetValueStep(1)
            _G[s:GetName() .. "Low"]:SetText(""); _G[s:GetName() .. "High"]:SetText("")
            local txt = _G[s:GetName() .. "Text"]
            s:SetScript("OnValueChanged", function(self, v)
                v = math.floor(v + 0.5); local t = T(); txt:SetText(fmt:format(v)); if not t then return end
                t[field] = v; if not self._silent then t.enabled = true; Commit() end
            end)
            s.txt = txt; return s
        end
        f.slMult       = MakeSlider("mult",       "Intensity  %d%%",      50, 250)
        f.slGlow       = MakeSlider("glowStr",    "Glow  %d",             0, 255)
        f.slContrast   = MakeSlider("contrast",   "Contrast  %d%%",       50, 300)
        f.slSpan       = MakeSlider("span",       "Rainbow spread  %d%%", 30, 400)
        f.slPhase      = MakeSlider("phase",      "Color shift  %d",      0, 255)
        f.slBrightness = MakeSlider("brightness", "Brightness  %d",       0, 255)
        f.slSaturation = MakeSlider("saturation", "Saturation  %d",       -100, 100)
        f.slHueShift   = MakeSlider("hueShift",   "Hue shift  %d",        0, 255)
        f._sliderRows = {
            { s = f.slMult }, { s = f.slGlow }, { s = f.slContrast },
            { s = f.slSpan,  vis = function(t) return t.mode == 2 end },
            { s = f.slPhase, vis = function(t) return t.mode ~= 0 end },
            { s = f.slBrightness }, { s = f.slSaturation }, { s = f.slHueShift },
        }

        local rb = ns.CreateGoldenButton(nil, f); rb:SetSize(190, 24)
        rb:SetPoint("BOTTOMRIGHT", -14, 12); rb:SetText("Clear Color")
        rb:SetScript("OnClick", function()
            if not f.region then return end
            b.tint[f.region] = nil
            SendTintGroup(f.region)
            if ns.NotifyDressingRoomChanged then ns.NotifyDressingRoomChanged("barber", 0.20) end
            if f.card then RefreshCard(f.card) end
            if f.Refresh then f.Refresh() end
        end)

        local function setSil(s, v) s._silent = true; s:SetValue(v); s._silent = false; s.txt:SetText(s.txt:GetText()) end
        function f.Refresh()
            local t = T(); if not t then return end
            f.title:SetText("Customize Color — " .. (f.regionLabel or ""))
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
            local lastTrackBottom = (y + PITCH) - 18
            f:SetHeight(math.floor(-lastTrackBottom + 14 + 24 + 14 + 0.5))
            for i = 0, 3 do
                local on = (i == t.mode)
                if f.modeBtns[i].SetBackdropBorderColor then f.modeBtns[i]:SetBackdropBorderColor(on and 1 or 0.45, on and 0.82 or 0.38, on and 0.2 or 0.12, 1) end
            end
            for i = 0, 2 do
                local on = (i == t.dir)
                if f.dirBtns[i].SetBackdropBorderColor then f.dirBtns[i]:SetBackdropBorderColor(on and 1 or 0.45, on and 0.82 or 0.38, on and 0.2 or 0.12, 1) end
            end
        end
        parent.customizer = f
        return f
    end

    OpenCustomizer = function(cat, card)
        if not cat.colorRegions then return end
        local f = parent.customizer or BuildCustomizer()
        local primary = PrimaryRegionFor(cat)
        f.region = primary; f.regionLabel = cat.label; f.cat = cat; f.card = card
        RegionRec(primary, cat)
        f.Refresh(); f:Show(); f:Raise()
    end

    randomBtn:SetScript("OnClick", function()
        for _, cat in ipairs(CATS) do b[cat.key] = RandomValue(cat) end
        local palette = BuildBarberPalette()
        for _, cat in ipairs(CATS) do
            if cat.colorRegions then b.tint[PrimaryRegionFor(cat)] = RandomTintFor(cat, palette) end
        end
        b.active = true
        PushBarber(); QueryMaxes(); ResendActiveRegionTints(); RefreshAll()
        if ns.NotifyDressingRoomChanged then ns.NotifyDressingRoomChanged("barber", 0.20) end
        PlaySound("gsTitleOptionOK")
    end)
    resetBtn:SetScript("OnClick", function()
        ns.Barber_Reset(false); RefreshAll(); PlaySound("gsTitleOptionOK")
    end)

    parent:SetScript("OnShow", function()
        Relayout(); QueryMaxes(); RefreshAll()
    end)
    ns.RunAfter(0.05, function() Relayout(); RefreshAll() end)
    QueryMaxes()
end
