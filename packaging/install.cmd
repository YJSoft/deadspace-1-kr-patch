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
echo Example: D:\SteamLibrary\steamapps\common\Dead Space
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
  echo ERROR: Close Dead Space before installing.
  pause
  exit /b 1
)

set "BACKUP_DIR=%GAME_DIR%\DS1K_Backup_PreInstall"
if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"
if errorlevel 1 goto :backup_error

call :backup "xinput1_3.dll" "xinput1_3.dll" || goto :backup_error
call :backup "ds1k_utf8.dll" "ds1k_utf8.dll" || goto :backup_error
call :backup "SDL3.dll" "SDL3.dll" || goto :backup_error
call :backup "DeadSpaceFixes.ini" "DeadSpaceFixes.ini" || goto :backup_error
call :backup "text_assets\text_assets_global.str" "text_assets_global.str" || goto :backup_error
call :backup "text_assets\text\D8CBB618.str" "D8CBB618.str" || goto :backup_error

if not exist "%GAME_DIR%\text_assets" mkdir "%GAME_DIR%\text_assets"
if not exist "%GAME_DIR%\text_assets\text" mkdir "%GAME_DIR%\text_assets\text"

copy /Y "%PACKAGE_DIR%payload\xinput1_3.dll" "%GAME_DIR%\xinput1_3.dll" >nul || goto :copy_error
copy /Y "%PACKAGE_DIR%payload\ds1k_utf8.dll" "%GAME_DIR%\ds1k_utf8.dll" >nul || goto :copy_error
copy /Y "%PACKAGE_DIR%payload\SDL3.dll" "%GAME_DIR%\SDL3.dll" >nul || goto :copy_error
copy /Y "%PACKAGE_DIR%payload\DeadSpaceFixes.ini" "%GAME_DIR%\DeadSpaceFixes.ini" >nul || goto :copy_error
copy /Y "%PACKAGE_DIR%payload\text_assets\text_assets_global.str" "%GAME_DIR%\text_assets\text_assets_global.str" >nul || goto :copy_error
copy /Y "%PACKAGE_DIR%payload\text_assets\text\D8CBB618.str" "%GAME_DIR%\text_assets\text\D8CBB618.str" >nul || goto :copy_error

>"%BACKUP_DIR%\DS1K-Test-v0.1.installed" echo Installed from %PACKAGE_DIR%

echo.
echo DS1K Test v0.1 installation completed.
echo Backup: "%BACKUP_DIR%"
echo Launch Dead Space from the Steam library.
pause
exit /b 0

:try_parent
if exist "%PARENT_DIR%\Dead Space.exe" set "GAME_DIR=%PARENT_DIR%"
exit /b 0

:backup
set "RELATIVE_PATH=%~1"
set "BACKUP_NAME=%~2"
if exist "%BACKUP_DIR%\%BACKUP_NAME%" exit /b 0
if exist "%BACKUP_DIR%\%BACKUP_NAME%.absent" exit /b 0
if exist "%GAME_DIR%\%RELATIVE_PATH%" (
  copy /Y "%GAME_DIR%\%RELATIVE_PATH%" "%BACKUP_DIR%\%BACKUP_NAME%" >nul || exit /b 1
) else (
  type nul >"%BACKUP_DIR%\%BACKUP_NAME%.absent" || exit /b 1
)
exit /b 0

:backup_error
echo.
echo ERROR: Existing files could not be backed up. No patch files were installed.
pause
exit /b 1

:copy_error
echo.
echo ERROR: A file could not be copied. Close the game and check permissions.
pause
exit /b 1
