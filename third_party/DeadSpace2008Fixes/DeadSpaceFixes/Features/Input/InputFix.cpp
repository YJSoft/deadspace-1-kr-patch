#include "InputFix.h"
#include "Config.h"
#include "Utils.h"
#include "logging.hpp"
#include "mouse_hook.hpp"

// Rama2120's MIT input implementation is linked into the existing proxy.
// The game signatures can become available late on packed EA builds.
namespace Features::Input::CompleteInputFix {
    namespace {
        DWORD WINAPI InstallMouseCamera(LPVOID) {
            MouseConfig config;
            for (int attempt = 0; attempt < 240; ++attempt) {
                if (MouseHook::Install(config)) {
                    LOG_INFO("[Input/CompleteInputFix]", "Raw mouse camera hooks installed");
                    return 0;
                }
                Sleep(250);
            }
            LOG_WARN("[Input/CompleteInputFix]", "Mouse signatures not found; keeping original camera input");
            return 0;
        }
    }

    void StartMouseCameraFix(HMODULE module) {
        if (!Config::Fixes::RawMouseCamera)
            return;
        Logging::Initialise(module);
        HANDLE thread = CreateThread(nullptr, 0, InstallMouseCamera, nullptr, 0, nullptr);
        if (thread)
            CloseHandle(thread);
        else
            LOG_WARN("[Input/CompleteInputFix]", "Could not start mouse hook installer");
    }
}
