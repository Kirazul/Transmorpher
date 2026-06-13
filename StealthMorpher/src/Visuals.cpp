#include "Visuals.h"
#include "Utils.h"
#include "SpellMorph.h"
#include "ColorEngine.h"
#include <windows.h>
#include <string>
#include <vector>
#include <utility>
#include <cstring>
#include <cstdio>

extern uint64_t g_playerGuid;                       // dllmain.cpp
extern FrameScript_Execute_fn FrameScript_Execute;  // Utils.cpp

// ---- verified addresses (RE_VISUALS_FINDINGS.md) ----
typedef void*(__cdecl* ClntObjMgrObjectPtr_fn)(uint32_t lo, uint32_t hi, int typeMask, const char* file, int line);
static const ClntObjMgrObjectPtr_fn ClntObjMgrObjectPtr = (ClntObjMgrObjectPtr_fn)0x004D4DB0;
static const int VIS_TYPEMASK_UNIT = 0x0008;

// CGUnit_C::ApplyVisualKitDesc(this, KitDesc* desc) — attaches a SpellVisualKit's models
// to the unit. thiscall -> emulate with __fastcall(this, edx, desc).
typedef void(__fastcall* ApplyVisualKit_fn)(void* self, void* edx, void* desc);
static const ApplyVisualKit_fn ApplyVisualKit = (ApplyVisualKit_fn)0x00745230;

// CGUnit_C::RemoveVisualKitsBySpellRec(this, spellRec, flag) @ 0x00743B40 — walks the
// unit's visual-kit list (this+0xA8) and removes every node whose spellRec (node+0x18)
// equals the arg. Our injected kits carry NO spellRec (0), so (player, 0, 1) instantly
// removes exactly the visuals we applied, leaving real game-buff kits (nonzero spellRec)
// untouched. flag=1 bypasses the persistent-protection skip.  thiscall, ret 8.
typedef void(__fastcall* RemoveVisualKits_fn)(void* self, void* edx, void* spellRec, int flag);
static const RemoveVisualKits_fn RemoveVisualKits = (RemoveVisualKits_fn)0x00743B40;

// SpellVisual fast-path (row = rows[id - min]).
static const uintptr_t SV_MIN  = 0x00AD4AB8;
static const uintptr_t SV_MAX  = 0x00AD4AB4;
static const uintptr_t SV_ROWS = 0x00AD4AC8;
// SpellVisualKit fast-path.
static const uintptr_t SVK_MIN  = 0x00AD4A4C;
static const uintptr_t SVK_MAX  = 0x00AD4A48;
static const uintptr_t SVK_ROWS = 0x00AD4A5C;

// SpellVisual row kit-field byte offsets, LOOPABLE first. The loopable kits (state,
// stateDone, channel, precast) are continuous/ambient emitters that, attached as a
// type-8 state kit with duration -1, loop FOREVER on their own — exactly how the game
// shows infinite buff auras. The remaining kits (cast/impact/...) are momentary "poses"
// that play once; attaching those just makes the character look like it keeps casting,
// which is NOT what we want for a persistent target visual.
static const uint32_t SV_KIT_OFFS[] = {
    0x10, // [0] state       (persistent aura)  } LOOPABLE — attach all of these
    0x14, // [1] stateDone                       }
    0x18, // [2] channel                         }
    0x04, // [3] precast                         }
    0x08, // [4] cast         } momentary poses — only used as a last-resort fallback
    0x0C, // [5] impact       }
    0x38, // [6] casterImpact }
    0x3C, // [7] targetImpact }
};
static const int SV_KIT_COUNT    = sizeof(SV_KIT_OFFS) / sizeof(SV_KIT_OFFS[0]);
static const int SV_LOOPABLE     = 4;   // indices 0..3 above loop forever when attached

// The persistent-attach descriptor, laid out exactly like the inline one the client
// builds at 0x0071EC13 (TYPE 8 = persistent state attach, duration -1).
#pragma pack(push, 4)
struct KitDesc {
    uint32_t f00;       // 0
    uint32_t kitRow;    // +04 SpellVisualKit row ptr
    uint32_t type;      // +08 = 8
    uint32_t f0c, f10, f14;
    uint32_t f18;       // +18 = 1
    uint32_t f1c, f20;
    uint32_t f24;       // +24 = 0xFFFFFFFF
    uint32_t f28, f2c, f30;
};
#pragma pack(pop)

// ---- POD-only SEH leaf helpers (no C++ objects, so they can use __try freely) ----
static void* SafeResolvePlayer() {
    if (g_playerGuid == 0) return nullptr;
    __try {
        return ClntObjMgrObjectPtr((uint32_t)(g_playerGuid & 0xFFFFFFFFu),
                                   (uint32_t)(g_playerGuid >> 32), VIS_TYPEMASK_UNIT, "", 0);
    } __except (EXCEPTION_EXECUTE_HANDLER) { return nullptr; }
}
static void* SafeSpellVisualRow(uint32_t id) {
    __try {
        int mn = *(int*)SV_MIN, mx = *(int*)SV_MAX;
        if ((int)id < mn || (int)id > mx) return nullptr;
        void** rows = *(void***)SV_ROWS;
        if (!rows) return nullptr;
        return rows[id - mn];
    } __except (EXCEPTION_EXECUTE_HANDLER) { return nullptr; }
}
static void* SafeKitRow(uint32_t kitId) {
    __try {
        int mn = *(int*)SVK_MIN, mx = *(int*)SVK_MAX;
        if ((int)kitId < mn || (int)kitId > mx) return nullptr;
        void** rows = *(void***)SVK_ROWS;
        if (!rows) return nullptr;
        return rows[kitId - mn];
    } __except (EXCEPTION_EXECUTE_HANDLER) { return nullptr; }
}
// Reads every kit-slot of a SpellVisual row into out[SV_KIT_COUNT]; returns count of
// nonzero kits. out[0]=state, out[1]=stateDone, etc. (order = SV_KIT_OFFS).
static int SafeReadAllKits(void* row, uint32_t* out) {
    __try {
        int n = 0;
        for (int i = 0; i < SV_KIT_COUNT; ++i) {
            out[i] = *(uint32_t*)((uint8_t*)row + SV_KIT_OFFS[i]);
            if (out[i]) ++n;
        }
        return n;
    } __except (EXCEPTION_EXECUTE_HANDLER) { return 0; }
}
static bool SafeReadSVBounds(int* mn, int* mx, void*** rows) {
    __try {
        *mn = *(int*)SV_MIN; *mx = *(int*)SV_MAX; *rows = *(void***)SV_ROWS;
        return *rows != nullptr && *mx >= *mn;
    } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}
static bool SafeApply(void* player, KitDesc* d) {
    __try { ApplyVisualKit(player, nullptr, d); return true; }
    __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}
static void SafeRebuildModel(void* player) {
    if (!CGUnit_UpdateDisplayInfo) return;
    __try { CGUnit_UpdateDisplayInfo(player, 1); }
    __except (EXCEPTION_EXECUTE_HANDLER) {}
}
// INSTANT, definitive clear: walk the unit's visual-kit linked list (head @ this+0xA8,
// next @ node+0x108) and remove EVERY node via the engine's own removal vtable method
// (vtable+0xB8, thiscall(this, node)) — the exact call the game uses in 0x00743B40. This
// drops our applied visuals immediately; any real buff visuals the game owns are re-added
// by the client on its next aura update. Heavily guarded + iteration-capped.
static const uintptr_t UNIT_KITLIST_HEAD = 0xA8;
static const uintptr_t KITNODE_NEXT      = 0x108;
static const uintptr_t UNIT_VT_REMOVEKIT = 0xB8;  // byte offset into the CGUnit vtable
typedef void(__fastcall* RemoveKitNode_fn)(void* self, void* edx, void* node);
static const uintptr_t KITNODE_SPELLREC = 0x18;   // node+0x18 = backing spellRec (0 for ours)
// node+0x48 flags. Bit 0x20000 = "persistent / protected": the engine's own kit-cleanup
// (RemoveVisualKits @0x00743B40) SKIPS a node with this bit unless called with flag!=0.
// Real buff-aura state kits carry it; setting it on OUR injected nodes makes the engine's
// routine visual GCs leave them alone (our own removal walks the list directly, ignoring it).
static const uintptr_t KITNODE_FLAGS         = 0x48;
static const uint32_t  KITNODE_FLAG_PERSIST  = 0x20000;
static void SafeProtectNode(void* node) {
    __try {
        if (node && (uintptr_t)node >= 0x10000)
            *(uint32_t*)((uint8_t*)node + KITNODE_FLAGS) |= KITNODE_FLAG_PERSIST;
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
}

// ============================================================================
// ★ THE "never expires, seamless loop" fix — keep the ONE original emitter alive (no re-fire).
// A real buff aura (Shadowmourne) shows ONE continuous particle emitter that loops forever — it is
// NEVER re-spawned, which is why it looks perfectly smooth. We do exactly that: attach the kit ONCE
// and keep its emitter running, so there is never a despawn/respawn "pulse". RE (RE_VISUALS_FINDINGS):
// applied kits land in a per-unit EMITTER-SLOT array (separate from the +0xA8 node list). The
// per-frame processor 0x00728140 reads, per active slot:
//     if ((int)(clock[0xCD76AC] - slot+0x2C) < 0)  keep it alive (still pending)
//     else  deactivate (clear slot+0x24 bit 0x08)  unless slot+0x28 == 1
// The factory 0x72AF60 seeds slot+0x2C = clock + 0x2710 (10000 ms), so the slot would deactivate
// ~10 s after attach. We PIN slot+0x2C far into the future every tick for OUR exact slots, so the
// engine never deactivates them → the original continuous emitter keeps running forever with ZERO
// re-apply ⇒ a true seamless loop, never a flicker/spawn. (Combined with the node 0x20000 protect
// + the model-rebuild watchdog below.) A genuinely FINITE one-shot kit will still finish its own
// animation — that is inherent to the asset; we never paper over it with an ugly periodic respawn.
static const uintptr_t UNIT_KITSLOT_COUNT = 0xF4C;   // dword: number of slots
static const uintptr_t UNIT_KITSLOT_ARRAY = 0xF50;   // ptr: base of slot array
static const uintptr_t SLOT_STRIDE        = 0x30;
static const uintptr_t SLOT_KITID         = 0x04;    // *kitRow == SpellVisualKit DBC id
static const uintptr_t SLOT_FLAGS         = 0x24;    // bit 0x08 = active/pending
static const uintptr_t SLOT_EXPIRE        = 0x2C;    // engine: (clock - this) < 0 ⇒ keep alive
static const uint32_t  SLOT_ACTIVE_BIT    = 0x08;
static const uintptr_t G_VISUAL_CLOCK     = 0x00CD76AC;
static const uint32_t  SLOT_KEEPALIVE_AHEAD = 0x00100000; // push expiry ~17 min ahead each tick

// One emitter slot WE created: its address in the +0xF50 array plus the kit id that lived in it
// at creation. We track by EXACT slot (not by kit id), so a real game effect that happens to use
// the same SpellVisualKit is never matched. kitId is only a recycle-guard: if the engine freed
// our slot and the index now holds a different kit, the id won't match and we skip it.
struct SlotRef { void* slot; uint32_t kitId; };

// POD-only SEH leaf: snapshot the ACTIVE emitter slots into out[0..cap); returns the count.
static int SafeReadActiveSlots(void* player, SlotRef* out, int cap) {
    __try {
        uint32_t count = *(uint32_t*)((uint8_t*)player + UNIT_KITSLOT_COUNT);
        if (count == 0 || count > 8192) return 0;               // sanity bound
        uint8_t* base = *(uint8_t**)((uint8_t*)player + UNIT_KITSLOT_ARRAY);
        if (!base || (uintptr_t)base < 0x10000) return 0;
        int n = 0;
        for (uint32_t i = 0; i < count && n < cap; ++i) {
            uint8_t* slot = base + i * SLOT_STRIDE;
            if (!(*(uint32_t*)(slot + SLOT_FLAGS) & SLOT_ACTIVE_BIT)) continue;
            out[n].slot  = slot;
            out[n].kitId = *(uint32_t*)(slot + SLOT_KITID);
            ++n;
        }
        return n;
    } __except (EXCEPTION_EXECUTE_HANDLER) { return 0; }
}

// POD-only SEH leaf: push the expiry of OUR exact tracked slots far into the future so the engine's
// 0x728140 loop never deactivates them → the original emitter keeps running forever (no re-apply,
// no flicker, no spawn). Each ref is validated against the LIVE array bounds + alignment + active
// bit + matching kit id before any write, so a stale/recycled ref can never corrupt memory or pin
// someone else's effect. Pure timestamp writes ⇒ zero visual side effect. Because our slots are
// always "kept", the loop's tail never hits kept==0, so the array never compacts (0x723170) while
// visuals are up ⇒ our slot pointers stay valid frame-to-frame.
static void SafePinTrackedSlots(void* player, const SlotRef* refs, int n) {
    if (n <= 0) return;
    __try {
        uint32_t count = *(uint32_t*)((uint8_t*)player + UNIT_KITSLOT_COUNT);
        if (count == 0 || count > 8192) return;
        uint8_t* base = *(uint8_t**)((uint8_t*)player + UNIT_KITSLOT_ARRAY);
        if (!base || (uintptr_t)base < 0x10000) return;
        uint8_t* end = base + count * SLOT_STRIDE;
        uint32_t future = *(uint32_t*)G_VISUAL_CLOCK + SLOT_KEEPALIVE_AHEAD;
        for (int i = 0; i < n; ++i) {
            uint8_t* slot = (uint8_t*)refs[i].slot;
            if (slot < base || slot >= end) continue;                       // not in live array
            if ((uint32_t)((slot - base) % SLOT_STRIDE) != 0) continue;     // misaligned
            if (!(*(uint32_t*)(slot + SLOT_FLAGS) & SLOT_ACTIVE_BIT)) continue;
            if (*(uint32_t*)(slot + SLOT_KITID) != refs[i].kitId) continue; // recycled → skip
            *(uint32_t*)(slot + SLOT_EXPIRE) = future;
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
}
// Remove kit nodes. If onlyMine, removes only nodes with spellRec==0 (the ones WE injected),
// leaving real game-buff kits (nonzero spellRec) running — so a periodic re-assert never
// nukes the player's real buff visuals. If !onlyMine, removes everything (hard clear).
static void SafeRemoveKits(void* player, bool onlyMine) {
    __try {
        void** vt = *(void***)player;
        if (!vt) return;
        RemoveKitNode_fn rm = (RemoveKitNode_fn)vt[UNIT_VT_REMOVEKIT / 4];
        if (!rm) return;
        void* node = *(void**)((uint8_t*)player + UNIT_KITLIST_HEAD);
        int guard = 0;
        while (node && (uintptr_t)node > 0x10000 && guard++ < 256) {
            void* next = *(void**)((uint8_t*)node + KITNODE_NEXT);
            bool mine = (*(uint32_t*)((uint8_t*)node + KITNODE_SPELLREC) == 0);
            if (!onlyMine || mine) rm(player, nullptr, node);
            node = next;
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
}
static void SafeRemoveAllKits(void* player) { SafeRemoveKits(player, false); }
static void SafeRemoveMyKits(void* player)  { SafeRemoveKits(player, true);  }

// Active visuals. Each is attached ONCE (loopable state kit, TYPE 8, duration -1) and then kept
// alive by pinning its emitter slots (above) — NEVER re-fired — so the original continuous emitter
// loops forever, exactly like a real buff aura: a true seamless loop, no respawn, no flicker. We
// remember, per visual, the kit-list nodes it spawned (for surgical remove without flashing the
// others) and the emitter slots it created (pinned every tick). See RE_VISUALS_FINDINGS.md.
struct ActiveVisual {
    uint32_t id;
    std::vector<void*>   nodes;   // kit-list nodes this visual added to unit+0xA8 (this session)
    std::vector<SlotRef> slots;   // emitter slots this visual created (pinned to never expire)
};
static std::vector<ActiveVisual> g_activeVisuals;

// Watchdog gate ("Survive morphs & relogs"). When false, dropped visuals are not re-attached
// (session-only). Default on. Declared early so the diagnostic + tick can read it.
static bool g_visualsAutoHeal = true;

static ActiveVisual* FindActive(uint32_t id) {
    for (auto& a : g_activeVisuals) if (a.id == id) return &a;
    return nullptr;
}

// Walk the unit's visual-kit linked list (head @ unit+0xA8, next @ node+0x108) collecting
// every live node pointer. Heavily guarded + iteration-capped. Used to diff before/after an
// attach (to learn which nodes a visual spawned) and to validate tracked pointers are still
// live before we ever call the per-node destructor on them.
static void SafeCollectKitNodes(void* player, std::vector<void*>& out) {
    out.clear();
    __try {
        void* node = *(void**)((uint8_t*)player + UNIT_KITLIST_HEAD);
        int guard = 0;
        while (node && (uintptr_t)node > 0x10000 && guard++ < 256) {
            out.push_back(node);
            node = *(void**)((uint8_t*)node + KITNODE_NEXT);
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) { /* leave what we gathered */ }
}

// ---- POD-only SEH leaves for surgical node removal (no C++ objects, so __try is legal) ----
// Fetch the unit's per-node destructor (unit_vtbl+0xB8) — the exact call the engine uses in
// 0x00743B40.
static RemoveKitNode_fn SafeGetRemoveFn(void* player) {
    __try {
        void** vt = *(void***)player;
        if (!vt) return nullptr;
        return (RemoveKitNode_fn)vt[UNIT_VT_REMOVEKIT / 4];
    } __except (EXCEPTION_EXECUTE_HANDLER) { return nullptr; }
}
// True if `node` is still reachable in the live kit list (so we never feed the destructor a
// stale / already-freed pointer).
static bool SafeNodeIsLive(void* player, void* node) {
    __try {
        void* cur = *(void**)((uint8_t*)player + UNIT_KITLIST_HEAD);
        int guard = 0;
        while (cur && (uintptr_t)cur > 0x10000 && guard++ < 256) {
            if (cur == node) return true;
            cur = *(void**)((uint8_t*)cur + KITNODE_NEXT);
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
    return false;
}
static void SafeCallRemove(RemoveKitNode_fn rm, void* player, void* node) {
    __try { rm(player, nullptr, node); } __except (EXCEPTION_EXECUTE_HANDLER) {}
}

// Remove a specific set of nodes from the unit, but ONLY those still present in the live list.
// (Plain C++ wrapper — no __try here, so the std::vector iteration is fine.)
static void SafeRemoveNodeSet(void* player, const std::vector<void*>& nodes) {
    if (nodes.empty()) return;
    RemoveKitNode_fn rm = SafeGetRemoveFn(player);
    if (!rm) return;
    for (void* n : nodes) {
        if (!n || (uintptr_t)n < 0x10000) continue;
        if (SafeNodeIsLive(player, n)) SafeCallRemove(rm, player, n);
    }
}

// ---- targeted sound mute (only the visuals applied here, not global SFX) ----
// We zero the sound ids on the exact SpellVisual rows + SpellVisualKit rows our active
// visuals use, remembering each original so it can be restored on unmute / clear.
static bool g_muteSounds = false;
struct SavedSound { uint32_t* addr; uint32_t orig; };
static std::vector<SavedSound> g_savedSounds;
// SpellVisual sound fields: missileSound +0x2C, animEventSound +0x30.
// SpellVisualKit sound id (DBC field 15, 4 bytes/field) -> +0x3C.
static const uint32_t SV_MISSILE_SOUND = 0x2C;
static const uint32_t SV_ANIM_SOUND    = 0x30;
static const uint32_t SVK_SOUND_ID     = 0x3C;

static void MuteField(uint32_t* addr) {
    __try {
        if (!addr || (uintptr_t)addr < 0x10000) return;
        uint32_t v = *addr;
        if (v == 0) return;                       // already silent
        g_savedSounds.push_back({ addr, v });
        *addr = 0;
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
}
static void MuteVisualSounds(uint32_t visualId) {
    if (!g_muteSounds) return;
    void* row = SafeSpellVisualRow(visualId);
    if (!row || (uintptr_t)row < 0x10000) return;
    __try {
        MuteField((uint32_t*)((uint8_t*)row + SV_MISSILE_SOUND));
        MuteField((uint32_t*)((uint8_t*)row + SV_ANIM_SOUND));
        uint32_t kits[SV_KIT_COUNT] = {0};
        if (SafeReadAllKits(row, kits) > 0) {
            for (int i = 0; i < SV_KIT_COUNT; ++i) {
                if (!kits[i]) continue;
                void* kr = SafeKitRow(kits[i]);
                if (kr && (uintptr_t)kr >= 0x10000)
                    MuteField((uint32_t*)((uint8_t*)kr + SVK_SOUND_ID));
            }
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
}
static void RestoreAllSounds() {
    for (auto& s : g_savedSounds) {
        __try { if (s.addr && (uintptr_t)s.addr >= 0x10000) *s.addr = s.orig; }
        __except (EXCEPTION_EXECUTE_HANDLER) {}
    }
    g_savedSounds.clear();
}

static bool AttachOneKit(void* player, uint32_t kitId) {
    if (kitId == 0) return false;
    void* kitRow = SafeKitRow(kitId);
    if (!kitRow || (uintptr_t)kitRow < 0x10000) return false;
    KitDesc d; std::memset(&d, 0, sizeof(d));
    d.kitRow = (uint32_t)(uintptr_t)kitRow;
    d.type   = 8;            // persistent state attach
    d.f18    = 1;
    d.f24    = 0xFFFFFFFF;   // duration -1
    return SafeApply(player, &d);
}

// Attach a visual's LOOPABLE kits (state/stateDone/channel/precast) so the effect loops
// FOREVER on its own — exactly how the game shows an infinite buff aura (TYPE 8, duration
// -1). Momentary cast/impact "poses" are only used as a last resort (so we never make the
// character look like it keeps casting). If `av` is non-null, the kit-list NODES (unit+0xA8)
// and the emitter SLOTS (unit+0xF50) this attach spawned are recorded into it — diffed against
// before/after snapshots — so the visual can be removed/replayed surgically AND kept alive
// (slots pinned). Does NOT touch the active set.
static bool AttachVisual(void* player, uint32_t visualId, ActiveVisual* av = nullptr) {
    void* row = SafeSpellVisualRow(visualId);
    if (!row || (uintptr_t)row < 0x10000) return false;
    uint32_t kits[SV_KIT_COUNT] = {0};
    if (SafeReadAllKits(row, kits) == 0) return false;

    std::vector<void*> nodesBefore;
    SlotRef slotsBefore[128]; int nSlotsBefore = 0;
    if (av) {
        SafeCollectKitNodes(player, nodesBefore);
        nSlotsBefore = SafeReadActiveSlots(player, slotsBefore, 128);
    }

    bool applied = false;
    for (int i = 0; i < SV_LOOPABLE; ++i)            // attach every loopable kit present
        if (AttachOneKit(player, kits[i])) applied = true;
    if (!applied) {                                   // no loopable kit: best-effort pose
        for (int i = SV_LOOPABLE; i < SV_KIT_COUNT; ++i)
            if (AttachOneKit(player, kits[i])) { applied = true; break; }
    }

    if (av && applied) {
        // nodes that just appeared on unit+0xA8 (for surgical remove/replay + persist-protect)
        av->nodes.clear();
        std::vector<void*> nodesAfter;
        SafeCollectKitNodes(player, nodesAfter);
        for (void* n : nodesAfter) {
            bool existed = false;
            for (void* b : nodesBefore) if (b == n) { existed = true; break; }
            if (!existed) { av->nodes.push_back(n); SafeProtectNode(n); }
        }
        // emitter slots that just appeared on unit+0xF50 (for keep-alive pinning)
        av->slots.clear();
        SlotRef slotsAfter[128];
        int nSlotsAfter = SafeReadActiveSlots(player, slotsAfter, 128);
        for (int i = 0; i < nSlotsAfter; ++i) {
            bool existed = false;
            for (int j = 0; j < nSlotsBefore; ++j)
                if (slotsBefore[j].slot == slotsAfter[i].slot) { existed = true; break; }
            if (!existed) av->slots.push_back(slotsAfter[i]);
        }
    }
    return applied;
}

// ---- public API ----
bool Visuals_ApplyToPlayer(uint32_t visualId) {
    void* player = SafeResolvePlayer();
    if (!player || (uintptr_t)player < 0x10000) return false;
    if (FindActive(visualId)) return true;          // already on
    if (g_muteSounds) MuteVisualSounds(visualId);   // silence its sounds before it plays
    ActiveVisual av; av.id = visualId;
    if (!AttachVisual(player, visualId, &av)) return false;
    g_activeVisuals.push_back(std::move(av));
    return true;
}

void Visuals_SetMuteSounds(bool on) {
    g_muteSounds = on;
    if (on) { for (auto& a : g_activeVisuals) MuteVisualSounds(a.id); }
    else    { RestoreAllSounds(); }
}

void Visuals_RemoveFromPlayer(uint32_t visualId) {
    void* player = SafeResolvePlayer();
    for (size_t i = 0; i < g_activeVisuals.size(); ++i) {
        if (g_activeVisuals[i].id != visualId) continue;
        // Surgical: drop ONLY this visual's nodes; every other active visual stays untouched
        // (no flash). If the player can't be resolved we still forget it from the active set.
        if (player && (uintptr_t)player >= 0x10000)
            SafeRemoveNodeSet(player, g_activeVisuals[i].nodes);
        g_activeVisuals.erase(g_activeVisuals.begin() + i);
        return;
    }
}

// Re-fire ONE visual surgically (attach a fresh instance ON TOP, then drop the previous instance's
// nodes — the brief overlap hides the swap). Only used for the rare genuinely-finite "pose" kit a
// user explicitly re-triggers (VIS_REPLAY); looping state visuals never need this — they persist
// natively via the slot pin.
void Visuals_Replay(uint32_t visualId) {
    void* player = SafeResolvePlayer();
    if (!player || (uintptr_t)player < 0x10000) return;
    ActiveVisual* a = FindActive(visualId);
    if (!a) return;
    if (g_muteSounds) MuteVisualSounds(visualId);
    std::vector<void*> prevNodes = a->nodes;
    AttachVisual(player, visualId, a);                            // new instance up first
    if (!prevNodes.empty()) SafeRemoveNodeSet(player, prevNodes); // then retire the old one
}

// Re-attach ALL active visuals (after a model rebuild dropped them). The rebuild already
// invalidated every node, so we just re-attach each visual and refresh its node list. Used
// after morphs / forms / zoning.
void Visuals_Reapply() {
    if (g_activeVisuals.empty()) return;
    void* player = SafeResolvePlayer();
    if (!player || (uintptr_t)player < 0x10000) return;
    SafeRemoveMyKits(player);                        // drop any of ours the rebuild left behind
    for (auto& a : g_activeVisuals) {
        if (g_muteSounds) MuteVisualSounds(a.id);
        AttachVisual(player, a.id, &a);
    }
}

bool Visuals_HasActive() { return !g_activeVisuals.empty(); }

// Self-healing watchdog — the core of "never expires". A character visual is an orphan kit
// (no aura backing), so anything that rebuilds the player's model or runs a visual GC drops
// it and, unlike a real buff, nothing re-drives it. Each tick we check whether a visual's
// tracked nodes are STILL in the live kit list; only if a visual has FULLY vanished do we
// re-attach it. Alive loopers are never touched, so there is no cut/restart flicker — we act
// exactly when (and only when) the engine actually dropped something. This is what gives a
// real buff its permanence (continuous re-drive), applied to our orphan kits. Cheap: a couple
// of capped list walks, throttled to ~4x/sec.
// g_visualsAutoHeal is declared near the active-visuals globals (above). When false, the
// watchdog stops re-attaching dropped visuals — they become session-only and fall off on the
// next model rebuild. The active set is still remembered, so toggling back on re-heals them.
void Visuals_SetAutoHeal(bool on) { g_visualsAutoHeal = on; }

void Visuals_Tick() {
    if (g_activeVisuals.empty()) return;
    static int throttle = 0;
    if (++throttle < 5) return;       // dllmain ticks ~50ms → ~250ms cadence
    throttle = 0;

    void* player = SafeResolvePlayer();
    if (!player || (uintptr_t)player < 0x10000) return;

    // (1) KEEP-ALIVE — THE fix for a seamless loop. For each visual, push the expiry of the EXACT
    // emitter slots it created far into the future so the engine's 10 s lifetime (0x728140) never
    // deactivates them. The ORIGINAL continuous emitter just keeps running — no re-apply, no
    // respawn, no flicker = a true loop, exactly like a real buff aura. We pin only our own tracked
    // slots (validated against the live array), so a real game effect sharing the same kit is never
    // touched. Runs ALWAYS (even with auto-heal off): "don't survive relogs" must not mean "expire
    // after 10 seconds mid-session". Pure timestamp writes ⇒ zero visual side effect.
    for (auto& a : g_activeVisuals)
        if (!a.slots.empty()) SafePinTrackedSlots(player, a.slots.data(), (int)a.slots.size());

    // (2) NODE WATCHDOG — gated by auto-heal. Re-attach a visual ONLY if its tracked nodes have
    // FULLY vanished (whole-model rebuild: morph / form / zone). The keep-alive above handles the
    // 10 s slot lifetime seamlessly; this is the safety net for a model rebuild that drops every
    // attached kit. Never touches an alive visual, so there is no cut/restart flicker.
    if (!g_visualsAutoHeal) return;
    std::vector<void*> live;
    SafeCollectKitNodes(player, live);
    for (auto& a : g_activeVisuals) {
        // No tracked nodes → nothing to compare; re-attaching blindly would stack kits (leak).
        if (a.nodes.empty()) continue;
        bool present = false;
        for (void* n : a.nodes) {
            for (void* l : live) if (l == n) { present = true; break; }
            if (present) break;
        }
        if (!present) {
            if (g_muteSounds) MuteVisualSounds(a.id);
            AttachVisual(player, a.id, &a);
            SafeCollectKitNodes(player, live);   // refresh so new nodes aren't re-triggered
        }
    }
}

void Visuals_Clear() {
    g_activeVisuals.clear();
    RestoreAllSounds();   // un-mute the rows we touched
    void* player = SafeResolvePlayer();
    if (!player || (uintptr_t)player < 0x10000) return;
    // HARD clear: remove every attached visual-kit node from the unit's list AND rebuild
    // the model. Either alone may miss a path; together they guarantee an instant, total
    // wipe of everything we put on the character.
    SafeRemoveAllKits(player);
    SafeRebuildModel(player);
    SafeRemoveAllKits(player);   // again post-rebuild in case the rebuild re-seeded any
}

void Visuals_EnumerateToLua() {
    if (!FrameScript_Execute) return;
    int mn = 0, mx = 0; void** rows = nullptr;
    std::string list;
    if (SafeReadSVBounds(&mn, &mx, &rows)) {
        for (int id = mn; id <= mx; ++id) {            // no artificial cap — list them all
            void* row = rows[id - mn];                 // index already validated by bounds
            if (!row || (uintptr_t)row < 0x10000) continue;
            uint32_t kits[SV_KIT_COUNT] = {0};
            if (SafeReadAllKits(row, kits) == 0) continue;   // a REAL visual has >=1 kit
            // visualId:spellId — spellId (a spell using this visual) lets Lua resolve a
            // real name + icon via GetSpellInfo. 0 when no spell references the visual.
            uint32_t spellId = SpellMorph_FindSpellForVisual((uint32_t)id);
            char buf[32];
            sprintf_s(buf, sizeof(buf), "%d:%u,", id, spellId);
            list += buf;
        }
    }

    FrameScript_Execute("TRANSMORPHER_VISUALS = ''", "Transmorpher", 0);
    const size_t CHUNK = 3000;
    for (size_t i = 0; i < list.size(); i += CHUNK) {
        std::string cmd = "TRANSMORPHER_VISUALS = TRANSMORPHER_VISUALS .. '" + list.substr(i, CHUNK) + "'";
        FrameScript_Execute(cmd.c_str(), "Transmorpher", 0);
    }
    FrameScript_Execute("if TransmorpherOnVisualsReady then TransmorpherOnVisualsReady() end",
                        "Transmorpher", 0);
}
