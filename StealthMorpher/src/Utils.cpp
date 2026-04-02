#include "Utils.h"
#include "WoWOffsets.h"
#include "Logger.h"
#include <cstdio>
#include <vector>
#include <cstring>
#include <algorithm>

// Define global function pointers
FrameScript_Execute_fn FrameScript_Execute = nullptr;
lua_getfield_fn wow_lua_getfield = nullptr;
lua_tolstring_fn wow_lua_tolstring = nullptr;
lua_settop_fn wow_lua_settop = nullptr;
UpdateDisplayInfo_fn CGUnit_UpdateDisplayInfo = nullptr;

// Additional Lua C API
lua_tonumber_fn wow_lua_tonumber = nullptr;
lua_pushcclosure_fn wow_lua_pushcclosure = nullptr;
lua_setfield_fn wow_lua_setfield = nullptr;
lua_pushstring_fn wow_lua_pushstring = nullptr;
lua_pushnumber_fn wow_lua_pushnumber = nullptr;
lua_gettop_fn wow_lua_gettop = nullptr;
lua_type_fn wow_lua_type = nullptr;

bool g_luaFunctionsRegistered = false;

// Internal helpers for object manager
typedef void* (__cdecl* GetLuaState_fn)();
static auto _GetLuaState = (GetLuaState_fn)0x00817DB0;

typedef WowObject* (__cdecl* GetObjectPtr_fn)(uint64_t guid, uint32_t typemask, const char* file, uint32_t line);
static auto _GetObjectPtr = (GetObjectPtr_fn)0x004D4DB0;

void* GetLuaState() {
    return _GetLuaState();
}

WowObject* GetObjectPtr(uint64_t guid, uint32_t typemask, const char* file, uint32_t line) {
    return _GetObjectPtr(guid, typemask, file, line);
}

typedef void* (__thiscall* GetRow_fn)(void* db, uint32_t id);
static auto _GetRow = (GetRow_fn)0x0065C290;

void* GetRow(void* db, uint32_t id) {
    if (!db) return nullptr;
    return _GetRow(db, id);
}

// Memory scanning
bool PatternScan(DWORD start, DWORD size, const char* pattern, const char* mask, DWORD* result) {
    DWORD patternLen = strlen(mask);
    if (patternLen == 0 || patternLen > size) return false;
    DWORD scanEnd = size - patternLen + 1;
    for (DWORD i = 0; i < scanEnd; i++) {
        bool found = true;
        for (DWORD j = 0; j < patternLen; j++) {
            if (mask[j] != '?' && pattern[j] != *(char*)(start + i + j)) {
                found = false;
                break;
            }
        }
        if (found) {
            *result = start + i;
            return true;
        }
    }
    return false;
}

DWORD FindDescriptorWriteHook(DWORD base) {
    // Looking for: 89 0C 90 (mov [eax+edx*4], ecx)
    // This is inside CGObject_C::SetDescriptor
    // Usually at base + 0x343BAC
    DWORD result = 0;
    if (PatternScan(base + 0x300000, 0x100000, "\x89\x0C\x90", "xxx", &result)) {
        return result;
    }
    return 0;
}

DWORD FindUpdateDisplayInfoHook(DWORD base) {
    // Looking for the start of CGUnit_UpdateDisplayInfo
    // Signature: 55 8B EC 81 EC 88 00 00 00 53 56 8B F1 8B 0D ? ? ? ? 57 8B
    DWORD result = 0;
    if (PatternScan(base + 0x300000, 0x100000, 
        "\x55\x8B\xEC\x81\xEC\x88\x00\x00\x00\x53\x56\x8B\xF1\x8B\x0D\x00\x00\x00\x00\x57\x8B", 
        "xxxxxxxxxxxxxxx????xx", &result)) {
        return result;
    }
    return 0;
}

uint64_t GetPlayerGuid() {
    __try {
        uint32_t clientConnection = *(uint32_t*)(uintptr_t)P_CLIENT_CONNECTION;
        if (clientConnection) {
            uint32_t objectManager = *(uint32_t*)(uintptr_t)(clientConnection + P_OBJECT_MGR_OFFSET);
            if (objectManager) {
                return *(uint64_t*)(uintptr_t)(objectManager + 0xC0);
            }
        }
    } __except(1) {}
    return 0;
}

WowObject* GetPlayer() {
    __try {
        uint32_t clientConnection = *(uint32_t*)(uintptr_t)P_CLIENT_CONNECTION;
        if (clientConnection) {
            uint32_t objectManager = *(uint32_t*)(uintptr_t)(clientConnection + P_OBJECT_MGR_OFFSET);
            if (objectManager) {
            uint64_t localGuid = *(uint64_t*)(uintptr_t)(objectManager + 0xC0);
            if (localGuid == 0) return nullptr;

            uint32_t playerObj = *(uint32_t*)(uintptr_t)(objectManager + 0x24);
            if (playerObj) {
                WowObject* player = (WowObject*)(uintptr_t)playerObj;
                if (player->descriptors) {
                    uint64_t objGuid = *(uint64_t*)player->descriptors;
                    if (objGuid == localGuid) return player;
                }
            }
        }
        }
    } __except(1) {}

    // Fallback
    uint64_t guid = GetPlayerGuid();
    if (guid == 0) return nullptr;
    return GetObjectPtr(guid, 16, __FILE__, __LINE__);
}

uint32_t ReadVisibleEnchant(WowObject* unit, int slot) {
    if (!unit || !unit->descriptors) return 0;
    uint32_t field = GetVisibleEnchantField(slot);
    if (field == 0) return 0;
    return *(uint32_t*)((uint8_t*)unit->descriptors + field);
}

bool WriteVisibleEnchant(WowObject* unit, int slot, uint32_t enchantId) {
    if (!unit || !unit->descriptors) return false;
    uint32_t field = GetVisibleEnchantField(slot);
    if (field == 0) return false;
    
    uint32_t* ptr = (uint32_t*)((uint8_t*)unit->descriptors + field);
    if (*ptr != enchantId) {
        *ptr = enchantId;
        return true;
    }
    return false;
}

bool IsRaceDisplayID(uint32_t displayId) {
    // Verified working race display IDs
    if (displayId == 2222) return true; // Night Elf Female
    if (displayId == 4358) return true; // Troll Female
    if (displayId == 6785) return true; // Orc Male
    if (displayId == 13250) return true; // Dwarf Female
    if (displayId == 17155) return true; // Draenei Male
    if (displayId >= 19723 && displayId <= 19724) return true; // Human
    if (displayId >= 20316 && displayId <= 20318) return true; // Orc Female, Dwarf Male, Night Elf Male
    if (displayId == 20321) return true; // Troll Male
    if (displayId == 20323) return true; // Draenei Female
    if (displayId >= 20578 && displayId <= 20579) return true; // Blood Elf
    if (displayId >= 20580 && displayId <= 20581) return true; // Gnome
    if (displayId >= 20584 && displayId <= 20585) return true; // Tauren
    if (displayId == 23112) return true; // Undead Female
    if (displayId == 28193) return true; // Undead Male
    
    // Legacy naked base models
    if (displayId >= 49 && displayId <= 60) return true;
    if (displayId >= 1563 && displayId <= 1564) return true;
    if (displayId >= 1478 && displayId <= 1479) return true;
    if (displayId >= 15475 && displayId <= 15476) return true;
    if (displayId >= 16125 && displayId <= 16126) return true;
    
    return false;
}

// Title Helpers
bool IsTitleKnown(WowObject* player, uint32_t titleId) {
    if (!player || !player->descriptors || titleId == 0 || titleId > 180) return false;
    uint32_t* knownTitles = (uint32_t*)((uint8_t*)player->descriptors + PLAYER_FIELD_KNOWN_TITLES);
    int index = titleId / 32;
    int bit = titleId % 32;
    return (knownTitles[index] & (1 << bit)) != 0;
}

void SetTitleKnown(WowObject* player, uint32_t titleId, bool known) {
    if (!player || !player->descriptors || titleId == 0 || titleId > 180) return;
    uint32_t* knownTitles = (uint32_t*)((uint8_t*)player->descriptors + PLAYER_FIELD_KNOWN_TITLES);
    int index = titleId / 32;
    int bit = titleId % 32;
    if (known)
        knownTitles[index] |= (1 << bit);
    else
        knownTitles[index] &= ~(1 << bit);
}

void ForEachPlayerGuardian(uint64_t playerGuid, GuardianCallback cb, void* ctx) {
    __try {
        uint32_t clientConnection = *(uint32_t*)P_CLIENT_CONNECTION;
        if (!clientConnection) return;
        uint32_t objMgr = *(uint32_t*)(clientConnection + 0x2ED0);
        if (!objMgr) return;
        
        uint32_t objPtr = *(uint32_t*)(objMgr + 0xAC);
        int iterCount = 0;
        while (objPtr != 0 && objPtr % 2 == 0 && ++iterCount <= 5000) {
            WowObject* current = (WowObject*)objPtr;
            
            if (current->descriptors) {
                uint8_t* desc = (uint8_t*)current->descriptors;
                uint32_t typeMask = ((uint32_t*)desc)[2]; // OBJECT_FIELD_TYPE is at index 2
                
                // Only process units (TYPEMASK_UNIT = 8) that are not players (TYPEMASK_PLAYER = 16)
                if ((typeMask & 8) != 0 && (typeMask & 16) == 0) {
                    uint64_t summonedBy = *(uint64_t*)(desc + UNIT_FIELD_SUMMONEDBY);
                    uint64_t createdBy  = *(uint64_t*)(desc + UNIT_FIELD_CREATEDBY);
                    
                    if (summonedBy == playerGuid || createdBy == playerGuid) {
                        cb(current, desc, ctx);
                    }
                }
            }
            objPtr = *(uint32_t*)(objPtr + 0x3C); // nextObject is at offset 0x3C
        }
    } __except(1) {}
}

bool IsInWorld() {
    __try {
        uint32_t clientConnection = *(uint32_t*)P_CLIENT_CONNECTION;
        if (clientConnection) {
            uint32_t objectManager = *(uint32_t*)(clientConnection + P_OBJECT_MGR_OFFSET);
            if (objectManager) {
                // If ObjectManager exists, we are likely in world
                // Double check by looking for local player
                uint64_t guid = *(uint64_t*)(objectManager + 0xC0);
                if (guid != 0) return true;
            }
        }
    } __except(1) {}
    return false;
}

bool IsInGlue() {
    __try {
        uint32_t state = *(uint32_t*)(uintptr_t)P_GAME_STATE;
        return state == 0;
    } __except(1) {}
    return false;
}

uint64_t GetSelectedCharacterGuid() {
    __try {
        if (!IsInGlue()) return 0;

        uint32_t selectionIndex = *(uint32_t*)(uintptr_t)P_CHARACTER_SELECTION;
        uint32_t charCount = *(uint32_t*)(uintptr_t)P_CHARACTER_COUNT;
        uint32_t charInfoPtr = *(uint32_t*)(uintptr_t)P_CHARACTER_INFO;

        if (charInfoPtr && selectionIndex < charCount) {
            // Character list is an array of structures.
            // GUID is at the start of each structure (offset 0x00).
            uint8_t* entryPtr = (uint8_t*)(uintptr_t)charInfoPtr + (selectionIndex * CHARACTER_SELECT_ENTRY_SIZE);
            uint64_t guid = *(uint64_t*)(uintptr_t)entryPtr;
            return guid;
        }
    } __except(1) {}
    return 0;
}

void ScanOffsets() {
    DWORD base = (DWORD)GetModuleHandleA(NULL);
    if (!base) return;

    DWORD result = 0;

    // FrameScript_Execute
    // Signature: 55 8B EC 81 EC ? ? ? ? 53 8B 5D 08 56 57 85 DB 74
    if (PatternScan(base, 0x800000,
        "\x55\x8B\xEC\x81\xEC\x00\x00\x00\x00\x53\x8B\x5D\x08\x56\x57\x85\xDB\x74",
        "xxxxx????xxxxxxxxx", &result)) {
        FrameScript_Execute = (FrameScript_Execute_fn)result;
        Log("Found FrameScript_Execute at 0x%08X", result);
    } else {
        FrameScript_Execute = (FrameScript_Execute_fn)0x00819210;
        Log("FrameScript_Execute not found, using default 0x00819210");
    }

    // CGUnit_UpdateDisplayInfo
    // Signature: 55 8B EC 81 EC 88 00 00 00 53 56 8B F1 8B 0D ? ? ? ? 57 8B
    if (PatternScan(base, 0x800000,
        "\x55\x8B\xEC\x81\xEC\x88\x00\x00\x00\x53\x56\x8B\xF1\x8B\x0D\x00\x00\x00\x00\x57\x8B",
        "xxxxxxxxxxxxxxx????xx", &result)) {
        CGUnit_UpdateDisplayInfo = (UpdateDisplayInfo_fn)result;
        Log("Found CGUnit_UpdateDisplayInfo at 0x%08X", result);
    } else {
        CGUnit_UpdateDisplayInfo = (UpdateDisplayInfo_fn)0x0073E410;
        Log("CGUnit_UpdateDisplayInfo not found, using default 0x0073E410");
    }

    // lua_getfield
    if (PatternScan(base, 0x800000,
        "\x55\x8B\xEC\x83\xEC\x10\x53\x56\x8B\x75\x08\x57\x8B\x7D\x0C\x85\xF6",
        "xxxxxxxxxxxxxxxx", &result)) {
        wow_lua_getfield = (lua_getfield_fn)result;
        Log("Found lua_getfield at 0x%08X", result);
    } else {
        wow_lua_getfield = (lua_getfield_fn)0x0084E590;
        Log("lua_getfield not found, using default 0x0084E590");
    }

    // lua_tolstring
    if (PatternScan(base, 0x800000,
        "\x55\x8B\xEC\x51\x8B\x45\x0C\x53\x56\x8B\x75\x08\x57\x85\xC0\x75\x0C",
        "xxxxxxxxxxxxxxxx", &result)) {
        wow_lua_tolstring = (lua_tolstring_fn)result;
        Log("Found lua_tolstring at 0x%08X", result);
    } else {
        wow_lua_tolstring = (lua_tolstring_fn)0x0084E0E0;
        Log("lua_tolstring not found, using default 0x0084E0E0");
    }

    // lua_settop
    if (PatternScan(base, 0x800000,
        "\x55\x8B\xEC\x8B\x45\x0C\x85\xC0\x78\x12\x8B\x55\x08\x8B\x0A\x8D\x14\xC1\x3B\x52\x08\x76\x1D",
        "xxxxxxxxxxxxxxxxxxxxxxx", &result)) {
        wow_lua_settop = (lua_settop_fn)result;
        Log("Found lua_settop at 0x%08X", result);
    } else {
        wow_lua_settop = (lua_settop_fn)0x0084DBF0;
        Log("lua_settop not found, using default 0x0084DBF0");
    }

    // ================================================================
    // Additional Lua C API for custom function registration
    // ================================================================

    // lua_tonumber - 55 8B EC 8B 45 0C 8B 4D 08 ... (checks type, converts)
    // Fallback address for 3.3.5a 12340
    wow_lua_tonumber = (lua_tonumber_fn)0x0084E030;
    if (PatternScan(base, 0x800000,
        "\x55\x8B\xEC\x56\x8B\x75\x08\x57\x8B\x7D\x0C\x85\xFF\x79",
        "xxxxxxxxxxxxxx", &result)) {
        wow_lua_tonumber = (lua_tonumber_fn)result;
        Log("Found lua_tonumber at 0x%08X", result);
    } else {
        Log("lua_tonumber using offset 0x%08X", (DWORD)wow_lua_tonumber);
    }

    // lua_pushcclosure (lua_pushcfunction is pushcclosure with 0 upvalues)
    // Signature varies; fallback to known offset
    wow_lua_pushcclosure = (lua_pushcclosure_fn)0x0084E400;
    if (PatternScan(base, 0x800000,
        "\x55\x8B\xEC\x56\x8B\x75\x08\x57\x8B\x46\x08\x8B\x78\x04",
        "xxxxxxxxxxxxxx", &result)) {
        wow_lua_pushcclosure = (lua_pushcclosure_fn)result;
        Log("Found lua_pushcclosure at 0x%08X", result);
    } else {
        Log("lua_pushcclosure using offset 0x%08X", (DWORD)wow_lua_pushcclosure);
    }

    // lua_setfield (used for lua_setglobal)
    // Similar signature to lua_getfield but writes
    wow_lua_setfield = (lua_setfield_fn)0x0084E670;
    if (PatternScan(base, 0x800000,
        "\x55\x8B\xEC\x83\xEC\x10\x53\x56\x8B\x75\x08\x57\x8B\x7D\x0C\x83\xFF",
        "xxxxxxxxxxxxxxxxx", &result)) {
        wow_lua_setfield = (lua_setfield_fn)result;
        Log("Found lua_setfield at 0x%08X", result);
    } else {
        Log("lua_setfield using offset 0x%08X", (DWORD)wow_lua_setfield);
    }

    // lua_pushstring
    wow_lua_pushstring = (lua_pushstring_fn)0x0084E280;
    // Try pattern scan
    Log("lua_pushstring using offset 0x%08X", (DWORD)wow_lua_pushstring);

    // lua_pushnumber
    wow_lua_pushnumber = (lua_pushnumber_fn)0x0084E1F0;
    Log("lua_pushnumber using offset 0x%08X", (DWORD)wow_lua_pushnumber);

    // lua_gettop
    wow_lua_gettop = (lua_gettop_fn)0x0084DBD0;
    Log("lua_gettop using offset 0x%08X", (DWORD)wow_lua_gettop);

    // lua_type
    wow_lua_type = (lua_type_fn)0x0084DC10;
    Log("lua_type using offset 0x%08X", (DWORD)wow_lua_type);
}

// ================================================================
// DBC Reader — Reads CreatureDisplayInfo and CreatureModelData
// from WoW's in-memory DBC storage
// ================================================================

// WoW 3.3.5a DBC storage structure
struct DBCHeader {
    uint32_t magic;       // 'WDBC'
    uint32_t numRecords;
    uint32_t numFields;
    uint32_t recordSize;
    uint32_t stringTableSize;
};

// Generic DBC storage accessor
// In 3.3.5a, DBC storages are typically objects with:
//   +0x00: vtable
//   +0x04: numRows
//   +0x08: fieldCount
//   +0x0C: recordSize
//   +0x10: data pointer (record array)
//   +0x14: string block pointer
//   +0x18: index table pointer (array of pointers indexed by ID)
//   +0x1C: maxID + 1

// Known DBC storage globals for 3.3.5a 12340
static DWORD g_creatureDisplayInfoStore = 0;
static DWORD g_creatureModelDataStore = 0;
static bool g_dbcScanned = false;

static void ScanDBCStores() {
    if (g_dbcScanned) return;
    g_dbcScanned = true;

    DWORD base = (DWORD)GetModuleHandleA(NULL);
    if (!base) return;

    // CreatureDisplayInfo DBC store
    // Look for references to "CreatureDisplayInfo.dbc" string
    DWORD result = 0;
    if (PatternScan(base, 0xC00000,
        "CreatureDisplayInfo.dbc",
        "xxxxxxxxxxxxxxxxxxxxxxx", &result)) {
        // The string address is referenced by the loader.
        // Search backwards/forwards for the store pointer.
        // For now, use known offset
        Log("Found CreatureDisplayInfo.dbc string at 0x%08X", result);
    }

    // Fallback to known addresses for 3.3.5a 12340
    g_creatureDisplayInfoStore = 0x00B44F30;
    g_creatureModelDataStore = 0x00B44E70;

    // Validate DBC stores by checking structure sanity
    __try {
        uint32_t* store = (uint32_t*)g_creatureDisplayInfoStore;
        uint32_t numRows = store[1];
        uint32_t recordSize = store[3];
        uint8_t* data = (uint8_t*)store[4];
        if (numRows == 0 || numRows > 100000 || recordSize == 0 || recordSize > 1024 || !data) {
            Log("WARNING: CreatureDisplayInfo store validation failed (rows=%u, recSize=%u)", numRows, recordSize);
            g_creatureDisplayInfoStore = 0;
        } else {
            Log("CreatureDisplayInfo store OK: rows=%u, recSize=%u", numRows, recordSize);
        }
    } __except(1) {
        Log("WARNING: CreatureDisplayInfo store access exception");
        g_creatureDisplayInfoStore = 0;
    }

    __try {
        uint32_t* store = (uint32_t*)g_creatureModelDataStore;
        uint32_t numRows = store[1];
        uint32_t recordSize = store[3];
        uint8_t* data = (uint8_t*)store[4];
        if (numRows == 0 || numRows > 100000 || recordSize == 0 || recordSize > 1024 || !data) {
            Log("WARNING: CreatureModelData store validation failed (rows=%u, recSize=%u)", numRows, recordSize);
            g_creatureModelDataStore = 0;
        } else {
            Log("CreatureModelData store OK: rows=%u, recSize=%u", numRows, recordSize);
        }
    } __except(1) {
        Log("WARNING: CreatureModelData store access exception");
        g_creatureModelDataStore = 0;
    }

    Log("DBC stores: DisplayInfo=0x%08X, ModelData=0x%08X",
        g_creatureDisplayInfoStore, g_creatureModelDataStore);
}

// Read a row from a DBC store by ID
// Returns pointer to the row data, or nullptr
static const uint8_t* DBCLookupEntry(DWORD storeAddr, uint32_t id) {
    if (!storeAddr) return nullptr;

    __try {
        // Try index table approach first
        // Structure: [vtable, numRows, fieldCount, recordSize, dataPtr, stringPtr, indexPtr, maxID]
        uint32_t* store = (uint32_t*)storeAddr;
        uint32_t numRows = store[1];
        uint32_t recordSize = store[3];
        uint8_t* data = (uint8_t*)store[4];
        uint8_t* stringBlock = (uint8_t*)store[5];

        if (!data || numRows == 0 || recordSize == 0) return nullptr;

        // Check if index table exists
        uint32_t* indexTable = (uint32_t*)store[6];
        uint32_t maxID = store[7];

        if (indexTable && id < maxID && id > 0) {
            uint32_t rowPtr = indexTable[id];
            if (rowPtr != 0) {
                return (const uint8_t*)rowPtr;
            }
        }

        // Fallback: linear scan
        for (uint32_t i = 0; i < numRows; i++) {
            const uint8_t* row = data + (i * recordSize);
            uint32_t rowID = *(uint32_t*)row;
            if (rowID == id) return row;
        }
    } __except(1) {
        Log("Exception in DBCLookupEntry for store 0x%08X, id %u", storeAddr, id);
    }
    return nullptr;
}

static const char* DBCGetString(DWORD storeAddr, uint32_t offset) {
    if (!storeAddr || offset == 0) return "";
    __try {
        uint32_t* store = (uint32_t*)storeAddr;
        const char* stringBlock = (const char*)store[5];
        if (!stringBlock) return "";
        return stringBlock + offset;
    } __except(1) {}
    return "";
}

bool LookupCreatureDisplay(uint32_t displayID, CreatureDisplayEntry* out) {
    ScanDBCStores();
    if (!out) return false;
    memset(out, 0, sizeof(CreatureDisplayEntry));

    const uint8_t* row = DBCLookupEntry(g_creatureDisplayInfoStore, displayID);
    if (!row) return false;

    __try {
        // CreatureDisplayInfo.dbc layout (3.3.5a):
        // 0: ID (uint32)
        // 1: ModelID (uint32)
        // 2: SoundID (uint32)
        // 3: ExtendedDisplayInfoID (uint32)
        // 4: CreatureModelScale (float)
        // 5: CreatureModelAlpha (uint32)
        // 6: TextureVariation1 (string offset)
        // 7: TextureVariation2 (string offset)
        // 8: TextureVariation3 (string offset)
        // ... more fields
        const uint32_t* fields = (const uint32_t*)row;
        out->displayID = fields[0];
        out->modelID = fields[1];
        out->modelScale = *(const float*)&fields[4];

        const char* tex1 = DBCGetString(g_creatureDisplayInfoStore, fields[6]);
        const char* tex2 = DBCGetString(g_creatureDisplayInfoStore, fields[7]);
        const char* tex3 = DBCGetString(g_creatureDisplayInfoStore, fields[8]);
        strncpy_s(out->texture1, sizeof(out->texture1), tex1, _TRUNCATE);
        strncpy_s(out->texture2, sizeof(out->texture2), tex2, _TRUNCATE);
        strncpy_s(out->texture3, sizeof(out->texture3), tex3, _TRUNCATE);

        return true;
    } __except(1) {
        Log("Exception reading CreatureDisplayInfo for ID %u", displayID);
    }
    return false;
}

bool LookupCreatureModel(uint32_t modelID, CreatureModelEntry* out) {
    ScanDBCStores();
    if (!out) return false;
    memset(out, 0, sizeof(CreatureModelEntry));

    const uint8_t* row = DBCLookupEntry(g_creatureModelDataStore, modelID);
    if (!row) return false;

    __try {
        // CreatureModelData.dbc layout (3.3.5a):
        // 0: ID (uint32)
        // 1: Flags (uint32)
        // 2: ModelPath (string offset)
        // ... more fields
        const uint32_t* fields = (const uint32_t*)row;
        out->modelID = fields[0];

        const char* path = DBCGetString(g_creatureModelDataStore, fields[2]);
        strncpy_s(out->modelPath, sizeof(out->modelPath), path, _TRUNCATE);

        return true;
    } __except(1) {
        Log("Exception reading CreatureModelData for ID %u", modelID);
    }
    return false;
}

// ================================================================
// Custom Lua Functions — Exposed to WoW's Lua environment
// ================================================================

// TransmorpherGetModelInfo(displayID) -> modelPath, scale, tex1, tex2, tex3
// Returns model information from the DBC for preview rendering
static int __cdecl Lua_TransmorpherGetModelInfo(void* L) {
    if (!wow_lua_tonumber || !wow_lua_pushstring || !wow_lua_pushnumber) return 0;

    __try {
        double arg = wow_lua_tonumber(L, 1);
        uint32_t displayID = (uint32_t)arg;
        if (displayID == 0) return 0;

        CreatureDisplayEntry disp = {};
        if (!LookupCreatureDisplay(displayID, &disp)) {
            // Return nil (no results pushed)
            return 0;
        }

        CreatureModelEntry model = {};
        if (!LookupCreatureModel(disp.modelID, &model)) {
            return 0;
        }

        // Return: modelPath, scale, texture1, texture2, texture3
        wow_lua_pushstring(L, model.modelPath);
        wow_lua_pushnumber(L, (double)disp.modelScale);
        wow_lua_pushstring(L, disp.texture1);
        wow_lua_pushstring(L, disp.texture2);
        wow_lua_pushstring(L, disp.texture3);

        return 5; // 5 return values
    } __except(1) {
        Log("Exception in Lua_TransmorpherGetModelInfo");
    }
    return 0;
}

void RegisterCustomLuaFunctions() {
    g_luaFunctionsRegistered = true;
}
bool GetDllDirectory(char* buffer, size_t size) {
    if (GetModuleFileNameA(GetModuleHandleA("dinput8.dll"), buffer, (DWORD)size)) {
        char* lastBS = strrchr(buffer, '\\');
        if (lastBS) {
            *lastBS = '\0';
            return true;
        }
    }
    return false;
}

bool CreateDllSubdirectory(const char* name) {
    char path[MAX_PATH];
    if (GetDllDirectory(path, sizeof(path))) {
        strcat_s(path, sizeof(path), "\\");
        strcat_s(path, sizeof(path), name);
        return CreateDirectoryA(path, NULL) || GetLastError() == ERROR_ALREADY_EXISTS;
    }
    return false;
}

static char g_sessionLogPath[MAX_PATH] = {0};

void GetSessionLogPath(char* buffer, size_t size) {
    if (g_sessionLogPath[0] != '\0') {
        strcpy_s(buffer, size, g_sessionLogPath);
        return;
    }

    char dllDir[MAX_PATH];
    if (GetDllDirectory(dllDir, sizeof(dllDir))) {
        SYSTEMTIME st;
        GetLocalTime(&st);
        sprintf_s(g_sessionLogPath, sizeof(g_sessionLogPath), "%s\\TSM_logs\\transmorpher_%04d%02d%02d_%02d%02d%02d.log", 
            dllDir, st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
        strcpy_s(buffer, size, g_sessionLogPath);
    }
}

void Log(const char* format, ...) {
    char buffer[4094];
    va_list args;
    va_start(args, format);
    vsprintf_s(buffer, format, args);
    va_end(args);

    char logPath[MAX_PATH];
    GetSessionLogPath(logPath, sizeof(logPath));

    FILE* f = nullptr;
    if (fopen_s(&f, logPath, "a") == 0 && f) {
        SYSTEMTIME st;
        GetLocalTime(&st);
        fprintf(f, "[%02d:%02d:%02d] %s\n", st.wHour, st.wMinute, st.wSecond, buffer);
        fclose(f);
    }
}

void CleanupOldLogs(int maxFilesToKeep) {
    if (maxFilesToKeep <= 0) return;
    char dllDir[MAX_PATH];
    if (!GetDllDirectory(dllDir, sizeof(dllDir))) return;

    char searchPath[MAX_PATH];
    sprintf_s(searchPath, sizeof(searchPath), "%s\\TSM_logs\\*.log", dllDir);

    WIN32_FIND_DATAA findData;
    HANDLE hFind = FindFirstFileA(searchPath, &findData);
    if (hFind == INVALID_HANDLE_VALUE) return;

    struct LogFileEntry {
        char fileName[MAX_PATH];
        ULARGE_INTEGER writeTime;
    };
    std::vector<LogFileEntry> logs;

    do {
        if ((findData.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
            LogFileEntry e = {};
            strcpy_s(e.fileName, sizeof(e.fileName), findData.cFileName);
            e.writeTime.LowPart = findData.ftLastWriteTime.dwLowDateTime;
            e.writeTime.HighPart = findData.ftLastWriteTime.dwHighDateTime;
            logs.push_back(e);
        }
    } while (FindNextFileA(hFind, &findData));

    FindClose(hFind);

    if ((int)logs.size() <= maxFilesToKeep) return;

    std::sort(logs.begin(), logs.end(), [](const LogFileEntry& a, const LogFileEntry& b) {
        return a.writeTime.QuadPart > b.writeTime.QuadPart;
    });

    for (size_t i = (size_t)maxFilesToKeep; i < logs.size(); ++i) {
        char deletePath[MAX_PATH];
        sprintf_s(deletePath, sizeof(deletePath), "%s\\TSM_logs\\%s", dllDir, logs[i].fileName);
        DeleteFileA(deletePath);
    }
}
