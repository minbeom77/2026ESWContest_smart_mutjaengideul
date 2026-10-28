# Python 수어 인식 기준 구현

C++ 분류기의 기준이 되는 Python 15종 수어 인식 코드와 참조 데이터를 모아 둔 폴더입니다.
Pi4의 실시간 C++ 실행 코드는 [rpi4_vision_atlas](../rpi4_vision_atlas)와
[rpi4_sign_cpp](../rpi4_sign_cpp)에 있습니다.

## 구성

| 경로 | 역할 |
|---|---|
| `07g_webcam_15class_final_frozen.py` | 15종 분류, SIGN/NO-SIGN 판정, 보완 분류 |
| `06u_webcam_combined_hierarchy.py` | 영상 입력과 한 손·양손 분류 연결 |
| `06j_webcam_local_template.py`, `hand_features.py` | 손 좌표 처리와 특징 추출 |
| `06z_diagnose_off_okay_onehand.py` | 분류 참조 복원·진단 |
| `06cd_evaluate_onehand_sign_nosign_knn_dev.py` | SIGN/NO-SIGN 특징 계산·평가 |
| `template_runtime_v3/` | 분류 템플릿과 한 손 보정 자료 |
| `reference_data/`, `new5_reference_v3/` | 기준 수어 참조 자료 |
| `diagnostics_v3/` | 분류 단계에서 참조하는 모델과 분석 자료 |
| `tools/` | C++ 비교용 입력·예상 결과 및 MediaPipe 그래프 생성 도구 |
| `tests/` | 저장된 입력의 결과 비교와 모듈 경로 검사 |

숫자로 시작하는 파일명은 기존 처리 단계의 이름입니다. `07g`가 `06u`, `06z`, `06cd`를
불러오므로 이전 번호의 파일도 사용합니다. 네 데이터 폴더는 스크립트와의 상대 위치를 유지합니다.

## 저장된 입력으로 검사

저장소 루트에서 실행합니다. 카메라·MQTT·MediaPipe 없이 저장된 참조 입력과 결과를 비교합니다.

```sh
python -m pip install -r SW/rpi4_sign_python/requirements-test.txt
python -m unittest discover -s SW/rpi4_sign_python/tests -p 'test_*.py' -v
```

영상 전처리 결과를 Python 분류기로 확인할 때는 다음 도구를 사용합니다.

```sh
python SW/rpi4_vision_atlas/offline_sign_pipeline.py /path/to/hand-frames.jsonl
```

이 검사는 저장된 입력에 대한 비교입니다. 카메라 인식 정확도와 Pi4 성능은 장치에서 별도로 측정합니다.

## 결과 생성 도구

```sh
python SW/rpi4_sign_python/tools/class_15_frozen_expected_export.py
python SW/rpi4_sign_python/tools/hand_input_frozen_expected_export.py
```

도구의 출력 위치는 `SW/rpi4_sign_cpp/tests/fixtures/`입니다. 실행하면 해당 예상 결과가
갱신되므로 변경 내용을 확인한 뒤 저장합니다. `sign_runtime_frozen_expected_export.py`와
`temp_positive_full_python_fixture_export.py`는 별도 원본 입력 `raw_test_data/`도 필요합니다.
원본 영상·녹음·개인 데이터는 Git에 추가하지 않습니다.

실시간 Python 카메라 입력과 `export_mediapipe_hands_canonical_graph.py`에는 MediaPipe가
추가로 필요합니다. 그래프 생성 기준 버전은 0.10.21입니다.
