#pragma once
#include <cstdint>
#include <cstddef>

// ============================================================
// ColorEngine — runtime recoloring features for Transmorpher.
//
// All addresses verified against the 3.3.5a (12340/HD) client:
//   TextureLoadImage          0x004B81D0  __cdecl   (BLP/texture redirect)
//   DayNight::SetOverrideFog  0x007ED870  __cdecl   (world fog color)
//   DayNight::ClearOverrideFog 0x007ED820 __cdecl
//   CParticleEmitter2::SetParticleColors 0x0097A990 __thiscall (particle color)
//
// These are the "DBC-swap" philosophy applied to rendering: we either call
// the client's own override APIs or redirect/override values at load/draw time.
// ============================================================
namespace ColorEngine {
    void Initialize();   // install hooks (call once, in world-safe init)
    void Shutdown();     // remove hooks (ONLY on graceful FreeLibrary, never on process exit)

    // --- Texture swap (Items / any texture): redirect one texture path to another ---
    void TexSwapAdd(const char* fromPath, const char* toPath);
    void TexSwapRemove(const char* fromPath);
    void TexSwapClear();

    // --- World fog color (uses the client's own override system) ---
    // start/end are the fog start/end rate (0..1 of far clip). Pass enable=false to clear.
    void SetFogColor(bool enable, uint8_t r, uint8_t g, uint8_t b, float start, float end);

    // --- Particle color tint (multiplies all emitted particle colors) ---
    void SetParticleTint(bool enable, uint8_t r, uint8_t g, uint8_t b);

    // --- World lighting preset override (recolors ALL lit geometry: units,
    //     terrain, buildings, sky) via the client's own DayNight override.
    //     id < 0 clears the override and restores the natural zone lighting. ---
    void SetLightPreset(int lightParamsId);

    // --- World color tint: multiplies the DayNight computed world colors
    //     (ambient, diffuse, and the sky band colors) so terrain, the sky and
    //     ambient lighting take on the chosen hue. Recomputed by the client on
    //     each light update; we re-apply in a hook. Identity at white. ---
    void SetWorldColorTint(bool enable, uint8_t r, uint8_t g, uint8_t b);

    // --- Absolute world-lighting mood: OVERWRITES the DayNight world color block
    //     with designed ambient/diffuse/sky colors so a preset looks identical in
    //     every zone (robust, deterministic). Builds a top->horizon sky gradient
    //     and an optional matching fog. All channels are 0..255. ---
    void SetWorldLight(bool enable,
                       uint8_t ar, uint8_t ag, uint8_t ab,
                       uint8_t dr, uint8_t dg, uint8_t db,
                       uint8_t str_, uint8_t stg, uint8_t stb,
                       uint8_t shr, uint8_t shg, uint8_t shb,
                       bool fogOn, uint8_t fr, uint8_t fg, uint8_t fb);

    // --- World brightness: multiplies the natural (or mood) world color block by
    //     a scalar (0..4, 1 = unchanged). Works in every zone/time of day. ---
    void SetWorldBrightness(bool enable, float mult);

    // --- Weather control (engine): force precipitation in the current zone via
    //     the client's own Weather::SetType. type: 0=clear, 1=rain, 2=snow,
    //     3=sandstorm. intensity 0..1. The desired state is remembered and
    //     re-asserted each tick until the engine actually applies it (the weather
    //     object is created lazily, so a single call can land too early — this is
    //     what made the user "spam the button"). ---
    void SetWeather(int type, float intensity, bool abrupt);
    void ReassertWeather();   // call each tick; retries until the engine takes it

    // --- Skybox override (engine): substitutes the zone's skybox model name so
    //     the client renders the chosen skybox M2 through its own path. Empty/null
    //     name clears the override. Re-asserted automatically each light update. ---
    void SetSkybox(const char* skyboxModelName);
    void SetSkyboxById(int lightSkyboxId);   // resolve name from LightSkybox.dbc, apply
    void ReassertSkybox();   // call each frame/light update to keep the override
    // Enumerate LightSkybox.dbc and publish (id,name) pairs into the Lua global
    // TRANSMORPHER_SKYBOXES so the addon can list every real skybox (no guessing).
    void PublishSkyboxList();

    // Enumerate ChrRaces.dbc live and publish each playable race + its male/female
    // body display ids into the Lua global TRANSMORPHER_RACES. These display ids are
    // the canonical PLAYER models, so they are guaranteed gear-capable (fixes the
    // races that rendered gearless from hand-picked NPC display ids) and any CUSTOM
    // races present on the client appear automatically.
    void PublishRaceList();

    // Enumerate gear-wearing HUMANOID displays (CreatureDisplayInfo entries whose
    // CDIExtra has a race and EMPTY baked items, so they wear the player's own gear)
    // into the Lua global TRANSMORPHER_HUMANOIDS for a browse/select picker. Scans
    // the DB's real id range. maxOut caps how many are published.
    void PublishHumanoidList(int maxOut);

    // --- Over-unit "world text" recolor (engine): the numbers/words the client
    //     draws floating up off a unit in the 3D world (your damage, crits, heals,
    //     MISS/DODGE/..., XP, honor). Recolored at the single creation chokepoint
    //     WorldTextCreate, addressed by the engine STYLE, so it works for the
    //     player's OWN hits too (the old constant-swap only caught pet text).
    //     Styles: 0=damage 2=damage-crit 6=heal 7=heal-crit 3=miss/avoid 1=absorb
    //             4=xp 5=honor (others left to the engine default).
    //     mode: 0 = solid color, 1 = animated rainbow gradient. Fully reversible. ---
    void SetWorldTextStyle(int style, bool enable, int mode, uint8_t r, uint8_t g, uint8_t b);
    void SetWorldTextGradientSpeed(float cyclesPerSec);  // rainbow speed (e.g. 0.25)
    void SetWorldTextSize(bool enable, float factor);     // 1.0 = native size
    void ClearWorldText();                                // disable all + restore size

    // --- Model lighting tint: multiplies the ambient + directional light color
    //     applied to every 3D model (units, bosses, the player, equipment,
    //     doodads). Preserves shading, recolors the whole scene's lighting. ---
    void SetModelTint(bool enable, uint8_t r, uint8_t g, uint8_t b);

    // --- Equipment retexture (true DBC-swap): repoints item A's in-memory
    //     ItemDisplayInfo texture pointers to item B's, so A renders with B's
    //     skin/color while keeping its own model. Fully reversible.
    //     Returns true on success. ---
    bool ItemRetexAdd(uint32_t fromItemId, uint32_t toItemId);
    void ItemRetexRemove(uint32_t fromItemId);
    void ItemRetexClear();
    // Display-id variants for render targets that only carry an ItemDisplayInfo
    // id (e.g. the character-select doll). Keyed internally on 0x80000000|disp so
    // they coexist with the item-id entries and ItemRetexClear cleans both.
    bool ItemRetexAddDisplay(uint32_t fromDisplayId, uint32_t toItemId);

    // --- Per-slot weapon texture tint: points the slot's ItemDisplayInfo texture
    //     name at a synthetic BLP path, loads the original BLP through that path,
    //     and tints the decoded pixels. slot is equipment id 16/17/18. ---
    // Extended per-slot tint with full effect set (Customize popup):
    //   mode: 0 solid, 1 gradient(2-color), 2 rainbow, 3 two-region
    //   (r,g,b) primary, (r2,g2,b2) secondary; dir 0 vert/1 horiz/2 diag;
    //   multX100 intensity, glowStr 0..255 emissive, contrast 0..200 (100 neutral),
    //   rainbowSpanX100 sweep tightness, phase 0..255 animation offset (slow cycle).
    bool ItemTintSlotSet(uint32_t slot, uint32_t fromItemId,
                         int mode, uint8_t r, uint8_t g, uint8_t b,
                         uint8_t r2, uint8_t g2, uint8_t b2,
                         int dir, int multX100, int glowStr, int contrast,
                         int rainbowSpanX100, int phase,
                         int brightness, int saturation, int hueShift);
    void ItemTintSlotRemove(uint32_t slot);
    void ItemTintClear();
    // Reload every loaded texture from source (the engine's own device-restart path).
    void ReloadAllTextures();
    // Force a clean re-decode of the separate-model textures (helmet/shoulder/cape/weapon)
    // shown in `slot` for `fromItemId`. The model item's tint is baked into its cached
    // texture pixels, so this is what actually drops it on reset without a relog. Call
    // AFTER the tint maps are cleared.
    void ReloadModelTexturesForSlot(uint32_t slot, uint32_t fromItemId);
    // Reset cache-buster for separate-model slots. Registers an identity virtual texture
    // path for the slot's original model BLPs, so a reset re-attaches a clean texture
    // object instead of reusing the old tinted/reskinned one.
    void ArmCleanModelTexturesForSlot(uint32_t slot, uint32_t fromItemId);
    // Display-id variant (see ItemRetexAddDisplay for rationale).
    bool ItemTintSlotSetDisplay(uint32_t slot, uint32_t fromDisplayId,
                                int mode, uint8_t r, uint8_t g, uint8_t b,
                                uint8_t r2, uint8_t g2, uint8_t b2,
                                int dir, int multX100, int glowStr, int contrast,
                                int rainbowSpanX100, int phase,
                                int brightness, int saturation, int hueShift);

    // Real per-race/gender character-customization counts, read live from the
    // CharSections / CharHairGeosets / CharacterFacialHairStyles DBCs (RE-verified
    // object addresses + field offsets). Used by the Barber tab so each option's
    // range is the TRUE number of variations for the player's race+sex, not a guess.
    // A 0 means the table wasn't loaded for that race/sex (caller falls back).
    void GetBarberMaxes(int race, int sex, int* outSkin, int* outFace,
                        int* outHairStyle, int* outHairColor, int* outFacial);
    void GetBarberValueLists(int race, int sex, int classId,
                             int skinIdx, int faceIdx, int hairStyleIdx, int hairColorIdx, int facialIdx,
                             char* outSkin, size_t skinSz,
                             char* outFace, size_t faceSz,
                             char* outHairStyle, size_t hairStyleSz,
                             char* outHairColor, size_t hairColorSz,
                             char* outFacial, size_t facialSz);

    // Resolve a display id to the character race/gender/appearance it renders as.
    // Uses CreatureDisplayInfoExtra first, then ChrRaces male/female display fallback.
    // Returns false for true non-character creature displays.
    bool ResolveDisplayCharacterAppearance(uint32_t displayId,
                                           int* outRace, int* outSex,
                                           int* outSkin, int* outFace,
                                           int* outHairStyle, int* outHairColor,
                                           int* outFacial, bool* outFromExtra);

    // Free-RGB recolor of the player's OWN body/hair textures, per region
    // (0 skin, 1 face, 2 hair, 3 facial). The exact BLP paths are read live from
    // CharSections for the player's race/sex + current colour index, then tinted with
    // the same effect set as the Skin tab via the body-component SFile pipeline.
    // enable=false (or ClearBarberRegionTints) removes the region's tint. A model
    // rebuild after calling is what makes the new colour show.
    void SetBarberRegionTint(int region, int race, int sex, int classId,
                             int skinIdx, int faceIdx, int hairStyleIdx, int hairColorIdx, int facialIdx,
                             bool enable,
                             int mode, uint8_t r, uint8_t g, uint8_t b,
                             uint8_t r2, uint8_t g2, uint8_t b2,
                             int dir, int multX100, int glowStr, int contrast,
                             int rainbowSpanX100, int phase,
                             int brightness, int saturation, int hueShift);
    void ClearBarberRegionTints();

    // Force the currently-selected character-select doll to rebuild through our glue hook,
    // so the persisted barber/morph/skin look shows on a COLD game launch (the engine caches
    // the doll once before our customization ran, and only rebuilds on a world round-trip
    // otherwise). Glue-screen + main-thread only.
    void ForceRefreshCharSelectDoll();

    // Diagnostic: log every body/model component texture path the client requests
    // (Item\TextureComponents\... and Item\ObjectComponents\...) with which hook saw
    // it and whether our redirect/tint matched. Used to pin down why composite armor
    // recolor misses. Resets the hit cap so a fresh capture starts each toggle.
    void SetTexDiag(bool on);
}
