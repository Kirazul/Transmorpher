#pragma once

#include <Windows.h>
#include <Detours/detours.h>

namespace Hooks {
	template <typename addr, typename detour>
	inline LONG Detour(addr** ppPointer, detour pDetour) {
		return DetourAttach(reinterpret_cast<PVOID*>(ppPointer), reinterpret_cast<PVOID>(pDetour));
	}

	template <typename addr, typename detour>
	inline LONG Detach(addr** ppPointer, detour pDetour) {
		return DetourDetach(reinterpret_cast<PVOID*>(ppPointer), reinterpret_cast<PVOID>(pDetour));
	}

	void initialize();
}
