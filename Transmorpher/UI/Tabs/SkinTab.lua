local addon, ns = ...

-- ============================================================
-- SKIN SUB-TAB  (Preview > Skin)
--   Per-slot recolor: re-skin the item you're WEARING (or transmogged to) with
--   the look of another item of the same slot — keeps the item's own model/shape,
--   swaps its texture + glow/particles. Forms-tab card styling, with a glow on
--   any slot that has an active skin.
--
--   Backed by the DLL ColorEngine (ITEM_RETEX / ITEM_TINT_SLOT commands).
--   Recolors persist per-character (ns.GetSettings().slotRecolor) and re-apply on
--   login. If you change the weapon/item a skin was applied to, the skin for that
--   slot is automatically reset (it was tied to the old item).
-- ============================================================

local mainFrame = ns.mainFrame
local QUESTION  = "Interface\\Icons\\INV_Misc_QuestionMark"

-- ----- settings + backend bridge --------------------------------
local function S()
    local s = ns.GetSettings()
    s.slotRecolor = s.slotRecolor or {}   -- [slotName] = { to=itemId, toName=string, appliedTo=itemId, tint={...} }
    return s
end

local function Send(cmd)
    if ns.IsMorpherReady and ns.IsMorpherReady() then
        if ns.SendRawMorphCommand then ns.SendRawMorphCommand(cmd); return true
        elseif ns.SendMorphCommand then ns.SendMorphCommand(cmd); return true end
    end
    return false
end

local lastFrom = {}   -- slot -> source itemId currently retextured (for clean undo)
local lastTint = {}   -- slot -> true when a weapon tint is currently pushed
local lastTintCmd = {}     -- slot -> last live tint command sent; avoids redundant native churn
local lastRetexTo = {}     -- slot -> donor itemId last sent through ITEM_RETEX_SLOT
local lastPersistCmd = {}  -- slot -> last persistence command sent; avoids repeated disk flushes
local customizer
local OpenSkinCustomizer
local skinPickerFrame
local PruneStaleSkins
local function IsTintSlot(slot)
    return (ns.slotToMorphSlot and ns.slotToMorphSlot[slot]) and true or false
end

-- Effect model (per slot): enabled + a full set the Customize popup drives.
--   mode 0 solid / 1 gradient(2-color) / 2 rainbow / 3 two-tone
--   dir  0 vertical / 1 horizontal / 2 diagonal
local function NormalizeTint(rec)
    if not rec then return nil end
    local t = rec.tint or {}
    rec.tint = t
    if t.enabled  == nil then t.enabled  = false end
    if t.mode     == nil then t.mode     = 0 end
    if t.r        == nil then t.r        = 255 end
    if t.g        == nil then t.g        = 80  end
    if t.b        == nil then t.b        = 80  end
    if t.r2       == nil then t.r2       = 60  end
    if t.g2       == nil then t.g2       = 120 end
    if t.b2       == nil then t.b2       = 255 end
    if t.dir      == nil then t.dir      = 0   end
    if t.mult     == nil then t.mult     = 130 end
    if t.glowStr  == nil then t.glowStr  = 0   end
    if t.contrast == nil then t.contrast = 100 end
    if t.span     == nil then t.span     = 100 end
    -- v5 post-effect color transforms. brightness is 0..255 (128 = neutral);
    -- saturation is -100..+100 (0 = neutral, -100 = grayscale, +100 = 2x vibrancy);
    -- hueShift is 0..255 (0 = neutral, 128 = 180 deg rotation). All three are
    -- per-pixel post-effects applied after the spatial tint is resolved, so they
    -- work with every Effect mode (Solid / Gradient / Rainbow / Two-Tone) and on
    -- both the model-item path and the body-component path.
    if t.brightness == nil then t.brightness = 128 end
    if t.saturation == nil then t.saturation = 0   end
    if t.hueShift   == nil then t.hueShift   = 0   end
    -- "Animate \226\128\148 moving RGB" feature was removed. Strip the dead fields
    -- from anything we read off disk so old saves load cleanly with the option gone.
    t.animate = false
    t.animSpeed = 60
    -- phase is now a manual "Color shift" control (rotates the gradient/rainbow start);
    -- keep whatever is saved instead of forcing it to 0.
    if t.phase == nil then t.phase = 0 end
    if t.rainbow  == nil then t.rainbow  = (t.mode == 2) end
    if t.glow     == nil then t.glow     = (t.glowStr > 0) end
    return rec.tint
end

local function TintActive(rec)
    return rec and rec.tint and rec.tint.enabled
end

local function SlotRec(slot)
    local sr = S().slotRecolor
    sr[slot] = sr[slot] or {}
    NormalizeTint(sr[slot])
    return sr[slot]
end

local function CleanEmptyRec(slot)
    local sr = S().slotRecolor
    local rec = sr[slot]
    if rec and not rec.to and not TintActive(rec) then sr[slot] = nil end
end

local function OpenColorPicker(r, g, b, onChange)
    local function apply()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        onChange(math.floor(nr * 255 + 0.5), math.floor(ng * 255 + 0.5), math.floor(nb * 255 + 0.5))
    end
    ColorPickerFrame.func = apply
    ColorPickerFrame.swatchFunc = apply
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.previousValues = { r = r / 255, g = g / 255, b = b / 255 }
    ColorPickerFrame.cancelFunc = function(prev)
        if prev then onChange(math.floor(prev.r * 255 + 0.5), math.floor(prev.g * 255 + 0.5), math.floor(prev.b * 255 + 0.5)) end
    end
    ColorPickerFrame:SetColorRGB(r / 255, g / 255, b / 255)
    ColorPickerFrame:Hide(); ColorPickerFrame:Show()
    -- The Customize modal sits at FULLSCREEN_DIALOG strata, above Blizzard's default
    -- ColorPickerFrame (DIALOG) — so the picker would open hidden BEHIND it. Force the
    -- picker (and its opacity sub-frame) to the highest strata + raise so it is always
    -- clickable on top of the modal.
    ColorPickerFrame:SetFrameStrata("TOOLTIP")
    ColorPickerFrame:SetToplevel(true)
    ColorPickerFrame:Raise()
    if OpacitySliderFrame then OpacitySliderFrame:SetFrameStrata("TOOLTIP"); OpacitySliderFrame:Raise() end
end

local previewRefresh = CreateFrame("Frame")
previewRefresh:Hide()
previewRefresh.t = 0
previewRefresh:SetScript("OnUpdate", function(self, dt)
    self.t = self.t - (dt or 0)
    if self.t > 0 then return end
    self:Hide()
    if ns.UpdatePreviewModel then ns.UpdatePreviewModel() end
    if ns.SyncDressingRoom then ns.SyncDressingRoom() end
end)

local function RefreshModel(delay)
    ns._skinChangeSeq = (ns._skinChangeSeq or 0) + 1
    previewRefresh.t = delay or 0.18
    previewRefresh:Show()
end

-- The item currently SHOWING in a slot: live UI morph first, saved morph state during
-- reload/login before the UI is restored, then the equipped item.
local function ActiveItem(slot)
    local sf = mainFrame.slots and mainFrame.slots[slot]
    if sf and sf.isMorphed and sf.morphedItemId and sf.morphedItemId > 0 then
        return sf.morphedItemId
    end
    local eq = ns.slotToEquipSlotId[slot]
    local state = rawget(_G, "TransmorpherCharacterState")
    if eq and state and state.Items then
        local saved = state.Items[eq]
        if saved and saved > 0 and not (state.HiddenItems and state.HiddenItems[eq]) then
            return saved
        end
    end
    if eq then
        local id = GetInventoryItemID("player", eq)
        if id and id > 0 then return id end
    end
    return nil
end

local function SendTintDel(slot, idx)
    if IsTintSlot(slot) and lastTint[slot] and idx then
        Send("ITEM_TINT_SLOT_DEL:" .. idx)
        lastTint[slot] = nil
        lastTintCmd[slot] = nil
        return true
    end
    return false
end

local function SendTintApply(slot, idx, rec, force)
    if not IsTintSlot(slot) or not idx or not TintActive(rec) then return false end
    local t = NormalizeTint(rec)
    local mult = math.max(0, math.min(400, tonumber(t.mult) or 130))
    local cmd = ("ITEM_TINTX_SLOT:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d"):format(
        idx, t.mode or 0, t.r or 255, t.g or 255, t.b or 255,
        t.r2 or 0, t.g2 or 0, t.b2 or 0, t.dir or 0, mult,
        t.glowStr or 0, t.contrast or 100, t.span or 100, math.floor(t.phase or 0) % 256,
        math.max(0, math.min(255, math.floor(t.brightness or 128))),
        math.max(-100, math.min(100, math.floor(t.saturation or 0))),
        math.floor(t.hueShift or 0) % 256)
    if not force and lastTint[slot] and lastTintCmd[slot] == cmd then return false end
    Send(cmd)
    lastTint[slot] = true
    lastTintCmd[slot] = cmd
    return true
end

-- Push the current skin+tint for one slot to the C++ persistent state so the
-- character-select doll renders the same look. The C++ writes its in-memory
-- g_skinToItem / g_skinTint and calls SaveFullState(GetPlayerGuid()) to flush
-- the v4 state file. The mirror is purely defensive — the world has the live
-- retex/tint already, this is for the doll (and survives relog).
local function PersistSlot(slot, deferBind, force)
    local s = S()
    local rec = s.slotRecolor and s.slotRecolor[slot]
    local idx = ns.slotToMorphSlot and ns.slotToMorphSlot[slot]
    if not idx then return end
    local toId = 0
    -- 0 = let the DLL infer the current live item now; -1 = mirror only and let
    -- MorphGuard bind after morph/loadout descriptors have been stamped.
    local sourceId = deferBind and -1 or 0
    local enabled, mode, r, g, b, r2, g2, b2, dir, mult, glow, contrast, span, phase =
        0, 0, 255, 80, 80, 60, 120, 255, 0, 130, 0, 100, 100, 0
    local brightness, saturation, hueShift = 128, 0, 0
    if rec then
        if rec.to and rec.to > 0 then toId = rec.to end
        -- sourceId is deliberately 0: the DLL ALWAYS determines the correct visible
        -- item from the descriptor field on reconcile (ApplyPersistedSkins). Sending
        -- an equipped-item id from Lua (ActiveItem / rec.appliedTo) would mismatch the
        -- descriptor when a server-side transmog (Warmane) is active, causing the DLL
        -- to clear the skin on the next reconcile tick because g_skinAppliedTo would
        -- hold the equipped item while the visible item is the transmog appearance.
        -- Letting the DLL read the descriptor ensures it matches every time.
        local t = NormalizeTint(rec)
        if t and t.enabled then
            enabled = 1; mode = t.mode or 0
            r, g, b = t.r or 255, t.g or 80, t.b or 80
            r2, g2, b2 = t.r2 or 60, t.g2 or 120, t.b2 or 255
            dir = t.dir or 0
            mult = t.mult or 130
            glow = t.glowStr or 0
            contrast = t.contrast or 100
            span = t.span or 100
            phase = t.phase or 0
            brightness = t.brightness or 128
            saturation = t.saturation or 0
            hueShift = t.hueShift or 0
        end
    end
    local cmd = ("ITEM_SKIN_PERSIST:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d"):format(
        idx, toId, enabled, mode,
        r, g, b, r2, g2, b2,
        dir, mult, glow, contrast, span, phase,
        brightness, saturation, hueShift, sourceId)
    if not force and lastPersistCmd[slot] == cmd then return end
    Send(cmd)
    lastPersistCmd[slot] = cmd
end

-- Apply / refresh the recolor for one slot. Tracks the source item it was applied
-- to so we can auto-reset when the underlying item changes.
local function ApplySlot(slot, silent, force)
    local s = S()
    local rec = s.slotRecolor[slot]
    local idx = ns.slotToMorphSlot and ns.slotToMorphSlot[slot]
    if not idx then return end
    local changed = false
    local cur = ActiveItem(slot)

    -- A skin/color is anchored to the item it was applied to. If the visible item
    -- changed, clear the slot instead of rebinding the old tint to the new item.
    if rec and rec.appliedTo and rec.appliedTo > 0 and cur and cur ~= rec.appliedTo then
        changed = SendTintDel(slot, idx) or changed
        if lastFrom[slot] then
            Send("ITEM_RETEX_SLOT_DEL:" .. idx); lastFrom[slot] = nil; changed = true
            lastRetexTo[slot] = nil
        end
        s.slotRecolor[slot] = nil
        PersistSlot(slot, nil, true)
        if changed and not silent then RefreshModel() end
        return
    elseif rec and (rec.to or TintActive(rec)) and cur and cur > 0 and not rec.appliedTo then
        rec.appliedTo = cur
    end

    local wantsRetex = rec and cur and cur > 0 and rec.to and cur ~= rec.to
    local wantsTint = rec and cur and cur > 0 and TintActive(rec)

    if lastTint[slot] and not wantsTint then
        changed = SendTintDel(slot, idx) or changed
    end
    if lastFrom[slot] and not wantsRetex then
        Send("ITEM_RETEX_SLOT_DEL:" .. idx)
        lastFrom[slot] = nil
        lastRetexTo[slot] = nil
        lastTintCmd[slot] = nil
        changed = true
    end
    if not rec then if changed and not silent then RefreshModel() end; PersistSlot(slot, nil, true); return end

    -- Use the SLOT-based retex so the skin lands on whatever the slot is actually
    -- RENDERING. Do not delete/re-add on every color change; the DLL can update the
    -- same binding and repeated delete/add cycles race the texture compositor.
    if wantsRetex and (force or not lastFrom[slot] or lastRetexTo[slot] ~= rec.to) then
        Send(("ITEM_RETEX_SLOT:%d:%d"):format(idx, rec.to))
        lastFrom[slot] = true
        lastRetexTo[slot] = rec.to
        lastTintCmd[slot] = nil
        rec.appliedTo = cur
        changed = true
    end
    if wantsTint and SendTintApply(slot, idx, rec, force) then
        rec.appliedTo = cur
        changed = true
    end
    CleanEmptyRec(slot)
    if changed and not silent then RefreshModel() end
    PersistSlot(slot, nil, force)
end

local queuedSkinSlots, queuedSkinSilent, queuedSkinForce = {}, true, false
local skinApplyQueue = CreateFrame("Frame")
skinApplyQueue:Hide()
skinApplyQueue.t = 0
skinApplyQueue:SetScript("OnUpdate", function(self, dt)
    self.t = self.t - (dt or 0)
    if self.t > 0 then return end
    self:Hide()

    local slots, silent, force = queuedSkinSlots, queuedSkinSilent, queuedSkinForce
    queuedSkinSlots, queuedSkinSilent, queuedSkinForce = {}, true, false

    for slot in pairs(slots) do
        ApplySlot(slot, true, force)
    end
    if not silent then RefreshModel(0.12) end
end)

local function QueueApplySlot(slot, silent, delay, force)
    if not slot then return end
    queuedSkinSlots[slot] = true
    if not silent then queuedSkinSilent = false end
    if force then queuedSkinForce = true end
    skinApplyQueue.t = delay or 0.12
    skinApplyQueue:Show()
end

-- Re-push all saved skins to the DLL (login / DLL ready / sync). Also writes
-- the per-slot skin+tint to the C++ persistent state file (via ITEM_SKIN_PERSIST
-- inside ApplySlot) so the character-select doll renders the same look next
-- time the user reaches the character select screen.
function ns.Skin_ApplyAll()
    local s = S()
    for slot in pairs(s.slotRecolor) do QueueApplySlot(slot, true, 0.18, true) end
    RefreshModel(0.35)
end

-- Push the per-slot skin DESIRE (donor + tint) to the DLL for EVERY slot without
-- doing the live retex ourselves. The DLL mirrors this into g_skinToItem/g_skinTint
-- and re-binds the skin to whatever each slot is actually rendering at the right
-- moment (after morphs are stamped) via its own MorphGuard reconcile. This is the
-- correct path for login and loadout-apply, where sending ITEM_RETEX_SLOT from Lua
-- would bind to the PRE-morph item (the "only one skin shows" bug) and flash.
function ns.Skin_PersistAll()
    if not (ns.IsMorpherReady and ns.IsMorpherReady()) then return end
    for _, slot in ipairs(ns.slotOrder or {}) do
        PersistSlot(slot, true, true)
    end
end

function ns.Skin_ClosePopups()
    if customizer and customizer.Hide then customizer:Hide() end
    if skinPickerFrame and skinPickerFrame.Hide then skinPickerFrame:Hide() end
    if ColorPickerFrame and ColorPickerFrame.Hide then ColorPickerFrame:Hide() end
end

function ns.Skin_ResetAll(silent)
    local s = S()
    -- One authoritative clear command. It wipes live retex/tint state AND the
    -- persisted per-slot skin/tint tables in the DLL, then saves the cleared state.
    Send("ITEM_RETEX_CLEAR")
    for slot in pairs(lastFrom) do lastFrom[slot] = nil end
    for slot in pairs(lastTint) do lastTint[slot] = nil end
    for slot in pairs(lastTintCmd) do lastTintCmd[slot] = nil end
    for slot in pairs(lastRetexTo) do lastRetexTo[slot] = nil end
    for slot in pairs(lastPersistCmd) do lastPersistCmd[slot] = nil end
    queuedSkinSlots, queuedSkinSilent, queuedSkinForce = {}, true, false
    skinApplyQueue:Hide()
    s.slotRecolor = {}
    RefreshModel()

    local skinTab = mainFrame.tabs and mainFrame.tabs.preview and mainFrame.tabs.preview.skinSubTab
    if skinTab and skinTab.RefreshSkinCards then skinTab.RefreshSkinCards() end
    if not silent and ns.EnhPrint then ns.EnhPrint("Cleared all item skins.") end
end

-- ============================================================
-- CUSTOMIZE popup — unlimited per-item color/effect control.
-- Modes: Solid / Gradient (2 colors) / Rainbow / Two-Tone, with direction,
-- intensity, glow, contrast, and rainbow spread. (The "Animate - moving RGB"
-- toggle was removed; old settings that still carry the flag are silently
-- downgraded to a static tint on load.)
-- ============================================================

-- Sentinel slot used by the "Color All" header button: the customizer edits one
-- shared tint template and Commit fans it out to EVERY slot (color works with or
-- without a donor skin). gAllRec mirrors a normal rec so NormalizeTint/Apply reuse.
local ALL_SLOTS = "\001ALL"
local gAllRec = { tint = {} }

local function HSVtoRGB(h, s, v)
    local i = math.floor(h * 6); local f = h * 6 - i
    local p = v * (1 - s); local q = v * (1 - f * s); local t = v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return v, t, p elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v else return v, p, q end
end

local function RGB255(h, s, v)
    if s < 0 then s = 0 elseif s > 1 then s = 1 end
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    local r, g, b = HSVtoRGB(h % 1, s, v)
    return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
end

local function Clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local function ColorLuma(r, g, b)
    return (r * 299 + g * 587 + b * 114) / (255000)
end

local function HarmonyColor(h, s, v, minLuma)
    local r, g, b = RGB255(h, s, v)
    local lum = ColorLuma(r, g, b)
    minLuma = minLuma or 0.48
    if lum < minLuma then
        local mix = Clamp((minLuma - lum) / math.max(0.001, 1 - lum), 0, 0.72)
        r = math.floor(r + (255 - r) * mix + 0.5)
        g = math.floor(g + (255 - g) * mix + 0.5)
        b = math.floor(b + (255 - b) * mix + 0.5)
    end
    return Clamp(r, 0, 255), Clamp(g, 0, 255), Clamp(b, 0, 255)
end

local function CopyTint(dst, src)
    for k, v in pairs(src) do dst[k] = v end
end

local function IsWeaponSlot(slot)
    return slot == "Main Hand" or slot == "Off-hand" or slot == "Ranged"
end

local function SlotColorRole(slot)
    if slot == "Back" or slot == "Tabard" or slot == "Shirt" then return "cloth" end
    if slot == "Shoulder" or slot == "Head" then return "hero" end
    if IsWeaponSlot(slot) then return "weapon" end
    return "armor"
end

local function SlotHues(slot, palette)
    local role = SlotColorRole(slot)
    if role == "weapon" then return palette.accentHue, palette.primaryHue end
    if role == "cloth" then return palette.secondaryHue, palette.accentHue end
    if role == "hero" then return palette.primaryHue, palette.accentHue end
    return palette.primaryHue, palette.secondaryHue
end

local function RandomMatchedTint(slot, palette, index)
    local role = SlotColorRole(slot)
    local accent = role == "weapon"
    local heroic = role == "hero"
    local cloth = role == "cloth"
    local variance = ((index or 1) % 3) - 1
    local h1, h2 = SlotHues(slot, palette)
    local s1 = palette.sat + (accent and 0.08 or (cloth and -0.04 or 0))
    local s2 = palette.sat2 + (accent and 0.06 or 0)
    local v1 = palette.val + (accent and 0.04 or (cloth and 0.03 or 0))
    local v2 = palette.val2 + (accent and 0.03 or 0)
    local r, g, b = HarmonyColor(h1, s1, v1, palette.minLuma)
    local r2, g2, b2 = HarmonyColor(h2, s2, v2, palette.minLuma2)
    return {
        enabled = true,
        mode = palette.mode,
        r = r, g = g, b = b,
        r2 = r2, g2 = g2, b2 = b2,
        dir = palette.dir,
        mult = Clamp(palette.mult + variance * 2 + (accent and palette.weaponBoost or 0) + (cloth and -4 or 0), 90, 190),
        glowStr = accent and palette.weaponGlow or (heroic and palette.heroGlow or palette.armorGlow),
        contrast = palette.contrast,
        span = palette.span,
        phase = palette.phase,
        brightness = Clamp(palette.brightness + variance + (accent and 5 or (cloth and 2 or 0)), 96, 180),
        saturation = Clamp(palette.saturation + (accent and 7 or (cloth and -3 or 0)), -35, 45),
        hueShift = 0,
        rainbow = palette.mode == 2,
        glow = accent,
        animate = false,
        animSpeed = 60,
    }
end

local function BuildMatchedPalette()
    local h = math.random()
    local schemes = {
        { 0.07,  0.14 },  -- analogous
        { 0.50,  0.58 },  -- complementary accent
        { 0.42,  0.58 },  -- split complementary
        { 0.333, 0.666 }, -- triad
        { 0.035, 0.095 }, -- monochrome polish
    }
    local scheme = schemes[math.random(1, #schemes)]
    local mode = math.random(0, 3)
    local phase = (mode == 2) and math.floor(h * 255 + 0.5) or math.random(0, 96)
    return {
        primaryHue = h,
        secondaryHue = (h + scheme[1]) % 1,
        accentHue = (h + scheme[2]) % 1,
        sat = 0.42 + math.random() * 0.18,
        sat2 = 0.38 + math.random() * 0.18,
        val = 0.78 + math.random() * 0.16,
        val2 = 0.74 + math.random() * 0.16,
        minLuma = 0.50 + math.random() * 0.10,
        minLuma2 = 0.48 + math.random() * 0.10,
        mode = mode,
        dir = math.random(0, 2),
        mult = math.random(114, 132),
        weaponBoost = math.random(8, 18),
        armorGlow = math.random(0, 10),
        heroGlow = math.random(4, 18),
        weaponGlow = math.random(14, 42),
        contrast = math.random(98, 116),
        span = (mode == 2) and math.random(24, 58) or math.random(80, 130),
        phase = phase,
        brightness = math.random(126, 140),
        saturation = math.random(2, 16),
    }
end

local function ApplyRandomMatchedColors()
    local palette = BuildMatchedPalette()
    local previewTint = nil
    for i, sn in ipairs(ns.slotOrder or {}) do
        local rec = SlotRec(sn)
        rec.tint = rec.tint or {}
        local tint = RandomMatchedTint(sn, palette, i)
        CopyTint(rec.tint, tint)
        rec.appliedTo = ActiveItem(sn)
        if not previewTint then previewTint = tint end
        QueueApplySlot(sn, true, 0.18)
        CleanEmptyRec(sn)
    end
    if previewTint then
        gAllRec.tint = {}
        CopyTint(gAllRec.tint, previewTint)
    end
    RefreshModel(0.30)
end

-- Apply the shared "Color All" template to every slot's tint (donor skins kept).
local function ApplyColorAll()
    local src = NormalizeTint(gAllRec)
    for _, sn in ipairs(ns.slotOrder or {}) do
        local rec = SlotRec(sn)
        rec.tint = rec.tint or {}
        CopyTint(rec.tint, src)
        rec.appliedTo = ActiveItem(sn)
        QueueApplySlot(sn, true, 0.18)
        CleanEmptyRec(sn)
    end
    RefreshModel(0.30)
end

-- Clear the color (tint) on every slot, leaving donor skins intact.
local function ClearColorAll()
    local s = S()
    for _, sn in ipairs(ns.slotOrder or {}) do
        local rec = s.slotRecolor[sn]
        if rec and rec.tint then
            rec.tint.enabled = false
            QueueApplySlot(sn, true, 0.18)
            CleanEmptyRec(sn)
        end
    end
    RefreshModel(0.30)
end

local function BuildCustomizer()
    local f = CreateFrame("Frame", "TM_Skin_Customizer", UIParent)
    -- v6: compacted from 640px to 412px. Tightened top-section spacing (effect/dir
    -- rows) and pulled slider spacing from 40px to 22px. Still hosts all 8 sliders
    -- + 2 reset buttons in the bottom row.
    f:SetSize(372, 412); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true); f:Hide()
    f:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    f:SetBackdropColor(0.05, 0.05, 0.06, 0.98); f:SetBackdropBorderColor(0.8, 0.65, 0.3, 1)
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetPoint("CENTER")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); title:SetPoint("TOPLEFT", 14, -12); title:SetTextColor(1, 0.82, 0.2); f.title = title
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)

    local function T()
        if not f.slot then return nil end
        if f.slot == ALL_SLOTS then return NormalizeTint(gAllRec) end
        return NormalizeTint(SlotRec(f.slot))
    end
    local function Commit()
        local slot = f.slot; if not slot then return end
        if slot == ALL_SLOTS then
            ApplyColorAll()
            if f.onChange then f.onChange() end
            if f.Refresh then f.Refresh() end
            return
        end
        local rec = SlotRec(slot); rec.appliedTo = ActiveItem(slot)
        QueueApplySlot(slot, false, 0.12); CleanEmptyRec(slot)
        if f.onChange then f.onChange() end
        if f.Refresh then f.Refresh() end
    end

    -- Enable
    local enableCb = CreateFrame("CheckButton", nil, f, "ChatConfigCheckButtonTemplate")
    enableCb:SetPoint("TOPLEFT", 12, -32); enableCb:SetSize(24, 24)
    if ns.NormalizeCheckboxHitRect then ns.NormalizeCheckboxHitRect(enableCb) end
    local enLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); enLbl:SetPoint("LEFT", enableCb, "RIGHT", 2, 0); enLbl:SetText("Enable color")
    enableCb:SetScript("OnClick", function() local t = T(); if not t then return end; t.enabled = enableCb:GetChecked() and true or false; Commit() end)
    f.enableCb = enableCb

    -- Mode buttons
    local modeNames = { [0] = "Solid", [1] = "Gradient", [2] = "Rainbow", [3] = "Two-Tone" }
    f.modeBtns = {}
    local mlabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); mlabel:SetPoint("TOPLEFT", 14, -62); mlabel:SetText("Effect")
    for i = 0, 3 do
        local mb = ns.CreateGoldenButton(nil, f); mb:SetSize(84, 22)
        mb:SetPoint("TOPLEFT", 14 + (i % 2) * 92, -76 - math.floor(i / 2) * 24)
        mb:SetText(modeNames[i])
        mb:SetScript("OnClick", function() local t = T(); if not t then return end; t.mode = i; t.enabled = true; t.rainbow = (i == 2); Commit() end)
        f.modeBtns[i] = mb
    end

    -- Color swatches
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

    -- Direction
    local dirNames = { [0] = "Vert", [1] = "Horiz", [2] = "Diag" }
    f.dirBtns = {}
    f.dlbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.dlbl:SetPoint("TOPLEFT", 14, -128); f.dlbl:SetText("Direction")
    for i = 0, 2 do
        local db = ns.CreateGoldenButton(nil, f); db:SetSize(66, 20); db:SetPoint("TOPLEFT", 14 + (i % 3) * 72, -144)
        db:SetText(dirNames[i]); db:SetScript("OnClick", function() local t = T(); if not t then return end; t.dir = i; t.enabled = true; Commit() end)
        f.dirBtns[i] = db
    end

    -- Sliders (OptionsSliderTemplate; 3.3.5 has no SetObeyStepOnDrag)
    local function MakeSlider(x, y, lo, hi, field, fmt)
        local s = CreateFrame("Slider", "TM_Skin_Sl_" .. field, f, "OptionsSliderTemplate")
        s:SetWidth(336); s:SetPoint("TOPLEFT", x, y); s:SetMinMaxValues(lo, hi); s:SetValueStep(1)
        _G[s:GetName() .. "Low"]:SetText(""); _G[s:GetName() .. "High"]:SetText("")
        local txt = _G[s:GetName() .. "Text"]
        s:SetScript("OnValueChanged", function(self, v)
            v = math.floor(v + 0.5); local t = T(); txt:SetText(fmt:format(v)); if not t then return end
            t[field] = v; if not self._silent then t.enabled = true; Commit() end
        end)
        s.txt = txt; return s
    end
    -- v6: compact layout. 22px between sliders (was 40). Sliders start right under
    -- the Direction row. The 8 sliders + 2 reset buttons now fit in 412px total
    -- instead of 640px.
    f.slMult     = MakeSlider(18, -176, 50, 250, "mult",      "Intensity  %d%%")
    f.slGlow     = MakeSlider(18, -198, 0, 255,  "glowStr",   "Glow  %d")
    f.slContrast = MakeSlider(18, -220, 50, 300, "contrast",  "Contrast  %d%%")
    f.slSpan     = MakeSlider(18, -242, 30, 400, "span",      "Rainbow spread  %d%%")
    -- Color shift rotates where the gradient/rainbow starts (drives the persisted
    -- `phase` field). Works on EVERY slot incl. body armor (the SFile path), so the
    -- option set is universal across both texture paths.
    f.slPhase    = MakeSlider(18, -264, 0, 255,  "phase",     "Color shift  %d")
    -- v5 post-effect color transforms. All three are per-pixel post-effects, so they
    -- work in every Effect mode (Solid / Gradient / Rainbow / Two-Tone) and on both
    -- the model-item decode path and the body-component SFile path. Brightness is a
    -- 0..255 scalar (128 = neutral, 0 = black, 255 = 2x). Saturation is -100..+100
    -- (0 = neutral, -100 = grayscale, +100 = 2x vibrancy). Hue shift is 0..255
    -- (0 = no rotation, 128 = 180 deg). All three default to neutral so a fresh slot
    -- is identical to the v4 visual. The format strings show the raw value so the
    -- user sees "Brightness 128" (neutral) rather than misreading a percentage.
    f.slBrightness = MakeSlider(18, -286, 0, 255,  "brightness", "Brightness  %d")
    f.slSaturation = MakeSlider(18, -308, -100, 100, "saturation", "Saturation  %d")
    f.slHueShift   = MakeSlider(18, -330, 0, 255,  "hueShift",   "Hue shift  %d")

    -- Ordered slider rows for dynamic reflow. `vis` decides if the row shows for the
    -- current effect mode; hidden rows are SKIPPED (not just hidden in place) so the
    -- visible sliders always stack with even spacing and the panel never shows a gap.
    f._sliderRows = {
        { s = f.slMult       },
        { s = f.slGlow       },
        { s = f.slContrast   },
        { s = f.slSpan,  vis = function(t) return t.mode == 2 end },   -- Rainbow only
        { s = f.slPhase, vis = function(t) return t.mode ~= 0 end },   -- not Solid
        { s = f.slBrightness },
        { s = f.slSaturation },
        { s = f.slHueShift   },
    }

    -- "Restore Original Values" — resets all 8 slider fields to their neutral
    -- defaults but KEEPS the colors (r/g/b/r2/g2/b2), the Effect mode and the
    -- Color 2 visibility. Useful when the user has cranked every slider to
    -- extremes (as the screenshot shows) and wants to start over without losing
    -- the chosen color scheme or wiping the whole recolor record. Sends ITEM_TINTX
    -- + persists, so the DLL updates and the saved file is rewritten.
    local DEFAULTS = { mult = 130, glowStr = 0, contrast = 100, span = 100, phase = 0,
                       brightness = 128, saturation = 0, hueShift = 0 }
    local rbDefaults = ns.CreateGoldenButton(nil, f); rbDefaults:SetSize(140, 24)
    rbDefaults:SetPoint("BOTTOMLEFT", 14, 12); rbDefaults:SetText("Restore Defaults")
    f.rbDefaults = rbDefaults
    rbDefaults:SetScript("OnClick", function()
        local t = T(); if not t then return end
        for k, v in pairs(DEFAULTS) do t[k] = v end
        -- Keep enabled on so the user can immediately see whether the new defaults
        -- look right with the current colors / mode. Don't touch r/g/b/r2/g2/b2
        -- or mode/dir — those are the "color scheme" the user picked.
        t.enabled = true
        Commit()
    end)

    local rb = ns.CreateGoldenButton(nil, f); rb:SetSize(190, 24)
    rb:SetPoint("BOTTOMRIGHT", -14, 12); rb:SetText("Reset This Item")
    f.rb = rb
    rb:SetScript("OnClick", function()
        local slot = f.slot; if not slot then return end
        if slot == ALL_SLOTS then
            -- "Color All" mode: clear the color on every slot (donor skins kept).
            ClearColorAll()
            if f.onChange then f.onChange() end; if f.Refresh then f.Refresh() end
            return
        end
        S().slotRecolor[slot] = nil
        local idx = ns.slotToMorphSlot and ns.slotToMorphSlot[slot]
        -- One synchronous, self-contained reset for this slot (clears tint+donor+persist
        -- and re-decodes the model item clean in the DLL — no relog, no leftover state).
        if idx then Send("ITEM_SKIN_RESET:" .. idx) end
        lastTint[slot] = nil; lastTintCmd[slot] = nil; lastFrom[slot] = nil; lastRetexTo[slot] = nil; lastPersistCmd[slot] = nil
        RefreshModel(); if f.onChange then f.onChange() end; if f.Refresh then f.Refresh() end
    end)

    local function setSil(s, v) s._silent = true; s:SetValue(v); s._silent = false; s.txt:SetText(s.txt:GetText()) end
    function f.Refresh()
        local t = T(); if not t then return end
        if f.slot == ALL_SLOTS then
            f.title:SetText("Customize Color \226\128\148 All Slots")
            f.rb:SetText("Clear Color (All)")
        else
            f.title:SetText("Customize \226\128\148 " .. (f.slot or ""))
            f.rb:SetText("Reset This Item")
        end
        f.enableCb:SetChecked(t.enabled and true or false)
        f.sw1:SetBackdropColor(t.r / 255, t.g / 255, t.b / 255, 1)
        f.sw2:SetBackdropColor(t.r2 / 255, t.g2 / 255, t.b2 / 255, 1)
        local twoCol = (t.mode == 1 or t.mode == 3)
        if twoCol then f.sw2:Show(); f.sw2lbl:Show() else f.sw2:Hide(); f.sw2lbl:Hide() end
        local hasDir = (t.mode == 1 or t.mode == 2 or t.mode == 3)
        if hasDir then f.dlbl:Show(); for i = 0, 2 do f.dirBtns[i]:Show() end else f.dlbl:Hide(); for i = 0, 2 do f.dirBtns[i]:Hide() end end

        -- Push the current values into every slider (silent so it doesn't Commit).
        setSil(f.slMult, t.mult); setSil(f.slGlow, t.glowStr); setSil(f.slContrast, t.contrast)
        setSil(f.slSpan, t.span); setSil(f.slPhase, t.phase)
        setSil(f.slBrightness, t.brightness); setSil(f.slSaturation, t.saturation); setSil(f.slHueShift, t.hueShift)

        -- Reflow: stack only the visible slider rows with even spacing, skipping any
        -- mode-hidden row so there is never a gap. Then size the panel to fit exactly,
        -- so the Restore/Reset buttons (anchored to the bottom) always sit just below
        -- the last slider regardless of which effect mode is active.
        local SLIDER_PITCH = 32
        local sliderTop = hasDir and -188 or -140    -- below the Direction row, or below Effect
        local y = sliderTop
        for _, row in ipairs(f._sliderRows) do
            if (not row.vis) or row.vis(t) then
                row.s:ClearAllPoints()
                row.s:SetPoint("TOPLEFT", 18, y)
                row.s:Show()
                y = y - SLIDER_PITCH
            else
                row.s:Hide()
            end
        end
        -- `y` is one pitch below the last slider's top; its track bottom is ~18px under
        -- that top. Leave a gap + the 24px button row + a bottom margin.
        local lastTrackBottom = (y + SLIDER_PITCH) - 18
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
    customizer = f
    return f
end

OpenSkinCustomizer = function(slot, onChange)
    local f = customizer or BuildCustomizer()
    f.slot = slot; f.onChange = onChange
    if slot == ALL_SLOTS then NormalizeTint(gAllRec) else NormalizeTint(SlotRec(slot)) end
    f.Refresh(); f:Show(); f:Raise()
end

-- Drop the skin for a slot whose underlying item changed away from what the skin
-- was applied to ("change weapon -> reset the skin of that item"). Returns true
-- if anything was reset.
PruneStaleSkins = function()
    local s = S()
    local changed = false
    for slot, rec in pairs(s.slotRecolor) do
        local cur = ActiveItem(slot)
        if rec.appliedTo and rec.appliedTo > 0 and cur and cur ~= rec.appliedTo then
            local idx = ns.slotToMorphSlot and ns.slotToMorphSlot[slot]
            if lastTint[slot] and idx then Send("ITEM_TINT_SLOT_DEL:" .. idx); lastTint[slot] = nil end
            lastTintCmd[slot] = nil
            if lastFrom[slot] and idx then Send("ITEM_RETEX_SLOT_DEL:" .. idx); lastFrom[slot] = nil end
            lastRetexTo[slot] = nil
            s.slotRecolor[slot] = nil
            -- Also clear the DLL's PERSISTED desire for this slot, otherwise the DLL
            -- reconciler (g_skinToItem) would re-bind the skin to the new weapon and
            -- defeat the "change weapon -> reset its skin" behavior.
            PersistSlot(slot, nil, true)
            changed = true
        end
    end
    return changed
end

local function ItemIcon(itemId)
    if not itemId then return nil end
    return select(10, GetItemInfo(itemId))
end
local function ItemName(itemId)
    if not itemId then return "|cff808080(empty)|r" end
    return (GetItemInfo(itemId)) or ("Item " .. itemId)
end

local catalogCache = {}
local function CatalogForSlot(slot)
    if catalogCache[slot] then return catalogCache[slot] end
    local out, seen = {}, {}
    local subs = ns.slotSubclasses and ns.slotSubclasses[slot]
    if subs then
        for _, sub in ipairs(subs) do
            local recs = ns.GetSubclassRecords and ns.GetSubclassRecords(slot, sub)
            if recs then
                for _, data in ipairs(recs) do
                    local id = data[1] and data[1][1]
                    local nm = data[2] and data[2][1]
                    if id and not seen[id] then
                        seen[id] = true
                        out[#out + 1] = { id = id, name = nm or ("Item " .. id) }
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        local an = (a.name or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local bn = (b.name or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        return an < bn
    end)
    catalogCache[slot] = out
    return out
end

-- ============================================================
-- Init (called once, lazily, by PreviewTab when the Skin sub-tab opens)
-- ============================================================
function ns.InitSkinTab(parent)
    -- ---- header bar ----
    local header = CreateFrame("Frame", nil, parent)
    header:SetPoint("TOPLEFT", 6, -6); header:SetPoint("TOPRIGHT", -6, -6); header:SetHeight(40)
    header:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    header:SetBackdropColor(0.08, 0.08, 0.08, 0.95); header:SetBackdropBorderColor(0.35, 0.30, 0.18, 0.9)

    local headerTitle = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerTitle:SetPoint("LEFT", 12, 0); headerTitle:SetTextColor(1.0, 0.84, 0.40); headerTitle:SetText("Item Skins")

    local resetAllBtn = ns.CreateGoldenButton(nil, header)
    resetAllBtn:SetSize(96, 24); resetAllBtn:SetPoint("RIGHT", -10, 0); resetAllBtn:SetText("Reset All")

    -- Color every slot at once (works whether or not a slot has a donor skin).
    local colorAllBtn = ns.CreateGoldenButton(nil, header)
    colorAllBtn:SetSize(96, 24); colorAllBtn:SetPoint("RIGHT", resetAllBtn, "LEFT", -8, 0); colorAllBtn:SetText("Color All")

    local randomAllBtn = ns.CreateGoldenButton(nil, header)
    randomAllBtn:SetSize(86, 24); randomAllBtn:SetPoint("RIGHT", colorAllBtn, "LEFT", -8, 0); randomAllBtn:SetText("Random")

    local headerDesc = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    headerDesc:SetPoint("RIGHT", randomAllBtn, "LEFT", -12, 0); headerDesc:SetTextColor(0.78, 0.78, 0.78)
    headerDesc:SetText("Re-skin & color items per slot")

    -- ---- donor picker popup ----
    local picker = CreateFrame("Frame", "TM_Skin_Picker", parent)
    skinPickerFrame = picker
    picker:SetSize(280, 360); picker:SetFrameStrata("DIALOG"); picker:Hide()
    picker:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    picker:SetBackdropColor(0.05, 0.05, 0.06, 0.97); picker:SetBackdropBorderColor(0.8, 0.65, 0.3, 1)
    local pkTitle = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal"); pkTitle:SetPoint("TOPLEFT", 12, -10)
    local pkClose = CreateFrame("Button", nil, picker, "UIPanelCloseButton"); pkClose:SetPoint("TOPRIGHT", 2, 2)
    pkClose:SetScript("OnClick", function() picker:Hide() end)
    local pkFilter = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
    pkFilter:SetSize(230, 18); pkFilter:SetPoint("TOPLEFT", 14, -32); pkFilter:SetAutoFocus(false)
    pkFilter:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local pkBg = CreateFrame("Frame", nil, picker); pkBg:SetPoint("TOPLEFT", 10, -56); pkBg:SetPoint("BOTTOMRIGHT", -10, 10)
    local pkScroll = CreateFrame("ScrollFrame", "TM_Skin_PickerScroll", pkBg, "UIPanelScrollFrameTemplate")
    pkScroll:SetPoint("TOPLEFT", 0, 0); pkScroll:SetPoint("BOTTOMRIGHT", -24, 0)
    local pkContent = CreateFrame("Frame", nil, pkScroll); pkContent:SetSize(240, 1); pkScroll:SetScrollChild(pkContent)
    local pkRows = {}; local pkSlot, pkOnPick = nil, nil

    local function PickerPopulate()
        local items = pkSlot and CatalogForSlot(pkSlot) or {}
        local ft = (pkFilter:GetText() or ""):lower()
        for _, r in ipairs(pkRows) do r:Hide() end
        local shown = 0
        for _, it in ipairs(items) do
            local plain = (it.name or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
            if ft == "" or plain:find(ft, 1, true) then
                shown = shown + 1
                local r = pkRows[shown]
                if not r then
                    r = CreateFrame("Button", nil, pkContent); r:SetSize(214, 18)
                    local ic = r:CreateTexture(nil, "ARTWORK"); ic:SetSize(16, 16); ic:SetPoint("LEFT", 2, 0); ic:SetTexCoord(0.08,0.92,0.08,0.92); r.ic = ic
                    local t = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); t:SetPoint("LEFT", ic, "RIGHT", 4, 0); t:SetPoint("RIGHT", -2, 0); t:SetJustifyH("LEFT"); r.t = t
                    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetTexture(0.96, 0.78, 0.26, 0.18); r:SetHighlightTexture(hl)
                    pkRows[shown] = r
                end
                r.item = it
                r.ic:SetTexture(ItemIcon(it.id) or QUESTION); r.t:SetText(it.name or ("Item " .. it.id))
                r:SetScript("OnClick", function(self) if pkOnPick then pkOnPick(self.item) end; picker:Hide() end)
                r:SetPoint("TOPLEFT", 0, -((shown - 1) * 18)); r:Show()
                if shown >= 400 then break end
            end
        end
        pkContent:SetHeight(math.max(1, shown * 18))
    end
    pkFilter:SetScript("OnTextChanged", PickerPopulate)
    local function OpenPicker(slot, anchor, onPick)
        pkSlot = slot; pkOnPick = onPick
        pkTitle:SetText("Choose a look \226\128\148 " .. slot); pkFilter:SetText("")
        picker:ClearAllPoints(); picker:SetPoint("CENTER", parent, "CENTER", 0, 0); picker:Show(); picker:Raise()
        PickerPopulate()
    end

    -- ---- scrollable card grid ----
    local scroll = CreateFrame("ScrollFrame", "TM_Skin_Scroll", parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 10)
    local content = CreateFrame("Frame", nil, scroll); content:SetSize(10, 10); scroll:SetScrollChild(content)

    local cards = {}
    local cols = 2
    local gapX, gapY = 10, 12
    -- Clean vertical bands, no overlap (y measured from the card top):
    --   ICON row   (10..50)  : 40px icon (left) + name + worn (right of icon)
    --   LOOK row   (56)      : "-> donor look" line, FULL card width
    --   COLOR row  (80)      : "Customize Color" button + tint chip
    --   BUTTON row (bottom)  : "Choose Look/Change" + "Reset", 12px from card bottom
    -- Text fonts are single-line (truncate) and their widths are set in Relayout so
    -- nothing ever bleeds into the icon or the next band, at any column width.
    local ICON_SIZE       = 40
    local TEXT_LEFT       = 10 + 40 + 8   -- right edge of icon + gap (matches ICON_SIZE)
    local cardHeight = 140

    local function RefreshCard(card)
        local slot = card.slot
        local active = ActiveItem(slot)
        local rec = S().slotRecolor[slot]
        local tintOn = IsTintSlot(slot) and TintActive(rec)
        -- Worn line
        card.worn:SetText(active and ("|cffBBBBBBWearing:|r " .. ItemName(active)) or "|cff808080(nothing here)|r")
        if rec and rec.to then
            card.look:SetText("|cff88ff88Look:|r " .. (rec.toName or ItemName(rec.to)))
            -- Show the donor item icon (what it will look like) + glow.
            card.icon:SetTexture(ItemIcon(rec.to) or ItemIcon(active) or (ns.slotTextures and ns.slotTextures[slot]) or QUESTION)
            card.actionBtn:SetText("Change")
        else
            card.look:SetText("|cff707070Default look|r")
            card.icon:SetTexture(ItemIcon(active) or (ns.slotTextures and ns.slotTextures[slot]) or QUESTION)
            card.actionBtn:SetText("Choose Look")
        end

        if (rec and rec.to) or tintOn then
            card.glow:Show()
            if card.iconBorder then ns.ShowMorphGlow(card.iconBorder, "gold") end
            card:SetBackdropBorderColor(0.78, 0.62, 0.22, 0.9)
            card.resetBtn:Show()
        else
            card.glow:Hide()
            if card.iconBorder then ns.HideMorphGlow(card.iconBorder) end
            card:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)
            card.resetBtn:Hide()
        end

        if card.custBtn then
            local t = rec and rec.tint and NormalizeTint(rec) or nil
            if t and t.enabled then
                local modeName = ({ [0] = "Solid", [1] = "Gradient", [2] = "Rainbow", [3] = "Two-Tone" })[t.mode or 0] or "Solid"
                card.custBtn:SetText(modeName)
                card.tintChip:Show()
                card.tintChip:SetVertexColor((t.r or 255) / 255, (t.g or 80) / 255, (t.b or 80) / 255)
            else
                card.custBtn:SetText("Customize Color")
                card.tintChip:Hide()
            end
        end
    end

    local function RefreshAll() for _, card in ipairs(cards) do RefreshCard(card) end end

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
            local topTextW = math.max(40, cardWidth - TEXT_LEFT - 12)
            if card.name and card.name.SetWidth then card.name:SetWidth(topTextW) end
            if card.worn and card.worn.SetWidth then card.worn:SetWidth(topTextW) end
            if card.look and card.look.SetWidth then card.look:SetWidth(math.max(40, cardWidth - 20)) end
            local btnW = math.max(86, math.min(cardWidth - 92, math.floor((cardWidth - 30) * 0.60)))
            card.actionBtn:SetWidth(btnW)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", 2 + col * (cardWidth + gapX), -(row * (cardHeight + gapY)))
            col = col + 1
            if col >= cols then col = 0; row = row + 1 end
        end
        local totalRows = row + (col > 0 and 1 or 0)
        content:SetHeight(math.max(scroll:GetHeight() or 1, totalRows * (cardHeight + gapY)))
    end

    local function BuildCard(slot)
        local card = CreateFrame("Frame", nil, content)
        card.slot = slot
        card:SetHeight(cardHeight)
        card:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        card:SetBackdropColor(0.05, 0.05, 0.05, 0.9); card:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)

        local glow = card:CreateTexture(nil, "BACKGROUND")
        glow:SetPoint("TOPLEFT", 1, -1); glow:SetPoint("BOTTOMRIGHT", -1, 1)
        glow:SetTexture("Interface\\Buttons\\WHITE8X8"); glow:SetVertexColor(0.50, 0.35, 0.08, 0.22); glow:Hide()
        card.glow = glow

        local iconBorder = CreateFrame("Frame", nil, card)
        iconBorder:SetPoint("TOPLEFT", 10, -10); iconBorder:SetSize(44, 44)
        iconBorder:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        iconBorder:SetBackdropColor(0.07, 0.07, 0.07, 1); iconBorder:SetBackdropBorderColor(0.35, 0.30, 0.18, 0.9)
        local icon = iconBorder:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 2, -2); icon:SetPoint("BOTTOMRIGHT", -2, 2); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        card.icon = icon; card.iconBorder = iconBorder

        -- Three explicit vertical bands so nothing can overlap:
        --  TOP    : icon (10..54) and right-hand name + worn + look text column.
        --           The right-hand text is bounded TOP at 10px from the card top
        --           and BOTTOM at 60px, so it cannot bleed into the button band.
        --  MID    : "Customize Color" row, only on tint slots.
        --  BOTTOM : Choose-Look + Reset buttons anchored to the card's bottom.
        local TEXT_BAND_BOTTOM = 72   -- y from card top where the text block ends

        local nameText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 10, -1)
        nameText:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -1)
        nameText:SetJustifyH("LEFT"); nameText:SetWordWrap(false)
        nameText:SetTextColor(0.96, 0.90, 0.72); nameText:SetText(slot)
        card.name = nameText

        local worn = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        worn:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2)
        worn:SetJustifyH("LEFT"); worn:SetWordWrap(false); card.worn = worn

        local look = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        look:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -56)
        look:SetJustifyH("LEFT"); look:SetWordWrap(false); card.look = look

        if IsTintSlot(slot) then
            -- "Customize Color" sits in the middle band, not the bottom band, so
            -- tint slots get the same two-button row as non-tint slots in the
            -- bottom band.
            local custBtn = ns.CreateGoldenButton(nil, card)
            custBtn:SetSize(150, 22); custBtn:SetPoint("TOPLEFT", 10, -(TEXT_BAND_BOTTOM + 8))
            custBtn:SetText("Customize Color")
            card.custBtn = custBtn
            local chip = card:CreateTexture(nil, "OVERLAY")
            chip:SetSize(14, 14); chip:SetPoint("LEFT", custBtn, "RIGHT", 6, 0)
            chip:SetTexture("Interface\\Buttons\\WHITE8X8"); chip:Hide()
            card.tintChip = chip
            custBtn:SetScript("OnClick", function()
                OpenSkinCustomizer(slot, function() RefreshCard(card) end)
            end)
        end

        local actionBtn = ns.CreateGoldenButton(nil, card)
        actionBtn:SetSize(96, 22); actionBtn:SetPoint("BOTTOMLEFT", 10, 10)
        card.actionBtn = actionBtn

        local resetBtn = ns.CreateGoldenButton(nil, card)
        resetBtn:SetSize(68, 22); resetBtn:SetPoint("LEFT", actionBtn, "RIGHT", 6, 0); resetBtn:SetText("Reset")
        card.resetBtn = resetBtn

        actionBtn:SetScript("OnClick", function()
            OpenPicker(slot, card, function(it)
                local rec = S().slotRecolor
                local oldTint = rec[slot] and rec[slot].tint
                rec[slot] = { to = it.id, toName = it.name, appliedTo = ActiveItem(slot), tint = oldTint }
                ApplySlot(slot); RefreshCard(card)
                PlaySound("gsTitleOptionOK")
            end)
        end)
        resetBtn:SetScript("OnClick", function()
            S().slotRecolor[slot] = nil
            local idx = ns.slotToMorphSlot and ns.slotToMorphSlot[slot]
            -- Single synchronous, self-contained slot reset (see customizer reset above).
            if idx then Send("ITEM_SKIN_RESET:" .. idx) end
            lastTint[slot] = nil; lastTintCmd[slot] = nil; lastFrom[slot] = nil; lastRetexTo[slot] = nil; lastPersistCmd[slot] = nil
            RefreshModel(); RefreshCard(card)
            PlaySound("gsTitleOptionOK")
        end)

        return card
    end

    for _, slot in ipairs(ns.slotOrder or {}) do cards[#cards + 1] = BuildCard(slot) end
    scroll:SetScript("OnSizeChanged", Relayout)

    colorAllBtn:SetScript("OnClick", function()
        OpenSkinCustomizer(ALL_SLOTS, function() RefreshAll() end)
        PlaySound("gsTitleOptionOK")
    end)

    randomAllBtn:SetScript("OnClick", function()
        ApplyRandomMatchedColors()
        RefreshAll()
        PlaySound("gsTitleOptionOK")
    end)

    resetAllBtn:SetScript("OnClick", function()
        ns.Skin_ResetAll(false)
        RefreshAll()
        PlaySound("gsTitleOptionOK")
    end)

    parent.RefreshSkinCards = function() PruneStaleSkins(); RefreshAll() end
    parent:SetScript("OnShow", function() Relayout(); PruneStaleSkins(); RefreshAll() end)
    ns.RunAfter(0.05, function() Relayout(); RefreshAll() end)
end

-- ============================================================
-- Auto-reset / re-sync skins when gear or transmog changes.
-- (Works even if the Skin tab was never opened this session.)
-- ============================================================
do
    local pending = CreateFrame("Frame"); pending:Hide(); pending.t = 0
    pending:SetScript("OnUpdate", function(self, dt)
        self.t = self.t - (dt or 0)
        if self.t > 0 then return end
        self:Hide()
        PruneStaleSkins()  -- drop skins whose item changed (reset on weapon change)
        local s = S()
        for slot in pairs(s.slotRecolor) do QueueApplySlot(slot, true, 0.18) end
        RefreshModel(0.45)
        local previewTab = mainFrame.tabs and mainFrame.tabs.preview
        local skinTab = previewTab and previewTab.skinSubTab
        if skinTab and skinTab:IsShown() and skinTab.RefreshSkinCards then skinTab.RefreshSkinCards() end
    end)
    local function schedule(delay)
        local d = delay or 0.45
        pending.t = math.max(pending.t or 0, d)
        pending:Show()
        if skinApplyQueue and skinApplyQueue:IsShown() then
            skinApplyQueue.t = math.max(skinApplyQueue.t or 0, d)
        end
    end

    local function SafeRegister(frame, event)
        if frame and frame.RegisterEvent then pcall(frame.RegisterEvent, frame, event) end
    end

    local ev = CreateFrame("Frame")
    SafeRegister(ev, "PLAYER_EQUIPMENT_CHANGED")
    SafeRegister(ev, "UNIT_MODEL_CHANGED")
    SafeRegister(ev, "GLYPH_ADDED")
    SafeRegister(ev, "GLYPH_REMOVED")
    SafeRegister(ev, "GLYPH_UPDATED")
    SafeRegister(ev, "PLAYER_TALENT_UPDATE")
    SafeRegister(ev, "ACTIVE_TALENT_GROUP_CHANGED")
    ev:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_MODEL_CHANGED" and unit ~= "player" then return end
        if event == "PLAYER_EQUIPMENT_CHANGED" then
            schedule(0.45)
        else
            -- Glyph/talent/model updates can stream/rebuild BLPs for a few frames.
            -- Wait longer before skin reconciliation touches ColorEngine state.
            schedule(0.90)
        end
    end)

    local function CommandChangesVisibleItems(cmd)
        if type(cmd) ~= "string" then return false end
        for part in cmd:gmatch("[^|]+") do
            if part:match("^ITEM:%-?%d+:") or part:match("^RESET:%d+$") or part == "RESET:ALL" or part == "REFRESH" then
                return true
            end
        end
        return false
    end

    local function WrapSender(field, flag)
        if ns[field] and not ns[flag] then
            ns[flag] = true
            local orig = ns[field]
            ns[field] = function(cmd, ...)
                local rv = orig(cmd, ...)
                if CommandChangesVisibleItems(cmd) then schedule(0.45) end
                return rv
            end
        end
    end

    -- Morphing/resetting a slot changes the shown item too, so re-sync skins for
    -- both tracked and raw command paths. This covers single switches and batches.
    WrapSender("SendMorphCommand", "_skinSyncWrappedMorph")
    WrapSender("SendRawMorphCommand", "_skinSyncWrappedRaw")
end
