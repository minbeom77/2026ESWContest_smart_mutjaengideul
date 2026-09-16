# C++ 사진 기반 Palm + HandPose 통합

## 범위
한 C++ 프로세스에서 사진 전처리, Palm CPU 추론, anchor 생성, sigmoid/decode/IoU NMS, 회전 ROI, HandPose CPU 추론, 원본 21 XY 복원을 수행합니다.
실행 중 Python이나 외부 다운로드는 필요하지 않습니다. Python은 결과 비교 스크립트에만 사용합니다.
원본 영상에 flip을 적용하지 않습니다. 좌표는 원본 픽셀입니다. `handedness_raw`를 기록하며 실제 LEFT/RIGHT는 `physical_hand: unverified`로 남깁니다.
Palm score > 0.3, NMS IoU > 0.3 제거, Hand confidence >= 0.8. 후보 수를 임의로 2개로 제한하지 않습니다.

## 사용자 Docker에서 실행
준비된 x86_64 ATLAS 개발 컨테이너 전용입니다. 실제 RPi4에서 실행하는 빌드 스크립트가 아닙니다.
- ORT_ROOT 기본값: /app/onnxruntime-host-1.29.0 (include/, lib/)
- OpenCV: /usr/include/opencv4, /usr/lib/x86_64-linux-gnu
- 모델: /app/models, 기존 파일 사용

```bash
bash /app/vision_cpp_integrated/run_host.sh
```
기본 입력 `/app/capture3.jpeg`, 출력 `/app/vision_cpp_result_01/result.json`, `overlay.png`.
출력 폴더가 이미 존재하면 중단합니다. 재실행 시 새 폴더를 지정하세요.

```bash
bash /app/vision_cpp_integrated/run_host.sh /app/capture3.jpeg /app/models /app/vision_cpp_result_02
/app/palm-check-venv/bin/python /app/vision_cpp_integrated/compare_result.py /app/palm_hand_auto_check_01/result.json /app/vision_cpp_result_02/result.json
```
검증 스크립트는 동일 사진의 anchor ID로 연결해 XY 차이를 보고합니다. 추적기나 일반 정확도 평가가 아닙니다.

## 여기서 수행한 검증 (2026-09-10)
- 사용자 업로드 코드와 fixture로 기존 C++ generated-anchor decode/NMS 재실행 PASS.
- 통합 코드 x86_64 컴파일 및 실제 두 ONNX 모델 실행 성공: OpenCV 4.6.0 / ORT 1.29.0.
- 현 환경에 JPEG codec 의존성이 완비되지 않아 `-DVISION_RAW_ONLY`로 동일 decoded BGR fixture를 사용했습니다. Palm 전처리부터 두 추론과 좌표 복원까지 모두 통합 코드가 실행합니다.
- JPEG 입력/PNG 출력 기본 빌드 경로는 C++ syntax check 통과. JPEG 실행 및 링크는 사용자 Docker에서 최종 확인해야 합니다.
- 사진 결과: Palm 후보 5, NMS 1, anchor 388, 손 신뢰도 0.991991221905.
- Python JSON 대비 원본 XY 거리: 최대 0.03919108571 px, 평균 0.02118942609 px.
- 이는 이 사진의 수치 비교 결과이며 15클래스 정확도/실시간 성능/양손 일반화 PASS가 아닙니다.
- 640x480 black BGR 입력: 후보 0, 검출 손 0, 정상 종료/빈 hands 배열.
- 출력 overlay 시각 검토: 손목 및 다섯 손가락 위치에 landmark 정렬.
- `validated_overlay.png`는 raw 실행의 PPM을 PNG로 변환한 결과입니다.

## 의도적으로 남겨 둔 항목
기존 ROI 픽셀 완전 일치 검사는 FAIL(최대 4/255), 행렬/자르기 좌표는 일치합니다. 이 차이를 허용 오차 변경으로 숨기지 않았습니다.
C++ ONNX 단일 모델의 동일 입력 결과가 Python과 같다는 기존 검증과 전체 전처리 포함 결과는 구분됩니다.
실제 RPi4 Camera1 연속 프레임, Palm CPU + HandPose XNNPACK, FrameHands 좌우 의미, SignEngine/MQTT, 성능 검증은 아직 미구현/미검증입니다.
이 도구는 파일 입력용입니다. 최종 target의 JPEG/imgcodecs 의존을 요구하는 설계가 아닙니다.

## 코드 출처
사용자가 제공한 `vision_cpp_integration_bundle.tar.gz`의 검증 C++/Python 코드와 그 대화에서 확인한 OpenCV Zoo 수식을 통합했습니다.
- https://github.com/opencv/opencv_zoo/tree/main/models/palm_detection_mediapipe
- https://github.com/opencv/opencv_zoo/tree/main/models/handpose_estimation_mediapipe
- https://github.com/microsoft/onnxruntime
NMS는 xyxy 기준 greedy IoU 구현이며 Zoo의 NMSBoxes 호출과 동등하다고 주장하지 않습니다.
모델·ORT·OpenCV 바이너리는 이 묶음에 포함하지 않습니다. 대회 제출 전 해당 코드 및 모델별 라이선스/고지를 기존 프로젝트에 정리해야 합니다.

## RPi4 실기기 사전 검증

크로스 컴파일된 `VISION_RAW_ONLY` 실행파일은 JPEG가 아닌 준비된 BGR fixture를 입력으로 사용합니다.

필수 공유 라이브러리:
- `libopencv_imgproc.so.409`
- `libopencv_core.so.409`
- `libonnxruntime.so.1`

RPi4에 배포본을 전송한 뒤 실행합니다.

```bash
tar -xzf rpi4_vision_deploy.tar.gz
cd rpi4_vision_deploy
./run_rpi4.sh
```

`run_rpi4.sh`는 aarch64 환경, 필수 파일, 공유 라이브러리를 검사한 뒤 Palm → NMS → HandPose → 원본 좌표 복원을 실행합니다.

기준 fixture의 호스트 결과는 Palm 후보 5개, NMS 후 1개, 채택 손 1개입니다. RPi4에서는 실행 성공 여부와 결과 수치 및 처리 시간을 별도로 기록해야 합니다.

## Handedness 및 좌우반전 규칙

HandPose 모델의 `handedness_raw`는 `0.5` 이하가 모델상 `LEFT`, `0.5` 초과가 모델상 `RIGHT`입니다. 현재 C++ 사진 파이프라인은 원본 비반전 영상을 입력하므로 실제 손은 모델 라벨의 반대로 기록합니다.

- `mirror_input=false`: 모델 `LEFT` → 실제 `RIGHT`, 모델 `RIGHT` → 실제 `LEFT`
- `mirror_input=true`: 모델 라벨을 실제 손 라벨로 그대로 사용

검증 사진 `capture3.jpeg`는 실제 왼손이며 `handedness_raw=0.73526763916`이 출력되었습니다. 따라서 모델 라벨 `RIGHT`, 보정된 `physical_hand=LEFT`로 확인했습니다.

표시 화면의 반전과 추론 입력의 반전은 별도 설정으로 관리해야 합니다. 향후 Camera1 연동 시 원본 프레임을 저장하여 V4L2 입력 방향을 다시 확인합니다.
