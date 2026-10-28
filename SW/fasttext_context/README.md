# fastText 문맥 설명 서비스

생성형 LLM 대신 자막·사건 문맥을 짧게 설명하는 loopback HTTP 서비스입니다.
현재 UI의 기본 모델 이름은 `fasttext-fire-screen`입니다. 실제 경보와 도움 화면은
이 서비스의 응답을 기다리지 않으며 모델 점수를 실제 위험 확률로 사용하지 않습니다.

## 소스와 API

- `classifier.py`: 부정·훈련·예방·오보와 독립 문장의 위험 표현을 구분하는 규칙.
  줄바꿈은 규칙에서 보존하고 native fastText 입력만 한 줄로 만듭니다.
- `server.py`: `127.0.0.1:9380`의 `/health`, `/classify`, `/v1/chat/completions`.
  시작할 때 **이미 확보한 모델**을 `--model`로 지정해야 합니다. 학습·모델 다운로드는 하지 않습니다.
- `safehub-fasttext.service`: 검토용 장치 경로/실행 설정. 이번 작업에서 설치·시작하지 않았습니다.
- [공통 방송 사례](../safehub_scenario/test/fixtures/broadcast_cases.json): Python과 Dart가 함께 검사하는 20사례.

문장 경계가 없는 ASR, 오인식·인용·복잡한 부정문을 완전히 이해하는 구현은 아닙니다.
음향 경보음 검출이나 화재 확정 센서도 아닙니다. 사용자는 원문과 실제 상황을 확인해야 합니다.

## 장비·모델 없는 검사

저장소 루트에서 Python 3.12로 실행합니다. 표준 라이브러리 기반 검사에는
실제 fastText 패키지나 사용자 모델이 필요하지 않습니다.

```sh
python3 -m unittest discover -s SW/fasttext_context/tests -p 'test_*.py' -v
```

9개 검사는 가짜 모델을 주입한 규칙·잘못된 HTTP 요청·서버 복구 검사입니다.
실제 모델의 정확도/로드 호환 검증과 구별합니다.

## 호스트 런타임 준비

검증한 조합은 Linux x86_64 CPython 3.12, fastText 0.9.3, NumPy 1.26.4,
GCC/G++ 14.2입니다. Bash·uv·GCC/G++가 준비된 호스트에서:

```sh
bash SW/fasttext_context/tools/install_host.sh /tmp/safehub-fasttext-venv
/tmp/safehub-fasttext-venv/bin/python SW/fasttext_context/tools/check_runtime.py
```

설치 도구는 저장소 밖 venv만 허용합니다. `CC=gcc CXX=g++`를 명시해 이 클라우드 Python의
실행 불가능한 기본 clang++ 선택 문제를 해결했습니다. 이 결과는 ARM64 보장이나 장치 서비스 설치가 아닙니다.
확보한 기존 모델의 로드·분류·해시만 확인하려면 probe에 `--model <기존 모델 경로>`를 줄 수 있습니다.
실제 모델 HTTP 검사는 별도이며 probe가 서버를 시작하지 않습니다.

## 현재 미확인 의존성

`fire_screen_model.bin`은 공개 Git에 포함하지 않습니다. #14 작성자 장치 기록에는
`/data/safehub/fasttext/fire_screen_model.bin`, SHA256
`5691ceb3daa177053dc68cc57e2622ec83cc9c9e90cb8d10de2b05751fef512d`가 보고돼 있습니다.
이번 클라우드의 실제 파일·현재 해시·출처/보관본 및 대상 장치 런타임 직접 확인은 미확인/미확보입니다.
모델을 다른 보관본에 없다고 단정하거나 새 모델로 임의 교체/재학습하지 않습니다.
실제 모델 검사 opt-in Flutter flag는 `SAFEHUB_LIVE_FASTTEXT_TEST=1`이며 기본은 skip입니다.

기존 생성형 설정은 파일을 덮어쓰지 않고 메모리에서 설명을 꺼 자동 호출을 막습니다.
팀에서 확보한 fastText 모델·endpoint를 확인한 뒤 설정에서 켤 수 있습니다.
[제품 범위](../../docs/integration/product-scope-20261027.md)와
[제출 전 검증 기록](../../docs/integration/submission-audit-20261027.md)을 참고하세요.
