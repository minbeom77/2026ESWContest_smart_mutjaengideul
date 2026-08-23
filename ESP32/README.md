# ESP32 Wi-Fi CSI 실험 도구

ESP32-WROOM-32와 2.4 GHz Wi-Fi를 이용해 CSI(Channel State Information)를 수집하고,
Windows PC에서 행동별 실험 데이터를 기록·시각화·비교하기 위한 도구입니다.

현재 목표는 카메라 없이 공간의 신호 변화를 측정하여 일상 행동, 낙상,
화장실 미끄러짐 같은 안전 관련 행동을 구분할 수 있는 데이터셋을 만드는 것입니다.

## 현재 구현 상태

- ESP32의 2.4 GHz AP 연결 및 자동 재연결
- AP에서 수신한 패킷의 CSI를 시리얼 `CSI_DATA` 형식으로 출력
- Windows에서 CSI 파싱 및 CSV 저장
- 실험 조건과 요약 지표를 JSON 메타데이터로 저장
- CSI 진폭 히트맵과 움직임 점수 실시간 표시
- 행동 분야·세부 행동·참가자·거리·메모 기반 라벨링
- 저장 실험 조회, 라벨 수정, 복구 가능한 휴지통 이동
- 여러 실험의 움직임 점수와 분포 동시 비교
- 전체 실험을 `experiment_catalog.csv`로 자동 정리

> 움직임 점수는 데이터 수집을 돕는 초기 지표이며 완성된 낙상 판정 모델이 아닙니다.

## 폴더 구성

```text
ESP32/
├─ firmware/          ESP-IDF 펌웨어
│  └─ main/           Wi-Fi 연결 및 CSI 수집 코드
├─ pc/                파서, 저장기, 분석기, 실험 UI
├─ docs/              실험 계획과 상세 사용 설명
├─ 01_...11_*.cmd     Windows 실행 순서별 도구
├─ README.md          GitHub 프로젝트 안내
└─ README.txt         기능별 빠른 안내
```

## 기능별 실행 파일

### PC 환경 및 연결 확인

| 파일 | 기능 |
|---|---|
| `01_SETUP_PC.cmd` | Python 가상환경과 의존성 설치 |
| `02_DEMO_PC.cmd` | ESP32 없이 파서·그래프 데모 실행 |
| `03_LIST_PORTS.cmd` | ESP32 COM 포트 검색 |

### 펌웨어 설정 및 보드 기록

| 파일 | 기능 |
|---|---|
| `04_CONFIGURE_FIRMWARE.cmd` | 로컬 Wi-Fi SSID·비밀번호 설정 |
| `05_BUILD_FIRMWARE.cmd` | ESP-IDF 펌웨어 빌드 |
| `06_FLASH_FIRMWARE.cmd COM번호` | 지정한 ESP32에 펌웨어 기록 |
| `07_MONITOR_FIRMWARE.cmd COM번호` | 부팅·Wi-Fi·CSI 로그 확인 |

### 데이터 수집 및 실험

| 파일 | 기능 |
|---|---|
| `08_CAPTURE_CSI.cmd COM번호 라벨 시간` | 명령행 CSI 저장 |
| `09_TEST_PARSER.cmd` | 저장 파서 단위 테스트 |
| `10_EXPERIMENT_UI.cmd` | 기본 실험 UI |
| `11_EXPERIMENT_UI_V2.cmd` | 분류·저장·다중 비교가 포함된 권장 UI |

## 요구 환경

- Windows 10/11
- ESP32-WROOM-32 개발 보드
- 데이터 통신이 가능한 USB 케이블
- ESP-IDF 5.5 계열
- PC 도구용 Python 3.12 권장
- 2.4 GHz Wi-Fi AP 또는 휴대폰 핫스팟

ESP-IDF가 사용하는 Python과 PC UI용 Python 가상환경은 서로 독립적입니다.

## 빠른 시작

```cmd
01_SETUP_PC.cmd
03_LIST_PORTS.cmd
04_CONFIGURE_FIRMWARE.cmd
05_BUILD_FIRMWARE.cmd
06_FLASH_FIRMWARE.cmd COM7
11_EXPERIMENT_UI_V2.cmd
```

`COM7`은 예시이므로 `03_LIST_PORTS.cmd`에서 확인한 실제 포트로 바꿉니다.
펌웨어를 이미 기록한 같은 보드를 사용한다면 설정·빌드·플래시 단계는 생략할 수 있습니다.

## 데이터 파일

실험 결과는 실행 PC의 `pc/sessions/`에 저장됩니다.

- `csi_*.csv`: 프레임별 원본 CSI와 라벨
- `csi_*.json`: 실험 조건, 프레임 수, FPS, 움직임 점수 요약
- `experiment_catalog.csv`: 전체 실험 통합 목록
- `_trash/`: UI에서 제외한 파일의 복구용 보관 위치

실험 데이터와 참가자 메타데이터는 기본적으로 Git에 올리지 않습니다.

## 보안 원칙

- `firmware/sdkconfig`와 `firmware/sdkconfig.old`는 커밋하지 않습니다.
- Wi-Fi SSID·비밀번호는 각 개발자의 PC에서 `04_CONFIGURE_FIRMWARE.cmd`로 설정합니다.
- `pc/sessions/`, `.venv/`, `firmware/build/`는 커밋하지 않습니다.
- 공개 저장소에 참가자 이름, MAC 주소, 실제 CSI 원본을 올리기 전에 팀 검토를 거칩니다.

## 참고

- [Espressif ESP-IDF Wi-Fi examples](https://github.com/espressif/esp-idf/tree/master/examples/wifi)
- [Espressif ESP-CSI](https://github.com/espressif/esp-csi)
- [ESP-CSI router receiver example](https://github.com/espressif/esp-csi/tree/master/examples/get-started/csi_recv_router)
