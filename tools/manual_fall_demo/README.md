# Manual fall-event controller

Run `python controller.py` with Python/Tk. Enter the Pi5 MQTT host and port.

- Fall sends the existing `safehub/csi/bedroom/event` envelope with `event=fall_detected`.
- Normal sends the same envelope with `event=normal`. It only acknowledges the active operator-created fall; it does not clear a real hazard or assert that a person is safe/present.
- Both use the distinct device value `safehub_manual_demo`, a fresh UUID/timestamp, QoS 1 and retain false. No topic or JSON key is added. Confidence is zero because no model prediction was measured.
- Pi5 retains `origin=csi_demo` and the incident's demonstration badge. Real CSI collection, training and model outputs are unchanged.
- The notebook keeps a local `operator-events.jsonl` journal. Broker acknowledgement proves message acceptance, not physical device movement.

This tests event delivery, UI response, emergency audio and actuator commands. It is not a CSI fall-detection accuracy experiment. Use the real sensor's pipeline for field evaluation.

## Validation · 2026-10-28

- Python loopback protocol/envelope tests: 2 passed.
- Flutter full suite: 291 passed, 1 skipped.
- Pi5 1.5.13 accepted fall and normal events from the notebook. Emergency audio playback requests and Pi4 Uno UART command echoes were observed, including stop commands on normal.
- Existing settings/layout hashes and native runner were preserved during deployment. Prior app/profile snapshot: `/data/safehub-pr7/releases/manual-fall-demo-20261028/before-20261028-044325`.
