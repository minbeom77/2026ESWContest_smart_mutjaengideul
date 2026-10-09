# ATLAS 음성 재생 권한

실시간 STT 설치·연결은 [기기 내 음성 자막](../../local_stt/README.md)을 참고한다.
STT와 아래 TTS 재생 권한은 서로 다른 경로다.

음성 안내는 ATLAS MediaPlayer 서비스를 사용한다. `meta/appinfo.json`에
`com.atlas.permission.user_consent.mediaplayer`를 선언해야 한다.
ATLAS의 `/etc/permission/atlas_permission.json`에서 이 권한은
`perm_mediaplayer` 그룹과 `Load`, `Play`, `Pause`, `Seek`, `SetVolume`에 연결된다.
권한이 없는 앱에서는 `Load`가 D-Bus `AccessDenied`로 거절될 수 있다.

새 매니페스트를 포함한 앱을 정상 패키지 설치 절차로 배포한다.
`AppManager1.Register`는 실행 중 앱의 등록 응답이므로 매니페스트 갱신에
사용하지 않는다. 설치된 앱이 다음 조회 결과에 재생 권한을 표시하는지 확인한다.

```sh
busctl --system call com.atlas.AppManager1 /com/atlas/AppManager1 \
  com.atlas.AppManager1 GetInfo s com.atlas.app.safehub_app
```

사용자 동의는 ATLAS 권한 요청 화면에서 받는다. 아래 `app_user`에는
앞선 `GetInfo`의 `user` 값(`u0_a...`)을 넣는다. 장치마다 달라지는 값을 고정하지 않는다.

```sh
app_user='<GetInfo의 user 값>'
permission='com.atlas.permission.user_consent.mediaplayer'
busctl --system call com.atlas.PermissionAgent1 /com/atlas/PermissionAgent1 \
  com.atlas.PermissionAgent1 GetUserConsentPermissions as 1 "$app_user"

busctl --system call com.atlas.PermissionAgent1 /com/atlas/PermissionAgent1 \
  com.atlas.PermissionAgent1 CheckUserConsentPermission ss \
  "$app_user" "$permission"
```

위 조회 API는 ATLAS 26.06.0-246에서 확인했다. 이 이미지에는
`RequestUserConsentPermission(s permission)`과 관리자용
`UpdateUserConsentPermission(s uid, s permission, i state)`도 있다.
관리자 API로 동의를 반영할 때는 해당 버전의 상태값 명세와 사용자의 동의를 확인한다.
새 프로세스에 적용된 권한과 실제 음성 재생은 별도로 검증해야 한다.
시스템 D-Bus 정책을 완화하거나 모든 앱에
재생 권한을 부여하는 설정은 필요하지 않다.

## 재생 실패 후 터치가 멈추는 경우

시험 장치의 오디오 플러그인은 `SetSourceUrl`에서 파일 로딩 반환값을 확인하지
않고 완료 콜백을 최대 150초 동안 동기적으로 기다린다. `MediaPlayer.Load`가
권한 오류로 거부되면 이 대기가 입력 처리를 막을 수 있다. Dart의 Future에만
시간 제한을 추가해도 네이티브 대기가 해제되지는 않는다.

현재 `AudioService`는 실제 재생을 요청할 때 플레이어를 생성하고,
Dart 측 재생·정지·종료 응답에 각각 5초 제한을 둔다.
플러그인이 Future 응답을 보내지 않는 경우 호출자는 오류를 처리할 수 있지만,
Flutter 입력 스레드를 막는 동기 호출을 중단하거나 이미 시작한 재생을 취소하지는
않는다. 이 제한을 네이티브 입력 멈춤 문제의 해결로 간주하지 않는다.

권한 수정본을 적용하기 전에는 연결 설정의 TTS 주소를 비워 자동 음성 재생을
중단하고 앱을 다시 실행할 수 있다. 원래 주소를 백업하고 STT 주소는 유지한다.
이 조치는 수어 텍스트 표시와 CSI 수집을 계속하기 위한 임시 조치다.
재생 권한과 실패 시 즉시 반환하는 플러그인을 검증한 뒤 음성 안내를 복구한다.
