#include <Windows.h>
#include <Xinput.h>

#include <cstdarg>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cwchar>

extern "C"
{
    volatile DWORD g_ds1kUtf8Length1 = 1;
    volatile DWORD g_ds1kUtf8Length2 = 1;
    volatile DWORD g_ds1kUtf8Codepoint = 0;
    DWORD g_ds1kF1MissingReturn = 0;
    DWORD g_ds1kF1AdvanceReturn = 0;
    DWORD g_ds1kF2SetReturn = 0;
    DWORD g_ds1kF2AdvanceReturn = 0;
}

extern "C" __declspec(naked) void Ds1kDecodeUtf8FromEsi()
{
    __asm
    {
        mov al, byte ptr [esi]
        mov dl, al
        and dl, 0E0h
        cmp dl, 0E0h
        jne decode_two

        movzx edx, byte ptr [esi + 1]
        movzx ecx, byte ptr [esi + 2]
        movzx eax, al
        and eax, 0Fh
        shl eax, 6
        and edx, 3Fh
        or eax, edx
        and ecx, 3Fh
        shl eax, 6
        or eax, ecx
        mov dword ptr [g_ds1kUtf8Length1], 3
        ret

    decode_two:
        mov dl, al
        and dl, 0C0h
        cmp dl, 0C0h
        jne decode_one

        movzx ecx, byte ptr [esi + 1]
        movzx eax, al
        and eax, 1Fh
        and ecx, 3Fh
        shl eax, 6
        or eax, ecx
        mov dword ptr [g_ds1kUtf8Length1], 2
        ret

    decode_one:
        cmp al, 80h
        movzx eax, al
        jb decode_one_done
        mov eax, 20h
    decode_one_done:
        mov dword ptr [g_ds1kUtf8Length1], 1
        ret
    }
}

extern "C" __declspec(naked) void Ds1kDecodeUtf8FromEbp()
{
    __asm
    {
        push eax
        mov al, byte ptr [ebp]
        mov dl, al
        and dl, 0E0h
        cmp dl, 0E0h
        jne decode_two

        movzx edx, byte ptr [ebp + 1]
        movzx ecx, byte ptr [ebp + 2]
        movzx eax, al
        and eax, 0Fh
        shl eax, 6
        and edx, 3Fh
        or eax, edx
        and ecx, 3Fh
        shl eax, 6
        or eax, ecx
        mov dword ptr [g_ds1kUtf8Length2], 3
        mov dword ptr [g_ds1kUtf8Codepoint], eax
        mov ecx, eax
        pop eax
        ret

    decode_two:
        mov dl, al
        and dl, 0C0h
        cmp dl, 0C0h
        jne decode_one

        movzx ecx, byte ptr [ebp + 1]
        movzx eax, al
        and eax, 1Fh
        and ecx, 3Fh
        shl eax, 6
        or eax, ecx
        mov dword ptr [g_ds1kUtf8Length2], 2
        mov dword ptr [g_ds1kUtf8Codepoint], eax
        mov ecx, eax
        pop eax
        ret

    decode_one:
        cmp al, 80h
        movzx eax, al
        jb decode_one_done
        mov eax, 20h
    decode_one_done:
        mov dword ptr [g_ds1kUtf8Length2], 1
        mov dword ptr [g_ds1kUtf8Codepoint], eax
        mov ecx, eax
        pop eax
        ret
    }
}

extern "C" __declspec(naked) void Ds1kF1MissingGlyphHook()
{
    __asm
    {
        mov word ptr [esp + 0Ch], 0
        jmp dword ptr [g_ds1kF1MissingReturn]
    }
}

extern "C" __declspec(naked) void Ds1kF1AdvanceHook()
{
    __asm
    {
        mov ecx, dword ptr [g_ds1kUtf8Length1]
        add dword ptr [ebp], ecx
        mov eax, dword ptr [esp + 34h]
        add dword ptr [eax], ecx
        add esi, ecx
        jmp dword ptr [g_ds1kF1AdvanceReturn]
    }
}

extern "C" __declspec(naked) void Ds1kF2SetCodepointHook()
{
    __asm
    {
        mov dword ptr [g_ds1kUtf8Codepoint], eax
        cmp byte ptr [esp + 17h], bl
        jmp dword ptr [g_ds1kF2SetReturn]
    }
}

extern "C" __declspec(naked) void Ds1kF2AdvanceHook()
{
    __asm
    {
        mov eax, dword ptr [g_ds1kUtf8Length2]
        add ebp, eax
        add dword ptr [esp + 40h], eax
        jmp dword ptr [g_ds1kF2AdvanceReturn]
    }
}

namespace
{
    HMODULE g_self = nullptr;
    HMODULE g_realXInput = nullptr;
    INIT_ONCE g_xinputInit = INIT_ONCE_STATIC_INIT;

    using XInputGetStateFn = DWORD(WINAPI*)(DWORD, XINPUT_STATE*);
    using XInputSetStateFn = DWORD(WINAPI*)(DWORD, XINPUT_VIBRATION*);
    using XInputGetCapabilitiesFn = DWORD(WINAPI*)(DWORD, DWORD, XINPUT_CAPABILITIES*);
    using XInputEnableFn = void(WINAPI*)(BOOL);
    using XInputGetDSoundAudioDeviceGuidsFn = DWORD(WINAPI*)(DWORD, GUID*, GUID*);
    using XInputGetBatteryInformationFn = DWORD(WINAPI*)(DWORD, BYTE, XINPUT_BATTERY_INFORMATION*);
    using XInputGetKeystrokeFn = DWORD(WINAPI*)(DWORD, DWORD, PXINPUT_KEYSTROKE);

    XInputGetStateFn g_getState = nullptr;
    XInputGetStateFn g_getStateEx = nullptr;
    XInputSetStateFn g_setState = nullptr;
    XInputGetCapabilitiesFn g_getCapabilities = nullptr;
    XInputEnableFn g_enable = nullptr;
    XInputGetDSoundAudioDeviceGuidsFn g_getDSoundGuids = nullptr;
    XInputGetBatteryInformationFn g_getBatteryInformation = nullptr;
    XInputGetKeystrokeFn g_getKeystroke = nullptr;

    wchar_t g_runtimeDirectory[MAX_PATH]{};

    BOOL CALLBACK LoadRealXInput(PINIT_ONCE, PVOID, PVOID*)
    {
        wchar_t systemDirectory[MAX_PATH]{};
        const UINT length = GetSystemDirectoryW(systemDirectory, MAX_PATH);
        if (length == 0 || length >= MAX_PATH - 16)
        {
            return TRUE;
        }

        wchar_t path[MAX_PATH]{};
        _snwprintf_s(path, _TRUNCATE, L"%s\\xinput1_3.dll", systemDirectory);
        g_realXInput = LoadLibraryW(path);
        if (g_realXInput == nullptr)
        {
            return TRUE;
        }

        g_getState = reinterpret_cast<XInputGetStateFn>(GetProcAddress(g_realXInput, MAKEINTRESOURCEA(1)));
        g_setState = reinterpret_cast<XInputSetStateFn>(GetProcAddress(g_realXInput, MAKEINTRESOURCEA(2)));
        g_getCapabilities = reinterpret_cast<XInputGetCapabilitiesFn>(GetProcAddress(g_realXInput, MAKEINTRESOURCEA(3)));
        g_enable = reinterpret_cast<XInputEnableFn>(GetProcAddress(g_realXInput, MAKEINTRESOURCEA(4)));
        g_getDSoundGuids = reinterpret_cast<XInputGetDSoundAudioDeviceGuidsFn>(GetProcAddress(g_realXInput, MAKEINTRESOURCEA(5)));
        g_getBatteryInformation = reinterpret_cast<XInputGetBatteryInformationFn>(GetProcAddress(g_realXInput, MAKEINTRESOURCEA(6)));
        g_getKeystroke = reinterpret_cast<XInputGetKeystrokeFn>(GetProcAddress(g_realXInput, MAKEINTRESOURCEA(7)));
        g_getStateEx = reinterpret_cast<XInputGetStateFn>(GetProcAddress(g_realXInput, MAKEINTRESOURCEA(100)));
        return TRUE;
    }

    void EnsureRealXInput()
    {
        InitOnceExecuteOnce(&g_xinputInit, LoadRealXInput, nullptr, nullptr);
    }

    void BuildRuntimeDirectory()
    {
        wchar_t modulePath[MAX_PATH]{};
        if (GetModuleFileNameW(g_self, modulePath, MAX_PATH) == 0)
        {
            return;
        }

        wchar_t* slash = wcsrchr(modulePath, L'\\');
        if (slash == nullptr)
        {
            return;
        }
        *slash = L'\0';

        _snwprintf_s(
            g_runtimeDirectory,
            _TRUNCATE,
            L"%s\\DS1K",
            modulePath);
        CreateDirectoryW(g_runtimeDirectory, nullptr);
    }

    void Log(const char* format, ...)
    {
        if (g_runtimeDirectory[0] == L'\0')
        {
            return;
        }

        wchar_t path[MAX_PATH]{};
        _snwprintf_s(path, _TRUNCATE, L"%s\\DS1K.log", g_runtimeDirectory);
        HANDLE file = CreateFileW(
            path,
            FILE_APPEND_DATA,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            nullptr,
            OPEN_ALWAYS,
            FILE_ATTRIBUTE_NORMAL,
            nullptr);
        if (file == INVALID_HANDLE_VALUE)
        {
            return;
        }

        char buffer[2048]{};
        va_list args;
        va_start(args, format);
        const int count = _vsnprintf_s(buffer, _TRUNCATE, format, args);
        va_end(args);

        if (count > 0)
        {
            DWORD written = 0;
            WriteFile(file, buffer, static_cast<DWORD>(count), &written, nullptr);
        }
        CloseHandle(file);
    }

    bool IsReadableProtection(DWORD protection)
    {
        if ((protection & PAGE_GUARD) != 0 || (protection & PAGE_NOACCESS) != 0)
        {
            return false;
        }
        const DWORD base = protection & 0xFF;
        return base == PAGE_READONLY ||
               base == PAGE_READWRITE ||
               base == PAGE_WRITECOPY ||
               base == PAGE_EXECUTE_READ ||
               base == PAGE_EXECUTE_READWRITE ||
               base == PAGE_EXECUTE_WRITECOPY;
    }

    std::uint8_t* FindPattern(
        std::uint8_t* begin,
        SIZE_T size,
        const std::uint8_t* pattern,
        SIZE_T patternSize)
    {
        if (patternSize == 0 || size < patternSize)
        {
            return nullptr;
        }

        for (SIZE_T offset = 0; offset <= size - patternSize; ++offset)
        {
            if (memcmp(begin + offset, pattern, patternSize) == 0)
            {
                return begin + offset;
            }
        }
        return nullptr;
    }

    bool Matches(const void* address, const std::uint8_t* expected, SIZE_T size)
    {
        return memcmp(address, expected, size) == 0;
    }

    bool WriteBytes(void* address, const void* bytes, SIZE_T size)
    {
        DWORD oldProtection = 0;
        if (VirtualProtect(address, size, PAGE_EXECUTE_READWRITE, &oldProtection) == FALSE)
        {
            return false;
        }

        memcpy(address, bytes, size);
        FlushInstructionCache(GetCurrentProcess(), address, size);

        DWORD ignored = 0;
        if (VirtualProtect(address, size, oldProtection, &ignored) == FALSE)
        {
            return false;
        }
        return true;
    }

    bool WriteRelativeBranch(
        std::uint8_t* address,
        SIZE_T overwriteSize,
        std::uint8_t opcode,
        const void* destination)
    {
        if (overwriteSize < 5 || overwriteSize > 64)
        {
            return false;
        }

        std::uint8_t patch[64];
        memset(patch, 0x90, overwriteSize);
        patch[0] = opcode;
        const auto displacement =
            reinterpret_cast<const std::uint8_t*>(destination) - (address + 5);
        const auto relative = static_cast<std::int32_t>(displacement);
        memcpy(patch + 1, &relative, sizeof(relative));
        return WriteBytes(address, patch, overwriteSize);
    }

    bool ApplyUtf8Patches(std::uint8_t* f1, std::uint8_t* f2)
    {
        const std::uint8_t f1MainExpected[] = {
            0xC6, 0x44, 0x24, 0x0F, 0x00,
            0x8A, 0x1E,
            0x66, 0x0F, 0xB6, 0xD3,
            0x0F, 0xB7, 0xC2,
            0x8B, 0x17,
            0x0F, 0xB7, 0xC0,
        };
        const std::uint8_t f1NoAlternateFontExpected[] = {
            0x0F, 0x84, 0xBB, 0x00, 0x00, 0x00,
        };
        const std::uint8_t f1AlternateLookupMissExpected[] = {
            0x0F, 0x8E, 0x85, 0x00, 0x00, 0x00,
        };
        const std::uint8_t f1KernExpected[] = {
            0x66, 0x0F, 0xB6, 0x4C, 0x24, 0x0F,
            0x66, 0x0F, 0xBE, 0xC3,
        };
        const std::uint8_t f1StoreExpected[] = {0x88, 0x5C, 0x24, 0x0F};
        const std::uint8_t f1MissingExpected[] = {0xC6, 0x44, 0x24, 0x0F, 0x00};
        const std::uint8_t f1AdvanceExpected[] = {
            0x83, 0x45, 0x00, 0x01,
            0x8B, 0x44, 0x24, 0x34,
            0x83, 0x00, 0x01,
            0x83, 0xC6, 0x01,
        };
        const std::uint8_t f2DecodeExpected[] = {
            0x8A, 0x4D, 0x00,
            0x3A, 0xCB,
            0x88, 0x4C, 0x24, 0x1B,
        };
        const std::uint8_t f2SetExpected[] = {
            0x38, 0x5C, 0x24, 0x17,
            0x88, 0x44, 0x24, 0x1B,
        };
        const std::uint8_t f2Read1Expected[] = {
            0x66, 0x0F, 0xB6, 0x4C, 0x24, 0x1B,
            0x0F, 0xB7, 0xC1,
        };
        const std::uint8_t f2Read2Expected[] = {
            0x66, 0x0F, 0xB6, 0x54, 0x24, 0x1B,
            0x8B, 0xB4, 0x24, 0xE0, 0x3A, 0x00, 0x00,
            0x0F, 0xB7, 0xC2,
        };
        const std::uint8_t f2AdvanceExpected[] = {
            0x83, 0xC5, 0x01,
            0x83, 0x44, 0x24, 0x40, 0x01,
        };

        auto* f1InitDisplacement = f1 - 0xAF;
        auto* f1NoAlternateFont = f1 - 0x50;
        auto* f1AlternateLookupMiss = f1 - 0x1A;
        auto* f1PreviousDisplacement = f1 + 0x66;
        auto* f1Main = f1 + 0x6C;
        auto* f1Kern = f1 + 0xBC;
        auto* f1OriginalCall = f1 + 0xC7;
        auto* f1AfterOriginalCall = f1 + 0xCC;
        auto* f1Store = f1 + 0xED;
        auto* f1Missing = f1 + 0xF7;
        auto* f1Advance = f1 + 0x106;

        auto* f2Decode = f2 + 0x70;
        auto* f2Set = f2 + 0x106;
        auto* f2Read1 = f2 + 0x27E;
        auto* f2Read2 = f2 + 0x2A7;
        auto* f2Advance = f2 + 0x5D7;

        if (*f1InitDisplacement != 0x0F ||
            !Matches(
                f1NoAlternateFont,
                f1NoAlternateFontExpected,
                sizeof(f1NoAlternateFontExpected)) ||
            !Matches(
                f1AlternateLookupMiss,
                f1AlternateLookupMissExpected,
                sizeof(f1AlternateLookupMissExpected)) ||
            *f1PreviousDisplacement != 0x0F ||
            !Matches(f1Main, f1MainExpected, sizeof(f1MainExpected)) ||
            !Matches(f1Kern, f1KernExpected, sizeof(f1KernExpected)) ||
            *f1OriginalCall != 0xE8 ||
            !Matches(f1Store, f1StoreExpected, sizeof(f1StoreExpected)) ||
            !Matches(f1Missing, f1MissingExpected, sizeof(f1MissingExpected)) ||
            !Matches(f1Advance, f1AdvanceExpected, sizeof(f1AdvanceExpected)) ||
            !Matches(f2Decode, f2DecodeExpected, sizeof(f2DecodeExpected)) ||
            !Matches(f2Set, f2SetExpected, sizeof(f2SetExpected)) ||
            !Matches(f2Read1, f2Read1Expected, sizeof(f2Read1Expected)) ||
            !Matches(f2Read2, f2Read2Expected, sizeof(f2Read2Expected)) ||
            !Matches(f2Advance, f2AdvanceExpected, sizeof(f2AdvanceExpected)))
        {
            Log("Patch-site validation failed; no code was changed. f1=%p f2=%p\r\n", f1, f2);
            return false;
        }

        std::int32_t oldCallDisplacement = 0;
        memcpy(&oldCallDisplacement, f1OriginalCall + 1, sizeof(oldCallDisplacement));
        auto* kerningFunction = f1OriginalCall + 5 + oldCallDisplacement;

        std::uint8_t f1MainPatch[sizeof(f1MainExpected)] = {
            0x66, 0xC7, 0x44, 0x24, 0x0C, 0x00, 0x00,
            0xE8, 0x00, 0x00, 0x00, 0x00,
            0x66, 0x8B, 0xD8,
            0x8B, 0x17,
            0x90, 0x90,
        };
        const auto decoder1Displacement = static_cast<std::int32_t>(
            reinterpret_cast<std::uint8_t*>(&Ds1kDecodeUtf8FromEsi) - (f1Main + 12));
        memcpy(f1MainPatch + 8, &decoder1Displacement, sizeof(decoder1Displacement));

        const std::uint8_t f1NoAlternateFontPatch[] = {
            0x0F, 0x84, 0xBD, 0x00, 0x00, 0x00,
        };
        const std::uint8_t f1AlternateLookupMissPatch[] = {
            0x0F, 0x8E, 0x87, 0x00, 0x00, 0x00,
        };

        std::uint8_t f1KernPatch[0x35]{};
        const std::uint8_t f1KernPrefix[] = {
            0x66, 0x8B, 0x4C, 0x24, 0x0C,
            0x66, 0x8B, 0xC3,
            0x50,
            0xE8, 0x00, 0x00, 0x00, 0x00,
        };
        memcpy(f1KernPatch, f1KernPrefix, sizeof(f1KernPrefix));
        const auto movedCallDisplacement = static_cast<std::int32_t>(
            kerningFunction - (f1Kern + sizeof(f1KernPrefix)));
        memcpy(f1KernPatch + 10, &movedCallDisplacement, sizeof(movedCallDisplacement));
        memcpy(f1KernPatch + sizeof(f1KernPrefix), f1AfterOriginalCall, 0x21);
        const std::uint8_t wordStore[] = {0x66, 0x89, 0x5C, 0x24, 0x0C, 0x90};
        memcpy(f1KernPatch + sizeof(f1KernPrefix) + 0x21, wordStore, sizeof(wordStore));

        std::uint8_t f2DecodePatch[sizeof(f2DecodeExpected)] = {
            0xE8, 0x00, 0x00, 0x00, 0x00,
            0x83, 0xF9, 0x00,
            0x90,
        };
        const auto decoder2Displacement = static_cast<std::int32_t>(
            reinterpret_cast<std::uint8_t*>(&Ds1kDecodeUtf8FromEbp) - (f2Decode + 5));
        memcpy(f2DecodePatch + 1, &decoder2Displacement, sizeof(decoder2Displacement));

        std::uint8_t f2Read1Patch[sizeof(f2Read1Expected)] = {
            0xA1, 0x00, 0x00, 0x00, 0x00,
            0x90, 0x90, 0x90, 0x90,
        };
        const auto codepointAddress = reinterpret_cast<DWORD>(&g_ds1kUtf8Codepoint);
        memcpy(f2Read1Patch + 1, &codepointAddress, sizeof(codepointAddress));

        std::uint8_t f2Read2Patch[sizeof(f2Read2Expected)] = {
            0xA1, 0x00, 0x00, 0x00, 0x00,
            0x90,
            0x8B, 0xB4, 0x24, 0xE0, 0x3A, 0x00, 0x00,
            0x90, 0x90, 0x90,
        };
        memcpy(f2Read2Patch + 1, &codepointAddress, sizeof(codepointAddress));

        g_ds1kF1MissingReturn = reinterpret_cast<DWORD>(f1Missing + 5);
        g_ds1kF1AdvanceReturn = reinterpret_cast<DWORD>(f1Advance + sizeof(f1AdvanceExpected));
        g_ds1kF2SetReturn = reinterpret_cast<DWORD>(f2Set + sizeof(f2SetExpected));
        g_ds1kF2AdvanceReturn = reinterpret_cast<DWORD>(f2Advance + sizeof(f2AdvanceExpected));

        const std::uint8_t stackWordOffset = 0x0C;
        if (!WriteBytes(f1InitDisplacement, &stackWordOffset, 1) ||
            !WriteBytes(
                f1NoAlternateFont,
                f1NoAlternateFontPatch,
                sizeof(f1NoAlternateFontPatch)) ||
            !WriteBytes(
                f1AlternateLookupMiss,
                f1AlternateLookupMissPatch,
                sizeof(f1AlternateLookupMissPatch)) ||
            !WriteBytes(f1PreviousDisplacement, &stackWordOffset, 1) ||
            !WriteBytes(f1Main, f1MainPatch, sizeof(f1MainPatch)) ||
            !WriteBytes(f1Kern, f1KernPatch, sizeof(f1KernPatch)) ||
            !WriteRelativeBranch(f1Missing, 5, 0xE9, &Ds1kF1MissingGlyphHook) ||
            !WriteRelativeBranch(f1Advance, sizeof(f1AdvanceExpected), 0xE9, &Ds1kF1AdvanceHook) ||
            !WriteBytes(f2Decode, f2DecodePatch, sizeof(f2DecodePatch)) ||
            !WriteRelativeBranch(f2Set, sizeof(f2SetExpected), 0xE9, &Ds1kF2SetCodepointHook) ||
            !WriteBytes(f2Read1, f2Read1Patch, sizeof(f2Read1Patch)) ||
            !WriteBytes(f2Read2, f2Read2Patch, sizeof(f2Read2Patch)) ||
            !WriteRelativeBranch(f2Advance, sizeof(f2AdvanceExpected), 0xE9, &Ds1kF2AdvanceHook))
        {
            Log("A VirtualProtect/write operation failed: %lu\r\n", GetLastError());
            return false;
        }

        Log(
            "UTF-8 hooks installed. f1=%p f2=%p decoder1=%p decoder2=%p\r\n",
            f1,
            f2,
            &Ds1kDecodeUtf8FromEsi,
            &Ds1kDecodeUtf8FromEbp);
        return true;
    }

    DWORD WINAPI PatchThread(void*)
    {
        BuildRuntimeDirectory();
        Log("DS1K UTF-8 proxy loaded. pid=%lu\r\n", GetCurrentProcessId());

        auto* module = reinterpret_cast<std::uint8_t*>(GetModuleHandleW(nullptr));
        if (module == nullptr)
        {
            Log("GetModuleHandleW(NULL) failed: %lu\r\n", GetLastError());
            return 0;
        }

        const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(module);
        const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS32*>(module + dos->e_lfanew);
        const SIZE_T imageSize = nt->OptionalHeader.SizeOfImage;

        const std::uint8_t f1Signature[] = {
            0x0F, 0xB7, 0xC2,
            0x8B, 0x57, 0x04,
            0x0F, 0xB7, 0xC0,
            0x8B, 0xC8,
            0xC1, 0xE9, 0x08,
            0x8B, 0x4C, 0x8A, 0x44,
            0x85, 0xC9,
            0x0F, 0x28, 0xC8,
            0xF3, 0x0F, 0x59, 0x4C, 0x24, 0x24,
        };
        const std::uint8_t f2Signature[] = {
            0x8B, 0xBC, 0x24, 0xFC, 0x3A, 0x00, 0x00,
            0x8A, 0x45, 0x00,
            0x3C, 0x0A,
        };

        for (unsigned attempt = 0; attempt < 600; ++attempt)
        {
            auto* f1 = FindPattern(module, imageSize, f1Signature, sizeof(f1Signature));
            auto* f2 = FindPattern(module, imageSize, f2Signature, sizeof(f2Signature));
            if (f1 != nullptr && f2 != nullptr)
            {
                ApplyUtf8Patches(f1, f2);
                return 0;
            }
            Sleep(50);
        }

        Log("Timed out waiting for the decrypted Steam code image.\r\n");
        return 0;
    }
}

extern "C" DWORD WINAPI XInputGetState(DWORD userIndex, XINPUT_STATE* state) noexcept
{
    EnsureRealXInput();
    return g_getState != nullptr ? g_getState(userIndex, state) : ERROR_DEVICE_NOT_CONNECTED;
}

extern "C" DWORD WINAPI XInputGetStateEx(DWORD userIndex, XINPUT_STATE* state) noexcept
{
    EnsureRealXInput();
    const auto function = g_getStateEx != nullptr ? g_getStateEx : g_getState;
    return function != nullptr ? function(userIndex, state) : ERROR_DEVICE_NOT_CONNECTED;
}

extern "C" DWORD WINAPI XInputSetState(DWORD userIndex, XINPUT_VIBRATION* vibration) noexcept
{
    EnsureRealXInput();
    return g_setState != nullptr ? g_setState(userIndex, vibration) : ERROR_DEVICE_NOT_CONNECTED;
}

extern "C" DWORD WINAPI XInputGetCapabilities(
    DWORD userIndex,
    DWORD flags,
    XINPUT_CAPABILITIES* capabilities) noexcept
{
    EnsureRealXInput();
    return g_getCapabilities != nullptr
        ? g_getCapabilities(userIndex, flags, capabilities)
        : ERROR_DEVICE_NOT_CONNECTED;
}

extern "C" void WINAPI XInputEnable(BOOL enable) noexcept
{
    EnsureRealXInput();
    if (g_enable != nullptr)
    {
        g_enable(enable);
    }
}

extern "C" DWORD WINAPI XInputGetDSoundAudioDeviceGuids(
    DWORD userIndex,
    GUID* renderGuid,
    GUID* captureGuid) noexcept
{
    EnsureRealXInput();
    return g_getDSoundGuids != nullptr
        ? g_getDSoundGuids(userIndex, renderGuid, captureGuid)
        : ERROR_DEVICE_NOT_CONNECTED;
}

extern "C" DWORD WINAPI XInputGetBatteryInformation(
    DWORD userIndex,
    BYTE deviceType,
    XINPUT_BATTERY_INFORMATION* batteryInformation) noexcept
{
    EnsureRealXInput();
    return g_getBatteryInformation != nullptr
        ? g_getBatteryInformation(userIndex, deviceType, batteryInformation)
        : ERROR_DEVICE_NOT_CONNECTED;
}

extern "C" DWORD WINAPI XInputGetKeystroke(
    DWORD userIndex,
    DWORD reserved,
    PXINPUT_KEYSTROKE keystroke) noexcept
{
    EnsureRealXInput();
    return g_getKeystroke != nullptr
        ? g_getKeystroke(userIndex, reserved, keystroke)
        : ERROR_EMPTY;
}

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        g_self = module;
        DisableThreadLibraryCalls(module);
        HANDLE thread = CreateThread(nullptr, 0, PatchThread, nullptr, 0, nullptr);
        if (thread != nullptr)
        {
            CloseHandle(thread);
        }
    }
    return TRUE;
}
