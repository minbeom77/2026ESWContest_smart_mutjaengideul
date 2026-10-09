import copy
import json
import unittest
import uuid

from adapter import CsiEventAdapter


def result(label="fall_fixture", score=0.92):
    return {"label": label, "scores": {label: score},
            "window_seconds": 3.0, "device_time": 12.5}


class AdapterTests(unittest.TestCase):
    def make(self, **overrides):
        options = dict(room="bedroom", device="fixture_csi_bedroom",
                       fall_labels={"fall_fixture"},
                       normal_labels={"normal_fixture"},
                       normal_confirmations=2)
        options.update(overrides)
        return CsiEventAdapter(**options)

    def feed(self, adapter, value=None):
        return adapter.update(result() if value is None else value,
                              timestamp=1800000000)

    def test_contract_and_host_timestamp(self):
        envelope = self.feed(self.make())
        self.assertEqual(envelope["topic"], "safehub/csi/bedroom/event")
        self.assertEqual(envelope["qos"], 1)
        self.assertIs(envelope["retain"], False)
        payload = envelope["payload"]
        self.assertEqual(set(payload), {"message_id", "device", "event",
                                        "confidence", "priority", "timestamp"})
        self.assertEqual(payload["event"], "fall_detected")
        self.assertEqual(payload["confidence"], 0.92)
        self.assertEqual(payload["priority"], 9)
        self.assertEqual(payload["timestamp"], 1800000000)
        self.assertEqual(str(uuid.UUID(payload["message_id"])),
                         payload["message_id"])
        json.dumps(envelope, allow_nan=False)

    def test_bathroom_route_and_explicit_label_mapping(self):
        adapter = self.make(room="bathroom", fall_labels={"落下_fixture"})
        envelope = self.feed(adapter, result("落下_fixture"))
        self.assertEqual(envelope["topic"], "safehub/csi/bathroom/event")

    def test_repeated_fall_emits_once(self):
        adapter = self.make()
        self.assertIsNotNone(self.feed(adapter))
        for _ in range(20):
            self.assertIsNone(self.feed(adapter))

    def test_confirmed_normal_rearms_and_new_id(self):
        adapter = self.make()
        first = self.feed(adapter)
        self.assertIsNone(self.feed(adapter, result("normal_fixture")))
        self.assertIsNone(self.feed(adapter))
        for _ in range(2):
            self.assertIsNone(self.feed(adapter, result("normal_fixture")))
        second = self.feed(adapter)
        self.assertIsNotNone(second)
        self.assertNotEqual(first["payload"]["message_id"],
                            second["payload"]["message_id"])

    def test_invalid_output_neither_emits_nor_rearms(self):
        invalid = [{"label": "판단 보류", "reason": "새 신호 대기"},
                   {"state": "collecting", "seconds": 1},
                   result("unknown_fixture"), {"label": "fall_fixture"},
                   [], {"label": [], "scores": {}},
                   *[result(score=x) for x in
                     [True, "0.92", None, -0.1, 1.1, float("nan"),
                      float("inf")]]]
        for value in invalid:
            with self.subTest(value=value):
                adapter = self.make()
                self.assertIsNone(adapter.update(value, timestamp=1))
                self.feed(adapter)
                self.feed(adapter, result("normal_fixture"))
                self.assertIsNone(adapter.update(value, timestamp=1))
                self.feed(adapter, result("normal_fixture"))
                self.assertIsNone(self.feed(adapter))

    def test_input_is_not_modified(self):
        value = result()
        original = copy.deepcopy(value)
        self.feed(self.make(), value)
        self.assertEqual(value, original)

    def test_invalid_configuration(self):
        for options in [dict(room="kitchen"), dict(device=" "),
                        dict(fall_labels=set()), dict(normal_labels=set()),
                        dict(normal_labels={"fall_fixture"}),
                        dict(fall_labels={"판단 보류"}),
                        dict(fall_labels="fall_fixture"),
                        dict(normal_confirmations=True),
                        dict(normal_confirmations=0)]:
            with self.subTest(options=options):
                with self.assertRaises(ValueError):
                    self.make(**options)

    def test_invalid_timestamp_does_not_consume_episode(self):
        adapter = self.make()
        for timestamp in [True, -1, 12.5, "1800000000"]:
            with self.assertRaises(ValueError):
                adapter.update(result(), timestamp=timestamp)
        self.assertIsNotNone(self.feed(adapter))


if __name__ == "__main__":
    unittest.main(verbosity=2)
