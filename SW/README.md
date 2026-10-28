# 소프트웨어 구성

| 구성 | 폴더 | 역할 |
|---|---|---|
| 화면 | [safehub_scenario](safehub_scenario) | 현재 Flutter 대시보드 |
| Pi4 영상 | [rpi4_vision_atlas](rpi4_vision_atlas) | 카메라·손 검출·영상 전송 |
| Pi4 수어 | [rpi4_sign_cpp](rpi4_sign_cpp) | 실시간 C++ 분류 |
| Python 수어 | [rpi4_sign_python](rpi4_sign_python) | 기준 구현·참조 데이터·비교 도구 |
| 장치 연결 | [rpi5_hub](rpi5_hub), [uno_bridge](uno_bridge) | MQTT 라우팅·수어 단축키·시리얼 제어 |
| 음성 입력 | [local_stt](local_stt) | 한국어 스트리밍 자막 |
| 음향 분석 | [yamnet_alarm](yamnet_alarm) | 사이렌·경보음 분류 |
| 음성 출력 | [tts_server](tts_server) | 문장 음성 합성 |
| 문맥 설명 | [fasttext_context](fasttext_context) | 방송 내용 분류와 요약 |
| Wi-Fi 센싱 | [wifi_sensing](wifi_sensing) | CSI 수집·전처리·학습·추론 |
| 실행 환경 | [atlas_boot](atlas_boot), [windows_preview](windows_preview) | ATLAS 시작 구성·Windows 미리보기 |

전체 구성과 사용 예시는 [프로젝트 README](../README.md), 모델·SDK 준비 사항은
[실행 자료 안내](../docs/REPRODUCIBILITY.md)를 참고하세요.
