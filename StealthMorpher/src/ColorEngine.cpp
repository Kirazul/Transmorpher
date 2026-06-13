#include "ColorEngine.h"
#include "Morpher.h"
#include "ShutdownCheck.h"
#include "Utils.h"

#include <windows.h>
#include <string>
#include <vector>
#include <unordered_map>
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <cstdarg>
#include "../third_party/Detours/detours.h"

// Weapon sheath-position hook lives in Morpher.cpp (it needs the local-player /
// descriptor logic); we attach it here alongside the other render hooks. These
// are GLOBAL-scope symbols (defined in Morpher.cpp), declared before the
// ColorEngine namespace so they don't get namespace-mangled.
extern void* g_oGetSheatheType;
int __fastcall Morpher_hkGetSheatheType(void* This, void* edx);

// ------------------------------------------------------------------
// Verified client functions (3.3.5a 12340 / HD)
// ------------------------------------------------------------------
typedef void* (__cdecl* TextureLoadImage_t)(const char* filename, uint32_t* width, uint32_t* height,
                                            int* dataFormat, int* isOpaque, void* status,
                                            uint32_t* alphaBits, int a8);
static TextureLoadImage_t oTextureLoadImage = reinterpret_cast<TextureLoadImage_t>(0x004B81D0);

typedef void* (__cdecl* TextureCacheGetTexture_t)(const char* filename);
static TextureCacheGetTexture_t oTextureCacheGetTexture = reinterpret_cast<TextureCacheGetTexture_t>(0x004B6F30);

typedef void* (__cdecl* TextureCacheGetTextureEx_t)(const char* filename, char* outExt, int a3);
static TextureCacheGetTextureEx_t oTextureCacheGetTextureEx = reinterpret_cast<TextureCacheGetTextureEx_t>(0x004B6FA0);

typedef int(__fastcall* BLPFileLockChain2_t)(void* This, void* edx, char* fileName,
                                             int format, void** images, uint32_t mipLevel, int a6);
static BLPFileLockChain2_t oBLPFileLockChain2 = reinterpret_cast<BLPFileLockChain2_t>(0x006AFFD0);

// TextureNotifyGxRestart (@0x004B65E0): the engine's own "reload every texture from
// source" — it walks the global texture list and, for each, rebuilds "<name>.blp" and
// re-runs the BLP loader (0x004B5C30 -> BLPFileLockChain2, our decode hook) then re-
// uploads to the GPU. This is what the client does on a device reset / alt-tab, and it
// is the ONE reliable way to drop a tint that was baked IN PLACE into a model item's
// cached texture (helmet/shoulder/cape/weapon): once our tint map is cleared, the reload
// re-decodes those textures clean. Takes no args; reads its globals.
typedef void(__cdecl* TextureReloadAll_t)();
static TextureReloadAll_t oTextureReloadAll = reinterpret_cast<TextureReloadAll_t>(0x004B65E0);

// CTexture::LoadFromFile (@0x004B7BD0): a texture object's "(re)decode my BLP from disk
// into my own buffer AND re-upload to the GPU". `this` arrives in EAX. We HOOK it only to
// CAPTURE the live texture object for every model-item BLP (Item\ObjectComponents\...:
// helmet/shoulder/cape/weapon) keyed by its real path, so a reset can force exactly those
// to re-decode. The decode runs back through our BLPFileLockChain2 hook, so once the tint
// map is cleared the reload is clean — this is the only thing that drops a tint that was
// baked directly into a model item's cached texture pixels (verified via runtime logs).
static PVOID oTexLoadFromFile = reinterpret_cast<PVOID>(0x004B7BD0);
// CTexture::Reload (@0x004B7E80): int __cdecl(texObj) — calls LoadFromFile with the arg
// derived from the texture itself. This is what we invoke per captured texobj on reset.
typedef int(__cdecl* ReloadTexture_t)(void* texObj);
static ReloadTexture_t oReloadTexture = reinterpret_cast<ReloadTexture_t>(0x004B7E80);

// Character body-armor compositor: get-or-create a component texture by path. This
// is the ONLY consumer of the "Item\TextureComponents\%s\%s_%s.blp" path builder
// (@0x004E6FB0) and uses its OWN texture cache (@0x00B6BA54) — which is exactly why
// body armor (chest/legs/hands/feet/waist/wrist/shirt/tabard) bypasses the four
// generic texture hooks above. Hooking it lets us redirect a body component to a
// donor's (skin swap) and observe whether the bake actually re-runs on re-apply.
typedef void* (__cdecl* CompositeTexGet_t)(const char* path);
static CompositeTexGet_t oCompositeTexGet = reinterpret_cast<CompositeTexGet_t>(0x004F3930);

// SFile (Storm) layer — how the character compositor actually pulls body-armor
// component BLP bytes (it bypasses the 4 texture hooks). VERIFIED ABIs:
//   SFileOpen  0x00424B50  __stdcall(int a0, const char* path, int a2, void** outHandle) -> 1 on success
//   SFileRead  0x00422530  __stdcall(void* h, void* buf, uint32_t toRead, uint32_t* bytesRead, void* a4, void* a5)
//   HandleFree 0x004224A0  __thiscall(void* handle, int flags)  (handle destructor)
// We tint the BLP pixel bytes in-place as the client reads them, so body armor
// recolors through the SAME pixel math as weapons, just one layer lower.
typedef int(__stdcall* SFileOpen_t)(int a0, const char* path, int a2, void** outHandle);
static SFileOpen_t oSFileOpen = reinterpret_cast<SFileOpen_t>(0x00424B50);
typedef int(__stdcall* SFileRead_t)(void* handle, void* buf, uint32_t toRead, uint32_t* bytesRead, void* a4, void* a5);
static SFileRead_t oSFileRead = reinterpret_cast<SFileRead_t>(0x00422530);
typedef void* (__fastcall* HandleFree_t)(void* handle, void* edx, int flags);
static HandleFree_t oHandleFree = reinterpret_cast<HandleFree_t>(0x004224A0);

typedef void(__cdecl* SetOverrideFog_t)(float startRate, float endRate, uint32_t colorBGRA, int flag);
static SetOverrideFog_t pSetOverrideFog = reinterpret_cast<SetOverrideFog_t>(0x007ED870);
typedef void(__cdecl* ClearOverrideFog_t)();
static ClearOverrideFog_t pClearOverrideFog = reinterpret_cast<ClearOverrideFog_t>(0x007ED820);

// DayNight::SetOverrideLightParamsID(int) / ClearOverrideLightParamsID()
typedef void(__cdecl* SetOverrideLightParams_t)(int id);
static SetOverrideLightParams_t pSetOverrideLightParams = reinterpret_cast<SetOverrideLightParams_t>(0x007ECEC0);
typedef void(__cdecl* ClearOverrideLightParams_t)();
static ClearOverrideLightParams_t pClearOverrideLightParams = reinterpret_cast<ClearOverrideLightParams_t>(0x007ECEE0);

// CParticleEmitter2::SetParticleColors(this, CImVector* start, CImVector* mid, CImVector* end)
typedef void(__fastcall* SetParticleColors_t)(void* This, void* edx, uint32_t* start, uint32_t* mid, uint32_t* end);
static SetParticleColors_t oSetParticleColors = reinterpret_cast<SetParticleColors_t>(0x0097A990);

// WowClientDB::GetRecord(this=IDatabase*, id)  __thiscall, ret 4. The IDatabase
// sub-object lives at (db_base + 0x18). Returns the record pointer or null.
typedef void* (__fastcall* GetRecord_t)(void* idatabase, void* edx, int id);
static GetRecord_t pGetRecord = reinterpret_cast<GetRecord_t>(0x0065C290);
static void* const g_itemDB             = reinterpret_cast<void*>(0x00AD3D4C);
static void* const g_itemDisplayInfoDB  = reinterpret_cast<void*>(0x00AD3DDC);
// ItemRec: m_displayInfoID @ 0x14
// ItemDisplayInfoRec layout (verified, records.h):
//   m_ID 0x00; m_modelName[2] 0x04,0x08; m_modelTexture[2] 0x0C,0x10;
//   m_inventoryIcon[2] 0x14,0x18; m_geosetGroup[3] 0x1C,0x20,0x24; m_flags 0x28;
//   m_spellVisualID 0x2C; m_groupSoundIndex 0x30; m_helmetGeosetVisID[2] 0x34,0x38;
//   m_texture[8] 0x3C..0x58; m_itemVisual 0x5C; m_particleColorID 0x60.
// Recolor = swap the skin (BLP) + the visual EFFECTS, but NOT the shape. So the
// item keeps its own model and geometry and only its color/glow/particles change:
//   m_modelTexture[0..1]  -> weapon / single-model skin
//   m_texture[0..7]       -> armor body component skins
//   m_spellVisualID       -> weapon glow
//   m_itemVisual          -> enchant / particle visuals
//   m_particleColorID     -> particle color
// Left untouched (shape & identity): m_modelName (model), m_geosetGroup &
// m_helmetGeosetVisID (geometry), m_flags, m_inventoryIcon, m_groupSoundIndex.
static const int kRetexOffsets[] = {
    0x0C, 0x10,                                     // modelTexture[0..1] (skin)
    0x3C, 0x40, 0x44, 0x48, 0x4C, 0x50, 0x54, 0x58, // texture[0..7] (skin)
    0x2C,                                           // spellVisualID (weapon glow)
    0x5C,                                           // itemVisual (enchant/particle FX)
    0x60,                                           // particleColorID
};
static const int kRetexCount = (int)(sizeof(kRetexOffsets) / sizeof(kRetexOffsets[0]));
static const int kTintNameOffsets[] = {
    0x0C, 0x10,
    0x3C, 0x40, 0x44, 0x48, 0x4C, 0x50, 0x54, 0x58,
};
static const int kTintNameCount = (int)(sizeof(kTintNameOffsets) / sizeof(kTintNameOffsets[0]));

// Body-armor component texture directories, indexed by the m_texture[0..7] field
// index (i.e. kTintNameOffsets index minus 2). VERIFIED against the live 3.3.5a
// client: the engine builds each component's BLP path at 0x004E6FB0 with the
// format string "Item\TextureComponents\%s\%s_%s.blp" where the first %s is taken
// from this region-name table @0x00AC4680, the second is m_texture[index] (at
// ItemDisplayInfo+0x3C+index*4), and the third is the sex/region suffix below.
// This is why armor never recolored: the old code keyed redirects on the bare
// "<name>.blp" (a weapon-style path), but armor really loads from
// "Item\TextureComponents\<region>\<name>_<U|M|F>.blp".
static const char* const kComponentDirs[8] = {
    "ArmUpperTexture",  "ArmLowerTexture",  "HandTexture",
    "TorsoUpperTexture","TorsoLowerTexture","LegUpperTexture",
    "LegLowerTexture",  "FootTexture",
};
// The client tries "_U" (unisex) first, then falls back to the wearer's sex char
// ("_M"/"_F") if the unisex file is absent (path builder @0x004E6FE6). We don't
// know which variant ships for a given component, so we register all three; only
// the one the client actually requests ever fires.
static const char* const kComponentSex[3] = { "U", "M", "F" };
// modelTexture[0..1] (offsets 0x0C/0x10) are single-model item skins; the client
// loads them from Item\ObjectComponents\<Type>\<name>.blp (strings @0x009F6C0C+).
// Pick the subdir from the equip slot; off-hand items may be a weapon OR a shield.
static inline void ObjectComponentDirs(uint32_t slot, const char* out[2], int* count) {
    switch (slot) {
        case 1:  out[0] = "Item\\ObjectComponents\\Head\\";     *count = 1; break;  // Head
        case 3:  out[0] = "Item\\ObjectComponents\\Shoulder\\"; *count = 1; break;  // Shoulder
        case 15: out[0] = "Item\\ObjectComponents\\Cape\\";     *count = 1; break;  // Back/cloak
        case 16: case 18:
                 out[0] = "Item\\ObjectComponents\\Weapon\\";   *count = 1; break;  // MainHand/Ranged
        default: out[0] = "Item\\ObjectComponents\\Weapon\\";
                 out[1] = "Item\\ObjectComponents\\Shield\\";   *count = 2; break;  // Off-hand / unknown
    }
}

// DayNight::SetColors()  __cdecl, no args. Computes the world colors into a
// global block: 21 floats at 0x00D38C1C (7 RGB triples: ambient, diffuse, and
// sky bands) + a packed ambient CImVector at 0x00D38BD4.
typedef void(__cdecl* SetColors_t)();
static SetColors_t oSetColors = reinterpret_cast<SetColors_t>(0x007F3230);
static float* const g_worldColorFloats = reinterpret_cast<float*>(0x00D38C1C);
static const int    g_worldColorFloatCount = 21;
static uint32_t* const g_worldAmbientCImVector = reinterpret_cast<uint32_t*>(0x00D38BD4);

// ---- Weather (engine) ----
// g_weather = *(Weather**)0x00CD7544 (set right after Weather::ctor at 0x781322).
// Weather::SetType(this, type, intensity, WeatherRec*, abrupt, transition) __thiscall.
//   Mimics the SMSG_WEATHER handler at 0x526A96: it does GetRecord(WeatherDB,id)
//   then SetType. We instead pass a self-built WeatherRec so no DBC id is needed
//   (the engine fills the rain texture itself; we supply snow/sand textures).
// Weather::Clear(this) __thiscall — stops all precipitation.
static void** const g_weatherPtr = reinterpret_cast<void**>(0x00CD7544);
typedef void(__fastcall* WeatherSetType_t)(void* This, void* edx, int type, float intensity, void* rec, int abrupt, float transition);
static WeatherSetType_t pWeatherSetType = reinterpret_cast<WeatherSetType_t>(0x007846A0);
typedef void(__fastcall* WeatherClear_t)(void* This, void* edx);
static WeatherClear_t pWeatherClear = reinterpret_cast<WeatherClear_t>(0x0078D0B0);
// WeatherRec layout: id 0x00, ambienceID 0x04, effectType 0x08, transitionSkyBox 0x0C,
//   effectColor[3] 0x10/0x14/0x18, effectTexture 0x1C.
struct WeatherRecFake { int id; int ambience; int effectType; float transition; float color[3]; const char* tex; };

// ---- Skybox (engine) ----
// 0x00CD861C holds the const char* name of the current zone's skybox M2; the
// skybox renderer (0x79AC81) reads it each frame and feeds SetBlendSky. Overwrite
// it with our own name to force any skybox through the engine's own path.
static const char** const g_zoneSkyboxName = reinterpret_cast<const char**>(0x00CD861C);
// g_lightSkyboxDB (WowClientDB_LightSkyboxRec). IDatabase sub-object at +0x18.
// LightSkyboxRec: m_ID 0x00, m_name 0x04 (const char* M2 path), m_flags 0x08.
static void* const g_lightSkyboxDB = reinterpret_cast<void*>(0x00AF4998);
// DayNight::SetBlendSky(slot, name, flag, weight) __cdecl, 0x007F31C0. The skybox
// renderer calls it each frame with the zone's blend weight — which is 0 in zones
// that have no native skybox, so forcing only the name renders nothing. We hook it
// to pin OUR skybox into slot 0 at full weight whenever an override is active.
typedef void(__cdecl* SetBlendSky_t)(int slot, const char* name, int flag, float weight);
static SetBlendSky_t oSetBlendSky = reinterpret_cast<SetBlendSky_t>(0x007F31C0);

// ---- Over-unit "world text" recolor (the right way) ----
// Every floating number/word over a unit funnels through ONE creator:
//   WorldTextCreate(int style, C3Vector* pos, const char* text, CImVector* color,
//                   void* a5)  __cdecl, 0x007E6DC0, returns the WORLDTEXTSTRING*.
// It copies the color BY VALUE: `if(color){ obj->color = *color; } else {
// obj->color = g_styleColorTable[style]; }`. The emitters (AddWorldDamageText,
// AddWorldText, AddWorldHealingText, XP/Honor) pass `color = NULL` for the
// PLAYER's own text and only pass the 0xADAA70/0xADAA6C constants for pet/other
// sources — which is why the old constant-swap never colored your own damage.
// Hooking WorldTextCreate and substituting the color by STYLE fixes every case.
// CImVector packs as (A<<24 | R<<16 | G<<8 | B).
typedef void* (__cdecl* WorldTextCreate_t)(int style, void* pos, const char* text,
                                           uint32_t* color, void* a5);
static WorldTextCreate_t oWorldTextCreate = reinterpret_cast<WorldTextCreate_t>(0x007E6DC0);
// WORLDTEXTSTRING::Update(this, age) __thiscall, 0x007E70D0 — runs once per string
// per FRAME (it calls CalculateNewColor to recompute the fade alpha at obj+0x23).
// The base RGB the renderer uses is the CImVector at obj+0x20 (bytes B,G,R,A);
// rewriting just its RGB each frame here makes a rainbow text actually FLOW
// through the spectrum as it floats (an animated gradient on every number),
// instead of each number being one static hue. obj+0x08 = style.
typedef char(__fastcall* WTUpdate_t)(void* This, void* edx, int age);
static WTUpdate_t oWTUpdate = reinterpret_cast<WTUpdate_t>(0x007E70D0);

// ---- Glue character-select morph (transmog + race) ----
// CCharacterSelection::SelectCharacter() __cdecl, no args (reads the selected
// index from a global). It lazily builds the 3D doll (a CCharacterComponent) for
// the selected character and caches it at entry+0x188, so it only builds ONCE.
// We wrap it: mutate the selected character's appearance/items BEFORE the build,
// restore them AFTER — so the doll is created already-morphed (no flicker), and
// the list data stays truthful for login.
typedef void(__cdecl* SelectCharacter_t)();
static SelectCharacter_t oSelectCharacter = reinterpret_cast<SelectCharacter_t>(0x004E3CD0);
// Char list: *(CHARACTER_INFO**)0xB6B240, entry stride 0x198, count @0xB6B23C,
// selected index @0xAC436C. Per entry: guid@+0x00, race@+0x178, class@+0x179,
// gender@+0x17a, skin/face/hairStyle/hairColor/facialHair@+0x17b..+0x17f, and the
// per-slot item DISPLAY-INFO ids @+0x50 (equip slot index).
static uint8_t** const g_charListPtr = reinterpret_cast<uint8_t**>(0x00B6B240);
static int* const      g_charCount   = reinterpret_cast<int*>(0x00B6B23C);
static int* const      g_charSelected = reinterpret_cast<int*>(0x00AC436C);
static void* const     g_chrRacesDB  = reinterpret_cast<void*>(0x00AD3428);  // WowClientDB_ChrRacesRec
// CreatureDisplayInfo.m_extendedDisplayInfoID (+0x0C) -> CreatureDisplayInfoExtra,
// which holds the (race, sex, skin, face, hair...) that makes a display render as
// a gear-wearing CHARACTER. A display WITHOUT an extra is a plain creature model.
// This is how we turn "morph display id" into a doll the select screen can wear
// gear on: derive the race/appearance from the morph's OWN CDIExtra (so there's
// never any race-mixing or faction confusion — it's the morph's intended look).
static void* const g_creatureDisplayInfoDB = reinterpret_cast<void*>(0x00AD34B8); // WowClientDB_CreatureDisplayInfoRec
static void* const g_cdiExtraDB            = reinterpret_cast<void*>(0x00AD3494); // WowClientDB_CreatureDisplayInfoExtraRec
// Character-customization DBCs (RE-verified, 3.3.5a 12340). Object addresses found
// by tracing each DBC's WowClientDB vtable (GetRow @0x0065C290 at vtable slot 9) to
// its global object; record field offsets read straight from each DBC's row parser:
//   CharSections    (parser 0x008BCC20): Race@+0x04 Sex@+0x08 Section@+0x0C
//                                        VariationIndex@+0x20 ColorIndex@+0x24
//   CharHairGeosets (parser 0x008B5200): Race@+0x04 Sex@+0x08 VariationID@+0x0C
//   CharFacialHair  (parser 0x008AB4A0): Race@+0x00 Sex@+0x04 VariationID@+0x08
// Section enum: 0 base-skin, 1 face, 2 facial-hair, 3 hair, 4 underwear.
static void* const g_charSectionsDB  = reinterpret_cast<void*>(0x00AD332C);
static void* const g_charHairGeoDB   = reinterpret_cast<void*>(0x00AD3308);
static void* const g_charFacialDB    = reinterpret_cast<void*>(0x00AD3398);
// Persisted-morph reader (defined in Morpher.cpp). Reads a character's morph by
// GUID without touching live in-world state.
bool ReadMorphFileForGuid(uint64_t guid, uint32_t* outDisplay, uint32_t outItems[20]);
// Weather::GetType(this) __thiscall -> 0=none,1=rain,2=snow,3=sand. Used to know
// when a forced weather has actually been applied (so we stop re-asserting).
typedef int(__fastcall* WeatherGetType_t)(void* This, void* edx);
static WeatherGetType_t pWeatherGetType = reinterpret_cast<WeatherGetType_t>(0x00783B60);
// Per-style screen-height fields the engine animates text between (CalculateText-
// Height, 0x7E6CC0): min @ 0xAF4758+style*28, max @ 0xAF475C+style*28. Scaling
// both resizes that style's over-unit text. The table lives in .data (writable).
static float* const g_wtSizeBase = reinterpret_cast<float*>(0x00AF474C);  // record[0]
static const int    g_wtStyleStride = 28;
static const int    g_wtStyleCount  = 12;

// CGxDevice::LightSet(this, uint32 index, CGxLight* light, C3Vector* pos)  __thiscall, ret 0xC
// CGxLight: f_flags@0x00, m_dir@0x04, m_ambColor@0x10, m_dirColor@0x1C, m_specColor@0x28
typedef void(__fastcall* LightSet_t)(void* This, void* edx, uint32_t index, void* light, void* pos);
static LightSet_t oLightSet = reinterpret_cast<LightSet_t>(0x006847D0);

// ------------------------------------------------------------------
// State
// ------------------------------------------------------------------
namespace {
    // Texture swap map (normalized UPPERCASE, backslashes). Guarded by SRW lock.
    SRWLOCK g_texLock = SRWLOCK_INIT;
    std::unordered_map<std::string, std::string> g_texMap;
    volatile LONG g_texActive = 0;   // fast path: 0 = no swaps -> zero overhead

    // Live model-item texture objects (Item\ObjectComponents\...), keyed by normalized
    // real ".blp" path -> CTexture*. Populated by the LoadFromFile capture hook; consumed
    // by ReloadModelTexturesForSlot to force a clean re-decode of helmet/shoulder/cape/
    // weapon on reset (their tint is baked into the cached pixels, see oTexLoadFromFile).
    SRWLOCK g_modelTexLock = SRWLOCK_INIT;
    std::unordered_map<std::string, void*> g_modelTexByName;

    // Virtual texture tint map. Item display records can point at a synthetic BLP
    // name; the load hook resolves it to the real BLP, then tints the decoded mips.
    struct TextureTint {
        char realPath[260];
        uint8_t r, g, b;            // primary color
        int multX100;               // intensity (100 = neutral)
        bool rainbow;               // legacy flag (== mode 2)
        bool glow;                  // legacy flag (glowStr>0)
        // --- extended effect fields (Customize popup) ---
        int  mode;                  // 0 solid, 1 gradient(2-col), 2 rainbow, 3 two-region
        uint8_t r2, g2, b2;         // secondary color (gradient / two-region)
        int  dir;                   // gradient dir: 0 vertical, 1 horizontal, 2 diagonal
        int  glowStr;               // emissive add 0..255
        int  contrast;              // 0..200 (100 neutral)
        int  phase;                 // 0..255 animation phase (hue/gradient offset)
        int  rainbowSpanX100;       // rainbow tightness (100 = one full sweep across piece)
        // --- v5 post-effect color transforms (applied per-pixel after the effect
        //     color is resolved). brightness is a 0..255 scalar (128 = 1.0x);
        //     saturation is -100..+100 (0 = 1.0x, -100 = grayscale, +100 = 2x);
        //     hueShift is 0..255 (0 = no rotation, 256 = full cycle = 0). All
        //     three default to neutral so a v4->v5 in-memory upgrade is invisible.
        int  brightness;            // 0..255 (128 neutral)
        int  saturation;            // -100..100 (0 neutral)
        int  hueShift;              // 0..255 (0 neutral)
    };
    SRWLOCK g_tintLock = SRWLOCK_INIT;
    std::unordered_map<std::string, TextureTint> g_tintMap;
    volatile LONG g_tintActive = 0;
    volatile LONG g_tintSerial = 0;
    volatile LONG g_tintDbgHits = 0;

    // Particle tint (CImVector multiply). Color stored as 0..255 per channel.
    volatile LONG g_particleTintActive = 0;
    volatile LONG g_ptR = 255, g_ptG = 255, g_ptB = 255;

    // Model lighting tint (multiplies CGxLight ambient + directional colors).
    volatile LONG g_modelTintActive = 0;
    volatile LONG g_mtR = 255, g_mtG = 255, g_mtB = 255;

    // World color tint (multiplies DayNight ambient/diffuse/sky color block).
    volatile LONG g_worldTintActive = 0;
    volatile LONG g_wtR = 255, g_wtG = 255, g_wtB = 255;

    // ---- Absolute world-lighting mood (deterministic in every zone) ----
    // Unlike the multiply tint, this OVERWRITES the DayNight computed color block
    // with designed colors, so a preset looks identical regardless of zone/time.
    // ambient + diffuse + a top->horizon sky gradient, all 0..1 floats.
    SRWLOCK g_wlLock = SRWLOCK_INIT;
    volatile LONG g_wlActive = 0;
    float g_wlAmb[3]    = { 1, 1, 1 };
    float g_wlDif[3]    = { 1, 1, 1 };
    float g_wlSkyTop[3] = { 1, 1, 1 };
    float g_wlSkyHor[3] = { 1, 1, 1 };

    // World brightness: multiplies the natural (or mood) color block by a scalar.
    // The genuinely-useful, always-on-top control (replaces the old flat tint).
    volatile LONG g_brightActive = 0;
    volatile LONG g_brightX1000  = 1000;   // 1000 = 1.0x

    // Skybox override.
    volatile LONG g_skyActive = 0;
    char  g_skyName[260] = {0};
    const char* g_savedSky = nullptr;
    bool  g_skySaved = false;

    // Over-unit world-text recolor state, indexed by engine STYLE.
    //   mode 0 = solid (use col), 1 = animated rainbow gradient.
    struct WTStyle { volatile LONG enabled; volatile LONG mode; volatile LONG col; };
    WTStyle g_wt[16] = {0};
    volatile LONG g_wtActive   = 0;            // any style enabled -> hook does work
    volatile LONG g_wtGradX1000 = 250;         // rainbow speed * 1000 (cycles/sec)
    volatile LONG g_wtSeq      = 0;            // per-number counter -> spread hues across the stream
    // Per-style size scaling (writes the shared engine table; save/restore).
    volatile LONG g_wtSizeActive = 0;
    volatile LONG g_wtSizeX1000  = 1000;       // 1000 = native
    bool  g_wtSizeSaved = false, g_wtSizeWritable = false;
    float g_wtSizeOrig[16][2] = {0};           // [style] = { min, max }

    WeatherRecFake g_wRec = {0};

    // Weather override: remembered + re-asserted until the engine applies it.
    volatile LONG g_weatherActive = 0;   // 1 = an override (incl. forced-clear) is armed
    volatile LONG g_weatherType   = 0;   // desired type (0=clear,1=rain,2=snow,3=sand)
    volatile LONG g_weatherIntX1000 = 600;
    volatile LONG g_weatherAbrupt = 1;

    bool g_hooksInstalled = false;

    // Equipment retexture: original texture pointers saved per modified displayId,
    // so we can restore the in-memory ItemDisplayInfo record exactly.
    struct SavedRetex { void* di; void* orig[24]; char texFrom[2][160]; int texCount; };  // >= kRetexCount
    std::unordered_map<uint32_t, SavedRetex> g_retexSaved; // key = fromItemId

    struct SavedItemTint {
        uint32_t fromItemId = 0;
        std::vector<std::string> tintKeys;       // keys registered in g_tintMap
        std::vector<std::string> redirectKeys;   // keys registered in g_texMap
        std::vector<std::string> sfileKeys;      // keys registered in g_sfileTint (body components)
    };
    std::unordered_map<uint32_t, SavedItemTint> g_itemTintSaved; // key = equip slot id

    // --- Body-armor component tint via the SFile read layer ----------------------
    // Maps a normalized body-component BLP path (full path AND bare basename) to the
    // tint to bake into its pixels. Populated for the 8 m_texture component fields.
    std::unordered_map<std::string, TextureTint> g_sfileTint;
    SRWLOCK g_sfileLock = SRWLOCK_INIT;
    volatile LONG g_sfileActive = 0;
    // Per-open file handle state: which tint to apply + BLP layout parsed from the
    // header as the client streams the file in.
    struct BlpTintState {
        TextureTint tint;
        uint32_t offset;        // bytes delivered to the client so far
        uint8_t  hdr[0x94];     // accumulated BLP2 header (magic..mipSizes)
        int      hdrLen;
        bool     parsed;
        bool     isBlp;
        bool     loggedRead;
        bool     loggedParsed;
        bool     barber;
        char     path[260];
        uint32_t comp, alpha, width, height;
        uint32_t mipOff[16], mipSize[16];
    };
    std::unordered_map<void*, BlpTintState> g_blpHandles;
    SRWLOCK g_handleLock = SRWLOCK_INIT;
    volatile LONG g_blpTagged = 0;   // fast gate: tagged handles outstanding

    void NormalizeTexPath(const char* in, char* out, size_t outSz);   // defined below
    static bool IsVirtualComponentKey(const char* path);              // defined below
    static bool IsRecolorBlockedSourcePath(const char* normPath);     // defined below
    static bool SfileTintLookup(const char* path, TextureTint* out) {
        if (!path || !path[0]) return false;
        char norm[300]; NormalizeTexPath(path, norm, sizeof(norm));
        if (IsRecolorBlockedSourcePath(norm)) return false;
        bool found = false;
        AcquireSRWLockShared(&g_sfileLock);
        auto it = g_sfileTint.find(norm);
        if (it == g_sfileTint.end()) {
            const char* b = strrchr(norm, '\\'); b = b ? (b + 1) : norm;
            if (b[0]) { auto it2 = g_sfileTint.find(b); if (it2 != g_sfileTint.end()) { *out = it2->second; found = true; } }
        } else { *out = it->second; found = true; }
        ReleaseSRWLockShared(&g_sfileLock);
        return found;
    }
    static void SfileTintSet(const char* normKey, const TextureTint& t) {
        if (!normKey || !normKey[0]) return;
        AcquireSRWLockExclusive(&g_sfileLock);
        g_sfileTint[normKey] = t;
        InterlockedExchange(&g_sfileActive, (LONG)g_sfileTint.size());
        ReleaseSRWLockExclusive(&g_sfileLock);
    }
    static void SfileTintErase(const char* normKey) {
        if (!normKey || !normKey[0]) return;
        AcquireSRWLockExclusive(&g_sfileLock);
        g_sfileTint.erase(normKey);
        InterlockedExchange(&g_sfileActive, (LONG)g_sfileTint.size());
        ReleaseSRWLockExclusive(&g_sfileLock);
    }

    // Direct WowClientDB record fetch by id. Valid only for DBCs with unique id keys;
    // some character-customization DBCs (CharacterFacialHairStyles) are not unique-id
    // tables, so Barber iteration uses DbRecords instead.
    void* DbRecord(void* dbBase, int id) {
        __try {
            uint8_t* b = reinterpret_cast<uint8_t*>(dbBase);
            int maxId = *reinterpret_cast<int*>(b + 0x0C);
            int minId = *reinterpret_cast<int*>(b + 0x10);
            void** arr = *reinterpret_cast<void***>(b + 0x20);
            if (!arr || id < minId || id > maxId) return nullptr;
            void* rec = arr[id - minId];
            return (reinterpret_cast<uintptr_t>(rec) >= 0x10000) ? rec : nullptr;
        } __except (EXCEPTION_EXECUTE_HANDLER) { return nullptr; }
    }

    static bool DbRecords(void* dbBase, void** outRecords, int* outCount) {
        if (outRecords) *outRecords = nullptr;
        if (outCount) *outCount = 0;
        if (!dbBase || !outRecords || !outCount) return false;
        __try {
            uint8_t* b = reinterpret_cast<uint8_t*>(dbBase);
            int loaded = *reinterpret_cast<int*>(b + 0x04);
            int count = *reinterpret_cast<int*>(b + 0x08);
            void* records = *reinterpret_cast<void**>(b + 0x1C); // IDatabase::m_records
            if (!loaded || !records || reinterpret_cast<uintptr_t>(records) < 0x10000) return false;
            if (count <= 0 || count > 200000) return false;
            *outRecords = records;
            *outCount = count;
            return true;
        } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
    }

    static bool SafeReadInt(void* rec, int off, int* out) {
        if (out) *out = 0;
        if (!rec || !out || off < 0) return false;
        __try {
            *out = *reinterpret_cast<int*>(reinterpret_cast<uint8_t*>(rec) + off);
            return true;
        } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
    }

    static void AppendCsv(char* out, size_t outSz, int value, bool* first) {
        if (!out || outSz == 0 || !first) return;
        size_t used = strlen(out);
        if (used >= outSz) return;
        _snprintf_s(out + used, outSz - used, _TRUNCATE, *first ? "%d" : ",%d", value);
        *first = false;
    }

    static void WriteValueCsv(const std::vector<int>& vals, char* out, size_t outSz) {
        if (!out || outSz == 0) return;
        out[0] = 0;
        bool first = true;
        for (int v : vals) AppendCsv(out, outSz, v, &first);
    }

    static void SortUnique(std::vector<int>& vals) {
        std::sort(vals.begin(), vals.end());
        vals.erase(std::unique(vals.begin(), vals.end()), vals.end());
    }

    // Mirrors wow.exe 0x004F3A40 + 0x004F39A0. The second selector input is the
    // character class; class 6 (Death Knight) enables the DK CharSections rows.
    static int CharSectionFlagSelector(int section, int classId) {
        switch (section) {
            case 0: return (classId == 6) ? 1 : 0;
            case 1: return (classId == 6) ? 3 : 2;
            case 2: return 4;
            case 3: return (classId == 6) ? 6 : 5;
            default: return (classId == 6) ? 1 : 0;
        }
    }

    static bool CharSectionFlagsAllowed(int flags, int section, int classId) {
        int f = flags & 0xFF;
        if (section == 4) return (f & 8) == 0; // underwear overlay path checks bit 0x08 only.
        switch (CharSectionFlagSelector(section, classId)) {
            case 0: return (f & 1) != 0 && (f & 0x0C) == 0;
            case 1: return (f & 1) != 0 && (f & 0x14) != 0 && (f & 8) == 0;
            case 2: return (f & 3) != 0 && (f & 0x0C) == 0;
            case 3: return (f & 3) != 0 && (f & 0x14) != 0 && (f & 8) == 0;
            case 4: return true;
            case 5: return (f & 0x0C) == 0;
            case 6: return (f & 0x14) != 0 && (f & 8) == 0;
            default: return false;
        }
    }

    static bool CharSectionRowInfo(void* rec, int* race, int* sex, int* section,
                                   int* type, int* color, int* flags) {
        int rv = 0, sv = 0, sec = 0, typ = 0, col = 0, fl = 0;
        if (!SafeReadInt(rec, 0x04, &rv)) return false;
        if (!SafeReadInt(rec, 0x08, &sv)) return false;
        if (!SafeReadInt(rec, 0x0C, &sec)) return false;
        if (!SafeReadInt(rec, 0x1C, &fl)) return false;
        if (!SafeReadInt(rec, 0x20, &typ)) return false;
        if (!SafeReadInt(rec, 0x24, &col)) return false;
        if (race) *race = rv;
        if (sex) *sex = sv;
        if (section) *section = sec;
        if (type) *type = typ;
        if (color) *color = col;
        if (flags) *flags = fl;
        return true;
    }

    static bool CharSectionExists(int race, int sex, int classId,
                                  int section, int type, int color) {
        void* records = nullptr;
        int count = 0;
        if (!DbRecords(g_charSectionsDB, &records, &count)) return false;
        for (int i = 0; i < count; ++i) {
            void* rec = reinterpret_cast<uint8_t*>(records) + (i * 0x28);
            int rv = 0, sv = 0, sec = 0, typ = 0, col = 0, fl = 0;
            if (!CharSectionRowInfo(rec, &rv, &sv, &sec, &typ, &col, &fl)) continue;
            if (rv != race || sv != sex || sec != section || typ != type || col != color) continue;
            if (!CharSectionFlagsAllowed(fl, section, classId)) continue;
            return true;
        }
        return false;
    }

    static void CollectCharSectionValues(int race, int sex, int classId,
                                         int section,
                                         int fixedType, bool useFixedType,
                                         int fixedColor, bool useFixedColor,
                                         int valueOff, std::vector<int>& out) {
        out.clear();
        void* records = nullptr;
        int count = 0;
        if (!DbRecords(g_charSectionsDB, &records, &count)) return;
        for (int i = 0; i < count; ++i) {
            void* rec = reinterpret_cast<uint8_t*>(records) + (i * 0x28);
            int rv = 0, sv = 0, sec = 0, typ = 0, col = 0, fl = 0, val = 0;
            if (!CharSectionRowInfo(rec, &rv, &sv, &sec, &typ, &col, &fl)) continue;
            if (rv != race || sv != sex || sec != section) continue;
            if (!CharSectionFlagsAllowed(fl, section, classId)) continue;
            if (useFixedType && typ != fixedType) continue;
            if (useFixedColor && col != fixedColor) continue;
            if (!SafeReadInt(rec, valueOff, &val)) continue;
            if (val >= 0 && val <= 255) out.push_back(val);
        }
        SortUnique(out);
    }

    static void FilterValuesByCharSection(std::vector<int>& vals, int race, int sex, int classId,
                                          int section, bool valueIsType, int fixedOther) {
        vals.erase(std::remove_if(vals.begin(), vals.end(), [&](int v) {
            int typ = valueIsType ? v : fixedOther;
            int col = valueIsType ? fixedOther : v;
            return !CharSectionExists(race, sex, classId, section, typ, col);
        }), vals.end());
    }

    static void CollectBarberValuesAt(void* db, int rowSize, int race, int sex,
                                      int raceOff, int sexOff,
                                      int secOff, int wantSection,
                                      int filterOff, int filterValue,
                                      int valOff, std::vector<int>& out) {
        out.clear();
        if (!db || rowSize <= 0 || race <= 0) return;
        void* records = nullptr;
        int count = 0;
        if (!DbRecords(db, &records, &count)) return;
        for (int i = 0; i < count; ++i) {
            void* rec = reinterpret_cast<uint8_t*>(records) + (i * rowSize);
            int rv = 0, sv = 0, sec = 0, filter = 0, val = 0;
            if (!SafeReadInt(rec, raceOff, &rv) || rv != race) continue;
            if (!SafeReadInt(rec, sexOff, &sv) || sv != sex) continue;
            if (secOff >= 0 && (!SafeReadInt(rec, secOff, &sec) || sec != wantSection)) continue;
            if (filterOff >= 0 && (!SafeReadInt(rec, filterOff, &filter) || filter != filterValue)) continue;
            if (!SafeReadInt(rec, valOff, &val)) continue;
            if (val >= 0 && val <= 255) out.push_back(val);
        }
        SortUnique(out);
    }

    // ---- Barber: real per-race/gender customization counts -----------------
    // Iterate a customization DBC (via the proven GetRow id-indexed array) and,
    // for rows matching the player's race+sex, track the highest VariationIndex
    // (or ColorIndex) at `valOff`, optionally filtered to a CharSections section.
    // Returns max index + 1 = the number of valid options (0 if the table is not
    // loaded / nothing matched). secOff<0 disables the section filter.
    static int CountBarberOptionsAt(void* db, int rowSize, int race, int sex,
                                    int raceOff, int sexOff,
                                    int secOff, int wantSection, int valOff) {
        int best = -1;
        void* records = nullptr;
        int count = 0;
        if (!DbRecords(db, &records, &count)) return 0;
        for (int i = 0; i < count; ++i) {
            void* rec = reinterpret_cast<uint8_t*>(records) + (i * rowSize);
            int rv = 0, sv = 0, sec = 0, v = 0;
            if (!SafeReadInt(rec, raceOff, &rv) || rv != race) continue;
            if (!SafeReadInt(rec, sexOff, &sv) || sv != sex) continue;
            if (secOff >= 0 && (!SafeReadInt(rec, secOff, &sec) || sec != wantSection)) continue;
            if (!SafeReadInt(rec, valOff, &v)) continue;
            if (v > best) best = v;
        }
        return best + 1;   // 0-based index -> count
    }

    static int CountBarberOptions(void* db, int race, int sex,
                                  int secOff, int wantSection, int valOff) {
        return CountBarberOptionsAt(db, 0x28, race, sex, 0x04, 0x08, secOff, wantSection, valOff);
    }

    static int CountBarberOptionsFiltered(void* db, int race, int sex,
                                          int wantSection, int filterOff, int filterValue,
                                          int valOff) {
        int best = -1;
        void* records = nullptr;
        int count = 0;
        if (!DbRecords(db, &records, &count)) return 0;
        for (int i = 0; i < count; ++i) {
            void* rec = reinterpret_cast<uint8_t*>(records) + (i * 0x28);
            int rv = 0, sv = 0, sec = 0, filter = 0, v = 0;
            if (!SafeReadInt(rec, 0x04, &rv) || rv != race) continue;
            if (!SafeReadInt(rec, 0x08, &sv) || sv != sex) continue;
            if (!SafeReadInt(rec, 0x0C, &sec) || sec != wantSection) continue;
            if (filterOff >= 0 && (!SafeReadInt(rec, filterOff, &filter) || filter != filterValue)) continue;
            if (!SafeReadInt(rec, valOff, &v)) continue;
            if (v > best) best = v;
        }
        return best + 1;
    }

    void* ResolveItemRec(uint32_t itemId) {
        void* idb = reinterpret_cast<uint8_t*>(g_itemDB) + 0x18;
        __try { return pGetRecord(idb, nullptr, (int)itemId); }
        __except (EXCEPTION_EXECUTE_HANDLER) { return nullptr; }
    }
    void* ResolveDisplayInfo(uint32_t displayId) {
        void* idb = reinterpret_cast<uint8_t*>(g_itemDisplayInfoDB) + 0x18;
        __try { return pGetRecord(idb, nullptr, (int)displayId); }
        __except (EXCEPTION_EXECUTE_HANDLER) { return nullptr; }
    }
    uint32_t DisplayIdFromItem(uint32_t itemId) {
        void* rec = ResolveItemRec(itemId);
        if (!rec || reinterpret_cast<uintptr_t>(rec) < 0x10000) return 0;
        __try { return *reinterpret_cast<uint32_t*>(reinterpret_cast<uint8_t*>(rec) + 0x14); }
        __except (EXCEPTION_EXECUTE_HANDLER) { return 0; }
    }

    void NormalizeTexPath(const char* in, char* out, size_t outSz) {
        size_t i = 0;
        for (; in[i] && i + 1 < outSz; ++i) {
            char c = in[i];
            if (c == '/') c = '\\';
            else if (c >= 'a' && c <= 'z') c = (char)(c - 32);
            out[i] = c;
        }
        out[i] = '\0';
    }

    bool HasBlpExt(const char* norm) {
        if (!norm) return false;
        size_t n = strlen(norm);
        if (n < 4) return false;
        return norm[n - 4] == '.' && norm[n - 3] == 'B' && norm[n - 2] == 'L' && norm[n - 1] == 'P';
    }

    void BuildBlpPath(const char* nameOrPath, const char* defaultDir, char* out, size_t outSz) {
        if (!out || outSz == 0) return;
        out[0] = '\0';
        if (!nameOrPath || !nameOrPath[0]) return;
        const bool hasDir = strchr(nameOrPath, '\\') != nullptr || strchr(nameOrPath, '/') != nullptr;
        const bool hasExt = strrchr(nameOrPath, '.') != nullptr;
        if (hasDir) {
            if (hasExt) _snprintf_s(out, outSz, _TRUNCATE, "%s", nameOrPath);
            else _snprintf_s(out, outSz, _TRUNCATE, "%s.blp", nameOrPath);
            return;
        }
        if (!defaultDir) defaultDir = "";
        if (hasExt) _snprintf_s(out, outSz, _TRUNCATE, "%s%s", defaultDir, nameOrPath);
        else _snprintf_s(out, outSz, _TRUNCATE, "%s%s.blp", defaultDir, nameOrPath);
    }

    static bool IsRecolorBlockedSourcePath(const char* normPath) {
        if (!normPath || !normPath[0]) return false;
        // Skin/barber recolors are model texture overrides. Never let those maps rewrite
        // UI art or world/terrain source textures that happen to share a filename/key.
        return strncmp(normPath, "INTERFACE\\", 10) == 0 ||
               strncmp(normPath, "WORLD\\", 6) == 0;
    }

    int BuildTextureLookupKeys(const char* norm, char keys[][300], int maxKeys) {
        if (!norm || !norm[0] || !keys || maxKeys <= 0) return 0;
        int n = 0;
        strncpy_s(keys[n++], 300, norm, _TRUNCATE);
        const bool hasBlp = HasBlpExt(norm);
        const bool hasDir = strchr(norm, '\\') != nullptr;
        const bool allowBaseKeys = !hasDir;
        if (!hasBlp && n < maxKeys) {
            _snprintf_s(keys[n++], 300, _TRUNCATE, "%s.BLP", norm);
        }
        // Basename keys are only safe when the client itself supplied a bare name.
        // Letting full paths fall back to a basename caused item tint redirects to
        // recolor unrelated UI/world textures that happened to share a filename.
        const char* base = strrchr(norm, '\\');
        base = base ? (base + 1) : norm;
        if (allowBaseKeys && base && base[0]) {
            if (n < maxKeys) strncpy_s(keys[n++], 300, base, _TRUNCATE);
            if (n < maxKeys && !HasBlpExt(base)) _snprintf_s(keys[n++], 300, _TRUNCATE, "%s.BLP", base);
            if (n < maxKeys) {
                char noExt[300]; strncpy_s(noExt, sizeof(noExt), base, _TRUNCATE);
                char* dot = strrchr(noExt, '.'); if (dot) *dot = 0;
                if (noExt[0]) strncpy_s(keys[n++], 300, noExt, _TRUNCATE);
            }
        }
        if (!hasDir) {
            if (n < maxKeys) _snprintf_s(keys[n++], 300, _TRUNCATE, "ITEM\\OBJECTCOMPONENTS\\WEAPON\\%s", norm);
            if (n < maxKeys && !hasBlp) _snprintf_s(keys[n++], 300, _TRUNCATE, "ITEM\\OBJECTCOMPONENTS\\WEAPON\\%s.BLP", norm);
            if (n < maxKeys) _snprintf_s(keys[n++], 300, _TRUNCATE, "ITEM\\OBJECTCOMPONENTS\\SHIELD\\%s", norm);
            if (n < maxKeys && !hasBlp) _snprintf_s(keys[n++], 300, _TRUNCATE, "ITEM\\OBJECTCOMPONENTS\\SHIELD\\%s.BLP", norm);
        }
        return n;
    }

    bool TryGetTintForFilename(const char* filename, TextureTint* outTint, char* outNorm, size_t outNormSz) {
        if (!filename || !filename[0] || !outTint) return false;
        char norm[300];
        NormalizeTexPath(filename, norm, sizeof(norm));
        if (IsRecolorBlockedSourcePath(norm)) return false;
        if (outNorm && outNormSz > 0) strncpy_s(outNorm, outNormSz, norm, _TRUNCATE);
        char keys[16][300];
        int k = BuildTextureLookupKeys(norm, keys, 16);
        bool found = false;
        AcquireSRWLockShared(&g_tintLock);
        for (int i = 0; i < k; ++i) {
            auto it = g_tintMap.find(keys[i]);
            if (it != g_tintMap.end()) {
                *outTint = it->second;
                found = true;
                break;
            }
        }
        ReleaseSRWLockShared(&g_tintLock);
        return found;
    }

    bool FindTexRedirect(const char* filename, char* outRepl, size_t outSz) {
        if (!filename || !filename[0] || !outRepl || outSz == 0) return false;
        char norm[300];
        NormalizeTexPath(filename, norm, sizeof(norm));
        if (IsRecolorBlockedSourcePath(norm)) return false;
        char keys[16][300];
        int k = BuildTextureLookupKeys(norm, keys, 16);
        bool found = false;
        AcquireSRWLockShared(&g_texLock);
        for (int i = 0; i < k; ++i) {
            auto it = g_texMap.find(keys[i]);
            if (it != g_texMap.end()) {
                strncpy_s(outRepl, outSz, it->second.c_str(), _TRUNCATE);
                found = true;
                break;
            }
        }
        ReleaseSRWLockShared(&g_texLock);
        return found;
    }

    // Multiply a CImVector (BGRA in a uint32) by the active tint, preserving alpha.
    inline uint32_t TintCImVector(uint32_t c) {
        uint32_t b = (c) & 0xFF;
        uint32_t g = (c >> 8) & 0xFF;
        uint32_t r = (c >> 16) & 0xFF;
        uint32_t a = (c >> 24) & 0xFF;
        b = (b * (uint32_t)g_ptB) / 255;
        g = (g * (uint32_t)g_ptG) / 255;
        r = (r * (uint32_t)g_ptR) / 255;
        return (a << 24) | (r << 16) | (g << 8) | b;
    }

    struct C4PixelLocal { uint8_t b, g, r, a; };
    struct MipBitsLocal { C4PixelLocal* mip[1]; };

    inline uint8_t ClampByteInt(int v) {
        if (v < 0) return 0;
        if (v > 255) return 255;
        return (uint8_t)v;
    }

    void HsvToRgbBytes(float h, uint8_t* outR, uint8_t* outG, uint8_t* outB) {
        h -= (float)(int)h;
        if (h < 0.0f) h += 1.0f;
        float r = 0.0f, g = 0.0f, b = 0.0f;
        float x = h * 6.0f;
        int i = (int)x;
        float f = x - (float)i;
        switch (i % 6) {
            case 0: r = 1.0f;     g = f;        b = 0.0f;     break;
            case 1: r = 1.0f - f; g = 1.0f;     b = 0.0f;     break;
            case 2: r = 0.0f;     g = 1.0f;     b = f;        break;
            case 3: r = 0.0f;     g = 1.0f - f; b = 1.0f;     break;
            case 4: r = f;        g = 0.0f;     b = 1.0f;     break;
            default:r = 1.0f;     g = 0.0f;     b = 1.0f - f; break;
        }
        *outR = (uint8_t)(r * 255.0f + 0.5f);
        *outG = (uint8_t)(g * 255.0f + 0.5f);
        *outB = (uint8_t)(b * 255.0f + 0.5f);
    }

    // Map a 0..1 position to the effect's color, independent of WHERE the position
    // comes from (spatial XY for model items, luminance for body components). phase
    // (0..1) animates gradients/rainbow for the slow cycle.
    inline void TintColorAtPos(const TextureTint& t, float pos,
                               uint8_t* tr, uint8_t* tg, uint8_t* tb) {
        const float phase = (float)t.phase / 256.0f;
        const int mode = t.mode;
        if (mode == 2 || (mode == 0 && t.rainbow)) {            // rainbow / RGB sweep
            float span = (t.rainbowSpanX100 > 0) ? (float)t.rainbowSpanX100 / 100.0f : 1.0f;
            HsvToRgbBytes(pos * span + phase, tr, tg, tb);
            return;
        }
        if (mode == 1 || mode == 3) {                            // gradient / two-region
            float p = pos + phase; p -= (float)(int)p;
            float f = (mode == 3) ? ((p < 0.5f) ? 0.0f : 1.0f)   // hard split (two-tone)
                                  : ((p < 0.5f) ? (p * 2.0f)     // smooth gradient (ping-pong)
                                                : (2.0f - p * 2.0f));
            *tr = (uint8_t)((int)t.r + (int)(((int)t.r2 - (int)t.r) * f));
            *tg = (uint8_t)((int)t.g + (int)(((int)t.g2 - (int)t.g) * f));
            *tb = (uint8_t)((int)t.b + (int)(((int)t.b2 - (int)t.b) * f));
            return;
        }
        *tr = t.r; *tg = t.g; *tb = t.b;                         // solid
    }

    // Per-pixel target color for the active effect mode. x,y are pixel coords in a
    // mip of size w x h. The gradient/rainbow runs along the chosen direction.
    inline void TintColorForPixel(const TextureTint& t, uint32_t x, uint32_t y, uint32_t w, uint32_t h,
                                  uint8_t* tr, uint8_t* tg, uint8_t* tb) {
        const float fx = (w > 1) ? ((float)x / (float)(w - 1)) : 0.0f;
        const float fy = (h > 1) ? ((float)y / (float)(h - 1)) : 0.0f;
        const float pos = (t.dir == 1) ? fx : (t.dir == 2 ? (fx + fy) * 0.5f : fy);
        TintColorAtPos(t, pos, tr, tg, tb);
    }

    // Combine a source pixel (*r,*g,*b) with an already-resolved effect color
    // (tr,tg,tb): multiply (intensity), contrast and emissive glow, then apply the
    // v5 post-effect color transforms (brightness, saturation, hue shift). Shared
    // by the spatial and palette-index entry points so every BLP format tints
    // identically.
    inline void ApplyTintRgbTarget(uint8_t* r, uint8_t* g, uint8_t* b, const TextureTint& t,
                                   uint8_t tr, uint8_t tg, uint8_t tb) {
        int mult = t.multX100; if (mult < 0) mult = 0; if (mult > 400) mult = 400;
        int rr = ((int)(*r) * (int)tr * mult) / (255 * 100);
        int gg = ((int)(*g) * (int)tg * mult) / (255 * 100);
        int bb = ((int)(*b) * (int)tb * mult) / (255 * 100);
        int ct = (t.contrast > 0) ? t.contrast : 100;            // contrast around mid-grey
        if (ct != 100) {
            rr = 128 + ((rr - 128) * ct) / 100;
            gg = 128 + ((gg - 128) * ct) / 100;
            bb = 128 + ((bb - 128) * ct) / 100;
        }
        int gs = t.glowStr; if (gs <= 0 && t.glow) gs = 36;      // emissive add
        if (gs > 0) { rr += ((int)tr * gs) / 255; gg += ((int)tg * gs) / 255; bb += ((int)tb * gs) / 255; }
        // --- v5 post-effects (order matters: brightness first scales magnitude,
        //     then saturation re-weights chroma around luminance, then hueShift
        //     rotates the resulting color in HSV space) ---
        if (t.brightness != 128) {
            int br = t.brightness; if (br < 0) br = 0; if (br > 255) br = 255;
            rr = (rr * br) / 128; if (rr > 255) rr = 255;
            gg = (gg * br) / 128; if (gg > 255) gg = 255;
            bb = (bb * br) / 128; if (bb > 255) bb = 255;
        }
        if (t.saturation != 0) {
            int sat = t.saturation; if (sat < -100) sat = -100; if (sat > 100) sat = 100;
            int lum = (rr * 299 + gg * 587 + bb * 114) / 1000;
            rr = lum + ((rr - lum) * (100 + sat)) / 100;
            gg = lum + ((gg - lum) * (100 + sat)) / 100;
            bb = lum + ((bb - lum) * (100 + sat)) / 100;
            if (rr < 0) rr = 0; if (rr > 255) rr = 255;
            if (gg < 0) gg = 0; if (gg > 255) gg = 255;
            if (bb < 0) bb = 0; if (bb > 255) bb = 255;
        }
        if (t.hueShift != 0) {
            // RGB -> HSV -> shift H -> RGB. hueShift of 256 = 1 full cycle = 0.
            float rf = rr / 255.0f, gf = gg / 255.0f, bf = bb / 255.0f;
            float mx = rf; if (gf > mx) mx = gf; if (bf > mx) mx = bf;
            float mn = rf; if (gf < mn) mn = gf; if (bf < mn) mn = bf;
            float d  = mx - mn;
            float h = 0.0f, s = (mx > 0.0001f) ? (d / mx) : 0.0f;
            if (d > 0.0001f) {
                if (mx == rf)      h = ((gf - bf) / d) + (gf < bf ? 6.0f : 0.0f);
                else if (mx == gf) h = ((bf - rf) / d) + 2.0f;
                else               h = ((rf - gf) / d) + 4.0f;
                h /= 6.0f;
            }
            int hue = t.hueShift & 0xFF;
            h += (float)hue / 256.0f;
            h -= (float)(int)h;
            float hp = h * 6.0f;
            int   i  = (int)hp;
            float f  = hp - (float)i;
            float p  = mx * (1.0f - s);
            float q  = mx * (1.0f - s * f);
            float tt = mx * (1.0f - s * (1.0f - f));
            switch (i % 6) {
                case 0: rf = mx; gf = tt; bf = p;  break;
                case 1: rf = q;  gf = mx; bf = p;  break;
                case 2: rf = p;  gf = mx; bf = tt; break;
                case 3: rf = p;  gf = q;  bf = mx; break;
                case 4: rf = tt; gf = p;  bf = mx; break;
                default:rf = mx; gf = p;  bf = q;  break;
            }
            rr = (int)(rf * 255.0f + 0.5f); if (rr > 255) rr = 255;
            gg = (int)(gf * 255.0f + 0.5f); if (gg > 255) gg = 255;
            bb = (int)(bf * 255.0f + 0.5f); if (bb > 255) bb = 255;
        }
        *r = ClampByteInt(rr); *g = ClampByteInt(gg); *b = ClampByteInt(bb);
    }

    // Spatial entry point: effect position from pixel XY (model items, DXT/BGRA armor).
    inline void ApplyTintRgb(uint8_t* r, uint8_t* g, uint8_t* b, const TextureTint& t,
                             uint32_t x, uint32_t y, uint32_t w, uint32_t h) {
        uint8_t tr = 255, tg = 255, tb = 255;
        TintColorForPixel(t, x, y, w, h, &tr, &tg, &tb);
        ApplyTintRgbTarget(r, g, b, t, tr, tg, tb);
    }

    // Explicit-position entry point: used by the palettized path, where pixels have no
    // XY (the engine stores 1-byte indices into a 256-color table). We spread the effect
    // across the palette index so a rainbow/gradient covers the FULL color range instead
    // of collapsing to color1 (the "non-reskinned body part is one flat color" bug —
    // those originals are palettized BLPs; reskinned slots load DXT donors and were fine).
    inline void ApplyTintRgbPos(uint8_t* r, uint8_t* g, uint8_t* b, const TextureTint& t, float pos) {
        uint8_t tr = 255, tg = 255, tb = 255;
        TintColorAtPos(t, pos, &tr, &tg, &tb);
        ApplyTintRgbTarget(r, g, b, t, tr, tg, tb);
    }

    inline void Unpack565(uint16_t c, uint8_t* r, uint8_t* g, uint8_t* b) {
        *r = (uint8_t)((((c >> 11) & 0x1F) * 255) / 31);
        *g = (uint8_t)((((c >> 5)  & 0x3F) * 255) / 63);
        *b = (uint8_t)((( c        & 0x1F) * 255) / 31);
    }
    inline uint16_t Pack565(uint8_t r, uint8_t g, uint8_t b) {
        return (uint16_t)((((uint16_t)r * 31 / 255) << 11) |
                          (((uint16_t)g * 63 / 255) << 5) |
                           ((uint16_t)b * 31 / 255));
    }
    inline void Tint565Word(uint8_t* p, const TextureTint& t, uint32_t x, uint32_t y, uint32_t w, uint32_t h) {
        uint16_t c = (uint16_t)(p[0] | (p[1] << 8));
        uint8_t r, g, b;
        Unpack565(c, &r, &g, &b);
        ApplyTintRgb(&r, &g, &b, t, x, y, w, h);
        c = Pack565(r, g, b);
        p[0] = (uint8_t)(c & 0xFF);
        p[1] = (uint8_t)(c >> 8);
    }

    void TintArgb8888(C4PixelLocal* pixels, uint32_t w, uint32_t h, const TextureTint& t) {
        for (uint32_t y = 0; y < h; ++y) {
            for (uint32_t x = 0; x < w; ++x) {
                C4PixelLocal& p = pixels[(size_t)y * w + x];
                if (p.a == 0) continue;
                uint8_t r = p.r, g = p.g, b = p.b;
                ApplyTintRgb(&r, &g, &b, t, x, y, w, h);
                p.r = r; p.g = g; p.b = b;
            }
        }
    }

    void TintRgb565(uint8_t* data, uint32_t w, uint32_t h, const TextureTint& t) {
        for (uint32_t y = 0; y < h; ++y) {
            for (uint32_t x = 0; x < w; ++x) Tint565Word(data + ((size_t)y * w + x) * 2, t, x, y, w, h);
        }
    }

    void TintArgb1555(uint8_t* data, uint32_t w, uint32_t h, const TextureTint& t) {
        for (uint32_t y = 0; y < h; ++y) {
            for (uint32_t x = 0; x < w; ++x) {
                uint8_t* p = data + ((size_t)y * w + x) * 2;
                uint16_t c = (uint16_t)(p[0] | (p[1] << 8));
                uint8_t r = (uint8_t)((((c >> 10) & 0x1F) * 255) / 31);
                uint8_t g = (uint8_t)((((c >> 5)  & 0x1F) * 255) / 31);
                uint8_t b = (uint8_t)((( c        & 0x1F) * 255) / 31);
                ApplyTintRgb(&r, &g, &b, t, x, y, w, h);
                c = (uint16_t)((c & 0x8000) | (((uint16_t)r * 31 / 255) << 10) |
                               (((uint16_t)g * 31 / 255) << 5) | ((uint16_t)b * 31 / 255));
                p[0] = (uint8_t)(c & 0xFF); p[1] = (uint8_t)(c >> 8);
            }
        }
    }

    void TintArgb4444(uint8_t* data, uint32_t w, uint32_t h, const TextureTint& t) {
        for (uint32_t y = 0; y < h; ++y) {
            for (uint32_t x = 0; x < w; ++x) {
                uint8_t* p = data + ((size_t)y * w + x) * 2;
                uint16_t c = (uint16_t)(p[0] | (p[1] << 8));
                uint8_t r = (uint8_t)((((c >> 8) & 0x0F) * 255) / 15);
                uint8_t g = (uint8_t)((((c >> 4) & 0x0F) * 255) / 15);
                uint8_t b = (uint8_t)((( c       & 0x0F) * 255) / 15);
                ApplyTintRgb(&r, &g, &b, t, x, y, w, h);
                c = (uint16_t)((c & 0xF000) | (((uint16_t)r * 15 / 255) << 8) |
                               (((uint16_t)g * 15 / 255) << 4) | ((uint16_t)b * 15 / 255));
                p[0] = (uint8_t)(c & 0xFF); p[1] = (uint8_t)(c >> 8);
            }
        }
    }

    void TintDxt(uint8_t* data, uint32_t w, uint32_t h, int fmt, const TextureTint& t) {
        const uint32_t bw = (w + 3) / 4;
        const uint32_t bh = (h + 3) / 4;
        const uint32_t blockSize = (fmt == 0) ? 8 : 16; // DXT1=0, DXT3=1, DXT5=7
        const uint32_t colorOff = (fmt == 0) ? 0 : 8;
        for (uint32_t by = 0; by < bh; ++by) {
            for (uint32_t bx = 0; bx < bw; ++bx) {
                uint8_t* color = data + ((size_t)by * bw + bx) * blockSize + colorOff;
                uint32_t px = bx * 4;
                uint32_t py = by * 4;
                Tint565Word(color,     t, px, py, w, h);
                Tint565Word(color + 2, t, px, py, w, h);
            }
        }
    }

    void ApplyTextureTint(void* image, uint32_t width, uint32_t height, int dataFormat, const TextureTint& t) {
        if (!image || width == 0 || height == 0) return;
        MipBitsLocal* mips = reinterpret_cast<MipBitsLocal*>(image);
        uint32_t w = width, h = height;
        __try {
            for (int level = 0; level < 16; ++level) {
                uint8_t* data = reinterpret_cast<uint8_t*>(mips->mip[level]);
                if (!data) break;
                switch (dataFormat) {
                    case 0: TintDxt(data, w, h, 0, t); break;                         // PIXEL_DXT1
                    case 1: TintDxt(data, w, h, 1, t); break;                         // PIXEL_DXT3
                    case 2: TintArgb8888(reinterpret_cast<C4PixelLocal*>(data), w, h, t); break;
                    case 3: TintArgb1555(data, w, h, t); break;
                    case 4: TintArgb4444(data, w, h, t); break;
                    case 5: TintRgb565(data, w, h, t); break;
                    case 7: TintDxt(data, w, h, 7, t); break;                         // PIXEL_DXT5
                    default: return;
                }
                if (w == 1 && h == 1) break;
                if (w > 1) w >>= 1;
                if (h > 1) h >>= 1;
            }
        } __except (EXCEPTION_EXECUTE_HANDLER) {
            Log("[ColorEngine] texture tint exception (format=%d %ux%u)", dataFormat, width, height);
        }
    }

    // ===========================================================================
    // Body-armor component tint at the SFile read layer.
    // Tints whole DXT blocks / BGRA pixels / palette entries of a BLP that fall
    // inside the byte range [start, start+n) the client just read into `buf`.
    // Works incrementally across multiple reads; only ever touches fully-contained
    // blocks/pixels so a chunk boundary can never corrupt the file.
    // ===========================================================================
    static void TintDxtRange(uint8_t* p, uint32_t bytes, int fmt, uint32_t mipW, uint32_t mipH,
                             uint32_t firstBlockIndex, const TextureTint& t) {
        const uint32_t blockSize = (fmt == 0) ? 8 : 16;   // DXT1=0 (8B), DXT3=1/DXT5=7 (16B)
        const uint32_t colorOff  = (fmt == 0) ? 0 : 8;
        const uint32_t bw = (mipW + 3) / 4; if (!bw) return;
        uint32_t nblocks = bytes / blockSize;
        for (uint32_t i = 0; i < nblocks; ++i) {
            uint8_t* color = p + (size_t)i * blockSize + colorOff;
            uint32_t bidx = firstBlockIndex + i;
            uint32_t px = (bidx % bw) * 4, py = (bidx / bw) * 4;
            Tint565Word(color,     t, px, py, mipW, mipH);
            Tint565Word(color + 2, t, px, py, mipW, mipH);
        }
    }
    static void TintBgraRange(uint8_t* p, uint32_t bytes, uint32_t mipW, uint32_t mipH,
                              uint32_t firstPixelIndex, const TextureTint& t) {
        const uint32_t w = mipW ? mipW : 1;
        uint32_t npx = bytes / 4;
        for (uint32_t i = 0; i < npx; ++i) {
            C4PixelLocal* px = reinterpret_cast<C4PixelLocal*>(p + (size_t)i * 4);
            if (px->a == 0) continue;
            uint32_t idx = firstPixelIndex + i;
            uint8_t r = px->r, g = px->g, b = px->b;
            ApplyTintRgb(&r, &g, &b, t, idx % w, idx / w, w, mipH ? mipH : 1);
            px->r = r; px->g = g; px->b = b;
        }
    }
    // firstIndex/total give each entry its ABSOLUTE position in the 256-color palette
    // (the palette can stream across several reads), so the effect spreads coherently.
    static void TintPaletteRange(uint8_t* p, uint32_t bytes, uint32_t firstIndex,
                                 uint32_t total, const TextureTint& t) {
        uint32_t n = bytes / 4;                 // palette entries are BGRA
        const uint32_t denom = (total > 1) ? (total - 1) : 1;
        for (uint32_t i = 0; i < n; ++i) {
            uint8_t* e = p + (size_t)i * 4;
            uint8_t r = e[2], g = e[1], b = e[0];
            // A palette has no XY axis, so spread the effect across the palette index.
            // "Direction" still does something universal: Vert = ascending index, Horiz =
            // reversed, Diag = interleaved — so every effect option (incl. direction) is
            // live on the SFile path, matching the spatial (decode) path's option set.
            const uint32_t idx = firstIndex + i;
            float u = (float)idx / (float)denom;
            float pos = (t.dir == 1) ? (1.0f - u)
                      : (t.dir == 2) ? ((float)((idx * 2u) % total) / (float)denom)
                                     : u;
            ApplyTintRgbPos(&r, &g, &b, t, pos);
            e[2] = r; e[1] = g; e[0] = b;
        }
    }

    static void ParseBlpHeader(BlpTintState& s) {
        if (s.hdrLen < 0x94) return;
        if (memcmp(s.hdr, "BLP2", 4) != 0) { s.isBlp = false; s.parsed = true; return; }
        s.comp   = s.hdr[8];           // 1=palette, 2=DXT, 3=uncompressed BGRA
        s.alpha  = s.hdr[9];
        uint32_t alphaType = s.hdr[10];// for DXT: 0=DXT1, 1=DXT3, 7=DXT5
        s.width  = *reinterpret_cast<uint32_t*>(s.hdr + 0x0C);
        s.height = *reinterpret_cast<uint32_t*>(s.hdr + 0x10);
        for (int i = 0; i < 16; ++i) {
            s.mipOff[i]  = *reinterpret_cast<uint32_t*>(s.hdr + 0x14 + i * 4);
            s.mipSize[i] = *reinterpret_cast<uint32_t*>(s.hdr + 0x54 + i * 4);
        }
        if (s.width == 0 || s.height == 0 || s.width > 8192 || s.height > 8192) {
            s.isBlp = false; s.parsed = true; return;
        }
        s.alpha = alphaType;           // reuse field to carry DXT subtype
        s.isBlp = true; s.parsed = true;
    }

    // Apply the tint to the part of [start, start+n) sitting in `buf`.
    static void ProcessBlpRead(BlpTintState& s, uint8_t* buf, uint32_t start, uint32_t n) {
        if (!s.parsed || !s.isBlp || n == 0) return;
        __try {
            const uint64_t readStart = start;
            const uint64_t readEnd = readStart + n;
            if (s.comp == 1) {
                // Palettized: tint the 256-entry BGRA palette at 0x94.
                const uint64_t pStart = 0x94, pEnd = 0x94 + 256 * 4;
                uint64_t lo = (readStart > pStart) ? readStart : pStart;
                uint64_t hi = (readEnd < pEnd) ? readEnd : pEnd;
                if (lo < hi) {
                    uint32_t a = (uint32_t)((lo - readStart) & ~3ull), b = (uint32_t)((hi - readStart) & ~3ull);
                    if (b > a) {
                        uint32_t firstIdx = (uint32_t)((readStart + a - pStart) / 4);  // absolute palette index
                        TintPaletteRange(buf + a, b - a, firstIdx, 256, s.tint);
                    }
                }
                return;
            }
            int dxt = -1;
            if (s.comp == 2) dxt = (s.alpha == 0) ? 0 : (s.alpha == 1 ? 1 : 7);
            for (int i = 0; i < 16; ++i) {
                uint32_t off = s.mipOff[i], sz = s.mipSize[i];
                if (!off || !sz) continue;
                uint64_t mEnd = (uint64_t)off + (uint64_t)sz;
                if (mEnd <= off) continue;
                uint64_t lo = (readStart > off) ? readStart : (uint64_t)off;
                uint64_t hi = (readEnd < mEnd) ? readEnd : mEnd;
                if (lo >= hi) continue;
                uint32_t mipW = s.width >> i; if (!mipW) mipW = 1;
                uint32_t mipH = s.height >> i; if (!mipH) mipH = 1;
                uint8_t* base = buf + (uint32_t)(lo - readStart);
                uint32_t rel = (uint32_t)(lo - off);                       // bytes into the mip
                if (dxt >= 0) {
                    uint32_t blockSize = (dxt == 0) ? 8u : 16u;
                    uint32_t firstBlk = (rel + blockSize - 1) / blockSize;   // first whole block at/after lo
                    uint32_t skip = firstBlk * blockSize - rel;
                    uint32_t span = (uint32_t)(hi - lo);
                    if (skip < span) TintDxtRange(base + skip, span - skip, dxt, mipW, mipH, firstBlk, s.tint);
                } else if (s.comp == 3) {
                    uint32_t firstPx = (rel + 3) / 4;
                    uint32_t skip = firstPx * 4 - rel;
                    uint32_t span = (uint32_t)(hi - lo);
                    if (skip < span) TintBgraRange(base + skip, span - skip, mipW, mipH, firstPx, s.tint);
                }
            }
        } __except (EXCEPTION_EXECUTE_HANDLER) {}
    }

    // --- Diagnostic texture-request log ----------------------------------------
    // The "Skin" recolor works for separate-model items (weapon/shield/helm/shoulder)
    // but not for body-composite armor, because those load their BLPs through a
    // different path. To pin down the EXACT filename the client requests for the
    // broken slots, this logs every load whose path is a body component
    // (Item\TextureComponents\...) or a model-item component (Item\ObjectComponents\...),
    // tagged by which hook saw it. Capped so it can't run away. Toggle with the
    // DIAGTEX:<0/1> command; OFF by default so the skin/texture path is quiet. Turn it
    // on only when actively debugging skins (it logs every texture load + every skin
    // register/reset and floods the log otherwise).
    volatile LONG g_diagTexOn   = 0;
    volatile LONG g_diagTexHits = 0;
    static bool ContainsCI(const char* hay, const char* needleUpper) {
        if (!hay) return false;
        for (const char* p = hay; *p; ++p) {
            const char* h = p; const char* n = needleUpper;
            while (*n && *h) {
                char c = *h; if (c >= 'a' && c <= 'z') c = (char)(c - 32);
                if (c != *n) break;
                ++h; ++n;
            }
            if (!*n) return true;
        }
        return false;
    }
    static bool IsCharacterTexPath(const char* normPath) {
        return normPath && strncmp(normPath, "CHARACTER\\", 10) == 0;
    }
    static const char* CharacterRaceDir(int race) {
        switch (race) {
            case 1: return "HUMAN";
            case 2: return "ORC";
            case 3: return "DWARF";
            case 4: return "NIGHTELF";
            case 5: return "SCOURGE";
            case 6: return "TAUREN";
            case 7: return "GNOME";
            case 8: return "TROLL";
            case 10: return "BLOODELF";
            case 11: return "DRAENEI";
            default: return nullptr;
        }
    }
    static const char* CharacterSexDir(int sex) {
        return (sex == 1) ? "FEMALE" : "MALE";
    }
    static bool IsTintVirtualKey(const char* path) { return ContainsCI(path, "TM_CTINT_"); }
    static bool IsCleanVirtualKey(const char* path) { return ContainsCI(path, "TM_CLEAN_"); }
    static bool IsVirtualComponentKey(const char* path) {
        return IsTintVirtualKey(path) || IsCleanVirtualKey(path);
    }

    struct BarberPathMatcher {
        int region = -1;
        std::string norm;
        std::string noExt;
        std::string baseNoExt;
        TextureTint tint = {};
    };
    struct BarberDynamicKeys {
        std::vector<std::string> redirectKeys;
        std::vector<std::string> tintKeys;
        std::vector<std::string> sfileKeys;
    };
    SRWLOCK g_barberPathLock = SRWLOCK_INIT;
    std::vector<BarberPathMatcher> g_barberPathMatchers;
    BarberDynamicKeys g_barberDynamicKeys[4];
    volatile LONG g_barberPathActive = 0;
    static void StripBlpExt(char* s) {
        if (!s) return;
        size_t n = strlen(s);
        if (n >= 4 && s[n - 4] == '.' && s[n - 3] == 'B' && s[n - 2] == 'L' && s[n - 1] == 'P') {
            s[n - 4] = 0;
        }
    }

    static void BarberEraseRedirectKey(const std::string& k) {
        if (k.empty()) return;
        AcquireSRWLockExclusive(&g_texLock);
        g_texMap.erase(k);
        InterlockedExchange(&g_texActive, (LONG)g_texMap.size());
        ReleaseSRWLockExclusive(&g_texLock);
    }
    static void BarberEraseTintKey(const std::string& k) {
        if (k.empty()) return;
        AcquireSRWLockExclusive(&g_tintLock);
        g_tintMap.erase(k);
        InterlockedExchange(&g_tintActive, (LONG)g_tintMap.size());
        ReleaseSRWLockExclusive(&g_tintLock);
    }
    static void BarberEraseSfileKey(const std::string& k) {
        if (k.empty()) return;
        AcquireSRWLockExclusive(&g_sfileLock);
        g_sfileTint.erase(k);
        InterlockedExchange(&g_sfileActive, (LONG)g_sfileTint.size());
        ReleaseSRWLockExclusive(&g_sfileLock);
    }

    static void BarberClearPathRegion(int region) {
        if (region < 0 || region > 3) return;
        BarberDynamicKeys dyn;
        AcquireSRWLockExclusive(&g_barberPathLock);
        for (auto it = g_barberPathMatchers.begin(); it != g_barberPathMatchers.end(); ) {
            if (it->region == region) it = g_barberPathMatchers.erase(it);
            else ++it;
        }
        dyn = std::move(g_barberDynamicKeys[region]);
        g_barberDynamicKeys[region] = BarberDynamicKeys{};
        InterlockedExchange(&g_barberPathActive, (LONG)g_barberPathMatchers.size());
        ReleaseSRWLockExclusive(&g_barberPathLock);

        for (const auto& k : dyn.redirectKeys) {
            if (!IsVirtualComponentKey(k.c_str())) BarberEraseRedirectKey(k);
        }
        for (const auto& k : dyn.tintKeys)  BarberEraseTintKey(k);
        for (const auto& k : dyn.sfileKeys) BarberEraseSfileKey(k);
    }

    static void BarberAddPathMatcher(int region, const char* rawName, const TextureTint& tint) {
        if (region < 0 || region > 3 || !rawName || !rawName[0]) return;
        char norm[300]; NormalizeTexPath(rawName, norm, sizeof(norm));
        if (!norm[0]) return;
        char noExt[300]; strncpy_s(noExt, sizeof(noExt), norm, _TRUNCATE); StripBlpExt(noExt);
        const char* base = strrchr(noExt, '\\'); base = base ? base + 1 : noExt;
        if (!base[0]) return;

        BarberPathMatcher m;
        m.region = region;
        m.norm = norm;
        m.noExt = noExt;
        m.baseNoExt = base;
        m.tint = tint;

        AcquireSRWLockExclusive(&g_barberPathLock);
        g_barberPathMatchers.emplace_back(std::move(m));
        InterlockedExchange(&g_barberPathActive, (LONG)g_barberPathMatchers.size());
        ReleaseSRWLockExclusive(&g_barberPathLock);
    }

    static bool BarberMatcherHits(const BarberPathMatcher& m, const char* norm, const char* noExt, const char* baseNoExt) {
        if (!norm || !noExt || !baseNoExt) return false;
        // EXACT full-path match ONLY (with or without the .BLP extension). No basename, no
        // substring, no suffix: anything looser lets a texture that merely shares a filename
        // (or fragment) get tinted, which is how the recolor "leaked" onto clothing/weapons.
        // A CharSections skin/hair texture is identified by its COMPLETE path and nothing else.
        (void)baseNoExt;
        if (!m.norm.empty()  && _stricmp(norm,  m.norm.c_str())  == 0) return true;
        if (!m.noExt.empty() && _stricmp(noExt, m.noExt.c_str()) == 0) return true;
        return false;
    }

    static bool BarberRouteCompositePath(const char* path, char* outPath, size_t outSz) {
        if (!g_barberPathActive || !path || !path[0] || !outPath || outSz == 0 || g_isProcessTerminating) return false;
        char norm[300]; NormalizeTexPath(path, norm, sizeof(norm));
        if (!norm[0] || IsVirtualComponentKey(norm)) return false;
        // Hard gate: barber ONLY recolors the player's body/skin/hair, whose textures all
        // live under "CHARACTER\". Item textures (weapons, armor TextureComponents, capes,
        // helms) live under "ITEM\" and must never be routed here. Require the CHARACTER
        // prefix before any matcher runs so the extra skin overlay cannot leak to gear.
        if (!IsCharacterTexPath(norm)) return false;
        char noExt[300]; strncpy_s(noExt, sizeof(noExt), norm, _TRUNCATE); StripBlpExt(noExt);
        const char* base = strrchr(noExt, '\\'); base = base ? base + 1 : noExt;

        TextureTint tint = {};
        int region = -1;
        bool found = false;
        AcquireSRWLockShared(&g_barberPathLock);
        for (const auto& m : g_barberPathMatchers) {
            if (BarberMatcherHits(m, norm, noExt, base)) {
                tint = m.tint;
                region = m.region;
                found = true;
                break;
            }
        }
        ReleaseSRWLockShared(&g_barberPathLock);
        if (!found || region < 0 || region > 3) return false;

        LONG serial = InterlockedIncrement(&g_tintSerial);
        char virt[260], normVirt[260];
        _snprintf_s(virt, sizeof(virt), _TRUNCATE, "TM_CTINT_BARBER_LIVE_R%d_%ld.blp", region, serial);
        NormalizeTexPath(virt, normVirt, sizeof(normVirt));
        if (!normVirt[0]) return false;

        TextureTint decodeTint = tint;
        strncpy_s(decodeTint.realPath, sizeof(decodeTint.realPath), norm, _TRUNCATE);

        AcquireSRWLockExclusive(&g_sfileLock);
        g_sfileTint[normVirt] = tint;
        InterlockedExchange(&g_sfileActive, (LONG)g_sfileTint.size());
        ReleaseSRWLockExclusive(&g_sfileLock);

        AcquireSRWLockExclusive(&g_tintLock);
        g_tintMap[normVirt] = decodeTint;
        InterlockedExchange(&g_tintActive, (LONG)g_tintMap.size());
        ReleaseSRWLockExclusive(&g_tintLock);

        AcquireSRWLockExclusive(&g_texLock);
        g_texMap[norm] = normVirt;
        g_texMap[normVirt] = norm;
        InterlockedExchange(&g_texActive, (LONG)g_texMap.size());
        ReleaseSRWLockExclusive(&g_texLock);

        AcquireSRWLockExclusive(&g_barberPathLock);
        g_barberDynamicKeys[region].sfileKeys.emplace_back(normVirt);
        g_barberDynamicKeys[region].tintKeys.emplace_back(normVirt);
        g_barberDynamicKeys[region].redirectKeys.emplace_back(norm);
        g_barberDynamicKeys[region].redirectKeys.emplace_back(normVirt);
        ReleaseSRWLockExclusive(&g_barberPathLock);

        strncpy_s(outPath, outSz, normVirt, _TRUNCATE);
        return true;
    }

    static void DiagTex(const char* tag, const char* fn) {
        if (!g_diagTexOn || !fn || g_isProcessTerminating) return;
        if (g_diagTexHits >= 2000) return;
        // ONLY the slots the user reports broken: body-composite armor
        // (Item\TextureComponents\...) and the cloak (Item\ObjectComponents\Cape\...).
        // The WORKING items — weapon / shield / helmet(Head) / shoulder — are skipped
        // so the log isn't drowned in their texture requests.
        // DIAGNOSTIC: also include the separate-model items (weapon/shoulder/head/cape)
        // so we can see exactly how their textures are requested & decoded on reset.
        bool isArmor = ContainsCI(fn, "TEXTURECOMPONENT") || ContainsCI(fn, "OBJECTCOMPONENTS") ||
                       ContainsCI(fn, "CHARACTER\\") || ContainsCI(fn, "TM_CTINT_BARBER");
        if (!isArmor) return;
        InterlockedIncrement(&g_diagTexHits);
        bool red = false, tnt = false, sft = false;
        { char tmp[300]; red = FindTexRedirect(fn, tmp, sizeof(tmp)); }
        { TextureTint t; tnt = TryGetTintForFilename(fn, &t, nullptr, 0); }
        { TextureTint t; sft = SfileTintLookup(fn, &t); }
        Log("[DIAGTEX %-8s] redir=%d tint=%d sfile=%d  %s", tag, red ? 1 : 0, tnt ? 1 : 0, sft ? 1 : 0, fn);
    }

    // =====================================================================
    // COMPOSITE OWNER GATE — keep player skin / hair / body-armor recolors on
    // the LOCAL player ONLY.
    //
    // The barber (CHARACTER\<race>\<sex>\...skin/hair) and body-armor
    // (Item\TextureComponents\...) recolors are applied at the per-unit character
    // composite layer (hkCompositeTexGet -> SFile). Because the SOURCE BLP is SHARED
    // by every unit of the same race/sex (or wearing the same item), the old
    // path-based tint leaked onto OTHER players / NPCs that happened to composite the
    // very same source texture.
    //
    // Fix: the engine composites each unit through a per-unit thiscall whose `this`
    // identifies the unit being built — players: CGPlayer build @0x00730290 (this =
    // CGUnit base), other units/NPCs: @0x007059A0 (this = CGUnit base), body-armor
    // component bake: @0x004F1520 (this = unit's character-component object, located at
    // CGUnit+0xB4C — verified at the CGPlayer build site 0x00730F7D). We wrap those and
    // mark whether the composite currently running belongs to the local player. While a
    // composite is running for a unit that is POSITIVELY NOT the local player,
    // hkCompositeTexGet does not route its textures through our barber/skin tint.
    //
    // SAFE BY DESIGN: we only suppress when a driver fired with this != local player
    // (a positively-identified remote composite). The local player AND any ambiguous
    // path (no driver active — e.g. the glue char-select doll, which is tinted by a
    // different hook) keep the exact previous behavior, so no feature is broken.
    // =====================================================================
    static thread_local int g_remoteCompositeDepth = 0;
    static thread_local int g_localCompositeDepth  = 0;

    static inline bool CompositeIsRemote() {
        return g_remoteCompositeDepth > 0 && g_localCompositeDepth == 0;
    }
    static inline bool CompositeIsLocal() { return g_localCompositeDepth > 0; }

    // A player-appearance texture (the Skin tab + Barber recolor everything the player wears or
    // is) lives under CHARACTER\ (body/skin/hair) or ITEM\ (weapon/armor components). Creature /
    // mount skins recolored by the Colors tab live under CREATURE\ and must stay global (they are
    // meant to recolor the target), so they are NOT matched here.
    static bool IsPlayerAppearancePath(const char* norm) {
        if (!norm) return false;
        return strncmp(norm, "CHARACTER\\", 10) == 0 || strncmp(norm, "ITEM\\", 5) == 0;
    }

    // Player-appearance tints are applied ONLY when we are compositing the LOCAL player (a driver
    // marked the owner, or the morpher forced a local-composite scope), OR at the char-select glue
    // screen (the only model there is the selected character — no other players to leak onto). For
    // every other case (another player / NPC streaming in, or an ambiguous lazy load) the real,
    // untinted texture is used, so a recolor can never appear on anyone but you.
    static bool PlayerTintAllowed() {
        if (g_localCompositeDepth > 0) return true;
        __try { if (IsInGlue()) return true; } __except (EXCEPTION_EXECUTE_HANDLER) {}
        return false;
    }

    // ===================== SCOPE DIAGNOSTIC (file-only, temporary) =====================
    // Writes a plain text file next to wow.exe (NOT TSM_logs, NOT in-game) so we can learn,
    // for the body-component texture loads that carry a Skin/Barber recolor, WHICH composite
    // scope they fall in (local depth / remote depth) and on WHICH thread — the data needed to
    // build a precise local-only gate that never blocks your own skin. Bounded + SEH-guarded +
    // active only while a recolor is registered, so it is quiet until you apply a skin. Remove
    // once the gate is implemented.
    static volatile LONG g_scopeDiagLines = 0;
    static const LONG    SCOPE_DIAG_MAX   = 8000;
    static void ScopeDiag(const char* fmt, ...) {
        if (g_isProcessTerminating) return;
        if (!(g_texActive || g_sfileActive)) return;          // only while a recolor is active
        if (g_scopeDiagLines >= SCOPE_DIAG_MAX) return;
        char body[700];
        va_list ap; va_start(ap, fmt);
        _vsnprintf_s(body, sizeof(body), _TRUNCATE, fmt, ap);
        va_end(ap);
        __try {
            char path[MAX_PATH];
            if (!GetModuleFileNameA(NULL, path, MAX_PATH)) return;
            char* slash = strrchr(path, '\\');
            if (!slash) return;
            strcpy_s(slash + 1, MAX_PATH - (size_t)(slash + 1 - path), "transmorpher_scope_diag.txt");
            FILE* f = nullptr;
            if (fopen_s(&f, path, "a") == 0 && f) {
                fprintf(f, "[tid=%lu lD=%d rD=%d] %s\n",
                        GetCurrentThreadId(), g_localCompositeDepth, g_remoteCompositeDepth, body);
                fclose(f);
                InterlockedIncrement(&g_scopeDiagLines);
            }
        } __except (EXCEPTION_EXECUTE_HANDLER) {}
    }
    // True for the body/skin/item textures we care about (keeps the trace focused + small).
    // Case-insensitive: raw engine paths arrive in mixed case before NormalizeTexPath.
    static bool ScopeDiagInteresting(const char* p) {
        if (!p) return false;
        return ContainsCI(p, "CHARACTER\\") || ContainsCI(p, "ITEM\\") ||
               ContainsCI(p, "TM_CTINT") || ContainsCI(p, "TEXTURECOMPONENT");
    }

    // One-shot READ-ONLY dump of the per-unit component-entry array (the engine cache the
    // morph/weapon re-attach hinges on). For the local player we log, per equipment slot 0..0x12:
    //   entry[0] = the ID the slot is attached with (RefreshAllComponentItems treats a NEGATIVE
    //              value as "pending re-attach"; resolved via the item store 0xC5D828), entry[1].
    // Base = *(unit+0x1008); array at +0x21c, stride 8 (RE-verified from 0x6E09E0/0x6E08C0).
    // Comparing these to the warglaive item ids you morphed to tells us the exact id-space and the
    // slot index to mark, so the "weapon needs relog" re-attach can be written with no guessing.
    static volatile LONG g_compDumpCount = 0;
    static void DumpComponentEntries(void* unit) {
        if (g_isProcessTerminating || !unit || (uintptr_t)unit < 0x10000) return;
        if (g_compDumpCount >= 6) return;            // a few snapshots is plenty
        __try {
            uint8_t* mgr = *reinterpret_cast<uint8_t**>(reinterpret_cast<uint8_t*>(unit) + 0x1008);
            if (!mgr || (uintptr_t)mgr < 0x10000) return;
            char line[700]; int n = 0;
            n += _snprintf_s(line + n, sizeof(line) - n, _TRUNCATE, "COMPDUMP unit=%p mgr=%p :", unit, mgr);
            for (int slot = 0; slot <= 0x12 && n < (int)sizeof(line) - 32; ++slot) {
                int32_t e0 = *reinterpret_cast<int32_t*>(mgr + slot * 8 + 0x21c);
                int32_t e1 = *reinterpret_cast<int32_t*>(mgr + slot * 8 + 0x21c + 4);
                if (e0 != 0 || e1 != 0)
                    n += _snprintf_s(line + n, sizeof(line) - n, _TRUNCATE, " [%d]=%d/%d", slot, e0, e1);
            }
            char path[MAX_PATH];
            if (!GetModuleFileNameA(NULL, path, MAX_PATH)) return;
            char* slash = strrchr(path, '\\');
            if (!slash) return;
            strcpy_s(slash + 1, MAX_PATH - (size_t)(slash + 1 - path), "transmorpher_scope_diag.txt");
            FILE* f = nullptr;
            if (fopen_s(&f, path, "a") == 0 && f) { fprintf(f, "%s\n", line); fclose(f); InterlockedIncrement(&g_compDumpCount); }
        } __except (EXCEPTION_EXECUTE_HANDLER) {}
    }
    // ================================================================================

    // CGUnit_C offset of the character-component object the body-armor bake (0x004F1520)
    // runs on. Verified: the CGPlayer build site at 0x00730F7D loads it from [player+0xB4C]
    // immediately before calling 0x004F1520.
    static const uintptr_t CHAR_COMPONENT_OBJ_OFF = 0xB4C;

    typedef char (__fastcall* UnitCharBuild_t)(void* This, void* edx, int a1);
    static UnitCharBuild_t oPlayerCharBuild = reinterpret_cast<UnitCharBuild_t>(0x00730290);
    static UnitCharBuild_t oUnitCharBuild   = reinterpret_cast<UnitCharBuild_t>(0x007059A0);
    static UnitCharBuild_t oItemCompBake    = reinterpret_cast<UnitCharBuild_t>(0x004F1520);

    static void* LocalPlayerObjSafe() {
        __try { return reinterpret_cast<void*>(GetPlayer()); }
        __except (EXCEPTION_EXECUTE_HANDLER) { return nullptr; }
    }

    // GetPlayer() returns NULL inside the engine's render-pass character composite (the
    // body bake 0x4F1520 logs lp=0), so we can't identify the local player THERE. But it is
    // valid in other main-thread contexts (UpdateDisplayInfo, the dllmain tick). We cache the
    // local CGPlayer pointer whenever it resolves, then the composite hooks compare against the
    // cache — this is what lets the bake mark OTHER units' composites as remote (so their shared
    // textures are never tinted = no cross-character leak) while keeping your own composite local.
    static void* g_cachedLocalPlayer = nullptr;   // plain global; everything here is main-thread
    static inline void* CachedLocalPlayer() {
        void* lp = LocalPlayerObjSafe();
        if (lp) { g_cachedLocalPlayer = lp; return lp; }
        return g_cachedLocalPlayer;               // fall back to the last known-good pointer
    }
    // The local player's character-component object (the `this` the body bake 0x4F1520 runs on).
    static void* CachedLocalCharObj() {
        void* lp = CachedLocalPlayer();
        if (!lp) return nullptr;
        __try { return *reinterpret_cast<void**>(reinterpret_cast<uint8_t*>(lp) + CHAR_COMPONENT_OBJ_OFF); }
        __except (EXCEPTION_EXECUTE_HANDLER) { return nullptr; }
    }

    static inline void CompositeEnter(bool isLocal, bool isRemote) {
        if (isRemote) ++g_remoteCompositeDepth;
        else if (isLocal) ++g_localCompositeDepth;
    }
    static inline void CompositeLeave(bool isLocal, bool isRemote) {
        if (isRemote) { if (g_remoteCompositeDepth > 0) --g_remoteCompositeDepth; }
        else if (isLocal) { if (g_localCompositeDepth > 0) --g_localCompositeDepth; }
    }

    // Players: this = CGUnit base; compare directly to the local player object.
    char __fastcall hkPlayerCharBuild(void* This, void* edx, int a1) {
        void* lp = CachedLocalPlayer();
        bool isLocal  = (lp && This == lp);
        bool isRemote = (lp && This != lp);
        CompositeEnter(isLocal, isRemote);
        ScopeDiag("CHARBUILD(player) This=%p lp=%p isLocal=%d isRemote=%d", This, lp, (int)isLocal, (int)isRemote);
        char rv = 0;
        __try { rv = oPlayerCharBuild(This, edx, a1); }
        __finally { CompositeLeave(isLocal, isRemote); }
        return rv;
    }

    // Other units / NPCs: this = CGUnit base; never the local player (so always remote
    // when a local player exists), which keeps the player recolor off NPCs too.
    char __fastcall hkUnitCharBuild(void* This, void* edx, int a1) {
        void* lp = CachedLocalPlayer();
        bool isLocal  = (lp && This == lp);
        bool isRemote = (lp && This != lp);
        CompositeEnter(isLocal, isRemote);
        ScopeDiag("CHARBUILD(unit) This=%p lp=%p isLocal=%d isRemote=%d", This, lp, (int)isLocal, (int)isRemote);
        char rv = 0;
        __try { rv = oUnitCharBuild(This, edx, a1); }
        __finally { CompositeLeave(isLocal, isRemote); }
        return rv;
    }

    // Body-armor component bake: this = the character-component object, so compare to the
    // local player's component object (player+0xB4C) rather than the CGUnit base.
    char __fastcall hkItemCompBake(void* This, void* edx, int a1) {
        // GetPlayer() is NULL here (render pass), so use the cached local char-component obj.
        void* localCharObj = CachedLocalCharObj();
        bool isLocal  = (localCharObj && This == localCharObj);
        bool isRemote = (localCharObj && This != localCharObj);
        CompositeEnter(isLocal, isRemote);
        ScopeDiag("ITEMCOMPBAKE This=%p localCharObj=%p isLocal=%d isRemote=%d", This, localCharObj, (int)isLocal, (int)isRemote);
        char rv = 0;
        __try { rv = oItemCompBake(This, edx, a1); }
        __finally { CompositeLeave(isLocal, isRemote); }
        return rv;
    }

    // CGUnit_C::UpdateDisplayInfo @0x0073E410 (this=ecx=CGUnit, ret 4). The per-unit
    // model + EQUIPMENT rebuild. This is what wraps the OBJECT-COMPONENT item loads
    // (weapon / shoulder / helmet / cape models, decoded via BLPFileLockChain2 /
    // TextureLoadImage — a different path than the body composite), so marking the
    // owner here lets those texture hooks keep an item recolor on the local player only.
    typedef char (__fastcall* UpdateDisplay_t)(void* This, void* edx, int forceFlag);
    static UpdateDisplay_t oUpdateDisplayInfo = reinterpret_cast<UpdateDisplay_t>(0x0073E410);
    char __fastcall hkUpdateDisplayInfo(void* This, void* edx, int forceFlag) {
        void* lp = CachedLocalPlayer();   // valid here -> also refreshes the cache for the bake
        bool isLocal  = (lp && This == lp);
        bool isRemote = (lp && This != lp);
        CompositeEnter(isLocal, isRemote);
        ScopeDiag("UPDATEDISPLAY This=%p lp=%p isLocal=%d isRemote=%d force=%d", This, lp, (int)isLocal, (int)isRemote, forceFlag);
        if (isLocal) DumpComponentEntries(This);   // read-only: confirm the weapon re-attach entry format

        char rv = 0;
        __try { rv = oUpdateDisplayInfo(This, edx, forceFlag); }
        __finally { CompositeLeave(isLocal, isRemote); }
        return rv;
    }

    // --- Hooks ---
    // Character compositor component fetch. Logs body-armor component requests (so we
    // can confirm the bake re-runs on re-apply) and redirects a source component to a
    // donor's real file for skin swaps. Tint virtual targets are cache keys only; when
    // SFileOpen sees them it opens the real BLP and SFileRead tints the streamed bytes.
    void* __cdecl hkCompositeTexGet(const char* path) {
        if (!path || g_isProcessTerminating) return oCompositeTexGet(path);
        DiagTex("Comp", path);
        if (ScopeDiagInteresting(path)) ScopeDiag("COMP path=%s", path);
        // Keep player skin / hair / body-armor recolors on the LOCAL player only: when
        // the engine is compositing a positively-identified REMOTE unit, do not route its
        // shared source textures through our barber/skin tint (the "recolor leaks onto
        // other players" fix). The local player and any ambiguous path are unaffected.
        const bool remoteComposite = CompositeIsRemote();
        char barberVirt[300];
        if (!remoteComposite && BarberRouteCompositePath(path, barberVirt, sizeof(barberVirt))) {
            return oCompositeTexGet(barberVirt);
        }
        if (!remoteComposite && g_texActive) {
            char repl[300];
            // ONLY follow redirects to a REAL existing file (skin swap / retex donor).
            // NEVER hand the compositor a TM_TINT virtual: its component decode does
            // NOT pass through our BLP hooks, so a virtual path fails to load and the
            // body armor renders as bare skin. Tints are applied at the decode layer
            // (see hkCompositeDecode) instead.
            if (FindTexRedirect(path, repl, sizeof(repl)) && !ContainsCI(repl, "TM_TINT")) {
                if (g_diagTexOn && g_diagTexHits < 2000 &&
                    (ContainsCI(path, "TEXTURECOMPONENT") || ContainsCI(path, "OBJECTCOMPONENTS\\CAPE"))) {
                    InterlockedIncrement(&g_diagTexHits);
                    Log("[DIAGTEX Comp-RDR] %s -> %s", path, repl);
                }
                return oCompositeTexGet(repl);
            }
        }
        return oCompositeTexGet(path);
    }

    // SFile open: when the body compositor opens a component BLP that has an active
    // tint, remember the returned handle + tint so the reads below can recolor it.
    int __stdcall hkSFileOpen(int a0, const char* path, int a2, void** outHandle) {
        const char* openPath = path;
        char repl[300] = {0};
        // Body-component tint cache-buster path: CompositeTexGet may request a
        // synthetic TM_CTINT_* key. Resolve it back to the real BLP here so SFile
        // opens valid data while the cache key remains unique.
        if (path && g_texActive && IsVirtualComponentKey(path)) {
            if (FindTexRedirect(path, repl, sizeof(repl))) {
                openPath = repl;
            } else if (!g_isProcessTerminating) {
                // Reverse redirect was cleared while the engine still held a live
                // virtual-key request. Refuse the open cleanly so the engine gets a
                // proper fail-status handle instead of a stale one; the texture
                // loader treats this as a normal load failure.
                if (outHandle) *outHandle = nullptr;
                return 0;
            }
        }

        int rv = oSFileOpen(a0, openPath, a2, outHandle);
        if (rv && g_sfileActive && outHandle && *outHandle && path && !g_isProcessTerminating) {
            TextureTint t;
            bool matched = SfileTintLookup(path, &t);
            const bool remote = CompositeIsRemote();
            if (path && ScopeDiagInteresting(path))
                ScopeDiag("SFOPEN match=%d remote=%d path=%s open=%s", (int)matched, (int)remote, path, openPath);
            // Block the body-component tint when we are positively compositing a REMOTE unit
            // (now reliably detected via the cached local identity) -> the recolor stays on you
            // only. Local and any still-ambiguous load keep tinting (fail-safe toward your own
            // appearance), so your skin/barber is never lost.
            if (matched && !remote) {
                BlpTintState st = {}; st.tint = t;
                st.barber = ContainsCI(path, "TM_CTINT_BARBER") || ContainsCI(path, "CHARACTER\\");
                strncpy_s(st.path, sizeof(st.path), path, _TRUNCATE);
                AcquireSRWLockExclusive(&g_handleLock);
                if (g_blpHandles.size() > 1024) g_blpHandles.clear();   // safety bound
                g_blpHandles[*outHandle] = st;
                InterlockedExchange(&g_blpTagged, (LONG)g_blpHandles.size());
                ReleaseSRWLockExclusive(&g_handleLock);
            }
        }
        return rv;
    }

    // SFile read: tint the BLP bytes of a tagged handle in place as they stream in.
    int __stdcall hkSFileRead(void* handle, void* buf, uint32_t toRead, uint32_t* bytesRead, void* a4, void* a5) {
        // SEH-guard the engine read. A stale/invalid MPQ handle — observed while a
        // body-component tint re-binds during a gear swap or zone transition — can have
        // a NULL internal stream object, so the engine's own SFileRead dereferences NULL
        // and crashes the client (ERROR #132 @0x00426559). Catch it and report a clean
        // read failure instead of taking down the game.
        int rv = 0;
        __try {
            rv = oSFileRead(handle, buf, toRead, bytesRead, a4, a5);
        } __except (EXCEPTION_EXECUTE_HANDLER) {
            if (bytesRead) *bytesRead = 0;
            return 0;
        }
        if (!rv || !g_sfileActive || !handle || !buf || g_isProcessTerminating) return rv;
        uint32_t n = bytesRead ? *bytesRead : toRead;
        if (!n) return rv;
        AcquireSRWLockExclusive(&g_handleLock);
        auto it = g_blpHandles.find(handle);
        if (it != g_blpHandles.end()) {
            BlpTintState& s = it->second;
            uint32_t start = s.offset;
            // Accumulate the BLP2 header (first 0x94 bytes) so we know the layout.
            if (s.hdrLen < (int)sizeof(s.hdr)) {
                for (uint32_t k = 0; k < n && s.hdrLen < (int)sizeof(s.hdr); ++k) {
                    uint32_t filePos = start + k;
                    if (filePos < sizeof(s.hdr)) { s.hdr[filePos] = ((uint8_t*)buf)[k]; if ((int)filePos + 1 > s.hdrLen) s.hdrLen = filePos + 1; }
                }
                if (!s.parsed && s.hdrLen >= 0x94) ParseBlpHeader(s);
            }
            if (s.parsed && s.isBlp) ProcessBlpRead(s, (uint8_t*)buf, start, n);
            s.offset += n;
        }
        ReleaseSRWLockExclusive(&g_handleLock);
        return rv;
    }

    // Handle destructor: drop any tint tag so a reused handle is never mis-tinted.
    void* __fastcall hkHandleFree(void* handle, void* edx, int flags) {
        if (handle && g_blpTagged) {
            AcquireSRWLockExclusive(&g_handleLock);
            auto it = g_blpHandles.find(handle);
            if (it != g_blpHandles.end()) {
                g_blpHandles.erase(it);
                InterlockedExchange(&g_blpTagged, (LONG)g_blpHandles.size());
            }
            ReleaseSRWLockExclusive(&g_handleLock);
        }
        return oHandleFree(handle, edx, flags);
    }

    void* __cdecl hkTextureCacheGetTexture(const char* filename) {
        DiagTex("Cache", filename);
        if (CompositeIsRemote()) return oTextureCacheGetTexture(filename);  // remote unit -> no recolor
        if (g_texActive && filename && !IsVirtualComponentKey(filename) && !g_isProcessTerminating) {
            char repl[300];
            if (FindTexRedirect(filename, repl, sizeof(repl))) {
                return oTextureCacheGetTexture(repl);
            }
        }
        return oTextureCacheGetTexture(filename);
    }

    void* __cdecl hkTextureCacheGetTextureEx(const char* filename, char* outExt, int a3) {
        DiagTex("CacheEx", filename);
        if (CompositeIsRemote()) return oTextureCacheGetTextureEx(filename, outExt, a3);  // remote unit -> no recolor
        if (g_texActive && filename && !IsVirtualComponentKey(filename) && !g_isProcessTerminating) {
            char repl[300];
            if (FindTexRedirect(filename, repl, sizeof(repl))) {
                return oTextureCacheGetTextureEx(repl, outExt, a3);
            }
        }
        return oTextureCacheGetTextureEx(filename, outExt, a3);
    }

    int __fastcall hkBLPFileLockChain2(void* This, void* edx, char* fileName,
                                       int format, void** images, uint32_t mipLevel, int a6) {
        static __declspec(thread) char repl[300];
        static __declspec(thread) char repl2[300];
        DiagTex("Lock2", fileName);
        // Remote unit being composited/equipped -> decode the real (untinted) BLP so an
        // item recolor (weapon/shoulder/helm/cape) stays on the local player only.
        if (CompositeIsRemote())
            return oBLPFileLockChain2(This, edx, fileName, format, images, mipLevel, a6);
        const char* loadName = fileName;
        TextureTint tint = {};
        bool hasTint = false;
        if (g_texActive && fileName && !g_isProcessTerminating) {
            if (IsCleanVirtualKey(fileName)) {
                if (FindTexRedirect(fileName, repl, sizeof(repl))) loadName = repl;
            } else if (IsTintVirtualKey(fileName)) {
                // Active tint virtuals must load through g_tintMap. If this is an
                // old virtual CTexture whose tint was replaced, fall back through
                // the kept reverse redirect instead of trying to load TM_CTINT_*.blp.
                if (g_tintActive) hasTint = TryGetTintForFilename(fileName, &tint, nullptr, 0);
                if (hasTint) loadName = tint.realPath;
                else if (FindTexRedirect(fileName, repl, sizeof(repl))) {
                    loadName = repl;
                    if (FindTexRedirect(loadName, repl2, sizeof(repl2)) && IsTintVirtualKey(repl2)) {
                        loadName = repl2;
                    }
                }
            } else if (!IsTintVirtualKey(fileName)) {
                if (FindTexRedirect(fileName, repl, sizeof(repl))) {
                    loadName = repl;
                    if (IsCleanVirtualKey(loadName) && FindTexRedirect(loadName, repl2, sizeof(repl2))) {
                        loadName = repl2;
                    }
                }
            }
        }

        if (!hasTint && g_tintActive && fileName && !g_isProcessTerminating) {
            hasTint = TryGetTintForFilename(loadName, &tint, nullptr, 0);
            if (!hasTint && loadName != fileName) hasTint = TryGetTintForFilename(fileName, &tint, nullptr, 0);
            if (hasTint) loadName = tint.realPath;
        }

        int rv = oBLPFileLockChain2(This, edx, const_cast<char*>(loadName), format, images, mipLevel, a6);
        // DIAGNOSTIC: trace separate-model item decodes (weapon/shoulder/head/cape) so we
        // can see, on reset, whether they re-decode and onto WHICH texture object.
        if (g_diagTexOn && fileName && !g_isProcessTerminating && ContainsCI(fileName, "OBJECTCOMPONENTS")) {
            Log("[DIAGTEX DECODE-M] mip=%u tint=%d rv=%d This=%p file=%s load=%s",
                mipLevel, hasTint ? 1 : 0, rv, This, fileName, loadName);
        }
        if (hasTint && rv && images && *images) {
            uint32_t w = 0, h = 0;
            __try {
                uint8_t* t = reinterpret_cast<uint8_t*>(This);
                w = *reinterpret_cast<uint32_t*>(t + 0x10);
                h = *reinterpret_cast<uint32_t*>(t + 0x14);
            } __except (EXCEPTION_EXECUTE_HANDLER) { w = 0; h = 0; }
            if (w && h) {
                ApplyTextureTint(*images, w, h, format, tint);
            }
        }
        return rv;
    }

    void* __cdecl hkTextureLoadImage(const char* filename, uint32_t* width, uint32_t* height,
                                     int* dataFormat, int* isOpaque, void* status,
                                     uint32_t* alphaBits, int a8) {
        DiagTex("LoadImg", filename);
        if (CompositeIsRemote())  // remote unit -> load the real (untinted) image
            return oTextureLoadImage(filename, width, height, dataFormat, isOpaque, status, alphaBits, a8);
        if (g_texActive && filename && IsCleanVirtualKey(filename) && !g_isProcessTerminating) {
            static __declspec(thread) char cleanRepl[300];
            if (FindTexRedirect(filename, cleanRepl, sizeof(cleanRepl))) {
                return oTextureLoadImage(cleanRepl, width, height, dataFormat, isOpaque, status, alphaBits, a8);
            }
        }
        if (g_tintActive && filename && !g_isProcessTerminating) {
            TextureTint tint = {};
            if (TryGetTintForFilename(filename, &tint, nullptr, 0)) {
                void* image = oTextureLoadImage(tint.realPath, width, height, dataFormat, isOpaque, status, alphaBits, a8);
                if (image && width && height && dataFormat) ApplyTextureTint(image, *width, *height, *dataFormat, tint);
                return image;
            }
        }
        if (g_texActive && filename && IsTintVirtualKey(filename) && !g_isProcessTerminating) {
            static __declspec(thread) char staleTintRepl[300];
            static __declspec(thread) char staleTintRepl2[300];
            if (FindTexRedirect(filename, staleTintRepl, sizeof(staleTintRepl))) {
                if (FindTexRedirect(staleTintRepl, staleTintRepl2, sizeof(staleTintRepl2)) &&
                    IsTintVirtualKey(staleTintRepl2) && g_tintActive) {
                    TextureTint tint = {};
                    if (TryGetTintForFilename(staleTintRepl2, &tint, nullptr, 0)) {
                        void* image = oTextureLoadImage(tint.realPath, width, height, dataFormat, isOpaque, status, alphaBits, a8);
                        if (image && width && height && dataFormat) ApplyTextureTint(image, *width, *height, *dataFormat, tint);
                        return image;
                    }
                }
                return oTextureLoadImage(staleTintRepl, width, height, dataFormat, isOpaque, status, alphaBits, a8);
            }
        }
        if (g_texActive && filename && !IsVirtualComponentKey(filename) && !g_isProcessTerminating) {
            static __declspec(thread) char replBuf[300];
            const char* repl = nullptr;
            if (FindTexRedirect(filename, replBuf, sizeof(replBuf))) {
                repl = replBuf;
            }
            if (repl) {
                if (g_tintActive) {
                    TextureTint tint = {};
                    if (TryGetTintForFilename(repl, &tint, nullptr, 0)) {
                        void* image = oTextureLoadImage(tint.realPath, width, height, dataFormat, isOpaque, status, alphaBits, a8);
                        if (image && width && height && dataFormat) ApplyTextureTint(image, *width, *height, *dataFormat, tint);
                        return image;
                    }
                }
                if (IsCleanVirtualKey(repl)) {
                    static __declspec(thread) char cleanRepl2[300];
                    if (FindTexRedirect(repl, cleanRepl2, sizeof(cleanRepl2))) {
                        return oTextureLoadImage(cleanRepl2, width, height, dataFormat, isOpaque, status, alphaBits, a8);
                    }
                }
                return oTextureLoadImage(repl, width, height, dataFormat, isOpaque, status, alphaBits, a8);
            }
        }
        return oTextureLoadImage(filename, width, height, dataFormat, isOpaque, status, alphaBits, a8);
    }

    void ApplyWorldTintToGlobals() {
        const float tr = (float)g_wtR / 255.0f;
        const float tg = (float)g_wtG / 255.0f;
        const float tb = (float)g_wtB / 255.0f;
        const float ch[3] = { tr, tg, tb };
        __try {
            for (int i = 0; i < g_worldColorFloatCount; ++i) {
                g_worldColorFloats[i] *= ch[i % 3];
            }
            // Ambient CImVector (little-endian B,G,R,A): tint R,G,B keep A.
            uint32_t c = *g_worldAmbientCImVector;
            uint32_t b = (c) & 0xFF, gg = (c >> 8) & 0xFF, r = (c >> 16) & 0xFF, a = (c >> 24) & 0xFF;
            b = (uint32_t)(b * tb); gg = (uint32_t)(gg * tg); r = (uint32_t)(r * tr);
            if (b > 255) b = 255; if (gg > 255) gg = 255; if (r > 255) r = 255;
            *g_worldAmbientCImVector = (a << 24) | (r << 16) | (gg << 8) | b;
        } __except (EXCEPTION_EXECUTE_HANDLER) {}
    }

    inline void SetTriple(float* f, const float c[3]) { f[0] = c[0]; f[1] = c[1]; f[2] = c[2]; }
    inline void LerpTriple(float* f, const float a[3], const float b[3], float t) {
        f[0] = a[0] + (b[0] - a[0]) * t;
        f[1] = a[1] + (b[1] - a[1]) * t;
        f[2] = a[2] + (b[2] - a[2]) * t;
    }

    // Apply the active mood. The SKY (atmosphere) is recolored fully — that's the
    // whole point and it should change dramatically. But the ambient + diffuse
    // (the light that hits TERRAIN and models) is only TINTED toward the mood, not
    // overwritten — overwriting painted the whole ground a flat solid colour
    // (greenscreen). f[] already holds the natural values (oSetColors ran first),
    // so we lerp them toward the mood by kLight.
    void ApplyWorldLightToGlobals() {
        float amb[3], dif[3], top[3], hor[3];
        AcquireSRWLockShared(&g_wlLock);
        for (int i = 0; i < 3; ++i) { amb[i] = g_wlAmb[i]; dif[i] = g_wlDif[i]; top[i] = g_wlSkyTop[i]; hor[i] = g_wlSkyHor[i]; }
        ReleaseSRWLockShared(&g_wlLock);
        const float kLight = 0.45f;   // how far terrain/model light is tinted toward the mood
        __try {
            float* f = g_worldColorFloats;
            LerpTriple(f + 0, f + 0, amb, kLight);   // ambient  (tint, keep detail)
            LerpTriple(f + 3, f + 3, dif, kLight);   // diffuse  (tint, keep detail)
            SetTriple(f + 6,  top);                  // sky band 0 (zenith)  - full
            LerpTriple(f + 9,  top, hor, 0.34f);     // sky band 1
            LerpTriple(f + 12, top, hor, 0.62f);     // sky band 2
            LerpTriple(f + 15, top, hor, 0.85f);     // sky band 3
            SetTriple(f + 18, hor);                  // sky band 4 (horizon) - full
            // Model ambient CImVector: tint toward the mood ambient too.
            uint32_t c = *g_worldAmbientCImVector;
            float nb = (float)(c & 0xFF) / 255.0f, ng = (float)((c >> 8) & 0xFF) / 255.0f, nr = (float)((c >> 16) & 0xFF) / 255.0f;
            uint32_t a = (c >> 24) & 0xFF;
            float rr = nr + (amb[0] - nr) * kLight, gg = ng + (amb[1] - ng) * kLight, bb = nb + (amb[2] - nb) * kLight;
            uint32_t R = (uint32_t)(rr * 255.0f), G = (uint32_t)(gg * 255.0f), B = (uint32_t)(bb * 255.0f);
            if (R > 255) R = 255; if (G > 255) G = 255; if (B > 255) B = 255;
            *g_worldAmbientCImVector = (a << 24) | (R << 16) | (G << 8) | B;
        } __except (EXCEPTION_EXECUTE_HANDLER) {}
    }

    // Brightness = scale ONLY the scene lighting (ambient triple 0 + diffuse/sun
    // triple 1) and the model ambient CImVector. The 5 sky-band colors (floats
    // 6..20) and the fog are left alone, so brightening doesn't blow out the sky
    // into a white horizon band or change the fog.
    void ApplyBrightnessToGlobals() {
        float m = (float)g_brightX1000 / 1000.0f;
        if (m < 0.0f) m = 0.0f; if (m > 4.0f) m = 4.0f;
        __try {
            float* f = g_worldColorFloats;
            for (int i = 0; i < 6 && i < g_worldColorFloatCount; ++i) {  // ambient + diffuse only
                float v = f[i] * m;
                if (v > 1.0f) v = 1.0f;
                f[i] = v;
            }
            uint32_t c = *g_worldAmbientCImVector;
            uint32_t b = (c) & 0xFF, gg = (c >> 8) & 0xFF, r = (c >> 16) & 0xFF, a = (c >> 24) & 0xFF;
            b = (uint32_t)(b * m); gg = (uint32_t)(gg * m); r = (uint32_t)(r * m);
            if (b > 255) b = 255; if (gg > 255) gg = 255; if (r > 255) r = 255;
            *g_worldAmbientCImVector = (a << 24) | (r << 16) | (gg << 8) | b;
        } __except (EXCEPTION_EXECUTE_HANDLER) {}
    }

    void __cdecl hkSetColors() {
        oSetColors();
        if (g_isProcessTerminating) return;
        // Order: mood overwrite -> legacy multiply tint -> brightness.
        if (g_wlActive)        ApplyWorldLightToGlobals();
        if (g_worldTintActive) ApplyWorldTintToGlobals();
        if (g_brightActive)    ApplyBrightnessToGlobals();
        // Re-assert the skybox override (the zone writer runs during light updates).
        if (g_skyActive) {
            __try { *g_zoneSkyboxName = g_skyName; } __except (EXCEPTION_EXECUTE_HANDLER) {}
        }
    }

    // Force our chosen skybox into the primary slot at full weight. Without this the
    // engine uses the zone's blend weight (0 in skybox-less zones) and the override
    // shows nothing. Only slot 0 is overridden; everything else passes through.
    void __cdecl hkSetBlendSky(int slot, const char* name, int flag, float weight) {
        if (g_skyActive && slot == 0 && !g_isProcessTerminating) {
            oSetBlendSky(0, g_skyName, flag, 1.0f);
            return;
        }
        oSetBlendSky(slot, name, flag, weight);
    }

    void __fastcall hkLightSet(void* This, void* edx, uint32_t index, void* light, void* pos) {
        if (g_modelTintActive && light && !g_isProcessTerminating) {
            float* amb = reinterpret_cast<float*>(reinterpret_cast<uint8_t*>(light) + 0x10);
            float* dir = reinterpret_cast<float*>(reinterpret_cast<uint8_t*>(light) + 0x1C);
            const float tr = (float)g_mtR / 255.0f;
            const float tg = (float)g_mtG / 255.0f;
            const float tb = (float)g_mtB / 255.0f;
            // Save originals, apply tint, call original, then restore so shared
            // light objects don't accumulate the multiply across frames.
            float a0 = amb[0], a1 = amb[1], a2v = amb[2];
            float d0 = dir[0], d1 = dir[1], d2 = dir[2];
            __try {
                amb[0] = a0 * tr; amb[1] = a1 * tg; amb[2] = a2v * tb;
                dir[0] = d0 * tr; dir[1] = d1 * tg; dir[2] = d2 * tb;
                oLightSet(This, edx, index, light, pos);
                amb[0] = a0; amb[1] = a1; amb[2] = a2v;
                dir[0] = d0; dir[1] = d1; dir[2] = d2;
            } __except (EXCEPTION_EXECUTE_HANDLER) {
                oLightSet(This, edx, index, light, pos);
            }
            return;
        }
        oLightSet(This, edx, index, light, pos);
    }

    // HSV(0..1, 1, 1) -> packed CImVector (A=0xFF). Used for the rainbow gradient.
    uint32_t HsvFull(float h) {
        h -= (float)(int)h; if (h < 0) h += 1.0f;
        float r = 0, g = 0, b = 0;
        float x = h * 6.0f; int i = (int)x; float f = x - i;
        switch (i % 6) {
            case 0: r = 1; g = f; b = 0; break;
            case 1: r = 1 - f; g = 1; b = 0; break;
            case 2: r = 0; g = 1; b = f; break;
            case 3: r = 0; g = 1 - f; b = 1; break;
            case 4: r = f; g = 0; b = 1; break;
            default: r = 1; g = 0; b = 1 - f; break;
        }
        uint32_t R = (uint32_t)(r * 255.0f), G = (uint32_t)(g * 255.0f), B = (uint32_t)(b * 255.0f);
        return 0xFF000000u | (R << 16) | (G << 8) | B;
    }

    // Rainbow hue = time*speed (so the whole rainbow flows over time) + a phase
    // offset (so different numbers sit at different points = a moving gradient
    // across the stream, not one synchronized color). phase01 in [0,1).
    inline uint32_t RainbowAt(float phase01) {
        float spd = (float)g_wtGradX1000 / 1000.0f;
        return HsvFull((float)GetTickCount() * 0.001f * spd + phase01);
    }

    // Single CREATION chokepoint: every over-unit number/word is created here. When
    // the style has an override we substitute the color (the engine copies it by
    // value immediately, so a stack local is safe). Solid = constant color; rainbow
    // = a starting hue stepped per number (hkWTUpdate then animates it each frame).
    // NOTE: phase MUST come from a per-number counter — the emitter reuses the same
    // stack address for `pos` every call, so seeding from it makes every number the
    // SAME color (the "it's all one color" bug).
    void* __cdecl hkWorldTextCreate(int style, void* pos, const char* text, uint32_t* color, void* a5) {
        if (g_wtActive && !g_isProcessTerminating && (unsigned)style < 16) {
            const WTStyle& s = g_wt[style];
            if (s.enabled) {
                uint32_t local = (uint32_t)s.col;
                if (s.mode == 1) {
                    LONG n = InterlockedIncrement(&g_wtSeq);
                    local = RainbowAt((float)(n & 0x3F) / 64.0f);   // step ~6° per number
                }
                __try { return oWorldTextCreate(style, pos, text, &local, a5); }
                __except (EXCEPTION_EXECUTE_HANDLER) { return nullptr; }
            }
        }
        return oWorldTextCreate(style, pos, text, color, a5);
    }

    // Per-FRAME, per-string: after the engine recomputes the fade alpha (+0x23),
    // overwrite only the RGB of the base CImVector (+0x20) for rainbow styles, so
    // each individual number animates through the spectrum while it floats. We keep
    // the engine's alpha byte so the fade-out still works.
    char __fastcall hkWTUpdate(void* This, void* edx, int age) {
        char rv = oWTUpdate(This, edx, age);
        if (g_wtActive && This && !g_isProcessTerminating) {
            __try {
                int style = *reinterpret_cast<int*>(reinterpret_cast<uint8_t*>(This) + 0x08);
                if ((unsigned)style < 16 && g_wt[style].enabled && g_wt[style].mode == 1) {
                    uint32_t* col = reinterpret_cast<uint32_t*>(reinterpret_cast<uint8_t*>(This) + 0x20);
                    uint32_t a = *col & 0xFF000000u;                 // keep engine fade alpha
                    float phase = (float)(((uintptr_t)This >> 4) & 0x3FF) / 1024.0f;
                    *col = (RainbowAt(phase) & 0x00FFFFFFu) | a;
                }
            } __except (EXCEPTION_EXECUTE_HANDLER) {}
        }
        return rv;
    }

    // Resolved appearance for a morphed doll: the 6 customization bytes the glue
    // build reads (race@+0x178, gender@+0x17a, skin@+0x17b, face@+0x17c,
    // hairStyle@+0x17d, hairColor@+0x17e, facialHair@+0x17f). Class (+0x179) is
    // left untouched so gear validation stays correct.
    struct DollAppearance {
        uint8_t race, gender, skin, face, hairStyle, hairColor, facialHair;
        bool    fromExtra;        // true = resolved via CDIExtra (an NPC that may carry baked gear)
        int32_t npcItems[11];     // CDIExtra m_npcitemDisplay[11] (ItemDisplayInfo ids), 0 if none
    };

    // The general resolver: a morph display id -> a gear-wearing character look.
    //  1) CreatureDisplayInfo[disp].m_extendedDisplayInfoID (+0x0C) -> CDIExtra.
    //     CDIExtra gives race/sex/skin/face/hair of THIS exact display, so any
    //     humanoid NPC *or* race renders correctly and wears the equipped gear.
    //  2) Fallback: scan ChrRaces male/female display ids (covers bare race ids
    //     that point straight at the body model with no extra record).
    // Returns false for true non-character creatures (no extra, not a race) — those
    // can't be shown as a gear doll and are left as the real character.
    bool ResolveDollAppearance(uint32_t displayId, DollAppearance* out) {
        if (!displayId) return false;

        // 1) CDIExtra path (verified order: CDI[+0x0C]->CDIExtra->race@+0x04)
        void* cdi = DbRecord(g_creatureDisplayInfoDB, (int)displayId);
        if (cdi) {
            uint32_t extId = 0;
            __try { extId = *reinterpret_cast<uint32_t*>(reinterpret_cast<uint8_t*>(cdi) + 0x0C); }
            __except (EXCEPTION_EXECUTE_HANDLER) { extId = 0; }
            void* ex = extId ? DbRecord(g_cdiExtraDB, (int)extId) : nullptr;
            if (ex) {
                __try {
                    uint8_t* x = reinterpret_cast<uint8_t*>(ex);
                    int race = *reinterpret_cast<int*>(x + 0x04);
                    int sex  = *reinterpret_cast<int*>(x + 0x08);
                    if (race >= 1 && race <= 15 && (sex == 0 || sex == 1)) {
                        out->race       = (uint8_t)race;
                        out->gender     = (uint8_t)sex;
                        out->skin       = (uint8_t)*reinterpret_cast<int*>(x + 0x0C);
                        out->face       = (uint8_t)*reinterpret_cast<int*>(x + 0x10);
                        out->hairStyle  = (uint8_t)*reinterpret_cast<int*>(x + 0x14);
                        out->hairColor  = (uint8_t)*reinterpret_cast<int*>(x + 0x18);
                        out->facialHair = (uint8_t)*reinterpret_cast<int*>(x + 0x1C);
                        // CDIExtra m_npcitemDisplay[11] @ +0x20 — the NPC's BAKED gear
                        // (ItemDisplayInfo ids). The select doll builds as a clean race
                        // character, so without these an NPC morph shows NAKED. Carry
                        // them out so the caller can dress the doll like the NPC.
                        for (int i = 0; i < 11; ++i)
                            out->npcItems[i] = *reinterpret_cast<int32_t*>(x + 0x20 + i * 4);
                        out->fromExtra = true;
                        return true;
                    }
                } __except (EXCEPTION_EXECUTE_HANDLER) {}
            }
        }

        // 2) ChrRaces fallback (bare race display id with no extra record)
        for (int id = 1; id <= 15; ++id) {
            void* rec = DbRecord(g_chrRacesDB, id);
            if (!rec) continue;
            uint32_t male = 0, female = 0;
            __try {
                male   = *reinterpret_cast<uint32_t*>(reinterpret_cast<uint8_t*>(rec) + 0x10);
                female = *reinterpret_cast<uint32_t*>(reinterpret_cast<uint8_t*>(rec) + 0x14);
            } __except (EXCEPTION_EXECUTE_HANDLER) { continue; }
            if (displayId == male || displayId == female) {
                out->race = (uint8_t)id; out->gender = (displayId == female) ? 1 : 0;
                out->skin = 0; out->face = 0; out->hairStyle = 0; out->hairColor = 0; out->facialHair = 0;
                return true;
            }
        }
        return false;
    }

    // Wrap SelectCharacter: morph the selected entry, build, then restore.
    void __cdecl hkSelectCharacter() {
        const uint32_t kHidden = 0xFFFFFFFFu;
        uint8_t* e = nullptr;
        bool raceChanged = false;
        uint8_t  savedAppear[8] = {0};        // +0x178..+0x17f
        uint32_t savedItems[19] = {0};
        bool     savedItemMask[19] = {false};

        if (!g_isProcessTerminating) {
            __try {
                int idx = *g_charSelected, count = *g_charCount;
                uint8_t* arr = *g_charListPtr;
                if (arr && idx >= 0 && idx < count) {
                    e = arr + (size_t)idx * 0x198;
                    uint64_t guid = *reinterpret_cast<uint64_t*>(e);
                    uint32_t disp = 0, items[20] = {0};
                    // Always enter the customization block. Morph-specific parts self-guard on
                    // disp/items being non-zero, so a character that has ONLY a barber look (no
                    // morph/transmog) still gets it on the doll — previously barber was gated
                    // behind a morph file existing, so barber-only chars showed nothing.
                    ReadMorphFileForGuid(guid, &disp, items);
                    {
                        // SKIN: pull the persisted per-slot skin+tint so the doll
                        // renders with the same colors and donor item the user set
                        // in the world. Applied in the morph loop below, after
                        // transmog has set the slot's display id.
                        uint32_t skin[20] = {0};
                        SlotSkinTint skinTint[20] = {};
                        ReadSkinFileForGuid(guid, skin, skinTint);

                        // RACE / HUMANOID-NPC: derive the morph's own race+appearance
                        // from its CDIExtra so the doll builds as that character and
                        // wears the gear. (True non-character creatures are skipped.)
                        DollAppearance ap = {0};
                        if (ResolveDollAppearance(disp, &ap)) {
                            memcpy(savedAppear, e + 0x178, 8);   // +0x178..+0x17f
                            e[0x178] = ap.race;        // race
                            // e[0x179] = class — left untouched
                            e[0x17a] = ap.gender;      // gender
                            e[0x17b] = ap.skin;        // skin
                            e[0x17c] = ap.face;        // face
                            e[0x17d] = ap.hairStyle;   // hair style
                            e[0x17e] = ap.hairColor;   // hair color
                            e[0x17f] = ap.facialHair;  // facial hair
                            raceChanged = true;
                        }
                        // BARBER: overlay the user's saved base-model customization
                        // (skin/face/hairStyle/hairColor/facialHair) on the doll, from
                        // the same per-guid state file. Overrides on top of whatever
                        // race the doll resolved to (native or a morph's); race/gender/
                        // class are left intact. Reuses the savedAppear restore path so
                        // the character list stays truthful for the next select.
                        {
                            uint8_t bSk = 0, bFc = 0, bHr = 0, bHc = 0, bFh = 0;
                            if (ReadBarberFileForGuid(guid, &bSk, &bFc, &bHr, &bHc, &bFh)) {
                                if (!raceChanged) memcpy(savedAppear, e + 0x178, 8);
                                e[0x17b] = bSk;   // skin
                                e[0x17c] = bFc;   // face
                                e[0x17d] = bHr;   // hair style
                                e[0x17e] = bHc;   // hair color
                                e[0x17f] = bFh;   // facial hair
                                raceChanged = true;
                            }
                        }
                        // BARBER COLORS: replay the saved free-RGB recolor onto the doll so the
                        // character-select screen shows the same colors as in the world. The
                        // addon isn't running at the glue screen, so without this the colors
                        // only appeared after a world round-trip pushed them. Clear any tints
                        // left by a previously-selected doll first, then register this
                        // character's regions against the doll's actual race/sex + barber bytes.
                        ColorEngine::ClearBarberRegionTints();
                        {
                            SlotSkinTint bt[4] = {};
                            if (ReadBarberTintFileForGuid(guid, bt)) {
                                int dRace  = e[0x178], dSex = e[0x17a], dClass = e[0x179];
                                uint8_t bSk = e[0x17b], bFc = e[0x17c], bHr = e[0x17d], bHc = e[0x17e], bFh = e[0x17f];
                                for (int rg = 0; rg < 4; ++rg) {
                                    const SlotSkinTint& t = bt[rg];
                                    if (!t.enabled) continue;
                                    ColorEngine::SetBarberRegionTint(rg, dRace, dSex, dClass, bSk, bFc, bHr, bHc, bFh,
                                        true, (int)t.mode, t.r, t.g, t.b, t.r2, t.g2, t.b2,
                                        (int)t.dir, (int)t.mult, (int)t.glowStr, (int)t.contrast,
                                        (int)t.span, (int)t.phase, (int)t.brightness, (int)t.saturation, (int)t.hueShift);
                                }
                            }
                        }
                        // NPC BAKED GEAR: an NPC morph's armor lives in its CDIExtra
                        // m_npcitemDisplay[11], not in equipped items — so dress the doll
                        // with it, else the NPC shows naked on the select screen. Map each
                        // NPC item slot to the doll's per-slot display array (+0x50, indexed
                        // by equip slot: 0=head,2=shoulder,3=shirt,4=chest,5=waist,6=legs,
                        // 7=feet,8=wrist,9=hands,14=back,18=tabard). Save originals so the
                        // list stays truthful for login; user transmog (below) overrides.
                        if (ap.fromExtra) {
                            static const int kNpcToDoll[11] = { 0, 2, 3, 4, 5, 6, 7, 8, 9, 18, 14 };
                            for (int n = 0; n < 11; ++n) {
                                uint32_t d2 = (uint32_t)ap.npcItems[n];
                                if (d2 == 0) continue;
                                int di = kNpcToDoll[n];
                                uint32_t* slot = reinterpret_cast<uint32_t*>(e + 0x50 + (size_t)di * 4);
                                if (!savedItemMask[di]) { savedItems[di] = *slot; savedItemMask[di] = true; }
                                *slot = d2;
                            }
                        }
                        // TRANSMOG: morph slot s (1..19) -> equip slot (s-1) @ +0x50.
                        // Applied AFTER the NPC gear so an explicit transmog/hide wins.
                        for (int s = 1; s <= 19; ++s) {
                            uint32_t it = items[s];
                            if (it == 0) continue;
                            uint32_t d2 = (it == kHidden) ? 0 : DisplayIdFromItem(it);
                            if (it != kHidden && d2 == 0) continue;  // unresolved -> keep original
                            uint32_t* slot = reinterpret_cast<uint32_t*>(e + 0x50 + (size_t)(s - 1) * 4);
                            if (!savedItemMask[s - 1]) { savedItems[s - 1] = *slot; savedItemMask[s - 1] = true; }
                            *slot = d2;
                        }
                        // SKIN+TINT: apply the persisted skin (donor item id) and
                        // tint to each slot's now-morphed display id. The doll has
                        // no live item record, so we use the display-id variants
                        // of the retex/tint APIs (keyed on 0x80000000|disp). The
                        // retex and tint writes to the global ItemDisplayInfo in
                        // memory, so the doll picks them up on its next render.
                        for (int s = 1; s <= 19; ++s) {
                            uint32_t toId = skin[s];
                            uint32_t dispId = *reinterpret_cast<uint32_t*>(e + 0x50 + (size_t)(s - 1) * 4);
                            if (dispId == 0) continue;
                            if (toId > 0) {
                                if (toId != kHidden) {
                                    uint32_t toDisp = DisplayIdFromItem(toId);
                                    if (toDisp != 0 && toDisp != dispId)
                                        ColorEngine::ItemRetexAddDisplay(dispId, toId);
                                }
                            }
                            if (skinTint[s].enabled) {
                                ColorEngine::ItemTintSlotSetDisplay(
                                    (uint32_t)s, dispId,
                                    (int)skinTint[s].mode,
                                    skinTint[s].r, skinTint[s].g, skinTint[s].b,
                                    skinTint[s].r2, skinTint[s].g2, skinTint[s].b2,
                                    (int)skinTint[s].dir, (int)skinTint[s].mult,
                                    (int)skinTint[s].glowStr, (int)skinTint[s].contrast,
                                    (int)skinTint[s].span, (int)skinTint[s].phase,
                                    (int)skinTint[s].brightness, (int)skinTint[s].saturation,
                                    (int)skinTint[s].hueShift);
                            }
                        }
                    }
                }
            } __except (EXCEPTION_EXECUTE_HANDLER) { e = nullptr; }
        }

        oSelectCharacter();   // builds the (now morphed) doll, caches it at +0x188

        if (e) {
            __try {
                if (raceChanged) memcpy(e + 0x178, savedAppear, 8);
                for (int i = 0; i < 19; ++i)
                    if (savedItemMask[i])
                        *reinterpret_cast<uint32_t*>(e + 0x50 + (size_t)i * 4) = savedItems[i];
            } __except (EXCEPTION_EXECUTE_HANDLER) {}
        }
    }

    // Force the currently-selected character-select doll to rebuild through our hook so it
    // reflects the persisted look. SelectCharacter only (re)builds when the per-entry cached
    // model (entry+0x188) is null; at a COLD game launch the doll is built and cached once
    // before our customization ran, so it stayed un-customized until a world round-trip freed
    // the list. We null that cached pointer to force a fresh build, then invoke the hooked
    // SelectCharacter. Orphaning one model object is a bounded, crash-free leak (we null it,
    // so the engine never double-frees). Call ONLY at the glue screen, on the main thread.
    void RebuildSelectedDoll() {
        if (g_isProcessTerminating) return;
        __try {
            int idx = *g_charSelected, count = *g_charCount;
            uint8_t* arr = *g_charListPtr;
            if (!arr || idx < 0 || idx >= count) return;
            uint8_t* e = arr + (size_t)idx * 0x198;
            *reinterpret_cast<uint32_t*>(e + 0x188) = 0;   // drop cached doll -> force rebuild
        } __except (EXCEPTION_EXECUTE_HANDLER) { return; }
        hkSelectCharacter();   // hooked path: injects the saved look, rebuilds, restores
    }

    void __fastcall hkSetParticleColors(void* This, void* edx, uint32_t* start, uint32_t* mid, uint32_t* end) {
        if (g_particleTintActive && !g_isProcessTerminating && start && mid && end) {
            uint32_t s = TintCImVector(*start);
            uint32_t m = TintCImVector(*mid);
            uint32_t e = TintCImVector(*end);
            oSetParticleColors(This, edx, &s, &m, &e);
            return;
        }
        oSetParticleColors(This, edx, start, mid, end);
    }

    // SEH-only helper (no C++ objects): copy the texture object's name field out.
    static bool ReadTexObjName(void* texObj, char* out, size_t outSz) {
        __try {
            const char* nm = reinterpret_cast<const char*>(reinterpret_cast<uint8_t*>(texObj) + 0x6C);
            if (!nm[0]) return false;
            strncpy_s(out, outSz, nm, _TRUNCATE);
            return true;
        } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
    }
    // Capture a model-item texture object (helmet/shoulder/cape/weapon) as it (re)loads,
    // keyed by its normalized real .blp path, so a reset can force it to re-decode clean.
    static void OnModelTexLoad(void* texObj) {
        if (!texObj || g_isProcessTerminating) return;
        char nm[260];
        if (!ReadTexObjName(texObj, nm, sizeof(nm))) return;
        if (!ContainsCI(nm, "OBJECTCOMPONENTS")) return;
        char buf[260]; _snprintf_s(buf, sizeof(buf), _TRUNCATE, "%s.blp", nm);
        char norm[260]; NormalizeTexPath(buf, norm, sizeof(norm));
        if (!norm[0]) return;
        AcquireSRWLockExclusive(&g_modelTexLock);
        if (g_modelTexByName.size() > 1024) g_modelTexByName.clear();   // safety bound
        g_modelTexByName[norm] = texObj;
        ReleaseSRWLockExclusive(&g_modelTexLock);
    }
    // SEH-only helper: invoke the engine's texture reload, isolated from C++ unwinding.
    static int SafeReloadTexObj(void* texObj) {
        __try { return oReloadTexture(texObj); } __except (EXCEPTION_EXECUTE_HANDLER) { return -1; }
    }

    // Verify a captured CTexture* is STILL the live texture for `expectedNorm` before we
    // reload it. g_modelTexByName holds RAW pointers captured at LoadFromFile time and is
    // never pruned when the engine frees a CTexture (a model unload), so an entry can point
    // at memory that has since been freed and recycled for an unrelated object. The page is
    // usually still mapped, so the SEH guard around CTexture::Reload does NOT catch it —
    // instead Reload runs over a garbage object and frees/reallocs garbage internal buffers,
    // corrupting the heap free list. That corruption surfaces LATER as an ACCESS_VIOLATION
    // inside an unrelated allocation (e.g. SetPortraitTexture) — the Skin-tab "Reset" crash.
    // Re-reading the object's own name field (offset 0x6C) and confirming it still maps to
    // the same normalized path is a cheap liveness check: a freed/recycled slot will not
    // carry the same OBJECTCOMPONENTS path. SEH-guarded via ReadTexObjName.
    static bool TexObjStillMatches(void* texObj, const char* expectedNorm) {
        if (!texObj || !expectedNorm || !expectedNorm[0]) return false;
        char nm[260];
        if (!ReadTexObjName(texObj, nm, sizeof(nm))) return false;
        char buf[260]; _snprintf_s(buf, sizeof(buf), _TRUNCATE, "%s.blp", nm);
        char norm[260]; NormalizeTexPath(buf, norm, sizeof(norm));
        if (!norm[0]) return false;
        return _stricmp(norm, expectedNorm) == 0;
    }

    // CTexture::LoadFromFile takes `this` in EAX and one stack arg; tail-call the original.
    __declspec(naked) static int hkTexLoadFromFile() {
        __asm {
            pushad
            mov  eax, [esp + 0x1c]   // saved EAX = this (CTexture*)
            push eax
            call OnModelTexLoad
            add  esp, 4
            popad
            jmp  oTexLoadFromFile    // run the original (Detours trampoline), EAX/stack intact
        }
    }
}

namespace ColorEngine {

static void RetexTexSet(const char* fromNorm, const char* toNorm); // defined below
static void RetexTexErase(const char* fromNorm);                  // defined below
static void TintTexSet(const char* virtualNorm, const TextureTint& tint); // defined below
static void TintTexErase(const char* virtualNorm);                // defined below

// Real per-race/gender customization counts from the char DBCs (RE-verified offsets).
//   skin      = distinct skin colors  (CharSections section 0, Variation=0, max Color+1)
//   face      = face types            (CharSections section 1, max Variation+1)
//   hairColor = hair colors           (CharSections section 3, max Color+1)
//   hairStyle = hairstyles            (CharHairGeosets,        max VariationID+1)
//   facial    = facial-hair styles    (CharFacialHair,         max VariationID+1)
// Any count that comes back 0 (table not loaded for that race/sex) is left for the
// caller to treat as "unknown" and fall back to a default.
// Public wrapper: force the selected character-select doll to rebuild through our hook so
// it shows the persisted look on a cold game launch (called from the glue-screen timer).
void ForceRefreshCharSelectDoll() { RebuildSelectedDoll(); }

void GetBarberMaxes(int race, int sex, int* outSkin, int* outFace,
                    int* outHairStyle, int* outHairColor, int* outFacial) {
    if (outSkin)      *outSkin      = CountBarberOptionsFiltered(g_charSectionsDB, race, sex, 0, 0x20, 0, 0x24);
    if (outFace)      *outFace      = CountBarberOptions(g_charSectionsDB, race, sex, 0x0C, 1, 0x20);
    if (outHairColor) *outHairColor = CountBarberOptions(g_charSectionsDB, race, sex, 0x0C, 3, 0x24);
    if (outHairStyle) *outHairStyle = CountBarberOptionsAt(g_charHairGeoDB, 0x18, race, sex, 0x04, 0x08, -1, 0, 0x0C);
    if (outFacial)    *outFacial    = CountBarberOptionsAt(g_charFacialDB,  0x20, race, sex, 0x00, 0x04, -1, 0, 0x08);
}

void GetBarberValueLists(int race, int sex, int classId,
                         int skinIdx, int faceIdx, int hairStyleIdx, int hairColorIdx, int facialIdx,
                         char* outSkin, size_t skinSz,
                         char* outFace, size_t faceSz,
                         char* outHairStyle, size_t hairStyleSz,
                         char* outHairColor, size_t hairColorSz,
                         char* outFacial, size_t facialSz) {
    std::vector<int> vals;

    CollectCharSectionValues(race, sex, classId, 0, 0, true, 0, false, 0x24, vals);
    if (faceIdx >= 0) FilterValuesByCharSection(vals, race, sex, classId, 1, false, faceIdx);
    WriteValueCsv(vals, outSkin, skinSz);

    CollectCharSectionValues(race, sex, classId, 1, 0, false, skinIdx, true, 0x20, vals);
    WriteValueCsv(vals, outFace, faceSz);

    CollectBarberValuesAt(g_charHairGeoDB, 0x18, race, sex, 0x04, 0x08, -1, 0, -1, 0, 0x0C, vals);
    if (hairColorIdx >= 0) FilterValuesByCharSection(vals, race, sex, classId, 3, true, hairColorIdx);
    WriteValueCsv(vals, outHairStyle, hairStyleSz);

    CollectCharSectionValues(race, sex, classId, 3, hairStyleIdx, true, 0, false, 0x24, vals);
    WriteValueCsv(vals, outHairColor, hairColorSz);

    CollectBarberValuesAt(g_charFacialDB, 0x20, race, sex, 0x00, 0x04, -1, 0, -1, 0, 0x08, vals);
    WriteValueCsv(vals, outFacial, facialSz);
}

bool ResolveDisplayCharacterAppearance(uint32_t displayId,
                                       int* outRace, int* outSex,
                                       int* outSkin, int* outFace,
                                       int* outHairStyle, int* outHairColor,
                                       int* outFacial, bool* outFromExtra) {
    DollAppearance ap = {};
    if (!::ResolveDollAppearance(displayId, &ap)) return false;
    if (outRace)      *outRace      = ap.race;
    if (outSex)       *outSex       = ap.gender;
    if (outSkin)      *outSkin      = ap.skin;
    if (outFace)      *outFace      = ap.face;
    if (outHairStyle) *outHairStyle = ap.hairStyle;
    if (outHairColor) *outHairColor = ap.hairColor;
    if (outFacial)    *outFacial    = ap.facialHair;
    if (outFromExtra) *outFromExtra = ap.fromExtra;
    return true;
}

// ---- Barber free-RGB BLP recolor of the player's body/hair textures ----------
// Per region (0 skin, 1 face, 2 hair, 3 facial) we read the ACTUAL character
// texture filenames straight from the loaded CharSections records (TextureName1/2/3
// @ +0x10/+0x14/+0x18, RE-verified) for the player's race+sex+section+current color
// index, then register the SAME tint the Skin tab uses (mode/gradient/rainbow/glow/
// brightness/saturation/hue) on those exact BLP paths via the body-component SFile
// read pipeline (SfileTintLookup matches on the real path AND its basename, so the
// character compositor's component reads get recoloured in place — no redirect, no
// virtual key). A model rebuild re-bakes the body so it shows. Fully data-driven:
// the paths come from the game's own DBC, nothing is hard-coded.
struct BarberRegionState {
    std::vector<std::string> sfileKeys;
    std::vector<std::string> tintKeys;
    std::vector<std::string> redirectKeys;
    bool active = false;
};
static BarberRegionState g_barberRegion[4];

static void ClearBarberRegionInternal(int region) {
    if (region < 0 || region > 3) return;
    BarberClearPathRegion(region);
    // Keep reverse TM_CTINT_* -> real redirects alive; a cached virtual CTexture can
    // still ask SFile for its source while the model is being rebuilt. This matches the
    // working Skin-tab reset path and avoids stale virtual-key load failures.
    for (auto& k : g_barberRegion[region].redirectKeys) {
        if (!IsVirtualComponentKey(k.c_str())) RetexTexErase(k.c_str());
    }
    for (auto& k : g_barberRegion[region].tintKeys)  TintTexErase(k.c_str());
    for (auto& k : g_barberRegion[region].sfileKeys) SfileTintErase(k.c_str());
    g_barberRegion[region].redirectKeys.clear();
    g_barberRegion[region].tintKeys.clear();
    g_barberRegion[region].sfileKeys.clear();
    g_barberRegion[region].active = false;
}

void ClearBarberRegionTints() {
    for (int r = 0; r < 4; ++r) ClearBarberRegionInternal(r);
}

// region -> CharSections rows exactly as CGCharacterModelBase indexes them in
// wow.exe (0x004EA0B0 / 0x004EA1F0 call sites). CharSections fields after the
// three texture names are Flags@+0x1C, Type@+0x20, Color@+0x24, but the meaning
// of Type/Color is section-specific:
//   0 skin   : section 0, Type=0,         Color=skin
//              section 4, Type=0,         Color=skin  (naked pelvis/torso overlay)
//   1 face   : section 1, Type=face,      Color=skin
//   2 hair   : section 3, Type=hairStyle, Color=hairColor
//   3 facial : section 2, Type=facial,    Color=hairColor
void SetBarberRegionTint(int region, int race, int sex, int classId,
                         int skinIdx, int faceIdx, int hairStyleIdx, int hairColorIdx, int facialIdx,
                         bool enable,
                         int mode, uint8_t r, uint8_t g, uint8_t b,
                         uint8_t r2, uint8_t g2, uint8_t b2,
                         int dir, int multX100, int glowStr, int contrast,
                          int rainbowSpanX100, int phase,
                          int brightness, int saturation, int hueShift) {
    if (region < 0 || region > 3) return;
    ClearBarberRegionInternal(region);
    if (!enable || race <= 0 || !g_charSectionsDB) return;

    struct RowFilter { int section; int type; int color; } filters[4] = {};
    int filterCount = 1;
    switch (region) {
        case 0:
            filters[0] = { 0, 0, skinIdx };  // base body skin
            filters[1] = { 4, 0, skinIdx };  // naked pelvis/torso overlay, skin-tone-owned
            filterCount = 2;
            break;
        case 1: filters[0] = { 1, faceIdx,      skinIdx      }; break;
        case 2: filters[0] = { 3, hairStyleIdx, hairColorIdx }; break;
        case 3: filters[0] = { 2, facialIdx,    hairColorIdx }; break;
        default: return;
    }
    TextureTint t = {};
    t.r = r; t.g = g; t.b = b;
    t.multX100 = (multX100 < 0) ? 0 : (multX100 > 400 ? 400 : multX100);
    t.mode = mode;
    t.r2 = r2; t.g2 = g2; t.b2 = b2;
    t.dir = dir;
    t.glowStr = (glowStr < 0) ? 0 : (glowStr > 255 ? 255 : glowStr);
    t.contrast = (contrast <= 0) ? 100 : (contrast > 400 ? 400 : contrast);
    t.rainbowSpanX100 = (rainbowSpanX100 > 0) ? rainbowSpanX100 : 100;
    t.phase = phase & 0xFF;
    t.rainbow = (mode == 2);
    t.glow = (t.glowStr > 0);
    t.brightness = (brightness < 0) ? 0 : (brightness > 255 ? 255 : brightness);
    t.saturation = (saturation < -100) ? -100 : (saturation > 100 ? 100 : saturation);
    t.hueShift = hueShift & 0xFF;

    int maxId = 0, minId = 0;
    __try {
        uint8_t* db = reinterpret_cast<uint8_t*>(g_charSectionsDB);
        maxId = *reinterpret_cast<int*>(db + 0x0C);
        minId = *reinterpret_cast<int*>(db + 0x10);
    } __except (EXCEPTION_EXECUTE_HANDLER) { return; }
    void* charSectionRecords = nullptr;
    int charSectionCount = 0;
    if (!DbRecords(g_charSectionsDB, &charSectionRecords, &charSectionCount)) return;
    if (maxId < minId || (maxId - minId) > 1000000) return;

    // SEH-only string copy (no C++ objects) — guards a possibly-bad DBC pointer.
    auto safeCopy = [](const char* nm, char* out, size_t sz) -> bool {
        if (!nm || (uintptr_t)nm < 0x10000) { if (sz) out[0] = 0; return false; }
        __try { strncpy_s(out, sz, nm, _TRUNCATE); return out[0] != 0; }
        __except (EXCEPTION_EXECUTE_HANDLER) { if (sz) out[0] = 0; return false; }
    };
    auto rememberSfile = [&](const char* normKey) {
        if (!normKey || !normKey[0]) return;
        SfileTintSet(normKey, t);
        g_barberRegion[region].sfileKeys.emplace_back(normKey);
    };
    auto rememberTint = [&](const char* normKey, const TextureTint& tint) {
        if (!normKey || !normKey[0]) return;
        TintTexSet(normKey, tint);
        g_barberRegion[region].tintKeys.emplace_back(normKey);
    };
    auto rememberRedirect = [&](const char* fromNorm, const char* toNorm) {
        if (!fromNorm || !toNorm || !fromNorm[0] || !toNorm[0]) return;
        RetexTexSet(fromNorm, toNorm);
        g_barberRegion[region].redirectKeys.emplace_back(fromNorm);
    };

    // C++-object work (std::string) kept OUTSIDE any __try (C2712).
    auto registerRealBlp = [&](const char* normReal) {
        if (!normReal || !normReal[0]) return;
        // Barber tint paths must be real character-body textures. Never register bare
        // filenames or ITEM\ paths, otherwise SFile basename fallback can recolor gear
        // that happens to share a texture name.
        if (!IsCharacterTexPath(normReal)) return;
        BarberAddPathMatcher(region, normReal, t);

        // Direct SFile fallback — only the full path, NEVER the bare filename.
        // Basename-only entries caused "color leaking to random stuff" by matching
        // unrelated textures that happen to share a filename (see line ~749 comment).
        rememberSfile(normReal);

        LONG serial = InterlockedIncrement(&g_tintSerial);
        char virt[220], normVirt[220];
        _snprintf_s(virt, sizeof(virt), _TRUNCATE, "TM_CTINT_BARBER_R%d_%ld.blp", region, serial);
        NormalizeTexPath(virt, normVirt, sizeof(normVirt));
        if (!normVirt[0] || _stricmp(normReal, normVirt) == 0) return;

        // Cache-busted path: real CharSections BLP -> unique virtual key. The virtual
        // key opens the real BLP through the reverse redirect while carrying the tint.
        rememberSfile(normVirt);
        TextureTint decodeTint = t;
        strncpy_s(decodeTint.realPath, sizeof(decodeTint.realPath), normReal, _TRUNCATE);
        rememberTint(normVirt, decodeTint);
        rememberRedirect(normReal, normVirt);
        rememberRedirect(normVirt, normReal);
    };

    auto registerCandidate = [&](const char* rawName) {
        char norm[220];
        NormalizeTexPath(rawName, norm, sizeof(norm));
        if (!norm[0]) return;

        char withBlp[260];
        if (strchr(norm, '\\')) {
            if (HasBlpExt(norm)) _snprintf_s(withBlp, sizeof(withBlp), _TRUNCATE, "%s", norm);
            else _snprintf_s(withBlp, sizeof(withBlp), _TRUNCATE, "%s.BLP", norm);
        } else {
            const char* raceDir = CharacterRaceDir(race);
            if (!raceDir) return;
            if (HasBlpExt(norm)) {
                _snprintf_s(withBlp, sizeof(withBlp), _TRUNCATE,
                            "CHARACTER\\%s\\%s\\%s", raceDir, CharacterSexDir(sex), norm);
            } else {
                _snprintf_s(withBlp, sizeof(withBlp), _TRUNCATE,
                            "CHARACTER\\%s\\%s\\%s.BLP", raceDir, CharacterSexDir(sex), norm);
            }
        }
        registerRealBlp(withBlp);
    };

    auto registerName = [&](const char* raw) {
        char nameBuf[200];
        if (!safeCopy(raw, nameBuf, sizeof(nameBuf))) return;
        registerCandidate(nameBuf);
    };

    // Read the matching rows' texture pointers under SEH (no C++ objects here), then
    // register them outside the guard.
    auto rowTextures = [&](void* rec, const char** o0, const char** o1, const char** o2) -> bool {
        *o0 = *o1 = *o2 = nullptr;
        __try {
            uint8_t* p = reinterpret_cast<uint8_t*>(rec);
            if (*reinterpret_cast<int*>(p + 0x04) != race) return false;
            if (*reinterpret_cast<int*>(p + 0x08) != sex)  return false;
            int sec = *reinterpret_cast<int*>(p + 0x0C);
            int flg = *reinterpret_cast<int*>(p + 0x1C);
            int typ = *reinterpret_cast<int*>(p + 0x20);
            int col = *reinterpret_cast<int*>(p + 0x24);
            if (!CharSectionFlagsAllowed(flg, sec, classId)) return false;
            bool match = false;
            for (int i = 0; i < filterCount; ++i) {
                if (sec == filters[i].section && typ == filters[i].type && col == filters[i].color) {
                    match = true;
                    break;
                }
            }
            if (!match) return false;
            *o0 = *reinterpret_cast<const char**>(p + 0x10);
            *o1 = *reinterpret_cast<const char**>(p + 0x14);
            *o2 = *reinterpret_cast<const char**>(p + 0x18);
            return true;
        } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
    };

    for (int i = 0; i < charSectionCount; ++i) {
        void* rec = reinterpret_cast<uint8_t*>(charSectionRecords) + (i * 0x28);
        const char *n0 = nullptr, *n1 = nullptr, *n2 = nullptr;
        if (!rowTextures(rec, &n0, &n1, &n2)) continue;
        registerName(n0); registerName(n1); registerName(n2);
    }
    g_barberRegion[region].active = !g_barberRegion[region].sfileKeys.empty() ||
                                     !g_barberRegion[region].tintKeys.empty();
}

void Initialize() {
    if (g_hooksInstalled) return;
    LONG status = DetourTransactionBegin();
    if (status != NO_ERROR) return;
    DetourUpdateThread(GetCurrentThread());
    DetourAttach(&(PVOID&)oTextureCacheGetTexture, hkTextureCacheGetTexture);
    DetourAttach(&(PVOID&)oTextureCacheGetTextureEx, hkTextureCacheGetTextureEx);
    DetourAttach(&(PVOID&)oBLPFileLockChain2, hkBLPFileLockChain2);
    DetourAttach(&oTexLoadFromFile, (PVOID)hkTexLoadFromFile);   // capture model-item texobjs
    DetourAttach(&(PVOID&)oTextureLoadImage, hkTextureLoadImage);
    DetourAttach(&(PVOID&)oCompositeTexGet, hkCompositeTexGet);
    DetourAttach(&(PVOID&)oSFileOpen, hkSFileOpen);
    DetourAttach(&(PVOID&)oSFileRead, hkSFileRead);
    DetourAttach(&(PVOID&)oHandleFree, hkHandleFree);
    DetourAttach(&(PVOID&)oSetParticleColors, hkSetParticleColors);
    DetourAttach(&(PVOID&)oLightSet, hkLightSet);
    DetourAttach(&(PVOID&)oSetColors, hkSetColors);
    DetourAttach(&(PVOID&)oWorldTextCreate, hkWorldTextCreate);
    DetourAttach(&(PVOID&)oWTUpdate, hkWTUpdate);
    DetourAttach(&(PVOID&)oSelectCharacter, hkSelectCharacter);  // glue char-select morph
    DetourAttach(&(PVOID&)oSetBlendSky, hkSetBlendSky);
    DetourAttach(&(PVOID&)g_oGetSheatheType, (PVOID)Morpher_hkGetSheatheType);  // weapon sheath position
    // Composite-owner gate: identify the unit being composited so player skin/hair/body
    // recolors stay on the LOCAL player only (no leak onto other players / NPCs).
    DetourAttach(&(PVOID&)oPlayerCharBuild, hkPlayerCharBuild);
    DetourAttach(&(PVOID&)oUnitCharBuild, hkUnitCharBuild);
    DetourAttach(&(PVOID&)oItemCompBake, hkItemCompBake);
    DetourAttach(&(PVOID&)oUpdateDisplayInfo, hkUpdateDisplayInfo);
    status = DetourTransactionCommit();
    g_hooksInstalled = (status == NO_ERROR);
    Log("[ColorEngine] hooks %s", g_hooksInstalled ? "installed" : "FAILED");
}

void Shutdown() {
    if (!g_hooksInstalled) return;
    DetourTransactionBegin();
    DetourUpdateThread(GetCurrentThread());
    DetourDetach(&(PVOID&)oTextureCacheGetTexture, hkTextureCacheGetTexture);
    DetourDetach(&(PVOID&)oTextureCacheGetTextureEx, hkTextureCacheGetTextureEx);
    DetourDetach(&(PVOID&)oBLPFileLockChain2, hkBLPFileLockChain2);
    DetourDetach(&oTexLoadFromFile, (PVOID)hkTexLoadFromFile);
    DetourDetach(&(PVOID&)oTextureLoadImage, hkTextureLoadImage);
    DetourDetach(&(PVOID&)oCompositeTexGet, hkCompositeTexGet);
    DetourDetach(&(PVOID&)oSFileOpen, hkSFileOpen);
    DetourDetach(&(PVOID&)oSFileRead, hkSFileRead);
    DetourDetach(&(PVOID&)oHandleFree, hkHandleFree);
    DetourDetach(&(PVOID&)oSetParticleColors, hkSetParticleColors);
    DetourDetach(&(PVOID&)oLightSet, hkLightSet);
    DetourDetach(&(PVOID&)oSetColors, hkSetColors);
    DetourDetach(&(PVOID&)oWorldTextCreate, hkWorldTextCreate);
    DetourDetach(&(PVOID&)oWTUpdate, hkWTUpdate);
    DetourDetach(&(PVOID&)oSelectCharacter, hkSelectCharacter);
    DetourDetach(&(PVOID&)oSetBlendSky, hkSetBlendSky);
    DetourDetach(&(PVOID&)g_oGetSheatheType, (PVOID)Morpher_hkGetSheatheType);
    DetourDetach(&(PVOID&)oPlayerCharBuild, hkPlayerCharBuild);
    DetourDetach(&(PVOID&)oUnitCharBuild, hkUnitCharBuild);
    DetourDetach(&(PVOID&)oItemCompBake, hkItemCompBake);
    DetourDetach(&(PVOID&)oUpdateDisplayInfo, hkUpdateDisplayInfo);
    DetourTransactionCommit();
    g_hooksInstalled = false;
}

void TexSwapAdd(const char* fromPath, const char* toPath) {
    if (!fromPath || !toPath || !fromPath[0] || !toPath[0]) return;
    char norm[300];
    NormalizeTexPath(fromPath, norm, sizeof(norm));
    AcquireSRWLockExclusive(&g_texLock);
    g_texMap[norm] = toPath;
    InterlockedExchange(&g_texActive, (LONG)g_texMap.size());
    ReleaseSRWLockExclusive(&g_texLock);
    if (g_diagTexOn) Log("[ColorEngine] texswap '%s' -> '%s'", norm, toPath);
}

void TexSwapRemove(const char* fromPath) {
    if (!fromPath) return;
    char norm[300];
    NormalizeTexPath(fromPath, norm, sizeof(norm));
    AcquireSRWLockExclusive(&g_texLock);
    g_texMap.erase(norm);
    InterlockedExchange(&g_texActive, (LONG)g_texMap.size());
    ReleaseSRWLockExclusive(&g_texLock);
}

void TexSwapClear() {
    AcquireSRWLockExclusive(&g_texLock);
    g_texMap.clear();
    InterlockedExchange(&g_texActive, 0);
    ReleaseSRWLockExclusive(&g_texLock);
}

void SetFogColor(bool enable, uint8_t r, uint8_t g, uint8_t b, float start, float end) {
    if (g_isProcessTerminating) return;
    __try {
        if (!enable) {
            pClearOverrideFog();
            return;
        }
        // CImVector packs as little-endian B,G,R,A.
        uint32_t color = (uint32_t)b | ((uint32_t)g << 8) | ((uint32_t)r << 16) | (0xFFu << 24);
        if (start < 0.0f) start = 0.0f;
        if (end <= start) end = start + 0.1f;
        pSetOverrideFog(start, end, color, 1);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        Log("[ColorEngine] SetFogColor exception");
    }
}

void SetParticleTint(bool enable, uint8_t r, uint8_t g, uint8_t b) {
    InterlockedExchange(&g_ptR, r);
    InterlockedExchange(&g_ptG, g);
    InterlockedExchange(&g_ptB, b);
    InterlockedExchange(&g_particleTintActive, enable ? 1 : 0);
}

void SetModelTint(bool enable, uint8_t r, uint8_t g, uint8_t b) {
    InterlockedExchange(&g_mtR, r);
    InterlockedExchange(&g_mtG, g);
    InterlockedExchange(&g_mtB, b);
    InterlockedExchange(&g_modelTintActive, enable ? 1 : 0);
}

void SetWorldColorTint(bool enable, uint8_t r, uint8_t g, uint8_t b) {
    InterlockedExchange(&g_wtR, r);
    InterlockedExchange(&g_wtG, g);
    InterlockedExchange(&g_wtB, b);
    InterlockedExchange(&g_worldTintActive, enable ? 1 : 0);
    // Force an immediate recompute so the change is visible at once. oSetColors
    // restores the natural values; if enabling, re-apply the tint on top.
    if (g_hooksInstalled && !g_isProcessTerminating) {
        __try {
            oSetColors();
            if (enable) ApplyWorldTintToGlobals();
        } __except (EXCEPTION_EXECUTE_HANDLER) {}
    }
}

// Force the client to recompute the natural world colors now, then re-stack our
// overrides so a change is visible immediately (not only on the next light tick).
static void ForceWorldRecompute() {
    if (!g_hooksInstalled || g_isProcessTerminating) return;
    __try {
        oSetColors();
        if (g_wlActive)        ApplyWorldLightToGlobals();
        if (g_worldTintActive) ApplyWorldTintToGlobals();
        if (g_brightActive)    ApplyBrightnessToGlobals();
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
}

void SetWorldLight(bool enable,
                   uint8_t ar, uint8_t ag, uint8_t ab,
                   uint8_t dr, uint8_t dg, uint8_t db,
                   uint8_t str_, uint8_t stg, uint8_t stb,
                   uint8_t shr, uint8_t shg, uint8_t shb,
                   bool fogOn, uint8_t fr, uint8_t fg, uint8_t fb) {
    AcquireSRWLockExclusive(&g_wlLock);
    g_wlAmb[0] = ar / 255.0f; g_wlAmb[1] = ag / 255.0f; g_wlAmb[2] = ab / 255.0f;
    g_wlDif[0] = dr / 255.0f; g_wlDif[1] = dg / 255.0f; g_wlDif[2] = db / 255.0f;
    g_wlSkyTop[0] = str_ / 255.0f; g_wlSkyTop[1] = stg / 255.0f; g_wlSkyTop[2] = stb / 255.0f;
    g_wlSkyHor[0] = shr / 255.0f; g_wlSkyHor[1] = shg / 255.0f; g_wlSkyHor[2] = shb / 255.0f;
    ReleaseSRWLockExclusive(&g_wlLock);
    InterlockedExchange(&g_wlActive, enable ? 1 : 0);
    // NOTE: lighting moods do NOT touch fog. Fog is owned solely by the World
    // Environment fog override (worldfog ENV cfg); applying/clearing it here used
    // to slam fog right up to the camera and to wipe the user's fog override.
    (void)fogOn; (void)fr; (void)fg; (void)fb;
    ForceWorldRecompute();
}

void SetWorldBrightness(bool enable, float mult) {
    if (mult < 0.0f) mult = 0.0f; if (mult > 4.0f) mult = 4.0f;
    InterlockedExchange(&g_brightX1000, (LONG)(mult * 1000.0f + 0.5f));
    InterlockedExchange(&g_brightActive, enable ? 1 : 0);
    ForceWorldRecompute();
}

// Push the desired weather to the engine right now. Returns true if it landed
// (the weather object existed and we issued the call). Safe to call repeatedly.
static bool ApplyWeatherNow() {
    if (g_isProcessTerminating) return false;
    bool ok = false;
    __try {
        void* w = *g_weatherPtr;
        if (!w) return false;                 // weather object not created yet -> retry later
        int type = (int)g_weatherType;
        if (type <= 0) { pWeatherClear(w, nullptr); return true; }   // forced clear
        float intensity = (float)g_weatherIntX1000 / 1000.0f;
        if (intensity < 0.0f) intensity = 0.0f;
        if (intensity > 1.0f) intensity = 1.0f;
        g_wRec.id = 0;
        g_wRec.ambience = -1;
        g_wRec.effectType = type;
        g_wRec.transition = 0.25f;
        g_wRec.color[0] = 1.0f; g_wRec.color[1] = 1.0f; g_wRec.color[2] = 1.0f;
        // type 1 (rain): empty -> engine fills its default RainDrop01 texture.
        g_wRec.tex = (type == 1) ? ""
                   : (type == 2) ? "textures\\Weather\\SnowFlake01.blp"
                                 : "textures\\Weather\\WeatherMistGrainy01.blp";
        pWeatherSetType(w, nullptr, type, intensity, &g_wRec, g_weatherAbrupt ? 1 : 0, 0.25f);
        ok = true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        Log("[ColorEngine] ApplyWeatherNow exception");
    }
    return ok;
}

void SetWeather(int type, float intensity, bool abrupt) {
    if (intensity < 0.0f) intensity = 0.0f;
    if (intensity > 1.0f) intensity = 1.0f;
    if (type <= 0) {
        // "Clear" = drop our override and let the zone return to natural. One-shot
        // clear of any precip showing now; stop re-asserting.
        InterlockedExchange(&g_weatherActive, 0);
        InterlockedExchange(&g_weatherType, 0);
        __try { void* w = *g_weatherPtr; if (w) pWeatherClear(w, nullptr); }
        __except (EXCEPTION_EXECUTE_HANDLER) {}
        return;
    }
    InterlockedExchange(&g_weatherType, type);
    InterlockedExchange(&g_weatherIntX1000, (LONG)(intensity * 1000.0f + 0.5f));
    InterlockedExchange(&g_weatherAbrupt, abrupt ? 1 : 0);
    // Arm the override. ReassertWeather() keeps trying every tick until the engine
    // actually applies it (the weather object is lazily created, so a lone call can
    // land before it exists — that was the "spam the button" bug).
    InterlockedExchange(&g_weatherActive, 1);
    ApplyWeatherNow();
}

// Called every tick. Retries the forced weather until the engine confirms it (via
// Weather::GetType), then goes quiet — and re-applies again only if the zone/engine
// later reverts it. No-op (zero cost) unless a weather override is armed.
void ReassertWeather() {
    if (!g_weatherActive || g_isProcessTerminating) return;
    __try {
        void* w = *g_weatherPtr;
        if (!w) return;                       // not in an outdoor zone yet -> wait
        int want = (int)g_weatherType;
        if (want <= 0) return;
        if (pWeatherGetType(w, nullptr) != want) ApplyWeatherNow();   // not (yet) applied
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
}

void SetSkybox(const char* skyboxModelName) {
    if (g_isProcessTerminating) return;
    __try {
        if (!skyboxModelName || !skyboxModelName[0]) {
            if (g_skySaved) *g_zoneSkyboxName = g_savedSky;   // restore zone sky
            InterlockedExchange(&g_skyActive, 0);
            return;
        }
        strncpy_s(g_skyName, sizeof(g_skyName), skyboxModelName, _TRUNCATE);
        if (!g_skySaved) { g_savedSky = *g_zoneSkyboxName; g_skySaved = true; }
        *g_zoneSkyboxName = g_skyName;
        InterlockedExchange(&g_skyActive, 1);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        Log("[ColorEngine] SetSkybox exception");
    }
}

void ReassertSkybox() {
    if (!g_skyActive || g_isProcessTerminating) return;
    __try { *g_zoneSkyboxName = g_skyName; } __except (EXCEPTION_EXECUTE_HANDLER) {}
}

static const char* SkyboxNameById(int id) {
    void* idb = reinterpret_cast<uint8_t*>(g_lightSkyboxDB) + 0x18;
    void* rec = nullptr;
    __try { rec = pGetRecord(idb, nullptr, id); } __except (EXCEPTION_EXECUTE_HANDLER) { rec = nullptr; }
    if (!rec || reinterpret_cast<uintptr_t>(rec) < 0x10000) return nullptr;
    const char* name = nullptr;
    __try { name = *reinterpret_cast<const char**>(reinterpret_cast<uint8_t*>(rec) + 0x04); }
    __except (EXCEPTION_EXECUTE_HANDLER) { name = nullptr; }
    if (!name || reinterpret_cast<uintptr_t>(name) < 0x10000 || !name[0]) return nullptr;
    return name;
}

void SetSkyboxById(int lightSkyboxId) {
    if (g_isProcessTerminating) return;
    if (lightSkyboxId < 0) { SetSkybox(nullptr); return; }
    const char* name = SkyboxNameById(lightSkyboxId);
    if (name) SetSkybox(name);
}

void PublishSkyboxList() {
    if (!FrameScript_Execute || g_isProcessTerminating) return;
    FrameScript_Execute("TRANSMORPHER_SKYBOXES = {}", "Transmorpher", 0);
    char buf[1900]; int n = 0; buf[0] = 0; int count = 0;
    for (int id = 1; id <= 4000; ++id) {
        const char* name = SkyboxNameById(id);
        if (!name) continue;
        // Lua single-quoted string: escape backslashes and quotes.
        char esc[300]; int e = 0;
        for (const char* p = name; *p && e < (int)sizeof(esc) - 2; ++p) {
            if (*p == '\\' || *p == '\'') esc[e++] = '\\';
            esc[e++] = *p;
        }
        esc[e] = 0;
        char line[360];
        int ln = _snprintf_s(line, sizeof(line), _TRUNCATE, "TRANSMORPHER_SKYBOXES[%d]='%s';", id, esc);
        if (ln <= 0) continue;
        if (n + ln >= (int)sizeof(buf) - 1) { FrameScript_Execute(buf, "Transmorpher", 0); n = 0; buf[0] = 0; }
        memcpy(buf + n, line, ln); n += ln; buf[n] = 0;
        ++count;
    }
    if (n > 0) FrameScript_Execute(buf, "Transmorpher", 0);
    char done[96];
    _snprintf_s(done, sizeof(done), _TRUNCATE, "TRANSMORPHER_SKYBOXES_READY = %d", count);
    FrameScript_Execute(done, "Transmorpher", 0);
    Log("[ColorEngine] published %d skyboxes", count);
}

// Publish every playable race live from ChrRaces.dbc -> TRANSMORPHER_RACES[id] =
// {name, male, female}. These display ids are the canonical PLAYER bodies, so they
// are guaranteed to wear gear (fixes the races that rendered gearless from picked
// NPC ids), and any CUSTOM race on the client is included automatically.
void PublishRaceList() {
    if (!FrameScript_Execute || g_isProcessTerminating) return;
    FrameScript_Execute("TRANSMORPHER_RACES = {}", "Transmorpher", 0);
    int minId = 1, maxId = 100, count = 0;
    __try {
        uint8_t* b = reinterpret_cast<uint8_t*>(g_chrRacesDB);
        maxId = *reinterpret_cast<int*>(b + 0x0C);
        minId = *reinterpret_cast<int*>(b + 0x10);
    } __except (EXCEPTION_EXECUTE_HANDLER) { minId = 1; maxId = 100; }
    if (minId < 1) minId = 1;
    if (maxId < minId || maxId > 1000) maxId = minId + 99;
    for (int id = minId; id <= maxId; ++id) {
        void* rec = DbRecord(g_chrRacesDB, id);
        if (!rec) continue;
        uint32_t male = 0, female = 0; const char* name = nullptr;
        __try {
            uint8_t* r = reinterpret_cast<uint8_t*>(rec);
            male   = *reinterpret_cast<uint32_t*>(r + 0x10);
            female = *reinterpret_cast<uint32_t*>(r + 0x14);
            name   = *reinterpret_cast<const char**>(r + 0x38);   // m_name
        } __except (EXCEPTION_EXECUTE_HANDLER) { continue; }
        if (male == 0 && female == 0) continue;
        char esc[80]; int e = 0;
        if (name && reinterpret_cast<uintptr_t>(name) >= 0x10000) {
            __try {
                for (const char* p = name; *p && e < (int)sizeof(esc) - 2; ++p) {
                    if (*p == '\\' || *p == '\'') esc[e++] = '\\';
                    esc[e++] = *p;
                }
            } __except (EXCEPTION_EXECUTE_HANDLER) { e = 0; }
        }
        esc[e] = 0;
        char line[200];
        int ln = _snprintf_s(line, sizeof(line), _TRUNCATE,
            "TRANSMORPHER_RACES[%d]={name='%s',male=%u,female=%u};", id, esc, male, female);
        if (ln > 0) { FrameScript_Execute(line, "Transmorpher", 0); ++count; }
    }
    char done[64];
    _snprintf_s(done, sizeof(done), _TRUNCATE, "TRANSMORPHER_RACES_READY=%d", count);
    FrameScript_Execute(done, "Transmorpher", 0);
    Log("[ColorEngine] published %d races", count);
}

// Publish gear-wearing HUMANOID displays: CreatureDisplayInfo entries whose CDIExtra
// has a playable race AND empty baked items (so morphing to it shows the PLAYER's own
// gear). -> TRANSMORPHER_HUMANOIDS[i] = {d=display, r=race, s=sex}. Scans the DB's
// real id range, capped at maxOut entries.
void PublishHumanoidList(int maxOut) {
    if (!FrameScript_Execute || g_isProcessTerminating) return;
    if (maxOut <= 0 || maxOut > 3000) maxOut = 800;
    FrameScript_Execute("TRANSMORPHER_HUMANOIDS = {}", "Transmorpher", 0);
    int minId = 1, maxId = 0, count = 0;
    __try {
        uint8_t* b = reinterpret_cast<uint8_t*>(g_creatureDisplayInfoDB);
        maxId = *reinterpret_cast<int*>(b + 0x0C);
        minId = *reinterpret_cast<int*>(b + 0x10);
    } __except (EXCEPTION_EXECUTE_HANDLER) { minId = 1; maxId = 0; }
    if (minId < 1) minId = 1;
    if (maxId < minId || maxId > 200000) maxId = minId;   // safety bound
    char buf[1900]; int n = 0; buf[0] = 0;
    for (int id = minId; id <= maxId && count < maxOut; ++id) {
        void* cdi = DbRecord(g_creatureDisplayInfoDB, id);
        if (!cdi) continue;
        uint32_t extId = 0;
        __try { extId = *reinterpret_cast<uint32_t*>(reinterpret_cast<uint8_t*>(cdi) + 0x0C); }
        __except (EXCEPTION_EXECUTE_HANDLER) { continue; }
        if (!extId) continue;
        void* ex = DbRecord(g_cdiExtraDB, (int)extId);
        if (!ex) continue;
        int race = 0, sex = 0; bool emptyGear = true;
        __try {
            uint8_t* x = reinterpret_cast<uint8_t*>(ex);
            race = *reinterpret_cast<int*>(x + 0x04);
            sex  = *reinterpret_cast<int*>(x + 0x08);
            for (int k = 0; k < 11; ++k) {
                if (*reinterpret_cast<int*>(x + 0x20 + k * 4) != 0) { emptyGear = false; break; }
            }
        } __except (EXCEPTION_EXECUTE_HANDLER) { continue; }
        if (race < 1 || race > 15 || (sex != 0 && sex != 1)) continue;
        if (!emptyGear) continue;   // only displays that wear the player's own gear
        char line[80];
        int ln = _snprintf_s(line, sizeof(line), _TRUNCATE,
            "TRANSMORPHER_HUMANOIDS[%d]={d=%d,r=%d,s=%d};", count + 1, id, race, sex);
        if (ln <= 0) continue;
        if (n + ln >= (int)sizeof(buf) - 1) { FrameScript_Execute(buf, "Transmorpher", 0); n = 0; buf[0] = 0; }
        memcpy(buf + n, line, ln); n += ln; buf[n] = 0; ++count;
    }
    if (n > 0) FrameScript_Execute(buf, "Transmorpher", 0);
    char done[64];
    _snprintf_s(done, sizeof(done), _TRUNCATE, "TRANSMORPHER_HUMANOIDS_READY=%d", count);
    FrameScript_Execute(done, "Transmorpher", 0);
    Log("[ColorEngine] published %d humanoid displays", count);
}

void SetWorldTextStyle(int style, bool enable, int mode, uint8_t r, uint8_t g, uint8_t b) {
    if ((unsigned)style >= 16) return;
    InterlockedExchange(&g_wt[style].col,  (LONG)((0xFFu << 24) | ((uint32_t)r << 16) | ((uint32_t)g << 8) | b));
    InterlockedExchange(&g_wt[style].mode, mode ? 1 : 0);
    InterlockedExchange(&g_wt[style].enabled, enable ? 1 : 0);
    LONG any = 0;
    for (int i = 0; i < 16; ++i) any |= g_wt[i].enabled;
    InterlockedExchange(&g_wtActive, any ? 1 : 0);
}

void SetWorldTextGradientSpeed(float cyclesPerSec) {
    if (cyclesPerSec < 0.0f) cyclesPerSec = 0.0f;
    if (cyclesPerSec > 5.0f) cyclesPerSec = 5.0f;
    InterlockedExchange(&g_wtGradX1000, (LONG)(cyclesPerSec * 1000.0f + 0.5f));
}

void SetWorldTextSize(bool enable, float factor) {
    if (g_isProcessTerminating) return;
    if (factor < 0.2f) factor = 0.2f; if (factor > 6.0f) factor = 6.0f;
    if (!g_wtSizeWritable) {
        DWORD old = 0;
        if (VirtualProtect((void*)g_wtSizeBase, g_wtStyleStride * g_wtStyleCount, PAGE_EXECUTE_READWRITE, &old))
            g_wtSizeWritable = true;
    }
    if (!g_wtSizeWritable) return;
    __try {
        // Capture native min/max once so we always scale from the true baseline.
        if (!g_wtSizeSaved) {
            for (int i = 0; i < g_wtStyleCount; ++i) {
                float* rec = (float*)((uint8_t*)g_wtSizeBase + i * g_wtStyleStride);
                g_wtSizeOrig[i][0] = rec[3];   // +0x0C min height
                g_wtSizeOrig[i][1] = rec[4];   // +0x10 max height
            }
            g_wtSizeSaved = true;
        }
        for (int i = 0; i < g_wtStyleCount; ++i) {
            float* rec = (float*)((uint8_t*)g_wtSizeBase + i * g_wtStyleStride);
            rec[3] = enable ? g_wtSizeOrig[i][0] * factor : g_wtSizeOrig[i][0];
            rec[4] = enable ? g_wtSizeOrig[i][1] * factor : g_wtSizeOrig[i][1];
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
    InterlockedExchange(&g_wtSizeX1000, (LONG)(factor * 1000.0f + 0.5f));
    InterlockedExchange(&g_wtSizeActive, enable ? 1 : 0);
}

void ClearWorldText() {
    for (int i = 0; i < 16; ++i) {
        InterlockedExchange(&g_wt[i].enabled, 0);
        InterlockedExchange(&g_wt[i].mode, 0);
    }
    InterlockedExchange(&g_wtActive, 0);
    SetWorldTextSize(false, 1.0f);   // restore native size
}

void SetLightPreset(int lightParamsId) {
    if (g_isProcessTerminating) return;
    __try {
        if (lightParamsId < 0) pClearOverrideLightParams();
        else pSetOverrideLightParams(lightParamsId);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        Log("[ColorEngine] SetLightPreset exception");
    }
}

// Weapon-skin texture redirect helpers. These touch std::string (via g_texMap),
// which needs C++ unwinding, so they live OUTSIDE the __try functions below
// (mixing __try with object-unwinding in one function is a compile error C2712).
static void RetexTexSet(const char* fromNorm, const char* toNorm) {
    if (!fromNorm || !toNorm || !fromNorm[0] || !toNorm[0]) return;
    AcquireSRWLockExclusive(&g_texLock);
    g_texMap[fromNorm] = toNorm;
    InterlockedExchange(&g_texActive, (LONG)g_texMap.size());
    ReleaseSRWLockExclusive(&g_texLock);
}
static void RetexTexErase(const char* fromNorm) {
    if (!fromNorm || !fromNorm[0]) return;
    AcquireSRWLockExclusive(&g_texLock);
    g_texMap.erase(fromNorm);
    InterlockedExchange(&g_texActive, (LONG)g_texMap.size());
    ReleaseSRWLockExclusive(&g_texLock);
}

static void TintTexSet(const char* virtualNorm, const TextureTint& tint) {
    if (!virtualNorm || !virtualNorm[0] || !tint.realPath[0]) return;
    AcquireSRWLockExclusive(&g_tintLock);
    g_tintMap[virtualNorm] = tint;
    InterlockedExchange(&g_tintActive, (LONG)g_tintMap.size());
    ReleaseSRWLockExclusive(&g_tintLock);
}

static void TintTexErase(const char* virtualNorm) {
    if (!virtualNorm || !virtualNorm[0]) return;
    AcquireSRWLockExclusive(&g_tintLock);
    g_tintMap.erase(virtualNorm);
    InterlockedExchange(&g_tintActive, (LONG)g_tintMap.size());
    ReleaseSRWLockExclusive(&g_tintLock);
}

static int ClampTintMult(int multX100) {
    if (multX100 < 0) return 0;
    if (multX100 > 400) return 400;
    return multX100;
}

void ItemTintSlotRemove(uint32_t slot) {
    auto it = g_itemTintSaved.find(slot);
    if (it == g_itemTintSaved.end()) return;
    // Keep the reverse virtual-key redirects alive until the engine has actually
    // dropped the model attachment. Erasing them while the compositor still holds
    // a cached CTexture loaded under the virtual name would leave the next stream
    // request with a phantom key that the SFile hook can no longer resolve
    // (observed on dressroom reset / gear swap with a tinted body component).
    for (const auto& k : it->second.redirectKeys) {
        if (!IsVirtualComponentKey(k.c_str())) RetexTexErase(k.c_str());
    }
    for (const auto& k : it->second.tintKeys)     TintTexErase(k.c_str());
    for (const auto& k : it->second.sfileKeys)    SfileTintErase(k.c_str());
    g_itemTintSaved.erase(it);
}

// Build every real BLP path the client may load for one ItemDisplayInfo texture-name
// field. fieldIdx is the index into kTintNameOffsets: 0..1 = modelTexture (single
// model item, lives in Item\ObjectComponents\<Type>\<name>.blp), 2..9 = body
// component texture[0..7] (lives in Item\TextureComponents\<region>\<name>_<U|M|F>.blp,
// per the client path builder at 0x004E6FB0). Returns the count written.
static int BuildRealTexCandidates(int fieldIdx, uint32_t slot, const char* name,
                                  char out[][220], int maxOut) {
    if (!name || !name[0] || maxOut <= 0) return 0;
    // If the DBC already stored a full path, use it verbatim.
    if (strchr(name, '\\') || strchr(name, '/')) {
        BuildBlpPath(name, "", out[0], 220);
        return out[0][0] ? 1 : 0;
    }
    int n = 0;
    if (fieldIdx <= 1) {
        const char* dirs[2] = { nullptr, nullptr }; int dc = 0;
        ObjectComponentDirs(slot, dirs, &dc);
        for (int d = 0; d < dc && n < maxOut; ++d)
            _snprintf_s(out[n++], 220, _TRUNCATE, "%s%s.blp", dirs[d], name);
    } else {
        int region = fieldIdx - 2;            // 0..7 -> kComponentDirs
        if (region < 0 || region > 7) return 0;
        for (int s = 0; s < 3 && n < maxOut; ++s)
            _snprintf_s(out[n++], 220, _TRUNCATE,
                "Item\\TextureComponents\\%s\\%s_%s.blp", kComponentDirs[region], name, kComponentSex[s]);
    }
    return n;
}

// Read the live ItemDisplayInfo texture-name fields into names[kTintNameCount][120].
// Kept separate (and free of C++ objects) because it uses SEH __try, which cannot
// live in a function that also needs C++ object unwinding (compiler error C2712).
static bool ReadDisplayInfoTexNames(void* di, char names[][120]) {
    if (!di || reinterpret_cast<uintptr_t>(di) < 0x10000) return false;
    __try {
        for (int i = 0; i < kTintNameCount; ++i) {
            names[i][0] = '\0';
            const char* s = reinterpret_cast<const char*>(*reinterpret_cast<void**>(
                reinterpret_cast<uint8_t*>(di) + kTintNameOffsets[i]));
            if (s && reinterpret_cast<uintptr_t>(s) >= 0x10000 && s[0])
                strncpy_s(names[i], 120, s, _TRUNCATE);
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
    return true;
}

// Force a CLEAN re-decode of the separate-model textures (helmet/shoulder/cape/weapon)
// currently shown in `slot` for item `fromItemId`. For each modelTexture (field 0/1) we
// resolve the real .blp path, look up the live CTexture captured at load time, and call
// CTexture::Reload on it. Because the tint map is cleared before this runs, LoadFromFile
// re-decodes the BLP with no tint and re-uploads to the GPU — so the baked-in tint is
// gone with no relog. SEH-guarded; silently skips slots with no captured texture.
void ReloadModelTexturesForSlot(uint32_t slot, uint32_t fromItemId) {
    if (g_isProcessTerminating || fromItemId == 0 || slot < 1 || slot > 19) return;
    uint32_t disp = DisplayIdFromItem(fromItemId);
    if (!disp) return;
    char curName[10][120] = {{0}};
    if (!ReadDisplayInfoTexNames(ResolveDisplayInfo(disp), curName)) return;
    for (int i = 0; i < 2 && i < kTintNameCount; ++i) {
        if (!curName[i][0]) continue;
        char cands[3][220];
        int nc = BuildRealTexCandidates(i, slot, curName[i], cands, 3);
        for (int c = 0; c < nc; ++c) {
            char norm[220]; NormalizeTexPath(cands[c], norm, sizeof(norm));
            if (!norm[0]) continue;
            void* tex = nullptr;
            AcquireSRWLockShared(&g_modelTexLock);
            auto it = g_modelTexByName.find(norm);
            if (it != g_modelTexByName.end()) tex = it->second;
            ReleaseSRWLockShared(&g_modelTexLock);
            if (tex) {
                // Only reload if the captured pointer is STILL the live texture for this
                // path. A stale/recycled pointer would corrupt the heap inside Reload (see
                // TexObjStillMatches) — the Skin-tab "Reset" crash. Drop stale entries so we
                // never touch them again.
                if (TexObjStillMatches(tex, norm)) {
                    SafeReloadTexObj(tex);
                    if (g_diagTexOn) Log("[RESET] reloaded model tex %s -> %p", norm, tex);
                } else {
                    AcquireSRWLockExclusive(&g_modelTexLock);
                    auto it2 = g_modelTexByName.find(norm);
                    if (it2 != g_modelTexByName.end() && it2->second == tex) g_modelTexByName.erase(it2);
                    ReleaseSRWLockExclusive(&g_modelTexLock);
                    if (g_diagTexOn) Log("[RESET] stale texobj for %s -> dropped (not reloaded)", norm);
                }
            } else {
                if (g_diagTexOn) Log("[RESET] no captured texobj for %s", norm);
            }
        }
    }
}

static bool IsSeparateModelSlot(uint32_t slot) {
    return slot == 1 || slot == 3 || slot == 15 || slot == 16 || slot == 17 || slot == 18;
}

void ArmCleanModelTexturesForSlot(uint32_t slot, uint32_t fromItemId) {
    if (g_isProcessTerminating || fromItemId == 0 || !IsSeparateModelSlot(slot)) return;
    uint32_t disp = DisplayIdFromItem(fromItemId);
    if (!disp) return;

    char curName[10][120] = {{0}};
    if (!ReadDisplayInfoTexNames(ResolveDisplayInfo(disp), curName)) return;

    for (int i = 0; i < 2 && i < kTintNameCount; ++i) {
        if (!curName[i][0]) continue;
        char cands[3][220];
        int nc = BuildRealTexCandidates(i, slot, curName[i], cands, 3);
        for (int c = 0; c < nc; ++c) {
            char normReal[220];
            NormalizeTexPath(cands[c], normReal, sizeof(normReal));
            if (!normReal[0]) continue;

            char virt[220], normVirt[220];
            _snprintf_s(virt, sizeof(virt), _TRUNCATE,
                        "TM_CLEAN_S%02u_%08X_%d_%d.blp", slot, fromItemId, i, c);
            NormalizeTexPath(virt, normVirt, sizeof(normVirt));
            if (!normVirt[0] || _stricmp(normReal, normVirt) == 0) continue;

            RetexTexSet(normReal, normVirt);
            const char* base = strrchr(normReal, '\\');
            base = base ? (base + 1) : normReal;
            if (base[0] && _stricmp(base, normReal) != 0) {
                char normBase[220];
                NormalizeTexPath(base, normBase, sizeof(normBase));
                if (normBase[0] && _stricmp(normBase, normVirt) != 0) RetexTexSet(normBase, normVirt);
            }
            RetexTexSet(normVirt, normReal);
            Log("[RESET] clean model key slot=%u item=%u %s -> %s", slot, fromItemId, normReal, normVirt);
        }
    }
}

bool ItemTintSlotSet(uint32_t slot, uint32_t fromItemId,
                     int mode, uint8_t r, uint8_t g, uint8_t b,
                     uint8_t r2, uint8_t g2, uint8_t b2,
                     int dir, int multX100, int glowStr, int contrast,
                     int rainbowSpanX100, int phase,
                     int brightness, int saturation, int hueShift) {
    if (g_isProcessTerminating || fromItemId == 0) return false;
    if (slot < 1 || slot > 19) return false;

    ItemTintSlotRemove(slot);
    InterlockedExchange(&g_tintDbgHits, 0);

    uint32_t fromDisp = DisplayIdFromItem(fromItemId);
    if (fromDisp == 0) return false;

    // Read the texture names the slot is ACTUALLY rendering right now.
    char curName[10][120] = {{0}};
    if (!ReadDisplayInfoTexNames(ResolveDisplayInfo(fromDisp), curName)) return false;

    TextureTint baseTint = {};
    baseTint.r = r; baseTint.g = g; baseTint.b = b;
    baseTint.multX100 = ClampTintMult(multX100);
    baseTint.mode = mode;
    baseTint.r2 = r2; baseTint.g2 = g2; baseTint.b2 = b2;
    baseTint.dir = dir;
    baseTint.glowStr = (glowStr < 0) ? 0 : (glowStr > 255 ? 255 : glowStr);
    baseTint.contrast = (contrast <= 0) ? 100 : (contrast > 400 ? 400 : contrast);
    baseTint.rainbowSpanX100 = (rainbowSpanX100 > 0) ? rainbowSpanX100 : 100;
    baseTint.phase = phase & 0xFF;
    baseTint.rainbow = (mode == 2);
    baseTint.glow = (baseTint.glowStr > 0);
    baseTint.brightness = (brightness < 0) ? 0 : (brightness > 255 ? 255 : brightness);
    baseTint.saturation = (saturation < -100) ? -100 : (saturation > 100 ? 100 : saturation);
    baseTint.hueShift   = hueShift & 0xFF;

    SavedItemTint saved;
    saved.fromItemId = fromItemId;

    // For every populated texture field, redirect the real component/model BLP that
    // the client loads to a unique virtual key carrying the tint. Routing through a
    // fresh virtual path per apply (serial) keeps the ORIGINAL file uncached-as-tinted,
    // so removing the entries on Reset makes the slot snap back to its true colors.
    for (int i = 0; i < kTintNameCount; ++i) {
        if (!curName[i][0]) continue;
        char cands[3][220];
        int nc = BuildRealTexCandidates(i, slot, curName[i], cands, 3);
        for (int c = 0; c < nc; ++c) {
            char normReal[220];
            NormalizeTexPath(cands[c], normReal, sizeof(normReal));
            if (!normReal[0]) continue;
            const char* base = strrchr(normReal, '\\');
            base = base ? (base + 1) : normReal;

            if (i >= 2) {
                // BODY-COMPOSITE component (chest/legs/hands/feet/waist/wrist/shirt/
                // tabard). Route through a unique synthetic path to avoid poisoning
                // the compositor cache entry for the ORIGINAL BLP path. SFileOpen maps
                // TM_CTINT_* back to the real file and tints the streamed bytes.
                LONG serial = InterlockedIncrement(&g_tintSerial);
                char virt[220], normVirt[220];
                _snprintf_s(virt, sizeof(virt), _TRUNCATE, "TM_CTINT_S%02u_%d_%d_%ld.blp", slot, i, c, serial);
                NormalizeTexPath(virt, normVirt, sizeof(normVirt));

                // DXT/BGRA components tint spatially; palettized components spread the
                // effect across the palette index (see TintPaletteRange). Either way the
                // body now shows a real multi-color rainbow/gradient, not a flat hue.
                SfileTintSet(normVirt, baseTint);
                saved.sfileKeys.emplace_back(normVirt);

                RetexTexSet(normReal, normVirt);
                saved.redirectKeys.emplace_back(normReal);

                if (base[0] && _stricmp(base, normReal) != 0) {
                    char normBase[220]; NormalizeTexPath(base, normBase, sizeof(normBase));
                    if (_stricmp(normBase, normVirt) != 0) {
                        RetexTexSet(normBase, normVirt);
                        saved.redirectKeys.emplace_back(normBase);
                    }
                }

                // Reverse redirect for SFileOpen(TM_CTINT_*) -> real path.
                RetexTexSet(normVirt, normReal);
                saved.redirectKeys.emplace_back(normVirt);

                if (g_diagTexOn) Log("[DIAGTEX REG-SF  ] slot=%u field=%d real=%s virt=%s", slot, i, normReal, normVirt);
                continue;
            }

            // MODEL item skin (weapon/shield/helm/shoulder/cape). These resolve through
            // TextureCacheCreateTexture and pass through BLPFileLockChain2, so the known
            // working path is decode-layer tint on a TM_CTINT virtual cache key. The real
            // path redirects to the virtual key, while the virtual key's tint.realPath
            // tells the BLP hook where to load clean source bytes from.
            LONG serial = InterlockedIncrement(&g_tintSerial);
            char virt[220], normVirt[220];
            _snprintf_s(virt, sizeof(virt), _TRUNCATE, "TM_CTINT_S%02u_%d_%d_%ld.blp", slot, i, c, serial);
            NormalizeTexPath(virt, normVirt, sizeof(normVirt));
            if (_stricmp(normReal, normVirt) == 0) continue;

            TextureTint tint = baseTint;
            strncpy_s(tint.realPath, sizeof(tint.realPath), normReal, _TRUNCATE);
            TintTexSet(normVirt, tint);
            saved.tintKeys.emplace_back(normVirt);
            if (g_diagTexOn) Log("[DIAGTEX REG     ] slot=%u field=%d real=%s virt=%s", slot, i, normReal, normVirt);

            RetexTexSet(normReal, normVirt);
            saved.redirectKeys.emplace_back(normReal);
            if (base[0] && _stricmp(base, normReal) != 0) {
                char normBase[220];
                NormalizeTexPath(base, normBase, sizeof(normBase));
                if (_stricmp(normBase, normVirt) != 0) {
                    RetexTexSet(normBase, normVirt);
                    saved.redirectKeys.emplace_back(normBase);
                }
            }
            // Reverse redirect is kept for fallback paths that ask SFileOpen directly
            // for the virtual key; the BLP decode hook normally uses tint.realPath.
            RetexTexSet(normVirt, normReal);
            saved.redirectKeys.emplace_back(normVirt);
        }
    }

    if (saved.tintKeys.empty() && saved.sfileKeys.empty()) {
        if (g_diagTexOn) Log("[DIAGTEX TINTSET ] slot=%u item=%u -> NO texture names resolved (nothing to recolor)", slot, fromItemId);
        return false;
    }
    g_itemTintSaved[slot] = std::move(saved);
    if (g_diagTexOn) Log("[DIAGTEX TINTSET ] slot=%u item=%u registered %zu decode + %zu sfile key(s)", slot, fromItemId,
        g_itemTintSaved[slot].tintKeys.size(), g_itemTintSaved[slot].sfileKeys.size());
    return true;
}

// Reload EVERY loaded texture from its source file. Call this AFTER the tint/retex maps
// are cleared on a reset: model items (helmet/shoulder/cape/weapon) can keep an old
// tinted CTexture alive even after the redirect is gone, so force the engine to re-decode
// loaded textures from disk. The reset path also arms clean virtual keys for the affected
// model BLPs so the next attach cannot reuse the stale cache object.
void ReloadAllTextures() {
    if (g_isProcessTerminating) return;
    if (g_diagTexOn) Log("[RESET] ReloadAllTextures: begin (calling TextureNotifyGxRestart @0x4B65E0)");
    __try { oTextureReloadAll(); } __except (EXCEPTION_EXECUTE_HANDLER) { Log("[RESET] ReloadAllTextures: EXCEPTION"); }
    if (g_diagTexOn) Log("[RESET] ReloadAllTextures: end");
}

void SetTexDiag(bool on) {
    InterlockedExchange(&g_diagTexHits, 0);
    InterlockedExchange(&g_diagTexOn, on ? 1 : 0);
    Log("[DIAGTEX] capture %s (cap reset)", on ? "ON" : "OFF");
}

void ItemTintClear() {
    while (!g_itemTintSaved.empty()) {
        uint32_t slot = g_itemTintSaved.begin()->first;
        ItemTintSlotRemove(slot);
    }
    AcquireSRWLockExclusive(&g_tintLock);
    g_tintMap.clear();
    InterlockedExchange(&g_tintActive, 0);
    ReleaseSRWLockExclusive(&g_tintLock);
    AcquireSRWLockExclusive(&g_sfileLock);
    g_sfileTint.clear();
    InterlockedExchange(&g_sfileActive, 0);
    ReleaseSRWLockExclusive(&g_sfileLock);
    AcquireSRWLockExclusive(&g_handleLock);
    g_blpHandles.clear();
    InterlockedExchange(&g_blpTagged, 0);
    ReleaseSRWLockExclusive(&g_handleLock);
}

bool ItemRetexAdd(uint32_t fromItemId, uint32_t toItemId) {
    if (g_isProcessTerminating || fromItemId == 0 || toItemId == 0) return false;

    uint32_t fromDisp = DisplayIdFromItem(fromItemId);
    uint32_t toDisp   = DisplayIdFromItem(toItemId);
    if (fromDisp == 0 || toDisp == 0) {
        Log("[ColorEngine] retex: could not resolve display (from=%u to=%u)", fromItemId, toItemId);
        return false;
    }

    void* fromDI = ResolveDisplayInfo(fromDisp);
    void* toDI   = ResolveDisplayInfo(toDisp);
    if (!fromDI || !toDI ||
        reinterpret_cast<uintptr_t>(fromDI) < 0x10000 ||
        reinterpret_cast<uintptr_t>(toDI) < 0x10000) {
        return false;
    }

    __try {
        // Save originals once (so repeated swaps still restore the true source).
        if (g_retexSaved.find(fromItemId) == g_retexSaved.end()) {
            SavedRetex sv = {}; sv.di = fromDI;
            for (int i = 0; i < kRetexCount; ++i)
                sv.orig[i] = *reinterpret_cast<void**>(reinterpret_cast<uint8_t*>(fromDI) + kRetexOffsets[i]);
            sv.texCount = 0; sv.texFrom[0][0] = '\0'; sv.texFrom[1][0] = '\0';
            g_retexSaved[fromItemId] = sv;
        }
        SavedRetex& saved = g_retexSaved[fromItemId];
        // Write donor pointers DIRECTLY into the shared ItemDisplayInfo record so the
        // compositor always reads the donor's appearance (global, matches reference).
        for (int i = 0; i < kRetexCount; ++i) {
            void* donor = *reinterpret_cast<void**>(reinterpret_cast<uint8_t*>(toDI) + kRetexOffsets[i]);
            *reinterpret_cast<void**>(reinterpret_cast<uint8_t*>(fromDI) + kRetexOffsets[i]) = donor;
        }

        // --- Weapon-skin redirect (the "warglaive" case) ---------------------
        // Some weapon M2 models reference their texture by a HARDCODED path baked
        // into the model itself (texture type 0), so swapping the ItemDisplayInfo
        // texture POINTER above has no visible effect on the skin — only the glow
        // and particle FX (spellVisual/itemVisual) swap shows ("only contrast
        // applies"). Fix: redirect the actual BLP load through the TextureLoadImage
        // hook, mapping the source weapon's texture file to the donor's, derived
        // from the ItemDisplayInfo model-texture NAMES. Weapon textures live in
        // Item\ObjectComponents\Weapon\<name>.blp. Fully reversible (entries are
        // removed in ItemRetexRemove/Clear). Harmless for armor (it never loads
        // from the Weapon directory, so a stray weapon-path entry never matches).
        {
            for (int n = 0; n < 2; ++n) {
                const char* srcName = reinterpret_cast<const char*>(saved.orig[n]);          // original source tex name
                const char* dstName = *reinterpret_cast<char**>(reinterpret_cast<uint8_t*>(toDI) + kRetexOffsets[n]); // donor tex name
                if (!srcName || !dstName || !srcName[0] || !dstName[0]) continue;
                if (_stricmp(srcName, dstName) == 0) continue;
                char srcPath[200], dstPath[200], normSrc[200], normDst[200];
                _snprintf_s(srcPath, sizeof(srcPath), _TRUNCATE, "Item\\ObjectComponents\\Weapon\\%s.blp", srcName);
                _snprintf_s(dstPath, sizeof(dstPath), _TRUNCATE, "Item\\ObjectComponents\\Weapon\\%s.blp", dstName);
                NormalizeTexPath(srcPath, normSrc, sizeof(normSrc));
                NormalizeTexPath(dstPath, normDst, sizeof(normDst));
                RetexTexSet(normSrc, normDst);
                strncpy_s(saved.texFrom[n], sizeof(saved.texFrom[n]), normSrc, _TRUNCATE);
                if (saved.texCount < n + 1) saved.texCount = n + 1;
            }
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        Log("[ColorEngine] retex exception (from=%u to=%u)", fromItemId, toItemId);
        return false;
    }
    if (g_diagTexOn) Log("[ColorEngine] retex item %u -> %u (disp %u<-%u)", fromItemId, toItemId, fromDisp, toDisp);
    return true;
}

void ItemRetexRemove(uint32_t fromItemId) {
    auto it = g_retexSaved.find(fromItemId);
    if (it == g_retexSaved.end()) return;
    __try {
        uint8_t* di = reinterpret_cast<uint8_t*>(it->second.di);
        for (int i = 0; i < kRetexCount; ++i)
            *reinterpret_cast<void**>(di + kRetexOffsets[i]) = it->second.orig[i];
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
    for (int i = 0; i < it->second.texCount && i < 2; ++i) {
        if (it->second.texFrom[i][0]) RetexTexErase(it->second.texFrom[i]);
    }
    g_retexSaved.erase(it);
}

void ItemRetexClear() {
    ItemTintClear();
    for (auto& kv : g_retexSaved) {
        __try {
            uint8_t* di = reinterpret_cast<uint8_t*>(kv.second.di);
            for (int i = 0; i < kRetexCount; ++i)
                *reinterpret_cast<void**>(di + kRetexOffsets[i]) = kv.second.orig[i];
        } __except (EXCEPTION_EXECUTE_HANDLER) {}
        for (int i = 0; i < kv.second.texCount && i < 2; ++i) {
            if (kv.second.texFrom[i][0]) RetexTexErase(kv.second.texFrom[i]);
        }
    }
    g_retexSaved.clear();
}

// --- Display-id variants -----------------------------------------------------
// These take a fully-resolved ItemDisplayInfo id (not an item id) so they can be
// used on render targets that only have a display id -- notably the character-
// select doll built by SelectCharacter, which stores per-slot display ids in the
// gluescreen entry struct (e + 0x50 + slot*4) and has no live item record.
// They share g_retexSaved / g_itemTintSaved with the item-id variants, keyed on
// a synthetic id 0x80000000 | displayId so the two paths don't collide and
// ItemRetexClear / ItemTintClear clean them up uniformly.
static inline uint32_t DispKey(uint32_t displayId) { return 0x80000000u | (displayId & 0x7FFFFFFFu); }

bool ItemRetexAddDisplay(uint32_t fromDisplayId, uint32_t toItemId) {
    if (g_isProcessTerminating || fromDisplayId == 0 || toItemId == 0) return false;
    uint32_t toDisp = DisplayIdFromItem(toItemId);
    if (fromDisplayId == 0 || toDisp == 0 || fromDisplayId == toDisp) return false;
    void* fromDI = ResolveDisplayInfo(fromDisplayId);
    void* toDI   = ResolveDisplayInfo(toDisp);
    if (!fromDI || !toDI ||
        reinterpret_cast<uintptr_t>(fromDI) < 0x10000 ||
        reinterpret_cast<uintptr_t>(toDI)   < 0x10000) return false;
    uint32_t key = DispKey(fromDisplayId);
    __try {
        if (g_retexSaved.find(key) == g_retexSaved.end()) {
            SavedRetex sv = {}; sv.di = fromDI;
            for (int i = 0; i < kRetexCount; ++i)
                sv.orig[i] = *reinterpret_cast<void**>(reinterpret_cast<uint8_t*>(fromDI) + kRetexOffsets[i]);
            sv.texCount = 0; sv.texFrom[0][0] = '\0'; sv.texFrom[1][0] = '\0';
            g_retexSaved[key] = sv;
        }
        SavedRetex& saved = g_retexSaved[key];
        for (int i = 0; i < kRetexCount; ++i) {
            void* donor = *reinterpret_cast<void**>(reinterpret_cast<uint8_t*>(toDI) + kRetexOffsets[i]);
            *reinterpret_cast<void**>(reinterpret_cast<uint8_t*>(fromDI) + kRetexOffsets[i]) = donor;
        }
        // Weapon-skin redirect (matches ItemRetexAdd)
        for (int n = 0; n < 2; ++n) {
            const char* srcName = reinterpret_cast<const char*>(saved.orig[n]);
            const char* dstName = *reinterpret_cast<char**>(reinterpret_cast<uint8_t*>(toDI) + kRetexOffsets[n]);
            if (!srcName || !dstName || !srcName[0] || !dstName[0]) continue;
            if (_stricmp(srcName, dstName) == 0) continue;
            char srcPath[200], dstPath[200], normSrc[200], normDst[200];
            _snprintf_s(srcPath, sizeof(srcPath), _TRUNCATE, "Item\\ObjectComponents\\Weapon\\%s.blp", srcName);
            _snprintf_s(dstPath, sizeof(dstPath), _TRUNCATE, "Item\\ObjectComponents\\Weapon\\%s.blp", dstName);
            NormalizeTexPath(srcPath, normSrc, sizeof(normSrc));
            NormalizeTexPath(dstPath, normDst, sizeof(normDst));
            RetexTexSet(normSrc, normDst);
            strncpy_s(saved.texFrom[n], sizeof(saved.texFrom[n]), normSrc, _TRUNCATE);
            if (saved.texCount < n + 1) saved.texCount = n + 1;
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
    return true;
}

bool ItemTintSlotSetDisplay(uint32_t slot, uint32_t fromDisplayId,
                            int mode, uint8_t r, uint8_t g, uint8_t b,
                            uint8_t r2, uint8_t g2, uint8_t b2,
                            int dir, int multX100, int glowStr, int contrast,
                            int rainbowSpanX100, int phase,
                            int brightness, int saturation, int hueShift) {
    if (g_isProcessTerminating || fromDisplayId == 0) return false;
    if (slot < 1 || slot > 19) return false;
    // Remove any previous tint on this slot (item-id and display-id variants)
    ItemTintSlotRemove(slot);

    void* fromDI = ResolveDisplayInfo(fromDisplayId);
    if (!fromDI || reinterpret_cast<uintptr_t>(fromDI) < 0x10000) return false;

    uint32_t key = DispKey(fromDisplayId);
    char curName[10][120] = {{0}};
    if (!ReadDisplayInfoTexNames(fromDI, curName)) return false;

    TextureTint baseTint = {};
    baseTint.r = r; baseTint.g = g; baseTint.b = b;
    baseTint.multX100 = ClampTintMult(multX100);
    baseTint.mode = mode;
    baseTint.r2 = r2; baseTint.g2 = g2; baseTint.b2 = b2;
    baseTint.dir = dir;
    baseTint.glowStr = (glowStr < 0) ? 0 : (glowStr > 255 ? 255 : glowStr);
    baseTint.contrast = (contrast <= 0) ? 100 : (contrast > 400 ? 400 : contrast);
    baseTint.rainbowSpanX100 = (rainbowSpanX100 > 0) ? rainbowSpanX100 : 100;
    baseTint.phase = phase & 0xFF;
    baseTint.rainbow = (mode == 2);
    baseTint.glow = (baseTint.glowStr > 0);
    baseTint.brightness = (brightness < 0) ? 0 : (brightness > 255 ? 255 : brightness);
    baseTint.saturation = (saturation < -100) ? -100 : (saturation > 100 ? 100 : saturation);
    baseTint.hueShift   = hueShift & 0xFF;

    // Manually route through the same registration loop as ItemTintSlotSet so
    // the doll (which only has a display id) ends up in g_itemTintSaved keyed on
    // DispKey(displayId). We mirror the saved record but with our key.
    SavedItemTint saved;
    saved.fromItemId = key;

    for (int i = 0; i < kTintNameCount; ++i) {
        if (!curName[i][0]) continue;
        char cands[3][220];
        int nc = BuildRealTexCandidates(i, slot, curName[i], cands, 3);
        for (int c = 0; c < nc; ++c) {
            char normReal[220];
            NormalizeTexPath(cands[c], normReal, sizeof(normReal));
            if (!normReal[0]) continue;
            const char* base = strrchr(normReal, '\\');
            base = base ? (base + 1) : normReal;

            if (i >= 2) {
                LONG serial = InterlockedIncrement(&g_tintSerial);
                char virt[220], normVirt[220];
                _snprintf_s(virt, sizeof(virt), _TRUNCATE, "TM_CTINT_D%02u_%d_%d_%ld.blp", slot, i, c, serial);
                NormalizeTexPath(virt, normVirt, sizeof(normVirt));

                // Spatial for DXT/BGRA, palette-index spread for palettized (see
                // TintPaletteRange) — real multi-color on the body, not a flat hue.
                SfileTintSet(normVirt, baseTint);
                saved.sfileKeys.emplace_back(normVirt);

                RetexTexSet(normReal, normVirt);
                saved.redirectKeys.emplace_back(normReal);

                if (base[0] && _stricmp(base, normReal) != 0) {
                    char normBase[220]; NormalizeTexPath(base, normBase, sizeof(normBase));
                    if (_stricmp(normBase, normVirt) != 0) {
                        RetexTexSet(normBase, normVirt);
                        saved.redirectKeys.emplace_back(normBase);
                    }
                }

                RetexTexSet(normVirt, normReal);
                saved.redirectKeys.emplace_back(normVirt);
                continue;
            }

            // Model item: decode-layer tint on a virtual cache key, same as ItemTintSlotSet.
            LONG serial = InterlockedIncrement(&g_tintSerial);
            char virt[220], normVirt[220];
            _snprintf_s(virt, sizeof(virt), _TRUNCATE, "TM_CTINT_S%02u_%d_%d_%ld.blp", slot, i, c, serial);
            NormalizeTexPath(virt, normVirt, sizeof(normVirt));
            if (_stricmp(normReal, normVirt) == 0) continue;

            TextureTint tint = baseTint;
            strncpy_s(tint.realPath, sizeof(tint.realPath), normReal, _TRUNCATE);
            TintTexSet(normVirt, tint);
            saved.tintKeys.emplace_back(normVirt);

            RetexTexSet(normReal, normVirt);
            saved.redirectKeys.emplace_back(normReal);
            if (base[0] && _stricmp(base, normReal) != 0) {
                char normBase[220];
                NormalizeTexPath(base, normBase, sizeof(normBase));
                RetexTexSet(normBase, normVirt);
                saved.redirectKeys.emplace_back(normBase);
            }
            RetexTexSet(normVirt, normReal);   // reverse: load real bytes for the virtual key
            saved.redirectKeys.emplace_back(normVirt);
        }
    }
    if (saved.sfileKeys.empty() && saved.tintKeys.empty() && saved.redirectKeys.empty()) return false;
    g_itemTintSaved[key] = std::move(saved);
    return true;
}

} // namespace ColorEngine
