# develop 통합 검토 · #15/#16 시점 · 2026-10-28 (서울)

> #18/#19 및 수어 알림 후속 보완의 최신 기록은 [final-submission-20261028](final-submission-20261028.md)을 따른다.

사용자가 develop 최종 통합과 main 병합 직전 준비를 지시했다. main 병합·기존 PR 임의
닫기/삭제·장치 교체는 이번 범위가 아니다. 시작 develop은
`a9dfd5a3002c0c8d69365617d8f15c0951d26a00`, main은
`40551d781e19a8e7974be47334ef4132d1ed4d1d`다.

원래 `/workspace/safehub-integration`은 clean으로 보존하고 별도 worktree에서 작업했다.
전체 이력과 로그는 `/workspace/.cloud-setup/final-develop-20261028/`에 보관했다.
SDK/환경을 처음부터 재생성하지 않았다.

## 포함 관계

| 소스 | 처리 |
|---|---|
| #11 `9a6d704` | develop merge `a9dfd5a`에 포함. #10(#8/#7 포함)·#9·#6 선택 안정화 유지 |
| #14 `4958c1565f540d3fe33aec1f74eb22c99fc90076` | 장치 후속 소스 검토·merge: 긴급 음성, YAMNet/STT tap, 낙상 정책, Pi4 추적/정지 지지 손/관절 표시 |
| 닫힌 #12 `4e4d0d1`, #13 `4f603c7` | 닫힌 PR은 변경하지 않고 보존된 브랜치 이력 통합. 도움 판정/문구와 두 항목 UI 유지 |

#14와 #12의 도움 음성 처리가 충돌했다. 공유 도움 수어 판정·문구는 유지하며 #14의 내장 긴급
음성이 사건의 오디오를 소유하도록 했다. 일반 온라인 TTS가 겹치지 않게 generation/중단 정책을
유지한다. 도움 중 괜찮다 수어로 닫는 #14 처리도 유지한다.
UI는 원래 버건디/아이보리 배치이며 도움 요청 CTA와 카메라 바로 아래 큰 결과를 유지한다.
제품 Dart 41개 모두 main에서 연결되고 누락 로컬 import/선언 asset은 없다. 옛 UI·생성형
서버는 복구하지 않았다. 필수 회귀 참조·diagnostics·라이선스는 보존한다.

## 추가 보완

- 이전 Controller의 runtime module import가 남으면 새 CSI data-dir 대신 삭제된 경로에 설정을
  쓰던 문제를 수정하고 재생성 회귀를 추가했다. vendored baseline 파일은 변경하지 않았다.
  제품 실행은 기존대로 Controller 하나를 사용한다.
- Linux의 파일 재생 경로와 byte-source 검사 두 개가 충돌해 검사 옵션을 명시했다.
  기존 실제 파일 생성/삭제 회귀는 유지했다.
- 긴급 음성으로 남던 FHD 도움 화면 검사 타이머는 괜찮아요로 닫기와 비동기 정리 검사로 해결했다.
- 미설치 제출 후보의 버전은 pubspec 1.6.0+1 / manifest 1.6.0으로 일치시켰다.
- CI는 develop/main push, YAMNet/shared PCM/낙상 정책, 기존 조건부 OpenCV 회귀 네 개를
  추가 검사한다. ORT 공개 헤더는 commit/hash를 고정해 임시 폴더에만 받으며 LG SDK/모델은 포함하지 않는다.
- 장치 inventory 도구는 해시/경로만 읽는다. 비교는 일치·미일치·바이너리 출처 미확인을 구별하고
  부분 출력을 거절한다. 장치 전체가 같다고 자동 선언하거나 파일을 삭제하지 않는다.

## 검증

| 검사 | 결과·범위 |
|---|---|
| Flutter 전체 | 289 pass / 0 fail / 1 실제 fastText opt-in skip. 초기 286 pass/3 fail 후 위 검사 보완을 적용해 재검사 |
| 분석 | error 0 / warning 0 / info 106. `--no-fatal-infos` 통과; strict 기본 명령의 info 실패와 구분 |
| 제품 web release | 성공. APP_LOCAL_PREVIEW=true / SAFEHUB_DEVELOPER_TOOLS=false. 장비 I/O 미실행 |
| C++ 호스트 | 24/24. OpenCV 4.9 core/imgproc + ORT 1.24.4 공개 헤더. scripted geometry/정지 지지 손/관절 회귀, 실제 ONNX 정확도 아님 |
| CSI 전체 | 65/65. 초기 64개 중 저장 경로 오류 1건, 수정·회귀 추가 후 통과. 실제 장치 낙상 검출 아님 |
| YAMNet/PCM/tap/STT 호환 | 18/18. fake interpreter/recognizer·정책 입력, 실제 음향 정확도 아님 |
| 나머지 계약/도구 | 문맥 9, TTS 8, Uno 15, vision Python 22, 부팅 stub 4, host 준비 6, Windows 도구 14, tools 8 통과. 허브 14개 assertion 스크립트 통과 |

빌드 중 OpenCV 라이브러리가 완성되기 전에 링크를 시작해 geometry 네 개가 처음 미실행됐다.
외부 의존성 빌드 완료 후 24/24를 확인했다. 이전 미실행을 성공으로 세지 않았다.
Windows 준비 검사의 옛 버전 고정값도 새 후보와 충돌해 실제 canonical 버전을 보존하는 검사로 바꾸고 14/14를 확인했다.
#14 원본 GitHub Flutter job은 실패했다. 이번 통합의 수정 후 결과와 구분한다.
SDK·산출물·개인 설정·인증정보·백업을 커밋하지 않는다.

## 현재 장치와의 일치는 미확인

클라우드에서 Pi4 사설망 SSH에 접속하지 못했다. #14 문서와 이전 사용자 보고를 대조한 것이며
현재 장치 직접 확인 결과로 쓰지 않는다.

- 1.2.0은 과거 사용자 확인, 1.4.0은 #10 작성자 설치 보고, 1.5.7은 #14 후속 문서의 설치 보고다.
  1.6.0은 이번 소스 후보일 뿐 설치 보고가 아니다.
- Pi4 원래 ELF `5b2f…55499`, #9 별도 후보 `5c14…775c`, #14 초기 PR11 배포 `5cd818…0d3b7`을
  구분한다. 최종 관절 추적 release ELF 해시는 외부 `status.json`에만 기록돼 현재 저장소에서 미확보다.
- #14의 쓰러지다 ID15/paired38 한 사례 성공과 다른 점등/소등 실패를 함께 유지한다. 인식률 개선
  완료로 판단하지 않는다. 현재 모델·active reference·wrapper 대조가 필요하다.
- 지정 시연 사이렌/벨의 성공은 #14 작성자 보고이며 다른 소리·거리·소음 일반화는 미검증이다.
  모델/선택 reference는 외부 자료다. 저장소 clone만으로 실제 모델이 준비되지 않는다.
- #14 인수인계 당시 Pi5에 낙상 라벨 CSI 모델이 없었다. 실제 자동 CSI 낙상 검출은 미실행이다.
- Uno 최종 스케치/펌웨어·재부팅·MQTT 복구·마이크→UI→장치·물리 모터/진동/LED 시험은 이번
  통합에서 직접 확인하지 않았다. 작성자 관찰을 이번 통합본의 실기 통과로 바꾸지 않는다.

보관본은 미확인/미확보로 유지하며 없다고 단정하지 않는다.
장치 대조 명령·제출 절차는 [SUBMISSION](../SUBMISSION.md)을 따른다.

## main 준비 중 발견한 web 실행 보완

PR #15의 3개 CI job을 통과한 뒤 develop merge `e05d5e9`의 tree가 검증 후보와 같음을 확인했다.
추가 실제 Chromium 실행에서는 #14의 AudioService 생성자가 브라우저에서 Platform을 읽어
`Unsupported operation: Platform._operatingSystem`으로 화면이 열리지 않았다. 컴파일 성공을
실행 성공으로 취급하지 않고 web에서는 native 파일/OS 경로를 건너뛰도록 수정했다.

`tool/web_preview_smoke_test.dart`는 일회성 web host에서 Chrome으로 실제 앱 진입→홈→도움 요청→
괜찮아요 복귀를 검사한다. 일반 호스트 289개와 별도 검사이며 실제 장치 연결 시험이 아니다.
CI도 web 빌드 뒤 이 Chrome 검사를 실행한다. Linux/ATLAS 경로는 기존 조건을 유지하며 관련
오디오/홈 18개 회귀와 분석을 추가 확인했다. 실제 Chrome smoke 1/1 통과를 확인했다.
