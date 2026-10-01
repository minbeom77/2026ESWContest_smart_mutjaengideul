# SafeHub Voice Server

FastAPI 기반 한국어 STT·TTS 서버.
마이크 녹음과 음성 재생은 SafeHub 앱에서 담당한다.

- STT: faster-whisper, 기본 base 모델, CPU/int8
- TTS: edge-tts, ko-KR-SunHiNeural, 인터넷 필요

## 검증 상태

Windows 기존 가상환경에서 서버 함수 테스트 8개 통과.
RPi5/Atlas OS 설치 호환성, 처리 속도 및 장비 연동은 미검증.
requirements.txt는 기존 Windows 환경의 패키지 버전 기록이다.

## 설치

이 README가 있는 SW/voice_server 폴더에서 실행한다.

Windows PowerShell:

```powershell
python -m venv .venv
& ".\.venv\Scripts\python.exe" -m pip install -r requirements.txt
```

Linux/RPi5 설치 시도:

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
```

RPi5 설치 성공 여부는 실제 장비에서 확인해야 한다.

## 실행

Windows PowerShell:

```powershell
$env:WHISPER_MODEL = "base"
& ".\.venv\Scripts\python.exe" -m uvicorn server:app --host 127.0.0.1 --port 8000 --workers 1
```

Linux:

```bash
WHISPER_MODEL=base .venv/bin/python -m uvicorn server:app --host 127.0.0.1 --port 8000 --workers 1
```

다른 장치에서 접속할 때는 --host 0.0.0.0으로 실행하고,
앱 서버 주소를 http://서버장치IP:8000으로 설정한다.
127.0.0.1은 앱과 서버가 같은 장치에서 실행될 때 사용한다.

프로세스별 모델 중복 로딩을 피하기 위해 --workers 1을 사용한다.
STT 동시 요청은 프로세스 안에서 순차 처리한다.

## API

### GET /health

서버 응답 가능 여부와 STT 모델 상태를 반환한다.

- status: ok
- stt_model_state: not_loaded / loading / ready / failed
- tts_requires_internet: true

status=ok는 모델 준비나 외부 TTS 연결 성공을 보장하지 않는다.
모델은 첫 STT 요청 때 로딩한다.
첫 모델 다운로드에는 인터넷이 필요할 수 있다.
모델 로딩 실패 후 다음 STT 요청에서 다시 시도한다.

### POST /stt

multipart 필드 audio로 음성 파일을 전송한다.

- 성공: {"text": "인식 결과"}
- 빈 파일: 400
- 인식 결과 없음: 422
- 모델 준비 실패: 503
- 기타 변환 실패: 500

### POST /tts

JSON {"text": "읽을 문장"}을 전송한다.

- 성공: audio/mpeg
- 빈 문장: 400
- 외부 TTS 실패 또는 빈 음성: 502
- 음성 생성 30초 초과: 504

잘못된 요청 형식은 FastAPI 검증에 따라 422를 반환한다.

## 테스트

SW/voice_server 폴더에서 의존성이 설치된 Python으로 실행한다.

```bash
python tests/test_server.py
```

실제 모델과 TTS를 대체해 동시 처리, 오류 코드 및 임시 파일 삭제를 검사한다.
실제 HTTP 통신, 인식 정확도, MP3 재생 및 RPi5 성능은 별도 검사가 필요하다.
