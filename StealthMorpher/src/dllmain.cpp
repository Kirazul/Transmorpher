// unified version.dll proxy & stealth morpher v3
// Uses window subclassing to execute on WoW's main thread
// NO hooks on game functions, NO memory patches, NO registered Lua functions

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <atomic>

extern "C" {
    FARPROC p[17] = {0};
}

void SetupProxy();

// ================================================================
// Logging
// ================================================================
static void Log(const char* fmt, ...) {
    /* Logging disabled for release
    FILE* f;
    if (fopen_s(&f, "VaultMorph_Stealth.log", "a") == 0) {
        SYSTEMTIME st;
        GetLocalTime(&st);
        fprintf(f, "[%02d:%02d:%02d.%03d] ", st.wHour, st.wMinute, st.wSecond, st.wMilliseconds);
        va_list args;
        va_start(args, fmt);
        vfprintf(f, fmt, args);
        va_end(args);
        fprintf(f, "\n");
        fclose(f);
    }
    */
}

// ================================================================
// WoW Known Offsets (3.3.5a 12340)
// ================================================================
typedef void* (__cdecl* GetLuaState_fn)();
static auto GetLuaState = (GetLuaState_fn)0x00817DB0;

// FrameScript_ExecuteBuffer(code, filename, unused)
typedef int  (__cdecl* FrameScript_Execute_fn)(const char*, const char*, int);
static auto FrameScript_Execute = (FrameScript_Execute_fn)0x00819210;

// Lua 5.1 C API functions (embedded in Wow.exe)
// lua_getfield(L, idx, name) — with idx=-10002 acts as lua_getglobal
typedef void (__cdecl* lua_getfield_fn)(void* L, int idx, const char* k);
static auto wow_lua_getfield = (lua_getfield_fn)0x0084E590;

// lua_tolstring(L, idx, len) — returns const char*
typedef const char* (__cdecl* lua_tolstring_fn)(void* L, int idx, size_t* len);
static auto wow_lua_tolstring = (lua_tolstring_fn)0x0084E0E0;

// lua_settop(L, idx) — used to pop values (settop(L, -2) pops one)
typedef void (__cdecl* lua_settop_fn)(void* L, int idx);
static auto wow_lua_settop = (lua_settop_fn)0x0084DBF0;

#define LUA_GLOBALSINDEX (-10002)

// Object Manager
enum { TYPEMASK_PLAYER = 0x0010 };
static const uint32_t UNIT_FIELD_DISPLAYID       = 0x43 * 4; // OBJECT_END(0x06) + 0x3D
static const uint32_t UNIT_FIELD_NATIVEDISPLAYID = 0x44 * 4; // OBJECT_END(0x06) + 0x3E

static uint32_t GetVisibleItemField(int slot) {
    if (slot < 1 || slot > 19) return 0;
    return (0x11B + (slot - 1) * 2) * 4; // UNIT_END(0x94) + 0x87
}

struct WowObject {
    uint32_t vtable;
    uint32_t unk04;
    uint32_t* descriptors;
};

typedef WowObject* (__cdecl* GetObjectPtr_fn)(uint64_t guid, uint32_t typemask, const char* file, uint32_t line);
static auto GetObjectPtr = (GetObjectPtr_fn)0x004D4DB0;

typedef void(__thiscall* UpdateDisplayInfo_fn)(void* thisPtr, uint32_t unk);
static auto CGUnit_UpdateDisplayInfo = (UpdateDisplayInfo_fn)0x0073E410;

static uint64_t GetPlayerGuid() {
    __try {
        uint32_t clientConnection = *(uint32_t*)0x00C79CE0;
        if (clientConnection) {
            uint32_t objectManager = *(uint32_t*)(clientConnection + 0x2ED0);
            if (objectManager) {
                return *(uint64_t*)(objectManager + 0xC0);
            }
        }
    } __except(EXCEPTION_EXECUTE_HANDLER) {}
    return 0;
}

static WowObject* GetPlayer() {
    __try {
        uint64_t guid = GetPlayerGuid();
        if (!guid) return nullptr;
        WowObject* o = (WowObject*)GetObjectPtr(guid, TYPEMASK_PLAYER, "", 0);
        if (o && o->descriptors) return o;
    } __except(EXCEPTION_EXECUTE_HANDLER) {}
    return nullptr;
}

// ================================================================
// Morph Execution
// ================================================================
static uint32_t g_origDisplay = 0;
static uint32_t g_origItems[20] = {0};
static float g_origScale = 1.0f;
static bool g_saved = false;

static void SaveOriginals(WowObject* p) {
    if (!p || !p->descriptors || g_saved) return;
    g_origDisplay = *(uint32_t*)((uint8_t*)p->descriptors + UNIT_FIELD_DISPLAYID);
    g_origScale = *(float*)((uint8_t*)p->descriptors + 0x10);
    for (int s = 1; s <= 19; s++) {
        uint32_t off = GetVisibleItemField(s);
        if (off) g_origItems[s] = *(uint32_t*)((uint8_t*)p->descriptors + off);
    }
    g_saved = true;
    Log("Originals saved (display=%u, scale=%.2f)", g_origDisplay, g_origScale);
}

static bool DoMorph(const char* cmd) {
    WowObject* player = GetPlayer();
    if (!player) { Log("No player object"); return false; }
    SaveOriginals(player);

    uint8_t* desc = (uint8_t*)player->descriptors;
    bool update = false;

    if (strncmp(cmd, "MORPH:", 6) == 0) {
        uint32_t id = (uint32_t)atoi(cmd + 6);
        if (id > 0) {
            *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = id;
            update = true;
            Log("Morphed displayId=%u", id);
        }
    }
    else if (strncmp(cmd, "SCALE:", 6) == 0) {
        float scale = (float)atof(cmd + 6);
        if (scale > 0.05f && scale <= 20.0f) {
            *(float*)(desc + 0x10) = scale;
            update = true;
            Log("Scaled to %.2f", scale);
        }
    }
    else if (strncmp(cmd, "ITEM:", 5) == 0) {
        int slot = 0; uint32_t itemId = 0;
        sscanf_s(cmd + 5, "%d:%u", &slot, &itemId);
        uint32_t off = GetVisibleItemField(slot);
        if (off) {
            *(uint32_t*)(desc + off) = itemId;
            update = true;
            Log("Set slot %d = item %u", slot, itemId);
        }
    }
    else if (strncmp(cmd, "RESET:ALL", 9) == 0 && g_saved) {
        *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = g_origDisplay;
        *(float*)(desc + 0x10) = g_origScale;
        for (int s = 1; s <= 19; s++) {
            uint32_t off = GetVisibleItemField(s);
            if (off) *(uint32_t*)(desc + off) = g_origItems[s];
        }
        update = true;
        Log("Reset all");
    }
    else if (strncmp(cmd, "RESET:", 6) == 0 && g_saved) {
        int slot = atoi(cmd + 6);
        uint32_t off = GetVisibleItemField(slot);
        if (off) {
            *(uint32_t*)(desc + off) = g_origItems[slot];
            update = true;
            Log("Reset slot %d", slot);
        }
    }

    return update;
}

// ================================================================
// Window Subclassing — runs on WoW's main thread
// ================================================================
static WNDPROC g_origWndProc = nullptr;
static HWND    g_wowHwnd = nullptr;
static UINT_PTR MORPH_TIMER_ID = 0xDEAD;

// Called every 100ms on WoW's MAIN THREAD via SetTimer
static VOID CALLBACK MorphTimerProc(HWND hwnd, UINT uMsg, UINT_PTR idEvent, DWORD dwTime) {
    static int callCount = 0;
    callCount++;
    bool shouldLog = (callCount % 50 == 1); // Log every 5 seconds

    __try {
        void* L = GetLuaState();
        if (!L) { if (shouldLog) Log("TimerProc: No Lua state (call #%d)", callCount); return; }

        // Read TRANSMORPHER_CMD from Lua global table
        wow_lua_getfield(L, LUA_GLOBALSINDEX, "TRANSMORPHER_CMD");
        size_t len = 0;
        const char* val = wow_lua_tolstring(L, -1, &len);
        wow_lua_settop(L, -2); // pop the value

        if (!val || len == 0) return;

        // Copy safely
        char buffer[4096];
        strncpy_s(buffer, sizeof(buffer), val, _TRUNCATE);

        // Clear the Lua variable immediately so we don't double-process and Lua can append again
        FrameScript_Execute("TRANSMORPHER_CMD = ''", "Transmorpher", 0);

        if (shouldLog) Log("TimerProc #%d: Processing queue len=%d", callCount, (int)len);

        // Parse '|' separated commands
        char* next_token = nullptr;
        char* token = strtok_s(buffer, "|", &next_token);
        bool needsVisualUpdate = false;
        
        while (token) {
            Log("Processing token: %s", token);
            if (DoMorph(token)) {
                needsVisualUpdate = true;
            }
            token = strtok_s(nullptr, "|", &next_token);
        }

        if (needsVisualUpdate) {
            WowObject* player = GetPlayer();
            if (player) {
                __try { 
                    CGUnit_UpdateDisplayInfo(player, 1); 
                } __except(EXCEPTION_EXECUTE_HANDLER) { 
                    Log("UpdateDisplayInfo exception"); 
                }
            }
        }

    } __except(EXCEPTION_EXECUTE_HANDLER) {
        Log("Exception in MorphTimerProc");
    }
}

// ================================================================
// Background thread — finds WoW's window and installs timer
// ================================================================
static std::atomic<bool> g_running{true};

static DWORD WINAPI StealthThread(LPVOID lpParam) {
    SetupProxy();
    Log("Stealth thread started. Waiting for WoW window...");
    Sleep(8000);

    // Find WoW's main window
    while (g_running) {
        g_wowHwnd = FindWindowA("GxWindowClass", NULL);
        if (g_wowHwnd) break;
        g_wowHwnd = FindWindowA("GxWindowClassD3d", NULL);
        if (g_wowHwnd) break;
        Sleep(1000);
    }

    if (!g_wowHwnd) {
        Log("Could not find WoW window!");
        return 0;
    }
    Log("Found WoW window: 0x%p", g_wowHwnd);

    // Install a timer on WoW's main thread — fires every 100ms
    // SetTimer with a callback ensures it runs on the window's thread
    SetTimer(g_wowHwnd, MORPH_TIMER_ID, 100, MorphTimerProc);
    Log("Timer installed. Morpher active!");

    // Keep thread alive
    while (g_running) {
        Sleep(1000);
    }

    KillTimer(g_wowHwnd, MORPH_TIMER_ID);
    return 0;
}

// ================================================================
// dinput8.dll proxy
// ================================================================
void SetupProxy() {
    char sysDir[MAX_PATH];
    GetSystemDirectoryA(sysDir, MAX_PATH);
    strcat_s(sysDir, "\\dinput8.dll");

    HMODULE hMod = LoadLibraryA(sysDir);
    if (!hMod) return;

    p[0] = GetProcAddress(hMod, "DirectInput8Create");
    p[1] = GetProcAddress(hMod, "GetdfDIJoystick");
    p[2] = GetProcAddress(hMod, "GetdfDIKeyboard");
    p[3] = GetProcAddress(hMod, "GetdfDIMouse");
    p[4] = GetProcAddress(hMod, "GetdfDIMouse2");
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved) {
    switch (ul_reason_for_call) {
    case DLL_PROCESS_ATTACH: {
        DisableThreadLibraryCalls(hModule);
        CreateThread(nullptr, 0, StealthThread, nullptr, 0, nullptr);
        break;
    }
    case DLL_PROCESS_DETACH:
        g_running = false;
        if (g_wowHwnd) KillTimer(g_wowHwnd, MORPH_TIMER_ID);
        break;
    }
    return TRUE;
}
