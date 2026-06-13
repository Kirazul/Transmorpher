#include "ShutdownCheck.h"
extern "C" volatile bool g_isProcessTerminating = false;

#include <windows.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <atomic>
#include <cmath>
#include "Logger.h"
#include "Proxy.h"
#include "Hooks.h"
#include "Morpher.h"
#include "Utils.h"
#include "WoWOffsets.h"
#include "SpellMorph.h"
#include "D3DHooks.h"
#include "RenderEnables.h"
#include "RenderOverrides.h"
#include "UnitHider.h"
#include "PlayerSoundFilter.h"
#include "ColorEngine.h"
#include "MSDF.h"
#include "Visuals.h"

bool FontExact_OnAttach();

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
static bool g_luaBridgeReady = false;
static constexpr bool kEnableMSDFRuntime = true;
static bool g_msdfBootstrapInstalled = false;
static bool g_msdfBootstrapAttempted = false;

// DLL init status tracking for Lua feedback
static const char* g_initStatus = "STARTING";
static bool g_hookSuccess = false;

static D3DCOLOR HexToD3DColor(const char* hex) {
    if (!hex) return 0xFFFFFFFF;

    char buffer[9] = {};
    strncpy_s(buffer, sizeof(buffer), hex, _TRUNCATE);

    for (char* p = buffer; *p; ++p) {
        if (*p >= 'a' && *p <= 'f') {
            *p = *p - 'a' + 'A';
        }
    }

    if (strlen(buffer) == 6) {
        unsigned int rgb = 0;
        sscanf_s(buffer, "%06X", &rgb);
        return 0xFF000000 | rgb;
    }

    if (strlen(buffer) == 8) {
        unsigned int argb = 0;
        sscanf_s(buffer, "%08X", &argb);
        return (D3DCOLOR)argb;
    }

    return 0xFFFFFFFF;
}


static bool HandleWorldRenderFlagsCommand(const char* key, const char* value) {
    if (!key || !value) return false;

    if (_stricmp(key, "renderenable") == 0) {
        // Gate: render-flag overrides only take effect once the Analysis panel is
        // manually activated. "0" restores the engine's own per-zone flags.
        RenderEnables_SetActive(atoi(value) != 0);
    } else if (_stricmp(key, "renderm2") == 0) {
        RenderEnables_SetM2(atoi(value) != 0);
    } else if (_stricmp(key, "renderterrain") == 0) {
        RenderEnables_SetTerrain(atoi(value) != 0);
    } else if (_stricmp(key, "terrainculling") == 0) {
        RenderEnables_SetTerrainCulling(atoi(value) != 0);
    } else if (_stricmp(key, "m2wmoshadow") == 0) {
        RenderEnables_SetM2WmoShadow(atoi(value) != 0);
    } else if (_stricmp(key, "renderwmo") == 0) {
        RenderEnables_SetWmo(atoi(value) != 0);
    } else if (_stricmp(key, "wmolighting") == 0) {
        RenderEnables_SetWmoLighting(atoi(value) != 0);
    } else if (_stricmp(key, "footprints") == 0) {
        RenderEnables_SetFootprints(atoi(value) != 0);
    } else if (_stricmp(key, "wmotextures") == 0) {
        RenderEnables_SetWmoTextures(atoi(value) != 0);
    } else if (_stricmp(key, "wmoportals") == 0) {
        RenderEnables_SetWmoPortals(atoi(value) != 0);
    } else if (_stricmp(key, "occluders") == 0) {
        RenderEnables_SetOccluders(atoi(value) != 0);
    } else if (_stricmp(key, "m2fade") == 0) {
        RenderEnables_SetM2Fade(atoi(value) != 0);
    } else if (_stricmp(key, "groundclutter") == 0) {
        RenderEnables_SetGroundClutter(atoi(value) != 0);
    } else if (_stricmp(key, "collision") == 0) {
        RenderEnables_SetCollision(atoi(value) != 0);
    } else if (_stricmp(key, "liquidsurface") == 0) {
        RenderEnables_SetLiquidSurface(atoi(value) != 0);
    } else if (_stricmp(key, "liquidparticles") == 0) {
        RenderEnables_SetLiquidParticles(atoi(value) != 0);
    } else if (_stricmp(key, "mountains") == 0) {
        RenderEnables_SetMountains(atoi(value) != 0);
    } else if (_stricmp(key, "specularlighting") == 0) {
        RenderEnables_SetSpecularLighting(atoi(value) != 0);
    } else if (_stricmp(key, "renderobjectshadow") == 0) {
        RenderEnables_SetRenderObjectShadow(atoi(value) != 0);
    } else if (_stricmp(key, "wireframe") == 0) {
        RenderEnables_SetWireframe(atoi(value) != 0);
    } else if (_stricmp(key, "normals") == 0) {
        RenderEnables_SetNormals(atoi(value) != 0);
    } else {
        return false;
    }

    return true;
}

static bool HandleAnalysisConfigCommand(const char* key, const char* value) {
    if (!key || !value) return false;

    if (HandleWorldRenderFlagsCommand(key, value)) {
        return true;
    }

    if (_stricmp(key, "smoothtex") == 0) RenderOverrides_SetSmoothTextures(atoi(value) != 0);
    else if (_stricmp(key, "smoothtexbias") == 0) RenderOverrides_SetSmoothTextureBias((float)atof(value));
    else return false;

    return true;
}

static bool HandleEnvironmentConfigCommand(const char* key, const char* value) {
    if (!key || !value) return false;

    if (_stricmp(key, "worldfog") == 0) RenderOverrides_SetWorldFogEnabled(atoi(value) != 0);
    else if (_stricmp(key, "worldfogcolor") == 0) RenderOverrides_SetWorldFogColor(HexToD3DColor(value));
    else if (_stricmp(key, "worldfogstart") == 0) RenderOverrides_SetWorldFogStart((float)atof(value));
    else if (_stricmp(key, "worldfogend") == 0) RenderOverrides_SetWorldFogEnd((float)atof(value));
    else if (_stricmp(key, "worldfarclipenabled") == 0) RenderOverrides_SetWorldFarClipEnabled(atoi(value) != 0);
    else if (_stricmp(key, "worldfarclip") == 0) RenderOverrides_SetWorldFarClip((float)atof(value));
    else return false;

    return true;
}

static bool ConsumeConfigString(void* luaState, const char* globalName, bool (*handler)(const char*, const char*)) {
    if (!luaState || !globalName || !handler || !wow_lua_getfield || !wow_lua_tolstring || !wow_lua_settop) {
        return false;
    }

    wow_lua_getfield(luaState, LUA_GLOBALSINDEX, globalName);
    size_t valueLen = 0;
    const char* value = wow_lua_tolstring(luaState, -1, &valueLen);
    if (!value || valueLen == 0) {
        wow_lua_settop(luaState, -2);
        return false;
    }

    size_t safeLen = valueLen;
    if (safeLen > 65535) safeLen = 65535;

    char* payload = (char*)malloc(safeLen + 1);
    if (!payload) {
        wow_lua_settop(luaState, -2);
        return false;
    }

    memcpy(payload, value, safeLen);
    payload[safeLen] = '\0';

    wow_lua_settop(luaState, -2);
    if (FrameScript_Execute) {
        char clearCommand[128];
        sprintf_s(clearCommand, sizeof(clearCommand), "%s = ''", globalName);
        FrameScript_Execute(clearCommand, "Transmorpher", 0);
    }

    bool handledAny = false;
    char* nextToken = nullptr;
    char* token = strtok_s(payload, ";", &nextToken);
    while (token) {
        if (token[0] != '\0') {
            char* eq = strchr(token, '=');
            if (eq) {
                *eq = '\0';
                char* key = token;
                char* cfgValue = eq + 1;

                while (*key == ' ' || *key == '\t') ++key;
                while (*cfgValue == ' ' || *cfgValue == '\t') ++cfgValue;

                for (char* end = key + strlen(key); end > key && (end[-1] == ' ' || end[-1] == '\t'); ) {
                    *(--end) = '\0';
                }
                for (char* end = cfgValue + strlen(cfgValue); end > cfgValue && (end[-1] == ' ' || end[-1] == '\t'); ) {
                    *(--end) = '\0';
                }

                if (handler(key, cfgValue)) {
                    handledAny = true;
                }
            }
        }
        token = strtok_s(nullptr, ";", &nextToken);
    }

    free(payload);
    return handledAny;
}

static bool IsWindowOwnedByCurrentProcess(HWND hwnd) {
    if (!hwnd) return false;
    DWORD wndPid = 0;
    GetWindowThreadProcessId(hwnd, &wndPid);
    return wndPid == GetCurrentProcessId();
}

static bool IsLuaBridgeReady(void* luaState) {
    if (g_luaBridgeReady) return true;
    if (!luaState || !wow_lua_getfield || !wow_lua_tolstring || !wow_lua_settop) return false;

    wow_lua_getfield(luaState, LUA_GLOBALSINDEX, "TRANSMORPHER_LUA_READY");
    size_t len = 0;
    const char* value = wow_lua_tolstring(luaState, -1, &len);
    const bool ready = value && strcmp(value, "TRUE") == 0;
    wow_lua_settop(luaState, -2);

    if (ready) {
        g_luaBridgeReady = true;
        Log("Lua bridge reported ready by addon");
    }
    return ready;
}

static VOID CALLBACK MorphTimerProc(HWND hwnd, UINT uMsg, UINT_PTR idEvent, DWORD dwTime) {
    if (!g_running) return;
    if (g_isProcessTerminating) return;
    if (!g_wowHwnd) return;

    // HANDLE CHARACTER SELECTION (GLUE) MONITORING
    if (IsInGlue()) {
        uint64_t selectedGuid = GetSelectedCharacterGuid();
        if (selectedGuid != 0 && selectedGuid != g_lastCharacterGuid) {
            Log("Character selected in Glue: %llu, pre-loading morph state", selectedGuid);
            LoadFullState(selectedGuid);
            g_lastCharacterGuid = selectedGuid;
            g_forceCharacterStateReload = false; // Already loaded for this GUID
            // Force the doll to rebuild through our char-select hook so the persisted
            // barber/morph/skin look (incl. free-RGB colors) shows on a COLD launch. Without
            // this the engine keeps the doll it cached before our customization ran, so the
            // look only appeared after entering the world once and returning. One rebuild per
            // selection on the glue screen — cheap and exactly when the engine rebuilds anyway.
            ColorEngine::ForceRefreshCharSelectDoll();
        }
        
        g_luaLoadedSent = false;
        g_luaBridgeReady = false;
        g_worldStabilityTicks = 0;
        g_playerGuid = 0;
        g_wasInWorld = false;
        UnitHider_ClearLocal();
        return;
    }

    // Only run if we are in World
    if (!IsInWorld()) {
        g_luaLoadedSent = false;
        g_luaBridgeReady = false;
        g_worldStabilityTicks = 0;
        g_playerGuid = 0;
        UnitHider_ClearLocal(); // stale local snapshot must not hide players
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

        // Refresh the local-player position/GUID snapshot used by the distance-based
        // player hide. Runs on the main thread, same as the ShouldRender render pass.
        UnitHider_SetLocal(currentGuid, player);
        // Reassert global toggles (shadow render flag) each in-world tick.
        UnitHider_ApplyGlobals();

        // World entry detection
        bool stable = false;
        if (!g_wasInWorld) {
            g_worldStabilityTicks++;
            if (g_worldStabilityTicks >= 1) {
                Log("Entered world (Login/Teleport/Reload complete)");
                PrimeOriginalState(player); // Capture native visual of this character
                SoftResetState(player);    // Re-apply morph targets
                RenderOverrides_RefreshWorldState();
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
            // Fire the deferred initial model refresh once the model system has
            // warmed up after login (prevents the first-login cold-start crash).
            ProcessDeferredInitialRefresh(player);
            // Fire the coalesced skin/recolor rebuild after a batch of recolor
            // commands settles (one re-bake per batch: flicker-free, no relog).
            ProcessDeferredSkinRefresh(player);
            // Self-healing character-aura watchdog: re-attaches a visual ONLY if it actually
            // vanished (model rebuild / GC / finished one-shot). Runs independent of morph/skin
            // state and never touches alive visuals, so there is no flicker. This is what makes
            // applied visuals truly permanent ("virtual buff") without any periodic re-assert.
            Visuals_Tick();
        }
        RemoteMorphGuard();

        // Re-affirm the custom camera FOV (no-op unless the user set one).
        ApplyCameraFov();

        // Keep the skybox override pinned (the zone writer runs on light updates).
        ColorEngine::ReassertSkybox();
        // Keep forced weather pinned until the engine actually applies it (the
        // weather object is created lazily, so a lone SetType can land too early).
        ColorEngine::ReassertWeather();

        // Only process Lua once the addon explicitly reports that its world-side Lua bridge is ready.
        if (stable) {
            D3DHooks_Initialize();
        }

        if (stable) {
            void* L = GetLuaState();
            if (L && IsLuaBridgeReady(L)) {
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
                        char buffer[32768];
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
                            // This batch already rebuilt the model — cancel the deferred
                            // login forced refresh so entering world doesn't reload twice.
                            CancelDeferredInitialRefresh();
                            ReStampWeapons(player);
                            // When MOUNTED, the rider model caches its equipment, so a
                            // plain UpdateDisplayInfo doesn't show newly-applied gear.
                            // Re-trigger the mount model (dismount+remount) once so the
                            // mounted character rebuilds with the new items/morph.
                            //
                            // Detect "is rendering a mount" from the DESCRIPTOR itself
                            // (UNIT_FIELD_MOUNTDISPLAYID > 0), NOT from g_luaMounted: that
                            // flag is only set by the addon's SET:MOUNTED on a mount-STATE
                            // CHANGE, so if the player was already mounted when they applied
                            // a transmog (or that event never reached us) it stays 0 and the
                            // rider was never rebuilt -> "can't transmog on top of the mount."
                            // The native mount field is authoritative, so use it and self-heal
                            // g_luaMounted (the MorphGuard skipMount gate relies on it too).
                            if (player->descriptors) {
                                uint8_t* d = (uint8_t*)player->descriptors;
                                uint32_t curMount = *(uint32_t*)(d + UNIT_FIELD_MOUNTDISPLAYID);
                                if (curMount > 0) {
                                    if (g_luaMounted != 1) g_luaMounted = 1;  // self-heal stale flag
                                    __try { CGUnit_C_DismountModel(player, 0); } __except(1) {}
                                    __try { CGUnit_C_MountModel(player, 0, 0); } __except(1) {}
                                }
                            }
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

                    const bool analysisCfgChanged = ConsumeConfigString(L, "TRANSMORPHER_ANALYSIS_CFG", HandleAnalysisConfigCommand);
                    const bool environmentCfgChanged = ConsumeConfigString(L, "TRANSMORPHER_ENV_CFG", HandleEnvironmentConfigCommand);
                    (void)analysisCfgChanged;
                    (void)environmentCfgChanged;

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

    RenderOverrides_RefreshWorldState();
    RenderEnables_Apply();
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

    // UpdateDisplayInfo injection hook: DISABLED. This experimental hook rewrote our
    // morph into the unit descriptors INSIDE WoW's own model rebuild. It caused a
    // string of regressions (slots not reliably reflecting their morph state, mount
    // sync breakage, etc.), so we revert to the stable enforcement path:
    // MorphGuard (per-tick descriptor enforcement) + the command-driven rebuilds +
    // the deferred login refresh. Do NOT re-enable without an in-game soak test.
    //
    // if (InstallUpdateDisplayInfoHook()) {
    //     Log("UpdateDisplayInfo injection hook installed (seamless morph)");
    // } else {
    //     Log("WARNING: UpdateDisplayInfo injection hook failed to install");
    // }
    Log("UpdateDisplayInfo injection hook intentionally DISABLED (stable MorphGuard path)");


    bool spellHookOk = InstallSpellVisualHook();
    if (!spellHookOk) {
        Log("WARNING: Failed to install spell visual hook!");
    }

    // Production: make sure the user's client has SET dbCompress "0" (adds it if missing).
    EnsureConfigDbCompress();

    D3DHooks_Initialize();
    RenderEnables_Initialize();
    RenderOverrides_RefreshWorldState();
    UnitHider_Initialize();      // distance-based player hide (inert until enabled)
    PlayerSoundFilter_Initialize(); // mute other players' sounds (inert until enabled)
    ColorEngine::Initialize();   // texture-swap / fog-color / particle-tint hooks

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
        if (kEnableMSDFRuntime && !g_msdfBootstrapInstalled && !g_msdfBootstrapAttempted) {
            g_msdfBootstrapAttempted = true;
            g_msdfBootstrapInstalled = FontExact_OnAttach();
            Log(g_msdfBootstrapInstalled
                ? "[MSDF] Reference bootstrap armed during DLL attach"
                : "[MSDF] Reference bootstrap skipped or failed during DLL attach");
        }
        HANDLE hThread = CreateThread(nullptr, 0, StealthThread, nullptr, 0, nullptr);
        if (!hThread) {
            Log("CRITICAL: Failed to create stealth thread! Error: %lu", GetLastError());
            g_initStatus = "FAILED_NO_THREAD";
        } else {
            CloseHandle(hThread); // Don't leak handle
        }
        break;
    }
    case DLL_PROCESS_DETACH: {
        // Mark the global terminating flag first so any hook callbacks that may
        // still fire (D3D present/draw, FreeType teardown, etc.) immediately pass
        // through to the originals instead of touching our state.
        g_running = false;
        g_isProcessTerminating = true;
        extern volatile bool g_mountHookBypass;
        g_mountHookBypass = true;

        // CRITICAL: When lpReserved != NULL the process is terminating. At this
        // point Windows has already forcibly terminated every other thread while
        // holding the loader lock, so any remaining state (heap, D3D device,
        // FreeType/msdfgen objects, detoured code pages) may be half-torn-down.
        // Removing Detours hooks (which rewrites code pages and runs a transaction
        // across now-dead threads) or freeing FreeType/msdfgen here is exactly what
        // produced the ERROR #132 ACCESS_VIOLATION on close. The OS reclaims all of
        // this memory automatically, so we MUST NOT do manual cleanup here.
        if (lpReserved != nullptr) {
            // Process is exiting: leave everything to the OS. Just stop our timer
            // (cheap, safe) and return.
            if (g_wowHwnd) {
                KillTimer(g_wowHwnd, MORPH_TIMER_ID);
                g_wowHwnd = nullptr;
            }
            break;
        }

        // lpReserved == NULL: a genuine FreeLibrary() unload (never happens for the
        // injected proxy in practice, but handle it correctly). Other threads are
        // still alive here, so perform a full graceful teardown.
        if (g_wowHwnd) {
            KillTimer(g_wowHwnd, MORPH_TIMER_ID);
            g_wowHwnd = nullptr;
        }
        Sleep(100); // Let any in-flight hook execution drain
        UninstallMountHook();
        UninstallUpdateDisplayInfoHook();

        UninstallSpellVisualHook();
        UninstallTimeHook();
        ColorEngine::Shutdown();
        D3DHooks_Shutdown();
        RenderEnables_Shutdown();
        UnitHider_Shutdown();
        PlayerSoundFilter_Shutdown();
        if (g_msdfBootstrapInstalled || MSDF::IsInitialized()) {
            MSDF::shutdown();
            g_msdfBootstrapInstalled = false;
            g_msdfBootstrapAttempted = false;
        }

        Sleep(50);

        // Clear all pointers to prevent access violations
        extern DWORD g_playerDescBase;
        g_playerDescBase = 0;

        Log("DLL detached cleanly");
        break;
    }
    }
    return TRUE;
}

// Global HMODULE storage for Proxy
HMODULE g_hThisModule = nullptr;
