#include <windows.h>
#include <cstdio>
#include <atomic>
#include "Logger.h"
#include "Proxy.h"
#include "Hooks.h"
#include "Morpher.h"
#include "Utils.h"
#include "WoWOffsets.h"
#include "SpellMorph.h"

// ================================================================
// Timer & Threading
// ================================================================
static std::atomic<bool> g_running{true};
static HWND    g_wowHwnd = nullptr;
static UINT_PTR MORPH_TIMER_ID = 0xDEAD;
uint64_t g_playerGuid = 0; // Globally visible for Hooks.cpp isolation
static uint64_t g_lastCharacterGuid = 0; // Tracked for persistence loading

static bool g_luaLoadedSent = false;
static bool g_wasInWorld = false;
static int  g_worldStabilityTicks = 0;

// DLL init status tracking for Lua feedback
static const char* g_initStatus = "STARTING";
static bool g_hookSuccess = false;

static bool IsWindowOwnedByCurrentProcess(HWND hwnd) {
    if (!hwnd) return false;
    DWORD wndPid = 0;
    GetWindowThreadProcessId(hwnd, &wndPid);
    return wndPid == GetCurrentProcessId();
}

static VOID CALLBACK MorphTimerProc(HWND hwnd, UINT uMsg, UINT_PTR idEvent, DWORD dwTime) {
    if (!g_running) return;
    if (!g_wowHwnd) return;

    // HANDLE CHARACTER SELECTION (GLUE) MONITORING
    if (IsInGlue()) {
        uint64_t selectedGuid = GetSelectedCharacterGuid();
        if (selectedGuid != 0 && selectedGuid != g_lastCharacterGuid) {
            Log("Character selected in Glue: %llu, pre-loading morph state", selectedGuid);
            LoadFullState(selectedGuid);
            g_lastCharacterGuid = selectedGuid;
            g_forceCharacterStateReload = false; // Already loaded for this GUID
        }
        
        g_luaLoadedSent = false;
        g_worldStabilityTicks = 0;
        g_playerGuid = 0;
        g_wasInWorld = false;
        return;
    }

    // Only run if we are in World
    if (!IsInWorld()) {
        g_luaLoadedSent = false;
        g_worldStabilityTicks = 0;
        g_playerGuid = 0;
        // DO NOT CLEAR g_lastCharacterGuid here if it was set in Glue.
        // We want to preserve it so line 73 knows we already loaded the state.
        g_forceCharacterStateReload = true;
        if (g_wasInWorld) {
            Log("Left world (Teleport/Reload/Logout) - Hard reset (clearing morph targets)");
            ResetAllMorphs(true);
            extern DWORD g_playerDescBase;
            g_playerDescBase = 0; // Invalidate descriptor base immediately
            g_wasInWorld = false;
            g_lastCharacterGuid = 0; // Only clear on EXPLICIT world exit
        }
        return;
    }

    __try {
        WowObject* player = GetPlayer();

        // Debug logging for display ID writes
        extern uint32_t g_debugLastDisplayID;
        static uint32_t s_lastLoggedID = 0;
        if (g_debugLastDisplayID != 0 && g_debugLastDisplayID != s_lastLoggedID) {
            Log("Game attempted to write DisplayID: %u", g_debugLastDisplayID);
            s_lastLoggedID = g_debugLastDisplayID;
        }

        // Character change detection
        uint64_t currentGuid = GetPlayerGuid();
        g_playerGuid = currentGuid; // Keep globally visible GUID updated for hooks

        // Character change detection
        if (currentGuid != 0 && player && player->descriptors) {
            bool guidChanged = (currentGuid != g_lastCharacterGuid);
            if (guidChanged || g_forceCharacterStateReload) {
                // If GUID changed without pre-loading, or forced reload triggered
                if (guidChanged) {
                    Log("Character context change (%llu -> %llu), clearing state",
                        g_lastCharacterGuid, currentGuid);
                    ResetAllMorphs(true);
                    LoadFullState(currentGuid);
                }
                
                g_lastCharacterGuid = currentGuid;
                g_forceCharacterStateReload = false;
                Log("Character isolation active for GUID: %llu", currentGuid);
            }
        } else {
            if (player && player->descriptors && currentGuid == 0) {
                ResetAllMorphs(true);
                g_lastCharacterGuid = 0;
                g_forceCharacterStateReload = true;
            }
            return;
        }

        // UPDATE PLAYER BASE
        if (player && player->descriptors) {
            extern DWORD g_playerDescBase;
            g_playerDescBase = (DWORD)(uintptr_t)player->descriptors;
        } else {
            extern DWORD g_playerDescBase;
            g_playerDescBase = 0;
        }

        // World entry detection
        bool stable = false;
        if (!g_wasInWorld) {
            g_worldStabilityTicks++;
            if (g_worldStabilityTicks >= 1) {
                Log("Entered world (Login/Teleport/Reload complete)");
                PrimeOriginalState(player); // Capture native visual of this character
                SoftResetState(player);    // Re-apply morph targets
                g_wasInWorld = true;
                stable = true;
            }
        } else {
            stable = true;
        }

        // Decrement anti-flicker cooldown each tick (50ms)
        if (g_updateCooldown > 0) g_updateCooldown--;

        // Run MorphGuard handles local player, RemoteMorphGuard handles others
        if (player) {
            MorphGuard(player);
        }
        RemoteMorphGuard();

        // Only process Lua commands and initialization if stable
        if (stable) {
            void* L = GetLuaState();
            if (L) {
                // Check if we need to initialize (Reload detection)
                bool needInit = false;
                if (wow_lua_getfield && wow_lua_tolstring && wow_lua_settop) {
                    wow_lua_getfield(L, LUA_GLOBALSINDEX, "TRANSMORPHER_DLL_LOADED");
                    size_t len = 0;
                    const char* val = wow_lua_tolstring(L, -1, &len);
                    // If it's nil/false or not "TRUE", we need to re-init
                    if (!val || strcmp(val, "TRUE") != 0) {
                        needInit = true;
                    }
                    wow_lua_settop(L, -2); // Pop the value
                } else if (!g_luaLoadedSent) {
                    // Fallback if Lua functions missing (shouldn't happen)
                    needInit = true;
                }

                if (FrameScript_Execute && needInit) {
                    FrameScript_Execute("TRANSMORPHER_DLL_LOADED = 'TRUE'", "Transmorpher", 0);

                    // Report detailed status so addon can show diagnostics
                    char statusCmd[512];
                    sprintf_s(statusCmd, sizeof(statusCmd),
                        "TRANSMORPHER_DLL_STATUS = {hooks=%s,status='%s'}",
                        g_hookSuccess ? "true" : "false", g_initStatus);
                    FrameScript_Execute(statusCmd, "Transmorpher", 0);

                    FrameScript_Execute("if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage('|cffffff00StealthMorpher v1.2.0|r initialized. Features: |cff00ff00ACTIVE|r') end", "Transmorpher", 0);
                    g_luaLoadedSent = true;
                    Log("Sent DLL_LOADED flag and welcome message to Lua");

                    RegisterCustomLuaFunctions();
                }

                if (wow_lua_getfield && wow_lua_tolstring && wow_lua_settop) {
                    wow_lua_getfield(L, LUA_GLOBALSINDEX, "TRANSMORPHER_CMD");
                    size_t len = 0;
                    const char* val = wow_lua_tolstring(L, -1, &len);

                    if (val && len > 0) {
                        char buffer[4096];
                        strncpy_s(buffer, sizeof(buffer), val, _TRUNCATE);
                        wow_lua_settop(L, -2); // Pop string

                        if (FrameScript_Execute) {
                            FrameScript_Execute("TRANSMORPHER_CMD = ''", "Transmorpher", 0);
                        }

                        char* next_token = nullptr;
                        char* token = strtok_s(buffer, "|", &next_token);
                        bool needsVisualUpdate = false;

                        while (token) {
                            if (DoMorph(token, player)) needsVisualUpdate = true;
                            token = strtok_s(nullptr, "|", &next_token);
                        }

                        if (needsVisualUpdate && player) {
                            if (CGUnit_UpdateDisplayInfo) {
                                __try { CGUnit_UpdateDisplayInfo(player, 1); } __except(1) {}
                            }
                            ReStampWeapons(player);
                        }
                    } else {
                        wow_lua_settop(L, -2); // Pop nil/empty
                    }

                    // Handle Logging from Lua
                    wow_lua_getfield(L, LUA_GLOBALSINDEX, "TRANSMORPHER_LOG");
                    size_t logLen = 0;
                    const char* logVal = wow_lua_tolstring(L, -1, &logLen);
                    if (logVal && logLen > 0) {
                        char logBuffer[8192];
                        strncpy_s(logBuffer, sizeof(logBuffer), logVal, _TRUNCATE);
                        wow_lua_settop(L, -2); // pop string

                        if (FrameScript_Execute) {
                            FrameScript_Execute("TRANSMORPHER_LOG = ''", "Transmorpher", 0);
                        }

                        char* next_log_token = nullptr;
                        char* log_token = strtok_s(logBuffer, "\n", &next_log_token);
                        while (log_token) {
                            if (strlen(log_token) > 0) {
                                Log("[Lua] %s", log_token);
                            }
                            log_token = strtok_s(nullptr, "\n", &next_log_token);
                        }
                    } else {
                        wow_lua_settop(L, -2); // pop nil/empty
                    }

                    // Periodically export nearby players (every 1 second = 20 ticks of 50ms)
                    static int s_nearbyPlayerTicks = 0;
                    s_nearbyPlayerTicks++;
                    if (s_nearbyPlayerTicks >= 20) {
                        s_nearbyPlayerTicks = 0;
                        if (g_playerGuid != 0) {
                            /*
                            char nearby[4096] = {0};
                            GetNearbyPlayers(g_playerGuid, nearby, sizeof(nearby));
                            char escaped[4096] = {0};
                            int ei = 0;
                            for (int ni = 0; nearby[ni] && ei < 4090; ni++) {
                                char c = nearby[ni];
                                if (c == '"' || c == '\\') {
                                    escaped[ei++] = '\\';
                                }
                                if (c != '\n' && c != '\r') {
                                    escaped[ei++] = c;
                                }
                            }
                            escaped[ei] = '\0';
                            char luaCmd[4096];
                            sprintf_s(luaCmd, sizeof(luaCmd), "TRANSMORPHER_NEARBY = \"%s\"", escaped);
                            if (FrameScript_Execute) {
                                __try {
                                    FrameScript_Execute(luaCmd, "Transmorpher", 0);
                                } __except(1) {}
                            }
                            */
                        }
                    }
                }
            }
        }
    } __except(EXCEPTION_EXECUTE_HANDLER) {
        Log("Exception in MorphTimerProc");
    }
}

static DWORD WINAPI StealthThread(LPVOID lpParam) {
    Log("Stealth thread started. Waiting for WoW window...");
    g_initStatus = "WAITING_WINDOW";

    // FOLDER INIT: Ensure state and log folders exist
    CreateDllSubdirectory("state");
    CreateDllSubdirectory("TSM_logs");
    CleanupOldLogs(10); // Keep latest 10 log files

    // Adaptive wait: poll every 500ms instead of sleeping 8s upfront
    // Total timeout: 60 seconds
    const int MAX_WAIT_MS = 60000;
    const int POLL_MS = 500;
    int waited = 0;

    // Initial short delay to let the process settle
    Sleep(2000);
    waited += 2000;

    while (g_running && waited < MAX_WAIT_MS) {
        g_wowHwnd = FindWindowA("GxWindowClass", NULL);
        if (g_wowHwnd && !IsWindowOwnedByCurrentProcess(g_wowHwnd)) {
            g_wowHwnd = NULL;
        }
        if (g_wowHwnd) break;
        g_wowHwnd = FindWindowA("GxWindowClassD3d", NULL);
        if (g_wowHwnd && !IsWindowOwnedByCurrentProcess(g_wowHwnd)) {
            g_wowHwnd = NULL;
        }
        if (g_wowHwnd) break;
        // Also try enumerating by process ID for unusual window classes
        DWORD pid = GetCurrentProcessId();
        HWND candidate = NULL;
        while ((candidate = FindWindowExA(NULL, candidate, NULL, NULL)) != NULL) {
            DWORD wndPid = 0;
            GetWindowThreadProcessId(candidate, &wndPid);
            if (wndPid == pid && IsWindowVisible(candidate)) {
                char cls[64] = {0};
                GetClassNameA(candidate, cls, sizeof(cls));
                if (strstr(cls, "Gx") || strstr(cls, "WoW") || strstr(cls, "gx")) {
                    g_wowHwnd = candidate;
                    Log("Found WoW window via PID scan: class='%s'", cls);
                    break;
                }
            }
        }
        if (g_wowHwnd) break;
        Sleep(POLL_MS);
        waited += POLL_MS;
    }

    if (!g_wowHwnd) {
        Log("Could not find WoW window after %dms!", waited);
        g_initStatus = "FAILED_NO_WINDOW";
        return 0;
    }
    Log("Found WoW window: 0x%p (after %dms)", g_wowHwnd, waited);

    // Initialize offsets via pattern scanning
    g_initStatus = "SCANNING";
    ScanOffsets();

    // Verify critical function pointers
    if (!FrameScript_Execute) {
        Log("CRITICAL: FrameScript_Execute not found! DLL cannot communicate with addon.");
        g_initStatus = "FAILED_NO_LUA";
        // Still install timer so we can retry if patterns update
    }
    if (!wow_lua_getfield || !wow_lua_tolstring || !wow_lua_settop) {
        Log("WARNING: Some Lua API functions not found. Limited functionality.");
    }

    g_initStatus = "HOOKING";
    bool mountHookOk = false;
    if (InstallMountHook()) {
        Log("Mount display hook installed successfully");
        mountHookOk = true;
    } else {
        Log("WARNING: Failed to install mount display hook!");
    }

    // UpdateDisplayInfo hook is currently disabled in code, just attempt it
    // InstallUpdateDisplayInfoHook();
    

    bool spellHookOk = InstallSpellVisualHook();
    if (!spellHookOk) {
        Log("WARNING: Failed to install spell visual hook!");
    }

    g_hookSuccess = mountHookOk || spellHookOk;
    g_initStatus = (mountHookOk || spellHookOk) ? "ACTIVE" : "ACTIVE_NO_HOOKS";

    // Install Timer on Main Thread
    if (!SetTimer(g_wowHwnd, MORPH_TIMER_ID, 50, MorphTimerProc)) {
        Log("CRITICAL: SetTimer failed! Error: %lu", GetLastError());
        g_initStatus = "FAILED_NO_TIMER";
        return 0;
    }
    Log("Timer installed. Morpher active! (init took %dms)", waited);

    while (g_running) {
        Sleep(1000);
    }

    return 0;
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved) {
    switch (ul_reason_for_call) {
    case DLL_PROCESS_ATTACH: {
        extern HMODULE g_hThisModule;
        g_hThisModule = hModule;
        DisableThreadLibraryCalls(hModule);
        SetupProxy();
        HANDLE hThread = CreateThread(nullptr, 0, StealthThread, nullptr, 0, nullptr);
        if (!hThread) {
            Log("CRITICAL: Failed to create stealth thread! Error: %lu", GetLastError());
            g_initStatus = "FAILED_NO_THREAD";
        } else {
            CloseHandle(hThread); // Don't leak handle
        }
        break;
    }
    case DLL_PROCESS_DETACH:
        g_running = false;
        if (g_wowHwnd) {
            KillTimer(g_wowHwnd, MORPH_TIMER_ID);
            g_wowHwnd = nullptr;
        }
        // Set bypass before unhooking so any in-flight hook execution passes through
        extern volatile bool g_mountHookBypass;
        g_mountHookBypass = true;
        Sleep(100); // Let any in-flight hook execution drain
        UninstallMountHook();
        UninstallUpdateDisplayInfoHook();

        UninstallSpellVisualHook();
        UninstallTimeHook();

        Sleep(50);

        // Clear all pointers to prevent access violations
        extern DWORD g_playerDescBase;
        g_playerDescBase = 0;

        Log("DLL detached cleanly");
        break;
    }
    return TRUE;
}

// Global HMODULE storage for Proxy
HMODULE g_hThisModule = nullptr;
