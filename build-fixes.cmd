@echo off
setlocal

call "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" -arch=x86 -host_arch=x64
if errorlevel 1 exit /b %errorlevel%

set "UPSTREAM=%~dp0third_party\DeadSpace2008Fixes\DeadSpaceFixes"
set "BUILD_ROOT=%TEMP%\ds1k-fixes-build"
if not exist "%BUILD_ROOT%" mkdir "%BUILD_ROOT%"
if not exist "%BUILD_ROOT%\obj" mkdir "%BUILD_ROOT%\obj"
if not exist "%~dp0dist" mkdir "%~dp0dist"

cl.exe /nologo /LD /MT /O2 /Oi /GS /Gy /EHsc /std:c++20 /permissive- /utf-8 /W3 ^
  /DWIN32 /DNDEBUG /D_WINDOWS /D_USRDLL /DDIRECTINPUT_VERSION=0x0800 ^
  /I"%UPSTREAM%" /I"%UPSTREAM%\include" ^
  /Fo"%BUILD_ROOT%\obj\\" /Fd"%BUILD_ROOT%\obj\DeadSpaceFixes.pdb" ^
  "%UPSTREAM%\Config.cpp" ^
  "%UPSTREAM%\dllmain.cpp" ^
  "%UPSTREAM%\Log.cpp" ^
  "%UPSTREAM%\Utils.cpp" ^
  "%UPSTREAM%\Features\Graphics\AnisotropicFiltering.cpp" ^
  "%UPSTREAM%\Features\Graphics\D3D9Device.cpp" ^
  "%UPSTREAM%\Features\Graphics\FrameRateCap.cpp" ^
  "%UPSTREAM%\Features\Input\SdlGamepad.cpp" ^
  "%UPSTREAM%\Fixes\Graphics\SubtitleScale.cpp" ^
  "%UPSTREAM%\Fixes\Graphics\VSync.cpp" ^
  "%UPSTREAM%\Fixes\Input\LegacyDirectInput.cpp" ^
  "%UPSTREAM%\Fixes\Physics\Timer.cpp" ^
  "%UPSTREAM%\Fixes\Save\SafeStringHandling.cpp" ^
  "%UPSTREAM%\Fixes\UI\LoadingScreen.cpp" ^
  "%UPSTREAM%\Patches\Gameplay\IntroCutscene.cpp" ^
  "%UPSTREAM%\Patches\System\BorderlessWindow.cpp" ^
  "%UPSTREAM%\Patches\System\Telemetry.cpp" ^
  "%UPSTREAM%\Patches\UI\MainIntro.cpp" ^
  "%UPSTREAM%\Patches\UI\VersionString.cpp" ^
  "%UPSTREAM%\include\MinHook\buffer.c" ^
  "%UPSTREAM%\include\MinHook\hde32.c" ^
  "%UPSTREAM%\include\MinHook\hook.c" ^
  "%UPSTREAM%\include\MinHook\trampoline.c" ^
  /link /DEF:"%UPSTREAM%\proxy.def" /OUT:"%BUILD_ROOT%\xinput1_3.dll" ^
  /IMPLIB:"%BUILD_ROOT%\xinput1_3.lib" /PDB:"%BUILD_ROOT%\xinput1_3.pdb" ^
  /LIBPATH:"%UPSTREAM%\lib\SDL3\x86" SDL3.lib d3d9.lib user32.lib ^
  /SUBSYSTEM:WINDOWS /OPT:REF /OPT:ICF

if errorlevel 1 exit /b %errorlevel%

copy /y "%BUILD_ROOT%\xinput1_3.dll" "%~dp0dist\xinput1_3.dll" >nul
copy /y "%UPSTREAM%\lib\SDL3\x86\SDL3.dll" "%~dp0dist\SDL3.dll" >nul

exit /b %errorlevel%
