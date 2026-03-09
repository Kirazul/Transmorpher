// unified dinput8.dll proxy & stealth morpher v5
// Uses window subclassing to execute on WoW's main thread
// Minimal hook at base+0x343BAC for mount model morphing
//
// v5 changes:
// - Mount morph via assembly hook on descriptor write instruction
//   (only way to trigger the client's mount model reload pipeline)
// - DLL-side morph state tracking for automatic single-shot restoration
// - Detects displayId / weapon field changes and restores ONCE per tick
// - Weapon persistence across sheathe/unsheathe/combat/swap
// - Shapeshift / Deathbringer's Will suspend/resume via addon signals

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <psapi.h>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <atomic>

#pragma comment(lib, "psapi.lib")

extern "C" {
    FARPROC p[17] = {0};
}

void SetupProxy();

// ================================================================
// Logging
// ================================================================
static void Log(const char* fmt, ...) {
    FILE* f;
    if (fopen_s(&f, "Transmorpher.log", "a") == 0) {
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
typedef void (__cdecl* lua_getfield_fn)(void* L, int idx, const char* k);
static auto wow_lua_getfield = (lua_getfield_fn)0x0084E590;

typedef const char* (__cdecl* lua_tolstring_fn)(void* L, int idx, size_t* len);
static auto wow_lua_tolstring = (lua_tolstring_fn)0x0084E0E0;

typedef void (__cdecl* lua_settop_fn)(void* L, int idx);
static auto wow_lua_settop = (lua_settop_fn)0x0084DBF0;

#define LUA_GLOBALSINDEX (-10002)

// SimplyMorpher3 addresses (verified working)
static const uint32_t CLIENT_CONNECTION = 0x00CD87A8;  // SimplyMorpher3 uses this
static const uint32_t OBJMGR_OFFSET = 0x34;            // +52 decimal
static const uint32_t PLAYER_OFFSET = 0x24;            // +36 decimal  
static const uint32_t DESC_OFFSET = 0x08;              // +8 decimal

// Object Manager
enum { TYPEMASK_PLAYER = 0x0010, TYPEMASK_UNIT = 0x0008 };
static const uint32_t UNIT_FIELD_DISPLAYID        = 0x43 * 4;
static const uint32_t UNIT_FIELD_NATIVEDISPLAYID  = 0x44 * 4;
static const uint32_t UNIT_FIELD_MOUNTDISPLAYID   = 0x45 * 4;  // mount display
static const uint32_t UNIT_FIELD_CRITTER          = 0x0A * 4;  // critter GUID (companion pet)
static const uint32_t UNIT_FIELD_SUMMON           = 0x08 * 4;  // summoned pet GUID (hunter/warlock pet)
static const uint32_t UNIT_FIELD_SUMMONEDBY       = 0x0E * 4;  // GUID of unit that summoned this one
static const uint32_t UNIT_FIELD_CREATEDBY        = 0x10 * 4;  // GUID of unit that created this one
static const uint32_t PLAYER_FIELD_CHOSEN_TITLE   = 0x141 * 4; // PLAYER_CHOSEN_TITLE (3.3.5a 12340)
static const uint32_t PLAYER_FIELD_KNOWN_TITLES   = 0x272 * 4; // PLAYER__FIELD_KNOWN_TITLES (start, 6 uint32 total)

static uint32_t GetVisibleItemField(int slot) {
    if (slot < 1 || slot > 19) return 0;
    return (0x11B + (slot - 1) * 2) * 4;
}

// ================================================================
// Visible enchant field in PLAYER descriptor
// ================================================================
// PLAYER_VISIBLE_ITEM uses 2 fields per slot: [displayID, enchantVisualID]
// GetVisibleItemField(slot) returns the offset for displayID.
// The enchant visual is at the NEXT field (+1 index = +4 bytes).
static uint32_t GetVisibleEnchantField(int slot) {
    if (slot < 1 || slot > 19) return 0;
    return (0x11B + (slot - 1) * 2 + 1) * 4;  // +1 for enchant field
}

struct WowObject {
    uint32_t vtable;
    uint32_t unk04;
    uint32_t* descriptors;      // 0x08
    uint8_t  pad0C[0x14];       // 0x0C .. 0x1F
    uint32_t objType;           // 0x20 (1=Object,3=Unit,4=Player,5=GameObject)
    uint8_t  pad24[0x18];       // 0x24 .. 0x3B
    uint32_t nextObject;        // 0x3C — pointer to next object in linked list
};

// ================================================================
// Helper: Read item GUID from inventory slot
// ================================================================
static uint64_t GetInventoryItemGuid(WowObject* player, int slot) {
    if (!player || !player->descriptors) return 0;
    __try {
        // PLAYER_FIELD_INV_SLOT_HEAD starts at offset 0x4A (field index 0x4A * 4 bytes)
        // Each inventory slot is 2 fields (8 bytes for GUID)
        // Slot 0 = head, slot 15 = main hand (16-1), slot 16 = off-hand (17-1)
        uint32_t baseField = 0x4A;  // PLAYER_FIELD_INV_SLOT_HEAD
        uint32_t slotIndex = slot - 1;  // Convert 1-based to 0-based
        uint32_t fieldOffset = (baseField + slotIndex * 2) * 4;
        
        uint8_t* desc = (uint8_t*)player->descriptors;
        uint32_t guidLow = *(uint32_t*)(desc + fieldOffset);
        uint32_t guidHigh = *(uint32_t*)(desc + fieldOffset + 4);
        return ((uint64_t)guidHigh << 32) | guidLow;
    } __except(EXCEPTION_EXECUTE_HANDLER) {}
    return 0;
}

// Iterate ALL units in the object manager that were summoned/created by playerGuid.
// For each match, call the callback.  Catches guardians (DK ghoul, Army of the Dead, etc.)
typedef void (*ForEachGuardianCb)(WowObject* unit, uint8_t* desc, void* ctx);
static void ForEachPlayerGuardian(uint64_t playerGuid, ForEachGuardianCb cb, void* ctx) {
    __try {
        uint32_t clientConnection = *(uint32_t*)0x00C79CE0;
        if (!clientConnection) return;
        uint32_t objectManager = *(uint32_t*)(clientConnection + 0x2ED0);
        if (!objectManager) return;
        uint32_t objPtr = *(uint32_t*)(objectManager + 0xAC);
        while (objPtr != 0) {
            __try {
                WowObject* obj = (WowObject*)objPtr;
                // Only process units (type 3), skip players (type 4)
                if (obj->objType == 3 && obj->descriptors) {
                    uint8_t* d = (uint8_t*)obj->descriptors;
                    uint64_t summonedBy = *(uint64_t*)(d + UNIT_FIELD_SUMMONEDBY);
                    uint64_t createdBy  = *(uint64_t*)(d + UNIT_FIELD_CREATEDBY);
                    if (summonedBy == playerGuid || createdBy == playerGuid) {
                        cb(obj, d, ctx);
                    }
                }
                objPtr = obj->nextObject;
            } __except(EXCEPTION_EXECUTE_HANDLER) {
                break;
            }
        }
    } __except(EXCEPTION_EXECUTE_HANDLER) {}
}

typedef WowObject* (__cdecl* GetObjectPtr_fn)(uint64_t guid, uint32_t typemask, const char* file, uint32_t line);
static auto GetObjectPtr = (GetObjectPtr_fn)0x004D4DB0;

typedef void(__thiscall* UpdateDisplayInfo_fn)(void* thisPtr, uint32_t unk);
static auto CGUnit_UpdateDisplayInfo = (UpdateDisplayInfo_fn)0x0073E410;

// Time/Day-Night (3.3.5a 12340)
// Hook at 0x0076CFF0 to override game time (re-implemented using .1337 file logic)
static const DWORD TIME_HOOK_ADDR = 0x0076CFF0;
static const DWORD TIME_VAR_ADDR = 0x0076D000;
static float g_timeOfDay = 0.5f;
static bool g_timeHookInstalled = false;
static BYTE g_timeHookOrigBytes[32] = {0}; // Increased size to cover var area too

static bool InstallTimeHook() {
    if (g_timeHookInstalled) return true;
    
    // Unprotect a larger block to cover both hook and var
    DWORD oldProt;
    if (!VirtualProtect((void*)TIME_HOOK_ADDR, 64, PAGE_EXECUTE_READWRITE, &oldProt)) {
        Log("ERROR: Time hook VirtualProtect failed");
        return false;
    }

    // Save original bytes (enough for hook + var)
    memcpy(g_timeHookOrigBytes, (void*)TIME_HOOK_ADDR, 32);

    // Prepare patch
    // 50           push eax
    // B8 00 D0 76 00 mov eax, 0076D000
    // D9 00        fld dword ptr [eax]
    // 58           pop eax
    // C3           ret
    // ... NOPs ...
    
    BYTE patch[16];
    memset(patch, 0x90, 16);
    
    patch[0] = 0x50;
    patch[1] = 0xB8;
    *(DWORD*)(patch + 2) = TIME_VAR_ADDR;
    patch[6] = 0xD9;
    patch[7] = 0x00;
    patch[8] = 0x58;
    patch[9] = 0xC3;
    
    memcpy((void*)TIME_HOOK_ADDR, patch, 16);
    
    // Initialize the var at 0x0076D000
    *(float*)TIME_VAR_ADDR = g_timeOfDay;
    
    // We leave it writable/executable so we can update the float dynamically
    // VirtualProtect((void*)TIME_HOOK_ADDR, 64, oldProt, &oldProt);
    
    g_timeHookInstalled = true;
    Log("Time hook installed at 0x%08X (using storage at 0x%08X)", TIME_HOOK_ADDR, TIME_VAR_ADDR);
    return true;
}

static void UninstallTimeHook() {
    if (!g_timeHookInstalled) return;
    
    DWORD oldProt;
    if (VirtualProtect((void*)TIME_HOOK_ADDR, 64, PAGE_EXECUTE_READWRITE, &oldProt)) {
        memcpy((void*)TIME_HOOK_ADDR, g_timeHookOrigBytes, 32);
        VirtualProtect((void*)TIME_HOOK_ADDR, 64, oldProt, &oldProt);
    }
    g_timeHookInstalled = false;
    Log("Time hook uninstalled");
}

// ================================================================
// Get player object using SimplyMorpher3's exact method
// ================================================================
static WowObject* GetPlayerSimplyMorpher3() {
    __try {
        // SimplyMorpher3's exact pointer chain
        uint32_t clientConn = *(uint32_t*)CLIENT_CONNECTION;
        if (!clientConn) return nullptr;
        
        uint32_t objMgr = *(uint32_t*)(clientConn + OBJMGR_OFFSET);
        if (!objMgr) return nullptr;
        
        uint32_t playerObj = *(uint32_t*)(objMgr + PLAYER_OFFSET);
        if (!playerObj) return nullptr;
        
        WowObject* player = (WowObject*)playerObj;
        if (player && player->descriptors) {
            return player;
        }
    } __except(EXCEPTION_EXECUTE_HANDLER) {}
    return nullptr;
}

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
    // Try SimplyMorpher3's method first (more reliable for morphing)
    WowObject* player = GetPlayerSimplyMorpher3();
    if (player) return player;
    
    // Fallback to original method
    __try {
        uint64_t guid = GetPlayerGuid();
        if (!guid) return nullptr;
        WowObject* o = (WowObject*)GetObjectPtr(guid, TYPEMASK_PLAYER, "", 0);
        if (o && o->descriptors) return o;
    } __except(EXCEPTION_EXECUTE_HANDLER) {}
    return nullptr;
}

// ================================================================
// Enchant Morph Helpers (PLAYER_VISIBLE_ITEM based)
// ================================================================
// Read the visible enchant ID from the PLAYER descriptor for a given slot
static uint32_t ReadVisibleEnchant(WowObject* player, int slot) {
    if (!player || !player->descriptors) return 0;
    uint32_t off = GetVisibleEnchantField(slot);
    if (!off) return 0;
    __try {
        return *(uint32_t*)((uint8_t*)player->descriptors + off);
    } __except(EXCEPTION_EXECUTE_HANDLER) {}
    return 0;
}

// Write a visible enchant ID to the PLAYER descriptor for a given slot
static bool WriteVisibleEnchant(WowObject* player, int slot, uint32_t enchantId) {
    if (!player || !player->descriptors) return false;
    uint32_t off = GetVisibleEnchantField(slot);
    if (!off) return false;
    __try {
        uint8_t* desc = (uint8_t*)player->descriptors;
        uint32_t cur = *(uint32_t*)(desc + off);
        if (cur != enchantId) {
            *(uint32_t*)(desc + off) = enchantId;
            return true;
        }
    } __except(EXCEPTION_EXECUTE_HANDLER) {}
    return false;
}

// ================================================================
// Morph State Tracking (DLL-side)
// ================================================================

// Original values saved from the player's real data (before any morph)
static uint32_t g_origDisplay = 0;
static uint32_t g_origItems[20] = {0};
static float g_origScale = 1.0f;
static bool g_saved = false;
// Sentinel value stored in g_morphItems[slot] when a slot is hidden (item 0).
// We cannot use 0 itself because 0 means "not morphed" and RefreshOriginals
// would overwrite g_origItems with the now-zeroed descriptor field.
static const uint32_t HIDDEN_SENTINEL = UINT32_MAX;

// Active morph state — what the addon has requested
// 0 means "no morph for this field, use native value"
static uint32_t g_morphDisplay = 0;
static uint32_t g_morphItems[20] = {0};
static float g_morphScale = 0.0f;
static bool g_hasMorph = false;

// Mount morph state
static uint32_t g_morphMount = 0;
static uint32_t g_origMount = 0;

// Pet (critter) morph state
static uint32_t g_morphPet = 0;  // desired critter displayID
static uint32_t g_origPetDisplay = 0;  // original critter display before morph

// Hunter pet (summoned unit) morph state
static uint32_t g_morphHPet = 0;  // desired hunter pet displayID
static uint32_t g_origHPetDisplay = 0;  // original hunter pet display before morph
static float    g_morphHPetScale = 0.0f; // desired hunter pet scale (0 = no change)

// Enchant morph state — visual enchant override for weapons
// slot 16 = Main Hand, slot 17 = Off-Hand (1-based equipment slots)
static uint32_t g_morphEnchantMH = 0;  // desired enchant ID for main hand
static uint32_t g_morphEnchantOH = 0;  // desired enchant ID for off-hand
// Title morph state
static uint32_t g_morphTitle = 0;      // desired title ID
static bool g_origTitleWasKnown = false; // was title originally known?

static uint32_t g_origEnchantMH = 0;   // original enchant ID before morph
static uint32_t g_origEnchantOH = 0;   // original enchant ID before morph
static uint32_t g_origTitle = 0;       // original title before morph

// Track equipped weapons to detect swaps
// We need to track the actual item GUID, not just display ID
// because enchant-only morphs don't change the display ID
static uint64_t g_lastWeaponMHGuid = 0;
static uint64_t g_lastWeaponOHGuid = 0;

// Suspension: true when addon signals a model-changing form is active
static bool g_suspended = false;

// Character change detection — track the local player GUID so we can
// automatically clear all stale morph state the instant a new character
// loads, BEFORE MorphGuard has a chance to apply old morphs.
static uint64_t g_lastPlayerGuid = 0;

// Weapon refresh: after weapon morphs, force extra visual updates for
// a few ticks to ensure the render pipeline picks up our values.
// Counts down from 3 to 0. While > 0, each tick re-stamps + updates.
static int g_weaponRefreshTicks = 0;

static bool IsTitleKnown(WowObject* player, uint32_t titleId) {
    if (!player || !player->descriptors || titleId == 0) return false;
    uint32_t* known = (uint32_t*)((uint8_t*)player->descriptors + PLAYER_FIELD_KNOWN_TITLES);
    int idx = titleId / 32;
    if (idx >= 6) return false;
    return (known[idx] & (1 << (titleId % 32))) != 0;
}

static void SetTitleKnown(WowObject* player, uint32_t titleId, bool known) {
    if (!player || !player->descriptors || titleId == 0) return;
    uint32_t* arr = (uint32_t*)((uint8_t*)player->descriptors + PLAYER_FIELD_KNOWN_TITLES);
    int idx = titleId / 32;
    if (idx >= 6) return;
    uint32_t mask = (1 << (titleId % 32));
    if (known) arr[idx] |= mask;
    else arr[idx] &= ~mask;
}

// ================================================================
// Helper: Recompute g_hasMorph
// ================================================================
static void UpdateHasMorph() {
    g_hasMorph = false;
    if (g_morphDisplay > 0) { g_hasMorph = true; return; }
    if (g_morphScale > 0.0f) { g_hasMorph = true; return; }
    if (g_morphMount > 0)   { g_hasMorph = true; return; }
    if (g_morphPet > 0)     { g_hasMorph = true; return; }
    if (g_morphHPet > 0)    { g_hasMorph = true; return; }
    if (g_morphEnchantMH > 0) { g_hasMorph = true; return; }
    if (g_morphEnchantOH > 0) { g_hasMorph = true; return; }
    if (g_morphTitle > 0)   { g_hasMorph = true; return; }
    for (int s = 1; s <= 19; s++) {
        if (g_morphItems[s] > 0) { g_hasMorph = true; return; }
    }
}

// ================================================================
// Save originals (once, on first morph)
// ================================================================
static void SaveOriginals(WowObject* p) {
    if (!p || !p->descriptors || g_saved) return;
    uint8_t* desc = (uint8_t*)p->descriptors;
    // Use NATIVEDISPLAYID — always the character's real humanoid model,
    // never a shapeshift form (cat, bear, ghost wolf, etc.)
    g_origDisplay = *(uint32_t*)(desc + UNIT_FIELD_NATIVEDISPLAYID);
    g_origMount = *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID);
    g_origScale = *(float*)(desc + 0x10);
    for (int s = 1; s <= 19; s++) {
        uint32_t off = GetVisibleItemField(s);
        if (off) g_origItems[s] = *(uint32_t*)(desc + off);
    }
    // Save original enchant visuals from PLAYER_VISIBLE_ITEM
    {
        uint32_t offMH = GetVisibleEnchantField(16);
        uint32_t offOH = GetVisibleEnchantField(17);
        if (offMH) g_origEnchantMH = *(uint32_t*)(desc + offMH);
        if (offOH) g_origEnchantOH = *(uint32_t*)(desc + offOH);
    }
    // Save original title
    g_origTitle = *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE);
    g_saved = true;
    Log("Originals saved (display=%u, scale=%.2f)", g_origDisplay, g_origScale);
}

// ================================================================
// Refresh originals for non-morphed slots
// Called periodically so that RESET works correctly after gear changes.
// Only updates slots that are NOT currently morphed.
// ================================================================
static void RefreshOriginals(WowObject* p) {
    if (!p || !p->descriptors || !g_saved) return;
    uint8_t* desc = (uint8_t*)p->descriptors;

    // Update native display ID if we're not morphing it.
    // Always read from NATIVEDISPLAYID — it's the character's real model,
    // never a shapeshift form, DBW proc race, or other transient display.
    if (g_morphDisplay == 0) {
        g_origDisplay = *(uint32_t*)(desc + UNIT_FIELD_NATIVEDISPLAYID);
    }
    // Update mount display if not morphed
    if (g_morphMount == 0) {
        g_origMount = *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID);
    }
    // Update scale if not morphed
    if (g_morphScale <= 0.0f) {
        g_origScale = *(float*)(desc + 0x10);
    }
    // Update item slots that aren't morphed
    for (int s = 1; s <= 19; s++) {
        if (g_morphItems[s] == 0) {
            uint32_t off = GetVisibleItemField(s);
            if (off) g_origItems[s] = *(uint32_t*)(desc + off);
        }
    }
    // Update original enchant visuals if not morphed
    if (g_morphEnchantMH == 0) {
        uint32_t off = GetVisibleEnchantField(16);
        if (off) g_origEnchantMH = *(uint32_t*)(desc + off);
    }
    if (g_morphEnchantOH == 0) {
        uint32_t off = GetVisibleEnchantField(17);
        if (off) g_origEnchantOH = *(uint32_t*)(desc + off);
    }
    // Update original title if not morphed
    if (g_morphTitle == 0) {
        g_origTitle = *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE);
    }
}

// ================================================================
// Re-stamp weapon descriptors after UpdateDisplayInfo
// UpdateDisplayInfo may internally overwrite weapon visible item
// fields from the real inventory. We re-write our morphed values
// immediately so the render pipeline (which reads descriptors
// asynchronously) sees our values, not the real ones.
// ================================================================
static void ReStampWeapons(WowObject* player) {
    if (!player || !player->descriptors) return;
    uint8_t* desc = (uint8_t*)player->descriptors;
    for (int s = 16; s <= 18; s++) {
        if (g_morphItems[s] > 0) {
            uint32_t off = GetVisibleItemField(s);
            if (off) {
                uint32_t target = (g_morphItems[s] == HIDDEN_SENTINEL) ? 0 : g_morphItems[s];
                *(uint32_t*)(desc + off) = target;
            }
        }
    }
    // Re-stamp enchant visuals via PLAYER_VISIBLE_ITEM
    if (g_morphEnchantMH > 0) {
        uint32_t off = GetVisibleEnchantField(16);
        if (off) *(uint32_t*)(desc + off) = g_morphEnchantMH;
    }
    if (g_morphEnchantOH > 0) {
        uint32_t off = GetVisibleEnchantField(17);
        if (off) *(uint32_t*)(desc + off) = g_morphEnchantOH;
    }
}

// ================================================================
// Pattern scanning for dynamic offset resolution
// ================================================================
static bool PatternScan(DWORD start, DWORD size, const char* pattern, const char* mask, DWORD* result) {
    DWORD patternLen = (DWORD)strlen(mask);
    
    __try {
        for (DWORD i = 0; i < size - patternLen; i++) {
            bool found = true;
            for (DWORD j = 0; j < patternLen; j++) {
                if (mask[j] == 'x' && pattern[j] != *(char*)(start + i + j)) {
                    found = false;
                    break;
                }
            }
            if (found) {
                *result = start + i;
                return true;
            }
        }
    } __except(EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
    return false;
}

// Find the descriptor write instruction: mov [eax+edx*4], ecx
// Pattern: 89 0C 90 (mov [eax+edx*4], ecx) followed by 5D (pop ebp) and C2 08 00 (ret 8)
static DWORD FindDescriptorWriteHook(DWORD base) {
    // Search in .text section (typical range for code)
    DWORD searchStart = base + 0x1000;
    DWORD searchSize = 0x500000; // Search first ~5MB of code
    
    // Pattern: mov [eax+edx*4], ecx; pop ebp; ret 8
    const char pattern[] = "\x89\x0C\x90\x5D\xC2\x08\x00";
    const char mask[] = "xxxxxxx";
    
    DWORD addr = 0;
    DWORD currentPos = searchStart;
    
    // We might find multiple matches, look for the one in a function that
    // has the right context (descriptor write function)
    while (currentPos < searchStart + searchSize) {
        if (PatternScan(currentPos, searchStart + searchSize - currentPos, pattern, mask, &addr)) {
            // Verify this is in a valid function by checking for prologue nearby
            __try {
                bool validFunc = false;
                for (DWORD a = addr - 1; a > addr - 256 && a > base; a--) {
                    // Look for: push ebp; mov ebp, esp (55 8B EC)
                    if (*(BYTE*)a == 0x55 && *(BYTE*)(a+1) == 0x8B && *(BYTE*)(a+2) == 0xEC) {
                        validFunc = true;
                        break;
                    }
                }
                if (validFunc) {
                    Log("Found descriptor write pattern at 0x%08X", addr);
                    return addr;
                }
            } __except(EXCEPTION_EXECUTE_HANDLER) {}
            
            // Continue searching after this match
            currentPos = addr + 1;
        } else {
            break;
        }
    }
    
    return 0;
}

// ================================================================
// Mount Morph Hook — intercepts the game's descriptor write instruction
// ================================================================
// Hooks at Wow.exe base+0x343BAC: the `mov [eax+edx*4], ecx`
// instruction inside the descriptor write function.  When the game
// writes UNIT_FIELD_MOUNTDISPLAYID (field index 0x45) for the local
// player and we have a mount morph active, we substitute our desired
// displayID.  Because the game's own write path executes, its internal
// change notification fires naturally and the mount model reloads.
// This is the ONLY approach that triggers a visual mount model swap;
// writing to the descriptor memory directly does NOT cause a reload.
static DWORD g_playerDescBase = 0;   // player->descriptors, updated each tick
static bool  g_hookInstalled = false;
static BYTE  g_hookOrigBytes[6] = {0};
static DWORD g_hookAddr = 0;

// Bypass flag: when true, the hook skips its substitution logic.
// Used when WE call the descriptor-write function to force a live mount change.
static volatile bool g_hookBypass = false;

// Address of the game's descriptor-write function (the function that
// contains our hooked mov instruction).  Found by scanning backward
// from the hook address for a push-ebp/mov-ebp,esp prologue.
// Calling convention: __thiscall(CGObject* this, uint32_t fieldIndex, uint32_t value)
static DWORD g_setDescValueFunc = 0;
typedef void (__thiscall* SetDescValue_fn)(void* obj, uint32_t index, uint32_t value);

// Live mount update is now handled immediately in DoMorph (no state machine needed).

void __declspec(naked) MountDisplayHook()
{
    __asm
    {
        // When we call the function ourselves, skip substitution logic
        cmp byte ptr [g_hookBypass], 1
        je do_original

        // Safety: If morph is suspended, skip substitution
        cmp byte ptr [g_suspended], 1
        je do_original

        // Is this writing to UNIT_FIELD_MOUNTDISPLAYID (index 0x45)?
        cmp edx, 0x45
        jne do_original

        // Is this a dismount (writing 0)?
        cmp ecx, 0
        je do_original

        // Is this the local player's descriptor array?
        cmp eax, dword ptr [g_playerDescBase]
        jne do_original

        // --- SMART INTERVENTION: POINTER PROTECTION ---
        // Display IDs in 3.3.5a are always < 100,000.
        // Vehicle Seat and Transport pointers are always > 0x01000000.
        cmp ecx, 0x00FFFFFF
        ja do_original

        // Save the real mount displayID the game intended to write
        mov dword ptr [g_origMount], ecx

        // Do we have a mount morph active?
        cmp dword ptr [g_morphMount], 0
        je do_original

        // Substitute with our morphed mount displayID
        mov ecx, dword ptr [g_morphMount]

    do_original:
        mov [eax+edx*4], ecx   // Original instruction — write descriptor
        pop ebp                  // Original epilogue
        ret 8                    // Original return (cleans 2 dword args)
    }
}

static bool InstallMountHook()
{
    // Try multiple methods to get the WoW executable base address
    DWORD base = (DWORD)GetModuleHandleA("Wow.exe");
    if (!base) {
        base = (DWORD)GetModuleHandleA("WoW.exe");  // Try with capital W
    }
    if (!base) {
        base = (DWORD)GetModuleHandleA(NULL);  // Get main executable (whatever it's called)
    }
    if (!base) {
        Log("ERROR: Could not get WoW executable module handle");
        return false;
    }
    
    Log("WoW executable base address: 0x%08X", base);

    // Try hardcoded offset first (fastest for standard 3.3.5a 12340)
    g_hookAddr = base + 0x343BAC;
    bool useHardcoded = false;
    
    // Verify the hardcoded offset has the expected pattern
    __try {
        if (*(BYTE*)g_hookAddr == 0x89 && 
            *(BYTE*)(g_hookAddr+1) == 0x0C && 
            *(BYTE*)(g_hookAddr+2) == 0x90) {
            useHardcoded = true;
            Log("Using hardcoded offset 0x343BAC (pattern verified)");
        }
    } __except(EXCEPTION_EXECUTE_HANDLER) {}
    
    // If hardcoded offset doesn't match, scan for the pattern
    if (!useHardcoded) {
        Log("Hardcoded offset invalid, scanning for descriptor write pattern...");
        DWORD foundAddr = FindDescriptorWriteHook(base);
        if (foundAddr == 0) {
            Log("ERROR: Could not find descriptor write instruction pattern");
            Log("This may be an unsupported WoW client version");
            return false;
        }
        g_hookAddr = foundAddr;
        Log("Found descriptor write hook at 0x%08X (offset 0x%X)", g_hookAddr, g_hookAddr - base);
    }

    const int LEN = 6;

    // Verify the hook address is readable before attempting to hook
    __try {
        BYTE testRead = *(BYTE*)g_hookAddr;
        (void)testRead; // Suppress unused variable warning
    } __except(EXCEPTION_EXECUTE_HANDLER) {
        Log("ERROR: Hook address 0x%08X is not readable", g_hookAddr);
        return false;
    }

    // Save original bytes so we can unhook cleanly
    __try {
        memcpy(g_hookOrigBytes, (void*)g_hookAddr, LEN);
    } __except(EXCEPTION_EXECUTE_HANDLER) {
        Log("ERROR: Failed to read original bytes at 0x%08X", g_hookAddr);
        return false;
    }

    DWORD oldProt;
    if (!VirtualProtect((void*)g_hookAddr, LEN, PAGE_EXECUTE_READWRITE, &oldProt)) {
        DWORD err = GetLastError();
        Log("ERROR: VirtualProtect failed at 0x%08X (error code: %u)", g_hookAddr, err);
        return false;
    }

    __try {
        // NOP the region, then write JMP rel32
        memset((void*)g_hookAddr, 0x90, LEN);
        *(BYTE*)g_hookAddr = 0xE9;
        *(DWORD*)(g_hookAddr + 1) = (DWORD)&MountDisplayHook - g_hookAddr - 5;
    } __except(EXCEPTION_EXECUTE_HANDLER) {
        Log("ERROR: Exception while writing hook at 0x%08X", g_hookAddr);
        VirtualProtect((void*)g_hookAddr, LEN, oldProt, &oldProt);
        return false;
    }

    DWORD tmp;
    if (!VirtualProtect((void*)g_hookAddr, LEN, oldProt, &tmp)) {
        Log("WARNING: Failed to restore memory protection at 0x%08X", g_hookAddr);
        // Not fatal - hook is still installed
    }

    g_hookInstalled = true;
    Log("Mount hook installed at 0x%08X", g_hookAddr);

    // Find the start of the function containing our hook point.
    // Scan backward for the prologue: push ebp (0x55) / mov ebp, esp (0x8B EC)
    g_setDescValueFunc = 0;
    __try {
        for (DWORD a = g_hookAddr - 1; a > g_hookAddr - 256; a--) {
            if (*(BYTE*)a == 0x55 && *(BYTE*)(a+1) == 0x8B && *(BYTE*)(a+2) == 0xEC) {
                g_setDescValueFunc = a;
                break;
            }
        }
    } __except(EXCEPTION_EXECUTE_HANDLER) {
        Log("WARNING: Exception while scanning for function prologue");
    }
    
    if (g_setDescValueFunc) {
        Log("Descriptor write function found at 0x%08X", g_setDescValueFunc);
    } else {
        Log("WARNING: Could not find descriptor write function start");
    }

    return true;
}

static void UninstallMountHook()
{
    if (!g_hookInstalled || !g_hookAddr) return;
    DWORD oldProt;
    if (VirtualProtect((void*)g_hookAddr, 6, PAGE_EXECUTE_READWRITE, &oldProt)) {
        memcpy((void*)g_hookAddr, g_hookOrigBytes, 6);
        DWORD tmp;
        VirtualProtect((void*)g_hookAddr, 6, oldProt, &tmp);
    }
    g_hookInstalled = false;
    Log("Mount hook uninstalled");
}

// ================================================================
// Helper: Check if a display ID is a race character model
// Using verified working display IDs
// ================================================================
static bool IsRaceDisplayID(uint32_t displayId) {
    // Verified working race display IDs
    // Night Elf Female: 2222
    if (displayId == 2222) return true;
    // Troll Female: 4358
    if (displayId == 4358) return true;
    // Orc Male: 6785
    if (displayId == 6785) return true;
    // Dwarf Female: 13250
    if (displayId == 13250) return true;
    // Draenei Male: 17155
    if (displayId == 17155) return true;
    // Human: 19723-19724
    if (displayId >= 19723 && displayId <= 19724) return true;
    // Orc Female, Dwarf Male, Night Elf Male: 20316-20318
    if (displayId >= 20316 && displayId <= 20318) return true;
    // Troll Male: 20321
    if (displayId == 20321) return true;
    // Draenei Female: 20323
    if (displayId == 20323) return true;
    // Blood Elf: 20578-20579
    if (displayId >= 20578 && displayId <= 20579) return true;
    // Gnome: 20580-20581
    if (displayId >= 20580 && displayId <= 20581) return true;
    // Tauren: 20584-20585
    if (displayId >= 20584 && displayId <= 20585) return true;
    // Undead Female: 23112
    if (displayId == 23112) return true;
    // Undead Male: 28193
    if (displayId == 28193) return true;
    
    // Legacy naked base models (keep for compatibility)
    if (displayId >= 49 && displayId <= 60) return true;
    if (displayId >= 1563 && displayId <= 1564) return true;
    if (displayId >= 1478 && displayId <= 1479) return true;
    if (displayId >= 15475 && displayId <= 15476) return true;
    if (displayId >= 16125 && displayId <= 16126) return true;
    
    return false;
}

// ================================================================
// Apply all active morphs to descriptors
// Returns true if any descriptor was actually changed
// ================================================================
static bool ApplyMorphState(WowObject* player) {
    if (!player || !player->descriptors) return false;
    uint8_t* desc = (uint8_t*)player->descriptors;
    bool changed = false;

    if (g_morphDisplay > 0) {
        uint32_t current = *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID);
        if (current != g_morphDisplay) {
            // Use SimplyMorpher3's double-update technique for race morphs
            if (IsRaceDisplayID(g_morphDisplay)) {
                // Step 1: Dummy display ID
                *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = 621;
                // Step 2: Actual display ID
                *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = g_morphDisplay;
                
                // Refresh equipment slots
                for (int s = 1; s <= 19; s++) {
                    if (g_morphItems[s] == 0) {
                        uint32_t off = GetVisibleItemField(s);
                        if (off) {
                            uint32_t currentItem = *(uint32_t*)(desc + off);
                            if (currentItem > 0) {
                                *(uint32_t*)(desc + off) = currentItem;
                            }
                        }
                    }
                }
            } else {
                // Non-race morph: simple write
                *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = g_morphDisplay;
            }
            changed = true;
        }
    }

    // Mount display is NOT handled here — it's handled by the assembly hook
    // (MountDisplayHook) which intercepts the game's own descriptor write

    if (g_morphScale > 0.0f) {
        float current = *(float*)(desc + 0x10);
        if (current < g_morphScale - 0.001f || current > g_morphScale + 0.001f) {
            *(float*)(desc + 0x10) = g_morphScale;
            changed = true;
        }
    }

    if (g_morphTitle > 0) {
        uint32_t current = *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE);
        if (current != g_morphTitle) {
            *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE) = g_morphTitle;
            changed = true;
        }
        // Force title to be known
        if (!IsTitleKnown(player, g_morphTitle)) {
            SetTitleKnown(player, g_morphTitle, true);
            changed = true;
        }
    }

    for (int s = 1; s <= 19; s++) {
        if (g_morphItems[s] > 0) {
            uint32_t off = GetVisibleItemField(s);
            if (off) {
                // HIDDEN_SENTINEL means "write 0" (hide the slot)
                uint32_t target = (g_morphItems[s] == HIDDEN_SENTINEL) ? 0 : g_morphItems[s];
                uint32_t current = *(uint32_t*)(desc + off);
                if (current != target) {
                    *(uint32_t*)(desc + off) = target;
                    changed = true;
                }
            }
        }
    }

    return changed;
}

// ================================================================
// Process a single command from the addon
// ================================================================
static bool DoMorph(const char* cmd, WowObject* player) {
    if (!player) { Log("No player object"); return false; }
    SaveOriginals(player);

    uint8_t* desc = (uint8_t*)player->descriptors;
    bool update = false;

    if (strncmp(cmd, "MORPH:", 6) == 0) {
        uint32_t id = (uint32_t)atoi(cmd + 6);
        if (id > 0) {
            // RACE MORPH FIX: SimplyMorpher3's exact technique
            // Key insight: UpdateDisplayInfo must be called TWICE with specific setup
            
            // Step 1: Write dummy display ID (621) and call UpdateDisplayInfo
            *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = 621;
            __try {
                // Call with parameter 0 (SimplyMorpher3 pushes 0)
                CGUnit_UpdateDisplayInfo(player, 0);
            } __except(EXCEPTION_EXECUTE_HANDLER) {
                Log("UpdateDisplayInfo exception (dummy)");
            }
            
            // Step 2: Write actual display ID and call UpdateDisplayInfo again
            *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = id;
            g_morphDisplay = id;
            
            __try {
                // Call with parameter 0 again (SimplyMorpher3 pushes 0 both times)
                CGUnit_UpdateDisplayInfo(player, 0);
            } __except(EXCEPTION_EXECUTE_HANDLER) {
                Log("UpdateDisplayInfo exception (actual)");
            }
            
            // For race morphs, also refresh equipment slots
            if (IsRaceDisplayID(id)) {
                for (int s = 1; s <= 19; s++) {
                    if (g_morphItems[s] == 0) {
                        uint32_t off = GetVisibleItemField(s);
                        if (off) {
                            uint32_t currentItem = *(uint32_t*)(desc + off);
                            if (currentItem > 0) {
                                *(uint32_t*)(desc + off) = currentItem;
                            }
                        }
                    }
                }
                Log("Race morph applied displayId=%u (SimplyMorpher3 technique)", id);
            } else {
                Log("Morphed displayId=%u (SimplyMorpher3 technique)", id);
            }
            
            update = false; // We already called UpdateDisplayInfo, don't call it again
        } else if (id == 0) {
            // MORPH:0 = reset character morph only (preserve item morphs)
            // Restore native display ID
            uint32_t nativeDisplay = *(uint32_t*)(desc + UNIT_FIELD_NATIVEDISPLAYID);
            *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = nativeDisplay;
            g_morphDisplay = 0;
            update = true;
            Log("Character morph reset (restored native display=%u)", nativeDisplay);
        }
    }
    else if (strncmp(cmd, "SCALE:", 6) == 0) {
        float scale = (float)atof(cmd + 6);
        if (scale > 0.05f && scale <= 20.0f) {
            *(float*)(desc + 0x10) = scale;
            g_morphScale = scale;
            update = true;
            Log("Scaled to %.2f", scale);
        }
    }
    else if (strncmp(cmd, "ITEM:", 5) == 0) {
        int slot = 0; uint32_t itemId = 0;
        sscanf_s(cmd + 5, "%d:%u", &slot, &itemId);
        if (slot >= 1 && slot <= 19) {
            uint32_t off = GetVisibleItemField(slot);
            if (off) {
                *(uint32_t*)(desc + off) = itemId;
                // Use HIDDEN_SENTINEL for itemId 0 so the slot stays
                // "actively morphed" — prevents RefreshOriginals from
                // corrupting g_origItems and lets MorphGuard re-stamp.
                g_morphItems[slot] = (itemId == 0) ? HIDDEN_SENTINEL : itemId;
                update = true;
                Log("Set slot %d = item %u%s", slot, itemId, itemId == 0 ? " (hidden)" : "");
                // Weapon slots need extra refresh ticks because
                // UpdateDisplayInfo may overwrite weapon descriptors
                if (slot >= 16 && slot <= 18) {
                    g_weaponRefreshTicks = 5;
                }
            }
        }
    }
    else if (strncmp(cmd, "MOUNT_MORPH:", 12) == 0) {
        uint32_t id = (uint32_t)atoi(cmd + 12);
        g_morphMount = id;
        Log("Mount morph set displayId=%u (will apply on next mount)", id);
        // The assembly hook (MountDisplayHook) intercepts descriptor writes
        // for UNIT_FIELD_MOUNTDISPLAYID and substitutes our value automatically.
        // No live swap needed — it takes effect on the next mount event.
    }
    else if (strncmp(cmd, "MOUNT_RESET", 11) == 0) {
        Log("Mount morph reset (was=%u)", g_morphMount);
        g_morphMount = 0;
        // The hook will stop substituting on next mount event.
        // Current mount appearance stays until dismount/remount.
    }
    else if (strncmp(cmd, "PET_MORPH:", 10) == 0) {
        g_morphPet = (uint32_t)atoi(cmd + 10);
        Log("Pet morph displayId=%u", g_morphPet);
        // Pet morph is applied in MorphGuard via critter GUID lookup
    }
    else if (strncmp(cmd, "PET_RESET", 9) == 0) {
        // Restore original critter display before clearing state
        if (g_origPetDisplay > 0) {
            __try {
                uint32_t lo = *(uint32_t*)(desc + UNIT_FIELD_CRITTER);
                uint32_t hi = *(uint32_t*)(desc + UNIT_FIELD_CRITTER + 4);
                uint64_t critterGuid = ((uint64_t)hi << 32) | lo;
                if (critterGuid != 0) {
                    WowObject* critter = (WowObject*)GetObjectPtr(critterGuid, TYPEMASK_UNIT, "", 0);
                    if (critter && critter->descriptors) {
                        *(uint32_t*)((uint8_t*)critter->descriptors + UNIT_FIELD_DISPLAYID) = g_origPetDisplay;
                        __try { CGUnit_UpdateDisplayInfo(critter, 1); }
                        __except(EXCEPTION_EXECUTE_HANDLER) {}
                    }
                }
            } __except(EXCEPTION_EXECUTE_HANDLER) {}
        }
        g_morphPet = 0;
        g_origPetDisplay = 0;
        Log("Pet morph reset");
    }
    else if (strncmp(cmd, "HPET_MORPH:", 11) == 0) {
        g_morphHPet = (uint32_t)atoi(cmd + 11);
        Log("Hunter pet morph displayId=%u", g_morphHPet);
        // Applied in MorphGuard via UNIT_FIELD_SUMMON GUID lookup
    }
    else if (strncmp(cmd, "HPET_SCALE:", 11) == 0) {
        float scale = (float)atof(cmd + 11);
        if (scale > 0.05f && scale <= 20.0f) {
            g_morphHPetScale = scale;
            // Apply immediately if pet exists (SUMMON or guardian)
            bool applied = false;
            __try {
                uint32_t lo = *(uint32_t*)(desc + UNIT_FIELD_SUMMON);
                uint32_t hi = *(uint32_t*)(desc + UNIT_FIELD_SUMMON + 4);
                uint64_t petGuid = ((uint64_t)hi << 32) | lo;
                if (petGuid != 0) {
                    WowObject* pet = (WowObject*)GetObjectPtr(petGuid, TYPEMASK_UNIT, "", 0);
                    if (pet && pet->descriptors) {
                        *(float*)((uint8_t*)pet->descriptors + 0x10) = scale;
                        applied = true;
                    }
                }
            } __except(EXCEPTION_EXECUTE_HANDLER) {}
            if (!applied) {
                struct ScaleCtx { float s; };
                ScaleCtx sctx = { scale };
                uint64_t pGuid = GetPlayerGuid();
                if (pGuid != 0) {
                    ForEachPlayerGuardian(pGuid, [](WowObject* unit, uint8_t* d, void* vctx) {
                        ScaleCtx* c = (ScaleCtx*)vctx;
                        *(float*)(d + 0x10) = c->s;
                    }, &sctx);
                }
            }
            Log("Hunter pet scaled to %.2f", scale);
        }
    }
    else if (strncmp(cmd, "HPET_RESET", 10) == 0) {
        // Restore original hunter pet display before clearing state
        uint32_t origDisp = g_origHPetDisplay;
        if (origDisp > 0) {
            bool restored = false;
            __try {
                uint32_t lo = *(uint32_t*)(desc + UNIT_FIELD_SUMMON);
                uint32_t hi = *(uint32_t*)(desc + UNIT_FIELD_SUMMON + 4);
                uint64_t petGuid = ((uint64_t)hi << 32) | lo;
                if (petGuid != 0) {
                    WowObject* pet = (WowObject*)GetObjectPtr(petGuid, TYPEMASK_UNIT, "", 0);
                    if (pet && pet->descriptors) {
                        *(uint32_t*)((uint8_t*)pet->descriptors + UNIT_FIELD_DISPLAYID) = origDisp;
                        __try { CGUnit_UpdateDisplayInfo(pet, 1); }
                        __except(EXCEPTION_EXECUTE_HANDLER) {}
                        restored = true;
                    }
                }
            } __except(EXCEPTION_EXECUTE_HANDLER) {}
            // Also restore guardians (DK ghoul, etc.)
            if (!restored) {
                struct ResetCtx { uint32_t disp; };
                ResetCtx rctx = { origDisp };
                uint64_t pGuid = GetPlayerGuid();
                if (pGuid != 0) {
                    ForEachPlayerGuardian(pGuid, [](WowObject* unit, uint8_t* d, void* vctx) {
                        ResetCtx* c = (ResetCtx*)vctx;
                        *(uint32_t*)(d + UNIT_FIELD_DISPLAYID) = c->disp;
                        __try { CGUnit_UpdateDisplayInfo(unit, 1); }
                        __except(EXCEPTION_EXECUTE_HANDLER) {}
                    }, &rctx);
                }
            }
        }
        g_morphHPet = 0;
        g_origHPetDisplay = 0;
        g_morphHPetScale = 0.0f;
        Log("Hunter pet morph reset");
    }
    else if (strncmp(cmd, "ENCHANT_MH:", 11) == 0) {
        uint32_t enchantId = (uint32_t)atoi(cmd + 11);
        // Always save the current enchant as original before morphing (unless we already have one)
        if (g_morphEnchantMH == 0 && g_origEnchantMH == 0) {
            g_origEnchantMH = ReadVisibleEnchant(player, 16);
        }
        g_morphEnchantMH = enchantId;
        if (WriteVisibleEnchant(player, 16, enchantId)) update = true;
        g_weaponRefreshTicks = 5;
        Log("Enchant MH set id=%u (orig=%u)", enchantId, g_origEnchantMH);
    }
    else if (strncmp(cmd, "ENCHANT_OH:", 11) == 0) {
        uint32_t enchantId = (uint32_t)atoi(cmd + 11);
        // Always save the current enchant as original before morphing (unless we already have one)
        if (g_morphEnchantOH == 0 && g_origEnchantOH == 0) {
            g_origEnchantOH = ReadVisibleEnchant(player, 17);
        }
        g_morphEnchantOH = enchantId;
        if (WriteVisibleEnchant(player, 17, enchantId)) update = true;
        g_weaponRefreshTicks = 5;
        Log("Enchant OH set id=%u (orig=%u)", enchantId, g_origEnchantOH);
    }
    else if (strncmp(cmd, "ENCHANT_RESET_MH", 16) == 0) {
        // Read current real enchant before resetting (in case weapon was swapped)
        uint32_t currentRealEnchant = ReadVisibleEnchant(player, 16);
        
        if (g_morphEnchantMH > 0) {
            // If we have a saved original, restore it
            if (g_origEnchantMH > 0) {
                WriteVisibleEnchant(player, 16, g_origEnchantMH);
            } else {
                // No saved original, use current real enchant
                WriteVisibleEnchant(player, 16, currentRealEnchant);
            }
        }
        g_morphEnchantMH = 0;
        g_origEnchantMH = 0;
        g_weaponRefreshTicks = 5;
        update = true;
        Log("Enchant MH morph reset (restored to %u)", currentRealEnchant);
    }
    else if (strncmp(cmd, "ENCHANT_RESET_OH", 16) == 0) {
        // Read current real enchant before resetting (in case weapon was swapped)
        uint32_t currentRealEnchant = ReadVisibleEnchant(player, 17);
        
        if (g_morphEnchantOH > 0) {
            // If we have a saved original, restore it
            if (g_origEnchantOH > 0) {
                WriteVisibleEnchant(player, 17, g_origEnchantOH);
            } else {
                // No saved original, use current real enchant
                WriteVisibleEnchant(player, 17, currentRealEnchant);
            }
        }
        g_morphEnchantOH = 0;
        g_origEnchantOH = 0;
        g_weaponRefreshTicks = 5;
        update = true;
        Log("Enchant OH morph reset (restored to %u)", currentRealEnchant);
    }
    else if (strncmp(cmd, "ENCHANT_RESET", 13) == 0) {
        // Restore original enchant visuals
        if (g_morphEnchantMH > 0) {
            WriteVisibleEnchant(player, 16, g_origEnchantMH);
        }
        if (g_morphEnchantOH > 0) {
            WriteVisibleEnchant(player, 17, g_origEnchantOH);
        }
        g_morphEnchantMH = 0;
        g_morphEnchantOH = 0;
        g_origEnchantMH = 0;
        g_origEnchantOH = 0;
        g_weaponRefreshTicks = 5;
        update = true;
        Log("Enchant morph reset");
    }
    else if (strncmp(cmd, "TITLE:", 6) == 0) {
        uint32_t titleId = (uint32_t)atoi(cmd + 6);
        if (titleId == 0) {
            return false;
        }
        // If we are switching from a previously morphed title, restore its known state
        if (g_morphTitle > 0 && g_morphTitle != titleId) {
            SetTitleKnown(player, g_morphTitle, g_origTitleWasKnown);
        }
        // Always save the current title as original before morphing
        if (g_origTitle == 0) {
            g_origTitle = *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE);
        }
        
        // Capture known state of NEW title before we force it
        if (g_morphTitle != titleId) {
            g_origTitleWasKnown = IsTitleKnown(player, titleId);
        }
        
        g_morphTitle = titleId;
        *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE) = titleId;
        // Force known bit immediately
        SetTitleKnown(player, titleId, true);
        {
            char luaCmd[128];
            sprintf_s(luaCmd, "if SetCurrentTitle then SetCurrentTitle(%u) end", titleId);
            FrameScript_Execute(luaCmd, "Transmorpher", 0);
            FrameScript_Execute("if PaperDollTitlesPane_Update then PaperDollTitlesPane_Update() end", "Transmorpher", 0);
        }
        
        update = true;
    }
    else if (strncmp(cmd, "TITLE_RESET", 11) == 0) {
        // Restore original title
        if (g_morphTitle > 0) {
            *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE) = g_origTitle;
            // Restore known bit
            SetTitleKnown(player, g_morphTitle, g_origTitleWasKnown);
        }
        FrameScript_Execute("if SetCurrentTitle then SetCurrentTitle(0) end", "Transmorpher", 0);
        FrameScript_Execute("if PaperDollTitlesPane_Update then PaperDollTitlesPane_Update() end", "Transmorpher", 0);
        g_morphTitle = 0;
        g_origTitle = 0;
        g_origTitleWasKnown = false;
        update = true;
    }
    else if (strncmp(cmd, "SUSPEND", 7) == 0) {
        // Addon signals: model-changing form active, stop overriding
        g_suspended = true;
        Log("Morph suspended (shapeshift/proc)");
        return false;
    }
    else if (strncmp(cmd, "RESUME", 6) == 0) {
        // Addon signals: form ended, restore morphs once
        g_suspended = false;
        Log("Morph resumed — restoring");
        {
            bool changed = false;
            if (g_hasMorph) {
                changed = ApplyMorphState(player);
            }
            // If no display morph is active, ensure the native display is
            // restored.  This fixes cases where a shapeshift form or DBW
            // proc left a stale display (e.g. druid leaving form after a
            // DBW proc that changed the model).
            if (g_morphDisplay == 0) {
                uint32_t nativeDisp = *(uint32_t*)(desc + UNIT_FIELD_NATIVEDISPLAYID);
                uint32_t currentDisp = *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID);
                if (currentDisp != nativeDisp) {
                    *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = nativeDisp;
                    changed = true;
                }
            }
            if (changed) {
                __try { CGUnit_UpdateDisplayInfo(player, 1); }
                __except(EXCEPTION_EXECUTE_HANDLER) {}
                ReStampWeapons(player);
                g_weaponRefreshTicks = 5;
            }
        }
        return false; // Already handled visual update
    }
    else if (strncmp(cmd, "RESET:ALL", 9) == 0) {
        // Restore descriptors only if we have valid originals for THIS character
        if (g_saved) {
            // Use NATIVEDISPLAYID directly — always the correct base model,
            // never a shapeshift form or DBW proc race.
            uint32_t nativeDisplay = *(uint32_t*)(desc + UNIT_FIELD_NATIVEDISPLAYID);
            *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = nativeDisplay;
            *(float*)(desc + 0x10) = g_origScale;
            for (int s = 1; s <= 19; s++) {
                uint32_t off = GetVisibleItemField(s);
                if (off) *(uint32_t*)(desc + off) = g_origItems[s];
            }
            // Reset mount display
            if (g_morphMount > 0) {
                uint32_t curMount = *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID);
                if (curMount > 0) *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID) = g_origMount;
            }
            // Restore pet (critter) original display if morphed
            if (g_origPetDisplay > 0) {
                __try {
                    uint32_t plo = *(uint32_t*)(desc + UNIT_FIELD_CRITTER);
                    uint32_t phi = *(uint32_t*)(desc + UNIT_FIELD_CRITTER + 4);
                    uint64_t cGuid = ((uint64_t)phi << 32) | plo;
                    if (cGuid != 0) {
                        WowObject* critter = (WowObject*)GetObjectPtr(cGuid, TYPEMASK_UNIT, "", 0);
                        if (critter && critter->descriptors) {
                            *(uint32_t*)((uint8_t*)critter->descriptors + UNIT_FIELD_DISPLAYID) = g_origPetDisplay;
                            __try { CGUnit_UpdateDisplayInfo(critter, 1); }
                            __except(EXCEPTION_EXECUTE_HANDLER) {}
                        }
                    }
                } __except(EXCEPTION_EXECUTE_HANDLER) {}
            }
            // Restore hunter pet original display if morphed
            if (g_origHPetDisplay > 0) {
                __try {
                    uint32_t hlo = *(uint32_t*)(desc + UNIT_FIELD_SUMMON);
                    uint32_t hhi = *(uint32_t*)(desc + UNIT_FIELD_SUMMON + 4);
                    uint64_t hGuid = ((uint64_t)hhi << 32) | hlo;
                    if (hGuid != 0) {
                        WowObject* hpet = (WowObject*)GetObjectPtr(hGuid, TYPEMASK_UNIT, "", 0);
                        if (hpet && hpet->descriptors) {
                            *(uint32_t*)((uint8_t*)hpet->descriptors + UNIT_FIELD_DISPLAYID) = g_origHPetDisplay;
                            __try { CGUnit_UpdateDisplayInfo(hpet, 1); }
                            __except(EXCEPTION_EXECUTE_HANDLER) {}
                        }
                    }
                } __except(EXCEPTION_EXECUTE_HANDLER) {}
            }
            // Restore enchant visuals via PLAYER_VISIBLE_ITEM
            if (g_morphEnchantMH > 0) {
                WriteVisibleEnchant(player, 16, g_origEnchantMH);
            }
            if (g_morphEnchantOH > 0) {
                WriteVisibleEnchant(player, 17, g_origEnchantOH);
            }
            // Restore title
            if (g_morphTitle > 0) {
                *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE) = g_origTitle;
                SetTitleKnown(player, g_morphTitle, g_origTitleWasKnown);
            }
        }
        // ALWAYS clear all morph state — even if g_saved was false.
        // On character switch, the DLL must re-capture originals via SaveOriginals.
        g_morphDisplay = 0;
        g_morphScale = 0.0f;
        g_morphMount = 0;
        g_morphPet = 0;
        g_morphHPet = 0;
        g_morphHPetScale = 0.0f;
        g_morphEnchantMH = 0;
        g_morphEnchantOH = 0;
        g_morphTitle = 0;
        g_origPetDisplay = 0;
        g_origHPetDisplay = 0;
        g_origEnchantMH = 0;
        g_origEnchantOH = 0;
        g_origTitle = 0;
        g_origTitleWasKnown = false;
        g_origMount = 0;
        g_origDisplay = 0;
        g_origScale = 1.0f;
        memset(g_origItems, 0, sizeof(g_origItems));
        g_weaponRefreshTicks = 0;
        memset(g_morphItems, 0, sizeof(g_morphItems));
        g_hasMorph = false;
        g_suspended = false;
        g_saved = false;
        update = true;
        Log("Reset all");
    }
    else if (strncmp(cmd, "TIME:", 5) == 0) {
        float val = (float)atof(cmd + 5);
        if (val < 0.0f) {
            // Negative value = reset (uninstall hook)
            UninstallTimeHook();
            Log("Time reset (hook uninstalled)");
        } else {
            g_timeOfDay = val;
            // Clamp to 0-1
            if (g_timeOfDay < 0.0f) g_timeOfDay = 0.0f;
            if (g_timeOfDay > 1.0f) g_timeOfDay = 1.0f;
            
            // Ensure hook is installed
            if (!g_timeHookInstalled) {
                InstallTimeHook();
            }
            
            // Write directly to the storage address
            __try {
                *(float*)TIME_VAR_ADDR = g_timeOfDay;
                Log("Time set to %.3f (at 0x%08X)", g_timeOfDay, TIME_VAR_ADDR);
            } __except(EXCEPTION_EXECUTE_HANDLER) {
                Log("ERROR: Failed to write time to 0x%08X", TIME_VAR_ADDR);
            }
        }
    }
    else if (strncmp(cmd, "RESET:", 6) == 0 && g_saved) {
        int slot = atoi(cmd + 6);
        if (slot >= 1 && slot <= 19) {
            uint32_t off = GetVisibleItemField(slot);
            if (off) {
                *(uint32_t*)(desc + off) = g_origItems[slot];
                g_morphItems[slot] = 0;
                update = true;
                Log("Reset slot %d", slot);
            }
        }
    }

    UpdateHasMorph();
    return update;
}

// ================================================================
// Morph Guard — automatic single-shot restoration
// Runs every tick. Detects when the game has overwritten our morphed
// descriptors (shapeshift end, trinket proc end, equipment swap,
// weapon sheathe/unsheathe) and restores them ONCE.
// No loops, no burst frames, no repeated attempts.
// ================================================================
static void MorphGuard(WowObject* player) {
    if (!player || !player->descriptors) return;
    if (!g_hasMorph) return;
    if (g_suspended) return;

    uint8_t* desc = (uint8_t*)player->descriptors;
    bool needsRestore = false;

    // Check display ID
    if (g_morphDisplay > 0) {
        uint32_t cur = *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID);
        if (cur != g_morphDisplay) {
            needsRestore = true;
        }
    }

    // Check item slots (weapons, armor — all persistent)
    if (!needsRestore) {
        for (int s = 1; s <= 19; s++) {
            if (g_morphItems[s] > 0) {
                uint32_t off = GetVisibleItemField(s);
                if (off) {
                    uint32_t target = (g_morphItems[s] == HIDDEN_SENTINEL) ? 0 : g_morphItems[s];
                    uint32_t cur = *(uint32_t*)(desc + off);
                    if (cur != target) {
                        needsRestore = true;
                        break;
                    }
                }
            }
        }
    }

    // Mount display is handled by the assembly hook (MountDisplayHook)

    // Check scale
    if (!needsRestore && g_morphScale > 0.0f) {
        float cur = *(float*)(desc + 0x10);
        if (cur < g_morphScale - 0.001f || cur > g_morphScale + 0.001f) {
            needsRestore = true;
        }
    }

    // Single-shot restore: write all morph values back & update once
    if (needsRestore) {
        bool changed = ApplyMorphState(player);
        if (changed) {
            __try {
                CGUnit_UpdateDisplayInfo(player, 1);
            } __except(EXCEPTION_EXECUTE_HANDLER) {
                Log("Guard: UpdateDisplayInfo exception");
            }
            // Re-stamp weapons immediately — UpdateDisplayInfo may have
            // overwritten weapon descriptors from real inventory
            ReStampWeapons(player);
            Log("Guard: Restored morph (single-shot)");
        }
    }

    // --- Pet (critter) morph guard ---
    // The player's critter GUID is at UNIT_FIELD_CRITTER (2 x uint32 = GUID)
    // We look up that object and override its DISPLAYID
    if (g_morphPet > 0) {
        __try {
            uint32_t lo = *(uint32_t*)(desc + UNIT_FIELD_CRITTER);
            uint32_t hi = *(uint32_t*)(desc + UNIT_FIELD_CRITTER + 4);
            uint64_t critterGuid = ((uint64_t)hi << 32) | lo;
            if (critterGuid != 0) {
                WowObject* critter = (WowObject*)GetObjectPtr(critterGuid, TYPEMASK_UNIT, "", 0);
                if (critter && critter->descriptors) {
                    uint8_t* cDesc = (uint8_t*)critter->descriptors;
                    uint32_t curDisp = *(uint32_t*)(cDesc + UNIT_FIELD_DISPLAYID);
                    if (curDisp != g_morphPet) {
                        // Save original display before first override
                        if (g_origPetDisplay == 0) g_origPetDisplay = curDisp;
                        *(uint32_t*)(cDesc + UNIT_FIELD_DISPLAYID) = g_morphPet;
                        __try { CGUnit_UpdateDisplayInfo(critter, 1); }
                        __except(EXCEPTION_EXECUTE_HANDLER) {}
                        Log("Guard: Pet morph applied (display=%u, orig=%u)", g_morphPet, g_origPetDisplay);
                    }
                }
            }
        } __except(EXCEPTION_EXECUTE_HANDLER) {
            Log("Guard: Pet morph exception");
        }
    }

    // --- Combat pet (summoned unit + guardians) morph guard ---
    // First check UNIT_FIELD_SUMMON (controlled pets: hunter, warlock, mage, DK permanent ghoul)
    // If empty, scan all objects for guardians created/summoned by the player
    // (DK temporary ghoul from Raise Dead, Army of the Dead, etc.)
    if (g_morphHPet > 0 || g_morphHPetScale > 0.0f) {
        bool found = false;
        // Try UNIT_FIELD_SUMMON first (fast path)
        __try {
            uint32_t lo = *(uint32_t*)(desc + UNIT_FIELD_SUMMON);
            uint32_t hi = *(uint32_t*)(desc + UNIT_FIELD_SUMMON + 4);
            uint64_t petGuid = ((uint64_t)hi << 32) | lo;
            if (petGuid != 0) {
                WowObject* pet = (WowObject*)GetObjectPtr(petGuid, TYPEMASK_UNIT, "", 0);
                if (pet && pet->descriptors) {
                    uint8_t* pDesc = (uint8_t*)pet->descriptors;
                    if (g_morphHPet > 0) {
                        uint32_t curDisp = *(uint32_t*)(pDesc + UNIT_FIELD_DISPLAYID);
                        if (curDisp != g_morphHPet) {
                            if (g_origHPetDisplay == 0) g_origHPetDisplay = curDisp;
                            *(uint32_t*)(pDesc + UNIT_FIELD_DISPLAYID) = g_morphHPet;
                            __try { CGUnit_UpdateDisplayInfo(pet, 1); }
                            __except(EXCEPTION_EXECUTE_HANDLER) {}
                            Log("Guard: Combat pet morph applied via SUMMON (display=%u)", g_morphHPet);
                        }
                    }
                    if (g_morphHPetScale > 0.0f) {
                        float curScale = *(float*)(pDesc + 0x10);
                        if (curScale < g_morphHPetScale - 0.01f || curScale > g_morphHPetScale + 0.01f) {
                            *(float*)(pDesc + 0x10) = g_morphHPetScale;
                        }
                    }
                    found = true;
                }
            }
        } __except(EXCEPTION_EXECUTE_HANDLER) {}

        // Fallback: scan object manager for guardians (DK ghoul, Army of the Dead, etc.)
        if (!found) {
            struct GuardianCtx {
                uint32_t morphDisplay;
                uint32_t* origDisplay;
                float morphScale;
            };
            GuardianCtx ctx = { g_morphHPet, &g_origHPetDisplay, g_morphHPetScale };
            uint64_t pGuid = GetPlayerGuid();
            if (pGuid != 0) {
                ForEachPlayerGuardian(pGuid, [](WowObject* unit, uint8_t* d, void* vctx) {
                    GuardianCtx* c = (GuardianCtx*)vctx;
                    if (c->morphDisplay > 0) {
                        uint32_t curDisp = *(uint32_t*)(d + UNIT_FIELD_DISPLAYID);
                        if (curDisp != c->morphDisplay) {
                            if (*c->origDisplay == 0) *c->origDisplay = curDisp;
                            *(uint32_t*)(d + UNIT_FIELD_DISPLAYID) = c->morphDisplay;
                            __try { CGUnit_UpdateDisplayInfo(unit, 1); }
                            __except(EXCEPTION_EXECUTE_HANDLER) {}
                        }
                    }
                    if (c->morphScale > 0.0f) {
                        float curScale = *(float*)(d + 0x10);
                        if (curScale < c->morphScale - 0.01f || curScale > c->morphScale + 0.01f) {
                            *(float*)(d + 0x10) = c->morphScale;
                        }
                    }
                }, &ctx);
            }
        }
    }

    // --- Enchant morph guard ---
    // Simple guard: just reapply if game reset the enchant
    if (g_morphEnchantMH > 0) {
        __try {
            uint32_t curEnchant = ReadVisibleEnchant(player, 16);
            if (curEnchant != g_morphEnchantMH) {
                WriteVisibleEnchant(player, 16, g_morphEnchantMH);
            }
        } __except(EXCEPTION_EXECUTE_HANDLER) {}
    }
    if (g_morphEnchantOH > 0) {
        __try {
            uint32_t curEnchant = ReadVisibleEnchant(player, 17);
            if (curEnchant != g_morphEnchantOH) {
                WriteVisibleEnchant(player, 17, g_morphEnchantOH);
            }
        } __except(EXCEPTION_EXECUTE_HANDLER) {}
    }

    // --- Title morph guard ---
    if (g_morphTitle > 0) {
        __try {
            uint32_t curTitle = *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE);
            if (curTitle != g_morphTitle) {
                *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE) = g_morphTitle;
            }
            // Enforce known bit
            if (!IsTitleKnown(player, g_morphTitle)) {
                SetTitleKnown(player, g_morphTitle, true);
            }
        } __except(EXCEPTION_EXECUTE_HANDLER) {}
    }
    
    // Pet/mount morphs are persistent and don't need guard logic
}

// ================================================================
// Timer callback — runs on WoW's main thread every 20ms
// ================================================================
static std::atomic<bool> g_running{true};
static WNDPROC g_origWndProc = nullptr;
static HWND    g_wowHwnd = nullptr;
static UINT_PTR MORPH_TIMER_ID = 0xDEAD;

static VOID CALLBACK MorphTimerProc(HWND hwnd, UINT uMsg, UINT_PTR idEvent, DWORD dwTime) {
    // Safety check: if DLL is shutting down, exit immediately
    if (!g_running) return;
    if (!g_wowHwnd) return;
    
    __try {
        WowObject* player = GetPlayer();

        // --- Character change detection ---
        // If the local player GUID changed (character switch / relog),
        // immediately wipe ALL morph state so MorphGuard cannot apply
        // stale morphs from the previous character to the new one.
        {
            uint64_t currentGuid = GetPlayerGuid();
            if (currentGuid != 0 && currentGuid != g_lastPlayerGuid) {
                if (g_lastPlayerGuid != 0) {
                    Log("Character change detected (0x%llX -> 0x%llX), clearing all state",
                        g_lastPlayerGuid, currentGuid);
                    g_morphDisplay = 0;
                    g_morphScale = 0.0f;
                    g_morphMount = 0;
                    g_morphPet = 0;
                    g_morphHPet = 0;
                    g_morphHPetScale = 0.0f;
                    g_morphEnchantMH = 0;
                    g_morphEnchantOH = 0;
                    g_morphTitle = 0;
                    g_origPetDisplay = 0;
                    g_origHPetDisplay = 0;
                    g_origEnchantMH = 0;
                    g_origEnchantOH = 0;
                    g_origTitle = 0;
                    g_origTitleWasKnown = false;
                    g_lastWeaponMHGuid = 0;
                    g_lastWeaponOHGuid = 0;
                    g_origMount = 0;
                    g_origDisplay = 0;
                    g_origScale = 1.0f;
                    memset(g_origItems, 0, sizeof(g_origItems));
                    g_weaponRefreshTicks = 0;
                    memset(g_morphItems, 0, sizeof(g_morphItems));
                    g_hasMorph = false;
                    g_suspended = false;
                    g_saved = false;
                }
                g_lastPlayerGuid = currentGuid;
            }
        }

        // Keep the hook's player descriptor pointer up to date
        if (player && player->descriptors)
            g_playerDescBase = (DWORD)(uintptr_t)player->descriptors;

        // --- Phase 1: Process addon commands from Lua global ---
        void* L = GetLuaState();
        if (L) {
            wow_lua_getfield(L, LUA_GLOBALSINDEX, "TRANSMORPHER_CMD");
            size_t len = 0;
            const char* val = wow_lua_tolstring(L, -1, &len);
            wow_lua_settop(L, -2);

            if (val && len > 0) {
                char buffer[4096];
                strncpy_s(buffer, sizeof(buffer), val, _TRUNCATE);
                FrameScript_Execute("TRANSMORPHER_CMD = ''", "Transmorpher", 0);

                char* next_token = nullptr;
                char* token = strtok_s(buffer, "|", &next_token);
                bool needsVisualUpdate = false;

                while (token) {
                    if (DoMorph(token, player)) {
                        needsVisualUpdate = true;
                    }
                    token = strtok_s(nullptr, "|", &next_token);
                }

                if (needsVisualUpdate && player) {
                    __try {
                        CGUnit_UpdateDisplayInfo(player, 1);
                    } __except(EXCEPTION_EXECUTE_HANDLER) {
                        Log("UpdateDisplayInfo exception");
                    }
                    // Re-stamp weapons after UpdateDisplayInfo
                    ReStampWeapons(player);
                }
            }
        }

        // --- Phase 2: Morph Guard — detect & restore external changes ---
        if (player) {
            SaveOriginals(player);
            RefreshOriginals(player);
            MorphGuard(player);
        }

        // --- Phase 3: Weapon refresh — extra update ticks after weapon morphs ---
        // Forces the render pipeline to pick up weapon changes that
        // UpdateDisplayInfo may have clobbered.
        if (player && g_weaponRefreshTicks > 0 && !g_suspended) {
            g_weaponRefreshTicks--;
            ApplyMorphState(player);
            __try {
                CGUnit_UpdateDisplayInfo(player, 1);
            } __except(EXCEPTION_EXECUTE_HANDLER) {}
            ReStampWeapons(player);
        }

        // Live mount model swap is now handled immediately in DoMorph
        // (same approach as MOUNT_RESET: clear→set in one call).

    } __except(EXCEPTION_EXECUTE_HANDLER) {
        Log("Exception in MorphTimerProc");
    }
}

// ================================================================
// Background thread — finds WoW's window and installs timer
// ================================================================

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

    // Install the mount display hook (intercepts descriptor writes)
    if (InstallMountHook()) {
        Log("Mount display hook installed successfully");
    } else {
        Log("WARNING: Failed to install mount display hook!");
        Log("NOTE: All other features (character/item/pet/enchant morphs) will still work normally.");
        Log("Only mount morphing will be unavailable. This may happen on some systems due to memory protection.");
    }

    // Install a timer on WoW's main thread — fires every 20ms
    // SetTimer with a callback ensures it runs on the window's thread
    SetTimer(g_wowHwnd, MORPH_TIMER_ID, 20, MorphTimerProc);
    Log("Timer installed. Morpher active!");

    // Keep thread alive
    while (g_running) {
        Sleep(1000);
    }

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
        // Signal shutdown
        g_running = false;
        
        // Kill timer first to stop all memory access
        if (g_wowHwnd) {
            KillTimer(g_wowHwnd, MORPH_TIMER_ID);
            g_wowHwnd = nullptr;
        }
        
        // Uninstall mount hook
        UninstallMountHook();
        UninstallTimeHook();
        
        // Give time for any pending operations to complete
        Sleep(50);
        
        // Clear all pointers to prevent access violations
        g_playerDescBase = 0;
        
        Log("DLL detached cleanly");
        break;
    }
    return TRUE;
}
