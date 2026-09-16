@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "PACKAGE_DIR=%~dp0"
set "GAME_DIR=%~1"
if defined GAME_DIR set "GAME_DIR=%GAME_DIR:"=%"

if not exist "%GAME_DIR%\Dead Space.exe" (
  for %%I in ("%PACKAGE_DIR%..") do set "PARENT_DIR=%%~fI"
  call :try_parent
)

if not exist "%GAME_DIR%\Dead Space.exe" goto :prompt_game_dir
goto :game_dir_ready

:prompt_game_dir
echo.
echo Enter the Dead Space game folder path.
set /p "GAME_DIR=> "
set "GAME_DIR=%GAME_DIR:"=%"

:game_dir_ready

if not exist "%GAME_DIR%\Dead Space.exe" (
  echo.
  echo ERROR: Dead Space.exe was not found.
  pause
  exit /b 1
)

tasklist /FI "IMAGENAME eq Dead Space.exe" 2>nul | find /I "Dead Space.exe" >nul
if not errorlevel 1 (
  echo.
  echo ERROR: Close Dead Space before uninstalling.
  pause
  exit /b 1
)

set "BACKUP_DIR=%GAME_DIR%\DS1K_Backup_PreInstall"
if not exist "%BACKUP_DIR%" (
  echo.
  echo ERROR: Backup folder was not found: "%BACKUP_DIR%"
  echo No files were changed.
  pause
  exit /b 1
)

call :restore "xinput1_3.dll" "xinput1_3.dll" || goto :restore_error
call :restore "ds1k_utf8.dll" "ds1k_utf8.dll" || goto :restore_error
call :restore "SDL3.dll" "SDL3.dll" || goto :restore_error
call :restore "DeadSpaceFixes.ini" "DeadSpaceFixes.ini" || goto :restore_error
call :restore "text_assets\text_assets_global.str" "text_assets_global.str" || goto :restore_error
call :restore "text_assets\text\D8CBB618.str" "D8CBB618.str" || goto :restore_error

echo.
echo DS1K files were removed and previous files were restored.
echo The backup and DS1K log folders were intentionally kept.
pause
exit /b 0

:try_parent
if exist "%PARENT_DIR%\Dead Space.exe" set "GAME_DIR=%PARENT_DIR%"
exit /b 0

:restore
set "RELATIVE_PATH=%~1"
set "BACKUP_NAME=%~2"
if exist "%BACKUP_DIR%\%BACKUP_NAME%" (
  copy /Y "%BACKUP_DIR%\%BACKUP_NAME%" "%GAME_DIR%\%RELATIVE_PATH%" >nul || exit /b 1
  exit /b 0
)
if exist "%BACKUP_DIR%\%BACKUP_NAME%.absent" (
  if exist "%GAME_DIR%\%RELATIVE_PATH%" del /Q "%GAME_DIR%\%RELATIVE_PATH%" || exit /b 1
)
exit /b 0

:restore_error
echo.
echo ERROR: A file could not be restored. The backup folder was not deleted.
pause
exit /b 1
