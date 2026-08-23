# 첫 CSI 검증 실험

## 배치

```text
[2.4 GHz 공유기] -------- 1~3 m -------- [ESP-WROOM-32]
                         ↑
                   사람이 움직일 구역
```

보드와 공유기의 위치·높이·방향은 실험 중 바꾸지 않습니다. 처음에는 안테나가 가려지지 않게 두고, 사람은 두 장치 사이 또는 두 장치를 잇는 선 근처에서 움직입니다.

## 세 세션

각 세션을 별도 CSV로 저장합니다.

```bash
python csi_capture.py --port COM5 --label empty --duration 60
python csi_capture.py --port COM5 --label still --duration 60
python csi_capture.py --port COM5 --label moving --duration 60
```

Linux 예시에서는 `COM5` 대신 `COM5`을 사용합니다.

1. `empty`: 방을 비우고 60초
2. `still`: 같은 위치에 앉거나 누워 최대한 정지하고 60초
3. `moving`: 팔 흔들기, 몸 돌리기, 걷기 등 큰 움직임을 60초

## 성공 판정

- 유효 수집률이 설정값의 약 80% 이상
- 시퀀스 누락이 10% 이하
- `moving` 세션의 움직임 점수 중앙값 또는 상위 95% 값이 `empty`보다 뚜렷하게 큼
- 같은 세션 안에서 CSI raw 길이가 대부분 일정함

이 기준은 의료 정확도 기준이 아니라, 다음 단계인 존재·움직임 감지 개발로 넘어가기 위한 엔지니어링 기준입니다.

## 분석

```bash
python analyze_capture.py sessions/csi_YYYYMMDD_HHMMSS_empty.csv
python analyze_capture.py sessions/csi_YYYYMMDD_HHMMSS_still.csv
python analyze_capture.py sessions/csi_YYYYMMDD_HHMMSS_moving.csv
```
