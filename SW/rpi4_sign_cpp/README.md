\# RPi4 Sign Recognition C++ Runtime



Python으로 구현된 Frozen 15-class 수어 인식 엔진을 C++로 포팅한 런타임입니다.



주요 구성은 다음과 같습니다.



\- Frozen Python 15-class classifier의 C++ 포팅

\- Feature V3

\- Temporal Resample

\- C4 SIGN / NO-SIGN Gate

\- One-hand / Two-hand classifier

\- HOT rescue

\- AIRCON / COLD LAST40

\- TEMP overlap rescue

\- MediaPipe Hands C++ 입력

\- C++ Vision JSON / JSONL -> RecordingFrames adapter

\- RuntimeData loader

\- Production `classifyRecording()`



Frozen Python baseline은 수정하지 않습니다.



\---



\## 1. 디렉터리 구조



```text

SW/rpi4\_sign\_cpp/

├─ BUILD.bazel

├─ WORKSPACE

├─ README.md

│

├─ include/

│  ├─ c4\_gate.hpp

│  ├─ feature\_v3.hpp

│  ├─ hand\_input.hpp

│  ├─ jsonl\_frame\_hands.hpp

│  ├─ knn.hpp

│  ├─ mediapipe\_hand\_detector.hpp

│  ├─ onehand\_classifier.hpp

│  ├─ runtime\_data.hpp

│  ├─ sign\_classifier.hpp

│  ├─ sign\_runtime.hpp

│  ├─ sign\_types.hpp

│  ├─ temporal\_resample.hpp

│  └─ twohand\_classifier.hpp

│

├─ src/

│  ├─ c4\_gate.cpp

│  ├─ feature\_v3.cpp

│  ├─ hand\_input.cpp

│  ├─ jsonl\_frame\_hands.cpp

│  ├─ knn.cpp

│  ├─ main.cpp

│  ├─ mediapipe\_hand\_detector.cpp

│  ├─ onehand\_classifier.cpp

│  ├─ runtime\_data.cpp

│  ├─ sign\_classifier.cpp

│  ├─ sign\_runtime.cpp

│  ├─ temporal\_resample.cpp

│  └─ twohand\_classifier.cpp

│

├─ mediapipe\_assets/

│  ├─ hands\_0\_10\_21\_canonical.binarypb

│  ├─ hands\_0\_10\_21\_canonical.pbtxt

│  └─ hands\_0\_10\_21\_info.txt

│

├─ runtime\_data/

│  └─ ...

│

└─ tests/

&#x20;  └─ ...

```



\---



\## 2. 지원 수어 클래스



총 15개 클래스를 사용합니다.



| ID | 수어 |

|---:|---|

| 0 | 에어컨 |

| 1 | 문잠그다 |

| 2 | 꺼지다 |

| 3 | 덥다 |

| 4 | 춥다 |

| 5 | 구조 |

| 6 | 연기 |

| 7 | 아프다 |

| 8 | 괜찮다 |

| 9 | 감사 |

| 10 | 점등 |

| 11 | 소등 |

| 12 | 온도 |

| 13 | 배고프다 |

| 14 | 목마르다 |



분류 결과가 수어가 아니라고 판단되면 `NO-SIGN`을 반환할 수 있습니다.



\---



\## 3. RuntimeData 경로



분류기에 필요한 reference 및 calibration 데이터는 다음 디렉터리에 있습니다.



```text

SW/rpi4\_sign\_cpp/runtime\_data

```



실행할 때 이 디렉터리 자체를 `runtime\_data\_dir` 인자로 전달합니다.



예:



```text

/mnt/c/2026ESWContest\_smart\_mutjaengideul/SW/rpi4\_sign\_cpp/runtime\_data

```



RPi4에서 저장소가 예를 들어 다음 위치에 있다면:



```text

/home/pi/2026ESWContest\_smart\_mutjaengideul

```



RuntimeData 경로는 다음과 같습니다.



```text

/home/pi/2026ESWContest\_smart\_mutjaengideul/SW/rpi4\_sign\_cpp/runtime\_data

```



경로는 고정값이 아니므로 실제 repository 위치에 맞게 지정해야 합니다.



\---



\## 4. Build 환경



현재 x86\_64 개발 환경에서는 다음 조합으로 검증했습니다.



\- WSL2 Ubuntu

\- GCC 14 / G++ 14

\- Bazel / Bazelisk

\- MediaPipe `v0.10.21`

\- OpenCV

\- C++17



현재 개발 환경의 MediaPipe workspace:



```text

\~/mediapipe-v0.10.21

```



`@rpi4\_sign\_cpp` repository가 MediaPipe Bazel workspace에서 접근 가능한 상태를 전제로 합니다.



\---



\## 5. Build



MediaPipe workspace로 이동합니다.



```bash

cd \~/mediapipe-v0.10.21

```



\### Pure sign-recognition runtime



```bash

CC=/usr/bin/gcc-14 \\

CXX=/usr/bin/g++-14 \\

bazelisk build \\

&#x20; --repo\_env=CC=/usr/bin/gcc-14 \\

&#x20; --repo\_env=HERMETIC\_PYTHON\_VERSION=3.12 \\

&#x20; --define MEDIAPIPE\_DISABLE\_GPU=1 \\

&#x20; @rpi4\_sign\_cpp//:sign\_runtime\_stack

```



\### MediaPipe detector smoke test



```bash

CC=/usr/bin/gcc-14 \\

CXX=/usr/bin/g++-14 \\

bazelisk build \\

&#x20; --repo\_env=CC=/usr/bin/gcc-14 \\

&#x20; --repo\_env=HERMETIC\_PYTHON\_VERSION=3.12 \\

&#x20; --define MEDIAPIPE\_DISABLE\_GPU=1 \\

&#x20; @rpi4\_sign\_cpp//:mediapipe\_detector\_smoke

```



\### Video pipeline smoke test



```bash

CC=/usr/bin/gcc-14 \\

CXX=/usr/bin/g++-14 \\

bazelisk build \\

&#x20; --repo\_env=CC=/usr/bin/gcc-14 \\

&#x20; --repo\_env=HERMETIC\_PYTHON\_VERSION=3.12 \\

&#x20; --define MEDIAPIPE\_DISABLE\_GPU=1 \\

&#x20; @rpi4\_sign\_cpp//:video\_pipeline\_smoke

```



\### Production runtime



```bash

CC=/usr/bin/gcc-14 \\

CXX=/usr/bin/g++-14 \\

bazelisk build \\

&#x20; --repo\_env=CC=/usr/bin/gcc-14 \\

&#x20; --repo\_env=HERMETIC\_PYTHON\_VERSION=3.12 \\

&#x20; --define MEDIAPIPE\_DISABLE\_GPU=1 \\

&#x20; @rpi4\_sign\_cpp//:sign\_runtime\_app

```



\### JSONL adapter



```bash

CC=/usr/bin/gcc-14 \\

CXX=/usr/bin/g++-14 \\

bazelisk build \\

&#x20; --repo\_env=CC=/usr/bin/gcc-14 \\

&#x20; --repo\_env=HERMETIC\_PYTHON\_VERSION=3.12 \\

&#x20; --define MEDIAPIPE\_DISABLE\_GPU=1 \\

&#x20; @rpi4\_sign\_cpp//:jsonl\_frame\_hands

```



\### JSONL -> production classifier



```bash

CC=/usr/bin/gcc-14 \\

CXX=/usr/bin/g++-14 \\

bazelisk build \\

&#x20; --repo\_env=CC=/usr/bin/gcc-14 \\

&#x20; --repo\_env=HERMETIC\_PYTHON\_VERSION=3.12 \\

&#x20; --define MEDIAPIPE\_DISABLE\_GPU=1 \\

&#x20; @rpi4\_sign\_cpp//:jsonl\_classifier\_parity

```



\---



\## 6. 실시간 MediaPipe 실행



Production executable:



```text

@rpi4\_sign\_cpp//:sign\_runtime\_app

```



인자는 다음 순서입니다.



```text

sign\_runtime\_app <graph.binarypb> <runtime\_data\_dir> \[camera\_index]

```



예:



```bash

cd \~/mediapipe-v0.10.21



CC=/usr/bin/gcc-14 \\

CXX=/usr/bin/g++-14 \\

bazelisk run \\

&#x20; --repo\_env=CC=/usr/bin/gcc-14 \\

&#x20; --repo\_env=HERMETIC\_PYTHON\_VERSION=3.12 \\

&#x20; --define MEDIAPIPE\_DISABLE\_GPU=1 \\

&#x20; @rpi4\_sign\_cpp//:sign\_runtime\_app -- \\

&#x20; /mnt/c/2026ESWContest\_smart\_mutjaengideul/SW/rpi4\_sign\_cpp/mediapipe\_assets/hands\_0\_10\_21\_canonical.binarypb \\

&#x20; /mnt/c/2026ESWContest\_smart\_mutjaengideul/SW/rpi4\_sign\_cpp/runtime\_data \\

&#x20; 0

```



마지막 `0`은 OpenCV camera index입니다.



실행 후 키 입력:



```text

S : 수어 녹화 시작

E : 녹화 종료 및 추론

Q : 종료

```



`S` 이전 프레임은 MediaPipe에서 처리되지만 `RecordingFrames`에는 저장되지 않습니다.



\---



\## 7. C++ Vision JSONL 입력



`feature/offline-sign-pipeline`의 C++ Vision pipeline에서 생성한 JSON/JSONL을 직접 읽을 수 있습니다.



전체 흐름:



```text

Camera / Video

&#x20;     ↓

C++ Vision

&#x20;     ↓

JSON / JSONL

&#x20;     ↓

jsonl\_frame\_hands

&#x20;     ↓

RecordingFrames

&#x20;     ↓

classifyRecording()

&#x20;     ↓

15-class / NO-SIGN

```



JSONL -> RecordingFrames 변환은 다음 코드에서 담당합니다.



```text

include/jsonl\_frame\_hands.hpp

src/jsonl\_frame\_hands.cpp

```



Python reference implementation:



```text

SW/rpi4\_vision\_atlas/frame\_hands\_adapter.py

```



\---



\## 8. JSONL classifier 실행



입력 형식:



```text

jsonl\_classifier\_parity <input.jsonl> <runtime\_data\_dir>

```



실제 fixture 예:



```bash

cd \~/mediapipe-v0.10.21



CC=/usr/bin/gcc-14 \\

CXX=/usr/bin/g++-14 \\

bazelisk run \\

&#x20; --repo\_env=CC=/usr/bin/gcc-14 \\

&#x20; --repo\_env=HERMETIC\_PYTHON\_VERSION=3.12 \\

&#x20; --define MEDIAPIPE\_DISABLE\_GPU=1 \\

&#x20; @rpi4\_sign\_cpp//:jsonl\_classifier\_parity -- \\

&#x20; /mnt/c/2026ESWContest\_smart\_mutjaengideul/SW/rpi4\_sign\_cpp/tests/fixtures/real\_sign\_video/real\_sign\_01\_vision.jsonl \\

&#x20; /mnt/c/2026ESWContest\_smart\_mutjaengideul/SW/rpi4\_sign\_cpp/runtime\_data

```



검증에 사용한 실제 Vision JSONL에서는 다음 결과를 얻었습니다.



```text

json\_documents  : 81

adapter\_frames  : 42

maximum\_hands   : 1

single\_stabilize: true

stabilized\_hand : RIGHT



valid           : true

final\_id        : -1

stage           : ONEHAND\_C4\_NOSIGN\_REJECT

is\_nosign       : true

source\_mode     : RIGHT\_ONLY

selected\_frames : 42

total\_frames    : 42

left\_frames     : 0

right\_frames    : 42

both\_frames     : 0

both\_ratio      : 0.000000

```



동일 JSONL에 대한 Frozen Python runtime의 결과도:



```text

Frames          : 42

Source mode     : RIGHT\_ONLY

Selected frames : 42

Stage           : ONEHAND\_C4\_NOSIGN\_REJECT

Result          : NO-SIGN

```



으로 동일했습니다.



\---



\## 9. JSONL handedness 처리



Vision JSONL의 handedness를 classifier의 physical LEFT / RIGHT slot으로 변환합니다.



현재 contract:



```text

handedness\_raw > 0.5

&#x20;   → model RIGHT

&#x20;   → physical LEFT



handedness\_raw <= 0.5

&#x20;   → model LEFT

&#x20;   → physical RIGHT

```



Single-hand recording에서는 전체 recording의 `handedness\_raw` median을 사용하여 physical side를 안정화합니다.



Multi-hand recording에서는 frame 단위로 physical side를 결정합니다.



같은 physical slot에 hand가 두 개 이상 들어오는 경우:



```text

higher confidence wins

```



동일 confidence에서는 먼저 관측된 hand를 유지합니다.



landmark는 `(21, 2)` float32 좌표를 사용합니다.



\---



\## 10. Python ↔ C++ parity



Frozen Python implementation과 C++ port 사이에서 다음을 검증했습니다.



```text

102 / 102 frozen outputs match

```



검증 대상:



\- Feature V3

\- Temporal Resample

\- Handshape40

\- C4 SIGN / NO-SIGN

\- One-hand classifier

\- Two-hand classifier

\- HOT rescue

\- AIRCON / COLD LAST40

\- TEMP eligibility

\- TEMP minimum-frame condition

\- TEMP positive / negative branch

\- Production `classifyRecording()`



또한 Python `frame\_hands\_adapter.py`와 C++ JSONL adapter 사이에서:



\- LEFT / RIGHT placement

\- Single-hand median stabilization

\- Empty-frame omission

\- Multi-hand duplicate-side confidence selection

\- Equal-confidence first observation 유지

\- 21x2 landmark float32 bit pattern



을 deterministic fixture로 비교하여 parity를 확인했습니다.



\---



\## 11. RPi4 실행



RPi4에서도 기본 실행 구조는 동일합니다.



예를 들어 repository가:



```text

/home/pi/2026ESWContest\_smart\_mutjaengideul

```



에 있고 MediaPipe workspace가:



```text

/home/pi/mediapipe-v0.10.21

```



에 있다면 runtime 경로는 다음과 같이 사용할 수 있습니다.



```text

/home/pi/2026ESWContest\_smart\_mutjaengideul/SW/rpi4\_sign\_cpp/runtime\_data

```



graph:



```text

/home/pi/2026ESWContest\_smart\_mutjaengideul/SW/rpi4\_sign\_cpp/mediapipe\_assets/hands\_0\_10\_21\_canonical.binarypb

```



실행 형식:



```bash

cd /home/pi/mediapipe-v0.10.21



bazelisk run \\

&#x20; --define MEDIAPIPE\_DISABLE\_GPU=1 \\

&#x20; @rpi4\_sign\_cpp//:sign\_runtime\_app -- \\

&#x20; /home/pi/2026ESWContest\_smart\_mutjaengideul/SW/rpi4\_sign\_cpp/mediapipe\_assets/hands\_0\_10\_21\_canonical.binarypb \\

&#x20; /home/pi/2026ESWContest\_smart\_mutjaengideul/SW/rpi4\_sign\_cpp/runtime\_data \\

&#x20; 0

```



RPi4에서는 실제 설치된 compiler 및 Python toolchain에 맞게 Bazel toolchain 옵션을 설정해야 합니다.



\### 현재 검증 상태



현재 다음 환경에서는 build / runtime 검증을 완료했습니다.



```text

x86\_64 WSL2 Ubuntu

MediaPipe 0.10.21

GCC/G++ 14

```



RPi4 `aarch64` 실제 기기에서의 최종 build/run 검증은 아직 진행하지 않았습니다.



따라서 RPi4에서는 위 실행 구조를 기준으로 실제 기기에서:



1\. Bazel build

2\. MediaPipe graph load

3\. Camera open

4\. Hand detection

5\. RuntimeData load

6\. Sign classification



순서로 최종 확인이 필요합니다.



\---



\## 12. 주요 Bazel targets



| Target | 설명 |

|---|---|

| `sign\_runtime\_stack` | 순수 C++ 수어 인식 엔진 |

| `jsonl\_frame\_hands` | Vision JSON/JSONL -> RecordingFrames |

| `mediapipe\_hand\_detector` | MediaPipe Hands C++ detector |

| `mediapipe\_detector\_smoke` | MediaPipe detector smoke test |

| `video\_pipeline\_smoke` | 영상 입력 전체 pipeline 테스트 |

| `sign\_runtime\_app` | 실시간 production runtime |

| `jsonl\_frame\_hands\_parity` | Python/C++ adapter parity |

| `jsonl\_classifier\_parity` | 동일 JSONL에 대한 production classifier parity |



\---



\## 13. 참고



\- Frozen Python baseline은 수정하지 않습니다.

\- C++ classifier runtime은 JSON library에 직접 의존하지 않습니다.

\- JSON 의존성은 `jsonl\_frame\_hands` adapter에 분리되어 있습니다.

\- MediaPipe 입력과 Vision JSONL 입력은 동일한 `RecordingFrames` / `classifyRecording()` 경로로 연결됩니다.

\- OpenCV Zoo ONNX Vision frontend와 MediaPipe frontend가 동일한 landmark를 생성한다는 의미는 아닙니다.

\- parity 검증은 동일한 `RecordingFrames` 또는 동일한 JSONL을 입력으로 사용하여 Python/C++ classifier 결과를 비교합니다.
