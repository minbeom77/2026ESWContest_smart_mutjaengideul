# SafeHub 통합 앱

RPi4 카메라와 수어 번역 결과, CSI 상태, 음성 자막과 재난·안전 알림을 표시하는
Flutter 앱이다. 실제 서비스 주소가 없으면 연결 대기로 표시한다. 모의 입력은
`APP_LOCAL_PREVIEW=true`로 빌드한 체험 모드에서만 사용한다.

ATLAS 배치는 [부팅 설정](../atlas_boot/README.md), 로컬 음성 자막은
[STT 서버](../local_stt/README.md), 주소 설정은
[실제 모드 안내](../../docs/wifi-csi/REAL_MODE.md)를 참고한다.

## 호스트에서 검사

ATLAS 전용 플러그인 경로가 없는 PC에서는 앱 소스를 별도 폴더로 복사한다.
준비 스크립트는 ATLAS의 두 path 의존성만 제외하고 앱 코드와 테스트를 복사한다.
아래 명령은 저장소 루트에서 실행하며 출력 폴더는 새 폴더여야 한다.

```sh
python3 SW/csi_bridge/export_contract_fixture.py --out SW/safehub_app/test/fixtures/csi_bridge_contract.json
python3 SW/wifi_sensing/prepare_ui_tests.py --full /tmp/safehub-ui-tests
cd /tmp/safehub-ui-tests
flutter pub get
flutter test --reporter expanded
flutter analyze --no-pub
```

이 검사는 ATLAS 플러그인의 권한, 실제 마이크·스피커, 무선 연결이나 모델 정확도를
검증하지 않는다. [장치 검증 기록](../../docs/wifi-csi/ATLAS_VALIDATION.md)에
시험 환경과 미확인 항목을 구분해 기록한다.

## 현재 제한

- 안전 이벤트 중복 방지는 최근 ID 2,000개에 한정하며 앱 재시작 후 초기화된다.
  ID 없는 기존 메시지는 호환 수신하되 중복 여부를 판별하지 않는다.
- [CSI 어댑터](../csi_bridge/README.md)는 오프라인 변환과 계약 검사 단계다.
  실제 낙상 결과를 MQTT로 발행하거나 베드셰이커를 작동시키지 않는다.
- ATLAS TTS 재생 실패 시 네이티브 동기 대기가 입력을 막는 문제가 남아 있다.
  Dart의 5초 응답 제한은 그 대기를 취소하지 않는다.
  [재생 권한과 임시 중단 방법](atlas/README.md)을 참고한다.
