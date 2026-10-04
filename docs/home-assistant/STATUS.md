# Home Assistant · LG ThinQ 연동 상태

확인일: 2026-10-04. 대상: ATLAS 26.06.0-246, Raspberry Pi 5.

## 설치

Home Assistant 2026.9.4를 별도 Docker 25.0.9 데몬으로 설치했다.
기존 SafeHub UI·CSI·MQTT 서비스를 유지한다.

| 항목 | 설정 |
| --- | --- |
| 서비스 | `homeassistant-docker.service` |
| Docker 소켓 | `/run/homeassistant-docker.sock` |
| 컨테이너 | `homeassistant` |
| 웹 포트 | `8123` |
| 설정 폴더 | `/opt/safehub-homeassistant/config` |
| Docker 데이터 | `/mnt/rawopt/homeassistant/docker` |
| 네트워크 | host, privileged 및 하드웨어 전달 없음 |
| 재시작 | 서비스 부팅 연결, 컨테이너 `unless-stopped` |

사용한 이미지: `ghcr.io/home-assistant/home-assistant@sha256:3e6710a7ab2a61311d9d899b719f6c3657791c63e8f4942cec4ebc42401d6b76`.
ATLAS의 AppArmor ABI에 맞춘 Docker 기본 정책을 적용했다.
설정 검사, 서비스 재시작 후 컨테이너 복구, 웹 응답을 확인했다.
Home Assistant 설치 후 보드 전체 재부팅은 별도로 검증하지 않았다.

현재 보드 IP의 `http://<보드-IP>:8123`으로 접속한다. 네트워크를 바꾸면 주소도
달라질 수 있다. 토큰, `.storage`, 계정 설정, 개인 네트워크 프로필은 저장소에
포함하지 않는다. 이 문서는 설치 상태 기록이며 새 SD카드용 자동 설치기는 아니다.

## 연동 범위

- Home Assistant 소유자 설정과 LG ThinQ 토큰 설정은 완료했다.
- 인증된 ThinQ 기기 목록 조회에서는 기기 0개를 확인했다.
- ATLAS Cloud Gateway의 계정 등록은 미완료다. Bluetooth 연결과 등록용 Wi-Fi
  표시를 일부 확인했지만, Wi-Fi 접속 실패와 검색 불안정이 남아 있다.
- 학교 Wi-Fi에서 휴대폰 핫스팟으로 옮겨 재시험 중이며 원인은 확정하지 않았다.
- Cloud Gateway가 등록되더라도 Home Assistant의 LG ThinQ 지원 기기로
  노출되는지는 별도로 확인해야 한다. 세탁기나 가상 세탁기 지원을 의미하지 않는다.
- SafeHub의 세탁 완료 이벤트 수신과 화면 알림은 아직 연결하지 않았다.
  MQTT Topic과 JSON 필드는 변경하지 않았다.

## 다음 확인

ThinQ 앱에서 계정 등록을 완료하고 기기 목록을 다시 확인한다. Home Assistant에서
지원되는 기기·엔티티가 실제로 생성되는지 확인한 후, 팀의 이벤트 명세에 맞춰
세탁 완료 알림을 연결하고 실제 상태 변화로 시험한다.

참고: [Home Assistant LG ThinQ 지원 기기](https://www.home-assistant.io/integrations/lg_thinq/#supported-devices).
