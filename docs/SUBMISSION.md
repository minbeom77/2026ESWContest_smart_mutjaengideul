# 제출과 장치 소스 대조

통합 기준은 **develop**, 최종 제출 대상은 **main**이다. main 병합 전 PR에서 변경·Checks·장치
미확인 항목을 확인한다. [최종 통합 기록](integration/submission-ready-20261028.md)을 기준으로 한다.

## GitHub에 포함된 구성

- 현재 UI 원본은 `SW/safehub_scenario` 한 곳이다. 옛 `SW/safehub_app`과 거실 배경 UI는 제거했다.
  버건디/아이보리 배치, 도움 요청 버튼, 카메라 아래 큰 수어 결과를 유지한다.
- #11의 #10(#8/#7 포함)·#9·#6 선택 안정화에 #14·#18 장치 후속 소스, #12/#13의 필요한
  음성·최소 UI, #19 README와 수어 전달/종료 회귀 보완을 통합한다. #8을 중복 병합하거나 #6의 옛 UI 전체를 가져오지 않는다.
- YAMNet/STT 공유 PCM, 긴급 내장 음성, TTS, CSI 낙상 정책, Pi4 추적/정지 지지 손/관절 표시 소스가 있다.
- SDK·설치 바이너리·실제 모델/참조·개인 설정은 별도다. Uno `.ino`/현재 펌웨어, 최종 장치
  빌드 자료는 미확인/미확보이며 자동으로 통합 완료로 표시하지 않는다.

## 실행 중인 라즈베리파이와 비교

원래 경로의 ELF 해시만 보면 안 된다. #14 보고에서는 원래 파일을 남기고 wrapper가 새 release
ELF를 실행했다. `/proc/PID/exe`와 해당 소스 archive/빌드 manifest를 대조한다.

클라우드에서 사설망에 접근하지 못하면 **저장소를 받은 Windows PC의 저장소 루트**에서 실행한다.
`<PI4-IP>`와 `<PI5-IP>`를 현재 주소로 바꾼다. 서비스·카메라·MQTT·펌웨어를 조작하지 않고 해시와
경로만 읽는다. 결과는 저장소 밖 사용자 폴더에 저장한다.

```powershell
Get-Content -Raw .\tools\collect_device_inventory.sh | ssh root@<PI4-IP> "tr -d '\r' | sh -s -- pi4" | Set-Content -Encoding utf8 "$env:USERPROFILE\safehub-pi4-inventory.tsv"
Get-Content -Raw .\tools\collect_device_inventory.sh | ssh root@<PI5-IP> "tr -d '\r' | sh -s -- pi5" | Set-Content -Encoding utf8 "$env:USERPROFILE\safehub-pi5-inventory.tsv"
python .\tools\compare_device_inventory.py "$env:USERPROFILE\safehub-pi4-inventory.tsv" > "$env:USERPROFILE\safehub-pi4-compare.json"
python .\tools\compare_device_inventory.py "$env:USERPROFILE\safehub-pi5-inventory.tsv" > "$env:USERPROFILE\safehub-pi5-compare.json"
```

명시된 배치 경로·읽을 수 있는 파일만 조사한다. 일치 파일이 있어도 실행 중 로드 여부까지 증명하지
않는다. 미일치 파일은 검토 대상이지 자동 삭제 대상이 아니다. ELF/kernel을 소스 SHA로 역변환하지
않으며 장치 전체 일치는 미확인으로 남긴다. Pi5 설치 manifest/kernel/IPK와 소스/빌드 archive는
별도로 확보해 대조한다. 비밀번호·설정 원문·모델·녹음·전체 백업을 공개 Git에 올리지 않는다.

| 남은 항목 | 확인할 것 |
|---|---|
| Pi4 | 현재 `/proc/PID/exe` 해시, wrapper, 최종 release `status.json`, 소스/도구 archive. #14 최종 경로는 `sign-landmarks-v2-20261028/vision_sign_preserve_tracks`로 보고됨 |
| Pi5 | 현재 manifest/kernel/IPK 해시·빌드 출처. #14의 1.5.7은 #14, 1.5.16은 #18 작성자 보고이고 이번 1.6.0 소스 후보의 설치를 뜻하지 않음 |
| 수어 | ONNX 두 모델·active targets·runtime data 해시/출처. 아프다/괜찮다/쓰러지다/점등·소등 반복, 무동작 오탐·양손 관측 기록 |
| 음향 | YAMNet/embedding 모델·선택 siren/bell 참조와 서비스 옵션. 다른 소리·거리·소음 조건 오탐/미탐은 미검증 |
| CSI | 낙상/일상 학습 모델. #14 인수인계 당시 Pi5에 낙상 라벨 모델이 없다고 보고됨 |
| Uno | 최종 `.ino`/펌웨어·핀/시리얼 계약과 실제 LED·진동·팬·커튼 동작 |
| 전체 | 재부팅, MQTT 끊김/복구, 실제 마이크→UI→장치와 물리 출력 |

## main 제출 순서

1. develop 통합 PR의 Checks와 제한을 확인한다. 장치 일치 미확인을 “운영 장치 완전 재현”으로 쓰지 않는다.
2. main PR의 **base=main / compare=develop**과 diff를 확인한다. 병합 전 양쪽 SHA와 기존 main 백업을 남긴다.
3. 사용자가 최종 검토 후 main PR을 병합한다. main/develop 소스 tree 일치와 제출 SHA/URL을 기록한다.
   main 반영은 사용자의 명시 지시에 따라 진행하며 장치 배포와 구분한다.
4. 제출 안내는 main으로 통일한다. 다른 브랜치·닫힌 PR·Git 이력은 main의 파일에 섞이지 않는다.
   정리를 위해 삭제하거나 이력을 다시 쓰지 않는다. 복구 백업은 보존한다.

필수 수어 참조·diagnostics·라이선스·검사·문서를 용량이나 오래된 이름만 보고 지우지 않는다.
LG 비공개 SDK/문서의 공개 권한을 runner 소스의 라이선스만으로 추정하지 않는다.

## 이후 수정

최신 develop에서 기능 브랜치→수정·관련 검사→develop PR→Checks→병합 순서로 진행한다.
main 제출 PR의 diff와 Checks도 갱신한다. 장치 적용은 별도로 실행본·개인 설정·모델/참조를
백업하고 빌드 SHA/옵션·산출물 해시를 기록한 다음 진행한다.

```sh
python tools/audit_product_sources.py
python -m unittest discover -s tools -p 'test_*.py' -v
python SW/safehub_scenario/tool/run_ui_preview.py --check-only
```

전체 명령은 [source-checks.yml](../.github/workflows/source-checks.yml)에 있다.
Flutter 3.35.7 / Dart 3.9.2와 host lock을 사용한다. 과거 허브 `test_*.py`에는 실제 발행 코드가
섞일 수 있으므로 [선별된 차단 runner](../tools/run_hub_checks.py)만 실행한다.


## 2026-10-28 후속 통합

최신 검증 기록은 [final-submission-20261028](integration/final-submission-20261028.md),
외부 실행 자료는 [REPRODUCIBILITY](REPRODUCIBILITY.md)를 우선한다.
#18의 수어 알림 전달·응답 정리, 재난 상시 카드, 명시적 시연 입력, 미전송 영상 신고 흐름과
#19 문서를 통합한다. 기존 미리보기/오디오/최소 UI 보완도 유지한다.
수어로 도움 화면을 여는 것과 LED·진동 명령 전달이 이어지는지는 별도 회귀 검사로 확인한다.
화면의 괜찮아요는 해당 도움 사건의 알림 정리와 연결하되, 도움 취소가 동시에 열린 화재/재난을
무조건 확인 처리하지 않도록 구분한다. 실제 신고·통역사 연결은 구현하지 않았다.
