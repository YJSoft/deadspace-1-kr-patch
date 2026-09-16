# Dead Space 1 한국어 개선 패치

Steam판 **Dead Space (2008) 1.0.0.222**의 실행 파일을 교체하지 않고 한국어 UTF-8
표시, ID 기반 번역, 통합 글꼴, 자동 자막 배율 및 여러 원작 버그 수정을 적용하는
프로젝트다.

이 저장소는 소스 공개본이다. 빌드된 DLL, 게임 리소스 STR, 배포 ZIP, 원본 게임 파일과
다른 언어 패치 파일은 포함하지 않는다.

## 현재 상태

- 원본 실행 코드의 두 문자열 처리 루프를 시그니처로 찾고 UTF-8 1~3바이트/BMP
  코드포인트를 처리한다.
- 예상 바이트가 모두 일치할 때만 훅을 기록한다. 지원하지 않는 실행 파일에서는 코드
  변경을 중단하고 `DS1K/DS1K.log`에 원인을 남긴다.
- 번역은 `translations/dead_space_ko.csv`의 문자열 ID를 기준으로 관리한다.
- 번역 가능한 4,550개 ID가 CSV에 들어 있으며, 유효하지 않은 UTF-8·한 글자·의미
  없는 기호뿐인 495개 항목은 원본 바이트를 보존한다.
- 세 로컬라이제이션 UI 글꼴의 한글·영문·숫자·기호를 나눔바른고딕 Regular로
  통일한다.
- 720p를 기준으로 실제 게임 창 높이에 따라 자막 영역과 크기를 자동 조절한다.
- Alt+Tab 복귀 시 보더리스 창의 마우스 고정과 시스템 커서 숨김을 복원한다.
- [DeadSpace2008Fixes](https://github.com/seamusduncmcgrath/DeadSpace2008Fixes)의
  수정 기능을 통합한다.

중국어 패치는 확장 FFN 글리프 테이블의 구조를 확인하기 위한 역공학 기준으로만
사용했다. 중국어 실행 파일과 리소스는 이 저장소에 포함하지 않는다.

## 저장소 구조

| 경로 | 내용 |
| --- | --- |
| `src/` | 독립 UTF-8 사이드카 DLL과 XInput 전달 코드 |
| `third_party/DeadSpace2008Fixes/` | MIT 기반 메인 XInput 프록시와 DS1K 수정 사항 |
| `tools/` | 번역 CSV 및 LCH2/FFN/TG4D 자산 생성기 |
| `translations/` | 현재 번역과 초기 가져오기 스냅샷 |
| `assets/fonts/` | 글꼴 자산 생성에 사용하는 나눔바른고딕 원본 입력 파일 |
| `config/` | `DeadSpaceFixes.ini` 설정 예제 |
| `packaging/` | 향후 배포 패키지용 설치·제거 스크립트 원본 |
| `docs/` | 빌드, 구조, 유지보수, 테스트 및 설치 설명 |

## 문서

- [빌드와 자산 생성](docs/BUILD.md)
- [구조와 역공학 메모](docs/ARCHITECTURE.md)
- [유지보수 및 릴리스 절차](docs/MAINTENANCE.md)
- [회귀 테스트 체크리스트](docs/TESTING.md)
- [번역 편집 안내](translations/README.md)
- [테스트 배포판 설치·설정 안내](docs/INSTALL_KO.txt)
- [라이선스 경계](docs/LICENSING.md)

## 빠른 시작

Visual Studio 2022의 C++ 데스크톱 도구와 Windows SDK를 설치한 뒤 SDL3 x86 개발
파일을 준비한다. 자세한 배치 위치는 `docs/BUILD.md`를 참고한다.

```bat
build.cmd
build-assets.cmd
```

`build.cmd`는 `ds1k_utf8.dll`, DeadSpaceFixes 기반 `xinput1_3.dll`과 SDL3 런타임을
`dist/`에 모은다. `dist/`는 빌드 산출물이므로 Git에서 제외된다.

GitHub Actions도 push된 모든 커밋과 pull request를 Windows 환경에서 빌드하고
`dead-space-kr-dist-<commit>` artifact를 업로드한다. 이 artifact에는 게임 원본에서
파생되는 STR가 포함되지 않으므로 테스트 설치에는 로컬에서 생성한 STR가 별도로 필요하다.

폰트와 번역 STR 생성에는 소유 중인 원본 게임 리소스, 확장 FFN 테이블을 가진 작업용
폰트 리소스, Gibbed.Visceral 계열 unpack/pack 도구와 `squish64.dll`이 별도로
필요하다. 이들은 저작권 또는 바이너리 산출물 문제로 저장소에 포함하지 않는다.

## 번역 참여

CSV의 `id`와 `english`는 유지하고 `translation`만 수정한다. CSV는 UTF-8 BOM 형식을
사용한다. 번역 PR에서는 가능하면 문자열 ID, 등장 장면, 전후 문맥과 스크린샷을 함께
남긴다. 자세한 규칙은 `translations/README.md`와 `CONTRIBUTING.md`를 참고한다.

## 지원 범위

- Steam판 Dead Space (2008) `1.0.0.222`
- 32비트 Windows 실행 파일
- UTF-8 1~3바이트와 BMP(`U+0000`~`U+FFFF`)

다른 실행 파일 버전이나 크랙/수정 EXE는 지원하지 않는다. 시그니처를 찾더라도 예상
바이트 검증을 우회해서는 안 된다.

## 출처와 라이선스

DeadSpace2008Fixes 수정 코드는 upstream revision
`ec7ae5cdb799af5494e483cb3357b897d8fe9fe1`을 기준으로 한다. MinHook, SDL3,
나눔바른고딕을 포함한 제3자 저작물은 각각의 라이선스를 따른다.

프로젝트 고유 코드와 번역 데이터에 적용할 저장소 전체 라이선스는 아직 별도로
선언되지 않았다. 제3자 라이선스가 프로젝트 전체에 자동으로 적용되는 것은 아니다.
외부 재사용 전에는 [라이선스 문서](docs/LICENSING.md)를 확인해야 한다.
