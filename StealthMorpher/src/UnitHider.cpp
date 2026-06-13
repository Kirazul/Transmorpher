#include "UnitHider.h"

#include <windows.h>
#include <cstdlib>
#include <cstring>
#include "Logger.h"
#include "WoWOffsets.h"
#include "SpellClass.h"
#include "../third_party/Detours/detours.h"

extern "C" volatile bool g_isProcessTerminating;

namespace {

// ---------------------------------------------------------------------------
// RE'd entry points (wow.exe 3.3.5a 12340)
// ---------------------------------------------------------------------------
// ShouldRender family. Engine renders an object only when its ShouldRender leaves
// BOTH out-params == 0 (dispatch at 0x004F8D4C; the result gates the draw block at
// 0x004F8DA9 `cmp [ebp+8],0; je skip-draw`). Forcing *pOutA = 1 removes the object
// from the draw cleanly (no white, no flicker) — this is the proven hide.
//   __thiscall void ShouldRender(obj; uint flags, int* pOutA, int* pOutB) ret 0xC
typedef void(__fastcall* ShouldRender_fn)(void* self, void* edx, uint32_t flags, int* pOutA, int* pOutB);
static void* g_oSRPlayer = reinterpret_cast<void*>(0x00730F30); // CGPlayer_C::ShouldRender
static void* g_oSRUnit   = reinterpret_cast<void*>(0x006E0840); // CGUnit_C::ShouldRender
static void* g_oSRBase   = reinterpret_cast<void*>(0x00743300); // CGObject_C::ShouldRender (game/dyn objects, corpses)

// CGUnit_C::Animate (vtable idx 35). Runs every frame for every unit BEFORE the draw
// gate, so it is the always-paid CPU cost (bones/particles via 0x74A7F0 / 0x71FBF0).
// Skipping it for culled (already hidden) units is the real FPS win; we still return
// its normal success value (1) so the dispatcher's control flow is byte-for-byte the
// same as a normal hidden unit — no white, no scene corruption.
//   __thiscall int Animate(unit; float dt) ret 4
typedef int(__fastcall* Animate_fn)(void* self, void* edx, float dt);
static void* g_oAnimate = reinterpret_cast<void*>(0x0071FD80);

static bool g_installed = false;

// CGUnit_C::GetCreatureType -> CreatureType.dbc id (Totem = 11). Totems are never
// culled — they must stay visible on the ground (yours and others').
typedef int(__thiscall* GetCreatureType_fn)(void* unit);
static const GetCreatureType_fn GetCreatureType = (GetCreatureType_fn)0x0071F300;
static const int CREATURE_TYPE_TOTEM = 11;
static inline bool IsPlayerGuid(uint64_t g) { return g != 0 && (g >> 48) == 0; }

// UNIT_FIELD_CHARMEDBY = descriptor index 0x0C -> byte 0x30 (3.3.5a). SUMMONEDBY (0x38)
// and CREATEDBY (0x40) come from WoWOffsets.h. All three re-verified against the on-disk
// wow.exe via the CGUnit descriptor dump (descriptor base = obj+0x1958; CharmedBy@0x1988,
// SummonedBy@0x1990, CreatedBy@0x1998 -> desc-relative 0x30/0x38/0x40).
static const uint32_t UNIT_FIELD_CHARMED   = 0x06 * 4;
static const uint32_t UNIT_FIELD_CHARMEDBY = 0x0C * 4;
// UNIT_CREATED_BY_SPELL = descriptor index 0x51 -> byte 0x144 (3.3.5a). Verified: dump
// CreatedBySpell@0x1A9C - descBase 0x1958 = 0x144. (The old 0x48 here was bogus — that is
// UNIT_FIELD_TARGET's low dword.) Nonzero on any spell-created unit; informational only.
static const uint32_t UNIT_CREATED_BY_SPELL = 0x51 * 4;
static const uint32_t UNIT_FIELD_PETNUMBER = 0x4B * 4; // public, nonzero on real pets even when owner GUIDs are absent
static const uint32_t UNIT_FIELD_DISPLAYID  = 0x17 * 4; // 0x5C, current display model id

// --- Mirror-Image discriminator (RE'd authoritative signal) -----------------
// Mage Mirror Images (and similar spell-cloned guardians) often carry NO owner GUID in
// SUMMONEDBY/CREATEDBY/CHARMEDBY on OBSERVER clients — the clone only knows its own GUID
// and pulls the owner's appearance from the server (SMSG_MIRRORIMAGE_DATA). So owner-field
// detection alone misses other players' Mirror Images. The engine itself decides "this is
// a Mirror Image" in its per-unit appearance updater @0x00730100, which gates the
// RequestMirrorImageDataFromServer call (0x00716F10) on a cache flag:
//     mov eax,[unit+0xD0]      ; CGUnit unit-cache ptr (same ptr GetCreatureType/Rank use)
//     mov ecx,[eax+0xD8]       ; cache flags dword
//     shr ecx,4 ; test cl,1    ; bit 0x10 set  -> treat as Mirror Image
// We read that exact bit. Server-independent and matches the client's own classification.
static const uintptr_t OBJ_UNITCACHE              = 0xD0;
static const uintptr_t UNITCACHE_FLAGS            = 0xD8;
static const uint32_t  UNITCACHE_FLAG_MIRRORIMAGE = 0x10;
static bool IsMirrorImage(void* obj) {
    __try {
        uintptr_t cache = *(uintptr_t*)((uint8_t*)obj + OBJ_UNITCACHE);
        if (!cache) return false;
        const uint32_t f = *(uint32_t*)(cache + UNITCACHE_FLAGS);
        return (f & UNITCACHE_FLAG_MIRRORIMAGE) != 0;
    } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

// ---------------------------------------------------------------------------
// Config — main-thread only (render pass + 50ms timer share that thread), volatiles.
// ---------------------------------------------------------------------------
static volatile bool  g_enabled      = false;  // master
static volatile bool  g_hidePlayers  = true;
static volatile bool  g_hidePets     = false;
static volatile bool  g_hideNpcs     = false;
static volatile bool  g_hideObjects  = false;
static volatile bool  g_hideCorpses  = false;
static volatile bool  g_hideOtherSummons = false; // hide other players' summons (Mirror Images etc.) at ANY distance
static volatile bool  g_skipAnimate  = true;   // also skip animation work for culled units (FPS)
static volatile float g_distSq       = 30.0f * 30.0f;

static volatile bool     g_haveLocal = false;
static volatile uint64_t g_localGuid = 0;
static volatile float    g_lx = 0.0f, g_ly = 0.0f, g_lz = 0.0f;

static const uintptr_t OBJ_DESCRIPTORS = 0x08;

// Group/raid protection (party+raid GUIDs). Written from the main-thread command
// path, read from the main-thread render pass — same thread, no lock needed.
static volatile bool g_showGroup = true;
static const int     MAX_GROUP = 64;
static uint64_t      g_groupGuids[MAX_GROUP] = {};
static volatile int  g_groupCount = 0;

// Pets sometimes reach observer clients without SUMMONEDBY/CREATEDBY populated. Keep
// only the local player's public pet/summon GUIDs protected; group pets can be hidden.
static const int MAX_PROTECTED_PETS = 3;
static uint64_t g_protectedPetGuids[MAX_PROTECTED_PETS] = {};
static volatile int g_protectedPetCount = 0;

// Shadow render-flag bits in the engine's render-flags global (0x00CD774C). RE-verified by the
// console-variable setters that write this global (wow.exe 3.3.5a):
//   0x00000040  = "Terrain shadow"   (model/character shadows cast on the ground — the blob
//                  shadows under units; toggled @0x0077F7E2/0x0078D681 with that exact string)
//   0x10000000  = renderObjectShadow (object shadows; @0x00780F92/0x007814CA)
// "Hide All Shadows" used to clear ONLY 0x10000000, which left the character/terrain blob shadows
// visible (the dark patches the user still saw after culling players). We clear BOTH so no shadow
// of any kind renders — full cleanup + FPS.
static const DWORD ADDR_RENDER_FLAGS   = 0x00CD774C;
static const DWORD RENDER_FLAG_SHADOWS = 0x10000000 | 0x00000040; // renderObjectShadow | terrain(model) shadow
static volatile bool g_hideShadows = false;
static bool g_shadowCleared = false;

static bool IsGroupMember(uint64_t guid) {
    if (guid == 0) return false;
    const int n = g_groupCount;
    for (int i = 0; i < n && i < MAX_GROUP; ++i) {
        if (g_groupGuids[i] == guid) return true;
    }
    return false;
}

static void AddProtectedPetGuid(uint64_t guid, int* count) {
    if (guid == 0 || !count || *count >= MAX_PROTECTED_PETS) return;
    for (int i = 0; i < *count; ++i) {
        if (g_protectedPetGuids[i] == guid) return;
    }
    g_protectedPetGuids[(*count)++] = guid;
}

static void AddProtectedPetsFromPlayerObj(void* obj, int* count) {
    if (!obj || !count) return;
    __try {
        void* descV = *(void**)((uint8_t*)obj + OBJ_DESCRIPTORS);
        if (!descV) return;
        uint8_t* desc = (uint8_t*)descV;
        AddProtectedPetGuid(*(uint64_t*)(desc + UNIT_FIELD_CHARMED), count);
        AddProtectedPetGuid(*(uint64_t*)(desc + UNIT_FIELD_SUMMON), count);
        AddProtectedPetGuid(*(uint64_t*)(desc + UNIT_FIELD_CRITTER), count);
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
}

static bool IsProtectedPetGuid(uint64_t guid) {
    if (guid == 0) return false;
    const int n = g_protectedPetCount;
    for (int i = 0; i < n && i < MAX_PROTECTED_PETS; ++i) {
        if (g_protectedPetGuids[i] == guid) return true;
    }
    return false;
}

static const uintptr_t OBJ_MOVEMENT    = 0xD8;   // unit/player movement struct ptr
static const uintptr_t MOVE_POS        = 0x10;   // C3Vector x/y/z within movement
static const int       VT_GETPOSITION  = 12;     // CGObject_C::GetPosition(out) — for non-unit objects

// Direct, verified read for units/players: *(obj+0xD8) -> +0x10/0x14/0x18.
static bool ReadUnitPos(void* obj, float* out /*[3]*/) {
    __try {
        uintptr_t move = *(uintptr_t*)((uint8_t*)obj + OBJ_MOVEMENT);
        if (!move) return false;
        out[0] = *(float*)(move + MOVE_POS + 0);
        out[1] = *(float*)(move + MOVE_POS + 4);
        out[2] = *(float*)(move + MOVE_POS + 8);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

// Virtual GetPosition for game/dynamic objects & corpses (no +0xD8 movement block).
static bool ReadObjPosVtbl(void* obj, float* out /*[3]*/) {
    __try {
        void** vt = *(void***)obj;
        if (!vt) return false;
        typedef void(__thiscall* GetPos_fn)(void*, float*);
        GetPos_fn getPos = (GetPos_fn)vt[VT_GETPOSITION];
        if (!getPos) return false;
        out[0] = out[1] = out[2] = 0.0f;
        getPos(obj, out);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

static bool FarFromLocal(const float* p) {
    if (p[0] == 0.0f && p[1] == 0.0f && p[2] == 0.0f) return false; // positionless / invalid
    const float dx = p[0] - g_lx, dy = p[1] - g_ly, dz = p[2] - g_lz;
    return (dx * dx + dy * dy + dz * dz) > g_distSq;
}

// Decide if a UNIT or PLAYER object should be culled. The "hide other players'
// summons" rule is INDEPENDENT of the distance-cull master and of having a local
// position (it hides at ANY distance); the distance categories need g_haveLocal.
static bool ShouldCullUnit(void* obj) {
    void* descV = *(void**)((uint8_t*)obj + OBJ_DESCRIPTORS);
    if (!descV) return false;
    uint8_t* desc = (uint8_t*)descV;
    const uint32_t typeMask = ((uint32_t*)desc)[2];
    const uint64_t guid = *(uint64_t*)desc;

    if (typeMask & TYPEMASK_PLAYER) {
        // Players are only affected by the distance-cull (master must be on + position).
        if (!g_enabled || !g_haveLocal) return false;
        if (guid == g_localGuid) return false;            // never the local player
        if (g_showGroup && IsGroupMember(guid)) return false; // never party/raid members
        if (!g_hidePlayers) return false;
        float p[3];
        if (!ReadUnitPos(obj, p)) return false;
        return FarFromLocal(p);
    }

    if (typeMask & TYPEMASK_UNIT) {
        // Totems are NEVER culled — they must stay readable on the ground (yours/others').
        __try { if (GetCreatureType(obj) == CREATURE_TYPE_TOTEM) return false; }
        __except (EXCEPTION_EXECUTE_HANDLER) {}

        // ★ ENCOUNTER ADD — never cull its MODEL (no hardcoded ids). A HOSTILE NPC during an
        // active boss fight is fight content (Lich King Raging Spirit / Val'kyr, Festergut/Rotface
        // adds). The Raging Spirit "rips out a piece of the target's spirit", so its createdBy is
        // the VICTIM PLAYER — which otherwise trips the other-players'-summon hide below and makes
        // the spirit vanish entirely. Keeping it visible matches the spell-visual filter's
        // encounter-add protection. Scoped to active encounters so trash still declutters normally.
        if (SpellClass_IsBossEncounterActive() && SpellClass_IsEnemyUnit(obj)) return false;

        // A creature's owner can live in either field; Mirror Images / guardians use
        // SUMMONEDBY, temp-summons use CREATEDBY. Also consult CHARMEDBY for charmed
        // guardians. Check ALL so we never miss the player that spawned it.
        const uint64_t charmedBy  = *(uint64_t*)(desc + UNIT_FIELD_CHARMEDBY);
        const uint64_t summonedBy = *(uint64_t*)(desc + UNIT_FIELD_SUMMONEDBY);
        const uint64_t createdBy  = *(uint64_t*)(desc + UNIT_FIELD_CREATEDBY);
        const uint32_t petNumber  = *(uint32_t*)(desc + UNIT_FIELD_PETNUMBER);

        // Never the local player's own pet/guardians/summons.
        if (g_localGuid != 0 && (summonedBy == g_localGuid || createdBy == g_localGuid || charmedBy == g_localGuid))
            return false;
        if (IsProtectedPetGuid(guid)) return false;
        // ★ VEHICLES / player-controlled units: a unit a player RIDES or controls carries that
        // player's GUID in CHARMEDBY. NEVER cull it — when a player enters a vehicle the engine
        // hides the player model (they're the passenger), so culling the vehicle too makes them
        // "vanish into nothing". This covers raid vehicles AND encounter ones that carry a player
        // (Lich King Val'kyr, gunship cannons, Putricide's abomination, Malygos drakes, etc.).
        // Mind-controlled units (also charmed-by-player) staying visible is correct — they're a
        // mechanic, not summon clutter.
        if (IsPlayerGuid(charmedBy)) return false;
        // OTHER players' summons — Mirror Images, guardians, ghouls, elementals, etc.
        // Hidden at ANY distance whenever the option is on, REGARDLESS of the distance
        // -cull master. Hidden if a SUMMON/CREATE owner field is another player's GUID (wild and
        // boss-summoned NPCs have non-player owners, so they are not touched; charmed/ridden units
        // already returned above). Totems already returned above.
        // (Protected encounter adds — hostile NPCs during a boss fight, incl. the Lich King Raging
        // Spirit whose createdBy is the victim player — already returned "don't cull" at the top of
        // this branch, so the summon-hide below never reaches them. Ordinary/PvP pets are unchanged.)
        const bool ownedByPlayer =
            IsPlayerGuid(summonedBy) || IsPlayerGuid(createdBy);
        const bool realPet = (petNumber != 0);
        // Mirror Images that come with no owner GUID (the common observer-client case)
        // are caught by the engine's own mirror-image flag. The local player's own clones
        // carry the owner field on this client and were already exempted above.
        const bool mirrorImage = IsMirrorImage(obj);
        if (g_hideOtherSummons && (ownedByPlayer || mirrorImage || realPet)) return true;
        const uint64_t owner = summonedBy ? summonedBy : (createdBy ? createdBy : charmedBy);

        // Remaining unit categories are pure distance-cull (need master + position).
        if (!g_enabled || !g_haveLocal) return false;
        const bool owned = (owner != 0) || realPet;
        if (!(owned ? g_hidePets : g_hideNpcs)) return false;
        float p[3];
        if (!ReadUnitPos(obj, p)) return false;
        return FarFromLocal(p);
    }

    return false;
}

// Caster/creator GUID of a ground/area object: DYNAMICOBJECT_CASTER and GAMEOBJECT_CREATED_BY
// both live at descriptor field OBJECT_END+0 == byte 0x18 (RE-verified; same field SpellClass
// reads as DESC_DYNOBJ_OWNER). Lets us tell a PLAYER's ground clutter from an NPC/boss mechanic.
static const uintptr_t OBJ_DYNOBJ_OWNER = 0x18;

// Decide if a non-unit object (gameobject / dynamic object / corpse) should be culled.
static bool ShouldCullObject(void* obj) {
    if (!g_haveLocal) return false;
    void* descV = *(void**)((uint8_t*)obj + OBJ_DESCRIPTORS);
    if (!descV) return false;
    uint8_t* desc = (uint8_t*)descV;
    const uint32_t typeMask = ((uint32_t*)desc)[2];

    if (typeMask & (TYPEMASK_GAMEOBJECT | TYPEMASK_DYNAMICOBJECT)) {
        if (!g_hideObjects) return false;
        // ENCOUNTER SAFETY (RE-based, no hardcoded ids): a ground/area object is culled ONLY
        // when a PLAYER created/cast it — real player ground clutter (Blizzard, Death and
        // Decay, mage table, hunter trap, banner), exactly what this option is meant to thin
        // out. Anything cast/created by an NPC or boss (Algalon's Cosmic Smash void zone,
        // fire pools, boss telegraphs) and every owner-less world doodad / light source is
        // KEPT, so encounter mechanics and scene lighting can never be hidden. Your own and
        // your group's ground effects are kept too, matching the rest of the cull system.
        const uint64_t owner = *(uint64_t*)(desc + OBJ_DYNOBJ_OWNER);
        if (!IsPlayerGuid(owner)) return false;                       // NPC/boss/unowned -> always visible
        if (g_localGuid != 0 && owner == g_localGuid) return false;   // never your own ground effects
        if (g_showGroup && IsGroupMember(owner)) return false;        // never party/raid ground effects
    } else if (typeMask & TYPEMASK_CORPSE) {
        if (!g_hideCorpses) return false;
    } else {
        return false;                                                 // units/players handled elsewhere
    }

    float p[3];
    if (!ReadObjPosVtbl(obj, p)) return false;
    return FarFromLocal(p);
}

// ---------------------------------------------------------------------------
// Hooks
// ---------------------------------------------------------------------------
// Any unit-cull feature active? (distance-cull master OR the independent summons hide)
static inline bool UnitCullActive() { return g_enabled || g_hideOtherSummons; }

void __fastcall hkSRPlayer(void* self, void* edx, uint32_t flags, int* pOutA, int* pOutB) {
    reinterpret_cast<ShouldRender_fn>(g_oSRPlayer)(self, edx, flags, pOutA, pOutB);
    if (UnitCullActive() && !g_isProcessTerminating && self && pOutA) {
        __try { if (ShouldCullUnit(self)) *pOutA = 1; } __except (EXCEPTION_EXECUTE_HANDLER) {}
    }
}

void __fastcall hkSRUnit(void* self, void* edx, uint32_t flags, int* pOutA, int* pOutB) {
    reinterpret_cast<ShouldRender_fn>(g_oSRUnit)(self, edx, flags, pOutA, pOutB);
    if (UnitCullActive() && !g_isProcessTerminating && self && pOutA) {
        __try { if (ShouldCullUnit(self)) *pOutA = 1; } __except (EXCEPTION_EXECUTE_HANDLER) {}
    }
}

void __fastcall hkSRBase(void* self, void* edx, uint32_t flags, int* pOutA, int* pOutB) {
    reinterpret_cast<ShouldRender_fn>(g_oSRBase)(self, edx, flags, pOutA, pOutB);
    // This base is ALSO reached via internal calls from the player/unit ShouldRender;
    // ShouldCullObject ignores unit/player types, so only true objects are affected here.
    if (g_enabled && !g_isProcessTerminating && self && pOutA) {
        __try { if (ShouldCullObject(self)) *pOutA = 1; } __except (EXCEPTION_EXECUTE_HANDLER) {}
    }
}

int __fastcall hkAnimate(void* self, void* edx, float dt) {
    if (UnitCullActive() && g_skipAnimate && !g_isProcessTerminating && self) {
        __try {
            if (ShouldCullUnit(self)) {
                // Unit is hidden this frame anyway — skip the bone/particle work and
                // report normal success so the dispatcher's flow is unchanged.
                return 1;
            }
        } __except (EXCEPTION_EXECUTE_HANDLER) {}
    }
    return reinterpret_cast<Animate_fn>(g_oAnimate)(self, edx, dt);
}

} // namespace

void UnitHider_Initialize() {
    if (g_installed) return;
    if (DetourTransactionBegin() != NO_ERROR) { Log("[UnitHider] txn begin failed"); return; }
    DetourUpdateThread(GetCurrentThread());
    DetourAttach(&(PVOID&)g_oSRPlayer, (PVOID)hkSRPlayer);
    DetourAttach(&(PVOID&)g_oSRUnit,   (PVOID)hkSRUnit);
    DetourAttach(&(PVOID&)g_oSRBase,   (PVOID)hkSRBase);
    DetourAttach(&(PVOID&)g_oAnimate,  (PVOID)hkAnimate);
    if (DetourTransactionCommit() != NO_ERROR) { Log("[UnitHider] txn commit failed"); return; }
    g_installed = true;
    Log("[UnitHider] hooks installed (ShouldRender x3 + Animate; inert until enabled)");
}

void UnitHider_Shutdown() {
    if (!g_installed || g_isProcessTerminating) { g_installed = false; return; }
    g_enabled = false;
    DetourTransactionBegin();
    DetourUpdateThread(GetCurrentThread());
    DetourDetach(&(PVOID&)g_oSRPlayer, (PVOID)hkSRPlayer);
    DetourDetach(&(PVOID&)g_oSRUnit,   (PVOID)hkSRUnit);
    DetourDetach(&(PVOID&)g_oSRBase,   (PVOID)hkSRBase);
    DetourDetach(&(PVOID&)g_oAnimate,  (PVOID)hkAnimate);
    DetourTransactionCommit();
    g_installed = false;
}

void UnitHider_SetEnabled(bool enabled)     { g_enabled = enabled; Log("[UnitHider] enabled=%d", enabled ? 1 : 0); }
void UnitHider_SetHidePlayers(bool enabled) { g_hidePlayers = enabled; }
void UnitHider_SetHidePets(bool enabled)    { g_hidePets = enabled; }
void UnitHider_SetHideNpcs(bool enabled)    { g_hideNpcs = enabled; }
void UnitHider_SetHideObjects(bool enabled) { g_hideObjects = enabled; }
void UnitHider_SetHideCorpses(bool enabled) { g_hideCorpses = enabled; }
void UnitHider_SetHideOtherSummons(bool enabled) { g_hideOtherSummons = enabled; }

void UnitHider_SetDistance(float yards) {
    if (yards < 0.0f)    yards = 0.0f;   // 0 = hide everything past you
    if (yards > 1000.0f) yards = 1000.0f;
    g_distSq = yards * yards;
}

void UnitHider_SetShowGroup(bool enabled) { g_showGroup = enabled; }
void UnitHider_SetHideShadows(bool enabled) { g_hideShadows = enabled; }

// Reasserts the shadow-flag each tick (the engine re-enables it on zone changes), and
// restores it exactly once when the option is turned off. Read-modify-write of only the
// shadow bit keeps every other render flag at its live value — safe per-tick write.
void UnitHider_ApplyGlobals() {
    if (g_isProcessTerminating) return;
    __try {
        if (g_hideShadows) {
            DWORD v = *(DWORD*)(uintptr_t)ADDR_RENDER_FLAGS;
            if (v & RENDER_FLAG_SHADOWS) {
                *(DWORD*)(uintptr_t)ADDR_RENDER_FLAGS = v & ~RENDER_FLAG_SHADOWS;
            }
            g_shadowCleared = true;
        } else if (g_shadowCleared) {
            DWORD v = *(DWORD*)(uintptr_t)ADDR_RENDER_FLAGS;
            *(DWORD*)(uintptr_t)ADDR_RENDER_FLAGS = v | RENDER_FLAG_SHADOWS;
            g_shadowCleared = false;
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
}

void UnitHider_SetGroupList(const char* csvHexGuids) {
    int count = 0;
    if (csvHexGuids && csvHexGuids[0]) {
        char buf[2048];
        strncpy_s(buf, sizeof(buf), csvHexGuids, _TRUNCATE);
        char* ctx = nullptr;
        char* tok = strtok_s(buf, ",", &ctx);
        while (tok && count < MAX_GROUP) {
            while (*tok == ' ') ++tok;
            if (*tok) {
                uint64_t g = _strtoui64(tok, nullptr, 16); // handles optional 0x prefix
                if (g != 0) g_groupGuids[count++] = g;
            }
            tok = strtok_s(nullptr, ",", &ctx);
        }
    }
    g_groupCount = count;
}

void UnitHider_SetLocal(uint64_t localGuid, void* localPlayerObj) {
    if (!localPlayerObj || localGuid == 0) {
        g_haveLocal = false;
        g_localGuid = 0;
        g_protectedPetCount = 0;
        return;
    }
    // Always capture the local GUID (the summons-hide needs it to exempt your own
    // summons, and it must work even when distance-cull is off / no valid position).
    g_localGuid = localGuid;
    int protectedCount = 0;
    AddProtectedPetsFromPlayerObj(localPlayerObj, &protectedCount);
    for (int i = protectedCount; i < MAX_PROTECTED_PETS; ++i) g_protectedPetGuids[i] = 0;
    g_protectedPetCount = protectedCount;
    float p[3];
    if (ReadUnitPos(localPlayerObj, p) && !(p[0] == 0.0f && p[1] == 0.0f && p[2] == 0.0f)) {
        g_lx = p[0]; g_ly = p[1]; g_lz = p[2];
        g_haveLocal = true;   // have a valid position for distance checks
    } else {
        g_haveLocal = false;
    }
}

void UnitHider_ClearLocal() { g_haveLocal = false; }

// Public predicate for the spell-visual filter — true when this unit is being model-culled
// right now, so its attached spell visuals should be suppressed too. Reuses the exact same
// per-frame decision as the render hooks (ShouldCullUnit), so it stays perfectly in sync with
// what is actually hidden. SEH-guarded; file-local statics are reachable from this TU.
bool UnitHider_ShouldCullVisualHost(void* unit) {
    if (!unit || (uintptr_t)unit < 0x10000) return false;
    if (g_isProcessTerminating || !UnitCullActive()) return false;
    __try { return ShouldCullUnit(unit); } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

// True if any distance-cull / summons-hide feature is active (cheap gate for the per-frame
// spell-visual Tick suppression, so it stays a no-op when nothing is enabled).
bool UnitHider_CullActive() { return UnitCullActive(); }
