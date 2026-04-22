#pragma once

#include <windows.h>
#include <d3d9.h>

struct RenderOverrideConfig {
    bool smoothTextures;
    float smoothTextureBias;

    bool worldFogEnabled;
    D3DCOLOR worldFogColor;
    float worldFogStart;
    float worldFogEnd;

    bool worldFarClipEnabled;
    float worldFarClip;
};

void RenderOverrides_Initialize();
void RenderOverrides_Shutdown();

void RenderOverrides_SetSmoothTextures(bool enabled);
void RenderOverrides_SetSmoothTextureBias(float value);

void RenderOverrides_SetWorldFogEnabled(bool enabled);
void RenderOverrides_SetWorldFogColor(D3DCOLOR color);
void RenderOverrides_SetWorldFogStart(float value);
void RenderOverrides_SetWorldFogEnd(float value);
void RenderOverrides_SetWorldFarClipEnabled(bool enabled);
void RenderOverrides_SetWorldFarClip(float distance);
void RenderOverrides_RefreshWorldState();
void RenderOverrides_ApplyDeviceOverrides(IDirect3DDevice9* device);

bool RenderOverrides_OnSetRenderState(IDirect3DDevice9* device, D3DRENDERSTATETYPE state, DWORD* value);
bool RenderOverrides_OnSetSamplerState(IDirect3DDevice9* device, DWORD sampler, D3DSAMPLERSTATETYPE type, DWORD* value);
