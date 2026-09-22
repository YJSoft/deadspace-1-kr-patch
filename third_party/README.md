# 제3자 구성 요소

| 구성 요소 | 저장소 포함 범위 | 라이선스 |
| --- | --- | --- |
| DeadSpace2008Fixes | 기준 소스와 DS1K 수정본 | MIT |
| DSOpt | 자막 전체 레이아웃·그리기 배율 설계와 시그니처 참고 | MIT |
| MinHook | DeadSpace2008Fixes에 내장된 C 소스/헤더 | BSD 2-Clause |
| SDL3 3.2.8 | 빌드용 헤더만 포함, LIB/DLL 제외 | zlib |
| NanumBarunGothic | OFL 전문과 `assets/fonts`의 Regular TTF | SIL OFL 1.1 |
| fltk-rs / FLTK | Linux AppImage GUI에 정적 링크 | MIT / LGPL-2.0 + FLTK 예외 |
| AppImage type-2 runtime | Linux AppImage 실행 헤더 | MIT 및 포함 구성 요소별 조건 |

SDL3 링크/런타임 바이너리는 공식 SDL 개발 패키지에서 별도로 준비한다. 빌드 산출물이나
외부 도구 바이너리를 이 디렉터리에 커밋하지 않는다.
