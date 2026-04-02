#include "Hooks.h"
#include "Logger.h"
#include "Morpher.h"
#include "Utils.h"
#include <windows.h>
#include <cstdio>
#include <cstring>

// ================================================================
// Time Hook (Refactored for Stability)
// ================================================================
DWORD TIME_HOOK_ADDR = 0x0076CFF0;
DWORD TIME_VAR_ADDR = 0x0076D000;
float g_timeOfDay = 0.5f; 
bool g_timeHookInstalled = false;
static BYTE g_timeHookOrigBytes[32] = {0};

bool InstallTimeHook() {
    if (g_timeHookInstalled) return true;
    
    // Safety check: ensure we are hooking the expected function prologue
    // Found: 55 8B EC 51 56 8B (on user's client)
    // Expected: 55 8B EC 83 E4 F8 (standard)
    // We'll relax the check to just the first 3 bytes (standard frame setup)
    BYTE expected[3] = { 0x55, 0x8B, 0xEC };
    if (memcmp((void*)TIME_HOOK_ADDR, expected, 3) != 0) {
        // Log what we found
        BYTE* p = (BYTE*)TIME_HOOK_ADDR;
        Log("Time hook mismatch at 0x%08X: %02X %02X %02X", 
            TIME_HOOK_ADDR, p[0], p[1], p[2]);
        Log("WARNING: Time hook location modified/mismatch, skipping install.");
        return false;
    }

    DWORD oldProt;
    // Unprotect a larger block to cover both hook and var area
    if (!VirtualProtect((void*)TIME_HOOK_ADDR, 64, PAGE_EXECUTE_READWRITE, &oldProt)) {
        Log("ERROR: Time hook VirtualProtect failed");
        return false;
    }

    // Save original bytes
    std::memcpy(g_timeHookOrigBytes, (void*)TIME_HOOK_ADDR, 32);

    // Prepare patch: Replace function with a stub that returns our float
    // 50           push eax
    // B8 00 D0 76 00 mov eax, 0076D000 (TIME_VAR_ADDR)
    // D9 00        fld dword ptr [eax]
    // 58           pop eax
    // C3           ret
    // ... NOPs ...
    BYTE patch[16];
    std::memset(patch, 0x90, 16);
    
    patch[0] = 0x50;
    patch[1] = 0xB8;
    *(DWORD*)(patch + 2) = TIME_VAR_ADDR;
    patch[6] = 0xD9;
    patch[7] = 0x00;
    patch[8] = 0x58;
    patch[9] = 0xC3;
    
    std::memcpy((void*)TIME_HOOK_ADDR, patch, 16);
    
    // Initialize storage
    *(float*)TIME_VAR_ADDR = g_timeOfDay;
    
    g_timeHookInstalled = true;
    Log("Time hook installed at 0x%08X", TIME_HOOK_ADDR);
    return true;
}

void UninstallTimeHook() {
    if (!g_timeHookInstalled) return;
    
    DWORD oldProt;
    if (VirtualProtect((void*)TIME_HOOK_ADDR, 64, PAGE_EXECUTE_READWRITE, &oldProt)) {
        std::memcpy((void*)TIME_HOOK_ADDR, g_timeHookOrigBytes, 32);
        VirtualProtect((void*)TIME_HOOK_ADDR, 64, oldProt, &oldProt);
    }
    g_timeHookInstalled = false;
    Log("Time hook uninstalled");
}


// ================================================================
// Title Hook (MERGED into Mount Hook)
// ================================================================

extern uint32_t g_morphTitle;
extern uint32_t g_origTitle;

// ================================================================
// Mount & Title Combined Hook
// ================================================================
extern uint32_t g_morphMount;

extern uint32_t g_origMount;
extern bool g_suspended;
extern uint32_t g_morphDisplay;
extern uint32_t g_morphItems[20];
extern float g_morphScale;
extern uint32_t g_morphEnchantMH;
extern uint32_t g_morphEnchantOH;
extern uint32_t g_origEnchantMH;
extern uint32_t g_origEnchantOH;
extern uint32_t g_origItems[20];
extern uint64_t g_playerGuid; // From dllmain.cpp
extern uint32_t g_showMeta;
extern uint32_t g_keepShapeshift;

static DWORD g_mountHookAddr = 0;
static bool  g_mountHookInstalled = false;
static BYTE  g_mountHookOrigBytes[6] = {0};
volatile bool g_mountHookBypass = false;


// ================================================================
// Mount & Title Combined Hook
// ================================================================

// ================================================================
// LAYER 1: Descriptor Hook (MountDisplayHook)
// Intercepts server packets and manual descriptor writes.
// Status: Perfect Persistence via GUID-Based Identification.
// ================================================================
void __declspec(naked) MountDisplayHook()
{
    __asm
    {
        // EAX = Descriptor Base
        // EDX = Index
        // ECX = Value
        
        push eax
        push edx
        push ebx 

        cmp byte ptr [g_mountHookBypass], 1
        je do_original

        // 1. QUICK CHECK: Descriptor base must match globally verified player base
        push ebx
        mov ebx, [g_playerDescBase]
        test ebx, ebx
        jz check_guid_fallback
        cmp eax, ebx
        je is_player_verified_asm
        pop ebx
        jmp do_original

    check_guid_fallback:
        // 2. GUID IDENTIFICATION (Using globally captured g_playerGuid)
        push edi
        mov edi, offset g_playerGuid
        mov ebx, [edi]      // playerGuid Low
        test ebx, ebx       // Safety: if GUID is 0, we can't identify reliably
        jz pop_edi_ebx_orig_v
        
        cmp [eax], ebx
        jne pop_edi_ebx_orig_v
        mov ebx, [edi+4]    // playerGuid High
        cmp [eax+4], ebx
        jne pop_edi_ebx_orig_v
        
        pop edi
        pop ebx
        jmp is_player_verified

    pop_edi_ebx_orig_v:
        pop edi
        pop ebx
        jmp do_original

    is_player_verified_asm:
        pop ebx

        // It is the player!
        // ==========================================================
        // SUSPEND CHECK (Allows DBW, Barber, Vehicle, etc.)
        // ==========================================================
        cmp byte ptr [g_suspended], 1
        je do_original
        jmp is_player_verified

    pop_ebx_do_original:
        pop ebx
        jmp do_original


    is_player_verified:

        // --- CHECK 1: Mount Display (0x45) ---
        cmp edx, 0x45 
        jne check_display_id

        cmp ecx, 0 // Dismount
        jne save_mount_orig
        mov dword ptr [g_origMount], 0
        jmp do_original

    save_mount_orig:
        mov dword ptr [g_origMount], ecx

        // GHOST PROTECTION: Never morph mount visuals if the player is a ghost.
        push ebx
        mov ebx, [eax+0x10C] // UNIT_FIELD_DISPLAYID (Index 0x43 * 4 = 0x10C)
        cmp ebx, 16543
        je pop_ebx_do_original
        cmp ebx, 16544
        je pop_ebx_do_original
        pop ebx

        cmp dword ptr [g_morphMount], 0
        je do_original

        // HIDDEN_SENTINEL support
        cmp dword ptr [g_morphMount], 0xFFFFFFFF
        je do_hide_mount

        cmp dword ptr [g_morphMount], 0x01000000 // Max valid model ID approx
        ja do_original
        mov ecx, dword ptr [g_morphMount]
        jmp do_original

    do_hide_mount:
        mov ecx, 0
        jmp do_original

    check_display_id:
        // --- CHECK 1.5: Display ID (0x43) ---
        cmp edx, 0x43 // UNIT_FIELD_DISPLAYID
        jne check_items

        // ==========================================================
        // DBW / META CHECKS (Must run FIRST, before any morph logic)
        // ==========================================================
        
        // 1. Check Metamorphosis (ID: 25277)
        cmp ecx, 25277
        jne check_dbw_ids
        
        // It is Meta. Check setting.
        cmp dword ptr [g_showMeta], 1
        je do_original       // Show Meta
        
        // Block Meta (force morph if any, else force original)
        mov ebx, [g_morphDisplay]
        test ebx, ebx
        jnz do_override_generic
        mov ebx, [g_origDisplay]
        test ebx, ebx
        jnz do_override_generic
        mov ebx, [eax+0x110]
        jmp do_override_generic

    check_dbw_ids:
        // 2. Check Deathbringer's Will (CORRECT Display IDs from buff data)
        // Check ALL DBW forms first, before any other logic
        
        // Normal Heroic versions
        cmp ecx, 71484  // Taunka Strength (NH)
        je is_dbw
        cmp ecx, 71561  // Taunka Strength (HC)
        je is_dbw
        cmp ecx, 71486  // Taunka Attack Power (NH)
        je is_dbw
        cmp ecx, 71558  // Taunka Attack Power (HC)
        je is_dbw
        cmp ecx, 71485  // Vrykul Haste (NH)
        je is_dbw
        cmp ecx, 71556  // Vrykul Haste (HC)
        je is_dbw
        cmp ecx, 71492  // Vrykul Speed (NH)
        je is_dbw
        cmp ecx, 71560  // Vrykul Speed (HC)
        je is_dbw
        cmp ecx, 71491  // Iron Dwarf Crit ranged (NH)
        je is_dbw
        cmp ecx, 71559  // Iron Dwarf Crit ranged (HC)
        je is_dbw
        cmp ecx, 71487  // Iron Dwarf Crit melee (NH)
        je is_dbw
        cmp ecx, 71557  // Iron Dwarf Crit melee (HC)
        je is_dbw
        
        jmp check_morph_active // Not DBW or Meta

    is_dbw:
        // DBW proc detected!
        cmp dword ptr [g_keepShapeshift], 0
        je do_original // Option UNTICKED -> allow DBW
        
        // Option TICKED -> block DBW (force morph if any, else force original)
        mov ebx, [g_morphDisplay]
        test ebx, ebx
        jnz do_override_generic
        mov ebx, [g_origDisplay]
        test ebx, ebx
        jnz do_override_generic
        mov ebx, [eax+0x110]
        jmp do_override_generic

    check_morph_active:
        // Try active morph first
        mov ebx, dword ptr [g_morphDisplay]
        test ebx, ebx
        jnz do_keep_check
        
        // No morph set — should we still block shapeshifts?
        cmp dword ptr [g_keepShapeshift], 1
        jne do_original // Not blocking
        
        // BLOCK: Force original race
        mov ebx, dword ptr [g_origDisplay]
        test ebx, ebx
        jnz do_override_generic
        
        // Fallback: native race ID (0x110)
        mov ebx, [eax+0x110]
        test ebx, ebx
        jz do_original

    do_override_generic:
        mov ecx, ebx
        jmp do_original

    do_keep_check:
        // Already writing the target morph?
        cmp ecx, ebx
        je do_original

        // Writing the saved original display during a form teardown?
        cmp ecx, dword ptr [g_origDisplay]
        je do_override_generic

        // Writing native ID? (Offset 0x110)
        push eax
        mov eax, [eax+0x110]
        cmp ecx, eax
        pop eax
        je do_override_generic // Writing native -> force morph
        
        // Writing 0?
        test ecx, ecx
        jz do_override_generic // Writing 0 -> force morph
        
        // Writing something else! (Form or Proc)
        cmp dword ptr [g_keepShapeshift], 0
        je do_original // Option UNTICKED -> allow form
        
        // Option TICKED -> force morph
        jmp do_override_generic

    check_items:
        // --- CHECK 1.6: Items (283 to 319) ---
        cmp edx, 283
        jb check_title // If below items, skip to title (enchants are handled inside items logic for simplicity)
        cmp edx, 319
        ja check_title

        // Visibility items (1..19) are at indices 283, 285, 287...
        // We handle item IDs (even offset from 283) and enchants (odd offset) separately here.
        mov ebx, edx
        sub ebx, 283
        test ebx, 1
        jnz check_enchants_l1 // Odd offset = potential enchant

        // It's an item slot ID write
        shr ebx, 1
        inc ebx // ebx = slot (1..19)
        
        // Safety: ensure ebx is in range 1..19
        cmp ebx, 1
        jb check_title
        cmp ebx, 19
        ja check_title

        // Save original item ID
        mov [g_origItems + ebx * 4], ecx
        
        // Apply morph if exists
        push eax
        mov eax, [g_morphItems + ebx * 4]
        test eax, eax
        jz pop_eax_orig_item
        
        cmp eax, 0xFFFFFFFF // HIDDEN_SENTINEL?
        jne set_morphed_item
        mov ecx, 0
        jmp pop_eax_orig_item
    set_morphed_item:
        mov ecx, eax
    pop_eax_orig_item:
        pop eax
        jmp do_original

    check_enchants_l1:
        // Enchant writes are usually at 314 (MH) and 316 (OH)
        cmp edx, 314
        je m_enchant_l1
        cmp edx, 316
        je o_enchant_l1
        jmp do_original

    m_enchant_l1:
        mov [g_origEnchantMH], ecx
        mov ebx, [g_morphEnchantMH]
        test ebx, ebx
        jz do_original
        mov ecx, ebx
        jmp do_original

    o_enchant_l1:
        mov [g_origEnchantOH], ecx
        mov ebx, [g_morphEnchantOH]
        test ebx, ebx
        jz do_original
        mov ecx, ebx
        jmp do_original

    check_title:
        // --- CHECK 2: Chosen Title (0x141) ---
        cmp edx, 0x141 
        jne do_original

        mov dword ptr [g_origTitle], ecx
        mov ebx, [g_morphTitle]
        test ebx, ebx
        jz do_original
        mov ecx, ebx
        jmp do_original

    do_original:
        pop ebx
        pop edx
        pop eax
        
        // Conditional Write: Only write if value is different.
        // This prevents the engine from marking descriptors as 'dirty' 
        // and triggering unnecessary model reloads (UpdateDisplayInfo).
        cmp [eax+edx*4], ecx
        je skip_final_write
        mov [eax+edx*4], ecx
    skip_final_write:
        pop ebp
        ret 8
    }
}

bool InstallMountHook()
{
    DWORD base = (DWORD)GetModuleHandleA("Wow.exe");
    if (!base) base = (DWORD)GetModuleHandleA("WoW.exe");
    if (!base) base = (DWORD)GetModuleHandleA(NULL);
    if (!base) return false;
    
    g_mountHookAddr = FindDescriptorWriteHook(base);
    if (g_mountHookAddr == 0) {
        // Fallback to hardcoded if scan fails
        g_mountHookAddr = base + 0x343BAC; 
    }

    // Verify pattern at address: 89 0C 90 (mov [eax+edx*4], ecx)
    // And ensure followed by 5D C2 (pop ebp; ret ...)
    BYTE* ptr = (BYTE*)g_mountHookAddr;
    __try {
        if (ptr[0] != 0x89 || ptr[1] != 0x0C || ptr[2] != 0x90) {
            Log("ERROR: Mount hook pattern mismatch at %p (got %02X %02X %02X)", (void*)g_mountHookAddr, ptr[0], ptr[1], ptr[2]);
            g_mountHookAddr = 0;
            return false;
        }
        if (ptr[3] != 0x5D || ptr[4] != 0xC2) {
             Log("ERROR: Mount hook epilogue mismatch at %p (got %02X %02X)", (void*)g_mountHookAddr, ptr[3], ptr[4]);
             g_mountHookAddr = 0;
             return false;
        }
    } __except(1) {
        Log("ERROR: Exception verifying mount hook at %p", (void*)g_mountHookAddr);
        g_mountHookAddr = 0;
        return false;
    }

    const int LEN = 5;
    memcpy(g_mountHookOrigBytes, (void*)g_mountHookAddr, LEN);

    DWORD oldProt;
    if (!VirtualProtect((void*)g_mountHookAddr, LEN, PAGE_EXECUTE_READWRITE, &oldProt)) {
        Log("ERROR: VirtualProtect failed at %p (err=%lu)", (void*)g_mountHookAddr, GetLastError());
        g_mountHookAddr = 0;
        return false;
    }

    *(BYTE*)g_mountHookAddr = 0xE9;
    *(DWORD*)(g_mountHookAddr + 1) = (DWORD)&MountDisplayHook - g_mountHookAddr - 5;

    g_mountHookInstalled = true;
    Log("Mount hook installed at 0x%08X", g_mountHookAddr);
    return true;
}

void UninstallMountHook()
{
    if (!g_mountHookInstalled || !g_mountHookAddr) return;
    DWORD oldProt;
    if (VirtualProtect((void*)g_mountHookAddr, 5, PAGE_EXECUTE_READWRITE, &oldProt)) {
        memcpy((void*)g_mountHookAddr, g_mountHookOrigBytes, 5);
        VirtualProtect((void*)g_mountHookAddr, 5, oldProt, &oldProt);
    }
    g_mountHookInstalled = false;
}

// ================================================================
// LAYER 2: Visual Update Hook (UpdateDisplayInfoHook)
// Enforces appearance & mount just before the 3D model is rebuilt.
// Status: "Perfect Persistence" via Dynamic Prologue Reconstruction.
// ================================================================
static DWORD g_updateDisplayHookAddr = 0;
static bool  g_updateDisplayHookInstalled = false;
static BYTE  g_updateDisplayHookOrigBytes[6] = {0};

// Flag to track which prologue variant we're dealing with
bool g_updateDisplayPrologueIs83 = false;
uint32_t g_updateDisplayPrologueSub = 0;  // The sub esp operand (1-byte or 4-byte)

void __declspec(naked) UpdateDisplayInfoHook()
{
    __asm
    {
        // ECX = 'this' pointer (Unit*)
        
        push eax
        push edx
        push ecx
        
        cmp byte ptr [g_suspended], 1
        je do_orig_v

        // EAX = descriptors base from Unit*
        mov eax, [ecx+8]
        test eax, eax
        jz do_orig_v

        // GUID IDENTIFICATION: Only proceed if it is the local player
        push edi
        push ebx
        
        // 1. Match against verified player descriptor base
        mov ebx, [g_playerDescBase]
        test ebx, ebx
        jz check_guid_fallback_v
        cmp eax, ebx
        je is_player_verified_v
        
    check_guid_fallback_v:
        // 2. Fallback to GUID check
        mov edi, offset g_playerGuid
        mov ebx, [edi]      // playerGuid Low
        test ebx, ebx
        jz pop_ebx_edi_orig_v_asm
        
        cmp [eax], ebx
        jne pop_ebx_edi_orig_v_asm
        mov ebx, [edi + 4]  // playerGuid High
        cmp [eax + 4], ebx
        jne pop_ebx_edi_orig_v_asm
        
        pop ebx
        pop edi
        
        // It is the player! Save the base and proceed
        mov [g_playerDescBase], eax
        jmp do_verified_v

    pop_ebx_edi_orig_v_asm:
        pop ebx
        pop edi
        jmp do_orig_v

    is_player_verified_v:
        pop ebx
        pop edi
        jmp do_verified_v


    do_verified_v:
        push ebx
        
        // READ NATIVE MOUNT ID: Only morph if WoW actually wants to render a mount.
        // This prevents the dismount race condition where the hook forces 
        // a mount ID on during the transition, causing a visual flash.
        mov ebx, [eax+0x114] 
        test ebx, ebx
        jz handle_items_morph

        // LEAKAGE PREVENTION: Only morph if the Transmorpher addon says we are mounted.
        // This fixes the issue where ghost gryphons or vehicles were overridden
        // because WoW's mount field was non-zero.
        cmp dword ptr [g_luaMounted], 1
        jne handle_items_morph

        // GHOST PROTECTION: Never morph mount visuals if the player is a ghost.
        // Ghost IDs: 16543 (Male), 16544 (Female).
        mov ebx, [eax+UNIT_FIELD_DISPLAYID]
        cmp ebx, 16543
        je handle_items_morph
        cmp ebx, 16544
        je handle_items_morph

        mov ebx, dword ptr [g_morphMount]
        cmp ebx, 0
        je handle_items_morph  // No morph set — let game use native mount

    write_mount:
        cmp ebx, 0xFFFFFFFF // HIDDEN_SENTINEL
        jne do_cmp_mount
        xor ebx, ebx
    do_cmp_mount:
        cmp [eax+0x114], ebx
        je handle_items_morph
        mov [eax+0x114], ebx

    handle_items_morph:
        // ENFORCE WEAPON MORPHS (283-319, slot 16, 17, 18)
        // 283 = Left/Right Hand Item ID start
        // Slot 16 (Main Hand) = index 283 + (16-1)*2 = 283 + 30 = 313 -> Wait, no.
        // Slot = (Index - 283) / 2 + 1
        // Index = (Slot - 1) * 2 + 283
        
        // Slot 16 (Main Hand): Index = 15*2 + 283 = 313
        // Slot 17 (Off Hand): Index = 16*2 + 283 = 315
        // Slot 18 (Ranged): Index = 17*2 + 283 = 317
        
        push esi
        push edi
        
        // Main Hand (Slot 16)
        mov esi, dword ptr [g_morphItems + 16*4]
        test esi, esi
        jz check_oh_v
        cmp esi, 0xFFFFFFFF // HIDDEN_SENTINEL
        jne write_mh_v
        xor esi, esi
    write_mh_v:
        mov [eax+313*4], esi
        
    check_oh_v:
        // Off Hand (Slot 17)
        mov esi, dword ptr [g_morphItems + 17*4]
        test esi, esi
        jz check_ranged_v
        cmp esi, 0xFFFFFFFF // HIDDEN_SENTINEL
        jne write_oh_v
        xor esi, esi
    write_oh_v:
        mov [eax+315*4], esi

    check_ranged_v:
        // Ranged (Slot 18)
        mov esi, dword ptr [g_morphItems + 18*4]
        test esi, esi
        jz check_enchants_v
        cmp esi, 0xFFFFFFFF // HIDDEN_SENTINEL
        jne write_ranged_v
        xor esi, esi
    write_ranged_v:
        mov [eax+317*4], esi

    check_enchants_v:
        // MH Enchant (314)
        mov esi, dword ptr [g_morphEnchantMH]
        test esi, esi
        jz check_oh_ench_v
        mov [eax+314*4], esi
    check_oh_ench_v:
        // OH Enchant (316)
        mov esi, dword ptr [g_morphEnchantOH]
        test esi, esi
        jz pop_si_di_v
        mov [eax+316*4], esi

    pop_si_di_v:
        pop edi
        pop esi

    handle_base_morph:
        // Current display ID is at [eax+0x10C]
        mov ebx, [eax+0x10C]
        
        // 1. Check Metamorphosis (ID: 25277)
        cmp ebx, 25277
        jne check_other_forms_v
        
        // It is Meta. Should we show it?
        cmp dword ptr [g_showMeta], 1
        je pop_ebx_and_cont // Option TICKED -> Show Meta (do nothing)
        
        // Option UNTICKED -> Override Meta with morph (or native)
        jmp write_morph_v

    check_other_forms_v:
        // 2. Check if it is a DBW / Druid form (different from native)
        // Native display ID is at [eax+0x110]
        cmp ebx, [eax+0x110]
        je write_morph_v    // If current IS native, proceed to write morph normally

        // Saved original display can briefly appear when forms end; treat it like a transition
        cmp ebx, dword ptr [g_origDisplay]
        je write_morph_v
        
        // It is a form! Should we keep morph?
        cmp dword ptr [g_keepShapeshift], 1
        je write_morph_v    // Option TICKED -> Override form with morph
        
        // Option UNTICKED -> Allow form (do nothing)
        jmp pop_ebx_and_cont

    write_morph_v:
        mov ebx, dword ptr [g_morphDisplay]
        test ebx, ebx
        jnz do_write_v
        
        // No morph set, use native
        mov ebx, [eax+0x110]
        test ebx, ebx
        jz pop_ebx_and_cont

    do_write_v:
        cmp [eax+0x10C], ebx
        je pop_ebx_and_cont
        mov [eax+0x10C], ebx

    pop_ebx_and_cont:
        pop ebx

    do_orig_v:
        pop ecx
        pop edx
        pop eax

        // Reconstruct original prologue: push ebp; mov ebp, esp
        push ebp
        mov ebp, esp
        
        // Branch based on prologue variant
        cmp byte ptr [g_updateDisplayPrologueIs83], 1
        je short_sub_variant

        // 81 EC variant: sub esp, DWORD (use saved g_updateDisplayPrologueSub)
        push eax
        mov eax, [g_updateDisplayPrologueSub]
        sub esp, eax
        pop eax
        push g_updateDisplayHookAddr
        add dword ptr [esp], 9  // skip 9 bytes: 55 8B EC 81 EC xx xx xx xx
        ret

    short_sub_variant:
        // 83 EC variant: sub esp, BYTE (use saved g_updateDisplayPrologueSub)
        push eax
        mov eax, [g_updateDisplayPrologueSub]
        sub esp, eax
        pop eax
        push g_updateDisplayHookAddr
        add dword ptr [esp], 6  // skip 6 bytes: 55 8B EC 83 EC xx
        ret
    }
}




bool InstallUpdateDisplayInfoHook()
{
    DWORD base = (DWORD)GetModuleHandleA("Wow.exe");
    if (!base) base = (DWORD)GetModuleHandleA("WoW.exe");
    if (!base) base = (DWORD)GetModuleHandleA(NULL);
    if (!base) return false;

    g_updateDisplayHookAddr = FindUpdateDisplayInfoHook(base);
    if (g_updateDisplayHookAddr == 0) {
        // Fallback: 3.3.5a 12340 CGUnit_C::UpdateDisplayInfo 
        g_updateDisplayHookAddr = base + 0x33DE30;
        if (CGUnit_UpdateDisplayInfo) {
            g_updateDisplayHookAddr = (DWORD)(uintptr_t)CGUnit_UpdateDisplayInfo;
        }
    }
    
    if (g_updateDisplayHookAddr == 0) return false;

    // Verify prologue: 55 8B EC (81 EC | 83 EC)
    BYTE* ptr = (BYTE*)g_updateDisplayHookAddr;
    int hookLen = 0;
    __try {
        if (ptr[0] != 0x55 || ptr[1] != 0x8B || ptr[2] != 0xEC) {
            Log("ERROR: UpdateDisplayInfo hook prologue mismatch (got %02X %02X %02X)", 
                ptr[0], ptr[1], ptr[2]);
            return false;
        }
        if (ptr[3] == 0x81 && ptr[4] == 0xEC) {
            // sub esp, DWORD — 9 bytes total (55 8B EC 81 EC xx xx xx xx)
            g_updateDisplayPrologueIs83 = false;
            g_updateDisplayPrologueSub = *(uint32_t*)&ptr[5]; // Save the operand
            hookLen = 9;
            Log("UpdateDisplayInfo prologue: sub esp, DWORD (81 EC) val=0x%X", g_updateDisplayPrologueSub);
        } else if (ptr[3] == 0x83 && ptr[4] == 0xEC) {
            // sub esp, BYTE — 6 bytes total (55 8B EC 83 EC xx)
            g_updateDisplayPrologueIs83 = true;
            g_updateDisplayPrologueSub = (uint32_t)ptr[5]; // Save the operand
            hookLen = 6;
            Log("UpdateDisplayInfo prologue: sub esp, 0x%02X (83 EC)", ptr[5]);
        } else {
            Log("ERROR: UpdateDisplayInfo hook sub esp mismatch (got %02X %02X at +3)", 
                ptr[3], ptr[4]);
            return false;
        }
    } __except(1) { return false; }

    std::memcpy(g_updateDisplayHookOrigBytes, (void*)(uintptr_t)g_updateDisplayHookAddr, hookLen);

    DWORD oldProt;
    if (!VirtualProtect((void*)(uintptr_t)g_updateDisplayHookAddr, hookLen, PAGE_EXECUTE_READWRITE, &oldProt)) {
        return false;
    }

    // Write JMP to our hook
    *(BYTE*)(uintptr_t)g_updateDisplayHookAddr = 0xE9;
    *(DWORD*)(uintptr_t)(g_updateDisplayHookAddr + 1) = (DWORD)((uintptr_t)&UpdateDisplayInfoHook - (uintptr_t)g_updateDisplayHookAddr - 5);
    // NOP remaining bytes
    for (int i = 5; i < hookLen; i++) {
        *(BYTE*)(uintptr_t)(g_updateDisplayHookAddr + i) = 0x90;
    }

    g_updateDisplayHookInstalled = true;
    Log("UpdateDisplayInfo hook installed at 0x%08X (len=%d)", (unsigned)g_updateDisplayHookAddr, hookLen);

    return true;
}

void UninstallUpdateDisplayInfoHook() {
    if (!g_updateDisplayHookInstalled || !g_updateDisplayHookAddr) return;
    DWORD oldProt;
    if (VirtualProtect((void*)(uintptr_t)g_updateDisplayHookAddr, 5, PAGE_EXECUTE_READWRITE, &oldProt)) {
        std::memcpy((void*)(uintptr_t)g_updateDisplayHookAddr, g_updateDisplayHookOrigBytes, 5);
        VirtualProtect((void*)(uintptr_t)g_updateDisplayHookAddr, 5, oldProt, &oldProt);
        FlushInstructionCache(GetCurrentProcess(), (void*)(uintptr_t)g_updateDisplayHookAddr, 5);
    }
    g_updateDisplayHookInstalled = false;
    Log("UpdateDisplayInfo hook uninstalled");
}
