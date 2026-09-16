@echo off
setlocal

call "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64
if errorlevel 1 exit /b %errorlevel%

set "ASSET_BUILD=%TEMP%\ds1k-prototype-assets"
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
