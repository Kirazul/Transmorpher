#include "SpellMorph.h"
#include "Logger.h"
#include "Utils.h"
#include <windows.h>
#include <psapi.h>
#include <unordered_map>
#include <vector>
#include <cstring>
#include <string>
#include <algorithm>
#include <cmath>
#include <memory>

namespace {
    // Option to hide all spell visuals from other players
    static bool g_hideAllOtherSpells = false;

    // Expose to Lua/command bridge
    void SetHideAllOtherSpells(bool hide) { g_hideAllOtherSpells = hide; }
    bool GetHideAllOtherSpells() { return g_hideAllOtherSpells; }
    struct SpellRec {
        int32_t m_ID;
        // ... many fields ...
        int32_t m_spellVisualID[2];
        // ... rest ...
    };

    struct SpellVisualRec {
        int32_t m_ID;
        int32_t m_precastKit;
        int32_t m_castKit;
        int32_t m_impactKit;
        int32_t m_stateKit;
        int32_t m_stateDoneKit;
        int32_t m_channelKit;
        int32_t m_hasMissile;
        int32_t m_missileModel;
        int32_t m_missilePathType;
        int32_t m_missileDestinationAttachment;
        int32_t m_missileSound;
        int32_t m_animEventSoundID;
        int32_t m_flags;
        int32_t m_casterImpactKit;
        int32_t m_targetImpactKit;
        int32_t m_missileAttachment;
        int32_t m_missileFollowGroundHeight;
        int32_t m_missileFollowGroundDropSpeed;
        int32_t m_missileFollowGroundApproach;
        int32_t m_missileFollowGroundFlags;
        int32_t m_missileMotion;
        int32_t m_missileTargetingKit;
        int32_t m_instantAreaKit;
        int32_t m_impactAreaKit;
        int32_t m_persistentAreaKit;
        float m_missileCastOffset[3];
        float m_missileImpactOffset[3];
    };

    static const uintptr_t ADDR_GET_SPELL_VISUAL_ROW = 0x007FA290;
    static const size_t MAX_SPELL_MORPHS = 128;

    typedef SpellVisualRec* (__cdecl* GetSpellVisualRowFn)(SpellRec*);

    // RAII Lock wrappers to prevent deadlocks on exceptions/early returns
    struct SharedLock {
        SRWLOCK* lock;
        SharedLock(SRWLOCK* l) : lock(l) { AcquireSRWLockShared(lock); }
        ~SharedLock() { ReleaseSRWLockShared(lock); }
    };
    struct ExclusiveLock {
        SRWLOCK* lock;
        ExclusiveLock(SRWLOCK* l) : lock(l) { AcquireSRWLockExclusive(lock); }
        ~ExclusiveLock() { ReleaseSRWLockExclusive(lock); }
    };

    static std::unordered_map<uint32_t, uint32_t> g_spellMorphs;
    static std::unordered_map<uint32_t, uint32_t> g_visualOverrides;
    static SRWLOCK g_spellMorphLock = SRWLOCK_INIT;

    static bool g_hookInstalled = false;
    static BYTE g_originalBytes[5] = {0};
    static void* g_trampoline = nullptr;
    static GetSpellVisualRowFn g_originalGetSpellVisualRow = nullptr;
    static std::unordered_map<uint32_t, std::pair<uint32_t, uint32_t>> g_spellIdToVisualIdMap;
    static std::unordered_map<uint32_t, void*> g_spellRowPointers; // Memory addresses of Spell.dbc rows
    static std::unordered_map<uint32_t, uint32_t> g_originalMissileIds; // Original Field 227 values
    static std::unordered_map<uint32_t, std::string> g_spellNames;
    static std::vector<uint8_t> g_spellStringTable;
    static bool g_dbcPreloaded = false;
    static std::unordered_map<uint32_t, bool> g_validVisualKits;
    static std::unordered_map<uint32_t, bool> g_validEffectNames;
    static std::unordered_map<uint32_t, bool> g_validSpellMissiles;
    static std::unordered_map<uint32_t, bool> g_validSpellMissileMotions;
    static std::unordered_map<uint32_t, std::vector<uint8_t>> g_spellVisualRecs;
    static std::unordered_map<uint64_t, std::unique_ptr<SpellVisualRec>> g_sanitizedVisuals;
    static uint32_t g_morphGeneration = 0; // Incremented on change to ensure "soft reset" without invalidating pointers
    static SpellVisualRec g_nullVisualRec = {};

    static void SoftResetCache() {
        AcquireSRWLockExclusive(&g_spellMorphLock);
        g_morphGeneration++; // New lookups will use new keys, old pointers stay valid in the map
        ReleaseSRWLockExclusive(&g_spellMorphLock);
    }

    static bool PreloadIdsFromDBC(const char* primary, const char* fallback1, const char* fallback2,
                                  std::unordered_map<uint32_t, bool>& outSet, const char* label) {
        FILE* f = nullptr;
        const char* path = primary;
        if (fopen_s(&f, path, "rb") != 0 || !f) {
            path = fallback1;
            if (fopen_s(&f, path, "rb") != 0 || !f) {
                path = fallback2;
                fopen_s(&f, path, "rb");
            }
        }
        if (!f) return false;

        uint32_t h[5] = { 0,0,0,0,0 };
        if (fread(h, 4, 5, f) != 5 || h[0] != 0x43424457 || h[3] < 4) {
            fclose(f);
            Log("WARNING: Invalid DBC header for %s (%s)", label, path);
            return false;
        }

        outSet.clear();
        for (uint32_t i = 0; i < h[1]; ++i) {
            uint32_t id = 0;
            if (fread(&id, 4, 1, f) != 1) break;
            outSet[id] = true;
            if (fseek(f, h[3] - 4, SEEK_CUR) != 0) break;
        }
        fclose(f);
        Log("Preloaded %zu %s records for validation", outSet.size(), label);
        return !outSet.empty();
    }

    static void PreloadValidationDBCs() {
        PreloadIdsFromDBC(
            "Interface\\AddOns\\Transmorpher\\DBC\\SpellVisualKit.dbc",
            "Data\\DBFilesClient\\SpellVisualKit.dbc",
            "dbc2\\DBFilesClient\\SpellVisualKit.dbc",
            g_validVisualKits,
            "SpellVisualKit");

        PreloadIdsFromDBC(
            "Interface\\AddOns\\Transmorpher\\DBC\\SpellVisualEffectName.dbc",
            "Data\\DBFilesClient\\SpellVisualEffectName.dbc",
            "dbc2\\DBFilesClient\\SpellVisualEffectName.dbc",
            g_validEffectNames,
            "SpellVisualEffectName");

        PreloadIdsFromDBC(
            "Interface\\AddOns\\Transmorpher\\DBC\\SpellMissile.dbc",
            "Data\\DBFilesClient\\SpellMissile.dbc",
            "dbc\\DBFilesClient\\SpellMissile.dbc",
            g_validSpellMissiles,
            "SpellMissile");

        PreloadIdsFromDBC(
            "Interface\\AddOns\\Transmorpher\\DBC\\SpellMissileMotion.dbc",
            "Data\\DBFilesClient\\SpellMissileMotion.dbc",
            "dbc\\DBFilesClient\\SpellMissileMotion.dbc",
            g_validSpellMissileMotions,
            "SpellMissileMotion");
    }

    static void PreloadSpellVisualDBC() {
        const char* path = "Interface\\AddOns\\Transmorpher\\DBC\\SpellVisual.dbc";
        Log("Preloading SpellVisual.dbc (Priority: %s)", path);

        PreloadValidationDBCs(); // Load validation data first

        FILE* f = nullptr;
        if (fopen_s(&f, path, "rb") != 0 || !f) {
            path = "Data\\DBFilesClient\\SpellVisual.dbc";
            if (fopen_s(&f, path, "rb") != 0 || !f) {
                path = "dbc2\\DBFilesClient\\SpellVisual.dbc";
                if (fopen_s(&f, path, "rb") != 0 || !f) {
                    Log("ERROR: Could not find SpellVisual.dbc in addon or Data folder");
                    return;
                }
            }
        }

        struct DBCHeader {
            uint32_t magic, numRecords, numFields, recordSize, stringTableSize;
        } header;

        if (fread(&header, sizeof(header), 1, f) != 1 || header.magic != 0x43424457) {
            fclose(f); return;
        }

        std::vector<uint8_t> buffer(header.recordSize);
        for (uint32_t i = 0; i < header.numRecords; ++i) {
            if (fread(buffer.data(), header.recordSize, 1, f) != 1) break;
            uint32_t vid = *reinterpret_cast<uint32_t*>(buffer.data());
            g_spellVisualRecs[vid] = buffer;
        }
        fclose(f);
        Log("Preloaded %u visual records from disk", (uint32_t)g_spellVisualRecs.size());
    }

    static void PreloadSpellDBC() {
        if (g_dbcPreloaded) return;
        g_dbcPreloaded = true;

        PreloadSpellVisualDBC();

        const char* path = "Interface\\AddOns\\Transmorpher\\DBC\\Spell.dbc";
        Log("Preloading Spell.dbc (Priority: %s)", path);

        FILE* f = nullptr;
        if (fopen_s(&f, path, "rb") != 0 || !f) {
            path = "Data\\DBFilesClient\\Spell.dbc";
            if (fopen_s(&f, path, "rb") != 0 || !f) {
                path = "dbc2\\DBFilesClient\\Spell.dbc";
                if (fopen_s(&f, path, "rb") != 0 || !f) {
                    Log("ERROR: Could not find Spell.dbc in addon or Data folder");
                    return;
                }
            }
        }

        struct DBCHeader {
            uint32_t magic, numRecords, numFields, recordSize, stringTableSize;
        } h;

        if (fread(&h, sizeof(h), 1, f) != 1) {
            Log("ERROR: Could not read DBC header");
            fclose(f); return;
        }

        std::vector<uint8_t> records(h.numRecords * h.recordSize);
        fread(records.data(), h.recordSize, h.numRecords, f);
        
        g_spellStringTable.resize(h.stringTableSize);
        fread(g_spellStringTable.data(), 1, h.stringTableSize, f);
        fclose(f);

        // Name is at field 136 in 3.3.5.12340
        const uint32_t NAME_OFFSET = 136 * 4;
        const uint32_t VISUAL_OFFSET = 131 * 4;

        for (uint32_t i = 0; i < h.numRecords; ++i) {
            uint8_t* rec = &records[i * h.recordSize];
            uint32_t id = *reinterpret_cast<uint32_t*>(rec);
            // Field 131 and 132 are SpellVisualID[0] and [1]
            uint32_t v0 = *reinterpret_cast<uint32_t*>(rec + VISUAL_OFFSET);
            uint32_t v1 = *reinterpret_cast<uint32_t*>(rec + VISUAL_OFFSET + 4);
            // Field 227 is SpellMissileID
            uint32_t mId = *reinterpret_cast<uint32_t*>(rec + 227 * 4);
            
            g_spellIdToVisualIdMap[id] = {v0, v1};
            g_spellRowPointers[id] = (void*)rec;
            g_originalMissileIds[id] = mId;

            uint32_t namePtr = *reinterpret_cast<uint32_t*>(rec + NAME_OFFSET);
            if (namePtr < h.stringTableSize) {
                const char* nameStr = reinterpret_cast<const char*>(g_spellStringTable.data() + namePtr);
                if (nameStr && nameStr[0] != '\0') {
                    g_spellNames[id] = nameStr;
                }
            }
        }
        Log("Preloaded %zu spells and names", g_spellNames.size());
    }

    static std::unordered_map<uint32_t, uint32_t> g_spellToVisualCache;

    static SpellRec* GetSpellRecById(uint32_t spellId) {
        return nullptr;
    }

    static const SpellVisualRec* GetSafeSpellVisualRec(uint32_t visualId) {
        auto it = g_spellVisualRecs.find(visualId);
        if (it != g_spellVisualRecs.end() && it->second.size() >= sizeof(SpellVisualRec)) {
            return reinterpret_cast<const SpellVisualRec*>(it->second.data());
        }
        return nullptr;
    }

    static bool SanitizeSpellVisualRec(SpellVisualRec* rec, const SpellVisualRec* original) {
        if (!rec) return false;

        auto ValidKit = [](int32_t id) {
            if (id == 0 || id == -1) return true;
            if (id < 0 || id > 1000000) return false;
            return g_validVisualKits.count((uint32_t)id) > 0;
        };

        if (!ValidKit(rec->m_precastKit)) return false;
        if (!ValidKit(rec->m_castKit)) return false;
        if (!ValidKit(rec->m_impactKit)) return false;
        if (!ValidKit(rec->m_stateKit)) return false;
        if (!ValidKit(rec->m_stateDoneKit)) return false;
        if (!ValidKit(rec->m_channelKit)) return false;
        if (!ValidKit(rec->m_casterImpactKit)) return false;
        if (!ValidKit(rec->m_targetImpactKit)) return false;
        if (!ValidKit(rec->m_instantAreaKit)) return false;
        if (!ValidKit(rec->m_impactAreaKit)) return false;
        if (!ValidKit(rec->m_persistentAreaKit)) return false;
        if (!ValidKit(rec->m_missileTargetingKit)) return false;

        // Safety: Ensure floats are finite to prevent FPU-related crashes/freezes.
        for (int i = 0; i < 3; ++i) {
            if (!std::isfinite(rec->m_missileCastOffset[i])) rec->m_missileCastOffset[i] = 0.0f;
            if (!std::isfinite(rec->m_missileImpactOffset[i])) rec->m_missileImpactOffset[i] = 0.0f;
        }

        if (rec->m_hasMissile < 0 || rec->m_hasMissile > 1) rec->m_hasMissile = (rec->m_hasMissile != 0) ? 1 : 0;
        if (rec->m_missilePathType < 0 || rec->m_missilePathType > 16) rec->m_missilePathType = 0;
        if (rec->m_missileDestinationAttachment < 0 || rec->m_missileDestinationAttachment > 128) rec->m_missileDestinationAttachment = 0;
        if (rec->m_missileAttachment < 0 || rec->m_missileAttachment > 128) rec->m_missileAttachment = 0;

        if (original && (rec->m_hasMissile != 0 || rec->m_channelKit != 0)) {
            rec->m_missileAttachment = original->m_missileAttachment;
            for (int i = 0; i < 3; ++i) rec->m_missileCastOffset[i] = original->m_missileCastOffset[i];
        }
        return true;
    }

    static SpellVisualRec* BuildSanitizedSpellVisual(const SpellVisualRec* src, const SpellVisualRec* original) {
        if (!src) return nullptr;

        uint32_t targetVid = src->m_ID;
        uint32_t originalVid = original ? original->m_ID : 0;
        
        // Key includes generation to ensure we pick up fresh settings/original-context changes
        // while keeping old pointers in g_sanitizedVisuals valid (eternal pointer stability).
        uint64_t key = (static_cast<uint64_t>(g_morphGeneration) << 48) | 
                       (static_cast<uint64_t>(originalVid) << 24) | 
                       (targetVid & 0xFFFFFF);

        // 1. Fast Path: Check Cache (Shared Lock)
        {
            SharedLock lock(&g_spellMorphLock);
            auto it = g_sanitizedVisuals.find(key);
            if (it != g_sanitizedVisuals.end()) {
                return it->second ? it->second.get() : nullptr;
            }
        }

        // 2. Slow Path: Work outside the lock to minimize contention
        auto sanitized = std::make_unique<SpellVisualRec>(*src);
        bool valid = SanitizeSpellVisualRec(sanitized.get(), original);

        // 3. Write Path: Store in Cache (Exclusive Lock)
        {
            ExclusiveLock lock(&g_spellMorphLock);
            // Double check in case another thread already did the work
            auto it = g_sanitizedVisuals.find(key);
            if (it != g_sanitizedVisuals.end()) {
                return it->second ? it->second.get() : nullptr;
            }

            if (!valid) {
                g_sanitizedVisuals[key] = nullptr; // Cache the failure to prevent re-sanitizing
                return nullptr;
            }

            SpellVisualRec* finalPtr = sanitized.get();
            g_sanitizedVisuals[key] = std::move(sanitized);
            return finalPtr;
        }
    }

    static SpellVisualRec* GetSpellVisualRecById(uint32_t visualId) {
        return const_cast<SpellVisualRec*>(GetSafeSpellVisualRec(visualId));
    }

    static uint32_t ResolveTargetVisualId_NoLock(uint32_t targetSpellId) {
        if (targetSpellId == 0) return 0;

        // Use preloaded map for stability
        auto it = g_spellIdToVisualIdMap.find(targetSpellId);
        if (it != g_spellIdToVisualIdMap.end()) {
            uint32_t v0 = it->second.first;
            uint32_t v1 = it->second.second;
            if (v0 > 0 && v0 < 100000) return v0;
            if (v1 > 0 && v1 < 100000) return v1;
        }

        auto cacheIt = g_spellToVisualCache.find(targetSpellId);
        if (cacheIt != g_spellToVisualCache.end()) {
            return cacheIt->second;
        }

        return 0; // No override found
    }

    static uint32_t ResolveTargetVisualId(uint32_t targetSpellId) {
        AcquireSRWLockShared(&g_spellMorphLock);
        uint32_t v = ResolveTargetVisualId_NoLock(targetSpellId);
        ReleaseSRWLockShared(&g_spellMorphLock);
        return v;
    }

    static uint32_t SelectCompatibleTargetVisualId_NoLock(uint32_t sourceSpellId, uint32_t sourceVisualId, uint32_t targetSpellId) {
        if (targetSpellId == 0) return 0;

        auto targetIt = g_spellIdToVisualIdMap.find(targetSpellId);
        if (targetIt == g_spellIdToVisualIdMap.end()) {
            return ResolveTargetVisualId_NoLock(targetSpellId);
        }

        uint32_t targetV0 = targetIt->second.first;
        uint32_t targetV1 = targetIt->second.second;

        // If source visual corresponds to slot 0/1, mirror that slot first.
        auto sourceIt = g_spellIdToVisualIdMap.find(sourceSpellId);
        if (sourceIt != g_spellIdToVisualIdMap.end() && sourceVisualId > 0) {
            uint32_t sourceV0 = sourceIt->second.first;
            uint32_t sourceV1 = sourceIt->second.second;
            if (sourceVisualId == sourceV0 && targetV0 > 0) return targetV0;
            if (sourceVisualId == sourceV1 && targetV1 > 0) return targetV1;
        }

        const SpellVisualRec* srcRec = (sourceVisualId > 0) ? GetSpellVisualRecById(sourceVisualId) : nullptr;
        auto Score = [&](uint32_t candidateVisualId) -> int {
            if (candidateVisualId == 0) return -100000;

            int score = 0;
            const SpellVisualRec* dstRec = GetSpellVisualRecById(candidateVisualId);
            if (!dstRec) return -10;

            if (!srcRec) return 1; // Any valid target visual is better than none when source profile is unknown.

            if ((srcRec->m_hasMissile != 0) == (dstRec->m_hasMissile != 0)) score += 8;
            if ((srcRec->m_channelKit > 0) == (dstRec->m_channelKit > 0)) score += 3;
            if ((srcRec->m_stateKit > 0) == (dstRec->m_stateKit > 0)) score += 2;
            if ((srcRec->m_stateDoneKit > 0) == (dstRec->m_stateDoneKit > 0)) score += 2;
            if ((srcRec->m_impactKit > 0) == (dstRec->m_impactKit > 0)) score += 3;
            if ((srcRec->m_persistentAreaKit > 0) == (dstRec->m_persistentAreaKit > 0)) score += 2;

            if (srcRec->m_hasMissile != 0 && dstRec->m_hasMissile != 0) {
                if (srcRec->m_missilePathType == dstRec->m_missilePathType) score += 4;
                if (srcRec->m_missileFollowGroundFlags == dstRec->m_missileFollowGroundFlags) score += 2;
                if ((srcRec->m_missileMotion > 0) == (dstRec->m_missileMotion > 0)) score += 2;
            }

            return score;
        };

        int s0 = Score(targetV0);
        int s1 = Score(targetV1);

        if (s1 > s0 && targetV1 > 0) return targetV1;
        if (targetV0 > 0) return targetV0;
        if (targetV1 > 0) return targetV1;
        return 0;
    }

    static void AddSourceVisualOverrides_NoLock(uint32_t sourceSpellId, uint32_t targetSpellId) {
        bool added = false;

        // Try disk-preloaded source spell visuals first.
        auto it = g_spellIdToVisualIdMap.find(sourceSpellId);
        if (it != g_spellIdToVisualIdMap.end()) {
            uint32_t sourceVisual0 = it->second.first;
            uint32_t sourceVisual1 = it->second.second;

            if (sourceVisual0 > 0) {
                uint32_t tv = SelectCompatibleTargetVisualId_NoLock(sourceSpellId, sourceVisual0, targetSpellId);
                if (tv > 0) {
                    g_visualOverrides[sourceVisual0] = tv;
                    added = true;
                }
            }
            if (sourceVisual1 > 0) {
                uint32_t tv = SelectCompatibleTargetVisualId_NoLock(sourceSpellId, sourceVisual1, targetSpellId);
                if (tv > 0) {
                    g_visualOverrides[sourceVisual1] = tv;
                    added = true;
                }
            }
        }

        if (!added) {
            SpellRec* sourceRec = GetSpellRecById(sourceSpellId);
            if (sourceRec) {
                uint32_t sourceVisual0 = static_cast<uint32_t>(sourceRec->m_spellVisualID[0]);
                uint32_t sourceVisual1 = static_cast<uint32_t>(sourceRec->m_spellVisualID[1]);

                if (sourceVisual0 > 0) {
                    uint32_t tv = SelectCompatibleTargetVisualId_NoLock(sourceSpellId, sourceVisual0, targetSpellId);
                    if (tv > 0) {
                        g_visualOverrides[sourceVisual0] = tv;
                        added = true;
                    }
                }
                if (sourceVisual1 > 0) {
                    uint32_t tv = SelectCompatibleTargetVisualId_NoLock(sourceSpellId, sourceVisual1, targetSpellId);
                    if (tv > 0) {
                        g_visualOverrides[sourceVisual1] = tv;
                        added = true;
                    }
                }
            }
        }

        // Last resort: if sourceSpellId itself is a visual row id (non-standard use), map it.
        if (!added && GetSpellVisualRecById(sourceSpellId)) {
            uint32_t tv = SelectCompatibleTargetVisualId_NoLock(sourceSpellId, sourceSpellId, targetSpellId);
            if (tv > 0) g_visualOverrides[sourceSpellId] = tv;
        }
    }

    static void RebuildVisualOverrides_NoLock() {
        g_visualOverrides.clear();
        for (auto it = g_spellMorphs.begin(); it != g_spellMorphs.end(); ++it) {
            uint32_t sourceSpellId = it->first;
            uint32_t targetSpellId = it->second;
            uint32_t targetVisualId = ResolveTargetVisualId_NoLock(targetSpellId);
            if (targetVisualId == 0) continue;
            AddSourceVisualOverrides_NoLock(sourceSpellId, targetSpellId);
        }
    }

    static bool IsValidReadPtr(uintptr_t ptr) {
        __try {
            volatile uintptr_t val = *reinterpret_cast<uintptr_t*>(ptr);
            return val != 0;
        }
        __except (EXCEPTION_EXECUTE_HANDLER) {
            return false;
        }
    }

    // Removed ScanForSpellDB as it was causing crashes by finding wrong DBs in text section.
    // We now use hardcoded addresses ADDR_SPELL_DB and ADDR_SPELL_VISUAL_DB which are 
    // verified for 3.3.5a 12340.

    static const uint32_t SPELL_VISUAL_OFFSET = 131 * 4;

    static uint32_t ResolveVisualIdFromSpellRec(SpellRec* rec) {
        if (!rec) return 0;
        
        // Try preloaded map first
        uint32_t spellId = *reinterpret_cast<uint32_t*>(rec);
        auto it = g_spellIdToVisualIdMap.find(spellId);
        if (it != g_spellIdToVisualIdMap.end()) {
            if (it->second.first > 0) return it->second.first;
            if (it->second.second > 0) return it->second.second;
        }

        // Fallback to memory reading
        uintptr_t base = reinterpret_cast<uintptr_t>(rec);
        uint32_t v0 = *reinterpret_cast<uint32_t*>(base + SPELL_VISUAL_OFFSET);
        uint32_t v1 = *reinterpret_cast<uint32_t*>(base + SPELL_VISUAL_OFFSET + 4);
        
        if (v0 > 0 && v0 < 100000) return v0;
        if (v1 > 0 && v1 < 100000) return v1;
        return 0;
    }

    static uint32_t ResolveMissileIdFromSpellRec(SpellRec* rec) {
        if (!rec) return 0;
        uintptr_t base = reinterpret_cast<uintptr_t>(rec);
        // Field 227 (SpellMissileID) is at index 227 in 3.3.5a 12340
        return *reinterpret_cast<uint32_t*>(base + 227 * 4);
    }

    static SpellVisualRec* __cdecl Hooked_GetSpellVisualRow(SpellRec* pSpellRec) {
        if (!pSpellRec || !g_originalGetSpellVisualRow) {
            return &g_nullVisualRec;
        }

        __try {
            SpellVisualRec* original = nullptr;
            __try {
                original = g_originalGetSpellVisualRow(pSpellRec);
            } __except (EXCEPTION_EXECUTE_HANDLER) {
                return &g_nullVisualRec;
            }

            // Preserve native client behavior for non-morphed flow.
            // Do NOT sanitize/copy native rows globally, to avoid visual regressions.
            if (!pSpellRec) {
                return original ? original : &g_nullVisualRec;
            }

            // HIDE ALL OTHER SPELLS LOGIC
            if (g_hideAllOtherSpells) {
                // Try to get the caster GUID from the spell record if possible (pseudo, as actual field may differ)
                // For most client-side hooks, we can't get the caster directly, so we hide ALL except self-cast
                // If you have a way to get the caster, use it here. Otherwise, this will hide all spell visuals except for the local player.
                // For now, we assume all non-self spells are hidden.
                // TODO: If you can get the caster GUID, compare to GetLocalPlayerGuid().
                // If not, this will hide all spell visuals except for self-cast (which is safest for now).
                return &g_nullVisualRec;
            }
            uint32_t sourceSpellId = static_cast<uint32_t>(pSpellRec->m_ID);
            uint32_t sourceVisualId = ResolveVisualIdFromSpellRec(pSpellRec);

            uint32_t targetVisualId = 0;
            bool hasSpellMorph = false;
            AcquireSRWLockShared(&g_spellMorphLock);

            // Compatibility map: source visual -> best matching target visual.
            if (sourceVisualId > 0) {
                auto ovIt = g_visualOverrides.find(sourceVisualId);
                if (ovIt != g_visualOverrides.end()) {
                    targetVisualId = ovIt->second;
                }
            }

            auto spellIt = g_spellMorphs.find(sourceSpellId);
            if (spellIt != g_spellMorphs.end()) {
                hasSpellMorph = true;
                uint32_t mappedTargetSpellId = spellIt->second;
                if (targetVisualId == 0) {
                    targetVisualId = SelectCompatibleTargetVisualId_NoLock(sourceSpellId, sourceVisualId, mappedTargetSpellId);
                }
            }

            ReleaseSRWLockShared(&g_spellMorphLock);

            if (!hasSpellMorph) {
                return original ? original : &g_nullVisualRec;
            }

            // Morph path only: return sanitized override if available.
            if (targetVisualId > 0 && targetVisualId != sourceVisualId) {
                SpellVisualRec* overrideRec = GetSpellVisualRecById(targetVisualId);
                SpellVisualRec* safeOverride = BuildSanitizedSpellVisual(overrideRec, original);
                if (safeOverride) {
                    return safeOverride;
                }
            }

            // Fallback to native visual when morph target is invalid/unavailable.
            return original ? original : &g_nullVisualRec;
        }
        __except (EXCEPTION_EXECUTE_HANDLER) {
            return &g_nullVisualRec;
        }
    }
}

// Command handler for Lua bridge
extern "C" __declspec(dllexport) void SpellMorph_SetHideAllOtherSpells(int hide) {
    SetHideAllOtherSpells(hide != 0);
    Log("[SpellMorph] HideAllOtherSpells set to %d", hide != 0);
}

bool InstallSpellVisualHook() {
    if (g_hookInstalled) return true;

    BYTE* target = reinterpret_cast<BYTE*>(ADDR_GET_SPELL_VISUAL_ROW);
    __try {
        if (target[0] != 0x55 || target[1] != 0x8B || target[2] != 0xEC) {
            Log("Spell hook prologue mismatch at 0x%08X (%02X %02X %02X)",
                (unsigned)ADDR_GET_SPELL_VISUAL_ROW, target[0], target[1], target[2]);
            return false;
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        Log("Spell hook verification exception at 0x%08X", (unsigned)ADDR_GET_SPELL_VISUAL_ROW);
        return false;
    }

    std::memcpy(g_originalBytes, target, 5);

    g_trampoline = VirtualAlloc(nullptr, 16, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if (!g_trampoline) {
        Log("Spell hook trampoline allocation failed");
        return false;
    }

    BYTE* tramp = reinterpret_cast<BYTE*>(g_trampoline);
    std::memcpy(tramp, g_originalBytes, 5);
    tramp[5] = 0xE9;
    *reinterpret_cast<DWORD*>(tramp + 6) =
        (DWORD)((reinterpret_cast<uintptr_t>(target) + 5) - (reinterpret_cast<uintptr_t>(tramp) + 10));

    g_originalGetSpellVisualRow = reinterpret_cast<GetSpellVisualRowFn>(g_trampoline);

    DWORD oldProt = 0;
    if (!VirtualProtect(target, 5, PAGE_EXECUTE_READWRITE, &oldProt)) {
        Log("Spell hook VirtualProtect failed");
        VirtualFree(g_trampoline, 0, MEM_RELEASE);
        g_trampoline = nullptr;
        g_originalGetSpellVisualRow = nullptr;
        return false;
    }

    target[0] = 0xE9;
    *reinterpret_cast<DWORD*>(target + 1) =
        (DWORD)(reinterpret_cast<uintptr_t>(&Hooked_GetSpellVisualRow) - reinterpret_cast<uintptr_t>(target) - 5);

    DWORD dummy = 0;
    VirtualProtect(target, 5, oldProt, &dummy);
    FlushInstructionCache(GetCurrentProcess(), target, 5);

    g_hookInstalled = true;

    PreloadSpellDBC();

    Log("Spell visual hook installed at 0x%08X", (unsigned)ADDR_GET_SPELL_VISUAL_ROW);
    return true;
}

void UninstallSpellVisualHook() {
    if (!g_hookInstalled) return;

    BYTE* target = reinterpret_cast<BYTE*>(ADDR_GET_SPELL_VISUAL_ROW);
    DWORD oldProt = 0;
    if (VirtualProtect(target, 5, PAGE_EXECUTE_READWRITE, &oldProt)) {
        std::memcpy(target, g_originalBytes, 5);
        DWORD dummy = 0;
        VirtualProtect(target, 5, oldProt, &dummy);
        FlushInstructionCache(GetCurrentProcess(), target, 5);
    }

    if (g_trampoline) {
        VirtualFree(g_trampoline, 0, MEM_RELEASE);
        g_trampoline = nullptr;
    }

    g_originalGetSpellVisualRow = nullptr;
    g_hookInstalled = false;
    Log("Spell visual hook uninstalled");
}

    static void PatchSpellRecordMissile(uint32_t spellId, uint32_t targetMissileId) {
        auto it = g_spellRowPointers.find(spellId);
        if (it == g_spellRowPointers.end() || !it->second) return;

        uintptr_t rowAddr = (uintptr_t)it->second;
        DWORD oldProt;
        if (VirtualProtect((void*)(rowAddr + 227 * 4), 4, PAGE_EXECUTE_READWRITE, &oldProt)) {
            *reinterpret_cast<uint32_t*>(rowAddr + 227 * 4) = targetMissileId;
            DWORD dummy;
            VirtualProtect((void*)(rowAddr + 227 * 4), 4, oldProt, &dummy);
        }
    }

bool SetSpellMorph(uint32_t sourceSpellId, uint32_t targetSpellId) {
    if (sourceSpellId == 0 || targetSpellId == 0) return false;
    if (sourceSpellId == targetSpellId) return false;

    AcquireSRWLockExclusive(&g_spellMorphLock);
    if (g_spellMorphs.find(sourceSpellId) == g_spellMorphs.end() && g_spellMorphs.size() >= MAX_SPELL_MORPHS) {
        ReleaseSRWLockExclusive(&g_spellMorphLock);
        return false;
    }
    g_spellMorphs[sourceSpellId] = targetSpellId;
    
    // Patch Missile ID (Field 227) in the original Spell record to match target spell's behavior.
    uint32_t targetMissileId = 0;
    {
        auto ptrIt = g_spellRowPointers.find(targetSpellId);
        if (ptrIt != g_spellRowPointers.end() && ptrIt->second) {
            targetMissileId = *reinterpret_cast<uint32_t*>((uintptr_t)ptrIt->second + 227 * 4);
        }
    }
    /*
    if (targetMissileId > 0) {
        PatchSpellRecordMissile(sourceSpellId, targetMissileId);
    }
    */

    RebuildVisualOverrides_NoLock();
    g_morphGeneration++; // Safe Hard Reset (Gen bump)

    // Finalize without calling client GetRow (too slow for UI thread)
    ReleaseSRWLockExclusive(&g_spellMorphLock);
    return true;
}

void RemoveSpellMorph(uint32_t sourceSpellId) {
    if (sourceSpellId == 0) return;
    AcquireSRWLockExclusive(&g_spellMorphLock);
    
    // Restore original Missile ID
    /*
    auto itOrig = g_originalMissileIds.find(sourceSpellId);
    if (itOrig != g_originalMissileIds.end()) {
        PatchSpellRecordMissile(sourceSpellId, itOrig->second);
    }
    */

    g_spellMorphs.erase(sourceSpellId);
    RebuildVisualOverrides_NoLock();
    g_morphGeneration++;
    ReleaseSRWLockExclusive(&g_spellMorphLock);
}

void ClearSpellMorphs() {
    AcquireSRWLockExclusive(&g_spellMorphLock);
    g_spellMorphs.clear();
    g_visualOverrides.clear();
    g_spellToVisualCache.clear();
    g_morphGeneration++;
    ReleaseSRWLockExclusive(&g_spellMorphLock);
}

bool HasSpellMorphs() {
    bool hasAny = false;
    AcquireSRWLockShared(&g_spellMorphLock);
    hasAny = !g_spellMorphs.empty();
    ReleaseSRWLockShared(&g_spellMorphLock);
    return hasAny;
}

size_t ExportSpellMorphPairs(SpellMorphPair* outPairs, size_t maxPairs) {
    if (!outPairs || maxPairs == 0) return 0;
    size_t written = 0;
    AcquireSRWLockShared(&g_spellMorphLock);
    for (auto it = g_spellMorphs.begin(); it != g_spellMorphs.end() && written < maxPairs; ++it) {
        outPairs[written].sourceSpellId = it->first;
        outPairs[written].targetSpellId = it->second;
        ++written;
    }
    ReleaseSRWLockShared(&g_spellMorphLock);
    return written;
}

void ImportSpellMorphPairs(const SpellMorphPair* pairs, size_t count) {
    AcquireSRWLockExclusive(&g_spellMorphLock);
    g_spellMorphs.clear();
    if (pairs && count > 0) {
        size_t safeCount = (count < MAX_SPELL_MORPHS) ? count : MAX_SPELL_MORPHS;
        for (size_t i = 0; i < safeCount; ++i) {
            uint32_t sourceSpellId = pairs[i].sourceSpellId;
            uint32_t targetSpellId = pairs[i].targetSpellId;
            if (sourceSpellId == 0 || targetSpellId == 0 || sourceSpellId == targetSpellId) continue;
            g_spellMorphs[sourceSpellId] = targetSpellId;
        }
    }
    RebuildVisualOverrides_NoLock();
    ReleaseSRWLockExclusive(&g_spellMorphLock);
}

namespace {
    std::string SearchSpellsInternal(const std::string& query) {
        std::string result;
        int count = 0;
        const int LIMIT = 200;
        const int SCAN_LIMIT = 1000; // Scan more to find enough valid client-side spells

        if (query.empty()) {
            // Return first 1000 spells with names as default (Lua will filter to ~200)
            for (auto it = g_spellNames.begin(); it != g_spellNames.end(); ++it) {
                if (count >= SCAN_LIMIT) break;
                result += std::to_string((unsigned int)it->first) + "|";
                count++;
            }
            return result;
        }

        std::string q = query;
        for (size_t i = 0; i < q.length(); ++i) q[i] = (char)tolower(q[i]);

        uint32_t qId = 0;
        try { qId = (uint32_t)std::stoul(q); } catch (...) {}

        // 1. Search by ID
        if (qId > 0 && g_spellIdToVisualIdMap.count(qId)) {
            result += std::to_string((unsigned int)qId) + "|";
            count++;
        }

        // 2. Search by Name (Substring)
        for (auto it = g_spellNames.begin(); it != g_spellNames.end(); ++it) {
            if (count >= LIMIT) break;
            if (it->first == qId) continue;

            std::string n = it->second;
            for (size_t i = 0; i < n.length(); ++i) n[i] = (char)tolower(n[i]);

            if (n.find(q) != std::string::npos) {
                result += std::to_string((unsigned int)it->first) + "|";
                count++;
            }
        }

        // 3. Fallback: Search by numeric ID partial match
        if (count < 20) {
            for (auto it = g_spellIdToVisualIdMap.begin(); it != g_spellIdToVisualIdMap.end(); ++it) {
                if (count >= LIMIT) break;
                uint32_t sid = it->first;
                if (sid == qId || g_spellNames.count(sid)) continue;
                
                std::string sidStr = std::to_string((unsigned int)sid);
                if (sidStr.find(q) != std::string::npos) {
                    result += sidStr + "|";
                    count++;
                }
            }
        }
        return result;
    }
}

std::string SearchSpells(const std::string& query) {
    return SearchSpellsInternal(query);
}

size_t GetSpellDBCRecordCount() {
    return g_spellIdToVisualIdMap.size();
}
