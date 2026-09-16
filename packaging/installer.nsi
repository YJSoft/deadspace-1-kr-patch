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
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeadSpace1KR"

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
!define MUI_WELCOMEPAGE_TEXT "이 마법사는 Steam판 Dead Space (2008) 1.0.0.222에 한국어 개선 패치를 설치합니다.$\r$\n$\r$\n원본 STR는 설치 폴더에서 직접 읽어 백업한 뒤 한국어 STR로 변환합니다. 게임을 종료한 상태에서 계속하십시오."
!define MUI_DIRECTORYPAGE_TEXT_TOP "Dead Space.exe가 들어 있는 Dead Space (2008) 설치 폴더를 선택하십시오. 원본 STR가 맞지 않으면 설치하지 않습니다."
!define MUI_FINISHPAGE_TITLE "설치 완료"
!define MUI_FINISHPAGE_TEXT "한국어 개선 패치 설치가 완료되었습니다.$\r$\n$\r$\n원본 파일은 Dead Space 설치 폴더의 DS1K_Backup_v0.1에 보존됩니다."

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
  Goto ${PREFIX}_restore_${TAG}_done
${PREFIX}_restore_${TAG}_absent:
  IfFileExists "$BackupDir\runtime\${FILE}.absent" 0 ${PREFIX}_restore_${TAG}_done
  Delete "$INSTDIR\${FILE}"
${PREFIX}_restore_${TAG}_done:
!macroend

Function .onInit
  SetRegView 32
  ReadRegStr $0 HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 17470" "InstallLocation"
  ${If} $0 == ""
    ReadRegStr $0 HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 17470" "InstallLocation"
  ${EndIf}
  ${If} $0 != ""
    StrCpy $INSTDIR $0
  ${EndIf}
FunctionEnd

Function .onVerifyInstDir
  IfFileExists "$INSTDIR\Dead Space.exe" 0 invalid_dir
  IfFileExists "$INSTDIR\text_assets\text_assets_global.str" 0 invalid_dir
  IfFileExists "$INSTDIR\text_assets\text\D8CBB618.str" 0 invalid_dir
  Return
invalid_dir:
  Abort
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
  IfFileExists "$BackupDir\text_assets\text_assets_global.str" 0 +2
  CopyFiles /SILENT "$BackupDir\text_assets\text_assets_global.str" "$INSTDIR\text_assets\text_assets_global.str"
  IfFileExists "$BackupDir\text_assets\text\D8CBB618.str" 0 +2
  CopyFiles /SILENT "$BackupDir\text_assets\text\D8CBB618.str" "$INSTDIR\text_assets\text\D8CBB618.str"
  !insertmacro RestoreRuntime "ds1k_utf8.dll" "ds1k" "install"
  !insertmacro RestoreRuntime "xinput1_3.dll" "xinput" "install"
  !insertmacro RestoreRuntime "SDL3.dll" "sdl" "install"
  !insertmacro RestoreRuntime "DeadSpaceFixes.ini" "config" "install"
FunctionEnd

Section "한국어 개선 패치" SecMain
  SectionIn RO
  StrCpy $BackupDir "$INSTDIR\DS1K_Backup_v0.1"
  StrCpy $FontSource "$INSTDIR\text_assets\text_assets_global.str"
  StrCpy $TextSource "$INSTDIR\text_assets\text\D8CBB618.str"

  IfFileExists "$BackupDir\text_assets\text_assets_global.str" 0 +2
  StrCpy $FontSource "$BackupDir\text_assets\text_assets_global.str"
  IfFileExists "$BackupDir\text_assets\text\D8CBB618.str" 0 +2
  StrCpy $TextSource "$BackupDir\text_assets\text\D8CBB618.str"

  DetailPrint "Steam 원본 STR를 검증하고 한국어 STR를 생성하는 중..."
  InitPluginsDir
  SetOutPath "$PLUGINSDIR"
  File /oname=deadspace1-kr-v0.1.pat "${PATCH_FILE}"

  vpatch::vpatchfile "$PLUGINSDIR\deadspace1-kr-v0.1.pat" "$FontSource" "$PLUGINSDIR\text_assets_global.str"
  Pop $PatchResult
  StrCpy $0 $PatchResult 2
  StrCmp $0 "OK" font_patch_ok
  Goto patch_error
font_patch_ok:
  IfFileExists "$PLUGINSDIR\text_assets_global.str" 0 patch_error

  vpatch::vpatchfile "$PLUGINSDIR\deadspace1-kr-v0.1.pat" "$TextSource" "$PLUGINSDIR\D8CBB618.str"
  Pop $PatchResult
  StrCpy $0 $PatchResult 2
  StrCmp $0 "OK" text_patch_ok
  Goto patch_error
text_patch_ok:
  IfFileExists "$PLUGINSDIR\D8CBB618.str" 0 patch_error

  DetailPrint "원본 파일을 백업하는 중..."
  CreateDirectory "$BackupDir\text_assets\text"
  CreateDirectory "$BackupDir\runtime"

  IfFileExists "$BackupDir\text_assets\text_assets_global.str" font_backup_done
  ClearErrors
  CopyFiles /SILENT "$INSTDIR\text_assets\text_assets_global.str" "$BackupDir\text_assets\text_assets_global.str"
  IfErrors backup_error
font_backup_done:
  IfFileExists "$BackupDir\text_assets\text\D8CBB618.str" text_backup_done
  ClearErrors
  CopyFiles /SILENT "$INSTDIR\text_assets\text\D8CBB618.str" "$BackupDir\text_assets\text\D8CBB618.str"
  IfErrors backup_error
text_backup_done:

  !insertmacro BackupRuntime "ds1k_utf8.dll" "ds1k"
  !insertmacro BackupRuntime "xinput1_3.dll" "xinput"
  !insertmacro BackupRuntime "SDL3.dll" "sdl"
  !insertmacro BackupRuntime "DeadSpaceFixes.ini" "config"

  DetailPrint "한국어 STR와 런타임 파일을 설치하는 중..."
  ClearErrors
  CopyFiles /SILENT "$PLUGINSDIR\text_assets_global.str" "$INSTDIR\text_assets\text_assets_global.str"
  IfErrors install_error
  ClearErrors
  CopyFiles /SILENT "$PLUGINSDIR\D8CBB618.str" "$INSTDIR\text_assets\text\D8CBB618.str"
  IfErrors install_error

  SetOverwrite on
  SetOutPath "$INSTDIR"
  File /oname=ds1k_utf8.dll "${REPO_ROOT}\dist\ds1k_utf8.dll"
  File /oname=xinput1_3.dll "${REPO_ROOT}\dist\xinput1_3.dll"
  File /oname=SDL3.dll "${REPO_ROOT}\dist\SDL3.dll"

  SetOverwrite off
  File /oname=DeadSpaceFixes.ini "${REPO_ROOT}\dist\DeadSpaceFixes.ini"
  SetOverwrite on

  SetOutPath "$INSTDIR\DS1K_Patch"
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

  WriteUninstaller "$INSTDIR\DS1K_Patch\Uninstall.exe"
  FileOpen $0 "$INSTDIR\DS1K_Patch\installed-version.txt" w
  FileWrite $0 "Dead Space 1 KR ${PRODUCT_VERSION}$\r$\nCommit ${GIT_HASH}$\r$\n"
  FileClose $0

  WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayName" "${PRODUCT_NAME} ${PRODUCT_VERSION}"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "UninstallString" "$\"$INSTDIR\DS1K_Patch\Uninstall.exe$\""
  WriteRegDWORD HKLM "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTALL_KEY}" "NoRepair" 1
  Goto install_done

patch_error:
!ifdef TEST_BUILD
  FileOpen $0 "$INSTDIR\installer-test.log" w
  FileWrite $0 "patch_error: $PatchResult$\r$\nfont_source: $FontSource$\r$\ntext_source: $TextSource$\r$\n"
  FileClose $0
!endif
  MessageBox MB_ICONSTOP|MB_OK "원본 STR 검증 또는 변환에 실패했습니다.$\r$\n$\r$\nSteam판 Dead Space (2008) 1.0.0.222의 깨끗한 원본 파일이 필요합니다. Steam에서 파일 무결성 검사를 한 뒤 다시 실행하십시오.$\r$\n$\r$\n상세 결과: $PatchResult" /SD IDOK
  Abort

backup_error:
!ifdef TEST_BUILD
  FileOpen $0 "$INSTDIR\installer-test.log" w
  FileWrite $0 "backup_error$\r$\n"
  FileClose $0
!endif
  MessageBox MB_ICONSTOP|MB_OK "원본 파일 백업에 실패했습니다. 디스크 공간과 폴더 쓰기 권한을 확인하십시오. 게임 파일은 변경하지 않았습니다." /SD IDOK
  Abort

install_error:
!ifdef TEST_BUILD
  FileOpen $0 "$INSTDIR\installer-test.log" w
  FileWrite $0 "install_error$\r$\n"
  FileClose $0
!endif
  DetailPrint "설치 실패: 백업에서 원본 파일을 복원합니다."
  Call RestoreInstalledFiles
  MessageBox MB_ICONSTOP|MB_OK "파일 설치에 실패하여 원본을 복원했습니다. Dead Space가 실행 중인지 확인한 뒤 다시 시도하십시오." /SD IDOK
  Abort

install_done:
  DetailPrint "설치 완료. 백업 위치: $BackupDir"
SectionEnd

Function un.RestoreInstalledFiles
  StrCpy $BackupDir "$INSTDIR\DS1K_Backup_v0.1"
  IfFileExists "$BackupDir\text_assets\text_assets_global.str" 0 un_no_backup
  IfFileExists "$BackupDir\text_assets\text\D8CBB618.str" 0 un_no_backup
  ClearErrors
  CopyFiles /SILENT "$BackupDir\text_assets\text_assets_global.str" "$INSTDIR\text_assets\text_assets_global.str"
  IfErrors un_restore_error
  ClearErrors
  CopyFiles /SILENT "$BackupDir\text_assets\text\D8CBB618.str" "$INSTDIR\text_assets\text\D8CBB618.str"
  IfErrors un_restore_error
  !insertmacro RestoreRuntime "ds1k_utf8.dll" "ds1k" "uninstall"
  !insertmacro RestoreRuntime "xinput1_3.dll" "xinput" "uninstall"
  !insertmacro RestoreRuntime "SDL3.dll" "sdl" "uninstall"
  !insertmacro RestoreRuntime "DeadSpaceFixes.ini" "config" "uninstall"
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
  DeleteRegKey HKLM "${UNINSTALL_KEY}"
  RMDir /r "$INSTDIR\DS1K_Patch"
  MessageBox MB_ICONINFORMATION|MB_OK "한국어 개선 패치를 제거하고 원본 파일을 복원했습니다.$\r$\n$\r$\n백업 폴더는 안전을 위해 유지합니다:$\r$\n$INSTDIR\DS1K_Backup_v0.1" /SD IDOK
SectionEnd
