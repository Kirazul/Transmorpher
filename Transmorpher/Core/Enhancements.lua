local addon, ns = ...

-- ============================================================
-- ENHANCEMENTS — Quality-of-life feature pack
-- Random morph, morph-into-target, undo history, recent morphs,
-- show/hide helm + cloak, screenshot, camera FOV control.
--
-- Everything here reuses Transmorpher's existing, working morph
-- bridge (ns.SendMorphCommand -> DLL) or documented 3.3.5a API,
-- so it is reliable and side-effect free.
-- ============================================================

local MAX_RECENT = 12
local MAX_HISTORY = 40

ns.morphHistory = ns.morphHistory or {}   -- session undo stack of display IDs
local recording = true                    -- suppressed during undo to avoid loops

local function Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffF5C842Transmorpher:|r " .. msg)
    end
end
ns.EnhPrint = Print

-- ------------------------------------------------------------
-- History + Recent tracking (hooks the central send function)
-- ------------------------------------------------------------
local function RecordMorph(displayId)
    -- Undo history (skip consecutive duplicates)
    local h = ns.morphHistory
    if h[#h] ~= displayId then
        h[#h + 1] = displayId
        if #h > MAX_HISTORY then table.remove(h, 1) end
    end

    -- Recent list (account-wide, MRU, only real morphs)
    if displayId and displayId > 0 then
        local s = ns.GetSettings()
        s.recentMorphs = s.recentMorphs or {}
        local r = s.recentMorphs
        for i = #r, 1, -1 do
            if r[i] == displayId then table.remove(r, i) end
        end
        table.insert(r, 1, displayId)
        while #r > MAX_RECENT do table.remove(r) end
    end
end

-- Wrap ns.SendMorphCommand once it exists (this file loads after DLLBridge).
do
    local origSend = ns.SendMorphCommand
    if type(origSend) == "function" and not ns._enhSendWrapped then
        ns._enhSendWrapped = true
        ns.SendMorphCommand = function(cmd)
            if recording and type(cmd) == "string" then
                local id = cmd:match("^MORPH:(%-?%d+)$")
                if id then RecordMorph(tonumber(id)) end
            end
            return origSend(cmd)
        end
    end
end

-- ------------------------------------------------------------
-- Random creature morph ("Surprise Me")
-- ------------------------------------------------------------
local randomPool = nil
local function BuildRandomPool()
    if randomPool then return randomPool end
    randomPool = {}
    local db = ns.creatureDisplayDB
    if db then
        for did in pairs(db) do
            local n = tonumber(did)
            if n and n > 0 then randomPool[#randomPool + 1] = n end
        end
    end
    return randomPool
end

-- Refresh every piece of UI that reflects the active morph. Called after a morph
-- changes through ANY path (race buttons, Random, Copy Target, ...) so they all
-- behave identically and the panel/slots/preview stay in sync with the state.
function ns.RefreshMorphUIAfterChange()
    if ns.UpdatePreviewModel then ns.UpdatePreviewModel() end
    if ns.UpdateSpecialSlots then ns.UpdateSpecialSlots() end
    if ns.SyncDressingRoom then ns.SyncDressingRoom() end
    if ns.UpdateMorphStatusBar then ns.UpdateMorphStatusBar() end
end

-- Invoked BY THE DLL (FrameScript_Execute) after MORPH_GUID resolves a target's
-- display id, which Lua cannot read itself. This makes "Copy Target" land in the
-- canonical state and show in the panel exactly like every other morph instead of
-- being an independent, untracked side effect.
function _G.TransmorpherAdoptMorph(disp)
    disp = tonumber(disp)
    if not disp or disp <= 0 then return end
    if not TransmorpherCharacterState then TransmorpherCharacterState = {} end
    TransmorpherCharacterState.Morph = disp
    ns.RefreshMorphUIAfterChange()
end

function ns.Enh_RandomMorph()
    if not ns.IsMorpherReady or not ns.IsMorpherReady() then
        Print("DLL not ready.")
        return
    end
    local pool = BuildRandomPool()
    if #pool == 0 then Print("No creature data loaded.") return end
    local did = pool[math.random(1, #pool)]
    ns.SendMorphCommand("MORPH:" .. did)
    ns.RefreshMorphUIAfterChange()
    local name = ns.creatureDisplayDB and ns.creatureDisplayDB[did]
    Print("Random morph: " .. (name or ("Display " .. did)) .. " (|cff888888" .. did .. "|r)")
end

-- ------------------------------------------------------------
-- Morph into current target's display (DLL reads the GUID)
-- ------------------------------------------------------------
function ns.Enh_MorphTarget(unit)
    unit = unit or "target"
    if not UnitExists(unit) then Print("No valid " .. unit .. ".") return end
    local guid = UnitGUID(unit)
    if not guid then Print("Could not read GUID.") return end
    -- Strip a leading 0x if present; DLL parses hex either way.
    guid = guid:gsub("^0[xX]", "")
    -- Tell the DLL whether this is a player (copy their transmog gear) or an
    -- NPC/creature (clone the display only). Copying gear off a creature reads
    -- junk item ids and produces a naked, race-merged morph.
    local isPlayer = (UnitIsPlayer and UnitIsPlayer(unit)) and 1 or 0
    ns.SendMorphCommand("MORPH_GUID:" .. guid .. ":" .. isPlayer)
    if ns.UpdatePreviewModel then ns.UpdatePreviewModel() end
    Print("Morphing into " .. (UnitName(unit) or unit) .. "'s appearance.")
end

-- ------------------------------------------------------------
-- Undo last character morph
-- ------------------------------------------------------------
function ns.Enh_Undo()
    local h = ns.morphHistory
    if #h <= 1 then
        -- nothing earlier to go back to -> clear morph
        h[1] = nil
        recording = false
        ns.SendMorphCommand("MORPH:0")
        recording = true
        Print("Reverted character morph.")
        return
    end
    table.remove(h)                 -- drop current
    local prev = h[#h]              -- previous becomes active
    recording = false
    ns.SendMorphCommand("MORPH:" .. (prev or 0))
    recording = true
    if ns.UpdatePreviewModel then ns.UpdatePreviewModel() end
    Print("Undo -> " .. ((prev and prev > 0) and ("display " .. prev) or "no morph"))
end

-- ------------------------------------------------------------
-- Re-apply a recent morph
-- ------------------------------------------------------------
function ns.Enh_GetRecent()
    local s = ns.GetSettings()
    return s.recentMorphs or {}
end

function ns.Enh_ApplyDisplay(did)
    did = tonumber(did)
    if not did or did <= 0 then return end
    ns.SendMorphCommand("MORPH:" .. did)
    if ns.UpdatePreviewModel then ns.UpdatePreviewModel() end
end

-- ------------------------------------------------------------
-- Show / hide helm and cloak (documented 3.3.5a API, persists)
-- ------------------------------------------------------------
function ns.Enh_ToggleHelm()
    local s = ns.GetSettings()
    s.hideHelm = not s.hideHelm
    if ShowHelm then ShowHelm(s.hideHelm and 0 or 1) end
    Print(s.hideHelm and "Helm hidden." or "Helm shown.")
    return s.hideHelm
end

function ns.Enh_ToggleCloak()
    local s = ns.GetSettings()
    s.hideCloak = not s.hideCloak
    if ShowCloak then ShowCloak(s.hideCloak and 0 or 1) end
    Print(s.hideCloak and "Cloak hidden." or "Cloak shown.")
    return s.hideCloak
end

-- Re-apply stored helm/cloak preference on login so it matches the UI.
local hcFrame = CreateFrame("Frame")
hcFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
hcFrame:SetScript("OnEvent", function()
    local s = ns.GetSettings()
    if ShowHelm and s.hideHelm ~= nil then ShowHelm(s.hideHelm and 0 or 1) end
    if ShowCloak and s.hideCloak ~= nil then ShowCloak(s.hideCloak and 0 or 1) end
end)

-- ------------------------------------------------------------
-- Screenshot
-- ------------------------------------------------------------
function ns.Enh_Screenshot()
    if Screenshot then Screenshot() end
end

-- ------------------------------------------------------------
-- Camera field of view (handled by the DLL; 0 = client default)
-- ------------------------------------------------------------
function ns.Enh_SetFov(deg)
    deg = tonumber(deg) or 0
    if deg ~= 0 then
        if deg < 20 then deg = 20 elseif deg > 350 then deg = 350 end
    end
    local s = ns.GetSettings()
    s.cameraFov = deg
    if ns.SendMorphCommand then ns.SendMorphCommand("SET:CAMERA_FOV:" .. deg) end
    return deg
end

function ns.Enh_GetFov()
    local s = ns.GetSettings()
    return s.cameraFov or 0
end
