# 유지보수와 릴리스 절차

## 번역 갱신

1. `translations/dead_space_ko.csv`의 `translation` 열만 수정한다.
2. CSV 파서와 원본 LCH2 검증을 실행한다.
3. 모든 번역 문자로 폰트 아틀라스를 다시 생성한다.
4. STR를 재패킹한 뒤 다시 풀어 INF/TG4D/LH2 해시를 비교한다.
5. `scripts/generate-vpatch.ps1`로 배포용 VPatch와 매니페스트를 갱신한다.
6. 새 번역이 표시되는 실제 장면과 긴 자막을 확인한다.

`dead_space_ko_original.csv`는 과거 한글패치에서 처음 가져온 상태를 보존하는 비교용
스냅샷이다. 현재 번역의 기준은 항상 `dead_space_ko.csv`다.

## 코드 갱신

- 지원 게임 빌드를 바꿀 때는 EXE 해시, 버전, 새 시그니처와 예상 바이트를 함께
  기록한다.
- DeadSpace2008Fixes upstream을 갱신할 때는 현재 기준 revision과 DS1K 수정 파일을
  먼저 diff한다.
- SDL을 갱신할 때는 헤더·LIB·DLL 버전을 맞추고 XInput/PlayStation/Switch 입력을
  모두 확인한다.
- 나눔바른고딕을 교체하거나 변형하지 않는다. OFL Reserved Font Name 조건을 확인한다.

## 테스트 배포 체크리스트

1. Release Win32 DLL 두 개와 자산 생성기를 깨끗한 환경에서 빌드한다.
2. 지원 원본과 최종 STR로 VPatch를 재생성하고 매니페스트 해시를 검토한다.
3. NSIS 설치 마법사를 빌드하고 원본 Steam 파일을 복사한 격리 폴더에서 설치한다.
4. 같은 폴더에 업그레이드하여 백업 원본 복원 후 재패치, 사용자 설정 유지와 새
   `BuildCommit` 기록을 확인한다.
5. 원본 백업 일부를 제거한 채 업그레이드하면 게임 파일 변경 없이 중단되는지 확인한다.
   그 상태에서 Steam 원본 STR를 복원해 재실행하고 백업 재구성과 설치를 확인한다.
6. 제거 후 원본 STR와 런타임 파일이 정확히 복원되는지 해시로 확인한다.
7. 잘못된 STR에서 설치가 변경 없이 중단되는지 확인한다.
8. 실제 게임에서 `docs/TESTING.md`의 기본/회귀 항목을 실행한다.
9. 다음 라이선스 전문을 설치 파일에 넣는다.
   - DeadSpace2008Fixes MIT
   - MinHook BSD 2-Clause
   - SDL zlib
   - NanumBarunGothic SIL OFL 1.1
   - NSIS 라이선스
   - VPatch zlib
10. DLL과 완성 STR는 Git 소스 브랜치에 커밋하지 않는다. 배포는 CI가 생성한
   `DeadSpace1-KR-0.1.exe`를 사용한다.

## 장애 진단 자료

제보에는 다음을 요청한다.

- 정확한 재현 단계와 난이도/세이브 상태
- 게임 해상도, 화면비, 전체 화면 여부, 모니터 수
- `DeadSpaceFixes.ini`
- `DS1K/DS1K.log`
- 함께 사용하는 모드와 오버레이
- 글꼴/자막 문제의 경우 문자열 ID와 원본 크기 스크린샷

`Application load error 5:0000065434`는 패치 훅 오류가 아니라 Steam DRM 실행 경로
문제일 수 있다. 게임 EXE를 직접 더블클릭하지 말고 Steam 라이브러리에서 실행한다.
