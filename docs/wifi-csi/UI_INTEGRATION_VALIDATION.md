# SafeHub 통합 검증

검증 기준일: 2026-10-04 (Asia/Seoul)

## 2026-10-05 소스 게시 전 재검사

- 최신 소스를 새 호스트 테스트 폴더로 복사해 Flutter 테스트 162개를 통과했다.
- Windows Python CSI 테스트 52개, ATLAS 녹음 어댑터의 모의 프로세스 테스트 2개를 통과했다.
- 로컬 STT Python 소스 2개의 구문 검사를 통과했다. 이 검사는 음성 정확도 시험이 아니다.
- Flutter 정적 검사에서 미사용 import를 제거했다. 오류·경고와 별개로 스타일·deprecated API 안내가 남아 있어 `--no-fatal-infos`로 검사한다.
- 게시 파일에서 토큰·개인 키·비밀번호 대입 패턴을 검사했다. 개인 기록·모델·음성,
  Home Assistant 계정 설정과 비공개 ATLAS 자료는 포함하지 않았다.

아래 배포 패키지 검사는 이전 Windows 릴리스를 대상으로 한 결과다. 이번 게시로
그 ZIP이 갱신되지는 않는다. 실기기 결과와 남은 한계는 [ATLAS 검증](ATLAS_VALIDATION.md),
로컬 음성 모델과 측정 조건은 [STT 문서](../../SW/local_stt/README.md)를 참고한다.

## 구성과 범위

- UI 기준: 팀 `feature/SW`, commit `110a09e3063d629bc54676d157d940c347ebd1a5`
- CSI 기준: WifiSensing2-src의 실행 소스 29개. 복사 당시 해시는 `runtime/LOCAL_SOURCE_MANIFEST.json`, 변경 해시는 `LOCAL_MODIFICATIONS.json`, 입력 변환 원본은 `reference/soom_engine.py`에 보존한다.
- 환경: Windows x64, Python 3.12, torch 2.7.1+cpu, NumPy 2.2.6, Flutter 3.29.3 / Dart 3.7.2
- 역할: PC는 모델 학습, Pi는 수집·전처리·추론을 담당한다. 기존 MQTT Topic/JSON과 CSI 전처리·모델 입력 규격을 유지한다.
- 제출: 개인 fork의 `feature/wifi-sensing-ui` → 팀 `develop` 대상 Draft PR. 기존 WifiSensing2.0 실행본·측정 기록·모델은 별도로 보존한다.
- 출처와 라이선스: [런타임 출처](../../SW/wifi_sensing/runtime/NOTICE.md), [MIT 라이선스](../../SW/wifi_sensing/runtime/LICENSE), [제3자 고지](../../SW/wifi_sensing/runtime/THIRD_PARTY_NOTICES.txt)

## 소프트웨어 검사

| 검사 | 결과 | 확인 범위 |
| --- | --- | --- |
| Python 전체 | 44개 통과 | 소스 무결성, 입력·전처리 동등성, 수집·기록 관리, 선택 학습, 모델 ZIP, PC/NumPy 추론, 연결 공백·재연결·경합 처리 |
| Flutter 전체 | 135개 통과 | 연결 설정, MQTT 수명, 카메라 수신, 녹음 경합, CSI 화면과 API 요청, 작은 화면 레이아웃 |
| 체험 모드 홈 | 3개 통과 | 체험 설정과 홈 수명 관리 |
| 내장 Python | 44개 통과 | 전달본의 의존성·실행 경로와 동일 소프트웨어 검사 |
| 패키지 준비 | 4개 통과 | 의존성 수집, 제외 규칙·필수 파일, 긴 경로 사전 검사, 로컬 CSI 포트 일치 |
| Windows 오디오 패치 준비 | 7개 통과 | 원본·수정본·라이선스 해시, 패치 적용 및 덮어쓰기 방지 |
| C# 런처 설정 | 통과 | 상대·한글·공백 경로, 준비 시간, 잘못된 옵션 거부, UTF-8·격리 인수 |

Python 검사에는 합성 기록의 100 epoch CNN 학습, 선택한 기록 ID와 측정 회차별 데이터 분리, 표시 신호와 학습 입력의 동등성, PC/NumPy 추론 점수 오차 `1e-5` 이내 확인이 포함된다. Pi 모드 학습과 모의·실측 모델/기록 혼합을 거부한다. 모델 ZIP은 출처·MIT 라이선스·입력 변환 원본·변경 명세를 포함하며, 내보내기 실패 시 기존 파일을 유지한다.

HTTP 검사는 실제 로컬 서비스 프로세스로 수행했다. 실제 모드의 모의 CSI 요청은 HTTP 400으로 거부하며 브라우저 Origin 변경 요청도 차단한다. 실시간 전처리, 준비·수집·저장, 연결 해제 시 파형·판단 제거를 검사했다. USB 수신 경로는 장치 호출을 대체해 검사했으며 실물 검증에 포함하지 않는다.

Flutter 호스트 검사는 ATLAS 전용 오디오 플러그인 두 개를 테스트 복사본에서만 제외했다. 저장소의 production `pubspec`은 유지한다. 추가 UI의 정적 검사에는 오류·경고가 없고, 전체 UI의 기존 deprecated API 안내 8건은 남아 있다. 실제 글꼴과 아이콘으로 화면을 렌더링했으며 1280×720, 600×800 및 홈·의사소통 화면의 1024×600, 800×480 배치를 검사했다.

근거: [Python 검사](integration-validation/python-tests.log), [Flutter 검사](integration-validation/flutter-tests.log), [HTTP 프로세스 검사](integration-validation/http-smoke.json), [내장 Python 검사](integration-validation/portable-python-tests.txt), [합성 입력 화면](integration-validation/wifi-panel-synthetic.png)

## 실제 모드와 연결 처리

주소가 비어 있으면 홈을 표시하고 MQTT·카메라·재난 조회는 미설정 상태로 대기한다. 연결 설정은 주소 형식과 포트 범위를 검사하며 JSON/별도 ENV에 저장한다. 저장 실패 시 두 파일을 복원하고, 정상 저장 후 연결 객체를 새 설정으로 교체한다. API 키는 화면에서 마스킹한다. 실제 모드에서는 모의 신호·가전 시뮬레이션 조작을 제공하지 않으며, 모의 입력을 허용하는 CSI 서비스의 결과도 표시하지 않는다.

MQTT는 최초 연결 실패 재시도, 중복 연결 방지, 종료 시 재시도 취소와 늦은 연결 응답 무시를 처리한다. 제어 가능한 클라이언트 검사 5개와 실제 클라이언트·loopback TCP 시험 브로커 검사 3개가 통과했다. 기존 4개 구독 토픽·QoS, 수어·낙상·가전 명령 수신 및 shortcut UTF-8 발행을 유지한다. 팀 브로커·액추에이터와의 통합 결과는 아니다.

카메라는 320×240 RGBA와 4바이트 길이 헤더를 유지한다. 온전한 프레임 수신 후 연결 상태를 표시하고, 부분 패킷만으로 영상 유효 시간을 연장하지 않는다. 잘못된 프레임 길이는 연결을 종료한 뒤 재접속한다. 분할·연속 패킷, 길이 오류, 불완전한 데이터 지속, 최초 접속 거부 후 복구, 종료 후 콜백·재접속 차단 등 loopback 검사 6개가 통과했다.

CSI는 연결 공백이나 전처리 중 연결 해제 시 이전 파형·판단을 지운다. 재연결·시간 epoch 변경 때 진행 중이던 수집을 완료 처리하지 않는다. 시리얼 timeout으로 나뉜 줄은 이어 받고 과대 입력은 제한한다. 손상된 기록·모델 메타데이터는 원본을 보존한 채 목록에서 제외하고 경고한다. 학습 중 모델 교체·인식 시작을 거부하며, 학습 완료 후 이전 결과를 초기화한다.

UI는 USB 목록을 갱신하고 늦은 응답이 새 연결 상태를 덮어쓰지 않게 한다. 명령이 지연돼도 파형 조회를 유지하며, 결과가 불명확한 timeout 뒤 변경 명령을 자동 재전송하지 않는다. 잘못된 JSON·중복 ID·유효하지 않은 수치는 오류로 안내한다. 녹음 서비스는 권한 응답·취소·종료 경합을 처리하고 자신이 생성한 임시 파일만 정리한다.

## 처리 시간 측정

아래 수치는 Windows 노트북의 로컬 소프트웨어 경로 비교다. 실제 RF 수신·카메라 촬영·화면 렌더링·Pi 성능·행동 정확도를 포함하지 않는다.

카메라 수신 버퍼의 복사를 줄였다. Dart JIT에서 307,200바이트 프레임을 준비 20회 이후 120회 측정하고 각 조건을 번갈아 3회 실행했다.

| 카메라 수신 경로 | 수정 전 | 수정 후 |
| --- | --- | --- |
| 왕복 처리 중앙값 범위 | 22.62–23.14ms | 2.21–2.74ms |
| 측정 프로세스 최대 RSS 범위 | 325.7–326.8MiB | 203.5–204.6MiB |

근거: [카메라 원자료](integration-validation/camera-transport-benchmark.json), [재현 스크립트](../../SW/safehub_app/tool/benchmark_camera.dart)

CSI 상태 조회는 최신 4.025초만 복사하고 동일 입력·설정의 계산 결과를 공유한다. 기록·모델 목록은 파일 변경 시 다시 읽는다. 다음 측정은 합성 입력·8,400프레임 버퍼·모델 메타데이터 40개 조건의 20회 중앙값이며, 숫자 입력 변환 최적화 전의 상태 조회 비교다.

| 상태 조회 조건 | 수정 전 | 수정 후 |
| --- | --- | --- |
| 입력이 그대로인 상태에서 재조회 | 181.82ms | 3.86ms |
| 새 프레임 30개 생성 후 조회 | 189.50ms | 157.12ms |

캐시 재조회 비율은 스트리밍 전체 성능 향상률이 아니다. 근거: [기준 측정](integration-validation/status-baseline.json), [캐시 적용 측정](integration-validation/status-optimized.json)

I/Q 입력은 JSON 생성·AST 재파싱 대신 같은 int64 값에서 진폭을 직접 계산한다. 52채널 매핑(6–31, 33–58), pandas 나노초 변환, DWT·표준화·PCA·FFT·CNN 입력은 유지한다. bool·NumPy scalar 등 특수 입력은 보존된 변환 경로를 사용한다. 경계값·잘못된 입력·입력 불변성, 전처리 단계 16조합과 채널 3개, 표시·학습·고정 모델 입력의 배열 동등성과 소스 해시 변조 거부를 검사했다.

241개 새 합성 프레임, 준비 5회 이후 30회, 기준/변경 순서 교대, 캐시 없이 측정했다. Torch thread 수는 1이다.

| 경로 · 중앙값 | 기존 문자열 변환 | 숫자 변환 |
| --- | --- | --- |
| I/Q → 52채널 진폭 | 152.63ms | 10.58ms |
| 4초 구간 전체 전처리 | 212.93ms | 52.09ms |

근거: [숫자 입력 원자료](integration-validation/numeric-input-benchmark.json), [재현 스크립트](../../SW/wifi_sensing/tests/benchmark_numeric_input.py)

## 연속 실행 검사

| 검사 | 결과 | 적용 범위 |
| --- | --- | --- |
| 20분 합성 입력 | PASS | 입력 72,001개, HTTP 조회 2,400회, 평균 59.997Hz, HTTP 오류·워밍업 후 stale poll·관찰 공백 없음 |

20분 검사에서 최대 입력 공백은 145.2ms, 최대 조회 시간은 399.6ms였다. 버퍼는 8,400프레임 이하였고, 구간 기록 저장과 연결 해제 시 파형·판단 초기화를 확인했다. 검사 도구는 절전 포함 시간과 깨어 있는 시간을 비교하여 절전·긴 관찰 공백을 `INTERRUPTED`로 처리한다. 중단 판정은 가짜 시계 검사 7개로 검증했다.

근거: [연속 실행 검사](integration-validation/soak-numeric-20min.json). 합성 검사 결과는 실제 USB/RF·Pi·장시간 센서 운전이나 메모리 누수 없음의 근거가 아니다.

## Windows 실행 및 전달본

Windows x64 Release는 Flutter 3.29.3, VS 2026/MSVC 19.51, SDK 10.0.26100.0으로 빌드했다. ATLAS 플러그인 제외와 CMake generator 선택은 Windows 호스트 복사본에만 적용한다. 원본 Pub 캐시·production 의존성은 유지한다.

`audioplayers_windows` 4.3.0의 전역 이벤트 처리기 이중 소유권을 독립 vendor 복사본에서 수정했다. 패치 빌드의 실행·정상 종료 3회와 설정 저장 후 홈 재생성을 확인했으며, 확인 범위 내 새로운 Application Error는 없었다. 실제 음성 출력과 모든 종료 경합은 미검증이다. [오디오 실행 근거](integration-validation/windows-audio-smoke.json), [패치 절차](../../SW/windows_preview/README.md)

전달본은 Python 3.12, CPU PyTorch와 전이 의존성 23개를 포함한다. 런처는 상대 경로, UTF-8, 초기 준비 대기 180초를 지원한다. `_pth`와 `-I`로 외부 Python 환경·레지스트리·사용자 site-packages를 제외한다. 경로 길이는 준비 단계에서 검사하며 SciPy가 사용하는 NumPy `_natype.py`를 보존한다. 사용자 기록·모델·로그·개인 접속 정보와 Qt·개발 도구는 포함하지 않는다.

기본 연결 설정은 `CSI_SERVICE_URL=http://127.0.0.1:8768` 하나이며 런처 서비스 포트와 일치한다. 폴더별 실행 제한, 점유 포트 보호, 중복 실행 방지, 자신이 시작한 자식만 종료하는 Job Object를 검사했다.

| 실행 검사 | 결과 |
| --- | --- |
| 런처 `--check` 및 Windows 준비 스크립트 `--real --check-only` | 종료 코드 0 |
| 이동한 전달본 폴더의 GUI·서비스 | 실제 모드 홈 표시, 서비스 준비 13.5초, Flutter·MSVC DLL의 전달본 내부 로딩 확인 |
| 최종 압축 해제본 | 14,103개 파일 크기·주요 해시 일치, 외부 Python 경로 배제, 입력 동등성·출처 해시·checked-hash 캐시 확인 |
| 최종 압축 해제본의 실제 모드 서비스 | 준비 11.99초, 모의 CSI HTTP 400 거부, 수신 미연결·기록 0개·파형/판단 없음 |

최종 `-I` 옵션 적용 후 GUI 재실행은 미검증이다. GUI 검사는 동일 UI 바이너리의 해당 옵션 적용 전 실행 결과다. 압축 해제본의 서비스 검사는 최종 옵션으로 수행했다.

ZIP의 CRC와 SHA-256을 확인했으며 파일 수·용량·의존성은 [전달본 정보](integration-validation/portable-package.json)에 기록한다. [압축 해제본 검사](integration-validation/portable-extracted-smoke.json), [실제 모드 검사](integration-validation/real-mode-smoke.json), [서비스 확인](integration-validation/numeric-real-service-smoke.json), [Windows 빌드·실행 안내](../../SW/windows_preview/README.md)

## 미검증 범위

- 실제 C6 RX USB 수신·분리·복구 및 펌웨어 형식
- Pi 4/5·ATLAS 의존성 설치, ARM64 빌드·실행과 CPU/RAM·지연·장시간 운전
- 실기기 카메라 수어 인식·CSI·음성 동시 운전
- 실측 행동 정확도·오탐·독립 환경 평가
- 팀의 전역 안전 경보·MQTT 브로커·액추에이터 통합
- Pi/ATLAS 최종 설치 패키지와 별도 초기화 Windows PC에서의 전달본 실행

검사는 동일 Windows 노트북의 소프트웨어 경로와 합성 입력을 대상으로 했다. 합성 기록의 학습 점수는 실제 행동 인식 정확도가 아니다.
