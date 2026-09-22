# Linux / Steam Deck 설치 안내

이 설치기는 Linux에서 Steam/Proton으로 실행하는 Dead Space (2008)에 한국어 개선
패치 0.3을 설치한다. Ubuntu 26.04와 Steam Deck 데스크톱 모드에서 같은 AppImage를
사용할 수 있다.

## 설치

1. Steam에서 Dead Space를 설치하고 한 번도 실행하지 않았더라도 게임 파일이 완전히
   내려받아졌는지 확인한다.
2. 내려받은 `DeadSpace1-KR-0.3-x86_64.AppImage`에 실행 권한을 준다.

   ```bash
   chmod +x DeadSpace1-KR-0.3-x86_64.AppImage
   ```

3. 파일을 더블클릭한다. 열리지 않으면 터미널에서 다음처럼 실행한다.

   ```bash
   ./DeadSpace1-KR-0.3-x86_64.AppImage
   ```

4. 자동으로 표시된 Dead Space 폴더를 확인하고 `설치 / 업데이트`를 누른다. 자동
   탐색에 실패하면 `찾아보기`에서 `Dead Space.exe`가 들어 있는 폴더를 선택한다.
5. 설치가 끝나면 설치기 아래쪽의 `옵션 복사`를 누른다.
6. Steam의 `라이브러리 → Dead Space → 속성 → 일반 → 실행 옵션`에 아래 내용을
   붙여넣는다.

   ```text
   WINEDLLOVERRIDES="xinput1_3=n,b" %command%
   ```

이 실행 옵션은 Proton 내장 XInput DLL보다 패치가 설치한 `xinput1_3.dll`을 먼저
불러오게 한다. 옵션이 빠지면 나눔바른고딕은 적용되어도 UTF-8 훅이 로드되지 않아
한글이 깨져 보일 수 있다.

## 업데이트와 제거

- 새 AppImage를 실행해 같은 폴더에 `설치 / 업데이트`를 누르면 `DS1K_Backup`의
  원본을 복원한 뒤 새 패치를 적용한다. `DeadSpaceFixes.ini` 사용자 설정은 유지한다.
- `원본 복원 / 패치 제거`를 누르면 원본 STR와 기존 런타임 파일을 복원한다.
- 원본 백업은 안전을 위해 제거 후에도 `DS1K_Backup`에 유지한다.
- 백업이 손상되었으면 게임 파일을 변경하지 않고 중단한다. Steam의 게임 파일 무결성
  검사를 실행한 뒤 다시 설치한다.

## AppImage가 바로 실행되지 않을 때

일부 배포판은 FUSE 구성이 없어 AppImage를 직접 마운트하지 못할 수 있다. 이 경우
AppImage 자체의 추출 실행 기능을 사용할 수 있다.

```bash
./DeadSpace1-KR-0.3-x86_64.AppImage --appimage-extract-and-run
```

게임과 AppImage를 Wine/Proton 안에서 실행하지 않는다. 설치기는 Linux 프로그램이며,
게임 폴더의 Windows용 패치 DLL을 배치한 뒤 Steam이 Proton으로 이를 로드한다.
