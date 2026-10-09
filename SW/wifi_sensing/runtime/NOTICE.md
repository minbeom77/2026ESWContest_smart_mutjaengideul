# CSI 런타임 출처와 변경 범위

이 디렉터리는 2026-10-04 노트북 WifiSensing2-src에서 복사한 실행용 Python 코드에서 시작했습니다. LOCAL_SOURCE_MANIFEST.json은 당시 29개 파일의 SHA-256을 보존합니다. 현재 변경한 soom_engine.py는 LOCAL_MODIFICATIONS.json에 별도로 기록하며, 복사 당시 파일은 reference/soom_engine.py에 그대로 보존합니다.

- 참조 프로젝트: https://github.com/Dongbang-Yeuijiguk/2025ESWContest_smart_3019
- 원 저작권: Copyright (c) 2025 Dongbang Yeuijiguk
- 라이선스: MIT, 전문은 LICENSE에 보존합니다.
- 원본 커밋과 파일별 해시: soom_upstream/manifest.json
- 현재 전처리: 52채널, db4 DWT, 표준화, PCA 1성분, FFT 저역 통과. 현재 모델 입력은 4초/240시점입니다.
- 사용자 정의 행동, 측정 회차별 평가 분리, 기록 관리, NumPy 추론은 노트북 앱에서 이어받습니다.
- 상위 bridge.py/stream.py와 Flutter 화면은 이번 통합을 위해 추가했습니다. 원본 파이프라인의 숫자와 모델 구조는 변경하지 않았습니다.

I/Q 입력 변환은 JSON 문자열 생성·AST 재파싱 대신 NumPy 배열에서 52채널 진폭을 계산합니다. int64 변환, 채널 선택, 타임스탬프 반올림 및 특수 입력의 기존 처리 방식은 유지합니다. DWT·표준화·PCA·FFT와 CNN 소스는 변경하지 않았습니다. 서비스 시작 시 보존 원본과 현재 소스의 해시를 함께 검사합니다. 모델 ZIP에도 원본 입력 변환기와 변경 명세·라이선스를 포함합니다. ZIP은 실행에 필요한 파일만 담으므로 전체 29개 런타임 파일의 설치본은 아닙니다.

Python/PyTorch/NumPy/SciPy/scikit-learn/PyWavelets/pandas/pyserial 등의 라이선스는 THIRD_PARTY_NOTICES.txt를 참고하세요. 개인 측정 기록·모델·Wi-Fi 설정은 이 소스에 포함하지 않습니다.
