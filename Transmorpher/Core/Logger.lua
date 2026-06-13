local addon, ns = ...

-- ============================================================
-- CENTRALIZED LOGGING SYSTEM
-- Provides structured logging with log levels and throttling
-- ============================================================

ns.LogLevel = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4,
}

local currentLevel = ns.LogLevel.INFO
local debugEnabled = false

ns.LogLevel = ns.LogLevel

function ns.SetLogLevel(level)
    currentLevel = level
end

function ns.SetDebugEnabled(enabled)
    debugEnabled = enabled
    if enabled then
        currentLevel = ns.LogLevel.DEBUG
    end
end

function ns.IsDebugEnabled()
    return debugEnabled
end

local logThrottle = {}
local function CheckThrottle(key, minInterval)
    local now = GetTime()
    if not logThrottle[key] or (now - logThrottle[key]) > minInterval then
        logThrottle[key] = now
        return true
    end
    return false
end

function ns.Log(level, msg, ...)
    if level < currentLevel then return end
    
    local success, formatted = pcall(string.format, msg, ...)
    if not success then
        formatted = tostring(msg)
    end
    
    local prefix = ""
    if level == ns.LogLevel.DEBUG then
        prefix = "|cff808080[DEBUG]|r "
    elseif level == ns.LogLevel.WARN then
        prefix = "|cffffff00[WARN]|r "
    elseif level == ns.LogLevel.ERROR then
        prefix = "|cffff0000[ERROR]|r "
    else
        prefix = "|cff00ccff[TM]|r "
    end
    
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        pcall(DEFAULT_CHAT_FRAME.AddMessage, prefix .. formatted)
    end
    
    if level >= ns.LogLevel.ERROR then
        ns.LogToDLL(formatted)
    end
end

function ns.LogDebug(...)
    ns.Log(ns.LogLevel.DEBUG, ...)
end

function ns.LogInfo(...)
    ns.Log(ns.LogLevel.INFO, ...)
end

function ns.LogWarn(...)
    ns.Log(ns.LogLevel.WARN, ...)
end

function ns.LogError(...)
    ns.Log(ns.LogLevel.ERROR, ...)
end

function ns.LogThrottled(key, interval, ...)
    if CheckThrottle(key, interval) then
        ns.Log(ns.LogLevel.INFO, ...)
    end
end

function ns.LogToDLL(msg)
    if ns.obfuscatedLog and _G[ns.obfuscatedLog] ~= nil then
        local current = _G[ns.obfuscatedLog] or ""
        if #current + #msg < 8000 then
            _G[ns.obfuscatedLog] = current .. msg .. "\n"
        end
    end
end

ns.Log = ns.Log
ns.LogDebug = ns.LogDebug
ns.LogInfo = ns.LogInfo
ns.LogWarn = ns.LogWarn
ns.LogError = ns.LogError
ns.LogThrottled = ns.LogThrottled
