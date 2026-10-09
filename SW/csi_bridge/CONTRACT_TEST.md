# Python adapter to Flutter receiver contract test

Run from the repository root, before copying files to the Atlas test workspace:

```bash
python3 SW/csi_bridge/export_contract_fixture.py --out SW/safehub_app/test/fixtures/csi_bridge_contract.json
```

Then run the Flutter test from SW/safehub_app:

```bash
flutter test test/csi_bridge_contract_test.dart --reporter expanded
```

The exporter calls the actual adapter using synthetic accepted model outputs.
It checks repeated and undecided outputs do not create another envelope, and
exports four cases: bedroom fields, bathroom fields, transport retry, and a new
episode after confirmed normal results. UUID generation is mocked only during
fixture export to make regenerating the test file deterministic.

Flutter feeds these envelopes directly into MqttReceiver.handlePayload and
checks queued events and callbacks, including field preservation, location,
duplicate delivery and two different episode IDs. The test does not connect
to MQTT or exercise broker QoS/retain behavior; those settings are checked as
envelope metadata only. It does not exercise the UI, sensors or model accuracy.

Regenerate the fixture whenever adapter behavior changes. Running Flutter
against an old JSON fixture does not test the current Python implementation.
Production label mapping and the normal/rearm policy still require team review.
