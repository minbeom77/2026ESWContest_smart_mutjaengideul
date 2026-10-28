# 제출 소스와 외부 실행 자료

현재 UI·서비스·수어/비전·MQTT·Uno 브리지 소스는 공개 Git에서 검토한다.
실제 장치의 SDK·모델·설정·펌웨어/설치 산출물까지 모두 포함된 배포 이미지라고 선언하지 않는다.
이 문서의 장치 경로/해시는 기존 사용자·작성자 보고와 Git 코드를 대조한 기록이며
클라우드가 현재 장치에서 직접 읽은 결과가 아니다. 보관본은 미확인/미확보로 남기며 없다고 단정하지 않는다.

| 구성 | 공개 소스 및 준비 방법 | 장치 자료·확인 상태 |
|---|---|---|
| PC 화면 | `SW/safehub_scenario/tool/run_ui_preview.py`·host lock | 모델·장치 없이 실제 앱의 web 미리보기/호스트 회귀 가능. 장치 정확도 검증 아님 |
| ATLAS UI | `SW/safehub_scenario/atlas`, `third_party/record_atlas`, 수동 kernel용 `tool/atlas_main.dart` | 팀 ATLAS SDK와 audioplayers plugin은 별도 준비. 후보 1.6.0+1과 #18의 1.5.16 설치 보고를 구분 |
| Pi4 수어·비전 | `SW/rpi4_sign_cpp`, `SW/rpi4_vision_atlas`; candidate/portable 빌드 안내 | Palm/HandPose ONNX 두 모델, 실제 `runtime_data`, `active_targets_v4.bin` 필요. ARM64 도구/대상 라이브러리·ELF 대응 자료는 별도 |
| 한국어 STT | `SW/local_stt/download_model.py --destination <별도 폴더>` | 공식 pinned revision의 weights/tokens SHA 검증. Apache-2.0 모델 카드·Kiwi 고지 유지. ARM64 실제 설치/입력 시험은 별도 |
| fastText | `SW/fasttext_context/tools/install_host.sh`, `check_runtime.py --model <확보 모델>` | `fire_screen_model.bin`은 이미 확보한 모델 사용. 가짜 모델 규칙/HTTP 검사와 실제 모델 정확도 구분 |
| YAMNet | `SW/yamnet_alarm`·requirements·unit | `yamnet.tflite`·521 label 목록 필요. embedding model/target reference는 선택 옵션이며 실제 unit 옵션·파일을 함께 보존해야 동일 검출 구성이 됨 |
| CSI | `SW/wifi_sensing`, `HW/esp32_csi` | 개인 기록/학습 모델 별도. 실제 낙상·일상 모델이 없으면 자동 낙상 정확도를 검증했다고 표시하지 않음 |
| Uno | `SW/uno_bridge`·명령/핀 계약·모의 시리얼 검사 | 브리지는 펌웨어가 아님. 실제 올린 `.ino`/펌웨어 출처는 미확인/미확보. 임의 스케치를 원본으로 만들어 넣거나 플래시하지 않음 |
| 설정·복구 | unit/부팅/staging 소스와 `tools/collect_device_inventory.sh` | 개인 URL/인증정보/배치/모델/기록/백업은 공개 Git에 추가하지 않음. 읽기 inventory 후 source/build manifest와 대조 |

## 보고된 해시와 보관 위치

- 추가 수어 참조 `/data/safehub/active_targets_v4.bin`:
  `f1c3cec6b057a053733dc45690317724745cc47258a2f34753e4659ad669d7d7` (사용자 보고).
- fastText `/data/safehub/fasttext/fire_screen_model.bin`:
  `5691ceb3daa177053dc68cc57e2622ec83cc9c9e90cb8d10de2b05751fef512d` (#14 기록).
- YAMNet 선택 full-float embedding model:
  `141fba1cdaae842c816f28edc4937e8b4f0af4c8df21862ccc6b52dc567993c3` (#14 기록).
  이것을 기본 quantized `yamnet.tflite`의 해시라고 바꾸어 쓰지 않는다.
- 선택 siren/bell reference `/data/safehub-yamnet/models/target-siren-bell-20261027.npz`:
  `4b9ec8c93cd0dc7e5acab2af978b83b5022c6d9fd72ac640238738294d54dce9` (#14 기록).
- #18 체크포인트 보고: 각 Pi `/data/safehub-checkpoints/20261028-0425/`,
  개발 노트북 `output/checkpoint-20261028-0425/`. 완전한 SD 이미지나 모든 OS/서비스 자료가 아님.
- Pi5 1.5.16 보고: `/data/safehub-pr7/releases/sign-auto-video-20261028`,
  package `031c65518d1a0b5b46ac867fb29296c0587e70abbad7306b971cd7fac1f1a16e`,
  AOT `f81096a093ea9ceee544798f1baf40b2724188775be96e972973ee471fbdd528`.
- Pi4 최종 실행본 보고: `vision_sign_preserve_tracks`,
  `fb67a8fb98dbf8dace1e7ae7ab00a325bebfc4cf55902a0a788256244760d6e2` (#18 기록).

위 해시는 보관 자료를 찾을 때의 비교 기준이다. 현재 파일 일치·모델 로드·실물 동작을
이번 통합에서 확인한 증거가 아니다. 모델/녹음의 이용 권한·출처를 확인하고 필요한 자료를
별도 전달하며 LG 제공 비공개 SDK/문서를 공개 저장소로 복사하지 않는다.

## main 병합 후 최소 현장 확인

코드 제출과 장치 설치는 별개다. 장치 실행본을 바꾸지 않은 상태에서 먼저 현재 ELF/kernel·모델·
firmware/build 자료를 읽기 대조한다. 실제 수어의 도움 화면→LED·진동→괜찮다/터치 종료,
무동작 점등/소등, 실제 경보음, MQTT 복구·재부팅은 독립적으로 기록한다.
물리 출력 확인 없이 MQTT/PUBACK/UART 응답만으로 실물 통과라고 쓰지 않는다.
