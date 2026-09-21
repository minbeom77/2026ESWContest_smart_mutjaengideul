# SafeHub MQTT 통신 규격 v1.2 전환 안내

> 작성 목적: 현재 수어 C++ 런타임, RPi5 Hub, Flutter UI, Wi-Fi CSI 모듈과 ESP32 액추에이터를 기존 구현을 버리지 않고 하나의 규격으로 통합한다.
>
> 상태: 팀 검토용 초안  
> 기준 브랜치: `feature/SW`  
> 기존 규격: `config/topics.json` v1.1

## 1. 결론

기존 HW 코드를 전부 다시 작성하지 않는다.

- HW팀이 이미 구현한 CSI 이벤트와 LED·베드셰이커 토픽은 유지한다.
- 현재 RPi4 C++ 수어 번역 토픽과 학진이의 수어 단축키 토픽을 v1.2에 추가한다.
- 기존 `vision_landmarks` 토픽은 즉시 삭제하지 않고 deprecated로 표시한다.
- 전환 기간에는 기존 payload도 수신하되 경고 로그를 남긴다.
- 같은 장치 명령을 구형 토픽과 신형 토픽으로 동시에 발행하지 않는다. 중복 작동 위험이 있다.

## 2. 최종 시스템 역할

| 노드 | 역할 |
|---|---|
| RPi4 | V4L2 카메라, Palm/HandPose ONNX 추론, C++ KNN 수어 분류, 번역 결과 발행 |
| RPi5 | Mosquitto Broker, Python Hub, EventManager, 수어 단축키, Flutter UI |
| CSI Runtime | ESP32/C6 시리얼 CSI 수집, 전처리, CNN 판정, CSI 이벤트 발행 |
| ESP32 액추에이터 | LED·베드셰이커 명령 구독 및 GPIO 제어 |
| Flutter UI | 수어 번역과 안전 이벤트 표시, 사용자 설정 명령 발행 |

최종 Broker는 RPi5에서 실행한다.

- Host: RPi5 고정 IP 권장
- Port: `1883`
- 개발 중 PC Broker 사용은 허용하지만 최종 데모 설정에는 남기지 않는다.

## 3. v1.2 Topic 목록

| 구분 | Topic | QoS | Retain | 발행 | 구독 | 상태 |
|---|---|---:|---|---|---|---|
| 수어 번역 | `safehub/vision/livingroom/translation` | 1 | false | RPi4 | RPi5 Hub, Flutter | 정식 추가 |
| 침실 CSI | `safehub/csi/bedroom/event` | 1 | false | CSI Runtime | RPi5 Hub, Flutter | v1.1 유지 |
| 화장실 CSI | `safehub/csi/bathroom/event` | 1 | false | CSI Runtime | RPi5 Hub, Flutter | v1.1 유지 |
| 단축키 설정 | `safehub/config/sign_shortcut/command` | 1 | false | Flutter/관리 도구 | RPi5 Hub | 정식 추가 |
| 일반 기기 제어 | `safehub/control/{room}/{device}/command` | 1 | false | RPi5 Hub | 기기 노드 | 정식 추가 |
| LED 안전 제어 | `safehub/actuator/led/command` | 1 | false | RPi5 Hub | ESP32 | v1.1 유지 |
| 베드셰이커 | `safehub/actuator/bedshaker/command` | 1 | false | RPi5 Hub | ESP32 | v1.1 유지 |
| 생존 확인 | `safehub/system/heartbeat` | 0 | false | 각 노드 | RPi5 Hub | 선택 기능 |
| 손 관절 | `safehub/vision/livingroom/landmarks` | 0 | false | RPi4 | RPi5 | deprecated |

### Topic 구분 원칙

- `safehub/control/...`은 에어컨처럼 일반 스마트 가전 제어에 사용한다.
- `safehub/actuator/...`는 안전 경보용 LED와 베드셰이커에 사용한다.
- 두 namespace를 억지로 하나로 합치지 않는다.
- HW팀이 v1.1 액추에이터 토픽을 이미 구현했다면 그대로 유지할 수 있다.

## 4. Payload 계약

### 4.1 수어 번역

Topic:

```text
safehub/vision/livingroom/translation
```

최소 호환 payload:

```json
{
  "text": "아프다"
}
```

확장 payload를 발행할 경우에도 `text`는 반드시 유지한다.

```json
{
  "schema_version": "1.2",
  "message_id": "UUID",
  "device": "rpi4_vision",
  "event": "sign_translation",
  "class_id": 7,
  "text": "아프다",
  "timestamp": 1789960000
}
```

수신자는 알 수 없는 추가 필드를 무시해야 한다.

### 4.2 CSI 안전 이벤트

Topic:

```text
safehub/csi/bedroom/event
safehub/csi/bathroom/event
```

Payload:

```json
{
  "message_id": "UUID",
  "device": "csi_bedroom",
  "event": "fall_detected",
  "confidence": 0.92,
  "priority": 9,
  "timestamp": 1789960000
}
```

필수 조건:

- `message_id`: 이벤트마다 새 UUID
- `device`: 발행 노드 식별자
- `event`: 합의된 이벤트 이름
- `confidence`: 0 이상 1 이하
- `priority`: 정수 1 이상 10 이하
- `timestamp`: Unix timestamp 정수

현재 CSI 추론이 Raspberry Pi에서 수행되므로 MQTT 발행 주체는 ESP32 자체가 아니라 `CSI Runtime`일 수 있다. `device` 필드로 실제 장치를 구분한다.

전환 기간에는 `message_id`가 없는 기존 payload도 수신할 수 있지만 중복 방지를 보장하지 않으며 경고를 기록한다.

### 4.3 수어 단축키 설정

등록:

```json
{
  "operation": "register",
  "sign": "에어컨",
  "room": "livingroom",
  "device": "aircon",
  "action": "toggle"
}
```

삭제:

```json
{
  "operation": "remove",
  "sign": "에어컨"
}
```

### 4.4 일반 기기 제어

Topic 예시:

```text
safehub/control/livingroom/aircon/command
```

Payload:

```json
{
  "source": "sign_shortcut",
  "action": "set_power",
  "power_on": true
}
```

기존 학진이 코드와 Flutter UI의 계약을 유지한다.

### 4.5 LED 안전 제어

Topic:

```text
safehub/actuator/led/command
```

Payload:

```json
{
  "message_id": "UUID",
  "device": "rpi5_hub",
  "event": "led_command",
  "action": "blink",
  "timestamp": 1789960000
}
```

HW팀이 지원하는 `action` 값은 아래 표에 기록하고 팀 합의 없이 새 값을 추가하지 않는다.

| action | 동작 | 구현 여부 |
|---|---|---|
| `on` | 계속 켜기 | HW팀 확인 |
| `off` | 끄기 | HW팀 확인 |
| `blink` | 비상 점멸 | HW팀 확인 |

### 4.6 베드셰이커 제어

Topic:

```text
safehub/actuator/bedshaker/command
```

Payload:

```json
{
  "message_id": "UUID",
  "device": "rpi5_hub",
  "event": "bedshaker_command",
  "action": "on",
  "duration_sec": 10,
  "timestamp": 1789960000
}
```

`duration_sec`가 지나면 ESP32가 네트워크 상태와 관계없이 자체적으로 출력을 꺼야 한다.

## 5. QoS 및 중복 처리

- 수어 번역, CSI 이벤트, 단축키 설정, 기기 제어는 QoS 1을 사용한다.
- 카메라 영상은 MQTT로 전송하지 않는다. TCP 5000 스트림을 사용한다.
- Heartbeat처럼 다음 메시지가 이전 메시지를 대체하는 데이터만 QoS 0을 사용한다.
- QoS 1 메시지는 중복 전달될 수 있다.
- CSI 이벤트와 안전 액추에이터 명령은 `message_id` 기준으로 중복 실행을 막는다.
- 수어 단축키에는 기존 cooldown과 함께 `message_id` 중복 방지를 추가할 수 있다.
- 모든 Topic은 `retain=false`를 기본으로 한다.

## 6. 기존 구현을 살리는 전환 방법

### 단계 A: 규격 동결

팀원이 다음 정보를 공유한다.

- 실제 사용 보드: ESP32-WROOM-32, C3, C6 중 무엇인지
- 현재 발행·구독 Topic
- 실제 JSON 예시 한 건
- QoS와 retain 설정
- LED·베드셰이커 GPIO 및 지원 action
- CSI 판정 위치: ESP32, RPi4, RPi5 중 어디인지

이 확인 전에는 HW 펌웨어를 다시 작성하지 않는다.

### 단계 B: 수신 호환

RPi5 Hub가 기존 v1.1 payload와 v1.2 payload를 모두 받을 수 있게 한다.

- 필수 핵심 필드가 맞으면 처리한다.
- 빠진 선택 필드는 기본값을 사용하거나 경고한다.
- 범위를 벗어난 `priority`와 잘못된 JSON은 거부한다.
- 잘못된 메시지 한 건 때문에 MQTT loop를 종료하지 않는다.

### 단계 C: 발행 규격 통일

- RPi4 수어 번역은 QoS 1 유지
- RPi5 Hub와 Flutter의 수어 구독도 QoS 1로 변경
- CSI Runtime에 MQTT publisher 추가
- RPi5 Hub에 안전 이벤트 정책과 액추에이터 publisher 추가
- ESP32는 기존 v1.1 안전 액추에이터 Topic을 유지

### 단계 D: 실기기 E2E 검증

각 경로를 독립적으로 검사한다.

1. RPi4 수어 → Broker → Flutter 문구
2. RPi4 수어 → Broker → RPi5 단축키 → 에어컨 명령
3. CSI Runtime 낙상 → Broker → RPi5 EventManager
4. 낙상 → LED 명령 → ESP32 GPIO
5. 낙상 → 베드셰이커 명령 → 제한 시간 후 자동 OFF
6. 모든 장치 재부팅 후 자동 재연결

## 7. 팀원별 작업

### 민범

- [ ] RPi4 실시간 수어 인식 완료
- [ ] 수어 발행 Topic과 payload 유지
- [ ] 최종 Broker 주소를 RPi5로 변경
- [ ] `feature/rpi4-live-sign-mqtt`를 최신 `feature/SW` 기준으로 갱신
- [ ] `config/topics.json` v1.2 반영 PR 준비
- [ ] 전체 E2E 테스트 결과 기록

### 학진

- [ ] RPi5 Hub 수어 구독 QoS를 0에서 1로 변경
- [ ] Flutter 수어 구독 QoS를 0에서 1로 변경
- [ ] 기존 `{"text":"..."}` payload 호환 유지
- [ ] CSI `message_id` 중복 처리 구현
- [ ] CSI 이벤트에서 LED·베드셰이커 명령으로 연결할 정책 구현
- [ ] 단축키 저장·재시작 복원 유지
- [ ] RPi5 `main.py` 자동 실행 서비스 준비

### HW팀

- [ ] 실제 보드 종류와 역할 공유
- [ ] 현재 발행·구독 Topic과 JSON 예시 공유
- [ ] CSI Runtime이 어느 장치에서 실행되는지 확정
- [ ] CSI 결과를 v1.2 payload로 발행하거나 어댑터 입력 제공
- [ ] LED가 v1.1 Topic을 구독하는지 확인
- [ ] 베드셰이커가 v1.1 Topic을 구독하는지 확인
- [ ] QoS 1 중복 명령 방지
- [ ] 베드셰이커 로컬 타이머 OFF 구현
- [ ] Wi-Fi/MQTT 끊김 후 자동 재연결 확인

## 8. 팀원이 보내야 할 확인 자료

다음 형식으로 답하면 된다.

```text
[장치]
보드:
역할:
실행 위치:

[MQTT]
Broker:
Publish Topic:
Subscribe Topic:
QoS:
Retain:

[Payload 예시]
{실제 JSON 한 건}

[하드웨어]
LED GPIO:
Bed Shaker GPIO:
지원 action:
자동 OFF 여부:

[검증]
실기기 확인:
남은 문제:
```

## 9. 병합 순서

1. 이 문서와 `topics.json` v1.2를 팀이 검토한다.
2. 학진이·HW팀이 현재 구현 정보를 공유한다.
3. 규격을 확정한 후 코드 수정 PR을 각각 만든다.
4. 단위 테스트와 Mock MQTT 테스트를 통과시킨다.
5. RPi4·RPi5·ESP32 실기기 E2E 테스트를 수행한다.
6. 통합 브랜치에 병합한다.
7. 마지막에 `develop`으로 병합한다.

## 10. 금지 사항

- 확인 없이 `feature/HW` 전체를 바로 병합하지 않는다.
- 기존 HW Topic을 먼저 삭제하지 않는다.
- 동일 장치 명령을 구형·신형 Topic으로 동시에 발행하지 않는다.
- 실기기 검증 전 "낙상 감지 완료" 또는 "자동 제어 완료"라고 표시하지 않는다.
- Wi-Fi 비밀번호와 실제 CSI 원본 데이터를 공개 저장소에 커밋하지 않는다.
