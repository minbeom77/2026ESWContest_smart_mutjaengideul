# SafeHub Windows 런처

Python CSI 서비스와 Flutter Windows 앱의 시작·종료를 관리하는 WinExe입니다. 실제 모드에서 장비가 없으면 연결 대기로 표시합니다.

## 실행 파일 다운로드

[Windows x64 전달용 ZIP](https://github.com/MyeongJun725/2026ESWContest_smart_mutjaengideul/releases/download/safehub-windows-preview-20261004/SafeHub-Windows-x64-20261004.zip)을 모두 압축 풀고 `SafeHub 시작.exe`를 실행합니다. Python·Visual Studio를 별도로 설치할 필요가 없습니다. 실제 CSI 보드와 수어·카메라 서버는 별도로 연결합니다. 아래 빌드 절차는 소스에서 실행본을 만드는 개발자용 안내입니다.

## 실제 모드로 준비

실제 모드는 `prepare_windows_preview.py --real --build`로 준비합니다. 수동 빌드라면 아래 예제의 `APP_LOCAL_PREVIEW=true`를 `APP_LOCAL_PREVIEW=false`로 바꿉니다. 주소가 없으면 앱을 열고 **연결 설정**에서 MQTT·카메라·음성 서버와 CSI 서비스 주소를 저장할 수 있습니다.

런처 `config.json`에 `"real_only": true`와 `"settings_file": "C:/실제경로/data/connection-settings.json"`을 추가합니다. 설정 파일은 미리 `{}`로 만들어도 됩니다. 런처는 CSI 서비스를 `--real-only`로 실행하고 앱에 설정 파일 경로를 전달합니다. 이 서비스는 모의 신호 요청을 거부하며, 실제 모드 UI도 모의 신호를 허용하는 서비스의 파형과 결과를 사용하지 않습니다.

아래 체험 빌드 절차는 별도 미리보기용으로 유지합니다. 실제 연결 절차와 설정 저장 위치는 [실제 모드 안내](../../docs/wifi-csi/REAL_MODE.md)를 참고하세요.

## Windows 앱 준비

필요한 도구는 Python 3.12, Flutter SDK, Visual Studio의 **Desktop development with C++** 구성 요소와 Windows SDK입니다. 이 저장소의 기본 앱은 ATLAS용이므로 Windows에서는 별도 호스트 복사본을 만듭니다. 원래 `SW/safehub_app/pubspec.yaml`과 노트북 WifiSensing 앱·데이터는 수정하지 않습니다.

아래 명령은 저장소 루트에서 PowerShell로 실행합니다. Flutter 경로는 설치한 위치로 바꾸고 출력 폴더는 **아직 존재하지 않는 새 경로**를 선택합니다.

```powershell
$flutterExe = 'C:/실제경로/flutter/bin/flutter.bat'
$previewHost = Join-Path $env:LOCALAPPDATA 'SafeHub/windows-preview'
$audioPatch = (Resolve-Path SW/windows_preview/patch_windows_audio.py).Path
python SW/windows_preview/prepare_windows_preview.py --flutter-path $flutterExe --output-dir $previewHost --check-only
python SW/windows_preview/prepare_windows_preview.py --flutter-path $flutterExe --output-dir $previewHost
Set-Location $previewHost
& $flutterExe pub get
python $audioPatch --host-dir $previewHost
& $flutterExe pub get
& $flutterExe build windows --release --dart-define=APP_LOCAL_PREVIEW=true
```

준비 스크립트는 `flutter create --platforms=windows --no-pub`로 호스트를 생성하고, 실제 `lib`/`assets`를 복사한 뒤 호스트의 pubspec에서 `audioplayers_atlas`와 `record_atlas`만 제외합니다. Windows용 오디오·녹음 플러그인은 유지됩니다. 표준 라이브러리만 사용하며 기존 출력 폴더는 덮어쓰지 않습니다. 준비 실패 시 남은 폴더를 자동 삭제하지 않습니다.

처음부터 준비와 빌드까지 연속 실행하려면 두 번째 명령에 `--build`를 추가합니다. `--build`는 최초 `pub get` → 아래 Windows 오디오 소유권 패치 → `pub get` → 빌드를 실행합니다. 기본 실행은 소스 준비만 하며, `--check-only`는 경로·입력 파일·pubspec만 검사합니다. 사전 검사 성공은 의존성 설치나 컴파일 성공을 뜻하지 않습니다.

일반적인 빌드 결과는 호스트의 `build/windows/x64/runner/Release`입니다. Flutter 버전에 따라 위치가 달라지면 빌드 완료 메시지를 따릅니다. 실행파일 하나만 복사하지 말고 **Release 폴더 전체**를 배포 폴더의 `app`으로 복사해야 합니다. DLL과 `data` 폴더가 함께 있어야 실행됩니다.

### Windows 오디오 종료 오류 패치

`audioplayers_windows 4.3.0`의 전역 이벤트 처리기는 static `unique_ptr`와 Flutter messenger의 handler가 동일 객체의 소유권을 동시에 갖고 있었다. 엔진이 처리기를 삭제한 후 DLL의 정적 소멸자가 다시 삭제하면 access violation이 발생할 수 있다. [소유권 패치](audioplayers_windows-4.3.0-ownership.patch)는 전역 참조를 비소유 포인터로 두고 Flutter handler에만 소유권을 이전한다. 오디오 API·메시지·플러그인 버전·ATLAS 소스는 바꾸지 않는다.

`patch_windows_audio.py`는 최초 `pub get`의 `.dart_tool/package_config.json`에서 원본 패키지를 찾는다. 호스트의 `vendor/audioplayers_windows`로 복사하고, 그 복사본에만 패치를 적용한다. 독립 path 패키지로 사용하도록 복사본의 `resolution: workspace` 메타데이터를 제거한다. 호스트 `pubspec_overrides.yaml`은 이 경로만 참조한다. Pub 캐시 원본은 수정하지 않는다. 기존 사용자 overrides나 변경된 vendor 파일이 있으면 덮어쓰지 않고 중단한다. 복사본의 `SAFEHUB_PATCH.json`에 파일 해시와 패치 정보를 남긴다. 다른 버전은 검토되지 않았으므로 자동 패치하지 않는다.

```powershell
# 기존 Windows 호스트에 적용할 때; 현재 실행 중인 앱에는 영향을 주지 않습니다.
python SW/windows_preview/patch_windows_audio.py --host-dir $previewHost --check-only
python SW/windows_preview/patch_windows_audio.py --host-dir $previewHost
Set-Location $previewHost
& $flutterExe pub get
# 이후 일반 빌드 또는 아래 VS 2026 수동 빌드를 다시 실행합니다.
```

기존 호스트가 junction으로 플러그인을 연결했다면, `pub get` 후 `.flutter-plugins-dependencies`의 Windows `audioplayers_windows.path`와 `windows/flutter/ephemeral/.plugin_symlinks/audioplayers_windows`의 실제 대상이 모두 이 호스트의 `vendor/audioplayers_windows`인지 확인한다. 이전 Pub 캐시를 가리키는 junction이 남아 있으면 패치가 빌드되지 않으므로, 호스트 내부 연결을 확인하기 전에는 배포하지 않는다. 패치 스크립트는 기존 junction을 삭제하거나 교체하지 않는다.

원본 패키지는 Blue Fire의 MIT 라이선스이며 원본 고지와 `LICENSE`를 vendor 복사본에 유지한다. [라이선스](licenses/audioplayers_windows-MIT.txt)를 Windows 배포본에도 포함한다. 줄바꿈을 LF로 정규화한 `windows/audioplayers_windows_plugin.cpp` SHA256은 다음과 같다.

| 파일 | SHA256 |
|---|---|
| 원본 4.3.0 | `7d30e6359d6275a64323718d85eb55c1c79cc07da85511ef03f5439f08cc34d2` |
| 패치 결과 | `0b6020adeed64d1d7fe4aa0de3407c957d433fd86018c9a4cad99e845ede204c` |
| 원본 MIT LICENSE | `d6c0bdbc83e6bb5f02eed5caf25e6edf174cb56d0ecd6fe19a2cd05b62bbda41` |

2026-10-04 Windows Application Error/WER에서 이전 체험 앱과 실제 앱 모두 `audioplayers_windows_plugin.dll`, 예외 `0xc0000005`를 기록했다. 실제 앱 기록은 01:15:59, PID 56768, 오프셋 `0x6da8`이다. 해당 DLL과 Release OBJ의 역어셈블리를 비교하면 `EventStreamHandler<EncodableValue>`의 deleting destructor `+0x18`에 해당한다. 체험 앱의 `0x1d38c`는 `globalEvents`의 `atexit` 소멸자 `+0x0c`와 명령 바이트가 일치한다. PDB와 보존된 crash dump는 없어 호출 스택 전체는 확인하지 못했다. 패치 전 새 실행 1회는 정상 종료했으므로 모든 종료에 발생하는 오류나 60초 실행 타이머로 단정하지 않는다. 증거는 비결정적인 종료 시 이중 삭제와 일치한다.

전역 비소유 참조는 등록된 동기 method handler의 `OnGlobalLog`/`emitError`에서만 사용한다. 개별 재생 스레드는 이 전역 참조를 사용하지 않는다. messenger가 handler를 해제한 뒤 새 호출을 받는 경로는 현재 단일 엔진 Windows 호스트에 없으며, 재등록 시 참조는 새 handler로 교체된다. 다중 엔진 지원이나 다른 native 오디오 수명 문제까지 검증한 패치는 아니다. `AudioService`를 지연 생성하는 것만으로는 플러그인 등록 단계의 이중 소유권이 없어지지 않는다.

스크립트의 원본 보존·해시 검사·재실행·사용자 수정 거부 검사는 `python SW/windows_preview/test_patch_windows_audio.py`로 실행한다. GUI의 반복 열기/닫기와 음성 재생 검증은 별도로 필요하다.

### Flutter 3.29.3과 VS 2026을 함께 쓰는 경우

이 노트북에서 확인한 조합은 Flutter 3.29.3 / VS 2026 / Windows SDK 10.0.26100.0입니다. 이 Flutter 버전은 VS 2026 CMake generator를 직접 선택하지 못하므로 일반 빌드가 generator 선택 오류로 끝났습니다. 최신 Flutter에서 정상 빌드되면 아래 수동 절차는 필요하지 않습니다.

1. 위의 `flutter pub get`과 preview 옵션을 포함한 `flutter build windows`를 한 번 실행하여 `windows/flutter/ephemeral/generated_config.cmake`를 생성합니다. 다른 오류가 있으면 먼저 해결합니다.
2. MSVC 19.50 이상에서 오디오 플러그인의 legacy coroutine 폐기 안내가 오류로 처리된다면, **생성된 호스트의** `windows/CMakeLists.txt`에서 `include(flutter/generated_plugins.cmake)` 다음에 아래를 추가합니다. SDK와 Pub 캐시 소스는 수정하지 않습니다.

```cmake
if(MSVC_VERSION GREATER_EQUAL 1950 AND TARGET audioplayers_windows_plugin)
  target_compile_definitions(audioplayers_windows_plugin PRIVATE
    _SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)
endif()
```

3. 호스트 폴더에서 설치된 VS의 CMake로 새 빌드 디렉터리를 사용합니다. `$cmakeExe`는 자신의 VS 설치 경로로 바꿉니다.

```powershell
$cmakeExe = 'C:/Program Files/Microsoft Visual Studio/18/Insiders/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
& $cmakeExe -S windows -B build/windows/vs18 -G 'Visual Studio 18 2026' -A x64 -DFLUTTER_TARGET_PLATFORM=windows-x64
& $cmakeExe --build build/windows/vs18 --config Release --target INSTALL
```

이 경로의 결과는 `build/windows/vs18/runner/Release`입니다. `generated_config.cmake`가 이전 실행에서 남은 파일이면 현재 호스트 및 `APP_LOCAL_PREVIEW=true` 설정인지 먼저 확인합니다.

플러그인 심볼릭 링크 권한 오류가 나는 Windows에서는 개발자 모드를 허용한 환경에서 다시 실행할 수 있습니다. 이 노트북에서는 시스템 설정을 바꾸지 않고, `flutter pub get`이 생성한 `.flutter-plugins-dependencies`의 Windows 플러그인 경로로 디렉터리 junction을 만든 뒤 `pub get`을 다시 실행했습니다. 같은 방법이 필요하면 **새 호스트 폴더에서만** 다음을 실행합니다. 기존 경로는 교체하지 않습니다.

```powershell
$windowsPlugins = (Get-Content .flutter-plugins-dependencies -Raw | ConvertFrom-Json).plugins.windows
$pluginLinks = Join-Path (Get-Location) 'windows/flutter/ephemeral/.plugin_symlinks'
New-Item -ItemType Directory -Path $pluginLinks -Force | Out-Null
foreach ($plugin in $windowsPlugins) {
  $pluginLink = Join-Path $pluginLinks $plugin.name
  if (-not (Test-Path -LiteralPath $pluginLink)) {
    New-Item -ItemType Junction -Path $pluginLink -Value $plugin.path | Out-Null
  }
}
& $flutterExe pub get
```

## Python CSI 서비스 준비

기존 검증 환경이 없으면 별도 Python 3.12 가상환경에서 설치합니다. 아래는 저장소 루트에서 실행하는 설치 절차이며, **깨끗한 PC에서의 전체 재설치 검증을 완료했다는 의미는 아닙니다.** CPU PyTorch를 먼저 설치하여 노트북 검사 환경의 `2.7.1+cpu`와 맞춥니다. 다른 Python/ARM64 조합은 별도 검증 대상입니다.

```powershell
py -3.12 -m venv .venv-safehub
& .venv-safehub/Scripts/python.exe -m pip install --index-url https://download.pytorch.org/whl/cpu torch==2.7.1
& .venv-safehub/Scripts/python.exe -m pip install -r SW/wifi_sensing/requirements.txt
& .venv-safehub/Scripts/python.exe -m pip check
& .venv-safehub/Scripts/python.exe SW/wifi_sensing/tests/test_bridge.py
```

런처 설정의 `python_site_packages`에는 이 가상환경의 `Lib/site-packages`를 지정합니다. `python_exe`에는 아래 명령이 출력하는 실제 Python 실행파일 경로를 넣습니다. 가상환경의 실행 리디렉터 대신 본 실행파일을 사용하면 런처가 서비스 프로세스를 직접 관리할 수 있습니다.

```powershell
& .venv-safehub/Scripts/python.exe -c "import sys; print(sys._base_executable)"
```

## 런처 빌드

`SW/windows_preview` 폴더에서 다음 명령을 실행합니다.

```powershell
& "$env:WINDIR/Microsoft.NET/Framework64/v4.0.30319/csc.exe" /nologo /target:winexe /platform:x64 /optimize+ /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll /out:SafeHubLauncher.exe Launcher.cs
```

## 로컬 설정

`SafeHubLauncher.exe` 옆에 `config.json`을 만듭니다. 전체 경로 또는 실행기 폴더 기준 상대 경로를 사용할 수 있습니다. 아래는 형식 예시이며 그대로 실행하는 설정이 아닙니다. 사용자별 실제 설정 파일은 공개 소스에 포함하지 않습니다.

```json
{
  "python_exe": "C:/실제경로/python.exe",
  "python_site_packages": "C:/실제경로/venv/Lib/site-packages",
  "bridge_script": "C:/실제경로/SW/wifi_sensing/bridge.py",
  "data_dir": "C:/실제경로/SafeHubData/csi",
  "app_exe": "C:/실제경로/app/safehub_app.exe",
  "port": 8765
}
```

Flutter 앱은 `--dart-define=APP_LOCAL_PREVIEW=true`로 빌드합니다. 기본 CSI 주소는 `http://127.0.0.1:8765`이며, 포트를 바꾸는 경우 앱의 `CSI_SERVICE_URL` 빌드 설정도 일치시켜야 합니다. 기존 WifiSensing 데이터와 분리된 새 `data_dir`을 지정합니다.

## 실행 동작

1. 설치 폴더별 단일 실행 mutex와 필요한 파일을 검사합니다. 같은 폴더에서 이미 실행 중이거나 지정 포트가 사용 중이면 안내 후 종료합니다. 기존 프로세스에는 연결하거나 종료 명령을 보내지 않습니다.
2. 지정 Python을 `PYTHONPATH=python_site_packages`로 설정하고 `bridge.py --port 8765 --allow-training --data-dir ...`를 숨김 실행합니다.
3. `/state`에서 CSI 상태 구조가 확인될 때까지 기본 45초 기다리고 Flutter 앱을 표시합니다. `startup_timeout_seconds`는 15~300초로 지정할 수 있으며 전달본은 첫 로딩을 위해 180초를 사용합니다. 준비 창을 닫으면 시작을 취소합니다.
4. 사용자가 앱을 닫으면 이번에 시작한 CSI 서비스와 자식 프로세스를 정리합니다. Windows Job Object로 런처가 비정상 종료되어도 이 실행의 자식만 정리하도록 합니다.
5. 실행 로그와 CSI 표준 출력·오류를 런처 옆 `logs` 폴더에 남깁니다. 기존 로그는 덮어쓰지 않습니다.

체험 빌드의 모의 신호는 앱에서 **와이파이 센싱 → 장비 없이 모의 신호**를 직접 눌러 시작합니다. 실제 모드에는 이 버튼이 없습니다.

## 실행 전 검사

```powershell
$process = Start-Process -FilePath ./SafeHubLauncher.exe -ArgumentList '--check' -WindowStyle Hidden -Wait -PassThru
$process.ExitCode
```

`--check`는 설정·파일·포트만 확인하며 서비스와 앱을 시작하지 않고 오류 대화상자도 표시하지 않습니다. 결과는 `logs`에 기록합니다. 종료 코드 0은 검사 통과, 1은 설정/포트 등 오류, 2는 이미 실행 중입니다. 일반 실행에서 시작 취소는 130입니다. 검사 통과만으로 Python 의존성이나 실제 앱 실행까지 검증된 것은 아닙니다.

위 로컬 구성은 이 노트북의 Python 환경을 사용합니다. 다른 PC로 옮길 때는 아래 전달본 구성을 사용합니다. 라즈베리파이 설치 프로그램은 아닙니다.

## 다른 Windows PC용 전달본

`package_portable.py`는 검증한 Windows Release, Python 3.12 본 실행파일·표준 라이브러리, CSI requirements와 설치된 전이 의존성을 새 폴더에 복사합니다. Qt·개발 도구·원본 사용자의 site-packages 전체·측정 기록·모델·설정은 복사하지 않습니다. CPU PyTorch로 PC 학습을 지원합니다.

```powershell
python SW/windows_preview/package_portable.py --build C:/검증된/Release --crt C:/허용된/x64/Microsoft.VC145.CRT --output C:/새로운/SafeHub-전달용
```

출력은 저장소 밖의 새 폴더여야 합니다. 빌드·Python·C++ 런타임의 배포 권한과 라이선스를 확인하고 검증된 파일을 사용합니다. DLL은 app과 python 폴더에 함께 배포합니다. Python의 `_pth`로 검색 경로를 지정하고 전달본의 `isolated_python=true`는 `-I` 인수로 사용자 site-packages·외부 Python 환경을 제외합니다. 기존 로컬 환경 구성에는 이 옵션을 적용하지 않습니다. UTF-8도 실행 인수로 적용합니다. 테스트 자료·C++ 정적 라이브러리는 제외하고 Python 바이트코드를 미리 생성합니다. 런처 설정은 상대 경로이고 기본 포트는 8768입니다. 새 연결 설정에는 같은 포트의 로컬 CSI 주소만 넣어 UI의 빌드 기본값과 관계없이 전달본 서비스에 연결합니다.

폴더 전체를 ZIP으로 전달하고 **모두 압축 풀기 → SafeHub 시작.exe**로 실행합니다. Windows 10/11 x64용이며 Python·Visual Studio를 별도로 설치할 필요가 없습니다. 연결 주소·기록은 새 data 폴더에서 시작합니다. 실제 CSI 수신 보드와 수어·카메라 서버는 별도 장비/서비스로 준비해야 합니다. 이 패키지는 Pi/ATLAS·macOS 실행본이 아닙니다.

재현 검사에서는 다른 한글·공백 경로에 압축을 풀고, 외부 Python 환경변수를 오염시킨 상태에서 내장 Python의 경로·전처리·학습·추론과 실제 모드 시작을 확인합니다. 동일 PC의 이동 검사는 깨끗한 별도 PC에서 실물 동작을 확인한 결과와 구분합니다.
