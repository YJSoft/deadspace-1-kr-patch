#include "common.h"
#include "Utils.h"

namespace Patches {

	namespace UI {

		namespace VersionString {

			//Shows a custom version string on the main menu footer instead of the game's version number.
			void Apply(HMODULE hExe)
			{
				const char* versionSignature = "68 ? ? ? ? 6A 64 68 ? ? ? ? E8 ? ? ? ? 83 C4 1C";
				uintptr_t versionAddress = Utils::FindPattern(hExe, versionSignature);
				if (versionAddress != 0)
				{
					// Upstream c662b94: replace the format pointer rather than
					// overwriting the game's short, shared version buffer.
					char** ppFormatString = reinterpret_cast<char**>(versionAddress + 1);

					static const char customVersion[] = "Dead Space KR 0.4.0\n번역 검수용 버전";

					DWORD oldProtect;
					if (VirtualProtect(ppFormatString, sizeof(char*), PAGE_EXECUTE_READWRITE, &oldProtect))
					{
						*ppFormatString = const_cast<char*>(customVersion);
						VirtualProtect(ppFormatString, sizeof(char*), oldProtect, &oldProtect);
						LOG_INFO("[Patches/UI/VersionString]", "Set custom game version string to %s", customVersion);
					}
				}
			}
		}
	}
}
