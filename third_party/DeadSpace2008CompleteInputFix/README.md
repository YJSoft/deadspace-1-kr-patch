# CompleteInputFix 통합 범위

출처: https://github.com/RealRama2120/DeadSpace2008CompleteInputFix

기준 커밋: `ae3bc1508aeefe45fcdc8b03a45a0b68a6e543bc` (MIT, Rama2120)

원본 `src/payload`의 controller/mouse transform, mouse hook, logging 및 필요한
config 헤더와 두 transform 단위 검사를 가져왔다. 해당 파일은 원본 그대로 유지한다.
독립 `version.dll` 로더와 XInput IAT 훅, 별도 설정 파서는 가져오지 않았다.

통합부는 DeadSpace2008Fixes의 `Features/Input/InputFix.cpp`, `SdlGamepad.cpp`에
있다. 기존 메인 `xinput1_3.dll`에 함께 링크되므로 다른 프록시 DLL을 추가로 설치하지
않는다. 설정은 `DeadSpaceFixes.ini`의 `[Fixes]`에서 관리한다.

- `FixControllerDeadzone=1`: 오른쪽 스틱 물리 데드존 11%, 게임 내부 데드존
  `8689/32767`의 역보정. SDL3와 실제 XInput 전달 경로에 각각 한 번만 적용한다.
- `FixRawMouseCamera=1`: 게임이 수집한 원시 마우스 이동량으로 일반/무중력
  카메라 입력을 보정한다. 게임 감도·반전 설정을 따르며 메뉴는 변경하지 않는다.
- 마우스 설치는 UTF-8 및 기존 수정 모듈 적용 뒤 별도 스레드에서 최대 60초간
  기다린다. 실행 코드의 일곱 패턴, 호출 대상, 설정 주소가 모두 유일하고 정확히
  일치할 때만 원본의 트랜잭션 방식으로 훅을 설치한다. 불일치 시 원래 입력을 유지한다.
- 설치 로그: 게임 폴더의 `DeadSpaceCompleteInputFix.log`.

게임을 실행하지 않는 수학적 변환 검사는 `scripts/test-input.cmd`로 실행한다.
실제 Steam/EA/Proton 입력과 제보 화면 검수는 `docs/TESTING.md`를 따른다.
