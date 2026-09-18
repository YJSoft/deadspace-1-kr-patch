#include "common.h"
#include "Utils.h"

#include <atomic>

//Native PS4/5 & Switch controller support via SDL3.
//
//This DLL is a proxy for the real xinput1_3.dll (see proxy.def), so the
//XInputGetState/SetState/GetCapabilities functions below are exported and called
//by the game. When a gamepad managed by SDL is connected we serve the input from
//SDL; otherwise we forward to the real XInput DLL loaded from the system folder.

namespace {

	//Forwarding targets into the real xinput1_3.dll
	XInputGetState_t oXInputGetState = nullptr;
	XInputSetState_t oXInputSetState = nullptr;
	XInputGetCapabilities_t oXInputGetCapabilities = nullptr;

	SDL_Gamepad* g_CurrentGamepad = nullptr;
	SDL_JoystickID g_CurrentGamepadId = 0;
	SRWLOCK g_GamepadLock = SRWLOCK_INIT;
	std::atomic_bool g_StopRequested = false;

	bool OpenGamepadLocked(SDL_JoystickID instanceId)
	{
		if (g_CurrentGamepad != nullptr)
			return true;

		SDL_Gamepad* gamepad = SDL_OpenGamepad(instanceId);
		if (gamepad == nullptr)
		{
			LOG_WARN("[Features/Input/SdlGamepad]", "Failed to open controller %u: %s",
				static_cast<unsigned>(instanceId), SDL_GetError());
			return false;
		}

		g_CurrentGamepad = gamepad;
		g_CurrentGamepadId = instanceId;
		const char* name = SDL_GetGamepadName(gamepad);
		LOG_INFO("[Features/Input/SdlGamepad]", "Controller connected: %s", name ? name : "Unknown");
		SDL_SetGamepadLED(gamepad, 0, 255, 255);
		return true;
	}

	void OpenFirstAvailableGamepadLocked()
	{
		int count = 0;
		SDL_JoystickID* gamepads = SDL_GetGamepads(&count);
		if (gamepads == nullptr)
			return;

		for (int index = 0; index < count && g_CurrentGamepad == nullptr; ++index)
			OpenGamepadLocked(gamepads[index]);

		SDL_free(gamepads);
	}

	DWORD WINAPI SDLDeviceThread(LPVOID)
	{
		if (!SDL_Init(SDL_INIT_GAMEPAD))
		{
			LOG_ERROR("[Features/Input/SdlGamepad]", "SDL failed to init: %s", SDL_GetError());
			return 1;
		}

		AcquireSRWLockExclusive(&g_GamepadLock);
		OpenFirstAvailableGamepadLocked();
		ReleaseSRWLockExclusive(&g_GamepadLock);

		SDL_Event event{};

		//A timeout only means the queue was idle. Keep the watcher alive so
		//disconnect/reconnect and devices enabled after startup are still seen.
		while (!g_StopRequested.load(std::memory_order_acquire))
		{
			if (!SDL_WaitEventTimeout(&event, 50))
				continue;

			if (event.type == SDL_EVENT_GAMEPAD_ADDED) //controller plugged in
			{
				AcquireSRWLockExclusive(&g_GamepadLock);
				OpenGamepadLocked(event.gdevice.which);
				ReleaseSRWLockExclusive(&g_GamepadLock);
			}
			else if (event.type == SDL_EVENT_GAMEPAD_REMOVED) //controller removed
			{
				AcquireSRWLockExclusive(&g_GamepadLock);
				if (g_CurrentGamepad != nullptr && g_CurrentGamepadId == event.gdevice.which)
				{
					LOG_INFO("[Features/Input/SdlGamepad]", "Controller disconnected");
					SDL_CloseGamepad(g_CurrentGamepad);
					g_CurrentGamepad = nullptr;
					g_CurrentGamepadId = 0;
					OpenFirstAvailableGamepadLocked();
				}
				ReleaseSRWLockExclusive(&g_GamepadLock);
			}
		}

		AcquireSRWLockExclusive(&g_GamepadLock);
		if (g_CurrentGamepad != nullptr)
		{
			SDL_CloseGamepad(g_CurrentGamepad);
			g_CurrentGamepad = nullptr;
			g_CurrentGamepadId = 0;
		}
		ReleaseSRWLockExclusive(&g_GamepadLock);
		SDL_QuitSubSystem(SDL_INIT_GAMEPAD);
		return 0;
	}

}

namespace Features {

	namespace Input {

		namespace SdlGamepad {

			void StartThread()
			{
				//Load the real XInput DLL so unhandled calls can be forwarded to it.
				char syspath[MAX_PATH];
				GetSystemDirectoryA(syspath, MAX_PATH);
				strcat_s(syspath, "\\xinput1_3.dll");

				HMODULE hRealXInput = LoadLibraryA(syspath);
				if (hRealXInput)
				{
					oXInputGetState = (XInputGetState_t)GetProcAddress(hRealXInput, "XInputGetState");
					oXInputSetState = (XInputSetState_t)GetProcAddress(hRealXInput, "XInputSetState");
					oXInputGetCapabilities = (XInputGetCapabilities_t)GetProcAddress(hRealXInput, "XInputGetCapabilities");
				}

				g_StopRequested.store(false, std::memory_order_release);
				HANDLE deviceThread = CreateThread(nullptr, 0, SDLDeviceThread, nullptr, 0, nullptr);
				if (deviceThread != nullptr)
					CloseHandle(deviceThread);
				else
					LOG_ERROR("[Features/Input/SdlGamepad]", "Failed to start SDL controller watcher: %lu", GetLastError());
			}

			void Shutdown()
			{
				//DllMain calls this during process teardown. Do not wait while the
				//loader lock is held; the watcher wakes within 50 ms and cleans up.
				g_StopRequested.store(true, std::memory_order_release);
			}
		}
	}
}

extern "C" DWORD WINAPI XInputGetState(DWORD dwUserIndex, XINPUT_STATE* pState)
{
	if (dwUserIndex == 0)
	{
		AcquireSRWLockShared(&g_GamepadLock);
		if (g_CurrentGamepad == nullptr || !SDL_GamepadConnected(g_CurrentGamepad))
		{
			ReleaseSRWLockShared(&g_GamepadLock);
			if (oXInputGetState) return oXInputGetState(dwUserIndex, pState);
			return ERROR_DEVICE_NOT_CONNECTED;
		}

		memset(pState, 0, sizeof(XINPUT_STATE)); //clear the games struct so we start fresh

		static DWORD s_PacketNumber = 0;
		pState->dwPacketNumber = s_PacketNumber++;

		//map the buttons
		// SDL's south/east/west/north convention maps to cross/circle/square/triangle.
		static constexpr struct { SDL_GamepadButton sdl; WORD xinput; } kButtonMap[] = {
			{ SDL_GAMEPAD_BUTTON_SOUTH,         XINPUT_GAMEPAD_A },
			{ SDL_GAMEPAD_BUTTON_EAST,          XINPUT_GAMEPAD_B },
			{ SDL_GAMEPAD_BUTTON_WEST,          XINPUT_GAMEPAD_X },
			{ SDL_GAMEPAD_BUTTON_NORTH,         XINPUT_GAMEPAD_Y },
			{ SDL_GAMEPAD_BUTTON_DPAD_UP,       XINPUT_GAMEPAD_DPAD_UP },
			{ SDL_GAMEPAD_BUTTON_DPAD_DOWN,     XINPUT_GAMEPAD_DPAD_DOWN },
			{ SDL_GAMEPAD_BUTTON_DPAD_LEFT,     XINPUT_GAMEPAD_DPAD_LEFT },
			{ SDL_GAMEPAD_BUTTON_DPAD_RIGHT,    XINPUT_GAMEPAD_DPAD_RIGHT },
			{ SDL_GAMEPAD_BUTTON_LEFT_SHOULDER,  XINPUT_GAMEPAD_LEFT_SHOULDER },  //L1
			{ SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER, XINPUT_GAMEPAD_RIGHT_SHOULDER },  //R1
			{ SDL_GAMEPAD_BUTTON_START,          XINPUT_GAMEPAD_START },  //options/plus
			{ SDL_GAMEPAD_BUTTON_LEFT_STICK,    XINPUT_GAMEPAD_LEFT_THUMB },  //L3
			{ SDL_GAMEPAD_BUTTON_RIGHT_STICK,   XINPUT_GAMEPAD_RIGHT_THUMB },  //R3
		};
		WORD buttons = 0;
		for (const auto& b : kButtonMap)
			if (SDL_GetGamepadButton(g_CurrentGamepad, b.sdl))
				buttons |= b.xinput;

		pState->Gamepad.wButtons = buttons;

		//map the triggers
		int16_t leftTriggerSDL = SDL_GetGamepadAxis(g_CurrentGamepad, SDL_GAMEPAD_AXIS_LEFT_TRIGGER);
		int16_t rightTriggerSDL = SDL_GetGamepadAxis(g_CurrentGamepad, SDL_GAMEPAD_AXIS_RIGHT_TRIGGER);

		pState->Gamepad.bLeftTrigger = (BYTE)((leftTriggerSDL / 32767.0f) * 255.0f);
		pState->Gamepad.bRightTrigger = (BYTE)((rightTriggerSDL / 32767.0f) * 255.0f);

		//map the joysticks
		pState->Gamepad.sThumbLX = SDL_GetGamepadAxis(g_CurrentGamepad, SDL_GAMEPAD_AXIS_LEFTX);
		pState->Gamepad.sThumbRX = SDL_GetGamepadAxis(g_CurrentGamepad, SDL_GAMEPAD_AXIS_RIGHTX);

		int16_t sdlLeftY = SDL_GetGamepadAxis(g_CurrentGamepad, SDL_GAMEPAD_AXIS_LEFTY); //we need to fetch the raw y values or there cooked
		int16_t sdlRightY = SDL_GetGamepadAxis(g_CurrentGamepad, SDL_GAMEPAD_AXIS_RIGHTY);

		pState->Gamepad.sThumbLY = (sdlLeftY == -32768) ? 32767 : -sdlLeftY; //then  we safely invert the y values here
		pState->Gamepad.sThumbRY = (sdlRightY == -32768) ? 32767 : -sdlRightY;

		ReleaseSRWLockShared(&g_GamepadLock);
		return ERROR_SUCCESS;
	}
	if (oXInputGetState) return oXInputGetState(dwUserIndex, pState);
	return ERROR_DEVICE_NOT_CONNECTED;
}

extern "C" DWORD WINAPI XInputSetState(DWORD dwUserIndex, XINPUT_VIBRATION* pVibration)
{
	if (dwUserIndex == 0)
	{
		AcquireSRWLockShared(&g_GamepadLock);
		if (g_CurrentGamepad == nullptr || !SDL_GamepadConnected(g_CurrentGamepad))
		{
			ReleaseSRWLockShared(&g_GamepadLock);
			if (oXInputSetState) return oXInputSetState(dwUserIndex, pVibration);
			return ERROR_DEVICE_NOT_CONNECTED;
		}

		Uint16 lowFreq = pVibration->wLeftMotorSpeed; //heavy rumble
		Uint16 highFreq = pVibration->wRightMotorSpeed; //light rumble

		SDL_RumbleGamepad(g_CurrentGamepad, lowFreq, highFreq, 5000); //send the rumble to the controller for 5 seconds, the game should stop it early

		ReleaseSRWLockShared(&g_GamepadLock);
		return ERROR_SUCCESS;
	}
	if (oXInputSetState) return oXInputSetState(dwUserIndex, pVibration);
	return ERROR_DEVICE_NOT_CONNECTED;
}

extern "C" DWORD WINAPI XInputGetCapabilities(DWORD dwUserIndex, DWORD dwFlags, XINPUT_CAPABILITIES* pCapabilities) //maybe rewrite soon? Don't think this is great
{
	if (dwUserIndex == 0)
	{
		AcquireSRWLockShared(&g_GamepadLock);
		if (g_CurrentGamepad == nullptr || !SDL_GamepadConnected(g_CurrentGamepad))
		{
			ReleaseSRWLockShared(&g_GamepadLock);
			if (oXInputGetCapabilities) return oXInputGetCapabilities(dwUserIndex, dwFlags, pCapabilities);
			return ERROR_DEVICE_NOT_CONNECTED;
		}

		memset(pCapabilities, 0, sizeof(XINPUT_CAPABILITIES));

		pCapabilities->Type = XINPUT_DEVTYPE_GAMEPAD;
		pCapabilities->SubType = XINPUT_DEVSUBTYPE_GAMEPAD;
		pCapabilities->Flags = 0;

		pCapabilities->Gamepad.wButtons = 0xFFFF;
		pCapabilities->Gamepad.bLeftTrigger = 255;
		pCapabilities->Gamepad.bRightTrigger = 255;
		pCapabilities->Gamepad.sThumbLX = 32767;
		pCapabilities->Gamepad.sThumbLY = 32767;
		pCapabilities->Gamepad.sThumbRX = 32767;
		pCapabilities->Gamepad.sThumbRY = 32767;

		pCapabilities->Vibration.wLeftMotorSpeed = 65535;
		pCapabilities->Vibration.wRightMotorSpeed = 65535;

		ReleaseSRWLockShared(&g_GamepadLock);
		return ERROR_SUCCESS;
	}
	if (oXInputGetCapabilities) return oXInputGetCapabilities(dwUserIndex, dwFlags, pCapabilities);
	return ERROR_DEVICE_NOT_CONNECTED;
}
