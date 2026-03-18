#pragma once
#include <cstdint>
#include <windows.h>

// Forward declarations for types we don't fully define
struct WowObject;

// =========================================================================
// Field Offsets (3.3.5a 12340)
// =========================================================================
// Descriptor fields are 32-bit values relative to the descriptor pointer.
// We define them as byte offsets (Index * 4) for direct memory access.

static const uint32_t UNIT_FIELD_DISPLAYID = 0x43 * 4; // 0x10C
static const uint32_t UNIT_FIELD_NATIVEDISPLAYID = 0x44 * 4; // 0x110
static const uint32_t UNIT_FIELD_MOUNTDISPLAYID = 0x45 * 4; // 0x114
static const uint32_t UNIT_FIELD_CRITTER = 0x0A * 4; // 0x28 (Companion GUID)
static const uint32_t UNIT_FIELD_SUMMON = 0x08 * 4; // 0x20 (Summoned Pet GUID)
static const uint32_t UNIT_FIELD_SUMMONEDBY = 0x0E * 4; // 0x38
static const uint32_t UNIT_FIELD_CREATEDBY = 0x10 * 4; // 0x40
static const uint32_t PLAYER_FIELD_CHOSEN_TITLE = 0x141 * 4; // 0x504
static const uint32_t PLAYER_FIELD_KNOWN_TITLES = 0x272 * 4; // 0x9C8 (3.3.5a 12340)

// Type masks
enum { 
    TYPEMASK_OBJECT     = 0x0001,
    TYPEMASK_ITEM       = 0x0002,
    TYPEMASK_CONTAINER  = 0x0004,
    TYPEMASK_UNIT       = 0x0008,
    TYPEMASK_PLAYER     = 0x0010,
    TYPEMASK_GAMEOBJECT = 0x0020,
    TYPEMASK_DYNAMICOBJECT = 0x0040,
    TYPEMASK_CORPSE     = 0x0080
};

// =========================================================================
// Structures
// =========================================================================

struct WowObject {
    uint32_t vtable;
    uint32_t unk04;
    uint32_t* descriptors;      // 0x08
    uint8_t  pad0C[0x14];       // 0x0C .. 0x1F
    uint32_t objType;           // 0x20 (1=Object, 3=Unit, 4=Player)
    uint8_t  pad24[0x18];       // 0x24 .. 0x3B
    WowObject* nextObject;      // 0x3C
};

// =========================================================================
// Functions & Globals
// =========================================================================

// Helper functions (inline to avoid linking issues if included multiple times)
inline uint32_t GetVisibleItemField(int slot) {
    // Visible items start around 0x1D0 (Index 116 = 0x74) ?
    // Actually PLAYER_VISIBLE_ITEM_1_0 = 283 (0x46C)
    // 3.3.5a:
    // 0 = Head, 1=Neck, 2=Shoulder, 3=Shirt, 4=Chest, 5=Waist, 6=Legs, 7=Boots, 8=Wrist, 9=Hands
    // 10=Ring1, 11=Ring2, 12=Trinket1, 13=Trinket2, 14=Back, 15=MainHand, 16=OffHand, 17=Ranged, 18=Tabard
    // Each visible item is 2 integers (ID, Enchant)
    // PLAYER_VISIBLE_ITEM_1_ENTRYID = 283
    
    // Mapping logical slot (1..19) to field offset
    // Head=1 -> 283
    static const uint32_t BASE = 283;
    static const int MAP[] = {
        0, // 0 unused
        0, // 1 Head (Index 0 relative to base)
        1, // 2 Neck
        2, // 3 Shoulder
        3, // 4 Shirt
        4, // 5 Chest
        5, // 6 Waist
        6, // 7 Legs
        7, // 8 Boots
        8, // 9 Wrist
        9, // 10 Hands
        10, // 11 Ring1
        11, // 12 Ring2
        12, // 13 Trinket1
        13, // 14 Trinket2
        14, // 15 Back
        15, // 16 MainHand
        16, // 17 OffHand
        17, // 18 Ranged
        18  // 19 Tabard
    };
    
    if (slot < 1 || slot > 19) return 0;
    int idx = MAP[slot];
    // IMPORTANT: Each item slot takes TWO fields (Item ID + Enchant)
    // So the stride is 2, not 1.
    return (BASE + (idx * 2)) * 4;
}

inline uint32_t GetVisibleEnchantField(int slot) {
    // Enchants are +1 uint from the Item ID (4 bytes offset)
    uint32_t itemField = GetVisibleItemField(slot);
    if (itemField == 0) return 0;
    return itemField + 4;
}

// Global Pointers
static const DWORD P_CLIENT_CONNECTION = 0x00C79CE0; // 3.3.5a 12340
static const DWORD P_OBJECT_MGR_OFFSET = 0x2E04;     // Relative to ClientConnection? No, usually static.
// Re-verified 3.3.5a offsets:
// ObjectMgr is at [0x00C79CE0] + 0x2ED0 in some versions, or static.
// We use the scanning method in Utils.cpp usually.
