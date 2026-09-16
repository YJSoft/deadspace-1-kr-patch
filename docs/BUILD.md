# 빌드와 자산 생성

## 1. 필요한 도구

- Windows 10/11 x64
- Visual Studio 2022의 **Desktop development with C++** 워크로드
- MSVC x86 도구와 Windows SDK
- .NET Framework C# 컴파일러와 `System.Drawing`
- SDL 3.2.8 x86 개발 패키지
- 폰트 DXT5 압축용 `squish64.dll`
- Visceral STR를 풀고 다시 묶을 수 있는 Gibbed.Visceral 계열 도구
- 합법적으로 설치된 Steam판 Dead Space (2008) 1.0.0.222
- NSIS 3.12 (로컬 설치 파일 빌드 또는 VPatch 재생성 시)

저장소에는 게임 파일, 중국어 패치 파일, SDL 바이너리, `squish64.dll`, Gibbed 도구를
포함하지 않는다.

## 2. SDL3 배치

SDL3 헤더는 소스 검토를 위해 포함되어 있지만 링크·런타임 바이너리는 제외되어 있다.
SDL 3.2.8 x86 개발 패키지에서 다음 두 파일을 배치한다.

```text
third_party/DeadSpace2008Fixes/DeadSpaceFixes/lib/SDL3/x86/SDL3.lib
third_party/DeadSpace2008Fixes/DeadSpaceFixes/lib/SDL3/x86/SDL3.dll
```

다른 SDL 버전으로 올릴 때는 헤더도 같은 버전으로 함께 갱신하고 컨트롤러 회귀 테스트를
수행한다.

## 3. DLL 빌드

저장소 루트의 Developer Command Prompt 또는 일반 명령 프롬프트에서 실행한다.

```bat
build.cmd
```

스크립트는 다음을 수행한다.

1. `src/dllmain.cpp`를 Win32 `ds1k_utf8.dll`로 빌드한다.
2. 수정된 DeadSpace2008Fixes를 Win32 `xinput1_3.dll`로 빌드한다.
3. SDL3 런타임을 함께 `dist/`로 복사한다.

중간 파일은 `%TEMP%\deadspace-1-kr-patch-native`와 `%TEMP%\ds1k-fixes-build`에 생성된다.
최종 `dist/`도 Git 추적 대상이 아니다.

배치 파일은 Visual Studio Installer의 `vswhere.exe`로 최신 설치를 찾으므로 Community,
Professional, Enterprise와 기본 경로가 아닌 설치를 모두 지원한다.

## 4. C# 생성기 빌드

```bat
build-assets.cmd
```

다음 파일이 `%TEMP%\deadspace-1-kr-patch-assets`에 생성된다.

- `BuildPocAssets.exe`: 번역 LCH2와 세 UI 폰트 아틀라스 생성
- `GenerateTranslationCsv.exe`: 원본 LH2와 과거 `Launcher.xml`에서 CSV 생성

`BuildPocAssets.exe`와 같은 폴더 또는 DLL 검색 경로에 `squish64.dll`을 둔다.

## 5. 번역/폰트 자산 생성

작업 전에 원본 STR를 별도 폴더에 풀어 둔다. 첫 번째 폰트 디렉터리는 충분한 레코드
용량을 가진 확장 FFN 테이블 작업본이며 **도구가 제자리에서 수정하므로 복사본**을
사용한다. 두 번째 디렉터리는 Steam 원본 글자 목록을 읽는 기준본이다.

필수 상대 경로는 다음과 같다.

```text
FFN/0105_russellsquare32.inf
FFN/0106_briemakademistdsemibold32.inf
FFN/0108_eurostileltstdbold32.inf
tg4d/0013_russellsquare32.tg4d
tg4d/0001_briemakademistdsemibold32.tg4d
tg4d/0007_eurostileltstdbold32.tg4d
```

실행 형식:

```bat
%TEMP%\deadspace-1-kr-patch-assets\BuildPocAssets.exe ^
  translations\dead_space_ko.csv ^
  <writable-extended-font-unpacked-dir> ^
  <steam-font-unpacked-dir> ^
  assets\fonts\NanumBarunGothic.ttf ^
  <steam-original-english.lh2> ^
  <output-korean.lh2>
```

생성기는 다음 검증을 실패 조건으로 처리한다.

- CSV ID 중복, 누락, 빈 번역
- 원본 LCH2에 없는 CSV ID
- 잘못되거나 부족한 FFN 글리프 테이블
- 32×32 셀 밖으로 나가는 글리프
- 예상과 다른 TG4D 밉 체인 크기

작업 폰트 디렉터리의 INF/TG4D와 출력 LH2를 원래 리소스 트리 위치에 넣고 외부 STR
도구로 다시 묶는다. 현재 게임에 필요한 결과 파일은 다음 두 개다.

```text
text_assets/text_assets_global.str
text_assets/text/D8CBB618.str
```

STR 포맷과 게임 원본은 이 저장소의 소유물이 아니므로 결과 파일을 커밋하지 않는다.
패킹 후에는 다시 언팩하여 수정한 INF/TG4D/LH2의 해시가 입력과 일치하는지 확인한다.

## 6. 과거 패치에서 CSV 재생성

일상적인 번역 수정에는 사용하지 않는다. 현재 CSV를 유지하는 것이 우선이다.

```bat
generate-translations.cmd <original-lh2> <legacy-Launcher.xml> <output.csv>
```

전각 공백과 탭을 ASCII 공백으로 정규화하며, 의미 없는 항목을 제외한다. 재생성 결과로
현재 검수 CSV를 무조건 덮어쓰지 말고 ID별 diff를 검토한다.

## 7. 설치 마법사와 VPatch

배포 설치 파일은 완성된 STR를 내장하지 않는다. `packaging/patches`의 VPatch 차등
데이터를 사용해 설치 대상의 깨끗한 Steam 원본 STR에서 한국어 STR를 생성한다.

번역이나 글꼴이 바뀌어 새 STR를 만들었으면, 지원 원본 2개와 새 `dist` STR 2개를
지정해 차등 데이터와 매니페스트를 갱신한다.

```powershell
$nsisRoot = .\scripts\prepare-nsis.ps1
.\scripts\generate-vpatch.ps1 `
  -NsisRoot $nsisRoot `
  -OriginalTextAssets <원본-text_assets_global.str> `
  -OriginalLocalization <원본-D8CBB618.str>
```

스크립트는 알려진 Steam 원본 SHA-256을 확인한 뒤 작업한다. 생성된
`deadspace1-kr-v0.1.pat`와 `manifest.json`을 함께 커밋한다. 원본 또는 완성 STR는
커밋하지 않는다.

DLL과 배포 파일을 `dist`에 준비한 뒤 설치 마법사를 로컬에서 빌드할 수 있다.

```powershell
.\scripts\stage-dist.ps1
$nsisRoot = .\scripts\prepare-nsis.ps1
.\scripts\build-installer.ps1 -NsisRoot $nsisRoot
```

출력 파일명은 `DeadSpace1-KR-0.1.exe`다. 새 설치기는 깨끗한 임시 게임 폴더에서
최초 설치, 기존판 업그레이드, 설정 보존, 백업 손실 시 무변경 중단, Steam 원본 복원
후 백업 재구성, 제거 및 원본 해시 복원을 모두 확인한다.

## 8. GitHub Actions 빌드

`.github/workflows/build-dist.yml`은 저장소에 push된 모든 커밋과 pull request에서
Windows Server 2022 빌드를 수행한다. SDL 3.2.8 공식 Visual C++ 개발 패키지는 고정된
URL과 SHA-256으로 검증한 뒤 사용한다.

CI는 고정 URL과 SHA-256으로 NSIS 3.12도 검증해 준비한 뒤 설치 마법사를 만든다.
결과는 `actions/upload-artifact@v7`의 단일 파일 모드(`archive: false`)로 업로드하므로
artifact 자체가 ZIP이 아닌 다음 실행 파일 하나다.

```text
DeadSpace1-KR-0.1.exe
```

설치 파일에는 DLL, 기본 설정, 문서, 라이선스와 VPatch 차등 데이터가 들어간다. 게임
원본이나 완성된 STR는 포함하지 않으며, 사용자의 지원되는 Steam 원본 STR가 있어야
설치를 완료할 수 있다. `main` 브랜치 push 빌드가 성공하면 CI는 `nightly`
프리릴리스의 `DeadSpace1-KR-0.1.exe` 자산도 같은 파일로 교체한다. README의 고정
주소는 이 릴리스 자산을 가리킨다. nightly.link는 현재 `archive: false` 비압축
artifact를 지원하지 않는다.
