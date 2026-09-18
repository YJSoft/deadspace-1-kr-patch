# STR VPatch 데이터

`deadspace1-kr-v0.2.pat`는 Steam 및 EA App판 Dead Space (2008)의 원본 리소스를
한국어 패치 리소스로 변환하는 VPatch 데이터다. 원본 또는 완성 STR 자체는 저장소와
설치 파일에 포함하지 않는다. Steam판에서는 `12F4D5F8.str`, EA App판에서는 기존
영어 `D8CBB618.str`를 입력으로 받아 패치용 `D8CBB618.str`를 만든다.

`manifest.json`에는 지원하는 원본과 생성 결과의 SHA-256이 기록된다. 번역이나 폰트를
수정해 새 STR를 만들었으면 깨끗한 Steam 및 EA App 원본 파일을 준비하고 다음
명령으로 패치와 manifest를 함께 갱신한다.

```powershell
$nsis = .\scripts\prepare-nsis.ps1
.\scripts\generate-vpatch.ps1 `
  -NsisRoot $nsis `
  -OriginalTextAssets <clean-text_assets_global.str> `
  -OriginalLocalization <clean-12F4D5F8.str> `
  -EaTextAssets <ea-clean-text_assets_global.str> `
  -EaLocalization <ea-clean-D8CBB618.str> `
  -LegacyTextAssets <legacy-clean-text_assets_global.str> `
  -LegacyLocalization <legacy-clean-D8CBB618.str>
```

`Legacy*` 두 인수는 이전 배포 설치판의 백업에서 새 설치판으로 직접 업그레이드할 수
있게 만드는 호환 입력이다. `Ea*`와 `Legacy*`는 각각 두 파일을 한 쌍으로 생략하거나
지정해야 한다. 실제 순정 입력의 SHA-256은 필수로 확인하며, `manifest.json`에 지원
입력을 모두 기록한다.

생성 후 반드시 설치 마법사를 깨끗한 게임 폴더 복사본에서 시험하고, 결과 STR의 해시가
`manifest.json`의 `outputs`와 일치하는지 확인한다.
