local addon, ns = ...

-- ============================================================
-- P2P SYNC — Cross-player morph synchronization
--
-- HOW SYNC WORKS (strangers, no group):
--   T+0.0s  Enter zone
--   T+2.5s  SAY Hello (H|GUID) → all nearby addon users receive it
--   T+2.5s  Each whispers you their full state → you see them ✓
--   T+2.6s  MUTUAL HANDSHAKE: first time you receive their state
--           → you auto-whisper YOUR state back → they see you ✓
--   RESULT: Full mutual sync in ~2-3 seconds. No group needed.
--
-- Sync module loaded silently
-- UPDATE DETECTION:
--   • Every morph change → 300ms debounce → broadcast state
--   • SAY Hello+Request fires every 10s (invisible, addon-only)
--   • Heartbeat re-sends state to known peers (adaptive interval)
--   • State-change dedup: heartbeat skips if nothing changed
--   • Mutual handshake: first state from new peer → reply yours
--
-- CHANNELS (per message type):
--   Hello / Request → RAID/PARTY + GUILD + WHISPER known peers
--   State / Clear   → RAID/PARTY + GUILD + WHISPER known peers
--   (Message protocol via SAY is not supported by WoW for AddonMessages)
--
-- MESSAGE PROTOCOL (prefix "TMPH", ≤ 255 bytes):
--   H|GUIDHEX          Hello — I have the addon, reply with state
--   S|GUIDHEX|...      Full morph state (see SerializeState)
--   C|GUIDHEX          I reset my morph
--   R                  Request — please send me your state
-- ============================================================

-- ----------------------------------------------------------------
-- Constants
-- ----------------------------------------------------------------
local PREFIX             = "TMPH"
local MSG_STATE          = "S"
local MSG_HELLO          = "H"
local MSG_CLEAR          = "C"
local MSG_REQUEST        = "R"

local SYNC_CHANNEL_NAME  = "TransmorpherSync"
local syncChannelId      = nil

-- Adaptive heartbeat interval based on active peer count
local function GetHeartbeatInterval()
    local n = ns.P2PGetPeerCount and ns.P2PGetPeerCount() or 0
    if n == 0  then return 20 end    -- check for peers every 20s
    if n <= 5  then return 15   end  -- 1-5  peers → 15s
    if n <= 15 then return 30   end  -- 6-15 peers → 30s
    if n <= 30 then return 45   end  -- 16-30       → 45s
    return 90                        -- 31+          → 90s
end

local PEER_TIMEOUT_SECS  = 300  -- evict peer not heard from in 5 min
local CLEANUP_INTERVAL   = 60   -- run stale-peer sweep every 60s

-- ----------------------------------------------------------------
-- Runtime state
-- ----------------------------------------------------------------
ns.p2pPeers   = {}    -- [playerName] = { guid=HEX, lastSeen=time }
ns.p2pEnabled = true  -- toggled by Settings tab

local p2pStateCache     = {}   -- [guidHex] = last morph body (peer dedup)
local lastBroadcastBody = nil  -- our own last broadcast body (self dedup)
local lastHeartbeat     = 0
local myGUIDHex         = nil  -- cached after first UnitGUID call
ns.p2pDebug           = false -- toggle with /morph debug

-- ----------------------------------------------------------------
-- Register prefix so WoW routes CHAT_MSG_ADDON to us
-- ----------------------------------------------------------------
if RegisterAddonMessagePrefix then
    local ok = RegisterAddonMessagePrefix(PREFIX)
    if ok then
        -- Silent unless debug
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffF5C842<TM P2P>|r: ERROR: Failed to register Addon Prefix!")
    end
end

local function P2PLog(fmt, ...)
    if not ns.p2pDebug then return end
    local success, msg = pcall(string.format, fmt, ...)
    if not success then msg = tostring(fmt) end
    msg = msg:gsub("|", "||")
    pcall(function() DEFAULT_CHAT_FRAME:AddMessage("|cffF5C842<TM P2P>|r: " .. msg) end)
end

local function P2PLogChannels()
    local list = {GetChannelList()}
    local channels = {}
    -- list is [id1, name1, id2, name2, ...] step by 2
    for i=1, #list, 2 do
        local id, name = list[i], list[i+1]
        if type(id) == "number" and type(name) == "string" then
            table.insert(channels, string.format("[%d. %s]", id, name))
        end
    end
    P2PLog("Active Channels: %s", (#channels > 0 and table.concat(channels, ", ") or "None"))
end
ns.P2PLogChannels = P2PLogChannels

-- Chat filter to hide the custom sync channel messages and fallback whispers from the UI
if ChatFrame_AddMessageEventFilter then
    local function FilterTM(self, event, msg, ...)
        if msg then
            local pTag = "<" .. PREFIX .. ">"
            if msg:sub(1, #pTag) == pTag then return true end
            if msg:sub(1, 8) == "TM_SYNC:" then return true end
        end
        return false
    end
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", FilterTM)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", FilterTM)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", FilterTM)

    -- Hide "No player named 'XYZ' is currently playing" if the whisper fails (e.g. cross-faction)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(self, event, msg, ...)
        if msg and ns.lastP2PWhisperTarget and ns.lastP2PWhisperTime and (GetTime() - ns.lastP2PWhisperTime < 1.0) then
            local expectedErr = string.format(ERR_CHAT_PLAYER_NOT_FOUND_S, ns.lastP2PWhisperTarget)
            if msg == expectedErr then return true end
        end
        return false
    end)
end

-- ================================================================
-- GUID HELPERS
-- ================================================================

local function GetMyGUIDHex()
    if myGUIDHex then return myGUIDHex end
    local g = UnitGUID("player")
    if not g then return nil end
    myGUIDHex = g:match("^0[xX](.+)$") or g
    return myGUIDHex
end

-- ================================================================
-- LOW-LEVEL SEND HELPERS
-- ================================================================

--- Send to RAID or PARTY (whichever applies) and GUILD.
--- Also optionally broadcasts to custom channel for non-group discovery.
--- Returns true if a group channel was used.
local function SendToGroupAndGuild(msg, useChannel)
    local sentGroup = false
    if IsInRaid() then
        SendAddonMessage(PREFIX, msg, "RAID")
        sentGroup = true
    elseif IsInGroup() then
        SendAddonMessage(PREFIX, msg, "PARTY")
        sentGroup = true
    end
    if IsInGuild() then
        SendAddonMessage(PREFIX, msg, "GUILD")
    end
    
    -- Non-group sync: ONLY broadcast discovery/clear to custom channel
    if useChannel and ns.p2pEnabled then
        syncChannelId = GetChannelName(SYNC_CHANNEL_NAME)
        if not syncChannelId or syncChannelId == 0 then
            JoinChannelByName(SYNC_CHANNEL_NAME)
            syncChannelId = GetChannelName(SYNC_CHANNEL_NAME)
        end
        
        if syncChannelId and syncChannelId > 0 then
            -- We ONLY send small messages (H or C) here to avoid mutes
            -- Escape pipes for SendChatMessage to avoid "Invalid escape code" errors
            local wireMsg = msg:gsub("|", "||")
            P2PLog("Sending Discovery to [%s] (ID: %d): %s", SYNC_CHANNEL_NAME, syncChannelId, wireMsg)
            pcall(SendChatMessage, "TM_SYNC:" .. wireMsg, "CHANNEL", nil, syncChannelId)
        else
            P2PLog("Wait: syncChannelId for [%s] is still 0. Join pending...", SYNC_CHANNEL_NAME)
        end
    end

    return sentGroup
end

--- Whisper a specific player. pcall so it never raises an error.
local function WhisperPlayer(msg, target)
    if not ns.p2pEnabled or not msg or msg == ""
       or not target or target == "" then return end
    
    local wireMsg = msg:gsub("|", "||")
    P2PLog("Whispering state to: %s [Payload: %s]", target, wireMsg:sub(1, 40) .. "...")
    
    ns.lastP2PWhisperTarget = target
    ns.lastP2PWhisperTime = GetTime()
    
    pcall(SendAddonMessage, PREFIX, wireMsg, "WHISPER", target)
    -- Fallback for servers that block addon whispers
    pcall(SendChatMessage, "<" .. PREFIX .. ">" .. wireMsg, "WHISPER", nil, target)
end

--- True if player name is covered by our current group channel.
local function InOurGroup(name)
    if IsInRaid()  and UnitInRaid(name)  then return true end
    if IsInGroup() and UnitInParty(name) then return true end
    return false
end

-- ================================================================
-- BROADCAST HELPERS
-- Hello/Request → group + SAY + whisper known peers
-- State/Clear   → group + whisper known peers (NO SAY for state)
-- ================================================================

local function BroadcastHelloAndRequest()
    if not ns.p2pEnabled then return end
    local guid = GetMyGUIDHex()
    if not guid then return end
    local helloMsg = MSG_HELLO .. "|" .. guid

    -- Hello goes to group + CUSTOM CHANNEL (Discovery)
    SendToGroupAndGuild(helloMsg, true)

    local now = GetTime()
    for name, info in pairs(ns.p2pPeers) do
        if info.lastSeen and (now - info.lastSeen) < PEER_TIMEOUT_SECS then
            if not InOurGroup(name) then
                WhisperPlayer(helloMsg, name)
            end
        end
    end
end

local function BroadcastStateToAll(msg)
    if not ns.p2pEnabled or not msg then return end
    -- States ONLY go to Group/Guild. Peers outside group get whispers.
    local sentGroup = SendToGroupAndGuild(msg, false)
    local now = GetTime()
    for name, info in pairs(ns.p2pPeers) do
        if info.lastSeen and (now - info.lastSeen) < PEER_TIMEOUT_SECS then
            if not (sentGroup and InOurGroup(name)) then
                WhisperPlayer(msg, name)
            end
        end
    end
end

local function BroadcastClearToAll(msg)
    if not ns.p2pEnabled or not msg then return end
    -- Clear goes to group + CUSTOM CHANNEL
    local sentGroup = SendToGroupAndGuild(msg, true)
    local now = GetTime()
    for name, info in pairs(ns.p2pPeers) do
        if info.lastSeen and (now - info.lastSeen) < PEER_TIMEOUT_SECS then
            if not (sentGroup and InOurGroup(name)) then
                WhisperPlayer(msg, name)
            end
        end
    end
end

-- ================================================================
-- STATE SERIALIZATION
-- Format: S|GUIDHEX|display|scale100|mount|pet|hpet|hpscale100|emh|eoh|items
-- Scale values × 100 as integers (no decimal in the wire format).
-- items = "slot=id-slot=id-..." (only non-zero overrides; empty if none)
-- Worst-case size ≈ 195 bytes → safely under WoW's 255-byte limit.
-- ================================================================

local function SerializeState()
    local st = TransmorpherCharacterState
    if not st then return nil end
    local guid = GetMyGUIDHex()
    if not guid then return nil end

    local display    = ns.currentFormMorph or st.Morph or 0
    local scale100   = st.Scale            and math.floor(st.Scale            * 100 + 0.5) or 0
    local mount      = st.MountDisplay     or 0
    local pet        = st.PetDisplay       or 0
    local hpet       = st.HunterPetDisplay or 0
    local hpscale100 = st.HunterPetScale   and math.floor(st.HunterPetScale   * 100 + 0.5) or 0
    local ench_mh    = st.EnchantMH        or 0
    local ench_oh    = st.EnchantOH        or 0
    local title      = st.TitleID          or 0

    -- Serialize forms: formKey=displayID;...
    local formParts = {}
    if st.Forms then
        for fKey, fID in pairs(st.Forms) do
            if fID and fID > 0 then
                formParts[#formParts + 1] = fKey .. "=" .. fID
            end
        end
    end
    local formStr = (#formParts > 0) and table.concat(formParts, ";") or "0"

    local itemParts = {}
    if st.Items then
        for slot, itemId in pairs(st.Items) do
            if itemId and itemId > 0 then
                itemParts[#itemParts + 1] = slot .. "=" .. itemId
            end
        end
    end

    -- Format: S|GUIDHEX|display|scale100|mount|pet|hpet|hpscale100|emh|eoh|title|forms|items
    return string.format("%s|%s|%d|%d|%d|%d|%d|%d|%d|%d|%d|%s|%s",
        MSG_STATE, guid,
        display, scale100, mount, pet, hpet, hpscale100,
        ench_mh, ench_oh, title, formStr,
        table.concat(itemParts, "-"))
end

-- ================================================================
-- STATE DESERIALIZATION
-- Returns guidHex (string), state (table) — or nil, nil on error.
-- ================================================================

local function DeserializeState(msg)
    local t1, guidHex, s_disp, s_sc, s_mnt,
          s_pet, s_hpet, s_hpsc, s_emh, s_eoh,
          s_title, s_forms, items_str =
        strsplit("|", msg, 13)

    if t1 ~= MSG_STATE or not guidHex or guidHex == "" then
        return nil, nil
    end

    local state = {
        display    = tonumber(s_disp) or 0,
        scale      = (tonumber(s_sc)   or 0) / 100.0,
        mount      = tonumber(s_mnt)  or 0,
        pet        = tonumber(s_pet)  or 0,
        hpet       = tonumber(s_hpet) or 0,
        hpetscale  = (tonumber(s_hpsc) or 0) / 100.0,
        ench_mh    = tonumber(s_emh)  or 0,
        ench_oh    = tonumber(s_eoh)  or 0,
        title      = tonumber(s_title) or 0,
        forms      = {},
        items      = {},
    }

    if s_forms and s_forms ~= "0" then
        for pair in s_forms:gmatch("[^;]+") do
            local k, v = pair:match("^([^=]+)=(%d+)$")
            if k and v then
                state.forms[k] = tonumber(v)
            end
        end
    end

    if items_str and items_str ~= "" then
        for pair in items_str:gmatch("[^%-]+") do
            local s, id = pair:match("^(%d+)=(%d+)$")
            if s and id then
                state.items[tonumber(s)] = tonumber(id)
            end
        end
    end

    return guidHex, state
end

-- ================================================================
-- DLL PEER COMMAND SENDERS
-- ================================================================

local function SendPeerSetToDLL(guidHex, state)
    if not ns.IsMorpherReady() then 
        P2PLog("DLL not ready, skipping peer set for %s", guidHex)
        return 
    end

    local sc100  = state.scale     > 0 and math.floor(state.scale     * 100 + 0.5) or 0
    local hpsc100= state.hpetscale > 0 and math.floor(state.hpetscale * 100 + 0.5) or 0

    local itemParts = {}
    for slot, id in pairs(state.items or {}) do
        if id and id > 0 then
            itemParts[#itemParts + 1] = slot .. "=" .. id
        end
    end

    -- Send bulk state
    ns.SendRawMorphCommand(string.format(
        "PEER_SET:%s,%d,%d,%d,%d,%d,%d,%d,%d,%s",
        guidHex,
        state.display, sc100,
        state.mount, state.pet, state.hpet, hpsc100,
        state.ench_mh, state.ench_oh,
        table.concat(itemParts, "-")))

    -- Send Title separately (standard REMOTE protocol)
    if state.title and state.title > 0 then
        ns.SendRawMorphCommand("REMOTE:" .. guidHex .. ":TITLE:" .. state.title)
    end
end

local function SendPeerClearToDLL(guidHex)
    if ns.IsMorpherReady() then
        ns.SendRawMorphCommand("PEER_CLEAR:" .. guidHex)
        ns.SendRawMorphCommand("REMOTE:" .. guidHex .. ":RESET")
    end
end

-- ================================================================
-- PUBLIC: BROADCAST OWN STATE
-- Only transmits when the morph body actually changed (dedup).
-- ================================================================

function ns.P2PBroadcastState()
    if not ns.p2pEnabled or not TRANSMORPHER_DLL_LOADED then return end

    local msg = SerializeState()
    if not msg then return end

    -- Extract the morph body (skip "S|GUID|") for change detection
    local guid = GetMyGUIDHex() or ""
    -- body starts after "S|" + guid + "|"
    local bodyOffset = #MSG_STATE + 2 + #guid + 1
    local body = msg:sub(bodyOffset)

    if body ~= lastBroadcastBody then
        lastBroadcastBody = body
        BroadcastStateToAll(msg)
    end
    lastHeartbeat = GetTime()
end

--- Broadcast that we cleared our morph.
function ns.P2PBroadcastClear()
    if not ns.p2pEnabled or not TRANSMORPHER_DLL_LOADED then return end
    local guid = GetMyGUIDHex()
    if not guid then return end
    lastBroadcastBody = nil      -- reset dedup so next morph fires fresh
    BroadcastClearToAll(MSG_CLEAR .. "|" .. guid)
end

--- Announce presence + ask all nearby players to send their state.
--- Called on zone enter, login, and periodically.
function ns.P2PBroadcastHello()
    if not ns.p2pEnabled or not TRANSMORPHER_DLL_LOADED then return end
    BroadcastHelloAndRequest()
end

--- Ask all known peers to re-send their state (direct whispers).
function ns.P2PRequestStates()
    if not ns.p2pEnabled then return end
    local now = GetTime()
    for name, info in pairs(ns.p2pPeers) do
        if info.lastSeen and (now - info.lastSeen) < PEER_TIMEOUT_SECS then
            WhisperPlayer(MSG_REQUEST, name)
        end
    end
end

-- ================================================================
-- INCOMING MESSAGE HANDLER
-- Routed from EventLoop.lua on every CHAT_MSG_ADDON event.
-- ================================================================

function ns.P2PHandleAddonMessage(prefix, msg, channelName, senderName)
    if not msg then return end

    -- Raw Chat Fallback (Channel or standard Whisper)
    if not prefix then
        local pTag = "<" .. PREFIX .. ">"
        local isChat = false
        if msg:sub(1, #pTag) == pTag then
            msg = msg:sub(#pTag + 1)
            isChat = true
        elseif msg:sub(1, 8) == "TM_SYNC:" then
            msg = msg:sub(9)
            isChat = true
        end

        if isChat then
            if channelName == "WHISPER" or (channelName and string.find(string.lower(channelName), string.lower(SYNC_CHANNEL_NAME), 1, true)) then
                msg = msg:gsub("||", "|")
                -- We pretend it's a standard addon message
                P2PLog("Msg In: [CHAT:%s] from %s: %s", tostring(channelName), tostring(senderName), tostring(msg):sub(1, 40) .. "...")
            else
                return
            end
        else
            return
        end
    elseif prefix == PREFIX then
        msg = msg:gsub("||", "|")
        P2PLog("Msg In: [ADDON:%s] from %s: %s", tostring(channelName), tostring(senderName), tostring(msg):sub(1, 40) .. "...")
    else
        return
    end

    if msg == "" then return end

    local myName = UnitName("player")
    if senderName == myName then return end

    local msgType = msg:sub(1, 1)

    -- ----------------------------------------------------------------
    -- H|GUIDHEX — Hello: peer announcing presence
    -- ----------------------------------------------------------------
    if msgType == MSG_HELLO then
        local guidHex = msg:sub(3)
        if not guidHex or guidHex == "" then return end

        ns.p2pPeers[senderName] = {
            guid     = guidHex,
            lastSeen = GetTime(),
        }

        -- They said Hello → reply with our full state immediately
        -- so they see our morph right away (no waiting for heartbeat)
        local reply = SerializeState()
                   or (MSG_CLEAR .. "|" .. (GetMyGUIDHex() or ""))
        WhisperPlayer(reply, senderName)
        return
    end

    -- ----------------------------------------------------------------
    -- R — Request: peer asking for our current state
    -- ----------------------------------------------------------------
    if msgType == MSG_REQUEST then
        ns.p2pPeers[senderName] = ns.p2pPeers[senderName] or {}
        ns.p2pPeers[senderName].lastSeen = GetTime()

        local reply = SerializeState()
                   or (MSG_CLEAR .. "|" .. (GetMyGUIDHex() or ""))
        WhisperPlayer(reply, senderName)
        return
    end

    -- ----------------------------------------------------------------
    -- C|GUIDHEX — Clear: peer reset their morph
    -- ----------------------------------------------------------------
    if msgType == MSG_CLEAR then
        local guidHex = msg:sub(3)
        if not guidHex or guidHex == "" then return end

        ns.p2pPeers[senderName]          = ns.p2pPeers[senderName] or {}
        ns.p2pPeers[senderName].guid     = guidHex
        ns.p2pPeers[senderName].lastSeen = GetTime()

        p2pStateCache[guidHex] = nil
        SendPeerClearToDLL(guidHex)
        return
    end

    -- ----------------------------------------------------------------
    -- S|GUIDHEX|... — State: peer's full morph broadcast
    -- ----------------------------------------------------------------
    if msgType == MSG_STATE then
        local guidHex, state = DeserializeState(msg)
        if not guidHex or not state then return end

        -- *** MUTUAL HANDSHAKE ***
        -- First time we hear from this peer → whisper our state back
        -- immediately so they see OUR morph without waiting for the
        -- heartbeat. This completes mutual sync in ~2-3 seconds total
        -- even with complete strangers who share no group or guild.
        local isNewPeer = (ns.p2pPeers[senderName] == nil)
        if isNewPeer then
            P2PLog("Discovered new peer: %s", senderName)
        end

        ns.p2pPeers[senderName]          = ns.p2pPeers[senderName] or {}
        ns.p2pPeers[senderName].guid     = guidHex
        ns.p2pPeers[senderName].lastSeen = GetTime()

        if isNewPeer then
            local reply = SerializeState()
            if reply then WhisperPlayer(reply, senderName) end
        end

        -- Peer state dedup: skip DLL call if their state is unchanged
        local bodyOffset = #MSG_STATE + 2 + #guidHex + 1
        local cacheKey   = msg:sub(bodyOffset)
        if p2pStateCache[guidHex] == cacheKey then return end
        p2pStateCache[guidHex] = cacheKey

        -- Forward to DLL → PeerMorphGuard applies it in-game at 50ms
        SendPeerSetToDLL(guidHex, state)
        return
    end
end

-- ================================================================
-- HEARTBEAT TIMER
-- Periodically re-broadcasts our state to all known peers and
-- re-sends Hello+Request via SAY to catch newly arrived players.
-- Interval adapts based on active peer count (10s → 60s).
-- Broadcasts state ONLY when morph body actually changed.
-- ================================================================
local heartbeatFrame = CreateFrame("Frame")
heartbeatFrame.elapsed = 0
heartbeatFrame:SetScript("OnUpdate", function(self, elapsed)
    if not TRANSMORPHER_DLL_LOADED or not ns.p2pEnabled then return end
    self.elapsed = self.elapsed + elapsed
    local interval = GetHeartbeatInterval()
    if self.elapsed < interval then return end
    self.elapsed = 0

    -- Heartbeat fires silently; only log when state actually changes
    ns.P2PBroadcastState()       -- sends only if state changed (dedup)
    BroadcastHelloAndRequest()   -- SAY Hello/Request (rate-limited)
end)

-- ================================================================
-- PEER CLEANUP TIMER
-- Runs every CLEANUP_INTERVAL seconds.
-- Removes peers silent for PEER_TIMEOUT_SECS from both the Lua
-- peer table and the DLL's 100-slot peer morph table.
-- ================================================================
local cleanupFrame = CreateFrame("Frame")
cleanupFrame.elapsed = 0
cleanupFrame:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < CLEANUP_INTERVAL then return end
    self.elapsed = 0
    if not ns.p2pEnabled then return end

    local now = GetTime()
    for name, info in pairs(ns.p2pPeers) do
        if not info.lastSeen or (now - info.lastSeen) > PEER_TIMEOUT_SECS then
            if info.guid then
                SendPeerClearToDLL(info.guid)
                p2pStateCache[info.guid] = nil
            end
            ns.p2pPeers[name] = nil
        end
    end
end)

-- ================================================================
-- DEFERRED BROADCAST (300 ms debounce)
-- Prevents message spam when a full loadout/set is applied
-- (which can change 14+ slots in a single frame).
-- Called from DLLBridge.lua after every SendMorphCommand().
-- ================================================================
local broadcastPending  = false
local broadcastDebounce = CreateFrame("Frame")
broadcastDebounce:Hide()
broadcastDebounce.elapsed = 0
broadcastDebounce:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.3 then return end
    self:Hide()
    broadcastPending  = false
    lastBroadcastBody = nil    -- bypass dedup so change always fires
    ns.P2PBroadcastState()
end)

function ns.P2PScheduleBroadcast()
    if not ns.p2pEnabled then return end
    if broadcastPending then return end   -- already queued
    broadcastPending          = true
    broadcastDebounce.elapsed = 0
    broadcastDebounce:Show()
end

-- ================================================================
-- CLEAR ALL PEER DATA
-- Called on zone change so stale morphs from the last zone don't
-- linger. Peers re-introduce themselves via Hello/Request after load.
-- ================================================================
function ns.P2PClearAllPeers()
    ns.SendRawMorphCommand("PEER_CLEAR_ALL")
    p2pStateCache     = {}
    lastBroadcastBody = nil   -- force next broadcast regardless of dedup
    -- Keep ns.p2pPeers table so we can re-whisper known peers after load
end

local discoverDebounce = {}
function ns.P2PDiscoverPlayer(targetName)
    if not ns.p2pEnabled or not targetName then return end
    if targetName == UnitName("player") then return end
    
    local now = GetTime()
    if discoverDebounce[targetName] and (now - discoverDebounce[targetName]) < 30 then
        return -- already attempted recently
    end
    discoverDebounce[targetName] = now
    
    local guid = GetMyGUIDHex()
    if guid then
        -- Send standard AddonMessage Hello directly
        pcall(SendAddonMessage, PREFIX, MSG_HELLO .. "|" .. guid, "WHISPER", targetName)
        P2PLog("Proximity Discovery triggered for: %s", targetName)
    end
end

-- ================================================================
-- ACCESSOR: current synced peer count (used by SettingsTab counter)
-- ================================================================
function ns.P2PGetPeerCount()
    local n = 0
    for _ in pairs(ns.p2pPeers) do n = n + 1 end
    return n
end

-- ================================================================
-- API ALIASES (Compatibility with older Sync.lua callers)
-- ================================================================
ns.BroadcastMorphState = ns.P2PBroadcastState
ns.BroadcastResetState = ns.P2PBroadcastClear
ns.ClearRemoteMorphs   = ns.P2PClearAllPeers
