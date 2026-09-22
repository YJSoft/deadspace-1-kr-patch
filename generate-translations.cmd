@echo off
setlocal

if "%~3"=="" (
  echo Usage: generate-translations.cmd original-lh2 legacy-Launcher.xml output.csv [existing.csv]
  exit /b 2
)

call "%~dp0build-assets.cmd"
if errorlevel 1 exit /b %errorlevel%

if "%~4"=="" (
  "%TEMP%\deadspace-1-kr-patch-assets\GenerateTranslationCsv.exe" "%~1" "%~2" "%~3"
) else (
  "%TEMP%\deadspace-1-kr-patch-assets\GenerateTranslationCsv.exe" "%~1" "%~2" "%~3" "%~4"
)
exit /b %errorlevel%
