@echo off
setlocal

call "%~dp0tools\vsdevcmd.cmd" x64
if errorlevel 1 exit /b %errorlevel%

set "ASSET_BUILD=%TEMP%\deadspace-1-kr-patch-assets"
if not exist "%ASSET_BUILD%" mkdir "%ASSET_BUILD%"

csc.exe /nologo /optimize+ /platform:x64 /target:exe ^
  /reference:System.Drawing.dll ^
  /out:"%ASSET_BUILD%\BuildPocAssets.exe" ^
  "tools\BuildPocAssets.cs"
if errorlevel 1 exit /b %errorlevel%

csc.exe /nologo /optimize+ /platform:anycpu /target:exe ^
  /out:"%ASSET_BUILD%\GenerateTranslationCsv.exe" ^
  "tools\GenerateTranslationCsv.cs"

exit /b %errorlevel%
