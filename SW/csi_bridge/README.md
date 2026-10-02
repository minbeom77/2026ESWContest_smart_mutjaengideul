# CSI event adapter: offline prototype

This standalone prototype converts accepted `edge_runtime.py` inference results
into an envelope matching the existing CSI MQTT topic and payload fields.
It does not run a model, open a serial port, connect to a broker, publish a
message, or activate a device. Existing CSI and Flutter code is unchanged.

Run with the Python standard library only, from the repository root:

```bash
python3 SW/csi_bridge/test_adapter.py
```

The caller must explicitly supply the room, device identifier, exact fall and
normal label sets, and number of consecutive normal results used to rearm.
Labels in the tests are synthetic fixtures, not agreed production labels.
Two normal results in tests is an experimental policy, not a validated safety
threshold. The normal label set must be reviewed by the CSI team.

An accepted mapped fall produces one envelope with QoS 1, retain false,
priority 9, a UUID and host Unix timestamp. Further fall results are suppressed
until the configured number of consecutive valid normal results. Unknown,
collecting, invalid and undecided results interrupt the normal streak and do
not clear the active episode. Confidence is the selected model score, not
measured real-world recognition accuracy. Timestamp must be host Unix seconds;
CSI device_time is not a Unix timestamp.

This gate counts input results; a future runtime integration must ensure
freshness and avoid counting the same signal window as separate evidence.
State is held only in memory. Recreating the adapter starts a new session.
Creating an envelope does not confirm MQTT delivery: a future publisher must
retain it for retries with the same message_id and define reconnect, expiry,
and acknowledgement behavior before enabling live alerts.

Pending team decisions: production labels and normal/rearm policy, room and
device assignment, inference host, live publishing and actuator integration.
Tests verify conversion and the prototype gate, not CSI accuracy or hardware.
