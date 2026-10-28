# SafeHub checkpoint · 2026-10-28 04:25 KST

## Current Pi5 application

- App ID: `com.atlas.app.safehub_scenario_pr7`; version `1.5.12`.
- Release: `/data/safehub-pr7/releases/sign-response-20261028`.
- Package SHA256: `fcb635abf072e251d3c016e8d4997b6f5aa886b9472aeb6900f6486b04eda066`.
- AOT SHA256: `eb60ca4950973ec895f816e83d2bc9fe09c770c36b6d4f823c907dcf8c45f43a`.
- Pre-install rollback snapshot: release subdirectory `before-20261028-042027`.

The sign result under the home camera is centered at size 56; its heading remains size 26. The former home CSI tile now persistently displays the latest API disaster notice, region, issue time and polling state. The saved tile identifier remains `csi` to preserve user layouts; separate CSI functionality remains available. A previously issued notice is not proof of an ongoing emergency.

Help signs open help immediately while preserving an existing hazard incident. Camera signs can operate the active scenario-test window without promoting test input into a live hardware alarm. The okay sign invokes the same acknowledgement path as touch, including device stop or delivery of a queued incident. Acknowledgement records that the user responded; it does not assert that a hazard has ended.

## Validation

- Flutter full suite: **289 passed, 1 skipped** on the existing Windows test host.
- On Pi5, controlled MQTT test inputs `구조 → 괜찮다 → 쓰러지다 → 괜찮다` produced help state `true → false → true → false`; active assistance state cleared on each okay response.
- Each help input published existing bedshaker `on` and LED `blink` commands. Each okay input published `off` commands. Pi4 Uno UART command echoes were observed. These are transport/control checks, not a camera recognition accuracy measurement or independent observation of motor movement.
- Pi4 recognition executable remains `/data/safehub/releases/sign-landmarks-v2-20261028/vision_sign_preserve_tracks`, SHA256 `fb67a8fb98dbf8dace1e7ae7ab00a325bebfc4cf55902a0a788256244760d6e2`.

## Private recovery copies

Read-only live snapshots are stored on each Pi under `/data/safehub-checkpoints/20261028-0425/` and copied to the development laptop's `output/checkpoint-20261028-0425/`. They include device executables, settings and relevant Pi4 model/runtime files. They are not full SD-card images; OS and installed services' external runtimes are not all included. Services were left running during capture.

Device profiles can contain credentials and personal data. Recovery archives stay outside Git. Existing deployment snapshots and references are preserved. Recognition limitations and absent real fall-model validation from the preceding review still apply.
