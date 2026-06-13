#pragma once
#include <cstdint>

// ============================================================================
// SpellClass — intelligent, fully-granular per-caster spell-visual filtering.
//
// Every spell visual is attributed to the unit it is hosted on; that unit is
// classified into ONE primary row (relationship or creature grade) and, for
// players, additionally into a player-class row. A per-row × per-category matrix
// decides whether to hide it. Nothing is grouped — every in-game grade and every
// player class is its own independently configurable row.
//
// FAIL-SAFE: a visual is hidden ONLY when its host resolves to a row the user
// flagged. Unknown / unresolved / protected hosts are always shown, so unattached
// world mechanics (e.g. Ruby Sanctum orbs) never vanish.
//
// RE basis (wow.exe 3.3.5a 12340, verified — see RE_OPTIMIZATION_FINDINGS.md):
//   - GetSpellVisualRow (leaf chokepoint) 0x007FA290
//   - PlaySpellVisual_core (vtable unit emitter, this = host) 0x00720F80
//   - CGUnit_C::GetCreatureRank 0x00718A00  (returns 0..5, fallback 0)
//   - Lua_UnitClassification 0x0060D970 -> grade string table @ 0x00AD21BC:
//       0 normal, 1 elite, 2 rareelite, 3 worldboss, 4 rare, 5 trivial
//   - descriptors @ obj+0x08; guid @ desc+0; typeMask @ desc+0x08;
//     class byte @ desc+0x5D; summonedBy @ desc+0x38; createdBy @ desc+0x40
// ============================================================================

// Matrix rows. Order matters: SC_GRADE_BASE..+5 line up 1:1 with the client grade
// indices, and SC_PC_BASE.. follow the player-class ids.
enum {
    SC_SELF = 0,
    SC_OWN_PET,
    SC_GROUP,
    SC_PLAYER,       // any other player (generic fallback row)
    SC_PLAYER_PET,   // other players' pets / summons

    SC_NORMAL,       // grade 0  } creature grades, MUST stay in client order
    SC_ELITE,        // grade 1
    SC_RAREELITE,    // grade 2
    SC_WORLDBOSS,    // grade 3  (in-game "boss" skull)
    SC_RARE,         // grade 4
    SC_TRIVIAL,      // grade 5

    SC_ALL,          // every classified, non-protected unit

    SC_PC_WARRIOR,   // class 1  } player-class rows (other players of that class)
    SC_PC_PALADIN,   // class 2
    SC_PC_HUNTER,    // class 3
    SC_PC_ROGUE,     // class 4
    SC_PC_PRIEST,    // class 5
    SC_PC_DK,        // class 6
    SC_PC_SHAMAN,    // class 7
    SC_PC_MAGE,      // class 8
    SC_PC_WARLOCK,   // class 9
    SC_PC_DRUID,     // class 11 (10 is unused in 3.3.5)

    SC_CLASS_COUNT
};
#define SC_GRADE_BASE SC_NORMAL   // SC_GRADE_BASE + gradeIndex(0..5)

// Visual categories (matrix columns) — map 1:1 onto SpellVisual kit fields.
enum {
    SCAT_PRECAST = 0,
    SCAT_CAST,
    SCAT_CHANNEL,
    SCAT_AURA_START,
    SCAT_AURA_END,
    SCAT_IMPACT,
    SCAT_IMPACT_CASTER,
    SCAT_IMPACT_TARGET,
    SCAT_AREA_INSTANT,
    SCAT_AREA_IMPACT,
    SCAT_AREA_PERSISTENT,
    SCAT_MISSILE,
    SCAT_MISSILE_MARKER,
    SCAT_SOUND_MISSILE,
    SCAT_SOUND_EVENT,
    SCAT_COUNT
};

// ---- lifecycle ----
void SpellClass_InstallEmitterHook();
void SpellClass_RemoveEmitterHook();

// ---- configuration (from the Lua command bridge) ----
// Model: ONE global set of hidden effect categories (the "what"), applied to every
// row the user SELECTS (the "who"). A row is filtered only when selected; everything
// else — including unknown/unresolved hosts — always shows (fail-safe).
void SpellClass_SetMasterEnabled(bool on);
bool SpellClass_GetMasterEnabled();
void SpellClass_SetGlobalCategory(int cat, bool hide); // shared "what to hide"
void SpellClass_SetGlobalHideAll(bool hide);           // board: hide ALL effects on selected rows
void SpellClass_SetApplyAll(bool on);                  // simple mode: apply to ALL non-protected units
void SpellClass_SetSimpleCategory(int cat, bool hide); // simple mode: which category to hide for all
void SpellClass_SetSimpleHideAll(bool hide);           // simple mode: hide ALL effects for all units
void SpellClass_SetSelected(int row, bool selected);   // apply the filter to this target row
void SpellClass_SetGroupList(const char* csvHexGuids);
void SpellClass_SetBossList(const char* csvHexGuids);  // boss GUIDs from Lua boss frames
void SpellClass_SetBossByHealth(bool on);              // health-based boss protection (no boss frames)
void SpellClass_SetHideOtherEnchants(bool on);         // hide weapon/item enchant glows on OTHER players (live, no relog)
void SpellClass_SetHideNpcEnchants(bool on);           // also hide item/weapon glows on NPCs/adds (never bosses; live)
void SpellClass_SetHideOtherSwing(bool on);            // hide other players' melee/ranged attack ANIMATION (swing); never self/boss/NPC
void SpellClass_RefreshOtherPlayerItemVisuals();       // force visible units to re-bake item visuals now
void SpellClass_SetVdiag(int n);                       // bounded Tick-node diagnostics (n nodes logged)
void SpellClass_Reset();

// ---- hot path ----
void* SpellClass_DecideRow(uint32_t spellId, uint32_t visualId,
                           void* originalRow, void* nullRow, bool protectedHost);

// True if the unit currently hosting a visual (the caster, set by the emitter hooks)
// is the local player. Used to make spell morphs apply ONLY to your own casts.
bool SpellClass_HostIsLocalPlayer();

// Encounter helpers (shared with UnitHider). IsBossEncounterActive: a boss fight is in progress
// (boss-frame list non-empty, or a boss was seen within the last few seconds). IsEnemyUnit: the
// NPC is HOSTILE to the local player (CGUnit_C::UnitReaction). Together they let both the spell-
// visual filter and the model-cull keep encounter ADDS visible (Lich King Raging Spirit, etc.)
// without any hardcoded creature/spell ids.
bool SpellClass_IsBossEncounterActive();
bool SpellClass_IsEnemyUnit(void* unit);
