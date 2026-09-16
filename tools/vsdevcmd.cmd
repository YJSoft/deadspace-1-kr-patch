@echo off

set "DS1K_TARGET_ARCH=%~1"
if not defined DS1K_TARGET_ARCH set "DS1K_TARGET_ARCH=x86"

set "DS1K_VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%DS1K_VSWHERE%" (
  echo ERROR: Visual Studio Installer's vswhere.exe was not found.
  exit /b 1
)

set "DS1K_VS_INSTALL="
for /f "usebackq delims=" %%I in (`"%DS1K_VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "DS1K_VS_INSTALL=%%I"

if not defined DS1K_VS_INSTALL (
  echo ERROR: Visual Studio 2022 with the C++ x86/x64 tools was not found.
  exit /b 1
)

call "%DS1K_VS_INSTALL%\Common7\Tools\VsDevCmd.bat" -arch=%DS1K_TARGET_ARCH% -host_arch=x64
exit /b %errorlevel%
