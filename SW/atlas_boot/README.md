# ATLAS 보드 자동 실행

RPi5에서 SafeHub 화면, CSI 수집 서비스, MQTT 브로커를 실행한다. RPi4의
기존 카메라·수어 추론 서비스는 유지하고 MQTT 목적지를 RPi5로 지정한다.
Topic과 JSON 형식은 변경하지 않는다.

## 구성

| 장치 | 실행 항목 | 연결 |
| --- | --- | --- |
| RPi5 | SafeHub UI, CSI 전처리·추론, Mosquitto | 외부 화면, ESP32 수신기 USB |
| RPi4 | 카메라, 기존 수어 모델 | 카메라 USB, RPi5와 같은 네트워크 |
| ESP32 송신기 | 기존 송신 펌웨어 | USB 전원 |

RPi5의 설치 경로는 `/opt/safehub-csi`(Python·CSI)와
`/opt/safehub-system`(부팅·MQTT)이다. 기존 PC 배포본과 데이터는 사용하지 않는다.
CSI 서비스는 `127.0.0.1:8769`에만 열리고 학습·모의 입력을 허용하지 않는다.
PC에서 학습한 모델을 가져오기 전에는 실제 행동 분류 결과를 만들지 않는다.

## 설치 전제

이 폴더는 부팅 설정이다. ATLAS 앱, 검증된 ARM64 Python 환경, CSI 소스,
Mosquitto 실행 파일을 먼저 배치해야 한다. Raspberry Pi OS용 설치기가 아니다.

1. `safehub-csi.service`, `safehub-mqtt.service`, `safehub-ui.service`를
   `/data/share/usr/lib/systemd/system/`에 배치한다.
2. `boot.sh`, `start-ui.sh`, `mosquitto.conf`를 `/opt/safehub-system/`에 배치한다.
3. `/opt/safehub-system/receiver.env`에 수신기 고유 경로를 기록한다.
   `CSI_RECEIVER_PORT=/dev/serial/by-id/<수신기 USB 식별자>`
4. `/data/share/usr/lib/systemd/system/safehub-mqtt.service.d/camera.conf`에
   `[Service]`와 `IPAddressAllow=<RPi4 주소>/32`를 설정한다. 기본 허용 주소는
   루프백뿐이다. 커널의 IP 필터 동작을 허용/비허용 장치에서 각각 확인한다.
5. 앱의 `connection-settings.json`에서 MQTT는 `127.0.0.1:1883`, CSI는
   `http://127.0.0.1:8769`, 카메라는 RPi4 주소의 5000번 포트로 지정한다.
   RPi4의 `/data/safehub/run_camera.sh`에서는 `MQTT_BROKER`를 RPi5 주소로 바꾼다.
6. RPi5에서 `safehub-bootstrap.service`와 `install-bootstrap.sh`를 같은 폴더에
   두고 `sh install-bootstrap.sh`를 실행한다. 기존 설정은 백업하며, 읽기 전용
   루트는 설치 중에만 쓰기 가능하게 바꾸고 종료 시 복구한다.
7. 재부팅해 자동 시작을 확인한다. 두 보드의 네트워크 주소가 달라지면 설정도
   바꿔야 하므로 공유기에서 DHCP 주소 예약을 권장한다.

로컬 음성 자막을 사용하면 `../local_stt/README.md`에 따라 소스·Python 환경·
모델을 `/opt/safehub-stt`에 준비하고, `safehub-stt.service`를
`/data/share/usr/lib/systemd/system/`에 설치한다. 최신 `boot.sh`는 해당 단위
파일이 있을 때 STT도 시작한다. 외부 STT 서버를 사용하는 구성에는 설치하지 않는다.

ATLAS의 `/data`는 systemd의 최초 부팅 작업 구성 이후에 마운트된다.
따라서 `/data`에 unit 파일과 wants 링크만 두는 것으로는 자동 실행되지 않는다.
`/etc/systemd/system/safehub-bootstrap.service`가 마운트를 기다린 뒤
`daemon-reload`와 서비스 시작을 수행한다. 확인할 때는 개별 서비스의
`is-enabled` 대신 bootstrap의 활성화 여부와 재부팅 후 실제 상태를 함께 본다.

CSI는 시작 시 지정 수신기를 연결하고, USB가 없으면 재시도한다. 보드 번호가
`ttyACM0`에서 바뀌어도 고유 경로로 다시 찾는다. 앱에서 연결을 끊으면 그 실행
중에는 자동으로 다시 켜지지 않는다. 출력 전용 CSV 수신기에는 상태 명령을
보내지 않고 DTR/RTS를 내린 채 포트를 연다. C3 등 명령을 받는 펌웨어를 쓸
때는 `--passive-receiver` 옵션을 제거해야 한다.

UI는 ATLAS 홈 화면이 준비된 뒤 AppManager로 실행한다. 앱이 종료되면 다시
시작하지만 실행 중인 앱의 화면을 주기적으로 앞으로 가져오지는 않는다.

## 점검

```sh
systemctl is-enabled safehub-bootstrap
systemctl is-active safehub-bootstrap safehub-csi safehub-mqtt safehub-ui
busctl --system call com.atlas.AppManager1 /com/atlas/AppManager1 \
  com.atlas.AppManager1 GetStatus s com.atlas.app.safehub_app
journalctl -u safehub-csi -u safehub-mqtt -u safehub-ui -n 50
```

로컬 STT를 설치한 보드에서는 재부팅 후 `systemctl is-active safehub-stt`와
`journalctl -u safehub-stt -n 50`도 확인한다. 소스의 부팅 순서 검사는 저장소
루트에서 `python3 -m unittest discover -s SW/atlas_boot -v`로 실행한다.
이 검사는 systemctl 대역을 사용하며 실제 보드 재부팅 검증을 대체하지 않는다.

카메라 보드의 수어 추론 로그와 MQTT 연결 여부, UI 수신 로그를 따로 확인한다.
카메라 영상이 보이는 것만으로 수어 결과 전달이 정상이라는 뜻은 아니다.

로컬 STT는 별도 설치된 경우 부팅 때 시작한다. 외부 STT 주소를 설정하면
해당 서버가 계속 필요하다. TTS 서버 설치·자동 시작은 이 설정에 포함하지 않는다.

## 배포 의존성

시험 장치의 MQTT 런타임은 Debian arm64 `mosquitto=2.0.21-1` 패키지와 필요한
공유 라이브러리를 전용 폴더에 풀어 사용한다. 시스템 라이브러리를 덮어쓰지
않는다. 원본 패키지 목록·버전·SHA-256과 저작권 문서는 설치 폴더에 보존한다.
실제 CSI 소스 및 Python 의존성은 `../wifi_sensing`의 규격을 따른다.
## ATLAS UI 녹음 플러그인 소스

저장소의 `record_atlas` 패키지는 pubspec과 라이선스만 추적되어 Dart 구현이
누락되어 있었다. `record_linux` 1.2.0의 BSD-3-Clause 구현을 기반으로
`RecordAtlas`를 복구하고 `lib/` 제외 규칙에 예외를 추가했다.
출처: [record_linux 1.2.0](https://pub.dev/packages/record_linux/versions/1.2.0).

ATLAS의 `/data/share/safehub-tools/parecord`를 사용하며, 앱에서 쓰는 16kHz mono
WAV는 parecord가 직접 저장한다. 종료 시 프로세스가 파일을 마무리할 때까지 기다린다.
외부 STT/TTS 서버와 실제 마이크·스피커까지의 동작은 UI·CSI 검증과 구분한다.
