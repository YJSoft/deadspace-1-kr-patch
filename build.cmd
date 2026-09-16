@echo off
setlocal

call "%~dp0tools\vsdevcmd.cmd" x86
if errorlevel 1 exit /b %errorlevel%

set "BUILD_ROOT=%TEMP%\deadspace-1-kr-patch-native"
if not exist "%BUILD_ROOT%" mkdir "%BUILD_ROOT%"
if not exist "%BUILD_ROOT%\obj" mkdir "%BUILD_ROOT%\obj"
if not exist "%~dp0dist" mkdir "%~dp0dist"

cl.exe /nologo /LD /MT /O2 /Oi /GS /Gy /EHsc /std:c++17 /permissive- /W4 /wd4995 ^
  /DWIN32 /DNDEBUG /D_WINDOWS /D_USRDLL /DUNICODE /D_UNICODE ^
  /Fo"%BUILD_ROOT%\obj\\" /Fd"%BUILD_ROOT%\obj\ds1k_proxy.pdb" ^
  "src\dllmain.cpp" ^
  /link /DEF:"src\xinput_proxy.def" /OUT:"%BUILD_ROOT%\ds1k_utf8.dll" ^
  /IMPLIB:"%BUILD_ROOT%\ds1k_utf8.lib" /PDB:"%BUILD_ROOT%\ds1k_utf8.pdb" ^
  /SUBSYSTEM:WINDOWS /OPT:REF /OPT:ICF

if errorlevel 1 exit /b %errorlevel%
copy /y "%BUILD_ROOT%\ds1k_utf8.dll" "%~dp0dist\ds1k_utf8.dll" >nul

call "%~dp0build-fixes.cmd"
if errorlevel 1 exit /b %errorlevel%

exit /b %errorlevel%
