#include "common.h"

namespace Patches {

	namespace System {

		namespace BorderlessWindow {

			//Makes the game render in a borderless window covering the whole screen,
			//which fixes gamma issues and alt-tabbing bugs when running windowed.

			CreateWindowExA_t oCreateWindowExA = nullptr;
			AdjustWindowRect_t oAdjustWindowRect = nullptr;
			AdjustWindowRectEx_t oAdjustWindowRectEx = nullptr;
			HWND g_GameWindow = nullptr;
			WNDPROC g_OriginalGameWndProc = nullptr;

			namespace {

				void ReleaseCursorLock()
				{
					ClipCursor(nullptr);
				}

				void ApplyCursorLock(HWND hWnd)
				{
					if (!hWnd || GetForegroundWindow() != hWnd)
						return;

					RECT clientRect = {};
					if (!GetClientRect(hWnd, &clientRect))
						return;

					POINT topLeft = { clientRect.left, clientRect.top };
					POINT bottomRight = { clientRect.right, clientRect.bottom };
					if (!ClientToScreen(hWnd, &topLeft) || !ClientToScreen(hWnd, &bottomRight))
						return;

					RECT screenRect = {
						topLeft.x,
						topLeft.y,
						bottomRight.x,
						bottomRight.y
					};
					ClipCursor(&screenRect);
					SetCursor(nullptr);
				}

				LRESULT CALLBACK GameWindowProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam)
				{
					switch (message)
					{
					case WM_ACTIVATEAPP:
						if (wParam)
							ApplyCursorLock(hWnd);
						else
							ReleaseCursorLock();
						break;

					case WM_ACTIVATE:
						if (LOWORD(wParam) != WA_INACTIVE)
							ApplyCursorLock(hWnd);
						else
							ReleaseCursorLock();
						break;

					case WM_SETFOCUS:
						ApplyCursorLock(hWnd);
						break;

					case WM_KILLFOCUS:
						ReleaseCursorLock();
						break;

					case WM_MOVE:
					case WM_SIZE:
					case WM_WINDOWPOSCHANGED:
						ApplyCursorLock(hWnd);
						break;

					case WM_SETCURSOR:
						if (GetForegroundWindow() == hWnd && LOWORD(lParam) == HTCLIENT)
						{
							SetCursor(nullptr);
							return TRUE;
						}
						break;

					case WM_DESTROY:
						ReleaseCursorLock();
						break;
					}

					return CallWindowProcA(g_OriginalGameWndProc, hWnd, message, wParam, lParam);
				}
			}

			HWND WINAPI hkCreateWindowExA(DWORD dwExStyle, LPCSTR lpClassName, LPCSTR lpWindowName, DWORD dwStyle, int X, int Y, int nWidth, int nHeight, HWND hWndParent, HMENU hMenu, HINSTANCE hInstance, LPVOID lpParam)
			{
				if (lpClassName && strcmp(lpClassName, "DeadSpaceWndClass") == 0)
				{
					//strip standard borders
					dwStyle &= ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZE | WS_MAXIMIZE | WS_SYSMENU);
					dwStyle |= WS_POPUP;

					//strip extended borders
					dwExStyle &= ~(WS_EX_DLGMODALFRAME | WS_EX_CLIENTEDGE | WS_EX_STATICEDGE);

					X = 0; Y = 0;
					nWidth = GetSystemMetrics(SM_CXSCREEN); nHeight = GetSystemMetrics(SM_CYSCREEN);
				}
				HWND hWnd = oCreateWindowExA(dwExStyle, lpClassName, lpWindowName, dwStyle, X, Y, nWidth, nHeight, hWndParent, hMenu, hInstance, lpParam);
				if (hWnd && lpClassName && strcmp(lpClassName, "DeadSpaceWndClass") == 0 && !g_GameWindow)
				{
					WNDPROC originalWndProc = reinterpret_cast<WNDPROC>(
						SetWindowLongPtrA(hWnd, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(&GameWindowProc)));
					if (originalWndProc)
					{
						g_GameWindow = hWnd;
						g_OriginalGameWndProc = originalWndProc;
						ApplyCursorLock(hWnd);
					}
				}
				return hWnd;
			}

			//these 2 are also needed for true borderless as the game resizes the window after startup
			BOOL WINAPI hkAdjustWindowRect(LPRECT lpRect, DWORD dwStyle, BOOL bMenu)
			{
				dwStyle &= ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZE | WS_MAXIMIZE | WS_SYSMENU);
				return oAdjustWindowRect(lpRect, dwStyle, bMenu);
			}

			BOOL WINAPI hkAdjustWindowRectEx(LPRECT lpRect, DWORD dwStyle, BOOL bMenu, DWORD dwExStyle)
			{
				//strips standard & extended borders
				dwStyle &= ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZE | WS_MAXIMIZE | WS_SYSMENU);
				dwExStyle &= ~(WS_EX_DLGMODALFRAME | WS_EX_CLIENTEDGE | WS_EX_STATICEDGE);

				return oAdjustWindowRectEx(lpRect, dwStyle, bMenu, dwExStyle);
			}

			void Apply()
			{
				HMODULE hUser32 = GetModuleHandleA("user32.dll");
				LPVOID pCreateWindowExA = GetProcAddress(hUser32, "CreateWindowExA");
				LPVOID pAdjustWindowRect = GetProcAddress(hUser32, "AdjustWindowRect");
				LPVOID pAdjustWindowRectEx = GetProcAddress(hUser32, "AdjustWindowRectEx");

				MH_CreateHook(pCreateWindowExA, &hkCreateWindowExA, reinterpret_cast<LPVOID*>(&oCreateWindowExA));
				MH_CreateHook(pAdjustWindowRect, &hkAdjustWindowRect, reinterpret_cast<LPVOID*>(&oAdjustWindowRect));
				MH_CreateHook(pAdjustWindowRectEx, &hkAdjustWindowRectEx, reinterpret_cast<LPVOID*>(&oAdjustWindowRectEx));

				MH_EnableHook(pCreateWindowExA);
				MH_EnableHook(pAdjustWindowRect);
				MH_EnableHook(pAdjustWindowRectEx);
			}
		}
	}
}
