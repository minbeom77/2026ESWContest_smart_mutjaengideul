# Wi-Fi CSI Router MVP — Windows + ESP-WROOM-32 버전

이 패키지는 **Windows 노트북 + 사진에서 확인한 ESP-WROOM-32(클래식 ESP32) 개발보드**용입니다.
이전 ESP32-C6용 패키지와 섞어 쓰지 마세요.

## 핵심 구조

```text
2.4 GHz 공유기
      ↑↓ Ping / Wi-Fi packet
ESP-WROOM-32
      ↓ USB Serial (921600 baud)
Windows 노트북
      ↓
Python 실시간 CSI 그래프 + CSV 저장
```

## 이번 버전에서 바뀐 점

- 펌웨어 타깃: `esp32c6` → **`esp32`**
- CSI 설정: ESP32-C6 구조체 → **클래식 ESP32 CSI 설정(LLTF)**
- `Kconfig.projbuild` 위치를 `firmware/main/`으로 수정
- macOS/Linux 설치 스크립트 제거
- Windows용 `.cmd` 실행 파일을 1번부터 순서대로 추가
- UART/PC 캡처 속도: **921600 baud**
- COM 포트 기준으로 실행하도록 수정

---

# 0. 폴더 위치

압축을 풀고 가능하면 아래처럼 짧은 영문 경로에 둡니다.

```text
C:\esp\wifi_csi_windows_esp32_wroom32
```

경로에 한글/공백이 있어도 Python은 대체로 되지만 ESP-IDF 작업은 짧은 영문 경로가 편합니다.

# 1. PC Python 환경 테스트

일반 Windows 탐색기에서 다음 파일을 순서대로 실행할 수 있습니다.

```text
01_SETUP_PC.cmd
02_DEMO_PC.cmd
09_TEST_PARSER.cmd
```

`02_DEMO_PC.cmd`에서 가짜 CSI 그래프가 뜨면 PC 프로그램은 정상입니다.

# 2. ESP-IDF 설치

ESP-IDF v6.0.x를 Windows에 설치합니다. EIM GUI를 쓰는 것이 가장 간단합니다.
설치가 끝나면 바탕화면/시작 메뉴의 **IDF_PowerShell** 또는 ESP-IDF PowerShell 환경을 엽니다.

중요: 아래 펌웨어 관련 `.cmd`는 일반 CMD가 아니라 **ESP-IDF 환경이 활성화된 터미널**에서 실행하는 것이 안전합니다.

# 3. Wi-Fi 설정

IDF_PowerShell에서 프로젝트 폴더로 이동:

```powershell
cd C:\esp\wifi_csi_windows_esp32_wroom32
```

그 다음:

```powershell
.\04_CONFIGURE_FIRMWARE.cmd
```

`menuconfig`에서:

```text
Wi-Fi CSI Router MVP
  2.4 GHz Wi-Fi SSID    = 집 공유기 SSID
  Wi-Fi password        = 공유기 비밀번호
  Router ping rate      = 60
  CSI frame queue length= 32
```

저장 후 종료합니다.

# 4. 빌드

IDF_PowerShell에서:

```powershell
.\05_BUILD_FIRMWARE.cmd
```

성공 기준:

```text
Project build complete.
```

# 5. ESP32 연결 및 COM 포트 확인

사진의 보드는 USB-C 커넥터와 USB-UART 브리지를 사용하는 ESP-WROOM-32 호환 보드입니다.
Windows 노트북에서 전원이 들어오는 연결 방식을 사용하세요.

먼저 일반 PowerShell/CMD 또는 탐색기에서:

```text
03_LIST_PORTS.cmd
```

예:

```text
COM5  USB-SERIAL CH340
```

처럼 새 COM 포트가 보이면 그 포트를 사용합니다.

만약 보드 전원은 켜지는데 COM 포트가 전혀 생기지 않으면 Windows 장치 관리자에서 USB-Serial 장치를 확인하세요.

# 6. 펌웨어 Flash

COM5라고 가정:

```powershell
.\06_FLASH_FIRMWARE.cmd COM5
```

실패하면서 `Connecting...`만 반복되면:

1. 보드의 `BOOT` 버튼을 누른 상태로 유지
2. `EN` 버튼을 짧게 한 번 누름
3. `EN`에서 손을 뗌
4. 1초 후 `BOOT`에서 손을 뗌
5. flash 명령을 다시 실행

보드에 따라 자동 다운로드 모드가 되므로 이 과정이 필요 없을 수도 있습니다.

# 7. ESP32 출력 확인

```powershell
.\07_MONITOR_FIRMWARE.cmd COM5
```

정상적인 시작 예:

```text
#STATUS,connecting,ssid=...
#STATUS,connected,bssid=...,channel=...,rssi=...
#STATUS,csi_enabled,mode=LLTF
#STATUS,ping_started,rate_hz=60
```

이후 다음이 계속 나와야 합니다.

```text
CSI_DATA,0,...
CSI_DATA,1,...
CSI_DATA,2,...
```

Monitor 종료:

```text
Ctrl + ]
```

**Python 캡처 전에 monitor를 반드시 종료하세요.** 한 COM 포트를 두 프로그램이 동시에 열 수 없습니다.

# 8. 실제 CSI 그래프 + CSV 저장

일반 PowerShell 또는 CMD에서 프로젝트 폴더로 이동한 뒤:

```powershell
.\08_CAPTURE_CSI.cmd COM5 first_test
```

60초만 받을 경우:

```powershell
.\08_CAPTURE_CSI.cmd COM5 first_test 60
```

CSV는:

```text
pc\sessions\
```

아래에 저장됩니다.

# 9. 실험용 UI

반복 실험은 프로젝트 루트에서 다음 파일을 실행하는 것이 편합니다.

```powershell
.\10_EXPERIMENT_UI.cmd
```

그래프 전체 유지와 두 CSV 비교 기능이 명확히 구분된 개선판은 다음 파일로 실행합니다.

```powershell
.\11_EXPERIMENT_UI_V2.cmd
```

UI에서 COM 포트, 상태(`empty`, `still`, `moving`), 회차, 측정 시간, 참가자와 거리를 기록할 수 있습니다. 실시간 프레임/FPS/누락/파싱 오류와 정제된 CSI 히트맵을 한 화면에서 확인합니다.

측정 결과 CSV와 실험 조건 JSON은 같은 파일명으로 `pc\sessions`에 저장됩니다.

점수 그래프는 한 실험의 전체 구간을 유지하며 히트맵은 성능을 위해 최근 400프레임을 표시합니다. 하단 목록에서 실험 두 개를 `Ctrl+클릭`한 뒤 **실험 2개 비교**를 누르거나, 저장된 CSV 두 개를 직접 선택해 점수 곡선과 분포를 비교할 수 있습니다.

# 10. 첫 실험

동일한 공유기/ESP32 위치를 유지하고 각각 60초씩 받습니다.

```powershell
.\08_CAPTURE_CSI.cmd COM5 empty 60
.\08_CAPTURE_CSI.cmd COM5 still 60
.\08_CAPTURE_CSI.cmd COM5 moving 60
```

- `empty`: 측정 공간에 사람 없음
- `still`: 사람이 있지만 최대한 정지
- `moving`: 몸/팔을 반복해서 움직임

분석:

```powershell
cd pc
.\.venv\Scripts\python.exe analyze_capture.py sessions\파일명.csv
```

# 폴더 구조

```text
wifi_csi_windows_esp32_wroom32\
├─ START_HERE_WINDOWS_KO.md
├─ 01_SETUP_PC.cmd
├─ 02_DEMO_PC.cmd
├─ 03_LIST_PORTS.cmd
├─ 04_CONFIGURE_FIRMWARE.cmd
├─ 05_BUILD_FIRMWARE.cmd
├─ 06_FLASH_FIRMWARE.cmd
├─ 07_MONITOR_FIRMWARE.cmd
├─ 08_CAPTURE_CSI.cmd
├─ 09_TEST_PARSER.cmd
├─ 10_EXPERIMENT_UI.cmd
├─ firmware\
│  ├─ CMakeLists.txt
│  ├─ sdkconfig.defaults
│  └─ main\
│     ├─ CMakeLists.txt
│     ├─ Kconfig.projbuild
│     └─ main.c
└─ pc\
   ├─ requirements.txt
   ├─ setup_windows.ps1
   ├─ list_ports.py
   ├─ csi_capture.py
   ├─ experiment_ui.py
   ├─ analyze_capture.py
   └─ test_parser.py
```

# 주의

- 이 펌웨어는 **ESP32-C6용이 아닙니다.** 현재 사진의 `ESP-WROOM-32`에 맞춘 버전입니다.
- ESP32는 2.4 GHz Wi-Fi만 사용합니다.
- 첫 목표는 수면 AI가 아니라 `empty / still / moving`에서 CSI 변화가 반복적으로 구분되는지 확인하는 것입니다.
- 공유기 위치, ESP32 위치/방향을 데이터 수집 중 바꾸지 마세요.
