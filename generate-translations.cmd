@echo off
setlocal

if "%~3"=="" (
  echo Usage: generate-translations.cmd original-lh2 legacy-Launcher.xml output.csv
  exit /b 2
)

call "%~dp0build-assets.cmd"
if errorlevel 1 exit /b %errorlevel%

"%TEMP%\deadspace-1-kr-patch-assets\GenerateTranslationCsv.exe" "%~1" "%~2" "%~3"
exit /b %errorlevel%
