#include "SpellMorph.h"
#include "Logger.h"
#include "Utils.h"
#include <windows.h>
#include <psapi.h>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#include <cstring>
#include <string>
#include <cmath>
#include <algorithm>

    static bool g_hideAllSpells = false;
    static bool g_showOwnSpells = false;
    static bool g_hidePrecast = false;
    static bool g_hideCast = false;
    static bool g_hideChannel = false;
    static bool g_hideAuraStart = false;
    static bool g_hideAuraEnd = false;
    static bool g_hideImpact = false;
    static bool g_hideImpactCaster = false;
    static bool g_hideTargetImpact = false;
    static bool g_hideAreaInstant = false;
    static bool g_hideAreaImpact = false;
    static bool g_hideAreaPersistent = false;
    static bool g_hideMissile = false;
    static bool g_hideMissileMarker = false;
    static bool g_hideSoundMissile = false;
    static bool g_hideSoundEvent = false;

    static std::unordered_set<uint32_t> g_whiteCardSpells; // Custom Protection Whitelist
    static SRWLOCK g_whiteCardLock = SRWLOCK_INIT;
    static std::unordered_set<uint32_t> g_playerSpellbookSpells;
    static SRWLOCK g_playerSpellbookLock = SRWLOCK_INIT;

// Use thread_local to track which unit is currently requesting a visual
static thread_local uint64_t g_currentCasterGUID = 0;

namespace {
    struct SpellRec {
        int32_t m_ID;
        int32_t pad[130];
        int32_t m_spellVisualID[2];
        int32_t pad2[3];
        const char* m_name;
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
    typedef SpellVisualRec* (__thiscall* GetVisualRowByIdFn)(void*, uint32_t);

    static const uintptr_t ADDR_SPELL_VISUAL_DB = 0x00D94AF8;
    static const uintptr_t ADDR_SPELL_DB        = 0x00BA5238; // standard 3.3.5.12340
    static const uintptr_t ADDR_GET_VISUAL_ROW  = 0x00475E80;

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
    static std::unordered_map<uint32_t, uint32_t> g_spellToVisualCache;
    static SRWLOCK g_spellMorphLock = SRWLOCK_INIT;

    static bool g_hookInstalled = false;
    static BYTE g_originalBytes[5] = {0};
    static void* g_trampoline = nullptr;
    static GetSpellVisualRowFn g_originalGetSpellVisualRow = nullptr;
    static std::unordered_map<uint32_t, std::pair<uint32_t, uint32_t>> g_spellIdToVisualIdMap;
    static std::unordered_map<uint32_t, void*> g_spellRowPointers; // Memory addresses of Spell.dbc rows
    static std::unordered_map<uint32_t, SpellVisualRec*> g_visualIdToDbcPtrMap;
    static std::unordered_map<uint32_t, std::string> g_spellNames;
    static std::vector<uint8_t> g_spellStringTable;
    static bool g_dbcPreloaded = false;
    static std::unordered_map<uint32_t, bool> g_validVisualKits;
    static std::unordered_map<uint32_t, bool> g_validEffectNames;
    static std::unordered_map<uint32_t, bool> g_validSpellMissiles;
    static std::unordered_map<uint32_t, bool> g_validSpellMissileMotions;
    static std::unordered_map<uint32_t, std::vector<uint8_t>> g_spellVisualRecs; // Addon overrides backup
    static std::unordered_set<uint32_t> g_protectedVisualIds; // IDs that MUST NOT be modified
    static std::unordered_map<uint32_t, std::vector<uint8_t>> g_retailVisualRecs; // Snapshot of original memory
    static std::unordered_map<uint32_t, SpellVisualRec*> g_liveVisualRows; // Live client rows, including HD-only visuals
    static std::unordered_map<void*, bool> g_backupDataPtrMap; // For fast O(1) safety checks
    static std::unordered_map<uint32_t, std::vector<uint32_t>> g_spellIdToAllVisualIds;
    
    // In-Place Optimization Data
    static std::vector<uint8_t> g_spellVisualBackup; // Original raw data of SpellVisual.dbc
    static void* g_spellVisualBaseAddr = nullptr;
    static uint32_t g_spellVisualRecordCount = 0;
    static uint32_t g_spellVisualRecordSize = 0;


    static uint32_t g_morphGeneration = 0;
    static std::unordered_map<void*, uint32_t> g_sanitizedPtrGeneration; 
    static std::unordered_map<void*, bool> g_lastGranularState; 
    static SpellVisualRec g_nullVisualRec = {};

    static void SoftResetCache() {
        AcquireSRWLockExclusive(&g_spellMorphLock);
        g_morphGeneration++; // New lookups will use new keys, old pointers stay valid in the map
        
        // Clear ALL caches to force re-sync on next access
        // This ensures that when morphs change, we re-apply the correct visual data
        g_sanitizedPtrGeneration.clear();
        g_lastGranularState.clear();
        g_spellToVisualCache.clear();
        g_visualIdToDbcPtrMap.clear();
        g_liveVisualRows.clear();
        
        ReleaseSRWLockExclusive(&g_spellMorphLock);
    }

    static void AppendUniqueVisualId(std::vector<uint32_t>& visualIds, uint32_t visualId) {
        if (visualId == 0) return;
        for (size_t i = 0; i < visualIds.size(); ++i) {
            if (visualIds[i] == visualId) return;
        }
        visualIds.push_back(visualId);
    }

    static bool PreloadIdsFromDBC(const char* primary, const char* fallback1, const char* fallback2,
                                  std::unordered_map<uint32_t, bool>& outSet, const char* label) {
        FILE* f = nullptr;
        const char* path = primary;
        if (fopen_s(&f, path, "rb") != 0 || !f) {
            if (fallback1) {
                path = fallback1;
                if (fopen_s(&f, path, "rb") != 0 || !f) {
                    if (fallback2) {
                        path = fallback2;
                        fopen_s(&f, path, "rb");
                    }
                }
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
            nullptr, nullptr,
            g_validVisualKits,
            "SpellVisualKit");

        PreloadIdsFromDBC(
            "Interface\\AddOns\\Transmorpher\\DBC\\SpellVisualEffectName.dbc",
            nullptr, nullptr,
            g_validEffectNames,
            "SpellVisualEffectName");

        PreloadIdsFromDBC(
            "Interface\\AddOns\\Transmorpher\\DBC\\SpellMissile.dbc",
            nullptr, nullptr,
            g_validSpellMissiles,
            "SpellMissile");

        PreloadIdsFromDBC(
            "Interface\\AddOns\\Transmorpher\\DBC\\SpellMissileMotion.dbc",
            nullptr, nullptr,
            g_validSpellMissileMotions,
            "SpellMissileMotion");
    }

    static void PreloadSpellVisualDBC() {
        struct DBCHeader {
            uint32_t magic, numRecords, numFields, recordSize, stringTableSize;
        };

        // 1. Snapshot RETAIL Internal Data FIRST (Highest Priority)
        // Access the game's internal DBC store directly.
        // This captures the client's HD patches as the authoritative source.
        void* dbPtr = *reinterpret_cast<void**>(ADDR_SPELL_VISUAL_DB);
        if (dbPtr) {
            uint32_t* store = reinterpret_cast<uint32_t*>(dbPtr);
            uint32_t numRows = store[1];
            uint32_t recordSize = store[3];
            uint8_t* data = reinterpret_cast<uint8_t*>(store[4]);

            if (data && numRows > 0 && recordSize >= 128) {
                for (uint32_t i = 0; i < numRows; ++i) {
                    uint8_t* rec = data + (i * recordSize);
                    uint32_t vid = *reinterpret_cast<uint32_t*>(rec);
                    std::vector<uint8_t> buffer(128);
                    std::memcpy(buffer.data(), rec, 128);
                    g_retailVisualRecs[vid] = buffer;
                    g_liveVisualRows[vid] = reinterpret_cast<SpellVisualRec*>(rec);
                }
                Log("Snapshotted %zu RETAIL visuals from internal memory (HD patches preserved)", g_retailVisualRecs.size());
            }
        }

        // 2. Load Addon DBC as FALLBACK ONLY (Lower Priority)
        // Only use addon DBC for entries NOT already in retail or for filling gaps
        const char* path = "Interface\\AddOns\\Transmorpher\\DBC\\SpellVisual.dbc";
        Log("Preloading Addon DBC as fallback: %s", path);

        PreloadValidationDBCs(); // Load validation data first

        FILE* f = nullptr;
        if (fopen_s(&f, path, "rb") != 0 || !f) {
            Log("Addon SpellVisual.dbc not found. Using internal client data only.");
            return;
        }

        DBCHeader header;
        if (fread(&header, sizeof(header), 1, f) != 1 || header.magic != 0x43424457) {
            fclose(f); 
            Log("Invalid Addon SpellVisual.dbc header.");
            return;
        }

        uint32_t addedCount = 0;
        uint32_t skippedCount = 0;
        std::vector<uint8_t> buffer(header.recordSize);
        for (uint32_t i = 0; i < header.numRecords; ++i) {
            if (fread(buffer.data(), header.recordSize, 1, f) != 1) break;
            uint32_t vid = *reinterpret_cast<uint32_t*>(buffer.data());
            
            // Only add to addon overrides if retail doesn't have this entry
            // This ensures client HD patches are NOT overridden
            if (g_retailVisualRecs.find(vid) == g_retailVisualRecs.end()) {
                g_spellVisualRecs[vid] = buffer;
                g_backupDataPtrMap[g_spellVisualRecs[vid].data()] = true;
                addedCount++;
            } else {
                skippedCount++;
            }
        }
        fclose(f);
        Log("Addon SpellVisual: Added %u fallback records, skipped %u (client HD data takes precedence)", 
            addedCount, skippedCount);
    }

    static void PreloadSpellDBC() {
        if (g_dbcPreloaded) return;
        g_dbcPreloaded = true;

        PreloadSpellVisualDBC();

        const char* path = "Interface\\AddOns\\Transmorpher\\DBC\\Spell.dbc";
        Log("Preloading Spell.dbc (Priority: %s)", path);

        FILE* f = nullptr;
        if (fopen_s(&f, path, "rb") != 0 || !f) {
            Log("WARNING: Addon overrides (Spell.dbc) not found.");
            return;
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
            std::vector<uint32_t>& allVisuals = g_spellIdToAllVisualIds[id];
            AppendUniqueVisualId(allVisuals, v0);
            AppendUniqueVisualId(allVisuals, v1);
            g_spellRowPointers[id] = (void*)rec;


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

        // GRANULAR FILTERING: Applies to all spells globally if enabled (v3.0 Ultra-Granular)
        // Animation Safety (v4.3): Only clear kits, PRESERVE flags and attachments
        // Clearing flags can break the client's internal animation state machine (e.g. Frostbolt queuing)
        if (g_hideAllSpells) {
            rec->m_precastKit = 0;
            rec->m_castKit = 0;
            rec->m_impactKit = 0;
            rec->m_stateKit = 0;
            rec->m_stateDoneKit = 0;
            rec->m_channelKit = 0;
            rec->m_hasMissile = 0; 
            rec->m_missileModel = 0;
            rec->m_missileSound = 0;
            rec->m_animEventSoundID = 0;
            rec->m_casterImpactKit = 0;
            rec->m_targetImpactKit = 0;
            rec->m_missileTargetingKit = 0;
            rec->m_instantAreaKit = 0;
            rec->m_impactAreaKit = 0;
            rec->m_persistentAreaKit = 0;
        }

        if (g_hidePrecast) rec->m_precastKit = 0;
        if (g_hideCast)    rec->m_castKit = 0;
        if (g_hideChannel) rec->m_channelKit = 0;
        if (g_hideAuraStart) rec->m_stateKit = 0;
        if (g_hideAuraEnd)   rec->m_stateDoneKit = 0;

        if (g_hideImpact)       rec->m_impactKit = 0;
        if (g_hideImpactCaster)  rec->m_casterImpactKit = 0;
        if (g_hideTargetImpact)  rec->m_targetImpactKit = 0;

        if (g_hideAreaInstant)   rec->m_instantAreaKit = 0;
        if (g_hideAreaImpact)    rec->m_impactAreaKit = 0;
        if (g_hideAreaPersistent) rec->m_persistentAreaKit = 0;

        if (g_hideMissile) {
            rec->m_hasMissile = 0;
            rec->m_missileModel = 0;
        }
        if (g_hideMissileMarker) rec->m_missileTargetingKit = 0;

        if (g_hideSoundMissile) rec->m_missileSound = 0;
        if (g_hideSoundEvent)   rec->m_animEventSoundID = 0;

        return true;
    }




    static SpellVisualRec* GetLiveVisualRow(uint32_t visualId) {
        if (visualId == 0) return nullptr;
        void* db = *reinterpret_cast<void**>(ADDR_SPELL_VISUAL_DB);
        if (!db) return nullptr;
        GetVisualRowByIdFn fn = reinterpret_cast<GetVisualRowByIdFn>(ADDR_GET_VISUAL_ROW);
        return fn(db, visualId);
    }

    static SpellVisualRec* GetDbcVisualRow(uint32_t visualId) {
        if (visualId == 0) return nullptr;

        // 1. Check if we already mapped this visual to a DBC pointer
        {
            SharedLock lock(&g_spellMorphLock);
            auto it = g_visualIdToDbcPtrMap.find(visualId);
            if (it != g_visualIdToDbcPtrMap.end()) {
                // Validate cached pointer is still in valid range
                if (it->second && reinterpret_cast<uintptr_t>(it->second) > 0x10000) {
                    return it->second;
                }
            }
        }

        // 2. Use snapshotted LIVE client row from internal memory first.
        // Some HD-only visuals are not returned by the normal row lookup, but they still
        // exist in the loaded client table and must be patched in-place for optimization.
        {
            SharedLock lock(&g_spellMorphLock);
            auto liveIt = g_liveVisualRows.find(visualId);
            if (liveIt != g_liveVisualRows.end()) {
                SpellVisualRec* liveRow = liveIt->second;
                if (liveRow && reinterpret_cast<uintptr_t>(liveRow) > 0x10000) {
                    g_visualIdToDbcPtrMap[visualId] = liveRow;
                    return liveRow;
                }
            }
        }

        // 3. Use direct DBC lookup from LIVE client memory (Highest Priority fallback)
        // This ensures we get the HD patch version
        SpellVisualRec* pLiveRow = GetLiveVisualRow(visualId);
        if (pLiveRow && reinterpret_cast<uintptr_t>(pLiveRow) > 0x10000) {
            ExclusiveLock lock(&g_spellMorphLock);
            g_visualIdToDbcPtrMap[visualId] = pLiveRow;
            g_liveVisualRows[visualId] = pLiveRow;
            return pLiveRow;
        }

        // 4. Fallback to retail snapshot (captured at startup)
        auto itRetail = g_retailVisualRecs.find(visualId);
        if (itRetail != g_retailVisualRecs.end() && itRetail->second.size() >= sizeof(SpellVisualRec)) {
            return const_cast<SpellVisualRec*>(reinterpret_cast<const SpellVisualRec*>(itRetail->second.data()));
        }

        // 5. Last resort: Use addon DBC ONLY if client has no data (Safety)
        return const_cast<SpellVisualRec*>(GetSafeSpellVisualRec(visualId));
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

    static void RebuildVisualOverrides_NoLock() {
        // No longer needed - we use g_spellMorphs directly with spell IDs
        // This function is kept for API compatibility but does nothing
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

    static void CollectSpellVisualIds(uint32_t spellId, SpellRec* pSpellRec, std::vector<uint32_t>& outVisualIds) {
        auto mapIt = g_spellIdToAllVisualIds.find(spellId);
        if (mapIt != g_spellIdToAllVisualIds.end()) {
            for (size_t i = 0; i < mapIt->second.size(); ++i) {
                AppendUniqueVisualId(outVisualIds, mapIt->second[i]);
            }
        }

        auto pairIt = g_spellIdToVisualIdMap.find(spellId);
        if (pairIt != g_spellIdToVisualIdMap.end()) {
            AppendUniqueVisualId(outVisualIds, pairIt->second.first);
            AppendUniqueVisualId(outVisualIds, pairIt->second.second);
        }

        if (pSpellRec) {
            AppendUniqueVisualId(outVisualIds, static_cast<uint32_t>(pSpellRec->m_spellVisualID[0]));
            AppendUniqueVisualId(outVisualIds, static_cast<uint32_t>(pSpellRec->m_spellVisualID[1]));
            AppendUniqueVisualId(outVisualIds, ResolveVisualIdFromSpellRec(pSpellRec));
        }
    }

    static uint32_t ResolveMissileIdFromSpellRec(SpellRec* rec) {
        if (!rec) return 0;
        uintptr_t base = reinterpret_cast<uintptr_t>(rec);
        // Field 227 (SpellMissileID) is at index 227 in 3.3.5a 12340
        return *reinterpret_cast<uint32_t*>(base + 227 * 4);
    }

    static bool IsWhiteCardSpell(uint32_t spellId) {
        SharedLock lock(&g_whiteCardLock);
        if (g_whiteCardSpells.count(spellId)) return true;
        return false;
    }

    static bool IsPlayerSpellbookSpell(uint32_t spellId) {
        if (spellId == 0) return false;
        SharedLock lock(&g_playerSpellbookLock);
        return g_playerSpellbookSpells.count(spellId) != 0;
    }

    static std::unordered_set<uint32_t> g_protectedIds;

    static const char* GetProtectedSpellsPath() {
        return "Interface\\AddOns\\Transmorpher\\protected_spells.txt";
    }

    static void RebuildProtectedVisualIds_NoLock() {
        g_protectedVisualIds.clear();
        uint32_t count = 0;
        for (uint32_t spellId : g_protectedIds) {
            auto it = g_spellIdToVisualIdMap.find(spellId);
            if (it != g_spellIdToVisualIdMap.end()) {
                if (it->second.first > 0 && g_protectedVisualIds.insert(it->second.first).second) {
                    count++;
                }
                if (it->second.second > 0 && g_protectedVisualIds.insert(it->second.second).second) {
                    count++;
                }
            } else {
                void* db = *reinterpret_cast<void**>(ADDR_SPELL_DB);
                if (db) {
                    void* pSpellRec = GetRow(db, spellId);
                    if (pSpellRec) {
                        uint32_t visual0 = *reinterpret_cast<uint32_t*>(reinterpret_cast<uint8_t*>(pSpellRec) + 131 * 4);
                        uint32_t visual1 = *reinterpret_cast<uint32_t*>(reinterpret_cast<uint8_t*>(pSpellRec) + 132 * 4);
                        if (visual0 > 0 && g_protectedVisualIds.insert(visual0).second) {
                            count++;
                        }
                        if (visual1 > 0 && g_protectedVisualIds.insert(visual1).second) {
                            count++;
                        }
                    }
                }
            }

            auto allIt = g_spellIdToAllVisualIds.find(spellId);
            if (allIt != g_spellIdToAllVisualIds.end()) {
                for (size_t i = 0; i < allIt->second.size(); ++i) {
                    if (g_protectedVisualIds.insert(allIt->second[i]).second) {
                        count++;
                    }
                }
            }
        }
        Log("Identified %u visual IDs for protection whitelist", count);
    }

    static void LoadProtectedSpells() {
        const char* path = GetProtectedSpellsPath();
        FILE* f = nullptr;
        if (fopen_s(&f, path, "r") != 0 || !f) {
            Log("WARNING: protected_spells.txt not found at %s", path);
            return;
        }

        ExclusiveLock lock(&g_spellMorphLock);
        g_protectedIds.clear();
        g_protectedVisualIds.clear();
        
        char line[64];
        uint32_t count = 0;
        while (fgets(line, sizeof(line), f)) {
            uint32_t id = static_cast<uint32_t>(std::atoi(line));
            if (id > 0) {
                g_protectedIds.insert(id);
                count++;
            }
        }
        fclose(f);
        Log("Loaded %u protected spell IDs from database", count);
    }

    static void IdentifyProtectedVisualIds() {
        ExclusiveLock lock(&g_spellMorphLock);
        RebuildProtectedVisualIds_NoLock();
    }

    static bool IsCriticalVisual(uint32_t spellId, uint32_t visualId) {
        // Protection now depends only on protected_spells.txt-resolved spell/visual IDs.
        if (g_protectedIds.count(spellId) || g_protectedIds.count(visualId)) return true;

        return false;
    }

    static bool RestoreSpellVisualRow(SpellVisualRec* row) {
        if (!row || row == &g_nullVisualRec) return false;
        if (g_backupDataPtrMap.count(row)) return false;

        const uint32_t visualId = static_cast<uint32_t>(row->m_ID);
        auto it = g_retailVisualRecs.find(visualId);
        if (it == g_retailVisualRecs.end() || it->second.size() < 128) {
            return false;
        }

        DWORD oldProt;
        if (!VirtualProtect(row, 128, PAGE_READWRITE, &oldProt)) {
            return false;
        }

        std::memcpy(row, it->second.data(), 128);

        DWORD dummy;
        VirtualProtect(row, 128, oldProt, &dummy);

        g_sanitizedPtrGeneration.erase(row);
        g_lastGranularState.erase(row);
        return true;
    }

    static bool ShouldProtectVisualRow(uint32_t spellId, uint32_t visualId, SpellVisualRec* row) {
        (void)row;
        if (g_showOwnSpells && IsPlayerSpellbookSpell(spellId)) return true;
        if (IsCriticalVisual(spellId, visualId)) return true;
        if (g_protectedVisualIds.count(visualId)) return true;
        return false;
    }



    static void SynchronizeSpellVisualRow(SpellVisualRec* finalRow, bool granular, bool isProtected) {
        if (!finalRow || finalRow == &g_nullVisualRec) return;

        ExclusiveLock lock(&g_spellMorphLock); 
        
        // Skip for backup data (addon DBC)
        if (g_backupDataPtrMap.count(finalRow)) {
            return;
        }

        if (!granular || isProtected) {
            RestoreSpellVisualRow(finalRow);
            return;
        }

        DWORD oldProt;
        if (VirtualProtect(finalRow, 128, PAGE_READWRITE, &oldProt)) {
            // ALWAYS sanitize (hide) when granular is enabled
            // This is the optimization that hides spell visuals
            SanitizeSpellVisualRec(finalRow, nullptr);

            DWORD dummy;
            VirtualProtect(finalRow, 128, oldProt, &dummy);
            g_sanitizedPtrGeneration[finalRow] = g_morphGeneration;
            g_lastGranularState[finalRow] = granular;
        }
    }

    static void SynchronizeSpellVisualId(uint32_t visualId, bool granular, bool isProtected) {
        if (visualId == 0) return;

        SpellVisualRec* liveRow = nullptr;
        {
            SharedLock lock(&g_spellMorphLock);
            auto it = g_liveVisualRows.find(visualId);
            if (it != g_liveVisualRows.end()) {
                liveRow = it->second;
            }
        }

        if (!liveRow || liveRow == &g_nullVisualRec || reinterpret_cast<uintptr_t>(liveRow) < 0x10000) {
            liveRow = GetLiveVisualRow(visualId);
            if (liveRow && liveRow != &g_nullVisualRec && reinterpret_cast<uintptr_t>(liveRow) > 0x10000) {
                ExclusiveLock lock(&g_spellMorphLock);
                g_liveVisualRows[visualId] = liveRow;
                g_visualIdToDbcPtrMap[visualId] = liveRow;
            }
        }

        SynchronizeSpellVisualRow(liveRow, granular, isProtected);
    }


    static SpellVisualRec* __cdecl Hooked_GetSpellVisualRow(SpellRec* pSpellRec) {
        if (!pSpellRec || !g_originalGetSpellVisualRow) {
            return &g_nullVisualRec;
        }

        if (reinterpret_cast<uintptr_t>(pSpellRec) < 0x10000) {
            return &g_nullVisualRec;
        }

        SpellVisualRec* original = g_originalGetSpellVisualRow(pSpellRec);
        if (!original || reinterpret_cast<uintptr_t>(original) < 0x10000) {
            return &g_nullVisualRec;
        }

        if (original == &g_nullVisualRec) {
            return original;
        }

        bool granular = (g_hideAllSpells || g_hidePrecast || g_hideCast || g_hideChannel ||
                        g_hideAuraStart || g_hideAuraEnd || g_hideImpact || g_hideImpactCaster ||
                        g_hideTargetImpact || g_hideAreaInstant || g_hideAreaImpact ||
                        g_hideAreaPersistent || g_hideMissile || g_hideMissileMarker ||
                        g_hideSoundMissile || g_hideSoundEvent);
        uint32_t sourceSpellId = static_cast<uint32_t>(pSpellRec->m_ID);
        uint32_t sourceVisualId = ResolveVisualIdFromSpellRec(pSpellRec);

        uint32_t targetVisualId = 0;
        bool isProtected = ShouldProtectVisualRow(sourceSpellId, sourceVisualId, original);

        if (!isProtected) {
            AcquireSRWLockShared(&g_spellMorphLock);
            auto spellIt = g_spellMorphs.find(sourceSpellId);
            if (spellIt != g_spellMorphs.end()) {
                targetVisualId = SelectCompatibleTargetVisualId_NoLock(sourceSpellId, sourceVisualId, spellIt->second);
            }
            ReleaseSRWLockShared(&g_spellMorphLock);
        }

        SpellVisualRec* finalRow = original;
        bool isManualMorph = false;
        if (targetVisualId > 0 && targetVisualId != sourceVisualId) {
            SpellVisualRec* overrideRec = GetDbcVisualRow(targetVisualId);
            if (overrideRec && overrideRec != &g_nullVisualRec) {
                finalRow = overrideRec;
                isManualMorph = true;
            }
        }

        if (!finalRow || reinterpret_cast<uintptr_t>(finalRow) < 0x10000 || finalRow == &g_nullVisualRec) {
            return &g_nullVisualRec;
        }

        std::vector<uint32_t> sourceVisualIds;
        CollectSpellVisualIds(sourceSpellId, pSpellRec, sourceVisualIds);
        AppendUniqueVisualId(sourceVisualIds, static_cast<uint32_t>(original->m_ID));

        if (!sourceVisualIds.empty()) {
            for (size_t i = 0; i < sourceVisualIds.size(); ++i) {
                uint32_t visualId = sourceVisualIds[i];
                SpellVisualRec* row = GetDbcVisualRow(visualId);
                bool protectVisual = ShouldProtectVisualRow(sourceSpellId, visualId, row);
                SynchronizeSpellVisualId(visualId, granular, protectVisual);
            }
        } else {
            SynchronizeSpellVisualId(sourceVisualId, granular, isProtected);
        }

        bool protectFinal = ShouldProtectVisualRow(sourceSpellId, static_cast<uint32_t>(finalRow->m_ID), finalRow);
        SynchronizeSpellVisualRow(finalRow, granular && !isManualMorph, protectFinal);

        if (granular && !isManualMorph && !protectFinal) {
            return &g_nullVisualRec;
        }

        if (!finalRow || reinterpret_cast<uintptr_t>(finalRow) < 0x10000) {
            return &g_nullVisualRec;
        }

        return finalRow;
    }
}

// Command handlers for Lua bridge
// Redundant exports removed from here, moving to the end of file for visibility of SoftResetCache

// ------------------------------------------------------------------
// Caster Context Tracking Hook
// ------------------------------------------------------------------
static const uintptr_t ADDR_GET_CAST_VISUAL = 0x0080B840;
typedef SpellVisualRec* (__thiscall* GetCastVisualFn)(void*, SpellRec*);
static GetCastVisualFn g_originalGetCastVisual = nullptr;
static BYTE g_castVisualOrigBytes[5] = {0};

static SpellVisualRec* __fastcall Hooked_GetCastVisual(void* pThis, void* edx, SpellRec* pSpellRec) {
    if (pThis) {
        // CSpell_C + 0x08 is the caster GUID in 3.3.5a 12340
        // Correcting to fastcall/edx dummy to match thiscall register (ECX)
        g_currentCasterGUID = *reinterpret_cast<uint64_t*>(reinterpret_cast<uintptr_t>(pThis) + 0x08);
    }
    
    SpellVisualRec* res = g_originalGetCastVisual(pThis, pSpellRec);

    if (pSpellRec && res && res != &g_nullVisualRec && reinterpret_cast<uintptr_t>(res) > 0x10000) {
        bool granular = (g_hideAllSpells || g_hidePrecast || g_hideCast || g_hideChannel ||
                        g_hideAuraStart || g_hideAuraEnd || g_hideImpact || g_hideImpactCaster ||
                        g_hideTargetImpact || g_hideAreaInstant || g_hideAreaImpact ||
                        g_hideAreaPersistent || g_hideMissile || g_hideMissileMarker ||
                        g_hideSoundMissile || g_hideSoundEvent);
        uint32_t sourceSpellId = static_cast<uint32_t>(pSpellRec->m_ID);
        uint32_t returnedVisualId = static_cast<uint32_t>(res->m_ID);
        uint32_t sourceVisualId = ResolveVisualIdFromSpellRec(pSpellRec);
        uint32_t targetVisualId = 0;

        AcquireSRWLockShared(&g_spellMorphLock);
        auto spellIt = g_spellMorphs.find(sourceSpellId);
        if (spellIt != g_spellMorphs.end()) {
            targetVisualId = SelectCompatibleTargetVisualId_NoLock(sourceSpellId, sourceVisualId, spellIt->second);
        }
        ReleaseSRWLockShared(&g_spellMorphLock);

        bool isManualMorph = (targetVisualId > 0 && targetVisualId != sourceVisualId && returnedVisualId == targetVisualId);

        std::vector<uint32_t> visualIds;
        CollectSpellVisualIds(sourceSpellId, pSpellRec, visualIds);
        AppendUniqueVisualId(visualIds, returnedVisualId);

        bool protectReturned = ShouldProtectVisualRow(sourceSpellId, returnedVisualId, res);

        if (!visualIds.empty()) {
            for (size_t i = 0; i < visualIds.size(); ++i) {
                uint32_t visualId = visualIds[i];
                SpellVisualRec* row = GetDbcVisualRow(visualId);
                bool protectVisual = ShouldProtectVisualRow(sourceSpellId, visualId, row);
                SynchronizeSpellVisualId(visualId, granular, protectVisual);
            }
        } else {
            SynchronizeSpellVisualRow(res, granular && !isManualMorph, protectReturned);
        }

        SynchronizeSpellVisualRow(res, granular && !isManualMorph, protectReturned);

        if (granular && !isManualMorph && !protectReturned) {
            g_currentCasterGUID = 0;
            return &g_nullVisualRec;
        }
    }
    
    g_currentCasterGUID = 0; // Reset after visual resolution
    return res;
}

static bool InstallCastVisualHook() {
    BYTE* target = reinterpret_cast<BYTE*>(ADDR_GET_CAST_VISUAL);
    if (target[0] != 0x55 || target[1] != 0x8B || target[2] != 0xEC) return false;

    std::memcpy(g_castVisualOrigBytes, target, 5);
    
    void* tramp = VirtualAlloc(nullptr, 16, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if (!tramp) return false;

    BYTE* t = reinterpret_cast<BYTE*>(tramp);
    std::memcpy(t, g_castVisualOrigBytes, 5);
    t[5] = 0xE9;
    *reinterpret_cast<DWORD*>(t + 6) = (DWORD)((reinterpret_cast<uintptr_t>(target) + 5) - (reinterpret_cast<uintptr_t>(t) + 10));

    g_originalGetCastVisual = reinterpret_cast<GetCastVisualFn>(tramp);

    DWORD oldProt;
    if (VirtualProtect(target, 5, PAGE_EXECUTE_READWRITE, &oldProt)) {
        target[0] = 0xE9;
        *reinterpret_cast<DWORD*>(target + 1) = (DWORD)(reinterpret_cast<uintptr_t>(&Hooked_GetCastVisual) - reinterpret_cast<uintptr_t>(target) - 5);
        VirtualProtect(target, 5, oldProt, &oldProt);
        FlushInstructionCache(GetCurrentProcess(), target, 5);
        return true;
    }
    return false;
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
    
    LoadProtectedSpells(); // Load from database first
    PreloadSpellDBC(); // Snapshots and identifies visual IDs using the loaded spells
    InstallCastVisualHook(); // Install the context tracker hook
    IdentifyProtectedVisualIds();

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

static std::unordered_map<uint32_t, uint32_t> g_originalVisualIds;

void PatchSpellVisualId(uint32_t sourceSpellId, uint32_t targetSpellId) {
    if (sourceSpellId == 0 || targetSpellId == 0) return;

    auto srcIt = g_spellRowPointers.find(sourceSpellId);
    if (srcIt == g_spellRowPointers.end() || !srcIt->second) return;

    uint32_t targetVisualId = 0;
    auto tgtMapIt = g_spellIdToVisualIdMap.find(targetSpellId);
    if (tgtMapIt != g_spellIdToVisualIdMap.end()) {
        targetVisualId = tgtMapIt->second.first;
        if (targetVisualId == 0) targetVisualId = tgtMapIt->second.second;
    }
    if (targetVisualId == 0) return;

    uintptr_t rowAddr = (uintptr_t)srcIt->second;
    if (g_originalVisualIds.find(sourceSpellId) == g_originalVisualIds.end()) {
        g_originalVisualIds[sourceSpellId] = *reinterpret_cast<uint32_t*>(rowAddr + 131 * 4);
    }

    DWORD oldProt;
    if (VirtualProtect((void*)(rowAddr + 131 * 4), 4, PAGE_EXECUTE_READWRITE, &oldProt)) {
        *reinterpret_cast<uint32_t*>(rowAddr + 131 * 4) = targetVisualId;
        DWORD dummy;
        VirtualProtect((void*)(rowAddr + 131 * 4), 4, oldProt, &dummy);
    }

    Log("Patched spell %u visual ID: %u -> %u (target spell %u)",
        sourceSpellId, g_originalVisualIds[sourceSpellId], targetVisualId, targetSpellId);
}

void RestoreSpellVisualId(uint32_t sourceSpellId) {
    if (sourceSpellId == 0) return;

    auto origIt = g_originalVisualIds.find(sourceSpellId);
    if (origIt == g_originalVisualIds.end()) return;

    auto srcIt = g_spellRowPointers.find(sourceSpellId);
    if (srcIt == g_spellRowPointers.end() || !srcIt->second) return;

    uintptr_t rowAddr = (uintptr_t)srcIt->second;
    uint32_t originalId = origIt->second;

    DWORD oldProt;
    if (VirtualProtect((void*)(rowAddr + 131 * 4), 4, PAGE_EXECUTE_READWRITE, &oldProt)) {
        *reinterpret_cast<uint32_t*>(rowAddr + 131 * 4) = originalId;
        DWORD dummy;
        VirtualProtect((void*)(rowAddr + 131 * 4), 4, oldProt, &dummy);
    }

    g_originalVisualIds.erase(sourceSpellId);
    Log("Restored spell %u visual ID to %u", sourceSpellId, originalId);
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
    g_spellToVisualCache.clear();
    g_originalVisualIds.erase(sourceSpellId);
    g_sanitizedPtrGeneration.clear();
    g_lastGranularState.clear();
    g_morphGeneration++;
    ReleaseSRWLockExclusive(&g_spellMorphLock);
}

void ClearSpellMorphs() {
    AcquireSRWLockExclusive(&g_spellMorphLock);
    g_spellMorphs.clear();
    g_spellToVisualCache.clear();
    g_originalVisualIds.clear();
    g_sanitizedPtrGeneration.clear();
    g_lastGranularState.clear();
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

        std::string q = query;
        for (size_t i = 0; i < q.length(); ++i) q[i] = (char)tolower(q[i]);

        bool showAll = q == "*" || q == "all" || q == "." || q.empty();
        bool showProtected = q == "protected" || q == "icc" || q == "whitelist";

        // If we have live DBC access, use it for 100% accuracy
        void* db = *reinterpret_cast<void**>(ADDR_SPELL_DB);
        if (db) {
            uint32_t minId = *reinterpret_cast<uint32_t*>(reinterpret_cast<uintptr_t>(db) + 16);
            uint32_t maxId = *reinterpret_cast<uint32_t*>(reinterpret_cast<uintptr_t>(db) + 12);
            SpellRec** records = *reinterpret_cast<SpellRec***>(reinterpret_cast<uintptr_t>(db) + 32);

            if (records) {
                for (uint32_t id = minId; id <= maxId; ++id) {
                    SpellRec* pRec = records[id - minId];
                    if (!pRec || pRec->m_ID != id) continue;

                    bool match = false;
                    if (showAll) {
                        match = true;
                    } else if (showProtected) {
                        match = g_protectedIds.count(id) || g_protectedVisualIds.count(pRec->m_spellVisualID[0]);
                    } else {
                        // Match ID
                        if (std::to_string(id).find(q) != std::string::npos) {
                            match = true;
                        } else if (pRec->m_name) {
                            // Match Name
                            std::string n = pRec->m_name;
                            for (size_t i = 0; i < n.length(); ++i) n[i] = (char)tolower(n[i]);
                            if (n.find(q) != std::string::npos) match = true;
                        }
                    }

                    if (match) {
                        result += std::to_string((unsigned int)id) + "|";
                        count++;
                        if (count >= LIMIT) break;
                    }
                }
                if (!result.empty()) return result;
            }
        }

        // Fallback to preloaded names map if DBC iterate fails
        for (auto it = g_spellNames.begin(); it != g_spellNames.end(); ++it) {
            if (count >= LIMIT) break;
            std::string n = it->second;
            for (size_t i = 0; i < n.length(); ++i) n[i] = (char)tolower(n[i]);

            if (showAll || n.find(q) != std::string::npos || std::to_string(it->first).find(q) != std::string::npos) {
                result += std::to_string((unsigned int)it->first) + "|";
                count++;
            }
        }

        return result;
    }
}

std::string SearchSpells(const std::string& query) {
    return SearchSpellsInternal(query);
}

std::string ExportProtectedSpellIds() {
    std::vector<uint32_t> ids;
    {
        SharedLock lock(&g_spellMorphLock);
        ids.reserve(g_protectedIds.size());
        for (std::unordered_set<uint32_t>::const_iterator it = g_protectedIds.begin(); it != g_protectedIds.end(); ++it) {
            ids.push_back(*it);
        }
    }

    std::sort(ids.begin(), ids.end());

    std::string result;
    for (size_t i = 0; i < ids.size(); ++i) {
        if (!result.empty()) result += "|";
        result += std::to_string((unsigned int)ids[i]);
    }
    return result;
}

bool AddProtectedSpellId(uint32_t spellId) {
    if (spellId == 0) return false;
    bool changed = false;
    {
        ExclusiveLock lock(&g_spellMorphLock);
        std::pair<std::unordered_set<uint32_t>::iterator, bool> res = g_protectedIds.insert(spellId);
        if (res.second) {
            RebuildProtectedVisualIds_NoLock();
            changed = true;
        }
    }
    if (changed) {
        SoftResetCache();
    }
    return changed;
}

bool RemoveProtectedSpellId(uint32_t spellId) {
    if (spellId == 0) return false;
    bool changed = false;
    {
        ExclusiveLock lock(&g_spellMorphLock);
        size_t removed = g_protectedIds.erase(spellId);
        if (removed > 0) {
            RebuildProtectedVisualIds_NoLock();
            changed = true;
        }
    }
    if (changed) {
        SoftResetCache();
    }
    return changed;
}

void ClearProtectedSpellIds() {
    bool changed = false;
    {
        ExclusiveLock lock(&g_spellMorphLock);
        changed = !g_protectedIds.empty() || !g_protectedVisualIds.empty();
        g_protectedIds.clear();
        g_protectedVisualIds.clear();
    }
    if (changed) {
        SoftResetCache();
    }
}

bool SaveProtectedSpellIds() {
    std::vector<uint32_t> ids;
    {
        SharedLock lock(&g_spellMorphLock);
        ids.reserve(g_protectedIds.size());
        for (std::unordered_set<uint32_t>::const_iterator it = g_protectedIds.begin(); it != g_protectedIds.end(); ++it) {
            ids.push_back(*it);
        }
    }

    std::sort(ids.begin(), ids.end());

    FILE* f = nullptr;
    const char* path = GetProtectedSpellsPath();
    if (fopen_s(&f, path, "w") != 0 || !f) {
        Log("ERROR: failed to save protected spells to %s", path);
        return false;
    }

    for (size_t i = 0; i < ids.size(); ++i) {
        fprintf(f, "%u\n", (unsigned int)ids[i]);
    }

    fclose(f);
    Log("Saved %u protected spell IDs to %s", (unsigned int)ids.size(), path);
    return true;
}

void ReloadProtectedSpellIds() {
    LoadProtectedSpells();
    IdentifyProtectedVisualIds();
    SoftResetCache();
}

size_t GetSpellDBCRecordCount() {
    return g_spellIdToVisualIdMap.size();
}

// --- Visibility Logic (Post-Namespace for SoftResetCache Access) ---

void SetHideAllSpells(bool hide) { g_hideAllSpells = hide; }
void SetShowOwnSpells(bool show) { g_showOwnSpells = show; }
void SetHidePrecast(bool hide) { g_hidePrecast = hide; }
void SetHideCast(bool hide)    { g_hideCast = hide; }
void SetHideChannel(bool hide) { g_hideChannel = hide; }
void SetHideAuraStart(bool hide) { g_hideAuraStart = hide; }
void SetHideAuraEnd(bool hide)   { g_hideAuraEnd = hide; }
void SetHideImpact(bool hide)    { g_hideImpact = hide; }
void SetHideImpactCaster(bool hide) { g_hideImpactCaster = hide; }
void SetHideTargetImpact(bool hide) { g_hideTargetImpact = hide; }
void SetHideAreaInstant(bool hide)  { g_hideAreaInstant = hide; }
void SetHideAreaImpact(bool hide)   { g_hideAreaImpact = hide; }
void SetHideAreaPersistent(bool hide) { g_hideAreaPersistent = hide; }
void SetHideMissile(bool hide)      { g_hideMissile = hide; }
void SetHideMissileMarker(bool hide) { g_hideMissileMarker = hide; }
void SetHideSoundMissile(bool hide) { g_hideSoundMissile = hide; }
void SetHideSoundEvent(bool hide)   { g_hideSoundEvent = hide; }

bool GetHideAllSpells() { return g_hideAllSpells; }
bool GetShowOwnSpells() { return g_showOwnSpells; }
bool GetHidePrecast()   { return g_hidePrecast; }
bool GetHideCast()      { return g_hideCast; }
bool GetHideChannel()   { return g_hideChannel; }
bool GetHideAuraStart() { return g_hideAuraStart; }
bool GetHideAuraEnd()   { return g_hideAuraEnd; }
bool GetHideImpact()    { return g_hideImpact; }
bool GetHideImpactCaster() { return g_hideImpactCaster; }
bool GetHideTargetImpact() { return g_hideTargetImpact; }
bool GetHideAreaInstant()  { return g_hideAreaInstant; }
bool GetHideAreaImpact()   { return g_hideAreaImpact; }
bool GetHideAreaPersistent() { return g_hideAreaPersistent; }
bool GetHideMissile()      { return g_hideMissile; }
bool GetHideMissileMarker() { return g_hideMissileMarker; }
bool GetHideSoundMissile() { return g_hideSoundMissile; }
bool GetHideSoundEvent()   { return g_hideSoundEvent; }

void AddPlayerSpellbookSpellId(uint32_t spellId) {
    if (spellId == 0) return;
    ExclusiveLock lock(&g_playerSpellbookLock);
    g_playerSpellbookSpells.insert(spellId);
}

void ClearPlayerSpellbookSpellIds() {
    ExclusiveLock lock(&g_playerSpellbookLock);
    g_playerSpellbookSpells.clear();
}

void SpellMorph_SoftResetCache() {
    SoftResetCache();
}

extern "C" __declspec(dllexport) void SpellMorph_SetHideAll(int hide) {
    SetHideAllSpells(hide != 0);
    SoftResetCache();
}

extern "C" __declspec(dllexport) void SpellMorph_SetHidePrecast(int hide) { SetHidePrecast(hide != 0); SoftResetCache(); }
extern "C" __declspec(dllexport) void SpellMorph_SetHideCast(int hide)    { SetHideCast(hide != 0); SoftResetCache(); }
extern "C" __declspec(dllexport) void SpellMorph_SetHideChannel(int hide) { SetHideChannel(hide != 0); SoftResetCache(); }
extern "C" __declspec(dllexport) void SpellMorph_SetHideAuraStart(int hide) { SetHideAuraStart(hide != 0); SoftResetCache(); }
extern "C" __declspec(dllexport) void SpellMorph_SetHideAuraEnd(int hide)   { SetHideAuraEnd(hide != 0); SoftResetCache(); }
extern "C" __declspec(dllexport) void SpellMorph_SetHideImpact(int hide)    { SetHideImpact(hide != 0); SoftResetCache(); }
extern "C" __declspec(dllexport) void SpellMorph_SetHideImpactC(int hide)   { SetHideImpactCaster(hide != 0); SoftResetCache(); }
extern "C" __declspec(dllexport) void SpellMorph_SetHideImpactT(int hide)   { SetHideTargetImpact(hide != 0); SoftResetCache(); }
extern "C" __declspec(dllexport) void SpellMorph_SetHideAreaInst(int hide)  { SetHideAreaInstant(hide != 0); SoftResetCache(); }
extern "C" __declspec(dllexport) void SpellMorph_SetHideAreaImp(int hide)   { SetHideAreaImpact(hide != 0); SoftResetCache(); }
extern "C" __declspec(dllexport) void SpellMorph_SetHideAreaPers(int hide)  { SetHideAreaPersistent(hide != 0); SoftResetCache(); }
extern "C" __declspec(dllexport) void SpellMorph_SetHideMissile(int hide)   { SetHideMissile(hide != 0); SoftResetCache(); }
extern "C" __declspec(dllexport) void SpellMorph_SetHideMissileM(int hide)  { SetHideMissileMarker(hide != 0); SoftResetCache(); }
extern "C" __declspec(dllexport) void SpellMorph_SetHideSoundM(int hide)    { SetHideSoundMissile(hide != 0); SoftResetCache(); }
extern "C" __declspec(dllexport) void SpellMorph_SetHideSoundE(int hide)    { SetHideSoundEvent(hide != 0); SoftResetCache(); }

extern "C" {
    void SpellMorph_AddWhiteCard(int spellId) {
        if (spellId <= 0) return;
        ExclusiveLock lock(&g_whiteCardLock);
        g_whiteCardSpells.insert((uint32_t)spellId);
        SoftResetCache();
    }

    void SpellMorph_RemoveWhiteCard(int spellId) {
        if (spellId <= 0) return;
        ExclusiveLock lock(&g_whiteCardLock);
        g_whiteCardSpells.erase((uint32_t)spellId);
        SoftResetCache();
    }

    void SpellMorph_ClearWhiteCard() {
        ExclusiveLock lock(&g_whiteCardLock);
        g_whiteCardSpells.clear();
        SoftResetCache();
    }
}
