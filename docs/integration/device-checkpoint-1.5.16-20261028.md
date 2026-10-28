# Pi5 1.5.16 device-source checkpoint · 2026-10-28

This branch preserves the sources used for the current device UI. It follows the device checkpoint `a1a4d1d`, without replacing it with the separate submission-candidate UI.

PR #14 was merged through PR #15. At publication, team `develop` is `50e1b4d` and contains additional preview, audio and integration changes. This checkpoint is a separate Draft PR for comparison/integration; it must not overwrite those changes wholesale. The current device was not upgraded to that develop tree by this upload.

## Included behavior

- A notebook controller sends distinct operator-origin fall/normal events over the existing MQTT topic and JSON keys. Normal clears only its own active demonstration incident. It does not report a model probability or change CSI training data. The incident retains a demonstration marker.
- Help signs open the help flow; okay signs use the same acknowledgement/device-stop path as touch. Test-window responses remain isolated from real sensor data.
- A collapse sign defaults to another person, then starts one seven-second deadline. Okay, explicit reaction/target selection, cancellation, preparation and disposal cancel the deadline. Repeated signs do not reset it.
- Without a response, the app prepares an unsent report with reaction/consciousness **unconfirmed**, then opens the sign-video demonstration screen automatically. Camera video and subsequent sign text stay visible.
- The 119 video view is a local demonstration. No 119 call, interpreter session, emergency dispatch or report transmission is implemented. Operator-entered demonstration addresses and live user settings are excluded from source control.

## Device artifact identity

| Item | Value |
|---|---|
| Pi5 app ID | `com.atlas.app.safehub_scenario_pr7` |
| Package version | `1.5.16` |
| Release directory | `/data/safehub-pr7/releases/sign-auto-video-20261028` |
| Package SHA256 | `031c65518d1a0b5b46ac867fb29296c0587e70abbad7306b971cd7fac1f1a16e` |
| AOT SHA256 | `f81096a093ea9ceee544798f1baf40b2724188775be96e972973ee471fbdd528` |
| Pre-install backup | release subdirectory `before-20261028-054307` |

Package versioning was performed by the local ATLAS packaging helper; `pubspec.yaml` still contains its prior project version. The existing native runner was reused. These sources are not a new cross-built Pi4 executable or an instruction to replace unrelated deployments. See the accompanying source hash manifest for the Dart input snapshot.

## Verification

- Full Flutter suite on the existing Windows host / Flutter 3.27.4: 296 passed, 1 skipped.
- Controller protocol/envelope checks: 2 passed, including real loopback TCP/PUBACK framing, non-retained publishing and explicit operator origin.
- Seven-second transitions, late-arriving collapse signs, repeated signs, okay cancellation, manual responses, video view and live sign updates are covered by widget tests. They are not recognition-accuracy measurements.
- Pi5 installation reported Running, the expected AOT hash, unchanged native runner and four preserved profile JSON files.
- Earlier notebook fall/normal inputs reached Pi5; emergency playback requests and Uno UART echoes were observed. Physical actuator movement and new camera gestures were not independently measured in this publication step.

No credentials, recordings, operator journals, device archives, screenshots or installed model files are uploaded. Real fall detection accuracy and WORD1229 recognition limitations remain as previously documented.
