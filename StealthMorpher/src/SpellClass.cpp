#include "SpellClass.h"
#include "Logger.h"
#include <windows.h>
#include <cstring>
#include <cstdlib>
#include "../third_party/Detours/detours.h"

extern uint64_t g_playerGuid;                    // dllmain.cpp
extern "C" volatile bool g_isProcessTerminating; // dllmain.cpp
// Distance-cull predicates (UnitHider.cpp): true when this unit's MODEL is being hidden by the
// Units/Distance-Culling tab, so we suppress its attached spell visuals too (FPS).
bool UnitHider_ShouldCullVisualHost(void* unit);
bool UnitHider_CullActive();

// ============================================================================
// Descriptor / unit field offsets (3.3.5a 12340) — see RE_OPTIMIZATION_FINDINGS.md
// ============================================================================
static const uintptr_t OBJ_DESCRIPTORS = 0x08;
static const uintptr_t DESC_GUID       = 0x00;
static const uintptr_t DESC_TYPEMASK   = 0x08; // ((uint32_t*)desc)[2]
static const uintptr_t DESC_DYNOBJ_OWNER = 0x18; // DYNAMICOBJECT_CASTER / GAMEOBJECT_CREATED_BY (field OBJECT_END+0)
static const uintptr_t DESC_SUMMONEDBY = 0x38;
static const uintptr_t DESC_CREATEDBY  = 0x40;
static const uintptr_t DESC_BYTES0     = 0x5C; // b0 race, b1 class, b2 gender
enum { TYPEMASK_UNIT = 0x0008, TYPEMASK_PLAYER = 0x0010, TYPEMASK_GAMEOBJECT = 0x0020, TYPEMASK_DYNAMICOBJECT = 0x0040 };

typedef int(__thiscall* GetCreatureRank_fn)(void* unit);
static const GetCreatureRank_fn GetCreatureRank = (GetCreatureRank_fn)0x00718A00;

// CGUnit_C::GetCreatureType -> CreatureType.dbc id. Totem = 11 (3.3.5). Used to keep
// totems (yours and others') always visible — they must stay readable on the ground.
typedef int(__thiscall* GetCreatureType_fn)(void* unit);
static const GetCreatureType_fn GetCreatureType = (GetCreatureType_fn)0x0071F300;
static const int CREATURE_TYPE_TOTEM = 11;

// ClntObjMgrObjectPtr(guidLo, guidHi, typeMask, file, line) -> object* (or null).
// Lets us resolve a ground/area object's caster GUID back to the live unit so the
// effect is classified by WHO made it, not by the (untrackable) object itself.
typedef void*(__cdecl* ClntObjMgrObjectPtr_fn)(uint32_t lo, uint32_t hi, int typeMask, const char* file, int line);
static const ClntObjMgrObjectPtr_fn ClntObjMgrObjectPtr = (ClntObjMgrObjectPtr_fn)0x004D4DB0;
static inline bool IsPlayerGuid(uint64_t g) { return g != 0 && (g >> 48) == 0; }

// Spell.dbc fast-path. Used only as a safety fallback for player-carried boss debuffs:
// some encounter effects (Jaraxxus Legion Flame, BQL-style flames/shadows) are emitted
// by the debuffed player, but the active aura's Spell.dbc visual still identifies the
// boss/NPC debuff that caused it.
typedef void*(__thiscall* GetRow_fn)(void* db, uint32_t id);
static const GetRow_fn GetDbcRow = (GetRow_fn)0x0065C290;
static const uintptr_t ADDR_SPELL_DB = 0x00BA5238;
static const uint32_t SPELL_VISUAL0 = 131 * 4;
static const uint32_t SPELL_VISUAL1 = 132 * 4;

static void* ResolveUnitByGuid(uint64_t guid) {
    if (guid == 0) return nullptr;
    __try {
        return ClntObjMgrObjectPtr((uint32_t)(guid & 0xFFFFFFFFu), (uint32_t)(guid >> 32),
                                   TYPEMASK_UNIT, "", 0);
    } __except (EXCEPTION_EXECUTE_HANDLER) { return nullptr; }
}

// Resolve a GUID to ANY object type (unit, player, gameobject, dynamicobject, corpse). The 3rd
// arg of ClntObjMgrObjectPtr is a type bitmask tested `descType & mask` (RE-verified @0x4D4DF7);
// the engine itself resolves SpellVisual node endpoints with mask = 1 (the OBJECT bit, set on
// EVERY object). Mirror that here so a link/projectile whose endpoint is a ground/area object
// still resolves (Classify then maps it to its caster). Using TYPEMASK_UNIT (0x8) would miss
// GameObject/DynamicObject endpoints, dropping host context for those nodes.
static const int TYPEMASK_ANY = 0x1;
static void* ResolveAnyByGuid(uint64_t guid) {
    if (guid == 0) return nullptr;
    __try {
        return ClntObjMgrObjectPtr((uint32_t)(guid & 0xFFFFFFFFu), (uint32_t)(guid >> 32),
                                   TYPEMASK_ANY, "", 0);
    } __except (EXCEPTION_EXECUTE_HANDLER) { return nullptr; }
}

// Encounter boss list — the same list that drives the boss1..boss5 frames
// (Lua_UnitClassification / "boss%d"). This is the AUTHORITATIVE "is a boss"
// signal: many instance bosses (e.g. Lady Deathwhisper) have creature rank
// "elite", not "worldboss", so GetCreatureRank alone misclassifies them. A unit
// in this list is a real boss regardless of its rank.
//   count = *(int*)0x00C242FC ; array = *(void**)0x00C24300 ; 16-byte entries, GUID @ +0
static const uintptr_t ADDR_BOSS_COUNT = 0x00C242FC;
static const uintptr_t ADDR_BOSS_ARRAY = 0x00C24300;
static const int       BOSS_ENTRY_STRIDE = 16;

// Boss GUIDs pushed from Lua's canonical boss-frame API (UnitGUID("boss1..5")). This
// is the SAME authoritative encounter data, but read through the official API where
// it is always valid, then mirrored here — belt-and-suspenders with the direct read
// of the engine's own list below, so a unit the client treats as a boss is protected
// even if the raw global is momentarily unreadable from our thread.
static const int MAX_PUSHED_BOSS = 16;
static uint64_t  g_pushedBoss[MAX_PUSHED_BOSS] = {};
static int       g_pushedBossCount = 0;

static bool IsBossGuid(uint64_t guid) {
    if (guid == 0) return false;
    // 1) GUIDs pushed from Lua boss frames (server-API authoritative, always valid).
    for (int i = 0; i < g_pushedBossCount && i < MAX_PUSHED_BOSS; ++i)
        if (g_pushedBoss[i] == guid) return true;
    // 2) The engine's own encounter boss list (boss1..5 frame backing store).
    __try {
        int n = *reinterpret_cast<int*>(ADDR_BOSS_COUNT);
        if (n > 0 && n <= 64) {
            uint8_t* arr = *reinterpret_cast<uint8_t**>(ADDR_BOSS_ARRAY);
            if (arr && reinterpret_cast<uintptr_t>(arr) >= 0x10000) {
                for (int i = 0; i < n; ++i)
                    if (*reinterpret_cast<uint64_t*>(arr + i * BOSS_ENTRY_STRIDE) == guid) return true;
            }
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
    return false;
}

// CGUnit aura table (RE'd struct, binana profile): host + 0x0C50, 16 entries, stride
// 0x18, casterGUID @ +0, buffId @ +8. A "self-buff" is an aura whose caster IS the
// unit carrying it (its own procs / item glows / self-buffs). Incoming auras — boss
// debuffs, encounter mechanics, buffs cast on the unit by someone else — have
// caster != host and must always stay visible.
// ★ CGUnit_C aura store is a SMALL-BUFFER-OPTIMIZED array (RE-verified @0x004F88B0 / 0x0061F8D0):
//   mode = *(int32*)(unit + 0xDD0)
//     mode != -1  ⇒ INLINE: auras start at unit+0xC50, count = mode (inline capacity is 16)
//     mode == -1  ⇒ SPILLED TO HEAP: count = *(u32*)(unit+0xC54), array = *(u8**)(unit+0xC58)
//   entry stride 0x18: casterGuid @+0 (u64), spellId @+8 (u32).
// The OLD code always read the inline 0xC50 with a hardcoded 16 — so for any unit with >16 auras
// (every raider: raid buffs + flask + food + procs + boss debuffs) the auras live on the HEAP and
// 0xC50 holds STALE garbage → the boss caster is never found → the encounterAura gate fails → the
// mechanic's visual gets hidden. Reading the correct base+count is THE fix for "raid debuffs/buffs
// on players don't show".
static const uintptr_t UNIT_AURA_STRIDE   = 0x18;
static const uintptr_t UNIT_AURA_MODE     = 0x0DD0;  // -1 ⇒ heap, else inline count
static const uintptr_t UNIT_AURA_INLINE   = 0x0C50;  // inline array base
static const uintptr_t UNIT_AURA_HEAPCNT  = 0x0C54;  // heap-mode count
static const uintptr_t UNIT_AURA_HEAPPTR  = 0x0C58;  // heap-mode array ptr
static const int       UNIT_AURA_MAX      = 256;     // sanity bound on the count
// Aura-entry FLAGS byte. RE-verified against THIS wow.exe: the aura-visual classifier
// 0x0072C9B0 reads the flags byte at entry+0x0C ("movzx eax, byte ptr [esi+0xC]") and tests
// bit 0x10 to bucket the aura as POSITIVE (helpful/buff) vs harmful — `and eax,0x10` @0x72CAD0.
// (The old constant 0x14 was WRONG: entry+0x14 is the aura's expiration TIME — Lua_UnitAura
// reads it with `fild dword ptr [edi+0x14]` @0x614951.) The canonical 3.3.5a aura slot is
// {u64 caster @0, u32 spellId @8, u8 flags @0xC, u8 level @0xD, u8 stacks @0xE, u32 dur @0x10,
// u32 expire @0x14}. Bit 0x10 of the flags = AFLAG_POSITIVE. We use this only to refine the
// keep decision (and for diagnostics); the keep/hide call stays anchored on the RE-confirmed
// caster GUID (entry+0/+4, the exact field the client's 0x60B420 reads to attribute a caster).
static const uintptr_t UNIT_AURA_FLAGS    = 0x0C;    // u8 flags byte (RE: 0x72C9B0 reads entry+0xC)
static const uint8_t   AFLAG_POSITIVE     = 0x10;    // helpful/buff bit (RE: 0x72CAD0 `and eax,0x10`)

// SEH leaf: resolve the LIVE aura array (inline or heap) and its count. Returns base or nullptr.
static uint8_t* SafeAuraArray(void* host, int* outCount) {
    *outCount = 0;
    if (!host || (uintptr_t)host < 0x10000) return nullptr;
    __try {
        const int mode = *(int32_t*)((uint8_t*)host + UNIT_AURA_MODE);
        if (mode == -1) {                                            // spilled to heap
            const uint32_t c = *(uint32_t*)((uint8_t*)host + UNIT_AURA_HEAPCNT);
            uint8_t* base = *(uint8_t**)((uint8_t*)host + UNIT_AURA_HEAPPTR);
            if (!base || (uintptr_t)base < 0x10000 || c > (uint32_t)UNIT_AURA_MAX) return nullptr;
            *outCount = (int)c;
            return base;
        }
        if (mode < 0 || mode > 16) return nullptr;                   // inline count sanity (cap 16)
        *outCount = mode;
        return (uint8_t*)host + UNIT_AURA_INLINE;
    } __except (EXCEPTION_EXECUTE_HANDLER) { return nullptr; }
}

// Returns the caster GUID of the aura on `host` matching spellId, or 0 if `host`
// carries no such aura (i.e. this visual is not one of its auras).
static uint64_t GetAuraCaster(void* host, uint32_t spellId) {
    if (!host || spellId == 0) return 0;
    int count = 0;
    uint8_t* base = SafeAuraArray(host, &count);
    if (!base) return 0;
    __try {
        for (int i = 0; i < count; ++i) {
            uint8_t* e = base + i * UNIT_AURA_STRIDE;
            if (*(uint32_t*)(e + 8) == spellId) return *(uint64_t*)(e + 0);
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) { return 0; }
    return 0;
}

// Flags byte (entry+0x0C, RE-verified) of the aura on `host` matching spellId, or 0 if none.
// Bit AFLAG_POSITIVE (0x10) = helpful/buff. Used both for diagnostics and to refine the
// zero-caster keep decision below; the keep/hide call still keys primarily on the caster GUID.
static uint8_t GetAuraFlags(void* host, uint32_t spellId) {
    if (!host || spellId == 0) return 0;
    int count = 0;
    uint8_t* base = SafeAuraArray(host, &count);
    if (!base) return 0;
    __try {
        for (int i = 0; i < count; ++i) {
            uint8_t* e = base + i * UNIT_AURA_STRIDE;
            if (*(uint32_t*)(e + 8) == spellId) return *(uint8_t*)(e + UNIT_AURA_FLAGS);
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) { return 0; }
    return 0;
}

// True if the spell carries ANY SpellVisual (either SpellVisual id slot non-zero in Spell.dbc).
// Used to tell a VISUAL-BEARING aura (one that can own a persistent CSpellVisual node — the spore
// model, a debuff glow) from a visual-less stat aura (Chill of the Throne, raid auras), so the
// zero-caster keep below pins ONLY auras that actually have something to draw.
static bool SpellHasAnyVisual(uint32_t spellId) {
    if (spellId == 0) return false;
    __try {
        void* db = *reinterpret_cast<void**>(ADDR_SPELL_DB);
        if (!db) return false;
        uint8_t* row = reinterpret_cast<uint8_t*>(GetDbcRow(db, spellId));
        if (!row || reinterpret_cast<uintptr_t>(row) < 0x10000) return false;
        return *reinterpret_cast<uint32_t*>(row + SPELL_VISUAL0) != 0 ||
               *reinterpret_cast<uint32_t*>(row + SPELL_VISUAL1) != 0;
    } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

// True if `host` currently carries at least one ENCOUNTER aura — an effect applied by the fight,
// not by a player. This is what makes the persistent-visual teardown NEVER strip a mechanic off a
// player (Festergut Gas Spore, Legion Flame, raid debuff-marks, ...). An aura counts as encounter
// when its caster is:
//   • a non-player unit (NPC/boss/creature)                        — always (it is fight content), OR
//   • UNKNOWN (caster GUID 0) AND the aura bears a SpellVisual      — server/scripted mechanics
//        frequently land their aura record with NO client-side caster guid (the boss-skull caster
//        isn't transmitted to observers), so the old "skip caster==0" check silently dropped exactly
//        those auras and the spore/mark got torn down on any player the declutter was hiding. THIS
//        is the missing case behind "Gas Spore still doesn't show". We require a SpellVisual so a
//        visual-less zone debuff (Chill of the Throne) can't pin every raider's own buff glows.
// A player-cast aura — whether MINE (caster == me) or ANOTHER player's — never counts, so
// player→player and own-player buff clutter stays hideable, exactly as requested. No hardcoded ids.
static bool HostHasEncounterAura(void* host) {
    if (!host || (uintptr_t)host < 0x10000) return false;
    int count = 0;
    uint8_t* base = SafeAuraArray(host, &count);
    if (!base) return false;
    __try {
        for (int i = 0; i < count; ++i) {
            uint8_t* e = base + i * UNIT_AURA_STRIDE;
            const uint32_t spellId = *(uint32_t*)(e + 8);
            if (spellId == 0) continue;
            const uint64_t caster = *(uint64_t*)(e + 0);
            if (caster == g_playerGuid) continue;       // my own buff — not encounter (hideable)
            if (IsPlayerGuid(caster)) continue;         // another player's buff — not encounter
            if (caster != 0) return true;               // NPC/boss/creature-cast ⇒ mechanic present
            if (SpellHasAnyVisual(spellId)) return true; // unknown-caster mechanic that has a visual
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
    return false;
}

// Max-health read — mirrors the client's own Lua_UnitHealthMax (0x0060EC60):
//   maxHealth = *(uint32*)( *(void**)(unit + 0xD0) + 0x68 )
// (verified by disassembly). Used for a SERVER-INDEPENDENT boss signal: on servers
// that don't transmit boss frames (engine boss list empty), a raid/dungeon boss is
// still identifiable because its max health dwarfs a player's. No hardcoded IDs.
static const uintptr_t UNIT_STATS_BLOCK = 0xD0;
static const uintptr_t STATS_MAXHEALTH  = 0x68;
static uint32_t ReadMaxHealth(void* obj) {
    if (!obj || (uintptr_t)obj < 0x10000) return 0;
    __try {
        uint8_t* blk = *(uint8_t**)((uint8_t*)obj + UNIT_STATS_BLOCK);
        if (!blk || (uintptr_t)blk < 0x10000) return 0;
        return *(uint32_t*)(blk + STATS_MAXHEALTH);
    } __except (EXCEPTION_EXECUTE_HANDLER) { return 0; }
}

static volatile bool g_bossByHealth = false;         // health heuristic OFF (caused elite false-positives); IsBossMob is authoritative
// (health heuristic retained for diagnostics only; default OFF — see IsBossMob)
static const uint32_t BOSS_HP_FLOOR = 800000u;
static bool IsBossByHealth(void* obj) {
    if (!g_bossByHealth) return false;
    uint32_t mh = ReadMaxHealth(obj);
    return mh >= BOSS_HP_FLOOR;
}

// AUTHORITATIVE boss flag — mirrors the client's own boss-skull predicate @ 0x00715D70
// (the function that makes the target portrait show the "??" boss skull, RE-verified):
//     creatureInfo = *(unit + 0x964);            // same ptr GetCreatureRank uses
//     boss = (*(uint32*)(creatureInfo + 0x0C) >> 2) & 1;   // CreatureType type_flags BOSS (0x4)
// This is real server creature data transmitted to the client. It is set on actual
// encounter bosses (Lady Deathwhisper shows the skull) but NOT on trash or elite ADDS,
// and it does NOT depend on the boss-frame list. No hardcoded IDs, no health guessing.
static const uintptr_t UNIT_CREATUREINFO = 0x964;
static const uintptr_t CINFO_TYPEFLAGS   = 0x0C;
static const uint32_t  CTYPEFLAG_BOSS    = 0x4;
static bool IsBossMob(void* obj) {
    if (!obj || (uintptr_t)obj < 0x10000) return false;
    __try {
        uint8_t* ci = *(uint8_t**)((uint8_t*)obj + UNIT_CREATUREINFO);
        if (!ci || (uintptr_t)ci < 0x10000) return false;
        return (*(uint32_t*)(ci + CINFO_TYPEFLAGS) & CTYPEFLAG_BOSS) != 0;
    } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

// ============================================================================
// Encounter-add detection (no hardcoded ids) — the fix for "Raging Spirit / boss adds
// hidden on Lich King transition".
// ----------------------------------------------------------------------------
// CGUnit_C::UnitReaction @0x007251C0 — __thiscall(this=observer, other) -> EUnitReaction
// (1 HATED .. 8 EXALTED; <=3 = hostile/unfriendly, 4 = neutral, >=5 = friendly). RE-verified
// against THIS wow.exe (faction-template compare; returns 4 for self/same-faction, computes the
// rest from the two units' FactionTemplateRec). This is the SAME predicate the client uses to
// colour nameplates, so it is authoritative and needs no spell/creature ids.
typedef int(__thiscall* UnitReaction_fn)(void* self, void* other);
static const UnitReaction_fn CGUnit_UnitReaction = (UnitReaction_fn)0x007251C0;
enum { REACTION_HOSTILE_MAX = 3 };   // <=3 ⇒ hated/hostile/unfriendly = an enemy to us

// Resolve the LOCAL player object (cached per render frame is unnecessary — objmgr lookup is a
// hash probe). Players carry the UNIT bit, so TYPEMASK_UNIT resolves us correctly.
static void* LocalPlayerObj() {
    if (g_playerGuid == 0) return nullptr;
    return ResolveUnitByGuid(g_playerGuid);
}

// True when `unit` is HOSTILE to the local player (an enemy add / mob), false for friendly pets,
// neutral wildlife, other players, and when reaction can't be determined (fail-safe: NOT enemy).
// A real friendly summon (ghoul, water elemental, Mirror Image) is reaction >=5; a Lich King
// Raging Spirit ("rips out a piece of the target's spirit" — its createdBy is the VICTIM PLAYER,
// which otherwise misclassifies it as that player's pet) is HOSTILE, so this cleanly separates
// "encounter add spawned from a player" from "a player's pet".
static bool IsEnemyUnit(void* unit) {
    if (!unit || (uintptr_t)unit < 0x10000) return false;
    __try {
        void* descV = *(void**)((uint8_t*)unit + OBJ_DESCRIPTORS);
        if (!descV || (uintptr_t)descV < 0x10000) return false;
        const uint32_t tm = *(uint32_t*)((uint8_t*)descV + DESC_TYPEMASK);
        if (!(tm & TYPEMASK_UNIT) || (tm & TYPEMASK_PLAYER)) return false;  // NPC/creature only
        void* me = LocalPlayerObj();
        if (!me || me == unit) return false;
        const int reaction = CGUnit_UnitReaction(me, unit);
        return reaction >= 1 && reaction <= REACTION_HOSTILE_MAX;
    } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

// Self-maintaining "a boss encounter is in progress" flag — stamped whenever a unit is positively
// identified as a boss (boss-frame list OR the server boss type-flag/skull), which happens every
// frame during a fight because the boss's own model + persistent visuals tick continuously through
// these hooks. Expires shortly after the boss dies or you leave. No enumeration, no boss frames
// required (covers servers that don't transmit boss1..5). Boss-frame servers also short-circuit to
// true instantly via the live list, so a brand-new pull is covered before any boss visual ticks.
static volatile DWORD g_lastBossSeenMs = 0;
static const DWORD    BOSS_ACTIVE_WINDOW_MS = 6000;
static inline void NoteBossSeen() { g_lastBossSeenMs = GetTickCount(); }

bool SpellClass_IsBossEncounterActive() {
    if (g_pushedBossCount > 0) return true;                 // Lua boss-frame list (authoritative)
    __try {
        const int n = *reinterpret_cast<int*>(ADDR_BOSS_COUNT);
        if (n > 0 && n <= 64) {
            uint8_t* arr = *reinterpret_cast<uint8_t**>(ADDR_BOSS_ARRAY);
            if (arr && reinterpret_cast<uintptr_t>(arr) >= 0x10000) return true;
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
    const DWORD seen = g_lastBossSeenMs;
    return seen != 0 && (GetTickCount() - seen) < BOSS_ACTIVE_WINDOW_MS;
}

// Exposed for UnitHider (model culling) so the SAME enemy-add definition keeps a Raging Spirit's
// MODEL visible too — its createdBy=player otherwise makes the summon-hide cull it.
bool SpellClass_IsEnemyUnit(void* unit) { return IsEnemyUnit(unit); }

// True when `unit` is an ENCOUNTER ADD that must never be hidden: a hostile NPC while a boss
// encounter is active. Scoped to boss fights so the per-creature-grade declutter still works on
// ordinary trash outside encounters; inside an encounter every hostile creature is fight content.
static bool IsProtectedEncounterAdd(void* unit) {
    if (!unit || (uintptr_t)unit < 0x10000) return false;
    if (!SpellClass_IsBossEncounterActive()) return false;
    return IsEnemyUnit(unit);
}

// SpellVisual kit field byte offsets within the 128-byte row.
static const uint32_t KIT_PRECAST       = 0x04;
static const uint32_t KIT_CAST          = 0x08;
static const uint32_t KIT_IMPACT        = 0x0C;
static const uint32_t KIT_STATE         = 0x10; // aura start
static const uint32_t KIT_STATE_DONE    = 0x14; // aura end
static const uint32_t KIT_CHANNEL       = 0x18;
static const uint32_t FLD_HAS_MISSILE   = 0x1C;
static const uint32_t FLD_MISSILE_MODEL = 0x20;
static const uint32_t FLD_MISSILE_SOUND = 0x2C;
static const uint32_t FLD_ANIM_SOUND    = 0x30;
static const uint32_t KIT_CASTER_IMPACT = 0x38;
static const uint32_t KIT_TARGET_IMPACT = 0x3C;
static const uint32_t KIT_MISSILE_MARK  = 0x58;
static const uint32_t KIT_AREA_INSTANT  = 0x5C;
static const uint32_t KIT_AREA_IMPACT   = 0x60;
static const uint32_t KIT_AREA_PERSIST  = 0x64;
static const size_t   ROW_SIZE          = 128;

// ============================================================================
// State (main-thread only: command path + render pass share that thread).
// ============================================================================
static volatile bool g_masterEnabled = false;
// Auto-armed diagnostic budget: when filtering is switched on we log the first N SpellVisualsTick
// nodes (host class + node GUID table + teardown decision) so a single test session reveals where
// a persistent visual (Shadowform/Shadowmourne) lives and why it is/ isn't removed. 0 = silent.
static volatile int g_vdiagBudget = 0;
// "Hide other players' attack animations" — independent tickable option (SC_SWING).
static volatile bool g_hideOtherSwing = false;

// BOARD ("By Unit Class" tab): per-row categories applied only to SELECTED rows.
static bool g_boardCat[SCAT_COUNT]     = {};
static bool g_boardHideAll             = false;
static bool g_selected[SC_CLASS_COUNT] = {};
// SIMPLE (left-column "All Units" toggles): categories applied to every NON-protected
// unit when g_applyAll is on (other players, their pets, trash/elite/rare). Self, own
// pet, group, totems, real encounter bosses and world effects are NEVER touched.
// The two stores are independent so neither UI clobbers the other on resync.
static bool g_simpleCat[SCAT_COUNT]    = {};
static bool g_simpleHideAll            = false;
static bool g_applyAll                 = false;

static const int MAX_GROUP = 64;
static uint64_t  g_groupGuids[MAX_GROUP] = {};
static int       g_groupCount = 0;

// Per-call scratch rows: the engine consumes the returned row synchronously while
// spawning the visual, so a small round-robin pool never aliases live reads. This
// is what makes hiding PER-INSTANCE: the shared DBC row is never mutated, so the
// same spell cast by a selected unit and an unselected unit yields different results.
static uint8_t  g_scratch[32][ROW_SIZE];
static unsigned g_scratchIdx = 0;

// Plain main-thread global (the command path AND the whole render/SpellVisualsTick pass run on
// the game's single main thread). Deliberately NOT thread_local: the channel re-resolution hook
// hk_7FEC00 sets it from __declspec(naked) asm, which cannot reach a TLS slot. The __fastcall
// emitter hooks still save/restore it around their call, so nesting is correct.
static void* g_host = nullptr; // unit a visual is being played on

// ============================================================================
// Classification
// ============================================================================
static bool IsGroupMember(uint64_t guid) {
    if (guid == 0) return false;
    for (int i = 0; i < g_groupCount && i < MAX_GROUP; ++i)
        if (g_groupGuids[i] == guid) return true;
    return false;
}

static bool SpellUsesVisual(uint32_t spellId, uint32_t visualId) {
    if (spellId == 0 || visualId == 0) return false;
    __try {
        void* db = *reinterpret_cast<void**>(ADDR_SPELL_DB);
        if (!db) return false;
        uint8_t* row = reinterpret_cast<uint8_t*>(GetDbcRow(db, spellId));
        if (!row || reinterpret_cast<uintptr_t>(row) < 0x10000) return false;
        return *reinterpret_cast<uint32_t*>(row + SPELL_VISUAL0) == visualId ||
               *reinterpret_cast<uint32_t*>(row + SPELL_VISUAL1) == visualId;
    } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

// Exact aura spell-id match first. If the visual request uses a triggered/helper spell
// id, fall back to matching the active aura's Spell.dbc visual ids against this row.
static uint64_t GetAuraCasterForVisual(void* host, uint32_t spellId, uint32_t visualId, uint32_t* outAuraSpellId) {
    if (outAuraSpellId) *outAuraSpellId = 0;
    uint64_t caster = GetAuraCaster(host, spellId);
    if (caster != 0) {
        if (outAuraSpellId) *outAuraSpellId = spellId;
        return caster;
    }
    if (!host || visualId == 0) return 0;
    int count = 0;
    uint8_t* base = SafeAuraArray(host, &count);
    if (!base) return 0;
    __try {
        for (int i = 0; i < count; ++i) {
            uint8_t* e = base + i * UNIT_AURA_STRIDE;
            const uint64_t auraCaster = *(uint64_t*)(e + 0);
            const uint32_t auraSpellId = *(uint32_t*)(e + 8);
            if (auraCaster != 0 && auraSpellId != 0 && SpellUsesVisual(auraSpellId, visualId)) {
                if (outAuraSpellId) *outAuraSpellId = auraSpellId;
                return auraCaster;
            }
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) { return 0; }
    return 0;
}

static int PcRow(int classId) {
    switch (classId) {
        case 1:  return SC_PC_WARRIOR;
        case 2:  return SC_PC_PALADIN;
        case 3:  return SC_PC_HUNTER;
        case 4:  return SC_PC_ROGUE;
        case 5:  return SC_PC_PRIEST;
        case 6:  return SC_PC_DK;
        case 7:  return SC_PC_SHAMAN;
        case 8:  return SC_PC_MAGE;
        case 9:  return SC_PC_WARLOCK;
        case 11: return SC_PC_DRUID;
        default: return -1;
    }
}

// Returns the primary SC_* row for `obj`, or -1 to force show. For players,
// *outClassId receives the WoW class id (1..11) so the caller can also fold in
// the player-class row.
static int Classify(void* obj, int* outClassId) {
    if (outClassId) *outClassId = 0;
    if (!obj || (uintptr_t)obj < 0x10000) return -1;
    __try {
        void* descV = *(void**)((uint8_t*)obj + OBJ_DESCRIPTORS);
        if (!descV || (uintptr_t)descV < 0x10000) return -1;
        uint8_t* desc = (uint8_t*)descV;

        const uint64_t guid     = *(uint64_t*)(desc + DESC_GUID);
        const uint32_t typeMask = *(uint32_t*)(desc + DESC_TYPEMASK);

        if (guid != 0 && guid == g_playerGuid) return SC_SELF;

        if (typeMask & TYPEMASK_PLAYER) {
            if (IsGroupMember(guid)) return SC_GROUP;
            if (outClassId) *outClassId = desc[DESC_BYTES0 + 1];
            return SC_PLAYER;
        }

        if (typeMask & TYPEMASK_UNIT) {
            // Totems are never hidden (yours or anyone's) — they must stay visible on
            // the ground as readable mechanics/utility.
            int ctype = 0;
            __try { ctype = GetCreatureType(obj); } __except (EXCEPTION_EXECUTE_HANDLER) { ctype = 0; }
            if (ctype == CREATURE_TYPE_TOTEM) return -1;

            // Real encounter boss (boss1..5 list) — authoritative, overrides rank so
            // bosses that are only "elite" in creature data still classify as bosses.
            if (IsBossGuid(guid)) { NoteBossSeen(); return SC_WORLDBOSS; }
            // Authoritative, server-independent: the CreatureType BOSS type-flag (the same
            // bit that draws the portrait "??" skull). Catches bosses the boss-frame list
            // misses (Lady Deathwhisper) WITHOUT flagging elite adds. (Health stays off.)
            if (IsBossMob(obj) || IsBossByHealth(obj)) { NoteBossSeen(); return SC_WORLDBOSS; }

            const uint64_t summonedBy = *(uint64_t*)(desc + DESC_SUMMONEDBY);
            const uint64_t createdBy  = *(uint64_t*)(desc + DESC_CREATEDBY);
            const uint64_t owner = summonedBy ? summonedBy : createdBy;
            // A unit OWNED by a player is that player's pet/summon — UNLESS it is a protected
            // encounter add (a HOSTILE NPC during a boss fight). A Lich King Raging Spirit "rips
            // out a piece of the target's spirit", so its createdBy is the VICTIM PLAYER, which
            // would otherwise classify it as that player's pet (SC_PLAYER_PET) and hide it with
            // "hide player pets" / hide-all. Such adds fall through to the grade rows, where
            // HostBossProtected (→ IsProtectedEncounterAdd) keeps them fully visible. Scoped to
            // encounters so ordinary (incl. PvP enemy) pets keep their normal classification.
            if (owner != 0 && !IsProtectedEncounterAdd(obj)) {
                if (owner == g_playerGuid) return SC_OWN_PET;
                if (IsGroupMember(owner))  return SC_GROUP;
                if (IsPlayerGuid(owner))   return SC_PLAYER_PET;
            }
            int rank = 0;
            __try { rank = GetCreatureRank(obj); }
            __except (EXCEPTION_EXECUTE_HANDLER) { rank = 0; }
            if (rank < 0 || rank > 5) rank = 0;          // clamp to known grades
            return SC_GRADE_BASE + rank;                  // 0..5 -> SC_NORMAL..SC_TRIVIAL
        }

        // Ground / area effects (Consecration, Blizzard, traps, banners...) are not
        // units — but they carry the caster's GUID. Resolve it and classify the
        // CASTER, so "hide area effects from <class>" works. Ownerless / unresolved
        // world hazards fall through to show (fail-safe).
        if (typeMask & (TYPEMASK_DYNAMICOBJECT | TYPEMASK_GAMEOBJECT)) {
            const uint64_t owner = *(uint64_t*)(desc + DESC_DYNOBJ_OWNER);
            if (owner != 0) {
                void* ownerObj = ResolveUnitByGuid(owner);
                if (ownerObj && ownerObj != obj) return Classify(ownerObj, outClassId);
            }
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return -1;
    }
    return -1; // unresolved / corpse / ownerless world effect -> fail-safe show
}

// ============================================================================
// Decision (per-instance; never mutates the shared row)
// ============================================================================
static inline void ClearKit(uint8_t* row, uint32_t off) { *(int32_t*)(row + off) = 0; }

static void ApplyHiddenCats(uint8_t* row, const bool* cats) {
    if (cats[SCAT_PRECAST])        ClearKit(row, KIT_PRECAST);
    if (cats[SCAT_CAST])           ClearKit(row, KIT_CAST);
    if (cats[SCAT_CHANNEL])        ClearKit(row, KIT_CHANNEL);
    if (cats[SCAT_AURA_START])     ClearKit(row, KIT_STATE);
    if (cats[SCAT_AURA_END])       ClearKit(row, KIT_STATE_DONE);
    if (cats[SCAT_IMPACT])         ClearKit(row, KIT_IMPACT);
    if (cats[SCAT_IMPACT_CASTER])  ClearKit(row, KIT_CASTER_IMPACT);
    if (cats[SCAT_IMPACT_TARGET])  ClearKit(row, KIT_TARGET_IMPACT);
    if (cats[SCAT_AREA_INSTANT])   ClearKit(row, KIT_AREA_INSTANT);
    if (cats[SCAT_AREA_IMPACT])    ClearKit(row, KIT_AREA_IMPACT);
    if (cats[SCAT_AREA_PERSISTENT])ClearKit(row, KIT_AREA_PERSIST);
    if (cats[SCAT_MISSILE])      { ClearKit(row, FLD_HAS_MISSILE); ClearKit(row, FLD_MISSILE_MODEL); }
    if (cats[SCAT_MISSILE_MARKER]) ClearKit(row, KIT_MISSILE_MARK);
    if (cats[SCAT_SOUND_MISSILE])  ClearKit(row, FLD_MISSILE_SOUND);
    if (cats[SCAT_SOUND_EVENT])    ClearKit(row, FLD_ANIM_SOUND);
}

// True if a unit classified as (prim, classId) is one the user selected to hide.
//
// SC_ALL is a "hide other-player clutter" button: it applies ONLY to other players
// and their pets/summons — NEVER to your own, your group, or to ANY NPC (trash,
// elite, rare, boss). NPC creature grades are hidden ONLY when their exact grade row
// is explicitly ticked. This is deliberate: it guarantees that "hide everything" can
// never silently swallow encounter mechanics, boss casts, or ground hazards — the #1
// thing the user must always be able to see.
static bool RowSelected(int prim, int classId) {
    if (prim < 0) return false;
    if (g_selected[prim]) return true;
    int sec = (prim == SC_PLAYER) ? PcRow(classId) : -1;
    if (sec >= 0 && g_selected[sec]) return true;
    if (g_selected[SC_ALL] && (prim == SC_PLAYER || prim == SC_PLAYER_PET)) return true;
    return false;
}

// Rows the simple "apply to all" mode touches: every other unit that is safe to
// declutter — other players, their pets/summons, and trash/elite/rare creatures.
// NEVER yourself, your pet, your group, or a (rank-3) world boss; encounter bosses,
// totems and world effects are already protected upstream.
static bool AppliesToAll(int prim) {
    switch (prim) {
        case SC_PLAYER: case SC_PLAYER_PET:
        case SC_NORMAL: case SC_ELITE: case SC_RAREELITE: case SC_RARE: case SC_TRIVIAL:
            return true;
        default:
            return false; // SELF, OWN_PET, GROUP, WORLDBOSS, ALL
    }
}

// True if a primary row is a PLAYER-controlled source (you, your pet, group, other
// players, their pets). Ground/area effects are hidden ONLY for these — every NPC
// (trash, elite ADD, rare, boss) keeps its ground effects so encounter mechanics
// (Marrowgar Coldflame, Defile, Void Zones, etc.) are always visible.
static bool IsPlayerSourcePrim(int prim) {
    switch (prim) {
        case SC_SELF: case SC_OWN_PET: case SC_GROUP: case SC_PLAYER: case SC_PLAYER_PET:
            return true;
        default:
            return false;
    }
}

// How a unit is targeted by the two filters (independent, composable).
struct HideSource { bool bySimple; bool byRow; bool any() const { return bySimple || byRow; } };
static HideSource ClassifyHideSource(int prim, int classId) {
    HideSource h{ false, false };
    if (prim < 0) return h;
    h.bySimple = g_applyAll && AppliesToAll(prim);
    h.byRow    = RowSelected(prim, classId);
    return h;
}

// BOSS HARD PROTECTION (overrides every selection/category): a visual is ALWAYS shown
// when its host — or the unit that owns/summoned/cast it — is a real encounter boss
// (boss1..5 frame list, boss type-flag, or boss-owned orb/ground effect). This keeps
// boss mechanics, boss-spawned orbs and boss ground effects (Consecration-style
// DynObjects, Meteor pools, etc.) visible no matter what the user hides. Totems are
// already exempted in Classify(). NOTE: this intentionally does NOT special-case the
// local player — self handling is finer-grained in DecideRow (my own casts/auras are
// always shown, but a buff ANOTHER player put on me is hideable).
static bool HostBossProtected(void* obj) {
    if (!obj || (uintptr_t)obj < 0x10000) return false;
    __try {
        void* descV = *(void**)((uint8_t*)obj + OBJ_DESCRIPTORS);
        if (!descV || (uintptr_t)descV < 0x10000) return false;
        uint8_t* desc = (uint8_t*)descV;
        const uint64_t guid = *(uint64_t*)(desc + DESC_GUID);
        if (IsBossGuid(guid)) { NoteBossSeen(); return true; }   // the boss unit itself
        const uint32_t tm = *(uint32_t*)(desc + DESC_TYPEMASK);
        if (tm & TYPEMASK_UNIT) {
            if (IsBossMob(obj) || IsBossByHealth(obj)) { NoteBossSeen(); return true; }  // boss type-flag (skull)
            // boss-spawned NPC props (orbs, beasts, etc.) inherit boss protection
            const uint64_t s = *(uint64_t*)(desc + DESC_SUMMONEDBY);
            const uint64_t c = *(uint64_t*)(desc + DESC_CREATEDBY);
            if (IsBossGuid(s) || IsBossGuid(c)) return true;
            void* owner = ResolveUnitByGuid(s ? s : c);
            if (owner && owner != obj && (IsBossMob(owner) || IsBossByHealth(owner))) return true;
            // ENCOUNTER ADD (no hardcoded ids): a HOSTILE NPC while a boss fight is in progress is
            // fight content (Lich King Raging Spirit / Val'kyr, Festergut/Rotface adds, etc.) and
            // must never be hidden by the creature-grade rows, hide-all, or the summon-hide — even
            // when its summoner/creator GUID is a PLAYER (Raging Spirit spawns FROM a raid member).
            // Scoped to active encounters so ordinary trash can still be decluttered out of combat.
            if (IsProtectedEncounterAdd(obj)) return true;
        }
        if (tm & (TYPEMASK_DYNAMICOBJECT | TYPEMASK_GAMEOBJECT)) {
            // ground/area effect created by a boss -> always visible
            const uint64_t o = *(uint64_t*)(desc + DESC_DYNOBJ_OWNER);
            if (IsBossGuid(o)) return true;
            void* owner = ResolveUnitByGuid(o);
            if (owner && owner != obj && (IsBossMob(owner) || IsBossByHealth(owner))) return true;
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
    return false;
}

// As above, but ALSO protects the local player. Used when classifying the CASTER of an
// aura (a boss/NPC/me casting on someone): my own casts and boss casts both stay shown.
static bool HostHardProtected(void* obj) {
    if (!obj || (uintptr_t)obj < 0x10000) return false;
    __try {
        void* descV = *(void**)((uint8_t*)obj + OBJ_DESCRIPTORS);
        if (descV && (uintptr_t)descV >= 0x10000) {
            const uint64_t guid = *(uint64_t*)((uint8_t*)descV + DESC_GUID);
            if (guid != 0 && guid == g_playerGuid) return true;
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
    return HostBossProtected(obj);
}

void* SpellClass_DecideRow(uint32_t spellId, uint32_t visualId,
                           void* originalRow, void* nullRow, bool protectedHost) {
    void* host = g_host;

    // BOSS / SELF HARD PROTECTION — evaluated FIRST, before distance-culling and before the
    // board filter. A real encounter boss (boss-frame list or the server boss-skull type-flag),
    // the local player, and anything a boss owns / summons / casts (orbs, ground pools, area
    // telegraphs) ALWAYS show every visual. This is what keeps a FAR boss's mechanic visible
    // even when the Distance-Culling tab is hiding far NPC models — Thorim perched on his
    // balcony, Algalon's Cosmic Smash — and it can never be overridden by "hide all" or a
    // ticked creature-grade row. (HostHardProtected resolves the boss through DynObject /
    // GameObject and summon owners, so boss-spawned orbs / pools are covered too.)
    if (originalRow && host && HostHardProtected(host)) return originalRow;

    // DISTANCE-CULL FPS INTEGRATION (independent of the board, independent of protectedHost).
    // If this visual's host unit is far enough that the Units/Distance-Culling tab is already
    // hiding its MODEL, suppress the whole visual too — auras, buff glows, casts, channels,
    // weapon effects. The engine renders those via SpellVisualsTick separately from the model,
    // so a "hidden" unit otherwise keeps paying a full per-frame visual cost. Safe: the local
    // player and units it owns are never culled (so your own visuals are untouched), bosses are
    // hard-protected above, and a non-boss unit far enough to be model-culled is never a
    // mechanic you can see — this only removes work for things already invisible.
    if (host && nullRow && UnitHider_ShouldCullVisualHost(host)) return nullRow;

    if (!g_masterEnabled || protectedHost || !originalRow) return originalRow;
    if (!host) return originalRow;                 // no host context -> fail-safe show
    // (boss / self already hard-protected above)

    int classId = 0;
    int prim = Classify(host, &classId);
    if (prim < 0) return originalRow;              // unresolved / non-unit / totem -> show

    HideSource src = ClassifyHideSource(prim, classId);
    if (!src.any()) return originalRow;            // host not a hide target

    // "Hide all" no longer blanket-nulls the whole visual (that nuked encounter ground
    // effects). Instead it enables EVERY category, then the per-category safety gates
    // below (area-from-players-only, aura-from-players-only) still apply — so boss/add
    // ground mechanics survive even with "hide everything" on.
    const bool hideAll = (src.bySimple && g_simpleHideAll) || (src.byRow && g_boardHideAll);

    // Effective category set = union of whichever filter(s) matched this unit.
    bool cats[SCAT_COUNT];
    for (int i = 0; i < SCAT_COUNT; ++i)
        cats[i] = hideAll || (src.bySimple && g_simpleCat[i]) || (src.byRow && g_boardCat[i]);

    uint32_t auraSpellId = 0;
    const uint64_t auraCaster = GetAuraCasterForVisual(host, spellId, visualId, &auraSpellId);

    // Bounded "know the debuff" diagnostic (auto-armed with the filter; budget shared with the
    // node diag). For an AURA visual on an OTHER player we log the attributed aura, its caster, the
    // player/NPC verdict, and the client's own flags byte (entry+0x14, the field UnitDebuff reads).
    // This makes encounter-debuff detection observable in <wow>\TSM_logs without changing behaviour
    // — the keep/hide call below still uses ONLY the caster GUID (the client's own attribution).
    if (g_vdiagBudget > 0 && (cats[SCAT_AURA_START] || cats[SCAT_AURA_END]) && auraSpellId != 0) {
        g_vdiagBudget--;
        const uint8_t aflags = GetAuraFlags(host, auraSpellId);
        Log("[SC-AURA] host=%p spell=%u viz=%u auraSpell=%u caster=%016llX isPlayerCaster=%d isMine=%d flags=0x%02X",
            host, spellId, visualId, auraSpellId, (unsigned long long)auraCaster,
            (int)IsPlayerGuid(auraCaster), (int)(auraCaster == g_playerGuid), (unsigned)aflags);
    }

    // Player-carried encounter debuffs: Jaraxxus Legion Flame / BQL-style effects are
    // hosted on the affected player, but the active aura caster is an NPC/boss. Keep the
    // whole visual row, including area/impact kits, even when that player is selected by
    // hide-all. This is deliberately broader than the ground-object owner check above.
    if (auraCaster != 0 && auraCaster != g_playerGuid) {
        bool encounterAura = !IsPlayerGuid(auraCaster) || IsBossGuid(auraCaster);
        if (!encounterAura) {
            void* casterObj = ResolveUnitByGuid(auraCaster);
            encounterAura = casterObj && HostHardProtected(casterObj);
        }
        if (encounterAura) return originalRow;
    }

    // Auras (buffs/debuffs/procs) on a hide-target player. A positively NPC/boss/add-cast aura has
    // ALREADY returned above (encounterAura → full show). What remains is hidden ONLY when we
    // POSITIVELY attributed it to a player who is not me (a self-buff, a player→player buff). An
    // UNATTRIBUTED aura (auraCaster == 0) is SHOWN here — this is critical and is THE fix for
    // "Festergut Gas Spore / raid debuff-marks on players don't show":
    //   A boss debuff's STATE visual is frequently emitted in the SAME frame its aura record lands,
    //   so the per-visual lookup above briefly returns 0 (caster unknown). If we cleared the aura
    //   kit here, NO persistent CSpellVisual node would ever be created, and the per-frame node path
    //   (hk_7FAE90 → ShouldTearDownHostVisual, which keeps it via HostHasEncounterAura) would have
    //   nothing to preserve → the spore/mark is hidden FOREVER. By showing the unattributed aura we
    //   let the node be built; the node path then makes the real decision every frame — a boss
    //   debuff is kept, a player self-buff that merely raced its aura record is torn down next frame.
    // This does NOT leak the player-buff CATEGORY: a normal player self-buff/proc IS attributable
    // (its aura sits on the unit cast by itself ⇒ auraCaster != 0, != me ⇒ hidden here, no flicker).
    // Procs/auto-attacks flow through their own kit chokepoints (0x745230/0x73A6C0), unaffected.
    if (cats[SCAT_AURA_START] || cats[SCAT_AURA_END]) {
        const bool hideAura = (auraCaster != 0 && auraCaster != g_playerGuid);  // hide only POSITIVELY player-attributed; show unknown (build the node)
        if (!hideAura) { cats[SCAT_AURA_START] = false; cats[SCAT_AURA_END] = false; }
    }

    // GROUND / AREA EFFECTS: hide ONLY when the caster is a player or player-pet.
    // The host classification (prim) is the resolved caster (DynObjects/GameObjects are
    // resolved to their owner in Classify). If that caster is ANY NPC — trash, elite
    // ICC ADD, rare, or boss — the area kits are kept so the encounter mechanic stays
    // visible. This is the core "don't hide boss/add ground effects" guarantee and it
    // holds even under hide-all. ("Area effects are mostly from players; anything not
    // from a player, we keep.") A player-BORNE boss area debuff (Jaraxxus Legion Flame
    // fire) is kept WITHOUT a per-unit flag: either its DynObject host resolves to the
    // boss caster here (prim → WORLDBOSS, not a player source), or its aura caster matched
    // above and the whole row already returned (encounterAura). We do NOT use the broad
    // HostHasEncounterAura flag — in a raid it is true for nearly every player, so it would
    // leak every player's own ground AOE (Consecration, Blizzard, Death and Decay).
    if (cats[SCAT_AREA_INSTANT] || cats[SCAT_AREA_IMPACT] || cats[SCAT_AREA_PERSISTENT]) {
        if (!IsPlayerSourcePrim(prim)) {
            cats[SCAT_AREA_INSTANT] = false;
            cats[SCAT_AREA_IMPACT] = false;
            cats[SCAT_AREA_PERSISTENT] = false;
        }
    }

    bool any = false;
    for (int i = 0; i < SCAT_COUNT; ++i) { if (cats[i]) { any = true; break; } }
    if (!any) return originalRow;

    // Per-instance hide: clear the selected kits on a private copy of the row so the
    // shared client DBC row is never mutated (no cross-unit bleed, no restore logic).
    unsigned slot = g_scratchIdx++ & 31u;
    uint8_t* scratch = g_scratch[slot];
    std::memcpy(scratch, originalRow, ROW_SIZE);
    ApplyHiddenCats(scratch, cats);
    return scratch;
}

// ============================================================================
// Configuration
// ============================================================================
bool SpellClass_HostIsLocalPlayer() {
    void* h = g_host;
    if (!h || (uintptr_t)h < 0x10000) return false;
    __try {
        void* descV = *(void**)((uint8_t*)h + OBJ_DESCRIPTORS);
        if (!descV || (uintptr_t)descV < 0x10000) return false;
        const uint64_t guid = *(uint64_t*)((uint8_t*)descV + DESC_GUID);
        return guid != 0 && guid == g_playerGuid;
    } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

void SpellClass_SetMasterEnabled(bool on) {
    const bool was = g_masterEnabled;
    g_masterEnabled = on;
    if (on) {
        g_vdiagBudget = 400;
        if (!was) SpellClass_RefreshOtherPlayerItemVisuals();  // retroactively re-create existing visuals under the filter
    }
}
bool SpellClass_GetMasterEnabled() { return g_masterEnabled; }

void SpellClass_SetHideOtherSwing(bool on) { g_hideOtherSwing = on; }

void SpellClass_SetGlobalCategory(int cat, bool hide) {
    if (cat < 0 || cat >= SCAT_COUNT) return;
    g_boardCat[cat] = hide;
}
void SpellClass_SetGlobalHideAll(bool hide) { g_boardHideAll = hide; }
void SpellClass_SetApplyAll(bool on) { g_applyAll = on; }
void SpellClass_SetBossByHealth(bool on) { g_bossByHealth = on; }

// SIMPLE (left-column "All Units") category/hide-all — kept separate from the board.
void SpellClass_SetSimpleCategory(int cat, bool hide) {
    if (cat < 0 || cat >= SCAT_COUNT) return;
    g_simpleCat[cat] = hide;
}
void SpellClass_SetSimpleHideAll(bool hide) { g_simpleHideAll = hide; }

void SpellClass_SetSelected(int row, bool selected) {
    if (row < 0 || row >= SC_CLASS_COUNT) return;
    g_selected[row] = selected;
}

void SpellClass_SetBossList(const char* csvHexGuids) {
    int count = 0;
    if (csvHexGuids && csvHexGuids[0]) {
        char buf[1024];
        strncpy_s(buf, sizeof(buf), csvHexGuids, _TRUNCATE);
        char* ctx = nullptr;
        char* tok = strtok_s(buf, ",", &ctx);
        while (tok && count < MAX_PUSHED_BOSS) {
            while (*tok == ' ') ++tok;
            if (*tok) {
                uint64_t g = _strtoui64(tok, nullptr, 16);
                if (g != 0) g_pushedBoss[count++] = g;
            }
            tok = strtok_s(nullptr, ",", &ctx);
        }
    }
    g_pushedBossCount = count;
}

void SpellClass_SetGroupList(const char* csvHexGuids) {
    int count = 0;
    if (csvHexGuids && csvHexGuids[0]) {
        char buf[2048];
        strncpy_s(buf, sizeof(buf), csvHexGuids, _TRUNCATE);
        char* ctx = nullptr;
        char* tok = strtok_s(buf, ",", &ctx);
        while (tok && count < MAX_GROUP) {
            while (*tok == ' ') ++tok;
            if (*tok) {
                uint64_t g = _strtoui64(tok, nullptr, 16);
                if (g != 0) g_groupGuids[count++] = g;
            }
            tok = strtok_s(nullptr, ",", &ctx);
        }
    }
    g_groupCount = count;
}

void SpellClass_Reset() {
    std::memset(g_boardCat, 0, sizeof(g_boardCat));
    std::memset(g_simpleCat, 0, sizeof(g_simpleCat));
    std::memset(g_selected, 0, sizeof(g_selected));
    g_boardHideAll = false;
    g_simpleHideAll = false;
    g_applyAll = false;
}

// ============================================================================
// Emitter hooks — every CGUnit/CGPlayer thiscall method that resolves a spell
// visual via GetSpellVisualRow. Each sets the thread-local host = `this` (the
// unit the visual belongs to) for the duration of the call, so the leaf decision
// knows who it is. Covers cast, channel beams, aura state, impacts, areas and
// missiles — not just the cast path. All addresses verified to call 0x7FA290 and
// end in a clean `ret N` epilogue (see RE_OPTIMIZATION_FINDINGS.md).
//   this-in-ecx is emulated via __fastcall(self, edx_dummy, <stack args>); the
//   stack-arg count must match the function's `ret N` for correct cleanup.
// ============================================================================
typedef void*(__fastcall* Fn0)(void*, void*);
typedef void*(__fastcall* Fn1)(void*, void*, void*);
typedef void*(__fastcall* Fn2)(void*, void*, void*, void*);
typedef void*(__fastcall* Fn4)(void*, void*, void*, void*, void*, void*);
typedef void*(__fastcall* Fn7)(void*, void*, void*, void*, void*, void*, void*, void*, void*);
typedef void*(__fastcall* Fn9)(void*, void*, void*, void*, void*, void*, void*, void*, void*, void*, void*);
typedef void*(__fastcall* Fn13)(void*, void*, void*, void*, void*, void*, void*, void*, void*, void*, void*, void*, void*, void*, void*);

static bool g_emitterHooked = false;

// fwd: defined with the swing/auto-attack predicates below. True when `unit` is a hideable player
// whose source→target PROJECTILE (auto-shot arrow/bullet, cast missile) should be suppressed.
static bool ShouldHideArrowFor(void* unit);

// originals (patched in place by Detours). All are __thiscall CGUnit/CGPlayer
// methods with this=the unit hosting the visual, verified to call GetSpellVisualRow.
static void* g_o_720F80 = (void*)0x00720F80; // ret 0x10  cast / core play
static void* g_o_72BC70 = (void*)0x0072BC70; // ret 0     channel beam
static void* g_o_7224D0 = (void*)0x007224D0; // ret 8
static void* g_o_7228B0 = (void*)0x007228B0; // ret 0
static void* g_o_720BF0 = (void*)0x00720BF0; // ret 8
static void* g_o_704B30 = (void*)0x00704B30; // ret 4
static void* g_o_704F60 = (void*)0x00704F60; // ret 0
static void* g_o_733820 = (void*)0x00733820; // ret 0x1c
static void* g_o_733E20 = (void*)0x00733E20; // ret 0x1c
static void* g_o_71E930 = (void*)0x0071E930; // ret 8     aura state (buffs/debuffs)
static void* g_o_732FF0 = (void*)0x00732FF0; // ret 0x34  missile
static void* g_o_724820 = (void*)0x00724820; // ret 8
static void* g_o_703410 = (void*)0x00703410; // ret 8
// CGUnit_C::UpdateVisualState (Player_C/CGUnit vtable slot @ .rdata 0xA32748/0xA34E10).
// this=ecx=the unit. RE-verified (re_t.py): reads ranged/weapon slot state (slots 4/6),
// sheath/combat flags (+0xa38,+0xb84), and resolves the unit's PERSISTENT STATE spell
// visual at [unit+0xa8c] -> GetSpellVisualRow(0x7FA290)@0x73EAA4 -> plays its STATE kit
// ([row+0x10], the aura/buff/mount/shapeshift glow). This is the creation/refresh path
// for persistent self-buff / trinket-proc / mount / shapeshift glows AND the ranged
// (hunter auto-shot) weapon visual — none of which pass through the cast/aura emitters
// above, so without this hook those leaked (host=null -> fail-safe show). ret 4.
static void* g_o_73E840 = (void*)0x0073E840; // ret 4   persistent STATE + ranged/weapon visual
// Polymorphic object visual resolver — a thin vtable thunk (GetSpellVisualRow forwarder)
// present in 6 NON-unit vtables (.rdata 0x9F3B2C/0xA330DC/0xA33284/0xA3338C/0xA334E4/
// 0xA346FC = CGObject/CGGameObject/CGDynamicObject/CGCorpse family). this=ecx=the object
// hosting the visual. Setting host=this lets Classify resolve standalone DynamicObject/
// GameObject ground effects to their caster (desc+0x18) so player-cast area effects are
// hideable while boss/NPC ground mechanics stay protected. ret 0x10 (4 stack args).
static void* g_o_7432E0 = (void*)0x007432E0; // ret 0x10  non-unit object visual resolver

static void* __fastcall hk_720F80(void* s, void* e, void* a1, void* a2, void* a3, void* a4)
{ void* p=g_host; g_host=s; void* r=((Fn4)g_o_720F80)(s,e,a1,a2,a3,a4); g_host=p; return r; }
static void* __fastcall hk_72BC70(void* s, void* e)
{ void* p=g_host; g_host=s; void* r=((Fn0)g_o_72BC70)(s,e); g_host=p; return r; }
static void* __fastcall hk_7224D0(void* s, void* e, void* a1, void* a2)
{ void* p=g_host; g_host=s; void* r=((Fn2)g_o_7224D0)(s,e,a1,a2); g_host=p; return r; }
static void* __fastcall hk_7228B0(void* s, void* e)
{ void* p=g_host; g_host=s; void* r=((Fn0)g_o_7228B0)(s,e); g_host=p; return r; }
static void* __fastcall hk_720BF0(void* s, void* e, void* a1, void* a2)
{ void* p=g_host; g_host=s; void* r=((Fn2)g_o_720BF0)(s,e,a1,a2); g_host=p; return r; }
static void* __fastcall hk_704B30(void* s, void* e, void* a1)
{ void* p=g_host; g_host=s; void* r=((Fn1)g_o_704B30)(s,e,a1); g_host=p; return r; }
static void* __fastcall hk_704F60(void* s, void* e)
{ void* p=g_host; g_host=s; void* r=((Fn0)g_o_704F60)(s,e); g_host=p; return r; }
static void* __fastcall hk_733820(void* s, void* e, void* a1, void* a2, void* a3, void* a4, void* a5, void* a6, void* a7)
{ void* p=g_host; g_host=s; void* r=((Fn7)g_o_733820)(s,e,a1,a2,a3,a4,a5,a6,a7); g_host=p; return r; }
static void* __fastcall hk_733E20(void* s, void* e, void* a1, void* a2, void* a3, void* a4, void* a5, void* a6, void* a7)
{ void* p=g_host; g_host=s; void* r=((Fn7)g_o_733E20)(s,e,a1,a2,a3,a4,a5,a6,a7); g_host=p; return r; }
static void* __fastcall hk_71E930(void* s, void* e, void* a1, void* a2)
{ void* p=g_host; g_host=s; void* r=((Fn2)g_o_71E930)(s,e,a1,a2); g_host=p; return r; }
static void* __fastcall hk_724820(void* s, void* e, void* a1, void* a2)
{ void* p=g_host; g_host=s; void* r=((Fn2)g_o_724820)(s,e,a1,a2); g_host=p; return r; }
static void* __fastcall hk_703410(void* s, void* e, void* a1, void* a2)
{ void* p=g_host; g_host=s; void* r=((Fn2)g_o_703410)(s,e,a1,a2); g_host=p; return r; }
static void* __fastcall hk_732FF0(void* s, void* e, void* a1, void* a2, void* a3, void* a4, void* a5, void* a6,
                                  void* a7, void* a8, void* a9, void* a10, void* a11, void* a12, void* a13)
{
    // CREATION-TIME projectile suppression. 0x732FF0 (this=ecx=the CASTER) is the missile/projectile
    // CREATOR — it builds the very travelling SpellVisualEffect node that 0x7FAE90 then draws every
    // frame (hunter auto-shot arrow/bullet, a player's cast missile). RE-verified: it is the missile
    // emitter (reads SpellVisualKit db 0xAD4A28, sets the in-flight flag [this+0xa30]|=0x1000000) and
    // its 5 callers @0x800xxx IGNORE the return, so an early-out is safe. Suppressing HERE — when the
    // caster is a hideable player (ShouldHideArrowFor: swing toggle / board MISSILE / hide-all; never
    // self / boss / boss-owned / NPC) — stops the projectile before its node exists, which is why the
    // node-teardown path could not catch it (the arrow streak is anchored to the weapon with no unit
    // target, so it slipped past both the distinct-target arrow branch and the aura/cast teardown).
    // Boss/add projectiles (this=NPC) and my own (this=me) are never suppressed, so encounter missiles
    // stay; a player-carried mechanic is an AURA/area, not a missile from the player, so spores/links
    // are untouched.
    if (s && !g_isProcessTerminating) {
        // Bounded diagnostic: when filtering is on, log the first few missiles created by a NON-self
        // PLAYER source with the hide decision. If a hunter's arrow ever still shows, this line in
        // <wow>\TSM_logs proves whether the projectile even reached this creator (it should) and why
        // it was/wasn't suppressed — turning the next single shot into a definitive answer.
        static int s_missileDiag = 0;
        if (g_masterEnabled || g_hideOtherSwing) {
            __try {
                int cls = 0; const int prim = Classify(s, &cls);
                if (prim >= 0 && prim != SC_SELF && IsPlayerSourcePrim(prim) && s_missileDiag < 40) {
                    s_missileDiag++;
                    Log("[SC-MISSILE] src=%p prim=%d cls=%d hide=%d", s, prim, cls, (int)ShouldHideArrowFor(s));
                }
            } __except (EXCEPTION_EXECUTE_HANDLER) {}
        }
        __try { if (ShouldHideArrowFor(s)) return nullptr; } __except (EXCEPTION_EXECUTE_HANDLER) {}
    }
    void* p=g_host; g_host=s; void* r=((Fn13)g_o_732FF0)(s,e,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12,a13); g_host=p; return r;
}
static void* __fastcall hk_73E840(void* s, void* e, void* a1)
{ void* p=g_host; g_host=s; void* r=((Fn1)g_o_73E840)(s,e,a1); g_host=p; return r; }
static void* __fastcall hk_7432E0(void* s, void* e, void* a1, void* a2, void* a3, void* a4)
{ void* p=g_host; g_host=s; void* r=((Fn4)g_o_7432E0)(s,e,a1,a2,a3,a4); g_host=p; return r; }

// ============================================================================
// MELEE / RANGED AUTO-ATTACK weapon-trail suppression (the "swoosh").
// ----------------------------------------------------------------------------
// The white auto-attack swing trail is NOT a spell visual — it is a WeaponTrail object,
// so it never passes through GetSpellVisualRow and the leaf filter above can never touch
// it. It is (re)created every swing by CGUnit_C::SetWeaponTrail @0x00720170 (this=ecx=the
// swinging unit; trail objects cached at this+0xB50[idx], idx 0/1 = main/off-hand;
// WeaponTrailClose 0x7E4CC0 then WeaponTrailCreate 0x7E4BF0). ret 8.
//
// To hide OTHER players' auto-attacks we drop the call when the swinging unit is a
// positively-classified hideable other player (and the user is hiding their combat
// visuals). Because the trail is re-set per swing, skipping creation = no swoosh, with no
// stale-trail cleanup needed. Self / own-pet / bosses / NPCs are never suppressed
// (HostHardProtected + IsPlayerSourcePrim), so encounter/boss reads are untouched.
static bool ShouldHideSwingFor(void* unit);   // fwd: dedicated "hide attack animations" option
static bool ShouldHideUnitWeaponTrail(void* unit) {
    if (!unit || (uintptr_t)unit < 0x10000) return false;
    // Fast no-op for the hot kit chokepoint when neither the filter nor distance-cull is on.
    if (!g_masterEnabled && !UnitHider_CullActive()) return false;
    // Far / model-culled unit: kill its trail too (it is invisible anyway = pure FPS).
    if (UnitHider_ShouldCullVisualHost(unit)) return true;
    if (!g_masterEnabled) return false;
    if (HostHardProtected(unit)) return false;             // me / boss / boss-owned -> keep
    // NOTE: no HostHasEncounterAura guard. The kits suppressed via this predicate (weapon trail
    // 0x720170, auto-attack KIT 0x73A6C0, and the kit-by-id chokepoint 0x745230 used for trinket /
    // ability PROCS and auto-attacks) are ALWAYS player-produced — never an encounter mechanic. A
    // raider almost always carries some incidental boss/zone debuff, so guarding on that flag here
    // leaked every afflicted player's procs and swoosh (the "procs on players still show" bug). The
    // genuine mechanic glow (a boss/add DEBUFF's aura visual) flows through the LEAF, where the
    // per-visual aura-caster gate keeps it; it does not depend on this auto-attack/proc path.
    int classId = 0;
    const int prim = Classify(unit, &classId);
    if (prim < 0) return false;
    if (!IsPlayerSourcePrim(prim) || prim == SC_SELF || prim == SC_OWN_PET) return false;
    const HideSource src = ClassifyHideSource(prim, classId);
    // Auto-attacks (melee swing trail / ranged muzzle kit) are this player's combat
    // visuals. If the user has marked this player as a hide target AT ALL — via any
    // category, the board, or hide-all — suppress their auto-attack effects too. This is
    // deliberately broader than a single category so "hide this player's effects" also
    // removes their constant auto-attack swoosh, which has no dedicated category.
    return src.any();
}

// Auto-attack PRESENTATION fx (melee swoosh trail @0x720170 and the auto-attack / ranged
// muzzle KIT @0x73A6C0). Suppressed for an OTHER player when EITHER the board/master marks
// them a hide target OR the dedicated "Hide other players' attack animations" option is on.
// That second path is the fix for "swing option still shows hunters' auto attack": the option
// used to drop only the body ANIMATION (0x7385C0), but a hunter's ranged auto-shot is visible
// through this muzzle-flash KIT, not the body anim — so it kept showing. Self / own-pet /
// bosses / NPCs are hard-protected inside both predicates, so mechanics are never touched.
static bool ShouldHideUnitAutoAttackFx(void* unit) {
    if (ShouldHideUnitWeaponTrail(unit)) return true;
    return ShouldHideSwingFor(unit);
}

static void* g_o_720170 = (void*)0x00720170; // ret 8  CGUnit_C::SetWeaponTrail
static void* __fastcall hk_720170(void* s, void* e, void* a1, void* a2) {
    if (s && !g_isProcessTerminating) {
        __try {
            if (ShouldHideUnitAutoAttackFx(s)) return nullptr;  // skip: no auto-attack swoosh
        } __except (EXCEPTION_EXECUTE_HANDLER) {}
    }
    return ((Fn2)g_o_720170)(s, e, a1, a2);
}

// CGUnit_C::PlaySpellVisualKit_HandleWeapon @0x0073A6C0 (binana-named; this=ecx=CGUnit,
// ret 0x24 = 9 stack args). Plays the AUTO-ATTACK weapon visual KIT and its sound directly
// from the SpellVisualKit db (0xAD4A28) + PlaySoundKit (0x4C6A40) — it does NOT pass through
// the leaf, so the cast/missile filter never sees it. This is the melee swing-kit / ranged
// muzzle-flash effect (the other half of "auto attack from melee + hunters"). We drop it for a
// hidden other player only; the local player, bosses and NPCs are never affected (so combat
// reads and encounter mechanics are untouched), and the suppressed sound aligns with the
// other-player sound mute.
static void* g_o_73A6C0 = (void*)0x0073A6C0; // ret 0x24
static void* __fastcall hk_73A6C0(void* s, void* e, void* a1, void* a2, void* a3, void* a4,
                                  void* a5, void* a6, void* a7, void* a8, void* a9) {
    if (s && !g_isProcessTerminating) {
        __try {
            if (ShouldHideUnitAutoAttackFx(s)) return nullptr;  // skip: melee swoosh + hunter ranged muzzle kit
        } __except (EXCEPTION_EXECUTE_HANDLER) {}
    }
    return ((Fn9)g_o_73A6C0)(s, e, a1, a2, a3, a4, a5, a6, a7, a8, a9);
}

// CGObject_C::PlaySpellVisualKit @0x00745230 (this=ecx=CGObject host, ret 4, 1 arg = kit
// params). This is the CENTRAL "play a SpellVisualKit BY ID" chokepoint (29 callers incl.
// CGUnit_C::PlayAttackerRound's auto-attack @0x755365, the persistent STATE/proc refresh
// @0x73EAD7, and trinket/weapon procs). Kits played here go DIRECTLY by id and never pass
// through GetSpellVisualRow, so the row-clearing leaf filter cannot touch them — this is why
// other players' PROCS, weapon procs and auto-attack kit effects kept showing even with
// everything hidden. Dropping the call for a positively-classified hideable other player
// suppresses those. Self / own-pet / bosses / NPCs (and boss-owned hosts) are hard-protected
// in ShouldHideUnitWeaponTrail, so encounter/boss mechanics and your own effects are kept.
static void* g_o_745230 = (void*)0x00745230; // ret 4
static void* __fastcall hk_745230(void* s, void* e, void* a1) {
    if (s && !g_isProcessTerminating) {
        __try {
            if (ShouldHideUnitWeaponTrail(s)) return nullptr;  // skip: no proc / kit effect
        } __except (EXCEPTION_EXECUTE_HANDLER) {}
    }
    return ((Fn1)g_o_745230)(s, e, a1);
}

// ============================================================================
// AUTO-ATTACK SWING ANIMATION suppression (other players only) — SAFE BY CONSTRUCTION.
// ----------------------------------------------------------------------------
// The melee/ranged swing is the unit playing its attack ANIMATION through the generic
// CGUnit animation player @0x007385C0 (this=ecx=unit, ret 8; 57 callers: idle, run, emote,
// spell, combat). We must NOT gate 0x7385C0 globally (that freezes movement/idle), and we
// must NOT skip the combat handlers wholesale: PlayAttackerRound @0x00755130 also runs
// UnitCombatLog (0x751150) + ShowCombatFeedback (0x513380); HandleCombatAnimEvent
// @0x00756240 runs combat sound + PlayVictimRound + death handling. Skipping those would
// break the combat log / damage meters / deaths.
//
// SAFE design: wrap the two combat-presentation entry points; ONLY for a hidden other player,
// raise a thread-local flag around the ORIGINAL call so every bit of bookkeeping (combat log,
// feedback, sound, death) still runs untouched, and gate 0x7385C0 by that flag so just the
// swing/combat animation is skipped while it is set. PlayAttackerRound IGNORES 0x7385C0's
// return (verified @0x75520B: eax is reloaded), and the suppressed call only happens inside
// these combat rounds for a hidden player, so nothing relies on the result. ShouldHideUnitWeaponTrail
// hard-protects self / own-pet / boss / NPC, so encounter mechanics and your own swings are kept.
static thread_local int g_suppressCombatAnim = 0;

// Dedicated, independently-tickable option ("Hide other players' attack animations").
// Works on its own (does not need the board/master) — when on, the swing/combat animation of
// any OTHER player (and their pet) is skipped; self / own-pet / bosses / NPCs are always kept,
// so encounter mechanics are never affected. (Flag declared near g_masterEnabled.)
static bool ShouldHideSwingFor(void* unit) {
    if (!g_hideOtherSwing || !unit || (uintptr_t)unit < 0x10000 || g_isProcessTerminating) return false;
    __try {
        if (HostHardProtected(unit)) return false;            // self / boss / boss-owned
        int classId = 0;
        const int prim = Classify(unit, &classId);
        if (prim < 0) return false;
        if (!IsPlayerSourcePrim(prim) || prim == SC_SELF || prim == SC_OWN_PET) return false;
        return true;                                          // other player / their pet / group
    } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

static void* g_o_755130 = (void*)0x00755130; // CGUnit_C::PlayAttackerRound, ret 4
static void* __fastcall hk_755130(void* s, void* e, void* a1) {
    const bool sup = ShouldHideSwingFor(s);
    if (sup) ++g_suppressCombatAnim;
    void* r = ((Fn1)g_o_755130)(s, e, a1);
    if (sup && g_suppressCombatAnim > 0) --g_suppressCombatAnim;
    return r;
}

static void* g_o_756240 = (void*)0x00756240; // CGUnit_C::HandleCombatAnimEvent, ret 0x10
static void* __fastcall hk_756240(void* s, void* e, void* a1, void* a2, void* a3, void* a4) {
    const bool sup = ShouldHideSwingFor(s);
    if (sup) ++g_suppressCombatAnim;
    void* r = ((Fn4)g_o_756240)(s, e, a1, a2, a3, a4);
    if (sup && g_suppressCombatAnim > 0) --g_suppressCombatAnim;
    return r;
}

static void* g_o_7385C0 = (void*)0x007385C0; // CGUnit animation play, ret 8 (this=unit)
static void* __fastcall hk_7385C0(void* s, void* e, void* a1, void* a2) {
    if (g_suppressCombatAnim > 0 && !g_isProcessTerminating) return nullptr;  // skip swing/combat anim only
    return ((Fn2)g_o_7385C0)(s, e, a1, a2);
}

// CHANNEL per-frame re-resolution leak. SpellVisualsTick (0x7FCA30) re-plays channel beams
// (Mind Flay, Penance, Drain Life, Tranquility, etc.) EVERY frame via CGUnit method 0x7FEC00:
// this=ESI=the channeling unit (RE-verified: reads stats [esi+0xD0] and channelSpellId
// [esi+0xA60]); it RE-resolves the SpellVisual row through the leaf (call 0x7FA290 @0x7FEC38)
// and re-spawns the channel kit from the SpellVisualKit db (0xAD4A4C/48/5C). The creation-time
// channel hook (0x72BC70) only clears the kit on a per-instance copy at START, so this per-frame
// path re-reads the ORIGINAL shared row and a hidden player's beam reappears each frame (the
// "glimpses sneaking" for channels). Setting g_host=esi here makes the leaf re-apply the same
// per-caster decision every frame, so the beam stays hidden. Naked because `this` arrives in ESI
// (a register-this optimization, not ecx) and `ret 0`: we only read ESI and tail-jump to the
// Detours trampoline, touching no stack — the original runs byte-identical. g_host is left set to
// the unit (not restored); harmless — the next emitter call save/restores around itself and the
// next Tick unit re-sets it, and Classify fail-safes on any non-unit pointer.
static void* g_o_7FEC00 = (void*)0x007FEC00;
__declspec(naked) static void hk_7FEC00() {
    __asm {
        mov dword ptr [g_host], esi
        jmp dword ptr [g_o_7FEC00]
    }
}

// ============================================================================
// PERSISTENT-VISUAL suppression via SpellVisualsTick (fixes "Shadowform still shows").
// ----------------------------------------------------------------------------
// A persistent visual (Shadowform, other shapeshift glows, buff/proc auras) is created ONCE
// when its aura is applied and then lives as a CSpellVisual node that SpellVisualsTick updates
// and draws every frame. If it was created before the filter was enabled (or before the unit
// came into view), it never re-hits the leaf, so clearing kits at the leaf can't touch it.
//
// SpellVisualsTick @0x7FCA30 calls the per-node updater @0x7FAE90 (this=ecx=node, ret 4) and
// REMOVES the node when that returns 0 (keep when != 0). We resolve the node's host unit and,
// if that host is one we are hiding (board hide-target whose aura/cast/channel/all is hidden) or
// is being distance-culled, return 0 so the engine cleanly removes the visual through its OWN
// teardown path. RE-verified node layout (from 0x7FAE90): count @+0x1C, attach array @+0x20
// (entries {srcIdx:u16,dstIdx:u16}), GUID table @+0x10 (entries {lo:u32,hi:u32}); host =
// ClntObjMgrObjectPtr(table[arr[0].srcIdx]). Every read is SEH-guarded, so a bad/odd node simply
// falls through to the ORIGINAL return (visual kept) — never a crash, never a wrong removal.
// Conservative: only PLAYER-source hosts are torn down (never NPC/boss persistent visuals, which
// could be a mechanic); self/own-pet/boss are hard-protected.
static void* ResolveNodeHost(void* node) {
    __try {
        uint8_t* n = (uint8_t*)node;
        const uint32_t count = *(uint32_t*)(n + 0x1C);
        if (count == 0) return nullptr;
        uint8_t* arr   = *(uint8_t**)(n + 0x20);
        uint8_t* table = *(uint8_t**)(n + 0x10);
        if (!arr || !table || (uintptr_t)arr < 0x10000 || (uintptr_t)table < 0x10000) return nullptr;
        const uint16_t srcIdx = *(uint16_t*)(arr + 0);     // first attach element's source index
        if (srcIdx == 0xFFFF) return nullptr;
        const uint32_t lo = *(uint32_t*)(table + (uint32_t)srcIdx * 8 + 0);
        const uint32_t hi = *(uint32_t*)(table + (uint32_t)srcIdx * 8 + 4);
        const uint64_t guid = ((uint64_t)hi << 32) | lo;
        if (guid == 0) return nullptr;
        return ResolveAnyByGuid(guid);                     // any object (mirrors the engine, mask=1)
    } __except (EXCEPTION_EXECUTE_HANDLER) { return nullptr; }
}

// The TARGET endpoint of a source->target node (arr[0].dstIdx), or nullptr. Mirrors ResolveNodeHost
// (which resolves arr[0].srcIdx). Lets the projectile branch keep a link aimed at a PLAYER (an
// encounter link onto a raid member — ooze/gas-cloud tether, Blood Queen's Pact of the Darkfallen
// player<->player beam) while still hiding a player's projectile aimed at an ENEMY (auto-shot arrow,
// cast missile at the boss).
static void* ResolveNodeTarget(void* node) {
    __try {
        uint8_t* n = (uint8_t*)node;
        const uint32_t count = *(uint32_t*)(n + 0x1C);
        if (count == 0) return nullptr;
        uint8_t* arr   = *(uint8_t**)(n + 0x20);
        uint8_t* table = *(uint8_t**)(n + 0x10);
        if (!arr || !table || (uintptr_t)arr < 0x10000 || (uintptr_t)table < 0x10000) return nullptr;
        const uint16_t dstIdx = *(uint16_t*)(arr + 2);     // first attach element's target index
        if (dstIdx == 0xFFFF) return nullptr;
        const uint32_t lo = *(uint32_t*)(table + (uint32_t)dstIdx * 8 + 0);
        const uint32_t hi = *(uint32_t*)(table + (uint32_t)dstIdx * 8 + 4);
        const uint64_t guid = ((uint64_t)hi << 32) | lo;
        if (guid == 0) return nullptr;
        return ResolveAnyByGuid(guid);
    } __except (EXCEPTION_EXECUTE_HANDLER) { return nullptr; }
}

// True if `obj` is a PLAYER (descriptor typeMask has the PLAYER bit 0x10 — the exact test the
// client's own Lua_UnitIsPlayer @0x60C4B0 uses). Covers the local player, group and other players.
static bool IsPlayerUnit(void* obj) {
    if (!obj || (uintptr_t)obj < 0x10000) return false;
    __try {
        void* descV = *(void**)((uint8_t*)obj + OBJ_DESCRIPTORS);
        if (!descV || (uintptr_t)descV < 0x10000) return false;
        return (*(uint32_t*)((uint8_t*)descV + DESC_TYPEMASK) & TYPEMASK_PLAYER) != 0;
    } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

// True if this node links a SOURCE to a DISTINCT TARGET (a projectile / beam that travels between
// two units — e.g. a hunter's auto-shot arrow, a missile, a chain) as opposed to a self-anchored
// persistent visual (Shadowform & other shapeshift/aura glows, which have NO target: dstIdx ==
// 0xFFFF or == srcIdx). We use this to scope the auto-attack / "swing" arrow teardown to ACTUAL
// projectiles, so it can NEVER tear down another player's Shadowform-style self visual. The first
// attach element decides it (matches ResolveNodeHost, which classifies arr[0].srcIdx). SEH-guarded.
static bool NodeHasDistinctTarget(void* node) {
    __try {
        uint8_t* n = (uint8_t*)node;
        if (*(uint32_t*)(n + 0x1C) == 0) return false;
        uint8_t* arr = *(uint8_t**)(n + 0x20);
        if (!arr || (uintptr_t)arr < 0x10000) return false;
        const uint16_t srcIdx = *(uint16_t*)(arr + 0);
        const uint16_t dstIdx = *(uint16_t*)(arr + 2);
        return dstIdx != 0xFFFF && dstIdx != srcIdx;
    } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

// True if the whole persistent visual hosted on `host` should be torn down this frame.
static bool ShouldTearDownHostVisual(void* host) {
    if (!host || (uintptr_t)host < 0x10000) return false;
    // Boss / self / boss-owned persistent visuals are NEVER torn down — checked BEFORE the
    // distance-cull so a FAR boss's persistent mechanic (Thorim's Lightning Charge sparks to a
    // pillar, a boss enrage / channel glow) stays visible even while far NPC models are culled.
    if (HostHardProtected(host)) return false;             // me / boss / boss-owned -> keep
    // Distance-culled (model hidden) -> remove its visuals too (pure FPS, far non-boss unit).
    if (UnitHider_ShouldCullVisualHost(host)) return true;
    if (!g_masterEnabled) return false;
    // NEVER tear a mechanic off a player: if this unit is under any NPC/boss-cast aura (Gas Spore,
    // Legion Flame, etc.) keep ALL its persistent visuals — better to leave a player's own buff
    // glow up than to risk hiding an encounter debuff the raid must see. (Player-cast clutter is
    // unaffected: a buff from another raider does NOT set this.)
    if (HostHasEncounterAura(host)) return false;
    int classId = 0;
    const int prim = Classify(host, &classId);
    if (prim < 0) return false;
    if (!IsPlayerSourcePrim(prim)) return false;           // only OTHER players' persistent visuals
    if (prim == SC_SELF || prim == SC_OWN_PET) return false;
    const HideSource src = ClassifyHideSource(prim, classId);
    if (!src.any()) return false;
    const bool hideAll = (src.bySimple && g_simpleHideAll) || (src.byRow && g_boardHideAll);
    if (hideAll) return true;
    // Persistent visuals are state/aura (Shadowform), or re-asserting cast/channel glows.
    const bool byCat =
        (src.bySimple && (g_simpleCat[SCAT_AURA_START] || g_simpleCat[SCAT_AURA_END] ||
                          g_simpleCat[SCAT_CHANNEL]    || g_simpleCat[SCAT_CAST]    || g_simpleCat[SCAT_PRECAST])) ||
        (src.byRow    && (g_boardCat[SCAT_AURA_START]  || g_boardCat[SCAT_AURA_END]  ||
                          g_boardCat[SCAT_CHANNEL]     || g_boardCat[SCAT_CAST]     || g_boardCat[SCAT_PRECAST]));
    return byCat;
}

// Should this node's host have its source->target PROJECTILE (arrow / missile / beam) torn down?
// This is the fix for "the board / swing toggle hides hunters but NOT their auto-shot arrow":
// the arrow is a source->target SpellVisualEffect (model from SpellVisualEffectName.dbc, rendered
// every frame by 0x7FAE90), so it NEVER passes through GetSpellVisualRow's row-clearing — the only
// way to hide it is to stop the engine from drawing the node. Caller must additionally require
// NodeHasDistinctTarget(node) so this only ever affects real projectiles/beams, never a self-aura
// (Shadowform). Hidden when EITHER the dedicated "Hide other players' swings" toggle is on (ranged
// auto-shot is the ranged auto-attack) OR the board marks this other player a hide target via the
// MISSILE category / hide-all. Self / own-pet / bosses / NPCs are hard-protected, so encounter
// projectiles (boss arrows, mechanic missiles) are always kept.
static bool ShouldHideArrowFor(void* host) {
    if (!host || (uintptr_t)host < 0x10000) return false;
    if (HostHardProtected(host)) return false;             // me / boss / boss-owned -> keep
    // NOTE: no HostHasEncounterAura guard here. A source→target PROJECTILE whose SOURCE is a player
    // is that player's auto-attack arrow/bullet or cast missile — NEVER an encounter mechanic, even
    // while the player carries a boss/zone debuff (which nearly every raider does, e.g. Chill of the
    // Throne). The old guard returned false for any afflicted hunter, so their arrow kept showing.
    // Mechanic LINKS/tethers are still safe by SOURCE classification: a boss→player or ooze↔player
    // tether's source is the NPC (ShouldHideSwingFor/Classify ⇒ not a player source ⇒ kept below).
    if (ShouldHideSwingFor(host)) return true;             // swing toggle (independent of master)
    if (!g_masterEnabled) return false;
    int classId = 0;
    const int prim = Classify(host, &classId);
    if (prim < 0) return false;
    if (!IsPlayerSourcePrim(prim) || prim == SC_SELF || prim == SC_OWN_PET) return false;
    // If this player is a hide target AT ALL (any category / board / hide-all), suppress their
    // ranged projectile — exactly like their auto-attack swoosh (ShouldHideUnitWeaponTrail uses the
    // same src.any()). The flying arrow/bullet is the ranged half of the auto-attack and has no
    // dedicated category, so it is gated by "is this player hidden", not by the MISSILE checkbox.
    return ClassifyHideSource(prim, classId).any();
}

// Bounded diagnostics — logs the first g_vdiagBudget Tick nodes processed while filtering, with
// the resolved host class and the node's GUID-table contents, so we can pin down where a
// persistent visual (Shadowform/Shadowmourne) actually lives. Auto-armed on enable; SC_VDIAG
// re-arms manually. Pure no-op when budget is 0.
void SpellClass_SetVdiag(int n) { g_vdiagBudget = (n < 0) ? 0 : (n > 4000 ? 4000 : n); }

static void VdiagLogNode(void* node, void* host) {
    __try {
        uint8_t* n = (uint8_t*)node;
        const uint32_t cnt = *(uint32_t*)(n + 0x1C);
        uint8_t* table = *(uint8_t**)(n + 0x10);
        uint64_t g0 = 0, g1 = 0;
        if (table && (uintptr_t)table >= 0x10000) {
            g0 = *(uint64_t*)(table + 0);
            if (cnt > 1) g1 = *(uint64_t*)(table + 8);
        }
        int classId = 0, prim = -1; uint64_t hg = 0; uint32_t tm = 0;
        if (host) {
            prim = Classify(host, &classId);
            void* d = *(void**)((uint8_t*)host + OBJ_DESCRIPTORS);
            if (d && (uintptr_t)d >= 0x10000) { hg = *(uint64_t*)d; tm = *(uint32_t*)((uint8_t*)d + DESC_TYPEMASK); }
        }
        Log("[SC-VDIAG] node=%p cnt=%u tbl0=%016llX tbl1=%016llX host=%p prim=%d cls=%d hguid=%016llX tm=%X tear=%d",
            node, cnt, (unsigned long long)g0, (unsigned long long)g1, host, prim, classId,
            (unsigned long long)hg, tm, host ? (int)ShouldTearDownHostVisual(host) : 0);
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
}

typedef int(__fastcall* TickNode_fn)(void* node, void* edx, void* arg);
static void* g_o_7FAE90 = (void*)0x007FAE90;
static int __fastcall hk_7FAE90(void* node, void* edx, void* arg) {
    if (node && !g_isProcessTerminating &&
        (g_masterEnabled || g_hideOtherSwing || UnitHider_CullActive())) {
        __try {
            void* host = ResolveNodeHost(node);
            if (g_vdiagBudget > 0) { g_vdiagBudget--; VdiagLogNode(node, host); }
            if (host) {
                // Two MUTUALLY EXCLUSIVE node shapes, dispatched by NodeHasDistinctTarget so neither
                // branch ever acts on the other's nodes. (The old code ran BOTH on a distinct-target
                // node: the projectile branch correctly KEPT a player↔NPC encounter link, but the
                // persistent-teardown branch below — which only looks at the host, not the NPC target —
                // then destroyed it. That is why the Putricide ooze-adhesive tether and other
                // boss↔player links vanished.)
                if (NodeHasDistinctTarget(node)) {
                    // (a) SOURCE→TARGET projectile / beam / link (hunter auto-shot arrow, a player's
                    // cast missile, an encounter link). This node DRAWS its model every frame from
                    // SpellVisualEffectName.dbc, so it never passes the row-clearing leaf — the ONLY
                    // way to hide it is to drop the node. We hide it when:
                    //   • the SOURCE is a hideable player (ShouldHideArrowFor) — their auto-attack /
                    //     cast projectile, NOT a mechanic; AND
                    //   • the TARGET is NOT a player (it is a boss / enemy NPC, or unresolved).
                    // That second clause is the "friendly target" guard: a projectile a player aims
                    // at an ENEMY is hidden (hunter auto-shot/bullet, cast missile at the boss), but a
                    // link onto a PLAYER is kept — Blood Queen's Pact of the Darkfallen player↔player
                    // beam, or any tether onto a raid member. Tethers SOURCED by the NPC (Putricide
                    // ooze / gas-cloud bond) are already kept because their source is not a hideable
                    // player (ShouldHideArrowFor false), and an unresolvable source keeps the node too
                    // (host == null skips this whole block). Self / own-pet / boss / boss-owned are
                    // hard-protected inside ShouldHideArrowFor, so boss arrows & mechanic missiles show.
                    if (ShouldHideArrowFor(host) && !IsPlayerUnit(ResolveNodeTarget(node))) return 0;
                } else {
                    // (b) SELF-ANCHORED persistent visual (Shadowform & other shapeshift / aura / proc
                    // glows; dstIdx == 0xFFFF or == srcIdx). Proven behaviour: run the engine's normal
                    // update, then return 0 so it is removed via its own teardown. A player carrying a
                    // mechanic (Festergut Gas Spore, a boss debuff glow) is kept by HostHasEncounterAura
                    // inside ShouldTearDownHostVisual.
                    if (ShouldTearDownHostVisual(host)) {
                        ((TickNode_fn)g_o_7FAE90)(node, edx, arg);
                        return 0;
                    }
                }
            }
        } __except (EXCEPTION_EXECUTE_HANDLER) {}
    }
    return ((TickNode_fn)g_o_7FAE90)(node, edx, arg);
}

// ============================================================================
// Weapon / item ENCHANT-VISUAL hiding (other players only)
// ----------------------------------------------------------------------------
// Enchant glows (Flametongue, Crusader, Mongoose, sharpening-stone shimmer, etc.)
// are ITEM visuals, NOT spell visuals — they never pass through GetSpellVisualRow,
// so the emitter hooks above can't touch them. They are attached per item slot by
// the CGUnit item-visual applier @ 0x006D6BA0 (RE-verified, binana symbol
// "CGUnit_C item enchant applier"; this = CGUnit, descriptors at this+0x08), which
// calls VisibleItem_C::GetItemEnchantmentVisualID @ 0x00759050 to resolve the
// ItemVisuals.dbc id for the slot's enchant (0 = no glow — the engine's own
// "unenchanted" return).
//
// Strategy: tag the host unit while the applier runs (thread-local), and force the
// enchant-visual id to 0 for OTHER PLAYERS only. Returning 0 makes the engine treat
// the slot as unenchanted, so an existing glow is removed and none is added — never
// touching the local player, pets, NPCs or bosses. Always-installed; gated by the
// toggle so it is a pure pass-through when off.
static volatile bool g_hideOtherEnchants = false;  // OTHER players' item glows
static volatile bool g_hideNpcEnchants   = false;  // NPC/add item glows (never bosses)
static thread_local void* g_enchantHost = nullptr;

// Decide whether the slot's item enchant/glow visual should be suppressed for the unit the
// applier is currently running on. Players -> g_hideOtherEnchants (never me). NPC/add units ->
// g_hideNpcEnchants, but BOSSES are always kept (a boss's weapon glow can be part of its
// readable identity; item glows are never a wipe mechanic, but we stay conservative). Returns
// the same ItemVisuals.dbc behaviour the engine expects: 0 == "no glow".
static bool EnchantShouldHide(void* unit) {
    if (!unit || (uintptr_t)unit < 0x10000 || g_playerGuid == 0) return false;
    __try {
        void* descV = *(void**)((uint8_t*)unit + OBJ_DESCRIPTORS);
        if (!descV || (uintptr_t)descV < 0x10000) return false;
        uint8_t* desc = (uint8_t*)descV;
        const uint64_t guid = *(uint64_t*)(desc + DESC_GUID);
        if (guid == 0 || guid == g_playerGuid) return false;     // mine -> always keep
        const uint32_t tm = *(uint32_t*)(desc + DESC_TYPEMASK);
        if (tm & TYPEMASK_PLAYER) return g_hideOtherEnchants;     // other player
        if (tm & TYPEMASK_UNIT) {                                 // NPC / add / boss
            if (!g_hideNpcEnchants) return false;
            if (IsBossMob(unit) || IsBossGuid(guid)) return false;  // keep boss weapon glows
            return true;
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
    return false;
}

typedef int(__fastcall* GetEnchVis_fn)(void* self, void* edx);
static void* g_o_GetEnchVis = (void*)0x00759050;
static int __fastcall hk_GetEnchVis(void* self, void* edx) {
    if ((g_hideOtherEnchants || g_hideNpcEnchants) && g_enchantHost && EnchantShouldHide(g_enchantHost))
        return 0;  // pretend the slot is unenchanted -> glow cleared / never attached
    return ((GetEnchVis_fn)g_o_GetEnchVis)(self, edx);
}

typedef void*(__fastcall* ApplyEnch_fn)(void* self, void* edx, void* item, void* a1);
static void* g_o_ApplyEnch = (void*)0x006D6BA0; // ret 8
static void* __fastcall hk_ApplyEnch(void* self, void* edx, void* item, void* a1) {
    void* prev = g_enchantHost; g_enchantHost = self;
    void* r = ((ApplyEnch_fn)g_o_ApplyEnch)(self, edx, item, a1);
    g_enchantHost = prev; return r;
}

// ---- Real-time refresh (no relog) ----------------------------------------------------
// Toggling SC_ENCHANTS only changes what the applier RETURNS; models already in view keep
// their last-baked item visuals until they rebuild. To apply live, force a model rebuild on
// every visible OTHER player so the per-slot applier (0x6D6BA0 -> our hk_GetEnchVis) re-runs
// and returns 0 (hide) or the real id (restore). RE-verified addresses:
//   CGUnit_C::UpdateDisplayInfo @ 0x0073E410 — thiscall(this, forceFlag); prologue 55 8B EC
//     83 EC 10, this=ecx; rebuilds the unit model (same call dllmain uses for the local player).
//   ClntObjMgr EnumObjects   @ 0x004D4B30 — __cdecl(cb, udata); iterates the object manager
//     (fs:[0x2c] TLS slot [0xD439BC]) and calls cb(guidLo, guidHi, udata); return 1 to continue.
// CGUnit_C::UpdateItemVisuals @ 0x00707F50 — __thiscall(this) ret 0. RE-verified: loops the 18
// equipment slots (cmp 0x12) calling the per-slot applier loop 0x6D6C10 -> 0x6D6BA0 (our
// hk_GetEnchVis). THIS is what actually re-bakes weapon/item enchant glows — UpdateDisplayInfo
// (0x73E410) does NOT reach the applier (verified: no path within depth-2), which is why the old
// refresh only updated some players coincidentally. Calling this on every visible unit re-applies
// (or restores) the enchant decision instantly for EVERYONE.
typedef int(__thiscall* UpdateItemVisuals_fn)(void* unit);
static const UpdateItemVisuals_fn CGUnit_UpdateItemVisuals = (UpdateItemVisuals_fn)0x00707F50;
// CGUnit_C::UpdateDisplayInfo @ 0x0073E410 — __thiscall(this, forceFlag). Rebuilds the unit
// model; the engine re-applies the unit's ACTIVE aura/buff visuals as part of the rebuild (the
// same reason a morph re-shows a unit's buffs). We use it to force EXISTING persistent aura
// visuals (Shadowform, etc.) to re-create — so they pass through the leaf again under the now-
// active filter, where the aura-caster gate hides player self-buffs but keeps boss-cast debuffs.
typedef int(__thiscall* UpdateDisplayInfo_fn)(void* unit, int forceFlag);
static const UpdateDisplayInfo_fn CGUnit_UpdateDisplayInfo_re = (UpdateDisplayInfo_fn)0x0073E410;
typedef int(__cdecl* EnumObjects_fn)(int(__cdecl*)(uint32_t, uint32_t, void*), void*);
static const EnumObjects_fn ClntObjMgr_EnumObjects = (EnumObjects_fn)0x004D4B30;

// Two-phase refresh (avoids reentrancy): phase 1 COLLECTS the guids of every visible non-self
// unit during the object-manager walk (cheap, list untouched); phase 2 rebuilds them AFTER the
// walk completes. Rebuilding a model mid-enumeration could in principle perturb the manager, so
// we never call UpdateDisplayInfo from inside the callback.
static uint64_t g_refreshGuids[256];
static int      g_refreshCount = 0;

static int __cdecl CollectUnitGuidCb(uint32_t lo, uint32_t hi, void* /*udata*/) {
    const uint64_t guid = ((uint64_t)hi << 32) | lo;
    if (guid != 0 && guid != g_playerGuid && g_refreshCount < 256)
        g_refreshGuids[g_refreshCount++] = guid;
    return 1; // keep enumerating
}

// Force visible units to re-bake NOW (main thread only — the command path runs in the render
// loop, same context dllmain uses for these calls). mode bit0 = item/enchant visuals (0x707F50);
// bit1 = full model rebuild (UpdateDisplayInfo) which re-creates ACTIVE aura/buff visuals so they
// re-pass the leaf under the live filter (the fix for already-applied Shadowform/Shadowmourne).
// TYPEMASK_UNIT resolves players + npcs; objects resolve to null and are skipped. SEH-guarded.
static void RefreshVisibleUnits(int mode) {
    if (g_playerGuid == 0) return;  // not in world -> object manager not ready
    g_refreshCount = 0;
    __try { ClntObjMgr_EnumObjects(&CollectUnitGuidCb, nullptr); }
    __except (EXCEPTION_EXECUTE_HANDLER) { return; }
    for (int i = 0; i < g_refreshCount; ++i) {
        void* obj = ResolveUnitByGuid(g_refreshGuids[i]);  // TYPEMASK_UNIT -> players + npcs
        if (!obj || (uintptr_t)obj < 0x10000) continue;
        if (mode & 1) __try { CGUnit_UpdateItemVisuals(obj); }      __except (EXCEPTION_EXECUTE_HANDLER) {}
        if (mode & 2) __try { CGUnit_UpdateDisplayInfo_re(obj, 1); } __except (EXCEPTION_EXECUTE_HANDLER) {}
    }
}

void SpellClass_SetHideOtherEnchants(bool on) {
    if (g_hideOtherEnchants == on) return;     // unchanged (e.g. login re-push) -> no rebuild/flicker
    g_hideOtherEnchants = on;
    RefreshVisibleUnits(1);                    // item/enchant visuals only — light, instant
}
void SpellClass_SetHideNpcEnchants(bool on) {
    if (g_hideNpcEnchants == on) return;
    g_hideNpcEnchants = on;
    RefreshVisibleUnits(1);
}
// Re-create EXISTING aura/buff + item visuals on every visible unit so a freshly-enabled filter
// retroactively hides persistent visuals (Shadowform, Shadowmourne, paladin wings, etc.) that
// were applied before it was on. Called when the master filter turns on.
void SpellClass_RefreshOtherPlayerItemVisuals() { RefreshVisibleUnits(3); }

void SpellClass_InstallEmitterHook() {
    if (g_emitterHooked) return;
    if (DetourTransactionBegin() != NO_ERROR) { return; }
    DetourUpdateThread(GetCurrentThread());
    DetourAttach(&g_o_ApplyEnch, (PVOID)hk_ApplyEnch);
    DetourAttach(&g_o_GetEnchVis, (PVOID)hk_GetEnchVis);
    DetourAttach(&g_o_720F80, (PVOID)hk_720F80);
    DetourAttach(&g_o_72BC70, (PVOID)hk_72BC70);
    DetourAttach(&g_o_7224D0, (PVOID)hk_7224D0);
    DetourAttach(&g_o_7228B0, (PVOID)hk_7228B0);
    DetourAttach(&g_o_720BF0, (PVOID)hk_720BF0);
    DetourAttach(&g_o_704B30, (PVOID)hk_704B30);
    DetourAttach(&g_o_704F60, (PVOID)hk_704F60);
    DetourAttach(&g_o_733820, (PVOID)hk_733820);
    DetourAttach(&g_o_733E20, (PVOID)hk_733E20);
    DetourAttach(&g_o_71E930, (PVOID)hk_71E930);
    DetourAttach(&g_o_724820, (PVOID)hk_724820);
    DetourAttach(&g_o_703410, (PVOID)hk_703410);
    DetourAttach(&g_o_732FF0, (PVOID)hk_732FF0);
    DetourAttach(&g_o_73E840, (PVOID)hk_73E840);
    DetourAttach(&g_o_7432E0, (PVOID)hk_7432E0);
    DetourAttach(&g_o_7FEC00, (PVOID)hk_7FEC00);
    DetourAttach(&g_o_7FAE90, (PVOID)hk_7FAE90);
    DetourAttach(&g_o_720170, (PVOID)hk_720170);   // melee/ranged auto-attack weapon trail
    DetourAttach(&g_o_73A6C0, (PVOID)hk_73A6C0);   // auto-attack weapon visual kit + sound
    DetourAttach(&g_o_745230, (PVOID)hk_745230);   // procs / direct kit plays (auto-attack, trinkets)
    DetourAttach(&g_o_755130, (PVOID)hk_755130);   // attacker swing round (flag for anim gate)
    DetourAttach(&g_o_756240, (PVOID)hk_756240);   // combat anim event (flag for anim gate)
    DetourAttach(&g_o_7385C0, (PVOID)hk_7385C0);   // CGUnit animation play (gated by flag)
    if (DetourTransactionCommit() != NO_ERROR) { return; }
    g_emitterHooked = true;
}

void SpellClass_RemoveEmitterHook() {
    if (!g_emitterHooked || g_isProcessTerminating) { g_emitterHooked = false; return; }
    DetourTransactionBegin();
    DetourUpdateThread(GetCurrentThread());
    DetourDetach(&g_o_ApplyEnch, (PVOID)hk_ApplyEnch);
    DetourDetach(&g_o_GetEnchVis, (PVOID)hk_GetEnchVis);
    DetourDetach(&g_o_720F80, (PVOID)hk_720F80);
    DetourDetach(&g_o_72BC70, (PVOID)hk_72BC70);
    DetourDetach(&g_o_7224D0, (PVOID)hk_7224D0);
    DetourDetach(&g_o_7228B0, (PVOID)hk_7228B0);
    DetourDetach(&g_o_720BF0, (PVOID)hk_720BF0);
    DetourDetach(&g_o_704B30, (PVOID)hk_704B30);
    DetourDetach(&g_o_704F60, (PVOID)hk_704F60);
    DetourDetach(&g_o_733820, (PVOID)hk_733820);
    DetourDetach(&g_o_733E20, (PVOID)hk_733E20);
    DetourDetach(&g_o_71E930, (PVOID)hk_71E930);
    DetourDetach(&g_o_724820, (PVOID)hk_724820);
    DetourDetach(&g_o_703410, (PVOID)hk_703410);
    DetourDetach(&g_o_732FF0, (PVOID)hk_732FF0);
    DetourDetach(&g_o_73E840, (PVOID)hk_73E840);
    DetourDetach(&g_o_7432E0, (PVOID)hk_7432E0);
    DetourDetach(&g_o_7FEC00, (PVOID)hk_7FEC00);
    DetourDetach(&g_o_7FAE90, (PVOID)hk_7FAE90);
    DetourDetach(&g_o_720170, (PVOID)hk_720170);
    DetourDetach(&g_o_73A6C0, (PVOID)hk_73A6C0);
    DetourDetach(&g_o_745230, (PVOID)hk_745230);
    DetourDetach(&g_o_755130, (PVOID)hk_755130);
    DetourDetach(&g_o_756240, (PVOID)hk_756240);
    DetourDetach(&g_o_7385C0, (PVOID)hk_7385C0);
    DetourTransactionCommit();
    g_emitterHooked = false;
}
