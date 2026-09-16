# STR VPatch 데이터

`deadspace1-kr-v0.1.pat`는 Steam판 Dead Space (2008) 1.0.0.222의 두 원본 STR를
한국어 패치 STR로 변환하는 VPatch 데이터다. 원본 또는 완성 STR 자체는 저장소와
설치 파일에 포함하지 않는다.

`manifest.json`에는 지원하는 원본과 생성 결과의 SHA-256이 기록된다. 번역이나 폰트를
수정해 새 STR를 만들었으면 깨끗한 Steam 원본 두 파일을 준비하고 다음 명령으로 패치와
manifest를 함께 갱신한다.

```powershell
$nsis = .\scripts\prepare-nsis.ps1
.\scripts\generate-vpatch.ps1 `
  -NsisRoot $nsis `
  -OriginalTextAssets <clean-text_assets_global.str> `
  -OriginalLocalization <clean-D8CBB618.str>
```

생성 후 반드시 설치 마법사를 깨끗한 게임 폴더 복사본에서 시험하고, 결과 STR의 해시가
`manifest.json`의 `outputs`와 일치하는지 확인한다.
