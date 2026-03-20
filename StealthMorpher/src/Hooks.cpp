#include "Hooks.h"
#include "Logger.h"
#include "WoWOffsets.h"
#include "Utils.h"
#include <cstdio>

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
    memcpy(g_timeHookOrigBytes, (void*)TIME_HOOK_ADDR, 32);

    // Prepare patch: Replace function with a stub that returns our float
    // 50           push eax
    // B8 00 D0 76 00 mov eax, 0076D000 (TIME_VAR_ADDR)
    // D9 00        fld dword ptr [eax]
    // 58           pop eax
    // C3           ret
    // ... NOPs ...
    BYTE patch[16];
    memset(patch, 0x90, 16);
    
    patch[0] = 0x50;
    patch[1] = 0xB8;
    *(DWORD*)(patch + 2) = TIME_VAR_ADDR;
    patch[6] = 0xD9;
    patch[7] = 0x00;
    patch[8] = 0x58;
    patch[9] = 0xC3;
    
    memcpy((void*)TIME_HOOK_ADDR, patch, 16);
    
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
        memcpy((void*)TIME_HOOK_ADDR, g_timeHookOrigBytes, 32);
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
#include "Morpher.h"

extern uint32_t g_origMount;
extern bool g_suspended;
extern uint32_t g_morphDisplay;
extern uint32_t g_morphItems[20];
extern float g_morphScale;
extern uint32_t g_morphEnchantMH;
extern uint32_t g_morphEnchantOH;
extern uint64_t g_playerGuid; // From dllmain.cpp

static DWORD g_mountHookAddr = 0;
static bool  g_mountHookInstalled = false;
static BYTE  g_mountHookOrigBytes[6] = {0};
volatile bool g_mountHookBypass = false;

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

        // GET LOCAL PLAYER GUID (Instant lookup from Object Manager)
        mov ebx, 0x00C79CE0
        mov ebx, [ebx]
        test ebx, ebx
        jz do_original
        mov ebx, [ebx+0x2ED0]
        test ebx, ebx
        jz do_original
        
        push edi
        mov edi, [ebx+0xC0] // playerGuid Low
        cmp [eax], edi
        jne pop_edi_orig_v 
        
        mov edi, [ebx+0xC4] // playerGuid High
        cmp [eax+4], edi
        jne pop_edi_orig_v
        
        pop edi

        // It is the player!
        // ==========================================================
        // SUSPEND CHECK (Allows DBW, Barber, Vehicle, etc.)
        // ==========================================================
        cmp byte ptr [g_suspended], 1
        je do_original
        jmp is_player_verified

    pop_edi_orig_v:
        pop edi
        jmp do_original

    is_player_verified:

        // --- CHECK 1: Mount Display (0x45) ---
        cmp edx, 0x45 
        jne check_display_id

        cmp ecx, 0 // Dismount
        je do_original

        mov dword ptr [g_origMount], ecx
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
        jmp do_override_display // Hide Meta

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
        // Check if user wants to HIDE DBW procs (showDBW = 0)
        cmp dword ptr [g_showDBW], 0
        jne do_original // If showDBW = 1, allow DBW to show
        
        // User wants to hide DBW (showDBW = 0)
        // Check if we have an active morph to show instead
        cmp dword ptr [g_morphDisplay], 0
        je do_original // No morph active, show native character
        
        // We have a morph, show it instead of DBW
        mov ecx, dword ptr [g_morphDisplay]
        jmp do_original

    check_morph_active:
        // Now check if we have an active morph
        cmp dword ptr [g_morphDisplay], 0
        je do_original

        // If we are already writing the morph ID, just let it go through
        cmp ecx, dword ptr [g_morphDisplay]
        je do_original

        // Check if the game is trying to write the NATIVE display ID (Index 0x44 = 0x110)
        // If it is, we override it with our morph to prevent flicker.
        // If it's writing something else (like a shapeshift form), we let it pass.
        mov ebx, [eax + 0x110] 
        cmp ecx, ebx
        je do_override_display
        
        // Also override if the game writes 0 (often happens during model refreshes)
        test ecx, ecx
        jz do_override_display
        
        // Shapeshift check (only relevant if we have a morph active)
        cmp dword ptr [g_keepShapeshift], 1
        je do_override_display // Hide Form
        jmp do_original        // Show Form

    do_override_display:
        mov ecx, dword ptr [g_morphDisplay]
        jmp do_original

    check_items:
        // --- CHECK 1.6: Items (283 to 319) ---
        cmp edx, 283
        jb check_enchants
        cmp edx, 319
        ja check_enchants

        // Index 283..319 contains visible item fields
        // Slot = (Index - 283) / 2 + 1
        mov ebx, edx
        sub ebx, 283
        test ebx, 1
        jnz do_original // Ignore odd indexes (enchants/etc) for now

        shr ebx, 1
        inc ebx // ebx = slot (1..19)
        
        // Safety: ensure ebx is in range 1..19
        cmp ebx, 1
        jb do_original
        cmp ebx, 19
        ja do_original

        // Access g_morphItems[ebx]
        // EAX is already on stack, we can use it
        push eax
        mov eax, ebx
        shl eax, 2 // * 4
        add eax, offset g_morphItems
        mov eax, [eax]
        
        test eax, eax
        jz pop_eax_and_original
        
        cmp eax, 0xFFFFFFFF // HIDDEN_SENTINEL
        jne set_item_val
        mov ecx, 0
        jmp pop_eax_and_original
        
    set_item_val:
        mov ecx, eax
    pop_eax_and_original:
        pop eax
        jmp do_original

    check_enchants:
        // --- CHECK 1.7: Weapon Enchants (314, 316) ---
        cmp edx, 314 // MH Enchant
        je check_mh
        cmp edx, 316 // OH Enchant
        je check_oh
        jmp check_title

    check_mh:
        cmp dword ptr [g_morphEnchantMH], 0
        je do_original
        mov ecx, dword ptr [g_morphEnchantMH]
        jmp do_original

    check_oh:
        cmp dword ptr [g_morphEnchantOH], 0
        je do_original
        mov ecx, dword ptr [g_morphEnchantOH]
        jmp do_original

    check_title:
        // --- CHECK 2: Chosen Title (0x141) ---
        cmp edx, 0x141 
        jne do_original

        mov dword ptr [g_origTitle], ecx
        cmp dword ptr [g_morphTitle], 0
        je do_original
        mov ecx, dword ptr [g_morphTitle]
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

        mov eax, [ecx+8]
        test eax, eax
        jz do_orig_v

        // GET LOCAL PLAYER GUID (Instant lookup from Object Manager)
        mov edx, 0x00C79CE0
        mov edx, [edx]
        test edx, edx
        jz do_orig_v
        mov edx, [edx+0x2ED0]
        test edx, edx
        jz do_orig_v
        
        push ebx
        mov ebx, [edx+0xC0] // playerGuid Low
        cmp [eax], ebx
        jne pop_ebx_orig_v
        
        mov ebx, [edx+0xC4] // playerGuid High
        cmp [eax+4], ebx
        jne pop_ebx_orig_v
        
        pop ebx
        jmp do_verified_v

    pop_ebx_orig_v:
        pop ebx
        jmp do_orig_v

    do_verified_v:
        push ebx
        
        // READ NATIVE MOUNT ID: Only morph if WoW actually wants to render a mount.
        // This prevents the dismount race condition where the hook forces 
        // a mount ID on during the transition, causing a visual flash.
        mov ebx, [eax+0x114] 
        test ebx, ebx
        jz handle_base_morph

        mov ebx, dword ptr [g_morphMount]
        cmp ebx, 0
        je handle_base_morph  // No morph set — let game use native mount

    write_mount:
        cmp ebx, 0xFFFFFFFF // HIDDEN_SENTINEL
        jne do_cmp_mount
        xor ebx, ebx
    do_cmp_mount:
        cmp [eax+0x114], ebx
        je handle_base_morph
        mov [eax+0x114], ebx

    handle_base_morph:
        mov ebx, dword ptr [g_morphDisplay]
        cmp ebx, 0
        je pop_ebx_and_cont
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
        // Fallback
        g_updateDisplayHookAddr = base + 0x33E410;
        if (CGUnit_UpdateDisplayInfo) {
            g_updateDisplayHookAddr = (DWORD)CGUnit_UpdateDisplayInfo;
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

    memcpy(g_updateDisplayHookOrigBytes, (void*)g_updateDisplayHookAddr, hookLen);

    DWORD oldProt;
    if (!VirtualProtect((void*)g_updateDisplayHookAddr, hookLen, PAGE_EXECUTE_READWRITE, &oldProt)) {
        return false;
    }

    // Write JMP to our hook
    *(BYTE*)g_updateDisplayHookAddr = 0xE9;
    *(DWORD*)(g_updateDisplayHookAddr + 1) = (DWORD)&UpdateDisplayInfoHook - g_updateDisplayHookAddr - 5;
    // NOP remaining bytes
    for (int i = 5; i < hookLen; i++) {
        *(BYTE*)(g_updateDisplayHookAddr + i) = 0x90;
    }

    g_updateDisplayHookInstalled = true;
    Log("UpdateDisplayInfo hook installed at 0x%08X (len=%d)", g_updateDisplayHookAddr, hookLen);
    return true;
}


void UninstallUpdateDisplayInfoHook() {
    if (!g_updateDisplayHookInstalled || !g_updateDisplayHookAddr) return;
    DWORD oldProt;
    if (VirtualProtect((void*)g_updateDisplayHookAddr, 5, PAGE_EXECUTE_READWRITE, &oldProt)) {
        memcpy((void*)g_updateDisplayHookAddr, g_updateDisplayHookOrigBytes, 5);
        VirtualProtect((void*)g_updateDisplayHookAddr, 5, oldProt, &oldProt);
    }
    g_updateDisplayHookInstalled = false;
    Log("UpdateDisplayInfo hook uninstalled");
}
