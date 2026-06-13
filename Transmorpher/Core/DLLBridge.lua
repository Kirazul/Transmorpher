local addon, ns = ...

function ns.SyncOptimizationTierProtection()
    if not ns.IsMorpherReady or not ns.IsMorpherReady() then return end

    local settings = ns.GetSettings()
    local cmdQueue = {}
    local tierOptions = ns.optimizationTierOptions or {}

    for _, tier in ipairs(tierOptions) do
        local enabled = settings[tier.settingKey] and "1" or "0"
        table.insert(cmdQueue, "SET:PROTECTED_TIER:" .. tier.key .. ":" .. enabled)
    end

    if #cmdQueue > 0 then
        ns.SendRawMorphCommand(table.concat(cmdQueue, "|"))
    end
end

local function NormalizeHdFontMode(settings)
    local hdFontMode = tonumber(settings.miscHdFontMode) or 0
    if hdFontMode <= 0 then hdFontMode = 0 else hdFontMode = 1 end
    settings.miscHdFontMode = hdFontMode
    return hdFontMode
end

-- ============================================================
-- TRANSMORPHER DLL BRIDGE
-- Communication with the Transmorpher C++ DLL via global
-- variables. The DLL polls TRANSMORPHER_CMD every ~20ms.
-- ============================================================

-- Global variables the DLL interacts with
TRANSMORPHER_CMD = ""             -- DLL reads this for commands
-- Preserve the DLL-owned loaded flag across reloads/character swaps.
TRANSMORPHER_DLL_LOADED = TRANSMORPHER_DLL_LOADED
TRANSMORPHER_LUA_READY = nil      -- Addon sets this when the world-side Lua environment is ready for DLL interaction
TRANSMORPHER_ANALYSIS_CFG = ""    -- DLL reads this for analysis render config
TRANSMORPHER_ENV_CFG = ""         -- DLL reads this for misc fog/far clip config

-- ============================================================
-- COMMAND TRACKING
-- Persist morph commands into TransmorpherCharacterState so
-- they survive /reload and character logout.
-- ============================================================

local function InitCharacterState()
    if not TransmorpherCharacterState then
        TransmorpherCharacterState = {
            Items = {},
            Morph = nil,
            Scale = nil,
            MountDisplay = nil,
            PetDisplay = nil,
            Mounts = {}, -- Per-mount morphs: [spellID] = displayID
            MountHidden = false, -- Toggle for mount invisibility
            HunterPetDisplay = nil,
            HunterPetScale = nil,
            EnchantMH = nil,
            EnchantOH = nil,
            TitleID = nil,
            WeaponSets = {},
            Forms = {},
            SpellMorphs = {},
            HiddenItems = {}, -- [slotId] = true
        }
    end
    if not TransmorpherCharacterState.Items then TransmorpherCharacterState.Items = {} end
    if not TransmorpherCharacterState.HiddenItems then TransmorpherCharacterState.HiddenItems = {} end
    if not TransmorpherCharacterState.Mounts then TransmorpherCharacterState.Mounts = {} end
    if not TransmorpherCharacterState.WeaponSets then TransmorpherCharacterState.WeaponSets = {} end
    if not TransmorpherCharacterState.SpellMorphs then TransmorpherCharacterState.SpellMorphs = {} end
end

-- Helper: get weapon set key from equipped weapons
local function GetWeaponSetKey()
    local mainHand = GetInventoryItemLink("player", 16) or "0"
    local offHand  = GetInventoryItemLink("player", 17) or "0"
    return mainHand .. "|" .. offHand
end
ns.GetWeaponSetKey = GetWeaponSetKey

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

local function AddFlyoutSpellIds(flyoutId, seen, ids)
    if not flyoutId or flyoutId <= 0 then return end
    if type(GetFlyoutInfo) ~= "function" or type(GetFlyoutSlotInfo) ~= "function" then return end

    local _, _, numSlots = GetFlyoutInfo(flyoutId)
    if not numSlots or numSlots <= 0 then return end

    for slot = 1, numSlots do
        local spellId = GetFlyoutSlotInfo(flyoutId, slot)
        spellId = tonumber(spellId)
        if spellId and spellId > 0 and not seen[spellId] then
            seen[spellId] = true
            table.insert(ids, spellId)
        end
    end
end

local function GetPlayerSpellbookSpellIds()
    local ids, seen = {}, {}
    local bookType = BOOKTYPE_SPELL or "spell"
    local numTabs = GetNumSpellTabs() or 0
    for tab = 1, numTabs do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        if offset and numSpells then
            for i = 1, numSpells do
                local index = offset + i
                if type(GetSpellBookItemInfo) == "function" then
                    local spellType, spellId = GetSpellBookItemInfo(index, bookType)
                    spellId = tonumber(spellId)

                    if spellType == "SPELL" and spellId and spellId > 0 and not seen[spellId] then
                        seen[spellId] = true
                        table.insert(ids, spellId)
                    elseif spellType == "FLYOUT" and spellId and spellId > 0 then
                        AddFlyoutSpellIds(spellId, seen, ids)
                    end
                else
                    local spellId = GetSpellBookSpellId(index)
                    if spellId and spellId > 0 and not seen[spellId] then
                        seen[spellId] = true
                        table.insert(ids, spellId)
                    end
                end
            end
        end
    end
    table.sort(ids)
    return ids
end

local spellbookChunkTimer = CreateFrame("Frame")
spellbookChunkTimer:Hide()
spellbookChunkTimer.remaining = 0

local spellbookDebounceTimer = CreateFrame("Frame")
spellbookDebounceTimer:Hide()
spellbookDebounceTimer.remaining = 0

local pendingSpellbookChunks = nil
local pendingSpellbookChunkIndex = 1
local lastSyncedSpellbookSet = nil
local pendingSpellbookSetAfterFlush = nil
local spellbookSyncQueued = false

local function BuildSpellbookSet(ids)
    local set = {}
    for _, id in ipairs(ids) do
        set[id] = true
    end
    return set
end

local function BuildSpellbookSyncChunks(commands)
    local chunks = {}
    local current = ""
    local maxLen = 3000

    for _, cmd in ipairs(commands) do
        if current == "" then
            current = cmd
        else
            local mergedLen = string.len(current) + 1 + string.len(cmd)
            if mergedLen > maxLen then
                table.insert(chunks, current)
                current = cmd
            else
                current = current .. "|" .. cmd
            end
        end
    end

    if current ~= "" then
        table.insert(chunks, current)
    end

    return chunks
end

local function QueueSpellbookSync(commands)
    table.insert(commands, "SPELL_PLAYER_BOOK_COMMIT")

    pendingSpellbookChunks = BuildSpellbookSyncChunks(commands)
    pendingSpellbookChunkIndex = 1

    if pendingSpellbookChunks[1] then
        ns.SendRawMorphCommand(pendingSpellbookChunks[1])
        pendingSpellbookChunkIndex = 2
    end

    if pendingSpellbookChunkIndex <= #pendingSpellbookChunks then
        spellbookChunkTimer.remaining = 0.05
        spellbookChunkTimer:Show()
    else
        if pendingSpellbookSetAfterFlush then
            lastSyncedSpellbookSet = pendingSpellbookSetAfterFlush
            pendingSpellbookSetAfterFlush = nil
        end
        spellbookChunkTimer:Hide()
    end
end

spellbookChunkTimer:SetScript("OnUpdate", function(self, elapsed)
    self.remaining = self.remaining - elapsed
    if self.remaining > 0 then return end

    if not pendingSpellbookChunks or pendingSpellbookChunkIndex > #pendingSpellbookChunks then
        if pendingSpellbookSetAfterFlush then
            lastSyncedSpellbookSet = pendingSpellbookSetAfterFlush
            pendingSpellbookSetAfterFlush = nil
        end
        self:Hide()
        return
    end

    if TRANSMORPHER_CMD and TRANSMORPHER_CMD ~= "" then
        self.remaining = 0.05
        return
    end

    ns.SendRawMorphCommand(pendingSpellbookChunks[pendingSpellbookChunkIndex])
    pendingSpellbookChunkIndex = pendingSpellbookChunkIndex + 1
    self.remaining = 0.05
end)

function ns.SyncPlayerSpellbookVisibility(forceFull)
    if not ns.IsMorpherReady() then return end

    local spellIds = GetPlayerSpellbookSpellIds()
    local currentSet = BuildSpellbookSet(spellIds)
    local commands = {}

    local requireFull = forceFull or (not lastSyncedSpellbookSet)
    if not requireFull and lastSyncedSpellbookSet then
        for spellId, _ in pairs(lastSyncedSpellbookSet) do
            if not currentSet[spellId] then
                requireFull = true
                break
            end
        end
    end

    if requireFull then
        table.insert(commands, "SPELL_PLAYER_BOOK_CLEAR")
        for _, spellId in ipairs(spellIds) do
            table.insert(commands, "SPELL_PLAYER_BOOK_ADD:" .. spellId)
        end
    else
        for _, spellId in ipairs(spellIds) do
            if not lastSyncedSpellbookSet[spellId] then
                table.insert(commands, "SPELL_PLAYER_BOOK_ADD:" .. spellId)
            end
        end
        if #commands == 0 then
            return
        end
    end

    QueueSpellbookSync(commands)
    pendingSpellbookSetAfterFlush = currentSet
end

function ns.RequestPlayerSpellbookVisibilitySync(immediate)
    if immediate then
        spellbookSyncQueued = false
        spellbookDebounceTimer:Hide()
        ns.SyncPlayerSpellbookVisibility(false)
        return
    end

    spellbookSyncQueued = true
    spellbookDebounceTimer.remaining = 0.2
    spellbookDebounceTimer:Show()
end

function ns.InvalidatePlayerSpellbookVisibilityCache()
    lastSyncedSpellbookSet = nil
    pendingSpellbookSetAfterFlush = nil
    pendingSpellbookChunks = nil
    pendingSpellbookChunkIndex = 1
    spellbookChunkTimer:Hide()
    spellbookSyncQueued = false
    spellbookDebounceTimer:Hide()
end

spellbookDebounceTimer:SetScript("OnUpdate", function(self, elapsed)
    if not spellbookSyncQueued then return end
    self.remaining = self.remaining - elapsed
    if self.remaining > 0 then return end
    self:Hide()
    spellbookSyncQueued = false
    ns.SyncPlayerSpellbookVisibility(false)
end)

local function TrackMorphCommand(cmd)
    local settings = ns.GetSettings()
    if not settings.saveMorphState then return end
    InitCharacterState()

    for singleCmd in cmd:gmatch("[^|]+") do
        local parts = {strsplit(":", singleCmd)}
        local prefix = parts[1]

        if prefix == "ITEM" and parts[2] and parts[3] then
            local slotId = tonumber(parts[2])
            local itemId = tonumber(parts[3])
            if slotId then
                if itemId == -1 then
                    TransmorpherCharacterState.HiddenItems[slotId] = true
                    if TransmorpherCharacterState.Items[slotId] == nil then
                        TransmorpherCharacterState.Items[slotId] = -1
                    end
                else
                    TransmorpherCharacterState.Items[slotId] = itemId
                    TransmorpherCharacterState.HiddenItems[slotId] = nil
                end
            end

        elseif prefix == "MORPH" and parts[2] then
            local val = tonumber(parts[2])
            TransmorpherCharacterState.Morph = (val and val > 0) and val or nil

        elseif prefix == "SCALE" and parts[2] then
            TransmorpherCharacterState.Scale = tonumber(parts[2])

        elseif prefix == "MOUNT_MORPH" and parts[2] then
            local mountMorphID = tonumber(parts[2])
            if settings.saveMountMorph then
                if mountMorphID and mountMorphID > 0 then
                    TransmorpherCharacterState.MountHidden = false
                    TransmorpherCharacterState.MountDisplay = mountMorphID
                end
            end
        elseif prefix == "MOUNT_RESET" then
            TransmorpherCharacterState.MountDisplay = nil
            TransmorpherCharacterState.GroundMountDisplay = nil
            TransmorpherCharacterState.GroundMountName = nil
            TransmorpherCharacterState.FlyingMountDisplay = nil
            TransmorpherCharacterState.FlyingMountName = nil
            TransmorpherCharacterState.MountHidden = false
            if TransmorpherCharacterState.Mounts then
                wipe(TransmorpherCharacterState.Mounts)
            end
            ns.networkResetPending = true

        elseif prefix == "PET_MORPH" and parts[2] then
            if settings.savePetMorph then
                TransmorpherCharacterState.PetDisplay = tonumber(parts[2])
            end
        elseif prefix == "PET_RESET" then
            TransmorpherCharacterState.PetDisplay = nil
            ns.networkResetPending = true

        elseif prefix == "HPET_MORPH" and parts[2] then
            if settings.saveCombatPetMorph or settings.saveHunterPetMorph then
                TransmorpherCharacterState.HunterPetDisplay = tonumber(parts[2])
            end
        elseif prefix == "HPET_SCALE" and parts[2] then
            if settings.saveCombatPetMorph or settings.saveHunterPetMorph then
                TransmorpherCharacterState.HunterPetScale = tonumber(parts[2])
            end
        elseif prefix == "HPET_RESET" then
            TransmorpherCharacterState.HunterPetDisplay = nil
            TransmorpherCharacterState.HunterPetScale = nil
            ns.networkResetPending = true

        elseif prefix == "ENCHANT_MH" and parts[2] then
            local val = tonumber(parts[2])
            if val and val > 0 then TransmorpherCharacterState.EnchantMH = val end
        elseif prefix == "ENCHANT_OH" and parts[2] then
            local val = tonumber(parts[2])
            if val and val > 0 then TransmorpherCharacterState.EnchantOH = val end
        elseif prefix == "ENCHANT_RESET_MH" then
            TransmorpherCharacterState.EnchantMH = nil
            ns.networkResetPending = true
        elseif prefix == "ENCHANT_RESET_OH" then
            TransmorpherCharacterState.EnchantOH = nil
            ns.networkResetPending = true
        elseif prefix == "ENCHANT_RESET" then
            TransmorpherCharacterState.EnchantMH = nil
            TransmorpherCharacterState.EnchantOH = nil
            ns.networkResetPending = true

        elseif prefix == "TITLE" and parts[2] then
            local val = tonumber(parts[2])
            if val and val > 0 then TransmorpherCharacterState.TitleID = val end
        elseif prefix == "TITLE_RESET" then
            TransmorpherCharacterState.TitleID = nil
            ns.networkResetPending = true
        elseif prefix == "SPELL_MORPH" and parts[2] and parts[3] then
            local sourceSpellId = tonumber(parts[2])
            local targetSpellId = tonumber(parts[3])
            if sourceSpellId and sourceSpellId > 0 then
                if not TransmorpherCharacterState.SpellMorphs then TransmorpherCharacterState.SpellMorphs = {} end
                if targetSpellId and targetSpellId > 0 then
                    TransmorpherCharacterState.SpellMorphs[sourceSpellId] = targetSpellId
                else
                    TransmorpherCharacterState.SpellMorphs[sourceSpellId] = nil
                end
            end
        elseif prefix == "SPELL_RESET" and parts[2] then
            local sourceSpellId = tonumber(parts[2])
            if sourceSpellId and sourceSpellId > 0 and TransmorpherCharacterState.SpellMorphs then
                TransmorpherCharacterState.SpellMorphs[sourceSpellId] = nil
            end
        elseif prefix == "SPELL_RESET_ALL" then
            if TransmorpherCharacterState.SpellMorphs then
                wipe(TransmorpherCharacterState.SpellMorphs)
            else
                TransmorpherCharacterState.SpellMorphs = {}
            end



        elseif prefix == "RESET" and parts[2] then
            if parts[2] == "ALL" then
                if TransmorpherCharacterState and TransmorpherCharacterState.Items then
                    for slotId, _ in pairs(TransmorpherCharacterState.Items) do
                        local slotName = ns.equipSlotIdToSlot[slotId]
                        if slotName then
                            local nativeId = ns.GetEquippedItemForSlot(slotName) or 0
                            ns.TrackUnmorphedSlot(slotId, nativeId)
                        end
                    end
                end
                ns.networkResetPending = true
                -- Clear state in-place to preserve references
                if TransmorpherCharacterState.Items then
                    wipe(TransmorpherCharacterState.Items)
                else
                    TransmorpherCharacterState.Items = {}
                end
                TransmorpherCharacterState.Morph = nil
                TransmorpherCharacterState.Scale = nil
                TransmorpherCharacterState.MountDisplay = nil
                TransmorpherCharacterState.PetDisplay = nil
                TransmorpherCharacterState.MountHidden = false
                if TransmorpherCharacterState.HiddenItems then
                    wipe(TransmorpherCharacterState.HiddenItems)
                else
                    TransmorpherCharacterState.HiddenItems = {}
                end
                TransmorpherCharacterState.GroundMountDisplay = nil
                TransmorpherCharacterState.GroundMountName = nil
                TransmorpherCharacterState.FlyingMountDisplay = nil
                TransmorpherCharacterState.FlyingMountName = nil
                -- Clear per-mount morphs too
                if TransmorpherCharacterState.Mounts then
                    wipe(TransmorpherCharacterState.Mounts)
                else
                    TransmorpherCharacterState.Mounts = {}
                end
                TransmorpherCharacterState.HunterPetDisplay = nil
                TransmorpherCharacterState.HunterPetScale = nil
                TransmorpherCharacterState.EnchantMH = nil
                TransmorpherCharacterState.EnchantOH = nil
                TransmorpherCharacterState.TitleID = nil
                if TransmorpherCharacterState.WeaponSets then
                    wipe(TransmorpherCharacterState.WeaponSets)
                else
                    TransmorpherCharacterState.WeaponSets = {}
                end

                -- Preserve Forms and spell systems
                if not TransmorpherCharacterState.Forms then TransmorpherCharacterState.Forms = {} end
                if not TransmorpherCharacterState.SpellMorphs then TransmorpherCharacterState.SpellMorphs = {} end
            else
                local slotId = tonumber(parts[2])
                if slotId then
                    TransmorpherCharacterState.Items[slotId] = nil
                    if TransmorpherCharacterState.HiddenItems then
                        TransmorpherCharacterState.HiddenItems[slotId] = nil
                    end
                    if slotId == 16 or slotId == 17 then
                        local setKey = GetWeaponSetKey()
                        if TransmorpherCharacterState.WeaponSets and TransmorpherCharacterState.WeaponSets[setKey] then
                            TransmorpherCharacterState.WeaponSets[setKey][slotId] = nil
                        end
                    end
                end
            end
        end
    end
end

-- ============================================================
-- LOW-LEVEL COMMAND TRANSPORT
-- ============================================================

local function AppendCommand(cmd)
    if ns.isShuttingDown then return end
    if TRANSMORPHER_CMD == "" then
        TRANSMORPHER_CMD = cmd
    else
        TRANSMORPHER_CMD = TRANSMORPHER_CMD .. "|" .. cmd
    end
end

local morphBatchDepth = 0
local morphBatchStatusDirty = false

function ns.BeginMorphBatch()
    morphBatchDepth = morphBatchDepth + 1
end

function ns.EndMorphBatch()
    if morphBatchDepth <= 0 then return end
    morphBatchDepth = morphBatchDepth - 1
    if morphBatchDepth == 0 and morphBatchStatusDirty then
        morphBatchStatusDirty = false
        if ns.UpdateMorphStatusBar then ns.UpdateMorphStatusBar() end
    end
end

-- Send a morph command (tracked in SavedVariables)
function ns.SendMorphCommand(cmd)
    if ns.isShuttingDown then return end
    -- If a manual command is sent, clear the active loadout tracking.
    -- This ensures that if the user manually changes a piece of gear,
    -- the loadout system knows it's no longer perfectly matching the saved loadout.
    if not ns.isApplyingLoadout then
        ns.activeLoadoutUid = nil
    end

    TrackMorphCommand(cmd)
    AppendCommand(cmd)

    if morphBatchDepth > 0 then
        morphBatchStatusDirty = true
    else
        if ns.UpdateMorphStatusBar then ns.UpdateMorphStatusBar() end
    end

    -- Sync with other players
    if ns.BroadcastMorphState then
        ns.BroadcastMorphState()
    end
end

-- Send a raw signal to the DLL (SUSPEND/RESUME) without tracking state
function ns.SendRawMorphCommand(cmd)
    if ns.isShuttingDown then return end
    AppendCommand(cmd)
end

-- ============================================================
-- DISTANCE-CULL: party/raid member protection
-- The DLL keeps the protected set for member character models only; pets/summons
-- from party/raid members can still be hidden by the pet/summon toggles.
-- ============================================================
local lastHideGroupCSV = nil

function ns.BuildHideGroupCSV()
    local guids = {}
    local raidN = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    if raidN and raidN > 0 then
        for i = 1, raidN do
            local g = UnitGUID("raid" .. i)
            if g then guids[#guids + 1] = g end
        end
    else
        local partyN = (GetNumPartyMembers and GetNumPartyMembers()) or 0
        for i = 1, (partyN or 0) do
            local g = UnitGUID("party" .. i)
            if g then guids[#guids + 1] = g end
        end
    end
    return table.concat(guids, ",")
end

function ns.PushHideGroupList(force)
    if ns.isShuttingDown then return end
    local csv = ns.BuildHideGroupCSV()
    if force or csv ~= lastHideGroupCSV then
        lastHideGroupCSV = csv
        ns.SendRawMorphCommand("HIDE_GROUP_LIST:" .. csv)
    end
end

-- Apply the CVar-based "extra FPS" toggles (chat bubbles). Global.
-- NOTE: "Mute Sound Effects" no longer uses the Sound_EnableSFX CVar (which killed
-- EVERY world sound). It is now a DLL per-source filter that mutes ONLY other players'
-- sounds; it is pushed via MUTE_PLAYER_SOUNDS (see ns.PushPlayerSoundMute).
-- Every nameplate CVar (RE-verified present in wow.exe 3.3.5a). Setting them all to "0" stops the
-- engine from creating ANY nameplate (cheaper than hiding frames after the fact).
local NAMEPLATE_CVARS = {
    "nameplateShowEnemies", "nameplateShowFriends",
    "nameplateShowEnemyTotems", "nameplateShowEnemyGuardians", "nameplateShowEnemyPets",
    "nameplateShowFriendlyTotems", "nameplateShowFriendlyGuardians", "nameplateShowFriendlyPets",
}

function ns.ApplyHideCVars()
    local s = ns.GetSettings()
    pcall(SetCVar, "chatBubbles", s.hideChatBubbles and "0" or "1")
    pcall(SetCVar, "chatBubblesParty", s.hideChatBubbles and "0" or "1")
    -- Migration: older builds muted ALL sound effects via this CVar. We no longer touch
    -- it for muting, so force it back ON in case a previous version left it at "0".
    pcall(SetCVar, "Sound_EnableSFX", "1")
    -- Hide ALL nameplates (cleanup toggle). Forced off on login/apply so a fresh login never
    -- pops nameplates. We snapshot the prior values the first time we hide and restore them when
    -- the toggle is turned off, so the user's normal nameplate prefs come back.
    if s.hideNameplates then
        if not ns._savedNameplateCVars then
            ns._savedNameplateCVars = {}
            for _, c in ipairs(NAMEPLATE_CVARS) do ns._savedNameplateCVars[c] = GetCVar(c) end
        end
        for _, c in ipairs(NAMEPLATE_CVARS) do pcall(SetCVar, c, "0") end
    elseif ns._savedNameplateCVars then
        for _, c in ipairs(NAMEPLATE_CVARS) do
            local v = ns._savedNameplateCVars[c]
            if v then pcall(SetCVar, c, v) end
        end
        ns._savedNameplateCVars = nil
    end
end

-- Push the "mute other players' sounds" state to the DLL. Other players' footsteps,
-- voices, spell and combat sounds are dropped; the local player, NPCs, UI, music and
-- ambient keep playing. Re-pushed on login / DLL-ready so it survives a reload.
function ns.PushPlayerSoundMute()
    if ns.isShuttingDown then return end
    if not (ns.IsMorpherReady and ns.IsMorpherReady()) then return end
    local s = ns.GetSettings()
    ns.SendRawMorphCommand("MUTE_PLAYER_SOUNDS:" .. (s.hideOtherSounds and "1" or "0"))
end

-- Production: ensure dbCompress is 0 for THIS running session too. The DLL patches
-- Config.wtf on disk at startup (takes effect next launch / for the WDB cache); setting
-- the live CVar here means the client also writes "0" back on a clean exit, so the two
-- never fight. Best-effort and harmless if the CVar is protected.
do
    local cvarFrame = CreateFrame("Frame")
    cvarFrame:RegisterEvent("PLAYER_LOGIN")
    cvarFrame:SetScript("OnEvent", function()
        pcall(SetCVar, "dbCompress", "0")
    end)
end

local hideGroupWatcher = CreateFrame("Frame")
hideGroupWatcher:RegisterEvent("PARTY_MEMBERS_CHANGED")
hideGroupWatcher:RegisterEvent("RAID_ROSTER_UPDATE")
hideGroupWatcher:RegisterEvent("PARTY_MEMBER_ENABLE")
hideGroupWatcher:SetScript("OnEvent", function()
    if ns.IsMorpherReady and ns.IsMorpherReady() then
        ns.PushHideGroupList(false)
    end
end)

-- ============================================================
-- ENCOUNTER BOSS protection: mirror the client's own boss frames (boss1..5) to the
-- DLL via the canonical UnitGUID() API. This is the authoritative "is a boss" signal
-- (many raid bosses — e.g. Lady Deathwhisper — are creature-rank "elite", so only the
-- boss-frame list identifies them). The DLL hard-protects these GUIDs and their owned
-- ground effects so encounter mechanics are ALWAYS visible. Pushed only on change.
-- ============================================================
local lastBossCSV = nil
function ns.PushBossList(force)
    if ns.isShuttingDown then return end
    if not (ns.IsMorpherReady and ns.IsMorpherReady()) then return end
    local guids = {}
    for i = 1, 5 do
        local u = "boss" .. i
        if UnitExists(u) then
            local g = UnitGUID(u)
            if g then guids[#guids + 1] = g end
        end
    end
    -- Also protect the current target if the CLIENT itself classifies it a world boss.
    if UnitExists("target") and UnitClassification("target") == "worldboss" then
        local g = UnitGUID("target")
        if g then guids[#guids + 1] = g end
    end
    local csv = table.concat(guids, ",")
    if force or csv ~= lastBossCSV then
        lastBossCSV = csv
        ns.SendRawMorphCommand("SC_BOSSES:" .. csv)
    end
end

local bossWatcher = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "PLAYER_REGEN_DISABLED",
                      "PLAYER_REGEN_ENABLED", "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "UNIT_TARGET",
                      "PLAYER_ENTERING_WORLD", "RAID_ROSTER_UPDATE" }) do
    pcall(function() bossWatcher:RegisterEvent(ev) end)
end
bossWatcher:SetScript("OnEvent", function() ns.PushBossList(false) end)
-- Fallback poll while in combat (covers servers that don't fire encounter events).
local bossAccum = 0
bossWatcher:SetScript("OnUpdate", function(self, elapsed)
    bossAccum = bossAccum + (elapsed or 0)
    if bossAccum < 1.0 then return end
    bossAccum = 0
    if InCombatLockdown and InCombatLockdown() then ns.PushBossList(false) end
end)

-- ============================================================
-- DLL STATUS
-- ============================================================

-- Track if DLL settings have been initialized
local dllSettingsInitialized = false
local dllInitRetryFrame = CreateFrame("Frame")
dllInitRetryFrame:Hide()
dllInitRetryFrame.elapsed = 0
dllInitRetryFrame.startedAt = 0
dllInitRetryFrame:SetScript("OnUpdate", function(self, elapsed)
    if dllSettingsInitialized then
        self:Hide()
        return
    end
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.5 then return end
    self.elapsed = 0
    if TRANSMORPHER_DLL_LOADED then
        ns.InitializeDLLSettings()
        if dllSettingsInitialized then
            self:Hide()
        end
        return
    end
    if self.startedAt > 0 and (GetTime() - self.startedAt) > 60 then
        self:Hide()
    end
end)

function ns.IsMorpherReady()
    if TRANSMORPHER_DLL_LOADED then
        return true
    else
        return false
    end
end

-- Initialize DLL settings (called once when DLL is first detected)
function ns.InitializeDLLSettings()
    if dllSettingsInitialized then return end
    if not TRANSMORPHER_DLL_LOADED then
        if not dllInitRetryFrame:IsShown() then
            dllInitRetryFrame.elapsed = 0
            dllInitRetryFrame.startedAt = GetTime()
            dllInitRetryFrame:Show()
        end
        return
    end
    
    local settings = ns.GetSettings()
    
    if not TransmorpherCharacterState then 
        TransmorpherCharacterState = {} 
    end

    -- STATE RECOVERY: If SavedVariables were wiped, pull from DLL
    local hasItems = next(TransmorpherCharacterState.Items or {}) ~= nil
    local hasMorphData = TransmorpherCharacterState.Morph or hasItems
    
    if TRANSMORPHER_DLL_STATE and not hasMorphData then
        TransmorpherCharacterState.Morph = TRANSMORPHER_DLL_STATE.morph
        TransmorpherCharacterState.Scale = TRANSMORPHER_DLL_STATE.scale
        TransmorpherCharacterState.MountDisplay = TRANSMORPHER_DLL_STATE.mount
        TransmorpherCharacterState.EnchantMH = TRANSMORPHER_DLL_STATE.emh
        TransmorpherCharacterState.EnchantOH = TRANSMORPHER_DLL_STATE.eoh
        TransmorpherCharacterState.TitleID = TRANSMORPHER_DLL_STATE.title
        TransmorpherCharacterState.Items = TransmorpherCharacterState.Items or {}
        TransmorpherCharacterState.HiddenItems = TransmorpherCharacterState.HiddenItems or {}
        TransmorpherCharacterState.SpellMorphs = TransmorpherCharacterState.SpellMorphs or {}
        
        for s, id in pairs(TRANSMORPHER_DLL_STATE.items) do
            if id == 0 then
                TransmorpherCharacterState.HiddenItems[s] = true
            else
                TransmorpherCharacterState.Items[s] = id
            end
        end
        if TRANSMORPHER_DLL_STATE.spells then
            for sourceSpellId, targetSpellId in pairs(TRANSMORPHER_DLL_STATE.spells) do
                local source = tonumber(sourceSpellId)
                local target = tonumber(targetSpellId)
                if source and source > 0 and target and target > 0 then
                    TransmorpherCharacterState.SpellMorphs[source] = target
                end
            end
        end
        
        if ns.RestoreMorphedUI then
            ns.RestoreMorphedUI()
        end
    end

    -- Send all settings to DLL immediately. MSDF mode is startup-only and is persisted by the DLL for the next launch.
    ns.SendRawMorphCommand("MSDF_MODE:" .. NormalizeHdFontMode(settings))
    ns.SendRawMorphCommand("SET:DBW:0")
    ns.SendRawMorphCommand("SET:META:" .. (settings.showMetamorphosis and "1" or "0"))
    ns.SendRawMorphCommand("SET:SHAPE:" .. (settings.morphInShapeshift and "1" or "0"))
    ns.SendRawMorphCommand("SET:SHOW_OWN_SPELLS:" .. (settings.showOwnSpells and "1" or "0"))
    ns.PushSpellClassState(settings)
    ns.SendRawMorphCommand("SET:CAMERA_FOV:" .. (settings.cameraFov or 0))
    -- Distance culling. Push radius + categories first, then the master switch last.
    ns.SendRawMorphCommand("SET:HIDE_PLAYERS_DIST:" .. (settings.hidePlayersDistance or 30))
    ns.SendRawMorphCommand("SET:HIDE_PLAYERS:" .. (settings.hideCatPlayers and "1" or "0"))
    ns.SendRawMorphCommand("SET:HIDE_PETS:" .. (settings.hideCatPets and "1" or "0"))
    ns.SendRawMorphCommand("SET:HIDE_NPCS:" .. (settings.hideCatNpcs and "1" or "0"))
    ns.SendRawMorphCommand("SET:HIDE_OBJECTS:" .. (settings.hideCatObjects and "1" or "0"))
    ns.SendRawMorphCommand("SET:HIDE_CORPSES:" .. (settings.hideCatCorpses and "1" or "0"))
    ns.SendRawMorphCommand("SET:HIDE_OTHER_SUMMONS:" .. (settings.hideOtherSummons and "1" or "0"))
    ns.SendRawMorphCommand("SET:HIDE_SHOW_GROUP:" .. (settings.hideShowGroup and "1" or "0"))
    if ns.PushHideGroupList then ns.PushHideGroupList(true) end
    ns.SendRawMorphCommand("SET:HIDE_SHADOWS:" .. (settings.hideShadows and "1" or "0"))
    if ns.ApplyHideCVars then ns.ApplyHideCVars() end
    if ns.PushPlayerSoundMute then ns.PushPlayerSoundMute() end
    ns.SendRawMorphCommand("SET:HIDE_PLAYERS_ENABLED:" .. (settings.hidePlayersEnabled and "1" or "0"))
    if ns.Color_ApplyAll then ns.Color_ApplyAll() end

    -- Stamp saved morph/loadout descriptors before mirroring saved skins. Otherwise
    -- ITEM_SKIN_PERSIST can see the base equipped items and anchor colors to them,
    -- then the later morph descriptor update makes the DLL clear those colors as stale.
    if ns.SendFullMorphState then
        ns.SendFullMorphState()
    end

    -- Mirror saved per-slot skins to the DLL now that it is ready. We push the desire
    -- only (ITEM_SKIN_PERSIST); the DLL binds each skin to the correctly-rendered item
    -- itself, so there is no pre-morph mis-bind / login flash.
    if ns.Skin_PersistAll then ns.Skin_PersistAll() end

    -- Re-send the saved barber look now that the DLL is ready.
    if ns.Barber_ApplyAll then ns.Barber_ApplyAll() end

    -- Sync White Card (Protection) List
    ns.SendRawMorphCommand("SPELL_WHITE_CLEAR")
    if settings.whiteCardSpells then
        for id, _ in pairs(settings.whiteCardSpells) do
            ns.SendRawMorphCommand("SPELL_WHITE_CARD:" .. id)
        end
    end
    ns.SyncOptimizationTierProtection()
    ns.SyncPlayerSpellbookVisibility(true)

    if ns.QueueWorldAnalysisSync then ns.QueueWorldAnalysisSync() end
    if ns.QueueWorldEnvironmentSync then ns.QueueWorldEnvironmentSync() end
    

    
    dllSettingsInitialized = true
    dllInitRetryFrame:Hide()
    
    if type(Log) == "function" then
        Log("DLL settings initialized: DBW=0, META=%s, SHAPE=%s",
            settings.showMetamorphosis and "1" or "0",
            settings.morphInShapeshift and "1" or "0")
    end
end

-- Helper: Re-apply pet morphs from saved state
function ns.ApplyPetMorphs()
    local settings = ns.GetSettings()
    if not settings.saveMorphState or not TransmorpherCharacterState then return end

    local cmdQueue = {}
    -- Combat Pet
    if TransmorpherCharacterState.HunterPetDisplay and (settings.saveCombatPetMorph or settings.saveHunterPetMorph) then
        table.insert(cmdQueue, "HPET_MORPH:" .. TransmorpherCharacterState.HunterPetDisplay)
    end
    if TransmorpherCharacterState.HunterPetScale and (settings.saveCombatPetMorph or settings.saveHunterPetMorph) then
        table.insert(cmdQueue, "HPET_SCALE:" .. TransmorpherCharacterState.HunterPetScale)
    end
    -- Non-combat Pet
    if TransmorpherCharacterState.PetDisplay and settings.savePetMorph then
        table.insert(cmdQueue, "PET_MORPH:" .. TransmorpherCharacterState.PetDisplay)
    end

    if #cmdQueue > 0 then
        ns.SendRawMorphCommand(table.concat(cmdQueue, "|"))
    end
end

-- ============================================================
-- FULL STATE RESTORE
-- Sends all saved morph state to the DLL (used on login/zone change).
-- ============================================================

-- Flag: when true, next SendFullMorphState prepends RESET:ALL
ns.needsCharacterReset = false

function ns.SendFullMorphState()
    local settings = ns.GetSettings()

    if not settings.saveMorphState then
        if ns.needsCharacterReset then
            ns.SendRawMorphCommand("RESET:ALL")
            ns.needsCharacterReset = false
        end
        return
    end
    if not TransmorpherCharacterState then return end

    local cmdQueue = {}

    -- Sync settings to DLL first
    table.insert(cmdQueue, "SET:DBW:0")
    table.insert(cmdQueue, "SET:META:" .. (settings.showMetamorphosis and "1" or "0"))
    table.insert(cmdQueue, "SET:SHAPE:" .. (settings.morphInShapeshift and "1" or "0"))

    -- Character reset if needed
    if ns.needsCharacterReset then
        table.insert(cmdQueue, "RESET:ALL")
        ns.needsCharacterReset = false
    end

    local activeMorph = ns.currentFormMorph or TransmorpherCharacterState.Morph
    local hasActiveFormMorph = ns.currentFormMorph and ns.currentFormMorph > 0

    if hasActiveFormMorph then
        ns.morphSuspended = false
        table.insert(cmdQueue, "RESUME")
    end

    -- If suspended, still send morph data so DLL knows what to resume to
    if (ns.IsModelChangingForm() and not hasActiveFormMorph) or (ns.dbwSuspended and not hasActiveFormMorph) or ns.vehicleSuspended then
        table.insert(cmdQueue, "SUSPEND")

        if TransmorpherCharacterState.Scale then
            table.insert(cmdQueue, "SCALE:" .. TransmorpherCharacterState.Scale)
        end
        if activeMorph then
            table.insert(cmdQueue, "MORPH:" .. activeMorph)
        end
        if TransmorpherCharacterState.MountDisplay and settings.saveMountMorph then
            table.insert(cmdQueue, "MOUNT_MORPH:" .. TransmorpherCharacterState.MountDisplay)
        end
        if TransmorpherCharacterState.Items then
            for slot, item in pairs(TransmorpherCharacterState.Items) do
                table.insert(cmdQueue, "ITEM:" .. slot .. ":" .. item)
            end
        end
        local effectiveSpellMorphs = ns.GetEffectiveSpellMorphPairs and ns.GetEffectiveSpellMorphPairs() or TransmorpherCharacterState.SpellMorphs
        if effectiveSpellMorphs then
            for sourceSpellId, targetSpellId in pairs(effectiveSpellMorphs) do
                if sourceSpellId and targetSpellId and sourceSpellId > 0 and targetSpellId > 0 then
                    table.insert(cmdQueue, "SPELL_MORPH:" .. sourceSpellId .. ":" .. targetSpellId)
                end
            end
        end

        if #cmdQueue > 0 then
            ns.SendRawMorphCommand(table.concat(cmdQueue, "|"))
        end
        return
    end

    -- Force RESUME if settings allow morph in shapeshift
    if settings.morphInShapeshift and (GetShapeshiftForm() > 0) then
        ns.morphSuspended = false
        table.insert(cmdQueue, "RESUME")
    end
    if ns.HasDBWProc() then
        ns.dbwSuspended = false
        table.insert(cmdQueue, "RESUME")
    end

    -- Build morph data
    if TransmorpherCharacterState.Scale then
        table.insert(cmdQueue, "SCALE:" .. TransmorpherCharacterState.Scale)
    end
    if activeMorph then
        table.insert(cmdQueue, "MORPH:" .. activeMorph)
    end

    -- Handle Mount Morph (single per-character mount morph)
    if settings.saveMountMorph then
        local mountMorph = TransmorpherCharacterState.MountDisplay
        if not TransmorpherCharacterState.MountHidden then
            if TransmorpherCharacterState.MountDisplay == -1 then
                TransmorpherCharacterState.MountDisplay = nil
            end
            if mountMorph == -1 then
                mountMorph = nil
            end
        end
        
        -- Override with -1 ONLY if explicitly hidden by the eye button
        if TransmorpherCharacterState.MountHidden then
            mountMorph = -1
        end
        
        if IsMounted() then
            table.insert(cmdQueue, "SET:MOUNTED:1")
        end

        if mountMorph then
            table.insert(cmdQueue, "MOUNT_MORPH:" .. mountMorph)
        end
    end

    if TransmorpherCharacterState.PetDisplay and settings.savePetMorph then
        table.insert(cmdQueue, "PET_MORPH:" .. TransmorpherCharacterState.PetDisplay)
    end
    if TransmorpherCharacterState.HunterPetDisplay and (settings.saveCombatPetMorph or settings.saveHunterPetMorph) then
        table.insert(cmdQueue, "HPET_MORPH:" .. TransmorpherCharacterState.HunterPetDisplay)
    end
    if TransmorpherCharacterState.HunterPetScale and (settings.saveCombatPetMorph or settings.saveHunterPetMorph) then
        table.insert(cmdQueue, "HPET_SCALE:" .. TransmorpherCharacterState.HunterPetScale)
    end
    if TransmorpherCharacterState.EnchantMH then
        table.insert(cmdQueue, "ENCHANT_MH:" .. TransmorpherCharacterState.EnchantMH)
    end
    if TransmorpherCharacterState.EnchantOH then
        table.insert(cmdQueue, "ENCHANT_OH:" .. TransmorpherCharacterState.EnchantOH)
    end
    if TransmorpherCharacterState.TitleID then
        table.insert(cmdQueue, "TITLE:" .. TransmorpherCharacterState.TitleID)
    end
    if TransmorpherCharacterState.Items then
        for slot, item in pairs(TransmorpherCharacterState.Items) do
            local sendId = item
            if TransmorpherCharacterState.HiddenItems and TransmorpherCharacterState.HiddenItems[slot] then
                sendId = -1
            end
            table.insert(cmdQueue, "ITEM:" .. slot .. ":" .. sendId)
        end
    end
    -- Also handle hidden slots that are NOT morphed
    if TransmorpherCharacterState.HiddenItems then
        for slot, isHidden in pairs(TransmorpherCharacterState.HiddenItems) do
            if isHidden and not TransmorpherCharacterState.Items[slot] then
                table.insert(cmdQueue, "ITEM:" .. slot .. ":-1")
            end
        end
    end
    local effectiveSpellMorphs = ns.GetEffectiveSpellMorphPairs and ns.GetEffectiveSpellMorphPairs() or TransmorpherCharacterState.SpellMorphs
    if effectiveSpellMorphs then
        for sourceSpellId, targetSpellId in pairs(effectiveSpellMorphs) do
            if sourceSpellId and targetSpellId and sourceSpellId > 0 and targetSpellId > 0 then
                table.insert(cmdQueue, "SPELL_MORPH:" .. sourceSpellId .. ":" .. targetSpellId)
            end
        end
    end



    -- Spell filtering: spellbook protection + the per-unit-class filter state.
    table.insert(cmdQueue, "SET:SHOW_OWN_SPELLS:" .. (settings.showOwnSpells and "1" or "0"))
    ns.PushSpellClassState(settings)

    -- Protection Whitelist (White Card)
    table.insert(cmdQueue, "SPELL_WHITE_CLEAR")
    if settings.whiteCardSpells then
        for id, _ in pairs(settings.whiteCardSpells) do
            table.insert(cmdQueue, "SPELL_WHITE_CARD:" .. id)
        end
    end
    local tierOptions = ns.optimizationTierOptions or {}
    for _, tier in ipairs(tierOptions) do
        table.insert(cmdQueue, "SET:PROTECTED_TIER:" .. tier.key .. ":" .. (settings[tier.settingKey] and "1" or "0"))
    end

    if #cmdQueue > 0 then
        ns.SendRawMorphCommand(table.concat(cmdQueue, "|"))
    end

    ns.SyncPlayerSpellbookVisibility(true)
end

-- Pushes the full intelligent spell-filter state to the DLL: a SC_RESET to clear
-- the DLL side, then the master enable, the global "hide all"/category set, and
-- every selected target row. Only TRUE entries are sent (RESET already zeroes the
-- rest), so the command string stays small.
function ns.PushSpellClassState(settings)
    settings = settings or ns.GetSettings()
    local q = { "SC_RESET" }
    q[#q + 1] = "SC_ENABLE:" .. (settings.scEnabled and "1" or "0")
    q[#q + 1] = "SC_HIDEALL:" .. (settings.scHideAll and "1" or "0")
    -- Hide other players' enchant glows: independent engine toggle (not cleared by
    -- SC_RESET above), so push it explicitly to survive /reload and relog.
    q[#q + 1] = "SC_ENCHANTS:" .. (settings.hideOtherEnchants and "1" or "0")
    q[#q + 1] = "SC_ENCHANTS_NPC:" .. (settings.hideNpcEnchants and "1" or "0")
    -- Hide other players' attack ANIMATION (swing): independent engine toggle.
    q[#q + 1] = "SC_SWING:" .. (settings.hideOtherSwing and "1" or "0")
    local gc = settings.scGlobalCat or {}
    for cat, v in pairs(gc) do
        if v then q[#q + 1] = "SC_GCAT:" .. cat .. ":1" end
    end
    local sl = settings.scSelected or {}
    local selectedRows = {}
    for row, v in pairs(sl) do
        if v then
            local n = tonumber(row) or row
            -- Legacy UI row 11 was a confusing shortcut for player characters + pets.
            -- Keep the behavior, but sync it as the explicit rows now shown in the UI.
            if n == 11 then
                selectedRows[3] = true
                selectedRows[4] = true
            else
                selectedRows[n] = true
            end
        end
    end
    for row in pairs(selectedRows) do
        q[#q + 1] = "SC_SEL:" .. row .. ":1"
    end
    ns.SendRawMorphCommand(table.concat(q, "|"))

    -- Re-apply the left-column "All Units" simple toggles. These live in their own
    -- DLL store (independent of the board) but SC_RESET above cleared it, so we must
    -- restore them here so they survive /reload and relog. Only push the ones that
    -- are on; the SET handler sets g_applyAll + auto-enables when any is active.
    local SIMPLE = {
        { "hidePrecast",        "HIDE_PRECAST" },        { "hideCast",            "HIDE_CAST" },
        { "hideChannel",        "HIDE_CHANNEL" },        { "hideAuraStart",       "HIDE_AURA_START" },
        { "hideAuraEnd",        "HIDE_AURA_END" },       { "hideImpact",          "HIDE_IMPACT" },
        { "hideImpactCaster",   "HIDE_IMPACT_CASTER" },  { "hideTargetImpact",    "HIDE_IMPACT_TARGET" },
        { "hideAreaInstant",    "HIDE_AREA_INSTANT" },   { "hideAreaImpact",      "HIDE_AREA_IMPACT" },
        { "hideAreaPersistent", "HIDE_AREA_PERSISTENT" },{ "hideMissile",         "HIDE_MISSILE" },
        { "hideMissileMarker",  "HIDE_MISSILE_MARKER" }, { "hideSoundMissile",    "HIDE_SOUND_MISSILE" },
        { "hideSoundEvent",     "HIDE_SOUND_EVENT" },
    }
    for _, def in ipairs(SIMPLE) do
        if settings[def[1]] then ns.SendRawMorphCommand("SET:" .. def[2] .. ":1") end
    end
end
