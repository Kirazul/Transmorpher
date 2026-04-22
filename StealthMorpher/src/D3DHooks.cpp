#include "D3DHooks.h"

#include <cstring>

#include <windows.h>
#include <d3d9.h>

#include "Logger.h"
#include "RenderOverrides.h"

static bool g_d3dHooksActive = false;
static IDirect3DDevice9* g_device = nullptr;
static DWORD* g_vtable = nullptr;
static HRESULT(WINAPI* g_originalEndScene)(IDirect3DDevice9*) = nullptr;
static HRESULT(WINAPI* g_originalReset)(IDirect3DDevice9*, D3DPRESENT_PARAMETERS*) = nullptr;
static HRESULT(WINAPI* g_originalSetRenderState)(IDirect3DDevice9*, D3DRENDERSTATETYPE, DWORD) = nullptr;
static HRESULT(WINAPI* g_originalSetSamplerState)(IDirect3DDevice9*, DWORD, D3DSAMPLERSTATETYPE, DWORD) = nullptr;

static BYTE g_endSceneOriginalBytes[5];
static DWORD g_endSceneAddr = 0;
static bool g_endSceneDetoured = false;
static bool g_deviceCaptured = false;
static DWORD g_lastD3DNotLoadedLogTick = 0;
static bool g_applyingInternalOverrides = false;

static HRESULT WINAPI HookedReset(IDirect3DDevice9* device, D3DPRESENT_PARAMETERS* params) {
    return g_originalReset ? g_originalReset(device, params) : D3D_OK;
}

static HRESULT WINAPI HookedSetRenderState(IDirect3DDevice9* device, D3DRENDERSTATETYPE state, DWORD value) {
    if (!g_applyingInternalOverrides) {
        RenderOverrides_OnSetRenderState(device, state, &value);
    }
    return g_originalSetRenderState ? g_originalSetRenderState(device, state, value) : D3D_OK;
}

static HRESULT WINAPI HookedSetSamplerState(IDirect3DDevice9* device, DWORD sampler, D3DSAMPLERSTATETYPE type, DWORD value) {
    if (!g_applyingInternalOverrides) {
        RenderOverrides_OnSetSamplerState(device, sampler, type, &value);
    }
    return g_originalSetSamplerState ? g_originalSetSamplerState(device, sampler, type, value) : D3D_OK;
}

static HRESULT WINAPI HookedEndScene(IDirect3DDevice9* device);

static void RestoreInlineHook() {
    if (!g_endSceneDetoured || !g_endSceneAddr) return;
    DWORD oldProt = 0;
    if (VirtualProtect((void*)g_endSceneAddr, 5, PAGE_EXECUTE_READWRITE, &oldProt)) {
        memcpy((void*)g_endSceneAddr, g_endSceneOriginalBytes, 5);
        VirtualProtect((void*)g_endSceneAddr, 5, oldProt, &oldProt);
        FlushInstructionCache(GetCurrentProcess(), (void*)g_endSceneAddr, 5);
    }
}

static HRESULT WINAPI HookedEndScene(IDirect3DDevice9* device) {
    if (!g_deviceCaptured) {
        g_device = device;
        g_device->AddRef();
        g_vtable = (DWORD*)*(DWORD*)device;

        if (g_vtable) {
            g_originalEndScene = (HRESULT(WINAPI*)(IDirect3DDevice9*))g_vtable[42];
            g_originalReset = (HRESULT(WINAPI*)(IDirect3DDevice9*, D3DPRESENT_PARAMETERS*))g_vtable[16];
            g_originalSetRenderState = (HRESULT(WINAPI*)(IDirect3DDevice9*, D3DRENDERSTATETYPE, DWORD))g_vtable[57];
            g_originalSetSamplerState = (HRESULT(WINAPI*)(IDirect3DDevice9*, DWORD, D3DSAMPLERSTATETYPE, DWORD))g_vtable[69];

            DWORD oldProt = 0;
            if (VirtualProtect(&g_vtable[16], 4, PAGE_EXECUTE_READWRITE, &oldProt)) {
                g_vtable[16] = (DWORD)HookedReset;
                VirtualProtect(&g_vtable[16], 4, oldProt, &oldProt);
            }
            if (VirtualProtect(&g_vtable[42], 4, PAGE_EXECUTE_READWRITE, &oldProt)) {
                g_vtable[42] = (DWORD)HookedEndScene;
                VirtualProtect(&g_vtable[42], 4, oldProt, &oldProt);
            }
            if (VirtualProtect(&g_vtable[57], 4, PAGE_EXECUTE_READWRITE, &oldProt)) {
                g_vtable[57] = (DWORD)HookedSetRenderState;
                VirtualProtect(&g_vtable[57], 4, oldProt, &oldProt);
            }
            if (VirtualProtect(&g_vtable[69], 4, PAGE_EXECUTE_READWRITE, &oldProt)) {
                g_vtable[69] = (DWORD)HookedSetSamplerState;
                VirtualProtect(&g_vtable[69], 4, oldProt, &oldProt);
            }
        }

        RestoreInlineHook();
        g_deviceCaptured = true;
        Log("Captured game device: 0x%p, vtable: 0x%p, EndScene: 0x%p", g_device, g_vtable, g_originalEndScene);
    }

    g_applyingInternalOverrides = true;
    RenderOverrides_ApplyDeviceOverrides(device);
    g_applyingInternalOverrides = false;
    return g_originalEndScene(device);
}

static bool InstallInlineHook(DWORD targetAddr, DWORD hookAddr, BYTE* originalBytes) {
    if (!targetAddr || !hookAddr) return false;

    memcpy(originalBytes, (void*)targetAddr, 5);

    DWORD oldProt = 0;
    if (!VirtualProtect((void*)targetAddr, 5, PAGE_EXECUTE_READWRITE, &oldProt)) {
        return false;
    }

    BYTE* jmpInstr = (BYTE*)targetAddr;
    jmpInstr[0] = 0xE9;
    *(DWORD*)(jmpInstr + 1) = hookAddr - targetAddr - 5;

    VirtualProtect((void*)targetAddr, 5, oldProt, &oldProt);
    FlushInstructionCache(GetCurrentProcess(), (void*)targetAddr, 5);
    return true;
}

void D3DHooks_Initialize() {
    if (g_d3dHooksActive) return;

    RenderOverrides_Initialize();

    HMODULE d3d9 = GetModuleHandleA("d3d9.dll");
    if (!d3d9) {
        const DWORD now = GetTickCount();
        if (now - g_lastD3DNotLoadedLogTick > 5000u) {
            Log("D3D9 not loaded yet");
            g_lastD3DNotLoadedLogTick = now;
        }
        return;
    }

    typedef IDirect3D9* (WINAPI* Direct3DCreate9_t)(UINT);
    Direct3DCreate9_t createD3D = (Direct3DCreate9_t)GetProcAddress(d3d9, "Direct3DCreate9");
    if (!createD3D) return;

    IDirect3D9* d3d = createD3D(D3D_SDK_VERSION);
    if (!d3d) return;

    HWND tempWnd = CreateWindowA("STATIC", "", WS_DISABLED, 0, 0, 1, 1, NULL, NULL, GetModuleHandleA(NULL), NULL);
    if (tempWnd) {
        D3DPRESENT_PARAMETERS pp = {};
        pp.Windowed = TRUE;
        pp.SwapEffect = D3DSWAPEFFECT_DISCARD;
        pp.BackBufferFormat = D3DFMT_UNKNOWN;

        IDirect3DDevice9* dev = NULL;
        HRESULT hr = d3d->CreateDevice(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, tempWnd, D3DCREATE_SOFTWARE_VERTEXPROCESSING, &pp, &dev);
        if (SUCCEEDED(hr) && dev) {
            DWORD* vtable = (DWORD*)*(DWORD*)dev;
            g_endSceneAddr = vtable[42];

            if (InstallInlineHook(g_endSceneAddr, (DWORD)HookedEndScene, g_endSceneOriginalBytes)) {
                g_endSceneDetoured = true;
                Log("EndScene inline hook installed at 0x%X", g_endSceneAddr);
            } else {
                Log("Failed to install EndScene inline hook");
            }

            dev->Release();
        }
        DestroyWindow(tempWnd);
    }

    d3d->Release();
    g_d3dHooksActive = true;
}

void D3DHooks_Shutdown() {
    if (!g_d3dHooksActive) return;

    if (g_endSceneDetoured) {
        RestoreInlineHook();
        g_endSceneDetoured = false;
    }

    if (g_vtable && g_originalReset) {
        DWORD oldProt = 0;
        VirtualProtect(&g_vtable[16], 4, PAGE_EXECUTE_READWRITE, &oldProt);
        g_vtable[16] = (DWORD)g_originalReset;
        VirtualProtect(&g_vtable[16], 4, oldProt, &oldProt);
    }
    if (g_vtable && g_originalSetRenderState) {
        DWORD oldProt = 0;
        VirtualProtect(&g_vtable[57], 4, PAGE_EXECUTE_READWRITE, &oldProt);
        g_vtable[57] = (DWORD)g_originalSetRenderState;
        VirtualProtect(&g_vtable[57], 4, oldProt, &oldProt);
    }
    if (g_vtable && g_originalSetSamplerState) {
        DWORD oldProt = 0;
        VirtualProtect(&g_vtable[69], 4, PAGE_EXECUTE_READWRITE, &oldProt);
        g_vtable[69] = (DWORD)g_originalSetSamplerState;
        VirtualProtect(&g_vtable[69], 4, oldProt, &oldProt);
    }
    if (g_vtable && g_originalEndScene) {
        DWORD oldProt = 0;
        VirtualProtect(&g_vtable[42], 4, PAGE_EXECUTE_READWRITE, &oldProt);
        g_vtable[42] = (DWORD)g_originalEndScene;
        VirtualProtect(&g_vtable[42], 4, oldProt, &oldProt);
    }

    if (g_device) {
        g_device->Release();
        g_device = nullptr;
    }

    g_d3dHooksActive = false;
    RenderOverrides_Shutdown();
    Log("D3D hooks shutdown");
}
