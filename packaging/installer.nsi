Unicode true
ManifestDPIAware true
!ifdef TEST_BUILD
  RequestExecutionLevel user
!else
  RequestExecutionLevel admin
!endif
SetCompressor /SOLID lzma
SetCompressorDictSize 32

!include "MUI2.nsh"
!include "LogicLib.nsh"

!ifndef GIT_HASH
  !define GIT_HASH "dev"
!endif
!ifndef OUTPUT_DIR
  !define OUTPUT_DIR "${__FILEDIR__}\..\dist"
!endif

!define PRODUCT_NAME "Dead Space 1 한국어 개선 패치"
!define PRODUCT_VERSION "0.1"
!define PRODUCT_PUBLISHER "YJSoft"
!define REPO_ROOT "${__FILEDIR__}\.."
!define PATCH_FILE "${REPO_ROOT}\packaging\patches\deadspace1-kr-v0.1.pat"
!define STEAM_LOCALIZATION_FILE "12F4D5F8.str"
!define PATCH_LOCALIZATION_FILE "D8CBB618.str"
!ifdef TEST_BUILD
  !define PATCH_REG_ROOT HKCU
  !define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeadSpace1KR-Test"
!else
  !define PATCH_REG_ROOT HKLM
  !define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeadSpace1KR"
!endif

Name "${PRODUCT_NAME} ${PRODUCT_VERSION}"
Caption "${PRODUCT_NAME} ${PRODUCT_VERSION}"
OutFile "${OUTPUT_DIR}\DeadSpace1-KR-${PRODUCT_VERSION}.exe"
InstallDir "$PROGRAMFILES32\Steam\steamapps\common\Dead Space"
BrandingText "${PRODUCT_NAME} ${PRODUCT_VERSION} (${GIT_HASH})"
ShowInstDetails show
ShowUninstDetails show

VIProductVersion "0.1.0.0"
VIAddVersionKey /LANG=1042 "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey /LANG=1042 "ProductVersion" "${PRODUCT_VERSION}"
VIAddVersionKey /LANG=1042 "CompanyName" "${PRODUCT_PUBLISHER}"
VIAddVersionKey /LANG=1042 "FileDescription" "Dead Space (2008) 한국어 패치 설치 마법사"
VIAddVersionKey /LANG=1042 "FileVersion" "${PRODUCT_VERSION}-${GIT_HASH}"
VIAddVersionKey /LANG=1042 "LegalCopyright" "Third-party licenses are included with the installation."

!define MUI_ABORTWARNING
!define MUI_ICON "${NSISDIR}\Contrib\Graphics\Icons\orange-install.ico"
!define MUI_UNICON "${NSISDIR}\Contrib\Graphics\Icons\orange-uninstall.ico"
!define MUI_WELCOMEPAGE_TITLE "Dead Space 1 한국어 개선 패치 ${PRODUCT_VERSION}"
!define MUI_WELCOMEPAGE_TEXT "이 마법사는 Steam 또는 EA App판 Dead Space (2008)에 한국어 개선 패치를 설치합니다.$\r$\n$\r$\n게임을 완전히 종료한 상태에서 계속하십시오. 정상적으로 설치된 원본 게임이 필요합니다."
!define MUI_DIRECTORYPAGE_TEXT_TOP "Dead Space.exe가 들어 있는 Dead Space (2008) 설치 폴더를 선택하십시오."
!define MUI_FINISHPAGE_TITLE "설치 완료"
!define MUI_FINISHPAGE_TEXT "한국어 개선 패치 설치가 완료되었습니다.$\r$\n$\r$\n원본 파일은 Dead Space 설치 폴더의 DS1K_Backup에 보존됩니다."

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

!insertmacro MUI_LANGUAGE "Korean"

Var BackupDir
Var PatchResult
Var FontSource
Var TextSource
Var UpgradeDetected
Var ExistingBuild
Var BackupRecoveryNeeded
Var FontPatchOk
Var TextPatchOk
Var RestoreFailed
Var InstallStage
Var TextOriginalAbsent
Var BackupMigrationFailed
Var BackupMigratedFrom
Var BackupTargetDir

!macro BackupRuntime FILE TAG
  IfFileExists "$BackupDir\runtime\${FILE}" backup_${TAG}_done
  IfFileExists "$BackupDir\runtime\${FILE}.absent" backup_${TAG}_done
  IfFileExists "$INSTDIR\${FILE}" 0 backup_${TAG}_absent
  ClearErrors
  CopyFiles /SILENT "$INSTDIR\${FILE}" "$BackupDir\runtime\${FILE}"
  IfErrors backup_error
  Goto backup_${TAG}_done
backup_${TAG}_absent:
  ClearErrors
  FileOpen $0 "$BackupDir\runtime\${FILE}.absent" w
  IfErrors backup_error
  FileWrite $0 "absent$\r$\n"
  FileClose $0
backup_${TAG}_done:
!macroend

!macro RestoreRuntime FILE TAG PREFIX
  IfFileExists "$BackupDir\runtime\${FILE}" 0 ${PREFIX}_restore_${TAG}_absent
  ClearErrors
  CopyFiles /SILENT "$BackupDir\runtime\${FILE}" "$INSTDIR\${FILE}"
  IfErrors 0 +2
  StrCpy $RestoreFailed "1"
  Goto ${PREFIX}_restore_${TAG}_done
${PREFIX}_restore_${TAG}_absent:
  IfFileExists "$BackupDir\runtime\${FILE}.absent" 0 ${PREFIX}_restore_${TAG}_done
  ClearErrors
  Delete "$INSTDIR\${FILE}"
  IfErrors 0 +2
  StrCpy $RestoreFailed "1"
${PREFIX}_restore_${TAG}_done:
!macroend

!macro CheckRuntimeBackup FILE TAG
  IfFileExists "$BackupDir\runtime\${FILE}" check_runtime_${TAG}_done
  IfFileExists "$BackupDir\runtime\${FILE}.absent" check_runtime_${TAG}_done
  StrCpy $BackupRecoveryNeeded "1"
check_runtime_${TAG}_done:
!macroend

!macro RepairRuntimeBackup FILE TAG
  IfFileExists "$BackupDir\runtime\${FILE}" repair_runtime_${TAG}_done
  IfFileExists "$BackupDir\runtime\${FILE}.absent" repair_runtime_${TAG}_done
  ClearErrors
  FileOpen $0 "$BackupDir\runtime\${FILE}.absent" w
  IfErrors backup_error
  FileWrite $0 "absent$\r$\n"
  FileClose $0
repair_runtime_${TAG}_done:
!macroend

!macro BackupLocalization TAG
  Delete "$BackupDir\text_assets\text\${PATCH_LOCALIZATION_FILE}"
  Delete "$BackupDir\text_assets\text\${PATCH_LOCALIZATION_FILE}.absent"
  StrCmp $TextOriginalAbsent "1" backup_localization_${TAG}_absent
  ClearErrors
  CopyFiles /SILENT "$INSTDIR\text_assets\text\${PATCH_LOCALIZATION_FILE}" "$BackupDir\text_assets\text\${PATCH_LOCALIZATION_FILE}"
  IfErrors backup_error
  Goto backup_localization_${TAG}_done
backup_localization_${TAG}_absent:
  ClearErrors
  FileOpen $0 "$BackupDir\text_assets\text\${PATCH_LOCALIZATION_FILE}.absent" w
  IfErrors backup_error
  FileWrite $0 "absent$\r$\n"
  FileClose $0
backup_localization_${TAG}_done:
!macroend

!macro TryVpatch SOURCE OUTPUT FLAG TAG
  StrCpy ${FLAG} "0"
  Delete "${OUTPUT}"
  vpatch::vpatchfile "$PLUGINSDIR\deadspace1-kr-v0.1.pat" "${SOURCE}" "${OUTPUT}"
  Pop $PatchResult
  StrCpy $0 $PatchResult 2
  StrCmp $0 "OK" 0 try_vpatch_${TAG}_done
  IfFileExists "${OUTPUT}" 0 try_vpatch_${TAG}_done
  StrCpy ${FLAG} "1"
try_vpatch_${TAG}_done:
!macroend

Function .onInit
  SetRegView 32
  ReadRegStr $0 ${PATCH_REG_ROOT} "${UNINSTALL_KEY}" "InstallLocation"
  IfFileExists "$0\Dead Space.exe" detected_dir
  ReadRegStr $0 HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 17470" "InstallLocation"
  ${If} $0 == ""
    ReadRegStr $0 HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 17470" "InstallLocation"
  ${EndIf}
  IfFileExists "$0\Dead Space.exe" detected_dir
  ReadRegStr $0 HKLM "Software\Electronic Arts\Dead Space" "Install Dir"
  IfFileExists "$0\Dead Space.exe" detected_dir
  Return
detected_dir:
  StrCpy $INSTDIR $0
FunctionEnd

Function .onVerifyInstDir
  IfFileExists "$INSTDIR\Dead Space.exe" 0 invalid_dir
  IfFileExists "$INSTDIR\text_assets\text_assets_global.str" 0 invalid_dir
  IfFileExists "$INSTDIR\text_assets\text\${STEAM_LOCALIZATION_FILE}" valid_dir
  IfFileExists "$INSTDIR\text_assets\text\${PATCH_LOCALIZATION_FILE}" 0 invalid_dir
valid_dir:
  Return
invalid_dir:
  Abort
FunctionEnd

Function LocateBackupDirectory
  StrCpy $BackupMigrationFailed "0"
  StrCpy $BackupMigratedFrom ""
  IfFileExists "$BackupDir\text_assets\text_assets_global.str" backup_locate_done
  FindFirst $0 $1 "$INSTDIR\DS1K_Backup_v*"
backup_locate_loop:
  StrCmp $1 "" backup_locate_close
  IfFileExists "$INSTDIR\$1\text_assets\text_assets_global.str" 0 backup_locate_next
  StrCpy $BackupDir "$INSTDIR\$1"
  StrCpy $BackupMigratedFrom "$1"
  Goto backup_locate_close
backup_locate_next:
  FindNext $0 $1
  Goto backup_locate_loop
backup_locate_close:
  FindClose $0
backup_locate_done:
FunctionEnd

Function MigrateBackupDirectory
  StrCmp $BackupMigratedFrom "" backup_migration_done
  # Remove only an empty destination left by an interrupted install.
  RMDir "$BackupTargetDir"
  ClearErrors
  Rename "$BackupDir" "$BackupTargetDir"
  IfErrors backup_migration_failed
  StrCpy $BackupDir "$BackupTargetDir"
  DetailPrint "기존 원본 백업 폴더를 DS1K_Backup으로 변경했습니다: $BackupMigratedFrom"
  Goto backup_migration_done
backup_migration_failed:
  StrCpy $BackupMigrationFailed "1"
backup_migration_done:
FunctionEnd

Function un.onInit
  GetFullPathName $INSTDIR "$INSTDIR\.."
!ifdef TEST_BUILD
  FileOpen $0 "$TEMP\ds1k-uninstall-test.log" w
  FileWrite $0 "EXEDIR=$EXEDIR$\r$\nEXEPATH=$EXEPATH$\r$\nINSTDIR=$INSTDIR$\r$\n"
  FileClose $0
!endif
FunctionEnd

Function RestoreInstalledFiles
  StrCpy $RestoreFailed "0"
  IfFileExists "$BackupDir\text_assets\text_assets_global.str" 0 restore_installed_font_done
  ClearErrors
  CopyFiles /SILENT "$BackupDir\text_assets\text_assets_global.str" "$INSTDIR\text_assets\text_assets_global.str"
  IfErrors 0 +2
  StrCpy $RestoreFailed "1"
restore_installed_font_done:
  IfFileExists "$BackupDir\text_assets\text\${PATCH_LOCALIZATION_FILE}" 0 restore_installed_text_absent
  ClearErrors
  CopyFiles /SILENT "$BackupDir\text_assets\text\${PATCH_LOCALIZATION_FILE}" "$INSTDIR\text_assets\text\${PATCH_LOCALIZATION_FILE}"
  IfErrors 0 +2
  StrCpy $RestoreFailed "1"
  Goto restore_installed_text_done
restore_installed_text_absent:
  IfFileExists "$BackupDir\text_assets\text\${PATCH_LOCALIZATION_FILE}.absent" 0 restore_installed_text_done
  ClearErrors
  Delete "$INSTDIR\text_assets\text\${PATCH_LOCALIZATION_FILE}"
  IfErrors 0 +2
  StrCpy $RestoreFailed "1"
restore_installed_text_done:
  !insertmacro RestoreRuntime "ds1k_utf8.dll" "ds1k" "install"
  !insertmacro RestoreRuntime "xinput1_3.dll" "xinput" "install"
  !insertmacro RestoreRuntime "SDL3.dll" "sdl" "install"
  !insertmacro RestoreRuntime "DeadSpaceFixes.ini" "config" "install"
FunctionEnd

Section "한국어 개선 패치" SecMain
  SectionIn RO
  StrCpy $InstallStage "초기화"
  StrCpy $BackupTargetDir "$INSTDIR\DS1K_Backup"
  StrCpy $BackupDir "$BackupTargetDir"
  Call LocateBackupDirectory
  StrCpy $FontSource "$INSTDIR\text_assets\text_assets_global.str"
  StrCpy $TextSource "$INSTDIR\text_assets\text\${PATCH_LOCALIZATION_FILE}"
  StrCpy $TextOriginalAbsent "0"
  IfFileExists "$TextSource" initial_text_source_ready
  StrCpy $TextSource "$INSTDIR\text_assets\text\${STEAM_LOCALIZATION_FILE}"
  StrCpy $TextOriginalAbsent "1"
initial_text_source_ready:
  StrCpy $UpgradeDetected "0"
  StrCpy $ExistingBuild ""
  StrCpy $BackupRecoveryNeeded "0"

  ReadRegStr $ExistingBuild ${PATCH_REG_ROOT} "${UNINSTALL_KEY}" "BuildCommit"
  IfFileExists "$BackupDir\text_assets\text_assets_global.str" upgrade_found
  IfFileExists "$INSTDIR\DS1K_Patch\installed-version.txt" upgrade_found
  ReadRegStr $0 ${PATCH_REG_ROOT} "${UNINSTALL_KEY}" "InstallLocation"
  StrCmp $0 "$INSTDIR" upgrade_found upgrade_detection_done
upgrade_found:
  StrCpy $UpgradeDetected "1"
upgrade_detection_done:

  StrCmp $UpgradeDetected "1" 0 upgrade_sources_ready
  StrCmp $ExistingBuild "" 0 +2
  StrCpy $ExistingBuild "(기록 없음)"
  DetailPrint "기존 한국어 패치 설치를 발견했습니다: $ExistingBuild"

  IfFileExists "$BackupDir\text_assets\text_assets_global.str" 0 upgrade_backup_incomplete
  StrCpy $FontSource "$BackupDir\text_assets\text_assets_global.str"
  IfFileExists "$BackupDir\text_assets\text\${PATCH_LOCALIZATION_FILE}" upgrade_text_backup_present
  IfFileExists "$BackupDir\text_assets\text\${PATCH_LOCALIZATION_FILE}.absent" 0 upgrade_backup_incomplete
  IfFileExists "$INSTDIR\text_assets\text\${STEAM_LOCALIZATION_FILE}" 0 upgrade_backup_incomplete
  StrCpy $TextSource "$INSTDIR\text_assets\text\${STEAM_LOCALIZATION_FILE}"
  StrCpy $TextOriginalAbsent "1"
  Goto upgrade_text_source_ready
upgrade_text_backup_present:
  StrCpy $TextSource "$BackupDir\text_assets\text\${PATCH_LOCALIZATION_FILE}"
  StrCpy $TextOriginalAbsent "0"
upgrade_text_source_ready:
  !insertmacro CheckRuntimeBackup "ds1k_utf8.dll" "ds1k"
  !insertmacro CheckRuntimeBackup "xinput1_3.dll" "xinput"
  !insertmacro CheckRuntimeBackup "SDL3.dll" "sdl"
  !insertmacro CheckRuntimeBackup "DeadSpaceFixes.ini" "config"
  StrCmp $BackupRecoveryNeeded "1" upgrade_backup_incomplete
  Goto upgrade_sources_ready

upgrade_backup_incomplete:
  StrCpy $BackupRecoveryNeeded "1"
  StrCpy $FontSource "$INSTDIR\text_assets\text_assets_global.str"
  StrCpy $TextOriginalAbsent "1"
  StrCpy $TextSource "$INSTDIR\text_assets\text\${STEAM_LOCALIZATION_FILE}"
  IfFileExists "$TextSource" upgrade_live_sources_ready
  StrCpy $TextOriginalAbsent "0"
  StrCpy $TextSource "$INSTDIR\text_assets\text\${PATCH_LOCALIZATION_FILE}"
upgrade_live_sources_ready:
  DetailPrint "기존 설치 정보를 확인하는 중..."

upgrade_sources_ready:

  DetailPrint "게임 파일을 확인하고 설치를 준비하는 중..."
  InitPluginsDir
  StrCmp $UpgradeDetected "1" 0 config_snapshot_done
  IfFileExists "$INSTDIR\DeadSpaceFixes.ini" 0 config_snapshot_done
  ClearErrors
  CopyFiles /SILENT "$INSTDIR\DeadSpaceFixes.ini" "$PLUGINSDIR\previous-DeadSpaceFixes.ini"
  IfErrors snapshot_error
config_snapshot_done:

  SetOutPath "$PLUGINSDIR"
  File /oname=deadspace1-kr-v0.1.pat "${PATCH_FILE}"

patch_attempt:
  !insertmacro TryVpatch "$FontSource" "$PLUGINSDIR\text_assets_global.str" "$FontPatchOk" "font_source"
  StrCmp $FontPatchOk "1" 0 patch_attempt_failed
  !insertmacro TryVpatch "$TextSource" "$PLUGINSDIR\${PATCH_LOCALIZATION_FILE}" "$TextPatchOk" "text_source"
  StrCmp $TextPatchOk "1" patch_ready

patch_attempt_failed:
  StrCmp $UpgradeDetected "1" 0 patch_error
  StrCmp $BackupRecoveryNeeded "1" upgrade_backup_error
  StrCpy $BackupRecoveryNeeded "1"
  StrCpy $FontSource "$INSTDIR\text_assets\text_assets_global.str"
  StrCpy $TextOriginalAbsent "1"
  StrCpy $TextSource "$INSTDIR\text_assets\text\${STEAM_LOCALIZATION_FILE}"
  IfFileExists "$TextSource" retry_live_sources_ready
  StrCpy $TextOriginalAbsent "0"
  StrCpy $TextSource "$INSTDIR\text_assets\text\${PATCH_LOCALIZATION_FILE}"
retry_live_sources_ready:
  DetailPrint "현재 게임 파일로 설치를 다시 준비하는 중..."
  Goto patch_attempt

patch_ready:
  DetailPrint "설치 준비가 완료되었습니다."
  Call MigrateBackupDirectory
  StrCmp $BackupMigrationFailed "1" backup_migration_error

  DetailPrint "원본 파일을 백업하는 중..."
  CreateDirectory "$BackupDir\text_assets\text"
  CreateDirectory "$BackupDir\runtime"

  StrCmp $UpgradeDetected "1" upgrade_prepare
  ClearErrors
  CopyFiles /SILENT "$INSTDIR\text_assets\text_assets_global.str" "$BackupDir\text_assets\text_assets_global.str"
  IfErrors backup_error
  !insertmacro BackupLocalization "fresh"
  !insertmacro BackupRuntime "ds1k_utf8.dll" "ds1k"
  !insertmacro BackupRuntime "xinput1_3.dll" "xinput"
  !insertmacro BackupRuntime "SDL3.dll" "sdl"
  !insertmacro BackupRuntime "DeadSpaceFixes.ini" "config"
  Goto originals_ready

upgrade_prepare:
  StrCmp $BackupRecoveryNeeded "1" upgrade_recovery_prepare
  DetailPrint "기존 패치를 정리하는 중..."
  Call RestoreInstalledFiles
  StrCmp $RestoreFailed "1" upgrade_restore_error
  IfFileExists "$PLUGINSDIR\previous-DeadSpaceFixes.ini" 0 originals_ready
  ClearErrors
  CopyFiles /SILENT "$PLUGINSDIR\previous-DeadSpaceFixes.ini" "$INSTDIR\DeadSpaceFixes.ini"
  IfErrors upgrade_restore_error
  Goto originals_ready

upgrade_recovery_prepare:
  DetailPrint "원본 파일 백업을 다시 준비하는 중..."
  ClearErrors
  CopyFiles /SILENT "$INSTDIR\text_assets\text_assets_global.str" "$BackupDir\text_assets\text_assets_global.str"
  IfErrors backup_error
  !insertmacro BackupLocalization "recovery"
  !insertmacro RepairRuntimeBackup "ds1k_utf8.dll" "ds1k"
  !insertmacro RepairRuntimeBackup "xinput1_3.dll" "xinput"
  !insertmacro RepairRuntimeBackup "SDL3.dll" "sdl"
  !insertmacro RepairRuntimeBackup "DeadSpaceFixes.ini" "config"

originals_ready:

  StrCpy $InstallStage "한국어 파일 설치"
  DetailPrint "한국어 개선 패치를 설치하는 중..."
  ClearErrors
  CopyFiles /SILENT "$PLUGINSDIR\text_assets_global.str" "$INSTDIR\text_assets\text_assets_global.str"
  IfErrors install_error
  ClearErrors
  CopyFiles /SILENT "$PLUGINSDIR\${PATCH_LOCALIZATION_FILE}" "$INSTDIR\text_assets\text\${PATCH_LOCALIZATION_FILE}"
  IfErrors install_error

  SetOverwrite on
  SetOutPath "$INSTDIR"
  StrCpy $InstallStage "런타임 DLL 설치"
  ClearErrors
  File /oname=ds1k_utf8.dll "${REPO_ROOT}\dist\ds1k_utf8.dll"
  File /oname=xinput1_3.dll "${REPO_ROOT}\dist\xinput1_3.dll"
  File /oname=SDL3.dll "${REPO_ROOT}\dist\SDL3.dll"
  IfErrors install_error

  StrCpy $InstallStage "설정 파일 설치"
  IfFileExists "$INSTDIR\DeadSpaceFixes.ini" config_install_done
  ClearErrors
  File /oname=DeadSpaceFixes.ini "${REPO_ROOT}\dist\DeadSpaceFixes.ini"
  IfErrors install_error
config_install_done:

  StrCpy $InstallStage "설명 및 라이선스 설치"
  SetOutPath "$INSTDIR\DS1K_Patch"
  ClearErrors
  File /oname=README_KO.txt "${REPO_ROOT}\docs\INSTALL_KO.txt"
  File "${REPO_ROOT}\THIRD_PARTY_NOTICES.txt"
  File "${REPO_ROOT}\packaging\patches\manifest.json"
  SetOutPath "$INSTDIR\DS1K_Patch\licenses"
  File /oname=DeadSpace2008Fixes-MIT.txt "${REPO_ROOT}\third_party\DeadSpace2008Fixes\LICENSE"
  File "${REPO_ROOT}\third_party\licenses\MinHook-BSD-2-Clause.txt"
  File "${REPO_ROOT}\third_party\licenses\SDL3-zlib.txt"
  File /oname=NanumBarunGothic-OFL-1.1.txt "${REPO_ROOT}\third_party\NanumBarunGothic\OFL-1.1.txt"
  File "${REPO_ROOT}\third_party\licenses\NSIS-COPYING.txt"
  File "${REPO_ROOT}\third_party\licenses\VPatch-zlib.txt"
  IfErrors install_error

  StrCpy $InstallStage "제거 프로그램 생성"
  ClearErrors
  WriteUninstaller "$INSTDIR\DS1K_Patch\Uninstall.exe"
  IfErrors install_error
  StrCpy $InstallStage "설치 버전 기록"
  ClearErrors
  FileOpen $0 "$INSTDIR\DS1K_Patch\installed-version.txt" w
  IfErrors install_error
  FileWrite $0 "Dead Space 1 KR ${PRODUCT_VERSION}$\r$\nCommit ${GIT_HASH}$\r$\n"
  FileClose $0

!ifndef TEST_BUILD
  StrCpy $InstallStage "레지스트리 DisplayName 기록"
  ClearErrors
  WriteRegStr ${PATCH_REG_ROOT} "${UNINSTALL_KEY}" "DisplayName" "${PRODUCT_NAME} ${PRODUCT_VERSION}"
  IfErrors install_error
  StrCpy $InstallStage "레지스트리 DisplayVersion 기록"
  ClearErrors
  WriteRegStr ${PATCH_REG_ROOT} "${UNINSTALL_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
  IfErrors install_error
  StrCpy $InstallStage "레지스트리 Publisher 기록"
  ClearErrors
  WriteRegStr ${PATCH_REG_ROOT} "${UNINSTALL_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  IfErrors install_error
  StrCpy $InstallStage "레지스트리 InstallLocation 기록"
  ClearErrors
  WriteRegStr ${PATCH_REG_ROOT} "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  IfErrors install_error
  StrCpy $InstallStage "레지스트리 BuildCommit 기록"
  ClearErrors
  WriteRegStr ${PATCH_REG_ROOT} "${UNINSTALL_KEY}" "BuildCommit" "${GIT_HASH}"
  IfErrors install_error
  StrCpy $InstallStage "레지스트리 BackupDirectory 기록"
  ClearErrors
  WriteRegStr ${PATCH_REG_ROOT} "${UNINSTALL_KEY}" "BackupDirectory" "$BackupDir"
  IfErrors install_error
  StrCpy $InstallStage "레지스트리 UninstallString 기록"
  ClearErrors
  WriteRegStr ${PATCH_REG_ROOT} "${UNINSTALL_KEY}" "UninstallString" "$\"$INSTDIR\DS1K_Patch\Uninstall.exe$\""
  IfErrors install_error
  StrCpy $InstallStage "레지스트리 NoModify 기록"
  ClearErrors
  WriteRegDWORD ${PATCH_REG_ROOT} "${UNINSTALL_KEY}" "NoModify" 1
  IfErrors install_error
  StrCpy $InstallStage "레지스트리 NoRepair 기록"
  ClearErrors
  WriteRegDWORD ${PATCH_REG_ROOT} "${UNINSTALL_KEY}" "NoRepair" 1
  IfErrors install_error
!endif
  Goto install_done

patch_error:
!ifdef TEST_BUILD
  FileOpen $0 "$INSTDIR\installer-test.log" w
  FileWrite $0 "patch_error: $PatchResult$\r$\nfont_source: $FontSource$\r$\ntext_source: $TextSource$\r$\n"
  FileClose $0
!endif
  MessageBox MB_ICONSTOP|MB_OK "게임 파일을 확인할 수 없어 설치를 중단했습니다.$\r$\n$\r$\n지원되는 Steam 또는 EA App판 Dead Space (2008)가 원본 상태로 설치되어 있어야 합니다. 사용 중인 게임 클라이언트에서 게임 파일을 복구한 뒤 다시 설치하십시오." /SD IDOK
  Abort

backup_migration_error:
  MessageBox MB_ICONSTOP|MB_OK "기존 원본 백업 폴더의 이름을 변경할 수 없어 설치를 중단했습니다.$\r$\n$\r$\n게임 파일은 변경하지 않았습니다. Dead Space와 백업 폴더를 사용하는 프로그램을 종료하고 폴더 쓰기 권한을 확인한 뒤 다시 실행하십시오." /SD IDOK
  Abort

upgrade_backup_error:
!ifdef TEST_BUILD
  FileOpen $0 "$INSTDIR\installer-test.log" w
  FileWrite $0 "upgrade_backup_error: $PatchResult$\r$\nexisting_build: $ExistingBuild$\r$\nnew_build: ${GIT_HASH}$\r$\nfont_source: $FontSource$\r$\ntext_source: $TextSource$\r$\n"
  FileClose $0
!endif
  MessageBox MB_ICONSTOP|MB_OK "기존 패치의 원본 백업이 없거나 손상되어 안전하게 업그레이드할 수 없습니다.$\r$\n$\r$\n게임 파일은 변경하지 않았습니다. 사용 중인 게임 클라이언트에서 Dead Space 원본 파일을 복구한 뒤 이 설치 파일을 다시 실행하십시오.$\r$\n$\r$\n다른 모드를 사용 중이면 먼저 별도로 백업하십시오." /SD IDOK
  Abort

snapshot_error:
  MessageBox MB_ICONSTOP|MB_OK "기존 DeadSpaceFixes.ini 설정을 임시 보관할 수 없어 업그레이드를 중단했습니다. 게임 파일은 변경하지 않았습니다." /SD IDOK
  Abort

backup_error:
!ifdef TEST_BUILD
  FileOpen $0 "$INSTDIR\installer-test.log" w
  FileWrite $0 "backup_error$\r$\n"
  FileClose $0
!endif
  MessageBox MB_ICONSTOP|MB_OK "원본 파일 백업에 실패했습니다. 디스크 공간과 폴더 쓰기 권한을 확인하십시오. 게임 파일은 변경하지 않았습니다." /SD IDOK
  Abort

upgrade_restore_error:
!ifdef TEST_BUILD
  FileOpen $0 "$INSTDIR\installer-test.log" w
  FileWrite $0 "upgrade_restore_error$\r$\nexisting_build: $ExistingBuild$\r$\nnew_build: ${GIT_HASH}$\r$\n"
  FileClose $0
!endif
  DetailPrint "업그레이드 복원 실패: 원본 상태로 되돌립니다."
  Call RestoreInstalledFiles
  IfFileExists "$PLUGINSDIR\previous-DeadSpaceFixes.ini" 0 +2
  CopyFiles /SILENT "$PLUGINSDIR\previous-DeadSpaceFixes.ini" "$INSTDIR\DeadSpaceFixes.ini"
  DeleteRegKey ${PATCH_REG_ROOT} "${UNINSTALL_KEY}"
  RMDir /r "$INSTDIR\DS1K_Patch"
  MessageBox MB_ICONSTOP|MB_OK "기존 패치 복원 중 오류가 발생해 원본 상태로 되돌렸습니다. Dead Space가 실행 중인지 확인한 뒤 다시 설치하십시오." /SD IDOK
  Abort

install_error:
!ifdef TEST_BUILD
  FileOpen $0 "$INSTDIR\installer-test.log" w
  FileWrite $0 "install_error: $InstallStage$\r$\n"
  FileClose $0
!endif
  DetailPrint "설치 실패: 백업에서 원본 파일을 복원합니다."
  Call RestoreInstalledFiles
  IfFileExists "$PLUGINSDIR\previous-DeadSpaceFixes.ini" 0 +2
  CopyFiles /SILENT "$PLUGINSDIR\previous-DeadSpaceFixes.ini" "$INSTDIR\DeadSpaceFixes.ini"
  DeleteRegKey ${PATCH_REG_ROOT} "${UNINSTALL_KEY}"
  RMDir /r "$INSTDIR\DS1K_Patch"
  MessageBox MB_ICONSTOP|MB_OK "파일 설치에 실패하여 원본을 복원했습니다. 기존 패치가 있었다면 안전을 위해 제거되었습니다. Dead Space가 실행 중인지 확인한 뒤 다시 설치하십시오." /SD IDOK
  Abort

install_done:
  DetailPrint "설치 완료. 백업 위치: $BackupDir"
SectionEnd

Function un.RestoreInstalledFiles
  StrCpy $BackupDir "$INSTDIR\DS1K_Backup"
  StrCpy $RestoreFailed "0"
  IfFileExists "$BackupDir\text_assets\text_assets_global.str" 0 un_no_backup
  IfFileExists "$BackupDir\text_assets\text\${PATCH_LOCALIZATION_FILE}" un_text_backup_ready
  IfFileExists "$BackupDir\text_assets\text\${PATCH_LOCALIZATION_FILE}.absent" 0 un_no_backup
un_text_backup_ready:
  ClearErrors
  CopyFiles /SILENT "$BackupDir\text_assets\text_assets_global.str" "$INSTDIR\text_assets\text_assets_global.str"
  IfErrors un_restore_error
  IfFileExists "$BackupDir\text_assets\text\${PATCH_LOCALIZATION_FILE}" 0 un_restore_text_absent
  ClearErrors
  CopyFiles /SILENT "$BackupDir\text_assets\text\${PATCH_LOCALIZATION_FILE}" "$INSTDIR\text_assets\text\${PATCH_LOCALIZATION_FILE}"
  IfErrors un_restore_error
  Goto un_restore_text_done
un_restore_text_absent:
  ClearErrors
  Delete "$INSTDIR\text_assets\text\${PATCH_LOCALIZATION_FILE}"
  IfErrors un_restore_error
un_restore_text_done:
  !insertmacro RestoreRuntime "ds1k_utf8.dll" "ds1k" "uninstall"
  !insertmacro RestoreRuntime "xinput1_3.dll" "xinput" "uninstall"
  !insertmacro RestoreRuntime "SDL3.dll" "sdl" "uninstall"
  !insertmacro RestoreRuntime "DeadSpaceFixes.ini" "config" "uninstall"
  StrCmp $RestoreFailed "1" un_restore_error
  Return
un_no_backup:
  MessageBox MB_ICONSTOP|MB_OK "원본 백업을 찾을 수 없어 제거할 수 없습니다.$\r$\n$BackupDir" /SD IDOK
  Abort
un_restore_error:
  MessageBox MB_ICONSTOP|MB_OK "원본 파일 복원에 실패했습니다. Dead Space를 종료하고 다시 시도하십시오." /SD IDOK
  Abort
FunctionEnd

Section "Uninstall"
  Call un.RestoreInstalledFiles
  DeleteRegKey ${PATCH_REG_ROOT} "${UNINSTALL_KEY}"
  RMDir /r "$INSTDIR\DS1K_Patch"
  MessageBox MB_ICONINFORMATION|MB_OK "한국어 개선 패치를 제거하고 원본 파일을 복원했습니다.$\r$\n$\r$\n백업 폴더는 안전을 위해 유지합니다:$\r$\n$INSTDIR\DS1K_Backup" /SD IDOK
SectionEnd
