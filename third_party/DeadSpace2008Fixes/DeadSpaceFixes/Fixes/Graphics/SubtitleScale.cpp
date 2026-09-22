#include "common.h"
#include "Utils.h"

// The full subtitle layout/draw pipeline and render-height signature are
// adapted from DSOpt by Luminous, used under the MIT License. See
// third_party/licenses/DSOpt-MIT.txt.

namespace Fixes {

	namespace Graphics {

		namespace SubtitleScale {

			namespace {

				constexpr uint16_t kBaseRenderHeight = 720;
				constexpr uint16_t kMinimumValidHeight = 240;
				constexpr uint16_t kMaximumValidHeight = 10000;
				constexpr DWORD kRetryIntervalMs = 250;
				constexpr int kMaximumInstallAttempts = 240;

				alignas(4) volatile LONG gSubtitleScaleBits = 0x3F800000; // 1.0f
				alignas(4) float gBaseRenderHeightFloat = 720.0f;
				alignas(4) float gMinimumSubtitleScale = 1.0f;
				volatile uint16_t* gRenderHeight = nullptr;
				uintptr_t gLayoutHookReturn = 0;
				uintptr_t gDrawHookReturn = 0;
				volatile LONG gInstalled = 0;

				uintptr_t ModuleEnd(HMODULE module)
				{
					auto* base = reinterpret_cast<uint8_t*>(module);
					auto* dosHeader = reinterpret_cast<PIMAGE_DOS_HEADER>(base);
					auto* ntHeaders = reinterpret_cast<PIMAGE_NT_HEADERS>(base + dosHeader->e_lfanew);
					return reinterpret_cast<uintptr_t>(base) + ntHeaders->OptionalHeader.SizeOfImage;
				}

				uintptr_t FindUniquePattern(HMODULE module, const char* signature)
				{
					const uintptr_t first = Utils::FindPattern(module, signature);
					if (!first)
						return 0;

					const uintptr_t second = Utils::FindPattern(module, signature, first + 1, ModuleEnd(module));
					return second ? 0 : first;
				}

				bool IsReadableAddress(const void* address, size_t size)
				{
					MEMORY_BASIC_INFORMATION memoryInfo{};
					if (!address || VirtualQuery(address, &memoryInfo, sizeof(memoryInfo)) != sizeof(memoryInfo))
						return false;

					if (memoryInfo.State != MEM_COMMIT ||
						(memoryInfo.Protect & (PAGE_NOACCESS | PAGE_GUARD)) != 0)
						return false;

					const uintptr_t start = reinterpret_cast<uintptr_t>(address);
					const uintptr_t regionEnd = reinterpret_cast<uintptr_t>(memoryInfo.BaseAddress) + memoryInfo.RegionSize;
					return start <= regionEnd && size <= regionEnd - start;
				}

				void StoreSubtitleScale(float scale)
				{
					LONG bits = 0;
					static_assert(sizeof(bits) == sizeof(scale));
					std::memcpy(&bits, &scale, sizeof(bits));
					InterlockedExchange(&gSubtitleScaleBits, bits);
				}

				// The pre-layout stage controls line measurement, wrapping and capacity.
				// Refreshing the scale here also keeps layout and drawing synchronized
				// immediately after an in-game resolution change.
				__declspec(naked) void hkSubtitleLayout()
				{
					__asm
					{
						pushfd
						push eax

						mov eax, dword ptr[gRenderHeight]
						test eax, eax
						jz scale_ready
						movzx eax, word ptr[eax]
						cmp eax, 240
						jb scale_ready
						cmp eax, 10000
						ja scale_ready
						cvtsi2ss xmm0, eax
						divss xmm0, dword ptr[gBaseRenderHeightFloat]
						maxss xmm0, dword ptr[gMinimumSubtitleScale]
						movss dword ptr[gSubtitleScaleBits], xmm0

						scale_ready:
						pop eax
						popfd

						movss xmm0, dword ptr[esi + 0x18]
						mulss xmm0, dword ptr[gSubtitleScaleBits]
						jmp dword ptr[gLayoutHookReturn]
					}
				}

				// The final drawing stage uses the same scale for line spacing and glyphs.
				__declspec(naked) void hkSubtitleDraw()
				{
					__asm
					{
						fld dword ptr[edi + 0x18]
						fmul dword ptr[gSubtitleScaleBits]
						movss xmm0, dword ptr[esi + 0x34]
						push 0
						fstp dword ptr[esi + 0x34]
						movzx edx, byte ptr[edi + 0x29]
						fld dword ptr[edi + 0x18]
						fmul dword ptr[gSubtitleScaleBits]
						jmp dword ptr[gDrawHookReturn]
					}
				}

				bool TryInstallHooks(HMODULE hExe)
				{
					if (InterlockedCompareExchange(&gInstalled, 0, 0) != 0)
						return true;

					// Reads the game's real render height. Unlike GetSystemMetrics or
					// GetClientRect, this value is not virtualized by Windows DPI scaling.
					const char* renderResolutionSignature =
						"0F B7 05 ? ? ? ? F3 0F 10 05 ? ? ? ? F3 0F 2A C8 8B 44 24 04 "
						"0F 28 D0 F3 0F 5E D1 F3 0F 11 11 0F B7 15 ? ? ? ? F3 0F 2A CA "
						"F3 0F 5E C1 F3 0F 11 00 C3";
					const char* layoutSignature =
						"8B 74 24 30 F3 0F 10 46 18 57 8B F8 8B 46 10";
					const char* drawSignature =
						"D9 47 18 F3 0F 10 46 34 6A 00 D9 5E 34 0F B6 57 29 D9 47 18 8B 47 38";

					const uintptr_t resolutionAddress = FindUniquePattern(hExe, renderResolutionSignature);
					const uintptr_t layoutAddress = FindUniquePattern(hExe, layoutSignature);
					const uintptr_t drawAddress = FindUniquePattern(hExe, drawSignature);
					if (!resolutionAddress || !layoutAddress || !drawAddress)
						return false;

					uint32_t renderHeightAddress = 0;
					std::memcpy(&renderHeightAddress,
						reinterpret_cast<const void*>(resolutionAddress + 37),
						sizeof(renderHeightAddress));
					auto* renderHeight = reinterpret_cast<volatile uint16_t*>(
						static_cast<uintptr_t>(renderHeightAddress));
					if (!IsReadableAddress(const_cast<const uint16_t*>(renderHeight), sizeof(uint16_t)))
						return false;

					const uint16_t initialHeight = *renderHeight;
					if (initialHeight < kMinimumValidHeight || initialHeight > kMaximumValidHeight)
						return false;

					void* layoutHookSite = reinterpret_cast<void*>(layoutAddress + 4);
					void* drawHookSite = reinterpret_cast<void*>(drawAddress);
					gRenderHeight = renderHeight;
					gLayoutHookReturn = layoutAddress + 9;
					gDrawHookReturn = drawAddress + 20;
					float initialScale = static_cast<float>(initialHeight) /
						static_cast<float>(kBaseRenderHeight);
					if (initialScale < 1.0f)
						initialScale = 1.0f;
					StoreSubtitleScale(initialScale);

					MH_STATUS status = MH_CreateHook(layoutHookSite, &hkSubtitleLayout, nullptr);
					if (status != MH_OK)
						return false;

					status = MH_CreateHook(drawHookSite, &hkSubtitleDraw, nullptr);
					if (status != MH_OK)
					{
						MH_RemoveHook(layoutHookSite);
						return false;
					}

					const MH_STATUS layoutQueueStatus = MH_QueueEnableHook(layoutHookSite);
					const MH_STATUS drawQueueStatus = MH_QueueEnableHook(drawHookSite);
					status = (layoutQueueStatus == MH_OK && drawQueueStatus == MH_OK)
						? MH_ApplyQueued()
						: MH_UNKNOWN;
					if (status != MH_OK)
					{
						MH_DisableHook(layoutHookSite);
						MH_DisableHook(drawHookSite);
						MH_RemoveHook(layoutHookSite);
						MH_RemoveHook(drawHookSite);
						return false;
					}

					InterlockedExchange(&gInstalled, 1);
					LOG_INFO("[Fixes/Graphics/SubtitleScale]",
						"Installed full subtitle pipeline (height=%u, layout=0x%X, draw=0x%X)",
						initialHeight, layoutAddress + 4, drawAddress);
					return true;
				}

				DWORD WINAPI InstallRetryThread(LPVOID parameter)
				{
					HMODULE hExe = static_cast<HMODULE>(parameter);
					for (int attempt = 0; attempt < kMaximumInstallAttempts; ++attempt)
					{
						// Let the main module installer finish before touching MinHook from
						// this fallback thread.
						Sleep(kRetryIntervalMs);
						if (TryInstallHooks(hExe))
							return 0;
					}

					LOG_WARN("[Fixes/Graphics/SubtitleScale]",
						"Compatible subtitle pipeline signatures were not found");
					return 0;
				}

			}

			void Apply(HMODULE hExe)
			{
				if (TryInstallHooks(hExe))
					return;

				HANDLE thread = CreateThread(nullptr, 0, InstallRetryThread, hExe, 0, nullptr);
				if (thread)
					CloseHandle(thread);
				else
					LOG_WARN("[Fixes/Graphics/SubtitleScale]", "Could not start hook retry thread");
			}
		}
	}
}
