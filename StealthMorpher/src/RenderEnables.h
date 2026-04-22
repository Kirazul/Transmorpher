#pragma once

void RenderEnables_Initialize();
void RenderEnables_Shutdown();
void RenderEnables_Apply();

void RenderEnables_SetM2(bool enabled);
void RenderEnables_SetTerrain(bool enabled);
void RenderEnables_SetTerrainCulling(bool enabled);
void RenderEnables_SetM2WmoShadow(bool enabled);
void RenderEnables_SetWmo(bool enabled);
void RenderEnables_SetWmoLighting(bool enabled);
void RenderEnables_SetFootprints(bool enabled);
void RenderEnables_SetWmoTextures(bool enabled);
void RenderEnables_SetWmoPortals(bool enabled);
void RenderEnables_SetOccluders(bool enabled);
void RenderEnables_SetM2Fade(bool enabled);
void RenderEnables_SetGroundClutter(bool enabled);
void RenderEnables_SetCollision(bool enabled);
void RenderEnables_SetLiquidSurface(bool enabled);
void RenderEnables_SetLiquidParticles(bool enabled);
void RenderEnables_SetMountains(bool enabled);
void RenderEnables_SetSpecularLighting(bool enabled);
void RenderEnables_SetRenderObjectShadow(bool enabled);
void RenderEnables_SetWireframe(bool enabled);
void RenderEnables_SetNormals(bool enabled);
