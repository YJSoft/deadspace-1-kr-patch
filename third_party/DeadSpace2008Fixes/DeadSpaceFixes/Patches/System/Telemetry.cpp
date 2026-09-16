#include "common.h"
#include "Utils.h"

#include <intrin.h>

#pragma intrinsic(_ReturnAddress)

namespace Patches {

	namespace System {

		namespace Telemetry {

			//Disables the game's network/telemetry attempts so it stays fully offline
			//and starts a bit faster.

			WSAStartup_t oWSAStartup = nullptr;
			Netbios_t oNetbios = nullptr;
			HMODULE gameModule = nullptr;

			// Steam and overlays share the game process. Hooking WSAStartup globally
			// and returning an error to every caller also breaks Steam's vstdlib_s
			// networking thread, which responds with an unhandled breakpoint. Only
			// suppress calls made directly by Dead Space.exe; forward calls from
			// injected/runtime DLLs to the original Windows implementation.
			bool IsGameCaller(void* returnAddress)
			{
				HMODULE callerModule = nullptr;
				if (!GetModuleHandleExA(
					GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
					GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
					reinterpret_cast<LPCSTR>(returnAddress),
					&callerModule))
				{
					return false;
				}
				return callerModule == gameModule;
			}

			//returns WSASYSNOTREADY (10091) so the game thinks the network is unavailable
			int WINAPI hkWSAStartup(WORD wVersionRequested, LPWSADATA lpWSAData)
			{
				if (IsGameCaller(_ReturnAddress()))
					return 10091;
				return oWSAStartup != nullptr
					? oWSAStartup(wVersionRequested, lpWSAData)
					: 10091;
			}

			//returns NRC_SYSTEM (0x40) so it can't scan network devices
			UCHAR WINAPI hkNetbios(PNCB pncb)
			{
				if (IsGameCaller(_ReturnAddress()))
					return 0x40;
				return oNetbios != nullptr ? oNetbios(pncb) : 0x40;
			}

			void Apply()
			{
				gameModule = GetModuleHandleA(nullptr);
				HMODULE hWinSock = GetModuleHandleA("ws2_32.dll");
				//GetModuleHandleA can fail, guard against the NULL deref before passing to GetProcAddress
				if (hWinSock != nullptr)
				{
					FARPROC pWSAStartup = GetProcAddress(hWinSock, "WSAStartup");
					if (pWSAStartup)
					{
						MH_CreateHook(pWSAStartup, &hkWSAStartup, reinterpret_cast<LPVOID*>(&oWSAStartup));
						MH_EnableHook(pWSAStartup);
						LOG_INFO("[Patches/System/Telemetry]", "WSAStartup hooked, all network/telemetry blocked");
					}
				}
				//some games don't properly load this so we LoadLibrary it
				HMODULE hNetApi = LoadLibraryA("netapi32.dll");
				if (hNetApi != nullptr) //LoadLibraryA can also fail, same guard
				{
					FARPROC pNetbios = GetProcAddress(hNetApi, "Netbios");
					if (pNetbios)
					{
						MH_CreateHook(pNetbios, &hkNetbios, reinterpret_cast<LPVOID*>(&oNetbios));
						MH_EnableHook(pNetbios);
						LOG_INFO("[Patches/System/Telemetry]", "Netbios also hooked, weird NAT harvester is now blocked");
					}
				}
			}
		}
	}
}
