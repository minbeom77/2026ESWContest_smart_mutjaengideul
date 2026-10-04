# SafeHub 안의 와이파이 센싱

노트북 최신 WifiSensing2-src의 엔진을 기존 수어 Flutter UI에 연결한 개발본입니다. 원래 WifiSensing2.0 EXE/데이터는 수정하지 않습니다. 실기기 검증 전 상태입니다.

입력 I/Q의 문자열 변환을 줄인 숫자 변환기를 관찰·학습·추론에서 공유합니다. 원본 변환기, 변경 명세와 라이선스는 runtime에 보존하며 전처리 수치·채널·모델 입력 구조는 유지합니다.

## 실행

같은 기기에서 CSI 서비스와 기존 SafeHub 앱을 함께 실행합니다. 앱 홈의 **와이파이 센싱**을 누릅니다. 기본 연결 주소는 `http://127.0.0.1:8765`입니다. 웹 화면을 띄우는 구조가 아니라 네이티브 Flutter 화면이 로컬 Python 서비스에 명령을 전달합니다.

기존 노트북 Python 환경으로 실행:

```powershell
python SW/wifi_sensing/bridge.py --real-only --allow-training --data-dir <새로운_데이터_폴더>
```

Pi용 실행 형식(실제 OS 확인 후 설치):

```sh
python3 SW/wifi_sensing/bridge.py --real-only --data-dir "$HOME/SafeHubData/csi"
```

Pi에서는 `--allow-training`을 주지 않습니다. OS/ARM64에서 requirements 설치, 카메라/USB 권한, Flutter ATLAS 빌드 및 자동 시작 서비스는 장비 확인 후 확정합니다. 현재는 설치 완료/실기기 실행 가능으로 보증하지 않습니다.

UI의 기존 MQTT·카메라·음성 환경 설정은 기존 방식을 따릅니다. `CSI_SERVICE_URL`만 기본 loopback 주소가 추가되었습니다. 외부 IP에 CSI 제어 서비스를 노출하는 설정은 제공하지 않습니다.

실제 모드에서는 홈의 **연결 설정**에서 MQTT·카메라·TTS/STT 주소를 저장합니다. 주소가 비어 있는 기능은 미설정으로 대기하며, 저장하면 새 설정으로 연결을 다시 시작합니다. `--real-only` 서비스는 모의 신호 요청을 거부합니다. 별도 체험 빌드에서 모의 신호를 사용할 때만 이 옵션을 제외합니다. 자세한 준비 방법은 [실제 모드 연결](../../docs/wifi-csi/REAL_MODE.md)을 참고하세요.

## 사용 흐름

1. **신호 수집:** USB 포트를 선택해 연결합니다. C6 TX/RX가 기존 CSV 펌웨어를 사용하는 구성을 우선 대상으로 합니다. 여기서 펌웨어를 덮어쓰지 않습니다. 모의 신호 버튼은 별도 체험 모드에만 표시됩니다.
2. **파형:** 3단계 버튼이 최근 4초 파형에 적용됩니다. 모두 끄면 원본 채널을 봅니다. 학습/인식에는 항상 최종 3단계 전처리를 사용합니다.
3. **기록:** 행동과 회차, 시간을 선택합니다. 3초 준비 뒤 기록하고 완료 시 저장합니다. 한 실험 내 기록들은 같은 회차를 유지하고, 독립적으로 다시 실험할 때 회차를 바꿉니다. 기록 도중 수신 끊김/재부팅이 발생하면 그 기록은 저장하지 않습니다.
4. **기록·학습:** 체크한 기록만 학습합니다. 행동마다 최소 3회차가 필요하며 이는 평가 분할을 위한 최소 조건입니다. 행동 정확도를 보장하는 수량이 아닙니다. 일괄 삭제와 방금 삭제 복원을 지원합니다. 모의/실측은 같은 학습에 섞이지 않습니다.
5. **현재 행동:** 학습된 모델을 선택하고 인식을 시작합니다. 새 4초 구간이 모여야 판단하며, 수신이 끊기면 이전 결과를 지웁니다.

화면 이동은 수집/학습을 중단하지 않습니다. 취소 또는 연결 해제를 명시적으로 누릅니다. 연결이 끊어진 USB는 같은 포트로 2초 간격 재연결을 시도하고 재동기화합니다. 포트 자체가 바뀌면 새 포트를 선택합니다.

## 기존 데이터와 PC/Pi 이동

기존 앱에서 기록 ZIP을 내보내고 통합 화면의 `기록 가져오기`로 읽습니다. 기존 폴더를 직접 공유하지 않습니다. 기본 통합 데이터는 `~/SafeHubData/csi`이며 Git에 포함하지 않습니다.

Pi 기록은 체크 후 `선택 기록 내보내기`를 누르고 표시된 ZIP을 PC로 복사합니다. PC에서 학습 후 `Pi용 모델 내보내기`를 누릅니다. ZIP을 Pi에서 풀고 **model.json과 weights.npz가 있는 model 폴더**를 `PC에서 만든 모델 가져오기`에 입력합니다. 입력 경로는 UI/서비스가 실행되는 그 기기의 경로입니다. 임의의 joblib 파일은 가져오기 대상으로 지원하지 않습니다.

기존 노트북 앱의 같은 profile 모델도 같은 Pi 모델 ZIP 형식으로 가져올 수 있습니다. GitHub의 과거 50채널/PCA3 모델은 호환되지 않습니다.

## 통신과 배포 범위

기존 MQTT Topic/JSON 파일은 수정하지 않았습니다. 현재 센싱 페이지의 실시간 판단은 로컬 API를 사용합니다. 낙상 판단을 기존 전역 안전 경보·LED·베드셰이커로 자동 발행하는 기능은 아직 활성화하지 않았습니다. 행동별 이벤트 이름/우선순위와 v1.2 승인 여부를 확인한 뒤 별도 연결합니다. 모의 결과는 안전 경보에 사용하지 않습니다.

원본 엔진의 edge_runtime.py도 보존되어 있지만, 이번 화면은 새 stream.py를 사용합니다. 새 경로는 제한된 메모리 버퍼와 사용자가 지정한 기록만 저장하며 무제한 원본 저널을 만들지 않습니다.

## 검사

```sh
python SW/wifi_sensing/tests/test_bridge.py
python -m unittest discover -s SW/wifi_sensing/tests -p "test_*.py" -v
python SW/wifi_sensing/prepare_ui_tests.py /tmp/safehub-wifi-ui-tests
cd /tmp/safehub-wifi-ui-tests
flutter pub get
flutter test --reporter expanded
```

기본 구성은 CSI 서비스·화면 소스와 두 테스트 파일을 그대로 복사합니다. 홈·설정·음성·MQTT·카메라를 포함한 전체 앱의 호스트 검사는 `--full`로 준비합니다.

```sh
python SW/wifi_sensing/prepare_ui_tests.py --full /tmp/safehub-full-ui-tests
cd /tmp/safehub-full-ui-tests
flutter pub get
flutter test --reporter expanded
```

Windows에서는 `/tmp/...` 대신 저장소 밖의 새 폴더 경로를 지정합니다. 출력 폴더는 없거나 완전히 비어 있어야 하며, 기존 파일이 있으면 덮어쓰지 않고 중단합니다. 다시 검사 환경을 만들 때도 새 빈 폴더를 사용합니다. 저장소 내부·상위 폴더와 드라이브 루트는 출력 대상으로 허용하지 않습니다.

`--full`은 원본 `lib`, `test`, `assets`, 분석 설정을 복사하고, 복사본 pubspec에서 ATLAS 전용 path 의존성 `audioplayers_atlas`, `record_atlas` 두 개만 제외합니다. 원본 소스와 pubspec은 수정하지 않습니다. 이 검사는 호스트 환경의 코드 동작을 대상으로 하며, ATLAS 전용 플러그인·Pi 빌드·실제 장비 성능을 검증하는 것은 아닙니다. 외부 원본의 라이선스와 해시는 runtime/NOTICE.md에 기록합니다.
