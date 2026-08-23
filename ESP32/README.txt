ESP32 Wi-Fi CSI 실험 도구 - 기능별 빠른 안내
================================================

[1. 펌웨어]
- 위치: firmware/
- 기능: ESP32-WROOM-32를 2.4 GHz Wi-Fi에 연결하고 CSI_DATA를 시리얼로 출력
- Wi-Fi 정보는 firmware/sdkconfig에만 저장하며 GitHub에는 올리지 않음

[2. PC 데이터 수집]
- 위치: pc/csi_capture.py
- 기능: CSI_DATA 파싱, CSV 저장, 프레임·파싱 오류 통계 계산

[3. 실험 UI]
- 위치: pc/experiment_ui.py, pc/experiment_ui_v2.py
- 실행: 11_EXPERIMENT_UI_V2.cmd
- 기능: 행동 분류, 실시간 히트맵, 움직임 점수, CSV·JSON 저장

[4. 결과 관리]
- 기능: 완료 실험 조회, 여러 실험 비교, 라벨 수정, 휴지통 이동
- 전체 목록: pc/sessions/experiment_catalog.csv
- sessions 데이터는 개인정보와 대용량 원본을 포함할 수 있어 GitHub에 올리지 않음

[5. Windows 실행 순서]
- 01~03: PC 환경과 COM 포트 확인
- 04~07: 펌웨어 설정·빌드·플래시·모니터
- 08~11: CSI 저장·파서 테스트·실험 UI

[6. 공개 저장소 제외 항목]
- firmware/sdkconfig, firmware/sdkconfig.old
- firmware/build/
- pc/.venv/, pc/__pycache__/
- pc/sessions/
- *.csv, *.json 실험 결과와 백업 파일

상세 설명은 README.md와 docs/ 폴더를 참고하세요.
