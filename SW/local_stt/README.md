# 기기 내 실시간 음성 자막

한국어 스트리밍 Zipformer를 sherpa-onnx로 실행한다. 마이크의 16 kHz 모노
PCM을 연속 처리하며, 문장 전체를 매번 다시 분석하지 않는다. Kiwi는 인식된
글자의 띄어쓰기만 처리한다. 특정 문장을 맞추기 위한 치환 사전은 없다.

모델 설치에는 인터넷이 필요하다. 설치 후 음성 인식은 오프라인으로 실행된다.
서버는 `127.0.0.1:8766`에만 바인딩하고 음성·자막을 파일이나 로그에 저장하지
않는다. MQTT Topic과 JSON 규격은 변경하지 않는다.

## 설치

Python 3.12, Linux aarch64에서 다음 순서로 설치한다. CSI 가상환경과 분리한다.

```sh
cd /opt/safehub-stt
python3 -m venv venv
venv/bin/python3 -m pip install --no-cache-dir -r requirements.txt
venv/bin/python3 download_model.py
venv/bin/python3 server.py
```

앱 연결 설정의 STT 주소는 `http://127.0.0.1:8766`이다. 앱과 서버가 같은
장치에서 실행되어야 한다. 기존 팀 서버의 파일 업로드 API도 앱에서 지원하지만,
현재 배포 설정에서는 로컬 스트리밍을 사용한다. TTS 설정과는 별개다.

일반 Linux는 `safehub-stt.service`를 systemd에 설치해 활성화한다. 시험한
ATLAS 이미지에서는 `/etc`가 읽기 전용이므로 단위 파일을
`/data/share/usr/lib/systemd/system/`에 설치하고 같은 경로의
`multi-user.target.wants/`에 링크한다. `systemctl daemon-reload` 후 시작한다.
부팅 시 모델 준비 전에는 앱이 연결을 재시도한다.

## 연결 규격

- `GET /health`: 준비 상태, `streaming_protocol: safehub.pcm.v1` 반환.
- `WS /stt/stream`: 16-bit little-endian PCM, 모노, 16 kHz. 프레임은 최대 6,400 bytes.
- 서버는 `ready` 후 `ack` 또는 `caption`을 반환한다. `bytes`는 처리한 바이트 수다.
- `caption`: `segment`, `epoch`, `text`, `final`. 같은 segment의 임시 자막을 덮어쓴다.
- `reset`과 새 `epoch`는 자막 지우기 이후 늦게 도착한 결과를 구분한다.
- 마이크 연결은 하나만 허용한다. 앱은 미처리 음성을 최대 2초로 제한하며,
  응답 지연·연결 종료 시 마이크를 정리하고 다시 연결한다. 일시정지는 재시도를 취소한다.
- 인식 후 무음 0.8초 또는 최대 20초에서 문장을 나눈다. 임시 자막은 그 전에 표시된다.

## 확인한 범위 — 2026-10-04

RPi5 8GB, ATLAS 26.06.0-246, 두 개 추론 스레드, int8 모델로 확인했다.
기존에 생성해 둔 5.232초 시험 음성의 계산 시간은 1.222초, 같은 음성에
합성 잡음을 더한 경우는 1.254초였다. 실제 속도로 WebSocket에 보낸 시험에서는
첫 자막이 각각 0.780초, 0.799초에 도착했다. USB 마이크 발화부터 화면 표시까지의
지연 보장이나 실제 환경 정확도 측정은 아니다.

깨끗한 시험 문장은 글자 기준으로 일치했지만 합성 잡음에서는 ‘테스트’가
‘텍스트’로 인식됐다. 실제 발화의 정확도·멀리 떨어진 마이크·장시간 운전은
추가 평가가 필요하다. RPi4 성능은 측정하지 않았다.

Flutter에서는 중간 자막 갱신, 일시정지, 시작 중 취소, 자막 지우기, 끊김 복구,
오디오 대기량 제한과 화면 크기를 검사했다. 실물 Pi에서는 새 서버 연결과
마이크 입력에 따른 화면 자막 갱신을 확인했다. CSI 서비스와 사용자 기록은 유지한다.

## 출처

- [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx): Apache-2.0.
- [한국어 Zipformer 174m](https://huggingface.co/kangkyu/icefall-asr-ko-streaming-zipformer-174m):
  모델 카드 Apache-2.0, revision `f0e73b1653c3ea75898c6d949dd71c690c9121da`.
  다운로드 스크립트는 세 가중치와 토큰 파일의 SHA-256을 검증한다.
- [kiwipiepy](https://github.com/bab2min/kiwipiepy): 설치한 0.23.1 패키지의
  LICENSE.txt는 LGPL-2.1-or-later를 명시한다. 라이선스와 모델 파일을 보존한다.
  수정하지 않은 라이브러리를 별도 Python 패키지로 사용한다.

모델·가상환경·개인 음성 파일은 Git에 넣지 않는다. 의존성 버전 변경 시
설치와 인식 시간, 메모리 사용량을 다시 확인한다.
